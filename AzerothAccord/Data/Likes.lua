-- Likes: votes, the notary and the ledger (SPEC-07 §2, LIKE-01..LIKE-09, ADR 0007). Lua 5.1.
--
-- One like per ACCOUNT to each other account, irreversible and anonymous (owner decisions D1, D2):
--
--   Voter     Likes:Give(guid) puts the vote in a queue kept on this computer for the guild (GuildKey:Data().likes,
--             account-wide: every character of the account shares it). The queue is delivered by WHISPER to one online
--             officer, the notary (Notary:Choose), never on GUILD (LIKE-05); with no officer online the vote waits and
--             the interface shows it as pending. The notary answers with a receipt (LEDGER by WHISPER): "ok" or "dup"
--             (already given) mark the target account as liked here and the button disappears from all its characters;
--             "self", "target" and "conflict" drop the vote; "nosalt", "unknown" and "rate" try the next officer later.
--   Notary    an officer holding the guild salt (Data/Notary.lua) checks the vote (LIKE-06): the sender is in its roster,
--             its account is known (its own `accounts` record carries the token), the target is a guild member and not
--             a character of the voter's account, no character outside the voter's account publishes the same token
--             ("conflict": the token is public and could be copied, and a copy would share the pseudonym), and the voter
--             has not liked that account yet. It then writes ONE ledger
--             entry with Store:Put("likes", ...), which the sync sends to the guild on GUILD like any record (REC):
--               { pseudonym, tag, target, day }   author = the notary
--               pseudonym = the first 32 hex digits (128 bits) of HMAC-SHA256(salt, voter's account token)
--               tag       = the first 16 hex digits of HMAC-SHA256(salt, "char:" .. the voting character's GUID)
--             The double-vote check compares the pseudonyms of every token of the voter's characters and the tags of
--             every character of the voter's account, under EVERY salt of the ring, with the entries that target any
--             character of the target's account: a vote given again after a new account token (a new computer), from an
--             alt, or under another officer's salt is still refused.
--   Ledger    append-only (LIKE-03): Net/Store.lua accepts a `likes` record only from an officer (NET-12), only with
--             rev 1, only with an id derived from its content ("<first 16 digits of the pseudonym>:<target GUID>"), and
--             never replaces one it holds. The author does not have to be an officer still: an entry stays valid after
--             its notary left the guild or was demoted (LIKE-07).
--   Totals    the total of an account = the number of DISTINCT pseudonyms among the entries whose target is one of its
--             characters (proved ones: hints from public notes are left out). Linking alts later merges their likes
--             without counting a voter twice. A member without the addon receives likes on the character (LIKE-09).
-- Bus: LIKES_UPDATED() when totals or the own queue changed; LIKE_RESULT(targetGUID, result) when a receipt arrived.
local ADDON_NAME, ns = ...
ns = ns or {}
local Likes = {}
ns.Likes, ns.modules = Likes, ns.modules or {}
ns.modules.Likes = Likes

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, random, sort = math.floor, math.random, table.sort

Likes.AUTO = true                 -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Likes.TICK = 15                   -- seconds between two delivery passes while votes wait
Likes.WAIT_RECEIPT = 45           -- seconds without a receipt before the next officer is tried
Likes.RETRY_SILENT = 300          -- an officer that did not answer is tried again after this long
Likes.RETRY_SOON = 60             -- an officer that could not notarize yet (no salt yet, voter not known yet, rate)
Likes.VOTE_TTL = 40               -- a VOTE that could not leave in time is dropped (never saved for the next login)
Likes.RATE = { 20, 60 }           -- a notary answers at most 20 votes per sender per minute
Likes.PSEUDONYM_HEX = 32
Likes.TAG_HEX = 16
Likes.ID_HEX = 16
Likes.GUID_PATTERN = "^Player%-%d+%-%x+$"

Likes.RESULTS = { ok = true, dup = true, self = true, target = true, conflict = true, unknown = true, nosalt = true, rate = true }

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function isGUID(v) return type(v) == "string" and #v <= 40 and v:find(Likes.GUID_PATTERN) ~= nil end
local function myGUID() return compat() and compat().Player.GUID() or nil end

local state
local function resetState()
	if state and state.ticker then state.ticker:Cancel() end
	state = {
		inflight = {},       -- target GUID -> { name, at, nonce }
		tried = {},          -- target GUID -> { [officer name] = time until which it is skipped }
		answered = {},       -- sender name -> { start, count } (notary rate)
		index = nil,         -- target GUID -> { [pseudonym] = true }
		totals = {},         -- guid -> total (cache)
		ticker = nil,
		stats = { given = 0, sent = 0, receipts = 0, notarized = 0, refused = 0, votesHeard = 0, ignored = 0 },
	}
	Likes.state = state
end
resetState()

---------------------------------------------------------------------------------------------------------------------
-- The ledger record (checked by Net/Store.lua for every entry that arrives)
---------------------------------------------------------------------------------------------------------------------
local function hex(s, n) return type(s) == "string" and #s == n and s:find("^[0-9a-f]+$") ~= nil end

-- true when `rec` is a well-formed ledger entry (the owner rule of the set `likes`).
function Likes.ValidEntry(rec)
	if type(rec) ~= "table" or rec.rev ~= 1 or rec.del ~= nil then return false end
	if not hex(rec.pseudonym, Likes.PSEUDONYM_HEX) then return false end
	if rec.tag ~= nil and not hex(rec.tag, Likes.TAG_HEX) then return false end
	if not isGUID(rec.target) then return false end
	local day = rec.day
	if type(day) ~= "number" or day ~= floor(day) or day < 20000101 or day > 29991231 then return false end
	return rec.id == Likes.EntryId(rec.pseudonym, rec.target)
end

function Likes.EntryId(pseudonym, target)
	return pseudonym:sub(1, Likes.ID_HEX) .. ":" .. target
end

function Likes.Pseudonym(salt, token)
	local h = ns.Hash.HMACHex(salt, token)
	return h and h:sub(1, Likes.PSEUDONYM_HEX) or nil
end

function Likes.Tag(salt, guid)
	local h = ns.Hash.HMACHex(salt, "char:" .. guid)
	return h and h:sub(1, Likes.TAG_HEX) or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Accounts and totals
---------------------------------------------------------------------------------------------------------------------
-- The characters a like to `guid` counts for: the proved characters of its account (mutual listing, ADR 0006), or the
-- character alone when it has no group or is only joined to one by a note.
function Likes:AccountChars(guid)
	if ns.Accounts then return ns.Accounts:ProvedChars(guid) end
	return { guid }
end

local function index()
	if state.index then return state.index end
	local idx = {}
	for _, rec in pairs(ns.Store and ns.Store:Records("likes") or {}) do
		if type(rec) == "table" and type(rec.target) == "string" and type(rec.pseudonym) == "string" then
			local set = idx[rec.target]
			if not set then set = {} idx[rec.target] = set end
			set[rec.pseudonym] = true
		end
	end
	state.index = idx
	return idx
end

-- The newest ledger entry that counts for the account of `guid`: its `time` and `author` (the notary), or nil. For the
-- provenance label of the total (SPEC-11 §1.3).
function Likes:Newest(guid)
	if type(guid) ~= "string" or not ns.Store then return nil end
	local mine = {}
	for _, g in ipairs(self:AccountChars(guid)) do mine[g] = true end
	local best
	for _, rec in pairs(ns.Store:Records("likes")) do
		if type(rec) == "table" and mine[rec.target] and type(rec.time) == "number" and (not best or rec.time > best.time) then best = rec end
	end
	return best and { time = best.time, author = best.author } or nil
end

-- The likes of the account of `guid`: distinct pseudonyms over all its characters (LIKE-04).
function Likes:Total(guid)
	if type(guid) ~= "string" then return 0 end
	local cached = state.totals[guid]
	if cached then return cached end
	local idx, seen, n = index(), {}, 0
	for _, g in ipairs(self:AccountChars(guid)) do
		for p in pairs(idx[g] or {}) do
			if not seen[p] then seen[p] = true n = n + 1 end
		end
	end
	state.totals[guid] = n
	return n
end

function Likes:Invalidate()
	state.index, state.totals = nil, {}
end

---------------------------------------------------------------------------------------------------------------------
-- The voter: queue, delivery, receipts
---------------------------------------------------------------------------------------------------------------------
local function own(create)
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.likes) ~= "table" then
		if not create then return nil end
		data.likes = {}
	end
	local l = data.likes
	if type(l.given) ~= "table" then l.given = {} end
	if type(l.queue) ~= "table" then l.queue = {} end
	return l
end

-- true when `guid` is one of this player's own characters (the account, mutual listing or the own list).
local function mine(guid)
	local me = myGUID()
	if not me then return false end
	if guid == me then return true end
	for _, g in ipairs(Likes:AccountChars(me)) do if g == guid then return true end end
	for _, c in ipairs(ns.Accounts and ns.Accounts:OwnChars() or {}) do if c.guid == guid then return true end end
	return false
end

-- What the like button of `guid` shows: "self" (own account), "given", "pending", "nobody" (not a guild member), "can".
function Likes:StateOf(guid)
	if not isGUID(guid) then return "nobody" end
	if mine(guid) then return "self" end
	local l = own(false)
	local chars = self:AccountChars(guid)
	if l then
		for _, g in ipairs(chars) do if l.given[g] then return "given" end end
		for _, g in ipairs(chars) do if l.queue[g] then return "pending" end end
	end
	if not (ns.Roster and ns.Roster:ByGUID(guid)) then return "nobody" end
	return "can"
end

-- The votes waiting for a notary: a list of target GUIDs.
function Likes:Pending()
	local out = {}
	local l = own(false)
	for g in pairs(l and l.queue or {}) do out[#out + 1] = g end
	sort(out)
	return out
end

local function nonce()
	return ("%08x"):format(floor(random() * 4294967295))
end

local function startTicker()
	if state.ticker or not Likes.AUTO then return end
	state.ticker = compat().NewTicker(Likes.TICK, function() Likes:Flush() end)
end

-- Gives the like of this account to the account of `guid`. Returns true (queued, and sent when a notary is online), or
-- false plus the reason ("self", "given", "pending", "nobody", "guild").
function Likes:Give(guid)
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local st = self:StateOf(guid)
	if st ~= "can" then return false, st end
	local l = own(true)
	l.queue[guid] = { at = now(), n = nonce() }
	state.stats.given = state.stats.given + 1
	emit("LIKES_UPDATED")
	self:Flush()
	startTicker()
	return true
end

local function settle(target, result)
	local l = own(true)
	if not l then return end
	if result == "ok" or result == "dup" then
		l.given[target] = now()
		l.queue[target] = nil
	elseif result == "self" or result == "target" or result == "conflict" then
		l.queue[target] = nil
	end
	if not l.queue[target] then state.inflight[target], state.tried[target] = nil, nil end
	emit("LIKE_RESULT", target, result)
	emit("LIKES_UPDATED")
end

-- Delivers the waiting votes: each to one notary, the next officer when one did not answer in time. Returns the number
-- of votes handed to a notary (or notarized here).
function Likes:Flush()
	local l = own(false)
	if not l or not next(l.queue) then
		if state.ticker then state.ticker:Cancel() state.ticker = nil end
		return 0
	end
	local me = myGUID()
	local t, n = now(), 0
	local targets = {}
	for g in pairs(l.queue) do targets[#targets + 1] = g end
	sort(targets)
	for _, target in ipairs(targets) do
		local q = l.queue[target]
		local fly = state.inflight[target]
		if fly and t - fly.at >= Likes.WAIT_RECEIPT then
			-- no receipt: that officer is skipped for a while
			state.tried[target] = state.tried[target] or {}
			state.tried[target][fly.name] = t + Likes.RETRY_SILENT
			state.inflight[target], fly = nil, nil
		end
		if not fly then
			local exclude = {}
			for name, untilT in pairs(state.tried[target] or {}) do
				if t < untilT then exclude[name] = true end
			end
			local notary = ns.Notary and ns.Notary:Choose(me, exclude)
			if notary == "self" then
				local result = self:Notarize(me, target)
				n = n + 1
				settle(target, result)
			elseif notary then
				local item = ns.Transport and ns.Transport:Send("WHISPER", { t = "VOTE", g = target, n = q.n },
					{ target = notary, ttl = Likes.VOTE_TTL, key = "VOTE|" .. target })
				if item then
					state.inflight[target] = { name = notary, at = t, nonce = q.n }
					state.stats.sent = state.stats.sent + 1
					n = n + 1
				end
			end
		end
	end
	return n
end

local function onReceipt(msg, sender)
	local member = ns.Store and ns.Store:Member(sender)
	if not (member and member.officer) then state.stats.ignored = state.stats.ignored + 1 return end
	local target, result = msg.g, msg.r
	if not (isGUID(target) and Likes.RESULTS[result]) then state.stats.ignored = state.stats.ignored + 1 return end
	local l = own(false)
	local q = l and l.queue[target]
	if not q or (msg.n ~= nil and msg.n ~= q.n) then state.stats.ignored = state.stats.ignored + 1 return end
	state.stats.receipts = state.stats.receipts + 1
	-- the new entry rides along: this client shows the new total at once (it is checked like any record)
	if type(msg.e) == "table" and ns.Store then ns.Store:Receive("likes", { msg.e }, sender, "WHISPER") end
	if result == "ok" or result == "dup" or result == "self" or result == "target" or result == "conflict" then
		settle(target, result)
	else
		state.tried[target] = state.tried[target] or {}
		state.tried[target][sender] = now() + Likes.RETRY_SOON
		state.inflight[target] = nil
		emit("LIKE_RESULT", target, result)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The notary
---------------------------------------------------------------------------------------------------------------------
-- The tokens published by the characters of a list (normally one; several when the account changed its token).
local function tokensOf(chars)
	local out, seen = {}, {}
	local S = ns.Store
	for _, g in ipairs(chars) do
		local tok = S and S:TokenOf(g)
		if tok and not seen[tok] then seen[tok] = true out[#out + 1] = tok end
	end
	return out
end

-- Checks and records the vote of `voter` (GUID) for `target` (GUID). Returns the result code and the new entry (for
-- "ok"). Only an officer holding a salt notarizes.
function Likes:Notarize(voter, target)
	local N = ns.Notary
	if not (N and N:CanNotarize()) then return "nosalt" end
	local S = ns.Store
	if not isGUID(voter) or not (S:MemberByGUID(voter) or voter == myGUID()) then return "unknown" end
	local token = S:TokenOf(voter)
	if not token then return "unknown" end
	if not isGUID(target) or not S:MemberByGUID(target) then return "target" end
	local voterChars = self:AccountChars(voter)
	local targetChars = self:AccountChars(target)
	local inTarget = {}
	for _, g in ipairs(targetChars) do inTarget[g] = true end
	for _, g in ipairs(voterChars) do if inTarget[g] then return "self" end end
	if S:SameAccount(voter, target) then return "self" end
	-- the token is public: a character outside the voter's account that publishes the same token copied it (or was
	-- copied). Its votes would share one pseudonym, so neither side's vote is recorded until that is resolved.
	local ownChar = {}
	for _, g in ipairs(voterChars) do ownChar[g] = true end
	for guid, rec in pairs(S:Records("accounts")) do
		if type(rec) == "table" and rec.token == token and not ownChar[guid] then return "conflict" end
	end
	-- every pseudonym and tag the voter could have had, under every salt
	local tokens = tokensOf(voterChars)
	local pseudos, tags = {}, {}
	for _, s in ipairs(N:Salts()) do
		for _, tok in ipairs(tokens) do pseudos[Likes.Pseudonym(s.raw, tok)] = true end
		for _, g in ipairs(voterChars) do tags[Likes.Tag(s.raw, g)] = true end
	end
	for _, rec in pairs(S:Records("likes")) do
		if type(rec) == "table" and inTarget[rec.target] and (pseudos[rec.pseudonym] or (rec.tag and tags[rec.tag])) then
			return "dup"
		end
	end
	local salt = N:Current()
	local pseudonym = Likes.Pseudonym(salt, token)
	local rec, why = S:Put("likes", Likes.EntryId(pseudonym, target), {
		pseudonym = pseudonym, tag = Likes.Tag(salt, voter), target = target, day = compat().ServerDay(),
	})
	if not rec then return why == "immutable" and "dup" or "nosalt" end
	state.stats.notarized = state.stats.notarized + 1
	return "ok", rec
end

local function withinRate(sender)
	local t = now()
	local w = state.answered[sender]
	if not w or t - w.start >= Likes.RATE[2] then
		w = { start = t, count = 0 }
		state.answered[sender] = w
	end
	w.count = w.count + 1
	return w.count <= Likes.RATE[1]
end

local function onVote(msg, sender)
	state.stats.votesHeard = state.stats.votesHeard + 1
	if not (ns.Role and ns.Role:IsOfficer()) then state.stats.ignored = state.stats.ignored + 1 return end
	local member = ns.Store and ns.Store:Member(sender)
	if not (member and isGUID(member.guid)) then state.stats.ignored = state.stats.ignored + 1 return end
	local result, rec
	if not withinRate(sender) then result = "rate"
	else result, rec = Likes:Notarize(member.guid, msg.g) end
	if result ~= "ok" then state.stats.refused = state.stats.refused + 1 end
	if ns.Transport then
		ns.Transport:Send("WHISPER", { t = "LEDGER", g = tostring(msg.g), n = type(msg.n) == "string" and msg.n or nil, r = result, e = rec },
			{ target = sender, ttl = Likes.VOTE_TTL })
	end
end

function Likes:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" or dist ~= "WHISPER" then return end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return end
	if msg.t == "VOTE" then onVote(msg, sender)
	elseif msg.t == "LEDGER" then onReceipt(msg, sender) end
end

---------------------------------------------------------------------------------------------------------------------
-- Start and debug
---------------------------------------------------------------------------------------------------------------------
function Likes:Start()
	if not self.AUTO then return false end
	local l = own(false)
	if l and next(l.queue) then startTicker() end
	return true
end

function Likes:OnGuildChanged(key)
	resetState()
	if key then self:Start() end
end

function Likes:DebugLines()
	local s = state.stats
	local l = own(false)
	local given, queued = 0, 0
	for _ in pairs(l and l.given or {}) do given = given + 1 end
	for _ in pairs(l and l.queue or {}) do queued = queued + 1 end
	local entries = ns.Store and ns.Store:Count("likes") or 0
	return {
		("Likes: ledger %d entr%s; this account gave %d, %d pending"):format(entries, entries == 1 and "y" or "ies", given, queued),
		("  votes sent %d, receipts %d; as notary: heard %d, recorded %d, refused %d; ignored %d"):format(s.sent, s.receipts,
			s.votesHeard, s.notarized, s.refused, s.ignored),
	}
end

if ns.addon then
	ns.addon.Likes = Likes
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Likes", function() return Likes:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("NET_MESSAGE", function(msg, sender, dist)
			if type(msg) == "table" and (msg.t == "VOTE" or msg.t == "LEDGER") then Likes:OnMessage(msg, sender, dist) end
		end)
		ns.Bus:On("STORE_CHANGED", function(set)
			if set == "likes" then Likes:Invalidate() emit("LIKES_UPDATED")
			elseif set == "accounts" then state.totals = {} end   -- alts linked: totals merge
		end)
		ns.Bus:On("ACCOUNTS_UPDATED", function() state.totals = {} end)
		ns.Bus:On("ROSTER_UPDATED", function() state.totals = {} end)
		ns.Bus:On("GUILD_CHANGED", function(key) Likes:OnGuildChanged(key) end)
	end
	if ns.OnEnable then ns.OnEnable(function() Likes:Start() end) end
end

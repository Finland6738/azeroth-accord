-- Sync: how the clients of a guild converge on the same records (SPEC-02 §4). Lua 5.1.
--
-- The trust rules (Net/Store.lua) decide WHO may pass a record on: its author's account (first hand) or an officer
-- (relay). So the sync works per author:
--
--   Summary   for every author a client holds records of: key (a 32-bit hash of the author GUID), digest (24 bits of a
--             hash of the author's records: set, id, rev, time) and the newest record time. 11 bytes per author.
--   HELLO     (GUILD) the summary, 10-30 s after login and then every 15-20 minutes (at most one per 5 minutes, NET-04).
--   push      a client that sees a HELLO and is AHEAD of the sender for an author it may deliver sends those records to
--             the sender by WHISPER after a random 0.5-3 s: its own account's authors always; an officer also the
--             authors whose account has nobody online, but only the one officer designated for that sender (the
--             smallest hash of officer GUID and sender GUID among the officers heard recently), so officers never
--             answer twice.
--   REQ       (WHISPER) a client that sees a HELLO from someone AHEAD of it, who may deliver that author (same account
--             or officer), asks for that author after a random 1-5 s, unless the records arrived meanwhile.
--   REC       records of one set. Answers to REQ go on GUILD with a queue key per author and set, so the same request
--             from many clients goes out once and everyone who missed it catches up; local changes go on GUILD after a
--             5-second batch; pushes go by WHISPER.
--   OHELLO    (OFFICER) the same summary for the records that only officers hold (the bank tabs an officer read:
--             Store.IsRestricted). Those records never travel on GUILD and never count in a GUILD summary, so a member's
--             summary and an officer's agree on everything a member may hold. A local change of such a record goes out as
--             REC on OFFICER; an officer who is ahead of an OHELLO sender pushes the missing ones by WHISPER (only the
--             officer designated for that sender, or the author's own account), exactly as for a HELLO.
--   DIGEST    not used by this design (the push replaces the digest reply); the type stays in the codec.
--   ask       Sync:RequestSet(set, author): a view needs one author's records of ONE set now (a member's recipes), so it
--             sends a REQ for just that set by WHISPER to a peer that may deliver (the author's own account if online, else
--             up to two officers heard recently); the answer is a WHISPER REC with only those records, not a GUILD one.
--             Asked at most once per ASK_COOLDOWN seconds per author and set.
--
-- Received records always go through Store:Receive, so a client that is not allowed to pass something on is simply
-- refused by the others. Every timer is cancelled on a change of guild. Bus: SYNC_HELLO(sent), SYNC_RECEIVED(set, n).
local ADDON_NAME, ns = ...
ns = ns or {}
local Sync = {}
ns.Sync, ns.modules = Sync, ns.modules or {}
ns.modules.Sync = Sync

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, random, min, max = math.floor, math.random, math.min, math.max
local byte, char, sort, concat = string.byte, string.char, table.sort, table.concat

Sync.AUTO = true                    -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Sync.HELLO_DELAY = { 10, 30 }       -- seconds after login
Sync.HELLO_PERIOD = { 900, 1200 }   -- seconds between two HELLOs while online
Sync.PUSH_DELAY = { 0.5, 3 }
Sync.REQ_DELAY = { 1, 5 }
Sync.BATCH = 5                      -- seconds a local change waits, so several changes go out together
Sync.PRESENCE = 1500                -- a peer counts as online this long after its last message
Sync.REC_BYTES = 2500               -- estimated size of the records in one REC (the codec limit is far above)
Sync.ENTRY = 11                     -- bytes per author in a summary
Sync.ASK_COOLDOWN = 300             -- seconds before the same set of the same author is asked for again
Sync.ASK_OFFICERS = 2               -- officers asked when the author's account is not online
Sync.ASK_RATE = { 20, 60 }          -- answers to set requests: at most 20 per sender per 60 seconds

local function compat() return ns.Compat end
local function store() return ns.Store end
local function hash() return ns.Hash end
local function now() return compat().Now() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function between(r) return r[1] + (r[2] - r[1]) * random() end

local state
local function resetState()
	if state then
		for _, t in pairs(state.timers or {}) do if t.Cancel then t:Cancel() end end
	end
	state = {
		present = {},          -- sender name -> { guid, at, officer }
		push = {},             -- target name -> { authors = { [guid] = true }, timer }
		req = {},              -- target name -> { keys = { [key] = true }, theirs = summary, timer }
		dirty = {},            -- set -> { [id] = true }: local changes waiting for the batch
		asked = {},            -- "<set>|<author>" -> when this client asked for it (RequestSet)
		answering = {},        -- sender name -> { start, count }: the rate of the set requests answered
		batchTimer = nil, helloTimer = nil, timers = {},
		cache = {}, version = 0, cacheVersion = -1,
		stats = { hellosSent = 0, hellosHeard = 0, pushes = 0, requests = 0, answers = 0, recSent = 0, recReceived = 0,
			accepted = 0, refused = 0, asks = 0, asksAnswered = 0, asksLimited = 0 },
	}
	Sync.state = state
end
resetState()

---------------------------------------------------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------------------------------------------------
local keyCache = {}
function Sync.KeyOf(guid)
	local k = keyCache[guid]
	if not k then
		k = hash().Fast(guid)
		keyCache[guid] = k
	end
	return k
end

-- author GUID -> { key, d, t, records = { { set, rec }, ... } } over every data set of the current guild. The records for
-- officers only (Store.IsRestricted) are left out, unless `restricted` is true: then only those are grouped.
function Sync:Groups(restricted)
	restricted = restricted == true
	if state.cacheVersion ~= state.version then state.cache, state.cacheVersion = {}, state.version end
	if state.cache[restricted] then return state.cache[restricted] end
	local groups = {}
	local S = store()
	for _, set in ipairs(S.SET_ORDER) do
		for id, rec in pairs(S:Records(set)) do
			local author = type(rec) == "table" and rec.author
			if type(author) == "string" and S.IsRestricted(set, rec) == restricted then
				local g = groups[author]
				if not g then g = { records = {}, parts = {}, t = 0 } groups[author] = g end
				g.records[#g.records + 1] = { set, rec }
				g.parts[#g.parts + 1] = set .. "|" .. tostring(id) .. "|" .. tostring(rec.rev) .. "|" .. tostring(rec.time)
				if (rec.time or 0) > g.t then g.t = rec.time end
			end
		end
	end
	for author, g in pairs(groups) do
		sort(g.parts)
		g.key = Sync.KeyOf(author)
		g.d = hash().Fast(concat(g.parts, "\n")) % 16777216
		g.parts = nil
	end
	state.cache[restricted] = groups
	return groups
end

local function be(n, bytes)
	local out = {}
	for i = bytes, 1, -1 do
		out[i] = char(n % 256)
		n = floor(n / 256)
	end
	return concat(out)
end

local function readBE(s, at, bytes)
	local n = 0
	for i = at, at + bytes - 1 do n = n * 256 + byte(s, i) end
	return n
end

-- The summary as a byte string: entries sorted by key, each key (4 bytes), digest (3), newest time (4).
function Sync:EncodeSummary(groups)
	local entries = {}
	for _, g in pairs(groups or self:Groups()) do entries[#entries + 1] = g end
	sort(entries, function(a, b) return a.key < b.key end)
	local out = {}
	for i, g in ipairs(entries) do
		out[i] = be(g.key, 4) .. be(g.d, 3) .. be(max(0, min(floor(g.t), 4294967295)), 4)
	end
	return concat(out)
end

-- key -> { d, t } from a summary string, or nil when it is malformed.
function Sync.DecodeSummary(s)
	if type(s) ~= "string" or #s % Sync.ENTRY ~= 0 or #s > Sync.ENTRY * 2000 then return nil end
	local out = {}
	for at = 1, #s, Sync.ENTRY do
		out[readBE(s, at, 4)] = { d = readBE(s, at + 4, 3), t = readBE(s, at + 7, 4) }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Peers
---------------------------------------------------------------------------------------------------------------------
local function myGUID() return compat().Player.GUID() end

local function touch(sender)
	local member = store():Member(sender)
	if not member or type(member.guid) ~= "string" then return nil end
	state.present[sender] = { guid = member.guid, at = now(), officer = member.officer == true }
	return member
end

-- The peers with the addon that are online: heard within PRESENCE seconds and not offline in the roster (the roster
-- tells at once when somebody logs out; the last message alone would keep them "present" for minutes).
local function presentPeers()
	local t, out, S = now(), {}, store()
	for name, p in pairs(state.present) do
		local member = S:Member(name)
		if t - p.at > Sync.PRESENCE or (member and member.online == false) then
			state.present[name] = nil
		else
			out[name] = p
		end
	end
	return out
end

-- The GUIDs whose account has somebody online right now (this character and the peers heard recently).
local function onlineAccounts()
	local S, set = store(), {}
	local function mark(guid)
		set[guid] = true
		local rec = S:Get("accounts", guid)
		if rec and type(rec.chars) == "table" then
			for _, c in ipairs(rec.chars) do
				local g = type(c) == "table" and c.guid or c
				if type(g) == "string" and S:SameAccount(guid, g) then set[g] = true end
			end
		end
	end
	local me = myGUID()
	if me then mark(me) end
	for _, p in pairs(presentPeers()) do mark(p.guid) end
	return set
end

local function iAmOfficer() return ns.Role and ns.Role:IsOfficer() or false end

-- true when this client is the officer designated to relay to `targetGUID` (NET-04: one answer, not one per officer).
local function designated(targetGUID)
	if not iAmOfficer() then return false end
	local me = myGUID()
	local H = hash()
	local best, bestGUID = H.Fast(me .. targetGUID), me
	for _, p in pairs(presentPeers()) do
		if p.officer and p.guid ~= targetGUID then
			local v = H.Fast(p.guid .. targetGUID)
			if v < best or (v == best and p.guid < bestGUID) then best, bestGUID = v, p.guid end
		end
	end
	return bestGUID == me
end

-- true when `mine` (a group or nil) is ahead of `theirs` (a summary entry or nil).
local function ahead(mine, theirs)
	if not mine then return false end
	if not theirs then return true end
	if mine.t ~= theirs.t then return mine.t > theirs.t end
	return mine.d ~= theirs.d
end

---------------------------------------------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------------------------------------------
local function send(dist, msg, opts)
	if not ns.Transport then return nil end
	return ns.Transport:Send(dist, msg, opts)
end

-- REC messages for a list of { set, rec } entries, split by set and by size.
local function sendRecords(entries, dist, target, keyPrefix)
	local bySet = {}
	for _, e in ipairs(entries) do
		local list = bySet[e[1]]
		if not list then list = {} bySet[e[1]] = list end
		list[#list + 1] = e[2]
	end
	local Config = ns.Config
	local count = 0
	for _, set in ipairs(store().SET_ORDER) do
		local list = bySet[set]
		if list then
			sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
			local batch, size, part = {}, 0, 0
			local function flush()
				if #batch == 0 then return end
				part = part + 1
				send(dist, { t = "REC", s = set, r = batch }, {
					target = target, key = keyPrefix and (keyPrefix .. "|" .. set .. "|" .. part) or nil,
				})
				count = count + 1
				state.stats.recSent = state.stats.recSent + 1
				batch, size = {}, 0
			end
			for _, rec in ipairs(list) do
				local bytes = Config and Config.EstimateSize(rec) or 200
				if size > 0 and size + bytes > Sync.REC_BYTES then flush() end
				batch[#batch + 1] = rec
				size = size + bytes
			end
			flush()
		end
	end
	return count
end

local function recordsOf(authors, restricted)
	local groups, entries = Sync:Groups(restricted), {}
	for author in pairs(authors) do
		local g = groups[author]
		if g then for _, e in ipairs(g.records) do entries[#entries + 1] = e end end
	end
	return entries
end

-- A cancellable one-shot timer, remembered so a change of guild cancels it.
local function after(seconds, fn)
	local timer
	timer = compat().NewTimer(seconds, function()
		if timer then state.timers[timer] = nil end
		fn()
	end)
	if timer then state.timers[timer] = timer end
	return timer
end

-- Sends a HELLO with the current summary (the transport keeps it to one per five minutes).
function Sync:SendHello()
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false end
	local version = ns.addon and C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	local ok = send("GUILD", { t = "HELLO", d = {}, s = self:EncodeSummary(), av = type(version) == "string" and version:sub(1, 20) or nil },
		{ key = "HELLO" })
	if ok then
		state.stats.hellosSent = state.stats.hellosSent + 1
		emit("SYNC_HELLO", true)
	end
	-- the officers also tell each other what they hold of the restricted records (OFFICER, never GUILD)
	if iAmOfficer() then
		send("OFFICER", { t = "OHELLO", s = self:EncodeSummary(self:Groups(true)) }, { key = "OHELLO" })
	end
	return ok and true or false
end

local function scheduleHello(range)
	if state.helloTimer then state.helloTimer:Cancel() end
	state.helloTimer = after(between(range), function()
		state.helloTimer = nil
		Sync:SendHello()
		scheduleHello(Sync.HELLO_PERIOD)
	end)
end

-- Starts the HELLO cycle (at login, or when the character joins a guild).
function Sync:Start()
	if not self.AUTO then return false end
	scheduleHello(Sync.HELLO_DELAY)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------------------------------------------------
local function onHello(msg, sender)
	local theirs = Sync.DecodeSummary(msg.s)
	if not theirs then return end
	state.stats.hellosHeard = state.stats.hellosHeard + 1
	-- the roster says who is online; ask the server for a fresh one now and then (it answers later, throttled)
	local t = now()
	if not state.rosterAsked or t - state.rosterAsked > 60 then
		state.rosterAsked = t
		compat().Guild.RequestRoster()
	end
	local member = touch(sender)
	if not member then return end
	local target, S = member.guid, store()
	local me = myGUID()
	local groups = Sync:Groups()
	local accountsOnline = onlineAccounts()
	local isDesignated = nil

	-- push what the sender lacks and this client may deliver
	local pushAuthors = {}
	for author, g in pairs(groups) do
		if ahead(g, theirs[g.key]) then
			local targetsOwn = author == target or S:SameAccount(author, target)
			if me and S:SameAccount(me, author) and not targetsOwn then
				pushAuthors[author] = true
			elseif targetsOwn or not accountsOnline[author] then
				-- an offline author, or the sender's own records that it lost (a new computer): one officer relays
				if isDesignated == nil then isDesignated = designated(target) end
				if isDesignated then pushAuthors[author] = true end
			end
		end
	end
	if next(pushAuthors) then
		local entry = state.push[sender]
		if not entry then
			entry = { authors = {} }
			state.push[sender] = entry
			entry.timer = after(between(Sync.PUSH_DELAY), function()
				state.push[sender] = nil
				local n = sendRecords(recordsOf(entry.authors), "WHISPER", sender)
				if n > 0 then state.stats.pushes = state.stats.pushes + 1 end
			end)
		end
		for a in pairs(pushAuthors) do entry.authors[a] = true end
	end

	-- ask for what the sender has newer and may deliver
	local myKeys = {}
	for author, g in pairs(groups) do myKeys[g.key] = author end
	local senderOfficer = member.officer == true
	local wanted = {}
	for key, entryTheirs in pairs(theirs) do
		local author = myKeys[key]
		local mine = author and groups[author]
		local behind = (mine == nil) or entryTheirs.t > mine.t
		if behind then
			local canDeliver = senderOfficer or key == Sync.KeyOf(target)
				or (author ~= nil and S:SameAccount(target, author))
			-- this includes the client's own records: after a lost or older saved file it gets its versions back,
			-- so its next write does not start again from rev 1
			if canDeliver then wanted[key] = true end
		end
	end
	if next(wanted) then
		local entry = state.req[sender]
		if not entry then
			entry = { keys = {} }
			state.req[sender] = entry
			entry.timer = after(between(Sync.REQ_DELAY), function()
				state.req[sender] = nil
				local still, list = Sync:Groups(), {}
				local byKey = {}
				for a, g in pairs(still) do byKey[g.key] = g end
				for key in pairs(entry.keys) do
					local mine, theirs = byKey[key], entry.theirs[key]
					if theirs and (mine == nil or theirs.t > mine.t) then list[#list + 1] = key end
				end
				if #list == 0 then return end
				sort(list)
				send("WHISPER", { t = "REQ", s = "*", a = list }, { target = sender })
				state.stats.requests = state.stats.requests + 1
			end)
		end
		entry.theirs = theirs
		for key in pairs(wanted) do entry.keys[key] = true end
	end
end

-- An officer's OHELLO: the restricted records (bank tabs read by an officer) are pushed to an officer who lacks them. Only
-- officers speak and listen here; a member never holds such a record.
local function onOfficerHello(msg, sender)
	if not iAmOfficer() then return end
	local theirs = Sync.DecodeSummary(msg.s)
	if not theirs then return end
	local member = touch(sender)
	if not (member and member.officer) then return end
	local target, S, me = member.guid, store(), myGUID()
	local groups = Sync:Groups(true)
	local pushAuthors, isDesignated = {}, nil
	for author, g in pairs(groups) do
		if ahead(g, theirs[g.key]) then
			if me and S:SameAccount(me, author) and author ~= target and not S:SameAccount(author, target) then
				pushAuthors[author] = true
			else
				if isDesignated == nil then isDesignated = designated(target) end
				if isDesignated and author ~= target then pushAuthors[author] = true end
			end
		end
	end
	if not next(pushAuthors) then return end
	local key = "O|" .. sender
	local entry = state.push[key]
	if not entry then
		entry = { authors = {} }
		state.push[key] = entry
		entry.timer = after(between(Sync.PUSH_DELAY), function()
			state.push[key] = nil
			local n = sendRecords(recordsOf(entry.authors, true), "WHISPER", sender)
			if n > 0 then state.stats.pushes = state.stats.pushes + 1 end
		end)
	end
	for a in pairs(pushAuthors) do entry.authors[a] = true end
end

-- true while `sender` has not used up its share of set requests (ASK_RATE).
local function withinAskRate(sender)
	local t = now()
	local w = state.answering[sender]
	if not w or t - w.start >= Sync.ASK_RATE[2] then
		w = { start = t, count = 0 }
		state.answering[sender] = w
	end
	w.count = w.count + 1
	return w.count <= Sync.ASK_RATE[1]
end

local function onReq(msg, sender)
	if type(msg.a) ~= "table" then return end
	local member = touch(sender)
	if not member then return end
	local S, me = store(), myGUID()
	local groups = Sync:Groups()
	local byKey = {}
	for author, g in pairs(groups) do byKey[g.key] = author end
	local officer = iAmOfficer()
	local single = msg.s ~= "*" and S.SETS[msg.s] and msg.s or nil
	if single and not withinAskRate(sender) then
		state.stats.asksLimited = state.stats.asksLimited + 1
		return
	end
	local count = 0
	for i, key in ipairs(msg.a) do
		if i > (single and 20 or 500) then break end
		local author = type(key) == "number" and byKey[key]
		if author and (officer or (me and S:SameAccount(me, author))) then
			local entries = {}
			for _, e in ipairs(groups[author].records) do
				if not single or e[1] == single then entries[#entries + 1] = e end
			end
			if single then
				-- a request for one set came from a view that needs it now: the answer goes to that client only
				if #entries > 0 then count = count + sendRecords(entries, "WHISPER", sender) end
			else
				count = count + sendRecords(entries, "GUILD", nil, "REC|" .. key)
			end
		end
	end
	if count > 0 then
		if single then state.stats.asksAnswered = state.stats.asksAnswered + 1
		else state.stats.answers = state.stats.answers + 1 end
	end
end

local function onRec(msg, sender, dist)
	touch(sender)
	local S = store()
	if not S.SETS[msg.s] then return end
	local accepted, refused = S:Receive(msg.s, msg.r, sender, dist)
	state.stats.recReceived = state.stats.recReceived + 1
	state.stats.accepted = state.stats.accepted + accepted
	state.stats.refused = state.stats.refused + refused
	if accepted > 0 then
		state.lastReceived = compat().ServerTime()
		emit("SYNC_RECEIVED", msg.s, accepted)
	end
end

function Sync:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" then return end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return end
	if msg.t == "HELLO" and dist == "GUILD" then onHello(msg, sender)
	elseif msg.t == "REQ" and dist == "WHISPER" then onReq(msg, sender)
	elseif msg.t == "REC" then onRec(msg, sender, dist)
	elseif msg.t == "OHELLO" and dist == "OFFICER" then onOfficerHello(msg, sender)
	elseif msg.t == "DIGEST" then touch(sender) end
end

---------------------------------------------------------------------------------------------------------------------
-- Local changes
---------------------------------------------------------------------------------------------------------------------
local function flushLocal()
	state.batchTimer = nil
	local S, entries = store(), {}
	for set, ids in pairs(state.dirty) do
		for id in pairs(ids) do
			local rec = S:Get(set, id)
			if rec then entries[#entries + 1] = { set, rec } end
		end
	end
	state.dirty = {}
	-- the records for officers only never go on GUILD: they go on OFFICER (and nowhere when nobody can hear them)
	local open, closed = {}, {}
	for _, e in ipairs(entries) do
		if S.IsRestricted(e[1], e[2]) then closed[#closed + 1] = e else open[#open + 1] = e end
	end
	if #open > 0 then sendRecords(open, "GUILD") end
	if #closed > 0 and iAmOfficer() then sendRecords(closed, "OFFICER") end
end

function Sync:OnStoreChanged(set, id, origin)
	state.version = state.version + 1
	if origin ~= "local" then return end
	local ids = state.dirty[set]
	if not ids then ids = {} state.dirty[set] = ids end
	ids[id] = true
	if not state.batchTimer then state.batchTimer = after(Sync.BATCH, flushLocal) end
end

function Sync:OnGuildChanged(key)
	resetState()
	if key then Sync:Start() end
end

-- Asks for one author's records of one set because a view needs them (the recipes of a member). Returns "sent" and the
-- name asked, "own" (the author is this player's own account: nothing to ask), "recent" (asked within ASK_COOLDOWN),
-- "nobody" (no peer that may deliver them is online and known: nothing is sent and nothing is remembered, so the next
-- call tries again), "blocked" (the transport refused), "guild" or "invalid".
function Sync:RequestSet(set, author)
	if not (ns.GuildKey and ns.GuildKey:Current()) then return "guild" end
	local S = store()
	if not S.SETS[set] or type(author) ~= "string" or author == "" then return "invalid" end
	local me = myGUID()
	if me and (author == me or S:SameAccount(me, author)) then return "own" end
	local key = set .. "|" .. author
	local t = now()
	local last = state.asked[key]
	if last and t - last < Sync.ASK_COOLDOWN then return "recent" end
	local own, officers = {}, {}
	for name, p in pairs(presentPeers()) do
		if p.guid == author or S:SameAccount(p.guid, author) then own[#own + 1] = name
		elseif p.officer then officers[#officers + 1] = { name = name, rank = hash().Fast((p.guid or "") .. (me or "")) } end
	end
	local targets = {}
	if #own > 0 then
		sort(own)
		targets[1] = own[1]
	else
		sort(officers, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.name < b.name end)
		for i = 1, min(Sync.ASK_OFFICERS, #officers) do targets[i] = officers[i].name end
	end
	if #targets == 0 then return "nobody" end
	local sentTo
	for _, name in ipairs(targets) do
		if send("WHISPER", { t = "REQ", s = set, a = { Sync.KeyOf(author) } }, { target = name, key = "ASK|" .. key .. "|" .. name }) then
			sentTo = sentTo or name
		end
	end
	if not sentTo then return "blocked" end
	state.asked[key] = t
	state.stats.asks = state.stats.asks + 1
	return "sent", sentTo
end

-- The guildmates with the addon heard recently and still online in the roster: name -> { guid, officer }. A copy, for
-- the modules that pick one of them (the notary of the likes, Data/Notary.lua).
function Sync:Peers()
	local out = {}
	for name, p in pairs(presentPeers()) do out[name] = { guid = p.guid, officer = p.officer } end
	return out
end

-- For the top bar of the panel: how many guildmates with the addon are online, when records last arrived.
function Sync:Status()
	local n = 0
	for _ in pairs(presentPeers()) do n = n + 1 end
	return { peers = n, lastReceived = state.lastReceived }
end

---------------------------------------------------------------------------------------------------------------------
-- /accord debug
---------------------------------------------------------------------------------------------------------------------
function Sync:DebugLines()
	local s = state.stats
	local peers, officers = 0, 0
	for _, p in pairs(presentPeers()) do
		peers = peers + 1
		if p.officer then officers = officers + 1 end
	end
	local authors = 0
	if ns.GuildKey and ns.GuildKey:Current() then for _ in pairs(self:Groups()) do authors = authors + 1 end end
	return {
		("Sync: %s, %d author(s) known, %d peer(s) with the addon heard recently (%d officer(s))"):format(
			self.AUTO and "automatic" or "manual", authors, peers, officers),
		("  HELLO sent %d, heard %d; pushes %d, requests %d, answers %d; REC sent %d, received %d (accepted %d, refused %d)"):format(
			s.hellosSent, s.hellosHeard, s.pushes, s.requests, s.answers, s.recSent, s.recReceived, s.accepted, s.refused),
		("  set requests: asked %d, answered %d, over the rate limit %d"):format(s.asks, s.asksAnswered, s.asksLimited),
	}
end

if ns.addon then
	ns.addon.Sync = Sync
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Sync", function() return Sync:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) Sync:OnMessage(msg, sender, dist) end)
		ns.Bus:On("STORE_CHANGED", function(set, id, origin) Sync:OnStoreChanged(set, id, origin) end)
		ns.Bus:On("GUILD_CHANGED", function(key) Sync:OnGuildChanged(key) end)
	end
	if ns.OnEnable then
		ns.OnEnable(function() if ns.GuildKey and ns.GuildKey:Current() then Sync:Start() end end)
	end
end

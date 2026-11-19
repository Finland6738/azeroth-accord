-- Notary: the guild salt of the likes and the choice of the notary (SPEC-07 LIKE-05..LIKE-07, ADR 0007). Lua 5.1.
--
-- The salt is a 32-byte secret of the guild's officers. A notary turns a voter's account token into the pseudonym of
-- the ledger with HMAC-SHA256(salt, token) (Data/Likes.lua); members never hold the salt, so a pseudonym tells them
-- nothing, while the account tokens themselves are public (ADR 0006).
--
--   Who holds it   only officers and the Guild Master: a client keeps salts only while its character is an officer of
--                  the guild (GuildKey:Data().salts), drops them when it is demoted, and never answers or stores a salt
--                  for a sender who is not an officer in its own roster.
--   Sharing        SALT messages on OFFICER. An officer asks 15-30 s after login ("q" with the fingerprints it holds);
--                  an officer who holds salts the asker lacks shares them ("s") after 0.5-3 s, unless another officer's
--                  share on OFFICER already covered them. S5 is not verified yet: while the client has not shown that
--                  OFFICER carries addon messages (the Compat feature `officerAddonChannel` is not "available"), every
--                  SALT message ALSO goes by WHISPER to each officer with the addon heard recently (Sync:Peers), and an
--                  answer to a whispered question goes back by WHISPER.
--   Creation       an officer who still holds no salt CREATE_WAIT seconds after asking creates one (Hash.RandomBytes)
--                  and shares it. Two officers may create one at the same time: every salt is kept (a ring of at most
--                  MAX_SALTS), and all officers use the same CURRENT one, the oldest by creation time, then by
--                  fingerprint. A notary checks a vote against every salt of the ring, so a voter cannot vote twice
--                  because of two salts. If the last officer holding the salts leaves, the next officer creates a new
--                  one: the old ledger entries stay valid, only the double-vote check for votes given under the old salt
--                  is lost (LIKE-07, a known limit written in the wiki).
--   The notary     a voter whispers its vote to ONE officer with the addon who is online: this client itself when it is
--                  an officer holding the salt, else the officers heard recently ranked by a hash of officer and voter
--                  GUIDs (always the same one for a voter, spread over the officers), skipping the ones the caller
--                  already tried (Notary:Choose).
-- Bus: SALT_CHANGED(count) when the ring changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Notary = {}
ns.Notary, ns.modules = Notary, ns.modules or {}
ns.modules.Notary = Notary

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, random, sort = math.floor, math.random, table.sort

Notary.AUTO = true                -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Notary.QUERY_DELAY = { 15, 30 }   -- seconds after login (or after becoming an officer) before asking for the salt
Notary.CREATE_WAIT = 45           -- seconds after asking with no salt known before this officer creates one
Notary.SHARE_DELAY = { 0.5, 3 }
Notary.REASK = 60                 -- an officer asks again at most once a minute
Notary.TTL = 60                   -- a SALT message that could not leave within a minute is dropped
Notary.SALT_BYTES = 32
Notary.MAX_SALTS = 8
Notary.MAX_FUTURE = 3600

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function between(r) return r[1] + (r[2] - r[1]) * random() end
local function isOfficer() return ns.Role and ns.Role:IsOfficer() or false end

local state
local function resetState()
	if state then
		for _, t in pairs(state.timers or {}) do if t.Cancel then t:Cancel() end end
	end
	state = {
		timers = {}, lastQuery = nil, createTimer = nil, share = nil, queryTimer = nil,
		stats = { queries = 0, queriesHeard = 0, shares = 0, sharesHeard = 0, whispers = 0, ignored = 0, created = 0, added = 0,
			dropped = 0 },
	}
	Notary.state = state
end
resetState()

local function after(seconds, fn)
	local timer
	timer = compat().NewTimer(seconds, function()
		if timer then state.timers[timer] = nil end
		fn()
	end)
	if timer then state.timers[timer] = timer end
	return timer
end

---------------------------------------------------------------------------------------------------------------------
-- The ring of salts
---------------------------------------------------------------------------------------------------------------------
-- The fingerprint of a salt: 12 hex characters of a hash of it, to tell salts apart without showing them.
function Notary.Fingerprint(raw)
	local hex = ns.Hash.SHA256Hex("AzerothAccord salt\0" .. raw)
	return hex and hex:sub(1, 12) or nil
end

local function ring(create)
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.salts) ~= "table" then
		if not create then return nil end
		data.salts = {}
	end
	return data.salts
end

-- The salts held for the current guild, oldest first: { { fp, raw, b64, at }, ... }. Empty for a member.
function Notary:Salts()
	local out = {}
	if not isOfficer() then return out end
	local salts = ring(false)
	for fp, e in pairs(salts or {}) do
		local raw = type(e) == "table" and ns.Config.Base64Decode(e.k)
		if raw and #raw == Notary.SALT_BYTES and type(e.at) == "number" then
			out[#out + 1] = { fp = fp, raw = raw, b64 = e.k, at = e.at }
		end
	end
	sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.fp < b.fp end)
	return out
end

-- The salt new pseudonyms use (raw bytes) and its fingerprint, or nil when this client holds none or is no officer.
function Notary:Current()
	local list = self:Salts()
	local first = list[1]
	if not first then return nil end
	return first.raw, first.fp
end

function Notary:Count() return #self:Salts() end

local function fingerprints()
	local out = {}
	for _, s in ipairs(Notary:Salts()) do out[#out + 1] = s.fp end
	return out
end

-- Adds a salt (Base64 text of 32 bytes, creation time). Returns true when it is new; false plus a reason otherwise
-- ("officer", "guild", "shape", "time", "known", "full").
function Notary:AddSalt(b64, at)
	if not isOfficer() then return false, "officer" end
	local raw = type(b64) == "string" and #b64 <= 64 and ns.Config.Base64Decode(b64)
	if not raw or #raw ~= Notary.SALT_BYTES then return false, "shape" end
	at = tonumber(at)
	if not at or at ~= floor(at) or at < 0 or at > now() + Notary.MAX_FUTURE then return false, "time" end
	local salts = ring(true)
	if not salts then return false, "guild" end
	local fp = Notary.Fingerprint(raw)
	if not fp then return false, "hash" end
	if salts[fp] then return false, "known" end
	salts[fp] = { k = b64, at = at }
	-- at most MAX_SALTS: the newest goes (the oldest are the ones in use and in the ledger)
	local list = self:Salts()
	while #list > Notary.MAX_SALTS do
		local victim = table.remove(list)
		salts[victim.fp] = nil
		state.stats.dropped = state.stats.dropped + 1
	end
	if not salts[fp] then return false, "full" end
	state.stats.added = state.stats.added + 1
	emit("SALT_CHANGED", #list)
	return true
end

-- Forgets every salt of the current guild (a demoted officer).
function Notary:Wipe()
	local data = ns.GuildKey and ns.GuildKey:Data()
	if data and data.salts ~= nil then
		data.salts = nil
		emit("SALT_CHANGED", 0)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------------------------------------------------
-- true while the client has not shown that OFFICER carries addon messages (S5): SALT messages also go by whisper.
function Notary.UseWhisper()
	local C = compat()
	return not (C and C.Feature and C:Feature("officerAddonChannel") == "available")
end

local function officerPeers()
	local out = {}
	for name, p in pairs(ns.Sync and ns.Sync:Peers() or {}) do
		if p.officer then out[#out + 1] = name end
	end
	sort(out)
	return out
end

-- Sends a SALT message: by WHISPER to `target` when given, else on OFFICER and, while S5 is unproven, by WHISPER to
-- every officer with the addon heard recently.
local function sendSalt(msg, target)
	local T = ns.Transport
	if not T then return false end
	msg.t = "SALT"
	if target then
		state.stats.whispers = state.stats.whispers + 1
		return T:Send("WHISPER", msg, { target = target, ttl = Notary.TTL, key = "SALT|" .. msg.k .. "|" .. target }) ~= nil
	end
	local ok = T:Send("OFFICER", msg, { ttl = Notary.TTL, key = "SALT|" .. msg.k }) ~= nil
	if Notary.UseWhisper() then
		for _, name in ipairs(officerPeers()) do
			if T:Send("WHISPER", msg, { target = name, ttl = Notary.TTL, key = "SALT|" .. msg.k .. "|" .. name }) then
				state.stats.whispers = state.stats.whispers + 1
				ok = true
			end
		end
	end
	return ok
end

-- Asks the other officers for the salts this client lacks (sends the fingerprints it holds). `target`: one officer by
-- whisper. Returns true when a message was queued.
function Notary:Query(target)
	if not (isOfficer() and ns.GuildKey and ns.GuildKey:Current()) then return false end
	state.lastQuery = now()
	local ok = sendSalt({ k = "q", f = fingerprints() }, target)
	if ok then state.stats.queries = state.stats.queries + 1 end
	-- nobody answers within CREATE_WAIT and there is still no salt: this officer creates it
	if state.createTimer then state.createTimer:Cancel() state.timers[state.createTimer] = nil end
	state.createTimer = after(Notary.CREATE_WAIT, function()
		state.createTimer = nil
		if isOfficer() and Notary:Count() == 0 then Notary:Create() end
	end)
	return ok
end

-- Creates a new salt and shares it. Returns its fingerprint, or nil plus a reason.
function Notary:Create()
	if not isOfficer() then return nil, "officer" end
	local raw, err = ns.Hash.RandomBytes(Notary.SALT_BYTES)
	if not raw then return nil, err end
	local b64 = ns.Config.Base64(raw)
	local ok, why = self:AddSalt(b64, now())
	if not ok then return nil, why end
	state.stats.created = state.stats.created + 1
	sendSalt({ k = "s", s = { { b = b64, at = now() } } })
	state.stats.shares = state.stats.shares + 1
	return Notary.Fingerprint(raw)
end

-- Shares the salts with these fingerprints after a short random delay (several officers may hold them: the first
-- share on OFFICER makes the others stand down).
local function scheduleShare(fps, target)
	local key = target or "*"
	state.share = state.share or {}
	local entry = state.share[key]
	if not entry then
		entry = { fps = {} }
		state.share[key] = entry
		entry.timer = after(between(Notary.SHARE_DELAY), function()
			state.share[key] = nil
			local list = {}
			for _, s in ipairs(Notary:Salts()) do
				if entry.fps[s.fp] then list[#list + 1] = { b = s.b64, at = s.at } end
			end
			if #list == 0 then return end
			if sendSalt({ k = "s", s = list }, target) then state.stats.shares = state.stats.shares + 1 end
		end)
	end
	for _, fp in ipairs(fps) do entry.fps[fp] = true end
end

local function onQuery(msg, sender, dist)
	state.stats.queriesHeard = state.stats.queriesHeard + 1
	local theirs = {}
	for _, fp in ipairs(type(msg.f) == "table" and msg.f or {}) do
		if type(fp) == "string" then theirs[fp] = true end
	end
	local mine, lacking = {}, {}
	for _, s in ipairs(Notary:Salts()) do
		mine[s.fp] = true
		if not theirs[s.fp] then lacking[#lacking + 1] = s.fp end
	end
	-- a question that came by whisper is answered by whisper: that officer may not hear OFFICER
	local target = (dist == "WHISPER" or Notary.UseWhisper()) and sender or nil
	if #lacking > 0 then scheduleShare(lacking, target) end
	for fp in pairs(theirs) do
		if not mine[fp] then
			if not state.lastQuery or now() - state.lastQuery >= Notary.REASK then Notary:Query(target) end
			break
		end
	end
end

local function onShare(msg, dist)
	state.stats.sharesHeard = state.stats.sharesHeard + 1
	local heard = {}
	for i, e in ipairs(type(msg.s) == "table" and msg.s or {}) do
		if i > Notary.MAX_SALTS then break end
		if type(e) == "table" then
			Notary:AddSalt(e.b, e.at)
			local raw = type(e.b) == "string" and ns.Config.Base64Decode(e.b)
			if raw and #raw == Notary.SALT_BYTES then heard[Notary.Fingerprint(raw)] = true end
		end
	end
	-- another officer shared on OFFICER what this client was about to share there: stand down
	local pending = state.share and state.share["*"]
	if dist == "OFFICER" and pending then
		for fp in pairs(heard) do pending.fps[fp] = nil end
		if not next(pending.fps) then
			if pending.timer then pending.timer:Cancel() state.timers[pending.timer] = nil end
			state.share["*"] = nil
		end
	end
end

function Notary:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" or msg.t ~= "SALT" then return end
	if dist ~= "OFFICER" and dist ~= "WHISPER" then state.stats.ignored = state.stats.ignored + 1 return end
	if not (isOfficer() and ns.GuildKey and ns.GuildKey:Current()) then state.stats.ignored = state.stats.ignored + 1 return end
	local member = ns.Store and ns.Store:Member(sender)
	if not (member and member.officer) then state.stats.ignored = state.stats.ignored + 1 return end
	if msg.k == "q" then onQuery(msg, sender, dist)
	elseif msg.k == "s" then onShare(msg, dist) end
end

---------------------------------------------------------------------------------------------------------------------
-- The notary
---------------------------------------------------------------------------------------------------------------------
-- true when this client can notarize a vote now: an officer holding a salt.
function Notary:CanNotarize()
	return isOfficer() and self:Current() ~= nil
end

-- The officers with the addon heard recently who may notarize a vote of `voter` (GUID), best first, without the names
-- in `exclude` ({ [name] = true }): a list of { name, guid }.
function Notary:Candidates(voter, exclude)
	local out = {}
	local H = ns.Hash
	for name, p in pairs(ns.Sync and ns.Sync:Peers() or {}) do
		if p.officer and not (exclude and exclude[name]) then
			-- Hash.Fast is linear in the bytes: with the officer's GUID only at one end, two officers whose GUIDs differ in
			-- the last digits would keep the same order for every voter; on both ends the order changes with the voter
			local g = tostring(p.guid)
			out[#out + 1] = { name = name, guid = p.guid, rank = H.Fast(g .. "|" .. tostring(voter) .. "|" .. g) }
		end
	end
	sort(out, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.name < b.name end)
	for _, c in ipairs(out) do c.rank = nil end
	return out
end

-- Who notarizes a vote of `voter` now: "self" when this client can, else the name and GUID of the best officer not in
-- `exclude`, else nil (nobody: the vote waits in the queue, LIKE-05).
function Notary:Choose(voter, exclude)
	if self:CanNotarize() then return "self" end
	local best = self:Candidates(voter, exclude)[1]
	if best then return best.name, best.guid end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Start, role changes, debug
---------------------------------------------------------------------------------------------------------------------
-- An officer asks for the salt a little after login (or after becoming an officer).
function Notary:Start()
	if not self.AUTO or not isOfficer() or not (ns.GuildKey and ns.GuildKey:Current()) then return false end
	if state.queryTimer then return true end
	state.queryTimer = after(between(Notary.QUERY_DELAY), function()
		state.queryTimer = nil
		Notary:Query()
	end)
	return true
end

function Notary:OnRoleChanged(role, key, oldRole, oldKey)
	local officerNow = role == "officer" or role == "gm"
	local officerBefore = oldRole == "officer" or oldRole == "gm"
	if key and key == oldKey and officerBefore and not officerNow then
		-- demoted: the salt is for officers only
		resetState()
		local data = ns.GuildKey and ns.GuildKey:Data(key)
		if data then data.salts = nil end
		emit("SALT_CHANGED", 0)
	elseif officerNow and not officerBefore and key == oldKey then
		self:Start()
	end
end

function Notary:OnGuildChanged(key)
	resetState()
	if key then self:Start() end
end

function Notary:DebugLines()
	local s = state.stats
	local C = compat()
	return {
		("Notary: %s, %d salt(s) held; officer channel %s%s"):format(isOfficer() and "officer" or "not an officer", self:Count(),
			C and C.Feature and tostring(C:Feature("officerAddonChannel")) or "?", Notary.UseWhisper() and " (salt also by whisper)" or ""),
		("  asked %d, questions heard %d, shared %d, shares heard %d, whispers %d, created %d, added %d, ignored %d"):format(
			s.queries, s.queriesHeard, s.shares, s.sharesHeard, s.whispers, s.created, s.added, s.ignored),
	}
end

if ns.addon then
	ns.addon.Notary = Notary
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Notary", function() return Notary:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("NET_MESSAGE", function(msg, sender, dist)
			if ns.Hash then ns.Hash.Stir(sender) end   -- arrival times feed the entropy pool of the salt
			if type(msg) == "table" and msg.t == "SALT" then Notary:OnMessage(msg, sender, dist) end
		end)
		ns.Bus:On("ROLE_CHANGED", function(...) Notary:OnRoleChanged(...) end)
		ns.Bus:On("GUILD_CHANGED", function(key) Notary:OnGuildChanged(key) end)
	end
	if ns.OnEnable then ns.OnEnable(function() Notary:Start() end) end
end

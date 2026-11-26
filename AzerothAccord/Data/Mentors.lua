-- Mentors: the members who offer to help new members, and the pairs suggested to the officers (M12.5; SPEC-16 §6,
-- MEN-01..MEN-04; SPEC-07; SPEC-10 Q37, Q38; ADR 0026). Lua 5.1.
--
-- The set `mentor` is an ordinary set of the guild (GUILD, summary per author), one record per account that offers:
--   M:<GUID>   <GUID> = the character the mentor wants to be reached on. Either { on = true, topics = { up to 6 of
--              TOPICS } or nil, note = up to NOTE_MAX bytes or nil } or, once the mentor left, { off = true }.
-- MEN-01 only the own offer (its author is that character or one of its account; an officer may relay it, not write it),
-- MEN-02 the shape, MEN-03 one per account (Join refuses "account"; the interface shows the oldest), MEN-04 at most
-- WRITES_PER_HOUR revisions of one author an hour are taken ("rate"); a leaving is never refused for it.
-- Nothing exists before a click (the offer is off by default), and leaving is always possible.
--
-- The pairs are computed on an officer's client when they are shown, from the time played together (Data/Social.lua), the
-- communities of the group map, the availability map and the main's level. They are NEVER saved and NEVER sent, and nobody
-- is told about them (Q38). Only the live offers are ever suggested.
--
--   Mentors.ValidRecord(rec, store)    the owner rule of the set
--   Mentors:List(topic)                the live offers, one per account, in the roster: { account, guid, name, main,
--                                      classFile, level, online, own, topics, note, rec }, by name
--   Mentors:Own()                      this account's offer that is listed, or nil
--   Mentors:Join(topics, note)         offers this character; Mentors:Edit(topics, note) changes the account's offer;
--                                      Mentors:Leave() takes every offer of the account back
--   Mentors:Newcomers(t)               officers: the new members (an open trial, or a join in the last NEW_DAYS days),
--                                      the oldest first: { account, guid, name, since, joined, trial }
--   Mentors:Pairs(t)                   officers: { computing, mentors = how many offer, rows = { newcomer + mentors =
--                                      { { account, guid, name, online, first, together, shared, sameGroup, hours } } } }
--   Mentors:PairsFor(guid, t)          the row of the new member's account (or nil) and the whole result
-- Who sees the pairs: Mentors.PAIRS_VISIBLE_TO, the one place. It is a rule of the interface: co-play reaches the guild.
-- Switch: Core/Features.lua "recruit" (store def `feature = "recruit"`). Bus: MENTORS_CHANGED().
local ADDON_NAME, ns = ...
ns = ns or {}
local Mentors = {}
ns.Mentors, ns.modules = Mentors, ns.modules or {}
ns.modules.Mentors = Mentors

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, min = math.floor, math.min
local sort = table.sort
local DAY, HOUR = 86400, 3600

Mentors.SET = "mentor"
Mentors.TOPICS = { "raids", "dungeons", "pvp", "professions", "leveling", "addons" }
Mentors.NOTE_MAX = 80                 -- bytes
Mentors.OFF_DAYS = 60                 -- a leaving is kept this long
Mentors.WRITES_PER_HOUR = 10          -- MEN-04
Mentors.NEW_DAYS = 30                 -- a join this recent makes a new member
Mentors.MAX_PER_NEWCOMER = 3
Mentors.MAX_PER_MENTOR = 3            -- first choices
Mentors.PAIRS_VISIBLE_TO = "officers" -- "officers" or "members" (SPEC-10 Q37): the one place

local TOPIC = {}
for _, id in ipairs(Mentors.TOPICS) do TOPIC[id] = true end

local function store() return ns.Store end
local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function me() return compat().Player.GUID() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

function Mentors.Enabled() return ns.Features ~= nil and ns.Features.On("recruit") end

-- true when the connected character may see the suggested pairs.
function Mentors.CanSeePairs()
	if not (Mentors.Enabled() and ns.Role) then return false end
	if Mentors.PAIRS_VISIBLE_TO == "members" then return ns.Role:InGuild() == true end
	return ns.Role:IsOfficer() == true
end

---------------------------------------------------------------------------------------------------------------------
-- The record (MEN-01, MEN-02)
---------------------------------------------------------------------------------------------------------------------
function Mentors.IdOf(guid) return "M:" .. tostring(guid) end

-- The character of a record id, or nil.
function Mentors.CharOf(id)
	local guid = type(id) == "string" and id:match("^M:(.+)$") or nil
	if guid and #guid <= 40 and guid:find(store().GUID_PATTERN) then return guid end
	return nil
end

local function validTopics(list)
	if type(list) ~= "table" then return false end
	local n, seen = 0, {}
	for _, id in pairs(list) do
		if not TOPIC[id] or seen[id] then return false end
		seen[id] = true
		n = n + 1
	end
	if n > #Mentors.TOPICS then return false end
	for i = 1, n do if list[i] == nil then return false end end
	return true
end

local function validNote(note)
	return type(note) == "string" and #note <= Mentors.NOTE_MAX and not note:find("[%c|]")
end

local FIELDS = { id = true, author = true, rev = true, time = true }

function Mentors.ValidRecord(rec, s)
	s = s or store()
	local guid = type(rec) == "table" and Mentors.CharOf(rec.id)
	if not (guid and s:SameAccount(guid, rec.author)) then return false end
	local off = rec.off ~= nil
	for k in pairs(rec) do
		if not (FIELDS[k] or (off and k == "off") or (not off and (k == "on" or k == "topics" or k == "note"))) then return false end
	end
	if off then return rec.off == true end
	if rec.on ~= true then return false end
	if rec.topics ~= nil and not validTopics(rec.topics) then return false end
	return rec.note == nil or validNote(rec.note)
end

function Mentors.Expired(rec, t)
	return type(rec) ~= "table" or (rec.off == true and (rec.time or 0) < t - Mentors.OFF_DAYS * DAY)
end

---------------------------------------------------------------------------------------------------------------------
-- Rate (MEN-04)
---------------------------------------------------------------------------------------------------------------------
local received, written = {}, {}   -- author -> times (received); the times this client wrote an offer

local function recent(list, t)
	local keep = {}
	for _, at in ipairs(list or {}) do if at > t - HOUR then keep[#keep + 1] = at end end
	return keep
end

-- The rate rule of a received revision (Net/Store.lua `rate`): a revision written within the last hour counts against its
-- author; true while the author stays within WRITES_PER_HOUR. A leaving that follows an offer held here is always taken
-- (a member leaves the list at any time).
function Mentors.Within(rec)
	if type(rec) ~= "table" then return true end
	if rec.off == true then
		local held = store():Get(Mentors.SET, rec.id)
		if held and held.on == true then return true end
	end
	local t, at = now(), rec.time or 0
	if at <= t - HOUR then return true end
	local list = recent(received[rec.author], t)
	received[rec.author] = list
	if #list >= Mentors.WRITES_PER_HOUR then return false end
	list[#list + 1] = at
	return true
end

function Mentors:ResetRates() received, written = {}, {} end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function accountOf(guid) return ns.Accounts and ns.Accounts:AccountKey(guid) or guid end

local function inGuild(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	if e and not e.notInGuild then return e end
	return nil
end

local function mainOf(guid)
	local main = ns.Accounts and ns.Accounts:MainOf(guid)
	return main and inGuild(main.guid) or inGuild(guid)
end

-- true when `a` was offered before `b` (MEN-03: the one shown of an account with two).
local function older(a, b)
	if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) < (b.time or 0) end
	return a.id < b.id
end

-- account -> the record shown, over the live offers of characters in the roster.
local function live()
	local out = {}
	if not Mentors.Enabled() then return out end
	for id, rec in pairs(store():Records(Mentors.SET)) do
		local guid = Mentors.CharOf(id)
		if guid and type(rec) == "table" and rec.on == true and inGuild(guid) then
			local key = accountOf(guid)
			if not out[key] or older(rec, out[key]) then out[key] = rec end
		end
	end
	return out
end

local function entryOf(account, rec, mine)
	local guid = Mentors.CharOf(rec.id)
	local e, main = inGuild(guid), mainOf(guid)
	local topics = {}
	for i, id in ipairs(rec.topics or {}) do topics[i] = id end
	return { account = account, guid = guid, name = e.short or e.name or "?", main = main.short or main.name or "?",
		classFile = e.classFile, level = main.level or 0, online = e.online == true, own = account == mine, topics = topics,
		note = rec.note, rec = rec }
end

local function byName(a, b)
	local x, y = a.name:lower(), b.name:lower()
	if x ~= y then return x < y end
	return a.account < b.account
end

-- The mentor list, which every member sees; `topic` keeps those who help with it.
function Mentors:List(topic)
	local out = {}
	local mine = me() and accountOf(me())
	for account, rec in pairs(live()) do
		local m = entryOf(account, rec, mine)
		local keep = topic == nil
		for _, id in ipairs(m.topics) do if id == topic then keep = true end end
		if keep then out[#out + 1] = m end
	end
	sort(out, byName)
	return out
end

-- Every offer record (on) of this account, the oldest first.
local function ownOffers()
	local out, mine = {}, me()
	if not (mine and Mentors.Enabled()) then return out end
	local key = accountOf(mine)
	for id, rec in pairs(store():Records(Mentors.SET)) do
		local guid = Mentors.CharOf(id)
		if guid and type(rec) == "table" and rec.on == true and (store():SameAccount(mine, guid) or accountOf(guid) == key) then
			out[#out + 1] = rec
		end
	end
	sort(out, older)
	return out
end

-- The offer of this account that the others see (a character in the roster; the own one even before the roster is read).
function Mentors:Own()
	for _, rec in ipairs(ownOffers()) do
		local guid = Mentors.CharOf(rec.id)
		if guid == me() or inGuild(guid) then return rec end
	end
	return nil
end

-- The own character's record, offer or leaving (the What I share panel).
function Mentors:OwnRecord()
	return self:Own() or (me() and Mentors.Enabled() and store():Get(Mentors.SET, Mentors.IdOf(me()))) or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (the own account only)
---------------------------------------------------------------------------------------------------------------------
-- The note as it is saved: no control character, no |, no space at the ends.
function Mentors.CleanNote(text)
	if type(text) ~= "string" then return "" end
	text = text:gsub("%c", " "):gsub("|", "")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The topics in the order of TOPICS, each once; nil and "topics" for an unknown one.
local function cleanTopics(topics)
	local chosen = {}
	for _, id in ipairs(topics or {}) do
		if not TOPIC[id] then return nil, "topics" end
		chosen[id] = true
	end
	local out = {}
	for _, id in ipairs(Mentors.TOPICS) do if chosen[id] then out[#out + 1] = id end end
	return out
end

local function ready()
	if not Mentors.Enabled() then return false, "off" end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	if not me() then return false, "player" end
	return true
end

local function write(id, topics, note)
	local list, why = cleanTopics(topics)
	if not list then return nil, why end
	note = Mentors.CleanNote(note)
	if #note > Mentors.NOTE_MAX then return nil, "note" end
	local t = now()
	written = recent(written, t)
	if #written >= Mentors.WRITES_PER_HOUR then return nil, "rate" end
	local rec, reason = store():Put(Mentors.SET, id, { on = true, topics = #list > 0 and list or nil,
		note = note ~= "" and note or nil })
	if rec then written[#written + 1] = t end
	return rec, reason
end

-- Offers this character as a mentor (the click of SPEC-10 Q37). Returns the record, or nil and "off" | "guild" |
-- "player" | "account" (another character of the account is on the list) | "topics" | "note" | "rate" | a reason of
-- Store:Put.
function Mentors:Join(topics, note)
	local ok, why = ready()
	if not ok then return nil, why end
	local held = self:Own()
	if held and Mentors.CharOf(held.id) ~= me() then return nil, "account" end
	return write(Mentors.IdOf(me()), topics, note)
end

-- Changes the offer of the account (also from another of its characters). Returns the record, or nil and a reason.
function Mentors:Edit(topics, note)
	local ok, why = ready()
	if not ok then return nil, why end
	local held = self:Own()
	if not held then return nil, "none" end
	return write(held.id, topics, note)
end

-- Leaves the mentor list: a new revision `off` for every offer of the account, so that it reaches everybody. Never held
-- back by the rate. Returns true and how many, or false and a reason ("none": nothing to leave).
function Mentors:Leave()
	local ok, why = ready()
	if not ok then return false, why end
	local n, failed = 0, nil
	for _, rec in ipairs(ownOffers()) do
		local put, reason = store():Put(Mentors.SET, rec.id, { off = true })
		if put then n = n + 1 else failed = reason end
	end
	if n == 0 then return false, failed or "none" end
	return true, n
end

---------------------------------------------------------------------------------------------------------------------
-- The suggested pairs (officers; computed when shown, never saved, never sent)
---------------------------------------------------------------------------------------------------------------------
-- The new members as this officer sees them: the accounts with an open trial (M12.3) and those with a join in the
-- timeline of the last NEW_DAYS days, still in the roster; the one who came first first.
function Mentors:Newcomers(t)
	local out = {}
	if not Mentors.CanSeePairs() then return out end
	t = t or now()
	local byAccount = {}
	local function entry(guid)
		local e = inGuild(guid)
		if not e then return nil end
		local key = accountOf(guid)
		local n = byAccount[key]
		if not n then
			n = { account = key, guid = guid, name = e.short or e.name or "?", classFile = e.classFile }
			byAccount[key] = n
			out[#out + 1] = n
		end
		return n, e
	end
	for _, ev in ipairs(ns.Timeline and ns.Timeline:All() or {}) do
		if ev.k == "join" and (ev.b or 0) >= t - Mentors.NEW_DAYS * DAY then
			local n, e = entry(ev.g)
			if n and (not n.joined or ev.b < n.joined) then
				n.joined, n.guid, n.name, n.classFile = ev.b, ev.g, e.short or e.name or "?", e.classFile
			end
		end
	end
	local Tr = ns.Trials
	for _, row in ipairs(Tr and Tr:Rows(t).open or {}) do
		local n = entry(row.guid)
		if n then
			n.trial = true
			local started = (Tr.Number(row.rec.start) or 0) * DAY
			if not n.trialSince or started < n.trialSince then n.trialSince = started end
		end
	end
	for _, n in ipairs(out) do n.since = n.joined or n.trialSince or t end
	sort(out, function(a, b)
		if a.since ~= b.since then return a.since < b.since end
		return a.account < b.account
	end)
	return out
end

-- The time two accounts played with the same others: Σ over their common partners c of min(minutes(m, c), minutes(n, c)).
function Mentors.Shared(graph, m, n)
	local a, b = graph[m], graph[n]
	if not (a and b) then return 0 end
	local total = 0
	for c, minutes in pairs(a) do
		if c ~= m and c ~= n and b[c] then total = total + min(minutes, b[c]) end
	end
	return total
end

-- The order of two candidates for one new member (SPEC-16 §6.4): together, in common, same group, common hours, the level
-- of the mentor's main, the name.
function Mentors.Better(a, b)
	if a.together ~= b.together then return a.together > b.together end
	if a.shared ~= b.shared then return a.shared > b.shared end
	if a.sameGroup ~= b.sameGroup then return a.sameGroup end
	if a.hours ~= b.hours then return a.hours > b.hours end
	if a.level ~= b.level then return a.level > b.level end
	return byName(a, b)
end

local function candidate(m, newcomer, graph, labels)
	local row = graph[m.account]
	local la, lb = labels[m.account], labels[newcomer.account]
	return { account = m.account, guid = m.guid, name = m.name, classFile = m.classFile, level = m.level, online = m.online,
		together = row and row[newcomer.account] or 0, shared = Mentors.Shared(graph, m.account, newcomer.account),
		sameGroup = la ~= nil and la == lb,
		hours = ns.Availability and ns.Availability:Common(m.account, newcomer.account) or 0 }
end

function Mentors:Pairs(t)
	local out = { computing = false, mentors = 0, rows = {} }
	if not Mentors.CanSeePairs() then return out end
	local newcomers = self:Newcomers(t)
	local isNew = {}
	for _, n in ipairs(newcomers) do isNew[n.account] = true end
	local mentors = {}
	for _, m in ipairs(self:List()) do
		if not isNew[m.account] then mentors[#mentors + 1] = m end
	end
	out.mentors = #mentors
	if #newcomers == 0 then return out end
	local S = ns.Social
	local result = S and S:Result()
	if S and not result then out.computing = true end
	local graph = result and result.graph or {}
	local map = result and ns.GroupMap and ns.GroupMap:Current()
	local labels = map and map.labels or {}
	local firsts = {}
	for _, n in ipairs(newcomers) do
		local ranked = {}
		for _, m in ipairs(mentors) do ranked[#ranked + 1] = candidate(m, n, graph, labels) end
		sort(ranked, Mentors.Better)
		-- the first choice is the best one who is not already the first choice of MAX_PER_MENTOR new members
		local first
		for i, c in ipairs(ranked) do
			if (firsts[c.account] or 0) < Mentors.MAX_PER_MENTOR then first = i break end
		end
		local chosen = {}
		if first then
			local c = ranked[first]
			c.first = true
			firsts[c.account] = (firsts[c.account] or 0) + 1
			chosen[1] = c
		end
		for i, c in ipairs(ranked) do
			if #chosen >= Mentors.MAX_PER_NEWCOMER then break end
			if i ~= first then chosen[#chosen + 1] = c end
		end
		out.rows[#out.rows + 1] = { account = n.account, guid = n.guid, name = n.name, classFile = n.classFile, since = n.since,
			joined = n.joined, trial = n.trial == true, mentors = chosen }
	end
	return out
end

function Mentors:PairsFor(guid, t)
	if not (Mentors.CanSeePairs() and type(guid) == "string") then return nil end
	local key = accountOf(guid)
	local is = false
	for _, n in ipairs(self:Newcomers(t)) do if n.account == key then is = true break end end
	if not is then return nil end   -- nothing is computed for somebody who is not new
	local result = self:Pairs(t)
	for _, row in ipairs(result.rows) do if row.account == key then return row, result end end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
-- Counts only (SPEC-09 §6).
function Mentors:DebugLine()
	local on, off = 0, 0
	for _, rec in pairs(store():Records(Mentors.SET)) do
		if rec.on == true then on = on + 1 else off = off + 1 end
	end
	return ("  mentors: offers %d, left %d"):format(on, off)
end

if ns.addon then
	ns.addon.Mentors = Mentors
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set) if set == Mentors.SET then emit("MENTORS_CHANGED") end end)
		ns.Bus:On("GUILD_CHANGED", function()
			Mentors:ResetRates()
			emit("MENTORS_CHANGED")
		end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Mentors.Enabled() then return end
			if ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Mentors", function() return { Mentors:DebugLine() } end)
			end
		end)
	end
end

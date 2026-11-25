-- Season: the guild's raid seasons and each raider's declaration for the season (M10.3; SPEC-14 §4; SPEC-10 Q20, Q21).
-- Lua 5.1.
--
-- The data set `season` (Net/Store.lua, SPEC-03 §9), synced on GUILD like the others, holds two kinds of record:
--   S:<n>          a season: { kind = "season", n, name, start (YYYYMMDD), opened (time), closed? (time) }. Written only
--                  by Raid.WRITERS (officers and the Guild Master, Q21) and passed on only by officers (NET-12, `authorAny`:
--                  it stays valid after its officer was demoted). The current season is the highest n without `closed`.
--   E:<n>:<GUID>   the declaration of the character GUID for season n: { kind = "entry", n, class, ms1 = { spec, role },
--                  ms2?, os?, note, unsure, first, conv? }. Written only by the character's own account (SEA-01).
-- The trust rules SEA-01..SEA-06 of SPEC-14 §4.2, each from one constant below:
--   SEA-01 only the own entry: an entry whose author is not of the declared character's account is refused ("owner"),
--          an officer's entry for another member too. An officer may still relay a member's entry unchanged (NET-11).
--   SEA-02 locked for the season (Q20): MS1, MS2, OS, the class and "not sure yet" change freely for Season.LOCK seconds
--          after `first`, then never while the season lasts ("locked"); the note always changes; an entry "not sure yet"
--          becomes a declaration once (`first` starts again, `conv` stays true). `first` never changes otherwise.
--   SEA-03 an existing, open season: an entry for a season this client has not seen yet waits Season.WAIT seconds for it
--          (Store `wait`), then is dropped (it comes again with the sync); one for a closed season is taken only when it
--          was written before the season closed (`first` before `closed`, `time` at most Store.MAX_FUTURE after it).
--   SEA-04 valid content: the class (as the roster gives it, when it does), the tree and the role from Data/Specs.lua, MS2
--          and OS other than MS1, a note of at most Season.NOTE_MAX characters without control characters or "|".
--   SEA-05 one character per account and season (Q20): writing is refused for a second character of the account; of
--          entries received from two characters of one account the oldest `first` shows (then the smaller GUID), the
--          other is kept but not shown.
--   SEA-06 with FDCP as the source of the season roster (Integrations "raid" = "fdcp") no entry is written
--          (Declare: false, "source"); received entries are kept (for a return to Accord) but not shown.
-- Retention (Q20): the current season and Season.KEEP previous ones with their entries; an older season and its entries
-- go Season.DROP_AFTER seconds after the season Season.KEEP + 1 places later was opened.
--
-- Provider: Integrations.OWN (Data/Integrations.lua) answers for Accord's season roster from here: Level, Season,
-- Entries, Entry, Lineup (Data/Composition.lua, M10.7), CanDeclare, Gaps.
-- Switch: Core/Features.lua "season" (M10). Off: the set takes nothing and sends nothing (Store `feature`), nothing here
-- writes, and the Season view has no tab.
-- Bus: SEASON_CHANGED() when a season or an entry changed, locally or received, or the source changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Season = {}
ns.Season, ns.modules = Season, ns.modules or {}
ns.modules.Season = Season

-- Who opens and closes a season (and later sets the target composition and the lineup): the one place of SPEC-10 Q21.
local Raid = ns.Raid or {}
ns.Raid = Raid
Raid.WRITERS = "officers"

local type, pairs, ipairs, tostring, tonumber, floor, sort = type, pairs, ipairs, tostring, tonumber, math.floor, table.sort

local DAY = 86400
Season.SET = "season"
Season.LOCK = 30 * 60          -- SEA-02, Q20: the minutes to correct a typing error after the first write
Season.KEEP = 3                -- Q20: the previous seasons kept besides the current one
Season.DROP_AFTER = 30 * DAY   -- an older season goes this long after the season KEEP + 1 places later opened
Season.WAIT = 600              -- SEA-03: how long an entry waits for its season
Season.WAIT_MAX = 200          -- entries waiting at most (the oldest go first)
Season.NAME_MAX = 32
Season.NOTE_MAX = 80
Season.N_MAX = 99999

local function now() return ns.Compat and ns.Compat.ServerTime() or time() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function S() return ns.Store end

function Season.Enabled()
	return ns.Features ~= nil and ns.Features.On("season")
end

-- Whether this character may open or close a season (Raid.WRITERS).
function Raid.CanWrite()
	if Raid.WRITERS == "officers" then return ns.Role ~= nil and ns.Role:IsOfficer() end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Ids and validation
---------------------------------------------------------------------------------------------------------------------
function Season.SeasonId(n) return "S:" .. n end
function Season.EntryId(n, guid) return ("E:%d:%s"):format(n, guid) end

-- "S" or "E" from the id, or nil.
function Season.KindOf(rec)
	local id = type(rec) == "table" and rec.id
	if type(id) ~= "string" then return nil end
	if id:find("^S:%d+$") then return "S" end
	if id:find("^E:%d+:") then return "E" end
	return nil
end

local function count(n) return type(n) == "number" and n == floor(n) and n >= 1 and n <= Season.N_MAX end

local function cleanText(s, maxLen, minLen)
	if type(s) ~= "string" or #s < (minLen or 0) or #s > maxLen then return false end
	if s:find("[%c|]") then return false end
	return true
end
Season.CleanText = cleanText

-- A calendar day YYYYMMDD from 2000 to 2099.
local function validDay(d)
	if type(d) ~= "number" or d ~= floor(d) then return false end
	local y, m, dd = floor(d / 10000), floor(d / 100) % 100, d % 100
	return y >= 2000 and y <= 2099 and m >= 1 and m <= 12 and dd >= 1 and dd <= 31
end
Season.ValidDay = validDay

local function validSeason(rec)
	if rec.kind ~= "season" or not count(rec.n) or rec.id ~= Season.SeasonId(rec.n) then return false end
	if not cleanText(rec.name, Season.NAME_MAX, 1) or not validDay(rec.start) then return false end
	if type(rec.opened) ~= "number" then return false end
	if rec.closed ~= nil and type(rec.closed) ~= "number" then return false end
	return true
end

local function pick(p)
	return type(p) == "table" and type(p.spec) == "string" and type(p.role) == "string"
end

local function sameSpec(a, b)
	if a == nil or b == nil then return a == b end
	return a.spec == b.spec and a.role == b.role
end
Season.SameSpec = sameSpec

-- SEA-04: the content of an entry, without its season and its author.
function Season.ValidContent(rec)
	local Specs = ns.Specs
	if type(rec.class) ~= "string" or #rec.class > 16 then return false end
	if rec.note ~= nil and not cleanText(rec.note, Season.NOTE_MAX) then return false end
	if type(rec.first) ~= "number" then return false end
	if rec.conv ~= nil and rec.conv ~= true then return false end
	if rec.unsure == true then
		return rec.ms1 == nil and rec.ms2 == nil and rec.os == nil
	end
	if rec.unsure ~= nil and rec.unsure ~= false then return false end
	if not (Specs and Specs.Known(rec.class)) then return false end
	if not (pick(rec.ms1) and Specs.Valid(rec.class, rec.ms1.spec, rec.ms1.role)) then return false end
	for _, k in ipairs({ "ms2", "os" }) do
		local p = rec[k]
		if p ~= nil then
			if not (pick(p) and Specs.Valid(rec.class, p.spec, p.role)) then return false end
			if sameSpec(p, rec.ms1) then return false end
		end
	end
	if rec.ms2 and rec.os and sameSpec(rec.ms2, rec.os) then return false end
	return true
end

-- The GUID of the character an entry declares, from its id.
function Season.EntryChar(rec)
	local id = type(rec) == "table" and rec.id
	return type(id) == "string" and id:match("^E:%d+:(.+)$") or nil
end

-- The owner rule of the set (Net/Store.lua): true, or false and a reason ("owner", "class", "wait", "closed").
function Season.ValidRecord(rec, store)
	store = store or S()
	local kind = Season.KindOf(rec)
	if kind == "S" then return validSeason(rec) end
	if kind ~= "E" then return false end
	local char = Season.EntryChar(rec)
	if rec.kind ~= "entry" or not count(rec.n) or not char or not char:find(ns.Store.GUID_PATTERN)
		or rec.id ~= Season.EntryId(rec.n, char) then return false end
	if not store:SameAccount(char, rec.author) then return false, "owner" end          -- SEA-01
	if not Season.ValidContent(rec) then return false end                              -- SEA-04
	local member = ns.Roster and ns.Roster.ByGUID and ns.Roster:ByGUID(char)
	if member and member.classFile and member.classFile ~= rec.class then return false, "class" end
	local s = store:Get(Season.SET, Season.SeasonId(rec.n))                          -- SEA-03
	if not s then return false, "wait" end
	if s.closed and (rec.first >= s.closed or rec.time > s.closed + ns.Store.MAX_FUTURE) then return false, "closed" end
	return true
end

-- SEA-02 for an entry (and the seasons: a closed season stays closed): may `rec` replace `held`? true, or false and
-- "locked".
function Season.Transition(held, rec)
	if Season.KindOf(rec) == "S" then
		if held.closed and not rec.closed then return false, "locked" end
		return true
	end
	if held.n ~= rec.n then return false, "locked" end
	if held.conv and not rec.conv then return false, "locked" end
	local same = held.class == rec.class and (held.unsure == true) == (rec.unsure == true)
		and sameSpec(held.ms1, rec.ms1) and sameSpec(held.ms2, rec.ms2) and sameSpec(held.os, rec.os)
	if same then
		if rec.first ~= held.first or (rec.conv == true) ~= (held.conv == true) then return false, "locked" end
		return true                                    -- only the note (or nothing) changed
	end
	if (rec.time or 0) - held.first <= Season.LOCK then
		if rec.first ~= held.first or (rec.conv == true) ~= (held.conv == true) then return false, "locked" end
		return true                                    -- the window to correct an error
	end
	-- "not sure yet" becomes a declaration, once
	if held.unsure == true and not held.conv and rec.unsure ~= true and rec.conv == true
		and rec.first > held.first and rec.first <= (rec.time or 0) then
		return true
	end
	return false, "locked"
end

-- True when the entry's specs can no longer change (at time t).
function Season.IsLocked(rec, t)
	if type(rec) ~= "table" or type(rec.first) ~= "number" then return false end
	return (t or now()) - rec.first > Season.LOCK
end

-- Retention (Q20): true when a season KEEP + 1 places later was opened more than DROP_AFTER ago.
function Season.Expired(rec, t)
	local n = type(rec) == "table" and rec.n
	if not count(n) then return false end
	for _, s in pairs(S():Records(Season.SET)) do
		if Season.KindOf(s) == "S" and type(s.n) == "number" and s.n >= n + Season.KEEP + 1
			and type(s.opened) == "number" and s.opened < t - Season.DROP_AFTER then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Entries that wait for their season (SEA-03)
---------------------------------------------------------------------------------------------------------------------
Season.waiting = {}

function Season.Wait(rec, ctx)
	local w = Season.waiting
	w[#w + 1] = { rec = ns.Store.Copy(rec), sender = ctx and ctx.sender, dist = ctx and ctx.dist, at = now() }
	while #w > Season.WAIT_MAX do table.remove(w, 1) end
end

-- Tries again the entries that wait: those whose season arrived are checked and stored; those too old are dropped.
function Season.Retry()
	local w, t = Season.waiting, now()
	if #w == 0 then return 0 end
	Season.waiting = {}
	local taken = 0
	for _, e in ipairs(w) do
		if t - e.at <= Season.WAIT then
			if S():Get(Season.SET, Season.SeasonId(e.rec.n)) then
				if S():Accept(Season.SET, e.rec, { sender = e.sender, dist = e.dist }) then taken = taken + 1 end
			else
				Season.waiting[#Season.waiting + 1] = e
			end
		end
	end
	return taken
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
-- Every season held, newest first.
function Season:List()
	local out = {}
	for _, rec in pairs(S():Records(Season.SET)) do
		if Season.KindOf(rec) == "S" and validSeason(rec) then out[#out + 1] = rec end
	end
	sort(out, function(a, b) return a.n > b.n end)
	return out
end

function Season:Get(n)
	if not count(n) then return nil end
	return S():Get(Season.SET, Season.SeasonId(n))
end

-- The current season: the highest n without `closed`, or nil.
function Season:Current()
	local list = self:List()
	local top = list[1]
	if top and not top.closed then return top end
	return nil
end

-- The highest n held (0 without any).
function Season:Top()
	local list = self:List()
	return list[1] and list[1].n or 0
end

-- The account key of a character for SEA-05: its own GUID unless an earlier GUID of the same account was seen.
local function accountOf(guid, seen)
	for _, other in ipairs(seen) do
		if S():SameAccount(guid, other) then return other end
	end
	seen[#seen + 1] = guid
	return guid
end

-- The entries of season n, one per account (SEA-05), sorted by name: { rec, guid, name, hidden = { rec... } }.
function Season:Entries(n)
	local raw = {}
	for _, rec in pairs(S():Records(Season.SET)) do
		if Season.KindOf(rec) == "E" and rec.n == n then raw[#raw + 1] = rec end
	end
	sort(raw, function(a, b)
		if a.first ~= b.first then return a.first < b.first end
		return Season.EntryChar(a) < Season.EntryChar(b)
	end)
	local out, byAccount, seen = {}, {}, {}
	for _, rec in ipairs(raw) do
		local guid = Season.EntryChar(rec)
		local key = accountOf(guid, seen)
		local row = byAccount[key]
		if row then
			row.hidden[#row.hidden + 1] = rec
		else
			local member = ns.Roster and ns.Roster:ByGUID(guid)
			row = { rec = rec, guid = guid, name = member and member.name or nil, hidden = {} }
			byAccount[key] = row
			out[#out + 1] = row
		end
	end
	sort(out, function(a, b) return tostring(a.name or a.guid) < tostring(b.name or b.guid) end)
	return out
end

-- The own entry for season n (of this character or another of the account), or nil.
function Season:Own(n)
	local me = ns.Compat and ns.Compat.Player.GUID()
	if not me or not count(n) then return nil end
	local mine = S():Get(Season.SET, Season.EntryId(n, me))
	if mine then return mine end
	for _, rec in pairs(S():Records(Season.SET)) do
		if Season.KindOf(rec) == "E" and rec.n == n and S():SameAccount(me, Season.EntryChar(rec)) then return rec end
	end
	return nil
end

function Season.Source()
	return ns.Integrations and ns.Integrations:Source("raid") or "accord"
end

---------------------------------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------------------------------
function Season:CanOpen()
	return Season.Enabled() and Raid.CanWrite()
end

-- An officer opens a new season (Q21): S:<top + 1>, and the season open until now is closed in the same operation.
-- Returns the record, or nil and a reason: "off", "officer", "name", "start", or a reason of Store:Put.
function Season:Open(name, start)
	if not Season.Enabled() then return nil, "off" end
	if not Raid.CanWrite() then return nil, "officer" end
	if type(name) == "string" then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
	if not cleanText(name, Season.NAME_MAX, 1) then return nil, "name" end
	start = start or (ns.Compat and ns.Compat.ServerDay())
	if not validDay(start) then return nil, "start" end
	local t = now()
	local n = self:Top() + 1
	local rec, why = S():Put(Season.SET, Season.SeasonId(n), { kind = "season", n = n, name = name, start = start, opened = t })
	if not rec then return nil, why end
	for _, old in ipairs(self:List()) do
		if old.n < n and not old.closed then self:Close(old.n, t) end
	end
	return rec
end

-- An officer closes season n. Returns true, or false and a reason ("off", "officer", "missing").
function Season:Close(n, t)
	if not Season.Enabled() then return false, "off" end
	if not Raid.CanWrite() then return false, "officer" end
	local old = self:Get(n)
	if not old then return false, "missing" end
	if old.closed then return true end
	local fields = ns.Store.Copy(old)
	fields.id, fields.author, fields.rev, fields.time = nil, nil, nil, nil
	fields.closed = t or now()
	local rec, why = S():Put(Season.SET, old.id, fields)
	if not rec then return false, why end
	return true
end

local function ownClass(guid)
	local member = ns.Roster and ns.Roster:ByGUID(guid)
	if member and member.classFile then return member.classFile end
	if UnitClass then
		local _, file = UnitClass("player")
		if type(file) == "string" then return file end
	end
	return nil
end

-- Whether this character can write a declaration now: (true) or (false, reason).
function Season:CanDeclare()
	if not Season.Enabled() then return false, "off" end
	if Season.Source() ~= "accord" then return false, "source" end                    -- SEA-06
	local cur = self:Current()
	if not cur then return false, "season" end
	local me = ns.Compat and ns.Compat.Player.GUID()
	if not me then return false, "player" end
	local own = self:Own(cur.n)
	if own and Season.EntryChar(own) ~= me then return false, "account" end           -- SEA-05
	return true
end

-- The player's declaration for the current season: d = { ms1 = { spec, role }, ms2?, os?, note?, unsure? }.
-- Returns the record, or nil and a reason: "off", "source", "season", "player", "account", "class", "content",
-- "locked", or a reason of Store:Put.
function Season:Declare(d)
	local ok, why = self:CanDeclare()
	if not ok then return nil, why end
	d = type(d) == "table" and d or {}
	local cur, me = self:Current(), ns.Compat.Player.GUID()
	local class = ownClass(me)
	if not class then return nil, "class" end
	local id = Season.EntryId(cur.n, me)
	local held = S():Get(Season.SET, id)
	local t = now()
	local fields = { kind = "entry", n = cur.n, class = class, note = d.note or (held and held.note) or "" }
	if d.unsure then
		fields.unsure = true
	else
		fields.unsure = false
		fields.ms1, fields.ms2, fields.os = d.ms1, d.ms2, d.os
	end
	if fields.note == "" then fields.note = nil end
	fields.first = held and held.first or t
	fields.conv = held and held.conv or nil
	if held and held.unsure == true and not held.conv and not fields.unsure and t - held.first > Season.LOCK then
		fields.first, fields.conv = t, true                                            -- "not sure yet" -> declaration, once
	end
	fields.time = t
	fields.id = id
	if not Season.ValidContent(fields) then return nil, "content" end
	if held then
		local okT = Season.Transition(held, fields)
		if not okT then return nil, "locked" end
	end
	fields.id, fields.time = nil, nil
	return S():Put(Season.SET, id, fields)
end

-- Changes only the note of the own entry (always allowed). Returns the record, or nil and a reason.
function Season:SetNote(text)
	local ok, why = self:CanDeclare()
	if not ok then return nil, why end
	local cur = self:Current()
	local held = S():Get(Season.SET, Season.EntryId(cur.n, ns.Compat.Player.GUID()))
	if not held then return nil, "missing" end
	if text ~= nil and text ~= "" and not cleanText(text, Season.NOTE_MAX) then return nil, "content" end
	local fields = ns.Store.Copy(held)
	fields.id, fields.author, fields.rev, fields.time = nil, nil, nil, nil
	fields.note = (text ~= "" and text) or nil
	return S():Put(Season.SET, held.id, fields)
end

---------------------------------------------------------------------------------------------------------------------
-- The provider of Integrations ("raid" = "accord")
---------------------------------------------------------------------------------------------------------------------
local function providerEntry(row)
	local r = row.rec
	return { name = row.name, guid = row.guid, class = r.class, role = r.ms1 and r.ms1.role or nil, ms1 = r.ms1,
		ms2 = r.ms2, os = r.os, note = r.note, unsure = r.unsure == true or nil, first = r.first }
end

Season.Provider = {
	id = "accord",
	Level = function() return Season.Enabled() and 1 or nil end,
	Season = function()
		local cur = Season:Current() or Season:List()[1]
		if not cur then return nil end
		return { id = cur.n, name = cur.name, state = cur.closed and "CLOSED" or "OPEN", start = cur.start }
	end,
	Entries = function()
		local cur = Season:Current()
		if not cur then return {} end
		local out = {}
		for _, row in ipairs(Season:Entries(cur.n)) do out[#out + 1] = providerEntry(row) end
		return out
	end,
	Entry = function(name)
		local cur = Season:Current()
		if not cur or type(name) ~= "string" then return nil end
		for _, row in ipairs(Season:Entries(cur.n)) do
			if row.name == name then return providerEntry(row) end
		end
		return nil
	end,
	Lineup = function(eventKey) return ns.Composition and ns.Composition:Names(eventKey) or nil end,
	CanDeclare = function() return (Season:CanDeclare()) end,
	Gaps = function() return {} end,
}

function Season:DebugLines()
	local list, cur = self:List(), self:Current()
	local entries = 0
	for _, rec in pairs(S():Records(Season.SET)) do
		if Season.KindOf(rec) == "E" then entries = entries + 1 end
	end
	return { ("Season: %d held, current %s, %d entries, %d waiting, source %s"):format(#list, cur and tostring(cur.n) or "none",
		entries, #Season.waiting, tostring(Season.Source())) }
end

if ns.Integrations then ns.Integrations.OWN = Season.Provider end

if ns.addon then
	ns.addon.Season, ns.addon.Raid = Season, Raid
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set ~= Season.SET or not Season.Enabled() then return end
			if type(id) == "string" and id:find("^S:") then Season.Retry() end
			emit("SEASON_CHANGED")
		end)
		ns.Bus:On("SOURCES_CHANGED", function() if Season.Enabled() then emit("SEASON_CHANGED") end end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if Season.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Season", function() return Season:DebugLines() end)
			end
		end)
	end
end

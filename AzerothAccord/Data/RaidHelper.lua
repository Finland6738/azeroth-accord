-- RaidHelper: the guild's Raid-Helper events from Discord, brought into the game by pasting their export (M10.6;
-- SPEC-14 §6; ADR 0022 points 13-14). Lua 5.1.
--
-- Accord never contacts Discord or Raid-Helper: an officer copies the export of an event (JSON or CSV, read by
-- Data/RaidHelperText.lua) and pastes it into a box (UI/RaidHelperBox.lua).
--   Matching  each sign-up goes to an account of the guild by its name on Discord, in order: a hand match this officer
--             made before; the Discord name of the contacts (M2.5: the game's field and the shared one); a character's name
--             (case, spaces, a leading "@" and "#0000" apart). A name that fits two accounts fits none. Within the account
--             the sign-up goes to the character of its class, then the one of the season declaration, then the main.
--             Two sign-ups of one account count once (the primary first).
--   Synced    the record H:<id> of the data set `raidev` (Net/Store.lua; officers only, NET-12): the title, the start (the
--             realm's date and time, as a calendar event's), the time of the import and the MATCHED members only:
--             s = { { g = GUID, st = state, role?, class?, spec? } } (at most RECORD_MAX). <id> is the Discord event id, or
--             "t<start>" for an export without one; a new import of the same event replaces the record.
--   Local     the names that matched nobody and the hand matches stay in GuildKey:Data().raidHelper on the officer's
--             computer, never sent (SPEC-10 Q22): { manual = { [normalized name] = GUID },
--             imports = { [id] = { unmatched = { names }, at, start } } }. The names go Calendar.KEEP after the event, a
--             hand match when its character is no longer in the guild. The pasted export is kept in memory only, until the
--             reload, so that a hand match can be applied to it.
--   Calendar  RaidHelper:Push(id), from the officer's confirming click: finds the guild event at that date and time (or
--             creates a guild sign-up event) and, for the matched members who gave no answer in the game, invites them and
--             writes their state where the client lets this officer (never over an answer given in the game, SPEC-10 Q25),
--             one call at a time, at most INVITE_MAX members per confirmation; an error stops and says who was left out.
--             Where Accord cannot write the state, the member finds a row in the Action Center.
-- Only Raid.WRITERS (officers and the Guild Master) import and write into the calendar.
--
-- Switch: Core/Features.lua "season" (M10). Off: nothing is imported, written, accepted, sent or shown.
-- Bus: EVENT_CHANGED("h<id>") and CALENDAR_CHANGED() after an import, a hand match or a write into the calendar.
local ADDON_NAME, ns = ...
ns = ns or {}
local RH = {}
ns.RaidHelper, ns.modules = RH, ns.modules or {}
ns.modules.RaidHelper = RH

local type, pairs, ipairs, tostring, tonumber, floor, sort, lower = type, pairs, ipairs, tostring, tonumber, math.floor,
	table.sort, string.lower

local DAY = 86400
RH.RECORD_MAX = 80            -- sign-ups of one record
RH.MAX_BYTES = 12288          -- estimated size of an H: record (about 2 KB on the wire, compressed)
RH.TITLE_BYTES = 256          -- a title of 64 characters, "|" doubled
RH.AHEAD_DAYS = 366           -- an event further ahead is a wrong date
RH.INVITE_MAX = 40            -- members written into the game calendar per confirmation
RH.CALENDAR_TITLE_MAX = 31    -- characters of a title in the game calendar [verify]
RH.CHECK_DELAY = 0.2          -- seconds after a calendar event before the next step of a write
RH.SOON = 3 * 3600            -- a row of the Action Center stays this long after the start
RH.STATES = { signed = true, late = true, bench = true, tentative = true, absence = true }
RH.STATE_ORDER = { "signed", "late", "bench", "tentative", "absence" }
RH.ANSWER = { signed = "yes", late = "yes", bench = "yes", tentative = "maybe", absence = "no" }
-- the answer -> the calendar status an officer writes (SPEC-14 §6.5)
RH.CALENDAR_STATUS = { yes = "Confirmed", maybe = "Tentative", no = "Declined" }

RH.session = {}      -- id -> { event, title, start }: the export pasted in this session, never saved
RH.result = {}       -- id -> the outcome of the last write into the game calendar
RH.job = nil         -- the write in progress

local function compat() return ns.Compat end
local function now() return compat() and compat().ServerTime() or time() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function S() return ns.Store end
local function Cal() return ns.Compat.Calendar end
local function Text() return ns.RaidHelperText end

function RH.Enabled()
	return ns.Features ~= nil and ns.Features.On("season")
end

function RH.CanImport()
	return RH.Enabled() and ns.Raid ~= nil and ns.Raid.CanWrite()
end

local function changed(id)
	emit("EVENT_CHANGED", "h" .. id)
	emit("CALENDAR_CHANGED")
end

---------------------------------------------------------------------------------------------------------------------
-- The record H:<id>
---------------------------------------------------------------------------------------------------------------------
function RH.RecordId(id) return "H:" .. id end

local function validEventId(id)
	return type(id) == "string" and (id:find("^%d+$") ~= nil or id:find("^t%d+$") ~= nil) and #id <= 24
end

-- The id of an H: record, or nil.
function RH.IdOf(rec)
	local id = type(rec) == "table" and type(rec.id) == "string" and rec.id:match("^H:(.+)$")
	return validEventId(id) and id or nil
end

-- No control character, and no "|" but in pairs.
local function safeTitle(s)
	if type(s) ~= "string" or s == "" or #s > RH.TITLE_BYTES or s:find("%c") then return false end
	return not s:gsub("||", ""):find("|", 1, true)
end

local function validRole(r)
	for _, role in ipairs(ns.Specs.ROLES) do if r == role then return true end end
	return false
end

local function validSignup(e)
	if type(e) ~= "table" or type(e.g) ~= "string" or not e.g:find(ns.Store.GUID_PATTERN) or #e.g > 40 then return false end
	if not RH.STATES[e.st] then return false end
	if e.role ~= nil and not validRole(e.role) then return false end
	if e.class ~= nil and not (type(e.class) == "string" and #e.class <= 16 and e.class:find("^%u+$")) then return false end
	if e.spec ~= nil and not (type(e.spec) == "string" and #e.spec <= 24 and e.spec:find("^[%u_]+$")) then return false end
	return true
end

-- The owner rule of an H: record (its author is an officer: Net/Store.lua checks that, NET-12).
function RH.ValidRecord(rec)
	if not RH.IdOf(rec) or not safeTitle(rec.title) then return false end
	if type(rec.start) ~= "number" or type(rec.at) ~= "number" or type(rec.s) ~= "table" then return false end
	local n, seen = 0, {}
	for k, e in pairs(rec.s) do
		n = n + 1
		if type(k) ~= "number" or k < 1 or k > RH.RECORD_MAX or k ~= floor(k) then return false end
		if not validSignup(e) or seen[e.g] then return false end
		seen[e.g] = true
	end
	return n == #rec.s
end

-- Every imported event held, oldest start first: { id, rec }.
function RH:List()
	local out = {}
	if not RH.Enabled() then return out end
	local t = now()
	for _, rec in pairs(S():Records("raidev")) do
		local id = RH.IdOf(rec)
		if id and RH.ValidRecord(rec) and not ns.Calendar.Expired(rec, t) then out[#out + 1] = { id = id, rec = rec } end
	end
	sort(out, function(a, b)
		if a.rec.start ~= b.rec.start then return a.rec.start < b.rec.start end
		return a.id < b.id
	end)
	return out
end

function RH:Get(id)
	if not (RH.Enabled() and validEventId(id)) then return nil end
	local rec = S():Get("raidev", RH.RecordId(id))
	if rec and RH.ValidRecord(rec) then return rec end
	return nil
end

-- The imported event at the date and time of a calendar event: the one with its title first, then the newest import.
-- Returns id, record, or nil.
function RH:ForEvent(e)
	local best
	for _, row in ipairs(self:List()) do
		if row.rec.start == e.start then
			local same = RH.CalendarTitle(row.rec.title) == e.title
			if not best or (same and not best.same) or (same == best.same and row.rec.at > best.rec.at) then
				best = { id = row.id, rec = row.rec, same = same }
			end
		end
	end
	if best then return best.id, best.rec end
	return nil
end

-- The title as it goes into the game calendar: "|" single, at most CALENDAR_TITLE_MAX characters.
function RH.CalendarTitle(title)
	local s = tostring(title or ""):gsub("||", "|")
	local n, i = 0, 1
	while i <= #s do
		local b = s:byte(i)
		local size = b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1
		n = n + 1
		if n > RH.CALENDAR_TITLE_MAX then return (s:sub(1, i - 1):gsub(" +$", "")) end
		i = i + size
	end
	return s
end

-- The guild event of the game calendar at the date and time of an import (the one with its title first, then a raid), or
-- nil. Also further ahead than the view's window.
function RH:EventAt(rec)
	local title = RH.CalendarTitle(rec.title)
	local best, score
	for _, e in ipairs(ns.Calendar:AllEvents()) do
		if e.start == rec.start then
			local s = (e.title == title and 2 or 0) + (e.raid and 1 or 0)
			if not best or s > score then best, score = e, s end
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------------------------
-- Local data of the officer's computer (never sent, SPEC-10 Q22)
---------------------------------------------------------------------------------------------------------------------
local function localData(create)
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	local t = data.raidHelper
	if type(t) ~= "table" then
		if not create then return nil end
		t = {}
		data.raidHelper = t
	end
	if type(t.manual) ~= "table" then t.manual = {} end
	if type(t.imports) ~= "table" then t.imports = {} end
	return t
end

-- Drops the unmatched names of events over for Calendar.KEEP (of every guild of this computer) and, once the roster is
-- known, the hand matches whose character left the current guild. Returns the number of imports dropped.
function RH:Prune()
	local db = ns.Config and ns.Config.db and ns.Config.db.account
	local t, dropped = now(), 0
	for _, data in pairs(type(db) == "table" and type(db.guilds) == "table" and db.guilds or {}) do
		local held = type(data) == "table" and data.raidHelper
		if type(held) == "table" and type(held.imports) == "table" then
			for id, imp in pairs(held.imports) do
				if type(imp) ~= "table" or type(imp.start) ~= "number" or imp.start < t - ns.Calendar.KEEP then
					held.imports[id] = nil
					self.session[id] = nil
					dropped = dropped + 1
				end
			end
		end
	end
	local own = localData()
	if own and ns.Roster and ns.Roster:Count() > 0 then
		for name, guid in pairs(own.manual) do
			if not ns.Roster:ByGUID(guid) then own.manual[name] = nil end
		end
	end
	return dropped
end

-- The names of an import that matched nobody (this computer only), or an empty list.
function RH:Unmatched(id)
	self:Prune()
	local t = localData()
	local imp = t and t.imports[id]
	return imp and imp.unmatched or {}
end

---------------------------------------------------------------------------------------------------------------------
-- Matching (SPEC-14 §6.3)
---------------------------------------------------------------------------------------------------------------------
function RH.Normalize(name)
	if type(name) ~= "string" then return nil end
	local s = lower(name):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", ""):gsub("#%d%d%d%d$", ""):gsub("%s+$", "")
	return s ~= "" and s or nil
end

local function groupOf(guid)
	return ns.Accounts and ns.Accounts:GroupOf(guid) or nil
end

-- The account of a character: the id of its group, or the character itself.
function RH.AccountKey(guid)
	local group = groupOf(guid)
	return group and group.id or guid
end

local function add(index, name, guid)
	local n = RH.Normalize(name)
	if not n then return end
	local entry = index[n]
	if not entry then
		entry = { count = 0, accounts = {} }
		index[n] = entry
	end
	local key = RH.AccountKey(guid)
	if not entry.accounts[key] then
		entry.accounts[key] = guid
		entry.count = entry.count + 1
	end
end

-- name -> accounts, by Discord name and by character name, of the guild's roster.
function RH.Index()
	local discord, chars = {}, {}
	for _, m in ipairs(ns.Roster:Members()) do
		if m.guid then
			add(discord, m.discord, m.guid)
			local rec = S():Get("contacts", m.guid)
			if rec and rec.del ~= true and ns.Contacts then add(discord, ns.Contacts.ValidateDiscord(rec.discord), m.guid) end
			add(chars, m.short or (compat().SplitName(m.name)), m.guid)
		end
	end
	return { discord = discord, chars = chars }
end

local function only(entry)
	local _, guid = next(entry.accounts)
	return guid
end

-- The character of the guild whose account a Discord name means: guid, "manual" | "discord" | "name"; or nil, "none" |
-- "ambiguous".
function RH.Match(name, index)
	local n = RH.Normalize(name)
	if not n then return nil, "none" end
	local t = localData()
	local hand = t and t.manual[n]
	if hand and ns.Roster:ByGUID(hand) then return hand, "manual" end
	local d = index.discord[n]
	if d then
		if d.count == 1 then return only(d), "discord" end
		return nil, "ambiguous"
	end
	local c = index.chars[n]
	if c then
		if c.count == 1 then return only(c), "name" end
		return nil, "ambiguous"
	end
	return nil, "none"
end

-- guid -> true for the characters declared in the current season (Accord's declarations).
local function declared()
	local out = {}
	local cur = ns.Season and ns.Season.Source() == "accord" and ns.Season:Current()
	if cur then
		for _, row in ipairs(ns.Season:Entries(cur.n)) do out[row.guid] = true end
	end
	return out
end

-- The character of the account of `guid` that a sign-up is for: of its class, else the season's, else the main, else the
-- one matched. Returns the roster entry.
function RH.Character(guid, signup, season)
	local group = groupOf(guid)
	local list = {}
	if group then
		for _, member in ipairs(group.members) do
			local entry = ns.Roster:ByGUID(member.guid)
			if entry then list[#list + 1] = entry end
		end
	end
	if #list == 0 then list[1] = ns.Roster:ByGUID(guid) end
	local function fits(e)
		if signup.class then return e.classFile == signup.class end
		return signup.classes ~= nil and signup.classes[e.classFile] == true
	end
	season = season or declared()
	local function score(e)
		return (fits(e) and 8 or 0) + (season[e.guid] and 4 or 0) + (group and group.main == e.guid and 2 or 0)
			+ (e.guid == guid and 1 or 0)
	end
	local best, top
	for _, e in ipairs(list) do
		local s = score(e)
		if not best or s > top or (s == top and e.guid < best.guid) then best, top = e, s end
	end
	return best
end

---------------------------------------------------------------------------------------------------------------------
-- Parse, preview and import
---------------------------------------------------------------------------------------------------------------------
-- The start of the realm's date and time (as a calendar event's) of a Unix time: the difference between the realm's
-- clock and the server time now, to the quarter hour (a change to summer time between now and the event is not seen:
-- the officer can write the date and time by hand).
function RH.RealmStart(unix)
	if type(unix) ~= "number" then return nil end
	local t = compat().RealmTime()
	local offset = 0
	if t then
		local stamp = ns.Calendar.Stamp(t.year, t.month, t.day, t.hour, t.minute)
		if stamp then offset = floor((stamp - now()) / 900 + 0.5) * 900 end
		if offset > 15 * 3600 or offset < -15 * 3600 then offset = 0 end
	end
	local start = unix + offset
	return start - start % 60
end

-- What an import of the parsed event would write. `opts` = { title?, start? (realm's date and time) } replace the
-- export's. Returns { id?, title, start, format, ignored, signups = { { name, state, guid, member, role, class, spec } },
-- unmatched = { names }, ambiguous = n, twice = n, over = n (matched beyond RECORD_MAX) }, or nil and a reason
-- ("title", "start").
function RH:Preview(event, opts)
	opts = opts or {}
	-- a title typed in the box (the edit box may give "|" doubled), else the export's
	local typed = type(opts.title) == "string" and opts.title:find("%S") and opts.title
	local title = event.title
	if typed then title = Text().Clean((typed:gsub("||", "|"))) end
	if not title or not safeTitle(title) then return nil, "title" end
	local start = opts.start or RH.RealmStart(event.start)
	if not start then return nil, "start" end
	local t = now()
	if start < t - ns.Calendar.KEEP + 3600 or start > t + RH.AHEAD_DAYS * DAY then return nil, "start" end
	start = start - start % 60
	local out = { id = event.id, title = title, start = start, format = event.format, ignored = event.ignored or 0,
		signups = {}, unmatched = {}, ambiguous = 0, twice = 0, over = 0 }
	local index, season = RH.Index(), declared()
	local taken, named = {}, {}
	for _, signup in ipairs(event.signups) do
		local guid, how = RH.Match(signup.name, index)
		if guid then
			local key = RH.AccountKey(guid)
			if taken[key] then
				out.twice = out.twice + 1
			elseif #out.signups >= RH.RECORD_MAX then
				taken[key] = true
				out.over = out.over + 1
			else
				taken[key] = true
				local member = RH.Character(guid, signup, season)
				local class = signup.class
				if not class and signup.classes and signup.classes[member.classFile] then class = member.classFile end
				out.signups[#out.signups + 1] = { name = signup.name, state = signup.state, guid = member.guid,
					member = member.name, role = signup.role, class = class, spec = signup.spec }
			end
		else
			if how == "ambiguous" then out.ambiguous = out.ambiguous + 1 end
			if not named[signup.name] then
				named[signup.name] = true
				out.unmatched[#out.unmatched + 1] = signup.name
			end
		end
	end
	return out
end

-- Reads a pasted text and says what its import would do. Returns the preview and the parsed event, or nil and a reason.
function RH:Check(text, opts)
	if not RH.Enabled() then return nil, "off" end
	if not RH.CanImport() then return nil, "officer" end
	local event, why = Text().Parse(text)
	if not event then return nil, why end
	local preview, reason = self:Preview(event, opts)
	if not preview then return nil, reason end
	return preview, event
end

-- The id of the record an import writes: the export's, else that of an import at the same date and time, else "t<start>".
function RH:IdFor(preview)
	if preview.id then return preview.id end
	for _, row in ipairs(self:List()) do
		if row.rec.start == preview.start then return row.id end
	end
	return "t" .. preview.start
end

-- An officer imports a parsed event (from a click). Returns id and the preview, or nil and a reason ("off", "officer",
-- "title", "start", or a reason of Store:Put).
function RH:Import(event, opts)
	if not RH.Enabled() then return nil, "off" end
	if not RH.CanImport() then return nil, "officer" end
	if self.job then return nil, "busy" end
	local preview, why = self:Preview(event, opts)
	if not preview then return nil, why end
	local id = self:IdFor(preview)
	local list = {}
	for i, s in ipairs(preview.signups) do
		list[i] = { g = s.guid, st = s.state, role = s.role, class = s.class, spec = s.spec }
	end
	local rec, reason = S():Put("raidev", RH.RecordId(id), { title = preview.title, start = preview.start, at = now(), s = list })
	if not rec then return nil, reason end
	local t = localData(true)
	if t then
		local names = {}
		for i, name in ipairs(preview.unmatched) do names[i] = name end
		t.imports[id] = { unmatched = names, at = rec.at, start = rec.start }
	end
	self.session[id] = { event = event, opts = { title = opts and opts.title, start = preview.start } }
	self.result[id] = nil
	self:Prune()
	changed(id)
	return id, preview
end

-- An officer matches a Discord name to a member (its character's name as in the roster); the match is remembered for
-- later events. With the export of event `id` still in memory the event is imported again; else it must be pasted again.
-- Returns true and "added" or "paste", or false and a reason ("off", "officer", "member", "name").
function RH:SetMatch(id, name, memberName)
	if not RH.Enabled() then return false, "off" end
	if not RH.CanImport() then return false, "officer" end
	local n = RH.Normalize(name)
	if not n then return false, "name" end
	local member = type(memberName) == "string" and ns.Roster:ByName((memberName:gsub("^%s+", ""):gsub("%s+$", "")))
	if not (member and member.guid) then return false, "member" end
	local t = localData(true)
	if not t then return false, "off" end
	t.manual[n] = member.guid
	local held = id and self.session[id]
	if held and self:Get(id) then
		local done, why = self:Import(held.event, held.opts)
		if not done then return false, why end
		return true, "added"
	end
	changed(id or "")
	return true, "paste"
end

---------------------------------------------------------------------------------------------------------------------
-- Reading an imported event
---------------------------------------------------------------------------------------------------------------------
-- The own sign-up (of this character or another of the account), or nil.
function RH:Own(rec)
	local me = compat().Player.GUID()
	if not me then return nil end
	local key = RH.AccountKey(me)
	for _, e in ipairs(rec.s) do
		if e.g == me then return e end
	end
	for _, e in ipairs(rec.s) do
		if S():SameAccount(me, e.g) or RH.AccountKey(e.g) == key then return e end
	end
	return nil
end

-- role -> count of the sign-ups: { signed = {...} (signed and late), bench = {...}, tentative = {...}, unknown = n }.
function RH.Roles(rec)
	local out = { signed = {}, bench = {}, tentative = {}, unknown = 0 }
	for _, role in ipairs(ns.Specs.ROLES) do out.signed[role], out.bench[role], out.tentative[role] = 0, 0, 0 end
	for _, e in ipairs(rec.s) do
		local group = (e.st == "signed" or e.st == "late") and out.signed or out[e.st]
		if group then
			if e.role then group[e.role] = group[e.role] + 1 else out.unknown = out.unknown + 1 end
		end
	end
	return out
end

local function nameOf(guid, fallback)
	local m = ns.Roster and ns.Roster:ByGUID(guid)
	return m and m.name or fallback or guid
end

-- The sign-ups on Discord against the answers of the game calendar event, by account (its answers must have been read):
-- { onlyDiscord = { names } (signed up or tentative on Discord, not in the game), onlyGame = { names } (the other way),
--   differ = { { name, discord = state, game = answer } } }; nil while the answers were not read.
function RH:Compare(rec, e)
	local inv = e and ns.Calendar.invites[e.key]
	if not inv then return nil end
	local game = {}
	for _, i in ipairs(inv.list) do
		local guid = i.guid
		if not guid and i.name then
			local m = ns.Roster:ByName(i.name)
			guid = m and m.guid
		end
		local key = guid and RH.AccountKey(guid) or ("name:" .. tostring(i.name))
		local held = game[key]
		if not held or (not held.answer and i.answer) then game[key] = { answer = i.answer, name = i.name or nameOf(guid) } end
	end
	local out = { onlyDiscord = {}, onlyGame = {}, differ = {} }
	local seen = {}
	for _, s in ipairs(rec.s) do
		local key = RH.AccountKey(s.g)
		seen[key] = true
		local answer = RH.ANSWER[s.st]
		local g = game[key]
		if not (g and g.answer) then
			if answer ~= "no" then out.onlyDiscord[#out.onlyDiscord + 1] = nameOf(s.g) end
		elseif g.answer ~= answer then
			out.differ[#out.differ + 1] = { name = nameOf(s.g, g.name), discord = s.st, game = g.answer }
		end
	end
	for key, g in pairs(game) do
		if not seen[key] and (g.answer == "yes" or g.answer == "maybe") then out.onlyGame[#out.onlyGame + 1] = g.name or "?" end
	end
	sort(out.onlyDiscord)
	sort(out.onlyGame)
	sort(out.differ, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return out
end

-- The rows of an event for the export back to Discord (Data/Export.lua kind "event"): the answers of the game calendar
-- (with the role chosen in Accord) and the sign-ups of Discord, one per account. `e` the calendar event or nil, `rec` the
-- import or nil. { { guid?, name, class?, role?, answer?, discord? } }
function RH:ExportRows(e, rec)
	local rows, byKey = {}, {}
	local function row(key, guid, name)
		local r = byKey[key]
		if not r then
			local m = guid and ns.Roster:ByGUID(guid)
			r = { guid = guid, name = m and m.name or name, class = m and m.classFile or nil }
			byKey[key] = r
			rows[#rows + 1] = r
		end
		return r
	end
	local inv = e and ns.Calendar.invites[e.key]
	for _, i in ipairs(inv and inv.list or {}) do
		if i.answer then
			local guid = i.guid
			if not guid and i.name then
				local m = ns.Roster:ByName(i.name)
				guid = m and m.guid
			end
			local r = row(guid and RH.AccountKey(guid) or ("name:" .. tostring(i.name)), guid, i.name)
			r.answer, r.class = i.answer, r.class or i.classFile
			r.role = guid and ns.Calendar:RoleOf(e.key, guid) or r.role
		end
	end
	for _, s in ipairs(rec and rec.s or {}) do
		local r = row(RH.AccountKey(s.g), s.g)
		r.discord, r.role = s.st, r.role or s.role
		r.class = r.class or s.class
	end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Into the game calendar (SPEC-14 §6.5)
---------------------------------------------------------------------------------------------------------------------
-- The other raid event of the same day, or nil (FDCP links the first raid event of the day).
local function otherRaid(rec, chosen)
	local day = floor(rec.start / DAY)
	for _, e in ipairs(ns.Calendar:AllEvents()) do
		if e.raid and floor(e.start / DAY) == day and not (chosen and e.eventID == chosen.eventID) then return e end
	end
	return nil
end

-- A status that is no answer of the member: invited, or not signed up.
local function unanswered(status)
	local st = Cal().Status()
	return status == st.Invited or status == st.NotSignedup
end

local function findInvite(list, guid, name)
	local want = name and lower(name)
	local short = want and lower((compat().SplitName(name)))
	for i, row in ipairs(list) do
		if row.guid then
			if row.guid == guid then return i, row end
		elseif row.name and (lower(row.name) == want or lower(row.name) == short) then
			return i, row
		end
	end
	return nil
end

-- What a confirmation would do: { create = boolean, event?, members = n (at most INVITE_MAX), total = n, other? = title of
-- another raid event of the day }, or nil and a reason ("off", "officer", "busy", "missing", "past", "nocreate", or why
-- the calendar cannot be opened now, Calendar:Blocked()).
function RH:Plan(id)
	if not RH.Enabled() then return nil, "off" end
	if not RH.CanImport() then return nil, "officer" end
	if self.job then return nil, "busy" end
	local rec = self:Get(id)
	if not rec then return nil, "missing" end
	local why = ns.Calendar:Blocked()
	if why then return nil, why end
	if rec.start <= (RH.RealmStart(now()) or now()) then return nil, "past" end
	local e = self:EventAt(rec)
	if not e and not Cal().CanCreate() then return nil, "nocreate" end
	local inv = e and ns.Calendar.invites[e.key]
	local total = 0
	for _, s in ipairs(rec.s) do
		local m = ns.Roster:ByGUID(s.g)
		if m then
			local _, row
			if inv then _, row = findInvite(inv.list, s.g, m.name) end
			if not (row and row.status and not unanswered(row.status)) then total = total + 1 end
		end
	end
	local other = otherRaid(rec, e)
	return { create = e == nil, event = e, total = total, members = math.min(total, RH.INVITE_MAX),
		other = other and other.title or nil }
end

local function after(seconds, fn)
	compat().After(seconds, fn)
end

-- Ends the job: what was done and who was left out. Closes the event Accord holds.
local function finish(job, why)
	if job.done then return end
	job.done = true
	if RH.job == job then RH.job = nil end
	local res = job.result
	res.pending, res.ok, res.why = nil, why == nil, why
	for i = job.index, #job.queue do
		local target = job.queue[i]
		if not target.settled then res.left[#res.left + 1] = target.name end
	end
	local o = ns.Calendar.open
	if o and o.job == job then
		ns.Calendar:ReadHeld(why == nil)
		ns.Calendar:Finish(why)
	end
	changed(job.id)
end

local step, poke

-- Waits for the effect of the last call; Calendar.ANSWER_WAIT without it, the job stops.
local function wait(job, check, settle)
	job.seq = job.seq + 1
	local seq = job.seq
	job.waiting = { check = check, settle = settle }
	after(ns.Calendar.ANSWER_WAIT, function()
		if not job.done and job.seq == seq and job.waiting then
			if job.waiting.check() and not Cal().Pending() then poke(job) else finish(job, "timeout") end
		end
	end)
	poke(job)
end

poke = function(job)
	if job.done or job.poked then return end
	job.poked = true
	after(RH.CHECK_DELAY, function()
		job.poked = nil
		if not job.done then step(job) end
	end)
end

-- True (and the job ends) when the calendar may not be written now.
local function interrupted(job)
	local why
	if not RH.CanImport() then why = "officer"
	elseif compat().InCombat() then why = "combat"
	elseif compat().EncounterInProgress() then why = "encounter"
	elseif Cal().FrameShown() then why = "shown" end
	if why then finish(job, why) return true end
	return false
end

-- Runs a calendar call; a call the client refused ends the job. True when it ran.
local function call(job, fn, ...)
	ns.Calendar.blockedCall = nil
	local ran = fn(...)
	if not ran or ns.Calendar.blockedCall then
		finish(job, "blocked")
		return false
	end
	return true
end

local function hold(job, key, eventID)
	return ns.Calendar:Hold({ key = key, eventID = eventID, job = job, ended = function(why) finish(job, why or "closed") end })
end

-- Opens the calendar event to write into, then waits for its answers.
local function openFor(job, e)
	local why = ns.Calendar:Blocked()
	if why == "pending" or why == "busy" then return false end
	if why then finish(job, why) return true end
	job.phase, job.listed = "list", nil
	if not Cal().OpenEvent(e.eventID) then finish(job, "open") return true end
	if not hold(job, e.key, e.eventID) then finish(job, "busy") return true end
	wait(job, function() return job.listed == true end)
	return true
end

-- One step: at most one calendar call, then wait for its effect.
step = function(job)
	if interrupted(job) then return end
	if Cal().Pending() then
		if not job.waiting then wait(job, function() return not Cal().Pending() end) end
		return
	end
	local w = job.waiting
	if w then
		if not w.check() then return end
		job.waiting = nil
		if w.settle then w.settle() end
	end
	if job.phase == "create" then
		-- the event created is the one at that date and time that was not there before
		for _, e in ipairs(ns.Calendar:AllEvents()) do
			if e.start == job.rec.start and not job.before[e.eventID] then
				job.created = e
				break
			end
		end
		if not job.created then return end
		job.result.created = true
		job.phase = "open"
		local o = ns.Calendar.open
		if o and o.job == job then ns.Calendar:Release() end
		return poke(job)
	end
	if job.phase == "open" then
		if not openFor(job, job.created) then wait(job, function() return ns.Calendar:Blocked() == nil end) end
		return
	end
	local o = ns.Calendar.open
	if not (o and o.job == job) then return finish(job, "closed") end
	if job.phase == "list" then
		if not job.listed then return end
		if not Cal().CanEdit() then return finish(job, "noedit") end
		job.phase = "write"
	end
	local res = job.result
	while job.index <= #job.queue do
		local target = job.queue[job.index]
		local list = Cal().Invites()
		local i, row = findInvite(list, target.guid, target.name)
		local function done(kind)
			target.settled = true
			if kind then res[kind][#res[kind] + 1] = target.name end
			job.index = job.index + 1
		end
		-- a member written counts once towards INVITE_MAX, whether it takes an invite, a state or both
		local function room()
			if target.counted then return true end
			if job.count >= RH.INVITE_MAX then return false end
			target.counted, job.count = true, job.count + 1
			return true
		end
		if target.wrote then
			done("written")
		elseif row and not (row.status and unanswered(row.status)) then
			-- an answer given in the game wins (SPEC-10 Q25)
			done("answered")
		elseif not row then
			if target.invited then return finish(job, "server") end
			if not Cal().CanSendInvite() or not compat().PlainName(target.name) then
				done("member")
			elseif not room() then
				done("left")
			else
				if not call(job, Cal().Invite, target.name) then return end
				return wait(job, function() return findInvite(Cal().Invites(), target.guid, target.name) ~= nil end, function()
					target.invited = true
					res.invited = res.invited + 1
				end)
			end
		else
			local status = Cal().Status()[RH.CALENDAR_STATUS[target.answer]]
			if not Cal().CanSetStatus(i, status) then
				-- invited, the member answers in the game: a row of the Action Center says so
				done("member")
			elseif not room() then
				done("left")
			else
				if not call(job, Cal().SetStatus, i, status) then return end
				return wait(job, function()
					local _, held = findInvite(Cal().Invites(), target.guid, target.name)
					return held ~= nil and held.status == status
				end, function() target.wrote = true end)
			end
		end
	end
	finish(job, nil)
end

-- The officer's confirmation (from a click): writes the imported event `id` into the game calendar. Returns true while it
-- runs (RaidHelper.result[id] says what happened), or false and a reason (as Plan).
function RH:Push(id)
	local plan, why = self:Plan(id)
	if not plan then return false, why end
	local rec = self:Get(id)
	local queue = {}
	for _, s in ipairs(rec.s) do
		local m = ns.Roster:ByGUID(s.g)
		if m then queue[#queue + 1] = { guid = s.g, name = m.name, answer = RH.ANSWER[s.st] } end
	end
	local job = { id = id, rec = rec, queue = queue, index = 1, count = 0, seq = 0,
		result = { pending = true, invited = 0, written = {}, answered = {}, member = {}, left = {} } }
	self.job, self.result[id] = job, job.result
	if plan.event then
		job.phase = "open"
		job.created = plan.event
		if not openFor(job, plan.event) then poke(job) end
	else
		job.phase, job.before = "create", {}
		for _, e in ipairs(ns.Calendar:AllEvents()) do job.before[e.eventID] = true end
		local d = date("!*t", rec.start)
		hold(job, "new", nil)
		if call(job, Cal().Create, { title = RH.CalendarTitle(rec.title), description = ns.L["RH_CALENDAR_DESCRIPTION"],
			year = d.year, month = d.month, day = d.day, hour = d.hour, minute = d.min }) then
			wait(job, function()
				for _, e in ipairs(ns.Calendar:AllEvents()) do
					if e.start == rec.start and not job.before[e.eventID] then return true end
				end
				return false
			end)
		end
	end
	changed(id)
	if job.done and not job.result.ok then return false, job.result.why end
	return true
end

-- A calendar event of the game arrived.
function RH:OnCalendar(complete)
	local job = self.job
	if not job then return end
	if complete and job.phase == "list" then job.listed = true end
	poke(job)
end

function RH:Reset()
	if self.job then self.job.done = true end   -- the timers of a write in progress do nothing more
	self.job = nil
	self.session, self.result = {}, {}
end

---------------------------------------------------------------------------------------------------------------------
-- The Action Center (M9.2): sign up in the game calendar
---------------------------------------------------------------------------------------------------------------------
-- One row per imported event where the player's account is signed up on Discord and the game calendar has no answer.
function RH:ActionRows()
	local out = {}
	if not (RH.Enabled() and ns.Calendar.Usable()) then return out end
	local L = ns.L
	local realmNow = RH.RealmStart(now()) or now()
	for _, row in ipairs(self:List()) do
		local rec = row.rec
		local own = self:Own(rec)
		if own and rec.start >= realmNow - RH.SOON then
			local e = self:EventAt(rec)
			if e and not e.answer then
				local key = e.key
				out[#out + 1] = { key = "h" .. row.id, urgency = 2, time = rec.at,
					title = L["RH_ACTION_TITLE"]:format(rec.title),
					detail = L["RH_ACTION_DETAIL"]:format(L["RH_STATE_" .. own.st:upper()]),
					mark = own.st,
					open = function() if ns.EventsView then ns.EventsView:Open(key) end end }
			end
		end
	end
	return out
end

function RH:DebugLines()
	local imports, signups = 0, 0
	for _, row in ipairs(self:List()) do imports, signups = imports + 1, signups + #row.rec.s end
	local t = localData()
	local local_, manual = 0, 0
	for _, imp in pairs(t and t.imports or {}) do local_ = local_ + #(imp.unmatched or {}) end
	for _ in pairs(t and t.manual or {}) do manual = manual + 1 end
	return { ("Raid-Helper: %d imported events, %d matched sign-ups, %d unmatched names and %d hand matches kept here%s")
		:format(imports, signups, local_, manual, self.job and ", writing into the calendar" or "") }
end

if ns.Actions then
	ns.Actions:Register("events", { label = "ACT_PROVIDER_EVENTS", order = 15, feature = "season",
		events = { "CALENDAR_CHANGED", "EVENT_CHANGED", "ROSTER_UPDATED" },
		items = function() return RH:ActionRows() end })
end

---------------------------------------------------------------------------------------------------------------------
-- Events of the game
---------------------------------------------------------------------------------------------------------------------
if ns.addon then
	ns.addon.RaidHelper = RH
	LibStub("AceEvent-3.0"):Embed(RH)
	RH:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		if RH.Enabled() then after(30, function() RH:Prune() end) end
	end)
	RH:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST", function(_, complete) RH:OnCalendar(complete) end)
	for _, event in ipairs({ "CALENDAR_ACTION_PENDING", "CALENDAR_UPDATE_EVENT", "CALENDAR_UPDATE_EVENT_LIST",
		"CALENDAR_UPDATE_GUILD_EVENTS" }) do
		RH:RegisterEvent(event, function() RH:OnCalendar() end)
	end
	if ns.Bus then
		ns.Bus:On("GUILD_CHANGED", function() RH:Reset() end)
		ns.Bus:On("ROSTER_UPDATED", function() if RH.Enabled() then RH:Prune() end end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if RH.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Raid-Helper", function() return RH:DebugLines() end)
			end
		end)
	end
end

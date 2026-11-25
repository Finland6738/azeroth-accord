-- Absence: declared absences with a return date (SPEC-12 §3.4, INA-05, INA-06, M8.3). Lua 5.1.
--
-- A record of the set `absence` is { id, author, rev, time, char = GUID, from = day, until = day }, days written YYYYMMDD
-- (UTC). Two ids per character, so a member and an officer never overwrite each other's revisions:
--   "<GUID>:self"  written by the account of the character (the Settings card, `/accord away`)
--   "<GUID>:off"   written by an officer (the member card, the Inactive page)
-- `until = 0` clears the absence. `from` is the day it was written or an earlier one, `until` from `from` to `from` + 180
-- days. No reason and no free text. For an account the record written most recently among its characters counts.
--
--   Absence.ParseDate(text, t)  "2026-12-31" -> day, or nil plus "date" | "past" | "far"
--   Absence:Declare(day)        the connected character's own absence (0 clears it), sent to the officers
--   Absence:Own(t)              what the player sees: the newest `:self` record of the own account ({ rec, day, away }) or nil
--   Absence:SetFor(guid, day)   an officer sets or clears (0) the absence of any character of the guild
--   Absence.Of(guids, t, byChar) the absence of an account: { rec, day, away, back } or nil
--   Absence:Send()              a member's own records go by WHISPER to up to two online officers (Sync:SendToOfficers); the
--                               officers pass them on OFFICER (§1.5). Without an officer online it is tried at the next login.
local ADDON_NAME, ns = ...
ns = ns or {}
local Absence = {}
ns.Absence, ns.modules = Absence, ns.modules or {}
ns.modules.Absence = Absence

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, random, format = math.floor, math.random, string.format

Absence.AUTO = true                  -- the offline tests switch the sending after login off (Tests/lib/harness.lua)
Absence.SET = "absence"
Absence.MAX_DAYS = 180               -- `until` is at most this far from `from` (INA-05)
Absence.KEEP_DAYS = 30               -- a record is deleted this long after `until` (after its time when cleared)
Absence.BACK_DAYS = 14               -- "away until <date>" is still said this long after the return
Absence.BACK_ROWS = 3                -- the Action Center says "is back" to officers up to this many days after the return
Absence.ENDING_ROWS = 3              -- and reminds the member this many days before the own absence ends
Absence.LOGIN_DELAY = { 60, 120 }    -- seconds after the first HELLO of a login

local DAY = 86400

local state = { timer = nil, loginDone = false, sent = 0, sends = 0 }
Absence.state = state

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function store() return ns.Store end
local function timeline() return ns.Timeline end
local function myGUID() return compat().Player.GUID() end

---------------------------------------------------------------------------------------------------------------------
-- Days
---------------------------------------------------------------------------------------------------------------------
-- The number of days since 1970-01-01 of a server time.
function Absence.Today(t) return floor((t or now()) / DAY) end

-- "2026-12-31" of a day written 20261231.
function Absence.DayText(day)
	if type(day) ~= "number" then return "?" end
	return format("%04d-%02d-%02d", floor(day / 10000), floor(day / 100) % 100, day % 100)
end

-- The day YYYYMMDD typed as "YYYY-MM-DD", when it is a date from today to MAX_DAYS ahead.
function Absence.ParseDate(text, t)
	if type(text) ~= "string" then return nil, "date" end
	local y, m, d = text:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
	if not y then return nil, "date" end
	local day = tonumber(y) * 10000 + tonumber(m) * 100 + tonumber(d)
	local n = timeline().DayNumber(day)
	if not n then return nil, "date" end
	local today = Absence.Today(t)
	if n < today then return nil, "past" end
	if n - today > Absence.MAX_DAYS then return nil, "far" end
	return day
end

---------------------------------------------------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------------------------------------------------
-- "self" | "off" for the id of a record of `char`, nil for any other id.
function Absence.KindOf(rec)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.char) ~= "string" then return nil end
	if rec.id == rec.char .. ":self" then return "self" end
	if rec.id == rec.char .. ":off" then return "off" end
	return nil
end

local ALLOWED = { id = true, author = true, rev = true, time = true, char = true, from = true, ["until"] = true }

-- The owner rule of the set (OFF-03): the shape and the days; a `:self` record is written by the character's own account.
function Absence.ValidRecord(rec, s)
	if type(rec) ~= "table" then return false end
	for key in pairs(rec) do if not ALLOWED[key] then return false end end
	local kind = Absence.KindOf(rec)
	if not kind then return false end
	if not (#rec.char <= 40 and rec.char:find(store().GUID_PATTERN)) then return false end
	local from = timeline().DayNumber(rec.from)
	if not from or type(rec.time) ~= "number" or from > Absence.Today(rec.time) then return false end
	local back = rec["until"]
	if back ~= 0 then
		local n = timeline().DayNumber(back)
		if not n or n < from or n - from > Absence.MAX_DAYS then return false end
	end
	if kind == "self" and not (s or store()):SameAccount(rec.char, rec.author) then return false end
	return true
end

function Absence.Expired(rec, t)
	if type(rec) ~= "table" then return true end
	if rec["until"] == 0 then return (rec.time or 0) < t - Absence.KEEP_DAYS * DAY end
	local n = timeline().DayNumber(rec["until"])
	return not n or Absence.Today(t) > n + Absence.KEEP_DAYS
end

-- true when `a` was written after `b` (INA-06: the most recent write counts).
local function newer(a, b)
	if not b then return true end
	if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) > (b.time or 0) end
	if a.rev ~= b.rev then return (a.rev or 0) > (b.rev or 0) end
	return tostring(a.id) > tostring(b.id)
end

-- character GUID -> its newest record, over the whole set.
function Absence.ByChar()
	local out = {}
	for _, rec in pairs(store():Records(Absence.SET)) do
		if Absence.KindOf(rec) and newer(rec, out[rec.char]) then out[rec.char] = rec end
	end
	return out
end

-- What a record says at time `t`: { rec, day = until, away = the return is today or later, back = it ended at most
-- BACK_DAYS ago }, or nil for no record and for a cleared one.
function Absence.Read(rec, t)
	if not rec or rec["until"] == 0 then return nil end
	local n = timeline().DayNumber(rec["until"])
	if not n then return nil end
	local today = Absence.Today(t)
	if n >= today then return { rec = rec, day = rec["until"], away = true } end
	if today - n <= Absence.BACK_DAYS then return { rec = rec, day = rec["until"], away = false, back = true } end
	return nil
end

-- The absence of an account: the newest record among its characters `guids`. `byChar` is Absence.ByChar() (read once for
-- many accounts).
function Absence.Of(guids, t, byChar)
	byChar = byChar or Absence.ByChar()
	local best
	for _, guid in ipairs(guids or {}) do
		local rec = byChar[guid]
		if rec and newer(rec, best) then best = rec end
	end
	return Absence.Read(best, t)
end

-- The same for the account of one character, for whoever may see the absences of others (nil for a member).
function Absence:AccountOf(guid, t)
	if not ns.Officer.CanSee("absences") or type(guid) ~= "string" then return nil end
	local g = ns.Accounts and ns.Accounts:GroupOf(guid)
	local guids = {}
	if g then for _, m in ipairs(g.members) do guids[#guids + 1] = m.guid end else guids[1] = guid end
	return Absence.Of(guids, t)
end

---------------------------------------------------------------------------------------------------------------------
-- The player's own absence
---------------------------------------------------------------------------------------------------------------------
-- GUID -> true for every character of this account (every realm), the connected one included.
function Absence.OwnGUIDs()
	local out = {}
	local db = ns.Config and ns.Config.db and ns.Config.db.account
	for _, list in pairs(db and type(db.chars) == "table" and db.chars or {}) do
		if type(list) == "table" then for guid in pairs(list) do out[guid] = true end end
	end
	local me = myGUID()
	if me then out[me] = true end
	return out
end

-- The `:self` records of this account that the current guild holds.
function Absence:OwnRecords()
	local out = {}
	if not (ns.GuildKey and ns.GuildKey:Current()) then return out end
	local mine = Absence.OwnGUIDs()
	for _, rec in pairs(store():Records(Absence.SET)) do
		if Absence.KindOf(rec) == "self" and mine[rec.char] then out[#out + 1] = rec end
	end
	table.sort(out, function(a, b) return newer(a, b) end)
	return out
end

-- The newest declaration of this account (never what an officer wrote), read at `t`; nil when there is none.
function Absence:Own(t)
	return Absence.Read(self:OwnRecords()[1], t or now())
end

local function write(id, char, day)
	local t = now()
	local today = timeline().DayOf(t)
	if day ~= 0 then
		local n = timeline().DayNumber(day)
		if not n then return nil, "date" end
		if n < Absence.Today(t) then return nil, "past" end
		if n - Absence.Today(t) > Absence.MAX_DAYS then return nil, "far" end
	end
	return store():Put(Absence.SET, id, { char = char, from = today, ["until"] = day })
end

-- Declares (day) or clears (0) the absence of the connected character. Returns true and the number of officers it was sent
-- to (nil for an officer: the officers' sync carries it), or false and the reason.
function Absence:Declare(day)
	local me = myGUID()
	if not (me and ns.Role and ns.Role:InGuild() and ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local rec, why = write(me .. ":self", me, day)
	if not rec then return false, why end
	return true, self:Send()
end

-- An officer sets (day) or clears (0) the absence of any character of the guild.
function Absence:SetFor(guid, day)
	if not (ns.Role and ns.Role:IsOfficer()) then return false, "officer" end
	if type(guid) ~= "string" then return false, "unknown" end
	local rec, why = write(guid .. ":off", guid, day)
	if not rec then return false, why end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Sending (a member's own records, §3.4)
---------------------------------------------------------------------------------------------------------------------
-- Sends this account's `:self` records to the officers online. Returns the number of officers, 0 when none is (it is tried
-- again at the next login), or nil for an officer's character, whose records travel with the officers' sync.
function Absence:Send()
	if not (ns.Role and ns.Role:InGuild()) or ns.Role:IsOfficer() then return nil end
	local data = ns.GuildKey and ns.GuildKey:Data()
	local records = self:OwnRecords()
	if not data or #records == 0 then return 0 end
	local n = ns.Sync and ns.Sync:SendToOfficers(Absence.SET, records) or 0
	data.absenceUnsent = n == 0 and true or nil
	if n > 0 then state.sends, state.sent = state.sends + 1, state.sent + n end
	return n
end

-- true when something of this account still has to reach an officer after a login: a valid absence, or a change that found
-- no officer online.
function Absence:NeedsSending()
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	if not data then return false end
	if data.absenceUnsent and #self:OwnRecords() > 0 then return true end
	local own = self:Own()
	return own ~= nil and own.away == true
end

-- After the first HELLO of a login: once, 60-120 s later.
function Absence:OnHello()
	if not self.AUTO or state.loginDone then return false end
	state.loginDone = true
	local delay = Absence.LOGIN_DELAY[1] + (Absence.LOGIN_DELAY[2] - Absence.LOGIN_DELAY[1]) * random()
	state.timer = compat().NewTimer(delay, function()
		state.timer = nil
		if Absence:NeedsSending() then Absence:Send() end
	end)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The Action Center (SPEC-13 §2.3): part of the provider `officer` (Data/OfficerOps.lua registers it)
---------------------------------------------------------------------------------------------------------------------
-- For officers: every account whose declared return date is today or at most BACK_ROWS days ago (the newest record of the
-- account counts, INA-06; an account with nobody left in the guild is not listed): { char, name, day, number }. Nothing
-- for a member.
function Absence:Returned(t)
	local out = {}
	if not ns.Officer.CanSee("absences") then return out end
	t = t or now()
	local today = Absence.Today(t)
	local newest, shown = {}, {}   -- account key -> its newest record, a character of it that is in the guild
	for guid, rec in pairs(Absence.ByChar()) do
		local key = ns.Accounts and ns.Accounts:AccountKey(guid) or guid
		if newer(rec, newest[key]) then newest[key] = rec end
		if ns.Roster and ns.Roster:ByGUID(guid) and (not shown[key] or guid < shown[key]) then shown[key] = guid end
	end
	for key, rec in pairs(newest) do
		local a = Absence.Read(rec, t)
		local n = a and timeline().DayNumber(a.day)
		if n and n <= today and today - n <= Absence.BACK_ROWS then
			local main = ns.Accounts and ns.Accounts:MainOf(rec.char)
			local e = ns.Roster and (main and ns.Roster:ByGUID(main.guid) or ns.Roster:ByGUID(rec.char)
				or shown[key] and ns.Roster:ByGUID(shown[key]))
			if e then out[#out + 1] = { char = rec.char, name = e.short or e.name or "?", day = a.day, number = n } end
		end
	end
	return out
end

local function openInactive() if ns.OfficersView then ns.OfficersView:OpenPage("inactive") end end

---------------------------------------------------------------------------------------------------------------------
-- The notice of a member who is back (SPEC-13 §3.2: quiet, officers)
---------------------------------------------------------------------------------------------------------------------
-- The first look in a guild is only remembered.
function Absence:Notice()
	local N = ns.Notify
	local me = myGUID()
	if not (N and N.Enabled() and me and ns.Officer.CanSee("absences") and ns.Roster and ns.Roster:ByGUID(me)) then return end
	local book = N:Seen("officer")
	if not book then return end
	local first = not book.__baseline
	book.__baseline = true
	for _, r in ipairs(self:Returned()) do
		if book[r.char] ~= r.day then
			book[r.char] = r.day
			if not first then
				N:Post("officer", "back", { key = r.char .. ":" .. r.day, text = "ACT_ABSENCE_BACK",
					args = { r.name, Absence.DayText(r.day) }, view = "officers", page = "inactive", char = me })
			end
		end
	end
end

if ns.Notify then
	ns.Notify:Register("officer", { label = "NOTICE_MODULE_OFFICER", order = 30, open = openInactive,
		check = function() Absence:Notice() end,
		kinds = { { id = "back", level = "quiet", group = "NOTICE_BACK_MANY" } } })
end

---------------------------------------------------------------------------------------------------------------------
-- For officers: every account whose declared return date is today or at most BACK_ROWS days ago (the newest record of the
-- account counts, INA-06; an account with nobody left in the guild is not listed). For everybody: the own declaration that
-- ends within ENDING_ROWS days. It only reads.
function Absence:ActionRows(t)
	local L, rows = ns.L, {}
	t = t or now()
	local today = Absence.Today(t)
	for _, r in ipairs(self:Returned(t)) do
		rows[#rows + 1] = { key = "back:" .. r.char, urgency = 1, time = r.number * DAY, who = r.name,
			title = L["ACT_ABSENCE_BACK"]:format(r.name, Absence.DayText(r.day)), open = openInactive }
	end
	local own = self:Own(t)
	local n = own and own.away and timeline().DayNumber(own.day)
	if n and n - today <= Absence.ENDING_ROWS then
		rows[#rows + 1] = { key = "own", urgency = 1, time = math.max(own.rec.time or 0, (n - Absence.ENDING_ROWS) * DAY),
			title = L["ACT_ABSENCE_ENDS"]:format(Absence.DayText(own.day)),
			open = function() if ns.SettingsView then ns.SettingsView:ShowAbsence() end end }
	end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- /accord away
---------------------------------------------------------------------------------------------------------------------
-- The text that answers a save: what happened to the declaration.
function Absence.SavedText(day, sent)
	local L = ns.L
	local text = day == 0 and L["ABS_CLEARED"] or L["ABS_SAVED_UNTIL"]:format(Absence.DayText(day))
	if sent == nil then
		if not ns.Officer.ChannelProven() then text = text .. " " .. L["TL_LOCAL_ONLY"] end
	elseif sent > 0 then
		text = text .. " " .. L["ABS_SENT"]:format(sent)
	else
		text = text .. " " .. L["ABS_UNSENT"]
	end
	return text
end

function Absence.ErrorText(why)
	local L = ns.L
	if why == "date" then return L["ABS_ERR_DATE"] end
	if why == "past" then return L["ABS_ERR_PAST"] end
	if why == "far" then return L["ABS_ERR_FAR"] end
	if why == "guild" then return L["NOT_IN_GUILD"] end
	return L["ABS_ERR_OTHER"]:format(tostring(why))
end

-- `input` is what was typed after /accord: "away 2026-12-31", "away off", "away".
function Absence.Command(input)
	local L, addon = ns.L, ns.addon
	local function say(text) if addon then addon:Print(text) end end
	if not (ns.Role and ns.Role:InGuild()) then return say(L["NOT_IN_GUILD"]) end
	local word = tostring(input or ""):match("^%s*%S+%s+(%S+)")
	if not word then
		local own = Absence:Own()
		say(own and own.away and L["ABS_AWAY"]:format(Absence.DayText(own.day)) or L["ABS_NONE"])
		return say(L["ABS_USAGE"])
	end
	local day = 0
	if word:lower() ~= "off" then
		local why
		day, why = Absence.ParseDate(word)
		if not day then return say(Absence.ErrorText(why)) end
	end
	local ok, sent = Absence:Declare(day)
	if not ok then return say(Absence.ErrorText(sent)) end
	say(Absence.SavedText(day, sent))
end

function Absence:DebugLines()
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	return { ("Absence: %d own record(s), %d send(s) to officers, waiting for an officer: %s"):format(#self:OwnRecords(),
		state.sends, data and data.absenceUnsent and "yes" or "no") }
end

if ns.addon then
	ns.addon.Absence = Absence
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Absence", function() return Absence:DebugLines() end) end
	-- OFF-10: the account's own declarations stay when the officer data goes
	if ns.Officer then
		ns.Officer.KEEP[Absence.SET] = function(rec) return Absence.KindOf(rec) == "self" and Absence.OwnGUIDs()[rec.char] == true end
	end
	if ns.Bus then
		ns.Bus:On("SYNC_HELLO", function(sent) if sent then Absence:OnHello() end end)
		ns.Bus:On("STORE_CHANGED", function(set) if set == Absence.SET then Absence:Notice() end end)
		ns.Bus:On("ROSTER_UPDATED", function() Absence:Notice() end)
		ns.Bus:On("GUILD_CHANGED", function()
			if state.timer then state.timer:Cancel() state.timer = nil end
			state.loginDone = false
		end)
	end
end

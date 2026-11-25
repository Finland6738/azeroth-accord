-- Calendar: the guild's events and sign-ups on the game calendar (M10.5; SPEC-14 §5; M10 integration rule 2). Lua 5.1.
--
-- The game calendar is the shared ground: events and answers are read from it and written to it, so that FDCP, the
-- game's own interface and every other client see the same answer. Accord copies no calendar event.
--   Reading   at the first PLAYER_ENTERING_WORLD with the switch on, C_Calendar.OpenCalendar() once; at every
--             CALENDAR_UPDATE_EVENT_LIST and CALENDAR_UPDATE_GUILD_EVENTS the guild events from Calendar.PAST_DAYS
--             ago to Calendar.AHEAD_DAYS ahead are read again with GetGuildEventInfo, whoever created them. Their own
--             answer comes with them (inviteStatus). The answers of everybody are read only for the event the Events
--             view shows (Calendar:LoadInvites), never for all events in the background.
--   One open event per client: the client has one open event, shared with the game's calendar window and the other
--             addons. Accord never opens one while the window is shown or IsActionPending() is true, never in combat or
--             during a boss (SPEC-14 §10), and always closes what it opened.
--   Answering only from a click of the player: "yes" calls EventSignUp() on a guild sign-up event the player has not
--             answered yet, EventAvailable() otherwise [verify]; "maybe" EventTentative(); "no" EventDecline(). Then
--             Accord waits for CALENDAR_UPDATE_INVITE_LIST, CALENDAR_UPDATE_EVENT or CALENDAR_UPDATE_ERROR (at most
--             Calendar.ANSWER_WAIT seconds), reads the own status again, closes the event and says what happened. If the
--             client refuses the call from an addon (ADDON_ACTION_BLOCKED, or the call does not run), the game's
--             calendar window opens instead and the view says so.
--   The role has no place in the game calendar: Accord keeps it in the record R:<key>:<GUID> of the data set `raidev`,
--             preselected from the season declaration (MS1, or MS2 when MS1's role is already covered for the target
--             composition and MS2's is not), else from the class. A member without a declaration signs up all the same.
--   Fallback  only when the client has no usable calendar (the Compat feature "calendar" is "missing": no C_Calendar, or
--             no CALENDAR_UPDATE_EVENT_LIST within Calendar.FALLBACK_WAIT seconds of OpenCalendar) officers
--             (Raid.WRITERS) create events in the addon (F:<GUID>:<n>) and members answer there (A:<key>:<GUID>). Those
--             are always marked "Not in the game calendar", also on a client that has a calendar.
--
-- The data set `raidev` (Net/Store.lua, SPEC-14 §5.5), synced on GUILD; four kinds of record (C: comes with M10.7 and
-- is refused until then):
--   R:<key>:<GUID>   { role, spec = "ms1" | "ms2" | "class", at }  the role of a character for an event; its account only
--   F:<GUID>:<n>     { title, start, size, note? }                 an event only of the addon; officers only (authorAny)
--   A:<key>:<GUID>   { answer = "yes" | "maybe" | "no", role, at } an answer to an event only of the addon; its account
--   H:<id>           { title, start, at, s }                       a Raid-Helper event pasted by an officer (M10.6,
--                    Data/RaidHelper.lua checks it); officers only (authorAny)
-- The key of an event is "c<eventID>" (calendar) or "f<GUID>:<n>" (addon only). `at` and `start` are server times (of
-- H:, `start` is the realm's date and time as a calendar event's and `at` the time of the import); a record expires
-- Calendar.KEEP seconds after its event. No record says who was at a raid (RAID-05). Calendar.MAX_BYTES is the size of a
-- record, but of H: (the set takes RaidHelper.MAX_BYTES for it).
--
-- Switch: Core/Features.lua "season" (M10). Off: no call to C_Calendar, nothing written, accepted or sent.
-- Bus: CALENDAR_CHANGED() when the events or the calendar's state were read again; EVENT_CHANGED(key) when the answers,
-- the roles or the outcome of an answer of one event changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Calendar = {}
ns.Calendar, ns.modules = Calendar, ns.modules or {}
ns.modules.Calendar = Calendar

local type, pairs, ipairs, tostring, tonumber, floor, sort = type, pairs, ipairs, tostring, tonumber, math.floor, table.sort

local DAY = 86400
Calendar.SET = "raidev"
Calendar.PAST_DAYS = 7          -- the guild events read back
Calendar.AHEAD_DAYS = 14        -- and ahead
Calendar.FALLBACK_WAIT = 60     -- seconds without an event list after OpenCalendar: the client has no usable calendar
Calendar.ANSWER_WAIT = 10       -- seconds to wait for the server's answer to a sign-up
Calendar.KEEP = 2 * DAY         -- the records of an event go this long after it
Calendar.TITLE_MAX = 48
Calendar.NOTE_MAX = 120
Calendar.SIZE_MIN, Calendar.SIZE_MAX = 5, 40
Calendar.N_MAX = 99999
Calendar.MAX_BYTES = 512        -- of an R:, F: or A: record
Calendar.ANSWERS = { yes = true, maybe = true, no = true }
Calendar.SPECS = { ms1 = true, ms2 = true, class = true }

local function now() return ns.Compat and ns.Compat.ServerTime() or time() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function S() return ns.Store end
local function Cal() return ns.Compat.Calendar end

function Calendar.Enabled()
	return ns.Features ~= nil and ns.Features.On("season")
end

---------------------------------------------------------------------------------------------------------------------
-- Times
---------------------------------------------------------------------------------------------------------------------
-- Seconds since 1970 of a calendar date and time read as UTC (the realm's clock of the calendar); deterministic, no
-- dependence on the computer's time zone. nil for an impossible date.
function Calendar.Stamp(y, m, d, h, mi)
	if type(y) ~= "number" or type(m) ~= "number" or type(d) ~= "number" then return nil end
	if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
	local yy = m <= 2 and y - 1 or y
	local era = floor(yy / 400)
	local yoe = yy - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	local days = era * 146097 + doe - 719468
	return days * DAY + (h or 0) * 3600 + (mi or 0) * 60
end

-- The start of a calendar row (GetGuildEventInfo) in server seconds, or nil.
function Calendar.RowStart(row)
	return Calendar.Stamp(row.year, row.month, row.monthDay, row.hour or 0, row.minute or 0)
end

---------------------------------------------------------------------------------------------------------------------
-- Keys, ids and validation of the data set `raidev`
---------------------------------------------------------------------------------------------------------------------
function Calendar.CalendarKey(eventID) return "c" .. tostring(eventID) end
function Calendar.LocalKey(guid, n) return ("f%s:%d"):format(guid, n) end
function Calendar.RoleId(key, guid) return ("R:%s:%s"):format(key, guid) end
function Calendar.AnswerId(key, guid) return ("A:%s:%s"):format(key, guid) end
function Calendar.LocalId(guid, n) return ("F:%s:%d"):format(guid, n) end

local function isGUID(g) return type(g) == "string" and g:find(ns.Store.GUID_PATTERN) ~= nil end
local function count(n) return type(n) == "number" and n == floor(n) and n >= 1 and n <= Calendar.N_MAX end

-- "c" (calendar) or "f" (addon only) for a valid key, else nil.
function Calendar.KeyKind(key)
	if type(key) ~= "string" then return nil end
	if key:find("^c%d+$") and #key <= 21 then return "c" end
	local guid, n = key:match("^f([^:]+):(%d+)$")
	if guid and isGUID(guid) and count(tonumber(n)) then return "f" end
	return nil
end

-- The id of a local event from its key ("f<GUID>:<n>" -> "F:<GUID>:<n>").
function Calendar.LocalIdOf(key)
	if type(key) ~= "string" then return nil end
	local guid, n = key:match("^f([^:]+):(%d+)$")
	if not guid then return nil end
	return Calendar.LocalId(guid, tonumber(n))
end

-- "R", "F", "A" (M10.5), "H" (M10.6), "C" (M10.7) or nil from the id.
function Calendar.KindOf(rec)
	local id = type(rec) == "table" and rec.id
	if type(id) ~= "string" then return nil end
	local k = id:match("^([RFAHC]):")
	return k
end

-- R: and A: -> key, GUID of the character.
local function splitCharId(id)
	local key, guid = id:match("^[RA]:(.+):([^:]+)$")
	return key, guid
end
Calendar.SplitCharId = splitCharId

local function cleanText(s, maxLen, minLen)
	if type(s) ~= "string" or #s < (minLen or 0) or #s > maxLen then return false end
	return not s:find("[%c|]")
end

local function validRole(r)
	for _, role in ipairs(ns.Specs.ROLES) do if r == role then return true end end
	return false
end

-- The owner rule of the set: true, or false and a reason ("owner", "step").
function Calendar.ValidRecord(rec, store)
	store = store or S()
	local kind = Calendar.KindOf(rec)
	if kind == "H" then
		if not ns.RaidHelper then return false end
		return ns.RaidHelper.ValidRecord(rec)
	end
	if ns.Config and ns.Config.EstimateSize(rec) > Calendar.MAX_BYTES then return false, "size" end
	if kind == "R" or kind == "A" then
		local key, guid = splitCharId(rec.id)
		if not (key and Calendar.KeyKind(key) and isGUID(guid)) then return false end
		if not store:SameAccount(guid, rec.author) then return false, "owner" end
		if not validRole(rec.role) or type(rec.at) ~= "number" then return false end
		if kind == "R" then
			return Calendar.SPECS[rec.spec] == true
		end
		return Calendar.ANSWERS[rec.answer] == true
	elseif kind == "F" then
		local guid, n = rec.id:match("^F:([^:]+):(%d+)$")
		if not (isGUID(guid) and count(tonumber(n))) then return false end
		if not store:SameAccount(guid, rec.author) then return false, "owner" end
		if not cleanText(rec.title, Calendar.TITLE_MAX, 1) or type(rec.start) ~= "number" then return false end
		if type(rec.size) ~= "number" or rec.size ~= floor(rec.size) or rec.size < Calendar.SIZE_MIN or rec.size > Calendar.SIZE_MAX then
			return false
		end
		if rec.note ~= nil and not cleanText(rec.note, Calendar.NOTE_MAX) then return false end
		return true
	end
	return false, "step"                                        -- C: comes with M10.7
end

-- Officers only (NET-12): the events of the addon and the imports of Raid-Helper.
function Calendar.Authority(rec)
	local kind = Calendar.KindOf(rec)
	return kind == "F" or kind == "H"
end

-- Retention: Calendar.KEEP after the event.
function Calendar.Expired(rec, t)
	local kind = Calendar.KindOf(rec)
	local at
	if kind == "F" or kind == "H" then at = rec.start else at = rec.at end
	if type(at) ~= "number" then return true end
	return at < t - Calendar.KEEP
end

---------------------------------------------------------------------------------------------------------------------
-- The state of the game calendar
---------------------------------------------------------------------------------------------------------------------
Calendar.events = {}     -- the calendar events read last: { key, eventID, title, start, y, m, d, h, mi, raid, kind, status, answer }
Calendar.invites = {}    -- key -> { at, list = { { name, guid, classFile, status, answer, mine } }, complete }
Calendar.outcome = {}    -- key -> { ok, why, answer } of the last answer given here

-- "available" (read from the game), "missing" (the fallback of the addon) or "unknown" (still waiting).
function Calendar.State()
	return ns.Compat:Feature("calendar") or "unknown"
end

function Calendar.Usable() return Calendar.State() == "available" end
function Calendar.Fallback() return Calendar.State() == "missing" end

-- Asks the server for the calendar, once per session; Calendar.FALLBACK_WAIT later without an event list the client
-- has no usable calendar.
function Calendar:Start()
	if not Calendar.Enabled() or self.started then return false end
	local C = Cal()
	if not C.Has() then
		ns.Compat:SetFeature("calendar", "missing", "C_Calendar calls missing")
		emit("CALENDAR_CHANGED")
		return false
	end
	self.started = true
	C.Open()
	ns.Compat.After(Calendar.FALLBACK_WAIT, function()
		if not self.listSeen and Calendar.State() ~= "available" then
			ns.Compat:SetFeature("calendar", "missing", "no event list within " .. Calendar.FALLBACK_WAIT .. " s")
			emit("CALENDAR_CHANGED")
		end
	end)
	self:Read()
	return true
end

-- Every guild event the client holds now, also outside the window of the view (an imported event may be further ahead),
-- oldest first.
function Calendar:AllEvents()
	local out = {}
	if not Calendar.Enabled() then return out end
	local C = Cal()
	for _, row in ipairs(C.GuildEvents()) do
		local start = Calendar.RowStart(row)
		if start then
			out[#out + 1] = { key = Calendar.CalendarKey(row.eventID), eventID = row.eventID, title = row.title or "?",
				start = start, y = row.year, m = row.month, d = row.monthDay, h = row.hour or 0, mi = row.minute or 0,
				raid = row.eventType == ns.Compat.CALENDAR_EVENT_RAID, kind = row.calendarType,
				status = row.inviteStatus, answer = C.Answer(row.inviteStatus) }
		end
	end
	sort(out, function(a, b)
		if a.start ~= b.start then return a.start < b.start end
		return a.eventID < b.eventID
	end)
	return out
end

-- Reads the guild events again. Returns the list.
function Calendar:Read()
	if not Calendar.Enabled() then return {} end
	local C = Cal()
	local t = now()
	local out = {}
	for _, e in ipairs(self:AllEvents()) do
		if e.start >= t - Calendar.PAST_DAYS * DAY and e.start <= t + Calendar.AHEAD_DAYS * DAY then out[#out + 1] = e end
	end
	self.events = out
	emit("CALENDAR_CHANGED")
	return out
end

function Calendar:Event(key)
	for _, e in ipairs(self.events) do
		if e.key == key then return e end
	end
	return nil
end

-- Why Accord may not open an event now: nil, or "off", "calendar", "combat", "encounter", "shown", "pending", "busy".
function Calendar:Blocked()
	if not Calendar.Enabled() then return "off" end
	if not Calendar.Usable() then return "calendar" end
	if ns.Compat.InCombat() then return "combat" end
	if ns.Compat.EncounterInProgress() then return "encounter" end
	local C = Cal()
	if C.FrameShown() then return "shown" end
	if C.Pending() then return "pending" end
	if self.open then return "busy" end
	return nil
end

-- Opens a calendar event; the caller closes it (Calendar:Finish).
local function openEvent(self, e, purpose)
	local why = self:Blocked()
	if why then return false, why end
	if not Cal().OpenEvent(e.eventID) then return false, "open" end
	self.open = { key = e.key, eventID = e.eventID, purpose = purpose, at = now() }
	return true
end

-- Reads the answers of the open event into Calendar.invites.
local function readInvites(self, key, complete)
	local list = {}
	for _, i in ipairs(Cal().Invites()) do
		list[#list + 1] = { name = i.name, guid = i.guid, classFile = i.classFile, status = i.status, answer = Cal().Answer(i.status),
			mine = i.mine }
	end
	sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
	self.invites[key] = { at = now(), list = list, complete = complete and true or nil }
end

-- Holds the client's one open event for a job that writes into the calendar (Data/RaidHelper.lua): `open` = { key,
-- eventID?, ended = function(why) }. The caller asked Calendar:Blocked() first. `ended` runs when Calendar:Finish closes
-- the event or the game takes it.
function Calendar:Hold(open)
	if self.open then return false end
	open.purpose, open.at = "import", now()
	self.open = open
	return true
end

-- Closes the held event without ending its job (a created event, before it is opened again).
function Calendar:Release()
	if not (self.open and self.open.purpose == "import") then return false end
	self.open = nil
	Cal().CloseEvent()
	return true
end

-- Reads the answers of the held event, when it is a calendar event.
function Calendar:ReadHeld(complete)
	local o = self.open
	if o and Calendar.KeyKind(o.key) == "c" then readInvites(self, o.key, complete) end
end

-- Closes the event Accord opened. `why` nil: done.
function Calendar:Finish(why)
	local o = self.open
	if not o then return false end
	self.open = nil
	if o.purpose == "import" then
		Cal().CloseEvent()
		if o.ended then o.ended(why) end
		self:Read()
	elseif o.purpose == "answer" then
		local info = Cal().EventInfo()
		local status = info and info.inviteStatus
		readInvites(self, o.key, false)
		Cal().CloseEvent()
		local got = Cal().Answer(status)
		local res = self.outcome[o.key] or {}
		if why then
			res.ok, res.why = false, why
		else
			res.ok = got == res.answer
			res.why = not res.ok and "server" or nil
		end
		res.pending = nil
		self.outcome[o.key] = res
		self:Read()
	else
		if not why then readInvites(self, o.key, true) end
		Cal().CloseEvent()
	end
	emit("EVENT_CHANGED", o.key)
	return true
end

-- Reads the answers of one calendar event (the Events view shows it). True when the event was opened.
function Calendar:LoadInvites(key)
	local e = self:Event(key)
	if not e then return false, "missing" end
	local ok, why = openEvent(self, e, "invites")
	if not ok then return false, why end
	readInvites(self, key, false)
	-- the full list comes with CALENDAR_UPDATE_INVITE_LIST; if it does not come, close after ANSWER_WAIT
	ns.Compat.After(Calendar.ANSWER_WAIT, function()
		if self.open and self.open.key == key and self.open.purpose == "invites" then self:Finish() end
	end)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The role
---------------------------------------------------------------------------------------------------------------------
local function classOf(guid)
	local member = ns.Roster and ns.Roster.ByGUID and ns.Roster:ByGUID(guid)
	if member and member.classFile then return member.classFile end
	if guid == ns.Compat.Player.GUID() then return ns.Compat.Player.ClassFile() end
	return nil
end

-- The class's default role: the first role of its first tree.
function Calendar.ClassRole(classFile)
	local specs = ns.Specs.Of(classFile)
	local first = specs and specs[1]
	local roles = first and ns.Specs.Roles(classFile, first.spec)
	return roles and roles[1] or nil
end

-- The roles of the others signed up (yes or maybe) to the event: role -> count.
function Calendar:RoleCounts(key, except)
	local counts = {}
	for _, role in ipairs(ns.Specs.ROLES) do counts[role] = 0 end
	local local_ = Calendar.KeyKind(key) == "f"
	-- a calendar event: the answers read from the calendar when they were (an R: record is written only with yes or
	-- maybe, so without them every R: counts); an event of the addon: its A: records
	local answers
	local inv = self.invites[key]
	if inv and not local_ then
		answers = {}
		for _, i in ipairs(inv.list) do if i.guid then answers[i.guid] = i.answer end end
	end
	for _, rec in pairs(S():Records(Calendar.SET)) do
		local kind = Calendar.KindOf(rec)
		if kind == (local_ and "A" or "R") then
			local k, guid = splitCharId(rec.id)
			if k == key and guid ~= except and not (except and S():SameAccount(guid, except)) then
				local answer = "yes"
				if local_ then answer = rec.answer elseif answers then answer = answers[guid] end
				if (answer == "yes" or answer == "maybe") and counts[rec.role] then counts[rec.role] = counts[rec.role] + 1 end
			end
		end
	end
	return counts
end

-- The role to preselect for this character and event: role, from ("ms1" | "ms2" | "class" | "held").
function Calendar:SuggestRole(key)
	local me = ns.Compat.Player.GUID()
	if not me then return nil end
	local held = S():Get(Calendar.SET, Calendar.RoleId(key, me)) or S():Get(Calendar.SET, Calendar.AnswerId(key, me))
	if held and held.role then return held.role, "held" end
	local own
	if ns.Season and ns.Season.Source() == "accord" then
		local cur = ns.Season:Current()
		own = cur and ns.Season:Own(cur.n) or nil
		if own and own.unsure then own = nil end
	elseif ns.Integrations then
		local p = ns.Integrations:Provider("raid")
		local e = p and p.Entry and p.Entry(ns.Compat.Player.Name())
		if e and e.ms1 then own = e end
	end
	if own and own.ms1 then
		local target = ns.Composition and ns.Composition:Target()
		if own.ms2 and target then
			local counts = self:RoleCounts(key, me)
			local r1, r2 = own.ms1.role, own.ms2.role
			if (counts[r1] or 0) >= (target[r1] or 0) and (counts[r2] or 0) < (target[r2] or 0) then return r2, "ms2" end
		end
		return own.ms1.role, "ms1"
	end
	local role = Calendar.ClassRole(classOf(me))
	return role, role and "class" or nil
end

-- Writes the own role for an event. Returns the record, or nil and a reason.
function Calendar:SetRole(key, role, from)
	if not Calendar.Enabled() then return nil, "off" end
	local me = ns.Compat.Player.GUID()
	if not me then return nil, "player" end
	if not validRole(role) then return nil, "role" end
	local at
	local kind = Calendar.KeyKind(key)
	if kind == "c" then
		local e = self:Event(key)
		at = e and e.start
	elseif kind == "f" then
		local f = S():Get(Calendar.SET, Calendar.LocalIdOf(key))
		at = f and f.start
	end
	if not at then return nil, "missing" end
	if from ~= "ms1" and from ~= "ms2" then from = "class" end
	local id = Calendar.RoleId(key, me)
	local held = S():Get(Calendar.SET, id)
	if held and held.role == role and held.spec == from and held.at == at then return held end
	return S():Put(Calendar.SET, id, { role = role, spec = from, at = at })
end

---------------------------------------------------------------------------------------------------------------------
-- Answering
---------------------------------------------------------------------------------------------------------------------
local CALLS = { maybe = "tentative", no = "decline" }

-- The call for "yes": EventSignUp on a guild sign-up event not answered yet, EventAvailable otherwise [verify].
function Calendar.YesCall(info, status)
	local st = Cal().Status()
	local answered = type(status) == "number" and status ~= st.NotSignedup and status ~= st.Invited
	if info and info.calendarType == "GUILD_EVENT" and not answered then return "signup" end
	return "available"
end

-- The player's answer to an event, from a click: answer = "yes" | "maybe" | "no"; role optional (kept in R: or A:).
-- A calendar event: the answer goes into the game calendar (true, "pending" while the server answers). An event of
-- the addon: the record A:. Returns true, or false and a reason.
function Calendar:Answer(key, answer, role)
	if not Calendar.Enabled() then return false, "off" end
	if not Calendar.ANSWERS[answer] then return false, "answer" end
	local kind = Calendar.KeyKind(key)
	if kind == "f" then return self:AnswerLocal(key, answer, role) end
	local e = self:Event(key)
	if not e then return false, "missing" end
	local ok, why = openEvent(self, e, "answer")
	if not ok then return false, why end
	local info = Cal().EventInfo()
	local call = answer == "yes" and Calendar.YesCall(info, info and info.inviteStatus or e.status) or CALLS[answer]
	self.outcome[key] = { answer = answer, pending = true, call = call }
	self.blockedCall = nil
	local state = Cal().Respond(call)
	if state ~= ns.Compat.AVAILABLE or self.blockedCall then
		self:Finish("blocked")
		Cal().ShowGame()
		return false, "blocked"
	end
	if role and answer ~= "no" then
		local suggested, from = self:SuggestRole(key)
		self:SetRole(key, role, role == suggested and from ~= "held" and from or nil)
	end
	ns.Compat.After(Calendar.ANSWER_WAIT, function()
		if self.open and self.open.key == key and self.open.purpose == "answer" then self:Finish("timeout") end
	end)
	emit("EVENT_CHANGED", key)
	return true, "pending"
end

-- An answer to an event of the addon: A:<key>:<GUID>.
function Calendar:AnswerLocal(key, answer, role)
	local f = S():Get(Calendar.SET, Calendar.LocalIdOf(key) or "")
	if not f then return false, "missing" end
	local me = ns.Compat.Player.GUID()
	if not me then return false, "player" end
	role = role or self:SuggestRole(key)
	if not validRole(role) then return false, "role" end
	local rec, why = S():Put(Calendar.SET, Calendar.AnswerId(key, me), { answer = answer, role = role, at = f.start })
	if not rec then return false, why end
	self.outcome[key] = { answer = answer, ok = true }
	emit("EVENT_CHANGED", key)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Events only of the addon (the fallback, SPEC-14 §5.4)
---------------------------------------------------------------------------------------------------------------------
function Calendar:CanCreateLocal()
	return Calendar.Enabled() and Calendar.Fallback() and ns.Raid ~= nil and ns.Raid.CanWrite()
end

-- An officer creates an event of the addon. start: server time. Returns the record, or nil and a reason: "off",
-- "calendar" (the client has a usable calendar, or is still waiting for it), "officer", "title", "start", "size", "note".
function Calendar:CreateLocal(title, start, size, note)
	if not Calendar.Enabled() then return nil, "off" end
	if not Calendar.Fallback() then return nil, "calendar" end
	if not (ns.Raid and ns.Raid.CanWrite()) then return nil, "officer" end
	if type(title) == "string" then title = title:gsub("^%s+", ""):gsub("%s+$", "") end
	if not cleanText(title, Calendar.TITLE_MAX, 1) then return nil, "title" end
	local t = now()
	if type(start) ~= "number" or start < t - 3600 or start > t + 60 * DAY then return nil, "start" end
	size = tonumber(size) or 0
	if size ~= floor(size) or size < Calendar.SIZE_MIN or size > Calendar.SIZE_MAX then return nil, "size" end
	if note == "" then note = nil end
	if note ~= nil and not cleanText(note, Calendar.NOTE_MAX) then return nil, "note" end
	local me = ns.Compat.Player.GUID()
	local n = 0
	for _, rec in pairs(S():Records(Calendar.SET)) do
		if type(rec.id) == "string" then
			local guid, k = rec.id:match("^F:([^:]+):(%d+)$")
			if guid == me and tonumber(k) > n then n = tonumber(k) end
		end
	end
	return S():Put(Calendar.SET, Calendar.LocalId(me, n + 1), { title = title, start = start, size = size, note = note })
end

-- The events of the addon held (also on a client with a calendar: they are shown marked), oldest first:
-- { key, id, title, start, size, note, author, rec }.
function Calendar:LocalEvents()
	local out, t = {}, now()
	for _, rec in pairs(S():Records(Calendar.SET)) do
		if Calendar.KindOf(rec) == "F" and rec.start >= t - Calendar.PAST_DAYS * DAY then
			local guid, n = rec.id:match("^F:([^:]+):(%d+)$")
			out[#out + 1] = { key = Calendar.LocalKey(guid, tonumber(n)), id = rec.id, title = rec.title, start = rec.start,
				size = rec.size, note = rec.note, author = rec.author, rec = rec, addonOnly = true }
		end
	end
	sort(out, function(a, b)
		if a.start ~= b.start then return a.start < b.start end
		return a.id < b.id
	end)
	return out
end

-- The answers to an event of the addon: { { guid, name, answer, role } }, by name.
function Calendar:LocalAnswers(key)
	local out = {}
	for _, rec in pairs(S():Records(Calendar.SET)) do
		if Calendar.KindOf(rec) == "A" then
			local k, guid = splitCharId(rec.id)
			if k == key then
				local member = ns.Roster and ns.Roster:ByGUID(guid)
				out[#out + 1] = { guid = guid, name = member and member.name or nil, answer = rec.answer, role = rec.role,
					mine = guid == ns.Compat.Player.GUID() }
			end
		end
	end
	sort(out, function(a, b) return tostring(a.name or a.guid) < tostring(b.name or b.guid) end)
	return out
end

-- The role written for a character and an event (R: or A:), or nil.
function Calendar:RoleOf(key, guid)
	local rec = S():Get(Calendar.SET, Calendar.RoleId(key, guid)) or S():Get(Calendar.SET, Calendar.AnswerId(key, guid))
	return rec and rec.role or nil
end

function Calendar:DebugLines()
	local roles, locals, answers = 0, 0, 0
	for _, rec in pairs(S():Records(Calendar.SET)) do
		local k = Calendar.KindOf(rec)
		if k == "R" then roles = roles + 1 elseif k == "F" then locals = locals + 1 elseif k == "A" then answers = answers + 1 end
	end
	return { ("Calendar: %s, %d guild events, %d roles, %d addon events, %d addon answers%s"):format(Calendar.State(),
		#self.events, roles, locals, answers, self.open and ", an event is open" or "") }
end

---------------------------------------------------------------------------------------------------------------------
-- Events of the game
---------------------------------------------------------------------------------------------------------------------
function Calendar:OnEventList()
	if not Calendar.Enabled() then return end
	self.listSeen = true
	if Calendar.State() ~= "available" then ns.Compat:SetFeature("calendar", "available", "event list received") end
	self:Read()
end

function Calendar:OnInviteList(complete)
	local o = self.open
	if not o then return end
	if o.purpose == "invites" then
		readInvites(self, o.key, complete)
		if complete then self:Finish() else emit("EVENT_CHANGED", o.key) end
	elseif o.purpose == "answer" then
		self:AnswerSeen()
	end
end

-- While an answer waits: closes the event once the own status in it is the answer given (the list of answers and the
-- event are also sent when the event opens, before the server took the answer); an error or the timeout closes it too.
function Calendar:AnswerSeen()
	local o = self.open
	if not (o and o.purpose == "answer") then return false end
	local res = self.outcome[o.key]
	local info = Cal().EventInfo()
	if res and info and Cal().Answer(info.inviteStatus) == res.answer then
		self:Finish()
		return true
	end
	return false
end

function Calendar:Reset()
	self.events, self.invites, self.outcome, self.open = {}, {}, {}, nil
end

if ns.addon then
	ns.addon.Calendar = Calendar
	LibStub("AceEvent-3.0"):Embed(Calendar)
	Calendar:RegisterEvent("PLAYER_ENTERING_WORLD", function() if Calendar.Enabled() then Calendar:Start() end end)
	Calendar:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", function() Calendar:OnEventList() end)
	Calendar:RegisterEvent("CALENDAR_UPDATE_GUILD_EVENTS", function() Calendar:OnEventList() end)
	Calendar:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST", function(_, complete) Calendar:OnInviteList(complete) end)
	Calendar:RegisterEvent("CALENDAR_UPDATE_EVENT", function() Calendar:AnswerSeen() end)
	Calendar:RegisterEvent("CALENDAR_UPDATE_ERROR", function()
		if Calendar.open then Calendar:Finish("error") end
	end)
	for _, event in ipairs({ "CALENDAR_UPDATE_ERROR_WITH_COUNT", "CALENDAR_UPDATE_ERROR_WITH_PLAYER_NAME" }) do
		Calendar:RegisterEvent(event, function()
			if Calendar.open then Calendar:Finish("error") end
		end)
	end
	-- the game's window took the open event: Accord lets go and reads again later
	Calendar:RegisterEvent("CALENDAR_OPEN_EVENT", function()
		local o = Calendar.open
		if o and Cal().FrameShown() then
			Calendar.open = nil
			if o.purpose == "answer" then
				local res = Calendar.outcome[o.key] or {}
				res.ok, res.why, res.pending = false, "shown", nil
				Calendar.outcome[o.key] = res
			elseif o.ended then
				o.ended("shown")
			end
			emit("EVENT_CHANGED", o.key)
		end
	end)
	Calendar:RegisterEvent("ADDON_ACTION_BLOCKED", function(_, addon, fn)
		if addon == ADDON_NAME and type(fn) == "string" and fn:find("C_Calendar", 1, true) then Calendar.blockedCall = fn end
	end)
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set ~= Calendar.SET or not Calendar.Enabled() then return end
			local kind = Calendar.KindOf({ id = id })
			if kind == "R" or kind == "A" then
				local key = splitCharId(id)
				emit("EVENT_CHANGED", key)
			else
				emit("CALENDAR_CHANGED")
			end
		end)
		ns.Bus:On("GUILD_CHANGED", function() Calendar:Reset() emit("CALENDAR_CHANGED") end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if Calendar.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Calendar", function() return Calendar:DebugLines() end)
			end
		end)
	end
end

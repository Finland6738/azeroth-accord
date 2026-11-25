-- Mock client, part 7b: the game calendar (Accord, M10.5, M10.6; SPEC-14 §5, §6.5).
--
-- Imitates the part of C_Calendar that Accord reads and writes: OpenCalendar, GetNumGuildEvents, GetGuildEventInfo,
-- GetEventIndexInfo, OpenEvent, GetEventInfo, GetNumInvites, EventGetInvite, CloseEvent, IsActionPending, EventSignUp,
-- EventAvailable, EventTentative, EventDecline, with the events CALENDAR_UPDATE_EVENT_LIST, CALENDAR_UPDATE_GUILD_EVENTS,
-- CALENDAR_OPEN_EVENT, CALENDAR_UPDATE_INVITE_LIST(hasCompleteList), CALENDAR_UPDATE_ERROR and ADDON_ACTION_BLOCKED;
-- the globals CalendarFrame, ToggleCalendar, and C_InstanceEncounter.IsEncounterInProgress. M10.6 adds the writing
-- calls: CanAddEvent, CreateGuildSignUpEvent, EventSetTitle, EventSetDescription, EventSetDate(month, day, year),
-- EventSetTime, EventSetType, AddEvent, EventCanEdit, CanSendInvite, EventInvite, EventSetInviteStatus,
-- EventGetStatusOptions, the global CanEditGuildEvent and the event CALENDAR_ACTION_PENDING(pending). Dump: all of them are in
-- the Forever dump (the Calendar system, the globals). Enum.CalendarStatus is not set: its values are not in the dump,
-- so Accord's own constant (Compat.CALENDAR_STATUS) is what the tests use.
--
-- C_Calendar is missing by default (the other tests see a client without it). Configure (kept across Mock.Reload):
--   Mock.calendar.Set{ silent = true,       -- OpenCalendar never answers (a client without a usable calendar)
--                      protected = true,    -- the answer calls work only inside a click (Mock.hardware > 0)
--                      refuse = true,       -- the server answers CALENDAR_UPDATE_ERROR to every answer
--                      -- what this character may write (all true when left out):
--                      create = false,      -- CanAddEvent is false
--                      edit = false,        -- EventCanEdit is false (an event of its own, e.mine, can still be edited)
--                      invite = false,      -- CanSendInvite is false
--                      status = false,      -- CanEditGuildEvent is false
--                      refuseWrite = n,     -- the server answers CALENDAR_UPDATE_ERROR from the n-th write on
--                      silentWrite = n }    -- the server never answers from the n-th write on
--   Mock.calendar.writes      { { call, name?, status?, eventID } } of the writes that went through
--   Mock.calendar.maxFlight   the most writes waiting for the server at once
--   Mock.calendar.Add{ eventID, title, at = <server time>, calendarType = "GUILD_EVENT", eventType = 0, own = <status>,
--                      invites = { { name, guid, classFilename, inviteStatus } } }   a guild event, whoever created it
--   Mock.calendar.GameAnswer(eventID, status)   the player answers in the game's calendar window
--   Mock.calendar.ShowFrame(shown)              the game's calendar window is shown or hidden
--   Mock.calendar.calls       { { call, eventID } } of the answer calls that went through
--   Mock.calendar.opened, closed, blocked, toggled   counters; Mock.calendar.open the open event or nil
--   Mock.calendar.pending     IsActionPending
--   Mock.calendar.Off()       C_Calendar is gone
-- The server answers one frame later (C_Timer.After(0)).
local Mock, H = ...
local W = Mock.world

W.calendar = W.calendar or { on = false, events = {} }
local cal = W.calendar
Mock.calendar = cal
cal.calls = cal.calls or {}
cal.writes, cal.flight, cal.maxFlight = cal.writes or {}, cal.flight or 0, cal.maxFlight or 0
cal.opened, cal.closed, cal.blocked, cal.toggled = cal.opened or 0, cal.closed or 0, cal.blocked or 0, cal.toggled or 0

local STATUS = { Invited = 0, Available = 1, Declined = 2, Confirmed = 3, Out = 4, Standby = 5, Signedup = 6, NotSignedup = 7,
	Tentative = 8 }
cal.STATUS = STATUS

local function copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = copy(v) end
	return out
end

local function find(eventID)
	for i, e in ipairs(cal.events) do
		if e.eventID == eventID then return e, i end
	end
	return nil
end

local function later(fn) C_Timer.After(0, fn) end

local function protected(name)
	if not cal.protected or (Mock.hardware or 0) > 0 then return true end
	cal.blocked = cal.blocked + 1
	Mock.Fire("ADDON_ACTION_BLOCKED", "AzerothAccord", "C_Calendar." .. name .. "()")
	return false
end

local function guildInfo(e)
	local d = date("!*t", e.at)
	return { eventID = e.eventID, year = d.year, month = d.month, monthDay = d.day, weekday = d.wday, hour = d.hour,
		minute = d.min, eventType = e.eventType or 0, title = e.title, calendarType = e.calendarType or "GUILD_EVENT",
		texture = 0, inviteStatus = e.own or STATUS.NotSignedup, clubID = "1" }
end

local function answer(name, status)
	return function()
		if not protected(name) then return end
		local e = cal.open
		if not e then return end
		cal.calls[#cal.calls + 1] = { call = name, eventID = e.eventID }
		later(function()
			if cal.refuse then
				Mock.Fire("CALENDAR_UPDATE_ERROR", "refused")
				return
			end
			e.own = status
			Mock.Fire("CALENDAR_UPDATE_EVENT")
			Mock.Fire("CALENDAR_UPDATE_INVITE_LIST", true)
			Mock.Fire("CALENDAR_UPDATE_GUILD_EVENTS")
		end)
	end
end

-- A write the server answers one frame later: pending until then, `apply` when it accepts.
local function write(row, apply)
	cal.writes[#cal.writes + 1] = row
	local n = #cal.writes
	cal.pending = true
	cal.flight = cal.flight + 1
	cal.maxFlight = math.max(cal.maxFlight, cal.flight)
	Mock.Fire("CALENDAR_ACTION_PENDING", true)
	if cal.silentWrite and n >= cal.silentWrite then return end
	later(function()
		cal.pending = false
		cal.flight = cal.flight - 1
		if cal.refuseWrite and n >= cal.refuseWrite then
			Mock.Fire("CALENDAR_ACTION_PENDING", false)
			Mock.Fire("CALENDAR_UPDATE_ERROR", "refused")
			return
		end
		apply()
		Mock.Fire("CALENDAR_ACTION_PENDING", false)
	end)
end

local function memberNamed(name)
	for _, m in ipairs(Mock.world.guild and Mock.world.guild.members or {}) do
		if m.name == name or (m.name or ""):match("^([^%-]+)") == name then return m end
	end
	return nil
end

-- The invite rows of an event as the client lists them: the others, then the player's own.
local function writable(e, index)
	local rows = e.invites or {}
	if index <= #rows then return rows[index] end
	return nil
end

local function invites(e)
	local list = {}
	for _, i in ipairs(e.invites or {}) do list[#list + 1] = copy(i) end
	if e.own and e.own ~= STATUS.NotSignedup then
		list[#list + 1] = { name = Mock.player.name, guid = Mock.player.guid, classFilename = Mock.player.classFile,
			inviteStatus = e.own, inviteIsMine = true }
	end
	return list
end

local function install()
	local api = {}
	function api.OpenCalendar()
		if cal.silent then return end
		later(function() Mock.Fire("CALENDAR_UPDATE_EVENT_LIST") end)
	end
	function api.GetNumGuildEvents() return #cal.events end
	function api.GetGuildEventInfo(i)
		local e = cal.events[i]
		return e and guildInfo(e) or nil
	end
	function api.GetEventIndexInfo(eventID)
		local e = find(eventID)
		if not e then return nil end
		local d = date("!*t", e.at)
		local idx = 0
		for _, other in ipairs(cal.events) do
			local od = date("!*t", other.at)
			if od.year == d.year and od.month == d.month and od.day == d.day then
				idx = idx + 1
				if other == e then break end
			end
		end
		return { offsetMonths = 0, monthDay = d.day, eventIndex = idx }
	end
	function api.OpenEvent(offset, day, index)
		local idx = 0
		for _, e in ipairs(cal.events) do
			local d = date("!*t", e.at)
			if d.day == day then
				idx = idx + 1
				if idx == index then
					cal.open = e
					cal.opened = cal.opened + 1
					later(function()
						Mock.Fire("CALENDAR_OPEN_EVENT", "PLAYER")
						if cal.open == e then Mock.Fire("CALENDAR_UPDATE_INVITE_LIST", true) end
					end)
					return true
				end
			end
		end
		return false
	end
	function api.GetEventInfo()
		local e = cal.open
		if not e then return nil end
		return { title = e.title, calendarType = e.calendarType or "GUILD_EVENT", inviteStatus = e.own or STATUS.NotSignedup,
			inviteType = 1, isLocked = false, eventType = e.eventType or 0 }
	end
	function api.GetNumInvites() return cal.open and #invites(cal.open) or 0 end
	function api.EventGetInvite(i)
		local row = cal.open and invites(cal.open)[i]
		if not row then return nil end
		return { name = row.name, level = 60, className = row.classFilename, classFilename = row.classFilename,
			inviteStatus = row.inviteStatus, modStatus = "", inviteIsMine = row.inviteIsMine == true, type = 1, notes = "",
			classID = 1, guid = row.guid }
	end
	function api.CloseEvent()
		if cal.open then cal.closed = cal.closed + 1 end
		cal.open = nil
	end
	function api.IsActionPending() return cal.pending == true end
	api.EventSignUp = answer("EventSignUp", STATUS.Signedup)
	api.EventAvailable = answer("EventAvailable", STATUS.Available)
	api.EventTentative = answer("EventTentative", STATUS.Tentative)
	api.EventDecline = answer("EventDecline", STATUS.Declined)
	function api.CanAddEvent() return cal.create ~= false end
	function api.CreateGuildSignUpEvent()
		cal.draft = { calendarType = "GUILD_EVENT" }
	end
	function api.EventSetTitle(title) if cal.draft then cal.draft.title = title end end
	function api.EventSetDescription(text) if cal.draft then cal.draft.description = text end end
	function api.EventSetDate(month, day, year) if cal.draft then cal.draft.month, cal.draft.day, cal.draft.year = month, day, year end end
	function api.EventSetTime(hour, minute) if cal.draft then cal.draft.hour, cal.draft.minute = hour, minute end end
	function api.EventSetType(kind) if cal.draft then cal.draft.eventType = kind end end
	function api.AddEvent()
		local d = cal.draft
		if not d or not protected("AddEvent") then return end
		cal.draft = nil
		write({ call = "AddEvent", name = d.title }, function()
			-- the date and time as UTC, as guildInfo reads them back
			local y, m = d.year, d.month
			if m <= 2 then y = y - 1 end
			local era = math.floor(y / 400)
			local yoe = y - era * 400
			local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d.day - 1
			local days = era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
			cal.nextID = (cal.nextID or 900) + 1
			cal.events[#cal.events + 1] = { eventID = cal.nextID, title = d.title, at = days * 86400 + d.hour * 3600 + d.minute * 60,
				calendarType = d.calendarType, eventType = d.eventType, description = d.description, mine = true, invites = {},
				own = STATUS.Confirmed }
			Mock.Fire("CALENDAR_UPDATE_EVENT_LIST")
			Mock.Fire("CALENDAR_UPDATE_GUILD_EVENTS")
		end)
	end
	function api.EventCanEdit()
		local e = cal.open
		return e ~= nil and (e.mine == true or cal.edit ~= false)
	end
	function api.CanSendInvite() return cal.invite ~= false end
	function api.EventInvite(name)
		local e = cal.open
		if not e then return end
		write({ call = "EventInvite", name = name, eventID = e.eventID }, function()
			local m = memberNamed(name)
			e.invites = e.invites or {}
			e.invites[#e.invites + 1] = { name = name, guid = m and m.guid, classFilename = m and m.class, inviteStatus = STATUS.Invited }
			Mock.Fire("CALENDAR_UPDATE_INVITE_LIST", true)
		end)
	end
	function api.EventGetStatusOptions()
		local out = {}
		for name, value in pairs(STATUS) do out[#out + 1] = { status = value, statusString = name } end
		return out
	end
	function api.EventSetInviteStatus(index, status)
		local e = cal.open
		local row = e and writable(e, index)
		if not row then return end
		write({ call = "EventSetInviteStatus", name = row.name, status = status, eventID = e.eventID }, function()
			row.inviteStatus = status
			Mock.Fire("CALENDAR_UPDATE_EVENT")
			Mock.Fire("CALENDAR_UPDATE_INVITE_LIST", true)
		end)
	end
	function CanEditGuildEvent() return cal.status ~= false end
	C_Calendar = api
	function ToggleCalendar()
		cal.toggled = cal.toggled + 1
		cal.ShowFrame(not cal.shown)
	end
end

function cal.ShowFrame(shown)
	cal.shown = shown and true or false
	CalendarFrame = { IsShown = function() return cal.shown end }
end

function cal.Set(config)
	config = config or {}
	cal.on = true
	cal.silent = config.silent == true
	cal.protected = config.protected == true
	cal.refuse = config.refuse == true
	cal.create, cal.edit, cal.invite, cal.status = config.create, config.edit, config.invite, config.status
	cal.refuseWrite, cal.silentWrite = config.refuseWrite, config.silentWrite
	install()
end

function cal.Add(e)
	cal.events[#cal.events + 1] = e
	return e
end

-- The player answers in the game's window: the client tells the addons with CALENDAR_UPDATE_GUILD_EVENTS.
function cal.GameAnswer(eventID, status)
	local e = find(eventID)
	if not e then return false end
	e.own = status
	Mock.Fire("CALENDAR_UPDATE_GUILD_EVENTS")
	return true
end

function cal.Off()
	cal.on = false
	C_Calendar = nil
end

if cal.on then install() end
if cal.shown ~= nil then cal.ShowFrame(cal.shown) end

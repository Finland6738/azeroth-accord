-- Mock client, part 7b: the game calendar (Accord, M10.5; SPEC-14 §5).
--
-- Imitates the part of C_Calendar that Accord reads and writes: OpenCalendar, GetNumGuildEvents, GetGuildEventInfo,
-- GetEventIndexInfo, OpenEvent, GetEventInfo, GetNumInvites, EventGetInvite, CloseEvent, IsActionPending, EventSignUp,
-- EventAvailable, EventTentative, EventDecline, with the events CALENDAR_UPDATE_EVENT_LIST, CALENDAR_UPDATE_GUILD_EVENTS,
-- CALENDAR_OPEN_EVENT, CALENDAR_UPDATE_INVITE_LIST(hasCompleteList), CALENDAR_UPDATE_ERROR and ADDON_ACTION_BLOCKED;
-- the globals CalendarFrame, ToggleCalendar, and C_InstanceEncounter.IsEncounterInProgress. Dump: all of them are in
-- the Forever dump (the Calendar system, the globals). Enum.CalendarStatus is not set: its values are not in the dump,
-- so Accord's own constant (Compat.CALENDAR_STATUS) is what the tests use.
--
-- C_Calendar is missing by default (the other tests see a client without it). Configure (kept across Mock.Reload):
--   Mock.calendar.Set{ silent = true,       -- OpenCalendar never answers (a client without a usable calendar)
--                      protected = true,    -- the answer calls work only inside a click (Mock.hardware > 0)
--                      refuse = true }      -- the server answers CALENDAR_UPDATE_ERROR to every answer
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

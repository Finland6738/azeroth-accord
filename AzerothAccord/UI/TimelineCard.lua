-- TimelineCard: the "Timeline" section of the member card, for officers only (SPEC-12 §2.4, M8.2). Lua 5.1.
-- The section lists the observed roster changes of every character of the member's account in the guild (newest first, with
-- the character's name), the ten latest and "Show all", the oldest known join as "Member since", and the state of the officer
-- channel. A member never gets the section: Officer.CanSee("timeline") is false and the function returns nothing.
-- UI.Describe(entry) is a plain function (tested offline): { id, title, count, lines = { { text, muted, tip, onClick, action } } }.
-- The Timeline page of the Officers tab (SPEC-12 §8) comes with the tab; until then "Show all" opens the list in the card.
local ADDON_NAME, ns = ...
ns = ns or {}
local L = ns.L
local UI = {}
ns.TimelineCard, ns.modules = UI, ns.modules or {}
ns.modules.TimelineCard = UI

UI.MAX_ALL = 100         -- lines of the opened list (the page of the tab will show the rest)
UI.expanded = nil        -- the GUID of the card whose list is open

local function nameOf(guid, fallback)
	local entry = ns.Roster and ns.Roster:ByGUID(guid)
	return entry and (entry.short or entry.name) or fallback
end

-- The characters whose changes the card lists: the proved characters of the account, or the character alone.
local function guidsOf(guid)
	local A = ns.Accounts
	local list = A and A:ProvedChars(guid) or { guid }
	return #list > 0 and list or { guid }
end

local function tipOf(ev)
	local T = ns.Timeline
	local tip = { L["TL_TIP_TITLE"], L["TL_SEEN_BY"]:format(table.concat(T.ObserverNames(ev), ", ")) }
	tip[#tip + 1] = L["TL_BETWEEN_EXACT"]:format(date("!%Y-%m-%d %H:%M", ev.a), date("!%Y-%m-%d %H:%M", ev.b))
	return tip
end

function UI.Describe(entry)
	local Officer, T = ns.Officer, ns.Timeline
	if not (Officer and T and Officer.CanSee("timeline")) then return nil end
	if type(entry) ~= "table" or type(entry.guid) ~= "string" then return nil end
	local events = T:EventsOf(guidsOf(entry.guid))
	local lines = {}
	local since = T.OldestJoin(events)
	lines[1] = { text = since and L["TL_SINCE"]:format(date("!%Y-%m-%d", since)) or L["TL_SINCE_UNKNOWN"], muted = true }
	local open = UI.expanded == entry.guid
	local limit = open and UI.MAX_ALL or T.SHOWN
	for i = 1, math.min(#events, limit) do
		local ev = events[i]
		lines[#lines + 1] = { text = T.LineText(ev, nameOf(ev.g, ev.n)), tip = tipOf(ev) }
	end
	if #events == 0 then lines[#lines + 1] = { text = L["TL_EMPTY"], muted = true } end
	if #events > T.SHOWN then
		if open then
			lines[#lines + 1] = { text = L["TL_SHOW_LESS"], action = true, onClick = function()
				UI.expanded = nil
				if ns.MemberCard then ns.MemberCard:Refresh() end
			end }
		else
			lines[#lines + 1] = { text = L["TL_SHOW_ALL"]:format(#events), action = true, onClick = function()
				UI.expanded = entry.guid
				if ns.MemberCard then ns.MemberCard:Refresh() end
			end }
		end
	end
	-- the officer channel: the data stays here until it works (OFF-07)
	local proven = Officer.ChannelProven()
	lines[#lines + 1] = { text = proven and L["TL_CHANNEL_OK"] or L["TL_CHANNEL_NO"], muted = true }
	if not proven then lines[#lines + 1] = { text = L["TL_LOCAL_ONLY"], muted = true } end
	return { id = "timeline", title = L["TL_TITLE"], lines = lines, count = #events > 0 and #events or nil }
end

if ns.MemberCard then ns.MemberCard.AddSection("timeline", 8, UI.Describe) end

if ns.addon then
	ns.addon.TimelineCard = UI
	if ns.Bus then
		ns.Bus:On("TIMELINE_CHANGED", function() if ns.MemberCard then ns.MemberCard:Refresh() end end)
	end
end

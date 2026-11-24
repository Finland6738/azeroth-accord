-- TimelineCard: the "Timeline" section of the member card, for officers only (SPEC-12 §2.4, M8.2). Lua 5.1.
-- The section lists the observed roster changes of every character of the member's account in the guild (newest first, with
-- the character's name), the ten latest and "Show all", the oldest known join as "Member since", and the state of the officer
-- channel. A member never gets the section: Officer.CanSee("timeline") is false and the function returns nothing.
-- UI.Describe(entry) is a plain function (tested offline): { id, title, count, lines = { { text, muted, tip, onClick, action } } }.
-- "Show all" opens the Timeline page of the Officers tab (SPEC-12 §8, UI/Officers.lua) on this account.
local ADDON_NAME, ns = ...
ns = ns or {}
local L = ns.L
local UI = {}
ns.TimelineCard, ns.modules = UI, ns.modules or {}
ns.modules.TimelineCard = UI

local function nameOf(guid, fallback)
	local entry = ns.Roster and ns.Roster:ByGUID(guid)
	return entry and (entry.short or entry.name) or fallback
end

-- The characters whose changes the card lists: the proved characters of the account, or the character alone.
function UI.GUIDsOf(guid)
	local A = ns.Accounts
	local list = A and A:ProvedChars(guid) or { guid }
	return #list > 0 and list or { guid }
end

function UI.TipOf(ev)
	local T = ns.Timeline
	local tip = { L["TL_TIP_TITLE"], L["TL_SEEN_BY"]:format(table.concat(T.ObserverNames(ev), ", ")) }
	tip[#tip + 1] = L["TL_BETWEEN_EXACT"]:format(date("!%Y-%m-%d %H:%M", ev.a), date("!%Y-%m-%d %H:%M", ev.b))
	return tip
end

function UI.Describe(entry)
	local Officer, T = ns.Officer, ns.Timeline
	if not (Officer and T and Officer.CanSee("timeline")) then return nil end
	if type(entry) ~= "table" or type(entry.guid) ~= "string" then return nil end
	local events = T:EventsOf(UI.GUIDsOf(entry.guid))
	local lines = {}
	local since = T.OldestJoin(events)
	lines[1] = { text = since and L["TL_SINCE"]:format(date("!%Y-%m-%d", since)) or L["TL_SINCE_UNKNOWN"], muted = true }
	for i = 1, math.min(#events, T.SHOWN) do
		local ev = events[i]
		lines[#lines + 1] = { text = T.LineText(ev, nameOf(ev.g, ev.n)), tip = UI.TipOf(ev) }
	end
	if #events == 0 then lines[#lines + 1] = { text = L["TL_EMPTY"], muted = true } end
	if #events > T.SHOWN then
		lines[#lines + 1] = { text = L["TL_SHOW_ALL"]:format(#events), action = true, onClick = function()
			if ns.OfficersView then ns.OfficersView:OpenTimeline(entry.guid, nameOf(entry.guid, entry.short or entry.name or "?")) end
		end }
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

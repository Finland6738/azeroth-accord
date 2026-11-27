-- Bus: a tiny internal publish/subscribe (no dependency on the client). Lua 5.1. Modules talk to each other through
-- the Bus and their public functions only (SPEC-01 §3). A listener that raises never stops the others: the error is
-- caught with pcall and recorded for /accord debug.
-- Adapted from Azeroth Guild Finder (Core/Bus.lua), same owner, GPL-3.0 (ADR 0018).
--
-- Events (arguments in order):
--   CONFIG_LOADED()                                   Core/Config.lua; the SavedVariables are loaded and sanitized.
--   CONFIG_CHANGED(path)                              Core/Config.lua; Config:Set stored a value ("account.settings.theme"). The
--                                                     look (UI/Theme.lua) repaints from it; SETTINGS_CHANGED below is the
--                                                     one the settings page emits for an option the player changed.
--   THEME_CHANGED(themeId)                            UI/Theme.lua; the theme was applied (every themed region is repainted).
--   FEATURE_CHANGED(id, state)                        Core/Compat.lua; a module learned whether a feature capability
--                                                     works ("available", "missing", "unknown"), SPEC-01 §5.
--   ROLE_CHANGED(role, guildKey, oldRole, oldGuildKey) Core/Role.lua; role is "none"|"member"|"officer"|"gm", emitted
--                                                     only when the role or the guild key changed.
--   GUILD_CHANGED(guildKey, oldGuildKey)              Core/Role.lua; the character joined, left or changed guild (either
--                                                     key may be nil). Modules drop what they hold of the old guild.
--   SETTINGS_CHANGED(key)                             UI/SettingsModel.lua; an option ("notifyOfficer", "notifyDecision"), the "main", the
--                                                     "columns", "notify" (an output of the notices) or "clear" (guild data cleared) changed.
--   INTEGRATIONS_CHANGED()                            Data/Integrations.lua; a known raid or loot addon was detected again with
--                                                     another status, version or level (M10.2).
--   SOURCES_CHANGED()                                 Data/Integrations.lua; the officers' choice of a source per datum changed
--                                                     (locally, from an officer, or a change of guild).
--   SEASON_CHANGED()                                  Data/Season.lua; a season or a declaration changed (written here or
--                                                     received), or the source of the season roster changed (M10.3).
--   CALENDAR_CHANGED()                                Data/Calendar.lua; the guild events of the game calendar or the
--                                                     calendar's state were read again, or an event of the addon changed (M10.5).
--   EVENT_CHANGED(key)                                Data/Calendar.lua; the answers, the roles or the outcome of an answer
--                                                     of one event changed ("c<eventID>" or "f<GUID>:<n>"), M10.5.
--   AVAILABILITY_CHANGED()                            Data/Availability.lua; the guild's availability map or the own one may
--                                                     have changed, collected for a second (M10.8).
--   RALLY_CHANGED(id)                                 Data/Rallies.lua; a rally, or an answer to it, changed (nil: several)
--   FDCP_CHANGED(event)                               Data/FDCP.lua; FDCP's public API said its data changed (READY,
--                                                     SEASON_CHANGED, POOL_CHANGED, CREDITS_CHANGED, NIGHT_CHANGED or
--                                                     RULES_CHANGED), while the guild uses FDCP as a source (M11.7).
--   LOOT_CHANGED()                                    Data/Loot.lua; the loot system or addon, the census or the guild
--                                                     changed
--   HANDBOOK_CHANGED(id)                              Data/Handbook.lua; a handbook page arrived, was written or deleted
--                                                     (nil: several), M11.2.
--   HANDBOOK_CONFLICT(id)                             Data/Handbook.lua; this account's edit of a page was replaced by
--                                                     another writer's edit of the same revision, or its row was dismissed.
--   TRIALS_CHANGED(guid)                              Data/Trials.lua; a trial or a trial note arrived or was written (guid:
--                                                     the character on trial; nil: several), M12.3.
--   CHARACTER_GUILD_CHANGED(guid, from, to)           Data/Accounts.lua; the guild read for one of the account's characters
--                                                     is not the one held before (guild keys, "" = none), M12.4.
--   ONBOARDING_CHANGED()                              Data/Onboarding.lua; the welcome checklist appeared, was dismissed or
--                                                     one of its items changed, M12.4.
--   MENTORS_CHANGED()                                 Data/Mentors.lua; a mentor offer arrived, was written or taken back
--                                                     (or the guild changed), M12.5.
--   ORDERS_CHANGED(id)                                Data/Orders.lua; a craft order or the crafter's part of it arrived or was
--                                                     written, or an earlier craft request was dismissed (nil: several), M13.2.
--   REAGENTS_CHANGED(recipe)                          Data/Reagents.lua; the game gave the materials of a recipe, new or
--                                                     changed, M13.3.
--   WISHLIST_CHANGED(guid)                            Data/Wishlist.lua; a character's wishlist arrived or was written, M13.3.
--   DEMAND_CHANGED()                                  Data/Demand.lua; the material demand may have changed (1 s after what
--                                                     it is computed from), M13.3.
--   INVENTORY_CHANGED(guid)                           Data/Inventory.lua; the bags, bank or mail of a character of this
--                                                     account were read and changed, M13.4 (M17 listens too).
--   PRICES_CHANGED()                                  Data/Prices.lua; Auctionator's price database changed, M13.4.
--   SHOPPING_CHANGED()                                Data/Shopping.lua; the shopping list or what it is computed from
--                                                     changed (0.2 s after), M13.4.
--   DEMO_CHANGED(active)                              Core/Demo.lua; demo mode started (true) or ended (false), M7.4.
--   BACKUP_IMPORTED(summary)                          Data/Backup.lua; a personal backup was imported ({ chars, settings,
--                                                     records, token }), M7.5. SETTINGS_CHANGED("backup") follows.
--   TIMELINE_CHANGED()                                Data/Timeline.lua; the observed roster changes of the guild changed (an
--                                                     event was written, or a record arrived from another officer), M8.2.
--   ACTIONS_CHANGED()                                 Data/Actions.lua; the list of the Action Center changed (M9.2).
--   NOTICE_POSTED(entry)                              Data/Notify.lua; a new entry of the history of notices (M9.3).
--   NOTICES_CHANGED()                                 Data/Notify.lua; the history changed (posted, read, cleared, or
--                                                     another guild).
--   DIGEST_CHANGED()                                  Data/Digest.lua; the card of the login digest changed (new lines,
--                                                     closed, or another guild), M9.5.
--   GROUPS_CHANGED(id)                                Data/Groups.lua; a listing of the guild group finder changed (written,
--                                                     received, closed by itself or removed; nil: several), M9.6.
--   APPLICANTS_CHANGED(id)                            Data/Groups.lua; the applications of a listing changed on the
--                                                     leader's client or the candidate's, M9.6.
--   CENSUS_CHANGED()                                  Data/Census.lua; what the addon census counts changed (a record, the
--                                                     roster, the accounts, the guild), collected for a second, M9.9.
--   OFFICER_PURGED(removed)                           Data/Officer.lua; the officer data was deleted from this computer because
--                                                     no character of the account is an officer any more (SPEC-12 OFF-10).
-- Later modules add their events here.
local ADDON_NAME, ns = ...
ns = ns or {}
local Bus = {}
ns.Bus, ns.modules = Bus, ns.modules or {}
ns.modules.Bus = Bus

local pcall, type, tostring, ipairs, pairs = pcall, type, tostring, ipairs, pairs
local MAX_ERRORS = 10

local listeners = {}   -- event -> array of functions
Bus.errors = {}        -- the last MAX_ERRORS: { event = , message = }
Bus.errorCount = 0

-- Subscribes `fn` to `event`. The same function is registered once per event. Returns true when added.
function Bus:On(event, fn)
	if type(event) ~= "string" or type(fn) ~= "function" then return false end
	local list = listeners[event]
	if not list then list = {} listeners[event] = list end
	for _, f in ipairs(list) do if f == fn then return false end end
	list[#list + 1] = fn
	return true
end

-- Unsubscribes `fn` (or every listener of `event` when `fn` is nil). Returns true when something was removed.
function Bus:Off(event, fn)
	local list = listeners[event]
	if not list then return false end
	if fn == nil then listeners[event] = nil return true end
	for i, f in ipairs(list) do
		if f == fn then
			table.remove(list, i)
			if #list == 0 then listeners[event] = nil end
			return true
		end
	end
	return false
end

local function record(event, message)
	Bus.errorCount = Bus.errorCount + 1
	Bus.errors[#Bus.errors + 1] = { event = event, message = tostring(message):sub(1, 160) }
	if #Bus.errors > MAX_ERRORS then table.remove(Bus.errors, 1) end
end

-- Calls every listener of `event` in subscription order; returns the number of listeners that ran without error.
-- The list is copied first, so a listener may subscribe or unsubscribe while the event is delivered.
function Bus:Emit(event, ...)
	local list = listeners[event]
	if not list then return 0 end
	local copy, ok = {}, 0
	for i, f in ipairs(list) do copy[i] = f end
	for _, f in ipairs(copy) do
		local success, err = pcall(f, ...)
		if success then ok = ok + 1 else record(event, err) end
	end
	return ok
end

function Bus:ListenerCount(event)
	local list = listeners[event]
	return list and #list or 0
end

function Bus:DebugLines()
	local lines, events = {}, 0
	for event, list in pairs(listeners) do
		events = events + 1
		lines[#lines + 1] = ("%s: %d listener(s)"):format(event, #list)
	end
	table.sort(lines)
	table.insert(lines, 1, ("Events: %d with listeners, %d listener error(s)"):format(events, Bus.errorCount))
	for _, e in ipairs(Bus.errors) do lines[#lines + 1] = ("  error in %s: %s"):format(e.event, e.message) end
	return lines
end

if ns.addon then
	ns.addon.Bus = Bus
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Events", function() return Bus:DebugLines() end) end
end

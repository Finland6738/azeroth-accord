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
--                                                     "columns" or "clear" (guild data cleared) changed.
--   INTEGRATIONS_CHANGED()                            Data/Integrations.lua; a known raid or loot addon was detected again with
--                                                     another status, version or level (M10.2).
--   SOURCES_CHANGED()                                 Data/Integrations.lua; the officers' choice of a source per datum changed
--                                                     (locally, from an officer, or a change of guild).
--   FDCP_CHANGED(event)                               Data/FDCP.lua; FDCP's public API said its data changed (READY,
--                                                     SEASON_CHANGED, POOL_CHANGED, CREDITS_CHANGED, NIGHT_CHANGED or
--                                                     RULES_CHANGED), while the guild uses FDCP as a source (M11.7).
--   DEMO_CHANGED(active)                              Core/Demo.lua; demo mode started (true) or ended (false), M7.4.
--   BACKUP_IMPORTED(summary)                          Data/Backup.lua; a personal backup was imported ({ chars, settings,
--                                                     records, token }), M7.5. SETTINGS_CHANGED("backup") follows.
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

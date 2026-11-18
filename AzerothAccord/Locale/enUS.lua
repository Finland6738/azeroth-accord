-- English strings, the default locale (ADR 0015). Every visible string goes through L["KEY"].
-- Adapted from Azeroth Guild Finder (Locale/enUS.lua), same owner, GPL-3.0 (ADR 0018).
local ADDON_NAME = ...
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "enUS", true)
if not L then return end

L["ADDON_TITLE"] = "Azeroth Accord"
L["BINDING_TOGGLE"] = "Open or close Azeroth Accord"

-- Forever check
L["WARN_NOT_FOREVER"] = "This addon is built for WoW Forever (Interface 16001); this client was not recognised, so some features may not work."

-- Slash commands
L["HELP_HEADER"] = "Commands:"
L["HELP_TOGGLE"] = "open or close the Accord window"
L["HELP_ROSTER"] = "open the Roster view"
L["HELP_PROFESSIONS"] = "open the Professions view"
L["HELP_REPUTATION"] = "open the Reputation view"
L["HELP_BANK"] = "open the Bank view"
L["HELP_DEBUG"] = "diagnostics report to copy into a bug report"
L["HELP_HELP"] = "show this list"
L["UNKNOWN_COMMAND"] = "Unknown command '%s'."
L["COMING_SOON"] = "This part is coming soon."

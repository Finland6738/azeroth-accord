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

-- The Accord tab, the panel and the window (SPEC-04)
L["TAB_TOOLTIP"] = "Guild roster, professions, likes and bank."
L["NOT_IN_GUILD"] = "You are not in a guild."
L["EMPTY_TITLE"] = "Welcome to Azeroth Accord"
L["EMPTY_TEXT"] = "The roster, professions, reputation and bank views arrive with the next versions of the addon."
L["POP_OUT"] = "Pop out"
L["POP_OUT_TIP"] = "Open this panel in its own, larger window."
L["STATUS_PEERS"] = "%d guildmate(s) with Accord online"
L["STATUS_NEVER"] = "no data received yet"
L["STATUS_UPDATED"] = "updated %s"
L["AGO_NOW"] = "just now"
L["AGO_MINUTES"] = "%d min ago"
L["AGO_HOURS"] = "%d h ago"
L["AGO_DAYS"] = "%d d ago"
L["COMPARTMENT_HINT"] = "Click to open or close the Accord window."

-- The diagnostics box (/accord debug)
L["DIAG_TITLE"] = "Azeroth Accord diagnostics"
L["DIAG_HINT"] = "Press Ctrl+C to copy, then paste it into your bug report. It contains no player or guild names."
L["DIAG_SELECT"] = "Select all"
L["DIAG_CLOSE"] = "Close"

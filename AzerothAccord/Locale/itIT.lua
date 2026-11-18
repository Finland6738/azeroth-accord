-- Italian strings (ADR 0015). A key missing here falls back to English; tools/check_addon.py refuses a key that
-- English does not have.
local ADDON_NAME = ...
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "itIT")
if not L then return end

L["ADDON_TITLE"] = "Azeroth Accord"
L["BINDING_TOGGLE"] = "Apri o chiudi Azeroth Accord"

L["WARN_NOT_FOREVER"] = "Questo addon è fatto per WoW Forever (Interface 16001); questo client non è stato riconosciuto, quindi alcune funzioni potrebbero non andare."

L["HELP_HEADER"] = "Comandi:"
L["HELP_TOGGLE"] = "apri o chiudi la finestra di Accord"
L["HELP_ROSTER"] = "apri la vista Roster"
L["HELP_PROFESSIONS"] = "apri la vista Professioni"
L["HELP_REPUTATION"] = "apri la vista Reputazione"
L["HELP_BANK"] = "apri la vista Banca"
L["HELP_DEBUG"] = "rapporto di diagnostica da copiare in una segnalazione"
L["HELP_HELP"] = "mostra questo elenco"
L["UNKNOWN_COMMAND"] = "Comando sconosciuto '%s'."
L["COMING_SOON"] = "Questa parte arriva presto."

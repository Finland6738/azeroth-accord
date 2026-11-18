-- Mock client, part 7b: the playable classes (Accord, M2.1).
--
-- Imitates: GetNumClasses, C_CreatureInfo.GetClassInfo (className, classFile, classID). Dump: both are in api.json.
-- The ids are the ones C_Club.GetMemberInfo uses (Tests/mock/55_club.lua).
local Mock, H = ...

local CLASSES = {
	{ "Warrior", "WARRIOR" }, { "Paladin", "PALADIN" }, { "Hunter", "HUNTER" }, { "Rogue", "ROGUE" }, { "Priest", "PRIEST" },
	{ "Death Knight", "DEATHKNIGHT" }, { "Shaman", "SHAMAN" }, { "Mage", "MAGE" }, { "Warlock", "WARLOCK" }, { "Monk", "MONK" },
	{ "Druid", "DRUID" }, { "Demon Hunter", "DEMONHUNTER" }, { "Evoker", "EVOKER" },
}

function GetNumClasses() return #CLASSES end

C_CreatureInfo = C_CreatureInfo or {}
function C_CreatureInfo.GetClassInfo(id)
	local c = CLASSES[id]
	if not c then return nil end
	return { className = c[1], classFile = c[2], classID = id }
end

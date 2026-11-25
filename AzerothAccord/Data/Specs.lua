-- Specs: the classes of the base game and their three talent trees, with the roles a raider may declare for each one
-- (M10.3; SPEC-14 §4.3). Lua 5.1.
--
-- In the base game a talent tree does not decide the role, so the role is always chosen in the declaration: each tree
-- lists the roles it allows, the first one the default. A spec is stored by its key ("ARMS"); its text is the locale key
-- "SPEC_<key>" (the English tree name, translated in itIT.lua). Classes of later expansions are not here: a class the
-- table does not know can be declared only as "Not sure yet". The tree names are checked in the real client in M10.10.
local ADDON_NAME, ns = ...
ns = ns or {}
local Specs = {}
ns.Specs, ns.modules = Specs, ns.modules or {}
ns.modules.Specs = Specs

local type, ipairs = type, ipairs

Specs.ROLES = { "tank", "healer", "melee", "ranged" }

-- classFile -> { { key, roles = { first = default, ... } }, ... } in the game's tree order.
Specs.CLASSES = {
	WARRIOR = { { "ARMS", { "melee", "tank" } }, { "FURY", { "melee", "tank" } }, { "PROTECTION", { "tank", "melee" } } },
	PALADIN = { { "HOLY", { "healer" } }, { "PROTECTION", { "tank", "healer" } }, { "RETRIBUTION", { "melee", "healer" } } },
	HUNTER = { { "BEAST_MASTERY", { "ranged" } }, { "MARKSMANSHIP", { "ranged" } }, { "SURVIVAL", { "ranged", "melee" } } },
	ROGUE = { { "ASSASSINATION", { "melee" } }, { "COMBAT", { "melee" } }, { "SUBTLETY", { "melee" } } },
	PRIEST = { { "DISCIPLINE", { "healer", "ranged" } }, { "HOLY", { "healer" } }, { "SHADOW", { "ranged", "healer" } } },
	SHAMAN = { { "ELEMENTAL", { "ranged", "healer" } }, { "ENHANCEMENT", { "melee", "tank" } }, { "RESTORATION", { "healer" } } },
	MAGE = { { "ARCANE", { "ranged" } }, { "FIRE", { "ranged" } }, { "FROST", { "ranged" } } },
	WARLOCK = { { "AFFLICTION", { "ranged" } }, { "DEMONOLOGY", { "ranged" } }, { "DESTRUCTION", { "ranged" } } },
	DRUID = { { "BALANCE", { "ranged", "healer" } }, { "FERAL", { "tank", "melee" } }, { "RESTORATION", { "healer" } } },
}

local function find(classFile, spec)
	local list = type(classFile) == "string" and Specs.CLASSES[classFile]
	if not list or type(spec) ~= "string" then return nil end
	for _, row in ipairs(list) do
		if row[1] == spec then return row end
	end
	return nil
end

-- True when the table knows the class.
function Specs.Known(classFile)
	return type(classFile) == "string" and Specs.CLASSES[classFile] ~= nil
end

-- The trees of a class: { { spec = "ARMS", roles = { ... } }, ... }, or an empty list.
function Specs.Of(classFile)
	local out = {}
	for _, row in ipairs(type(classFile) == "string" and Specs.CLASSES[classFile] or {}) do
		out[#out + 1] = { spec = row[1], roles = row[2] }
	end
	return out
end

-- The roles a tree of a class allows (the first the default), or nil.
function Specs.Roles(classFile, spec)
	local row = find(classFile, spec)
	return row and row[2] or nil
end

-- True when `role` is allowed for the tree `spec` of `classFile`.
function Specs.Valid(classFile, spec, role)
	local roles = Specs.Roles(classFile, spec)
	if not roles then return false end
	for _, r in ipairs(roles) do
		if r == role then return true end
	end
	return false
end

-- The text of a tree ("Arms"), or the key itself when the locale has none.
function Specs.Name(spec)
	if type(spec) ~= "string" then return "?" end
	local text = ns.L and ns.L["SPEC_" .. spec]
	return type(text) == "string" and text or spec
end

if ns.addon then ns.addon.Specs = Specs end

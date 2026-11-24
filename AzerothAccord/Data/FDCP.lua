-- FDCP: the provider of Finland Dragon Credit Points, the guild's loot and raid addon of the same author (M10.2;
-- ADR 0022; SPEC-10 Q10). Lua 5.1.
--
-- FDCP publishes one read-only, versioned table, `FinlandDragonCreditPointsAPI` (FDCP's ADR 0009 and its wiki page
-- "API for Other Addons"). Accord reads FDCP ONLY through that table: never FDCP's SavedVariables, never its private
-- namespace, and it never writes anything of FDCP.
--
-- Levels (ADR 0022): 1 when the table is there and its API_VERSION is the one Accord knows (FDCP.API_VERSION); 0 when
-- FDCP is loaded but the table is missing or has another version (Accord only detects it and points to it); nil when
-- FDCP is not on this client. Data/Integrations.lua asks FDCP.API() for the level of the "fdcp" entry.
local ADDON_NAME, ns = ...
ns = ns or {}
local FDCP = {}
ns.FDCP, ns.modules = FDCP, ns.modules or {}
ns.modules.FDCP = FDCP

local type, pcall = type, pcall

FDCP.ID = "fdcp"
FDCP.FOLDER = "FinlandDragonCreditPoints"
FDCP.GLOBAL = "FinlandDragonCreditPointsAPI"
FDCP.API_VERSION = 1        -- the only version this Accord reads; any other one falls back to level 0

local function lookup(t, k) return t[k] end

-- The value of a field of the table, read protected (the table may have an __index that raises).
local function field(t, k)
	local ok, v = pcall(lookup, t, k)
	if ok then return v end
	return nil
end

-- The API table when Accord may read it, else nil plus the reason: "absent" (no table) or "version" (another version;
-- the version seen, when it is a number or a short text, as the third result).
function FDCP.API()
	local api = field(_G, FDCP.GLOBAL)
	if type(api) ~= "table" then return nil, "absent" end
	local v = field(api, "API_VERSION")
	if v ~= FDCP.API_VERSION then
		if type(v) ~= "number" and not (type(v) == "string" and #v <= 16) then v = nil end
		return nil, "version", v
	end
	return api
end

if ns.addon then ns.addon.FDCP = FDCP end

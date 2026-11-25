-- GroupActivities: the dungeons and raids a listing of the guild group finder can name (SPEC-13 §6.4, M9.6). Lua 5.1.
--
-- One row per instance: { mapID, kind = "dungeon" | "raid", size, min, max, name } (`name` in English, a fallback only:
-- the name shown is the client's own, GetRealZoneText(mapID)). The rows are the dungeons and raids of the base game
-- (levels 1-60). At the first use, when the client has C_LFGList.GetAvailableCategories, GetAvailableActivities and
-- GetActivityInfoTable (they are in the Forever dump), every activity of the dungeon and raid categories adds or corrects
-- the row of its mapID [verify on Forever which instances exist]. Only the mapID travels: a client with another table
-- still accepts a listing (Data/Groups.lua checks a mapID by its range, not by this table).
local ADDON_NAME, ns = ...
ns = ns or {}
local Activities = {}
ns.GroupActivities, ns.modules = Activities, ns.modules or {}
ns.modules.GroupActivities = Activities

local type, pairs, ipairs, floor = type, pairs, ipairs, math.floor

-- mapID, kind, size, min, max, name
Activities.BASE = {
	{ 389, "dungeon", 5, 13, 18, "Ragefire Chasm" },
	{ 43, "dungeon", 5, 15, 25, "Wailing Caverns" },
	{ 36, "dungeon", 5, 15, 23, "The Deadmines" },
	{ 33, "dungeon", 5, 18, 25, "Shadowfang Keep" },
	{ 48, "dungeon", 5, 20, 30, "Blackfathom Deeps" },
	{ 34, "dungeon", 5, 22, 30, "The Stockade" },
	{ 90, "dungeon", 5, 24, 34, "Gnomeregan" },
	{ 47, "dungeon", 5, 24, 34, "Razorfen Kraul" },
	{ 189, "dungeon", 5, 26, 45, "Scarlet Monastery" },
	{ 129, "dungeon", 5, 33, 41, "Razorfen Downs" },
	{ 70, "dungeon", 5, 35, 45, "Uldaman" },
	{ 209, "dungeon", 5, 42, 50, "Zul'Farrak" },
	{ 349, "dungeon", 5, 40, 52, "Maraudon" },
	{ 109, "dungeon", 5, 45, 55, "Sunken Temple" },
	{ 230, "dungeon", 5, 48, 60, "Blackrock Depths" },
	{ 229, "dungeon", 10, 55, 60, "Blackrock Spire" },   -- the lower spire is a party of 5, the upper one of 10
	{ 429, "dungeon", 5, 55, 60, "Dire Maul" },
	{ 289, "dungeon", 5, 58, 60, "Scholomance" },
	{ 329, "dungeon", 5, 58, 60, "Stratholme" },
	{ 409, "raid", 40, 60, 60, "Molten Core" },
	{ 249, "raid", 40, 60, 60, "Onyxia's Lair" },
	{ 469, "raid", 40, 60, 60, "Blackwing Lair" },
	{ 309, "raid", 20, 58, 60, "Zul'Gurub" },
	{ 509, "raid", 20, 60, 60, "Ruins of Ahn'Qiraj" },
	{ 531, "raid", 40, 60, 60, "Temple of Ahn'Qiraj" },
	{ 533, "raid", 40, 60, 60, "Naxxramas" },
}

Activities.MAX_MAP = 1000000   -- a mapID on the wire is an integer 1..MAX_MAP

local rows          -- mapID -> row, built at the first use
local stats = { base = 0, fromClient = 0 }
Activities.stats = stats

local function compat() return ns.Compat end

local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end

local function call(path, ...)
	local C = compat()
	if not (C and C.Call) then return nil end
	local results = { pcall(C.Call, path, ...) }
	if not results[1] or results[2] ~= "available" then return nil end
	return results[3]
end

-- Reads the client's own dungeon and raid activities (C_LFGList) into the table. Returns the number of rows added or
-- corrected. Nothing happens when the client lacks one of the three calls.
function Activities:FromClient()
	local categories = call("C_LFGList.GetAvailableCategories")
	if type(categories) ~= "table" then return 0 end
	local n = 0
	for _, category in ipairs(categories) do
		local info = call("C_LFGList.GetLfgCategoryInfo", category)
		local name = type(info) == "table" and type(info.name) == "string" and info.name:lower() or ""
		local kind = (info and info.isRaid == true or name:find("raid", 1, true)) and "raid"
			or (name:find("dungeon", 1, true) and "dungeon") or nil
		local activities = kind and call("C_LFGList.GetAvailableActivities", category)
		for _, activityID in ipairs(type(activities) == "table" and activities or {}) do
			local a = call("C_LFGList.GetActivityInfoTable", activityID)
			local mapID = type(a) == "table" and (a.mapID or a.instanceMapID) or nil
			if int(mapID, 1, Activities.MAX_MAP) then
				local row = rows[mapID] or { mapID = mapID, kind = kind, name = type(a.fullName) == "string" and a.fullName or nil }
				if int(a.maxNumPlayers, 2, 40) then row.size = a.maxNumPlayers end
				if int(a.minLevel, 1, 1000) and a.minLevel > 0 then row.min = a.minLevel end
				if int(a.maxLevelSuggestion, 1, 1000) and a.maxLevelSuggestion > 0 then row.max = a.maxLevelSuggestion end
				row.size = row.size or (kind == "raid" and 40 or 5)
				row.min = row.min or 1
				row.max = math.max(row.max or row.min, row.min)
				rows[mapID] = row
				n = n + 1
			end
		end
	end
	stats.fromClient = n
	return n
end

local function build()
	rows = {}
	for _, r in ipairs(Activities.BASE) do
		rows[r[1]] = { mapID = r[1], kind = r[2], size = r[3], min = r[4], max = r[5], name = r[6] }
	end
	stats.base = #Activities.BASE
	Activities:FromClient()
end

-- The row of a mapID, or nil when the table does not know it.
function Activities:Get(mapID)
	if not rows then build() end
	return rows[mapID]
end

-- Every row of a kind ("dungeon" or "raid"), sorted by level then name.
function Activities:List(kind)
	if not rows then build() end
	local out = {}
	for _, row in pairs(rows) do
		if kind == nil or row.kind == kind then out[#out + 1] = row end
	end
	table.sort(out, function(a, b)
		if a.min ~= b.min then return a.min < b.min end
		return tostring(a.name) < tostring(b.name)
	end)
	return out
end

-- The name to show: the client's own (GetRealZoneText), else the table's, else "Instance <mapID>".
function Activities:Name(mapID)
	local name = call("GetRealZoneText", mapID)
	if type(name) == "string" and name ~= "" then return name end
	local row = self:Get(mapID)
	return row and row.name or ("Instance " .. tostring(mapID))
end

-- Forget the table (tests): the next use builds it again.
function Activities:Reset() rows = nil end

if ns.addon then ns.addon.GroupActivities = Activities end

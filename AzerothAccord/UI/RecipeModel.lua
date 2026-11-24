-- RecipeModel: what the recipe list of a member's profession shows, without any frame (SPEC-06 PRO-01..PRO-03). Lua 5.1.
-- One instance holds the member and profession being looked at, the search text and the category filter; the frames of
-- UI/Professions.lua only draw what it returns.
--
--   local m = Model.new()
--   m:SetTarget(guid, skillLine)        asks every source that can give the list (Recipes:Ensure)
--   m:Describe()   -> { guid, skillLine, title, profession, rank, maxRank, status = "list"|"none", source, sourceText,
--                       message (when there is no list), total, shown }
--   m:SetSearch("potion"); m:SetCategory("unknown")
--   m:Rows()       -> { { id, name, icon, category, difficulty, known }, ... } sorted by name
--   m:Categories() -> { { key, label }, ... } what the filter menu offers
--
-- Recipes are spell ids: names and icons come from the client (Recipes.SpellData) and may arrive late (the row shows
-- "Recipe <id>" until then and the model is invalidated when the name loads). The filter offers "recipes I know" and
-- "recipes I do not know" (compared with the player's own list of the same profession) and, when the client tells it
-- about a recipe (RecipeMeta, [verify S4]), its category.
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.RecipeModel, ns.modules = Model, ns.modules or {}
ns.modules.RecipeModel = Model
Model.__index = Model

local L = ns.L
local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber

local function lower(s) return type(s) == "string" and s:lower() or "" end
local function compat() return ns.Compat end
local function now() return compat() and compat().ServerTime() or time() end

function Model.new()
	return setmetatable({ search = "", category = nil, guid = nil, skillLine = nil, rows = nil, version = 0, meta = {}, asked = nil }, Model)
end

function Model:Invalidate()
	self.rows = nil
	self.version = self.version + 1
end

function Model:SetSearch(text)
	text = lower(type(text) == "string" and text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == self.search then return false end
	self.search = text
	self:Invalidate()
	return true
end

-- key: nil (all), "known", "unknown" or "cat:<name>".
function Model:SetCategory(key)
	if key == self.category then return false end
	self.category = key
	self:Invalidate()
	return true
end

-- Looks at a member's profession (a skill line, or nil when the game did not say which profession it is) and asks the
-- sources for the list. Returns what Recipes:Ensure returned.
function Model:SetTarget(guid, skillLine)
	self.guid, self.skillLine = guid, type(skillLine) == "number" and skillLine or nil
	self.search, self.category, self.meta = "", nil, {}
	self:Invalidate()
	self.asked = nil
	if self.guid and self.skillLine and ns.Recipes then self.asked = ns.Recipes:Ensure(self.guid, self.skillLine) end
	return self.asked
end

---------------------------------------------------------------------------------------------------------------------
-- The data behind the list
---------------------------------------------------------------------------------------------------------------------
function Model:Entry()
	local guid = self.guid
	if not guid then return nil end
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	if e then return e end
	local g = ns.Accounts and ns.Accounts:GroupOf(guid)
	local m = g and g.byGUID and g.byGUID[guid]
	if m and ns.RosterModel then return ns.RosterModel.PseudoEntry(m) end
	return nil
end

function Model:Lookup()
	if not (self.guid and self.skillLine and ns.Recipes) then return nil end
	return ns.Recipes:Lookup(self.guid, self.skillLine)
end

-- The roster's own profession of this member with this skill line (the game's rank), or nil.
local function professionOf(entry, skillLine)
	for _, p in ipairs(entry and entry.professions or {}) do
		if p.id == skillLine then return p end
	end
	return nil
end

-- The set of spell ids the player knows in this profession, or nil when it is not known (or it is the player's own list).
function Model:OwnSet()
	local R, C = ns.Recipes, compat()
	local me = C and C.Player.GUID()
	if not (R and me and self.guid and self.guid ~= me and self.skillLine) then return nil end
	local mine = R:Shared(me, self.skillLine)
	if not mine then return nil end
	local set = {}
	for _, id in ipairs(mine.ids) do set[id] = true end
	return set
end

-- "from the game, 2 min ago" / "shared by the member's addon, 3 d ago" / "your own list, ..." (PRO-01).
function Model.SourceText(e)
	if type(e) ~= "table" then return "" end
	local age = e.time and ns.Shell and ns.Shell.Ago(now() - e.time) or nil
	local text
	if e.source == "native" then
		text = age and L["RV_SRC_NATIVE_AGE"]:format(age) or L["RV_SRC_NATIVE"]
		if e.sharedTime and ns.Shell then text = text .. "; " .. L["RV_SRC_ALSO_SHARED"]:format(ns.Shell.Ago(now() - e.sharedTime)) end
	elseif e.source == "own" then
		text = age and L["RV_SRC_OWN_AGE"]:format(age) or L["RV_SRC_OWN"]
	else
		text = age and L["RV_SRC_SHARED_AGE"]:format(age) or L["RV_SRC_SHARED"]
	end
	return text
end

local function messageFor(self, entry)
	local name = entry and (entry.short or entry.name) or "?"
	local profession = self.professionName or L["PROF_UNKNOWN"]:format(self.skillLine or 0)
	if not self.skillLine then return L["RV_NO_LINE"]:format(name) end
	local asked = self.asked or {}
	if asked.native == "queued" or asked.native == "pending" or asked.shared == "sent" then return L["RV_WAITING"]:format(name) end
	if entry and entry.hasAddon == false and asked.native == "unavailable" then return L["RV_NO_ADDON"]:format(name) end
	if asked.shared == "nobody" or asked.shared == "recent" or asked.shared == "blocked" then
		return L["RV_NOBODY"]:format(name, profession)
	end
	return L["RV_UNKNOWN"]:format(name, profession)
end

-- A description of what to show above the list (PRO-01, PRO-03).
function Model:Describe()
	local entry = self:Entry()
	local lookup = self:Lookup()
	local p = entry and professionOf(entry, self.skillLine)
	local name = (lookup and lookup.name) or (p and p.name)
	self.professionName = name
	local d = {
		guid = self.guid, skillLine = self.skillLine, title = entry and (entry.short or entry.name) or "?", classFile = entry and entry.classFile,
		profession = name or (self.skillLine and L["PROF_UNKNOWN"]:format(self.skillLine)) or "?",
		rank = (p and p.rank) or (lookup and lookup.rank), maxRank = (p and p.maxRank) or (lookup and lookup.maxRank),
		online = entry and entry.online == true, status = lookup and "list" or "none",
	}
	if lookup then
		d.source, d.sourceText, d.time = lookup.source, Model.SourceText(lookup), lookup.time
		d.provenance = { source = lookup.source, observedAt = lookup.time, author = lookup.author, set = "recipes" }
		d.total = #lookup.ids
		d.shown = #self:Rows()
		if d.total == 0 then d.message = L["RV_EMPTY_LIST"] end
	else
		d.message = messageFor(self, entry)
		d.total, d.shown = 0, 0
	end
	return d
end

---------------------------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------------------------
local function metaOf(self, id)
	local m = self.meta[id]
	if m == nil then
		local C = compat()
		m = C and C.TradeSkill.RecipeMeta(id) or false
		self.meta[id] = m
	end
	return m or nil
end

local function matchesCategory(self, row)
	local key = self.category
	if key == nil then return true end
	if key == "known" then return row.known == true end
	if key == "unknown" then return row.known == false end
	return key == "cat:" .. (row.category or "")
end

-- The rows for the current member, profession, search and category: every recipe of the list, filtered, by name.
function Model:Rows()
	if self.rows then return self.rows end
	local list = {}
	local lookup = self:Lookup()
	local ownSet = lookup and self:OwnSet() or nil
	local R = ns.Recipes
	local search = self.search
	self.pending = 0
	if lookup then
		for _, id in ipairs(lookup.ids) do
			local data = R.SpellData(id)
			local name = data and data.name or nil
			if not name then self.pending = self.pending + 1 end
			local meta = metaOf(self, id)
			local row = { id = id, name = name or L["RV_RECIPE_ID"]:format(id), resolved = name ~= nil, icon = data and data.icon or nil,
				category = meta and meta.category or nil, difficulty = meta and meta.difficulty or nil }
			if ownSet then row.known = ownSet[id] == true end
			row.key = lower(row.name)
			if matchesCategory(self, row) and (search == "" or row.key:find(search, 1, true) or tostring(id) == search) then
				list[#list + 1] = row
			end
		end
	end
	table.sort(list, function(a, b)
		if a.resolved ~= b.resolved then return a.resolved end
		if a.key ~= b.key then return a.key < b.key end
		return a.id < b.id
	end)
	self.rows = list
	return list
end

-- The entries of the category menu: "All", the player's comparison when it is known, and the categories the client
-- told about.
function Model:Categories()
	local out = { { key = nil, label = L["RV_CAT_ALL"] } }
	local lookup = self:Lookup()
	if not lookup then return out end
	if self:OwnSet() then
		out[#out + 1] = { key = "known", label = L["RV_CAT_KNOWN"] }
		out[#out + 1] = { key = "unknown", label = L["RV_CAT_UNKNOWN"] }
	end
	local seen, cats = {}, {}
	for _, id in ipairs(lookup.ids) do
		local meta = metaOf(self, id)
		if meta and meta.category and not seen[meta.category] then
			seen[meta.category] = true
			cats[#cats + 1] = meta.category
		end
	end
	table.sort(cats, function(a, b) return lower(a) < lower(b) end)
	for _, c in ipairs(cats) do out[#out + 1] = { key = "cat:" .. c, label = c } end
	return out
end

if ns.addon then ns.addon.RecipeModel = Model end

-- RecipeModel: what the recipe list of a member's profession shows, without any frame (SPEC-06 PRO-01..PRO-03). Lua 5.1.
-- One instance holds the member and profession being looked at, the search text and the category filter; the frames of
-- UI/Professions.lua only draw what it returns.
--
--   local m = Model.new()
--   m:SetTarget(guid, skillLine)        asks every source that can give the list (Recipes:Ensure)
--   m:Describe()   -> { guid, skillLine, title, profession, rank, maxRank, status = "list"|"none", source, sourceText,
--                       message (when there is no list), total, shown }
--   m:SetSearch("potion"); m:SetCategory("unknown")
--   m:Rows()       -> { { id, name, icon, category, difficulty, known, learned, level }, ... } sorted by name
--   m:Categories() -> { { key, label }, ... } what the filter menu offers
--
-- When the guild has the profession's catalogue (Data/RecipeCatalogue.lua) the member's list shows EVERY recipe of the
-- profession: the ones the member learned (`learned` = true) and the missing ones (false), with the required skill level
-- when the catalogue has it; the filter adds "learned" and "missing". Without a catalogue only the member's list shows.
--
-- Model.Catalogue is the guild's recipe catalogue of one profession (SPEC-06 §2.4): every recipe, its required level and how
-- many guild characters can craft it; a recipe that is opened lists them under it (Data/Crafters.lua):
--
--   local c = Model.Catalogue.new()
--   Model.Professions()  -> { { skillLine, name, recipes (in the catalogue, or nil), lists (characters with a list) } }
--   c:SetProfession(171); c:SetSearch("potion"); c:SetFilter("nobody"); c:Toggle(recipeId)
--   c:Describe()         -> { skillLine, profession, status = "catalogue" | "lists" | "none" | "pick", total, shown, crafted,
--                             sourceText, provenance, message }
--   c:Rows()             -> { { kind = "cat", id, name, icon, level, count, known, expanded }, { kind = "member", ... } }
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

-- key: nil (all), "known", "unknown", "learned", "missing" or "cat:<name>".
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
		local ids, _, cat = Model.IdsOf(self, lookup)
		d.total, d.learned, d.catalogue = #ids, #lookup.ids, cat ~= nil
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
	if key == "learned" then return row.learned ~= false end
	if key == "missing" then return row.learned == false end
	return key == "cat:" .. (row.category or "")
end

-- The profession's catalogue, when the guild has one.
function Model:FullList()
	return self.skillLine and ns.RecipeCatalogue and ns.RecipeCatalogue:Get(self.skillLine) or nil
end

-- Sorts recipe rows: by required level when the catalogue has levels, then the loaded names first, by name, by id.
local function sortRows(list, byLevel)
	table.sort(list, function(a, b)
		if byLevel and a.level ~= b.level then
			if a.level == nil or b.level == nil then return b.level == nil end
			return a.level < b.level
		end
		if a.resolved ~= b.resolved then return a.resolved end
		if a.key ~= b.key then return a.key < b.key end
		return a.id < b.id
	end)
end
Model.SortRows = sortRows

-- The ids of the rows: the member's list and, with a catalogue, every other recipe of the profession too. Returns the ids,
-- the set of the member's ones (nil without a catalogue) and the catalogue.
local function idsOf(self, lookup)
	local cat = self:FullList()
	if not cat then return lookup.ids, nil, nil end
	local mine, ids, seen = {}, {}, {}
	for _, id in ipairs(lookup.ids) do mine[id] = true seen[id] = true ids[#ids + 1] = id end
	for _, id in ipairs(cat.ids) do
		if not seen[id] then seen[id] = true ids[#ids + 1] = id end
	end
	return ids, mine, cat
end
Model.IdsOf = idsOf

-- The rows for the current member, profession, search and category: every recipe of the list (and of the catalogue),
-- filtered, by name (by required level when the catalogue has levels).
function Model:Rows()
	if self.rows then return self.rows end
	local list = {}
	local lookup = self:Lookup()
	local ownSet = lookup and self:OwnSet() or nil
	local R = ns.Recipes
	local search = self.search
	local cat
	self.pending = 0
	if lookup then
		local ids, mine
		ids, mine, cat = idsOf(self, lookup)
		for _, id in ipairs(ids) do
			local data = R.SpellData(id)
			local name = data and data.name or nil
			if not name then self.pending = self.pending + 1 end
			local meta = metaOf(self, id)
			local row = { id = id, name = name or L["RV_RECIPE_ID"]:format(id), resolved = name ~= nil, icon = data and data.icon or nil,
				category = meta and meta.category or nil, difficulty = meta and meta.difficulty or nil,
				level = cat and cat.levels[id] or nil }
			if mine then row.learned = mine[id] == true end
			if ownSet then row.known = ownSet[id] == true end
			row.key = lower(row.name)
			if matchesCategory(self, row) and (search == "" or row.key:find(search, 1, true) or tostring(id) == search) then
				list[#list + 1] = row
			end
		end
	end
	sortRows(list, cat ~= nil and cat.hasLevels)
	self.rows = list
	return list
end

-- The entries of the category menu: "All", the player's comparison when it is known, and the categories the client
-- told about.
function Model:Categories()
	local out = { { key = nil, label = L["RV_CAT_ALL"] } }
	local lookup = self:Lookup()
	if not lookup then return out end
	if self:FullList() then
		local entry = self:Entry()
		local name = entry and (entry.short or entry.name) or "?"
		out[#out + 1] = { key = "learned", label = L["RV_CAT_LEARNED"]:format(name) }
		out[#out + 1] = { key = "missing", label = L["RV_CAT_MISSING"]:format(name) }
	end
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

---------------------------------------------------------------------------------------------------------------------
-- The guild's recipe catalogue of one profession (SPEC-06 §2.4)
---------------------------------------------------------------------------------------------------------------------
local function isLine(v) return type(v) == "number" and v > 0 end

-- The name of a profession in the player's language: the client's own name for the skill line, the player's own
-- profession, a roster entry's, a shared record's; "Skill <id>" when nobody says.
local function professionName(line, fallback)
	local C = compat()
	local name = C and C.TradeSkill.ProfessionName and C.TradeSkill.ProfessionName(line)
	if name then return name end
	for _, p in ipairs(C and C.TradeSkill.OwnProfessions() or {}) do
		if p.skillLine == line and type(p.name) == "string" then return p.name end
	end
	return fallback or L["PROF_UNKNOWN"]:format(line)
end
Model.ProfessionName = professionName

-- Every profession the guild has something of: a catalogue, a member's list, or the roster's professions. Sorted by name.
function Model.Professions()
	local by, order = {}, {}
	local function add(line, name)
		if not isLine(line) then return nil end
		local p = by[line]
		if not p then
			p = { skillLine = line, lists = 0 }
			by[line] = p
			order[#order + 1] = p
		end
		if not p.fallback and type(name) == "string" and name ~= "" then p.fallback = name end
		return p
	end
	local C = compat()
	for _, p in ipairs(C and C.TradeSkill.OwnProfessions() or {}) do add(p.skillLine, p.name) end
	local RC = ns.RecipeCatalogue
	for _, line in ipairs(RC and RC:Lines() or {}) do
		local cat = RC:Get(line)
		local p = add(line, cat and cat.name)
		if p and cat then p.recipes = cat.n end
	end
	for _, list in ipairs(ns.Recipes and ns.Recipes:AllLists() or {}) do
		local p = add(list.skillLine, list.name)
		if p then p.lists = p.lists + 1 end
	end
	for _, e in ipairs(ns.Roster and ns.Roster:Members() or {}) do
		for _, q in ipairs(e.professions or {}) do add(q.id, q.name) end
	end
	for _, p in ipairs(order) do p.name = professionName(p.skillLine, p.fallback) end
	table.sort(order, function(a, b)
		if lower(a.name) ~= lower(b.name) then return lower(a.name) < lower(b.name) end
		return a.skillLine < b.skillLine
	end)
	return order
end

local Cat = {}
Cat.__index = Cat
Model.Catalogue = Cat

-- The filter starts on "crafted": by default only the recipes somebody in the guild can craft (owner, 2026-11-27).
Cat.DEFAULT_FILTER = "crafted"

function Cat.new()
	return setmetatable({ skillLine = nil, search = "", filter = Cat.DEFAULT_FILTER, expanded = {}, rows = nil, version = 0 }, Cat)
end

function Cat:Invalidate()
	self.rows = nil
	self.version = self.version + 1
end

function Cat:SetSearch(text)
	text = lower(type(text) == "string" and text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == self.search then return false end
	self.search = text
	self:Invalidate()
	return true
end

-- key: nil (all), "crafted" (somebody can), "nobody", "known" / "unknown" (the player's own list).
function Cat:SetFilter(key)
	if key == self.filter then return false end
	self.filter = key
	self:Invalidate()
	return true
end

-- Shows another profession: its recipes start closed; the filter the player chose stays.
function Cat:SetProfession(skillLine)
	skillLine = isLine(skillLine) and skillLine or nil
	if skillLine == self.skillLine then return false end
	self.skillLine, self.expanded = skillLine, {}
	self:Invalidate()
	return true
end

-- Opens or closes the crafters under a recipe. Returns true when it is open now.
function Cat:Toggle(id)
	if type(id) ~= "number" then return false end
	self.expanded[id] = not self.expanded[id] or nil
	self:Invalidate()
	return self.expanded[id] == true
end

function Cat:Get()
	return self.skillLine and ns.RecipeCatalogue and ns.RecipeCatalogue:Get(self.skillLine) or nil
end

-- The set of the player's own recipes in this profession, or nil.
function Cat:OwnSet()
	local R, C = ns.Recipes, compat()
	local me = C and C.Player.GUID()
	local mine = R and me and self.skillLine and R:Shared(me, self.skillLine)
	if not mine then return nil end
	local set = {}
	for _, id in ipairs(mine.ids) do set[id] = true end
	return set
end

-- The profession picked when none is: the player's own first, else the first that has a catalogue, else the first listed.
function Cat:DefaultProfession()
	local list = Model.Professions()
	local C = compat()
	for _, p in ipairs(C and C.TradeSkill.OwnProfessions() or {}) do
		for _, q in ipairs(list) do if q.skillLine == p.skillLine and (q.recipes or q.lists > 0) then return q.skillLine end end
	end
	for _, q in ipairs(list) do if q.recipes then return q.skillLine end end
	for _, q in ipairs(list) do if q.lists > 0 then return q.skillLine end end
	return list[1] and list[1].skillLine or nil
end

-- "Full list shared by Bob, 3 d ago" for a catalogue.
local function catalogueSource(cat)
	local e = ns.Roster and ns.Roster:ByGUID(cat.author)
	local who = e and (e.short or e.name) or "?"
	local age = cat.time and ns.Shell and ns.Shell.Ago(now() - cat.time) or nil
	return age and L["CAT_SRC_AGE"]:format(who, age) or L["CAT_SRC"]:format(who)
end

function Cat:Describe()
	local d = { skillLine = self.skillLine }
	if not self.skillLine then
		d.status, d.profession, d.total, d.shown = "pick", "", 0, 0
		d.message = L["CAT_PICK"]
		return d
	end
	d.profession = professionName(self.skillLine)
	for _, p in ipairs(Model.Professions()) do
		if p.skillLine == self.skillLine then d.profession = p.name end
	end
	local cat = self:Get()
	local known = ns.Crafters and ns.Crafters:KnownIn(self.skillLine) or {}
	local any = next(known) ~= nil
	if cat then
		d.status, d.sourceText = "catalogue", catalogueSource(cat)
		d.provenance = { source = "shared", observedAt = cat.time, author = cat.author, set = "recipecat" }
	elseif any then
		d.status, d.sourceText = "lists", L["CAT_SRC_LISTS"]
	else
		d.status, d.message, d.total, d.shown = "none", L["CAT_EMPTY"]:format(d.profession), 0, 0
		return d
	end
	local rows = self:Rows()
	d.total, d.crafted, d.shown = self.total, self.crafted, self.shownRecipes
	if #rows == 0 then
		d.message = (self.filter == "crafted" and self.crafted == 0 and self.search == "") and L["CAT_NONE_CRAFTED"]:format(d.profession)
			or L["RV_NO_MATCH"]
	end
	return d
end

local function matchesFilter(self, row)
	local key = self.filter
	if key == nil then return true end
	if key == "crafted" then return row.count > 0 end
	if key == "nobody" then return row.count == 0 end
	if key == "known" then return row.known == true end
	if key == "unknown" then return row.known == false end
	return true
end

-- The rows: every recipe of the catalogue and of the members' lists of this profession, filtered and searched; under an
-- opened recipe the characters who can craft it (online first, the alts of an account together).
function Cat:Rows()
	if self.rows then return self.rows end
	local list, out = {}, {}
	self.total, self.crafted, self.shownRecipes, self.pending = 0, 0, 0, 0
	if not self.skillLine then self.rows = out return out end
	local cat = self:Get()
	local known = ns.Crafters and ns.Crafters:KnownIn(self.skillLine) or {}
	local ids, seen = {}, {}
	for _, id in ipairs(cat and cat.ids or {}) do seen[id] = true ids[#ids + 1] = id end
	for id in pairs(known) do if not seen[id] then seen[id] = true ids[#ids + 1] = id end end
	local own = self:OwnSet()
	local R, search = ns.Recipes, self.search
	for _, id in ipairs(ids) do
		local data = R.SpellData(id)
		local name = data and data.name or nil
		if not name then self.pending = self.pending + 1 end
		local row = { kind = "cat", id = id, name = name or L["RV_RECIPE_ID"]:format(id), resolved = name ~= nil,
			icon = data and data.icon or nil, level = cat and cat.levels[id] or nil, count = known[id] or 0,
			expanded = self.expanded[id] == true, key = nil }
		if own then row.known = own[id] == true end
		row.key = lower(row.name)
		self.total = self.total + 1
		if row.count > 0 then self.crafted = self.crafted + 1 end
		if matchesFilter(self, row) and (search == "" or row.key:find(search, 1, true) or tostring(id) == search) then
			list[#list + 1] = row
		end
	end
	sortRows(list, cat ~= nil and cat.hasLevels)
	self.shownRecipes = #list
	for _, row in ipairs(list) do
		out[#out + 1] = row
		if row.expanded and row.count > 0 and ns.Crafters then
			for _, account in ipairs((ns.Crafters:Who(row.id))) do
				for i, m in ipairs(account.members) do
					out[#out + 1] = { kind = "member", depth = i == 1 and 0 or 1, recipeId = row.id, recipeName = row.name, member = m,
						key = "m:" .. row.id .. ":" .. m.guid }
				end
			end
		end
	end
	self.rows = out
	return out
end

-- The entries of the filter menu.
function Cat:Filters()
	local out = { { key = nil, label = L["RV_CAT_ALL"] }, { key = "crafted", label = L["CAT_F_CRAFTED"] },
		{ key = "nobody", label = L["CAT_F_NOBODY"] } }
	if self:OwnSet() then
		out[#out + 1] = { key = "known", label = L["RV_CAT_KNOWN"] }
		out[#out + 1] = { key = "unknown", label = L["RV_CAT_UNKNOWN"] }
	end
	return out
end

if ns.addon then ns.addon.RecipeModel = Model end

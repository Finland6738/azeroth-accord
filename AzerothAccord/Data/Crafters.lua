-- Crafters: "who can craft ..." (SPEC-06 PRO-04). Lua 5.1.
-- A reverse index from a recipe to the guild members who know it, built from every list the client has (Recipes:AllLists:
-- the native answers and the shared records, ADR 0010) and rebuilt lazily after a change. A search takes the name of a
-- recipe or of the item it makes (an item or spell link pasted into the box counts as its name), finds the recipes whose
-- name contains it (exact names first, then names that begin with it, then the rest) and lists for each one the members
-- who can craft it: online first, the characters of one account together (ACC-02).
--
--   local result = Crafters:Search("healing potion", { onlineOnly = false })
--   result = { status = "ok" | "short" | "none", query, recipes = { { id, name, icon, count, accounts = { { id, name, online,
--              members = { { guid, name, classFile, level, online, source, time, rank, maxRank, profession, skillLine,
--              isSelf }, ... } }, ... } }, ... }, total (recipes that match), more (not shown), pending (names not loaded yet) }
--   local rows = Crafters.Rows(result)   a flat list for a virtual table: { kind = "recipe", ... } and { kind = "member",
--              depth = 0|1, ... } rows
--
-- Only members of the guild are listed (a record of somebody who left is ignored), and the player's own character is
-- listed with its own scan. The recipe name is the name of the spell: it is the name of the item for most crafts.
local ADDON_NAME, ns = ...
ns = ns or {}
local Crafters = {}
ns.Crafters, ns.modules = Crafters, ns.modules or {}
ns.modules.Crafters = Crafters

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local sort = table.sort

Crafters.MIN_QUERY = 2          -- characters
Crafters.MAX_RECIPES = 40       -- recipes shown for one query
Crafters.MAX_MEMBERS = 120      -- members listed under one recipe

local state = { dirty = true, lists = {}, index = {}, lower = {}, builds = 0, searches = 0 }
Crafters.state = state

local function lower(s) return type(s) == "string" and s:lower() or "" end

-- The text to look for: the [name] of a pasted link, else the text; trimmed and lower-case.
function Crafters.Normalize(text)
	if type(text) ~= "string" then return "" end
	local linked = text:match("|h%[(.-)%]|h")
	if linked then text = linked end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return text:lower()
end

function Crafters:MarkDirty() state.dirty = true end

-- Rebuilds the index when a list changed: id -> { positions in state.lists }.
local function build()
	local lists, index = {}, {}
	local R, Ro = ns.Recipes, ns.Roster
	local me = ns.Compat and ns.Compat.Player.GUID()
	if R then
		for _, list in ipairs(R:AllLists()) do
			if list.guid == me or (Ro and Ro:ByGUID(list.guid)) then
				lists[#lists + 1] = list
				local pos = #lists
				for _, id in ipairs(list.ids) do
					local at = index[id]
					if not at then at = {} index[id] = at end
					at[#at + 1] = pos
				end
			end
		end
	end
	state.lists, state.index, state.dirty = lists, index, false
	state.builds = state.builds + 1
end

local function nameLower(id)
	local n = state.lower[id]
	if n then return n end
	local name = ns.Recipes and ns.Recipes.NameOf(id)
	if not name then return nil end
	n = name:lower()
	state.lower[id] = n
	return n
end

-- The members who can craft recipe `id`, grouped by account (online accounts first).
local function crafters(id, opts)
	local Ro, A = ns.Roster, ns.Accounts
	local groups, order = {}, {}
	local me = ns.Compat and ns.Compat.Player.GUID()
	local count = 0
	for _, pos in ipairs(state.index[id] or {}) do
		local list = state.lists[pos]
		local e = Ro and Ro:ByGUID(list.guid)
		local online = list.guid == me or (e and e.online == true) or false
		if not (opts and opts.onlineOnly) or online then
			local g = A and A:GroupOf(list.guid)
			local gid = g and g.id or ("c:" .. list.guid)
			local group = groups[gid]
			if not group then
				group = { id = gid, members = {}, online = false }
				groups[gid] = group
				order[#order + 1] = group
			end
			if online then group.online = true end
			group.members[#group.members + 1] = {
				guid = list.guid, name = e and (e.short or e.name) or "?", classFile = e and e.classFile, level = e and e.level,
				online = online, source = list.source, time = list.time, rank = list.rank, maxRank = list.maxRank,
				profession = list.name, skillLine = list.skillLine, isSelf = list.guid == me, rankName = e and e.rankName,
			}
			count = count + 1
		end
	end
	for _, group in ipairs(order) do
		sort(group.members, function(a, b)
			if a.online ~= b.online then return a.online end
			if lower(a.name) ~= lower(b.name) then return lower(a.name) < lower(b.name) end
			return a.guid < b.guid
		end)
		group.name = group.members[1].name
	end
	sort(order, function(a, b)
		if a.online ~= b.online then return a.online end
		if lower(a.name) ~= lower(b.name) then return lower(a.name) < lower(b.name) end
		return a.id < b.id
	end)
	-- never more than MAX_MEMBERS characters under one recipe
	local left = Crafters.MAX_MEMBERS
	for _, group in ipairs(order) do
		while #group.members > left do group.members[#group.members] = nil end
		left = left - #group.members
	end
	while #order > 0 and #order[#order].members == 0 do order[#order] = nil end
	return order, count
end

-- The guild characters who know recipe `id` (the catalogue view, SPEC-06 §2.4): accounts as in a search result, and the
-- number of characters. opts.onlineOnly keeps the online ones.
function Crafters:Who(id, opts)
	if state.dirty then build() end
	if type(id) ~= "number" or not state.index[id] then return {}, 0 end
	return crafters(id, opts)
end

-- How many guild characters know recipe `id` (cheap: no grouping).
function Crafters:CountOf(id)
	if state.dirty then build() end
	local at = state.index[id]
	return at and #at or 0
end

-- The ids of every recipe some guild character knows in `skillLine`: { [id] = count }.
function Crafters:KnownIn(skillLine)
	if state.dirty then build() end
	local out = {}
	for _, list in ipairs(state.lists) do
		if list.skillLine == skillLine then
			for _, id in ipairs(list.ids) do out[id] = (out[id] or 0) + 1 end
		end
	end
	return out
end

-- Searches. opts.onlineOnly keeps only crafters who are online now.
function Crafters:Search(query, opts)
	state.searches = state.searches + 1
	local text = Crafters.Normalize(query)
	local result = { query = text, recipes = {}, total = 0, more = 0, pending = 0, status = "ok" }
	if #text < Crafters.MIN_QUERY then result.status = "short" return result end
	if state.dirty then build() end
	local found = {}
	for id in pairs(state.index) do
		local name = nameLower(id)
		if not name then
			result.pending = result.pending + 1
		else
			local at = name:find(text, 1, true)
			if at then found[#found + 1] = { id = id, name = name, rank = (name == text) and 1 or (at == 1 and 2 or 3) } end
		end
	end
	sort(found, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	local R = ns.Recipes
	for _, f in ipairs(found) do
		local accounts, count = crafters(f.id, opts)
		if count > 0 then
			result.total = result.total + 1
			if #result.recipes < Crafters.MAX_RECIPES then
				local data = R and R.SpellData(f.id)
				result.recipes[#result.recipes + 1] = { id = f.id, name = data and data.name or f.name, icon = data and data.icon, count = count,
					accounts = accounts }
			end
		end
	end
	result.more = result.total - #result.recipes
	if result.total == 0 then result.status = "none" end
	return result
end

-- The flat rows of a result for a table: a recipe row, then its members, the alts of an account indented under the first.
function Crafters.Rows(result)
	local rows = {}
	for _, r in ipairs(result and result.recipes or {}) do
		rows[#rows + 1] = { kind = "recipe", id = r.id, name = r.name, icon = r.icon, count = r.count, key = "r:" .. r.id }
		for _, account in ipairs(r.accounts) do
			for i, m in ipairs(account.members) do
				rows[#rows + 1] = { kind = "member", depth = i == 1 and 0 or 1, recipeId = r.id, recipeName = r.name, member = m,
					key = "m:" .. r.id .. ":" .. m.guid }
			end
		end
	end
	return rows
end

-- How many recipes and how many lists the index covers, for the diagnostics.
function Crafters:DebugLines()
	local recipes = 0
	for _ in pairs(state.index) do recipes = recipes + 1 end
	return { ("Crafters: %d list(s), %d distinct recipe(s) indexed, %d build(s), %d search(es)%s"):format(#state.lists, recipes,
		state.builds, state.searches, state.dirty and "; index out of date" or "") }
end

if ns.addon then
	ns.addon.Crafters = Crafters
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Crafters", function() return Crafters:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("RECIPES_UPDATED", function() Crafters:MarkDirty() end)
		ns.Bus:On("ROSTER_UPDATED", function() Crafters:MarkDirty() end)
		ns.Bus:On("GUILD_CHANGED", function() state.lower = {} Crafters:MarkDirty() end)
	end
end

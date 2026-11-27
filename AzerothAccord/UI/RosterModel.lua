-- RosterModel: what the Roster table shows, without any frame (SPEC-05 §1, SPEC-04 §2). Lua 5.1.
-- Columns, search, filters, sorting, the grouped-by-account view and the text of each cell are plain functions of the
-- roster (Data/Roster.lua) and the account groups (Data/Accounts.lua), so every rule is covered by offline tests; the
-- frames of UI/Roster.lua only draw the rows this model returns.
--
--   local m = Model.new()                  the data comes from ns.Roster and ns.Accounts (tests may pass their own)
--   m:SetSearch("bob"); m:SetFilter("online", true); m:SetSort("level", true); m:SetGrouped(true)
--   m:Rows()  -> { { kind = "member"|"group"|"alt", entry, group, depth, expanded, count, id }, ... }
--
-- ROS-01: sort by every column, search by name (and profession), filters online / class / rank / profession / mains only.
-- ROS-02: grouped by account: one row per account (its main) with the alts under it, expandable.
-- The choices of the player (columns, sort, grouped) are saved per character in char.ui (SPEC-04 §2).
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.RosterModel, ns.modules = Model, ns.modules or {}
ns.modules.RosterModel = Model
Model.__index = Model

local L = ns.L
local type, pairs, ipairs, tostring, floor, next, unpack = type, pairs, ipairs, tostring, math.floor, next, unpack
local HUGE = math.huge

local function lower(s) return type(s) == "string" and s:lower() or "" end

---------------------------------------------------------------------------------------------------------------------
-- Columns (SPEC-05 §1). `available` is false until the module that fills the column exists: contacts come with M2.5,
-- likes and the social index with M4.
---------------------------------------------------------------------------------------------------------------------
Model.COLUMNS = {
	{ id = "name", label = "COL_NAME", width = 170, always = true },
	{ id = "level", label = "COL_LEVEL", width = 40 },
	-- widths tuned on the owner's screenshot (2026-11-27): rank and zone were cut, class and likes had room to spare
	{ id = "class", label = "COL_CLASS", width = 80 },
	{ id = "rank", label = "COL_RANK", width = 115 },
	{ id = "zone", label = "COL_ZONE", width = 175 },
	{ id = "lastOnline", label = "COL_LAST_ONLINE", width = 95 },
	{ id = "prof1", label = "COL_PROF1", width = 165 },
	{ id = "prof2", label = "COL_PROF2", width = 165 },
	{ id = "likes", label = "COL_LIKES", width = 45, available = function() return ns.Likes ~= nil end },
	-- the BattleTag of the member's account, as its own client shares it (owner, 2026-11-27: it replaces the Contacts and
	-- Social columns; the social index stays on the Reputation view and the member card)
	{ id = "battleTag", label = "COL_BATTLETAG", width = 140, available = function() return ns.Contacts ~= nil end },
	{ id = "addon", label = "COL_ADDON", width = 70 },
}
Model.DEFAULT_COLUMNS = { "name", "level", "class", "rank", "zone", "lastOnline", "prof1", "prof2", "likes", "battleTag", "addon" }

local byId = {}
for _, c in ipairs(Model.COLUMNS) do byId[c.id] = c end
Model.COLUMN = byId

Model.enabled = nil   -- tests: { [id] = true } makes a column available without its module

function Model.ColumnAvailable(id)
	local c = byId[id]
	if not c then return false end
	if Model.enabled and Model.enabled[id] then return true end
	return c.available == nil or c.available() == true
end

-- The ids of the columns that exist now, in table order.
function Model.AvailableColumns()
	local out = {}
	for _, c in ipairs(Model.COLUMNS) do if Model.ColumnAvailable(c.id) then out[#out + 1] = c end end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Cell values
---------------------------------------------------------------------------------------------------------------------
-- "3 h ago" for a number of hours since the member was last online.
function Model.LastOnlineText(hours)
	if type(hours) ~= "number" then return L["LAST_UNKNOWN"] end
	if hours < 1 then return L["LAST_LT_HOUR"] end
	if hours < 24 then return L["AGO_HOURS"]:format(floor(hours)) end
	local days = floor(hours / 24)
	if days < 60 then return L["AGO_DAYS"]:format(days) end
	if days < 730 then return L["AGO_MONTHS"]:format(floor(days / 30)) end
	return L["AGO_YEARS"]:format(floor(days / 365))
end

function Model.ProfessionText(p)
	if type(p) ~= "table" then return "" end
	local name = p.name or (p.id and L["PROF_UNKNOWN"]:format(p.id)) or "?"
	if p.rank then return name .. " " .. p.rank .. (p.maxRank and ("/" .. p.maxRank) or "") end
	return name
end

-- The profession in slot `i` (1 or 2) of an entry. Professions come sorted as the source gave them.
local function professionOf(entry, i)
	return entry.professions and entry.professions[i] or nil
end

-- The text of a cell and a colour hint ("class", "muted", "green", "red" or nil).
function Model.Cell(id, e)
	if id == "name" then
		return e.short or e.name or "?", e.notInGuild and "muted" or "class"
	elseif id == "level" then
		return e.level and tostring(e.level) or ""
	elseif id == "class" then
		return ns.Roster.ClassName(e.classFile) or "", "class"
	elseif id == "rank" then
		return e.rankName or ""
	elseif id == "zone" then
		return e.zone or ""
	elseif id == "lastOnline" then
		if e.notInGuild then return ns.Provenance.AltGuildText(e.altGuild), "muted" end
		if e.online then return L["ONLINE"], "green" end
		return Model.LastOnlineText(e.lastOnlineHours), "muted"
	elseif id == "prof1" or id == "prof2" then
		local p = professionOf(e, id == "prof1" and 1 or 2)
		if not p then return "", "muted" end
		return Model.ProfessionText(p), p.source == "shared" and "muted" or nil
	elseif id == "addon" then
		-- a development build says "@project-version@": "yes" then, like a member whose version is not known
		if e.hasAddon then
			local v = e.addonVersion
			return (type(v) == "string" and v ~= "" and v:sub(1, 1) ~= "@") and v or L["YES"], "green"
		end
		return "", "muted"
	elseif id == "battleTag" then
		return Model.BattleTagOf(e) or "", nil
	elseif id == "likes" then
		-- the total of the account; green when this player liked it, grey while the like waits for an officer
		local x = ns.Likes
		if not (x and x.Total and e.guid) or e.notInGuild then return "" end
		local state = x:StateOf(e.guid)
		return tostring(x:Total(e.guid)), state == "given" and "green" or (state == "pending" and "grey" or nil)
	elseif id == "social" then
		-- the index; a dash when the member has group play but under 5 hours (SOC-04)
		local x = ns.Social
		if not (x and x.CanSee and e.guid and x:CanSee(e.guid)) then return "" end
		local s = x:ForGUID(e.guid)
		if not s then return "", "muted" end
		if not s.index then return "-", "muted" end
		return tostring(s.index)
	end
	return ""
end

-- The BattleTag of a member's account: the player's own from the game, another's from the contacts its client shares.
function Model.BattleTagOf(e)
	local C = ns.Contacts
	if not (C and e and e.guid) then return nil end
	if e.isSelf and C.OwnBattleTag then return C:OwnBattleTag() end
	local c = C.Of and C:Of(e.guid)
	return c and c.battleTag or nil
end

-- Sort values: a number or a lower-case string, nil when the member has nothing for this column (nil sorts last).
local function sortValue(id, e)
	if id == "name" then return lower(e.short or e.name)
	elseif id == "level" then return e.level
	elseif id == "class" then return lower(ns.Roster.ClassName(e.classFile))
	elseif id == "rank" then return e.rankIndex
	elseif id == "zone" then return e.zone and lower(e.zone) or nil
	elseif id == "lastOnline" then
		if e.notInGuild then return nil end
		if e.online then return -1 end
		return e.lastOnlineHours
	elseif id == "prof1" or id == "prof2" then
		local p = professionOf(e, id == "prof1" and 1 or 2)
		return p and lower(p.name or "") or nil
	elseif id == "addon" then
		return e.hasAddon and 0 or 1
	elseif id == "battleTag" then
		return lower(Model.BattleTagOf(e))
	elseif id == "likes" then
		local x = ns.Likes
		return x and x.Total and x:Total(e.guid) or nil
	elseif id == "social" then
		local x = ns.Social
		return x and x.Index and x:Index(e.guid) or nil
	end
	return nil
end
Model.SortValue = sortValue

---------------------------------------------------------------------------------------------------------------------
-- Instance
---------------------------------------------------------------------------------------------------------------------
function Model.new(opts)
	opts = opts or {}
	local m = setmetatable({
		search = "", filters = {}, sort = { key = "name", desc = false }, grouped = false, expanded = {},
		columns = nil, rows = nil, members = opts.members, groupOf = opts.groupOf, version = 0,
	}, Model)
	m.columns = m:DefaultColumns()
	return m
end

function Model:DefaultColumns()
	local out = {}
	for _, id in ipairs(Model.DEFAULT_COLUMNS) do out[#out + 1] = id end
	return out
end

-- The data sources: ns.Roster / ns.Accounts unless the test gave its own.
function Model:Members()
	if self.members then return self.members() end
	return ns.Roster and ns.Roster:Members() or {}
end

function Model:GroupOf(guid)
	if self.groupOf then return self.groupOf(guid) end
	return ns.Accounts and ns.Accounts:GroupOf(guid) or nil
end

function Model:Invalidate()
	self.rows = nil
	self.version = self.version + 1
end

function Model:SetSearch(text)
	text = lower(type(text) == "string" and text or "")
	if text == self.search then return false end
	self.search = text
	self:Invalidate()
	return true
end

-- key: "online" (boolean), "class" (class file), "rank" (rank index), "profession" (id or lower-case name),
-- "mains" (boolean). nil or false clears it.
function Model:SetFilter(key, value)
	if value == false then value = nil end
	if self.filters[key] == value then return false end
	self.filters[key] = value
	self:Invalidate()
	return true
end

function Model:ClearFilters()
	self.filters = {}
	self.search = ""
	self:Invalidate()
end

function Model:HasFilters()
	return next(self.filters) ~= nil or self.search ~= ""
end

-- Sorts by `key`; the same key again flips the direction unless `desc` is given.
function Model:SetSort(key, desc)
	if not byId[key] then return false end
	if desc == nil then
		desc = (self.sort.key == key) and not self.sort.desc or false
	end
	self.sort = { key = key, desc = desc and true or false }
	self:Invalidate()
	return true
end

function Model:SetGrouped(on)
	on = on and true or false
	if self.grouped == on then return false end
	self.grouped = on
	self:Invalidate()
	return true
end

function Model:ToggleExpand(groupId)
	self.expanded[groupId] = not self.expanded[groupId] or nil
	self:Invalidate()
	return self.expanded[groupId] == true
end

function Model:ExpandAll(on)
	self.expanded = {}
	if on then
		for _, g in ipairs(ns.Accounts and ns.Accounts:Groups() or {}) do self.expanded[g.id] = true end
	end
	self:Invalidate()
end

-- Shown columns: ids in table order. The name column is always there; unknown and unavailable ids are dropped.
function Model:SetColumns(ids)
	local want = {}
	for _, id in ipairs(ids or {}) do want[id] = true end
	want.name = true
	local out = {}
	for _, c in ipairs(Model.COLUMNS) do
		if want[c.id] and Model.ColumnAvailable(c.id) then out[#out + 1] = c.id end
	end
	self.columns = out
	self:Invalidate()
end

function Model:ToggleColumn(id)
	if not byId[id] or byId[id].always then return false end
	local want = {}
	local has = false
	for _, c in ipairs(self.columns) do
		if c == id then has = true else want[#want + 1] = c end
	end
	if not has then want[#want + 1] = id end
	self:SetColumns(want)
	return not has
end

function Model:HasColumn(id)
	for _, c in ipairs(self.columns) do if c == id then return true end end
	return false
end

-- The visible columns as definitions, in order (columns whose module is not there yet never appear).
function Model:VisibleColumns()
	local out = {}
	for _, id in ipairs(self.columns) do
		if Model.ColumnAvailable(id) then out[#out + 1] = byId[id] end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------------------------
local function matchesSearch(self, e)
	local s = self.search
	if s == "" then return true end
	if lower(e.name):find(s, 1, true) then return true end
	for _, p in ipairs(e.professions or {}) do
		if p.name and lower(p.name):find(s, 1, true) then return true end
	end
	return false
end

local function hasProfession(e, key)
	for _, p in ipairs(e.professions or {}) do
		if p.id == key or (p.name and lower(p.name) == key) then return true end
	end
	return false
end

-- `isMain`: the member is the main of its group, or has no group.
local function matches(self, e, isMain)
	local f = self.filters
	if f.online and not e.online then return false end
	if f.class and e.classFile ~= f.class then return false end
	if f.rank ~= nil and e.rankIndex ~= f.rank then return false end
	if f.profession ~= nil and not hasProfession(e, f.profession) then return false end
	if f.mains and not isMain then return false end
	return matchesSearch(self, e)
end

local function compare(self, a, b, valueOf)
	local va, vb = valueOf(a), valueOf(b)
	local desc = self.sort.desc
	if va == nil or vb == nil then
		if va == nil and vb == nil then return nil end
		return vb == nil   -- a missing value sorts last whatever the direction
	end
	if va == vb then return nil end
	if desc then return va > vb end
	return va < vb
end

local function nameOf(e) return lower(e.short or e.name) end

local function sortEntries(self, list, valueOf)
	table.sort(list, function(a, b)
		local r = compare(self, a, b, valueOf)
		if r ~= nil then return r end
		local na, nb = nameOf(a), nameOf(b)
		if na ~= nb then return na < nb end
		return tostring(a.guid) < tostring(b.guid)
	end)
end

-- The member entry of a group member that is not in the roster (claimed by the account, ACC-03).
local function pseudoEntry(m)
	local R = ns.Roster
	local classFile = m.classFile or (m.classID and R and R.ClassFile(m.classID)) or nil
	return { name = m.name or "?", short = m.name, guid = m.guid, level = m.level, classID = m.classID, classFile = classFile,
		online = false, professions = {}, notInGuild = true, claimed = true, altGuild = m.altGuild }
end

Model.PseudoEntry = pseudoEntry

local function flatRows(self, members)
	local list = {}
	for _, e in ipairs(members) do
		local g = e.guid and self:GroupOf(e.guid) or nil
		local isMain = g == nil or g.main == e.guid
		if matches(self, e, isMain) then list[#list + 1] = e end
	end
	local col = self.sort.key
	sortEntries(self, list, function(e) return sortValue(col, e) end)
	local rows = {}
	for i, e in ipairs(list) do rows[i] = { kind = "member", entry = e, depth = 0, id = e.guid or e.name } end
	return rows
end

local function groupedRows(self, members)
	local byGUID = {}
	for _, e in ipairs(members) do if e.guid then byGUID[e.guid] = e end end
	local units, seen = {}, {}
	for _, e in ipairs(members) do
		local g = e.guid and self:GroupOf(e.guid) or nil
		if g and #g.members > 1 then
			if not seen[g.id] then
				seen[g.id] = true
				local entries = {}
				for _, gm in ipairs(g.members) do
					local re = byGUID[gm.guid]
					entries[#entries + 1] = { entry = re or pseudoEntry(gm), isMain = gm.guid == g.main }
				end
				units[#units + 1] = { group = g, entries = entries }
			end
		else
			units[#units + 1] = { entries = { { entry = e, isMain = true } } }
		end
	end

	local col = self.sort.key
	local shown = {}
	for _, u in ipairs(units) do
		local head
		for _, x in ipairs(u.entries) do if x.isMain then head = x.entry end end
		head = head or u.entries[1].entry
		-- an account is listed when any of its members matches (the "mains only" filter shapes the rows, below)
		local mainsOnly = self.filters.mains
		self.filters.mains = nil
		local alts, any = {}, false
		for _, x in ipairs(u.entries) do
			if matches(self, x.entry, x.isMain) then
				any = true
				if x.entry ~= head then alts[#alts + 1] = x.entry end
			end
		end
		self.filters.mains = mainsOnly
		if any then
			if mainsOnly or not u.group then alts = {} end
			shown[#shown + 1] = { head = head, alts = alts, group = u.group }
		end
	end
	-- order the accounts by their main's value (the most recent last-online of the account for that column)
	local function valueOf(u)
		if col == "lastOnline" then
			local best
			for _, x in ipairs(u.group and u.group.members or {}) do
				local e = byGUID[x.guid]
				local v = e and sortValue("lastOnline", e)
				if v ~= nil and (best == nil or v < best) then best = v end
			end
			if best ~= nil then return best end
		end
		return sortValue(col, u.head)
	end
	table.sort(shown, function(a, b)
		local r = compare(self, a, b, valueOf)
		if r ~= nil then return r end
		local na, nb = nameOf(a.head), nameOf(b.head)
		if na ~= nb then return na < nb end
		return tostring(a.head.guid) < tostring(b.head.guid)
	end)

	local rows = {}
	for _, u in ipairs(shown) do
		if u.group then
			local open = self.expanded[u.group.id] == true
			rows[#rows + 1] = { kind = "group", entry = u.head, group = u.group, depth = 0, expanded = open, count = #u.alts,
				id = "g:" .. u.group.id }
			if open then
				sortEntries(self, u.alts, function(e) return sortValue(col, e) end)
				for _, e in ipairs(u.alts) do
					rows[#rows + 1] = { kind = "alt", entry = e, group = u.group, depth = 1, id = e.guid or e.name }
				end
			end
		else
			rows[#rows + 1] = { kind = "member", entry = u.head, depth = 0, id = u.head.guid or u.head.name }
		end
	end
	return rows
end

-- The rows to draw, rebuilt only after a change of search, filters, sort, grouping or data (Invalidate).
function Model:Rows()
	if self.rows then return self.rows end
	local members = self:Members()
	self.rows = self.grouped and groupedRows(self, members) or flatRows(self, members)
	return self.rows
end

function Model:Count()
	return #self:Rows()
end

-- The characters in the guild that the table shows, in its order: in the grouped view every account is taken as open, so
-- the alts a closed row hides are there too. For the export (SPEC-12 §6).
function Model:Entries()
	local rows = self:Rows()
	if self.grouped then
		local open = self.expanded
		local all = {}
		for _, row in ipairs(rows) do if row.group then all[row.group.id] = true end end
		self.expanded = all
		rows = groupedRows(self, self:Members())
		self.expanded = open
	end
	local out = {}
	for _, row in ipairs(rows) do
		if not row.entry.notInGuild then out[#out + 1] = row.entry end
	end
	return out
end

-- What the filter menus offer, from the members the roster has now: { { key, label }, ... } sorted by label.
function Model:Choices(kind)
	local seen, out = {}, {}
	for _, e in ipairs(self:Members()) do
		if kind == "class" and e.classFile and not seen[e.classFile] then
			seen[e.classFile] = true
			out[#out + 1] = { key = e.classFile, label = ns.Roster.ClassName(e.classFile) }
		elseif kind == "rank" and e.rankIndex ~= nil and not seen[e.rankIndex] then
			seen[e.rankIndex] = true
			out[#out + 1] = { key = e.rankIndex, label = e.rankName or tostring(e.rankIndex), order = e.rankIndex }
		elseif kind == "profession" then
			for _, p in ipairs(e.professions or {}) do
				local key = p.id or (p.name and lower(p.name))
				if key ~= nil and not seen[key] then
					seen[key] = true
					out[#out + 1] = { key = key, label = Model.ProfessionText({ name = p.name, id = p.id }) }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.order and b.order then return a.order < b.order end
		return lower(a.label) < lower(b.label)
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Saved choices (char.ui)
---------------------------------------------------------------------------------------------------------------------
function Model:Save()
	local C = ns.Config
	if not C then return end
	C:Set("char.ui.columns", { unpack(self.columns) })
	C:Set("char.ui.sort", { key = self.sort.key, desc = self.sort.desc })
	C:Set("char.ui.grouped", self.grouped)
end

function Model:Load()
	local C = ns.Config
	if not C then return end
	local cols = C:Get("char.ui.columns")
	if type(cols) == "table" and #cols > 0 then
		-- a choice saved before the BattleTag column (2026-11-27) still names Contacts or Social, which it replaced
		local had, old = false, false
		for _, id in ipairs(cols) do
			if id == "battleTag" then had = true elseif id == "contacts" or id == "social" then old = true end
		end
		if old and not had then
			local copy = { unpack(cols) }
			copy[#copy + 1] = "battleTag"
			cols = copy
		end
		self:SetColumns(cols)
	end
	local sort = C:Get("char.ui.sort")
	if type(sort) == "table" and byId[sort.key] then self.sort = { key = sort.key, desc = sort.desc == true } end
	self.grouped = C:Get("char.ui.grouped") == true
	self:Invalidate()
end

if ns.addon then ns.addon.RosterModel = Model end

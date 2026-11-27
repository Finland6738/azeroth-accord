-- Professions view (SPEC-06 PRO-02..PRO-04, §2.4). Lua 5.1.
-- Three modes in one view:
--   catalogue the guild's recipes of one profession (the default, SPEC-06 §2.4): a Select picks the profession; the rows are
--             EVERY recipe of it (Data/RecipeCatalogue.lua, plus whatever a member's list has), with the required skill
--             level and how many guild characters can craft it (UI/RecipeModel.lua, Model.Catalogue). A click on a recipe
--             opens the characters who can craft it under it (with Request craft, PRO-05); a click on a character opens
--             that character's recipes. A filter keeps the recipes somebody can craft, nobody can, or the player knows.
--   craft     "who can craft ..." (PRO-04): the search box of the panel takes the name of an item or a recipe; the rows are
--             the recipes that match (Data/Crafters.lua), each followed by the members who know it, online first, the
--             characters of one account together; a click on a member opens that member's recipe list. "Online only"
--             keeps the crafters who are online now.
--   recipes   the recipe list of one member's profession (PRO-02, PRO-03): opened by a click on a profession cell of the
--             Roster table, on a profession line of the member card, or on a member in the craft list or the catalogue.
--             Rows come from UI/RecipeModel.lua: an icon, the name, a note when the player knows it too; with the
--             profession's catalogue also the recipes the member has NOT learned ("not learned", dimmed); the game's own
--             recipe tooltip; the search box filters by name; the Category menu; the message when there is no list.
-- With the switch "econ" (M13.2, SPEC-17 §3.5) Request craft opens the New order window (UI/Orders.lua), for members
-- offline too, and a recipe of the catalogue says how many open orders ask for it.
-- The header has a Back button (to the roster, the catalogue or the craft list, where the list was opened from), and in the
-- recipe list and the catalogue a "Who can craft" button, in the craft list a "Guild recipes" button; the source and the
-- age of the list are always in the header.
-- Drawn with the widget kit (M6.13): ghost / secondary Widgets.Buttons, a Widgets.Select for the category, a Widgets.Chip for "online
-- only" and one Widgets.DataTable (a pool of rows refilled while the list scrolls) for both lists.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.RecipeView, ns.modules = View, ns.modules or {}
ns.modules.RecipeView = View

local L, Widgets, Theme, Model = ns.L, ns.Widgets, ns.Theme, ns.RecipeModel
local type, ipairs, max = type, ipairs, math.max

View.ROW_HEIGHT = 36
View.HEADER_HEIGHT = 72
View.TOOLBAR_HEIGHT = 40
View.POOL = 24
View.ICON = 20
View.ALL = "all"                 -- the id of "All recipes" in the category select
View.REFRESH_DELAY = 0.4       -- lists, names and the roster change in bursts; a redraw waits for the burst to end

View.mode = "catalogue"        -- "catalogue", "craft" or "recipes"
View.cameFrom = "roster"       -- where Back goes from the recipe list: "roster", "catalogue" or "craft"
View.model = Model.new()       -- the recipe list being looked at
View.cat = Model.Catalogue.new()   -- the guild's recipes of one profession
View.craft = { query = "", onlineOnly = false, result = nil, rows = nil, dirty = true }

local function classColor(classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

-- The colour of a recipe name by difficulty (orange, yellow, green, grey: the game's own order), white when unknown.
local DIFFICULTY = { [0] = { 1, 0.5, 0.25 }, [1] = { 1, 1, 0 }, [2] = { 0.25, 0.75, 0.25 }, [3] = { 0.6, 0.6, 0.6 } }

local function searchBox()
	local c = ns.Shell and ns.Shell.content
	return c and c.bar and c.bar.search or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Modes and opening
---------------------------------------------------------------------------------------------------------------------
-- The skill line of a profession of a roster entry: its own id when the game gives one, else the id of the member's
-- shared list with the same name.
function View.SkillLineOf(entry, p)
	if type(p) ~= "table" then return nil end
	if type(p.id) == "number" then return p.id end
	local R = ns.Recipes
	if R and entry and entry.guid and type(p.name) == "string" then
		for _, q in ipairs(R:ProfessionsOf(entry.guid)) do
			if type(q.name) == "string" and q.name:lower() == p.name:lower() then return q.skillLine end
		end
	end
	return nil
end

-- The panel's search box holds the text of the mode that is showing.
local function syncSearchBox(self)
	local box = searchBox()
	if not box then return end
	local text = self.mode == "craft" and self.craft.query or (self.mode == "catalogue" and self.cat.search) or self.model.search
	if (box:GetText() or "") ~= text then box:SetText(text) end
end

-- The next draw starts at the top of the list.
function View:ResetScroll()
	if self.frame and self.frame.table then self.frame.table.offset = 0 end
end

function View:SetMode(mode)
	if mode ~= "craft" and mode ~= "recipes" and mode ~= "catalogue" then return false end
	self.mode = mode
	self:ResetScroll()
	syncSearchBox(self)
	if mode == "craft" then self.craft.dirty = true end
	if self.frame then self:Redraw() end
	return true
end

-- true while a member's own recipe list can be opened. The owner switched it off for now (2026-11-27): every way in (a
-- profession cell of the roster, the member card, a crafter, the Action Center) shows the guild's recipes of that
-- profession instead. The switch `memberRecipes` (Core/Features.lua) brings it back; the code stays, tested.
function View.MemberListOn()
	return ns.Features ~= nil and ns.Features.On("memberRecipes")
end

-- Opens the list of `guid` for `skillLine` (nil: the game did not say which profession it is) and shows the view. `from`
-- says where Back goes: "roster" (the default), "catalogue" or "craft". With the member list switched off it shows the
-- guild's recipes of that profession.
function View:Open(guid, skillLine, from)
	if type(guid) ~= "string" then return false end
	if not View.MemberListOn() then return self:OpenCatalogue(type(skillLine) == "number" and skillLine or nil) end
	self.cameFrom = (from == "craft" or from == "catalogue") and from or "roster"
	self.model:SetTarget(guid, skillLine)
	self.mode = "recipes"
	self:ResetScroll()
	local shown = true
	if ns.Shell then shown = ns.Shell:OpenView("professions") end
	syncSearchBox(self)
	if self.frame then self:Redraw() end
	return shown ~= false
end

-- From a roster entry and the slot (1 or 2) of its profession cell.
function View:OpenFor(entry, slot)
	local p = entry and entry.professions and entry.professions[slot]
	if not p then return false end
	return self:Open(entry.guid, View.SkillLineOf(entry, p))
end

-- Shows the "who can craft" search, with `text` in it when given.
function View:OpenCraft(text)
	if text ~= nil then self.craft.query = type(text) == "string" and text or "" end
	local shown = true
	if ns.Shell then shown = ns.Shell:OpenView("professions") end
	self:SetMode("craft")
	return shown ~= false
end

-- Shows the guild's recipes of a profession (the player's own first when `skillLine` is nil and none was picked), on
-- the default filter: what the guild can craft.
function View:OpenCatalogue(skillLine)
	if type(skillLine) == "number" then self.cat:SetProfession(skillLine) end
	self.cat:SetFilter(Model.Catalogue.DEFAULT_FILTER)
	self:ResetScroll()
	local shown = true
	if ns.Shell then shown = ns.Shell:OpenView("professions") end
	self:SetMode("catalogue")
	return shown ~= false
end

-- The click on the Professions tab: back to the guild's recipes of the profession picked last, on the default filter.
function View:ToCatalogue()
	self.cat:SetFilter(Model.Catalogue.DEFAULT_FILTER)
	self.mode = "catalogue"
	self:ResetScroll()
	syncSearchBox(self)
	if self.frame then self:Redraw() end
end

-- Picks the profession of the catalogue.
function View:SetProfession(skillLine)
	if self.cat:SetProfession(skillLine) then
		self:ResetScroll()
		self:Redraw()
	end
end

-- The text of the panel's search box changed.
function View:SetSearch(text)
	text = type(text) == "string" and text or ""
	if self.mode == "catalogue" then
		if self.cat:SetSearch(text) then
			self:ResetScroll()
			self:Redraw()
		end
	elseif self.mode == "craft" then
		if text == self.craft.query then return end
		self.craft.query = text
		self.craft.dirty = true
		self:ResetScroll()
		self:Redraw()
	elseif self.model:SetSearch(text) then
		self:ResetScroll()
		self:Redraw()
	end
end

function View:SetOnlineOnly(on)
	on = on and true or false
	if self.craft.onlineOnly == on then return end
	self.craft.onlineOnly = on
	self.craft.dirty = true
	self:ResetScroll()
	self:Redraw()
end

function View:Back()
	if self.cameFrom == "craft" or self.cameFrom == "catalogue" then
		self:SetMode(self.cameFrom)
	elseif ns.Shell then
		ns.Shell:Select("roster")
	end
end

-- The craft search, done again when the query, the filter or the data changed.
local function research(self)
	local c = self.craft
	if not c.dirty and c.result then return end
	c.result = ns.Crafters and ns.Crafters:Search(c.query, { onlineOnly = c.onlineOnly }) or { status = "none", recipes = {}, total = 0, more = 0, pending = 0 }
	c.rows = ns.Crafters and ns.Crafters.Rows(c.result) or {}
	c.dirty = false
end

---------------------------------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------------------------------
local function categoryChoices(self)
	local out = {}
	local list = self.mode == "catalogue" and self.cat:Filters() or self.model:Categories()
	for _, c in ipairs(list) do out[#out + 1] = { id = c.key or View.ALL, text = c.label } end
	return out
end

-- The professions of the Select: "<name> (<n> recipes)" when the catalogue is known.
local function professionChoices()
	local out = {}
	for _, p in ipairs(Model.Professions()) do
		out[#out + 1] = { id = p.skillLine, text = p.recipes and L["CAT_PROF_N"]:format(p.name, p.recipes) or p.name }
	end
	return out
end

local function build(self, f)
	local head = CreateFrame("Frame", nil, f)
	head:SetHeight(View.HEADER_HEIGHT)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	head.back = Widgets.Button(head, { text = L["RV_BACK"], style = "text", dense = true, onClick = function() View:Back() end })
	head.back:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
	head.craft = Widgets.Button(head, { text = L["CR_BUTTON"], style = "tonal", dense = true, onClick = function() View:SetMode("craft") end })
	head.craft:SetPoint("LEFT", head.back, "RIGHT", 8, 0)
	-- "Guild recipes" in the craft search; "All members" in a member's list: the guild's recipes of that profession
	head.cat = Widgets.Button(head, { text = L["CAT_BUTTON"], style = "tonal", dense = true, onClick = function()
		if View.mode == "recipes" and View.model.skillLine then View:OpenCatalogue(View.model.skillLine) else View:SetMode("catalogue") end
	end })
	head.cat:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
	head.cat:Hide()
	Widgets.Tooltip.Attach(head.cat, function()
		if View.mode == "recipes" then return { L["RV_ALL_MEMBERS"], L["RV_ALL_MEMBERS_TIP"] } end
		return nil
	end, "BOTTOM")
	head.title = Theme.NewText(head, "H1", "text-1")
	head.title:SetJustifyH("LEFT")
	head.title:SetPoint("LEFT", head.craft, "RIGHT", 16, 0)
	head.title:SetPoint("RIGHT", head, "RIGHT", 0, 0)
	head.source = Theme.NewText(head, "Small", "text-3")
	head.source:SetJustifyH("LEFT")
	head.source:SetPoint("TOPLEFT", head.back, "BOTTOMLEFT", 2, -8)
	head.prov = Widgets.Provenance(head)   -- the label of the list's source, at the right of the source line (M7.2)
	head.prov:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, -48)
	head.source:SetPoint("RIGHT", head.prov, "LEFT", -8, 0)
	f.head = head

	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(View.TOOLBAR_HEIGHT)
	bar:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
	bar.profession = Widgets.Select(bar, { width = 240, rows = 10, placeholder = L["CAT_PROFESSION"], onSelect = function(id)
		View:SetProfession(id)
	end })
	bar.profession:SetPoint("LEFT", bar, "LEFT", 0, 0)
	bar.profession:Hide()
	bar.category = Widgets.Select(bar, { width = 220, rows = 8, placeholder = L["RV_CATEGORY"], onSelect = function(id)
		local key = id ~= View.ALL and id or nil
		if View.mode == "catalogue" then View.cat:SetFilter(key) else View.model:SetCategory(key) end
		View:ResetScroll()
		View:Redraw()
	end })
	bar.category:SetPoint("LEFT", bar, "LEFT", 0, 0)
	bar.online = Widgets.Chip(bar, { text = L["CR_ONLINE_ONLY"], onClick = function(chip) View:SetOnlineOnly(not chip:IsSelected()) end })
	bar.online:SetPoint("LEFT", bar, "LEFT", 0, 0)
	Widgets.Tooltip.Attach(bar.online, { L["CR_ONLINE_ONLY"], L["CR_ONLINE_ONLY_TIP"] }, "BOTTOM")
	bar.count = Theme.NewText(bar, "Small", "text-3")
	bar.count:SetJustifyH("RIGHT")
	bar.count:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	f.bar = bar

	-- The one table of both lists: recipe (an icon and a name, or a crafter), details, status, and the request button.
	local columns = {
		{ id = "name", title = L["RV_COL_RECIPE"], flex = 1.4, sortable = false, render = function(cell, d, row) View.RenderName(cell, d, row) end },
		{ id = "detail", title = L["RV_COL_DETAILS"], flex = 1.6, sortable = false, render = function(cell, d) View.RenderDetail(cell, d) end },
		{ id = "note", title = L["RV_COL_STATUS"], width = 140, align = "RIGHT", sortable = false, render = function(cell, d) View.RenderNote(cell, d) end },
		{ id = "action", title = "", width = 116, sortable = false, render = function(cell) cell:SetText("") end },
	}
	local t = Widgets.DataTable(f, columns, {
		rowHeight = View.ROW_HEIGHT, pool = View.POOL, maxPool = 80,
		onRowClick = function(d, row) View:RowClicked(row) end,
		rowSetup = function(row) View.SetupRow(row) end,
		rowUpdate = function(row, d) View.UpdateRow(row, d) end,
	})
	t:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
	t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.table = t
	f.message = t.empty   -- the message in place of the rows
end

View.TIP_GAP = 12   -- points between the end of a name and its tooltip

-- Where a row's tooltip goes: its left edge just after the end of the name (owner, 2026-11-27: next to the name, not at
-- the far end of the row). A name longer than its cell ends at the cell's edge.
function View.TipAnchor(row)
	local cell = row.name
	local w = cell and (cell:GetStringWidth() or 0) or 0
	local room = cell and cell:GetWidth() or w
	if room and room > 0 and w > room then w = room end
	return { "LEFT", cell or row, "LEFT", w + View.TIP_GAP, 0 }
end

-- The game's own tooltip of a recipe (the spell link); the name and the category when it has none. A crafter row says who
-- they are and where the list comes from; a catalogue recipe that nobody knows says so. Every tooltip opens next to the name.
function View:ShowTooltip(row)
	local d = row.data
	if not d then return end
	local at = View.TipAnchor(row)
	if d.kind == "member" then
		local m = d.member
		Widgets.Tooltip.Show(row, { m.name, L["CR_TIP_RECIPE"]:format(d.recipeName), { text = View.MemberDetail(m), token = "text-3" },
			View.MemberListOn() and L["CR_TIP_CLICK"] or nil }, at)
		return
	end
	if d.kind == "cat" and not d.resolved then
		Widgets.Tooltip.Show(row, { d.name, { text = d.count > 0 and L["CAT_TIP_CLICK"] or L["CAT_TIP_NOBODY"], token = "text-3" } }, at)
		return
	end
	local link = ns.Recipes and ns.Recipes.LinkOf(d.id)
	if link and GameTooltip and GameTooltip.SetHyperlink then
		Widgets.Tooltip.Item(row, link, at)
	else
		local lines = { d.name }
		if d.category then lines[2] = { text = d.category, token = "text-3" } end
		Widgets.Tooltip.Show(row, lines, at)
	end
end

-- PRO-05: the member and the recipe of a row, for the Request craft button: a recipe of the member whose list is open, or
-- a crafter under a recipe of the search.
local function requestTarget(d)
	if type(d) ~= "table" then return nil end
	if d.kind == "member" then return d.member.guid, d.recipeId end
	if d.kind == "recipe" or d.kind == "cat" then return nil end
	if d.learned == false then return nil end   -- the member has not learned it
	return View.model.guid, d.id
end

-- With the switch "econ" a request is an order (SPEC-17 §3.5).
local function ordering() return ns.OrdersView ~= nil and ns.Orders ~= nil and ns.Orders.Enabled() end

-- Whether a row of `guid` has the Request craft button: an order takes any member outside the own account, online or
-- not; the whisper of M3 only an online one that is not the player.
local function canRequest(guid, online, isSelf)
	if not guid then return false end
	if ordering() then return ns.Orders:CanOrder(guid) end
	return online == true and isSelf ~= true
end

function View.RequestTip(d)
	local guid, id = requestTarget(d)
	if not guid then return nil end
	if ordering() then
		local e = ns.Roster and ns.Roster:ByGUID(guid)
		return { L["CR_REQUEST"], e and L["ORD_REQUEST_TIP"]:format(e.short or e.name) or L["CR_REQUEST_NO"] }
	end
	local request = ns.Recipes and ns.Recipes:CraftRequest(guid, id)
	return { L["CR_REQUEST"], request and L["CR_REQUEST_TIP"]:format(request.short) or L["CR_REQUEST_NO"] }
end

-- The Request craft button: opens the chat box with the whisper written; the player sends it. With the switch "econ" it
-- opens the New order window instead.
function View:RequestCraft(d)
	local guid, id = requestTarget(d)
	if not guid then return false end
	if ordering() then return ns.OrdersView:OpenNew(guid, id) ~= nil end
	local ok, result = ns.Recipes:OpenCraftRequest(guid, id)
	if ok then
		if ns.addon then ns.addon:Print(L["CR_REQUEST_OPENED"]:format(result.short)) end
	elseif ns.addon then
		ns.addon:Print(result == "offline" and L["CR_REQUEST_OFFLINE"] or L["CR_REQUEST_FAILED"])
	end
	return ok
end

-- A click on a crafter opens that member's recipe list for the profession the recipe is in; a click on a recipe of the
-- catalogue opens (or closes) the characters who can craft it.
function View:RowClicked(row)
	local d = row.data
	if not d then return end
	if d.kind == "member" then
		if not View.MemberListOn() then return end   -- the member list is switched off: a crafter's row only shows who
		self:Open(d.member.guid, d.member.skillLine or self.cat.skillLine, self.mode == "catalogue" and "catalogue" or "craft")
	elseif d.kind == "cat" and d.count > 0 then
		self.cat:Toggle(d.id)
		self:Redraw()
	end
end

function View:Build(f)
	self.frame = f
	build(self, f)
	f:SetScript("OnShow", function() View:Redraw() end)
	self:Redraw()
end

---------------------------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------------------------
-- "Alchemy 285/300, shared by the member's addon, 3 d ago" for a crafter (the profession, its rank and the source).
function View.MemberDetail(m)
	local parts = {}
	if m.profession or m.rank then
		parts[#parts + 1] = (m.profession or L["PROF_UNKNOWN"]:format(m.skillLine or 0)) .. (m.rank and (" " .. m.rank .. (m.maxRank and ("/" .. m.maxRank) or "")) or "")
	end
	local src = ns.RecipeModel.SourceText({ source = m.source, time = m.time }):gsub("^[^:]*:%s*", "")
	parts[#parts + 1] = src
	return table.concat(parts, " - ")
end

-- A row is made once: the recipe icon, the Request craft button, and short names for the cells the tests and the code use.
function View.SetupRow(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(View.ICON, View.ICON)
	row.name, row.detail, row.note = row.cells[1], row.cells[2], row.cells[3]
	row.name:SetJustifyH("LEFT")
	row.request = Widgets.Button(row, { text = L["CR_REQUEST"], style = "tonal", width = 104, height = Widgets.HEIGHT.small,
		onClick = function(b) View:RequestCraft(b:GetParent().data) end })
	row.request:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	row.request:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.request:Hide()
	Widgets.Tooltip.Attach(row.request, function(b) return View.RequestTip(b:GetParent().data) end, "TOP")
	row:HookScript("OnEnter", function(self) View:ShowTooltip(self) end)
	row:HookScript("OnLeave", function() Widgets.Tooltip.Hide() Widgets.Tooltip.HideItem() end)
end

-- Anchors a cell `offset` points inside its column (the first column makes room for the icon or the indent).
local function place(cell, row, col, offset)
	local pos = View.frame.table.pos and View.frame.table.pos[col]
	if not pos then return end
	cell:ClearAllPoints()
	cell:SetWidth(max(pos.w - offset - 8, 1))
	cell:SetPoint("LEFT", row, "LEFT", pos.x + offset, 0)
end

-- column 1: a recipe (icon and name, coloured by difficulty in the recipe list, accent in the craft list) or a crafter
function View.RenderName(cell, d, row)
	if d.kind == "member" then
		local m = d.member
		cell:SetText(m.name)
		Theme.ClassText(cell, classColor(m.classFile))
		place(cell, row, 1, 8 + d.depth * 14)
		return
	end
	cell:SetText(d.name)
	if d.kind == "recipe" then
		Theme.Text(cell, "accent-text")
	elseif d.kind == "cat" then
		Theme.Text(cell, d.expanded and "accent-text" or (d.resolved and "text-1" or "text-3"))
	elseif d.learned == false then
		Theme.Text(cell, "text-3")   -- not learned by the member: dimmed, never a difficulty colour
	else
		local diff = d.difficulty ~= nil and DIFFICULTY[d.difficulty]
		if diff then Theme.TextRGB(cell, diff[1], diff[2], diff[3]) else Theme.Text(cell, d.resolved and "text-1" or "text-3") end
	end
	place(cell, row, 1, View.ICON + 8)
end

function View.RenderDetail(cell, d)
	if d.kind == "member" then cell:SetText(View.MemberDetail(d.member))
	elseif d.level then cell:SetText(L["CAT_LEVEL"]:format(d.level))
	else cell:SetText("") end
	local open = d.kind ~= "member" and View.orders and View.orders[d.id]
	if open then
		local text = L[open == 1 and "ORD_CAT_ONE" or "ORD_CAT_N"]:format(open)
		cell:SetText(d.level and (cell:GetText() .. " · " .. text) or text)
	end
	Theme.Text(cell, "text-3")
end

function View.RenderNote(cell, d)
	if d.kind == "recipe" then
		cell:SetText(L["CR_CRAFTERS"]:format(d.count))
		Theme.Text(cell, "text-3")
	elseif d.kind == "cat" then
		cell:SetText(d.count > 0 and L["CR_CRAFTERS"]:format(d.count) or L["CAT_NOBODY"])
		Theme.Text(cell, d.count > 0 and "ok" or "text-3")
	elseif d.learned == false then
		cell:SetText(L["RV_NOT_LEARNED"])
		Theme.Text(cell, "text-3")
	elseif d.kind == "member" then
		cell:SetText(d.member.online and L["ONLINE"] or "")
		Theme.Text(cell, "ok")
	else
		cell:SetText(d.known and L["RV_YOU_KNOW"] or "")
		Theme.Text(cell, "ok")
	end
end

-- The icon and the Request button, once the cells are filled.
function View.UpdateRow(row, d)
	if d.kind == "member" then
		row.icon:Hide()
		row.request:SetShown(canRequest(d.member.guid, d.member.online, d.member.isSelf))
		return
	end
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	if d.icon then row.icon:SetTexture(d.icon) row.icon:Show() else row.icon:Hide() end
	if d.kind == "recipe" or d.kind == "cat" then
		row.request:Hide()
		return
	end
	local guid = requestTarget(d)
	local e = guid and ns.Roster and ns.Roster:ByGUID(guid)
	row.request:SetShown(e ~= nil and canRequest(guid, e.online, e.isSelf))
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
function View:VisibleRows()
	local t = self.frame and self.frame.table
	return t and t:Capacity() or 0
end

-- Gives the table `rows` (and the message shown when there are none), keeping the place in the list.
local function setRows(self, rows, message)
	local t = self.frame.table
	t:SetEmptyText(message or "")
	t:SetData(rows, true)
end

local function redrawCraft(self)
	local f, c = self.frame, self.craft
	research(self)
	local result = c.result
	f.head.back:Hide()
	f.head.craft:Hide()
	f.head.cat:SetLabel(L["CAT_BUTTON"])
	f.head.cat:ClearAllPoints()
	f.head.cat:SetPoint("TOPLEFT", f.head, "TOPLEFT", 0, 0)
	f.head.cat:Show()
	f.head.prov:SetSource(nil)
	f.head.title:ClearAllPoints()
	f.head.title:SetPoint("LEFT", f.head.cat, "RIGHT", 16, 0)
	f.head.title:SetPoint("RIGHT", f.head, "RIGHT", 0, 0)
	f.head.title:SetText(L["CR_TITLE"])
	Theme.Text(f.head.title, "text-1")
	f.head.source:ClearAllPoints()
	f.head.source:SetPoint("TOPLEFT", f.head.cat, "BOTTOMLEFT", 2, -8)
	f.head.source:SetPoint("RIGHT", f.head, "RIGHT", 0, 0)
	f.head.source:SetText(L["CR_HINT"])
	f.bar.profession:Hide()
	f.bar.category:Hide()
	f.bar.online:Show()
	f.bar.online:SetSelected(c.onlineOnly)
	if result.status == "ok" then
		setRows(self, c.rows, L["CR_NONE"]:format(self.craft.query))
		f.bar.count:SetText(result.more > 0 and L["CR_COUNT_MORE"]:format(#result.recipes, result.total) or L["CR_COUNT"]:format(result.total))
		return
	end
	f.bar.count:SetText("")
	if result.status == "short" then
		setRows(self, {}, L["CR_TYPE"])
	elseif result.pending > 0 then
		setRows(self, {}, L["CR_LOADING"])
	else
		setRows(self, {}, L["CR_NONE"]:format(self.craft.query))
	end
end

local function redrawRecipes(self)
	local f = self.frame
	local model = self.model
	f.head.back:Show()
	f.head.back:SetLabel(self.cameFrom == "catalogue" and L["CAT_BACK"] or (self.cameFrom == "craft" and L["CR_BACK"]) or L["RV_BACK"])
	f.head.craft:ClearAllPoints()
	f.head.craft:SetPoint("LEFT", f.head.back, "RIGHT", 8, 0)
	f.head.craft:Show()
	f.head.cat:SetLabel(L["RV_ALL_MEMBERS"])
	f.head.cat:ClearAllPoints()
	f.head.cat:SetPoint("LEFT", f.head.craft, "RIGHT", 8, 0)
	f.head.cat:SetShown(model.skillLine ~= nil)
	f.bar.profession:Hide()
	f.bar.category:ClearAllPoints()
	f.bar.category:SetPoint("LEFT", f.bar, "LEFT", 0, 0)
	f.head.title:ClearAllPoints()
	f.head.title:SetPoint("LEFT", model.skillLine and f.head.cat or f.head.craft, "RIGHT", 16, 0)
	f.head.title:SetPoint("RIGHT", f.head, "RIGHT", 0, 0)
	f.head.source:ClearAllPoints()
	f.head.source:SetPoint("TOPLEFT", f.head.back, "BOTTOMLEFT", 2, -8)
	f.head.source:SetPoint("RIGHT", f.head, "RIGHT", 0, 0)
	f.bar.online:Hide()
	local d = model:Describe()
	local title = L["RV_TITLE"]:format(d.title, d.profession)
	if d.rank then title = title .. " " .. d.rank .. (d.maxRank and ("/" .. d.maxRank) or "") end
	f.head.title:SetText(title)
	Theme.ClassText(f.head.title, classColor(d.classFile))
	f.head.source:SetText(d.sourceText or "")
	f.head.prov:SetSource(d.provenance)
	f.head.source:SetPoint("RIGHT", f.head.prov, "LEFT", -8, 0)
	local isList = d.status == "list"
	f.bar.category:SetShown(isList)
	if isList then
		local sel = f.bar.category
		sel:SetChoices(categoryChoices(self))
		if not sel:Select(model.category or View.ALL, true) then sel:Select(View.ALL, true) end
	end
	if not isList or d.total == 0 then
		f.bar.count:SetText("")
		setRows(self, {}, d.message or "")
		return
	end
	local rows = model:Rows()
	setRows(self, rows, L["RV_NO_MATCH"])
	if d.catalogue then
		f.bar.count:SetText(L["RV_COUNT_LEARNED"]:format(#rows, d.total, d.learned))
	else
		f.bar.count:SetText(L["RV_COUNT"]:format(#rows, d.total))
	end
end

-- The guild's recipes of one profession.
local function redrawCatalogue(self)
	local f, cat = self.frame, self.cat
	if not cat.skillLine then cat:SetProfession(cat:DefaultProfession()) end
	f.head.back:Hide()
	f.head.cat:Hide()
	f.head.craft:ClearAllPoints()
	f.head.craft:SetPoint("TOPLEFT", f.head, "TOPLEFT", 0, 0)
	f.head.craft:Show()
	f.bar.online:Hide()
	local d = cat:Describe()
	f.head.title:ClearAllPoints()
	f.head.title:SetPoint("LEFT", f.head.craft, "RIGHT", 16, 0)
	f.head.title:SetPoint("RIGHT", f.head, "RIGHT", 0, 0)
	f.head.title:SetText(d.skillLine and L["CAT_TITLE_OF"]:format(d.profession) or L["CAT_TITLE"])
	Theme.Text(f.head.title, "text-1")
	f.head.source:ClearAllPoints()
	f.head.source:SetPoint("TOPLEFT", f.head.craft, "BOTTOMLEFT", 2, -8)
	f.head.source:SetText(d.sourceText or "")
	f.head.prov:SetSource(d.provenance)
	f.head.source:SetPoint("RIGHT", f.head.prov, "LEFT", -8, 0)
	local profs = f.bar.profession
	profs:Show()
	profs:SetChoices(professionChoices())
	if d.skillLine then profs:Select(d.skillLine, true) end
	local sel = f.bar.category
	sel:ClearAllPoints()
	sel:SetPoint("LEFT", profs, "RIGHT", 8, 0)
	local hasRows = d.status == "catalogue" or d.status == "lists"
	sel:SetShown(hasRows)
	if hasRows then
		sel:SetChoices(categoryChoices(self))
		if not sel:Select(cat.filter or View.ALL, true) then sel:Select(View.ALL, true) end
	end
	if not hasRows then
		f.bar.count:SetText("")
		setRows(self, {}, d.message or "")
		return
	end
	setRows(self, cat:Rows(), d.message or L["RV_NO_MATCH"])
	f.bar.count:SetText(L["CAT_COUNT"]:format(d.shown, d.total, d.crafted))
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	if self.mode == "recipes" and not self.model.guid then self.mode = "catalogue" end
	-- the open orders of each recipe, said next to it in the catalogue (SPEC-17 §8)
	self.orders = ordering() and self.mode == "catalogue" and ns.Orders:OpenByRecipe() or nil
	if self.mode == "craft" then redrawCraft(self)
	elseif self.mode == "catalogue" then redrawCatalogue(self)
	else redrawRecipes(self) end
	self.drawn = (self.drawn or 0) + 1
end

function View:Scroll(delta)
	local t = self.frame and self.frame.table
	if not t then return false end
	local before = t.offset
	t:SetOffset(before + delta)
	return t.offset ~= before
end

-- Something changed behind what is on screen (a list arrived, names loaded, the roster refreshed): one redraw after the
-- burst, only when the view is visible.
function View:Changed()
	self.model:Invalidate()
	self.cat:Invalidate()
	self.craft.dirty = true
	if self.refreshTimer or not (self.frame and self.frame:IsVisible()) then return end
	self.refreshTimer = true
	local scheduled = ns.Compat and ns.Compat.After(View.REFRESH_DELAY, function()
		View.refreshTimer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.refreshTimer = nil self:Redraw() end
end

if ns.Shell then
	ns.Shell:RegisterView("professions", {
		label = L["VIEW_PROFESSIONS"], order = 20, search = true,
		build = function(f) View:Build(f) end,
		onSearch = function(text) View:SetSearch(text) end,
		-- a click on the Professions tab always shows the guild's recipes with the profession menu (owner, 2026-11-27)
		onTabClick = function() View:ToCatalogue() end,
	})
end

if ns.addon then
	ns.addon.RecipeView = View
	if ns.Bus then
		ns.Bus:On("RECIPES_UPDATED", function(guid, line)
			local m = View.model
			if View.mode == "craft" or View.mode == "catalogue" or (guid == nil and m.skillLine == line)
				or (m.guid == guid and (m.skillLine == line or m.skillLine == nil)) then View:Changed() end
		end)
		ns.Bus:On("RECIPE_NAMES_UPDATED", function() View:Changed() end)
		ns.Bus:On("ROSTER_UPDATED", function() View:Changed() end)
		ns.Bus:On("ORDERS_CHANGED", function() View:Changed() end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.model = Model.new()
			View.cat = Model.Catalogue.new()
			View.craft = { query = "", onlineOnly = false, result = nil, rows = nil, dirty = true }
			View.mode, View.cameFrom = "catalogue", "roster"
			View:ResetScroll()
			if View.frame then View:Redraw() end
		end)
	end
end

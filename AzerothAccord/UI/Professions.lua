-- Professions view (SPEC-06 PRO-02..PRO-04). Lua 5.1.
-- Two modes in one view:
--   craft     "who can craft ..." (PRO-04): the search box of the panel takes the name of an item or a recipe; the rows are
--             the recipes that match (Data/Crafters.lua), each followed by the members who know it, online first, the
--             characters of one account together; a click on a member opens that member's recipe list. "Online only"
--             keeps the crafters who are online now.
--   recipes   the recipe list of one member's profession (PRO-02, PRO-03): opened by a click on a profession cell of the
--             Roster table, on a profession line of the member card, or on a member in the craft list. Rows come from
--             UI/RecipeModel.lua: an icon, the name, a note when the player knows it too; the game's own recipe tooltip; the
--             search box filters by name; the Category menu; the message in place of the rows when there is no list.
-- The header has a Back button (to the roster, or to the craft list when the list was opened from it), and in the recipe
-- list a "Who can craft" button; the source and the age of the list are always in the header.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.RecipeView, ns.modules = View, ns.modules or {}
ns.modules.RecipeView = View

local L, W, Skin, Model = ns.L, ns.Widgets, ns.Skin, ns.RecipeModel
local type, ipairs, floor, max, min = type, ipairs, math.floor, math.max, math.min

View.ROW_HEIGHT = 22
View.HEADER_HEIGHT = 58
View.TOOLBAR_HEIGHT = 28
View.DEFAULT_ROWS = 14
View.WHEEL_STEP = 3
View.REFRESH_DELAY = 0.4       -- lists, names and the roster change in bursts; a redraw waits for the burst to end

View.mode = "craft"            -- "craft" or "recipes"
View.cameFrom = "roster"       -- where Back goes from the recipe list: "roster" or "craft"
View.model = Model.new()       -- the recipe list being looked at
View.craft = { query = "", onlineOnly = false, result = nil, rows = nil, dirty = true }
View.offset = 0

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
	local text = self.mode == "craft" and self.craft.query or self.model.search
	if (box:GetText() or "") ~= text then box:SetText(text) end
end

function View:SetMode(mode)
	if mode ~= "craft" and mode ~= "recipes" then return false end
	self.mode = mode
	self.offset = 0
	syncSearchBox(self)
	if mode == "craft" then self.craft.dirty = true end
	if self.frame then self:Redraw() end
	return true
end

-- Opens the list of `guid` for `skillLine` (nil: the game did not say which profession it is) and shows the view. `from`
-- says where Back goes: "roster" (the default) or "craft".
function View:Open(guid, skillLine, from)
	if type(guid) ~= "string" then return false end
	self.cameFrom = from == "craft" and "craft" or "roster"
	self.model:SetTarget(guid, skillLine)
	self.mode = "recipes"
	self.offset = 0
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

-- The text of the panel's search box changed.
function View:SetSearch(text)
	text = type(text) == "string" and text or ""
	if self.mode == "craft" then
		if text == self.craft.query then return end
		self.craft.query = text
		self.craft.dirty = true
		self.offset = 0
		self:Redraw()
	elseif self.model:SetSearch(text) then
		self.offset = 0
		self:Redraw()
	end
end

function View:SetOnlineOnly(on)
	on = on and true or false
	if self.craft.onlineOnly == on then return end
	self.craft.onlineOnly = on
	self.craft.dirty = true
	self.offset = 0
	self:Redraw()
end

function View:Back()
	if self.cameFrom == "craft" then
		self:SetMode("craft")
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
local function categoryMenu(self)
	local model = self.model
	local items = {}
	for _, c in ipairs(model:Categories()) do
		items[#items + 1] = { text = c.label, checked = model.category == c.key,
			onClick = function() model:SetCategory(c.key) self.offset = 0 self:Redraw() end }
	end
	return items
end

local function build(self, f)
	local head = W.Frame(f, 10, View.HEADER_HEIGHT)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	head.back = W.Button(head, { text = L["RV_BACK"], width = 110, onClick = function() View:Back() end })
	head.back:SetPoint("TOPLEFT", head, "TOPLEFT", 8, -6)
	head.craft = W.Button(head, { text = L["CR_BUTTON"], width = 120, onClick = function() View:SetMode("craft") end })
	head.craft:SetPoint("LEFT", head.back, "RIGHT", 6, 0)
	head.title = W.Text(head, "title", nil, "LEFT")
	head.title:SetPoint("LEFT", head.craft, "RIGHT", 12, 0)
	head.title:SetPoint("RIGHT", head, "RIGHT", -8, 0)
	head.source = W.Text(head, "small", "grey", "LEFT")
	head.source:SetPoint("TOPLEFT", head.back, "BOTTOMLEFT", 2, -6)
	head.source:SetPoint("RIGHT", head, "RIGHT", -8, 0)
	f.head = head

	local bar = W.Frame(f, 10, View.TOOLBAR_HEIGHT)
	bar:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
	bar.category = W.Button(bar, { text = L["RV_CATEGORY"], width = 130, onClick = function(b) W.ShowMenu(b, categoryMenu(View)) end })
	bar.category:SetPoint("LEFT", bar, "LEFT", 8, 0)
	bar.online = W.Check(bar, { text = L["CR_ONLINE_ONLY"], width = 110, checked = View.craft.onlineOnly,
		tooltip = { L["CR_ONLINE_ONLY"], L["CR_ONLINE_ONLY_TIP"] }, onClick = function(on) View:SetOnlineOnly(on) end })
	bar.online:SetPoint("LEFT", bar, "LEFT", 8, 0)
	bar.count = W.Text(bar, "small", "grey", "RIGHT")
	bar.count:SetPoint("RIGHT", bar, "RIGHT", -20, 0)
	f.bar = bar

	local area = W.Frame(f, 10, 10)
	area:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 0)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	area:SetScript("OnSizeChanged", function() View:Redraw() end)
	area.rows = {}
	f.area = area

	local track = W.Frame(f, 10, 10)
	track:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	track:SetWidth(12)
	track:EnableMouse(true)
	W.Background(track, "grey", 0.12)
	track.thumb = track:CreateTexture(nil, "ARTWORK")
	track.thumb:SetColorTexture(Skin.Color("gold", 0.5))
	track.thumb:SetWidth(10)
	track:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local cursorY
		if GetCursorPosition then _, cursorY = GetCursorPosition() end
		local top = track:GetTop()
		local scale = track:GetEffectiveScale() or 1
		if not (cursorY and top) then return end
		local y = top - cursorY / (scale > 0 and scale or 1)
		View:Scroll(y < (View.thumbTop or 0) and -View:VisibleRows() or View:VisibleRows())
	end)
	f.track = track

	f.message = W.Text(f, "body", "grey", "CENTER")
	f.message:SetPoint("CENTER", area, "CENTER", 0, 0)
	f.message:SetWidth(380)
end

local function newRow(self, area, i)
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(View.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(View.ROW_HEIGHT - 4, View.ROW_HEIGHT - 4)
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.name = W.Text(row, "body", nil, "LEFT")
	row.detail = W.Text(row, "small", "grey", "LEFT")
	row.request = W.Button(row, { text = L["CR_REQUEST"], width = 84, height = View.ROW_HEIGHT - 2,
		tooltip = function(b) return View.RequestTip(b:GetParent().data) end,
		onClick = function(b) View:RequestCraft(b:GetParent().data) end })
	row.request:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.request:Hide()
	row.note = W.Text(row, "small", "green", "RIGHT")
	row.note:SetPoint("RIGHT", row.request, "LEFT", -8, 0)
	row:SetScript("OnEnter", function(self2) View:ShowTooltip(self2) end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	row:SetScript("OnClick", function(self2) View:RowClicked(self2) end)
	area.rows[i] = row
	return row
end

-- The game's own tooltip of a recipe (the spell link); the name and the category when it has none. A crafter row says who
-- they are and where the list comes from.
function View:ShowTooltip(row)
	local d = row.data
	if not (d and GameTooltip) then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if d.kind == "member" then
		local m = d.member
		GameTooltip:SetText(m.name)
		GameTooltip:AddLine(L["CR_TIP_RECIPE"]:format(d.recipeName), 1, 1, 1, true)
		GameTooltip:AddLine(View.MemberDetail(m), 0.6, 0.6, 0.6, true)
		GameTooltip:AddLine(L["CR_TIP_CLICK"], 1, 1, 1, true)
		GameTooltip:Show()
		return
	end
	local link = ns.Recipes and ns.Recipes.LinkOf(d.id)
	if link and GameTooltip.SetHyperlink then
		GameTooltip:SetHyperlink(link)
	else
		GameTooltip:SetText(d.name)
	end
	if d.category then GameTooltip:AddLine(d.category, 0.6, 0.6, 0.6, true) end
	GameTooltip:Show()
end

-- PRO-05: the member and the recipe of a row, for the Request craft button: a recipe of the member whose list is open, or
-- a crafter under a recipe of the search.
local function requestTarget(d)
	if type(d) ~= "table" then return nil end
	if d.kind == "member" then return d.member.guid, d.recipeId end
	if d.kind == "recipe" then return nil end
	return View.model.guid, d.id
end

function View.RequestTip(d)
	local guid, id = requestTarget(d)
	if not guid then return nil end
	local request = ns.Recipes and ns.Recipes:CraftRequest(guid, id)
	return { L["CR_REQUEST"], request and L["CR_REQUEST_TIP"]:format(request.short) or L["CR_REQUEST_NO"] }
end

-- The Request craft button: opens the chat box with the whisper written; the player sends it.
function View:RequestCraft(d)
	local guid, id = requestTarget(d)
	if not guid then return false end
	local ok, result = ns.Recipes:OpenCraftRequest(guid, id)
	if ok then
		if ns.addon then ns.addon:Print(L["CR_REQUEST_OPENED"]:format(result.short)) end
	elseif ns.addon then
		ns.addon:Print(result == "offline" and L["CR_REQUEST_OFFLINE"] or L["CR_REQUEST_FAILED"])
	end
	return ok
end

-- A click on a crafter opens that member's recipe list for the profession the recipe is in.
function View:RowClicked(row)
	local d = row.data
	if d and d.kind == "member" then self:Open(d.member.guid, d.member.skillLine, "craft") end
end

function View:Build(f)
	self.frame = f
	build(self, f)
	f:SetScript("OnShow", function() View:Redraw() end)
	self.offset = 0
	self:Redraw()
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
function View:VisibleRows()
	local f = self.frame
	local h = f and f.area and f.area:GetHeight() or 0
	if not h or h < View.ROW_HEIGHT then return View.DEFAULT_ROWS end
	return max(1, floor(h / View.ROW_HEIGHT))
end

local function updateThumb(self, total, visible)
	local track = self.frame.track
	if total <= visible then
		track.thumb:Hide()
		self.thumbTop = 0
		return
	end
	local h = track:GetHeight() or 0
	if h <= 0 then h = 300 end
	local size = max(16, h * visible / total)
	local top = (h - size) * (self.offset / (total - visible))
	track.thumb:ClearAllPoints()
	track.thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -top)
	track.thumb:SetHeight(size)
	track.thumb:Show()
	self.thumbTop = top
end

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

local function fillRecipeRow(self, row, d)
	row.data = d
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row, "RIGHT", -110, 0)
	row.detail:Hide()
	row.name:SetText(d.name)
	local diff = d.difficulty ~= nil and DIFFICULTY[d.difficulty]
	if diff then row.name:SetTextColor(diff[1], diff[2], diff[3]) else row.name:SetTextColor(Skin.Color(d.resolved and "white" or "grey")) end
	if d.icon then
		row.icon:SetTexture(d.icon)
		row.icon:Show()
	else
		row.icon:Hide()
	end
	row.note:SetText(d.known and L["RV_YOU_KNOW"] or "")
	row.note:SetTextColor(Skin.Color("green"))
	local guid = requestTarget(d)
	local e = guid and ns.Roster and ns.Roster:ByGUID(guid)
	row.request:SetShown(e ~= nil and e.online == true and e.isSelf ~= true)
	row:Show()
end

local function fillCraftRow(self, row, d)
	row.data = d
	row.name:ClearAllPoints()
	row.detail:ClearAllPoints()
	if d.kind == "recipe" then
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.name:SetPoint("RIGHT", row, "RIGHT", -110, 0)
		row.name:SetText(d.name)
		row.name:SetTextColor(Skin.Color("gold"))
		if d.icon then row.icon:SetTexture(d.icon) row.icon:Show() else row.icon:Hide() end
		row.detail:Hide()
		row.request:Hide()
		row.note:SetText(L["CR_CRAFTERS"]:format(d.count))
		row.note:SetTextColor(Skin.Color("grey"))
	else
		local m = d.member
		row.icon:Hide()
		row.name:SetPoint("LEFT", row, "LEFT", 34 + d.depth * 14, 0)
		row.name:SetWidth(150)
		row.name:SetText(m.name)
		row.name:SetTextColor(classColor(m.classFile))
		row.detail:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
		row.detail:SetPoint("RIGHT", row, "RIGHT", -190, 0)
		row.detail:SetText(View.MemberDetail(m))
		row.detail:Show()
		row.note:SetText(m.online and L["ONLINE"] or "")
		row.note:SetTextColor(Skin.Color("green"))
		row.request:SetShown(m.online == true and m.isSelf ~= true)
	end
	row:Show()
end

-- Draws `rows` (a list) through `fill` in the pool; returns how many rows there are.
local function drawRows(self, rows, fill)
	local f = self.frame
	local total, visible = #rows, self:VisibleRows()
	self.offset = max(0, min(self.offset or 0, max(0, total - visible)))
	local drawn = max(0, min(visible + 1, total - self.offset))
	for i = 1, drawn do
		local row = f.area.rows[i] or newRow(self, f.area, i)
		fill(self, row, rows[self.offset + i])
	end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	updateThumb(self, total, visible)
	return total
end

local function hideRows(self)
	for _, row in ipairs(self.frame.area.rows) do row:Hide() end
	self.frame.track.thumb:Hide()
end

local function redrawCraft(self)
	local f, c = self.frame, self.craft
	research(self)
	local result = c.result
	f.head.back:Hide()
	f.head.craft:Hide()
	f.head.title:ClearAllPoints()
	f.head.title:SetPoint("TOPLEFT", f.head, "TOPLEFT", 8, -8)
	f.head.title:SetPoint("RIGHT", f.head, "RIGHT", -8, 0)
	f.head.title:SetText(L["CR_TITLE"])
	f.head.title:SetTextColor(Skin.Color("gold"))
	f.head.source:ClearAllPoints()
	f.head.source:SetPoint("TOPLEFT", f.head.title, "BOTTOMLEFT", 0, -6)
	f.head.source:SetPoint("RIGHT", f.head, "RIGHT", -8, 0)
	f.head.source:SetText(L["CR_HINT"])
	f.bar.category:Hide()
	f.bar.online:Show()
	f.bar.online:SetChecked(c.onlineOnly)
	if result.status == "ok" then
		local total = drawRows(self, c.rows, fillCraftRow)
		local crafters = 0
		for _, r in ipairs(result.recipes) do crafters = crafters + r.count end
		f.bar.count:SetText(result.more > 0 and L["CR_COUNT_MORE"]:format(#result.recipes, result.total) or L["CR_COUNT"]:format(result.total))
		f.message:SetShown(total == 0)
		return
	end
	hideRows(self)
	f.bar.count:SetText("")
	if result.status == "short" then
		f.message:SetText(L["CR_TYPE"])
	elseif result.pending > 0 then
		f.message:SetText(L["CR_LOADING"])
	else
		f.message:SetText(L["CR_NONE"]:format(self.craft.query))
	end
	f.message:Show()
end

local function redrawRecipes(self)
	local f = self.frame
	local model = self.model
	f.head.back:Show()
	f.head.craft:Show()
	f.head.title:ClearAllPoints()
	f.head.title:SetPoint("LEFT", f.head.craft, "RIGHT", 12, 0)
	f.head.title:SetPoint("RIGHT", f.head, "RIGHT", -8, 0)
	f.head.source:ClearAllPoints()
	f.head.source:SetPoint("TOPLEFT", f.head.back, "BOTTOMLEFT", 2, -6)
	f.head.source:SetPoint("RIGHT", f.head, "RIGHT", -8, 0)
	f.bar.online:Hide()
	local d = model:Describe()
	local title = L["RV_TITLE"]:format(d.title, d.profession)
	if d.rank then title = title .. " " .. d.rank .. (d.maxRank and ("/" .. d.maxRank) or "") end
	f.head.title:SetText(title)
	f.head.title:SetTextColor(classColor(d.classFile))
	f.head.source:SetText(d.sourceText or "")
	f.bar.category:SetShown(d.status == "list")
	if d.status ~= "list" or d.total == 0 then
		hideRows(self)
		f.bar.count:SetText("")
		f.message:SetText(d.message or "")
		f.message:Show()
		return
	end
	local total = drawRows(self, model:Rows(), fillRecipeRow)
	f.bar.count:SetText(L["RV_COUNT"]:format(total, d.total))
	if total == 0 then
		f.message:SetText(L["RV_NO_MATCH"])
		f.message:Show()
	else
		f.message:Hide()
	end
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	if self.mode == "recipes" and not self.model.guid then self.mode = "craft" end
	if self.mode == "craft" then redrawCraft(self) else redrawRecipes(self) end
	self.drawn = (self.drawn or 0) + 1
end

function View:Scroll(delta)
	local total = self.mode == "craft" and (self.craft.rows and #self.craft.rows or 0) or #self.model:Rows()
	local limit = max(0, total - self:VisibleRows())
	local target = max(0, min((self.offset or 0) + delta, limit))
	if target == self.offset then return false end
	self.offset = target
	self:Redraw()
	return true
end

-- Something changed behind what is on screen (a list arrived, names loaded, the roster refreshed): one redraw after the
-- burst, only when the view is visible.
function View:Changed()
	self.model:Invalidate()
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
	})
end

if ns.addon then
	ns.addon.RecipeView = View
	if ns.Bus then
		ns.Bus:On("RECIPES_UPDATED", function(guid, line)
			local m = View.model
			if View.mode == "craft" or (m.guid == guid and (m.skillLine == line or m.skillLine == nil)) then View:Changed() end
		end)
		ns.Bus:On("RECIPE_NAMES_UPDATED", function() View:Changed() end)
		ns.Bus:On("ROSTER_UPDATED", function() View:Changed() end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.model = Model.new()
			View.craft = { query = "", onlineOnly = false, result = nil, rows = nil, dirty = true }
			View.mode, View.offset, View.cameFrom = "craft", 0, "roster"
			if View.frame then View:Redraw() end
		end)
	end
end

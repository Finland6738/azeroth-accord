-- Professions view: the recipe list of a member's profession (SPEC-06 PRO-02, PRO-03). Lua 5.1.
-- A click on a profession cell of the Roster table, or on a profession line of a member's card, opens it here (the view
-- is registered as "professions"; M3.5 adds the "who can craft" search to the same view). The rows come from
-- UI/RecipeModel.lua; this file draws them:
--   header     a Back button to the roster, "<member> - <profession> <rank>/<max rank>", where the list comes from and how old
--              it is, the category menu and the count
--   rows       virtual (a pool as tall as the list), an icon, the recipe name, a note when the player knows it too; the
--              tooltip is the game's own spell tooltip (the recipe link), the search box of the panel filters by name
--   message    in place of the rows: why there is no list and what to ask the member (PRO-03)
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
View.REDRAW_DELAY = 0.2        -- names of recipes arrive one by one; the redraw waits for a burst to end

View.model = Model.new()
View.offset = 0

local function classColor(classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

-- The colour of a recipe name by difficulty (orange, yellow, green, grey: the game's own order), white when unknown.
local DIFFICULTY = { [0] = { 1, 0.5, 0.25 }, [1] = { 1, 1, 0 }, [2] = { 0.25, 0.75, 0.25 }, [3] = { 0.6, 0.6, 0.6 } }

---------------------------------------------------------------------------------------------------------------------
-- Opening the list
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

-- Opens the list of `guid` for `skillLine` (nil: the game did not say which profession it is) and shows the view.
function View:Open(guid, skillLine)
	if type(guid) ~= "string" then return false end
	self.offset = 0
	self.model:SetTarget(guid, skillLine)
	local shown = true
	if ns.Shell then shown = ns.Shell:OpenView("professions") end
	if self.frame then self:Redraw() end
	return shown ~= false
end

-- From a roster entry and the slot (1 or 2) of its profession cell.
function View:OpenFor(entry, slot)
	local p = entry and entry.professions and entry.professions[slot]
	if not p then return false end
	return self:Open(entry.guid, View.SkillLineOf(entry, p))
end

function View:SetSearch(text)
	if self.model:SetSearch(text) then
		self.offset = 0
		self:Redraw()
	end
end

function View:Back()
	if ns.Shell then ns.Shell:Select("roster") end
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
	head.title = W.Text(head, "title", nil, "LEFT")
	head.title:SetPoint("LEFT", head.back, "RIGHT", 12, 0)
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
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row, "RIGHT", -110, 0)
	row.note = W.Text(row, "small", "green", "RIGHT")
	row.note:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row:SetScript("OnEnter", function(self2) View:ShowTooltip(self2) end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	area.rows[i] = row
	return row
end

-- The game's own tooltip of the recipe (the spell link); the name and the category when it has none.
function View:ShowTooltip(row)
	local d = row.data
	if not (d and GameTooltip) then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local link = ns.Recipes and ns.Recipes.LinkOf(d.id)
	if link and GameTooltip.SetHyperlink then
		GameTooltip:SetHyperlink(link)
	else
		GameTooltip:SetText(d.name)
	end
	if d.category then GameTooltip:AddLine(d.category, 0.6, 0.6, 0.6, true) end
	GameTooltip:Show()
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

local function fillRow(self, row, d)
	row.data = d
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
	row:Show()
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local model = self.model
	if not model.guid then
		f.head.title:SetText(L["VIEW_PROFESSIONS"])
		f.head.source:SetText("")
		f.bar.count:SetText("")
		f.bar.category:Hide()
		for _, row in ipairs(f.area.rows) do row:Hide() end
		f.track.thumb:Hide()
		f.message:SetText(L["RV_HINT_PICK"])
		f.message:Show()
		return
	end
	local d = model:Describe()
	local title = L["RV_TITLE"]:format(d.title, d.profession)
	if d.rank then title = title .. " " .. d.rank .. (d.maxRank and ("/" .. d.maxRank) or "") end
	f.head.title:SetText(title)
	f.head.title:SetTextColor(classColor(d.classFile))
	f.head.source:SetText(d.sourceText or "")
	f.bar.category:SetShown(d.status == "list")
	if d.status ~= "list" or d.total == 0 then
		for _, row in ipairs(f.area.rows) do row:Hide() end
		f.track.thumb:Hide()
		f.bar.count:SetText("")
		f.message:SetText(d.message or "")
		f.message:Show()
		return
	end
	local rows = model:Rows()
	local total, visible = #rows, self:VisibleRows()
	self.offset = max(0, min(self.offset or 0, max(0, total - visible)))
	local drawn = max(0, min(visible + 1, total - self.offset))
	for i = 1, drawn do
		local row = f.area.rows[i] or newRow(self, f.area, i)
		fillRow(self, row, rows[self.offset + i])
	end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	updateThumb(self, total, visible)
	f.bar.count:SetText(L["RV_COUNT"]:format(total, d.total))
	if total == 0 then
		f.message:SetText(L["RV_NO_MATCH"])
		f.message:Show()
	else
		f.message:Hide()
	end
	self.drawn = (self.drawn or 0) + 1
end

function View:Scroll(delta)
	local total = #self.model:Rows()
	local limit = max(0, total - self:VisibleRows())
	local target = max(0, min((self.offset or 0) + delta, limit))
	if target == self.offset then return false end
	self.offset = target
	self:Redraw()
	return true
end

-- Something changed behind the list (a list arrived, names loaded, the roster refreshed): redraw when it is on screen.
function View:Changed()
	self.model:Invalidate()
	if self.frame and self.frame:IsVisible() then self:Redraw() end
end

-- Names of recipes load one by one: one redraw for a burst.
function View:NamesChanged()
	self.model:Invalidate()
	if self.namesTimer or not (self.frame and self.frame:IsVisible()) then return end
	self.namesTimer = true
	local scheduled = ns.Compat and ns.Compat.After(View.REDRAW_DELAY, function()
		View.namesTimer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.namesTimer = nil self:Redraw() end
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
			if m.guid == guid and (m.skillLine == line or m.skillLine == nil) then View:Changed() end
		end)
		ns.Bus:On("RECIPE_NAMES_UPDATED", function() if View.model.guid then View:NamesChanged() end end)
		ns.Bus:On("ROSTER_UPDATED", function() if View.model.guid then View:Changed() end end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.model = Model.new()
			View.offset = 0
			if View.frame then View:Redraw() end
		end)
	end
end

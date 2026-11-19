-- Roster view: the member table of the Accord panel (SPEC-05 §1, SPEC-04 §2). Lua 5.1.
-- The rows come from UI/RosterModel.lua; this file only draws them. Rows are virtual: a pool of as many row frames as the
-- table is tall (plus one) is refilled when the table scrolls, so a guild of 1000 members never creates 1000 frames.
--   toolbar    Online, Mains only, By account (grouped), Class / Rank / Profession menus, Columns, the count
--   header     one clickable title per visible column: sorts, a second click reverses
--   rows       class-coloured names, one cell per column; in the grouped view the main leads its account with a
--              +/- button that shows the alts
-- A click on a row selects the member (Bus: ROSTER_SELECT(guid, entry)); the member card of M2.4 listens to it.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.RosterView, ns.modules = View, ns.modules or {}
ns.modules.RosterView = View

local L, W, Skin, Model = ns.L, ns.Widgets, ns.Skin, ns.RosterModel
local type, ipairs, pairs, floor, max, min = type, ipairs, pairs, math.floor, math.max, math.min

View.ROW_HEIGHT = 18
View.HEADER_HEIGHT = 20
View.TOOLBAR_HEIGHT = 28
View.DEFAULT_ROWS = 20          -- rows drawn when the frame has no size yet
View.WHEEL_STEP = 3

View.model = nil                -- the RosterModel in use (one per session)
View.selected = nil             -- GUID of the selected member

function View:Model()
	if not self.model then
		self.model = Model.new()
		self.model:Load()
	end
	return self.model
end

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

---------------------------------------------------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------------------------------------------------
local function classColor(classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function setCell(fs, text, color, entry)
	fs:SetText(text or "")
	if color == "class" then fs:SetTextColor(classColor(entry.classFile))
	elseif color then fs:SetTextColor(Skin.Color(color))
	else fs:SetTextColor(Skin.Color("white")) end
end

---------------------------------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------------------------------
local function filterMenu(self, kind, labelAll)
	local model = self:Model()
	local items = { { text = labelAll, checked = model.filters[kind] == nil, onClick = function() model:SetFilter(kind, nil) self:Changed() end } }
	for _, choice in ipairs(model:Choices(kind)) do
		items[#items + 1] = { text = choice.label, checked = model.filters[kind] == choice.key,
			onClick = function() model:SetFilter(kind, choice.key) self:Changed() end }
	end
	return items
end

local function buildToolbar(self, f)
	local bar = W.Frame(f, 10, View.TOOLBAR_HEIGHT)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	local model = self:Model()
	local x = 6
	local function place(widget, width)
		widget:SetPoint("LEFT", bar, "LEFT", x, 0)
		x = x + width + 6
	end
	bar.online = W.Check(bar, { text = L["FILTER_ONLINE"], width = 64, checked = model.filters.online,
		onClick = function(on) model:SetFilter("online", on) self:Changed() end })
	place(bar.online, 64)
	bar.mains = W.Check(bar, { text = L["FILTER_MAINS"], width = 86, checked = model.filters.mains,
		tooltip = { L["FILTER_MAINS"], L["FILTER_MAINS_TIP"] },
		onClick = function(on) model:SetFilter("mains", on) self:Changed() end })
	place(bar.mains, 86)
	bar.grouped = W.Check(bar, { text = L["FILTER_GROUPED"], width = 100, checked = model.grouped,
		tooltip = { L["FILTER_GROUPED"], L["FILTER_GROUPED_TIP"] },
		onClick = function(on) model:SetGrouped(on) self:Changed() end })
	place(bar.grouped, 100)
	local function menuButton(text, kind, all)
		local b = W.Button(bar, { text = text, width = 84, onClick = function(self2) W.ShowMenu(self2, filterMenu(View, kind, all)) end })
		place(b, 84)
		return b
	end
	bar.class = menuButton(L["COL_CLASS"], "class", L["FILTER_ALL_CLASSES"])
	bar.rank = menuButton(L["COL_RANK"], "rank", L["FILTER_ALL_RANKS"])
	bar.profession = menuButton(L["FILTER_PROFESSION"], "profession", L["FILTER_ALL_PROFESSIONS"])
	bar.columns = W.Button(bar, { text = L["COLUMNS"], width = 74, tooltip = { L["COLUMNS"], L["COLUMNS_TIP"] },
		onClick = function(b) View:ShowColumnMenu(b) end })
	place(bar.columns, 74)
	bar.count = W.Text(bar, "small", "grey", "RIGHT")
	bar.count:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	f.toolbar = bar
end

function View:ShowColumnMenu(anchor)
	local model = self:Model()
	local items = {}
	for _, c in ipairs(Model.AvailableColumns()) do
		if not c.always then
			items[#items + 1] = { text = L[c.label], checked = model:HasColumn(c.id), keepOpen = true,
				onClick = function() model:ToggleColumn(c.id) model:Save() View:Changed(true) end }
		end
	end
	items[#items + 1] = { text = L["COLUMNS_RESET"], onClick = function()
		model:SetColumns(model:DefaultColumns())
		model:Save()
		View:Changed(true)
	end }
	W.ShowMenu(anchor, items)
end

local function buildHeader(self, f)
	local header = W.Frame(f, 10, View.HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", f.toolbar, "BOTTOMLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", f.toolbar, "BOTTOMRIGHT", -14, 0)
	W.Background(header, "navSelected", 0.12)
	header.buttons = {}
	f.header = header
end

local function buildScroll(self, f)
	local area = W.Frame(f, 10, 10)
	area:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, 0)
	area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 0)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	area:SetScript("OnSizeChanged", function() View:Redraw() end)
	area.rows = {}
	f.area = area

	local track = W.Frame(f, 10, 10)
	track:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 14, 0)
	track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	track:SetWidth(12)
	track:EnableMouse(true)
	W.Background(track, "grey", 0.12)
	track.thumb = track:CreateTexture(nil, "ARTWORK")
	track.thumb:SetColorTexture(Skin.Color("gold", 0.5))
	track.thumb:SetWidth(10)
	-- a click on the track pages up or down; the wheel does the fine work
	track:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local cursorY
		if GetCursorPosition then _, cursorY = GetCursorPosition() end
		local top = track:GetTop()
		local scale = track:GetEffectiveScale() or 1
		if not (cursorY and top) then return end
		local y = top - cursorY / (scale > 0 and scale or 1)
		local thumbTop = View.thumbTop or 0
		View:Scroll(y < thumbTop and -View:VisibleRows() or View:VisibleRows())
	end)
	f.track = track

	f.empty = W.Text(f, "body", "grey", "CENTER")
	f.empty:SetPoint("CENTER", area, "CENTER", 0, 0)
	f.empty:SetWidth(340)
end

local function newRow(self, area, i)
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(View.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints(row)
	row.selected:SetColorTexture(Skin.Color("navSelected", 0.25))
	row.selected:Hide()
	row.cells = {}
	row.expander = CreateFrame("Button", nil, row)
	row.expander:SetSize(14, View.ROW_HEIGHT)
	row.expander.label = W.Text(row.expander, "heading", "gold", "CENTER")
	row.expander.label:SetAllPoints(row.expander)
	row.expander:SetScript("OnClick", function(btn)
		local data = btn:GetParent().data
		if data and data.group then
			View:Model():ToggleExpand(data.group.id)
			View:Changed()
		end
	end)
	row:SetScript("OnClick", function(self2) View:Select(self2.data) end)
	W.SetTooltip(row, function(self2)
		local d = self2.data
		if not d then return nil end
		local lines = { d.entry.name or "?" }
		if d.kind == "group" then lines[#lines + 1] = L["ROW_TIP_GROUP"]:format(d.count) end
		lines[#lines + 1] = L["ROW_TIP_CLICK"]
		return lines
	end)
	area.rows[i] = row
	return row
end

-- While the table is visible the roster follows the server (Roster:Watch): asked for fresh data at most every 15 s and
-- rebuilt after a burst of changes. Idempotent, so OnShow and the first draw cannot count twice.
function View:StartWatch()
	if self.watching or not ns.Roster then return end
	self.watching = true
	ns.Roster:Watch()
end

function View:StopWatch()
	if W.MenuIsOpen() then W.HideMenu() end
	if not self.watching then return end
	self.watching = false
	if ns.Roster then ns.Roster:Unwatch() end
end

function View:Build(f)
	self.frame = f
	buildToolbar(self, f)
	buildHeader(self, f)
	buildScroll(self, f)
	f:SetScript("OnShow", function() View:StartWatch() View:Changed() end)
	f:SetScript("OnHide", function() View:StopWatch() end)
	self.offset = 0
	self:Changed(true)
	if f:IsVisible() then self:StartWatch() end   -- a new frame is shown without an OnShow
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

local function layoutHeader(self)
	local f, model = self.frame, self:Model()
	local header, x = f.header, 0
	local cols = model:VisibleColumns()
	for i, col in ipairs(cols) do
		local b = header.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, header)
			b:SetHeight(View.HEADER_HEIGHT)
			b.label = W.Text(b, "heading", nil, "LEFT")
			b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
			b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
			b.highlight:SetAllPoints(b)
			b.highlight:SetColorTexture(1, 1, 1, 0.08)
			b:SetScript("OnClick", function(btn)
				local m = View:Model()
				m:SetSort(btn.columnId)
				m:Save()
				View:Changed()
			end)
			header.buttons[i] = b
		end
		b.columnId = col.id
		b:ClearAllPoints()
		b:SetPoint("LEFT", header, "LEFT", x, 0)
		b:SetWidth(col.width)
		local arrow = ""
		if model.sort.key == col.id then arrow = model.sort.desc and " v" or " ^" end
		b.label:SetText(L[col.label] .. arrow)
		b:Show()
		x = x + col.width
	end
	for i = #cols + 1, #header.buttons do header.buttons[i]:Hide() end
	self.columnsWidth = x
end

local function fillRow(self, row, data)
	local model, cols = self:Model(), self.cols
	row.data = data
	local e = data.entry
	for i, col in ipairs(cols) do
		local fs = row.cells[i]
		if not fs then
			fs = W.Text(row, "small", nil, "LEFT")
			row.cells[i] = fs
		end
		local x = self.columnX[i]
		local indent = (col.id == "name") and (data.depth * 14 + (data.kind == "group" and 14 or 0)) or 0
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", row, "LEFT", x + 4 + indent, 0)
		fs:SetWidth(col.width - 6 - indent)
		local text, color = Model.Cell(col.id, e)
		if col.id == "name" and data.kind == "alt" then color = color or "class" end
		setCell(fs, text, color, e)
		fs:Show()
	end
	for i = #cols + 1, #row.cells do row.cells[i]:Hide() end
	if data.kind == "group" then
		row.expander:ClearAllPoints()
		row.expander:SetPoint("LEFT", row, "LEFT", self.columnX[1] + 2, 0)
		row.expander.label:SetText(data.expanded and "-" or "+")
		row.expander:SetShown(data.count > 0)
	else
		row.expander:Hide()
	end
	row.selected:SetShown(self.selected ~= nil and e.guid == self.selected)
	row:Show()
end

local function updateThumb(self, total, visible)
	local f = self.frame
	local track = f.track
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

function View:Redraw()
	local f = self.frame
	if not f then return end
	local model = self:Model()
	local rows = model:Rows()
	local total, visible = #rows, self:VisibleRows()
	self.offset = max(0, min(self.offset or 0, max(0, total - visible)))
	layoutHeader(self)
	self.cols = model:VisibleColumns()
	self.columnX = {}
	local x = 0
	for i, col in ipairs(self.cols) do self.columnX[i] = x x = x + col.width end
	local drawn = max(0, min(visible + 1, total - self.offset))
	for i = 1, drawn do
		local row = f.area.rows[i] or newRow(self, f.area, i)
		fillRow(self, row, rows[self.offset + i])
	end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	updateThumb(self, total, visible)
	local members = #model:Members()
	f.toolbar.count:SetText(L["ROSTER_COUNT"]:format(total, members))
	if total == 0 then
		f.empty:SetText(members == 0 and L["ROSTER_EMPTY"] or L["ROSTER_NO_MATCH"])
		f.empty:Show()
	else
		f.empty:Hide()
	end
	self.drawn = (self.drawn or 0) + 1
end

-- The model changed (a filter, the sort, the data): rebuild the rows and draw; `keepOffset` is the default, a changed
-- row set simply clamps it.
function View:Changed(reset)
	if reset then self.offset = 0 end
	self:Model():Invalidate()
	self:Redraw()
end

function View:Scroll(delta)
	local total = #self:Model():Rows()
	local limit = max(0, total - self:VisibleRows())
	local target = max(0, min((self.offset or 0) + delta, limit))
	if target == self.offset then return false end
	self.offset = target
	self:Redraw()
	return true
end

function View:SetSearch(text)
	if self:Model():SetSearch(text) then
		self.offset = 0
		self:Redraw()
	end
end

function View:Select(data)
	if not data then return end
	self.selected = data.entry.guid
	self:Redraw()
	emit("ROSTER_SELECT", data.entry.guid, data.entry)
end

if ns.Shell then
	ns.Shell:RegisterView("roster", {
		label = L["VIEW_ROSTER"], order = 10, search = true,
		build = function(f) View:Build(f) end,
		onSearch = function(text) View:SetSearch(text) end,
	})
end

if ns.addon then
	ns.addon.RosterView = View
	if ns.Bus then
		local function refresh()
			if View.frame and View.frame:IsVisible() then View:Changed() elseif View.model then View.model:Invalidate() end
		end
		ns.Bus:On("ROSTER_UPDATED", refresh)
		ns.Bus:On("ACCOUNTS_UPDATED", refresh)
		ns.Bus:On("GUILD_CHANGED", function() View.selected = nil refresh() end)
	end
end

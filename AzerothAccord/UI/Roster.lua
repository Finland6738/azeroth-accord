-- Roster view: the member table of the Accord panel (SPEC-05 §1, SPEC-04 §2, docs/specs/ui-style.md §3). Lua 5.1.
-- The rows come from UI/RosterModel.lua; this file only draws them, with the widget kit (UI/Widgets) and the theme
-- (UI/Theme.lua): every colour is a token, class colours come from the game. The table is a Widgets.DataTable: its rows are a
-- pool refilled while the list scrolls, so a guild of 1000 members never creates 1000 frames, and the model (not the table)
-- sorts, because the grouped view orders whole accounts.
--   toolbar    chips Online, By account (grouped, on by default); selects Class / Rank / Profession; the column chooser
--              (Widgets.Menu); the count. On a narrow panel the toolbar wraps to a second line.
--   header     one clickable title per visible column: sorts, a second click reverses (the sorted one in accent with an arrow)
--   rows       a class mark and the class-coloured name, one cell per column; in the grouped view the main leads its
--              account with a +/- button that shows the alts
-- A click on a row selects the member (Bus: ROSTER_SELECT(guid, entry)); the member card of M2.4 listens to it.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.RosterView, ns.modules = View, ns.modules or {}
ns.modules.RosterView = View

local L, Widgets, Theme, Model = ns.L, ns.Widgets, ns.Theme, ns.RosterModel
local type, ipairs, pairs, max, min = type, ipairs, pairs, math.max, math.min

View.ROW_HEIGHT = 32
View.HEADER_HEIGHT = 32
View.TOOLBAR_LINE = 40          -- one line of the toolbar (controls are 32 or 36 high)
View.POOL = 24                  -- row frames made up front (the table grows them when the window gets taller)
View.NAME_WIDTH = 160           -- the name column carries the class mark and, grouped, the +/- button
View.DEFAULT_WIDTH = 888        -- the width assumed before the frame has a size
View.COUNT_WIDTH = 130          -- room kept for the count at the right of the first toolbar line
View.INDENT = 14                -- an alt of an account is drawn this far in
View.ROLE_ICON = 14          -- the role icon before a name (ui-style §9.10: 14 inside a text)
View.ALL = "*"                  -- the id of "all" in the filter selects

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

-- The colour hint of RosterModel.Cell as a theme token ("class" is the game's colour, handled apart).
local TONE = { muted = "text-3", grey = "text-3", green = "ok", red = "err" }

local function paintCell(fs, color, entry)
	if color == "class" then
		Theme.ClassText(fs, classColor(entry.classFile))
	else
		Theme.Text(fs, TONE[color] or "text-1")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Toolbar
---------------------------------------------------------------------------------------------------------------------
local FILTERS = {   -- the three selects: kind, the label of "all"
	{ kind = "class", all = "FILTER_ALL_CLASSES", title = "COL_CLASS", width = 140 },
	{ kind = "rank", all = "FILTER_ALL_RANKS", title = "COL_RANK", width = 150 },
	-- wide enough for "All professions" on one line (owner, 2026-11-27: it wrapped at 128)
	{ kind = "profession", all = "FILTER_ALL_PROFESSIONS", title = "FILTER_PROFESSION", width = 180 },
}

local function exportAllowed() return ns.Export ~= nil and ns.Export.Allowed() end

local function buildToolbar(self, f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(View.TOOLBAR_LINE)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	local model = self:Model()
	-- a selected chip grows by its check: the toolbar places its controls again
	local function resized() View:LayoutToolbar() end
	bar.online = Widgets.Chip(bar, { text = L["FILTER_ONLINE"], onResize = resized, onClick = function(chip)
		model:SetFilter("online", not chip:IsSelected())
		View:Changed()
	end })
	bar.grouped = Widgets.Chip(bar, { text = L["FILTER_GROUPED"], onResize = resized, onClick = function(chip)
		model:SetGrouped(not chip:IsSelected())
		View:Changed()
	end })
	Widgets.Tooltip.Attach(bar.grouped, { L["FILTER_GROUPED"], L["FILTER_GROUPED_TIP"] }, "BOTTOM")
	for _, fl in ipairs(FILTERS) do
		bar[fl.kind] = Widgets.Select(bar, { width = fl.width or 128, rows = 8, placeholder = L[fl.title], onSelect = function(id)
			model:SetFilter(fl.kind, id ~= View.ALL and id or nil)
			View:Changed()
		end })
	end
	-- round buttons with an icon (owner, 2026-11-28); their names are in the tooltips
	bar.columns = Widgets.IconButton(bar, { icon = "columns", dense = true, onClick = function(b) View:ShowColumnMenu(b) end })
	Widgets.Tooltip.Attach(bar.columns, { L["COLUMNS"], L["COLUMNS_TIP"] }, "BOTTOM")
	-- officers only (SPEC-12 §6): the export of the characters the table shows
	bar.export = Widgets.IconButton(bar, { icon = "download", dense = true,
		onClick = function() View:OpenExport() end })
	Widgets.Tooltip.Attach(bar.export, { L["EXPORT_BUTTON"] }, "BOTTOM")
	bar.count = Theme.NewText(bar, "Small", "text-3")
	bar.count:SetJustifyH("RIGHT")
	bar.count:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -13)
	bar:SetScript("OnSizeChanged", function(self)
		local w = self:GetWidth() or 0
		if w ~= View.toolbarWidth then View.toolbarWidth = w View:LayoutToolbar() end   -- the height it sets is not a reason to run again
	end)
	f.toolbar = bar
	self.toolbarItems = { bar.online, bar.grouped, bar.class, bar.rank, bar.profession, bar.columns, bar.export }
	bar.export:SetShown(exportAllowed())
end

function View:OpenExport()
	if not exportAllowed() then return nil end
	return ns.ExportBox:Open("roster", self:Model():Entries())
end

-- Puts the controls in line and wraps them to a second line when they do not fit beside the count; the table starts under
-- the last line.
function View:LayoutToolbar()
	local f = self.frame
	if not (f and f.toolbar and self.toolbarItems) then return end
	local bar = f.toolbar
	local width = bar:GetWidth() or 0
	if width < 100 then width = View.DEFAULT_WIDTH - (self.inset or 0) end
	local limit = width - View.COUNT_WIDTH
	local x, line = 0, 0
	for _, item in ipairs(self.toolbarItems) do
		if item ~= bar.export or item:IsShown() then   -- a member has no export button: it takes no room
			local w = item:GetWidth() or 0
			if x > 0 and x + w > limit and line == 0 then x, line = 0, 1 elseif x + w > width and x > 0 then x, line = 0, line + 1 end
			item:ClearAllPoints()
			-- by the middle of its line: the controls are not all of one height
			item:SetPoint("LEFT", bar, "TOPLEFT", x, -(line + 0.5) * View.TOOLBAR_LINE)
			x = x + w + 8
		end
	end
	local h = (line + 1) * View.TOOLBAR_LINE
	bar:SetHeight(h)
	self.toolbarLines = line + 1
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
	return Widgets.Menu.Show(anchor, items)
end

-- Chips, selects and their choices follow the model (a filter set elsewhere, the roster changed).
local function syncToolbar(self)
	local f = self.frame
	if not (f and f.toolbar) then return end
	local bar, model = f.toolbar, self:Model()
	bar.online:SetSelected(model.filters.online == true)
	bar.grouped:SetSelected(model.grouped == true)
	for _, fl in ipairs(FILTERS) do
		local sel = bar[fl.kind]
		local choices = { { id = View.ALL, text = L[fl.all] } }
		for _, c in ipairs(model:Choices(fl.kind)) do choices[#choices + 1] = { id = c.key, text = c.label } end
		sel:SetChoices(choices)
		local want = model.filters[fl.kind]
		if want == nil or not sel:Select(want, true) then sel:Select(View.ALL, true) end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Table
---------------------------------------------------------------------------------------------------------------------
-- While the table is visible the roster follows the server (Roster:Watch): asked for fresh data at most every 15 s and
-- rebuilt after a burst of changes. Idempotent, so OnShow and the first draw cannot count twice.
function View:StartWatch()
	if self.watching or not ns.Roster then return end
	self.watching = true
	ns.Roster:Watch()
end

function View:StopWatch()
	if Widgets.Menu.IsOpen() then Widgets.Menu.Hide() end
	if not self.watching then return end
	self.watching = false
	if ns.Roster then ns.Roster:Unwatch() end
end

-- The tooltip of a row: the name, how many alts a group row hides, and the click.
local function rowTip(row)
	local d = row.data
	if not d then return nil end
	local lines = { d.entry.name or "?" }
	lines[#lines + 1] = Model.RoleLine(d.entry, View.season)
	if d.kind == "group" then lines[#lines + 1] = L["ROW_TIP_GROUP"]:format(d.count) end
	if d.entry.notInGuild and d.entry.altGuild then   -- the cell is narrow: the whole line, and where it comes from (M7.3)
		lines[#lines + 1] = ns.Provenance.AltGuildText(d.entry.altGuild)
		for _, tip in ipairs(ns.Provenance.TipLines(ns.Provenance.AltGuildInfo(d.entry.altGuild))) do lines[#lines + 1] = tip end
	end
	lines[#lines + 1] = L["ROW_TIP_CLICK"]
	return lines
end

-- The invisible button over a profession cell (PRO-02): a click opens that member's recipe list; the tooltip says where
-- the profession comes from and how old it is (PRO-01).
function View.ProfessionTip(data, slot)
	local p = data and data.entry and data.entry.professions and data.entry.professions[slot]
	if not p then return nil end
	local lines = { Model.ProfessionText(p) }
	for _, tip in ipairs(ns.Provenance.TipLines(ns.Provenance.ProfessionInfo(p))) do lines[#lines + 1] = tip end
	lines[#lines + 1] = L["PROF_TIP_CLICK"]
	return lines
end

local function profButton(row, i)
	row.profButtons = row.profButtons or {}
	local b = row.profButtons[i]
	if b then return b end
	b = CreateFrame("Button", nil, row)
	b:SetHeight(View.ROW_HEIGHT)
	b:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	b:SetScript("OnClick", function(self)
		local data = self:GetParent().data
		if data and self.slot and ns.RecipeView then ns.RecipeView:OpenFor(data.entry, self.slot) end
	end)
	Widgets.Tooltip.Attach(b, function(self) return View.ProfessionTip(self:GetParent().data, self.slot) end, "RIGHT")
	row.profButtons[i] = b
	return b
end

local function fillProfessionButtons(self, row, data)
	local t, e, used = self.frame.table, data.entry, {}
	for i, col in ipairs(t.columns) do
		local slot = col.id == "prof1" and 1 or (col.id == "prof2" and 2 or nil)
		if slot and ns.RecipeView and e.professions and e.professions[slot] and t.pos then
			local b = profButton(row, i)
			b.slot = slot
			b:ClearAllPoints()
			b:SetPoint("LEFT", row, "LEFT", t.pos[i].x, 0)
			b:SetWidth(max(t.pos[i].w - 4, 1))
			b:Show()
			used[i] = true
		end
	end
	for i, b in pairs(row.profButtons or {}) do
		if not used[i] then b.slot = nil b:Hide() end
	end
end

-- The role icon in the class colour of the game; on the light theme a darker shade, so a white class still shows.
local function paintRoleIcon(icon, themeId)
	local r, g, b = classColor(icon.classFile)
	local theme = ns.Theme.themes[themeId or ns.Theme.Current()]
	local k = (theme and not theme.dark) and 0.7 or 1
	icon:SetVertexColor(r * k, g * k, b * k, 1)
end

View.PaintRoleIcon = paintRoleIcon   -- the member card draws the same icon

-- How far the name is pushed right: the +/- slot (when grouped) and the indent of an alt, then the mark (the role icon,
-- or the class square of a member without a role).
local function nameOffset(self, data)
	local slot = self:Model().grouped and 18 or 0
	return slot + (data.depth or 0) * View.INDENT
end

-- One cell: the text of RosterModel.Cell in its colour; the name also moves right of the class mark.
local function renderCell(self, index, id)
	return function(cell, data, row)
		local e = data.entry
		local text, color = Model.Cell(id, e)
		cell:SetText(text or "")
		paintCell(cell, color, e)
		-- on the selected row the plain texts are on-secondary-container; the name keeps the class colour
		if color ~= "class" and self.selected ~= nil and e.guid == self.selected then Theme.Text(cell, "on-secondary-container") end
		if id == "name" then
			local t = self.frame.table
			local pos = t.pos and t.pos[index]
			if pos then
				local off = nameOffset(self, data) + 18
				cell:ClearAllPoints()
				cell:SetWidth(max(pos.w - off - 8, 1))
				cell:SetPoint("LEFT", row, "LEFT", pos.x + off, 0)
			end
		end
	end
end

local NUMERIC = { level = true, likes = true, social = true, addon = false }

local function tableColumns(self)
	local out = {}
	for i, col in ipairs(self:Model():VisibleColumns()) do
		out[i] = { id = col.id, title = L[col.label], width = col.id == "name" and View.NAME_WIDTH or col.width,
			mono = NUMERIC[col.id] or nil, render = renderCell(self, i, col.id) }
	end
	return out
end

local function rowSetup(row)
	row.mark = Widgets.ClassMark(row, 10)
	row.role = row:CreateTexture(nil, "ARTWORK")
	row.role:SetTexture(ns.Assets.textures.icons.path)
	row.role:SetSize(View.ROLE_ICON, View.ROLE_ICON)
	row.role:Hide()
	Theme.Call(row.role, paintRoleIcon)
	row.expander = CreateFrame("Button", nil, row)
	row.expander:SetSize(18, View.ROW_HEIGHT)
	row.expander:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	row.expander.label = Theme.NewText(row.expander, "BodyMedium", "accent-text")
	row.expander.label:SetAllPoints(row.expander)
	row.expander:SetScript("OnClick", function(btn)
		local data = btn:GetParent().data
		if data and data.group then
			View:Model():ToggleExpand(data.group.id)
			View:Changed()
		end
	end)
	row.expander:Hide()
	Widgets.Tooltip.Attach(row, rowTip, "RIGHT")
end

local function rowUpdate(row, data)
	local self = View
	local t = self.frame.table
	local e = data.entry
	local pos1 = t.pos and t.pos[1] or { x = 8 }
	local indent = (data.depth or 0) * View.INDENT
	local grouped = self:Model().grouped
	-- the +/- button of a group (account) row; every row of a grouped table leaves its slot
	if data.kind == "group" then
		row.expander:ClearAllPoints()
		row.expander:SetPoint("LEFT", row, "LEFT", pos1.x + indent - 2, 0)
		row.expander.label:SetText(data.expanded and "-" or "+")
		row.expander:SetShown(data.count > 0)
	else
		row.expander:Hide()
	end
	-- before the name, in the class colour of the game: the icon of the member's role (the public note, else the season
	-- declaration), else the square of the class
	local at = pos1.x + indent + (grouped and 18 or 0)
	local role = Model.Role(e, self.season)
	row.mark:ClearAllPoints()
	row.mark:SetPoint("LEFT", row, "LEFT", at, 0)
	row.role:ClearAllPoints()
	row.role:SetPoint("LEFT", row, "LEFT", at - 2, 0)
	if role then
		Widgets.ClearClassMark(row.mark)
		row.role:SetTexCoord(ns.Assets.IconCoords("role_" .. role, true))   -- filled (owner, 2026-11-28)
		row.role.classFile = e.classFile
		paintRoleIcon(row.role)
		row.role:Show()
	else
		row.role:Hide()
		if e.classFile then Widgets.PaintClassMark(row.mark, classColor(e.classFile)) else Widgets.ClearClassMark(row.mark) end
	end
	fillProfessionButtons(self, row, data)
end

function View:Build(f)
	self.frame = f
	buildToolbar(self, f)
	local t = Widgets.DataTable(f, tableColumns(self), {
		rowHeight = View.ROW_HEIGHT, headerHeight = View.HEADER_HEIGHT, pool = View.POOL, maxPool = 80,
		isSelected = function(data) return View.selected ~= nil and data.entry.guid == View.selected end,
		onSort = function(id)
			local m = View:Model()
			m:SetSort(id)
			m:Save()
			View:Changed()
		end,
		onRowClick = function(data) View:Select(data) end,
		rowSetup = rowSetup, rowUpdate = rowUpdate,
	})
	f.table = t
	self.columnsKey = nil
	f:SetScript("OnShow", function() View:StartWatch() View:Changed() end)
	f:SetScript("OnHide", function() View:StopWatch() end)
	f:SetScript("OnSizeChanged", function()
		if ns.MemberCard and ns.MemberCard:IsShown() then ns.MemberCard:Place() ns.MemberCard:Layout() end
		View:Reflow()
	end)
	self:Reflow()
	self:Changed(true)
	if f:IsVisible() then self:StartWatch() end   -- a new frame is shown without an OnShow
end

-- The table gives room to the member card when it sits beside it (Card:Inset): the toolbar and the table end that many
-- pixels before the right edge; the toolbar wraps to what is left.
function View:Reflow()
	local f = self.frame
	if not f or not f.toolbar then return end
	local inset = ns.MemberCard and ns.MemberCard:Inset() or 0
	self.inset = inset
	f.toolbar:ClearAllPoints()
	f.toolbar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.toolbar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, 0)
	self:LayoutToolbar()
	f.table:ClearAllPoints()
	f.table:SetPoint("TOPLEFT", f.toolbar, "BOTTOMLEFT", 0, -8)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, 0)
	f.table:Layout()
	f.table:Refresh()   -- Layout puts the cells back where a plain table has them: the name cell moves again
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
-- How many rows the table shows at once.
function View:VisibleRows()
	local t = self.frame and self.frame.table
	return t and t:Capacity() or 0
end

-- The visible columns changed (the column chooser): the table takes the new set.
local function applyColumns(self)
	local model = self:Model()
	local key = table.concat(model.columns, ",")
	if key == self.columnsKey then return end
	self.columnsKey = key
	self.frame.table:SetColumns(tableColumns(self))
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local model = self:Model()
	local rows = model:Rows()
	local t = f.table
	applyColumns(self)
	t:SetSortMark(model.sort.key, model.sort.desc)
	local members = #model:Members()
	t:SetEmptyText(members == 0 and L["ROSTER_EMPTY"] or L["ROSTER_NO_MATCH"])
	self.season = Model.Season()
	t:SetData(rows)
	f.toolbar.count:SetText(L["ROSTER_COUNT"]:format(#rows, members))
	self.drawn = (self.drawn or 0) + 1
end

-- The model changed (a filter, the sort, the data): rebuild the rows and draw; `reset` goes back to the top, otherwise
-- the table keeps its place (a changed row set simply clamps it).
function View:Changed(reset)
	local f = self.frame
	self:Model():Invalidate()
	if f and f.table and reset then f.table.offset = 0 end
	syncToolbar(self)
	self:Redraw()
end

function View:Scroll(delta)
	local t = self.frame and self.frame.table
	if not t then return false end
	local before = t.offset
	t:SetOffset(before + delta)
	return t.offset ~= before
end

function View:SetSearch(text)
	if self:Model():SetSearch(text) then
		if self.frame then self.frame.table.offset = 0 end
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
		ns.Bus:On("SEASON_CHANGED", refresh)   -- the role of a member without one in the note
		ns.Bus:On("ROLE_CHANGED", function()
			local bar = View.frame and View.frame.toolbar
			if not bar then return end
			bar.export:SetShown(exportAllowed())
			View:LayoutToolbar()
		end)
		ns.Bus:On("GUILD_CHANGED", function() View.selected = nil refresh() end)
	end
end

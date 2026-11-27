-- Availability view: when the guild usually plays (M10.8; SPEC-14 §8; SPEC-10 Q23). Lua 5.1.
--
-- At the top "Guild" or "Mine", and what the map is made of. Below, a grid of the week: one row per day (Monday first),
-- one column per hour of the realm's clock. In "Guild" every cell holds how many members are usually online then (level
-- Availability.USUAL or higher, out of those who share), darker where more are; in "Mine" the own four levels, counted
-- on this computer whether shared or not. A click on a cell shows it under the grid: the count, how often, the own
-- level and, only as far as Availability:Who() lets this character see (officers and the Guild Master: everybody),
-- the names. While FDCP is the source of the season roster an officer also reads the days declared in FDCP, apart and
-- labelled as a declaration, not a measurement.
-- Nothing here comes from raids: the map is made of the time online only (integration rule 7).
--
-- View.Model(cell, mode) reads everything now; View.Lines(model) and View.Cell(model, h) are plain functions of it
-- (tested offline); the frames only draw. While Core/Features.lua "season" is off there is no tab, no command and
-- nothing is redrawn.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.AvailabilityView, ns.modules = View, ns.modules or {}
ns.modules.AvailabilityView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, max, min, ceil, concat = math.floor, math.max, math.min, math.ceil, table.concat

View.ROW_HEIGHT = 20
View.WHEEL_STEP = 3
View.REFRESH_DELAY = 0.4
View.CELL_W, View.CELL_H, View.GAP = 26, 20, 2
View.LABEL_W = 44
View.NAMES_PER_LINE = 8
View.HOUR_STEP = 2                          -- a heading over every second column
View.ALPHA = { 0.2, 0.4, 0.65, 0.9 }        -- the four shades of a cell that is not empty
View.DAYS = { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" }

local function on() return ns.Features ~= nil and ns.Features.On("season") end
View.Enabled = on

local function dayName(d) return L["AVAIL_DAY_" .. View.DAYS[d]] end

-- 1..7 and 0..23 of a cell.
local function split(cell) return floor(cell / 24) + 1, cell % 24 end

-- "Monday 20:00-21:00"
function View.CellName(cell)
	local d, h = split(cell)
	return L["AVAIL_CELL"]:format(dayName(d), h, (h + 1) % 24)
end

---------------------------------------------------------------------------------------------------------------------
-- The model, the cells and the lines
---------------------------------------------------------------------------------------------------------------------
-- Everything the view shows, for the cell `cell` (nil: the hour of now) in mode "guild" (default) or "mine".
function View.Model(cell, mode)
	local A = ns.Availability
	local m = { mode = mode == "mine" and "mine" or "guild", sharing = A.Sharing() }
	if cell == nil then cell = select(2, A.Now()) end
	m.cell = cell
	m.map = A:Map()
	m.own, m.weeks = A:Own()
	m.who = A:Who(cell)
	m.names = A.CanSeeNames()
	m.declared = A:Declared()
	return m
end

-- What the cell `h` of a model draws: shade 0 (empty) to 4, and its text.
function View.Cell(m, h)
	if m.mode == "mine" then
		local level = m.own and m.own[h] or 0
		-- three levels over four shades: the darkest for "more than half of the weeks"
		return level == 0 and 0 or level + 1, ""
	end
	local n = m.map.cells[h].n
	if n == 0 or m.map.max == 0 then return 0, "" end
	return max(1, min(4, ceil(n * 4 / m.map.max))), tostring(n)
end

local function nameLines(add, head, names)
	if #names == 0 then return end
	add(head:format(#names), "sub")
	for i = 1, #names, View.NAMES_PER_LINE do
		local part = {}
		for j = i, min(#names, i + View.NAMES_PER_LINE - 1) do part[#part + 1] = names[j] end
		add(concat(part, ", "), "indent")
	end
end

-- { { text, heading?, sub?, muted?, indent? } } under the grid.
function View.Lines(m)
	local out = {}
	local function add(text, kind)
		local l = { text = text }
		if kind then l[kind] = true end
		out[#out + 1] = l
	end
	add(View.CellName(m.cell), "heading")
	local level = m.own and m.own[m.cell] or 0
	add(L["AVAIL_OWN"]:format(L["AVAIL_LEVEL_" .. level], m.weeks or 0))
	local c = m.map.cells[m.cell]
	if m.map.total == 0 then
		add(L["AVAIL_NOBODY"], "muted")
	else
		add(c.n == 1 and L["AVAIL_USUAL_ONE"]:format(m.map.total) or L["AVAIL_USUAL"]:format(c.n, m.map.total))
		for lv = 3, 1, -1 do
			if c.levels[lv] > 0 then add(("%s: %d"):format(L["AVAIL_LEVEL_" .. lv], c.levels[lv]), "indent") end
		end
		if m.names then
			for lv = 3, 1, -1 do
				local names = {}
				for _, w in ipairs(m.who) do
					if w.level == lv then
						names[#names + 1] = w.weeks < ns.Availability.WEEKS and L["AVAIL_NAME_WEEKS"]:format(w.name, w.weeks) or w.name
					end
				end
				nameLines(add, L["AVAIL_NAMES_" .. lv], names)
			end
		else
			add(L["AVAIL_NAMES_OFFICERS"], "muted")
		end
	end
	if m.declared then
		local d = split(m.cell)
		add(L["AVAIL_FDCP"]:format(dayName(d)), "heading")
		add(L["AVAIL_FDCP_NOTE"], "muted")
		if #m.declared[d] == 0 then add(L["AVAIL_FDCP_NONE"], "muted") end
		nameLines(add, L["AVAIL_FDCP_NAMES"], m.declared[d])
	end
	return out
end

-- The line under the switch: what the map is made of.
function View.Summary(m)
	local parts = {}
	if m.mode == "mine" then
		parts[1] = L["AVAIL_MINE_SUMMARY"]:format(m.weeks or 0)
	else
		parts[1] = L["AVAIL_GUILD_SUMMARY"]:format(m.map.total, ns.Availability.WEEKS)
	end
	if not m.sharing then parts[#parts + 1] = L["AVAIL_NOT_SHARING"] end
	return concat(parts, " ")
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local function buildGrid(f)
	local grid = CreateFrame("Frame", nil, f)
	grid:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -62)
	local w, h, gap, left = View.CELL_W, View.CELL_H, View.GAP, View.LABEL_W
	grid:SetSize(left + 24 * (w + gap), 18 + 7 * (h + gap))
	grid.cells, grid.days, grid.hours = {}, {}, {}
	for hour = 0, 23, View.HOUR_STEP do
		local t = Widgets.Text(grid, "Small", "text-3", "LEFT")
		t:SetPoint("TOPLEFT", grid, "TOPLEFT", left + hour * (w + gap) + 2, 0)
		t:SetText(("%02d"):format(hour))
		grid.hours[#grid.hours + 1] = t
	end
	for d = 1, 7 do
		local y = -18 - (d - 1) * (h + gap)
		local t = Widgets.Text(grid, "Small", "text-2", "LEFT")
		t:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, y - 4)
		t:SetText(L["AVAIL_SHORT_" .. View.DAYS[d]])
		grid.days[d] = t
		for hour = 0, 23 do
			local index = (d - 1) * 24 + hour
			local b = CreateFrame("Button", nil, grid)
			b:SetSize(w, h)
			b:SetPoint("TOPLEFT", grid, "TOPLEFT", left + hour * (w + gap), y)
			b.back = b:CreateTexture(nil, "BACKGROUND")
			b.back:SetAllPoints(b)
			b.mark = b:CreateTexture(nil, "OVERLAY")   -- the chosen cell: a line under it
			b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
			b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
			b.mark:SetHeight(3)
			Theme.Fill(b.mark, "text-1")
			b.mark:Hide()
			b.label = Widgets.Text(b, "Small", "text-1", "CENTER", "OVERLAY")
			b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
			b:SetScript("OnClick", function() View:Choose(index) end)
			Widgets.Tooltip.Attach(b, function()
				local m = View.model
				if not m then return nil end
				local second = m.mode == "mine" and L["AVAIL_LEVEL_" .. (m.own and m.own[index] or 0)]
					or L["AVAIL_USUAL_TIP"]:format(m.map.cells[index].n)
				return { View.CellName(index), second }
			end, "RIGHT")
			grid.cells[index] = b
		end
	end
	return grid
end

function View:Build(f)
	self.frame = f
	f.modeSeg = Widgets.Segmented(f, { { id = "guild", text = L["AVAIL_MODE_GUILD"] }, { id = "mine", text = L["AVAIL_MODE_MINE"] } },
		function(id)
			if View.painting then return end
			View.mode = id
			View:Redraw()
		end)
	f.modeSeg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.summary = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.summary:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -40)
	f.summary:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.grid = buildGrid(f)

	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", f.grid, "BOTTOMLEFT", 0, -10)
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.list:SetClipsChildren(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	f.list.lines = {}
	f.offset = 0
	f:SetScript("OnShow", function() View:Redraw() end)
	self:Redraw()
end

function View:Choose(cell)
	self.cell = cell
	if self.frame then self.frame.offset = 0 end
	self:Redraw()
end

local function visibleRows(list)
	local h = list and list:GetHeight() or 0
	return h >= View.ROW_HEIGHT and floor(h / View.ROW_HEIGHT) or 8
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local m = View.Model(self.cell, self.mode)
	self.model = m
	self.painting = true
	f.modeSeg:Select(m.mode)
	self.painting = false
	f.summary:SetText(View.Summary(m))
	for h = 0, ns.Availability.CELLS - 1 do
		local b = f.grid.cells[h]
		local shade, text = View.Cell(m, h)
		if shade == 0 then Theme.Fill(b.back, "surface-2") else Theme.Fill(b.back, "accent", View.ALPHA[shade]) end
		b.shade = shade
		b.label:SetText(text)
		b.mark:SetShown(h == m.cell)
	end

	local lines = View.Lines(m)
	self.shown = lines
	local list = f.list
	local visible = visibleRows(list)
	f.offset = max(0, min(f.offset or 0, max(0, #lines - visible)))
	local drawn = max(0, min(visible, #lines - f.offset))
	for i = 1, drawn do
		local l = lines[f.offset + i]
		local fs = list.lines[i]
		if not fs then
			fs = Widgets.Text(list, "Body", "text-1", "LEFT")
			fs:SetWordWrap(false)
			list.lines[i] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", list, "TOPLEFT", l.indent and 12 or 0, -(i - 1) * View.ROW_HEIGHT)
		fs:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		fs:SetText(l.text)
		fs:SetFontObject(Theme.Font(l.heading and "H2" or l.sub and "BodyMedium" or "Body"))
		if l.heading then Theme.Text(fs, "text-1")
		elseif l.muted then Theme.Text(fs, "text-3")
		else Theme.Text(fs, "text-2") end
		fs:Show()
	end
	for i = drawn + 1, #list.lines do list.lines[i]:Hide() end
end

function View:Scroll(delta)
	local f = self.frame
	if not f then return false end
	local total = self.shown and #self.shown or 0
	local target = max(0, min((f.offset or 0) + delta, max(0, total - visibleRows(f.list))))
	if target == f.offset then return false end
	f.offset = target
	self:Redraw()
	return true
end

function View:Changed()
	if self.refreshTimer or not (self.frame and self.frame:IsVisible()) then return end
	self.refreshTimer = true
	local scheduled = ns.Compat and ns.Compat.After(View.REFRESH_DELAY, function()
		View.refreshTimer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.refreshTimer = nil self:Redraw() end
end

if ns.Shell then
	ns.Shell:RegisterView("availability", { label = L["VIEW_AVAILABILITY"], order = 52, visible = on,
		build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.AvailabilityView = View
	if ns.Bus then
		local function changed() if on() then View:Changed() end end
		for _, event in ipairs({ "AVAILABILITY_CHANGED", "SOURCES_CHANGED", "SETTINGS_CHANGED", "ROLE_CHANGED", "FDCP_CHANGED" }) do
			ns.Bus:On(event, changed)
		end
	end
end

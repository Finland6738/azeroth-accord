-- Widget kit, part 6: the "Sort by" menu of a list without columns, and the sheet, a page of text lines in which every
-- list with columns is a Widgets.DataTable (docs/specs/ui-style.md §9.9, M13.8). Lua 5.1.
-- Like the rest of the kit: the words come in translated from the caller, ordinary frames only.
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets = ns.Widgets

local floor, max, min, ipairs, pairs, tonumber = math.floor, math.max, math.min, ipairs, pairs, tonumber

---------------------------------------------------------------------------------------------------------------------
-- "Sort by"
---------------------------------------------------------------------------------------------------------------------
-- A button that says the order of a list without columns and opens a menu of the choices: a choice sorts ascending, a
-- second click on the chosen one descending. opts: label (translated, with %s for the choice), items = { { id, text } }
-- (the first is the list's own order unless opts.default says another), default, memory (the remembered choice, as
-- the DataTable's), onChange(id, desc). :Get() -> id, desc; :Choose(id) (as a click in the menu); :ShowMenu().
function Widgets.SortMenu(parent, opts)
	local b = Widgets.Button(parent, { style = "outlined", height = Widgets.HEIGHT.small, icon = "arrow_up",
		text = "" })
	local function textOf(id)
		for _, item in ipairs(opts.items) do if item.id == id then return item.text end end
		return nil
	end
	local fallback = opts.default or opts.items[1].id

	function b:Get()
		local id, desc = Widgets.SortMemory.Get(opts.memory)
		if id and textOf(id) then
			self.id, self.desc = id, desc
		elseif not self.id then
			self.id, self.desc = fallback, false
		end
		return self.id, self.desc
	end

	function b:Paint()
		local id, desc = self:Get()
		self:SetLabel(opts.label:format(textOf(id)))
		self.icon:SetTexCoord(ns.Assets.IconCoords(desc and "arrow_down" or "arrow_up"))
	end

	function b:Choose(id)
		if not textOf(id) then return false end
		local current, desc = self:Get()
		self.id, self.desc = id, current == id and not desc
		Widgets.SortMemory.Set(opts.memory, self.id, self.desc)
		self:Paint()
		if opts.onChange then opts.onChange(self.id, self.desc) end
		return true
	end

	function b:ShowMenu()
		local current = self:Get()
		local items = {}
		for i, item in ipairs(opts.items) do
			items[i] = { text = item.text, checked = item.id == current, onClick = function() self:Choose(item.id) end }
		end
		return Widgets.Menu.Show(self, items)
	end

	b:SetScript("OnClick", function(self) self:ShowMenu() end)
	b:Paint()
	return b
end

---------------------------------------------------------------------------------------------------------------------
-- The sheet
---------------------------------------------------------------------------------------------------------------------
-- A scrolling page of lines. A line is { text, tip?, ... } drawn as one line of text (with its tooltip), or { table = key, cells = { [column] =
-- text }, keys? = { [column] = sort key } }: consecutive lines of the same key are the rows of a DataTable with its
-- header, as high as the rows it shows. The wheel moves one line or one row at a time.
-- opts: rowHeight (a text line, 20), tableRow (32), defaultRows (16, while the sheet has no height yet), wheelStep (3),
--   paint(fontString, line) (font and colour), indent(line) -> points from the left,
--   tables = { [key] = { columns = { { id, title, width | flex, mono?, align?, token? = fn(line), render? } },
--     memory?, onRowClick?(line, row), isSelected?(line), rowSetup?(row), rowUpdate?(row, line) } }
-- :SetLines(list) draws; :Draw(); :Scroll(delta) -> moved; .offset (lines and rows above the first one shown);
-- .lines (the font strings, pooled); :Table(key, n) the n-th table of `key` (1 by default), :Tables() those shown.
local HEAD, GAP = 34, 6   -- a table's header with the line under it, and the room after a table

function Widgets.Sheet(parent, opts)
	opts = opts or {}
	local rowH, tableRow = opts.rowHeight or 20, opts.tableRow or 32
	local s = CreateFrame("Frame", nil, parent)
	s.data, s.lines, s.offset, s.pool, s.hits = {}, {}, 0, {}, {}
	local blocks = {}   -- blocks[i] = the table block of line i
	if s.SetClipsChildren then s:SetClipsChildren(true) end
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(_, delta) s:Scroll(-delta * (opts.wheelStep or 3)) end)

	local function height()
		local h = s:GetHeight() or 0
		return h >= rowH and h or rowH * (opts.defaultRows or 16)
	end

	local function segment()
		blocks = {}
		local count, current = {}, nil
		for i, line in ipairs(s.data) do
			if line.table and opts.tables and opts.tables[line.table] then
				if not (current and current.key == line.table and current.last == i - 1) then
					count[line.table] = (count[line.table] or 0) + 1
					current = { key = line.table, n = count[line.table], first = i, rows = {} }
				end
				current.last = i
				current.rows[#current.rows + 1] = line
				blocks[i] = current
			end
		end
	end

	-- The columns of a key: the cells of the lines, sorted by their own key when a line has one.
	local function columnsOf(spec)
		local out = {}
		for i, c in ipairs(spec.columns) do
			local col = {}
			for k, v in pairs(c) do col[k] = v end
			local id = col.id
			col.text = col.text or function(l) return l.cells and l.cells[id] end
			col.value = col.value or function(l)
				local key = l.keys and l.keys[id]
				if key ~= nil then return key end
				local v = col.text(l)
				return tonumber(v) or v
			end
			out[i] = col
		end
		return out
	end

	local function tableFor(block)
		local list = s.pool[block.key]
		if not list then list = {} s.pool[block.key] = list end
		local t = list[block.n]
		if t then return t end
		local spec = opts.tables[block.key]
		t = Widgets.DataTable(s, columnsOf(spec), { rowHeight = tableRow, pool = 1, maxPool = 1,
			memory = spec.memory, onRowClick = spec.onRowClick, isSelected = spec.isSelected, rowSetup = spec.rowSetup,
			rowUpdate = spec.rowUpdate, noScrollbar = true,
			onWheel = function(delta) s:Scroll(-delta * (opts.wheelStep or 3)) end,
			onSorted = function() s:Draw() end })
		list[block.n] = t
		return t
	end

	function s:Table(key, n)
		local t = self.pool[key] and self.pool[key][n or 1]
		return t and t:IsShown() and t or nil
	end

	function s:Tables()
		local out = {}
		for _, list in pairs(self.pool) do
			for _, t in ipairs(list) do if t:IsShown() then out[#out + 1] = t end end
		end
		return out
	end

	-- The first line shown at the very end of the sheet: the lines after it fill the height.
	function s:MaxOffset()
		local room, used, counted = height(), 0, {}
		for i = #self.data, 1, -1 do
			local block, cost = blocks[i], rowH
			if block then
				cost = tableRow
				if not counted[block] then cost = cost + HEAD + GAP counted[block] = true end
			end
			if used + cost > room then return min(i, #self.data - 1) end
			used = used + cost
		end
		return 0
	end

	function s:Draw()
		local room, y, i, texts = height(), 0, self.offset + 1, 0
		local shown = {}
		while i <= #self.data do
			local line, block = self.data[i], blocks[i]
			if block then
				local fit = floor((room - y - HEAD - 1) / tableRow)
				if fit < 1 then break end
				local visible = min(block.last - i + 1, fit)
				local t = tableFor(block)
				local x = opts.indent and opts.indent(line) or 0
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
				t:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -y)
				t:SetHeight(HEAD + visible * tableRow + 1)
				local id, desc = Widgets.SortMemory.Get(opts.tables[block.key].memory)
				if id then t:SetSortMark(id, desc) end
				t.window = visible
				t:SetData(block.rows, true)
				t:SetWindow(visible, i - block.first)
				t:Show()
				shown[t] = true
				y = y + HEAD + visible * tableRow + 1 + GAP
				i = i + visible
				if i <= block.last then break end
			else
				if y + rowH > room then break end
				texts = texts + 1
				local fs = self.lines[texts]
				if not fs then
					fs = Widgets.Text(self, "Body", "text-1", "LEFT")
					fs:SetWordWrap(false)
					self.lines[texts] = fs
				end
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", self, "TOPLEFT", opts.indent and opts.indent(line) or 0, -y)
				fs:SetPoint("RIGHT", self, "RIGHT", 0, 0)
				fs:SetText(line.text or "")
				if opts.paint then opts.paint(fs, line) end
				fs:Show()
				local hit = self.hits[texts]
				if line.tip and not hit then
					hit = CreateFrame("Frame", nil, self)
					hit:SetAllPoints(fs)
					hit:EnableMouse(true)
					Widgets.Tooltip.Attach(hit, function(h) return h.tip end, "RIGHT")
					self.hits[texts] = hit
				end
				if hit then
					hit.tip = line.tip
					hit:SetShown(line.tip ~= nil)
				end
				y = y + rowH
				i = i + 1
			end
		end
		for n = texts + 1, #self.lines do
			self.lines[n]:Hide()
			if self.hits[n] then self.hits[n]:Hide() end
		end
		for _, list in pairs(self.pool) do
			for _, t in ipairs(list) do if not shown[t] then t:Hide() end end
		end
	end

	function s:SetLines(list)
		self.data = list or {}
		segment()
		self.offset = max(0, min(self.offset, self:MaxOffset()))
		self:Draw()
	end

	function s:Scroll(delta)
		local target = max(0, min(self.offset + delta, self:MaxOffset()))
		if target == self.offset then return false end
		self.offset = target
		self:Draw()
		return true
	end

	s:SetScript("OnSizeChanged", function() s:SetLines(s.data) end)
	return s
end

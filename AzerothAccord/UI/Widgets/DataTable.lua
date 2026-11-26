-- Widget kit, part 3: DataTable, the table of docs/specs/ui-style.md §3 (M6.11): a header on surface-2 OUTSIDE the list,
-- sortable columns (the sorted one in accent-text with an arrow), fixed and flexible column widths, and rows recycled from a
-- pool (a fixed number of row frames that are re-filled while the list scrolls with the mouse wheel). Lua 5.1; ordinary
-- frames. Blizzard's ScrollBox is not used: like Finland Dragon Credit Points (UI/Widgets/DataTable.lua, same owner,
-- GPL-3.0, ADR 0021) the table is its own pool, which behaves the same on every client and needs no fallback.
-- Budget (a 1000-member roster, SPEC-09): :SetData / :SortBy / scrolling touch at most `pool` rows and create no region;
-- a sort computes each row's key once and sorts an index list. The pool grows only when the window gets taller.
--
-- columns: { { id, title (translated), width? (fixed, in points), flex? (share of the free width), align? "LEFT" | "RIGHT" |
--   "CENTER", sortable? (default true), mono? (numbers), text = function(data) -> string, token? = function(data) -> token,
--   value? = function(data) -> sort key (default: the text), render? = function(cell, data, row) (custom cell) } }
-- opts: { rowHeight (30), headerHeight (28), pool (rows made, 40), maxPool (100), emptyText, onRowClick(data, row),
--   rowSetup(row) (a row is created), rowUpdate(row, data) (a row is filled),
--   onSort(id) (M6.13: the CALLER sorts: a click on a header calls it instead of sorting, :SetData keeps the order it is
--   given and :SetSortMark paints the arrow; the Roster sorts its rows in its own model, grouped by account) }
-- Methods: :SetData(list, keepOffset?), :SortBy(id, descending), :SetSortMark(id, descending), :Refresh(), :SetOffset(n), :VisibleRows(),
--   :GetData(), :GetSort(), :SetEmptyText(text), :Capacity(), :Layout(), :SetColumns(columns) (M6.13: another set of
--   columns, e.g. the Roster's column chooser; call :SetData or :Refresh after it).
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme, Assets = ns.Widgets, ns.Theme, ns.Assets

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local function textOf(col, data)
	local v = col.text and col.text(data)
	return v == nil and "" or tostring(v)
end

local function keyOf(col, data)
	if col.value then return col.value(data) end
	local v = textOf(col, data)
	return tonumber(v) or v:lower()
end

function Widgets.DataTable(parent, columns, opts)
	opts = opts or {}
	local rowH, headH = opts.rowHeight or 30, opts.headerHeight or 28
	local t = CreateFrame("Frame", nil, parent)
	t.columns, t.data, t.sorted, t.rows = columns, {}, {}, {}
	t.offset, t.rowH, t.headH = 0, rowH, headH
	t.sortId, t.sortDesc = nil, false

	if t.SetClipsChildren then t:SetClipsChildren(true) end   -- a header or a cell never shows outside the table
	t.head = CreateFrame("Frame", nil, t)
	t.head:SetHeight(headH)
	t.head:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
	t.head:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
	t.head.fill = Theme.Slice(t.head, "rr_fill_8", "surface-2", "BACKGROUND")
	t.head.fill:SetAllPoints(t.head)
	t.list = CreateFrame("Frame", nil, t)
	t.list:SetPoint("TOPLEFT", t.head, "BOTTOMLEFT", 0, -2)
	t.list:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
	t.list:EnableMouseWheel(true)
	t.empty = Theme.NewText(t.list, "Body", "text-3")
	t.empty:SetJustifyH("LEFT")
	t.empty:SetPoint("TOPLEFT", t.list, "TOPLEFT", 12, -12)
	t.empty:SetPoint("TOPRIGHT", t.list, "TOPRIGHT", -12, -12)   -- a long message wraps
	t.empty:SetText(opts.emptyText or "")

	-- a thin scroll indicator on the right edge (it shows where the window is in a long list; the wheel scrolls)
	t.scroll = CreateFrame("Frame", nil, t.list)
	t.scroll:SetWidth(4)
	t.scroll:SetPoint("TOPRIGHT", t.list, "TOPRIGHT", -2, -2)
	t.scroll:SetPoint("BOTTOMRIGHT", t.list, "BOTTOMRIGHT", -2, 2)
	t.scroll.track = t.scroll:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(t.scroll.track, "border-subtle")
	t.scroll.track:SetAllPoints(t.scroll)
	t.scroll.thumb = t.scroll:CreateTexture(nil, "ARTWORK")
	Theme.Fill(t.scroll.thumb, "border-strong")
	t.scroll:Hide()

	-- the column positions: the fixed ones keep their width, the flexible ones share what is left. When the fixed widths do
	-- not fit (a narrow window, many columns: found in game, 2026-11-26), every fixed column shrinks by the same share,
	-- down to MIN_SHRINK of its width, each flexible one keeps FLEX_MIN, and the texts are cut with dots; what still does
	-- not fit is clipped at the table's edge (never drawn outside the window).
	local FLEX_MIN, MIN_SHRINK = 60, 0.45
	local function widths()
		local total = (t:GetWidth() or 0) > 50 and t:GetWidth() or 800
		local fixed, flex, flexCount = 0, 0, 0
		for _, c in ipairs(columns) do
			if c.width then fixed = fixed + c.width else flex = flex + (c.flex or 1) flexCount = flexCount + 1 end
		end
		local avail = max(total - 16, 0)
		local k = 1
		if fixed > 0 and fixed + flexCount * FLEX_MIN > avail then
			k = max(MIN_SHRINK, (avail - flexCount * FLEX_MIN) / fixed)
		end
		local free = max(avail - floor(fixed * k), flexCount * FLEX_MIN)
		local out, x = {}, 8
		for i, c in ipairs(columns) do
			local w = c.width and floor(c.width * k) or (flex > 0 and max(FLEX_MIN, floor(free * (c.flex or 1) / flex)) or 0)
			out[i] = { x = x, w = w }
			x = x + w
		end
		t.shrink = k
		return out
	end

	local function place(fs, frame, col, pos)
		fs:ClearAllPoints()
		fs:SetWidth(max(pos.w - 8, 1))
		fs:SetJustifyH(col.align or "LEFT")
		fs:SetPoint("LEFT", frame, "LEFT", pos.x, 0)
	end

	-- header: a button per column; the label sits where the cells' text sits, the arrow of the sorted column next to it
	t.heads = {}
	local function makeHead(i)
		local b = CreateFrame("Button", nil, t.head)
		b:SetHeight(headH)
		b.label = Theme.NewText(b, "Th", "text-3")
		b.arrow = b:CreateTexture(nil, "OVERLAY")
		b.arrow:SetTexture(Assets.textures.icons.path)
		b.arrow:SetSize(10, 10)
		Theme.Tint(b.arrow, "accent-text")
		b.arrow:Hide()
		b.index = i
		t.heads[i] = b
		return b
	end
	local function setHead(b, c)
		b.col = c
		-- a column that says sortable = false has no click at all
		b:SetScript("OnClick", c.sortable ~= false and function()
			if opts.onSort then opts.onSort(c.id) else t:SortBy(c.id) end
		end or nil)
		b.label:SetText((c.title or ""):upper())
		b:Show()
	end
	for i, c in ipairs(columns) do setHead(makeHead(i), c) end

	local function placeHead(b, col, pos)
		b:ClearAllPoints()
		b:SetPoint("LEFT", t.head, "LEFT", pos.x, 0)
		b:SetWidth(max(pos.w - 4, 1))
		b.label:ClearAllPoints()
		b.arrow:ClearAllPoints()
		local align = col.align or "LEFT"
		if align == "RIGHT" then
			b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
			b.arrow:SetPoint("RIGHT", b.label, "LEFT", -3, 0)
		elseif align == "CENTER" then
			b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
			b.arrow:SetPoint("LEFT", b.label, "RIGHT", 3, 0)
		else
			b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
			b.arrow:SetPoint("LEFT", b.label, "RIGHT", 3, 0)
		end
	end

	function t:Layout()
		local pos = widths()
		self.pos = pos
		for i, b in ipairs(self.heads) do if columns[i] then placeHead(b, columns[i], pos[i]) end end
		for _, r in ipairs(self.rows) do
			for i, fs in ipairs(r.cells) do if columns[i] then place(fs, r, columns[i], pos[i]) end end
		end
	end

	-- the cells a row needs for the current columns (created once, re-fonted when a column is mono or not; extra cells hide)
	function t.ensureCells(r)
		for ci, c in ipairs(columns) do
			local fs = r.cells[ci]
			if not fs then
				fs = Theme.NewText(r, c.mono and "Mono" or "Body", "text-1")
				-- one line: a long text (a Forever full name "Name Surname-Realm") is cut with dots, never wrapped; the
				-- row's tooltip shows it whole (SPEC-11 §6.6)
				if fs.SetWordWrap then fs:SetWordWrap(false) end
				if fs.SetMaxLines then fs:SetMaxLines(1) end
				r.cells[ci] = fs
			else
				fs:SetFontObject(Theme.Font(c.mono and "Mono" or "Body"))
				fs:Show()
			end
		end
		for ci = #columns + 1, #r.cells do r.cells[ci]:Hide() end
	end

	-- The whole texts of the cells of row `r` that the client cut with dots (FontString:IsTruncated), for its tooltip.
	function t.CutTexts(r)
		local out = {}
		for ci, c in ipairs(columns) do
			local fs = r.cells[ci]
			if fs and not c.render and fs.IsTruncated and fs:IsTruncated() and r.data then out[#out + 1] = textOf(c, r.data) end
		end
		return out
	end

	local function newRow(i)
		local r = CreateFrame("Button", nil, t.list)
		r:SetHeight(rowH)
		r:SetPoint("TOPLEFT", t.list, "TOPLEFT", 0, -(i - 1) * rowH)
		r:SetPoint("TOPRIGHT", t.list, "TOPRIGHT", 0, -(i - 1) * rowH)
		r.hover = r:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(r.hover, "surface-2", 0)
		r.hover:SetAllPoints(r)
		r.line = r:CreateTexture(nil, "BORDER")
		Theme.Fill(r.line, "border-subtle")
		r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
		r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
		r.line:SetHeight(Theme.Px(1))
		r.cells = {}
		t.ensureCells(r)
		r:SetScript("OnEnter", function(self)
			Theme.Fill(self.hover, "surface-2", 1)
			local cut = t.CutTexts(self)
			if #cut > 0 and Widgets.Tooltip then
				Widgets.Tooltip.Show(self, cut)
				self.cutTip = true
			end
		end)
		r:SetScript("OnLeave", function(self)
			Theme.Fill(self.hover, "surface-2", 0)
			if self.cutTip and Widgets.Tooltip then Widgets.Tooltip.Hide() end
			self.cutTip = nil
		end)
		r:SetScript("OnClick", function(self) if opts.onRowClick and self.data then opts.onRowClick(self.data, self) end end)
		if t.pos then for ci, fs in ipairs(r.cells) do if columns[ci] then place(fs, r, columns[ci], t.pos[ci]) end end end
		if opts.rowSetup then opts.rowSetup(r) end
		r:Hide()
		return r
	end
	for i = 1, opts.pool or 40 do t.rows[i] = newRow(i) end

	-- The pool grows only when the table gets taller than its rows (a resize, never while it is filled).
	local function grow()
		local h = t.list:GetHeight() or 0
		local want = min(ceil(h / rowH), opts.maxPool or 100)
		for i = #t.rows + 1, want do t.rows[i] = newRow(i) end
	end

	function t:Capacity()
		local h = self.list:GetHeight() or 0
		if h < rowH then h = rowH * 14 end
		return min(#self.rows, max(floor(h / rowH), 1))
	end

	-- the sorted column's title in accent-text with the arrow, the others text-3 without
	local function paintSort(id, descending)
		for i, b in ipairs(t.heads) do
			local active = columns[i] ~= nil and columns[i].id == id
			Theme.Text(b.label, active and "accent-text" or "text-3")
			b.arrow:SetShown(active)
			if active then b.arrow:SetTexCoord(Assets.IconCoords(descending and "arrow_down" or "arrow_up")) end
		end
	end

	-- Paints the sort arrow without sorting (the caller sorts, opts.onSort). Returns false for an unknown column.
	function t:SetSortMark(id, descending)
		for _, c in ipairs(columns) do
			if c.id == id then
				self.sortId, self.sortDesc = id, descending and true or false
				paintSort(id, self.sortDesc)
				return true
			end
		end
		self.sortId, self.sortDesc = nil, false
		paintSort(nil, false)
		return false
	end

	function t:SortBy(id, descending)
		local col
		for _, c in ipairs(columns) do if c.id == id then col = c end end
		if not col then return false end
		if descending == nil then descending = (self.sortId == id) and not self.sortDesc or false end
		self.sortId, self.sortDesc = id, descending
		if opts.onSort then
			paintSort(id, descending)
			return true
		end
		local order = {}
		for i, d in ipairs(self.data) do order[i] = { d = d, i = i, k = keyOf(col, d) } end
		table.sort(order, function(a, b)
			if a.k ~= b.k then
				local ta, tb = type(a.k), type(b.k)
				local less
				if ta ~= tb then less = ta == "number" else less = a.k < b.k end
				if descending then return not less end
				return less
			end
			return a.i < b.i
		end)
		self.sorted = {}
		for i, o in ipairs(order) do self.sorted[i] = o.d end
		paintSort(id, descending)
		self.offset = 0
		self:Refresh()
		return true
	end

	-- Another set of columns (the cells and the header buttons are reused, the extra ones hide).
	function t:SetColumns(cols)
		columns = cols or {}
		self.columns = columns
		for i, c in ipairs(columns) do setHead(self.heads[i] or makeHead(i), c) end
		for i = #columns + 1, #self.heads do self.heads[i]:Hide() end
		for _, r in ipairs(self.rows) do t.ensureCells(r) end
		if self.sortId and not self:SetSortMark(self.sortId, self.sortDesc) then self.sortId = nil end
		self:Layout()
	end

	function t:GetSort() return self.sortId, self.sortDesc end
	function t:GetData() return self.sorted end

	function t:SetData(list, keepOffset)
		self.data = list or {}
		local offset = self.offset
		if self.sortId and not opts.onSort then
			self:SortBy(self.sortId, self.sortDesc)
			if keepOffset then self:SetOffset(offset) end
		else
			self.sorted = {}
			for i, d in ipairs(self.data) do self.sorted[i] = d end
			if not (opts.onSort or keepOffset) then self.offset = 0 end   -- a caller that sorts keeps the place in its list (Refresh clamps it)
			self:Refresh()
		end
	end

	function t:SetOffset(n)
		local top = max(#self.sorted - self:Capacity(), 0)
		self.offset = min(max(n, 0), top)
		self:Refresh()
	end

	local function paintScroll(total, cap)
		local s = t.scroll
		if total <= cap then s:Hide(); return end
		local h = (t.list:GetHeight() or 0) - 4
		if h <= 0 then h = cap * rowH end
		local size = max(h * cap / total, 12)
		local top = (h - size) * (t.offset / max(total - cap, 1))
		s.thumb:ClearAllPoints()
		s.thumb:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -top)
		s.thumb:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, -top)
		s.thumb:SetHeight(size)
		s:Show()
	end

	function t:Refresh()
		if not self.pos then self:Layout() end
		local cap = self:Capacity()
		self.offset = min(self.offset, max(#self.sorted - cap, 0))
		for i, r in ipairs(self.rows) do
			local data = i <= cap and self.sorted[self.offset + i] or nil
			r.data = data
			if data then
				for ci, c in ipairs(columns) do
					local fs = r.cells[ci]
					if c.render then
						c.render(fs, data, r)
					else
						fs:SetText(textOf(c, data))
						Theme.Text(fs, c.token and c.token(data) or "text-1")
					end
				end
				if opts.rowUpdate then opts.rowUpdate(r, data) end
				r:Show()
			else
				r:Hide()
			end
		end
		self.empty:SetShown(#self.sorted == 0)
		paintScroll(#self.sorted, cap)
	end

	function t:VisibleRows()
		local out = {}
		for _, r in ipairs(self.rows) do if r:IsShown() then out[#out + 1] = r end end
		return out
	end

	function t:SetEmptyText(text) self.empty:SetText(text or "") end

	t.list:SetScript("OnMouseWheel", function(_, delta) t:SetOffset(t.offset - delta * 3) end)
	t:SetScript("OnSizeChanged", function() grow(); t:Layout(); t:Refresh() end)
	t:Layout()
	return t
end

-- Bank log, donations and money modes of the Bank view (SPEC-08 BANK-10..BANK-12, SPEC-04 §2). Lua 5.1.
--
-- Log        the merged log (Data/BankLog.lua): when, which tab, who, what; newest first. The panel search filters by name or
--            item name.
-- Donations  the deposits of money and items per account (BANK-11) over 30 days, 365 days or all the entries held, sorted by
--            gold or by items. Visible to every member (SPEC-10 Q5 proposal: BankLog.DONATIONS_VISIBLE_TO).
-- Money      the guild's money over the last 30 or 90 days as bars (BANK-12), from the money records that reached this client.
--
-- Rows are plain functions (LogRows, DonationRows, tested offline); the frames only draw them.
local ADDON_NAME, ns = ...
ns = ns or {}
local Mode = {}
ns.BankLogView, ns.modules = Mode, ns.modules or {}
ns.modules.BankLogView = Mode

local View = ns.BankView
if not View then return end
local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, floor, max, min = type, ipairs, pairs, tostring, math.floor, math.max, math.min
local concat = table.concat

Mode.window = "d30"
Mode.sort = "gold"
Mode.days = 30

local function lower(s) return type(s) == "string" and s:lower() or "" end
local function now() return ns.Compat and ns.Compat.ServerTime() or 0 end

---------------------------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------------------------
-- The text of a kind of entry ("deposit" -> "Deposit"); a kind the addon does not know is shown as the game gave it.
function Mode.KindText(kind)
	local key = "BANKLOG_KIND_" .. tostring(kind):upper()
	return L[key] ~= key and L[key] or tostring(kind)
end

-- The merged log as rows: { when (text), tab, tabName, name, kind, text, detail, t }. opts.search filters by name, item
-- name or kind text.
function Mode.LogRows(opts)
	opts = opts or {}
	local Log, Bank = ns.BankLog, ns.Bank
	if not (Log and Bank) then return {} end
	local tabNames = {}
	for _, t in ipairs(Bank:Tabs()) do tabNames[t.tab] = t.name end
	local query = lower(opts.search)
	local out = {}
	for _, e in ipairs(Log:Entries()) do
		local detail
		if e.tab == Log.MONEY_TAB then
			detail = View.MoneyText(e.count)
		else
			local info = View.ItemInfo(e.itemID)
			detail = (info.name or L["BANK_ITEM_LOADING"]:format(e.itemID)) .. (e.count > 1 and (" x" .. e.count) or "")
		end
		local kind = Mode.KindText(e.kind)
		if query == "" or lower(e.name):find(query, 1, true) or lower(detail):find(query, 1, true) or lower(kind):find(query, 1, true) then
			out[#out + 1] = {
				t = e.t, when = ns.Shell and ns.Shell.Ago(max(0, now() - e.t)) or "", tab = e.tab,
				tabName = e.tab == Log.MONEY_TAB and L["BANKLOG_MONEY"] or (tabNames[e.tab] or L["BANK_TAB_N"]:format(e.tab)),
				name = e.name, kind = e.kind, text = kind, detail = detail,
			}
		end
	end
	return out
end

function Mode.DonationRows()
	local Log = ns.BankLog
	if not (Log and Log.DonationsVisible()) then return {} end
	return Log:Donations({ window = Mode.window, sort = Mode.sort })
end

---------------------------------------------------------------------------------------------------------------------
-- A list mode: virtual rows with columns
---------------------------------------------------------------------------------------------------------------------
local function visibleRows(area)
	local h = area and area:GetHeight() or 0
	if not h or h < View.ROW_HEIGHT then return View.DEFAULT_ROWS end
	return max(1, floor(h / View.ROW_HEIGHT))
end

-- def = { columns = { { key, title, width, font (a Theme font id), token, justify, value = function(d) -> sort key }, ... },
--   rows() -> list, fill(row, data), empty, sort = { key, desc } (the first order), renumber (place = position after sorting),
--   onSort(key, desc) (told when a header is clicked) }
-- A header row over the columns, in the DataTable's look: a click on a title sorts by that column, a second click reverses;
-- the sorted title is in accent-text with an arrow (owner, 2026-11-27: headers that sort instead of sorting buttons).
local HEAD_H = 28
local function sortRows(rows, def, key, desc)
	local col
	for _, c in ipairs(def.columns) do if c.key == key then col = c end end
	if not col then return rows end
	local value = col.value or function(d) return d[key] end
	local keyed = {}
	for i, d in ipairs(rows) do
		local v = value(d)
		if type(v) == "string" then v = v:lower() end
		keyed[i] = { d = d, v = v, i = i }
	end
	table.sort(keyed, function(a, b)
		if a.v == nil or b.v == nil then
			if (a.v == nil) ~= (b.v == nil) then return b.v == nil end   -- nothing to sort by: last
			return a.i < b.i
		end
		if type(a.v) ~= type(b.v) then a.v, b.v = tostring(a.v), tostring(b.v) end
		if a.v ~= b.v then
			if desc then return a.v > b.v end
			return a.v < b.v
		end
		return a.i < b.i
	end)
	local out = {}
	for i, k in ipairs(keyed) do out[i] = k.d end
	return out
end
Mode.SortRows = sortRows

local function listMode(def)
	local mode = { sortKey = def.sort and def.sort.key, sortDesc = def.sort and def.sort.desc or false }

	local function header(f, top)
		local head = CreateFrame("Frame", nil, f)
		head:SetHeight(HEAD_H)
		head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
		head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
		head.fill = Theme.Slice(head, "rr_fill_8", "surface-2", "BACKGROUND")
		head.fill:SetAllPoints(head)
		head.buttons = {}
		local x = 6
		for _, c in ipairs(def.columns) do
			local b = CreateFrame("Button", nil, head)
			b:SetHeight(HEAD_H)
			b:SetPoint("LEFT", head, "LEFT", x, 0)
			if c.width then b:SetWidth(c.width) else b:SetPoint("RIGHT", head, "RIGHT", -4, 0) end
			b.label = Widgets.Text(b, "Th", "text-3", c.justify or "LEFT")
			b.label:SetAllPoints(b)
			b.label:SetText((c.title or ""):upper())
			b.arrow = b:CreateTexture(nil, "OVERLAY")
			b.arrow:SetTexture(ns.Assets.textures.icons.path)
			b.arrow:SetSize(10, 10)
			b.arrow:Hide()
			b.key, b.justify = c.key, c.justify or "LEFT"
			b:SetScript("OnClick", function()
				if mode.sortKey == c.key then mode.sortDesc = not mode.sortDesc
				else mode.sortKey, mode.sortDesc = c.key, c.descFirst == true end
				View.offset = 0
				if def.onSort then def.onSort(mode.sortKey, mode.sortDesc) end
				View:Redraw()
			end)
			head.buttons[#head.buttons + 1] = b
			x = x + (c.width or 0) + 8
		end
		f.head = head
		return head
	end

	local function paintHeader(f)
		for _, b in ipairs(f.head and f.head.buttons or {}) do
			local on = b.key == mode.sortKey
			Theme.Text(b.label, on and "accent-text" or "text-3")
			if on then
				b.arrow:SetTexCoord(ns.Assets.IconCoords(mode.sortDesc and "arrow_down" or "arrow_up"))
				Theme.Tint(b.arrow, "accent-text")
				b.arrow:ClearAllPoints()
				local w = b.label:GetStringWidth() or 0
				if b.justify == "RIGHT" then b.arrow:SetPoint("RIGHT", b, "RIGHT", -w - 4, 0)
				else b.arrow:SetPoint("LEFT", b, "LEFT", w + 4, 0) end
				b.arrow:Show()
			else
				b.arrow:Hide()
			end
		end
	end
	mode.paintHeader = paintHeader
	local function newRow(area, i)
		local row = CreateFrame("Button", nil, area)
		row:SetHeight(View.ROW_HEIGHT)
		row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
		row.cells = {}
		local prev
		for n, c in ipairs(def.columns) do
			local fs = Widgets.Text(row, c.font or "Body", c.token or "text-1", c.justify or "LEFT")
			if prev then fs:SetPoint("LEFT", prev, "RIGHT", 8, 0) else fs:SetPoint("LEFT", row, "LEFT", 6, 0) end
			if c.width then fs:SetWidth(c.width) else fs:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
			row.cells[c.key] = fs
			prev = fs
		end
		Widgets.RowHover(row)
		area.rows[i] = row
		return row
	end

	function mode.build(f)
		local top = 4
		if def.toolbar then top = def.toolbar(f) end
		local head = header(f, top)
		local area = CreateFrame("Frame", nil, f)
		area:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
		area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		area:SetClipsChildren(true)
		area:EnableMouseWheel(true)
		area:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
		area:SetScript("OnSizeChanged", function() View:Redraw() end)
		area.rows = {}
		f.area = area
		f.message = Widgets.Text(f, "Body", "text-3", "CENTER")
		f.message:SetPoint("CENTER", area, "CENTER", 0, 0)
		f.message:SetWidth(380)
	end

	function mode.refresh(f)
		if def.beforeRefresh then def.beforeRefresh(f) end
		local rows = def.rows()
		if mode.sortKey then rows = sortRows(rows, def, mode.sortKey, mode.sortDesc) end
		if def.renumber then for i, d in ipairs(rows) do d.place = i end end
		paintHeader(f)
		View.rowsShown = rows
		local total, visible = #rows, visibleRows(f.area)
		View.offset = max(0, min(View.offset or 0, max(0, total - visible)))
		local drawn = max(0, min(visible + 1, total - View.offset))
		for i = 1, drawn do
			local row = f.area.rows[i] or newRow(f.area, i)
			row.data = rows[View.offset + i]
			def.fill(row, row.data)
			row:Show()
		end
		for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
		if total == 0 then
			f.message:SetText(def.empty())
			f.message:Show()
		else
			f.message:Hide()
		end
		return total
	end
	return mode
end

---------------------------------------------------------------------------------------------------------------------
-- Log
---------------------------------------------------------------------------------------------------------------------
local logMode = listMode({
	columns = {
		{ key = "when", title = L["BANKLOG_COL_WHEN"], width = 80, font = "MonoSmall", token = "text-3", value = function(d) return d.t end, descFirst = true },
		{ key = "tab", title = L["BANKLOG_COL_TAB"], width = 90, font = "Small", token = "text-3", value = function(d) return d.tabName end },
		{ key = "name", title = L["BANKLOG_COL_WHO"], width = 140, font = "BodyMedium" },
		{ key = "kind", title = L["BANKLOG_COL_WHAT"], width = 90, font = "Small", value = function(d) return d.text end },
		{ key = "detail", title = L["BANKLOG_COL_DETAIL"], token = "text-2" } },
	sort = { key = "when", desc = true },
	rows = function() return Mode.LogRows({ search = View.search }) end,
	fill = function(row, d)
		row.cells.when:SetText(d.when); row.cells.tab:SetText(d.tabName); row.cells.name:SetText(d.name)
		row.cells.kind:SetText(d.text)
		Theme.Text(row.cells.kind, d.kind == "withdraw" and "err" or (d.kind == "deposit" and "ok" or "text-3"))
		row.cells.detail:SetText(d.detail)
	end,
	empty = function() return View.search ~= "" and L["BANK_NO_MATCH"] or L["BANKLOG_EMPTY"] end,
})
View.AddMode("log", { label = L["BANK_MODE_LOG"], order = 30, build = logMode.build, refresh = logMode.refresh, search = true })

---------------------------------------------------------------------------------------------------------------------
-- Donations
---------------------------------------------------------------------------------------------------------------------
-- A row of chips for one choice of the mode (the period, the order): f.picks[key] = { buttons, get, labels, bar }.
local function pickRow(f, key, labels, get, set, anchor, dx)
	f.picks = f.picks or {}
	local bar = Widgets.ChipRow(f, function(id) set(id); View:Redraw() end, { height = 26 })
	if anchor then bar:SetPoint("LEFT", anchor, "RIGHT", dx or 24, 0) else bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) end
	local items = {}
	for i, item in ipairs(labels) do items[i] = { id = item[1], text = item[2] } end
	bar:SetItems(items, get())
	bar:SetWidth(bar.width)
	for i, b in ipairs(bar.buttons) do b.value = labels[i][1] end
	f.picks[key] = { buttons = bar.buttons, get = get, labels = labels, bar = bar }
	return bar
end

local function refreshPicks(f)
	for _, pick in pairs(f.picks or {}) do pick.bar:Select(pick.get()) end
end

local donationMode = listMode({
	toolbar = function(f)
		-- the period is a choice of what to count, so it stays as chips; the order is the headers' (2026-11-27)
		pickRow(f, "window", { { "d30", L["BANKLOG_D30"] }, { "d365", L["BANKLOG_D365"] }, { "all", L["BANKLOG_ALL"] } },
			function() return Mode.window end, function(v) Mode.window = v View.offset = 0 end)
		return 36
	end,
	beforeRefresh = refreshPicks,
	columns = {
		{ key = "place", title = "#", width = 28, font = "MonoSmall", token = "text-3", justify = "RIGHT" },
		{ key = "name", title = L["BANKLOG_COL_WHO"], width = 160, font = "BodyMedium" },
		{ key = "gold", title = L["BANKLOG_COL_GOLD"], width = 120, font = "MonoMedium", token = "accent-text", justify = "RIGHT", descFirst = true },
		{ key = "items", title = L["BANKLOG_COL_ITEMS"], width = 90, font = "Mono", justify = "RIGHT", descFirst = true },
		{ key = "deposits", title = L["BANKLOG_COL_DEPOSITS"], font = "Small", token = "text-3", descFirst = true } },
	sort = { key = "gold", desc = true },
	renumber = true,
	onSort = function(key) if key == "gold" or key == "items" then Mode.sort = key end end,
	rows = Mode.DonationRows,
	fill = function(row, d)
		row.cells.place:SetText(tostring(d.place))
		row.cells.name:SetText(d.name); Widgets.PaintName(row.cells.name, d.classFile)
		row.cells.gold:SetText(d.gold > 0 and View.MoneyText(d.gold) or "-")
		row.cells.items:SetText(d.items > 0 and L["BANKLOG_ITEMS_N"]:format(d.items) or "-")
		row.cells.deposits:SetText(L["BANKLOG_DEPOSITS"]:format(d.deposits))
	end,
	empty = function() return L["BANKLOG_NO_DONATIONS"] end,
})
View.AddMode("donations", {
	label = L["BANK_MODE_DONATIONS"], order = 40, build = donationMode.build, refresh = donationMode.refresh,
	available = function() return ns.BankLog ~= nil and ns.BankLog.DonationsVisible() end,
})

---------------------------------------------------------------------------------------------------------------------
-- Money over time
---------------------------------------------------------------------------------------------------------------------
Mode.BARS = 30

-- The money log as rows: { t, when, name, kind, text, amount }. The chart of the guild's money sits over the table.
function Mode.MoneyRows()
	local Log = ns.BankLog
	if not Log then return {} end
	local out = {}
	for _, e in ipairs(Log:Entries({ tab = Log.MONEY_TAB })) do
		out[#out + 1] = { t = e.t, when = ns.Shell and ns.Shell.Ago(max(0, now() - e.t)) or "", name = e.name, kind = e.kind,
			text = Mode.KindText(e.kind), amount = e.count }
	end
	return out
end

local CHART_H = 290
local function buildChart(f)
	f.card = Widgets.Card(f, { width = Mode.BARS * 14 + 48, height = CHART_H })
	f.card:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.title = Widgets.Text(f.card, "H2", "text-1", "LEFT")
	f.title:SetPoint("TOPLEFT", f.card, "TOPLEFT", 24, -18)
	f.title:SetPoint("RIGHT", f.card, "RIGHT", -24, 0)
	f.chart = CreateFrame("Frame", nil, f.card)
	f.chart:SetSize(Mode.BARS * 14, 180)
	f.chart:SetPoint("TOPLEFT", f.card, "TOPLEFT", 24, -72)
	f.chart.base = f.chart:CreateTexture(nil, "BORDER")
	Theme.Fill(f.chart.base, "border")
	f.chart.base:SetHeight(1)
	f.chart.base:SetPoint("BOTTOMLEFT", f.chart, "BOTTOMLEFT", 0, -1)
	f.chart.base:SetPoint("BOTTOMRIGHT", f.chart, "BOTTOMRIGHT", 0, -1)
	f.chart.bars = {}
	for i = 1, Mode.BARS do
		local t = f.chart:CreateTexture(nil, "ARTWORK")
		Theme.Fill(t, "accent")
		t:SetWidth(12)
		t:SetPoint("BOTTOMLEFT", f.chart, "BOTTOMLEFT", (i - 1) * 14, 0)
		f.chart.bars[i] = t
	end
	f.low = Widgets.Text(f.card, "MonoSmall", "text-3", "LEFT")
	f.low:SetPoint("TOPLEFT", f.chart, "BOTTOMLEFT", 0, -6)
	f.high = Widgets.Text(f.card, "MonoSmall", "text-3", "LEFT")
	f.high:SetPoint("BOTTOMLEFT", f.chart, "TOPLEFT", 0, 6)
	f.chartMessage = Widgets.Text(f.card, "Body", "text-3", "CENTER")
	f.chartMessage:SetPoint("CENTER", f.card, "CENTER", 0, 0)
	f.chartMessage:SetWidth(Mode.BARS * 14)
	return CHART_H + 12
end

-- The heights of the bars (0..1) for the series, plus the text of the range; nil without a single point.
function Mode.Chart(series)
	if not series or not series.max then return nil end
	local span = series.max - series.min
	local heights = {}
	for i = 1, series.n do
		local v = series.values[i]
		if v == nil then heights[i] = 0
		elseif span == 0 then heights[i] = 0.5
		else heights[i] = 0.1 + 0.9 * (v - series.min) / span end
	end
	return heights
end

local function drawChart(f)
	local series = ns.BankLog and ns.BankLog:MoneySeries(Mode.days, Mode.BARS)
	local heights = Mode.Chart(series)
	if not heights then
		f.chart:Hide(); f.low:Hide(); f.high:Hide(); f.title:Hide()
		f.chartMessage:SetText(L["BANKLOG_NO_MONEY"])
		f.chartMessage:Show()
		return
	end
	f.chartMessage:Hide(); f.chart:Show(); f.low:Show(); f.high:Show(); f.title:Show()
	f.title:SetText(L["BANKLOG_MONEY_TITLE"]:format(Mode.days))
	for i = 1, Mode.BARS do
		local bar = f.chart.bars[i]
		bar:SetHeight(max(1, floor(heights[i] * 180)))
		bar:SetShown(heights[i] > 0)
	end
	f.low:SetText(L["BANKLOG_LOW"]:format(View.MoneyText(series.min)))
	f.high:SetText(L["BANKLOG_HIGH"]:format(View.MoneyText(series.max)))
end

local moneyMode = listMode({
	toolbar = buildChart,
	beforeRefresh = drawChart,
	columns = {
		{ key = "when", title = L["BANKLOG_COL_WHEN"], width = 80, font = "MonoSmall", token = "text-3", value = function(d) return d.t end, descFirst = true },
		{ key = "name", title = L["BANKLOG_COL_WHO"], width = 160, font = "BodyMedium" },
		{ key = "kind", title = L["BANKLOG_COL_WHAT"], width = 110, font = "Small", value = function(d) return d.text end },
		{ key = "amount", title = L["BANKLOG_COL_AMOUNT"], width = 130, font = "MonoMedium", token = "accent-text", justify = "RIGHT", descFirst = true } },
	sort = { key = "when", desc = true },
	rows = Mode.MoneyRows,
	fill = function(row, d)
		row.cells.when:SetText(d.when); row.cells.name:SetText(d.name); row.cells.kind:SetText(d.text)
		Theme.Text(row.cells.kind, (d.kind == "withdraw" or d.kind == "repair") and "err" or (d.kind == "deposit" and "ok" or "text-3"))
		row.cells.amount:SetText(View.MoneyText(d.amount))
	end,
	empty = function() return L["BANKLOG_NO_MONEY"] end,
})

View.AddMode("money", { label = L["BANK_MODE_MONEY"], order = 50, build = moneyMode.build, refresh = moneyMode.refresh })

if ns.addon then
	ns.addon.BankLogView = Mode
	if ns.Bus then ns.Bus:On("BANK_CAPTURED", function() View:Changed() end) end
end

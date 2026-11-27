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
-- A list mode: a Widgets.DataTable (docs/specs/ui-style.md §9.9, M13.8)
---------------------------------------------------------------------------------------------------------------------
-- def = { columns (of the table), rows() -> list, empty() -> text, sort = { id, desc } (the first order), memory,
--   toolbar(frame) -> the table's top, beforeRefresh(frame), prepare(sorted), onSorted(id, desc) }
local function listMode(def)
	local mode = {}

	function mode.build(f)
		local top = 4
		if def.toolbar then top = def.toolbar(f) end
		f.table = Widgets.DataTable(f, def.columns, { rowHeight = View.ROW_HEIGHT, pool = 14, maxPool = 60,
			sort = def.sort, memory = def.memory, prepare = def.prepare, onSorted = def.onSorted })
		f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
		f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	end

	function mode.refresh(f)
		if def.beforeRefresh then def.beforeRefresh(f) end
		local rows = def.rows()
		f.table:SetEmptyText(def.empty())
		f.table:SetData(rows, true)
		View.rowsShown = f.table:GetData()
		return #rows
	end
	return mode
end

local function field(key) return function(d) return d[key] end end
local function muted() return "text-3" end

---------------------------------------------------------------------------------------------------------------------
-- Log
---------------------------------------------------------------------------------------------------------------------
local logMode = listMode({
	columns = {
		{ id = "when", title = L["BANKLOG_COL_WHEN"], width = 96, mono = true, text = field("when"), token = muted,
			value = field("t") },
		{ id = "tab", title = L["BANKLOG_COL_TAB"], width = 110, text = field("tabName"), token = muted },
		{ id = "name", title = L["BANKLOG_COL_WHO"], width = 150, text = field("name") },
		{ id = "kind", title = L["BANKLOG_COL_WHAT"], width = 110, text = field("text"),
			token = function(d) return d.kind == "withdraw" and "err" or (d.kind == "deposit" and "ok" or "text-3") end },
		{ id = "detail", title = L["BANKLOG_COL_DETAIL"], flex = 1, text = field("detail"),
			token = function() return "text-2" end },
	},
	sort = { id = "when", desc = true }, memory = "bank.log",
	rows = function() return Mode.LogRows({ search = View.search }) end,
	empty = function() return View.search ~= "" and L["BANK_NO_MATCH"] or L["BANKLOG_EMPTY"] end,
})
View.AddMode("log", { label = L["BANK_MODE_LOG"], order = 30, build = logMode.build, refresh = logMode.refresh, search = true })

---------------------------------------------------------------------------------------------------------------------
-- Donations
---------------------------------------------------------------------------------------------------------------------
-- A row of chips for one choice of the mode (the period, the order): f.picks[key] = { buttons, get, labels, bar }.
local function pickRow(f, key, labels, get, set, anchor, dx)
	f.picks = f.picks or {}
	local bar = Widgets.ChipRow(f, function(id) set(id); View:Redraw() end)
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
			function() return Mode.window end, function(v) Mode.window = v View:ResetScroll() end)
		return 40
	end,
	beforeRefresh = refreshPicks,
	columns = {
		-- the place in the order shown: it follows the sort, so it has none of its own
		{ id = "place", title = "#", width = 40, align = "RIGHT", mono = true, sortable = false, token = muted,
			text = function(d) return tostring(d.place or "") end },
		{ id = "name", title = L["BANKLOG_COL_WHO"], flex = 1, text = field("name"),
			render = function(cell, d) cell:SetText(d.name) Widgets.PaintName(cell, d.classFile) end },
		{ id = "gold", title = L["BANKLOG_COL_GOLD"], width = 140, align = "RIGHT", mono = true, value = field("gold"),
			text = function(d) return d.gold > 0 and View.MoneyText(d.gold) or "-" end,
			token = function() return "accent-text" end },
		{ id = "items", title = L["BANKLOG_COL_ITEMS"], width = 110, align = "RIGHT", mono = true, value = field("items"),
			text = function(d) return d.items > 0 and L["BANKLOG_ITEMS_N"]:format(d.items) or "-" end },
		{ id = "deposits", title = L["BANKLOG_COL_DEPOSITS"], width = 130, align = "RIGHT", value = field("deposits"),
			text = function(d) return L["BANKLOG_DEPOSITS"]:format(d.deposits) end, token = muted },
	},
	sort = { id = "gold", desc = true }, memory = "bank.donations",
	prepare = function(rows) for i, d in ipairs(rows) do d.place = i end end,
	onSorted = function(id)
		if id == "gold" or id == "items" then Mode.sort = id end
		View:Redraw()
	end,
	rows = Mode.DonationRows,
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
		{ id = "when", title = L["BANKLOG_COL_WHEN"], width = 96, mono = true, text = field("when"), token = muted,
			value = field("t") },
		{ id = "name", title = L["BANKLOG_COL_WHO"], flex = 1, text = field("name") },
		{ id = "kind", title = L["BANKLOG_COL_WHAT"], width = 140, text = field("text"), token = function(d)
			return (d.kind == "withdraw" or d.kind == "repair") and "err" or (d.kind == "deposit" and "ok" or "text-3")
		end },
		{ id = "amount", title = L["BANKLOG_COL_AMOUNT"], width = 150, align = "RIGHT", mono = true, value = field("amount"),
			text = function(d) return View.MoneyText(d.amount) end, token = function() return "accent-text" end },
	},
	sort = { id = "when", desc = true }, memory = "bank.money",
	rows = Mode.MoneyRows,
	empty = function() return L["BANKLOG_NO_MONEY"] end,
})

View.AddMode("money", { label = L["BANK_MODE_MONEY"], order = 50, build = moneyMode.build, refresh = moneyMode.refresh })

if ns.addon then
	ns.addon.BankLogView = Mode
	if ns.Bus then ns.Bus:On("BANK_CAPTURED", function() View:Changed() end) end
end

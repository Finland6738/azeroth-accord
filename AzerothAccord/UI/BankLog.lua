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
local L, W, Skin = ns.L, ns.Widgets, ns.Skin
local type, ipairs, pairs, tostring, floor, max, min = type, ipairs, pairs, tostring, math.floor, math.max, math.min
local concat = table.concat

Mode.window = "d30"
Mode.sort = "gold"
Mode.days = 30

local function lower(s) return type(s) == "string" and s:lower() or "" end
local function now() return ns.Compat and ns.Compat.ServerTime() or 0 end
local function classColor(classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

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

-- def = { columns = { { key, width, style, color, justify }, ... }, rows() -> list, fill(row, data, cells), empty }
local function listMode(def)
	local mode = {}
	local function newRow(area, i)
		local row = CreateFrame("Button", nil, area)
		row:SetHeight(View.ROW_HEIGHT)
		row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
		row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
		row.highlight:SetAllPoints(row)
		row.highlight:SetColorTexture(1, 1, 1, 0.08)
		row.cells = {}
		local prev
		for n, c in ipairs(def.columns) do
			local fs = W.Text(row, c.style or "body", c.color, c.justify or "LEFT")
			if prev then fs:SetPoint("LEFT", prev, "RIGHT", 8, 0) else fs:SetPoint("LEFT", row, "LEFT", 6, 0) end
			if c.width then fs:SetWidth(c.width) else fs:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
			row.cells[c.key] = fs
			prev = fs
		end
		area.rows[i] = row
		return row
	end

	function mode.build(f)
		local top = 4
		if def.toolbar then top = def.toolbar(f) end
		local area = W.Frame(f, 10, 10)
		area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
		area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 0)
		area:EnableMouseWheel(true)
		area:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
		area:SetScript("OnSizeChanged", function() View:Redraw() end)
		area.rows = {}
		f.area = area
		f.message = W.Text(f, "body", "grey", "CENTER")
		f.message:SetPoint("CENTER", area, "CENTER", 0, 0)
		f.message:SetWidth(380)
	end

	function mode.refresh(f)
		if def.beforeRefresh then def.beforeRefresh(f) end
		local rows = def.rows()
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
	columns = { { key = "when", width = 80, style = "small", color = "grey" }, { key = "tab", width = 90, style = "small", color = "grey" },
		{ key = "name", width = 120 }, { key = "kind", width = 90, style = "small" }, { key = "detail" } },
	rows = function() return Mode.LogRows({ search = View.search }) end,
	fill = function(row, d)
		row.cells.when:SetText(d.when); row.cells.tab:SetText(d.tabName); row.cells.name:SetText(d.name)
		row.cells.kind:SetText(d.text)
		row.cells.kind:SetTextColor(Skin.Color(d.kind == "withdraw" and "red" or (d.kind == "deposit" and "green" or "grey")))
		row.cells.detail:SetText(d.detail)
	end,
	empty = function() return View.search ~= "" and L["BANK_NO_MATCH"] or L["BANKLOG_EMPTY"] end,
})
View.AddMode("log", { label = L["BANK_MODE_LOG"], order = 30, build = logMode.build, refresh = logMode.refresh, search = true })

---------------------------------------------------------------------------------------------------------------------
-- Donations
---------------------------------------------------------------------------------------------------------------------
local function pickButton(f, key, labels, get, set, x)
	f.picks = f.picks or {}
	local buttons = {}
	for i, item in ipairs(labels) do
		local b = W.Button(f, { text = item[2], width = 96, height = 20, onClick = function() set(item[1]); View:Redraw() end })
		b:SetPoint("TOPLEFT", f, "TOPLEFT", x + (i - 1) * 100, -4)
		b.value = item[1]
		buttons[i] = b
	end
	f.picks[key] = { buttons = buttons, get = get, labels = labels }
end

local function refreshPicks(f)
	for _, pick in pairs(f.picks or {}) do
		for i, b in ipairs(pick.buttons) do
			local text = pick.labels[i][2]
			b:SetLabel(b.value == pick.get() and ("> " .. text .. " <") or text)
		end
	end
end

local donationMode = listMode({
	toolbar = function(f)
		pickButton(f, "window", { { "d30", L["BANKLOG_D30"] }, { "d365", L["BANKLOG_D365"] }, { "all", L["BANKLOG_ALL"] } },
			function() return Mode.window end, function(v) Mode.window = v View.offset = 0 end, 8)
		pickButton(f, "sort", { { "gold", L["BANKLOG_GOLD"] }, { "items", L["BANKLOG_ITEMS"] } },
			function() return Mode.sort end, function(v) Mode.sort = v View.offset = 0 end, 330)
		return 30
	end,
	beforeRefresh = refreshPicks,
	columns = { { key = "place", width = 28, style = "small", color = "grey", justify = "RIGHT" }, { key = "name", width = 160 },
		{ key = "gold", width = 120, color = "gold", justify = "RIGHT" }, { key = "items", width = 90, justify = "RIGHT" },
		{ key = "deposits", style = "small", color = "grey" } },
	rows = Mode.DonationRows,
	fill = function(row, d)
		row.cells.place:SetText(tostring(d.place))
		row.cells.name:SetText(d.name); row.cells.name:SetTextColor(classColor(d.classFile))
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
local money = {}

function money.build(f)
	f.title = W.Text(f, "small", "grey", "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
	f.title:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.chart = W.Frame(f, Mode.BARS * 14, 180)
	f.chart:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -50)
	f.chart.bars = {}
	for i = 1, Mode.BARS do
		local t = f.chart:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(Skin.Color("gold"))
		t:SetWidth(12)
		t:SetPoint("BOTTOMLEFT", f.chart, "BOTTOMLEFT", (i - 1) * 14, 0)
		f.chart.bars[i] = t
	end
	f.low = W.Text(f, "small", "grey", "LEFT")
	f.low:SetPoint("TOPLEFT", f.chart, "BOTTOMLEFT", 0, -4)
	f.high = W.Text(f, "small", "grey", "LEFT")
	f.high:SetPoint("BOTTOMLEFT", f.chart, "TOPLEFT", 0, 4)
	f.message = W.Text(f, "body", "grey", "CENTER")
	f.message:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.message:SetWidth(380)
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

function money.refresh(f)
	local series = ns.BankLog and ns.BankLog:MoneySeries(Mode.days, Mode.BARS)
	local heights = Mode.Chart(series)
	View.rowsShown = {}
	if not heights then
		f.chart:Hide(); f.low:Hide(); f.high:Hide(); f.title:Hide()
		f.message:SetText(L["BANKLOG_NO_MONEY"])
		f.message:Show()
		return 0
	end
	f.message:Hide(); f.chart:Show(); f.low:Show(); f.high:Show(); f.title:Show()
	f.title:SetText(L["BANKLOG_MONEY_TITLE"]:format(Mode.days))
	for i = 1, Mode.BARS do
		local bar = f.chart.bars[i]
		bar:SetHeight(max(1, floor(heights[i] * 180)))
		bar:SetShown(heights[i] > 0)
	end
	f.low:SetText(L["BANKLOG_LOW"]:format(View.MoneyText(series.min)))
	f.high:SetText(L["BANKLOG_HIGH"]:format(View.MoneyText(series.max)))
	return series.n
end

View.AddMode("money", { label = L["BANK_MODE_MONEY"], order = 50, build = money.build, refresh = money.refresh })

if ns.addon then
	ns.addon.BankLogView = Mode
	if ns.Bus then ns.Bus:On("BANK_CAPTURED", function() View:Changed() end) end
end

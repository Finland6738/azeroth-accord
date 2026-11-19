-- Bank view (SPEC-08 BANK-04, SPEC-04 §2). Lua 5.1.
--
-- The view shows the guild bank as the guild's addons last saw it (Data/Bank.lua: the newest snapshot of each tab that this
-- character's rank may see). It has modes, one button each in its toolbar; a mode is { label, order, available() -> bool,
-- build(frame), refresh(frame) } and later steps add theirs with View.AddMode (logs, donations, requests).
--
-- Tabs    the tab buttons (only the tabs this rank may see), the guild money, how old the tab is and who read it ("seen
--         2 h ago by Bob"), and the tab as the game draws it: 14 columns of 7 slots, an icon and a count, the item tooltip
--         on hover.
-- Items   one row per item over every visible tab: its total, and the tabs and counts it is in; the panel's search box
--         filters by item name, item id or tab name. The name of an item the client has not loaded yet is asked for and
--         the row is filled in when it arrives (GET_ITEM_INFO_RECEIVED).
--
-- View.ItemRows, View.SlotGrid and the text helpers are plain functions (tested offline); the frames only draw them.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.BankView, ns.modules = View, ns.modules or {}
ns.modules.BankView = View

local L, W, Skin = ns.L, ns.Widgets, ns.Skin
local type, ipairs, pairs, tostring, floor, max, min = type, ipairs, pairs, tostring, math.floor, math.max, math.min
local concat, sort = table.concat, table.sort

View.ROW_HEIGHT = 22
View.TOOLBAR_HEIGHT = 30
View.DEFAULT_ROWS = 12
View.WHEEL_STEP = 3
View.REFRESH_DELAY = 0.4
View.COLUMNS, View.ROWS, View.CELL = 14, 7, 34
View.MAX_REQUESTS_PER_REFRESH = 20     -- item names asked for in one redraw

View.modes = {}                -- id -> { id, label, order, available, build, refresh, frame }
View.mode = "tabs"
View.tab = nil                 -- the tab shown in the Tabs mode
View.search = ""
View.offset = 0

local function lower(s) return type(s) == "string" and s:lower() or "" end
local function now() return ns.Compat and ns.Compat.ServerTime() or 0 end

---------------------------------------------------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------------------------------------------------
-- 123456 copper -> "12g 34s 56c" (the silver and copper left out when zero, "0c" for nothing).
function View.MoneyText(copper)
	if type(copper) ~= "number" or copper ~= copper then return "?" end
	copper = max(0, floor(copper))
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = L["BANK_GOLD"]:format(g) end
	if s > 0 then parts[#parts + 1] = L["BANK_SILVER"]:format(s) end
	if c > 0 or #parts == 0 then parts[#parts + 1] = L["BANK_COPPER"]:format(c) end
	return concat(parts, " ")
end

-- "seen 2 h ago by Bob" (BANK-03); without a name, without "by".
function View.SeenText(t)
	if type(t) ~= "table" or not t.time then return "" end
	local ago = ns.Shell and ns.Shell.Ago(max(0, now() - t.time)) or "?"
	if t.authorName then return L["BANK_SEEN_BY"]:format(ago, t.authorName) end
	return L["BANK_SEEN"]:format(ago)
end

-- The hyperlink of an item for the tooltip: "item:<id>:<enchant>:<gem1..4>:<suffix>" from the compact variant.
function View.Hyperlink(itemID, variant)
	if type(itemID) ~= "number" then return nil end
	if type(variant) ~= "string" or variant == "" then return "item:" .. itemID end
	return "item:" .. itemID .. ":" .. variant:gsub("_", ":")
end

-- The item as the client knows it now: { name, quality, icon, link }; asks the client for it when it is not loaded.
-- `name` is nil until the item is known.
local asked = {}
function View.ItemInfo(itemID)
	local C = ns.Compat
	if not (C and C.Item) then return {} end
	local info = C.Item.Info(itemID)
	if info then return info end
	if not asked[itemID] then
		asked[itemID] = true
		C.Item.Request(itemID)
	end
	return { icon = C.Item.Icon(itemID) }
end

local function qualityColor(quality)
	local c = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

---------------------------------------------------------------------------------------------------------------------
-- Plain functions over the snapshots
---------------------------------------------------------------------------------------------------------------------
-- A snapshot's items as 98 slots: slots[n] = { itemID, count, variant } or nil.
function View.SlotGrid(tab)
	local slots = {}
	if type(tab) == "table" then
		for _, it in ipairs(tab.items or {}) do slots[it.slot] = it end
	end
	return slots
end

-- One row per item over the visible tabs, with its total and where it is:
--   { itemID, name (nil while not loaded), quality, icon, total, tabs = { { tab, name, count }, ... } }
-- opts.search keeps the rows whose item name, item id or tab name contains the text; opts.sort = "name" | "total".
function View.ItemRows(opts)
	opts = opts or {}
	local Bank = ns.Bank
	if not Bank then return {} end
	local byID, list = {}, {}
	for _, tab in ipairs(Bank:Tabs()) do
		for _, it in ipairs(tab.items) do
			local row = byID[it.itemID]
			if not row then
				local info = View.ItemInfo(it.itemID)
				row = { itemID = it.itemID, name = info.name, quality = info.quality, icon = info.icon, total = 0, tabs = {}, tabIndex = {} }
				byID[it.itemID] = row
				list[#list + 1] = row
			end
			row.total = row.total + it.count
			local at = row.tabIndex[tab.tab]
			if not at then
				at = { tab = tab.tab, name = tab.name, count = 0 }
				row.tabIndex[tab.tab] = at
				row.tabs[#row.tabs + 1] = at
			end
			at.count = at.count + it.count
		end
	end
	local query = lower(opts.search)
	local out = {}
	for _, row in ipairs(list) do
		sort(row.tabs, function(a, b) return a.tab < b.tab end)
		local keep = query == "" or lower(row.name):find(query, 1, true) ~= nil or tostring(row.itemID) == query
		if not keep then
			for _, t in ipairs(row.tabs) do
				if lower(t.name):find(query, 1, true) then keep = true break end
			end
		end
		if keep then out[#out + 1] = row end
	end
	local byTotal = opts.sort == "total"
	sort(out, function(a, b)
		if byTotal and a.total ~= b.total then return a.total > b.total end
		local an, bn = lower(a.name or "~"), lower(b.name or "~")   -- names not loaded yet go last
		if an ~= bn then return an < bn end
		return a.itemID < b.itemID
	end)
	return out
end

-- "Tab 1 x20, Tab 2 x3" for the Items rows.
function View.TabsText(row)
	local parts = {}
	for _, t in ipairs(row.tabs) do parts[#parts + 1] = L["BANK_TAB_COUNT"]:format(t.name or L["BANK_TAB_N"]:format(t.tab), t.count) end
	return concat(parts, ", ")
end

---------------------------------------------------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------------------------------------------------
function View.AddMode(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	def.id = id
	def.order = def.order or 100
	View.modes[id] = def
	if View.frame then View:Redraw() end
	return true
end

function View:ModeList()
	local list = {}
	for _, m in pairs(self.modes) do
		if m.available == nil or m.available() then list[#list + 1] = m end
	end
	sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
	return list
end

function View:SetMode(id)
	local m = self.modes[id]
	if not m or (m.available and not m.available()) then return false end
	self.mode = id
	self.offset = 0
	if self.frame then self:Redraw() end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Tabs mode
---------------------------------------------------------------------------------------------------------------------
local tabs = {}

local function newSlot(grid, i)
	local col, row = floor((i - 1) / View.ROWS), (i - 1) % View.ROWS
	local b = CreateFrame("Button", nil, grid)
	b:SetSize(View.CELL - 2, View.CELL - 2)
	b:SetPoint("TOPLEFT", grid, "TOPLEFT", col * View.CELL, -row * View.CELL)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.bg:SetColorTexture(0, 0, 0, 0.35)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	b.count = W.Text(b, "small", "white", "RIGHT", "OVERLAY")
	b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
	b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
	b.highlight:SetAllPoints(b)
	b.highlight:SetColorTexture(1, 1, 1, 0.2)
	b:SetScript("OnEnter", function(self)
		local d = self.data
		if not (d and GameTooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local link = View.Hyperlink(d.itemID, d.variant)
		if not (link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)) then
			GameTooltip:SetText(tostring(d.itemID))
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	grid.slots[i] = b
	return b
end

function tabs.build(f)
	f.bar = W.Frame(f, 10, 24)
	f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
	f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -4)
	f.bar.buttons = {}
	f.info = W.Text(f, "small", "grey", "LEFT")
	f.info:SetPoint("TOPLEFT", f.bar, "BOTTOMLEFT", 0, -6)
	f.info:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.grid = W.Frame(f, View.COLUMNS * View.CELL, View.ROWS * View.CELL)
	f.grid:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -8)
	f.grid.slots = {}
	for i = 1, View.COLUMNS * View.ROWS do newSlot(f.grid, i) end
	f.message = W.Text(f, "body", "grey", "CENTER")
	f.message:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.message:SetWidth(420)
end

local function tabButton(bar, i)
	local b = bar.buttons[i]
	if b then return b end
	b = W.Button(bar, { width = 104, height = 22, onClick = function(self) View.tab = self.tabIndex; View:Redraw() end })
	b:SetPoint("LEFT", bar, "LEFT", (i - 1) * 108, 0)
	bar.buttons[i] = b
	return b
end

-- The tab shown: the chosen one when it is still visible, else the first.
local function chosen(list)
	for _, t in ipairs(list) do if t.tab == View.tab then return t end end
	return list[1]
end

function tabs.refresh(f)
	local Bank = ns.Bank
	local list = Bank and Bank:Tabs() or {}
	if #list == 0 then
		f.bar:Hide(); f.info:Hide(); f.grid:Hide()
		f.message:SetText(L["BANK_EMPTY"])
		f.message:Show()
		return 0
	end
	f.message:Hide(); f.bar:Show(); f.info:Show(); f.grid:Show()
	local current = chosen(list)
	View.tab = current.tab
	for i, t in ipairs(list) do
		local b = tabButton(f.bar, i)
		b.tabIndex = t.tab
		b:SetLabel(t.tab == current.tab and ("> " .. (t.name or L["BANK_TAB_N"]:format(t.tab)) .. " <") or (t.name or L["BANK_TAB_N"]:format(t.tab)))
		b:Show()
	end
	for i = #list + 1, #f.bar.buttons do f.bar.buttons[i]:Hide() end
	local money = Bank:Money()
	local line = {}
	if money then line[#line + 1] = L["BANK_MONEY"]:format(View.MoneyText(money.money), View.SeenText(money)) end
	line[#line + 1] = L["BANK_TAB_SEEN"]:format(View.SeenText(current), current.n)
	f.info:SetText(concat(line, "   "))
	local slots = View.SlotGrid(current)
	for i = 1, View.COLUMNS * View.ROWS do
		local b, d = f.grid.slots[i], slots[i]
		b.data = d
		if d then
			local info = View.ItemInfo(d.itemID)
			b.icon:SetTexture(info.icon or 134400)
			b.icon:Show()
			b.count:SetText(d.count > 1 and tostring(d.count) or "")
		else
			b.icon:Hide()
			b.count:SetText("")
		end
	end
	return #current.items
end

View.AddMode("tabs", { label = L["BANK_MODE_TABS"], order = 10, build = tabs.build, refresh = tabs.refresh })

---------------------------------------------------------------------------------------------------------------------
-- Items mode
---------------------------------------------------------------------------------------------------------------------
local items = {}

local function newRow(area, i)
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(View.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.name = W.Text(row, "body", nil, "LEFT")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetWidth(210)
	row.total = W.Text(row, "body", "gold", "RIGHT")
	row.total:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.total:SetWidth(56)
	row.where = W.Text(row, "small", "grey", "LEFT")
	row.where:SetPoint("LEFT", row.total, "RIGHT", 12, 0)
	row.where:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not (d and GameTooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not pcall(GameTooltip.SetHyperlink, GameTooltip, View.Hyperlink(d.itemID)) then GameTooltip:SetText(tostring(d.itemID)) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	area.rows[i] = row
	return row
end

local function fillRow(row, d)
	row.data = d
	if d.icon then row.icon:SetTexture(d.icon) end
	row.name:SetText(d.name or L["BANK_ITEM_LOADING"]:format(d.itemID))
	row.name:SetTextColor(qualityColor(d.quality))
	row.total:SetText(tostring(d.total))
	row.where:SetText(View.TabsText(d))
	row:Show()
end

function items.build(f)
	f.explain = W.Text(f, "small", "grey", "LEFT")
	f.explain:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
	f.explain:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.explain:SetText(L["BANK_ITEMS_EXPLAIN"])
	local area = W.Frame(f, 10, 10)
	area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -26)
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

local function visibleRows(area)
	local h = area and area:GetHeight() or 0
	if not h or h < View.ROW_HEIGHT then return View.DEFAULT_ROWS end
	return max(1, floor(h / View.ROW_HEIGHT))
end

function items.refresh(f)
	local rows = View.ItemRows({ search = View.search })
	View.rowsShown = rows
	local total, visible = #rows, visibleRows(f.area)
	View.offset = max(0, min(View.offset or 0, max(0, total - visible)))
	local drawn = max(0, min(visible + 1, total - View.offset))
	for i = 1, drawn do fillRow(f.area.rows[i] or newRow(f.area, i), rows[View.offset + i]) end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	if total == 0 then
		f.message:SetText(View.search ~= "" and L["BANK_NO_MATCH"] or L["BANK_EMPTY"])
		f.message:Show()
	else
		f.message:Hide()
	end
	return total
end

View.AddMode("items", { label = L["BANK_MODE_ITEMS"], order = 20, build = items.build, refresh = items.refresh, search = true })

---------------------------------------------------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------------------------------------------------
function View:Build(f)
	self.frame = f
	local bar = W.Frame(f, 10, View.TOOLBAR_HEIGHT)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	bar.buttons = {}
	f.bar = bar
	f.body = W.Frame(f, 10, 10)
	f.body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f:SetScript("OnShow", function() View:Redraw() end)
	self:Redraw()
end

local function modeButton(bar, i)
	local b = bar.buttons[i]
	if b then return b end
	b = W.Button(bar, { width = 110, height = 22, onClick = function(self) View:SetMode(self.modeId) end })
	b:SetPoint("LEFT", bar, "LEFT", 8 + (i - 1) * 114, 0)
	bar.buttons[i] = b
	return b
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local list = self:ModeList()
	local current = self.modes[self.mode]
	if not current or (current.available and not current.available()) then
		current = list[1]
		self.mode = current and current.id or "tabs"
	end
	for i, m in ipairs(list) do
		local b = modeButton(f.bar, i)
		b.modeId = m.id
		b:SetLabel(m.id == self.mode and ("> " .. m.label .. " <") or m.label)
		b:Show()
	end
	for i = #list + 1, #f.bar.buttons do f.bar.buttons[i]:Hide() end
	for id, m in pairs(self.modes) do
		if m.frame and id ~= self.mode then m.frame:Hide() end
	end
	if current then
		if not current.frame then
			current.frame = W.Frame(f.body, 10, 10)
			current.frame:SetAllPoints(f.body)
			current.build(current.frame)
		end
		current.frame:Show()
		if current.refresh then current.refresh(current.frame) end
	end
	self.drawn = (self.drawn or 0) + 1
end

function View:Scroll(delta)
	local total = self.rowsShown and #self.rowsShown or 0
	local m = self.modes[self.mode]
	local area = m and m.frame and m.frame.area
	local limit = max(0, total - visibleRows(area))
	local target = max(0, min((self.offset or 0) + delta, limit))
	if target == self.offset then return false end
	self.offset = target
	self:Redraw()
	return true
end

function View:SetSearch(text)
	text = type(text) == "string" and text or ""
	if text == self.search then return end
	self.search = text
	self.offset = 0
	if text ~= "" and self.mode == "tabs" and self.modes.items then self.mode = "items" end   -- a search looks at the list
	self:Redraw()
end

-- The data changed: one redraw after the burst, only while the view is visible.
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
	ns.Shell:RegisterView("bank", {
		label = L["VIEW_BANK"], order = 40, search = true,
		badge = function() return ns.BankInbox and ns.BankInbox.PendingCount() or 0 end,
		build = function(f) View:Build(f) end,
		onSearch = function(text) View:SetSearch(text) end,
	})
end

if ns.addon then
	ns.addon.BankView = View
	LibStub("AceEvent-3.0"):Embed(View)
	pcall(View.RegisterEvent, View, "GET_ITEM_INFO_RECEIVED", function() View:Changed() end)
	if ns.Bus then
		local function changed() View:Changed() end
		ns.Bus:On("STORE_CHANGED", function(set) if set == "bank" then changed() end end)
		ns.Bus:On("BANK_CAPTURED", changed)
		ns.Bus:On("ROSTER_UPDATED", changed)
		ns.Bus:On("ROLE_CHANGED", changed)
		ns.Bus:On("GUILD_CHANGED", function()
			View.search, View.offset, View.tab, asked = "", 0, nil, {}
			if View.frame then View:Redraw() end
		end)
	end
end

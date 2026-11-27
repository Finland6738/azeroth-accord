-- DemandView: the "Demand" mode of the Market view (M13.3; SPEC-17 §4.1). Lua 5.1.
-- One row per material: how many are needed, by how many open orders and goals (the tooltip lists them), and how many the
-- guild bank shows to this player, with the age of that snapshot. A line says how many orders have materials the game has
-- not given yet. Nothing here is a button: the demand is computed. Only with the switch "econ".
--   View.FromText(row), View.BankText(row), View.NoteText(demand), View.Tip(row)    plain texts, tested offline
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.DemandView, ns.modules = View, ns.modules or {}
ns.modules.DemandView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, tostring, max = ipairs, tostring, math.max
local sort = table.sort

View.ROW_HEIGHT = 36
View.ICON = 20
View.TIP_LINES = 10

local function D() return ns.Demand end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end

local function ago(t) return ns.Provenance.AgeText(max(0, ns.Compat.ServerTime() - (t or 0))) end

function View.FromText(row)
	local parts = {}
	local orders, goals = #row.orders, #row.goals
	if orders > 0 then parts[#parts + 1] = L[orders == 1 and "DEMAND_ORDER_ONE" or "DEMAND_ORDER_N"]:format(orders) end
	if goals > 0 then parts[#parts + 1] = L[goals == 1 and "DEMAND_GOAL_ONE" or "DEMAND_GOAL_N"]:format(goals) end
	return table.concat(parts, ", ")
end

function View.BankText(row)
	if not row.bank then return "-" end
	return L["DEMAND_BANK"]:format(row.bank, ago(row.bankAt))
end

-- The line above the table: the orders whose materials are not known.
function View.NoteText(demand)
	local n = demand.unknown
	if n > 0 then return L[n == 1 and "DEMAND_UNKNOWN_ONE" or "DEMAND_UNKNOWN_N"]:format(n), "warn" end
	return L["DEMAND_HINT"], "text-3"
end

function View.Tip(row)
	local out = { escape(row.itemName or "") }
	local shown = 0
	local function add(text)
		shown = shown + 1
		if shown <= View.TIP_LINES then out[#out + 1] = { text = text, token = "text-2" } end
	end
	for _, o in ipairs(row.orders) do
		add(L["DEMAND_TIP_ORDER"]:format(ns.OrdersView.ItemText(o.row), escape(o.row.buyerName), escape(o.row.crafterName), o.need))
	end
	for _, g in ipairs(row.goals) do add(L["DEMAND_TIP_GOAL"]:format(escape(g.title or ""), g.need)) end
	if shown > View.TIP_LINES then out[#out + 1] = { text = L["DEMAND_TIP_MORE"]:format(shown - View.TIP_LINES), token = "text-3" } end
	out[#out + 1] = { text = row.bank and L["DEMAND_TIP_BANK"]:format(View.BankText(row)) or L["DEMAND_TIP_NO_BANK"],
		token = "text-3" }
	return out
end

local function renderItem(cell, row, frame)
	cell:SetText(escape(row.itemName))
	Theme.Text(cell, "text-1")
	local pos = View.frame.table.pos and View.frame.table.pos[1]
	if pos then
		cell:ClearAllPoints()
		cell:SetWidth(max(pos.w - View.ICON - 16, 1))
		cell:SetPoint("LEFT", frame, "LEFT", pos.x + View.ICON + 8, 0)
	end
end

-- How many of an item the player owns (bags, bank, mail and alts, SPEC-17 §5.4), "" for none.
function View.YoursText(r)
	local inv = ns.Inventory and ns.Inventory.Enabled() and ns.Inventory or nil
	local n = inv and inv:Count(r.item).owned or 0
	return n > 0 and tostring(n) or ""
end

local function columns()
	local function col(id, key, opts)
		opts.id, opts.title, opts.sortable = id, L[key], false
		return opts
	end
	return {
		col("item", "ORD_COL_ITEM", { flex = 2, render = renderItem }),
		col("need", "DEMAND_COL_NEED", { width = 96, mono = true, text = function(r) return tostring(r.need) end }),
		col("from", "DEMAND_COL_FROM", { flex = 1.2, text = View.FromText }),
		col("bank", "DEMAND_COL_BANK", { flex = 1.2, text = View.BankText,
			token = function(r) return r.bank and "text-2" or "text-3" end }),
		-- what the player owns (M13.4, the inventory of this computer)
		col("mine", "SHOP_COL_YOURS", { width = 80, mono = true, text = View.YoursText,
			token = function() return "text-2" end }),
	}
end

local mode = {}

function mode.build(f)
	View.frame = f
	f.note = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
	f.note:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.note:SetWordWrap(false)
	f.table = Widgets.DataTable(f, columns(), { rowHeight = View.ROW_HEIGHT, pool = 20, maxPool = 60,
		emptyText = L["DEMAND_EMPTY"],
		rowSetup = function(row)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(View.ICON, View.ICON)
			row:HookScript("OnEnter", function(self)
				if self.data then Widgets.Tooltip.Show(self, View.Tip(self.data), "BOTTOM") end
			end)
			row:HookScript("OnLeave", function() Widgets.Tooltip.Hide() end)
		end,
		rowUpdate = function(row, d)
			local pos = View.frame.table.pos and View.frame.table.pos[1]
			row.icon:ClearAllPoints()
			row.icon:SetPoint("LEFT", row, "LEFT", pos and pos.x or 8, 0)
			local icon = ns.Compat.Item.Icon(d.item)
			if icon then row.icon:SetTexture(icon) row.icon:Show() else row.icon:Hide() end
		end })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -28)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

function mode.refresh(f)
	local demand = D():Compute()
	local search = ns.MarketView and ns.MarketView.search
	local needle = search and search ~= "" and search:lower() or nil
	local rows = {}
	for _, row in ipairs(demand.rows) do
		row.itemName = ns.Wishlist.ItemName(row.item)
		if not needle or row.itemName:lower():find(needle, 1, true) then rows[#rows + 1] = row end
	end
	sort(rows, function(a, b)
		if a.itemName:lower() ~= b.itemName:lower() then return a.itemName:lower() < b.itemName:lower() end
		return a.item < b.item
	end)
	View.demand, View.rows = demand, rows
	local text, token = View.NoteText(demand)
	f.note:SetText(text)
	Theme.Text(f.note, token)
	f.table:SetEmptyText(L[needle and "DEMAND_NO_MATCH" or "DEMAND_EMPTY"])
	f.table:SetData(rows, true)
end

if ns.MarketView then
	ns.MarketView.AddMode("demand", { label = L["MARKET_MODE_DEMAND"], order = 30, build = mode.build, refresh = mode.refresh,
		available = function() return D() ~= nil and D().Enabled() end })
end

if ns.addon then
	ns.addon.DemandView = View
	if ns.Bus then
		ns.Bus:On("DEMAND_CHANGED", function() if ns.MarketView then ns.MarketView:Changed() end end)
	end
end

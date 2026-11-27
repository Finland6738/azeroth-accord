-- Demand: the materials the guild needs, summed per item (M13.3; SPEC-17 §4.1; ADR 0028). Lua 5.1.
-- Computed on every client from what it holds; never written and never sent. So it follows by itself an order that
-- closes (delivered, cancelled, declined, expired, a side that left the guild).
--   * open orders (requested, accepted, in progress): the materials of the recipe (Data/Reagents.lua) times the order's
--     count, intermediates not broken down. An order that is ready needs nothing any more.
--   * open item goals (Data/Goals.lua): what is missing to the target, through
--     Goals:Demand(t) -> { { id, item, missing, title } }.
--
--   Demand:Compute(t) -> { rows = { { item, need, orders = { { id, need, row } }, goals = { { id, need, title } },
--                          bank = how many the guild bank shows or nil, bankAt = the age's time } } sorted by item id,
--                          orders = how many orders were counted, unknown = how many have materials not known yet }
-- Switch: Core/Features.lua "econ". Bus: DEMAND_CHANGED(), DELAY seconds after what it is made of changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Demand = {}
ns.Demand, ns.modules = Demand, ns.modules or {}
ns.modules.Demand = Demand

local ipairs, pairs = ipairs, pairs
local sort = table.sort

Demand.DELAY = 1
Demand.STATES = { requested = true, accepted = true, progress = true }

function Demand.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

function Demand:Compute(t)
	local out = { rows = {}, orders = 0, unknown = 0 }
	if not (Demand.Enabled() and ns.GuildKey and ns.GuildKey:Current()) then return out end
	t = t or ns.Compat.ServerTime()
	local items = {}
	local function entry(item)
		local e = items[item]
		if not e then
			e = { item = item, need = 0, orders = {}, goals = {} }
			items[item] = e
			out.rows[#out.rows + 1] = e
		end
		return e
	end
	local list = ns.Orders and ns.Orders:List({ t = t }) or {}
	sort(list, function(a, b) return a.id < b.id end)
	for _, row in ipairs(list) do
		if Demand.STATES[row.state] then
			local mats = ns.Reagents and ns.Reagents:Ensure(row.recipe)
			if not mats then
				out.unknown = out.unknown + 1
			else
				out.orders = out.orders + 1
				for _, slot in ipairs(mats.r) do
					local e, need = entry(slot[1]), slot[2] * row.count
					e.need = e.need + need
					local last = e.orders[#e.orders]
					if last and last.id == row.id then last.need = last.need + need   -- one item in two slots
					else e.orders[#e.orders + 1] = { id = row.id, need = need, row = row } end
				end
			end
		end
	end
	local goals = ns.Goals
	for _, goal in ipairs(goals and goals.Demand and goals:Demand(t) or {}) do
		if (goal.missing or 0) > 0 then
			local e = entry(goal.item)
			e.need = e.need + goal.missing
			e.goals[#e.goals + 1] = { id = goal.id, need = goal.missing, title = goal.title }
		end
	end
	if #out.rows > 0 and ns.BankRequests then
		local bank = ns.BankRequests:BankItems()
		for _, e in pairs(items) do
			local held = bank[e.item]
			if held then e.bank, e.bankAt = held.available, held.time end
		end
	end
	sort(out.rows, function(a, b) return a.item < b.item end)
	return out
end

local pending, epoch = false, 0

function Demand:Changed()
	if pending or not Demand.Enabled() then return end
	pending = true
	local mine = epoch
	local function fire()
		if mine ~= epoch then return end
		pending = false
		if ns.Bus then ns.Bus:Emit("DEMAND_CHANGED") end
	end
	if not (ns.Compat and ns.Compat.After(Demand.DELAY, fire)) then fire() end
end

function Demand:Reset() pending, epoch = false, epoch + 1 end

if ns.addon then
	ns.addon.Demand = Demand
	if ns.Bus then
		for _, event in ipairs({ "ORDERS_CHANGED", "GOALS_CHANGED", "REAGENTS_CHANGED", "ROSTER_UPDATED" }) do
			ns.Bus:On(event, function() Demand:Changed() end)
		end
		ns.Bus:On("STORE_CHANGED", function(set)   -- a new snapshot of the guild bank
			if set == "bank" then Demand:Changed() end
		end)
		ns.Bus:On("GUILD_CHANGED", function()
			Demand:Reset()
			Demand:Changed()
		end)
	end
end

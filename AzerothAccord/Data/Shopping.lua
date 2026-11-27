-- Shopping: the player's shopping list, private and per account (M13.4; SPEC-17 §5; ECO-05; SPEC-10 Q44, Q46). Lua 5.1.
--
-- Config.db.account.shopping = { list = { { recipe, n = how many times to craft it (1..QTY_MAX), line = skill line } },
--     breakdown = true|nil, alts = false|nil (counted unless false), mail = false|nil, missingOnly = true|nil, skill, at }
-- Not a record, never sent: only "Ask the guild" (the missing materials into the own wishlist, M13.3) and "Ask the bank"
-- (a guild-bank request prefilled with what is missing and the bank shows, one at a time) let anything out, and then only
-- what is missing.
--
--   Shopping:List(), :Add(recipe, n, line), :Set(recipe, n), :Remove(recipe), :Clear()
--   Shopping:SetBreakdown(on), :SetOption(key, on)  (alts, mail, missingOnly), :Options()
--   Shopping:Compute() -> { rows = { { item, need, owned, missing, broken, intermediate, count = Inventory:Count(...),
--       guildBank, guildBankAt, price, priceAge, depth } } (missing first, then by name), unknown = { recipe ids the game
--       gave no materials for }, missingRows, cost (copper of the missing ones with a price), costAge, priced }
--     Breakdown on: an intermediate (a material a cached recipe makes, Reagents:MakerOf) is replaced, for its MISSING part
--     only, by the materials of its recipe, ceil(missing / made) times, up to DEPTH levels, never through an item already
--     on its own branch. The intermediate's row stays, with `broken` = how many were broken down.
--   Shopping.Wants(result) -> { { item, n } } the missing materials (the broken-down part of an intermediate excluded)
--   Shopping:PlanGuild(), :AskGuild()   Wishlist:Plan / Wishlist:Ask with the wants
--   Shopping:BankRows(result) -> { { item, missing, available, n = min(missing, available), requested, at } } the missing
--       materials the guild bank shows (BankRequests:BankItems); Shopping:Reason() the reason of such a request
-- Switch: Core/Features.lua "econ". Bus: SHOPPING_CHANGED() DELAY seconds after the list, the inventory, the materials,
-- the prices or the guild bank's snapshot changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Shop = {}
ns.Shopping, ns.modules = Shop, ns.modules or {}
ns.modules.Shopping = Shop

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local sort, concat = table.sort, table.concat

Shop.MAX_RECIPES = 50
Shop.QTY_MAX = 999
Shop.DEPTH = 4
Shop.DELAY = 0.2
Shop.REASON_MAX = 120   -- bytes, the reason of a bank request (BankRequests.MAX_REASON)
Shop.OPTIONS = { alts = true, mail = true, missingOnly = false }   -- the defaults

local function compat() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

function Shop.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end

local function db(create)
	local account = ns.Config and ns.Config.db.account
	if not account then return nil end
	if type(account.shopping) ~= "table" then
		if not create then return nil end
		account.shopping = { list = {} }
	end
	if type(account.shopping.list) ~= "table" then account.shopping.list = {} end
	return account.shopping
end

local pending, epoch = false, 0

function Shop:Changed()
	if pending or not Shop.Enabled() then return end
	pending = true
	local mine = epoch
	local function fire()
		if mine ~= epoch then return end
		pending = false
		emit("SHOPPING_CHANGED")
	end
	if not (compat() and compat().After(Shop.DELAY, fire)) then fire() end
end

local function touched(s)
	s.at = compat().ServerTime()
	Shop:Changed()
end

---------------------------------------------------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------------------------------------------------
function Shop:List()
	local s = db(false)
	local out = {}
	for i, e in ipairs(s and s.list or {}) do
		if type(e) == "table" and int(e.recipe, 1, 2147483647) and int(e.n, 1, Shop.QTY_MAX) then
			out[#out + 1] = { recipe = e.recipe, n = e.n, line = e.line, index = i }
		end
	end
	return out
end

local function find(list, recipe)
	for i, e in ipairs(list) do if type(e) == "table" and e.recipe == recipe then return i, e end end
	return nil
end

-- Adds `n` crafts of a recipe (one already listed grows). Returns the entry, or nil and "off", "recipe", "count", "full".
function Shop:Add(recipe, n, line)
	if not Shop.Enabled() then return nil, "off" end
	if not int(recipe, 1, 2147483647) then return nil, "recipe" end
	n = n == nil and 1 or tonumber(n)
	if not int(n, 1, Shop.QTY_MAX) then return nil, "count" end
	local s = db(true)
	local _, e = find(s.list, recipe)
	if e then
		e.n = min(e.n + n, Shop.QTY_MAX)
	else
		if #s.list >= Shop.MAX_RECIPES then return nil, "full" end
		e = { recipe = recipe, n = n, line = int(line, 1, 99999) and line or nil }
		s.list[#s.list + 1] = e
	end
	if ns.Reagents then ns.Reagents:Ensure(recipe) end
	touched(s)
	return e
end

function Shop:Set(recipe, n)
	if not Shop.Enabled() then return nil, "off" end
	n = tonumber(n)
	if not int(n, 1, Shop.QTY_MAX) then return nil, "count" end
	local s = db(false)
	local _, e = find(s and s.list or {}, recipe)
	if not e then return nil, "missing" end
	if e.n ~= n then
		e.n = n
		touched(s)
	end
	return e
end

function Shop:Remove(recipe)
	local s = db(false)
	local i = find(s and s.list or {}, recipe)
	if not i then return false end
	table.remove(s.list, i)
	touched(s)
	return true
end

function Shop:Clear()
	local s = db(false)
	if not s or #s.list == 0 then return false end
	s.list = {}
	touched(s)
	return true
end

function Shop:Options()
	local s = db(false) or {}
	local out = { breakdown = s.breakdown == true, skill = s.skill }
	for key, default in pairs(Shop.OPTIONS) do
		if s[key] == nil then out[key] = default else out[key] = s[key] == true end
	end
	return out
end

function Shop:SetBreakdown(on)
	local s = db(true)
	s.breakdown = on and true or nil
	touched(s)
end

function Shop:SetOption(key, on)
	if Shop.OPTIONS[key] == nil and key ~= "skill" then return false end
	local s = db(true)
	if key == "skill" then s.skill = int(on, 1, 99999) and on or nil
	else s[key] = (on and true or false) end
	touched(s)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The materials
---------------------------------------------------------------------------------------------------------------------
local function itemName(item)
	if ns.Wishlist and ns.Wishlist.ItemName then return (ns.Wishlist.ItemName(item)) end
	local info = compat().Item.Info(item)
	return info and info.name or tostring(item)
end

function Shop:Compute()
	local out = { rows = {}, unknown = {}, missingRows = 0, cost = 0, priced = 0 }
	if not Shop.Enabled() then return out end
	local R, Inv = ns.Reagents, ns.Inventory
	local o = self:Options()
	local counts = {}
	local function count(item)
		local c = counts[item]
		if not c then
			c = Inv and Inv:Count(item, { alts = o.alts, mail = o.mail, guildBank = true })
				or { owned = 0, bags = 0, bank = 0, mail = 0, account = 0, alts = {}, others = {}, ages = {} }
			counts[item] = c
		end
		return c
	end
	-- level 0: the materials of the recipes as listed
	local rows, order = {}, {}
	local function row(item, depth)
		local r = rows[item]
		if not r then
			r = { item = item, need = 0, broken = 0, depth = depth }
			rows[item] = r
			order[#order + 1] = r
		end
		return r
	end
	local current, ancestors = {}, {}
	local function add(level, item, n, from)
		level[item] = (level[item] or 0) + n
		if from then
			local a = ancestors[item] or {}
			ancestors[item] = a
			for k in pairs(ancestors[from] or {}) do a[k] = true end
			a[from] = true
		end
	end
	for _, e in ipairs(self:List()) do
		local mats = R and R:Ensure(e.recipe)
		if not mats then
			out.unknown[#out.unknown + 1] = e.recipe
		else
			for _, slot in ipairs(mats.r) do add(current, slot[1], slot[2] * e.n) end
		end
	end
	local makers = o.breakdown and R and R:Makers() or nil
	local pool = {}   -- what is still owned of an item after the earlier levels took their share
	local lineOfList = {}
	for _, e in ipairs(self:List()) do if e.line then lineOfList[#lineOfList + 1] = e.line end end
	for depth = 0, Shop.DEPTH do
		local items = {}
		for item in pairs(current) do items[#items + 1] = item end
		if #items == 0 then break end
		sort(items)
		local nextLevel = {}
		for _, item in ipairs(items) do
			local qty = current[item]
			local r = row(item, depth)
			r.need = r.need + qty
			if pool[item] == nil then pool[item] = count(item).owned end
			local use = min(pool[item], qty)
			pool[item] = pool[item] - use
			local missing = qty - use
			if makers and missing > 0 and depth < Shop.DEPTH then
				local maker = R:MakerOf(item, lineOfList[1], makers)
				local mats = maker and R:Get(maker)
				local ok = mats ~= nil
				if ok then
					local mine = ancestors[item] or {}
					for _, slot in ipairs(mats.r) do
						if slot[1] == item or mine[slot[1]] then ok = false break end   -- no cycle
					end
				end
				if ok then
					local times = ceil(missing / (mats.made or 1))
					r.broken = r.broken + missing
					r.intermediate, r.maker = true, maker
					for _, slot in ipairs(mats.r) do add(nextLevel, slot[1], slot[2] * times, item) end
				end
			end
		end
		current = nextLevel
	end
	local P = ns.Prices
	local priced = P and P:Available()
	for _, r in ipairs(order) do
		local c = count(r.item)
		r.count, r.owned = c, c.owned
		r.missing = max(0, r.need - r.owned - r.broken)
		r.guildBank, r.guildBankAt = c.guildBank, c.guildBankAt
		r.name = itemName(r.item)
		if r.missing > 0 then out.missingRows = out.missingRows + 1 end
		if priced then
			r.price, r.priceAge = P:Get(r.item)
			if r.price and r.missing > 0 then
				out.cost = out.cost + r.price * r.missing
				out.priced = out.priced + 1
				if r.priceAge and (out.costAge == nil or r.priceAge > out.costAge) then out.costAge = r.priceAge end
			end
		end
		if not (o.missingOnly and r.missing == 0 and r.broken == 0) then out.rows[#out.rows + 1] = r end
	end
	out.pricesOn = priced == true
	sort(out.rows, function(a, b)
		if (a.missing > 0) ~= (b.missing > 0) then return a.missing > 0 end
		local x, y = a.name:lower(), b.name:lower()
		if x ~= y then return x < y end
		return a.item < b.item
	end)
	return out
end

-- The missing materials of a computation (an intermediate's broken-down part is asked through its materials).
function Shop.Wants(result)
	local out = {}
	for _, r in ipairs(result and result.rows or {}) do
		if r.missing > 0 then out[#out + 1] = { item = r.item, n = min(r.missing, Shop.QTY_MAX) } end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Ask the guild, ask the bank (SPEC-17 §5.8)
---------------------------------------------------------------------------------------------------------------------
function Shop:PlanGuild(result)
	if not (Shop.Enabled() and ns.Wishlist) then return nil, "off" end
	return ns.Wishlist:Plan(Shop.Wants(result or self:Compute()))
end

function Shop:AskGuild(result)
	if not (Shop.Enabled() and ns.Wishlist) then return nil, "off" end
	return ns.Wishlist:Ask(Shop.Wants(result or self:Compute()))
end

-- The open withdrawal requests of the connected character, by item.
local function requested()
	local out, me = {}, compat().Player.GUID()
	for _, rec in pairs(ns.Store and ns.GuildKey and ns.GuildKey:Current() and ns.Store:Records("bankreq") or {}) do
		if type(rec) == "table" and rec.requester == me and rec.kind == "withdraw" and rec.itemID and rec.del ~= true
			and (rec.status == "open" or rec.status == "approved") then
			out[rec.itemID] = true
		end
	end
	return out
end

function Shop:BankRows(result)
	local out = {}
	if not (Shop.Enabled() and ns.BankRequests and ns.GuildKey and ns.GuildKey:Current()) then return out end
	local bank, asked = ns.BankRequests:BankItems(), requested()
	for _, r in ipairs((result or self:Compute()).rows) do
		local held = bank[r.item]
		if r.missing > 0 and held and held.available > 0 then
			out[#out + 1] = { item = r.item, name = r.name, missing = r.missing, available = held.available,
				n = min(r.missing, held.available, ns.BankRequests.MAX_COUNT), requested = asked[r.item] == true, at = held.time,
				author = held.author }
		end
	end
	return out
end

-- "Shopping list: Bolt of Silk Cloth, Heavy Linen Bandage" with as many recipe names as fit in REASON_MAX bytes.
function Shop:Reason()
	local prefix = ns.L and ns.L["SHOP_REASON"] or "Shopping list: %s"
	local names = {}
	for _, e in ipairs(self:List()) do
		local name = ns.Recipes and ns.Recipes.NameOf(e.recipe) or nil
		if name then
			local text = prefix:format(concat(names, ", ") .. (#names > 0 and ", " or "") .. name)
			if #text > Shop.REASON_MAX then break end
			names[#names + 1] = name
		end
	end
	if #names == 0 then
		local bare = prefix:gsub("%%s", ""):gsub("[:%s]+$", "")
		return bare
	end
	return prefix:format(concat(names, ", "))
end

function Shop:Reset() pending, epoch = false, epoch + 1 end

-- Counts only (SPEC-09 §6).
function Shop:DebugLines()
	local o, list = self:Options(), self:List()
	return { ("Shopping list: %d recipe(s), breakdown %s, alts %s, mail %s"):format(#list, tostring(o.breakdown),
		tostring(o.alts), tostring(o.mail)) }
end

if ns.addon then
	ns.addon.Shopping = Shop
	if ns.Bus then
		for _, event in ipairs({ "INVENTORY_CHANGED", "REAGENTS_CHANGED", "PRICES_CHANGED", "RECIPE_NAMES_UPDATED" }) do
			ns.Bus:On(event, function() Shop:Changed() end)
		end
		ns.Bus:On("STORE_CHANGED", function(set)
			if set == "bank" or set == "bankreq" or set == "recipecat" then Shop:Changed() end
		end)
		ns.Bus:On("GUILD_CHANGED", function() Shop:Changed() end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if Shop.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Shopping", function() return Shop:DebugLines() end)
			end
		end)
	end
end

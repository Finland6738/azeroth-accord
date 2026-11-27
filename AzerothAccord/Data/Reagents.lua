-- Reagents: the materials of a recipe as the game gives them, cached per account (M13.3; SPEC-17 §5.2; ADR 0028;
-- SPEC-10 Q45, R21). Reused by the shopping list (M13.4) and by M17. Lua 5.1.
--
-- The cache is account-wide and local (Config.db.account.reagents), never sent:
--   [recipe id] = { out = item id created (nil when not given), made = how many at once (at least 1),
--                   r = { { item id, n, alternative ids... }, ... } the basic slots, at = server time, build = client build }
-- An entry of another build is read again at the next chance (the old one is used until the game answers). Nothing is
-- ever guessed: a recipe the game gives nothing for has no entry, not an empty list.
--
--   Reagents.Parse(schematic)     the entry of a schematic table, or nil
--   Reagents:Get(recipe)          the cached entry, or nil; never asks the game
--   Reagents:Ensure(recipe)       the entry, asking the game when it is missing or of another build (a recipe it gave
--                                 nothing for is asked again after RETRY seconds); nil when unknown
--   Reagents:Queue(recipes)       reads many recipes, BATCH a second (the scan of an own profession)
-- Switch: Core/Features.lua "econ". Bus: REAGENTS_CHANGED(recipe) when an entry is new or changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Reagents = {}
ns.Reagents, ns.modules = Reagents, ns.modules or {}
ns.modules.Reagents = Reagents

local type, pairs, ipairs, tostring, floor = type, pairs, ipairs, tostring, math.floor
local sort, concat = table.sort, table.concat

Reagents.BATCH = 50          -- recipes read a second from the queue
Reagents.RETRY = 60          -- seconds before a recipe without an answer is asked again
Reagents.MAX_SLOTS = 20
Reagents.MAX_ALTERNATIVES = 5

local state
local function resetState()
	state = { queue = {}, queued = {}, at = 1, running = false, failed = {}, fields = nil,
		epoch = ((state and state.epoch) or 0) + 1 }
	Reagents.state = state
end
resetState()

local function compat() return ns.Compat end

function Reagents.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

local function int(v) return type(v) == "number" and v == floor(v) and v >= 1 and v <= 2147483647 end

local function build() return compat().BuildInfo().build end

local function cache(create)
	local account = ns.Config and ns.Config.db.account
	if not account then return nil end
	if type(account.reagents) ~= "table" then
		if not create then return nil end
		account.reagents = {}
	end
	return account.reagents
end

---------------------------------------------------------------------------------------------------------------------
-- Reading a schematic (the dump gives the function but not the fields [verify]: the modern client's names, tolerated
-- when missing)
---------------------------------------------------------------------------------------------------------------------
-- Only the basic materials count: Enum.CraftingReagentType.Basic, or `required` when a slot has no type.
local function basic(slot)
	local kind = slot.reagentType
	if kind ~= nil then
		local types = compat().Resolve("Enum.CraftingReagentType")
		local want = type(types) == "table" and types.Basic or 1
		return kind == want
	end
	return slot.required == true
end

local function slotOf(slot)
	if type(slot) ~= "table" or not basic(slot) or not int(slot.quantityRequired) then return nil end
	local out = {}
	for _, reagent in ipairs(type(slot.reagents) == "table" and slot.reagents or {}) do
		local id = type(reagent) == "table" and reagent.itemID
		if int(id) then
			if #out == 0 then out[1], out[2] = id, slot.quantityRequired
			elseif #out < 2 + Reagents.MAX_ALTERNATIVES then out[#out + 1] = id end
		end
	end
	if #out == 0 then return nil end
	return out
end

function Reagents.Parse(schematic)
	if type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then return nil end
	local r = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local s = slotOf(slot)
		if s and #r < Reagents.MAX_SLOTS then r[#r + 1] = s end
	end
	if #r == 0 then return nil end   -- never "no materials" from an answer this client cannot read
	return { out = int(schematic.outputItemID) and schematic.outputItemID or nil,
		made = int(schematic.quantityMin) and schematic.quantityMin or 1, r = r }
end

local function same(a, b)
	if a.out ~= b.out or a.made ~= b.made or #a.r ~= #b.r then return false end
	for i, s in ipairs(a.r) do
		if concat(s, ",") ~= concat(b.r[i], ",") then return false end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The cache
---------------------------------------------------------------------------------------------------------------------
function Reagents:Get(recipe)
	local c = cache(false)
	local e = c and c[recipe]
	if type(e) == "table" and type(e.r) == "table" then return e end
	return nil
end

-- The names of the fields the game gave, for /accord debug (never values).
local function remember(schematic)
	local seen, keys = {}, {}
	local function add(t, prefix)
		for k in pairs(t) do
			if type(k) == "string" and not seen[prefix .. k] then
				seen[prefix .. k] = true
				keys[#keys + 1] = prefix .. k
			end
		end
	end
	add(schematic, "")
	local slots = schematic.reagentSlotSchematics
	if type(slots) == "table" and type(slots[1]) == "table" then add(slots[1], "slot.") end
	sort(keys)
	while #keys > 40 do keys[#keys] = nil end
	state.fields = concat(keys, ", ")
end

-- Asks the game for one recipe and keeps the answer. Returns the entry, or nil.
local function read(recipe)
	local C = compat()
	local schematic = C.TradeSkill.Schematic and C.TradeSkill.Schematic(recipe)
	if schematic and not state.fields then remember(schematic) end
	local e = schematic and Reagents.Parse(schematic)
	if not e then
		state.failed[recipe] = C.Now()
		return nil
	end
	state.failed[recipe] = nil
	local c = cache(true)
	if not c then return nil end
	local held = c[recipe]
	e.at, e.build = C.ServerTime(), build()
	c[recipe] = e
	if not (type(held) == "table" and type(held.r) == "table" and same(held, e)) and ns.Bus then
		ns.Bus:Emit("REAGENTS_CHANGED", recipe)
	end
	return e
end

local function fresh(e) return e ~= nil and e.build == build() end

function Reagents:Ensure(recipe)
	if not (Reagents.Enabled() and int(recipe)) then return nil end
	local e = self:Get(recipe)
	if fresh(e) then return e end
	local last = state.failed[recipe]
	if last and compat().Now() - last < Reagents.RETRY then return e end
	return read(recipe) or e
end

---------------------------------------------------------------------------------------------------------------------
-- The queue: the recipes of a profession the player opened (its window is the surest moment for an answer)
---------------------------------------------------------------------------------------------------------------------
local function step()
	state.running = false
	local done, q = 0, state.queue
	while state.at <= #q and done < Reagents.BATCH do
		local recipe = q[state.at]
		state.at = state.at + 1
		state.queued[recipe] = nil
		if not fresh(Reagents:Get(recipe)) then
			read(recipe)
			done = done + 1
		end
	end
	if state.at > #q then
		state.queue, state.at = {}, 1
		return
	end
	state.running = true
	local epoch = state.epoch
	if not compat().After(1, function() if epoch == state.epoch then step() end end) then state.running = false end
end

function Reagents:Queue(recipes)
	if not Reagents.Enabled() or type(recipes) ~= "table" then return 0 end
	local added = 0
	for _, recipe in ipairs(recipes) do
		if int(recipe) and not state.queued[recipe] and not fresh(self:Get(recipe)) then
			state.queued[recipe] = true
			state.queue[#state.queue + 1] = recipe
			added = added + 1
		end
	end
	if added > 0 and not state.running then step() end
	return added
end

function Reagents:Reset() resetState() end

-- Counts and field names only (SPEC-09 §6).
function Reagents:DebugLines()
	local held, failed = 0, 0
	for _ in pairs(cache(false) or {}) do held = held + 1 end
	for _ in pairs(state.failed) do failed = failed + 1 end
	return { ("Reagents: %d recipe(s) cached, %d the game gave nothing for, %d waiting"):format(held, failed,
			#state.queue - state.at + 1),
		"Schematic fields seen: " .. (state.fields or "none") }
end

if ns.addon then
	ns.addon.Reagents = Reagents
	if ns.OnEnable then
		ns.OnEnable(function()
			if Reagents.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Reagents", function() return Reagents:DebugLines() end)
			end
		end)
	end
end

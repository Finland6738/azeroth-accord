-- The materials and their demand (M13.3; SPEC-17 §4.1, §5.2; ADR 0028; SPEC-10 Q45): the schematic read from the game
-- with tolerant field names and cached per account, never guessed; the scan of an own profession reads its recipes; the
-- demand sums the open orders and the open goals and follows an order that closes; unknown materials are counted apart;
-- the Demand mode; nothing sent; the switch "econ".
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function O() return AzerothAccord.Orders end
local function R() return AzerothAccord.Reagents end
local function D() return AzerothAccord.Demand end
local function DV() return AzerothAccord.DemandView end

local ME = "Player-1-0000A001"
local OFF, BOB, ANN = "Player-1-000000FF", "Player-1-00000B0B", "Player-1-00000A77"
local ALCHEMY, POTION, FLASK, ODD = 171, 2330, 3447, 9999
local HERB, ROOT, VIAL = 2447, 765, 3371
local DAY = 86400

local function setup(features)
	return function(M)
		M.features = features or { econ = true }
		M.spells.known[POTION] = { name = "Minor Healing Potion", icon = 1 }
		M.spells.known[FLASK] = { name = "Healing Potion", icon = 2 }
		M.items.info[HERB] = { name = "Peacebloom" }
		M.items.info[ROOT] = { name = "Silverleaf" }
		M.items.info[VIAL] = { name = "Empty Vial" }
		M.tradeskill.schematics = {
			[POTION] = M.tradeskill.Schematic(118, 1, { HERB, 1 }, { VIAL, 1 }),
			[FLASK] = M.tradeskill.Schematic(858, 1, { ROOT, 2 }, { VIAL, 1 }),
		}
		M.tradeskill.schematicCalls = {}
		M.tradeskill.schematicNeedsWindow = nil
		M.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Officer", rank = 1, guid = OFF, level = 60, class = "PRIEST", online = true },
			{ name = "Bob", rank = 3, guid = BOB, level = 60, class = "MAGE", online = true },
			{ name = "Ann", rank = 3, guid = ANN, level = 50, class = "DRUID", online = false },
		} }
	end
end

local function now() return GetServerTime() end
local NAME = { [OFF] = "Officer", [BOB] = "Bob", [ANN] = "Ann" }

local function order(buyer, crafter, recipe, count, n, fields)
	local r = { id = "O:" .. buyer .. ":" .. (n or 1), author = buyer, rev = 1, time = now(), crafter = crafter,
		recipe = recipe, count = count, mats = "buyer", created = now(), state = "open" }
	for k, v in pairs(fields or {}) do r[k] = v end
	truthy(S():Accept("orders", r, { sender = NAME[buyer], dist = "GUILD" }))
	return r
end

local function part(o, state)
	local held = S():Get("orders", "A" .. o.id:sub(2))
	local r = { id = "A" .. o.id:sub(2), author = o.crafter, rev = held and held.rev + 1 or 1, time = now(),
		crafter = o.crafter, state = state, at = now() }
	truthy(S():Accept("orders", r, { sender = NAME[o.crafter], dist = "GUILD" }))
end

local function needs()
	local out = {}
	for _, row in ipairs(D():Compute().rows) do out[row.item] = row.need end
	return out
end

---------------------------------------------------------------------------------------------------------------------
describe("the materials of a recipe, from the game (SPEC-17 §5.2)", function()
	before_boot(setup())

	it("reads the basic slots with the first alternative, what is created and how many", function()
		Mock.tradeskill.schematics[POTION] = { outputItemID = 118, quantityMin = 2, quantityMax = 3, reagentSlotSchematics = {
			{ reagentType = 1, quantityRequired = 2, reagents = { { itemID = HERB }, { itemID = ROOT } } },
			{ reagentType = 0, quantityRequired = 1, reagents = { { itemID = 11 } } },       -- optional: not counted
			{ reagentType = 2, quantityRequired = 1, reagents = { { itemID = 12 } } },       -- finishing: not counted
			{ required = true, quantityRequired = 1, reagents = { { itemID = VIAL } } },     -- no type: `required`
			{ reagentType = 1, reagents = { { itemID = 13 } } },                             -- no quantity
			{ reagentType = 1, quantityRequired = 1, reagents = {} },                        -- no item
		} }
		local e = R():Ensure(POTION)
		eq(e.out, 118); eq(e.made, 2)
		deepEq(e.r, { { HERB, 2, ROOT }, { VIAL, 1 } })
		eq(e.build, A().Compat.BuildInfo().build)
		eq(A().Config.db.account.reagents[POTION], e)
	end)

	it("guesses nothing: no answer, no slots or unreadable ones give no entry, asked again later", function()
		isNil(R():Ensure(ODD))
		Mock.tradeskill.schematics[ODD] = { outputItemID = 5 }
		Mock.Advance(R().RETRY + 1)
		isNil(R():Ensure(ODD))
		Mock.tradeskill.schematics[ODD] = { reagentSlotSchematics = { { quantityRequired = 1 } } }
		Mock.Advance(R().RETRY + 1)
		isNil(R():Ensure(ODD))
		local calls = #Mock.tradeskill.schematicCalls
		isNil(R():Ensure(ODD))
		eq(#Mock.tradeskill.schematicCalls, calls, "not asked again at once")
		Mock.tradeskill.schematics[ODD] = Mock.tradeskill.Schematic(nil, nil, { HERB, 1 })
		Mock.Advance(R().RETRY + 1)
		local e = R():Ensure(ODD)
		isNil(e.out); eq(e.made, 1)
	end)

	it("works without the function", function()
		local f = C_TradeSkillUI.GetRecipeSchematic
		C_TradeSkillUI.GetRecipeSchematic = nil
		isNil(R():Ensure(POTION))
		C_TradeSkillUI.GetRecipeSchematic = f
	end)

	it("asks once, and again with a new build; an unanswered new build keeps the old entry", function()
		R():Ensure(POTION); R():Ensure(POTION)
		eq(#Mock.tradeskill.schematicCalls, 1)
		A().Config.db.account.reagents[POTION].build = "1"
		R():Ensure(POTION)
		eq(#Mock.tradeskill.schematicCalls, 2)
		A().Config.db.account.reagents[POTION].build = "1"
		Mock.tradeskill.schematics[POTION] = nil
		eq(R():Ensure(POTION).out, 118)
	end)

	it("reads the recipes of an own profession when its window is scanned, 50 a second", function()
		local ids = {}
		for i = 1, 120 do
			ids[i] = 5000 + i
			Mock.tradeskill.schematics[5000 + i] = Mock.tradeskill.Schematic(6000 + i, 1, { HERB, i })
		end
		Mock.tradeskill.schematicNeedsWindow = true
		Mock.tradeskill.own = { { name = "Alchemy", skillLine = ALCHEMY, rank = 200, maxRank = 300, recipes = ids } }
		Mock.tradeskill.AddAllRecipeIDs()
		Mock.tradeskill.open = 1
		Mock.Fire("TRADE_SKILL_SHOW")
		Mock.Advance(A().RecipeScan.DEBOUNCE)
		eq(#Mock.tradeskill.schematicCalls, 50)
		Mock.Advance(1)
		eq(#Mock.tradeskill.schematicCalls, 100)
		Mock.Advance(2)
		eq(#Mock.tradeskill.schematicCalls, 120)
		truthy(R():Get(5120))
		Mock.tradeskill.open = nil
		eq(R():Ensure(5001).out, 6001, "kept with the window closed")
	end)

	it("reports counts and the field names in /accord debug, and sends nothing", function()
		local sent = #Mock.chat.sent
		R():Ensure(POTION); R():Ensure(ODD)
		local report = A().Diagnostics.Report()
		contains(report, "Reagents: 1 recipe(s) cached, 1 the game gave nothing for")
		contains(report, "slot.quantityRequired")
		eq(#Mock.chat.sent, sent)
	end)

	it("fills what an order creates", function()
		local rec = O():Create({ crafter = BOB, recipe = POTION })
		eq(rec.item, 118)
		isNil(O():Create({ crafter = BOB, recipe = ODD }).item)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the demand (SPEC-17 §4.1)", function()
	before_boot(setup())

	it("sums the materials of the open orders and changes when one closes (criterion)", function()
		local a = order(ANN, BOB, POTION, 2)
		local b = order(BOB, ANN, FLASK, 3)
		deepEq(needs(), { [HERB] = 2, [VIAL] = 5, [ROOT] = 6 })
		part(a, "accepted")
		part(b, "working")
		deepEq(needs(), { [HERB] = 2, [VIAL] = 5, [ROOT] = 6 })
		part(a, "ready")                                        -- ready: nothing more is needed for it
		deepEq(needs(), { [VIAL] = 3, [ROOT] = 6 })
		local cancel = {}
		for k, v in pairs(b) do cancel[k] = v end
		cancel.rev, cancel.state, cancel.closed = 2, "cancelled", now()
		truthy(S():Accept("orders", cancel, { sender = "Bob", dist = "GUILD" }))
		deepEq(needs(), {})
	end)

	it("leaves out a declined, a delivered and an expired order", function()
		local a = order(ANN, BOB, POTION, 1, 1)
		local b = order(ANN, BOB, POTION, 1, 2)
		order(ANN, BOB, FLASK, 1, 3)
		part(a, "declined")
		part(b, "handed")
		deepEq(needs(), { [ROOT] = 2, [VIAL] = 1 })
		Mock.Advance(15 * DAY)
		deepEq(needs(), {})
	end)

	it("counts apart the orders whose materials are not known", function()
		order(ANN, BOB, POTION, 1, 1)
		order(ANN, BOB, ODD, 4, 2)
		local d = D():Compute()
		eq(d.orders, 1); eq(d.unknown, 1); eq(#d.rows, 2)
	end)

	it("adds what is missing to the open goals", function()
		order(ANN, BOB, POTION, 1)
		local original = A().Goals.Demand
		A().Goals.Demand = function() return { { id = "G:1", item = HERB, missing = 40, title = "Herbs" },
			{ id = "G:2", item = ROOT, missing = 0, title = "Done" } } end
		local d = D():Compute()
		deepEq(needs(), { [HERB] = 41, [VIAL] = 1 })
		eq(d.rows[1].goals[1].title, "Herbs")
		A().Goals.Demand = original
	end)

	it("says what the guild bank shows, with its age", function()
		order(ANN, BOB, POTION, 2)
		local original = A().BankRequests.BankItems
		A().BankRequests.BankItems = function() return { [HERB] = { available = 15, time = now() - DAY } } end
		local d = D():Compute()
		A().BankRequests.BankItems = original
		eq(d.rows[1].item, HERB); eq(d.rows[1].bank, 15); isNil(d.rows[2].bank)
		contains(DV().BankText(d.rows[1]), "15 · seen")
		eq(DV().BankText(d.rows[2]), "-")
	end)

	it("announces a change once, a second after it", function()
		local n = 0
		A().Bus:On("DEMAND_CHANGED", function() n = n + 1 end)
		Mock.Advance(5)
		n = 0
		order(ANN, BOB, POTION, 1, 1)
		order(ANN, BOB, POTION, 1, 2)
		eq(n, 0)
		Mock.Advance(2)
		eq(n, 1)
	end)

	it("shows a row per material in the Demand mode, with names, search and the tooltip", function()
		order(ANN, BOB, POTION, 2, 1)
		order(ANN, BOB, ODD, 1, 2)
		truthy(A().MarketView:Open("demand"))
		Mock.Advance(2)
		local f = DV().frame
		local rows = {}
		for _, r in ipairs(f.table:VisibleRows()) do rows[#rows + 1] = r.cells[1]:GetText() .. " " .. r.cells[2]:GetText() .. " " .. r.cells[3]:GetText() end
		deepEq(rows, { "Empty Vial 2 1 order", "Peacebloom 2 1 order" })
		contains(f.note:GetText(), "Materials unknown for 1 order")
		contains(DV().Tip(DV().rows[1])[2].text, "2 × Minor Healing Potion for Ann (crafter Bob): 2")
		A().MarketView:SetSearch("peace")
		eq(#DV().rows, 1)
		A().MarketView:SetSearch("nothing")
		eq(#DV().rows, 0)
		eq(#Mock.errors, 0)
	end)

	it("lists the materials in an order's tooltip", function()
		local o = order(ANN, BOB, POTION, 2)
		A().Compat.Item.Request(HERB); A().Compat.Item.Request(VIAL)
		Mock.Advance(1)
		local found
		for _, line in ipairs(AzerothAccord.OrdersView.TipLines(O():Get(o.id))) do
			if type(line) == "table" and line.text:find("Materials: ", 1, true) then found = line.text end
		end
		eq(found, "Materials: 2 × Peacebloom (0/2), 2 × Empty Vial (0/2)", "with what the player owns (M13.4)")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the demo guild", function()
	before_boot(function(M) M.features = { econ = true } end)

	it("has a demand and three wishlists, and keeps the real cache as it was", function()
		local real = AzerothAccordDB.reagents
		Mock.Slash("/accord demo")
		Mock.Advance(2)
		local d = D():Compute()
		truthy(#d.rows >= 3, "rows " .. #d.rows)
		truthy(d.unknown >= 1)
		truthy(#AzerothAccord.Wishlist:Guild() >= 5)
		truthy(A().MarketView:Open("wishlist"))
		truthy(A().MarketView:Open("demand"))
		Mock.Advance(2)
		eq(#Mock.chat.sent, 0)
		eq(#Mock.errors, 0)
		Mock.Slash("/accord demo")
		eq(AzerothAccordDB.reagents, real)
		isNil(A().Config.db.account.reagents)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("with the switch econ off", function()
	before_boot(setup({ econ = false }))

	it("reads and computes nothing", function()
		isNil(R():Ensure(POTION))
		eq(R():Queue({ POTION }), 0)
		eq(#Mock.tradeskill.schematicCalls, 0)
		eq(#D():Compute().rows, 0)
		falsy(A().MarketView:Open("demand"))
		falsy(A().Diagnostics.Report():find("Reagents:", 1, true))
	end)
end)

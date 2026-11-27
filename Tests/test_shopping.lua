-- The shopping list (M13.4; SPEC-17 §5; ECO-01, ECO-05, ECO-06; SPEC-10 Q44, Q46): recipes and quantities, private and
-- per account; owned/needed from the inventory (bags, bank, an alt); the breakdown of intermediates changes the totals,
-- only for the missing part, 4 levels, no cycle; Ask the guild writes only the missing materials; Ask the bank prefills a
-- request with only what is missing and the bank shows; prices from a fake Auctionator, without it, with an API that
-- errors; live updates; the page; nothing moves items or gold; the switch "econ".
local function A() return AzerothAccord end
local function SH() return AzerothAccord.Shopping end
local function R() return AzerothAccord.Reagents end
local function V() return AzerothAccord.ShoppingView end

local ME, ALT = "Player-1-0000A001", "Player-1-0000A0A1"
local OFF, BOB = "Player-1-000000FF", "Player-1-00000B0B"
local TAILORING, FIRSTAID = 197, 129
local BOLT_R, SHIRT_R, BANDAGE_R = 3839, 3871, 3276        -- recipes
local SILK, BOLT, THREAD, SHIRT, LINEN, BANDAGE = 4306, 4305, 2321, 4334, 2589, 2581
local DAY = 86400

local function setup(features)
	return function(M)
		M.features = features or { econ = true }
		M.spells.known[BOLT_R] = { name = "Bolt of Silk Cloth", icon = 1 }
		M.spells.known[SHIRT_R] = { name = "Formal White Shirt", icon = 2 }
		M.spells.known[BANDAGE_R] = { name = "Heavy Linen Bandage", icon = 3 }
		for id, name in pairs({ [SILK] = "Silk Cloth", [BOLT] = "Bolt of Silk Cloth", [THREAD] = "Fine Thread",
			[LINEN] = "Linen Cloth", [SHIRT] = "Formal White Shirt", [BANDAGE] = "Heavy Linen Bandage" }) do
			M.items.info[id] = { name = name }
			M.items.cached[id] = true
		end
		M.tradeskill.schematics = {
			[BOLT_R] = M.tradeskill.Schematic(BOLT, 1, { SILK, 4 }),
			[SHIRT_R] = M.tradeskill.Schematic(SHIRT, 1, { BOLT, 3 }, { THREAD, 1 }),
			[BANDAGE_R] = M.tradeskill.Schematic(BANDAGE, 1, { LINEN, 2 }),
		}
		M.containers.Set(0, { { SILK, 10 }, { LINEN, 4 } })
		M.containers.Set(6, { { BOLT, 1 } })
		M.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Testchar", rank = 3, guid = ME, level = 60, class = "WARRIOR", online = true },
			{ name = "Officer", rank = 1, guid = OFF, level = 60, class = "PRIEST", online = true },
			{ name = "Bob", rank = 3, guid = BOB, level = 60, class = "MAGE", online = true },
		} }
	end
end

local function rows(result)
	local out = {}
	for _, r in ipairs((result or SH():Compute()).rows) do out[r.item] = r end
	return out
end

local function bank(items)
	A().BankRequests.BankItems = function()
		local out = {}
		for id, n in pairs(items) do out[id] = { itemID = id, available = n, time = GetServerTime() - 3600, author = OFF } end
		return out
	end
end

local function ready()
	Mock.Advance(2)
	Mock.containers.OpenBank()
	Mock.containers.CloseBank()
end

---------------------------------------------------------------------------------------------------------------------
describe("the list (SPEC-17 §5.1)", function()
	before_boot(setup())

	it("adds, grows, sets, removes and clears; per account, kept across a /reload", function()
		truthy(SH():Add(SHIRT_R, 2, TAILORING))
		eq(SH():Add(SHIRT_R, 3).n, 5, "the same recipe grows")
		eq(#SH():List(), 1)
		eq(SH():Set(SHIRT_R, 999).n, 999)
		isNil(SH():Set(SHIRT_R, 1000))
		eq(SH():Add(SHIRT_R, 5).n, 999, "never over 999")
		local _, why = SH():Add(BOLT_R, 0); eq(why, "count")
		Mock.Reload()
		eq(SH():List()[1].recipe, SHIRT_R)
		truthy(SH():Remove(SHIRT_R))
		eq(#SH():List(), 0)
		SH():Add(BOLT_R); SH():Add(BANDAGE_R)
		truthy(SH():Clear())
		eq(#SH():List(), 0)
	end)

	it("holds at most 50 recipes", function()
		for i = 1, SH().MAX_RECIPES do truthy(SH():Add(10000 + i)) end
		local e, why = SH():Add(20000)
		isNil(e); eq(why, "full")
	end)

	it("is not a record and sends nothing", function()
		ready()
		SH():Add(SHIRT_R, 2); SH():SetBreakdown(true); SH():Compute()
		Mock.Advance(3)
		eq(#Mock.chat.sent, 0)
		for set in pairs(A().Store.SETS) do
			for _, rec in pairs(A().Store:Records(set)) do isNil(rec.list) end
		end
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("owned and needed (the criterion of M13.4)", function()
	before_boot(setup())

	it("is right for the bags, the bank and an alt", function()
		ready()
		SH():Add(BANDAGE_R, 5, FIRSTAID)        -- 10 linen
		SH():Add(BOLT_R, 3, TAILORING)          -- 12 silk
		local r = rows()
		eq(r[LINEN].need, 10); eq(r[LINEN].owned, 4); eq(r[LINEN].missing, 6)
		eq(r[SILK].need, 12); eq(r[SILK].owned, 10); eq(r[SILK].missing, 2)
		Mock.Relog(60, function() Mock.player.guid, Mock.player.name = ALT, "Altchar" end)
		Mock.containers.Set(0, { { LINEN, 5 } }); Mock.containers.bags[6] = nil
		Mock.containers.Changed(); Mock.Advance(2)
		Mock.Relog(60, function() Mock.player.guid, Mock.player.name = ME, "Testchar" end)
		Mock.containers.Set(0, { { SILK, 10 }, { LINEN, 4 } }); Mock.containers.Changed(); Mock.Advance(2)
		r = rows()
		eq(r[LINEN].owned, 9, "bags 4 + the alt's 5"); eq(r[LINEN].missing, 1)
		eq(r[LINEN].count.alts[ALT], 5)
		SH():SetOption("alts", false)
		eq(rows()[LINEN].owned, 4, "Count alts off")
	end)

	it("missing first, then by name; Missing only hides the complete ones", function()
		ready()
		SH():Add(BANDAGE_R, 1)                   -- linen 2 of 4: enough
		SH():Add(BOLT_R, 3)                      -- silk 12 of 10: missing
		local list = SH():Compute().rows
		eq(list[1].item, SILK); eq(list[2].item, LINEN)
		SH():SetOption("missingOnly", true)
		eq(#SH():Compute().rows, 1)
	end)

	it("a recipe the game gave nothing for is counted apart, never as no materials", function()
		ready()
		SH():Add(9999)
		local result = SH():Compute()
		eq(result.unknown[1], 9999); eq(#result.rows, 0)
		matches(V().SummaryText(result), "unknown")
	end)

	it("updates while looting: SHOPPING_CHANGED after the bags are read", function()
		ready()
		SH():Add(BOLT_R, 3)
		Mock.Advance(1)
		local fired = 0
		A().Bus:On("SHOPPING_CHANGED", function() fired = fired + 1 end)
		Mock.containers.Set(0, { { SILK, 12 }, { LINEN, 4 } })
		Mock.containers.Changed()
		Mock.Advance(1)
		eq(fired, 1)
		eq(rows()[SILK].missing, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the intermediates (SPEC-17 §5.3)", function()
	before_boot(setup())

	it("MakerOf: the profession first, then the fewest materials, then the lowest id", function()
		R():Ensure(BOLT_R)
		eq(R():MakerOf(BOLT), BOLT_R)
		Mock.tradeskill.schematics[100] = Mock.tradeskill.Schematic(BOLT, 1, { SILK, 2 }, { THREAD, 1 })
		Mock.tradeskill.schematics[5000] = Mock.tradeskill.Schematic(BOLT, 1, { SILK, 9 })
		R():Ensure(100); R():Ensure(5000)
		eq(R():MakerOf(BOLT), BOLT_R, "one slot beats two, then the lower id")
		isNil(R():MakerOf(SILK))
	end)

	it("the switch changes the totals, breaking down only the missing part", function()
		ready()
		R():Ensure(BOLT_R)                       -- the bolt's recipe is known to this computer
		SH():Add(SHIRT_R, 2)                     -- 6 bolts and 2 thread; 1 bolt owned (bank)
		local r = rows()
		eq(r[BOLT].missing, 5); isNil(r[SILK], "off: the bolt is a material like the others")
		SH():SetBreakdown(true)
		r = rows()
		eq(r[BOLT].need, 6); eq(r[BOLT].broken, 5); eq(r[BOLT].missing, 0)
		eq(r[SILK].need, 20, "5 bolts x 4 silk, not 6"); eq(r[SILK].missing, 10)
		eq(r[THREAD].missing, 2)
		matches(V().MissingText(r[BOLT]), "1 owned, 5 broken down")
		local wants = {}
		for _, w in ipairs(SH().Wants(SH():Compute())) do wants[w.item] = w.n end
		deepEq(wants, { [SILK] = 10, [THREAD] = 2 }, "the bolt is asked through its silk")
	end)

	it("stops after 4 levels and never goes round a cycle", function()
		-- a chain 1 <- 2 <- 3 <- 4 <- 5 <- 6, and a cycle 7 <-> 8
		for i = 1, 5 do Mock.tradeskill.schematics[700 + i] = Mock.tradeskill.Schematic(i, 1, { i + 1, 1 }) end
		Mock.tradeskill.schematics[707] = Mock.tradeskill.Schematic(7, 1, { 8, 1 })
		Mock.tradeskill.schematics[708] = Mock.tradeskill.Schematic(8, 1, { 7, 1 })
		for i = 1, 8 do R():Ensure(700 + i) end
		Mock.tradeskill.schematics[800] = Mock.tradeskill.Schematic(99, 1, { 1, 1 }, { 7, 1 })
		SH():SetBreakdown(true)
		SH():Add(800, 1)
		local r = rows()
		truthy(r[5] and r[5].missing == 1, "level 4 is the last broken into")
		isNil(r[6], "never a fifth level")
		eq(r[7].broken, 1); eq(r[8].missing, 1, "the cycle stops at 8: 7 is on its branch")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("Ask the guild and Ask the bank (SPEC-17 §5.8)", function()
	before_boot(setup())

	it("Ask the guild writes only the missing materials, marked from the shopping list", function()
		ready()
		SH():Add(BANDAGE_R, 5)                   -- linen 6 missing
		SH():Add(BOLT_R, 1)                      -- silk enough
		local plan = SH():PlanGuild()
		eq(#plan.asked, 1); eq(plan.asked[1].item, LINEN); eq(plan.asked[1].n, 6)
		matches(V().GuildText(plan), "Linen Cloth × 6")
		truthy(SH():AskGuild())
		local own = A().Wishlist:Own()
		eq(#own, 1); eq(own[1].item, LINEN); eq(own[1].n, 6); eq(own[1].source, "sl")
	end)

	it("the page asks for a confirmation before anything is written", function()
		ready()
		SH():Add(BANDAGE_R, 5)
		V():Open()
		Mock.Advance(1)
		truthy(V():AskGuild())
		truthy(V().guildDialog:IsShown())
		eq(#A().Wishlist:Own(), 0, "nothing written yet")
		V().guildDialog.ok:Click()
		eq(#A().Wishlist:Own(), 1)
	end)

	it("Ask the bank lists only what is missing and the bank shows; Request prefills only what is missing", function()
		ready()
		SH():Add(BANDAGE_R, 5)                   -- linen: 6 missing
		SH():Add(BOLT_R, 3)                      -- silk: 2 missing
		SH():Add(SHIRT_R, 1)                     -- thread 1 missing (not in the bank), bolt 3 of 1: 2 missing
		bank({ [LINEN] = 40, [SILK] = 1, [SHIRT] = 9 })
		local list = SH():BankRows()
		local by = {}
		for _, b in ipairs(list) do by[b.item] = b end
		eq(by[LINEN].n, 6, "the missing part, not the bank's 40")
		eq(by[SILK].n, 1, "no more than the bank shows")
		isNil(by[THREAD], "the bank does not show it"); isNil(by[SHIRT], "not a material")
		V():Open(); Mock.Advance(1)
		V():BankList()
		truthy(V().bankDialog:IsShown())
		truthy(V():Request(by[LINEN]))
		Mock.Advance(1)
		local f = A().BankView.modes.requests.frame
		eq(f.item:GetText(), "Linen Cloth"); eq(f.amount:GetText(), "6")
		matches(f.reason:GetText(), "^Shopping list: ")
		f.send:Click()
		local held
		for _, rec in pairs(A().Store:Records("bankreq")) do held = rec end
		eq(held.itemID, LINEN); eq(held.count, 6); eq(held.kind, "withdraw")
		by = {}
		for _, b in ipairs(SH():BankRows()) do by[b.item] = b end
		truthy(by[LINEN].requested, "Already requested")
	end)

	it("the reason names the first recipes within 120 bytes", function()
		for i = 1, 30 do
			Mock.spells.known[30000 + i] = { name = "A rather long recipe name " .. i, icon = 1 }
			SH():Add(30000 + i)
		end
		Mock.Advance(1)
		SH():Reason()
		Mock.Advance(1)
		local reason = SH():Reason()
		truthy(#reason <= 120, #reason .. " bytes")
		matches(reason, "^Shopping list: A rather long recipe name 1")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("prices from Auctionator (SPEC-17 §5.7)", function()
	before_boot(setup())

	local function auctionator(v1)
		local get = C_AddOns.IsAddOnLoaded
		C_AddOns.IsAddOnLoaded = function(name) if name == "Auctionator" then return true, true end return get(name) end
		Auctionator = { API = { v1 = v1 } }
	end

	it("reads the price and its age, and sums the missing ones", function()
		ready()
		local callback
		auctionator({
			GetAuctionPriceByItemID = function(caller, item)
				eq(caller, "Azeroth Accord")
				return ({ [LINEN] = 150, [SILK] = 2000 })[item]
			end,
			GetAuctionAgeByItemID = function(_, item) return item == SILK and 9 or 1 end,
			RegisterForDBUpdate = function(_, fn) callback = fn end,
		})
		SH():Add(BANDAGE_R, 5); SH():Add(BOLT_R, 3)
		local result = SH():Compute()
		local r = rows(result)
		eq(r[LINEN].price, 150); eq(r[SILK].priceAge, 9)
		eq(result.cost, 6 * 150 + 2 * 2000); eq(result.costAge, 9)
		matches(V().SummaryText(result), "auction prices")
		local fired = 0
		A().Bus:On("PRICES_CHANGED", function() fired = fired + 1 end)
		callback()
		eq(fired, 1)
		matches(table.concat(A().Prices:DebugLines(), ""), "level 1")
	end)

	it("without Auctionator there is no price and one line says so", function()
		ready()
		Auctionator = nil
		SH():Add(BANDAGE_R, 5)
		local result = SH():Compute()
		isNil(rows(result)[LINEN].price)
		eq(A().Prices:Level(), 0)
		matches(V().SummaryText(result), "Install Auctionator")
	end)

	it("an API that errors drops to level 0 for the session, without errors on screen", function()
		ready()
		auctionator({ GetAuctionPriceByItemID = function() error("boom") end })
		SH():Add(BANDAGE_R, 5)
		isNil(rows()[LINEN].price)
		eq(A().Prices:Level(), 0)
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the page (SPEC-17 §5.6)", function()
	before_boot(setup())

	it("Add to list in the catalogue, then the page with its rows, the switch and the chips", function()
		ready()
		A().RecipeView:OpenCatalogue(TAILORING)
		Mock.Advance(1)
		truthy(V():Add(SHIRT_R, 1, TAILORING))
		eq(SH():List()[1].line, TAILORING)
		truthy(V():Open())
		Mock.Advance(1)
		local f = V().frame
		truthy(f:IsVisible())
		eq(#f.recipes:GetData(), 1)
		truthy(#f.mats:GetData() >= 2)
		f.breakdown:SetOn(true)
		truthy(SH():Options().breakdown)
		f.alts:Click()
		falsy(SH():Options().alts)
		Mock.TypeInto(A().Shell.content.bar.search, "thread")
		eq(#f.mats:GetData(), 1, "the panel's search filters the materials")
		-- a page of its own of Professions (M13.7): Recipes, Orders, Shopping list
		eq(A().Shell.content.dest, "professions")
		deepEq(A().Shell.content.tabs.order, { "professions", "orders", "shopping" })
		eq(A().Shell.content.tabs:Active(), "shopping")
		A().Shell.content.tabs.buttons.professions:Click()
		falsy(f:IsVisible())
		eq(#Mock.errors, 0)
	end)

	it("/accord shopping opens it", function()
		ready()
		Mock.Slash("/accord shopping")
		Mock.Advance(1)
		eq(A().Shell.selected, "shopping")
		truthy(V().frame:IsVisible())
	end)

	it("the tooltip of a material says every part with its age", function()
		ready()
		SH():Add(BANDAGE_R, 5)
		local tip = V().MaterialTip(rows()[LINEN])
		local text = {}
		for _, line in ipairs(tip) do text[#text + 1] = type(line) == "table" and line.text or line end
		text = table.concat(text, "\n")
		matches(text, "Bags 4"); matches(text, "Mail: never read")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("nothing moves items or gold (ECO-01)", function()
	before_boot(setup())

	it("the whole list, both asks and a request call none of the game's functions that would", function()
		local function stub(name) return function() error(name .. " was called", 0) end end
		for _, name in ipairs({ "InitiateTrade", "AcceptTrade", "SendMail", "TakeInboxItem", "TakeInboxMoney", "PlaceAuctionBid",
			"PickupGuildBankItem", "AutoStoreGuildBankItem", "PickupContainerItem", "UseContainerItem" }) do _G[name] = stub(name) end
		C_Container.PickupContainerItem = stub("C_Container.PickupContainerItem")
		C_Container.UseContainerItem = stub("C_Container.UseContainerItem")
		ready()
		Mock.mail.messages = { { items = { { LINEN, 3 } } } }
		Mock.mail.Open(); Mock.mail.Close()
		SH():Add(BANDAGE_R, 5); SH():SetBreakdown(true)
		bank({ [LINEN] = 40 })
		V():Open(); Mock.Advance(1)
		SH():AskGuild()
		V():Request(SH():BankRows()[1])
		A().BankView.modes.requests.frame.send:Click()
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the switch econ off", function()
	before_boot(setup({ econ = false }))

	it("no list, no page, no command, no Add to list", function()
		Mock.Advance(2)
		local e, why = SH():Add(SHIRT_R)
		isNil(e); eq(why, "off")
		falsy(V():Open())
		falsy(A().RecipeView:SetMode("shopping"))
		Mock.ClearOutput()
		Mock.Slash("/accord shopping")
		falsy(A().Shell.selected == "shopping")
		eq(#SH():Compute().rows, 0)
		eq(A().Prices:Level(), 0)
	end)
end)

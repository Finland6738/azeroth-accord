-- RecipeScan and the list encoding (M3.2; SPEC-06 §1, §3, SPEC-03 §3, PRO-06): the own recipes read from the profession
-- window, encoded as delta varints, hashed, and published at most once every 10 minutes per profession.
local function R() return AzerothAccord.Recipes end
local function Scan() return AzerothAccord.RecipeScan end
local function S() return AzerothAccord.Store end
local function C() return AzerothAccord.Compat end

local ME, BOB = "Player-1-0000A001", "Player-1-00000B0B"
local ALCHEMY, MINING, COOKING = 171, 186, 185

local function alchemy(recipes, rank)
	return { name = "Alchemy", skillLine = ALCHEMY, rank = rank or 250, maxRank = 300, recipes = recipes or { 2330, 2332, 3447 } }
end

local function setup(own)
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {} }
	Mock.tradeskill.AddAllRecipeIDs()
	Mock.tradeskill.own = own or { alchemy(), { name = "Mining", skillLine = MINING, rank = 200, maxRank = 300, recipes = { 2575, 2580 } } }
end

-- Opens profession `index` of Mock.tradeskill.own and lets the scan run.
local function open(index)
	Mock.tradeskill.open = index
	Mock.Fire("TRADE_SKILL_SHOW")
	Mock.Advance(Scan().DEBOUNCE + 0.5)
end

local function record(line) return S():Get("recipes", ME .. ":" .. (line or ALCHEMY)) end

describe("the list encoding", function()
	it("round-trips sorted spell ids as delta varints in Base64", function()
		for _, ids in ipairs({ { 1 }, { 2330, 2332, 3447 }, { 5, 6, 7, 1000, 2 ^ 20, 2 ^ 31 - 1 }, {} }) do
			local text = R().Encode(ids)
			eq(type(text), "string")
			falsy(text:find("[^A-Za-z0-9+/=]"), "plain text only")
			deepEq(R().Decode(text), ids)
		end
	end)

	it("sorts and de-duplicates before encoding, and drops anything that is not a spell id", function()
		deepEq(R().Decode(R().Encode({ 3447, 2330, 2330, 2332, 0, "x" })), { 2330, 2332, 3447 })
		isNil(R().Encode("nope"))
	end)

	it("takes about a byte and a half per recipe", function()
		local ids, id = {}, 2000
		for i = 1, 400 do id = id + 1 + (i * 7) % 90 ids[i] = id end   -- gaps of 1 to 90
		local text = R().Encode(ids)
		truthy(#text <= 400 * 1.5 * 4 / 3 + 4, "Base64 of about 1 byte per recipe: " .. #text)
		eq(#R().Decode(text), 400)
		-- a very large profession still fits the size limit of a record (8 KB)
		local big, v = {}, 0
		for i = 1, 1500 do v = v + 1 + (i * 37) % 400 big[i] = v end
		truthy(AzerothAccord.Config.EstimateSize({ ids = R().Encode(big), a = 1 }) < 8192)
	end)

	it("refuses a text that is not a list, never raising", function()
		eq(select(2, R().Decode(42)), "shape")
		eq(select(2, R().Decode("not base64!")), "base64")
		eq(select(2, R().Decode(("A"):rep(20000))), "shape")
		local C64 = C().Base64
		eq(select(2, R().Decode(C64.Encode("\128"))), "varint", "a number cut off")
		eq(select(2, R().Decode(C64.Encode("\0"))), "range", "a zero difference would repeat an id")
		eq(select(2, R().Decode(C64.Encode("\255\255\255\255\255\1"))), "varint", "too long")
		eq(select(2, R().Decode(C64.Encode("\255\255\255\255\127"))), "range", "beyond the spell id range")
		eq(select(2, R().Decode(C64.Encode(("\1"):rep(R().MAX_IDS + 1)))), "count")
		deepEq(R().Decode(""), {})
	end)

	it("the hash changes with the recipes and with the rank, not with anything else", function()
		local a = R().HashOf(171, 250, 300, "AAA")
		eq(R().HashOf(171, 250, 300, "AAA"), a)
		ne(R().HashOf(171, 251, 300, "AAA"), a)
		ne(R().HashOf(171, 250, 300, "AAB"), a)
		ne(R().HashOf(164, 250, 300, "AAA"), a)
	end)

	it("cooking, first aid and fishing are not primary professions", function()
		truthy(R().IsPrimary(171)); truthy(R().IsPrimary(164))
		falsy(R().IsPrimary(185)); falsy(R().IsPrimary(129)); falsy(R().IsPrimary(356))
	end)
end)

describe("scanning the profession window", function()
	before_boot(function() setup() end)

	it("reads the open profession and publishes one record per character and profession", function()
		open(1)
		local rec = record()
		notNil(rec)
		eq(rec.char, ME); eq(rec.author, ME); eq(rec.skillLine, ALCHEMY); eq(rec.name, "Alchemy")
		eq(rec.rank, 250); eq(rec.maxRank, 300); eq(rec.n, 3); eq(rec.rev, 1)
		deepEq(R().Decode(rec.ids), { 2330, 2332, 3447 })
		eq(rec.h, R().HashOf(ALCHEMY, 250, 300, rec.ids))
		eq(C():Feature("ownRecipes"), "available")
		open(2)
		deepEq(R().Decode(record(MINING).ids), { 2575, 2580 })
		eq(S():Count("recipes"), 2)
	end)

	it("waits for the end of a burst of window events, then scans once", function()
		Mock.tradeskill.open = 1
		for _ = 1, 5 do Mock.Fire("TRADE_SKILL_LIST_UPDATE") end
		Mock.Fire("TRADE_SKILL_SHOW")
		isNil(record(), "not yet")
		Mock.Advance(Scan().DEBOUNCE + 0.5)
		notNil(record())
		eq(Scan().state.stats.scans, 1)
	end)

	it("does not publish again while nothing changed", function()
		open(1)
		open(1)
		Mock.Fire("TRADE_SKILL_LIST_UPDATE"); Mock.Advance(3)
		eq(record().rev, 1)
		eq(Scan().state.stats.unchanged, 2)
	end)

	it("uses the skill line of the player's own profession when the window reports another id", function()
		Mock.tradeskill.open = 1
		local real = C_TradeSkillUI.GetBaseProfessionInfo
		C_TradeSkillUI.GetBaseProfessionInfo = function()
			return { professionID = 2823, professionName = "Alchemy", skillLevel = 99, maxSkillLevel = 300 }
		end
		Mock.Fire("TRADE_SKILL_SHOW"); Mock.Advance(3)
		C_TradeSkillUI.GetBaseProfessionInfo = real
		notNil(record(ALCHEMY), "matched by name to the own profession")
		isNil(record(2823))
		eq(record(ALCHEMY).rank, 250, "the rank of the own profession")
	end)

	it("publishes only the learned recipes of a list that also holds the unlearned ones", function()
		local known = { [2330] = true, [3447] = true }
		C_TradeSkillUI.GetAllRecipeIDs = function() return { 2330, 2332, 3447, 9000 } end
		C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id, learned = known[id] == true } end
		open(1)
		deepEq(R().Decode(record().ids), { 2330, 3447 })
	end)

	it("counts every id as known when the client gives no learned flag", function()
		C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id } end
		open(1)
		eq(record().n, 3)
	end)

	it("reads nothing when the client gives no recipe info at all: nothing is published from a guess", function()
		C_TradeSkillUI.GetRecipeInfo = function() return nil end
		open(1)
		isNil(record())
		eq(Scan().state.last, "skipped: noinfo")
	end)

	it("a scan from the filtered list can add recipes but never removes any", function()
		open(1)
		eq(record().n, 3)
		C_TradeSkillUI.GetAllRecipeIDs = nil
		C_TradeSkillUI.GetFilteredRecipeIDs = function() return { 2332 } end   -- the window's search shows one recipe
		Mock.Fire("TRADE_SKILL_LIST_UPDATE"); Mock.Advance(3)
		eq(record().n, 3, "the search did not shrink the list")
		C_TradeSkillUI.GetFilteredRecipeIDs = function() return { 2332, 5555 } end
		C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id, learned = true } end
		Mock.Fire("TRADE_SKILL_LIST_UPDATE"); Mock.Advance(3)
		Mock.Advance(Scan().PUBLISH_MIN)   -- the change waits for the ten-minute pause
		deepEq(R().Decode(record().ids), { 2330, 2332, 3447, 5555 }, "a new recipe is added")
	end)

	it("skips a closed window and a client without a recipe list API, and says so", function()
		Mock.tradeskill.open = nil
		Mock.Fire("TRADE_SKILL_SHOW"); Mock.Advance(3)
		eq(Scan().state.last, "skipped: closed")
		Mock.tradeskill.open = 1
		C_TradeSkillUI.GetAllRecipeIDs = nil
		Mock.Fire("TRADE_SKILL_SHOW"); Mock.Advance(3)
		eq(Scan().state.last, "skipped: norecipes")
		eq(C():Feature("ownRecipes"), "missing")
		eq(S():Count("recipes"), 0)
	end)

	it("a profession with no recipe publishes an empty list", function()
		Mock.tradeskill.own = { alchemy({}) }
		open(1)
		eq(record().n, 0); eq(record().ids, "")
		deepEq(R().Decode(record().ids), {})
	end)

	it("another character's records are never touched", function()
		S():Records("recipes")[BOB .. ":171"] = { id = BOB .. ":171", author = BOB, rev = 4, time = GetServerTime(), char = BOB, skillLine = 171 }
		open(1)
		eq(S():Get("recipes", BOB .. ":171").rev, 4)
	end)
end)

describe("without a guild", function()
	before_boot(function() Mock.tradeskill.AddAllRecipeIDs() Mock.tradeskill.own = { alchemy() } end)

	it("nothing is published and nothing fails", function()
		open(1)
		eq(S():Count("recipes"), 0)
		eq(select(2, Scan():Run()), "guild")
		eq(#Mock.errors, 0)
	end)
end)

describe("one publication per profession every ten minutes (PRO-06)", function()
	before_boot(function() setup() end)

	it("a change within the pause waits, and goes out with the latest state when the time is up", function()
		open(1)
		eq(record().rev, 1)
		Mock.tradeskill.own[1].recipes = { 2330, 2332, 3447, 4000 }
		Mock.tradeskill.own[1].rank = 260
		open(1)
		eq(record().rev, 1, "too soon")
		Mock.tradeskill.own[1].recipes = { 2330, 2332, 3447, 4000, 4001 }
		Mock.tradeskill.own[1].rank = 270
		open(1)
		eq(record().rev, 1, "still within the pause")
		eq(Scan().state.stats.deferred, 2)
		Mock.Advance(Scan().PUBLISH_MIN)
		local rec = record()
		eq(rec.rev, 2, "one publication for both changes")
		eq(rec.n, 5); eq(rec.rank, 270)
		Mock.Advance(2 * Scan().PUBLISH_MIN)
		eq(record().rev, 2, "and nothing more")
	end)

	it("the pause is per profession", function()
		open(1)
		Mock.tradeskill.own[1].rank = 251
		open(1)
		eq(record().rev, 1)
		open(2)
		notNil(record(MINING), "mining is not held back by alchemy")
		eq(record(MINING).rev, 1)
	end)

	it("a change that goes back to the published state needs no publication", function()
		open(1)
		Mock.tradeskill.own[1].rank = 251
		open(1)
		Mock.tradeskill.own[1].rank = 250
		open(1)
		Mock.Advance(Scan().PUBLISH_MIN + 5)
		eq(record().rev, 1)
		eq(Scan().state.stats.published, 1)
	end)

	it("the first scan of a new session publishes at once when the list changed while the addon was off", function()
		open(1)
		Mock.tradeskill.own[1].recipes = { 2330, 2332, 3447, 4000 }
		Mock.Reload()
		setup(); Mock.tradeskill.own[1].recipes = { 2330, 2332, 3447, 4000 }
		open(1)
		eq(record().rev, 2)
		eq(record().n, 4)
	end)

	it("a change of guild drops what waited, and its timer does nothing", function()
		open(1)
		Mock.tradeskill.own[1].rank = 251
		open(1)
		AzerothAccord.Bus:Emit("GUILD_CHANGED", "Realm/Other")
		Mock.Advance(Scan().PUBLISH_MIN + 5)
		eq(record().rev, 1)
	end)
end)

describe("what the guild gets", function()
	before_boot(function() setup() end)

	it("the published record passes the store's own rules, and a forged id is refused", function()
		open(1)
		local rec = S().Copy(record())
		truthy(S():Check("recipes", rec, { sender = "Testchar" }), "from the player itself")
		local bad = S().Copy(record())
		bad.id = ME .. ":999"
		eq(select(2, S():Check("recipes", bad, { sender = "Testchar" })), "owner", "an id that is not <GUID>:<skill line>")
	end)

	it("cooking is published like any profession but is not a profession cell in the roster", function()
		Mock.tradeskill.own = { { name = "Cooking", skillLine = COOKING, rank = 100, maxRank = 300, recipes = { 2538, 2540 } } }
		open(1)
		notNil(record(COOKING))
		Mock.guild.Set{ name = "Accord", myRank = 3, members = { { name = "Bob", guid = BOB, class = "MAGE" } } }
		S():Records("recipes")[BOB .. ":185"] = { id = BOB .. ":185", author = BOB, rev = 1, time = GetServerTime(), char = BOB, skillLine = 185 }
		S():Records("recipes")[BOB .. ":171"] = { id = BOB .. ":171", author = BOB, rev = 1, time = GetServerTime(), char = BOB, skillLine = 171 }
		AzerothAccord.Roster:Build()
		local bob = AzerothAccord.Roster:ByGUID(BOB)
		eq(#bob.professions, 1)
		eq(bob.professions[1].id, 171)
	end)

	it("/accord debug reports the scans", function()
		open(1)
		local text = AzerothAccord.Diagnostics.Report()
		truthy(text:find("RecipeScan: 1 scan(s), 1 published", 1, true))
	end)
end)

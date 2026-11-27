-- The guild recipe catalogue (SPEC-06 §1.5, §2.4; SPEC-03 §3.1): the whole profession read from the window (learned or
-- not), the `recipecat` record (merge that only grows, trust, size, update only on change), the merge with the members'
-- learned lists, the catalogue and member views of the Professions view, and one catalogue reaching the guild (simulator).
local function A() return AzerothAccord end
local function R() return AzerothAccord.Recipes end
local function Cat() return AzerothAccord.RecipeCatalogue end
local function Scan() return AzerothAccord.RecipeScan end
local function S() return AzerothAccord.Store end
local function V() return AzerothAccord.RecipeView end
local function Shell() return AzerothAccord.Shell end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-0000000F"
local ALCHEMY, MINING, LEATHER = 171, 186, 165

local NAMES = { [2330] = "Minor Healing Potion", [2332] = "Minor Rejuvenation Potion", [3447] = "Healing Potion",
	[4000] = "Elixir of Agility", [4001] = "Elixir of Defense" }
local LEVELS = { [2330] = 1, [2332] = 15, [3447] = 55, [4000] = 185, [4001] = 130 }

local function spells()
	for id, name in pairs(NAMES) do Mock.spells.known[id] = { name = name, icon = 100000 + id } end
end

local function guild()
	spells()
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = false },
		{ name = "Officer", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
	} }
	Mock.tradeskill.AddAllRecipeIDs()
	Mock.tradeskill.own = {
		{ name = "Alchemy", skillLine = ALCHEMY, rank = 120, maxRank = 150, recipes = { 2330, 2332 }, unlearned = { 3447, 4000, 4001 },
			levels = LEVELS },
		{ name = "Mining", skillLine = MINING, rank = 100, maxRank = 150, recipes = { 2575 } },
	}
end

local function openWindow(index)
	Mock.tradeskill.open = index or 1
	Mock.Fire("TRADE_SKILL_SHOW")
	Mock.Advance(Scan().DEBOUNCE + 0.5)
end

-- A shared list of a member, as the sync would have stored it.
local function put(guid, line, ids)
	local id = guid .. ":" .. line
	local old = S():Get("recipes", id)
	S():Records("recipes")[id] = { id = id, author = guid, rev = (old and old.rev or 0) + 1, time = GetServerTime() - 3600, char = guid,
		skillLine = line, name = "Alchemy", rank = 200, maxRank = 300, ids = R().Encode(ids), n = #ids }
	A().Roster:MarkDirty()
	A().Crafters:MarkDirty()
end

-- A catalogue record of another member, as it would arrive.
local function catalogue(author, line, ids, extra)
	local levels = {}
	for _, id in ipairs(ids) do levels[id] = LEVELS[id] end
	local text = R().Encode(ids)
	local sorted = R().Decode(text)
	local rec = { id = tostring(line), author = author, rev = 1, time = GetServerTime(), skillLine = line, name = "Alchemy",
		ids = text, lv = Cat().EncodeLevels(sorted, levels), n = #ids }
	for k, v in pairs(extra or {}) do rec[k] = v end
	return rec
end

local function from(sender) return { sender = sender, dist = "GUILD" } end

describe("the levels encoding", function()
	before_boot(function() guild() end)

	it("round-trips one level per id, 0 for an unknown one, and is absent when no level is known", function()
		local ids = { 2330, 2332, 3447, 4000 }
		local text = Cat().EncodeLevels(ids, { [2330] = 1, [3447] = 300, [4000] = 1000 })
		falsy(text:find("[^A-Za-z0-9+/=]"))
		deepEq(Cat().DecodeLevels(text, 4), { 1, 0, 300, 1000 })
		isNil(Cat().EncodeLevels(ids, {}))
		isNil(Cat().EncodeLevels(ids, { [2330] = 5000 }), "a level out of range counts as unknown")
	end)

	it("refuses a text that does not match the ids, never raising", function()
		local text = Cat().EncodeLevels({ 1, 2 }, { [1] = 5, [2] = 6 })
		isNil(Cat().DecodeLevels(text, 3)); isNil(Cat().DecodeLevels(text, 1))
		isNil(Cat().DecodeLevels("not base64!", 2)); isNil(Cat().DecodeLevels(42, 2))
	end)
end)

describe("reading the whole profession from the window", function()
	before_boot(function() guild() end)

	it("publishes the learned recipes in `recipes` and every recipe with its level in the catalogue", function()
		openWindow(1)
		local own = R():Shared(ME, ALCHEMY)
		deepEq(own.ids, { 2330, 2332 }, "only the learned ones in the member's list")
		local cat = Cat():Get(ALCHEMY)
		notNil(cat)
		deepEq(cat.ids, { 2330, 2332, 3447, 4000, 4001 })
		eq(cat.levels[4000], 185); eq(cat.levels[2330], 1); truthy(cat.hasLevels)
		eq(cat.author, ME); eq(cat.n, 5)
		local rec = S():Get("recipecat", "171")
		eq(rec.skillLine, ALCHEMY); eq(rec.author, ME); isNil(rec.names, "no recipe name is ever in the record")
		truthy(Scan():DebugLines()[3]:find("5 id%(s%), 5 with info, 2 learned, 5 with a required level"))
		truthy(Scan():DebugLines()[4]:find("learned, recipeID, requiredSkillLevel", 1, true), Scan():DebugLines()[4])
	end)

	it("reads the level from another field name the client may use, and goes on without levels", function()
		Mock.tradeskill.levelField = "minSkillLevel"
		openWindow(1)
		eq(Cat():Get(ALCHEMY).levels[3447], 55)
		Mock.tradeskill.levelField = "somethingElse"
		Mock.tradeskill.own[2].unlearned = { 2576 }
		openWindow(2)
		local mining = Cat():Get(MINING)
		deepEq(mining.ids, { 2575, 2576 }); falsy(mining.hasLevels)
		isNil(S():Get("recipecat", "186").lv)
	end)

	it("writes the catalogue again only when a read adds a recipe or a level, after the 10-minute pause", function()
		openWindow(1)
		local rev = S():Get("recipecat", "171").rev
		for _ = 1, 3 do
			Mock.Fire("TRADE_SKILL_LIST_UPDATE")
			Mock.Advance(Scan().DEBOUNCE + 0.5)
		end
		eq(S():Get("recipecat", "171").rev, rev, "the same profession again writes nothing")
		eq(Cat().state.stats.unchanged, 3)
		-- the client gives one more recipe: it waits for the pause, then goes out with the union
		local p = Mock.tradeskill.own[1]
		p.unlearned = { 3447, 4000, 4001, 4002 }
		Mock.Fire("TRADE_SKILL_LIST_UPDATE")
		Mock.Advance(Scan().DEBOUNCE + 0.5)
		eq(S():Get("recipecat", "171").rev, rev, "deferred")
		Mock.Advance(Cat().PUBLISH_MIN + 2)
		eq(S():Get("recipecat", "171").rev, rev + 1)
		deepEq(Cat():Get(ALCHEMY).ids, { 2330, 2332, 3447, 4000, 4001, 4002 })
	end)

	it("only grows: a window that lists fewer recipes removes nothing, a known level is never replaced", function()
		openWindow(1)
		local p = Mock.tradeskill.own[1]
		p.unlearned = { 3447 }
		p.levels = { [2330] = 1, [2332] = 99, [3447] = 55 }
		Mock.Advance(Cat().PUBLISH_MIN + 2)
		Mock.Fire("TRADE_SKILL_LIST_UPDATE")
		Mock.Advance(Scan().DEBOUNCE + 0.5)
		local cat = Cat():Get(ALCHEMY)
		eq(cat.n, 5); eq(cat.levels[2332], 15)
		eq(S():Get("recipecat", "171").rev, 1)
	end)

	it("fills a level the catalogue did not have", function()
		local held = { ids = { 2330, 2332 }, levels = { [2330] = 1 }, name = "Alchemy" }
		local fields = Cat().Merge(held, { skillLine = ALCHEMY, all = { 2330, 2332 }, levels = { [2332] = 15 } })
		notNil(fields)
		deepEq(Cat().DecodeLevels(fields.lv, 2), { 1, 15 })
		isNil(Cat().Merge(held, { skillLine = ALCHEMY, all = { 2330 }, levels = { [2330] = 7 } }), "nothing new")
		eq(select(2, Cat().Merge(nil, { skillLine = ALCHEMY, all = {} })), "empty")
	end)

	it("does not read a window that shows somebody else's recipes", function()
		Mock.tradeskill.linked = true
		openWindow(1)
		isNil(Cat():Get(ALCHEMY)); isNil(R():Shared(ME, ALCHEMY))
		truthy(Scan():DebugLines()[2]:find("others"))
		Mock.tradeskill.linked = false
		-- a primary profession the character does not have (the guild's view of a member, a link): not read either
		Mock.tradeskill.skillLines = true
		Mock.tradeskill.own[3] = { name = "Leatherworking", skillLine = LEATHER, recipes = { 2149 } }
		local own = Mock.tradeskill.own
		Mock.tradeskill.own = { own[1], own[2] }
		local readOwn = A().Compat.TradeSkill.OwnProfessions
		eq(#readOwn(), 2)
		Mock.tradeskill.own[3] = own[3]   -- the window shows it, but the Skills panel (first two lines read) has the others
		A().Compat.TradeSkill.OwnProfessions = function() return { readOwn()[1], readOwn()[2] } end
		openWindow(3)
		A().Compat.TradeSkill.OwnProfessions = readOwn
		isNil(Cat():Get(LEATHER))
		truthy(Scan():DebugLines()[2]:find("notown"))
	end)
end)

describe("trust and size of a catalogue record", function()
	before_boot(function() guild() end)

	it("takes a catalogue first hand from a member who has the profession", function()
		put(BOB, ALCHEMY, { 2330 })
		truthy(S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447 }), from("Bob")))
		deepEq(Cat():Get(ALCHEMY).ids, { 2330, 2332, 3447 })
		eq(Cat():Get(ALCHEMY).levels[3447], 55)
	end)

	it("a catalogue that arrives before its author's list waits for it", function()
		local ok, why = S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332 }), from("Bob"))
		falsy(ok); eq(why, "wait")
		eq(#Cat().waiting, 1)
		put(BOB, ALCHEMY, { 2330 })
		A().Bus:Emit("STORE_CHANGED", "recipes", BOB .. ":" .. ALCHEMY, "remote")
		notNil(Cat():Get(ALCHEMY), "taken once the list is here")
		eq(#Cat().waiting, 0)
	end)

	it("a waiting catalogue is dropped after a while and never kept forever", function()
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }), from("Bob"))
		Mock.Advance(Cat().WAIT + 5)
		put(BOB, ALCHEMY, { 2330 })
		A().Bus:Emit("STORE_CHANGED", "recipes", BOB .. ":" .. ALCHEMY, "remote")
		isNil(Cat():Get(ALCHEMY))
		for i = 1, Cat().WAIT_MAX + 10 do
			S():Accept("recipecat", catalogue(ANN, 1000 + i, { 2330 }), from("Bob"))   -- a relay: refused before waiting
		end
		eq(#Cat().waiting, 0)
		for i = 1, Cat().WAIT_MAX + 10 do S():Accept("recipecat", catalogue(BOB, 1000 + i, { 2330 }), from("Bob")) end
		eq(#Cat().waiting, Cat().WAIT_MAX)
	end)

	it("refuses a relay by a member, a wrong id, a text that is not a list, a bad level list and a record too big", function()
		put(BOB, ALCHEMY, { 2330 })
		eq(select(2, S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }), from("Ann"))), "relay")
		truthy(S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }, { rev = 2 }), from("Officer")), "an officer relays it")
		eq(select(2, S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }, { id = "172", rev = 3 }), from("Bob"))), "owner")
		eq(select(2, S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }, { ids = "not base64!", rev = 3 }), from("Bob"))), "owner")
		eq(select(2, S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }, { ids = "", rev = 3 }), from("Bob"))), "owner")
		eq(select(2, S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }, { lv = "AQID", rev = 3 }), from("Bob"))), "owner")
		local big = {}
		for i = 1, 3000 do big[i] = 100000 + i * 997 end
		local rec = catalogue(BOB, ALCHEMY, big, { rev = 3 })
		rec.pad = ("x"):rep(9000)
		eq(select(2, S():Accept("recipecat", rec, from("Bob"))), "size")
		eq(Cat():Get(ALCHEMY).n, 1)
	end)

	it("a whole Leatherworking of 600 recipes with their levels fits a record", function()
		local ids, levels, id = {}, {}, 2000
		for i = 1, 600 do id = id + 1 + (i * 37) % 700 ids[i] = id levels[id] = 1 + (i * 7) % 300 end
		local fields = Cat().Merge(nil, { skillLine = LEATHER, all = ids, levels = levels })
		local size = A().Config.EstimateSize(fields)
		T.log(("catalogue of 600 recipes with levels: %d bytes"):format(size))
		truthy(size <= 4096, "estimated " .. size)
	end)

	it("is summarised apart from the older sets", function()
		eq(S().SummaryKind("recipecat"), "extra")
	end)
end)

local function names(rows)
	local t = {}
	for _, r in ipairs(rows) do t[#t + 1] = (r.kind == "member" and ("  " .. r.member.name) or r.name) end
	return t
end

describe("the catalogue merged with the members' lists", function()
	before_boot(function() guild() end)

	local function model()
		local c = A().RecipeModel.Catalogue.new()
		c:SetProfession(ALCHEMY)
		c:SetFilter(nil)   -- every recipe (the view starts on "crafted")
		return c
	end

	it("starts on the recipes somebody in the guild can craft, and every profession picked starts there again", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 }), from("Bob"))
		local c = A().RecipeModel.Catalogue.new()
		eq(c.filter, "crafted")
		c:SetProfession(ALCHEMY)
		deepEq(names(c:Rows()), { "Minor Healing Potion", "Healing Potion" })
		local d = c:Describe()
		eq(d.shown, 2); eq(d.total, 4); eq(d.crafted, 2)
		c:SetFilter(nil)
		c:SetProfession(MINING)
		eq(c.filter, "crafted")
	end)

	it("says so when nobody can craft any recipe of the profession yet", function()
		Mock.tradeskill.own = {}
		S():Records("recipes")[OFF .. ":" .. ALCHEMY] = { id = OFF .. ":" .. ALCHEMY, author = OFF, rev = 1, time = GetServerTime(),
			char = OFF, skillLine = ALCHEMY, name = "Alchemy", ids = "", n = 0 }
		S():Accept("recipecat", catalogue(OFF, ALCHEMY, { 2330, 2332 }), from("Officer"))
		local c = A().RecipeModel.Catalogue.new()
		c:SetProfession(ALCHEMY)
		eq(#c:Rows(), 0)
		eq(c:Describe().message:sub(1, 42), "Nobody in the guild is known to craft a re")
	end)

	it("lists every recipe of the catalogue by required level, with how many guild characters can craft it", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		put(ANN, ALCHEMY, { 2330 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447, 4000, 4001 }), from("Bob"))
		local c = model()
		local rows = c:Rows()
		deepEq(names(rows), { "Minor Healing Potion", "Minor Rejuvenation Potion", "Healing Potion", "Elixir of Defense", "Elixir of Agility" })
		eq(rows[1].count, 2); eq(rows[2].count, 0); eq(rows[3].count, 1); eq(rows[1].level, 1); eq(rows[5].level, 185)
		local d = c:Describe()
		eq(d.status, "catalogue"); eq(d.total, 5); eq(d.crafted, 2); eq(d.shown, 5); eq(d.profession, "Alchemy")
		eq(d.sourceText:sub(1, 42), "Full list of the profession shared by Bob,")
	end)

	it("a recipe some member knows is listed even when the catalogue does not have it, and without catalogue the lists show", function()
		put(BOB, ALCHEMY, { 2330, 4000 })
		local c = model()
		eq(c:Describe().status, "lists")
		deepEq(names(c:Rows()), { "Elixir of Agility", "Minor Healing Potion" })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330 }), from("Bob"))
		c:Invalidate()
		eq(#c:Rows(), 2)
	end)

	it("opening a recipe lists who can craft it under it, online first; the filters keep crafted or uncrafted ones", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		put(ANN, ALCHEMY, { 2330 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447 }), from("Bob"))
		local c = model()
		truthy(c:Toggle(2330))
		deepEq(names(c:Rows()), { "Minor Healing Potion", "  Bob", "  Ann", "Minor Rejuvenation Potion", "Healing Potion" })
		falsy(c:Toggle(2330))
		c:SetFilter("nobody")
		deepEq(names(c:Rows()), { "Minor Rejuvenation Potion" })
		c:SetFilter("crafted")
		deepEq(names(c:Rows()), { "Minor Healing Potion", "Healing Potion" })
		c:SetFilter(nil)
		c:SetSearch("healing")
		deepEq(names(c:Rows()), { "Minor Healing Potion", "Healing Potion" })
		eq(c:Describe().shown, 2); eq(c:Describe().total, 3)
	end)

	it("a member who left the guild is not counted", function()
		put("Player-1-0000FFFF", ALCHEMY, { 2332 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2332 }), from("Officer"))
		put(BOB, ALCHEMY, { 2330 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332 }), from("Bob"))
		eq(model():Rows()[2].count, 0)
	end)

	it("offers the professions of the guild by name, the catalogue's size with them, and picks the player's own first", function()
		put(BOB, ALCHEMY, { 2330 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332 }), from("Bob"))
		local list = A().RecipeModel.Professions()
		eq(list[1].name, "Alchemy"); eq(list[1].recipes, 2); eq(list[1].lists, 1)
		eq(list[2].name, "Mining"); isNil(list[2].recipes)
		eq(A().RecipeModel.Catalogue.new():DefaultProfession(), ALCHEMY)
	end)

	it("a member's list starts on what the member learned; the missing ones are in the filter", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 }), from("Bob"))
		local m = A().RecipeModel.new()
		m:SetTarget(BOB, ALCHEMY)
		eq(m.category, "learned")
		deepEq(names(m:Rows()), { "Minor Healing Potion", "Healing Potion" })
		m:SetCategory(nil)
		local rows = m:Rows()
		eq(#rows, 4)
		eq(rows[1].name, "Minor Healing Potion"); eq(rows[1].learned, true); eq(rows[1].level, 1)
		eq(rows[2].name, "Minor Rejuvenation Potion"); eq(rows[2].learned, false)
		local d = m:Describe()
		eq(d.total, 4); eq(d.learned, 2); truthy(d.catalogue)
		eq(m:Categories()[2].label, "Learned by Bob"); eq(m:Categories()[3].label, "Not learned by Bob")
		m:SetCategory("missing")
		deepEq(names(m:Rows()), { "Minor Rejuvenation Potion", "Elixir of Agility" })
	end)
end)

local function visible()
	local out = {}
	for _, row in ipairs(V().frame.table.rows) do
		if row:IsShown() then out[#out + 1] = { name = row.name:GetText(), detail = row.detail:GetText(), note = row.note:GetText(), row = row } end
	end
	return out
end

describe("the Professions view opens on the guild's recipes", function()
	before_boot(function() guild() end)

	local function setup()
		put(BOB, ALCHEMY, { 2330, 3447 })
		put(ANN, ALCHEMY, { 2330 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 }), from("Bob"))
		Mock.Slash("/accord professions")
		V().frame.bar.category:Select(V().ALL)   -- every recipe
	end

	it("opens on the recipes the guild can craft; All recipes shows the rest", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		put(ANN, ALCHEMY, { 2330 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 }), from("Bob"))
		Mock.Slash("/accord professions")
		eq(V().frame.bar.category.label:GetText(), "Somebody can craft it")
		eq(V().frame.bar.count:GetText(), "2 of 4 recipes, 2 can be crafted in the guild")
		eq(#visible(), 2)
		V().frame.bar.category:Select(V().ALL)
		eq(#visible(), 4)
	end)

	it("a recipe's tooltip opens next to its name, not at the end of the row", function()
		setup()
		local row = visible()[1].row
		local at
		GameTooltip.SetPoint = function(_, ...) at = { ... } end
		GameTooltip.SetHyperlink = function() end
		V():ShowTooltip(row)
		eq(at[1], "LEFT"); eq(at[2], row.name); eq(at[3], "LEFT")
		local w = math.min(row.name:GetStringWidth(), row.name:GetWidth())
		eq(at[4], w + V().TIP_GAP)
		-- an open recipe's crafter: the addon's own tooltip, next to the character's name too
		row:Click()
		local member = visible()[2].row
		V():ShowTooltip(member)
		local _, rel, _, x = A().Widgets.Tooltip.Frame():GetPoint(1)
		eq(rel, member.name)
		eq(x, math.min(member.name:GetStringWidth(), member.name:GetWidth()) + V().TIP_GAP)
	end)

	it("shows every recipe of the profession with its level and how many can craft it", function()
		setup()
		eq(V().mode, "catalogue")
		eq(V().frame.head.title:GetText(), "Guild recipes - Alchemy")
		truthy(V().frame.bar.profession:IsShown())
		eq(V().frame.bar.profession.label:GetText(), "Alchemy (4 recipes)")
		eq(V().frame.bar.count:GetText(), "4 of 4 recipes, 2 can be crafted in the guild")
		local rows = visible()
		eq(#rows, 4)
		eq(rows[1].name, "Minor Healing Potion"); eq(rows[1].detail, "Skill 1"); eq(rows[1].note, "2 can craft it")
		eq(rows[2].note, "nobody yet")
		eq(rows[1].row.icon:GetTexture(), 100000 + 2330)
		falsy(rows[1].row.request:IsShown())
	end)

	it("a click on a recipe opens who can craft it, with Request craft for the online ones", function()
		setup()
		visible()[1].row:Click()
		local rows = visible()
		eq(rows[2].name, "Bob"); eq(rows[3].name, "Ann")
		truthy(rows[2].row.request:IsShown(), "Bob is online")
		falsy(rows[3].row.request:IsShown(), "Ann is offline")
		visible()[1].row:Click()
		eq(#visible(), 4, "a second click closes it")
	end)

	it("a click on a character opens their learned recipes, the missing ones one choice away; Back returns", function()
		setup()
		visible()[1].row:Click()
		visible()[2].row:Click()
		eq(V().mode, "recipes"); eq(V().cameFrom, "catalogue"); eq(V().model.guid, BOB)
		eq(V().frame.head.back:GetLabel(), "Back to guild recipes")
		eq(V().frame.bar.count:GetText(), "2 of 4 recipes, 2 learned")
		eq(V().frame.bar.category.label:GetText(), "Learned by Bob")
		eq(#visible(), 2)
		V().frame.bar.category:Select(V().ALL)
		eq(V().frame.bar.count:GetText(), "4 of 4 recipes, 2 learned")
		local rows = visible()
		eq(rows[2].name, "Minor Rejuvenation Potion"); eq(rows[2].note, "not learned")
		falsy(rows[2].row.request:IsShown(), "nobody asks Bob for a recipe Bob has not learned")
		truthy(rows[1].row.request:IsShown())
		V().frame.head.back:Click()
		eq(V().mode, "catalogue")
	end)

	it("a profession cell of a member opens their learned recipes; All members shows the guild's, crafted first", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		put(ANN, ALCHEMY, { 2330 })
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 }), from("Bob"))
		truthy(V():Open(BOB, ALCHEMY))
		eq(V().frame.bar.count:GetText(), "2 of 4 recipes, 2 learned")
		local all = V().frame.head.cat
		truthy(all:IsShown()); eq(all:GetLabel(), "All members")
		all:Click()
		eq(V().mode, "catalogue"); eq(V().cat.skillLine, ALCHEMY); eq(V().cat.filter, "crafted")
		eq(V().frame.bar.count:GetText(), "2 of 4 recipes, 2 can be crafted in the guild")
		eq(V().frame.head.cat:IsShown(), false)
	end)

	it("a click on the Professions tab shows the guild's recipes with the profession menu, on what can be crafted", function()
		setup()
		visible()[1].row:Click()
		visible()[2].row:Click()
		eq(V().mode, "recipes")
		Shell().content.tabs.buttons.professions:Click()
		eq(V().mode, "catalogue"); eq(V().cat.filter, "crafted")
		truthy(V().frame.bar.profession:IsShown())
		eq(V().frame.bar.count:GetText(), "2 of 4 recipes, 2 can be crafted in the guild")
		V():SetProfession(MINING)
		eq(V().cat.filter, "crafted", "a profession picked starts on what can be crafted")
	end)

	it("the profession select switches the profession, and the search box filters", function()
		setup()
		Mock.TypeInto(Shell().content.bar.search, "elixir")
		eq(#visible(), 1)
		V():SetProfession(MINING)
		eq(V().frame.head.title:GetText(), "Guild recipes - Mining")
		truthy(V().frame.message:IsShown())
		eq(V().frame.message:GetText():sub(1, 33), "Nothing is known about Mining yet")
	end)

	it("Who can craft and Guild recipes switch between the search and the catalogue", function()
		setup()
		V().frame.head.craft:Click()
		eq(V().mode, "craft")
		truthy(V().frame.head.cat:IsShown()); falsy(V().frame.head.back:IsShown())
		V().frame.head.cat:Click()
		eq(V().mode, "catalogue")
	end)

	it("a catalogue that arrives redraws the view", function()
		Mock.Advance(120)
		put(BOB, ALCHEMY, { 2330 })
		Mock.Slash("/accord professions")
		eq(V().frame.bar.count:GetText(), "1 of 1 recipes, 1 can be crafted in the guild")
		S():Accept("recipecat", catalogue(BOB, ALCHEMY, { 2330, 2332, 3447 }), from("Bob"))
		Mock.Advance(1)
		eq(V().frame.bar.count:GetText(), "1 of 3 recipes, 1 can be crafted in the guild", "the default filter keeps the one somebody can craft")
	end)

	it("names a profession nobody's client names from the guild's data", function()
		Mock.tradeskill.own = {}
		put(BOB, LEATHER, { 2149 })
		Mock.Slash("/accord professions")
		V():SetProfession(LEATHER)
		eq(V().frame.head.title:GetText(), "Guild recipes - Alchemy", "the shared record's name (the helper writes Alchemy)")
	end)
end)

describe("the Professions view in a guild where nothing is known", function()
	before_boot(function()
		guild()
		Mock.tradeskill.own = {}
	end)

	it("says how to fill it", function()
		Mock.Slash("/accord professions")
		eq(V().frame.message:GetText():sub(1, 41), "No profession is known in the guild yet. ")
	end)
end)

describe("one catalogue reaches the guild (simulator)", function()
	local function bigProfession()
		local learned, unlearned, levels, id = {}, {}, {}, 2000
		for i = 1, 593 do
			id = id + 1 + (i * 37) % 700
			if i % 3 == 0 then learned[#learned + 1] = id else unlearned[#unlearned + 1] = id end
			levels[id] = 1 + (i * 7) % 300
		end
		return learned, unlearned, levels
	end

	it("one window of 593 recipes reaches 20 clients once; a second member with the profession adds nothing", function()
		local learned, unlearned, levels = bigProfession()
		local sim = Sim.new{ clients = 20, officers = { 1, 11 }, latency = { 0.05, 0.5 }, seed = 61, setup = function(M, i)
			if i == 1 or i == 2 then
				M.tradeskill.AddAllRecipeIDs()
				M.tradeskill.own = { { name = "Leatherworking", skillLine = LEATHER, rank = 120, maxRank = 150,
					recipes = i == 1 and learned or { learned[1] }, unlearned = unlearned, levels = levels } }
				if i == 2 then
					local all = {}
					for _, x in ipairs(learned) do if x ~= learned[1] then all[#all + 1] = x end end
					for _, x in ipairs(unlearned) do all[#all + 1] = x end
					M.tradeskill.own[1].unlearned = all
				end
			end
		end }
		sim:advance(60)
		sim:resetStats()
		sim:client(1).Mock.tradeskill.open = 1
		sim:client(1).Mock.Fire("TRADE_SKILL_SHOW")
		local ok, took = sim:advanceUntil(function()
			for i = 1, 20 do
				if not sim:client(i):addon().Store:Get("recipecat", "165") then return false end
			end
			return true
		end, 120)
		truthy(ok, "all 20 clients hold the catalogue")
		local st = sim:stats()
		for i = 2, 20 do
			local c = sim:client(i):addon().RecipeCatalogue:Get(LEATHER)
			eq(c.n, 593, "client " .. i); eq(c.author, sim:client(1):guid())
		end
		T.log(("catalogue of 593 recipes + the learned list: %.1f s to reach 20 clients, %d message(s), %d bytes in all, %d by the author"):format(
			took, st.sent.msgs, st.sent.bytes, st.perClient[1].sent.bytes))
		truthy(st.perClient[1].sent.bytes <= 4096, "the author sent " .. st.perClient[1].sent.bytes)
		truthy(st.sent.bytes <= 6144, "the whole guild sent " .. st.sent.bytes)
		-- a second Leatherworker opens the same profession: their own list goes out, the catalogue does not
		sim:advance(60)
		local rev = sim:client(2):addon().Store:Get("recipecat", "165").rev
		sim:client(2).Mock.tradeskill.open = 1
		sim:client(2).Mock.Fire("TRADE_SKILL_SHOW")
		sim:advance(30)
		eq(sim:client(2):addon().Store:Get("recipecat", "165").rev, rev, "the catalogue was not written again")
		eq(sim:client(2):addon().RecipeCatalogue.state.stats.unchanged, 1)
		notNil(sim:client(3):addon().Store:Get("recipes", sim:client(2):guid() .. ":165"))
		eq(sim:client(3):addon().Crafters:CountOf(learned[1]), 2)
	end)
end)

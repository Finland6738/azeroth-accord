-- The recipe list of a member's profession (M3.4; SPEC-06 PRO-01..PRO-03): the model (rows, search, filters, sources, the
-- messages when there is no list), the Professions view that draws it, the clickable profession cells of the Roster
-- table and the lines of the member card.
local function A() return AzerothAccord end
local function R() return AzerothAccord.Recipes end
local function S() return AzerothAccord.Store end
local function V() return AzerothAccord.RecipeView end
local function Shell() return AzerothAccord.Shell end

local ME, BOB, ANN = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44"
local ALCHEMY, SMITHING = 171, 164

local NAMES = { [2330] = "Minor Healing Potion", [2332] = "Minor Rejuvenation Potion", [3447] = "Healing Potion", [4000] = "Elixir of Agility",
	[4001] = "Elixir of Defense" }

local function spells()
	for id, name in pairs(NAMES) do Mock.spells.known[id] = { name = name, icon = 100000 + id } end
end

local function guild(extra)
	Mock.club.fill.professions = true
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, zone = "Stormwind",
			professions = { { id = ALCHEMY, name = "Alchemy", rank = 285 }, { id = SMITHING, name = "Blacksmithing", rank = 75 } } },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN, online = false },
	} }
	if extra then extra() end
end

local function put(guid, line, ids, extra)
	local id = guid .. ":" .. line
	local old = S():Get("recipes", id)
	local rec = { id = id, author = guid, rev = (old and old.rev or 0) + 1, time = GetServerTime() - 3 * 86400, char = guid, skillLine = line,
		name = line == ALCHEMY and "Alchemy" or "Blacksmithing", rank = 285, maxRank = 300, ids = R().Encode(ids), n = #ids }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("recipes")[id] = rec
	A().Roster:MarkDirty()
	return rec
end

local function names(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.name end return t end

describe("the model", function()
	before_boot(function() guild() end)

	local function model(guid, line)
		local m = A().RecipeModel.new()
		m:SetTarget(guid or BOB, line or ALCHEMY)
		return m
	end

	it("lists the recipes of a shared list by name, with their icons, and describes the source and age (PRO-01, PRO-02)", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332, 3447 })
		local m = model()
		local d = m:Describe()
		eq(d.status, "list"); eq(d.title, "Bob"); eq(d.profession, "Alchemy"); eq(d.rank, 285); eq(d.maxRank, 300)
		eq(d.source, "shared"); eq(d.sourceText, "Source: shared by the member's addon, 3 d ago")
		eq(d.total, 3); eq(d.shown, 3)
		deepEq(names(m:Rows()), { "Healing Potion", "Minor Healing Potion", "Minor Rejuvenation Potion" })
		eq(m:Rows()[1].icon, 100000 + 3447)
	end)

	it("shows 'Recipe <id>' for a name the client has not loaded, asks for it, and sorts it last", function()
		spells()
		Mock.spells.known[3447] = nil
		Mock.spells.loadable[3447] = { name = "Healing Potion", icon = 7 }
		put(BOB, ALCHEMY, { 2330, 3447 })
		local m = model()
		deepEq(names(m:Rows()), { "Minor Healing Potion", "Recipe 3447" })
		eq(m.pending, 1)
		deepEq(Mock.spells.requests, { 3447 })
		local heard = {}
		A().Bus:On("RECIPE_NAMES_UPDATED", function(id) heard[#heard + 1] = id end)
		Mock.Advance(0.2)
		deepEq(heard, { 3447 })
		m:Invalidate()
		deepEq(names(m:Rows()), { "Healing Potion", "Minor Healing Potion" })
	end)

	it("searches by name or by spell id, case-insensitively", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 })
		local m = model()
		m:SetSearch("  POTION ")
		eq(#m:Rows(), 3)
		m:SetSearch("rejuv")
		deepEq(names(m:Rows()), { "Minor Rejuvenation Potion" })
		m:SetSearch("4000")
		deepEq(names(m:Rows()), { "Elixir of Agility" })
		falsy(m:SetSearch("4000"), "unchanged")
		m:SetSearch("")
		eq(#m:Rows(), 4)
	end)

	it("filters by the recipes the player knows and does not know in the same profession", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 })
		put(ME, ALCHEMY, { 2330, 4000 })
		local m = model()
		local cats = m:Categories()
		deepEq({ cats[1].label, cats[2].label, cats[3].label }, { "All recipes", "Recipes I know", "Recipes I do not know" })
		m:SetCategory("known")
		deepEq(names(m:Rows()), { "Elixir of Agility", "Minor Healing Potion" })
		m:SetCategory("unknown")
		deepEq(names(m:Rows()), { "Healing Potion", "Minor Rejuvenation Potion" })
		m:SetCategory(nil)
		eq(#m:Rows(), 4)
		truthy(m:Rows()[1].known ~= nil)
	end)

	it("offers no comparison without an own list, nor for the player's own list", function()
		put(BOB, ALCHEMY, { 2330 })
		eq(#model():Categories(), 1)
		put(ME, ALCHEMY, { 2330 })
		eq(#model(ME):Categories(), 1)
	end)

	it("offers the categories the client tells about, and difficulty colours", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332, 3447 })
		C_TradeSkillUI.GetRecipeInfo = function(id)
			return { recipeID = id, categoryID = id == 3447 and 20 or 10, relativeDifficulty = id == 2330 and 0 or nil }
		end
		C_TradeSkillUI.GetCategoryInfo = function(c) return { name = c == 10 and "Potions" or "Elixirs" } end
		local m = model()
		local cats = m:Categories()
		eq(#cats, 3); eq(cats[2].label, "Elixirs"); eq(cats[3].label, "Potions")
		m:SetCategory("cat:Potions")
		deepEq(names(m:Rows()), { "Minor Healing Potion", "Minor Rejuvenation Potion" })
		eq(m:Rows()[1].difficulty, 0)
		eq(m:Rows()[1].category, "Potions")
	end)

	it("says where the native list comes from, with the age of the shared one too", function()
		spells()
		put(BOB, ALCHEMY, { 2330 })
		Mock.tradeskill.guildEnabled = true
		Mock.tradeskill.guildRecipes = { [BOB] = { [ALCHEMY] = { 2330, 2332 } } }
		local m = model()
		Mock.Advance(0.5)
		m:Invalidate()
		local d = m:Describe()
		eq(d.source, "native")
		eq(d.sourceText, "Source: the game, just now; the member's addon list: 3 d ago")
		eq(d.total, 2)
	end)

	it("says it is the player's own list when it is (own scan)", function()
		put(ME, ALCHEMY, { 2330 }, { time = GetServerTime() })
		eq(model(ME):Describe().sourceText, "Source: your own profession window, read just now")
	end)

	it("PRO-03: with no list it says why and what to ask", function()
		local m = model()
		local d = m:Describe()
		eq(d.status, "none"); eq(d.total, 0)
		eq(d.message, "Nobody who has this list is online. Ask Bob to open their Alchemy window with Azeroth Accord: the list is shared at once.")
		-- the game gave no skill line for the profession
		m:SetTarget(BOB, nil)
		eq(m:Describe().message:sub(1, 40), "The game did not say which profession th")
		-- somebody is being asked
		Mock.tradeskill.guildEnabled = true
		m:SetTarget(BOB, ALCHEMY)
		eq(m:Describe().message, "Asking for Bob's recipes... the list appears here as soon as it arrives.")
	end)

	it("PRO-03: a member without the addon on a server without native lists is told so", function()
		A().Roster:Build()
		A().Roster:ByGUID(BOB).hasAddon = false
		local m = model()
		eq(m:Describe().message:sub(1, 44), "Bob does not seem to use Azeroth Accord, and")
	end)

	it("a list that exists but is empty says so", function()
		put(BOB, ALCHEMY, {})
		eq(model():Describe().message, "This profession has no recipe in the list.")
	end)

	it("a member who is not in the roster any more still has a title", function()
		put("Player-1-0000FFFF", ALCHEMY, { 2330 })
		eq(model("Player-1-0000FFFF"):Describe().title, "?")
	end)
end)

local function openRoster()
	Mock.Slash("/accord roster")
	return AzerothAccord.RosterView
end

local function rowOf(guid)
	for _, row in ipairs(AzerothAccord.RosterView.frame.table.rows) do
		if row:IsShown() and row.data and row.data.entry.guid == guid then return row end
	end
end

local function visibleNames()
	local out = {}
	for _, row in ipairs(V().frame.table.rows) do if row:IsShown() then out[#out + 1] = row.name:GetText() end end
	return out
end

describe("the Professions view", function()
	before_boot(function() guild() end)

	it("registers after the Roster, with the panel's search box", function()
		notNil(Shell().views.professions)
		eq(Shell().views.professions.label, "Professions"); eq(Shell().views.professions.order, 20)
		truthy(Shell().views.professions.search)
		local order = {}
		for i, v in ipairs(Shell():ViewList()) do order[v.id] = i end
		eq(order.professions, order.roster + 1)
	end)

	it("with nothing picked it opens on the who-can-craft search and says what to type", function()
		Mock.Slash("/accord professions")
		eq(V().mode, "craft")
		eq(V().frame.message:GetText(), "Type the name of an item or a recipe (at least two letters) in the search box above to see who can craft it.")
	end)

	it("Open shows the list of a member's profession: title with the rank, source, count and one row per recipe", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332, 3447 })
		truthy(V():Open(BOB, ALCHEMY))
		eq(Shell().selected, "professions")
		eq(V().frame.head.title:GetText(), "Bob - Alchemy 285/300")
		eq(V().frame.head.source:GetText(), "Source: shared by the member's addon, 3 d ago")
		eq(V().frame.bar.count:GetText(), "3 of 3 recipes")
		deepEq(visibleNames(), { "Healing Potion", "Minor Healing Potion", "Minor Rejuvenation Potion" })
		falsy(V().frame.message:IsShown())
		eq(V().frame.table.rows[1].icon:GetTexture(), 100000 + 3447)
	end)

	it("shows the message in place of the rows when there is no list, and the list when it arrives", function()
		spells()
		V():Open(BOB, ALCHEMY)
		truthy(V().frame.message:IsShown())
		eq(V().frame.message:GetText():sub(1, 19), "Nobody who has this")
		eq(#visibleNames(), 0)
		falsy(V().frame.bar.category:IsShown())
		local rec = put(BOB, ALCHEMY, { 2330, 2332 })
		A().Bus:Emit("STORE_CHANGED", "recipes", rec.id, "remote")
		Mock.Advance(1)   -- one redraw after the burst
		deepEq(visibleNames(), { "Minor Healing Potion", "Minor Rejuvenation Potion" })
		truthy(V().frame.bar.category:IsShown())
	end)

	it("the panel's search box filters the recipes and the count says so", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 })
		V():Open(BOB, ALCHEMY)
		Mock.TypeInto(Shell().content.bar.search, "elixir")
		deepEq(visibleNames(), { "Elixir of Agility" })
		eq(V().frame.bar.count:GetText(), "1 of 4 recipes")
		Mock.TypeInto(Shell().content.bar.search, "zzz")
		eq(V().frame.message:GetText(), "No recipe matches the search and the filter.")
		Mock.TypeInto(Shell().content.bar.search, "")
		eq(#visibleNames(), 4)
	end)

	it("the category select offers the comparison with the player's own recipes and filters", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332, 3447, 4000 })
		put(ME, ALCHEMY, { 2330 })
		V():Open(BOB, ALCHEMY)
		V().frame.bar.category:Click()
		local sel = V().frame.bar.category
		truthy(sel:IsOpen())
		eq(sel.list.rows[3].label:GetText(), "Recipes I do not know")
		sel.list.rows[3]:Click()
		eq(#visibleNames(), 3)
		eq(V().frame.bar.count:GetText(), "3 of 4 recipes")
		V():Open(BOB, ALCHEMY)
		eq(#visibleNames(), 4, "a new target clears the filter")
	end)

	it("marks the recipes the player knows too, and colours them by difficulty when the client says", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 3447 })
		put(ME, ALCHEMY, { 2330 })
		C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id, relativeDifficulty = id == 3447 and 1 or nil } end
		V():Open(BOB, ALCHEMY)
		local rows = V().frame.table.rows
		eq(rows[1].note:GetText(), "")          -- Healing Potion: not known by the player
		eq(rows[2].note:GetText(), "you know it") -- Minor Healing Potion
	end)

	it("the tooltip of a row is the game's own recipe tooltip", function()
		spells()
		put(BOB, ALCHEMY, { 2330 })
		V():Open(BOB, ALCHEMY)
		local linked
		GameTooltip.SetHyperlink = function(_, link) linked = link end
		V():ShowTooltip(V().frame.table.rows[1])
		eq(linked, "|cff71d5ff|Hspell:2330|h[Minor Healing Potion]|h|r")
	end)

	it("a long list uses a pool of rows and the wheel scrolls it", function()
		local ids = {}
		for i = 1, 300 do ids[i] = 10000 + i end
		put(BOB, ALCHEMY, ids)
		V():Open(BOB, ALCHEMY)
		local shown = #visibleNames()
		truthy(shown > 0 and shown < 40, "a pool as tall as the view: " .. shown)
		eq(V().frame.table.rows[1].name:GetText(), "Recipe 10001")
		V():Scroll(50)
		eq(V().frame.table.rows[1].name:GetText(), "Recipe 10051")
		truthy(V().frame.table.scroll:IsShown())
		falsy(V():Scroll(1000) and false)
		eq(V().frame.table.offset, 300 - V():VisibleRows())
	end)

	it("the list keeps its place when the data changes and starts at the top for another search or member (M6.13)", function()
		local ids = {}
		for i = 1, 300 do ids[i] = 10000 + i end
		put(BOB, ALCHEMY, ids)
		V():Open(BOB, ALCHEMY)
		V():Scroll(50)
		V():Redraw()
		eq(V().frame.table.offset, 50, "a redraw does not jump to the top")
		Mock.TypeInto(Shell().content.bar.search, "Recipe 10002")
		eq(V().frame.table.offset, 0, "a new search starts at the top")
		Mock.TypeInto(Shell().content.bar.search, "")
		V():Scroll(30)
		V():Open(BOB, ALCHEMY)
		eq(V().frame.table.offset, 0, "opening a list starts at the top")
	end)

	it("the names follow the theme: difficulty colours stay the game's, the other recipes use tokens (M6.13)", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 3447 })
		C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id, relativeDifficulty = id == 3447 and 1 or nil } end
		V():Open(BOB, ALCHEMY)
		local rows = V().frame.table.rows
		local function color(fs) local r, g, b = fs:GetTextColor() return { r, g, b } end
		deepEq(color(rows[1].name), { 1, 1, 0 })   -- Healing Potion: yellow, the game's own order
		local before = color(rows[2].name)
		AzerothAccord.Theme.Apply("aurora")
		deepEq(color(rows[1].name), { 1, 1, 0 }, "a game colour survives a change of theme")
		local r, g, b = AzerothAccord.Theme.Color("text-1", "aurora")
		deepEq(color(rows[2].name), { r, g, b })
		ne(color(rows[2].name)[1], before[1])
	end)

	it("names that load later redraw the list once", function()
		Mock.Advance(120)   -- the login's own work (the digest asks for the roster) is done: only the names redraw below
		Mock.spells.loadable[2330] = { name = "Minor Healing Potion", icon = 1 }
		Mock.spells.loadable[2332] = { name = "Minor Rejuvenation Potion", icon = 2 }
		put(BOB, ALCHEMY, { 2330, 2332 })
		V():Open(BOB, ALCHEMY)
		deepEq(visibleNames(), { "Recipe 2330", "Recipe 2332" })
		local before = V().drawn
		Mock.Advance(1)
		deepEq(visibleNames(), { "Minor Healing Potion", "Minor Rejuvenation Potion" })
		eq(V().drawn, before + 1, "one redraw for both names")
	end)

	it("Back returns to the roster", function()
		V():Open(BOB, ALCHEMY)
		V().frame.head.back:Click()
		eq(Shell().selected, "roster")
	end)

	it("opens nothing for a member that is not a GUID, and not outside a guild", function()
		falsy(V():Open(nil, ALCHEMY))
		Mock.guild.Leave()
		A().Bus:Emit("GUILD_CHANGED", nil)
		falsy(V():Open(BOB, ALCHEMY))
	end)

	it("forgets the member on a change of guild", function()
		V():Open(BOB, ALCHEMY)
		A().Bus:Emit("GUILD_CHANGED", "Realm/Other")
		isNil(V().model.guid)
	end)
end)

describe("from the Roster table and the member card", function()
	before_boot(function() guild() end)

	it("the profession cells show rank and maximum, and have a button that opens the recipes (PRO-01, PRO-02)", function()
		spells()
		put(BOB, ALCHEMY, { 2330, 2332 })
		openRoster()
		local row = rowOf(BOB)
		eq(row.cells[7]:GetText(), "Alchemy 285")   -- the game gives the rank only: it wins over the shared list
		local b = row.profButtons[7]
		notNil(b)
		truthy(b:IsShown())
		eq(b.slot, 1)
		eq(row.profButtons[8].slot, 2)
		b:Click()
		eq(Shell().selected, "professions")
		eq(V().model.guid, BOB); eq(V().model.skillLine, ALCHEMY)
		deepEq(visibleNames(), { "Minor Healing Potion", "Minor Rejuvenation Potion" })
	end)

	it("a member with no profession has no button, and a click on the rest of the row still selects", function()
		openRoster()
		local ann = rowOf(ANN)
		for _, b in pairs(ann.profButtons or {}) do falsy(b:IsShown()) end
		local selected
		A().Bus:On("ROSTER_SELECT", function(guid) selected = guid end)
		ann:Click()
		eq(selected, ANN)
	end)

	it("the tooltip of a profession cell gives the source and the age (PRO-01)", function()
		openRoster()
		local lines = AzerothAccord.RosterView.ProfessionTip(rowOf(BOB).data, 2)
		deepEq(lines, { "Blacksmithing 75", "From the game, read now.", "Click to see the recipes." })
		isNil(AzerothAccord.RosterView.ProfessionTip(rowOf(ANN).data, 1))
	end)

	it("a shared profession shows rank/max and its age in the tooltip", function()
		Mock.club.fill.professions = false
		put(BOB, ALCHEMY, { 2330 })
		openRoster()
		A().Roster:Build()
		local row = rowOf(BOB)
		eq(row.cells[7]:GetText(), "Alchemy 285/300")
		eq(AzerothAccord.RosterView.ProfessionTip(row.data, 1)[2], "Shared by Bob, updated 3 d ago.")
	end)

	it("a profession of the game without a skill line is found by name among the shared lists", function()
		Mock.club.fill.professions = true
		put(BOB, ALCHEMY, { 2330 })
		local e = { guid = BOB, professions = { { name = "alchemy", rank = 285, source = "native" } } }
		eq(V().SkillLineOf(e, e.professions[1]), ALCHEMY)
		isNil(V().SkillLineOf(e, { name = "Tailoring" }))
		eq(V().SkillLineOf(e, { id = 333 }), 333)
		isNil(V().SkillLineOf(e, nil))
	end)

	it("the member card lists the professions as lines that open the recipes", function()
		spells()
		put(BOB, ALCHEMY, { 2330 })
		openRoster()
		rowOf(BOB):Click()
		local card = A().MemberCard
		local line
		for _, s in ipairs(card.description.sections) do
			if s.id == "professions" then line = s.lines[1] end
		end
		notNil(line.onClick)
		line.onClick()
		eq(Shell().selected, "professions")
		eq(V().model.guid, BOB)
	end)
end)

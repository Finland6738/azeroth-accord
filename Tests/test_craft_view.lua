-- The "who can craft" mode of the Professions view (M3.5; SPEC-06 PRO-04): the search from the panel's box, rows grouped by
-- recipe and account with online members first, "online only", a click on a member opens their recipes and Back returns.
local function A() return AzerothAccord end
local function R() return AzerothAccord.Recipes end
local function S() return AzerothAccord.Store end
local function V() return AzerothAccord.RecipeView end
local function Shell() return AzerothAccord.Shell end

local ME, BOB, BOBALT, ANN, CID = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000A44", "Player-1-00000C1D"
local ALCHEMY = 171

local SPELLS = { [2330] = "Minor Healing Potion", [2332] = "Minor Rejuvenation Potion", [3447] = "Healing Potion", [4000] = "Elixir of Agility" }

local function guild()
	for id, name in pairs(SPELLS) do Mock.spells.known[id] = { name = name, icon = 1000 + id } end
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN, online = false },
		{ name = "Cid", level = 40, class = "ROGUE", rank = 3, guid = CID, online = true },
	} }
end

local function put(guid, line, ids)
	local id = guid .. ":" .. line
	local old = S():Get("recipes", id)
	S():Records("recipes")[id] = { id = id, author = guid, rev = (old and old.rev or 0) + 1, time = GetServerTime() - 3 * 86400, char = guid,
		skillLine = line, name = "Alchemy", rank = 285, maxRank = 300, ids = R().Encode(ids), n = #ids }
	A().Roster:MarkDirty()
	A().Crafters:MarkDirty()
end

local function accountBob()
	for guid, other in pairs({ [BOB] = BOBALT, [BOBALT] = BOB }) do
		S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T",
			chars = { { guid = guid, name = "x" }, { guid = other, name = "y" } } }
	end
	A().Accounts:MarkDirty()
end

local function open() Mock.Slash("/accord professions") V():SetMode("craft") end   -- the view opens on the catalogue
local function type_(text) Mock.TypeInto(Shell().content.bar.search, text) end

local function rows()
	local out = {}
	for _, row in ipairs(V().frame.table.rows) do
		if row:IsShown() then out[#out + 1] = { name = row.name:GetText(), detail = row.detail:IsShown() and row.detail:GetText() or nil, note = row.note:GetText(), row = row } end
	end
	return out
end

local function texts()
	local t = {}
	for i, r in ipairs(rows()) do t[i] = r.name .. (r.note ~= "" and (" [" .. r.note .. "]") or "") end
	return t
end

describe("the search", function()
	before_boot(function(M) guild() M.features = { memberRecipes = true } end)   -- the member list is switched off by default

	it("opens on the craft search with the hint, and the nav button is there", function()
		open()
		eq(V().mode, "craft")
		eq(V().frame.head.title:GetText(), "Who can craft")
		eq(V().frame.head.source:GetText():sub(1, 31), "Type an item or a recipe in the")
		falsy(V().frame.head.back:IsShown())
		falsy(V().frame.bar.category:IsShown())
		truthy(V().frame.bar.online:IsShown())
	end)

	it("the panel's search box takes the name; a recipe row is followed by its crafters, online first", function()
		put(ANN, ALCHEMY, { 2330, 3447 })
		put(CID, ALCHEMY, { 2330 })
		put(BOB, ALCHEMY, { 2330, 2332 })
		open()
		type_("minor healing")
		deepEq(texts(), { "Minor Healing Potion [3 can craft it]", "Bob [Online]", "Cid [Online]", "Ann" })
		eq(V().frame.bar.count:GetText(), "1 recipe(s)")
		falsy(V().frame.message:IsShown())
		eq(rows()[1].row.icon:GetTexture(), 1000 + 2330)
	end)

	it("a crafter row shows the profession, rank and where the list comes from", function()
		put(ANN, ALCHEMY, { 2330 })
		open(); type_("minor healing")
		eq(rows()[2].detail, "Alchemy 285/300 - shared by the member's addon, 3 d ago")
	end)

	it("the characters of one account are together, the alts indented", function()
		accountBob()
		put(ANN, ALCHEMY, { 2330 })
		put(BOBALT, ALCHEMY, { 2330 })
		put(BOB, ALCHEMY, { 2330 })
		open(); type_("minor healing")
		deepEq(texts(), { "Minor Healing Potion [3 can craft it]", "Bob [Online]", "Bobalt [Online]", "Ann" })
		eq(V().craft.rows[3].depth, 1, "the alt is indented under the first character of its account")
		eq(V().craft.rows[2].depth, 0)
	end)

	it("says what to type for a short text, and when nobody can craft it", function()
		put(BOB, ALCHEMY, { 3447 })
		open()
		type_("h")
		eq(V().frame.message:GetText():sub(1, 25), "Type the name of an item ")
		type_("elixir")
		eq(V().frame.message:GetText(), "Nobody in the guild is known to craft \"elixir\". Only members whose recipe list is known are searched: open a member's recipes to ask for theirs.")
		eq(#rows(), 0)
	end)

	it("Online only keeps the crafters who are online", function()
		put(ANN, ALCHEMY, { 2330 })
		put(BOB, ALCHEMY, { 2330 })
		open(); type_("minor healing")
		eq(#rows(), 3)
		V().frame.bar.online:Click()
		deepEq(texts(), { "Minor Healing Potion [1 can craft it]", "Bob [Online]" })
		V().frame.bar.online:Click()
		eq(#rows(), 3)
	end)

	it("a pasted item link counts as its name", function()
		put(BOB, ALCHEMY, { 3447 })
		open(); type_("|cffffffff|Hitem:118|h[Healing Potion]|h|r")
		eq(rows()[1].name, "Healing Potion")
	end)

	it("a list that arrives later appears in the results after the burst", function()
		open(); type_("minor healing")
		eq(#rows(), 0)
		local rec = put(BOB, ALCHEMY, { 2330 })
		A().Bus:Emit("RECIPES_UPDATED", BOB, ALCHEMY, "shared")
		eq(#rows(), 0, "not at once")
		Mock.Advance(1)
		deepEq(texts(), { "Minor Healing Potion [1 can craft it]", "Bob [Online]" })
	end)

	it("a long result is scrolled with the pool of rows", function()
		local ids = {}
		for i = 1, 60 do
			ids[i] = 40000 + i
			Mock.spells.known[ids[i]] = { name = "Test Potion " .. ("%02d"):format(i), icon = 1 }
		end
		put(BOB, ALCHEMY, ids)
		open(); type_("test potion")
		eq(V().frame.bar.count:GetText(), "Showing 40 of 60 recipes: type more of the name")
		local shown = #rows()
		truthy(shown > 0 and shown < 40)
		V():Scroll(30)
		eq(rows()[1].name:sub(1, 10), "Test Potio")
		truthy(V().frame.table.scroll:IsShown())
	end)
end)

describe("from the list of crafters to a member's recipes and back", function()
	before_boot(function(M) guild() M.features = { memberRecipes = true } end)   -- the member list is switched off by default

	it("a click on a crafter opens that member's list; Back and the header button return to the search", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		open(); type_("minor healing")
		rows()[2].row:Click()
		eq(V().mode, "recipes"); eq(V().cameFrom, "craft")
		eq(V().model.guid, BOB); eq(V().model.skillLine, ALCHEMY)
		eq(V().frame.head.title:GetText(), "Bob - Alchemy 285/300")
		truthy(V().frame.head.back:IsShown()); isNil(V().frame.head.craft)
		V().frame.head.back:Click()
		eq(V().mode, "craft")
		eq(Shell().content.bar.search:GetText(), "minor healing", "the box holds the craft query again")
		eq(rows()[1].name, "Minor Healing Potion")
		rows()[2].row:Click()
		V():SetMode("craft")
		eq(V().mode, "craft")
	end)

	it("each mode keeps its own search text in the panel's box", function()
		put(BOB, ALCHEMY, { 2330, 3447 })
		open(); type_("minor healing")
		V():Open(BOB, ALCHEMY)
		eq(Shell().content.bar.search:GetText(), "", "a new list starts with no filter")
		type_("healing")
		eq(#rows(), 2)
		V():SetMode("craft")
		eq(Shell().content.bar.search:GetText(), "minor healing")
	end)

	it("from the roster, Back goes to the roster", function()
		put(BOB, ALCHEMY, { 2330 })
		V():Open(BOB, ALCHEMY)
		eq(V().cameFrom, "roster")
		V().frame.head.back:Click()
		eq(Shell().selected, "roster")
	end)

	it("the tooltip of a crafter says who they are, what they craft and where the list comes from", function()
		put(BOB, ALCHEMY, { 2330 })
		open(); type_("minor healing")
		V():ShowTooltip(rows()[2].row)
		deepEq(AzerothAccord.Widgets.Tooltip.Lines(), { "Bob", "Can craft: Minor Healing Potion", "Alchemy 285/300 - shared by the member's addon, 3 d ago", "Click to see all their recipes." })
	end)

	it("OpenCraft shows the search with a given text", function()
		put(BOB, ALCHEMY, { 2330 })
		truthy(V():OpenCraft("minor healing"))
		eq(Shell().selected, "professions")
		eq(rows()[1].name, "Minor Healing Potion")
		eq(Shell().content.bar.search:GetText(), "minor healing")
	end)

	it("a change of guild clears the search and the member", function()
		open(); type_("minor healing")
		A().Bus:Emit("GUILD_CHANGED", "Realm/Other")
		eq(V().craft.query, "")
		eq(V().mode, "catalogue", "back to the guild's recipes")
	end)
end)

-- Request craft (M3.6; SPEC-06 PRO-05): a whisper with the recipe link already written, opened in the chat box for the
-- player to send. The addon never sends it.
local function A() return AzerothAccord end
local function R() return AzerothAccord.Recipes end
local function S() return AzerothAccord.Store end
local function V() return AzerothAccord.RecipeView end
local function Shell() return AzerothAccord.Shell end

local ME, BOB, ANN = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44"
local ALCHEMY = 171
local LINK = "|cff71d5ff|Hspell:2330|h[Minor Healing Potion]|h|r"

local function guild()
	Mock.spells.known[2330] = { name = "Minor Healing Potion", icon = 1 }
	Mock.spells.known[3447] = { name = "Healing Potion", icon = 2 }
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN, online = false },
	} }
end

local function put(guid, ids)
	local id = guid .. ":" .. ALCHEMY
	S():Records("recipes")[id] = { id = id, author = guid, rev = 1, time = GetServerTime() - 86400, char = guid, skillLine = ALCHEMY,
		name = "Alchemy", rank = 285, maxRank = 300, ids = R().Encode(ids), n = #ids }
	A().Roster:MarkDirty(); A().Crafters:MarkDirty()
end

local function capture()
	local box = { lines = {} }
	ChatFrame_OpenChat = function(text) box.lines[#box.lines + 1] = text end
	return box
end

describe("the whisper", function()
	before_boot(function() guild() end)

	it("the chat box opens with /w, the name and the text; a bad name or text opens nothing", function()
		local box = capture()
		truthy(A().Compat.Chat.OpenWhisper("Bob-Realm", "hello |cffffffff|Hitem:1|h[X]|h|r"))
		eq(box.lines[1], "/w Bob-Realm hello |cffffffff|Hitem:1|h[X]|h|r")
		truthy(A().Compat.Chat.OpenWhisper("Bob-Realm"))
		eq(box.lines[2], "/w Bob-Realm ")
		falsy(A().Compat.Chat.OpenWhisper("Bob-Realm", "two\nlines"))
		falsy(A().Compat.Chat.OpenWhisper("Bob-Realm", ("x"):rep(300)))
		falsy(A().Compat.Chat.OpenWhisper("Bob-Realm", 42))
		eq(#box.lines, 2)
	end)

	it("is written for one member and one recipe, with the link", function()
		local req = R():CraftRequest(BOB, 2330)
		eq(req.short, "Bob"); eq(req.link, LINK); eq(req.recipe, "Minor Healing Potion")
		eq(req.text, "Hello! Could you craft " .. LINK .. " for me? Thank you!")
		eq(req.name, A().Roster:ByGUID(BOB).name)
	end)

	it("builds the link from the name when the client gives none, and says when the recipe has no name", function()
		C_Spell.GetSpellLink = nil
		eq(R():CraftRequest(BOB, 2330).link, LINK)
		isNil(R():CraftRequest(BOB, 9999))
		eq(select(2, R():CraftRequest(BOB, 9999)), "noname")
	end)

	it("is refused for the player, for a member who is offline and for somebody who is not a member", function()
		eq(select(2, R():CraftRequest(ME, 2330)), "self")
		eq(select(2, R():CraftRequest(ANN, 2330)), "offline")
		eq(select(2, R():CraftRequest("Player-1-0000FFFF", 2330)), "member")
		eq(select(2, R():CraftRequest(nil, 2330)), "member")
	end)

	it("opens the chat box with the message and tells the Bus, and sends nothing", function()
		local box = capture()
		local sent = 0
		SendChatMessage = function() sent = sent + 1 end
		local before = #Mock.chat.sent
		local heard = {}
		A().Bus:On("CRAFT_REQUESTED", function(guid, id) heard[#heard + 1] = { guid, id } end)
		local ok, req = R():OpenCraftRequest(BOB, 2330)
		truthy(ok)
		eq(box.lines[1], "/w " .. A().Roster:ByGUID(BOB).name .. " Hello! Could you craft " .. LINK .. " for me? Thank you!")
		deepEq(heard, { { BOB, 2330 } })
		eq(sent, 0, "the addon never sends the whisper")
		eq(#Mock.chat.sent, before, "and no addon message either")
	end)

	it("fails honestly when the client cannot open the chat box", function()
		ChatFrame_OpenChat = nil
		local ok, why = R():OpenCraftRequest(BOB, 2330)
		falsy(ok); eq(why, "chat")
		falsy((R():OpenCraftRequest(ANN, 2330)))
	end)
end)

local function out() return table.concat(Mock.PlainOutput(), "\n") end
local function rowFor(i) return V().frame.area.rows[i] end

describe("the button in the recipe list", function()
	before_boot(function() guild() end)

	it("shows on each recipe of an online member, and a click opens the whisper", function()
		put(BOB, { 2330, 3447 })
		local box = capture()
		V():Open(BOB, ALCHEMY)
		truthy(rowFor(1).request:IsShown()); truthy(rowFor(2).request:IsShown())
		eq(rowFor(1).request:GetText() or rowFor(1).request.label:GetText(), "Request craft")
		rowFor(2).request:Click()   -- Minor Healing Potion (sorted: Healing Potion first)
		eq(box.lines[1]:sub(1, 3), "/w ")
		truthy(box.lines[1]:find("Minor Healing Potion", 1, true))
		truthy(out():find("Whisper to Bob ready in the chat box", 1, true))
	end)

	it("is not offered for an offline member or for the player's own list", function()
		put(ANN, { 2330 })
		V():Open(ANN, ALCHEMY)
		falsy(rowFor(1).request:IsShown())
		put(ME, { 2330 })
		V():Open(ME, ALCHEMY)
		falsy(rowFor(1).request:IsShown())
	end)

	it("the tooltip says whom the whisper goes to", function()
		put(BOB, { 2330 })
		V():Open(BOB, ALCHEMY)
		deepEq(V().RequestTip(rowFor(1).data), { "Request craft", "Opens a whisper to Bob with the recipe link already written. You read it and send it." })
	end)

	it("a failed chat box is reported in the chat", function()
		put(BOB, { 2330 })
		V():Open(BOB, ALCHEMY)
		ChatFrame_OpenChat = nil
		rowFor(1).request:Click()
		truthy(out():find("The chat box could not be opened with the whisper.", 1, true))
	end)

	it("a member who went offline meanwhile is told so", function()
		put(BOB, { 2330 })
		V():Open(BOB, ALCHEMY)
		capture()
		A().Roster:ByGUID(BOB).online = false
		rowFor(1).request:Click()
		truthy(out():find("That member is not online", 1, true))
	end)
end)

describe("the button in who can craft", function()
	before_boot(function() guild() end)

	it("is on the online crafters only, never on the recipe row", function()
		put(BOB, { 2330 })
		put(ANN, { 2330 })
		local box = capture()
		Mock.Slash("/accord professions")
		Mock.TypeInto(Shell().content.bar.search, "minor healing")
		local rows = V().frame.area.rows
		falsy(rows[1].request:IsShown(), "the recipe row")
		truthy(rows[2].request:IsShown(), "Bob is online")
		falsy(rows[3].request:IsShown(), "Ann is not")
		rows[2].request:Click()
		truthy(box.lines[1]:find("Minor Healing Potion", 1, true))
		eq(V().mode, "craft", "the click on the button does not open the member's list")
	end)

	it("the member row still opens the member's list", function()
		put(BOB, { 2330 })
		Mock.Slash("/accord professions")
		Mock.TypeInto(Shell().content.bar.search, "minor healing")
		V().frame.area.rows[2]:Click()
		eq(V().mode, "recipes")
	end)
end)

-- The member card (M2.4; SPEC-05 §2): its content (Card.Describe), the officers' note permission, the characters of the
-- same account, and the frame beside or over the Roster table.
local function A() return AzerothAccord end
local function Card() return A().MemberCard end
local function V() return A().RosterView end

local BOB, BOBALT, ANN, LONE = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000A01", "Player-1-00000E0E"
local OUT = "Player-1-0000CC01"

local seeded, seed
local function setup()
	local a = AzerothAccord
	if seeded ~= a then seeded = a seed(a) end
	return a
end

local function mockGuild()
	Mock.club.fill.professions = true
	Mock.guild.Set{ name = "Accord", myRank = 1, members = {
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN, zone = "Ironforge", note = "Raid lead", officerNote = "Trial passed",
			professions = { { id = 171, name = "Alchemy", rank = 300 } } },
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, online = false, lastOnline = { 0, 0, 3, 0 }, zone = "Stormwind" },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT },
		{ name = "Lone", level = 20, class = "ROGUE", rank = 3, guid = LONE, note = "main: Ann" },
	} }
end

seed = function(a)
	local S = a.Store
	local function acct(guid, list, extra)
		local rec = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T", chars = list, addonVersion = "0.2.0" }
		S:Records("accounts")[guid] = rec
	end
	acct(BOB, { { guid = BOB, name = "Bob", level = 50 }, { guid = BOBALT, name = "Bobalt", level = 30 },
		{ guid = OUT, name = "Elsewhere", level = 12, classID = 3 } })
	acct(BOBALT, { { guid = BOBALT, name = "Bobalt", level = 30 }, { guid = BOB, name = "Bob", level = 50 } })
	S:Records("recipes")[BOB .. ":164"] = { id = BOB .. ":164", author = BOB, rev = 1, time = GetServerTime() - 3 * 86400, char = BOB,
		skillLine = 164, name = "Blacksmithing", rank = 75, maxRank = 300 }
	a.Roster:MarkDirty(); a.Accounts:MarkDirty()
end

local function text(d, sectionId)
	for _, s in ipairs(d.sections) do
		if s.id == sectionId then
			local out = {}
			for _, l in ipairs(s.lines) do out[#out + 1] = l.text end
			return out, s
		end
	end
end

local function desc(guid) setup() return Card().Describe(A().Roster:ByGUID(guid)) end

describe("the content", function()
	before_boot(function() mockGuild() end)

	it("has the title, the level and class, and the details of a member who is online", function()
		local d = desc(ANN)
		eq(d.title, "Ann"); eq(d.subtitle, "Level 60 Priest"); eq(d.classFile, "PRIEST")
		deepEq(text(d, "details"), { "Zone: Ironforge", "Online now", "Rank: Officer", "Note: Raid lead", "Officer note: Trial passed", "No Azeroth Accord detected." })
	end)

	it("says when an offline member was last seen, and shows the addon version", function()
		local lines = text(desc(BOB), "details")
		eq(lines[2], "Last online: 3 d ago")
		eq(lines[#lines], "Uses Azeroth Accord 0.2.0")
	end)

	it("shows the officers' note only when the game lets the player read it", function()
		Mock.guild.officerNoteVisible = false
		for _, l in ipairs(text(desc(ANN), "details")) do falsy(l:find("Officer note", 1, true)) end
		Mock.guild.officerNoteVisible = true
		local found = false
		for _, l in ipairs(text(desc(ANN), "details")) do if l:find("Officer note", 1, true) then found = true end end
		truthy(found)
		Mock.guild.officerNoteVisible = nil
		A().Compat.Guild.CanViewOfficerNote = function() return false end
		for _, l in ipairs(text(desc(ANN), "details")) do falsy(l:find("Officer note", 1, true), "also when the client hands the note over") end
	end)

	it("lists the professions with where each comes from", function()
		eq(text(desc(ANN), "professions")[1], "Alchemy 300 (from the game)")
		local bob = text(desc(BOB), "professions")
		eq(bob[1], "Blacksmithing 75 (shared by the member, 3 d ago)")
		local _, section = text(desc(BOB), "professions")
		truthy(section.lines[1].muted)
		eq(text(desc(LONE), "professions")[1], "The game does not give this member's professions, and they do not use Azeroth Accord.")
		Mock.tradeskill.own = { { name = "Mining", skillLine = 186, rank = 200, maxRank = 300 } }
		A().Roster:MarkDirty()
		eq(text(desc("Player-1-0000A001"), "professions")[1], "Mining 200 (read from your own character)")
	end)

	it("says so when the member has the addon but nothing was shared yet", function()
		setup()
		A().Store:Records("accounts")[ANN] = { id = ANN, author = ANN, rev = 1, time = GetServerTime(), token = "T", chars = { { guid = ANN } } }
		Mock.club.fill.professions = false
		A().Roster:MarkDirty()
		eq(text(desc(ANN), "professions")[1], "No profession data yet.")
	end)

	it("lists all the characters of the account, also outside the guild, main first (ACC-03)", function()
		local lines = text(desc(BOBALT), "account")
		deepEq(lines, { "Bob (50 Mage) - main", "Elsewhere (12 Hunter) - not in guild" })
		local d = desc(BOBALT)
		local _, section = text(d, "account")
		eq(section.lines[1].guid, BOB)
		truthy(section.lines[2].muted)
	end)

	it("tells the main that it is the main, and the others who the alts are", function()
		local lines = text(desc(BOB), "account")
		eq(lines[1], "This is the main character.")
		eq(lines[2], "Bobalt (30 Warrior)")
	end)

	it("marks what the guild note declared", function()
		local lines = text(desc("Player-1-0000A001"), "account")
		deepEq(lines, { "No other character known." })
		local lone = text(desc(LONE), "account")
		eq(lone[1], "Ann (60 Priest) - main, declared in the note")
	end)

	it("describes a character outside the guild from what the account lists", function()
		setup()
		local e = Card().EntryFor(OUT)
		truthy(e.notInGuild)
		local d = Card().Describe(e)
		eq(d.title, "Elsewhere"); eq(d.subtitle, "Level 12 Hunter")
		eq(text(d, "details")[1], "Not in this guild: listed by the member's other characters.")
		isNil(Card().EntryFor("Player-1-00000000"))
		isNil(Card().EntryFor(nil))
	end)

	it("lets later steps add sections, ordered, and survives one that fails", function()
		setup()
		Card().AddSection("late", 20, function(e) return { id = "late", title = "Late", lines = { { text = "x" } } } end)
		Card().AddSection("early", 10, function(e) return { id = "early", title = "Early", lines = { { text = "y" } } } end)
		Card().AddSection("broken", 15, function(e) error("boom") end)
		Card().AddSection("none", 16, function(e) return nil end)
		local d = desc(ANN)
		eq(#d.sections, 5)
		eq(d.sections[4].id, "early"); eq(d.sections[5].id, "late")
		isNil(Card().Describe("nope"))
	end)
end)

describe("the frame", function()
	before_boot(function() mockGuild() end)

	local function open()
		setup()
		Mock.Slash("/accord roster")
		Mock.Advance(2)
	end

	local function rowOf(name)
		for _, r in ipairs(V().frame.area.rows) do
			if r:IsShown() and r.cells[1]:GetText() == name then return r end
		end
	end

	it("a click on a row opens the card beside the table and makes room for it", function()
		open()
		V().frame:SetWidth(900)
		falsy(Card():IsShown())
		rowOf("Bob"):Click()
		truthy(Card():IsShown())
		eq(Card().frame:GetParent(), V().frame)
		eq(Card().frame.title:GetText(), "Bob")
		eq(Card().frame.subtitle:GetText(), "Level 50 Mage")
		falsy(Card().narrow)
		eq(Card().frame:GetWidth(), Card().WIDTH)
		eq(V().inset, Card().WIDTH + 4)
		local _, _, _, x = V().frame.area:GetPoint(2)
		eq(x, -14 - (Card().WIDTH + 4))
		truthy(Card().frame.close:IsShown()); falsy(Card().frame.back:IsShown())
	end)

	it("draws the sections and the lines, reusing the same frames for the next member", function()
		open()
		rowOf("Bob"):Click()
		local items = Card().frame.items
		local texts = {}
		for _, it in ipairs(items) do if it:IsShown() then texts[#texts + 1] = it.text:GetText() end end
		eq(texts[1], "Details")
		contains(table.concat(texts, "|"), "Blacksmithing 75 (shared by the member, 3 d ago)")
		contains(table.concat(texts, "|"), "Elsewhere (12 Hunter) - not in guild")
		local count = #items
		rowOf("Ann"):Click()
		eq(Card().frame.title:GetText(), "Ann")
		truthy(#items <= count + 4)
	end)

	it("is over the table in a narrow panel, with a Back button", function()
		open()
		V().frame:SetWidth(600)
		rowOf("Bob"):Click()
		truthy(Card().narrow)
		eq(V().inset, 0)
		truthy(Card().frame.back:IsShown()); falsy(Card().frame.close:IsShown())
		local _, relative = Card().frame:GetPoint(1)
		eq(relative, V().frame.toolbar)
		Card().frame.back:Click()
		falsy(Card():IsShown())
	end)

	it("a click on another character of the account opens its card and selects it", function()
		open()
		V().frame:SetWidth(900)
		rowOf("Bobalt"):Click()
		local target
		for _, it in ipairs(Card().frame.items) do if it:IsShown() and it.guid == BOB then target = it end end
		notNil(target)
		target:Click()
		eq(Card().frame.title:GetText(), "Bob")
		eq(V().selected, BOB)
		-- a character outside the guild opens too
		for _, it in ipairs(Card().frame.items) do if it:IsShown() and it.guid == OUT then target = it end end
		target:Click()
		eq(Card().frame.title:GetText(), "Elsewhere")
		eq(Card().entry.notInGuild, true)
	end)

	it("the close button closes the card, clears the selection and gives the room back", function()
		open()
		V().frame:SetWidth(900)
		rowOf("Bob"):Click()
		Card().frame.close:Click()
		falsy(Card():IsShown())
		isNil(V().selected)
		eq(V().inset, 0)
		for _, r in ipairs(V().frame.area.rows) do falsy(r.selected:IsShown() and r.data.entry.guid == BOB) end
	end)

	it("follows the data while open and closes when the member leaves the roster", function()
		open()
		V().frame:SetWidth(900)
		rowOf("Ann"):Click()
		Mock.guild.members[1].note = "Changed note"
		A().Roster:MarkDirty()
		A().Bus:Emit("ROSTER_UPDATED", 4)
		local seen = false
		for _, it in ipairs(Card().frame.items) do if it:IsShown() and it.text:GetText() == "Note: Changed note" then seen = true end end
		truthy(seen)
		table.remove(Mock.guild.members, 1)
		A().Roster:MarkDirty()
		A().Bus:Emit("ROSTER_UPDATED", 3)
		falsy(Card():IsShown())
	end)

	it("closes when the character changes guild, and never raises an error", function()
		open()
		rowOf("Bob"):Click()
		A().Bus:Emit("GUILD_CHANGED", nil, "TestRealm/Accord")
		falsy(Card():IsShown())
		eq(#Mock.errors, 0)
	end)
end)

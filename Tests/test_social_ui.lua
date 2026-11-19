-- The social index in the interface (M4.5; SPEC-07 SOC-04, SOC-05, SOC-12, SPEC-10 Q3): the card section with the index,
-- effective and distinct partners, the time and the top five shares, its explanation tooltip, the Social column, the
-- Social mode of the Reputation view, and who sees what (everyone their own, officers everyone's).
local function A() return AzerothAccord end
local function So() return AzerothAccord.Social end
local function UI() return AzerothAccord.SocialUI end
local function S() return AzerothAccord.Store end
local function Card() return AzerothAccord.MemberCard end

local ME = "Player-1-0000A001"
local BOB, CAT, DAN, EVE, FAY, GUS = "Player-1-00000B0B", "Player-1-00000CA7", "Player-1-00000DA1", "Player-1-00000E0E", "Player-1-00000FA1",
	"Player-1-00000C05"

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB }, { name = "Cat", level = 60, class = "ROGUE", rank = 3, guid = CAT },
		{ name = "Dan", level = 60, class = "HUNTER", rank = 3, guid = DAN }, { name = "Eve", level = 60, class = "PRIEST", rank = 3, guid = EVE },
		{ name = "Fay", level = 60, class = "DRUID", rank = 3, guid = FAY }, { name = "Gus", level = 60, class = "PALADIN", rank = 1, guid = GUS },
	} }
end

local function pairKey(a, b) if a > b then a, b = b, a end return a .. ":" .. b end
local n = 0
local function observe(list)
	n = n + 1
	local p = {}
	for _, x in ipairs(list) do p[pairKey(x[1], x[2])] = x[3] end
	local id = ME .. ":" .. n
	S():Records("coplay")[id] = { id = id, author = ME, rev = 1, time = GetServerTime(), day = A().Compat.ServerDay(), observer = ME, pairs = p }
end

-- I played 6 hours: 3 with Bob, 1 each with Cat, Dan and Eve; Fay and Gus played 2 hours together (under 5 hours each)
local function world()
	observe({ { ME, BOB, 180 }, { ME, CAT, 60 }, { ME, DAN, 60 }, { ME, EVE, 60 }, { FAY, GUS, 120 } })
	So():ComputeNow()
end

local function texts(d)
	local out = {}
	for i, l in ipairs(d.lines) do out[i] = l.text end
	return out
end

describe("for a member", function()
	before_boot(function() guild(3) end)

	it("the own card shows the index, effective and distinct partners, the time and the top shares", function()
		world()
		local d = UI().Describe(ME)
		local t = texts(d)
		local e = So():ForGUID(ME)
		eq(t[1], ("Social index: %d / 100"):format(e.index))
		eq(t[2], ("Effective partners: %.1f (of 7 active players)"):format(e.effective))
		eq(t[3], "Different partners: 4")
		eq(t[4], "Time with guildmates: 6.0 h (counted per guildmate)")
		eq(t[5], "Played with most:")
		eq(t[6], "  Bob: 50%")
		eq(t[7], "  Cat: 17%")
		eq(#t, 9)
		eq(d.lines[1].tip[1], "Social index")
		truthy(#d.lines[1].tip >= 3)
		eq(e.index, So().IndexOf(e.effective, 7))
	end)

	it("never shows the index of others: no section, no value, no column (SPEC-10 Q3)", function()
		world()
		isNil(UI().Describe(BOB))
		isNil(UI().CardSection(A().Roster:ByGUID(BOB)))
		isNil(So():Index(BOB))
		notNil(So():Index(ME))
		falsy(A().RosterModel.ColumnAvailable("social"))
		deepEq(UI().Rows(), {})
	end)

	it("says not enough data under 5 hours, nothing without group play, and computing before the first run", function()
		local first = UI().Describe(ME)
		eq(first.lines[1].text, "Social index: being computed...")
		observe({ { ME, BOB, 90 } })
		So():ComputeNow()
		eq(UI().Describe(ME).lines[1].text, "Social index: not enough data (1.5 h of the 5 h needed)")
		S():Records("coplay")[ME .. ":" .. n] = nil
		observe({ { BOB, CAT, 90 } })
		So():ComputeNow()
		eq(UI().Describe(ME).lines[1].text, "No group play with guildmates in the last 30 days.")
	end)

	it("the Reputation view has a Social mode with the own index only", function()
		world()
		Mock.Slash("/accord reputation")
		A().ReputationView:SetMode("social")
		local lines = UI().ModeLines()
		eq(lines[1].text, "Your social index")
		contains(lines[2].text, "Social index:")
		eq(lines[#lines].text, "Each member sees their own index; officers see everyone's.")
		local shown = {}
		for _, fs in ipairs(UI().frame.lines) do if fs:IsShown() then shown[#shown + 1] = fs.text:GetText() end end
		eq(shown[1], "Your social index")
	end)
end)

describe("for an officer", function()
	before_boot(function() guild(1) end)

	it("sees everyone's index on the cards and in the Social column, a dash under 5 hours", function()
		world()
		notNil(UI().Describe(BOB))
		truthy(A().RosterModel.ColumnAvailable("social"))
		local M = A().RosterModel
		eq(M.Cell("social", A().Roster:ByGUID(FAY)), "-")
		eq(select(2, M.Cell("social", A().Roster:ByGUID(FAY))), "muted")
		local text = M.Cell("social", A().Roster:ByGUID(ME))
		eq(text, tostring(So():Index(ME)))
		eq(M.SortValue("social", A().Roster:ByGUID(ME)), So():Index(ME))
	end)

	it("the Social mode lists every player by index, low data last; a row opens the card", function()
		world()
		local rows = UI().Rows()
		eq(rows[1].key, ME)
		eq(#rows, 7)
		isNil(rows[7].index)
		Mock.Slash("/accord reputation")
		A().ReputationView:SetMode("social")
		local target
		for _, fs in ipairs(UI().frame.lines) do if fs:IsShown() and fs.key == BOB then target = fs end end
		notNil(target)
		target:Click()
		eq(Card().entry.guid, BOB)
	end)

	it("loses the others' index when demoted", function()
		world()
		Mock.guild.SetMyRank(3)
		isNil(UI().Describe(BOB))
		falsy(A().RosterModel.ColumnAvailable("social"))
	end)

	it("the card shows the section with its tooltip on the index line", function()
		world()
		Mock.Slash("/accord roster")
		Card():ShowGUID(BOB)
		local found
		for _, it in ipairs(Card().frame.items) do
			if it:IsShown() and it.text:GetText() and it.text:GetText():find("^Social index:") then found = it end
		end
		notNil(found)
		eq(found.tip[1], "Social index")
		truthy(found:IsMouseEnabled())
	end)
end)

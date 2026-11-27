-- The like interface (M4.3; SPEC-07 LIKE-01, LIKE-04, LIKE-05, LIKE-08): the Reputation view with one row per account
-- sorted by likes, the Like button with its confirmation, the pending state, the Likes section of the member card and
-- the Likes column of the roster.
local function A() return AzerothAccord end
local function L() return AzerothAccord.Likes end
local function S() return AzerothAccord.Store end
local function V() return AzerothAccord.ReputationView end
local function Card() return AzerothAccord.MemberCard end

local ME = "Player-1-0000A001"
local OFF, BOB, BOBALT, CAT, DAN = "Player-1-000000FF", "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000CA7", "Player-1-00000DA1"

local function guild()
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Officer", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Bobalt", level = 20, class = "WARRIOR", rank = 4, guid = BOBALT, online = false },
		{ name = "Cat", level = 58, class = "ROGUE", rank = 3, guid = CAT, online = false },
		{ name = "Dan", level = 40, class = "HUNTER", rank = 3, guid = DAN, online = true },
	} }
end

local function account(guid, chars, token)
	local list = {}
	for i, g in ipairs(chars) do list[i] = { guid = g, name = "C" .. i } end
	S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = token, chars = list,
		main = chars[1] }
	A().Accounts:MarkDirty()
	A().Bus:Emit("STORE_CHANGED", "accounts", guid, "remote")
end

local function entry(p, target)
	local rec = { id = p:sub(1, 16) .. ":" .. target, author = OFF, rev = 1, time = GetServerTime(), pseudonym = p, target = target, day = 20260101 }
	S():Records("likes")[rec.id] = rec
	A().Bus:Emit("STORE_CHANGED", "likes", rec.id, "remote")
end

local function world()
	account(ME, { ME }, "MYTOKEN")
	account(BOB, { BOB, BOBALT }, "BOBTOKEN"); account(BOBALT, { BOBALT, BOB }, "BOBTOKEN")
	account(CAT, { CAT }, "CATTOKEN")
	entry(("11"):rep(16), BOB); entry(("22"):rep(16), BOBALT); entry(("11"):rep(16), BOBALT)
	entry(("33"):rep(16), CAT); entry(("44"):rep(16), CAT)
	entry(("55"):rep(16), DAN)
end

local function names(rows)
	local out = {}
	for i, r in ipairs(rows) do out[i] = r.name .. "=" .. r.total end
	return out
end

local function shownRows()
	local out = {}
	local f = V().modes.likes.frame
	for _, row in ipairs(f.area.rows) do if row:IsShown() then out[#out + 1] = row end end
	return out
end

local function rowOf(name)
	for _, row in ipairs(shownRows()) do if row.name:GetText() == name then return row end end
end

describe("the rows", function()
	before_boot(function() guild() end)

	it("one row per account, the main shown, sorted by likes with shared places", function()
		world()
		local rows = V().LikeRows()
		deepEq(names(rows), { "Bob=2", "Cat=2", "Dan=1", "Officer=0", "Testchar=0" })
		eq(rows[1].chars, 2); eq(rows[1].guid, BOB)
		eq(rows[1].place, 1); eq(rows[2].place, 1); eq(rows[3].place, 3); eq(rows[4].place, 4); eq(rows[5].place, 4)
		eq(rows[1].state, "can"); eq(rows[5].state, "self")
		truthy(rows[1].online)
	end)

	it("sorts by name both ways and by fewest likes", function()
		world()
		deepEq(names(V().LikeRows({ sort = { key = "name" } })), { "Bob=2", "Cat=2", "Dan=1", "Officer=0", "Testchar=0" })
		deepEq(names(V().LikeRows({ sort = { key = "name", desc = true } })), { "Testchar=0", "Officer=0", "Dan=1", "Cat=2", "Bob=2" })
		deepEq(names(V().LikeRows({ sort = { key = "likes", desc = false } })), { "Officer=0", "Testchar=0", "Dan=1", "Bob=2", "Cat=2" })
	end)

	it("the search finds an account by any of its characters", function()
		world()
		deepEq(names(V().LikeRows({ search = "bobal" })), { "Bob=2" })
		deepEq(names(V().LikeRows({ search = "zzz" })), {})
	end)

	it("never shows who gave a like: a row has totals and the player's own state only", function()
		world()
		for _, row in ipairs(V().LikeRows()) do
			for k in pairs(row) do
				truthy(k == "key" or k == "guid" or k == "name" or k == "classFile" or k == "level" or k == "online" or k == "chars"
					or k == "names" or k == "total" or k == "state" or k == "place" or k == "isMain", k)
			end
		end
	end)
end)

describe("the view", function()
	before_boot(function() guild() end)

	local function open()
		world()
		Mock.Slash("/accord reputation")
		Mock.Advance(1)
	end

	it("opens with /accord reputation and draws the rows with place, name, characters and total", function()
		open()
		truthy(V().frame:IsVisible())
		local rows = shownRows()
		eq(#rows, 5)
		eq(rows[1].name:GetText(), "Bob"); eq(rows[1].total:GetText(), "2"); eq(rows[1].place:GetText(), "1")
		eq(rows[1].chars:GetText(), "2 characters")
		truthy(rows[1].like:IsShown())
		eq(rows[1].like:GetLabel(), "", "the Like button is a heart")
		truthy(rows[1].like.heart:IsShown())
		eq(rows[1].like.heart:GetWidth(), 20)
		deepEq(rows[1].like.heart._texCoord, { A().Assets.IconCoords("heart") }, "outlined: not given yet")
		falsy(rows[1].name:CanWordWrap(), "a long name is cut, never wrapped")
		falsy(rowOf("Testchar").like:IsShown())
		eq(rowOf("Testchar").state:GetText(), "you")
	end)

	it("a like needs two clicks; then the row says pending while no officer is online", function()
		open()
		local row = rowOf("Cat")
		row.like:Click()
		eq(row.like:GetLabel(), "Confirm?")
		eq(L():StateOf(CAT), "can", "nothing given yet")
		row.like:Click()
		eq(L():StateOf(CAT), "pending")
		Mock.Advance(1)
		local again = rowOf("Cat")
		falsy(again.like:IsShown())
		eq(again.state:GetText(), "pending")
		contains(table.concat(Mock.PlainOutput(), " "), "Your like for Cat is on its way")
	end)

	it("the confirmation expires", function()
		open()
		rowOf("Dan").like:Click()
		Mock.Advance(V().LIKE_CONFIRM + 1)
		rowOf("Dan").like:Click()
		eq(L():StateOf(DAN), "can")
	end)

	it("sorts from the header and filters from the panel's search box", function()
		open()
		V().modes.likes.frame.head.name:Click()
		eq(shownRows()[1].name:GetText(), "Bob")
		V().modes.likes.frame.head.name:Click()
		eq(shownRows()[1].name:GetText(), "Testchar")
		Mock.TypeInto(A().Shell.content.bar.search, "dan")
		eq(#shownRows(), 1)
		eq(shownRows()[1].name:GetText(), "Dan")
	end)

	it("a click on a row opens the member card in the roster", function()
		open()
		rowOf("Cat"):Click()
		eq(A().Shell.selected, "roster")
		truthy(Card():IsShown())
		eq(Card().entry.guid, CAT)
	end)

	it("a refusal of the notary is told in the chat", function()
		open()
		A().Bus:Emit("LIKE_RESULT", DAN, "conflict")
		contains(table.concat(Mock.PlainOutput(), " "), "Your like for Dan was not recorded")
	end)

	it("has a button per mode: Likes, Social, Someone new and Mentors (Groups only for officers)", function()
		open()
		local shown = 0
		for _, b in ipairs(V().frame.bar.buttons) do if b:IsShown() then shown = shown + 1 end end
		eq(shown, 4)
	end)
end)

describe("the member card and the roster column", function()
	before_boot(function() guild() end)

	local function lines(guid)
		local d = Card().Describe(A().Roster:ByGUID(guid))
		for _, s in ipairs(d.sections) do if s.id == "likes" then return s.lines end end
	end

	it("shows the account's total and the Like action, confirmed by a second click", function()
		world()
		local l = lines(BOBALT)
		eq(l[1].text, "Likes received: 2 (the same on all this player's characters)")
		eq(l[2].text, "[Like this player]"); truthy(l[2].action)
		l[2].onClick()
		l = lines(BOBALT)
		eq(l[2].text, "[Click again to confirm: a like cannot be taken back]")
		l[2].onClick()
		eq(lines(BOB)[2].text, "Your like is waiting for an officer with the addon to come online.")
		eq(lines(BOBALT)[2].text, "Your like is waiting for an officer with the addon to come online.")
	end)

	it("says when the player already liked, and has no action on the player's own characters", function()
		world()
		local data = A().GuildKey:Data()
		data.likes = { given = { [CAT] = GetServerTime() }, queue = {} }
		eq(lines(CAT)[2].text, "You liked this player.")
		eq(#lines(ME), 1)
	end)

	it("the Likes column shows the total, green when liked, grey while pending", function()
		world()
		local M = A().RosterModel
		local text, color = M.Cell("likes", A().Roster:ByGUID(BOBALT))
		eq(text, "2"); isNil(color)
		A().GuildKey:Data().likes = { given = { [CAT] = 1 }, queue = { [DAN] = { at = 1, n = "x" } } }
		eq(select(2, M.Cell("likes", A().Roster:ByGUID(CAT))), "green")
		eq(select(2, M.Cell("likes", A().Roster:ByGUID(DAN))), "grey")
		eq(M.SortValue("likes", A().Roster:ByGUID(BOB)), 2)
	end)
end)

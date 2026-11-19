-- "Who can craft" (M3.5; SPEC-06 PRO-04): the reverse index from a recipe to the members who know it, online first,
-- grouped by account; the search by recipe or item name.
local function A() return AzerothAccord end
local function R() return AzerothAccord.Recipes end
local function S() return AzerothAccord.Store end
local function X() return AzerothAccord.Crafters end

local ME, BOB, BOBALT, ANN, CID, GONE = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000A44",
	"Player-1-00000C1D", "Player-1-0000DEAD"
local ALCHEMY, SMITHING = 171, 164

local SPELLS = { [2330] = "Minor Healing Potion", [2332] = "Minor Rejuvenation Potion", [3447] = "Healing Potion",
	[4000] = "Elixir of Agility", [4001] = "Elixir of Defense", [4002] = "Greater Healing Potion", [2660] = "Rough Blunt" }

local function guild()
	for id, name in pairs(SPELLS) do Mock.spells.known[id] = { name = name, icon = 1000 + id } end
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN, online = false },
		{ name = "Cid", level = 40, class = "ROGUE", rank = 3, guid = CID, online = true },
	} }
end

local function put(guid, line, ids, extra)
	local id = guid .. ":" .. line
	local old = S():Get("recipes", id)
	local rec = { id = id, author = guid, rev = (old and old.rev or 0) + 1, time = GetServerTime() - 86400, char = guid, skillLine = line,
		name = line == ALCHEMY and "Alchemy" or "Blacksmithing", rank = 200, maxRank = 300, ids = R().Encode(ids), n = #ids }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("recipes")[id] = rec
	A().Roster:MarkDirty()
	X():MarkDirty()
end

local function accountBob()
	for guid, other in pairs({ [BOB] = BOBALT, [BOBALT] = BOB }) do
		S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T",
			chars = { { guid = guid, name = "x" }, { guid = other, name = "y" } } }
	end
	A().Accounts:MarkDirty()
end

local function names(list) local t = {} for i, r in ipairs(list) do t[i] = r.name end return t end

describe("what a search looks for", function()
	it("takes the name inside a pasted item or spell link", function()
		eq(X().Normalize("  Healing POTION "), "healing potion")
		eq(X().Normalize("|cff71d5ff|Hspell:2330|h[Minor Healing Potion]|h|r"), "minor healing potion")
		eq(X().Normalize("|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r"), "minor healing potion")
		eq(X().Normalize(42), "")
		eq(X().Normalize(nil), "")
	end)

	it("needs at least two characters", function()
		guild()
		eq(X():Search("h").status, "short")
		eq(X():Search("").status, "short")
	end)
end)

describe("who can craft it (PRO-04)", function()
	before_boot(function() guild() end)

	it("lists the members who know a recipe, online first, then by name", function()
		put(ANN, ALCHEMY, { 2330, 3447 })
		put(CID, ALCHEMY, { 2330 })
		put(BOB, ALCHEMY, { 2330, 2332 })
		local r = X():Search("minor healing")
		eq(r.status, "ok"); eq(r.total, 1)
		local rec = r.recipes[1]
		eq(rec.name, "Minor Healing Potion"); eq(rec.id, 2330); eq(rec.count, 3); eq(rec.icon, 1000 + 2330)
		local order = {}
		for _, acc in ipairs(rec.accounts) do for _, m in ipairs(acc.members) do order[#order + 1] = m.name .. (m.online and "+" or "-") end end
		deepEq(order, { "Bob+", "Cid+", "Ann-" })
	end)

	it("describes each crafter: class, level, profession, rank, source and age", function()
		put(BOB, ALCHEMY, { 2330 })
		local m = X():Search("minor healing").recipes[1].accounts[1].members[1]
		eq(m.guid, BOB); eq(m.classFile, "MAGE"); eq(m.level, 50); eq(m.profession, "Alchemy"); eq(m.rank, 200); eq(m.maxRank, 300)
		eq(m.source, "shared"); eq(m.time, GetServerTime() - 86400); eq(m.skillLine, ALCHEMY); eq(m.rankName ~= nil, true)
		falsy(m.isSelf)
	end)

	it("groups the characters of one account together, the account with somebody online first", function()
		accountBob()
		put(ANN, ALCHEMY, { 2330 })
		put(BOBALT, ALCHEMY, { 2330 })
		put(BOB, ALCHEMY, { 2330 })
		put(BOB, SMITHING, { 2330 })   -- the same recipe id in a second profession of the same character
		local rec = X():Search("minor healing").recipes[1]
		eq(#rec.accounts, 2)
		eq(#rec.accounts[1].members, 3, "Bob twice and Bobalt")
		eq(rec.accounts[1].members[1].name, "Bob")
		eq(rec.accounts[2].members[1].name, "Ann")
		eq(rec.count, 4)
	end)

	it("matches exact names first, then names that begin with the text, then the rest", function()
		put(BOB, ALCHEMY, { 2330, 3447, 4002, 4000 })
		local r = X():Search("healing potion")
		deepEq(names(r.recipes), { "Healing Potion", "Greater Healing Potion", "Minor Healing Potion" })
		local s = X():Search("potion")
		eq(s.total, 3)
		eq(s.recipes[1].name, "Greater Healing Potion", "no exact or prefix match: by name")
	end)

	it("is case-insensitive and finds a recipe by the name of a link", function()
		put(BOB, ALCHEMY, { 3447 })
		eq(X():Search("HEALING").total, 1)
		eq(X():Search("|cffffffff|Hitem:118|h[Healing Potion]|h|r").recipes[1].id, 3447)
	end)

	it("says when nobody can craft it", function()
		put(BOB, ALCHEMY, { 3447 })
		local r = X():Search("elixir")
		eq(r.status, "none"); eq(r.total, 0); eq(#r.recipes, 0)
	end)

	it("online only drops the members who are not online, and the recipes nobody online knows", function()
		put(ANN, ALCHEMY, { 2330, 4000 })
		put(BOB, ALCHEMY, { 2330 })
		local r = X():Search("e", { onlineOnly = true })
		eq(r.status, "short")
		r = X():Search("minor healing", { onlineOnly = true })
		eq(r.recipes[1].count, 1)
		eq(X():Search("elixir", { onlineOnly = true }).status, "none")
		eq(X():Search("elixir").total, 1)
	end)

	it("lists only guild members: a record of somebody who left the guild is ignored", function()
		put(GONE, ALCHEMY, { 2330 })
		eq(X():Search("minor healing").status, "none")
	end)

	it("lists the player's own character with its own scan", function()
		put(ME, ALCHEMY, { 2330 }, { time = GetServerTime() })
		local m = X():Search("minor healing").recipes[1].accounts[1].members[1]
		eq(m.guid, ME); eq(m.isSelf, true); eq(m.online, true); eq(m.source, "own")
	end)

	it("the native answer replaces the shared list of the same member and profession", function()
		put(BOB, ALCHEMY, { 2330 })
		Mock.tradeskill.guildEnabled = true
		Mock.tradeskill.guildRecipes = { [BOB] = { [ALCHEMY] = { 3447 } } }
		R():RequestNative(BOB, ALCHEMY)
		Mock.Advance(0.5)
		X():MarkDirty()
		eq(X():Search("minor healing").status, "none", "the game's list is the one that counts")
		local m = X():Search("healing potion").recipes[1].accounts[1].members[1]
		eq(m.source, "native")
	end)

	it("an index that is out of date is rebuilt after a record arrives", function()
		put(BOB, ALCHEMY, { 2330 })
		eq(X():Search("minor healing").total, 1)
		local before = X().state.builds
		eq(X():Search("minor healing").total, 1)
		eq(X().state.builds, before, "not rebuilt while nothing changed")
		put(CID, ALCHEMY, { 2332 })
		A().Bus:Emit("RECIPES_UPDATED", CID, ALCHEMY, "shared")
		eq(X():Search("rejuvenation").total, 1)
		eq(X().state.builds, before + 1)
	end)

	it("a name that is not loaded yet is counted as pending and found once it loads", function()
		Mock.spells.known[3447] = nil
		Mock.spells.loadable[3447] = { name = "Healing Potion", icon = 5 }
		put(BOB, ALCHEMY, { 2330, 3447 })
		local r = X():Search("healing potion")
		eq(r.pending, 1)
		eq(#r.recipes, 1)
		Mock.Advance(0.2)
		r = X():Search("healing potion")
		eq(r.pending, 0)
		eq(#r.recipes, 2)
	end)

	it("never lists more than MAX_RECIPES recipes, and says how many are left", function()
		local ids = {}
		for i = 1, 60 do
			ids[i] = 20000 + i
			Mock.spells.known[ids[i]] = { name = "Test Potion " .. ("%02d"):format(i), icon = 1 }
		end
		put(BOB, ALCHEMY, ids)
		local r = X():Search("test potion")
		eq(r.total, 60); eq(#r.recipes, X().MAX_RECIPES); eq(r.more, 20)
	end)

	it("never lists more than MAX_MEMBERS characters under one recipe", function()
		local list = {}
		for i = 1, 150 do list[i] = { name = "M" .. i, level = 10, class = "MAGE", rank = 3, guid = ("Player-1-%08X"):format(0x900 + i) } end
		Mock.guild.Set{ name = "Accord", myRank = 3, members = list }
		for i = 1, 150 do put(("Player-1-%08X"):format(0x900 + i), ALCHEMY, { 2330 }) end
		local rec = X():Search("minor healing").recipes[1]
		local n = 0
		for _, acc in ipairs(rec.accounts) do n = n + #acc.members end
		eq(n, X().MAX_MEMBERS)
	end)

	it("a list that cannot be read is not indexed", function()
		put(BOB, ALCHEMY, { 2330 }, { ids = "not base64!" })
		eq(X():Search("minor healing").status, "none")
	end)
end)

describe("the rows of a result", function()
	before_boot(function() guild() end)

	it("a recipe row, then its members; the alts of an account are indented under the first", function()
		accountBob()
		put(ANN, ALCHEMY, { 2330 })
		put(BOB, ALCHEMY, { 2330 })
		put(BOBALT, ALCHEMY, { 2330 })
		local rows = X().Rows(X():Search("minor healing"))
		eq(#rows, 4)
		eq(rows[1].kind, "recipe"); eq(rows[1].name, "Minor Healing Potion"); eq(rows[1].count, 3)
		deepEq({ rows[2].kind, rows[2].depth, rows[2].member.name }, { "member", 0, "Bob" })
		deepEq({ rows[3].kind, rows[3].depth, rows[3].member.name }, { "member", 1, "Bobalt" })
		deepEq({ rows[4].kind, rows[4].depth, rows[4].member.name }, { "member", 0, "Ann" })
		eq(rows[2].recipeId, 2330)
		deepEq(X().Rows(nil), {})
	end)

	it("/accord debug reports the index", function()
		put(BOB, ALCHEMY, { 2330 })
		X():Search("minor healing")
		truthy(A().Diagnostics.Report():find("Crafters: 1 list(s), 1 distinct recipe(s) indexed", 1, true))
	end)
end)

describe("the index at the size of a big guild", function()
	it("a search over 400 members with 2 lists of 300 recipes each stays fast", function()
		local members, ids = {}, {}
		for i = 1, 300 do
			ids[i] = 30000 + i
			Mock.spells.known[ids[i]] = { name = "Recipe Name " .. i, icon = 1 }
		end
		for i = 1, 400 do members[i] = { name = "M" .. i, level = 10, class = "MAGE", rank = 3, guid = ("Player-1-%08X"):format(0xA00 + i) } end
		Mock.guild.Set{ name = "Accord", myRank = 3, members = members }
		for i = 1, 400 do
			put(("Player-1-%08X"):format(0xA00 + i), ALCHEMY, ids)
			put(("Player-1-%08X"):format(0xA00 + i), SMITHING, ids)
		end
		local t0 = Mock.RealClock()
		local r = X():Search("recipe name 29")
		local ms = (Mock.RealClock() - t0) * 1000
		eq(r.total, 11)
		T.log(("first search over 240000 list entries: %.0f ms"):format(ms))
		truthy(ms < 3000, "first search (index build): " .. ms .. " ms")
		t0 = Mock.RealClock()
		X():Search("recipe name 150")
		ms = (Mock.RealClock() - t0) * 1000
		truthy(ms < 200, "the next search: " .. ms .. " ms")
	end)
end)

-- RosterModel (M2.3; SPEC-05 §1 ROS-01, ROS-02): columns, search, filters, sorting and the grouped-by-account rows are
-- plain functions of the roster and the account groups, tested here without a frame.
local seeded
local seed
local function A()
	local a = AzerothAccord
	if seeded ~= a then seeded = a seed(a) end   -- the records need the addon, which is not loaded yet in before_boot
	return a
end
local function M() return A().RosterModel end

local ANN, BOB, BOBALT, CID, DEE = "Player-1-00000A01", "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000C1D", "Player-1-00000D0E"
local OUT = "Player-1-0000CC01"

local function mockGuild()
	Mock.club.fill.professions = true
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN, zone = "Ironforge",
			professions = { { id = 171, name = "Alchemy", rank = 300 }, { id = 182, name = "Herbalism", rank = 200 } } },
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, online = false, lastOnline = { 0, 0, 3, 0 }, zone = "Stormwind",
			professions = { { id = 164, name = "Blacksmithing", rank = 75 } } },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT, online = false, lastOnline = { 0, 1, 0, 0 } },
		{ name = "Cid", level = 20, class = "ROGUE", rank = 3, guid = CID, zone = "Orgrimmar" },
		{ name = "Dee", level = 60, class = "MAGE", rank = 3, guid = DEE, online = false, lastOnline = { 0, 0, 0, 5 },
			professions = { { id = 171, name = "Alchemy", rank = 150 } } },
	} }
end
seed = function(a)
	local S = a.Store
	local function acct(guid, list)
		local chars = {}
		for i, c in ipairs(list) do chars[i] = c end
		S:Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T", chars = chars }
	end
	acct(BOB, { { guid = BOB, name = "Bob", level = 50 }, { guid = BOBALT, name = "Bobalt", level = 30 }, { guid = OUT, name = "Elsewhere", level = 12, classID = 3 } })
	acct(BOBALT, { { guid = BOBALT, name = "Bobalt", level = 30 }, { guid = BOB, name = "Bob", level = 50 } })
	a.Roster:MarkDirty()
	a.Accounts:MarkDirty()
end

local function names(model)
	local out = {}
	for _, r in ipairs(model:Rows()) do out[#out + 1] = (r.kind == "alt" and "  " or "") .. (r.entry.short or r.entry.name) end
	return out
end

local function sorted(key, desc)
	local m = M().new()
	m:SetSort(key, desc or false)
	return names(m)
end

describe("columns", function()
	before_boot(function() mockGuild() end)

	it("shows the default columns, never the social index before its module exists (M4)", function()
		local m = M().new()
		local ids = {}
		for _, c in ipairs(m:VisibleColumns()) do ids[#ids + 1] = c.id end
		deepEq(ids, { "name", "level", "class", "rank", "zone", "lastOnline", "prof1", "prof2", "likes", "battleTag", "addon" })
		truthy(M().ColumnAvailable("likes")); falsy(M().ColumnAvailable("social")); truthy(M().ColumnAvailable("battleTag"))
		falsy(M().ColumnAvailable("contacts"), "Contacts and Social left the Roster (owner, 2026-11-27)")
		falsy(M().ColumnAvailable("nope"))
	end)

	it("a column appears once its module exists", function()
		M().enabled = { likes = true }   -- what ns.Likes being there does (M4)
		truthy(M().ColumnAvailable("likes"))
		local m = M().new()
		m:SetColumns({ "name", "likes" })
		truthy(m:HasColumn("likes"))
		M().enabled = nil
	end)

	it("the name column cannot be hidden; the others toggle; the order stays the table's", function()
		local m = M().new()
		falsy(m:ToggleColumn("name"))
		falsy(m:ToggleColumn("zone"))
		falsy(m:HasColumn("zone"))
		truthy(m:ToggleColumn("zone"))
		local ids = {}
		for _, c in ipairs(m:VisibleColumns()) do ids[#ids + 1] = c.id end
		eq(ids[5], "zone")
		m:SetColumns({ "level" })
		deepEq(m.columns, { "name", "level" })
		m:SetColumns({ "social", "bogus", "class" })
		deepEq(m.columns, { "name", "class" })
	end)

	it("saves the columns, the sort and the grouping per character and loads them back", function()
		local m = M().new()
		m:ToggleColumn("zone"); m:SetSort("level", true); m:SetGrouped(true)
		m:Save()
		eq(A().Config:Get("char.ui.grouped"), true)
		local again = M().new()
		again:Load()
		falsy(again:HasColumn("zone"))
		eq(again.sort.key, "level"); eq(again.sort.desc, true); eq(again.grouped, true)
	end)

	it("a column choice saved before the BattleTag column gets it in place of Contacts / Social (2026-11-27)", function()
		A().Config:Set("char.ui.columns", { "name", "level", "zone", "contacts", "addon" })
		local m = M().new()
		m:Load()
		truthy(m:HasColumn("battleTag"))
		falsy(m:HasColumn("contacts"))
		A().Config:Set("char.ui.columns", { "name", "level" })
		local n = M().new()
		n:Load()
		falsy(n:HasColumn("battleTag"), "a newer choice without it stays as the player made it")
	end)

	it("the Addon column says yes for a development build (@project-version@)", function()
		eq((M().Cell("addon", { hasAddon = true, addonVersion = "@project-version@" })), "yes")
		eq((M().Cell("addon", { hasAddon = true, addonVersion = "v0.11.1" })), "v0.11.1")
	end)

	it("ignores damaged saved choices", function()
		A().Config.db.char.ui.columns = { 1, "x" }
		A().Config.db.char.ui.sort = { key = "bogus" }
		local m = M().new()
		m:Load()
		eq(m.sort.key, "name")
		truthy(m:HasColumn("name"))
	end)
end)

describe("ROS-01: sorting", function()
	before_boot(function() mockGuild() end)

	it("by name, both ways, and a second click on the same column reverses", function()
		deepEq(sorted("name"), { "Ann", "Bob", "Bobalt", "Cid", "Dee", "Testchar" })
		local m = M().new()
		m:SetSort("name")
		truthy(m.sort.desc)
		m:SetSort("name")
		falsy(m.sort.desc)
		deepEq(sorted("name", true), { "Testchar", "Dee", "Cid", "Bobalt", "Bob", "Ann" })
	end)

	it("by level with the name as the tie-break", function()
		deepEq(sorted("level", true), { "Ann", "Dee", "Testchar", "Bob", "Bobalt", "Cid" })
		deepEq(sorted("level", false), { "Cid", "Bobalt", "Bob", "Ann", "Dee", "Testchar" })
	end)

	it("by rank, the Guild Master end first", function()
		local list = sorted("rank")
		eq(list[1], "Ann")
	end)

	it("by class name and by zone", function()
		local list = sorted("class")
		eq(list[1], "Bob")   -- Mage first, Warrior (Bobalt, Testchar) last
		eq(list[#list], "Testchar")
		eq(sorted("zone")[1], "Ann")
	end)

	it("by last online: online first, then the most recent; a missing value last whatever the direction", function()
		local list = sorted("lastOnline")
		deepEq({ list[#list - 2], list[#list - 1], list[#list] }, { "Dee", "Bob", "Bobalt" })
		local desc = sorted("lastOnline", true)
		eq(desc[1], "Bobalt")
	end)

	it("by profession: members without one are last in both directions", function()
		local up, down = sorted("prof1", false), sorted("prof1", true)
		deepEq({ up[1], up[2], up[3] }, { "Ann", "Dee", "Bob" })
		deepEq({ down[1], down[2], down[3] }, { "Bob", "Ann", "Dee" })
		for _, list in ipairs({ up, down }) do
			local tail = {}
			for i = 4, #list do tail[list[i]] = true end
			truthy(tail.Cid and tail.Bobalt and tail.Testchar)
		end
	end)

	it("refuses an unknown column", function()
		falsy(M().new():SetSort("bogus"))
	end)
end)

describe("ROS-01: search and filters", function()
	before_boot(function() mockGuild() end)

	it("searches names without case or position, and professions", function()
		local m = M().new()
		m:SetSearch("BOB")
		deepEq(names(m), { "Bob", "Bobalt" })
		m:SetSearch("alch")
		deepEq(names(m), { "Ann", "Dee" })
		m:SetSearch("zzz")
		eq(m:Count(), 0)
		m:SetSearch("")
		eq(m:Count(), 6)
		falsy(m:SetSearch(""))
	end)

	it("filters by online", function()
		local m = M().new()
		m:SetFilter("online", true)
		deepEq(names(m), { "Ann", "Cid", "Testchar" })
	end)

	it("filters by class and by rank", function()
		local m = M().new()
		m:SetFilter("class", "MAGE")
		deepEq(names(m), { "Bob", "Dee" })
		m:SetFilter("class", nil)
		m:SetFilter("rank", 3)
		deepEq(names(m), { "Bob", "Cid", "Dee", "Testchar" })
		m:SetFilter("rank", 0)
		eq(m:Count(), 0)
	end)

	it("filters by profession id or by lower-case name", function()
		local m = M().new()
		m:SetFilter("profession", 171)
		deepEq(names(m), { "Ann", "Dee" })
		m:SetFilter("profession", "blacksmithing")
		deepEq(names(m), { "Bob" })
	end)

	it("'mains only' hides the alts of an account, keeps members without an account", function()
		local m = M().new()
		m:SetFilter("mains", true)
		deepEq(names(m), { "Ann", "Bob", "Cid", "Dee", "Testchar" })
	end)

	it("combines the filters with the search", function()
		local m = M().new()
		m:SetFilter("online", true); m:SetFilter("class", "PRIEST"); m:SetSearch("an")
		deepEq(names(m), { "Ann" })
		truthy(m:HasFilters())
		m:ClearFilters()
		falsy(m:HasFilters())
		eq(m:Count(), 6)
	end)

	it("offers the classes, ranks and professions the guild has", function()
		local m = M().new()
		local keys = {}
		for _, c in ipairs(m:Choices("class")) do keys[#keys + 1] = c.key end
		deepEq(keys, { "MAGE", "PRIEST", "ROGUE", "WARRIOR" })
		local ranks = {}
		for _, c in ipairs(m:Choices("rank")) do ranks[#ranks + 1] = c.key end
		deepEq(ranks, { 1, 3, 4 })
		local profs = {}
		for _, c in ipairs(m:Choices("profession")) do profs[#profs + 1] = c.label end
		deepEq(profs, { "Alchemy", "Blacksmithing", "Herbalism" })
	end)

	it("rebuilds the rows only after a change", function()
		local m = M().new()
		local first = m:Rows()
		eq(m:Rows(), first)
		m:SetFilter("online", true)
		ne(m:Rows(), first)
	end)
end)

describe("ROS-02: grouped by account", function()
	before_boot(function() mockGuild() end)

	local function grouped()
		local m = M().new()
		m:SetGrouped(true)
		return m
	end

	it("shows one row per account, collapsed, with the number of alts", function()
		local m = grouped()
		deepEq(names(m), { "Ann", "Bob", "Cid", "Dee", "Testchar" })
		local bob = m:Rows()[2]
		eq(bob.kind, "group"); eq(bob.count, 2); falsy(bob.expanded)
		eq(m:Rows()[1].kind, "member")
	end)

	it("expands to the alts under the main, including a character outside the guild", function()
		local m = grouped()
		local id = A().Accounts:GroupOf(BOB).id
		truthy(m:ToggleExpand(id))
		deepEq(names(m), { "Ann", "Bob", "  Bobalt", "  Elsewhere", "Cid", "Dee", "Testchar" })
		local alt = m:Rows()[3]
		eq(alt.kind, "alt"); eq(alt.depth, 1)
		local out = m:Rows()[4].entry
		truthy(out.notInGuild); eq(out.classFile, "HUNTER"); eq(out.level, 12)
		falsy(m:ToggleExpand(id))
		eq(m:Count(), 5)
	end)

	it("the row of an alt outside the guild says its guild and last login, or that it has none (M7.3)", function()
		local m = grouped()
		m:ToggleExpand(A().Accounts:GroupOf(BOB).id)
		local day = GetServerTime() - GetServerTime() % 86400
		local rec = A().Store:Records("accounts")[BOB]
		rec.chars[3].guild, rec.chars[3].seen = "Other Guild", day - 2 * 86400
		A().Accounts:MarkDirty()
		m:Invalidate()
		local out = m:Rows()[4].entry
		eq(M().Cell("lastOnline", out), "Other guild: Other Guild · seen 2 d ago")
		rec.chars[3].guild = ""
		A().Accounts:MarkDirty()
		m:Invalidate()
		eq(M().Cell("lastOnline", m:Rows()[4].entry), "No guild · seen 2 d ago")
		rec.chars[3].guild, rec.chars[3].seen = nil, nil
		A().Accounts:MarkDirty()
		m:Invalidate()
		eq(M().Cell("lastOnline", m:Rows()[4].entry), "not in guild")
	end)

	it("orders the accounts by their main's value, and the alts like any list", function()
		local m = grouped()
		m:ExpandAll(true)
		m:SetSort("level", true)
		deepEq(names(m), { "Ann", "Dee", "Testchar", "Bob", "  Bobalt", "  Elsewhere", "Cid" })
	end)

	it("sorts by last online with the most recent member of the account", function()
		local m = grouped()
		m:SetSort("lastOnline", false)
		local list = names(m)
		eq(list[#list], "Bob")   -- Bob was seen 3 days ago, Dee 5 hours ago
		eq(list[#list - 1], "Dee")
	end)

	it("keeps an account when only an alt matches the filters", function()
		local m = grouped()
		m:SetFilter("class", "WARRIOR")   -- Bobalt and Testchar
		deepEq(names(m), { "Bob", "Testchar" })
		m:ToggleExpand(A().Accounts:GroupOf(BOB).id)
		deepEq(names(m), { "Bob", "  Bobalt", "Testchar" })
	end)

	it("'mains only' shows the main of each account and never its alts", function()
		local m = grouped()
		m:SetFilter("mains", true)
		m:ExpandAll(true)
		deepEq(names(m), { "Ann", "Bob", "Cid", "Dee", "Testchar" })
	end)

	it("searches inside the accounts", function()
		local m = grouped()
		m:SetSearch("bobalt")
		deepEq(names(m), { "Bob" })
	end)

	it("without accounts every member is a row of its own", function()
		A().Store:Records("accounts")[BOB] = nil
		A().Store:Records("accounts")[BOBALT] = nil
		A().Accounts:MarkDirty()
		eq(grouped():Count(), 6)
	end)
end)

describe("cell texts", function()
	before_boot(function() mockGuild() end)

	it("writes the last online time in the largest unit", function()
		local T = M().LastOnlineText
		eq(T(0), "< 1 h ago"); eq(T(5), "5 h ago"); eq(T(48), "2 d ago"); eq(T(24 * 59), "59 d ago")
		eq(T(24 * 90), "3 mo ago"); eq(T(24 * 800), "2 y ago"); eq(T(nil), "unknown")
	end)

	it("writes professions with their rank, and the cells of a member", function()
		eq(M().ProfessionText({ name = "Alchemy", rank = 300 }), "Alchemy 300")
		eq(M().ProfessionText({ name = "Alchemy" }), "Alchemy")
		eq(M().ProfessionText({ id = 171 }), "Skill 171")
		local ann = A().Roster:ByGUID(ANN)
		deepEq({ M().Cell("name", ann) }, { "Ann", "class" })
		deepEq({ M().Cell("class", ann) }, { "Priest", "class" })
		deepEq({ M().Cell("lastOnline", ann) }, { "Online", "green" })
		eq((M().Cell("prof1", ann)), "Alchemy 300")
		eq((M().Cell("prof2", ann)), "Herbalism 200")
		eq((M().Cell("prof2", A().Roster:ByGUID(BOB))), "")
		eq((M().Cell("lastOnline", A().Roster:ByGUID(BOB))), "3 d ago")
		eq((M().Cell("level", ann)), "60")
	end)

	it("marks shared professions as muted and shows the addon version", function()
		local e = { professions = { { name = "Mining", rank = 10, source = "shared" } }, hasAddon = true, addonVersion = "0.2.0" }
		deepEq({ M().Cell("prof1", e) }, { "Mining 10", "muted" })
		deepEq({ M().Cell("addon", e) }, { "0.2.0", "green" })
		eq((M().Cell("addon", {})), "")
	end)
end)

describe("a guild of 1000 members", function()
	it("sorts, filters and groups within the budget", function()
		local list = {}
		for i = 1, 999 do
			list[i] = { name = "M" .. i, level = 1 + i % 60, class = (i % 2 == 0) and "MAGE" or "WARRIOR", rank = 2 + i % 3,
				online = i % 5 == 0, guid = ("Player-1-%08X"):format(0x5000 + i), lastOnline = { 0, 0, i % 20, 0 } }
		end
		Mock.guild.Set{ name = "Big", myRank = 3, members = list }
		A().Roster:Build()
		local m = M().new()
		local started = Mock.RealClock()
		m:SetSort("level", true); eq(m:Count(), 1000)
		m:SetSort("lastOnline"); m:SetFilter("online", true); m:SetFilter("class", "MAGE")
		truthy(m:Count() > 0)
		m:ClearFilters(); m:SetGrouped(true); eq(m:Count(), 1000)
		m:SetSearch("m99")
		truthy(m:Count() > 0)
		truthy(Mock.RealClock() - started < 2, "took " .. (Mock.RealClock() - started) .. " s")
	end)
end)

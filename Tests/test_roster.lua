-- Roster model (M2.1; SPEC-05 §1, ADR 0010): the members merged from the guild roster, C_Club, the shared records and
-- the player's own professions; the 15-second request throttle (ROS-03); lazy rebuilds; the 1000-member budget.
local function R() return AzerothAccord.Roster end
local function C() return AzerothAccord.Compat end

local BOB, ANN = "Player-1-00000B0B", "Player-1-00000A44"

local function guild(members, extra)
	local config = { name = "Accord", myRank = 3, members = members or {} }
	for k, v in pairs(extra or {}) do config[k] = v end
	Mock.guild.Set(config)
end

local function fill(fields)
	for k, v in pairs(fields) do Mock.club.fill[k] = v end
end

local function members()
	return {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, zone = "Stormwind", note = "hi",
			professions = { { id = 171, name = "Alchemy", rank = 300 }, { id = 164, name = "Blacksmithing", rank = 75 } }, discord = "bob_d" },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN, online = false, lastOnline = { 0, 0, 3, 5 } },
	}
end

describe("merging the sources", function()
	before_boot(function(M) guild(members()) end)

	it("lists the roster with rank, class, zone, notes and the last online time", function()
		fill{ professions = false }
		local list = R():Members()
		eq(#list, 3)
		local bob = R():ByGUID(BOB)
		eq(bob.name, "Bob"); eq(bob.level, 50); eq(bob.classFile, "MAGE"); eq(bob.classID, 8)
		eq(bob.rankIndex, 3); eq(bob.zone, "Stormwind"); eq(bob.note, "hi")
		truthy(bob.online)
		local ann = R():ByGUID(ANN)
		falsy(ann.online)
		eq(ann.lastOnlineHours, 3 * 24 + 5)
		truthy(R():ByGUID("Player-1-0000A001").isSelf)
		eq(R():ByName("bob"), bob)
	end)

	it("takes professions, Discord and the club member id from C_Club when the server fills them (native)", function()
		fill{ professions = true, discord = true, bnet = true }
		R():Build()
		local bob = R():ByGUID(BOB)
		eq(#bob.professions, 2)
		deepEq(bob.professions[1], { id = 171, name = "Alchemy", rank = 300, source = "native" })
		eq(bob.discord, "bob_d"); eq(bob.discordSource, "native")
		notNil(bob.clubMemberId); notNil(bob.bnetAccountId)
		eq(#R():ByGUID(ANN).professions, 0)
	end)

	it("leaves professions empty when the server does not fill them and nothing was shared", function()
		fill{ professions = false, discord = false }
		R():Build()
		eq(#R():ByGUID(BOB).professions, 0)
		isNil(R():ByGUID(BOB).discord)
		notNil(R():ByGUID(BOB).clubMemberId)
	end)

	it("refines the clubProfessions and clubDiscord capabilities from what the members show", function()
		fill{ professions = false, discord = false }
		R():Build()
		eq(C():Feature("clubProfessions"), "unknown")
		eq(C():Feature("clubDiscord"), "unknown")
		fill{ professions = true, discord = true }
		R():Build()
		eq(C():Feature("clubProfessions"), "available")
		eq(C():Feature("clubDiscord"), "available")
	end)

	it("joins the club to the roster by name when the club gives no GUID", function()
		fill{ professions = true, guid = false }
		R():Build()
		eq(#R():ByGUID(BOB).professions, 2)
	end)

	it("fills the gaps with the shared recipes records and lets the native data win", function()
		fill{ professions = false }
		AzerothAccord.Store:Records("recipes")[BOB .. ":171"] = { id = BOB .. ":171", author = BOB, rev = 1, time = GetServerTime(),
			char = BOB, skillLine = 171, name = "Alchemy", rank = 120, maxRank = 300 }
		AzerothAccord.Store:Records("recipes")[ANN .. ":164"] = { id = ANN .. ":164", author = ANN, rev = 1, time = GetServerTime(),
			char = ANN, skillLine = 164, rank = 10, maxRank = 300 }
		R():Build()
		local bob = R():ByGUID(BOB)
		deepEq({ bob.professions[1].id, bob.professions[1].rank, bob.professions[1].source }, { 171, 120, "shared" })
		eq(R():ByGUID(ANN).professions[1].source, "shared")
		fill{ professions = true }
		R():Build()
		eq(R():ByGUID(BOB).professions[1].rank, 300)
		eq(R():ByGUID(BOB).professions[1].source, "native")
	end)

	it("keeps at most two shared professions per character", function()
		fill{ professions = false }
		for i, line in ipairs({ 171, 164, 202 }) do
			AzerothAccord.Store:Records("recipes")[BOB .. ":" .. line] = { id = BOB .. ":" .. line, author = BOB, rev = i, time = GetServerTime(),
				char = BOB, skillLine = line }
		end
		R():Build()
		eq(#R():ByGUID(BOB).professions, 2)
	end)

	it("knows who has the addon (an accounts record) and its version", function()
		AzerothAccord.Store:Records("accounts")[BOB] = { id = BOB, author = BOB, rev = 1, time = GetServerTime(), token = "T",
			chars = { { guid = BOB } }, addonVersion = "0.2.0" }
		R():Build()
		truthy(R():ByGUID(BOB).hasAddon)
		eq(R():ByGUID(BOB).addonVersion, "0.2.0")
		falsy(R():ByGUID(ANN).hasAddon)
		truthy(R():ByGUID("Player-1-0000A001").hasAddon)
	end)

	it("knows the player's own professions natively, without C_Club", function()
		fill{ professions = false }
		Mock.tradeskill.own = { { name = "Mining", skillLine = 186, rank = 200, maxRank = 300 } }
		R():Build()
		local me = R():ByGUID("Player-1-0000A001")
		deepEq({ me.professions[1].name, me.professions[1].rank, me.professions[1].source }, { "Mining", 200, "own" })
	end)
end)

describe("a client without GetGuildRosterInfo", function()
	before_boot(function(M) guild(members()) end)

	it("builds the roster from C_Club alone and derives the class file from the class id", function()
		GetGuildRosterInfo = nil
		R():Build()
		eq(#R():Members(), 3)
		local bob = R():ByName("Bob")
		eq(bob.source, "club")
		eq(bob.classID, 8); eq(bob.classFile, "MAGE")
		eq(bob.rankIndex, 3)
	end)

	it("is empty without a guild", function()
		Mock.guild.Leave()
		R():Build()
		eq(#R():Members(), 0)
		isNil(R():ByGUID(BOB))
	end)
end)

describe("ROS-03: asking the server and rebuilding", function()
	before_boot(function(M) guild(members()) end)

	local function countRequests()
		local n = { 0 }
		local orig = C_GuildInfo.GuildRoster
		C_GuildInfo.GuildRoster = function(...) n[1] = n[1] + 1 return orig(...) end
		return n
	end

	it("asks for a fresh roster at most every 15 seconds, unless forced", function()
		local n = countRequests()
		truthy(R():Request())
		falsy(R():Request())
		Mock.Advance(14)
		falsy(R():Request())
		Mock.Advance(2)
		truthy(R():Request())
		truthy(R():Request(true))
		eq(n[1], 3)
	end)

	it("does not ask when the client has no roster call", function()
		C_GuildInfo.GuildRoster = nil
		falsy(R():Request())
	end)

	it("rebuilds lazily: events only mark it dirty, a read builds once", function()
		R():Members()
		local builds = R().state.builds
		for _ = 1, 5 do Mock.Fire("GUILD_ROSTER_UPDATE") end
		eq(R().state.builds, builds)
		R():Members(); R():Members()
		eq(R().state.builds, builds + 1)
	end)

	it("while a view watches, a burst of events gives one rebuild after the delay and a Bus event", function()
		R():Members()
		R():Watch()
		Mock.Advance(3)   -- the answer to the first request and its rebuild
		local builds, seen = R().state.builds, {}
		AzerothAccord.Bus:On("ROSTER_UPDATED", function(n) seen[#seen + 1] = n end)
		for _ = 1, 10 do Mock.Fire("GUILD_ROSTER_UPDATE") end
		Mock.Advance(0.5)
		eq(R().state.builds, builds)
		Mock.Advance(1)
		eq(R().state.builds, builds + 1)
		deepEq(seen, { 3 })
		R():Unwatch()
		Mock.Fire("GUILD_ROSTER_UPDATE")
		Mock.Advance(5)
		eq(R().state.builds, builds + 1)
	end)

	it("asks the server when a view starts watching, but not twice in 15 seconds", function()
		local n = countRequests()
		R():Watch(); R():Unwatch(); R():Watch()
		eq(n[1], 1)
	end)

	it("follows the shared records and forgets the list on a change of guild", function()
		R():Members()
		R():Watch()
		local builds = R().state.builds
		AzerothAccord.Bus:Emit("STORE_CHANGED", "recipes", "x", "remote")
		Mock.Advance(2)
		eq(R().state.builds, builds + 1)
		AzerothAccord.Bus:Emit("GUILD_CHANGED", nil, "Test/Old")
		eq(#R().state.list, 0)
	end)

	it("reports itself in /accord debug without names", function()
		R():Build()
		local text = table.concat(R():DebugLines(), "\n")
		matches(text, "3 member%(s%)")
		falsy(text:find("Bob", 1, true))
	end)
end)

describe("a guild of 1000 members", function()
	local function big()
		local list = {}
		for i = 1, 999 do
			list[i] = { name = "M" .. i, level = 1 + i % 60, class = (i % 2 == 0) and "MAGE" or "WARRIOR", rank = 2 + i % 3,
				online = i % 5 == 0, guid = ("Player-1-%08X"):format(0x5000 + i), lastOnline = { 0, 0, i % 20, 0 },
				professions = { { id = 171, name = "Alchemy", rank = i % 300 }, { id = 164, name = "Blacksmithing", rank = 1 } },
				discord = "d" .. i }
		end
		return list
	end
	before_boot(function(M) guild(big()) end)

	it("builds within the budget, with one pass per source and no repeated calls", function()
		fill{ professions = true, discord = true }
		local calls = { roster = 0, club = 0 }
		local rosterInfo, memberInfo = GetGuildRosterInfo, C_Club.GetMemberInfo
		GetGuildRosterInfo = function(...) calls.roster = calls.roster + 1 return rosterInfo(...) end
		C_Club.GetMemberInfo = function(...) calls.club = calls.club + 1 return memberInfo(...) end
		local started = Mock.RealClock()
		R():Build()
		local took = Mock.RealClock() - started
		eq(#R():Members(), 1000)
		eq(calls.roster, 1000)
		eq(calls.club, 1000)
		truthy(took < 3, "took " .. took .. " s (the mock client itself rebuilds its list on every call)")
		eq(R().state.native, 999)
		eq(R():ByName("M500").professions[1].rank, 500 % 300)
	end)
end)

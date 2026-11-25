-- Integrations with raid and loot addons (M10.2; ADR 0022): the known addons, their detection (loaded, missing,
-- disabled), the levels (FDCP's public API: absent, another version, the known version), nothing of another addon ever
-- written or switched on, the guild's choice of a source per datum (officers only, synced as `guildcfg`), and the Raid
-- view's section "Raid and loot addons in the guild" (detection here, and who has each addon from the M9.9 census).
local function A() return AzerothAccord end
local function I() return AzerothAccord.Integrations end
local function S() return AzerothAccord.Store end

local FOLDER, GLOBAL = "FinlandDragonCreditPoints", "FinlandDragonCreditPointsAPI"
local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-000000FF"

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 3, members = {
		{ name = "Bob", rank = 3, guid = BOB }, { name = "Officer", rank = 1, guid = OFF },
	} }
end

-- A stand-in for FDCP's table that remembers every key read and refuses every write.
local function fakeAPI(version)
	local reads, writes = {}, {}
	local api = setmetatable({}, {
		__index = function(_, k)
			reads[#reads + 1] = k
			if k == "API_VERSION" then return version end
			return nil
		end,
		__newindex = function(_, k) writes[#writes + 1] = k end,
	})
	return api, reads, writes
end

local function count(event)
	local n = { value = 0 }
	A().Bus:On(event, function() n.value = n.value + 1 end)
	return n
end

-- These tests cover the logic behind the switch "raid" (Core/Features.lua), which is off in releases: they turn it on.
-- tests of the switch off: Tests/test_features.lua.
local plainDescribe = describe
local function describe(name, body)
	plainDescribe(name, function()
		before_boot(function(M) M.features = { raid = true } end)
		body()
	end)
end

describe("the known addons", function()
	it("lists only loot and raid-roster addons, each id and folder once, and only FDCP's folder confirmed", function()
		local ids, folders = {}, {}
		for _, def in ipairs(I().KNOWN) do
			truthy(def.kind == "loot" or def.kind == "raid" or def.kind == "both", def.id)
			isNil(ids[def.id], def.id); isNil(folders[def.folder], def.folder)
			ids[def.id], folders[def.folder] = true, true
			eq(def.confirmed == true, def.id == "fdcp", def.id)
		end
		eq(I().KNOWN[1].folder, FOLDER)
	end)

	it("asks FDCP to load first when it is there, without depending on it", function()
		eq(C_AddOns.GetAddOnMetadata("AzerothAccord", "OptionalDeps"), FOLDER)
		isNil(C_AddOns.GetAddOnMetadata("AzerothAccord", "Dependencies"))
		eq(A().FDCP.FOLDER, FOLDER); eq(A().FDCP.GLOBAL, GLOBAL); eq(A().FDCP.API_VERSION, 1)
	end)
end)

describe("detection", function()
	it("finds nothing when FDCP is not installed", function()
		local st = I():Detect("fdcp")
		eq(st.status, "missing"); isNil(st.level); eq(st.reason, "absent"); isNil(st.version)
		isNil(I():Level("fdcp"))
	end)

	it("sees an installed FDCP that is switched off, with its version, at no level", function()
		Mock.addons[FOLDER] = { loaded = false, enabled = false, version = "1.0.2" }
		local st = I():Detect("fdcp")
		eq(st.status, "disabled"); eq(st.version, "1.0.2"); isNil(st.level)
	end)

	it("sees an enabled FDCP that did not load", function()
		Mock.addons[FOLDER] = { loaded = false, version = "1.0.2" }
		eq(I():Detect("fdcp").status, "installed")
	end)

	it("stays at level 0 when FDCP is loaded without its API table", function()
		Mock.addons[FOLDER] = { loaded = true, version = "0.9.0" }
		local st = I():Detect("fdcp")
		eq(st.status, "loaded"); eq(st.level, 0); eq(st.reason, "absent"); eq(st.version, "0.9.0")
	end)

	it("falls back to level 0 with an unknown API version, and says which", function()
		Mock.addons[FOLDER] = { loaded = true, version = "2.0.0" }
		_G[GLOBAL] = fakeAPI(2)
		local st = I():Detect("fdcp")
		eq(st.level, 0); eq(st.reason, "version"); eq(st.apiVersion, 2)
		_G[GLOBAL] = fakeAPI("one")
		eq(I():Detect("fdcp").level, 0)
		_G[GLOBAL] = "not a table"
		eq(I():Detect("fdcp").reason, "absent")
	end)

	it("reaches level 1 with API_VERSION 1, reading nothing else and writing nothing", function()
		Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
		local api, reads, writes = fakeAPI(1)
		_G[GLOBAL] = api
		local st = I():Detect("fdcp")
		eq(st.status, "loaded"); eq(st.level, 1); eq(st.apiVersion, 1); isNil(st.reason)
		deepEq(reads, { "API_VERSION" }); deepEq(writes, {})
	end)

	it("counts the published table even when the folder name is not found", function()
		_G[GLOBAL] = fakeAPI(1)
		eq(I():Detect("fdcp").level, 1)
	end)

	it("survives an API table that raises when it is read", function()
		Mock.addons[FOLDER] = { loaded = true }
		_G[GLOBAL] = setmetatable({}, { __index = function() error("boom") end })
		local st = I():Detect("fdcp")
		eq(st.level, 0); eq(st.reason, "version")
		eq(#Mock.errors, 0)
	end)

	it("detects the other known addons at level 0 only", function()
		Mock.addons.Gargul = { loaded = true, version = "7.1" }
		Mock.addons.RaidCore = { loaded = false, enabled = false }
		eq(I():Detect("gargul").status, "loaded"); eq(I():Detect("gargul").level, 0); eq(I():Detect("gargul").version, "7.1")
		eq(I():Detect("raidcore").status, "disabled"); isNil(I():Detect("raidcore").level)
		eq(I():Detect("wlc").status, "missing")
		isNil(I():Detect("unknown"))
	end)

	it("never loads, enables or disables another addon", function()
		local touched = {}
		for _, fn in ipairs({ "EnableAddOn", "DisableAddOn", "LoadAddOn", "EnableAllAddOns", "DisableAllAddOns", "SaveAddOns" }) do
			C_AddOns[fn] = function() touched[#touched + 1] = fn end
		end
		Mock.addons[FOLDER] = { loaded = false, enabled = false }
		Mock.addons.Gargul = { loaded = false }
		I():Refresh()
		for _, st in ipairs(I():List()) do eq(type(st.status), "string") end
		deepEq(touched, {})
	end)

	it("detects again at login and when a known addon loads, and says so only on a change", function()
		local changed = count("INTEGRATIONS_CHANGED")
		eq(I():Level("fdcp"), nil)
		Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
		_G[GLOBAL] = fakeAPI(1)
		Mock.Fire("ADDON_LOADED", FOLDER)
		eq(I():Level("fdcp"), 1); eq(changed.value, 1)
		Mock.Fire("ADDON_LOADED", FOLDER)
		eq(changed.value, 1)
		Mock.Fire("ADDON_LOADED", "SomethingElse")
		eq(changed.value, 1)
	end)

	it("finds FDCP that loaded before Accord at PLAYER_LOGIN", function()
		boot(function(M)
			M.addons[FOLDER] = { loaded = true, version = "1.0.2" }
			FinlandDragonCreditPointsAPI = fakeAPI(1)
		end)
		eq(I():Level("fdcp"), 1)
		Mock.addons[FOLDER] = nil
	end)

	it("adds a section to /accord debug without names", function()
		Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
		_G[GLOBAL] = fakeAPI(3)
		I():Refresh()
		local lines = I():DebugLines()
		eq(lines[1], "fdcp: loaded 1.0.2, level 0 (API version 3)")
		eq(lines[#lines], "Sources: raid accord, loot none (defaults)")
	end)
end)

describe("the sources", function()
	before_boot(function() guild(3) end)

	it("are Accord for the raid and none for the loot until an officer chooses", function()
		eq(I():Source("raid"), "accord"); eq(I():Source("loot"), "none")
		eq(I():Provider("raid"), I().OWN); isNil(I():Provider("loot"))
		isNil(I():Source("attendance"))
		falsy(I():Uses("fdcp"))
	end)

	it("cannot be changed by a member", function()
		local ok, why = I():SetSource("raid", "fdcp")
		falsy(ok); eq(why, "officer")
		eq(I():Source("raid"), "accord")
		isNil(S():Get("guildcfg", "sources"))
	end)

	it("refuses a record from a member, or one with an unknown choice", function()
		local rec = { id = "sources", author = BOB, rev = 1, time = GetServerTime(), raid = "fdcp", loot = "fdcp" }
		local ok, why = S():Accept("guildcfg", rec, { sender = "Bob" })
		falsy(ok); eq(why, "authority")
		local bad = { id = "sources", author = OFF, rev = 1, time = GetServerTime(), raid = "fdcp", loot = "dkp" }
		ok, why = S():Accept("guildcfg", bad, { sender = "Officer" })
		falsy(ok); eq(why, "owner")
		local other = { id = "motd", author = OFF, rev = 1, time = GetServerTime(), raid = "fdcp", loot = "fdcp" }
		falsy(S():Accept("guildcfg", other, { sender = "Officer" }))
		eq(I():Source("raid"), "accord")
	end)

	it("follows an officer's record and says so", function()
		local changed = count("SOURCES_CHANGED")
		local rec = { id = "sources", author = OFF, rev = 1, time = GetServerTime(), raid = "fdcp", loot = "fdcp" }
		truthy(S():Accept("guildcfg", rec, { sender = "Officer" }))
		eq(I():Source("raid"), "fdcp"); eq(I():Source("loot"), "fdcp")
		eq(I():Provider("raid"), A().FDCP); eq(I():Provider("loot"), A().FDCP)
		truthy(I():Uses("fdcp"))
		eq(changed.value, 1)
	end)
end)

describe("an officer choosing", function()
	before_boot(function() guild(1) end)

	it("writes one record with both choices and keeps it through a reload", function()
		local changed = count("SOURCES_CHANGED")
		truthy(I():CanChoose())
		truthy(I():SetSource("raid", "fdcp"))
		local rec = S():Get("guildcfg", "sources")
		eq(rec.raid, "fdcp"); eq(rec.loot, "none"); eq(rec.author, ME); eq(rec.rev, 1)
		eq(changed.value, 1)
		truthy(I():SetSource("raid", "fdcp"))            -- the same choice again writes nothing
		eq(S():Get("guildcfg", "sources").rev, 1)
		truthy(I():SetSource("loot", "fdcp"))
		eq(S():Get("guildcfg", "sources").rev, 2)
		local ok, why = I():SetSource("loot", "dkp")
		falsy(ok); eq(why, "choice")
		Mock.Reload()
		eq(I():Source("raid"), "fdcp"); eq(I():Source("loot"), "fdcp")
	end)

	it("goes back to the defaults in another guild", function()
		truthy(I():SetSource("raid", "fdcp"))
		local changed = count("SOURCES_CHANGED")
		Mock.guild.Set{ name = "Other", myRank = 1, members = {} }
		A().Role:Refresh()
		eq(I():Source("raid"), "accord")
		truthy(changed.value >= 1)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Who has each addon in the guild (the Raid view, from the census of M9.9; SPEC-10 Q11, Q17)
---------------------------------------------------------------------------------------------------------------------
local function V() return AzerothAccord.RaidView end

local function lines()
	local out = {}
	for _, l in ipairs(V().Lines(V().Model())) do out[#out + 1] = l.text end
	return table.concat(out, "\n")
end

local function hasLine(text, line)
	return ("\n" .. text .. "\n"):find("\n" .. line .. "\n", 1, true) ~= nil
end

local function census(rank, opts)
	return function(M)
		M.features = { raid = true, census = opts == nil or opts.census ~= false }
		guild(rank)
		M.addons.Gargul = { loaded = true, version = "7.1" }
	end
end

-- Bob and the officer share their lists; this client publishes its own after the first HELLO.
local function shared(refused)
	for _, r in ipairs({ { BOB, "Bob", { { "Gargul", "7.0" } } }, { OFF, "Officer", { { "Gargul", "7.0" }, { "Questie", "9.1" } } } }) do
		local rec = { id = r[1], author = r[1], rev = 1, time = GetServerTime(), l = r[3] }
		eq(S():Receive("addons", { rec }, r[2], "GUILD"), refused and 0 or 1)
	end
	A().Bus:Emit("SYNC_HELLO", true)
	Mock.Advance(130)
end

local GARGUL_HERE = "This client: loaded 7.1 · detection only (level 0) · folder name not confirmed in game yet"
local GARGUL_GUILD = "In the guild: 3 of 3 members who share their list (100%) · versions 7.0 (2), 7.1 (1)"

describe("who has each addon: a member", function()
	before_boot(census(3))

	it("sees the detection here, the counts and the versions, and only its own entry", function()
		shared()
		local t = lines()
		contains(t, "Raid and loot addons in the guild")
		truthy(hasLine(t, "Only officers and the Guild Master see who has each addon: you see the counts and your own entry."))
		truthy(hasLine(t, "Gargul · loot"))
		truthy(hasLine(t, GARGUL_HERE))
		truthy(hasLine(t, GARGUL_GUILD))
		truthy(hasLine(t, "Testchar (you) · 7.1"))
		falsy(t:find("Bob", 1, true), "no other member's name")
		falsy(t:find("Officer ·", 1, true))
		truthy(hasLine(t, "This client: not installed · folder name not confirmed in game yet"))
		truthy(hasLine(t, "In the guild: none of the 3 members who share their list"))
		falsy(t:find("Questie", 1, true), "only the known raid and loot addons")
	end)

	it("says when nobody shares yet and the player does not share, without an empty list", function()
		A().Config:Set("account.settings.shareAddons", false)
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(130)
		local t = lines()
		truthy(hasLine(t, "Nobody in the guild shares an addon list yet."))
		contains(t, "Your list is not shared, so you are not counted")
		truthy(hasLine(t, "Testchar (you, not counted) · 7.1"))
		falsy(t:find("In the guild:", 1, true))
		eq(S():Count("addons"), 0)
	end)
end)

describe("who has each addon: an officer", function()
	before_boot(census(1))

	it("sees every member who has it, with the version", function()
		shared()
		local t = lines()
		truthy(hasLine(t, "In Accord only officers and the Guild Master see these names."))
		truthy(hasLine(t, GARGUL_GUILD))
		truthy(hasLine(t, "Bob · 7.0"))
		truthy(hasLine(t, "Officer · 7.0"))
		truthy(hasLine(t, "Testchar (you) · 7.1"))
		local bob = t:find("Bob · 7.0", 1, true)
		truthy(bob < t:find("Officer · 7.0", 1, true) and bob > t:find(GARGUL_GUILD, 1, true), "by name, under the addon")
	end)

	it("shows FDCP read at level 1, and writes nothing into it", function()
		local api, _, writes = fakeAPI(1)
		Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
		_G[GLOBAL] = api
		I():Refresh()
		local t = lines()
		truthy(hasLine(t, "Finland Dragon Credit Points (FDCP) · loot and raid roster"))
		truthy(hasLine(t, "This client: loaded 1.0.2 · Accord reads its public interface (level 1)"))
		deepEq(writes, {})
		_G[GLOBAL] = nil
	end)
end)

describe("who has each addon: the census switched off", function()
	before_boot(census(1, { census = false }))

	it("says so in one line and still shows the detection here", function()
		shared(true)
		local t = lines()
		truthy(hasLine(t, "The addon census is switched off: Accord does not know who in the guild has these addons."))
		truthy(hasLine(t, GARGUL_HERE))
		falsy(t:find("In the guild:", 1, true))
		falsy(t:find("Bob", 1, true)); falsy(t:find("(you)", 1, true))
		isNil(I():Holders("gargul"))
	end)
end)

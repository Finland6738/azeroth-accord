-- Reading FDCP through its public API (M11.7; ADR 0022; SPEC-10 Q10), with a fake `FinlandDragonCreditPointsAPI`:
-- FDCP absent, another API version, not ready yet, a member's client (SNAPSHOT), an officer's client (LEDGER), the
-- callbacks that refresh the Raid view and the member card (and go away when the source changes away from FDCP), a
-- getter that gives nil or raises, nothing ever written to FDCP, and no attendance shown.
local function A() return AzerothAccord end
local function I() return AzerothAccord.Integrations end
local function F() return AzerothAccord.FDCP end
local function V() return AzerothAccord.RaidView end

local FOLDER, GLOBAL = "FinlandDragonCreditPoints", "FinlandDragonCreditPointsAPI"
local ANN, BOB = "Player-1-00000A01", "Player-1-00000B0B"
local PROT, HOLY, RET, FROST = 66, 65, 70, 64

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 3, members = {
		{ name = "Ann", level = 60, class = "PALADIN", rank = 1, guid = ANN },
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
	} }
end

local function short(name) return type(name) == "string" and (name:match("^[^%-]+") or name) or name end

-- The fake API: data the test changes, every function call and every write remembered, callbacks kept by event.
local function fake(opts)
	opts = opts or {}
	local f = { calls = {}, writes = {}, callbacks = {}, version = opts.version or 1 }
	f.data = {
		ready = opts.ready ~= false, source = opts.source or "LEDGER",
		season = { id = "S3", name = "Season 3", state = "OPEN", updated = "2026-11-20", extra = "dropped" },
		pool = {}, credits = {}, night = nil, rules = nil,
	}
	local fns = {}
	function fns.IsReady() return f.data.ready end
	function fns.GetVersion() return "1.0.2", 1 end
	function fns.GetSource() if f.data.ready then return f.data.source end end
	function fns.GetSeason() return f.data.season end
	function fns.GetPool() return f.data.pool end
	function fns.GetMember(name)
		for _, e in ipairs(f.data.pool) do if short(e.name) == short(name) then return e end end
	end
	function fns.GetCredits(name) return f.data.credits[short(name)] end
	function fns.GetCreditList() return {} end
	function fns.GetNight() return f.data.night end
	function fns.GetRules() return f.data.rules end
	function fns.GetEvents() return { "READY", "SEASON_CHANGED", "POOL_CHANGED", "CREDITS_CHANGED", "NIGHT_CHANGED", "RULES_CHANGED" } end
	function fns.RegisterCallback(event, fn)
		local list = f.callbacks[event] or {}
		f.callbacks[event] = list
		for _, x in ipairs(list) do if x == fn then return true end end
		list[#list + 1] = fn
		return true
	end
	function fns.UnregisterCallback(event, fn)
		local list = f.callbacks[event] or {}
		for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) return true end end
		return false
	end
	for k, fn in pairs(opts.override or {}) do fns[k] = fn end
	f.api = setmetatable({}, {
		__index = function(_, k)
			if k == "API_VERSION" then return f.version end
			local fn = fns[k]
			if not fn then return nil end
			return function(...)
				f.calls[#f.calls + 1] = k
				return fn(...)
			end
		end,
		__newindex = function(_, k) f.writes[#f.writes + 1] = k end,
	})
	function f.fire(event) for _, fn in ipairs(f.callbacks[event] or {}) do fn(event) end end
	function f.count()
		local n = 0
		for _, list in pairs(f.callbacks) do n = n + #list end
		return n
	end
	return f
end

-- An officer's ledger: every field, the open night with an absent list FDCP would never give (it must not show anyway).
local function officerData(f)
	f.data.source = "LEDGER"
	f.data.pool = {
		{ name = "Ann-TestRealm", faction = "Alliance", class = "PALADIN", role = "TANK", ms1 = PROT, ms2 = HOLY, os = RET,
			status = "ACTIVE", alts = { "Annalt-TestRealm" }, twin = "Anna-TestRealm", avail = { "MON", "WED" } },
		{ name = "Bob-TestRealm", faction = "Alliance", class = "MAGE", role = "DAMAGER", ms1 = FROST, status = "TRIAL", alts = {} },
	}
	f.data.credits = {
		Ann = { name = "Ann-TestRealm", credits = 4, place = 2, of = 18, faction = "Alliance", viaAlt = false },
		Bob = { name = "Bob-TestRealm", credits = 1.5, place = 1, of = 18, faction = "Alliance", viaAlt = false },
		Testchar = { name = "Testchar-TestRealm", credits = 7, place = 9, of = 18, faction = "Alliance", viaAlt = false },
	}
	f.data.night = { id = "N1", date = "2026-11-24", instanceID = 409, instance = "Molten Core", size = 40, difficulty = "normal",
		faction = "Alliance", raid = { "Ann-TestRealm", "Testchar-TestRealm" }, bench = { "Bob-TestRealm" }, absent = { "Zed-TestRealm" } }
	f.data.rules = { source = "GUILD", preset = "PATTO", custom = true, metric = "credits", startCredits = 0, awardMode = "confirm",
		costs = { weapon = { [3] = 2, [4] = 2, [5] = "council" }, cosmetic = { [3] = 0, [4] = 0 } },
		responseMultiplier = { MS = 1, OS = 0, TMOG = 0 }, lateJoin = "min", bench = { effect = "bonus", amount = 1 },
		penalties = { absence = 1, cheat = 2 }, attendance = { Zed = 0 } }
end

-- A member's snapshot: the playing mains without ms2, os, twin or avail; no night; the Patto defaults.
local function memberData(f)
	f.data.source = "SNAPSHOT"
	f.data.season.asOf = GetServerTime() - 3600
	f.data.pool = {
		{ name = "Ann-TestRealm", faction = "Alliance", class = "PALADIN", role = "TANK", ms1 = PROT, status = "ACTIVE", alts = {} },
		{ name = "Bob-TestRealm", faction = "Alliance", class = "MAGE", role = "DAMAGER", ms1 = FROST, status = "ACTIVE", alts = { "Bobalt-TestRealm" } },
	}
	f.data.credits = {
		Bob = { name = "Bob-TestRealm", credits = 3, place = 5, of = 12, faction = "Alliance", viaAlt = false },
		Bobalt = { name = "Bob-TestRealm", credits = 3, place = 5, of = 12, faction = "Alliance", viaAlt = true },
	}
	f.data.night = nil
	f.data.rules = { source = "DEFAULT", preset = "PATTO", custom = false, metric = "credits", startCredits = 0, awardMode = "confirm",
		costs = { weapon = { [3] = 2, [4] = 2, [5] = "council" } }, responseMultiplier = { MS = 1, OS = 0, TMOG = 0 }, lateJoin = "min",
		bench = { effect = "none", amount = 1 }, penalties = { absence = 1, cheat = 2 } }
end

local function install(f)
	Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
	_G[GLOBAL] = f and f.api or nil
	I():Refresh()
end

-- The guild's choice, as an officer (Ann) wrote it.
local function choose(raid, loot)
	local held = A().Store:Get("guildcfg", "sources")
	local rec = { id = "sources", author = ANN, rev = (held and held.rev or 0) + 1, time = GetServerTime(), raid = raid, loot = loot }
	truthy(A().Store:Accept("guildcfg", rec, { sender = "Ann" }))
end

local function texts(lines)
	local out = {}
	for _, l in ipairs(lines or V().Lines(V().Model())) do out[#out + 1] = l.text end
	return out
end
local function all() return table.concat(texts(), "\n") end

local function has(text) return all():find(text, 1, true) ~= nil end

local function card(guid)
	local e = A().Roster:ByGUID(guid)
	local s = V().CardSection(e)
	if not s then return nil end
	local out = {}
	for _, l in ipairs(s.lines) do out[#out + 1] = l.text end
	return out
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

describe("without FDCP as a source", function()
	before_boot(function() guild(3) end)

	it("reads nothing from FDCP and registers no callback, even at level 1", function()
		local f = fake()
		officerData(f)
		install(f)
		eq(I():Level("fdcp"), 1)
		local t = all()
		contains(t, "the declarations (MS1, MS2, OS) are in the Season view"); contains(t, "The guild has not chosen a loot addon")
		isNil(card(BOB))
		eq(f.count(), 0); isNil(F().watching)
		deepEq(f.calls, {})
	end)
end)

describe("FDCP chosen but not readable", function()
	before_boot(function() guild(3) end)

	it("says FDCP is missing, on the view and the card, without errors", function()
		choose("fdcp", "fdcp")
		install(nil)
		Mock.addons[FOLDER] = nil
		I():Refresh()
		contains(all(), "it is not loaded on this client")
		contains(all(), "Read from FDCP when it is available on this client.")
		deepEq(card(BOB), { "FDCP is not readable on this client." })
		isNil(F().Pool()); isNil(F().Credits("Bob")); isNil(F().Rules()); isNil(F().Night()); falsy(F().Ready())
		isNil(F().watching)
		eq(#Mock.errors, 0)
	end)

	it("says FDCP is switched off", function()
		choose("fdcp", "none")
		Mock.addons[FOLDER] = { loaded = false, enabled = false, version = "1.0.2" }
		I():Refresh()
		contains(all(), "switched off")
	end)

	it("stays at level 0 with another API version, calling none of its functions", function()
		choose("fdcp", "fdcp")
		local f = fake({ version = 2 })
		officerData(f)
		install(f)
		eq(I():Level("fdcp"), 0)
		contains(all(), "version 2 of its interface")
		deepEq(card(BOB), { "FDCP is not readable on this client." })
		isNil(F().Pool()); isNil(F().Credits("Bob"))
		deepEq(f.calls, {}); eq(f.count(), 0)
	end)

	it("waits while FDCP is not ready, then reads once READY comes", function()
		choose("fdcp", "fdcp")
		local f = fake({ ready = false })
		officerData(f)
		install(f)
		eq(f.count(), 6)                               -- one Accord function per FDCP event
		contains(all(), "still reading the guild roster")
		local heard = {}
		A().Bus:On("FDCP_CHANGED", function(event) heard[#heard + 1] = event end)
		f.data.ready = true
		f.fire("READY")
		deepEq(heard, { "READY" })
		contains(all(), "Pool: 2 mains")
	end)

	it("passes on a READY that happened before Accord registered", function()
		local heard = {}
		A().Bus:On("FDCP_CHANGED", function(event) heard[#heard + 1] = event end)
		local f = fake()
		install(f)
		choose("fdcp", "none")
		deepEq(heard, { "READY" })
	end)
end)

describe("a member's client (SNAPSHOT)", function()
	before_boot(function() guild(3) end)

	it("shows the pool without MS2 and OS, says the lineup is for officers, and the rules are the defaults", function()
		choose("fdcp", "fdcp")
		local f = fake()
		memberData(f)
		install(f)
		local t = texts()
		contains(table.concat(t, "\n"), "FDCP 1.0.2 · read from the credits table an officer sent")
		contains(table.concat(t, "\n"), "Season Season 3: open")
		contains(table.concat(t, "\n"), "MS2 and OS are shown on officers' clients only")
		local bobLine
		for _, line in ipairs(t) do if line:find("^Bob") then bobLine = line end end
		notNil(bobLine)
		contains(bobLine, "MS1 #64")
		falsy(bobLine:find("MS2", 1, true)); falsy(bobLine:find("OS ", 1, true))
		contains(table.concat(t, "\n"), "The lineup of the night is on officers' clients only")
		contains(table.concat(t, "\n"), "The defaults of FDCP's Patto preset")
		contains(table.concat(t, "\n"), "FDCP has no credits for you on this client.")
		isNil(F().Night())
		eq(F().Rules().source, "DEFAULT")
	end)

	it("shows a member's credits and place on the card, and an alt's through its main", function()
		choose("fdcp", "fdcp")
		local f = fake()
		memberData(f)
		install(f)
		deepEq(card(BOB), { "Credits: 3", "Loot queue: place 5 of 12" })
		deepEq(card(ANN), { "No FDCP credits on this client." })
		local c = F().Credits("Bobalt")
		truthy(c.viaAlt); eq(c.name, "Bob-TestRealm")
	end)
end)

describe("an officer's client (LEDGER)", function()
	before_boot(function() guild(1) end)

	it("shows MS2, OS, the trial, the lineup and the bench, and the guild's rules; never an absent list", function()
		truthy(I():SetSource("raid", "fdcp")); truthy(I():SetSource("loot", "fdcp"))
		local f = fake()
		officerData(f)
		install(f)
		local t = all()
		contains(t, "read from the guild's ledger (officer)")
		contains(t, "Ann · Paladin tank · MS1 #66 · MS2 #65 · OS #70")
		contains(t, "Bob · Mage dps · MS1 #64 · trial")
		contains(t, "Molten Core, 40 players, 2026-11-24")
		contains(t, "In the raid (2): Ann, Testchar")
		contains(t, "On the bench (1): Bob")
		contains(t, "You: 7 credits, place 9 of 18 in the loot queue")
		contains(t, "The guild's rules, as set in FDCP.")
		contains(t, "Preset: Patto (changed by the guild)")
		contains(t, "Weapon: 2, 2, council")
		contains(t, "Cosmetic: 0, 0, -")
		contains(t, "Bench: credit bonus 1")
		falsy(t:find("Zed", 1, true))
		falsy(t:find("Anna", 1, true))
		deepEq(card(BOB), { "Credits: 1.5", "Loot queue: place 1 of 18" })
		eq(#Mock.errors, 0)
	end)

	it("hands out copies: changing what it read changes nothing in FDCP, and nothing is written", function()
		truthy(I():SetSource("raid", "fdcp"))
		local f = fake()
		officerData(f)
		install(f)
		local pool = F().Pool()
		pool[1].ms1 = 0
		pool[1].alts[1] = "Changed"
		eq(f.data.pool[1].ms1, PROT); eq(f.data.pool[1].alts[1], "Annalt-TestRealm")
		-- the declared days are read since M10.8 (the Availability view), as a copy like the rest
		pool[1].avail[1] = "SUN"
		deepEq(f.data.pool[1].avail, { "MON", "WED" })
		isNil(F().Night().absent)
		isNil(F().Rules().attendance)
		isNil(F().Season().extra)
		deepEq(f.writes, {})
	end)
end)

describe("callbacks", function()
	before_boot(function() guild(1) end)

	it("refresh the open Raid view and member card, and go away when the source changes away from FDCP", function()
		local f = fake()
		officerData(f)
		install(f)
		eq(f.count(), 0)
		truthy(I():SetSource("loot", "fdcp"))
		eq(f.count(), 6)
		truthy(A().Shell:OpenView("raid"))
		Mock.Advance(1)
		local before = table.concat(texts(V().shown), "\n")
		contains(before, "You: 7 credits, place 9 of 18")
		f.data.credits.Testchar = { name = "Testchar-TestRealm", credits = 8, place = 10, of = 18 }
		f.fire("CREDITS_CHANGED")
		Mock.Advance(1)
		contains(table.concat(texts(V().shown), "\n"), "You: 8 credits, place 10 of 18")
		truthy(I():SetSource("raid", "fdcp"))
		eq(f.count(), 6)                                  -- still once per event
		truthy(I():SetSource("loot", "none"))
		eq(f.count(), 6)                                  -- the raid source still uses FDCP
		truthy(I():SetSource("raid", "accord"))
		eq(f.count(), 0); isNil(F().watching)
		eq(F().stats.unregistered, 6)
		f.fire("CREDITS_CHANGED")
		eq(#Mock.errors, 0)
	end)

	it("follow a source chosen by another officer on this client", function()
		local f = fake()
		officerData(f)
		install(f)
		choose("fdcp", "none")
		eq(f.count(), 6)
		choose("accord", "none")
		eq(f.count(), 0)
	end)
end)

describe("getters that give nothing", function()
	before_boot(function() guild(3) end)

	it("treat nil as not on this client, and a raising getter the same", function()
		choose("fdcp", "fdcp")
		local f = fake({ override = {
			GetPool = function() return nil end,
			GetRules = function() error("boom") end,
			GetSeason = function() return "not a table" end,
			GetCredits = function() return { name = "Bob", credits = "many" } end,
		} })
		install(f)
		isNil(F().Pool()); isNil(F().Rules()); isNil(F().Season()); isNil(F().Credits("Bob"))
		local t = all()
		contains(t, "FDCP gives no season pool on this client.")
		contains(t, "FDCP gives no rules summary on this client.")
		deepEq(card(BOB), { "No FDCP credits on this client." })
		eq(#Mock.errors, 0)
	end)

	it("say there is no data yet when FDCP has no source", function()
		choose("fdcp", "fdcp")
		local f = fake()
		f.data.source = nil
		install(f)
		isNil(F().Source()); isNil(F().Pool())
		contains(all(), "FDCP has no season data on this client yet")
	end)
end)

describe("opening FDCP", function()
	it("runs FDCP's own /fdcp command, and says false without one", function()
		falsy(F().Open())
		local ran = 0
		SlashCmdList.ACECONSOLE_FDCP = function() ran = ran + 1 end
		SLASH_ACECONSOLE_FDCP1 = "/fdcp"
		truthy(F().Open())
		eq(ran, 1)
	end)
end)

describe("the Raid view", function()
	before_boot(function(M) guild(3) M.player.locale = "itIT" end)

	it("opens on an Italian client, with FDCP and without, with the sources locked for a member", function()
		truthy(A().Shell:OpenView("raid"))
		Mock.Advance(1)
		local fr = V().frame
		falsy(fr.raidSeg.enabled); eq(fr.raidSeg:Active(), "accord"); eq(fr.lootSeg:Active(), "none")
		falsy(fr.open:IsShown())
		choose("fdcp", "fdcp")
		local f = fake()
		memberData(f)
		install(f)
		Mock.Advance(1)
		eq(fr.raidSeg:Active(), "fdcp")
		truthy(fr.open:IsShown())
		contains(table.concat(texts(V().shown), "\n"), "Pool: 2 personaggi principali")
		eq(#Mock.errors, 0)
	end)
end)

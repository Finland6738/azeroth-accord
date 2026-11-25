-- The season roster for officers (M10.4; SPEC-14 §4.5, §4.6, §7.1; SPEC-10 Q21): the role counts by MS1, the cover MS2
-- would add and the gaps against the target composition the officers set, the same from FDCP's pool (a fake FDCP),
-- members without a declaration listed apart and never as a gap, and the export as CSV and as text for Discord.

local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Se() return AzerothAccord.Season end
local function C() return AzerothAccord.Composition end
local function V() return AzerothAccord.SeasonView end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A77", "Player-1-000000FF"
local BOB2, CARL = "Player-1-00000B02", "Player-1-00000CA1"

local FOLDER, GLOBAL = "FinlandDragonCreditPoints", "FinlandDragonCreditPointsAPI"

local function setup(myRank)
	return function(M)
		M.features = { season = true }
		M.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
			{ name = "Bobalt", level = 60, class = "PRIEST", rank = 3, guid = BOB2 },
			{ name = "Ann", level = 60, class = "DRUID", rank = 3, guid = ANN },
			{ name = "Carl", level = 60, class = "ROGUE", rank = 3, guid = CARL },
			{ name = "Officer", level = 60, class = "PALADIN", rank = 1, guid = OFF },
		} }
	end
end

local function bobAccount()
	local t = GetServerTime()
	for _, g in ipairs({ BOB, BOB2 }) do
		S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = t, token = "TB", chars = { { guid = BOB }, { guid = BOB2 } } }
	end
	A().Accounts:MarkDirty()
end

local function declare(guid, sender, fields)
	local t = GetServerTime()
	local rec = { id = "E:1:" .. guid, author = guid, rev = 1, time = t, kind = "entry", n = 1, unsure = false, first = t }
	for k, v in pairs(fields) do rec[k] = v end
	local ok, why = S():Accept("season", rec, { sender = sender })
	truthy(ok, why)
end

-- The player (a warrior): tank, MS2 melee. Bob: ranged. Ann: tank, MS2 healer. Officer: not sure yet. Carl: nothing.
local function declarations()
	truthy(Se():Open("Naxx"))
	truthy(Se():Declare({ ms1 = { spec = "PROTECTION", role = "tank" }, ms2 = { spec = "FURY", role = "melee" },
		note = "Mon, \"Wed\"" }))
	declare(BOB, "Bob", { class = "MAGE", ms1 = { spec = "FROST", role = "ranged" } })
	declare(ANN, "Ann", { class = "DRUID", ms1 = { spec = "FERAL", role = "tank" }, ms2 = { spec = "RESTORATION", role = "healer" },
		os = { spec = "BALANCE", role = "ranged" } })
	declare(OFF, "Officer", { class = "PALADIN", unsure = true })
end

local function text()
	local out = {}
	for _, l in ipairs(V().Lines(V().Model())) do out[#out + 1] = l.text end
	return table.concat(out, "\n")
end

local function line(start)
	for l in (text() .. "\n"):gmatch("([^\n]*)\n") do
		if l:sub(1, #start) == start then return l end
	end
	return nil
end

-- the line after the heading that starts with `start`
local function after(start)
	local next_ = false
	for l in (text() .. "\n"):gmatch("([^\n]*)\n") do
		if next_ then return l end
		next_ = l:sub(1, #start) == start
	end
	return nil
end

describe("the target composition", function()
	before_boot(setup(1))

	it("is set by an officer and synced as the guild setting \"target\", beside the sources", function()
		isNil(C():Target())
		truthy(C():SetTarget({ size = 40, tank = 4, healer = 10, melee = 12, ranged = 14 }))
		local rec = S():Get("guildcfg", "target")
		eq(rec.size, 40); eq(rec.healer, 10); eq(rec.rev, 1)
		truthy(C():SetTarget({ size = 40, tank = 4, healer = 10, melee = 12, ranged = 14 }))
		eq(S():Get("guildcfg", "target").rev, 1, "the same target changes nothing")
		truthy(C():SetTarget({ size = 20, tank = 2, healer = 5, melee = 6, ranged = 7 }))
		eq(C():Target().rev, 2)
		truthy(A().Integrations:SetSource("raid", "fdcp"))
		eq(A().Integrations:Source("raid"), "fdcp"); eq(C():Target().size, 20)
	end)

	it("refuses a size other than 10, 20, 25 or 40, a sum over it and a number that is not whole", function()
		for _, bad in ipairs({
			{ size = 15, tank = 1, healer = 1, melee = 1, ranged = 1 },
			{ size = 10, tank = 3, healer = 3, melee = 3, ranged = 2 },
			{ size = 10, tank = 1.5, healer = 1, melee = 1, ranged = 1 },
			{ size = 10, tank = -1, healer = 1, melee = 1, ranged = 1 },
			{ size = 10, tank = 1, healer = 1, melee = 1 },
		}) do
			local ok, why = C():SetTarget(bad)
			falsy(ok); eq(why, "content")
		end
		isNil(C():Target())
	end)

	it("reads the editor's fields: empty is 0, text is refused", function()
		local t = V().Target({ size = "25", tank = "2", healer = "", melee = "x", ranged = "8" })
		eq(t.size, 25); eq(t.tank, 2); eq(t.healer, 0); isNil(t.melee); eq(t.ranged, 8)
	end)
end)

describe("the target composition for a member", function()
	before_boot(setup(3))

	it("cannot be set, and a member's record is refused", function()
		local ok, why = C():SetTarget({ size = 10, tank = 2, healer = 3, melee = 2, ranged = 3 })
		falsy(ok); eq(why, "officer")
		local rec = { id = "target", author = BOB, rev = 1, time = GetServerTime(), size = 10, tank = 2, healer = 3, melee = 2, ranged = 3 }
		ok, why = S():Accept("guildcfg", rec, { sender = "Bob" })
		falsy(ok); eq(why, "authority")
		rec.author = OFF
		truthy(S():Accept("guildcfg", rec, { sender = "Officer" }))
		eq(C():Target().healer, 3)
		eq(A().Integrations:Source("raid"), "accord")
	end)

	it("shows the counts and the declarations, but no target editor and no export", function()
		truthy(S():Accept("season", { id = "S:1", author = OFF, rev = 1, time = GetServerTime(), kind = "season", n = 1,
			name = "Naxx", start = 20261125, opened = GetServerTime() }, { sender = "Officer" }))
		declare(BOB, "Bob", { class = "MAGE", ms1 = { spec = "FROST", role = "ranged" } })
		contains(text(), "Ranged: 1")
		contains(text(), "MS1 Frost (ranged dps)")
		local m = V().Model()
		falsy(m.canSetTarget); falsy(m.canExport)
		Mock.Slash("/accord season")
		falsy(V().frame.target:IsShown()); falsy(V().frame.export:IsShown())
		isNil(V():Export())
		local out, why = A().Export.Build("season", "csv", m.rows)
		isNil(out); eq(why, "officer")
		eq(#Mock.errors, 0)
	end)
end)

describe("the counts from Accord", function()
	before_boot(setup(1))

	it("count the roles by MS1 and what MS2 would add", function()
		declarations()
		local m = V().Model()
		eq(m.counts.ms1.tank, 2); eq(m.counts.ms1.ranged, 1); eq(m.counts.ms1.healer, 0); eq(m.counts.ms1.melee, 0)
		eq(m.counts.ms2.melee, 1); eq(m.counts.ms2.healer, 1); eq(m.counts.ms2.tank, 0); eq(m.counts.ms2.ranged, 0, "OS never counts")
		eq(m.counts.counted, 3); eq(#m.counts.unsure, 1); isNil(m.gaps)
		contains(text(), "No target composition")
		eq(line("Tank:"), "Tank: 2 · MS2 would add 0")
		contains(after("Not sure yet (1)"), "Officer")
	end)

	it("shows the gaps against the target and how many MS2 would cover", function()
		declarations()
		truthy(C():SetTarget({ size = 10, tank = 2, healer = 3, melee = 1, ranged = 1 }))
		local g = V().Model().gaps
		eq(g[1].missing, 0); eq(g[2].missing, 3); eq(g[2].cover, 1); eq(g[3].missing, 1); eq(g[3].cover, 1); eq(g[4].missing, 0)
		eq(line("Tank:"), "Tank: 2 · MS2 would add 0 · target 2 · target met")
		eq(line("Healers:"), "Healers: 0 · MS2 would add 1 · target 3 · missing 3 · MS2 covers 1")
		contains(text(), "Slots of the target without a role: 3")
	end)

	it("lists the accounts without a declaration apart, never as a gap", function()
		bobAccount()
		declarations()
		local m = V().Model()
		eq(#m.missing, 1, "Bob's alt is declared with his account; the unsure answer is a declaration")
		contains(m.missing[1], "Carl")
		eq(after("Without a declaration (1)"), "Carl")
		truthy(C():SetTarget({ size = 10, tank = 2, healer = 0, melee = 0, ranged = 1 }))
		for _, gap in ipairs(V().Model().gaps) do eq(gap.missing, 0) end
	end)

	it("counts only the current season", function()
		declarations()
		truthy(Se():Open("BWL"))
		local old = V().Model(1)
		isNil(old.counts); isNil(old.missing); eq(#old.rows, 4)
		eq(V().Model().counts.counted, 0)
		eq(#V().Model().missing, 6)
	end)

	it("lets an officer set the target in the view", function()
		declarations()
		Mock.Slash("/accord season")
		local f = V().frame
		truthy(f.target:IsShown()); truthy(f.export:IsShown())
		f.size:Select("20", true)
		f.counts.tank:SetText("3")
		truthy(V():SetTarget())
		eq(C():Target().size, 20); eq(C():Target().tank, 3); eq(C():Target().healer, 0)
		f.counts.tank:SetText("30")
		local ok, why = V():SetTarget()
		falsy(ok); eq(why, "content")
		contains(f.message:GetText(), "whole numbers")
		eq(#Mock.errors, 0)
	end)

	it("exports the shown declarations as CSV and as text for Discord", function()
		declarations()
		local m = V().Model()
		local out, info = A().Export.Build("season", "csv", m.rows)
		eq(info.rows, 4); eq(info.left, 0)
		local header, records = CSV.records(out)
		eq(table.concat(header, ","), "name,realm,class,role,ms1,ms2,os,unsure,note,declared_date")
		local by = {}
		for _, r in ipairs(records) do by[r.name] = r end
		eq(by.Ann.class, "DRUID"); eq(by.Ann.role, "tank"); eq(by.Ann.ms1, "Feral"); eq(by.Ann.ms2, "Restoration (healer)")
		eq(by.Ann.os, "Balance (ranged)"); eq(by.Ann.unsure, "no"); eq(by.Ann.declared_date, date("!%Y-%m-%d", GetServerTime()))
		eq(by.Officer.unsure, "yes"); eq(by.Officer.ms1, ""); eq(by.Officer.role, "")
		falsy(out:find("Player-", 1, true))
		falsy(by.Carl, "no declaration, no row")
		local discord = A().Export.Build("season", "discord", m.rows)
		contains(discord, "```\nSeason roster · Accord · ")
		contains(discord, "Feral Combat (tank)")
		contains(discord, "Not sure yet")
		truthy(V():Export())
		eq(A().ExportBox.kind, "season")
		eq(#Mock.errors, 0)
	end)
end)

describe("the counts from FDCP", function()
	before_boot(setup(1))

	-- The same declarations as FDCP would publish them (spec ids), plus an inactive main.
	local function fdcp(source)
		local member = source == "SNAPSHOT"
		local pool = {
			{ name = "Testchar-TestRealm", class = "WARRIOR", role = "TANK", ms1 = 73, ms2 = 72, status = "ACTIVE" },
			{ name = "Bobalt-TestRealm", class = "PRIEST", role = "DAMAGER", ms1 = 258, status = "ACTIVE", alts = { "Bob-TestRealm" } },
			{ name = "Ann-TestRealm", class = "DRUID", role = "TANK", ms1 = 104, ms2 = 105, os = 102, status = "TRIAL" },
			{ name = "Officer-TestRealm", class = "PALADIN", role = "DAMAGER", ms1 = 70, status = "INACTIVE" },
		}
		if member then
			for _, e in ipairs(pool) do e.ms2, e.os = nil, nil end
		end
		local api = { API_VERSION = 1,
			IsReady = function() return true end, GetVersion = function() return "1.0.2" end,
			GetSource = function() return source end, GetSeason = function() return { id = "S3", name = "Season 3", state = "OPEN" } end,
			GetPool = function() return pool end, GetNight = function() end,
			RegisterCallback = function() return true end, UnregisterCallback = function() return true end }
		Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
		_G[GLOBAL] = api
		A().Integrations:Refresh()
		truthy(A().Integrations:SetSource("raid", "fdcp"))
	end

	it("match FDCP's declarations, leaving its inactive mains out", function()
		fdcp("LEDGER")
		truthy(C():SetTarget({ size = 10, tank = 2, healer = 3, melee = 1, ranged = 1 }))
		local m = V().Model()
		eq(m.counts.ms1.tank, 2); eq(m.counts.ms1.ranged, 1); eq(m.counts.ms1.melee, 0)
		eq(m.counts.ms2.melee, 1); eq(m.counts.ms2.healer, 1)
		eq(m.inactive, 1); eq(m.gaps[2].cover, 1)
		contains(text(), "Inactive in FDCP, not counted: 1")
		-- Bob is an alt of a pool main; Officer is inactive there: both Carl and Officer have no counted entry
		eq(#m.missing, 2)
		contains(m.missing[1], "Carl"); contains(m.missing[2], "Officer")
		local _, records = CSV.records((A().Export.Build("season", "csv", m.rows)))
		eq(#records, 3)
		eq(records[1].ms1, "Guardian"); eq(records[1].role, "tank"); eq(records[1].ms2, "Restoration (healer)")
		eq(records[1].declared_date, "")
		contains(A().Export.Build("season", "discord", m.rows), "(tank)")
	end)

	it("say that a member's client has no MS2 instead of counting none", function()
		fdcp("SNAPSHOT")
		local m = V().Model()
		truthy(m.noMS2)
		eq(m.counts.ms1.tank, 2)
		contains(text(), "FDCP shows MS2 to officers only")
		eq(line("Tank:"), "Tank: 2")
	end)

	it("count nothing while FDCP gives no pool", function()
		truthy(A().Integrations:SetSource("raid", "fdcp"))
		local m = V().Model()
		isNil(m.counts); isNil(m.missing); isNil(m.rows); falsy(m.canExport)
	end)
end)

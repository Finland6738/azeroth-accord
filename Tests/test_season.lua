-- The season roster (M10.3; SPEC-14 §4; SPEC-10 Q20, Q21): officers open and close seasons; each raider writes only their
-- own declaration (MS1 with its role, MS2, OS, a note, or "not sure yet"), locked 30 minutes after the first write; a new
-- season starts empty and the old ones stay readable; forged, invalid and out-of-season entries are refused; with FDCP
-- as the source no Accord entry is written; the four seasons kept; and the two switches ("season" for M10, "raid" for
-- M11) in both states.
local function A() return AzerothAccord end
local function Se() return AzerothAccord.Season end
local function S() return AzerothAccord.Store end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A77", "Player-1-000000FF"
local BOB2 = "Player-1-00000B02"     -- Bob's alt, same account

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 3, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Bobalt", level = 60, class = "PRIEST", rank = 3, guid = BOB2 },
		{ name = "Ann", level = 60, class = "DRUID", rank = 3, guid = ANN },
		{ name = "Officer", level = 60, class = "PALADIN", rank = 1, guid = OFF },
	} }
end

local function setup(myRank, features)
	return function(M)
		M.features = features or { season = true }
		guild(myRank)
	end
end

-- Bob and Bobalt list each other (NET-10).
local function bobAccount()
	local t = GetServerTime()
	for _, g in ipairs({ BOB, BOB2 }) do
		S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = t, token = "TB", chars = { { guid = BOB }, { guid = BOB2 } } }
	end
end

-- A season record as an officer would send it.
local function seasonRec(n, fields)
	local t = GetServerTime()
	local rec = { id = "S:" .. n, author = OFF, rev = 1, time = t, kind = "season", n = n, name = "Season " .. n,
		start = 20260101, opened = t }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

-- An entry of `guid` written by `author`.
local function entryRec(n, guid, author, fields)
	local t = GetServerTime()
	local rec = { id = ("E:%d:%s"):format(n, guid), author = author or guid, rev = 1, time = t, kind = "entry", n = n,
		class = "MAGE", ms1 = { spec = "FROST", role = "ranged" }, unsure = false, first = t }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

local WARRIOR = { ms1 = { spec = "PROTECTION", role = "tank" }, ms2 = { spec = "FURY", role = "melee" }, note = "Mon and Wed" }

-- These tests turn the switch "season" on (on in releases since M10.10).
describe("opening a season", function()
	before_boot(setup(1))

	it("is for officers only, and closes the previous season in the same operation", function()
		truthy(A().Raid.WRITERS == "officers")
		truthy(Se():CanOpen())
		local first = Se():Open("Naxx 1")
		eq(first.n, 1); eq(first.name, "Naxx 1"); eq(first.start, A().Compat.ServerDay())
		eq(Se():Current().n, 1)
		local second = Se():Open("Naxx 2", 20261201)
		eq(second.n, 2); eq(second.start, 20261201)
		eq(Se():Current().n, 2)
		notNil(Se():Get(1).closed, "the previous season is closed")
		eq(#Se():List(), 2)
	end)

	it("refuses a bad name or day", function()
		local rec, why = Se():Open("")
		isNil(rec); eq(why, "name")
		rec, why = Se():Open("a|b")
		isNil(rec); eq(why, "name")
		rec, why = Se():Open(string.rep("x", 33))
		isNil(rec); eq(why, "name")
		rec, why = Se():Open("Ok", 20261340)
		isNil(rec); eq(why, "start")
	end)
end)

describe("a member and the seasons", function()
	before_boot(setup(3))

	it("cannot open or close a season, and a member's season record is refused", function()
		falsy(Se():CanOpen())
		local rec, why = Se():Open("Mine")
		isNil(rec); eq(why, "officer")
		local ok
		ok, why = S():Accept("season", seasonRec(1, { author = BOB }), { sender = "Bob" })
		falsy(ok); eq(why, "authority")
		truthy(S():Accept("season", seasonRec(1), { sender = "Officer" }))
		eq(Se():Current().n, 1)
		ok, why = Se():Close(1)
		falsy(ok); eq(why, "officer")
	end)

	it("keeps a closed season closed", function()
		truthy(S():Accept("season", seasonRec(1, { closed = GetServerTime() }), { sender = "Officer" }))
		local ok, why = S():Accept("season", seasonRec(1, { rev = 2 }), { sender = "Officer" })
		falsy(ok); eq(why, "locked")
		isNil(Se():Current())
	end)
end)

describe("the own declaration", function()
	before_boot(setup(3))

	local function open()
		truthy(S():Accept("season", seasonRec(1), { sender = "Officer" }))
	end

	it("needs an open season", function()
		local rec, why = Se():Declare(WARRIOR)
		isNil(rec); eq(why, "season")
	end)

	it("is written for the player's own character with its class", function()
		open()
		local rec = Se():Declare(WARRIOR)
		notNil(rec)
		eq(rec.id, "E:1:" .. ME); eq(rec.author, ME); eq(rec.class, "WARRIOR")
		eq(rec.ms1.spec, "PROTECTION"); eq(rec.ms1.role, "tank"); eq(rec.ms2.spec, "FURY"); isNil(rec.os)
		eq(rec.note, "Mon and Wed"); eq(rec.first, rec.time)
		eq(Se():Own(1).id, rec.id)
		eq(#Se():Entries(1), 1)
	end)

	it("refuses invalid content", function()
		open()
		local function refused(d)
			local rec, why = Se():Declare(d)
			isNil(rec); eq(why, "content")
		end
		refused({})                                                                 -- no MS1
		refused({ ms1 = { spec = "FROST", role = "ranged" } })                      -- not a warrior tree
		refused({ ms1 = { spec = "ARMS", role = "healer" } })                       -- a role the tree does not allow
		refused({ ms1 = { spec = "ARMS", role = "melee" }, ms2 = { spec = "ARMS", role = "melee" } })
		refused({ ms1 = { spec = "ARMS", role = "melee" }, ms2 = { spec = "FURY", role = "melee" }, os = { spec = "FURY", role = "melee" } })
		refused({ ms1 = { spec = "ARMS", role = "melee" }, note = "a|cff" })
		refused({ ms1 = { spec = "ARMS", role = "melee" }, note = string.rep("n", 81) })
		isNil(Se():Own(1))
	end)

	it("can be corrected for 30 minutes, then the specs are locked and the note still changes", function()
		open()
		truthy(Se():Declare(WARRIOR))
		Mock.Advance(20 * 60)
		local fixed = Se():Declare({ ms1 = { spec = "ARMS", role = "melee" } })
		notNil(fixed, "inside the window")
		eq(fixed.ms1.spec, "ARMS"); eq(fixed.note, "Mon and Wed", "the note is kept")
		Mock.Advance(11 * 60)
		truthy(Se().IsLocked(Se():Own(1)))
		local rec, why = Se():Declare({ ms1 = { spec = "FURY", role = "melee" } })
		isNil(rec); eq(why, "locked")
		eq(Se():Own(1).ms1.spec, "ARMS")
		local noted = Se():SetNote("Only Wed")
		notNil(noted)
		eq(noted.note, "Only Wed"); eq(noted.ms1.spec, "ARMS"); eq(noted.first, fixed.first)
		rec, why = Se():Declare({ unsure = true })
		isNil(rec); eq(why, "locked", "a locked declaration cannot go back to not sure")
	end)

	it("turns \"not sure yet\" into a declaration once", function()
		open()
		local unsure = Se():Declare({ unsure = true, note = "back in two weeks" })
		notNil(unsure); truthy(unsure.unsure); isNil(unsure.ms1)
		Mock.Advance(3 * 86400)
		local rec = Se():Declare(WARRIOR)
		notNil(rec, "the one change from not sure")
		falsy(rec.unsure); truthy(rec.conv); truthy(rec.first > unsure.first)
		Mock.Advance(31 * 60)
		local again, why = Se():Declare({ ms1 = { spec = "ARMS", role = "melee" } })
		isNil(again); eq(why, "locked")
	end)

	it("is one character per account and season", function()
		open()
		local t = GetServerTime()
		S():Records("accounts")[ME] = { id = ME, author = ME, rev = 1, time = t, token = "TM", chars = { { guid = ME }, { guid = BOB } } }
		S():Records("accounts")[BOB] = { id = BOB, author = BOB, rev = 1, time = t, token = "TM", chars = { { guid = ME }, { guid = BOB } } }
		truthy(S():Accept("season", entryRec(1, BOB), { sender = "Bob" }))
		local rec, why = Se():Declare(WARRIOR)
		isNil(rec); eq(why, "account")
	end)

	it("keeps the declarations through a reload", function()
		open()
		truthy(Se():Declare(WARRIOR))
		Mock.Reload()
		eq(Se():Own(1).ms1.spec, "PROTECTION")
	end)
end)

describe("the trust rules of received entries", function()
	before_boot(setup(3))

	-- every test starts with season 1 open
	local plainIt = it
	local function it(name, body)
		plainIt(name, function()
			truthy(S():Accept("season", seasonRec(1), { sender = "Officer" }))
			body()
		end)
	end

	it("takes an entry first hand, and an officer's relay of it", function()
		truthy(S():Accept("season", entryRec(1, BOB), { sender = "Bob" }))
		truthy(S():Accept("season", entryRec(1, ANN, ANN, { class = "DRUID", ms1 = { spec = "FERAL", role = "tank" } }), { sender = "Officer" }))
		eq(#Se():Entries(1), 2)
	end)

	it("refuses a forged entry: another author, or an officer writing a member's entry", function()
		local ok, why = S():Accept("season", entryRec(1, BOB, ANN), { sender = "Ann" })
		falsy(ok); eq(why, "owner")
		ok, why = S():Accept("season", entryRec(1, BOB, OFF), { sender = "Officer" })
		falsy(ok); eq(why, "owner")
		ok, why = S():Accept("season", entryRec(1, BOB), { sender = "Ann" })
		falsy(ok); eq(why, "relay")
		eq(#Se():Entries(1), 0)
	end)

	it("refuses a class other than the roster's, and invalid content", function()
		local ok, why = S():Accept("season", entryRec(1, BOB, BOB, { class = "WARRIOR", ms1 = { spec = "ARMS", role = "melee" } }), { sender = "Bob" })
		falsy(ok); eq(why, "class")
		ok, why = S():Accept("season", entryRec(1, BOB, BOB, { ms1 = { spec = "FROST", role = "tank" } }), { sender = "Bob" })
		falsy(ok); eq(why, "owner")
		ok, why = S():Accept("season", entryRec(1, BOB, BOB, { id = "E:2:" .. BOB }), { sender = "Bob" })
		falsy(ok); eq(why, "owner")
	end)

	it("refuses a change of the specs after the lock, takes a new note", function()
		local first = entryRec(1, BOB)
		truthy(S():Accept("season", first, { sender = "Bob" }))
		Mock.StepClock(31 * 60)
		local changed = entryRec(1, BOB, BOB, { rev = 2, time = GetServerTime(), first = first.first, ms1 = { spec = "FIRE", role = "ranged" } })
		local ok, why = S():Accept("season", changed, { sender = "Bob" })
		falsy(ok); eq(why, "locked")
		local moved = entryRec(1, BOB, BOB, { rev = 2, time = GetServerTime(), first = GetServerTime() })
		ok, why = S():Accept("season", moved, { sender = "Bob" })
		falsy(ok); eq(why, "locked", "first cannot move")
		local noted = entryRec(1, BOB, BOB, { rev = 2, time = GetServerTime(), first = first.first, note = "Fridays" })
		truthy(S():Accept("season", noted, { sender = "Bob" }))
		eq(S():Get("season", "E:1:" .. BOB).note, "Fridays")
	end)

	it("keeps an entry that arrives before its season until the season comes", function()
		local early = entryRec(2, BOB)
		local ok, why = S():Accept("season", early, { sender = "Bob" })
		falsy(ok); eq(why, "wait")
		eq(#Se().waiting, 1)
		truthy(S():Accept("season", seasonRec(2), { sender = "Officer" }))
		notNil(S():Get("season", early.id), "taken when its season arrived")
		eq(#Se().waiting, 0)
	end)

	it("drops a waiting entry after 10 minutes", function()
		falsy(S():Accept("season", entryRec(2, BOB), { sender = "Bob" }))
		Mock.StepClock(Se().WAIT + 1)
		truthy(S():Accept("season", seasonRec(2), { sender = "Officer" }))
		isNil(S():Get("season", "E:2:" .. BOB))
	end)

	it("refuses an entry written after its season closed", function()
		local closedAt = GetServerTime()
		truthy(S():Accept("season", seasonRec(1, { rev = 2, closed = closedAt }), { sender = "Officer" }))
		Mock.StepClock(2 * 3600)
		local late = entryRec(1, BOB)
		local ok, why = S():Accept("season", late, { sender = "Bob" })
		falsy(ok); eq(why, "closed")
		local before = entryRec(1, ANN, ANN, { class = "DRUID", ms1 = { spec = "BALANCE", role = "ranged" }, first = closedAt - 60,
			time = closedAt - 60 })
		truthy(S():Accept("season", before, { sender = "Ann" }), "written before the close, arrived late")
	end)

	it("shows one entry per account: the oldest", function()
		bobAccount()
		truthy(S():Accept("season", entryRec(1, BOB), { sender = "Bob" }))
		Mock.StepClock(60)
		truthy(S():Accept("season", entryRec(1, BOB2, BOB2, { class = "PRIEST", ms1 = { spec = "HOLY", role = "healer" } }), { sender = "Bobalt" }))
		local rows = Se():Entries(1)
		eq(#rows, 1)
		eq(rows[1].guid, BOB); eq(#rows[1].hidden, 1)
	end)
end)

describe("a new season", function()
	before_boot(setup(1))

	it("starts empty, and the old season stays readable with its entries", function()
		Se():Open("Molten Core")
		truthy(Se():Declare(WARRIOR))
		truthy(S():Accept("season", entryRec(1, BOB), { sender = "Bob" }))
		Se():Open("Blackwing Lair")
		eq(Se():Current().n, 2)
		eq(#Se():Entries(2), 0)
		isNil(Se():Own(2))
		eq(#Se():Entries(1), 2)
		eq(Se():Own(1).ms1.spec, "PROTECTION")
		local rec, why = Se():Declare({ ms1 = { spec = "ARMS", role = "melee" } })
		notNil(rec, why)
		eq(rec.n, 2)
		eq(Se():Own(1).ms1.spec, "PROTECTION", "the old one unchanged")
	end)

	it("keeps the current season and the 3 previous ones", function()
		Se():Open("S1")
		truthy(S():Accept("season", entryRec(1, BOB), { sender = "Bob" }))
		for i = 2, 5 do Se():Open("S" .. i) end
		Mock.StepClock(31 * 86400)
		S():Prune()
		isNil(Se():Get(1)); isNil(S():Get("season", "E:1:" .. BOB))
		for n = 2, 5 do notNil(Se():Get(n), n) end
	end)
end)

describe("with FDCP as the source", function()
	before_boot(setup(1))

	it("no Accord entry can be written; received ones are kept but not shown", function()
		Se():Open("Naxx")
		truthy(A().Integrations:SetSource("raid", "fdcp"))
		eq(Se().Source(), "fdcp")
		local rec, why = Se():Declare(WARRIOR)
		isNil(rec); eq(why, "source")
		rec, why = Se():SetNote("x")
		isNil(rec); eq(why, "source")
		falsy(A().Integrations.OWN.CanDeclare())
		truthy(S():Accept("season", entryRec(1, BOB), { sender = "Bob" }))
		local m = A().SeasonView.Model()
		isNil(m.entries)
		local text = {}
		for _, l in ipairs(A().SeasonView.Lines(m)) do text[#text + 1] = l.text end
		text = table.concat(text, "\n")
		contains(text, "Accord asks for no declaration")
		falsy(text:find("Bob", 1, true))
		truthy(A().Integrations:SetSource("raid", "accord"))
		eq(#Se():Entries(1), 1, "back to Accord: the entries are there again")
	end)
end)

describe("the Season view", function()
	before_boot(setup(1))

	local function lines()
		local out = {}
		for _, l in ipairs(A().SeasonView.Lines(A().SeasonView.Model())) do out[#out + 1] = l.text end
		return table.concat(out, "\n")
	end

	it("opens, lets an officer open a season and a raider declare after a confirmation", function()
		Mock.Slash("/accord season")
		eq(A().Shell.selected, "season")
		local V = A().SeasonView
		contains(lines(), "No season is open")
		V:OpenSeason("Naxx")
		eq(Se():Current().name, "Naxx")
		local f = V.frame
		truthy(f.form:IsShown())
		f.ms1:Select("PROTECTION")
		eq(f.ms1role:Selected(), "tank")
		local rec, why = V:Save(false)
		isNil(rec); eq(why, "confirm")
		isNil(Se():Own(1))
		rec = V:Save(false)
		notNil(rec)
		eq(rec.ms1.spec, "PROTECTION")
		local t = lines()
		contains(t, "Season Naxx: open")
		contains(t, "Declarations: 1")
		contains(t, "MS1 Protection (tank)")
		contains(t, "can still be corrected")
		eq(#Mock.errors, 0)
	end)

	it("shows the provider of Accord through Integrations", function()
		Se():Open("Naxx")
		Se():Declare(WARRIOR)
		local P = A().Integrations:Provider("raid")
		eq(P, Se().Provider)
		eq(P.Level(), 1)
		eq(P.Season().name, "Naxx"); eq(P.Season().state, "OPEN")
		eq(#P.Entries(), 1); eq(P.Entries()[1].role, "tank")
		isNil(P.Lineup())
	end)

	it("lists the own declaration in What I share", function()
		Se():Open("Naxx")
		Se():Declare(WARRIOR)
		local row
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "season" then row = r end end
		notNil(row)
		eq(row.records, 1)
		eq(row.lines[1], "Naxx: MS1 Protection (tank)")
	end)
end)

describe("the switches", function()
	describe("season off", function()
		before_boot(setup(1, { season = false, raid = false }))

		it("has no view, no command, takes and sends nothing", function()
			eq(A().Features.season, false); eq(A().Features.raid, false)
			falsy(A().Features.On("season"))
			falsy(S().IsActive("season")); falsy(S().IsActive("guildcfg"))
			local rec, why = Se():Open("Naxx")
			isNil(rec); eq(why, "off")
			rec, why = Se():Declare(WARRIOR)
			isNil(rec); eq(why, "off")
			eq(S():Receive("season", { seasonRec(1) }, "Officer", "GUILD"), 0)
			isNil(S():Get("season", "S:1"))
			for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "season" and v.id ~= "raid") end
			Mock.Slash("/accord help")
			falsy(table.concat(Mock.PlainOutput(), "\n"):find("/accord season", 1, true))
			Mock.Slash("/accord season")
			contains(table.concat(Mock.PlainOutput(), "\n"), "Unknown command 'season'")
			isNil(A().SeasonView.frame)
			falsy(table.concat(A().Store:DebugLines(), " "):find("season", 1, true))
			for _, r in ipairs(A().ShareModel.Describe()) do truthy(r.id ~= "season") end
		end)
	end)

	describe("season on, raid off", function()
		before_boot(setup(1, { raid = false }))

		it("shows the Season view and the source of the season roster, not the Raid view or the loot source", function()
			eq(A().Features.season, true); eq(A().Features.raid, false)
			truthy(A().Features.On("season")); falsy(A().Features.On("raid"))
			truthy(S().IsActive("season")); truthy(S().IsActive("guildcfg"))
			truthy(A().Shell:OpenView("season"))
			falsy(A().Shell:OpenView("raid"))
			Mock.Slash("/accord help")
			local help = table.concat(Mock.PlainOutput(), "\n")
			contains(help, "/accord season")
			falsy(help:find("/accord raid", 1, true))
			truthy(A().Integrations:SetSource("raid", "fdcp"))
			local ok, why = A().Integrations:SetSource("loot", "fdcp")
			falsy(ok); eq(why, "off")
			isNil(A().RaidView.CardSection(A().Roster:ByGUID(BOB)))
		end)
	end)

	describe("raid on", function()
		before_boot(setup(1, { season = false, raid = true }))

		it("turns season on with it", function()
			eq(A().Features.season, false)
			truthy(A().Features.On("season")); truthy(A().Features.On("raid"))
			truthy(A().Shell:OpenView("season"))
			truthy(A().Shell:OpenView("raid"))
			truthy(A().Integrations:SetSource("loot", "fdcp"))
		end)
	end)
end)

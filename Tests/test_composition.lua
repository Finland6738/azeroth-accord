-- Bench and composition (M10.7; SPEC-14 §7): the record C: of `raidev` and its trust rules (officers only); who may be
-- placed (the game's answers and the matched sign-ups of Raid-Helper, one place per account); every member sees the own
-- place; the roles against the target and the MS2 offers; with FDCP as the source nothing is written, accepted or shown;
-- the write into a fake game calendar (confirmed and standby, never over an answer given in the game, at most 40 members
-- per confirmation); the export back to Discord; the Events view and the switch off.
-- Every name here is invented.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function C() return AzerothAccord.Calendar end
local function P() return AzerothAccord.Composition end
local function R() return AzerothAccord.RaidHelper end
local function V() return AzerothAccord.EventsView end

local ME = "Player-1-0000A001"
local TILDA, ORSO, PASTELLO = "Player-1-0000B001", "Player-1-0000B002", "Player-1-0000B003"
local NUVOLA, RUGGINE, OFF = "Player-1-0000B004", "Player-1-0000B005", "Player-1-0000B009"
local DAY = 86400

local MEMBERS = {
	{ name = "Tilda", class = "WARRIOR", rank = 3, guid = TILDA },
	{ name = "Orsetto", class = "MAGE", rank = 3, guid = ORSO },
	{ name = "Pastello", class = "PRIEST", rank = 3, guid = PASTELLO },
	{ name = "Nuvola", class = "DRUID", rank = 3, guid = NUVOLA },
	{ name = "Ruggine", class = "ROGUE", rank = 3, guid = RUGGINE },
	{ name = "Ufficiale", class = "PALADIN", rank = 1, guid = OFF },
}

local function setup(myRank, cfg, features, members)
	return function(M)
		M.features = features or { season = true }
		M.guild.Set{ name = "Accord", myRank = myRank or 1, members = members or MEMBERS }
		M.calendar.Set(cfg or {})
	end
end

-- Orsetto and Pastello are one account.
local function ready()
	Mock.Advance(15)
	local t = GetServerTime()
	for _, g in ipairs({ ORSO, PASTELLO }) do
		S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = t, token = "TO", chars = { { guid = ORSO }, { guid = PASTELLO } } }
	end
	A().Accounts:MarkDirty()
end

local function startAt()
	local t = GetServerTime() + 2 * DAY
	return t - t % 60
end

local function invite(name, guid, class, status) return { name = name, guid = guid, classFilename = class, inviteStatus = status } end

-- A calendar event with Tilda and Orsetto signed up, Nuvola tentative and Ruggine declined; its answers read.
local function event(extra)
	local st = Mock.calendar.STATUS
	local invites = {
		invite("Tilda", TILDA, "WARRIOR", st.Signedup),
		invite("Orsetto", ORSO, "MAGE", st.Signedup),
		invite("Nuvola", NUVOLA, "DRUID", st.Tentative),
		invite("Ruggine", RUGGINE, "ROGUE", st.Declined),
	}
	Mock.calendar.Add{ eventID = 701, title = "Notte di Naxx", at = startAt(), mine = true, invites = extra or invites }
	ready()
	A().Calendar:Start()
	Mock.Advance(2)
	truthy(C():LoadInvites("c701"))
	Mock.Advance(2)
	return C():Event("c701")
end

-- Declarations of the current season: Tilda tank (MS2 melee), Nuvola ranged (MS2 healer), Orsetto ranged.
local function season()
	truthy(A().Season:Open("Naxx"))
	local t = GetServerTime()
	local function entry(guid, class, ms1, ms2)
		local id = "E:1:" .. guid
		S():Records("season")[id] = { id = id, author = guid, rev = 1, time = t, kind = "entry", n = 1, class = class,
			ms1 = ms1, ms2 = ms2, first = t }
	end
	entry(TILDA, "WARRIOR", { spec = "PROTECTION", role = "tank" }, { spec = "FURY", role = "melee" })
	entry(NUVOLA, "DRUID", { spec = "BALANCE", role = "ranged" }, { spec = "RESTORATION", role = "healer" })
	entry(ORSO, "MAGE", { spec = "FROST", role = "ranged" })
end

local function names(list)
	local out = {}
	for i, p in ipairs(list) do out[i] = (p.name:match("^([^%-]+)")) end
	table.sort(out)
	return table.concat(out, ",")
end

local function lines(key)
	local out = {}
	for _, l in ipairs(V().Lines(V().Model(key))) do out[#out + 1] = l.text end
	return table.concat(out, "\n")
end

local function inviteOf(e, name)
	for _, i in ipairs(e.invites or {}) do
		if i.name:match("^([^%-]+)") == name then return i.inviteStatus end
	end
	return nil
end

local function writes(call)
	local n = 0
	for _, w in ipairs(Mock.calendar.writes) do
		if w.call == call then n = n + 1 end
	end
	return n
end

-- An import of Raid-Helper at the start of the event, with the given sign-ups.
local function imported(signups)
	local t = GetServerTime()
	S():Records("raidev")["H:55"] = { id = "H:55", author = OFF, rev = 1, time = t, title = "Notte di Naxx", start = startAt(), at = t,
		s = signups }
end

describe("an officer's line-up", function()
	before_boot(setup(1))

	it("places who signed up, one place per account, and nobody else", function()
		local e = event()
		local m = P():Model(e)
		eq(names(m.free), "Nuvola,Orsetto,Tilda", "the declined one is not offered")
		truthy(P():Place(e, TILDA, "raid"))
		truthy(P():Place(e, ORSO, "bench"))
		local ok, why = P():Place(e, RUGGINE, "raid")
		falsy(ok); eq(why, "member")
		ok, why = P():Place(e, PASTELLO, "raid")
		truthy(ok, why)   -- the account is placed already: its other character takes the place
		local rec = P():Lineup("c701")
		eq(#rec.raid, 2); eq(#rec.bench, 0); eq(rec.at, e.start)
		ok, why = P():Place(e, ORSO, "bench")
		truthy(ok, why)
		eq(P():Lineup("c701").bench[1], ORSO); eq(#P():Lineup("c701").raid, 1)
		truthy(P():Place(e, ORSO, nil))
		eq(#P():Lineup("c701").bench, 0)
		eq(A().Integrations:Provider("raid").Lineup("c701").raid[1], A().Roster:ByGUID(TILDA).name)
	end)

	it("counts the roles against the target and offers MS2 for a short role", function()
		local e = event()
		season()
		truthy(P():SetTarget({ size = 10, tank = 1, healer = 1, melee = 0, ranged = 3 }))
		truthy(P():Place(e, TILDA, "raid"))
		truthy(P():Place(e, NUVOLA, "bench"))
		local m = P():Model(e)
		eq(m.size, 10); eq(m.roles.raid.tank, 1); eq(m.roles.raid.healer, 0); eq(m.roles.bench.ranged, 1)
		eq(#m.offers, 1); eq(m.offers[1].person.guid, NUVOLA); eq(m.offers[1].role, "healer")
		local ok, why = P():Place(e, ORSO, "raid", true)
		falsy(ok); eq(why, "ms2")
		truthy(P():Place(e, NUVOLA, "raid", true))
		m = P():Model(e)
		eq(m.roles.raid.healer, 1); eq(#m.offers, 0); eq(P():Lineup("c701").as[NUVOLA], "healer")
		truthy(P():Place(e, NUVOLA, "raid"))
		eq(P():Model(e).roles.raid.ranged, 1)
		isNil(P():Lineup("c701").as)
		-- the role chosen for the event wins over MS1
		local t = GetServerTime()
		S():Records("raidev")["R:c701:" .. TILDA] = { id = "R:c701:" .. TILDA, author = TILDA, rev = 1, time = t, role = "melee",
			spec = "ms2", at = e.start }
		eq(P():Model(e).roles.raid.melee, 1)
	end)

	it("takes the matched sign-ups of Discord, and lets the game's no win", function()
		local e = event({ invite("Ruggine", RUGGINE, "ROGUE", Mock.calendar.STATUS.Declined) })
		imported({ { g = TILDA, st = "signed", role = "tank" }, { g = NUVOLA, st = "absence" },
			{ g = RUGGINE, st = "signed", role = "melee" } })
		e.importId = "55"
		local m = P():Model(e)
		eq(names(m.free), "Tilda"); eq(m.free[1].role, "tank")
		truthy(P():Place(e, TILDA, "raid"))
	end)

	it("marks who is no longer signed up, and still moves them", function()
		local e = event()
		truthy(P():Place(e, TILDA, "raid"))
		C().invites.c701.list = {}
		local m = P():Model(e)
		truthy(m.raid[1].gone)
		truthy(P():Place(e, TILDA, "bench"))
	end)

	it("holds at most 40 in the raid", function()
		local e = event()
		local raid = {}
		for i = 1, 40 do raid[i] = ("Player-1-0000D%03d"):format(i) end
		truthy(S():Put("raidev", "C:c701", { at = e.start, raid = raid, bench = {} }))
		local ok, why = P():Place(e, TILDA, "raid")
		falsy(ok); eq(why, "full")
		raid[41] = "Player-1-0000D041"
		isNil((S():Put("raidev", "C:c701", { at = e.start, raid = raid, bench = {} })))
		isNil((S():Put("raidev", "C:c701", { at = e.start, raid = { TILDA }, bench = { TILDA } })))
		isNil((S():Put("raidev", "C:h55", { at = e.start, raid = {}, bench = {} })))
	end)

	it("makes none for an event only on Discord", function()
		ready()
		local ok, why = P():Place({ key = "h55", discordOnly = true, start = startAt() }, TILDA, "raid")
		falsy(ok); eq(why, "calendar")
	end)
end)

describe("into the game calendar", function()
	before_boot(setup(1))

	it("writes confirmed and standby for who gave no answer, never over an answer, after a second click", function()
		local st = Mock.calendar.STATUS
		local e = event({ invite("Tilda", TILDA, "WARRIOR", st.Signedup), invite("Nuvola", NUVOLA, "DRUID", st.Invited) })
		imported({ { g = TILDA, st = "signed" }, { g = NUVOLA, st = "signed" }, { g = RUGGINE, st = "bench" },
			{ g = PASTELLO, st = "signed" } })
		V():Choose("c701")
		Mock.Advance(2)
		for _, step in ipairs({ { TILDA, "raid" }, { NUVOLA, "raid" }, { RUGGINE, "bench" } }) do
			truthy(V():Place(step[1], step[2]))
		end
		local ok, why = V():PushLineup()
		falsy(ok); eq(why, "confirm"); contains(V().said, "Write 2 members into the game event")
		eq(#Mock.calendar.writes, 0)
		truthy(V():PushLineup())
		Mock.Advance(30)
		local res = R().result["C:c701"]
		truthy(res.ok, tostring(res.why))
		local held = Mock.calendar.events[1]
		eq(inviteOf(held, "Tilda"), st.Signedup, "an answer given in the game stays")
		eq(inviteOf(held, "Nuvola"), st.Confirmed)
		eq(inviteOf(held, "Ruggine"), st.Standby)
		eq(#res.answered, 1); eq(#res.written, 2); eq(res.invited, 1); eq(Mock.calendar.maxFlight, 1)
		isNil(C().open)
		contains(lines("c701"), "Done: 1 invited, 2 answers written.")
		truthy(e)
	end)

	it("leaves a member who answered with another character", function()
		local st = Mock.calendar.STATUS
		local e = event({ invite("Orsetto", ORSO, "MAGE", st.Tentative) })
		truthy(S():Put("raidev", "C:c701", { at = e.start, raid = { PASTELLO }, bench = {} }))
		truthy(P():Push(e))
		Mock.Advance(10)
		eq(#Mock.calendar.writes, 0)
		eq(#R().result["C:c701"].answered, 1)
	end)

	it("asks again when the line-up changed after the first click", function()
		event({ invite("Tilda", TILDA, "WARRIOR", Mock.calendar.STATUS.Invited), invite("Nuvola", NUVOLA, "DRUID", Mock.calendar.STATUS.Invited) })
		imported({ { g = TILDA, st = "signed" }, { g = NUVOLA, st = "signed" } })
		V():Choose("c701")
		Mock.Advance(2)
		truthy(V():Place(TILDA, "raid"))
		V():PushLineup()
		truthy(P():Place(V().Model("c701").event, NUVOLA, "raid"))
		local ok, why = V():PushLineup()
		falsy(ok); eq(why, "confirm"); eq(#Mock.calendar.writes, 0)
	end)

	it("exports the line-up back to Discord", function()
		local e = event()
		V():Choose("c701")
		Mock.Advance(2)
		truthy(P():Place(e, TILDA, "bench"))
		truthy(P():Place(e, NUVOLA, "raid"))
		local text = V():Export()
		contains(text, "name,realm,class,role,game_answer,discord,lineup")
		contains(text, "Nuvola,,DRUID,,maybe,,raid\nTilda,,WARRIOR,,yes,,bench")
		contains(text, "Ruggine,,ROGUE,,no,,")
		A().ExportBox:SetFormat("discord")
		contains(A().ExportBox:GetText(), "Line-up"); contains(A().ExportBox:GetText(), "Bench")
	end)

	it("draws the officer's row and places from it", function()
		event()
		truthy(V():Open("c701"))
		Mock.Advance(2)
		V():Redraw()
		local f = V().frame
		truthy(f.placeRow:IsShown()); falsy(f.write:IsShown(), "nothing to write yet")
		f.person:Select(TILDA)
		f.toRaid:Click()
		eq(P():Lineup("c701").raid[1], TILDA)
		truthy(f.write:IsShown())
		f.write:Click()
		eq(f.write:GetLabel(), "Confirm")
		f.person:Select(TILDA)
		f.toBench:Click()
		eq(P():Lineup("c701").bench[1], TILDA)
		f.person:Select(TILDA)
		f.takeOut:Click()
		eq(#P():Lineup("c701").bench, 0)
	end)
end)

describe("a member's client", function()
	before_boot(setup(3))

	local function received(e, fields, sender)
		local rec = { id = "C:c701", author = OFF, rev = 1, time = GetServerTime(), at = e.start, raid = { TILDA }, bench = { ME } }
		for k, v in pairs(fields or {}) do rec[k] = v end
		return S():Accept("raidev", rec, { sender = sender or "Ufficiale" })
	end

	it("sees where it is placed and the line-up, and changes nothing", function()
		local e = event()
		truthy(received(e))
		local t = lines("c701")
		contains(t, "Your place: on the bench"); contains(t, "In the raid (1)"); contains(t, "On the bench (1)")
		falsy(t:find("Signed up, not placed"), "the officers' lists are not shown")
		local ok, why = P():Place(e, TILDA, "bench")
		falsy(ok); eq(why, "officer")
		ok, why = P():Push(e)
		falsy(ok); eq(why, "officer")
		falsy(V().Model("c701").editor)
		V():Open("c701")
		V():Redraw()
		falsy(V().frame.placeRow:IsShown())
		eq(#Mock.calendar.writes, 0)
	end)

	it("refuses a line-up from a member", function()
		local e = event()
		local ok, why = received(e, { author = TILDA }, "Tilda")
		falsy(ok); eq(why, "authority")
		isNil(P():Lineup("c701"))
	end)
end)

describe("with FDCP as the source", function()
	before_boot(setup(1))

	it("writes, accepts and shows no line-up of Accord", function()
		local e = event()
		truthy(P():Place(e, TILDA, "raid"))
		Mock.Advance(5)
		truthy(A().Integrations:SetSource("raid", "fdcp"))
		isNil(P():Lineup("c701"))
		local ok, why = P():Place(e, TILDA, "bench")
		falsy(ok); eq(why, "source")
		ok, why = P():Push(e)
		falsy(ok); eq(why, "source")
		local rec
		rec, why = S():Put("raidev", "C:c701", { at = e.start, raid = {}, bench = {} })
		isNil(rec)
		ok, why = S():Accept("raidev", { id = "C:c701", author = OFF, rev = 9, time = GetServerTime(), at = e.start, raid = { ORSO },
			bench = {} }, { sender = "Ufficiale" })
		falsy(ok); eq(why, "source")
		eq(S():Get("raidev", "C:c701").raid[1], TILDA, "the one held stays")
		local t = lines("c701")
		contains(t, "FDCP is the source"); falsy(t:find("In the raid (1)", 1, true))
		falsy(V().Model("c701").editor)
		V():Open("c701")
		V():Redraw()
		falsy(V().frame.placeRow:IsShown())
		Mock.Advance(5)
		truthy(A().Integrations:SetSource("raid", "accord"))
		eq(P():Lineup("c701").raid[1], TILDA, "back with Accord as the source")
		eq(#Mock.calendar.writes, 0)
	end)
end)

describe("with the switch season off", function()
	before_boot(setup(1, {}, {}))

	it("writes, accepts and shows nothing", function()
		ready()
		local e = { key = "c701", start = startAt() }
		local ok, why = P():Place(e, TILDA, "raid")
		falsy(ok); eq(why, "off")
		ok, why = S():Accept("raidev", { id = "C:c701", author = OFF, rev = 1, time = GetServerTime(), at = e.start, raid = { TILDA },
			bench = {} }, { sender = "Ufficiale" })
		falsy(ok); eq(why, "set")
		isNil(P():Lineup("c701")); isNil(P():Model(e))
		eq(#Mock.calendar.writes, 0)
	end)
end)

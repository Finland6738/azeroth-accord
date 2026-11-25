-- Events and sign-ups on the game calendar (M10.5; SPEC-14 §5, §10): guild events read from the game calendar whoever
-- created them; an answer given in Accord is the same answer in the game calendar (a fake C_Calendar,
-- Tests/mock/62_calendar.lua), one given in the game's window shows in Accord; no event is opened while the game's
-- calendar window is shown, an action is pending, in combat or during a boss, and the event opened is always closed; a
-- call the client refuses from an addon opens the game's calendar instead; the role is preselected from MS1, MS2 or the
-- class, so a member without a season entry signs up all the same; events only of the addon exist only without a usable
-- calendar, only from officers, and are marked; the trust rules of the data set `raidev`; silence during a boss; and
-- the switch "season" off.
local function A() return AzerothAccord end
local function C() return AzerothAccord.Calendar end
local function S() return AzerothAccord.Store end
local function Se() return AzerothAccord.Season end
local function V() return AzerothAccord.EventsView end

local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-000000FF"
local DAY = 86400

local function minute(t) return t - t % 60 end

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 3, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Officer", level = 60, class = "PALADIN", rank = 1, guid = OFF },
	} }
end

-- A guild event created by somebody else (Bob signed up, the Officer tentative) two days ahead, one three days ago,
-- one twenty days ahead (out of the window).
local function events(M)
	local t = minute(GetServerTime())
	M.calendar.Add{ eventID = 101, title = "Naxx night", at = t + 2 * DAY, invites = {
		{ name = "Bob", guid = BOB, classFilename = "MAGE", inviteStatus = 6 },
		{ name = "Officer", guid = OFF, classFilename = "PALADIN", inviteStatus = 8 },
	} }
	M.calendar.Add{ eventID = 102, title = "Old raid", at = t - 3 * DAY, own = 1 }
	M.calendar.Add{ eventID = 103, title = "Far away", at = t + 20 * DAY }
end

local function setup(myRank, cfg, features)
	return function(M)
		M.features = features or { season = true }
		guild(myRank)
		if cfg ~= false then
			M.calendar.Set(cfg or {})
			events(M)
		end
	end
end

local function key(id) return "c" .. id end

-- A season with the player's declaration (a warrior): MS1 tank, MS2 melee.
local function declare()
	truthy(Se():Open("Naxx"))
	truthy(Se():Declare({ ms1 = { spec = "PROTECTION", role = "tank" }, ms2 = { spec = "FURY", role = "melee" } }))
end

local function text(k)
	local out = {}
	for _, l in ipairs(V().Lines(V().Model(k))) do out[#out + 1] = l.text end
	return table.concat(out, "\n")
end

describe("reading the game calendar", function()
	before_boot(setup(3))

	it("reads the guild events whoever created them, from 7 days ago to 14 ahead", function()
		Mock.Advance(1)
		eq(C().State(), "available")
		local list = C().events
		eq(#list, 2)
		eq(list[1].key, key(102)); eq(list[1].answer, "yes")
		eq(list[2].key, key(101)); eq(list[2].title, "Naxx night"); isNil(list[2].answer)
		eq(list[2].start, Mock.calendar.events[1].at, "the realm's date and time of the event")
		isNil(C():Event(key(103)), "20 days ahead is out of the window")
	end)

	it("reads the answers of the chosen event only, and closes it", function()
		Mock.Advance(1)
		eq(Mock.calendar.opened, 0, "nothing is opened in the background")
		truthy(C():LoadInvites(key(101)))
		Mock.Advance(1)
		isNil(Mock.calendar.open, "closed again")
		eq(Mock.calendar.opened, Mock.calendar.closed)
		local inv = C().invites[key(101)]
		eq(#inv.list, 2)
		eq(inv.list[1].name, "Bob"); eq(inv.list[1].answer, "yes")
		eq(inv.list[2].answer, "maybe")
		local t = text(key(101))
		contains(t, "Signed up (1)"); contains(t, "Tentative (1)")
	end)

	it("shows an answer given in the game's window", function()
		Mock.Advance(1)
		truthy(Mock.calendar.GameAnswer(101, Mock.calendar.STATUS.Tentative))
		eq(C():Event(key(101)).answer, "maybe")
		contains(text(key(101)), "Your answer: Tentative")
		truthy(Mock.calendar.GameAnswer(101, Mock.calendar.STATUS.Declined))
		eq(C():Event(key(101)).answer, "no")
	end)
end)

describe("answering from Accord", function()
	before_boot(setup(3))

	it("writes the same answer into the game calendar, and closes the event", function()
		Mock.Advance(1)
		local ok, why = C():Answer(key(101), "yes", "melee")
		truthy(ok); eq(why, "pending")
		Mock.Advance(1)
		eq(Mock.calendar.events[1].own, Mock.calendar.STATUS.Signedup, "the game calendar has the sign-up")
		eq(Mock.calendar.calls[1].call, "EventSignUp")
		eq(C():Event(key(101)).answer, "yes", "Accord reads it back")
		truthy(C().outcome[key(101)].ok)
		isNil(Mock.calendar.open); eq(Mock.calendar.opened, Mock.calendar.closed)
		local r = S():Get("raidev", "R:c101:" .. ME)
		eq(r.role, "melee"); eq(r.spec, "class"); eq(r.at, C():Event(key(101)).start)
	end)

	it("answers tentative and decline, and an answered event takes EventAvailable", function()
		Mock.Advance(1)
		truthy(C():Answer(key(101), "maybe"))
		Mock.Advance(1)
		eq(Mock.calendar.calls[1].call, "EventTentative")
		eq(C():Event(key(101)).answer, "maybe")
		truthy(C():Answer(key(101), "yes"))
		Mock.Advance(1)
		eq(Mock.calendar.calls[2].call, "EventAvailable")
		eq(Mock.calendar.events[1].own, Mock.calendar.STATUS.Available)
		truthy(C():Answer(key(101), "no"))
		Mock.Advance(1)
		eq(Mock.calendar.calls[3].call, "EventDecline")
		eq(C():Event(key(101)).answer, "no")
	end)

	it("says when the server refuses, and closes the event", function()
		Mock.calendar.refuse = true
		Mock.Advance(1)
		truthy(C():Answer(key(101), "yes"))
		Mock.Advance(1)
		local o = C().outcome[key(101)]
		falsy(o.ok); eq(o.why, "error")
		isNil(Mock.calendar.open)
		contains(text(key(101)), "refused")
		Mock.calendar.refuse = false
	end)

	it("never opens an event while the game's window is shown, an action is pending, in combat or during a boss", function()
		Mock.Advance(1)
		Mock.calendar.ShowFrame(true)
		local ok, why = C():Answer(key(101), "yes")
		falsy(ok); eq(why, "shown")
		Mock.calendar.ShowFrame(false)
		Mock.calendar.pending = true
		ok, why = C():Answer(key(101), "yes")
		falsy(ok); eq(why, "pending")
		Mock.calendar.pending = false
		Mock.Fire("ENCOUNTER_START", 1, "Boss", 9, 40)
		ok, why = C():Answer(key(101), "yes")
		falsy(ok); eq(why, "encounter")
		ok, why = C():LoadInvites(key(101))
		falsy(ok); eq(why, "encounter")
		Mock.Fire("ENCOUNTER_END", 1, "Boss", 9, 40, 1)
		eq(Mock.calendar.opened, 0)
		truthy(C():Answer(key(101), "yes"))
	end)

	it("lets go of the event when the game's window takes it", function()
		Mock.Advance(1)
		truthy(C():LoadInvites(key(101)))
		Mock.calendar.ShowFrame(true)
		Mock.Advance(1)
		isNil(C().open)
	end)
end)

describe("a client that refuses the calls from an addon", function()
	before_boot(setup(3, { protected = true }))

	it("opens the game's calendar instead and says so", function()
		Mock.Advance(1)
		local ok, why = C():Answer(key(101), "yes")
		falsy(ok); eq(why, "blocked")
		eq(Mock.calendar.blocked, 1)
		eq(Mock.calendar.toggled, 1, "the game's calendar opened")
		isNil(Mock.calendar.open, "the event was closed")
		eq(#Mock.calendar.calls, 0)
		contains(text(key(101)), "did not let Accord answer")
	end)

	it("answers from a click of the Sign up button", function()
		Mock.Advance(1)
		A():OpenView("events")
		local f = V().frame
		notNil(f)
		V():Choose(key(101))
		Mock.Advance(11)
		f.yes:Click()
		Mock.Advance(1)
		eq(Mock.calendar.calls[1].call, "EventSignUp")
		eq(C():Event(key(101)).answer, "yes")
	end)
end)

describe("the role", function()
	before_boot(setup(1))

	it("comes from the class without a season entry, so a member without one signs up", function()
		Mock.Advance(1)
		local role, from = C():SuggestRole(key(101))
		eq(role, "melee"); eq(from, "class")
		truthy(C():Answer(key(101), "yes", role))
		Mock.Advance(1)
		eq(C():Event(key(101)).answer, "yes")
		contains(text(key(101)), "Your role: melee dps")
	end)

	it("comes from MS1, or MS2 when MS1's role is covered for the target and MS2's is not", function()
		Mock.Advance(1)
		declare()
		local role, from = C():SuggestRole(key(101))
		eq(role, "tank"); eq(from, "ms1")
		truthy(A().Composition:SetTarget({ size = 10, tank = 1, healer = 2, melee = 3, ranged = 4 }))
		local t = GetServerTime()
		truthy(S():Accept("raidev", { id = "R:c101:" .. OFF, author = OFF, rev = 1, time = t, role = "tank", spec = "ms1",
			at = C():Event(key(101)).start }, { sender = "Officer" }))
		role, from = C():SuggestRole(key(101))
		eq(role, "melee"); eq(from, "ms2")
		-- what the player chose stays
		truthy(C():SetRole(key(101), "tank", "ms1"))
		role, from = C():SuggestRole(key(101))
		eq(role, "tank"); eq(from, "held")
	end)
end)

describe("events only of the addon", function()
	it("cannot be created while the client has a usable calendar", function()
		boot(setup(1))
		Mock.Advance(1)
		falsy(C():CanCreateLocal())
		local rec, why = C():CreateLocal("Raid", GetServerTime() + DAY, 40)
		isNil(rec); eq(why, "calendar")
	end)

	it("exist when the calendar never answers, only from officers, and are marked", function()
		boot(setup(1, { silent = true }))
		eq(C().State(), "unknown")
		falsy(C():CanCreateLocal(), "not while still waiting")
		Mock.Advance(61)
		eq(C().State(), "missing")
		truthy(C():CanCreateLocal())
		local start = minute(GetServerTime()) + DAY
		local rec, why = C():CreateLocal("Raid", start, 25, "Bring flasks")
		notNil(rec, why)
		eq(rec.id, "F:" .. ME .. ":1")
		local k = "f" .. ME .. ":1"
		local t = text(k)
		contains(t, "Not in the game calendar")
		contains(t, "kept in Accord only")
		truthy(C():Answer(k, "maybe", "tank"))
		local a = S():Get("raidev", "A:" .. k .. ":" .. ME)
		eq(a.answer, "maybe"); eq(a.role, "tank"); eq(a.at, start)
		contains(text(k), "Your answer: Tentative")
		contains(text(k), "Tentative (1)")
		rec, why = C():CreateLocal("", start, 25)
		isNil(rec); eq(why, "title")
		rec, why = C():CreateLocal("x", start, 3)
		isNil(rec); eq(why, "size")
	end)

	it("exist when the client has no C_Calendar, and a member cannot create one", function()
		boot(setup(3, false))
		eq(C().State(), "missing")
		local rec, why = C():CreateLocal("Raid", GetServerTime() + DAY, 40)
		isNil(rec); eq(why, "officer")
		-- an officer's event arrives and the member answers it
		local t = GetServerTime()
		local start = minute(t) + DAY
		truthy(S():Accept("raidev", { id = "F:" .. OFF .. ":1", author = OFF, rev = 1, time = t, title = "Raid", start = start,
			size = 40 }, { sender = "Officer" }))
		local k = "f" .. OFF .. ":1"
		truthy(C():Answer(k, "yes"))
		eq(S():Get("raidev", "A:" .. k .. ":" .. ME).role, "melee")
		contains(text(k), "Not in the game calendar")
	end)

	it("are still marked on a client that has a calendar, with the FDCP note when FDCP is a source", function()
		boot(setup(3))
		Mock.Advance(1)
		local t = GetServerTime()
		truthy(S():Accept("raidev", { id = "F:" .. OFF .. ":1", author = OFF, rev = 1, time = t, title = "Raid", start = minute(t) + DAY,
			size = 40 }, { sender = "Officer" }))
		truthy(S():Accept("guildcfg", { id = "sources", author = OFF, rev = 1, time = t, raid = "fdcp", loot = "none" }, { sender = "Officer" }))
		local tx = text("f" .. OFF .. ":1")
		contains(tx, "Not in the game calendar")
		contains(tx, "do not count for FDCP")
	end)
end)

describe("the data set raidev", function()
	before_boot(setup(3))

	it("refuses another account's role or answer, a member's event, an import without content and later records", function()
		local t = GetServerTime()
		local ok, why = S():Accept("raidev", { id = "R:c101:" .. BOB, author = OFF, rev = 1, time = t, role = "tank", spec = "ms1",
			at = t + DAY }, { sender = "Officer" })
		falsy(ok); eq(why, "owner")
		truthy(S():Accept("raidev", { id = "R:c101:" .. BOB, author = BOB, rev = 1, time = t, role = "tank", spec = "ms1",
			at = t + DAY }, { sender = "Bob" }))
		ok, why = S():Accept("raidev", { id = "F:" .. BOB .. ":1", author = BOB, rev = 1, time = t, title = "Mine", start = t + DAY,
			size = 10 }, { sender = "Bob" })
		falsy(ok); eq(why, "authority")
		ok = S():Accept("raidev", { id = "R:c101:" .. BOB, author = BOB, rev = 2, time = t, role = "boss", spec = "ms1", at = t }, { sender = "Bob" })
		falsy(ok)
		ok, why = S():Accept("raidev", { id = "H:123", author = OFF, rev = 1, time = t, title = "x" }, { sender = "Officer" })
		falsy(ok)
		ok = S():Accept("raidev", { id = "C:c101", author = OFF, rev = 1, time = t }, { sender = "Officer" })
		falsy(ok)
	end)

	it("drops a record two days after its event", function()
		local t = GetServerTime()
		truthy(C().Expired({ id = "R:c1:" .. BOB, at = t - 3 * DAY }, t))
		falsy(C().Expired({ id = "R:c1:" .. BOB, at = t - DAY }, t))
		truthy(C().Expired({ id = "F:" .. OFF .. ":1", start = t - 3 * DAY }, t))
	end)
end)

describe("silence during a boss", function()
	before_boot(setup(3))

	it("holds NORMAL and BULK messages from ENCOUNTER_START to ENCOUNTER_END, ALERT goes", function()
		local Tr = A().Transport
		local sent = {}
		Tr.wire = function(prio, txt, dist, target, done)
			sent[#sent + 1] = prio
			done(Enum.SendAddonMessageResult.Success)
		end
		Mock.Advance(5)
		Mock.Fire("ENCOUNTER_START", 1, "Boss", 9, 40)
		truthy(Tr.BossSilence())
		local before = #sent
		Tr:Send("GUILD", { t = "REQ", s = "accounts" }, { prio = "NORMAL" })
		Tr:Send("GUILD", { t = "REQ", s = "contacts" }, { prio = "ALERT" })
		Mock.Advance(3)
		eq(#sent, before + 1)
		eq(sent[#sent], "ALERT")
		Mock.Fire("ENCOUNTER_END", 1, "Boss", 9, 40, 1)
		Mock.Advance(3)
		eq(#sent, before + 2)
		eq(sent[#sent], "NORMAL")
	end)
end)

describe("with the switch season off", function()
	before_boot(setup(1, nil, {}))

	it("never calls the calendar, takes and sends nothing, shows nothing", function()
		Mock.Advance(61)
		isNil(C().started)
		eq(#C().events, 0)
		eq(Mock.calendar.opened, 0)
		falsy(C():Answer(key(101), "yes"))
		local t = GetServerTime()
		falsy(S():Accept("raidev", { id = "R:c101:" .. BOB, author = BOB, rev = 1, time = t, role = "tank", spec = "ms1", at = t + DAY },
			{ sender = "Bob" }))
		falsy(A().Transport.BossSilence())
		local rec, why = C():CreateLocal("Raid", t + DAY, 40)
		isNil(rec); eq(why, "off")
	end)
end)

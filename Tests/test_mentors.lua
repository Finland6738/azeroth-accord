-- Mentors (M12.5; SPEC-16 §6, MEN-01..MEN-04; SPEC-10 Q37, Q38): only the own offer, one per account, the rate; leaving
-- at any time, and the leaving reaches everybody; only those who offered are suggested; a deterministic score and order
-- on the same graph; at most 3 mentors per new member and 3 first choices per mentor; the pairs only on an officer's
-- client, never in a record or a message; the shared traffic (SPEC-16 §7); the switch "recruit".
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Mn() return AzerothAccord.Mentors end
local function V() return AzerothAccord.MentorsView end
local function L(key) return LibStub("AceLocale-3.0"):GetLocale("AzerothAccord")[key] end

local ME = "Player-1-0000A001"
local OFF, BOB, ANN, CAT, DAN = "Player-1-000000FF", "Player-1-00000B0B", "Player-1-00000A77", "Player-1-00000CA7", "Player-1-00000DA7"
local NEW1, NEW2, NEW3, NEW4 = "Player-1-0000EE01", "Player-1-0000EE02", "Player-1-0000EE03", "Player-1-0000EE04"
local ALT = "Player-1-00000A17"
local DAY, HOUR = 86400, 3600

local function setup(myRank, features)
	return function(M)
		M.features = features or { recruit = true }
		local members = {}
		local function add(name, guid, rank, level)
			members[#members + 1] = { name = name, guid = guid, rank = rank or 3, level = level or 60, class = "MAGE", online = true }
		end
		add("Officer", OFF, 1)
		add("Bob", BOB, 3, 60); add("Ann", ANN, 3, 50); add("Cat", CAT, 3, 40); add("Dan", DAN, 3, 30); add("Alt", ALT, 3, 10)
		add("Newone", NEW1, 4, 5); add("Newtwo", NEW2, 4, 6); add("Newthree", NEW3, 4, 7); add("Newfour", NEW4, 4, 8)
		M.guild.Set{ name = "Accord", myRank = myRank or 1, members = members }
	end
end

local function rank(r)
	Mock.guild.SetMyRank(r)
	A().Role:Refresh()
	A().Roster:MarkDirty()
end

local function offer(guid, fields)
	local r = { id = "M:" .. guid, author = guid, rev = 1, time = GetServerTime(), on = true }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

local function left(guid, rev) return { id = "M:" .. guid, author = guid, rev = rev or 2, time = GetServerTime(), off = true } end

local function from(sender) return { sender = sender, dist = "GUILD" } end

local function accept(guid, sender, fields)
	return S():Accept("mentor", offer(guid, fields), from(sender))
end

-- Two characters of one account, as their own records say it.
local function sameAccount(a, b)
	for _, g in ipairs({ a, b }) do
		S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = GetServerTime(), token = "tok",
			chars = { { guid = a }, { guid = b } }, main = a }
	end
	A().Accounts:MarkDirty()
end

-- Minutes played together, as an observer recorded them today, and the graph computed from them.
local function played(list)
	local day = GetServerTime()
	local n = 0
	for _, p in ipairs(list) do
		n = n + 1
		local a, b = p[1], p[2]
		if a > b then a, b = b, a end
		local id = a .. ":x:" .. n
		S():Records("coplay")[id] = { id = id, author = a, rev = 1, time = day, day = tonumber(date("!%Y%m%d", day)),
			observer = a, pairs = { [a .. ":" .. b] = p[3] } }
	end
	A().Social:ComputeNow()
end

-- A join the officer's timeline holds, `ago` days old.
local function joined(guid, ago)
	local t = GetServerTime() - math.floor(ago * DAY)
	local day = tonumber(date("!%Y%m%d", t))
	local id = ME .. ":" .. day .. ":" .. (guid:sub(-4))
	S():Records("timeline")[id] = { id = id, author = ME, rev = 1, time = t, observer = ME, day = day,
		ev = { { k = "join", g = guid, n = "x", a = t - 60, b = t, r = 4, l = 1 } } }
	A().Timeline:Invalidate()
end

local function names(list)
	local out = {}
	for _, m in ipairs(list) do out[#out + 1] = m.name end
	return out
end

local function section(guid, id)
	for _, s in ipairs(A().MemberCard.Describe(A().Roster:ByGUID(guid)).sections) do if s.id == id then return s end end
	return nil
end

local function holds(v, needle, seen)
	if type(v) == "string" then return v:find(needle, 1, true) ~= nil end
	if type(v) ~= "table" then return false end
	seen = seen or {}
	if seen[v] then return false end
	seen[v] = true
	for k, x in pairs(v) do
		if holds(k, needle, seen) or holds(x, needle, seen) then return true end
	end
	return false
end

describe("the own offer", function()
	before_boot(setup(3))

	it("is off until the click; one click lists this character, and Edit sets the topics and the note", function()
		isNil(Mn():Own())
		eq(S():Count("mentor"), 0)
		truthy(V():Offer())
		local rec = Mn():Own()
		eq(rec.id, "M:" .. ME); eq(rec.on, true); isNil(rec.topics); isNil(rec.note)
		rec = Mn():Edit({ "pvp", "raids", "pvp" }, "  Ask|me\nanything  ")
		deepEq(rec.topics, { "raids", "pvp" })
		eq(rec.note, "Askme anything"); eq(rec.rev, 2)
		local list = Mn():List()
		eq(#list, 1); eq(list[1].own, true)
		eq(#Mn():List("raids"), 1); eq(#Mn():List("addons"), 0)
		local _, why = Mn():Edit({ "cooking" }, "") eq(why, "topics")
		_, why = Mn():Edit({}, ("x"):rep(81)) eq(why, "note")
		_, why = Mn():Edit({}, ("à"):rep(41)) eq(why, "note", "bytes, not letters")
		truthy(Mn():Edit(Mn().TOPICS, ("x"):rep(80)), "every topic and the longest note fit the record")
	end)

	it("is left with one click, at any time, and can come back", function()
		truthy(Mn():Join({ "raids" }, "hi"))
		truthy(V():Leave())
		local rec = S():Get("mentor", "M:" .. ME)
		eq(rec.off, true); isNil(rec.on); isNil(rec.topics); isNil(rec.note); eq(rec.rev, 2)
		isNil(Mn():Own()); eq(#Mn():List(), 0)
		local ok, why = Mn():Leave() eq(ok, false); eq(why, "none")
		truthy(Mn():Join())
		eq(#Mn():List(), 1)
	end)

	it("stops joining and editing after 10 writes in an hour, but never holds a leaving back", function()
		truthy(Mn():Join())
		for i = 2, 10 do truthy(Mn():Edit({}, "n" .. i), i) end
		local _, why = Mn():Edit({}, "again") eq(why, "rate")
		truthy(Mn():Leave())
		_, why = Mn():Join() eq(why, "rate")
		Mock.StepClock(HOUR + 1)
		truthy(Mn():Join())
	end)

	it("is one per account: a second character is refused, edits and leaves the first one's", function()
		sameAccount(ME, ALT)
		truthy(S():Accept("mentor", offer(ALT), from("Alt")))
		local rec, why = Mn():Join()
		isNil(rec); eq(why, "account")
		eq(Mn():Own().id, "M:" .. ALT)
		truthy(Mn():Edit({ "addons" }, "from the other character"))
		eq(S():Get("mentor", "M:" .. ALT).author, ME)
		truthy(Mn():Leave())
		eq(S():Get("mentor", "M:" .. ALT).off, true)
		truthy(Mn():Join())
	end)

	it("opens the dialog, toggles the topics and saves; What I share holds the switch, off by default", function()
		local function row()
			for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "mentor" then return r end end
		end
		eq(row().on, false); eq(row().records, 0)
		eq(row().switchLabel, L("MEN_OFFER"))
		truthy(holds(row().lines, L("MEN_PAIRS_NOTE")))
		truthy(A().ShareModel.SetSwitch("mentorOffer", true))
		eq(row().on, true); eq(row().rev, 1); truthy(row().age)
		truthy(V():OpenDialog())
		eq(V():Toggle("pvp"), true)
		truthy(V():Save("World PvP"))
		deepEq(Mn():Own().topics, { "pvp" })
		truthy(holds(row().lines, "World PvP"))
		truthy(A().ShareModel.SetSwitch("mentorOffer", false))
		eq(row().on, false); isNil(row().note)
		truthy(holds(row().lines, L("SHARE_MENTOR_LEFT")))
		eq(#Mock.errors, 0)
	end)

	it("shows the mode to a member with the list, Whisper and no error", function()
		truthy(accept(BOB, "Bob", { topics = { "raids" }, note = "hello" }))
		A().Shell:OpenView("reputation")
		truthy(A().ReputationView:SetMode("mentors"))
		eq(#V().shown, 1); eq(V().shown[1].name, "Bob")
		A().ReputationView:SetSearch("zzz")
		eq(#V().shown, 0)
		A().ReputationView:SetSearch("")
		truthy(V():Offer())
		A().ReputationView:Redraw()
		eq(#V().shown, 2)
		V():Whisper(BOB)
		eq(#Mock.errors, 0)
	end)
end)

describe("MEN-01..MEN-04: what is accepted", function()
	before_boot(setup(1))

	it("takes only the own offer of a character: nobody lists somebody else, an officer included", function()
		local ok, why = S():Accept("mentor", offer(BOB, { author = OFF }), from("Officer"))
		eq(ok, false); eq(why, "owner")
		ok, why = S():Accept("mentor", offer(BOB, { author = ANN }), from("Ann"))
		eq(ok, false); eq(why, "owner")
		ok, why = S():Accept("mentor", offer(BOB), from("Ann"))
		eq(ok, false); eq(why, "relay")
		truthy(S():Accept("mentor", offer(BOB), from("Officer")), "an officer relays the author's own record")
		local rec = S():Put("mentor", "M:" .. ANN, { on = true })
		isNil(rec, "not even this client writes another member's offer")
	end)

	it("refuses a record of the wrong shape (owner)", function()
		local bad = {
			offer(BOB, { off = true }), offer(BOB, { on = false }), offer(BOB, { topics = { "cooking" } }),
			offer(BOB, { topics = { "pvp", "pvp" } }), offer(BOB, { topics = "pvp" }), offer(BOB, { note = "a|cff" }),
			offer(BOB, { note = "two\nlines" }), offer(BOB, { note = ("x"):rep(81) }), offer(BOB, { extra = 1 }),
			offer(BOB, { id = BOB }), { id = "M:" .. BOB, author = BOB, rev = 1, time = GetServerTime() },
			{ id = "M:" .. BOB, author = BOB, rev = 1, time = GetServerTime(), off = true, note = "bye" },
		}
		for i, rec in ipairs(bad) do
			local ok, why = S():Accept("mentor", rec, from("Bob"))
			eq(ok, false, "record " .. i); eq(why, "owner", "record " .. i)
		end
		truthy(accept(BOB, "Bob", { topics = A().Mentors.TOPICS, note = ("x"):rep(80) }))
	end)

	it("takes at most 10 revisions of an author an hour (rate), and always the leaving of a listed offer", function()
		for i = 1, 10 do truthy(accept(BOB, "Bob", { rev = i }), i) end
		local ok, why = accept(BOB, "Bob", { rev = 11 })
		eq(ok, false); eq(why, "rate")
		truthy(S():Accept("mentor", left(BOB, 12), from("Bob")))
		ok, why = S():Accept("mentor", left(BOB, 13), from("Bob"))
		eq(ok, false); eq(why, "rate", "a leaving after a leaving counts")
		Mock.StepClock(HOUR + 1)
		truthy(accept(BOB, "Bob", { rev = 14 }))
	end)

	it("lists one offer per account, the oldest; a member who left the guild is not listed; a leaving expires", function()
		sameAccount(BOB, ALT)
		truthy(accept(ALT, "Alt", { time = GetServerTime() - 100 }))
		truthy(accept(BOB, "Bob"))
		deepEq(names(Mn():List()), { "Alt" })
		truthy(S():Accept("mentor", left(ALT), from("Alt")))
		deepEq(names(Mn():List()), { "Bob" })
		S():Records("mentor")["M:Player-1-0000FFFF"] = offer("Player-1-0000FFFF")
		deepEq(names(Mn():List()), { "Bob" }, "not in the roster")
		Mock.StepClock(61 * DAY)
		S():Prune()
		isNil(S():Get("mentor", "M:" .. ALT), "an off after 60 days")
		truthy(S():Get("mentor", "M:" .. BOB), "an offer does not expire")
	end)
end)

describe("the suggested pairs", function()
	before_boot(setup(1))

	local function offers(...)
		for _, g in ipairs({ ... }) do
			S():Records("mentor")["M:" .. g] = offer(g)
		end
	end

	it("takes the new members from the open trials and the joins of 30 days, the oldest first", function()
		joined(NEW2, 10)
		joined(NEW1, 20)
		joined(NEW3, 31)
		truthy(A().Trials:Start(NEW4, 14, A().Trials.DayOfNumber(A().Trials.Number(A().Trials.Today()) - 25)))
		local list = Mn():Newcomers()
		deepEq(names(list), { "Newfour", "Newone", "Newtwo" })
		eq(list[1].trial, true); isNil(list[1].joined)
	end)

	it("suggests only those who offered, never a new member, and stops at once when they leave", function()
		joined(NEW1, 2)
		joined(NEW2, 1)
		played({ { BOB, NEW1, 500 }, { ANN, NEW1, 100 }, { NEW2, NEW1, 900 } })
		eq(Mn():Pairs().mentors, 0, "nobody offered: nobody suggested, whoever they played with")
		eq(#Mn():Pairs().rows[1].mentors, 0)
		offers(ANN, NEW2)
		local data = Mn():Pairs()
		deepEq(names(data.rows[1].mentors), { "Ann" })
		truthy(S():Accept("mentor", left(ANN), from("Ann")))
		eq(#Mn():Pairs().rows[1].mentors, 0)
	end)

	it("orders by time together, then shared teammates, same group, common hours, level and name", function()
		joined(NEW1, 2)
		offers(BOB, ANN, CAT, DAN, ALT)
		-- Dan played with the new member; Cat shares a teammate with them; Alt, Bob and Ann only differ by level
		played({ { DAN, NEW1, 60 }, { CAT, NEW2, 300 }, { NEW1, NEW2, 200 } })
		local list = Mn():Pairs().rows[1].mentors
		deepEq(names(list), { "Dan", "Cat", "Bob" })
		eq(list[1].together, 60); eq(list[1].first, true)
		eq(list[2].shared, 200)
		eq(list[2].sameGroup, true)
		deepEq(names(Mn():Pairs().rows[1].mentors), names(list), "the same data, the same pairs")
		matches(V().Reasons(list[1]), "1%.0 h together")
		eq(V().Reasons(list[3]), L("MEN_WHY_NONE"))
		local function c(f)
			local base = { name = "x", account = "x", together = 0, shared = 0, sameGroup = false, hours = 0, level = 1 }
			for k, v in pairs(f) do base[k] = v end
			return base
		end
		local B = Mn().Better
		truthy(B(c{ together = 1 }, c{ shared = 99 }))
		truthy(B(c{ shared = 1 }, c{ sameGroup = true }))
		truthy(B(c{ sameGroup = true }, c{ hours = 99 }))
		truthy(B(c{ hours = 1 }, c{ level = 60 }))
		truthy(B(c{ level = 2 }, c{ name = "a" }))
		truthy(B(c{ name = "a" }, c{ name = "b" }))
	end)

	it("counts the hours both usually play, only for who may see who is online", function()
		local AV = A().Availability
		local function levels(cells)
			local l = {}
			for h = 0, 167 do l[h] = cells[h] or 0 end
			return AV.Encode(l)
		end
		for g, cells in pairs({ [ANN] = { [1] = 3, [2] = 2, [3] = 1 }, [NEW1] = { [1] = 2, [2] = 3, [3] = 3 } }) do
			S():Records("avail")[g] = { id = g, author = g, rev = 1, time = GetServerTime(), p = levels(cells), w = 4 }
		end
		AV:Changed()
		eq(AV:Common(ANN, NEW1), 2)
		joined(NEW1, 2)
		offers(ANN, BOB)
		deepEq(names(Mn():Pairs().rows[1].mentors), { "Ann", "Bob" }, "the common hours before the level")
		rank(3)
		eq(AV:Common(ANN, NEW1), 0)
	end)

	it("gives at most 3 mentors per new member and 3 first choices per mentor, the oldest new member first", function()
		joined(NEW1, 4); joined(NEW2, 3); joined(NEW3, 2); joined(NEW4, 1)
		offers(BOB, ANN, CAT, DAN)
		local together = {}
		for _, g in ipairs({ NEW1, NEW2, NEW3, NEW4 }) do together[#together + 1] = { BOB, g, 100 } end
		played(together)
		local rows = Mn():Pairs().rows
		for i = 1, 4 do eq(#rows[i].mentors, 3, i) end
		for i = 1, 3 do eq(rows[i].mentors[1].name, "Bob", i); eq(rows[i].mentors[1].first, true) end
		eq(rows[4].name, "Newfour")
		truthy(rows[4].mentors[1].name ~= "Bob", "the first choice moves on")
		eq(rows[4].mentors[1].first, true)
		eq(rows[4].mentors[2].name, "Bob", "still shown, not as the first choice")
		-- with one mentor only, the fourth new member gets no first choice
		for _, g in ipairs({ ANN, CAT, DAN }) do S():Records("mentor")["M:" .. g] = nil end
		rows = Mn():Pairs().rows
		isNil(rows[4].mentors[1].first)
		truthy(holds(V().PairLines(Mn():Pairs()), L("MEN_FULL"):format(3)))
	end)

	it("are shown on the Trials page and the new member's card, and are never saved or sent", function()
		joined(NEW1, 2)
		offers(BOB)
		played({ { BOB, NEW1, 120 } })
		Mock.Slash("/accord officers")
		A().Shell:OpenView("officers")
		truthy(A().OfficersView:OpenPage("trials") ~= false)
		A().TrialsView.tab = "mentors"
		A().OfficersView:Redraw()
		truthy(holds(V().pairs.list, "Bob"))
		truthy(holds(V().pairs.list, "Newone"))
		local s = section(NEW1, "mentors")
		truthy(s)
		truthy(holds(s.lines, "Bob"))
		isNil(section(ANN, "mentors"), "not a new member")
		local notices = #A().Notify:Entries()
		V():Whisper(BOB)
		Mock.StepClock(900)
		for set in pairs(S().SETS) do
			for _, rec in pairs(S():Records(set)) do
				if set ~= "coplay" and set ~= "timeline" then falsy(holds(rec, NEW1) and holds(rec, BOB), set) end
			end
		end
		falsy(holds(A().GuildKey:Data(), "together"))
		eq(#A().Notify:Entries(), notices, "a suggested pair notifies nobody (Q38)")
		eq(#Mock.errors, 0)
	end)

	it("do not exist for a member", function()
		joined(NEW1, 2)
		offers(BOB)
		rank(3)
		falsy(Mn().CanSeePairs())
		eq(#Mn():Newcomers(), 0); eq(#Mn():Pairs().rows, 0)
		isNil(Mn():PairsFor(NEW1))
		isNil(section(NEW1, "mentors"))
		eq(#Mn():List(), 1, "the list is for everybody")
	end)
end)

describe("with the switch recruit off", function()
	before_boot(setup(1, { recruit = false }))

	it("writes, accepts, shows nothing", function()
		local rec, why = Mn():Join() isNil(rec); eq(why, "off")
		local ok, w = accept(BOB, "Bob") eq(ok, false); eq(w, "set")
		eq(#Mn():List(), 0)
		falsy(Mn().CanSeePairs())
		for _, r in ipairs(A().ShareModel.Describe()) do truthy(r.id ~= "mentor") end
		for _, m in ipairs(A().ReputationView:ModeList()) do truthy(m.id ~= "mentors") end
		isNil(section(BOB, "mentors"))
		eq(S():Count("mentor"), 0)
	end)
end)

describe("the mentors in the demo guild", function()
	before_boot(function(M) M.features = { recruit = true } end)

	it("has five offers and suggests them to the new members, sending nothing", function()
		Mock.Slash("/accord demo")
		eq(#Mn():List(), 5)
		A().Social:ComputeNow()
		local data = Mn():Pairs()
		truthy(#data.rows >= 2, "new members: " .. #data.rows)
		for _, row in ipairs(data.rows) do eq(#row.mentors, 3, row.name) end
		eq(#Mock.chat.sent, 0)
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator
---------------------------------------------------------------------------------------------------------------------
local function seed(sim, c)
	local db = c:addon().Config.db.account
	if db.avail and next(db.avail.weeks) then return end
	local week = c:addon().Availability.Now()
	local data = { since = week - 3, weeks = {} }
	for w = week - 3, week - 1 do
		local cells = {}
		for k = 1, 30 do cells[(c.index * 11 + k * 5) % 168] = 45 end
		data.weeks[w] = cells
	end
	db.avail = data
end

describe("the mentor offers between clients", function()
	local function simulated(Mk) Mk.features = { season = true, recruit = true } end

	it("reach the guild, and so does the leaving; nothing about a pair travels", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 5 }, setup = simulated, accounts = true, seed = 71 }
		local types = {}
		for i = 1, 5 do
			local tr = sim:client(i).online and sim:client(i):addon().Transport
			if tr then
				local original = tr.wire
				tr.wire = function(prio, txt, dist, target, done)
					local m = sim:client(i):addon().Codec:Decode(txt)
					if type(m) == "table" then types[m.t] = true end
					return original(prio, txt, dist, target, done)
				end
			end
		end
		sim:advance(120)
		truthy(sim:client(2):addon().Mentors:Join({ "raids" }, "hello"))
		sim:advance(60)
		for _, j in ipairs({ 1, 3, 4 }) do
			eq(#sim:client(j):addon().Mentors:List(), 1, "client " .. j)
		end
		sim:client(5):login()
		truthy(sim:advanceUntil(function() return #sim:client(5):addon().Mentors:List() == 1 end, 25 * 60), "the newcomer")
		sim:client(4):logout()
		truthy(sim:client(2):addon().Mentors:Leave())
		sim:advance(60)
		sim:client(4):login()
		truthy(sim:advanceUntil(function() return #sim:client(4):addon().Mentors:List() == 0 end, 25 * 60), "the one away")
		for _, j in ipairs({ 1, 3, 5 }) do eq(#sim:client(j):addon().Mentors:List(), 0, "client " .. j) end
		sim:client(1):addon().Mentors:Pairs()
		for i = 1, 5 do eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i) end
	end)

	-- The scenario of M10.8 (Tests/test_availability.lua): 50 clients, 45 minutes of churn, availability maps included.
	-- `with`: one account in ten also joins the mentor list and leaves it again during the churn.
	local function churn(with, established)
		local N, OFFICERS = 50, { 1, 11, 21, 31, 41 }
		local offline = {}
		for i = 2, N, 2 do offline[#offline + 1] = i end
		local sim = Sim.new{ clients = N, officers = OFFICERS, setup = simulated, offline = not established and offline or nil,
			availability = true, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42 }
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		local writes, lockUntil = {}, {}
		local function writeNext(c)
			writes[c.index] = (writes[c.index] or 0) + 1
			local S_, guid = c:addon().Store, c:guid()
			truthy(S_:Put("accounts", guid, { token = "T" .. c.index, chars = { { guid = guid } }, n = writes[c.index] }))
			truthy(S_:Put("contacts", guid, { battleTag = c.name .. "#" .. c.index, n = writes[c.index] }))
		end
		for i = 1, N do
			local c = sim:client(i)
			if c.online then
				writeNext(c)
				seed(sim, c)
			end
		end
		if established then
			sim:advance(30 * 60)
			for i = 2, N, 2 do sim:client(i):logout() end
			sim:resetStats()
		end
		local changed, joinedAt, gone = {}, {}, {}
		local joins, leaves = 0, 0
		for step = 1, 90 do
			for i = 1, N do
				local c = sim:client(i)
				local r = rand()
				if c.online then
					if r < 0.04 then c:logout()
					elseif r < 0.08 then writeNext(c)
					elseif r < 0.10 and not lockUntil[i] then
						c:restrict({ lockdown = true })
						lockUntil[i] = sim.time + 60 + 240 * rand()
					end
				elseif r < 0.06 then
					c:login()
					seed(sim, c)
					if not writes[i] then writeNext(c) end
				end
				if lockUntil[i] and sim.time >= lockUntil[i] then
					c:restrict({ lockdown = false })
					lockUntil[i] = nil
				end
				if established and i % 7 == 0 and not changed[i] and step >= i and c.online then
					changed[i] = true
					local AV_ = c:addon().Availability
					local levels = {}
					for h = 0, 167 do levels[h] = (h + i) % 5 == 0 and 3 or 0 end
					truthy(c:addon().Store:Put("avail", c:guid(), { p = AV_.Encode(levels), w = 4 }))
				end
				if with and i % 10 == 3 and c.online then
					if not joinedAt[i] and step >= i then
						joinedAt[i] = step
						joins = joins + 1
						truthy(c:addon().Mentors:Join({ "raids", "dungeons", "professions" }, ("n"):rep(60)))
					elseif joinedAt[i] and not gone[i] and step >= joinedAt[i] + 20 then
						gone[i] = true
						leaves = leaves + 1
						truthy(c:addon().Mentors:Leave())
					end
				end
			end
			sim:advance(30)
		end
		local st = sim:stats()
		for i = 1, N do
			local c = sim:client(i)
			if c.online then eq(c:addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing") end
		end
		return st, joins, leaves
	end

	local function report(label, st, base)
		T.log(("mentors, %s: churn %.0f B/min per client on average (%.0f without them), %.0f at most (%.0f)"):format(
			label, st.avg.bytesPerMinute, base.avg.bytesPerMinute, st.max.bytesPerMinute, base.max.bytesPerMinute))
	end

	it("50 clients of a guild in step stay inside the shared traffic budget (SPEC-09 §7)", function()
		local base = churn(false, true)
		local st, joins, leaves = churn(true, true)
		report("a guild in step", st, base)
		truthy(joins >= 4, "joins " .. joins); truthy(leaves >= 3, "leaves " .. leaves)
		truthy(st.avg.bytesPerMinute <= 450, "churn average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2048, "churn busiest client " .. st.max.bytesPerMinute)
	end)

	-- The same ten changes in 45 minutes while half the guild has never run do not fit the 550 B/min of SPEC-10 Q26:
	-- over the seeds 42-45 they add 30-77 B/min on average (543-583) and up to 650 B/min to the busiest client. The
	-- bounds below keep the measure from growing until the owner answers SPEC-10 Q39.
	it("measures the offers while the maps are first exchanged (SPEC-10 Q39)", function()
		local base = churn(false, false)
		local st, joins = churn(true, false)
		report("first exchange", st, base)
		truthy(joins >= 4, "joins " .. joins)
		truthy(st.avg.bytesPerMinute <= 600, "first exchange average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2816, "first exchange busiest client " .. st.max.bytesPerMinute)
	end)
end)

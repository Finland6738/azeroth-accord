-- The guild group finder, listings and applications (M9.6; SPEC-13 §6, ADR 0024, SPEC-10 Q18): a listing from outside
-- the guild or with a forged author is refused (also from an officer); applications reach only the leader; full, expired
-- and abandoned listings close on every client; GASK brings the open listings to who comes later; the simulator keeps the
-- traffic inside the budget of SPEC-02 §4 with 50 open listings. With the switch `groups` off nothing of it exists.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function G() return AzerothAccord.Groups end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"
local DEADMINES = 36

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 30, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
	} }
end

local function on(Mk) Mk.features = { groups = true } guild(3) end
local function off(Mk) guild(3) end

-- Every message handed to the transport from now on: { dist, msg, target }.
local function capture()
	local out, T_ = {}, A().Transport
	local original = T_.Send
	T_.Send = function(self, dist, msg, opts)
		out[#out + 1] = { dist = dist, msg = msg, target = opts and opts.target }
		return original(self, dist, msg, opts)
	end
	return out
end

local function ofType(list, t)
	local out = {}
	for _, e in ipairs(list) do if e.msg.t == t then out[#out + 1] = e end end
	return out
end

local function hear(msg, sender, dist) A().Bus:Emit("NET_MESSAGE", msg, sender, dist or "WHISPER") end

-- A listing as its leader's client would write it.
local function listing(author, n, fields)
	local t = GetServerTime()
	local rec = { id = author .. ":" .. (n or 1), author = author, rev = 1, time = t, kind = "dungeon", act = DEADMINES,
		min = 15, max = 25, size = 5, have = 1, need = { t = 1, h = 1, d = 2 }, created = t, ends = t + 7200, status = "open" }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

local function post(spec)
	local s = { kind = "dungeon", act = DEADMINES, need = { t = 1, h = 1, d = 2 } }
	for k, v in pairs(spec or {}) do s[k] = v end
	return G():Post(s)
end

describe("the switch `groups`", function()
	before_boot(off)

	it("is off in the shipped code, and then nothing of the group finder exists or travels", function()
		eq(A().Features.groups, false)
		falsy(A().Features.On("groups"))
		falsy(S().IsActive("groups"))
		local sent = capture()
		local ok, why = post()
		falsy(ok); eq(why, "off")
		isNil(S():Put("groups", ME .. ":1", listing(ME)))
		eq(select(2, S():Check("groups", listing(BOB), { sender = "Bob", dist = "GUILD" })), "set")
		eq(S():Receive("groups", { listing(BOB) }, "Bob", "GUILD"), 0)
		hear({ t = "GASK", h = "" }, "Bob", "GUILD")
		hear({ t = "GAPP", g = ME .. ":1", k = "apply", r = "t", l = 20 }, "Bob")
		falsy(G():Ask())
		falsy(G():Apply(BOB .. ":1", "t"))
		Mock.Advance(120)
		eq(#sent, 0, "no group traffic at all")
		eq(#G():List(), 0)
		isNil(A().Groups.ticker, "no clean-up timer")
		falsy(A().Diagnostics.Report():find("Groups:", 1, true))
	end)

	it("leaves the sync summary as in v0.8.0: the set is not in it", function()
		S():Records("groups")[BOB .. ":1"] = listing(BOB)
		A().Sync:Invalidate()
		isNil(A().Sync:Groups()[BOB])
	end)
end)

describe("the owner rule and the texts", function()
	before_boot(on)

	it("accepts a well formed listing and refuses every bad field", function()
		truthy(G().ValidRecord(listing(BOB)))
		truthy(G().ValidRecord(listing(BOB, 7, { kind = "help", act = "Stranglethorn Vale", need = { d = 1 }, note = "elite at the camp" })))
		local bad = {
			{ id = ANN .. ":1" }, { id = BOB .. ":x" }, { id = BOB }, { kind = "mythic" }, { act = 0 }, { act = 2000000 },
			{ kind = "quest", act = 36 }, { kind = "quest", act = "" }, { kind = "quest", act = ("x"):rep(41) },
			{ kind = "quest", act = "a|cffff0000b" }, { kind = "quest", act = " padded" }, { min = 0 }, { max = 61 },
			{ min = 30, max = 20 }, { size = 1 }, { size = 41 }, { have = 0 }, { have = 6 }, { need = { t = -1 } },
			{ need = { x = 1 } }, { need = { d = 5 } }, { note = ("n"):rep(81) }, { meet = ("m"):rep(41) }, { meet = "a\nb" },
			{ ends = GetServerTime() + 60 }, { ends = GetServerTime() + 5 * 3600 }, { status = "maybe" },
			{ status = "closed" }, { status = "closed", why = "bored" }, { status = "open", why = "leader" }, { rev = 101 },
		}
		for i, change in ipairs(bad) do falsy(G().ValidRecord(listing(BOB, 1, change)), "bad field " .. i) end
	end)

	it("cleans form texts: no link escapes or control characters, trimmed, never cut inside a character", function()
		eq(G().CleanText("  near  the |cffff0000bank|r\n ", 40), "near the cffff0000bank r")
		eq(G().CleanText(nil, 40), "")
		eq(#G().CleanText(("x"):rep(100), 40), 40)
		local cut = G().CleanText(("a"):rep(39) .. "é", 40)
		eq(cut, ("a"):rep(39))
		truthy(G().ValidText(cut, 40))
		eq(G().CleanText("in città", 40), "in città", "a letter whose last byte looks like a space stays whole")
		truthy(G().ValidText("in città", 40))
	end)

	it("knows the dungeons and raids of the base game, and the name of an unknown instance", function()
		local row = A().GroupActivities:Get(DEADMINES)
		eq(row.kind, "dungeon"); eq(row.size, 5)
		eq(A().GroupActivities:Get(409).size, 40)
		eq(A().GroupActivities:Name(123456), "Instance 123456")
		truthy(#A().GroupActivities:List("raid") >= 5)
	end)
end)

describe("the activity table from the client's own Group Finder", function()
	before_boot(function(Mk)
		on(Mk)
		C_LFGList = {
			GetAvailableCategories = function() return { 2, 114 } end,
			GetLfgCategoryInfo = function(id) return { name = id == 2 and "Dungeons" or "Raids", isRaid = id == 114 } end,
			GetAvailableActivities = function(id) return id == 2 and { 801, 802 } or { 900 } end,
			GetActivityInfoTable = function(id)
				if id == 801 then return { mapID = 36, maxNumPlayers = 5, minLevel = 17, maxLevelSuggestion = 26, fullName = "Deadmines" } end
				if id == 802 then return { mapID = 777001, maxNumPlayers = 5, minLevel = 60, maxLevelSuggestion = 60, fullName = "New Place" } end
				return { mapID = 777002, maxNumPlayers = 25, minLevel = 60, maxLevelSuggestion = 60, fullName = "New Raid" }
			end,
		}
	end)

	it("corrects a known row and adds the instances the client brings back", function()
		local Act = A().GroupActivities
		Act:Reset()
		eq(Act:Get(36).min, 17); eq(Act:Get(36).max, 26)
		eq(Act:Get(777001).kind, "dungeon")
		eq(Act:Get(777002).kind, "raid"); eq(Act:Get(777002).size, 25)
		notNil(post({ kind = "raid", act = 777002, need = { t = 2, h = 5, d = 15 } }))
	end)
end)

describe("the trust rules of a listing (one client)", function()
	before_boot(on)

	it("refuses a listing from outside the guild", function()
		eq(S():Receive("groups", { listing(BOB) }, "Stranger", "GUILD"), 0)
		eq(S().stats.reasons.sender, 1)
		isNil(S():Get("groups", BOB .. ":1"))
	end)

	it("refuses a listing whose author is somebody else, from a member and from an officer alike", function()
		eq(S():Receive("groups", { listing(BOB) }, "Ann", "GUILD"), 0)
		eq(S():Receive("groups", { listing(BOB) }, "Boss", "GUILD"), 0, "an officer cannot relay a listing (GRP-02)")
		eq(S().stats.reasons.relay, 2)
		isNil(S():Get("groups", BOB .. ":1"))
		eq(S():Receive("groups", { listing(BOB) }, "Bob", "GUILD"), 1, "its own leader is believed")
		notNil(S():Get("groups", BOB .. ":1"))
	end)

	it("refuses a listing that breaks the owner rule, and one already past its time", function()
		eq(S():Receive("groups", { listing(BOB, 1, { id = ANN .. ":1" }) }, "Bob", "GUILD"), 0)
		local t = GetServerTime()
		eq(S():Receive("groups", { listing(BOB, 2, { created = t - 9000, ends = t - 1800, time = t - 1000 }) }, "Bob", "GUILD"), 0)
		eq(S().stats.reasons.expired, 1)
	end)
end)

describe("open or closed: the rule of every client", function()
	before_boot(on)

	local function hold(rec) S():Receive("groups", { rec }, "Bob", "GUILD") return S():Get("groups", rec.id) end

	it("is open while valid, and closed when full, expired, abandoned or replaced", function()
		local rec = hold(listing(BOB))
		eq(G():Status(rec), "open")
		eq(G():Status(listing(BOB, 1, { need = { t = 0 }, have = 5 })), "full")
		eq(G():Status(listing(BOB, 1, { status = "full" })), "full")
		eq(G():Status(rec, rec.ends), "expired")
		eq(G():Status(listing(BOB, 1, { status = "closed", why = "logout" })), "offline")
		eq(G():Status(listing(BOB, 1, { status = "closed", why = "leader" })), "closed")
		local newer = hold(listing(BOB, 2, { created = rec.created + 5, time = rec.created + 5 }))
		eq(G():Status(rec), "replaced", "a leader has one open listing: the newest")
		eq(G():Status(newer), "open")
		Mock.guild.members[1].online = false
		Mock.Fire("GUILD_ROSTER_UPDATE")
		eq(G():Status(newer), "offline", "the leader left the game")
	end)

	it("drops a listing GRACE seconds after its end, and says so", function()
		local rec = hold(listing(BOB))
		local changed = {}
		A().Bus:On("GROUPS_CHANGED", function(id) changed[#changed + 1] = id end)
		Mock.Advance(7200 + 60)
		eq(G():Status(S():Get("groups", rec.id)), "expired")
		contains(changed, rec.id)
		Mock.Advance(G().GRACE + 60)
		isNil(S():Get("groups", rec.id))
	end)
end)

describe("posting, changing and closing (the leader's client)", function()
	before_boot(on)

	it("posts a listing that goes on GUILD after the batch, never in a HELLO", function()
		local sent = capture()
		local rec = post({ note = "  bring  water ", meet = "Westfall, the tower" })
		notNil(rec)
		eq(rec.id, ME .. ":1"); eq(rec.author, ME); eq(rec.size, 5); eq(rec.min, 15); eq(rec.max, 23); eq(rec.have, 1)
		eq(rec.note, "bring water"); eq(rec.ends - rec.created, G().DURATION); eq(rec.status, "open")
		eq(A().Config.db.char.groups.next, 1)
		Mock.Advance(6)
		local recs = ofType(sent, "REC")
		eq(#recs, 1); eq(recs[1].dist, "GUILD"); eq(recs[1].msg.s, "groups")
		isNil(A().Sync:Groups()[ME], "not in the summary (GRP-03)")
	end)

	it("refuses a bad form and says why", function()
		eq(select(2, post({ kind = "x" })), "kind")
		eq(select(2, post({ act = 999 })), "act")
		eq(select(2, post({ kind = "raid" })), "act", "the Deadmines is no raid")
		eq(select(2, post({ size = 6 })), "size")
		eq(select(2, post({ min = 30, max = 20 })), "level")
		eq(select(2, post({ need = {} })), "need")
		eq(select(2, post({ need = { d = 5 } })), "need")
		eq(select(2, post({ duration = 600 })), "duration")
		eq(select(2, G():Post({ kind = "quest", act = "  ", need = { d = 1 } })), "act")
		eq(#G():List(), 0)
	end)

	it("keeps one open listing per character: a new one replaces the old", function()
		local first = post()
		local second = post({ kind = "quest", act = "The Defias Brotherhood", need = { d = 2 } })
		eq(second.id, ME .. ":2")
		local old = S():Get("groups", first.id)
		eq(old.status, "closed"); eq(old.why, "replaced")
	end)

	it("closes its open listing at the next login, not after a /reload", function()
		local rec = post()
		Mock.Reload()
		eq(S():Get("groups", rec.id).status, "open")
		Mock.Relog(120)
		local after = S():Get("groups", rec.id)
		eq(after.status, "closed"); eq(after.why, "logout")
		local again = post()
		eq(again.id, ME .. ":2", "the ids keep counting")
	end)

	it("merges quick changes into one write every 10 seconds, and becomes full when nobody is needed", function()
		local rec = post()
		truthy(G():Update(rec.id, { note = "first" }))
		truthy(G():Update(rec.id, { note = "second" }))
		eq(S():Get("groups", rec.id).rev, 1, "waiting for the gap")
		Mock.Advance(11)
		local now = S():Get("groups", rec.id)
		eq(now.rev, 2); eq(now.note, "second")
		truthy(G():Update(rec.id, { need = { t = 0, h = 0, d = 0 } }))
		eq(S():Get("groups", rec.id).status, "full")
	end)

	it("becomes full when the game's group reaches its size", function()
		local rec = post()
		Mock.group.Set{ members = { {}, {}, {}, {} } }
		eq(S():Get("groups", rec.id).status, "full")
	end)

	it("posts a help listing with the zone name only", function()
		local rec = G():Post({ kind = "help", act = "Duskwood", need = { d = 1 }, size = 3 })
		eq(rec.act, "Duskwood")
		eq(rec.kind, "help")
	end)
end)

describe("applications on the leader's client", function()
	before_boot(on)

	local function apply(sender, role, extra)
		local msg = { t = "GAPP", g = ME .. ":1", k = "apply", r = role or "h", l = 22 }
		for k, v in pairs(extra or {}) do msg[k] = v end
		hear(msg, sender)
	end

	it("takes an application from a guild member by whisper, and nothing from outside or on GUILD", function()
		post()
		apply("Bob", "h", { c = "  healer |r here " })
		apply("Stranger", "t")
		apply("Ann", "t")
		hear({ t = "GAPP", g = ME .. ":1", k = "apply", r = "d" }, "Boss", "GUILD")
		local list = G():Applicants(ME .. ":1")
		eq(#list, 2)
		eq(list[1].name, "Ann"); eq(list[1].r, "t")
		eq(list[2].name, "Bob"); eq(list[2].r, "h"); eq(list[2].c, "healer r here"); eq(list[2].l, 22)
		eq(A().Config.db.char.groups.apps[ME .. ":1"].Bob.r, "h", "saved per character, never in the Store")
		isNil(S():Records("groups")[ME .. ":1"].apps)
	end)

	it("answers `full` for a role nobody needs any more, and to the 41st applicant", function()
		post({ size = 40, need = { d = 39 }, act = "The Barrens", kind = "farm" })
		local sent = capture()
		apply("Bob", "t")
		eq(#G():Applicants(ME .. ":1"), 0)
		local names = {}
		local members = Mock.guild.members
		for i = 1, 41 do
			local name = "Dps" .. i
			members[#members + 1] = { name = name, level = 30, class = "ROGUE", rank = 3, guid = ("Player-1-%08X"):format(0x5000 + i), online = true }
			names[#names + 1] = name
		end
		Mock.Fire("GUILD_ROSTER_UPDATE")
		for _, name in ipairs(names) do apply(name, "d") end
		eq(#G():Applicants(ME .. ":1"), G().MAX_APPLICANTS)
		local fulls = ofType(sent, "GAPP")
		eq(#fulls, 2)
		eq(fulls[1].target, "Bob"); eq(fulls[1].msg.k, "full")
		eq(fulls[2].target, "Dps41")
	end)

	it("handles at most 10 GAPP per sender per minute", function()
		post()
		for _ = 1, 15 do
			apply("Bob", "h")
			hear({ t = "GAPP", g = ME .. ":1", k = "cancel" }, "Bob")
		end
		eq(G().state.stats.appsRefused, 20, "30 messages, 10 handled")
		Mock.Advance(61)
		apply("Bob", "h")
		eq(#G():Applicants(ME .. ":1"), 1)
	end)

	it("accepts with an invitation through Compat, rewrites need and have, and tells the candidate", function()
		local rec = post()
		apply("Bob", "h")
		apply("Ann", "t")
		local sent = capture()
		truthy(G():Accept(rec.id, "Bob"))
		eq(Mock.group.invites[#Mock.group.invites], "Bob")
		Mock.Advance(11)
		local now = S():Get("groups", rec.id)
		eq(now.need.h, 0); eq(now.have, 2); eq(now.status, "open")
		local answers = ofType(sent, "GAPP")
		eq(#answers, 1); eq(answers[1].dist, "WHISPER"); eq(answers[1].target, "Bob"); eq(answers[1].msg.k, "accept")
		truthy(G():Decline(rec.id, "Ann"))
		eq(ofType(sent, "GAPP")[2].msg.k, "decline")
		eq(#G():Applicants(rec.id), 0)
	end)

	it("becomes full at the last accepted player and tells the ones still waiting", function()
		local rec = post({ need = { h = 1 }, size = 2 })
		apply("Bob", "h")
		apply("Ann", "h")
		local sent = capture()
		truthy(G():Accept(rec.id, "Bob"))
		eq(S():Get("groups", rec.id).status, "full")
		local g = ofType(sent, "GAPP")
		eq(#g, 2); eq(g[1].msg.k, "accept"); eq(g[2].target, "Ann"); eq(g[2].msg.k, "full")
		eq(#G():Applicants(rec.id), 0)
	end)

	it("never invites when it is not the group's leader or a party would have to become a raid", function()
		local rec = post({ kind = "raid", act = 309, need = { t = 2, h = 4, d = 10 }, min = 58 })
		apply("Ann", "h")
		Mock.group.Set{ members = { {}, {}, {}, {} } }
		eq(select(2, G():Accept(rec.id, "Ann")), "raid")
		Mock.group.notLeader = true
		eq(select(2, G():Accept(rec.id, "Ann")), "leader")
		Mock.group.notLeader = nil
		eq(#Mock.group.invites, 0)
	end)

	it("tells the waiting candidates when the leader closes, and forgets them", function()
		local rec = post()
		apply("Bob", "h")
		local sent = capture()
		truthy(G():Close(rec.id))
		eq(ofType(sent, "GAPP")[1].msg.k, "full")
		eq(#G():Applicants(rec.id), 0)
		eq(S():Get("groups", rec.id).why, "leader")
	end)
end)

describe("applying (the candidate's client)", function()
	before_boot(function(Mk) on(Mk) Mk.player.level = 20 end)

	local function hold(rec) S():Receive("groups", { rec }, rec.author == BOB and "Bob" or "Ann", "GUILD") return rec end

	it("sends the application to the leader only, by whisper, with the role and the level", function()
		local rec = hold(listing(BOB))
		local sent = capture()
		truthy(G():Apply(rec.id, "h", "  ready "))
		Mock.Advance(1)
		eq(#sent, 1)
		eq(sent[1].dist, "WHISPER"); eq(sent[1].target, "Bob")
		eq(sent[1].msg.t, "GAPP"); eq(sent[1].msg.k, "apply"); eq(sent[1].msg.r, "h"); eq(sent[1].msg.l, 20); eq(sent[1].msg.c, "ready")
		eq(G():Mine(rec.id).state, "waiting")
	end)

	it("refuses what the rules forbid", function()
		local rec = hold(listing(BOB))
		eq(select(2, G():Apply(rec.id, "x")), "role")
		eq(select(2, G():Apply(hold(listing(BOB, 2, { need = { d = 1 } })).id, "t")), "role")
		eq(select(2, G():Apply(hold(listing(ANN, 1, { min = 40, max = 60 })).id, "d")), "level")
		eq(select(2, G():Apply("nothing", "d")), "missing")
		eq(select(2, G():Apply(G():Post({ kind = "quest", act = "x", need = { d = 1 } }).id, "d")), "own")
	end)

	it("takes an answer only from the listing's leader, and waits 10 minutes after a decline", function()
		local rec = hold(listing(BOB))
		truthy(G():Apply(rec.id, "d"))
		hear({ t = "GAPP", g = rec.id, k = "accept" }, "Ann")
		hear({ t = "GAPP", g = rec.id, k = "accept" }, "Bob", "GUILD")
		eq(G():Mine(rec.id).state, "waiting", "not from somebody else, not on GUILD")
		hear({ t = "GAPP", g = rec.id, k = "decline" }, "Bob")
		eq(G():Mine(rec.id).state, "declined")
		eq(select(2, G():Apply(rec.id, "d")), "wait")
		Mock.Advance(G().DECLINE_WAIT + 1)
		truthy(G():Apply(rec.id, "d"))
	end)

	it("has at most three applications waiting; one whose listing was replaced stops waiting", function()
		local CAT = "Player-1-00000CA7"
		local m = Mock.guild.members
		m[#m + 1] = { name = "Cat", level = 20, class = "DRUID", rank = 3, guid = CAT, online = true }
		Mock.Fire("GUILD_ROSTER_UPDATE")
		truthy(G():Apply(hold(listing(BOB)).id, "d"))
		truthy(G():Apply(hold(listing(ANN)).id, "d"))
		S():Receive("groups", { listing(OFF) }, "Boss", "GUILD")
		truthy(G():Apply(OFF .. ":1", "d"))
		S():Receive("groups", { listing(CAT) }, "Cat", "GUILD")
		eq(select(2, G():Apply(CAT .. ":1", "d")), "limit")
		local t = GetServerTime() + 1
		hold(listing(BOB, 2, { created = t, time = t }))
		eq(G():Mine(BOB .. ":1").state, "closed", "Bob's newer listing replaced the one applied to")
		truthy(G():Apply(CAT .. ":1", "d"))
	end)

	it("stops waiting when the listing closes, by itself or by a message", function()
		local rec = hold(listing(BOB))
		truthy(G():Apply(rec.id, "d"))
		Mock.guild.members[1].online = false
		Mock.Fire("GUILD_ROSTER_UPDATE")
		Mock.Advance(61)
		eq(G():Mine(rec.id).state, "closed")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Several clients (network simulator)
---------------------------------------------------------------------------------------------------------------------
local function enabled(Mk) Mk.features = { groups = true } end

-- Every GAPP each client received: received[i] = { { k, from }, ... }.
local function listen(sim)
	local received = {}
	for i = 1, sim:count() do
		received[i] = {}
		local c = sim:client(i)
		if c.online then
			c:addon().Bus:On("NET_MESSAGE", function(msg, sender)
				if msg.t == "GAPP" then received[i][#received[i] + 1] = { k = msg.k, from = sender } end
			end)
		end
	end
	return received
end

local function spec(extra)
	local s = { kind = "dungeon", act = DEADMINES, need = { t = 1, h = 1, d = 2 }, min = 1, max = 60 }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

local function statusOn(sim, i, id)
	local Gc = sim:client(i):addon().Groups
	local rec = sim:client(i):addon().Store:Get("groups", id)
	return rec and Gc:Status(rec) or "missing"
end

describe("listings and applications across the guild", function()
	it("reach every member; an application reaches the leader only; acceptance closes the full group everywhere", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, setup = enabled, latency = { 0.05, 0.3 }, seed = 3 }
		sim:advance(40)
		local received = listen(sim)
		local leader = sim:client(2)
		local rec = leader:addon().Groups:Post(spec({ need = { t = 1, h = 1 }, size = 3 }))
		sim:advance(8)
		for i = 1, 5 do eq(statusOn(sim, i, rec.id), "open", "client " .. i) end
		truthy(sim:client(3):addon().Groups:Apply(rec.id, "t"))
		truthy(sim:client(4):addon().Groups:Apply(rec.id, "h"))
		truthy(sim:client(5):addon().Groups:Apply(rec.id, "h"))
		sim:advance(3)
		eq(#leader:addon().Groups:Applicants(rec.id), 3)
		for _, i in ipairs({ 1, 3, 4, 5 }) do eq(#received[i], 0, "client " .. i .. " heard no application") end
		eq(#received[2], 3)
		local nameOf = {}
		for _, a in ipairs(leader:addon().Groups:Applicants(rec.id)) do nameOf[a.guid] = a.name end
		truthy(leader:addon().Groups:Accept(rec.id, nameOf[Sim.guidOf(3)]))
		truthy(leader:addon().Groups:Accept(rec.id, nameOf[Sim.guidOf(4)]))
		sim:advance(15)
		eq(sim:client(3):addon().Groups:Mine(rec.id).state, "accepted")
		eq(sim:client(4):addon().Groups:Mine(rec.id).state, "accepted")
		eq(sim:client(5):addon().Groups:Mine(rec.id).state, "closed", "told that the group filled up")
		for i = 1, 5 do eq(statusOn(sim, i, rec.id), "full", "full on client " .. i) end
		for i = 1, 5 do eq(sim:client(i):addon().Store.stats.rejected, 0) end
	end)

	it("refuses a listing an officer forged for another leader, on every client", function()
		local sim = Sim.new{ clients = 4, officers = { 1 }, setup = enabled, seed = 5 }
		sim:advance(40)
		local officer = sim:client(1):addon()
		local t = officer.Compat.ServerTime()
		local forged = { id = Sim.guidOf(2) .. ":1", author = Sim.guidOf(2), rev = 1, time = t, kind = "quest", act = "Fake",
			min = 1, max = 60, size = 5, have = 1, need = { d = 1 }, created = t, ends = t + 3600, status = "open" }
		officer.Transport:Send("GUILD", { t = "REC", s = "groups", r = { forged } })
		sim:advance(5)
		for i = 2, 4 do
			local Sc = sim:client(i):addon().Store
			isNil(Sc:Get("groups", forged.id), "client " .. i)
			eq(Sc.stats.reasons.relay, 1)
		end
	end)

	it("closes an expired listing and an abandoned one on every client without a message, and forgets them", function()
		local sim = Sim.new{ clients = 4, setup = enabled, seed = 9 }
		sim:advance(40)
		local short = sim:client(2):addon().Groups:Post(spec({ duration = 1800 }))
		local left = sim:client(3):addon().Groups:Post(spec())
		sim:advance(8)
		sim:client(3):logout()
		sim:advance(5)
		for _, i in ipairs({ 1, 2, 4 }) do eq(statusOn(sim, i, left.id), "offline", "abandoned on client " .. i) end
		sim:advance(1800)
		for _, i in ipairs({ 1, 2, 4 }) do eq(statusOn(sim, i, short.id), "expired", "expired on client " .. i) end
		-- the leader comes back: its listing is written closed, so who comes later reads it closed too
		sim:client(3):login()
		sim:advance(10)
		for _, i in ipairs({ 1, 2, 4 }) do
			local r = sim:client(i):addon().Store:Get("groups", left.id)
			eq(r.status, "closed"); eq(r.why, "logout")
		end
		sim:advance(7200 + 700)
		for i = 1, 4 do
			isNil(sim:client(i):addon().Store:Get("groups", short.id))
			isNil(sim:client(i):addon().Store:Get("groups", left.id))
		end
	end)

	it("brings the open listings to a member who logs in later, with GASK", function()
		local sim = Sim.new{ clients = 5, offline = { 5 }, setup = enabled, seed = 11 }
		sim:advance(40)
		local ids = {}
		for i = 1, 3 do ids[i] = sim:client(i):addon().Groups:Post(spec()).id end
		sim:advance(10)
		sim:client(5):login()
		sim:advance(30)
		for i = 1, 3 do isNil(sim:client(5):addon().Store:Get("groups", ids[i]), "nothing comes by itself at login") end
		truthy(sim:client(5):addon().Groups:Ask())
		eq(select(2, sim:client(5):addon().Groups:Ask()), "recent")
		sim:advance(10)
		for i = 1, 3 do eq(statusOn(sim, 5, ids[i]), "open") end
		eq(sim:client(4):addon().Groups.state.stats.asksAnswered, 0, "a client without a listing stays quiet")
	end)

	it("asks once after the first HELLO of a login only when the notice of matching listings is on", function()
		local sim = Sim.new{ clients = 3, setup = enabled, seed = 17 }
		-- the first HELLO goes 10-30 seconds after the login: the choice is made before it
		sim:client(2):addon().Config.db.account.settings.notify.groups.off.match = false
		sim:advance(150)
		eq(sim:client(1):addon().Groups.state.stats.asks, 0, "off by default: no GASK")
		eq(sim:client(2):addon().Groups.state.stats.asks, 1)
		eq(sim:client(3):addon().Groups.state.stats.asks, 0)
	end)

	it("sends no group traffic and v0.8.0 behaviour with the switch off", function()
		local sim = Sim.new{ clients = 3, seed = 13 }
		sim:advance(40)
		sim:resetStats()
		falsy(sim:client(1):addon().Groups:Post(spec()))
		falsy(sim:client(2):addon().Groups:Ask())
		sim:advance(60)
		for i = 1, 3 do
			local st = sim:client(i):addon().Transport:Stats()
			eq(sim:client(i):addon().Store:Count("groups"), 0)
			isNil(st.sentByType and (st.sentByType.GASK or st.sentByType.GAPP))
		end
	end)
end)

describe("the traffic budget (SPEC-13 §6.8, SPEC-02 §4)", function()
	it("50 clients with 50 open listings, rewrites, applications and GASK stay inside the limits", function()
		local N, OFFICERS = 50, { 1, 11, 21, 31, 41 }
		local sim = Sim.new{ clients = N, officers = OFFICERS, setup = enabled, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42 }
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		sim:advance(60)
		local ids, rewrites, queueMax = {}, {}, 0
		local function postFor(i)
			local c = sim:client(i)
			local rec = c:addon().Groups:Post(spec({ note = "listing of client " .. i, meet = "the gate of the city" }))
			if rec then ids[i], rewrites[i] = rec.id, 0 end
		end
		for i = 1, N do postFor(i) sim:advance(1) end
		local function sampleQueue()
			for _, c in ipairs(sim.clients) do
				if c.online then queueMax = math.max(queueMax, c:addon().Transport:Pending()) end
			end
		end

		-- the cost of one GASK with 50 open listings, for the whole guild (measured without loss: a lost answer would only
		-- make it look cheaper; the churn below has the 1% loss again)
		sim:advance(30)
		sim:setLoss(0)
		sim:resetStats()
		local late = sim:client(N)
		late:addon().Groups.state.askedAt = nil
		for id in pairs(late:addon().Store:Records("groups")) do late:addon().Store:Records("groups")[id] = nil end
		truthy(late:addon().Groups:Ask())
		sim:advance(15)
		local ask = sim:stats()
		local held = 0
		for _, rec in pairs(late:addon().Store:Records("groups")) do if late:addon().Groups:Status(rec) == "open" then held = held + 1 end end
		eq(held, N - 1, "every other open listing came back")
		sim:setLoss(0.01)

		-- 45 minutes: each listing rewritten 3 times, 20 applications a minute in the guild, each client asks once, logins
		-- and logouts (a leader who comes back finds its listing closed and posts another)
		sim:resetStats()
		local asked = {}
		for minute = 1, 45 do
			for _ = 1, 20 do
				local who, target = 1 + math.floor(rand() * N), 1 + math.floor(rand() * N)
				local c = sim:client(who)
				if who ~= target and c.online and ids[target] then
					local role = ({ "t", "h", "d" })[1 + math.floor(rand() * 3)]
					c:addon().Groups:Apply(ids[target], role)
				end
			end
			for i = 1, N do
				local c = sim:client(i)
				if c.online then
					if ids[i] and rewrites[i] < 3 and rand() < 0.07 then
						rewrites[i] = rewrites[i] + 1
						c:addon().Groups:Update(ids[i], { note = "rewrite " .. rewrites[i] })
					end
					if not asked[i] and rand() < 0.05 then
						asked[i] = true
						c:addon().Groups.state.askedAt = nil
						c:addon().Groups:Ask()
					end
					if rand() < 0.01 then c:logout() end
				elseif rand() < 0.3 then
					c:login()
					postFor(i)
				end
			end
			for _ = 1, 6 do
				sim:advance(10)
				sampleQueue()
			end
		end
		local churn = sim:stats()

		-- then the steady state: 25 minutes with the listings open and nothing new
		for i = 1, N do if not sim:client(i).online then sim:client(i):login() postFor(i) end end
		sim:advance(120)
		sim:resetStats()
		sim:advance(25 * 60)
		local steady = sim:stats()

		T.log(("groups: one GASK %.1f KB for the guild; churn %.0f B/min average, %.0f busiest; steady %.0f / %.0f B/min; queue at most %d"):format(
			ask.sent.bytes / 1024, churn.avg.bytesPerMinute, churn.max.bytesPerMinute, steady.avg.bytesPerMinute,
			steady.max.bytesPerMinute, queueMax))
		truthy(ask.sent.bytes <= 16 * 1024, "one GASK with 50 open listings " .. ask.sent.bytes)
		truthy(churn.avg.bytesPerMinute <= 400, "churn average " .. churn.avg.bytesPerMinute)
		truthy(churn.max.bytesPerMinute <= 2048, "churn busiest client " .. churn.max.bytesPerMinute)
		truthy(steady.avg.bytesPerMinute <= 100, "steady average " .. steady.avg.bytesPerMinute)
		truthy(steady.max.bytesPerMinute <= 200, "steady busiest client " .. steady.max.bytesPerMinute)
		truthy(queueMax <= 100, "transport queue " .. queueMax)
		local quarantined = 0
		for _, c in ipairs(sim.clients) do
			if c.online then quarantined = quarantined + (c:addon().Sync.state.stats.quarantined or 0) + (c:addon().Transport:Stats().quarantined or 0) end
		end
		eq(quarantined, 0, "no honest client is put in quarantine")
	end)
end)

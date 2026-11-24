-- The observed timeline (M8.2; SPEC-12 §2, ADR 0023): what an officer's client sees change in the roster, the events it
-- writes, two observers of one change, that nothing is deleted for its age, who sees it, and that nothing leaves the computer before the officer
-- channel is proven (S5). The network part runs in the simulator.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function T() return AzerothAccord.Timeline end
local function Tr() return AzerothAccord.Transport end
local function Sy() return AzerothAccord.Sync end
local function Codec() return AzerothAccord.Codec end

local ME = "Player-1-0000A001"
local OFF, OFF2, MEMBER = "Player-1-000000FF", "Player-1-000000FE", "Player-1-00000BAD"
local function g(i) return ("Player-1-%08X"):format(0x5000 + i) end
local DAY = 86400

local function members(n, extra)
	local list = {}
	for i = 1, n do
		list[i] = { name = "M" .. i, level = 40 + i % 20, class = "MAGE", rank = 3, guid = g(i), note = i == 1 and "raider" or "" }
	end
	for _, m in ipairs(extra or {}) do list[#list + 1] = m end
	return list
end

-- The player is an officer (rank 1) unless said otherwise; ranks 0 and 1 listen to the officer chat.
local function guild(n, myRank, extra)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 1, members = members(n or 6, extra or {
		{ name = "Officer", rank = 1, guid = OFF }, { name = "Officer2", rank = 1, guid = OFF2 }, { name = "Plain", rank = 3, guid = MEMBER },
	}) }
	if A() then A().Role:Refresh() end   -- before the boot the addon is not loaded yet: the boot computes the role
end

local function row(guid) for _, m in ipairs(Mock.guild.members) do if m.guid == guid then return m end end end
local function pend() local O = A().Officer:Peek() return O and O.pend or {} end
local function eventsOf(guid) return T():Events(guid) end

-- Moves the clock `seconds` forward (both clocks, no timers: the tests flush by hand).
local function later(seconds) Mock.StepClock(seconds) end

-- One event as an observer would have written it.
local function ev(k, guid, a, b, fields)
	local e = { k = k, g = guid, n = "M1", a = a, b = b }
	for key, v in pairs(fields or {}) do e[key] = v end
	return e
end

-- A record of the set as the observer `who` would have stored it.
local function record(who, day, part, list, extra)
	local rec = { id = who .. ":" .. day .. ":" .. (part or 1), author = who, rev = 1, time = GetServerTime(), observer = who, day = day, ev = list }
	for k, v in pairs(extra or {}) do rec[k] = v end
	return rec
end

local function dayOf(t) return T().DayOf(t) end

describe("TL-01..TL-03: what the client observes", function()
	before_boot(function() guild() end)

	it("takes the first complete read as the base and makes no event (TL-02)", function()
		local r, n = T():Read()
		eq(r, "base"); eq(n, 0)
		eq(#pend(), 0)
		truthy(A().Officer:Peek().snap.m[g(1)])
		eq(T():Read(), "applied", "the second read compares: nothing changed")
		eq(#pend(), 0)
	end)

	it("sees a join, a leave, a rank, a level and a public note change, with the interval of the reads", function()
		T():Read()
		local base = GetServerTime()
		later(600)
		local oldLevel = row(g(2)).level
		row(g(2)).level = 59
		row(g(3)).rank = 2
		row(g(1)).note = "main tank"
		table.remove(Mock.guild.members, 4)                       -- M4 leaves
		table.insert(Mock.guild.members, { name = "Newbie", level = 12, class = "ROGUE", rank = 4, guid = g(50) })
		local r, n = T():Read()
		eq(r, "applied"); eq(n, 5)
		eq(T():Flush(true), 5)
		local by = {}
		for _, e in ipairs(T():All()) do by[e.k] = e end
		eq(by.level.f, oldLevel); eq(by.level.t, 59)
		eq(by.rank.f, 3); eq(by.rank.t, 2); eq(by.rank.fn, "Member"); eq(by.rank.tn, "Veteran")
		eq(by.note.f, "raider"); eq(by.note.t, "main tank")
		eq(by.leave.g, g(4)); eq(by.join.g, g(50)); eq(by.join.n, "Newbie"); eq(by.join.r, 4)
		for _, e in pairs(by) do eq(e.a, base); eq(e.b, base + 600); eq(#e.observers, 1); eq(e.observers[1].guid, ME) end
	end)

	it("does not make an event of a renamed character (same GUID)", function()
		T():Read()
		later(60)
		row(g(2)).name = "Renamed"
		eq(T():Read(), "applied"); eq(#pend(), 0)
		eq(A().Officer:Peek().snap.m[g(2)].n, "Renamed")
	end)

	it("changes nothing on an incomplete read (TL-01)", function()
		T():Read()
		local snap = A().Officer:Peek().snap
		later(60)
		row(g(2)).level = 70
		row(g(5)).guid = nil                                       -- a row without a GUID
		eq(T():Read(), "incomplete")
		eq(A().Officer:Peek().snap, snap, "the snapshot stays")
		eq(#pend(), 0)
		eq(T():Observe({}, GetServerTime(), false), "incomplete")
	end)

	it("believes a mass departure only when a second read 120 s later says the same (TL-04)", function()
		guild(30)
		T():Read()
		later(300)
		for _ = 1, 15 do table.remove(Mock.guild.members, 1) end   -- 15 of 33 leave at once
		eq(T():Read(), "held"); eq(#pend(), 0)
		eq(A().Officer:Peek().snap.m[g(1)] ~= nil, true, "the snapshot is kept")
		later(60)
		eq(T():Read(), "held", "too soon")
		later(70)
		local r, n = T():Read()
		eq(r, "applied"); eq(n, 15)
		eq(A().Officer:Peek().snap.m[g(1)], nil)
	end)

	it("starts the wait again when the second read does not say the same", function()
		guild(30)
		T():Read()
		later(300)
		for _ = 1, 15 do table.remove(Mock.guild.members, 1) end
		eq(T():Read(), "held")
		later(200)
		table.remove(Mock.guild.members, 1)                         -- one more is gone: another set of departures
		eq(T():Read(), "held", "a different set of departures is not confirmed")
		later(130)
		eq(T():Read(), "applied")
	end)

	it("does not watch from a member's client or in demo mode", function()
		guild(6, 3)
		eq(T():Read(), "off")
		eq(A().Officer:Peek(), nil, "a member's client stores nothing")
	end)
end)

describe("TL-05, TL-06: records and grouping", function()
	before_boot(function() guild() end)

	local function levelEvents(n, first)
		local list = {}
		for i = 1, n do list[i] = ev("level", g(1 + i % 5), 1000, 2000 + i, { f = 10, t = 11, n = "L" .. i }) end
		return list
	end

	it("keeps one level event per character and day, with the first old level and the last new one (TL-06)", function()
		T():Read()
		later(100)
		row(g(2)).level = row(g(2)).level + 3
		local old = A().Officer:Peek().snap.m[g(2)].l
		T():Read()
		later(400)
		row(g(2)).level = row(g(2)).level + 4
		T():Read()
		eq(#pend(), 1, "one waiting event")
		T():Flush(true)
		later(1000)
		row(g(2)).level = row(g(2)).level + 1
		T():Read()
		T():Flush(true)
		local list = eventsOf(g(2))
		eq(#list, 1); eq(list[1].f, old); eq(list[1].t, old + 8)
	end)

	it("opens the next part at 60 events and loses the events beyond four parts (TL-05)", function()
		T():Read()
		local t0 = GetServerTime()
		local list = {}
		for i = 1, 250 do list[i] = ev("rank", g(1 + i % 5), t0, t0 + 10, { f = i % 18, t = (i % 18) + 1, n = "R" .. i }) end
		-- distinct (f, t, g) so none is a duplicate of another
		for i, e in ipairs(list) do e.g = g(i) e.f = i % 19 e.t = (i + 1) % 19 end
		eq(T():Write(list), 240)
		local day = dayOf(t0 + 10)
		for p = 1, 4 do
			local rec = S():Get("timeline", ME .. ":" .. day .. ":" .. p)
			truthy(rec, "part " .. p)
			eq(#rec.ev, 60)
			truthy(A().Config.EstimateSize(rec) <= S().SETS.timeline.maxBytes)
		end
		isNil(S():Get("timeline", ME .. ":" .. day .. ":5"))
		eq(T().state.stats.dropped, 10)
	end)

	it("stores a record that the owner rule accepts, for every kind", function()
		local t0 = GetServerTime()
		local list = {
			ev("join", g(1), t0, t0 + 1, { r = 3, rn = "Member", l = 20 }), ev("leave", g(2), t0, t0 + 1, { rn = "Member", l = 20 }),
			ev("rank", g(3), t0, t0 + 1, { f = 3, t = 2, fn = "Member", tn = "Veteran" }), ev("level", g(4), t0, t0 + 1, { f = 10, t = 12 }),
			ev("note", g(5), t0, t0 + 1, { f = "", t = "x" }),
		}
		eq(T():Write(list), 5)
		eq(S():Count("timeline"), 1)
		eq(T().state.stats.invalid, 0)
	end)
end)

describe("TL-08, TL-09: two observers of the same change", function()
	before_boot(function() guild() end)

	local t0 = 1767225600 + 3 * DAY

	it("merges the same change seen over a narrow and a wide interval into one event with both observers", function()
		local a = { ev = ev("rank", g(1), t0 - 600, t0, { f = 3, t = 2 }), obs = OFF }
		local b = { ev = ev("rank", g(1), t0 - 2 * DAY, t0 + 3 * 3600, { f = 3, t = 2 }), obs = OFF2 }
		local out = T().Merge({ b, a })
		eq(#out, 1)
		eq(out[1].a, t0 - 600, "the narrowest interval: the latest a"); eq(out[1].b, t0, "and the earliest b")
		eq(#out[1].observers, 2); eq(out[1].observers[1].guid, OFF, "the older b first"); eq(out[1].observers[2].guid, OFF2)
	end)

	it("keeps apart different values, different characters, and intervals more than 600 s apart", function()
		local function one(fields, a, b, obs) return { ev = ev(fields.k or "rank", fields.g or g(1), a, b, fields), obs = obs } end
		eq(#T().Merge({ one({ f = 3, t = 2 }, t0 - 10, t0, OFF), one({ f = 3, t = 1 }, t0 - 10, t0, OFF2) }), 2)
		eq(#T().Merge({ one({ f = 3, t = 2 }, t0 - 10, t0, OFF), one({ f = 3, t = 2, g = g(2) }, t0 - 10, t0, OFF2) }), 2)
		eq(#T().Merge({ one({ f = 3, t = 2 }, t0 - 10, t0, OFF), one({ f = 3, t = 2 }, t0 + 700, t0 + 800, OFF2) }), 2)
		eq(#T().Merge({ one({ f = 3, t = 2 }, t0 - 10, t0, OFF), one({ f = 3, t = 2 }, t0 + 500, t0 + 800, OFF2) }), 1, "within the 300 s tolerance on each side")
	end)

	it("counts a level change by its new level only, and keeps the lowest old level", function()
		local one = function(f, obs, a, b) return { ev = ev("level", g(1), a, b, { f = f, t = 27 }), obs = obs } end
		local out = T().Merge({ one(20, OFF, t0 - 100, t0), one(22, OFF2, t0 - 50, t0 + 20) })
		eq(#out, 1); eq(out[1].f, 20); eq(out[1].t, 27)
	end)

	it("never counts one observer twice, and joins the closest of several", function()
		local e1 = { ev = ev("join", g(1), t0 - 100, t0, {}), obs = OFF }
		local e2 = { ev = ev("join", g(1), t0 - 100, t0 + 500, {}), obs = OFF }   -- the same observer again: a second event
		eq(#T().Merge({ e1, e2 }), 2)
		local wide = { ev = ev("leave", g(1), t0 - DAY, t0 + 1000, {}), obs = OFF2 }
		local n1 = { ev = ev("leave", g(1), t0 - 50, t0, {}), obs = OFF }
		local n2 = { ev = ev("leave", g(1), t0 + 2000, t0 + 2050, {}), obs = MEMBER }
		local out = T().Merge({ n1, n2, wide })
		eq(#out, 2, "the wide interval joins one of them, not both")
	end)

	it("writes an event only once when another observer's record already holds it (confirmed)", function()
		local day = dayOf(t0)
		S():Records("timeline")[OFF .. ":" .. day .. ":1"] = record(OFF, day, 1, { ev("rank", g(1), t0 - 300, t0, { f = 3, t = 2 }) })
		later(3 * DAY + 100)
		local mine = ev("rank", g(1), t0 - 2 * DAY, t0 + 3600, { f = 3, t = 2 })
		eq(T():Write({ mine }), 0)
		eq(T().state.stats.confirmed, 1)
		isNil(S():Get("timeline", ME .. ":" .. day .. ":1"))
		eq(#eventsOf(g(1)), 1)
		local other = ev("rank", g(1), t0 - 300, t0, { f = 2, t = 1 })
		eq(T():Write({ other }), 1, "another change of the same character is a new event")
		eq(#eventsOf(g(1)), 2)
	end)

	it("two clients that observe the same change leave one event, whoever wrote first (simulator, channel proven)", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2, 3 }, seed = 5 }
		sim:advance(40)
		local function observe(i, a, b)
			local c = sim:client(i):addon()
			c.Timeline:Queue({ { k = "rank", g = Sim.guidOf(4), n = "Member", a = a, b = b, f = 3, t = 2 } }, b)
		end
		local now = sim:client(1).E.GetServerTime()
		observe(1, now - 60, now)
		sim:advance(20)
		observe(2, now - 3 * DAY, now + 20)
		sim:advance(400)
		for i = 1, 3 do
			local a = sim:client(i):addon()
			a.Timeline:Flush(true)
		end
		sim:advance(700)
		for i = 1, 3 do
			local list = sim:client(i):addon().Timeline:Events(Sim.guidOf(4))
			eq(#list, 1, "client " .. i)
			eq(#list[1].observers >= 1, true)
		end
	end)
end)

describe("TL-07: kept forever (the owner's answer to SPEC-10 Q14)", function()
	before_boot(function() guild() end)

	local function put(daysOld)
		local t = GetServerTime() - daysOld * DAY
		local day = dayOf(t)
		local e = ev("note", g(1), t - 100, t, { f = "old text", t = "new text " .. daysOld })
		local rec = record(OFF, day, 1, { e })
		S():Records("timeline")[rec.id] = rec
		return rec
	end

	it("does not delete a record for its age, not at day 365, 366 or years later", function()
		local list = { put(0), put(365), put(366), put(1000), put(3000) }
		eq(S():Prune(), 0)
		for _, r in ipairs(list) do truthy(S():Get("timeline", r.id)) end
		later(5 * 365 * DAY)
		eq(S():Prune(), 0, "five more years change nothing")
		eq(S():Count("timeline"), 5)
		local events = eventsOf(g(1))
		eq(#events, 5, "and every event is still read, with the old and the new text of the note")
		eq(events[#events].f, "old text")
	end)

	it("accepts an old record from an officer when a new officer is brought up to date", function()
		local t = GetServerTime() - 2000 * DAY
		local rec = record(OFF, dayOf(t), 1, { ev("level", g(1), t - 5, t, { f = 1, t = 2 }) })
		eq(S():Receive("timeline", { rec }, "Officer", "OFFICER"), 1)
		truthy(S():Get("timeline", rec.id))
	end)

	it("keeps who left, however long ago", function()
		T():Read()
		local O = A().Officer:Peek()
		O.gone = { [g(60)] = GetServerTime() - 2000 * DAY }
		later(10 * 365 * DAY)
		A().Store:Prune()
		truthy(O.gone[g(60)])
	end)

	it("time alone removes nothing, even twenty years on (only OFF-10 does)", function()
		put(100)
		eq(S():Count("timeline"), 1)
		later(20 * 365 * DAY)
		A().Store:Prune()
		eq(S():Count("timeline"), 1)
	end)

	it("measures the size of a year of a big guild (SPEC-10 R6)", function()
		-- 1000 members, 365 days, 40 events a day seen by one observer
		local list = {}
		local now = GetServerTime()
		local total = 0
		for d = 364, 0, -1 do
			list = {}
			for i = 1, 40 do
				local t = now - d * DAY + i * 600
				local kind = i % 4
				local guid = g(1 + (d * 40 + i) % 1000)
				if kind == 0 then list[i] = ev("level", guid, t - 3000, t, { f = 30 + i % 30, t = 31 + i % 30 })
				elseif kind == 1 then list[i] = ev("note", guid, t - 3000, t, { f = "old note " .. i, t = "new note " .. i })
				elseif kind == 2 then list[i] = ev("rank", guid, t - 3000, t, { f = 3, t = 2, fn = "Member", tn = "Veteran" })
				else list[i] = ev("join", guid, t - 3000, t, { r = 4, rn = "Initiate", l = 12 + i }) end
				-- distinct values so none is a duplicate
				if list[i].k == "level" then list[i].f = 1 + (d * 40 + i) % 100 list[i].t = list[i].f + 1 end
				list[i].n = "Name" .. i
			end
			total = total + T():Write(list)
		end
		eq(total >= 14000, true, "the events were stored")
		local bytes = A().Config.EstimateSize(S():Records("timeline"))
		print(("[R6] timeline, 1 observer, 40 events/day, 365 days: %d events, %d records, about %.0f KB"):format(total, S():Count("timeline"), bytes / 1024))
		truthy(bytes < 8 * 1024 * 1024, "well under the limit of the saved variables")
	end)

	it("keeps a snapshot of a guild of 1000 members that is small next to the timeline", function()
		local rows = {}
		for i = 1, 1000 do
			rows[i] = { guid = g(i), name = "Member" .. i, rankIndex = i % 5, rankName = "Rank" .. i % 5, level = 20 + i % 50, note = i % 3 == 0 and "alt of Someone" or "" }
		end
		eq(T():Observe(rows, GetServerTime(), true), "base")
		local bytes = A().Config.EstimateSize(A().Officer:Peek().snap)
		truthy(bytes < 400 * 1024, "the snapshot of 1000 members: " .. bytes)
	end)
end)

describe("OFF-01..OFF-03: who may hold and send these records", function()
	before_boot(function() guild() end)

	local function rec(who, k)
		local t = GetServerTime()
		return record(who, dayOf(t), 1, { ev("level", g(1), t - 60, t, { f = 10, t = 11 }) })
	end

	it("an officer accepts a record from an officer and keeps it after the author was demoted (authorAny)", function()
		local r = rec(OFF2)
		Mock.guild.members[2].rank = 3                                 -- Officer2 is a plain member now
		A().Store:RosterChanged()
		eq(S():Receive("timeline", { r }, "Officer", "OFFICER"), 1)
		truthy(S():Get("timeline", r.id))
	end)

	it("refuses a record whose sender is not an officer", function()
		local r = rec(MEMBER)
		local ok, why = S():Accept("timeline", r, { sender = "Plain" })
		eq(ok, false); eq(why, "authority")
	end)

	it("refuses a record that does not follow the owner rule (observer, id, day, part, events)", function()
		local good = rec(OFF)
		local function bad(change)
			local r = S().Copy(good)
			change(r)
			local ok, why = S():Accept("timeline", r, { sender = "Officer" })
			eq(ok, false, "accepted a bad record") eq(why, "owner")
		end
		bad(function(r) r.observer = OFF2 end)
		bad(function(r) r.id = OFF .. ":" .. r.day .. ":5" end)
		bad(function(r) r.id = OFF .. ":" .. (r.day - 1) .. ":1" end)
		bad(function(r) r.ev[1].k = "kick" end)
		bad(function(r) r.ev[1].t = "x" end)
		bad(function(r) r.ev[1].a, r.ev[1].b = r.ev[1].b + 1, r.ev[1].b end)
		bad(function(r) r.ev[1].b = r.ev[1].b - 2 * DAY end)
		bad(function(r) r.ev[1].n = "" end)
		bad(function(r) r.ev[1].extra = 1 end)
		bad(function(r) r.extra = 1 end)
		bad(function(r) r.ev = { n = r.ev[1] } end)
		bad(function(r) for i = 1, 61 do r.ev[i] = S().Copy(r.ev[1]) end end)
	end)

	it("refuses every record when the client is a member's (OFF-01), even from an officer", function()
		guild(6, 3)
		local r = rec(OFF)
		local ok, why = S():Accept("timeline", r, { sender = "Officer" })
		eq(ok, false); eq(why, "restricted")
		eq(S():Count("timeline"), 0)
	end)

	it("never takes such a record from GUILD (OFF-04)", function()
		local r = rec(OFF)
		Tr():OnReceive(assert(Codec():Encode("REC", { s = "timeline", r = { r } })), "GUILD", "Officer")
		eq(S():Count("timeline"), 0)
		Tr():OnReceive(assert(Codec():Encode("REC", { s = "timeline", r = { r } })), "OFFICER", "Officer")
		eq(S():Count("timeline"), 1)
	end)
end)

describe("who sees the timeline (the answer proposed for SPEC-10 Q13)", function()
	before_boot(function() guild() end)

	local function seed()
		local t = GetServerTime()
		local r = record(OFF, dayOf(t), 1, { ev("join", g(1), t - 60, t, { r = 3, rn = "Member", l = 20 }) })
		S():Records("timeline")[r.id] = r
	end

	it("gives an officer the events and a section on the member card", function()
		seed()
		eq(#eventsOf(g(1)), 1)
		A().Roster:MarkDirty()
		local d = A().MemberCard.Describe(A().Roster:ByGUID(g(1)))
		local found
		for _, s in ipairs(d.sections) do if s.id == "timeline" then found = s end end
		truthy(found, "the section")
		eq(found.title, "Timeline")
		contains(found.lines[2].text, "joined the guild")
		contains(found.lines[2].text, "M1")
	end)

	it("gives a member nothing: no events, no section, even with a record in the store", function()
		seed()
		guild(6, 3)
		A().Roster:MarkDirty()
		eq(#eventsOf(g(1)), 0)
		eq(#T():All(), 0)
		local d = A().MemberCard.Describe(A().Roster:ByGUID(g(1)))
		for _, s in ipairs(d.sections) do ne(s.id, "timeline") end
	end)

	it("follows the one table that decides it", function()
		seed()
		guild(6, 3)
		eq(#eventsOf(g(1)), 0)
		A().Officer.VISIBLE_TO.timeline = "members"
		eq(#eventsOf(g(1)), 1, "when the owner answers Q13 with members, one line is enough")
		A().Officer.VISIBLE_TO.timeline = "nobody"
		eq(#eventsOf(g(1)), 0)
		A().Officer.VISIBLE_TO.timeline = "officers"
	end)

	it("lists the events of the whole account, newest first, ten at a time, with Show all", function()
		local t = GetServerTime()
		local list = {}
		for i = 1, 14 do list[i] = ev("level", g(1), t - 1000 - i * 100, t - i * 100, { f = i, t = i + 1 }) end
		local r = record(OFF, dayOf(t), 1, list)
		S():Records("timeline")[r.id] = r
		local d = A().TimelineCard.Describe({ guid = g(1) })
		eq(d.count, 14)
		local texts = {}
		for _, l in ipairs(d.lines) do texts[#texts + 1] = l.text end
		eq(texts[1], "Member since: unknown")
		contains(texts[2], "level 1 → 2")                              -- the newest first
		eq(#texts, 1 + 10 + 1 + 2, "ten lines, Show all, the channel state and the note")
		eq(texts[12], "Show all (14)")
		d.lines[12].onClick()
		eq(#A().TimelineCard.Describe({ guid = g(1) }).lines, 1 + 14 + 1 + 2)
		A().TimelineCard.expanded = nil
	end)

	it("says the date of the oldest join and the interval of a long wait", function()
		local t = GetServerTime()
		local r = record(OFF, dayOf(t), 1, { ev("join", g(1), t - 5 * DAY, t - 100, { r = 3 }), ev("level", g(1), t - 3 * DAY, t, { f = 5, t = 6 }) })
		S():Records("timeline")[r.id] = r
		local d = A().TimelineCard.Describe({ guid = g(1) })
		eq(d.lines[1].text, "Member since " .. date("!%Y-%m-%d", t - 100))
		local longLine = d.lines[2].text
		contains(longLine, "between " .. date("!%Y-%m-%d", t - 3 * DAY) .. " and " .. date("!%Y-%m-%d", t))
	end)

	it("cleans the texts of a note and never shows a GUID", function()
		local t = GetServerTime()
		local r = record("Player-1-000000EE", dayOf(t), 1, { ev("note", g(1), t - 10, t, { f = "a|cffff0000b", t = "ok" }) })
		S():Records("timeline")[r.id] = r
		local d = A().TimelineCard.Describe({ guid = g(1) })
		contains(d.lines[2].text, "a||cffff0000b")
		for _, l in ipairs(d.lines) do
			falsy(l.text:find("Player%-"))
			for _, tip in ipairs(l.tip or {}) do falsy(tip:find("Player%-")) end
		end
		local tip = d.lines[2].tip
		contains(tip[2], "a former officer")
	end)
end)

describe("OFF-10: a demoted officer loses the officer data", function()
	before_boot(function() guild() end)

	-- the player's own character is in the account list, as a login registers it
	local function registered() A().Accounts:RegisterSelf() end

	it("deletes the snapshot and the timeline when no character of the account is an officer, and says so once", function()
		registered()
		T():Read()
		local t = GetServerTime()
		local r = record(OFF, dayOf(t), 1, { ev("join", g(1), t - 60, t, { r = 3 }) })
		S():Records("timeline")[r.id] = r
		truthy(A().Officer:Peek().snap)
		Mock.ClearOutput()
		guild(6, 3)                                                  -- the player is a member now: the change of role does it
		eq(S():Count("timeline"), 0); isNil(A().Officer:Peek())
		matches(table.concat(Mock.PlainOutput(), " "), "no longer an officer")
		eq(A().Officer:CheckDemotion(), false, "nothing to remove the second time")
	end)

	it("also does it at login, from the roster, when the data was left behind", function()
		registered()
		guild(6, 3)
		local t = GetServerTime()
		local r = record(OFF, dayOf(t), 1, { ev("join", g(1), t - 60, t, { r = 3 }) })
		S():Records("timeline")[r.id] = r
		A().Roster:MarkDirty()
		eq(A().Officer:CheckDemotion(), true)
		eq(S():Count("timeline"), 0)
	end)

	it("waits while the rank cannot be read, and while an officer character of the account remains", function()
		registered()
		T():Read()
		local real = A().Compat.Guild.RankIsOfficer
		A().Compat.Guild.RankIsOfficer = function() return nil end
		guild(6, 3)
		A().Roster:MarkDirty()
		eq(A().Officer:CheckDemotion(), false)
		truthy(A().Officer:Peek(), "the client does not say the rank yet: wait")
		A().Compat.Guild.RankIsOfficer = real
		eq(A().Officer:CheckDemotion(), true, "once it does, the data goes")
		isNil(A().Officer:Peek())
	end)
end)

describe("OFF-05, OFF-07: nothing travels before the officer channel is proven", function()
	local function capture()
		local sent = {}
		Tr().wire = function(prio, txt, dist, target, done)
			local msg = Codec():Decode(txt)
			sent[#sent + 1] = { dist = dist, target = target, msg = msg }
			done(0)
		end
		return sent
	end
	local function typesOf(sent, t, set)
		local out = {}
		for _, s in ipairs(sent) do if s.msg and s.msg.t == t and (set == nil or s.msg.s == set) then out[#out + 1] = s end end
		return out
	end

	before_boot(function() guild() end)

	it("keeps the records on this computer while the channel is unproven, and sends only the summary", function()
		local sent = capture()
		A().Compat:SetFeature("officerAddonChannel", "unknown", "test")
		eq(A().Officer.ChannelProven(), false)
		local t = GetServerTime()
		eq(T():Write({ ev("level", g(1), t - 60, t, { f = 10, t = 11 }) }), 1)
		Mock.Advance(30, 0.5)
		eq(#typesOf(sent, "REC", "timeline"), 0, "no REC of the timeline, on no distribution")
		Sy():SendHello()
		Mock.Advance(10, 0.5)
		local o = typesOf(sent, "OHELLO")[1]
		truthy(o, "the summary goes")
		eq(o.dist, "OFFICER")
		truthy(#o.msg.m >= Sy().ENTRY, "m names the group")
		eq(#o.msg.s, 0, "the bank's summary is not mixed with it")
		for _, s in ipairs(sent) do
			if s.msg and s.msg.t == "HELLO" then eq(#s.msg.s, 0, "nothing of it in the HELLO on GUILD") end
		end
	end)

	it("sends the record on OFFICER, never on GUILD, once the channel is proven, and at most every ten minutes", function()
		local sent = capture()
		A().Compat:SetFeature("officerAddonChannel", "available", "test")
		local t = GetServerTime()
		T():Write({ ev("level", g(1), t - 60, t, { f = 10, t = 11 }) })
		Mock.Advance(10, 0.5)
		local first = typesOf(sent, "REC", "timeline")
		eq(#first, 1); eq(first[1].dist, "OFFICER")
		T():Write({ ev("rank", g(2), t - 60, t, { f = 3, t = 2 }) })
		Mock.Advance(60, 0.5)
		eq(#typesOf(sent, "REC", "timeline"), 1, "the second change waits for the ten minutes")
		Mock.Advance(560, 1)
		local all = typesOf(sent, "REC", "timeline")
		eq(#all, 2); eq(all[2].dist, "OFFICER")
		eq(#all[2].msg.r, 1); eq(#all[2].msg.r[1].ev, 2, "the whole record of the day")
		for _, s in ipairs(sent) do
			if s.msg and s.msg.t == "REC" and s.msg.s == "timeline" then ne(s.dist, "GUILD") end
		end
	end)

	it("the transport refuses such a message for GUILD, for a member, and when the target was demoted meanwhile", function()
		local sent = capture()
		local rec = { s = "timeline", r = {} }
		local item, why = Tr():Send("GUILD", { t = "REC", s = "timeline", r = {} }, { officerOnly = true })
		isNil(item); eq(why, "officerOnly")
		item, why = Tr():Send("WHISPER", { t = "REC", s = "timeline", r = {} }, { officerOnly = true, target = "Plain" })
		isNil(item); eq(why, "officerOnly")
		truthy(Tr():Send("WHISPER", { t = "REC", s = "timeline", r = {} }, { officerOnly = true, target = "Officer" }))
		-- demoted while it waits
		for _, m in ipairs(Mock.guild.members) do if m.name == "Officer" then m.rank = 3 end end
		A().Store:RosterChanged()
		Tr().Pass()
		Mock.Advance(2, 0.5)
		eq(#typesOf(sent, "REC", "timeline"), 0)
		eq(Tr():Stats().droppedBy.officerOnly, 3)
		-- and a waiting message is never saved at logout
		truthy(Tr():Send("OFFICER", { t = "REC", s = "timeline", r = {} }, { officerOnly = true }))
		Mock.Advance(0, 0)
		eq(Tr():SaveQueue(), 0)
	end)
end)

describe("OFF-04..OFF-09: officers share the timeline among themselves (simulator)", function()
	local function stored(sim, i) return sim:client(i):addon().Store:Count("timeline") end
	local function write(sim, i, n, who)
		local c = sim:client(i):addon()
		local t = sim:client(i).E.GetServerTime()
		local list = {}
		for k = 1, n do list[k] = { k = "rank", g = Sim.guidOf(4 + k), n = "Sim", a = t - 100 - k, b = t, f = 3, t = 2 } end
		return c.Timeline:Write(list)
	end

	it("travels on OFFICER to the other officers and to nobody else", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2, 3 }, seed = 11 }
		sim:advance(60)
		eq(write(sim, 1, 1), 1)
		sim:advance(30)
		eq(stored(sim, 1), 1); eq(stored(sim, 2), 1); eq(stored(sim, 3), 1)
		eq(stored(sim, 4), 0, "a member never receives it"); eq(stored(sim, 5), 0)
		local m = sim:client(4)
		eq(#m:addon().Timeline:All(), 0)
	end)

	it("stays on the writer's computer when OFFICER carries nothing (S5 failing), whatever the time", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2, 3 }, officerChannel = false, seed = 12 }
		sim:advance(60)
		eq(write(sim, 1, 1), 1)
		sim:advance(2400)
		eq(stored(sim, 1), 1)
		eq(stored(sim, 2), 0); eq(stored(sim, 3), 0); eq(stored(sim, 4), 0)
		eq(sim:client(1):addon().Officer.ChannelProven(), false)
		local st = sim:client(1):addon().Transport:Stats()
		eq(st.sentBy.GUILD > 0, true, "the guild sync itself works")
		for i = 2, 4 do eq(sim:client(i):addon().Store:Count("timeline"), 0) end
	end)

	it("a new officer is brought up to date by the designated officer, by whisper, after its OHELLO", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2, 3 }, offline = { 3 }, seed = 13 }
		sim:advance(60)
		write(sim, 1, 3)
		sim:advance(60)
		eq(stored(sim, 2), 1)
		eq(stored(sim, 3), 0)
		sim:client(3):login()
		sim:advance(400)
		eq(stored(sim, 3), 1, "the missing record arrived after the summary was compared")
		eq(stored(sim, 4), 0)
	end)
end)

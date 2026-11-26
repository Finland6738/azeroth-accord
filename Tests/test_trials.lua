-- Trials (M12.3; SPEC-16 §4, TRI-01..TRI-05; SPEC-10 Q35): only officers write and receive them, a member refuses every
-- record (its own trial too); never on GUILD or by whisper to a member, only on this computer without S5; an extension
-- yes, a reopening or a shortening no ("locked"); one note per officer, only its author; the reminder on the end day,
-- once, also after a /reload and another login, and again after an extension; the row goes when the trial is closed; a
-- member who left the guild; OFF-10 deletes the trials; Passed and the queue of M8.4; the switch "recruit".
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function T() return AzerothAccord.Trials end
local function V() return AzerothAccord.TrialsView end
local function Tr() return AzerothAccord.Transport end
local function Sy() return AzerothAccord.Sync end
local function Codec() return AzerothAccord.Codec end

local ME = "Player-1-0000A001"
local BOB, ANN, OFF, MEMBER = "Player-1-00000B0B", "Player-1-00000A77", "Player-1-000000FF", "Player-1-00000BAD"
local DAY = 86400

local function roster(M, myRank)
	M.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Ann", level = 20, class = "DRUID", rank = 4, guid = ANN },
		{ name = "Officer", level = 60, class = "ROGUE", rank = 1, guid = OFF },
		{ name = "Plain", level = 60, class = "ROGUE", rank = 3, guid = MEMBER },
	} }
end

local function setup(myRank, features)
	return function(M)
		M.features = features or { recruit = true }
		roster(M, myRank)
	end
end

-- The player's rank changes (the role follows).
local function rank(r)
	Mock.guild.SetMyRank(r)
	A().Role:Refresh()
	A().Roster:MarkDirty()
end

local function today() return T().Today() end
local function dayAgo(n) return T().DayOfNumber(T().Number(today()) - n) end

-- A trial record as another officer's client would send it.
local function trial(char, start, days, fields)
	local s = T().Number(start)
	local r = { id = T().TrialId(char, start), author = OFF, rev = 1, time = GetServerTime(), char = char, start = start,
		days = days, ends = T().DayOfNumber(s + days), state = "open" }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

local function from(sender, dist) return { sender = sender or "Officer", dist = dist or "OFFICER" } end

local function trialNotices()
	local out = {}
	for _, e in ipairs(A().Notify:Entries()) do if e.module == "trials" then out[#out + 1] = e end end
	return out
end

local function trialRows()
	local out = {}
	for _, r in ipairs(A().Actions:Refresh()) do if r.provider == "trials" then out[#out + 1] = r end end
	return out
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

local function section(entry, id)
	for _, s in ipairs(A().MemberCard.Describe(entry).sections) do if s.id == id then return s end end
	return nil
end

describe("TRI-03: starting a trial", function()
	before_boot(setup())

	it("starts today for 14 days by default, from 1 to 60, at most 30 days back and 14 ahead", function()
		local rec, why = T():Start(BOB)
		truthy(rec, why)
		eq(rec.id, "T:" .. BOB .. ":" .. today())
		eq(rec.days, 14); eq(rec.state, "open")
		eq(T().Number(rec.ends) - T().Number(rec.start), 14)
		isNil(rec.closed)
		local _, w = T():Start(ANN, 0) eq(w, "days")
		_, w = T():Start(ANN, 61) eq(w, "days")
		_, w = T():Start(ANN, 2.5) eq(w, "days")
		_, w = T():Start(ANN, 10, dayAgo(31)) eq(w, "start")
		_, w = T():Start(ANN, 10, dayAgo(-15)) eq(w, "start")
		truthy(T():Start(ANN, 60, dayAgo(30)))
		_, w = T():Start("Player-1-00001234") eq(w, "unknown", "only a member of the roster")
		_, w = T():Start(BOB) eq(w, "exists")
	end)

	it("refuses a record of the wrong shape from another officer (owner)", function()
		local start = today()
		local bad = {
			trial(BOB, start, 0), trial(BOB, start, 61), trial(BOB, start, 14, { ends = start }),
			trial(BOB, start, 14, { ends = T().DayOfNumber(T().Number(start) + 121) }),
			trial(BOB, start, 14, { state = "reopened" }), trial(BOB, start, 14, { closed = start }),
			trial(BOB, start, 14, { state = "passed" }), trial(BOB, start, 14, { extra = 1 }),
			trial(BOB, start, 14, { char = ANN }),
		}
		for i, rec in ipairs(bad) do
			local ok, why = S():Accept("trials", rec, from())
			eq(ok, false, "record " .. i); eq(why, "owner", "record " .. i)
		end
		truthy(S():Accept("trials", trial(BOB, start, 14), from()))
		truthy(S():Accept("trials", trial(ANN, start, 14, { state = "failed", closed = start, rev = 2 }), from()))
	end)
end)

describe("TRI-01: only officers", function()
	before_boot(setup())

	it("an officer accepts trials only from an officer; a member's client refuses every record, its own trial too", function()
		local ok, why = S():Accept("trials", trial(BOB, today(), 14), from("Plain"))
		eq(ok, false); eq(why, "authority")
		truthy(S():Accept("trials", trial(BOB, today(), 14), from("Officer", "WHISPER")))
		rank(3)
		ok, why = S():Accept("trials", trial(ANN, today(), 14), from())
		eq(ok, false); eq(why, "restricted")
		-- the member on trial: the record about itself is refused as well
		Mock.player.guid = BOB
		ok, why = S():Accept("trials", trial(BOB, dayAgo(1), 14), from())
		eq(ok, false); eq(why, "restricted")
	end)

	it("a member cannot write, sees no trial, no page, no section and no row", function()
		truthy(T():Start(BOB, 5, dayAgo(1)))
		rank(3)
		Mock.StepClock(5 * DAY)
		local rec, why = T():Start(ANN)
		isNil(rec); eq(why, "officer")
		eq(#T():Of(BOB), 0)
		eq(#T():Rows().open, 0)
		isNil(section(A().Roster:ByGUID(BOB), "trial"))
		eq(#trialRows(), 0)
		A().Notify:Check()
		eq(#trialNotices(), 0)
		isNil(V():Open(T().TrialId(BOB, dayAgo(1))))
	end)
end)

describe("TRI-04: extensions and closings", function()
	before_boot(setup())

	it("extends up to 120 days from the start, closes once, and never reopens", function()
		local rec = T():Start(BOB, 14, dayAgo(10))
		local id = rec.id
		rec = T():Extend(id, 30)
		truthy(rec)
		eq(T().Number(rec.ends) - T().Number(rec.start), 44); eq(rec.days, 14)
		local _, why = T():Extend(id, 77) eq(why, "max")
		truthy(T():Extend(id, 76))
		_, why = T():Extend(id, 0) eq(why, "days")
		local closed = T():Close(id, "failed")
		eq(closed.state, "failed"); eq(closed.closed, today())
		_, why = T():Extend(id, 1) eq(why, "closed")
		_, why = T():Close(id, "passed") eq(why, "closed")
		_, why = T():Start(BOB, 14, dayAgo(10)) eq(why, "locked", "the same start again would reopen it")
		truthy(T():Start(BOB, 14), "a second trial starts from another day")
		eq(#T():Of(BOB), 2)
		eq(T():Of(BOB)[1].state, "open", "the open trial first")
	end)

	it("refuses a newer revision that reopens, shortens or changes the length (locked); an older one is only older", function()
		local start = dayAgo(5)
		truthy(S():Accept("trials", trial(BOB, start, 14, { ends = T().DayOfNumber(T().Number(start) + 20) }), from()))
		local ok, why = S():Accept("trials", trial(BOB, start, 14, { rev = 2 }), from())
		eq(ok, false); eq(why, "locked", "shorter")
		ok, why = S():Accept("trials", trial(BOB, start, 10, { rev = 2, ends = T().DayOfNumber(T().Number(start) + 20) }), from())
		eq(ok, false); eq(why, "locked", "another length")
		truthy(S():Accept("trials", trial(BOB, start, 14, { rev = 2, ends = T().DayOfNumber(T().Number(start) + 20),
			state = "passed", closed = today() }), from()))
		ok, why = S():Accept("trials", trial(BOB, start, 14, { rev = 3, ends = T().DayOfNumber(T().Number(start) + 20) }), from())
		eq(ok, false); eq(why, "locked", "reopened")
		ok, why = S():Accept("trials", trial(BOB, start, 14, { rev = 1 }), from())
		eq(ok, false); eq(why, "older")
		eq(S():Get("trials", T().TrialId(BOB, start)).state, "passed")
		-- a closed trial is kept for ever (Q35)
		Mock.StepClock(3650 * DAY)
		S():Prune()
		truthy(S():Get("trials", T().TrialId(BOB, start)))
	end)

	it("Passed with the switch adds a promotion to the nearest rank above to the own queue; nothing else changes", function()
		local id = T():Start(BOB).id
		local rec, entry = T():Close(id, "passed", true)
		eq(rec.state, "passed")
		eq(type(entry), "table")
		eq(entry.op, "promote"); eq(entry.g, BOB); eq(entry.fromRank, 3); eq(entry.toRank, 2)
		eq(A().OfficerOps:OpenCount(), 1)
		eq(A().Roster:ByGUID(BOB).rankIndex, 3, "the rank in the game is untouched")
		local id2 = T():Start(ANN).id
		local _, none = T():Close(id2, "passed")
		isNil(none)
		eq(A().OfficerOps:OpenCount(), 1, "without the switch, nothing in the queue")
	end)
end)

describe("trial notes (ONT-02 limits, one per officer)", function()
	before_boot(setup())

	it("each officer writes one note, reads the others', and only its own author may send it", function()
		local id = T():Start(BOB).id
		local rec = T():SetNote(id, "  Good healer  ")
		eq(rec.id, "N:" .. BOB .. ":" .. today() .. ":" .. ME); eq(rec.text, "Good healer")
		eq(T():SetNote(id, "Good healer").rev, 1, "the same text is no new revision")
		local other = { id = "N:" .. BOB .. ":" .. today() .. ":" .. OFF, author = OFF, rev = 1, time = GetServerTime(), char = BOB,
			text = "Late | twice" }
		truthy(S():Accept("trials", other, from()))
		local list = T():Notes(id)
		eq(#list, 2); eq(list[1].author, ME, "the own note first")
		contains(V().NotesText(id), "Late || twice")
		-- a note whose author is not the officer of its id is refused
		local forged = { id = "N:" .. BOB .. ":" .. today() .. ":" .. ME, author = OFF, rev = 5, time = GetServerTime(), char = BOB,
			text = "forged" }
		local ok, why = S():Accept("trials", forged, from())
		eq(ok, false); eq(why, "owner")
		eq(T():Note(id).text, "Good healer")
		local long = ("€"):rep(334)
		local _, w = T():SetNote(id, long) eq(w, "bytes")
		contains(T().ErrorText(w, long), "1002 / 1000 bytes")
		_, w = T():SetNote("T:" .. ANN .. ":" .. today(), "x") eq(w, "unknown")
	end)

	it("Delete writes an empty revision that expires after 60 days, through the dialog of the extended notes", function()
		local id = T():Start(BOB).id
		truthy(V():OpenNote(id))
		truthy(A().OfficerNotesView:Save("Line one\nLine two"))
		eq(T():Note(id).text, "Line one\nLine two")
		isNil(A().OfficerNotes:Get(BOB), "not the extended note of the character")
		V():OpenNote(id)
		truthy(A().OfficerNotesView:DeleteNote())
		isNil(T():Note(id))
		local nid = T().NoteId(id, ME)
		eq(S():Get("trials", nid).text, "")
		Mock.StepClock(61 * DAY)
		S():Prune()
		isNil(S():Get("trials", nid))
		truthy(S():Get("trials", id))
	end)
end)

describe("the reminder on the end day (SPEC-16 §4.4)", function()
	before_boot(setup())

	it("appears once on the end day, also after a /reload and another login, and again after an extension", function()
		local id = T():Start(BOB, 3).id
		Mock.StepClock(2 * DAY)
		A().Notify:Check()
		eq(#trialRows(), 0, "nothing before the end day")
		eq(#trialNotices(), 0)
		Mock.StepClock(DAY)
		A().Notify:Check()
		local rows = trialRows()
		eq(#rows, 1); eq(rows[1].urgency, 2); eq(rows[1].who, "Bob")
		contains(rows[1].title, "Trial of Bob ended on " .. T().DayText(today()))
		eq(#trialNotices(), 1)
		A().Notify:Check()
		A().Bus:Emit("STORE_CHANGED", "trials", id, "remote")
		eq(#trialNotices(), 1, "not twice")
		Mock.Reload()
		A().Notify:Check()
		eq(#trialNotices(), 1, "not again after a /reload")
		Mock.Relog(3600)
		A().Notify:Check()
		eq(#trialNotices(), 1, "not again at the next login")
		eq(#trialRows(), 1, "the row stays until somebody decides")
		truthy(T():Extend(id, 2))
		eq(#trialRows(), 0, "extended: no row until the new end")
		Mock.StepClock(2 * DAY)
		A().Notify:Check()
		eq(#trialRows(), 1)
		eq(#trialNotices(), 2, "a new notice on the new end day")
		truthy(T():Close(id, "cancelled"))
		eq(#trialRows(), 0, "closed: the row goes")
	end)

	it("an officer who logs in three days late sees the row and the notice once", function()
		truthy(S():Accept("trials", trial(BOB, dayAgo(17), 14), from()))
		A().Notify:Check()
		eq(#trialNotices(), 1)
		eq(#trialRows(), 1)
		A().Notify:Check()
		eq(#trialNotices(), 1)
	end)

	it("a member who left the guild during the trial: a reminder row until an officer cancels it", function()
		local id = T():Start(BOB, 5).id
		A().Timeline:Read()
		for i, m in ipairs(Mock.guild.members) do if m.guid == BOB then table.remove(Mock.guild.members, i) break end end
		A().Roster:MarkDirty()
		Mock.StepClock(DAY)
		A().Timeline:Read()
		A().Timeline:Flush(true)
		A().Roster:MarkDirty()
		Mock.StepClock(4 * DAY)
		local rows = trialRows()
		eq(#rows, 1); eq(rows[1].urgency, 1)
		contains(rows[1].title, "Bob left the guild during the trial")
		Mock.StepClock(30 * DAY)
		eq(#trialRows(), 1)
		truthy(T():Close(id, "cancelled"))
		eq(#trialRows(), 0)
	end)
end)

describe("the Trials page, the dialog and the member card", function()
	before_boot(setup())

	it("one row per character, the open trial with the farthest end, and how many are open", function()
		truthy(T():Start(BOB, 14, dayAgo(2)))
		truthy(T():Start(BOB, 30, dayAgo(1)))
		local closed = T():Start(ANN, 5, dayAgo(10))
		truthy(T():Close(closed.id, "failed"))
		local rows = T():Rows()
		eq(#rows.open, 1); eq(#rows.closed, 1)
		eq(rows.open[1].rec.days, 30); eq(rows.open[1].others, 1)
		eq(V().RowText(rows.open[1], "name"), "Bob (2 open trials)")
		eq(V().RowText(rows.open[1], "left"), "29 days")
		eq(V().RowText(rows.closed[1], "state"), "Not passed")
		Mock.StepClock(91 * DAY)
		eq(#T():Rows().closed, 0, "older than 90 days: only on the member card")
		matches(section(A().Roster:ByGUID(ANN), "trial").lines[1].text, "Last trial: Not passed on")
	end)

	it("the dialog asks before closing, then closes; Start from the dialog", function()
		local V_ = V()
		truthy(V_:OpenStart(BOB))
		local ok, rec = V_:Begin(nil, 7)
		truthy(ok); eq(rec.days, 7)
		truthy(V_:OpenDialog(rec.id))
		eq(V_:Press("passed"), "armed")
		eq(V_.dialog.passed:GetLabel(), "Confirm")
		eq(T():Get(rec.id).state, "open")
		eq(V_:Press("failed"), "armed", "another button asks again")
		truthy(V_:Press("failed"))
		eq(T():Get(rec.id).state, "failed")
		ok = V_:Begin(ANN, 99, today())
		eq(ok, false)
	end)

	it("the member card shows the trial to officers only", function()
		local id = T():Start(BOB).id
		T():SetNote(id, "Promising")
		local sec = section(A().Roster:ByGUID(BOB), "trial")
		truthy(sec); eq(sec.title, "Trial")
		local all = {}
		for _, l in ipairs(sec.lines) do all[#all + 1] = l.text end
		local text = table.concat(all, "\n")
		contains(text, "On trial until")
		contains(text, "Promising")
		contains(text, "Open the trial")
		rank(3)
		isNil(section(A().Roster:ByGUID(BOB), "trial"))
	end)

	it("What I share counts them without a text; they stay out of the backup; OFF-10 deletes them", function()
		local id = T():Start(BOB).id
		T():SetNote(id, "TRIAL-NOTE-MARK")
		local row
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "otools" then row = r end end
		contains(table.concat(row.lines, "\n"), "Trials you wrote: 1 · trial notes: 1")
		falsy(holds(row.lines, "TRIAL-NOTE-MARK"))
		falsy(holds(A().Backup:Content(), "TRIAL-NOTE-MARK"))
		A().Accounts:RegisterSelf()
		eq(S():Count("trials"), 2)
		Mock.ClearOutput()
		rank(3)
		eq(S():Count("trials"), 0)
		matches(table.concat(Mock.PlainOutput(), " "), "no longer an officer")
	end)
end)

describe("the switch recruit off", function()
	before_boot(setup(1, { recruit = false }))

	it("nothing is written, accepted, listed or shown", function()
		falsy(T().CanSee())
		local rec, why = T():Start(BOB)
		isNil(rec); eq(why, "officer")
		rec, why = S():Put("trials", T().TrialId(BOB, today()), { char = BOB, start = today(), days = 14,
			ends = T().DayOfNumber(T().Number(today()) + 14), state = "open" })
		isNil(rec); eq(why, "set")
		local ok, w = S():Accept("trials", trial(BOB, dayAgo(20), 14), from())
		eq(ok, false); eq(w, "set")
		eq(#trialRows(), 0)
		isNil(section(A().Roster:ByGUID(BOB), "trial"))
		for _, p in ipairs(A().OfficersView.pages) do
			if p.id == "trials" then falsy(p.visible()) end
		end
	end)
end)

describe("TRI-02 on the wire", function()
	before_boot(setup())

	it("the transport refuses them for GUILD and for a whisper to a member; before S5 only the summary on OFFICER", function()
		truthy(S().IsOfficerTool("trials"))
		local item, why = Tr():Send("GUILD", { t = "REC", s = "trials", r = {} }, { officerOnly = true })
		isNil(item); eq(why, "officerOnly")
		local sent = {}
		Tr().wire = function(prio, txt, dist, target, done)
			sent[#sent + 1] = { dist = dist, msg = Codec():Decode(txt), raw = txt }
			done(0)
		end
		A().Compat:SetFeature("officerAddonChannel", "unknown", "test")
		local id = T():Start(BOB).id
		T():SetNote(id, "TRIAL-UNPROVEN")
		Mock.Advance(60, 0.5)
		Sy():SendHello()
		Mock.Advance(10, 0.5)
		for _, s in ipairs(sent) do
			falsy(s.raw:find("TRIAL-UNPROVEN", 1, true), "left on " .. tostring(s.dist))
			if s.msg and s.msg.t == "REC" then ne(s.msg.s, "trials") end
		end
		eq(S():Count("trials"), 2, "kept on this computer")
	end)
end)

describe("TRI-01, TRI-02 in the simulator", function()
	local MARK = "TRIAL-NOTE-WIRE"

	local function watch(sim, members)
		local seen = { leaks = 0, carried = 0, dists = {} }
		for i = 1, sim:count() do
			local c = sim:client(i)
			local tr = c:addon().Transport
			local original = tr.wire
			tr.wire = function(prio, txt, dist, target, done)
				local m = c:addon().Codec:Decode(txt)
				local rec = type(m) == "table" and m.t == "REC" and m.s == "trials"
				local has = holds(m, MARK) or txt:find(MARK, 1, true) ~= nil
				if has or rec then
					seen.carried = seen.carried + 1
					seen.dists[dist] = (seen.dists[dist] or 0) + 1
					local toMember = false
					if dist == "WHISPER" then
						for _, k in ipairs(members) do
							if tostring(target):find(Sim.nameOf(k), 1, true) then toMember = true end
						end
					end
					if dist == "GUILD" or toMember then seen.leaks = seen.leaks + 1 end
				end
				return original(prio, txt, dist, target, done)
			end
		end
		return seen
	end

	local function on(Mk) Mk.features = { recruit = true } end
	local function count(sim, i) return sim:client(i):addon().Store:Count("trials") end

	it("reaches the other officers on OFFICER, never GUILD, never the member on trial", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2, 3 }, setup = on, seed = 61 }
		local seen = watch(sim, { 4, 5 })
		sim:advance(120)
		local Tw = sim:client(1):addon().Trials
		local rec = Tw:Start(Sim.guidOf(4))
		truthy(rec)
		truthy(Tw:SetNote(rec.id, MARK .. " first week"))
		sim:advance(60)
		eq(count(sim, 2), 2); eq(count(sim, 3), 2)
		eq(count(sim, 4), 0, "the member on trial receives nothing"); eq(count(sim, 5), 0)
		sim:advance(2400)
		eq(seen.leaks, 0)
		truthy((seen.dists.OFFICER or 0) > 0)
		isNil(seen.dists.GUILD)
	end)

	it("stays on the writer's computer while the officer channel is not proven", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2, 3 }, officerChannel = false, setup = on, seed = 62 }
		local seen = watch(sim, { 4 })
		sim:advance(120)
		local Tw = sim:client(1):addon().Trials
		local rec = Tw:Start(Sim.guidOf(4))
		truthy(Tw:SetNote(rec.id, MARK .. " local"))
		sim:advance(2400)
		eq(count(sim, 1), 2)
		eq(count(sim, 2), 0); eq(count(sim, 3), 0); eq(count(sim, 4), 0)
		eq(seen.carried, 0)
	end)
end)

describe("the trials in the demo guild", function()
	before_boot(function(M) M.features = { recruit = true } end)

	it("has three trials (one ends today, one extended, one closed) and two notes, and sends nothing", function()
		Mock.Slash("/accord demo")
		local rows = T():Rows()
		eq(#rows.open, 2); eq(#rows.closed, 1)
		eq(rows.open[1].daysLeft, 0, "one ends today")
		eq(rows.open[1].notes, 2)
		matches(V().InfoText(rows.open[2].rec), "extended from 14")
		eq(rows.closed[1].rec.state, "passed")
		eq(#trialRows(), 1)
		eq(#Mock.chat.sent, 0)
		eq(#Mock.errors, 0)
	end)
end)

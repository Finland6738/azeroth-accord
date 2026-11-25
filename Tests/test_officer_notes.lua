-- Extended officer notes (M8.5; SPEC-12 §5, ONT-01..ONT-04): the length limit, who writes and sees them, the note of a
-- former member kept forever, the deletion, the member card, that they stay out of the backup and that the What I share
-- panel only counts them; and, on the simulated wire, that they never travel on GUILD or by WHISPER to a non-officer,
-- that nothing leaves before the officer channel is proven (S5), that a demoted officer's client deletes them and that a
-- re-promotion brings them back.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function N() return AzerothAccord.OfficerNotes end
local function Tr() return AzerothAccord.Transport end
local function Sy() return AzerothAccord.Sync end
local function Codec() return AzerothAccord.Codec end

local ME = "Player-1-0000A001"
local BOB, BOBALT, GONE = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000090"
local OFF, MEMBER = "Player-1-000000FF", "Player-1-00000BAD"
local DAY = 86400

-- The player is an officer (rank 1) unless said otherwise.
local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT },
		{ name = "Officer", level = 60, class = "ROGUE", rank = 1, guid = OFF },
		{ name = "Plain", level = 60, class = "ROGUE", rank = 3, guid = MEMBER },
	} }
	if A() then A().Role:Refresh() A().Roster:MarkDirty() end
end

local function note(char, text, author, extra)
	local r = { id = char, author = author or OFF, rev = 1, time = GetServerTime(), char = char, text = text }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

-- true when `needle` is anywhere in `v` (keys and values, nested tables).
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

describe("ONT-02: the length limit", function()
	before_boot(function() guild() end)

	it("takes 500 characters and 1000 bytes, and no more", function()
		truthy(N().Check(("a"):rep(500)))
		local ok, why = N().Check(("a"):rep(501))
		isNil(ok); eq(why, "chars")
		truthy(N().Check(("à"):rep(500)), "500 characters of two bytes: exactly 1000 bytes")
		ok, why = N().Check(("€"):rep(334))
		isNil(ok); eq(why, "bytes", "334 characters but 1002 bytes")
		eq(N().Length(("€"):rep(334)), 334)
	end)

	it("takes 20 lines and refuses the 21st, and any control character but the line end", function()
		local twenty = {}
		for i = 1, 20 do twenty[i] = "line " .. i end
		truthy(N().Check(table.concat(twenty, "\n")))
		twenty[21] = "one more"
		local ok, why = N().Check(table.concat(twenty, "\n"))
		isNil(ok); eq(why, "lines")
		ok, why = N().Check("bell\7")
		isNil(ok); eq(why, "control")
	end)

	it("cleans what is typed: line ends, tabs, other control characters, spaces at both ends", function()
		eq(N().Clean("  one\r\ntwo\rthree\tfour\1  "), "one\ntwo\nthree four")
		eq(N().Clean("città"), "città", "the last byte of à is not taken for a space")
	end)

	it("refuses to save a note over the limit, says the bytes, and the store refuses such a record from anyone", function()
		local rec, why = N():Set(BOB, ("€"):rep(334))
		isNil(rec); eq(why, "bytes")
		contains(N().ErrorText(why, ("€"):rep(334)), "1002 / 1000 bytes")
		rec, why = N():Set(BOB, ("a"):rep(501))
		isNil(rec); eq(why, "chars")
		truthy(N():Set(BOB, ("à"):rep(500)), "the longest note fits the record size of the set")
		local ok, reason = S():Accept("onotes", note(BOBALT, ("a"):rep(501)), { sender = "Officer", dist = "OFFICER" })
		eq(ok, false); eq(reason, "owner")
		ok, reason = S():Accept("onotes", note(BOBALT, "hi", OFF, { char = BOB }), { sender = "Officer", dist = "OFFICER" })
		eq(ok, false); eq(reason, "owner", "the id is the character")
		ok, reason = S():Accept("onotes", note(BOBALT, "hi", OFF, { extra = 1 }), { sender = "Officer", dist = "OFFICER" })
		eq(ok, false)
	end)
end)

describe("ONT-01: writing, reading, deleting", function()
	before_boot(function() guild() end)

	it("an officer writes one note per character; the latest revision wins and says who wrote it", function()
		local rec = N():Set(BOB, "Raid leader on Thursdays")
		truthy(rec); eq(rec.rev, 1); eq(rec.author, ME); eq(rec.char, BOB)
		eq(N():Get(BOB).text, "Raid leader on Thursdays")
		rec = N():Set(BOB, "Raid leader on Fridays")
		eq(rec.rev, 2)
		eq(N():Set(BOB, "Raid leader on Fridays").rev, 2, "the same text again is not a new revision")
		-- another officer's later revision replaces it
		truthy(S():Accept("onotes", note(BOB, "Moved to Saturdays", OFF, { rev = 3 }), { sender = "Officer", dist = "OFFICER" }))
		eq(N():Get(BOB).text, "Moved to Saturdays")
		eq(N():Get(BOB).author, OFF)
	end)

	it("Delete writes an empty revision, which expires after 60 days; a note with a text never does", function()
		N():Set(BOB, "Keep me")
		N():Set(BOBALT, "Delete me")
		local rec = N():Delete(BOBALT)
		truthy(rec); eq(rec.text, ""); eq(rec.rev, 2)
		isNil(N():Get(BOBALT))
		Mock.StepClock(59 * DAY)
		S():Prune()
		truthy(S():Get("onotes", BOBALT), "the deletion still travels for 60 days")
		Mock.StepClock(2 * DAY)
		S():Prune()
		isNil(S():Get("onotes", BOBALT))
		Mock.StepClock(3650 * DAY)
		S():Prune()
		eq(N():Get(BOB).text, "Keep me", "ten years later")
	end)

	it("a member cannot write one, and sees none", function()
		N():Set(BOB, "Officers only")
		guild(3)
		local rec, why = N():Set(BOB, "mine")
		isNil(rec); eq(why, "officer")
		isNil(N():Get(BOB))
	end)
end)

describe("a former member's note (SPEC-10 Q14: kept forever)", function()
	before_boot(function()
		guild()
		table.insert(Mock.guild.members, { name = "Gone", level = 20, class = "ROGUE", rank = 3, guid = GONE })
	end)

	it("stays after the character left the roster, with the day it left on the card", function()
		A().Timeline:Read()
		truthy(N():Set(GONE, "Left for another guild, may come back"))
		for i, m in ipairs(Mock.guild.members) do if m.guid == GONE then table.remove(Mock.guild.members, i) break end end
		A().Roster:MarkDirty()
		A().Timeline:Read()
		Mock.StepClock(400 * DAY)
		A().Roster:MarkDirty()
		A().Timeline:Read()
		S():Prune()
		eq(N():Get(GONE).text, "Left for another guild, may come back")
		local sec = section({ guid = GONE, name = "Gone", short = "Gone", notInGuild = true }, "onotes")
		truthy(sec)
		eq(sec.lines[1].text, "Left for another guild, may come back")
		local all = {}
		for _, l in ipairs(sec.lines) do all[#all + 1] = l.text end
		matches(table.concat(all, " "), "Left the guild on %d%d%d%d%-%d%d%-%d%d")
	end)
end)

describe("ONT-03, ONT-04: who sees them and where they go", function()
	before_boot(function() guild() end)

	it("the member card shows the note to officers, with the author, the other characters' notes, and | doubled", function()
		local acc = { { guid = BOB, name = "Bob" }, { guid = BOBALT, name = "Bobalt" } }
		for _, g in ipairs({ BOB, BOBALT }) do
			S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = GetServerTime(), token = "T", chars = acc }
		end
		A().Accounts:MarkDirty()
		N():Set(BOB, "Uses a | in the note")
		S():Accept("onotes", note(BOBALT, "The alt's note"), { sender = "Officer", dist = "OFFICER" })
		local sec = section(A().Roster:ByGUID(BOB), "onotes")
		truthy(sec)
		eq(sec.title, "Officer notes")
		eq(sec.lines[1].text, "Uses a || in the note")
		local all = {}
		for _, l in ipairs(sec.lines) do all[#all + 1] = l.text end
		local text = table.concat(all, "\n")
		contains(text, "Written by you")
		contains(text, "Bobalt: The alt's note")
		contains(text, "Edit the note")
		guild(3)
		isNil(section(A().Roster:ByGUID(BOB), "onotes"), "a member never gets the section")
	end)

	it("the dialog saves, refuses a note over the limit and deletes", function()
		local V = A().OfficerNotesView
		truthy(V:Open(BOB, "Bob"))
		truthy(V:Save("First line\nSecond line"))
		eq(N():Get(BOB).text, "First line\nSecond line")
		V:Open(BOB, "Bob")
		local ok, why = V:Save(("€"):rep(334))
		eq(ok, false); eq(why, "bytes")
		contains(V.dialog.status:GetText(), "Too long: 1002 / 1000 bytes.")
		truthy(V:DeleteNote())
		isNil(N():Get(BOB))
		contains(V.CountText("abc"), "3 / 500")
	end)

	it("a member's client refuses them from anyone; an officer's only from an officer (OFF-01, OFF-02)", function()
		local ok, why = S():Accept("onotes", note(BOB, "x"), { sender = "Plain", dist = "OFFICER" })
		eq(ok, false); eq(why, "authority")
		truthy(S():Accept("onotes", note(BOB, "x"), { sender = "Officer", dist = "WHISPER" }))
		guild(3)
		ok, why = S():Accept("onotes", note(BOBALT, "y"), { sender = "Officer", dist = "OFFICER" })
		eq(ok, false); eq(why, "restricted")
	end)

	it("the transport refuses them for GUILD and for a whisper to a member", function()
		truthy(S().IsOfficerTool("onotes"))
		local item, why = Tr():Send("GUILD", { t = "REC", s = "onotes", r = {} }, { officerOnly = true })
		isNil(item); eq(why, "officerOnly")
		item, why = Tr():Send("WHISPER", { t = "REC", s = "onotes", r = {} }, { officerOnly = true, target = "Plain" })
		isNil(item); eq(why, "officerOnly")
	end)

	it("never sends a REC of them before the channel is proven, only the summary on OFFICER", function()
		local sent = {}
		Tr().wire = function(prio, txt, dist, target, done)
			sent[#sent + 1] = { dist = dist, target = target, msg = Codec():Decode(txt), raw = txt }
			done(0)
		end
		A().Compat:SetFeature("officerAddonChannel", "unknown", "test")
		truthy(N():Set(BOB, "SECRET-NOTE-UNPROVEN"))
		Mock.Advance(60, 0.5)
		Sy():SendHello()
		Mock.Advance(10, 0.5)
		local ohello
		for _, s in ipairs(sent) do
			falsy(holds(s.msg, "SECRET-NOTE-UNPROVEN"), "the text left on " .. tostring(s.dist))
			falsy(s.raw:find("SECRET-NOTE-UNPROVEN", 1, true))
			if s.msg and s.msg.t == "REC" then ne(s.msg.s, "onotes") end
			if s.msg and s.msg.t == "OHELLO" then ohello = s end
		end
		truthy(ohello); eq(ohello.dist, "OFFICER")
		truthy(#ohello.msg.m >= Sy().ENTRY, "the summary names the group of the note")
		eq(S():Get("onotes", BOB).text, "SECRET-NOTE-UNPROVEN", "kept on this computer")
	end)

	it("a demoted officer's client deletes them (OFF-10)", function()
		A().Accounts:RegisterSelf()
		N():Set(BOB, "Officers only")
		S():Accept("onotes", note(BOBALT, "And this one"), { sender = "Officer", dist = "OFFICER" })
		eq(S():Count("onotes"), 2)
		Mock.ClearOutput()
		guild(3)
		eq(S():Count("onotes"), 0)
		matches(table.concat(Mock.PlainOutput(), " "), "no longer an officer")
	end)

	it("stays out of the personal backup, and What I share counts them without a text", function()
		N():Set(BOB, "NOTE-NOT-IN-BACKUP")
		falsy(holds(A().Backup:Content(), "NOTE-NOT-IN-BACKUP"))
		local text = A().Backup:Export()
		falsy(type(text) == "string" and text:find("NOTE-NOT-IN-BACKUP", 1, true))
		local row
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "otools" then row = r end end
		truthy(row)
		contains(table.concat(row.lines, "\n"), "Officer notes you wrote: 1")
		falsy(holds(row, "NOTE-NOT-IN-BACKUP"))
	end)

	it("marks the account on the Inactive page", function()
		local V = A().OfficersView
		local a = { name = "Bob", chars = { BOB, BOBALT }, unknown = true }
		local plain = V.InactiveText(a, "name")
		N():Set(BOBALT, "on the alt")
		local marked = V.InactiveText(a, "name")
		ne(plain, marked)
		contains(marked, "|T")
		contains(table.concat(V.InactiveTip(a, GetServerTime()), "\n"), "Has an officer note")
		-- step 2 of the review (SPEC-12 §4.1): the account's note on one line, the main's first, cut to 90 characters
		local Ops = A().OfficersView
		local draft = { account = { chars = { BOB, BOBALT }, main = { guid = BOB } } }
		contains(Ops.NoteLine(draft), "on the alt")
		N():Set(BOB, ("é"):rep(120) .. "\nsecond")
		local line = Ops.NoteLine(draft)
		contains(line, ("é"):rep(90) .. "…")
		falsy(line:find("second", 1, true))
		N():Delete(BOB) N():Delete(BOBALT)
		isNil(Ops.NoteLine(draft))
	end)
end)

describe("ONT-03, ONT-04 on the simulated wire", function()
	local MARK = "EXTENDED-NOTE-MARK"

	-- Wraps every client's wire: `leaks` counts a message that carries the note's text, or a REC of the set, on GUILD or
	-- by WHISPER to a non-officer (`members`, client indexes); `carried` counts every message that carries it.
	local function watch(sim, members)
		local seen = { leaks = 0, carried = 0, dists = {} }
		for i = 1, sim:count() do
			local c = sim:client(i)
			local tr = c:addon().Transport
			local original = tr.wire
			tr.wire = function(prio, txt, dist, target, done)
				local m = c:addon().Codec:Decode(txt)
				local has = holds(m, MARK) or txt:find(MARK, 1, true) ~= nil
				local rec = type(m) == "table" and m.t == "REC" and m.s == "onotes"
				if has then
					seen.carried = seen.carried + 1
					seen.dists[dist] = (seen.dists[dist] or 0) + 1
				end
				if has or rec then
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

	local function count(sim, i) return sim:client(i):addon().Store:Count("onotes") end

	-- Every client's roster shows client `k` at `rank`; client k's own rank changes too (its role follows).
	local function setRank(sim, k, rank)
		local name = Sim.nameOf(k)
		sim.officer[k] = rank <= 1 or nil
		for i = 1, sim:count() do
			local c = sim:client(i)
			if i == k then
				c.Mock.guild.SetMyRank(rank)
			else
				for _, m in ipairs(c.Mock.guild.members) do if m.name == name then m.rank = rank end end
				c.Mock.Fire("GUILD_ROSTER_UPDATE")
				c:addon().Store:RosterChanged()
			end
		end
	end

	it("travels on OFFICER to the other officers and never on GUILD or to a member, once the channel is proven", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2, 3 }, seed = 41 }
		local seen = watch(sim, { 4, 5 })
		sim:advance(120)
		truthy(sim:client(1):addon().Officer.ChannelProven())
		truthy(sim:client(1):addon().OfficerNotes:Set(Sim.guidOf(4), MARK .. " raid leader"))
		sim:advance(60)
		eq(count(sim, 2), 1); eq(count(sim, 3), 1)
		eq(count(sim, 4), 0, "the member it is about never receives it"); eq(count(sim, 5), 0)
		-- a late officer is brought up to date by whisper, from the designated officer
		sim:advance(2400)
		eq(seen.leaks, 0, "nothing on GUILD, nothing by whisper to a member")
		truthy(seen.carried > 0)
		truthy((seen.dists.OFFICER or 0) > 0, "it went on OFFICER")
		isNil(seen.dists.GUILD)
	end)

	it("stays on the writer's computer while OFFICER carries nothing (S5 not proven), whatever the time", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2, 3 }, officerChannel = false, seed = 42 }
		local seen = watch(sim, { 4 })
		sim:advance(120)
		eq(sim:client(1):addon().Officer.ChannelProven(), false)
		truthy(sim:client(1):addon().OfficerNotes:Set(Sim.guidOf(4), MARK .. " local only"))
		sim:advance(2400)
		eq(count(sim, 1), 1)
		eq(count(sim, 2), 0); eq(count(sim, 3), 0); eq(count(sim, 4), 0)
		eq(seen.carried, 0, "the text never left, on no distribution: no whisper fallback")
		eq(seen.leaks, 0)
	end)

	it("a demoted officer's client deletes them; promoted again, it receives them from the other officers", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2, 3 }, accounts = true, seed = 43 }   -- the account registers itself, as at login
		local seen = watch(sim, { 4, 5 })
		sim:advance(120)
		local writer = sim:client(1):addon().OfficerNotes
		truthy(writer:Set(Sim.guidOf(4), MARK .. " one"))
		truthy(writer:Set(Sim.guidOf(5), MARK .. " two"))
		sim:advance(60)
		eq(count(sim, 3), 2)
		setRank(sim, 3, 3)
		sim:advance(5)
		eq(count(sim, 3), 0, "deleted on demotion")
		falsy(sim:client(3):addon().Officer:HasData())
		-- while it is a member, a new note never reaches it
		truthy(writer:Set(Sim.guidOf(4), MARK .. " one, edited"))
		sim:advance(1800)
		eq(count(sim, 3), 0)
		eq(seen.leaks, 0)
		-- promoted again: the whole set comes back with the officers' sync
		setRank(sim, 3, 1)
		sim:advance(2400)
		eq(count(sim, 3), 2, "re-promotion receives the notes again")
		eq(sim:client(3):addon().Store:Get("onotes", Sim.guidOf(4)).text, MARK .. " one, edited")
		eq(count(sim, 4), 0); eq(count(sim, 5), 0)
		eq(seen.leaks, 0)
	end)
end)

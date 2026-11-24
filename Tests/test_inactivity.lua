-- Inactivity tiers and declared absences (M8.3; SPEC-12 §3, §8): last seen per account (an alt counts, in the guild and
-- outside it), the tiers and their edges, the officers' choice, absences with a return date, who sees what, and that the
-- records reach only officers. The network part runs in the simulator.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function I() return AzerothAccord.Inactivity end
local function Ab() return AzerothAccord.Absence end
local function V() return AzerothAccord.OfficersView end
local function Tr() return AzerothAccord.Transport end

local ME = "Player-1-0000A001"
local BOB, BOBALT, ANN, GONE = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000A01", "Player-1-00000090"
local OFF, MEMBER, OUT = "Player-1-000000FF", "Player-1-00000BAD", "Player-1-0000CC01"
local DAY = 86400

-- The player is an officer (rank 1) unless said otherwise. Bob has been offline 100 days, Bob's alt 2 days.
local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = false, lastOnline = { 0, 0, 100, 0 } },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT, online = false, lastOnline = { 0, 0, 2, 0 } },
		{ name = "Ann", level = 50, class = "PRIEST", rank = 3, guid = ANN, online = false, lastOnline = { 0, 0, 40, 0 } },
		{ name = "Gone", level = 20, class = "ROGUE", rank = 3, guid = GONE, online = false, lastOnline = {} },   -- the client tells nothing
		{ name = "Officer", level = 60, class = "ROGUE", rank = 1, guid = OFF },
		{ name = "Plain", level = 60, class = "ROGUE", rank = 3, guid = MEMBER },
	} }
	if A() then A().Role:Refresh() A().Roster:MarkDirty() end
end

local function account(guid, chars)
	S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T", chars = chars }
	A().Accounts:MarkDirty()
	I():Invalidate()
end

local function link()
	account(BOB, { { guid = BOB, name = "Bob" }, { guid = BOBALT, name = "Bobalt" } })
	account(BOBALT, { { guid = BOB, name = "Bob" }, { guid = BOBALT, name = "Bobalt" } })
end

local function find(guid)
	A().Accounts:MarkDirty()
	I():Invalidate()
	for _, a in ipairs(I():Accounts()) do
		for _, c in ipairs(a.chars) do if c == guid then return a end end
	end
end

local function listed(rows, guid)
	for _, a in ipairs(rows) do
		for _, c in ipairs(a.chars) do if c == guid then return a end end
	end
	return nil
end

local function today(offset) return A().Timeline.DayOf(GetServerTime() + (offset or 0) * DAY) end

local function rec(id, char, back, extra)
	local r = { id = id, author = char, rev = 1, time = GetServerTime(), char = char, from = today(), ["until"] = back }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

describe("INA-01, INA-02: an account is as recent as its most recent character", function()
	before_boot(function() guild() end)

	it("does not count a player active only on an alt as inactive", function()
		eq(find(BOB).tier, 4, "alone, Bob is 100 days away")
		link()
		local a = find(BOB)
		eq(a.days, 2); eq(a.tier, 0); eq(a.lastName, "Bobalt"); eq(a.lastSource, "native"); eq(#a.chars, 2)
		falsy(listed(I():Rows(), BOB), "not on the page")
	end)

	it("counts an alt outside the guild by the day its account tells (shared)", function()
		local seen = GetServerTime() - 3 * DAY
		seen = seen - seen % DAY
		account(BOB, { { guid = BOB, name = "Bob" }, { guid = OUT, name = "Elsewhere", inGuild = false, guild = "", seen = seen } })
		local a = find(BOB)
		eq(a.lastSource, "shared"); eq(a.lastName, "Elsewhere"); eq(a.tier, 0)
		eq(a.days, math.floor((GetServerTime() - seen) / DAY))
		eq(#a.chars, 1, "only the characters in the guild are counted")
	end)

	it("takes an online character as seen now", function()
		account(BOB, { { guid = BOB, name = "Bob" }, { guid = OFF, name = "Officer" } })
		account(OFF, { { guid = BOB, name = "Bob" }, { guid = OFF, name = "Officer" } })
		local a = find(BOB)
		eq(a.days, 0); truthy(a.online); truthy(a.officer, "one of its characters is an officer")
	end)

	it("counts the player's own characters by their last login", function()
		local db = A().Config.db.account
		db.chars = db.chars or {}
		db.chars.TestRealm = db.chars.TestRealm or {}
		db.chars.TestRealm[BOB] = { name = "Bob", seen = GetServerTime() - DAY - 10 }
		local a = find(BOB)
		eq(a.days, 1); eq(a.lastSource, "own")
	end)

	it("joins characters by a public note and says so", function()
		Mock.guild.members[2].note = "main: Bob"
		A().Roster:MarkDirty()
		local a = find(BOB)
		eq(a.tier, 0); truthy(a.byNote)
		contains(V().InactiveText(a, "name"), "grouped by a note")
	end)

	it("is unknown when no character of the account is known", function()
		local a = find(GONE)
		truthy(a.unknown); isNil(a.tier); isNil(a.days)
		truthy(listed(I():Rows(), GONE))
		falsy(listed(I():Rows{ unknown = false }, GONE))
		local rows = I():Rows()
		eq(rows[#rows].name, "Gone", "the unknown ones last")
	end)
end)

describe("INA-03, INA-04: tiers", function()
	before_boot(function() guild() end)

	it("puts every edge in the highest tier whose threshold is reached", function()
		local t = { 14, 30, 60, 90 }
		local cases = { { 0, 0 }, { 13, 0 }, { 14, 1 }, { 29, 1 }, { 30, 2 }, { 59, 2 }, { 60, 3 }, { 89, 3 }, { 90, 4 }, { 400, 4 } }
		for _, c in ipairs(cases) do eq(I().TierOf(c[1], t), c[2], c[1] .. " days") end
		isNil(I().TierOf(nil, t))
	end)

	it("changes tier at the exact day of the roster's hours", function()
		Mock.guild.members[3].lastOnline = { 0, 0, 13, 23 }
		A().Roster:MarkDirty()
		eq(find(ANN).tier, 0)
		Mock.guild.members[3].lastOnline = { 0, 0, 14, 0 }
		A().Roster:MarkDirty()
		eq(find(ANN).tier, 1)
	end)

	it("lists from the chosen tier, the longest away first", function()
		local rows = I():Rows{ unknown = false }
		eq(rows[1].name, "Bob"); eq(rows[2].name, "Ann"); eq(#rows, 2)
		eq(#I():Rows{ minTier = 3, unknown = false }, 1)
		eq(#I():Rows{ search = "ann", unknown = false }, 1)
	end)

	it("lets an officer choose the tiers for all officers, and reset them", function()
		deepEq(I():Tiers(), { 14, 30, 60, 90 })
		truthy(I():SetTiers{ 1, 2, 3, 150 })
		deepEq(I():Tiers(), { 1, 2, 3, 150 })
		eq(find(BOB).tier, 3, "100 days with these tiers")
		eq(S():Get("ocfg", "tiers").rev, 1)
		truthy(I():ResetTiers())
		deepEq(I():Tiers(), { 14, 30, 60, 90 })
		eq(S():Get("ocfg", "tiers").rev, 2)
	end)

	it("refuses tiers that are not four increasing days from 1 to 365", function()
		for _, bad in ipairs({ { 1, 2, 3 }, { 1, 2, 2, 3 }, { 4, 3, 2, 1 }, { 0, 2, 3, 4 }, { 1, 2, 3, 366 }, { 1, 2, 3, 4.5 },
			{ 1, 2, 3, 4, 5 } }) do
			local ok, why = I():SetTiers(bad)
			eq(ok, false); eq(why, "tiers")
		end
		local r = { id = "tiers", author = OFF, rev = 1, time = GetServerTime(), tiers = { 90, 60, 30, 14 } }
		local ok, why = S():Accept("ocfg", r, { sender = "Officer", dist = "OFFICER" })
		eq(ok, false); eq(why, "owner")
		S():Records("ocfg").tiers = r
		deepEq(I():Tiers(), { 14, 30, 60, 90 }, "an invalid record held is ignored")
	end)

	it("keeps an officer's choice valid after its demotion, and refuses it from a member", function()
		local r = { id = "tiers", author = MEMBER, rev = 1, time = GetServerTime(), tiers = { 10, 20, 30, 40 } }
		local ok, why = S():Accept("ocfg", r, { sender = "Plain", dist = "WHISPER" })
		eq(ok, false); eq(why, "authority")
		truthy(S():Accept("ocfg", r, { sender = "Officer", dist = "OFFICER" }))
	end)
end)

describe("INA-05, INA-06: declared absences", function()
	before_boot(function() guild() end)

	it("hides an account until the return date, that day included, then counts it again", function()
		truthy(A().Absence:SetFor(ANN, today(5)))
		falsy(listed(I():Rows(), ANN))
		local a = listed(I():Rows{ away = true }, ANN)
		truthy(a.away); eq(V().InactiveText(a, "away"), "Away until " .. Ab().DayText(today(5)))
		eq(V().InactiveText(a, "tier"), "")
		local last = today(5)
		Mock.StepClock(5 * DAY)
		eq(today(), last)
		falsy(listed(I():Rows(), ANN), "still away on the return day")
		Mock.StepClock(DAY)
		a = listed(I():Rows(), ANN)
		truthy(a, "back on the list the day after")
		eq(V().InactiveText(a, "away"), "away until " .. Ab().DayText(last))
		Mock.StepClock(14 * DAY)
		eq(V().InactiveText(listed(I():Rows(), ANN), "away"), "", "not said any more after 14 days")
	end)

	it("counts for the whole account, whatever character declared it", function()
		link()
		Mock.guild.members[2].lastOnline = { 0, 0, 50, 0 }
		A().Roster:MarkDirty()
		truthy(listed(I():Rows(), BOB))
		A().Absence:SetFor(BOBALT, today(3))
		I():Invalidate()
		falsy(listed(I():Rows(), BOB))
	end)

	it("takes the most recently written record between :self and :off", function()
		local t = GetServerTime()
		S():Records("absence")[ANN .. ":self"] = rec(ANN .. ":self", ANN, today(10), { time = t - 100 })
		S():Records("absence")[ANN .. ":off"] = rec(ANN .. ":off", ANN, 0, { time = t - 50, author = OFF })
		isNil(find(ANN).away, "the officer cleared it later")
		S():Records("absence")[ANN .. ":self"] = rec(ANN .. ":self", ANN, today(2), { time = t })
		eq(find(ANN).absence.day, today(2))
		S():Records("absence")[ANN .. ":off"] = rec(ANN .. ":off", ANN, today(20), { time = t + 1, author = OFF })
		eq(find(ANN).absence.day, today(20))
	end)

	it("checks the shape: today or earlier to 180 days, no reason and no other field", function()
		local function valid(r) return Ab().ValidRecord(r, S()) end
		truthy(valid(rec(ANN .. ":off", ANN, today(180), { author = OFF })))
		truthy(valid(rec(ANN .. ":off", ANN, 0, { author = OFF })))
		falsy(valid(rec(ANN .. ":off", ANN, today(181), { author = OFF })))
		falsy(valid(rec(ANN .. ":off", ANN, today(-1), { author = OFF })), "ends before it starts")
		falsy(valid(rec(ANN .. ":off", ANN, today(3), { author = OFF, from = today(1) })), "starts after it was written")
		falsy(valid(rec(ANN .. ":off", ANN, today(3), { author = OFF, reason = "holiday" })))
		falsy(valid(rec(ANN .. ":x", ANN, today(3))))
		falsy(valid(rec(ANN .. ":self", ANN, today(3), { author = BOB })), "another account cannot write :self")
	end)

	it("reads a typed date", function()
		eq(Ab().ParseDate(Ab().DayText(today(7))), today(7))
		eq(select(2, Ab().ParseDate("next week")), "date")
		eq(select(2, Ab().ParseDate("2026-02-30")), "date")
		eq(select(2, Ab().ParseDate(Ab().DayText(today(-1)))), "past")
		eq(select(2, Ab().ParseDate(Ab().DayText(today(181)))), "far")
	end)

	it("is deleted 30 days after the return, or after it was cleared", function()
		local t = GetServerTime()
		S():Records("absence")[ANN .. ":off"] = rec(ANN .. ":off", ANN, today(2), { author = OFF })
		S():Records("absence")[BOB .. ":off"] = rec(BOB .. ":off", BOB, 0, { author = OFF })
		Mock.StepClock(30 * DAY)
		S():Prune()
		eq(S():Count("absence"), 2)
		Mock.StepClock(DAY + 1)
		S():Prune()
		eq(S():Count("absence"), 1, "the cleared one goes first")
		Mock.StepClock(2 * DAY)
		S():Prune()
		eq(S():Count("absence"), 0)
	end)

	it("fits the size limit of its set", function()
		local long = "Player-4294967295-FFFFFFFFFFFF"
		local r = rec(long .. ":self", long, today(180), { rev = 2147483647 })
		truthy(A().Config.EstimateSize(r) <= S().SETS.absence.maxBytes, "size " .. A().Config.EstimateSize(r))
	end)
end)

describe("who sees what (SPEC-10 Q13)", function()
	before_boot(function() guild() end)

	local function tabIds()
		local ids = {}
		for _, v in ipairs(A().Shell:ViewList()) do ids[v.id] = true end
		return ids
	end

	it("gives an officer the tab, the page and the card section", function()
		truthy(tabIds().officers)
		truthy(#I():Rows() > 0)
		A().Roster:MarkDirty()
		local d = A().MemberCard.Describe(A().Roster:ByGUID(ANN))
		local found
		for _, s in ipairs(d.sections) do if s.id == "absence" then found = s end end
		truthy(found); eq(found.lines[1].text, "No absence declared.")
		truthy(A().Shell:OpenView("officers"))
		eq(V().pageId, "inactive")
		truthy(#V().rows > 0)
		truthy(V():ShowPage("timeline"))
		truthy(V():OpenTiers()); V().tiersDialog.fields[1]:SetText("5")
		truthy(V():SaveTiers()); eq(I():Tiers()[1], 5)
		truthy(V():OpenAbsence(ANN, "Ann"))
		V().absenceDialog.field:SetText("nope")
		eq(V():SaveAbsence(), false)
		V().absenceDialog.field:SetText(Ab().DayText(today(4)))
		truthy(V():SaveAbsence())
		eq(S():Get("absence", ANN .. ":off")["until"], today(4))
	end)

	it("gives a member nothing about others: no tab, no tier, not even their own, no section", function()
		guild(3)
		falsy(tabIds().officers)
		eq(#I():Accounts(), 0); eq(#I():Rows(), 0)
		isNil(I():AccountOf(ME))
		isNil(A().Absence:AccountOf(ANN))
		falsy(A().Shell:OpenView("officers"))
		local d = A().MemberCard.Describe(A().Roster:ByGUID(ANN))
		for _, s in ipairs(d.sections) do ne(s.id, "absence") end
		eq(A().Absence:SetFor(ANN, today(3)), false)
		eq(I():SetTiers{ 1, 2, 3, 4 }, false)
		isNil(V():OpenTiers())
	end)

	it("shows a member their own declaration only, never what an officer wrote", function()
		guild(3)
		S():Records("absence")[ME .. ":off"] = rec(ME .. ":off", ME, today(9), { author = OFF })
		isNil(A().Absence:Own())
		truthy(A().Absence:Declare(today(3)))
		eq(A().Absence:Own().day, today(3))
	end)

	it("leaves the tab when the officer is demoted while it is open", function()
		A().Shell:OpenView("officers")
		guild(3)
		A().Shell:Refresh()
		ne(A().Shell.selected, "officers")
		falsy(tabIds().officers)
	end)

	it("declares and clears with /accord away", function()
		guild(3)
		Mock.Slash("/accord away " .. Ab().DayText(today(6)))
		eq(S():Get("absence", ME .. ":self")["until"], today(6))
		Mock.Slash("/accord away off")
		eq(S():Get("absence", ME .. ":self")["until"], 0)
		Mock.Slash("/accord away yesterday")
		matches(table.concat(Mock.PlainOutput(), " "), "YYYY%-MM%-DD")
	end)

	it("declares from the Absence card of the Settings", function()
		guild(3)
		A().Shell:OpenView("settings")
		local f = A().SettingsView.frame
		f.absenceEdit:SetText(Ab().DayText(today(8)))
		truthy(A().SettingsView:SaveAbsence(f))
		contains(f.absenceStatus:GetText(), "next login")
		contains(f.absenceCurrent:GetText(), "Away until")
		truthy(A().SettingsView:SaveAbsence(f, 0))
		eq(f.absenceCurrent:GetText(), "No absence declared.")
	end)

	it("keeps only the account's own declaration when the officer is demoted (OFF-10)", function()
		A().Absence:Declare(today(3))
		A().Absence:SetFor(ANN, today(3))
		I():SetTiers{ 1, 2, 3, 4 }
		local db = A().Config.db.account
		db.chars = { TestRealm = { [ME] = { name = "Tester", guild = A().GuildKey:Current(), seen = GetServerTime() } } }
		guild(3)
		A().Officer:CheckDemotion()
		eq(S():Count("ocfg"), 0)
		eq(S():Count("absence"), 1)
		truthy(S():Get("absence", ME .. ":self"))
		falsy(A().Officer:HasData(), "the own declaration is not officer data: nothing more to delete, no second message")
		eq(A().Officer:CheckDemotion(), false)
	end)

	it("takes a member's own declaration by whisper only, from its account (OFF-02)", function()
		local r = rec(MEMBER .. ":self", MEMBER, today(3))
		local ok, why = S():Accept("absence", r, { sender = "Plain", dist = "GUILD" })
		eq(ok, false); eq(why, "authority")
		ok, why = S():Accept("absence", r, { sender = "Ann", dist = "WHISPER" })
		eq(ok, false); eq(why, "authority", "somebody else's declaration from a member")
		ok, why = S():Accept("absence", rec(MEMBER .. ":off", MEMBER, today(3)), { sender = "Plain", dist = "WHISPER" })
		eq(ok, false); eq(why, "authority", "a member cannot write :off")
		truthy(S():Accept("absence", r, { sender = "Plain", dist = "WHISPER" }))
	end)

	it("is refused by a member's client from anyone (OFF-01), and never sent on GUILD", function()
		guild(3)
		local ok, why = S():Accept("absence", rec(MEMBER .. ":self", MEMBER, today(3)), { sender = "Officer", dist = "WHISPER" })
		eq(ok, false); eq(why, "restricted")
		for _, set in ipairs({ "absence", "ocfg" }) do
			local item, refused = Tr():Send("GUILD", { t = "REC", s = set, r = {} }, { officerOnly = true })
			isNil(item); eq(refused, "officerOnly")
			truthy(S().IsOfficerTool(set))
		end
	end)

	it("says it in What I share, to officers only, with the return date and no switch", function()
		guild(3)
		A().Absence:Declare(today(3))
		local row
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "absence" then row = r end end
		truthy(row); isNil(row.switch)
		contains(row.lines[1], Ab().DayText(today(3)))
		contains(row.to, "officers only")
	end)
end)

describe("the cost (SPEC-12 §3.2)", function()
	before_boot(function()
		local list = {}
		for i = 1, 1000 do
			list[i] = { name = "M" .. i, level = 10 + i % 50, class = "MAGE", rank = 3, guid = ("Player-1-%08X"):format(0x5000 + i),
				online = i % 7 == 0, lastOnline = { 0, 0, i % 120, 0 } }
		end
		Mock.guild.Set{ name = "Accord", myRank = 1, members = list }
	end)

	it("computes a guild of 1000 members quickly", function()
		for i = 1, 600, 3 do
			local g = {}
			for k = 0, 2 do g[k + 1] = { guid = ("Player-1-%08X"):format(0x5000 + i + k), name = "M" .. (i + k) } end
			for k = 1, 3 do
				S():Records("accounts")[g[k].guid] = { id = g[k].guid, author = g[k].guid, rev = 1, time = GetServerTime(), token = "T", chars = g }
			end
		end
		A().Accounts:MarkDirty()
		A().Roster:Members()
		A().Accounts:Groups()
		local best
		for _ = 1, 5 do
			I():Invalidate()
			local t0 = Mock.RealClock()
			local n = #I():Accounts()
			local ms = (Mock.RealClock() - t0) * 1000
			truthy(n >= 599, "accounts " .. n)
			best = best and math.min(best, ms) or ms
		end
		T.log(("[M8.3] inactivity of 1000 members: %.1f ms"):format(best))
		truthy(best < 100, "took " .. best .. " ms")
	end)
end)

describe("OFF-04..OFF-09: absences and tiers among officers (simulator)", function()
	local function held(sim, i, set) return sim:client(i):addon().Store:Count(set) end
	local function plus(sim, i, days)
		local c = sim:client(i)
		return c:addon().Timeline.DayOf(c.E.GetServerTime() + days * DAY)
	end

	it("sends a member's declaration to the officers by whisper, even with the officer channel dead", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2, 3 }, officerChannel = false, seed = 31 }
		sim:advance(120)
		local ok, sent = sim:client(4):addon().Absence:Declare(plus(sim, 4, 5))
		truthy(ok); eq(sent, 2, "two officers chosen")
		sim:advance(60)
		eq(held(sim, 1, "absence") + held(sim, 2, "absence") + held(sim, 3, "absence"), 2)
		eq(held(sim, 5, "absence"), 0, "another member never receives it")
	end)

	it("spreads it to the other officers on OFFICER once the channel is proven, with the tiers", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2, 3 }, seed = 32 }
		sim:advance(120)
		sim:client(4):addon().Absence:Declare(plus(sim, 4, 5))
		truthy(sim:client(1):addon().Inactivity:SetTiers{ 5, 10, 20, 40 })
		sim:advance(2400)
		for i = 1, 3 do
			eq(held(sim, i, "absence"), 1, "officer " .. i)
			deepEq(sim:client(i):addon().Inactivity:Tiers(), { 5, 10, 20, 40 })
		end
		eq(held(sim, 5, "absence"), 0); eq(held(sim, 5, "ocfg"), 0)
		eq(held(sim, 4, "ocfg"), 0, "the member holds its own declaration only")
	end)

	it("tries again at the next login when no officer was online", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, offline = { 1, 2 }, officerChannel = false, seed = 33 }
		sim:advance(120)
		local ok, sent = sim:client(3):addon().Absence:Declare(plus(sim, 3, 5))
		truthy(ok); eq(sent, 0)
		truthy(sim:client(3):addon().Absence:NeedsSending())
		sim:client(1):login()
		sim:advance(120)
		sim:client(3):addon().Absence.AUTO = true
		sim:client(3):addon().Absence.state.loginDone = false
		sim:client(3):addon().Sync:SendHello()
		sim:advance(600)
		eq(held(sim, 1, "absence"), 1)
		eq(held(sim, 4, "absence"), 0)
	end)
end)

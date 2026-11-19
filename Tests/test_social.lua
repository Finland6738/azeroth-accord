-- The social index (M4.4; SPEC-07 §3.2, SOC-04..SOC-06, ADR 0008): the day window, entropy and effective partners, the
-- three worked examples of SPEC-07 §3.2 as numeric tests (index 10, 22, 75 with A = 41), the maximum over observers, alts
-- merged into accounts, "not enough data", and the computation in steps at most once every ten minutes.
local function A() return AzerothAccord end
local function So() return AzerothAccord.Social end
local function S() return AzerothAccord.Store end

local ME = "Player-1-0000A001"
local BOB, BOBALT, CAT, DAN, EVE = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000CA7", "Player-1-00000DA1", "Player-1-00000E0E"

local function pairKey(a, b) if a > b then a, b = b, a end return a .. ":" .. b end

-- Co-play records as the observers publish them: { [day] = { { a, b, minutes }, ... } } for one observer.
local seq = 0
local function observe(observer, day, list)
	seq = seq + 1
	local p = {}
	for _, x in ipairs(list) do p[pairKey(x[1], x[2])] = x[3] end
	local id = observer .. ":" .. day .. ":" .. seq
	S():Records("coplay")[id] = { id = id, author = observer, rev = 1, time = GetServerTime(), day = day, observer = observer, pairs = p }
	A().Bus:Emit("STORE_CHANGED", "coplay", id, "remote")
end

local function guild()
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", rank = 3, guid = BOB }, { name = "Bobalt", rank = 4, guid = BOBALT },
		{ name = "Cat", rank = 3, guid = CAT }, { name = "Dan", rank = 3, guid = DAN }, { name = "Eve", rank = 3, guid = EVE },
	} }
end

local function bobAccount()
	for guid, other in pairs({ [BOB] = BOBALT, [BOBALT] = BOB }) do
		S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "BOBTOKEN",
			chars = { { guid = guid, name = "x" }, { guid = other, name = "y" } } }
	end
	A().Accounts:MarkDirty()
end

describe("days and the window", function()
	it("adds days across months, years and leap days", function()
		eq(So().AddDays(20260101, -1), 20251231)
		eq(So().AddDays(20240301, -1), 20240229)
		eq(So().AddDays(20230301, -1), 20230228)
		eq(So().AddDays(20251231, 1), 20260101)
		eq(So().AddDays(20260115, 0), 20260115)
		eq(So().AddDays(20000229, 365), 20010228)
	end)

	it("the window is the last 30 days, today included", function()
		eq(So().CutoffDay(20260130), 20260101)
		eq(So().CutoffDay(20260301), 20260131)
	end)
end)

describe("entropy and the index", function()
	it("equal time with four partners is four effective partners", function()
		local n, total, count = So().Effective({ a = 600, b = 600, c = 600, d = 600 })
		near(n, 4, 1e-9); eq(total, 2400); eq(count, 4)
	end)

	it("one partner only is one; nobody is zero", function()
		near(So().Effective({ a = 500 }), 1, 1e-12)
		eq(So().Effective({}), 0)
		eq(select(3, So().Effective({ a = 0, b = 10 })), 1)
	end)

	it("index = min(100, round(100 N / (A - 1))), none with fewer than two active accounts", function()
		eq(So().IndexOf(4, 41), 10)
		eq(So().IndexOf(30, 41), 75)
		eq(So().IndexOf(50, 41), 100)
		eq(So().IndexOf(1, 3), 50)
		isNil(So().IndexOf(1, 1)); isNil(So().IndexOf(nil, 10))
	end)
end)

describe("the worked examples of SPEC-07 §3.2 (A = 41)", function()
	-- The subject S, its partners P1.., and filler accounts F1.. that play an hour together in pairs, so that exactly 41
	-- accounts are active. Minutes over several days (a pair has at most 1440 minutes a day).
	local DAY = 20260110
	local function scenario(partnerMinutes, fillers)
		local records = {}
		local function rec(day, list)
			local p = {}
			for _, x in ipairs(list) do p[pairKey(x[1], x[2])] = x[3] end
			records[#records + 1] = { day = day, pairs = p }
		end
		for i, minutes in ipairs(partnerMinutes) do
			local partner = ("P%02d"):format(i)
			local left, day = minutes, DAY
			while left > 0 do
				local m = math.min(left, 1000)
				rec(day, { { "S", partner, m } })
				left, day = left - m, day + 1
			end
		end
		for i = 1, fillers do rec(DAY, { { ("F%02d"):format(i), ("F%02d"):format(i % fillers + 1), 60 } }) end   -- a ring
		local result = So().Build(records, function(g) return g end, 20260101)
		eq(result.active, 41, "41 active accounts")
		return result.accounts.S
	end

	it("100 hours always with the same 4 people, in equal parts: N = 4, index 10", function()
		local s = scenario({ 1500, 1500, 1500, 1500 }, 36)
		near(s.effective, 4, 1e-9)
		eq(s.minutes, 6000); eq(s.partners, 4)
		eq(s.index, 10)
	end)

	it("100 hours, half with one friend and the rest over 20 people: N ≈ 8.9, index 22", function()
		local minutes = { 3000 }
		for i = 2, 21 do minutes[i] = 150 end
		local s = scenario(minutes, 19)
		near(s.effective, 8.94, 0.005)
		eq(s.partners, 21)
		eq(s.index, 22)
		eq(s.top[1].key, "P01"); near(s.top[1].share, 0.5, 1e-12)
		eq(#s.top, 5); near(s.top[2].share, 0.025, 1e-12)
	end)

	it("60 hours split evenly over 30 people: N = 30, index 75", function()
		local minutes = {}
		for i = 1, 30 do minutes[i] = 120 end
		local s = scenario(minutes, 10)
		near(s.effective, 30, 1e-9)
		eq(s.minutes, 3600)
		eq(s.index, 75)
	end)
end)

describe("from the co-play records", function()
	before_boot(function() guild() end)

	local TODAY

	local function today() TODAY = A().Compat.ServerDay() return TODAY end

	it("takes the maximum over observers, never the sum", function()
		local d = today()
		observe(ME, d, { { ME, CAT, 200 }, { ME, DAN, 200 } })
		observe(CAT, d, { { ME, CAT, 180 }, { CAT, DAN, 150 } })
		observe(DAN, d, { { ME, CAT, 210 }, { ME, DAN, 190 }, { CAT, DAN, 150 } })
		local r = So():ComputeNow()
		eq(r.graph[ME][CAT], 210); eq(r.graph[ME][DAN], 200); eq(r.graph[CAT][DAN], 150)
		eq(So():MinutesBetween(CAT, ME), 210)
		eq(r.active, 3)
	end)

	it("merges alts into one account and leaves out the pairs inside an account", function()
		bobAccount()
		local d = today()
		observe(BOB, d, { { BOB, CAT, 200 }, { BOB, BOBALT, 300 } })
		observe(BOBALT, So().AddDays(d, -3), { { BOBALT, CAT, 100 }, { BOBALT, DAN, 30 } })
		local r = So():ComputeNow()
		local bob = So():ForGUID(BOBALT)
		eq(bob, So():ForGUID(BOB))
		eq(bob.minutes, 330); eq(bob.partners, 2)
		eq(So():MinutesBetween(CAT, BOBALT), 300)
		isNil(r.graph[BOB] and r.graph[BOB][BOBALT])
	end)

	it("counts only the last 30 days", function()
		local d = today()
		observe(ME, So().AddDays(d, -29), { { ME, CAT, 400 } })
		observe(ME, So().AddDays(d, -30), { { ME, DAN, 400 } })
		So():ComputeNow()
		eq(So():MinutesBetween(ME, CAT), 400)
		eq(So():MinutesBetween(ME, DAN), 0)
	end)

	it("below 5 hours there is not enough data (SOC-04); an account with no group play has nothing", function()
		local d = today()
		observe(ME, d, { { ME, CAT, 299 }, { CAT, DAN, 300 }, { DAN, EVE, 60 } })
		So():ComputeNow()
		local me = So():ForGUID(ME)
		falsy(me.enough); isNil(me.index); isNil(So():Index(ME))
		local cat = So():ForGUID(CAT)
		truthy(cat.enough); eq(So():Active(), 4)
		eq(cat.index, So().IndexOf(cat.effective, 4))
		isNil(So():ForGUID(BOB))
	end)

	it("runs in steps on later frames, at most once every ten minutes unless asked (SOC-06)", function()
		local d = today()
		for i = 1, 150 do observe(ME, So().AddDays(d, -(i % 20)), { { ME, ("Player-1-%08X"):format(0x5000 + i), 61 } }) end
		eq(So():Refresh(), "started")
		eq(So():Refresh(), "running")
		isNil(So().state.result)
		Mock.Advance(1)
		local r = So().state.result
		notNil(r)
		truthy(So().state.lastSteps > 2, "steps: " .. tostring(So().state.lastSteps))
		eq(r.accounts[ME].partners, 150)
		eq(So():Refresh(), "recent")
		observe(ME, d, { { ME, CAT, 500 } })
		eq(So():Refresh(), "recent", "the data changed, but the last run is less than ten minutes old")
		Mock.SetServerTime(GetServerTime() + So().MIN_INTERVAL + 1)
		eq(So():Refresh(), "started")
		Mock.Advance(1)
		eq(So().state.result.accounts[ME].partners, 151)
		eq(So():Refresh(true), "started", "forced")
	end)

	it("tells the views when a computation ended, and forgets everything on a change of guild", function()
		local heard = 0
		A().Bus:On("SOCIAL_UPDATED", function() heard = heard + 1 end)
		observe(ME, today(), { { ME, CAT, 400 } })
		So():ComputeNow()
		eq(heard, 1)
		A().Bus:Emit("GUILD_CHANGED", "Realm/Other", "TestRealm/Accord")
		isNil(So().state.result)
		isNil(So():ForGUID(ME))
	end)

	it("a guild of 200 accounts and 30 days is computed in steps within a few frames", function()
		local d = today()
		local n = 200
		local function g(i) return ("Player-1-%08X"):format(0x6000 + i) end
		for day = 0, 29 do
			local list = {}
			for i = 1, 100 do
				local a = (i * 7 + day * 13) % n + 1
				local b = (i * 11 + day * 3) % n + 1
				if a ~= b then list[#list + 1] = { g(a), g(b), 30 + (i % 50) } end
			end
			observe(g(day + 1), So().AddDays(d, -day), list)
		end
		local t0 = Mock.RealClock()
		So():ComputeNow()
		local ms = (Mock.RealClock() - t0) * 1000
		T.log(("200 accounts, 30 days, ~3000 pairs: %.0f ms in the offline harness"):format(ms))
		truthy(ms < 3000)
		truthy(So():Active() > 100)
	end)
end)

-- The availability map (M10.8; SPEC-14 §8; SPEC-10 Q23): only the minutes online of this account, per hour of the week,
-- over 8 weeks, in 4 levels; the data set `avail` and its trust rules; at most one record a day; the switch "Share when I
-- usually play" that withdraws it while the local count goes on; counts for everybody, names for officers and the own
-- one for everybody; FDCP's declared days apart, for officers; nothing about raid attendance recorded or sent; the view;
-- the switch "season" off; and the traffic on the simulator (SPEC-09 §7). Every name here is invented.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function AV() return AzerothAccord.Availability end
local function V() return AzerothAccord.AvailabilityView end

local ME, TILDA, ORSO = "Player-1-0000A001", "Player-1-0000B001", "Player-1-0000B002"
local PASTELLO, OFF, GONE = "Player-1-0000B003", "Player-1-0000B009", "Player-1-0000B00F"
local DAY, HOUR = 86400, 3600
local THURSDAY = 1767225600          -- 2026-01-01 00:00, a Thursday: the cell 72

local MEMBERS = {
	{ name = "Tilda", class = "WARRIOR", rank = 3, guid = TILDA },
	{ name = "Orsetto", class = "MAGE", rank = 3, guid = ORSO },
	{ name = "Pastello", class = "PRIEST", rank = 3, guid = PASTELLO },
	{ name = "Ufficiale", class = "PALADIN", rank = 1, guid = OFF },
}

local function setup(myRank, features)
	return function(M)
		M.features = features or { season = true }
		M.guild.Set{ name = "Accord", myRank = myRank or 1, members = MEMBERS }
	end
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function online(minutes)
	for _ = 1, minutes do
		AV():Tick()
		Mock.Advance(60)
	end
end

local function at(t) Mock.SetServerTime(t) end

-- levels with the given cells: { [cell] = level }
local function levelsOf(cells)
	local out = {}
	for h = 0, 167 do out[h] = cells[h] or 0 end
	return out
end

local function put(guid, cells, extra)
	local rec = { id = guid, author = guid, rev = 1, time = GetServerTime(), p = AV().Encode(levelsOf(cells)), w = 8 }
	for k, v in pairs(extra or {}) do rec[k] = v end
	if rec.del then rec.p, rec.w = nil, nil end
	S():Records("avail")[guid] = rec
	A().Bus:Emit("STORE_CHANGED", "avail", guid, "remote")
	Mock.Advance(2)
	return rec
end

describe("the count of the time online", function()
	before_boot(setup(3))

	it("places a date and an hour in a week that starts on Monday", function()
		local week, cell = AV().Cell(THURSDAY / DAY, 0)
		eq(cell, 72)
		local w2, monday = AV().Cell(THURSDAY / DAY + 4, 23)
		eq(monday, 23); eq(w2, week + 1)
		local w3, sunday = AV().Cell(THURSDAY / DAY + 3, 0)
		eq(sunday, 144); eq(w3, week)
	end)

	it("counts one minute in the hour of now, at most 60, and keeps nothing else", function()
		at(THURSDAY + 20 * HOUR)
		online(3)
		local data = AzerothAccordDB.avail
		local week = AV().Now()
		eq(data.since, week)
		eq(data.weeks[week][72 + 20], 3)
		eq(count(data), 2); eq(count(data.weeks), 1); eq(count(data.weeks[week]), 1)
		at(THURSDAY + 20 * HOUR)
		data.weeks[week][92] = 60
		AV():Tick()
		eq(data.weeks[week][92], 60)
	end)

	it("reads the realm's clock when the client says it", function()
		C_DateAndTime = C_DateAndTime or {}
		C_DateAndTime.GetCurrentCalendarTime = function() return { year = 2026, month = 1, monthDay = 5, hour = 21, minute = 7 } end
		local _, cell = AV().Now()
		eq(cell, 21)
	end)

	it("counts the same in a raid: no instance, group or attendance is looked at or kept", function()
		at(THURSDAY + 20 * HOUR)
		Mock.Fire("ENCOUNTER_START", 663, "Boss", 9, 40)
		online(12)
		Mock.Fire("ENCOUNTER_END", 663, "Boss", 9, 40, 1)
		local week = AV().Now()
		eq(AzerothAccordDB.avail.weeks[week][92], 12)
		eq(count(AzerothAccordDB.avail), 2)
		eq(AV():Publish(), true)
		local keys = {}
		for k in pairs(S():Get("avail", ME)) do keys[#keys + 1] = k end
		table.sort(keys)
		eq(table.concat(keys, ","), "author,id,p,rev,time,w")
	end)

	it("runs by itself once started, in a ticker of one minute", function()
		AV().AUTO = true
		truthy(AV():Start())
		falsy(AV():Start())
		at(THURSDAY)
		Mock.Advance(600)
		eq(AzerothAccordDB.avail.weeks[(AV().Now())][72], 10)
	end)

	it("drops damaged values, weeks out of the window and weeks from a clock that ran ahead", function()
		local data = AV().Clean({ since = 9999, weeks = { [100] = { [0] = 30, [200] = 5, [1] = 99, [2] = "x" }, [91] = { [0] = 30 },
			[101] = { [0] = 30 }, [92] = { [3] = 12 }, bad = {} } }, 100)
		eq(data.since, 100)
		eq(count(data.weeks), 2)
		eq(count(data.weeks[100]), 1); eq(data.weeks[92][3], 12)
		eq(count(AV().Clean("broken", 5).weeks), 0)
	end)
end)

describe("the four levels", function()
	before_boot(setup(3))

	-- an account measured from week 93 to week 100, online in cell 10 in the first `n` of those weeks
	local function seen(n, minutes)
		local data = { since = 93, weeks = {} }
		for i = 0, n - 1 do data.weeks[93 + i] = { [10] = minutes or 30 } end
		local levels, weeks = AV().Levels(data, 100, 100)
		return levels[10], weeks, levels
	end

	it("are never, less than one week in four, up to half and more than half of the weeks measured", function()
		local expected = { [0] = 0, 1, 2, 2, 2, 3, 3, 3, 3 }
		for n = 0, 8 do
			local level, weeks = seen(n)
			eq(level, expected[n], n .. " weeks"); eq(weeks, 8)
		end
	end)

	it("count a week only when the account was online ten minutes of that hour", function()
		eq((seen(8, 9)), 0)
		eq((seen(8, 10)), 3)
	end)

	it("look at the last 8 weeks only", function()
		local data = { since = 80, weeks = { [92] = { [10] = 60 } } }
		-- the cell 10 of week 100 is over: the 8 weeks are 93..100
		eq(AV().Levels(data, 100, 100)[10], 0)
		-- not over yet: the 8 weeks are 92..99
		eq(AV().Levels(data, 100, 5)[10], 1)
	end)

	it("do not count an hour of this week before it is over", function()
		local data = { since = 99, weeks = { [99] = { [150] = 30 } } }
		eq(AV().Levels(data, 100, 20)[150], 3)
		eq(AV().Levels(data, 100, 160)[150], 2)
		local levels, weeks = AV().Levels({ since = 100, weeks = { [100] = { [20] = 15 } } }, 100, 20)
		eq(levels[20], 3); eq(weeks, 1)
	end)

	it("fit 42 bytes and come back the same", function()
		local levels = {}
		for h = 0, 167 do levels[h] = (h * 7 + 1) % 4 end
		local p = AV().Encode(levels)
		eq(#p, 42)
		local back = AV().Decode(p)
		for h = 0, 167 do eq(back[h], levels[h], "cell " .. h) end
		isNil(AV().Decode("short")); isNil(AV().Decode(nil))
	end)
end)

describe("publishing", function()
	before_boot(setup(3))

	local function played(hourOfThursday)
		at(THURSDAY + hourOfThursday * HOUR)
		online(10)
	end

	it("says nothing before there is anything to say", function()
		local ok, why = AV():Publish()
		falsy(ok); eq(why, "nothing")
		isNil(S():Get("avail", ME))
	end)

	it("writes only when the levels changed: once a day in the first week measured, then once a week", function()
		played(20)
		eq(AV():Publish(), true)
		local rec = S():Get("avail", ME)
		eq(rec.rev, 1); eq(rec.w, 1)
		eq(AV().Decode(rec.p)[92], 3)
		local _, why = AV():Publish()
		eq(why, "unchanged")
		played(21)
		_, why = AV():Publish()
		eq(why, "recent")
		at(GetServerTime() + DAY + 60)
		eq(AV():Publish(), true)
		eq(S():Get("avail", ME).rev, 2)
		-- a second week measured: not again before seven days
		played(20 + 7 * 24)
		_, why = AV():Publish()
		eq(why, "unchanged")
		played(22 + 7 * 24)
		at(S():Get("avail", ME).time + 6 * DAY)
		_, why = AV():Publish()
		eq(why, "recent")
		at(S():Get("avail", ME).time + 7 * DAY)
		eq(AV():Publish(), true)
		eq(S():Get("avail", ME).rev, 3); eq(S():Get("avail", ME).w, 2)
	end)

	it("writes unchanged levels again before the record expires", function()
		played(20)
		eq(AV():Publish(), true)
		local rec = S():Get("avail", ME)
		rec.time = rec.time - AV().REFRESH_AGE - 1
		eq(AV():Publish(), true)
		eq(S():Get("avail", ME).rev, 2)
	end)

	it("goes by the account's newest record, whichever character wrote it", function()
		S():Records("accounts")[ME] = { id = ME, author = ME, rev = 1, time = GetServerTime(), token = "T",
			chars = { { guid = ME }, { guid = ORSO } } }
		S():Records("accounts")[ORSO] = { id = ORSO, author = ORSO, rev = 1, time = GetServerTime(), token = "T",
			chars = { { guid = ME }, { guid = ORSO } } }
		played(20)
		put(ORSO, { [5] = 3 })
		local _, why = AV():Publish()
		eq(why, "recent")
		isNil(S():Get("avail", ME))
	end)

	it("looks by itself after the first HELLO and then every hour", function()
		AV().AUTO = true
		at(THURSDAY + 20 * HOUR)
		AV():Start()
		Mock.Advance(11 * 60)
		isNil(S():Get("avail", ME), "not before the first check")
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(AV().FIRST_DELAY[2] + 1)
		eq(S():Get("avail", ME).rev, 1)
		Mock.Advance(3600)
		eq(S():Get("avail", ME).rev, 1, "not again within the day")
		Mock.Advance(DAY)
		truthy(S():Get("avail", ME).rev >= 2)
	end)

	it("publishes nothing in demo mode", function()
		played(20)
		Mock.Slash("/accord demo")
		local ok, why = AV():Publish()
		falsy(ok); eq(why, "demo")
		Mock.Advance(2)
		eq(#Mock.errors, 0)
	end)
end)

describe("Share when I usually play", function()
	before_boot(setup(3))

	local function published()
		at(THURSDAY + 20 * HOUR)
		online(10)
		eq(AV():Publish(), true)
	end

	it("is on by default, in Settings and in What I share", function()
		eq(AzerothAccordDB.settings.shareAvailability, true)
		truthy(A().SettingsModel.Visible("shareAvailability"))
		published()
		local row
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "avail" then row = r end end
		notNil(row)
		eq(row.switch, "shareAvailability"); eq(row.on, true); eq(row.records, 1)
		contains(table.concat(row.lines, "\n"), "online at least once: 1")
		A().Shell:OpenView("settings")
		local check = A().SettingsView.frame.checks.shareAvailability
		truthy(check:IsShown()); truthy(check:GetChecked())
		check:Click()
		eq(AzerothAccordDB.settings.shareAvailability, false)
	end)

	it("off: an empty record withdraws the old one, nothing more goes out, the own count goes on", function()
		published()
		truthy(A().ShareModel.SetSwitch("shareAvailability", false))
		Mock.Advance(AV().SWITCH_DELAY + 1)
		local rec = S():Get("avail", ME)
		eq(rec.del, true); isNil(rec.p); isNil(rec.w); eq(rec.rev, 2)
		at(THURSDAY + 2 * DAY)
		online(10)
		AV():Publish()
		eq(S():Get("avail", ME).rev, 2)
		eq(AV():Own()[120], 3, "the own map still counts")
		eq(AV():Map().total, 0)
		local row
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "avail" then row = r end end
		notNil(row.note)
		contains(table.concat(row.lines, "\n"), "Withdrawn")
		truthy(A().ShareModel.SetSwitch("shareAvailability", true))
		Mock.Advance(AV().SWITCH_DELAY + 1)
		eq(S():Get("avail", ME).rev, 3)
		notNil(S():Get("avail", ME).p)
	end)

	it("off from the start: nothing is ever written", function()
		A().Config:Set("account.settings.shareAvailability", false)
		at(THURSDAY + 20 * HOUR)
		online(10)
		local ok, why = AV():Publish()
		falsy(ok); eq(why, "nothing")
		isNil(S():Get("avail", ME))
	end)

	it("takes back a record that comes from the guild while sharing is off", function()
		A().Config:Set("account.settings.shareAvailability", false)
		put(ME, { [1] = 3 })
		Mock.Advance(AV().SWITCH_DELAY + 1)
		eq(S():Get("avail", ME).del, true)
	end)
end)

describe("the records of others", function()
	before_boot(setup(1))

	local function rec(fields)
		local r = { id = TILDA, author = TILDA, rev = 1, time = GetServerTime(), p = AV().Encode(levelsOf{ [92] = 3 }), w = 8 }
		for k, v in pairs(fields or {}) do r[k] = v end
		return r
	end
	local function accept(r, sender) return S():Accept("avail", r, { sender = sender or "Tilda" }) end

	it("are taken first hand or from an officer, never from another member", function()
		local ok, why = accept(rec(), "Orsetto")
		falsy(ok); eq(why, "relay")
		truthy(accept(rec()))
		truthy(accept(rec({ rev = 2 }), "Ufficiale"))
	end)

	it("of another account are refused", function()
		local ok, why = accept(rec({ id = ORSO }))
		falsy(ok); eq(why, "owner")
	end)

	it("hold the levels, the weeks and nothing else", function()
		for _, bad in ipairs({ { p = "x" }, { p = 12 }, { w = 0 }, { w = 9 }, { w = 1.5 }, { raid = 663 }, { attended = true },
			{ zone = "Naxxramas" }, { del = true }, { del = false } }) do
			local ok = accept(rec(bad))
			falsy(ok, next(bad))
		end
		truthy(accept({ id = TILDA, author = TILDA, rev = 2, time = GetServerTime(), del = true }))
	end)

	it("go after 30 days", function()
		local ok, why = accept(rec({ time = GetServerTime() - 31 * DAY }))
		falsy(ok); eq(why, "expired")
		truthy(accept(rec({ time = GetServerTime() - 29 * DAY })))
		at(GetServerTime() + 2 * DAY)
		S():Prune()
		isNil(S():Get("avail", TILDA))
	end)
end)

describe("the guild's map", function()
	before_boot(setup(1))

	local function guild()
		local t = GetServerTime()
		for _, g in ipairs({ ORSO, PASTELLO }) do   -- one account
			S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = t, token = "TO",
				chars = { { guid = ORSO }, { guid = PASTELLO } } }
		end
		A().Accounts:MarkDirty()
		put(TILDA, { [92] = 3, [93] = 1 })
		put(ORSO, { [92] = 3 }, { time = t - DAY })
		put(PASTELLO, { [92] = 2, [93] = 2 })        -- the newer record of that account
		put(OFF, { [92] = 1 })
		put(GONE, { [92] = 3 })                       -- not in the guild
	end

	it("counts accounts, by their newest record, from the level \"up to half\"", function()
		guild()
		local m = AV():Map()
		eq(m.total, 3)
		eq(m.cells[92].n, 2); eq(m.cells[93].n, 1); eq(m.max, 2)
		eq(m.cells[92].levels[1], 1); eq(m.cells[92].levels[2], 1); eq(m.cells[92].levels[3], 1)
		eq(m.cells[0].n, 0)
	end)

	it("hides an account that withdrew", function()
		guild()
		put(PASTELLO, {}, { del = true, rev = 2, time = GetServerTime() + 1 })
		eq(AV():Map().total, 2)
		eq(AV():Map().cells[93].n, 0)
	end)

	it("gives officers the names of a cell, the most often first", function()
		guild()
		local who = AV():Who(92)
		eq(#who, 3)
		eq(who[1].name, "Tilda"); eq(who[1].level, 3); eq(who[3].level, 1)
		local lines = {}
		for _, l in ipairs(V().Lines(V().Model(92))) do lines[#lines + 1] = l.text end
		local text = table.concat(lines, "\n")
		contains(text, "Thursday 20:00-21:00")
		contains(text, "2 members usually online, out of 3 who share")
		contains(text, "Tilda")
		eq(#AV():Who(200), 0)
	end)

	it("shows the grid and follows a click, in both modes", function()
		guild()
		truthy(A().Shell:OpenView("availability"))
		local f = V().frame
		eq(f.grid.cells[92].shade, 4); eq(f.grid.cells[92].label:GetText(), "2")
		eq(f.grid.cells[93].shade, 2); eq(f.grid.cells[0].shade, 0)
		f.grid.cells[93]:Click()
		eq(V().model.cell, 93)
		contains(V().shown[1].text, "Thursday 21:00-22:00")
		at(THURSDAY + 20 * HOUR)
		online(10)
		f.modeSeg.buttons.mine:Click()
		eq(V().model.mode, "mine")
		eq(f.grid.cells[92].shade, 4); eq(f.grid.cells[92].label:GetText(), "")
		eq(f.grid.cells[93].shade, 0)
		Mock.Advance(2)
		eq(#Mock.errors, 0)
	end)

	it("answers /accord availability", function()
		Mock.Slash("/accord availability")
		eq(A().Shell.selected, "availability")
		isNil(A().Shell.views.availability.failed)
	end)
end)

describe("a member", function()
	before_boot(setup(3))

	it("sees the counts and the own entry, never another name", function()
		put(TILDA, { [92] = 3 })
		put(ME, { [92] = 2 })
		eq(AV():Map().cells[92].n, 2)
		local who = AV():Who(92)
		eq(#who, 1); truthy(who[1].own)
		local lines = {}
		for _, l in ipairs(V().Lines(V().Model(92))) do lines[#lines + 1] = l.text end
		local text = table.concat(lines, "\n")
		contains(text, "2 members usually online")
		contains(text, "officers and the Guild Master only")
		falsy(text:find("Tilda", 1, true))
		isNil(AV():Declared())
	end)
end)

describe("with FDCP as the source", function()
	local function withFDCP(rank)
		return function(M)
			setup(rank)(M)
			M.addons.FinlandDragonCreditPoints = { loaded = true, version = "1.0.2" }
			FinlandDragonCreditPointsAPI = {
				API_VERSION = 1, IsReady = function() return true end, GetSource = function() return "LEDGER" end,
				GetPool = function() return { { name = "Tilda-TestRealm", status = "ACTIVE", avail = { "THU", "SUN", "never" } } } end,
				RegisterCallback = function() end, UnregisterCallback = function() end,
			}
		end
	end
	local function choose()
		S():Records("guildcfg").sources = { id = "sources", author = OFF, rev = 1, time = GetServerTime(), raid = "fdcp", loot = "none" }
		A().Integrations:Refresh()
		A().Bus:Emit("SOURCES_CHANGED")
		Mock.Advance(2)
	end

	describe("an officer", function()
		before_boot(withFDCP(1))

		it("reads the declared days apart, labelled as a declaration", function()
			isNil(AV():Declared(), "Accord is the source")
			choose()
			local d = AV():Declared()
			eq(d[4][1], "Tilda"); eq(d[7][1], "Tilda"); eq(#d[1], 0)
			local lines = {}
			for _, l in ipairs(V().Lines(V().Model(92))) do lines[#lines + 1] = l.text end
			local text = table.concat(lines, "\n")
			contains(text, "Declared in FDCP for Thursday")
			contains(text, "not a measurement")
			eq(AV():Map().total, 0, "nothing of it enters the map")
			isNil(S():Get("avail", ME))
		end)
	end)

	describe("a member", function()
		before_boot(withFDCP(3))

		it("sees none of them", function()
			choose()
			isNil(AV():Declared())
		end)
	end)
end)

describe("the availability map with the switch season off", function()
	before_boot(setup(1, { season = false }))

	it("counts nothing, takes and sends nothing, and shows nothing", function()
		AV().AUTO = true
		falsy(AV():Start())
		falsy(AV():Tick())
		isNil(AzerothAccordDB.avail)
		local ok, why = AV():Publish()
		falsy(ok); eq(why, "off")
		A().Bus:Emit("SYNC_HELLO", true)
		A().Bus:Emit("SETTINGS_CHANGED", "shareAvailability")
		Mock.Advance(600)
		falsy(S().IsActive("avail"))
		isNil((S():Put("avail", ME, { del = true })))
		ok, why = S():Accept("avail", { id = TILDA, author = TILDA, rev = 1, time = GetServerTime(), del = true }, { sender = "Tilda" })
		falsy(ok); eq(why, "set")
		Mock.Slash("/accord availability")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Unknown command 'availability'")
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "availability") end
		falsy(A().SettingsModel.Visible("shareAvailability"))
		for _, r in ipairs(A().ShareModel.Describe()) do truthy(r.id ~= "avail") end
		A().Shell:OpenView("settings")
		falsy(A().SettingsView.frame.checks.shareAvailability:IsShown())
		eq(count(S():Records("avail")), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator
---------------------------------------------------------------------------------------------------------------------
-- A count of three weeks, different for every client: about 30 hours a week.
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

describe("the availability map between clients", function()
	local function simulated(Mk) Mk.features = { season = true } end

	it("reaches the guild, and a withdrawal does too", function()
		local sim = Sim.new{ clients = 4, officers = { 1 }, offline = { 4 }, setup = simulated, availability = true, accounts = true, seed = 11 }
		for i = 1, 3 do seed(sim, sim:client(i)) end
		sim:advance(400)
		local function holds(j, i) return sim:client(j):addon().Store:Get("avail", Sim.guidOf(i)) end
		for i = 1, 3 do
			for j = 1, 3 do notNil(holds(j, i), j .. " holds " .. i) end
		end
		sim:client(4):login()
		truthy(sim:advanceUntil(function() return holds(4, 1) and holds(4, 2) and holds(4, 3) end, 25 * 60), "the newcomer")
		eq(sim:client(4):addon().Availability:Map().total >= 3, true)
		sim:client(2):addon().SettingsModel.Set("shareAvailability", false)
		sim:advance(60)
		for _, j in ipairs({ 1, 3, 4 }) do eq(holds(j, 2).del, true, "client " .. j) end
		for i = 1, 4 do eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i) end
	end)

	-- 50 clients, the 45 minutes of churn of Tests/test_sync_sim.lua (the same writes, logins, logouts and lockdowns).
	-- `with`: the availability map too. `established`: everybody has been online and in sync before the churn, maps
	-- included, and during it one account in seven has a new map to publish (a whole day's worth, at one a week each,
	-- squeezed into 45 minutes); otherwise half the guild never ran and nobody has anybody's map: the first exchange.
	local function churn(with, established)
		local N, OFFICERS = 50, { 1, 11, 21, 31, 41 }
		local offline = {}
		for i = 2, N, 2 do offline[#offline + 1] = i end
		local sim = Sim.new{ clients = N, officers = OFFICERS, setup = simulated, offline = not established and offline or nil,
			availability = with, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42 }
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
				if with then seed(sim, c) end
			end
		end
		if established then
			sim:advance(30 * 60)
			if with then
				for i = 1, N do
					eq(sim:client(i):addon().Store:Count("avail"), N, "client " .. i .. " holds every map before the churn")
				end
			end
			for i = 2, N, 2 do sim:client(i):logout() end
			sim:resetStats()
		end
		local changed = {}
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
					if with then seed(sim, c) end
					if not writes[i] then writeNext(c) end
				end
				if lockUntil[i] and sim.time >= lockUntil[i] then
					c:restrict({ lockdown = false })
					lockUntil[i] = nil
				end
				-- a week has passed for this account: its map changed and is due
				if with and established and i % 7 == 0 and not changed[i] and step >= i and c.online then
					changed[i] = true
					local AV_ = c:addon().Availability
					local levels = {}
					for h = 0, 167 do levels[h] = (h + i) % 5 == 0 and 3 or 0 end
					truthy(c:addon().Store:Put("avail", c:guid(), { p = AV_.Encode(levels), w = 4 }))
				end
			end
			sim:advance(30)
		end
		local st = sim:stats()
		for i = 1, N do
			local c = sim:client(i)
			if c.online then eq(c:addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing") end
		end
		return st, count(changed)
	end

	local function report(label, st, base)
		T.log(("availability, %s: churn %.0f B/min per client on average (%.0f without the map), %.0f at most (%.0f)"):format(
			label, st.avg.bytesPerMinute, base.avg.bytesPerMinute, st.max.bytesPerMinute, base.max.bytesPerMinute))
	end

	it("50 clients of a guild in step stay inside the shared traffic budget (SPEC-09 §7)", function()
		local base = churn(false, true)
		local st, changed = churn(true, true)
		report("a guild in step", st, base)
		truthy(changed >= 5, "maps changed " .. changed)
		truthy(st.avg.bytesPerMinute <= 450, "churn average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2048, "churn busiest client " .. st.max.bytesPerMinute)
		truthy(st.avg.bytesPerMinute - base.avg.bytesPerMinute <= 100, "added " .. (st.avg.bytesPerMinute - base.avg.bytesPerMinute))
	end)

	-- The first exchange does not fit the 450 B/min of the budget: it is measured here.
	-- The owner accepted it (SPEC-10 Q26, 2026-11-26): up to about 550 B/min on average while the maps are first
	-- exchanged; the bound of the busiest client only keeps the measured peak from growing (R17).
	it("measures the first exchange of the maps of 50 members, inside the peak the owner accepted (SPEC-10 Q26)", function()
		local base = churn(false, false)
		local st = churn(true, false)
		report("first exchange", st, base)
		truthy(st.avg.bytesPerMinute <= 550, "first exchange average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2560, "first exchange busiest client " .. st.max.bytesPerMinute)
	end)
end)

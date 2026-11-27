-- PvP and world rallies (M10.9; SPEC-14 §9; SPEC-10 Q24): a rally expires by itself on every client; no coordinate and no
-- map ever travels, and the player's position is never read; one open rally per character and at most 4 an hour, held by
-- the caller and again by every receiver; the start within 2 hours, 15 minutes to 2 hours long; only the caller changes
-- or closes it and an officer cannot send one for another; answers visible to everyone; the set is short-lived (never in
-- a summary), RASK brings the open rallies to who comes later; the notice, the Action Center and the Rallies page; the
-- traffic of 50 clients; and the switch "season" off.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function R() return AzerothAccord.Rallies end
local function V() return AzerothAccord.RalliesView end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 30, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
	} }
end

local function on(Mk) Mk.features = { season = true } guild(3) end
local function off(Mk) Mk.features = { season = false, raid = false } guild(3) end

local function capture()
	local out, T_ = {}, A().Transport
	local original = T_.Send
	T_.Send = function(self, dist, msg, opts)
		out[#out + 1] = { dist = dist, msg = msg, target = opts and opts.target }
		return original(self, dist, msg, opts)
	end
	return out
end

local function hear(msg, sender, dist) A().Bus:Emit("NET_MESSAGE", msg, sender, dist or "GUILD") end

-- A rally as its caller's client would write it.
local function rally(author, n, fields)
	local t = GetServerTime()
	local rec = { id = author .. ":" .. (n or 1), author = author, rev = 1, time = t, kind = "pvp", text = "the crossroads",
		created = t, start = t + 900, ends = t + 2700 }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

local function answer(author, rallyID, value, fields)
	local t = GetServerTime()
	local rec = { id = rallyID .. ":" .. author, author = author, rev = 1, time = t, answer = value or "yes", ends = t + 2700 }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

local function call(spec)
	local s = { kind = "pvp", text = "the crossroads", ahead = 900, duration = 1800 }
	for k, v in pairs(spec or {}) do s[k] = v end
	return R():Call(s)
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

describe("rallies with the switch `season` off", function()
	before_boot(off)

	it("takes, sends and shows nothing", function()
		falsy(S().IsActive("rally"))
		local sent = capture()
		local ok, why = call()
		falsy(ok); eq(why, "off")
		isNil((S():Put("rally", ME .. ":1", rally(ME))))
		eq(select(2, S():Check("rally", rally(BOB), { sender = "Bob", dist = "GUILD" })), "set")
		hear({ t = "RASK", h = "" }, "Bob")
		falsy(R():Ask())
		falsy(R():Answer(BOB .. ":1", "yes"))
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(300)
		for _, e in ipairs(sent) do truthy(e.msg.t ~= "RASK" and e.msg.s ~= "rally") end
		eq(#R():List(), 0)
		isNil(R().ticker)
		falsy(A().Diagnostics.Report():find("Rallies:", 1, true))
		for _, r in ipairs(A().ShareModel.Describe()) do truthy(r.id ~= "rally") end
		for _, row in ipairs(A().Actions:Rows()) do truthy(row.provider ~= "rally") end
		falsy(V():Open())
	end)
end)

describe("the owner rule of a rally", function()
	before_boot(on)

	it("accepts a well formed rally and answer, and refuses every bad field", function()
		local t = GetServerTime()
		truthy(R().ValidRecord(rally(BOB)))
		truthy(R().ValidRecord(rally(BOB, 2, { kind = "world", closed = true, start = t, ends = t + 900 })))
		truthy(R().ValidRecord(rally(BOB, 3, { start = t + 7200, ends = t + 14400, text = "alle porte della città" })))
		truthy(R().ValidRecord(answer(ANN, BOB .. ":1", "no")))
		local bad = {
			{ id = ANN .. ":1" }, { id = BOB .. ":x" }, { id = BOB }, { kind = "raid" }, { text = "" }, { text = ("x"):rep(61) },
			{ text = "a|cffff0000b" }, { text = " padded" }, { text = "a\nb" }, { created = t + 301, start = t + 301, ends = t + 2000 },
			{ start = t - 1 }, { start = t + 7201, ends = t + 9000 }, { ends = t + 900 + 899 }, { ends = t + 900 + 7201 },
			{ time = t - 10 }, { closed = false }, { closed = "yes" }, { rev = 101 },
			-- no coordinate and no map: the record takes no field it does not know
			{ x = 0.5 }, { y = 0.5 }, { map = 1413 }, { position = "52,31" },
		}
		for i, change in ipairs(bad) do falsy(R().ValidRecord(rally(BOB, 1, change)), "bad field " .. i) end
		for i, change in ipairs({ { answer = "maybe" }, { id = BOB .. ":1:" .. BOB }, { ends = t + 20000 }, { rev = 21 },
			{ x = 1 }, { text = "here" } }) do
			falsy(R().ValidRecord(answer(ANN, BOB .. ":1", "yes", change)), "bad answer " .. i)
		end
	end)

	it("takes a record only from its author's account: an officer cannot send one for another", function()
		eq(S():Receive("rally", { rally(BOB) }, "Bob", "GUILD"), 1)
		eq(select(2, S():Check("rally", rally(ANN), { sender = "Boss", dist = "GUILD" })), "relay")
		eq(select(2, S():Check("rally", rally(BOB, 1, { rev = 2, closed = true }), { sender = "Boss", dist = "GUILD" })), "relay")
		eq(select(2, S():Check("rally", answer(ANN, BOB .. ":1"), { sender = "Boss", dist = "GUILD" })), "relay")
		falsy(R():Close(BOB .. ":1"))
		falsy(R():Update(BOB .. ":1", { text = "elsewhere" }))
	end)

	it("keeps the set out of the sync summary", function()
		eq(S():Receive("rally", { rally(BOB) }, "Bob", "GUILD"), 1)
		A().Sync:Invalidate()
		isNil(A().Sync:Groups()[BOB])
		truthy(S().IsVolatile("rally"))
	end)
end)

describe("calling a rally", function()
	before_boot(on)

	it("starts within 2 hours and lasts 15 minutes to 2 hours", function()
		eq(select(2, call({ ahead = 7201 })), "start")
		eq(select(2, call({ ahead = -1 })), "start")
		eq(select(2, call({ duration = 899 })), "duration")
		eq(select(2, call({ duration = 7201 })), "duration")
		eq(select(2, call({ text = "  " })), "text")
		eq(select(2, call({ kind = "raid" })), "kind")
		local rec = call({ ahead = 0, duration = 900, text = "  the |dock " })
		eq(rec.text, "the dock"); eq(R():Status(rec), "on")
	end)

	it("takes the longest meeting point from the longest character id", function()
		Mock.player.guid = "Player-12345-0A1B2C3D4E"
		local rec = call({ text = ("à"):rep(30) })
		eq(#rec.text, 60)
		truthy(R():Close(rec.id), "also once closed")
		Mock.player.guid = ME
	end)

	it("keeps one open rally per character and allows 4 an hour", function()
		local first = call()
		Mock.Advance(20)
		local second = call({ text = "the bridge" })
		eq(R():Status(S():Get("rally", first.id)), "closed")
		eq(R():Own().id, second.id)
		eq(#R():List(), 2, "the closed one still shows for a while")
		truthy(call()); truthy(call())
		eq(select(2, call()), "limit")
		Mock.Advance(3601)
		truthy(call())
	end)

	it("lets the caller change it, with the start still within 2 hours of the call", function()
		local rec = call()
		eq(select(2, R():Update(rec.id, { text = "x" })), "wait")
		Mock.Advance(11)
		local changed = R():Update(rec.id, { text = "the bridge", kind = "world" })
		eq(changed.text, "the bridge"); eq(changed.kind, "world"); eq(changed.start, rec.start); eq(changed.ends, rec.ends)
		Mock.Advance(11)
		eq(select(2, R():Update(rec.id, { ahead = 7200 })), "start")
		changed = R():Update(rec.id, { ahead = 60, duration = 900 })
		eq(changed.start, GetServerTime() + 60); eq(changed.ends, changed.start + 900)
		truthy(R():Close(rec.id))
		eq(select(2, R():Update(rec.id, { text = "x" })), "status")
		isNil(R():Own())
	end)
end)

describe("expiry", function()
	before_boot(on)

	it("ends by itself, then goes with its answers, without any message", function()
		eq(S():Receive("rally", { rally(BOB, 1, { start = GetServerTime(), ends = GetServerTime() + 900 }) }, "Bob", "GUILD"), 1)
		eq(S():Receive("rally", { answer(ANN, BOB .. ":1", "yes", { ends = GetServerTime() + 900 }) }, "Ann", "GUILD"), 1)
		truthy(R():Answer(BOB .. ":1", "no"))
		local sent = capture()
		Mock.Advance(10)
		for i = #sent, 1, -1 do sent[i] = nil end
		eq(R():List()[1].status, "on")
		eq(#R():Answers(BOB .. ":1").yes, 1)
		eq(#R():Answers(BOB .. ":1").no, 1)
		Mock.Advance(900)
		eq(R():List()[1].status, "expired")
		eq(select(2, R():Answer(BOB .. ":1", "yes")), "status")
		Mock.Advance(R().GRACE + 31)
		eq(#R():List(), 0)
		eq(count(S():Records("rally")), 0, "the rally and its answers are gone")
		for _, e in ipairs(sent) do truthy(e.msg.s ~= "rally" and e.msg.t ~= "RASK") end
		eq(S():Receive("rally", { rally(BOB, 1, { created = GetServerTime() - 4000, start = GetServerTime() - 3000,
			ends = GetServerTime() - 2000 }) }, "Bob", "GUILD"), 0, "an old one is not taken again")
	end)

	it("keeps the answers of a rally the caller made longer", function()
		local t = GetServerTime()
		S():Receive("rally", { rally(BOB, 1, { start = t, ends = t + 900 }) }, "Bob", "GUILD")
		S():Receive("rally", { answer(ANN, BOB .. ":1", "yes", { ends = t + 900 }) }, "Ann", "GUILD")
		S():Receive("rally", { rally(BOB, 1, { rev = 2, created = t, start = t, ends = t + 7200 }) }, "Bob", "GUILD")
		Mock.Advance(900 + R().GRACE + 31)
		eq(#R():Answers(BOB .. ":1").yes, 1)
	end)

	it("counts only the newest rally of a caller, and no more than 4 an hour, on the receiver too", function()
		local t = GetServerTime()
		for n = 1, 6 do
			S():Receive("rally", { rally(BOB, n, { created = t - 60 + n, start = t + 900, ends = t + 2700, time = t }) }, "Bob", "GUILD")
		end
		eq(#R():List(), 0, "the fifth and sixth are over the limit, the older ones are replaced")
		eq(R():Status(S():Get("rally", BOB .. ":6")), "limit")
		eq(R():Status(S():Get("rally", BOB .. ":4")), "replaced")
		S():Receive("rally", { rally(ANN, 1) }, "Ann", "GUILD")
		eq(#R():List(), 1)
	end)
end)

describe("no position", function()
	before_boot(on)

	it("never reads the player's position and sends only the fields of the record", function()
		local read = 0
		local function spy() read = read + 1 end
		C_Map = { GetBestMapForUnit = spy, GetPlayerMapPosition = spy }
		UnitPosition = spy
		local sent = capture()
		local rec = call()
		Mock.Advance(10)
		A().Bus:Emit("SYNC_HELLO", true)
		R():Ask()
		Mock.Advance(10)
		V():Open(rec.id)
		Mock.Advance(10)
		eq(read, 0, "no position call")
		local allowed = { id = true, author = true, rev = true, time = true, kind = true, text = true, created = true,
			start = true, ends = true, closed = true }
		local seen = 0
		for _, e in ipairs(sent) do
			if e.msg.s == "rally" then
				for _, r in ipairs(e.msg.r) do
					seen = seen + 1
					for k in pairs(r) do truthy(allowed[k], "field " .. k) end
				end
			end
		end
		truthy(seen > 0, "the rally went out")
		C_Map, UnitPosition = nil, nil
	end)
end)

describe("notices, the Action Center and the page", function()
	before_boot(on)

	it("posts one notice for a new rally of somebody else, and a row while it is open", function()
		Mock.Advance(300)   -- past the grouping of the notices after a login
		local t = GetServerTime()
		S():Receive("rally", { rally(BOB) }, "Bob", "GUILD")
		Mock.Advance(10)
		local posted = {}
		for _, e in ipairs(A().Notify:Entries()) do if e.module == "rally" then posted[#posted + 1] = e end end
		eq(#posted, 1)
		eq(posted[1].page, "rallies")
		contains(table.concat(Mock.PlainOutput(), "\n"), "the crossroads")
		S():Receive("rally", { rally(BOB, 1, { rev = 2, created = t, start = t + 900, ends = t + 2700, text = "the bridge" }) },
			"Bob", "GUILD")
		Mock.Advance(10)
		local n = 0
		for _, e in ipairs(A().Notify:Entries()) do if e.module == "rally" then n = n + 1 end end
		eq(n, 1, "a change posts nothing more")
		local rows = R():ActionRows()
		eq(#rows, 1); contains(rows[1].title, "the bridge")
		Mock.Advance(3000)
		eq(#R():ActionRows(), 0)
	end)

	it("posts nothing for the own rally", function()
		call()
		Mock.Advance(10)
		for _, e in ipairs(A().Notify:Entries()) do truthy(e.module ~= "rally") end
		eq(#R():ActionRows(), 1)
	end)

	it("shows the page (a page of Groups since M13.7), answers from it and calls from it", function()
		S():Receive("rally", { rally(BOB) }, "Bob", "GUILD")
		truthy(V():Open(BOB .. ":1"))
		eq(A().Shell.selected, "rallies")
		eq(A().Shell.content.dest, "groups")
		isNil(A().Shell.views.rallies.failed)
		local f = V().frame
		truthy(f.yes:IsShown()); falsy(f.close:IsShown())
		truthy(V():Answer("yes"))
		eq(R():Mine(BOB .. ":1"), "yes")
		local lines = {}
		for _, l in ipairs(V().shown) do lines[#lines + 1] = l.text end
		local text = table.concat(lines, "\n")
		contains(text, "PvP rally: the crossroads"); contains(text, "Coming: 1"); contains(text, "Not coming: 0")
		truthy(V():Call({ kind = "world", text = "the gate", ahead = 0, duration = 900 }))
		truthy(f.close:IsShown()); truthy(f.change:IsShown())
		falsy(f.yes:IsShown(), "no answer to the own rally")
		truthy(V():Close())
		isNil(R():Own())
		truthy(A().EventsView:ShowPage("events"))
		isNil(A().Shell.views.events.failed)
	end)

	it("lists the own rally and answers in What I share", function()
		call()
		S():Receive("rally", { rally(BOB) }, "Bob", "GUILD")
		R():Answer(BOB .. ":1", "no")
		local row
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "rally" then row = r end end
		notNil(row)
		eq(#row.lines, 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator
---------------------------------------------------------------------------------------------------------------------
local function enabled(Mk) Mk.features = { season = true } end

describe("rallies between clients", function()
	it("reach everyone with their answers, expire everywhere and come to who logs in later", function()
		local sim = Sim.new{ clients = 5, offline = { 5 }, officers = { 1 }, setup = enabled, latency = { 0.05, 0.3 }, seed = 3,
			rallies = true }
		sim:advance(40)
		local rec = sim:client(2):addon().Rallies:Call({ kind = "pvp", text = "the crossroads", ahead = 600, duration = 900 })
		sim:advance(10)
		truthy(sim:client(3):addon().Rallies:Answer(rec.id, "yes"))
		truthy(sim:client(4):addon().Rallies:Answer(rec.id, "no"))
		sim:advance(10)
		for i = 1, 4 do
			local a = sim:client(i):addon().Rallies:Answers(rec.id)
			eq(#a.yes, 1, "client " .. i); eq(#a.no, 1, "client " .. i)
		end
		sim:client(5):login()
		sim:advance(120)   -- the first HELLO, then one RASK by itself: the rallies only
		local late = sim:client(5):addon().Rallies
		eq(late.state.stats.asks, 1)
		eq(#late:List(), 1)
		eq(#late:Answers(rec.id).yes, 0)
		eq(sim:client(3):addon().Rallies.state.stats.asksAnswered, 0, "only the caller answers at a login")
		truthy(late:Ask(true))   -- what opening the page does
		sim:advance(15)
		eq(#late:Answers(rec.id).yes, 1); eq(#late:Answers(rec.id).no, 1)
		eq(select(2, late:Ask(true)), "recent")
		eq(sim:client(1):addon().Rallies.state.stats.asksAnswered, 0, "a client with nothing of its own stays quiet")
		sim:advance(600 + 900 + 700)
		for i = 1, 5 do
			eq(sim:client(i):addon().Store:Count("rally"), 0, "client " .. i)
			eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i)
		end
	end)

	it("refuses a rally an officer forged for another caller, on every client", function()
		local sim = Sim.new{ clients = 4, officers = { 1 }, setup = enabled, seed = 5 }
		sim:advance(40)
		local officer = sim:client(1):addon()
		local t = officer.Compat.ServerTime()
		local forged = { id = Sim.guidOf(2) .. ":1", author = Sim.guidOf(2), rev = 1, time = t, kind = "pvp", text = "Fake",
			created = t, start = t, ends = t + 900 }
		officer.Transport:Send("GUILD", { t = "REC", s = "rally", r = { forged } })
		sim:advance(5)
		for i = 2, 4 do
			local Sc = sim:client(i):addon().Store
			isNil(Sc:Get("rally", forged.id), "client " .. i)
			eq(Sc.stats.reasons.relay, 1)
		end
	end)

	it("waits for the end of a boss encounter", function()
		local sim = Sim.new{ clients = 3, setup = enabled, seed = 7 }
		sim:advance(40)
		sim:client(1).Mock.Fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
		local rec = sim:client(1):addon().Rallies:Call({ kind = "world", text = "the gate" })
		sim:advance(30)
		isNil(sim:client(2):addon().Store:Get("rally", rec.id))
		sim:client(1).Mock.Fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
		sim:advance(10)
		notNil(sim:client(2):addon().Store:Get("rally", rec.id))
	end)
end)

describe("the traffic of the rallies (SPEC-09 §7)", function()
	local N, OFFICERS = 50, { 1, 11, 21, 31, 41 }

	-- 50 clients, 45 minutes with logins and logouts. `with`: a rally every 5 minutes (9 in all, 3 times what an evening
	-- is likely to see), 25 answers to each over its first 3 minutes, and who logs in asks (the notice is on by default).
	local function churn(with)
		local sim = Sim.new{ clients = N, officers = OFFICERS, setup = enabled, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42,
			rallies = with }
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		sim:advance(10 * 60)
		sim:resetStats()
		local current, calls, answers = nil, 0, 0
		for half = 0, 89 do
			if with and half % 10 == 0 then
				local c = sim:client(1 + half / 10 * 5)
				if not c.online then c:login() end
				local rec = c:addon().Rallies:Call({ kind = "pvp", text = "the crossroads, north road", ahead = 600, duration = 1800 })
				if rec then current, calls = rec.id, calls + 1 end
			end
			for i = 1, N do
				local c = sim:client(i)
				local r = rand()
				if c.online then
					if r < 0.02 then c:logout() end
				elseif r < 0.06 then
					c:login()
				end
			end
			if with and current and half % 10 >= 1 and half % 10 <= 5 then
				for _ = 1, 5 do
					local c = sim:client(1 + math.floor(rand() * N))
					if c.online and c:addon().Rallies:Answer(current, rand() < 0.6 and "yes" or "no") then answers = answers + 1 end
				end
			end
			sim:advance(30)
		end
		local st = sim:stats()
		local asks = 0
		for i = 1, N do
			local c = sim:client(i)
			if c.online then
				eq(c:addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing")
				asks = asks + c:addon().Rallies.state.stats.asks
			end
		end
		return st, calls, answers, sim
	end

	it("adds little to the shared budget with 9 rallies and their answers in 45 minutes", function()
		local base = churn(false)
		local st, calls, answers, sim = churn(true)
		T.log(("rallies: %.0f B/min per client on average (%.0f without), %.0f at most (%.0f); %d calls, %d answers"):format(
			st.avg.bytesPerMinute, base.avg.bytesPerMinute, st.max.bytesPerMinute, base.max.bytesPerMinute, calls, answers))
		eq(calls, 9)
		truthy(answers >= 120, "answers " .. answers)
		truthy(st.avg.bytesPerMinute - base.avg.bytesPerMinute <= 100, "added " .. (st.avg.bytesPerMinute - base.avg.bytesPerMinute))
		truthy(st.avg.bytesPerMinute <= 450, "average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2048, "busiest " .. st.max.bytesPerMinute)
	end)

	-- What one rally with 48 answers costs: the answers themselves, and one question of each kind. Every figure is what
	-- the 50 clients send in that window, less what they send in the same window of a quiet guild.
	it("keeps the cost of a question after a login small, and answers it fully when the page opens", function()
		local sim = Sim.new{ clients = N, offline = { N }, officers = OFFICERS, setup = enabled, latency = { 0.05, 0.5 }, seed = 21,
			rallies = true }
		sim:setStep(0.5)
		sim:advance(20 * 60)
		local function window(act)
			sim:resetStats()
			act()
			sim:advance(60)
			return sim:stats().sent.bytes
		end
		local quiet = window(function() end)
		local rec
		window(function() rec = sim:client(1):addon().Rallies:Call({ kind = "pvp", text = "the crossroads, north road" }) end)
		local answered = window(function()
			for i = 2, N - 1 do truthy(sim:client(i):addon().Rallies:Answer(rec.id, "yes")) end
		end)
		sim:client(N):login()
		sim:advance(10 * 60)
		local late = sim:client(N):addon().Rallies
		late.state.askedAt = {}
		for id in pairs(sim:client(N):addon().Store:Records("rally")) do sim:client(N):addon().Store:Records("rally")[id] = nil end
		sim:advance(5 * 60)
		quiet = window(function() end)
		local short = window(function() truthy(late:Ask(false)) end)
		eq(#late:List(), 1)
		eq(#late:Answers(rec.id).yes, 0)
		local full = window(function() truthy(late:Ask(true)) end)
		eq(#late:Answers(rec.id).yes, N - 2)
		T.log(("rallies: in 60 s the guild sends %.0f bytes when quiet, %.0f with 48 answers, %.0f with a question after a login, %.0f with the page opened"):format(
			quiet, answered, short, full))
		truthy(short - quiet <= 1500, "login question " .. (short - quiet))
		truthy(full - quiet <= 49 * 250 + 1000, "page question " .. (full - quiet))
		truthy(answered - quiet <= 48 * 250, "answers " .. (answered - quiet))
	end)
end)

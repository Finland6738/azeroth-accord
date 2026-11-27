-- The guild goals (M13.9; SPEC-17 §7; SPEC-10 Q48, Q56): who writes them and what stays locked; the progress as the sum
-- of the deposits of the merged bank logs, the same on every client; a goal closed when reached or at its end date; a
-- member who sees fewer tabs; at most five open; the demand; one notice; the Goals page and its window; What I share,
-- /accord debug and the demo; the switch "econ"; between clients and with an older client.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function G() return AzerothAccord.Goals end
local function V() return AzerothAccord.GoalsView end

local ME = "Player-1-0000A001"
local OFF, BOB, ANN, ALT = "Player-1-000000FF", "Player-1-00000B0B", "Player-1-00000A77", "Player-1-00000A17"
local LINEN, SILK = 2589, 4306
local DAY, HOUR, GOLD = 86400, 3600, 10000

local function setup(myRank, features)
	return function(M)
		M.features = features or { econ = true }
		M.items.info[LINEN] = { name = "Linen Cloth" }
		M.items.info[SILK] = { name = "Silk Cloth" }
		M.items.cached[LINEN], M.items.cached[SILK] = true, true
		M.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
			{ name = "Officer", rank = 1, guid = OFF, level = 60, class = "PRIEST", online = true },
			{ name = "Bob", rank = 3, guid = BOB, level = 60, class = "MAGE", online = true },
			{ name = "Ann", rank = 3, guid = ANN, level = 50, class = "DRUID", online = false },
			{ name = "Alt", rank = 4, guid = ALT, level = 10, class = "ROGUE", online = true },
		} }
	end
end

local function now() return GetServerTime() end
local function dayOf(t) return A().Timeline.DayOf(t) end
local NAME = { [OFF] = "Officer", [BOB] = "Bob", [ANN] = "Ann", [ALT] = "Alt" }
local function must(rec, why) truthy(rec, tostring(why)) return rec end
local function printed() return table.concat(Mock.PlainOutput(), "\n") end

local function goal(author, n, fields)
	local r = { id = "G:" .. (1000 + (n or 1)), author = author, rev = 1, time = now(), kind = "items", item = LINEN,
		target = 100, start = dayOf(now()), ends = dayOf(now() + 30 * DAY), title = "Linen", state = "open" }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

local function accept(rec, sender) return S():Accept("goals", rec, { sender = NAME[sender or rec.author], dist = "GUILD" }) end

local function refused(rec, sender, why)
	local ok, w = accept(rec, sender)
	eq(ok, false, "refused: " .. tostring(why))
	eq(w, why)
end

local function entry(kind, name, item, count, t) return { kind = kind, name = name, itemID = item, count = count, t = t or now() } end

-- The log of one tab (0: money) as `author` read it, put straight in the store.
local function logRec(author, tab, entries, fields)
	local id = author .. ":log:" .. tab
	local r = { id = id, author = author, rev = 1, time = now(), kind = "log", tab = tab, rank = tab > 0 and 4 or nil,
		e = A().BankLog.Encode(entries), n = #entries }
	for k, v in pairs(fields or {}) do r[k] = v end
	S():Records("bank")[id] = r
	return r
end

local function create(spec)
	spec = spec or {}
	spec.kind, spec.title = spec.kind or "items", spec.title or "Linen"
	if spec.kind == "items" then spec.item = spec.item or LINEN end
	spec.target = spec.target or 100
	return must(G():Create(spec))
end

-- Every function of the game that moves gold or items fails the test when called (ECO-01).
local function forbidTrade()
	for _, name in ipairs({ "InitiateTrade", "AcceptTrade", "SendMail", "TakeInboxItem", "PlaceAuctionBid",
		"DepositGuildBankMoney", "WithdrawGuildBankMoney", "PickupContainerItem", "PickupGuildBankItem" }) do
		_G[name] = function() fail("called " .. name) end
	end
end

---------------------------------------------------------------------------------------------------------------------
describe("the records of the goals (SPEC-17 §7.1)", function()
	before_boot(setup(3))

	it("takes a goal from an officer only (NET-12), also after the author was demoted", function()
		truthy(accept(goal(OFF)))
		refused(goal(BOB, 2), BOB, "authority")
		refused(goal(OFF, 3), BOB, "authority")
		truthy(accept(goal(BOB, 4), OFF))   -- an officer passes on the goal of somebody who is not one now
		eq(select(2, G():Create({ kind = "gold", target = 5, title = "x" })), "authority")
		falsy(G().CanWrite())
	end)

	it("refuses a shape that is not a goal's", function()
		for what, fields in pairs({
			id = { id = "G:x" }, kind = { kind = "silver" }, noItem = { kind = "items", target = 5, item = 0 },
			none = { target = 0 }, many = { target = 100001 }, frac = { target = 1.5 },
			goldItem = { kind = "gold", target = GOLD }, start = { start = 20261340 },
			same = { ends = dayOf(now()) }, far = { ends = dayOf(now() + 181 * DAY) }, noTitle = { title = "" },
			title = { title = ("t"):rep(41) }, bar = { title = "|c" }, note = { note = ("n"):rep(121) },
			state = { state = "reached" }, extra = { have = 5 },
		}) do
			local ok, why = accept(goal(OFF, 1, fields))
			eq(ok, false, what); eq(why, "owner", what)
		end
		for what, target in pairs({ small = GOLD - 1, part = GOLD + 1, big = 1000001 * GOLD }) do
			local rec = goal(OFF, 2, { kind = "gold", target = target })
			rec.item = nil
			eq(select(2, accept(rec)), "owner", what)
		end
		truthy(accept(goal(OFF, 3, { ends = dayOf(now() + 180 * DAY), title = ("t"):rep(40), note = ("n"):rep(120) })))
	end)

	it("holds the longest record inside its size", function()
		local long = "Player-1234-0ABCDEF123456789"
		local r = { id = "G:4294967295", author = long, rev = 2147483647, time = now(), kind = "items", item = 2147483647,
			target = 100000, start = 20990101, ends = 20990601, title = ("t"):rep(40), note = ("n"):rep(120), state = "cancelled" }
		truthy(A().Config.EstimateSize(r) <= G().BYTES, "size " .. A().Config.EstimateSize(r))
		eq(S().SETS.goals.maxBytes, G().BYTES)
	end)

	it("changes only the title, the note, a later end and the cancellation", function()
		local g = goal(OFF)
		truthy(accept(g))
		for what, fields in pairs({ item = { item = SILK }, target = { target = 99 }, start = { start = dayOf(now() - DAY) },
			earlier = { ends = dayOf(now() + 10 * DAY) } }) do
			local f = { rev = 2 }
			for k, v in pairs(fields) do f[k] = v end
			local ok, why = accept(goal(OFF, 1, f))
			eq(ok, false, what); eq(why, "locked", what)
		end
		truthy(accept(goal(OFF, 1, { rev = 2, title = "More linen", note = "Please", ends = dayOf(now() + 60 * DAY) })))
		truthy(accept(goal(OFF, 1, { rev = 3, ends = dayOf(now() + 60 * DAY), state = "cancelled" })))
		refused(goal(OFF, 1, { rev = 4, ends = dayOf(now() + 60 * DAY) }), OFF, "locked")
		-- two goals made in the same second: the newer one wins
		truthy(accept(goal(OFF, 2)))
		truthy(accept(goal(OFF, 2, { time = now() + 5, item = SILK })))
		eq(S():Get("goals", "G:1002").item, SILK)
	end)

	it("keeps a record 90 days after its end or its cancellation", function()
		local r = goal(OFF, 1, { ends = dayOf(now() + DAY) })
		falsy(G().Expired(r, now() + 91 * DAY))
		truthy(G().Expired(r, now() + 93 * DAY))
		local c = goal(OFF, 2, { state = "cancelled" })
		falsy(G().Expired(c, now() + 89 * DAY))
		truthy(G().Expired(c, now() + 91 * DAY))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the progress from the bank logs (SPEC-17 §7.2)", function()
	before_boot(setup(1))

	it("is the sum of the deposits of the item in the dates, from every tab (criterion)", function()
		forbidTrade()
		local id = create({ target = 100 }).id
		eq(G():Get(id).have, 0)
		eq(G():Get(id).logAt, nil)
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 30), entry("withdraw", "Ann", LINEN, 10),
			entry("move", "Ann", LINEN, 7), entry("deposit", "Ann", SILK, 9), entry("deposit", "Ann", LINEN, 5, now() - 3 * DAY) })
		logRec(BOB, 2, { entry("deposit", "Ann", LINEN, 12) })
		logRec(BOB, 0, { entry("deposit", "Ann", 0, 99 * GOLD) })
		local row = G():Get(id)
		eq(row.have, 42, "30 + 12: withdrawals not taken off, other items and older days left out")
		eq(row.state, "open")
		eq(row.tabsSeen, 2)
		eq(row.contributors[1].name, "Bob")
		eq(row.contributors[1].amount, 30)
		eq(row.contributors[2].amount, 12)
		-- the same event read by a second guildmate counts once
		logRec(ANN, 1, { entry("deposit", "Bob", LINEN, 30) })
		eq(G():Get(id).have, 42)
		deepEq(G():Demand(), { { id = id, item = LINEN, missing = 58, title = "Linen" } })
		local demand = A().Demand:Compute()
		eq(demand.rows[1].item, LINEN)
		eq(demand.rows[1].need, 58)
		eq(demand.rows[1].goals[1].title, "Linen")
	end)

	it("adds the money deposits for gold, without withdrawals or repairs", function()
		local id = create({ kind = "gold", target = 50 }).id
		logRec(BOB, 0, { entry("deposit", "Bob", 0, 20 * GOLD), entry("withdraw", "Ann", 0, 15 * GOLD),
			entry("repair", "Ann", 0, 3 * GOLD), entry("deposit", "Ann", 0, 5 * GOLD, now() + HOUR) })
		local row = G():Get(id)
		eq(row.target, 50 * GOLD)
		eq(row.have, 25 * GOLD)
		eq(row.state, "open")
		eq(V().ProgressText(row), "25g / 50g · 50%")
		eq(#G():Demand(), 0)
	end)

	it("closes a goal when reached, on the day of the entry that reached it, and keeps it closed (criterion)", function()
		local rec = create({ target = 40 })
		local at = now() + 2 * HOUR
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 30, at - HOUR), entry("deposit", "Ann", LINEN, 15, at),
			entry("deposit", "Ann", LINEN, 5, at + HOUR) })
		local row = G():Get(rec.id)
		eq(row.state, "reached")
		eq(row.have, 50)
		eq(row.reachedAt, at)
		eq(row.fraction, 1)
		falsy(row.canEdit)
		eq(#G():List(), 0)
		eq(#G():List({ closed = true }), 1)
		eq(#G():Demand(), 0)
		eq(S():Get("goals", rec.id).rev, 1, "nothing written")
		eq(select(2, G():Cancel(rec.id)), "state")
		-- the entries leave the game's short logs: still reached here
		S():Records("bank")[BOB .. ":log:1"] = nil
		row = G():Get(rec.id)
		eq(row.state, "reached")
		eq(row.have, 40)
	end)

	it("closes a goal after its end date, and a later read can still reach it (criterion)", function()
		local rec = create({ target = 40, days = 2 })
		local made = now()
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 30) })
		Mock.Advance(2 * DAY)
		eq(G():Get(rec.id).state, "open", "the last day still counts")
		Mock.Advance(DAY + 1)
		local row = G():Get(rec.id)
		eq(row.state, "ended")
		eq(row.have, 30)
		eq(#G():List(), 0)
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 30, made), entry("deposit", "Ann", LINEN, 99, now()) })
		eq(G():Get(rec.id).have, 30, "a deposit after the end does not count")
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 30, made), entry("deposit", "Ann", LINEN, 10, made + DAY) })
		eq(G():Get(rec.id).state, "reached")
		eq(#G():List({ closed = true, t = now() + 100 * DAY }), 0)
	end)

	it("lets officers edit and cancel open goals only", function()
		local id = create({ days = 10 }).id
		eq(select(2, G():Edit(id, { days = 9 })), "locked")
		eq(select(2, G():Edit(id, { days = 181 })), "days")
		eq(select(2, G():Edit(id, { title = "" })), "title")
		local rec = must(G():Edit(id, { title = "Bags", note = "Now", days = 20 }))
		eq(rec.ends, dayOf(now() + 20 * DAY))
		eq(rec.note, "Now")
		rec = must(G():Edit(id, { note = "" }))
		eq(rec.note, nil)
		eq(rec.title, "Bags")
		rec = must(G():Cancel(id))
		eq(rec.state, "cancelled")
		eq(G():Get(id).state, "cancelled")
		eq(select(2, G():Edit(id, { title = "x" })), "state")
	end)

	it("takes at most 5 open goals and checks what is asked", function()
		for _ = 1, 5 do create() end
		eq(S():Count("goals"), 5, "five ids in the same second")
		eq(select(2, G():Create({ kind = "items", item = LINEN, target = 5, title = "x" })), "limit")
		for why, spec in pairs({ kind = { kind = "x" }, item = { kind = "items", target = 1 },
			target = { kind = "gold", target = 0 }, days = { kind = "gold", target = 1, days = 181 },
			title = { kind = "gold", target = 1, title = " " },
			note = { kind = "gold", target = 1, title = "t", note = ("n"):rep(121) } }) do
			eq(select(2, G():Create(spec)), why, why)
		end
		must(G():Cancel(G():List()[1].id))
		create()
	end)

	it("tells once about a reached goal, in the chat while the centre is off", function()
		A().Features.actions = false
		local rec = create({ target = 10, title = "Quick" })
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 10) })
		G():Changed()
		Mock.Advance(5)
		G():Changed()
		Mock.Advance(5)
		local _, times = printed():gsub("Guild goal reached: Quick", "")
		eq(times, 1)
		eq(G():Notices(), 0)
		truthy(rec)
	end)

	it("gives no notice for a goal reached long ago", function()
		local t = now() - 20 * DAY
		S():Records("goals")["G:5"] = goal(OFF, 1, { id = "G:5", start = dayOf(t - DAY), target = 5 })
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 10, t) })
		eq(G():Get("G:5").state, "reached")
		eq(G():Notices(), 0)
	end)

	it("posts the notice in the centre when it is on", function()
		A().Features.actions = true
		local rec = create({ target = 10 })
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 10) })
		eq(G():Notices(), 1)
		eq(G():Notices(), 0)
		local list = A().Notify:Entries()
		local found
		for _, e in ipairs(list) do if e.module == "goals" then found = e end end
		truthy(found)
		eq(found.key, rec.id)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a member who sees fewer tabs", function()
	before_boot(setup(3))

	it("counts less and says from how many tabs", function()
		S():Records("goals")["G:7"] = goal(OFF, 1, { id = "G:7" })
		logRec(OFF, 1, { entry("deposit", "Bob", LINEN, 20) })
		logRec(OFF, 2, { entry("deposit", "Ann", LINEN, 50) }, { rank = 1, restricted = true })
		local row = G():Get("G:7")
		eq(row.have, 20)
		eq(row.tabsSeen, 1)
		eq(row.tabsTotal, 2)
		eq(V().TabsText(row), "Counted from the logs you can see: 1 of 2 tabs")
		falsy(row.canEdit)
		-- an old log mutes the bar
		Mock.Advance(8 * DAY)
		row = G():Get("G:7")
		truthy(row.stale)
		contains(V().LogText(row), "Newest bank log")
		A().BankLog.DONATIONS_VISIBLE_TO = "officers"
		eq(G():Get("G:7").contributors, nil)
		A().BankLog.DONATIONS_VISIBLE_TO = "everyone"
	end)

	it("opens the page without New goal and without Edit", function()
		S():Records("goals")["G:7"] = goal(OFF, 1, { id = "G:7" })
		truthy(V():Open("G:7"))
		local f = V().frame
		falsy(f.new:IsShown())
		falsy(f.foot.edit:IsShown())
		falsy(f.foot.cancel:IsShown())
		isNil(V():OpenNew())
		isNil(V():OpenEdit("G:7"))
		for _, s in ipairs(A().ShareModel.Describe()) do truthy(s.id ~= "goals") end
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the Goals page", function()
	before_boot(setup(1))

	it("is a page of Economy with a window that sets, edits and cancels", function()
		forbidTrade()
		eq(A().Shell.DestOf(A().Shell.views.goals), "economy")
		truthy(A().Shell:OpenView("goals"))
		local f = V().frame
		truthy(f.new:IsShown())
		local d = must(V():OpenNew())
		eq(select(2, V():Place()), "item")
		d.item:SetText(tostring(LINEN))
		d.target:SetText("200")
		d.titleBox:SetText("Linen for bags")
		d.note:SetText("Materials tab")
		local rec = must(V():Place())
		eq(rec.target, 200)
		eq(rec.ends, dayOf(now() + 30 * DAY))
		eq(#V().rows, 1)
		eq(V().selected, rec.id)
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 50) })
		V():Redraw()
		contains(f.foot.info:GetText(), "50 / 200 · 25%")
		contains(f.foot.who:GetText(), "Bob 50")
		local tip = V().TipLines(V().rows[1])
		eq(tip[1], "Linen for bags")
		d = must(V():OpenEdit(rec.id))
		falsy(d.target:IsShown())
		d.days:SetText("40")
		eq(must(V():Place()).ends, dayOf(now() + 40 * DAY))
		d = must(V():OpenNew())
		d.kind:Select("gold")
		V():KindChanged("gold")
		falsy(d.item:IsShown())
		d.target:SetText("0")
		d.titleBox:SetText("Gold")
		eq(select(2, V():Place()), "target")
		contains(d.status:GetText(), "1000000")
		d.target:SetText("100")
		must(V():Place())
		eq(#V().rows, 2)
		eq(V():Press(rec.id), "armed")
		eq(V().armed, rec.id)
		eq(V():Press(rec.id), true)
		eq(#V().rows, 1)
		V().show = "closed"
		V():Redraw()
		eq(#V().rows, 1)
		eq(V().EndsText(V().rows[1]), "Cancelled")
		V():SetSearch("nothing")
		eq(#V().rows, 0)
		eq(#Mock.errors, 0)
	end)

	it("shows the goals in What I share and in /accord debug, without names or titles", function()
		create({ title = "Secret title" })
		local found
		for _, s in ipairs(A().ShareModel.Describe()) do if s.id == "goals" then found = s end end
		truthy(found)
		contains(table.concat(found.lines, "\n"), "Goal Secret title: 100 × Linen Cloth")
		local report = A().Diagnostics.Report()
		contains(report, "Goals: 1 open, 0 reached, 0 ended, 0 cancelled; refused: none")
		falsy(report:find("Secret", 1, true))
	end)

	it("has two goals in the demo, one reached", function()
		truthy(A().Demo:Enter())
		eq(#G():List(), 1)
		eq(#G():List({ closed = true }), 1)
		eq(G():List({ closed = true })[1].kind, "gold")
		truthy(G():List()[1].have > 0)
		truthy(V():Open())
		eq(#Mock.errors, 0)
		A().Demo:Exit()
		eq(S():Count("goals"), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the goals with the switch econ off", function()
	before_boot(setup(1, { econ = false }))

	it("shows, writes and takes nothing of it", function()
		eq(select(2, G():Create({ kind = "gold", target = 1, title = "x" })), "off")
		falsy(S().IsActive("goals"))
		refused(goal(OFF), OFF, "set")
		falsy(V():Open())
		isNil(V():OpenNew())
		falsy(A().Shell:OpenView("goals"))
		deepEq(G():List(), {})
		deepEq(G():Demand(), {})
		eq(G():Notices(), 0)
		for _, s in ipairs(A().ShareModel.Describe()) do truthy(s.id ~= "goals") end
		falsy(A().Diagnostics.Report():find("Goals:", 1, true))
		eq(S():Count("goals"), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator
---------------------------------------------------------------------------------------------------------------------
describe("the goals between clients", function()
	local function simulated(M)
		M.features = { econ = true }
		M.items.info[LINEN] = { name = "Linen Cloth" }
		M.items.cached[LINEN] = true
	end

	local function seen(sim, i, id)
		local row = sim:client(i):addon().Goals:Get(id)
		return row and (row.have .. " " .. row.state)
	end

	it("shows the same progress on every client with the same logs, also one that was away", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 5 }, setup = simulated, accounts = true, seed = 139 }
		sim:advance(120)
		local officer, reader = sim:client(1), sim:client(2)
		local rec = must(officer:addon().Goals:Create({ kind = "items", item = LINEN, target = 50, title = "Linen" }))
		sim:advance(60)
		local t = reader:addon().Compat.ServerTime()
		truthy(reader:addon().BankLog:Capture(1, { entry("deposit", "Someone", LINEN, 20, t) }))
		sim:advance(120)
		for _, j in ipairs({ 1, 2, 3, 4 }) do eq(seen(sim, j, rec.id), "20 open", "client " .. j) end
		truthy(reader:addon().BankLog:Capture(1, { entry("deposit", "Other", LINEN, 35, t) }))
		sim:advance(120)
		for _, j in ipairs({ 1, 2, 3, 4 }) do eq(seen(sim, j, rec.id), "55 reached", "client " .. j) end
		sim:client(5):login()
		truthy(sim:advanceUntil(function() return seen(sim, 5, rec.id) == "55 reached" end, 25 * 60), "the one away")
		for i = 1, 5 do
			eq(sim:client(i):addon().Sync.state.stats.refused, 0, "client " .. i)
			eq(sim:client(i):addon().Sync.state.stats.quarantined, 0, "client " .. i)
		end
	end)

	-- A client released before M13 knows none of its sets: here they are switched off in it, after every login.
	local function makeOld(c)
		local Store = c:addon().Store
		local original = Store.IsActive
		Store.IsActive = function(set)
			if set == "orders" or set == "wish" or set == "board" or set == "goals" then return false end
			return original(set)
		end
	end

	it("leaves a client that does not know the set as before: nothing pushed, asked or refused", function()
		local sim = Sim.new{ clients = 4, officers = { 1 }, offline = { 3 }, setup = simulated, accounts = true, seed = 75 }
		makeOld(sim:client(4))
		sim:advance(120)
		local officer = sim:client(1)
		must(officer:addon().Goals:Create({ kind = "gold", target = 10, title = "Gold" }))
		sim:advance(120)
		local old = sim:client(4):addon()
		eq(old.Store:Count("goals"), 0)
		sim:client(3):login()
		truthy(sim:advanceUntil(function() return sim:client(3):addon().Store:Count("goals") == 1 end, 25 * 60), "the newcomer")
		sim:advance(600)
		local s, c = old.Sync:EncodeSummary(), old.Sync:EncodeSummary(nil, true)
		for i = 1, 3 do
			local Sy = sim:client(i):addon().Sync
			eq(Sy:EncodeSummary(), s, "the per-author summary, client " .. i)
			eq(Sy:EncodeSummary(nil, true), c, "the census's extra summary, client " .. i)
		end
		eq(#old.Sync:EncodeSummary(nil, "ec"), 0, "the old client has no summary of M13")
		local sent = 0
		for i = 1, 4 do
			local Tr = sim:client(i):addon().Transport
			local original = Tr.Send
			Tr.Send = function(self, dist, msg, opts)
				if msg.t == "REC" and msg.s == "goals" then sent = sent + 1 end
				return original(self, dist, msg, opts)
			end
		end
		sim:client(4):logout()
		sim:client(4):login()
		makeOld(sim:client(4))
		sim:advance(45 * 60)
		eq(sent, 0, "no goal sent to it or because of it")
		eq(sim:client(4):addon().Sync.state.stats.requests, 0, "and it asked for nothing")
		for i = 1, 4 do
			local Ci = sim:client(i):addon()
			eq(Ci.Store.stats.rejected, 0, "client " .. i)
			eq(Ci.Sync.state.stats.quarantined, 0)
		end
	end)
end)

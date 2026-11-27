-- The wishlist (M13.3; SPEC-17 §4.2, WSH-01..WSH-03; SPEC-10 Q43): the shape, the owner and the rate; every entry
-- expires by itself; the own list; the entry the shopping list will use (Plan, Ask); the guild's wishes and "I have
-- some", which sends nothing; the member card, What I share and /accord debug; the switch "econ"; between clients and
-- the shared traffic.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function W() return AzerothAccord.Wishlist end
local function V() return AzerothAccord.WishlistView end

local ME = "Player-1-0000A001"
local OFF, BOB, ANN, ALT = "Player-1-000000FF", "Player-1-00000B0B", "Player-1-00000A77", "Player-1-00000A17"
local LINEN, SILK, COPPER = 2589, 4306, 2840
local DAY, HOUR = 86400, 3600

local function setup(features)
	return function(M)
		M.features = features or { econ = true }
		M.items.info[LINEN] = { name = "Linen Cloth" }
		M.items.info[SILK] = { name = "Silk Cloth" }
		M.items.info[COPPER] = { name = "Copper Bar" }
		M.items.cached[LINEN], M.items.cached[SILK], M.items.cached[COPPER] = true, true, true
		M.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Officer", rank = 1, guid = OFF, level = 60, class = "PRIEST", online = true },
			{ name = "Bob", rank = 3, guid = BOB, level = 60, class = "MAGE", online = true },
			{ name = "Ann", rank = 3, guid = ANN, level = 50, class = "DRUID", online = false },
			{ name = "Alt", rank = 4, guid = ALT, level = 10, class = "ROGUE", online = true },
		} }
	end
end

local function now() return GetServerTime() end
local function day(days, t) return tonumber(date("!%Y%m%d", (t or now()) + days * DAY)) end
local NAME = { [OFF] = "Officer", [BOB] = "Bob", [ANN] = "Ann", [ALT] = "Alt" }

local function entry(item, n, days, s) return { i = item, n = n or 1, u = day(days or 14), s = s } end

local function record(guid, entries, fields)
	local r = { id = "W:" .. guid, author = guid, rev = 1, time = now(), e = entries or { entry(LINEN, 5) } }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

local function accept(rec, sender) return S():Accept("wish", rec, { sender = NAME[sender or rec.author], dist = "GUILD" }) end

local function refused(rec, sender, why)
	local ok, w = accept(rec, sender)
	eq(ok, false, "refused: " .. tostring(why))
	eq(w, why)
end

local function own()
	local out = {}
	for i, e in ipairs((W():Own())) do out[i] = e.item .. "x" .. e.n end
	return out
end

local function printed() return table.concat(Mock.PlainOutput(), "\n") end

---------------------------------------------------------------------------------------------------------------------
describe("the records (WSH-01..WSH-03)", function()
	before_boot(setup())

	it("takes a list from its character, an alt of the account or an officer's relay, from nobody else", function()
		truthy(accept(record(BOB)))
		refused(record(ANN, nil, { author = OFF }), OFF, "owner")
		refused(record(ANN, nil, { author = BOB }), BOB, "owner")
		refused(record(ANN), BOB, "relay")
		truthy(accept(record(ANN), OFF))
		for _, g in ipairs({ BOB, ALT }) do
			S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = now(), token = "tok",
				chars = { { guid = BOB }, { guid = ALT } }, main = BOB }
		end
		truthy(accept(record(ALT, nil, { author = BOB })))
	end)

	it("refuses a shape that is not a wishlist's", function()
		local many = {}
		for i = 1, 31 do many[i] = entry(i) end
		for what, rec in pairs({
			many = record(BOB, many), twice = record(BOB, { entry(LINEN), entry(LINEN, 2) }), zero = record(BOB, { entry(LINEN, 0) }),
			big = record(BOB, { entry(LINEN, 1000) }), frac = record(BOB, { entry(LINEN, 1.5) }),
			item = record(BOB, { { i = "x", n = 1, u = day(1) } }), noDay = record(BOB, { { i = 1, n = 1 } }),
			badDay = record(BOB, { { i = 1, n = 1, u = 20269999 } }), past = record(BOB, { entry(LINEN, 1, -1) }),
			far = record(BOB, { entry(LINEN, 1, 31) }), source = record(BOB, { entry(LINEN, 1, 1, "x") }),
			key = record(BOB, { { i = 1, n = 1, u = day(1), price = "5g" } }), notList = record(BOB, "x"),
			hole = record(BOB, { [1] = entry(1), [3] = entry(2) }), note = record(BOB, nil, { note = ("n"):rep(81) }),
			noteBar = record(BOB, nil, { note = "|cff" }), noteEmpty = record(BOB, nil, { note = "" }),
			extra = record(BOB, nil, { price = "5g" }), id = record(BOB, nil, { id = "W:x" }),
		}) do
			local ok, why = accept(rec, BOB)
			eq(ok, false, what); eq(why, "owner", what)
		end
		truthy(accept(record(BOB, { entry(LINEN, 999, 30), entry(SILK, 1, 0) }, { note = ("n"):rep(80) })))
	end)

	it("holds the longest list inside its size", function()
		local long = "Player-1234-0ABCDEF123456789"
		local list = {}
		for i = 1, 30 do list[i] = { i = 2147483600 + i, n = 999, u = day(30), s = "sl" } end
		local rec = { id = "W:" .. long, author = long, rev = 2147483647, time = now(), e = list, note = ("n"):rep(80) }
		truthy(A().Config.EstimateSize(rec) <= W().RECORD_BYTES, "size " .. A().Config.EstimateSize(rec))
		eq(S().SETS.wish.maxBytes, W().RECORD_BYTES)
	end)

	it("takes at most 20 revisions of an author an hour", function()
		for rev = 1, 20 do truthy(accept(record(BOB, nil, { rev = rev })), rev) end
		refused(record(BOB, nil, { rev = 21 }), BOB, "rate")
		Mock.Advance(HOUR + 1)
		truthy(accept(record(BOB, nil, { rev = 22 })))
	end)

	it("expires every entry by itself, from the date (criterion)", function()
		truthy(accept(record(BOB, { entry(LINEN, 5, 1), entry(SILK, 2, 10) })))
		local rec = S():Get("wish", "W:" .. BOB)
		eq(#W():Guild(), 2)
		eq(W():Guild()[1].left, 2)
		Mock.Advance(2 * DAY + HOUR, 60)
		eq(#W():Guild(), 1, "gone without a write")
		eq(S():Get("wish", "W:" .. BOB).rev, rec.rev)
		falsy(W().Expired(rec, now()))
		Mock.Advance(9 * DAY, 600)
		eq(#W():Guild(), 0)
		falsy(W().Expired(rec, now()), "kept 30 days after its write")
		Mock.Advance(20 * DAY, 600)
		truthy(W().Expired(rec, now()))
		A().Store:Prune()
		isNil(S():Get("wish", "W:" .. BOB))
		refused(rec, BOB, "expired")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the own list", function()
	before_boot(setup())

	it("adds, replaces, removes and notes", function()
		local rec = W():Add(LINEN, 5)
		eq(rec.e[1].u, day(14))
		W():Add(SILK, 2, 30)
		W():Add(LINEN, 8, 1)
		deepEq(own(), { LINEN .. "x8", SILK .. "x2" })
		eq(W():Own()[1].left, 2)
		truthy(W():SetNote(" for |the bags\n"))
		eq(select(2, W():Own()), "for the bags")
		truthy(W():Remove(LINEN))
		deepEq(own(), { SILK .. "x2" })
		eq(select(2, W():Own()), "for the bags")
		truthy(W():SetNote(""))
		isNil(S():Get("wish", "W:" .. ME).note)
		truthy(W():Remove(SILK))
		eq(#S():Get("wish", "W:" .. ME).e, 0)
	end)

	it("drops the expired entries at the next write", function()
		W():Add(LINEN, 1, 1)
		Mock.Advance(2 * DAY + HOUR, 60)
		W():Add(SILK)
		eq(#S():Get("wish", "W:" .. ME).e, 1)
	end)

	it("says why not", function()
		local function why(...) local rec, w = W():Add(...) isNil(rec) return w end
		eq(why("x"), "item"); eq(why(LINEN, 0), "count"); eq(why(LINEN, 1000), "count"); eq(why(LINEN, 1, 0), "days")
		eq(why(LINEN, 1, 31), "days")
		eq(select(2, W():Remove(LINEN)), "missing")
		eq(select(2, W():SetNote(("n"):rep(81))), "note")
		for i = 1, 20 do truthy(W():Add(i), i) end
		eq(why(21), "rate")
		Mock.Advance(HOUR + 1)
		for i = 21, 30 do truthy(W():Add(i), i) end
		eq(why(31), "full")
		truthy(W():Add(30, 2), "an entry listed can still change")
	end)

	it("reads a link, a number or the name of a known item", function()
		A().Compat.Item.Request(LINEN); A().Compat.Item.Request(COPPER)
		Mock.Advance(1)
		eq(W().ParseItem("|cffffffff|Hitem:2589::::|h[Linen Cloth]|h|r"), LINEN)
		eq(W().ParseItem(" 4306 "), SILK)
		eq(W().ParseItem("linen cloth"), LINEN)
		eq(W().ParseItem("[Copper Bar]"), COPPER)
		isNil(W().ParseItem("mithril"))
		isNil(W().ParseItem(""))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the entry of the shopping list (Plan and Ask, SPEC-17 §5.8)", function()
	before_boot(setup())

	it("writes the missing materials, keeping the larger quantity of a listed item", function()
		W():Add(LINEN, 40, 2)
		W():Add(COPPER, 1, 30)
		local rec, plan = W():Ask({ { item = LINEN, n = 28 }, { item = SILK, n = 6 }, { item = SILK, n = 2 } })
		truthy(rec)
		deepEq(own(), { LINEN .. "x40", COPPER .. "x1", SILK .. "x8" })
		local list = W():Own()
		eq(list[1].day, day(14)); isNil(list[1].source)
		eq(list[2].day, day(30))
		eq(list[3].source, "sl")
		eq(plan.left, 0); eq(#plan.asked, 2)
		W():Ask({ { item = SILK, n = 2000 } })
		eq(W():Own()[3].n, 999)
	end)

	it("keeps the typed entries and the largest quantities when 30 are not enough, and says how many are left", function()
		W():Add(9001, 1)
		W():Ask({ { item = 9002, n = 1 } })
		local wants = {}
		for i = 1, 35 do wants[i] = { item = i, n = i } end
		local plan = W():Plan(wants)
		eq(#S():Get("wish", "W:" .. ME).e, 2, "a plan writes nothing")
		eq(#plan.entries, 30); eq(plan.left, 6); eq(#plan.asked, 29)
		eq(plan.entries[1].item, 9001)
		eq(plan.asked[1].item, 35)
		for _, e in ipairs(plan.entries) do truthy(e.item ~= 9002 and e.item ~= 6, "gave way: " .. e.item) end
		truthy(W():Ask(wants))
		eq(#W():Own(), 30)
	end)

	it("writes nothing when there is nothing to ask", function()
		eq(select(2, W():Ask({})), "empty")
		eq(select(2, W():Ask({ { item = LINEN, n = 0 } })), "empty")
		eq(S():Count("wish"), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the Wishlist mode", function()
	before_boot(setup())

	local function open()
		truthy(A().MarketView:Open("wishlist"))
		Mock.Advance(2)
		return V().frame
	end

	it("adds from the form and removes from the row", function()
		A().Compat.Item.Request(LINEN)
		local f = open()
		f.item:SetText("Linen Cloth"); f.count:SetText("12")
		f.add:Click()
		deepEq(own(), { LINEN .. "x12" })
		eq(f.item:GetText(), "")
		eq(f.status:GetText(), "Added to your wishlist.")
		f.item:SetText("mithril")
		f.add:Click()
		contains(f.status:GetText(), "Item not recognised")
		eq(f.item:GetText(), "mithril")
		f.item:SetText("4306"); f.days:SetText("40")
		f.add:Click()
		eq(f.status:GetText(), "Days: from 1 to 30.")
		f.note:SetText("for the bags")
		truthy(V():SaveNote())
		eq(select(2, W():Own()), "for the bags")
		f.own:VisibleRows()[1].action:Click()
		eq(#W():Own(), 0)
	end)

	it("lists the guild's wishes by item, online first, and searches", function()
		accept(record(ANN, { entry(LINEN, 3), entry(COPPER, 1) }))
		accept(record(BOB, { entry(LINEN, 7) }))
		W():Add(SILK, 1)
		local f = open()
		local rows = {}
		for _, r in ipairs(f.guild:VisibleRows()) do
			rows[#rows + 1] = r.cells[1]:GetText() .. "/" .. r.cells[2]:GetText() .. "/" .. tostring(r.action:IsShown())
		end
		deepEq(rows, { "Copper Bar/Ann/true", "Linen Cloth/Bob/true", "Linen Cloth/Ann/true", "Silk Cloth/Testchar/false" })
		A().MarketView:SetSearch("linen")
		eq(#V().rows, 2)
		A().MarketView:SetSearch("ann")
		eq(#V().rows, 2)
		eq(#Mock.errors, 0)
	end)

	it("hides who left the guild", function()
		accept(record(BOB))
		eq(#W():Guild(), 1)
		S():Records("wish")["W:Player-1-0000DEAD"] = record("Player-1-0000DEAD")
		eq(#W():Guild(), 1)
	end)

	it("only writes the whisper of I have some: nothing is sent", function()
		accept(record(BOB, { entry(LINEN, 7) }))
		local f = open()
		local chat = {}
		ChatFrame_OpenChat = function(text) chat[#chat + 1] = text end
		local sent = #Mock.chat.sent
		f.guild:VisibleRows()[1].action:Click()
		deepEq(chat, { "/w Bob Hi! I have Linen Cloth for your wishlist." })
		eq(#Mock.chat.sent, sent)
	end)

	it("shows the wishes on the member card", function()
		accept(record(BOB, { entry(LINEN, 7, 3) }))
		local section = A().OrdersView.CardSection(A().Roster:ByGUID(BOB))
		eq(section.id, "market")
		eq(section.lines[1].text, "Wishes for Linen Cloth × 7 · expires in 4 days")
		section.lines[1].onClick()
		eq(A().MarketView.mode, "wishlist")
		isNil(A().OrdersView.CardSection(A().Roster:ByGUID(ANN)))
	end)

	it("lists it in What I share and counts it in /accord debug, without a name", function()
		W():Add(LINEN, 4)
		W():SetNote("soon")
		accept(record(ANN, nil, { author = OFF }), OFF)
		local found
		for _, s in ipairs(A().ShareModel.Describe()) do if s.id == "wish" then found = s end end
		local text = table.concat(found.lines, "\n")
		contains(text, "Linen Cloth × 4, until ")
		contains(text, "note: soon")
		local report = A().Diagnostics.Report()
		contains(report, "Wishlist: 1 list(s), 1 live entr(ies); refused: owner 1")
		falsy(report:find("Linen", 1, true))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("with the switch econ off", function()
	before_boot(setup({ econ = false }))

	it("shows, writes and takes nothing of it", function()
		eq(select(2, W():Add(LINEN)), "off")
		eq(select(2, W():Ask({ { item = LINEN, n = 1 } })), "off")
		falsy(S().IsActive("wish"))
		refused(record(BOB), BOB, "set")
		falsy(A().MarketView:Open("wishlist"))
		for _, s in ipairs(A().ShareModel.Describe()) do truthy(s.id ~= "wish") end
		falsy(A().Diagnostics.Report():find("Wishlist:", 1, true))
		eq(S():Count("wish"), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator
---------------------------------------------------------------------------------------------------------------------
describe("the wishlists between clients", function()
	it("reach the guild, also one that was away", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 5 }, setup = function(M) M.features = { econ = true } end,
			accounts = true, seed = 133 }
		sim:advance(120)
		local who = sim:client(2)
		truthy(who:addon().Wishlist:Add(LINEN, 5))
		sim:advance(60)
		local function held(i)
			local r = sim:client(i):addon().Store:Get("wish", "W:" .. who:guid())
			return r and #r.e
		end
		for _, j in ipairs({ 1, 3, 4 }) do eq(held(j), 1, "client " .. j) end
		sim:client(5):login()
		truthy(sim:advanceUntil(function() return held(5) == 1 end, 25 * 60), "the one away")
		for i = 1, 5 do eq(sim:client(i):addon().Sync.state.stats.refused, 0, "client " .. i) end
	end)

	-- The scenario of M10.8 (SPEC-17 §10.3): 50 clients, 45 minutes of churn; with `with`, a wishlist changed every 3
	-- minutes for the whole guild, each list growing to 30 entries.
	local function churn(with)
		local N = 50
		local sim = Sim.new{ clients = N, officers = { 1, 11, 21, 31, 41 }, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42,
			setup = function(M) M.features = { econ = true } end }
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		local writes = {}
		local function writeNext(c)
			writes[c.index] = (writes[c.index] or 0) + 1
			local S_, guid = c:addon().Store, c:guid()
			truthy(S_:Put("accounts", guid, { token = "T" .. c.index, chars = { { guid = guid } }, n = writes[c.index] }))
			truthy(S_:Put("contacts", guid, { battleTag = c.name .. "#" .. c.index, n = writes[c.index] }))
		end
		for i = 1, N do if sim:client(i).online then writeNext(sim:client(i)) end end
		sim:advance(30 * 60)
		for i = 2, N, 2 do sim:client(i):logout() end
		sim:resetStats()
		local changed = 0
		for step = 1, 90 do
			for i = 1, N do
				local c, r = sim:client(i), rand()
				if c.online then
					if r < 0.04 then c:logout() elseif r < 0.08 then writeNext(c) end
				elseif r < 0.06 then
					c:login()
					if not writes[i] then writeNext(c) end
				end
			end
			if with and step % 6 == 1 then
				for _ = 1, 100 do
					local c = sim:client(1 + math.floor(rand() * N) % N)
					if c.online then
						local wants = {}
						for k = 1, 30 do wants[k] = { item = 10000 + step * 40 + k, n = 999 } end
						if c:addon().Wishlist:Ask(wants) then changed = changed + 1 end
						break
					end
				end
			end
			sim:advance(30)
		end
		for i = 1, N do
			local c = sim:client(i)
			if c.online then
				for why, n in pairs(c:addon().Store.stats.reasons) do fail("client " .. i .. " refused " .. n .. " for " .. why) end
				eq(c:addon().Sync.state.stats.quarantined, 0)
			end
		end
		return sim:stats(), changed
	end

	it("50 clients of a guild in step stay inside the shared traffic budget (SPEC-09 §7)", function()
		local base = churn(false)
		local st, changed = churn(true)
		T.log(("wishlists: churn %.0f B/min per client on average (%.0f without them), %.0f at most (%.0f); %d changes"):format(
			st.avg.bytesPerMinute, base.avg.bytesPerMinute, st.max.bytesPerMinute, base.max.bytesPerMinute, changed))
		truthy(changed >= 10, "changes " .. changed)
		truthy(st.avg.bytesPerMinute <= 450, "churn average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2048, "churn busiest client " .. st.max.bytesPerMinute)
	end)
end)

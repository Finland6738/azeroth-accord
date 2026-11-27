-- Craft orders (M13.2; SPEC-17 §3, ORD-01..ORD-06; SPEC-10 Q40..Q42, Q50; ADR 0028): each side writes only its own
-- record; the content is locked and the steps only go forward; a crafter part waits for its order; the state both derive;
-- delivered only with both confirmations; expiry and retention; the craft requests of M3 offered as orders, never
-- published by themselves; limits and rate; the Action Center and the notices once; nothing that moves gold or items;
-- the Market view, the New order window and Request craft; the summary `ec`; the shared traffic; the switch "econ".
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function O() return AzerothAccord.Orders end
local function V() return AzerothAccord.OrdersView end
local function R() return AzerothAccord.RecipeView end
local function L(key) return LibStub("AceLocale-3.0"):GetLocale("AzerothAccord")[key] end

local ME = "Player-1-0000A001"
local OFF, BOB, ANN, ALT = "Player-1-000000FF", "Player-1-00000B0B", "Player-1-00000A77", "Player-1-00000A17"
local DAY, HOUR = 86400, 3600
local ALCHEMY, POTION, FLASK = 171, 2330, 3447

local function setup(myRank, features)
	return function(M)
		M.features = features or { econ = true }
		M.spells.known[POTION] = { name = "Minor Healing Potion", icon = 1 }
		M.spells.known[FLASK] = { name = "Healing Potion", icon = 2 }
		M.guild.Set{ name = "Accord", myRank = myRank or 3, members = {
			{ name = "Officer", rank = 1, guid = OFF, level = 60, class = "PRIEST", online = true },
			{ name = "Bob", rank = 3, guid = BOB, level = 60, class = "MAGE", online = true },
			{ name = "Ann", rank = 3, guid = ANN, level = 50, class = "DRUID", online = false },
			{ name = "Alt", rank = 4, guid = ALT, level = 10, class = "ROGUE", online = true },
		} }
	end
end

local function settle() Mock.Advance(5) end
local function must(v, why) truthy(v, why) return v end
local function now() return GetServerTime() end
local function today(t) return tonumber(date("!%Y%m%d", t or now())) end

local function sameAccount(a, b)
	for _, g in ipairs({ a, b }) do
		S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = now(), token = "tok",
			chars = { { guid = a }, { guid = b } }, main = a }
	end
	A().Accounts:MarkDirty()
end

local NAME = { [OFF] = "Officer", [BOB] = "Bob", [ANN] = "Ann", [ALT] = "Alt" }

local function from(guid) return { sender = NAME[guid], dist = "GUILD" } end

-- An order record as its buyer would write it.
local function order(buyer, crafter, fields, n)
	local r = { id = "O:" .. buyer .. ":" .. (n or 1), author = buyer, rev = 1, time = now(), crafter = crafter, recipe = POTION,
		count = 2, mats = "buyer", created = now(), state = "open" }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

-- The crafter's part of order `o`.
local function part(o, state, fields)
	local r = { id = "A" .. o.id:sub(2), author = o.crafter, rev = 1, time = now(), crafter = o.crafter, state = state, at = now() }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

-- A newer revision of a record with `fields` changed (false removes a field).
local function nextRev(rec, fields)
	local r = {}
	for k, v in pairs(rec) do r[k] = v end
	r.rev, r.time = rec.rev + 1, now()
	for k, v in pairs(fields or {}) do
		if v == false then r[k] = nil else r[k] = v end
	end
	return r
end

local function accept(rec, sender) return S():Accept("orders", rec, from(sender or rec.author)) end

local function refused(rec, sender, why)
	local ok, w = accept(rec, sender)
	eq(ok, false, "refused: " .. tostring(why))
	eq(w, why)
end

local function recipes(guid, ids)
	local id = guid .. ":" .. ALCHEMY
	S():Records("recipes")[id] = { id = id, author = guid, rev = 1, time = now(), char = guid, skillLine = ALCHEMY,
		name = "Alchemy", rank = 200, maxRank = 300, ids = A().Recipes.Encode(ids or { POTION }), n = #(ids or { POTION }) }
	A().Roster:MarkDirty(); A().Crafters:MarkDirty()
end

local function place(spec)
	local s = { crafter = BOB, recipe = POTION, count = 2 }
	for k, v in pairs(spec or {}) do s[k] = v end
	return O():Create(s)
end

local function state(id) local row = O():Get(id) return row and row.state end

local function actionRows()
	local out = {}
	A().Actions:Refresh()
	for _, r in ipairs(A().Actions:Rows()) do if r.provider == "orders" then out[#out + 1] = r end end
	return out
end

local function titles(rows)
	local out = {}
	for i, r in ipairs(rows) do out[i] = r.title end
	return out
end

local function notices()
	local out = {}
	for _, e in ipairs(A().Notify:Entries()) do if e.module == "orders" then out[#out + 1] = A().Notify.Text(e) end end
	return out
end

local function printed() return table.concat(Mock.PlainOutput(), "\n") end

---------------------------------------------------------------------------------------------------------------------
describe("each side writes only its own record (ORD-01, ORD-02)", function()
	before_boot(setup())

	it("takes an order from its buyer and the part from its crafter", function()
		local o = order(ANN, BOB)
		truthy(accept(o))
		truthy(accept(part(o, "accepted")))
		eq(state(o.id), "accepted")
	end)

	it("refuses an order somebody else wrote, also an officer or the crafter, and a forged relay", function()
		refused(order(ANN, BOB, { author = OFF }), OFF, "owner")
		refused(order(ANN, BOB, { author = BOB }), BOB, "owner")
		refused(order(ANN, BOB), BOB, "relay")           -- a member passing on somebody else's record
		truthy(accept(order(ANN, BOB), OFF))             -- an officer's relay of Ann's own words (NET-11)
	end)

	it("lets nobody change the other side's word: the buyer and an officer cannot write the crafter's part", function()
		local o = order(ANN, BOB)
		accept(o)
		refused(part(o, "handed", { author = ANN }), ANN, "owner")
		refused(part(o, "handed", { author = OFF }), OFF, "owner")
		refused(part(o, "handed", { author = OFF, crafter = OFF }), OFF, "locked")
		refused(part(o, "handed", { author = ALT, crafter = ALT }), ALT, "locked")
		refused(nextRev(o, { author = OFF, state = "cancelled", closed = now() }), OFF, "owner")
		eq(state(o.id), "requested")
	end)

	it("lets an alt of the account write its side", function()
		sameAccount(BOB, ALT)
		local o = order(ANN, BOB)
		accept(o)
		truthy(accept(part(o, "accepted", { author = ALT })))
	end)

	it("refuses a shape that is not an order's", function()
		local t = now()
		for what, fields in pairs({
			self = { crafter = ANN }, count0 = { count = 0 }, count201 = { count = 201 }, frac = { count = 1.5 },
			mats = { mats = "gold" }, recipe = { recipe = "x" }, item = { item = -1 }, price = { price = ("g"):rep(25) },
			priceBar = { price = "|cff" }, note = { note = ("n"):rep(81) }, noteLine = { note = "a\nb" }, state = { state = "delivered" },
			closedOpen = { closed = t }, noClosed = { state = "received" }, byLate = { by = today(t + 62 * DAY) },
			byPast = { by = today(t - 3 * DAY) }, byBad = { by = 20269999 }, created = { created = t + 90 }, extra = { gold = 5 },
		}) do
			local ok, why = accept(order(ANN, BOB, fields))
			eq(ok, false, what); eq(why, "owner", what)
		end
		sameAccount(ANN, ALT)
		refused(order(ANN, ALT), ANN, "owner")   -- the crafter is a character of the buyer's account
		local o = order(BOB, ANN)
		accept(o)
		for what, fields in pairs({ state = { state = "open" }, note = { note = ("n"):rep(81) }, at = { at = now() + 90 },
			extra = { price = "5g" } }) do
			local ok, why = accept(part(o, "accepted", fields))
			eq(ok, false, what); eq(why, "owner", what)
		end
	end)

	it("holds the longest order and part inside their sizes", function()
		local long = "Player-1234-0ABCDEF123456789"
		A().Orders.ValidRecord(order(ANN, BOB), S())
		local o = { id = "O:" .. long .. ":999999999", author = long, rev = 2147483647, time = now(), crafter = long .. "A",
			recipe = 2147483647, item = 2147483647, count = 200, mats = "crafter", price = ("p"):rep(24), note = ("n"):rep(80),
			by = today(), created = now(), state = "cancelled", closed = now() }
		truthy(A().Config.EstimateSize(o) <= O().ORDER_BYTES, "order " .. A().Config.EstimateSize(o))
		local a = { id = "A:" .. long .. ":999999999", author = long, rev = 2147483647, time = now(), crafter = long,
			state = "declined", note = ("n"):rep(80), at = now() }
		truthy(A().Config.EstimateSize(a) <= O().PART_BYTES, "part " .. A().Config.EstimateSize(a))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the content is locked and the steps only go forward (ORD-03, ORD-04)", function()
	before_boot(setup())

	it("keeps the content of an order: a revision changes only the state, the note and the closing", function()
		local o = order(ANN, BOB, { price = "5g" })
		accept(o)
		for what, fields in pairs({ crafter = { crafter = OFF }, recipe = { recipe = FLASK }, count = { count = 5 },
			mats = { mats = "mixed" }, price = { price = "50g" }, noPrice = { price = false }, item = { item = 5 },
			created = { created = o.created - 5 }, by = { by = today(now() + DAY) } }) do
			local ok, why = accept(nextRev(o, fields))
			eq(ok, false, what); eq(why, "locked", what)
		end
		local noted = nextRev(o, { note = "thanks" })
		truthy(accept(noted))
		local closed = nextRev(noted, { state = "received", closed = now() })
		truthy(accept(closed))
		refused(nextRev(closed, { state = "open", closed = false }), ANN, "locked")
		refused(nextRev(closed, { state = "cancelled" }), ANN, "locked")
	end)

	it("moves the crafter's state forward only; declined and handed are final", function()
		local o = order(ANN, BOB)
		accept(o)
		local a = part(o, "accepted")
		accept(a)
		local ready = nextRev(a, { state = "ready" })   -- a step may be skipped
		truthy(accept(ready))
		refused(nextRev(ready, { state = "working" }), BOB, "locked")
		refused(nextRev(ready, { state = "accepted" }), BOB, "locked")
		local ok, why = accept(nextRev(a, { rev = 1, time = now() - 10, at = now() - 10, state = "accepted" }))
		eq(ok, false); eq(why, "older")
		local handed = nextRev(ready, { state = "handed" })
		truthy(accept(handed))
		refused(nextRev(handed, { state = "declined" }), BOB, "locked")
		local o2 = order(ANN, BOB, nil, 2)
		accept(o2)
		local no = part(o2, "declined")   -- declined may be the first word
		truthy(accept(no))
		refused(nextRev(no, { state = "accepted" }), BOB, "locked")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a part waits for its order (ORD-05)", function()
	before_boot(setup())

	it("is kept aside and taken when the order arrives, without counting against the sender", function()
		local o = order(ANN, BOB)
		local accepted, rejected = S():Receive("orders", { part(o, "working") }, "Bob", "GUILD")
		eq(accepted, 0); eq(rejected, 0, "not against an honest sender")
		eq(#O().waiting, 1)
		eq(S().stats.bySet.orders.wait, 1, "but counted for /accord debug")
		truthy(accept(o))
		eq(state(o.id), "progress")
		eq(#O().waiting, 0)
		contains(table.concat(O():DebugLines(), " "), "wait 1")
	end)

	it("waits ten minutes at most, and the list has a limit", function()
		local o = order(ANN, BOB)
		accept(part(o, "accepted"))
		Mock.Advance(O().WAIT + 5)
		accept(o)
		eq(state(o.id), "requested")
		for n = 2, O().WAIT_MAX + 10 do accept(part(order(ANN, BOB, nil, n), "accepted")) end
		eq(#O().waiting, O().WAIT_MAX)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the state both sides give (SPEC-17 §3.2)", function()
	before_boot(setup())

	local function st(o, a, t) local s, info = O().State(o, a, t) return s, info end

	it("is derived from the two records", function()
		local o = order(ANN, BOB)
		eq(st(o), "requested")
		eq(st(o, part(o, "accepted", { crafter = OFF })), "requested", "somebody else's part is none")
		eq(st(o, part(o, "accepted")), "accepted")
		eq(st(o, part(o, "working")), "progress")
		eq(st(o, part(o, "ready")), "ready")
		local s, info = st(o, part(o, "declined"))
		eq(s, "cancelled"); eq(info.why, "declined")
		s, info = st(order(ANN, BOB, { state = "cancelled", closed = now() }), part(o, "handed"))
		eq(s, "cancelled"); eq(info.why, "cancelled")
	end)

	it("is delivered only with both confirmations: one side stays ready and says who is missing", function()
		local o = order(ANN, BOB)
		local s, info = st(o, part(o, "handed"))
		eq(s, "ready"); eq(info.missing, "buyer")
		local received = nextRev(o, { state = "received", closed = now() })
		s, info = st(received, part(o, "ready"))
		eq(s, "ready"); eq(info.missing, "crafter")
		s, info = st(received)
		eq(s, "ready"); eq(info.missing, "crafter")
		s, info = st(received, part(o, "handed"))
		eq(s, "delivered"); eq(info.closed, received.closed)
	end)

	it("expires a request after 14 days, an order after its day, and one without a day after 60 quiet days (Q50)", function()
		local t = now()
		local o = order(ANN, BOB)
		eq(st(o, nil, t + 14 * DAY - 5), "requested")
		local s, info = st(o, nil, t + 14 * DAY)
		eq(s, "cancelled"); eq(info.why, "expired"); eq(info.closed, t + 14 * DAY)
		local by = order(ANN, BOB, { by = today(t + 3 * DAY) })
		eq(st(by, part(by, "accepted"), t + 9 * DAY), "accepted")
		eq(st(by, part(by, "accepted"), t + 12 * DAY), "cancelled")
		local late = order(ANN, BOB, { by = today(t + 40 * DAY) })
		eq(st(late, nil, t + 15 * DAY), "cancelled", "still not accepted")
		eq(st(late, part(late, "accepted"), t + 45 * DAY), "accepted")
		eq(st(o, part(o, "accepted"), t + 59 * DAY), "accepted")
		eq(st(o, part(o, "accepted"), t + 60 * DAY), "cancelled")
		eq(st(o, part(o, "handed"), t + 61 * DAY), "cancelled", "confirmed by one side only")
		eq(st(o, part(o, "accepted", { at = t + 50 * DAY }), t + 61 * DAY), "accepted", "a step counts again")
		local delivered = nextRev(o, { state = "received", closed = t })
		eq(st(delivered, part(o, "handed"), t + 400 * DAY), "delivered")
	end)

	it("shows the orders of somebody who left the guild as cancelled, once the roster is read", function()
		accept(order(ANN, BOB))
		local o = order("Player-1-0000DEAD", BOB, nil, 3)
		S():Records("orders")[o.id] = o
		local row = O():Get(o.id)
		eq(row.state, "cancelled"); eq(row.why, "left")
		eq(#row.actions, 0)
		eq(state("O:" .. ANN .. ":1"), "requested")
		eq(S():Count("orders"), 2, "the records stay")
	end)

	it("deletes a closed order and its part together 30 days after it closed", function()
		local t = now()
		local o = order(ANN, BOB, { created = t, time = t })
		local done = nextRev(o, { state = "received", closed = t })
		accept(done)
		accept(part(o, "handed"))
		local declined = order(ANN, BOB, nil, 2)
		accept(declined)
		accept(part(declined, "declined"))
		accept(order(ANN, BOB, nil, 3))   -- never accepted: closed after 14 days, gone after 44
		local open = order(ANN, BOB, { by = today(t + 60 * DAY) }, 4)
		accept(open)
		accept(part(open, "accepted"))
		Mock.SetServerTime(t + 29 * DAY)
		eq(S():Prune(), 0)
		Mock.SetServerTime(t + 31 * DAY)
		eq(S():Prune(), 4, "the delivered and the declined one, each with its part")
		eq(S():Count("orders"), 3)
		-- a peer that still holds the delivered one sends it again, the part first as a sync does, or the order alone
		local ok, why = accept(done)
		eq(ok, false); eq(why, "expired", "the order alone")
		accept(part(o, "handed", { time = t, at = t }))
		ok, why = accept(done)
		eq(ok, false); eq(why, "expired", "after its part")
		Mock.SetServerTime(t + 45 * DAY)
		eq(S():Prune(), 1)
		eq(S():Count("orders"), 2, "the open one and its part stay")
	end)

	it("takes a delivery confirmed late whole, the part first as a sync sends it", function()
		local t = now()
		local o = order(ANN, BOB, { created = t, time = t })
		local done = nextRev(o, { state = "received", closed = t })
		Mock.SetServerTime(t + 40 * DAY)
		local p = part(o, "handed", { time = t + 20 * DAY, at = t + 20 * DAY })
		S():Receive("orders", { p, done }, "Officer", "GUILD")
		eq(S():Count("orders"), 2)
		eq(state(o.id), "delivered")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("placing and taking steps", function()
	before_boot(setup())

	it("the buyer places an order and both confirm it in the end", function()
		local heard = {}
		A().Bus:On("CRAFT_REQUESTED", function(g, r) heard[#heard + 1] = { g, r } end)
		local rec = must(place({ mats = "mixed", price = " 5g |c ", note = "two\nlines", by = "" }))
		eq(rec.id, "O:" .. ME .. ":1"); eq(rec.price, "5g c"); eq(rec.note, "two lines"); eq(rec.state, "open")
		isNil(rec.by)
		deepEq(heard, { { BOB, POTION } })
		local row = O():Get(rec.id)
		truthy(row.mine); falsy(row.forMe)
		deepEq(row.actions, { "cancel" })
		falsy(O():Act(rec.id, "accept"))
		local p = part(rec, "accepted")
		truthy(accept(p, BOB))
		deepEq(O():Get(rec.id).actions, { "received", "cancel" })
		truthy(O():Act(rec.id, "received"))
		row = O():Get(rec.id)
		eq(row.state, "ready"); eq(row.missing, "crafter"); deepEq(row.actions, {})
		truthy(accept(nextRev(p, { state = "handed" }), BOB))
		eq(state(rec.id), "delivered")
		eq(S():Get("orders", rec.id).state, "received")
	end)

	it("the crafter takes every step on an order of somebody else", function()
		local o = order(ANN, ME)
		accept(o)
		local row = O():Get(o.id)
		truthy(row.forMe)
		deepEq(row.actions, { "accept", "decline" })
		falsy(O():Act(o.id, "received"))
		falsy(O():Act(o.id, "cancel"))
		truthy(O():Act(o.id, "accept", "on it"))
		deepEq(O():Get(o.id).actions, { "working", "ready", "handed", "decline" })
		truthy(O():Act(o.id, "working"))
		eq(S():Get("orders", "A" .. o.id:sub(2)).note, "on it", "the note stays")
		truthy(O():Act(o.id, "ready"))
		local ok, why = O():Act(o.id, "working")
		eq(ok, false); eq(why, "state")
		truthy(O():Act(o.id, "handed"))
		row = O():Get(o.id)
		eq(row.state, "ready"); eq(row.missing, "buyer"); deepEq(row.actions, {})
		eq(S():Get("orders", o.id).author, ANN, "the buyer's record was not touched")
		eq(S():Get("orders", o.id).rev, 1)
		truthy(accept(nextRev(o, { state = "received", closed = now() })))
		eq(state(o.id), "delivered")
	end)

	it("an order between two others can be read, not changed", function()
		local o = order(ANN, BOB)
		accept(o)
		deepEq(O():Get(o.id).actions, {})
		local ok, why = O():Act(o.id, "cancel")
		eq(ok, false); eq(why, "owner")
	end)

	it("refuses what is not an order", function()
		sameAccount(ME, ALT)
		for why, spec in pairs({ crafter = { crafter = "Player-1-0000FFFF" }, own = { crafter = ALT }, count = { count = 0 },
			mats = { mats = "none" }, price = { price = ("p"):rep(25) }, note = { note = ("n"):rep(81) }, by = { by = "tomorrow" },
			recipe = { recipe = 0 } }) do
			local rec, w = place(spec)
			isNil(rec, why); eq(w, why)
		end
		local rec, w = place({ crafter = ME })
		isNil(rec); eq(w, "own")
		rec, w = place({ by = "2000-01-01" })
		isNil(rec); eq(w, "by")
		truthy(place({ by = O().DayText(today(now() + 3 * DAY)), crafter = ANN }), "an offline crafter too")
	end)

	it("keeps at most 10 open orders per account, and counts only the open ones (ORD-06)", function()
		local ids = {}
		for i = 1, O().MAX_OPEN do ids[i] = must(place()).id end
		local rec, why = place()
		isNil(rec); eq(why, "limit")
		truthy(O():Act(ids[1], "cancel"))
		truthy(place())
		eq(O():OpenCount(), O().MAX_OPEN)
	end)

	it("never reuses a number, also after the local counter is gone", function()
		local a = must(place())
		A().GuildKey:Data().econ = nil
		eq(must(place()).id, "O:" .. ME .. ":2")
		truthy(a)
	end)

	it("writes and takes at most 30 revisions of an author an hour (ORD-06)", function()
		local written = 0
		for _ = 1, 20 do
			local rec, why = place()
			if not rec then eq(why, "rate") break end
			written = written + 1
			if O():Act(rec.id, "cancel") then written = written + 1 end
		end
		eq(written, O().WRITES_PER_HOUR)
		local taken = 0
		for n = 1, 40 do
			local ok, why = accept(order(ANN, BOB, nil, n))
			if ok then taken = taken + 1 else eq(why, "rate") end
		end
		eq(taken, O().WRITES_PER_HOUR)
		Mock.Advance(HOUR + 5)
		truthy(accept(order(ANN, BOB, nil, 41)))
		truthy(place())
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the craft requests of M3 (the migration, SPEC-17 §3.6)", function()
	before_boot(setup())

	local function asks()
		A().GuildKey:Data().craftAsks = {
			{ guid = BOB, recipeId = POTION, at = now() - 2 * DAY },
			{ guid = ANN, recipeId = FLASK, at = now() - HOUR },
			{ guid = BOB, recipeId = FLASK, at = now() - 8 * DAY },   -- too old
			{ guid = "Player-1-0000FFFF", recipeId = FLASK, at = now() },   -- left the guild
		}
	end

	it("offers the recent ones as orders and publishes none by itself", function()
		asks()
		local list = O():Earlier()
		eq(#list, 2)
		eq(list[1].guid, ANN); eq(list[2].guid, BOB)
		A().MarketView:Open("orders")
		Mock.Advance(600)
		eq(S():Count("orders"), 0, "nothing was published")
		truthy(V().frame.earlier:IsShown())
	end)

	it("Make it an order opens the window filled; placed, it is not offered again", function()
		asks()
		A().MarketView:Open("orders")
		V().frame.earlier.lines[2].make:Click()
		local d = V().dialog
		truthy(d:IsShown())
		eq(d.crafter:Selected(), BOB); eq(d.recipeId, POTION); eq(d.count:GetText(), "1")
		d.cancel:Click()
		eq(#O():Earlier(), 2, "closing the window keeps the request")
		V().frame.earlier.lines[2].make:Click()
		truthy(V():Place())
		eq(S():Count("orders"), 1)
		eq(#O():Earlier(), 1)
		A().GuildKey:Data().craftAsks = { { guid = BOB, recipeId = POTION, at = now() - 2 * DAY } }
		eq(#O():Earlier(), 0, "that request was already made an order")
	end)

	it("Dismiss removes it for good, also from the Action Center", function()
		asks()
		A().Actions:Refresh()
		A().MarketView:Open("orders")
		V().frame.earlier.lines[1].dismiss:Click()
		eq(#O():Earlier(), 1)
		eq(#A().GuildKey:Data().craftAsks, 2)
		for _, a in ipairs(A().GuildKey:Data().craftAsks) do truthy(a.guid ~= ANN) end
	end)

	it("keeps no new reminder: the orders replace them", function()
		ChatFrame_OpenChat = function() end
		truthy((A().Recipes:OpenCraftRequest(BOB, POTION)))
		isNil(A().GuildKey:Data().craftAsks)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the Action Center and the notices (SPEC-17 §3.7)", function()
	before_boot(setup())

	it("asks the crafter to answer a new order, and both to confirm a delivery", function()
		local o = order(ANN, ME)
		accept(o)
		settle()
		deepEq(titles(actionRows()), { "Ann ordered 2 × Minor Healing Potion" })
		eq(actionRows()[1].urgency, 2)
		deepEq(notices(), { "New craft order from Ann: 2 × Minor Healing Potion" })
		O():Act(o.id, "accept")
		eq(#actionRows(), 0)
		accept(nextRev(o, { state = "received", closed = now() }))
		deepEq(titles(actionRows()), { "Confirm the delivery of Minor Healing Potion" })
		O():Act(o.id, "handed")
		settle()
		eq(#actionRows(), 0)
		eq(notices()[1], "Order delivered: 2 × Minor Healing Potion")
		eq(#notices(), 2)
	end)

	it("tells the buyer each step once, and closes a declined order with Done", function()
		Mock.Advance(400)   -- past the window after the login, which groups the notices (NTF-05)
		local rec = place()
		local p = part(rec, "accepted")
		accept(p, BOB)
		settle()
		eq(#actionRows(), 0)
		deepEq(notices(), { "Bob accepted your order: Minor Healing Potion" })
		p = nextRev(p, { state = "ready" })
		accept(p, BOB)
		A().Bus:Emit("STORE_CHANGED", "orders", p.id, "remote")   -- the same state again: told once
		settle()
		eq(#notices(), 2)
		deepEq(titles(actionRows()), { "Bob has your Minor Healing Potion ready" })
		accept(nextRev(p, { state = "handed" }), BOB)
		deepEq(titles(actionRows()), { "Confirm the delivery of Minor Healing Potion" })
		local second = place({ crafter = ANN })
		accept(part(second, "declined"), ANN)
		settle()
		eq(notices()[1], "Ann declined your order: Minor Healing Potion")
		local rows = actionRows()
		eq(#rows, 2)
		eq(rows[2].title, "Your order was declined: Minor Healing Potion"); eq(rows[2].urgency, 1)
		A().Actions:Dismiss(rows[2])
		eq(#actionRows(), 1)
		Mock.Reload()
		settle()
		eq(#notices(), 4, "after a /reload nothing is told again")
		eq(#actionRows(), 1)
	end)

	it("opens the order from a row and from a notice", function()
		local o = order(ANN, ME)
		accept(o)
		settle()
		A().Actions:Open(actionRows()[1])
		eq(A().Shell.selected, "market")
		eq(V().selected, o.id)
		V().selected = nil
		for _, e in ipairs(A().Notify:Entries()) do if e.module == "orders" then A().Notify:Open(e) end end
		eq(V().selected, o.id)
	end)

	it("can be switched off by kind", function()
		truthy(A().SettingsModel.SetKind("orders", "new", false))
		accept(order(ANN, ME))
		settle()
		falsy(printed():find("New craft order", 1, true))
	end)
end)

describe("the notices without the Action Center", function()
	before_boot(setup(3, { econ = true, actions = false }))

	it("are chat lines, once", function()
		local o = order(ANN, ME)
		accept(o)
		settle()
		contains(printed(), "New craft order from Ann: 2 × Minor Healing Potion")
		Mock.Reload()
		A().Orders:Notices(o.id)
		settle()
		local _, n = printed():gsub("New craft order from Ann", "")
		eq(n, 1)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("nothing moves gold or items (ECO-01)", function()
	before_boot(setup())

	it("a whole order calls none of the game's functions that would", function()
		local called = {}
		local function stub(name) return function() called[#called + 1] = name error(name .. " was called", 0) end end
		for _, name in ipairs({ "InitiateTrade", "AcceptTrade", "SendMail", "TakeInboxItem", "TakeInboxMoney", "PlaceAuctionBid",
			"DepositGuildBankMoney", "WithdrawGuildBankMoney", "PickupGuildBankItem", "AutoStoreGuildBankItem",
			"PickupContainerItem", "SendChatMessage", "PickupPlayerMoney", "SetTradeMoney" }) do _G[name] = stub(name) end
		C_CraftingOrders = setmetatable({}, { __index = function(_, k) return stub("C_CraftingOrders." .. k) end })
		C_Mail = setmetatable({}, { __index = function(_, k) return stub("C_Mail." .. k) end })
		C_AuctionHouse = setmetatable({}, { __index = function(_, k) return stub("C_AuctionHouse." .. k) end })
		ChatFrame_OpenChat = function() end
		local rec = place()
		local p = part(rec, "handed")
		accept(p, BOB)
		O():Act(rec.id, "received")
		local theirs = order(ANN, ME)
		accept(theirs)
		for _, step in ipairs({ "accept", "working", "ready", "handed" }) do truthy(O():Act(theirs.id, step), step) end
		A().MarketView:Open("orders")
		V():Whisper(BOB)
		Mock.Advance(60)
		eq(#called, 0, table.concat(called, ", "))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("Request craft with the switch on", function()
	before_boot(setup())

	local function row(i) return R().frame.table.rows[i] end

	local function craftList()
		recipes(BOB)
		recipes(ANN)
		Mock.Slash("/accord professions")
		R():SetMode("craft")
		Mock.TypeInto(A().Shell.content.bar.search, "minor healing")
	end

	it("is on every crafter outside the own account, online or not, and opens the New order window", function()
		craftList()
		truthy(row(2).request:IsShown()); truthy(row(3).request:IsShown(), "Ann is offline: she can be ordered from")
		deepEq(R().RequestTip(row(3).data), { "Request craft", "Opens the New order window for Ann." })
		local chat = {}
		ChatFrame_OpenChat = function(text) chat[#chat + 1] = text end
		row(2).request:Click()
		local d = V().dialog
		truthy(d:IsShown())
		eq(d.crafter:Selected(), BOB); eq(d.recipeId, POTION)
		falsy(d.whisper:IsOn(), "the whisper is off by default")
		eq(#d.crafters, 2); eq(d.crafters[1].guid, BOB, "online first")
		eq(#chat, 0)
		d.count:SetText("3"); d.price:SetText("5g"); d.note:SetText("for the raid"); d.mats:Select("crafter")
		d.ok:Click()
		falsy(d:IsShown())
		local o = S():Get("orders", "O:" .. ME .. ":1")
		eq(o.count, 3); eq(o.price, "5g"); eq(o.note, "for the raid"); eq(o.mats, "crafter"); eq(o.crafter, BOB)
		contains(printed(), "Order placed with Bob.")
		eq(#chat, 0, "no whisper unless asked")
	end)

	it("writes the whisper too when asked, and the player sends it", function()
		craftList()
		local chat = {}
		ChatFrame_OpenChat = function(text) chat[#chat + 1] = text end
		local sent = #Mock.chat.sent
		row(2).request:Click()
		V().dialog.whisper:SetOn(true)
		V():Place()
		eq(#chat, 1); contains(chat[1], "Minor Healing Potion")
		eq(#Mock.chat.sent, sent, "nothing went out at the click")
	end)

	it("says why an order is refused and stays open; offline says so and locks the whisper", function()
		craftList()
		row(3).request:Click()
		local d = V().dialog
		contains(d.offline:GetText(), "Ann is offline")
		falsy(d.whisper:IsEnabled())
		d.count:SetText("0")
		d.ok:Click()
		truthy(d:IsShown())
		eq(d.status:GetText(), "How many: from 1 to 200.")
		eq(S():Count("orders"), 0)
	end)

	it("the catalogue says how many open orders a recipe has", function()
		recipes(BOB)
		accept(order(ANN, BOB))
		accept(order(OFF, BOB))
		R():OpenCatalogue(ALCHEMY)
		Mock.Advance(2)
		local found = false
		for _, r in ipairs(R().frame.table.rows) do
			if r:IsShown() and r.data and r.data.id == POTION then
				contains(r.detail:GetText(), "2 open orders")
				found = true
			end
		end
		truthy(found)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the Market view", function()
	before_boot(setup())

	local function rowsText()
		local out = {}
		for _, r in ipairs(V().frame.table:VisibleRows()) do out[#out + 1] = r.cells[1]:GetText() .. " / " .. r.cells[4]:GetText() end
		return out
	end

	local function four()
		local mine = place()
		local forMe = order(ANN, ME, { count = 4 })
		accept(forMe)
		accept(order(ANN, BOB, { count = 7 }, 2))
		local done = order(ANN, BOB, { count = 9 }, 3)
		accept(nextRev(done, { state = "cancelled", closed = now() }))
		return mine, forMe
	end

	it("lists the orders with the chips, the closed ones when asked, and searches", function()
		four()
		truthy(A().MarketView:Open("orders"))
		eq(#V().rows, 3)
		V().who = "mine"; A().MarketView:Redraw()
		deepEq(rowsText(), { "2 × Minor Healing Potion / Requested" })
		V().who = "forme"; A().MarketView:Redraw()
		deepEq(rowsText(), { "4 × Minor Healing Potion / Requested" })
		V().who = "all"; V().closed = true; A().MarketView:Redraw()
		eq(#V().rows, 4)
		eq(rowsText()[4], "9 × Minor Healing Potion / Cancelled")
		A().MarketView:SetSearch("bob")
		eq(#V().rows, 3)
		A().MarketView:SetSearch("nothing")
		eq(#V().rows, 0)
	end)

	it("takes a step from the row with a second click", function()
		local _, forMe = four()
		A().MarketView:Open("orders")
		V().who = "forme"; A().MarketView:Redraw()
		local r = V().frame.table.rows[1]
		eq(r.step:GetLabel(), "Accept")
		r.step:Click()
		eq(r.step:GetLabel(), "Confirm")
		isNil(S():Get("orders", "A" .. forMe.id:sub(2)), "one click writes nothing")
		r.step:Click()
		eq(S():Get("orders", "A" .. forMe.id:sub(2)).state, "accepted")
		eq(r.step:GetLabel(), "Working on it")
	end)

	it("has every step in the bar of the selected order, with the note", function()
		local mine, forMe = four()
		A().MarketView:Open("orders")
		V():Select(forMe.id)
		local f = V().frame
		local labels = {}
		for _, b in pairs(f.foot.buttons) do if b:IsShown() then labels[#labels + 1] = b:GetLabel() end end
		table.sort(labels)
		deepEq(labels, { "Accept", "Decline" })
		f.note:SetText("no vials")
		eq(V():Press(forMe.id, "decline"), "armed")
		f.note:SetText("no vials")
		truthy(V():Press(forMe.id, "decline"))
		eq(S():Get("orders", "A" .. forMe.id:sub(2)).note, "no vials")
		V():Select(mine.id)
		eq(V():Press(mine.id, "cancel"), "armed")
		truthy(V():Press(mine.id, "cancel"))
		eq(S():Get("orders", mine.id).state, "cancelled")
	end)

	it("says who has not confirmed a delivery", function()
		local rec = place()
		accept(part(rec, "handed"), BOB)
		local row = O():Get(rec.id)
		eq(V().StateText(row), "Confirm: you")
		eq(V().WaitingText(row), "Delivered on Bob's side, waiting for you to confirm")
		local theirs = order(ANN, BOB)
		accept(theirs)
		accept(nextRev(theirs, { state = "received", closed = now() }))
		row = O():Get(theirs.id)
		eq(V().StateText(row), "Waiting: Bob")
		eq(V().WaitingText(row), "Delivered on Ann's side, waiting for Bob to confirm")
		truthy(#V().TipLines(row) > 3)
	end)

	it("shows the open orders on the member card", function()
		accept(order(ANN, BOB))
		local section = V().CardSection(A().Roster:ByGUID(BOB))
		eq(section.title, "Market")
		eq(section.lines[1].text, "To craft: 2 × Minor Healing Potion for Ann · Requested")
		section.lines[1].onClick()
		eq(A().Shell.selected, "market")
		isNil(V().CardSection(A().Roster:ByGUID(OFF)))
	end)

	it("lists in What I share what this character wrote", function()
		place({ price = "5g", note = "soon" })
		local theirs = order(ANN, ME)
		accept(theirs)
		O():Act(theirs.id, "accept")
		local found
		for _, s in ipairs(A().ShareModel.Describe()) do if s.id == "orders" then found = s end end
		eq(found.records, 2)
		local text = table.concat(found.lines, "\n")
		contains(text, "Your order: 2 × Minor Healing Potion (open) · price: 5g · note: soon")
		contains(text, "As the crafter: 2 × Minor Healing Potion (Accepted)")
	end)

	it("counts records and refusals in /accord debug, without a name", function()
		accept(order(ANN, BOB))
		accept(order(ANN, BOB, { author = OFF }, 2), OFF)
		local report = A().Diagnostics.Report()
		contains(report, "Orders: 1 order(s) (1 open), 0 crafter part(s)")
		contains(report, "owner 1")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the demo guild", function()
	before_boot(function(M) M.features = { econ = true } end)

	it("has five orders in different states and sends nothing", function()
		Mock.Slash("/accord demo")
		Mock.Advance(2)
		local states = {}
		for _, row in ipairs(O():List({ closed = true })) do states[#states + 1] = row.state end
		table.sort(states)
		deepEq(states, { "progress", "ready", "ready", "requested", "requested" })
		truthy(A().MarketView:Open("orders"))
		Mock.Advance(2)
		truthy(#actionRows() >= 3, "rows: " .. #actionRows())
		eq(#Mock.chat.sent, 0)
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("with the switch econ off", function()
	before_boot(setup(3, { econ = false }))

	it("shows, writes, takes and sends nothing of it", function()
		falsy(A().Features.On("econ"))
		falsy(S().IsActive("orders"))
		local rec, why = place()
		isNil(rec); eq(why, "off")
		local ok, w = accept(order(ANN, BOB))
		eq(ok, false); eq(w, "set")
		Mock.Slash("/accord help")
		falsy(printed():find("/accord market", 1, true))
		Mock.Slash("/accord market")
		contains(printed(), "Unknown command 'market'")
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "market") end
		falsy(A().MarketView:Open("orders"))
		for _, s in ipairs(A().ShareModel.Describe()) do truthy(s.id ~= "orders") end
		for _, p in ipairs(A().Actions:Providers()) do truthy(p.id ~= "orders") end
		for _, m in ipairs(A().SettingsModel.NoticeModules()) do truthy(m.id ~= "orders") end
		isNil(V().CardSection(A().Roster:ByGUID(BOB)))
		falsy(A().Diagnostics.Report():find("Orders:", 1, true))
		eq(S():Count("orders"), 0)
	end)

	it("keeps Request craft as the whisper of M3, with its reminder", function()
		recipes(BOB)
		Mock.Slash("/accord professions")
		R():SetMode("craft")
		Mock.TypeInto(A().Shell.content.bar.search, "minor healing")
		local chat = {}
		ChatFrame_OpenChat = function(text) chat[#chat + 1] = text end
		R().frame.table.rows[2].request:Click()
		eq(#chat, 1)
		isNil(V().dialog)
		eq(#A().GuildKey:Data().craftAsks, 1)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The summary `ec` and the simulator
---------------------------------------------------------------------------------------------------------------------
describe("the summary of M13 (SPEC-17 §10.2)", function()
	before_boot(setup())

	local function capture()
		local sent, T_ = {}, A().Transport
		local original = T_.Send
		T_.Send = function(self, dist, msg, opts)
			sent[#sent + 1] = { dist = dist, msg = msg }
			return original(self, dist, msg, opts)
		end
		return sent
	end

	it("goes in ec, even empty, and leaves the summary per author as it was", function()
		local sent = capture()
		A().Sync:SendHello()
		local first = sent[#sent].msg
		for _, e in ipairs(sent) do if e.msg.t == "HELLO" then first = e.msg end end
		eq(first.ec, "")
		local s0 = first.s
		place()
		Mock.Advance(400)
		A().Sync:SendHello()
		local last
		for _, e in ipairs(sent) do if e.msg.t == "HELLO" then last = e.msg end end
		eq(#last.ec, 11, "one entry: this buyer")
		eq(last.s, s0, "an older client sees nothing new")
		A().Sync.BLOCK_OVER = -1
		Mock.Advance(400)
		A().Sync:SendHello()
		local bh
		for _, e in ipairs(sent) do if e.msg.t == "BHELLO" then bh = e.msg end end
		eq(#bh.ecb, 3)
		A().Sync.BLOCK_OVER = 200
	end)

	it("keeps a BHELLO of a large guild with every summary under 512 B", function()
		local Sy, groups = A().Sync, {}
		for i = 1, 1000 do
			local guid = ("Player-1-%08X"):format(0x50000 + i)
			groups[guid] = { key = Sy.KeyOf(guid), d = i * 7919 % 16777216, t = 1767225600 + i, author = guid }
			for _, kind in ipairs({ { true, Sy.ExtraName, 1000 }, { "hb", Sy.HandbookName, 12 }, { "rc", Sy.CatalogueName, 12 },
				{ "ec", Sy.EconName, 300 } }) do
				if i <= kind[3] then
					local name = kind[2](guid)
					groups[name] = { key = Sy.KeyOf(name), d = i * 104729 % 16777216, t = 1767225600 + i, author = guid, extra = kind[1] }
				end
			end
		end
		local msg = { b = Sy:EncodeBlocks(groups), cb = Sy:EncodeBlocks(groups, true), hbb = Sy:EncodeBlocks(groups, "hb"),
			rcb = Sy:EncodeBlocks(groups, "rc"), ecb = Sy:EncodeBlocks(groups, "ec"), n = 1000, av = "0.13.0" }
		local wire = A().Codec:Encode("BHELLO", msg)
		T.log(("orders: a BHELLO with every summary is %d B"):format(#wire))
		truthy(#wire <= 512, "BHELLO " .. #wire)
	end)
end)

describe("the orders between clients", function()
	local function simulated(M) M.features = { econ = true } end

	local function rowState(sim, i, id)
		local row = sim:client(i):addon().Orders:Get(id)
		return row and row.state
	end

	it("reach both sides and the guild, every client with the same state, also one that was away", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 5 }, setup = simulated, accounts = true, seed = 131 }
		sim:advance(120)
		local buyer, crafter = sim:client(2), sim:client(3)
		local rec = must(buyer:addon().Orders:Create({ crafter = crafter:guid(), recipe = POTION, count = 2, price = "5g" }))
		sim:advance(60)
		for _, j in ipairs({ 1, 2, 3, 4 }) do eq(rowState(sim, j, rec.id), "requested", "client " .. j) end
		truthy(crafter:addon().Orders:Act(rec.id, "accept"))
		sim:advance(60)
		truthy(crafter:addon().Orders:Act(rec.id, "handed"))
		sim:advance(60)
		for _, j in ipairs({ 1, 2, 3, 4 }) do eq(rowState(sim, j, rec.id), "ready", "client " .. j) end
		truthy(buyer:addon().Orders:Act(rec.id, "received"))
		sim:advance(60)
		for _, j in ipairs({ 1, 2, 3, 4 }) do eq(rowState(sim, j, rec.id), "delivered", "client " .. j) end
		sim:client(5):login()
		truthy(sim:advanceUntil(function() return rowState(sim, 5, rec.id) == "delivered" end, 25 * 60), "the one away")
		for i = 1, 5 do
			local stats = sim:client(i):addon().Store.stats
			for why in pairs(stats.reasons) do eq(why, "wait", "client " .. i) end
			eq(sim:client(i):addon().Sync.state.stats.refused, 0, "client " .. i)
		end
	end)

	-- The scenario of M10.8 (SPEC-17 §10.3): 50 clients, 45 minutes of churn; with `with`, one new order every 5 minutes for
	-- the whole guild, taken through every step. One client in ten has the switch off.
	local function churn(with)
		local N = 50
		local function off(i) return i % 10 == 0 end
		local sim = Sim.new{ clients = N, officers = { 1, 11, 21, 31, 41 }, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42,
			setup = function(M, i) M.features = { econ = not off(i) } end }
		local ordersFrom = 0
		for i = 1, N do
			if off(i) then
				local tr = sim:client(i):addon().Transport
				local original = tr.wire
				tr.wire = function(prio, txt, dist, target, done)
					local m = sim:client(i):addon().Codec:Decode(txt)
					if type(m) == "table" and (m.s == "orders" or m.ec ~= nil or m.ecb ~= nil) then ordersFrom = ordersFrom + 1 end
					return original(prio, txt, dist, target, done)
				end
			end
		end
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		local writes, lockUntil = {}, {}
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
		local live, placed, steps = {}, 0, 0
		local SEQUENCE = { { "crafter", "accept" }, { "crafter", "working" }, { "crafter", "ready" }, { "crafter", "handed" },
			{ "buyer", "received" } }
		local function pick(not_)
			for _ = 1, 200 do
				local i = 1 + math.floor(rand() * N) % N
				if sim:client(i).online and not off(i) and i ~= not_ then return i end
			end
		end
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
					if not writes[i] then writeNext(c) end
				end
				if lockUntil[i] and sim.time >= lockUntil[i] then
					c:restrict({ lockdown = false })
					lockUntil[i] = nil
				end
			end
			if with and step % 10 == 1 then
				local b = pick()
				local c = b and pick(b)
				if c then
					local rec = sim:client(b):addon().Orders:Create({ crafter = sim:client(c):guid(), recipe = POTION, count = 20,
						price = ("p"):rep(24), note = ("n"):rep(80) })
					if rec then
						placed = placed + 1
						live[#live + 1] = { id = rec.id, buyer = b, crafter = c, step = 1 }
					end
				end
			end
			for _, o in ipairs(live) do
				local s = SEQUENCE[o.step]
				local c = s and sim:client(o[s[1]])
				if c and c.online and c:addon().Orders:Act(o.id, s[2], ("x"):rep(60)) then
					o.step = o.step + 1
					steps = steps + 1
				end
			end
			sim:advance(30)
		end
		eq(ordersFrom, 0, "a client with the switch off sends nothing of M13")
		for i = 1, N do
			local c = sim:client(i)
			if c.online then
				if off(i) then eq(c:addon().Store:Count("orders"), 0, "client " .. i .. " takes nothing") end
				for why, n in pairs(c:addon().Store.stats.reasons) do
					eq(why, "wait", "client " .. i .. " refused " .. n .. " for " .. why)
				end
				eq(c:addon().Sync.state.stats.quarantined, 0)
			end
		end
		return sim:stats(), placed, steps
	end

	it("50 clients of a guild in step stay inside the shared traffic budget (SPEC-09 §7)", function()
		local base = churn(false)
		local st, placed, steps = churn(true)
		T.log(("orders: churn %.0f B/min per client on average (%.0f without them), %.0f at most (%.0f); %d orders, %d steps"):format(
			st.avg.bytesPerMinute, base.avg.bytesPerMinute, st.max.bytesPerMinute, base.max.bytesPerMinute, placed, steps))
		truthy(placed >= 7, "orders " .. placed); truthy(steps >= 15, "steps " .. steps)
		truthy(st.avg.bytesPerMinute <= 450, "churn average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2048, "churn busiest client " .. st.max.bytesPerMinute)
	end)
end)

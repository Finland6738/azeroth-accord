-- The buy and sell board (M13.5; SPEC-17 §6, BRD-01..BRD-03; SPEC-10 Q47): who writes what; a deal closed only by both
-- confirmations and never reopened; posts that expire by themselves; locked content; hidden authors; the Board mode and
-- the New post window; the member card, What I share, /accord debug and the demo; the switch "econ"; between clients, an
-- older client and the shared traffic.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function B() return AzerothAccord.Board end
local function V() return AzerothAccord.BoardView end

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
local NAME = { [OFF] = "Officer", [BOB] = "Bob", [ANN] = "Ann", [ALT] = "Alt" }

local function post(guid, n, fields)
	local r = { id = "P:" .. guid .. ":" .. (n or 1), author = guid, rev = 1, time = now(), kind = "wts", item = LINEN,
		count = 20, price = "1g", ["until"] = now() + 3 * DAY, state = "open" }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

local function answer(postId, guid, state, fields)
	local r = { id = "D" .. postId:sub(2) .. ":" .. guid, author = guid, rev = 1, time = now(), state = state or "want" }
	for k, v in pairs(fields or {}) do r[k] = v end
	return r
end

local function accept(rec, sender) return S():Accept("board", rec, { sender = NAME[sender or rec.author], dist = "GUILD" }) end

local function refused(rec, sender, why)
	local ok, w = accept(rec, sender)
	eq(ok, false, "refused: " .. tostring(why))
	eq(w, why)
end

local function must(rec, why) truthy(rec, tostring(why)) return rec end
local function printed() return table.concat(Mock.PlainOutput(), "\n") end

-- Every function of the game that moves gold or items fails the test when called (ECO-01).
local function forbidTrade()
	for _, name in ipairs({ "InitiateTrade", "AcceptTrade", "SendMail", "TakeInboxItem", "PlaceAuctionBid",
		"DepositGuildBankMoney", "WithdrawGuildBankMoney", "PickupContainerItem" }) do
		_G[name] = function() fail("called " .. name) end
	end
end

---------------------------------------------------------------------------------------------------------------------
describe("the records of the board (BRD-01..BRD-03)", function()
	before_boot(setup())

	it("takes a post from its author, an alt of the account or an officer's relay, from nobody else", function()
		truthy(accept(post(BOB)))
		refused(post(ANN, 1, { author = OFF }), OFF, "owner")
		refused(post(ANN, 1, { author = BOB }), BOB, "owner")
		refused(post(ANN), BOB, "relay")
		truthy(accept(post(ANN), OFF))
		for _, g in ipairs({ BOB, ALT }) do
			S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = now(), token = "tok",
				chars = { { guid = BOB }, { guid = ALT } }, main = BOB }
		end
		truthy(accept(post(ALT, 1, { author = BOB })))
		refused(answer("P:" .. BOB .. ":1", ALT), ALT, "owner")   -- not from an alt of the author
	end)

	it("takes an answer from its character only, never the author's own", function()
		local p = post(BOB)
		truthy(accept(p))
		refused(answer(p.id, BOB), BOB, "owner")
		refused(answer(p.id, ANN, "want", { author = OFF }), OFF, "owner")
		refused(answer(p.id, ANN), BOB, "relay")
		truthy(accept(answer(p.id, ANN), OFF))
	end)

	it("refuses a shape that is not the board's", function()
		for what, fields in pairs({
			kind = { kind = "give" }, item = { item = 0 }, none = { count = 0 }, many = { count = 10000 },
			price = { price = ("p"):rep(25) }, priceBar = { price = "|c" }, note = { note = ("n"):rep(81) },
			far = { ["until"] = now() + 8 * DAY }, frac = { ["until"] = now() + 0.5 }, state = { state = "sold" },
			withOpen = { with = ANN }, doneNobody = { state = "done" }, doneSelf = { state = "done", with = BOB },
			extra = { gold = 5 }, id = { id = "P:x:1" },
		}) do
			local ok, why = accept(post(BOB, 1, fields), BOB)
			eq(ok, false, what); eq(why, "owner", what)
		end
		truthy(accept(post(BOB, 1, { price = ("p"):rep(24), note = ("n"):rep(80), count = 9999, ["until"] = now() + 7 * DAY })))
		for what, fields in pairs({ state = { state = "yes" }, extra = { price = "1g" }, note = { note = ("n"):rep(81) } }) do
			local rec = answer("P:" .. BOB .. ":1", ANN, "want", fields)
			local ok, why = accept(rec, ANN)
			eq(ok, false, what); eq(why, "owner", what)
		end
	end)

	it("holds the longest records inside their sizes", function()
		local long, other = "Player-1234-0ABCDEF123456789", "Player-1234-0ABCDEF987654321"
		local p = { id = "P:" .. long .. ":999999999", author = long, rev = 2147483647, time = now(), kind = "wts",
			item = 2147483647, count = 9999, price = ("p"):rep(24), note = ("n"):rep(80), ["until"] = now(),
			state = "withdrawn", with = other }
		truthy(A().Config.EstimateSize(p) <= B().POST_BYTES, "post " .. A().Config.EstimateSize(p))
		local d = { id = "D:" .. long .. ":999999999:" .. other, author = other, rev = 2147483647, time = now(),
			state = "withdrawn", note = ("n"):rep(80) }
		truthy(A().Config.EstimateSize(d) <= B().ANSWER_BYTES, "answer " .. A().Config.EstimateSize(d))
		eq(S().SETS.board.maxBytes, B().POST_BYTES)
	end)

	it("never changes the content of a post, and a withdrawn one stays withdrawn", function()
		local p = post(BOB)
		truthy(accept(p))
		for what, fields in pairs({ kind = { kind = "wtb" }, item = { item = SILK }, count = { count = 21 },
			price = { price = "2g" }, ["until"] = { ["until"] = p["until"] + 60 } }) do
			local ok, why = accept(post(BOB, 1, { rev = 2, kind = fields.kind, item = fields.item, count = fields.count,
				price = fields.price, ["until"] = fields["until"] or p["until"] }), BOB)
			eq(ok, false, what); eq(why, "locked", what)
		end
		truthy(accept(post(BOB, 1, { rev = 2, state = "withdrawn", note = "gone", ["until"] = p["until"] })))
		refused(post(BOB, 1, { rev = 3, ["until"] = p["until"] }), BOB, "locked")
	end)

	it("keeps an answer that arrives before its post (BRD-03)", function()
		local p = post(BOB)
		refused(answer(p.id, ANN), OFF, "wait")
		eq(#B().waiting, 1)
		eq(S():Count("board"), 0)
		truthy(accept(p))
		eq(S():Count("board"), 2)
		eq(#B().waiting, 0)
	end)

	it("takes at most 20 revisions of an author an hour", function()
		for n = 1, 20 do truthy(accept(post(BOB, n)), n) end
		refused(post(BOB, 21), BOB, "rate")
		Mock.Advance(HOUR + 1)
		truthy(accept(post(BOB, 22)))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the deal (SPEC-17 §6.2)", function()
	before_boot(setup())

	local function mine(spec)
		spec = spec or {}
		spec.kind, spec.item = spec.kind or "wts", spec.item or LINEN
		return must(B():Post(spec))
	end

	it("stays open while one side only has confirmed (criterion)", function()
		forbidTrade()
		local p = mine({ count = 5, price = "1g" })
		truthy(accept(answer(p.id, BOB)))
		eq(B():Get(p.id).state, "open")
		truthy(B():Act(p.id, "confirm", BOB))
		local row = B():Get(p.id)
		eq(row.state, "open")
		eq(row.withName, "Bob")
		eq(V().StatusText(row), "Confirmed by Testchar, waiting for Bob")
		-- the others still see it open
		truthy(accept(answer(p.id, ANN)))
		eq(B():Get(p.id).state, "open")
		-- the other side's confirmation alone, on a post of somebody else
		local q = post(BOB)
		truthy(accept(q))
		truthy(B():Act(q.id, "deal"))
		truthy(B():Act(q.id, "confirm"))
		row = B():Get(q.id)
		eq(row.state, "open")
		eq(V().StatusText(row), "Confirmed by Testchar, waiting for Bob")
		eq(#Mock.errors, 0)
	end)

	it("is closed with both confirmations and is not reopened", function()
		forbidTrade()
		local p = mine()
		truthy(accept(answer(p.id, BOB)))
		truthy(B():Act(p.id, "confirm", BOB))
		truthy(accept(answer(p.id, BOB, "done", { rev = 2 })))
		local row = B():Get(p.id)
		eq(row.state, "closed")
		eq(V().StatusText(row), "Deal closed between Testchar and Bob")
		eq(#row.actions, 0)
		for _, action in ipairs({ "unconfirm", "withdraw", "confirm" }) do
			eq(select(2, B():Act(p.id, action, BOB)), "state", action)
		end
		-- a revision written well after the closing, from a forged client, is refused
		Mock.Advance(B().LOCK_GRACE + 5, 30)
		refused(answer(p.id, BOB, "withdrawn", { rev = 3 }), BOB, "locked")
		local q = post(BOB)
		truthy(accept(q))
		truthy(B():Act(q.id, "deal"))
		truthy(B():Act(q.id, "confirm"))
		truthy(accept(post(BOB, 1, { rev = 2, state = "done", with = ME, ["until"] = q["until"] })))
		eq(B():Get(q.id).state, "closed")
		Mock.Advance(B().LOCK_GRACE + 5, 30)
		refused(post(BOB, 1, { rev = 3, ["until"] = q["until"] }), BOB, "locked")
		refused(post(BOB, 1, { rev = 3, state = "done", with = ANN, ["until"] = q["until"] }), BOB, "locked")
		eq(B():Get(q.id).state, "closed")
	end)

	it("lets a withdrawal that crossed the other confirmation stand", function()
		local q = post(BOB)
		truthy(accept(q))
		truthy(accept(post(BOB, 1, { rev = 2, state = "done", with = ME, ["until"] = q["until"] })))
		truthy(B():Act(q.id, "deal"))
		truthy(B():Act(q.id, "confirm"))
		eq(B():Get(q.id).state, "closed")
		Mock.Advance(5)
		truthy(accept(post(BOB, 1, { rev = 3, ["until"] = q["until"] })))
		eq(B():Get(q.id).state, "open")
	end)

	it("lets each side take its word back before the other confirms", function()
		local p = mine()
		truthy(accept(answer(p.id, BOB)))
		truthy(B():Act(p.id, "confirm", BOB))
		truthy(B():Act(p.id, "unconfirm", BOB))
		local row = B():Get(p.id)
		eq(row.state, "open"); isNil(row.with); eq(row.rec.state, "open")
		truthy(B():Act(p.id, "withdraw"))
		eq(B():Get(p.id).state, "withdrawn")
		eq(#B():List(), 0)
		local q = post(BOB)
		truthy(accept(q))
		truthy(B():Act(q.id, "deal", nil, "for me"))
		eq(B():Get(q.id).my.note, "for me")
		truthy(B():Act(q.id, "confirm"))
		truthy(B():Act(q.id, "unconfirm"))
		eq(B():Get(q.id).my.state, "want")
		eq(B():Get(q.id).my.note, "for me")
		truthy(B():Act(q.id, "drop"))
		isNil(B():Get(q.id).my)
		truthy(B():Act(q.id, "deal"))
		eq(B():Get(q.id).my.state, "want")
	end)

	it("expires a post by itself, from the date (criterion)", function()
		local p = mine({ days = 1 })
		truthy(accept(post(BOB)))   -- three days
		eq(#B():List(), 2)
		Mock.Advance(DAY + 60, 600)
		eq(#B():List(), 1, "gone without a write")
		eq(S():Get("board", p.id).rev, 1)
		eq(B():Get(p.id).state, "expired")
		eq(select(2, B():Act(p.id, "withdraw")), "state")
		eq(B():OpenCount(), 0)
		-- one confirmation does not keep it alive
		local q = "P:" .. BOB .. ":1"
		truthy(B():Act(q, "deal"))
		truthy(B():Act(q, "confirm"))
		Mock.Advance(2 * DAY, 600)
		eq(#B():List(), 0)
		-- a confirmation written after the end closes nothing
		truthy(accept(post(BOB, 1, { rev = 2, state = "done", with = ME, ["until"] = S():Get("board", q)["until"] })))
		eq(B():Get(q).state, "expired")
		Mock.Advance(8 * DAY, 3600)
		S():Prune()
		eq(S():Count("board"), 0, "records go 7 days after the end")
	end)

	it("keeps a closed deal 7 days, and does not take it back once deleted", function()
		local p = mine({ days = 7 })
		truthy(accept(answer(p.id, BOB, "done")))
		truthy(B():Act(p.id, "confirm", BOB))
		eq(B():Get(p.id).state, "closed")
		local held, d = S().Copy(S():Get("board", p.id)), S().Copy(S():Get("board", "D" .. p.id:sub(2) .. ":" .. BOB))
		Mock.Advance(6 * DAY, 3600)
		S():Prune()
		eq(S():Count("board"), 2)
		eq(#B():List(), 1)
		Mock.Advance(DAY + HOUR, 600)
		S():Prune()
		eq(S():Count("board"), 0)
		-- the sync sends the answer first: it waits, and the post is then judged with it
		refused(d, OFF, "wait")
		refused(held, OFF, "expired")
		refused(held, ME == held.author and OFF or held.author, "expired")
		eq(S():Count("board"), 0)
	end)

	it("opens at most 10 posts per account and says why not", function()
		local function why(spec) local rec, w = B():Post(spec) isNil(rec) return w end
		eq(why({ kind = "x", item = LINEN }), "kind")
		eq(why({ kind = "wts" }), "item")
		eq(why({ kind = "wts", item = LINEN, count = 0 }), "count")
		eq(why({ kind = "wts", item = LINEN, days = 8 }), "days")
		eq(why({ kind = "wts", item = LINEN, price = ("p"):rep(25) }), "price")
		eq(why({ kind = "wts", item = LINEN, note = ("n"):rep(81) }), "note")
		local rec = mine({ price = " 5g\n|cff " })
		eq(rec.price, "5g cff")
		eq(rec["until"], now() + 3 * DAY)
		for _ = 2, 10 do mine() end
		eq(why({ kind = "wts", item = LINEN }), "limit")
		truthy(B():Act(rec.id, "withdraw"))
		eq(mine().id, "P:" .. ME .. ":11", "a number is not used twice")
	end)

	it("hides the posts of a person on this computer, never the own", function()
		truthy(accept(post(BOB)))
		mine()
		falsy(B():Hide(ME))
		local sent = #Mock.chat.sent
		truthy(B():Hide(BOB))
		eq(#B():List(), 1)
		eq(B():HiddenCount(), 1)
		eq(#Mock.chat.sent, sent)
		truthy(B():UnhideAll())
		eq(#B():List(), 2)
	end)

	it("keeps only what the player can help with", function()
		truthy(accept(post(BOB, 1, { kind = "wtb", item = LINEN })))
		truthy(accept(post(BOB, 2, { kind = "wtb", item = COPPER })))
		truthy(accept(post(BOB, 3, { kind = "wts", item = SILK })))
		truthy(accept(post(BOB, 4, { kind = "wts", item = COPPER })))
		A().Config.db.account.inventory = { [A().Compat.Player.RealmKey()] = { [ME] = { name = "Testchar",
			faction = A().Compat.Player.Faction(), bags = { [LINEN] = 3 } } } }
		truthy(A().Wishlist:Add(SILK, 1))
		local seen = {}
		for _, row in ipairs(B():List({ help = true })) do seen[#seen + 1] = row.kind .. row.item end
		table.sort(seen)
		deepEq(seen, { "wtb" .. LINEN, "wts" .. SILK })
		eq(#B():List({ side = "wtb" }), 2)
		eq(#B():List({ search = "silk" }), 1)
		eq(#B():List({ search = "bob" }), 4)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the Board mode", function()
	before_boot(setup())

	local function open()
		truthy(A().MarketView:Open("board"))
		Mock.Advance(2)
		return V().frame
	end

	it("posts from the window", function()
		A().Compat.Item.Request(LINEN)
		local f = open()
		truthy(f.warning:IsShown())
		f.warning.ok:Click()
		falsy(f.warning:IsShown())
		f.new:Click()
		local d = V().dialog
		truthy(d:IsShown())
		d.item:SetText("mithril")
		d.ok:Click()
		contains(d.status:GetText(), "Item not recognised")
		d.item:SetText("Linen Cloth"); d.count:SetText("40"); d.price:SetText("1g"); d.days:SetText("9")
		d.ok:Click()
		eq(d.status:GetText(), "Days: from 1 to 7.")
		d.days:SetText("")
		d.ok:Click()
		falsy(d:IsShown())
		eq(#f.table:VisibleRows(), 1)
		contains(printed(), "Your post is on the guild board.")
		eq(#Mock.errors, 0)
	end)

	it("asks once, then writes, for both sides; Whisper only opens the chat box", function()
		forbidTrade()
		local q = post(BOB, 1, { note = "At the inn" })
		truthy(accept(q))
		local f = open()
		local row = f.table:VisibleRows()[1]
		eq(row.step:IsShown(), true)
		row.step:Click()
		eq(S():Count("board"), 1, "the first click writes nothing")
		row = f.table:VisibleRows()[1]
		row.step:Click()
		eq(S():Count("board"), 2)
		eq(V().selected, q.id)
		truthy(f.foot.buttons.confirm:IsShown())
		truthy(f.foot.buttons.drop:IsShown())
		truthy(f.foot.hide:IsShown())
		local chat, sent = {}, #Mock.chat.sent
		ChatFrame_OpenChat = function(text) chat[#chat + 1] = text end
		f.foot.whisper:Click()
		deepEq(chat, { "/w Bob " })
		eq(#Mock.chat.sent, sent)
		-- the author's side: who the deal is with
		local p = must(B():Post({ kind = "wtb", item = SILK }))
		truthy(accept(answer(p.id, BOB)))
		truthy(accept(answer(p.id, ANN, "want", { time = now() - 10 }), OFF))
		V():Select(p.id)
		eq(V().who, ANN)
		f.foot.who:Select(BOB)
		eq(f.foot.buttons.confirm.guid, BOB)
		f.foot.buttons.confirm:Click()
		f.foot.buttons.confirm:Click()
		eq(S():Get("board", p.id).with, BOB)
		truthy(f.foot.buttons.unconfirm:IsShown())
		truthy(f.foot.buttons.withdraw:IsShown())
		falsy(f.foot.hide:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("shows the posts on the member card, in What I share, /accord debug and Settings", function()
		truthy(accept(post(BOB)))
		local section = A().OrdersView.CardSection(A().Roster:ByGUID(BOB))
		eq(section.id, "market")
		eq(section.lines[1].text, "WTS 20 × Linen Cloth · 3 d left")
		section.lines[1].onClick()
		eq(A().MarketView.mode, "board")
		must(B():Post({ kind = "wtb", item = SILK, price = "2g" }))
		truthy(B():Act("P:" .. BOB .. ":1", "deal"))
		local found
		for _, s in ipairs(A().ShareModel.Describe()) do if s.id == "board" then found = s end end
		local text = table.concat(found.lines, "\n")
		contains(text, "Post WTB 1 × Silk Cloth: open")
		contains(text, "Your answer to WTS 20 × Linen Cloth: interested")
		B():Hide(BOB)
		local report = A().Diagnostics.Report()
		contains(report, "Board: 2 post(s) (2 open), 1 answer(s), 0 waiting for their post, 1 author(s) hidden here; refused: none")
		falsy(report:find("Linen", 1, true))
		truthy(A().Shell:OpenView("settings"))
		local f = A().SettingsView.frame
		truthy(f.unhide:IsShown())
		f.unhide:Click()
		eq(B():HiddenCount(), 0)
		falsy(f.unhide:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("has six posts and a deal half way in the demo", function()
		truthy(A().Demo:Enter())
		local rows = B():List()
		eq(#rows, 6)
		local half = 0
		for _, row in ipairs(rows) do
			if V().StatusText(row):find("^Confirmed by") then half = half + 1 end
		end
		eq(half, 1)
		open()
		eq(#Mock.errors, 0)
		A().Demo:Exit()
		eq(S():Count("board"), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("with the switch econ off", function()
	before_boot(setup({ econ = false }))

	it("shows, writes and takes nothing of it", function()
		eq(select(2, B():Post({ kind = "wts", item = LINEN })), "off")
		eq(select(2, B():Act("P:" .. BOB .. ":1", "deal")), "off")
		falsy(S().IsActive("board"))
		refused(post(BOB), BOB, "set")
		falsy(A().MarketView:Open("board"))
		isNil(V():OpenNew())
		deepEq(V().CardLines(BOB), {})
		for _, s in ipairs(A().ShareModel.Describe()) do truthy(s.id ~= "board") end
		falsy(A().Diagnostics.Report():find("Board:", 1, true))
		eq(S():Count("board"), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator
---------------------------------------------------------------------------------------------------------------------
describe("the board between clients", function()
	local function simulated(M) M.features = { econ = true } end

	local function state(sim, i, id)
		local row = sim:client(i):addon().Board:Get(id)
		return row and row.state
	end

	it("reaches both sides and the guild, every client with the same state, also one that was away", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 5 }, setup = simulated, accounts = true, seed = 135 }
		sim:advance(120)
		local author, other = sim:client(2), sim:client(3)
		local rec = must(author:addon().Board:Post({ kind = "wts", item = LINEN, count = 2, days = 7 }))
		sim:advance(60)
		truthy(other:addon().Board:Act(rec.id, "deal"))
		sim:advance(60)
		truthy(author:addon().Board:Act(rec.id, "confirm", other:guid()))
		sim:advance(60)
		for _, j in ipairs({ 1, 2, 3, 4 }) do eq(state(sim, j, rec.id), "open", "client " .. j) end
		truthy(other:addon().Board:Act(rec.id, "confirm"))
		sim:advance(60)
		for _, j in ipairs({ 1, 2, 3, 4 }) do eq(state(sim, j, rec.id), "closed", "client " .. j) end
		sim:client(5):login()
		truthy(sim:advanceUntil(function() return state(sim, 5, rec.id) == "closed" end, 25 * 60), "the one away")
		for i = 1, 5 do
			for why in pairs(sim:client(i):addon().Store.stats.reasons) do eq(why, "wait", "client " .. i) end
			eq(sim:client(i):addon().Sync.state.stats.refused, 0, "client " .. i)
		end
	end)

	-- A client released before M13 knows none of its sets: here they are switched off in it, after every login.
	local function makeOld(c)
		local Store = c:addon().Store
		local original = Store.IsActive
		Store.IsActive = function(set)
			if set == "orders" or set == "wish" or set == "board" then return false end
			return original(set)
		end
	end

	it("leaves a client that does not know the set as before: nothing pushed, asked or refused", function()
		local sim = Sim.new{ clients = 4, officers = { 1 }, offline = { 3 }, setup = simulated, accounts = true, seed = 74 }
		makeOld(sim:client(4))
		sim:advance(120)
		local author = sim:client(2)
		local rec = must(author:addon().Board:Post({ kind = "wtb", item = SILK, days = 7 }))
		sim:advance(120)
		truthy(sim:client(1):addon().Board:Act(rec.id, "deal"))
		sim:advance(120)
		local old = sim:client(4):addon()
		eq(old.Store:Count("board"), 0)
		sim:client(3):login()
		truthy(sim:advanceUntil(function() return sim:client(3):addon().Store:Count("board") == 2 end, 25 * 60), "the newcomer")
		sim:advance(600)
		local s, c = old.Sync:EncodeSummary(), old.Sync:EncodeSummary(nil, true)
		for i = 1, 3 do
			local Sy = sim:client(i):addon().Sync
			eq(Sy:EncodeSummary(), s, "the per-author summary, client " .. i)
			eq(Sy:EncodeSummary(nil, true), c, "the census's extra summary, client " .. i)
		end
		eq(#old.Sync:EncodeSummary(nil, "ec"), 0, "the old client has no summary of M13")
		local seen = 0
		for i = 1, 4 do
			local Tr = sim:client(i):addon().Transport
			local original = Tr.Send
			Tr.Send = function(self, dist, msg, opts)
				if msg.t == "REC" and msg.s == "board" then seen = seen + 1 end
				return original(self, dist, msg, opts)
			end
		end
		local pushes = 0
		for i = 1, 3 do pushes = pushes + sim:client(i):addon().Sync.state.stats.pushes end
		for round = 1, 2 do
			sim:client(4):logout()
			sim:client(4):login()
			makeOld(sim:client(4))
			if round == 2 then for i = 1, 4 do sim:client(i):addon().Sync.BLOCK_OVER = -1 end end
			sim:advance(45 * 60)
		end
		truthy(sim:client(4):addon().Sync.state.stats.bhellosSent >= 1, "the old client sent a BHELLO")
		eq(seen, 0, "no record of the board sent to it or because of it")
		local after = 0
		for i = 1, 3 do after = after + sim:client(i):addon().Sync.state.stats.pushes end
		eq(after, pushes, "nobody pushed anything to it")
		eq(sim:client(4):addon().Sync.state.stats.requests, 0, "and it asked for nothing")
		for i = 1, 4 do
			local Ci = sim:client(i):addon()
			eq(Ci.Store.stats.rejected, 0, "client " .. i)
			eq(Ci.Sync.state.stats.quarantined, 0)
		end
	end)

	-- The scenario of M10.8 (SPEC-17 §10.3): 50 clients, 45 minutes of churn; with `with`, a post every 3 minutes and an
	-- answer every 5 for the whole guild.
	local function churn(with)
		local N = 50
		local sim = Sim.new{ clients = N, officers = { 1, 11, 21, 31, 41 }, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42,
			setup = simulated }
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
		local posts, answers, ids = 0, 0, {}
		local function anyOnline(fn)
			for _ = 1, 100 do
				local c = sim:client(1 + math.floor(rand() * N) % N)
				if c.online and fn(c) then return end
			end
		end
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
				anyOnline(function(c)
					local rec = c:addon().Board:Post({ kind = "wts", item = 10000 + step, count = 9999, price = ("p"):rep(24),
						note = ("n"):rep(80), days = 7 })
					if not rec then return false end
					posts, ids[#ids + 1] = posts + 1, rec.id
					return true
				end)
			end
			if with and step % 10 == 5 and #ids > 0 then
				anyOnline(function(c)
					if not c:addon().Board:Act(ids[#ids], "deal", nil, ("n"):rep(80)) then return false end
					answers = answers + 1
					return true
				end)
			end
			sim:advance(30)
		end
		for i = 1, N do
			local c = sim:client(i)
			if c.online then
				for why, n in pairs(c:addon().Store.stats.reasons) do
					if why ~= "wait" then fail("client " .. i .. " refused " .. n .. " for " .. why) end
				end
				eq(c:addon().Sync.state.stats.quarantined, 0)
			end
		end
		return sim:stats(), posts, answers
	end

	it("50 clients of a guild in step stay inside the shared traffic budget (SPEC-09 §7)", function()
		local base = churn(false)
		local st, posts, answers = churn(true)
		T.log(("board: churn %.0f B/min per client on average (%.0f without it), %.0f at most (%.0f); %d posts, %d answers"):format(
			st.avg.bytesPerMinute, base.avg.bytesPerMinute, st.max.bytesPerMinute, base.max.bytesPerMinute, posts, answers))
		truthy(posts >= 10, "posts " .. posts)
		truthy(answers >= 5, "answers " .. answers)
		truthy(st.avg.bytesPerMinute <= 450, "churn average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2048, "churn busiest client " .. st.max.bytesPerMinute)
	end)
end)

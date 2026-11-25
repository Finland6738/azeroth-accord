-- Bank requests (M5.5; SPEC-08 BANK-20..BANK-22, SPEC-03 §7, ADR 0005): a member opens and cancels requests, only officers
-- move them to approved, rejected or fulfilled, every guildmate sees every request, and every client ends with the same
-- status (network simulator).
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function R() return AzerothAccord.BankRequests end
local function V() return AzerothAccord.BankView end
local function RV() return AzerothAccord.BankRequestsView end

local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000C0C"
local LINEN = 2589

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function asOfficer()
	Mock.guild.Set{ name = "Accord", myRank = 1, members = { { name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB } } }
	A().Role:Refresh()
end

describe("the text of a request", function()
	before_boot(function() guild() end)

	it("takes an item from a link or a number, and nothing else", function()
		eq(R().ParseItem("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"), 2589)
		eq(R().ParseItem("  2589 "), 2589)
		eq(R().ParseItem(118), 118)
		isNil(R().ParseItem("linen cloth")); isNil(R().ParseItem("")); isNil(R().ParseItem(0)); isNil(R().ParseItem(nil)); isNil(R().ParseItem(2 ^ 40))
	end)

	it("cleans a reason: no control characters, no link escapes, one space, at most 120 characters", function()
		eq(R().CleanText("  need  it\n for |cffff0000raid|r  "), "need it for cffff0000raid r")
		eq(#R().CleanText(("x"):rep(500)), 120)
		eq(R().CleanText(nil), "")
	end)
end)

describe("opening, cancelling and deciding (one client)", function()
	before_boot(function() guild(3) end)

	local function mine() return S():Get("bankreq", ME .. ":1") end

	it("opens a request for an item with a reason, with its history", function()
		local seen
		A().Bus:On("BANKREQ_CHANGED", function(id, status) seen = id .. status end)
		local rec = R():Create({ kind = "withdraw", itemID = LINEN, count = 20, reason = "for the raid" })
		notNil(rec)
		eq(rec.id, ME .. ":1"); eq(rec.status, "open"); eq(rec.itemID, LINEN); eq(rec.count, 20); eq(rec.reason, "for the raid")
		eq(rec.requester, ME); eq(rec.author, ME); eq(#rec.history, 1); eq(rec.history[1].s, "open"); eq(rec.history[1].by, ME)
		eq(seen, ME .. ":1open")
		eq(R():OpenCount(), 1)
	end)

	it("opens a request for gold, and a donation; a deposit needs an item", function()
		truthy(R():Create({ kind = "withdraw", amount = 50000 }))
		truthy(R():Create({ kind = "donation", amount = 100000, reason = "weekly" }))
		truthy(R():Create({ kind = "donation", itemID = LINEN, count = 100 }))
		eq(select(2, R():Create({ kind = "deposit", amount = 5 })), "item")
		truthy(R():Create({ kind = "deposit", itemID = LINEN, count = 3 }))
		eq(S():Get("bankreq", ME .. ":2").amount, 100000, "the ids count up")
	end)

	it("refuses a bad request and says why", function()
		eq(select(2, R():Create({ kind = "steal", amount = 5 })), "kind")
		eq(select(2, R():Create({ kind = "withdraw", itemID = "nope", count = 1 })), "item")
		eq(select(2, R():Create({ kind = "withdraw", itemID = LINEN, count = 0 })), "count")
		eq(select(2, R():Create({ kind = "withdraw", itemID = LINEN, count = 10000 })), "count")
		eq(select(2, R():Create({ kind = "withdraw", amount = 0 })), "amount")
		eq(select(2, R():Create({ kind = "withdraw", amount = 1.5 })), "amount")
		eq(select(2, R():Create(nil)), "kind")
		eq(R():OpenCount(), 0)
	end)

	it("allows five open requests at a time", function()
		for i = 1, 5 do truthy(R():Create({ kind = "withdraw", amount = i * 100 })) end
		eq(select(2, R():Create({ kind = "withdraw", amount = 1000 })), "limit")
		truthy(R():Cancel(ME .. ":1"))
		truthy(R():Create({ kind = "withdraw", amount = 1000 }))
	end)

	it("the requester cancels an open request, once; not somebody else's, not a decided one", function()
		R():Create({ kind = "withdraw", amount = 100 })
		local rec = R():Cancel(ME .. ":1")
		eq(rec.status, "cancelled"); eq(#rec.history, 2); eq(rec.history[2].s, "cancelled"); eq(rec.rev, 2)
		eq(select(2, R():Cancel(ME .. ":1")), "status")
		eq(select(2, R():Cancel(ME .. ":9")), "missing")
		S():Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "withdraw",
			status = "open", amount = 5, created = GetServerTime(), history = {} }
		eq(select(2, R():Cancel(BOB .. ":1")), "owner")
	end)

	it("a member cannot decide", function()
		R():Create({ kind = "withdraw", amount = 100 })
		eq(select(2, R():Decide(ME .. ":1", "approved")), "officer")
		eq(mine().status, "open")
	end)

	it("every guildmate sees every request, and what this player may do with each", function()
		R():Create({ kind = "withdraw", itemID = LINEN, count = 5 })
		S():Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "donation",
			status = "open", amount = 5, created = GetServerTime() - 100, history = {} }
		local rows = R():List()
		eq(#rows, 2)
		eq(rows[1].own, true); eq(rows[1].canCancel, true); eq(#rows[1].moves, 0)
		eq(rows[2].own, false); eq(rows[2].canCancel, false); eq(rows[2].name, "Bob")
		eq(#R():List({ own = true }), 1)
		eq(#R():List({ status = { approved = true } }), 0)
	end)
end)

describe("an officer moves requests", function()
	before_boot(function() guild(1) end)

	it("approves and fulfils with the history, in the right order only", function()
		A().Role:Refresh()
		local rec = R():Create({ kind = "withdraw", itemID = LINEN, count = 5 })
		local id = rec.id
		eq(R():List()[1].moves[1], "approved"); eq(#R():List()[1].moves, 3, "approve, reject or mark fulfilled")
		local a = R():Decide(id, "approved")
		eq(a.status, "approved"); eq(#a.history, 2); eq(a.history[2].s, "approved"); eq(a.history[2].by, ME); eq(a.rev, 2)
		eq(a.itemID, LINEN); eq(a.count, 5); eq(a.created, rec.created, "the content stays")
		eq(select(2, R():Decide(id, "approved")), "status")
		eq(select(2, R():Decide(id, "open")), "status")
		local f = R():Decide(id, "fulfilled")
		eq(f.status, "fulfilled"); eq(#f.history, 3)
		eq(select(2, R():Decide(id, "rejected")), "status", "a closed request does not move")
		eq(select(2, R():Cancel(id)), "status")
		eq(R():OpenCount(), 0)
	end)

	it("rejects with a reason that is kept and cleaned", function()
		A().Role:Refresh()
		local id = R():Create({ kind = "withdraw", amount = 100 }).id
		local r = R():Decide(id, "rejected", "  not now |cffff0000sorry|r ")
		eq(r.status, "rejected"); eq(r.note, "not now cffff0000sorry r")
	end)

	it("only the three decisions exist", function()
		A().Role:Refresh()
		local id = R():Create({ kind = "withdraw", amount = 100 }).id
		eq(select(2, R():Decide(id, "cancelled")), "status")
		eq(select(2, R():Decide(id, "bogus")), "status")
		eq(select(2, R():Decide("Player-1-0000FFFF:1", "approved")), "missing")
	end)

	it("the highest status wins whatever order the versions arrive in, and the content never changes", function()
		A().Role:Refresh()
		local base = { id = BOB .. ":1", requester = BOB, kind = "withdraw", amount = 5, created = GetServerTime(), history = {}, time = GetServerTime() }
		local function v(status, author, rev)
			local r = {}
			for k, x in pairs(base) do r[k] = x end
			r.status, r.author, r.rev = status, author, rev
			return r
		end
		local approved, cancelled = v("approved", OFF, 2), v("cancelled", BOB, 2)
		eq(R().Compare(approved, cancelled), 1); eq(R().Compare(cancelled, approved), -1)
		eq(R().Compare(v("fulfilled", OFF, 3), v("rejected", OFF, 9)), 1)
		eq(R().Compare(v("open", BOB, 1), nil), 1)
		eq(R().Compare(v("approved", OFF, 3), v("approved", OFF, 2)), 1, "same status: the later revision")
		local changed = v("approved", OFF, 3); changed.amount = 9
		falsy(R().Transition(base, changed))
		truthy(R().Transition(base, v("approved", OFF, 2)))
	end)
end)

describe("the requests in the network simulator", function()
	local function sendRequest(c, spec) return c:addon().BankRequests:Create(spec) end

	it("a member's request reaches every guildmate, an officer approves it and everyone shows the same status", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, seed = 81 }
		sim:advance(40)
		local rec = sendRequest(sim:client(3), { kind = "withdraw", itemID = LINEN, count = 20, reason = "raid" })
		local id = rec.id
		sim:advance(60)
		for i = 1, 5 do
			local r = sim:client(i):addon().Store:Get("bankreq", id)
			notNil(r, "client " .. i .. " sees the open request")
			eq(r.status, "open")
		end
		local decided = sim:client(1):addon().BankRequests:Decide(id, "approved")
		notNil(decided)
		sim:advance(60)
		for i = 1, 5 do eq(sim:client(i):addon().Store:Get("bankreq", id).status, "approved", "client " .. i) end
		sim:client(2):addon().BankRequests:Decide(id, "fulfilled")
		sim:advance(60)
		for i = 1, 5 do
			local r = sim:client(i):addon().Store:Get("bankreq", id)
			eq(r.status, "fulfilled", "client " .. i); eq(#r.history, 3)
			eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing")
		end
	end)

	it("status changes come only from officers: a member's forged decision, or a cancel of somebody else's request, is refused", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, seed = 83 }
		sim:advance(40)
		local id = sendRequest(sim:client(3), { kind = "withdraw", amount = 100000 }).id
		sim:advance(60)
		local held = sim:client(4):addon().Store:Get("bankreq", id)
		local function forged(status, author, rev)
			local r = {}
			for k, v in pairs(held) do r[k] = v end
			r.status, r.author, r.rev, r.time = status, author, rev, held.time + 5
			return r
		end
		-- client 4 (a member) writes an approval in its own name, and one in an officer's name
		local T = sim:client(4):addon().Transport
		T:Send("GUILD", { t = "REC", s = "bankreq", r = { forged("approved", Sim.guidOf(4), 2) } })
		T:Send("GUILD", { t = "REC", s = "bankreq", r = { forged("approved", Sim.guidOf(1), 3) } })
		-- and a cancel of client 3's request in client 3's name
		T:Send("GUILD", { t = "REC", s = "bankreq", r = { forged("cancelled", Sim.guidOf(3), 4) } })
		sim:advance(60)
		for i = 1, 5 do eq(sim:client(i):addon().Store:Get("bankreq", id).status, "open", "client " .. i .. " still sees it open") end
		truthy((sim:client(1):addon().Store.stats.reasons.authority or 0) >= 2, "officers refused the decisions")
		truthy((sim:client(1):addon().Store.stats.reasons.relay or 0) >= 1, "and the cancel in somebody else's name")
	end)

	it("a decision and a cancel written at the same moment end the same everywhere: the decision", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, seed = 85 }
		sim:advance(40)
		local id = sendRequest(sim:client(3), { kind = "withdraw", amount = 100000 }).id
		sim:advance(60)
		sim:client(3):restrict({ lockdown = true })     -- its cancel waits in the queue while the decision goes out
		notNil(sim:client(3):addon().BankRequests:Cancel(id))
		notNil(sim:client(1):addon().BankRequests:Decide(id, "approved"))
		sim:advance(30)
		sim:client(3):restrict({ lockdown = false })
		sim:advance(120)
		for i = 1, 5 do eq(sim:client(i):addon().Store:Get("bankreq", id).status, "approved", "client " .. i) end
	end)

	it("a member who logs in later gets the requests from an officer", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, offline = { 5 }, seed = 87 }
		sim:advance(40)
		local id = sendRequest(sim:client(3), { kind = "donation", itemID = LINEN, count = 50 }).id
		sim:advance(60)
		sim:client(1):addon().BankRequests:Decide(id, "approved")
		sim:advance(60)
		sim:client(3):logout()
		sim:client(5):login()
		local ok = sim:advanceUntil(function()
			local r = sim:client(5):addon().Store:Get("bankreq", id)
			return r and r.status == "approved"
		end, 400)
		truthy(ok, "relayed by an officer")
	end)

	it("a request stays on the record for the requester's alt too: an alt may cancel it", function()
		local sim = Sim.new{ clients = 4, officers = { 1 }, seed = 89, accounts = true }
		sim:advance(120)
		-- clients 3 and 4 are alts of one account: each lists the other
		for _, i in ipairs({ 3, 4 }) do
			local c = sim:client(i)
			local other = Sim.guidOf(i == 3 and 4 or 3)
			local rec = c:addon().Store:Get("accounts", c:guid())
			if rec then
				local chars = {}
				for _, ch in ipairs(rec.chars) do chars[#chars + 1] = ch end
				chars[#chars + 1] = { guid = other, name = "alt" }
				c:addon().Store:Put("accounts", c:guid(), { token = rec.token, chars = chars, main = rec.main })
			end
		end
		sim:advance(120)
		local id = sendRequest(sim:client(3), { kind = "withdraw", amount = 5000 }).id
		sim:advance(60)
		local ok = sim:client(4):addon().BankRequests:Cancel(id)
		notNil(ok, "the alt is the same account")
		sim:advance(60)
		for i = 1, 4 do eq(sim:client(i):addon().Store:Get("bankreq", id).status, "cancelled", "client " .. i) end
	end)
end)

describe("the Requests mode", function()
	before_boot(function()
		guild(3)
		Mock.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
		Mock.items.cached[LINEN] = true
	end)

	local function shown(frames)
		local out = {}
		for _, f in ipairs(frames) do if f:IsShown() then out[#out + 1] = f end end
		return out
	end

	local function open()
		Mock.Slash("/accord bank")
		V():SetMode("requests")
		return V().modes.requests.frame
	end

	it("opens a request from the form, and lists it with its status", function()
		local f = open()
		contains(f.message:GetText(), "No open requests")
		f.item:SetText("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r")
		f.amount:SetText("20")
		f.reason:SetText("for the raid")
		f.send:Click()
		eq(f.item:GetText(), "", "the form is cleared")
		contains(f.status:GetText(), "Request sent")
		local rows = shown(f.area.rows)
		eq(#rows, 1)
		eq(rows[1].status:GetText(), "Open"); eq(rows[1].name:GetText(), "Testchar"); eq(rows[1].kind:GetText(), "Withdraw")
		eq(rows[1].what:GetText(), "Linen Cloth x20"); eq(rows[1].reason:GetText(), "for the raid")
		eq(rows[1].buttons[1]:GetLabel(), "Cancel"); falsy(rows[1].buttons[2]:IsShown())
	end)

	it("asks for gold in whole gold pieces and says what is wrong with the form", function()
		local f = open()
		f.amount:SetText("12")
		f.send:Click()
		eq(S():Get("bankreq", ME .. ":1").amount, 120000)
		f.amount:SetText("")
		f.send:Click()
		contains(f.status:GetText(), "Gold")
		f.item:SetText("not an item")
		f.send:Click()
		contains(f.status:GetText(), "item link or an item number")
	end)

	it("the kind buttons choose the kind", function()
		local f = open()
		f.kindButtons[2]:Click()
		eq(RV().kind, "deposit")
		eq(f.kindButtons[2].label:GetText(), "Deposit"); truthy(f.kindButtons[2]:IsSelected()); falsy(f.kindButtons[1]:IsSelected())
		f.amount:SetText("5")
		f.send:Click()
		contains(f.status:GetText(), "item link or an item number")
		f.item:SetText("2589"); f.amount:SetText("3")
		f.send:Click()
		eq(S():Get("bankreq", ME .. ":1").kind, "deposit")
	end)

	it("Cancel cancels the player's own open request and hides it", function()
		local f = open()
		f.amount:SetText("5"); f.send:Click()
		f.area.rows[1].buttons[1]:Click()
		eq(S():Get("bankreq", ME .. ":1").status, "cancelled")
		eq(#shown(f.area.rows), 0)
		f.closed:Click()
		eq(#shown(f.area.rows), 1)
		eq(shown(f.area.rows)[1].status:GetText(), "Cancelled")
	end)

	it("a member sees the requests of others, but only the buttons of their own", function()
		S():Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "donation",
			status = "open", itemID = LINEN, count = 9, created = GetServerTime(), history = {} }
		local f = open()
		local rows = shown(f.area.rows)
		eq(#rows, 1); eq(rows[1].name:GetText(), "Bob"); falsy(rows[1].buttons[1]:IsShown())
		f.mine:Click()
		eq(#shown(f.area.rows), 0, "only mine")
	end)

	it("an officer sees Approve, Reject and Fulfilled, and the reason box is the reason of a rejection", function()
		asOfficer()
		S():Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "withdraw",
			status = "open", itemID = LINEN, count = 9, created = GetServerTime(), history = { { s = "open", by = BOB, t = GetServerTime() } } }
		local f = open()
		local row = shown(f.area.rows)[1]
		eq(row.buttons[1]:GetLabel(), "Approve"); eq(row.buttons[2]:GetLabel(), "Reject"); eq(row.buttons[3]:GetLabel(), "Fulfilled")
		row.buttons[1]:Click()
		eq(S():Get("bankreq", BOB .. ":1").status, "approved")
		row = shown(f.area.rows)[1]
		eq(row.status:GetText(), "Approved"); eq(row.buttons[1]:GetLabel(), "Reject"); eq(row.buttons[2]:GetLabel(), "Fulfilled")
		f.reason:SetText("sorry, out of stock")
		row.buttons[1]:Click()
		eq(S():Get("bankreq", BOB .. ":1").status, "rejected")
		eq(S():Get("bankreq", BOB .. ":1").note, "sorry, out of stock")
	end)

	it("the tooltip of a row gives the history", function()
		asOfficer()
		S():Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "withdraw",
			status = "open", itemID = LINEN, count = 9, reason = "gear", created = GetServerTime(), history = { { s = "open", by = BOB, t = GetServerTime() - 7200 } } }
		local f = open()
		local row = shown(f.area.rows)[1]
		A().Widgets.Tooltip.Show(row, A().BankRequestsView.TooltipLines(row.data), "RIGHT")
		local lines = A().Widgets.Tooltip.Lines()
		eq(lines[2], "gear"); eq(lines[3], "Open by Bob, 2 h ago")
	end)
end)

-- M8.7: the item picked from the bank contents, and the tip (SPEC-08 BANK-25..BANK-27) -------------------------------------
local COPPER, SILK, GOLD = 2840, 4306, 10000

-- A snapshot of a tab as `author` read it, `age` seconds ago; items = { { itemID, count }, ... }.
local function snapshot(author, tab, items, age, extra)
	local slots = {}
	for i, it in ipairs(items) do slots[i] = { slot = i, itemID = it[1], count = it[2] } end
	local rec = { id = author .. ":t" .. tab, author = author, rev = 1, time = GetServerTime() - (age or 60), kind = "tab", tab = tab,
		name = "Tab " .. tab, rank = 3, it = A().Bank.EncodeItems(slots), n = #slots }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("bank")[rec.id] = rec
end

local function itemNames()
	for id, name in pairs({ [LINEN] = "Linen Cloth", [COPPER] = "Copper Bar", [SILK] = "Silk Cloth" }) do
		Mock.items.info[id] = { name = name, quality = 1, icon = 132889 }
		Mock.items.cached[id] = true
	end
end

-- Linen in two tabs (20 + 15), 7 copper bars, and silk in an officers' tab.
local function stocked()
	snapshot(BOB, 1, { { LINEN, 20 }, { COPPER, 7 } }, 3 * 3600)
	snapshot(BOB, 2, { { LINEN, 15 } }, 2 * 86400)
	snapshot(OFF, 3, { { SILK, 50 } }, 60, { restricted = true, rank = 1 })
end

local function theirs(n, extra)
	local rec = { id = BOB .. ":" .. n, author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "withdraw", status = "open",
		itemID = LINEN, count = 3, created = GetServerTime(), history = { { s = "open", by = BOB, t = GetServerTime() } } }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("bankreq")[rec.id] = rec
	return rec
end

describe("picking from the bank contents", function()
	before_boot(function() guild(3) itemNames() end)

	it("sums each item over the tabs this member sees, with the age of the oldest snapshot that holds it", function()
		stocked()
		local items = R():BankItems()
		eq(items[LINEN].available, 35); eq(items[LINEN].time, GetServerTime() - 2 * 86400); eq(items[LINEN].author, BOB)
		eq(items[COPPER].available, 7)
		isNil(items[SILK], "the officers' tab is not shown to a member")
	end)

	it("an officer picks from the officers' tab too", function()
		asOfficer(); stocked()
		eq(R():BankItems()[SILK].available, 50)
	end)

	it("lists the items by name, searches by name or number and shows how many are available", function()
		stocked()
		local all = RV().Choices("")
		eq(#all, 2); eq(all[1].name, "Copper Bar"); eq(all[2].name, "Linen Cloth")
		eq(all[2].available, 35); contains(all[2].text, "Linen Cloth - 35")
		eq(#RV().Choices("linen"), 1); eq(RV().Choices("  CLOTH ")[1].id, LINEN); eq(RV().Choices("2840")[1].id, COPPER)
		eq(#RV().Choices("mithril"), 0)
	end)

	it("caps a withdrawal at what the bank holds, and says the most it may ask", function()
		stocked()
		local rec, why, most = R():Create({ kind = "withdraw", itemID = LINEN, count = 36 })
		falsy(rec); eq(why, "stock"); eq(most, 35)
		eq(R():OpenCount(), 0)
		truthy(R():Create({ kind = "withdraw", itemID = LINEN, count = 35 }))
	end)

	it("keeps 1-9999 and does not cap a deposit, a donation or an item the snapshots do not show (the fallback)", function()
		stocked()
		snapshot(BOB, 4, { { 159, 20000 } })
		eq(R():MaxCount("withdraw", 159), 9999)
		eq(select(2, R():Create({ kind = "withdraw", itemID = 159, count = 10000 })), "count")
		eq(select(2, R():Create({ kind = "withdraw", itemID = LINEN, count = 0 })), "count")
		truthy(R():Create({ kind = "deposit", itemID = LINEN, count = 500 }))
		truthy(R():Create({ kind = "donation", itemID = LINEN, count = 500 }))
		truthy(R():Create({ kind = "withdraw", itemID = 118, count = 500 }), "not in the bank as seen")
		truthy(R():Create({ kind = "withdraw", itemID = SILK, count = 500 }), "in a tab this member cannot see")
	end)

	it("reads the box: the picked item, a link or a number, or the exact name of one bank item", function()
		stocked()
		eq(RV().Resolve("withdraw", "linen cloth"), LINEN)
		eq(RV().Resolve("withdraw", "|cffffffff|Hitem:118::::::::60:::::|h[Potion]|h|r"), 118)
		eq(RV().Resolve("withdraw", "2840"), COPPER)
		eq(RV().Resolve("withdraw", "Anything", { id = SILK, text = "Anything" }), SILK)
		isNil(RV().Resolve("withdraw", ""))
		eq(select(2, RV().Resolve("withdraw", "linen")), "item", "a part of a name is a search, not a choice")
		eq(select(2, RV().Resolve("deposit", "linen cloth")), "item", "only a withdrawal picks by name")
		Mock.items.info[2592] = { name = "Linen Cloth", quality = 1, icon = 132889 }
		Mock.items.cached[2592] = true
		snapshot(BOB, 5, { { 2592, 1 } })
		eq(select(2, RV().Resolve("withdraw", "Linen Cloth")), "pick", "two items share the name")
		eq(RV().Resolve("withdraw", "Linen Cloth", { id = 2592, text = "Linen Cloth" }), 2592)
	end)

	it("the line under the box gives the quantity and the age of the snapshot (the provenance label)", function()
		contains(RV().BankLine("").text, "No bank contents seen yet")
		stocked()
		local none = RV().BankLine("")
		contains(none.text, "choose from 2 bank items"); eq(none.info.observedAt, GetServerTime() - 2 * 86400)
		local linen = RV().BankLine("Copper Bar")
		eq(linen.text, "7 in the bank"); eq(linen.max, 7)
		eq(linen.info.source, "shared"); eq(linen.info.set, "bank"); eq(linen.info.author, BOB); eq(linen.info.observedAt, GetServerTime() - 3 * 3600)
		contains(RV().BankLine("118").text, "Not in the bank")
		eq(RV().CappedAmount("Copper Bar", "50"), "7")
		isNil(RV().CappedAmount("Copper Bar", "7")); isNil(RV().CappedAmount("118", "50")); isNil(RV().CappedAmount("", "50"))
	end)

	it("the form refuses more than the bank holds and says how much it holds", function()
		stocked()
		local ok, text = RV().Submit({ kind = "withdraw", item = "Copper Bar", amount = "8" })
		falsy(ok); contains(text, "only 7")
		truthy(RV().Submit({ kind = "withdraw", item = "Copper Bar", amount = "7" }))
		eq(S():Get("bankreq", ME .. ":1").itemID, COPPER); eq(S():Get("bankreq", ME .. ":1").count, 7)
	end)
end)

describe("the tip", function()
	before_boot(function() guild(3) itemNames() end)

	local function ask(tip, extra)
		local spec = { kind = "withdraw", itemID = LINEN, count = 2, tip = tip }
		for k, v in pairs(extra or {}) do spec[k] = v end
		return R():Create(spec)
	end

	it("is optional whole gold up to 10,000 on a withdrawal of an item; 0 is none", function()
		eq(R().MAX_TIP, 10000 * GOLD)
		eq(ask(5 * GOLD).tip, 5 * GOLD)
		isNil(ask(0).tip); isNil(ask(nil).tip)
		eq(ask(R().MAX_TIP).tip, R().MAX_TIP)
		for _, bad in ipairs({ -GOLD, 1, GOLD + 1, 1.5 * GOLD, R().MAX_TIP + GOLD, "5" }) do
			eq(select(2, ask(bad)), "tip", "tip " .. tostring(bad))
		end
	end)

	it("goes with a withdrawal of an item only", function()
		eq(select(2, R():Create({ kind = "deposit", itemID = LINEN, count = 1, tip = GOLD })), "tip")
		eq(select(2, R():Create({ kind = "donation", itemID = LINEN, count = 1, tip = GOLD })), "tip")
		eq(select(2, R():Create({ kind = "withdraw", amount = 5 * GOLD, tip = GOLD })), "tip")
		eq(R():OpenCount(), 0)
	end)

	it("is read from the box in whole gold pieces", function()
		isNil(RV().ParseTip("")); isNil(RV().ParseTip(nil)); isNil(RV().ParseTip(" 0 "))
		eq(RV().ParseTip("5"), 5 * GOLD); eq(RV().ParseTip("10 000"), 10000 * GOLD)
		for _, bad in ipairs({ "-1", "1.5", "five", "10001", "1g" }) do eq(RV().ParseTip(bad), false, bad) end
		local ok, text = RV().Submit({ kind = "withdraw", item = "2589", amount = "1", tip = "1.5" })
		falsy(ok); contains(text, "Tip")
		ok, text = RV().Submit({ kind = "withdraw", item = "2589", amount = "1", tip = "3" })
		truthy(ok); contains(text, "3g"); contains(text, "deposit it in the bank")
		eq(S():Get("bankreq", ME .. ":1").tip, 3 * GOLD)
		ok, text = RV().Submit({ kind = "withdraw", item = "", amount = "10", tip = "3" })
		falsy(ok); contains(text, "only when you ask for an item")
		truthy(RV().Submit({ kind = "deposit", item = "2589", amount = "1", tip = "3" }), "a hidden tip box is ignored")
		isNil(S():Get("bankreq", ME .. ":2").tip)
	end)

	it("a record with a badly shaped tip is refused, and a tip never changes after the opening", function()
		local good = ask(2 * GOLD)
		truthy(R().ValidRecord(good, S()))
		local function with(k, v) local r = S().Copy(good) r[k] = v return r end
		falsy(R().ValidRecord(with("tip", 5), S())); falsy(R().ValidRecord(with("tip", "20000"), S()))
		falsy(R().ValidRecord(with("tip", R().MAX_TIP + GOLD), S())); falsy(R().ValidRecord(with("kind", "donation"), S()))
		truthy(R().Transition(good, with("status", "approved")))
		falsy(R().Transition(good, with("tip", 3 * GOLD)))
		local gone = S().Copy(good); gone.tip = nil
		falsy(R().Transition(good, gone))
		eq(R():Cancel(good.id).tip, 2 * GOLD, "a new revision keeps it")
	end)

	it("a record with every field at its largest stays inside the size limit of a request", function()
		local rec = { id = ME .. ":999999999", author = ME, rev = 2147483647, time = GetServerTime(), requester = ME, kind = "withdraw",
			status = "rejected", itemID = 2147483647, count = 9999, tip = R().MAX_TIP, reason = ("x"):rep(120), note = ("y"):rep(120),
			created = GetServerTime(), history = {} }
		for i = 1, R().MAX_HISTORY do rec.history[i] = { s = "cancelled", by = ME, t = GetServerTime() } end
		truthy(R().ValidRecord(rec, S()))
		truthy(A().Config.EstimateSize(rec) <= S().SETS.bankreq.maxBytes, tostring(A().Config.EstimateSize(rec)))
	end)

	it("a member sees the tip of their own requests only; an officer and the Guild Master see all", function()
		ask(2 * GOLD)
		theirs(1, { tip = 7 * GOLD })
		local function tips()
			local out = {}
			for _, r in ipairs(R():List()) do out[r.requester] = r.tip or 0 end
			return out
		end
		eq(tips()[ME], 2 * GOLD); eq(tips()[BOB], 0, "somebody else's tip is not shown")
		for _, r in ipairs(RV().Rows({})) do
			if r.requester == BOB then
				isNil(r.tipText)
				for _, line in ipairs(RV().TooltipLines(r)) do falsy(type(line) == "table" and line.text:find("Tip:")) end
			end
		end
		R().TIP_VISIBLE_TO = "everyone"
		eq(tips()[BOB], 7 * GOLD, "the one switch of SPEC-10 Q16")
		R().TIP_VISIBLE_TO = "officers"
		asOfficer()
		eq(tips()[BOB], 7 * GOLD)
	end)

	it("the requester's alt sees the tip too", function()
		theirs(1, { tip = 7 * GOLD })
		for _, pair in ipairs({ { ME, BOB }, { BOB, ME } }) do
			S():Records("accounts")[pair[1]] = { id = pair[1], author = pair[1], rev = 1, time = GetServerTime(), token = "T",
				chars = { { guid = pair[1] }, { guid = pair[2] } } }
		end
		eq(R():List()[1].tip, 7 * GOLD)
	end)

	it("What I share says the tip of the player's own requests", function()
		ask(4 * GOLD)
		local lines
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "bankreq" then lines = table.concat(r.lines, "\n") end end
		contains(lines, "tip 4 gold")
	end)
end)

describe("an older client and the tip", function()
	-- The rules of a client from before M8.7: it does not know `tip`, so it neither checks nor compares it.
	local function older(c)
		local Req = c:addon().BankRequests
		local valid = Req.ValidRecord
		Req.ValidRecord = function(rec, s)
			local plain = {}
			for k, v in pairs(rec) do plain[k] = v end
			plain.tip = nil
			return valid(plain, s)
		end
		Req.Transition = function(held, rec)
			return held.requester == rec.requester and held.kind == rec.kind and held.itemID == rec.itemID and held.count == rec.count
				and held.amount == rec.amount and held.created == rec.created
		end
	end

	it("accepts the request, and an older officer's decision keeps the tip on every client", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, seed = 93 }
		sim:advance(40)
		older(sim:client(1))
		local id = sim:client(3):addon().BankRequests:Create({ kind = "withdraw", itemID = LINEN, count = 2, tip = 6 * GOLD }).id
		sim:advance(60)
		eq(sim:client(1):addon().Store:Get("bankreq", id).tip, 6 * GOLD, "held as it came")
		truthy(sim:client(1):addon().BankRequests:Decide(id, "approved"))
		sim:advance(60)
		for i = 1, 4 do
			local r = sim:client(i):addon().Store:Get("bankreq", id)
			eq(r.status, "approved", "client " .. i); eq(r.tip, 6 * GOLD, "client " .. i)
			eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing")
		end
	end)
end)

describe("the form picks from the bank", function()
	before_boot(function() guild(3) itemNames() end)

	local function open()
		stocked()
		Mock.Slash("/accord bank")
		V():SetMode("requests")
		return V().modes.requests.frame
	end

	local function shownRows(list)
		local out = {}
		for _, b in ipairs(list.rows) do if b:IsShown() then out[#out + 1] = b end end
		return out
	end

	it("opens the list on the box, filters it while typing, and a click picks the item", function()
		local f = open()
		falsy(f.picker:IsShown())
		f.item.edit:SetFocus()
		truthy(f.picker:IsShown()); eq(#shownRows(f.list), 2)
		contains(f.stock:GetText(), "choose from 2 bank items")
		truthy(f.prov:IsShown()); eq(f.prov.text:GetText(), "2 d ago")
		Mock.TypeInto(f.item.edit, "lin")
		eq(#shownRows(f.list), 1); contains(shownRows(f.list)[1].label:GetText(), "Linen Cloth - 35")
		shownRows(f.list)[1]:Click()
		falsy(f.picker:IsShown()); eq(f.item:GetText(), "Linen Cloth"); eq(f.stock:GetText(), "35 in the bank")
		Mock.TypeInto(f.amount.edit, "100")
		eq(f.amount:GetText(), "35", "the quantity stops at what the bank holds")
		Mock.TypeInto(f.gift.edit, "5")
		f.send:Click()
		local rec = S():Get("bankreq", ME .. ":1")
		eq(rec.itemID, LINEN); eq(rec.count, 35); eq(rec.tip, 5 * GOLD)
		eq(f.item:GetText(), ""); eq(f.gift:GetText(), "")
		local row = f.area.rows[1]
		contains(row.reason:GetText(), "tip 5g")
		contains(A().BankRequestsView.TooltipLines(row.data)[2].text, "Tip: 5g")
	end)

	it("a quantity typed first is capped when the item is chosen", function()
		local f = open()
		Mock.TypeInto(f.amount.edit, "100")
		eq(f.amount:GetText(), "100", "no item yet")
		f.item.edit:SetFocus()
		shownRows(f.list)[1]:Click()
		eq(f.item:GetText(), "Copper Bar"); eq(f.amount:GetText(), "7")
	end)

	it("a pasted link closes the list and still works", function()
		local f = open()
		f.item.edit:SetFocus()
		Mock.TypeInto(f.item.edit, "|cffffffff|Hitem:118::::::::60:::::|h[Potion]|h|r")
		falsy(f.picker:IsShown()); contains(f.stock:GetText(), "Not in the bank")
		f.amount:SetText("3"); f.send:Click()
		eq(S():Get("bankreq", ME .. ":1").itemID, 118)
	end)

	it("a deposit has no list, no bank line and no tip box; a click elsewhere closes the list", function()
		local f = open()
		f.item.edit:SetFocus()
		f.catcher:Click()
		falsy(f.picker:IsShown())
		f.item.edit:ClearFocus(); f.item.edit:SetFocus()
		truthy(f.picker:IsShown())
		f.kindButtons[2]:Click()
		falsy(f.picker:IsShown()); falsy(f.gift:IsShown()); falsy(f.stock:IsShown()); falsy(f.prov:IsShown())
		f.item.edit:ClearFocus(); f.item.edit:SetFocus()
		falsy(f.picker:IsShown())
		f.kindButtons[1]:Click()
		truthy(f.gift:IsShown()); truthy(f.stock:IsShown())
	end)
end)

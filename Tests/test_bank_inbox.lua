-- The officers' inbox, the notices and the counter (M5.6; SPEC-08 BANK-23, BANK-24): how many requests wait, who is told when
-- a request arrives or is decided, the inbox with its "looks delivered" proposal, and the counter on the tab.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Inbox() return AzerothAccord.BankInbox end
local function V() return AzerothAccord.BankView end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, BOBALT, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000C0C"
local LINEN = 2589
local HOUR = 3600

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Bobalt", level = 20, class = "WARRIOR", rank = 4, guid = BOBALT },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function names()
	Mock.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
	Mock.items.cached[LINEN] = true
end

local function account(guid, chars, token)
	local list = {}
	for i, g in ipairs(chars) do list[i] = { guid = g, name = "C" .. i } end
	S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = token, chars = list, main = chars[1] }
	A().Accounts:MarkDirty()
	A().Bus:Emit("STORE_CHANGED", "accounts", guid, "remote")
end

-- A request record as another client would have sent it, announced on the Bus like an accepted remote record.
local function arrive(requester, n, status, extra, age)
	local id = requester .. ":" .. n
	local rec = { id = id, author = requester, rev = 1, time = GetServerTime(), requester = requester, kind = "withdraw", status = status or "open",
		itemID = LINEN, count = 20, created = GetServerTime() - (age or 0), history = { { s = "open", by = requester, t = GetServerTime() - (age or 0) } } }
	if rec.status ~= "open" and rec.status ~= "cancelled" then rec.author = OFF end
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("bankreq")[id] = rec
	A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
	return rec
end

local function asOfficer()
	guild(1)
	A().Role:Refresh()
end

local function entry(kind, name, item, count, t) return { kind = kind, name = name, itemID = item, count = count, t = t } end

local function log(author, tab, entries)
	local id = author .. ":log:" .. tab
	S():Records("bank")[id] = { id = id, author = author, rev = 1, time = GetServerTime(), kind = "log", tab = tab, rank = tab > 0 and 3 or nil,
		e = A().BankLog.Encode(entries), n = #entries }
end

describe("the counter", function()
	before_boot(function() guild(3) names() end)

	it("counts the open requests for an officer and nothing for a member", function()
		arrive(BOB, 1, "open"); arrive(BOB, 2, "open"); arrive(BOB, 3, "approved"); arrive(BOB, 4, "cancelled")
		eq(Inbox().PendingCount(), 0, "a member sees no counter")
		asOfficer()
		eq(Inbox().PendingCount(), 2, "approved and cancelled ones are not waiting for a decision")
	end)
end)

describe("the counter on the tab, the panel and the compartment", function()
	before_boot(function() guild(3) names() end)

	local function attach()
		Mock.communities.Open()
		return A().GuildTab.tab
	end

	it("shows the number on the tab for an officer, and nothing for 0 or for a member", function()
		local tab = attach()
		arrive(BOB, 1, "open")
		falsy(tab.badge:IsShown(), "a member: no mark")
		asOfficer()
		A().Bus:Emit("STORE_CHANGED", "bankreq", BOB .. ":1", "remote")
		truthy(tab.badge:IsShown()); eq(tab.badge:GetText(), "1")
		arrive(BOB, 2, "open")
		eq(tab.badge:GetText(), "2")
		arrive(BOB, 1, "approved", { rev = 2 }); arrive(BOB, 2, "rejected", { rev = 2 })
		falsy(tab.badge:IsShown(), "nothing waits")
	end)

	it("a tab that attaches after the counter was set shows it at once", function()
		asOfficer()
		arrive(BOB, 1, "open")
		A().Bus:Emit("ROLE_CHANGED")
		local tab = attach()
		eq(tab.badge:GetText(), "1")
	end)

	it("the Bank tab of the panel and the compartment tooltip say how many wait", function()
		asOfficer()
		arrive(BOB, 1, "open"); arrive(BOB, 2, "open")
		Mock.Slash("/accord bank")
		local bank = A().Shell.content.tabs.buttons.bank
		eq(bank.label:GetText(), "Bank")
		truthy(bank.badge:IsShown())
		eq(bank.badge.label:GetText(), "2")
		local tip = { lines = {} }
		function tip:AddLine(t) self.lines[#self.lines + 1] = t end
		A().Shell.FillTooltip(tip)
		contains(tip.lines, "2 bank request(s) waiting for an officer")
		arrive(BOB, 1, "approved", { rev = 2 }); arrive(BOB, 2, "approved", { rev = 2 })
		falsy(bank.badge:IsShown(), "nothing waits: no badge")
	end)
end)

describe("the notices", function()
	before_boot(function() guild(3) names() end)

	it("an install or a new guild starts silent: what is held counts as seen", function()
		asOfficer()
		local id = BOB .. ":1"
		S():Records("bankreq")[id] = { id = id, author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "withdraw", status = "open",
			itemID = LINEN, count = 20, created = GetServerTime(), history = {} }
		A().GuildKey:Data().bank = nil          -- the first run of this guild: nothing was ever told
		Inbox():Baseline()
		A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
		Mock.Advance(Inbox().NOTICE_WAIT + 1)
		falsy(text():find("New bank request"), "an old request is not news")
	end)

	it("an officer is told once about a new request, with who and what", function()
		asOfficer()
		Inbox():Baseline()
		arrive(BOB, 1, "open")
		arrive(BOB, 1, "open")   -- the same version again
		Mock.Advance(Inbox().NOTICE_WAIT + 1)
		local out = text()
		contains(out, "New bank request from Bob: Linen Cloth x20.")
		local _, n = out:gsub("New bank request", "")
		eq(n, 1)
	end)

	it("a member is not told about requests of others, and nobody about their own", function()
		Inbox():Baseline()
		arrive(BOB, 1, "open")
		Mock.Advance(Inbox().NOTICE_WAIT + 1)
		falsy(text():find("New bank request"))
		asOfficer()
		local rec = A().BankRequests:Create({ kind = "withdraw", amount = 100 })
		Mock.Advance(Inbox().NOTICE_WAIT + 1)
		falsy(text():find("New bank request"), "an officer's own request is no news")
	end)

	it("the requester is told when an officer approves, rejects or fulfils", function()
		Inbox():Baseline()
		local rec = A().BankRequests:Create({ kind = "withdraw", itemID = LINEN, count = 20 })
		local function decided(status, extra)
			local r = {}
			for k, v in pairs(S():Get("bankreq", rec.id)) do r[k] = v end
			r.status, r.author, r.rev, r.time = status, OFF, r.rev + 1, GetServerTime()
			r.history = { r.history[1], { s = status, by = OFF, t = GetServerTime() } }
			for k, v in pairs(extra or {}) do r[k] = v end
			S():Records("bankreq")[rec.id] = r
			A().Bus:Emit("STORE_CHANGED", "bankreq", rec.id, "remote")
			Mock.Advance(Inbox().NOTICE_WAIT + 1)
		end
		decided("approved")
		contains(text(), "Your bank request (Linen Cloth x20) was approved by Boss.")
		decided("fulfilled")
		contains(text(), "was marked as fulfilled by Boss")
	end)

	it("a rejection carries the officer's reason", function()
		Inbox():Baseline()
		local rec = A().BankRequests:Create({ kind = "withdraw", amount = 50000 })
		local r = S():Get("bankreq", rec.id)
		r.status, r.author, r.rev, r.note = "rejected", OFF, 2, "out of stock"
		r.history = { r.history[1], { s = "rejected", by = OFF, t = GetServerTime() } }
		A().Bus:Emit("STORE_CHANGED", "bankreq", rec.id, "remote")
		Mock.Advance(Inbox().NOTICE_WAIT + 1)
		contains(text(), "was rejected by Boss")
		contains(text(), "Reason: out of stock")
	end)

	it("the notices of one burst are printed together: three lines and the rest counted", function()
		asOfficer()
		Inbox():Baseline()
		for n = 1, 5 do arrive(BOB, n, "open") end
		Mock.Advance(1)
		falsy(text():find("New bank request"), "they wait for the rest of the burst")
		Mock.Advance(Inbox().NOTICE_WAIT)
		local _, lines = text():gsub("New bank request", "")
		eq(lines, 3)
		contains(text(), "...and 2 more bank notices")
	end)

	it("remembers what it told, so a reload does not repeat it", function()
		asOfficer()
		Inbox():Baseline()
		arrive(BOB, 1, "open")
		Mock.Advance(Inbox().NOTICE_WAIT + 1)
		eq(A().GuildKey:Data().bank.seen[BOB .. ":1"], "open")
	end)
end)

describe("the proposal: a movement of the bank that looks like the delivery", function()
	before_boot(function() guild(1) names() end)

	local function request(extra) return arrive(BOB, 1, "approved", extra, 5 * HOUR) end

	it("matches a withdrawal of the item by a character of the requester's account, after the request", function()
		account(BOB, { BOB, BOBALT }, "T"); account(BOBALT, { BOBALT, BOB }, "T")
		local now = GetServerTime()
		log(OFF, 1, { entry("withdraw", "Bobalt", LINEN, 20, now - 2 * HOUR) })
		local r = A().BankRequests:Get(request().id)
		local e = Inbox():Suggest(r)
		notNil(e); eq(e.name, "Bobalt"); eq(e.itemID, LINEN)
	end)

	it("does not match another kind, another item, a smaller count, an earlier time or another account", function()
		local now = GetServerTime()
		local r = A().BankRequests:Get(request().id)
		log(OFF, 1, { entry("deposit", "Bob", LINEN, 20, now - 2 * HOUR) })
		isNil(Inbox():Suggest(r), "a deposit is not a withdrawal")
		log(OFF, 1, { entry("withdraw", "Bob", 118, 20, now - 2 * HOUR) })
		isNil(Inbox():Suggest(r), "another item")
		log(OFF, 1, { entry("withdraw", "Bob", LINEN, 5, now - 2 * HOUR) })
		isNil(Inbox():Suggest(r), "fewer than asked")
		log(OFF, 1, { entry("withdraw", "Bob", LINEN, 20, now - 9 * HOUR) })
		isNil(Inbox():Suggest(r), "before the request")
		log(OFF, 1, { entry("withdraw", "Ann", LINEN, 20, now - 2 * HOUR) })
		isNil(Inbox():Suggest(r), "somebody else")
		log(OFF, 1, { entry("withdraw", "Bob-Realm", LINEN, 25, now - 2 * HOUR) })
		notNil(Inbox():Suggest(r), "the realm is ignored and more than asked is fine")
	end)

	it("a deposit or a donation of an item matches a deposit, and gold matches the money log", function()
		local now = GetServerTime()
		local rd = A().BankRequests:Get(arrive(BOB, 2, "approved", { kind = "donation" }, 5 * HOUR).id)
		log(OFF, 1, { entry("deposit", "Bob", LINEN, 20, now - HOUR) })
		notNil(Inbox():Suggest(rd))
		local rg = A().BankRequests:Get(arrive(BOB, 3, "approved", { kind = "withdraw", itemID = false, count = false, amount = 50000 }, 5 * HOUR).id)
		isNil(Inbox():Suggest(rg))
		log(OFF, 0, { entry("withdraw", "Bob", 0, 60000, now - HOUR) })
		local e = Inbox():Suggest(rg)
		notNil(e); eq(e.count, 60000)
	end)
end)

describe("the inbox mode", function()
	before_boot(function() guild(1) names() end)

	local function shown(frames)
		local out = {}
		for _, f in ipairs(frames) do if f:IsShown() then out[#out + 1] = f end end
		return out
	end

	it("has no button for a member", function()
		guild(3)
		A().Role:Refresh()
		Mock.Slash("/accord bank")
		for _, m in ipairs(V():ModeList()) do ne(m.id, "inbox") end
		eq(#Inbox():Rows(), 0)
	end)

	it("lists what waits for an officer, oldest first, with the suggestion, and Fulfilled closes it", function()
		A().Role:Refresh()
		local now = GetServerTime()
		arrive(BOB, 1, "open", nil, 3 * HOUR)
		arrive(BOB, 2, "approved", { itemID = LINEN, count = 20 }, 6 * HOUR)
		arrive(BOB, 3, "fulfilled", nil, 7 * HOUR)
		log(OFF, 1, { entry("withdraw", "Bob", LINEN, 20, now - HOUR) })
		Mock.Slash("/accord bank")
		V():SetMode("inbox")
		local f = V().modes.inbox.frame
		local rows = shown(f.area.rows)
		eq(#rows, 2)
		eq(rows[1].status:GetText(), "Approved"); eq(rows[2].status:GetText(), "Open")
		contains(rows[1].reason:GetText(), "Looks delivered: Bob - Linen Cloth x20, 1 h ago")
		eq(rows[1].buttons[1]:GetLabel(), "Reject"); eq(rows[1].buttons[2]:GetLabel(), "Fulfilled")
		eq(rows[2].buttons[1]:GetLabel(), "Approve")
		rows[1].buttons[2]:Click()
		eq(S():Get("bankreq", BOB .. ":2").status, "fulfilled")
		eq(#shown(f.area.rows), 1)
	end)

	it("says when nothing waits", function()
		A().Role:Refresh()
		Mock.Slash("/accord bank")
		V():SetMode("inbox")
		contains(V().modes.inbox.frame.message:GetText(), "Nothing waits for you")
	end)
end)

describe("notices in the network simulator", function()
	it("an online officer is told about a member's request, and the requester about the officer's decision", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, seed = 91 }
		sim:advance(60)
		local id = sim:client(3):addon().BankRequests:Create({ kind = "withdraw", itemID = LINEN, count = 20 }).id
		sim:advance(60)
		local function out(i) return table.concat(sim:client(i):output(), "\n") end
		contains(out(1), "New bank request from " .. Sim.nameOf(3))
		contains(out(2), "New bank request from " .. Sim.nameOf(3))
		falsy(out(4):find("New bank request"), "a member is not told")
		falsy(out(3):find("New bank request"), "nor the requester")
		eq(sim:client(1):addon().BankInbox.PendingCount(), 1)
		eq(sim:client(4):addon().BankInbox.PendingCount(), 0)
		sim:client(1):addon().BankRequests:Decide(id, "approved")
		sim:advance(60)
		contains(out(3), "Your bank request")
		contains(out(3), "was approved by " .. Sim.nameOf(1))
		falsy(out(4):find("Your bank request"))
		eq(sim:client(2):addon().BankInbox.PendingCount(), 0, "the other officer's counter went down")
	end)
end)

-- M8.7: the officers' list and the "looks paid" hint (SPEC-08 BANK-26, BANK-27) --------------------------------------------
local GOLD = 10000

local function money(entries) log(OFF, 0, entries) end
local function deposit(name, copper, age) return entry("deposit", name, 0, copper, GetServerTime() - age) end

-- Three waiting requests: Bob's oldest with no tip, then 2 gold, then 9 gold (the newest).
local function three()
	arrive(BOB, 1, "open", nil, 5 * HOUR)
	arrive(BOB, 2, "approved", { tip = 2 * GOLD }, 4 * HOUR)
	arrive(BOB, 3, "open", { tip = 9 * GOLD }, 3 * HOUR)
end

local function ids(rows)
	local out = {}
	for i, r in ipairs(rows) do out[i] = tonumber(r.id:match(":(%d+)$")) end
	return out
end

describe("the sort orders of the officers' list", function()
	before_boot(function() guild(1) names() end)

	it("oldest first by default, newest first, or the highest tip first", function()
		A().Role:Refresh(); three()
		deepEq(ids(Inbox():Rows()), { 1, 2, 3 })
		deepEq(ids(Inbox():Rows({ sort = "oldest" })), { 1, 2, 3 })
		deepEq(ids(Inbox():Rows({ sort = "newest" })), { 3, 2, 1 })
		deepEq(ids(Inbox():Rows({ sort = "tip" })), { 3, 2, 1 })
		arrive(BOB, 4, "open", { tip = 2 * GOLD }, 9 * HOUR)
		arrive(BOB, 5, "open", nil, 8 * HOUR)
		deepEq(ids(Inbox():Rows({ sort = "tip" })), { 3, 4, 2, 5, 1 }, "equal tips and no tip: the oldest first")
		deepEq(ids(Inbox():Rows({ sort = "oldest" })), { 4, 5, 1, 2, 3 })
	end)

	it("shows date and time, requester, item, quantity and tip, and the chips change the order", function()
		A().Role:Refresh(); three()
		arrive(BOB, 4, "open", { itemID = false, count = false, amount = 50000 }, HOUR)
		Mock.Slash("/accord bank")
		V():SetMode("inbox")
		local f = V().modes.inbox.frame
		local row = f.area.rows[1]
		eq(row.date:GetText(), date("%Y-%m-%d %H:%M", GetServerTime() - 5 * HOUR))
		eq(row.name:GetText(), "Bob"); eq(row.what:GetText(), "Linen Cloth"); eq(row.count:GetText(), "20"); eq(row.gift:GetText(), "-")
		eq(f.area.rows[2].gift:GetText(), "2g")
		eq(f.area.rows[4].what:GetText(), "5g", "a request for gold"); eq(f.area.rows[4].count:GetText(), "")
		eq(f.columns.gift:GetText(), "Tip"); eq(f.columns.date:GetText(), "Date and time")
		eq(f.sorts.active, "oldest")
		f.sorts.buttons[3]:Click()
		eq(A().BankRequestsView.inboxSort, "tip")
		eq(f.area.rows[1].gift:GetText(), "9g"); eq(f.area.rows[2].gift:GetText(), "2g")
		f.sorts.buttons[2]:Click()
		eq(f.area.rows[1].what:GetText(), "5g", "newest first")
	end)
end)

describe("the proposal: a deposit of gold that looks like the payment of a tip", function()
	before_boot(function() guild(1) names() end)

	local function tipped(n, status, tip, age) return arrive(BOB, n, status, { tip = tip }, age).id end

	it("matches a deposit of at least the tip by a character of the account, after the request", function()
		A().Role:Refresh()
		account(BOB, { BOB, BOBALT }, "T"); account(BOBALT, { BOBALT, BOB }, "T")
		local id = tipped(1, "open", 5 * GOLD, 5 * HOUR)
		money({ deposit("Bobalt", 6 * GOLD, 2 * HOUR) })
		local e = Inbox():Payments()[id]
		notNil(e); eq(e.name, "Bobalt"); eq(e.count, 6 * GOLD)
		eq(Inbox():Rows()[1].paid.count, 6 * GOLD)
	end)

	it("does not match less gold, a withdrawal, an item, an earlier time or another account", function()
		A().Role:Refresh()
		local id = tipped(1, "open", 5 * GOLD, 5 * HOUR)
		local function none(why) isNil(Inbox():Payments()[id], why) end
		money({ deposit("Bob", 5 * GOLD - 1, 2 * HOUR) }); none("less than the tip")
		money({ deposit("Bob", 3 * GOLD, 2 * HOUR), deposit("Bob", 2 * GOLD, HOUR) }); none("small deposits are not added up")
		money({ entry("withdraw", "Bob", 0, 5 * GOLD, GetServerTime() - HOUR) }); none("a withdrawal")
		money({ deposit("Bob", 5 * GOLD, 9 * HOUR) }); none("before the request")
		money({ deposit("Ann", 5 * GOLD, HOUR) }); none("somebody else")
		money({})
		log(OFF, 1, { entry("deposit", "Bob", LINEN, 5 * GOLD, GetServerTime() - HOUR) }); none("an item log")
		money({ deposit("Bob-Realm", 5 * GOLD, HOUR) })
		notNil(Inbox():Payments()[id])
	end)

	it("one deposit pays one tip, the oldest request first; rejected and cancelled ones take none", function()
		A().Role:Refresh()
		local rejected = tipped(1, "rejected", GOLD, 9 * HOUR)
		local cancelled = tipped(2, "cancelled", GOLD, 8 * HOUR)
		local first = tipped(3, "fulfilled", GOLD, 7 * HOUR)
		local second = tipped(4, "open", GOLD, 6 * HOUR)
		money({ deposit("Bob", GOLD, HOUR) })
		local paid = Inbox():Payments()
		isNil(paid[rejected]); isNil(paid[cancelled]); notNil(paid[first]); isNil(paid[second])
		money({ deposit("Bob", GOLD, HOUR), deposit("Bob", 2 * GOLD, 2 * HOUR) })
		paid = Inbox():Payments()
		eq(paid[first].count, 2 * GOLD, "the oldest deposit first"); eq(paid[second].count, GOLD)
	end)

	it("is for officers only, and says nothing about a request without a tip", function()
		A().Role:Refresh()
		local id = tipped(1, "open", GOLD, 5 * HOUR)
		arrive(BOB, 2, "open", nil, 4 * HOUR)
		money({ deposit("Bob", 2 * GOLD, HOUR) })
		notNil(Inbox():Payments()[id]); isNil(Inbox():Payments()[BOB .. ":2"])
		guild(3)
		A().Role:Refresh()
		deepEq(Inbox():Payments(), {})
	end)

	it("the officers' list and the tooltip say Looks paid; the officer still marks the request", function()
		A().Role:Refresh()
		local id = tipped(1, "approved", GOLD, 5 * HOUR)
		money({ deposit("Bob", GOLD, HOUR) })
		Mock.Slash("/accord bank")
		V():SetMode("inbox")
		local row = V().modes.inbox.frame.area.rows[1]
		contains(row.reason:GetText(), "Looks paid: Bob deposited 1g, 1 h ago")
		eq(S():Get("bankreq", id).status, "approved", "nothing is marked by itself")
		V():SetMode("requests")
		local lines = A().BankRequestsView.TooltipLines(V().modes.requests.frame.area.rows[1].data)
		local found = false
		for _, line in ipairs(lines) do if type(line) == "table" and line.text:find("Looks paid", 1, true) then found = true end end
		truthy(found)
	end)
end)

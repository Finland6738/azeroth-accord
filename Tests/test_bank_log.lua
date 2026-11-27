-- Bank logs, donations and the money over time (M5.4; SPEC-08 BANK-10..BANK-12, ADR 0009 rule 3): the logs are captured at the
-- vault, merged over time and over guildmates without duplicates, the donations are counted per account, and the money keeps
-- a history. Includes the view modes and the network simulator.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Log() return AzerothAccord.BankLog end
local function V() return AzerothAccord.BankView end

local ME, BOB, BOBALT, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000A44", "Player-1-00000C0C"
local LINEN, POTION = 2589, 118
local HOUR, DAY = 3600, 86400

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Bobalt", level = 20, class = "WARRIOR", rank = 4, guid = BOBALT },
		{ name = "Ann", level = 55, class = "PRIEST", rank = 3, guid = ANN },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function account(guid, chars, token)
	local list = {}
	for i, g in ipairs(chars) do list[i] = { guid = g, name = "C" .. i } end
	S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = token, chars = list, main = chars[1] }
	A().Accounts:MarkDirty()
	A().Bus:Emit("STORE_CHANGED", "accounts", guid, "remote")
end

-- A game item-log row: { kind, name, itemID, count, tab1, tab2, years, months, days, hours }
local function row(kind, name, item, count, days, hours) return { kind, name, item, count, nil, nil, 0, 0, days or 0, hours or 0 } end

local function setVault(tabs, moneyLog)
	Mock.bank.tabs = tabs
	Mock.bank.money = 500000
	Mock.bank.moneyLog = moneyLog or {}
end

local function openVault(seconds)
	Mock.bank.Open()
	Mock.Advance(seconds or 40)
	Mock.bank.Close()
	Mock.Advance(1)
end

local function logRec(author, tab, entries, extra)
	local id = author .. ":log:" .. tab
	local rec = { id = id, author = author, rev = 1, time = GetServerTime(), kind = "log", tab = tab, rank = tab > 0 and 3 or nil,
		e = Log().Encode(entries), n = #entries }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("bank")[id] = rec
	return rec
end

local function entry(kind, name, item, count, t) return { kind = kind, name = name, itemID = item, count = count, t = t } end

describe("entries: time, text and merge", function()
	before_boot(function() guild() end)

	it("rounds the time as coarsely as the age", function()
		local at = 1000 * DAY + 1234
		eq(Log().Bucket(at, 0, 0, 0, 2), math.floor((at - 2 * HOUR) / HOUR) * HOUR, "hours within two days")
		eq(Log().Bucket(at, 0, 0, 3, 5) % DAY, 0, "a day beyond two days")
		eq(Log().Bucket(at, 0, 3, 0, 0) % (7 * DAY), 0, "a week beyond two months")
		eq(Log().Bucket(at, nil, nil, nil, nil), math.floor(at / HOUR) * HOUR, "no age: now")
	end)

	it("round-trips entries as text, sorted newest first, and refuses what is not text of entries", function()
		local list = { entry("deposit", "Bob", LINEN, 20, 3600), entry("withdraw", "Ann", POTION, 3, 7200), entry("deposit", "Bob", 0, 10000, 3600) }
		local text = Log().Encode(list)
		local back = Log().Decode(text)
		eq(#back, 3); eq(back[1].t, 7200); eq(back[1].name, "Ann")
		deepEq(Log().Decode(""), {})
		eq(select(2, Log().Decode(7)), "shape")
		eq(select(2, Log().Decode(("x"):rep(10000))), "size")
		eq(select(2, Log().Decode("deposit,Bob,1,2")), "entry")
		eq(select(2, Log().Decode("deposit,,1,2,3")), "entry", "a name is needed")
		eq(select(2, Log().Decode("dep osit,Bob,1,2,3")), "entry")
		local many = {}
		for i = 1, 151 do many[i] = ("deposit,Bob,1,%d,%d"):format(i, i) end
		eq(select(2, Log().Decode(table.concat(many, ";"))), "count")
	end)

	it("merges the same events once, even when their times differ by one bucket", function()
		local a = { entry("deposit", "Bob", LINEN, 20, 10 * HOUR), entry("withdraw", "Ann", POTION, 1, 8 * HOUR) }
		local b = { entry("deposit", "Bob", LINEN, 20, 11 * HOUR), entry("deposit", "Ann", LINEN, 5, 12 * HOUR) }
		local m = Log().Merge(a, b)
		eq(#m, 3)
		local count = 0
		for _, e in ipairs(m) do if e.name == "Bob" then count = count + 1 end end
		eq(count, 1, "the deposit of Bob seen in both captures is one entry")
		eq(#Log().Merge(a, a), 2, "merging a capture with itself changes nothing")
	end)

	it("two identical events in one capture are two; the other capture does not make them four", function()
		local twice = { entry("deposit", "Bob", LINEN, 20, 10 * HOUR), entry("deposit", "Bob", LINEN, 20, 10 * HOUR) }
		local once = { entry("deposit", "Bob", LINEN, 20, 10 * HOUR) }
		eq(#Log().Merge(twice, once), 2)
		eq(#Log().Merge(once, twice), 2)
		eq(#Log().Merge(twice, twice), 2)
	end)

	it("different counts, names, items or hours are different events", function()
		local a = { entry("deposit", "Bob", LINEN, 20, 10 * HOUR) }
		eq(#Log().Merge(a, { entry("deposit", "Bob", LINEN, 21, 10 * HOUR) }), 2)
		eq(#Log().Merge(a, { entry("deposit", "Ann", LINEN, 20, 10 * HOUR) }), 2)
		eq(#Log().Merge(a, { entry("deposit", "Bob", POTION, 20, 10 * HOUR) }), 2)
		eq(#Log().Merge(a, { entry("withdraw", "Bob", LINEN, 20, 10 * HOUR) }), 2)
		eq(#Log().Merge(a, { entry("deposit", "Bob", LINEN, 20, 14 * HOUR) }), 2, "four hours apart")
	end)

	it("gives the same result whichever list comes first", function()
		local a = { entry("deposit", "Bob", LINEN, 20, 10 * HOUR), entry("deposit", "Bob", LINEN, 20, 30 * HOUR) }
		local b = { entry("deposit", "Bob", LINEN, 20, 11 * HOUR), entry("deposit", "Bob", LINEN, 20, 50 * HOUR) }
		eq(Log().Encode(Log().Merge(a, b)), Log().Encode(Log().Merge(b, a)))
	end)

	it("a log record is valid with its own id, a tab 0..8 and entries that decode", function()
		local rec = logRec(ME, 1, { entry("deposit", "Bob", LINEN, 20, 3600) })
		truthy(A().Bank.ValidRecord(rec))
		falsy(A().Bank.ValidRecord(logRec(ME, 1, {}, { id = BOB .. ":log:1" })))
		falsy(A().Bank.ValidRecord(logRec(ME, 1, {}, { e = "junk" })))
		falsy(A().Bank.ValidRecord(logRec(ME, 1, {}, { tab = 9, id = ME .. ":log:9" })))
		truthy(A().Bank.ValidRecord(logRec(ME, 0, {})))
		local many = {}
		for i = 1, 150 do many[i] = entry("deposit", "Bobbybobbyname", LINEN, i, i * 3600) end
		local big = logRec(ME, 2, many)
		truthy(A().Bank.ValidRecord(big))
		truthy(AzerothAccord.Config.EstimateSize(big) < S().SETS.bank.maxBytes, "150 entries fit a record: " .. AzerothAccord.Config.EstimateSize(big))
	end)
end)

describe("the capture of the logs", function()
	before_boot(function()
		guild(3)
		Mock.bank.tabs = nil
	end)

	local function tabs(log)
		return { { name = "Consumables", items = { [1] = { itemID = LINEN, count = 20 } }, log = log }, { name = "Gear", items = {}, log = {} } }
	end

	it("reads the item logs and the money log at the open vault and publishes one record each", function()
		setVault(tabs({ row("deposit", "Bob", LINEN, 20, 0, 2), row("withdraw", "Ann", POTION, 3, 1, 4) }),
			{ { "deposit", "Bob", 25000, 0, 0, 0, 3 }, { "repair", "Ann", 500, 0, 0, 1, 0 } })
		openVault()
		local item = S():Get("bank", ME .. ":log:1")
		notNil(item); eq(item.kind, "log"); eq(item.tab, 1); eq(item.n, 2); eq(item.rank, 3)
		isNil(item.restricted)
		local money = S():Get("bank", ME .. ":log:0")
		notNil(money); eq(money.n, 2); isNil(money.rank)
		isNil(S():Get("bank", ME .. ":log:2"), "an empty log is not published")
		local entries = Log():Entries()
		eq(#entries, 4)
		eq(A().Compat:Feature("bankLogs"), "available")
	end)

	it("a second visit adds to the history, and entries seen twice stay one", function()
		setVault(tabs({ row("deposit", "Bob", LINEN, 20, 0, 2), row("withdraw", "Ann", POTION, 3, 0, 5) }))
		openVault()
		eq(#Log():Entries({ tab = 1 }), 2)
		Mock.Advance(2 * HOUR)
		-- the game forgot the oldest one and shows a new one; the other is now 2 hours older
		Mock.bank.tabs[1].log = { row("deposit", "Bob", LINEN, 20, 0, 4), row("deposit", "Cat", POTION, 1, 0, 0) }
		openVault()
		local entries = Log():Entries({ tab = 1 })
		eq(#entries, 3, "Ann's withdrawal is kept beyond the game's own history; Bob's deposit is not counted twice")
		local names = {}
		for _, e in ipairs(entries) do names[#names + 1] = e.name end
		table.sort(names)
		deepEq(names, { "Ann", "Bob", "Cat" })
	end)

	it("an unchanged log is not published again", function()
		setVault(tabs({ row("deposit", "Bob", LINEN, 20, 0, 2) }))
		openVault()
		local rev = S():Get("bank", ME .. ":log:1").rev
		openVault()
		eq(S():Get("bank", ME .. ":log:1").rev, rev)
	end)

	it("the log of a tab read by an officer is restricted, the money log is not", function()
		Mock.guild.Set{ name = "Accord", myRank = 1, members = {} }
		A().Role:Refresh()
		setVault(tabs({ row("deposit", "Bob", LINEN, 20, 0, 2) }), { { "deposit", "Bob", 100, 0, 0, 0, 1 } })
		openVault()
		eq(S():Get("bank", ME .. ":log:1").restricted, true)
		isNil(S():Get("bank", ME .. ":log:0").restricted)
	end)

	it("asks for the money log with the tab number after the last item tab, one query at a time", function()
		local asked = {}
		local original = QueryGuildBankLog
		QueryGuildBankLog = function(tab) asked[#asked + 1] = tab return original(tab) end
		setVault(tabs({ row("deposit", "Bob", LINEN, 20, 0, 2) }), { { "deposit", "Bob", 100, 0, 0, 0, 1 } })
		openVault()
		deepEq(asked, { 1, 2, 7 })
		QueryGuildBankLog = original
	end)

	it("keeps at most 150 entries per record, the newest", function()
		local log = {}
		for i = 1, 90 do log[i] = row("deposit", "Bob", LINEN, i, 0, 1 + i % 40) end
		setVault(tabs(log))
		openVault()
		Mock.bank.tabs[1].log = {}
		for i = 1, 90 do Mock.bank.tabs[1].log[i] = row("deposit", "Ann", POTION, i, 3, 1 + i % 20) end
		openVault()
		eq(S():Get("bank", ME .. ":log:1").n, 150)
	end)
end)

describe("the merged log of the guild", function()
	before_boot(function() guild(3) end)

	it("merges what two guildmates read, once", function()
		local t = GetServerTime() - 10 * HOUR
		t = math.floor(t / HOUR) * HOUR
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 20, t), entry("withdraw", "Ann", POTION, 3, t - 5 * HOUR) })
		logRec(ANN, 1, { entry("deposit", "Bob", LINEN, 20, t + HOUR), entry("deposit", "Cat", POTION, 1, t + 2 * HOUR) })
		local entries = Log():Entries()
		eq(#entries, 3)
		eq(entries[1].name, "Cat"); eq(entries[1].tab, 1)
	end)

	it("a log of a tab above this rank is not shown, the money log is", function()
		logRec(OFF, 2, { entry("deposit", "Bob", LINEN, 20, 3600) }, { rank = 1, restricted = true })
		logRec(OFF, 3, { entry("deposit", "Bob", LINEN, 20, 7200) }, { rank = 2 })
		logRec(OFF, 0, { entry("deposit", "Bob", 0, 100, 3600) })
		local entries = Log():Entries()
		eq(#entries, 1); eq(entries[1].tab, 0)
	end)

	it("an officer sees every log", function()
		Mock.guild.Set{ name = "Accord", myRank = 1, members = {} }
		A().Role:Refresh()
		logRec(OFF, 2, { entry("deposit", "Bob", LINEN, 20, 3600) }, { rank = 1, restricted = true })
		eq(#Log():Entries(), 1)
	end)
end)

describe("donations per account", function()
	before_boot(function() guild(3) end)

	local now
	local function world()
		now = GetServerTime()
		account(BOB, { BOB, BOBALT }, "BOBTOKEN"); account(BOBALT, { BOBALT, BOB }, "BOBTOKEN")
		account(ANN, { ANN }, "ANNTOKEN")
		logRec(BOB, 1, {
			entry("deposit", "Bob", LINEN, 20, now - 2 * DAY), entry("deposit", "Bobalt", LINEN, 30, now - 3 * DAY),
			entry("deposit", "Ann", POTION, 5, now - 40 * DAY), entry("withdraw", "Ann", POTION, 50, now - 1 * DAY),
			entry("deposit", "Gone", LINEN, 100, now - 200 * DAY),
		})
		logRec(BOB, 0, {
			entry("deposit", "Bob", 0, 50000, now - 5 * DAY), entry("deposit", "Ann", 0, 80000, now - 100 * DAY),
			entry("repair", "Ann", 0, 999999, now - 1 * DAY), entry("deposit", "Bobalt", 0, 25000, now - 10 * DAY),
		})
	end

	it("counts the deposits of an account's characters together, 30 days first", function()
		world()
		local rows = Log():Donations({ window = "d30" })
		eq(#rows, 1)
		eq(rows[1].name, "Bob"); eq(rows[1].gold, 75000); eq(rows[1].items, 50); eq(rows[1].deposits, 4)
		eq(rows[1].place, 1)
	end)

	it("a year and all the time add the older deposits, and withdrawals and repairs never count", function()
		world()
		local year = Log():Donations({ window = "d365", sort = "gold" })
		eq(#year, 3)
		eq(year[1].name, "Ann"); eq(year[1].gold, 80000); eq(year[1].items, 5)
		eq(year[2].name, "Bob")
		eq(year[3].name, "Gone"); isNil(year[3].classFile, "somebody who left is listed by name")
		local ordered = Log():Donations({ window = "all", sort = "items" })
		eq(ordered[1].name, "Gone"); eq(ordered[1].items, 100)
	end)

	it("a tie shares the place", function()
		now = GetServerTime()
		account(BOB, { BOB }, "B"); account(ANN, { ANN }, "A")
		logRec(BOB, 0, { entry("deposit", "Bob", 0, 100, now - DAY), entry("deposit", "Ann", 0, 100, now - DAY) })
		local rows = Log():Donations({ window = "all" })
		eq(rows[1].place, 1); eq(rows[2].place, 1)
	end)

	it("is visible to every member, or to officers only with the one switch (SPEC-10 Q5)", function()
		world()
		truthy(Log().DonationsVisible())
		Log().DONATIONS_VISIBLE_TO = "officers"
		falsy(Log().DonationsVisible())
		falsy(V().modes.donations.available())
		Log().DONATIONS_VISIBLE_TO = "everyone"
	end)
end)

describe("the money over time", function()
	before_boot(function() guild(3) end)

	local function money(author, copper, age)
		local id = author .. ":money"
		local rec = { id = id, author = author, rev = 1, time = GetServerTime() - age, kind = "money", money = copper }
		S():Records("bank")[id] = rec
		return rec
	end

	it("keeps a history of the money records that arrive, in time order, without repeating the same amount", function()
		Log():RecordMoney(money(BOB, 1000, 10 * DAY))
		Log():RecordMoney(money(ANN, 5000, 2 * DAY))
		Log():RecordMoney(money(OFF, 3000, 6 * DAY))   -- older than the last: inserted in order
		Log():RecordMoney(money(OFF, 3000, 6 * DAY))   -- the same record again
		Log():RecordMoney(money(OFF, 3000, 6 * DAY - 3 * HOUR))   -- the same amount three hours later: not a new point
		local h = Log():History()
		eq(#h, 3)
		eq(h[1].m, 1000); eq(h[2].m, 3000); eq(h[3].m, 5000)
	end)

	it("a money record that reaches the store is noted by the Bus", function()
		local rec = money(BOB, 7777, DAY)
		A().Bus:Emit("STORE_CHANGED", "bank", rec.id, "remote")
		eq(#Log():History(), 1); eq(Log():History()[1].m, 7777)
	end)

	it("draws the series as the last known amount at the end of each slice", function()
		Log():RecordMoney(money(BOB, 1000, 20 * DAY))
		Log():RecordMoney(money(ANN, 4000, 5 * DAY))
		local s = Log():MoneySeries(30, 30)
		eq(s.n, 30)
		isNil(s.values[1], "before the first point")
		eq(s.values[12], 1000); eq(s.values[30], 4000)
		eq(s.min, 1000); eq(s.max, 4000)
		local heights = A().BankLogView.Chart(s)
		eq(heights[1], 0); near(heights[30], 1.0, 1e-9); near(heights[12], 0.1, 1e-9)
		isNil(A().BankLogView.Chart({ values = {}, n = 30 }), "no point at all: nothing to draw")
	end)

	it("keeps at most 500 points", function()
		for i = 1, 520 do Log():RecordMoney({ kind = "money", money = i * 100, time = GetServerTime() - (600 - i) * DAY }) end
		eq(#Log():History(), 500)
	end)
end)

describe("the log, donations and money modes", function()
	before_boot(function()
		guild(3)
		Mock.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
		Mock.items.info[POTION] = { name = "Minor Healing Potion", quality = 1, icon = 134830 }
		Mock.items.cached[LINEN] = true; Mock.items.cached[POTION] = true
	end)

	local function shown(frames)
		local out = {}
		for _, f in ipairs(frames) do if f:IsShown() then out[#out + 1] = f end end
		return out
	end

	local function world()
		local now = GetServerTime()
		account(BOB, { BOB, BOBALT }, "BOBTOKEN"); account(BOBALT, { BOBALT, BOB }, "BOBTOKEN")
		S():Records("bank")[BOB .. ":t1"] = { id = BOB .. ":t1", author = BOB, rev = 1, time = now, kind = "tab", tab = 1, name = "Consumables",
			rank = 3, it = "1.2589.20", n = 1 }
		logRec(BOB, 1, { entry("deposit", "Bob", LINEN, 20, now - 3 * HOUR), entry("withdraw", "Ann", POTION, 3, now - 30 * HOUR) })
		logRec(BOB, 0, { entry("deposit", "Bob", 0, 25000, now - 4 * DAY) })
		Log():RecordMoney({ kind = "money", money = 1000, time = now - 20 * DAY })
		Log():RecordMoney({ kind = "money", money = 4000, time = now - 2 * DAY })
		A().Bus:Emit("STORE_CHANGED", "bank", BOB .. ":log:1", "remote")
	end

	it("the log lists when, tab, who, what and how much, newest first; the search filters it", function()
		world()
		Mock.Slash("/accord bank")
		V():SetMode("log")
		local f = V().modes.log.frame
		local rows = shown(f.area.rows)
		eq(#rows, 3)
		eq(rows[1].cells.name:GetText(), "Bob"); eq(rows[1].cells.kind:GetText(), "Deposit")
		eq(rows[1].cells.detail:GetText(), "Linen Cloth x20"); eq(rows[1].cells.tab:GetText(), "Consumables")
		eq(rows[1].cells.when:GetText(), "3 h ago")
		eq(rows[2].cells.kind:GetText(), "Withdrawal"); eq(rows[2].cells.detail:GetText(), "Minor Healing Potion x3")
		eq(rows[3].cells.tab:GetText(), "Money"); eq(rows[3].cells.detail:GetText(), "2g 50s")
		A().Shell:OnSearch("potion")
		eq(#shown(f.area.rows), 1)
	end)

	it("the donations list ranks accounts and the buttons change the window and the order", function()
		world()
		Mock.Slash("/accord bank")
		V():SetMode("donations")
		local f = V().modes.donations.frame
		local rows = shown(f.area.rows)
		eq(#rows, 1); eq(rows[1].cells.name:GetText(), "Bob"); eq(rows[1].cells.gold:GetText(), "2g 50s"); eq(rows[1].cells.items:GetText(), "20 items")
		f.picks.window.buttons[3]:Click()
		eq(f.picks.window.buttons[3].label:GetText(), "All time"); truthy(f.picks.window.buttons[3]:IsSelected())
		isNil(f.picks.sort, "the order is the headers', not buttons (2026-11-27)")
		local items
		for _, b in ipairs(f.head.buttons) do if b.key == "items" then items = b end end
		items:Click()
		eq(A().BankLogView.sort, "items")
		truthy(items.arrow:IsShown(), "the sorted header has its arrow")
	end)

	it("the log has a header and a click on a title sorts by it, a second click reverses", function()
		world()
		Mock.Slash("/accord bank")
		V():SetMode("log")
		local f = V().modes.log.frame
		local titles = {}
		for i, b in ipairs(f.head.buttons) do titles[i] = b.label:GetText() end
		deepEq(titles, { "WHEN", "TAB", "WHO", "WHAT", "ITEM OR AMOUNT" })
		local who
		for _, b in ipairs(f.head.buttons) do if b.key == "name" then who = b end end
		who:Click()
		local first = shown(f.area.rows)[1].cells.name:GetText()
		who:Click()
		local again = shown(f.area.rows)[1].cells.name:GetText()
		truthy(first <= again, "ascending, then descending")
	end)

	it("the donations mode has no button when the list is for officers and this is a member", function()
		world()
		Log().DONATIONS_VISIBLE_TO = "officers"
		Mock.Slash("/accord bank")
		for _, m in ipairs(V():ModeList()) do ne(m.id, "donations") end
		Log().DONATIONS_VISIBLE_TO = "everyone"
	end)

	it("the money mode draws bars, or says there is no money yet", function()
		world()
		Mock.Slash("/accord bank")
		V():SetMode("money")
		local f = V().modes.money.frame
		truthy(f.chart:IsShown())
		contains(f.high:GetText(), "40s")
		eq(#shown(f.chart.bars) > 0, true)
		notNil(f.head, "the money log as a table under the chart")
		A().GuildKey:Data().bank.history = {}
		V():Redraw()
		truthy(f.chartMessage:IsShown())
	end)
end)

describe("logs in the network simulator", function()
	it("two guildmates read overlapping logs and every client shows the same merged list once", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, seed = 71 }
		sim:advance(40)
		local function vault(c, log)
			local m = c.Mock
			m.bank.tabs = { { name = "Consumables", items = { [1] = { itemID = LINEN, count = 20 } }, log = log } }
			m.bank.money = 1000
			m.bank.moneyLog = { { "deposit", "Sima", 50000, 0, 0, 0, 2 } }
			m.bank.Open()
			sim:advance(30)
			m.bank.Close()
			sim:advance(5)
		end
		vault(sim:client(3), { row("deposit", "Sima", LINEN, 20, 0, 2), row("withdraw", "Simb", POTION, 3, 0, 5) })
		vault(sim:client(4), { row("deposit", "Sima", LINEN, 20, 0, 2), row("deposit", "Simc", POTION, 1, 0, 0) })
		sim:advance(120)
		local reference
		for i = 1, 5 do
			local entries = sim:client(i):addon().BankLog:Entries()
			eq(#entries, 4, "client " .. i .. ": three item events and one money deposit")
			local text = {}
			for _, e in ipairs(entries) do text[#text + 1] = e.tab .. e.kind .. e.name .. e.count .. ":" .. e.t end
			text = table.concat(text, "|")
			reference = reference or text
			eq(text, reference, "client " .. i .. " has the same list")
		end
	end)
end)

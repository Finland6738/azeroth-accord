-- Bank snapshot sync (M5.2; SPEC-08 BANK-02, BANK-03, SPEC-02 §6): the newest snapshot per tab, the permissions of the
-- snapshots (GUILD, OFFICER only, nothing to a rank that cannot see them) and the authority rule of the restricted tabs.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function B() return AzerothAccord.Bank end

local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000C0C"

local function tabsA()
	return {
		{ name = "Consumables", icon = 133784, items = { [1] = { itemID = 2589, count = 20 }, [5] = { itemID = 118, count = 3 } } },
		{ name = "Gear", icon = 133785, items = { [2] = { itemID = 2092, count = 1 } } },
	}
end

local function tabsB()   -- what a second visit saw: tab 1 changed, tab 2 not
	local t = tabsA()
	t[1].items[7] = { itemID = 4306, count = 40 }
	return t
end

local function openVault(client, tabs, money)
	local bank = client.Mock.bank
	bank.tabs, bank.money = tabs, money or 5000
	bank.Open()
end

local function closeVault(client) client.Mock.bank.Close() end

local function tab(client, n)
	return client:addon().Bank:Snapshot(n)
end

local function bankRecords(client)
	local n = 0
	for _ in pairs(client:addon().Store:Records("bank")) do n = n + 1 end
	return n
end

describe("who may see a snapshot (store, one client)", function()
	before_boot(function()
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
			{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
		} }
	end)

	local function put(author, tab, rank, extra, time)
		local id = author .. ":t" .. tab
		local rec = { id = id, author = author, rev = 1, time = time or GetServerTime(), kind = "tab", tab = tab, name = "Tab " .. tab,
			rank = rank, it = "1.2589.20", n = 1 }
		for k, v in pairs(extra or {}) do rec[k] = v end
		S():Records("bank")[id] = rec
		return rec
	end

	it("a member sees the snapshots of its own rank and above, not of a rank above it", function()
		put(BOB, 1, 3)       -- read by a rank 3 member: rank 3 may see it
		put(OFF, 2, 2)       -- read by a rank 2: rank 3 may not
		local tabs = B():Tabs()
		eq(#tabs, 1); eq(tabs[1].tab, 1)
		isNil(B():Snapshot(2))
	end)

	it("a snapshot that does not say its rank, or one for officers only, is not for a member", function()
		put(BOB, 1, nil, { rank = nil })
		put(OFF, 2, 1, { restricted = true })
		eq(#B():Tabs(), 0)
	end)

	it("an officer sees everything, a restricted snapshot included", function()
		Mock.guild.Set{ name = "Accord", myRank = 1, members = { { name = "Bob", rank = 3, guid = BOB } } }
		A().Role:Refresh()
		put(BOB, 1, 3); put(OFF, 2, 1, { restricted = true }); put(BOB, 3, nil, { rank = nil })
		eq(#B():Tabs(), 3)
	end)

	it("the newest snapshot wins for each tab, with who saw it and when", function()
		local now = GetServerTime()
		put(BOB, 1, 3, { name = "Old" }, now - 3600)
		put(OFF, 1, 3, { name = "New" }, now - 60)
		local t = B():Snapshot(1)
		eq(t.name, "New"); eq(t.author, OFF); eq(t.authorName, "Boss"); eq(t.time, now - 60); falsy(t.mine)
		put(BOB, 1, 2, { name = "Hidden" }, now - 10)   -- newer, but read by a rank this member is below
		eq(B():Snapshot(1).name, "New", "a newer snapshot that this rank may not see does not replace the one it may")
	end)

	it("a member's client refuses a restricted record, whoever sends it (authority and restriction)", function()
		local rec = { id = OFF .. ":t1", author = OFF, rev = 1, time = GetServerTime(), kind = "tab", tab = 1, rank = 1, restricted = true,
			it = "1.2589.20", n = 1 }
		local ok, why = S():Accept("bank", rec, { sender = "Boss" })
		falsy(ok); eq(why, "restricted")
		isNil(S():Get("bank", rec.id))
	end)

	it("decodes the items once and gives the money of the newest record", function()
		put(BOB, 1, 3)
		local a = B():Tabs()[1].items
		eq(B():Tabs()[1].items, a, "the same table until the record changes")
		S():Records("bank")[BOB .. ":money"] = { id = BOB .. ":money", author = BOB, rev = 1, time = GetServerTime() - 100, kind = "money", money = 5 }
		S():Records("bank")[OFF .. ":money"] = { id = OFF .. ":money", author = OFF, rev = 1, time = GetServerTime() - 10, kind = "money", money = 9 }
		eq(B():Money().money, 9)
	end)
end)

describe("snapshots in the network simulator", function()
	it("a member's snapshot reaches everybody, and the newest per tab wins", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, seed = 51 }
		sim:advance(40)
		openVault(sim:client(3), tabsA(), 1000)
		sim:advance(20)
		closeVault(sim:client(3))
		sim:advance(40)
		for i = 1, 5 do
			local t = tab(sim:client(i), 1)
			notNil(t, "client " .. i .. " has tab 1")
			eq(t.author, Sim.guidOf(3)); eq(#t.items, 2); eq(t.name, "Consumables")
			eq(tab(sim:client(i), 2).items[1].itemID, 2092)
			eq(sim:client(i):addon().Bank:Money().money, 1000)
		end
		sim:advance(900)   -- a quarter of an hour later another member sees a different tab 1
		openVault(sim:client(4), tabsB(), 2000)
		sim:advance(20)
		closeVault(sim:client(4))
		sim:advance(60)
		for i = 1, 5 do
			local t1, t2 = tab(sim:client(i), 1), tab(sim:client(i), 2)
			eq(t1.author, Sim.guidOf(4), "client " .. i .. ": the newest tab 1"); eq(#t1.items, 3)
			eq(t2.author, Sim.guidOf(4), "tab 2 was read again too: the newest wins")
			eq(sim:client(i):addon().Bank:Money().money, 2000)
		end
	end)

	it("a client that logs in later gets the snapshots from an officer", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, offline = { 5 }, seed = 53 }
		sim:advance(40)
		openVault(sim:client(3), tabsA())
		sim:advance(20)
		closeVault(sim:client(3))
		sim:advance(60)
		isNil(sim:client(5):addon() and tab(sim:client(5), 1) or nil)
		sim:client(3):logout()
		sim:client(5):login()
		local ok = sim:advanceUntil(function() return tab(sim:client(5), 1) ~= nil end, 300)
		truthy(ok, "the officers relay the snapshot of a member who is gone")
		eq(tab(sim:client(5), 1).authorName, Sim.nameOf(3))
	end)

	it("a snapshot read by an officer goes on OFFICER only: members never hold it", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, seed = 55 }
		sim:advance(40)
		sim:resetStats()
		openVault(sim:client(1), tabsA())
		sim:advance(20)
		closeVault(sim:client(1))
		sim:advance(60)
		truthy(tab(sim:client(1), 1).restricted, "the reader keeps it")
		local second = tab(sim:client(2), 1)
		notNil(second, "the other officer has it")
		truthy(second.restricted); eq(#second.items, 2)
		for i = 3, 5 do
			eq(bankRecords(sim:client(i)), 1, "client " .. i .. " holds nothing of the officer's tabs, only the money")
			isNil(tab(sim:client(i), 1))
			eq(sim:client(i):addon().Store.stats.rejected, 0, "and was never even sent one")
		end
		truthy(sim:stats().byDist.OFFICER.msgs > 0)
	end)

	it("an officer who logs in later receives the restricted snapshot with the officers' summary", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, offline = { 2 }, seed = 57 }
		sim:advance(40)
		openVault(sim:client(1), tabsA())
		sim:advance(20)
		closeVault(sim:client(1))
		sim:advance(40)
		sim:client(2):login()
		local ok = sim:advanceUntil(function() return tab(sim:client(2), 1) ~= nil end, 400)
		truthy(ok, "pushed by officer 1 after its OHELLO")
		truthy(tab(sim:client(2), 1).restricted)
		isNil(tab(sim:client(3), 1)); isNil(tab(sim:client(4), 1))
	end)

	it("the restricted records are in no GUILD summary: members and officers agree, and nothing is pushed over and over", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, seed = 59 }
		sim:advance(40)
		openVault(sim:client(1), tabsA())
		sim:advance(20)
		closeVault(sim:client(1))
		sim:advance(120)
		sim:resetStats()
		sim:advance(3600)
		local st = sim:stats()
		truthy(st.sent.bytes / 4 / 60 < 150, "an hour of quiet: " .. (st.sent.bytes / 4 / 60) .. " B/min per client")
	end)

	it("with no addon messages on OFFICER the restricted snapshot stays with its reader (never a GUILD or WHISPER fallback)", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, seed = 61, officerChannel = false }
		sim:advance(40)
		openVault(sim:client(1), tabsA())
		sim:advance(20)
		closeVault(sim:client(1))
		sim:advance(200)
		notNil(tab(sim:client(1), 1))
		for i = 2, 4 do isNil(tab(sim:client(i), 1), "client " .. i) end
	end)

	it("a member cannot forge a restricted snapshot in an officer's name: officers and members refuse it", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, seed = 63 }
		sim:advance(40)
		local forged = { id = Sim.guidOf(1) .. ":t1", author = Sim.guidOf(1), rev = 1, time = 1767225600 + 30, kind = "tab", tab = 1,
			rank = 1, restricted = true, it = "1.2589.20", n = 1, name = "Fake" }
		sim:client(3):addon().Transport:Send("GUILD", { t = "REC", s = "bank", r = { forged } })
		sim:advance(20)
		for _, i in ipairs({ 1, 2, 4 }) do
			isNil(sim:client(i):addon().Store:Get("bank", forged.id), "client " .. i)
		end
		truthy((sim:client(2):addon().Store.stats.reasons.authority or 0) > 0, "an officer refused it: the sender is no officer")
		truthy((sim:client(4):addon().Store.stats.reasons.restricted or 0) > 0, "a member refused it as restricted")
	end)

	it("a member's snapshot forged in somebody else's id is refused", function()
		local sim = Sim.new{ clients = 3, officers = { 1 }, seed = 65 }
		sim:advance(40)
		local forged = { id = Sim.guidOf(2) .. ":t1", author = Sim.guidOf(2), rev = 1, time = 1767225600 + 30, kind = "tab", tab = 1,
			rank = 3, it = "1.2589.20", n = 1, name = "Fake" }
		sim:client(3):addon().Transport:Send("GUILD", { t = "REC", s = "bank", r = { forged } })
		sim:advance(20)
		isNil(sim:client(1):addon().Store:Get("bank", forged.id), "only the author (or an officer) may pass a record on")
	end)
end)

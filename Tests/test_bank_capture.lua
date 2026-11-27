-- Bank capture (M5.1; SPEC-08 BANK-01, ADR 0009): the vault is read tab by tab, one query at a time with a pause, and the
-- snapshots and the money are published as records of the set `bank`.
local function B() return AzerothAccord.Bank end
local function S() return AzerothAccord.Store end
local function C() return AzerothAccord.Compat end

local ME, BOB = "Player-1-0000A001", "Player-1-00000B0B"

local function tabs()
	return {
		{ name = "Consumables", icon = 133784, items = { [1] = { itemID = 2589, count = 20 }, [5] = { itemID = 118, count = 3 } } },
		{ name = "Gear", icon = 133785, items = { [2] = { itemID = 2092, count = 1 } } },
		{ name = "Officers", icon = 133786, viewable = false, items = { [1] = { itemID = 6948, count = 1 } } },
	}
end

local function vault(rank, money)
	Mock.guild.Set{ name = "Accord", myRank = rank or 4, members = {} }
	Mock.bank.tabs = tabs()
	Mock.bank.money = money or 123456
end

local function tabRecord(n) return S():Get("bank", ME .. ":t" .. n) end

local function open(seconds)
	Mock.bank.Open()
	Mock.Advance(seconds or 30)
end

describe("the items text", function()
	it("round-trips slots, ids, counts and variants", function()
		local items = { { slot = 5, itemID = 118, count = 3 }, { slot = 1, itemID = 2589, count = 20, variant = "0_0_0_0_0_123" } }
		local text = B().EncodeItems(items)
		eq(text, "1.2589.20.0_0_0_0_0_123,5.118.3")
		local back = B().DecodeItems(text)
		eq(#back, 2); eq(back[1].slot, 1); eq(back[1].variant, "0_0_0_0_0_123"); eq(back[2].count, 3); isNil(back[2].variant)
		deepEq(B().DecodeItems(""), {})
	end)

	it("keeps only what tells two items of one kind apart", function()
		eq(B().Variant("|cffffffff|Hitem:2589::::::::60:::::|h[Linen]|h|r"), nil)
		eq(B().Variant("|cff1eff00|Hitem:3000:2564:0:0:0:0:-12:99:60:::::|h[Sword of the Bear]|h|r"), "2564_0_0_0_0_-12")
		eq(B().Variant("|cff1eff00|Hitem:3000:0:0:0:0:0:0:99:60:::::|h[Plain]|h|r"), nil, "the unique id and the level are not variants")
		eq(B().Variant("|Hitem:3000:x:::::|h"), nil, "not numbers")
		eq(B().Variant("item:2589"), nil)
		eq(B().Variant(nil), nil)
	end)

	it("refuses a text that is not a list of items, never raising", function()
		eq(select(2, B().DecodeItems(42)), "shape")
		eq(select(2, B().DecodeItems(("1.2.3,"):rep(2000))), "size")
		eq(select(2, B().DecodeItems("1.2")), "item")
		eq(select(2, B().DecodeItems("1.2.3;4.5.6")), "item")
		eq(select(2, B().DecodeItems("0.2.3")), "slot")
		eq(select(2, B().DecodeItems("99.2.3")), "slot")
		eq(select(2, B().DecodeItems("4.2.3,4.5.6")), "slot", "a slot once")
		eq(select(2, B().DecodeItems("4.0.3")), "count")
		eq(select(2, B().DecodeItems("4.2.0")), "count")
	end)
end)

describe("the capture at the vault", function()
	before_boot(function() vault(4) end)

	it("reads every viewable tab and the money, and publishes one record each", function()
		open()
		local t1, t2 = tabRecord(1), tabRecord(2)
		notNil(t1); notNil(t2)
		eq(t1.kind, "tab"); eq(t1.tab, 1); eq(t1.name, "Consumables"); eq(t1.icon, 133784); eq(t1.n, 2); eq(t1.rank, 4)
		eq(t1.it, "1.2589.20,5.118.3")
		eq(t2.it, "2.2092.1")
		isNil(t1.restricted, "a member's snapshot is not restricted")
		isNil(tabRecord(3), "a tab this rank cannot view is not read")
		local money = S():Get("bank", ME .. ":money")
		eq(money.kind, "money"); eq(money.money, 123456)
		eq(t1.author, ME)
	end)

	it("reads the vault when the client opens it through the interaction manager (WoW Forever, 2026-11-27)", function()
		Mock.bank.viaInteraction = true
		open()
		Mock.bank.Close()
		Mock.bank.viaInteraction = nil
		notNil(tabRecord(1), "the capture ran")
		notNil(S():Get("bank", ME .. ":money"))
		contains(table.concat(B():DebugLines(), " "), "opened by interaction")
		Mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)   -- another interaction (a merchant) is not the vault
		falsy(B():DebugLines()[1]:find("vault open", 1, true))
	end)

	it("asks for one tab at a time, a pause apart", function()
		local at = {}
		local original = QueryGuildBankTab
		QueryGuildBankTab = function(tab) at[#at + 1] = { tab = tab, t = GetTime() } return original(tab) end
		open()
		eq(#at, 2)
		eq(at[1].tab, 1); eq(at[2].tab, 2)
		truthy(at[2].t - at[1].t >= B().PAUSE - 0.01, "pause of " .. (at[2].t - at[1].t))
	end)

	it("the permissions of the rank are kept for the view", function()
		open()
		local p = B():Permissions()
		truthy(p[1].viewable); truthy(p[2].viewable); falsy(p[3].viewable)
		eq(p[1].name, "Consumables")
	end)

	it("a snapshot of an officer is restricted: officers only", function()
		Mock.guild.Set{ name = "Accord", myRank = 1, members = {} }
		AzerothAccord.Role:Refresh()
		open()
		eq(tabRecord(1).restricted, true)
		eq(tabRecord(1).rank, 1)
		isNil(S():Get("bank", ME .. ":money").restricted, "the money is not restricted")
	end)

	it("an unchanged tab is published again only after the pause, a changed one at once", function()
		open()
		local rev = tabRecord(1).rev
		Mock.bank.Close(); Mock.Advance(1)
		open()
		eq(tabRecord(1).rev, rev, "the same content, a minute later: nothing new")
		Mock.bank.Close(); Mock.Advance(B().REPUBLISH)
		open()
		eq(tabRecord(1).rev, rev + 1, "an old snapshot is renewed")
		local rev2 = tabRecord(1).rev
		Mock.bank.Close(); Mock.Advance(1)
		Mock.bank.tabs[1].items[7] = { itemID = 4306, count = 40 }
		open()
		eq(tabRecord(1).rev, rev2 + 1, "a changed tab goes out at once")
		eq(tabRecord(1).n, 3)
	end)

	it("closing the vault in the middle stops the capture: later tabs are not read", function()
		Mock.bank.Open()
		Mock.Advance(0.3)
		Mock.bank.Close()
		Mock.Advance(30)
		isNil(tabRecord(2))
		truthy(B():IsOpen() == false)
	end)

	it("an empty tab is published once the vault has delivered data", function()
		Mock.bank.tabs[2].items = {}
		open()
		notNil(tabRecord(2)); eq(tabRecord(2).n, 0); eq(tabRecord(2).it, "")
	end)

	it("a vault that delivers nothing publishes nothing, and a late answer is read at the timeout", function()
		local original = QueryGuildBankTab
		QueryGuildBankTab = function() end   -- no event at all
		Mock.bank.tabs[2].items = {}
		open(40)
		notNil(tabRecord(1), "a tab with items is read at the timeout")
		isNil(tabRecord(2))
		eq(B().state.stats.unreadable >= 1, true)
		QueryGuildBankTab = original
	end)

	it("does nothing when the guild bank is switched off, and says so", function()
		Mock.bank.enabled = false
		open()
		isNil(tabRecord(1))
		contains(table.concat(AzerothAccord.Bank:DebugLines(), "\n"), "off")
	end)

	it("waits for the tab count when the vault has not told it yet", function()
		local real = GetNumGuildBankTabs
		local calls = 0
		GetNumGuildBankTabs = function() calls = calls + 1 if calls < 3 then return 0 end return real() end
		open()
		notNil(tabRecord(1))
		GetNumGuildBankTabs = real
	end)

	it("makes the bank tab feature available once a tab was read", function()
		eq(C():Feature("bankTabs"), "unknown")
		open()
		eq(C():Feature("bankTabs"), "available")
	end)

	it("the money alone is published when it changes at the open vault", function()
		open()
		local rev = S():Get("bank", ME .. ":money").rev
		Mock.bank.money = 999
		Mock.Fire("GUILDBANK_UPDATE_MONEY")
		eq(S():Get("bank", ME .. ":money").money, 999)
		eq(S():Get("bank", ME .. ":money").rev, rev + 1)
	end)

	it("emits BANK_CAPTURED and /accord debug tells the outcome", function()
		local seen = 0
		AzerothAccord.Bus:On("BANK_CAPTURED", function() seen = seen + 1 end)
		open()
		eq(seen, 1)
		contains(table.concat(B():DebugLines(), "\n"), "captured")
	end)
end)

describe("the shape of a bank record (store rules)", function()
	before_boot(function() vault(4) end)

	local function rec(fields)
		local r = { id = ME .. ":t1", author = ME, rev = 1, time = GetServerTime(), kind = "tab", tab = 1, name = "Consumables",
			rank = 4, it = "1.2589.20", n = 1 }
		for k, v in pairs(fields or {}) do r[k] = v end
		return r
	end

	it("accepts a well-formed record and refuses what the owner rule forbids", function()
		truthy(B().ValidRecord(rec()))
		falsy(B().ValidRecord(rec({ id = BOB .. ":t1" })), "somebody else's id")
		falsy(B().ValidRecord(rec({ tab = 0 })))
		falsy(B().ValidRecord(rec({ tab = 9, id = ME .. ":t9" })))
		falsy(B().ValidRecord(rec({ it = "garbage" })))
		falsy(B().ValidRecord(rec({ it = 5 })))
		falsy(B().ValidRecord(rec({ name = ("x"):rep(80) })))
		falsy(B().ValidRecord(rec({ restricted = "yes" })))
		falsy(B().ValidRecord(rec({ kind = "other" })))
		falsy(B().ValidRecord(rec({ n = 200 })))
		truthy(B().ValidRecord({ id = ME .. ":money", author = ME, kind = "money", money = 5 }))
		falsy(B().ValidRecord({ id = ME .. ":money", author = ME, kind = "money", money = -5 }))
		falsy(B().ValidRecord(nil))
	end)

	it("the store keeps a snapshot for 90 days", function()
		local r = rec()
		local t = GetServerTime()
		falsy(S().SETS.bank.expires(r, t))
		r.time = t - 91 * 86400
		truthy(S().SETS.bank.expires(r, t))
	end)
end)

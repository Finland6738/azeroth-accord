-- The Bank view (M5.3; SPEC-08 BANK-04, BANK-03): the tabs as the game draws them (14 x 7 slots), the guild money, the age of
-- each tab and who read it, the list of items with totals, the search, and what a rank may see.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function V() return AzerothAccord.BankView end

local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000C0C"
local LINEN, POTION, SWORD = 2589, 118, 3000

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function names()
	Mock.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
	Mock.items.info[POTION] = { name = "Minor Healing Potion", quality = 1, icon = 134830 }
	Mock.items.info[SWORD] = { name = "Sword of the Bear", quality = 4, icon = 135274 }
	for id in pairs(Mock.items.info) do Mock.items.cached[id] = true end   -- loaded already (the client's cache)
end

local function put(author, tab, items, extra, age)
	local id = author .. ":t" .. tab
	local rec = { id = id, author = author, rev = 1, time = GetServerTime() - (age or 0), kind = "tab", tab = tab, name = "Tab " .. tab,
		rank = 3, it = A().Bank.EncodeItems(items), n = #items }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("bank")[id] = rec
	A().Bus:Emit("STORE_CHANGED", "bank", id, "remote")
	return rec
end

local function money(author, copper, age)
	local id = author .. ":money"
	S():Records("bank")[id] = { id = id, author = author, rev = 1, time = GetServerTime() - (age or 0), kind = "money", money = copper }
	A().Bus:Emit("STORE_CHANGED", "bank", id, "remote")
end

local function world()
	names()
	put(BOB, 1, { { slot = 1, itemID = LINEN, count = 20 }, { slot = 5, itemID = POTION, count = 3 }, { slot = 98, itemID = SWORD, count = 1, variant = "2564" } },
		{ name = "Consumables" }, 7200)
	put(BOB, 2, { { slot = 3, itemID = LINEN, count = 40 } }, { name = "Cloth" }, 60)
	money(BOB, 123456, 7200)
end

describe("the text helpers", function()
	before_boot(function() guild() end)

	it("writes money as gold, silver and copper", function()
		eq(V().MoneyText(123456), "12g 34s 56c")
		eq(V().MoneyText(100), "1s")
		eq(V().MoneyText(0), "0c")
		eq(V().MoneyText(10000), "1g")
		eq(V().MoneyText(nil), "?")
	end)

	it("says how old a snapshot is and who read it", function()
		world()
		local t = A().Bank:Snapshot(1)
		eq(V().SeenText(t), "seen 2 h ago by Bob")
		eq(V().SeenText({ time = GetServerTime() - 30 }), "seen just now")
		eq(V().SeenText(nil), "")
	end)

	it("writes the item link of a variant for the tooltip", function()
		eq(V().Hyperlink(3000), "item:3000")
		eq(V().Hyperlink(3000, "2564_0_0_0_0_-12"), "item:3000:2564:0:0:0:0:-12")
		isNil(V().Hyperlink(nil))
	end)

	it("lays the items in 98 slots", function()
		world()
		local slots = V().SlotGrid(A().Bank:Snapshot(1))
		eq(slots[1].itemID, LINEN); eq(slots[98].variant, "2564"); isNil(slots[2])
		deepEq(V().SlotGrid(nil), {})
	end)
end)

describe("the list of items", function()
	before_boot(function() guild() end)

	it("one row per item over the tabs, with its total and where it is", function()
		world()
		local rows = V().ItemRows()
		eq(#rows, 3)
		eq(rows[1].name, "Linen Cloth"); eq(rows[1].total, 60)
		eq(#rows[1].tabs, 2); eq(rows[1].tabs[1].count, 20); eq(rows[1].tabs[2].count, 40)
		eq(rows[2].name, "Minor Healing Potion"); eq(rows[3].name, "Sword of the Bear")
		eq(V().TabsText(rows[1]), "Consumables x20, Cloth x40")
	end)

	it("sorts by total when asked", function()
		world()
		local rows = V().ItemRows({ sort = "total" })
		eq(rows[1].itemID, LINEN); eq(rows[2].itemID, POTION); eq(rows[3].itemID, SWORD)
	end)

	it("the search finds a name, an item number or a tab name", function()
		world()
		eq(#V().ItemRows({ search = "sword" }), 1)
		eq(V().ItemRows({ search = "HEAL" })[1].itemID, POTION)
		eq(V().ItemRows({ search = "118" })[1].itemID, POTION)
		eq(#V().ItemRows({ search = "cloth" }), 1, "the item 'Linen Cloth' and the tab 'Cloth' both lead to the linen")
		eq(#V().ItemRows({ search = "consum" }), 3, "a tab name finds every item in the tab")
		eq(#V().ItemRows({ search = "zzz" }), 0)
	end)

	it("an item the client has not loaded is asked for once and listed last until it arrives", function()
		world()
		Mock.items.cached[POTION] = nil
		local rows = V().ItemRows()
		eq(rows[3].itemID, POTION); isNil(rows[3].name)
		V().ItemRows(); V().ItemRows()
		local n = 0
		for _, id in ipairs(Mock.items.requests) do if id == POTION then n = n + 1 end end
		eq(n, 1, "asked once")
	end)

	it("shows only the tabs this rank may see", function()
		world()
		put(OFF, 3, { { slot = 1, itemID = SWORD, count = 1 } }, { name = "Officers", rank = 1, restricted = true })
		put(OFF, 4, { { slot = 1, itemID = SWORD, count = 1 } }, { name = "Raiders", rank = 2 })
		for _, row in ipairs(V().ItemRows()) do
			for _, t in ipairs(row.tabs) do truthy(t.tab == 1 or t.tab == 2, "tab " .. t.tab .. " is above this rank") end
		end
	end)
end)

describe("the view", function()
	before_boot(function() guild() end)

	local function open()
		world()
		Mock.Slash("/accord bank")
		Mock.Advance(1)
	end

	local function shown(frames)
		local out = {}
		for _, f in ipairs(frames) do if f:IsShown() then out[#out + 1] = f end end
		return out
	end

	it("says there is no data yet, and why", function()
		Mock.Slash("/accord bank")
		Mock.Advance(1)
		local f = V().modes.tabs.frame
		contains(f.message:GetText(), "No bank data yet")
		truthy(f.message:IsShown())
	end)

	it("opens with /accord bank on the first tab: a button per tab, the money and the age, the slots with icons and counts", function()
		open()
		local f = V().modes.tabs.frame
		local buttons = shown(f.bar.buttons)
		eq(#buttons, 2)
		eq(buttons[1]:GetText(), "> Consumables <"); eq(buttons[2]:GetText(), "Cloth")
		contains(f.info:GetText(), "Guild money: 12g 34s 56c (seen 2 h ago by Bob)")
		contains(f.info:GetText(), "This tab: seen 2 h ago by Bob, 3 item(s)")
		local slots = f.grid.slots
		eq(#slots, 98)
		eq(slots[1].count:GetText(), "20"); eq(slots[1].icon:GetTexture(), 132889); truthy(slots[1].icon:IsShown())
		eq(slots[5].count:GetText(), "3")
		eq(slots[98].count:GetText(), "", "one item shows no count"); truthy(slots[98].icon:IsShown())
		falsy(slots[2].icon:IsShown())
	end)

	it("a click on a tab button shows that tab, a tooltip shows the item", function()
		open()
		local f = V().modes.tabs.frame
		f.bar.buttons[2]:Click()
		eq(f.bar.buttons[2]:GetText(), "> Cloth <")
		eq(f.grid.slots[3].count:GetText(), "40"); falsy(f.grid.slots[1].icon:IsShown())
		f.bar.buttons[1]:Click()
		local seen
		GameTooltip.SetHyperlink = function(_, link) seen = link end
		f.grid.slots[98]:GetScript("OnEnter")(f.grid.slots[98])
		eq(seen, "item:3000:2564")
		GameTooltip.SetHyperlink = nil
	end)

	it("the Items mode lists the items and the search box filters them", function()
		open()
		V():SetMode("items")
		local f = V().modes.items.frame
		local rows = shown(f.area.rows)
		eq(#rows, 3)
		eq(rows[1].name:GetText(), "Linen Cloth"); eq(rows[1].total:GetText(), "60")
		contains(rows[1].where:GetText(), "Consumables x20")
		AzerothAccord.Shell:OnSearch("sword")
		eq(#shown(f.area.rows), 1)
		eq(shown(f.area.rows)[1].name:GetText(), "Sword of the Bear")
		AzerothAccord.Shell:OnSearch("nothing here")
		truthy(f.message:IsShown()); contains(f.message:GetText(), "No item or tab matches")
	end)

	it("a search typed in the Tabs mode moves to the list", function()
		open()
		AzerothAccord.Shell:OnSearch("potion")
		eq(V().mode, "items")
	end)

	it("an item name that arrives later fills its row in", function()
		world()
		Mock.items.cached[POTION] = nil
		Mock.Slash("/accord bank")
		V():SetMode("items")
		local f = V().modes.items.frame
		local names = {}
		for _, r in ipairs(shown(f.area.rows)) do names[#names + 1] = r.name:GetText() end
		contains(table.concat(names, "|"), "loading")
		Mock.Advance(2)
		names = {}
		for _, r in ipairs(shown(f.area.rows)) do names[#names + 1] = r.name:GetText() end
		contains(table.concat(names, "|"), "Minor Healing Potion")
	end)

	it("redraws when a snapshot arrives, and hides a tab that a rank may not see", function()
		open()
		put(OFF, 3, { { slot = 1, itemID = SWORD, count = 1 } }, { name = "Officers", rank = 1 })
		Mock.Advance(1)
		eq(#shown(V().modes.tabs.frame.bar.buttons), 2, "rank 1 only: not for this member")
		put(BOB, 4, { { slot = 1, itemID = SWORD, count = 1 } }, { name = "Newest" })
		Mock.Advance(1)
		eq(#shown(V().modes.tabs.frame.bar.buttons), 3)
	end)

	it("an officer sees the restricted tabs too", function()
		Mock.guild.Set{ name = "Accord", myRank = 1, members = { { name = "Bob", rank = 3, guid = BOB } } }
		A().Role:Refresh()
		world()
		put(OFF, 3, { { slot = 1, itemID = SWORD, count = 1 } }, { name = "Officers", rank = 1, restricted = true })
		Mock.Slash("/accord bank")
		Mock.Advance(1)
		eq(#shown(V().modes.tabs.frame.bar.buttons), 3)
	end)
end)

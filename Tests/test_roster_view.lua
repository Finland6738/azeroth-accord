-- The Roster view (M2.3; SPEC-05 §1, SPEC-04 §2): the frames that draw the model's rows. Virtual rows for 1000 members,
-- clickable headers, the toolbar, the column menu, selection and the choices that survive a /reload.
local function A() return AzerothAccord end
local function V() return A().RosterView end
local function Shell() return A().Shell end

local function members(n)
	local list = {}
	for i = 1, n do
		list[i] = { name = "M" .. ("%04d"):format(i), level = 1 + i % 60, class = (i % 2 == 0) and "MAGE" or "WARRIOR", rank = 2 + i % 3,
			online = i % 5 == 0, guid = ("Player-1-%08X"):format(0x5000 + i), lastOnline = { 0, 0, i % 20, 0 }, zone = "Zone" .. i % 7 }
	end
	return list
end

local function open(n)
	Mock.guild.Set{ name = "Accord", myRank = 3, members = members(n or 30) }
	Mock.Slash("/accord roster")
	return V()
end

local function Widgets_menuOpen() return AzerothAccord.Widgets.MenuIsOpen() end

local function nameAt(i)
	local row = V().frame.area.rows[i]
	return row and row:IsShown() and row.cells[1]:GetText() or nil
end

local function shownRows()
	local n = 0
	for _, row in ipairs(V().frame.area.rows) do if row:IsShown() then n = n + 1 end end
	return n
end

describe("the view", function()
	it("registers as the first view, opens with /accord roster and is built when first shown", function()
		notNil(Shell().views.roster)
		eq(Shell().views.roster.label, "Roster")
		eq(Shell().views.roster.order, 10)
		truthy(Shell().views.roster.search)
		isNil(V().frame)
		open(10)
		notNil(V().frame)
		truthy(V().frame:IsShown())
	end)

	it("draws the header titles of the visible columns and the count", function()
		open(10)
		local titles = {}
		for _, b in ipairs(V().frame.header.buttons) do if b:IsShown() then titles[#titles + 1] = b.label:GetText() end end
		eq(titles[1], "Name ^")
		eq(titles[2], "Lvl")
		eq(#titles, 11)
		eq(V().frame.toolbar.count:GetText(), "11 of 11 members")
	end)

	it("fills a row with the cells of the member", function()
		open(10)
		local row
		for _, r in ipairs(V().frame.area.rows) do if r:IsShown() and r.cells[1]:GetText() == "M0005" then row = r end end
		notNil(row)
		eq(row.cells[2]:GetText(), "6")
		eq(row.cells[3]:GetText(), "Warrior")
		eq(row.cells[6]:GetText(), "Online")
	end)

	it("asks for a fresh roster when shown and watches while visible", function()
		open(10)
		eq(A().Roster.state.watchers, 1)
		A().Window:Close()
		eq(A().Roster.state.watchers, 0)
	end)

	it("says so when the roster is empty or nothing matches", function()
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {} }
		Mock.Slash("/accord roster")
		falsy(V().frame.empty:IsShown() and V().frame.empty:GetText() == "")
		V():SetSearch("zzz")
		eq(V().frame.empty:GetText(), "No member matches the search and the filters.")
		truthy(V().frame.empty:IsShown())
	end)
end)

describe("headers and the toolbar", function()
	it("a click on a header sorts, a second click reverses, and the choice is saved", function()
		open(30)
		local level
		for _, b in ipairs(V().frame.header.buttons) do if b.columnId == "level" then level = b end end
		level:Click()
		eq(V():Model().sort.key, "level")
		eq(V():Model().sort.desc, false)
		level:Click()
		truthy(V():Model().sort.desc)
		eq(level.label:GetText(), "Lvl v")
		eq(A().Config:Get("char.ui.sort").key, "level")
		eq(nameAt(1), "Testchar")   -- level 60, the highest
	end)

	it("the search box of the panel filters the rows", function()
		open(30)
		local bar = Shell().content.bar
		Mock.TypeInto(bar.search, "M0007")
		eq(shownRows(), 1)
		eq(nameAt(1), "M0007")
		Mock.TypeInto(bar.search, "")
		eq(V().frame.toolbar.count:GetText(), "31 of 31 members")
	end)

	it("Online, Mains only and By account act on the model", function()
		open(30)
		local bar = V().frame.toolbar
		bar.online:Click()
		truthy(V():Model().filters.online)
		eq(V().frame.toolbar.count:GetText(), "7 of 31 members")
		bar.online:Click()
		falsy(V():Model().filters.online)
		bar.mains:Click()
		truthy(V():Model().filters.mains)
		bar.grouped:Click()
		truthy(V():Model().grouped)
		truthy(A().Config:Get("char.ui.grouped") == false, "grouping is saved by the model, not by the checkbox")
	end)

	it("the class menu lists the classes of the guild and filters by the chosen one", function()
		open(30)
		V().frame.toolbar.class:Click()
		truthy(Widgets_menuOpen())
		local items = A().Widgets.menu.items
		eq(items[1].text, "All classes")
		eq(items[2].text, "Mage"); eq(items[3].text, "Warrior")
		A().Widgets.menu.rows[2]:Click()
		eq(V():Model().filters.class, "MAGE")
		eq(shownRows(), 15)
		falsy(Widgets_menuOpen())
	end)

	it("the column menu keeps open while columns are toggled and saves the choice", function()
		open(30)
		V().frame.toolbar.columns:Click()
		local items = A().Widgets.menu.items
		local zone
		for i, it in ipairs(items) do if it.text == "Zone" then zone = i end end
		notNil(zone)
		A().Widgets.menu.rows[zone]:Click()
		truthy(Widgets_menuOpen())
		falsy(V():Model():HasColumn("zone"))
		local titles = 0
		for _, b in ipairs(V().frame.header.buttons) do if b:IsShown() then titles = titles + 1 end end
		eq(titles, 10)
		deepEq(A().Config:Get("char.ui.columns")[1], "name")
		A().Widgets.menu.rows[#items]:Click()   -- default columns
		truthy(V():Model():HasColumn("zone"))
	end)
end)

describe("virtual rows", function()
	it("never creates more row frames than the table is tall, however big the guild", function()
		open(999)
		eq(#V().frame.area.rows, V().DEFAULT_ROWS + 1)
		eq(V().frame.toolbar.count:GetText(), "1000 of 1000 members")
		eq(nameAt(1), "M0001")
	end)

	it("the wheel scrolls by rows and stops at both ends; the same frames show other members", function()
		open(999)
		local before = V().frame.area.rows[1]
		Mock.RunScript(V().frame.area, "OnMouseWheel", -1)
		eq(V().offset, 3)
		eq(nameAt(1), "M0004")
		eq(V().frame.area.rows[1], before)
		Mock.RunScript(V().frame.area, "OnMouseWheel", 1)
		Mock.RunScript(V().frame.area, "OnMouseWheel", 1)
		eq(V().offset, 0)
		V():Scroll(100000)
		eq(V().offset, 1000 - V():VisibleRows())
		eq(#V().frame.area.rows, V().DEFAULT_ROWS + 1)
	end)

	it("shows the scroll thumb only when the table is longer than the window", function()
		open(5)
		falsy(V().frame.track.thumb:IsShown())
		open(100)
		Mock.Advance(2)   -- the roster rebuilds a second after the change
		truthy(V().frame.track.thumb:IsShown())
	end)

	it("a new search or a changed roster clamps the scroll position", function()
		open(100)
		V():Scroll(60)
		truthy(V().offset > 0)
		V():SetSearch("M0003")
		eq(V().offset, 0)
		eq(shownRows(), 1)
	end)
end)

describe("selection", function()
	it("a click selects the member, highlights the row and tells the Bus", function()
		open(10)
		local got
		A().Bus:On("ROSTER_SELECT", function(guid, entry) got = { guid, entry.name } end)
		V().frame.area.rows[3]:Click()
		deepEq(got, { V().frame.area.rows[3].data.entry.guid, "M0003" })
		truthy(V().frame.area.rows[3].selected:IsShown())
		falsy(V().frame.area.rows[2].selected:IsShown())
	end)
end)

describe("the grouped view", function()
	local BOB, BOBALT = "Player-1-00000B0B", "Player-1-00000B0C"

	local function twoAlts()
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB }, { name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT } } }
		local S = A().Store
		for guid, other in pairs({ [BOB] = BOBALT, [BOBALT] = BOB }) do
			S:Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T",
				chars = { { guid = guid, name = "x" }, { guid = other, name = "y" } } }
		end
		A().Roster:MarkDirty(); A().Accounts:MarkDirty()
		Mock.Slash("/accord roster")
	end

	it("shows an account as one row with a + button that reveals the alts", function()
		twoAlts()
		V().frame.toolbar.grouped:Click()
		local rows = V().frame.area.rows
		local bob
		for _, r in ipairs(rows) do if r:IsShown() and r.data.kind == "group" then bob = r end end
		notNil(bob)
		eq(bob.expander.label:GetText(), "+")
		truthy(bob.expander:IsShown())
		bob.expander:Click()
		local texts = {}
		for _, r in ipairs(rows) do if r:IsShown() then texts[#texts + 1] = r.cells[1]:GetText() end end
		deepEq({ texts[1], texts[2] }, { "Bob", "Bobalt" })
		eq(bob.expander.label:GetText(), "-")
	end)

	it("follows the data: a new accounts record changes the rows without reopening", function()
		twoAlts()
		V().frame.toolbar.grouped:Click()
		eq(V().frame.toolbar.count:GetText(), "2 of 3 members")
		A().Store:Records("accounts")[BOBALT] = nil
		A().Accounts:MarkDirty()
		A().Bus:Emit("ACCOUNTS_UPDATED", 0)
		eq(V().frame.toolbar.count:GetText(), "3 of 3 members")
	end)
end)

describe("saved choices", function()
	it("come back after a /reload", function()
		open(30)
		local level
		for _, b in ipairs(V().frame.header.buttons) do if b.columnId == "level" then level = b end end
		level:Click(); level:Click()
		V():Model():ToggleColumn("zone"); V():Model():Save()
		V().frame.toolbar.grouped:Click()
		V():Model():Save()
		Mock.Reload()
		Mock.Slash("/accord roster")
		eq(V():Model().sort.key, "level")
		truthy(V():Model().sort.desc)
		truthy(V():Model().grouped)
		falsy(V():Model():HasColumn("zone"))
	end)

	it("a Lua error never comes out of drawing (the test fails on any recorded error)", function()
		open(40)
		V():Scroll(5)
		V():Select(V().frame.area.rows[1].data)
		eq(#Mock.errors, 0)
	end)
end)

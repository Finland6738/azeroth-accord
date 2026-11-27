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

local function menuOpen() return AzerothAccord.Widgets.Menu.IsOpen() end
local function menu() return AzerothAccord.Widgets.Menu.frame end

local function nameAt(i)
	local row = V().frame.table.rows[i]
	return row and row:IsShown() and row.cells[1]:GetText() or nil
end

local function shownRows()
	local n = 0
	for _, row in ipairs(V().frame.table.rows) do if row:IsShown() then n = n + 1 end end
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
		for _, b in ipairs(V().frame.table.heads) do if b:IsShown() then titles[#titles + 1] = b.label:GetText() end end
		eq(titles[1], "NAME")
		eq(titles[2], "LVL")
		eq(#titles, 11)
		local id, desc = V().frame.table:GetSort()
		eq(id, "name"); eq(desc, false)
		truthy(V().frame.table.heads[1].arrow:IsShown(), "the sorted column has its arrow")
		falsy(V().frame.table.heads[2].arrow:IsShown())
		eq(V().frame.toolbar.count:GetText(), "11 of 11 members")
	end)

	it("fills a row with the cells of the member", function()
		open(10)
		local row
		for _, r in ipairs(V().frame.table.rows) do if r:IsShown() and r.cells[1]:GetText() == "M0005" then row = r end end
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
		falsy(V().frame.table.empty:IsShown() and V().frame.table.empty:GetText() == "")
		V():SetSearch("zzz")
		eq(V().frame.table.empty:GetText(), "No member matches the search and the filters.")
		truthy(V().frame.table.empty:IsShown())
	end)
end)

describe("headers and the toolbar", function()
	it("a click on a header sorts, a second click reverses, and the choice is saved", function()
		open(30)
		local level
		for _, b in ipairs(V().frame.table.heads) do if b.col.id == "level" then level = b end end
		level:Click()
		eq(V():Model().sort.key, "level")
		eq(V():Model().sort.desc, false)
		eq(V().frame.table:GetSort(), "level")
		level:Click()
		truthy(V():Model().sort.desc)
		local id, desc = V().frame.table:GetSort()
		eq(id, "level"); truthy(desc)
		truthy(level.arrow:IsShown())
		falsy(V().frame.table.heads[1].arrow:IsShown(), "the arrow moved with the sort")
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

	it("Online and By account act on the model, By account on by default", function()
		open(30)
		local bar = V().frame.toolbar
		bar.online:Click()
		truthy(V():Model().filters.online)
		eq(V().frame.toolbar.count:GetText(), "7 of 31 members")
		bar.online:Click()
		falsy(V():Model().filters.online)
		isNil(bar.mains)
		truthy(V():Model().grouped)
		bar.grouped:Click()
		falsy(V():Model().grouped)
	end)

	it("the class select lists the classes of the guild and filters by the chosen one", function()
		open(30)
		local sel = V().frame.toolbar.class
		sel:Click()
		truthy(sel:IsOpen())
		local choices = sel.choices
		eq(choices[1].text, "All classes")
		eq(choices[2].text, "Mage"); eq(choices[3].text, "Warrior")
		sel.list.rows[2]:Click()
		eq(V():Model().filters.class, "MAGE")
		eq(V().frame.toolbar.count:GetText(), "15 of 31 members")
		eq(shownRows(), 14, "a page of rows")
		falsy(sel:IsOpen())
		eq(sel.label:GetText(), "Mage")
		sel.list.rows[1]:Click()
		isNil(V():Model().filters.class)
		eq(shownRows(), 14, "back to all: a page of rows")
	end)

	it("the chips show the state of the model, also when it was set elsewhere", function()
		open(30)
		local bar = V().frame.toolbar
		falsy(bar.online:IsSelected())
		V():Model():SetFilter("online", true)
		V():Changed()
		truthy(bar.online:IsSelected())
		V():Model():SetFilter("class", "MAGE")
		V():Changed()
		eq(bar.class:Selected(), "MAGE")
		V():Model():ClearFilters()
		V():Changed()
		falsy(bar.online:IsSelected())
		eq(bar.class:Selected(), "*")
	end)

	it("the column menu keeps open while columns are toggled and saves the choice", function()
		open(30)
		V().frame.toolbar.columns:Click()
		local items = menu().items
		local zone
		for i, it in ipairs(items) do if it.text == "Zone" then zone = i end end
		notNil(zone)
		menu().rows[zone]:Click()
		truthy(menuOpen())
		falsy(V():Model():HasColumn("zone"))
		local titles = 0
		for _, b in ipairs(V().frame.table.heads) do if b:IsShown() then titles = titles + 1 end end
		eq(titles, 10)
		deepEq(A().Config:Get("char.ui.columns")[1], "name")
		menu().rows[#items]:Click()   -- default columns
		truthy(V():Model():HasColumn("zone"))
	end)
end)

describe("virtual rows", function()
	it("never creates more row frames than the table is tall, however big the guild", function()
		open(999)
		eq(#V().frame.table.rows, V().POOL)
		eq(V().frame.toolbar.count:GetText(), "1000 of 1000 members")
		eq(nameAt(1), "M0001")
	end)

	it("the wheel scrolls by rows and stops at both ends; the same frames show other members", function()
		open(999)
		local before = V().frame.table.rows[1]
		Mock.RunScript(V().frame.table.list, "OnMouseWheel", -1)
		eq(V().frame.table.offset, 3)
		eq(nameAt(1), "M0004")
		eq(V().frame.table.rows[1], before)
		Mock.RunScript(V().frame.table.list, "OnMouseWheel", 1)
		Mock.RunScript(V().frame.table.list, "OnMouseWheel", 1)
		eq(V().frame.table.offset, 0)
		V():Scroll(100000)
		eq(V().frame.table.offset, 1000 - V():VisibleRows())
		eq(#V().frame.table.rows, V().POOL)
	end)

	it("shows the scroll thumb only when the table is longer than the window", function()
		open(5)
		falsy(V().frame.table.scroll:IsShown())
		open(100)
		Mock.Advance(2)   -- the roster rebuilds a second after the change
		truthy(V().frame.table.scroll:IsShown())
	end)

	it("a new search or a changed roster clamps the scroll position", function()
		open(100)
		V():Scroll(60)
		truthy(V().frame.table.offset > 0)
		V():SetSearch("M0003")
		eq(V().frame.table.offset, 0)
		eq(shownRows(), 1)
	end)
end)

describe("selection", function()
	it("a click selects the member, highlights the row and tells the Bus", function()
		open(10)
		local got
		A().Bus:On("ROSTER_SELECT", function(guid, entry) got = { guid, entry.name } end)
		V().frame.table.rows[3]:Click()
		deepEq(got, { V().frame.table.rows[3].data.entry.guid, "M0003" })
		truthy(V().frame.table.rows[3].selection:IsShown())
		falsy(V().frame.table.rows[2].selection:IsShown())
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
		local rows = V().frame.table.rows
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
		for _, b in ipairs(V().frame.table.heads) do if b.col.id == "level" then level = b end end
		level:Click(); level:Click()
		V():Model():ToggleColumn("zone"); V():Model():Save()
		V().frame.toolbar.grouped:Click()
		V():Model():Save()
		Mock.Reload()
		Mock.Slash("/accord roster")
		eq(V():Model().sort.key, "level")
		truthy(V():Model().sort.desc)
		falsy(V():Model().grouped)
		falsy(V():Model():HasColumn("zone"))
	end)

	it("a Lua error never comes out of drawing (the test fails on any recorded error)", function()
		open(40)
		V():Scroll(5)
		V():Select(V().frame.table.rows[1].data)
		eq(#Mock.errors, 0)
	end)
end)

describe("the look (M6.13)", function()
	local function nameCell(guidName)
		for _, r in ipairs(V().frame.table.rows) do
			if r:IsShown() and r.cells[1]:GetText() == guidName then return r.cells[1], r end
		end
	end
	local function near3(fs, r, g, b)
		local cr, cg, cb = fs:GetTextColor()
		return math.abs(cr - r) < 1e-4 and math.abs(cg - g) < 1e-4 and math.abs(cb - b) < 1e-4
	end

	it("a name is in the colour of the game's class, with a class square; the light theme keeps the name dark", function()
		RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
		open(10)
		local cell, row = nameCell("M0005")   -- a warrior
		local c = RAID_CLASS_COLORS.WARRIOR
		truthy(near3(cell, c.r, c.g, c.b), "the game's class colour on a dark theme")
		truthy(row.mark:IsShown(), "the square next to the name")
		A().Theme.Apply("aurora")
		local r, g, b = A().Theme.Color("text-1", "aurora")
		truthy(near3(cell, r, g, b), "text-1 on the light theme")
		A().Theme.Apply("nebula")
		truthy(near3(cell, c.r, c.g, c.b), "and back")
	end)

	it("cells of an online or a missing value use tokens, and a theme change repaints them", function()
		open(10)
		local online
		for _, r in ipairs(V().frame.table.rows) do
			if r:IsShown() and r.cells[1]:GetText() == "M0005" then online = r.cells[6] end   -- Last online: Online
		end
		eq(online:GetText(), "Online")
		local r, g, b = A().Theme.Color("ok")
		truthy(near3(online, r, g, b))
		A().Theme.Apply("accord")
		r, g, b = A().Theme.Color("ok", "accord")
		truthy(near3(online, r, g, b), "the colour of the new theme")
	end)

	it("the sorted column's title and the chips follow the theme and the model", function()
		open(10)
		local head = V().frame.table.heads[1]
		local r, g, b = A().Theme.Color("accent-text")
		truthy(near3(head.label, r, g, b), "the sorted column is in accent-text")
		local level = V().frame.table.heads[2]
		r, g, b = A().Theme.Color("text-3")
		truthy(near3(level.label, r, g, b))
		level:Click()
		r, g, b = A().Theme.Color("accent-text")
		truthy(near3(level.label, r, g, b), "the mark moved")
		V().frame.toolbar.online:Click()
		truthy(V().frame.toolbar.online:IsSelected())
		A().Theme.Apply("aurora")
		r, g, b = A().Theme.Color("on-secondary-container", "aurora")
		truthy(near3(V().frame.toolbar.online.label, r, g, b), "a selected chip has the ink of the tonal fill (ui-style §9.6)")
	end)

	it("the toolbar wraps to a second line in a narrow panel and the table starts under it", function()
		open(10)
		V().frame.toolbar:SetWidth(2000)
		V():Reflow()
		eq(V().toolbarLines, 1)
		V().frame.toolbar:SetWidth(520)
		V():LayoutToolbar()
		truthy(V().toolbarLines >= 2, "the controls do not fit one line")
		eq(V().frame.toolbar:GetHeight(), V().toolbarLines * V().TOOLBAR_LINE)
	end)
end)

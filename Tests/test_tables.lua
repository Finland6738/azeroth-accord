-- Sortable tables everywhere and the roster's role icon (M13.8; docs/specs/ui-style.md §9.9): the sort the DataTable
-- remembers, the rows without a sort key, nested rows, the "Sort by" menu, the sheet of lines and tables, the role read
-- from a public note.
local function A() return AzerothAccord end
local function W() return AzerothAccord.Widgets end

local function cells(t, id)
	local out = {}
	for _, r in ipairs(t.rows) do if r:IsShown() then out[#out + 1] = r.cells[id]:GetText() end end
	return out
end

local function columns()
	return {
		{ id = "name", title = "Name", flex = 1, text = function(d) return d.name end },
		{ id = "n", title = "N", width = 60, value = function(d) return d.n end,
			text = function(d) return d.n and tostring(d.n) or "-" end },
		{ id = "action", title = "", width = 60, sortable = false, text = function() return "" end },
	}
end

local function made(opts)
	local t = W().DataTable(UIParent, columns(), opts)
	t:SetSize(400, 300)
	return t
end

local data = { { name = "b", n = 2 }, { name = "none" }, { name = "C", n = 1 }, { name = "a", n = 3 } }

describe("a sortable table", function()
	it("sorts ascending then descending, the rows without a key last both ways; an action column has no click", function()
		local t = made({})
		t:SetData(data)
		t.heads[2]:Click()
		deepEq(cells(t, "name"), { "C", "b", "a", "none" })
		truthy(t.heads[2].arrow:IsShown())
		t.heads[2]:Click()
		deepEq(cells(t, "name"), { "a", "b", "C", "none" })
		t.heads[1]:Click()
		deepEq(cells(t, "name"), { "a", "b", "C", "none" }, "texts without case")
		isNil(t.heads[3]:GetScript("OnClick"))
	end)

	it("remembers the choice for the character, over the first order the caller gave", function()
		local t = made({ memory = "test.table", sort = { id = "name" } })
		t:SetData(data)
		deepEq({ t:GetSort() }, { "name", false })
		t.heads[2]:Click(); t.heads[2]:Click()
		deepEq(A().Config:Get("char.ui.tableSort")["test.table"], { id = "n", desc = true })
		local again = made({ memory = "test.table", sort = { id = "name" } })
		again:SetData(data)
		deepEq({ again:GetSort() }, { "n", true })
		deepEq(cells(again, "name"), { "a", "b", "C", "none" })
		falsy(A().Config:Set("char.ui.tableSort", { x = "name" }), "a bad shape is refused")
	end)

	it("keeps nested rows under their parent", function()
		local t = made({ level = function(d) return d.level end })
		t:SetData({ { name = "z", level = 0 }, { name = "y", level = 1 }, { name = "x", level = 1 },
			{ name = "m", level = 0 }, { name = "q", level = 1 } })
		t.heads[1]:Click()
		deepEq(cells(t, "name"), { "m", "q", "z", "x", "y" })
	end)
end)

describe("the Sort by menu", function()
	it("sorts ascending on a choice, descending on the same one again, and remembers it", function()
		local got = {}
		local items = { { id = "order", text = "Order" }, { id = "title", text = "Title" } }
		local m = W().SortMenu(UIParent, { label = "Sort by: %s", items = items, memory = "test.menu",
			onChange = function(id, desc) got = { id, desc } end })
		deepEq({ m:Get() }, { "order", false })
		eq(m:GetLabel(), "Sort by: Order")
		m:Click()
		eq(#W().Menu.frame.items, 2)
		W().Menu.frame.rows[2]:Click()
		deepEq(got, { "title", false })
		eq(m:GetLabel(), "Sort by: Title")
		m:Choose("title")
		deepEq(got, { "title", true })
		local again = W().SortMenu(UIParent, { label = "%s", items = items, memory = "test.menu" })
		deepEq({ again:Get() }, { "title", true })
		falsy(again:Choose("nothing"))
	end)
end)

describe("the sheet of lines and tables", function()
	local function sheet()
		local s = W().Sheet(UIParent, { rowHeight = 20, defaultRows = 12, tables = {
			people = { memory = "test.sheet", columns = { { id = "name", title = "Name", flex = 1 } } } } })
		s:SetSize(300, 160)
		return s
	end
	local function lines(n)
		local out = { { text = "Title" } }
		for i = 1, n do out[#out + 1] = { table = "people", cells = { name = "P" .. (n - i + 1) } } end
		out[#out + 1] = { text = "End" }
		return out
	end

	it("draws the text lines and the table lines as a table with its header", function()
		local s = sheet()
		s:SetLines(lines(2))
		eq(s.lines[1]:GetText(), "Title")
		eq(s.lines[2]:GetText(), "End")
		local t = s:Table("people")
		deepEq(cells(t, "name"), { "P2", "P1" })
		t.heads[1]:Click()
		deepEq(cells(s:Table("people"), "name"), { "P1", "P2" })
	end)

	it("scrolls through the rows of a long table, in its order, up to the last line", function()
		local s = sheet()
		s:SetLines(lines(9))
		deepEq(cells(s:Table("people"), "name"), { "P9", "P8", "P7" })
		truthy(s:Scroll(3))
		deepEq(cells(s:Table("people"), "name"), { "P7", "P6", "P5" })
		s:Table("people").heads[1]:Click()
		deepEq(cells(s:Table("people"), "name"), { "P3", "P4", "P5" })
		s:Scroll(100)
		eq(s.offset, s:MaxOffset())
		local last
		for _, fs in ipairs(s.lines) do if fs:IsShown() then last = fs:GetText() end end
		eq(last, "End")
		s:Scroll(-100)
		eq(s.offset, 0)
	end)
end)

describe("the role of a public note", function()
	local function role(note) return A().Roster.RoleFromNote(note) end

	it("is the first role word, whole, in any case", function()
		eq(role("Tank / alt di Mario"), "tank")
		eq(role("dps, a volte heal"), "damage")
		eq(role("main healer"), "healer")
		eq(role("CURA e dps"), "healer")
		eq(role("Curatore"), "healer"); eq(role("guaritore"), "healer"); eq(role("Healing"), "healer")
		eq(role("melee/ranged"), "damage"); eq(role("caster"), "damage"); eq(role("DD"), "damage"); eq(role("damage"), "damage")
		eq(role("alt\226\128\148tank"), "tank", "a dash of UTF-8 separates words")
		eq(role("\194\171heal\194\187"), "healer", "and so do the guillemets")
	end)

	it("is nothing without one: part of a word does not count", function()
		isNil(role(""))
		isNil(role(nil))
		isNil(role("Herbalist"))
		isNil(role("tankard, sicuramente, healthy"))
		isNil(role("curacao\195\168"))
	end)
end)

describe("the roster's role mark", function()
	local TANK, HEAL, NONE = "Player-1-00000001", "Player-1-00000002", "Player-1-00000003"

	local function open()
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Aaa", class = "WARRIOR", rank = 3, guid = TANK, note = "Tank / alt" },
			{ name = "Bbb", class = "PRIEST", rank = 3, guid = HEAL, note = "main healer" },
			{ name = "Ccc", class = "MAGE", rank = 3, guid = NONE, note = "Herbalist" },
		} }
		Mock.Slash("/accord roster")
		Mock.Advance(1)
	end

	local function rowOf(guid)
		for _, r in ipairs(A().RosterView.frame.table.rows) do
			if r:IsShown() and r.data.entry.guid == guid then return r end
		end
	end

	it("is the role icon in the class colour, or the class square without a role", function()
		RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 },
			MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
		open()
		local tank, heal, none = rowOf(TANK), rowOf(HEAL), rowOf(NONE)
		truthy(tank.role:IsShown()); falsy(tank.mark:IsShown())
		deepEq(tank.role._texCoord, { A().Assets.IconCoords("role_tank", true) })
		deepEq(heal.role._texCoord, { A().Assets.IconCoords("role_healer", true) })
		local c = RAID_CLASS_COLORS.WARRIOR
		near((tank.role:GetVertexColor()), c.r, 1e-6)
		falsy(none.role:IsShown()); truthy(none.mark:IsShown())
	end)

	it("is the same icon on the member card, the square without a role", function()
		open()
		local Card = A().MemberCard
		rowOf(TANK):Click()
		truthy(Card.frame.role:IsShown()); falsy(Card.frame.mark:IsShown())
		deepEq(Card.frame.role._texCoord, { A().Assets.IconCoords("role_tank", true) })
		rowOf(NONE):Click()
		falsy(Card.frame.role:IsShown()); truthy(Card.frame.mark:IsShown())
	end)

	it("is said by the member card, with where it comes from", function()
		open()
		local d = A().MemberCard.Describe(A().Roster:ByGUID(HEAL))
		local found = false
		for _, l in ipairs(d.sections[1].lines) do
			if l.text == "Role: healer (from the public note)" then found = true end
		end
		truthy(found)
		eq(A().RosterModel.Role(A().Roster:ByGUID(TANK)), "tank")
		isNil(A().RosterModel.Role(A().Roster:ByGUID(NONE)))
	end)

	it("takes MS1 of the season declaration when the note says no role", function()
		open()
		A().Season.Source = function() return "accord" end
		A().Season.Enabled = function() return true end
		A().Store:Records("season")["E:1:" .. NONE] = { id = "E:1:" .. NONE, ms1 = { spec = "frost", role = "ranged" } }
		local entry = A().Roster:ByGUID(NONE)
		deepEq({ A().RosterModel.Role(entry, { n = 1 }) }, { "damage", "season" })
		deepEq({ A().RosterModel.Role(A().Roster:ByGUID(TANK), { n = 1 }) }, { "tank", "note" })
		isNil(A().RosterModel.Role(entry, nil))
	end)
end)

-- Every header of every table the views show, with the invented guild of demo mode and every switch on: it sorts both
-- ways without an error (the sort keys are read only on a click).
describe("every table of every view", function()
	before_boot(function(M)
		M.features = { season = true, raid = true, actions = true, groups = true, census = true, recruit = true, econ = true }
	end)

	local function walk(frame, visit)
		if not frame:IsShown() then return end
		visit(frame)
		for _, child in ipairs({ frame:GetChildren() }) do walk(child, visit) end
	end

	local seen = {}
	local function clickAll(frame, where)
		local tables = {}
		walk(frame, function(f) if f.SortBy and f.heads then tables[#tables + 1] = f end end)
		for _, t in ipairs(tables) do
			seen[t] = true
			for _, b in ipairs(t.heads) do
				if b:IsShown() and b:GetScript("OnClick") then
					b:Click()
					b:Click()
					eq(#Mock.errors, 0, where .. ": " .. tostring(b.col.id) .. " " .. tostring(Mock.errors[1] and Mock.errors[1].message))
				end
			end
		end
	end

	it("sorts by every column, both ways", function()
		Mock.Slash("/accord demo")
		Mock.Advance(2)
		local function open(id)
			truthy(A().Shell:OpenView(id), id .. " opens")
			Mock.Advance(2)
			return A().Shell.views[id].frame
		end
		for _, view in ipairs(A().Shell:ViewList()) do clickAll(open(view.id), view.id) end
		local function pages(id, list, show)
			local frame = open(id)
			for _, page in ipairs(list) do
				show(page)
				Mock.Advance(2)
				clickAll(frame, id .. "/" .. page)
			end
		end
		local function ids(defs)
			local out = {}
			for key, def in pairs(defs) do out[#out + 1] = type(def) == "table" and def.id or key end
			table.sort(out)
			return out
		end
		pages("groups", { "list", "form", "mine" }, function(p) A().GroupsView:ShowPage(p) end)
		pages("actions", ids(A().ActionsView.pages), function(p) A().ActionsView:ShowPage(p) end)
		pages("officers", ids(A().OfficersView.pages), function(p) A().OfficersView:ShowPage(p) end)
		pages("bank", ids(A().BankView.modes), function(p) A().BankView:SetMode(p) end)
		pages("market", ids(A().MarketView.modes), function(p) A().MarketView:SetMode(p) end)
		pages("reputation", ids(A().ReputationView.modes), function(p) A().ReputationView:SetMode(p) end)
		pages("professions", { "catalogue", "craft" }, function(p) A().RecipeView:SetMode(p) end)
		A().OfficersView:OpenReview()
		local d = A().OfficersView.reviewDialog
		for step = 1, 3 do
			A().OfficersView:ReviewStep(step)
			clickAll(d, "review " .. step)
		end
		d:Hide()
		local n = 0
		for _ in pairs(seen) do n = n + 1 end
		truthy(n >= 25, "tables walked: " .. n)
		T.log("tables walked: " .. n)
	end)
end)

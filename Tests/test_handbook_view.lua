-- The handbook's reader (M11.3; SPEC-15 §4, §5; SPEC-04): the text format (blocks, links, cleaning, the HTML of a
-- block, the search) and the Handbook view behind the switch "raid": every member reads every published page from what
-- the client holds, also after a /reload with nobody online; the "updated" mark clears on reading, never by passing
-- through; links, Back, headings, web addresses and the search lead where they say.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function H() return AzerothAccord.Handbook end
local function T() return AzerothAccord.HandbookText end
local function V() return AzerothAccord.HandbookView end

local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000C0C"

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank, members = {
		{ name = "Bob", level = 30, class = "MAGE", rank = 3, guid = BOB, online = false },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = false },
	} }
end

local function member(Mk) Mk.features = { raid = true } guild(3) end
local function officer(Mk) Mk.features = { raid = true } guild(1) end
local function off(Mk) Mk.features = { raid = false, season = true } guild(3) end

-- Pages as the officer's client sent them.
local function give(slug, fields)
	local rec = { id = "P:" .. slug, author = OFF, rev = 1, time = GetServerTime(), title = slug, body = "Text.", order = 20 }
	for k, v in pairs(fields or {}) do rec[k] = v end
	eq(S():Receive("handbook", { rec }, "Boss", "GUILD"), 1, "page " .. slug)
	Mock.Advance(1)
end

local RULES = table.concat({
	"# General",                                             -- 1
	"Be kind. See [[loot¦the loot rules]] and",              -- 2
	"[[raid#Bench]], or [[ghost]].",                         -- 3
	"",
	"## Voice",                                              -- 5
	"- Join before the pull: https://example.org/voice.",    -- 6
	"1. Then the [[season]].",                               -- 7
}, "\n")

local function library()
	give("rules", { title = "Rules", body = RULES, order = 10 })
	give("raid", { title = "Raids", body = "# Times\nOn Thursday.\n\n## Bench\nIt turns, città permitting.", order = 20 })
	give("loot", { title = "Loot", body = "Credits.", order = 30 })
	give("draft", { title = "Draft", body = "Not yet.", order = 40, tpl = true })
end

local function open()
	truthy(A().Shell:OpenView("handbook"))
	return V().frame
end

local function titles()
	local out = {}
	for _, row in ipairs(V().frame.rows) do
		if row:IsShown() then out[#out + 1] = row.label:GetText() end
	end
	return out
end

local function rowOf(title)
	for _, row in ipairs(V().frame.rows) do
		if row:IsShown() and row.label:GetText() == title then return row end
	end
end

-- The HTML of the blocks shown, one line each.
local function shown()
	local out = {}
	for _, h in ipairs(V().frame.blocks) do
		if h:IsShown() then out[#out + 1] = h:GetText() end
	end
	return table.concat(out, "\n")
end

-- Clicks the n-th link of the block that holds `needle`.
local function click(needle, n)
	for _, h in ipairs(V().frame.blocks) do
		if h:IsShown() and h:GetText():find(needle, 1, true) then
			Mock.RunScript(h, "OnHyperlinkClick", "acc:" .. (n or 1), "", "LeftButton")
			return true
		end
	end
	error("no block with " .. needle)
end

local function updated()
	local out = {}
	for _, rec in ipairs(H():Updated()) do out[#out + 1] = rec.id end
	return out
end

---------------------------------------------------------------------------------------------------------------------
describe("the handbook's text (SPEC-15 §4)", function()
	before_boot(member)

	it("reads headings, lists of two levels, numbered items and paragraphs, with their lines", function()
		local b = T().Blocks("# One\n### three\nsame paragraph\n\n- a\n  * b\n12. c\nafter\n## Two\n#no\n-no")
		local got = {}
		for i, x in ipairs(b) do got[i] = ("%s:%s:%d-%d"):format(x.kind, x.text, x.line, x.last) end
		deepEq(got, { "h1:One:1-1", "p:### three same paragraph:2-3", "li:a:5-5", "li:b:6-6", "oli:c:7-7", "p:after:8-8",
			"h2:Two:9-9", "p:#no -no:10-11" })
		eq(b[3].level, 1); eq(b[4].level, 2); eq(b[5].number, "12.")
		eq(#T().Blocks(""), 0)
	end)

	it("cleans game codes, so that a cleaned text is one that can be saved", function()
		local raw = "Take |cffa335ee|Hitem:19019::::|h[Thunderfury]|h|r now |TInterface\\Icons\\x:0|t|A:atlas:0:0|a  \r\n"
			.. "a || b | c\t.\1\127\r\r\r\r\r\nend |cnIQ4:purple|r"
		local clean = T().Clean(raw)
		eq(clean, "Take [Thunderfury] now\na ¦ b ¦ c .\n\n\nend purple")
		eq(T().Clean(clean), clean, "twice is once")
		truthy(H().IsClean(clean, true))
		eq(T().Clean("  A |cffffffffTitle|r\nhere  ", true), "A Title here")
		eq(T().Clean("[[loot||the loot]]"), "[[loot¦the loot]]", "a typed | stays a link's separator")
		eq(T().Clean(nil), "")
	end)

	it("finds links, headings, own texts and web addresses", function()
		local p = T().Inline("a [[Loot¦the rules]] b [[raid#Bench]] [[not a slug]] (https://example.org/x_y?a=1). [[season]]")
		local kinds = {}
		for i, x in ipairs(p) do kinds[i] = x.kind end
		deepEq(kinds, { "text", "link", "text", "link", "text", "url", "text", "link" })
		eq(p[2].link.slug, "loot"); eq(p[2].link.label, "the rules"); eq(p[2].link.special, "loot")
		eq(p[4].link.slug, "raid"); eq(p[4].link.heading, "Bench"); isNil(p[4].link.label)
		eq(p[5].text, " [[not a slug]] (")
		eq(p[6].url, "https://example.org/x_y?a=1")
		eq(p[7].text, "). ")
		eq(p[8].link.special, "season")
		eq(T().Plain("see [[raid#Bench¦the bench]]!"), "see the bench!")
	end)

	it("writes HTML in which only our tags are tags", function()
		local block = T().Blocks("- <h1>no</h1> & [[a¦<b>]] [[gone]]")[1]
		local html, links = T().HTML(block, function(part)
			if part.link.slug == "a" then return part.link.label, "A" end
			return part.link.slug, nil
		end, { link = "112233", missing = "445566" })
		eq(html, "<html><body><p>• &lt;h1&gt;no&lt;/h1&gt; &amp; <a href=\"acc:1\">|cff112233&lt;b&gt;|r</a> "
			.. "|cff445566gone|r</p></body></html>")
		deepEq(links, { "A" })
		matches((T().HTML(T().Blocks("## T")[1], nil)), "<h2>T</h2>")
	end)

	it("searches titles and lines without case and accents, from 2 characters, 50 results at most", function()
		local pages = {
			{ id = "P:a", title = "Città", body = "# Regole\nPerché sì.\n\n## Altro\nniente" },
			{ id = "P:b", title = "B", body = ("perche\n"):rep(60) },
		}
		isNil(T().Search("p", pages)); isNil(T().Search("è", pages)); isNil(T().Search("  ", pages))
		local r = T().Search("CITTA", pages)
		eq(#r, 1); eq(r[1].id, "P:a"); isNil(r[1].line)
		r = T().Search("perche", pages)
		eq(#r, 50); eq(r[1].heading, "Regole"); eq(r[1].line, 2); eq(r[1].text, "Perché sì.")
		eq(r[2].id, "P:b"); eq(r[2].line, 1)
		r = T().Search("altro", pages)
		eq(#r, 1); isNil(r[1].heading, "a heading is not under another"); eq(r[1].line, 4)
		eq(#T().Search("zz", pages), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the Handbook view with the switch `raid` off", function()
	before_boot(off)

	it("has no tab, no command and no row", function()
		falsy(A().Shell:OpenView("handbook"))
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "handbook") end
		Mock.Slash("/accord handbook rules")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Unknown command 'handbook'")
		isNil(V().frame)
		falsy(H():MarkRead("P:rules"))
		eq(H():MarkAllRead(), 0)
		eq(#H():Updated(), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a member reads the handbook", function()
	before_boot(member)

	it("says so when there are no pages", function()
		local f = open()
		truthy(f.empty:IsShown())
		eq(f.empty:GetText(), "No handbook pages yet.")
		falsy(f.reader:IsShown()); falsy(f.markAll:IsShown())
	end)

	it("lists the published pages in their order and reads them with nobody online, also after a /reload", function()
		library()
		Mock.Reload()
		local f = open()
		deepEq(titles(), { "Rules", "Raids", "Loot" })
		eq(f.title:GetText(), "Rules")
		matches(f.meta:GetText(), "^Updated %d%d%d%d%-%d%d%-%d%d by Boss$")
		contains(shown(), "<h1>General</h1>")
		contains(shown(), "• Join before the pull")
		contains(shown(), "1. Then the ")
		rowOf("Loot"):Click()
		eq(f.title:GetText(), "Loot")
		contains(shown(), "Credits.")
		eq(#Mock.errors, 0)
	end)

	it("marks a page updated until it stays open for 2 seconds", function()
		library()
		deepEq(updated(), { "P:rules", "P:raid", "P:loot" })
		local f = open()
		eq(A().Shell.BadgeText(A().Shell.views.handbook), "3")
		eq(rowOf("Rules").mark:GetText(), "Updated")
		-- passing through does not read
		Mock.Advance(1)
		rowOf("Raids"):Click()
		Mock.Advance(1)
		rowOf("Loot"):Click()
		Mock.Advance(1.5)
		deepEq(updated(), { "P:rules", "P:raid", "P:loot" })
		Mock.Advance(1)
		deepEq(updated(), { "P:rules", "P:raid" })
		eq(rowOf("Loot").mark:GetText(), "")
		eq(A().Shell.BadgeText(A().Shell.views.handbook), "2")
		-- a new revision of a page read marks it again, and reading it clears the mark again
		give("loot", { title = "Loot", body = "Credits, then the roll.", order = 30, rev = 2 })
		eq(rowOf("Loot").mark:GetText(), "Updated")
		contains(shown(), "then the roll", "the open page shows the new text")
		Mock.Advance(2)
		eq(rowOf("Loot").mark:GetText(), "")
		-- the mark is kept over a /reload
		Mock.Reload()
		deepEq(updated(), { "P:rules", "P:raid" })
		open()
		truthy(f ~= V().frame)
		V().frame.markAll:Click()
		deepEq(updated(), {})
		isNil(A().Shell.BadgeText(A().Shell.views.handbook))
		falsy(V().frame.markAll:IsEnabled())
	end)

	it("reads nothing while the panel is closed", function()
		library()
		open()
		A().Window:Close()
		Mock.Advance(10)
		eq(#updated(), 3)
		A().Window:Open()
		Mock.Advance(3)
		eq(#updated(), 2)
	end)

	it("has one Action Center row for the updated pages, gone once they are read", function()
		library()
		local function row()
			for _, r in ipairs(A().Actions:Refresh()) do if r.provider == "handbook" then return r end end
		end
		local r = row()
		eq(r.title, "3 handbook pages updated"); eq(r.urgency, 1); eq(r.detail, "Rules, Raids, Loot")
		r.open()
		eq(A().Shell.selected, "handbook"); eq(V().selected, "P:rules")
		Mock.Advance(3)
		eq(row().title, "2 handbook pages updated")
		H():MarkAllRead()
		isNil(row())
	end)

	it("follows links, scrolls to a heading and goes back", function()
		library()
		local f = open()
		falsy(f.back:IsShown())
		contains(shown(), "ghost|r", "a missing page is grey text")
		falsy(shown():find("ghost</a>", 1, true))
		Mock.htmlHeight = function() return 100 end
		click("Be kind", 2)                      -- [[raid#Bench]]
		eq(V().selected, "P:raid"); eq(f.title:GetText(), "Raids")
		truthy(f.back:IsShown())
		local bench
		for _, h in ipairs(f.blocks) do if h:IsShown() and h:GetText():find("<h2>Bench</h2>", 1, true) then bench = h end end
		truthy(bench.y > 0)
		eq(f.text:GetVerticalScroll(), bench.y)
		f.back:Click()
		eq(V().selected, "P:rules"); falsy(f.back:IsShown()); eq(f.text:GetVerticalScroll(), 0)
		click("Be kind", 1)                      -- [[loot¦the loot rules]]
		eq(V().selected, "P:loot")
		-- a choice in the list starts afresh
		rowOf("Rules"):Click()
		eq(#V().history, 0); falsy(f.back:IsShown())
	end)

	it("remembers at most 20 steps back", function()
		give("a", { body = "[[b]]" })
		give("b", { body = "[[a]]" })
		open()
		for _ = 1, 25 do click("<a href") end
		eq(#V().history, 20)
	end)

	it("opens a web address in the copy box and the season link on the Season view", function()
		library()
		open()
		click("Join before", 1)
		truthy(A().CopyBox:IsShown())
		eq(A().CopyBox:GetText(), "https://example.org/voice")
		A().CopyBox:Hide()
		click("Then the", 1)
		eq(A().Shell.selected, "season")
	end)

	it("searches from the panel's search box and opens the page at the line", function()
		library()
		local f = open()
		Mock.htmlHeight = function() return 50 end
		truthy(A().Shell.content.bar.searchField:IsShown())
		A().Shell:OnSearch("c")
		eq(f.note:GetText(), "Type at least 2 characters.")
		deepEq(titles(), { "Rules", "Raids", "Loot" })
		A().Shell:OnSearch("citta")
		deepEq(titles(), { "Raids · Bench" })
		eq(rowOf("Raids · Bench").sub:GetText(), "It turns, città permitting.")
		rowOf("Raids · Bench"):Click()
		eq(f.title:GetText(), "Raids")
		truthy(f.text:GetVerticalScroll() > 0)
		A().Shell:OnSearch("draft")
		eq(#titles(), 0, "a template is not searched for a member")
		eq(f.note:GetText(), "Nothing found.")
		A().Shell:OnSearch("")
		deepEq(titles(), { "Rules", "Raids", "Loot" })
	end)

	it("opens a page from /accord handbook, and the last one read without a name", function()
		library()
		Mock.Slash("/accord handbook raid")
		eq(A().Shell.selected, "handbook"); eq(V().selected, "P:raid")
		Mock.Slash("/accord handbook nothing")
		contains(table.concat(Mock.PlainOutput(), "\n"), "no page named nothing")
		eq(V().selected, "P:raid")
		Mock.Slash("/accord handbook draft")
		eq(V().selected, "P:raid", "a template is not there for a member")
		Mock.Reload()
		Mock.Slash("/accord handbook")
		eq(V().selected, "P:raid")
	end)

	it("moves on when the open page is deleted", function()
		library()
		local f = open()
		rowOf("Loot"):Click()
		eq(S():Receive("handbook", { { id = "P:loot", author = OFF, rev = 2, time = GetServerTime(), del = true } },
			"Boss", "GUILD"), 1)
		Mock.Advance(1)
		deepEq(titles(), { "Rules", "Raids" })
		truthy(f.title:GetText() ~= "Loot")
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a writer reads the handbook", function()
	before_boot(officer)

	it("sees the templates too, which are never 'updated', and links to them stay grey", function()
		library()
		give("index", { title = "Index", body = "[[draft]]", order = 1 })
		local f = open()
		deepEq(titles(), { "Index", "Rules", "Raids", "Loot", "Draft" })
		eq(rowOf("Draft").mark:GetText(), "Template")
		falsy(shown():find("<a href", 1, true))
		rowOf("Draft"):Click()
		contains(f.meta:GetText(), "Template, not yet published")
		eq(#updated(), 4)
	end)

	it("sees no mark on what its own account wrote", function()
		truthy(H():Save("P:mine", { title = "Mine", body = "x", order = 1 }))
		eq(#updated(), 0)
	end)

	it("sees the pages over the limit, marked", function()
		for i = 1, 21 do give("p" .. i, { title = ("P%02d"):format(i), order = i, author = OFF }) end
		open()
		eq(#titles(), 21)
		eq(rowOf("P21").mark:GetText(), "Over the limit")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("an Italian client reads the handbook", function()
	before_boot(function(Mk)
		Mk.player.locale = "itIT"
		member(Mk)
	end)

	it("shows the view in Italian", function()
		library()
		local f = open()
		eq(A().Shell.views.handbook.label, "Manuale")
		eq(rowOf("Rules").mark:GetText(), "Aggiornata")
		matches(f.meta:GetText(), "^Aggiornata il .+ da Boss$")
		eq(#Mock.errors, 0)
	end)
end)

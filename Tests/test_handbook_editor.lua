-- The handbook's editor (M11.4; SPEC-15 §3.5, §5.2, §6) behind the switch "raid": only writers see it; a text over a
-- limit after cleaning cannot be saved; the preview; the draft; a page saved by somebody else meanwhile; the revisions
-- and "Restore", which writes a new revision, also of a deleted page; moving pages; the choice of the writers.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function H() return AzerothAccord.Handbook end
local function V() return AzerothAccord.HandbookView end
local function E() return AzerothAccord.HandbookEditor end

local BOB, OFF = "Player-1-00000B0B", "Player-1-00000C0C"

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank, members = {
		{ name = "Bob", level = 30, class = "MAGE", rank = 3, guid = BOB, online = false },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = false },
	} }
end

local function member(Mk) Mk.features = { raid = true } guild(3) end
local function officer(Mk) Mk.features = { raid = true } guild(1) end

local function give(slug, fields)
	local rec = { id = "P:" .. slug, author = OFF, rev = 1, time = GetServerTime(), title = slug, body = "Text.", order = 20 }
	for k, v in pairs(fields or {}) do rec[k] = v end
	if rec.del then rec.title, rec.body, rec.order = nil, nil, nil end
	eq(S():Receive("handbook", { rec }, "Boss", "GUILD"), 1, "page " .. slug)
	Mock.Advance(1)
end

local function save(slug, fields, base)
	local rec, why = H():Save("P:" .. slug, fields, { base = base })
	truthy(rec, tostring(why))
	Mock.Advance(1)
	return rec
end

local function open()
	truthy(A().Shell:OpenView("handbook"))
	return V().frame
end

local function rowOf(title)
	for _, row in ipairs(V().frame.rows) do
		if row:IsShown() and row.label:GetText() == title then return row end
	end
end

local function titles()
	local out = {}
	for _, row in ipairs(V().frame.rows) do
		if row:IsShown() then out[#out + 1] = row.label:GetText() end
	end
	return out
end

local function panel() return V().frame.editorPanel end

local function type_(title, body)
	if title then Mock.TypeInto(panel().title.edit, title) end
	if body then Mock.TypeInto(panel().edit, body) end
end

local function html(pane)
	local out = {}
	for _, h in ipairs(pane.blocks) do
		if h:IsShown() then out[#out + 1] = h:GetText() end
	end
	return table.concat(out, "\n")
end

local function held(slug) return S():Get("handbook", "P:" .. slug) end

---------------------------------------------------------------------------------------------------------------------
describe("a member and the editor", function()
	before_boot(member)

	it("shows nothing of it", function()
		give("rules", { title = "Rules" })
		give("old", { title = "Old" })
		give("old", { rev = 2, del = true })
		local f = open()
		isNil(f.newPage); isNil(f.edit); isNil(f.editorPanel)
		deepEq(titles(), { "Rules" })
		falsy(V():Edit("P:rules")); falsy(V():Edit()); falsy(V():OpenRevisions("P:rules"))
		truthy(V():OpenConflict("P:rules", 1))
		isNil(V().revisions)
		local ok, why = H():Move("P:rules", 1)
		falsy(ok); eq(why, "writer")
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a writer edits the handbook", function()
	before_boot(officer)

	it("writes a new page, whose link's | is saved as ¦", function()
		local f = open()
		truthy(f.newPage:IsShown()); truthy(f.empty:IsShown())
		f.newPage:Click()
		truthy(panel():IsShown()); falsy(f.list:IsShown()); falsy(f.newPage:IsShown())
		falsy(panel().save:IsEnabled())
		eq(panel().status:GetText(), "Write a title.")
		-- an edit box gives a typed | back as ||
		type_("Città e regole", "See [[loot||the loot]].  ")
		truthy(panel().save:IsEnabled())
		eq(panel().count:GetText(), "23 / 4 000 bytes")
		panel().save:Click()
		local rec = held("citta-e-regole")
		eq(rec.rev, 1); eq(rec.title, "Città e regole"); eq(rec.body, "See [[loot¦the loot]]."); eq(rec.order, 10)
		falsy(panel():IsShown()); eq(V().selected, "P:citta-e-regole")
		isNil(H().LocalData().draft)
		-- the next one goes after it
		f.newPage:Click()
		type_("Second", "x")
		panel().save:Click()
		eq(held("second").order, 15)
		eq(#Mock.errors, 0)
	end)

	it("cannot save a body over the limit, counted after the cleaning", function()
		save("rules", { title = "Rules", body = "Short.", order = 10 })
		local f = open()
		f.edit:Click()
		-- 4000 bytes once the game codes are gone
		type_(nil, ("a"):rep(4000) .. "|cffffffff|r   ")
		truthy(panel().save:IsEnabled())
		eq(panel().count:GetText(), "4 000 / 4 000 bytes")
		type_(nil, ("a"):rep(4000) .. "è")
		falsy(panel().save:IsEnabled())
		eq(panel().status:GetText(), "Too long by 2 bytes.")
		eq(panel().count:GetText(), "4 002 / 4 000 bytes")
		eq(#panel().edit:GetText(), 4002, "the box cuts nothing")
		panel().save:Click()
		local ok, why = E():Save()
		falsy(ok); eq(why, "body")
		eq(held("rules").rev, 1); eq(held("rules").body, "Short.")
	end)

	it("cannot save a long title, an empty one or a handbook over its total", function()
		for i = 1, 8 do save("p" .. i, { title = "P" .. i, body = ("a"):rep(3999), order = i }) end
		local f = open()
		f.newPage:Click()
		type_(("t"):rep(41), "x")
		falsy(panel().save:IsEnabled()); eq(panel().status:GetText(), "Title too long by 1 bytes.")
		type_("   ")
		falsy(panel().save:IsEnabled()); eq(panel().status:GetText(), "Write a title.")
		type_("Nine", ("a"):rep(9))
		falsy(panel().save:IsEnabled())
		eq(panel().status:GetText(), "The handbook would be over its limit by 1 bytes.")
		eq(panel().total:GetText(), "Handbook: 32 001 / 32 000")
		type_(nil, ("a"):rep(8))
		truthy(panel().save:IsEnabled())
		eq(H():Check(nil, "Nine", ("a"):rep(8)).total, 32000)
	end)

	it("cannot add a page over 20", function()
		for i = 1, 20 do give("p" .. i, { title = "P" .. i, order = i }) end
		open()
		truthy(V():Edit())
		type_("One more", "x")
		falsy(panel().save:IsEnabled())
		matches(panel().status:GetText(), "already has 20 pages")
	end)

	it("previews the cleaned text, with missing pages grey, and follows no page link", function()
		save("rules", { title = "Rules", body = "x", order = 10 })
		save("raid", { title = "Raids", body = "y", order = 20 })
		local f = open()
		f.edit:Click()
		type_(nil, "# Head\n[[raid]] [[ghost]] https://example.org/a")
		panel().toggle:Click()
		falsy(panel().field:IsShown()); truthy(panel().pane.text:IsShown())
		eq(panel().toggle:GetLabel(), "Back to text")
		contains(html(panel().pane), "<h1>Head</h1>")
		contains(html(panel().pane), "Raids|r</a>")
		contains(html(panel().pane), "ghost|r")
		for _, h in ipairs(panel().pane.blocks) do
			if h:IsShown() and h:GetText():find("<a href", 1, true) then
				Mock.RunScript(h, "OnHyperlinkClick", "acc:1", "", "LeftButton")
				truthy(panel():IsShown()); eq(V().selected, "P:rules")
				Mock.RunScript(h, "OnHyperlinkClick", "acc:2", "", "LeftButton")
				truthy(A().CopyBox:IsShown())
			end
		end
		panel().toggle:Click()
		truthy(panel().field:IsShown())
		eq(held("rules").rev, 1)
	end)

	it("asks before throwing changes away, and closes at once without any", function()
		save("rules", { title = "Rules", body = "Base.", order = 10 })
		local f = open()
		f.edit:Click()
		panel().cancel:Click()
		falsy(panel():IsShown())
		f.edit:Click()
		type_(nil, "Changed.")
		panel().cancel:Click()
		truthy(panel():IsShown()); eq(panel().cancel:GetLabel(), "Confirm")
		type_(nil, "Changed again.")
		eq(panel().cancel:GetLabel(), "Cancel", "typing disarms")
		panel().cancel:Click()
		panel().cancel:Click()
		falsy(panel():IsShown()); isNil(H().LocalData().draft)
		eq(held("rules").body, "Base.")
	end)

	it("saves nothing when nothing changed, and publishes a template", function()
		save("rules", { title = "Rules", body = "Base.", order = 10 })
		save("info", { title = "Info", body = "# About", order = 20, tpl = true })
		local f = open()
		f.edit:Click(); panel().save:Click()
		eq(held("rules").rev, 1)
		rowOf("Info"):Click()
		f.edit:Click(); panel().save:Click()
		eq(held("info").rev, 2); isNil(held("info").tpl)
	end)

	it("keeps a draft over a /reload and restores it", function()
		save("rules", { title = "Rules", body = "Base.", order = 10 })
		local f = open()
		f.edit:Click()
		type_(nil, "Half written [[loot||x")
		eq(H().LocalData().draft.id, "P:rules")
		Mock.Reload()
		f = open()
		f.edit:Click()
		truthy(panel().draft:IsShown())
		eq(panel().status:GetText(), "An unsaved draft of this page is kept.")
		eq(panel().edit:GetText(), "Base.")
		-- cancelling without touching it keeps it
		panel().cancel:Click()
		f.edit:Click()
		type_(nil, "Other.")
		panel().cancel:Click(); panel().cancel:Click()
		eq(H().LocalData().draft.body, "Half written [[loot||x", "an offered draft survives a cancelled change")
		f.edit:Click()
		panel().draft:Click()
		eq(panel().edit:GetText(), "Half written [[loot||x")
		falsy(panel().draft:IsShown())
		panel().save:Click()
		eq(held("rules").body, "Half written [[loot¦x"); isNil(H().LocalData().draft)
		-- a new page's draft
		f.newPage:Click()
		type_("New one", "text")
		Mock.Reload()
		f = open()
		f.newPage:Click()
		panel().draft:Click()
		eq(panel().title:GetText(), "New one")
	end)

	it("shows a page saved meanwhile and writes over it only on Keep mine", function()
		save("rules", { title = "Rules", body = "Base.", order = 10 })
		local f = open()
		f.edit:Click()
		type_(nil, "Mine.")
		give("rules", { title = "Rules", body = "Theirs.", rev = 2, order = 10 })
		eq(panel().edit:GetText(), "Mine.", "an arriving page does not touch the text being written")
		panel().save:Click()
		eq(held("rules").body, "Theirs.")
		truthy(panel().keep:IsShown()); falsy(panel().save:IsShown())
		matches(panel().status:GetText(), "^This page changed while you were editing %(by Boss, ")
		contains(html(panel().pane), "Theirs.")
		-- saved again before the choice: shown again, not overwritten
		give("rules", { title = "Rules", body = "Theirs, 3.", rev = 3, order = 10 })
		panel().keep:Click()
		eq(held("rules").body, "Theirs, 3.")
		contains(html(panel().pane), "Theirs, 3.")
		panel().keep:Click()
		eq(held("rules").rev, 4); eq(held("rules").body, "Mine.")
		falsy(panel():IsShown())
	end)

	it("keeps a discarded text among the revisions, marked lost", function()
		save("rules", { title = "Rules", body = "Base.", order = 10 })
		local f = open()
		f.edit:Click()
		type_(nil, "Mine.")
		give("rules", { rev = 2, del = true })
		panel().save:Click()
		matches(panel().status:GetText(), "^This page was deleted while you were editing")
		panel().discard:Click()
		falsy(panel():IsShown()); isNil(H().LocalData().draft)
		eq(held("rules").del, true)
		local lost
		for _, r in ipairs(H():Revisions("P:rules")) do if r.lost then lost = r end end
		eq(lost.body, "Mine."); falsy(lost.open)
		eq(#H():Conflicts(), 0)
	end)

	it("restores a past revision as a new revision", function()
		save("rules", { title = "Rules", body = "One.", order = 10 })
		save("rules", { title = "Rules", body = "Two.", order = 10 }, 1)
		local f = open()
		f.revisionsButton:Click()
		local p = f.revPanel
		truthy(p:IsShown()); falsy(f.reader:IsShown())
		matches(p.rows[1].label:GetText(), "^Revision 2 · .+ · %d%d%d%d%-%d%d%-%d%d %d%d:%d%d · 4 bytes · current$")
		falsy(p.restore:IsShown())
		p.rows[2]:Click()
		contains(html(p.pane), "One.")
		truthy(p.restore:IsShown()); falsy(p.dismiss:IsShown())
		p.restore:Click()
		eq(held("rules").rev, 3); eq(held("rules").body, "One.")
		falsy(p:IsShown()); truthy(f.reader:IsShown())
		eq(#H():Revisions("P:rules"), 3)
		f.revisionsButton:Click()
		p.close:Click()
		falsy(p:IsShown())
	end)

	it("opens its own lost text from the conflict's Action Center row", function()
		save("rules", { title = "Rules", body = "Base.", order = 10 })
		local mine = save("rules", { title = "Rules", body = "Mine." }, 1)
		give("rules", { title = "Rules", body = "Theirs.", rev = 2, time = mine.time + 3 })
		local row
		for _, r in ipairs(A().Actions:Refresh()) do if r.provider == "handbook" and r.key ~= "updated" then row = r end end
		row.open()
		eq(A().Shell.selected, "handbook")
		local p = V().frame.revPanel
		truthy(p:IsShown())
		contains(html(p.pane), "Mine.")
		truthy(p.dismiss:IsShown())
		p.dismiss:Click()
		eq(#H():Conflicts(), 0)
		falsy(p.dismiss:IsShown())
		p.restore:Click()
		eq(held("rules").rev, 3); eq(held("rules").body, "Mine.")
	end)

	it("deletes on the second click and restores the deleted page", function()
		save("rules", { title = "Rules", body = "Keep me.", order = 10 })
		save("raid", { title = "Raids", body = "y", order = 20 })
		local f = open()
		f.delete:Click()
		eq(f.delete:GetLabel(), "Confirm"); truthy(f.deleteNote:IsShown())
		rowOf("Raids"):Click()
		eq(f.delete:GetLabel(), "Delete", "another page disarms")
		rowOf("Rules"):Click()
		f.delete:Click(); f.delete:Click()
		eq(held("rules").del, true)
		Mock.Advance(1)
		deepEq(titles(), { "Raids", "Deleted pages", "Rules" })
		rowOf("Deleted pages"):Click()
		rowOf("Rules"):Click()
		local p = f.revPanel
		truthy(p:IsShown()); contains(html(p.pane), "Keep me.")
		p.restore:Click()
		local rec = held("rules")
		eq(rec.rev, 3); eq(rec.body, "Keep me."); eq(rec.order, 10); isNil(rec.del)
		eq(V().selected, "P:rules")
		deepEq(titles(), { "Rules", "Raids" })
		eq(#Mock.errors, 0)
	end)

	it("lists the deleted pages when no page is left", function()
		save("rules", { title = "Rules", body = "x", order = 10 })
		H():Delete("P:rules", 1)
		local f = open()
		truthy(f.empty:IsShown()); truthy(f.list:IsShown()); truthy(f.newPage:IsShown())
		deepEq(titles(), { "Deleted pages", "Rules" })
		falsy(f.reader:IsShown())
	end)

	it("moves a page with the arrows, one revision at a time", function()
		save("a", { title = "A", body = "x", order = 10 })
		save("b", { title = "B", body = "x", order = 20 })
		save("c", { title = "C", body = "x", order = 30, tpl = true })
		open()
		rowOf("A"):Click()
		falsy(rowOf("A").up:IsEnabled()); truthy(rowOf("A").down:IsEnabled())
		rowOf("C"):Click()
		rowOf("C").up:Click()
		deepEq(titles(), { "A", "C", "B" })
		eq(held("c").rev, 2); eq(held("c").tpl, true); eq(held("b").rev, 1)
		rowOf("C").down:Click()
		deepEq(titles(), { "A", "B", "C" })
	end)

	it("moves pages whose orders leave no room", function()
		-- equal orders: only the titles tell them apart
		save("a", { title = "A", body = "x", order = 1 })
		save("b", { title = "B", body = "x", order = 1 })
		truthy(H():Move("P:b", -1))
		local order = {}
		for i, rec in ipairs(H():Pages(true)) do order[i] = rec.title end
		deepEq(order, { "B", "A" })
		save("c", { title = "C", body = "x", order = 99 })
		save("d", { title = "D", body = "x", order = 99 })
		truthy(H():Move("P:d", -1))
		order = {}
		for i, rec in ipairs(H():Pages(true)) do order[i] = rec.title end
		deepEq(order, { "B", "A", "D", "C" })
		local ok, why = H():Move("P:b", -1)
		falsy(ok); eq(why, "id")
	end)

	it("does not open in combat", function()
		save("rules", { title = "Rules", body = "x", order = 10 })
		local f = open()
		local was = InCombatLockdown
		InCombatLockdown = function() return true end
		f.edit:Click()
		isNil(V().editor)
		contains(table.concat(Mock.PlainOutput(), "\n"), "does not open in combat")
		InCombatLockdown = was
		f.edit:Click()
		truthy(V().editor)
	end)

	it("closes when the player stops being a writer, keeping the draft", function()
		save("rules", { title = "Rules", body = "x", order = 10 })
		local f = open()
		f.edit:Click()
		type_(nil, "Unsaved.")
		guild(3)
		A().Bus:Emit("ROLE_CHANGED")
		Mock.Advance(30)
		falsy(H():CanWrite())
		isNil(V().editor); falsy(panel():IsShown()); truthy(f.list:IsShown())
		falsy(f.newPage:IsShown()); falsy(f.edit:IsShown())
		eq(held("rules").body, "x")
		eq(A().GuildKey:Data().handbook.draft.body, "Unsaved.")
	end)

	it("lets an officer choose the ranks that write", function()
		local f = open()
		truthy(f.writers:IsShown())
		f.writers:Click()
		local menu = A().Widgets.Menu.frame
		local pick
		for _, row in ipairs(menu.rows) do
			if row:IsShown() and row.item and row.item.rank == 3 then pick = row end
		end
		truthy(pick, "rank 3 can be chosen")
		pick:Click()
		eq(H():ChosenRanks()[1].i, 3)
		truthy(H().IsWriter({ rankIndex = 3 }))
		pick:Click()
		eq(#H():ChosenRanks(), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("an Italian writer", function()
	before_boot(function(Mk)
		Mk.player.locale = "itIT"
		officer(Mk)
	end)

	it("edits in Italian", function()
		local f = open()
		eq(f.newPage:GetLabel(), "Nuova pagina")
		f.newPage:Click()
		eq(panel().save:GetLabel(), "Salva")
		eq(panel().status:GetText(), "Scrivi un titolo.")
		eq(#Mock.errors, 0)
	end)
end)

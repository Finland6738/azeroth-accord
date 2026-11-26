-- The loot page (M11.6; SPEC-15 §8; SPEC-10 Q30-Q33): the `guildcfg` record "loot" (officers only, any CurseForge addon,
-- the address on CurseForge only), the addon and the loot source chosen together, who has the addon from the census
-- (counts for everybody, names for officers), nothing checked without an addon, the FDCP suggestion (a locale text, for
-- writers), FDCP's rules beside the page and never in its text, and the part in the Handbook and Raid views.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Lo() return AzerothAccord.Loot end
local function P() return AzerothAccord.LootPage end
local function I() return AzerothAccord.Integrations end
local function V() return AzerothAccord.HandbookView end
local function L(key) return LibStub("AceLocale-3.0"):GetLocale("AzerothAccord")[key] end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"
local URL = "https://www.curseforge.com/wow/addons/my-loot"

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank, members = {
		{ name = "Bob", level = 30, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
	} }
end

local function member(Mk) Mk.features = { raid = true, census = true } guild(3) end
local function officer(Mk) Mk.features = { raid = true, census = true } guild(1) end

-- A loot record as the officer "Boss" wrote it.
local function record(fields)
	local held = S():Get("guildcfg", "loot")
	local rec = { id = "loot", author = OFF, rev = (held and held.rev or 0) + 1, time = GetServerTime(), system = "none", addon = "none" }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

local function receive(fields)
	local ok, why = S():Accept("guildcfg", record(fields), { sender = "Boss" })
	Mock.Advance(2)
	return ok, why
end

local OTHER = { system = "other", systemName = "Plus one", addon = "other", addonName = "My Loot", addonFolder = "MyLoot", url = URL }

local function shares(id, name, list)
	local rec = { id = id, author = id, rev = 1, time = GetServerTime(), l = list }
	eq(S():Receive("addons", { rec }, name, "GUILD"), 1, name)
	Mock.Advance(2)
end

local function lines(form)
	local out = {}
	for _, l in ipairs(P().Lines(P().Model(), form)) do
		out[#out + 1] = l.text or (l.copy and "[copy] " .. l.copy) or (l.button and "[button] " .. l.button) or "[form]"
	end
	return out
end
local function text(form) return table.concat(lines(form), "\n") end

local function has(t, part) truthy(t:find(part, 1, true), part .. " in:\n" .. t) end
local function lacks(t, part) falsy(t:find(part, 1, true), part .. " not in:\n" .. t) end

local function page(slug, body, fields)
	local rec = { id = "P:" .. slug, author = OFF, rev = 1, time = GetServerTime(), title = slug, body = body, order = 60 }
	for k, v in pairs(fields or {}) do rec[k] = v end
	eq(S():Receive("handbook", { rec }, "Boss", "GUILD"), 1, "page " .. slug)
	Mock.Advance(2)
end

---------------------------------------------------------------------------------------------------------------------
describe("the loot record", function()
	before_boot(member)

	it("holds a system and an addon, with the names only for 'other'", function()
		local function valid(f) return Lo().ValidRecord(record(f)) end
		truthy(valid())
		truthy(valid({ system = "council", addon = "gargul" }))
		truthy(valid(OTHER))
		for i, f in ipairs({
			{ system = "gdkp" }, { system = "other" }, { system = "dkp", systemName = "x" }, { systemName = "x" },
			{ addon = "unknown" }, { addon = "gargul", url = URL }, { addon = "gargul", addonName = "x" },
			{ addon = "other" }, { addon = "other", addonName = "n", addonFolder = "f" },
			{ addon = "other", addonName = "a|r", addonFolder = "f", url = URL },
			{ addon = "other", addonName = "n", addonFolder = "a/b", url = URL },
			{ addon = "other", addonName = "n", addonFolder = ("f"):rep(65), url = URL },
			{ system = "other", systemName = ("n"):rep(33) }, { extra = 1 },
		}) do
			falsy(valid(f), "bad record " .. i)
		end
	end)

	it("accepts an address on CurseForge over https only", function()
		for _, ok in ipairs({ URL, "https://curseforge.com/wow/addons/x", "https://WWW.CurseForge.com/wow/addons/x?a=1",
			"https://www.curseforge.com" }) do
			truthy(Lo().ValidUrl(ok), ok)
		end
		for _, bad in ipairs({ "http://www.curseforge.com/x", "https://github.com/x", "https://curseforge.com.evil.example/x",
			"https://evil.example/curseforge.com", "https://user" .. "@" .. "www.curseforge.com/x", "https://www.curseforge.com:8080/x",
			"https://www.curseforge.com/a b", "https://www.curseforge.com/a|r", "https://www.curseforge.com\\@evil.example",
			"www.curseforge.com/x", "https://www.curseforge.com/" .. ("a"):rep(100), 5 }) do
			falsy(Lo().ValidUrl(bad), tostring(bad))
		end
	end)

	it("is refused from a member, and with a foreign address even from an officer", function()
		local ok, why = S():Accept("guildcfg", record({ author = BOB, addon = "gargul" }), { sender = "Bob" })
		falsy(ok); eq(why, "authority")
		local bad = { addon = "other", addonName = "n", addonFolder = "f", url = "https://evil.example/x" }
		ok, why = receive(bad)
		falsy(ok); eq(why, "owner")
		truthy(receive(OTHER))
		eq(Lo():Get().addonFolder, "MyLoot")
	end)

	it("cannot be written by a member", function()
		local ok, why = Lo():Set({ addon = "gargul" })
		falsy(ok); eq(why, "officer")
		isNil(S():Get("guildcfg", "loot"))
	end)

	it("decides the loot source, also over a sources record that says otherwise", function()
		truthy(S():Accept("guildcfg", { id = "sources", author = OFF, rev = 1, time = GetServerTime(), raid = "accord",
			loot = "fdcp" }, { sender = "Boss" }))
		eq(I():Source("loot"), "fdcp")
		eq(Lo():Get().addon, "fdcp", "without a loot record the source is the same choice")
		receive({ addon = "gargul" })
		eq(I():Source("loot"), "none")
		eq(Lo():Get().addon, "gargul")
		receive({ addon = "fdcp" })
		eq(I():Source("loot"), "fdcp")
	end)
end)

describe("with the switch off", function()
	before_boot(function(M) M.features = { raid = false, season = true } guild(1) end)

	it("takes and writes no loot record", function()
		local ok, why = Lo():Set({ addon = "gargul" })
		falsy(ok); eq(why, "off")
		ok, why = S():Accept("guildcfg", record({ addon = "gargul" }), { sender = "Boss" })
		falsy(ok); eq(why, "owner")
		isNil(Lo():Record())
		eq(Lo():Get().addon, "none")
	end)
end)

describe("an officer chooses", function()
	before_boot(officer)

	it("writes the addon and the loot source together", function()
		truthy(Lo():Set({ addon = "fdcp" }))
		eq(S():Get("guildcfg", "loot").addon, "fdcp")
		eq(S():Get("guildcfg", "sources").loot, "fdcp")
		truthy(I():SetSource("raid", "fdcp"))
		truthy(Lo():Set({ system = "council" }))
		eq(Lo():Get().addon, "fdcp", "the system keeps the addon")
		truthy(Lo():Set({ addon = "gargul" }))
		eq(S():Get("guildcfg", "sources").loot, "none")
		eq(S():Get("guildcfg", "sources").raid, "fdcp", "the raid source stays")
		eq(Lo():Get().system, "council")
		truthy(Lo():Set({ addon = "none" }))
		eq(I():Source("loot"), "none")
	end)

	it("takes any CurseForge addon, trimmed, and drops the names with another choice", function()
		local ok, why = Lo():Set({ addon = "other", addonName = "My Loot", addonFolder = "MyLoot", url = "https://example.org/x" })
		falsy(ok); eq(why, "url")
		isNil(S():Get("guildcfg", "loot"))
		truthy(Lo():Set({ addon = "other", addonName = " My Loot ", addonFolder = "MyLoot ", url = " " .. URL }))
		local rec = S():Get("guildcfg", "loot")
		eq(rec.addonName, "My Loot"); eq(rec.addonFolder, "MyLoot"); eq(rec.url, URL)
		truthy(Lo():Set({ addon = "raidcore" }))
		rec = S():Get("guildcfg", "loot")
		isNil(rec.addonName); isNil(rec.addonFolder); isNil(rec.url)
		local rev = rec.rev
		truthy(Lo():Set({ addon = "raidcore" }))
		eq(S():Get("guildcfg", "loot").rev, rev, "the same choice writes nothing")
	end)

	it("sees who has the addon, who lacks it and how many are not known", function()
		Mock.addons.Gargul = { loaded = true, version = "7.1" }
		I():Refresh()
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(130)
		shares(BOB, "Bob", { { "Gargul", "7.0" } })
		shares(ANN, "Ann", { { "Questie", "1.0" } })
		truthy(Lo():Set({ system = "softres", addon = "gargul" }))
		local t = text()
		has(t, "Loot system: Soft reserve")
		has(t, "Loot addon: Gargul")
		has(t, "On this client: Loaded 7.1")
		has(t, "2 of 3 members who share their list have it loaded")
		has(t, "Bob · 7.0")
		has(t, "Testchar (you) · 7.1")
		has(t, "Without it (1): Ann")
		has(t, "Not known: 1 more")
		has(t, "[copy] https://www.curseforge.com/wow/addons/gargul")
	end)

	it("looks for another addon by its folder, in any case, and says when nobody has it", function()
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(130)
		shares(BOB, "Bob", { { "myloot", "2.0" } })
		truthy(Lo():Set(OTHER))
		local t = text()
		has(t, "Loot system: Plus one")
		has(t, "Loot addon: My Loot")
		has(t, "On this client: Not installed")
		has(t, "1 of 2 members who share their list have it loaded")
		has(t, "Bob · 2.0")
		has(t, "Without it (1): Testchar")
		has(t, "[copy] " .. URL)
		truthy(Lo():Set({ addon = "other", addonName = "X", addonFolder = "Nobody", url = URL }))
		has(text(), "No member who shares their list has an addon in the folder Nobody.")
	end)

	it("says the state of the addon on this client", function()
		truthy(Lo():Set({ addon = "raidcore" }))
		has(text(), "On this client: Folder not confirmed")
		Mock.addons.RaidCore = { loaded = false, enabled = false }
		I():Refresh()
		has(text(), "On this client: Not loaded")
		truthy(Lo():Set({ addon = "fdcp" }))
		has(text(), "On this client: Not installed")
	end)

	it("says one line instead of a table while nobody shares or the census is off", function()
		truthy(Lo():Set({ addon = "gargul" }))
		A().Config:Set("account.settings.shareAddons", false)
		local t = text()
		has(t, L("ADDONS_NOBODY")); has(t, L("ADDONS_NOT_SHARING"))
		lacks(t, "have it loaded")
		A().Features.census = false
		t = text()
		has(t, L("INTEG_CENSUS_OFF"))
		lacks(t, "have it loaded")
	end)

	it("without an addon checks nothing and gets the suggestion, a text of the interface", function()
		local asked = 0
		for _, name in ipairs({ "Who", "Without", "Count", "Summary", "Unknown" }) do
			local original = A().Census[name]
			A().Census[name] = function(...) asked = asked + 1 return original(...) end
		end
		local detect = I().Holders
		I().Holders = function(...) asked = asked + 1 return detect(...) end
		local t = text()
		has(t, "Loot system: Not set")
		has(t, L("LOOT_SUGGEST_FDCP"))
		has(t, "[copy] https://github.com/Finland6738/finland-dragon-credit-points/releases")
		has(t, "[button] fdcp"); has(t, "[button] pick")
		lacks(t, "Loot addon:"); lacks(t, "On this client"); lacks(t, "Who has it")
		eq(asked, 0)
		isNil(S():Get("guildcfg", "loot"), "the suggestion is not guild data")
		isNil(S():Get("handbook", "P:loot"))
	end)

	it("shows FDCP's credits and rules beside the page, never in its text", function()
		page("loot", "# Loot system")
		Mock.addons.FinlandDragonCreditPoints = { loaded = true, version = "1.0.2" }
		FinlandDragonCreditPointsAPI = {
			API_VERSION = 1, IsReady = function() return true end, GetSource = function() return "LEDGER" end,
			GetCredits = function() return { name = "Testchar", credits = 7, place = 2, of = 9 } end,
			GetRules = function() return { source = "GUILD", preset = "PATTO", costs = {} } end,
			RegisterCallback = function() return true end, UnregisterCallback = function() return true end,
		}
		I():Refresh()
		truthy(Lo():Set({ addon = "fdcp" }))
		local t = text()
		has(t, "You: 7 credits, place 2 of 9 in the loot queue")
		has(t, "Preset: Patto")
		has(t, "[button] open")
		eq(S():Get("handbook", "P:loot").body, "# Loot system")
		-- level 0: status, version and "Open FDCP" only
		FinlandDragonCreditPointsAPI.API_VERSION = 2
		I():Refresh()
		t = text()
		has(t, "On this client: Loaded 1.0.2"); has(t, "[button] open")
		lacks(t, "credits"); lacks(t, "Preset")
		FinlandDragonCreditPointsAPI = nil
		Mock.addons.FinlandDragonCreditPoints = nil
		I():Refresh()
		t = text()
		has(t, "On this client: Not installed"); has(t, "[copy] https://github.com/")
		lacks(t, "[button] open")
		eq(#Mock.errors, 0)
	end)
end)

describe("a member reads", function()
	before_boot(member)

	it("sees nothing at all while nothing is chosen", function()
		eq(#lines(), 0)
	end)

	it("sees the counts and the own row, never other names, and no controls", function()
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(130)
		shares(BOB, "Bob", { { "Gargul", "7.0" } })
		receive({ system = "rolls", addon = "gargul" })
		local t = text("addon")
		has(t, "Loot system: Rolls (MS/OS)")
		has(t, "1 of 2 members who share their list have it loaded")
		has(t, "Testchar (you): not loaded")
		has(t, "[copy] https://www.curseforge.com/wow/addons/gargul")
		lacks(t, "Bob"); lacks(t, "Without it"); lacks(t, "Not known"); lacks(t, "[button]"); lacks(t, "[form]")
	end)

	it("sees no suggestion and no address without an addon", function()
		receive({ system = "dkp" })
		deepEq(lines(), { "Loot system: DKP" })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("in the Handbook view", function()
	before_boot(officer)

	local function open(id)
		truthy(A().Shell:OpenView("handbook"))
		truthy(V():Show(id))
		Mock.Advance(1)
		return V().frame
	end

	it("sits above the text of the loot page only", function()
		page("loot", "Rolls on Thursday.")
		page("rules", "Be kind.", { order = 10 })
		local f = open("P:loot")
		truthy(f.loot:IsShown())
		truthy(f.fixed >= f.loot.contentHeight and f.fixed > 0)
		eq(f.blocks[1].y, f.fixed, "the text starts under it")
		truthy(V():Show("P:rules"))
		falsy(f.loot:IsShown())
		eq(f.blocks[1].y, 0)
	end)

	it("lets an officer change the addon in a form, and refuses a foreign address there", function()
		page("loot", "Text.")
		local w = open("P:loot").loot
		w:Press("pick")
		w:ShowChoices("addon")
		truthy(A().Widgets.Menu.IsOpen())
		w:Choose("other")
		local form = w.forms.addon
		truthy(form:IsShown() and form.fields.url:IsShown())
		form.fields.addonName:SetText("My Loot")
		form.fields.addonFolder:SetText("MyLoot")
		form.fields.url:SetText("https://example.org/x")
		A().Bus:Emit("LOOT_CHANGED")
		eq(form.fields.addonName:GetText(), "My Loot", "a redraw keeps what is typed")
		falsy(w:Save())
		eq(form.error:GetText(), L("LOOT_ERR_URL"))
		form.fields.url:SetText(URL)
		truthy(w:Save())
		isNil(w.form)
		eq(Lo():Get().url, URL)
		eq(w.copy:GetText(), URL)
		w:Press("system")
		w:Choose("council")
		truthy(w:Save())
		eq(Lo():Get().system, "council"); eq(Lo():Get().addon, "other")
		eq(#Mock.errors, 0)
	end)

	it("chooses FDCP with one click", function()
		page("loot", "Text.")
		local w = open("P:loot").loot
		w:Press("fdcp")
		eq(Lo():Get().addon, "fdcp"); eq(I():Source("loot"), "fdcp")
	end)

	it("finds the system's and the addon's names with the search", function()
		page("loot", "Text.")
		open("P:loot")
		truthy(Lo():Set(OTHER))
		V():Search("my lo")
		eq(V().results[#V().results].id, "P:loot")
		V():Search("plus")
		eq(V().results[1].text, "Plus one")
		V():Search("gargul")
		eq(#V().results, 0)
	end)
end)

describe("in the Raid view", function()
	before_boot(officer)

	it("shows the fixed part there while the loot page cannot be read, and opens the page when it can", function()
		truthy(A().Shell:OpenView("raid"))
		Mock.Advance(1)
		local R = A().RaidView
		local f = R.frame
		falsy(R.LootReadable())
		R:ToggleLoot()
		truthy(f.lootPane:IsShown()); falsy(f.list:IsShown())
		f.loot:Press("fdcp")
		eq(Lo():Get().addon, "fdcp")
		eq(f.lootName:GetText(), "Finland Dragon Credit Points (FDCP)")
		R:ToggleLoot()
		falsy(f.lootPane:IsShown()); truthy(f.list:IsShown())
		R:ToggleLoot()
		page("loot", "Text.")
		falsy(f.lootPane:IsShown(), "the page can be read now")
		R:ToggleLoot()
		eq(A().Shell.selected, "handbook"); eq(V().selected, "P:loot")
		eq(#Mock.errors, 0)
	end)
end)

describe("on an Italian client", function()
	before_boot(function(M) officer(M) M.player.locale = "itIT" end)

	it("draws the page and the form in Italian", function()
		page("loot", "Testo.")
		truthy(A().Shell:OpenView("handbook"))
		truthy(V():Show("P:loot"))
		local w = V().frame.loot
		has(table.concat(lines(), "\n"), "Sistema di loot: Non indicato")
		w:Press("pick")
		w:Choose("gargul")
		truthy(w:Save())
		has(table.concat(lines(), "\n"), "Addon del loot: Gargul")
		eq(#Mock.errors, 0)
	end)
end)

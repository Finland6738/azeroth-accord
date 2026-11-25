-- The addon census (M9.9; SPEC-13 §8, SPEC-10 Q11 and Q17): what a client shares (its loaded addons, never Blizzard's,
-- cleaned and capped), when it goes out, "Share my addon list" off, the owner rule, counts over many authors, retention,
-- who sees names, the read API for the raid and loot addons, the view, the sync between clients (also with a client that
-- does not know the census) and the traffic budget of SPEC-02 §4. With the switch `census` off nothing of it exists.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function C() return AzerothAccord.Census end
local function View() return AzerothAccord.GuildAddonsView end
local function Shell() return AzerothAccord.Shell end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"
local DAY = 86400

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 30, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
	} }
end

local function installed(Mk)
	Mk.addons.Questie = { loaded = true, version = "9.1.0", title = "|cff33ff99Questie|r" }
	Mk.addons.Details = { loaded = true, version = "", title = "|TInterface\\Icons\\x:0|t Details! Damage Meter" }
	Mk.addons.Gargul = { loaded = true, version = "7.1" }
	Mk.addons.Blizzard_AuctionUI = { loaded = true, security = "SECURE" }
	Mk.addons.Blizzard_Insecure = { loaded = true }
	Mk.addons.SecureThing = { loaded = true, security = "SECURE" }
	Mk.addons.Sleeping = { loaded = false, version = "1.0" }
end

local function on(rank)
	return function(Mk)
		Mk.features = { census = true }
		guild(rank)
		installed(Mk)
	end
end
local function off(Mk) Mk.features = { census = false } guild(3) installed(Mk) end

-- Every message handed to the transport from now on.
local function capture()
	local out, T_ = {}, A().Transport
	local original = T_.Send
	T_.Send = function(self, dist, msg, opts)
		out[#out + 1] = { dist = dist, msg = msg, target = opts and opts.target }
		return original(self, dist, msg, opts)
	end
	return out
end

local function censusSent(list)
	local out = {}
	for _, e in ipairs(list) do
		if e.msg.t == "REC" and e.msg.s == "addons" then
			for _, rec in ipairs(e.msg.r) do out[#out + 1] = rec end
		end
	end
	return out
end

-- The first HELLO of the session, then long enough for the first check.
local function login()
	A().Bus:Emit("SYNC_HELLO", true)
	Mock.Advance(130)
end

local function own() return S():Get("addons", ME) end

local function folders(rec)
	local out = {}
	for i, e in ipairs(rec and rec.l or {}) do out[i] = e[1] end
	return out
end

local function record(id, entries, fields)
	local rec = { id = id, author = id, rev = 1, time = GetServerTime(), l = entries }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

local function hear(rec, sender)
	eq(S():Receive("addons", { rec }, sender, "GUILD"), 1, "the record is taken")
	Mock.Advance(2)
end

-- Two characters of one account: each one's record lists the other.
local function account(a, b)
	local records = S():Records("accounts")
	for _, g in ipairs({ a, b }) do
		records[g] = { id = g, author = g, rev = 1, time = GetServerTime(), token = "T" .. a,
			chars = { { guid = a }, { guid = b } } }
		A().Bus:Emit("STORE_CHANGED", "accounts", g, "remote")
	end
end

local function row(folder)
	for _, r in ipairs(C():Summary().rows) do
		if r.folder == folder then return r end
	end
end

local function names(list)
	local out = {}
	for i, w in ipairs(list) do out[i] = w.name end
	return table.concat(out, ",")
end

---------------------------------------------------------------------------------------------------------------------
describe("the switch `census`, off", function()
	before_boot(off)

	it("switched off: the addons are not read, the set takes and sends nothing", function()
		eq(A().Features.census, false)
		falsy(A().Features.On("census"))
		falsy(S().IsActive("addons"))
		local read = 0
		local original = C_AddOns.GetAddOnInfo
		C_AddOns.GetAddOnInfo = function(...) read = read + 1 return original(...) end
		local sent = capture()
		login()
		Mock.Fire("ADDON_LOADED", "Questie")
		A().Config:Set("account.settings.shareAddons", false)
		A().Bus:Emit("SETTINGS_CHANGED", "shareAddons")
		Mock.Advance(700)
		local ok, why = C():Publish()
		falsy(ok); eq(why, "off")
		isNil((S():Put("addons", ME, { l = { { "Questie" } } })))
		eq(S():Receive("addons", { record(BOB, { { "Questie" } }) }, "Bob", "GUILD"), 0)
		eq(S():Count("addons"), 0)
		eq(#censusSent(sent), 0)
		eq(read, 0, "the addon list is never read")
	end)

	it("sends the HELLO of v0.8.0, and ignores a census record or summary from others without counting it", function()
		local sent = capture()
		A().Sync:SendHello()
		local hello
		for _, e in ipairs(sent) do if e.msg.t == "HELLO" then hello = e.msg end end
		notNil(hello)
		isNil(hello.c)
		A().Sync:OnMessage({ t = "REC", s = "addons", r = { record(BOB, { { "Questie" } }) } }, "Bob", "GUILD")
		eq(A().Sync.state.stats.refused, 0)
		eq(S().stats.rejected, 0)
		A().Sync:OnMessage({ t = "HELLO", s = "", c = A().Sync:EncodeSummary({ { key = 5, d = 1, t = 1, extra = true } }, true) },
			"Boss", "GUILD")
		Mock.Advance(30)
		eq(A().Sync.state.stats.requests, 0)
	end)

	it("shows nothing: no tab, no command, no help line, no switch, no row in What I share, no debug section", function()
		Mock.Slash("/accord")
		for _, v in ipairs(Shell():ViewList()) do truthy(v.id ~= "addons") end
		isNil(Shell().content.tabs.buttons.addons)
		falsy(Shell():Select("addons"))
		Mock.Slash("/accord help")
		falsy(text():find("/accord addons", 1, true))
		Mock.Slash("/accord addons")
		contains(text(), "Unknown command 'addons'")
		isNil(View().frame)
		falsy(A().SettingsModel.Visible("shareAddons"))
		for _, r in ipairs(A().ShareModel.Describe()) do truthy(r.id ~= "addons") end
		truthy(Shell():OpenView("settings"))
		falsy(A().SettingsView.frame.checks.shareAddons:IsShown())
		falsy(A().Diagnostics.Report():find("Census:", 1, true))
		isNil(A().Integrations:Holders("gargul"))
		eq(#C():Summary().rows, 0)
		eq(#C():Who("Questie"), 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("what a client shares", function()
	before_boot(on(3))

	it("lists the loaded addons by folder, never Blizzard's, with cleaned titles and versions", function()
		login()
		local rec = own()
		notNil(rec)
		deepEq(folders(rec), { "AzerothAccord", "Details", "Gargul", "Questie" })
		deepEq(rec.l[2], { "Details", "", "Details! Damage Meter" })
		deepEq(rec.l[3], { "Gargul", "7.1" })
		deepEq(rec.l[4], { "Questie", "9.1.0" })   -- the title says no more than the folder
		eq(rec.l[1][3], "Azeroth Accord")
		isNil(rec.more)
		truthy(C().ValidRecord(rec))
	end)

	it("cleans a title: no colours, icons or links, one line, at most 48 characters, never cut inside a letter", function()
		eq(C().CleanTitle("|cff00ff00Bag|r|cffffffffnon|r", "x"), "Bagnon")
		eq(C().CleanTitle("|cnGREEN_FONT_COLOR:Bagnon|r", "x"), "Bagnon")
		eq(C().CleanTitle("|A:atlas:0:0|a Bag\nnon |Hlink:1|h[here]|h", "x"), "Bag non [here]")
		eq(C().CleanTitle("a || b |", "x"), "a b")
		eq(C().CleanTitle("Città", "x"), "Città")
		eq(C().CleanTitle(("é"):rep(60), "x"), ("é"):rep(48))
		isNil(C().CleanTitle("Questie", "Questie"))
		isNil(C().CleanTitle("|cff00ff00|r", "x"))
		isNil(C().CleanTitle(nil, "x"))
		eq(C().CleanVersion("|cff00ff00v1.2|r"), "v1.2")
		isNil(C().CleanVersion(("1"):rep(41)))
	end)

	it("keeps the first 120 by folder and says how many it left out", function()
		for i = 1, 200 do Mock.addons[("a%03d"):format(i)] = { loaded = true } end
		for _, f in ipairs({ "Questie", "Details", "Gargul" }) do Mock.addons[f] = nil end
		login()
		local rec = own()
		eq(#rec.l, 120)
		eq(rec.more, 201 - 120)
		eq(rec.l[1][1], "AzerothAccord"); eq(rec.l[120][1], "a119")
		truthy(C().ValidRecord(rec))
	end)

	it("cuts long lists at the size limit of the set, and others accept the record", function()
		for i = 1, 150 do
			Mock.addons[("VeryLongAddonFolderName%03d"):format(i)] =
				{ loaded = true, version = "10.2.7-release", title = "A rather long addon title " .. i }
		end
		login()
		local rec = own()
		truthy(#rec.l < 120, "cut by size: " .. #rec.l)
		truthy(#rec.l > 40, "still useful: " .. #rec.l)
		eq(rec.more, 154 - #rec.l)
		truthy(A().Config.EstimateSize(rec) <= S().SETS.addons.maxBytes)
		rec.rev = 100000
		truthy(A().Config.EstimateSize(rec) <= S().SETS.addons.maxBytes)
		isNil(S().ValidShape("addons", rec))
	end)

	it("publishes nothing when the client cannot list its addons", function()
		C_AddOns.GetNumAddOns = nil
		login()
		isNil(own())
		eq(select(2, C():Publish()), "api")
		eq(#C():Summary().rows, 0)
		C_AddOns.GetAddOnInfo = nil
		isNil(A().Compat.Addon.Loaded())
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("when the list goes out", function()
	before_boot(on(3))

	it("goes out 60 to 120 seconds after the first HELLO of a session, once", function()
		local sent = capture()
		Mock.Advance(300)
		isNil(own(), "nothing before the first HELLO")
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(59)
		isNil(own())
		Mock.Advance(70)
		notNil(own())
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(1000)
		local recs = censusSent(sent)
		eq(#recs, 1); eq(recs[1].id, ME); eq(recs[1].rev, 1)
	end)

	it("goes out again only when the list changed, also after a new login", function()
		login()
		Mock.Reload()
		login()
		eq(own().rev, 1, "unchanged: nothing written")
		Mock.addons.Bagnon = { loaded = true, version = "2.0" }
		Mock.Reload()
		login()
		eq(own().rev, 2)
		deepEq(folders(own()), { "AzerothAccord", "Bagnon", "Details", "Gargul", "Questie" })
		Mock.addons.Gargul.version = "7.2"
		Mock.Reload()
		login()
		eq(own().rev, 3, "another version is another list")
	end)

	it("looks again after an addon loads during the session, at most once every ten minutes", function()
		login()
		Mock.addons.Bagnon = { loaded = true }
		Mock.Fire("ADDON_LOADED", "Bagnon")
		Mock.Advance(300)
		eq(own().rev, 1, "within ten minutes of the last check")
		Mock.Advance(320)
		eq(own().rev, 2)
		Mock.Advance(700)
		Mock.addons.Late = { loaded = true }
		Mock.Fire("ADDON_LOADED", "Late")
		Mock.Fire("ADDON_LOADED", "Late")
		Mock.Advance(59)
		eq(own().rev, 2)
		Mock.Advance(2)
		eq(own().rev, 3)
	end)

	it("writes the same list again when the own record is older than 30 days", function()
		login()
		own().time = GetServerTime() - 29 * DAY
		eq(select(2, C():Publish()), "unchanged")
		own().time = GetServerTime() - 31 * DAY
		truthy(C():Publish())
		eq(own().rev, 2)
		eq(own().time, GetServerTime())
	end)

	it("publishes nothing in demo mode", function()
		Mock.Slash("/accord demo")
		login()
		eq(select(2, C():Publish()), "demo")
		Mock.Slash("/accord demo")
		isNil(own())
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("`Share my addon list`", function()
	before_boot(on(3))
	local ALT = "Player-1-0000A0A1"

	it("is on by default", function()
		eq(AzerothAccordDB.settings.shareAddons, true)
		truthy(C().Sharing())
		truthy(A().SettingsModel.Get("shareAddons"))
	end)

	it("off: one withdrawal and nothing more; on again: the list goes out", function()
		login()
		local sent = capture()
		truthy(A().ShareModel.SetSwitch("shareAddons", false))
		Mock.Advance(20)
		local rec = own()
		eq(rec.del, true); eq(rec.rev, 2); isNil(rec.l)
		Mock.addons.Bagnon = { loaded = true }
		Mock.Fire("ADDON_LOADED", "Bagnon")
		Mock.Advance(700)
		Mock.Reload()
		sent = capture()
		login()
		Mock.Advance(700)
		eq(own().rev, 2)
		eq(#censusSent(sent), 0, "nothing more after the withdrawal")
		truthy(A().SettingsModel.Set("shareAddons", true))
		Mock.Advance(20)
		eq(own().rev, 3)
		isNil(own().del)
		eq(#censusSent(sent), 1)
	end)

	it("off from the start: nothing is ever written", function()
		A().Config:Set("account.settings.shareAddons", false)
		local sent = capture()
		login()
		Mock.Advance(700)
		eq(S():Count("addons"), 0)
		eq(#censusSent(sent), 0)
	end)

	it("withdraws the lists of every character of the account, never of anybody else", function()
		account(ME, ALT)
		S():Records("addons")[ALT] = { id = ALT, author = ALT, rev = 4, time = GetServerTime(), l = { { "Questie" } } }
		hear(record(BOB, { { "Questie" } }), "Bob")
		login()
		A().SettingsModel.Set("shareAddons", false)
		Mock.Advance(20)
		eq(S():Get("addons", ALT).del, true)
		eq(S():Get("addons", ALT).rev, 5)
		eq(S():Get("addons", ALT).author, ME)
		eq(own().del, true)
		isNil(S():Get("addons", BOB).del)
	end)

	it("follows a switch that a backup brought", function()
		login()
		A().Config:Set("account.settings.shareAddons", false)
		A().Bus:Emit("SETTINGS_CHANGED", "backup")
		Mock.Advance(20)
		eq(own().del, true)
	end)

	it("withdraws a list that comes back from the guild while sharing is off", function()
		A().Config:Set("account.settings.shareAddons", false)
		login()
		Mock.Advance(700)
		local mine = record(ME, { { "Questie" } })
		eq(S():Receive("addons", { mine }, "Boss", "WHISPER"), 1)
		Mock.Advance(70)
		eq(own().del, true)
		eq(own().rev, 2)
	end)

	it("an author who turns sharing off disappears from the counts", function()
		hear(record(BOB, { { "Questie" }, { "OnlyBob" } }), "Bob")
		hear(record(ANN, { { "Questie" } }), "Ann")
		eq(C():Summary().total, 2)
		eq(row("Questie").users, 2)
		hear(record(BOB, nil, { rev = 2, del = true }), "Bob")
		eq(C():Summary().total, 1)
		eq(row("Questie").users, 1)
		eq(row("Questie").share, 100)
		isNil(row("OnlyBob"))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the owner rule and the trust rules", function()
	before_boot(on(3))

	it("accepts a well formed record and refuses every bad field", function()
		truthy(C().ValidRecord(record(BOB, { { "Questie", "1.0", "A title" }, { "b" }, { "c", "" } }, { more = 3 })))
		truthy(C().ValidRecord(record(BOB, nil, { del = true })))
		local many = {}
		for i = 1, 121 do many[i] = { "a" .. i } end
		local bad = {
			{ id = ANN }, { id = BOB .. ":1" }, { id = "x" }, { l = "x" }, { l = many }, { l = { "Questie" } },
			{ l = { { "" } } }, { l = { { ("a"):rep(65) } } }, { l = { { "a|b" } } }, { l = { { "a\nb" } } },
			{ l = { { "Blizzard_AuctionUI" } } }, { l = { { "a", ("1"):rep(41) } } }, { l = { { "a", "|cff" } } },
			{ l = { { "a", 1 } } }, { l = { { "a", "1", ("t"):rep(49) } } }, { l = { { "a", "1", "x|r" } } },
			{ l = { { "a", "1", "t", "more" } } }, { l = { { name = "a" } } }, { l = { a = { "a" } } },
			{ more = 0 }, { more = 1.5 }, { more = "3" }, { del = true }, { del = "yes" },
		}
		for i, change in ipairs(bad) do falsy(C().ValidRecord(record(BOB, { { "a" } }, change)), "bad field " .. i) end
		falsy(C().ValidRecord(record(BOB, nil)), "neither a list nor a deletion")
	end)

	it("takes a list first hand or from an officer, never from another member or from outside the guild", function()
		local rec = record(BOB, { { "Questie" } })
		eq(S():Receive("addons", { rec }, "Ann", "GUILD"), 0)
		eq(S():Receive("addons", { rec }, "Stranger", "GUILD"), 0)
		eq(S():Receive("addons", { record(ANN, { { "x" } }, { author = BOB }) }, "Bob", "GUILD"), 0)
		isNil(S():Get("addons", BOB))
		eq(S():Receive("addons", { rec }, "Boss", "WHISPER"), 1, "an officer relays")
		eq(S():Receive("addons", { record(ANN, { { "x" } }) }, "Ann", "GUILD"), 1)
	end)

	it("keeps a list 60 days, and counts it no longer", function()
		eq(S():Receive("addons", { record(BOB, { { "Old" } }, { time = GetServerTime() - 61 * DAY }) }, "Bob", "GUILD"), 0)
		hear(record(BOB, { { "Old" } }, { time = GetServerTime() - 59 * DAY }), "Bob")
		hear(record(ANN, { { "New" } }), "Ann")
		eq(C():Summary().total, 2)
		Mock.SetServerTime(GetServerTime() + 2 * DAY)
		C():Changed()
		eq(C():Summary().total, 1, "not counted any more, also before it is removed")
		eq(S():Prune(), 1)
		isNil(S():Get("addons", BOB))
		notNil(S():Get("addons", ANN))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- A guild of 30 members with the addon: all have Questie (20 the newer version), every second one DBM.
local function crowd(Mk)
	Mk.features = { census = true }
	local members = {}
	for i = 1, 30 do
		members[i] = { name = ("M%02d"):format(i), level = 60, class = "MAGE", rank = 3, guid = ("Player-1-%08X"):format(0x100 + i),
			online = true }
	end
	Mk.guild.Set{ name = "Accord", myRank = 3, members = members }
end

local function member(i) return ("Player-1-%08X"):format(0x100 + i) end

local function fillCrowd()
	for i = 1, 30 do
		local l = { { "Questie", i <= 20 and "9.1" or "9.0", "Questie Quests" } }
		if i % 2 == 0 then l[2] = { "DBM-Core", "1.2" } end
		if i == 7 then l[#l + 1] = { "Rare" } end
		eq(S():Receive("addons", { record(member(i), l) }, ("M%02d"):format(i), "GUILD"), 1)
	end
	Mock.Advance(2)
end

describe("the counts", function()
	before_boot(crowd)

	it("count accounts over many authors, with shares and versions", function()
		fillCrowd()
		local s = C():Summary()
		eq(s.total, 30); eq(s.own, false)
		eq(#s.rows, 3)
		local q = row("Questie")
		eq(q.users, 30); eq(q.share, 100); eq(q.name, "Questie Quests")
		deepEq(q.versions, { { version = "9.1", n = 20 }, { version = "9.0", n = 10 } })
		eq(row("DBM-Core").users, 15); eq(row("DBM-Core").share, 50); eq(row("DBM-Core").name, "DBM-Core")
		eq(row("Rare").users, 1); eq(row("Rare").share, 3)
		deepEq(row("Rare").versions, { { n = 1 } })
	end)

	it("count the alts of one account once, with the version of the newest list", function()
		fillCrowd()
		account(member(1), member(2))
		Mock.Advance(2)
		eq(C():Summary().total, 29)
		eq(row("Questie").users, 29)
		eq(row("DBM-Core").users, 15, "one of the two has it")
		Mock.Advance(5)
		hear(record(member(1), { { "Questie", "9.9" } }, { rev = 2 }), "M01")
		local q = row("Questie")
		eq(q.users, 29)
		eq(q.versions[3].version, "9.9"); eq(q.versions[3].n, 1)
		eq(q.versions[1].n, 18)
	end)

	it("replace a changed list", function()
		fillCrowd()
		hear(record(member(7), { { "Newer" } }, { rev = 2 }), "M07")
		isNil(row("Rare"))
		eq(row("Newer").users, 1)
		eq(row("Questie").users, 29)
	end)

	it("leave out who is not in the guild any more", function()
		fillCrowd()
		S():Records("addons")["Player-1-0000FFFF"] = record("Player-1-0000FFFF", { { "Ghost" } })
		C():Changed()
		eq(C():Summary().total, 30)
		isNil(row("Ghost"))
	end)

	it("announce a change once, a second later", function()
		local n = 0
		A().Bus:On("CENSUS_CHANGED", function() n = n + 1 end)
		Mock.Advance(5)
		n = 0
		fillCrowd()
		Mock.Advance(5)
		eq(n, 1)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
local function lists()
	hear(record(BOB, { { "Questie", "9.0" }, { "Gargul", "7.0" } }), "Bob")
	hear(record(ANN, { { "Questie", "9.1.0" } }), "Ann")
end

describe("who sees names (SPEC-10 Q11): a member", function()
	before_boot(on(3))

	it("sees counts but no names, except its own entry", function()
		lists()
		login()
		eq(row("Gargul").users, 2)
		truthy(row("Gargul").mine)
		falsy(C().CanSeeNames())
		local mine = C():Who("Gargul")
		eq(#mine, 1); eq(mine[1].name, "Testchar"); truthy(mine[1].own); truthy(mine[1].shared); eq(mine[1].version, "7.1")
		eq(#C():Who("Questie"), 1)
		for _, r in ipairs(C():Summary().rows) do
			isNil(r.accounts); isNil(r.chars)
		end
		eq(C().NAMES_VISIBLE_TO, "officers")
		C().NAMES_VISIBLE_TO = "members"
		eq(names(C():Who("Gargul")), "Bob,Testchar")
		C().NAMES_VISIBLE_TO = "officers"
	end)

	it("always sees its own, also when it does not share (and is not counted)", function()
		lists()
		A().Config:Set("account.settings.shareAddons", false)
		eq(row("Gargul").users, 1)
		falsy(row("Gargul").mine); truthy(row("Gargul").here)
		local mine = C():Who("Gargul")
		eq(#mine, 1); truthy(mine[1].own); falsy(mine[1].shared)
		eq(#C():Who("Nothing"), 0)
	end)

	it("reads the known raid and loot addons through Integrations:Holders", function()
		lists()
		local list, n, total = A().Integrations:Holders("gargul")
		eq(n, 1); eq(total, 2)
		eq(#list, 1); truthy(list[1].own, "a member gets only its own entry")
		isNil(A().Integrations:Holders("unknown"))
	end)
end)

describe("who sees names (SPEC-10 Q11): an officer", function()
	before_boot(on(1))

	it("sees everybody who uses an addon, with the characters and the version", function()
		lists()
		login()
		truthy(C().CanSeeNames())
		local who = C():Who("Gargul")
		eq(names(who), "Bob,Testchar")
		eq(who[1].version, "7.0"); deepEq(who[1].chars, { "Bob" }); falsy(who[1].own)
		truthy(who[2].own)
		local list, n, total = A().Integrations:Holders("gargul")
		eq(n, 2); eq(total, 3); eq(#list, 2)
	end)

	it("groups an account under its main, with the characters that list the addon", function()
		lists()
		account(BOB, ANN)
		Mock.Advance(2)
		local who = C():Who("Questie")
		eq(#who, 2, "the account of Bob and Ann, and this client's own copy, not shared yet")
		eq(who[1].name, "Ann")   -- the main: the highest level
		deepEq(who[1].chars, { "Ann", "Bob" })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
local function open()
	truthy(Shell():OpenView("addons"))
	Mock.Advance(2)
	return View().frame
end

local function shownFolders()
	local out = {}
	for i, r in ipairs(View().frame.table:GetData()) do out[i] = r.folder end
	return out
end

describe("the Guild addons view", function()
	before_boot(on(1))

	it("shows the denominator and the table, most used first, sorted by any column", function()
		lists()
		Mock.Slash("/accord help")
		contains(text(), "/accord addons")
		Mock.Slash("/accord addons")
		eq(Shell().selected, "addons")
		isNil(Shell().views.addons.failed)
		local f = open()
		eq(f.sentence:GetText(), "Out of 2 members who run Accord and share their list.")
		deepEq(shownFolders(), { "Questie", "Gargul" })
		f.table:SortBy("name", false)
		deepEq(shownFolders(), { "Gargul", "Questie" })
		f.table:SortBy("users", false)
		deepEq(shownFolders(), { "Gargul", "Questie" })
		f.table:SortBy("share", true)
		deepEq(shownFolders(), { "Questie", "Gargul" })
		f.table:SortBy("versions", false)
		deepEq(shownFolders(), { "Gargul", "Questie" })
		eq(View().Text(row("Questie"), "versions"), "9.1.0 (+1)")
		eq(View().Text(row("Questie"), "share"), "100%")
		contains(table.concat({ View().TipLines(row("Gargul"))[2].text }, ""), "Folder: Gargul")
	end)

	it("follows the search box and a new list", function()
		lists()
		local f = open()
		View():Search("garg")
		deepEq(shownFolders(), { "Gargul" })
		View():Search("zzz")
		eq(#f.table:GetData(), 0)
		View():Search("")
		hear(record(OFF, { { "Fresh" } }), "Boss")
		eq(#f.table:GetData(), 3)
		eq(f.sentence:GetText(), "Out of 3 members who run Accord and share their list.")
	end)

	it("says so when nobody shares yet, and when this account does not", function()
		local f = open()
		eq(f.sentence:GetText(), "Nobody in the guild shares an addon list yet.")
		falsy(f.note:IsShown())
		A().SettingsModel.Set("shareAddons", false)
		truthy(f.note:IsShown())
		hear(record(BOB, { { "Questie" } }), "Bob")
		eq(f.sentence:GetText(), "Out of 1 member who runs Accord and shares their list.")
	end)

	it("shows who uses an addon to an officer, and closes again", function()
		lists()
		local f = open()
		falsy(f.detail:IsShown())
		View():Choose("Gargul")
		truthy(f.detail:IsShown())
		contains(f.detail.title:GetText(), "Who uses Gargul")
		local rows = f.detail.table:GetData()
		eq(#rows, 2)
		eq(rows[1].name, "Bob"); eq(rows[1].version, "7.0")
		contains(rows[2].name, "not counted")
		View():Choose("Gargul")
		falsy(f.detail:IsShown())
	end)

	it("has its switch in Settings and its card in What I share", function()
		login()
		truthy(Shell():OpenView("settings"))
		local settings = A().SettingsView.frame
		truthy(settings.checks.shareAddons:IsShown())
		truthy(settings.checks.shareAddons:GetChecked())
		settings.checks.shareAddons:Click()
		eq(AzerothAccordDB.settings.shareAddons, false)
		Mock.Advance(20)
		local found
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "addons" then found = r end end
		notNil(found)
		eq(found.switch, "shareAddons"); eq(found.on, false)
		eq(found.switchLabel, "Share my addon list")
		contains(found.lines[1], "Withdrawn")
		notNil(found.note)
		A().ShareModel.SetSwitch("shareAddons", true)
		Mock.Advance(20)
		for _, r in ipairs(A().ShareModel.Describe()) do if r.id == "addons" then found = r end end
		eq(found.lines[1], "Addons in the list: 4")
		contains(found.lines[2], "Azeroth Accord")
		contains(found.lines[#found.lines], "only officers see who")
		A().SettingsView:ShowPage(settings, "share")
		eq(#Mock.errors, 0)
	end)

	it("adds a line to /accord debug without any name", function()
		lists()
		login()
		local report = A().Diagnostics.Report()
		contains(report, "Census:")
		contains(report, "own list 4 addon(s)")
	end)
end)

describe("the Guild addons view of a member", function()
	before_boot(on(3))

	it("shows only the own entry under a row", function()
		lists()
		login()
		local f = open()
		View():Choose("Questie")
		contains(f.detail.title:GetText(), "your entry")
		eq(#f.detail.table:GetData(), 1)
		contains(f.detail.note:GetText(), "Only officers")
		hear(record(OFF, { { "Theirs" } }), "Boss")
		View():Choose("Theirs")
		eq(#f.detail.table:GetData(), 0)
		contains(f.detail.note:GetText(), "You do not use it")
	end)

	it("shows the invented guild's addons in demo mode, without this computer's own", function()
		Mock.addons.OnlyOnThisComputer = { loaded = true }
		Mock.Slash("/accord demo")
		local f = open()
		truthy(#f.table:GetData() >= 5)
		truthy(C():Summary().total >= 10)
		truthy(row("Questie").mine)
		isNil(row("OnlyOnThisComputer"))
		for _, r in ipairs(C():Summary().rows) do falsy(r.here, "the player's real addons stay out of the demo") end
		Mock.Slash("/accord demo")
		Mock.Advance(2)
		eq(#C():Summary().rows, 0)
	end)

	it("runs in Italian", function()
		T.boot(function(Mk) Mk.player.locale = "itIT" end)
		lists()
		local f = open()
		eq(f.sentence:GetText(), "Su 2 membri che usano Accord e condividono l'elenco.")
		View():Choose("Questie")
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator: client i has Common, Own<i> and (the odd ones) Gargul.
local function simulated(Mk, i)
	Mk.features = { census = true }
	Mk.addons.Common = { loaded = true, version = "1." .. (i % 3) }
	Mk.addons["Own" .. i] = { loaded = true }
	if i % 2 == 1 then Mk.addons.Gargul = { loaded = true, version = "7.1" } end
end

local function holds(sim, i, j)
	return sim:client(i):addon().Store:Get("addons", Sim.guidOf(j))
end

local function everyoneHolds(sim, list, of)
	for _, i in ipairs(list) do
		for _, j in ipairs(of) do
			if not holds(sim, i, j) then return false end
		end
	end
	return true
end

-- Every census message each client hands to its transport.
local function watchWire(sim)
	local seen = {}
	for i, c in ipairs(sim.clients) do
		local T_ = c:addon().Transport
		local original = T_.Send
		T_.Send = function(self, dist, msg, opts)
			if msg.t == "REC" and msg.s == "addons" then
				seen[#seen + 1] = { from = i, dist = dist, target = opts and opts.target }
			end
			return original(self, dist, msg, opts)
		end
	end
	return seen
end

describe("the census between clients", function()
	it("reaches everyone, and whoever comes later: from the authors, and from an officer for who is offline", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 5 }, setup = simulated, latency = { 0.05, 0.3 }, seed = 31 }
		sim:advance(200)
		truthy(everyoneHolds(sim, { 1, 2, 3, 4 }, { 1, 2, 3, 4 }))
		sim:client(4):logout()
		sim:client(5):login()
		local ok = sim:advanceUntil(function() return everyoneHolds(sim, { 1, 2, 3, 5 }, { 1, 2, 3, 4, 5 }) end, 300)
		truthy(ok, "the newcomer holds every list, the offline member's too")
		local c = sim:client(5):addon()
		eq(c.Census:Summary().total, 5)
		local n, total = c.Census:Count("Gargul")
		eq(n, 3); eq(total, 5)
		-- in step: nothing of the census travels any more
		sim:advance(120)
		local seen = watchWire(sim)
		sim:advance(45 * 60)
		eq(#seen, 0)
		for i = 1, 5 do
			if sim:client(i).online then eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i) end
		end
	end)

	it("works with block summaries too, in a BHELLO that stays under 512 B", function()
		local sim = Sim.new{ clients = 4, officers = { 1 }, offline = { 4 }, setup = simulated, seed = 37 }
		for i = 1, 3 do sim:client(i):addon().Sync.BLOCK_OVER = 0 end
		for i = 1, 3 do
			local guid = Sim.guidOf(i)
			sim:client(i):addon().Store:Put("accounts", guid, { token = "T" .. i, chars = { { guid = guid } } })
		end
		sim:advance(200)
		truthy(everyoneHolds(sim, { 1, 2, 3 }, { 1, 2, 3 }))
		sim:client(3):logout()
		sim:client(4):login()
		sim:client(4):addon().Sync.BLOCK_OVER = -1   -- it holds nobody yet: blocks all the same
		local ok = sim:advanceUntil(function() return everyoneHolds(sim, { 1, 2, 4 }, { 1, 2, 3 }) end, 25 * 60)
		truthy(ok, "the DIGEST brought the lists, the offline author's too")
		truthy(sim:client(1):addon().Sync.state.stats.digestsSent >= 1)
		-- a BHELLO of a large guild, with both summaries
		local A1 = sim:client(1):addon()
		local groups = {}
		for i = 1, 1000 do
			local guid = ("Player-1-%08X"):format(0x50000 + i)
			groups[guid] = { key = A1.Sync.KeyOf(guid), d = i * 7919 % 16777216, t = 1767225600 + i, author = guid }
			local extra = A1.Sync.ExtraName(guid)
			groups[extra] = { key = A1.Sync.KeyOf(extra), d = i * 104729 % 16777216, t = 1767225600 + i, author = guid, extra = true }
		end
		local msg = { b = A1.Sync:EncodeBlocks(groups), cb = A1.Sync:EncodeBlocks(groups, true), n = 1000, av = "0.9.0" }
		eq(#msg.b, 288); eq(#msg.cb, 36)
		local wire = A1.Codec:Encode("BHELLO", msg)
		T.log(("census: a BHELLO with both summaries is %d B"):format(#wire))
		truthy(#wire <= 512, "BHELLO " .. #wire)
	end)

	it("leaves a client that does not know the census as before: same summaries, nothing pushed, asked or refused", function()
		-- client 4 runs with the switch off, as v0.8.0 does not know the set at all
		local function mixed(Mk, i) if i < 4 then simulated(Mk, i) else Mk.features = { census = false } end end
		local sim = Sim.new{ clients = 4, officers = { 1 }, setup = mixed, seed = 41 }
		local seen = watchWire(sim)
		for i = 1, 4 do
			local guid = Sim.guidOf(i)
			sim:client(i):addon().Store:Put("accounts", guid, { token = "T" .. i, chars = { { guid = guid } } })
		end
		sim:advance(300)
		truthy(everyoneHolds(sim, { 1, 2, 3 }, { 1, 2, 3 }))
		local old = sim:client(4):addon()
		eq(old.Store:Count("addons"), 0)
		local summary = old.Sync:EncodeSummary()
		for i = 1, 3 do eq(sim:client(i):addon().Sync:EncodeSummary(), summary, "the older sets compare the same, client " .. i) end
		-- the old client logs in again, so it says HELLO to everybody, and then 45 quiet minutes
		for k = #seen, 1, -1 do seen[k] = nil end
		local pushes = 0
		for i = 1, 3 do pushes = pushes + sim:client(i):addon().Sync.state.stats.pushes end
		sim:client(4):logout()
		sim:client(4):login()
		sim:advance(45 * 60)
		eq(#seen, 0, "no census record sent to it or because of it")
		local after, asked = 0, 0
		for i = 1, 3 do after = after + sim:client(i):addon().Sync.state.stats.pushes end
		asked = sim:client(4):addon().Sync.state.stats.requests
		eq(after, pushes, "nobody pushed anything to it")
		eq(asked, 0, "and it asked for nothing")
		for i = 1, 4 do
			local c = sim:client(i):addon()
			eq(c.Store.stats.rejected, 0, "client " .. i)
			eq(c.Sync.state.stats.quarantined, 0)
		end
	end)

	it("sends nothing of the census with the switch off", function()
		local sim = Sim.new{ clients = 3, setup = function(Mk, i) simulated(Mk, i) Mk.features = { census = false } end, seed = 43 }
		local seen = watchWire(sim)
		sim:advance(600)
		eq(#seen, 0)
		for i = 1, 3 do eq(sim:client(i):addon().Store:Count("addons"), 0) end
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the census in the traffic budget (SPEC-02 §4)", function()
	it("50 clients with 60 to 110 addons each, logins, logouts and changed lists stay inside the limits", function()
		local N, OFFICERS = 50, { 1, 11, 21, 31, 41 }
		local function setup(Mk, i)
			Mk.features = { census = true }
			-- addon names and versions most players share, and some of their own
			for k = 1, 60 + (i * 7) % 51 do
				local common = k <= 40
				local name = common and ("CommonAddon%02d"):format(k) or ("Addon%02d-%02d"):format(i, k)
				Mk.addons[name] = { loaded = true, version = ("%d.%d.%d"):format(k % 11, (i + k) % 7, k),
					title = "The " .. name:lower() }
			end
		end
		local sim = Sim.new{ clients = N, officers = OFFICERS, setup = setup, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42 }
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		local function everyList()
			for i = 1, N do
				local mine = holds(sim, i, i)
				if not mine then return false end
				for j = 1, N do
					local c = sim:client(j)
					if c.online then
						local seen = holds(sim, j, i)
						if not seen or seen.rev ~= mine.rev then return false end
					end
				end
			end
			return true
		end
		sim:resetStats()
		truthy(sim:advanceUntil(everyList, 40 * 60), "the first lists reach everyone")
		local first = sim:stats().sent.bytes
		sim:advance(120)
		sim:resetStats()

		-- 45 minutes: logins and logouts; now and then somebody comes back with one more addon
		local extra = 0
		for _ = 1, 90 do
			for i = 1, N do
				local c = sim:client(i)
				local r = rand()
				if c.online then
					if r < 0.03 then c:logout() end
				elseif r < 0.06 then
					if rand() < 0.1 then
						extra = extra + 1
						c.Mock.addons["Added" .. extra] = { loaded = true, version = "1.0" }
					end
					c:login()
				end
			end
			sim:advance(30)
		end
		local churn = sim:stats()
		for i = 1, N do
			local c = sim:client(i)
			if not c.online then c:login() sim:advance(2.5) end
		end
		truthy(sim:advanceUntil(everyList, 40 * 60), "everyone holds the newest lists")
		sim:advance(120)
		sim:resetStats()
		sim:advance(25 * 60)
		local steady = sim:stats()
		local record = holds(sim, 1, 1)
		T.log(("census: first lists %.0f KB for the guild (%d entries in client 1's record, %d B estimated); churn %.0f B/min average, %.0f busiest; steady %.0f / %.0f B/min")
			:format(first / 1024, #record.l, sim:client(1):addon().Config.EstimateSize(record), churn.avg.bytesPerMinute,
				churn.max.bytesPerMinute, steady.avg.bytesPerMinute, steady.max.bytesPerMinute))
		truthy(churn.avg.bytesPerMinute <= 400, "churn average " .. churn.avg.bytesPerMinute)
		truthy(churn.max.bytesPerMinute <= 2048, "churn busiest client " .. churn.max.bytesPerMinute)
		truthy(steady.avg.bytesPerMinute <= 100, "steady average " .. steady.avg.bytesPerMinute)
		truthy(steady.max.bytesPerMinute <= 200, "steady busiest client " .. steady.max.bytesPerMinute)
		for _, c in ipairs(sim.clients) do
			eq((c:addon().Sync.state.stats.quarantined or 0) + (c:addon().Transport:Stats().quarantined or 0), 0)
		end
	end)
end)

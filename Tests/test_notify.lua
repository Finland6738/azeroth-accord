-- The notification centre (M9.3; SPEC-13 §3): the two bank options of M5 work as before, with the switch `actions` off
-- and on; a kind or a module switched off puts out nothing and still adds to the history; read and unread; chat line,
-- toast and sound per module; the limits of the history (NTF-03) and of the floods (NTF-04 to NTF-08).
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Notify() return AzerothAccord.Notify end
local function M() return AzerothAccord.SettingsModel end
local function View() return AzerothAccord.ActionsView end
local function Toast() return AzerothAccord.Toast end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"
local LINEN = 2589
local DAY = 86400

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 1, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function items(Mk)
	Mk.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
	Mk.items.cached[LINEN] = true
end

local function on(Mk) Mk.features = { actions = true } guild(1) items(Mk) end
local function off(Mk) guild(1) items(Mk) end

-- The window of the login (NTF-05) is over.
local function late() Mock.Advance(Notify().LOGIN_MAX + 5) end
local function wait() Mock.Advance(Notify().NOTICE_WAIT + 1) end

-- A bank request as the sync would store it, announced on the Bus.
local function request(requester, n, status, extra)
	local id = requester .. ":" .. n
	local t = GetServerTime()
	local rec = { id = id, author = requester, rev = 1, time = t, requester = requester, kind = "withdraw", status = status or "open",
		itemID = LINEN, count = 20, created = t, history = { { s = "open", by = requester, t = t } } }
	if rec.status ~= "open" then
		rec.author, rec.rev = OFF, 2
		rec.history[2] = { s = rec.status, by = OFF, t = t }
	end
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("bankreq")[id] = rec
	A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
	return id
end

local function lines(pattern)
	local n = 0
	for _, line in ipairs(Mock.PlainOutput()) do
		if line:find(pattern, 1, true) then n = n + 1 end
	end
	return n
end

local function entries() return Notify():Entries() end

-- A module of the test, so the limits are tried without records.
local function module(id, level)
	truthy(Notify():Register(id, { label = "ACT_PROVIDER_BANK", order = 90,
		kinds = { { id = "x", level = level or "normal", group = "NOTICE_BANK_OFFICER_MANY" } } }))
	local all = A().Config.db.account.settings.notify
	all[id] = { chat = true, toast = false, sound = false, off = {} }
end

local function post(id, n, extra)
	local def = { key = id .. n, text = "BANKNOTE_NEW", args = { "N" .. n, "thing" } }
	for k, v in pairs(extra or {}) do def[k] = v end
	return Notify():Post(id, "x", def)
end

describe("with the switch off, as released", function()
	before_boot(off)

	it("prints the bank notices of M5 itself, with the same options", function()
		request(BOB, 1)
		wait()
		contains(text(), "New bank request from Bob: Linen Cloth x20.")
		contains(text(), "Azeroth Accord")
		falsy(text():find("Accord: New", 1, true))
		Mock.ClearOutput()
		M().Set("notifyOfficer", false)
		request(BOB, 2)
		wait()
		falsy(text():find("New bank request", 1, true))
		request(ME, 1)
		request(ME, 1, "rejected", { note = "out of stock" })
		wait()
		contains(text(), "Your bank request (Linen Cloth x20) was rejected by Boss. Reason: out of stock")
		Mock.ClearOutput()
		M().Set("notifyDecision", false)
		request(ME, 2)
		request(ME, 2, "approved")
		wait()
		falsy(text():find("approved", 1, true))
	end)

	it("keeps no history, makes no toast and no sound, and its book stays where M5 keeps it", function()
		request(BOB, 1)
		wait()
		local data = A().GuildKey:Data()
		isNil(data.notify)
		eq(data.bank.seen[BOB .. ":1"], "open")
		isNil(Notify():Post("bank", "officer", { text = "BANKNOTE_NEW", args = { "a", "b" } }))
		eq(#entries(), 0)
		isNil(Toast().frame)
		eq(#Mock.sounds, 0)
		falsy(A().Diagnostics.Report():find("Notify:", 1, true))
	end)

	it("shows the Notifications card of M5: the two switches and its note", function()
		Mock.Slash("/accord settings")
		local f = A().SettingsView.frame
		truthy(f.checks.notifyOfficer:IsShown())
		truthy(f.checks.notifyDecision:IsShown())
		falsy(f.noticeHeads.bank:IsShown())
		for _, check in pairs(f.noticeOutputs.bank) do falsy(check:IsShown()) end
		contains(f.noticeNote:GetText(), "These are chat lines only.")
	end)
end)

describe("the bank notices through the centre", function()
	before_boot(function(Mk) on(Mk) end)

	it("by default are one chat line, the words of M5, after Accord:", function()
		late()
		request(BOB, 1)
		wait()
		contains(text(), "Accord: New bank request from Bob: Linen Cloth x20.")
		eq(lines("New bank request"), 1)
		eq(#entries(), 1)
		local e = entries()[1]
		eq(e.module, "bank"); eq(e.kind, "officer"); eq(e.level, "normal"); falsy(e.read); isNil(e.muted); eq(e.char, ME)
		isNil(Toast().frame, "no toast by default")
		eq(#Mock.sounds, 0, "no sound by default")
		eq(A().GuildKey:Data().notify.seen.bank[BOB .. ":1"], "open")
	end)

	it("tell the requester a decision, with the reason of a rejection", function()
		late()
		request(ME, 1)
		request(ME, 1, "approved")
		request(ME, 1, "fulfilled", { rev = 3 })
		request(ME, 2)
		request(ME, 2, "rejected", { note = "out of stock" })
		wait()
		contains(text(), "Your bank request (Linen Cloth x20) was approved by Boss.")
		contains(text(), "was marked as fulfilled by Boss.")
		contains(text(), "was rejected by Boss. Reason: out of stock")
		eq(#entries(), 3)
		isNil(entries()[1].char, "for the whole account")
	end)

	it("an officer's option switched off puts out nothing and still adds to the history", function()
		late()
		M().Set("notifyOfficer", false)
		request(BOB, 1)
		wait()
		falsy(text():find("New bank request", 1, true))
		eq(#entries(), 1)
		truthy(entries()[1].muted)
		eq(Notify():Unread(), 1)
		eq(A().BankInbox.PendingCount(), 1, "the counter still counts what waits")
	end)

	it("the decision option switched off does the same", function()
		late()
		M().Set("notifyDecision", false)
		request(ME, 1)
		request(ME, 1, "approved")
		wait()
		falsy(text():find("approved", 1, true))
		eq(#entries(), 1)
		truthy(entries()[1].muted)
	end)

	it("a module with every output off is muted: no line, no toast, no sound, an entry", function()
		late()
		truthy(M().SetOutput("bank", "chat", false))
		request(BOB, 1)
		wait()
		falsy(text():find("New bank request", 1, true))
		isNil(Toast().frame)
		eq(#Mock.sounds, 0)
		truthy(entries()[1].muted)
	end)

	it("each output is chosen on its own", function()
		late()
		M().SetOutput("bank", "chat", false)
		M().SetOutput("bank", "toast", true)
		request(BOB, 1)
		wait()
		falsy(text():find("New bank request", 1, true))
		truthy(Toast().frame:IsShown())
		eq(Toast().frame.text:GetText(), "New bank request from Bob: Linen Cloth x20.")
		eq(#Mock.sounds, 0)
		M().SetOutput("bank", "toast", false)
		M().SetOutput("bank", "sound", true)
		Mock.Advance(20)
		request(BOB, 2)
		wait()
		falsy(text():find("New bank request", 1, true))
		falsy(Toast().frame:IsShown())
		deepEq(Mock.sounds, { SOUNDKIT.TELL_MESSAGE })
		request(BOB, 3)
		wait()
		eq(#Mock.sounds, 1, "at most one every 10 seconds")
		Mock.Advance(10)
		request(BOB, 4)
		wait()
		eq(#Mock.sounds, 2)
		M().SetOutput("bank", "chat", true)
		M().SetOutput("bank", "sound", false)
		request(BOB, 5)
		wait()
		eq(lines("New bank request"), 1)
	end)

	it("a client without the sound constant is silent", function()
		late()
		SOUNDKIT = nil
		M().SetOutput("bank", "sound", true)
		request(BOB, 1)
		wait()
		eq(#Mock.sounds, 0)
		eq(#Mock.errors, 0)
	end)

	it("one burst comes out together: three lines and the rest counted", function()
		late()
		for n = 1, 5 do request(BOB, n) end
		Mock.Advance(1)
		falsy(text():find("New bank request", 1, true))
		wait()
		eq(lines("New bank request"), 3)
		contains(text(), "Accord: and 2 more — /accord inbox")
	end)

	it("a request that is no longer open when its turn comes is not announced", function()
		late()
		request(BOB, 1)
		S():Records("bankreq")[BOB .. ":1"].status = "cancelled"
		wait()
		falsy(text():find("New bank request", 1, true))
		eq(#entries(), 1)
	end)

	it("takes over what M5 had already announced, so nothing comes back as new", function()
		late()
		local data = A().GuildKey:Data()
		data.notify = nil
		data.bank = { seen = { [BOB .. ":1"] = "open", __baseline = true }, history = {} }
		request(BOB, 1)
		wait()
		falsy(text():find("New bank request", 1, true))
		eq(#entries(), 0)
		isNil(data.bank.seen)
		eq(data.notify.seen.bank[BOB .. ":1"], "open")
		notNil(data.bank.history, "the rest of the bank table stays")
	end)

	it("the first run in a guild takes everything held as seen (NTF-04)", function()
		late()
		local id = request(BOB, 1)
		wait()
		Notify():Clear()
		local data = A().GuildKey:Data()
		data.notify, data.bank = nil, nil
		Mock.ClearOutput()
		A().BankInbox:Baseline()
		A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
		wait()
		falsy(text():find("New bank request", 1, true))
		eq(#entries(), 0)
	end)

	it("Clear guild data empties the history and keeps what was announced", function()
		late()
		request(BOB, 1)
		wait()
		truthy(M().ClearGuildData())
		eq(#entries(), 0)
		Mock.ClearOutput()
		request(BOB, 1)
		wait()
		falsy(text():find("New bank request", 1, true))
		request(BOB, 2)
		wait()
		eq(lines("New bank request"), 1)
	end)

	it("does not repeat anything after a /reload, and the history stays", function()
		late()
		request(BOB, 1)
		wait()
		Mock.Reload()
		guild(1)
		Mock.ClearOutput()
		A().Bus:Emit("STORE_CHANGED", "bankreq", BOB .. ":1", "remote")
		wait()
		falsy(text():find("New bank request", 1, true))
		eq(#entries(), 1)
		request(BOB, 2)
		wait()
		eq(lines("New bank request"), 1, "a /reload opens no login window")
	end)
end)

describe("read and unread", function()
	before_boot(on)

	it("a click marks one read and opens the bank on its request; Mark all read does the rest", function()
		late()
		request(BOB, 1)
		request(BOB, 2)
		wait()
		eq(Notify():Unread(), 2)
		local first = entries()[2]
		truthy(Notify():Open(first))
		truthy(first.read)
		eq(Notify():Unread(), 1)
		eq(A().Shell.selected, "bank")
		eq(A().BankRequestsView.focus, BOB .. ":1")
		eq(#Notify():Entries(true), 1)
		eq(Notify():MarkAllRead(), 1)
		eq(Notify():Unread(), 0)
		eq(#entries(), 2, "read entries stay")
		truthy(Notify():Clear())
		eq(#entries(), 0)
	end)

	it("shows the entries of this character and of the account, not of another character", function()
		late()
		module("t")
		post("t", 1, { char = ME })
		post("t", 2, { char = BOB })
		post("t", 3)
		eq(#entries(), 2)
		eq(Notify():Unread(), 2)
	end)

	it("an unread notice with the same key is updated, not repeated (NTF-07)", function()
		late()
		module("t")
		local a = post("t", 1)
		wait()
		Mock.ClearOutput()
		post("t", 2)
		local b = post("t", 1, { args = { "again", "thing" } })
		eq(a, b)
		wait()
		eq(#entries(), 2)
		eq(entries()[1], a, "it is the newest now")
		falsy(text():find("again", 1, true))
		Notify():MarkRead(a)
		local c = post("t", 1)
		ne(c, a)
		eq(#entries(), 3)
	end)

	it("a quiet notice is history only", function()
		late()
		module("q", "quiet")
		A().Config.db.account.settings.notify.q.sound = true
		post("q", 1)
		wait()
		falsy(text():find("N1", 1, true))
		eq(#Mock.sounds, 0)
		eq(#entries(), 1)
		isNil(entries()[1].muted)
	end)

	it("keeps 200 entries and 30 days (NTF-03)", function()
		late()
		module("q", "quiet")
		for n = 1, 210 do
			post("q", n)
			Mock.Advance(4)
		end
		eq(#A().GuildKey:Data().notify.list, 200)
		eq(entries()[200].args[1], "N11")
		A().GuildKey:Data().notify.list[1].time = GetServerTime() - 31 * DAY
		A().GuildKey:Data().notify.list[2].time = GetServerTime() - 29 * DAY
		eq(#entries(), 199)
	end)
end)

describe("the floods", function()
	before_boot(on)

	it("after the login the notices are grouped and come out when the window ends (NTF-05)", function()
		for n = 1, 5 do request(BOB, n) end
		Mock.Advance(100)
		falsy(text():find("bank request", 1, true))
		eq(#entries(), 1)
		eq(entries()[1].count, 5)
		eq(Notify().Text(entries()[1]), "5 new bank requests")
		Mock.Advance(Notify().LOGIN_MAX)
		eq(lines("5 new bank requests"), 1)
		eq(lines("New bank request from"), 0)
	end)

	it("the window ends 120 seconds after the first HELLO", function()
		Mock.Advance(10)
		A().Bus:Emit("SYNC_HELLO", true)
		request(BOB, 1)
		Mock.Advance(60)
		A().Bus:Emit("SYNC_HELLO", true)   -- a later one changes nothing
		Mock.Advance(55)
		falsy(text():find("New bank request", 1, true))
		Mock.Advance(10)
		eq(lines("New bank request from Bob"), 1, "a single notice keeps its own words")
		request(BOB, 2)
		wait()
		eq(lines("New bank request from Bob"), 2)
	end)

	it("a notice read while it waits does not come out", function()
		request(BOB, 1)
		Notify():MarkAllRead()
		Mock.Advance(Notify().LOGIN_MAX + 10)
		falsy(text():find("New bank request", 1, true))
	end)

	it("a muted kind is grouped apart and stays silent", function()
		M().Set("notifyOfficer", false)
		request(BOB, 1)
		request(BOB, 2)
		request(ME, 1)
		request(ME, 1, "approved")
		Mock.Advance(Notify().LOGIN_MAX + 10)
		falsy(text():find("new bank requests", 1, true))
		eq(lines("was approved"), 1)
		eq(#entries(), 2)
	end)

	it("more than 20 of a kind in a minute become one entry (NTF-06)", function()
		late()
		module("t")
		for n = 1, 25 do
			post("t", n)
			Mock.Advance(0.1)
		end
		eq(#entries(), 1)
		eq(entries()[1].count, 25)
		wait()
		contains(text(), "25 new bank requests")
		eq(lines("N1"), 0)
		Mock.Advance(Notify().BURST_SECONDS + 1)
		post("t", 99)
		eq(#entries(), 2)
		isNil(entries()[1].count)
	end)

	it("at most 30 notices come out in a session (NTF-08)", function()
		late()
		module("t")
		for n = 1, 33 do
			post("t", n)
			Mock.Advance(5)
		end
		eq(lines("New bank request from"), 30)
		eq(lines("More notices in /accord inbox"), 1)
		eq(#entries(), 33)
	end)
end)

describe("the toast", function()
	before_boot(on)

	local function three()
		module("t")
		A().Config.db.account.settings.notify.t = { chat = false, toast = true, sound = false, off = {} }
	end

	it("shows one at a time for six seconds, three wait and the rest are summed up", function()
		late()
		three()
		for n = 1, 6 do post("t", n) end
		wait()
		local f = Toast().frame
		contains(f.text:GetText(), "N1")
		eq(#Toast().queue, 3)
		eq(Toast().over, 2)
		Mock.Advance(Toast().SECONDS)
		contains(f.text:GetText(), "N2")
		f:GetScript("OnClick")(f, "RightButton")
		contains(f.text:GetText(), "N3")
		eq(Notify():Unread(), 6, "a right click only closes")
		f:GetScript("OnClick")(f, "RightButton")
		f:GetScript("OnClick")(f, "RightButton")
		eq(f.text:GetText(), "2 more notices")
		f:GetScript("OnClick")(f, "LeftButton")
		eq(A().Shell.selected, "actions")
		eq(View().pageId, "notices")
		falsy(f:IsShown())
	end)

	it("a click opens the view of the notice and marks it read", function()
		late()
		M().SetOutput("bank", "toast", true)
		request(BOB, 1)
		wait()
		local f = Toast().frame
		f:GetScript("OnClick")(f, "LeftButton")
		eq(A().Shell.selected, "bank")
		eq(Notify():Unread(), 0)
		falsy(f:IsShown())
	end)

	it("goes with the guild", function()
		late()
		M().SetOutput("bank", "toast", true)
		request(BOB, 1)
		wait()
		Mock.guild.Leave()
		A().Role:Refresh()
		falsy(Toast().frame:IsShown())
		eq(#Mock.errors, 0)
	end)
end)

describe("the quiet notices of officers and likes", function()
	before_boot(on)

	local function absence(guid, ahead)
		local T, t = A().Timeline, GetServerTime()
		local id = guid .. ":off"
		S():Records("absence")[id] = { id = id, author = ME, rev = 1, time = t - 20 * DAY, char = guid,
			from = T.DayOf(t - 20 * DAY), ["until"] = T.DayOf(t + ahead * DAY) }
		A().Bus:Emit("STORE_CHANGED", "absence", id, "remote")
	end

	it("an officer finds who is back in the history, once, and nothing comes out", function()
		late()
		A().Roster:MarkDirty()
		Notify():Check()
		absence(BOB, 0)
		Notify():Check()
		wait()
		eq(#entries(), 1)
		eq(entries()[1].module, "officer")
		contains(Notify().Text(entries()[1]), "Bob is back (away until ")
		falsy(text():find("is back", 1, true))
		Notify():MarkAllRead()
		Mock.Advance(Notify().TICK * 2)
		eq(#entries(), 1)
	end)

	it("likes are counted, never named, in one entry", function()
		late()
		Notify():Check()
		local function like(n)
			local p = ("%x"):format(n) .. ("0"):rep(A().Likes.PSEUDONYM_HEX - 1)
			local id = A().Likes.EntryId(p, ME)
			S():Records("likes")[id] = { id = id, author = OFF, rev = 1, time = GetServerTime(), pseudonym = p, target = ME, day = 20260101 }
			A().Bus:Emit("STORE_CHANGED", "likes", id, "remote")
		end
		like(1)
		eq(#entries(), 1)
		eq(Notify().Text(entries()[1]), "You received 1 like")
		like(2)
		like(3)
		eq(#entries(), 1)
		eq(Notify().Text(entries()[1]), "You received 3 likes")
		wait()
		falsy(text():find("received", 1, true))
	end)
end)

describe("the Notices page", function()
	before_boot(on)

	local function open()
		Mock.Slash("/accord inbox")
		truthy(View():ShowPage("notices"))
		return View().frame.holders.notices
	end

	it("has its own tab with the number of unread notices, and lists the newest first", function()
		late()
		request(BOB, 1)
		request(ANN, 1)
		M().Set("notifyOfficer", false)
		request(ANN, 2)
		local page = open()
		eq(View().frame.pager.buttons.notices.label:GetText(), "Notices (3)")
		local rows = page.table:VisibleRows()
		eq(#rows, 3)
		eq(View().NoticeText(rows[1].data, "module"), "Bank")
		eq(View().NoticeText(rows[1].data, "muted"), "muted")
		contains(View().NoticeText(rows[3].data, "text"), "Bob")
		truthy(rows[1].mark:IsShown())
	end)

	it("filters the unread ones, marks all read and clears after a second click", function()
		late()
		request(BOB, 1)
		request(ANN, 1)
		local page = open()
		Notify():MarkRead(entries()[1])
		local unread = page.chips.buttons[2]
		unread:GetScript("OnClick")(unread)
		eq(#page.table:VisibleRows(), 1)
		page.markAll:Click()
		eq(#page.table:VisibleRows(), 0)
		eq(page.table.empty:GetText(), "Nothing unread.")
		eq(View().frame.pager.buttons.notices.label:GetText(), "Notices")
		local all = page.chips.buttons[1]
		all:GetScript("OnClick")(all)
		eq(#page.table:VisibleRows(), 2)
		page.clear:Click()
		eq(page.clear:GetLabel(), "Click again to clear")
		eq(#entries(), 2)
		Mock.Advance(View().CONFIRM_SECONDS + 1)
		eq(page.clear:GetLabel(), "Clear")
		page.clear:Click()
		page.clear:Click()
		eq(#entries(), 0)
		eq(page.table.empty:GetText(), "No notices yet.")
	end)

	it("a click on a row reads it and opens its view", function()
		late()
		request(BOB, 1)
		local page = open()
		local row = page.table:VisibleRows()[1]
		row:GetScript("OnClick")(row)
		truthy(entries()[1].read)
		eq(A().Shell.selected, "bank")
	end)

	it("the Settings card offers the outputs of the bank, saved per account", function()
		Mock.Slash("/accord settings")
		local f = A().SettingsView.frame
		truthy(f.noticeHeads.bank:IsShown())
		truthy(f.noticeOutputs.bank.chat:GetChecked())
		falsy(f.noticeOutputs.bank.toast:GetChecked())
		falsy(f.noticeOutputs.bank.sound:GetChecked())
		isNil(f.noticeOutputs.likes, "a quiet module has nothing to choose")
		isNil(f.noticeOutputs.officer)
		f.noticeOutputs.bank.toast:Click()
		truthy(A().Config:Get("account.settings.notify.bank.toast"))
		truthy(f.noticeOutputs.bank.toast:GetChecked())
		f.checks.notifyDecision:Click()
		eq(A().Config:Get("account.settings.notifyDecision"), false)
		contains(f.noticeNote:GetText(), "Notices page")
		eq(#Mock.errors, 0)
	end)
end)

describe("the saved choices", function()
	it("are the ones of SPEC-13 §3.2 on a new install", function()
		local n = A().Config:Get("account.settings.notify")
		deepEq(n.bank, { chat = true, toast = false, sound = false, off = {} })
		deepEq(n.groups, { chat = true, toast = true, sound = false, off = { match = true } })
		eq(n.digest.chat, true)
		eq(n.digest.sound, false)
	end)

	it("schema 4 adds them and keeps the M5 options; a damaged value is reset, a saved one stays", function()
		T.boot(function() AzerothAccordDB = { schemaVersion = 3, settings = { notifyOfficer = false } } end)
		eq(AzerothAccordDB.schemaVersion, 4)
		eq(AzerothAccordDB.settings.notifyOfficer, false)
		eq(AzerothAccordDB.settings.notifyDecision, true)
		eq(AzerothAccordDB.settings.notify.bank.chat, true)
		T.boot(function()
			AzerothAccordDB = { schemaVersion = 4, settings = { notify = { bank = { chat = false, toast = "yes" },
				groups = { off = { match = false } } } } }
		end)
		local n = AzerothAccordDB.settings.notify
		eq(n.bank.chat, false)
		eq(n.bank.toast, false)
		eq(n.groups.off.match, false)
	end)
end)

describe("in Italian", function()
	before_boot(function(Mk) Mk.player.locale = "itIT" on(Mk) end)

	it("shows the line, the page and the settings in Italian", function()
		late()
		M().SetOutput("bank", "toast", true)
		request(BOB, 1)
		wait()
		contains(text(), "Accord: Nuova richiesta alla banca di Bob")
		eq(Toast().frame.title:GetText(), "Banca")
		Mock.Slash("/accord inbox")
		truthy(View():ShowPage("notices"))
		eq(View().frame.pager.buttons.notices.label:GetText(), "Avvisi (1)")
		Mock.Slash("/accord settings")
		eq(#Mock.errors, 0)
	end)
end)

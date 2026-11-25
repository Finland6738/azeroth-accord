-- The login digest (M9.5; SPEC-13 §5): only after a login, a few seconds after the roster is read; each line only when
-- not zero, with the view it opens; silent and without a card when nothing changed; likes are a number and never a name;
-- the chat line waits like a notice. With the switch `actions` off there is no digest at all.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Digest() return AzerothAccord.Digest end
local function Notify() return AzerothAccord.Notify end
local function View() return AzerothAccord.ActionsView end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"
local LINEN = 2589
local DAY = 86400
local SINCE = "since your last session: "

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
local function asMember(Mk) Mk.features = { actions = true } guild(3) items(Mk) end
local function off(Mk) guild(1) items(Mk) end

-- A whole first session: the picture is taken, the catch-up and the login window are over.
local function session() Mock.Advance(400) end

-- Out of the game for a day (or `away` seconds), then in again and up to just after the summary.
local function again(change, away)
	Mock.ClearOutput()
	Mock.Relog(away or DAY, change)
	Mock.Advance(Digest().RUN_DELAY + 3)
end

local function join(name, guid)
	return function()
		local m = Mock.guild.members
		m[#m + 1] = { name = name, level = 10, class = "ROGUE", rank = 3, online = false, zone = "Orgrimmar", note = "",
			officerNote = "", guid = guid }
	end
end

local function leave(name)
	return function()
		local m = Mock.guild.members
		for i = #m, 1, -1 do if m[i].name == name then table.remove(m, i) end end
	end
end

local function both(...)
	local list = { ... }
	return function() for _, fn in ipairs(list) do fn() end end
end

local function chat()
	local out = {}
	for _, line in ipairs(Mock.PlainOutput()) do
		if line:find(SINCE, 1, true) then out[#out + 1] = line end
	end
	return out
end

local function rows()
	local card = Digest():Card()
	return card and card.rows or {}
end

local function row(id)
	for _, r in ipairs(rows()) do if r.id == id then return r end end
	return nil
end

local function ids()
	local out = {}
	for i, r in ipairs(rows()) do out[i] = r.id end
	return table.concat(out, " ")
end

local function request(requester, n, status)
	local id = requester .. ":" .. n
	local t = GetServerTime()
	local rec = { id = id, author = requester, rev = 1, time = t, requester = requester, kind = "withdraw", status = status or "open",
		itemID = LINEN, count = 20, created = t, history = { { s = "open", by = requester, t = t } } }
	if rec.status ~= "open" then rec.history[2] = { s = rec.status, by = OFF, t = t } end
	S():Records("bankreq")[id] = rec
	A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
	return id
end

-- A like of the ledger for `target`, written at `at` by the notary OFF.
local function like(n, target, at)
	local p = ("%x"):format(n) .. ("0"):rep(A().Likes.PSEUDONYM_HEX - #("%x"):format(n))
	local id = A().Likes.EntryId(p, target or ME)
	S():Records("likes")[id] = { id = id, author = OFF, rev = 1, time = at or GetServerTime(), pseudonym = p, tag = "00000000000000ff",
		target = target or ME, day = 20260101 }
	A().Likes:Invalidate()
	A().Bus:Emit("STORE_CHANGED", "likes", id, "remote")
end

local function money(copper) truthy((A().Bank:PublishMoney(copper, true))) end

local function movements(list)
	local out = {}
	for i, e in ipairs(list) do out[i] = { kind = "deposit", name = "Bob", itemID = 0, count = e[1], t = GetServerTime() - (e[2] or 0) } end
	A().BankLog:Capture(0, out)
end

describe("when the digest comes", function()
	before_boot(asMember)

	it("the first time in a guild only takes the picture", function()
		session()
		eq(#chat(), 0)
		isNil(Digest():Card())
		local d = A().GuildKey:Data().digest
		eq(d.roster[BOB], "Bob")
		truthy(d.at)
		eq(#Mock.errors, 0)
	end)

	it("nothing changed: no line, no card, no sound (DIG-03)", function()
		session()
		local sounds = #(Mock.sounds or {})
		again()
		Mock.Advance(400)
		eq(#chat(), 0)
		isNil(Digest():Card())
		isNil(A().GuildKey:Data().digest.card)
		eq(#(Mock.sounds or {}), sounds)
		Mock.Slash("/accord inbox")
		falsy(View().frame.holders.inbox.digest:IsShown())
		eq(#View().DigestRows(), 0)
		eq(#Mock.errors, 0)
	end)

	it("comes RUN_DELAY seconds after the roster is read, once, inside the login window", function()
		session()
		Mock.ClearOutput()
		Mock.Relog(DAY, join("Cid", "Player-1-0000C1D0"))
		Mock.Advance(Digest().RUN_DELAY - 2)
		eq(#chat(), 0)
		Mock.Advance(5)
		eq(#chat(), 1)
		contains(chat()[1], "Accord: since your last session: 1 new member. /accord inbox")
		Mock.Advance(2000)
		eq(#chat(), 1)
		eq(#Notify():Entries(), 0, "the digest is not a notice of the history")
	end)

	it("not after a /reload, and the card of the login stays", function()
		session()
		again(join("Cid", "Player-1-0000C1D0"))
		Mock.Advance(400)
		Mock.ClearOutput()
		join("Dan", "Player-1-0000DA00")()
		Mock.Reload()
		Mock.Advance(400)
		eq(#chat(), 0)
		eq(row("joined").n, 1)
	end)

	it("the next login replaces the card", function()
		session()
		again(join("Cid", "Player-1-0000C1D0"))
		Mock.Advance(400)
		again()
		isNil(Digest():Card())
		eq(#chat(), 0)
	end)

	it("a logout before the summary loses nothing", function()
		session()
		Mock.Relog(DAY, join("Cid", "Player-1-0000C1D0"))
		Mock.Advance(2)
		again(nil, 60)
		eq(#chat(), 1)
		eq(row("joined").names[1], "Cid")
	end)

	it("a roster that is never complete gives no roster line, and keeps the picture", function()
		session()
		-- a row without a GUID makes every read partial
		again(both(join("Cid", "Player-1-0000C1D0"), join("Ghost", nil), leave("Ann")))
		like(1)
		Mock.Advance(400)
		eq(ids(), "likes notices")
		eq(A().GuildKey:Data().digest.roster[ANN], "Ann")
		isNil(A().GuildKey:Data().digest.roster["Player-1-0000C1D0"])
	end)

	it("a roster that becomes complete during the catch-up still gives its lines", function()
		session()
		again(both(join("Cid", "Player-1-0000C1D0"), join("Ghost", nil)))
		Mock.Advance(Digest().RUN_MAX)
		isNil(row("joined"))
		leave("Ghost")()
		Mock.Fire("GUILD_ROSTER_UPDATE")
		Mock.Advance(Digest().REFRESH + 1)
		eq(row("joined").n, 1)
		Mock.Advance(Digest().CATCH_UP)
		eq(#chat(), 1)
	end)

	it("after the summary only a complete read renews the picture of the roster", function()
		session()
		Mock.Advance(Digest().ROSTER_GAP + 1)
		local real = GetNumGuildMembers
		GetNumGuildMembers = function() local n, o, m = real() return n + 1, o, m end
		leave("Ann")()
		Mock.Fire("GUILD_ROSTER_UPDATE")
		eq(A().GuildKey:Data().digest.roster[ANN], "Ann")
		GetNumGuildMembers = real
		Mock.Fire("GUILD_ROSTER_UPDATE")
		isNil(A().GuildKey:Data().digest.roster[ANN])
	end)

	it("renews the time every five minutes and at the logout", function()
		session()
		local at = A().GuildKey:Data().digest.at
		Mock.Advance(Digest().TOUCH)
		truthy(A().GuildKey:Data().digest.at > at)
		Mock.Advance(10)
		Mock.Fire("PLAYER_LOGOUT")
		eq(A().GuildKey:Data().digest.at, GetServerTime())
	end)

	it("none in demo mode", function()
		session()
		Mock.ClearOutput()
		Mock.Relog(DAY, join("Cid", "Player-1-0000C1D0"))
		Mock.Slash("/accord demo")
		Mock.Advance(400)
		eq(#chat(), 0)
		isNil(Digest():Card())
		Mock.Slash("/accord demo off")
		Mock.Advance(400)
		eq(#chat(), 0)
		eq(#Mock.errors, 0)
	end)
end)

describe("new and departed members", function()
	before_boot(asMember)

	it("are counted and named, each line opening the roster", function()
		session()
		again(both(join("Cid", "Player-1-0000C1D0"), join("Dan", "Player-1-0000DA00"), leave("Ann")))
		eq(ids(), "joined left")
		eq(row("joined").n, 2)
		deepEq(row("joined").names, { "Cid", "Dan" })
		eq(Digest().Text(row("joined")), "2 new members: Cid, Dan")
		eq(Digest().Text(row("left")), "1 member left: Ann")
		eq(row("joined").view, "roster")
		eq(row("left").view, "roster")
		contains(chat()[1], "2 new members, 1 member left.")
		falsy(chat()[1]:find("Cid", 1, true), "numbers only in chat")
	end)

	it("names three at most and counts the rest", function()
		session()
		again(both(join("Eve", "Player-1-0000E000"), join("Cid", "Player-1-0000C1D0"), join("Dan", "Player-1-0000DA00"),
			join("Fay", "Player-1-0000F000"), join("Gus", "Player-1-00006000")))
		eq(Digest().Text(row("joined")), "5 new members: Cid, Dan, Eve, and 2 more")
	end)

	it("gives numbers only after more than 90 days", function()
		session()
		again(join("Cid", "Player-1-0000C1D0"), 91 * DAY)
		isNil(row("joined").names)
		eq(Digest().Text(row("joined")), "1 new member")
	end)

	it("gives numbers only when more than 50 joined or left", function()
		session()
		local list = {}
		for i = 1, 51 do list[i] = join("New" .. i, ("Player-1-%08X"):format(0x20000 + i)) end
		again(both((table.unpack or unpack)(list)))
		eq(row("joined").n, 51)
		isNil(row("joined").names)
	end)
end)

describe("things that wait", function()
	before_boot(on)

	it("alone and unchanged since the last session, they are no digest", function()
		request(BOB, 1)
		session()
		eq(A().Actions:Count(), 1)
		again()
		Mock.Advance(400)
		eq(#chat(), 0)
		isNil(Digest():Card())
	end)

	it("a new one counts all that wait, and opens the Inbox", function()
		request(BOB, 1)
		session()
		again()
		request(ANN, 1)
		Mock.Advance(Digest().REFRESH + 1)
		eq(row("pending").n, 2)
		eq(row("pending").view, "actions")
		eq(row("pending").page, "inbox")
		eq(Digest().Text(row("pending")), "2 things wait for you")
	end)

	it("one that changed while away counts as a change", function()
		local id = request(BOB, 1)
		session()
		local rec = S():Records("bankreq")[id]
		rec.status = "approved"
		again()
		eq(row("pending").n, 1)
		contains(chat()[1], "1 thing waits for you")
	end)

	it("go on the card beside another change", function()
		request(BOB, 1)
		session()
		again(join("Cid", "Player-1-0000C1D0"))
		eq(ids(), "joined pending")
	end)
end)

describe("likes", function()
	before_boot(asMember)

	it("are the number received since the last session, and open Reputation", function()
		like(1)
		session()
		again()
		like(2, ME, GetServerTime() - 60)
		like(3)
		like(4, BOB)
		Mock.Advance(Digest().REFRESH + 1)
		eq(row("likes").n, 2)
		eq(row("likes").view, "reputation")
		eq(Digest().Text(row("likes")), "You received 2 likes")
	end)

	it("an entry written before the last session is not counted, even if it arrives now", function()
		like(1)
		session()
		again()
		-- the sync brings it late: it carries the time it was written
		like(2, ME, GetServerTime() - 3 * DAY)
		Mock.Advance(Digest().REFRESH + 1)
		isNil(row("likes"))
		eq(A().Likes:ReceivedSince(GetServerTime() + 1), 0)
	end)

	it("never name who gave them: no voter, notary or pseudonym in the data or the strings", function()
		session()
		again()
		like(2)
		like(3)
		Mock.Advance(400)
		eq(type(A().Likes:ReceivedSince(0)), "number")
		local line = row("likes")
		local keys = {}
		for k in pairs(line) do keys[#keys + 1] = k end
		table.sort(keys)
		deepEq(keys, { "id", "n", "view" })
		local saved = A().GuildKey:Data().digest.card
		local function walk(v, out)
			if type(v) == "table" then
				for k, x in pairs(v) do walk(k, out) walk(x, out) end
			else out[#out + 1] = tostring(v) end
			return out
		end
		local shown = { table.concat(walk(saved, {}), " "), Digest().Text(line), table.concat(chat(), " "),
			table.concat(Digest():DebugLines(), " ") }
		for _, r in ipairs(View().DigestRows()) do shown[#shown + 1] = r.text end
		for _, n in ipairs(Notify():Entries()) do shown[#shown + 1] = Notify().Text(n) end
		local all = table.concat(shown, "\n")
		for _, secret in ipairs({ "Bob", "Ann", "Boss", OFF, BOB, ANN, "20000000", "30000000", "00000000000000ff" }) do
			falsy(all:find(secret, 1, true), secret)
		end
		contains(all, "You received 2 likes")
	end)

	it("what arrives with the sync after a silent start is said once, at the end of the catch-up", function()
		session()
		again()
		eq(#chat(), 0)
		like(2, ME, GetServerTime() - 3600)
		Mock.Advance(Digest().REFRESH + 1)
		eq(row("likes").n, 1)
		eq(#chat(), 0)
		Mock.Advance(Digest().CATCH_UP)
		eq(#chat(), 1)
		contains(chat()[1], "1 like")
		like(3)
		Mock.Advance(400)
		eq(#chat(), 1)
		eq(row("likes").n, 1, "after the catch-up the card stays as it is")
	end)
end)

describe("the bank", function()
	before_boot(asMember)

	it("shows the gold moved and the new entries of the logs, and opens the Bank", function()
		money(1000000)
		movements({ { 100, 3600 } })
		session()
		again()
		money(2200000)
		movements({ { 100, DAY + 3600 }, { 200, 7200 }, { 300, 60 } })
		Mock.Advance(Digest().REFRESH + 1)
		local line = row("bank")
		eq(line.money, 1200000)
		eq(line.n, 2)
		eq(line.view, "bank")
		contains(Digest().Text(line), "Bank: +120")
		contains(Digest().Text(line), "2 movements")
		contains(Digest().ChatText(rows()), "bank +120")
	end)

	it("says less gold with a minus, and nothing when the bank was only read again", function()
		money(1000000)
		movements({ { 100, 3600 } })
		session()
		again()
		money(1000000)
		movements({ { 100, DAY + 3600 } })
		Mock.Advance(Digest().REFRESH + 1)
		isNil(row("bank"))
		money(900000)
		Mock.Advance(Digest().REFRESH + 1)
		eq(row("bank").money, -100000)
		eq(row("bank").n, 0)
		contains(Digest().Text(row("bank")), "Bank: -10")
	end)
end)

describe("unread notices", function()
	before_boot(asMember)

	it("of this session are counted and open the Notices page", function()
		session()
		again()
		request(ME, 1, "approved")
		Mock.Advance(Digest().REFRESH + 1)
		local line = row("notices")
		eq(line.n, 1)
		eq(line.view, "actions")
		eq(line.page, "notices")
		eq(Digest().Text(line), "1 unread notice")
	end)

	it("of an older session are not", function()
		session()
		request(ME, 1, "approved")
		Mock.Advance(10)
		again()
		Mock.Advance(400)
		isNil(row("notices"))
	end)
end)

describe("the chat line waits like a notice", function()
	before_boot(asMember)

	local function login()
		session()
		Mock.ClearOutput()
		Mock.Relog(DAY, join("Cid", "Player-1-0000C1D0"))
	end

	it("in combat, and comes out once after it", function()
		login()
		Mock.world.inCombat = true
		Mock.Fire("PLAYER_REGEN_DISABLED")
		Mock.Advance(200)
		eq(#chat(), 0)
		notNil(Digest():Card(), "the card does not wait")
		Mock.world.inCombat = false
		Mock.Fire("PLAYER_REGEN_ENABLED")
		Mock.Advance(Notify().RELEASE_COMBAT + 1)
		eq(#chat(), 1)
		Mock.Advance(600)
		eq(#chat(), 1)
	end)

	it("in the quiet hours, until they end", function()
		login()
		local hour = A().Compat.LocalHour()
		truthy(A().Config:Set("account.settings.quiet.from", hour))
		truthy(A().Config:Set("account.settings.quiet.to", (hour + 2) % 24))
		truthy(A().Config:Set("account.settings.quiet.on", true))
		Mock.Advance(200)
		eq(#chat(), 0)
		A().Config:Set("account.settings.quiet.on", false)
		eq(#chat(), 1)
	end)

	it("not at all with the chat output of the digest off, the card stays", function()
		login()
		truthy(A().SettingsModel.SetOutput("digest", "chat", false))
		Mock.Advance(400)
		eq(#chat(), 0)
		notNil(Digest():Card())
	end)

	it("not when the card was closed while it waited", function()
		login()
		Mock.world.inCombat = true
		Mock.Fire("PLAYER_REGEN_DISABLED")
		Mock.Advance(20)
		truthy(Digest():Close())
		Mock.world.inCombat = false
		Mock.Fire("PLAYER_REGEN_ENABLED")
		Mock.Advance(400)
		eq(#chat(), 0)
		isNil(Digest():Card())
	end)
end)

describe("the card on the Inbox page", function()
	before_boot(on)

	local function digest()
		money(1000000)
		session()
		again(join("Cid", "Player-1-0000C1D0"))
		request(BOB, 1)
		like(2)
		money(2000000)
		Mock.Advance(Digest().REFRESH + 1)
		eq(ids(), "joined pending likes bank notices")
		Mock.Slash("/accord inbox")
		return View().frame.holders.inbox
	end

	it("shows the lines above the list, and each opens its view", function()
		local page = digest()
		truthy(page.digest:IsShown())
		local want = { { "roster" }, { "actions", "inbox" }, { "reputation" }, { "bank" }, { "actions", "notices" } }
		for i, w in ipairs(want) do
			Mock.Slash("/accord inbox")
			View():ShowPage("inbox")
			local line = page.digest.lines[i]
			truthy(line:IsShown())
			eq(line.label:GetText(), View().DigestRows()[i].text)
			line:Click()
			eq(A().Shell.selected, w[1], "line " .. i)
			if w[2] then eq(View().pageId, w[2], "line " .. i) end
		end
		eq(#Mock.errors, 0)
	end)

	it("Close takes it away until the next login", function()
		local page = digest()
		page.digest.close:Click()
		falsy(page.digest:IsShown())
		isNil(Digest():Card())
		Mock.Advance(10)
		like(3)
		Mock.Advance(10)
		isNil(Digest():Card())
	end)

	it("the Settings card offers only the chat line of the summary", function()
		Mock.Slash("/accord settings")
		local f = A().SettingsView.frame
		truthy(f.noticeOutputs.digest.chat:IsShown())
		truthy(f.noticeOutputs.digest.chat:GetChecked())
		isNil(f.noticeOutputs.digest.toast)
		isNil(f.noticeOutputs.digest.sound)
		eq(#Mock.errors, 0)
	end)
end)

describe("with the switch actions off", function()
	before_boot(off)

	it("there is no digest: nothing saved, said, shown or reported", function()
		session()
		money(1000000)
		again(join("Cid", "Player-1-0000C1D0"))
		like(2)
		Mock.Advance(400)
		Mock.Fire("PLAYER_LOGOUT")
		eq(A().Features.actions, false)
		eq(#chat(), 0)
		isNil(A().GuildKey:Data().digest)
		isNil(Digest():Card())
		eq(Digest():Run(), false)
		falsy(A().Diagnostics.Report():find("Digest:", 1, true))
		Mock.Slash("/accord settings")
		local f = A().SettingsView.frame
		falsy(f.noticeOutputs.digest.chat:IsShown())
		eq(#Mock.errors, 0)
	end)
end)

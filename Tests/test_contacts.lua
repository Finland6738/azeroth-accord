-- Contacts (M2.5; SPEC-05 §4, SPEC-03 §2): the own BattleTag and Discord name published to the guild (always), other
-- members' contacts validated and shown, the copy box, "Add BattleTag friend" and the Discord field of the settings.
local function A() return AzerothAccord end
local function C() return AzerothAccord.Contacts end
local function S() return AzerothAccord.Store end

local ME = "Player-1-0000A001"
local BOB, BOBALT, MAL = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000BAD"

local function guild()
	Mock.club.fill.discord = true
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, discord = "bob_native" },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT },
		{ name = "Mallory", rank = 3, guid = MAL },
	} }
end

local function put(guid, fields)
	local rec = { id = guid, author = guid, rev = (S():Get("contacts", guid) and S():Get("contacts", guid).rev or 0) + 1, time = GetServerTime() }
	for k, v in pairs(fields) do rec[k] = v end
	S():Records("contacts")[guid] = rec
	return rec
end

local function bobAccount()
	for guid, other in pairs({ [BOB] = BOBALT, [BOBALT] = BOB }) do
		S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T",
			chars = { { guid = guid, name = "x" }, { guid = other, name = "y" } } }
	end
	A().Accounts:MarkDirty()
end

describe("validation", function()
	it("accepts BattleTags and refuses the rest", function()
		local V = AzerothAccord.Contacts.ValidateBattleTag
		eq(V("Name#1234"), "Name#1234"); eq(V("Ünïcode#99"), "Ünïcode#99")
		isNil(V("Name")); isNil(V("Name#")); isNil(V("Na me#1")); isNil(V("#1234")); isNil(V("N#1")); isNil(V(42)); isNil(V(("x"):rep(50) .. "#1"))
		isNil(V("|cffff0000Red#1|r"))
	end)

	it("accepts a Discord user name of 2 to 32 characters without links, '@' or spaces", function()
		local V = AzerothAccord.Contacts.ValidateDiscord
		eq(V("bob_the.mage"), "bob_the.mage")
		eq(V("  @bob  "), "bob")
		eq(V("old#1234"), "old#1234")
		eq(select(2, V("")), "empty"); eq(select(2, V("a")), "short"); eq(select(2, V(("x"):rep(33))), "long")
		for _, bad in ipairs({ "has space", "http://x.y", "discord.gg/abc", "www.example", "a/b", "a|b", "a:b", "x@y", "a\nb", "<b>x</b>" }) do
			eq(select(2, V(bad)), "invalid", bad)
		end
		eq(select(2, V(42)), "invalid")
	end)

	it("escapes the pipe that would start a colour or link", function()
		eq(AzerothAccord.Contacts.Escape("a|cffff0000b"), "a||cffff0000b")
		isNil(AzerothAccord.Contacts.Escape(nil))
	end)
end)

describe("the own contacts (CON-01, CON-02)", function()
	before_boot(function() guild() end)

	it("reads the BattleTag from the game and shares it, and says so in the capability", function()
		Mock.player.battleTag = "Testchar#4321"
		truthy(C():Publish())
		local rec = S():Get("contacts", ME)
		eq(rec.battleTag, "Testchar#4321")
		eq(rec.account, A().Config:Token())
		isNil(rec.discord)
		eq(A().Compat:Feature("battleTag"), "available")
	end)

	it("publishes nothing for a player who has neither, and does not repeat an unchanged record", function()
		Mock.player.battleTag = nil
		falsy(C():Publish())
		eq(select(2, C():Publish()), "nothing")
		Mock.player.battleTag = "Testchar#4321"
		truthy(C():Publish())
		eq(S():Get("contacts", ME).rev, 1)
		eq(select(2, C():Publish()), "unchanged")
		eq(S():Get("contacts", ME).rev, 1)
	end)

	it("the typed Discord name is validated, saved in the account settings and published at once", function()
		Mock.player.battleTag = "Testchar#4321"
		truthy(C():SetDiscord("@Tester_1"))
		eq(A().Config:Get("account.settings.discord"), "Tester_1")
		eq(S():Get("contacts", ME).discord, "Tester_1")
		eq(select(2, C():SetDiscord("bad name")), "invalid")
		eq(A().Config:Get("account.settings.discord"), "Tester_1")
		eq(select(2, C():SetDiscord(("x"):rep(40))), "long")
	end)

	it("removing the Discord name publishes a record without it", function()
		Mock.player.battleTag = "Testchar#4321"
		C():SetDiscord("tester")
		local ok, why = C():SetDiscord("   ")
		truthy(ok); eq(why, "cleared")
		isNil(A().Config:Get("account.settings.discord"))
		isNil(S():Get("contacts", ME).discord)
		eq(S():Get("contacts", ME).rev, 2)
	end)

	it("works with a Discord name alone, and takes back a record when everything goes", function()
		Mock.player.battleTag = nil
		truthy(C():SetDiscord("tester"))
		eq(S():Get("contacts", ME).discord, "tester")
		C():SetDiscord("")
		notNil(S():Get("contacts", ME), "the record stays, emptied, so that the old value is taken back")
		isNil(S():Get("contacts", ME).discord)
	end)

	it("is always shared: no setting turns it off (D3)", function()
		for key in pairs(A().Config.rules) do
			-- the co-play switch is Q12 and the addon list's one is Q11, not contacts
			if key ~= "account.settings.shareCoplay" and key ~= "account.settings.shareAddons" then
				falsy(key:find("share", 1, true), key)
			end
		end
	end)

	it("publishes by itself after login, and again when Battle.net comes up late", function()
		C().AUTO = true
		Mock.player.battleTag = nil
		truthy(C():Start())
		Mock.Advance(12)
		isNil(S():Get("contacts", ME))
		Mock.player.battleTag = "Testchar#4321"
		Mock.Fire("BN_CONNECTED")
		Mock.Advance(3)
		eq(S():Get("contacts", ME).battleTag, "Testchar#4321")
	end)

	it("is not published without a guild", function()
		Mock.player.battleTag = "Testchar#4321"
		Mock.guild.Leave()
		eq(select(2, C():Publish()), "guild")
	end)
end)

describe("other members' contacts", function()
	before_boot(function() guild() end)

	it("takes the BattleTag and a shared Discord name from the newest records of the account", function()
		bobAccount()
		put(BOB, { battleTag = "Bob#1111", discord = "old_discord", time = GetServerTime() - 100 })
		put(BOBALT, { battleTag = "Bobnew#2222", time = GetServerTime() })
		local c = C():Of(BOBALT)
		eq(c.battleTag, "Bobnew#2222")
		eq(c.discord, "bob_native", "the native Discord name wins")
		eq(c.discordSource, "native")
		A().Club = nil
	end)

	it("falls back to the shared Discord name when the server does not give one", function()
		Mock.guild.members[1].discord = nil
		A().Roster:MarkDirty()
		bobAccount()
		put(BOB, { discord = "shared_d" })
		local c = C():Of(BOB)
		eq(c.discord, "shared_d"); eq(c.discordSource, "shared")
		isNil(c.battleTag)
	end)

	it("ignores what does not validate, whoever sent it", function()
		Mock.guild.members[1].discord = nil
		A().Roster:MarkDirty()
		put(BOB, { battleTag = "|cffff0000x#1|r", discord = "see http://evil" })
		isNil(C():Of(BOB))
		put(BOB, { battleTag = "Good#1", discord = "has space" })
		eq(C():Of(BOB).battleTag, "Good#1")
		isNil(C():Of(BOB).discord)
	end)

	it("writes a short text for the table cell", function()
		bobAccount()
		eq(C():Summary(BOB), "DC", "native Discord only")
		put(BOB, { battleTag = "Bob#1" })
		eq(C():Summary(BOB), "BT DC")
		eq(C():Summary(MAL), "")
		eq(C():Summary(nil), "")
	end)

	it("the Store refuses contacts written for somebody else's character", function()
		local rec = { id = BOB, author = BOB, rev = 1, time = GetServerTime(), account = "T", battleTag = "Fake#1" }
		local ok, why = S():Accept("contacts", rec, { sender = "Mallory" })
		falsy(ok); eq(why, "relay")
		local own = { id = MAL, author = MAL, rev = 1, time = GetServerTime(), account = "T", battleTag = "Mal#1" }
		truthy(S():Accept("contacts", own, { sender = "Mallory" }))
	end)

	it("the table's Contacts column is there and reads the summary", function()
		bobAccount()
		put(BOB, { battleTag = "Bob#1" })
		truthy(A().RosterModel.ColumnAvailable("contacts"))
		eq((A().RosterModel.Cell("contacts", A().Roster:ByGUID(BOB))), "BT DC")
	end)

	it("reports itself in /accord debug without names", function()
		put(BOB, { battleTag = "Bob#1" })
		local text = table.concat(C():DebugLines(), "\n")
		matches(text, "1 record%(s%)")
		falsy(text:find("Bob", 1, true))
	end)
end)

describe("Add BattleTag friend (CON-04)", function()
	before_boot(function() guild() end)

	local function entry(name) return A().Roster:ByName(name) end

	it("sends the request through C_Club for a member of the guild and says so", function()
		local bob = entry("Bob")
		truthy(C():CanSendFriendRequest(bob))
		Mock.ClearOutput()
		eq(C():SendFriendRequest(bob), "available")
		deepEq(Mock.club.friendRequests, { bob.clubMemberId })
		contains(table.concat(Mock.PlainOutput(), "\n"), "Friend request sent to Bob.")
	end)

	it("is not offered for yourself, for somebody outside the guild or without the API", function()
		falsy(C():CanSendFriendRequest(A().Roster:ByGUID(ME)))
		falsy(C():CanSendFriendRequest(A().RosterModel.PseudoEntry({ guid = "x", name = "Out" })))
		falsy(C():CanSendFriendRequest(nil))
		C_Club.SendBattleTagFriendRequest = nil
		A().Compat:Probe()
		falsy(C():CanSendFriendRequest(entry("Bob")))
		Mock.ClearOutput()
		eq(C():SendFriendRequest(entry("Bob")), "unavailable")
		contains(table.concat(Mock.PlainOutput(), "\n"), "cannot be sent")
	end)

	it("reports a call the game refuses", function()
		C_Club.SendBattleTagFriendRequest = function() error("ADDON_ACTION_FORBIDDEN") end
		Mock.ClearOutput()
		eq(C():SendFriendRequest(entry("Bob")), "restricted")
		contains(table.concat(Mock.PlainOutput(), "\n"), "did not accept")
		Mock.ClearErrors()
	end)
end)

describe("the card, the copy box and the settings", function()
	before_boot(function() guild() end)

	local function openCard(name)
		Mock.Slash("/accord roster")
		Mock.Advance(2)
		A().RosterView.frame:SetWidth(900)
		for _, r in ipairs(A().RosterView.frame.table.rows) do
			if r:IsShown() and r.cells[1]:GetText() == name then r:Click() return end
		end
		fail("no row " .. name)
	end

	local function itemWith(prefix)
		for _, it in ipairs(A().MemberCard.frame.items) do
			if it:IsShown() and (it.text:GetText() or ""):sub(1, #prefix) == prefix then return it end
		end
	end

	it("shows the contacts of the member, and a click copies them through the box", function()
		bobAccount()
		put(BOB, { battleTag = "Bob#1111" })
		openCard("Bob")
		local bt = itemWith("Battle.net: ")
		notNil(bt)
		eq(bt.text:GetText(), "Battle.net: Bob#1111")
		bt:Click()
		truthy(A().CopyBox:IsShown())
		eq(A().CopyBox:GetText(), "Bob#1111")
		eq(A().CopyBox.frame.edit:GetText(), "Bob#1111")
		eq(A().CopyBox.frame.title:GetText(), "Battle.net name")
		truthy(A().CopyBox.frame.edit._highlighted)
		-- read-only: typing is undone
		A().CopyBox.frame.edit:SetText("changed")
		Mock.RunScript(A().CopyBox.frame.edit, "OnTextChanged", true)
		eq(A().CopyBox.frame.edit:GetText(), "Bob#1111")
		A().CopyBox:Hide()
		itemWith("Discord: "):Click()
		eq(A().CopyBox:GetText(), "bob_native")
		eq(itemWith("Discord: ").text:GetText(), "Discord: bob_native (from the game)")
	end)

	it("a hostile contact never puts an escape sequence on the card", function()
		bobAccount()
		Mock.guild.members[1].discord = nil
		A().Roster:MarkDirty()
		put(BOB, { battleTag = "Evil|cffff0000#1" })
		openCard("Bob")
		falsy(itemWith("Battle.net: "))
	end)

	it("the Add BattleTag friend line sends the request", function()
		openCard("Bobalt")
		local add = itemWith("[Add BattleTag friend]")
		notNil(add)
		add:Click()
		eq(#Mock.club.friendRequests, 1)
		openCard("Testchar")
		isNil(itemWith("[Add BattleTag friend]"), "not for yourself")
	end)

	it("says why a member has no contacts", function()
		openCard("Mallory")
		notNil(itemWith("Contacts come from members who use Azeroth Accord."))
		bobAccount()
		Mock.guild.members[1].discord = nil
		A().Roster:MarkDirty()
		openCard("Bobalt")
		notNil(itemWith("No contacts shared yet."))
	end)

	it("the Settings view saves a valid Discord name and refuses an invalid one", function()
		Mock.player.battleTag = "Testchar#4321"
		Mock.Slash("/accord settings")
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {} }
		A().Shell:OpenView("settings")
		local f = A().SettingsView.frame
		notNil(f)
		eq(f.battleTag:GetText(), "Your BattleTag: Testchar#4321")
		f.discordEdit:SetText("Tester_9")
		f.save:Click()
		eq(f.status:GetText(), "Saved and shared with your guild.")
		eq(A().Config:Get("account.settings.discord"), "Tester_9")
		notNil(S():Get("contacts", ME))
		f.discordEdit:SetText("http://bad")
		f.save:Click()
		eq(f.status:GetText(), "Not a valid Discord user name: 2 to 32 characters, no spaces, no links.")
		eq(A().Config:Get("account.settings.discord"), "Tester_9")
		f.discordEdit:SetText("")
		f.save:Click()
		eq(f.status:GetText(), "Discord name removed.")
	end)

	it("the Settings view says so when the game gives no BattleTag, and explains it is always shared", function()
		Mock.player.battleTag = nil
		A().Shell:OpenView("settings")
		local f = A().SettingsView.frame
		matches(f.battleTag:GetText(), "not available")
		matches(f.explain:GetText(), "always on")
		eq(#Mock.errors, 0)
	end)
end)

describe("contacts across clients", function()
	it("a third client sees the BattleTag and Discord name of an alt's account", function()
		local sim = Sim.new{ clients = 3, seed = 31, accounts = true, contacts = true, latency = { 0.05, 0.3 } }
		local a, c = sim:client(1), sim:client(3)
		a.Mock.player.battleTag = "SimA#1001"
		a:addon().Config.db.account.settings.discord = "sim_a"
		local ok = sim:advanceUntil(function()
			local rec = c:addon().Store:Get("contacts", a:guid())
			return rec ~= nil and rec.discord == "sim_a"
		end, 240)
		truthy(ok)
		local got = c:addon().Contacts:Of(a:guid())
		eq(got.battleTag, "SimA#1001")
		eq(got.discord, "sim_a"); eq(got.discordSource, "shared")
		eq(c:addon().Store.stats.rejected, 0)
	end)
end)

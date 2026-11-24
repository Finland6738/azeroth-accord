-- Demo mode (M7.4; SPEC-11 §3): `/accord demo` fills every view from an invented guild, sends nothing, saves nothing and
-- leaves the real data as it was. Data/Demo.lua (the invented guild), Core/Demo.lua (the mode), the overlay of Compat,
-- the refusals of Transport, the strip of the Shell.
local function A() return AzerothAccord end
local function enter() Mock.Slash("/accord demo") end
local function leave() Mock.Slash("/accord demo") end

-- A text that is the same for equal tables whatever the order of the keys: the saved variables as the game would write them.
local function canon(value, seen)
	-- `lastSeen` of a guild moves with the clock whenever the real addon reads the guild: not a trace of the demo
	local t = type(value)
	if t == "string" then return ("%q"):format(value) end
	if t ~= "table" then return tostring(value) end
	seen = seen or {}
	if seen[value] then error("a circular table") end
	seen[value] = true
	local keys = {}
	for k in pairs(value) do if k ~= "lastSeen" then keys[#keys + 1] = k end end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) < type(b) end
		return a < b
	end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. canon(k, seen) .. "]=" .. canon(value[k], seen) end
	seen[value] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

local function saved() return canon(AzerothAccordDB), canon(AzerothAccordCharDB) end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

describe("the invented guild (Data/Demo.lua)", function()
	local D
	it("is the same twice and every name is in the list of the file", function()
		D = A().DemoData.Build(1800000000)
		eq(canon(D.sets), canon(A().DemoData.Build(1800000000).sets))
		eq(canon(D.roster), canon(A().DemoData.Build(1800000000).roster))
		eq(D.guildName, "Demo Guild")
		eq(D.realm, "Demo")
		eq(D.key, "Demo/Demo Guild")
	end)

	it("has 60 members of every class, 15 online, 5 ranks, two names with a space", function()
		eq(#D.roster, 60)
		local online, classes, spaced, ranks = 0, {}, 0, {}
		for _, r in ipairs(D.roster) do
			if r.online then online = online + 1 else truthy(r.lastOnlineHours and r.lastOnlineHours <= 90 * 24 + 24) end
			classes[r.classFile] = true
			if r.name:find(" ", 1, true) then spaced = spaced + 1 end
			ranks[r.rankIndex] = true
			truthy(r.level >= 10 and r.level <= 70)
			truthy(r.guid:find("^Player%-%d+%-%x+$"))
		end
		eq(online, 15)
		eq(count(classes), 10)
		eq(spaced, 2)
		eq(count(ranks), 5)
		eq(D.player.rankIndex, 1, "the player is an officer")
	end)

	it("has a queue of four entries, three to do and one done (SPEC-12 §7)", function()
		local queue = D.guildData.officer.queue
		local open, done = 0, 0
		for _, e in ipairs(queue) do
			if e.status == "open" then open = open + 1 elseif e.status == "done" then done = done + 1 end
		end
		eq(#queue, 4); eq(open, 3); eq(done, 1)
	end)

	it("has 20 accounts, alts outside the guild, a hint in a note and 40 likes", function()
		eq(#D.accounts, 20)
		local outside = {}
		for _, o in ipairs(D.outsiders) do outside[o.name] = o end
		eq(outside.Wanderel.guild, "Wandering Stars")
		eq(outside.Driftmoor.guild, "")
		truthy(outside.Ashgrove.seen <= 1800000000 - 44 * 86400)
		eq(#D.accounts[2].chars, 3, "the player: two characters in the guild and one outside")
		eq(count(D.sets.likes), 40)
		local noted
		for _, r in ipairs(D.roster) do if r.note and r.note:find("^alt: ") then noted = r end end
		notNil(noted)
		eq(count(D.sets.bankreq), 7)
	end)

	it("has three professions, one list 70 days old, a bank with a tab for officers, and requests in every state", function()
		local lines, old = {}, 0
		for _, rec in pairs(D.sets.recipes) do
			lines[rec.skillLine] = true
			if rec.time <= 1800000000 - 69 * 86400 then old = old + 1 end
		end
		eq(count(lines), 3)
		eq(old, 1)
		local restricted, tabs, states = 0, 0, {}
		for _, rec in pairs(D.sets.bank) do
			if rec.kind == "tab" then tabs = tabs + 1 end
			if rec.restricted then restricted = restricted + 1 end
		end
		eq(tabs, 3)
		truthy(restricted >= 1)
		for _, rec in pairs(D.sets.bankreq) do states[rec.status] = true end
		for _, s in ipairs({ "open", "approved", "rejected", "fulfilled", "cancelled" }) do truthy(states[s], s) end
		eq(D.sets.guildcfg.sources.raid, "accord")
		eq(D.sets.guildcfg.sources.loot, "none")
	end)

	it("needs no call to the game client: the file names none of its API", function()
		local source = Mock.ReadSource("AzerothAccord/Data/Demo.lua")
		notNil(source)
		source = source:gsub("%-%-[^\r\n]*", "")   -- the comments may name them
		falsy(source:find("C_[A-Z]%a+%.", 1), "no C_ namespace")
		falsy(source:find("Compat", 1, true))
		falsy(source:find("UnitName", 1, true))
	end)
end)

describe("entering and leaving", function()
	it("starts without a guild and without the network, shows the invented guild and says so", function()
		falsy(A().Role:InGuild())
		enter()
		truthy(A().Demo:IsActive())
		truthy(A().Role:InGuild())
		eq(A().Role:Get(), "officer")
		eq(A().GuildKey:Current(), "Demo/Demo Guild")
		eq(A().Roster:Count(), 60)
		truthy(Mock.PlainOutput()[#Mock.PlainOutput()]:find("Demo", 1, true))
		eq(#Mock.chat.sent, 0)
	end)

	it("leaves with the same command, with `off`, and says it when it was not on", function()
		enter()
		leave()
		falsy(A().Demo:IsActive())
		falsy(A().Role:InGuild())
		Mock.Slash("/accord demo off")
		falsy(A().Demo:IsActive())
		Mock.Slash("/accord demo on")
		truthy(A().Demo:IsActive())
		Mock.Slash("/accord demo off")
		falsy(A().Demo:IsActive())
	end)

	it("brings the real guild back: GUILD_CHANGED with the real key, and the real roster", function()
		Mock.guild.Set{ name = "Real Guild", myRank = 3, members = { { name = "Someone", level = 20, class = "MAGE", rank = 3, guid = "Player-1-0000AAAA" } } }
		Mock.Fire("PLAYER_GUILD_UPDATE")
		local before, realCount = A().GuildKey:Current(), A().Roster:Count()
		notNil(before)
		local events = {}
		A().Bus:On("GUILD_CHANGED", function(key) events[#events + 1] = key end)
		enter()
		eq(A().GuildKey:Current(), "Demo/Demo Guild")
		leave()
		eq(A().GuildKey:Current(), before)
		eq(events[#events], before)
		eq(A().Roster:Count(), realCount)
	end)

	it("is never on after a /reload", function()
		enter()
		truthy(A().Demo:IsActive())
		Mock.Reload()
		falsy(A().Demo:IsActive())
		falsy(A().Role:InGuild())
	end)
end)

describe("every view opens in demo mode with no guild and no network", function()
	it("opens each view of the panel without an error, filled with the invented guild", function()
		enter()
		local Shell = A().Shell
		for _, view in ipairs(AzerothAccord.VIEWS) do
			Mock.Slash("/accord " .. view)
			eq(Shell.selected, view, view)
			local def = Shell.views[view]
			notNil(def, view)
			isNil(def.failed, view .. " failed to build")
			truthy(def.frame:IsShown(), view)
		end
		eq(#Mock.chat.sent, 0)
	end)

	it("shows the strip with the exit button, and Demo instead of the sync state", function()
		enter()
		local strip = A().Shell.content.strip
		notNil(strip)
		truthy(strip:IsShown())
		eq(strip.text:GetText(), "Demo: invented guild. Nothing is sent or saved.")
		eq(strip.exit:GetLabel(), "Exit demo")
		eq(A().Shell.StatusText(), "Demo")
		eq(A().Shell.content.status:GetText(), "Demo")
		strip.exit:GetScript("OnClick")(strip.exit)
		falsy(A().Demo:IsActive())
		falsy(strip:IsShown())
	end)

	it("fills the roster, the professions, the reputation, the bank and the Raid view", function()
		enter()
		local R = A().Roster
		eq(R:Count(), 60)
		local withAddon = 0
		for _, e in ipairs(R:Members()) do if e.hasAddon then withAddon = withAddon + 1 end end
		eq(withAddon, 31)
		local professions = 0
		for _, e in ipairs(R:Members()) do professions = professions + #e.professions end
		truthy(professions > 10, "professions from the shared records")
		eq(#A().Bank:Tabs(), 3)
		truthy(A().Bank:Money().money > 0)
		eq(#A().BankRequests:List(), 7)
		local likes = 0
		for _, e in ipairs(R:Members()) do likes = likes + A().Likes:Total(e.guid) end
		truthy(likes >= 20)
		eq(A().Integrations:Source("raid"), "accord")
		Mock.Slash("/accord raid")
		isNil(A().Shell.views.raid.failed)
	end)

	it("opens the member card, the Settings page, /accord about and /accord debug", function()
		enter()
		local entry = A().Roster:Members()[5]
		A().MemberCard:Show(entry)
		truthy(A().MemberCard.frame:IsShown())
		Mock.Slash("/accord settings")
		Mock.Slash("/accord about")
		Mock.Slash("/accord debug")
		local debug = table.concat(Mock.PlainOutput(), "\n")
		contains(debug, "Demo")
		isNil(A().Shell.views.settings.failed)
	end)

	it("keeps every record to the rules of the Store: the trust check accepts all of them", function()
		enter()
		local S, R = A().Store, A().Roster
		local nameOf = {}
		for _, e in ipairs(R:Members()) do nameOf[e.guid] = e.name end
		local checked = 0
		for set, records in pairs(A().DemoData.Build(A().Compat.ServerTime()).sets) do
			for id, rec in pairs(records) do
				-- a member's own declared absence travels by whisper only (SPEC-12 OFF-02)
				local ok, why = S:Check(set, rec, { sender = nameOf[rec.author], dist = set == "absence" and "WHISPER" or nil })
				truthy(ok, set .. " " .. id .. ": " .. tostring(why))
				checked = checked + 1
			end
		end
		truthy(checked > 150, "checked " .. checked)
	end)
end)

describe("nothing is sent", function()
	it("refuses every message with the reason demo and leaves the queue as it was", function()
		Mock.guild.Set{ name = "Real Guild", myRank = 3, members = { { name = "Someone", level = 20, class = "MAGE", rank = 3, guid = "Player-1-0000AAAA" } } }
		Mock.Fire("PLAYER_GUILD_UPDATE")
		local T = A().Transport
		Mock.chat.lockdown = true   -- the message waits in the queue
		notNil(T:Send("GUILD", { t = "HELLO", d = {}, s = "" }, { key = "HELLO" }))
		eq(T:Pending(), 1)
		enter()
		local item, why = T:Send("GUILD", { t = "HELLO", d = {}, s = "" }, { key = "HELLO2" })
		isNil(item)
		eq(why, "demo")
		eq(T:Pending(), 1, "the waiting message stays")
		Mock.chat.lockdown = false
		Mock.Advance(60)
		eq(#Mock.chat.sent, 0)
		eq(T:Pending(), 1, "and does not go out during the demo")
		leave()
		Mock.Advance(10)
		eq(T:Pending(), 0, "it goes out after the exit")
	end)

	it("drops what arrives and counts it as demo in /accord debug", function()
		enter()
		local T = A().Transport
		local text = A().Codec:Encode("HELLO", { t = "HELLO", d = {}, s = "" })
		local ok, why = T:OnReceive(text, "GUILD", "Somebody")
		falsy(ok)
		eq(why, "demo")
		eq(T:Stats().rxReasons.demo, 1)
		contains(table.concat(T:DebugLines(), "\n"), "demo 1")
	end)

	it("starts no sync timer, and the sync starts again after the exit", function()
		Mock.guild.Set{ name = "Real Guild", myRank = 3, members = { { name = "Someone", level = 20, class = "MAGE", rank = 3, guid = "Player-1-0000AAAA" } } }
		Mock.Fire("PLAYER_GUILD_UPDATE")
		A().Sync.AUTO = true
		enter()
		isNil(A().Sync.state.helloTimer)
		Mock.Advance(2000)
		eq(#Mock.chat.sent, 0)
		leave()
		notNil(A().Sync.state.helloTimer)
	end)

	it("sends nothing while the player gives a like, asks the bank, changes the main and the theme", function()
		enter()
		local R = A().Roster
		local target
		for _, e in ipairs(R:Members()) do
			if A().Likes:StateOf(e.guid) == "can" and e.hasAddon then target = e break end
		end
		notNil(target)
		truthy(A().Likes:Give(target.guid))
		truthy(A().BankRequests:Create({ kind = "withdraw", itemID = 2840, count = 5, reason = "demo" }))
		truthy(A().Accounts:SetMain(A().Demo.state.data.player.guid))
		truthy(A().Config:Set("account.settings.theme", "aurora"))
		truthy(A().Contacts:SetDiscord("demo_player"))
		Mock.Advance(3000)
		eq(#Mock.chat.sent, 0)
		eq(#Mock.chat.attempts, 0)
		eq(A().Transport:Stats().sent, 0)
	end)
end)

describe("nothing is saved", function()
	it("the saved variables are the same, byte for byte, after the demo and what was done in it", function()
		Mock.guild.Set{ name = "Real Guild", myRank = 3, members = { { name = "Someone", level = 20, class = "MAGE", rank = 3, guid = "Player-1-0000AAAA" } } }
		Mock.Fire("PLAYER_GUILD_UPDATE")
		Mock.Advance(5)
		enter()   -- a first visit: the real addon then reads its own guild again and fills the empty tables it needs
		for _, view in ipairs(AzerothAccord.VIEWS) do Mock.Slash("/accord " .. view) end
		leave()
		local account, char = saved()
		enter()
		truthy(A().Config.db.account ~= AzerothAccordDB, "the demo works on a copy")
		truthy(A().Config.db.char ~= AzerothAccordCharDB)
		for _, e in ipairs(A().Roster:Members()) do
			if A().Likes:StateOf(e.guid) == "can" then A().Likes:Give(e.guid) break end
		end
		A().BankRequests:Create({ kind = "withdraw", itemID = 2840, count = 5, reason = "demo" })
		A().Accounts:SetMain(A().Demo.state.data.player.guid)
		A().Config:Set("account.settings.theme", "aurora")
		A().Config:Set("char.ui.lastView", "bank")
		A().Contacts:SetDiscord("demo_player")
		A().GuildKey:Clear()
		for _, view in ipairs(AzerothAccord.VIEWS) do Mock.Slash("/accord " .. view) end
		Mock.Advance(3000)
		leave()
		local account2, char2 = saved()
		eq(account2, account)
		eq(char2, char)
		truthy(A().Config.db.account == AzerothAccordDB, "the saved table is the one in use again")
		isNil(AzerothAccordDB.guilds["Demo/Demo Guild"])
		isNil(AzerothAccordDB.chars.Demo)
	end)

	it("does not save the demo at a logout inside it, and keeps the real queue", function()
		Mock.guild.Set{ name = "Real Guild", myRank = 3, members = { { name = "Someone", level = 20, class = "MAGE", rank = 3, guid = "Player-1-0000AAAA" } } }
		Mock.Fire("PLAYER_GUILD_UPDATE")
		Mock.chat.lockdown = true
		A().Transport:Send("GUILD", { t = "HELLO", d = {}, s = "" }, { key = "HELLO" })
		enter()
		A().Likes:Give(A().Roster:Members()[9].guid)
		Mock.Reload()   -- logout inside the demo, then a new session
		local text = Mock.savedText.AzerothAccordDB
		falsy(text:find("Demo Guild", 1, true))
		falsy(text:find("Demo/", 1, true))
		falsy(Mock.savedText.AzerothAccordCharDB:find("demo_", 1, true))
		eq(#AzerothAccordCharDB.outbox, 0, "the saved message was sent again at login and the outbox emptied")
	end)

	it("the demo copies do not leak the player's own Discord name or character names", function()
		A().Config:Set("account.settings.discord", "real_person")
		enter()
		isNil(A().Config:Get("account.settings.discord"))
		leave()
		eq(A().Config:Get("account.settings.discord"), "real_person")
	end)
end)

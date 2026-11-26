-- Onboarding (M12.4; SPEC-16 §5, ONB-01..ONB-04; SPEC-10 Q36): only a character that joined after the addon saw the
-- guild's roster gets the list (seen on this client, or from the game's guild log), never an alt or the guild that is
-- starting to use Accord; the items tick themselves and stay ticked, hidden when they cannot be done; Dismiss for good,
-- 30 days, `/accord welcome` for anyone; the card and the Action Center row; nothing is sent; the switch "recruit".

local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function O() return AzerothAccord.Onboarding end
local function V() return AzerothAccord.OnboardingView end
local function Ac() return AzerothAccord.Accounts end
local function H() return AzerothAccord.Handbook end

local ME, OFF, BOB = "Player-1-0000A001", "Player-1-000000FF", "Player-1-00000B0B"
local ALT = "Player-1-0000A002"
local FOLDER, GLOBAL = "FinlandDragonCreditPoints", "FinlandDragonCreditPointsAPI"
local KEY = "TestRealm/Accord"
local DAY = 86400

local function noGuild(features)
	return function(M)
		M.features = features or { recruit = true }
		M.guild.Leave()
	end
end

-- The character joins "Accord" (an invitation accepted while playing).
local function join()
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Officer", level = 60, class = "PALADIN", rank = 1, guid = OFF },
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
	} }
	A().Role:Refresh()
	Ac():RegisterSelf()   -- Accounts:Start does it in the game (switched off in the single-client tests)
	A().Roster:MarkDirty()
end

-- What an officer's client wrote `ago` seconds ago arrives: the proof that Accord saw the guild before the join.
local function received(ago, author, sender)
	author = author or OFF
	local t = GetServerTime() - (ago or 100)
	local ok, why = S():Accept("contacts", { id = author, author = author, rev = 1, time = t, account = "tok-" .. author,
		discord = "boss" }, { sender = sender or "Officer" })
	truthy(ok, why)
end

local function settle() Mock.Advance(2) end

local function newMember(ago)
	Ac():RegisterSelf()   -- read once without a guild
	Mock.Advance(1)
	join()
	received(ago)
	settle()
end

local function ids(items)
	local out = {}
	for _, item in ipairs(items or O():Items()) do out[#out + 1] = item.id .. (item.done and "+" or "-") end
	return table.concat(out, " ")
end

local function rows()
	local out = {}
	for _, r in ipairs(A().Actions:Refresh()) do if r.provider == "welcome" then out[#out + 1] = r end end
	return out
end

local function chatLines()
	local n = 0
	for _, line in ipairs(Mock.PlainOutput()) do if line:find("/accord welcome", 1, true) then n = n + 1 end end
	return n
end

local function page(slug, title, tpl)
	local id = "P:" .. slug
	local ok, why = S():Accept("handbook", { id = id, author = OFF, rev = (H():Get(id) or { rev = 0 }).rev + 1,
		time = GetServerTime(), title = title, body = "Text of " .. title, order = 10, tpl = tpl }, { sender = "Officer" })
	truthy(ok, why)
end

describe("ONB-01..ONB-03: who is new", function()
	before_boot(noGuild())

	it("lists a character that joined while Accord saw it, once an older record of the guild arrives", function()
		Ac():RegisterSelf()
		Mock.Advance(1)
		join()
		local e = O():Entry()
		eq(e.how, "seen"); eq(e.joined, GetServerTime())
		settle()
		falsy(O():Active(), "no record of another account yet: the guild may be starting with Accord")
		eq(#rows(), 0); eq(chatLines(), 0)
		received(100)
		settle()
		truthy(O():Active())
		eq(#rows(), 1); eq(chatLines(), 1)
		contains(rows()[1].title, "Welcome checklist: ")
	end)

	it("does not list the first of a guild: every record is newer than the join", function()
		Ac():RegisterSelf()
		Mock.Advance(1)
		join()
		Mock.Advance(60)
		received(10)
		settle()
		falsy(O():Active()); eq(#rows(), 0); eq(chatLines(), 0)
	end)

	it("does not list an alt of an account already in the guild", function()
		Ac():Register{ guid = ALT, name = "Altchar", realm = A().Compat.Player.Realm(), classID = 8, level = 20, guild = KEY }
		Mock.Advance(10)
		newMember()
		eq(A().GuildKey:Data().onboarding[ME].none, true)
		falsy(O():Active())
	end)

	it("does not list a character that was in the guild when the addon came: nothing changed", function()
		join()   -- the first reading is already this guild
		received()
		settle()
		isNil(O():Entry())
		falsy(O():Active())
		Mock.Advance(O().LOG_DELAY + O().LOG_WAIT)
		eq(O():Entry().none, true, "no sign: never checked again")
		eq(#rows(), 0)
	end)

	it("does not take a \"no guild\" read before the game was ready for a join", function()
		join()
		A().GuildKey:Data().firstSeen = GetServerTime() - 30 * DAY   -- the account knew this guild
		A().Accounts:Register{ guid = ME, name = "Testchar", guild = "" }
		Mock.Advance(1)
		A().Accounts:RegisterSelf()
		eq(O():Entry().none, true)
	end)

	it("keeps the list through a /reload and sends nothing", function()
		newMember()
		local before = #Mock.chat.sent
		Mock.Reload()
		settle()
		truthy(O():Active())
		eq(chatLines(), 1, "the chat line once")
		O():Refresh()
		eq(#Mock.chat.sent, before)
		eq(#Mock.errors, 0)
	end)
end)

describe("ONB-01: the game's guild log", function()
	before_boot(noGuild())

	local function log(M, events)
		local asked = { n = 0 }
		QueryGuildEventLog = function() asked.n = asked.n + 1 end
		GetNumGuildEvents = function() return #events end
		GetGuildEventInfo = function(i)
			local e = events[i]
			return e[1], e[2], nil, nil, 0, 0, e[3], e[4] or 0
		end
		return asked
	end

	it("lists a character the log shows joining in the last 14 days, read once after the login", function()
		local asked = log(Mock, { { "join", "Bob", 1 }, { "join", "Testchar-TestRealm", 20 }, { "join", "Testchar", 3 },
			{ "promote", "Testchar", 0 } })
		join()
		received(5 * DAY)
		settle()
		isNil(O():Entry())
		Mock.Advance(O().LOG_DELAY)
		eq(asked.n, 1)
		Mock.Advance(O().LOG_WAIT + 1)
		local e = O():Entry()
		eq(e.how, "log")
		truthy(math.abs(GetServerTime() - 3 * DAY - e.joined) <= 5)
		settle()
		truthy(O():Active())
		A().Bus:Emit("GUILD_CHANGED", KEY, KEY)
		Mock.Advance(O().LOG_DELAY + O().LOG_WAIT)
		eq(asked.n, 1)
	end)

	it("does not list an old join", function()
		log(Mock, { { "join", "Testchar", 15 } })
		join()
		received(30 * DAY)
		Mock.Advance(O().LOG_DELAY + O().LOG_WAIT + 1)
		eq(O():Entry().none, true)
		falsy(O():Active())
	end)

	it("without the functions leaves only what the client saw", function()
		falsy(A().Compat.Guild.HasEventLog())
		join()
		received(5 * DAY)
		Mock.Advance(O().LOG_DELAY + 1)
		eq(O():Entry().none, true)
		contains(O():DebugLine(), "sign none")
		contains(O():DebugLine(), "guild log functions no")
	end)
end)

describe("ONB-04: the items", function()
	before_boot(noGuild({ recruit = true, season = true, raid = true, actions = true }))

	it("ticks each item by itself and never unticks it", function()
		newMember()
		eq(ids(), "main+ discord-", "one character; no handbook page and no season: those items are hidden")
		page("info", "Guild info", true)
		eq(ids(), "main+ discord-", "a template is not a page to read")
		page("info", "Guild info")
		page("rules", "Rules")
		settle()
		eq(ids(), "read- main+ discord-")
		eq(O():Items()[1].target, "P:info")
		H():MarkRead("P:info")
		eq(O():Items()[1].target, "P:rules")
		H():MarkRead("P:rules")
		settle()
		eq(ids(), "read+ main+ discord-")
		page("rules", "Rules, again")
		settle()
		eq(ids(), "read+ main+ discord-", "a new revision does not untick")

		Ac():Register{ guid = ALT, name = "Altchar", realm = A().Compat.Player.Realm(), classID = 8, level = 20, guild = "" }
		O():Entry().done.main = nil
		eq(ids(), "read+ main- discord-", "two characters and no choice")
		truthy(Ac():SetMain(ME))
		settle()
		eq(ids(), "read+ main+ discord-")

		Mock.guild.SetMyRank(1)   -- an officer opens a season
		A().Role:Refresh()
		truthy(A().Season:Open("Naxx"))
		settle()
		eq(ids(), "read+ main+ discord- season-")
		eq(rows()[1].title, "Welcome checklist: 2 of 4 done")
		truthy(A().Season:Declare({ unsure = true }))
		settle()
		eq(ids(), "read+ main+ discord- season+")

		truthy(A().Contacts:SetDiscord("newbie"))
		settle()
		eq(ids(), "read+ main+ discord+ season+")
		eq(#rows(), 0, "nothing left to do")
		truthy(O():Active(), "All done for the rest of the session")
		truthy(O():Entry().completed)
		truthy(A().Contacts:SetDiscord(""))
		eq(ids(), "read+ main+ discord+ season+")
		Mock.Reload()
		settle()
		falsy(O():Active(), "and not again")
	end)

	it("reads the season of FDCP when it is the source", function()
		newMember()
		truthy(A().Integrations ~= nil)
		A().Integrations.Source = function() return "fdcp" end
		eq(ids(), "main+ discord-", "FDCP not loaded")
		local state, member = "OPEN", nil
		Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
		_G[GLOBAL] = { API_VERSION = 1, IsReady = function() return true end, GetSource = function() return "SNAPSHOT" end,
			GetSeason = function() return { id = "S3", name = "S3", state = state } end,
			GetMember = function(name) return member and name == "Testchar" and member or nil end }
		eq(ids(), "main+ discord- season-")
		eq(O():Items()[3].target, "fdcp")
		member = { name = "Testchar-TestRealm", class = "WARRIOR", role = "TANK", status = "ACTIVE" }
		eq(ids(), "main+ discord- season+")
		state = "CLOSED"
		eq(ids(), "main+ discord-")
		eq(#Mock.errors, 0)
	end)
end)

describe("the welcome card, Dismiss and /accord welcome", function()
	before_boot(noGuild({ recruit = true, actions = true }))

	it("shows the card in the Action Center and takes it away for good with Dismiss", function()
		newMember()
		rows()[1].open()
		local f = A().ActionsView.frame
		truthy(f, "the Action Center is open")
		local card = f.holders.inbox.welcome
		truthy(card and card:IsShown())
		eq(card.count:GetText(), "1 of 2 done")
		eq(card.lines[2].label:GetText(), "Add your Discord name")
		card.dismiss:Click()
		falsy(card:IsShown())
		falsy(O():Active()); eq(#rows(), 0)
		Mock.Reload()
		settle()
		falsy(O():Active())
		-- "Clear guild data" does not bring it back
		truthy(A().GuildKey:Clear())
		received()
		settle()
		falsy(O():Active())
		eq(#Mock.errors, 0)
	end)

	it("opens from a click on an item", function()
		newMember()
		truthy(V():Open())
		local items = V().Model().items
		truthy(V():Go(items[2]))
		falsy(V():IsShown())
		eq(A().Shell.selected, "settings")
		eq(#Mock.errors, 0)
	end)

	it("goes away 30 days after the join", function()
		newMember()
		Mock.SetServerTime(GetServerTime() + 30 * DAY - 10)
		truthy(O():Active())
		Mock.SetServerTime(GetServerTime() + 20)
		falsy(O():Active()); eq(#rows(), 0)
	end)

	it("opens with /accord welcome for anyone, new or not", function()
		join()
		settle()
		Mock.Slash("/accord welcome")
		truthy(V():IsShown())
		eq(V().frame.body.count:GetText(), "1 of 2 done")
		falsy(V().frame.body.dismiss:IsShown(), "nothing to dismiss")
		eq(#rows(), 0)
		isNil(O():Entry(), "opening it writes nothing")
		newMember()
		O():Dismiss()
		Mock.Slash("/accord welcome")
		truthy(V():IsShown())
		eq(#Mock.errors, 0)
	end)

	it("says in What I share that it stays here", function()
		join()
		local found
		for _, row in ipairs(A().ShareModel.Describe()) do if row.id == "welcome" then found = row end end
		truthy(found)
		eq(found.to, "only on this computer"); eq(found.records, 0)
	end)
end)

describe("without the Action Center", function()
	before_boot(noGuild({ recruit = true, actions = false }))

	it("opens the list in its window and still says the chat line once", function()
		newMember()
		eq(chatLines(), 1)
		truthy(V():ShowList())
		truthy(V():IsShown())
	end)
end)

describe("the welcome checklist with the switch off", function()
	before_boot(noGuild({ recruit = false }))

	it("keeps nothing, shows nothing and has no command", function()
		newMember()
		Mock.Advance(O().LOG_DELAY + O().LOG_WAIT)
		isNil(A().GuildKey:Data().onboarding)
		falsy(O():Active()); eq(#O():Items(), 0); eq(#rows(), 0); eq(chatLines(), 0)
		Mock.ClearOutput()
		Mock.Slash("/accord welcome")
		falsy(V():IsShown())
		contains(table.concat(Mock.PlainOutput(), "\n"), "welcome")
	end)
end)

describe("the welcome checklist in the demo guild", function()
	before_boot(function(M) M.features = { recruit = true } end)

	it("is a new member's with two items ticked", function()
		Mock.Slash("/accord demo")
		settle()
		truthy(O():Active())
		local done, total = O():Progress()
		truthy(done >= 2 and total > done, done .. "/" .. total)
		eq(chatLines(), 0)
		eq(#Mock.chat.sent, 0)
		eq(#Mock.errors, 0)
	end)
end)

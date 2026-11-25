-- The Action Center (M9.2; SPEC-13 §2): one list from the providers `bank`, `craft` and `officer`, sorted by urgency and
-- age; a thing resolved in its view leaves the list; who sees what; the limits of ACT-02; a provider that raises never
-- stops the others; the view, the badge, the command and the tooltip of the Compartment.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Actions() return AzerothAccord.Actions end
local function View() return AzerothAccord.ActionsView end
local function Shell() return AzerothAccord.Shell end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"
local LINEN = 2589
local POTION = 2330
local HOUR, DAY = 3600, 86400
local OFFICER_RANK, MEMBER_RANK = 1, 3

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or MEMBER_RANK, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function on(M)
	M.features = { actions = true }
	M.spells.known[POTION] = { name = "Minor Healing Potion", icon = 1 }
	M.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
	M.items.cached[LINEN] = true
end

local function member() guild(MEMBER_RANK) end
local function officer() guild(OFFICER_RANK) end

local function settle() Mock.Advance(1) end

local function asOfficer()
	guild(OFFICER_RANK)
	A().Role:Refresh()
	settle()
end

local function asMember()
	guild(MEMBER_RANK)
	A().Role:Refresh()
	settle()
end

-- A bank request as the sync would store it, announced on the Bus.
local function request(requester, n, status, age, extra)
	local id = requester .. ":" .. n
	local at = GetServerTime() - (age or 0)
	local rec = { id = id, author = requester, rev = 1, time = at, requester = requester, kind = "withdraw", status = status or "open",
		itemID = LINEN, count = 20, created = at, history = { { s = "open", by = requester, t = at } } }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("bankreq")[id] = rec
	A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
	return id
end

local function recipes(guid)
	local id = guid .. ":171"
	S():Records("recipes")[id] = { id = id, author = guid, rev = 1, time = GetServerTime(), char = guid, skillLine = 171, name = "Alchemy",
		rank = 200, maxRank = 300, ids = A().Recipes.Encode({ POTION }), n = 1 }
	A().Roster:MarkDirty(); A().Crafters:MarkDirty()
end

local function ask(guid, recipeId)
	ChatFrame_OpenChat = function() end
	truthy((A().Recipes:OpenCraftRequest(guid or BOB, recipeId or POTION)))
	settle()
end

local function queue(guid, name, op, age)
	local entry = A().OfficerOps:Add({ g = guid, name = name, op = op, fromRank = 3, toRank = op == "demote" and 4 or 2 },
		GetServerTime() - (age or 0))
	truthy(entry)
	settle()
	return entry
end

-- An absence record of `guid` that ends `ahead` days from today (negative: ended that long ago).
local function absence(guid, ahead, kind, written)
	local T = A().Timeline
	local t = GetServerTime()
	local id = guid .. ":" .. (kind or "off")
	S():Records("absence")[id] = { id = id, author = kind == "self" and guid or OFF, rev = 1, time = written or (t - 20 * DAY),
		char = guid, from = T.DayOf(t - 20 * DAY), ["until"] = T.DayOf(t + ahead * DAY) }
	A().Bus:Emit("STORE_CHANGED", "absence", id, "remote")
	settle()
end

local function titles(rows)
	local out = {}
	for i, r in ipairs(rows or Actions():Rows()) do out[i] = r.title end
	return out
end

local function find(title)
	for _, r in ipairs(Actions():Rows()) do if r.title == title then return r end end
	return nil
end

-- A provider of the test with `n` rows.
local function provider(id, n, def)
	def = def or {}
	def.label, def.order = def.label or "ACT_PROVIDER_BANK", def.order or 100
	def.items = def.items or function()
		local rows = {}
		for i = 1, n do
			rows[i] = { key = ("k%04d"):format(i), urgency = 2, time = 1000 + i, title = id .. " " .. i, open = function() end }
		end
		return rows
	end
	truthy(Actions():Register(id, def))
	settle()
end

describe("the list", function()
	before_boot(function(M) on(M) officer() end)

	it("shows the rows of three providers in one list, the most urgent first, then who waited longest", function()
		recipes(BOB)
		ask(BOB)
		request(BOB, 1, "open", 5 * HOUR)
		request(ANN, 1, "approved", 9 * HOUR)
		queue(BOB, "Bob", "promote", 7 * HOUR)
		deepEq(titles(), { "Deliver: Linen Cloth x20", "1 promotion to do in the game", "Bank request: Linen Cloth x20",
			"You asked Bob to craft Minor Healing Potion" })
		local rows = Actions():Rows()
		deepEq({ rows[1].provider, rows[2].provider, rows[3].provider, rows[4].provider }, { "bank", "officer", "bank", "craft" })
		deepEq({ rows[1].urgency, rows[3].urgency, rows[4].urgency }, { 2, 2, 1 })
		eq(rows[1].who, "Ann")
		eq(rows[3].detail, "Withdraw")
		eq(Actions():Count(), 3, "reminders are not counted")
	end)

	it("orders by urgency, time, the provider's order, then the key", function()
		local function one(id, order, rows)
			provider(id, 0, { order = order, items = function() return rows end })
		end
		local function row(key, urgency, time) return { key = key, urgency = urgency, time = time, title = key, open = function() end } end
		one("b", 60, { row("b-late", 1, 100), row("b-now", 3, 900) })
		one("a", 50, { row("a-z", 2, 100), row("a-a", 2, 100), row("a-old", 1, 50) })
		one("c", 40, { row("c-same", 2, 100) })
		deepEq(titles(), { "b-now", "c-same", "a-a", "a-z", "a-old", "b-late" })
	end)

	it("skips a row that is not well formed and cuts a long title", function()
		provider("odd", 0, { items = function()
			return { "no", { key = "a", urgency = 4, time = 1, title = "x", open = function() end },
				{ key = "b", urgency = 1, time = 1, title = "x" },
				{ key = ("k"):rep(65), urgency = 1, time = 1, title = "x", open = function() end },
				{ key = "ok", urgency = 1, time = 1, title = ("è"):rep(100), detail = ("d"):rep(200), open = function() end },
				{ key = "ok", urgency = 1, time = 1, title = "twice", open = function() end } }
		end })
		local rows = Actions():Rows()
		eq(#rows, 1)
		eq(rows[1].title, ("è"):rep(77) .. "...")
		eq(rows[1].detail, ("d"):rep(117) .. "...")
		eq(Actions().Cut(("a"):rep(80), 80), ("a"):rep(80))
		falsy(Actions():Register("bad", {}))
		falsy(Actions():Register(nil, { items = function() end }))
	end)

	it("keeps 50 rows of a provider and says how many more, and 200 rows in all", function()
		local opened
		provider("big", 0, { items = function()
			local rows = {}
			for i = 1, 60 do
				rows[i] = { key = ("k%04d"):format(i), urgency = 2, time = 1000 + i, title = "big " .. i, open = function() opened = i end }
			end
			return rows
		end })
		local rows = Actions():Rows()
		eq(#rows, 51)
		eq(rows[50].title, "big 50")
		eq(rows[51].title, "and 10 more")
		truthy(Actions():Open(rows[51]))
		eq(opened, 51, "it opens the view of the first row left out")
		for _, id in ipairs({ "p1", "p2", "p3" }) do provider(id, 70) end
		eq(#Actions():Rows(), 200)
	end)

	it("a provider that raises is skipped and recorded, the others stay", function()
		request(BOB, 1, "open")
		provider("broken", 0, { items = function() error("boom") end })
		provider("hidden", 0, { visible = function() error("no") end })
		provider("shy", 2, { visible = function() return false end })
		provider("off", 2, { feature = "raid" })
		provider("nothing", 0, { items = function() return nil end })
		deepEq(titles(), { "Bank request: Linen Cloth x20" })
		truthy(Actions().errorCount >= 3)
		local lines = table.concat(Actions():DebugLines(), "\n")
		contains(lines, "error in broken")
		contains(lines, "boom")
		-- an `open` that raises is caught too
		falsy(Actions():Open({ provider = "x", open = function() error("again") end }))
	end)

	it("says ACTIONS_CHANGED once for a burst, and only when the list changed", function()
		local n = 0
		A().Bus:On("ACTIONS_CHANGED", function() n = n + 1 end)
		request(BOB, 1, "open"); request(BOB, 2, "open")
		eq(n, 0, "collected for half a second")
		settle()
		eq(n, 1)
		A().Bus:Emit("ROSTER_UPDATED")
		settle()
		eq(n, 1)
	end)

	it("is read again every minute", function()
		local rows = {}
		provider("clock", 0, { items = function() return rows end })
		rows[1] = { key = "late", urgency = 3, time = 1, title = "late", open = function() end }
		isNil(find("late"))
		Mock.Advance(Actions().TICK + 1)
		notNil(find("late"))
	end)

	it("reads and does nothing else: nothing sent, nothing printed", function()
		recipes(BOB)
		ask(BOB)
		request(BOB, 1, "open")
		Mock.Advance(10)
		local sent, printed = #Mock.chat.sent, #Mock.PlainOutput()
		Actions():Refresh()
		eq(#Mock.chat.sent, sent)
		eq(#Mock.PlainOutput(), printed)
	end)
end)

describe("resolving a row in its view", function()
	before_boot(function(M) on(M) officer() end)

	it("a bank request: approved it waits to be delivered, fulfilled or rejected it leaves", function()
		local one, two = request(BOB, 1, "open", HOUR), request(ANN, 1, "open")
		settle()
		eq(#Actions():Rows(), 2)
		truthy(A().BankRequestsView.Act(one, "approved"))
		settle()
		notNil(find("Deliver: Linen Cloth x20"))
		truthy(A().BankRequestsView.Act(one, "fulfilled"))
		truthy(A().BankRequestsView.Act(two, "rejected"))
		settle()
		eq(#Actions():Rows(), 0)
	end)

	it("the own request: a reminder, gone once cancelled", function()
		asMember()
		local id = request(ME, 1, "open")
		settle()
		deepEq(titles(), { "Waiting for an officer: Linen Cloth x20" })
		eq(Actions():Rows()[1].urgency, 1)
		isNil(Actions():Rows()[1].dismiss)
		truthy(A().BankRequestsView.Act(id, "cancel"))
		settle()
		eq(#Actions():Rows(), 0)
	end)

	it("the queue of the officers: one row per kind with how many, gone when the roster shows it done", function()
		local oldest = queue(BOB, "Bob", "promote", 2 * HOUR)
		queue(ANN, "Ann", "promote", HOUR)
		local removal = queue(ANN, "Ann", "remove")
		deepEq(titles(), { "2 promotions to do in the game", "1 removal to do in the game" })
		eq(Actions():Rows()[1].time, oldest.created, "since the oldest of the kind")
		truthy(A().OfficerOps:Cancel(removal.n))
		settle()
		deepEq(titles(), { "2 promotions to do in the game" })
		A().OfficerOps:CheckRoster({ { guid = BOB, rankIndex = 2 }, { guid = ANN, rankIndex = 2 } })
		settle()
		eq(#Actions():Rows(), 0)
	end)

	it("an expired queue entry is not listed, and reading does not sweep it", function()
		local entry = queue(BOB, "Bob", "promote")
		entry.created = GetServerTime() - A().OfficerOps.EXPIRE - 1
		A().Actions:Refresh()
		eq(#Actions():Rows(), 0)
		eq(entry.status, "open")
	end)
end)

describe("the craft reminders", function()
	before_boot(function(M) on(M) member() end)

	it("a request is remembered on this computer, renewed when asked again, closed with Done", function()
		recipes(BOB)
		ask(BOB)
		local first = Actions():Rows()[1].time
		Mock.Advance(60)
		ask(BOB)
		eq(#Actions():Rows(), 1)
		truthy(Actions():Rows()[1].time > first)
		local asks = A().GuildKey:Data().craftAsks
		eq(#asks, 1)
		deepEq({ asks[1].guid, asks[1].recipeId }, { BOB, POTION })
		truthy(Actions():Dismiss(Actions():Rows()[1]))
		eq(#Actions():Rows(), 0)
		isNil(A().GuildKey:Data().craftAsks)
	end)

	it("keeps at most 20, the oldest leaving, and drops them after 7 days", function()
		for i = 1, 22 do A().Recipes:RememberAsk(BOB, 1000 + i) Mock.Advance(1) end
		local asks = A().GuildKey:Data().craftAsks
		eq(#asks, 20)
		eq(asks[1].recipeId, 1003)
		eq(asks[20].recipeId, 1022)
		A().Actions:Refresh()
		eq(#Actions():Rows(), 20)
		eq(Actions():Rows()[1].title, "You asked Bob to craft Recipe 1003")
		for _, a in ipairs(asks) do a.at = a.at - 7 * DAY end
		A().Actions:Refresh()
		eq(#Actions():Rows(), 0)
	end)

	it("survives a /reload and is never in the backup", function()
		A().Recipes:RememberAsk(BOB, POTION)
		local function holds(t)
			for k, v in pairs(t) do
				if k == "craftAsks" or type(v) == "table" and holds(v) then return true end
			end
			return false
		end
		falsy(holds(A().Backup:Content()))
		Mock.Reload()
		settle()
		eq(#A().GuildKey:Data().craftAsks, 1)
		eq(#Actions():Rows(), 1)
	end)
end)

describe("who sees what", function()
	before_boot(function(M) on(M) member() end)

	local function everything()
		request(BOB, 1, "open")
		request(ANN, 1, "approved")
		local day = GetServerTime()
		local entry = { n = 1, g = BOB, name = "Bob", op = "promote", fromRank = 3, toRank = 2, created = day, status = "open" }
		A().GuildKey:Data().officer = { queue = { entry }, queueSeq = 1 }   -- even with officer data left on the computer
		absence(ANN, -1)
	end

	it("a member sees no officer row and nobody else's request", function()
		everything()
		eq(#Actions():Rows(), 0)
		eq(Actions():Count(), 0)
		request(ME, 1, "approved")
		absence(ME, 2, "self")
		local rows = Actions():Rows()
		eq(#rows, 2)
		deepEq({ rows[1].provider, rows[2].provider }, { "officer", "bank" })
		matches(rows[1].title, "^Your absence ends on %d%d%d%d%-%d%d%-%d%d$")
		eq(rows[2].title, "Approved: Linen Cloth x20")
	end)

	it("an officer sees them, and they go at once when the officer is demoted", function()
		everything()
		asOfficer()
		eq(#Actions():Rows(), 4)
		notNil(find("1 promotion to do in the game"))
		guild(MEMBER_RANK)
		A().Role:Refresh()
		eq(#Actions():Rows(), 0, "nothing of the officer stays while the list is read again")
		settle()
		eq(#Actions():Rows(), 0)
	end)

	it("the Guild Master sees them too", function()
		everything()
		guild(0)
		A().Role:Refresh()
		settle()
		eq(#Actions():Rows(), 4)
	end)

	it("an officer's own request is a row to decide and a reminder", function()
		asOfficer()
		request(ME, 1, "open")
		settle()
		deepEq(titles(), { "Bank request: Linen Cloth x20", "Waiting for an officer: Linen Cloth x20" })
		eq(Actions():Count(), 1)
	end)

	it("out of a guild the list is empty", function()
		request(ME, 1, "open")
		settle()
		eq(#Actions():Rows(), 1)
		Mock.guild.Leave()
		A().Role:Refresh()
		settle()
		eq(#Actions():Rows(), 0)
	end)
end)

describe("the absences", function()
	before_boot(function(M) on(M) officer() end)

	it("officers are told who is back, from the return day to three days after", function()
		for ahead, listed in pairs({ [1] = false, [0] = true, [-3] = true, [-4] = false }) do
			absence(BOB, ahead)
			local rows = Actions():Rows()
			eq(#rows, listed and 1 or 0, "return in " .. ahead .. " days")
			if listed then
				eq(rows[1].title, "Bob is back (away until " .. A().Absence.DayText(A().Timeline.DayOf(GetServerTime() + ahead * DAY)) .. ")")
				eq(rows[1].urgency, 1)
			end
		end
	end)

	it("the newest declaration of the account counts: cleared, nothing is listed", function()
		absence(BOB, -1)
		eq(#Actions():Rows(), 1)
		truthy(A().Absence:SetFor(BOB, 0))
		settle()
		eq(#Actions():Rows(), 0)
	end)

	it("the member's own one shows within three days of the end and leaves after the return", function()
		asMember()
		absence(ME, 4, "self")
		eq(#Actions():Rows(), 0)
		absence(ME, 3, "self")
		eq(#Actions():Rows(), 1)
		absence(ME, 0, "self")
		eq(#Actions():Rows(), 1)
		absence(ME, -1, "self")
		eq(#Actions():Rows(), 0)
	end)
end)

describe("the view", function()
	before_boot(function(M) on(M) officer() end)

	local function open()
		Mock.Slash("/accord inbox")
		Mock.Advance(1)
		return View().frame.holders.inbox
	end

	it("is the first tab, opened by /accord inbox, with the count on it", function()
		request(BOB, 1, "open")
		settle()
		open()
		eq(Shell().selected, "actions")
		eq(Shell():ViewList()[1].id, "actions")
		local tab = Shell().content.tabs.buttons.actions
		eq(tab.label:GetText(), "Action Center")
		eq(tab.badge.label:GetText(), "1")
	end)

	it("says that nothing waits when nothing does", function()
		local page = open()
		truthy(page.table.empty:IsShown())
		eq(page.table.empty:GetText(), "Nothing waits for you.")
		local tab = Shell().content.tabs.buttons.actions
		truthy(tab.badge == nil or not tab.badge:IsShown())
	end)

	it("has a chip per provider present and filters by it", function()
		recipes(BOB)
		ask(BOB)
		request(BOB, 1, "open")
		settle()
		local page = open()
		local chips = {}
		for _, c in ipairs(View().Chips()) do chips[#chips + 1] = c.text end
		deepEq(chips, { "All", "Groups", "Bank", "Crafting", "Officers and absences" })
		eq(#page.table:VisibleRows(), 2)
		local craft = page.chips.buttons[4]
		craft:GetScript("OnClick")(craft)
		eq(View().filter, "craft")
		eq(#page.table:VisibleRows(), 1)
		eq(page.table:VisibleRows()[1].data.provider, "craft")
	end)

	it("draws the mark of the urgency and Done only on a reminder, which Done closes", function()
		recipes(BOB)
		ask(BOB)
		request(BOB, 1, "open")
		settle()
		local page = open()
		local rows = page.table:VisibleRows()
		falsy(rows[1].done:IsShown())
		truthy(rows[2].done:IsShown())
		rows[2].done:GetScript("OnClick")(rows[2].done)
		eq(#page.table:VisibleRows(), 1)
		eq(page.table:VisibleRows()[1].data.provider, "bank")
	end)

	it("follows the list while it is on screen", function()
		local page = open()
		local id = request(BOB, 1, "open")
		settle()
		eq(#page.table:VisibleRows(), 1)
		truthy(A().BankRequestsView.Act(id, "rejected"))
		settle()
		eq(#page.table:VisibleRows(), 0)
	end)

	local function click(title)
		local page = open()
		for _, row in ipairs(page.table:VisibleRows()) do
			if row.data.title == title then
				row:GetScript("OnClick")(row)
				return
			end
		end
		fail("no row " .. title)
	end

	it("a bank row opens the officers' inbox on that request", function()
		request(BOB, 1, "open", 2 * HOUR)
		local second = request(ANN, 1, "approved")
		A().BankView.search = "nothing"
		settle()
		click("Deliver: Linen Cloth x20")
		eq(Shell().selected, "bank")
		eq(A().BankView.mode, "inbox")
		eq(A().BankView.search, "")
		eq(A().BankRequestsView.focus, second)
		local area = A().BankView.modes.inbox.frame.area
		local marked = {}
		for _, row in ipairs(area.rows) do
			if row:IsShown() and row.focus:IsShown() then marked[#marked + 1] = row.data.id end
		end
		deepEq(marked, { second })
	end)

	it("the own request opens the own requests", function()
		asMember()
		local id = request(ME, 1, "open")
		settle()
		click("Waiting for an officer: Linen Cloth x20")
		eq(A().BankView.mode, "requests")
		truthy(A().BankRequestsView.onlyMine)
		eq(A().BankRequestsView.focus, id)
	end)

	it("a craft reminder opens that member's recipe list", function()
		recipes(BOB)
		ask(BOB)
		click("You asked Bob to craft Minor Healing Potion")
		eq(Shell().selected, "professions")
		eq(A().RecipeView.mode, "recipes")
		eq(A().RecipeView.model.guid, BOB)
		eq(A().RecipeView.model.skillLine, 171)
	end)

	it("the officer rows open the Queue and the Inactive pages", function()
		queue(BOB, "Bob", "promote")
		absence(ANN, -1)
		click("1 promotion to do in the game")
		eq(Shell().selected, "officers")
		eq(A().OfficersView.pageId, "queue")
		click(titles()[2])
		eq(A().OfficersView.pageId, "inactive")
	end)

	it("the own absence opens Settings on the Absence card", function()
		absence(ME, 1, "self")
		click(titles()[1])
		eq(Shell().selected, "settings")
		local f = A().SettingsView.frame
		eq(f.pageId, "settings")
		truthy(f.scroll:GetVerticalScroll() > 0)
	end)

	it("the tooltip of the Compartment says how many are to do", function()
		local function lines()
			local tip = { lines = {} }
			function tip:AddLine(t) self.lines[#self.lines + 1] = t end
			Shell().FillTooltip(tip)
			return table.concat(tip.lines, "\n")
		end
		falsy(lines():find("Action Center"))
		request(BOB, 1, "open"); request(ANN, 1, "open")
		settle()
		contains(lines(), "Action Center: 2 to do")
	end)

	it("/accord help and /accord debug know it", function()
		Mock.Slash("/accord help")
		contains(text(), "/accord inbox")
		request(BOB, 1, "open")
		settle()
		contains(A().Diagnostics.Report(), "Actions: 1 row(s), 1 to do, providers: groups, bank, craft, officer, 0 error(s)")
	end)
end)

describe("in Italian", function()
	before_boot(function(M)
		M.player.locale = "itIT"
		on(M)
		officer()
	end)

	it("opens with the rows in Italian", function()
		request(BOB, 1, "open")
		queue(BOB, "Bob", "demote")
		Mock.Slash("/accord inbox")
		Mock.Advance(1)
		eq(Shell().content.tabs.buttons.actions.label:GetText(), "Centro azioni")
		notNil(find("Richiesta in banca: Linen Cloth x20"))
		notNil(find("1 retrocessione da fare nel gioco"))
		eq(#View().frame.holders.inbox.table:VisibleRows(), 2)
	end)
end)

describe("in demo mode", function()
	before_boot(function(M) M.features = { actions = true } end)

	it("shows the invented guild's requests, reminders and queue, and keeps nothing", function()
		Mock.Slash("/accord demo")
		Mock.Advance(2)
		local count = {}
		for _, r in ipairs(Actions():Rows()) do count[r.provider] = (count[r.provider] or 0) + 1 end
		eq(count.craft, 2)
		truthy((count.bank or 0) >= 4)
		truthy((count.officer or 0) >= 3)
		Mock.Slash("/accord inbox")
		Mock.Advance(1)
		for _, r in ipairs(Actions():Rows()) do truthy(Actions():Open(r), r.title) end
		eq(Actions().errorCount, 0)
		Mock.Slash("/accord demo off")
		Mock.Advance(2)
		eq(#Actions():Rows(), 0)
	end)
end)

-- The Groups view (M9.7; SPEC-13 §6.10): the filters, the role preselected, the form, applying, the leader's Accept
-- and Decline, the Action Center rows, the notices (the one of a new listing off by default, held in combat and quiet
-- hours), the demo, and the switches: without `groups` no tab, without `actions` no row and no notice.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function G() return AzerothAccord.Groups end
local function M() return AzerothAccord.GroupsModel end
local function View() return AzerothAccord.GroupsView end
local function Shell() return AzerothAccord.Shell end
local function N() return AzerothAccord.Notify end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C"
local DEADMINES, STOCKADE, MOLTEN = 36, 34, 409

local function guild()
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 20, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 3, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
	} }
end

local function player(level, class)
	return function(Mk)
		Mk.player.level, Mk.player.classFile = level, class
	end
end

local function on(Mk) Mk.features = { groups = true, actions = false } guild() player(20, "PALADIN")(Mk) end
local function both(Mk) on(Mk) Mk.features = { groups = true, actions = true } end

local function hear(msg, sender) A().Bus:Emit("NET_MESSAGE", msg, sender, "WHISPER") end

local serial = 0
-- A listing heard from its leader.
local function listing(author, name, fields)
	serial = serial + 1
	local t = GetServerTime()
	local rec = { id = author .. ":" .. serial, author = author, rev = 1, time = t, kind = "dungeon", act = DEADMINES,
		min = 15, max = 25, size = 5, have = 1, need = { t = 1, h = 1, d = 2 }, created = t, ends = t + 7200, status = "open" }
	for k, v in pairs(fields or {}) do rec[k] = v end
	eq(S():Receive("groups", { rec }, name, "GUILD"), 1, "the listing is taken")
	return rec
end

local function ids(rows)
	local out = {}
	for i, r in ipairs(rows) do out[i] = r.id end
	return out
end

local function apply(sender, id, role, comment)
	hear({ t = "GAPP", g = id, k = "apply", r = role, c = comment, l = 20 }, sender)
end

local function form(change)
	local v = M().Defaults("dungeon", DEADMINES)
	for k, x in pairs(change or {}) do v[k] = x end
	return v
end

local function open()
	truthy(Shell():OpenView("groups"))
	return View().frame
end

local function click(button) button:GetScript("OnClick")(button) end

describe("the Groups view, the switch `groups` off", function()
	before_boot(function(Mk) Mk.features = { actions = true, groups = false } guild() end)

	it("has no tab, no command, no help line, no Settings row, no Action Center row or chip", function()
		Mock.Slash("/accord")
		for _, v in ipairs(Shell():ViewList()) do truthy(v.id ~= "groups") end
		isNil(Shell().content.tabs.buttons.groups)
		falsy(Shell():Select("groups"))
		falsy(View():ShowMine())
		falsy(View():ShowListing("x"))
		Mock.Slash("/accord help")
		falsy(text():find("/accord groups", 1, true))
		Mock.Slash("/accord groups")
		contains(text(), "Unknown command 'groups'")
		isNil(View().frame)
		for _, def in ipairs(A().SettingsModel.NoticeModules()) do truthy(def.id ~= "groups") end
		for _, c in ipairs(A().ActionsView.Chips()) do truthy(c.id ~= "groups") end
		eq(#G():ActionRows(), 0)
		A().Bus:Emit("GROUPS_CHANGED", "x")
		eq(#N():Entries(), 0)
		eq(#Mock.errors, 0)
	end)
end)

describe("the Groups view, `groups` on and `actions` off", function()
	before_boot(on)

	it("shows the tab and the command, but no Action Center row and no notice", function()
		Mock.Slash("/accord help")
		contains(text(), "/accord groups")
		Mock.Slash("/accord groups")
		eq(Shell().selected, "groups")
		isNil(Shell().views.groups.failed)
		local rec = M().Submit(form())
		truthy(rec)
		local id = M().Own().id
		apply("Bob", id, "d")
		eq(M().ApplicantCount(), 1)
		eq(A().Actions:Count(), 0)
		listing(ANN, "Ann")
		Mock.Advance(10)
		eq(#N():Entries(), 0)
		eq(#Mock.errors, 0)
	end)

	it("asks the guild for the open listings when it opens, at most once in ten minutes", function()
		local before = G().state.stats.asks
		open()
		eq(G().state.stats.asks, before + 1)
		Shell():Select("roster")
		Shell():Select("groups")
		eq(G().state.stats.asks, before + 1)
	end)
end)

describe("the list and its filters", function()
	before_boot(on)

	local dungeon, raid, quest
	local function three()
		dungeon = listing(BOB, "Bob", { note = "quests first", created = GetServerTime() - 30 })
		raid = listing(ANN, "Ann", { kind = "raid", act = MOLTEN, size = 40, min = 60, max = 60, need = { t = 2 },
			created = GetServerTime() - 20 })
		quest = listing(OFF, "Boss", { kind = "quest", act = "Westfall", min = 10, max = 30, need = { h = 1 },
			meet = "the tower", created = GetServerTime() - 10 })
	end

	it("lists the newest first and hides what is outside the player's level, unless asked", function()
		three()
		deepEq(ids(M().Rows()), { quest.id, dungeon.id })
		M().SetFits(false)
		deepEq(ids(M().Rows()), { quest.id, raid.id, dungeon.id })
		eq(A().Config:Get("account.settings.groupFilter").fits, false, "saved")
	end)

	it("filters by type, activity, role and the search text", function()
		three()
		M().SetFits(false)
		M().ToggleKind("raid"); M().ToggleKind("quest")
		deepEq(ids(M().Rows()), { quest.id, raid.id })
		M().ToggleKind("all")
		M().SetActivity("dungeon:" .. DEADMINES)
		deepEq(ids(M().Rows()), { dungeon.id })
		eq(#M().ActivityChoices(), 4, "All activities and the three held")
		M().SetActivity("")
		M().ToggleRole("h")
		deepEq(ids(M().Rows()), { quest.id, dungeon.id })
		M().ToggleRole("h")
		M().SetSearch("TOWER")
		deepEq(ids(M().Rows()), { quest.id })
		M().SetSearch("bob")
		deepEq(ids(M().Rows()), { dungeon.id })
	end)

	it("offers as role chips only the roles of the player's class", function()
		local roles = {}
		for i, c in ipairs(M().RoleChoices()) do roles[i] = c.id end
		deepEq(roles, { "t", "h", "d" })
		A().Compat.Player.ClassFile = function() return "MAGE" end
		eq(#M().RoleChoices(), 1)
	end)

	it("preselects the saved role of the game's Group Finder, then the group's, then the class's", function()
		local rec = { need = { t = 1, h = 1, d = 1 } }
		eq(G().PreferredRole(rec), "t", "the first the class can take")
		eq(G().PreferredRole({ need = { d = 1 } }), "d")
		UnitGroupRolesAssigned = function() return "HEALER" end
		eq(G().PreferredRole(rec), "h")
		C_LFGListRoles = { GetSavedRoles = function() return { tank = false, healer = false, dps = true } end }
		eq(G().PreferredRole(rec), "d")
		eq(G().PreferredRole({ need = { h = 1 } }), "h", "a saved role that is not needed is passed over")
		isNil(G().SeasonRole(), "no season before M10")
		G().SeasonRole = function() return "t" end
		eq(G().PreferredRole(rec), "t", "M10's declaration comes first")
		G().SeasonRole = function() return nil end
		C_LFGListRoles, UnitGroupRolesAssigned = nil, nil
		A().Compat.Player.ClassFile = function() return "MAGE" end
		isNil(G().PreferredRole({ need = { t = 1 } }))
	end)

	it("applies from the panel under the list and withdraws", function()
		three()
		local f = open()
		eq(#View().shown, 2)
		View():Choose(dungeon.id)
		local d = f.holders.list.detail
		truthy(d:IsShown())
		eq(View().role, "t", "preselected")
		truthy(d.apply:IsShown()); falsy(d.withdraw:IsShown()); falsy(d.manage:IsShown())
		click(d.apply)
		eq(G():Mine(dungeon.id).state, "waiting")
		eq(G():Mine(dungeon.id).r, "t")
		falsy(d.apply:IsShown()); truthy(d.withdraw:IsShown())
		eq(M().Text(View().shown[2], "state"), "Applied as Tank, waiting")
		click(d.withdraw)
		isNil(G():Mine(dungeon.id))
		eq(d.status:GetText(), "Application withdrawn.")
		eq(#Mock.errors, 0)
	end)

	it("offers no Apply outside the levels, and shows a closed listing as closed", function()
		three()
		local info = M().Detail(raid.id)
		falsy(info.canApply)
		eq(info.hint, "Your level is outside the levels of this group.")
		Mock.guild.members[1].online = false
		Mock.Fire("GUILD_ROSTER_UPDATE")
		info = M().Detail(dungeon.id)
		falsy(info.canApply)
		eq(info.state, "Leader offline")
		isNil(M().Detail("nothing:1"))
	end)
end)

describe("the form", function()
	before_boot(on)

	it("starts from the activity's levels and size, the player's instances first", function()
		local list = M().ActivityList("dungeon")
		local row = A().GroupActivities:Get(list[1].id)
		truthy(row.min <= 20 and row.max >= 20)
		local v = M().Defaults("dungeon", STOCKADE)
		eq(v.act, STOCKADE); eq(v.min, "22"); eq(v.max, "30"); eq(v.size, "5")
		eq(M().Defaults("help").size, "2")
		for _, kind in ipairs({ "dungeon", "raid" }) do
			for _, c in ipairs(M().ActivityList(kind)) do
				local d = M().Defaults(kind, c.id)
				truthy(d.t + d.h + d.d <= d.size - 1, kind .. " " .. c.id .. ": the defaults fit the instance")
			end
		end
	end)

	it("says what is wrong and posts nothing", function()
		local cases = {
			{ { min = "ten" }, "Check the levels: from 1 to the highest level, minimum first." },
			{ { min = "30", max = "20" }, "Check the levels: from 1 to the highest level, minimum first." },
			{ { size = "9" }, "Check the group size: 2 to 40, no more than the instance takes." },
			{ { have = "-1" }, "The players in the group must be at least 1 and fewer than the group size." },
			{ { t = "x" }, "Ask for at least one role, and no more players than the free places." },
			{ { t = "0", h = "0", d = "" }, "Ask for at least one role, and no more players than the free places." },
			{ { kind = "quest", act = "  " }, "Say what the group is for." },
		}
		for _, c in ipairs(cases) do
			local ok, why = M().Submit(form(c[1]))
			falsy(ok); eq(why, c[2])
		end
		eq(#G():List(), 0)
	end)

	it("asks before replacing the open listing, then updates and closes it", function()
		truthy((M().Submit(form({ note = "first" }))))
		local first = M().Own().id
		local ok, why, ask = M().Submit(form({ note = "second" }))
		falsy(ok); truthy(ask); contains(why, "Click again")
		eq(M().Own().id, first)
		truthy((M().Submit(form({ note = "second" }), true)))
		truthy(M().Own().id ~= first)
		Mock.Advance(11)
		truthy((M().Update(form({ note = "third", have = "2", t = "0" }))))
		Mock.Advance(11)
		local rec = M().Own()
		eq(rec.note, "third"); eq(rec.have, 2); eq(rec.need.t, 0)
		truthy((M().Close()))
		isNil(M().Own())
		falsy((M().Close()))
	end)

	it("does not undo an Accept with the numbers the form was filled with", function()
		truthy((M().Submit(form())))
		open()
		View():ShowPage("form")
		local f = View().frame.holders.form
		local id = M().Own().id
		apply("Bob", id, "h")
		Mock.Advance(11)
		truthy((M().Accept("Bob")))
		eq(f.boxes.h:GetText(), "0", "the untouched fields follow the group")
		f.boxes.note:SetText("one healer found")
		click(f.update)
		Mock.Advance(11)
		local rec = M().Own()
		eq(rec.need.h, 0); eq(rec.have, 2); eq(rec.note, "one healer found")
		-- an Accept still waiting to be written is kept too
		apply("Ann", id, "d")
		truthy((M().Accept("Ann")))
		f.boxes.meet:SetText("at the gate")
		click(f.update)
		Mock.Advance(11)
		rec = M().Own()
		eq(rec.need.d, 1); eq(rec.have, 3); eq(rec.meet, "at the gate"); eq(rec.note, "one healer found")
		eq(#Mock.errors, 0)
	end)

	it("works from the buttons of the page", function()
		open()
		View():ShowPage("form")
		local f = View().frame.holders.form
		eq(f.kind:Selected(), "dungeon")
		notNil(f.instance:Selected())
		falsy(f.update:IsShown())
		f.boxes.note:SetText("bring water")
		click(f.post)
		local own = M().Own()
		notNil(own)
		eq(own.note, "bring water")
		truthy(f.update:IsShown()); truthy(f.close:IsShown())
		click(f.post)
		eq(f.post:GetLabel(), "Close the old one and post")
		eq(M().Own().id, own.id)
		Mock.Advance(View().CONFIRM_SECONDS + 1)
		eq(f.post:GetLabel(), "Post")
		f.kind:Select("quest")
		truthy(f.actText:IsShown()); falsy(f.instance:IsShown())
		eq(f.boxes.note:GetText(), "bring water", "the note stays when the type changes")
		click(f.close)
		isNil(M().Own())
		eq(#Mock.errors, 0)
	end)
end)

describe("the leader's applicants", function()
	before_boot(both)

	local function posted()
		truthy((M().Submit(form())))
		return M().Own().id
	end

	it("lists them with Accept and Decline, which invite and answer", function()
		local id = posted()
		apply("Bob", id, "d", "ready")
		Mock.Advance(2)
		apply("Ann", id, "h")
		open()
		truthy(View():ShowMine())
		local f = View().frame.holders.mine
		eq(#View().shownApplicants, 2)
		local a = View().shownApplicants[1]
		eq(a.name, "Bob"); eq(a.comment, "ready"); eq(M().ApplicantText(a, "level"), "20")
		eq(Shell().BadgeText(Shell().views.groups), "2")
		local rows = f.table:VisibleRows()
		click(rows[1].accept)
		deepEq(Mock.group.invites, { "Bob" })
		eq(#View().shownApplicants, 1)
		click(f.table:VisibleRows()[1].decline)
		eq(#View().shownApplicants, 0)
		deepEq(Mock.group.invites, { "Bob" }, "Decline invites nobody")
		eq(f.status:GetText(), "Application declined.")
		eq(#Mock.errors, 0)
	end)

	it("says why an invitation cannot go", function()
		local id = posted()
		apply("Bob", id, "d")
		Mock.group.Set{ members = { { name = "Ann", guid = ANN } } }
		Mock.group.notLeader = true
		local ok, why = M().Accept("Bob")
		falsy(ok); eq(why, "Only the leader of your party or raid can invite.")
		Mock.group.notLeader = nil
		eq(M().ApplicantCount(), 1)
	end)

	it("puts one urgent row per applicant in the Action Center, which goes when answered", function()
		local id = posted()
		apply("Bob", id, "d", "ready")
		apply("Ann", id, "h")
		Mock.Advance(1)
		local rows = A().Actions:Refresh()
		eq(#rows, 2)
		eq(rows[1].provider, "groups"); eq(rows[1].urgency, 3)
		local titles = { rows[1].title, rows[2].title }
		contains(titles, "Bob wants to join as damage"); contains(titles, "Ann wants to join as healer")
		A().Actions:Open(rows[1])
		eq(Shell().selected, "groups"); eq(View().pageId, "mine")
		truthy((M().Decline("Bob")))
		eq(#A().Actions:Refresh(), 1)
		M().Close()
		eq(#A().Actions:Refresh(), 0)
	end)

	it("posts an alert for a new applicant, which opens the applicants", function()
		local id = posted()
		apply("Bob", id, "d")
		local e = N():Entries()[1]
		eq(e.module, "groups"); eq(e.kind, "applicant"); eq(e.level, "alert")
		eq(N().Text(e), "Bob wants to join as damage")
		apply("Bob", id, "d", "again")
		eq(#N():Entries(), 1, "the same application is told once")
		View().pageId = "list"
		truthy(N():Open(e))
		eq(View().pageId, "mine")
	end)

	it("tells the candidate the leader's answer", function()
		local rec = listing(ANN, "Ann")
		truthy((M().Apply(rec.id, "d")))
		hear({ t = "GAPP", g = rec.id, k = "accept" }, "Ann")
		local found
		for _, e in ipairs(N():Entries()) do if e.kind == "answer" then found = e end end
		notNil(found)
		eq(N().Text(found), "Ann accepted you: watch for the invitation")
		N():Open(found)
		eq(View().selected, rec.id)
	end)
end)

describe("the notice of a new listing", function()
	before_boot(both)

	local function matches()
		local out = {}
		for _, e in ipairs(N():Entries()) do if e.kind == "match" then out[#out + 1] = e end end
		return out
	end
	local function enable()
		Mock.Advance(400)   -- past the window of the login, which groups the notices (NTF-05)
		truthy(A().SettingsModel.SetKind("groups", "match", true))
		Mock.ClearOutput()
	end

	it("is off by default: it goes to the history, muted, and nothing comes out", function()
		eq(A().SettingsModel.GetKind("groups", "match"), false)
		Mock.ClearOutput()
		listing(BOB, "Bob")
		Mock.Advance(10)
		eq(#matches(), 1)
		truthy(matches()[1].muted)
		falsy(text():find("New group", 1, true))
		truthy(N():Module("groups").byKind.match.optIn, "its muted entries stay out of the login digest")
	end)

	it("comes out once switched on, only for what fits the filters, the level and a role of the player", function()
		enable()
		local f = G():Filter()
		f.kinds = { dungeon = true }
		G():SetFilter(f)
		listing(OFF, "Boss", { kind = "quest", act = "Westfall" })
		listing(ANN, "Ann", { min = 40, max = 60 })
		eq(#matches(), 0)
		A().Compat.Player.ClassFile = function() return "MAGE" end
		listing(OFF, "Boss", { need = { t = 1 } })
		eq(#matches(), 0, "no role of the class is wanted")
		local rec = listing(BOB, "Bob")
		Mock.Advance(10)
		eq(#matches(), 1)
		falsy(matches()[1].muted)
		contains(text(), "New group: " .. G().ActivityName(rec) .. ", led by Bob")
	end)

	it("looks only at the chosen roles, and comes at most once in five minutes", function()
		enable()
		local f = G():Filter()
		f.roles = { h = true }
		G():SetFilter(f)
		listing(BOB, "Bob", { need = { d = 2 } })
		eq(#matches(), 0)
		listing(ANN, "Ann")
		listing(OFF, "Boss")
		eq(#matches(), 1)
		Mock.Advance(G().MATCH_EVERY + 1)
		listing(BOB, "Bob")
		eq(#matches(), 2)
	end)

	it("waits during combat and in the quiet hours", function()
		enable()
		Mock.world.inCombat = true
		Mock.Fire("PLAYER_REGEN_DISABLED")
		listing(BOB, "Bob")
		Mock.Advance(20)
		falsy(text():find("New group", 1, true), "held in combat")
		Mock.world.inCombat = false
		Mock.Fire("PLAYER_REGEN_ENABLED")
		Mock.Advance(10)
		contains(text(), "New group")
		Mock.ClearOutput()
		local hour = 23
		A().Compat.LocalHour = function() return hour end
		truthy(A().SettingsModel.SetQuiet("on", true))
		Mock.Advance(G().MATCH_EVERY)
		listing(ANN, "Ann")
		Mock.Advance(20)
		falsy(text():find("New group", 1, true), "held in the quiet hours")
		hour = 12
		Mock.Advance(70)
		contains(text(), "New group")
	end)

	it("has its four switches in the Notifications card of Settings (the fourth, `game`, from M9.8)", function()
		local found
		for _, def in ipairs(A().SettingsModel.NoticeModules()) do if def.id == "groups" then found = def end end
		notNil(found)
		eq(#found.kinds, 4)
		eq(found.kinds[4].id, "game")
		truthy(Shell():OpenView("settings"))
		eq(#Mock.errors, 0)
	end)
end)

describe("the saved filters", function()
	it("are added to the account's settings by the migration, and a damaged value is reset", function()
		local db = { settings = {} }
		A().Config.migrations.account[4](db)
		eq(db.settings.groupFilter.fits, true)
		falsy(A().Config:Set("account.settings.groupFilter", { kinds = { dungeon = "yes" } }))
		falsy(A().Config:Set("account.settings.groupFilter", { fits = 1 }))
		truthy(A().Config:Set("account.settings.groupFilter", { kinds = { raid = true }, fits = false, roles = {} }))
	end)
end)

describe("the demo", function()
	before_boot(function(Mk) Mk.features = { groups = true, actions = true } end)

	it("shows six listings and two applicants to the player's own", function()
		Mock.Slash("/accord demo")
		Mock.Advance(2)
		eq(#G():List(), 6)
		eq(M().ApplicantCount(), 2)
		eq(#G():ActionRows(), 2)
		Mock.Slash("/accord groups")
		for _, page in ipairs({ "list", "form", "mine" }) do View():ShowPage(page) end
		isNil(Shell().views.groups.failed)
		for _, e in ipairs(G():List()) do truthy(G().ValidRecord(e.rec), e.rec.id) end
		eq(#Mock.chat.sent, 0)
		eq(#Mock.errors, 0)
	end)
end)

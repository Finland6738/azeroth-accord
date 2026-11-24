-- The cleanup review and the queue of manual actions (M8.4; SPEC-12 §4, ADR 0023): the accounts proposed by tier, the
-- choices, the queue ticked by the roster, the expiry, who sees it, and that the addon never changes the roster: its code
-- does not name any function that does (OPS-01).
local function A() return AzerothAccord end
local function O() return AzerothAccord.OfficerOps end
local function V() return AzerothAccord.OfficersView end
local function T() return AzerothAccord.Timeline end

local ME = "Player-1-0000A001"
local BOB, BOBALT, ANN, CARL, DEE, GONE = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000A01", "Player-1-00000C01",
	"Player-1-00000D01", "Player-1-00000090"
local OFF = "Player-1-000000FF"
local DAY = 86400

-- Ranks: 0 Guild Master, 1 Officer, 2 Veteran, 3 Member, 4 Initiate. The player is an officer (rank 1).
local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = false, lastOnline = { 0, 0, 100, 0 }, note = "old" },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT, online = false, lastOnline = { 0, 0, 120, 0 } },
		{ name = "Ann", level = 50, class = "PRIEST", rank = 3, guid = ANN, online = false, lastOnline = { 0, 0, 65, 0 } },
		{ name = "Carl", level = 40, class = "ROGUE", rank = 2, guid = CARL, online = false, lastOnline = { 0, 0, 95, 0 } },
		{ name = "Dee", level = 40, class = "ROGUE", rank = 3, guid = DEE, online = false, lastOnline = { 0, 0, 2, 0 } },
		{ name = "Gone", level = 20, class = "ROGUE", rank = 3, guid = GONE, online = false, lastOnline = {} },
		{ name = "Officer", level = 60, class = "ROGUE", rank = 1, guid = OFF, online = false, lastOnline = { 0, 0, 200, 0 } },
	} }
	if A() then A().Role:Refresh() A().Roster:MarkDirty() end
end

local function member(guid)
	for _, m in ipairs(Mock.guild.members) do if m.guid == guid then return m end end
end

local function drop(guid)
	for i, m in ipairs(Mock.guild.members) do if m.guid == guid then table.remove(Mock.guild.members, i) return end end
end

local function link()
	local chars = { { guid = BOB, name = "Bob" }, { guid = BOBALT, name = "Bobalt" } }
	for _, g in ipairs({ BOB, BOBALT }) do
		A().Store:Records("accounts")[g] = { id = g, author = g, rev = 1, time = GetServerTime(), token = "T", chars = chars }
	end
	A().Accounts:MarkDirty()
	A().Inactivity:Invalidate()
end

-- A complete read of the roster as the observation does it.
local function read()
	A().Roster:MarkDirty()
	A().Inactivity:Invalidate()
	return T():Read()
end

local function add(guid, op, extra)
	local spec = { g = guid, name = member(guid) and member(guid).name or "?", op = op }
	for k, v in pairs(extra or {}) do spec[k] = v end
	return O():Add(spec)
end

local function status(entry) return O():Get(entry.n) and O():Get(entry.n).status end

local function names(group)
	local out = {}
	for _, a in ipairs(group.accounts) do out[#out + 1] = a.name end
	return table.concat(out, ",")
end

local function draftOf(guid, filter)
	for _, group in ipairs(O():Proposal(filter or { minTier = 1 }).groups) do
		for _, a in ipairs(group.accounts) do
			for _, c in ipairs(a.chars) do if c == guid then return O():Draft(a) end end
		end
	end
end

describe("the review: which accounts (SPEC-12 §4.1)", function()
	before_boot(function() guild() end)

	it("groups them by inactivity tier, the longest away first, from tier 4 unless asked", function()
		link()
		local p = O():Proposal()
		eq(#p.groups, 1); eq(p.groups[1].tier, 4); eq(names(p.groups[1]), "Bob,Carl"); eq(p.count, 2)
		p = O():Proposal{ minTier = 1 }
		eq(#p.groups, 2); eq(p.groups[1].tier, 4); eq(p.groups[2].tier, 3); eq(names(p.groups[2]), "Ann"); eq(p.count, 3)
		eq(#p.groups[1].accounts[1].chars, 2, "an account, not a character")
	end)

	it("never proposes an officer's account or one away, and the unknown ones only when asked", function()
		A().Absence:SetFor(CARL, A().Timeline.DayOf(GetServerTime() + 5 * DAY))
		local p = O():Proposal{ minTier = 1 }
		for _, g in ipairs(p.groups) do
			falsy(names(g):find("Officer", 1, true)); falsy(names(g):find("Carl", 1, true)); falsy(names(g):find("Gone", 1, true))
			falsy(names(g):find("Dee", 1, true), "active")
		end
		p = O():Proposal{ minTier = 1, unknown = true }
		local last = p.groups[#p.groups]
		isNil(last.tier); eq(names(last), "Gone")
	end)

	it("does not propose a kept account again for 30 days, unless asked", function()
		local draft = draftOf(ANN)
		local r = O():Apply({ draft })
		eq(r.added, 0); eq(r.kept, 1)
		isNil(draftOf(ANN))
		truthy(draftOf(ANN, { minTier = 1, reviewed = true }))
		Mock.StepClock(29 * DAY)
		A().Inactivity:Invalidate()
		isNil(draftOf(ANN))
		Mock.StepClock(DAY)
		A().Inactivity:Invalidate()
		truthy(draftOf(ANN))
	end)
end)

describe("the review: choices (SPEC-12 §4.1)", function()
	before_boot(function() guild() end)

	it("applies the account's action to every character, one of them may differ", function()
		link()
		local d = draftOf(BOB)
		d.action = "demote"
		d.per[BOBALT] = { action = "remove" }
		local plan = O():Plan({ d })
		eq(#plan.add, 2); eq(#plan.kept, 0)
		local by = {}
		for _, s in ipairs(plan.add) do by[s.g] = s end
		eq(by[BOB].op, "demote"); eq(by[BOB].fromRank, 3); eq(by[BOB].toRank, 4)
		eq(by[BOBALT].op, "remove")
	end)

	it("offers only the ranks below the officer's own, above or below the character's", function()
		local function list(op, rank)
			local out = {}
			for _, r in ipairs(O():RankChoices(op, rank)) do out[#out + 1] = r.index end
			return table.concat(out, ",")
		end
		eq(list("promote", 4), "2,3"); eq(list("demote", 2), "3,4"); eq(list("promote", 2), ""); eq(list("demote", 4), "")
		eq(list("demote", 1), "", "a rank equal to the officer's own")
	end)

	it("leaves out what cannot be done, and says why", function()
		link()
		local function why(guid, choice)
			local d = draftOf(guid, { minTier = 1, reviewed = true })
			for k, v in pairs(choice) do d[k] = v end
			return select(2, O():Resolve(d, guid))
		end
		eq(why(CARL, { action = "promote" }), "rank", "the rank above is the officer's own")
		eq(why(BOBALT, { action = "demote" }), "rank", "already the lowest")
		eq(why(BOB, { action = "demote", rank = 2 }), "rank", "not a demotion")
		eq(why(BOB, { action = "note", text = "old" }), "same")
		eq(why(BOB, { action = "note", text = ("x"):rep(32) }), "long")
		eq(why(BOB, { action = "keep" }), "keep")
		CanGuildRemove = function() return false end
		eq(why(BOB, { action = "remove" }), "permission")
		local d = draftOf(BOB, { minTier = 1, reviewed = true })
		d.action, d.text = "note", ("é"):rep(31)
		truthy(O():Resolve(d, BOB), "31 characters, whatever their bytes")
	end)

	it("does not mark an account reviewed when one of its characters was not kept, even if nothing could be added", function()
		local d = draftOf(CARL)
		d.action = "promote"
		local r = O():Apply({ d })
		eq(r.added, 0); eq(r.kept, 0); eq(r.skipped, 1)
		truthy(draftOf(CARL))
	end)
end)

describe("OPS-02: the queue is ticked by the roster", function()
	before_boot(function() guild() end)

	it("ticks a rank change, a removal and both notes when the roster shows them done", function()
		read()
		local p = add(ANN, "promote", { fromRank = 3, toRank = 2 })
		local d = add(CARL, "demote", { fromRank = 2, toRank = 3 })
		local r = add(BOB, "remove", { fromRank = 3 })
		local n = add(DEE, "note", { noteKind = "public", text = "raider" })
		local o = add(BOBALT, "note", { noteKind = "officer", text = "alt" })
		read()
		for _, e in ipairs({ p, d, r, n, o }) do eq(status(e), "open") end
		member(ANN).rank = 2
		member(CARL).rank = 3
		drop(BOB)
		member(DEE).note = "  raider "
		member(BOBALT).officerNote = "alt"
		read()
		for _, e in ipairs({ p, d, r, n, o }) do eq(status(e), "done") end
		eq(O():OpenCount(), 0)
	end)

	it("ticks nothing on an unrelated change", function()
		read()
		local p = add(ANN, "promote", { fromRank = 3, toRank = 2 })
		local r = add(BOB, "remove", { fromRank = 3 })
		local n = add(DEE, "note", { noteKind = "public", text = "raider" })
		local o = add(BOBALT, "note", { noteKind = "officer", text = "alt" })
		member(ANN).rank = 4                    -- another rank than the one asked
		member(ANN).note = "raider"
		member(BOB).rank = 4
		member(DEE).rank = 2
		member(DEE).note = "raider2"
		member(DEE).officerNote = "raider"      -- the other note
		member(BOBALT).note = "alt"
		drop(CARL)                              -- somebody else leaves
		read()
		for _, e in ipairs({ p, r, n, o }) do eq(status(e), "open") end
		eq(O():OpenCount(), 4)
	end)

	it("closes as gone what waits for a character who left", function()
		read()
		local p = add(ANN, "promote", { fromRank = 3, toRank = 2 })
		local n = add(ANN, "note", { noteKind = "public", text = "x" })
		drop(ANN)
		read()
		eq(status(p), "gone"); eq(status(n), "gone")
	end)

	it("ticks nothing on an incomplete read", function()
		read()
		local r = add(BOB, "remove", { fromRank = 3 })
		drop(BOB)
		member(ANN).guid = nil
		eq(read(), "incomplete")
		eq(status(r), "open")
	end)

	it("is not held back by a mass change (TL-04)", function()
		for i = 1, 30 do
			Mock.guild.members[#Mock.guild.members + 1] = { name = "M" .. i, level = 10, class = "MAGE", rank = 3, online = true,
				zone = "", note = "", officerNote = "", guid = ("Player-1-%08X"):format(0x7000 + i) }
		end
		read()
		local r = add("Player-1-00007001", "remove", { fromRank = 3 })
		for i = 1, 20 do drop(("Player-1-%08X"):format(0x7000 + i)) end
		eq(read(), "held")
		eq(status(r), "done")
	end)

	it("does not read the officer note without the permission: only Mark done closes the entry", function()
		Mock.guild.officerNoteVisible = false
		read()
		local o = add(ANN, "note", { noteKind = "officer", text = "x" })
		member(ANN).officerNote = "x"
		read()
		eq(status(o), "open")
		truthy(O():CanMarkDone(O():Get(o.n)))
		truthy(O():MarkDone(o.n)); eq(status(o), "done")
		local p = add(ANN, "promote", { fromRank = 3, toRank = 2 })
		falsy(O():MarkDone(p.n), "the others are ticked by the roster only")
	end)
end)

describe("OPS-03: expiry, replacement and limits", function()
	before_boot(function() guild() end)

	it("expires an entry after 14 days and deletes a closed one 7 days after it closed", function()
		local e = add(ANN, "remove")
		local c = add(BOB, "remove")
		truthy(O():Cancel(c.n)); falsy(O():Cancel(c.n))
		Mock.StepClock(7 * DAY - 1)
		eq(#O():Entries(), 2)
		Mock.StepClock(1)
		eq(#O():Entries(), 1, "the cancelled one is gone")
		Mock.StepClock(7 * DAY - 1)
		eq(status(e), "open")
		Mock.StepClock(1)
		eq(O():OpenCount(), 0); eq(status(e), "expired")
		member(ANN).rank = 4
		Mock.StepClock(7 * DAY)
		eq(#O():Entries(), 0)
	end)

	it("replaces the open entry of the same character and action, and keeps 200 open ones at most", function()
		local first = add(ANN, "promote", { toRank = 2 })
		local second, replaced = add(ANN, "promote", { toRank = 3 })
		truthy(replaced); isNil(O():Get(first.n)); eq(O():OpenCount(), 1)
		add(ANN, "remove"); eq(O():OpenCount(), 2)
		for i = 3, 200 do truthy(O():Add{ g = ("Player-1-%08X"):format(i), name = "X", op = "remove" }) end
		local e, why = O():Add{ g = "Player-1-0000FFFF", name = "X", op = "remove" }
		isNil(e); eq(why, "full")
		truthy(add(ANN, "promote", { toRank = 2 }), "a replacement still fits")
		eq(O():OpenCount(), 200)
	end)

	it("lists the open entries oldest first, then the closed ones", function()
		local a = add(ANN, "remove")
		Mock.StepClock(10)
		local b = add(BOB, "remove")
		Mock.StepClock(10)
		local c = add(CARL, "remove")
		O():Cancel(a.n)
		local list = O():Entries()
		eq(list[1].n, b.n); eq(list[2].n, c.n); eq(list[3].n, a.n)
	end)
end)

describe("who sees the queue (SPEC-10 Q13)", function()
	before_boot(function() guild() end)

	it("gives a member nothing and a demoted officer loses it (OFF-10)", function()
		add(ANN, "remove")
		local db = A().Config.db.account
		db.chars = { TestRealm = { [ME] = { name = "Tester", guild = A().GuildKey:Current(), seen = GetServerTime() } } }
		guild(3)
		eq(O():OpenCount(), 0); eq(#O():Entries(), 0); eq(O():Proposal{ minTier = 1 }.count, 0)
		isNil(O():Add{ g = ANN, name = "Ann", op = "remove" })
		isNil(O():Apply({}))
		isNil(V():OpenReview())
		A().Officer:CheckDemotion()
		isNil(A().Officer:Peek())
	end)

	it("never goes to the network", function()
		add(ANN, "remove")
		falsy(A().Store.SETS.queue)
		eq(A().Officer:Peek().queue[1].op, "remove")
	end)
end)

describe("the interface of the review and the queue", function()
	before_boot(function() guild() end)

	it("goes through the three steps, fills the queue and shows what to do by hand", function()
		link()
		truthy(A().Shell:OpenView("officers"))
		truthy(V():OpenReview())
		eq(V().review.step, 1); eq(V().review.proposal.count, 2)
		truthy(V():ReviewStep(2))
		local rows = V().ReviewRows(V().review)
		eq(rows[1].header, "90+ days (2)"); eq(#rows, 3)
		local bob, carl = rows[2].draft.account, rows[3].draft.account
		eq(bob.name, "Bob")
		truthy(V():SetAction("remove"))
		truthy(V():SelectTarget(BOBALT))
		truthy(V():SetAction("note")); truthy(V():SetNote("public", "bank alt"))
		eq(#V().CharRows(V().review.drafts[bob.key]), 2)
		truthy(V():SelectAccount(carl.key))
		truthy(V():SetAction("demote"))
		eq(#V():RankOptions(), 2)
		truthy(V():SetRank(4))
		truthy(V():ReviewStep(1)); truthy(V():ReviewStep(2)); truthy(V():ReviewStep(3))
		eq(#V().review.plan.add, 3)
		eq(V().reviewDialog.next:GetLabel(), "Add 3 actions to the queue")
		local r = V():ApplyReview()
		eq(r.added, 3); eq(V().pageId, "queue"); eq(#V().queueRows, 3)
		eq(A().Shell.BadgeText(A().Shell.views.officers), "3")
		local remove
		for _, e in ipairs(V().queueRows) do if e.op == "remove" then remove = e end end
		local d = V():OpenEntry(remove.n)
		eq(d.name:GetText(), "Bob"); eq(d.hand:GetText(), "/gremove Bob"); falsy(d.done:IsShown())
		eq(V().QueueText(remove, "op"), "Remove"); eq(V().QueueText(remove, "status"), "to do")
		d.guildWindow:Click()
		d.cancel:Click()
		eq(status(remove), "cancelled")
		eq(A().Shell.BadgeText(A().Shell.views.officers), "2")
	end)

	it("closes the dialogs when the officer is demoted", function()
		V():OpenReview()
		local e = add(ANN, "remove")
		V():OpenEntry(e.n)
		guild(3)
		falsy(V().reviewDialog:IsShown()); falsy(V().entryDialog:IsShown())
	end)

	it("counts the queue in the diagnostics without names", function()
		add(ANN, "remove")
		local text = table.concat(A().Officer:DebugLines(), "\n")
		contains(text, "queue: open 1")
		falsy(text:find("Ann", 1, true))
	end)
end)

describe("OPS-01: the addon never changes the roster", function()
	before_boot(function() guild() end)

	local GLOBALS = { "GuildPromote", "GuildDemote", "GuildUninvite", "GuildSetLeader", "SetGuildMemberRank",
		"GuildRosterSetPublicNote", "GuildRosterSetOfficerNote", "RunMacroText", "ChatEdit_SendText" }
	local NAMESPACED = { "Promote", "Demote", "Uninvite", "RemoveFromGuild", "SetNote", "SetLeader", "SetGuildRankOrder" }

	local function forbidden()
		local list = {}
		for _, name in ipairs(GLOBALS) do list[#list + 1] = name end
		for _, name in ipairs(NAMESPACED) do list[#list + 1] = "C_GuildInfo." .. name end
		return list
	end

	-- the names of `forbidden` that `source` holds as whole words (CanGuildPromote is not GuildPromote)
	local function named(source)
		local found = {}
		for _, name in ipairs(forbidden()) do
			if (" " .. source .. " "):find("[^%w_]" .. name:gsub("%.", "%%.") .. "[^%w_]") then found[#found + 1] = name end
		end
		return found
	end

	it("names none of the functions that change the roster in any Lua file of the addon", function()
		local seen, found = 0, {}
		for _, file in ipairs(Mock.loadedFiles) do
			if file:find("^AzerothAccord/") and file:find("%.lua$") then
				seen = seen + 1
				local source = Mock.ReadSource(file)
				truthy(source, file)
				for _, name in ipairs(named(source)) do found[#found + 1] = file .. ": " .. name end
			end
		end
		truthy(seen >= 80, "the addon files were really read: " .. seen)
		deepEq(found, {})
	end)

	it("the scan itself finds a call, also behind a string, and not a permission query", function()
		deepEq(named("GuildUninvite(name)"), { "GuildUninvite" })
		deepEq(named([[first("C_GuildInfo.RemoveFromGuild", guid)]]), { "C_GuildInfo.RemoveFromGuild" })
		deepEq(named("if CanGuildPromote() and CanGuildDemote() then end"), {})
		deepEq(named("C_GuildInfo.SetNoteX()"), {})
	end)

	it("does none of it while a review and the queue run", function()
		local called = {}
		for _, name in ipairs(GLOBALS) do _G[name] = function() called[#called + 1] = name end end
		for _, name in ipairs(NAMESPACED) do C_GuildInfo[name] = function() called[#called + 1] = name end end
		A().Shell:OpenView("officers")
		V():OpenReview(); V():ReviewStep(2); V():SetAction("remove"); V():ReviewStep(3); V():ApplyReview()
		for _, e in ipairs(O():Entries()) do V():OpenEntry(e.n).guildWindow:Click() end
		read()
		eq(#called, 0, table.concat(called, ","))
	end)
end)

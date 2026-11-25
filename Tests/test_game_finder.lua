-- The game's Group Finder, privately (M9.8; SPEC-13 §7, ADR 0024): without the capability nothing is offered and nothing
-- fails; with it the button is offered only to the leader, the listing is created only from the click (the mock's
-- C_LFGList.CreateListing and RemoveListing are protected: outside a click they are blocked), always private, and it
-- closes with the guild listing; a listing the game made public switches the capability off for that client build.
local function A() return AzerothAccord end
local function G() return AzerothAccord.Groups end
local function GF() return AzerothAccord.GameFinder end
local function M() return AzerothAccord.GroupsModel end
local function View() return AzerothAccord.GroupsView end
local function Shell() return AzerothAccord.Shell end
local function N() return AzerothAccord.Notify end

local BOB = "Player-1-00000B0B"
local DEADMINES, MOLTEN, ULDAMAN = 36, 409, 70

local function guild()
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Bob", level = 20, class = "MAGE", rank = 3, guid = BOB, online = true },
	} }
end

local function base(Mk, features)
	Mk.features = features or { groups = true, actions = true }
	Mk.player.level, Mk.player.classFile = 20, "PALADIN"
	guild()
end
local function capable(Mk) base(Mk) Mk.lfg.Set{} end
local function absent(Mk) base(Mk) end
local function finderOff(Mk) base(Mk) Mk.lfg.Set{ enabled = false } end
local function ignored(Mk) base(Mk) Mk.lfg.Set{ private = "ignore" } end
local function noField(Mk) base(Mk) Mk.lfg.Set{ private = "absent" } end
local function switchOff(Mk) base(Mk, { groups = false }) Mk.lfg.Set{} end

local function post(spec)
	local s = { kind = "dungeon", act = DEADMINES, need = { t = 1, h = 1, d = 2 } }
	for k, v in pairs(spec or {}) do s[k] = v end
	local rec = G():Post(s)
	truthy(rec, "posted")
	return rec
end

-- The My group page, built.
local function mine()
	truthy(Shell():OpenView("groups"))
	View():ShowPage("mine")
	return View().frame.holders.mine
end

local function gameNotices()
	local out = {}
	for _, e in ipairs(N():Entries()) do if e.module == "groups" and e.kind == "game" then out[#out + 1] = e end end
	return out
end

describe("the game's Group Finder, capability present", function()
	before_boot(capable)

	it("is detected through Compat", function()
		truthy(A().Compat.LFG.Has())
		truthy(A().Compat.LFG.Enabled())
		eq(A().Compat:Feature("gameFinderPrivate"), "available")
		eq(A().Compat.LFG.ActivityFor(DEADMINES), 1001)
		eq(A().Compat.LFG.ActivityFor(MOLTEN), 1101)
		isNil(A().Compat.LFG.ActivityFor(ULDAMAN), "no activity in the game for this instance")
		truthy(GF():Capable())
	end)

	it("offers the button only to the leader of an own open dungeon or raid listing", function()
		local f = mine()
		falsy(f.game:IsShown(), "no listing, no button")
		post()
		View():Redraw()
		truthy(f.game:IsShown())
		eq(f.game:GetLabel(), "Also list in the game's finder")
		local tip = M().GameButton().tip
		eq(tip[3], "Your friends outside the guild can see it too.")
		-- in a party but not its leader
		Mock.group.Set{ members = { { name = "Bob", guid = BOB, inGuild = true } } }
		Mock.group.notLeader = true
		View():Redraw()
		falsy(f.game:IsShown(), "not the leader")
		Mock.group.notLeader = false
		View():Redraw()
		truthy(f.game:IsShown())
		Mock.world.inCombat = true
		View():Redraw()
		falsy(f.game:IsShown(), "not in combat")
		Mock.world.inCombat = false
		eq(#Mock.lfg.created, 0, "offering lists nothing")
	end)

	it("offers nothing for other kinds or for an instance the game's finder does not have", function()
		local rec = post({ kind = "quest", act = "The Defias" })
		isNil((GF():Offer(rec)))
		eq(select(2, GF():Offer(rec)), "kind")
		rec = post({ act = ULDAMAN })
		eq(select(2, GF():Offer(rec)), "activity")
		isNil(M().GameButton())
	end)

	it("creates the listing only from the click, always private and without text", function()
		local rec = post()
		local f = mine()
		-- timers, events, messages and the Groups clean-up never list anything
		Mock.Advance(600)
		A().Bus:Emit("GROUPS_CHANGED", rec.id)
		Mock.Fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
		Mock.Fire("GROUP_ROSTER_UPDATE")
		eq(#Mock.lfg.created, 0)
		eq(Mock.lfg.blocked, 0, "no protected call outside a click")
		f.game:Click()
		eq(#Mock.lfg.created, 1)
		local data = Mock.lfg.created[1]
		eq(data.isPrivateGroup, true, "never public")
		eq(data.activityIDs[1], 1001)
		isNil(data.name); isNil(data.comment)
		eq(Mock.lfg.blocked, 0)
		eq(GF():Listed(), rec.id)
		Mock.Advance(1)
		truthy(Mock.lfg.entry, "the game answered")
		eq(Mock.lfg.entry.privateGroup, true)
		View():Redraw()
		eq(f.game:GetLabel(), "Remove from the game's finder")
		eq(Mock.lfg.updated, 0, "never updated")
		eq(A().Compat:Feature("gameFinderPrivate"), "available")
		eq(#gameNotices(), 0)
		eq(#Mock.errors, 0)
	end)

	it("never lists from code outside a click: the protected call is blocked and the capability turns off", function()
		local rec = post()
		local ok, why = GF():List(rec.id)   -- what a timer or a message handler would do
		falsy(ok)
		eq(Mock.lfg.blocked, 1)
		isNil(Mock.lfg.entry)
		eq(A().Compat:Feature("gameFinderPrivate"), "restricted")
		falsy(GF():Capable())
		isNil(M().GameButton(), "nothing offered for the rest of the session")
		eq(why, "restricted")
	end)

	it("closes with the guild listing in the same click", function()
		post()
		local f = mine()
		f.game:Click()
		Mock.Advance(1)
		truthy(Mock.lfg.entry)
		f.close:Click()
		isNil(M().Own())
		isNil(Mock.lfg.entry, "the game's listing went with the guild listing")
		eq(Mock.lfg.removed, 1)
		eq(Mock.lfg.blocked, 0)
		isNil(GF():Listed())
		falsy(f.game:IsShown())
	end)

	it("also goes when a new post replaces the guild listing", function()
		post()
		local f = mine()
		f.game:Click()
		Mock.Advance(1)
		View():ShowPage("form")
		local form = View().frame.holders.form
		form.post:Click()
		form.post:Click()   -- the second click confirms the replacement
		eq(Mock.lfg.removed, 1)
		isNil(Mock.lfg.entry)
		eq(Mock.lfg.blocked, 0)
	end)

	it("asks for the click when the guild listing closes by itself, and Remove takes it away", function()
		local rec = post({ duration = 1800 })
		local f = mine()
		f.game:Click()
		Mock.Advance(1)
		Mock.Advance(1800 + 120)   -- the guild listing expires; nothing is removed from a timer
		G():Tick()
		eq(Mock.lfg.blocked, 0)
		truthy(Mock.lfg.entry, "still in the game")
		local notes = gameNotices()
		eq(#notes, 1)
		eq(N().Text(notes[1]), "Your group is closed but still in the game's Group Finder. Remove it?")
		View().pageId = "list"
		truthy(N():Open(notes[1]))
		eq(View().pageId, "mine")
		View():Redraw()
		truthy(f.game:IsShown())
		eq(f.game:GetLabel(), "Remove from the game's finder")
		f.game:Click()
		isNil(Mock.lfg.entry)
		eq(Mock.lfg.blocked, 0)
		isNil(GF():Listed())
		eq(rec.id ~= nil, true)
	end)

	it("forgets a listing the game took away by itself", function()
		post()
		mine().game:Click()
		Mock.Advance(1)
		Mock.lfg.Expire()
		isNil(GF():Listed())
		eq(#gameNotices(), 0)
	end)
end)

describe("the game's Group Finder, a listing that turns out public", function()
	before_boot(ignored)

	it("switches the capability off for this client build and asks to remove it", function()
		post()
		local f = mine()
		f.game:Click()
		eq(Mock.lfg.created[1].isPrivateGroup, true, "Accord asked for a private group")
		Mock.Advance(1)
		eq(A().Compat:Feature("gameFinderPrivate"), "missing")
		eq(A().Config.db.account.gameFinder.state, "missing")
		eq(A().Config.db.account.gameFinder.build, "70170")
		local notes = gameNotices()
		eq(#notes, 1)
		eq(N().Text(notes[1]), "The game listed your group publicly. Remove it?")
		View():Redraw()
		eq(f.game:GetLabel(), "Remove from the game's finder")
		f.game:Click()
		isNil(Mock.lfg.entry)
		View():Redraw()
		falsy(f.game:IsShown(), "never offered again")
		isNil(M().GameButton())
		Mock.Reload()
		falsy(A().GameFinder:Capable(), "not after a reload either, on the same build")
		isNil(A().GroupsModel.GameButton())
	end)
end)

describe("the game's Group Finder, an entry without the privateGroup field", function()
	before_boot(noField)

	it("is treated like a public one", function()
		post()
		mine().game:Click()
		Mock.Advance(1)
		eq(A().Compat:Feature("gameFinderPrivate"), "missing")
		eq(#gameNotices(), 1)
		falsy(GF():Capable())
	end)
end)

local function nothingOffered()
	local rec = post()
	isNil((GF():Offer(rec)))
	isNil(M().GameButton())
	local f = mine()
	falsy(f.game:IsShown())
	f.close:Click()
	eq(Mock.lfg.blocked or 0, 0)
	eq(#Mock.errors, 0)
end

describe("the game's Group Finder, capability absent", function()
	describe("no C_LFGList", function()
		before_boot(absent)
		it("offers nothing and fails nowhere", function()
			isNil(C_LFGList)
			falsy(A().Compat.LFG.Has())
			eq(A().Compat:Feature("gameFinderPrivate"), "missing")
			eq(select(2, GF():Capable()), "missing")
			nothingOffered()
			falsy(GF():CloseWith())
			isNil(A().Compat.LFG.ActivityFor(DEADMINES))
			isNil(A().Compat.LFG.EntryPrivate())
		end)
	end)

	describe("the finder switched off in the client", function()
		before_boot(finderOff)
		it("offers nothing", function()
			eq(A().Compat:Feature("gameFinderPrivate"), "missing")
			eq(select(2, GF():Capable()), "disabled")
			nothingOffered()
		end)
	end)

	describe("C_LFGList without RemoveListing", function()
		before_boot(function(Mk) base(Mk) Mk.lfg.Set{ noRemove = true } end)
		it("offers nothing", function()
			falsy(A().Compat.LFG.Has())
			nothingOffered()
		end)
	end)

	describe("a public listing seen earlier on this build", function()
		before_boot(capable)
		it("offers nothing until the client changes", function()
			A().Config.db.account.gameFinder = { build = "70170", state = "missing" }
			eq(select(2, GF():Capable()), "public")
			nothingOffered()
			A().Config.db.account.gameFinder = { build = "70000", state = "missing" }
			truthy(GF():Capable(), "a new client build is tried again")
		end)
	end)
end)

describe("the game's Group Finder, the switch `groups` off", function()
	before_boot(switchOff)

	it("offers nothing, registers nothing and never lists", function()
		eq(A().Features.groups, false)
		falsy(GF().Enabled())
		eq(select(2, GF():Capable()), "off")
		isNil(M().GameButton())
		falsy(GF():List("x:1"))
		falsy(GF():Remove())
		Mock.Fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
		Mock.Fire("ADDON_ACTION_BLOCKED", "AzerothAccord", "C_LFGList.CreateListing()")
		eq(#Mock.lfg.created, 0)
		falsy(A().Diagnostics.Report():find("Game finder:", 1, true))
		eq(#Mock.errors, 0)
	end)
end)

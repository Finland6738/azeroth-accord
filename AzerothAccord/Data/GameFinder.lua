-- GameFinder: the leader's guild group also listed in the game's own Group Finder, privately (SPEC-13 §7, ADR 0024,
-- M9.8). Lua 5.1.
--
-- The Forever dump has C_LFGList.CreateListing with LfgListingCreateData.isPrivateGroup, RemoveListing and
-- GetActiveEntryInfo().privateGroup; it does not say which calls are protected, so they are treated as protected.
-- LFG-01 Never public: the only listing Accord makes is Compat.LFG.CreatePrivate (isPrivateGroup = true, no text); it is
--        never updated. When the game's entry does not answer privateGroup = true, the capability is switched off for
--        that client build (account.gameFinder = { build, state = "missing" }) and the notice `groups.game` asks the
--        leader to remove it.
-- LFG-02 Only from the leader's click: GameFinder:List, :Remove and :CloseWith are called only by the OnClick of a button
--        of the Groups view (UI/GroupsModel.lua), never from a timer, an event, a message or a command; never in combat;
--        only while the player is alone or leads the group. Everything else in this file only reads.
-- LFG-03 No taint: no Blizzard frame is touched, nothing is hooked. ADDON_ACTION_BLOCKED / _FORBIDDEN naming Accord switch
--        the capability to restricted for the session.
-- LFG-04 Offered only for an own open dungeon or raid listing whose instance has an activity in the game's finder.
-- LFG-05 It closes with the guild listing: the click that closes the guild listing (Close, a new Post, an Accept that
--        fills it) removes it too; when the guild listing closes by itself (full, expired, logout) the notice asks for
--        the click. char.groups.game is the id of the guild listing it belongs to.
-- LFG-07 Without the capability (no C_LFGList, finder off, a public listing seen on this build, blocked) nothing is
--        offered and no text shows.
-- Switch: everything waits for Features.On("groups"), like Data/Groups.lua.
local ADDON_NAME, ns = ...
ns = ns or {}
local GameFinder = {}
ns.GameFinder, ns.modules = GameFinder, ns.modules or {}
ns.modules.GameFinder = GameFinder

local type, tostring = type, tostring

GameFinder.FEATURE = "gameFinderPrivate"
local INSTANCE = { dungeon = true, raid = true }

local function compat() return ns.Compat end
local function groups() return ns.Groups end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

local state
local function fresh()
	return {
		restricted = nil,   -- the function a blocked action named, for this session
		pending = false,    -- a CreateListing was sent and the game has not answered yet
		told = {},          -- guild listing id -> a notice was posted for it (once per session)
		stats = { listed = 0, removed = 0, public = 0, blocked = 0, failed = 0 },
	}
end
state = fresh()
GameFinder.state = state

function GameFinder.Enabled() return groups() ~= nil and groups().Enabled() end

local function charDB() return GameFinder.Enabled() and groups().DB() or nil end

local function accountDB()
	local A = ns.Config and ns.Config.db and ns.Config.db.account
	return type(A) == "table" and A or nil
end

local function build() return tostring(compat().BuildInfo().build) end

-- true when a public listing was seen on this client build (saved across sessions).
local function seenPublic()
	local A = accountDB()
	local saved = A and A.gameFinder
	return type(saved) == "table" and saved.state == "missing" and saved.build == build()
end

-- The guild listing id the game's listing belongs to, or nil.
function GameFinder:Listed()
	local g = charDB()
	return g and g.game or nil
end

local function forget()
	local g = charDB()
	if g and g.game then
		g.game = nil
		emit("GROUPS_CHANGED", nil)
	end
	state.pending = false
end

local function restrict(fn)
	state.restricted = fn or "?"
	state.stats.blocked = state.stats.blocked + 1
	compat():SetFeature(GameFinder.FEATURE, compat().RESTRICTED, "blocked: " .. tostring(fn))
	emit("GROUPS_CHANGED", nil)
end

-- Whether the client can list privately now: true, or false and a reason ("off", "restricted", "public", "missing",
-- "disabled").
function GameFinder:Capable()
	if not GameFinder.Enabled() then return false, "off" end
	if state.restricted then return false, "restricted" end
	if seenPublic() then return false, "public" end
	local LFG = compat().LFG
	if not LFG.Has() then return false, "missing" end
	if not LFG.Enabled() then return false, "disabled" end
	return true
end

-- Whether the button is offered for `rec` (the player's own guild listing): the game's activity id, or nil and a reason
-- (a reason of Capable, or "listing", "kind", "activity", "combat", "leader", "listed").
function GameFinder:Offer(rec)
	local ok, why = self:Capable()
	if not ok then return nil, why end
	local G = groups()
	if type(rec) ~= "table" or rec.author ~= compat().Player.GUID() or G:Status(rec) ~= "open" then return nil, "listing" end
	if not INSTANCE[rec.kind] then return nil, "kind" end
	local activity = compat().LFG.ActivityFor(rec.act)
	if not activity then return nil, "activity" end
	if compat().InCombat() then return nil, "combat" end
	if not compat().Group.CanInvite() then return nil, "leader" end
	if state.pending or compat().LFG.HasEntry() then return nil, "listed" end
	return activity
end

-- Lists guild listing `id` in the game's finder, privately. Only from the leader's click (LFG-02). Returns true, or
-- false and a reason.
function GameFinder:List(id)
	local G = groups()
	local rec = G and G:Get(id)
	local activity, why = self:Offer(rec)
	if not activity then return false, why end
	local call, ok = compat().LFG.CreatePrivate(activity)
	if call == compat().RESTRICTED then restrict("CreateListing") return false, "restricted" end
	if state.restricted then return false, "restricted" end   -- ADDON_ACTION_BLOCKED came during the call
	if not ok then state.stats.failed = state.stats.failed + 1 return false, "failed" end
	local g = charDB()
	g.game, state.pending = id, true
	state.stats.listed = state.stats.listed + 1
	emit("GROUPS_CHANGED", id)
	if compat().LFG.HasEntry() then self:Check() end   -- a client that answers at once
	return true
end

-- Removes the game's listing. Only from the leader's click (LFG-02). Returns true, or false and a reason.
function GameFinder:Remove()
	if not GameFinder.Enabled() then return false, "off" end
	if compat().InCombat() then return false, "combat" end
	if not compat().LFG.HasEntry() then forget() return true end
	local call = compat().LFG.Remove()
	if call == compat().RESTRICTED then restrict("RemoveListing") return false, "restricted" end
	if state.restricted then return false, "restricted" end
	if call ~= compat().AVAILABLE then state.stats.failed = state.stats.failed + 1 return false, "failed" end
	state.stats.removed = state.stats.removed + 1
	forget()
	return true
end

-- In the click that may have closed the guild listing (Close, Post, Accept, Update): the game's listing goes with it
-- (LFG-05). Returns true when it removed one.
function GameFinder:CloseWith()
	local id = self:Listed()
	if not id then return false end
	local rec = groups():Get(id)
	if rec and groups():Status(rec) == "open" then return false end
	return self:Remove() and true or false
end

-- The notice `groups.game`: the game's listing turned out public, or outlived its guild listing. A click on it opens
-- My group, where the Remove button is.
local function notice(id, text)
	local N = ns.Notify
	if state.told[id .. text] or not (N and N.Enabled()) then return end
	state.told[id .. text] = true
	N:Post("groups", "game", { key = "game#" .. id .. "#" .. text, text = text, view = "groups", page = "mine",
		char = compat().Player.GUID(), still = function() return GameFinder:Listed() ~= nil and compat().LFG.HasEntry() end })
end

-- The game's listing turned out public (LFG-01): never offered again on this build, and the leader is asked to remove it.
local function public(id)
	local A = accountDB()
	if A then A.gameFinder = { build = build(), state = "missing" } end
	state.stats.public = state.stats.public + 1
	compat():SetFeature(GameFinder.FEATURE, compat().MISSING, "the game listed a group publicly")
	notice(id, "GRP_NOTICE_GAME_PUBLIC")
	emit("GROUPS_CHANGED", id)
end

-- Looks at the game's listing (an event, the guild listing changed): reads only, never writes to the game.
function GameFinder:Check()
	local id = self:Listed()
	if not id then return end
	local LFG = compat().LFG
	if not LFG.HasEntry() then
		if not state.pending then forget() end   -- the game removed it (full, timeout) or someone else did
		return
	end
	state.pending = false
	if LFG.EntryPrivate() ~= true then
		if not seenPublic() then public(id) end
		return
	end
	local rec = groups():Get(id)
	if not rec or groups():Status(rec) ~= "open" then notice(id, "GRP_NOTICE_GAME_STALE") end
end

function GameFinder:OnCreationFailed()
	if state.pending then
		state.stats.failed = state.stats.failed + 1
		forget()
	end
end

-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN (isTainted = the addon's name, function).
function GameFinder:OnBlocked(addon, fn)
	if addon == ADDON_NAME and (fn == nil or tostring(fn):find("LFGList", 1, true) or tostring(fn):find("Listing", 1, true)) then
		restrict(fn)
	end
end

-- Whether the player's game listing came from Accord and is still there (the Remove button).
function GameFinder:CanRemove()
	return self:Listed() ~= nil and compat().LFG.HasEntry()
end

function GameFinder:DebugLines()
	local s = state.stats
	local ok, why = self:Capable()
	return { ("Game finder: %s; listed %d, removed %d, public %d, blocked %d, failed %d%s"):format(ok and "available" or ("not offered (" .. why .. ")"),
		s.listed, s.removed, s.public, s.blocked, s.failed, self:Listed() and ", one listed now" or "") }
end

function GameFinder:Reset()
	state = fresh()
	GameFinder.state = state
end

if ns.addon then
	ns.addon.GameFinder = GameFinder
	if ns.Bus then
		ns.Bus:On("GROUPS_CHANGED", function() if GameFinder.Enabled() then GameFinder:Check() end end)
	end
	LibStub("AceEvent-3.0"):Embed(GameFinder)
	if ns.OnEnable then
		ns.OnEnable(function()
			if not GameFinder.Enabled() then return end
			GameFinder:RegisterEvent("ADDON_ACTION_BLOCKED", function(_, addon, fn) GameFinder:OnBlocked(addon, fn) end)
			GameFinder:RegisterEvent("ADDON_ACTION_FORBIDDEN", function(_, addon, fn) GameFinder:OnBlocked(addon, fn) end)
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Game finder", function() return GameFinder:DebugLines() end) end
			if not compat().LFG.Has() then return end
			local function check() GameFinder:Check() end
			GameFinder:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", check)
			GameFinder:RegisterEvent("LFG_LIST_ENTRY_EXPIRED_TIMEOUT", check)
			GameFinder:RegisterEvent("LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS", check)
			GameFinder:RegisterEvent("LFG_LIST_ENTRY_CREATION_FAILED", function() GameFinder:OnCreationFailed() end)
		end)
	end
end

-- Demo: demo mode, an invented guild in every view (SPEC-11 §3, M7.4). Lua 5.1.
-- `/accord demo` enters, the same command (or `/accord demo off`, or the button of the strip) leaves.
--
--   * Sees: Compat answers for the character, the guild and the roster from an overlay (Compat:SetOverlay), so every
--     module reads the invented guild exactly as it would read the real one; the optional native sources (the club's
--     professions and Discord, the guild recipe directory, the bank, the BattleTag) answer "not available" and the views
--     use the shared records of the demo, as they do when the server gives nothing.
--   * Sends nothing: Transport:Send refuses every message with the reason "demo" (the queue stays as it was, and goes out
--     after the exit) and what arrives is dropped; Sync starts no timer.
--   * Saves nothing: Config.db.account and Config.db.char point at deep copies of the saved tables for the whole demo;
--     AzerothAccordDB and AzerothAccordCharDB (what the game writes) are never touched. Whatever is done meanwhile (a like,
--     a request, a main, the theme) goes into the copies, which are thrown away at the exit. The demo never stays on: a
--     /reload or a logout starts from the real data.
--   * The real data comes back untouched; the real guild comes back with a GUILD_CHANGED, so the views redraw as for a
--     change of guild, and the sync starts again (the first HELLO 10-30 seconds later, as at login).
-- The invented guild is in Data/Demo.lua.
-- Bus: DEMO_CHANGED(active) after the mode changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Demo = {}
ns.Demo, ns.modules = Demo, ns.modules or {}
ns.modules.Demo = Demo

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

local state = { active = false, real = nil, readOnly = nil, data = nil, enteredAt = nil, enters = 0 }
Demo.state = state

local function L() return ns.L end
local function compat() return ns.Compat end

function Demo:IsActive() return state.active end

-- The saved table of `scope` ("account" | "char") the game writes, also while the demo works on copies.
function Demo:Real(scope)
	if state.active and state.real then return state.real[scope] end
	return ns.Config and ns.Config.db[scope] or nil
end

---------------------------------------------------------------------------------------------------------------------
-- The overlay: what the game would answer, from the invented guild
---------------------------------------------------------------------------------------------------------------------
local function copyRow(row)
	local out = {}
	for k, v in pairs(row) do out[k] = v end
	return out
end

local function buildOverlay(data)
	local rows, ranks, me = data.roster, data.ranks, data.player
	local online = 0
	for _, r in ipairs(rows) do if r.online then online = online + 1 end end
	local function no() return nil end
	local function empty() return {} end
	local MISSING = compat().MISSING
	return {
		Guild = {
			InGuild = function() return true end,
			GuildName = function() return data.guildName end,
			PlayerRank = function() return data.guildName, ranks[me.rankIndex + 1].name, me.rankIndex end,
			GuildRealm = no,
			ClubId = no,
			IsGuildLeader = function() return me.rankIndex == 0 end,
			IsOfficer = function() return ranks[me.rankIndex + 1].officer == true end,
			CanViewOfficerNote = function() return true end,
			RequestRoster = function() return compat().AVAILABLE end,   -- nothing to ask: the roster is already here
			MayDo = function() return true end,
			Ranks = function()
				local out = {}
				for i, rank in ipairs(ranks) do out[i] = { index = i - 1, name = rank.name } end
				return out
			end,
			RosterCount = function() return #rows, online end,
			LastOnline = function(index) return rows[index] and rows[index].lastOnlineHours or nil end,
			RosterRow = function(index) return rows[index] and copyRow(rows[index]) or nil end,
			Roster = function()
				local out = {}
				for i, r in ipairs(rows) do out[i] = copyRow(r) end
				return out
			end,
			RankIsOfficer = function(rankIndex)
				if type(rankIndex) ~= "number" then return nil end
				local rank = ranks[rankIndex + 1]
				return rank ~= nil and rank.officer == true
			end,
		},
		Player = {
			Name = function() return me.name end,
			Realm = function() return data.realm end,
			RealmDisplay = function() return data.realm end,
			GUID = function() return me.guid end,
			Level = function() return me.level end,
			ClassID = function() return me.classID end,
			ClassFile = function() return me.classFile end,
			BattleTag = no,
			InfoByGUID = no,
		},
		Club = {
			MemberInfo = no, GuildMembers = no,
			SendBattleTagFriendRequest = function() return MISSING end,
		},
		TradeSkill = {
			GuildRecipesEnabled = no,
			QueryGuildMemberRecipes = function() return MISSING end,
			GuildMemberRecipes = no,
			NumGuildTradeSkill = function() return 0 end,
			OwnProfessions = empty, RecipeIDs = no, RecipeInfo = no, BaseProfessionInfo = no, RecipeMeta = no,
		},
		Bank = {
			Enabled = function() return false end,
			NumTabs = function() return 0 end,
			TabInfo = no, Item = no, Money = no, CurrentTab = no,
			QueryTab = function() return MISSING end,
			QueryLog = function() return MISSING end,
			ItemLog = empty, MoneyLog = empty,
		},
		Group = { Invite = function() return false end },   -- an invitation would go to the server
		Chat = { OpenWhisper = function() return false end },
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Enter and leave
---------------------------------------------------------------------------------------------------------------------
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

-- Puts the invented guild into the copies of the saved tables.
local function fill(data, account, char)
	account.token = data.token   -- the token of the invented account: the mutual listing of its characters then holds
	account.chars = { [data.realm] = data.ownChars }
	account.mains = { [data.realm] = data.main }
	account.settings.discord = nil   -- the player's own contact name is not shown
	local guild = { firstSeen = state.enteredAt, lastSeen = state.enteredAt, store = { sets = data.sets },
		likes = data.guildData.likes, bank = data.guildData.bank, officer = data.guildData.officer,
		craftAsks = data.guildData.craftAsks }
	account.guilds = { [data.key] = guild }
	char.outbox = {}
end

-- Enters demo mode. Returns true, or false and a reason ("active", "config", "data").
function Demo:Enter()
	if state.active then return false, "active" end
	local Config, C = ns.Config, compat()
	if not (Config and Config.loaded and C and ns.DemoData and ns.Role and ns.GuildKey) then return false, "config" end
	local now = C.ServerTime()
	local ok, data = pcall(ns.DemoData.Build, now)
	if not ok then
		if geterrorhandler then geterrorhandler()(data) end
		return false, "data"
	end
	state.real = { account = Config.db.account, char = Config.db.char }
	state.readOnly = { account = Config.readOnly.account, char = Config.readOnly.char }
	state.data, state.enteredAt = data, now
	Config.db.account, Config.db.char = Config.Copy(state.real.account), Config.Copy(state.real.char)
	Config.readOnly.account, Config.readOnly.char = nil, nil   -- the copies are free to change: nothing of them is saved
	fill(data, Config.db.account, Config.db.char)
	local set, why = C:SetOverlay(buildOverlay(data))
	if not set then
		Config.db.account, Config.db.char = state.real.account, state.real.char
		Config.readOnly.account, Config.readOnly.char = state.readOnly.account, state.readOnly.char
		state.real, state.data = nil, nil
		if geterrorhandler then geterrorhandler()("Demo overlay: " .. tostring(why)) end
		return false, "data"
	end
	state.active = true
	state.enters = state.enters + 1
	ns.Role:Refresh()   -- the demo guild: ROLE_CHANGED and GUILD_CHANGED, so every module takes the demo data
	if ns.Notary then ns.Notary:AddSalt(ns.Config.Base64(data.saltBytes), now - 100 * 86400) end   -- the player is an officer
	emit("DEMO_CHANGED", true)
	return true
end

-- Leaves demo mode: the real tables, the real guild, the sync again. Returns true, or false and "inactive".
function Demo:Exit()
	if not state.active then return false, "inactive" end
	local Config = ns.Config
	state.active = false   -- first: from here on the transport and the sync work as usual
	compat():ClearOverlay()
	Config.db.account, Config.db.char = state.real.account, state.real.char
	Config.readOnly.account, Config.readOnly.char = state.readOnly.account, state.readOnly.char
	state.real, state.readOnly, state.data = nil, nil, nil
	ns.Role:Refresh()   -- the real guild (or none): GUILD_CHANGED, and Sync starts again
	emit("DEMO_CHANGED", false)
	return true
end

function Demo:Toggle()
	if state.active then return self:Exit() end
	return self:Enter()
end

---------------------------------------------------------------------------------------------------------------------
-- /accord demo and /accord debug
---------------------------------------------------------------------------------------------------------------------
-- `input` is what was typed after /accord: "demo", "demo off", "demo on".
function Demo.Command(input)
	local word = tostring(input or ""):lower():match("^%s*%S+%s+(%S+)")
	local addon = ns.addon
	local function say(key) if addon then addon:Print(L()[key]) end end
	local wantOn, wantOff = word == "on", word == "off"
	if state.active and not wantOn then
		Demo:Exit()
		say("DEMO_LEFT")
		return
	end
	if not state.active and wantOff then say("DEMO_NOT_ON") return end
	if state.active then say("DEMO_ALREADY") return end
	local ok = Demo:Enter()
	if not ok then say("DEMO_FAILED") return end
	say("DEMO_ENTERED")
	if ns.Shell and not ns.Shell:IsShown() and ns.Window then ns.Window:Open() end
end

function Demo:DebugLines()
	if not state.active then return { "Demo: off" } end
	return { ("Demo: ON since %d s, nothing is sent or saved (entered %d time(s) this session)"):format(
		(compat().ServerTime() - (state.enteredAt or 0)), state.enters) }
end

if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Demo", function() return Demo:DebugLines() end) end
if ns.addon then ns.addon.Demo = Demo end

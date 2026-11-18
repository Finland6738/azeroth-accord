-- Compat: the only door to the game API (SPEC-01 §3, §5). Every call is guarded: a missing, failing or restricted API
-- turns one feature off, never the addon. Lua 5.1.
-- Adapted from Azeroth Guild Finder (Core/Compat.lua), same owner, GPL-3.0 (ADR 0018): the guarded calls, secret
-- values, guild, player, restrictions, time and encoding come from there; the channel helpers are left out (Accord uses
-- only GUILD, OFFICER and WHISPER, ADR 0004) and the club, group, trade skill, guild bank and Battle.net helpers and
-- the feature capabilities of SPEC-01 §5 are new.
--
-- Every name used here is in the Forever API dump (../WoW-Addons/docs/api.json) except C_TradeSkillUI.GetAllRecipeIDs
-- and GetFilteredRecipeIDs and GetGuildRosterLastOnline, marked [verify]. The M0 probe results are not in yet, so the
-- APIs the spec marks [verify] (S2 club fields, S3 guild recipes, S4 own recipes, S5 OFFICER, S7 group GUIDs, S8
-- BattleTag, S9 bank logs) all go through here and degrade to nil / false / "unknown" without an error.
local ADDON_NAME, ns = ...
ns = ns or {}
local Compat = {}
ns.Compat, ns.modules = Compat, ns.modules or {}
ns.modules.Compat = Compat

local AVAILABLE, MISSING, ERROR, RESTRICTED = "available", "missing", "error", "restricted"
Compat.AVAILABLE, Compat.MISSING, Compat.ERROR, Compat.RESTRICTED = AVAILABLE, MISSING, ERROR, RESTRICTED
-- States of a feature capability (SPEC-01 §5): it works, it does not, or the client has the API but the data has not
-- shown yet whether the server fills it.
local UNKNOWN = "unknown"
Compat.UNKNOWN = UNKNOWN

local type, pcall, select, pairs, ipairs, tostring, tonumber, unpack = type, pcall, select, pairs, ipairs, tostring, tonumber, unpack
local floor, min = math.floor, math.min

---------------------------------------------------------------------------------------------------------------------
-- Resolve, secret values, guarded calls
---------------------------------------------------------------------------------------------------------------------

-- "C_Club.GetGuildClubId" -> the value in the global table, or nil. Never raises.
function Compat.Resolve(path)
	if type(path) ~= "string" or path == "" then return nil end
	local value = _G
	for part in path:gmatch("[^.]+") do
		if type(value) ~= "table" then return nil end
		local ok, nextValue = pcall(function() return value[part] end)
		if not ok then return nil end
		value = nextValue
	end
	return value
end
local Resolve = Compat.Resolve

-- A secret value can be passed around but not read, compared or used in arithmetic: never look inside one.
-- The client functions are looked up on every call (they may appear late, tests replace them).
function Compat.IsSecret(value)
	if value == nil then return false end
	if issecretvalue and issecretvalue(value) then return true end
	if canaccessvalue and not canaccessvalue(value) then return true end
	if type(value) == "table" and issecrettable and issecrettable(value) then return true end
	return false
end
local IsSecret = Compat.IsSecret

-- The value, or nil when the client hides it.
function Compat.Readable(value)
	if IsSecret(value) then return nil end
	return value
end
local Readable = Compat.Readable

local function restrictedMessage(message)
	message = tostring(message):lower()
	return message:find("restrict", 1, true) or message:find("secret", 1, true) or message:find("forbidden", 1, true)
		or message:find("blocked", 1, true) or message:find("lockdown", 1, true)
end

-- Runs fn(...) under pcall. Returns state, detail, count, values-table. A secret result is dropped (nil) and the
-- state becomes restricted; an error that talks about restrictions is restricted, any other error is error.
local function run(fn, ...)
	if type(fn) ~= "function" then return MISSING, "not a function", 0, {} end
	local packed = { pcall(fn, ...) }
	local n = #packed
	if not packed[1] then
		local message = tostring(packed[2])
		return restrictedMessage(message) and RESTRICTED or ERROR, message:sub(1, 120), 0, {}
	end
	local state, values, count = AVAILABLE, {}, n - 1
	for i = 1, count do
		local v = packed[i + 1]
		if IsSecret(v) then state, v = RESTRICTED, nil end
		values[i] = v
	end
	return state, state == RESTRICTED and "secret value" or nil, count, values
end

-- Compat.Call("C_Club.GetGuildClubId", ...) -> state, value1, value2, ...
function Compat.Call(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	return state, unpack(values, 1, count)
end

-- First value only when the call is available, else nil (plus the state as second result).
local function first(path, ...)
	local state, _, _, values = run(Resolve(path), ...)
	if state == AVAILABLE then return values[1], state end
	return nil, state
end

-- Every value when the call is available (a table and the count), else nil, 0, state.
local function all(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	if state == AVAILABLE then return values, count, state end
	return nil, 0, state
end

-- Every value of a call that ran, secret ones as nil (a table and the count, plus the state, "restricted" when
-- something was hidden), or nil, 0, state when it did not run. For rows where one hidden field must not hide the rest.
local function readable(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	if state == AVAILABLE or (state == RESTRICTED and count > 0) then return values, count, state end
	return nil, 0, state
end

-- A copy of the readable plain fields of a table the client gave (secret fields and nested secret tables dropped).
-- Nested tables are copied one level deep; anything deeper is dropped (no client table Accord reads is deeper).
local function readableCopy(t, depth)
	if type(t) ~= "table" or IsSecret(t) then return nil end
	depth = depth or 0
	local out = {}
	for k, v in pairs(t) do
		if not IsSecret(k) and not IsSecret(v) then
			if type(v) == "table" then
				if depth < 1 then out[k] = readableCopy(v, depth + 1) end
			elseif type(v) ~= "function" and type(v) ~= "userdata" then
				out[k] = v
			end
		end
	end
	return out
end
Compat.ReadableCopy = readableCopy

local function str(v) return type(v) == "string" and v ~= "" and v or nil end
local function num(v) return type(v) == "number" and v == v and v or nil end

---------------------------------------------------------------------------------------------------------------------
-- Guild
---------------------------------------------------------------------------------------------------------------------
local Guild = {}
Compat.Guild = Guild
Guild.MAX_ROSTER = 1000   -- a guild has at most 1000 members

-- Guild club id (the C_Club side of the guild); nil without a guild or when the API is missing.
function Guild.ClubId()
	local id = first("C_Club.GetGuildClubId")
	if type(id) == "number" or type(id) == "string" then return id end
	return nil
end
local guildClubId = Guild.ClubId

-- The member ids of the guild club, in the order the client gives them.
local function clubMemberIds()
	local clubId = guildClubId()
	if not clubId then return nil, nil end
	local ids = first("C_Club.GetClubMembers", clubId)
	if type(ids) ~= "table" then return nil, clubId end
	return ids, clubId
end

function Guild.InGuild()
	local v, state = first("IsInGuild")
	if state == AVAILABLE then return v and true or false end
	return guildClubId() ~= nil   -- the fallback: a guild club exists
end

function Guild.GuildName()
	local name, state = first("GetGuildInfo", "player")
	if str(name) then return name end
	local clubId = state ~= AVAILABLE and guildClubId() or nil
	if clubId then
		local info = first("C_Club.GetClubInfo", clubId)
		if type(info) == "table" and str(info.name) then return info.name end
	end
	return nil
end

-- guildName, rankName, rankIndex (0 = Guild Master), or nil.
function Guild.PlayerRank()
	local values = all("GetGuildInfo", "player")
	if values and type(values[1]) == "string" then return values[1], values[2], values[3] end
	return nil
end

function Guild.IsGuildLeader()
	local v, state = first("IsGuildLeader")
	if state == AVAILABLE then return v and true or false end
	local _, _, rankIndex = Guild.PlayerRank()
	return rankIndex == 0
end

-- Officer: the client says so, or the player leads the guild.
function Guild.IsOfficer()
	if Guild.IsGuildLeader() then return true end
	local v, state = first("C_GuildInfo.IsGuildOfficer")
	return state == AVAILABLE and v and true or false
end

-- Asks the server for a fresh roster (GUILD_ROSTER_UPDATE follows). Returns the call state.
function Guild.RequestRoster()
	local _, state = first("C_GuildInfo.GuildRoster")
	return state
end

-- total, online. Falls back to the guild club members; online is nil when only the club is known.
function Guild.RosterCount()
	local values = all("GetNumGuildMembers")
	if values and type(values[1]) == "number" then return values[1], values[2] end
	local ids = clubMemberIds()
	if ids then return #ids, nil end
	return 0, nil
end

-- Hours since the member was last online, from years, months, days, hours. Months count 30 days, years 365.
function Compat.LastOnlineHours(years, months, days, hours)
	years, months, days, hours = tonumber(years) or 0, tonumber(months) or 0, tonumber(days) or 0, tonumber(hours) or 0
	return years * 8760 + months * 720 + days * 24 + hours
end

-- Hours since member i was last online (nil while online or unknown). GetGuildRosterLastOnline is [verify].
function Guild.LastOnline(index)
	local values = all("GetGuildRosterLastOnline", index)
	if values then
		if values[1] == nil and values[2] == nil and values[3] == nil and values[4] == nil then return nil end
		return Compat.LastOnlineHours(values[1], values[2], values[3], values[4])
	end
	return nil
end

-- One roster row: { name, rankName, rankIndex, level, classFile, classID, zone, note, officerNote, online, guid,
-- lastOnlineHours, source } or nil. GetGuildRosterInfo first; the C_Club members when it is missing.
-- `source` is "roster" or "club" (ADR 0010: the interface says where a value comes from).
function Guild.RosterRow(index)
	local values, _, state = readable("GetGuildRosterInfo", index)
	if values and type(values[1]) == "string" then
		local online = values[9] and true or false
		return {
			name = values[1], rankName = str(values[2]), rankIndex = num(values[3]), level = num(values[4]),
			classFile = str(values[11]), zone = str(values[6]), note = str(values[7]), officerNote = str(values[8]),
			online = online, guid = str(values[17]), lastOnlineHours = (not online) and Guild.LastOnline(index) or nil,
			source = "roster",
		}
	end
	if values then return nil end   -- the client answered: no such row (or no readable name)
	local ids, clubId = clubMemberIds()
	local memberId = ids and ids[index]
	if memberId == nil then return nil end
	local info = Compat.Club.MemberInfo(clubId, memberId)
	if not info then return nil end
	return {
		name = info.name, rankName = info.guildRank, rankIndex = info.guildRankOrder and (info.guildRankOrder - 1) or nil,
		level = info.level, classID = info.classID, zone = info.zone, note = info.memberNote, officerNote = info.officerNote,
		online = info.online, guid = info.guid, lastOnlineHours = info.lastOnlineHours, source = "club",
	}
end

-- Every roster row (at most MAX_ROSTER).
function Guild.Roster()
	local rows = {}
	if not Guild.InGuild() then return rows end
	local total = Guild.RosterCount()
	total = min(tonumber(total) or 0, Guild.MAX_ROSTER)
	for i = 1, total do
		local row = Guild.RosterRow(i)
		if row then rows[#rows + 1] = row end
	end
	return rows
end

local function shortName(name)
	return ((name:match("^[^%-]+") or name):lower())
end

-- The rank index (0 = Guild Master) of the roster member called `name` ("Name" or "Name-Realm", compared without the
-- realm and the case), or nil while the roster is not loaded or has no such member. The trust rules of SPEC-02 §6
-- read ranks from here, never from a message.
function Guild.MemberRankIndex(name)
	if type(name) ~= "string" or name == "" or not Guild.InGuild() then return nil end
	local want = shortName(name)
	local total = Guild.RosterCount()   -- (two results: tonumber would read the second as a base)
	total = min(tonumber(total) or 0, Guild.MAX_ROSTER)
	for i = 1, total do
		local row = Guild.RosterRow(i)
		if row and type(row.name) == "string" and shortName(row.name) == want then return row.rankIndex end
	end
	return nil
end

-- true when members of rank `rankIndex` read officer chat: the rank of the Guild Master, or a rank whose permissions
-- (C_GuildInfo.GuildControlGetRankFlags, 1-based rank order) have "officer chat listen", the third flag [verify in
-- game]. nil when the client does not say.
Guild.OFFICER_LISTEN_FLAG = 3
function Guild.RankIsOfficer(rankIndex)
	if type(rankIndex) ~= "number" then return nil end
	if rankIndex == 0 then return true end
	local flags, state = first("C_GuildInfo.GuildControlGetRankFlags", rankIndex + 1)
	if state ~= AVAILABLE or type(flags) ~= "table" then return nil end
	return flags[Guild.OFFICER_LISTEN_FLAG] == true
end

-- true when the roster member called `name` is an officer according to this client's roster (SPEC-02 §6, NET-11).
function Guild.MemberIsOfficer(name)
	return Guild.RankIsOfficer(Guild.MemberRankIndex(name)) == true
end

---------------------------------------------------------------------------------------------------------------------
-- Club (the guild seen through C_Club): profession and Discord fields of ClubMemberInfo are [verify] S2
---------------------------------------------------------------------------------------------------------------------
local Club = {}
Compat.Club = Club

-- The member as a plain table: the readable fields of ClubMemberInfo, plus `online` and `lastOnlineHours`.
-- nil when the API is missing, fails or gives nothing.
function Club.MemberInfo(clubId, memberId)
	if clubId == nil or memberId == nil then return nil end
	local info = first("C_Club.GetMemberInfo", clubId, memberId)
	info = readableCopy(info)
	if not info then return nil end
	local offline = info.lastOnlineYear ~= nil or info.lastOnlineMonth ~= nil or info.lastOnlineDay ~= nil or info.lastOnlineHour ~= nil
	info.online = not offline
	info.lastOnlineHours = offline and Compat.LastOnlineHours(info.lastOnlineYear, info.lastOnlineMonth, info.lastOnlineDay, info.lastOnlineHour) or nil
	return info
end

-- Every member of the guild club as plain tables; nil when the club API is missing.
function Club.GuildMembers()
	local ids, clubId = clubMemberIds()
	if not ids then return nil end
	local out = {}
	for i = 1, min(#ids, Guild.MAX_ROSTER) do
		local info = Club.MemberInfo(clubId, ids[i])
		if info then out[#out + 1] = info end
	end
	return out
end

-- The professions of a member info: { { id, name, rank }, ... } (0 to 2 entries) from the profession1/2 fields.
function Club.Professions(info)
	local out = {}
	if type(info) ~= "table" then return out end
	for i = 1, 2 do
		local name, rank, id = str(info["profession" .. i .. "Name"]), num(info["profession" .. i .. "Rank"]), num(info["profession" .. i .. "ID"])
		if name or id then out[#out + 1] = { id = id, name = name, rank = rank } end
	end
	return out
end

-- The Discord handle in a member info, or nil. The shape of DiscordChatInfo is not in the dump [verify S2]: a string
-- is taken as it is, a table gives its first plain string field among the likely names.
Club.DISCORD_FIELDS = { "username", "userName", "name", "handle", "discordName", "displayName" }
function Club.Discord(info)
	local d = type(info) == "table" and info.discordInfo or nil
	if type(d) == "string" then return str(d) end
	if type(d) ~= "table" then return nil end
	for _, field in ipairs(Club.DISCORD_FIELDS) do
		if str(d[field]) then return d[field] end
	end
	return nil
end

-- Sends the client's own BattleTag friend request to a club member (SPEC-05 §4) [verify S8]. Returns the call state.
function Club.SendBattleTagFriendRequest(clubId, memberId)
	local _, state = first("C_Club.SendBattleTagFriendRequest", clubId, memberId)
	return state
end

---------------------------------------------------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------------------------------------------------
local Player = {}
Compat.Player = Player

-- "Horde" or "Alliance" (English name), nil when unknown.
function Player.Faction()
	local v = first("UnitFactionGroup", "player")
	if v == "Horde" or v == "Alliance" then return v end
	return nil
end

-- The character name without the realm, nil when unknown.
function Player.Name()
	return str((first("UnitName", "player")))
end

-- Normalized realm name (no spaces), falling back to GetRealmName without spaces.
function Player.Realm()
	local v = first("GetNormalizedRealmName")
	if not str(v) then
		v = first("GetRealmName")
		if type(v) == "string" then v = v:gsub("[%s%-']", "") end
	end
	return str(v)
end

-- The realm as the game shows it (with spaces), nil when unknown.
function Player.RealmDisplay()
	return str((first("GetRealmName")))
end

function Player.GUID()
	return str((first("UnitGUID", "player")))
end

function Player.Level()
	return num((first("UnitLevel", "player")))
end

function Player.ClassID()
	local values = all("UnitClass", "player")
	return values and num(values[3]) or nil
end

function Player.ClassFile()
	local values = all("UnitClass", "player")
	return values and str(values[2]) or nil
end

-- The player's own BattleTag ("Name#1234") [verify S8]: BNet_GetBattleTagSelf, else the second result of BNGetInfo.
function Player.BattleTag()
	local tag = first("BNet_GetBattleTagSelf")
	if str(tag) and tag:find("#", 1, true) then return tag end
	local values = all("BNGetInfo")
	if values and str(values[2]) and values[2]:find("#", 1, true) then return values[2] end
	return nil
end

-- Playable classes the client knows: { { id, name, file }, ... } sorted by id, or nil when the API gives nothing.
function Compat.Classes()
	local count = first("GetNumClasses")
	local limit = type(count) == "number" and count >= 1 and count <= 40 and count or 20
	local list = {}
	for id = 1, limit do
		local info = first("C_CreatureInfo.GetClassInfo", id)
		if type(info) == "table" and type(info.classID) == "number" then
			list[#list + 1] = { id = info.classID, name = str(info.className), file = str(info.classFile) }
		end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Group and raid (SPEC-07 §3.1): GUIDs may be secret in an instance [verify S7]
---------------------------------------------------------------------------------------------------------------------
local Group = {}
Compat.Group = Group

function Group.InRaid()
	return (first("IsInRaid")) and true or false
end

function Group.InGroup()
	return (first("IsInGroup")) and true or false
end

-- Members of the group including the player (0 when alone or unknown).
function Group.Size()
	return num((first("GetNumGroupMembers"))) or 0
end

-- The unit tokens of the other members: raid1..raidN (without the player) or party1..party4.
function Group.Units()
	local units, n = {}, Group.Size()
	if n <= 1 then return units end
	if Group.InRaid() then
		local me = Player.GUID()
		for i = 1, min(n, 40) do
			local unit = "raid" .. i
			local guid = str((first("UnitGUID", unit)))
			if guid == nil or guid ~= me then units[#units + 1] = unit end
		end
	else
		for i = 1, min(n - 1, 4) do units[#units + 1] = "party" .. i end
	end
	return units
end

-- What the addon may know of one unit: { unit, guid, name, inGuild } with nil for anything secret or missing.
function Group.Member(unit)
	local guid = str((first("UnitGUID", unit)))
	local values = readable("UnitName", unit)
	local name = values and str(values[1]) or nil
	if name and values and str(values[2]) then name = name .. "-" .. values[2] end
	local isIn, state = first("UnitIsInMyGuild", unit)
	local inGuild = nil
	if state == AVAILABLE then inGuild = isIn and true or false end
	return { unit = unit, guid = guid, name = name, inGuild = inGuild }
end

-- The other members of the group: a list of Group.Member tables (secret ones kept with nil fields, so a count is
-- honest about what could not be read).
function Group.Members()
	local out = {}
	for _, unit in ipairs(Group.Units()) do out[#out + 1] = Group.Member(unit) end
	return out
end

-- GetRaidRosterInfo(i) as a table: { name, rank, subgroup, level, classFile, zone, online, isDead }; nil when missing.
function Group.RaidRosterRow(i)
	local values = readable("GetRaidRosterInfo", i)
	if not values or not str(values[1]) then return nil end
	return { name = values[1], rank = num(values[2]), subgroup = num(values[3]), level = num(values[4]), classFile = str(values[6]),
		zone = str(values[7]), online = values[8] and true or false, isDead = values[9] and true or false }
end

function Compat.InInstance()
	local values = all("IsInInstance")
	if not values then return false, nil end
	return values[1] and true or false, str(values[2])
end

---------------------------------------------------------------------------------------------------------------------
-- Trade skills (SPEC-06): the guild recipe directory [verify S3] and the own recipes [verify S4]
---------------------------------------------------------------------------------------------------------------------
local TradeSkill = {}
Compat.TradeSkill = TradeSkill

-- true / false when the client says whether the guild recipe directory works, nil when it cannot tell.
function TradeSkill.GuildRecipesEnabled()
	local v, state = first("C_TradeSkillUI.IsGuildTradeSkillsEnabled")
	if state ~= AVAILABLE then return nil end
	return v and true or false
end

-- Asks the server for the recipes of a guild member in one profession (GUILD_RECIPE_KNOWN_BY_MEMBERS answers later).
function TradeSkill.QueryGuildMemberRecipes(guid, skillLineID)
	if type(guid) ~= "string" or type(skillLineID) ~= "number" then return MISSING end
	local _, state = first("C_GuildInfo.QueryGuildMemberRecipes", guid, skillLineID)
	return state
end

-- skillLineID, recipes (a list of spell ids, possibly a bitfield string: kept as the client gives it, read later by
-- Data/Recipes), or nil. The shape of GetGuildMemberRecipes is [verify S3].
function TradeSkill.GuildMemberRecipes()
	local values = all("GetGuildMemberRecipes")
	if not values then return nil end
	return values[1], values[2]
end

-- Number of guild trade skill entries (GetNumGuildTradeSkill), 0 when unknown.
function TradeSkill.NumGuildTradeSkill()
	return num((first("GetNumGuildTradeSkill"))) or 0
end

-- The player's own professions: { { index, name, skillLine, rank, maxRank }, ... } from GetProfessions and
-- GetProfessionInfo; an empty list when the client gives nothing.
function TradeSkill.OwnProfessions()
	local out = {}
	local indexes = all("GetProfessions")
	if not indexes then return out end
	for i = 1, 2 do
		local index = indexes[i]
		if type(index) == "number" then
			local info = all("GetProfessionInfo", index)
			if info and str(info[1]) then
				out[#out + 1] = { index = index, name = info[1], rank = num(info[3]), maxRank = num(info[4]), skillLine = num(info[7]) }
			end
		end
	end
	return out
end

-- The recipe ids of the open profession window [verify S4: whether the window must be open]: GetAllRecipeIDs, else
-- GetFilteredRecipeIDs (neither is in the dump). A list of numbers, or nil.
function TradeSkill.RecipeIDs()
	for _, path in ipairs({ "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetFilteredRecipeIDs" }) do
		local ids = first(path)
		if type(ids) == "table" then
			local out = {}
			for _, id in ipairs(ids) do if num(id) then out[#out + 1] = id end end
			return out
		end
	end
	return nil
end

-- Readable copy of GetRecipeInfo(spellID) or nil (fields: learned, name, ...).
function TradeSkill.RecipeInfo(spellID)
	return readableCopy((first("C_TradeSkillUI.GetRecipeInfo", spellID)))
end

-- Readable copy of GetBaseProfessionInfo() (the profession of the open window) or nil.
function TradeSkill.BaseProfessionInfo()
	return readableCopy((first("C_TradeSkillUI.GetBaseProfessionInfo")))
end

---------------------------------------------------------------------------------------------------------------------
-- Guild bank (SPEC-08): readable only while the vault is open [verify S9]
---------------------------------------------------------------------------------------------------------------------
local Bank = {}
Compat.Bank = Bank
Bank.SLOTS_PER_TAB = 98

-- false when the client says the guild bank is off, true otherwise (also when the API is missing: older clients).
function Bank.Enabled()
	local v, state = first("C_GuildBank.IsGuildBankEnabled")
	if state == AVAILABLE then return v and true or false end
	return true
end

function Bank.NumTabs()
	return num((first("GetNumGuildBankTabs"))) or 0
end

-- { name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals } or nil.
function Bank.TabInfo(tab)
	local v = all("GetGuildBankTabInfo", tab)
	if not v or not str(v[1]) then return nil end
	return { name = v[1], icon = v[2], isViewable = v[3] and true or false, canDeposit = v[4] and true or false,
		numWithdrawals = num(v[5]), remainingWithdrawals = num(v[6]) }
end

-- { itemID, link, count, locked } for one slot, nil for an empty or unreadable slot.
function Bank.Item(tab, slot)
	local v = all("GetGuildBankItemInfo", tab, slot)
	if not v or v[1] == nil then return nil end
	local link = str((first("GetGuildBankItemLink", tab, slot)))
	local itemID = link and tonumber(link:match("item:(%d+)")) or nil   -- GetGuildBankItemInfo gives no item id
	if not itemID then return nil end
	return { itemID = itemID, link = link, count = num(v[2]) or 1, locked = v[3] and true or false }
end

function Bank.Money()
	return num((first("GetGuildBankMoney")))
end

function Bank.CurrentTab()
	return num((first("GetCurrentGuildBankTab")))
end

function Bank.QueryTab(tab)
	local _, state = first("QueryGuildBankTab", tab)
	return state
end

function Bank.QueryLog(tab)
	local _, state = first("QueryGuildBankLog", tab)
	return state
end

-- The item log of a tab: { { kind, name, itemLink, count, tab1, tab2, years, months, days, hours }, ... }; the
-- shape of the time fields is [verify S9]. An empty list when the client gives nothing.
function Bank.ItemLog(tab)
	local out = {}
	local n = num((first("GetNumGuildBankTransactions", tab))) or 0
	for i = 1, min(n, 100) do
		local v = all("GetGuildBankTransaction", tab, i)
		if v and str(v[1]) then
			out[#out + 1] = { kind = v[1], name = str(v[2]), itemLink = str(v[3]), count = num(v[4]), tab1 = num(v[5]),
				tab2 = num(v[6]), years = num(v[7]), months = num(v[8]), days = num(v[9]), hours = num(v[10]) }
		end
	end
	return out
end

-- The money log: { { kind, name, amount, years, months, days, hours }, ... }.
function Bank.MoneyLog()
	local out = {}
	local n = num((first("GetNumGuildBankMoneyTransactions"))) or 0
	for i = 1, min(n, 100) do
		local v = all("GetGuildBankMoneyTransaction", i)
		if v and str(v[1]) then
			out[#out + 1] = { kind = v[1], name = str(v[2]), amount = num(v[3]), years = num(v[4]), months = num(v[5]),
				days = num(v[6]), hours = num(v[7]) }
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Chat restrictions (SPEC-02 §5)
---------------------------------------------------------------------------------------------------------------------
local Chat = {}
Compat.Chat = Chat

-- The addon restriction kinds of Enum.AddOnRestrictionType that matter (names as in the retail enum; one the client
-- does not have is skipped, not an error).
Compat.RESTRICTION_KINDS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }

-- true while the client blocks outgoing chat messages (the messages must wait in the queue).
function Chat.InChatLockdown()
	local v, state = first("C_ChatInfo.InChatMessagingLockdown")
	if state == AVAILABLE then return v and true or false end
	return state == RESTRICTED or state == ERROR   -- cannot tell: stay on the safe side
end

-- true when the addon is read only: outgoing addon chat messages are restricted.
function Chat.OutgoingAddonRestricted()
	local v, state = first("C_ChatInfo.AreOutgoingAddonChatMessagesRestricted")
	if state == AVAILABLE then return v and true or false end
	return state == RESTRICTED or state == ERROR
end

-- active, state for one kind ("Combat", ...). Missing enum or function: false, nil (nothing can be known and nothing
-- is restricted). An error or a secret state counts as active (safe side). Falls back to IsAddOnRestrictionActive.
function Chat.RestrictionActive(kind)
	local types = Resolve("Enum.AddOnRestrictionType")
	local value = type(types) == "table" and types[kind] or nil
	if value == nil then return false, nil end
	local state, callState = first("C_RestrictedActions.GetAddOnRestrictionState", value)
	if callState == AVAILABLE and type(state) == "number" then return state > 0, state end
	if callState == RESTRICTED or callState == ERROR then return true, nil end
	local active, activeState = first("C_RestrictedActions.IsAddOnRestrictionActive", value)
	if activeState == AVAILABLE then return active and true or false, nil end
	return activeState ~= MISSING, nil
end

-- The first active restriction kind, or nil.
function Chat.RestrictionAny()
	for _, kind in ipairs(Compat.RESTRICTION_KINDS) do
		if (Chat.RestrictionActive(kind)) then return kind end
	end
	return nil
end

-- Sending is allowed: no lockdown, no restriction, not read only.
function Chat.CanSend()
	return not Chat.InChatLockdown() and not Chat.OutgoingAddonRestricted() and Chat.RestrictionAny() == nil
end

-- Opens the chat box with "/w Name " typed in (the player writes and sends). false when the name is not a plain
-- character name or the client has no ChatFrame_OpenChat.
function Chat.OpenWhisper(name)
	if type(name) ~= "string" or name == "" or name:find("[%s|%c]") then return false end
	local _, state = first("ChatFrame_OpenChat", "/w " .. name .. " ")
	return state == AVAILABLE
end

-- true while the player is in combat lockdown (UI changes are blocked); false when the function is missing.
function Compat.InCombat()
	return (first("InCombatLockdown")) and true or false
end

---------------------------------------------------------------------------------------------------------------------
-- Time and encoding
---------------------------------------------------------------------------------------------------------------------
function Compat.ServerTime()
	local v = first("GetServerTime")
	if type(v) == "number" then return v end
	return time()
end

-- Monotonic seconds with sub-second precision (GetTime); the wall clock when the client function is missing.
function Compat.Now()
	local v = first("GetTime")
	if type(v) == "number" then return v end
	return time()
end

-- C_Timer wrappers. After(seconds, fn) -> true when scheduled. NewTicker(seconds, fn) -> handle with :Cancel(), or nil
-- when timers are not available (the caller must cope: no timer, no sending).
function Compat.After(seconds, fn)
	local state = Compat.Call("C_Timer.After", seconds, fn)
	return state == AVAILABLE
end

function Compat.NewTicker(seconds, fn)
	local state, handle = Compat.Call("C_Timer.NewTicker", seconds, fn)
	if state == AVAILABLE and type(handle) == "table" then return handle end
	return nil
end

local function enum(name, key)
	local t = Resolve("Enum." .. name)
	return type(t) == "table" and t[key] or nil
end

-- Encoding wrappers: value, or nil plus an error text (never raise).
local function encoding(path, ...)
	local state, detail, _, values = run(Resolve("C_EncodingUtil." .. path), ...)
	if state == AVAILABLE and values[1] ~= nil then return values[1] end
	return nil, state == AVAILABLE and "no result" or (state .. (detail and (": " .. detail) or ""))
end

Compat.CBOR = {
	Encode = function(value) return encoding("SerializeCBOR", value) end,
	Decode = function(text) return encoding("DeserializeCBOR", text) end,
}
Compat.Compress = {
	Deflate = function(text) return encoding("CompressString", text, enum("CompressionMethod", "Deflate"), enum("CompressionLevel", "Default")) end,
	Inflate = function(text) return encoding("DecompressString", text, enum("CompressionMethod", "Deflate")) end,
}
Compat.Base64 = {
	Encode = function(text) return encoding("EncodeBase64", text) end,
	Decode = function(text) return encoding("DecodeBase64", text) end,
}

---------------------------------------------------------------------------------------------------------------------
-- Build, API probe and feature capabilities
---------------------------------------------------------------------------------------------------------------------
function Compat.BuildInfo()
	local values = all("GetBuildInfo") or {}
	return {
		version = tostring(values[1] or "?"), build = tostring(values[2] or "?"), interface = tonumber(values[4]) or 0,
		projectID = WOW_PROJECT_ID, isForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT,
	}
end

-- API definitions: { id, group, path, call = true to call it, args = {...}, restrictedWhenTrue, note, table }.
-- Functions with side effects (queries, friend requests) are only checked for existence.
local CAPS = {
	{ "guild.IsInGuild", "guild", "IsInGuild", call = true },
	{ "guild.GetGuildInfo", "guild", "GetGuildInfo", call = true, args = { "player" } },
	{ "guild.IsGuildLeader", "guild", "IsGuildLeader", call = true },
	{ "guild.IsGuildOfficer", "guild", "C_GuildInfo.IsGuildOfficer", call = true },
	{ "guild.GetNumGuildMembers", "guild", "GetNumGuildMembers", call = true },
	{ "guild.GetGuildRosterInfo", "guild", "GetGuildRosterInfo" },
	{ "guild.GetGuildRosterLastOnline", "guild", "GetGuildRosterLastOnline", note = "[verify] not in the dump" },
	{ "guild.GuildRoster", "guild", "C_GuildInfo.GuildRoster" },
	{ "guild.GuildControlGetRankFlags", "guild", "C_GuildInfo.GuildControlGetRankFlags" },
	{ "club.GetGuildClubId", "club", "C_Club.GetGuildClubId", call = true },
	{ "club.GetClubMembers", "club", "C_Club.GetClubMembers" },
	{ "club.GetMemberInfo", "club", "C_Club.GetMemberInfo", note = "[verify S2] profession and Discord fields" },
	{ "club.GetClubInfo", "club", "C_Club.GetClubInfo" },
	{ "club.SendBattleTagFriendRequest", "club", "C_Club.SendBattleTagFriendRequest", note = "[verify S8]" },
	{ "player.UnitGUID", "player", "UnitGUID", call = true, args = { "player" } },
	{ "player.UnitFactionGroup", "player", "UnitFactionGroup", call = true, args = { "player" } },
	{ "player.UnitClass", "player", "UnitClass", call = true, args = { "player" } },
	{ "player.GetNormalizedRealmName", "player", "GetNormalizedRealmName", call = true },
	{ "player.BNet_GetBattleTagSelf", "player", "BNet_GetBattleTagSelf", note = "[verify S8]" },
	{ "player.BNGetInfo", "player", "BNGetInfo" },
	{ "group.IsInGroup", "group", "IsInGroup", call = true },
	{ "group.IsInRaid", "group", "IsInRaid", call = true },
	{ "group.GetNumGroupMembers", "group", "GetNumGroupMembers", call = true },
	{ "group.UnitIsInMyGuild", "group", "UnitIsInMyGuild" },
	{ "group.GetRaidRosterInfo", "group", "GetRaidRosterInfo", note = "[verify S7] secret values in instances" },
	{ "tradeskill.IsGuildTradeSkillsEnabled", "tradeskill", "C_TradeSkillUI.IsGuildTradeSkillsEnabled", call = true, note = "[verify S3]" },
	{ "tradeskill.QueryGuildMemberRecipes", "tradeskill", "C_GuildInfo.QueryGuildMemberRecipes", note = "[verify S3]" },
	{ "tradeskill.GetGuildMemberRecipes", "tradeskill", "GetGuildMemberRecipes", note = "[verify S3]" },
	{ "tradeskill.GetProfessions", "tradeskill", "GetProfessions" },
	{ "tradeskill.GetProfessionInfo", "tradeskill", "GetProfessionInfo" },
	{ "tradeskill.GetAllRecipeIDs", "tradeskill", "C_TradeSkillUI.GetAllRecipeIDs", note = "[verify S4] not in the dump" },
	{ "tradeskill.GetFilteredRecipeIDs", "tradeskill", "C_TradeSkillUI.GetFilteredRecipeIDs", note = "[verify S4] not in the dump" },
	{ "tradeskill.GetRecipeInfo", "tradeskill", "C_TradeSkillUI.GetRecipeInfo" },
	{ "bank.IsGuildBankEnabled", "bank", "C_GuildBank.IsGuildBankEnabled", call = true },
	{ "bank.GetNumGuildBankTabs", "bank", "GetNumGuildBankTabs" },
	{ "bank.GetGuildBankItemInfo", "bank", "GetGuildBankItemInfo" },
	{ "bank.GetGuildBankTransaction", "bank", "GetGuildBankTransaction", note = "[verify S9] time format" },
	{ "bank.GetGuildBankMoneyTransaction", "bank", "GetGuildBankMoneyTransaction", note = "[verify S9]" },
	{ "chat.InChatMessagingLockdown", "chat", "C_ChatInfo.InChatMessagingLockdown", call = true, restrictedWhenTrue = true },
	{ "chat.AreOutgoingAddonChatMessagesRestricted", "chat", "C_ChatInfo.AreOutgoingAddonChatMessagesRestricted", call = true, restrictedWhenTrue = true },
	{ "chat.SendAddonMessage", "chat", "C_ChatInfo.SendAddonMessage" },
	{ "chat.RegisterAddonMessagePrefix", "chat", "C_ChatInfo.RegisterAddonMessagePrefix" },
	{ "chat.ChatFrame_OpenChat", "chat", "ChatFrame_OpenChat", note = "FrameXML global" },
	{ "time.GetServerTime", "time", "GetServerTime", call = true },
	{ "time.GetTime", "time", "GetTime", call = true },
	{ "time.NewTicker", "time", "C_Timer.NewTicker" },
	{ "time.After", "time", "C_Timer.After" },
	{ "secret.issecretvalue", "secret", "issecretvalue" },
	{ "secret.canaccessvalue", "secret", "canaccessvalue" },
	{ "restriction.GetAddOnRestrictionState", "restriction", "C_RestrictedActions.GetAddOnRestrictionState" },
	{ "restriction.AddOnRestrictionType", "restriction", "Enum.AddOnRestrictionType", table = true },
	{ "encoding.SerializeCBOR", "encoding", "C_EncodingUtil.SerializeCBOR" },
	{ "encoding.DeserializeCBOR", "encoding", "C_EncodingUtil.DeserializeCBOR" },
	{ "encoding.CompressString", "encoding", "C_EncodingUtil.CompressString" },
	{ "encoding.DecompressString", "encoding", "C_EncodingUtil.DecompressString" },
	{ "encoding.EncodeBase64", "encoding", "C_EncodingUtil.EncodeBase64" },
	{ "encoding.DecodeBase64", "encoding", "C_EncodingUtil.DecodeBase64" },
}
Compat.CAPABILITY_DEFS = CAPS

local function probeOne(def)
	local path = def[3]
	local value = Resolve(path)
	if def.table then
		if type(value) == "table" then return AVAILABLE, nil end
		return MISSING, nil
	end
	if type(value) ~= "function" then return MISSING, nil end
	if not def.call then return AVAILABLE, def.note end
	local state, detail, _, values = run(value, unpack(def.args or {}))
	local result = values[1]
	if state == AVAILABLE then
		if def.restrictedWhenTrue and result == true then return RESTRICTED, "active now" end
		if type(result) == "boolean" then detail = "returns " .. tostring(result) elseif def.note then detail = def.note end
	end
	return state, detail
end

-- The feature capabilities of SPEC-01 §5, in report order. Each is { state, detail }: "available", "missing" or
-- "unknown" (the client has the API but no data has confirmed yet that the server fills it). Probe sets what the client
-- can tell at login; modules refine them later with Compat:SetFeature (the Accord tab when it attaches, the roster when
-- members come in, the transport when an OFFICER message comes back, the bank when the vault opens).
Compat.FEATURES = { "guildTab", "clubProfessions", "clubDiscord", "guildRecipesNative", "ownRecipes", "officerAddonChannel",
	"groupGUIDs", "battleTag", "bankLogs" }

local function hasAll(...)
	for i = 1, select("#", ...) do
		if type(Resolve((select(i, ...)))) ~= "function" then return false end
	end
	return true
end

-- What the player's own club entry says about the [verify S2] fields: "available" when filled, else "unknown".
local function ownClubField(check)
	local clubId = guildClubId()
	local ids = clubId and first("C_Club.GetClubMembers", clubId)
	if type(ids) ~= "table" then return UNKNOWN, "no guild club" end
	for i = 1, min(#ids, Guild.MAX_ROSTER) do
		local info = Club.MemberInfo(clubId, ids[i])
		if info and info.isSelf then
			if check(info) then return AVAILABLE, "own entry filled" end
			return UNKNOWN, "own entry empty"
		end
	end
	return UNKNOWN, "own entry not found"
end

local function probeFeatures()
	local f = {}
	local function set(id, state, detail) f[id] = { state = state, detail = detail } end
	local communities = Resolve("CommunitiesFrame")
	if type(communities) == "table" then
		set("guildTab", UNKNOWN, "guild window loaded, tab not attached yet")
	else
		set("guildTab", UNKNOWN, "guild window not loaded yet")
	end
	if hasAll("C_Club.GetGuildClubId", "C_Club.GetClubMembers", "C_Club.GetMemberInfo") then
		set("clubProfessions", ownClubField(function(info) return #Club.Professions(info) > 0 end))
		set("clubDiscord", ownClubField(function(info) return Club.Discord(info) ~= nil end))
	else
		set("clubProfessions", MISSING, "C_Club member API missing")
		set("clubDiscord", MISSING, "C_Club member API missing")
	end
	local enabled = TradeSkill.GuildRecipesEnabled()
	if enabled == true and hasAll("C_GuildInfo.QueryGuildMemberRecipes", "GetGuildMemberRecipes") then
		set("guildRecipesNative", UNKNOWN, "enabled, no answer seen yet")
	elseif enabled == false then
		set("guildRecipesNative", MISSING, "IsGuildTradeSkillsEnabled returns false")
	else
		set("guildRecipesNative", MISSING, "API missing")
	end
	if hasAll("C_TradeSkillUI.GetAllRecipeIDs") or hasAll("C_TradeSkillUI.GetFilteredRecipeIDs") then
		set("ownRecipes", UNKNOWN, "profession window not read yet")
	else
		set("ownRecipes", MISSING, "no recipe list API")
	end
	set("officerAddonChannel", hasAll("C_ChatInfo.SendAddonMessage") and UNKNOWN or MISSING, "no OFFICER message seen yet")
	set("groupGUIDs", hasAll("UnitGUID", "GetNumGroupMembers") and UNKNOWN or MISSING, "not in a group yet")
	set("battleTag", Player.BattleTag() and AVAILABLE or (hasAll("BNet_GetBattleTagSelf") and UNKNOWN or MISSING))
	if hasAll("GetNumGuildBankTransactions", "GetGuildBankTransaction") then
		set("bankLogs", UNKNOWN, "vault not opened yet")
	else
		set("bankLogs", MISSING, "log API missing")
	end
	return f
end

-- Fills Compat.caps ({ [id] = { id, group, state, detail } } and Compat.capOrder) and Compat.features from the client
-- as it is now. Features already refined by a module (Compat:SetFeature) keep their state.
function Compat:Probe()
	self.caps, self.capOrder = {}, {}
	local function set(id, group, state, detail)
		self.caps[id] = { id = id, group = group, state = state, detail = detail }
		self.capOrder[#self.capOrder + 1] = id
	end
	for _, def in ipairs(CAPS) do
		local state, detail = probeOne(def)
		set(def[1], def[2], state, detail)
	end
	-- One entry per restriction kind: restricted while the client says the restriction is active.
	for _, kind in ipairs(self.RESTRICTION_KINDS) do
		local types = Resolve("Enum.AddOnRestrictionType")
		local state, detail = MISSING, nil
		if type(types) == "table" and types[kind] ~= nil then
			local active, value = Chat.RestrictionActive(kind)
			state, detail = active and RESTRICTED or AVAILABLE, value and ("state " .. tostring(value)) or nil
		end
		set("restriction." .. kind, "restriction", state, detail)
	end
	-- A CBOR + Base64 round trip proves the encoding chain works as a whole.
	local encoded = Compat.CBOR.Encode({ a = 1 })
	local text = encoded and Compat.Base64.Encode(encoded)
	local decoded = text and Compat.CBOR.Decode(Compat.Base64.Decode(text) or "")
	set("encoding.roundTrip", "encoding", (type(decoded) == "table" and decoded.a == 1) and AVAILABLE or
		((self.caps["encoding.SerializeCBOR"].state == MISSING or self.caps["encoding.EncodeBase64"].state == MISSING) and MISSING or ERROR))
	local features = probeFeatures()
	self.features = self.features or {}
	for id, value in pairs(features) do
		local old = self.features[id]
		if not (old and old.refined) then self.features[id] = value end
	end
	self.probed = true
	return self.caps
end

function Compat:State(id)
	local c = self.caps and self.caps[id]
	return c and c.state or nil
end

function Compat:IsAvailable(id)
	return self:State(id) == AVAILABLE
end

-- The state of a feature capability ("available", "missing", "unknown") or nil before the first probe.
function Compat:Feature(id)
	local f = self.features and self.features[id]
	return f and f.state or nil
end

-- A module that learned whether a feature works records it here (the probe at the next login keeps it until then).
-- Returns true when the state changed; FEATURE_CHANGED(id, state) goes on the Bus.
function Compat:SetFeature(id, state, detail)
	self.features = self.features or {}
	local old = self.features[id]
	self.features[id] = { state = state, detail = detail, refined = true }
	local changed = not old or old.state ~= state
	if changed and ns.Bus then ns.Bus:Emit("FEATURE_CHANGED", id, state) end
	return changed
end

-- Text lines for /accord debug. No player names, no guild names: the build, the project, each feature and each API.
function Compat:DebugLines()
	if not self.probed then self:Probe() end
	local build = Compat.BuildInfo()
	local lines = {
		("Client: %s (build %s), interface %d, project id %s%s"):format(build.version, build.build, build.interface,
			tostring(build.projectID), build.isForever and " (Forever)" or ""),
		"Features:",
	}
	for _, id in ipairs(Compat.FEATURES) do
		local f = self.features[id] or { state = "?" }
		lines[#lines + 1] = ("  [%s] %s%s"):format(f.state, id, f.detail and (" - " .. f.detail) or "")
	end
	local counts = { [AVAILABLE] = 0, [MISSING] = 0, [RESTRICTED] = 0, [ERROR] = 0 }
	local rows = {}
	for _, id in ipairs(self.capOrder) do
		local c = self.caps[id]
		counts[c.state] = (counts[c.state] or 0) + 1
		rows[#rows + 1] = ("  [%s] %s%s"):format(c.state, id, c.detail and (" - " .. c.detail) or "")
	end
	lines[#lines + 1] = ("APIs: %d available, %d missing, %d restricted, %d error"):format(
		counts[AVAILABLE], counts[MISSING], counts[RESTRICTED], counts[ERROR])
	for _, row in ipairs(rows) do lines[#lines + 1] = row end
	return lines
end

if ns.addon then ns.addon.Compat = Compat end   -- also reachable from tests
if ns.addon and ns.addon.AddDebugSection then
	ns.addon:AddDebugSection("Compat", function() return Compat:DebugLines() end)
end

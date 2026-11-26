-- Roster: the guild members as one list, merged from every source the client has (SPEC-05 §1, ADR 0010). Lua 5.1.
--
-- Sources, in the order they are merged for each member:
--   roster   GetGuildRosterInfo + GetGuildRosterLastOnline (Compat.Guild.Roster): name, rank, level, class, zone, notes,
--            online, last online, GUID.
--   club     C_Club.GetMemberInfo (Compat.Club.GuildMembers): profession1/2, discordInfo, bnetAccountId, memberId
--            [verify S2: the server may not fill them]. Joined to the roster row by GUID, else by character name.
--   shared   what the members' addons published: the `recipes` records give professions of members the server does
--            not fill (ADR 0010: native first, shared fills the gaps) and the `accounts` record says who has the addon.
--   own      the player's own professions, always native (TradeSkill.OwnProfessions).
-- Every value says where it comes from (`source` on each profession, `discordSource`), so the interface can show it.
--
-- Cost: one pass over the roster and one over the club, whatever the guild size (at most 1000 members), then hash joins:
-- no call is made twice. The list is rebuilt lazily: GUILD_ROSTER_UPDATE and the stores only mark it dirty, and while a
-- view is watching (Roster:Watch) a rebuild follows after REBUILD_DELAY seconds, however many events came in.
-- `C_GuildInfo.GuildRoster()` is asked for at most every REQUEST_MIN seconds (ROS-03).
--
-- Entry: { index, name, short, realm, guid, rankIndex, rankName, level, classFile, classID, zone, note, officerNote,
--          online, lastOnlineHours, isSelf, clubMemberId, bnetAccountId, discord, discordSource,
--          professions = { { id, name, rank, maxRank, source = "native"|"shared"|"own", time }, ... },
--          hasAddon, addonVersion }
-- Bus: ROSTER_UPDATED(count) after every rebuild.
local ADDON_NAME, ns = ...
ns = ns or {}
local Roster = {}
ns.Roster, ns.modules = Roster, ns.modules or {}
ns.modules.Roster = Roster

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

Roster.REQUEST_MIN = 15      -- seconds between two C_GuildInfo.GuildRoster() calls (ROS-03)
Roster.REBUILD_DELAY = 1     -- seconds a rebuild waits after the last change while a view is watching
Roster.EVENTS = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }

local state = {
	list = {}, byGUID = {}, byName = {}, dirty = true, watchers = 0, timer = nil, lastRequest = nil,
	builds = 0, native = 0, shared = 0, online = 0, discord = 0, source = "none",
}
Roster.state = state

local function compat() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function lower(s) return type(s) == "string" and s:lower() or nil end

-- "Name" and "Name-Realm" -> name, realm (nil when the name has no realm part).
-- A Forever full name may have a space ("Name Surname-Realm"): the realm is after the last hyphen (Compat.SplitName).
function Roster.SplitName(name)
	return compat().SplitName(name)
end

---------------------------------------------------------------------------------------------------------------------
-- Classes: the roster gives the class file ("MAGE"), the club the class id; each is derived from the other
---------------------------------------------------------------------------------------------------------------------
local classes
local function classTable()
	if classes then return classes end
	local found = { byID = {}, byFile = {}, names = {} }
	local list = compat().Classes()
	for _, c in ipairs(list or {}) do
		if c.file then found.byID[c.id] = c.file found.byFile[c.file] = c.id found.names[c.file] = c.name end
	end
	if list then classes = found end   -- an empty answer (too early at login) is not kept
	return found
end

-- The class file ("MAGE") of a class id, nil when the client does not say.
function Roster.ClassFile(classID)
	return classTable().byID[classID]
end

-- The player-facing class name of a class file ("Mage"), as the client spells it; the file name itself when unknown.
function Roster.ClassName(classFile)
	if type(classFile) ~= "string" then return nil end
	local name = classTable().names[classFile]
	if name then return name end
	return classFile:sub(1, 1) .. classFile:sub(2):lower()
end

---------------------------------------------------------------------------------------------------------------------
-- Shared data (ADR 0010: it fills the gaps the native source leaves)
---------------------------------------------------------------------------------------------------------------------
-- guid -> { { id = skillLine, name, rank, maxRank, source = "shared", time }, ... } from the `recipes` records
-- (M3 publishes them: one per character and profession).
local function sharedProfessions()
	local out, count = {}, 0
	local S = ns.Store
	if not S then return out, 0 end
	for _, rec in pairs(S:Records("recipes")) do
		if type(rec) == "table" and type(rec.char) == "string" and type(rec.skillLine) == "number" and rec.del ~= true
			and (not ns.Recipes or ns.Recipes.IsPrimary(rec.skillLine)) then
			local list = out[rec.char]
			if not list then list = {} out[rec.char] = list end
			list[#list + 1] = { id = rec.skillLine, name = type(rec.name) == "string" and rec.name or nil,
				rank = rec.rank, maxRank = rec.maxRank, source = "shared", time = rec.time, author = rec.author }
			count = count + 1
		end
	end
	for _, list in pairs(out) do
		table.sort(list, function(a, b) return a.id < b.id end)
		while #list > 2 do table.remove(list) end   -- a character has two primary professions
	end
	return out, count
end

---------------------------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------------------------
-- The real levels of `known` (the guild data's professions, whose rank may be missing) from `levels` (the member's own
-- client: shared records, or the player's own skill lines), matched by skill line id, else by name. Only a missing rank is
-- filled, unless `force` (the player's own skill lines are always the latest).
function Roster.MergeRanks(known, levels, force)
	for _, p in ipairs(known) do
		for _, q in ipairs(levels or {}) do
			local same = (p.id ~= nil and p.id == q.id)
				or (type(p.name) == "string" and type(q.name) == "string" and lower(p.name) == lower(q.name))
			if same and type(q.rank) == "number" and q.rank > 0 and (force or p.rank == nil) then
				p.rank, p.maxRank, p.rankSource = q.rank, q.maxRank, q.source
				break
			end
		end
	end
end

-- Rebuilds the list from the client now. Returns the number of members.
function Roster:Build()
	local C = compat()
	local list, byGUID, byName = {}, {}, {}
	local rows = C and C.Guild.InGuild() and C.Guild.Roster() or {}
	local club = (C and #rows > 0 and C.Club.GuildMembers()) or nil
	local clubByGUID, clubByName = {}, {}
	for _, info in ipairs(club or {}) do
		if type(info.guid) == "string" then clubByGUID[info.guid] = info end
		if type(info.name) == "string" then clubByName[lower(info.name)] = info end
	end
	local shared = sharedProfessions()
	local S, classTbl = ns.Store, classTable()
	local nativeCount, sharedCount, onlineCount, discordCount = 0, 0, 0, 0
	local myGUID = C and C.Player.GUID()
	local sourceName = "none"

	for i, row in ipairs(rows) do
		local short, realm = Roster.SplitName(row.name)
		local info = (type(row.guid) == "string" and clubByGUID[row.guid]) or clubByName[lower(row.name)]
		if not info and short then info = clubByName[lower(short)] end
		local classFile = row.classFile or (info and info.classID and classTbl.byID[info.classID]) or classTbl.byID[row.classID]
		local e = {
			index = i, name = row.name, short = short, realm = realm, guid = row.guid or (info and info.guid),
			rankIndex = row.rankIndex, rankName = row.rankName, level = row.level, classFile = classFile,
			classID = row.classID or (info and info.classID) or (classFile and classTbl.byFile[classFile]) or nil,
			zone = row.zone, note = row.note, officerNote = row.officerNote, online = row.online == true,
			lastOnlineHours = row.lastOnlineHours, source = row.source, professions = {},
		}
		sourceName = row.source
		if e.online then onlineCount = onlineCount + 1 end
		e.isSelf = myGUID ~= nil and e.guid == myGUID
		if info then
			e.clubMemberId, e.bnetAccountId = info.memberId, info.bnetAccountId
			for _, p in ipairs(C.Club.Professions(info)) do
				-- WoW Forever's guild data gives rank 1 for everybody (found in game, 2026-11-26): a rank of 1 or less is
				-- not a level, the profession is known and its level comes from the member's own client, if shared
				local rank = (type(p.rank) == "number" and p.rank > 1) and p.rank or nil
				e.professions[#e.professions + 1] = { id = p.id, name = p.name, rank = rank, source = "native" }
			end
			local discord = C.Club.Discord(info)
			if discord then e.discord, e.discordSource = discord, "native" discordCount = discordCount + 1 end
		end
		if #e.professions > 0 then
			nativeCount = nativeCount + 1
			if e.guid and shared[e.guid] then Roster.MergeRanks(e.professions, shared[e.guid]) end
		elseif e.guid and shared[e.guid] then
			e.professions = shared[e.guid]
			sharedCount = sharedCount + 1
		end
		if e.guid and S then
			local acc = S:Get("accounts", e.guid)
			if acc then
				e.hasAddon, e.addonVersion = true, type(acc.addonVersion) == "string" and acc.addonVersion or nil
				e.addonTime, e.addonAuthor = acc.time, acc.author   -- for the provenance label (M7.2)
			end
		end
		list[i] = e
		if e.guid then byGUID[e.guid] = e end
		if e.name then byName[lower(e.name)] = e end
	end

	-- the player's own professions are always known natively
	local me = myGUID and byGUID[myGUID]
	if me then
		local own = {}
		for _, p in ipairs(C.TradeSkill.OwnProfessions()) do
			own[#own + 1] = { id = p.skillLine, name = p.name, rank = p.rank, maxRank = p.maxRank, source = "own" }
		end
		if #me.professions == 0 then me.professions = own else Roster.MergeRanks(me.professions, own, true) end
	end
	if me and me.hasAddon == nil then me.hasAddon = true end

	state.list, state.byGUID, state.byName, state.dirty = list, byGUID, byName, false
	state.builds, state.native, state.shared, state.online, state.discord = state.builds + 1, nativeCount, sharedCount, onlineCount, discordCount
	state.source = club and #club > 0 and (sourceName .. "+club") or sourceName
	state.builtAt = C and C.Now() or nil

	-- what the first full pass taught about the [verify S2] club fields (a field nobody fills stays "unknown")
	if C and club and #club > 0 then
		if nativeCount > 0 then C:SetFeature("clubProfessions", "available", nativeCount .. " member(s) filled") end
		if discordCount > 0 then C:SetFeature("clubDiscord", "available", discordCount .. " member(s) filled") end
	end
	emit("ROSTER_UPDATED", #list)
	return #list
end

---------------------------------------------------------------------------------------------------------------------
-- Access
---------------------------------------------------------------------------------------------------------------------
-- The members (rebuilt first when something changed). Do not modify the list: copies are the caller's business.
function Roster:Members()
	if state.dirty then self:Build() end
	return state.list
end

function Roster:Count()
	return #self:Members()
end

function Roster:ByGUID(guid)
	if state.dirty then self:Build() end
	return guid and state.byGUID[guid] or nil
end

-- By "Name" or "Name-Realm" (the roster's own spelling first, then the name without the realm when it is unambiguous).
function Roster:ByName(name)
	if state.dirty then self:Build() end
	if type(name) ~= "string" then return nil end
	local e = state.byName[lower(name)]
	if e then return e end
	local short = Roster.SplitName(name)
	local found
	for _, m in ipairs(state.list) do
		if m.short and lower(m.short) == lower(short) then
			if found then return nil end   -- ambiguous
			found = m
		end
	end
	return found
end

---------------------------------------------------------------------------------------------------------------------
-- Refresh: asking the server (throttled) and rebuilding after changes
---------------------------------------------------------------------------------------------------------------------
-- Asks the server for a fresh roster, at most every REQUEST_MIN seconds unless `force`. Returns true when it asked.
function Roster:Request(force)
	local C = compat()
	if not C then return false end
	local t = C.Now()
	if not force and state.lastRequest and t - state.lastRequest < Roster.REQUEST_MIN then return false end
	if C.Guild.RequestRoster() ~= C.AVAILABLE then return false end
	state.lastRequest = t
	return true
end

local function scheduleRebuild()
	if state.timer or state.watchers <= 0 then return end
	state.timer = true
	local scheduled = compat().After(Roster.REBUILD_DELAY, function()
		state.timer = nil
		if state.dirty and state.watchers > 0 then Roster:Build() end
	end)
	if not scheduled then state.timer = nil end
end

-- The roster, the club or the shared records changed: the list is stale.
function Roster:MarkDirty()
	state.dirty = true
	scheduleRebuild()
end

-- A view that shows the roster calls Watch when it appears and Unwatch when it goes: while watched, changes rebuild the
-- list by themselves and the first Watch asks the server for fresh data.
function Roster:Watch()
	state.watchers = state.watchers + 1
	self:Request()
	if state.dirty then scheduleRebuild() end
end

function Roster:Unwatch()
	if state.watchers > 0 then state.watchers = state.watchers - 1 end
end

function Roster:Reset()
	state.list, state.byGUID, state.byName, state.dirty = {}, {}, {}, true
end

function Roster:DebugLines()
	local watched = state.watchers > 0 and ", watched" or ""
	if state.builds == 0 then return { "Roster: not built yet" .. watched } end
	return {
		("Roster: %d member(s), %d online, source %s, %d build(s)%s"):format(#state.list, state.online, state.source, state.builds, watched),
		("  professions: %d member(s) native, %d shared; Discord native for %d"):format(state.native, state.shared, state.discord),
	}
end

if ns.addon then
	ns.addon.Roster = Roster
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Roster", function() return Roster:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Roster)
	for _, event in ipairs(Roster.EVENTS) do
		Roster:RegisterEvent(event, function() Roster:MarkDirty() end)
	end
	if ns.Bus then
		ns.Bus:On("GUILD_CHANGED", function() Roster:Reset() end)
		ns.Bus:On("STORE_CHANGED", function(set)
			if set == "recipes" or set == "accounts" then Roster:MarkDirty() end
		end)
	end
end

-- CoPlay: minutes played together, recorded silently (SPEC-07 §3.1, ADR 0008, owner decision D6). Lua 5.1.
-- There is no view yet: the data accumulates from M2 on, so that the social index of M4 starts with weeks of history.
--
--   SOC-01  every 60 seconds, a player in a party or raid with at least one other guild member adds 1 minute to EVERY pair of
--           guild members present in the group (the player included), not only the pairs the player is in: one addon
--           user per group is enough. Guild membership comes from UnitIsInMyGuild and from the guild roster; a member whose
--           GUID is hidden (a secret value, [verify S7]) is identified by name when the name is readable, else counted as
--           unreadable and left out (never guessed).
--   SOC-02  counting goes on inside instances and raids; only the sending waits for the end of the chat lockdown (the
--           Transport holds the messages), the minutes are kept locally meanwhile.
--   SOC-03  the minutes are kept per realm day (YYYYMMDD) and published once an hour, at the change of day and at logout.
--
-- Records (SPEC-03 §4): one per observer, day and chunk: id = "<observer GUID>:<day>:<n>", { day, observer, pairs = {
-- ["<guidA>:<guidB>"] = minutes } } with the two GUIDs sorted. A day with many pairs (a 40-man raid has 780) is split in
-- chunks of at most CHUNK_PAIRS pairs so each record fits the size limit of the set, and every chunk holds at least one pair
-- of the observer (the trust rule NET-13). Observers are combined with the MAXIMUM per pair and day (Store:MergeMax), never the
-- sum, so a group seen by five addon users counts once. Retention: 90 days (Store).
-- Bus: none. /accord debug shows counts only, no names.
local ADDON_NAME, ns = ...
ns = ns or {}
local CoPlay = {}
ns.CoPlay, ns.modules = CoPlay, ns.modules or {}
ns.modules.CoPlay = CoPlay

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, ceil, max = math.floor, math.ceil, math.max

CoPlay.AUTO = true              -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
CoPlay.TICK = 60                -- seconds between two counts (SOC-01)
CoPlay.PUBLISH_EVERY = 3600     -- seconds between two publications (SOC-03)
CoPlay.CHUNK_PAIRS = 100        -- pairs per record
CoPlay.MAX_MINUTES = 1440       -- a pair cannot have more than a day of minutes

local state = {
	days = {},                  -- day -> { pairs = { [key] = minutes }, dirty = bool, loaded = bool }
	ticks = 0, counted = 0, unreadable = 0, publishedRecords = 0, lastPublish = nil, lastTick = nil, ticker = nil,
}
CoPlay.state = state

local function compat() return ns.Compat end
local function now() return compat() and compat().ServerTime() or time() end

-- "<guidA>:<guidB>" with the two GUIDs in order.
function CoPlay.PairKey(a, b)
	if a > b then a, b = b, a end
	return a .. ":" .. b
end

local function myGUID() return compat() and compat().Player.GUID() end

-- The switch "Record time played together" (M7.6, SPEC-11 §5): off, this client neither counts nor publishes. A value that
-- is not a boolean counts as the default (on). Records already published stay until they expire.
function CoPlay.Enabled()
	local C = ns.Config
	return not (C and C.db and C.db.account and C:Get("account.settings.shareCoplay") == false)
end

---------------------------------------------------------------------------------------------------------------------
-- The group
---------------------------------------------------------------------------------------------------------------------
-- The GUIDs of the guild members in the group, the player included: a sorted list, and how many members could not be told.
function CoPlay:GuildMembersInGroup()
	local C = compat()
	local me = myGUID()
	local list, seen, unreadable = {}, {}, 0
	if not (C and me and C.Guild.InGuild() and C.Group.InGroup()) then return list, 0 end
	list[1], seen[me] = me, true
	local R = ns.Roster
	for _, m in ipairs(C.Group.Members()) do
		local guid, inGuild = m.guid, m.inGuild
		if not guid and m.name and R then
			local e = R:ByName(m.name)
			guid = e and e.guid or nil
		end
		if inGuild == nil and guid and R then inGuild = R:ByGUID(guid) ~= nil end
		if inGuild == false then
			-- not a guild member: nothing to count
		elseif not guid then
			unreadable = unreadable + 1   -- a hidden GUID with no readable name: left out, never guessed
		elseif inGuild == true and not seen[guid] then
			seen[guid] = true
			list[#list + 1] = guid
		end
	end
	table.sort(list)
	return list, unreadable
end

---------------------------------------------------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------------------------------------------------
local function dayTable(day)
	local d = state.days[day]
	if not d then d = { pairs = {}, dirty = false, loaded = false } state.days[day] = d end
	return d
end

-- The own chunks already in the store for `day` come back into memory (a /reload or a new login in the same day continues
-- where it was), once per day.
local function loadDay(day)
	local d = dayTable(day)
	if d.loaded then return d end
	d.loaded = true
	local S, me = ns.Store, myGUID()
	if not (S and me) then return d end
	for _, rec in pairs(S:Records("coplay")) do
		if type(rec) == "table" and rec.author == me and rec.day == day and type(rec.pairs) == "table" then
			for key, minutes in pairs(rec.pairs) do
				if type(minutes) == "number" and minutes > (d.pairs[key] or 0) then d.pairs[key] = minutes end
			end
		end
	end
	return d
end

-- One count: adds a minute to every pair of the guild members in the group. Returns the number of pairs counted.
function CoPlay:Tick()
	if not CoPlay.Enabled() then return 0 end
	state.ticks = state.ticks + 1
	state.lastTick = now()
	local C = compat()
	if not (C and ns.GuildKey and ns.GuildKey:Current()) then return 0 end
	local members, unreadable = self:GuildMembersInGroup()
	state.unreadable = state.unreadable + unreadable
	if #members < 2 then return 0 end
	if C and C.Group.Size() > 1 and unreadable == 0 then C:SetFeature("groupGUIDs", "available", "guild members told apart in a group") end
	local day = C.ServerDay()
	local d = loadDay(day)
	local n = 0
	for i = 1, #members - 1 do
		for j = i + 1, #members do
			local key = CoPlay.PairKey(members[i], members[j])
			local minutes = (d.pairs[key] or 0) + 1
			if minutes <= CoPlay.MAX_MINUTES then d.pairs[key] = minutes n = n + 1 end
		end
	end
	if n > 0 then d.dirty = true state.counted = state.counted + 1 end
	-- a new day: what was counted yesterday goes out now
	for other, od in pairs(state.days) do
		if other ~= day and od.dirty then self:Publish(other) end
	end
	if not state.lastPublish then state.lastPublish = now() end
	if now() - state.lastPublish >= CoPlay.PUBLISH_EVERY then self:Publish() end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- Publishing
---------------------------------------------------------------------------------------------------------------------
local function samePairs(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Splits the pairs of a day in chunks of at most CHUNK_PAIRS, each with at least one pair of `me` (NET-13). Deterministic: the
-- same pairs always give the same chunks. Returns a list of { [key] = minutes }.
function CoPlay.Chunks(pairsTable, me)
	local mine, others = {}, {}
	for key in pairs(pairsTable) do
		if key:find(me, 1, true) then mine[#mine + 1] = key else others[#others + 1] = key end
	end
	table.sort(mine); table.sort(others)
	local total = #mine + #others
	if total == 0 then return {} end
	local count = max(1, ceil(total / CoPlay.CHUNK_PAIRS))
	count = math.min(count, max(1, #mine))   -- every chunk needs one of the observer's pairs
	local chunks = {}
	for i = 1, count do chunks[i] = { n = 0 } end
	local function add(i, key) local c = chunks[i] c[key] = pairsTable[key] c.n = c.n + 1 end
	for i, key in ipairs(mine) do add((i - 1) % count + 1, key) end
	local at = 1
	for _, key in ipairs(others) do
		while chunks[at].n >= CoPlay.CHUNK_PAIRS and at < count do at = at + 1 end
		add(at, key)
	end
	for _, c in ipairs(chunks) do c.n = nil end
	return chunks
end

-- Publishes the minutes of `day` (all days with changes when nil). Only the chunks that differ from the record held are
-- written. Returns the number of records written.
function CoPlay:Publish(day)
	if not CoPlay.Enabled() then return 0 end
	local S, me = ns.Store, myGUID()
	if not (S and me and ns.GuildKey and ns.GuildKey:Current()) then return 0 end
	local written = 0
	for dayKey, d in pairs(state.days) do
		if (day == nil or day == dayKey) and d.dirty then
			local chunks = CoPlay.Chunks(d.pairs, me)
			local clean = true
			for i, chunk in ipairs(chunks) do
				local id = ("%s:%d:%d"):format(me, dayKey, i)
				local old = S:Get("coplay", id)
				if not (old and samePairs(old.pairs, chunk)) then
					local rec = S:Put("coplay", id, { day = dayKey, observer = me, pairs = chunk })
					if rec then written = written + 1 else clean = false end
				end
			end
			if clean then d.dirty = false end
		end
	end
	if written > 0 or day == nil then state.lastPublish = now() end
	state.publishedRecords = state.publishedRecords + written
	return written
end

---------------------------------------------------------------------------------------------------------------------
-- Start, stop, events
---------------------------------------------------------------------------------------------------------------------
function CoPlay:Start()
	if not self.AUTO or state.ticker then return false end
	local C = compat()
	state.ticker = C and C.NewTicker(CoPlay.TICK, function() CoPlay:Tick() end)
	return state.ticker ~= nil
end

function CoPlay:Stop()
	if state.ticker then state.ticker:Cancel() state.ticker = nil end
end

-- The merged minutes of every pair on `day`: the maximum over the observers (SPEC-02 §6).
function CoPlay:Merged(day)
	return ns.Store and ns.Store:MergeMax(day) or {}
end

-- A change of guild forgets what is in memory (the records of the old guild stay with it).
function CoPlay:Reset()
	state.days, state.lastPublish = {}, nil
end

function CoPlay:DebugLines()
	local S = ns.Store
	local today = ns.Compat and ns.Compat.ServerDay()
	local pairsToday = 0
	local d = today and state.days[today]
	if d then for _ in pairs(d.pairs) do pairsToday = pairsToday + 1 end end
	return {
		("CoPlay: %s; %d count(s), %d with guild members, %d pair(s) today, %d member(s) unreadable"):format(
			state.ticker and "recording" or (self.AUTO and "not started" or "manual"), state.ticks, state.counted, pairsToday, state.unreadable),
		("  records held %d, published %d%s"):format(S and S:Count("coplay") or 0, state.publishedRecords,
			state.lastPublish and "" or " (nothing yet)"),
	}
end

if ns.addon then
	ns.addon.CoPlay = CoPlay
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("CoPlay", function() return CoPlay:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(CoPlay)
	CoPlay:RegisterEvent("PLAYER_LOGOUT", function() CoPlay:Publish() end)
	if ns.Bus then
		ns.Bus:On("GUILD_CHANGED", function(key)
			CoPlay:Reset()   -- the minutes in memory belong to the old guild (logout and the hourly publication cover the normal case)
			if key then CoPlay:Start() end
		end)
	end
	if ns.OnEnable then ns.OnEnable(function() CoPlay:Start() end) end
end

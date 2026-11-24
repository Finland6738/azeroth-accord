-- Inactivity: which ACCOUNTS have not been seen for a while (SPEC-12 §3, M8.3). Lua 5.1.
--
--   Last seen of a character (INA §3.1): the most recent of
--     native  online now, or the roster's "last online" hours (GetGuildRosterLastOnline [verify])
--     shared  the `seen` day an account's record tells for a character outside the guild (M7.3)
--     own     the last login of the player's own characters (AzerothAccordDB.chars)
--   An account (INA-01, INA-02) is the group of Accounts:GroupOf (mutual listing, the characters outside the guild, the
--   characters a public note joins), or a member alone. Its last seen is the most recent of its characters, its days are
--   floor((now - last) / 86400); it is unknown when none of its characters is known. Only accounts with a character in the
--   guild are listed. Nothing is saved: everything is computed again after the roster, the accounts or the absences change.
--   Tiers (INA-03, INA-04): four increasing numbers of days, 14 / 30 / 60 / 90 unless an officer chose others (the record
--   "tiers" of the set `ocfg`, the same for all officers).
--   Absences (INA-06, Data/Absence.lua): an account away until a day, that day included, is not inactive.
--   Visibility: Officer.CanSee("inactivity"); a member gets nothing, not even their own tier.
--
--   Inactivity:Accounts(t) -> every account: { key, main = { guid, name, classFile }, chars = { guid, ... } (in the guild),
--     rankIndex, rankName, officer, byNote, last, days, tier (0 active .. 4, nil unknown), unknown, lastGUID, lastName,
--     lastSource, online, away, back, absence, name (of the main) }
--   Inactivity:Rows({ minTier, away, unknown, search }, t) -> the rows of the Inactive page, the longest away first
local ADDON_NAME, ns = ...
ns = ns or {}
local Inactivity = {}
ns.Inactivity, ns.modules = Inactivity, ns.modules or {}
ns.modules.Inactivity = Inactivity

local type, pairs, ipairs = type, pairs, ipairs
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local sort = table.sort

Inactivity.DEFAULT = { 14, 30, 60, 90 }
Inactivity.CONFIG_SET, Inactivity.CONFIG_ID = "ocfg", "tiers"
Inactivity.MAX_DAYS = 365
Inactivity.CACHE_SECONDS = 60     -- the days grow with the time: a computed list is not kept longer than this

local DAY, HOUR = 86400, 3600

local state = { list = nil, at = nil, builds = 0 }
Inactivity.state = state

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function store() return ns.Store end

---------------------------------------------------------------------------------------------------------------------
-- Tiers
---------------------------------------------------------------------------------------------------------------------
-- true for four whole numbers of days, each from 1 to 365, each greater than the one before.
function Inactivity.ValidTiers(list)
	if type(list) ~= "table" then return false end
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	if n ~= 4 then return false end
	local last = 0
	for i = 1, 4 do
		local v = list[i]
		if type(v) ~= "number" or v ~= floor(v) or v <= last or v > Inactivity.MAX_DAYS then return false end
		last = v
	end
	return true
end

local ALLOWED = { id = true, author = true, rev = true, time = true, tiers = true }

-- The owner rule of the set `ocfg`.
function Inactivity.ValidConfig(rec)
	if type(rec) ~= "table" or rec.id ~= Inactivity.CONFIG_ID then return false end
	for key in pairs(rec) do if not ALLOWED[key] then return false end end
	return Inactivity.ValidTiers(rec.tiers)
end

-- The tiers in force (a copy), and the record that chose them (nil for the default ones).
function Inactivity:Tiers()
	local rec = ns.GuildKey and ns.GuildKey:Current() and store():Get(Inactivity.CONFIG_SET, Inactivity.CONFIG_ID)
	local from = rec and Inactivity.ValidTiers(rec.tiers) and rec or nil
	local list = from and from.tiers or Inactivity.DEFAULT
	return { list[1], list[2], list[3], list[4] }, from
end

-- An officer's choice for all officers. Returns true, or false plus "officer" | "tiers" | the store's reason.
function Inactivity:SetTiers(list)
	if not (ns.Role and ns.Role:IsOfficer()) then return false, "officer" end
	if not Inactivity.ValidTiers(list) then return false, "tiers" end
	local rec, why = store():Put(Inactivity.CONFIG_SET, Inactivity.CONFIG_ID, { tiers = { list[1], list[2], list[3], list[4] } })
	if not rec then return false, why end
	return true
end

function Inactivity:ResetTiers() return self:SetTiers(Inactivity.DEFAULT) end

-- The tier of `days`: the highest one whose threshold is at most `days`, 0 below the first.
function Inactivity.TierOf(days, tiers)
	if type(days) ~= "number" then return nil end
	local tier = 0
	for i = 1, 4 do if days >= tiers[i] then tier = i end end
	return tier
end

---------------------------------------------------------------------------------------------------------------------
-- Computing
---------------------------------------------------------------------------------------------------------------------
-- character GUID -> last login, for the characters of this account.
local function ownSeen()
	local out = {}
	local db = ns.Config and ns.Config.db and ns.Config.db.account
	for _, list in pairs(db and type(db.chars) == "table" and db.chars or {}) do
		if type(list) == "table" then
			for guid, e in pairs(list) do
				if type(e) == "table" and type(e.seen) == "number" then out[guid] = e.seen end
			end
		end
	end
	return out
end

-- The most recent proof that a character was seen: time, source ("native" | "shared" | "own"), online; nil when unknown.
-- `entry` is its roster entry (nil outside the guild), `member` its entry in the account group (nil without a group).
function Inactivity.LastSeen(guid, entry, member, own, t)
	local last, source, online
	if entry then
		if entry.online then return t, "native", true end
		if type(entry.lastOnlineHours) == "number" then last, source = t - max(0, entry.lastOnlineHours) * HOUR, "native" end
	elseif member and member.altGuild and type(member.altGuild.seen) == "number" then
		last, source = min(member.altGuild.seen, t), "shared"
	end
	local mine = own and own[guid]
	if mine and (not last or mine > last) then last, source = min(mine, t), "own" end
	return last, source, online
end

local function shortName(entry, member)
	if entry then return entry.short or entry.name end
	local name = member and member.name
	if type(name) ~= "string" then return "?" end
	return (compat().SplitName(name))
end

local function build(t)
	local R, A, Abs = ns.Roster, ns.Accounts, ns.Absence
	local out = {}
	if not (R and ns.GuildKey and ns.GuildKey:Current()) then return out end
	local roster = R:Members()
	local own = ownSeen()
	local byChar = Abs and Abs.ByChar() or {}
	local tiers = Inactivity:Tiers()
	local officerRank = {}
	local function isOfficerRank(rank)
		if rank == nil then return false end
		if officerRank[rank] == nil then officerRank[rank] = compat().Guild.RankIsOfficer(rank) == true end
		return officerRank[rank]
	end
	local done = {}
	for _, e in ipairs(roster) do
		local guid = e.guid
		if guid and not done[guid] then
			local group = A and A:GroupOf(guid) or nil
			local members = group and group.members or { { guid = guid } }
			local account = { chars = {}, key = guid, officer = false, byNote = false }
			local guids = {}
			for i, m in ipairs(members) do
				local entry = R:ByGUID(m.guid)
				done[m.guid] = true
				guids[i] = m.guid
				if m.guid < account.key then account.key = m.guid end
				if m.hint then account.byNote = true end
				if entry then
					account.chars[#account.chars + 1] = m.guid
					if entry.rankIndex and (account.rankIndex == nil or entry.rankIndex < account.rankIndex) then
						account.rankIndex, account.rankName = entry.rankIndex, entry.rankName
					end
					if isOfficerRank(entry.rankIndex) then account.officer = true end
				end
				local last, source, online = Inactivity.LastSeen(m.guid, entry, group and m or nil, own, t)
				if online then account.online = true end
				if last and (not account.last or last > account.last or (last == account.last and online)) then
					account.last, account.lastGUID, account.lastSource = last, m.guid, source
					account.lastName = shortName(entry, m)
				end
			end
			local mainMember = group and group.byGUID[group.main] or members[1]
			local mainEntry = R:ByGUID(mainMember.guid)
			local mainShown = mainEntry or (not group and e) or nil
			account.name = shortName(mainShown, mainMember)
			account.main = { guid = mainMember.guid, name = account.name,
				classFile = mainShown and mainShown.classFile or mainMember.classFile }
			if account.last then
				account.days = max(0, floor((t - account.last) / DAY))
				account.tier = Inactivity.TierOf(account.days, tiers)
			else
				account.unknown = true
			end
			local absence = Abs and Abs.Of(guids, t, byChar)
			if absence then account.absence, account.away, account.back = absence, absence.away or nil, absence.back end
			out[#out + 1] = account
		end
	end
	return out
end

function Inactivity:Invalidate() state.list = nil end

-- Every account of the guild (empty for whoever may not see the inactivity). Do not modify it.
function Inactivity:Accounts(t)
	if not ns.Officer.CanSee("inactivity") then return {} end
	t = t or now()
	local R = ns.Roster
	if state.list and R and not R.state.dirty and abs(t - state.at) < Inactivity.CACHE_SECONDS
		and ns.Absence.Today(t) == ns.Absence.Today(state.at) then
		return state.list
	end
	local list = build(t)   -- reading the roster and the groups may emit their own changes: keep the list after them
	state.list, state.at, state.builds = list, t, state.builds + 1
	return list
end

-- The account of a character, or nil.
function Inactivity:AccountOf(guid, t)
	local list = self:Accounts(t)
	for _, a in ipairs(list) do
		for _, c in ipairs(a.chars) do if c == guid then return a end end
	end
	return nil
end

-- The rows of the Inactive page: the accounts in a tier of at least `minTier` (1), the unknown ones unless `unknown` is
-- false, and the ones away only with `away`. `search` filters by the name of the main or of the character last seen.
-- Sorted by days, the longest first; the unknown ones last; then by name.
function Inactivity:Rows(filter, t)
	filter = filter or {}
	local minTier = filter.minTier or 1
	local needle = type(filter.search) == "string" and filter.search ~= "" and filter.search:lower() or nil
	local out = {}
	for _, a in ipairs(self:Accounts(t)) do
		local show
		if a.away then show = filter.away == true
		elseif a.unknown then show = filter.unknown ~= false
		else show = a.tier >= minTier end
		if show and needle then
			show = a.name:lower():find(needle, 1, true) ~= nil
				or (a.lastName ~= nil and a.lastName:lower():find(needle, 1, true) ~= nil)
		end
		if show then out[#out + 1] = a end
	end
	sort(out, function(x, y)
		local dx, dy = x.days or -1, y.days or -1
		if dx ~= dy then return dx > dy end
		if x.name ~= y.name then return x.name < y.name end
		return x.key < y.key
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
function Inactivity:DebugLines()
	if not ns.Officer.CanSee("inactivity") then return { "Inactivity: officers only" } end
	local tiers, from = self:Tiers()
	local counts, unknown, away = { [0] = 0, 0, 0, 0, 0 }, 0, 0
	for _, a in ipairs(self:Accounts()) do
		if a.away then away = away + 1
		elseif a.unknown then unknown = unknown + 1
		else counts[a.tier] = counts[a.tier] + 1 end
	end
	return {
		("Inactivity: tiers %d/%d/%d/%d (%s), %d computation(s)"):format(tiers[1], tiers[2], tiers[3], tiers[4],
			from and "chosen" or "default", state.builds),
		("  accounts: active %d, tiers %d/%d/%d/%d, unknown %d, away %d"):format(counts[0], counts[1], counts[2], counts[3],
			counts[4], unknown, away),
	}
end

if ns.addon then
	ns.addon.Inactivity = Inactivity
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Inactivity", function() return Inactivity:DebugLines() end) end
	if ns.Bus then
		local function stale() Inactivity:Invalidate() end
		for _, event in ipairs({ "ROSTER_UPDATED", "ACCOUNTS_UPDATED", "GUILD_CHANGED", "ROLE_CHANGED", "DEMO_CHANGED",
			"BACKUP_IMPORTED", "OFFICER_PURGED" }) do
			ns.Bus:On(event, stale)
		end
		ns.Bus:On("STORE_CHANGED", function(set)
			if set == "absence" or set == "ocfg" or set == "accounts" then stale() end
		end)
		ns.Bus:On("SETTINGS_CHANGED", function(key) if key == "clear" then stale() end end)
	end
end

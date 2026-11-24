-- Officer: who may see the officer tools, where their data lives and what happens to it (SPEC-12 §1, ADR 0023). Lua 5.1.
--
--   Officer.VISIBLE_TO       the one place of the visibility choices (SPEC-10 Q13, proposed answer): feature -> "officers" |
--                            "members". Features: timeline, inactivity, absences, notes, export.
--   Officer.CanSee(feature)  true when the connected character may see `feature`: the officers and the Guild Master, or
--                            everybody when the table says "members". Nothing is shown from a record a member holds: a
--                            member's client refuses these records (OFF-01) and observes nothing (TL, §2.1).
--   Officer.ChannelProven()  true while this session has seen an addon message arrive on OFFICER (S5, OFF-07): the only time
--                            the officer data may leave this computer.
--   Officer:Data()           the table `officer` of the guild's saved data (GuildKey:Data().officer): what stays on this
--                            computer only (the roster snapshot of the timeline, the queue of M8.4).
--   Officer:CheckDemotion()  OFF-10: when no character of the account in the guild is an officer any more, the officer data of
--                            this computer is deleted (Officer:Purge).
-- Bus: OFFICER_PURGED() after the data was deleted.
local ADDON_NAME, ns = ...
ns = ns or {}
local Officer = {}
ns.Officer, ns.modules = Officer, ns.modules or {}
ns.modules.Officer = Officer

local type, pairs, ipairs, next = type, pairs, ipairs, next

-- Proposed answer to SPEC-10 Q13: the officers see all of it. One line to change if the owner decides otherwise.
Officer.VISIBLE_TO = { timeline = "officers", inactivity = "officers", absences = "officers", notes = "officers", export = "officers" }

-- The data sets of the officer tools, in the order they were added (a step of M8 appends its own).
Officer.SETS = { "timeline", "absence", "onotes", "ocfg" }

-- set -> function(rec, id) -> true for a record that survives the purge (M8.3: the account's own `:self` absence).
Officer.KEEP = {}

local function compat() return ns.Compat end

function Officer.CanSee(feature)
	local who = Officer.VISIBLE_TO[feature]
	if who == "members" then return ns.Role ~= nil and ns.Role:InGuild() end
	if who ~= "officers" then return false end
	return ns.Role ~= nil and ns.Role:IsOfficer() == true
end

function Officer.ChannelProven()
	local C = compat()
	return C ~= nil and C.Feature ~= nil and C:Feature("officerAddonChannel") == "available"
end

-- The officer table of the current guild, created on first use; nil without a guild.
function Officer:Data()
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.officer) ~= "table" then data.officer = {} end
	return data.officer
end

-- The officer table when it exists (never creates it: a member's client holds none).
function Officer:Peek()
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	return data and type(data.officer) == "table" and data.officer or nil
end

-- true when this computer holds anything of the officer tools for the current guild.
function Officer:HasData()
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return false end
	if type(data.officer) == "table" and next(data.officer) ~= nil then return true end
	local sets = type(data.store) == "table" and data.store.sets   -- read directly: Store:Records would create empty sets
	for _, set in ipairs(Officer.SETS) do
		if type(sets) == "table" and type(sets[set]) == "table" and next(sets[set]) ~= nil then return true end
	end
	return false
end

-- Deletes the officer data of the current guild from this computer (OFF-10). Returns the number of records removed.
function Officer:Purge()
	local removed = 0
	local S = ns.Store
	local data0 = ns.GuildKey and ns.GuildKey:Data()
	local sets = data0 and type(data0.store) == "table" and data0.store.sets
	for _, set in ipairs(Officer.SETS) do
		if S and S.SETS[set] and type(sets) == "table" and type(sets[set]) == "table" then
			local records, keep = sets[set], Officer.KEEP[set]
			for id, rec in pairs(records) do
				if not (keep and keep(rec, id)) then
					records[id] = nil
					removed = removed + 1
				end
			end
		end
	end
	local data = ns.GuildKey and ns.GuildKey:Data()
	local had = data ~= nil and type(data.officer) == "table" and next(data.officer) ~= nil
	if data then data.officer = nil end
	if ns.Sync then ns.Sync:Invalidate() end
	if ns.Bus then ns.Bus:Emit("OFFICER_PURGED", removed) end
	return removed, had
end

-- OFF-10: called at the change of role and after a roster read. Deletes the officer data when every character of this
-- account that is in the guild is known NOT to be an officer. A rank the client does not tell (nil) means wait. Returns
-- true when it deleted something.
function Officer:CheckDemotion()
	if ns.Demo and ns.Demo:IsActive() then return false end
	if ns.Role and ns.Role:IsOfficer() then return false end
	if not (ns.Role and ns.Role:InGuild()) or not self:HasData() then return false end
	local C, R, A = compat(), ns.Roster, ns.Accounts
	if not (C and R and A) then return false end
	local seen = 0
	for _, c in ipairs(A:OwnChars()) do
		if c.inGuild then
			local entry = R:ByGUID(c.guid)
			local officer = entry and C.Guild.RankIsOfficer(entry.rankIndex)
			if officer == nil or officer == true then return false end   -- not readable yet, or still an officer
			seen = seen + 1
		end
	end
	if seen == 0 then return false end   -- the roster has not shown any character of this account yet
	local removed, had = self:Purge()
	if removed > 0 or had then
		if ns.addon and ns.L then ns.addon:Print(ns.L["OFFICER_PURGED"]) end
		return true
	end
	return false
end

function Officer:DebugLines()
	local lines = {}
	if not (ns.GuildKey and ns.GuildKey:Current()) then return { "Officer tools: no guild" } end
	local parts = {}
	for _, set in ipairs(Officer.SETS) do
		if ns.Store and ns.Store.SETS[set] then parts[#parts + 1] = set .. " " .. ns.Store:Count(set) end
	end
	lines[1] = ("Officer tools: channel %s, %s"):format(Officer.ChannelProven() and "working" or "not proven yet", table.concat(parts, ", "))
	return lines
end

if ns.addon then
	ns.addon.Officer = Officer
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Officer tools", function() return Officer:DebugLines() end) end
	if ns.Bus then
		-- a character that stopped being an officer: the officer data of the account goes when none of its characters is one
		ns.Bus:On("ROLE_CHANGED", function(role, key, oldRole, oldKey)
			if key ~= nil and key == oldKey and oldRole ~= nil and (oldRole == "officer" or oldRole == "gm") and role == "member" then
				Officer:CheckDemotion()
			end
		end)
	end
end

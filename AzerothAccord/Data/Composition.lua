-- Composition: the target composition of the guild's raid and the counts of the season roster against it (M10.4; SPEC-14
-- §4.5, §7.1). Lua 5.1. The line-up and the bench of one event (SPEC-14 §7.2) come with M10.7.
--
-- Target     the record "target" of the data set `guildcfg` (Net/Store.lua): { size = 10 | 20 | 25 | 40, tank, healer,
--            melee, ranged } (whole numbers, their sum at most `size`). Written only by Raid.WRITERS (officers and the
--            Guild Master, SPEC-10 Q21) and passed on only by officers (NET-12), whatever the source of the season roster
--            is: it is Accord's own setting and only serves to compare. Without it no gap is computed.
-- Rows       the declarations of the chosen source in one shape, { name, guid?, class, role?, ms1?, ms2?, os?, note?,
--            unsure?, first?, alts? } where ms1, ms2 and os are { name (the English tree name), text (as the interface
--            writes it), role? }:
--              Composition.FromAccord(entries)  the rows of Season:Entries(n)
--              Composition.FromPool(pool)       FDCP's pool (Data/FDCP.lua): its role is MS1's, a damage dealer is melee
--                                               or ranged by the spec (Specs.Game), MS2 and OS take the spec's role. Its
--                                               INACTIVE mains are left out and counted apart (second result).
-- Counts     Composition.Count(rows) -> { ms1 = { tank, healer, melee, ranged }, ms2 = the raiders each role would gain
--            from MS2 (MS2 in that role, MS1 in another), counted, unsure = { names }, unknown = { names } (no role
--            known) }. "Not sure yet" and an unknown role count for no role.
-- Gaps       Composition.Gaps(counts, target) -> one { role, target, have, missing, cover } per role: missing = target -
--            MS1 (never below 0), cover = how many of the missing MS2 would fill.
-- Missing    Composition.Missing(rows) -> the names of the accounts of the guild without any declaration among the rows
--            (one per account, the main's name). They are never a gap.
-- Switch: Core/Features.lua "season" (M10). Off: nothing is written (SetTarget: false, "off").
local ADDON_NAME, ns = ...
ns = ns or {}
local Composition = {}
ns.Composition, ns.modules = Composition, ns.modules or {}
ns.modules.Composition = Composition

local type, ipairs, floor, min, max, sort, lower = type, ipairs, math.floor, math.min, math.max, table.sort, string.lower

Composition.SET = "guildcfg"
Composition.ID = "target"
Composition.SIZES = { 10, 20, 25, 40 }
Composition.ROLES = { "tank", "healer", "melee", "ranged" }   -- the same as Data/Specs.lua

---------------------------------------------------------------------------------------------------------------------
-- The target composition
---------------------------------------------------------------------------------------------------------------------
local function whole(v) return type(v) == "number" and v == floor(v) and v >= 0 end

local function validSize(size)
	for _, s in ipairs(Composition.SIZES) do
		if s == size then return true end
	end
	return false
end

-- The size and the four roles of a table are a target composition.
local function validFields(t)
	if type(t) ~= "table" or not validSize(t.size) then return false end
	local sum = 0
	for _, role in ipairs(Composition.ROLES) do
		if not whole(t[role]) then return false end
		sum = sum + t[role]
	end
	return sum <= t.size
end

function Composition.ValidTarget(rec)
	return type(rec) == "table" and rec.id == Composition.ID and validFields(rec)
end

-- The target the officers set, or nil.
function Composition:Target()
	local rec = ns.Store and ns.Store:Get(Composition.SET, Composition.ID)
	if Composition.ValidTarget(rec) then return rec end
	return nil
end

function Composition:CanSet()
	return ns.Features ~= nil and ns.Features.On("season") and ns.Raid ~= nil and ns.Raid.CanWrite()
end

-- An officer sets the target: t = { size, tank, healer, melee, ranged }. Returns true, or false and a reason: "off",
-- "officer", "content", or a reason of Store:Put. Setting the target already set changes nothing.
function Composition:SetTarget(t)
	if not (ns.Features and ns.Features.On("season")) then return false, "off" end
	if not (ns.Raid and ns.Raid.CanWrite()) then return false, "officer" end
	if not validFields(t) then return false, "content" end
	local fields = { size = t.size }
	for _, role in ipairs(Composition.ROLES) do fields[role] = t[role] end
	local held = self:Target()
	if held then
		local same = held.size == fields.size
		for _, role in ipairs(Composition.ROLES) do same = same and held[role] == fields[role] end
		if same then return true end
	end
	local rec, why = ns.Store:Put(Composition.SET, Composition.ID, fields)
	if not rec then return false, why end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The rows of the two sources
---------------------------------------------------------------------------------------------------------------------
local function accordPick(p)
	if type(p) ~= "table" then return nil end
	return { name = ns.Specs.English(p.spec), text = ns.Specs.Name(p.spec), role = p.role }
end

-- `entries`: the rows of Season:Entries(n), { rec, guid, name }.
function Composition.FromAccord(entries)
	local out = {}
	for _, row in ipairs(entries or {}) do
		local r = row.rec
		out[#out + 1] = { name = row.name, guid = row.guid, class = r.class, role = r.ms1 and r.ms1.role or nil,
			ms1 = accordPick(r.ms1), ms2 = accordPick(r.ms2), os = accordPick(r.os), note = r.note,
			unsure = r.unsure == true or nil, first = r.first }
	end
	return out
end

local FDCP_ROLE = { TANK = "tank", HEALER = "healer" }

local function gamePick(id)
	if type(id) ~= "number" then return nil end
	local english, role = ns.Specs.Game(id)
	local text = ns.Compat and ns.Compat.SpecName(id) or english or ("#" .. id)
	return { name = english or text, text = text, role = role }
end

-- `pool`: FDCP.Pool(). Returns the rows of the playing mains and the number of inactive ones left out.
function Composition.FromPool(pool)
	local out, inactive = {}, 0
	for _, e in ipairs(pool or {}) do
		if e.status == "INACTIVE" then
			inactive = inactive + 1
		else
			local ms1 = gamePick(e.ms1)
			local role = FDCP_ROLE[e.role]
			if not role and ms1 and (e.role ~= "DAMAGER" or ms1.role == "melee" or ms1.role == "ranged") then role = ms1.role end
			if ms1 then ms1.role = role end
			out[#out + 1] = { name = e.name, class = e.class, role = role, ms1 = ms1, ms2 = gamePick(e.ms2),
				os = gamePick(e.os), alts = e.alts }
		end
	end
	return out, inactive
end

---------------------------------------------------------------------------------------------------------------------
-- Counts and gaps
---------------------------------------------------------------------------------------------------------------------
function Composition.Count(rows)
	local c = { ms1 = {}, ms2 = {}, counted = 0, unsure = {}, unknown = {} }
	for _, role in ipairs(Composition.ROLES) do c.ms1[role], c.ms2[role] = 0, 0 end
	for _, row in ipairs(rows or {}) do
		if row.unsure then
			c.unsure[#c.unsure + 1] = row.name or "?"
		else
			if row.role and c.ms1[row.role] then
				c.ms1[row.role] = c.ms1[row.role] + 1
				c.counted = c.counted + 1
			else
				c.unknown[#c.unknown + 1] = row.name or "?"
			end
			local second = row.ms2 and row.ms2.role
			if second and c.ms2[second] and second ~= row.role then c.ms2[second] = c.ms2[second] + 1 end
		end
	end
	return c
end

function Composition.Gaps(counts, target)
	if not (counts and target) then return nil end
	local out = {}
	for _, role in ipairs(Composition.ROLES) do
		local missing = max(0, target[role] - counts.ms1[role])
		out[#out + 1] = { role = role, target = target[role], have = counts.ms1[role], missing = missing,
			cover = min(missing, counts.ms2[role]) }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Who has not declared
---------------------------------------------------------------------------------------------------------------------
-- The account of a roster character: its group, or the character itself when it is in none.
local function accountKey(guid)
	local group = ns.Accounts and ns.Accounts:GroupOf(guid)
	return group or guid, group
end

function Composition.Missing(rows)
	local Roster = ns.Roster
	if not Roster then return {} end
	local declared = {}
	local function mark(guid) if guid then declared[(accountKey(guid))] = true end end
	for _, row in ipairs(rows or {}) do
		if row.guid then
			mark(row.guid)
		else
			local names = { row.name }
			for _, alt in ipairs(row.alts or {}) do names[#names + 1] = alt end
			for _, name in ipairs(names) do
				local member = Roster:ByName(name)
				if member then mark(member.guid) end
			end
		end
	end
	local out, seen = {}, {}
	for _, member in ipairs(Roster:Members()) do
		if member.guid then
			local key, group = accountKey(member.guid)
			if not declared[key] and not seen[key] then
				seen[key] = true
				local main = group and group.main and Roster:ByGUID(group.main)
				out[#out + 1] = (main or member).name
			end
		end
	end
	sort(out, function(a, b) return lower(a) < lower(b) end)
	return out
end

if ns.addon then ns.addon.Composition = Composition end

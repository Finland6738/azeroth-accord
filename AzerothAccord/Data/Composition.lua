-- Composition: the target composition of the guild's raid, the counts of the season roster against it (M10.4; SPEC-14
-- §4.5, §7.1) and the line-up and bench of one event (M10.7; SPEC-14 §7.2, §7.3). Lua 5.1.
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
-- Line-up    the record C:<event key> of the data set `raidev`: { at = the event's start, raid = { GUID }, bench = { GUID }
--            (at most LINEUP_MAX each, no character twice), as? = { [GUID] = role } (placed to play the MS2 of that role) }.
--            The key is a calendar event's "c<eventID>" or an addon event's "f<GUID>:<n>". Written only by Raid.WRITERS,
--            passed on only by officers (NET-12), gone Calendar.KEEP after the event. With FDCP as the source of the raid the
--            line-up is FDCP's: Accord writes none (false, "source"), refuses one written while FDCP was the source and shows
--            none of those held (they stay, and show again with Accord as the source).
--              Composition:Candidates(event)     who signed up: the game's yes and maybe (or the addon event's) and the
--                                                matched sign-ups of a Raid-Helper import; the game's "no" wins. One per account.
--              Composition:Model(event)          the line-up, who is not placed, the roles against the target, the MS2 offers
--              Composition:Place(event, guid, where, asMS2)   where = "raid" | "bench" | nil (taken out)
--              Composition:Plan(event), :Push(event)   confirmed (raid) and standby (bench) into the game calendar through
--                                                Data/RaidHelper.lua's write (SPEC-10 Q25)
--            Nothing here says who was at a raid (RAID-05): a line-up is a plan.
-- Switch: Core/Features.lua "season" (M10). Off: nothing is written (SetTarget, Place: false, "off").
local ADDON_NAME, ns = ...
ns = ns or {}
local Composition = {}
ns.Composition, ns.modules = Composition, ns.modules or {}
ns.modules.Composition = Composition

local type, pairs, ipairs, next, floor, min, max = type, pairs, ipairs, next, math.floor, math.min, math.max
local sort, lower = table.sort, string.lower

Composition.SET = "guildcfg"
Composition.ID = "target"
Composition.SIZES = { 10, 20, 25, 40 }
Composition.ROLES = { "tank", "healer", "melee", "ranged" }   -- the same as Data/Specs.lua
Composition.LINEUP_MAX = 40          -- places in the raid, and on the bench
Composition.LINEUP_BYTES = 6144      -- estimated size of a C: record
Composition.PLACES = { "raid", "bench" }
Composition.CALENDAR_STATUS = { raid = "Confirmed", bench = "Standby" }

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

---------------------------------------------------------------------------------------------------------------------
-- The line-up of an event (SPEC-14 §7.2): the record C:<key>
---------------------------------------------------------------------------------------------------------------------
function Composition.LineupId(key) return "C:" .. key end

-- The event key of a C: record, or nil.
function Composition.KeyOf(rec)
	local key = type(rec) == "table" and type(rec.id) == "string" and rec.id:match("^C:(.+)$")
	if key and ns.Calendar.KeyKind(key) then return key end
	return nil
end

local function fdcp()
	return ns.Integrations ~= nil and ns.Integrations:Source("raid") == "fdcp"
end

local function validRole(r)
	for _, role in ipairs(Composition.ROLES) do
		if role == r then return true end
	end
	return false
end

-- A list of 0 to LINEUP_MAX GUIDs without a hole, none of them in `seen`.
local function validList(list, seen)
	if type(list) ~= "table" then return false end
	local n = 0
	for k, guid in pairs(list) do
		n = n + 1
		if type(k) ~= "number" or k < 1 or k > Composition.LINEUP_MAX or k ~= floor(k) then return false end
		if type(guid) ~= "string" or #guid > 40 or not guid:find(ns.Store.GUID_PATTERN) or seen[guid] then return false end
		seen[guid] = true
	end
	return n == #list
end

local function validContent(rec)
	if not Composition.KeyOf(rec) or type(rec.at) ~= "number" then return false end
	if ns.Config and ns.Config.EstimateSize(rec) > Composition.LINEUP_BYTES then return false end
	local seen = {}
	if not (validList(rec.raid, seen) and validList(rec.bench, seen)) then return false end
	if rec.as ~= nil then
		if type(rec.as) ~= "table" then return false end
		for guid, role in pairs(rec.as) do
			if not (seen[guid] and validRole(role)) then return false end
		end
	end
	return true
end

-- The owner rule of a C: record (its author is an officer: Net/Store.lua checks that, NET-12): true, or false and "owner"
-- or "source" (written while FDCP was the source of the raid, SPEC-14 §7.3).
function Composition.ValidLineup(rec)
	if not validContent(rec) then return false end
	if fdcp() then
		local sources = ns.Integrations:SourcesRecord()
		if sources and type(rec.time) == "number" and rec.time >= sources.time then return false, "source" end
	end
	return true
end

-- The line-up of an event as Accord shows it, or nil: none, the switch off, or FDCP as the source.
function Composition:Lineup(key)
	if not (ns.Features and ns.Features.On("season")) or fdcp() or type(key) ~= "string" then return nil end
	local rec = ns.Store:Get("raidev", Composition.LineupId(key))
	if rec and validContent(rec) and not ns.Calendar.Expired(rec, ns.Compat.ServerTime()) then return rec end
	return nil
end

-- Whether this character may change a line-up: true, or false and "off", "source" or "officer".
function Composition:CanEdit()
	if not (ns.Features and ns.Features.On("season")) then return false, "off" end
	if fdcp() then return false, "source" end
	if not (ns.Raid and ns.Raid.CanWrite()) then return false, "officer" end
	return true
end

local function account(guid) return ns.RaidHelper.AccountKey(guid) end

-- "raid" | "bench" and the character placed, for the account of `guid` in a line-up; nil when not placed.
function Composition.PlaceOf(rec, guid)
	if not (rec and guid) then return nil end
	for _, where in ipairs(Composition.PLACES) do
		for _, g in ipairs(rec[where]) do
			if g == guid then return where, g end
		end
	end
	local key = account(guid)
	for _, where in ipairs(Composition.PLACES) do
		for _, g in ipairs(rec[where]) do
			if account(g) == key or ns.Store:SameAccount(guid, g) then return where, g end
		end
	end
	return nil
end

-- account -> declaration of the current season of Accord's roster ("not sure yet" apart).
local function declarations()
	local out = {}
	local cur = ns.Season and ns.Season.Source() == "accord" and ns.Season:Current()
	if cur then
		for _, row in ipairs(ns.Season:Entries(cur.n)) do
			if not row.rec.unsure then out[account(row.guid)] = row.rec end
		end
	end
	return out
end

local function guidOf(guid, name)
	if guid then return guid end
	local member = name and ns.Roster:ByName(name)
	return member and member.guid or nil
end

-- One person of a line-up: the character and its role (the MS2 it was placed as, else the one chosen for the event, else
-- the season's MS1, else Discord's), and the role of its MS2.
local function person(key, guid, rec, season, extra)
	local member = ns.Roster:ByGUID(guid)
	local entry = season[account(guid)]
	local p = { guid = guid, name = member and member.name or (extra and extra.name) or guid,
		classFile = (member and member.classFile) or (extra and extra.classFile),
		answer = extra and extra.answer, discord = extra and extra.discord }
	p.ms2 = entry and entry.ms2 and entry.ms2.role or nil
	local as = rec and rec.as and rec.as[guid]
	if as then
		p.role, p.roleFrom = as, "ms2"
		return p
	end
	p.role = ns.Calendar:RoleOf(key, guid)
	if p.role then p.roleFrom = "held"
	elseif entry and entry.ms1 then p.role, p.roleFrom = entry.ms1.role, "ms1"
	elseif extra and extra.discordRole then p.role, p.roleFrom = extra.discordRole, "discord" end
	return p
end

-- account -> { guid, name?, classFile?, answer?, discord?, discordRole?, declined? } of who answered an event: the game's
-- answers (or the addon event's) first, then the matched sign-ups of Discord. Second result: whether the answers of the
-- calendar event were read.
local function answers(event)
	local out, read, list = {}, true, nil
	if event.addonOnly then
		list = ns.Calendar:LocalAnswers(event.key)
	elseif not event.discordOnly then
		local inv = ns.Calendar.invites[event.key]
		list, read = inv and inv.list, inv ~= nil
	end
	for _, a in ipairs(list or {}) do
		local guid = guidOf(a.guid, a.name)
		if guid and a.answer then
			local key = account(guid)
			local held = out[key]
			-- of two characters of an account, the one that signed up
			if not held or (a.answer ~= "no" and (held.declined or (held.answer == "maybe" and a.answer == "yes"))) then
				out[key] = { guid = guid, name = a.name, classFile = a.classFile,
					answer = a.answer ~= "no" and a.answer or nil, declined = a.answer == "no" or nil }
			end
		end
	end
	local rec = event.importId and ns.RaidHelper:Get(event.importId)
	for _, s in ipairs(rec and rec.s or {}) do
		local key = account(s.g)
		local held = out[key]
		if held then
			held.discord, held.discordRole = s.st, s.role
		elseif ns.RaidHelper.ANSWER[s.st] ~= "no" then
			out[key] = { guid = s.g, discord = s.st, discordRole = s.role }
		end
	end
	return out, read
end

local function byRole(a, b)
	local x, y = 5, 5
	for i, role in ipairs(Composition.ROLES) do
		if a.role == role then x = i end
		if b.role == role then y = i end
	end
	if x ~= y then return x < y end
	return lower(a.name) < lower(b.name)
end

-- The line-up of an event against the target:
-- { rec?, raid = { person }, bench = { person }, free = { person } (signed up, not placed), size = the target's or the
--   addon event's, target?, roles = { raid = role -> n, bench = role -> n }, unknown = placed in the raid without a role,
--   offers = { { person, role } } (MS2 of a role the raid is short of), read = the calendar's answers were read }.
-- A person: { guid, name, classFile, role?, roleFrom?, ms2?, answer?, discord?, place?, gone? = no longer signed up }.
function Composition:Model(event)
	if not (event and event.key and ns.Features.On("season")) then return nil end
	local rec, season = self:Lineup(event.key), declarations()
	local signed, read = answers(event)
	local m = { rec = rec, raid = {}, bench = {}, free = {}, offers = {}, unknown = 0, read = read,
		roles = { raid = {}, bench = {} }, target = self:Target() }
	m.size = (m.target and m.target.size) or event.size
	for _, role in ipairs(Composition.ROLES) do m.roles.raid[role], m.roles.bench[role] = 0, 0 end
	local placed = {}
	for _, where in ipairs(Composition.PLACES) do
		for _, guid in ipairs(rec and rec[where] or {}) do
			local key = account(guid)
			local a = signed[key]
			local p = person(event.key, guid, rec, season, a)
			p.place = where
			-- known only once the calendar's answers were read
			p.gone = (read and (a == nil or a.declined)) or nil
			placed[key] = true
			m[where][#m[where] + 1] = p
			if p.role then m.roles[where][p.role] = m.roles[where][p.role] + 1
			elseif where == "raid" then m.unknown = m.unknown + 1 end
		end
		sort(m[where], byRole)
	end
	for key, a in pairs(signed) do
		if not placed[key] and not a.declined and ns.Roster:ByGUID(a.guid) then
			m.free[#m.free + 1] = person(event.key, a.guid, rec, season, a)
		end
	end
	sort(m.free, byRole)
	if m.target then
		for _, role in ipairs(Composition.ROLES) do
			if m.roles.raid[role] < m.target[role] then
				for _, list in ipairs({ m.bench, m.free, m.raid }) do
					for _, p in ipairs(list) do
						if p.ms2 == role and p.role ~= role and not p.gone then m.offers[#m.offers + 1] = { person = p, role = role } end
					end
				end
			end
		end
	end
	return m
end

local function without(list, key)
	local out = {}
	for _, g in ipairs(list or {}) do
		if account(g) ~= key then out[#out + 1] = g end
	end
	return out
end

-- An officer places a member (from a click): where = "raid" | "bench", or nil to take them out; asMS2: to play their MS2.
-- One place per account. Returns true, or false and a reason: "off", "source", "officer", "calendar" (an event only on
-- Discord), "place", "member" (not signed up), "full", "ms2", or a reason of Store:Put.
function Composition:Place(event, guid, where, asMS2)
	local ok, why = self:CanEdit()
	if not ok then return false, why end
	if not (event and event.key and not event.discordOnly and ns.Calendar.KeyKind(event.key)) then return false, "calendar" end
	if where ~= nil and where ~= "raid" and where ~= "bench" then return false, "place" end
	if type(guid) ~= "string" then return false, "member" end
	local held = self:Lineup(event.key)
	local current = Composition.PlaceOf(held, guid)
	if not current then
		if where == nil then return true end
		-- somebody new must be signed up; somebody placed may be moved or taken out whatever they answered since
		local a = answers(event)[account(guid)]
		if not a or a.declined or a.guid ~= guid then return false, "member" end
	end
	local key = account(guid)
	local role
	if where and asMS2 then
		local entry = declarations()[key]
		role = entry and entry.ms2 and entry.ms2.role
		if not role then return false, "ms2" end
	end
	local fields = { at = event.start, raid = without(held and held.raid, key), bench = without(held and held.bench, key) }
	local as = {}
	for g, r in pairs(held and held.as or {}) do
		if account(g) ~= key then as[g] = r end
	end
	if where then
		local list = fields[where]
		if #list >= Composition.LINEUP_MAX then return false, "full" end
		list[#list + 1] = guid
		as[guid] = role
	end
	if next(as) then fields.as = as end
	local rec, reason = ns.Store:Put("raidev", Composition.LineupId(event.key), fields)
	if not rec then return false, reason end
	return true
end

-- The raid and bench of an event by name (the provider of Integrations), or nil.
function Composition:Names(key)
	local rec = self:Lineup(key)
	if not rec then return nil end
	local out = { raid = {}, bench = {} }
	for _, where in ipairs(Composition.PLACES) do
		for _, guid in ipairs(rec[where]) do
			local member = ns.Roster:ByGUID(guid)
			if member then out[where][#out[where] + 1] = member.name end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Into the game calendar (SPEC-14 §7.2, SPEC-10 Q25): Data/RaidHelper.lua writes
---------------------------------------------------------------------------------------------------------------------
-- The id of the outcome of a write (RaidHelper.result).
function Composition.WriteId(key) return "C:" .. key end

-- The members of a line-up as the write takes them: the raid confirmed, the bench on standby.
function Composition:Queue(key)
	local rec, out = self:Lineup(key), {}
	for _, where in ipairs(Composition.PLACES) do
		for _, guid in ipairs(rec and rec[where] or {}) do
			local member = ns.Roster:ByGUID(guid)
			if member then out[#out + 1] = { guid = guid, name = member.name, status = Composition.CALENDAR_STATUS[where] } end
		end
	end
	return out
end

-- What a confirmation would do: RaidHelper:PlanWrite's result, or nil and a reason (also "source", "calendar", "empty").
function Composition:Plan(event)
	local ok, why = self:CanEdit()
	if not ok then return nil, why end
	if not (event and not event.addonOnly and not event.discordOnly and ns.Calendar.KeyKind(event.key) == "c") then
		return nil, "calendar"
	end
	local queue = self:Queue(event.key)
	if #queue == 0 then return nil, "empty" end
	return ns.RaidHelper:PlanWrite(event, queue)
end

-- The officer's confirmation (from a click). Returns true while it runs, or false and a reason.
function Composition:Push(event)
	local plan, why = self:Plan(event)
	if not plan then return false, why end
	local key = event.key
	return ns.RaidHelper:Write({ id = Composition.WriteId(key), event = event, queue = self:Queue(key),
		changed = function()
			if ns.Bus then
				ns.Bus:Emit("EVENT_CHANGED", key)
				ns.Bus:Emit("CALENDAR_CHANGED")
			end
		end,
		check = function()
			local may, reason = Composition:CanEdit()
			if not may then return reason end
		end })
end

if ns.addon then ns.addon.Composition = Composition end

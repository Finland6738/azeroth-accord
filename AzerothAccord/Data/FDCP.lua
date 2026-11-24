-- FDCP: the provider of Finland Dragon Credit Points, the guild's loot and raid addon of the same author (M10.2 levels,
-- M11.7 reading; ADR 0022; SPEC-10 Q10). Lua 5.1.
--
-- FDCP publishes one read-only, versioned table, `FinlandDragonCreditPointsAPI` (FDCP's ADR 0009 and its wiki page
-- "API for Other Addons"). Accord reads FDCP ONLY through that table: never FDCP's SavedVariables, never its private
-- namespace, and it never writes anything of FDCP.
--
-- Levels (ADR 0022): 1 when the table is there and its API_VERSION is the one Accord knows (FDCP.API_VERSION); 0 when
-- FDCP is loaded but the table is missing or has another version (Accord only detects it and offers to open it); nil when
-- FDCP is not on this client. Data/Integrations.lua asks FDCP.API() for the level of the "fdcp" entry.
--
-- Reading (M11.7). Every getter calls the API protected and returns a NEW plain table of the fields Accord knows, checked
-- for their type; anything else (a field FDCP adds later, a wrong type) is dropped. `nil` means "not on this client"
-- (no API, not ready, the getter has nothing, or it failed), never "empty". FDCP never exposes attendance, and Accord
-- keeps none of what it reads: nothing is saved or sent.
--   FDCP.Ready()            true once FDCP has read the guild roster
--   FDCP.Version()          FDCP's own version text
--   FDCP.Source()           "LEDGER" (an officer's client: the guild's ledger) | "SNAPSHOT" (a member's client: the
--                           credits table an officer sent) | nil
--   FDCP.Season()           { id, name, state = "OPEN" | "CLOSED", updated, asOf }
--   FDCP.Pool()             { { name, faction, class, role, ms1, ms2, os, status, alts, twin } } sorted by name; a member's
--                           client has no ms2, os or twin (FDCP's snapshot does not carry them)
--   FDCP.Member(name)       one pool entry; an alt gives its main with viaAlt = true
--   FDCP.Credits(name)      { name, credits, place, of, faction, viaAlt }: place in the loot queue, nil for an inactive main
--   FDCP.Night()            { date, instanceID, instance, size, difficulty, faction, raid = { names }, bench = { names } };
--                           nil on a member's client (FDCP gives members no nights)
--   FDCP.Rules()            { source = "GUILD" | "DEFAULT", preset, custom, metric, startCredits, awardMode, lateJoin,
--                           costs = { [category] = { [3|4|5] = n | "council" } }, responseMultiplier = { MS, OS, TMOG },
--                           bench = { effect, amount }, penalties = { absence, cheat } }; DEFAULT on a member's client
--                           (the Patto preset's defaults: a member's client has no copy of the guild's rules)
--
-- Callbacks (M11.7). FDCP:Update() registers one Accord function for each FDCP event (READY, SEASON_CHANGED,
-- POOL_CHANGED, CREDITS_CHANGED, NIGHT_CHANGED, RULES_CHANGED) only while the guild chose FDCP as a source and level 1
-- holds, and unregisters it as soon as that stops (the source changed away from FDCP, another API version after a
-- reload). It runs on INTEGRATIONS_CHANGED and SOURCES_CHANGED. Each FDCP event becomes Bus FDCP_CHANGED(event); a
-- READY that happened before Accord registered is passed on once at registration.
--
-- Opening FDCP (level 0 and 1): FDCP.Open() runs FDCP's own /fdcp command, as typing it would; false when there is none.
local ADDON_NAME, ns = ...
ns = ns or {}
local FDCP = {}
ns.FDCP, ns.modules = FDCP, ns.modules or {}
ns.modules.FDCP = FDCP

local type, pcall, ipairs, pairs, tostring, sort = type, pcall, ipairs, pairs, tostring, table.sort

FDCP.ID = "fdcp"
FDCP.FOLDER = "FinlandDragonCreditPoints"
FDCP.GLOBAL = "FinlandDragonCreditPointsAPI"
FDCP.API_VERSION = 1        -- the only version this Accord reads; any other one falls back to level 0
FDCP.COMMAND = "/fdcp"
FDCP.EVENTS = { "READY", "SEASON_CHANGED", "POOL_CHANGED", "CREDITS_CHANGED", "NIGHT_CHANGED", "RULES_CHANGED" }
FDCP.MAX_LIST = 1000        -- a guild has at most 1000 members: longer lists are cut
FDCP.MAX_TEXT = 64

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function lookup(t, k) return t[k] end

-- The value of a field of the table, read protected (the table may have an __index that raises).
local function field(t, k)
	local ok, v = pcall(lookup, t, k)
	if ok then return v end
	return nil
end

-- The API table when Accord may read it, else nil plus the reason: "absent" (no table) or "version" (another version;
-- the version seen, when it is a number or a short text, as the third result).
function FDCP.API()
	local api = field(_G, FDCP.GLOBAL)
	if type(api) ~= "table" then return nil, "absent" end
	local v = field(api, "API_VERSION")
	if v ~= FDCP.API_VERSION then
		if type(v) ~= "number" and not (type(v) == "string" and #v <= 16) then v = nil end
		return nil, "version", v
	end
	return api
end

-- Calls API function `name` (dot style) protected. Returns its first two results, or nil when there is no API of the
-- known version, no such function, or it raised.
local function call(name, ...)
	local api = FDCP.API()
	if not api then return nil end
	local fn = field(api, name)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then return nil end
	return a, b
end
FDCP.Call = call

---------------------------------------------------------------------------------------------------------------------
-- Checked copies
---------------------------------------------------------------------------------------------------------------------
local function text(v, max)
	if type(v) ~= "string" or v == "" or #v > (max or FDCP.MAX_TEXT) then return nil end
	return v
end

local function number(v)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

local function oneOf(v, allowed)
	if type(v) == "string" and allowed[v] then return v end
	return nil
end

local function names(v)
	if type(v) ~= "table" then return nil end
	local out = {}
	for _, x in ipairs(v) do
		local s = text(x)
		if s then out[#out + 1] = s end
		if #out >= FDCP.MAX_LIST then break end
	end
	return out
end

local STATUS = { ACTIVE = true, TRIAL = true, INACTIVE = true }
local STATE = { OPEN = true, CLOSED = true }
local SOURCE = { LEDGER = true, SNAPSHOT = true }
local RULES_SOURCE = { GUILD = true, DEFAULT = true }

local function poolEntry(e)
	if type(e) ~= "table" then return nil end
	local name = text(e.name)
	if not name then return nil end
	return {
		name = name, faction = text(e.faction), class = text(e.class), role = text(e.role),
		ms1 = number(e.ms1), ms2 = number(e.ms2), os = number(e.os), status = oneOf(e.status, STATUS) or "ACTIVE",
		alts = names(e.alts) or {}, twin = text(e.twin), viaAlt = e.viaAlt == true or nil,
	}
end

local function creditEntry(c)
	if type(c) ~= "table" then return nil end
	local name, credits = text(c.name), number(c.credits)
	if not name or not credits then return nil end
	return { name = name, credits = credits, place = number(c.place), of = number(c.of), faction = text(c.faction),
		viaAlt = c.viaAlt == true }
end

---------------------------------------------------------------------------------------------------------------------
-- Getters
---------------------------------------------------------------------------------------------------------------------
function FDCP.Ready() return call("IsReady") == true end

function FDCP.Version()
	local v = call("GetVersion")
	return text(v, 40)
end

function FDCP.Source()
	return oneOf(call("GetSource"), SOURCE)
end

function FDCP.Season()
	local s = call("GetSeason")
	if type(s) ~= "table" then return nil end
	return { id = text(s.id) or number(s.id), name = text(s.name), state = oneOf(s.state, STATE), updated = text(s.updated) or number(s.updated),
		asOf = number(s.asOf) }
end

-- The pool only when FDCP has a source of data: its empty list for "no data yet" is not an empty pool.
function FDCP.Pool()
	if not FDCP.Source() then return nil end
	local list = call("GetPool")
	if type(list) ~= "table" then return nil end
	local out = {}
	for _, e in ipairs(list) do
		local entry = poolEntry(e)
		if entry then out[#out + 1] = entry end
		if #out >= FDCP.MAX_LIST then break end
	end
	sort(out, function(a, b) return a.name < b.name end)
	return out
end

function FDCP.Member(name)
	if not text(name) then return nil end
	return poolEntry(call("GetMember", name))
end

function FDCP.Credits(name)
	if not text(name) then return nil end
	return creditEntry(call("GetCredits", name))
end

function FDCP.CreditList()
	if not FDCP.Source() then return nil end
	local list = call("GetCreditList")
	if type(list) ~= "table" then return nil end
	local out = {}
	for _, c in ipairs(list) do
		local entry = creditEntry(c)
		if entry then out[#out + 1] = entry end
		if #out >= FDCP.MAX_LIST then break end
	end
	return out
end

-- Only who is in the raid and who is on the bench: FDCP keeps the absent list (attendance) for its officers.
function FDCP.Night()
	local n = call("GetNight")
	if type(n) ~= "table" then return nil end
	return {
		date = text(n.date) or number(n.date), instanceID = number(n.instanceID), instance = text(n.instance),
		size = number(n.size), difficulty = text(n.difficulty) or number(n.difficulty), faction = text(n.faction),
		raid = names(n.raid) or {}, bench = names(n.bench) or {},
	}
end

local function cell(v)
	if v == "council" then return v end
	return number(v)
end

function FDCP.Rules()
	local r = call("GetRules")
	if type(r) ~= "table" then return nil end
	local costs = {}
	if type(r.costs) == "table" then
		for category, row in pairs(r.costs) do
			if text(category, 24) and type(row) == "table" then
				local out = {}
				for _, q in ipairs({ 3, 4, 5 }) do out[q] = cell(row[q]) end
				costs[category] = out
			end
		end
	end
	local rm = type(r.responseMultiplier) == "table" and r.responseMultiplier or {}
	local bench = type(r.bench) == "table" and r.bench or nil
	local pen = type(r.penalties) == "table" and r.penalties or nil
	return {
		source = oneOf(r.source, RULES_SOURCE) or "DEFAULT", preset = text(r.preset, 24), custom = r.custom == true,
		metric = text(r.metric, 24), startCredits = number(r.startCredits), awardMode = text(r.awardMode, 24),
		lateJoin = text(r.lateJoin, 24), costs = costs,
		responseMultiplier = { MS = number(rm.MS), OS = number(rm.OS), TMOG = number(rm.TMOG) },
		bench = bench and { effect = text(bench.effect, 24), amount = number(bench.amount) } or nil,
		penalties = pen and { absence = number(pen.absence), cheat = number(pen.cheat) } or nil,
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------------------------------------
FDCP.watching = nil            -- the API table the callbacks are registered with, or nil
FDCP.stats = { events = 0, registered = 0, unregistered = 0 }

-- The one function Accord registers for every FDCP event (FDCP calls it as fn(event), protected).
local function onEvent(event)
	if type(event) ~= "string" then return end
	FDCP.stats.events = FDCP.stats.events + 1
	emit("FDCP_CHANGED", event)
end
FDCP.OnEvent = onEvent

-- True when the callbacks should be registered: level 1 and FDCP chosen as a source by the guild.
function FDCP.Wanted()
	local I = ns.Integrations
	return I ~= nil and I:Level(FDCP.ID) == 1 and I:Uses(FDCP.ID)
end

function FDCP:Unwatch()
	local api = self.watching
	if not api then return false end
	self.watching = nil
	local unregister = field(api, "UnregisterCallback")
	if type(unregister) == "function" then
		for _, event in ipairs(FDCP.EVENTS) do
			if pcall(unregister, event, onEvent) then self.stats.unregistered = self.stats.unregistered + 1 end
		end
	end
	return true
end

function FDCP:Watch()
	local api = FDCP.API()
	if not api then return false end
	if self.watching == api then return true end
	if self.watching then self:Unwatch() end
	local register = field(api, "RegisterCallback")
	if type(register) ~= "function" then return false end
	for _, event in ipairs(FDCP.EVENTS) do
		if pcall(register, event, onEvent) then self.stats.registered = self.stats.registered + 1 end
	end
	self.watching = api
	-- FDCP fires READY only on a change after the registration: a READY that already happened is passed on now
	if FDCP.Ready() then emit("FDCP_CHANGED", "READY") end
	return true
end

-- Registers or unregisters the callbacks as FDCP.Wanted() says. Returns true while they are registered.
function FDCP:Update()
	if FDCP.Wanted() then return self:Watch() end
	self:Unwatch()
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Opening FDCP
---------------------------------------------------------------------------------------------------------------------
function FDCP.Open()
	local handler = ns.Compat and ns.Compat.SlashHandler and ns.Compat.SlashHandler(FDCP.COMMAND)
	if not handler then return false end
	return (pcall(handler, ""))
end

function FDCP.DebugLines()
	return { ("FDCP: callbacks %s, %d registered, %d unregistered, %d events"):format(FDCP.watching and "on" or "off",
		FDCP.stats.registered, FDCP.stats.unregistered, FDCP.stats.events) }
end

if ns.addon then
	ns.addon.FDCP = FDCP
	if ns.Bus then
		ns.Bus:On("INTEGRATIONS_CHANGED", function() FDCP:Update() end)
		ns.Bus:On("SOURCES_CHANGED", function() FDCP:Update() end)
	end
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("FDCP", FDCP.DebugLines) end
end

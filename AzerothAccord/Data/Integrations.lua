-- Integrations: the raid and loot addons Accord knows, whether this client has them, at which level Accord can use
-- them, and which addon the guild's officers chose as the source of each datum (M10.2; ADR 0022; M10 integration rules).
-- Lua 5.1.
--
-- Known addons   Integrations.KNOWN: only loot and raid-roster addons (integration rule 6), each with its folder name, its
--                kind and whether the folder name is confirmed. Only FDCP's is (same author, same repository family); the
--                others come from the survey of M11 and are checked in game before they are trusted (M11.1). An addon
--                whose folder is wrong is simply never found.
-- Detection      Integrations:Detect(id) -> { id, kind, folder, status, version, level, reason, apiVersion }, read through
--                Compat.Addon.State: status "loaded" | "disabled" (installed but switched off) | "installed" (enabled, not
--                loaded: load on demand or a load error) | "missing". `level` (ADR 0022): 1 = Accord reads the addon's public
--                API (only FDCP, and only when its API_VERSION is the known one: Data/FDCP.lua), 0 = detection only (the addon
--                is loaded; `reason` "absent" or "version" for FDCP), nil = not on this client. Level 2 (a two-way
--                exchange) never exists. Nothing of another addon is ever written, loaded or switched on.
--                Refreshed at login (PLAYER_LOGIN: the other addons have loaded by then, whatever the load order) and on
--                ADDON_LOADED of a known folder; Bus: INTEGRATIONS_CHANGED() when a status or level changed.
-- Sources        One source per datum, chosen by an officer and synced to everyone (integration rule 1), never guessed by
--                each client: the record "sources" of the data set `guildcfg` (Net/Store.lua, SPEC-03 §8), written only
--                by officers (NET-12), with
--                  raid = "accord" | "fdcp"   the season roster (MS1, MS2, OS), the lineup and the bench
--                  loot = "none" | "fdcp"     a member's credits and queue place, the loot rules summary
--                Without a record: raid "accord", loot "none" (Integrations.DEFAULTS). Bus: SOURCES_CHANGED() when the record
--                changed, locally or from an officer, or the guild changed.
-- Providers      Integrations:Provider(datum) gives the module that answers for the chosen source: Data/FDCP.lua for
--                "fdcp", Integrations.OWN for Accord's own season roster (it reads nothing yet: it comes with M10.3), nil
--                for loot "none" (Accord has no loot engine, SPEC-10 Q6). Every provider has `id` and Level().
-- Switch         Core/Features.lua "raid": while it is off, nothing is detected at login or on ADDON_LOADED, no officer
--                can choose a source (SetSource: false, "off"), the data set `guildcfg` is neither accepted nor sent
--                (Net/Store.lua) and /accord debug has no Integrations section.
-- Census         Which known addons the OTHER members have loaded comes from the addon census of M9.9 (Data/Census.lua,
--                with the same folder name as in KNOWN): Integrations:Holders(id) reads it, and the Raid view
--                (UI/Raid.lua) shows it per addon. This module keeps no field of its own and sends nothing.
local ADDON_NAME, ns = ...
ns = ns or {}
local Integrations = {}
ns.Integrations, ns.modules = Integrations, ns.modules or {}
ns.modules.Integrations = Integrations

local type, ipairs, pairs, tostring, concat = type, ipairs, pairs, tostring, table.concat

-- kind: "loot", "raid" (the raid roster) or "both". confirmed: the folder name is known for sure (see above). name: the
-- addon's own name, as the Raid view shows it (a proper name: not translated).
Integrations.KNOWN = {
	{ id = "fdcp", folder = "FinlandDragonCreditPoints", kind = "both", confirmed = true, name = "Finland Dragon Credit Points (FDCP)" },
	{ id = "gargul", folder = "Gargul", kind = "loot", name = "Gargul" },
	{ id = "raidcore", folder = "RaidCore", kind = "loot", name = "RaidCore" },
	{ id = "wlc", folder = "WLC", kind = "loot", name = "WLC" },
	{ id = "foreverlootmanager", folder = "ForeverLootManager", kind = "loot", name = "Forever Loot Manager" },
	{ id = "nostalgiaforeverlc", folder = "NostalgiaForeverLC", kind = "loot", name = "NostalgiaForeverLC" },
	{ id = "rollforme", folder = "RollForMe", kind = "loot", name = "RollForMe" },
}
local byId, byFolder = {}, {}
for _, def in ipairs(Integrations.KNOWN) do
	byId[def.id] = def
	byFolder[def.folder] = def
end
Integrations.BY_ID = byId

Integrations.SET = "guildcfg"
Integrations.SOURCES_ID = "sources"
Integrations.DATA = { "raid", "loot" }
Integrations.CHOICES = { raid = { "accord", "fdcp" }, loot = { "none", "fdcp" } }
Integrations.DEFAULTS = { raid = "accord", loot = "none" }

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

---------------------------------------------------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------------------------------------------------
local states = {}            -- id -> the last Detect result
local fingerprint = nil      -- of the last Refresh, to emit INTEGRATIONS_CHANGED only on a change

function Integrations:Detect(id)
	local def = byId[id]
	if not def then return nil end
	local s = ns.Compat and ns.Compat.Addon and ns.Compat.Addon.State(def.folder) or { loaded = false }
	local out = { id = def.id, kind = def.kind, folder = def.folder, confirmed = def.confirmed == true, version = s.version }
	if s.loaded then out.status = "loaded"
	elseif s.exists and s.enabled == false then out.status = "disabled"
	elseif s.exists then out.status = "installed"
	else out.status = "missing" end
	if def.id == "fdcp" and ns.FDCP then
		local api, why, seen = ns.FDCP.API()
		if api then
			-- the published table is the contract: it counts even if the folder had another name
			out.status, out.level, out.apiVersion = "loaded", 1, ns.FDCP.API_VERSION
		else
			out.reason, out.apiVersion = why, seen
			if out.status == "loaded" then out.level = 0 end
		end
	elseif out.status == "loaded" then
		out.level = 0
	end
	return out
end

local function stamp(st)
	return concat({ st.id, st.status, tostring(st.version), tostring(st.level), tostring(st.reason), tostring(st.apiVersion) }, ":")
end

-- Detects every known addon again. Returns true (and emits INTEGRATIONS_CHANGED) when something changed.
function Integrations:Refresh()
	local parts = {}
	for _, def in ipairs(Integrations.KNOWN) do
		local st = self:Detect(def.id)
		states[def.id] = st
		parts[#parts + 1] = stamp(st)
	end
	local fp = concat(parts, "|")
	if fp == fingerprint then return false end
	fingerprint = fp
	emit("INTEGRATIONS_CHANGED")
	return true
end

-- The last detection of a known addon (detected now when it never was).
function Integrations:State(id)
	if not byId[id] then return nil end
	if not states[id] then self:Refresh() end
	return states[id]
end

-- 1, 0 or nil (see the header).
function Integrations:Level(id)
	local st = self:State(id)
	return st and st.level or nil
end

-- Every known addon's state, in table order.
function Integrations:List()
	local out = {}
	for _, def in ipairs(Integrations.KNOWN) do out[#out + 1] = self:State(def.id) end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Sources (the guild setting)
---------------------------------------------------------------------------------------------------------------------
local function valid(datum, value)
	local choices = Integrations.CHOICES[datum]
	if not choices then return false end
	for _, c in ipairs(choices) do if c == value then return true end end
	return false
end
Integrations.ValidChoice = valid

-- The owner rule of the set `guildcfg` (Net/Store.lua): only the record "sources", with a valid choice for every datum.
function Integrations.ValidRecord(rec)
	if type(rec) ~= "table" or rec.id ~= Integrations.SOURCES_ID then return false end
	for _, datum in ipairs(Integrations.DATA) do
		if not valid(datum, rec[datum]) then return false end
	end
	return true
end

-- The record the officers wrote, or nil (then every datum has its default).
function Integrations:SourcesRecord()
	local rec = ns.Store and ns.Store:Get(Integrations.SET, Integrations.SOURCES_ID)
	if Integrations.ValidRecord(rec) then return rec end
	return nil
end

-- The source chosen for `datum` ("raid" | "loot").
function Integrations:Source(datum)
	if not Integrations.CHOICES[datum] then return nil end
	local rec = self:SourcesRecord()
	if rec then return rec[datum] end
	return Integrations.DEFAULTS[datum]
end

-- True when the guild chose the addon `id` as the source of at least one datum.
function Integrations:Uses(id)
	for _, datum in ipairs(Integrations.DATA) do
		if self:Source(datum) == id then return true end
	end
	return false
end

-- Whether this character may change the sources: officers and the Guild Master.
function Integrations:CanChoose()
	return ns.Role ~= nil and ns.Role:IsOfficer()
end

-- An officer chooses the source of `datum`. Returns true, or false and the reason: "off" (the feature's switch is off),
-- "officer" (not an officer), "choice"
-- (an unknown datum or value), or a reason of Store:Put. Choosing the source already set changes nothing.
function Integrations:SetSource(datum, value)
	if not (ns.Features and ns.Features.On("raid")) then return false, "off" end
	if not self:CanChoose() then return false, "officer" end
	if not valid(datum, value) then return false, "choice" end
	local fields = {}
	for _, d in ipairs(Integrations.DATA) do fields[d] = self:Source(d) end
	if fields[datum] == value then return true end
	fields[datum] = value
	local rec, why = ns.Store:Put(Integrations.SET, Integrations.SOURCES_ID, fields)
	if not rec then return false, why end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------------------------------------------------
-- Accord's own provider of the season roster: it reads nothing yet (M10.3 adds the declarations).
Integrations.OWN = { id = "accord", Level = function() return nil end }

-- The module that answers for the source chosen for `datum`, or nil (loot "none").
function Integrations:Provider(datum)
	local source = self:Source(datum)
	if source == "fdcp" then return ns.FDCP end
	if source == "accord" then return Integrations.OWN end
	return nil
end

-- Which members have the known addon `id` loaded, from the addon census (M9.9, SPEC-13 §8.1): the accounts and their
-- versions as far as this character may see them (Census:Who: officers and the Guild Master all of them, anybody else
-- only the own account), then how many accounts use it and out of how many that share. nil for an unknown id and while
-- the census is switched off.
function Integrations:Holders(id)
	local def, Census = byId[id], ns.Census
	if not (def and Census and Census.Enabled()) then return nil end
	local n, total = Census:Count(def.folder)
	return Census:Who(def.folder), n, total
end

function Integrations:DebugLines()
	local lines = {}
	for _, st in ipairs(self:List()) do
		local text = ("%s: %s"):format(st.id, st.status)
		if st.version then text = text .. " " .. st.version end
		if st.level then text = text .. ", level " .. st.level end
		if st.reason then text = text .. " (API " .. st.reason .. (st.apiVersion and " " .. tostring(st.apiVersion) or "") .. ")" end
		if not st.confirmed then text = text .. ", folder not confirmed" end
		lines[#lines + 1] = text
	end
	lines[#lines + 1] = ("Sources: raid %s, loot %s%s"):format(tostring(self:Source("raid")), tostring(self:Source("loot")),
		self:SourcesRecord() and "" or " (defaults)")
	return lines
end

if ns.addon then
	ns.addon.Integrations = Integrations
	LibStub("AceEvent-3.0"):Embed(Integrations)
	Integrations:RegisterEvent("ADDON_LOADED", function(_, name)
		if byFolder[name] and ns.Features.On("raid") then Integrations:Refresh() end
	end)
	if ns.OnEnable then
		ns.OnEnable(function()
			if not ns.Features.On("raid") then return end
			Integrations:Refresh()
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Integrations", function() return Integrations:DebugLines() end) end
		end)
	end
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set)
			if set == Integrations.SET then emit("SOURCES_CHANGED") end
		end)
		ns.Bus:On("GUILD_CHANGED", function() emit("SOURCES_CHANGED") end)
	end
end

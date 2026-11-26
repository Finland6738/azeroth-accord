-- Loot: the guild's loot system and loot addon, who has that addon and where to download it (M11.6, SPEC-15 §8;
-- ADR 0022; SPEC-10 Q30-Q32). Lua 5.1. Loot is described, never computed.
--
-- Record     "loot" of the data set `guildcfg`, written only by officers and the Guild Master (NET-12), behind "raid":
--              system     "none" | "rolls" | "softres" | "council" | "dkp" | "credits" | "other"
--              systemName only with "other", 1-32 bytes
--              addon      "none" | "other" | the id of a loot addon of Integrations.KNOWN
--              addonName, addonFolder, url   only with "other", all three: any loot addon published on CurseForge
--            Without a record: none and none; an older choice of the loot source "fdcp" (record "sources") then counts as
--            the addon FDCP, because the two are one choice.
-- Source     The loot addon and the loot source are chosen together (Loot:Set): FDCP writes sources.loot = "fdcp", any
--            other choice "none". While a loot record is held, it decides (Integrations:Source("loot")): a client holding
--            both with different answers shows the addon and reads FDCP only when the addon is FDCP.
-- Address    Of a known addon: Accord's own constant (Integrations.KNOWN url). Of "other": written by an officer and
--            accepted only as https:// on CurseForge (Loot.URL_HOSTS), by the writer and by every receiver.
-- Who has it From the addon census (Data/Census.lua), only when an addon is chosen: nothing is read or checked without
--            one. Nothing is written or sent by that.
-- Bus        LOOT_CHANGED() when the record, the census or the guild changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Loot = {}
ns.Loot, ns.modules = Loot, ns.modules or {}
ns.modules.Loot = Loot

local type, ipairs, pairs = type, ipairs, pairs

Loot.FEATURE = "raid"
Loot.SET = "guildcfg"
Loot.ID = "loot"                  -- the record of `guildcfg`
Loot.PAGE = "P:loot"              -- the handbook page whose fixed part shows all this (UI/LootPage.lua)
Loot.SYSTEMS = { "none", "rolls", "softres", "council", "dkp", "credits", "other" }
Loot.NAME_MAX = 32                -- bytes of systemName and addonName
Loot.FOLDER_MAX = 64
Loot.URL_MAX = 120
Loot.URL_HOSTS = { "www.curseforge.com", "curseforge.com" }   -- SPEC-10 Q32

local BASE = { id = true, author = true, rev = true, time = true }
local FIELDS = { system = true, systemName = true, addon = true, addonName = true, addonFolder = true, url = true }
local ORDER = { "system", "systemName", "addon", "addonName", "addonFolder", "url" }

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

function Loot.Enabled() return ns.Features ~= nil and ns.Features.On(Loot.FEATURE) end

---------------------------------------------------------------------------------------------------------------------
-- Shape
---------------------------------------------------------------------------------------------------------------------
local function isSystem(v)
	for _, s in ipairs(Loot.SYSTEMS) do if s == v then return true end end
	return false
end

-- A loot addon Accord knows (kind "loot" or "both"), or nil.
function Loot.Known(id)
	local def = ns.Integrations and ns.Integrations.BY_ID[id]
	if def and (def.kind == "loot" or def.kind == "both") then return def end
	return nil
end

-- The values of `addon`, in the order of the menu: none, the known loot addons, other.
function Loot.Addons()
	local out = { "none" }
	for _, def in ipairs(ns.Integrations and ns.Integrations.KNOWN or {}) do
		if Loot.Known(def.id) then out[#out + 1] = def.id end
	end
	out[#out + 1] = "other"
	return out
end

-- No game code and no control character (ASCII classes only: %c follows the C locale).
function Loot.ValidName(v)
	return type(v) == "string" and v ~= "" and #v <= Loot.NAME_MAX and not v:find("[%z\1-\31\127|]")
end

function Loot.ValidFolder(v)
	return type(v) == "string" and #v <= Loot.FOLDER_MAX and v:find("^[A-Za-z0-9_%.%-]+$") ~= nil
end

-- https:// on CurseForge: printable ASCII without spaces and "|", and the whole host one of URL_HOSTS (no user, port or
-- look-alike host).
function Loot.ValidUrl(v)
	if type(v) ~= "string" or #v > Loot.URL_MAX or v:find("[^\33-\126]") or v:find("|", 1, true) then return false end
	local host, rest = v:match("^https://([^/%?#\\]+)(.*)$")
	if not host or (rest ~= "" and not rest:find("^[/%?#]")) then return false end
	host = host:lower()
	for _, h in ipairs(Loot.URL_HOSTS) do if h == host then return true end end
	return false
end

-- What stops these fields from being a loot record: "system", "systemName", "addon", "addonName", "addonFolder", "url",
-- or nil when nothing does.
function Loot.Problem(f)
	if not isSystem(f.system) then return "system" end
	if f.system == "other" then
		if not Loot.ValidName(f.systemName) then return "systemName" end
	elseif f.systemName ~= nil then return "systemName" end
	if not (f.addon == "none" or f.addon == "other" or Loot.Known(f.addon)) then return "addon" end
	if f.addon == "other" then
		if not Loot.ValidName(f.addonName) then return "addonName" end
		if not Loot.ValidFolder(f.addonFolder) then return "addonFolder" end
		if not Loot.ValidUrl(f.url) then return "url" end
	else
		if f.addonName ~= nil then return "addonName" end
		if f.addonFolder ~= nil then return "addonFolder" end
		if f.url ~= nil then return "url" end
	end
	return nil
end

-- The owner rule of the record "loot" (Data/Integrations.lua calls it with "raid" on).
function Loot.ValidRecord(rec)
	if type(rec) ~= "table" or rec.id ~= Loot.ID then return false end
	for k in pairs(rec) do
		if not (BASE[k] or FIELDS[k]) then return false end
	end
	return Loot.Problem(rec) == nil
end

---------------------------------------------------------------------------------------------------------------------
-- The choice
---------------------------------------------------------------------------------------------------------------------
-- The record the officers wrote, or nil (also while the switch is off).
function Loot:Record()
	if not Loot.Enabled() then return nil end
	local rec = ns.Store and ns.Store:Get(Loot.SET, Loot.ID)
	if rec and Loot.ValidRecord(rec) then return rec end
	return nil
end

-- The choice as it stands: a new table with the fields of a record (see the header).
function Loot:Get()
	local out = { system = "none", addon = "none" }
	local rec = self:Record()
	if rec then
		for _, k in ipairs(ORDER) do out[k] = rec[k] end
	elseif Loot.Enabled() and ns.Integrations and ns.Integrations:Source("loot") == "fdcp" then
		out.addon = "fdcp"
	end
	return out
end

-- Officers and the Guild Master.
function Loot:CanChoose()
	return Loot.Enabled() and ns.Integrations ~= nil and ns.Integrations:CanChoose() == true
end

local function trim(s)
	if type(s) ~= "string" then return s end
	return (s:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

-- An officer changes the system, the addon or both: `changes` holds the fields that change; the names that do not belong
-- to the new values are dropped. Writes the record and the loot source together. Returns true, or false and the reason:
-- "off", "officer", a field of Loot.Problem, or a reason of Store:Put.
function Loot:Set(changes)
	if not Loot.Enabled() then return false, "off" end
	if not self:CanChoose() then return false, "officer" end
	local f = self:Get()
	for _, k in ipairs(ORDER) do
		if changes[k] ~= nil then f[k] = trim(changes[k]) end
	end
	if f.system ~= "other" then f.systemName = nil end
	if f.addon ~= "other" then f.addonName, f.addonFolder, f.url = nil, nil, nil end
	local why = Loot.Problem(f)
	if why then return false, why end
	local held = self:Record()
	local same = held ~= nil
	for _, k in ipairs(ORDER) do
		if same and held[k] ~= f[k] then same = false end
	end
	if not same then
		local rec, refused = ns.Store:Put(Loot.SET, Loot.ID, f)
		if not rec then return false, refused end
	end
	return ns.Integrations:SetSource("loot", f.addon == "fdcp" and "fdcp" or "none")
end

---------------------------------------------------------------------------------------------------------------------
-- The chosen addon
---------------------------------------------------------------------------------------------------------------------
-- { id, name, folder, url? } of the chosen addon, or nil without one.
function Loot:Addon()
	local f = self:Get()
	if f.addon == "none" then return nil end
	if f.addon == "other" then return { id = "other", name = f.addonName, folder = f.addonFolder, url = f.url } end
	local def = Loot.Known(f.addon)
	if not def then return nil end
	return { id = def.id, name = def.name or def.folder, folder = def.folder, url = def.url }
end

-- The chosen addon on THIS client: { status, version, level, confirmed } (Integrations:Detect for a known one; only
-- detection for another), or nil without an addon.
function Loot:State()
	local a = self:Addon()
	if not a then return nil end
	if a.id ~= "other" then return ns.Integrations:State(a.id) end
	local s = ns.Compat.Addon.State(a.folder)
	local out = { folder = a.folder, version = s.version, confirmed = true }
	if s.loaded then out.status, out.level = "loaded", 0
	elseif s.exists and s.enabled == false then out.status = "disabled"
	elseif s.exists then out.status = "installed"
	else out.status = "missing" end
	return out
end

-- The census of the chosen addon, or nil without an addon: { off = true } while the census is switched off, else
-- { users, total, sharing, officer, found, folder, versions = { { version?, n } },
--   who = Census:Who (as far as this character may see it), without = Census:Without, unknown (officers) }.
function Loot:Holders()
	local a = self:Addon()
	if not a then return nil end
	local Census = ns.Census
	if not (Census and Census.Enabled()) then return { off = true } end
	-- the census spells a folder as the member's client does; an officer may have typed another case
	local folder, versions = a.folder, {}
	local wanted, found = folder:lower(), false
	for _, row in ipairs(Census:Summary().rows) do
		if row.folder == a.folder or (not found and row.folder:lower() == wanted) then
			folder, versions, found = row.folder, row.versions, true
		end
	end
	local out = { found = found, folder = folder, versions = versions, sharing = Census.Sharing(),
		officer = Census.CanSeeNames() }
	if a.id ~= "other" and folder == a.folder then
		out.who, out.users, out.total = ns.Integrations:Holders(a.id)
	else
		out.users, out.total = Census:Count(folder)
		out.who = Census:Who(folder)
	end
	out.without = Census:Without(folder)
	if out.officer then out.unknown = Census:Unknown() end
	return out
end

if ns.addon then
	ns.addon.Loot = Loot
	if ns.Bus then
		local function changed()
			if Loot.Enabled() then emit("LOOT_CHANGED") end
		end
		ns.Bus:On("STORE_CHANGED", function(set) if set == Loot.SET then changed() end end)
		ns.Bus:On("CENSUS_CHANGED", changed)
		ns.Bus:On("GUILD_CHANGED", changed)
	end
end

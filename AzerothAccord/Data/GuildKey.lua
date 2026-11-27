-- GuildKey: the key of the guild the data belongs to, "<realm>/<guild name>" (SPEC-01 §3, ADR 0011 §4). Lua 5.1.
-- Every per-guild table lives in AzerothAccordDB.guilds[<key>] and is handed out only through GuildKey:Data(), so data
-- of two guilds never mixes: after a change of guild the modules get the other guild's table (or a new empty one),
-- and the old one stays untouched for the day the character comes back.
--
-- The realm is the guild's own realm (the 4th result of GetGuildInfo on connected realms), else the player's realm,
-- without spaces, dashes or apostrophes (the form the client uses in "Name-Realm").
local ADDON_NAME, ns = ...
ns = ns or {}
local GuildKey = {}
ns.GuildKey, ns.modules = GuildKey, ns.modules or {}
ns.modules.GuildKey = GuildKey

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

GuildKey.SEP = "/"

local function normalizeRealm(realm)
	if type(realm) ~= "string" then return nil end
	realm = realm:gsub("[%s%-']", "")
	return realm ~= "" and realm or nil
end
GuildKey.NormalizeRealm = normalizeRealm

-- "<realm>/<guild>" or nil when either part is unknown.
function GuildKey.Make(realm, guildName)
	realm = normalizeRealm(realm)
	if not realm or type(guildName) ~= "string" or guildName == "" then return nil end
	return realm .. GuildKey.SEP .. guildName
end

-- realm, guild name of a key (nil, nil for a malformed one).
function GuildKey.Split(key)
	if type(key) ~= "string" then return nil, nil end
	local realm, name = key:match("^([^/]+)/(.+)$")
	return realm, name
end

-- The key of the player's guild as the client tells it now (nil without a guild or before the guild name loads).
function GuildKey.Compute()
	local C = ns.Compat
	if not C or not C.Guild.InGuild() then return nil end
	local name = C.Guild.GuildName()
	local realm = C.Guild.GuildRealm and C.Guild.GuildRealm() or nil
	return GuildKey.Make(realm or (C.Player.RealmKey and C.Player.RealmKey()) or C.Player.Realm(), name)
end

-- The key the addon works with: the one Role computed (it changes only on the guild events).
function GuildKey:Current()
	if ns.Role then return ns.Role:GuildKey() end
	return GuildKey.Compute()
end

local function now()
	return ns.Compat and ns.Compat.ServerTime() or time()
end

-- The table of guild `key` (the current guild by default), created on first use; nil without a guild or before the
-- SavedVariables are loaded. In read-only mode (a newer schema) it is a table of the working copy: usable, not saved.
function GuildKey:Data(key)
	key = key or self:Current()
	local db = ns.Config and ns.Config.db.account
	if not key or type(db) ~= "table" or type(db.guilds) ~= "table" then return nil end
	local data = db.guilds[key]
	if type(data) ~= "table" then
		data = { firstSeen = now() }
		db.guilds[key] = data
	end
	data.lastSeen = now()
	return data
end

-- The keys of every guild the account has data of (sorted).
function GuildKey:Known()
	local db = ns.Config and ns.Config.db.account
	local keys = {}
	for key in pairs(type(db) == "table" and db.guilds or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

-- The size of the current guild's data per top-level table, biggest first: { { name, bytes }, ... }, total (SPEC-09 §5);
-- nil when there is no data. No names: the key itself is not part of it.
function GuildKey:SizeParts()
	local key = self:Current()
	local db = ns.Config and ns.Config.db.account
	local data = key and type(db) == "table" and db.guilds and db.guilds[key]
	if type(data) ~= "table" then return nil, 0 end
	local parts, total = {}, 0
	for name, value in pairs(data) do
		if type(value) == "table" then
			local size = ns.Config.EstimateSize(value)
			total = total + size
			parts[#parts + 1] = { name = tostring(name), bytes = size }
		end
	end
	table.sort(parts, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.name < b.name
	end)
	return parts, total
end

-- /accord debug: the same, as one line.
function GuildKey:SizeLines()
	local parts, total = self:SizeParts()
	if not parts then return { "Current guild: no data" } end
	local text = {}
	table.sort(parts, function(a, b) return a.name < b.name end)
	for _, p in ipairs(parts) do text[#text + 1] = ("%s %.1f KB"):format(p.name, p.bytes / 1024) end
	return { ("Current guild: about %.1f KB%s"):format(total / 1024, #text > 0 and (" (" .. table.concat(text, ", ") .. ")") or "") }
end

-- Tables of a guild that Clear keeps unless told otherwise: what only this computer knows and the guild cannot send
-- back. The notary's salts (the likes key of the guild: losing the only copy would let an old like be given twice,
-- ADR 0007), this account's own likes memory (SPEC-07 LIKE-04), the bank table (the money history observed at the
-- vault and which request notices were already shown, so a resend is not announced again) and, of the notices
-- (SPEC-13 §3), only what was already announced, and the welcome checklist (SPEC-16 §5: dismissed stays dismissed).
GuildKey.KEEP_ON_CLEAR = { "salts", "likes", "bank", "notify", "onboarding" }

-- A kept table of which only a part stays.
GuildKey.TRIM_ON_CLEAR = { notify = function(t) return { seen = t.seen } end }

-- "Clear guild data" (M6.1): forgets everything the addon holds about the current guild except `keep` (default
-- KEEP_ON_CLEAR) and starts again from the guild: the modules reset (GUILD_CHANGED with the same key twice in a row is
-- the signal they already handle for a guild change) and the guild sends what it knows again. Never touches the
-- account (token, characters, main, settings) or the character's own settings. Returns the bytes freed, or false and
-- the reason ("guild", "read-only").
function GuildKey:Clear(key, keep)
	key = key or self:Current()
	local db = ns.Config and ns.Config.db.account
	if not key or type(db) ~= "table" or type(db.guilds) ~= "table" then return false, "guild" end
	if ns.Config:IsReadOnly("account") then return false, "read-only" end
	local data = db.guilds[key]
	if type(data) ~= "table" then return 0 end
	local before = ns.Config.EstimateSize(data)
	local kept = {}
	for _, name in ipairs(keep or GuildKey.KEEP_ON_CLEAR) do kept[name] = true end
	for name in pairs(data) do
		if not kept[name] and name ~= "firstSeen" then
			data[name] = nil
		elseif GuildKey.TRIM_ON_CLEAR[name] and type(data[name]) == "table" then
			data[name] = GuildKey.TRIM_ON_CLEAR[name](data[name])
		end
	end
	data.lastSeen = now()
	if ns.Bus then ns.Bus:Emit("GUILD_CHANGED", key, key) end
	return before - ns.Config.EstimateSize(data)
end

if ns.addon then ns.addon.GuildKey = GuildKey end

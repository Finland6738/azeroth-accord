-- Config: SavedVariables, schema versions, defaults, validation and migrations (SPEC-01 §4, ADR 0011). Lua 5.1.
-- Adapted from Azeroth Guild Finder (Core/Config.lua), same owner, GPL-3.0 (ADR 0018).
--
--   AzerothAccordDB      (account)   = { schemaVersion, token, chars[realm][guid], mains[realm], guilds[guildKey], settings }
--   AzerothAccordCharDB  (character) = { schemaVersion, ui, outbox, groups }
--
-- Load() runs on ADDON_LOADED (from Init's OnInitialize): defaults are merged without overwriting anything, old data
-- is migrated step by step, bad values are reset and listed in Config.issues. Data from a NEWER schema is never
-- rewritten: the addon works on a copy and refuses writes (Config:IsReadOnly). Nothing here reads a player or guild
-- name; the per-guild tables are handed out by Data/GuildKey.lua, so data of two guilds never mixes (ADR 0011 §4).
--
-- Like Azeroth Guild Finder, the variables are managed directly rather than through AceDB profiles: Accord has no
-- profiles, and the schema / read-only rules need the raw tables (ADR 0011, implementation note).
local ADDON_NAME, ns = ...
ns = ns or {}
local Config = {}
ns.Config, ns.modules = Config, ns.modules or {}
ns.modules.Config = Config

local type, pairs, ipairs, pcall, tostring, next, select = type, pairs, ipairs, pcall, tostring, next, select
local floor, huge = math.floor, math.huge
local byte, char, concat = string.byte, string.char, table.concat

-- 2 (M6.10): the look settings of the account (theme, effects, animations, font); 3 (M7.6): shareCoplay;
-- 4 (M9, SPEC-13 §1.4): notify, the outputs of the notices (M9.3), and quiet, the quiet hours (M9.4); the later steps
-- of M9 add their keys to this step
Config.SCHEMA_VERSION = 4

-- Development build. A checkout of the repository is one; the BigWigs packager comments out the block between the
-- debug markers below in every packaged build, so a release has DEV = false (tools/check_package.py checks it).
Config.DEV = false
--@debug@
Config.DEV = true
--@end-debug@
Config.VARIABLES = { account = "AzerothAccordDB", char = "AzerothAccordCharDB" }

-- Growth limits of SPEC-01 §4, enforced by the modules that own the data (Net/Store.lua retention).
Config.LIMITS = {
	COPLAY_DAYS = 90,
	BANK_LOG_DAYS = 365,
	BANK_REQUEST_CLOSED_DAYS = 60,
}

Config.VIEWS = { "actions", "roster", "professions", "reputation", "bank", "groups", "season", "events", "raid", "addons", "settings" }

-- The personal look of the panel (docs/specs/ui-style.md §2), saved per account: UI/Theme.lua reads them.
Config.THEMES = { "nebula", "aurora", "accord" }
Config.FONT_SOURCES = { "addon", "game" }

Config.defaults = {
	account = {
		schemaVersion = Config.SCHEMA_VERSION,
		token = "",          -- the account token (SPEC-03 §1): 16 random bytes in Base64, created once, never changed
		chars = {},          -- [realm] = { [guid] = { name, classID, level, guild, guildAt, seen, added, answered } }: Data/Accounts.lua
		mains = {},          -- [realm] = guid of the main the player chose (Data/Accounts.lua); default: the highest level
		guilds = {},         -- [guildKey] = { ... }: one table per guild, Data/GuildKey.lua
		settings = { notifyOfficer = true, notifyDecision = true,     -- plus discord (typed, optional): UI/SettingsModel.lua
			notify = {            -- the outputs of the notices per module (SPEC-13 §3.2), Data/Notify.lua
				bank = { chat = true, toast = false, sound = false, off = {} },
				groups = { chat = true, toast = true, sound = false, off = { match = true } },
				digest = { chat = true, toast = false, sound = false, off = {} },
			},
			quiet = { on = false, from = 23, to = 8, instances = true },   -- quiet hours, local time (SPEC-13 §4)
			theme = "nebula", effects = true, animations = true, font = "addon",   -- the look (M6.10), UI/Theme.lua
			groupFilter = { kinds = {}, fits = true, roles = {} },   -- the saved filters of the Groups view (SPEC-13 §6.10)
			shareCoplay = true,     -- record and publish the time played together (M7.6, SPEC-11 §5), Data/CoPlay.lua
			shareAddons = true },   -- publish the list of the loaded addons (M9.9, SPEC-13 §8.3), Data/Census.lua
	},
	char = {
		schemaVersion = Config.SCHEMA_VERSION,
		ui = { lastView = "roster", columns = {}, sort = {}, grouped = false },   -- windowPos, windowSize: nil until the user moves it
		outbox = {},         -- messages waiting at logout, sent again at the next login (Net/Transport.lua, SPEC-02 §5)
		groups = { next = 0, apps = {}, mine = {} },   -- the group finder (SPEC-13 §6.5): ids, applications; Data/Groups.lua
	},
}

-- Rules by path (scope first). type: boolean | number | string | table | timestamp. number: min, max, integer.
-- string: enum, pattern, minLen, maxLen. optional: nil is allowed. A value that breaks a rule is reset to its default
-- (nil for optional values). timestamp: integer epoch >= 0; one in the future is clamped to now, not reset.
local function posRule() return { type = "table", optional = true, validate = function(v) return Config.IsPos(v) end } end
local function sizeRule() return { type = "table", optional = true, validate = function(v) return Config.IsSize(v) end } end
Config.rules = {
	["account.schemaVersion"] = { type = "number", min = 0, integer = true },
	["account.token"] = { type = "string", pattern = "^[A-Za-z0-9+/][A-Za-z0-9+/]*=*$", minLen = 24, maxLen = 24 },
	["account.chars"] = { type = "table" },
	["account.mains"] = { type = "table" },
	["account.guilds"] = { type = "table" },
	["account.settings"] = { type = "table" },
	["account.settings.discord"] = { type = "string", optional = true, maxLen = 32 },
	["account.settings.notifyOfficer"] = { type = "boolean" },
	["account.settings.notifyDecision"] = { type = "boolean" },
	["account.settings.notify"] = { type = "table" },
	["account.settings.theme"] = { type = "string", enum = Config.THEMES },
	["account.settings.effects"] = { type = "boolean" },
	["account.settings.animations"] = { type = "boolean" },
	["account.settings.font"] = { type = "string", enum = Config.FONT_SOURCES },
	["account.settings.shareCoplay"] = { type = "boolean" },
	["account.settings.shareAddons"] = { type = "boolean" },
	["account.settings.groupFilter"] = { type = "table", validate = function(v)
		if v.fits ~= nil and type(v.fits) ~= "boolean" then return false end
		for _, key in ipairs({ "kinds", "roles" }) do
			if v[key] ~= nil then
				if type(v[key]) ~= "table" then return false end
				for k, on in pairs(v[key]) do
					if type(k) ~= "string" or type(on) ~= "boolean" then return false end
				end
			end
		end
		return true
	end },
	["char.schemaVersion"] = { type = "number", min = 0, integer = true },
	["char.ui"] = { type = "table" },
	["char.ui.lastView"] = { type = "string", enum = Config.VIEWS },
	["char.ui.columns"] = { type = "table" },
	["char.ui.sort"] = { type = "table" },
	["char.ui.grouped"] = { type = "boolean" },
	["char.ui.windowPos"] = posRule(),
	["char.ui.windowSize"] = sizeRule(),
	["char.outbox"] = { type = "table" },
	["char.groups"] = { type = "table" },
}

-- The switches of account.settings.notify.<module>: three outputs and `off`, the kinds switched off.
for _, module in ipairs({ "bank", "groups", "digest" }) do
	local path = "account.settings.notify." .. module
	Config.rules[path] = { type = "table" }
	for _, output in ipairs({ "chat", "toast", "sound" }) do Config.rules[path .. "." .. output] = { type = "boolean" } end
	Config.rules[path .. ".off"] = { type = "table", validate = function(v)
		for kind, off in pairs(v) do
			if type(kind) ~= "string" or type(off) ~= "boolean" then return false end
		end
		return true
	end }
end

-- The quiet hours (SPEC-13 §4): whole local hours, and a window that starts when it ends is none.
local function hourOr(v, default)
	if type(v) == "number" and v >= 0 and v <= 23 and v == floor(v) then return v end
	return default
end
Config.rules["account.settings.quiet"] = { type = "table", validate = function(v)
	local d = Config.defaults.account.settings.quiet
	return hourOr(v.from, d.from) ~= hourOr(v.to, d.to)
end }
for _, key in ipairs({ "on", "instances" }) do Config.rules["account.settings.quiet." .. key] = { type = "boolean" } end
for _, key in ipairs({ "from", "to" }) do
	Config.rules["account.settings.quiet." .. key] = { type = "number", min = 0, max = 23, integer = true }
end

-- Migrations: Config.migrations[scope][n] brings data from version n-1 to n. Each step must be idempotent (running it
-- on data that already has the new shape changes nothing). Version 1 is the first schema: data without a version is
-- treated as 0 and only needs the defaults and the rules, so step 1 has nothing to do.
-- Version 2 (M6.10) adds the look settings to the account's settings, each only when it is not there yet (a value that
-- is there but wrong is reset by the rules afterwards). The character data has no change: its step only moves the version.
-- Version 3 (M7.6) adds `shareCoplay` (default true) to the account's settings, when it is not there yet.
-- Version 4 (M9) adds `notify`, `quiet`, `groupFilter` (M9.7) and `shareAddons` (M9.9) to the account's settings, each
-- only when it is not there yet, and `groups` (the group finder's ids and applications, M9.6) to the character's data.
local function deep(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deep(x) end
	return out
end
local function defaultSetting(key) return deep(Config.defaults.account.settings[key]) end

Config.migrations = {
	account = {
		[1] = function(db) end,
		[2] = function(db)
			if type(db.settings) ~= "table" then db.settings = {} end
			for _, key in ipairs({ "theme", "effects", "animations", "font" }) do
				if db.settings[key] == nil then db.settings[key] = Config.defaults.account.settings[key] end
			end
		end,
		[3] = function(db)
			if type(db.settings) ~= "table" then db.settings = {} end
			if db.settings.shareCoplay == nil then db.settings.shareCoplay = Config.defaults.account.settings.shareCoplay end
		end,
		[4] = function(db)
			if type(db.settings) ~= "table" then db.settings = {} end
			if db.settings.notify == nil then db.settings.notify = defaultSetting("notify") end
			if db.settings.quiet == nil then db.settings.quiet = defaultSetting("quiet") end
			if db.settings.groupFilter == nil then db.settings.groupFilter = defaultSetting("groupFilter") end
			if db.settings.shareAddons == nil then db.settings.shareAddons = defaultSetting("shareAddons") end
		end,
	},
	char = { [1] = function(db) end, [2] = function(db) end, [3] = function(db) end,
		[4] = function(db)
			if type(db.groups) ~= "table" then db.groups = { next = 0, apps = {}, mine = {} } end
		end },
}

Config.issues = {}          -- problems found and fixed by the last Load (text only, no names)
Config.readOnly = {}        -- readOnly[scope] = true: newer schema (or failed migration), writes refused
Config.db = {}              -- Config.db.account / Config.db.char: the tables the addon works on
Config.loadedVersion = {}   -- the schema version found in the saved data (0 for none or damaged)

---------------------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------------------
local function copy(value, seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
	return out
end
Config.Copy = copy

local function issue(text)
	Config.issues[#Config.issues + 1] = text
end

local function isFiniteNumber(v)
	return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function now()
	if ns.Compat and ns.Compat.ServerTime then return ns.Compat.ServerTime() end
	return time()
end

-- A saved window position: { point, relPoint, x, y } (relPoint optional).
function Config.IsPos(v)
	return type(v) == "table" and type(v.point) == "string" and isFiniteNumber(v.x) and isFiniteNumber(v.y)
		and (v.relPoint == nil or type(v.relPoint) == "string")
end

-- A saved window size: { w, h } with sane bounds.
function Config.IsSize(v)
	return type(v) == "table" and isFiniteNumber(v.w) and isFiniteNumber(v.h) and v.w >= 200 and v.h >= 150
		and v.w <= 4000 and v.h <= 4000
end

local function split(path)
	local parts = {}
	for part in tostring(path):gmatch("[^.]+") do parts[#parts + 1] = part end
	return parts
end

-- The table that holds `path` (below the scope root) and the key: nil when a parent is missing or not a table.
local function locate(root, parts, from)
	local node = root
	for i = from, #parts - 1 do
		node = node[parts[i]]
		if type(node) ~= "table" then return nil end
	end
	return node, parts[#parts]
end

-- nil when `value` satisfies `rule`, else the reason. Timestamps are checked for shape only (clamping is separate).
local function violation(rule, value)
	if value == nil then return (not rule.optional) and "missing" or nil end
	local t = rule.type
	if t == "timestamp" then
		if not isFiniteNumber(value) or value < 0 or value ~= floor(value) then return "not an epoch" end
		return nil
	end
	if type(value) ~= t then return "expected " .. t .. ", got " .. type(value) end
	if t == "number" then
		if not isFiniteNumber(value) then return "not a finite number" end
		if rule.integer and value ~= floor(value) then return "not an integer" end
		if rule.min and value < rule.min then return "below " .. rule.min end
		if rule.max and value > rule.max then return "above " .. rule.max end
	elseif t == "string" then
		if rule.enum then
			local found = false
			for _, option in ipairs(rule.enum) do if option == value then found = true end end
			if not found then return "not an allowed value" end
		end
		if rule.minLen and #value < rule.minLen then return "too short" end
		if rule.maxLen and #value > rule.maxLen then return "too long" end
		if rule.pattern and not value:find(rule.pattern) then return "bad format" end
	elseif t == "table" and rule.validate and not rule.validate(value) then
		return "bad shape"
	end
	return nil
end
Config.Violation = violation

local function defaultAt(scope, path)
	local node = Config.defaults[scope]
	for _, part in ipairs(split(path)) do
		if type(node) ~= "table" then return nil end
		node = node[part]
	end
	return copy(node)
end

-- Standard Base64 of a byte string, in pure Lua (the token must not depend on C_EncodingUtil being there).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function Config.Base64(bytes)
	local out = {}
	for i = 1, #bytes, 3 do
		local a, b, c = byte(bytes, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1, c2, c3, c4 = floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
	end
	return concat(out)
end

-- The bytes of a standard Base64 text (padding required when the length is not a multiple of 4), or nil when the text
-- is not valid Base64. Pure Lua, the inverse of Config.Base64 (the guild salt of the likes travels and is kept in it).
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:byte(i)] = i - 1 end
function Config.Base64Decode(text)
	if type(text) ~= "string" or #text % 4 ~= 0 then return nil end
	local out = {}
	for i = 1, #text, 4 do
		local a, b, c, d = byte(text, i, i + 3)
		local va, vb = B64_INDEX[a], B64_INDEX[b]
		if va == nil or vb == nil then return nil end
		local last = i + 3 == #text
		local vc = c == 61 and last and -1 or B64_INDEX[c]
		local vd = d == 61 and last and -1 or B64_INDEX[d]
		if vc == nil or vd == nil or (vc == -1 and vd ~= -1) then return nil end
		local n = va * 262144 + vb * 4096 + (vc > 0 and vc or 0) * 64 + (vd > 0 and vd or 0)
		out[#out + 1] = char(floor(n / 65536) % 256)
		if vc ~= -1 then out[#out + 1] = char(floor(n / 256) % 256) end
		if vd ~= -1 then out[#out + 1] = char(n % 256) end
	end
	return concat(out)
end

-- 16 random bytes. The client's Lua has no secure random source: the seed mixes the server time with the sub-second
-- clock and the profiler clock, so two accounts that log in at the same second still differ. The token only has to be
-- unique inside a guild (SPEC-03 §1); nothing secret is derived from it.
function Config.RandomBytes(n)
	local seed = now()
	local fine = (type(debugprofilestop) == "function" and debugprofilestop() or 0) + (type(GetTime) == "function" and GetTime() or 0) * 1000
	seed = (seed % 1000000) * 1000 + floor(fine % 1000000)
	math.randomseed(seed)
	for _ = 1, 10 do math.random() end
	local out = {}
	for i = 1, n do out[i] = char(math.random(0, 255)) end
	return concat(out)
end

local function newToken() return Config.Base64(Config.RandomBytes(16)) end

-- Fills what is missing from `defaults`, recursively; an existing value is never overwritten.
local function mergeDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = copy(v)
		elseif type(v) == "table" and type(db[k]) == "table" then
			mergeDefaults(db[k], v)
		end
	end
end
Config.MergeDefaults = mergeDefaults

---------------------------------------------------------------------------------------------------------------------
-- Sanitize: rules, extra checks, clamping
---------------------------------------------------------------------------------------------------------------------
-- guilds is { [guildKey] = table } and chars is { [realm] = { [guid] = table } }: anything else at those levels goes.
local function sanitizeMaps(db)
	for key, data in pairs(db.guilds or {}) do
		if type(key) ~= "string" or type(data) ~= "table" or not key:find("/", 1, true) then
			db.guilds[key] = nil
			issue("account.guilds: dropped a malformed guild entry")
		end
	end
	for realm, list in pairs(db.chars or {}) do
		if type(realm) ~= "string" or type(list) ~= "table" then
			db.chars[realm] = nil
			issue("account.chars: dropped a malformed realm entry")
		else
			for guid, entry in pairs(list) do
				if type(guid) ~= "string" or type(entry) ~= "table" then
					list[guid] = nil
					issue("account.chars: dropped a malformed character entry")
				end
			end
		end
	end
end

local function sortedRulePaths(scope)
	local paths, prefix = {}, scope .. "."
	for path in pairs(Config.rules) do
		if path:sub(1, #prefix) == prefix then paths[#paths + 1] = path end
	end
	table.sort(paths, function(a, b)   -- parents first, so a reset parent is validated again below
		local da, db = select(2, a:gsub("%.", "")), select(2, b:gsub("%.", ""))
		if da ~= db then return da < db end
		return a < b
	end)
	return paths
end

-- Brings `db` (the working table of `scope`) within the rules. Returns the number of fixes.
function Config.Sanitize(scope, db)
	local before = #Config.issues
	local nowValue = now()
	for _, path in ipairs(sortedRulePaths(scope)) do
		local rule = Config.rules[path]
		local parts = split(path)
		local parent, key = locate(db, parts, 2)
		if parent then
			local value = parent[key]
			local why = violation(rule, value)
			if why then
				if path == "account.token" then
					parent[key] = newToken()
					if value ~= nil and value ~= "" then issue(path .. ": replaced (" .. why .. ")") end
				else
					parent[key] = defaultAt(scope, table.concat(parts, ".", 2))
					issue(path .. ": reset (" .. why .. ")")
				end
			elseif rule.type == "timestamp" and value and value > nowValue then
				parent[key] = nowValue
				issue(path .. ": future time clamped")
			end
		end
	end
	if scope == "account" then sanitizeMaps(db) end
	return #Config.issues - before
end

---------------------------------------------------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------------------------------------------------
local function schemaOf(raw)
	local v = raw.schemaVersion
	if v == nil then return 0 end
	if isFiniteNumber(v) and v >= 0 and v == floor(v) then return v end
	return nil   -- damaged
end

local function isEmpty(t) return next(t) == nil end

-- Runs the steps from..target on `db`. Returns true, or false and the reason (db may be half changed: use a copy).
local function migrate(scope, db, from, target)
	local steps = Config.migrations[scope] or {}
	for n = from + 1, target do
		local step = steps[n]
		if step then
			local ok, err = pcall(step, db)
			if not ok then return false, "step " .. n .. " failed: " .. tostring(err):sub(1, 100) end
		end
		db.schemaVersion = n
	end
	return true
end

local function loadScope(scope)
	local var = Config.VARIABLES[scope]
	local raw = _G[var]
	local target = Config.SCHEMA_VERSION
	Config.readOnly[scope] = nil
	local work

	if type(raw) ~= "table" then
		if raw ~= nil then issue(var .. ": not a table, replaced by defaults") end
		raw = {}
		_G[var] = raw
		Config.loadedVersion[scope] = target
		work = raw
		raw.schemaVersion = target
	else
		local version = schemaOf(raw)
		if version == nil then
			issue(var .. ": damaged schemaVersion, treated as 0")
			version = 0
		elseif version == 0 and raw.schemaVersion == nil and not isEmpty(raw) then
			issue(var .. ": schemaVersion lost, treated as 0")
		end
		Config.loadedVersion[scope] = version

		if version > target then
			-- Newer addon wrote this: read it, never rewrite it. All work happens on a copy.
			Config.readOnly[scope] = true
			issue(("%s: schema %d is newer than %d, read-only"):format(var, version, target))
			work = copy(raw)
			work.schemaVersion = target
		elseif version < target and not (version == 0 and isEmpty(raw)) then
			local trial = copy(raw)
			local ok, why = migrate(scope, trial, version, target)
			if ok then
				-- success: apply in place so the saved table keeps its identity
				for k in pairs(raw) do raw[k] = nil end
				for k, v in pairs(trial) do raw[k] = v end
				work = raw
			else
				Config.readOnly[scope] = true
				issue(var .. ": migration " .. why .. ", read-only")
				work = copy(raw)
				work.schemaVersion = target
			end
		else
			work = raw
		end
		work.schemaVersion = target
	end

	mergeDefaults(work, Config.defaults[scope])
	Config.Sanitize(scope, work)
	Config.db[scope] = work
end

-- Loads both variables. Safe to call again (tests, /reload): the second run changes nothing.
function Config:Load()
	Config.issues = {}
	for _, scope in ipairs({ "account", "char" }) do loadScope(scope) end
	self.loaded = true
	if ns.Bus then ns.Bus:Emit("CONFIG_LOADED") end
	return #Config.issues == 0
end

function Config:IsReadOnly(scope)
	if scope then return Config.readOnly[scope] == true end
	return Config.readOnly.account == true or Config.readOnly.char == true
end

-- The account token (SPEC-03 §1), or nil before Load.
function Config:Token()
	local db = Config.db.account
	return db and db.token or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Get / Set by path: "char.ui.lastView"
---------------------------------------------------------------------------------------------------------------------
function Config:Get(path)
	local parts = split(path)
	local node = Config.db[parts[1]]
	for i = 2, #parts do
		if type(node) ~= "table" then return nil end
		node = node[parts[i]]
	end
	return node
end

-- Validated write. Returns true, or false and a reason ("unknown path", "read-only", or the rule violation).
function Config:Set(path, value)
	local parts = split(path)
	local scope = parts[1]
	local key = table.concat(parts, ".")
	local rule = Config.rules[key]
	if not rule or not Config.db[scope] then return false, "unknown path" end
	if Config.readOnly[scope] then return false, "read-only" end
	if #parts < 2 or key == scope .. ".schemaVersion" or key == "account.token" then return false, "protected" end
	local why = violation(rule, value)
	if why then return false, why end
	local parent, leaf = locate(Config.db[scope], parts, 2)
	if not parent then return false, "parent missing" end
	if rule.type == "timestamp" and value > now() then value = now() end
	parent[leaf] = value
	if ns.Bus then ns.Bus:Emit("CONFIG_CHANGED", key) end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Sizes (SPEC-01 §4: /accord debug shows them) and /accord debug
---------------------------------------------------------------------------------------------------------------------
-- An estimate of the bytes a value takes in the saved file: keys, values and punctuation, like the client writes it.
function Config.EstimateSize(value, seen)
	local t = type(value)
	if t == "string" then return #value + 2 end
	if t == "number" then return 8 end
	if t == "boolean" then return 5 end
	if t ~= "table" then return 0 end
	seen = seen or {}
	if seen[value] then return 0 end
	seen[value] = true
	local total = 2
	for k, v in pairs(value) do
		total = total + Config.EstimateSize(k, seen) + Config.EstimateSize(v, seen) + 4
	end
	return total
end

local function kb(bytes) return ("%.1f KB"):format(bytes / 1024) end

function Config:DebugLines()
	local lines = {}
	for _, scope in ipairs({ "account", "char" }) do
		local db = Config.db[scope]
		lines[#lines + 1] = ("%s: schema found %s, current %d, about %s%s"):format(Config.VARIABLES[scope],
			tostring(Config.loadedVersion[scope]), Config.SCHEMA_VERSION, kb(db and Config.EstimateSize(db) or 0),
			Config.readOnly[scope] and " - READ-ONLY (never rewritten)" or "")
	end
	local account = Config.db.account or {}
	local guilds, realms, chars = 0, 0, 0
	for _ in pairs(account.guilds or {}) do guilds = guilds + 1 end
	for _, list in pairs(account.chars or {}) do
		realms = realms + 1
		for _ in pairs(list) do chars = chars + 1 end
	end
	lines[#lines + 1] = ("Account: token %s, %d character(s) on %d realm(s), data of %d guild(s)"):format(
		(account.token and account.token ~= "") and "set" or "missing", chars, realms, guilds)
	local kb = ns.Compat and ns.Compat.Addon and ns.Compat.Addon.MemoryKB()
	lines[#lines + 1] = kb and ("Memory: about %.1f MB in use by the addon (the game's figure)"):format(kb / 1024)
		or "Memory: unknown (the game gives no figure)"
	if ns.GuildKey and ns.GuildKey.SizeLines then
		for _, line in ipairs(ns.GuildKey:SizeLines()) do lines[#lines + 1] = line end
	end
	lines[#lines + 1] = #Config.issues == 0 and "Saved data: no problems" or
		("Saved data: %d problem(s) fixed or noted:"):format(#Config.issues)
	for i, text in ipairs(Config.issues) do
		if i > 15 then lines[#lines + 1] = "  ..." break end
		lines[#lines + 1] = "  " .. text
	end
	return lines
end

if ns.addon then
	ns.addon.Config = Config
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Saved data", function() return Config:DebugLines() end)
	end
end

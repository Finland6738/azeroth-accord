-- Backup: the player's own data as one text to copy to another computer (SPEC-11 §4, M7.5). Lua 5.1.
--
--   text = "AZACCORD<format>:<checksum>:<body>"
--   body = Base64( flag .. (flag == "\1" and Deflate(CBOR(content)) or CBOR(content)) )   -- the encoding of Net/Codec.lua
--   checksum = the first 8 lower-case hex digits of SHA-256(body): it finds a text cut or changed in the copy, it does not
--              protect against somebody who forges one (anybody can compute it again)
--   content  = { v, made, addon, account = { token, chars, mains, settings }, guilds = { [key] = { accounts, contacts,
--                recipes } } }  -- in `guilds` only the records whose character is one of the account's (and written by one)
--
-- Never in it: other players' records, co-play, bank snapshots, logs and requests, the likes (ledger, queue, memory, salt),
-- the guild settings, the character's own settings (AzerothAccordCharDB) and the outbox.
--
--   Backup:Export()        -> text, stats | nil, reason ("demo", "token", "encode", "size", "hash")
--   Backup:Check(text)     -> result: { ok = true, content, preview } | { ok = false, reason, part }; changes nothing.
--                             reasons, in the order of SPEC-11 §4.4: "foreign", "newer", "damaged", "unusable" (with
--                             `part`), "account"; plus "demo" and "read-only" when no import is possible at all
--   Backup:Apply(content)  -> summary { chars, settings, records } | nil, reason: writes only AzerothAccordDB, never the
--                             outbox; then the accounts are rebuilt and the own records published again
--   Backup:Import(text)    -> Check then Apply (the tests; the UI shows the preview between the two)
--   Backup.Message(result) -> the text the box shows for a refusal
--
-- The token: the text holds it, so nothing here prints, logs or sends the text or the token, and /accord debug only counts.
-- Bus: BACKUP_IMPORTED(summary) after an import.
local ADDON_NAME, ns = ...
ns = ns or {}
local Backup = {}
ns.Backup, ns.modules = Backup, ns.modules or {}
ns.modules.Backup = Backup

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, huge = math.floor, math.huge
local sub, find, match, gsub = string.sub, string.find, string.match, string.gsub

Backup.HEADER = "AZACCORD"
Backup.FORMAT = 1                  -- grows when the content changes in a way an older addon would not understand
Backup.MAX_TEXT = 262144           -- 256 KB, out and in
Backup.MAX_DECODED = 1048576       -- 1 MB of CBOR after decompression
Backup.COMPRESS_OVER = 120
Backup.FLAG_RAW, Backup.FLAG_DEFLATE = "\0", "\1"
Backup.SETS = { "accounts", "contacts", "recipes" }                   -- the own records it carries
Backup.CHAR_FIELDS = { name = "string", classID = "number", level = "number", guild = "string", guildAt = "number",
	seen = "number", added = "number", answered = "number" }        -- the local fields of a character
Backup.GUID_PATTERN = "^Player%-%d+%-%x+$"
Backup.NAME_MAX = 48
Backup.REALM_MAX = 64
Backup.KEY_MAX = 128

local state = { exports = 0, checks = 0, refused = {}, imports = 0 }
Backup.state = state

local function compat() return ns.Compat end
local function now() return compat() and compat().ServerTime() or time() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function accountDB() return ns.Config and ns.Config.db and ns.Config.db.account or nil end
local function inDemo() return ns.Demo ~= nil and ns.Demo:IsActive() end
local function copy(v) return ns.Config.Copy(v) end

local function isGUID(v) return type(v) == "string" and #v <= 40 and find(v, Backup.GUID_PATTERN) ~= nil end
local function isFinite(v) return type(v) == "number" and v == v and v ~= huge and v ~= -huge end
local function plainText(v, max)   -- a non-empty string without control characters
	return type(v) == "string" and v ~= "" and #v <= max and not find(v, "%c")
end

local function addonVersion()
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or nil
	return type(v) == "string" and v or nil
end

-- The GUIDs of the account's characters in `chars` ({ [realm] = { [guid] = entry } }), as a set.
local function guidsOf(chars)
	local out = {}
	for _, list in pairs(type(chars) == "table" and chars or {}) do
		if type(list) == "table" then
			for guid in pairs(list) do out[guid] = true end
		end
	end
	return out
end

-- The character a record of `set` belongs to.
local function charOf(set, rec)
	if set == "recipes" then return rec.char end
	return rec.id
end

---------------------------------------------------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------------------------------------------------
local function ownChars(db)
	local out = {}
	for realm, list in pairs(type(db.chars) == "table" and db.chars or {}) do
		if type(realm) == "string" and type(list) == "table" then
			for guid, e in pairs(list) do
				if isGUID(guid) and type(e) == "table" then
					local entry = {}
					for field, kind in pairs(Backup.CHAR_FIELDS) do
						if type(e[field]) == kind then entry[field] = e[field] end
					end
					out[realm] = out[realm] or {}
					out[realm][guid] = entry
				end
			end
		end
	end
	return out
end

-- The own records of every known guild: a record of a character of the account, written by a character of the account
-- (a copy an officer passed on keeps its author, so it is still the player's own).
local function ownRecords(db, own)
	local out, count = {}, 0
	for key, data in pairs(type(db.guilds) == "table" and db.guilds or {}) do
		local sets = type(data) == "table" and type(data.store) == "table" and data.store.sets
		if type(key) == "string" and type(sets) == "table" then
			local entry
			for _, set in ipairs(Backup.SETS) do
				local list = {}
				for _, rec in pairs(type(sets[set]) == "table" and sets[set] or {}) do
					if type(rec) == "table" and own[charOf(set, rec)] and own[rec.author] then list[#list + 1] = copy(rec) end
				end
				if #list > 0 then
					table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
					entry = entry or {}
					entry[set] = list
					count = count + #list
				end
			end
			if entry then out[key] = entry end
		end
	end
	return out, count
end

-- The content of the backup of this account (a table; the tests look at it).
function Backup:Content()
	local db = accountDB()
	if type(db) ~= "table" then return nil, "db" end
	local chars = ownChars(db)
	local own = guidsOf(chars)
	local mains = {}
	for realm, guid in pairs(type(db.mains) == "table" and db.mains or {}) do
		if type(realm) == "string" and own[guid] then mains[realm] = guid end
	end
	local settings = {}
	for k, v in pairs(type(db.settings) == "table" and db.settings or {}) do
		if type(k) == "string" and ns.Config.rules["account.settings." .. k] and type(v) ~= "table" then settings[k] = v end
	end
	local guilds, records = ownRecords(db, own)
	return { v = Backup.FORMAT, made = now(), addon = addonVersion(),
		account = { token = db.token, chars = chars, mains = mains, settings = settings }, guilds = guilds }, records
end

function Backup:Export()
	if inDemo() then return nil, "demo" end
	local C = compat()
	local content, records = self:Content()
	if not content then return nil, records end
	if type(content.account.token) ~= "string" or content.account.token == "" then return nil, "token" end
	local cbor = C and C.CBOR.Encode(content)
	if not cbor then return nil, "encode" end
	if #cbor > Backup.MAX_DECODED then return nil, "size" end
	local flag, packed = Backup.FLAG_RAW, cbor
	if #cbor > Backup.COMPRESS_OVER then
		local deflated = C.Compress.Deflate(cbor)
		if deflated and #deflated < #cbor then flag, packed = Backup.FLAG_DEFLATE, deflated end
	end
	local body = C.Base64.Encode(flag .. packed)
	if not body then return nil, "encode" end
	local digest = ns.Hash and ns.Hash.SHA256Hex(body)
	if not digest then return nil, "hash" end
	local text = Backup.HEADER .. Backup.FORMAT .. ":" .. sub(digest, 1, 8) .. ":" .. body
	if #text > Backup.MAX_TEXT then return nil, "size" end
	state.exports = state.exports + 1
	local nChars = 0
	for _ in pairs(guidsOf(content.account.chars)) do nChars = nChars + 1 end
	return text, { length = #text, chars = nChars, records = records }
end

---------------------------------------------------------------------------------------------------------------------
-- Reading and validation (SPEC-11 §4.4): the first error refuses the whole text
---------------------------------------------------------------------------------------------------------------------
local function refuse(reason, part)
	state.refused[reason] = (state.refused[reason] or 0) + 1
	return { ok = false, reason = reason, part = part }
end

-- Steps 1-4: the text to the content table, or nil plus the reason.
function Backup.Decode(text)
	if type(text) ~= "string" then return nil, "foreign" end
	text = gsub(text, "%s", "")
	if text == "" or #text > Backup.MAX_TEXT then return nil, "foreign" end
	local version, checksum, body = match(text, "^" .. Backup.HEADER .. "(%d+):([0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]):(.*)$")
	if not version then return nil, "foreign" end
	version = tonumber(version)
	if not version or version < 1 then return nil, "foreign" end
	if version > Backup.FORMAT then return nil, "newer" end
	local digest = ns.Hash and ns.Hash.SHA256Hex(body)
	if not digest or sub(digest, 1, 8) ~= checksum then return nil, "damaged" end
	if body == "" or #body % 4 ~= 0 or find(body, "[^A-Za-z0-9+/=]") then return nil, "damaged" end
	local C = compat()
	local raw = C and C.Base64.Decode(body)
	if type(raw) ~= "string" or raw == "" then return nil, "damaged" end
	local flag, packed = sub(raw, 1, 1), sub(raw, 2)
	if flag == Backup.FLAG_DEFLATE then
		packed = C.Compress.Inflate(packed)
		if type(packed) ~= "string" then return nil, "damaged" end
	elseif flag ~= Backup.FLAG_RAW then
		return nil, "damaged"
	end
	if #packed == 0 or #packed > Backup.MAX_DECODED then return nil, "damaged" end
	local content = C.CBOR.Decode(packed)
	if type(content) ~= "table" or content.v ~= version then return nil, "damaged" end
	return content
end

local function badChars(chars)
	if type(chars) ~= "table" or next(chars) == nil then return true end
	for realm, list in pairs(chars) do
		if not plainText(realm, Backup.REALM_MAX) or type(list) ~= "table" then return true end
		for guid, e in pairs(list) do
			if not isGUID(guid) or type(e) ~= "table" then return true end
			if not plainText(e.name, Backup.NAME_MAX) then return true end
			for field, kind in pairs(Backup.CHAR_FIELDS) do
				local v = e[field]
				if v ~= nil then
					if type(v) ~= kind then return true end
					if kind == "number" and (not isFinite(v) or v < 0 or v ~= floor(v)) then return true end
					if kind == "string" and (#v > Backup.KEY_MAX or find(v, "%c")) then return true end
				end
			end
		end
	end
	return false
end

local function badSettings(settings)
	if type(settings) ~= "table" then return true end
	for k, v in pairs(settings) do
		local rule = type(k) == "string" and ns.Config.rules["account.settings." .. k]
		-- an unknown or wrong value is an error, never a reset to the default
		if not rule or rule.type == "table" or ns.Config.Violation(rule, v) then return true end
	end
	return false
end

-- The owner rules of Store, with "same account" read from the backup's own list of characters.
local function badRecords(guilds, own)
	if type(guilds) ~= "table" then return true end
	local S = ns.Store
	local fake = { SameAccount = function(_, a, b) return own[a] == true and own[b] == true end }
	for key, sets in pairs(guilds) do
		if not plainText(key, Backup.KEY_MAX) or not find(key, "^[^/]+/.+$") or type(sets) ~= "table" then return true end
		for set, list in pairs(sets) do
			local allowed = false
			for _, name in ipairs(Backup.SETS) do if name == set then allowed = true end end
			if not allowed or type(list) ~= "table" then return true end
			local seen = {}
			for i, rec in pairs(list) do
				if type(i) ~= "number" or type(rec) ~= "table" then return true end
				if S.ValidShape(set, rec) then return true end
				if seen[rec.id] then return true end
				seen[rec.id] = true
				if not own[charOf(set, rec)] or not own[rec.author] then return true end
				local def = S.SETS[set]
				if def.owner and not def.owner(rec, fake) then return true end
			end
		end
	end
	return false
end

-- Step 5: nil when the content can be used, else the part that cannot.
function Backup.Invalid(content)
	local account = content.account
	if type(account) ~= "table" then return "account" end
	if content.made ~= nil and not isFinite(content.made) then return "account" end
	if content.addon ~= nil and not plainText(content.addon, 32) then return "account" end
	if ns.Config.Violation(ns.Config.rules["account.token"], account.token) then return "token" end
	if badChars(account.chars) then return "characters" end
	local own = guidsOf(account.chars)
	if type(account.mains) ~= "table" then return "main" end
	for realm, guid in pairs(account.mains) do
		if not plainText(realm, Backup.REALM_MAX) or not own[guid] then return "main" end
	end
	if badSettings(account.settings) then return "settings" end
	if badRecords(content.guilds, own) then return "records" end
	return nil
end

-- Step 6: a backup of another account. A new computer (only the character logged in, a token just made) takes it.
local function otherAccount(content, db)
	if content.account.token == db.token then return false end
	local own = guidsOf(content.account.chars)
	local me = compat() and compat().Player.GUID()
	for guid in pairs(guidsOf(db.chars)) do
		if guid ~= me and not own[guid] then return true end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Preview (SPEC-11 §4.5)
---------------------------------------------------------------------------------------------------------------------
local function findChar(chars, guid)
	for realm, list in pairs(type(chars) == "table" and chars or {}) do
		if type(list) == "table" and type(list[guid]) == "table" then return list[guid], realm end
	end
	return nil
end

local function nameOf(db, content, guid)
	local e = findChar(content.account.chars, guid) or findChar(db.chars, guid)
	return e and e.name or "?"
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

-- What an import would change: { token = "kept"|"replaced", added = { { name, realm } }, present = n, replaced = n,
-- selfMissing = name|nil, mains = { { realm, old, new } }, settings = { { key, old, new } }, guilds = { { key, restore,
-- keep } }, changes = n }.
function Backup:Preview(content)
	local db = accountDB()
	local p = { token = content.account.token == db.token and "kept" or "replaced", added = {}, present = 0, replaced = 0,
		mains = {}, settings = {}, guilds = {} }
	for _, realm in ipairs(sortedKeys(content.account.chars)) do
		local list = content.account.chars[realm]
		for _, guid in ipairs(sortedKeys(list)) do
			local mine = findChar(db.chars, guid)
			if not mine then
				p.added[#p.added + 1] = { name = list[guid].name, realm = realm }
			else
				p.present = p.present + 1
				if (list[guid].seen or 0) > (mine.seen or 0) then p.replaced = p.replaced + 1 end
			end
		end
	end
	local me = compat() and compat().Player.GUID()
	if me and not guidsOf(content.account.chars)[me] then
		local e = findChar(db.chars, me)
		p.selfMissing = e and e.name or (compat().Player.Name() or "?")
	end
	local mains = type(db.mains) == "table" and db.mains or {}
	for _, realm in ipairs(sortedKeys(content.account.mains)) do
		local new = content.account.mains[realm]
		if mains[realm] ~= new then
			p.mains[#p.mains + 1] = { realm = realm, old = mains[realm] and nameOf(db, content, mains[realm]) or nil,
				new = nameOf(db, content, new), guid = new }
		end
	end
	local settings = type(db.settings) == "table" and db.settings or {}
	for _, key in ipairs(sortedKeys(content.account.settings)) do
		local new = content.account.settings[key]
		if settings[key] ~= new then p.settings[#p.settings + 1] = { key = key, old = settings[key], new = new } end
	end
	for _, key in ipairs(sortedKeys(content.guilds)) do
		local data = type(db.guilds) == "table" and db.guilds[key]
		local held = type(data) == "table" and type(data.store) == "table" and type(data.store.sets) == "table" and data.store.sets or {}
		local restore, keep = 0, 0
		for _, set in ipairs(Backup.SETS) do
			for _, rec in ipairs(content.guilds[key][set] or {}) do
				local mine = type(held[set]) == "table" and held[set][rec.id] or nil
				if ns.Store.Compare(rec, mine) > 0 then restore = restore + 1 else keep = keep + 1 end
			end
		end
		p.guilds[#p.guilds + 1] = { key = key, restore = restore, keep = keep }
	end
	local n = (p.token == "replaced" and 1 or 0) + #p.added + p.replaced + #p.mains + #p.settings
	for _, g in ipairs(p.guilds) do n = n + g.restore end
	p.changes = n
	return p
end

---------------------------------------------------------------------------------------------------------------------
-- Check and apply
---------------------------------------------------------------------------------------------------------------------
-- Why no import is possible now (the card says it), or nil.
function Backup:ImportBlocked()
	if inDemo() then return "demo" end
	if ns.Config:IsReadOnly("account") then return "read-only" end
	if type(accountDB()) ~= "table" then return "db" end
	return nil
end

function Backup:Check(text)
	state.checks = state.checks + 1
	local blocked = self:ImportBlocked()
	if blocked then return refuse(blocked) end
	local content, why = Backup.Decode(text)
	if not content then return refuse(why) end
	local part = Backup.Invalid(content)
	if part then return refuse("unusable", part) end
	if otherAccount(content, accountDB()) then return refuse("account") end
	return { ok = true, content = content, preview = self:Preview(content) }
end

function Backup:Apply(content)
	local blocked = self:ImportBlocked()
	if blocked then return nil, blocked end
	if type(content) ~= "table" or Backup.Invalid(content) then return nil, "unusable" end
	local db = accountDB()
	if otherAccount(content, db) then return nil, "account" end
	local t = now()
	local summary = { chars = 0, settings = 0, records = 0, token = content.account.token ~= db.token }

	db.token = content.account.token

	if type(db.chars) ~= "table" then db.chars = {} end
	for realm, list in pairs(content.account.chars) do
		for guid, entry in pairs(list) do
			local mine, at = findChar(db.chars, guid)
			if not mine or (entry.seen or 0) > (mine.seen or 0) then
				if mine then db.chars[at][guid] = nil end
				if type(db.chars[realm]) ~= "table" then db.chars[realm] = {} end
				local e = copy(entry)
				if e.added == nil then e.added = t end
				db.chars[realm][guid] = e
				summary.chars = summary.chars + 1
			end
		end
	end

	if type(db.mains) ~= "table" then db.mains = {} end
	for realm, guid in pairs(content.account.mains) do db.mains[realm] = guid end

	if type(db.settings) ~= "table" then db.settings = {} end
	local changed = {}
	for key, value in pairs(content.account.settings) do
		if db.settings[key] ~= value then
			db.settings[key] = value
			changed[#changed + 1] = key
		end
	end
	summary.settings = #changed

	-- the own records: never replaced by an older version (Store.Compare); written straight into the guild's table, so
	-- nothing goes to the outbox (origin "backup": the sync does not send them)
	local restored = {}
	if type(db.guilds) ~= "table" then db.guilds = {} end
	for key, sets in pairs(content.guilds) do
		local data = db.guilds[key]
		if type(data) ~= "table" then data = { firstSeen = t, lastSeen = t } db.guilds[key] = data end
		if type(data.store) ~= "table" then data.store = { sets = {} } end
		if type(data.store.sets) ~= "table" then data.store.sets = {} end
		for _, set in ipairs(Backup.SETS) do
			for _, rec in ipairs(sets[set] or {}) do
				local records = data.store.sets[set]
				if type(records) ~= "table" then records = {} data.store.sets[set] = records end
				if ns.Store.Compare(rec, records[rec.id]) > 0 then
					records[rec.id] = copy(rec)
					summary.records = summary.records + 1
					restored[#restored + 1] = { key = key, set = set, id = rec.id }
				end
			end
		end
	end

	state.imports = state.imports + 1
	local current = ns.GuildKey and ns.GuildKey:Current()
	for _, r in ipairs(restored) do
		if r.key == current then emit("STORE_CHANGED", r.set, r.id, "backup") end
	end
	for _, key in ipairs(changed) do emit("CONFIG_CHANGED", "account.settings." .. key) end
	-- the accounts again, then this character's own records: `rev` goes on from the restored one
	if ns.Accounts then
		ns.Accounts:MarkDirty()
		if ns.Accounts.Rebuild then ns.Accounts:Rebuild() end
		if current then ns.Accounts:Publish() end
	end
	if ns.Contacts and current then ns.Contacts:Publish() end
	emit("BACKUP_IMPORTED", summary)
	emit("SETTINGS_CHANGED", "backup")
	return summary
end

function Backup:Import(text)
	local result = self:Check(text)
	if not result.ok then return nil, result.reason, result.part end
	return self:Apply(result.content)
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
local MESSAGES = { foreign = "BACKUP_FOREIGN", newer = "BACKUP_NEWER", damaged = "BACKUP_DAMAGED", unusable = "BACKUP_UNUSABLE",
	account = "BACKUP_OTHER_ACCOUNT", demo = "BACKUP_NO_DEMO", ["read-only"] = "BACKUP_READONLY" }
local PARTS = { account = "BACKUP_PART_ACCOUNT", token = "BACKUP_PART_TOKEN", characters = "BACKUP_PART_CHARACTERS",
	main = "BACKUP_PART_MAIN", settings = "BACKUP_PART_SETTINGS", records = "BACKUP_PART_RECORDS" }

-- The text of a refusal (a result of Check, or a reason).
function Backup.Message(result)
	local L = ns.L
	local reason = type(result) == "table" and result.reason or result
	local key = MESSAGES[reason]
	if not key then return L["BACKUP_FAILED"]:format(tostring(reason)) end
	if reason == "unusable" then
		local part = type(result) == "table" and result.part or nil
		return L[key]:format(L[PARTS[part] or "BACKUP_PART_ACCOUNT"])
	end
	return L[key]
end

local function show(v)
	local L = ns.L
	if v == nil then return L["BACKUP_NONE"] end
	if v == true then return L["BACKUP_ON"] end
	if v == false then return L["BACKUP_OFF"] end
	return tostring(v)
end

-- The lines of a preview, in the player's language.
function Backup.PreviewLines(p)
	local L = ns.L
	local lines = { L["BACKUP_PV_TITLE"] }
	lines[#lines + 1] = p.token == "kept" and L["BACKUP_PV_TOKEN_KEPT"] or L["BACKUP_PV_TOKEN_REPLACED"]
	for _, c in ipairs(p.added) do lines[#lines + 1] = L["BACKUP_PV_CHAR_ADDED"]:format(c.name, c.realm) end
	if p.present > 0 then lines[#lines + 1] = L["BACKUP_PV_CHARS_PRESENT"]:format(p.present, p.replaced) end
	if p.selfMissing then lines[#lines + 1] = L["BACKUP_PV_SELF"]:format(p.selfMissing) end
	for _, m in ipairs(p.mains) do lines[#lines + 1] = L["BACKUP_PV_MAIN"]:format(m.realm, show(m.old), m.new) end
	for _, s in ipairs(p.settings) do lines[#lines + 1] = L["BACKUP_PV_SETTING"]:format(s.key, show(s.old), show(s.new)) end
	for _, g in ipairs(p.guilds) do lines[#lines + 1] = L["BACKUP_PV_RECORDS"]:format(g.key, g.restore, g.keep) end
	if p.changes == 0 then lines[#lines + 1] = L["BACKUP_PV_NOTHING"] end
	return lines
end

-- `/accord backup`: the card of the Settings page.
function Backup.Command()
	if ns.addon then ns.addon:OpenView("settings") end
	if ns.SettingsView and ns.SettingsView.ShowBackup then ns.SettingsView:ShowBackup() end
end

-- /accord debug: counts only, never the text or the token.
function Backup:DebugLines()
	local reasons = {}
	for k, v in pairs(state.refused) do reasons[#reasons + 1] = k .. " " .. v end
	table.sort(reasons)
	return { ("Backup: exported %d, checked %d, imported %d, refused %s"):format(state.exports, state.checks, state.imports,
		#reasons > 0 and table.concat(reasons, ", ") or "0") }
end

if ns.addon then
	ns.addon.Backup = Backup
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Backup", function() return Backup:DebugLines() end) end
end

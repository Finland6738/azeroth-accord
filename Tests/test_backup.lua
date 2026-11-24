-- Personal backup (M7.5; SPEC-11 §4): the player's own data to one text and back. A round trip restores the same data;
-- a damaged, truncated, foreign, other-version or other-account text is refused with its message and nothing changes;
-- other players' data never appears in the export; the token is never printed.
local function A() return AzerothAccord end
local function B() return AzerothAccord.Backup end
local function S() return AzerothAccord.Store end
local function L() return LibStub("AceLocale-3.0"):GetLocale("AzerothAccord", true) end

local ME, ALT = "Player-1-0000A001", "Player-1-0000A002"
local BOB, BOBALT, MAL = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000BAD"

-- A text that is the same for equal tables whatever the order of the keys.
local function canon(value, skip)
	local t = type(value)
	if t == "string" then return ("%q"):format(value) end
	if t ~= "table" then return tostring(value) end
	local keys = {}
	for k in pairs(value) do if not (skip and skip[k]) then keys[#keys + 1] = k end end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) < type(b) end
		return a < b
	end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. canon(k, skip) .. "]=" .. canon(value[k], skip) end
	return "{" .. table.concat(parts, ",") .. "}"
end
local LAST = { lastSeen = true }
local function saved() return canon(AzerothAccordDB, LAST) .. canon(AzerothAccordCharDB, LAST) end

local function guild()
	Mock.guild.Set{ name = "Accord", myRank = 1, members = {
		{ name = "Bob", level = 50, class = "MAGE", rank = 0, guid = BOB },
		{ name = "Bobalt", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT },
		{ name = "Mallory", level = 20, class = "ROGUE", rank = 3, guid = MAL },
		{ name = "Altchar", level = 40, class = "PRIEST", rank = 4, guid = ALT },
	} }
end

local function rec(set, id, author, fields)
	local r = { id = id, author = author, rev = 1, time = GetServerTime() }
	for k, v in pairs(fields or {}) do r[k] = v end
	S():Records(set)[id] = r
	return r
end

-- A guild full of other players' data, and the player's own: an alt, a main, a Discord name, the theme, a recipe list.
local function fill()
	local Acc = A().Accounts
	Acc:Register{ guid = ALT, name = "Altchar", classID = 5, level = 40, guild = A().GuildKey:Current() }
	truthy(Acc:SetMain(ALT))
	truthy(A().Contacts:SetDiscord("me_on_discord"))
	truthy(A().Config:Set("account.settings.theme", "aurora"))
	truthy(A().Config:Set("account.settings.effects", false))
	truthy(S():Put("recipes", ME .. ":171", { char = ME, skillLine = 171, ids = { 2329, 2330 } }))
	-- the alt's own record, as the alt would have published it
	rec("accounts", ALT, ALT, { token = A().Config:Token(), chars = { { guid = ME, name = "Testchar" }, { guid = ALT, name = "Altchar" } } })
	-- other players
	rec("accounts", BOB, BOB, { token = "BOBTOKENBOBTOKENBOBTOKEN", chars = { { guid = BOB, name = "Bob" }, { guid = BOBALT, name = "Bobalt" } } })
	rec("accounts", BOBALT, BOBALT, { token = "BOBTOKENBOBTOKENBOBTOKEN", chars = { { guid = BOB, name = "Bob" }, { guid = BOBALT, name = "Bobalt" } } })
	rec("contacts", BOB, BOB, { account = "BOBTOKENBOBTOKENBOBTOKEN", battleTag = "Bob#1234", discord = "bob_disc" })
	rec("contacts", MAL, BOB, { account = "x", discord = "mallory_disc" })   -- relayed by an officer: still not mine
	rec("recipes", BOB .. ":164", BOB, { char = BOB, skillLine = 164, ids = { 1, 2 } })
	rec("coplay", ME .. ":20261124", ME, { observer = ME, day = 20261124, pairs = { [ME .. "|" .. BOB] = 30 } })
	rec("bankreq", ME .. ":1", ME, { status = "open", item = 2589, count = 1 })
	A().Accounts:MarkDirty()
	Acc:Publish()
	notNil(S():Get("accounts", ME))
end

local exported, before = nil, nil

describe("export (SPEC-11 §4.1-4.2)", function()
	before_boot(function() guild() end)

	it("is one line with the versioned header and the checksum, and holds only the player's own data", function()
		fill()
		local text, info = B():Export()
		notNil(text)
		matches(text, "^AZACCORD1:[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]:[A-Za-z0-9+/=]+$")
		eq(info.chars, 2)
		eq(info.records, 4, "the two accounts records, the contacts and the recipes of the player")
		local content = B().Decode(text)
		notNil(content)
		eq(content.v, 1)
		eq(content.account.token, A().Config:Token())
		eq(content.account.mains[GetNormalizedRealmName()], ALT)
		eq(content.account.settings.theme, "aurora")
		eq(content.account.settings.effects, false)
		eq(content.account.settings.discord, "me_on_discord")
		local all = canon(content)
		for _, other in ipairs({ BOB, BOBALT, MAL, "Bob", "Mallory", "bob_disc", "mallory_disc", "BOBTOKEN", "20261124", "bankreq", "coplay" }) do
			falsy(all:find(other, 1, true), other .. " is not in the export")
		end
		-- every GUID and every name in it is a character of the account
		for guid in all:gmatch("Player%-%d+%-%x+") do truthy(guid == ME or guid == ALT, guid) end
		exported = text
		before = { token = content.account.token, chars = canon(content.account.chars), mains = canon(content.account.mains),
			settings = canon(content.account.settings), guilds = canon(content.guilds) }
	end)

	it("never prints the text or the token", function()
		fill()
		Mock.ClearOutput()
		local text = B():Export()
		B():Import(text)
		local out = table.concat(Mock.PlainOutput(), " ")
		falsy(out:find(A().Config:Token(), 1, true))
		falsy(out:find(text:sub(20, 60), 1, true))
		for _, line in ipairs(B():DebugLines()) do falsy(line:find(A().Config:Token(), 1, true)) end
	end)

	it("is refused in demo mode", function()
		Mock.Slash("/accord demo")
		local text, why = B():Export()
		isNil(text)
		eq(why, "demo")
		eq(B():Check(exported or "x").reason, "demo")
		Mock.Slash("/accord demo")
	end)
end)

describe("round trip on a new computer (SPEC-11 §4.4-4.5)", function()
	before_boot(function() guild() end)

	it("restores the same data", function()
		notNil(exported, "the export test ran first")
		A().Accounts:RegisterSelf()   -- at login (the automatic start is off in the tests)
		-- a new computer has its own token
		A().Config.db.account.token = "TkVXQ09NUFVURVJUT0tFTg=="
		local result = B():Check(exported)
		truthy(result.ok, result.reason)
		eq(result.preview.token, "replaced")
		eq(#result.preview.added, 1, "the alt is added; the character logged in is already there")
		local summary = B():Apply(result.content)
		notNil(summary)
		local db = A().Config.db.account
		eq(db.token, before.token)
		eq(canon(db.mains), before.mains)
		local back = B():Content()
		eq(canon(back.account.settings), before.settings)
		eq(back.account.chars[GetNormalizedRealmName()][ALT].name, "Altchar")
		eq(back.account.chars[GetNormalizedRealmName()][ALT].classID, 5)
		eq(A().Config:Get("account.settings.theme"), "aurora")
		eq(A().Contacts:OwnDiscord(), "me_on_discord")
		-- the own records are back, and republished from the restored rev on
		local key = A().GuildKey:Current()
		local recipe = S():Get("recipes", ME .. ":171")
		notNil(recipe)
		eq(canon(recipe.ids), canon({ 2329, 2330 }))
		truthy(S():Get("accounts", ALT))
		eq(S():Get("accounts", ME).token, before.token)
		eq(S():Get("contacts", ME).discord, "me_on_discord")
		-- the restored record is the one this account published: nothing new to publish, and a later write goes on from its rev
		local restoredRev = S():Get("accounts", ME).rev
		truthy(A().Accounts:SetMain(ME))
		eq(S():Get("accounts", ME).rev, restoredRev + 1)
		eq(summary.settings >= 3, true)
		-- the outbox was not touched by the import itself
		eq(#(AzerothAccordCharDB.outbox or {}), 0)
		notNil(key)
	end)

	it("a second import of the same text changes nothing more", function()
		truthy(B():Import(exported))
		local first = saved()
		local result = B():Check(exported)
		truthy(result.ok)
		eq(result.preview.token, "kept")
		local s = B():Apply(result.content)
		eq(s.records, 0)
		eq(s.settings, 0)
	end)

	it("accepts the text with spaces and line breaks in it", function()
		local broken = exported:sub(1, 30) .. "\n  " .. exported:sub(31, 80) .. "\r\n" .. exported:sub(81)
		truthy(B():Check(broken).ok)
	end)
end)

-- A backup text of any content, made the same way as the addon does (to forge the cases the addon never writes).
local function make(content, version)
	local C = A().Compat
	local cbor = C.CBOR.Encode(content)
	local body = C.Base64.Encode("\0" .. cbor)
	return "AZACCORD" .. (version or 1) .. ":" .. A().Hash.SHA256Hex(body):sub(1, 8) .. ":" .. body
end

local function goodContent()
	local realm = GetNormalizedRealmName()
	return { v = 1, made = GetServerTime(), account = { token = A().Config:Token(),
		chars = { [realm] = { [ME] = { name = "Testchar", level = 60, seen = GetServerTime() } } }, mains = {}, settings = {} }, guilds = {} }
end

describe("refusals (SPEC-11 §4.4): nothing changes", function()
	before_boot(function() guild() end)

	local function refused(text, reason, message, part)
		local snapshot = saved()
		local result = B():Check(text)
		falsy(result.ok)
		eq(result.reason, reason)
		if part then eq(result.part, part) end
		eq(B().Message(result), message)
		local ok, why = B():Import(text)
		isNil(ok)
		eq(why, reason)
		eq(saved(), snapshot, "nothing changed")
	end

	it("refuses what is not a backup", function()
		local M = L()
		refused("", "foreign", M["BACKUP_FOREIGN"])
		refused("hello", "foreign", M["BACKUP_FOREIGN"])
		refused("AZACCORD1:XYZ:abcd", "foreign", M["BACKUP_FOREIGN"])
		refused("AZACCORD1:ABCDEF12:abcd", "foreign", M["BACKUP_FOREIGN"], nil)   -- the checksum is lower case
		refused("AZACCORD0:abcdef12:abcd", "foreign", M["BACKUP_FOREIGN"])
		refused("AZACCORD1:abcdef12:" .. ("A"):rep(262144), "foreign", M["BACKUP_FOREIGN"])
	end)

	it("refuses a newer format", function()
		refused(make(goodContent(), 2), "newer", L()["BACKUP_NEWER"])
		refused(make(goodContent(), 17), "newer", L()["BACKUP_NEWER"])
	end)

	it("refuses a text with one character changed, a truncated text and an undecodable body", function()
		fill()
		local text = B():Export()
		local at = 60
		local c = text:sub(at, at)
		local changed = text:sub(1, at - 1) .. (c == "A" and "B" or "A") .. text:sub(at + 1)
		refused(changed, "damaged", L()["BACKUP_DAMAGED"])
		refused(text:sub(1, #text - 12), "damaged", L()["BACKUP_DAMAGED"])
		refused(text:sub(1, 30), "damaged", L()["BACKUP_DAMAGED"])
		local body = A().Compat.Base64.Encode("\1not deflate at all")
		refused("AZACCORD1:" .. A().Hash.SHA256Hex(body):sub(1, 8) .. ":" .. body, "damaged", L()["BACKUP_DAMAGED"])
		local bad = goodContent()
		bad.v = 2
		refused(make(bad, 1), "damaged", L()["BACKUP_DAMAGED"], nil)
	end)

	it("refuses content Accord cannot use, naming the part", function()
		local M = L()
		local function unusable(mutate, part)
			local c = goodContent()
			mutate(c)
			refused(make(c), "unusable", M["BACKUP_UNUSABLE"]:format(M["BACKUP_PART_" .. part:upper()]), part)
		end
		unusable(function(c) c.account.token = "short" end, "token")
		unusable(function(c) c.account.chars = {} end, "characters")
		unusable(function(c) c.account.chars[GetNormalizedRealmName()]["not-a-guid"] = { name = "X" } end, "characters")
		unusable(function(c) c.account.chars[GetNormalizedRealmName()][ME].name = ("x"):rep(49) end, "characters")
		unusable(function(c) c.account.mains = { [GetNormalizedRealmName()] = BOB } end, "main")
		unusable(function(c) c.account.settings = { theme = "pink" } end, "settings")
		unusable(function(c) c.account.settings = { unknownKey = true } end, "settings")
		unusable(function(c) c.account.settings = { effects = "yes" } end, "settings")
		-- a record of another player, a record with a forged author, a record of a set that is never in a backup
		unusable(function(c) c.guilds["TestRealm/Accord"] = { contacts = { { id = BOB, author = BOB, rev = 1, time = 1, account = "x" } } } end, "records")
		unusable(function(c) c.guilds["TestRealm/Accord"] = { contacts = { { id = ME, author = BOB, rev = 1, time = 1, account = "x" } } } end, "records")
		unusable(function(c) c.guilds["TestRealm/Accord"] = { coplay = { { id = ME .. ":1", author = ME, rev = 1, time = 1 } } } end, "records")
		unusable(function(c) c.guilds["TestRealm/Accord"] = { recipes = { { id = ME .. ":171", author = ME, rev = 0, time = 1, char = ME, skillLine = 171 } } } end, "records")
		unusable(function(c) c.guilds["no slash"] = {} end, "records")
	end)

	it("refuses a backup of another account", function()
		-- this computer knows another character than the one logged in, which the backup does not list
		A().Accounts:Register{ guid = "Player-1-0000C001", name = "Mine", classID = 1, level = 10 }
		local c = goodContent()
		c.account.token = "QUJDREVGR0hJSktMTU5PUA=="
		refused(make(c), "account", L()["BACKUP_OTHER_ACCOUNT"])
		-- the same token is this account: accepted
		truthy(B():Check(make(goodContent())).ok)
	end)

	it("refuses an import with read-only data", function()
		A().Config.readOnly.account = true
		local snapshot = saved()
		eq(B():Check(make(goodContent())).reason, "read-only")
		eq(B().Message("read-only"), L()["BACKUP_READONLY"])
		eq(saved(), snapshot)
		A().Config.readOnly.account = nil
	end)
end)

describe("preview (SPEC-11 §4.5)", function()
	before_boot(function() guild() end)

	it("never restores a record with an older rev, and lists what changes", function()
		fill()
		local text = B():Export()
		-- this computer moves on: the own contacts and recipes get newer revisions, the theme changes
		truthy(A().Contacts:SetDiscord("newer_name"))
		truthy(S():Put("recipes", ME .. ":171", { char = ME, skillLine = 171, ids = { 1 } }))
		truthy(A().Config:Set("account.settings.theme", "accord"))
		local contactsRev = S():Get("contacts", ME).rev
		local result = B():Check(text)
		truthy(result.ok)
		local p = result.preview
		eq(p.token, "kept")
		eq(#p.added, 0)
		eq(p.present, 2)
		eq(#p.guilds, 1)
		eq(p.guilds[1].restore, 0)
		eq(p.guilds[1].keep, 4)
		local themeLine
		for _, s in ipairs(p.settings) do if s.key == "theme" then themeLine = s end end
		eq(themeLine.old, "accord")
		eq(themeLine.new, "aurora")
		local lines = table.concat(B().PreviewLines(p), "\n")
		contains(lines, "theme: accord -> aurora")
		contains(lines, "0 restored, 4 kept")
		B():Apply(result.content)
		-- the newer record was not replaced; the Discord name of the backup is a setting, so it is published again
		eq(S():Get("contacts", ME).rev, contactsRev + 1)
		eq(S():Get("contacts", ME).discord, "me_on_discord")
		eq(canon(S():Get("recipes", ME .. ":171").ids), canon({ 1 }))
		eq(A().Config:Get("account.settings.theme"), "aurora")
	end)

	it("says when the character logged in is not in the backup", function()
		local c = goodContent()
		local realm = GetNormalizedRealmName()
		c.account.chars = { [realm] = { [ALT] = { name = "Altchar", level = 40 } } }
		local result = B():Check(make(c))
		truthy(result.ok)
		eq(result.preview.selfMissing, "Testchar")
		B():Apply(result.content)
		notNil(A().Config.db.account.chars[realm][ME], "the character logged in stays")
		notNil(A().Config.db.account.chars[realm][ALT])
	end)
end)

describe("the Backup card and the box (SPEC-11 §4.3)", function()
	before_boot(function() guild() end)

	it("/accord backup opens the Settings page with the card; Export fills the box, selected", function()
		fill()
		Mock.Slash("/accord backup")
		local f = A().SettingsView.frame
		notNil(f)
		truthy(f.backupCard:IsShown())
		truthy(f.backupExport:IsEnabled())
		truthy(f.backupImport:IsEnabled())
		local text = A().BackupBox:OpenExport()
		notNil(text)
		eq(A().BackupBox.frame.edit:GetText(), text)
		eq(A().BackupBox:Step(), "export")
		eq(A().BackupBox.frame.warning:GetText(), L()["BACKUP_WARNING"])
		A().BackupBox:Hide()
		eq(A().BackupBox.frame.edit:GetText(), "", "nothing of the text stays after closing")
	end)

	it("Import: paste, Check, preview, Import", function()
		fill()
		local text = B():Export()
		local box = A().BackupBox
		box:OpenImport()
		eq(box:Step(), "paste")
		box.frame.edit:SetText("not a backup")
		box:Right()
		eq(box:Step(), "paste")
		eq(box.frame.status:GetText(), L()["BACKUP_FOREIGN"])
		box.frame.edit:SetText(text)
		box:Right()
		eq(box:Step(), "preview")
		contains(box.frame.edit:GetText(), L()["BACKUP_PV_TITLE"])
		box:Left()
		eq(box:Step(), "paste")
		eq(box.frame.edit:GetText(), text, "Cancel goes back with the text pasted")
		box:Right()
		box:Right()
		eq(box:Step(), "done")
		matches(box.frame.status:GetText(), "^Backup imported: %d+ characters, %d+ settings, %d+ records%.$")
		box:Hide()
	end)

	it("in demo mode the card says why there is no backup", function()
		Mock.Slash("/accord settings")
		Mock.Slash("/accord demo")
		local f = A().SettingsView.frame
		A().SettingsView:Refresh()
		falsy(f.backupExport:IsEnabled())
		falsy(f.backupImport:IsEnabled())
		eq(f.backupNote:GetText(), L()["BACKUP_NO_DEMO"])
		Mock.Slash("/accord demo")
	end)
end)

describe("Italian", function()
	before_boot(function(M) guild() M.player.locale = "itIT" end)

	it("speaks Italian in the refusals and the preview", function()
		eq(B().Message("damaged"), "Il backup è danneggiato o incompleto: copia di nuovo tutto il testo.")
		eq(B().Message("foreign"), "Questo non è un backup di Azeroth Accord.")
		eq(B().Message({ reason = "unusable", part = "settings" }),
			"Questo backup contiene dati che Accord non può usare (le impostazioni). Non è cambiato nulla.")
		local result = B():Check(make(goodContent()))
		truthy(result.ok)
		local lines = B().PreviewLines(result.preview)
		eq(lines[1], "Questo backup cambia:")
		eq(lines[2], "Token dell'account: resta")
	end)
end)

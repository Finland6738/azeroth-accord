-- The two interface languages (M6.2; ADR 0015): the English and the Italian tables have exactly the same keys, the same
-- placeholders in the same order, the same colour and link codes, nothing untranslated by accident, every key the code
-- reads exists, and an Italian client runs every view without a Lua error.

local function readSource(name)
	local text = Mock.ReadSource("AzerothAccord/Locale/" .. name)
	if not text then fail("Locale/" .. name .. " was not loaded") end
	return text
end

-- Runs a locale file against a stand-in for AceLocale and returns its plain table of strings.
local function loadLocale(name)
	local tbl = {}
	local env = { LibStub = function() return { NewLocale = function() return tbl end } end }
	local chunk = assert(loadstring(readSource(name), "@Locale/" .. name))
	setfenv(chunk, env)
	chunk("AzerothAccord")
	return tbl
end

local function keysOf(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- "%d of %d %s" -> { "%d", "%d", "%s" } in order (a literal %% is not a placeholder).
local function placeholders(s)
	local out = {}
	s = s:gsub("%%%%", "")
	for p in s:gmatch("%%[%-%+ #0]*%d*%.?%d*[sdfxXq]") do out[#out + 1] = p end
	return table.concat(out, " ")
end

local function codes(s)
	local out = {}
	for c in s:gmatch("|c%x%x%x%x%x%x%x%x") do out[#out + 1] = "|c" end
	for _ in s:gmatch("|r") do out[#out + 1] = "|r" end
	for _ in s:gmatch("|[THn]") do out[#out + 1] = "|x" end
	return table.concat(out, " ")
end

-- Strings that are the same in both languages on purpose: names, loanwords and bare numbers.
local SAME = {
	DIGEST_CHAT_LIKES_ONE = true, DIGEST_CHAT_LIKES = true,   -- "like" is the word in Italian too
	HANDBOOK_TPL_CHAT = true,   -- "chat" too
	TL_LINE = true, ONT_OTHER = true, TRI_NOTE_LINE = true, EXPORT_ROSTER = true, EXPORT_CSV = true, EXPORT_DISCORD = true,
	RECRUIT_DISCORD = true, RECRUIT_TANK_ONE = true, RECRUIT_HEALER_ONE = true,   -- "Discord", "tank", "healer" in Italian too
	MEN_TOPIC_PVP = true, MEN_MAIN = true, MEN_NEW_LINE = true,   -- M12.5
	SHOP_GUILD_ITEM = true, SHOP_TIMES = true, SHOP_PART = true, SHOP_PART_AGE = true, ORD_ITEM_OWNED = true,   -- M13.4: numbers only
	COL_BATTLETAG = true,   -- "BattleTag" is Blizzard's word in Italian too
	ADDONS_COL_NAME = true,   -- "Addon" in Italian too
	ADDON_TITLE = true, WINDOW_TITLE = true, VIEW_ROSTER = true, COL_ADDON = true, ONLINE = true, FILTER_ONLINE = true, CARD_MAIN = true, CARD_ALT = true,
	CONTACT_BT_SHORT = true, CONTACT_DISCORD_SHORT = true, CARD_BATTLETAG = true, CARD_DISCORD = true, SET_DATA_PART = true,
	RV_TITLE = true, REP_LIKE = true, SOC_HOURS = true, SOC_TOP_LINE = true, NEW_MINUTES = true, BANK_TAB_COUNT = true,
	THEME_NEBULA = true, THEME_AURORA = true, THEME_ACCORD = true,
	ABOUT_TAB = true, ABOUT_LINK_REPO = true, DEMO_STATUS = true, SET_BACKUP_TITLE = true,
	COL_OPS_ACCOUNT = true, OPS_GROUP = true,
	GRP_ROLE_T = true, GRP_ROLE_H = true, GRP_FIELD_TANKS = true, GRP_FIELD_HEALERS = true,
	GRP_KIND_PVP = true, GRP_KIND_FARM = true, GRP_ACT_CHOICE = true, GRP_MINUTES = true, GRP_HOURS = true, GRP_AUTO = true,
	EVENTS_CHOSEN = true, EVENTS_EVENT = true, EVENTS_NAME_ROLE = true, SHARE_EVENTS_LINE = true,   -- M10.5
	RH_PREVIEW_EVENT = true, RH_LIST_LINKED = true, EXPORT_COL_DISCORD = true,   -- M10.6
	LINEUP_CHOICE = true, LINEUP_PLACE_RAID = true, LINEUP_MARK_MS2 = true,   -- M10.7
	VIEW_SEASON = true, SEASON_FIELD_TANK = true, SEASON_COUNT = true, SEASON_ROLE_TANK = true, SEASON_ROLE_HEALER = true, SEASON_PICK = true, SEASON_MS1 = true, SEASON_MS2 = true, SEASON_OS = true, SHARE_SEASON_LINE = true,   -- M10.3
	VIEW_RAID = true, SOURCE_LOOT = true, SOURCE_ACCORD = true, SOURCE_FDCP = true, FDCP_STATUS = true, RAID_SEASON_LINE = true, RAID_MS1 = true, RAID_MS2 = true, RAID_OS = true, ROLE_TANK = true, ROLE_HEALER = true, ROLE_DAMAGER = true, RAID_LOOT = true, RULES_PRESET = true, RULES_COST = true, FDCP_PRESET_PATTO = true, CARD_FDCP = true,
	INTEG_ADDON = true, INTEG_KIND_LOOT = true, INTEG_VERSION_N = true,
	RALLY_KIND_PVP = true,   -- M10.9
	LOOT_SYSTEM_SOFTRES = true, LOOT_SYSTEM_COUNCIL = true, LOOT_SYSTEM_DKP = true, LOOT_URL_HINT = true,   -- M11.6
	ORD_ITEM = true, ORD_NOTE_OF = true, ORD_CHOICE_ONLINE = true,   -- M13.2: "2 × name", "name: text", "online"
}

describe("the two locale tables", function()
	it("have exactly the same keys", function()
		local en, it = loadLocale("enUS.lua"), loadLocale("itIT.lua")
		deepEq(keysOf(it), keysOf(en))
		truthy(#keysOf(en) > 300, "the table was really read")
	end)

	it("hold only non-empty strings under upper-case keys, with no stray space at the end", function()
		for _, name in ipairs({ "enUS.lua", "itIT.lua" }) do
			for k, v in pairs(loadLocale(name)) do
				matches(k, "^[A-Z][A-Z0-9_]*$", name .. " key")
				eq(type(v), "string", name .. " " .. k)
				truthy(v ~= "", name .. " " .. k .. " is empty")
				-- ASCII spaces only: %s follows the C locale, which may take the last byte of "à" for a space
				local last = v:byte(-1)
				falsy(last == 32 or (last >= 9 and last <= 13), name .. " " .. k .. " ends with a space")
			end
		end
	end)

	it("use the same placeholders in the same order in every string (a swapped %s and %d would raise at runtime)", function()
		local en, it = loadLocale("enUS.lua"), loadLocale("itIT.lua")
		for k, v in pairs(en) do eq(placeholders(it[k]), placeholders(v), "placeholders of " .. k) end
	end)

	it("use the same colour, texture and link codes", function()
		local en, it = loadLocale("enUS.lua"), loadLocale("itIT.lua")
		for k, v in pairs(en) do eq(codes(it[k]), codes(v), "codes of " .. k) end
	end)

	it("leave nothing untranslated by accident", function()
		local en, it = loadLocale("enUS.lua"), loadLocale("itIT.lua")
		for k, v in pairs(en) do
			if it[k] == v then truthy(SAME[k], k .. " is identical in both languages: translate it or list it as intended") end
		end
		for k in pairs(SAME) do truthy(en[k], "SAME lists a key that no longer exists: " .. k) end
	end)

	it("format with sample arguments in both languages", function()
		local en, it = loadLocale("enUS.lua"), loadLocale("itIT.lua")
		for _, tbl in ipairs({ en, it }) do
			for k, v in pairs(tbl) do
				local args = {}
				for p in v:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*([sdfxXq])") do args[#args + 1] = (p == "s" or p == "q") and "x" or 7 end
				local ok, err = pcall(string.format, v, unpack(args))
				truthy(ok, k .. " does not format: " .. tostring(err))
			end
		end
	end)
end)

describe("the keys the code reads", function()
	it("all exist in the English table (a missing one would show the key itself)", function()
		local en = loadLocale("enUS.lua")
		local seen, missing = 0, {}
		for _, name in ipairs(Mock.loadedFiles) do
			if name:find("^AzerothAccord/") and not name:find("/Libs/") and not name:find("/Locale/") then
				local source = Mock.ReadSource(name)
				if source then
					for key in source:gmatch('L%["([A-Z][A-Z0-9_]*)"%]') do
						seen = seen + 1
						if not en[key] then missing[#missing + 1] = name .. ": " .. key end
					end
				end
			end
		end
		truthy(seen > 200, "the sources were really scanned")
		deepEq(missing, {})
	end)

	it("every key of a family built from a value exists for each value", function()
		local en = loadLocale("enUS.lua")
		for _, kind in ipairs({ "WITHDRAW", "DEPOSIT", "DONATION" }) do
			truthy(en["BANKREQ_KIND_" .. kind], kind)
			truthy(en["BANKREQ_TIP_" .. kind], kind)
		end
		for _, action in ipairs({ "ACCEPT", "DECLINE", "WORKING", "READY", "HANDED", "RECEIVED", "CANCEL" }) do   -- M13.2
			truthy(en["ORD_DO_" .. action], action)
			truthy(en["ORD_ASK_" .. action], action)
		end
		for _, state in ipairs({ "REQUESTED", "ACCEPTED", "PROGRESS", "READY", "HANDED", "DELIVERED", "CANCELLED", "DECLINED",
			"EXPIRED", "LEFT" }) do truthy(en["ORD_ST_" .. state], state) end
		for _, step in ipairs({ "ACCEPTED", "DECLINED", "WORKING", "READY", "HANDED" }) do
			truthy(en["ORD_STEP_" .. step], step)
			truthy(en["ORD_NOTE_" .. step], step)
		end
		for _, status in ipairs({ "OPEN", "APPROVED", "REJECTED", "FULFILLED", "CANCELLED" }) do
			truthy(en["BANKREQ_STATUS_" .. status], status)
		end
		for _, status in ipairs({ "APPROVED", "REJECTED", "FULFILLED" }) do truthy(en["BANKNOTE_" .. status], status) end
		for _, mixing in ipairs({ "LOW", "MEDIUM", "HIGH" }) do truthy(en["MAP_MIXING_" .. mixing], mixing) end
		for _, k in ipairs({ "KIND", "ITEM", "COUNT", "AMOUNT", "LIMIT", "OTHER", "ACT", "GUILD" }) do truthy(en["BANKREQ_ERR_" .. k], k) end
		for _, k in ipairs({ "DEPOSIT", "WITHDRAW", "MOVE", "REPAIR", "WITHDRAWFORTAB", "BUYTAB" }) do truthy(en["BANKLOG_KIND_" .. k], k) end
		for _, id in ipairs(AzerothAccord.RosterModel.COLUMNS) do truthy(en[id.label], id.label) end
	end)
end)

describe("an Italian client", function()
	local ME, BOB = "Player-1-0000A001", "Player-1-00000B0B"

	before_boot(function(M)
		M.player.locale = "itIT"
		M.guild.Set{ name = "Accord", myRank = 1, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, professions = { { name = "Alchemy", rank = 285, max = 300 } } },
		} }
	end)

	it("shows the panel, every view and the member card in Italian without a Lua error", function()
		local A = AzerothAccord
		local text = function() return table.concat(Mock.PlainOutput(), "\n") end
		eq(GetLocale(), "itIT")
		for _, view in ipairs({ "actions", "roster", "professions", "reputation", "bank", "groups", "season", "events",
			"availability", "raid", "handbook", "addons", "settings" }) do
			truthy(A.Shell:OpenView(view), view)
			Mock.Advance(2)
		end
		eq(#Mock.errors, 0)
		local labels = {}
		for _, v in ipairs(A.Shell:ViewList()) do labels[#labels + 1] = v.label end
		deepEq(labels, { "Centro azioni", "Roster", "Professioni", "Reputazione", "Banca", "Gruppi", "Season", "Eventi",
			"Disponibilità", "Raid", "Manuale", "Addon della gilda", "Ufficiali", "Impostazioni" })
		A.Shell:OpenView("settings")
		eq(A.SettingsView.frame.title:GetText(), "Contatti condivisi con la gilda")
		eq(A.SettingsView.frame.mainTitle:GetText(), "Personaggio principale")
		eq(A.SettingsView.frame.clear.label and A.SettingsView.frame.clear.label:GetText() or A.SettingsView.frame.clear:GetText(),
			"Cancella i dati della gilda")
		Mock.Slash("/accord bogus")
		contains(text(), "Comando sconosciuto 'bogus'.")
	end)

	it("the Settings view saves and refuses a Discord name with Italian messages", function()
		local A = AzerothAccord
		A.Shell:OpenView("settings")
		local f = A.SettingsView.frame
		f.discordEdit:SetText("http://bad")
		f.save:Click()
		matches(f.status:GetText(), "^Nome utente Discord non valido")
		eq(#Mock.errors, 0)
	end)

	it("ages and counts use the Italian words", function()
		local A = AzerothAccord
		eq(A.Shell.Ago(30), "adesso")
		eq(A.Shell.Ago(120), "2 min fa")
		eq(A.Shell.Ago(7200), "2 h fa")
		eq(A.Shell.Ago(172800), "2 g fa")
	end)
end)

-- ShareModel: what this character publishes to the guild, set by set, as the records the client last sent (SPEC-11 §5,
-- M7.6). Pure Lua, no frame; UI/SharePanel.lua draws it. Lua 5.1.
-- The content comes from the records of the Store whose `author` is this character, the same ones the sync sends (every
-- local write goes out as REC) or keeps in the queue: it is read, never recomputed from the game.
--   ShareModel.Describe(at)   -> list of rows in ShareModel.ORDER, each { id, set, to, when, lines = { text, ... }, records,
--                                rev (the highest), updated (the newest `time`), age (text), switch = key | nil, on = bool | nil,
--                                note = text | nil }
--   ShareModel.Add(id, def)   another data set (M9.9, the addon list): def = { order, to, when, switch, build(me, at) ->
--                                lines, records, rev, updated, note }
--   ShareModel.SetSwitch(key, on)   the switch of a row ("shareCoplay"; "shareAddons", M9.9; "shareAvailability", M10.8)
-- A row with `feature` shows only while that switch of Core/Features.lua is on. A row with a switch may name its texts
-- (switchLabel, switchTip, offNote: locale keys); without them they are the co-play ones.
-- The other characters' own `accounts` rows are not shown as published by this one (SPEC-11 §5): the page says so.
local ADDON_NAME, ns = ...
ns = ns or {}
local L = ns.L
local Model = {}
ns.ShareModel, ns.modules = Model, ns.modules or {}
ns.modules.ShareModel = Model

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local sort, concat, max = table.sort, table.concat, math.max

Model.COPLAY_DAYS = 7           -- the days of co-play the panel lists
Model.REQUESTS = 5              -- the bank requests it lists
Model.ADDONS = 5                -- the addons it names

local function S() return ns.Store end
local function me() return ns.Compat and ns.Compat.Player.GUID() end
local function now() return ns.Compat and ns.Compat.ServerTime() or time() end

-- The records of `set` written by `guid`, in the order of their ids.
local function own(set, guid)
	local out = {}
	if not (S() and guid) then return out end
	for id, rec in pairs(S():Records(set)) do
		if type(rec) == "table" and rec.author == guid then
			out[#out + 1] = rec
		end
	end
	sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
	return out
end

local function summary(recs)
	local rev, updated = 0, nil
	for _, r in ipairs(recs) do
		rev = max(rev, r.rev or 0)
		if type(r.time) == "number" and (not updated or r.time > updated) then updated = r.time end
	end
	return rev, updated
end

local function className(classID)
	local R = ns.Roster
	local file = R and classID and R.ClassFile(classID)
	return file and R.ClassName(file) or nil
end

---------------------------------------------------------------------------------------------------------------------
-- The data sets
---------------------------------------------------------------------------------------------------------------------
local builders = {}

builders.accounts = function(guid, at)
	local rec = S():Get("accounts", guid)
	if not rec then return {}, {} end
	local lines = { L["SHARE_ACCOUNT_TOKEN"]:format(tostring(rec.token or ""):sub(1, 4) .. "…") }
	local mainName
	for _, c in ipairs(rec.chars or {}) do
		local where
		if c.inGuild then where = L["SHARE_IN_GUILD"]
		else where = ns.Provenance.AltGuildText({ guild = c.guild, seen = c.seen }, at) end
		local parts = { tostring(c.name or "?") }
		if c.realm then parts[1] = parts[1] .. "-" .. c.realm end
		local cls = className(c.classID)
		if cls then parts[#parts + 1] = cls end
		if c.level then parts[#parts + 1] = L["SHARE_LEVEL"]:format(c.level) end
		parts[#parts + 1] = where
		lines[#lines + 1] = concat(parts, " · ")
		if c.guid == rec.main then mainName = c.name end
	end
	if mainName then lines[#lines + 1] = L["SHARE_MAIN"]:format(mainName) end
	if rec.addonVersion then lines[#lines + 1] = L["SHARE_ADDON_VERSION"]:format(rec.addonVersion) end
	lines[#lines + 1] = L["SHARE_OTHER_CHARS"]
	return lines, { rec }
end

builders.contacts = function(guid)
	local rec = S():Get("contacts", guid)
	if not rec then return { L["SHARE_NOTHING_YET"] }, {} end
	return {
		L["SHARE_BATTLETAG"]:format(rec.battleTag or L["SHARE_NONE"]),
		L["SHARE_DISCORD"]:format(rec.discord or L["SHARE_NONE"]),
	}, { rec }
end

builders.recipes = function(guid)
	local recs, lines = own("recipes", guid), {}
	for _, r in ipairs(recs) do
		lines[#lines + 1] = L["SHARE_RECIPE_LINE"]:format(tostring(r.name or r.skillLine or "?"), r.rank or 0, r.maxRank or 0, r.n or 0)
	end
	if #lines == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	return lines, recs
end

builders.coplay = function(guid)
	local recs = own("coplay", guid)
	local days, order = {}, {}
	for _, r in ipairs(recs) do
		local d = days[r.day]
		if not d then d = { pairs = 0, minutes = 0 } days[r.day] = d order[#order + 1] = r.day end
		for _, minutes in pairs(r.pairs or {}) do
			d.pairs = d.pairs + 1
			d.minutes = d.minutes + (tonumber(minutes) or 0)
		end
	end
	sort(order, function(a, b) return a > b end)
	local lines = {}
	for i = 1, math.min(#order, Model.COPLAY_DAYS) do
		local day, d = order[i], days[order[i]]
		lines[#lines + 1] = L["SHARE_COPLAY_DAY"]:format(("%04d-%02d-%02d"):format(day / 10000, day / 100 % 100, day % 100), d.pairs, d.minutes)
	end
	if #lines == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	lines[#lines + 1] = L["SHARE_COPLAY_NAMES"]
	return lines, recs
end

builders.bank = function(guid)
	local recs, lines = own("bank", guid), {}
	for _, r in ipairs(recs) do
		if r.kind == "tab" then lines[#lines + 1] = L["SHARE_BANK_TAB"]:format(tostring(r.name or r.tab or "?"), r.n or 0)
		elseif r.kind == "money" then lines[#lines + 1] = L["SHARE_BANK_MONEY"]:format(math.floor((r.money or 0) / 10000))
		elseif r.kind == "log" then lines[#lines + 1] = L["SHARE_BANK_LOG"]:format(r.tab or 0, r.n or 0) end
	end
	if #lines == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	return lines, recs
end

builders.bankreq = function(guid)
	local mine = {}
	if S() then
		for id, rec in pairs(S():Records("bankreq")) do
			if type(rec) == "table" and rec.requester == guid then mine[#mine + 1] = rec end
		end
	end
	sort(mine, function(a, b) return (tonumber(tostring(a.id):match(":(%d+)$")) or 0) > (tonumber(tostring(b.id):match(":(%d+)$")) or 0) end)
	local lines, recs = {}, {}
	for i = 1, math.min(#mine, Model.REQUESTS) do
		local r = mine[i]
		recs[#recs + 1] = r
		local n, status = tostring(tostring(r.id):match(":(%d+)$") or "?"), tostring(r.status or "?")
		lines[#lines + 1] = type(r.tip) == "number" and L["SHARE_REQUEST_GIFT"]:format(n, status, math.floor(r.tip / 10000))
			or L["SHARE_REQUEST_LINE"]:format(n, status)
	end
	if #lines == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	return lines, recs
end

builders.likes = function()
	local n = ns.Likes and ns.Likes:GivenCount() or 0
	return { L["SHARE_LIKES_GIVEN"]:format(n) }, {}
end

builders.hello = function()
	local v = ns.Compat and ns.Compat.AddonVersion and ns.Compat.AddonVersion() or nil
	if not v and C_AddOns and C_AddOns.GetAddOnMetadata then v = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") end
	return { L["SHARE_HELLO_LINE"]:format(tostring(v or "?")) }, {}
end

builders.officer = function(guid)
	local ledger = 0
	for _, r in ipairs(own("likes", guid)) do ledger = ledger + 1 end
	local lines = { L["SHARE_OFFICER_LEDGER"]:format(ledger) }
	if not (ns.Store and ns.Store.IsActive("guildcfg")) then return lines, {} end
	local cfg = own("guildcfg", guid)
	lines[#lines + 1] = L["SHARE_OFFICER_CFG"]:format(#cfg)
	return lines, cfg
end

-- The officer tools (SPEC-12 §7): the roster changes this character observed, by month, and where they stay.
builders.otools = function(guid)
	local recs = own("timeline", guid)
	local months, order = {}, {}
	for _, r in ipairs(recs) do
		local month = math.floor((tonumber(r.day) or 0) / 100)
		if not months[month] then months[month] = 0 order[#order + 1] = month end
		months[month] = months[month] + (type(r.ev) == "table" and #r.ev or 0)
	end
	sort(order, function(a, b) return a > b end)
	local lines = {}
	for i = 1, math.min(#order, 3) do
		local m = order[i]
		lines[#lines + 1] = L["SHARE_TL_MONTH"]:format(("%04d-%02d"):format(math.floor(m / 100), m % 100), months[m])
	end
	-- the absences this officer set and the tiers it chose (M8.3)
	local set = {}
	for _, r in ipairs(own("absence", guid)) do
		if ns.Absence and ns.Absence.KindOf(r) == "off" then set[#set + 1] = r end
	end
	local cfg = own("ocfg", guid)
	if #set > 0 then lines[#lines + 1] = L["SHARE_ABSENCE_SET"]:format(#set) end
	-- the extended notes this officer wrote (M8.5): a count, never a text
	local notes = {}
	for _, r in ipairs(own("onotes", guid)) do if r.text ~= "" then notes[#notes + 1] = r end end
	if #notes > 0 then lines[#lines + 1] = L["SHARE_NOTES_WRITTEN"]:format(#notes) end
	-- the trials and trial notes this officer wrote (M12.3, SPEC-16 §8): counts, never a text
	local trials = {}
	if ns.Trials and ns.Trials.Enabled() then
		local nt, nn = 0, 0
		for _, r in ipairs(own("trials", guid)) do
			local kind = ns.Trials.KindOf(r)
			if kind == "T" then nt = nt + 1 trials[#trials + 1] = r
			elseif kind == "N" and r.text ~= "" then nn = nn + 1 trials[#trials + 1] = r end
		end
		if nt + nn > 0 then lines[#lines + 1] = L["SHARE_TRIALS_WRITTEN"]:format(nt, nn) end
	end
	for _, r in ipairs(cfg) do
		if ns.Inactivity and ns.Inactivity.ValidConfig(r) then
			lines[#lines + 1] = L["SHARE_TIERS"]:format(table.concat(r.tiers, " / "))
		end
	end
	for _, list in ipairs({ set, cfg, notes, trials }) do for _, r in ipairs(list) do recs[#recs + 1] = r end end
	if #lines == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	if not (ns.Officer and ns.Officer.ChannelProven()) then lines[#lines + 1] = L["SHARE_OTOOLS_LOCAL"] end
	return lines, recs
end

-- The declared absence of this character (SPEC-12 §7): only the return date, to the officers only.
builders.absence = function(guid)
	local lines, recs = {}, {}
	for _, r in ipairs(own("absence", guid)) do
		if ns.Absence and ns.Absence.KindOf(r) == "self" then
			recs[#recs + 1] = r
			lines[#lines + 1] = r["until"] == 0 and L["SHARE_ABSENCE_CLEARED"] or L["SHARE_ABSENCE_UNTIL"]:format(ns.Absence.DayText(r["until"]))
		end
	end
	if #lines == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	return lines, recs
end

-- id, locale keys of the title and of "who receives it / when", the builder, the switch key
Model.ORDER = {}
Model.DEFS = {}
local function define(id, def)
	def.id = id
	if not Model.DEFS[id] then Model.ORDER[#Model.ORDER + 1] = id end
	Model.DEFS[id] = def
end
-- The addon census (SPEC-13 §8.3): how many addons the own record lists and the first of them.
builders.addons = function(guid)
	local rec = S():Get("addons", guid)
	local lines, recs = {}, { rec }
	if not rec then
		lines[1] = L["SHARE_NOTHING_YET"]
	elseif rec.del == true then
		lines[1] = L["SHARE_ADDONS_WITHDRAWN"]
	else
		local names = {}
		for i = 1, math.min(#(rec.l or {}), Model.ADDONS) do names[i] = tostring(rec.l[i][3] or rec.l[i][1]) end
		local count = #(rec.l or {})
		lines[1] = L["SHARE_ADDONS_COUNT"]:format(count)
		if count > #names then lines[2] = L["SHARE_ADDONS_FIRST"]:format(concat(names, ", "), count - #names)
		else lines[2] = concat(names, ", ") end
		if rec.more then lines[#lines + 1] = L["SHARE_ADDONS_MORE"]:format(rec.more) end
	end
	lines[#lines + 1] = L["SHARE_ADDONS_NAMES"]
	return lines, recs
end

define("accounts", { set = "accounts", build = builders.accounts, title = "SHARE_ACCOUNTS", to = "SHARE_TO_GUILD", when = "SHARE_WHEN_LOGIN" })
define("contacts", { set = "contacts", build = builders.contacts, title = "SHARE_CONTACTS", to = "SHARE_TO_GUILD", when = "SHARE_WHEN_CHANGE", always = true })
define("recipes", { set = "recipes", build = builders.recipes, title = "SHARE_RECIPES", to = "SHARE_TO_GUILD", when = "SHARE_WHEN_PROFESSION" })
define("coplay", { set = "coplay", build = builders.coplay, title = "SHARE_COPLAY", to = "SHARE_TO_GUILD", when = "SHARE_WHEN_HOURLY", switch = "shareCoplay" })
define("bank", { set = "bank", build = builders.bank, title = "SHARE_BANK", to = "SHARE_TO_GUILD_OFFICERS", when = "SHARE_WHEN_BANK" })
define("bankreq", { set = "bankreq", build = builders.bankreq, title = "SHARE_BANKREQ", to = "SHARE_TO_GUILD", when = "SHARE_WHEN_REQUEST" })
define("likes", { build = builders.likes, title = "SHARE_LIKES", to = "SHARE_TO_NOTARY", when = "SHARE_WHEN_LIKE" })
define("hello", { build = builders.hello, title = "SHARE_HELLO", to = "SHARE_TO_GUILD", when = "SHARE_WHEN_HELLO" })
define("absence", { set = "absence", build = builders.absence, title = "SHARE_ABSENCE", to = "SHARE_TO_OFFICERS_ONLY", when = "SHARE_WHEN_ABSENCE" })
define("officer", { build = builders.officer, title = "SHARE_OFFICER", to = "SHARE_TO_OFFICERS", when = "SHARE_WHEN_OFFICER", officersOnly = true })
define("otools", { set = "timeline", build = builders.otools, title = "SHARE_OTOOLS", to = "SHARE_TO_OFFICER_CHANNEL", when = "SHARE_WHEN_OTOOLS", officersOnly = true })

-- Another data set (SPEC-11 §5): def = { build(guid, at) -> lines, records; title, to, when (locale keys); switch; order }.
function Model.Add(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	local fresh = Model.DEFS[id] == nil
	def.id = id
	Model.DEFS[id] = def
	if fresh then
		local at = tonumber(def.order) or #Model.ORDER + 1
		table.insert(Model.ORDER, math.min(math.max(1, at), #Model.ORDER + 1), id)
	end
	return true
end

local function switchOn(key)
	local M = ns.SettingsModel
	return M and M.Get(key) or false
end

function Model.Describe(at)
	at = at or now()
	local guid = me()
	local rows = {}
	if not (guid and S() and ns.GuildKey and ns.GuildKey:Current()) then return rows end
	for _, id in ipairs(Model.ORDER) do
		local def = Model.DEFS[id]
		local visible = (not def.officersOnly or (ns.Role ~= nil and ns.Role:IsOfficer()))
			and (def.feature == nil or (ns.Features ~= nil and ns.Features.On(def.feature)))
		if visible then
			local lines, recs = def.build(guid, at)
			local rev, updated = summary(recs or {})
			local row = { id = id, set = def.set, title = L[def.title], to = L[def.to], when = L[def.when], lines = lines or {},
				records = #(recs or {}), rev = rev, updated = updated, always = def.always }
			if updated then row.age = L["SHARE_UPDATED"]:format(ns.Provenance.AgeText(ns.Provenance.Age(updated, at))) end
			if def.switch then
				row.switch, row.on = def.switch, switchOn(def.switch)
				row.switchLabel = L[def.switchLabel or "SHARE_COPLAY_SWITCH"]
				row.switchTip = L[def.switchTip or "SHARE_COPLAY_SWITCH_TIP"]
				if not row.on then row.note = L[def.offNote or "SHARE_COPLAY_OFF_NOTE"] end
			end
			rows[#rows + 1] = row
		end
	end
	return rows
end

function Model.SetSwitch(key, on)
	local M = ns.SettingsModel
	if not (M and M.OPTION[key] and M.OPTION[key].group == "sharing") then return false, "unknown" end
	return M.Set(key, on)
end

-- the own season declarations (M10.3, SPEC-14 §4); an officer's seasons are under the officer's row of guild settings
builders.season = function(guid)
	local lines, recs = {}, {}
	for _, rec in ipairs(own("season", guid)) do
		if ns.Season and ns.Season.KindOf(rec) == "E" then
			recs[#recs + 1] = rec
			local s = ns.Season:Get(rec.n)
			local what = rec.unsure and L["SEASON_UNSURE"] or (ns.SeasonView and ns.SeasonView.PickText(rec.ms1)) or "?"
			lines[#lines + 1] = L["SHARE_SEASON_LINE"]:format(s and s.name or tostring(rec.n), what)
		end
	end
	if #recs == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	return lines, recs
end
Model.Add("season", { set = "season", feature = "season", build = builders.season, title = "SHARE_SEASON",
	to = "SHARE_TO_GUILD", when = "SHARE_WHEN_SEASON" })

-- the own roles and answers for events (M10.5, SPEC-14 §5.5) and, of an officer, the Raid-Helper events imported (M10.6,
-- §6.4) and the line-ups written (M10.7, §7.2); the answer to a calendar event is in the game calendar
builders.raidev = function(guid)
	local lines, recs = {}, {}
	for _, rec in ipairs(own("raidev", guid)) do
		local C = ns.Calendar
		local kind = C and C.KindOf(rec)
		if kind == "R" or kind == "A" then
			recs[#recs + 1] = rec
			local key = C.SplitCharId(rec.id)
			local e = C:Event(key)
			local f = not e and C.LocalIdOf(key) and ns.Store:Get(C.SET, C.LocalIdOf(key))
			local title = (e and e.title) or (f and f.title) or (ns.EventsView and ns.EventsView.WhenText(rec.at)) or "?"
			local what = L["SEASON_ROLE_" .. tostring(rec.role):upper()] or tostring(rec.role)
			if kind == "A" and ns.EventsView then what = ns.EventsView.AnswerText(rec.answer) .. ", " .. what end
			lines[#lines + 1] = L["SHARE_EVENTS_LINE"]:format(title, what)
		elseif kind == "H" and type(rec.s) == "table" then
			recs[#recs + 1] = rec
			lines[#lines + 1] = L["SHARE_EVENTS_LINE"]:format(rec.title or "?", L["SHARE_RH_LINE"]:format(#rec.s))
		elseif kind == "C" and type(rec.raid) == "table" and type(rec.bench) == "table" then
			recs[#recs + 1] = rec
			local e = C:Event(rec.id:sub(3))
			local title = (e and e.title) or (ns.EventsView and ns.EventsView.WhenText(rec.at)) or "?"
			lines[#lines + 1] = L["SHARE_EVENTS_LINE"]:format(title, L["SHARE_LINEUP_LINE"]:format(#rec.raid, #rec.bench))
		end
	end
	if #recs == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	return lines, recs
end
Model.Add("raidev", { set = "raidev", feature = "season", build = builders.raidev, title = "SHARE_EVENTS",
	to = "SHARE_TO_GUILD", when = "SHARE_WHEN_EVENTS" })

-- when this account usually plays (M10.8, SPEC-14 §8.3): the own record as it was last sent
builders.avail = function(guid)
	local rec = S():Get("avail", guid)
	local lines, recs = {}, { rec }
	if not rec then
		lines[1] = L["SHARE_NOTHING_YET"]
	elseif rec.del == true then
		lines[1] = L["SHARE_AVAIL_WITHDRAWN"]
	else
		local A = ns.Availability
		local usual, any = 0, 0
		for _, level in pairs(A and A.Decode(rec.p) or {}) do
			if level > 0 then any = any + 1 end
			if level >= A.USUAL then usual = usual + 1 end
		end
		lines[1] = L["SHARE_AVAIL_LINE"]:format(usual, any, rec.w or 0)
	end
	lines[#lines + 1] = L["SHARE_AVAIL_NAMES"]
	return lines, recs
end
Model.Add("avail", { set = "avail", feature = "season", build = builders.avail, title = "SHARE_AVAIL",
	to = "SHARE_TO_GUILD", when = "SHARE_WHEN_AVAIL", switch = "shareAvailability", switchLabel = "SHARE_AVAIL_SWITCH",
	switchTip = "SHARE_AVAIL_SWITCH_TIP", offNote = "SHARE_AVAIL_OFF_NOTE" })

-- the own rallies and answers (M10.9, SPEC-14 §9): short-lived, gone 10 minutes after the rally ends
builders.rally = function(guid)
	local lines, recs = {}, {}
	local R = ns.Rallies
	for _, rec in ipairs(own("rally", guid)) do
		local kind = R and R.KindOf(rec)
		if kind == "rally" then
			lines[#lines + 1] = L["SHARE_RALLY_CALL"]:format(L["RALLY_ROW_" .. rec.kind:upper()]:format(rec.text), R.Clock(rec.start),
				R.Clock(rec.ends)) .. (rec.closed and (" " .. L["SHARE_RALLY_CLOSED"]) or "")
			recs[#recs + 1] = rec
		elseif kind == "answer" then
			local _, id = R.KindOf(rec)
			local rally = S():Get("rally", id)
			lines[#lines + 1] = L["RALLY_MINE_" .. rec.answer:upper()] .. (rally and (" (" .. rally.text .. ")") or "")
			recs[#recs + 1] = rec
		end
	end
	if #recs == 0 then lines[1] = L["SHARE_NOTHING_YET"] end
	return lines, recs
end
Model.Add("rally", { set = "rally", feature = "season", build = builders.rally, title = "SHARE_RALLY",
	to = "SHARE_TO_GUILD", when = "SHARE_WHEN_RALLY" })

-- added after the sets above, under the recipes (SPEC-13 §8.3)
Model.Add("addons", { set = "addons", feature = "census", build = builders.addons, order = 4, title = "SHARE_ADDONS",
	to = "SHARE_TO_GUILD", when = "SHARE_WHEN_ADDONS", switch = "shareAddons", switchLabel = "SHARE_ADDONS_SWITCH",
	switchTip = "SHARE_ADDONS_SWITCH_TIP", offNote = "SHARE_ADDONS_OFF_NOTE" })

if ns.addon then ns.addon.ShareModel = Model end

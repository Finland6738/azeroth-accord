-- Export: the roster, the inactive accounts and the timeline as CSV or as text for Discord (SPEC-12 §6, M8.6). Lua 5.1.
-- Pure text: it reads what a page of the officer tools shows (the items) and writes columns; UI/ExportBox.lua shows it.
--
--   Export.Build(kind, format, items, t) -> text, { rows = rows in the text, left = rows left out } or nil, "officer" | "kind"
--     kind    "roster"    items: the roster entries the view shows (characters in the guild), in its order
--             "inactive"  items: the accounts of Inactivity:Rows
--             "timeline"  items: { { ev, name }, ... } of OfficersView.TimelineRows
--     format  "csv" | "discord"
--   Export.Display(text)  the text as the edit box takes it: "|" doubled (EXP-04)
--
-- EXP-01: no account token, no GUID, no guild key and no officer note (the game's or the extended ones) is ever read into a
-- row: every column is built from names, ranks, levels, times, tiers, absences, public notes and the timeline.
-- EXP-02, EXP-03: RFC 4180 with "," and "\n"; a text that starts like a formula gets an apostrophe in front.
-- EXP-05: Discord text is one code block per part of at most 1900 characters, columns aligned with spaces.
-- Limit: Export.MAX_TEXT bytes; whole rows only.
local ADDON_NAME, ns = ...
ns = ns or {}
local Export = {}
ns.Export, ns.modules = Export, ns.modules or {}
ns.modules.Export = Export

local type, ipairs, tostring = type, ipairs, tostring
local floor, max = math.floor, math.max
local concat = table.concat

Export.KINDS = { "roster", "inactive", "timeline" }
Export.FORMATS = { "csv", "discord" }
Export.MAX_TEXT = 262144       -- 256 KB, as the backup
Export.PART_MAX = 1900         -- characters of one Discord part (a message takes 2000)
Export.NAME_CUT, Export.NOTE_CUT = 24, 30

-- The CSV columns, fixed and not translated: a program reads them.
Export.CSV = {
	roster = { "name", "realm", "main", "class", "level", "rank", "last_seen_date", "days_inactive", "account_days_inactive",
		"tier", "away_until", "public_note", "has_addon" },
	inactive = { "main", "realm", "characters", "highest_rank", "days_inactive", "tier", "last_seen_date",
		"last_seen_character", "last_seen_source", "grouped_by_note", "away_until" },
	timeline = { "date_utc", "since_utc", "event", "name", "realm", "from", "to", "observers" },
}
local SOURCES = { native = "game", shared = "shared", own = "you" }

local DAY = 86400

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function dayText(t) return t and date("!%Y-%m-%d", t) or "" end
local function minuteText(t) return t and date("!%Y-%m-%d %H:%M", t) or "" end
local function yesNo(v) return v and "yes" or "no" end

---------------------------------------------------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------------------------------------------------
local function plainRealm(realm) return (realm:gsub("[%s%-']", "")):lower() end

-- The realm to write: "" for the player's own realm and when none is known.
function Export.Realm(realm)
	if type(realm) ~= "string" or realm == "" then return "" end
	local own = compat().Player.Realm()
	if own and plainRealm(own) == plainRealm(realm) then return "" end
	return realm
end

-- name, realm of a character: from its roster entry, else from the member of an account group, else from `fallback`
-- ("Name" or "Name-Realm"). Never a GUID: a character nothing names is "?".
local function nameRealm(guid, member, fallback)
	local entry = guid and ns.Roster and ns.Roster:ByGUID(guid)
	local name, realm
	if entry then
		name, realm = entry.short or entry.name, entry.realm
	else
		local full = (member and member.name) or fallback
		if type(full) == "string" then name, realm = compat().SplitName(full) end
		realm = realm or (member and member.realm)
	end
	return name or "?", Export.Realm(realm)
end

-- "Name" or "Name-Realm" for a column that has no realm column of its own.
local function fullName(guid, member)
	local name, realm = nameRealm(guid, member)
	return realm ~= "" and (name .. "-" .. realm) or name
end

local function memberOf(guid)
	local group = guid and ns.Accounts and ns.Accounts:GroupOf(guid)
	return group and group.byGUID[guid] or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Records: one table per row, with the CSV column names as keys (numbers stay numbers); `_` fields are for Discord only
---------------------------------------------------------------------------------------------------------------------
-- character GUID -> its account (Data/Inactivity.lua).
local function accountsByChar(t)
	local out = {}
	for _, a in ipairs(ns.Inactivity:Accounts(t)) do
		for _, guid in ipairs(a.chars) do out[guid] = a end
	end
	return out
end

local RECORDS = {}

function RECORDS.roster(entries, t)
	local byChar = accountsByChar(t)
	local out = {}
	for _, e in ipairs(entries) do
		if not e.notInGuild then
			local a = e.guid and byChar[e.guid]
			local name, realm = e.short or e.name or "?", Export.Realm(e.realm)
			local last = a and a.seen[e.guid]
			if not a then last = ns.Inactivity.LastSeen(e.guid, e, nil, nil, t) end
			local days = last and max(0, floor((t - last) / DAY)) or nil
			local main = e.guid and ns.Accounts and ns.Accounts:MainOf(e.guid)
			out[#out + 1] = {
				name = name, realm = realm,
				main = main and main.guid ~= e.guid and fullName(main.guid, main) or "",
				class = e.classFile or "", level = e.level or "", rank = e.rankName or "",
				last_seen_date = dayText(last), days_inactive = days or "",
				account_days_inactive = a and a.days or "", tier = a and a.tier or "",
				away_until = a and a.away and ns.Absence.DayText(a.absence.day) or "",
				public_note = e.note or "", has_addon = yesNo(e.hasAddon),
				_classFile = e.classFile,
			}
		end
	end
	return out
end

function RECORDS.inactive(accounts)
	local out = {}
	for _, a in ipairs(accounts) do
		local main, realm = nameRealm(a.main.guid, memberOf(a.main.guid), a.name)
		local chars = {}
		for i, guid in ipairs(a.chars) do chars[i] = fullName(guid, memberOf(guid)) end
		out[#out + 1] = {
			main = main, realm = realm, characters = concat(chars, "; "), highest_rank = a.rankName or "",
			days_inactive = a.days or "", tier = a.tier or "", last_seen_date = dayText(a.last),
			last_seen_character = a.lastGUID and fullName(a.lastGUID, memberOf(a.lastGUID)) or "",
			last_seen_source = a.lastSource and SOURCES[a.lastSource] or "", grouped_by_note = yesNo(a.byNote),
			away_until = a.away and ns.Absence.DayText(a.absence.day) or "",
			_chars = #a.chars, _tier = a.tier, _unknown = a.unknown,
		}
	end
	return out
end

function RECORDS.timeline(rows)
	local out = {}
	for _, r in ipairs(rows) do
		local ev = r.ev
		local name, realm = nameRealm(ev.g, nil, ev.n)
		local from, to = "", ""
		if ev.k == "rank" then from, to = ev.fn or tostring(ev.f), ev.tn or tostring(ev.t)
		elseif ev.k == "level" then from, to = ev.f, ev.t
		elseif ev.k == "note" then from, to = ev.f or "", ev.t or "" end
		out[#out + 1] = {
			date_utc = minuteText(ev.b), since_utc = minuteText(ev.a), event = ev.k, name = name, realm = realm,
			from = from, to = to, observers = #(ev.observers or {}), _ev = ev,
		}
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- CSV (§6.3)
---------------------------------------------------------------------------------------------------------------------
-- One value as it stands in the file: a number as it is; a text that a spreadsheet would read as a formula with an
-- apostrophe in front (EXP-03), then quoted when it needs to be (EXP-02).
function Export.CSVValue(v)
	if type(v) == "number" then return tostring(v) end
	v = tostring(v or "")
	if v:find("^[=+%-@\t\r]") then v = "'" .. v end
	if v:find('[,"\r\n]') or v:find("^[ \t]") or v:find("[ \t]$") then v = '"' .. v:gsub('"', '""') .. '"' end
	return v
end

local function csvText(kind, records)
	local columns = Export.CSV[kind]
	local lines = { concat(columns, ",") }
	local size = #lines[1]
	for _, record in ipairs(records) do
		local cells = {}
		for i, column in ipairs(columns) do cells[i] = Export.CSVValue(record[column]) end
		local line = concat(cells, ",")
		if size + 1 + #line > Export.MAX_TEXT then break end
		lines[#lines + 1] = line
		size = size + 1 + #line
	end
	return concat(lines, "\n"), #lines - 1
end

---------------------------------------------------------------------------------------------------------------------
-- Discord (§6.4)
---------------------------------------------------------------------------------------------------------------------
-- The number of characters of a UTF-8 text.
function Export.Length(text)
	local _, n = text:gsub("[^\128-\191]", "")
	return n
end

-- A value inside the code block: one line, no backtick (it would close the block), cut to `limit` characters with "…".
function Export.DiscordValue(v, limit)
	v = tostring(v or ""):gsub("[\r\n\t]", " "):gsub("%c", ""):gsub("`", "'")
	if limit and Export.Length(v) > limit then
		local count = 0
		for i = 1, #v do
			local b = v:byte(i)
			if b < 128 or b >= 192 then
				count = count + 1
				if count == limit then return v:sub(1, i - 1) .. "…" end
			end
		end
	end
	return v
end
local value = Export.DiscordValue

local function eventText(record)
	local L, ev = ns.L, record._ev
	if ev.k == "join" then return L["TL_JOINED"] end
	if ev.k == "leave" then return L["TL_LEFT"] end
	if ev.k == "level" then return L["TL_LEVEL"]:format(ev.f, ev.t) end
	if ev.k == "rank" then return L["TL_RANK"]:format(value(record.from), value(record.to)) end
	return L["TL_NOTE"]:format(value(record.from, Export.NOTE_CUT), value(record.to, Export.NOTE_CUT))
end

local function name(v) return value(v, Export.NAME_CUT) end

-- kind -> { { heading key, record -> cell }, ... }
local DISCORD = {
	roster = {
		{ "COL_NAME", function(r) return name(r.name) end },
		{ "EXPORT_COL_LEVEL", function(r) return r.level end },
		{ "COL_CLASS", function(r) return r._classFile and ns.Roster.ClassName(r._classFile) or "" end },
		{ "COL_RANK", function(r) return r.rank end },
		{ "COL_INA_LAST", function(r) return r.last_seen_date end },
		{ "COL_INA_DAYS", function(r) return r.days_inactive end },
	},
	inactive = {
		{ "COL_INA_MAIN", function(r) return name(r.main) end },
		{ "COL_INA_CHARS", function(r) return r._chars end },
		{ "COL_INA_RANK", function(r) return r.highest_rank end },
		{ "COL_INA_DAYS", function(r) return r.days_inactive end },
		{ "COL_INA_TIER", function(r)
			-- as on the page: an account away has no tier
			if r.away_until ~= "" then return "" end
			return ns.OfficersView.TierText(r._tier)
		end },
		{ "COL_INA_LAST", function(r) return r.last_seen_date end },
		{ "COL_INA_AWAY", function(r) return r.away_until end },
	},
	timeline = {
		{ "EXPORT_COL_DATE", function(r) return ns.Timeline.WhenText(r._ev) end },
		{ "COL_TL_NAME", function(r) return name(r.name) end },
		{ "COL_TL_EVENT", eventText },
	},
}

local function pad(text, width) return text .. (" "):rep(width - Export.Length(text)) end

local function discordText(kind, records, t)
	local L, columns = ns.L, DISCORD[kind]
	local head, widths = {}, {}
	for i, column in ipairs(columns) do
		head[i] = value(L[column[1]])
		widths[i] = Export.Length(head[i])
	end
	local rows = {}
	for n, record in ipairs(records) do
		local cells = {}
		for i, column in ipairs(columns) do
			cells[i] = value(column[2](record))
			widths[i] = max(widths[i], Export.Length(cells[i]))
		end
		rows[n] = cells
	end
	local function line(cells)
		local out = {}
		for i = 1, #columns do out[i] = i < #columns and pad(cells[i], widths[i]) or cells[i] end
		return (concat(out, "  "):gsub(" +$", ""))
	end
	local title = ("%s · %s · %s"):format(L["EXPORT_" .. kind:upper()], value(compat().Guild.GuildName() or "?"), dayText(t))
	local header = line(head)
	-- what every part holds besides its rows, with room for the " (999/999)" of the title
	local frameChars = Export.Length(title) + 10 + Export.Length(header) + #"```\n\n\n```"
	local frameBytes = #title + 10 + #header + #"```\n\n\n```" + 2   -- 2: the empty line between two parts
	local parts, current, chars = {}, nil, 0
	local bytes, taken = frameBytes, 0
	for _, cells in ipairs(rows) do
		local text = line(cells)
		local length = Export.Length(text)
		local fresh = not current or chars + 1 + length > Export.PART_MAX
		local added = #text + 1 + ((fresh and current) and frameBytes or 0)
		if bytes + added > Export.MAX_TEXT then break end
		if fresh then
			current, chars = {}, frameChars
			parts[#parts + 1] = current
		end
		current[#current + 1] = text
		chars, bytes, taken = chars + 1 + length, bytes + added, taken + 1
	end
	if #parts == 0 then parts[1] = {} end
	local out = {}
	for i, part in ipairs(parts) do
		local block = { "```", #parts > 1 and ("%s (%d/%d)"):format(title, i, #parts) or title, header }
		for _, text in ipairs(part) do block[#block + 1] = text end
		block[#block + 1] = "```"
		out[i] = concat(block, "\n")
	end
	return concat(out, "\n\n"), taken
end

---------------------------------------------------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------------------------------------------------
-- Officers and the Guild Master only (SPEC-10 Q13).
function Export.Allowed()
	return ns.Officer ~= nil and ns.Officer.CanSee("export") == true
end

function Export.Build(kind, format, items, t)
	if not Export.Allowed() then return nil, "officer" end
	if not RECORDS[kind] or (format ~= "csv" and format ~= "discord") then return nil, "kind" end
	t = t or now()
	local records = RECORDS[kind](items or {}, t)
	local text, taken
	if format == "csv" then text, taken = csvText(kind, records)
	else text, taken = discordText(kind, records, t) end
	return text, { rows = taken, left = #records - taken }
end

function Export.Display(text)
	return (text:gsub("|", "||"))
end

if ns.addon then ns.addon.Export = Export end

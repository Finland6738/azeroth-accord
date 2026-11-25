-- RaidHelperText: the reader of a pasted Raid-Helper export (M10.6; SPEC-14 §6.1). Lua 5.1.
--
-- Pure text in, a plain table out. Nothing of the text is ever run: no loadstring, no load, the JSON and the CSV are read
-- here character by character. What it does not understand it refuses with a reason; what it does not know it ignores.
--
--   Text.Parse(text) -> event, or nil and a reason
--     reason  "empty" nothing pasted, "long" more than Text.MAX_TEXT bytes, "deep" JSON nested deeper than
--             Text.MAX_DEPTH, "broken" JSON or CSV cut or malformed, "unknown" not a Raid-Helper event export,
--             "many" more than Text.MAX_SIGNUPS sign-ups
--     event   { format = "json" | "csv", id? (the Discord event id, digits), title?, start? (JSON: Unix seconds, UTC),
--               ignored = rows without a name, signups = { { name, state, class?, classes?, spec?, role?, primary, order } } }
--             name     the name shown on the Discord server, cleaned: no control character, at most Text.FIELD_MAX
--                      characters, "|" doubled
--             state    "signed" | "late" | "bench" | "tentative" | "absence"
--             class    classFile ("WARRIOR") when the export names it; classes: the classes that can have the spec when the
--                      export names only the spec (a "Tank" or "Tentative" row), as a set
--             spec     a key of Data/Specs.lua; role: "tank" | "healer" | "melee" | "ranged"
--             primary  false for a "secondary" sign-up: the primary one of the same person counts first
--
-- The formats follow Raid-Helper's public API v4 (GET /api/v4/events/<id>) and its CSV export, read by the header. The
-- fields of a sign-up are not in Raid-Helper's public documentation [verify with a real export, SPEC-14 §13].
local ADDON_NAME, ns = ...
ns = ns or {}
local Text = {}
ns.RaidHelperText, ns.modules = Text, ns.modules or {}
ns.modules.RaidHelperText = Text

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, concat, sort = math.floor, table.concat, table.sort
local char = string.char

Text.MAX_TEXT = 204800     -- bytes (200 KB)
Text.MAX_DEPTH = 8         -- JSON objects and arrays inside each other
Text.MAX_SIGNUPS = 200
Text.FIELD_MAX = 64        -- characters of one text
Text.STATES = { "signed", "late", "bench", "tentative", "absence" }

---------------------------------------------------------------------------------------------------------------------
-- Cleaning
---------------------------------------------------------------------------------------------------------------------
-- A text of the export made safe to keep and show: control characters out, the spaces at the ends too, at most
-- FIELD_MAX characters (never half a UTF-8 character), "|" doubled. nil for no text.
function Text.Clean(s)
	if type(s) == "number" then s = tostring(s) end
	if type(s) ~= "string" then return nil end
	s = s:gsub("[%z\1-\31\127]", " "):gsub("^ +", ""):gsub(" +$", "")
	local n, i = 0, 1
	while i <= #s do
		local b = s:byte(i)
		local size = b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1
		n = n + 1
		if n > Text.FIELD_MAX then
			s = s:sub(1, i - 1):gsub(" +$", "")
			break
		end
		i = i + size
	end
	if s == "" then return nil end
	return (s:gsub("|", "||"))
end

---------------------------------------------------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------------------------------------------------
local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\8", f = "\12", n = "\n", r = "\r", t = "\t" }

local function utf8Char(code)
	if code < 128 then return char(code) end
	if code < 2048 then return char(192 + floor(code / 64), 128 + code % 64) end
	if code < 65536 then return char(224 + floor(code / 4096), 128 + floor(code / 64) % 64, 128 + code % 64) end
	return char(240 + floor(code / 262144), 128 + floor(code / 4096) % 64, 128 + floor(code / 64) % 64, 128 + code % 64)
end

local function fail(why) error({ why = why }, 0) end

local function skip(s, i)
	return s:find("[^ \t\r\n]", i) or (#s + 1)
end

local function hex4(s, i)
	local h = s:sub(i, i + 3)
	if not h:find("^%x%x%x%x$") then fail("broken") end
	return tonumber(h, 16)
end

local function readString(s, i)                 -- s:sub(i, i) is the opening quote
	local parts = {}
	i = i + 1
	while true do
		local j = s:find('[%z\1-\31\\"]', i)
		if not j then fail("broken") end
		if j > i then parts[#parts + 1] = s:sub(i, j - 1) end
		local c = s:sub(j, j)
		if c == '"' then return concat(parts), j + 1 end
		if c ~= "\\" then fail("broken") end
		local e = s:sub(j + 1, j + 1)
		if e == "u" then
			local code = hex4(s, j + 2)
			i = j + 6
			if code >= 55296 and code < 56320 then                   -- a high surrogate needs its low one
				if s:sub(i, i + 1) ~= "\\u" then fail("broken") end
				local low = hex4(s, i + 2)
				if low < 56320 or low > 57343 then fail("broken") end
				code = 65536 + (code - 55296) * 1024 + (low - 56320)
				i = i + 6
			end
			parts[#parts + 1] = utf8Char(code)
		elseif ESCAPES[e] then
			parts[#parts + 1] = ESCAPES[e]
			i = j + 2
		else
			fail("broken")
		end
	end
end

local readValue

local function readObject(s, i, depth)
	if depth > Text.MAX_DEPTH then fail("deep") end
	local out = {}
	i = skip(s, i + 1)
	if s:sub(i, i) == "}" then return out, i + 1 end
	while true do
		if s:sub(i, i) ~= '"' then fail("broken") end
		local key
		key, i = readString(s, i)
		i = skip(s, i)
		if s:sub(i, i) ~= ":" then fail("broken") end
		out[key], i = readValue(s, skip(s, i + 1), depth)
		i = skip(s, i)
		local c = s:sub(i, i)
		if c == "}" then return out, i + 1 end
		if c ~= "," then fail("broken") end
		i = skip(s, i + 1)
	end
end

local function readArray(s, i, depth)
	if depth > Text.MAX_DEPTH then fail("deep") end
	local out, n = {}, 0
	i = skip(s, i + 1)
	if s:sub(i, i) == "]" then return out, i + 1 end
	while true do
		local v
		v, i = readValue(s, i, depth)
		if v ~= nil then
			n = n + 1
			out[n] = v
		end
		i = skip(s, i)
		local c = s:sub(i, i)
		if c == "]" then return out, i + 1 end
		if c ~= "," then fail("broken") end
		i = skip(s, i + 1)
	end
end

local WORDS = { ["true"] = true, ["false"] = false }

function readValue(s, i, depth)
	local c = s:sub(i, i)
	if c == "{" then return readObject(s, i, depth + 1) end
	if c == "[" then return readArray(s, i, depth + 1) end
	if c == '"' then return readString(s, i) end
	local word = s:match("^%a+", i)
	if word then
		if word == "null" then return nil, i + 4 end
		if WORDS[word] ~= nil then return WORDS[word], i + #word end
		fail("broken")
	end
	local text = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
	local number = text and tonumber(text)
	if not number then fail("broken") end
	return number, i + #text
end

-- The value of a JSON text, or nil and a reason ("broken", "deep").
function Text.JSON(s)
	local ok, value = pcall(function()
		local v, i = readValue(s, skip(s, 1), 0)
		if skip(s, i) <= #s then fail("broken") end
		return v
	end)
	if ok then return value end
	return nil, type(value) == "table" and value.why or "broken"
end

---------------------------------------------------------------------------------------------------------------------
-- CSV
---------------------------------------------------------------------------------------------------------------------
-- The rows of a CSV text (RFC 4180: quotes doubled inside a quoted value) with the delimiter `sep`, or nil when a quote
-- is not closed or something follows a closing one.
function Text.CSV(s, sep)
	local rows, row, i, n = {}, {}, 1, #s
	local plain = "[" .. (sep == "\t" and "\t" or sep) .. "\n]"
	while i <= n do
		local cell
		if s:sub(i, i) == '"' then
			local parts = {}
			i = i + 1
			while true do
				local j = s:find('"', i, true)
				if not j then return nil end
				parts[#parts + 1] = s:sub(i, j - 1)
				if s:sub(j + 1, j + 1) == '"' then
					parts[#parts + 1] = '"'
					i = j + 2
				else
					i = j + 1
					break
				end
			end
			cell = concat(parts)
			local c = s:sub(i, i)
			if c ~= "" and c ~= sep and c ~= "\n" then return nil end
		else
			local j = s:find(plain, i) or (n + 1)
			cell = s:sub(i, j - 1)
			i = j
		end
		row[#row + 1] = cell
		local c = s:sub(i, i)
		if c == sep then
			i = i + 1
			if i > n then row[#row + 1] = "" end
		else
			rows[#rows + 1] = row
			row = {}
			i = i + 1
		end
	end
	if #row > 0 then rows[#rows + 1] = row end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Class, spec, role and state
---------------------------------------------------------------------------------------------------------------------
-- A word of the export as the tables below know it: lower case, letters only ("Beast Mastery", "Protection1").
local function word(s)
	if type(s) ~= "string" then return "" end
	return (s:lower():gsub("[^%a]", ""))
end

local STATE_OF_CLASS = { late = "late", bench = "bench", benched = "bench", tentative = "tentative", absence = "absence",
	absent = "absence" }
local STATE_OF_STATUS = { late = "late", bench = "bench", benched = "bench", queued = "bench", tentative = "tentative",
	absence = "absence", absent = "absence", declined = "absence" }
local ROLES = { tank = "tank", tanks = "tank", healer = "healer", healers = "healer", heal = "healer", melee = "melee",
	meleedps = "melee", ranged = "ranged", rangeddps = "ranged", range = "ranged", caster = "ranged" }
-- names of a spec that Data/Specs.lua writes another way: word -> { key, role? }
local SPEC_WORDS = { beastmastery = { "BEAST_MASTERY" }, feralcombat = { "FERAL" }, guardian = { "FERAL", "tank" } }

-- The spec key, and the role the name itself says, of a spec of the export; nil for one Data/Specs.lua does not know.
function Text.Spec(name)
	local w = word(name)
	if w == "" then return nil end
	local alias = SPEC_WORDS[w]
	if alias then return alias[1], alias[2] end
	for _, list in pairs(ns.Specs.CLASSES) do
		for _, row in ipairs(list) do
			if word(row[1]) == w then return row[1] end
		end
	end
	return nil
end

-- The classFile of a class name of the export, or nil ("Tank", "Tentative" and the classes the base game has not).
function Text.Class(name)
	local w = word(name):upper()
	return ns.Specs.CLASSES[w] and w or nil
end

-- The classes of Data/Specs.lua that have the tree `spec`: { WARRIOR = true, ... }.
local function classesWith(spec)
	local out, any = {}, false
	for classFile in pairs(ns.Specs.CLASSES) do
		if ns.Specs.Roles(classFile, spec) then out[classFile] = true any = true end
	end
	return any and out or nil
end

-- One sign-up from the words of the export: { class, spec, role, state } as texts or nil.
function Text.Signup(name, className, specName, roleName, status)
	local clean = Text.Clean(name)
	if not clean then return nil end
	local classWord, statusWord = word(className), word(status)
	local e = { name = clean, primary = statusWord ~= "secondary" }
	e.state = STATE_OF_CLASS[classWord] or STATE_OF_STATUS[statusWord] or "signed"
	e.class = Text.Class(className)
	local spec, specRole = Text.Spec(specName)
	if spec and e.class and not ns.Specs.Roles(e.class, spec) then spec, specRole = nil, nil end
	e.spec = spec
	if not e.class and spec then e.classes = classesWith(spec) end
	e.role = ROLES[word(roleName)] or specRole or ROLES[classWord]
	if not e.role and e.class and spec then
		local roles = ns.Specs.Roles(e.class, spec)
		e.role = roles and roles[1] or nil
	end
	return e
end

---------------------------------------------------------------------------------------------------------------------
-- The event
---------------------------------------------------------------------------------------------------------------------
local function firstText(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "string" and v ~= "" then return v end
	end
	return nil
end

-- Primary sign-ups first, then Raid-Helper's position, then the order in the text.
local function ordered(list)
	sort(list, function(a, b)
		if a.primary ~= b.primary then return a.primary end
		if a.position ~= b.position then return a.position < b.position end
		return a.order < b.order
	end)
	for i, e in ipairs(list) do e.order, e.position = i, nil end
	return list
end

local function fromJSON(text)
	local data, why = Text.JSON(text)
	if data == nil then return nil, why or "unknown" end
	if type(data) ~= "table" or type(data.signUps) ~= "table" or type(data.title) ~= "string" then return nil, "unknown" end
	local rows = data.signUps
	if next(rows) ~= nil and rows[1] == nil then return nil, "unknown" end   -- an object where the list should be
	if #rows > Text.MAX_SIGNUPS then return nil, "many" end
	local ev = { format = "json", title = Text.Clean(data.title), signups = {}, ignored = 0 }
	if type(data.id) == "string" and data.id:find("^%d+$") and #data.id <= 24 then ev.id = data.id end
	local start = tonumber(data.startTime)
	if start and start > 100000000000 then start = floor(start / 1000) end    -- milliseconds
	if start and start > 1000000000 and start < 4000000000 then ev.start = floor(start) end
	for i, row in ipairs(rows) do
		local e
		if type(row) == "table" then
			e = Text.Signup(row.name, firstText(row.className, row.class), firstText(row.specName, row.spec),
				firstText(row.roleName, row.role), row.status)
		end
		if e then
			e.order, e.position = i, tonumber(row.position) or i
			ev.signups[#ev.signups + 1] = e
		else
			ev.ignored = ev.ignored + 1
		end
	end
	if #rows > 0 and #ev.signups == 0 then return nil, "unknown" end
	ordered(ev.signups)
	return ev
end

-- header word -> column
local COLUMNS = { name = "name", discordname = "name", user = "name", username = "name", class = "class",
	classname = "class", spec = "spec", specname = "spec", specialization = "spec", role = "role", rolename = "role",
	status = "status", state = "status", signupstatus = "status" }

local function fromCSV(text)
	local header = text:match("^[^\n]*")
	local sep, best = ",", 0
	for _, candidate in ipairs({ ",", ";", "\t" }) do
		local _, count = header:gsub(candidate, "")
		if count > best then sep, best = candidate, count end
	end
	if best == 0 then return nil, "unknown" end
	-- the header first: a text that is no table at all is "unknown", not a broken one
	local first = Text.CSV(header, sep)
	if not first or not first[1] then return nil, "unknown" end
	local columns = {}
	for i, cell in ipairs(first[1]) do
		local column = COLUMNS[word(cell)]
		if column and not columns[column] then columns[column] = i end
	end
	if not columns.name or not (columns.class or columns.role or columns.status) then return nil, "unknown" end
	local rows = Text.CSV(text, sep)
	if not rows then return nil, "broken" end
	local width = #rows[1]
	local ev = { format = "csv", signups = {}, ignored = 0 }
	local function cell(row, column)
		local i = columns[column]
		return i and row[i] or nil
	end
	for r = 2, #rows do
		local row = rows[r]
		local empty = true
		for i, value in ipairs(row) do
			if value:find("%S") then
				empty = false
				if i > width then return nil, "broken" end
			end
		end
		if not empty then
			local e = Text.Signup(cell(row, "name"), cell(row, "class"), cell(row, "spec"), cell(row, "role"), cell(row, "status"))
			if e then
				if #ev.signups >= Text.MAX_SIGNUPS then return nil, "many" end
				e.order, e.position = r, r
				ev.signups[#ev.signups + 1] = e
			else
				ev.ignored = ev.ignored + 1
			end
		end
	end
	if #ev.signups == 0 then return nil, "unknown" end
	ordered(ev.signups)
	return ev
end

function Text.Parse(text)
	if type(text) ~= "string" then return nil, "empty" end
	if #text > Text.MAX_TEXT then return nil, "long" end
	-- the game's edit box may give a pasted "|" doubled; a byte order mark may come with a saved file
	text = text:gsub("||", "|"):gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil, "empty" end
	if text:find("%z") then return nil, "broken" end
	local first = text:sub(1, 1)
	if first == "{" then return fromJSON(text) end
	if first == "[" or first == "<" then return nil, "unknown" end
	return fromCSV(text)
end

if ns.addon then ns.addon.RaidHelperText = Text end

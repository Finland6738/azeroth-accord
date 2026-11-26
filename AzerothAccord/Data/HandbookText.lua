-- HandbookText: the text format of the guild handbook (M11.3, SPEC-15 §4). Lua 5.1, no frames, no data of its own.
--
-- Format     a plain text read line by line: "# " and "## " headings, "- " / "* " bullets (two spaces before the mark: the
--            second level), "1. " numbered items, an empty line ends a paragraph, other consecutive lines join.
-- Links      [[slug]], [[slug#heading]], each with an optional own text after "¦" (U+00A6): the writer types "|", which a
--            saved text never keeps (SPEC-15 §4.1), so Clean writes it as "¦". [[season]] and [[loot]] are special.
--            A web address stays text; the reader makes it clickable to copy it.
-- Clean      every text that comes in goes through HandbookText.Clean: no game codes, no `|`, no control characters.
-- HTML       HandbookText.HTML(block, resolve) is what one block of the reader shows in a SimpleHTML: the writer's text is
--            escaped, so no tag of the writer reaches the game; the only markup is ours.
-- Search     HandbookText.Search(query, pages): at least 2 characters, no case and no accents, titles and lines.
local ADDON_NAME, ns = ...
ns = ns or {}
local Text = {}
ns.HandbookText, ns.modules = Text, ns.modules or {}
ns.modules.HandbookText = Text

local type, ipairs, floor, concat, tostring = type, ipairs, math.floor, table.concat, tostring

Text.SEPARATOR = "\194\166"       -- "¦", between a link's target and its own text
Text.SEARCH_MIN = 2               -- characters of a search
Text.SEARCH_MAX = 50              -- results of a search
Text.BULLET = "\226\128\162"      -- "•"

local SEP = Text.SEPARATOR

---------------------------------------------------------------------------------------------------------------------
-- Cleaning (SPEC-15 §4.1, §4.4)
---------------------------------------------------------------------------------------------------------------------
local PIPE = "\1"   -- a typed "|" while the codes are removed (a control character: none of the text's survives)

-- The text without game codes: item links leave their name in brackets, icons and colours go, any other `|` becomes "¦".
local function noCodes(s)
	-- an edit box gives a typed "|" back as "||"
	s = s:gsub("||", PIPE)
	s = s:gsub("|H.-|h(.-)|h", function(name)
		name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
		if name == "" then return "" end
		if name:sub(1, 1) ~= "[" then name = "[" .. name .. "]" end
		return name
	end)
	s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", ""):gsub("|n", "\n")
	return (s:gsub("[|\1]", SEP))
end

-- A page's body (or, with `title`, a title: one line) as it may be saved and shown.
function Text.Clean(s, title)
	if type(s) ~= "string" then return "" end
	s = s:gsub("\1", ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", " ")
	s = noCodes(s)
	if title then s = s:gsub("\n", " ") end
	s = s:gsub("[%z\1-\9\11-\31\127]", "")
	if title then return (s:gsub("^ +", ""):gsub(" +$", "")) end
	local out, blank = {}, 0
	for line in (s .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub(" +$", "")
		blank = line == "" and blank + 1 or 0
		if blank <= 2 then out[#out + 1] = line end
	end
	return concat(out, "\n")
end

---------------------------------------------------------------------------------------------------------------------
-- Blocks (SPEC-15 §4)
---------------------------------------------------------------------------------------------------------------------
-- One line: kind, text, level, number. "text" is a line of a paragraph, "blank" ends it.
local function lineOf(line)
	if line:match("^%s*$") then return "blank" end
	local text = line:match("^## +(.*)$")
	if text and text ~= "" then return "h2", text end
	text = line:match("^# +(.*)$")
	if text and text ~= "" then return "h1", text end
	local indent, rest = line:match("^( *)[%-%*] +(.*)$")
	if indent and rest ~= "" then return "li", rest, #indent >= 2 and 2 or 1 end
	local spaces, number, item = line:match("^( *)(%d+%.) +(.*)$")
	if number and item ~= "" then return "oli", item, #spaces >= 2 and 2 or 1, number end
	return "text", (line:gsub("^%s+", ""))
end

-- The blocks of a body: { kind = "h1" | "h2" | "li" | "oli" | "p", text, level, number, line, last } (`line` and `last`
-- are the first and last line of the body the block comes from).
function Text.Blocks(body)
	local out, par = {}, nil
	local n = 0
	for line in (tostring(body or "") .. "\n"):gmatch("([^\n]*)\n") do
		n = n + 1
		local kind, text, level, number = lineOf(line)
		if kind == "text" then
			if par then
				par.text, par.last = par.text .. " " .. text, n
			else
				par = { kind = "p", text = text, line = n, last = n }
				out[#out + 1] = par
			end
		else
			par = nil
			if kind ~= "blank" then
				out[#out + 1] = { kind = kind, text = text, level = level, number = number, line = n, last = n }
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Links
---------------------------------------------------------------------------------------------------------------------
-- What stands between "[[" and "]]": { slug, heading, label, special = "season" | "loot" }, or nil (it stays text).
function Text.Link(inner)
	local target, label = inner, nil
	local a, b = inner:find(SEP, 1, true)
	if a then target, label = inner:sub(1, a - 1), inner:sub(b + 1) end
	local slug, heading = target:match("^([^#]*)#(.*)$")
	slug = (slug or target):gsub("^%s+", ""):gsub("%s+$", "")
	slug = slug:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
	if not slug:match("^[a-z0-9%-]+$") or #slug > 24 then return nil end
	if heading then heading = heading:gsub("^%s+", ""):gsub("%s+$", "") end
	if label then label = label:gsub("^%s+", ""):gsub("%s+$", "") end
	return { slug = slug, heading = heading ~= "" and heading or nil, label = label ~= "" and label or nil,
		special = (slug == "season" or slug == "loot") and slug or nil }
end

-- The plain text between two links, cut where a web address starts.
local function addText(out, s)
	local from = 1
	while true do
		local a, b = s:find("https?://[^%s<>\"]+", from)
		if not a then break end
		local url = s:sub(a, b):gsub("[%.,;:!%?%)%]}'\194\166]+$", "")
		if url:match("^https?://.") then
			if a > from then out[#out + 1] = { kind = "text", text = s:sub(from, a - 1) } end
			out[#out + 1] = { kind = "url", text = url, url = url }
			from = a + #url
		else
			out[#out + 1] = { kind = "text", text = s:sub(from, b) }
			from = b + 1
		end
	end
	if from <= #s then out[#out + 1] = { kind = "text", text = s:sub(from) } end
end

-- The pieces of a block's text: { kind = "text" | "url" | "link", text, url, link }.
function Text.Inline(s)
	local out, from, plain = {}, 1, {}
	s = tostring(s or "")
	while true do
		local a, b, inner = s:find("%[%[([^%[%]]*)%]%]", from)
		if not a then break end
		local link = Text.Link(inner)
		if link then
			plain[#plain + 1] = s:sub(from, a - 1)
			addText(out, concat(plain))
			plain = {}
			out[#out + 1] = { kind = "link", link = link }
		else
			plain[#plain + 1] = s:sub(from, b)
		end
		from = b + 1
	end
	plain[#plain + 1] = s:sub(from)
	addText(out, concat(plain))
	return out
end

local function escape(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
Text.Escape = escape

local function colored(hex, text)
	if not hex then return text end
	return "|cff" .. hex .. text .. "|r"
end

-- The HTML of one block for a SimpleHTML, and the targets of its links (href "acc:<n>" is the n-th).
-- `resolve(part)` says what a link or an address of Text.Inline shows: its label and, when it can be clicked, the target
-- the reader gets back. `colors` = { link, missing }: hex colours.
function Text.HTML(block, resolve, colors)
	colors = colors or {}
	local links, out = {}, {}
	for _, part in ipairs(Text.Inline(block.text)) do
		if part.kind == "text" then
			out[#out + 1] = escape(part.text)
		else
			local label, target = resolve(part)
			if target then
				links[#links + 1] = target
				out[#out + 1] = '<a href="acc:' .. #links .. '">' .. colored(colors.link, escape(label)) .. "</a>"
			else
				out[#out + 1] = colored(colors.missing, escape(label))
			end
		end
	end
	local text = concat(out)
	local tag = (block.kind == "h1" or block.kind == "h2") and block.kind or "p"
	if block.kind == "li" then text = Text.BULLET .. " " .. text
	elseif block.kind == "oli" then text = block.number .. " " .. text end
	return "<html><body><" .. tag .. ">" .. text .. "</" .. tag .. "></body></html>", links, tag
end

-- A block's text as it reads: links as their label (`resolve` as in HTML; without it, their own text or target).
function Text.Plain(s, resolve)
	local out = {}
	for _, part in ipairs(Text.Inline(s)) do
		if part.kind ~= "link" then out[#out + 1] = part.text
		elseif resolve then out[#out + 1] = (resolve(part))
		else out[#out + 1] = part.link.label or part.link.heading or part.link.slug end
	end
	return concat(out)
end

---------------------------------------------------------------------------------------------------------------------
-- Search (SPEC-15 §4.3)
---------------------------------------------------------------------------------------------------------------------
-- `s` without case and without accents. Accented letters first and ASCII lowered by hand: string.lower follows the C
-- locale, which may change UTF-8 bytes.
function Text.Fold(s)
	local accents = ns.Handbook and ns.Handbook.ACCENTS or {}
	s = tostring(s or ""):gsub("\195[\128-\191]", function(c)
		local b = c:byte(2)
		return accents[c] or (b < 160 and accents["\195" .. string.char(b + 32)]) or c
	end)
	return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

-- Characters (not bytes) of a UTF-8 text.
local function length(s)
	local _, continuation = s:gsub("[\128-\191]", "")
	return #s - floor(continuation)
end

-- The matches of `query` in `pages` (records { id, title, body }, in the order of the list), at most SEARCH_MAX:
-- { { id, title, heading (the nearest above the line), text (the line as it reads), line } }; a match of the title has no
-- line. `resolve` as in Plain. Returns nil for a query too short to search.
function Text.Search(query, pages, resolve)
	local needle = Text.Fold((tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")))
	if length(needle) < Text.SEARCH_MIN then return nil end
	local out = {}
	local function add(r)
		if #out < Text.SEARCH_MAX then out[#out + 1] = r end
	end
	for _, page in ipairs(pages or {}) do
		if Text.Fold(page.title):find(needle, 1, true) then add({ id = page.id, title = page.title }) end
		local heading, n = nil, 0
		for line in (Text.Clean(page.body) .. "\n"):gmatch("([^\n]*)\n") do
			n = n + 1
			local kind, text = lineOf(line)
			if kind ~= "blank" then
				local plain = Text.Plain(text, resolve)
				local isHeading = kind == "h1" or kind == "h2"
				if Text.Fold(plain):find(needle, 1, true) then
					add({ id = page.id, title = page.title, heading = not isHeading and heading or nil, text = plain, line = n })
				end
				if isHeading then heading = plain end
			end
		end
		if #out >= Text.SEARCH_MAX then break end
	end
	return out
end

if ns.addon then ns.addon.HandbookText = Text end

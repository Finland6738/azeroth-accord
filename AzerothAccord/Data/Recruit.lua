-- Recruit: the recruitment text built from what the guild already has (M12.2; SPEC-16 §3; ADR 0026). Lua 5.1.
--
-- Pure text: UI/Recruit.lua shows it in a read-only box and the officer copies it. REC-01: nothing here, or anywhere in
-- M12, calls a function that sends a chat or Battle.net message. REC-02: the text is never saved or sent.
--
--   Recruit.VISIBLE_TO       the one place of SPEC-10 Q34: "officers" (the officers and the Guild Master) | "members"
--   Recruit:CanSee()         true when the switch "recruit" is on and this character may see the text
--   Recruit:Build(format)    "chat" | "discord" (nil: the last chosen) -> text, { format, length, max,
--                            missing = { { part, why } } }, or nil and "off", "officer" or "guild"
--     parts   "description" why "raid" (the switch is off), "page" (no Guild info page, a template or an empty paragraph)
--             "gaps"        why "season" (the switch is off), "closed" (no open season), "fdcp" (FDCP gives no roster),
--                           "target" (no target composition), "full" (no gaps against it)
--   Recruit:Settings()       { contact?, extra?, format }: kept on this computer, GuildKey:Data().recruit
--   Recruit:Set(key, value)  "contact" | "extra" (cleaned, cut to their limit; empty = none) | "format"; returns the
--                            value kept
-- A part never holds a "|", a line break or a control character: the officer's two lines and the handbook text go
-- through Data/HandbookText.lua, names come from the game.
-- Switch: Core/Features.lua "recruit" (M12). The parts ask "season" and "raid" themselves.
local ADDON_NAME, ns = ...
ns = ns or {}
local Recruit = {}
ns.Recruit, ns.modules = Recruit, ns.modules or {}
ns.modules.Recruit = Recruit

local type, ipairs, tostring, concat, max, min = type, ipairs, tostring, table.concat, math.max, math.min

Recruit.VISIBLE_TO = "officers"
Recruit.FORMATS = { "chat", "discord" }
Recruit.CHAT_MAX = 255            -- bytes of one chat message of the game
Recruit.DISCORD_MAX = 1900        -- characters (a Discord message takes 2000)
Recruit.DISCORD_DESCRIPTION = 600 -- bytes of the description in the Discord text
Recruit.CONTACT_MAX = 48          -- bytes of the officer's contact line
Recruit.EXTRA_MAX = 100           -- bytes of the officer's extra line
Recruit.PAGE = "info"             -- the handbook page the description comes from
Recruit.SEPARATOR = " \226\128\147 "   -- " – " between the parts of the chat line

local ELLIPSIS = "\226\128\166"   -- "…"

local function on(name) return ns.Features ~= nil and ns.Features.On(name) end
function Recruit.Enabled() return on("recruit") end

function Recruit:CanSee()
	if not (Recruit.Enabled() and ns.Role and ns.Role:InGuild()) then return false end
	if Recruit.VISIBLE_TO == "members" then return true end
	return ns.Role:IsOfficer() == true
end

---------------------------------------------------------------------------------------------------------------------
-- Lengths and cuts
---------------------------------------------------------------------------------------------------------------------
-- Characters (not bytes) of a UTF-8 text.
function Recruit.Characters(s)
	local _, continuation = s:gsub("[\128-\191]", "")
	return #s - continuation
end

-- The first `n` bytes of `s` at most, never inside a UTF-8 character.
local function head(s, n)
	if #s <= n then return s end
	while n > 0 do
		local b = s:byte(n + 1)
		if b < 128 or b >= 192 then break end
		n = n - 1
	end
	return s:sub(1, max(0, n))
end

-- `s` in at most `n` bytes: whole words and "…"; "" when not even the first word fits.
function Recruit.CutWords(s, n)
	if #s <= n then return s end
	local room = n - #ELLIPSIS
	if room < 1 then return "" end
	local cut = s:sub(1, room)
	if s:sub(room + 1, room + 1) ~= " " then cut = cut:match("^(.*) ") or "" end
	cut = cut:gsub("[ ,;:]+$", "")
	if cut == "" then return "" end
	return cut .. ELLIPSIS
end

---------------------------------------------------------------------------------------------------------------------
-- The officer's own lines (local)
---------------------------------------------------------------------------------------------------------------------
local LIMITS = { contact = Recruit.CONTACT_MAX, extra = Recruit.EXTRA_MAX }

local function validFormat(f) return f == "chat" or f == "discord" end

-- One line as it may be kept and shown, or nil when nothing is left.
local function line(value, limit)
	if type(value) ~= "string" then return nil end
	local s = ns.HandbookText.Clean(value, true)
	s = head(s, limit):gsub(" +$", "")
	if s == "" then return nil end
	return s
end

local function held()
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	return data and type(data.recruit) == "table" and data.recruit or nil
end

function Recruit:Settings()
	local r = held() or {}
	return { contact = line(r.contact, Recruit.CONTACT_MAX), extra = line(r.extra, Recruit.EXTRA_MAX),
		format = validFormat(r.format) and r.format or "chat" }
end

function Recruit:Set(key, value)
	if not self:CanSee() then return nil end
	if key == "format" then
		if not validFormat(value) then return nil end
	elseif LIMITS[key] then
		value = line(value, LIMITS[key])
	else
		return nil
	end
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.recruit) ~= "table" then data.recruit = {} end
	data.recruit[key] = value
	return value
end

---------------------------------------------------------------------------------------------------------------------
-- The parts (SPEC-16 §3.2)
---------------------------------------------------------------------------------------------------------------------
-- "<Guild> (<faction>, <realm>)", with what the client knows; nil without a guild name.
function Recruit.Head()
	local C = ns.Compat
	local name = C and C.Guild.GuildName()
	if not name then return nil end
	local about = {}
	local faction = C.Player.Faction()
	if faction then about[#about + 1] = ns.L["RECRUIT_" .. faction:upper()] end
	local realm = (C.Guild.GuildRealm and C.Guild.GuildRealm()) or C.Player.RealmDisplay()
	if realm then about[#about + 1] = realm end
	if #about == 0 then return name end
	return ("%s (%s)"):format(name, concat(about, ", "))
end

-- A link of the page as plain text: its own words, else the page's title; "" for [[season]] and [[loot]].
local function resolve(part)
	local link = part.link
	if not link then return part.text end
	if link.special then return "" end
	if link.label then return link.label end
	local page = ns.Handbook:Get(ns.Handbook.PageId(link.slug))
	if page and page.del ~= true and page.title then return page.title end
	return link.heading or link.slug
end

local function readable(text)
	local s = ns.HandbookText.Plain(text, resolve):gsub(" +", " "):gsub("^ ", ""):gsub(" $", "")
	return (s:gsub(" ([%.,])", "%1"))   -- the space a removed link leaves before a full stop
end

local function isItem(b) return b.kind == "li" or b.kind == "oli" end

-- The first paragraph under the first heading of a body (of the body when it has no heading), as one line: a list (also
-- one right under a paragraph) becomes sentences separated by "; ". "" when there is nothing to read.
function Recruit.FirstParagraph(body)
	local blocks = ns.HandbookText.Blocks(body)
	local from = 1
	for i, b in ipairs(blocks) do
		if b.kind == "h1" or b.kind == "h2" then from = i + 1 break end
	end
	local i = from
	while blocks[i] and blocks[i].kind ~= "h1" and blocks[i].kind ~= "h2" do
		local first = blocks[i]
		local text, items, last = readable(first.text), {}, first
		i = i + 1
		while blocks[i] and isItem(blocks[i]) and (isItem(last) or blocks[i].line == last.last + 1) do
			last = blocks[i]
			local item = readable(last.text)
			if item ~= "" then items[#items + 1] = item end
			i = i + 1
		end
		if isItem(first) then
			if text ~= "" then table.insert(items, 1, text) end
			text = concat(items, "; ")
		elseif #items > 0 then
			text = (text ~= "" and text .. " " or "") .. concat(items, "; ")
		end
		if text ~= "" then return text end
	end
	return ""
end

-- The description, or nil and why.
function Recruit.Description()
	if not on("raid") then return nil, "raid" end
	local page = ns.Handbook and ns.Handbook:Get(ns.Handbook.PageId(Recruit.PAGE))
	if not page or page.del == true or page.tpl or type(page.body) ~= "string" then return nil, "page" end
	local text = Recruit.FirstParagraph(page.body)
	if text == "" then return nil, "page" end
	return text
end

-- The roles the season roster of the chosen source misses by MS1, { { role, missing } } in the order of
-- Composition.ROLES, or nil and why.
function Recruit.Gaps()
	if not on("season") then return nil, "season" end
	local C, rows = ns.Composition, nil
	if ns.Season.Source() == "fdcp" then
		local I = ns.Integrations
		local state = I and I:State("fdcp")
		if not (state and state.level == 1 and ns.FDCP and ns.FDCP.Ready()) then return nil, "fdcp" end
		local season = ns.FDCP.Season()
		if season and season.state == "CLOSED" then return nil, "closed" end
		local pool = ns.FDCP.Pool()
		if not pool then return nil, "fdcp" end
		rows = C.FromPool(pool)
	else
		local current = ns.Season:Current()
		if not current then return nil, "closed" end
		rows = C.FromAccord(ns.Season:Entries(current.n))
	end
	local gaps = C.Gaps(C.Count(rows), C:Target())
	if not gaps then return nil, "target" end
	local out = {}
	for _, g in ipairs(gaps) do
		if g.missing > 0 then out[#out + 1] = { role = g.role, missing = g.missing } end
	end
	if #out == 0 then return nil, "full" end
	return out
end

-- "2 tanks"
function Recruit.RoleCount(role, n)
	return ns.L["RECRUIT_" .. role:upper() .. (n == 1 and "_ONE" or "_MANY")]:format(n)
end

---------------------------------------------------------------------------------------------------------------------
-- The two formats (SPEC-16 §3.3)
---------------------------------------------------------------------------------------------------------------------
-- p = { head, description?, roles? = { "2 tanks" }, extra?, contact }
local FORMAT = {
	chat = {
		max = Recruit.CHAT_MAX, length = function(s) return #s end,
		join = function(p)
			local out = { p.head }
			out[#out + 1] = p.description
			if p.roles then out[#out + 1] = ns.L["RECRUIT_LOOKING"]:format(concat(p.roles, ", ")) end
			out[#out + 1] = p.extra
			out[#out + 1] = p.contact
			return concat(out, Recruit.SEPARATOR)
		end,
	},
	discord = {
		max = Recruit.DISCORD_MAX, length = Recruit.Characters, description = Recruit.DISCORD_DESCRIPTION,
		join = function(p)
			local out = { "**" .. p.head .. "**" }
			out[#out + 1] = p.description
			if p.roles then
				out[#out + 1] = ns.L["RECRUIT_LOOKING_HEAD"]
				for _, r in ipairs(p.roles) do out[#out + 1] = "- " .. r end
			end
			out[#out + 1] = p.extra
			out[#out + 1] = p.contact
			return concat(out, "\n")
		end,
	},
}

-- Shortens p[key] until the text fits; the part goes when nothing of it does. The head, the gaps and the contact are
-- never cut.
local function shorten(f, p, key)
	local full = p[key]
	if not full then return end
	local room = #full
	while p[key] do
		local over = f.length(f.join(p)) - f.max
		if over <= 0 then return end
		room = min(room - 1, #p[key] - over)
		local cut = Recruit.CutWords(full, room)
		p[key] = cut ~= "" and cut or nil
	end
end

function Recruit:Build(format)
	if not Recruit.Enabled() then return nil, "off" end
	if not self:CanSee() then return nil, "officer" end
	local settings = self:Settings()
	format = validFormat(format) and format or settings.format
	local f = FORMAT[format]
	local head_ = Recruit.Head()
	if not head_ then return nil, "guild" end
	local missing = {}
	local description, why = Recruit.Description()
	if not description then missing[#missing + 1] = { part = "description", why = why } end
	local gaps, whyGaps = Recruit.Gaps()
	local roles
	if gaps then
		roles = {}
		for _, g in ipairs(gaps) do roles[#roles + 1] = Recruit.RoleCount(g.role, g.missing) end
	else
		missing[#missing + 1] = { part = "gaps", why = whyGaps }
	end
	if description and f.description then
		local cut = Recruit.CutWords(description, f.description)
		description = cut ~= "" and cut or nil
	end
	local contact = settings.contact or ns.L["RECRUIT_WHISPER"]:format(ns.Compat.Player.Name() or "?")
	local p = { head = head_, description = description, roles = roles, extra = settings.extra, contact = contact }
	shorten(f, p, "description")
	shorten(f, p, "extra")
	local text = f.join(p)
	return text, { format = format, length = f.length(text), max = f.max, missing = missing }
end

if ns.addon then ns.addon.Recruit = Recruit end

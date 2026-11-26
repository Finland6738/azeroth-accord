-- Handbook: the guild handbook's data (M11.2, SPEC-15 §3; ADR 0025). Lua 5.1.
--
-- Records    the data set `handbook` (Net/Store.lua): "P:<slug>" a page { title, body, order, tpl } or { del }, and
--            "seeded" { at, by } (the default pages' seeding, Data/HandbookDefaults.lua). `rev` is the page's revision: Store:Put writes the
--            revision held plus one, whoever wrote it, and the highest revision wins, then the later time, then the
--            greater author (Store.Compare). A deleted page stays a `del` record for ever, so it never comes back.
-- Writers    the Guild Master, the officers and the ranks the officers chose: the record "handbook" of `guildcfg`
--            { ranks = { { i, n } } }. A chosen rank counts only while rank `i` still has the name `n` in this client's
--            roster. Without the record: officers (WRITERS, SPEC-10 Q27). Handbook.IsWriter(member) is the one place
--            that decides, for this client's writes and for the trust rules (HBK-01: Net/Store.lua `writer`).
-- Limits     BODY_MAX, TITLE_MAX, MAX_PAGES, TOTAL_MAX, WRITES_PER_HOUR (SPEC-10 Q29). Handbook:Save refuses a write over
--            them ("size", "pages", "rate"); a receiver refuses a page over BODY_MAX or TITLE_MAX ("size", HBK-02) and
--            more than WRITES_PER_HOUR new revisions of one author an hour ("rate", HBK-05); it keeps a handbook over
--            MAX_PAGES or TOTAL_MAX (every client must hold the same), Handbook:Pages() shows its first MAX_PAGES.
-- Revisions  past revisions never travel (SPEC-10 Q28): when a page this client holds is replaced, the old version goes
--            into GuildKey:Data().handbook.revs[id] (the last KEEP_REVISIONS). A save over a revision that changed meanwhile
--            does not write ("changed", with the page held) unless the writer keeps theirs (`force`); Handbook:Discard
--            keeps the writer's own text there, marked `lost`.
-- Conflicts  two writers saving from the same revision write the same `rev`: every client keeps the later (HBK-04). The
--            client of the losing author, when its own version is replaced by another author's of the same revision,
--            keeps its text as a `lost` revision, emits HANDBOOK_CONFLICT(id), posts the notice `handbook` / `conflict`
--            and shows an Action Center row until Restore (a new revision) or Dismiss. Nobody else is told.
-- Editor     (M11.4, SPEC-15 §6) Check says what stops a save before it is tried, Move changes the order of the list
--            (one revision, rarely more), Deleted lists the deleted pages this client can restore, and one draft per account
--            is kept in GuildKey:Data().handbook.draft { id, base, title, body, at }; it never travels.
-- Read marks (M11.3, SPEC-15 §5.4) GuildKey:Data().handbook.read[id], per account: the revision last read. A page is
--            updated while its revision is higher and another account wrote it; the reader marks it read.
-- Switch     Core/Features.lua "raid": off, nothing is written, accepted or sent, and nothing is shown.
-- Bus        HANDBOOK_CHANGED(id) a page arrived, was written or deleted (nil: many); HANDBOOK_CONFLICT(id);
--            HANDBOOK_READ(id) the read mark of a page (nil: many) changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Handbook = {}
ns.Handbook, ns.modules = Handbook, ns.modules or {}
ns.modules.Handbook = Handbook

local type, pairs, ipairs, tostring, tonumber, floor, sort, remove = type, pairs, ipairs, tostring, tonumber, math.floor,
	table.sort, table.remove

Handbook.FEATURE = "raid"
Handbook.SET = "handbook"
Handbook.BODY_MAX = 4000          -- bytes of a page's body (UTF-8: an accented letter is 2)
Handbook.TITLE_MAX = 40
Handbook.MAX_PAGES = 20           -- live (not deleted) pages
Handbook.TOTAL_MAX = 32000        -- bytes of every live body together
Handbook.KEEP_REVISIONS = 5       -- past revisions kept on this client per page
Handbook.WRITES_PER_HOUR = 30     -- revisions of one author an hour
Handbook.SLUG_MAX = 24
Handbook.ORDER_MAX = 99
Handbook.WRITERS = "officers"     -- who writes without a choice of the officers (SPEC-10 Q27)
Handbook.WRITERS_ID = "handbook"  -- the record of `guildcfg` with the chosen ranks
Handbook.RANKS_MAX = 9
Handbook.RANK_NAME_MAX = 32
Handbook.SEEDED_ID = "seeded"
Handbook.NEW_DRAFT = "new"        -- the draft of a page that has no id yet
Handbook.NEW_ORDER = 10           -- the order of the first page; a new one goes ORDER_STEP after the last
Handbook.ORDER_STEP = 5

local HOUR = 3600

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function store() return ns.Store end
local function now() return ns.Compat and ns.Compat.ServerTime() or time() end
local function ownGUID() return ns.Compat and ns.Compat.Player.GUID() or nil end

function Handbook.Enabled() return ns.Features ~= nil and ns.Features.On(Handbook.FEATURE) end

local function ready() return Handbook.Enabled() and ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- Shape (HBK-02)
---------------------------------------------------------------------------------------------------------------------
local BASE = { id = true, author = true, rev = true, time = true }
local PAGE = { title = true, body = true, order = true, tpl = true }

-- true when `s` has no game code (`|`) and no control character (the line break too, unless `lines`).
local function clean(s, lines)
	if s:find("|", 1, true) or s:find("\127", 1, true) then return false end
	for i = 1, #s do
		local b = s:byte(i)
		if b < 32 and not (lines and b == 10) then return false end
	end
	return true
end
Handbook.IsClean = clean

-- The slug of a page id ("P:<slug>"), or nil.
function Handbook.SlugOf(id)
	local slug = type(id) == "string" and id:match("^P:([a-z0-9%-]+)$")
	if slug and #slug <= Handbook.SLUG_MAX then return slug end
	return nil
end

function Handbook.PageId(slug) return "P:" .. slug end

local function onlyFields(rec, allowed)
	for k in pairs(rec) do
		if not (BASE[k] or allowed[k]) then return false end
	end
	return true
end

-- The owner rule of the set (Net/Store.lua): true, or false and the reason ("size" for a title or body over its
-- limit, "owner" for anything else).
function Handbook.ValidRecord(rec)
	if type(rec) ~= "table" then return false, "owner" end
	if rec.id == Handbook.SEEDED_ID then
		local ok = onlyFields(rec, { at = true, by = true }) and type(rec.at) == "number" and rec.at >= 0
			and (rec.by == nil or (type(rec.by) == "string" and #rec.by <= 20 and clean(rec.by)))
		return ok, not ok and "owner" or nil
	end
	if not Handbook.SlugOf(rec.id) then return false, "owner" end
	if rec.del ~= nil then
		local ok = rec.del == true and onlyFields(rec, { del = true })
		return ok, not ok and "owner" or nil
	end
	if not onlyFields(rec, PAGE) then return false, "owner" end
	local title, body, order = rec.title, rec.body, rec.order
	if type(title) ~= "string" or title == "" or type(body) ~= "string" then return false, "owner" end
	if #title > Handbook.TITLE_MAX or #body > Handbook.BODY_MAX then return false, "size" end
	if not (clean(title) and clean(body, true)) then return false, "owner" end
	if type(order) ~= "number" or order ~= floor(order) or order < 1 or order > Handbook.ORDER_MAX then return false, "owner" end
	if rec.tpl ~= nil and rec.tpl ~= true then return false, "owner" end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Writers (SPEC-15 §3.3)
---------------------------------------------------------------------------------------------------------------------
-- The owner rule of the `guildcfg` record "handbook" (Data/Integrations.lua calls it with "raid" on).
function Handbook.ValidWriters(rec)
	if type(rec) ~= "table" or rec.id ~= Handbook.WRITERS_ID or not onlyFields(rec, { ranks = true }) then return false end
	local ranks = rec.ranks
	if type(ranks) ~= "table" then return false end
	local n, seen = 0, {}
	for k in pairs(ranks) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	if n > Handbook.RANKS_MAX then return false end
	for i = 1, n do
		local r = ranks[i]
		if type(r) ~= "table" then return false end
		for k in pairs(r) do if k ~= "i" and k ~= "n" then return false end end
		if type(r.i) ~= "number" or r.i ~= floor(r.i) or r.i < 1 or r.i > 9 or seen[r.i] then return false end
		if type(r.n) ~= "string" or r.n == "" or #r.n > Handbook.RANK_NAME_MAX or not clean(r.n) then return false end
		seen[r.i] = true
	end
	return true
end

-- The ranks the officers chose ({ { i, n } }, possibly empty), from the `guildcfg` record.
function Handbook:ChosenRanks()
	local rec = store() and store():Get("guildcfg", Handbook.WRITERS_ID)
	if rec and Handbook.ValidWriters(rec) then return rec.ranks end
	return {}
end

-- rank index -> name in this client's roster.
local function rankNames()
	local out = {}
	local C = ns.Compat
	for _, r in ipairs(C and C.Guild.Ranks() or {}) do out[r.index] = r.name end
	return out
end

-- true when a chosen rank still names the rank it was chosen for (index and name), in this client's roster.
function Handbook:RankStillValid(r, names)
	names = names or rankNames()
	return type(r) == "table" and names[r.i] ~= nil and names[r.i] == r.n
end

-- true when `member` (a roster entry: { rankIndex, officer }) writes the handbook: the Guild Master, an officer, or a
-- chosen rank whose index still has the chosen name.
function Handbook.IsWriter(member)
	if type(member) ~= "table" then return false end
	if member.rankIndex == 0 or member.officer == true then return true end
	if member.rankIndex == nil then return false end
	local names
	for _, r in ipairs(Handbook:ChosenRanks()) do
		if r.i == member.rankIndex then
			names = names or rankNames()
			if Handbook:RankStillValid(r, names) then return true end
		end
	end
	return false
end

-- This character as a roster entry, for IsWriter.
local function me()
	local C = ns.Compat
	local guid = ownGUID()
	local member = guid and store() and store():MemberByGUID(guid)
	local _, _, rankIndex = C.Guild.PlayerRank()
	return { rankIndex = rankIndex or (member and member.rankIndex),
		officer = (ns.Role ~= nil and ns.Role:IsOfficer()) or (member ~= nil and member.officer == true) }
end

-- true when this character may write the handbook now.
function Handbook:CanWrite()
	return ready() and Handbook.IsWriter(me())
end

-- An officer chooses the ranks that write besides the officers: a list of rank indexes (1-9). Returns true, or false
-- and "off", "officer", "rank" (an index without a rank in the roster), or a reason of Store:Put.
function Handbook:SetWriters(indexes)
	if not ready() then return false, "off" end
	if not (ns.Role and ns.Role:IsOfficer()) then return false, "officer" end
	local names, ranks, seen = rankNames(), {}, {}
	for _, i in ipairs(indexes or {}) do
		if type(i) ~= "number" or i < 1 or i > 9 or not names[i] then return false, "rank" end
		if not seen[i] then
			seen[i] = true
			ranks[#ranks + 1] = { i = i, n = names[i]:sub(1, Handbook.RANK_NAME_MAX) }
		end
	end
	sort(ranks, function(a, b) return a.i < b.i end)
	local rec, why = store():Put("guildcfg", Handbook.WRITERS_ID, { ranks = ranks })
	if not rec then return false, why end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------------------------------------------------
local function records() return store():Records(Handbook.SET) end

local function live(rec) return type(rec) == "table" and Handbook.SlugOf(rec.id) ~= nil and rec.del ~= true end

-- The page held for `id` (live or deleted), or nil.
function Handbook:Get(id)
	if not ready() then return nil end
	return store():Get(Handbook.SET, id)
end

-- The order of the list: `order`, then the title, then the id.
local function before(a, b)
	if a.order ~= b.order then return a.order < b.order end
	if a.title ~= b.title then return a.title < b.title end
	return a.id < b.id
end

-- The live pages in their order (`order`, then the title, then the id), the templates only with `templates`. The second
-- result is the number of pages left out over MAX_PAGES (SPEC-15 §3.2), the third those pages, in the same order.
function Handbook:Pages(templates)
	local out = {}
	if not ready() then return out, 0, {} end
	for _, rec in pairs(records()) do
		if live(rec) then out[#out + 1] = rec end
	end
	sort(out, before)
	local over = {}
	while #out > Handbook.MAX_PAGES do
		table.insert(over, 1, remove(out))
	end
	if not templates then
		for i = #out, 1, -1 do if out[i].tpl then remove(out, i) end end
	end
	return out, #over, over
end

-- The live pages and the bytes of their bodies, without the page `except`.
function Handbook:Usage(except)
	local pages, bytes = 0, 0
	if not ready() then return 0, 0 end
	for id, rec in pairs(records()) do
		if id ~= except and live(rec) then
			pages = pages + 1
			bytes = bytes + #(rec.body or "")
		end
	end
	return pages, bytes
end

-- The deleted pages this client holds a revision of, by title: { { id, title } }.
function Handbook:Deleted()
	local out = {}
	if not ready() then return out end
	local data = ns.GuildKey:Data()
	local revs = data and data.handbook and data.handbook.revs or {}
	for id, rec in pairs(records()) do
		local list = Handbook.SlugOf(id) and rec.del == true and revs[id]
		if type(list) == "table" and list[1] then
			local newest = list[1]
			for _, r in ipairs(list) do if (r.rev or 0) > (newest.rev or 0) then newest = r end end
			out[#out + 1] = { id = id, title = newest.title or Handbook.SlugOf(id) }
		end
	end
	sort(out, function(a, b)
		if a.title ~= b.title then return a.title < b.title end
		return a.id < b.id
	end)
	return out
end

-- The order a new page gets: after the last one.
function Handbook:NextOrder()
	local pages = self:Pages(true)
	local last = pages[#pages]
	if not last then return Handbook.NEW_ORDER end
	local order = last.order + Handbook.ORDER_STEP
	return order > Handbook.ORDER_MAX and Handbook.ORDER_MAX or order
end

-- What stops a save of the page `id` (nil: a new page) with this cleaned title and body, before it is tried:
-- { title, body, total (bytes the save would leave), reason, over }. `reason` is nil, "title_empty", "title", "body",
-- "total" (each with `over` = the bytes too many) or "pages".
function Handbook:Check(id, title, body)
	local pages, bytes = self:Usage(id)
	local out = { title = #title, body = #body, total = bytes + #body }
	local held = id and ready() and store():Get(Handbook.SET, id)
	if title == "" then out.reason = "title_empty"
	elseif out.title > Handbook.TITLE_MAX then out.reason, out.over = "title", out.title - Handbook.TITLE_MAX
	elseif out.body > Handbook.BODY_MAX then out.reason, out.over = "body", out.body - Handbook.BODY_MAX
	elseif out.total > Handbook.TOTAL_MAX then out.reason, out.over = "total", out.total - Handbook.TOTAL_MAX
	elseif not live(held) and pages >= Handbook.MAX_PAGES then out.reason = "pages" end
	return out
end

-- A free page id for a title: the letters without accents, spaces as "-", a number when the slug is taken.
local ACCENTS = {
	["à"] = "a", ["á"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["å"] = "a", ["è"] = "e", ["é"] = "e", ["ê"] = "e",
	["ë"] = "e", ["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i", ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["ö"] = "o",
	["õ"] = "o", ["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u", ["ñ"] = "n", ["ç"] = "c", ["ß"] = "ss",
}
Handbook.ACCENTS = ACCENTS   -- the search of Data/HandbookText.lua
function Handbook.Slug(title)
	-- the accents first and only ASCII lowered by hand: string.lower follows the C locale, which may change UTF-8 bytes
	local s = type(title) == "string" and title or ""
	s = s:gsub("\195[\128-\191]", function(c)
		local b = c:byte(2)
		return ACCENTS[c] or (b < 160 and ACCENTS["\195" .. string.char(b + 32)]) or ""
	end)
	s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
	s = s:gsub("[%s_]+", "-"):gsub("[^a-z0-9%-]", ""):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
	s = s:sub(1, Handbook.SLUG_MAX):gsub("%-$", "")
	if s == "" then s = "page" end
	return s
end

function Handbook:NewId(title)
	local base = Handbook.Slug(title)
	local held = ready() and records() or {}
	local id = Handbook.PageId(base)
	local n = 1
	while held[id] do
		n = n + 1
		local suffix = "-" .. n
		id = Handbook.PageId(base:sub(1, Handbook.SLUG_MAX - #suffix):gsub("%-$", "") .. suffix)
	end
	return id
end

---------------------------------------------------------------------------------------------------------------------
-- The rate of writes (HBK-05)
---------------------------------------------------------------------------------------------------------------------
local rates = {}   -- author GUID -> times of its revisions of the last hour (held in memory, per session)

local function recent(author, t)
	local list = rates[author]
	if not list then return {} end
	local keep = {}
	for _, at in ipairs(list) do if at > t - HOUR then keep[#keep + 1] = at end end
	rates[author] = keep
	return keep
end

-- The rate rule of a received revision (Net/Store.lua `rate`): a revision written within the last hour counts against its
-- author; true while the author stays within WRITES_PER_HOUR (and then it is counted).
function Handbook.Within(rec)
	local t, at = now(), type(rec) == "table" and rec.time or 0
	if at <= t - HOUR then return true end
	local list = recent(rec.author, t)
	if #list >= Handbook.WRITES_PER_HOUR then return false end
	list[#list + 1] = at
	rates[rec.author] = list
	return true
end

function Handbook:ResetRates() rates = {} end

---------------------------------------------------------------------------------------------------------------------
-- Local data: revisions (SPEC-15 §2.4)
---------------------------------------------------------------------------------------------------------------------
local function localData()
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	local hb = data.handbook
	if type(hb) ~= "table" then
		hb = {}
		data.handbook = hb
	end
	if type(hb.revs) ~= "table" then hb.revs = {} end
	if type(hb.read) ~= "table" then hb.read = {} end
	return hb
end
Handbook.LocalData = localData

local function remember(rec, lost, open)
	if not live(rec) then return end
	local hb = localData()
	if not hb then return end
	local list = hb.revs[rec.id]
	if type(list) ~= "table" then
		list = {}
		hb.revs[rec.id] = list
	end
	for _, r in ipairs(list) do
		if r.rev == rec.rev and r.author == rec.author and r.time == rec.time then
			if lost then r.lost, r.open = true, open or nil end
			return
		end
	end
	sort(list, function(a, b) return (a.rev or 0) > (b.rev or 0) end)
	table.insert(list, 1, { rev = rec.rev, author = rec.author, time = rec.time, title = rec.title, body = rec.body,
		order = rec.order, lost = lost or nil, open = (lost and open) or nil })
	while #list > Handbook.KEEP_REVISIONS do remove(list) end
end

-- The page's revisions as this client saw them: the current one first (when the page is live), then the past ones, the
-- newest first, each { rev, author, time, title, body, order, lost, open, current }.
function Handbook:Revisions(id)
	local out = {}
	if not ready() then return out end
	local held = store():Get(Handbook.SET, id)
	if live(held) then
		out[1] = { rev = held.rev, author = held.author, time = held.time, title = held.title, body = held.body,
			order = held.order, current = true }
	end
	local hb = localData()
	local list = hb and hb.revs[id]
	if type(list) == "table" then
		local past = {}
		for _, r in ipairs(list) do past[#past + 1] = r end
		sort(past, function(a, b)
			if a.rev ~= b.rev then return a.rev > b.rev end
			return (a.time or 0) > (b.time or 0)
		end)
		for _, r in ipairs(past) do out[#out + 1] = r end
	end
	return out
end

local function sameAccount(a, b) return a ~= nil and b ~= nil and store():SameAccount(a, b) end

-- The record a revision replaces (Net/Store.lua `replaced`): it is kept as a past revision; a version of this account
-- replaced by another author's of the same revision is a conflict lost (SPEC-15 §3.5).
function Handbook.Replaced(held, rec, origin)
	if not live(held) then return end
	local me_ = ownGUID()
	-- two writers seeding the default pages at once (SPEC-15 §7.2) lose no text of anybody
	local lost = origin == "remote" and held.rev == rec.rev and sameAccount(me_, held.author)
		and not sameAccount(me_, rec.author) and not (held.tpl and rec.tpl)
	remember(held, lost, lost)
	if lost then Handbook:Conflict(held, rec) end
end

---------------------------------------------------------------------------------------------------------------------
-- Read marks (SPEC-15 §5.4)
---------------------------------------------------------------------------------------------------------------------
-- true when the page changed since this account last read it: a published page whose revision is higher than the one
-- read (never read: every page) and whose last revision no character of this account wrote.
function Handbook:IsUpdated(rec)
	if not (ready() and live(rec)) or rec.tpl then return false end
	local hb = localData()
	if not hb or rec.rev <= (tonumber(hb.read[rec.id]) or 0) then return false end
	return not sameAccount(ownGUID(), rec.author)
end

-- The updated pages, in the order of the list.
function Handbook:Updated()
	local out = {}
	for _, rec in ipairs(self:Pages()) do
		if self:IsUpdated(rec) then out[#out + 1] = rec end
	end
	return out
end

local function mark(rec)
	local hb = localData()
	if not (hb and live(rec)) or (tonumber(hb.read[rec.id]) or 0) >= rec.rev then return false end
	hb.read[rec.id] = rec.rev
	return true
end

-- The page `id` has been read, at the revision held. Returns true when its mark changed.
function Handbook:MarkRead(id)
	if not ready() or not mark(store():Get(Handbook.SET, id)) then return false end
	emit("HANDBOOK_READ", id)
	return true
end

-- "Mark all as read". Returns the number of pages it marked.
function Handbook:MarkAllRead()
	local n = 0
	for _, rec in ipairs(self:Updated()) do
		if mark(rec) then n = n + 1 end
	end
	if n > 0 then emit("HANDBOOK_READ") end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------------------------------
-- Writes a page. `fields` = { title, body, order, tpl }; `opts` = { base = the revision the editor started from (nil for
-- a new page), force = true to write over a revision that changed meanwhile ("Keep mine") }. Returns the record, or nil
-- and a reason: "off", "writer", "id", "size" (title, body or the total over its limit), "pages", "rate", "owner"
-- (a field that is not allowed, a `|` or a control character: the editor cleans the text first), "changed" (with the
-- page held as third result: somebody saved meanwhile), or a reason of Store:Put.
function Handbook:Save(id, fields, opts)
	opts = opts or {}
	if not ready() then return nil, "off" end
	if not self:CanWrite() then return nil, "writer" end
	if not Handbook.SlugOf(id) then return nil, "id" end
	fields = fields or {}
	local title, body = fields.title, fields.body or ""
	if type(title) ~= "string" or type(body) ~= "string" then return nil, "owner" end
	if #title > Handbook.TITLE_MAX or #body > Handbook.BODY_MAX then return nil, "size" end
	local held = store():Get(Handbook.SET, id)
	if held and not opts.force and opts.base ~= held.rev then return nil, "changed", held end
	if not held and opts.base ~= nil and not opts.force then return nil, "changed", nil end
	local pages, bytes = self:Usage(id)
	if not live(held) and pages >= Handbook.MAX_PAGES then return nil, "pages" end
	if bytes + #body > Handbook.TOTAL_MAX then return nil, "size" end
	local author = ownGUID()
	if #recent(author, now()) >= Handbook.WRITES_PER_HOUR then return nil, "rate" end
	local rec = { title = title, body = body, order = fields.order or (held and held.order) or 50, tpl = fields.tpl or nil }
	local ok, why = Handbook.ValidRecord({ id = id, title = rec.title, body = rec.body, order = rec.order, tpl = rec.tpl })
	if not ok then return nil, why end
	local written, whyPut = store():Put(Handbook.SET, id, rec)
	if not written then return nil, whyPut end
	Handbook.Within(written)
	return written
end

-- Deletes a page for the whole guild (a `del` record, kept for ever). `base` as in Save. Returns the record or nil and
-- a reason of Save.
function Handbook:Delete(id, base, force)
	if not ready() then return nil, "off" end
	if not self:CanWrite() then return nil, "writer" end
	local held = store():Get(Handbook.SET, id)
	if not live(held) then return nil, "id" end
	if not force and base ~= held.rev then return nil, "changed", held end
	if #recent(ownGUID(), now()) >= Handbook.WRITES_PER_HOUR then return nil, "rate" end
	local written, why = store():Put(Handbook.SET, id, { del = true })
	if not written then return nil, why end
	Handbook.Within(written)
	return written
end

-- "Discard mine": the writer's own text of a page that changed meanwhile stays among the page's revisions, marked lost.
function Handbook:Discard(id, title, body, base)
	if not (ready() and Handbook.SlugOf(id)) then return false end
	-- chosen by the writer: kept, but no row to act on
	remember({ id = id, rev = (base or 0) + 1, author = ownGUID(), time = now(), title = title or "", body = body or "",
		order = 50 }, true, false)
	emit("HANDBOOK_CHANGED", id)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The order of the list (SPEC-15 §5.2)
---------------------------------------------------------------------------------------------------------------------
-- An order that puts `rec` between `prev` and `next` (either may be nil), the middle of those that do; or nil.
local function orderBetween(rec, prev, nxt)
	local fits = {}
	for o = 1, Handbook.ORDER_MAX do
		local moved = { id = rec.id, title = rec.title, order = o }
		if (not prev or before(prev, moved)) and (not nxt or before(moved, nxt)) then fits[#fits + 1] = o end
	end
	return fits[floor((#fits + 1) / 2)]
end

-- The writes that move page `id` one place up (step -1) or down (1): { { rec, order } }, usually one: the page's, or
-- the neighbour's; when neither fits (equal orders), the pages are numbered anew. nil when it cannot move.
function Handbook:MovePlan(id, step)
	local pages = self:Pages(true)
	local at
	for i, rec in ipairs(pages) do if rec.id == id then at = i end end
	local to = at and at + step
	if not (to and pages[to] and (step == 1 or step == -1)) then return nil end
	local moved, other = pages[at], pages[to]
	pages[at], pages[to] = other, moved
	for _, pick in ipairs({ { moved, to }, { other, at } }) do
		local order = orderBetween(pick[1], pages[pick[2] - 1], pages[pick[2] + 1])
		if order then return { { pick[1], order } } end
	end
	local gap = floor(Handbook.ORDER_MAX / (#pages + 1))
	local plan = {}
	for i, rec in ipairs(pages) do
		if rec.order ~= i * gap then plan[#plan + 1] = { rec, i * gap } end
	end
	return plan
end

-- Moves the page in the list: each changed page is written as a new revision. Returns true, or false and a reason of
-- Save ("id" when it cannot move that way).
function Handbook:Move(id, step)
	if not ready() then return false, "off" end
	if not self:CanWrite() then return false, "writer" end
	local plan = self:MovePlan(id, step)
	if not plan then return false, "id" end
	if #recent(ownGUID(), now()) + #plan > Handbook.WRITES_PER_HOUR then return false, "rate" end
	for _, w in ipairs(plan) do
		local rec = w[1]
		local ok, why = self:Save(rec.id, { title = rec.title, body = rec.body, order = w[2], tpl = rec.tpl },
			{ base = rec.rev })
		if not ok then return false, why end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The draft (SPEC-15 §6): one per account, never sent
---------------------------------------------------------------------------------------------------------------------
-- The draft of the page `id` (NEW_DRAFT: a new page), or nil.
function Handbook:Draft(id)
	local hb = ready() and localData()
	local d = hb and hb.draft
	if type(d) == "table" and d.id == id and type(d.title) == "string" and type(d.body) == "string" then return d end
	return nil
end

-- Keeps the editor's text as it is typed (not cleaned); it takes the place of any other draft.
function Handbook:SaveDraft(id, base, title, body)
	local hb = ready() and localData()
	if not hb then return false end
	hb.draft = { id = id, base = base, title = title, body = body, at = now() }
	return true
end

function Handbook:ClearDraft(id)
	local hb = ready() and localData()
	if hb and type(hb.draft) == "table" and hb.draft.id == id then hb.draft = nil end
end

---------------------------------------------------------------------------------------------------------------------
-- Conflicts (SPEC-15 §3.5)
---------------------------------------------------------------------------------------------------------------------
local function nameOf(guid)
	local member = guid and store():MemberByGUID(guid)
	if member and member.name then
		local C = ns.Compat
		return C and C.SplitName and (C.SplitName(member.name)) or member.name
	end
	return "?"
end
Handbook.NameOf = nameOf

-- The lost revisions still waiting for the writer's choice: { { id, title, rev, author (the winner), time } }.
function Handbook:Conflicts()
	local out = {}
	if not ready() then return out end
	local hb = localData()
	for id, list in pairs(hb and hb.revs or {}) do
		for _, r in ipairs(list) do
			if r.lost and r.open then
				local held = store():Get(Handbook.SET, id)
				out[#out + 1] = { id = id, title = r.title, rev = r.rev, time = r.time,
					winner = held and held.author, page = held and held.title or r.title }
			end
		end
	end
	sort(out, function(a, b) return (a.time or 0) > (b.time or 0) end)
	return out
end

-- Dismiss: the lost revision stays, its row goes.
function Handbook:Dismiss(id, rev)
	local hb = ready() and localData()
	for _, r in ipairs(hb and hb.revs[id] or {}) do
		if r.lost and (rev == nil or r.rev == rev) then r.open = nil end
	end
	emit("HANDBOOK_CONFLICT", id)
end

-- Restore: the revision `rev` of the page (a past one, lost or not) written as a new revision; `time` and `author`
-- tell apart two of the same number.
function Handbook:Restore(id, rev, time, author)
	if not ready() then return nil, "off" end
	local pick
	for _, r in ipairs(self:Revisions(id)) do
		if not r.current and r.rev == rev and (time == nil or r.time == time) and (author == nil or r.author == author) then
			pick = r
			break
		end
	end
	if not pick then return nil, "revision" end
	local held = store():Get(Handbook.SET, id)
	local written, why = self:Save(id, { title = pick.title, body = pick.body, order = pick.order },
		{ base = held and held.rev, force = true })
	if written and pick.lost then pick.open = nil end
	return written, why
end

function Handbook:Conflict(mine, winner)
	emit("HANDBOOK_CONFLICT", mine.id)
	local N = ns.Notify
	if N and N.Enabled() then
		N:Post("handbook", "conflict", { key = "conflict#" .. mine.id .. "#" .. tostring(mine.rev),
			text = "HANDBOOK_NOTICE_CONFLICT", args = { mine.title or "?", nameOf(winner.author) }, char = ownGUID(),
			still = function()
				for _, c in ipairs(Handbook:Conflicts()) do if c.id == mine.id then return true end end
				return false
			end })
	end
end

-- Opens the handbook on a page; with `rev`, on its revisions (the writer's lost text, M11.4).
local function openView(id, rev)
	local view = ns.HandbookView
	if not view then return end
	if rev and view.OpenConflict then view:OpenConflict(id, rev) elseif view.Open then view:Open(id) end
end

-- The Action Center rows: for a writer one per lost revision waiting for a choice (urgency 2); for everybody one for the
-- pages updated since they were read (urgency 1).
function Handbook:ActionRows()
	local rows = {}
	if self:CanWrite() then
		for _, c in ipairs(self:Conflicts()) do
			rows[#rows + 1] = { key = c.id .. ":" .. tostring(c.rev), urgency = 2, time = c.time, mark = tostring(c.rev),
				who = nameOf(c.winner), title = ns.L["HANDBOOK_ROW_CONFLICT"]:format(c.page or "?"),
				detail = ns.L["HANDBOOK_ROW_CONFLICT_DETAIL"]:format(nameOf(c.winner)),
				open = function() openView(c.id, c.rev) end }
		end
	end
	local updated = self:Updated()
	if #updated > 0 then
		local since, mark_, titles = updated[1].time, 0, {}
		for i, rec in ipairs(updated) do
			if rec.time < since then since = rec.time end
			mark_ = mark_ + rec.rev
			titles[i] = rec.title
		end
		local first = updated[1].id
		rows[#rows + 1] = { key = "updated", urgency = 1, time = since, mark = #updated .. ":" .. mark_,
			title = #updated == 1 and ns.L["HANDBOOK_ROW_UPDATED_ONE"]
				or ns.L["HANDBOOK_ROW_UPDATED"]:format(#updated),
			detail = table.concat(titles, ", "), open = function() openView(first) end }
	end
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
function Handbook:DebugLines()
	if not ready() then return {} end
	local pages, bytes = self:Usage()
	local _, hidden = self:Pages(true)
	return { ("Handbook: %d page(s), %d / %d bytes, %d hidden over the limit, %d conflict(s) waiting, writer: %s"):format(
		pages, bytes, Handbook.TOTAL_MAX, hidden, #self:Conflicts(), self:CanWrite() and "yes" or "no") }
end

if ns.Notify then
	ns.Notify:Register("handbook", { label = "ACT_PROVIDER_HANDBOOK", order = 27, feature = "raid",
		open = function(entry)
			local key = type(entry.key) == "string" and entry.key or ""
			local id, rev = key:match("^conflict#(P:[^#]+)#(%d+)$")
			openView(id, tonumber(rev))
		end, kinds = {
			{ id = "conflict", level = "alert", off = "SET_NOTICE_HANDBOOK_CONFLICT", group = "HANDBOOK_NOTICE_CONFLICTS" },
		} })
end

if ns.Actions then
	ns.Actions:Register("handbook", { label = "ACT_PROVIDER_HANDBOOK", order = 7, feature = "raid",
		events = { "HANDBOOK_CONFLICT", "HANDBOOK_CHANGED", "HANDBOOK_READ", "ROSTER_UPDATED" }, items = function() return Handbook:ActionRows() end })
end

if ns.addon then
	ns.addon.Handbook = Handbook
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Handbook", function() return Handbook:DebugLines() end)
	end
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set == Handbook.SET and Handbook.Enabled() then emit("HANDBOOK_CHANGED", id) end
		end)
		ns.Bus:On("GUILD_CHANGED", function() rates = {} end)
	end
end

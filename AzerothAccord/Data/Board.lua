-- Board: the buy and sell board of the guild, one record per side (M13.5; SPEC-17 §6, BRD-01..BRD-03; SPEC-10 Q47;
-- ADR 0028). Lua 5.1.
--
-- The set `board` is an ordinary set of the guild (GUILD, with the summary kind `ec`, SPEC-17 §10.2) with two records:
--   P:<author GUID>:<n>              a post, written only by the author's account: { kind = wts | wtb, item (item id),
--                                    count 1..QTY_MAX, price? (text), note?, until (a time), state = open | withdrawn |
--                                    done, with (the other side, with done) }
--   D:<author GUID>:<n>:<GUID>       the answer of a character to that post, written only by its account:
--                                    { state = want | withdrawn | done, note? }
-- Nobody writes the other side (BRD-01), officers included. After the first write `kind`, `item`, `count`, `price` and
-- `until` do not change, and a withdrawn post stays withdrawn (BRD-02). An answer that arrives before its post waits for
-- it (BRD-03). A deal is CLOSED only when the post says done with a character and that character's answer says done, both
-- written before the post expired (ECO-03): one confirmation leaves the post open. A closed deal is not reopened: a
-- revision that takes a confirmation back more than LOCK_GRACE seconds after the deal closed is refused by who holds both
-- (inside the grace the two writes crossed, and the withdrawal stands everywhere). The state shown is never written.
-- A post expires by itself on every client, from the date; the records go KEEP_DAYS after `until` or after the deal
-- closed. Accord never moves gold or items (ECO-01): nothing here calls the game's trade, mail, auction or bank functions.
--
--   Board.ValidRecord(rec, store)    the owner rule of the set: true, or false and "owner" | "wait"
--   Board.Transition(held, rec)      BRD-02: true, or false and "locked"
--   Board.ClosedAt(p, d)             the time the deal between post p and answer d closed, or nil
--   Board:Row(p, t), Board:Get(id)   a post as the views use it (names, answers, state, allowed actions)
--   Board:List(opts)                 opts = { side = "all" | "wts" | "wtb", help, search }: open posts and closed deals
--   Board:Post(spec)                 spec = { kind, item, count, price?, note?, days? }: the record, or nil and why
--   Board:Act(id, action, guid, note)
--       "withdraw" (author), "confirm" (author: with `guid`; the other side: its own), "unconfirm" (the own confirmation
--       taken back), "deal" ("want"), "drop" (the interest taken back): the record written, or false and why
--   Board:OfMember(guid), Board:OpenCount()
--   Board:Hide(guid), Board:UnhideAll(), Board:HiddenCount()     posts hidden on this computer only
-- Switch: Core/Features.lua "econ" (store def `feature = "econ"`). Bus: BOARD_CHANGED(id).
local ADDON_NAME, ns = ...
ns = ns or {}
local Board = {}
ns.Board, ns.modules = Board, ns.modules or {}
ns.modules.Board = Board

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, max = math.floor, math.max
local sort, concat = table.sort, table.concat
local DAY, HOUR = 86400, 3600

Board.SET = "board"
Board.DAYS = 3                -- how long a post holds by default (SPEC-10 Q47)
Board.DAYS_MAX = 7
Board.QTY_MAX = 9999
Board.PRICE_MAX = 24          -- bytes
Board.NOTE_MAX = 80           -- bytes
Board.MAX_OPEN = 10           -- open posts of one account
Board.KEEP_DAYS = 7           -- after `until`, or after the deal closed
Board.POST_BYTES = 448        -- estimated size of a post (Config.EstimateSize)
Board.ANSWER_BYTES = 320
Board.WRITES_PER_HOUR = 20
Board.WAIT = 600              -- BRD-03: seconds an answer waits for its post
Board.WAIT_MAX = 200
Board.LOCK_GRACE = 600        -- seconds after a deal closed in which a withdrawal that crossed it still stands
Board.KINDS = { "wts", "wtb" }

local KINDS = { wts = true, wtb = true }
local POST_STATES = { open = true, withdrawn = true, done = true }
local ANSWER_STATES = { want = true, withdrawn = true, done = true }
local POST_FIELDS = { id = true, author = true, rev = true, time = true, kind = true, item = true, count = true,
	price = true, note = true, ["until"] = true, state = true, with = true }
local ANSWER_FIELDS = { id = true, author = true, rev = true, time = true, state = true, note = true }
local LOCKED = { "kind", "item", "count", "price", "until" }

local function store() return ns.Store end
local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function me() return compat() and compat().Player.GUID() or nil end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function inGuild() return ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil end

function Board.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

local function isGUID(g) return type(g) == "string" and #g <= 40 and g:find(store().GUID_PATTERN) ~= nil end
local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end

-- A price or a note: no control characters and no "|" (SPEC-15 §4.4), trimmed.
function Board.Clean(value)
	if type(value) ~= "string" then return "" end
	value = value:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return value
end

local function validText(v, limit)
	return v == nil or (type(v) == "string" and v ~= "" and #v <= limit and not v:find("[%c|]"))
end

---------------------------------------------------------------------------------------------------------------------
-- Ids
---------------------------------------------------------------------------------------------------------------------
-- "P", the author's GUID and the number; "D", the same and the answering character's GUID. Nil for anything else.
function Board.Parse(id)
	if type(id) ~= "string" then return nil end
	local author, n = id:match("^P:(Player%-%d+%-%x+):([1-9]%d*)$")
	if author then
		if #author > 40 or #n > 9 then return nil end
		return "P", author, tonumber(n)
	end
	local other
	author, n, other = id:match("^D:(Player%-%d+%-%x+):([1-9]%d*):(Player%-%d+%-%x+)$")
	if not author or #author > 40 or #n > 9 or #other > 40 then return nil end
	return "D", author, tonumber(n), other
end

function Board.PostId(author, n) return "P:" .. tostring(author) .. ":" .. tostring(n) end
function Board.AnswerId(postId, guid) return "D" .. tostring(postId):sub(2) .. ":" .. tostring(guid) end
local function postIdOf(answerId) return "P" .. (tostring(answerId):sub(2):gsub(":[^:]+$", "")) end

---------------------------------------------------------------------------------------------------------------------
-- Trust: the rules Net/Store.lua applies (BRD-01..BRD-03)
---------------------------------------------------------------------------------------------------------------------
local function onlyFields(rec, fields)
	for k in pairs(rec) do if not fields[k] then return false end end
	return true
end

local function validPost(rec, s, author)
	if not (onlyFields(rec, POST_FIELDS) and s:SameAccount(author, rec.author)) then return false end
	if not (KINDS[rec.kind] and int(rec.item, 1, 2147483647) and int(rec.count, 1, Board.QTY_MAX)) then return false end
	if not (validText(rec.price, Board.PRICE_MAX) and validText(rec.note, Board.NOTE_MAX)) then return false end
	local last = rec["until"]
	if not (type(rec.time) == "number" and type(last) == "number" and last > 0 and last == floor(last)
		and last <= rec.time + Board.DAYS_MAX * DAY) then
		return false
	end
	if not POST_STATES[rec.state] then return false end
	if rec.state ~= "done" then return rec.with == nil end
	return isGUID(rec.with) and not s:SameAccount(author, rec.with)
end

function Board.ValidRecord(rec, s)
	s = s or store()
	if type(rec) ~= "table" then return false, "owner" end
	local kind, author, _, other = Board.Parse(rec.id)
	if kind == "P" then
		if not validPost(rec, s, author) or ns.Config.EstimateSize(rec) > Board.POST_BYTES then return false, "owner" end
		return true
	end
	if kind ~= "D" then return false, "owner" end
	if not (onlyFields(rec, ANSWER_FIELDS) and ANSWER_STATES[rec.state] and validText(rec.note, Board.NOTE_MAX)
		and type(rec.time) == "number" and s:SameAccount(other, rec.author) and not s:SameAccount(author, other)
		and ns.Config.EstimateSize(rec) <= Board.ANSWER_BYTES) then
		return false, "owner"
	end
	if not s:Get(Board.SET, postIdOf(rec.id)) then return false, "wait" end   -- BRD-03
	return true
end

-- The time the deal between a post and an answer closed (both confirmations, before the post expired), or nil.
function Board.ClosedAt(p, d)
	if not (p and d and p.state == "done" and d.state == "done") then return nil end
	local _, _, _, other = Board.Parse(d.id)
	if p.with ~= other or postIdOf(d.id) ~= p.id then return nil end
	if (p.time or 0) > p["until"] or (d.time or 0) > p["until"] then return nil end
	return max(p.time or 0, d.time or 0)
end

function Board.Transition(held, rec)
	local kind = Board.Parse(rec.id)
	if type(held) ~= "table" or store().Compare(rec, held) <= 0 then return true end   -- the store keeps the one it holds
	local closed
	if kind == "P" then
		for _, key in ipairs(LOCKED) do
			if rec[key] ~= held[key] then return false, "locked" end
		end
		if held.state == "withdrawn" and rec.state ~= "withdrawn" then return false, "locked" end
		if held.state == "done" and not (rec.state == "done" and rec.with == held.with) then
			closed = Board.ClosedAt(held, store():Get(Board.SET, Board.AnswerId(held.id, held.with)))
		end
	elseif held.state == "done" and rec.state ~= "done" then
		local post = store():Get(Board.SET, postIdOf(held.id))
		closed = Board.ClosedAt(post, held)
	end
	if closed and (rec.time or 0) > closed + Board.LOCK_GRACE then return false, "locked" end
	return true
end

-- BRD-03: the answers that arrived before their post, tried again when it does.
Board.waiting = {}

function Board.Wait(rec, ctx)
	local list = Board.waiting
	for i = #list, 1, -1 do
		if list[i].rec.id == rec.id then table.remove(list, i) end
	end
	list[#list + 1] = { rec = store().Copy(rec), sender = ctx and ctx.sender, dist = ctx and ctx.dist, at = compat().Now() }
	while #list > Board.WAIT_MAX do table.remove(list, 1) end
end

-- Tries the answers of post `postId` again. Returns how many were taken.
function Board.Retry(postId)
	local list, mine = Board.waiting, {}
	for i = #list, 1, -1 do
		if postIdOf(list[i].rec.id) == postId then mine[#mine + 1] = table.remove(list, i) end
	end
	local taken = 0
	for i = #mine, 1, -1 do
		local w = mine[i]
		if compat().Now() - w.at <= Board.WAIT
			and store():Accept(Board.SET, w.rec, { sender = w.sender, dist = w.dist }) == true then
			taken = taken + 1
		end
	end
	return taken
end

local function waitingAnswer(answerId)
	for _, w in ipairs(Board.waiting) do
		if w.rec.id == answerId then return w.rec end
	end
	return nil
end

-- Retention: a post and its answers go KEEP_DAYS after `until`, or after the deal closed. Judged on what the store holds
-- (it prunes after judging every record), or on the answer that waits for its post (a sync sends the answers first, "D:"
-- before "P:"). A post that says done whose answer is not known goes KEEP_DAYS after that confirmation, so a closed deal
-- already deleted here does not come back as one confirmed by one side.
function Board.Expired(rec, t)
	local kind = Board.Parse(type(rec) == "table" and rec.id or nil)
	if not kind then return true end
	local s, keep = store(), Board.KEEP_DAYS * DAY
	if kind == "D" then
		local post = s:Get(Board.SET, postIdOf(rec.id))
		if post then return Board.Expired(post, t) end
		return (rec.time or 0) < t - Board.DAYS_MAX * DAY - keep
	end
	local base = rec["until"] or 0
	if rec.state == "done" and type(rec.with) == "string" then
		local answerId = Board.AnswerId(rec.id, rec.with)
		local d = s:Get(Board.SET, answerId) or waitingAnswer(answerId)
		if d then base = Board.ClosedAt(rec, d) or base
		elseif (rec.time or 0) < base then base = rec.time or 0 end
	end
	return base < t - keep
end

---------------------------------------------------------------------------------------------------------------------
-- Rate
---------------------------------------------------------------------------------------------------------------------
local received, written = {}, {}   -- author -> times (received); the times this client wrote a record

local function recent(list, t)
	local keep = {}
	for _, at in ipairs(list or {}) do if at > t - HOUR then keep[#keep + 1] = at end end
	return keep
end

function Board.Within(rec)
	if type(rec) ~= "table" then return true end
	local t, at = now(), rec.time or 0
	if at <= t - HOUR then return true end
	local list = recent(received[rec.author], t)
	received[rec.author] = list
	if #list >= Board.WRITES_PER_HOUR then return false end
	list[#list + 1] = at
	return true
end

function Board:ResetRates() received, written = {}, {} end

---------------------------------------------------------------------------------------------------------------------
-- Local data (GuildKey:Data().econ: never sent)
---------------------------------------------------------------------------------------------------------------------
local function econ()
	local data = inGuild() and ns.GuildKey:Data() or nil
	if not data then return nil end
	if type(data.econ) ~= "table" then data.econ = {} end
	return data.econ
end

local function hiddenBook()
	local e = econ()
	return e and type(e.hidden) == "table" and e.hidden or nil
end

function Board:IsHidden(guid)
	local book = hiddenBook()
	if not book then return false end
	if book[guid] then return true end
	for held in pairs(book) do
		if store():SameAccount(held, guid) then return true end
	end
	return false
end

-- The posts of this person are not shown on this computer any more. Never the own account.
function Board:Hide(guid)
	local e, mine = econ(), me()
	if not (Board.Enabled() and e and isGUID(guid)) or (mine and store():SameAccount(mine, guid)) then return false end
	if type(e.hidden) ~= "table" then e.hidden = {} end
	e.hidden[guid] = true
	emit("BOARD_CHANGED", nil)
	return true
end

function Board:HiddenCount()
	local n = 0
	for _ in pairs(hiddenBook() or {}) do n = n + 1 end
	return n
end

function Board:UnhideAll()
	local e = econ()
	if not e then return false end
	e.hidden = nil
	emit("BOARD_CHANGED", nil)
	return true
end

-- The warning of the board ("Accord does not trade"), shown until the player says it was read.
function Board:Warned()
	local e = econ()
	return e ~= nil and e.boardWarned == true
end

function Board:SetWarned()
	local e = econ()
	if e then e.boardWarned = true end
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function entryOf(guid) return ns.Roster and ns.Roster:ByGUID(guid) or nil end
local function rosterRead() return ns.Roster ~= nil and ns.Roster:Count() > 0 end

local function nameOf(guid)
	local e = entryOf(guid)
	return e and (e.short or e.name) or "?"
end
Board.NameOf = nameOf

local function own(guid)
	local mine = me()
	return mine ~= nil and store():SameAccount(mine, guid)
end

local function itemName(item)
	if ns.Wishlist and ns.Wishlist.ItemName then return (ns.Wishlist.ItemName(item)) end
	local info = compat().Item.Info(item)
	return info and info.name or tostring(item)
end

-- The answers held, by post id.
local function answersByPost()
	local out = {}
	for id, rec in pairs(store():Records(Board.SET)) do
		local kind = Board.Parse(id)
		if kind == "D" then
			local post = postIdOf(id)
			out[post] = out[post] or {}
			out[post][#out[post] + 1] = rec
		end
	end
	return out
end

-- What the viewer may do with a row now: { { action, guid? } }; the first one is the next step.
function Board.Allowed(row)
	local out = {}
	local function add(action, guid) out[#out + 1] = { action = action, guid = guid } end
	if row.state ~= "open" then return out end
	if row.mine then
		for _, a in ipairs(row.answers) do
			if row.with ~= a.guid then add("confirm", a.guid) end
		end
		if row.with then add("unconfirm", row.with) end
		add("withdraw")
		return out
	end
	local my = row.my
	if not my then
		add("deal")
	elseif my.state == "want" then
		add("confirm", my.guid)
		add("drop", my.guid)
	else
		add("unconfirm", my.guid)
		add("drop", my.guid)
	end
	return out
end

-- One post as the views use it, or nil for a record that is not a post. `answers` may be given (a whole list at once).
-- row.state: "open" | "closed" | "withdrawn" | "expired" | "left"
function Board:Row(p, t, answers)
	local kind, author = Board.Parse(type(p) == "table" and p.id or nil)
	if kind ~= "P" then return nil end
	t = t or now()
	answers = answers or answersByPost()[p.id] or {}
	local list, closed, closedAt, my = {}, nil, nil, nil
	for _, d in ipairs(answers) do
		local _, _, _, guid = Board.Parse(d.id)
		local at = Board.ClosedAt(p, d)
		if at then closed, closedAt = guid, at end
		local member = not rosterRead() or entryOf(guid) ~= nil
		if d.state ~= "withdrawn" and (member or at) then
			local e = entryOf(guid)
			local a = { guid = guid, name = nameOf(guid), state = d.state, note = d.note, time = d.time or 0,
				online = e ~= nil and e.online == true }
			-- a confirmation written after the post expired does not count
			if a.state == "done" and a.time > p["until"] then a.state = "want" end
			list[#list + 1] = a
			if own(guid) and (not my or a.time > my.time) then my = a end
		end
	end
	sort(list, function(a, b) if a.time ~= b.time then return a.time < b.time end return a.guid < b.guid end)
	local state = "open"
	if closed then state = "closed"
	elseif p.state == "withdrawn" then state = "withdrawn"
	elseif t >= p["until"] then state = "expired"
	elseif rosterRead() and not entryOf(author) then state = "left" end
	local e = entryOf(author)
	local with = p.state == "done" and p.time <= p["until"] and p.with or nil
	local row = {
		id = p.id, rec = p, author = author, authorName = nameOf(author), online = e ~= nil and e.online == true,
		kind = p.kind, item = p.item, itemName = itemName(p.item), count = p.count, price = p.price, note = p.note,
		untilAt = p["until"], left = max(0, p["until"] - t), state = state, closedWith = closed,
		closedName = closed and nameOf(closed) or nil, closedAt = closedAt, with = with,
		withName = with and nameOf(with) or nil, answers = list, my = my, mine = own(author),
		posted = p.time or 0,
	}
	row.actions = Board.Allowed(row)
	return row
end

function Board:Get(id)
	if not (Board.Enabled() and inGuild() and id) then return nil end
	return self:Row(store():Get(Board.SET, id))
end

-- Every post held, with its answers, unsorted.
local function rows(t)
	local out = {}
	if not (Board.Enabled() and inGuild()) then return out end
	t = t or now()
	local answers = answersByPost()
	for id, rec in pairs(store():Records(Board.SET)) do
		local row = Board:Row(rec, t, answers[id] or {})
		if row then out[#out + 1] = row end
	end
	return out
end

-- The items "Only what I can help with" keeps: a function of a row.
local function helper()
	local wanted, owned = {}, {}
	if ns.Wishlist and ns.Wishlist.Enabled() then
		for _, e in ipairs((ns.Wishlist:Own())) do wanted[e.item] = true end
	end
	if ns.Shopping and ns.Shopping.Enabled() then
		for _, r in ipairs(ns.Shopping:Compute().rows) do wanted[r.item] = true end
	end
	return function(row)
		if row.mine or row.state ~= "open" then return false end
		if row.kind == "wts" then return wanted[row.item] == true end
		if owned[row.item] == nil then
			owned[row.item] = ns.Inventory ~= nil and ns.Inventory.Enabled() and ns.Inventory:Count(row.item).owned > 0
		end
		return owned[row.item]
	end
end

-- The open posts and the closed deals, hidden authors left out: open first, authors online first, the newest first.
function Board:List(opts)
	opts = opts or {}
	local needle = type(opts.search) == "string" and opts.search ~= "" and opts.search:lower() or nil
	local helps = opts.help and helper() or nil
	local out = {}
	for _, row in ipairs(rows(opts.t)) do
		local keep = (row.state == "open" or row.state == "closed") and (row.mine or not self:IsHidden(row.author))
		if keep and (opts.side == "wts" or opts.side == "wtb") then keep = row.kind == opts.side end
		if keep and helps then keep = helps(row) end
		if keep and needle then
			keep = row.itemName:lower():find(needle, 1, true) ~= nil or row.authorName:lower():find(needle, 1, true) ~= nil
		end
		if keep then out[#out + 1] = row end
	end
	sort(out, function(a, b)
		if a.state ~= b.state then return a.state == "open" end
		if a.online ~= b.online then return a.online end
		if a.posted ~= b.posted then return a.posted > b.posted end
		return a.id < b.id
	end)
	return out
end

-- The open posts of the player's account.
function Board:OpenCount()
	local n = 0
	for _, row in ipairs(rows()) do
		if row.mine and row.state == "open" then n = n + 1 end
	end
	return n
end

-- The open posts of one character (the member card).
function Board:OfMember(guid)
	local out = {}
	for _, row in ipairs(self:List()) do
		if row.author == guid and row.state == "open" then out[#out + 1] = row end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------------------------------
local function put(id, fields)
	local t = now()
	written = recent(written, t)
	if #written >= Board.WRITES_PER_HOUR then return nil, "rate" end
	local rec, why = store():Put(Board.SET, id, fields)
	if rec then written[#written + 1] = t end
	return rec, why
end

local function nextNumber(author)
	local e = econ()
	local highest = e and tonumber(e.boardNext) or 0
	for id in pairs(store():Records(Board.SET)) do
		local kind, guid, n = Board.Parse(id)
		if kind == "P" and guid == author and n > highest then highest = n end
	end
	return highest + 1
end

local function ready()
	if not Board.Enabled() then return false, "off" end
	if not (me() and inGuild()) then return false, "guild" end
	return true
end

-- A new post of the connected character. Why: "off", "guild", "kind", "item", "count", "price", "note", "days",
-- "limit" (MAX_OPEN), "rate", or a reason of Store:Put.
function Board:Post(spec)
	local ok, why = ready()
	if not ok then return nil, why end
	spec = type(spec) == "table" and spec or {}
	if not KINDS[spec.kind] then return nil, "kind" end
	if not int(spec.item, 1, 2147483647) then return nil, "item" end
	local count = spec.count == nil and 1 or tonumber(spec.count)
	if not int(count, 1, Board.QTY_MAX) then return nil, "count" end
	local days = spec.days == nil and Board.DAYS or tonumber(spec.days)
	if not int(days, 1, Board.DAYS_MAX) then return nil, "days" end
	local price, note = Board.Clean(spec.price), Board.Clean(spec.note)
	if #price > Board.PRICE_MAX then return nil, "price" end
	if #note > Board.NOTE_MAX then return nil, "note" end
	if self:OpenCount() >= Board.MAX_OPEN then return nil, "limit" end
	local author = me()
	local n = nextNumber(author)
	local rec, w = put(Board.PostId(author, n), { kind = spec.kind, item = spec.item, count = count,
		price = price ~= "" and price or nil, note = note ~= "" and note or nil,
		["until"] = floor(now() + days * DAY), state = "open" })
	if not rec then return nil, w end
	local e = econ()
	if e then e.boardNext = n end
	return rec
end

-- One step of one side. `guid` names the other side when the author confirms. Why: "off", "guild", "missing", "state"
-- (not a step this account may take now), "note", "rate", or a reason of Store:Put.
function Board:Act(id, action, guid, note)
	local ok, why = ready()
	if not ok then return false, why end
	local row = self:Get(id)
	if not row then return false, "missing" end
	local allowed = nil
	for _, a in ipairs(row.actions) do
		if a.action == action and (guid == nil or a.guid == nil or a.guid == guid) then allowed = allowed or a end
	end
	if not allowed then return false, "state" end
	note = Board.Clean(note)
	if #note > Board.NOTE_MAX then return false, "note" end
	local rec, w
	if row.mine then
		local fields = store().Copy(row.rec)
		fields.id, fields.author, fields.rev, fields.time, fields.with = nil, nil, nil, nil, nil
		if action == "withdraw" then fields.state = "withdrawn"
		elseif action == "confirm" then fields.state, fields.with = "done", allowed.guid
		else fields.state = "open" end
		if note ~= "" then fields.note = note end
		rec, w = put(id, fields)
	else
		local answerId = Board.AnswerId(id, action == "deal" and me() or allowed.guid)
		local held = store():Get(Board.SET, answerId)
		local state = action == "confirm" and "done" or action == "drop" and "withdrawn" or "want"
		local kept = note ~= "" and note or (action ~= "deal" and held and held.note) or nil
		rec, w = put(answerId, { state = state, note = kept or nil })
	end
	if not rec then return false, w end
	return rec
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
-- Counts only (SPEC-09 §6).
function Board:DebugLines()
	local posts, answers, open = 0, 0, 0
	for id in pairs(inGuild() and store():Records(Board.SET) or {}) do
		local kind = Board.Parse(id)
		if kind == "P" then posts = posts + 1 elseif kind == "D" then answers = answers + 1 end
	end
	for _, row in ipairs(rows()) do if row.state == "open" then open = open + 1 end end
	local reasons = {}
	for why, n in pairs(store().stats.bySet[Board.SET] or {}) do reasons[#reasons + 1] = why .. " " .. n end
	sort(reasons)
	return { ("Board: %d post(s) (%d open), %d answer(s), %d waiting for their post, %d author(s) hidden here; refused: %s"):format(
		posts, open, answers, #Board.waiting, self:HiddenCount(), #reasons > 0 and concat(reasons, ", ") or "none") }
end

function Board:Reset() Board.waiting = {} end

local function onStoreChanged(set, id)
	if set ~= Board.SET then return end
	local kind = Board.Parse(id)
	if not kind then return emit("BOARD_CHANGED", nil) end
	local postId = kind == "D" and postIdOf(id) or id
	if kind == "P" and #Board.waiting > 0 then Board.Retry(postId) end
	emit("BOARD_CHANGED", postId)
end

if ns.addon then
	ns.addon.Board = Board
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", onStoreChanged)
		ns.Bus:On("GUILD_CHANGED", function() Board:Reset() end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if Board.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Board", function() return Board:DebugLines() end)
			end
		end)
	end
end

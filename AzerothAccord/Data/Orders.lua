-- Orders: the craft orders of the guild, one record per side (M13.2; SPEC-17 §3, ORD-01..ORD-06; SPEC-06 PRO-05;
-- SPEC-10 Q40..Q42, Q50; ADR 0028). Lua 5.1.
--
-- The set `orders` is an ordinary set of the guild (GUILD, with the summary kind `ec`, SPEC-17 §10.2) with two records:
--   O:<buyer GUID>:<n>  the order, written only by the buyer's account: { crafter, recipe, item?, count 1..MAX_COUNT,
--                       mats = buyer | crafter | mixed, price? (text), note?, by? (day YYYYMMDD), created,
--                       state = open | received | cancelled, closed (a time, with a state other than open) }
--   A:<buyer GUID>:<n>  the crafter's side of that order, written only by the crafter's account: { crafter,
--                       state = accepted | declined | working | ready | handed, note?, at }
-- Nobody writes the other side (ORD-01), officers included. After the first write only `state`, `note` and `closed` of an
-- order change (ORD-03), and a state only moves forward (ORD-04). A crafter part that arrives before its order waits for it
-- (ORD-05). A receiver takes at most WRITES_PER_HOUR revisions of one author an hour (ORD-06).
-- The state shown is never written: every client derives it from the two records in the same way (Orders.State), and an
-- order is delivered only when both sides confirmed it (ECO-03). Accord never moves gold or items (ECO-01): nothing here
-- calls the game's trade, mail, auction, bank or crafting-order functions.
--
--   Orders.ValidRecord(rec, store)   the owner rule of the set: true, or false and "owner" | "wait" | "locked"
--   Orders.Transition(held, rec)     ORD-03, ORD-04: true, or false and "locked"
--   Orders.State(o, a, t)            "requested" | "accepted" | "progress" | "ready" | "delivered" | "cancelled", and
--                                    { why = "cancelled" | "declined" | "expired", missing = "buyer" | "crafter",
--                                      closed = the time it closed }
--   Orders:Row(o, t), Orders:Get(id) an order as the views use it (with the names, the sides and the allowed actions)
--   Orders:List(opts)                opts = { who = "forme" | "mine" | "all", closed, search }
--   Orders:Create(spec)              spec = { crafter, recipe, item?, count, mats, price?, note?, by?, from? (an earlier
--                                    request of M3) }: the record, or nil and why
--   Orders:Act(id, action, note)     "accept" | "decline" | "working" | "ready" | "handed" (crafter), "received" |
--                                    "cancel" (buyer): the record written, or false and why
--   Orders:Earlier(t)                the craft requests of M3 still offered as orders (SPEC-17 §3.6)
--   Orders:Dismiss(ask)              such a request is not offered again
-- Switch: Core/Features.lua "econ" (store def `feature = "econ"`). Bus: ORDERS_CHANGED(id).
local ADDON_NAME, ns = ...
ns = ns or {}
local Orders = {}
ns.Orders, ns.modules = Orders, ns.modules or {}
ns.modules.Orders = Orders

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, max, min = math.floor, math.max, math.min
local sort = table.sort
local DAY, HOUR = 86400, 3600

Orders.SET = "orders"
Orders.MAX_COUNT = 200
Orders.MAX_OPEN = 10             -- open orders of one buyer, counting its account (SPEC-10 Q41)
Orders.REQUEST_DAYS = 14         -- an order nobody accepted expires
Orders.BY_GRACE = 7              -- days after `by` without a delivery
Orders.STALE_DAYS = 60           -- an order without `by`, accepted or confirmed by one side, with no step (SPEC-10 Q50)
Orders.KEEP_DAYS = 30            -- a closed order and its part
Orders.BY_MAX = 60               -- `by` at most this many days after the day the order is written
Orders.PRICE_MAX = 24            -- bytes
Orders.NOTE_MAX = 80             -- bytes
Orders.ORDER_BYTES = 512         -- estimated size of an order record (Config.EstimateSize)
Orders.PART_BYTES = 384
Orders.WRITES_PER_HOUR = 30      -- ORD-06
Orders.WAIT = 600                -- ORD-05: seconds a part waits for its order
Orders.WAIT_MAX = 200            -- parts that wait at once (a first exchange brings every part before its order)
Orders.NOTICE_WAIT = 3           -- seconds of the chat lines while the switch `actions` is off
Orders.MAX_LINES = 3
Orders.VISIBLE_TO = "everyone"   -- SPEC-10 Q40: "everyone", or "parties" (the buyer, the crafter and their alts)
Orders.MATS = { "buyer", "crafter", "mixed" }
Orders.RANK = { accepted = 1, working = 2, ready = 3, handed = 4 }   -- the crafter's states; "declined" ends them
Orders.MOVES = { accept = "accepted", decline = "declined", working = "working", ready = "ready", handed = "handed",
	received = "received", cancel = "cancelled" }

local MATS = { buyer = true, crafter = true, mixed = true }
local ORDER_STATES = { open = true, received = true, cancelled = true }
local ORDER_FIELDS = { id = true, author = true, rev = true, time = true, crafter = true, recipe = true, item = true,
	count = true, mats = true, price = true, note = true, by = true, created = true, state = true, closed = true }
local PART_FIELDS = { id = true, author = true, rev = true, time = true, crafter = true, state = true, note = true, at = true }
local LOCKED = { "crafter", "recipe", "item", "count", "mats", "price", "by", "created" }

local function store() return ns.Store end
local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function me() return compat() and compat().Player.GUID() or nil end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function inGuild() return ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil end

function Orders.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

local function isGUID(g) return type(g) == "string" and #g <= 40 and g:find(store().GUID_PATTERN) ~= nil end
local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end

---------------------------------------------------------------------------------------------------------------------
-- Texts, days and ids
---------------------------------------------------------------------------------------------------------------------
-- A price or a note: no control characters and no "|" (SPEC-15 §4.4), trimmed.
function Orders.Clean(value)
	if type(value) ~= "string" then return "" end
	value = value:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return value
end

local function validText(v, limit)
	return v == nil or (type(v) == "string" and v ~= "" and #v <= limit and not v:find("[%c|]"))
end

local function dayNumber(day) return ns.Timeline.DayNumber(day) end

-- The day typed as "YYYY-MM-DD", or nil.
function Orders.ParseDay(text)
	if type(text) ~= "string" then return nil end
	local y, m, d = text:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
	if not y then return nil end
	local day = tonumber(y) * 10000 + tonumber(m) * 100 + tonumber(d)
	return dayNumber(day) and day or nil
end

function Orders.DayText(day)
	if type(day) ~= "number" then return "?" end
	return ("%04d-%02d-%02d"):format(floor(day / 10000), floor(day / 100) % 100, day % 100)
end

-- "O" or "A", the buyer's GUID and the number of an order or part id; nil for anything else.
function Orders.Parse(id)
	if type(id) ~= "string" then return nil end
	local kind, buyer, n = id:match("^([OA]):(Player%-%d+%-%x+):([1-9]%d*)$")
	if not kind or #buyer > 40 or #n > 9 then return nil end
	return kind, buyer, tonumber(n)
end

function Orders.KindOf(rec) return type(rec) == "table" and (Orders.Parse(rec.id)) or nil end
function Orders.OrderId(buyer, n) return "O:" .. tostring(buyer) .. ":" .. tostring(n) end
function Orders.PartId(id) return "A" .. tostring(id):sub(2) end
local function orderIdOf(partId) return "O" .. tostring(partId):sub(2) end

---------------------------------------------------------------------------------------------------------------------
-- Trust: the rules Net/Store.lua applies (ORD-01..ORD-04)
---------------------------------------------------------------------------------------------------------------------
local function onlyFields(rec, fields)
	for k in pairs(rec) do if not fields[k] then return false end end
	return true
end

local function validOrder(rec, s, buyer)
	if not (onlyFields(rec, ORDER_FIELDS) and isGUID(rec.crafter)) then return false end
	if not s:SameAccount(buyer, rec.author) or s:SameAccount(buyer, rec.crafter) then return false end
	if not (int(rec.recipe, 1, 2147483647) and (rec.item == nil or int(rec.item, 1, 2147483647))) then return false end
	if not (int(rec.count, 1, Orders.MAX_COUNT) and MATS[rec.mats]) then return false end
	if not (validText(rec.price, Orders.PRICE_MAX) and validText(rec.note, Orders.NOTE_MAX)) then return false end
	if not (type(rec.created) == "number" and rec.created > 0 and type(rec.time) == "number" and rec.created <= rec.time) then
		return false
	end
	if rec.by ~= nil then
		local by, first = dayNumber(rec.by), floor(rec.created / DAY)
		if not (by and by >= first and by <= first + Orders.BY_MAX) then return false end
	end
	if not ORDER_STATES[rec.state] then return false end
	if rec.state == "open" then return rec.closed == nil end
	return type(rec.closed) == "number" and rec.closed >= rec.created and rec.closed <= rec.time
end

function Orders.ValidRecord(rec, s)
	s = s or store()
	if type(rec) ~= "table" then return false, "owner" end
	local kind, buyer = Orders.Parse(rec.id)
	if kind == "O" then
		if not validOrder(rec, s, buyer) or ns.Config.EstimateSize(rec) > Orders.ORDER_BYTES then return false, "owner" end
		return true
	end
	if kind ~= "A" then return false, "owner" end
	if not (onlyFields(rec, PART_FIELDS) and isGUID(rec.crafter) and (Orders.RANK[rec.state] or rec.state == "declined")
		and validText(rec.note, Orders.NOTE_MAX) and type(rec.at) == "number" and rec.at > 0 and type(rec.time) == "number"
		and rec.at <= rec.time and s:SameAccount(rec.crafter, rec.author)
		and ns.Config.EstimateSize(rec) <= Orders.PART_BYTES) then
		return false, "owner"
	end
	local order = s:Get(Orders.SET, orderIdOf(rec.id))
	if not order then return false, "wait" end                          -- ORD-05
	if order.crafter ~= rec.crafter then return false, "locked" end     -- ORD-03
	return true
end

function Orders.Transition(held, rec)
	local kind = Orders.KindOf(rec)
	if type(held) ~= "table" or store().Compare(rec, held) <= 0 then return true end   -- the store keeps the one it holds
	if kind == "O" then
		for _, key in ipairs(LOCKED) do
			if rec[key] ~= held[key] then return false, "locked" end
		end
		if held.state ~= "open" and (rec.state ~= held.state or rec.closed ~= held.closed) then return false, "locked" end
		return true
	end
	if rec.crafter ~= held.crafter then return false, "locked" end
	if held.state == "declined" or held.state == "handed" then
		if rec.state ~= held.state then return false, "locked" end
		return true
	end
	if rec.state == "declined" then return true end
	if (Orders.RANK[rec.state] or 0) < (Orders.RANK[held.state] or 0) then return false, "locked" end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The state both sides give (SPEC-17 §3.2, §3.4)
---------------------------------------------------------------------------------------------------------------------
-- The time at which an order that is not delivered expires, or nil.
local function deadline(o, a)
	local t = nil
	if o.by then
		local by = dayNumber(o.by)
		if by then t = (by + 1 + Orders.BY_GRACE) * DAY end
	end
	if o.state == "open" and not a then
		local first = (o.created or 0) + Orders.REQUEST_DAYS * DAY
		t = t and min(t, first) or first
	elseif not t then
		t = max(o.created or 0, o.closed or 0, a and a.at or 0) + Orders.STALE_DAYS * DAY
	end
	return t
end

function Orders.State(o, a, t)
	if a and a.crafter ~= o.crafter then a = nil end
	local last = max(o.closed or 0, a and a.at or 0)
	if o.state == "cancelled" then return "cancelled", { why = "cancelled", closed = last } end
	if a and a.state == "declined" then return "cancelled", { why = "declined", closed = last } end
	local received, handed = o.state == "received", a ~= nil and a.state == "handed"
	if received and handed then return "delivered", { closed = last } end
	local limit = deadline(o, a)
	if limit and (t or now()) >= limit then return "cancelled", { why = "expired", closed = limit } end
	if received then return "ready", { missing = "crafter" } end
	if handed then return "ready", { missing = "buyer" } end
	if not a then return "requested", {} end
	if a.state == "working" then return "progress", {} end
	return a.state, {}
end

-- ORD-05: the parts that arrived before their order, tried again when it does.
Orders.waiting = {}

local function waitingPart(partId)
	for _, w in ipairs(Orders.waiting) do
		if w.rec.id == partId then return w.rec end
	end
	return nil
end

function Orders.Wait(rec, ctx)
	local list = Orders.waiting
	for i = #list, 1, -1 do
		if list[i].rec.id == rec.id then table.remove(list, i) end
	end
	list[#list + 1] = { rec = store().Copy(rec), sender = ctx and ctx.sender, dist = ctx and ctx.dist, at = compat().Now() }
	while #list > Orders.WAIT_MAX do table.remove(list, 1) end
end

-- Tries the part of order `orderId` again. Returns true when it was taken.
function Orders.Retry(orderId)
	local list, partId = Orders.waiting, Orders.PartId(orderId)
	for i = 1, #list do
		local w = list[i]
		if w.rec.id == partId then
			table.remove(list, i)
			if compat().Now() - w.at > Orders.WAIT then return false end
			return store():Accept(Orders.SET, w.rec, { sender = w.sender, dist = w.dist }) == true
		end
	end
	return false
end

-- Retention: a closed order and its part go KEEP_DAYS after it closed. Both are judged on what the store holds (it prunes
-- after judging every record), or on the part that waits for its order (a sync sends the parts first, "A:" before "O:"). An
-- order the buyer closed whose part is not known goes KEEP_DAYS after the buyer's closing: so a delivery already deleted
-- here does not come back as a delivery confirmed by one side.
function Orders.Expired(rec, t)
	local kind = Orders.KindOf(rec)
	if not kind then return true end
	local s, limit = store(), t - Orders.KEEP_DAYS * DAY
	local o, a
	if kind == "O" then
		o, a = rec, s:Get(Orders.SET, Orders.PartId(rec.id)) or waitingPart(Orders.PartId(rec.id))
		if not a and o.state ~= "open" then return (o.closed or 0) < limit end
	else
		o, a = s:Get(Orders.SET, orderIdOf(rec.id)), rec
		if not o then return (rec.at or 0) < limit end
	end
	local _, info = Orders.State(o, a, t)
	return info.closed ~= nil and info.closed < limit
end

---------------------------------------------------------------------------------------------------------------------
-- Rate (ORD-06)
---------------------------------------------------------------------------------------------------------------------
local received, written = {}, {}   -- author -> times (received); the times this client wrote a record

local function recent(list, t)
	local keep = {}
	for _, at in ipairs(list or {}) do if at > t - HOUR then keep[#keep + 1] = at end end
	return keep
end

-- The rate rule of a received revision (Net/Store.lua `rate`): a revision written within the last hour counts against its
-- author; true while the author stays within WRITES_PER_HOUR.
function Orders.Within(rec)
	if type(rec) ~= "table" then return true end
	local t, at = now(), rec.time or 0
	if at <= t - HOUR then return true end
	local list = recent(received[rec.author], t)
	received[rec.author] = list
	if #list >= Orders.WRITES_PER_HOUR then return false end
	list[#list + 1] = at
	return true
end

function Orders:ResetRates() received, written = {}, {} end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function entryOf(guid) return ns.Roster and ns.Roster:ByGUID(guid) or nil end
local function rosterRead() return ns.Roster ~= nil and ns.Roster:Count() > 0 end

local function nameOf(guid)
	local e = entryOf(guid)
	return e and (e.short or e.name) or "?"
end
Orders.NameOf = nameOf

-- true for a character of the player's own account.
local function own(guid)
	local mine = me()
	return mine ~= nil and store():SameAccount(mine, guid)
end

-- "Flask of the Titans", or "Recipe 1234" while the game has not given the name.
function Orders.RecipeName(id)
	return ns.Recipes and ns.Recipes.NameOf(id) or ns.L["RV_RECIPE_ID"]:format(tostring(id))
end

-- What the viewer may do with a row now; the first one is the next step.
function Orders.Allowed(row)
	local out = {}
	if not row.open then return out end
	local o, a = row.rec, row.part
	if row.mine then
		if o.state == "open" then
			if a then out[#out + 1] = "received" end
			out[#out + 1] = "cancel"
		end
	elseif row.forMe then
		local step = a and a.state
		if step == "handed" then return out end
		if o.state == "received" then return { "handed" } end
		if not step then return { "accept", "decline" } end
		if step == "accepted" then return { "working", "ready", "handed", "decline" } end
		if step == "working" then return { "ready", "handed", "decline" } end
		return { "handed", "decline" }
	end
	return out
end

-- One order as the views use it, or nil for a record that is not an order.
function Orders:Row(o, t)
	local kind, buyer = Orders.Parse(type(o) == "table" and o.id or nil)
	if kind ~= "O" then return nil end
	t = t or now()
	local a = store():Get(Orders.SET, Orders.PartId(o.id))
	if a and a.crafter ~= o.crafter then a = nil end
	local state, info = Orders.State(o, a, t)
	local why, closed = info.why, info.closed
	-- SPEC-17 §3.4: a side that left the guild, once the roster was read
	if state ~= "delivered" and state ~= "cancelled" and rosterRead() and not (entryOf(buyer) and entryOf(o.crafter)) then
		state, why = "cancelled", "left"
	end
	local row = {
		id = o.id, rec = o, part = a, state = state, why = why, missing = info.missing, closed = closed, buyer = buyer,
		crafter = o.crafter, recipe = o.recipe, count = o.count, mats = o.mats, price = o.price, created = o.created,
		buyerName = nameOf(buyer), crafterName = nameOf(o.crafter), recipeName = Orders.RecipeName(o.recipe),
		mine = own(buyer), forMe = own(o.crafter), open = state ~= "delivered" and state ~= "cancelled",
		changed = max(o.time or 0, a and a.time or 0),
	}
	row.actions = Orders.Allowed(row)
	return row
end

local function visible(row)
	return Orders.VISIBLE_TO == "everyone" or row.mine or row.forMe
end

-- Every order held that this player is shown, unsorted.
local function rows(t)
	local out = {}
	if not (Orders.Enabled() and inGuild()) then return out end
	t = t or now()
	for _, rec in pairs(store():Records(Orders.SET)) do
		local row = Orders:Row(rec, t)
		if row and visible(row) then out[#out + 1] = row end
	end
	return out
end

local function newer(a, b)
	if a.open ~= b.open then return a.open end
	local ta, tb = a.open and a.created or a.closed or a.created, b.open and b.created or b.closed or b.created
	if ta ~= tb then return (ta or 0) > (tb or 0) end
	return a.id < b.id
end

function Orders:Get(id)
	if not (Orders.Enabled() and inGuild()) then return nil end
	local row = id and self:Row(store():Get(Orders.SET, id))
	if row and visible(row) then return row end
	return nil
end

function Orders:List(opts)
	opts = opts or {}
	local needle = type(opts.search) == "string" and opts.search ~= "" and opts.search:lower() or nil
	local out = {}
	for _, row in ipairs(rows(opts.t)) do
		local keep = opts.closed or row.open
		if opts.who == "forme" then keep = keep and row.forMe
		elseif opts.who == "mine" then keep = keep and row.mine end
		if keep and needle then
			keep = row.recipeName:lower():find(needle, 1, true) ~= nil or row.buyerName:lower():find(needle, 1, true) ~= nil
				or row.crafterName:lower():find(needle, 1, true) ~= nil
		end
		if keep then out[#out + 1] = row end
	end
	sort(out, newer)
	return out
end

-- The open orders of the player's account as a buyer (ORD-06; an order the buyer confirmed is not counted).
function Orders:OpenCount()
	local n = 0
	for _, row in ipairs(rows()) do
		if row.mine and row.open and row.rec.state == "open" then n = n + 1 end
	end
	return n
end

-- How many open orders ask for each recipe: { [recipe id] = n } (the recipe catalogue).
function Orders:OpenByRecipe()
	local out = {}
	for _, row in ipairs(rows()) do
		if row.open then out[row.recipe] = (out[row.recipe] or 0) + 1 end
	end
	return out
end

-- The open orders of one character: those it placed and those it has to craft (the member card).
function Orders:OfMember(guid)
	local buying, crafting = {}, {}
	for _, row in ipairs(self:List()) do
		if row.buyer == guid then buying[#buying + 1] = row end
		if row.crafter == guid then crafting[#crafting + 1] = row end
	end
	return buying, crafting
end

-- true when the player may order from `guid`: a member of the guild that is not a character of the own account.
function Orders:CanOrder(guid)
	return Orders.Enabled() and inGuild() and isGUID(guid) and entryOf(guid) ~= nil and not own(guid)
end

-- Who can be asked for a recipe: the members who know it, online first, never the own account.
-- { { guid, name, online } }; `chosen` is kept even when no list says it knows the recipe.
function Orders:CraftersOf(recipe, chosen)
	local out, seen = {}, {}
	local function add(guid)
		if seen[guid] or not self:CanOrder(guid) then return end
		seen[guid] = true
		local e = entryOf(guid)
		out[#out + 1] = { guid = guid, name = nameOf(guid), online = e.online == true }
	end
	for _, group in ipairs(ns.Crafters and (ns.Crafters:Who(recipe)) or {}) do
		for _, m in ipairs(group.members) do add(m.guid) end
	end
	if chosen then add(chosen) end
	sort(out, function(a, b)
		if a.online ~= b.online then return a.online end
		if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
		return a.guid < b.guid
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Local data (GuildKey:Data().econ: never sent)
---------------------------------------------------------------------------------------------------------------------
local function econ()
	local data = inGuild() and ns.GuildKey:Data() or nil
	if not data then return nil end
	if type(data.econ) ~= "table" then data.econ = {} end
	return data.econ
end

local function sub(key)
	local e = econ()
	if not e then return nil end
	if type(e[key]) ~= "table" then e[key] = {} end
	return e[key]
end

---------------------------------------------------------------------------------------------------------------------
-- The craft requests of M3 (SPEC-17 §3.6)
---------------------------------------------------------------------------------------------------------------------
local function askKey(a) return a.guid .. ":" .. a.recipeId .. ":" .. a.at end

-- The reminders of the last days that were not turned into an order or dismissed, newest first. Never published by
-- themselves: each stays a line of this computer until the player acts on it.
function Orders:Earlier(t)
	local out = {}
	if not (Orders.Enabled() and inGuild() and ns.Recipes) then return out end
	local data = ns.GuildKey:Data()
	local done = type(data.econ) == "table" and data.econ.migrated or nil
	t = t or now()
	for _, a in ipairs(type(data.craftAsks) == "table" and data.craftAsks or {}) do
		if type(a) == "table" and type(a.guid) == "string" and type(a.recipeId) == "number" and type(a.at) == "number"
			and t - a.at < ns.Recipes.ASK_DAYS * DAY and not (done and done[askKey(a)]) and self:CanOrder(a.guid) then
			out[#out + 1] = { guid = a.guid, recipeId = a.recipeId, at = a.at, name = nameOf(a.guid),
				recipeName = Orders.RecipeName(a.recipeId) }
		end
	end
	sort(out, function(a, b) if a.at ~= b.at then return a.at > b.at end return askKey(a) < askKey(b) end)
	return out
end

function Orders:Dismiss(ask)
	local done = type(ask) == "table" and ask.at and sub("migrated")
	if not done then return false end
	local limit = now() - (ns.Recipes.ASK_DAYS + 1) * DAY
	for key, at in pairs(done) do if type(at) ~= "number" or at < limit then done[key] = nil end end
	done[askKey(ask)] = ask.at
	ns.Recipes:ForgetAsk(ask.guid, ask.recipeId)
	emit("ORDERS_CHANGED", nil)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------------------------------
local function put(id, fields)
	local t = now()
	written = recent(written, t)
	if #written >= Orders.WRITES_PER_HOUR then return nil, "rate" end
	local rec, why = store():Put(Orders.SET, id, fields)
	if rec then written[#written + 1] = t end
	return rec, why
end

local function nextNumber(buyer)
	local e = econ()
	local highest = e and tonumber(e.next) or 0
	for id in pairs(store():Records(Orders.SET)) do
		local _, guid, n = Orders.Parse(id)
		if guid == buyer and n > highest then highest = n end
	end
	return highest + 1
end

-- Places an order (the buyer is the connected character). Why: "off", "guild", "crafter" (not a member), "own" (the own
-- account), "recipe", "count", "mats", "price", "note", "by", "limit" (MAX_OPEN), "rate", or a reason of Store:Put.
function Orders:Create(spec)
	if not Orders.Enabled() then return nil, "off" end
	local buyer = me()
	if not (buyer and inGuild()) then return nil, "guild" end
	spec = type(spec) == "table" and spec or {}
	local crafter = spec.crafter
	if not (isGUID(crafter) and entryOf(crafter)) then return nil, "crafter" end
	if own(crafter) then return nil, "own" end
	if not int(spec.recipe, 1, 2147483647) then return nil, "recipe" end
	local count = spec.count == nil and 1 or tonumber(spec.count)
	if not int(count, 1, Orders.MAX_COUNT) then return nil, "count" end
	local mats = spec.mats or "buyer"
	if not MATS[mats] then return nil, "mats" end
	local price, note = Orders.Clean(spec.price), Orders.Clean(spec.note)
	if #price > Orders.PRICE_MAX then return nil, "price" end
	if #note > Orders.NOTE_MAX then return nil, "note" end
	local t = now()
	local by = spec.by
	if type(by) == "string" then
		if by:match("^%s*$") then by = nil
		else
			by = Orders.ParseDay(by)
			if not by then return nil, "by" end
		end
	end
	if by ~= nil then
		local n, today = dayNumber(by), floor(t / DAY)
		if not (n and n >= today and n <= today + Orders.BY_MAX) then return nil, "by" end
	end
	if self:OpenCount() >= Orders.MAX_OPEN then return nil, "limit" end
	local n = nextNumber(buyer)
	local item = spec.item
	if item == nil then   -- what the recipe creates, when the game says it (locked after this write)
		local mats = ns.Reagents and ns.Reagents:Ensure(spec.recipe)
		item = mats and mats.out or nil
	end
	local rec, why = put(Orders.OrderId(buyer, n), { crafter = crafter, recipe = spec.recipe, item = item, count = count,
		mats = mats, price = price ~= "" and price or nil, note = note ~= "" and note or nil, by = by, created = t, state = "open" })
	if not rec then return nil, why end
	local e = econ()
	if e then e.next = n end
	if spec.from then self:Dismiss(spec.from) end
	emit("CRAFT_REQUESTED", crafter, spec.recipe)
	return rec
end

-- One step of one side. Why: "off", "missing", "owner" (neither side is this account's), "state" (not a step this side may
-- take now), "note", "rate", or a reason of Store:Put.
function Orders:Act(id, action, note)
	if not Orders.Enabled() then return false, "off" end
	local row = self:Get(id)
	if not row then return false, "missing" end
	if not (row.mine or row.forMe) then return false, "owner" end
	local allowed = false
	for _, a in ipairs(row.actions) do if a == action then allowed = true end end
	if not allowed then return false, "state" end
	note = Orders.Clean(note)
	if #note > Orders.NOTE_MAX then return false, "note" end
	local t = now()
	local rec, why
	if row.mine then
		local fields = store().Copy(row.rec)
		fields.id, fields.author, fields.rev, fields.time = nil, nil, nil, nil
		fields.state, fields.closed = Orders.MOVES[action], t
		if note ~= "" then fields.note = note end
		rec, why = put(id, fields)
	else
		local held = row.part
		rec, why = put(Orders.PartId(id), { crafter = row.crafter, state = Orders.MOVES[action], at = t,
			note = note ~= "" and note or (held and held.note) or nil })
	end
	if not rec then return false, why end
	return rec
end

---------------------------------------------------------------------------------------------------------------------
-- The Action Center (SPEC-17 §3.7)
---------------------------------------------------------------------------------------------------------------------
local function openOrder(id)
	return function() if ns.OrdersView then ns.OrdersView:Open(id) end end
end

-- The buyer closed the row of a declined or expired order.
function Orders:Done(id)
	local done = sub("done")
	if not done then return false end
	done[id] = now()
	emit("ORDERS_CHANGED", id)
	return true
end

function Orders:ActionRows(t)
	local L, out = ns.L, {}
	t = t or now()
	local data = inGuild() and ns.GuildKey:Data() or nil
	local done = data and type(data.econ) == "table" and data.econ.done or {}
	for _, row in ipairs(rows(t)) do
		local id = row.id
		local function add(prefix, urgency, who, title, dismiss)
			out[#out + 1] = { key = prefix .. ":" .. id, urgency = urgency, time = row.changed, who = who, title = title,
				mark = row.state, open = openOrder(id), dismiss = dismiss }
		end
		if row.forMe and row.state == "requested" then
			add("new", 2, row.buyerName, L["ORD_ACT_NEW"]:format(row.buyerName, row.count, row.recipeName))
		elseif row.forMe and row.state == "ready" and row.missing == "crafter" then
			add("confirm", 2, row.buyerName, L["ORD_ACT_CONFIRM"]:format(row.recipeName))
		elseif row.mine and row.state == "ready" and row.missing == "buyer" then
			add("confirm", 2, row.crafterName, L["ORD_ACT_CONFIRM"]:format(row.recipeName))
		elseif row.mine and row.state == "ready" and not row.missing then
			add("ready", 2, row.crafterName, L["ORD_ACT_READY"]:format(row.crafterName, row.recipeName))
		elseif row.mine and (row.why == "declined" or row.why == "expired") and not done[id] then
			add("closed", 1, row.crafterName,
				L[row.why == "declined" and "ORD_ACT_DECLINED" or "ORD_ACT_EXPIRED"]:format(row.recipeName),
				function() Orders:Done(id) end)
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Notices (SPEC-17 §3.7): once per order and state, also after a /reload or another login
---------------------------------------------------------------------------------------------------------------------
-- The notification centre when the switch `actions` is on, else nil.
local function centre()
	local N = ns.Notify
	return N and N.Enabled() and N or nil
end

-- What this character was told: the book of Data/Notify.lua, or GuildKey:Data().econ.seen without the centre.
local function seenBook()
	if not inGuild() then return nil end
	local N = centre()
	if N then return N:Seen("orders") end
	return sub("seen")
end

-- The notices an order gives this account now: { key, kind, step, text, args }.
local function noticesOf(row)
	local out = {}
	local function add(kind, step, text, ...)
		out[#out + 1] = { key = row.id .. ":" .. step, kind = kind, step = step, text = text, args = { ... } }
	end
	if row.state == "delivered" then
		if row.mine or row.forMe then add("delivered", "delivered", "ORD_NOTE_DELIVERED", row.count, row.recipeName) end
	elseif row.forMe and row.state == "requested" then
		add("new", "requested", "ORD_NOTE_NEW", row.buyerName, row.count, row.recipeName)
	elseif row.mine and row.part and row.rec.state == "open" and (row.open or row.why == "declined") then
		local step = row.part.state
		add("state", step, "ORD_NOTE_" .. step:upper(), row.crafterName, row.recipeName)
	end
	return out
end

local chat = { pending = {}, timer = false, epoch = 0 }

local function flushChat()
	chat.timer = false
	local list = chat.pending
	chat.pending = {}
	if #list == 0 or not ns.addon then return end
	for i = 1, min(#list, Orders.MAX_LINES) do ns.addon:Print(list[i]) end
	if #list > Orders.MAX_LINES then ns.addon:Print(ns.L["NOTICE_MORE"]:format(#list - Orders.MAX_LINES)) end
end

local function say(text)
	chat.pending[#chat.pending + 1] = text
	if chat.timer then return end
	chat.timer = true
	local epoch = chat.epoch
	local scheduled = compat().After(Orders.NOTICE_WAIT, function() if epoch == chat.epoch then flushChat() end end)
	if not scheduled then flushChat() end
end

function Orders:Notices(id)
	if not Orders.Enabled() then return 0 end
	local book, row = seenBook(), self:Get(id)
	if not (book and row) then return 0 end
	local N, posted = centre(), 0
	for _, n in ipairs(noticesOf(row)) do
		if not book[n.key] then
			book[n.key] = true
			posted = posted + 1
			if N then
				local step = n.step
				N:Post("orders", n.kind, { key = n.key, text = n.text, args = n.args, view = "market", page = "orders",
					still = function()
						local held = Orders:Get(id)
						if not held then return false end
						if step == "requested" then return held.state == "requested" end
						if step == "delivered" then return true end
						return held.part ~= nil and held.part.state == step
					end })
			else
				say(ns.L[n.text]:format(unpack(n.args)))
			end
		end
	end
	return posted
end

-- The first run of a guild: everything held counts as seen. The keys of orders that are gone are dropped.
function Orders:Baseline()
	if not Orders.Enabled() then return end
	local book = seenBook()
	if not book then return end
	local s = store()
	for key in pairs(book) do
		local id = type(key) == "string" and key:match("^(O:[^:]+:%d+):")
		if id and not s:Get(Orders.SET, id) then book[key] = nil end
	end
	local done = sub("done")
	for id in pairs(done or {}) do if not s:Get(Orders.SET, id) then done[id] = nil end end
	if book.__baseline then return end
	for _, row in ipairs(rows()) do
		for _, n in ipairs(noticesOf(row)) do book[n.key] = true end
	end
	book.__baseline = true
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
-- Counts only (SPEC-09 §6).
function Orders:DebugLines()
	local orders, parts, open = 0, 0, 0
	for _, rec in pairs(inGuild() and store():Records(Orders.SET) or {}) do
		local kind = Orders.KindOf(rec)
		if kind == "O" then orders = orders + 1 elseif kind == "A" then parts = parts + 1 end
	end
	for _, row in ipairs(rows()) do if row.open then open = open + 1 end end
	local reasons = {}
	for why, n in pairs(store().stats.bySet[Orders.SET] or {}) do reasons[#reasons + 1] = why .. " " .. n end
	sort(reasons)
	return { ("Orders: %d order(s) (%d open), %d crafter part(s), %d waiting for their order; refused: %s"):format(orders, open,
		parts, #Orders.waiting, #reasons > 0 and table.concat(reasons, ", ") or "none") }
end

function Orders:Reset()
	Orders.waiting = {}
	chat.pending, chat.timer, chat.epoch = {}, false, chat.epoch + 1
end

if ns.Actions then
	ns.Actions:Register("orders", { label = "ACT_PROVIDER_ORDERS", order = 22, feature = "econ",
		events = { "ORDERS_CHANGED", "ROSTER_UPDATED", "ACCOUNTS_UPDATED", "RECIPE_NAMES_UPDATED" },
		items = function(t) return Orders:ActionRows(t) end })
end

if ns.Notify then
	ns.Notify:Register("orders", { label = "ACT_PROVIDER_ORDERS", order = 22, feature = "econ",
		open = function(entry)
			local id = type(entry.key) == "string" and entry.key:match("^(O:[^:]+:%d+):") or nil
			if ns.OrdersView then ns.OrdersView:Open(id) end
		end,
		kinds = {
			{ id = "new", level = "normal", off = "SET_NOTICE_ORDERS_NEW", group = "ORD_NOTICE_NEW_MANY" },
			{ id = "state", level = "normal", off = "SET_NOTICE_ORDERS_STATE", group = "ORD_NOTICE_STATE_MANY" },
			{ id = "delivered", level = "normal", off = "SET_NOTICE_ORDERS_DELIVERED", group = "ORD_NOTICE_DELIVERED_MANY" },
		} })
end

local function onStoreChanged(set, id)
	if set ~= Orders.SET then return end
	local kind = Orders.Parse(id)
	if not kind then return emit("ORDERS_CHANGED", nil) end
	local orderId = kind == "A" and orderIdOf(id) or id
	if kind == "O" and #Orders.waiting > 0 then Orders.Retry(orderId) end
	emit("ORDERS_CHANGED", orderId)
	Orders:Notices(orderId)
end

if ns.addon then
	ns.addon.Orders = Orders
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", onStoreChanged)
		ns.Bus:On("GUILD_CHANGED", function(key)
			Orders:Reset()
			if key then Orders:Baseline() end
		end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Orders.Enabled() then return end
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Orders", function() return Orders:DebugLines() end) end
			Orders:Baseline()
		end)
	end
end

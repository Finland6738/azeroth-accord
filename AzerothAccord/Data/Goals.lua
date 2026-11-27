-- Goals: the guild goals, collective targets in materials or gold, with the progress read from the bank logs (M13.9;
-- SPEC-17 §7; SPEC-10 Q48, Q56; ADR 0028 point 7). Lua 5.1.
--
-- The set `goals` is an ordinary set of the guild (GUILD, with the summary kind `ec`, SPEC-17 §10.2), one record per goal:
--   G:<n>   { kind = items | gold, item (item id, items only), target (units, or copper in whole gold coins),
--             start, ends (days YYYYMMDD, UTC), title, note?, state = open | cancelled }
-- Written only by Goals.WRITERS (officers and the Guild Master, Q48) and passed on only by officers (NET-12, `authorAny`:
-- a goal stays valid after its officer was demoted). After the first write `kind`, `item`, `target` and `start` do not
-- change, `ends` only moves later and a cancelled goal stays cancelled ("locked").
-- The progress is never written: every client adds up the deposits of the merged bank logs it may see (Data/BankLog.lua)
-- from the first moment of `start` to the last of `ends` (UTC days; the log times are rounded, BANK-10). Withdrawals and
-- repairs are not subtracted. A goal is REACHED when the progress gets to the target and ENDED after the day `ends`,
-- both without a write. The game's logs are short (BankLog keeps 150 entries per record), so a client remembers, on this
-- computer only, that it saw a goal reached: it does not open again when old entries leave the logs (Q56).
-- Retention: a record goes KEEP_DAYS after the day `ends`, or after it was cancelled: from the record alone, so every
-- client drops it at the same time. Accord never moves gold or items (ECO-01): nothing here calls the game.
--
--   Goals.CanWrite()                      the connected character may write goals
--   Goals.ValidRecord(rec)                the owner rule of the set (the shape)
--   Goals.Transition(held, rec)           true, or false and "locked"
--   Goals:List(opts)                      opts = { closed, search, t }: the open goals, or those closed in the last
--                                         KEEP_DAYS; Goals:Get(id), Goals:OpenCount()
--       a row: { id, rec, kind, item, itemName, title, note, target, have, fraction, start, ends, daysLeft,
--         state = open | reached | ended | cancelled, closedAt, reachedAt, contributors? = { { name, classFile, amount } },
--         tabsSeen, tabsTotal, logAt, stale, canEdit }
--   Goals:Demand(t)                       { { id, item, missing, title } } of the open item goals (Data/Demand.lua)
--   Goals:Create(spec)                    spec = { kind, item, target (units, or gold coins), days?, title, note? }
--   Goals:Edit(id, spec)                  spec = { title?, note?, days? (from today to the new end) }
--   Goals:Cancel(id)
-- Switch: Core/Features.lua "econ" (store def `feature = "econ"`). Bus: GOALS_CHANGED(id), nil = the progress of any.
local ADDON_NAME, ns = ...
ns = ns or {}
local Goals = {}
ns.Goals, ns.modules = Goals, ns.modules or {}
ns.modules.Goals = Goals

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, max, min = math.floor, math.max, math.min
local sort, concat = table.sort, table.concat
local DAY = 86400

Goals.SET = "goals"
Goals.WRITERS = "officers"           -- SPEC-10 Q48, the one place
Goals.KINDS = { "items", "gold" }
Goals.MAX_OPEN = 5
Goals.DAYS = 30                      -- how long a new goal lasts by default
Goals.DAYS_MAX = 180
Goals.ITEMS_MAX = 100000
Goals.GOLD_MAX = 1000000             -- gold coins
Goals.COPPER = 10000                 -- copper in a gold coin
Goals.TITLE_MAX = 40                 -- bytes
Goals.NOTE_MAX = 120                 -- bytes
Goals.BYTES = 448                    -- estimated size of a record (Config.EstimateSize)
Goals.KEEP_DAYS = 90                 -- after the end, or after the cancellation
Goals.STALE = 7 * DAY                -- an older newest log mutes the bar
Goals.TOP = 3                        -- contributors shown
Goals.NOTICE_AGE = 7 * DAY           -- a goal reached longer ago gives no notice
Goals.DELAY = 1                      -- seconds the changes of the bank are collected

local KINDS = { items = true, gold = true }
local STATES = { open = true, cancelled = true }
local FIELDS = { id = true, author = true, rev = true, time = true, kind = true, item = true, target = true,
	start = true, ends = true, title = true, note = true, state = true }
local LOCKED = { "kind", "item", "target", "start" }

local function store() return ns.Store end
local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function me() return compat() and compat().Player.GUID() or nil end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function inGuild() return ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil end

function Goals.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

function Goals.CanWrite()
	if Goals.WRITERS == "officers" then return ns.Role ~= nil and ns.Role:IsOfficer() end
	return false
end

local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end

---------------------------------------------------------------------------------------------------------------------
-- Days and texts
---------------------------------------------------------------------------------------------------------------------
local function dayNumber(day) return ns.Timeline.DayNumber(day) end
local function dayOf(t) return ns.Timeline.DayOf(t) end

-- The first second of a day (YYYYMMDD, UTC), or nil.
function Goals.DayStart(day)
	local n = dayNumber(day)
	return n and n * DAY or nil
end

-- A title or a note: no control characters and no "|" (SPEC-15 §4.4), trimmed.
function Goals.Clean(value)
	if type(value) ~= "string" then return "" end
	value = value:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return value
end

local function validText(v, limit)
	return type(v) == "string" and v ~= "" and #v <= limit and not v:find("[%c|]")
end

---------------------------------------------------------------------------------------------------------------------
-- Trust: the rules Net/Store.lua applies
---------------------------------------------------------------------------------------------------------------------
function Goals.Number(id)
	local n = type(id) == "string" and #id <= 14 and id:match("^G:([1-9]%d*)$")
	return n and tonumber(n) or nil
end

function Goals.ValidRecord(rec)
	if type(rec) ~= "table" or not Goals.Number(rec.id) then return false end
	for k in pairs(rec) do if not FIELDS[k] then return false end end
	if rec.kind == "items" then
		if not (int(rec.item, 1, 2147483647) and int(rec.target, 1, Goals.ITEMS_MAX)) then return false end
	elseif rec.kind == "gold" then
		if rec.item ~= nil or not int(rec.target, Goals.COPPER, Goals.GOLD_MAX * Goals.COPPER)
			or rec.target % Goals.COPPER ~= 0 then
			return false
		end
	else
		return false
	end
	local first, last = dayNumber(rec.start), dayNumber(rec.ends)
	if not (first and last and last - first >= 1 and last - first <= Goals.DAYS_MAX) then return false end
	if not validText(rec.title, Goals.TITLE_MAX) then return false end
	if rec.note ~= nil and not validText(rec.note, Goals.NOTE_MAX) then return false end
	if not STATES[rec.state] or type(rec.time) ~= "number" then return false end
	return ns.Config.EstimateSize(rec) <= Goals.BYTES
end

function Goals.Transition(held, rec)
	if type(held) ~= "table" or store().Compare(rec, held) <= 0 then return true end   -- the store keeps the one it holds
	if held.rev == 1 and rec.rev == 1 then return true end   -- two goals made in the same second: the newer one wins
	for _, key in ipairs(LOCKED) do
		if rec[key] ~= held[key] then return false, "locked" end
	end
	if rec.rev > held.rev then   -- two writes of one revision: the newer wins on every client
		if rec.ends < held.ends then return false, "locked" end
		if held.state == "cancelled" and rec.state ~= "cancelled" then return false, "locked" end
	end
	return true
end

-- The time a record stops being open whatever the logs say: its cancellation, or the end of the day `ends`.
local function recordEnd(rec)
	if rec.state == "cancelled" then return rec.time or 0 end
	local at = Goals.DayStart(rec.ends)
	return at and at + DAY or 0
end

function Goals.Expired(rec, t)
	if not Goals.Number(type(rec) == "table" and rec.id) then return true end
	return recordEnd(rec) < t - Goals.KEEP_DAYS * DAY
end

---------------------------------------------------------------------------------------------------------------------
-- The bank logs
---------------------------------------------------------------------------------------------------------------------
-- What this client may count: the merged entries (one read for a whole list), how many tabs of items have a log it may
-- see, how many tabs the bank has, and the time of the newest log of money and of items.
local function logs()
	local ctx = { entries = {}, tabsSeen = 0, tabsTotal = 0 }
	local Log, Bank = ns.BankLog, ns.Bank
	if not (Log and Bank) then return ctx end
	ctx.entries = Log:Entries()
	local seen = {}
	for _, rec in pairs(store():Records("bank")) do
		if type(rec) == "table" and type(rec.tab) == "number" and rec.del ~= true then
			if rec.tab > ctx.tabsTotal then ctx.tabsTotal = rec.tab end
			if rec.kind == "log" and (rec.tab == Log.MONEY_TAB or Bank:CanSee(rec)) then
				local key = rec.tab == Log.MONEY_TAB and "goldAt" or "itemsAt"
				ctx[key] = max(ctx[key] or 0, rec.time or 0)
				if rec.tab ~= Log.MONEY_TAB and not seen[rec.tab] then
					seen[rec.tab] = true
					ctx.tabsSeen = ctx.tabsSeen + 1
				end
			end
		end
	end
	local game = compat().Bank and compat().Bank.NumTabs and compat().Bank.NumTabs()
	if type(game) == "number" and game > ctx.tabsTotal then ctx.tabsTotal = game end
	return ctx
end

-- The deposits that count for a goal: have, the time of the entry that reached the target (or nil), the amount by account.
local function count(rec, ctx)
	local Log = ns.BankLog
	local from, to = Goals.DayStart(rec.start), Goals.DayStart(rec.ends)
	local gold = rec.kind == "gold"
	local list = {}
	if from and to then
		for _, e in ipairs(ctx.entries) do
			if e.kind == "deposit" and e.count > 0 and e.t >= from and e.t < to + DAY then
				if (gold and e.tab == Log.MONEY_TAB) or (not gold and e.tab ~= Log.MONEY_TAB and e.itemID == rec.item) then
					list[#list + 1] = e
				end
			end
		end
	end
	local have, reachedAt, by = 0, nil, {}
	for i = #list, 1, -1 do   -- the entries come newest first
		local e = list[i]
		have = have + e.count
		if not reachedAt and have >= rec.target then reachedAt = e.t end
		by[e.name] = (by[e.name] or 0) + e.count
	end
	return have, reachedAt, by
end

-- The amounts by name as amounts by account, the largest first.
local function contributors(by)
	local Log, byKey, list = ns.BankLog, {}, {}
	local names = {}
	for name in pairs(by) do names[#names + 1] = name end
	sort(names)
	for _, name in ipairs(names) do
		local key, shown, classFile = Log.AccountOf(name)
		local row = byKey[key]
		if not row then
			row = { key = key, name = shown, classFile = classFile, amount = 0 }
			byKey[key] = row
			list[#list + 1] = row
		end
		row.amount = row.amount + by[name]
	end
	sort(list, function(a, b)
		if a.amount ~= b.amount then return a.amount > b.amount end
		return a.key < b.key
	end)
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function econ()
	local data = inGuild() and ns.GuildKey:Data() or nil
	if not data then return nil end
	if type(data.econ) ~= "table" then data.econ = {} end
	return data.econ
end

-- The goals this client saw reached (never sent): a goal stays reached when its entries left the logs.
local function memory(rec, reachedAt)
	local e = econ()
	if not e then return reachedAt end
	if type(e.reached) ~= "table" then e.reached = {} end
	local sig = concat({ rec.kind, tostring(rec.item), tostring(rec.target), tostring(rec.start) }, ":")
	local held = e.reached[rec.id]
	if held and held.sig ~= sig then held = nil end
	if reachedAt then
		if not held or reachedAt < held.at then e.reached[rec.id] = { at = reachedAt, sig = sig } end
		return reachedAt
	end
	return held and held.at or nil
end

local function itemName(item)
	if ns.Wishlist and ns.Wishlist.ItemName then return (ns.Wishlist.ItemName(item)) end
	local info = compat().Item.Info(item)
	return info and info.name or tostring(item)
end

local function row(rec, t, ctx)
	local have, reachedAt, by = count(rec, ctx)
	local state
	if rec.state == "cancelled" then
		state, reachedAt = "cancelled", nil
	else
		reachedAt = memory(rec, reachedAt)
		if reachedAt then
			state, have = "reached", max(have, rec.target)
		elseif t >= recordEnd(rec) then
			state = "ended"
		else
			state = "open"
		end
	end
	local logAt = rec.kind == "gold" and ctx.goldAt or (rec.kind == "items" and ctx.itemsAt) or nil
	local last, today = dayNumber(rec.ends), dayNumber(dayOf(t))
	local out = {
		id = rec.id, rec = rec, kind = rec.kind, item = rec.item, title = rec.title, note = rec.note,
		itemName = rec.kind == "items" and itemName(rec.item) or nil,
		target = rec.target, have = have, fraction = min(1, have / rec.target), start = rec.start, ends = rec.ends,
		daysLeft = max(0, last - today), state = state, reachedAt = reachedAt,
		closedAt = state == "reached" and reachedAt or (state ~= "open" and recordEnd(rec)) or nil,
		tabsSeen = ctx.tabsSeen, tabsTotal = ctx.tabsTotal, logAt = logAt,
		stale = logAt == nil or t - logAt > Goals.STALE,
		canEdit = state == "open" and Goals.CanWrite(),
	}
	if ns.BankLog and ns.BankLog.DonationsVisible() then out.contributors = contributors(by) end
	return out
end

-- Every goal held, unsorted.
local function rows(t)
	local out = {}
	if not (Goals.Enabled() and inGuild()) then return out end
	t = t or now()
	local ctx
	for _, rec in pairs(store():Records(Goals.SET)) do
		if type(rec) == "table" and not rec.del and Goals.ValidRecord(rec) then
			ctx = ctx or logs()
			out[#out + 1] = row(rec, t, ctx)
		end
	end
	return out
end

-- The open goals, the nearest end first; with opts.closed those closed in the last KEEP_DAYS, the latest first.
function Goals:List(opts)
	opts = opts or {}
	local t = opts.t or now()
	local needle = type(opts.search) == "string" and opts.search ~= "" and opts.search:lower() or nil
	local out = {}
	for _, r in ipairs(rows(t)) do
		local keep
		if opts.closed then keep = r.state ~= "open" and r.closedAt >= t - Goals.KEEP_DAYS * DAY
		else keep = r.state == "open" end
		if keep and needle then
			keep = r.title:lower():find(needle, 1, true) ~= nil
				or (r.itemName ~= nil and r.itemName:lower():find(needle, 1, true) ~= nil)
		end
		if keep then out[#out + 1] = r end
	end
	sort(out, function(a, b)
		if opts.closed then
			if a.closedAt ~= b.closedAt then return a.closedAt > b.closedAt end
		elseif a.ends ~= b.ends then
			return a.ends < b.ends
		end
		return a.id < b.id
	end)
	return out
end

function Goals:Get(id)
	if not (Goals.Enabled() and inGuild() and id) then return nil end
	local rec = store():Get(Goals.SET, id)
	if not (rec and not rec.del and Goals.ValidRecord(rec)) then return nil end
	return row(rec, now(), logs())
end

function Goals:OpenCount() return #self:List() end

-- What the open item goals still need (Data/Demand.lua).
function Goals:Demand(t)
	local out = {}
	for _, r in ipairs(self:List({ t = t })) do
		if r.kind == "items" and r.target > r.have then
			out[#out + 1] = { id = r.id, item = r.item, missing = r.target - r.have, title = r.title }
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------------------------------
local function ready()
	if not Goals.Enabled() then return false, "off" end
	if not (me() and inGuild()) then return false, "guild" end
	if not Goals.CanWrite() then return false, "authority" end
	return true
end

local function texts(title, note)
	title, note = Goals.Clean(title), Goals.Clean(note)
	if title == "" or #title > Goals.TITLE_MAX then return nil, "title" end
	if #note > Goals.NOTE_MAX then return nil, "note" end
	return title, note ~= "" and note or nil
end

-- A new goal that starts today. Why: "off", "guild", "authority", "kind", "item", "target", "days", "title", "note",
-- "limit" (MAX_OPEN), or a reason of Store:Put.
function Goals:Create(spec)
	local ok, why = ready()
	if not ok then return nil, why end
	spec = type(spec) == "table" and spec or {}
	if not KINDS[spec.kind] then return nil, "kind" end
	local item, target = nil, tonumber(spec.target)
	if spec.kind == "items" then
		item = spec.item
		if not int(item, 1, 2147483647) then return nil, "item" end
		if not int(target, 1, Goals.ITEMS_MAX) then return nil, "target" end
	else
		if not int(target, 1, Goals.GOLD_MAX) then return nil, "target" end
		target = target * Goals.COPPER
	end
	local days = spec.days == nil and Goals.DAYS or tonumber(spec.days)
	if not int(days, 1, Goals.DAYS_MAX) then return nil, "days" end
	local title, note = texts(spec.title, spec.note)
	if not title then return nil, note end
	if self:OpenCount() >= Goals.MAX_OPEN then return nil, "limit" end
	local t = floor(now())
	local n = t
	while store():Get(Goals.SET, "G:" .. n) do n = n + 1 end
	return store():Put(Goals.SET, "G:" .. n, { kind = spec.kind, item = item, target = target, start = dayOf(t),
		ends = dayOf(t + days * DAY), title = title, note = note, state = "open" })
end

local function rewrite(id, change)
	local fields = store().Copy(store():Get(Goals.SET, id))
	fields.id, fields.author, fields.rev, fields.time = nil, nil, nil, nil
	for k, v in pairs(change) do fields[k] = v end
	if change.note == false then fields.note = nil end
	return store():Put(Goals.SET, id, fields)
end

local function editable(self, id)
	local ok, why = ready()
	if not ok then return nil, why end
	local r = self:Get(id)
	if not r then return nil, "missing" end
	if r.state ~= "open" then return nil, "state" end
	return r
end

-- Changes the title, the note and the end (later only) of an open goal. Why also: "missing", "state", "locked" (an end
-- earlier than the one held).
function Goals:Edit(id, spec)
	local r, why = editable(self, id)
	if not r then return nil, why end
	spec = type(spec) == "table" and spec or {}
	local title, note = texts(spec.title == nil and r.title or spec.title, spec.note == nil and r.note or spec.note)
	if not title then return nil, note end
	local ends = r.ends
	if spec.days ~= nil then
		local days = tonumber(spec.days)
		if not int(days, 0, Goals.DAYS_MAX) then return nil, "days" end
		ends = dayOf(now() + days * DAY)
		if ends < r.ends then return nil, "locked" end
		if dayNumber(ends) - dayNumber(r.start) > Goals.DAYS_MAX then return nil, "days" end
	end
	return rewrite(id, { title = title, note = note or false, ends = ends })
end

function Goals:Cancel(id)
	local r, why = editable(self, id)
	if not r then return nil, why end
	return rewrite(id, { state = "cancelled" })
end

---------------------------------------------------------------------------------------------------------------------
-- Notices (SPEC-17 §7.3): once per goal reached
---------------------------------------------------------------------------------------------------------------------
local function centre()
	local N = ns.Notify
	return N and N.Enabled() and N or nil
end

local function seenBook()
	if not inGuild() then return nil end
	local N = centre()
	if N then return N:Seen("goals") end
	local e = econ()
	if not e then return nil end
	if type(e.goalSeen) ~= "table" then e.goalSeen = {} end
	return e.goalSeen
end

-- Tells about the goals reached since the last look. Returns how many.
function Goals:Notices()
	if not Goals.Enabled() then return 0 end
	local book = seenBook()
	if not book then return 0 end
	local N, t, posted = centre(), now(), 0
	for _, r in ipairs(rows(t)) do
		if r.state == "reached" and not book[r.id] then
			book[r.id] = true
			if r.reachedAt >= t - Goals.NOTICE_AGE then
				posted = posted + 1
				if N then
					N:Post("goals", "reached", { key = r.id, text = "GOAL_NOTE_REACHED", args = { r.title }, view = "goals" })
				elseif ns.addon then
					ns.addon:Print(ns.L["GOAL_NOTE_REACHED"]:format(ns.Contacts and ns.Contacts.Escape(r.title) or r.title))
				end
			end
		end
	end
	return posted
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
-- Counts only (SPEC-09 §6).
function Goals:DebugLines()
	local by = { open = 0, reached = 0, ended = 0, cancelled = 0 }
	for _, r in ipairs(rows()) do by[r.state] = by[r.state] + 1 end
	local reasons = {}
	for why, n in pairs(store().stats.bySet[Goals.SET] or {}) do reasons[#reasons + 1] = why .. " " .. n end
	sort(reasons)
	return { ("Goals: %d open, %d reached, %d ended, %d cancelled; refused: %s"):format(by.open, by.reached, by.ended,
		by.cancelled, #reasons > 0 and concat(reasons, ", ") or "none") }
end

local pending, epoch = false, 0

-- The bank or the goals changed: after a pause the views and the demand take the new progress, and the notices go out.
function Goals:Changed()
	if pending or not Goals.Enabled() then return end
	pending = true
	local mine = epoch
	local function fire()
		if mine ~= epoch then return end
		pending = false
		Goals:Notices()
		emit("GOALS_CHANGED", nil)
	end
	if not (compat() and compat().After(Goals.DELAY, fire)) then fire() end
end

function Goals:Reset() pending, epoch = false, epoch + 1 end

if ns.Notify then
	ns.Notify:Register("goals", { label = "ACT_PROVIDER_GOALS", order = 23, feature = "econ",
		open = function(entry) if ns.GoalsView then ns.GoalsView:Open(entry.key) end end,
		kinds = { { id = "reached", level = "normal", off = "SET_NOTICE_GOALS_REACHED", group = "GOAL_NOTICE_REACHED_MANY" } } })
end

if ns.addon then
	ns.addon.Goals = Goals
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set == Goals.SET then
				emit("GOALS_CHANGED", id)
				Goals:Changed()
			elseif set == "bank" then
				Goals:Changed()
			end
		end)
		ns.Bus:On("GUILD_CHANGED", function(key)
			Goals:Reset()
			if key then Goals:Changed() end
		end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Goals.Enabled() then return end
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Goals", function() return Goals:DebugLines() end) end
			Goals:Changed()
		end)
	end
end

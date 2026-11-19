-- BankLog: the item and money logs of the guild bank, merged over time and over the guildmates who read them, the
-- donations per account and the guild's money over time (SPEC-08 BANK-10, BANK-11, BANK-12; ADR 0009 rule 3). Lua 5.1.
--
-- The game keeps a short, recent history of the bank (the item log of each tab and the money log) and only shows it at the
-- open vault. Each capture (Data/Bank.lua) hands the entries it read to BankLog:Capture, which keeps them in the record of
-- the character that read them: id "<GUID>:log:<tab>" (tab 0 is the money log), { kind = "log", tab, rank, restricted, e, n,
-- h }. `e` is the entries as text, "kind,name,itemID,count,time" separated by ";" (for the money log itemID is 0 and
-- `count` is the amount in copper). A capture is MERGED into the record already held, never replaced, so the history grows
-- beyond the game's: at most MAX_ENTRIES newest entries are kept per record and nothing older than a year.
--
-- Time (BANK-10): the game gives "years, months, days, hours ago" [verify S9]; the entry's time is the capture time minus
-- that age, rounded down to a bucket as coarse as the age is (an hour for the last two days, a day for the last two
-- months, a week beyond): two captures of the same entry then give the same time, and so the same key.
--
-- No duplicates: kind, name, item, count or amount and a time within one bucket make one event. The same event read by two
-- guildmates, or by one guildmate in two visits, is one entry; two identical events that the game shows as two entries in
-- one capture are two (an entry counts as often as the capture that saw it most, never the sum; Log.Merge).
--
-- Who may see what: the entries of a tab follow the rank rule of the snapshots of that tab (Bank:CanSee); the money log and
-- the donations list are visible to every member (SPEC-10 Q5 proposal, one switch: BankLog.DONATIONS_VISIBLE_TO).
--
-- Donations (BANK-11): the deposits of money and of items per ACCOUNT (the characters of a player together, Accounts:
-- AccountKey), over the last 30 days, the last 365 days and all the entries held.
--
-- Money over time (BANK-12): the money records that arrive (from any author) are kept as a short local history,
-- { time, money } at most every HISTORY_MIN seconds or when the amount changes, 500 points; MoneySeries gives it as bars.
local ADDON_NAME, ns = ...
ns = ns or {}
local Log = {}
ns.BankLog, ns.modules = Log, ns.modules or {}
ns.modules.BankLog = Log

local type, pairs, ipairs, tostring, tonumber, floor, max, min = type, pairs, ipairs, tostring, tonumber, math.floor, math.max, math.min
local concat, sort = table.concat, table.sort

Log.MAX_ENTRIES = 150
Log.MAX_TEXT = 9000
Log.MONEY_TAB = 0
Log.RETENTION = 365 * 86400
Log.HISTORY_MAX = 500
Log.HISTORY_MIN = 6 * 3600
Log.DONATIONS_VISIBLE_TO = "everyone"      -- SPEC-10 Q5: "everyone" (proposal) or "officers"

local function compat() return ns.Compat end
local function ownGUID() return compat() and compat().Player.GUID() or nil end
local function serverTime() return compat() and compat().ServerTime() or 0 end

---------------------------------------------------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------------------------------------------------
-- The time of an entry from its age, rounded as coarsely as the age (see the header). `at` is the capture time.
function Log.Bucket(at, years, months, days, hours)
	local ago = ((((tonumber(years) or 0) * 365) + ((tonumber(months) or 0) * 30) + (tonumber(days) or 0)) * 24 + (tonumber(hours) or 0)) * 3600
	if ago < 0 then ago = 0 end
	local unit = ago < 2 * 86400 and 3600 or (ago < 60 * 86400 and 86400 or 7 * 86400)
	return floor((at - ago) / unit) * unit
end

local function cleanName(name)
	return (tostring(name or ""):gsub("[,;|%c]", ""))
end

local function itemIDOf(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- The entries of a capture: from Compat.Bank.ItemLog(tab) (tab 1..8) or Compat.Bank.MoneyLog() (tab 0), at server time
-- `at`. Returns a list of { kind, name, itemID, count, t }; an entry without a name or a time is skipped.
function Log.FromGame(tab, rows, at)
	local out = {}
	for _, r in ipairs(rows or {}) do
		local kind = type(r.kind) == "string" and r.kind:match("^%a+$") and #r.kind <= 20 and r.kind or nil
		local name = cleanName(r.name)
		local hasTime = r.years or r.months or r.days or r.hours
		if kind and name ~= "" and hasTime then
			local entry = { kind = kind, name = name, t = Log.Bucket(at, r.years, r.months, r.days, r.hours) }
			if tab == Log.MONEY_TAB then
				entry.itemID, entry.count = 0, max(0, floor(tonumber(r.amount) or 0))
			else
				entry.itemID, entry.count = itemIDOf(r.itemLink), max(1, floor(tonumber(r.count) or 1))
			end
			if entry.itemID then out[#out + 1] = entry end
		end
	end
	return out
end

local function keyOf(e) return concat({ e.kind, e.name, e.itemID, e.count, e.t }, "|") end
Log.KeyOf = keyOf

local function order(a, b)
	if a.t ~= b.t then return a.t > b.t end
	return keyOf(a) < keyOf(b)
end

function Log.Encode(entries)
	local list = {}
	for _, e in ipairs(entries) do list[#list + 1] = e end
	sort(list, order)
	local parts = {}
	for i, e in ipairs(list) do parts[i] = ("%s,%s,%d,%d,%d"):format(e.kind, e.name, e.itemID, e.count, e.t) end
	return concat(parts, ";")
end

-- The reader does not trust the text. Returns the list, or nil and a reason ("shape", "size", "entry", "count").
function Log.Decode(text)
	if type(text) ~= "string" then return nil, "shape" end
	if #text > Log.MAX_TEXT then return nil, "size" end
	local out = {}
	if text == "" then return out end
	for part in (text .. ";"):gmatch("([^;]*);") do
		local kind, name, item, count, t = part:match("^(%a+),([^,;]+),(%d+),(%d+),(%d+)$")
		if not kind or #kind > 20 then return nil, "entry" end
		if #out >= Log.MAX_ENTRIES then return nil, "count" end
		out[#out + 1] = { kind = kind, name = name, itemID = tonumber(item), count = tonumber(count), t = tonumber(t) }
	end
	return out
end

-- How coarse the time of an entry is: its bucket unit (a week, a day or an hour), read from the time itself.
local function unitOf(t)
	if t % 604800 == 0 then return 604800 elseif t % 86400 == 0 then return 86400 end
	return 3600
end

-- The merge of two lists of entries (the same events seen in two captures, or by two guildmates): an entry counts as often
-- as the list that has it most often, never the sum. Two entries are the same event when kind, name, item and count agree
-- and their times are within one bucket (the game's own times are coarse and shift by an hour or a day from one capture
-- to the next); the merged entry keeps the earlier time. Deterministic: the lists are matched in time order.
function Log.Merge(a, b)
	local groups, bases = {}, {}
	local function add(list, which)
		for _, e in ipairs(list or {}) do
			local base = concat({ e.kind, e.name, e.itemID, e.count }, "|")
			local g = groups[base]
			if not g then
				g = { A = {}, B = {}, kind = e.kind, name = e.name, itemID = e.itemID, count = e.count }
				groups[base] = g
				bases[#bases + 1] = base
			end
			g[which][#g[which] + 1] = e.t
		end
	end
	add(a, "A"); add(b, "B")
	local out = {}
	for _, base in ipairs(bases) do
		local g = groups[base]
		sort(g.A); sort(g.B)
		local times, i, j = {}, 1, 1
		while i <= #g.A and j <= #g.B do
			local ta, tb = g.A[i], g.B[j]
			if math.abs(ta - tb) <= max(unitOf(ta), unitOf(tb)) then
				times[#times + 1] = min(ta, tb); i = i + 1; j = j + 1
			elseif ta < tb then
				times[#times + 1] = ta; i = i + 1
			else
				times[#times + 1] = tb; j = j + 1
			end
		end
		while i <= #g.A do times[#times + 1] = g.A[i]; i = i + 1 end
		while j <= #g.B do times[#times + 1] = g.B[j]; j = j + 1 end
		for _, t in ipairs(times) do out[#out + 1] = { kind = g.kind, name = g.name, itemID = g.itemID, count = g.count, t = t } end
	end
	sort(out, order)
	return out
end

-- The shape rule of a log record (Bank.ValidRecord).
function Log.ValidRecord(rec)
	if type(rec.tab) ~= "number" or rec.tab ~= floor(rec.tab) or rec.tab < 0 or rec.tab > 8 then return false end
	if rec.id ~= rec.author .. ":log:" .. rec.tab then return false end
	if rec.rank ~= nil and not (type(rec.rank) == "number" and rec.rank == floor(rec.rank) and rec.rank >= 0 and rec.rank <= 40) then return false end
	if type(rec.n) ~= "number" or rec.n ~= floor(rec.n) or rec.n < 0 or rec.n > Log.MAX_ENTRIES then return false end
	return Log.Decode(rec.e) ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- Publishing a capture
---------------------------------------------------------------------------------------------------------------------
-- Merges `entries` (tab 0 = the money log) into this character's record of that log and writes it when it changed.
-- Returns true, or false and "unchanged" or the reason it was not written.
function Log:Capture(tab, entries)
	local S, me, Bank = ns.Store, ownGUID(), ns.Bank
	if not (S and me and Bank) then return false, "player" end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local id = me .. ":log:" .. tab
	local old = S:Get("bank", id)
	local held = old and Log.Decode(old.e) or {}
	local merged = Log.Merge(held, entries)
	local cutoff = serverTime() - Log.RETENTION
	local kept = {}
	for _, e in ipairs(merged) do
		if e.t >= cutoff and #kept < Log.MAX_ENTRIES then kept[#kept + 1] = e end
	end
	local text = Log.Encode(kept)
	if old and old.e == text then return false, "unchanged" end
	if #kept == 0 then return false, "empty" end
	local officer = ns.Role and ns.Role:IsOfficer() or false
	local rec, why = S:Put("bank", id, {
		kind = "log", tab = tab, rank = tab > 0 and Bank.OwnRank() or nil, restricted = (tab > 0 and officer) or nil,
		e = text, n = #kept, h = ns.Hash and ns.Hash.Fast(text) or 0,
	})
	if not rec then return false, why end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The merged log
---------------------------------------------------------------------------------------------------------------------
local decoded = {}   -- record id -> { rev, e, list }
local function entriesOf(rec)
	local d = decoded[rec.id]
	if d and d.rev == rec.rev and d.e == rec.e then return d.list end
	local list = Log.Decode(rec.e) or {}
	decoded[rec.id] = { rev = rec.rev, e = rec.e, list = list }
	return list
end

-- Every entry this client may see, newest first, each event once: { tab, kind, name, itemID, count, t }. For tab 0 (the
-- money log) `count` is the amount in copper. The records of each log (one per guildmate who read it) are merged with
-- Log.Merge in the order of their ids. opts.tab keeps one log.
function Log:Entries(opts)
	opts = opts or {}
	local S, Bank = ns.Store, ns.Bank
	if not (S and Bank) then return {} end
	local byTab = {}
	for _, rec in pairs(S:Records("bank")) do
		if type(rec) == "table" and rec.kind == "log" and type(rec.tab) == "number" and rec.del ~= true
			and (opts.tab == nil or opts.tab == rec.tab) and (rec.tab == Log.MONEY_TAB or Bank:CanSee(rec)) then
			local list = byTab[rec.tab]
			if not list then list = {} byTab[rec.tab] = list end
			list[#list + 1] = rec
		end
	end
	local out = {}
	for tab, records in pairs(byTab) do
		sort(records, function(x, y) return x.id < y.id end)
		local merged = {}
		for _, rec in ipairs(records) do merged = Log.Merge(merged, entriesOf(rec)) end
		for _, e in ipairs(merged) do
			out[#out + 1] = { tab = tab, kind = e.kind, name = e.name, itemID = e.itemID, count = e.count, t = e.t }
		end
	end
	sort(out, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		if a.tab ~= b.tab then return a.tab < b.tab end
		return keyOf(a) < keyOf(b)
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Donations per account (BANK-11)
---------------------------------------------------------------------------------------------------------------------
Log.WINDOWS = { d30 = 30 * 86400, d365 = 365 * 86400, all = false }

-- Who may see the list: everybody, or officers only (SPEC-10 Q5).
function Log.DonationsVisible()
	if Log.DONATIONS_VISIBLE_TO == "officers" then return ns.Role ~= nil and ns.Role:IsOfficer() end
	return true
end

-- The account a name in a log belongs to: the key, the name to show and the class: from the roster and the account groups
-- (the main when it is in the guild), or the name itself for somebody who left.
local function accountOf(name)
	local R, A = ns.Roster, ns.Accounts
	local e = R and R:ByName(name)
	if e and type(e.guid) == "string" and not e.notInGuild then
		local key = A and A:AccountKey(e.guid) or e.guid
		local shown = e
		local main = A and A:MainOf(e.guid)
		if main and not main.hint and main.guid ~= e.guid then
			local m = R:ByGUID(main.guid)
			if m then shown = m end
		end
		return key, shown.short or shown.name or name, shown.classFile
	end
	return "name:" .. name:lower(), name, nil
end

-- { windows = ..., rows } : rows = { { key, name, classFile, gold (copper), items (units), deposits, place }, ... } for one
-- window ("d30", "d365", "all"), sorted by opts.sort ("gold" or "items"), ties sharing a place. Only deposits count.
function Log:Donations(opts)
	opts = opts or {}
	local window = Log.WINDOWS[opts.window or "d30"]
	if window == nil then window = Log.WINDOWS.d30 end
	local cutoff = window and (serverTime() - window) or nil
	local byKey, list = {}, {}
	for _, e in ipairs(self:Entries()) do
		if e.kind == "deposit" and (cutoff == nil or e.t >= cutoff) and e.count > 0 then
			local key, name, classFile = accountOf(e.name)
			local row = byKey[key]
			if not row then
				row = { key = key, name = name, classFile = classFile, gold = 0, items = 0, deposits = 0 }
				byKey[key] = row
				list[#list + 1] = row
			end
			if e.tab == Log.MONEY_TAB then row.gold = row.gold + e.count else row.items = row.items + e.count end
			row.deposits = row.deposits + 1
		end
	end
	local byItems = opts.sort == "items"
	sort(list, function(a, b)
		local pa, pb = byItems and a.items or a.gold, byItems and b.items or b.gold
		if pa ~= pb then return pa > pb end
		local sa, sb = byItems and a.gold or a.items, byItems and b.gold or b.items
		if sa ~= sb then return sa > sb end
		if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
		return a.key < b.key
	end)
	for i, row in ipairs(list) do
		local v, p = byItems and row.items or row.gold, list[i - 1]
		if p and v == (byItems and p.items or p.gold) then row.place = p.place else row.place = i end
	end
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- The money over time (BANK-12)
---------------------------------------------------------------------------------------------------------------------
local function history(create)
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.bank) ~= "table" then
		if not create then return nil end
		data.bank = {}
	end
	if type(data.bank.history) ~= "table" then
		if not create then return nil end
		data.bank.history = {}
	end
	return data.bank.history
end

-- Notes the money of a record (any author): a point { t, m } when the amount changed or HISTORY_MIN passed.
function Log:RecordMoney(rec)
	if type(rec) ~= "table" or rec.kind ~= "money" or type(rec.money) ~= "number" or type(rec.time) ~= "number" then return false end
	local h = history(true)
	if not h then return false end
	local at = #h + 1
	for i = #h, 1, -1 do
		if h[i].t == rec.time then return false end   -- this record is in already
		if h[i].t < rec.time then at = i + 1 break end
		at = i
	end
	local before, after = h[at - 1], h[at]
	if before and before.m == rec.money and rec.time - before.t < Log.HISTORY_MIN then return false end
	table.insert(h, at, { t = rec.time, m = floor(rec.money) })
	while #h > Log.HISTORY_MAX do table.remove(h, 1) end
	return true
end

function Log:History()
	return history(false) or {}
end

-- The money as `bars` values over the last `days` days, the last known amount at the end of each slice: { values = {
-- number | nil, ... } (n slices; read it with a numeric loop, the first ones can be nil), n, min, max, from, to }.
function Log:MoneySeries(days, bars)
	days, bars = days or 30, bars or 30
	local h = self:History()
	local to = serverTime()
	local from = to - days * 86400
	local step = (to - from) / bars
	local values, lo, hi = {}, nil, nil
	local i = 1
	local last
	for b = 1, bars do
		local endAt = from + b * step
		while h[i] and h[i].t <= endAt do last = h[i].m; i = i + 1 end
		values[b] = last
		if last then
			lo = lo and min(lo, last) or last
			hi = hi and max(hi, last) or last
		end
	end
	return { values = values, n = bars, min = lo, max = hi, from = from, to = to }
end

---------------------------------------------------------------------------------------------------------------------
-- Events and /accord debug
---------------------------------------------------------------------------------------------------------------------
function Log:Ingest()
	if not ns.Store then return end
	for _, rec in pairs(ns.Store:Records("bank")) do
		if type(rec) == "table" and rec.kind == "money" then self:RecordMoney(rec) end
	end
end

function Log:DebugLines()
	local S, logs, entries = ns.Store, 0, 0
	if S and ns.GuildKey and ns.GuildKey:Current() then
		for _, rec in pairs(S:Records("bank")) do
			if type(rec) == "table" and rec.kind == "log" then logs = logs + 1 entries = entries + (rec.n or 0) end
		end
	end
	return { ("BankLog: %d log record(s) with %d entries, %d money point(s)"):format(logs, entries, #self:History()) }
end

if ns.addon then
	ns.addon.BankLog = Log
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("BankLog", function() return Log:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set == "bank" then
				local rec = ns.Store and ns.Store:Get("bank", id)
				if rec and rec.kind == "money" then Log:RecordMoney(rec) end
			end
		end)
		ns.Bus:On("GUILD_CHANGED", function() decoded = {} end)
	end
	if ns.OnEnable then ns.OnEnable(function() if ns.GuildKey and ns.GuildKey:Current() then Log:Ingest() end end) end
end

-- BankRequests: withdrawal, deposit and donation requests to the guild bank, approved by officers (SPEC-08 BANK-20..BANK-22,
-- SPEC-03 §7, ADR 0009 rule 4, ADR 0005). Lua 5.1.
--
-- A request is a record of the set `bankreq`: id "<requester GUID>:<n>" (n counts the requests of that character) and
--
--   kind      "withdraw" (an item from the bank or gold), "deposit" (an item the requester offers), "donation" (a promise of
--             items or gold)
--   itemID, count   the item and how many, or
--   amount          gold in copper (not for a deposit)
--   tip             optional, only on a withdrawal of an item: whole gold pieces in copper, 1 to 10,000 gold (BANK-26). A
--                   promise: the member deposits it in the bank; the addon never moves gold. Older clients ignore it and
--                   keep it (a decision copies every field)
--   reason    up to 120 characters
--   status    open -> approved | rejected | fulfilled, cancelled (by the requester); see STATUS_RANK
--   note      the officer's reason for a rejection (up to 120 characters)
--   history   { { s = status, by = GUID, t = time }, ... } oldest first, at most 8
--   created   server time of the request
--
-- Who writes what (the Store checks it on every client, SPEC-02 §6): the requester or a character of the same account opens
-- or cancels (first hand); only officers move a request to approved, rejected or fulfilled (an authority record: the sender
-- and the author must be officers). An officer's decision is a new revision of the same id, written by the officer.
-- Everyone in the guild sees every request (BANK-21).
--
-- Order: two clients that hold different versions of one request keep the same one, the one with the highest status (open <
-- cancelled < approved < rejected < fulfilled), then the highest revision, time and author. So a decision of an officer
-- beats a cancel written at the same moment, and every client ends with the same status. The content of a request (kind,
-- item, count, amount, tip, requester) can never change after it was opened.
--
-- A withdrawal of an item can be picked from the bank as this character sees it (BANK-25): Req:BankItems sums the newest
-- snapshot of every visible tab, and what it shows caps the quantity of a new request (a received record is never checked
-- against the snapshots: every client holds different ones). Who sees a tip is a display rule (BANK-27, SPEC-10 Q16:
-- Req.TIP_VISIBLE_TO); the record itself reaches the whole guild.
--
-- Delivering the item stays manual (mail, trade or the vault): the addon only keeps the record (BANK-24).
local ADDON_NAME, ns = ...
ns = ns or {}
local Req = {}
ns.BankRequests, ns.modules = Req, ns.modules or {}
ns.modules.BankRequests = Req

local type, pairs, ipairs, tostring, tonumber, floor = type, pairs, ipairs, tostring, tonumber, math.floor
local sort = table.sort

Req.KINDS = { "withdraw", "deposit", "donation" }
Req.STATUS_RANK = { open = 1, cancelled = 2, approved = 3, rejected = 4, fulfilled = 5 }
Req.MOVES = {
	open = { approved = true, rejected = true, fulfilled = true, cancelled = true },
	approved = { fulfilled = true, rejected = true },
}
Req.MAX_REASON = 120
Req.MAX_OPEN = 5              -- open requests one character may have at once
Req.MAX_COUNT = 9999
Req.MAX_AMOUNT = 1000000000   -- copper: 100,000 gold
Req.MAX_HISTORY = 8
Req.COPPER_PER_GOLD = 10000
Req.MAX_TIP = 100000000       -- copper: 10,000 gold
Req.TIP_VISIBLE_TO = "officers"   -- SPEC-10 Q16: "officers" (officers, the GM and the requester) or "everyone"

local KIND = { withdraw = true, deposit = true, donation = true }

local function compat() return ns.Compat end
local function now() return compat() and compat().ServerTime() or 0 end
local function ownGUID() return compat() and compat().Player.GUID() or nil end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function isOfficer() return ns.Role ~= nil and ns.Role:IsOfficer() end

local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end
local function text(v, max) return type(v) == "string" and #v <= max end

-- The text of a reason or a note: no control characters and no "|" (which starts a link or a colour), trimmed, shortened.
function Req.CleanText(value)
	if type(value) ~= "string" then return "" end
	value = value:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return value:sub(1, Req.MAX_REASON)
end

-- The item id of an item link, or of a plain number written in the box; nil for anything else.
function Req.ParseItem(value)
	if type(value) == "number" then return int(value, 1, 2147483647) and value or nil end
	if type(value) ~= "string" then return nil end
	local id = value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$")
	id = tonumber(id)
	return id and int(id, 1, 2147483647) and id or nil
end

-- A tip: whole gold pieces, from 1 gold to MAX_TIP, in copper.
function Req.ValidTip(copper)
	return int(copper, Req.COPPER_PER_GOLD, Req.MAX_TIP) and copper % Req.COPPER_PER_GOLD == 0
end

---------------------------------------------------------------------------------------------------------------------
-- The rules the Store applies (Net/Store.lua)
---------------------------------------------------------------------------------------------------------------------
local function decision(status) return status == "approved" or status == "rejected" or status == "fulfilled" end

-- The shape of a record, and its owner rule: a decision only has to be well formed (its authority is checked by the
-- Store: sender and author are officers); an opening or a cancel must be written by the account of the requester.
function Req.ValidRecord(rec, store)
	if type(rec) ~= "table" or type(rec.requester) ~= "string" or type(rec.id) ~= "string" then return false end
	if not rec.requester:find("^Player%-%d+%-%x+$") then return false end
	local n = rec.id:match("^" .. rec.requester:gsub("%-", "%%-") .. ":(%d+)$")
	if not n or #n > 9 then return false end
	if not KIND[rec.kind] or not Req.STATUS_RANK[rec.status] then return false end
	if rec.reason ~= nil and not text(rec.reason, Req.MAX_REASON) then return false end
	if rec.note ~= nil and not text(rec.note, Req.MAX_REASON) then return false end
	if type(rec.created) ~= "number" then return false end
	local item = rec.itemID ~= nil
	if item then
		if not (int(rec.itemID, 1, 2147483647) and int(rec.count, 1, Req.MAX_COUNT) and rec.amount == nil) then return false end
	else
		if not (int(rec.amount, 1, Req.MAX_AMOUNT) and rec.count == nil) or rec.kind == "deposit" then return false end
	end
	if rec.tip ~= nil and not (item and rec.kind == "withdraw" and Req.ValidTip(rec.tip)) then return false end
	if type(rec.history) ~= "table" or #rec.history > Req.MAX_HISTORY then return false end
	for _, h in ipairs(rec.history) do
		if type(h) ~= "table" or not Req.STATUS_RANK[h.s] or type(h.by) ~= "string" or #h.by > 40 or type(h.t) ~= "number" then return false end
	end
	if decision(rec.status) then return true end
	return store ~= nil and type(rec.author) == "string" and store:SameAccount(rec.requester, rec.author)
end

-- The version to keep (SPEC-03 §7): 1 when `a` replaces `b`, -1 when `b` stays, 0 when they are the same.
function Req.Compare(a, b)
	if b == nil then return 1 end
	local ra, rb = Req.STATUS_RANK[a.status] or 0, Req.STATUS_RANK[b.status] or 0
	if ra ~= rb then return ra > rb and 1 or -1 end
	return ns.Store.Compare(a, b)
end

-- A new version must keep the content of the request it replaces.
function Req.Transition(held, rec)
	return held.requester == rec.requester and held.kind == rec.kind and held.itemID == rec.itemID and held.count == rec.count
		and held.amount == rec.amount and held.tip == rec.tip and held.created == rec.created
end

---------------------------------------------------------------------------------------------------------------------
-- The bank this character sees (BANK-25)
---------------------------------------------------------------------------------------------------------------------
-- What the newest snapshot of every tab this rank may see holds (Bank:Tabs): [itemID] = { itemID, available (the total over
-- the tabs), time and author of the OLDEST of the snapshots that hold it (the age to show) }.
function Req:BankItems()
	local out = {}
	for _, tab in ipairs(ns.Bank and ns.Bank:Tabs() or {}) do
		for _, it in ipairs(tab.items) do
			local e = out[it.itemID]
			if not e then
				e = { itemID = it.itemID, available = 0, time = tab.time, author = tab.author }
				out[it.itemID] = e
			elseif (tab.time or 0) < (e.time or 0) then
				e.time, e.author = tab.time, tab.author
			end
			e.available = e.available + it.count
		end
	end
	return out
end

-- The most a new request for this item may ask: what the visible snapshots hold, for a withdrawal of an item they show;
-- MAX_COUNT for anything else (a deposit, a donation, an item the snapshots do not show: the fallback of a pasted link).
function Req:MaxCount(kind, itemID, items)
	if kind ~= "withdraw" or not itemID then return Req.MAX_COUNT end
	local held = (items or self:BankItems())[itemID]
	if not held or held.available < 1 then return Req.MAX_COUNT end
	return math.min(held.available, Req.MAX_COUNT)
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function nameOf(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	return e and (e.short or e.name) or nil
end

local function sameAccount(guid)
	local me = ownGUID()
	return me ~= nil and ns.Store ~= nil and ns.Store:SameAccount(me, guid)
end

-- Whether this player is shown the tip of a request of `requester` (BANK-27, SPEC-10 Q16).
function Req:CanSeeTip(requester)
	return Req.TIP_VISIBLE_TO == "everyone" or isOfficer() or sameAccount(requester)
end

-- The requests as rows for a view: newest first. opts.status = a set { open = true, ... } (nil = all), opts.own = only the
-- requests of this player's account, opts.search filters by requester name, item name or reason.
--   { id, kind, status, requester, name, itemID, count, amount, tip (nil when this player may not see it), reason, note,
--     history, created, time, own, canCancel, moves = { "approved", ... } (what this officer may do next) }
function Req:List(opts)
	opts = opts or {}
	local S = ns.Store
	if not S then return {} end
	local officer = isOfficer()
	local out = {}
	for _, rec in pairs(S:Records("bankreq")) do
		if type(rec) == "table" and rec.del ~= true and Req.STATUS_RANK[rec.status] and type(rec.requester) == "string"
			and (opts.status == nil or opts.status[rec.status]) then
			local own = sameAccount(rec.requester)
			if not opts.own or own then
				local moves = {}
				if officer and Req.MOVES[rec.status] then
					for to in pairs(Req.MOVES[rec.status]) do if to ~= "cancelled" then moves[#moves + 1] = to end end
					sort(moves, function(a, b) return Req.STATUS_RANK[a] < Req.STATUS_RANK[b] end)
				end
				out[#out + 1] = {
					id = rec.id, kind = rec.kind, status = rec.status, requester = rec.requester, name = nameOf(rec.requester),
					itemID = rec.itemID, count = rec.count, amount = rec.amount, reason = rec.reason, note = rec.note,
					tip = self:CanSeeTip(rec.requester) and rec.tip or nil,
					history = rec.history or {}, created = rec.created, time = rec.time, own = own,
					canCancel = own and rec.status == "open", moves = moves,
				}
			end
		end
	end
	sort(out, function(a, b)
		if (a.created or 0) ~= (b.created or 0) then return (a.created or 0) > (b.created or 0) end
		return a.id < b.id
	end)
	return out
end

function Req:Get(id)
	for _, r in ipairs(self:List()) do if r.id == id then return r end end
	return nil
end

-- How many requests are open (waiting for an officer).
function Req:OpenCount()
	local n = 0
	for _, rec in pairs(ns.Store and ns.Store:Records("bankreq") or {}) do
		if type(rec) == "table" and rec.status == "open" and rec.del ~= true then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------------------------------
-- Opens a request: spec = { kind, itemID | amount, count, tip (copper; nil or 0 = none), reason }. Returns the record, or
-- false and a reason: "guild", "kind", "item" (a deposit needs one), "count", "stock" (more than the bank shows; a third
-- value gives the most it may ask), "amount", "tip" (not whole gold within MAX_TIP, or not on a withdrawal of an item),
-- "limit" (too many open requests), or the Store's reason.
function Req:Create(spec)
	local S, me = ns.Store, ownGUID()
	if not (S and me and ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	if type(spec) ~= "table" or not KIND[spec.kind] then return false, "kind" end
	local fields = { kind = spec.kind, requester = me, status = "open", created = now(), reason = Req.CleanText(spec.reason) }
	if spec.itemID ~= nil then
		local id = Req.ParseItem(spec.itemID)
		if not id then return false, "item" end
		if not int(spec.count, 1, Req.MAX_COUNT) then return false, "count" end
		local most = self:MaxCount(spec.kind, id)
		if spec.count > most then return false, "stock", most end
		fields.itemID, fields.count = id, spec.count
	else
		if spec.kind == "deposit" then return false, "item" end
		if not int(spec.amount, 1, Req.MAX_AMOUNT) then return false, "amount" end
		fields.amount = spec.amount
	end
	if spec.tip ~= nil and spec.tip ~= 0 then
		if not (spec.kind == "withdraw" and fields.itemID and Req.ValidTip(spec.tip)) then return false, "tip" end
		fields.tip = spec.tip
	end
	if fields.reason == "" then fields.reason = nil end
	local open, highest = 0, 0
	for id, rec in pairs(S:Records("bankreq")) do
		if type(rec) == "table" and rec.requester == me then
			local n = tonumber(id:match(":(%d+)$"))
			if n and n > highest then highest = n end
			if rec.status == "open" and rec.del ~= true then open = open + 1 end
		end
	end
	if open >= Req.MAX_OPEN then return false, "limit" end
	fields.history = { { s = "open", by = me, t = fields.created } }
	local rec, why = S:Put("bankreq", me .. ":" .. (highest + 1), fields)
	if not rec then return false, why end
	emit("BANKREQ_CHANGED", rec.id, "open")
	return rec
end

local function advance(id, status, note, by)
	local S = ns.Store
	local held = S and S:Get("bankreq", id)
	if not held or held.del == true then return false, "missing" end
	if not (Req.MOVES[held.status] and Req.MOVES[held.status][status]) then return false, "status" end
	local fields = S.Copy(held)
	fields.id, fields.author, fields.rev, fields.time = nil, nil, nil, nil
	fields.status = status
	if status == "rejected" then
		local n = Req.CleanText(note)
		fields.note = n ~= "" and n or nil
	end
	local history = {}
	for _, h in ipairs(held.history or {}) do history[#history + 1] = h end
	history[#history + 1] = { s = status, by = by, t = now() }
	while #history > Req.MAX_HISTORY do table.remove(history, 2) end   -- the opening stays
	fields.history = history
	local rec, why = S:Put("bankreq", id, fields)
	if not rec then return false, why end
	emit("BANKREQ_CHANGED", id, status)
	return rec
end

-- The requester (or a character of the same account) cancels an open request.
function Req:Cancel(id)
	local S, me = ns.Store, ownGUID()
	local held = S and S:Get("bankreq", id)
	if not (me and held) then return false, "missing" end
	if not sameAccount(held.requester) then return false, "owner" end
	if held.status ~= "open" then return false, "status" end
	return advance(id, "cancelled", nil, me)
end

-- An officer moves a request: status = "approved", "rejected" (with an optional note) or "fulfilled".
function Req:Decide(id, status, note)
	local me = ownGUID()
	if not me then return false, "player" end
	if not isOfficer() then return false, "officer" end
	if not (status == "approved" or status == "rejected" or status == "fulfilled") then return false, "status" end
	return advance(id, status, note, me)
end

function Req:DebugLines()
	local counts = { open = 0, approved = 0, rejected = 0, fulfilled = 0, cancelled = 0 }
	for _, rec in pairs(ns.Store and ns.GuildKey and ns.GuildKey:Current() and ns.Store:Records("bankreq") or {}) do
		if type(rec) == "table" and counts[rec.status] then counts[rec.status] = counts[rec.status] + 1 end
	end
	return { ("BankRequests: %d open, %d approved, %d fulfilled, %d rejected, %d cancelled"):format(counts.open, counts.approved,
		counts.fulfilled, counts.rejected, counts.cancelled) }
end

if ns.addon then
	ns.addon.BankRequests = Req
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("BankRequests", function() return Req:DebugLines() end) end
end

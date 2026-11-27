-- Wishlist: what each character wishes for, seen by the whole guild (M13.3; SPEC-17 §4.2, WSH-01..WSH-03; SPEC-10 Q43;
-- ADR 0028). Lua 5.1.
--
-- The set `wish` is an ordinary set of the guild (GUILD, with the summary kind `ec`, SPEC-17 §10.2), one record per
-- character:
--   W:<GUID>   { e = up to MAX entries { i = item id, n = 1..QTY_MAX, u = the last day it holds (YYYYMMDD), s = "sl"
--              when it came from the shopping list } , note = up to NOTE_MAX bytes or nil }
-- WSH-01 only the account of the character writes it (an officer may relay it); WSH-02 the shape: no item twice, no
-- expiry already past or further than DAYS_MAX days from the record's time; WSH-03 at most WRITES_PER_HOUR revisions of
-- one author an hour are taken. Every entry expires by itself on every client, from the date, without a write; the
-- author's client drops it at the next write. A record without a live entry goes KEEP_DAYS after its time.
--
--   Wishlist.ValidRecord(rec, store)      the owner rule of the set
--   Wishlist.Live(rec, t)                 the entries that still hold: { item, n, day, left (days, 1 = today only),
--                                         source = "sl" | nil }, in the record's order
--   Wishlist:Own(t)                       the live entries of the connected character, and its note
--   Wishlist:Add(item, n, days)           adds or replaces one entry: the record, or nil and why
--   Wishlist:Remove(item), Wishlist:SetNote(text)
--   Wishlist:Plan(wants, t), Wishlist:Ask(wants)
--       THE ENTRY OF THE SHOPPING LIST (M13.4, "Ask the guild"): wants = { { item, n }, ... }, the missing materials.
--       Plan says what Ask would write, without writing: { entries, asked = { { item, n } }, left = how many did not
--       fit }. An item already listed keeps the larger quantity; a new one is marked "sl"; when MAX entries are not
--       enough, the entries typed by hand stay, old "sl" entries give way and the largest quantities come first.
--   Wishlist:Guild(search, t)             a row per item and character, by item name, online first
-- Switch: Core/Features.lua "econ" (store def `feature = "econ"`). Bus: WISHLIST_CHANGED(guid).
local ADDON_NAME, ns = ...
ns = ns or {}
local Wish = {}
ns.Wishlist, ns.modules = Wish, ns.modules or {}
ns.modules.Wishlist = Wish

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, min, max = math.floor, math.min, math.max
local sort, concat = table.sort, table.concat
local DAY, HOUR = 86400, 3600

Wish.SET = "wish"
Wish.MAX = 30                -- entries of one character (SPEC-10 Q43)
Wish.DAYS = 14               -- how long an entry holds by default
Wish.DAYS_MAX = 30
Wish.QTY_MAX = 999
Wish.NOTE_MAX = 80           -- bytes
Wish.KEEP_DAYS = 30          -- a record without a live entry
Wish.RECORD_BYTES = 2560     -- estimated size of a record with MAX entries (Config.EstimateSize)
Wish.WRITES_PER_HOUR = 20    -- WSH-03

local FIELDS = { id = true, author = true, rev = true, time = true, e = true, note = true }
local ENTRY = { i = true, n = true, u = true, s = true }

local function store() return ns.Store end
local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function me() return compat() and compat().Player.GUID() or nil end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function inGuild() return ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil end

function Wish.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end
local function dayNumber(day) return ns.Timeline.DayNumber(day) end

-- The day (YYYYMMDD, UTC) `days` after the time t.
function Wish.DayAfter(t, days) return tonumber(date("!%Y%m%d", t + days * DAY)) end

function Wish.IdOf(guid) return "W:" .. tostring(guid) end

function Wish.CharOf(id)
	local guid = type(id) == "string" and id:match("^W:(.+)$") or nil
	if guid and #guid <= 40 and guid:find(store().GUID_PATTERN) then return guid end
	return nil
end

-- The note as it is saved: no control character and no "|" (SPEC-15 §4.4), trimmed.
function Wish.Clean(value)
	if type(value) ~= "string" then return "" end
	value = value:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return value
end

---------------------------------------------------------------------------------------------------------------------
-- Trust (WSH-01, WSH-02), retention and rate (WSH-03)
---------------------------------------------------------------------------------------------------------------------
local function validEntries(list, t)
	if type(list) ~= "table" then return false end
	local count = 0
	for _ in pairs(list) do count = count + 1 end
	if count > Wish.MAX or count ~= #list then return false end
	local first, seen = floor(t / DAY), {}
	for _, e in ipairs(list) do
		if type(e) ~= "table" then return false end
		for k in pairs(e) do if not ENTRY[k] then return false end end
		if not (int(e.i, 1, 2147483647) and int(e.n, 1, Wish.QTY_MAX)) or seen[e.i] then return false end
		if e.s ~= nil and e.s ~= "sl" then return false end
		local day = int(e.u, 20000101, 99991231) and dayNumber(e.u)
		if not (day and day >= first and day <= first + Wish.DAYS_MAX) then return false end
		seen[e.i] = true
	end
	return true
end

function Wish.ValidRecord(rec, s)
	s = s or store()
	local guid = type(rec) == "table" and Wish.CharOf(rec.id)
	if not (guid and s:SameAccount(guid, rec.author) and type(rec.time) == "number") then return false end
	for k in pairs(rec) do if not FIELDS[k] then return false end end
	local note = rec.note
	if note ~= nil and not (type(note) == "string" and note ~= "" and #note <= Wish.NOTE_MAX and not note:find("[%c|]")) then
		return false
	end
	return validEntries(rec.e, rec.time)
end

function Wish.Live(rec, t)
	local out = {}
	if type(rec) ~= "table" or type(rec.e) ~= "table" then return out end
	local today = floor((t or now()) / DAY)
	for _, e in ipairs(rec.e) do
		local day = type(e) == "table" and type(e.u) == "number" and dayNumber(e.u)
		if day and day >= today then
			out[#out + 1] = { item = e.i, n = e.n, day = e.u, left = day - today + 1, source = e.s }
		end
	end
	return out
end

function Wish.Expired(rec, t)
	return type(rec) ~= "table" or ((rec.time or 0) < t - Wish.KEEP_DAYS * DAY and #Wish.Live(rec, t) == 0)
end

local received, written = {}, {}   -- author -> times (received); the times this client wrote its list

local function recent(list, t)
	local keep = {}
	for _, at in ipairs(list or {}) do if at > t - HOUR then keep[#keep + 1] = at end end
	return keep
end

function Wish.Within(rec)
	if type(rec) ~= "table" then return true end
	local t, at = now(), rec.time or 0
	if at <= t - HOUR then return true end
	local list = recent(received[rec.author], t)
	received[rec.author] = list
	if #list >= Wish.WRITES_PER_HOUR then return false end
	list[#list + 1] = at
	return true
end

function Wish:ResetRates() received, written = {}, {} end

---------------------------------------------------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------------------------------------------------
local asked = {}   -- the items asked for this session (once each: an answer redraws the views)

-- The item's name, or "item 2589 (loading...)" while the game has not given it (it is asked for:
-- GET_ITEM_INFO_RECEIVED), and the item's info.
function Wish.ItemName(item)
	local C = compat()
	local info = C.Item.Info(item)
	if info then return info.name, info end
	if not asked[item] then
		asked[item] = true
		C.Item.Request(item)
	end
	return ns.L["BANK_ITEM_LOADING"]:format(item), nil
end

-- The item id of what a player typed or pasted: a link, an id, or the name of an item the client knows.
function Wish.ParseItem(text)
	local id = ns.BankRequests and ns.BankRequests.ParseItem(text)
	if id then return id end
	if type(text) ~= "string" then return nil end
	local name = text:gsub("^%s*%[?", ""):gsub("%]?%s*$", "")
	if name == "" then return nil end
	return compat().Item.IDByName(name)
end

---------------------------------------------------------------------------------------------------------------------
-- The own list
---------------------------------------------------------------------------------------------------------------------
local function held()
	local guid = me()
	return guid and inGuild() and store():Get(Wish.SET, Wish.IdOf(guid)) or nil
end

function Wish:Own(t)
	if not Wish.Enabled() then return {}, nil end
	local rec = held()
	return Wish.Live(rec, t), rec and rec.note or nil
end

local function put(entries, note)
	local t = now()
	written = recent(written, t)
	if #written >= Wish.WRITES_PER_HOUR then return nil, "rate" end
	local list = {}
	for i, e in ipairs(entries) do list[i] = { i = e.item, n = e.n, u = e.day, s = e.source } end
	local rec, why = store():Put(Wish.SET, Wish.IdOf(me()), { e = list, note = note })
	if not rec then return nil, why end
	written[#written + 1] = t
	return rec
end

local function ready()
	if not Wish.Enabled() then return false, "off" end
	if not (me() and inGuild()) then return false, "guild" end
	return true
end

local function find(list, item)
	for i, e in ipairs(list) do if e.item == item then return i, e end end
	return nil
end

-- Why: "off", "guild", "item", "count", "days", "full", "rate", or a reason of Store:Put.
function Wish:Add(item, n, days)
	local ok, why = ready()
	if not ok then return nil, why end
	if not int(item, 1, 2147483647) then return nil, "item" end
	n = n == nil and 1 or tonumber(n)
	if not int(n, 1, Wish.QTY_MAX) then return nil, "count" end
	days = days == nil and Wish.DAYS or tonumber(days)
	if not int(days, 1, Wish.DAYS_MAX) then return nil, "days" end
	local list, note = self:Own()
	local i, old = find(list, item)
	if not i and #list >= Wish.MAX then return nil, "full" end
	list[i or #list + 1] = { item = item, n = n, day = Wish.DayAfter(now(), days), source = old and old.source or nil }
	return put(list, note)
end

function Wish:Remove(item)
	local ok, why = ready()
	if not ok then return nil, why end
	local list, note = self:Own()
	local i = find(list, item)
	if not i then return nil, "missing" end
	table.remove(list, i)
	return put(list, note)
end

function Wish:SetNote(text)
	local ok, why = ready()
	if not ok then return nil, why end
	text = Wish.Clean(text)
	if #text > Wish.NOTE_MAX then return nil, "note" end
	local list, note = self:Own()
	if text == (note or "") then return held() end
	return put(list, text ~= "" and text or nil)
end

---------------------------------------------------------------------------------------------------------------------
-- "Ask the guild" of the shopping list (SPEC-17 §5.8; M13.4 calls these)
---------------------------------------------------------------------------------------------------------------------
function Wish:Plan(wants, t)
	t = t or now()
	local day = Wish.DayAfter(t, Wish.DAYS)
	local asking, order = {}, {}   -- item -> quantity (the same item twice adds up)
	for _, w in ipairs(type(wants) == "table" and wants or {}) do
		local item, n = type(w) == "table" and w.item, type(w) == "table" and tonumber(w.n)
		if int(item, 1, 2147483647) and n and n >= 1 then
			if not asking[item] then order[#order + 1] = item end
			asking[item] = min((asking[item] or 0) + floor(n), Wish.QTY_MAX)
		end
	end
	local kept, loose, new = {}, {}, {}
	local listed = {}
	for _, e in ipairs((self:Own(t))) do
		listed[e.item] = true
		if asking[e.item] then
			e.n, e.day = max(e.n, asking[e.item]), max(e.day, day)
			kept[#kept + 1] = e
		elseif e.source == "sl" then loose[#loose + 1] = e
		else kept[#kept + 1] = e end
	end
	for _, item in ipairs(order) do
		if not listed[item] then new[#new + 1] = { item = item, n = asking[item], day = day, source = "sl" } end
	end
	sort(new, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.item < b.item end)
	local entries, asked, left = kept, {}, 0
	for _, e in ipairs(kept) do if asking[e.item] then asked[#asked + 1] = { item = e.item, n = e.n } end end
	for _, e in ipairs(new) do
		if #entries < Wish.MAX then
			entries[#entries + 1] = e
			asked[#asked + 1] = { item = e.item, n = e.n }
		else
			left = left + 1
		end
	end
	for _, e in ipairs(loose) do if #entries < Wish.MAX then entries[#entries + 1] = e end end
	return { entries = entries, asked = asked, left = left }
end

-- Writes the plan. Returns the record and the plan, or nil and why ("empty" when there is nothing to ask).
function Wish:Ask(wants)
	local ok, why = ready()
	if not ok then return nil, why end
	local plan = self:Plan(wants)
	if #plan.asked == 0 then return nil, "empty" end
	local _, note = self:Own()
	local rec, w = put(plan.entries, note)
	if not rec then return nil, w end
	return rec, plan
end

---------------------------------------------------------------------------------------------------------------------
-- The guild's wishes
---------------------------------------------------------------------------------------------------------------------
local function entryOf(guid) return ns.Roster and ns.Roster:ByGUID(guid) or nil end

local function own(guid)
	local mine = me()
	return mine ~= nil and store():SameAccount(mine, guid)
end

-- { guid, name, online, own, item, itemName, n, day, left, source, note }; characters that left the guild are
-- not shown once the roster was read. `search` filters by item name or character.
function Wish:Guild(search, t)
	local out = {}
	if not (Wish.Enabled() and inGuild()) then return out end
	t = t or now()
	local needle = type(search) == "string" and search ~= "" and search:lower() or nil
	local read = ns.Roster ~= nil and ns.Roster:Count() > 0
	for id, rec in pairs(store():Records(Wish.SET)) do
		local guid = Wish.CharOf(id)
		local e = guid and entryOf(guid)
		if guid and not (read and not e) then
			local name = e and (e.short or e.name) or "?"
			for _, w in ipairs(Wish.Live(rec, t)) do
				local itemName = Wish.ItemName(w.item)
				if not needle or itemName:lower():find(needle, 1, true) or name:lower():find(needle, 1, true) then
					out[#out + 1] = { guid = guid, name = name, online = e ~= nil and e.online == true, own = own(guid),
						item = w.item, itemName = itemName, n = w.n, day = w.day,
						left = w.left, source = w.source, note = rec.note }
				end
			end
		end
	end
	sort(out, function(a, b)
		if a.itemName:lower() ~= b.itemName:lower() then return a.itemName:lower() < b.itemName:lower() end
		if a.item ~= b.item then return a.item < b.item end
		if a.online ~= b.online then return a.online end
		if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
		return a.guid < b.guid
	end)
	return out
end

-- Counts only (SPEC-09 §6).
function Wish:DebugLines()
	local records, live = 0, 0
	for _, rec in pairs(inGuild() and store():Records(Wish.SET) or {}) do
		records = records + 1
		live = live + #Wish.Live(rec)
	end
	local reasons = {}
	for why, n in pairs(store().stats.bySet[Wish.SET] or {}) do reasons[#reasons + 1] = why .. " " .. n end
	sort(reasons)
	return { ("Wishlist: %d list(s), %d live entr(ies); refused: %s"):format(records, live,
		#reasons > 0 and concat(reasons, ", ") or "none") }
end

if ns.addon then
	ns.addon.Wishlist = Wish
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set == Wish.SET then emit("WISHLIST_CHANGED", Wish.CharOf(id)) end
		end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if Wish.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Wishlist", function() return Wish:DebugLines() end)
			end
		end)
	end
end

-- Bank: snapshots of the guild bank, captured while the player has the vault open (SPEC-08 BANK-01..03, ADR 0009). Lua 5.1.
--
-- The game gives the bank contents only while the vault window is open, and only for the tabs the player's rank may view
-- [verify S9]. When the window opens (GUILDBANKFRAME_OPENED) the capture reads, one query at a time with a pause between
-- them (the client throttles the guild bank queries), every viewable tab and the money, and publishes:
--
--   tab    id "<GUID>:t<tab>"   { kind = "tab", tab, name, icon, rank, restricted, it = <items text>, n, h }
--   money  id "<GUID>:money"    { kind = "money", money }
--
-- `it` lists the items as "slot.itemID.count" or "slot.itemID.count.variant" separated by commas (Bank.EncodeItems /
-- Bank.DecodeItems; a compact text, one record per tab fits a few KB). `variant` keeps the item string fields after the
-- id that differ between two items of one kind (enchant, gems, suffix), colons written as "_". `h` is a hash of the
-- items: an unchanged tab is published again only after REPUBLISH seconds (so its "seen ... ago" stays honest without a
-- message per visit). Every record belongs to the character that captured it: other captures of the same tab are other
-- records, and the newest one wins in the view (Bank:Snapshot, BANK-03).
--
-- Permissions (ADR 0009 rule 2, SPEC-10 Q4 proposal): the game does not tell a client which RANKS may view a tab, only
-- whether its own rank can. So a snapshot carries `rank`, the rank index of the character that read it: it may be shown to
-- members of that rank or above (a lower index), and a snapshot read by an officer is `restricted` (officers only, sent
-- on OFFICER, never on GUILD). A tab that every rank can view reaches the members only when a member read it.
--
-- Capture states: a tab with no readable item is published as empty only when the vault stayed open and delivered data
-- at least once during this capture (an event arrived); a tab that never loaded is not published, so a slow or throttled
-- vault can never wipe a good snapshot.
local ADDON_NAME, ns = ...
ns = ns or {}
local Bank = {}
ns.Bank, ns.modules = Bank, ns.modules or {}
ns.modules.Bank = Bank

local type, pairs, ipairs, tostring, tonumber, floor = type, pairs, ipairs, tostring, tonumber, math.floor
local concat, sort = table.concat, table.sort

Bank.EVENTS = { "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_MONEY" }
Bank.PAUSE = 1.0          -- seconds between two queries
Bank.WAIT = 4             -- seconds to wait for a tab to load before reading what is there
Bank.TABS_RETRY = 1.5     -- seconds before asking again for the tab count while the vault has not told it yet
Bank.TABS_TRIES = 3
Bank.REPUBLISH = 1800     -- seconds before an unchanged tab is published again
Bank.MAX_TABS = 8
Bank.MAX_SLOTS = 98
Bank.MAX_ITEMS_TEXT = 3000

local state
local function resetState()
	if state and state.run then state.run.cancelled = true end
	state = {
		open = false,          -- the vault window is open
		run = nil,             -- the capture in progress: { jobs, i, waiting, cancelled, epoch }
		epoch = ((state and state.epoch) or 0) + 1,
		perms = {},            -- tab -> { name, icon, viewable, canDeposit, withdrawals, remaining }: this rank, this session
		published = {},        -- tab -> { h, at }: the last publication of this session (REPUBLISH)
		stats = { captures = 0, tabs = 0, published = 0, unchanged = 0, unreadable = 0, aborted = 0 },
		last = nil,            -- the outcome of the last capture, for /accord debug
		lastCapture = nil,     -- server time of the last complete capture
	}
	Bank.state = state
end
resetState()

local function compat() return ns.Compat end
local function now() return compat() and compat().Now() or 0 end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function ownGUID() return compat() and compat().Player.GUID() or nil end

---------------------------------------------------------------------------------------------------------------------
-- The items text
---------------------------------------------------------------------------------------------------------------------
-- The fields of an item link that tell two items of one kind apart: enchant, four gems and the suffix, as "e_g_g_g_g_s"
-- (trailing empties dropped), or nil when the item is plain. The id, the unique id and the character's level are left out.
function Bank.Variant(link)
	if type(link) ~= "string" then return nil end
	local body = link:match("|Hitem:([^|]+)|h") or link:match("^item:(.+)$")
	if not body then return nil end
	local fields = {}
	for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
	local out = {}
	for i = 2, 7 do out[#out + 1] = fields[i] or "" end
	while #out > 0 and (out[#out] == "" or out[#out] == "0") do out[#out] = nil end
	if #out == 0 then return nil end
	for _, v in ipairs(out) do if not v:find("^%-?%d*$") then return nil end end
	return concat(out, "_")
end

-- items = { { slot, itemID, count, variant }, ... } (named fields: slot, itemID, count, variant) -> text.
function Bank.EncodeItems(items)
	local list = {}
	for _, it in ipairs(items or {}) do list[#list + 1] = it end
	sort(list, function(a, b) return a.slot < b.slot end)
	local parts = {}
	for _, it in ipairs(list) do
		local text = ("%d.%d.%d"):format(it.slot, it.itemID, it.count)
		if it.variant then text = text .. "." .. it.variant end
		parts[#parts + 1] = text
	end
	return concat(parts, ",")
end

-- The reader does not trust the text: nothing but digits and underscores, slots 1..98 once each, at most 98 items.
-- Returns the list, or nil and a reason ("shape", "size", "item", "slot", "count").
function Bank.DecodeItems(text)
	if type(text) ~= "string" then return nil, "shape" end
	if #text > Bank.MAX_ITEMS_TEXT then return nil, "size" end
	local out, seen = {}, {}
	if text == "" then return out end
	for part in (text .. ","):gmatch("([^,]*),") do
		local slot, id, count, variant = part:match("^(%d+)%.(%d+)%.(%d+)%.?([%d_%-]*)$")
		if not slot then return nil, "item" end
		slot, id, count = tonumber(slot), tonumber(id), tonumber(count)
		if slot < 1 or slot > Bank.MAX_SLOTS or seen[slot] then return nil, "slot" end
		if id < 1 or id > 2147483647 or count < 1 or count > 2147483647 or #out >= Bank.MAX_SLOTS then return nil, "count" end
		seen[slot] = true
		out[#out + 1] = { slot = slot, itemID = id, count = count, variant = variant ~= "" and variant or nil }
	end
	return out
end

-- The shape rules of a `bank` record (Store owner rule, SPEC-02 §6): its id belongs to its author, so a client cannot
-- write another character's snapshot, and every field has a type and a limit.
local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end
local function text(v, max) return type(v) == "string" and #v <= max end

function Bank.ValidRecord(rec)
	if type(rec) ~= "table" or type(rec.author) ~= "string" or type(rec.id) ~= "string" then return false end
	if rec.restricted ~= nil and type(rec.restricted) ~= "boolean" then return false end
	if rec.kind == "tab" then
		if rec.id ~= rec.author .. ":t" .. tostring(rec.tab) or not int(rec.tab, 1, Bank.MAX_TABS) then return false end
		if rec.name ~= nil and not text(rec.name, 48) then return false end
		if rec.icon ~= nil and not int(rec.icon, 0, 2147483647) and not text(rec.icon, 160) then return false end
		if rec.rank ~= nil and not int(rec.rank, 0, 40) then return false end
		if not text(rec.it, Bank.MAX_ITEMS_TEXT) or not int(rec.n, 0, Bank.MAX_SLOTS) then return false end
		return Bank.DecodeItems(rec.it) ~= nil
	elseif rec.kind == "money" then
		return rec.id == rec.author .. ":money" and int(rec.money, 0, 9007199254740991)
	end
	return false
end

-- A hash of the items text: changes with any slot, item, count or variant.
function Bank.HashOf(text)
	return ns.Hash and ns.Hash.Fast(text or "") or 0
end

---------------------------------------------------------------------------------------------------------------------
-- Reading the open vault
---------------------------------------------------------------------------------------------------------------------
-- The items of one tab as the client shows them now: a list of { slot, itemID, count, variant }.
function Bank:ReadItems(tab)
	local C, items = compat(), {}
	for slot = 1, Bank.MAX_SLOTS do
		local item = C.Bank.Item(tab, slot)
		if item then
			items[#items + 1] = { slot = slot, itemID = item.itemID, count = floor(item.count or 1), variant = Bank.Variant(item.link) }
		end
	end
	return items
end

-- The tab list of the vault: { { tab, name, icon, viewable, canDeposit, withdrawals, remaining }, ... }, the tabs this
-- rank cannot view included (marked viewable = false); empty while the vault has not told the tab count.
function Bank:ReadTabs()
	local C, out = compat(), {}
	for tab = 1, math.min(C.Bank.NumTabs(), Bank.MAX_TABS) do
		local info = C.Bank.TabInfo(tab)
		if info then
			out[#out + 1] = { tab = tab, name = info.name, icon = info.icon, viewable = info.isViewable, canDeposit = info.canDeposit,
				withdrawals = info.numWithdrawals, remaining = info.remainingWithdrawals }
		end
	end
	return out
end

-- The permissions of this character's rank read at the last capture: tab -> { name, icon, viewable, canDeposit,
-- withdrawals, remaining }. For the bank view (what the rank may do) and for the tests.
function Bank:Permissions() return state.perms end
function Bank:IsOpen() return state.open end

---------------------------------------------------------------------------------------------------------------------
-- Publishing
---------------------------------------------------------------------------------------------------------------------
local function myRank()
	local _, _, rank = compat().Guild.PlayerRank()
	return type(rank) == "number" and rank or nil
end

local function officer() return ns.Role and ns.Role:IsOfficer() or false end

-- Writes the snapshot of one tab. Returns true, or false and "unchanged", "unreadable" or the store's reason.
function Bank:PublishTab(tab, name, icon, items, force)
	local S, me = ns.Store, ownGUID()
	if not (S and me) then return false, "player" end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local text = Bank.EncodeItems(items)
	local h = Bank.HashOf(text)
	local id = me .. ":t" .. tab
	local old = S:Get("bank", id)
	local at = state.published[tab]
	local t = now()
	if not force and old and old.h == h and old.n == #items and at and at.h == h and t - at.at < Bank.REPUBLISH then
		state.stats.unchanged = state.stats.unchanged + 1
		return false, "unchanged"
	end
	local rank = myRank()
	local rec, why = S:Put("bank", id, {
		kind = "tab", tab = tab, name = name, icon = icon, rank = rank, restricted = officer() or nil,
		it = text, n = #items, h = h,
	})
	if not rec then
		state.stats.unreadable = state.stats.unreadable + 1
		return false, why
	end
	state.published[tab] = { h = h, at = t }
	state.stats.published = state.stats.published + 1
	return true
end

-- Writes the money (the gold of the guild bank in copper) when it changed or the last record is old.
function Bank:PublishMoney(money, force)
	local S, me = ns.Store, ownGUID()
	if not (S and me and type(money) == "number") then return false, "player" end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local id = me .. ":money"
	local old = S:Get("bank", id)
	local t = now()
	local at = state.published.money
	if not force and old and old.money == money and at and t - at < Bank.REPUBLISH then return false, "unchanged" end
	local rec, why = S:Put("bank", id, { kind = "money", money = floor(money) })
	if not rec then return false, why end
	state.published.money = t
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The capture: one query at a time
---------------------------------------------------------------------------------------------------------------------
local function after(seconds, fn)
	local C = compat()
	local epoch = state.epoch
	local scheduled = C and C.After(seconds, function()
		if epoch ~= state.epoch then return end
		fn()
	end)
	return scheduled and true or false
end

local advance

-- The job `job` of `run` has its data (or ran out of time): read it, then go on after the pause.
local function complete(run, how)
	if run.cancelled or run ~= state.run then return end
	local waiting = run.waiting
	if not waiting then return end
	run.waiting = nil
	local C = compat()
	if waiting.kind == "tab" then
		local items = Bank:ReadItems(waiting.tab)
		if #items == 0 and how == "event" and not waiting.settled then
			-- an event can come from the player's own browsing: an empty tab counts only once the timeout has passed
			run.waiting = waiting
			waiting.settled = true
			return
		end
		if not state.open then
			state.stats.aborted = state.stats.aborted + 1
		elseif #items == 0 and not (how == "timeout" and run.loaded) then
			state.stats.unreadable = state.stats.unreadable + 1
		else
			local info = state.perms[waiting.tab] or {}
			state.stats.tabs = state.stats.tabs + 1
			local ok, why = Bank:PublishTab(waiting.tab, info.name, info.icon, items)
			run.results[#run.results + 1] = ("tab %d: %s%s"):format(waiting.tab, ok and ("%d item(s)"):format(#items) or "not published",
				ok and "" or (" (" .. tostring(why) .. ")"))
			if ok and #items > 0 or why == "unchanged" then
				if C:Feature("bankTabs") ~= "available" then C:SetFeature("bankTabs", "available", "a tab was read from the open vault") end
			end
		end
	end
	if not after(Bank.PAUSE, function() advance(run) end) then advance(run) end
end

local function startJob(run, job)
	local C = compat()
	if job.kind == "tab" then
		run.waiting = { kind = "tab", tab = job.tab }
		C.Bank.QueryTab(job.tab)
		local waiting = run.waiting
		-- the timeout: whatever the client has by then is read
		if not after(Bank.WAIT, function()
			if run.waiting == waiting then complete(run, "timeout") end
		end) then
			complete(run, "timeout")
		end
	elseif job.kind == "money" then
		local money = C.Bank.Money()
		if money and state.open then
			local ok = Bank:PublishMoney(money)
			run.results[#run.results + 1] = ("money: %s"):format(ok and "published" or "unchanged")
		end
		advance(run)
	else
		advance(run)
	end
end

-- Moves to the next job, or ends the capture.
advance = function(run)
	if run.cancelled or run ~= state.run then return end
	if not state.open then
		state.stats.aborted = state.stats.aborted + 1
		state.last = "closed before the capture ended"
		state.run = nil
		return
	end
	run.i = run.i + 1
	local job = run.jobs[run.i]
	if not job then
		state.run = nil
		state.lastCapture = compat().ServerTime()
		state.last = ("captured: %s"):format(#run.results > 0 and concat(run.results, "; ") or "nothing to read")
		emit("BANK_CAPTURED")
		return
	end
	startJob(run, job)
end

-- Builds the job list from the tab count the vault gives now, and starts. `tries` counts the waits for the tab count.
local function begin(tries)
	if not state.open or state.run then return end
	local tabs = Bank:ReadTabs()
	if #tabs == 0 then
		if tries < Bank.TABS_TRIES and after(Bank.TABS_RETRY, function() begin(tries + 1) end) then return end
		state.last = "the vault told no tab"
		return
	end
	state.perms = {}
	local jobs = {}
	for _, t in ipairs(tabs) do
		state.perms[t.tab] = t
		if t.viewable then jobs[#jobs + 1] = { kind = "tab", tab = t.tab } end
	end
	jobs[#jobs + 1] = { kind = "money" }
	local run = { jobs = jobs, i = 0, results = {}, epoch = state.epoch }
	state.run = run
	state.stats.captures = state.stats.captures + 1
	advance(run)
end

function Bank:OnOpened()
	local C = compat()
	if not (C and ns.GuildKey and ns.GuildKey:Current()) then return end
	state.open = true
	if not C.Bank.Enabled() then
		state.last = "the guild bank is off"
		return
	end
	if state.run then state.run.cancelled = true state.run = nil end
	begin(1)
end

function Bank:OnClosed()
	state.open = false
	if state.run then
		state.run.cancelled = true
		state.run = nil
		state.stats.aborted = state.stats.aborted + 1
		state.last = "closed before the capture ended"
	end
end

-- A tab (or the log) loaded: the job that waits for it can read.
function Bank:OnSlotsChanged()
	local run = state.run
	if run then run.loaded = true end   -- the vault does deliver data: an empty tab after a timeout is then really empty
	if run and run.waiting and run.waiting.kind == "tab" then complete(run, "event") end
end

-- The money changed while the vault is open and no capture runs: publish the new amount.
function Bank:OnMoney()
	if not state.open or state.run then return end
	local money = compat().Bank.Money()
	if money then Bank:PublishMoney(money) end
end

-- A change of guild: nothing waits any more.
function Bank:Reset() resetState() end

---------------------------------------------------------------------------------------------------------------------
-- /accord debug
---------------------------------------------------------------------------------------------------------------------
function Bank:DebugLines()
	local s = state.stats
	return {
		("Bank: vault %s, %d capture(s), %d tab(s) read, %d published, %d unchanged, %d unreadable, %d aborted"):format(
			state.open and "open" or "closed", s.captures, s.tabs, s.published, s.unchanged, s.unreadable, s.aborted),
		("  last: %s"):format(state.last or "the vault has not been opened this session"),
	}
end

if ns.addon then
	ns.addon.Bank = Bank
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Bank", function() return Bank:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Bank)
	local handlers = {
		GUILDBANKFRAME_OPENED = function() Bank:OnOpened() end,
		GUILDBANKFRAME_CLOSED = function() Bank:OnClosed() end,
		GUILDBANKBAGSLOTS_CHANGED = function() Bank:OnSlotsChanged() end,
		GUILDBANK_UPDATE_MONEY = function() Bank:OnMoney() end,
	}
	for _, event in ipairs(Bank.EVENTS) do pcall(Bank.RegisterEvent, Bank, event, handlers[event]) end
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() Bank:Reset() end) end
end

-- BankInbox: what the officers and the requesters are told about bank requests (SPEC-08 BANK-23, BANK-24). Lua 5.1.
--
-- Counter     an officer's tab in the guild window, the Bank button of the panel and the compartment tooltip show how many
--             requests are open (waiting for a decision): BankInbox.PendingCount(). Members see no counter.
-- Inbox       the requests that need an officer, oldest first: open ones (to approve or reject) and approved ones (to mark as
--             fulfilled), each with the movement of the bank that looks like its delivery (BankInbox:Suggest).
-- Notices     one chat line when a request arrives that an officer has not seen ("New bank request from Bob: Linen Cloth
--             x20"), and one to the requester when an officer moves one of their requests ("Your bank request ... was
--             approved by Boss"). What a character has been told is kept per guild in GuildKey:Data().bank.seen
--             ({ [request id] = the status seen }); the first time the addon runs everything held is taken as seen, so an
--             install or a new guild does not start with a flood. Notices of one burst (a login brings many) are printed
--             together after NOTICE_WAIT seconds, MAX_LINES at most plus "and N more".
-- Proposal    BANK-24: delivery stays manual; when the bank log shows the movement that matches a request (an item taken out
--             by the requester's account for a withdrawal, deposited for a deposit or a donation, the gold in the money log),
--             the inbox says so next to the request and the officer marks it fulfilled with one click.
local ADDON_NAME, ns = ...
ns = ns or {}
local Inbox = {}
ns.BankInbox, ns.modules = Inbox, ns.modules or {}
ns.modules.BankInbox = Inbox

local type, pairs, ipairs, tostring, max = type, pairs, ipairs, tostring, math.max
local sort = table.sort

Inbox.NOTICE_WAIT = 3         -- seconds a notice waits for the rest of its burst
Inbox.MAX_LINES = 3
Inbox.MATCH_SLACK = 3600      -- an entry up to this long before the request still counts (its time is rounded down)

local L = ns.L
local state = { pending = {}, timer = false }

local function compat() return ns.Compat end
local function isOfficer() return ns.Role ~= nil and ns.Role:IsOfficer() end
local function lower(s) return type(s) == "string" and s:lower() or "" end

-- The counter: open requests, for officers; 0 for everybody else.
function Inbox.PendingCount()
	if not (isOfficer() and ns.BankRequests) then return 0 end
	return ns.BankRequests:OpenCount()
end

---------------------------------------------------------------------------------------------------------------------
-- The inbox
---------------------------------------------------------------------------------------------------------------------
-- The requests that need an officer, oldest first: { request row..., suggestion = entry | nil }.
function Inbox:Rows()
	local Req = ns.BankRequests
	if not (Req and isOfficer()) then return {} end
	local rows = Req:List({ status = { open = true, approved = true } })
	sort(rows, function(a, b)
		if (a.created or 0) ~= (b.created or 0) then return (a.created or 0) < (b.created or 0) end
		return a.id < b.id
	end)
	for _, r in ipairs(rows) do r.suggestion = self:Suggest(r) end
	return rows
end

-- The names (lower case, without realm) of the characters of the requester's account.
local function accountNames(requester)
	local names = {}
	local function add(guid)
		local e = ns.Roster and ns.Roster:ByGUID(guid)
		if e then
			if e.short then names[lower(e.short)] = true end
			if e.name then names[lower(e.name:match("^[^%-]+") or e.name)] = true end
		end
	end
	add(requester)
	for _, g in ipairs(ns.Accounts and ns.Accounts:ProvedChars(requester) or {}) do add(g) end
	return names
end

-- The log entry that looks like the delivery of a request, or nil: the newest entry, after the request was made, of the
-- requester's account, with the item (or the gold) and at least the quantity asked for. A withdrawal is matched by a
-- withdrawal, a deposit or a donation by a deposit.
function Inbox:Suggest(r)
	local Log = ns.BankLog
	if not (Log and type(r) == "table") then return nil end
	local want = r.kind == "withdraw" and "withdraw" or "deposit"
	local names = accountNames(r.requester)
	local since = (r.created or 0) - Inbox.MATCH_SLACK
	for _, e in ipairs(Log:Entries()) do   -- newest first
		if e.kind == want and e.t >= since and names[lower(e.name:match("^[^%-]+") or e.name)] then
			if r.itemID then
				if e.tab ~= Log.MONEY_TAB and e.itemID == r.itemID and e.count >= (r.count or 1) then return e end
			elseif e.tab == Log.MONEY_TAB and e.count >= (r.amount or 0) then
				return e
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Notices
---------------------------------------------------------------------------------------------------------------------
local function seen(create)
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.bank) ~= "table" then
		if not create then return nil end
		data.bank = {}
	end
	if type(data.bank.seen) ~= "table" then
		if not create then return nil end
		data.bank.seen = {}
	end
	return data.bank.seen
end

local function whatOf(rec)
	local View = ns.BankView
	if rec.itemID then
		local info = View and View.ItemInfo(rec.itemID) or {}
		return (info.name or ("item " .. rec.itemID)) .. " x" .. (rec.count or 1)
	end
	return View and View.MoneyText(rec.amount) or tostring(rec.amount)
end

local function nameOf(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	return e and (e.short or e.name) or "?"
end

-- A notice the player switched off in the Settings (UI/SettingsModel.lua) is not printed; what waits is still counted.
local function wanted(key)
	local M = ns.SettingsModel
	return M == nil or M.Get(key) ~= false
end

local flush
local function queue(text)
	state.pending[#state.pending + 1] = text
	if state.timer then return end
	state.timer = true
	local scheduled = compat() and compat().After(Inbox.NOTICE_WAIT, function() flush() end)
	if not scheduled then flush() end
end

flush = function()
	state.timer = false
	local list = state.pending
	state.pending = {}
	if #list == 0 or not ns.addon then return end
	for i = 1, math.min(#list, Inbox.MAX_LINES) do ns.addon:Print(list[i]) end
	if #list > Inbox.MAX_LINES then ns.addon:Print(L["BANKNOTE_MORE"]:format(#list - Inbox.MAX_LINES)) end
end

-- A request record arrived or changed: what should this character be told?
function Inbox:OnRequest(id)
	local S = ns.Store
	local rec = S and S:Get("bankreq", id)
	local book = seen(true)
	if not (rec and book and rec.status) then return end
	local before = book[id]
	book[id] = rec.status
	if before == rec.status then return end
	local me = compat() and compat().Player.GUID()
	local own = me ~= nil and S:SameAccount(me, rec.requester)
	if rec.status == "open" and before == nil then
		if isOfficer() and not own and wanted("notifyOfficer") then
			queue(L["BANKNOTE_NEW"]:format(nameOf(rec.requester), whatOf(rec)))
		end
	elseif own and (rec.status == "approved" or rec.status == "rejected" or rec.status == "fulfilled") and wanted("notifyDecision") then
		local last = rec.history and rec.history[#rec.history]
		local text = L["BANKNOTE_" .. rec.status:upper()]:format(whatOf(rec), last and nameOf(last.by) or "?")
		if rec.status == "rejected" and rec.note then text = text .. " " .. L["BANKREQ_NOTE"]:format(rec.note) end
		queue(text)
	end
end

-- The first run of a guild: everything held counts as seen.
function Inbox:Baseline()
	local book = seen(true)
	if not book or book.__baseline then return end
	for id, rec in pairs(ns.Store and ns.Store:Records("bankreq") or {}) do
		if type(rec) == "table" and rec.status then book[id] = rec.status end
	end
	book.__baseline = true
end

---------------------------------------------------------------------------------------------------------------------
-- The counter on the tab and the panel
---------------------------------------------------------------------------------------------------------------------
function Inbox:UpdateCounter()
	local n = Inbox.PendingCount()
	if ns.GuildTab and ns.GuildTab.SetBadge then ns.GuildTab:SetBadge(n) end
	if ns.Shell and ns.Shell.UpdateBadges then ns.Shell:UpdateBadges() end
end

function Inbox:DebugLines()
	return { ("BankInbox: %d open request(s) waiting, %d notice(s) queued"):format(Inbox.PendingCount(), #state.pending) }
end

if ns.addon then
	ns.addon.BankInbox = Inbox
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("BankInbox", function() return Inbox:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set == "bankreq" then
				Inbox:OnRequest(id)
				Inbox:UpdateCounter()
			end
		end)
		ns.Bus:On("BANKREQ_CHANGED", function() Inbox:UpdateCounter() end)
		ns.Bus:On("ROLE_CHANGED", function() Inbox:UpdateCounter() end)
		ns.Bus:On("GUILD_CHANGED", function(key)
			state.pending, state.timer = {}, false
			if key then Inbox:Baseline() Inbox:UpdateCounter() end
		end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if ns.GuildKey and ns.GuildKey:Current() then Inbox:Baseline() Inbox:UpdateCounter() end
		end)
	end
end

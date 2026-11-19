-- Requests mode of the Bank view (SPEC-08 BANK-20..BANK-22, SPEC-03 §7). Lua 5.1.
--
-- A form at the top opens a request: the kind (Withdraw, Deposit, Donation), the item (an item link pasted into the box, or
-- the item number; empty for gold), how many (or how much gold) and a reason. Below it every request of the guild is listed,
-- newest first, with its status; the requester sees [Cancel] on an open request of their own, and an officer sees the moves
-- the request allows ([Approve], [Reject], [Fulfilled]); the reason box also carries the officer's reason for a rejection.
-- The tooltip of a row shows the history (who moved it and when). Handing the item over stays manual (BANK-24).
--
-- Mode.Rows, Mode.Submit and Mode.Act are plain functions (tested offline); the frames only draw and call them.
local ADDON_NAME, ns = ...
ns = ns or {}
local Mode = {}
ns.BankRequestsView, ns.modules = Mode, ns.modules or {}
ns.modules.BankRequestsView = Mode

local View = ns.BankView
if not View then return end
local L, W, Skin = ns.L, ns.Widgets, ns.Skin
local type, ipairs, pairs, tostring, tonumber, floor, max, min = type, ipairs, pairs, tostring, tonumber, math.floor, math.max, math.min

Mode.kind = "withdraw"
Mode.onlyMine = false
Mode.showClosed = false
Mode.FORM_HEIGHT = 120

local OPEN_STATES = { open = true, approved = true }
local function now() return ns.Compat and ns.Compat.ServerTime() or 0 end
local function lower(s) return type(s) == "string" and s:lower() or "" end
local function print_(msg) if ns.addon and msg then ns.addon:Print(msg) end end

---------------------------------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------------------------------
function Mode.KindText(kind) return L["BANKREQ_KIND_" .. tostring(kind):upper()] end
function Mode.StatusText(status) return L["BANKREQ_STATUS_" .. tostring(status):upper()] end
local STATUS_COLOR = { open = "gold", approved = "green", fulfilled = "green", rejected = "red", cancelled = "grey" }

-- What a request is about: "Linen Cloth x20" or "12g 50s".
function Mode.WhatText(r)
	if r.itemID then
		local info = View.ItemInfo(r.itemID)
		return (info.name or L["BANK_ITEM_LOADING"]:format(r.itemID)) .. " x" .. (r.count or 1)
	end
	return View.MoneyText(r.amount)
end

-- One line of the history for the tooltip: "Approved by Boss, 2 h ago".
function Mode.HistoryLine(h)
	local e = ns.Roster and ns.Roster:ByGUID(h.by)
	local who = e and (e.short or e.name) or "?"
	local ago = ns.Shell and ns.Shell.Ago(max(0, now() - (h.t or 0))) or ""
	return L["BANKREQ_HISTORY_LINE"]:format(Mode.StatusText(h.s), who, ago)
end

---------------------------------------------------------------------------------------------------------------------
-- Rows and actions
---------------------------------------------------------------------------------------------------------------------
-- The requests to list: open and approved ones, and the closed ones when showClosed; only this player's when onlyMine; the
-- panel search filters by requester name, item name or reason. Each row adds `what`, `kindText`, `statusText` and `ago`.
function Mode.Rows(opts)
	opts = opts or {}
	local Req = ns.BankRequests
	if not Req then return {} end
	local status = (not opts.showClosed) and OPEN_STATES or nil
	local query = lower(opts.search)
	local out = {}
	for _, r in ipairs(Req:List({ status = status, own = opts.onlyMine })) do
		r.what = Mode.WhatText(r)
		r.kindText, r.statusText = Mode.KindText(r.kind), Mode.StatusText(r.status)
		r.ago = ns.Shell and ns.Shell.Ago(max(0, now() - (r.created or 0))) or ""
		if query == "" or lower(r.name):find(query, 1, true) or lower(r.what):find(query, 1, true) or lower(r.reason):find(query, 1, true) then
			out[#out + 1] = r
		end
	end
	return out
end

-- Opens a request from the text of the form: spec = { kind, item, amount, reason } (strings as typed). With an item `amount`
-- is how many; without one it is gold (whole gold pieces). Returns true, or false and the text to show.
function Mode.Submit(spec)
	local Req = ns.BankRequests
	if not Req then return false, L["BANKREQ_ERR_GUILD"] end
	local itemText = type(spec.item) == "string" and spec.item:gsub("^%s+", ""):gsub("%s+$", "") or ""
	local number = tonumber((tostring(spec.amount or ""):gsub("%s", "")))
	local request = { kind = spec.kind, reason = spec.reason }
	if itemText ~= "" then
		local id = Req.ParseItem(itemText)
		if not id then return false, L["BANKREQ_ERR_ITEM"] end
		request.itemID = id
		request.count = number and floor(number) or 1
	else
		if not number then return false, L["BANKREQ_ERR_AMOUNT"] end
		request.amount = floor(number) * 10000
	end
	local rec, why = Req:Create(request)
	if not rec then
		local text = L["BANKREQ_ERR_" .. tostring(why):upper()]
		return false, text ~= "BANKREQ_ERR_" .. tostring(why):upper() and text or L["BANKREQ_ERR_OTHER"]:format(tostring(why))
	end
	return true, L["BANKREQ_SENT"]
end

-- A button of a row: action = "cancel", "approved", "rejected" or "fulfilled" (`note` is the reason typed in the form for a
-- rejection). Returns true, or false and a reason.
function Mode.Act(id, action, note)
	local Req = ns.BankRequests
	if not Req then return false, "guild" end
	local rec, why
	if action == "cancel" then rec, why = Req:Cancel(id) else rec, why = Req:Decide(id, action, note) end
	return rec and true or false, why
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local mode = {}

local function editBox(parent, width, maxLetters)
	local edit = W.Create("EditBox", nil, parent, { "InputBoxTemplate", "" })
	edit:SetSize(width, 22)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(maxLetters or 60)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return edit
end

local function label(parent, text, anchor, dx, dy)
	local fs = W.Text(parent, "small", "grey", "LEFT")
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx or 0, dy or -2)
	fs:SetText(text)
	return fs
end

local function newRow(area, i)
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(View.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints(row)
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	row.status = W.Text(row, "small", nil, "LEFT")
	row.status:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.status:SetWidth(74)
	row.name = W.Text(row, "body", nil, "LEFT")
	row.name:SetPoint("LEFT", row.status, "RIGHT", 4, 0)
	row.name:SetWidth(96)
	row.kind = W.Text(row, "small", "grey", "LEFT")
	row.kind:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
	row.kind:SetWidth(66)
	row.what = W.Text(row, "body", "gold", "LEFT")
	row.what:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
	row.what:SetWidth(170)
	row.reason = W.Text(row, "small", "grey", "LEFT")
	row.reason:SetPoint("LEFT", row.what, "RIGHT", 4, 0)
	row.reason:SetWidth(130)
	row.buttons = {}
	local x = 0
	for n = 1, 3 do
		local b = W.Button(row, { width = 78, height = View.ROW_HEIGHT - 2, onClick = function(self)
			local d = self:GetParent().data
			if not (d and self.action) then return end
			local ok, why = Mode.Act(d.id, self.action, Mode.noteText and Mode.noteText() or nil)
			if not ok then print_(L["BANKREQ_ERR_ACT"]:format(tostring(why))) end
			View:Redraw()
		end })
		b:SetPoint("RIGHT", row, "RIGHT", -(4 + (3 - n) * 80), 0)
		row.buttons[n] = b
	end
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not (d and GameTooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(d.what or "")
		if d.reason then GameTooltip:AddLine(d.reason, 1, 1, 1, true) end
		for _, h in ipairs(d.history) do GameTooltip:AddLine(Mode.HistoryLine(h)) end
		if d.note then GameTooltip:AddLine(L["BANKREQ_NOTE"]:format(d.note), 1, 0.4, 0.4, true) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	area.rows[i] = row
	return row
end

local BUTTON_TEXT = { cancel = "BANKREQ_CANCEL", approved = "BANKREQ_APPROVE", rejected = "BANKREQ_REJECT", fulfilled = "BANKREQ_FULFILL" }

local function fillRow(row, d)
	row.data = d
	row.status:SetText(d.statusText)
	row.status:SetTextColor(Skin.Color(STATUS_COLOR[d.status] or "white"))
	row.name:SetText(d.name or "?")
	row.kind:SetText(d.kindText)
	row.what:SetText(d.what)
	if d.suggestion then
		row.reason:SetText(Mode.SuggestionText(d.suggestion))
		row.reason:SetTextColor(Skin.Color("gold"))
	else
		row.reason:SetText(d.reason or "")
		row.reason:SetTextColor(Skin.Color("grey"))
	end
	local actions = {}
	if d.canCancel then actions[#actions + 1] = "cancel" end
	for _, m in ipairs(d.moves) do actions[#actions + 1] = m end
	for n, b in ipairs(row.buttons) do
		local action = actions[n]
		b.action = action
		if action then b:SetLabel(L[BUTTON_TEXT[action]]) b:Show() else b:Hide() end
	end
	row:Show()
end

-- The list under the form (or at the top of a mode without one): virtual rows and the empty-list message.
local function buildArea(f, top)
	local area = W.Frame(f, 10, 10)
	area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
	area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 0)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	area:SetScript("OnSizeChanged", function() View:Redraw() end)
	area.rows = {}
	f.area = area
	f.message = W.Text(f, "body", "grey", "CENTER")
	f.message:SetPoint("CENTER", area, "CENTER", 0, 0)
	f.message:SetWidth(380)
end

local function visibleRows(area)
	local h = area and area:GetHeight() or 0
	if not h or h < View.ROW_HEIGHT then return View.DEFAULT_ROWS end
	return max(1, floor(h / View.ROW_HEIGHT))
end

local function drawRows(f, rows, emptyText)
	View.rowsShown = rows
	local total, visible = #rows, visibleRows(f.area)
	View.offset = max(0, min(View.offset or 0, max(0, total - visible)))
	local drawn = max(0, min(visible + 1, total - View.offset))
	for i = 1, drawn do fillRow(f.area.rows[i] or newRow(f.area, i), rows[View.offset + i]) end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	if total == 0 then
		f.message:SetText(emptyText)
		f.message:Show()
	else
		f.message:Hide()
	end
	return total
end

function mode.build(f)
	f.kindButtons = {}
	local x = 8
	for i, kind in ipairs(ns.BankRequests and ns.BankRequests.KINDS or { "withdraw", "deposit", "donation" }) do
		local b = W.Button(f, { text = Mode.KindText(kind), width = 96, height = 20, onClick = function() Mode.kind = kind View:Redraw() end })
		b:SetPoint("TOPLEFT", f, "TOPLEFT", x + (i - 1) * 100, -4)
		b.kind = kind
		f.kindButtons[i] = b
	end
	f.tip = W.Text(f, "small", "grey", "LEFT")
	f.tip:SetPoint("LEFT", f.kindButtons[3], "RIGHT", 10, 0)
	f.tip:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.itemLabel = W.Text(f, "small", "grey", "LEFT")
	f.itemLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
	f.itemLabel:SetText(L["BANKREQ_ITEM"])
	f.item = editBox(f, 210, 120)
	f.item:SetPoint("TOPLEFT", f.itemLabel, "BOTTOMLEFT", 0, -2)
	f.amount = editBox(f, 70, 9)
	f.amount:SetPoint("LEFT", f.item, "RIGHT", 14, 0)
	f.amountLabel = W.Text(f, "small", "grey", "LEFT")
	f.amountLabel:SetPoint("BOTTOMLEFT", f.amount, "TOPLEFT", 0, 2)
	f.reason = editBox(f, 210, 120)
	f.reason:SetPoint("LEFT", f.amount, "RIGHT", 14, 0)
	f.reasonLabel = W.Text(f, "small", "grey", "LEFT")
	f.reasonLabel:SetPoint("BOTTOMLEFT", f.reason, "TOPLEFT", 0, 2)
	f.reasonLabel:SetText(L["BANKREQ_REASON"])
	f.send = W.Button(f, { text = L["BANKREQ_SEND"], width = 110, height = 22, onClick = function()
		local ok, text = Mode.Submit({ kind = Mode.kind, item = f.item:GetText(), amount = f.amount:GetText(), reason = f.reason:GetText() })
		f.status:SetText(text or "")
		f.status:SetTextColor(Skin.Color(ok and "green" or "red"))
		if ok then f.item:SetText("") f.amount:SetText("") f.reason:SetText("") end
		View:Redraw()
	end })
	f.send:SetPoint("LEFT", f.reason, "RIGHT", 10, 0)
	f.status = W.Text(f, "small", nil, "LEFT")
	f.status:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -4)
	f.status:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.mine = W.Check(f, { text = L["BANKREQ_ONLY_MINE"], width = 150, onClick = function(checked) Mode.onlyMine = checked View.offset = 0 View:Redraw() end })
	f.mine:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -Mode.FORM_HEIGHT + 22)
	f.closed = W.Check(f, { text = L["BANKREQ_SHOW_CLOSED"], width = 170, onClick = function(checked) Mode.showClosed = checked View.offset = 0 View:Redraw() end })
	f.closed:SetPoint("LEFT", f.mine, "RIGHT", 12, 0)
	buildArea(f, Mode.FORM_HEIGHT)
	Mode.noteText = function() return f.reason:GetText() end
end

function mode.refresh(f)
	Mode.noteText = function() return f.reason:GetText() end
	for _, b in ipairs(f.kindButtons) do
		local text = Mode.KindText(b.kind)
		b:SetLabel(b.kind == Mode.kind and ("> " .. text .. " <") or text)
	end
	f.tip:SetText(L["BANKREQ_TIP_" .. Mode.kind:upper()])
	f.amountLabel:SetText(L["BANKREQ_AMOUNT_ITEM"])
	f.mine:SetChecked(Mode.onlyMine)
	f.closed:SetChecked(Mode.showClosed)
	local rows = Mode.Rows({ search = View.search, onlyMine = Mode.onlyMine, showClosed = Mode.showClosed })
	return drawRows(f, rows, View.search ~= "" and L["BANK_NO_MATCH"] or L["BANKREQ_EMPTY"])
end

---------------------------------------------------------------------------------------------------------------------
-- The officers' inbox (BANK-23, BANK-24)
---------------------------------------------------------------------------------------------------------------------
-- "Looks delivered: Bob took Linen Cloth x20, 3 h ago" for the log entry that matches a request.
function Mode.SuggestionText(e)
	local Log = ns.BankLog
	local what
	if Log and e.tab == Log.MONEY_TAB then
		what = View.MoneyText(e.count)
	else
		local info = View.ItemInfo(e.itemID)
		what = (info.name or L["BANK_ITEM_LOADING"]:format(e.itemID)) .. " x" .. e.count
	end
	local ago = ns.Shell and ns.Shell.Ago(max(0, now() - e.t)) or ""
	return L["BANKREQ_LOOKS_DONE"]:format(e.name, what, ago)
end

-- The rows of the inbox: what needs an officer, oldest first, with the suggestion; each gets `what`, `kindText`, `statusText`.
function Mode.InboxRows(opts)
	opts = opts or {}
	local Inbox = ns.BankInbox
	if not Inbox then return {} end
	local query = lower(opts.search)
	local out = {}
	for _, r in ipairs(Inbox:Rows()) do
		r.what = Mode.WhatText(r)
		r.kindText, r.statusText = Mode.KindText(r.kind), Mode.StatusText(r.status)
		if query == "" or lower(r.name):find(query, 1, true) or lower(r.what):find(query, 1, true) or lower(r.reason):find(query, 1, true) then
			out[#out + 1] = r
		end
	end
	return out
end

local inbox = {}

function inbox.build(f)
	f.explain = W.Text(f, "small", "grey", "LEFT")
	f.explain:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
	f.explain:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.explain:SetText(L["BANKREQ_INBOX_EXPLAIN"])
	buildArea(f, 26)
	Mode.noteText = Mode.noteText or function() return "" end
end

function inbox.refresh(f)
	Mode.noteText = function() return Mode.inboxNote or "" end
	return drawRows(f, Mode.InboxRows({ search = View.search }), View.search ~= "" and L["BANK_NO_MATCH"] or L["BANKREQ_INBOX_EMPTY"])
end

local function isOfficer() return ns.Role ~= nil and ns.Role:IsOfficer() end
View.AddMode("inbox", {
	label = L["BANK_MODE_INBOX"], order = 22, build = inbox.build, refresh = inbox.refresh, search = true,
	available = isOfficer,
})

View.AddMode("requests", { label = L["BANK_MODE_REQUESTS"], order = 25, build = mode.build, refresh = mode.refresh, search = true })

if ns.addon then
	ns.addon.BankRequestsView = Mode
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set) if set == "bankreq" then View:Changed() end end)
		ns.Bus:On("BANKREQ_CHANGED", function() View:Changed() end)
	end
end

-- Requests and Inbox modes of the Bank view (SPEC-08 BANK-20..BANK-27, SPEC-03 §7). Lua 5.1.
--
-- A form at the top opens a request: the kind (Withdraw, Deposit, Donation), the item, how many (or how much gold), an
-- optional tip in gold (withdrawals only) and a reason. For a withdrawal the item box picks from the bank as this
-- character sees it (BANK-25): a list under the box, filtered by what is typed, with the quantity the bank holds; the line
-- under the box says it with the age of the snapshot (the provenance label) and the quantity stops there. An item link or
-- an item number pasted into the box still works; the box empty means gold. Below the form every request of the guild is
-- listed, newest first, with its status; the requester sees [Cancel] on an open request of their own, and an officer sees
-- the moves the request allows ([Approve], [Reject], [Fulfilled]); the reason box also carries the officer's reason for a
-- rejection. The tooltip of a row shows the tip (to those who may see it) and the history (who moved it and when).
--
-- The Inbox mode is the officers' list (BANK-27): date and time, requester, item, quantity and tip of the requests that
-- wait, sorted by date (oldest or newest first) or by tip, with the "looks delivered" and "looks paid" proposals. Handing
-- the item over stays manual (BANK-24), and so does paying a tip (BANK-26): the addon never moves items or gold.
--
-- Mode.ShowRequest(id, "inbox" | "requests") opens the view on one request (the Action Center, SPEC-13 §2.3).
-- Mode.Prefill({ item, name, count, reason }) opens the form filled in (the shopping list's Ask the bank, SPEC-17 §5.8).
--
-- Mode.Choices, Mode.Resolve, Mode.BankLine, Mode.Submit, Mode.Rows, Mode.InboxRows and Mode.Act are plain functions
-- (tested offline); the frames only draw and call them.
local ADDON_NAME, ns = ...
ns = ns or {}
local Mode = {}
ns.BankRequestsView, ns.modules = Mode, ns.modules or {}
ns.modules.BankRequestsView = Mode

local View = ns.BankView
if not View then return end
local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, select, tostring, tonumber, floor, max, min = type, ipairs, pairs, select, tostring, tonumber, math.floor, math.max, math.min

Mode.kind = "withdraw"
Mode.onlyMine = false
Mode.showClosed = false
Mode.FORM_HEIGHT = 184
Mode.picked = nil               -- { id, text }: the bank item chosen from the list, while the box still shows its text
Mode.inboxSort = "oldest"       -- BankInbox.SORTS
Mode.INBOX_ROW = 44
Mode.INBOX_TOP = 96             -- the explanation, the sort chips and the column titles above the officers' list
Mode.PICKER_ROWS = 7
Mode.DATE_FORMAT = "%Y-%m-%d %H:%M"   -- the local date and time of a request in the officers' list

local OPEN_STATES = { open = true, approved = true }
local function now() return ns.Compat and ns.Compat.ServerTime() or 0 end
local function lower(s) return type(s) == "string" and s:lower() or "" end
local function print_(msg) if ns.addon and msg then ns.addon:Print(msg) end end
local function trim(s) return type(s) == "string" and (s:gsub("^%s+", ""):gsub("%s+$", "")) or "" end

---------------------------------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------------------------------
function Mode.KindText(kind) return L["BANKREQ_KIND_" .. tostring(kind):upper()] end
function Mode.StatusText(status) return L["BANKREQ_STATUS_" .. tostring(status):upper()] end
local STATUS_TOKEN = { open = "accent-text", approved = "ok", fulfilled = "ok", rejected = "err", cancelled = "text-3" }

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
-- Picking an item from the bank (BANK-25) and the tip (BANK-26)
---------------------------------------------------------------------------------------------------------------------
-- The bank items a withdrawal can pick: { id, name (nil while not loaded), available, time, author, text }, by name (the
-- names not loaded yet last). `query` keeps the names that contain it, or the item with that number.
function Mode.Choices(query)
	local Req = ns.BankRequests
	if not Req then return {} end
	local q = lower(trim(query))
	local out = {}
	for id, held in pairs(Req:BankItems()) do
		local name = View.ItemInfo(id).name
		if q == "" or lower(name):find(q, 1, true) or tostring(id) == q then
			out[#out + 1] = { id = id, name = name, available = held.available, time = held.time, author = held.author,
				text = L["BANKREQ_CHOICE"]:format(name or L["BANK_ITEM_LOADING"]:format(id), held.available) }
		end
	end
	table.sort(out, function(a, b)
		local an, bn = lower(a.name or "~"), lower(b.name or "~")
		if an ~= bn then return an < bn end
		return a.id < b.id
	end)
	return out
end

-- The item the box means: the one picked from the list while the box still shows it; else a link or a number; else, for a
-- withdrawal, the only bank item with exactly that name. Returns the item id; nothing for an empty box (gold); or nil and
-- "item" (not an item) or "pick" (several bank items have that name).
function Mode.Resolve(kind, text, picked)
	local Req = ns.BankRequests
	text = trim(text)
	if text == "" or not Req then return nil end
	if picked and picked.text == text then return picked.id end
	local id = Req.ParseItem(text)
	if id then return id end
	if kind == "withdraw" then
		local found, n, wanted = nil, 0, lower(text)
		for _, c in ipairs(Mode.Choices(text)) do
			if lower(c.name) == wanted then found, n = c.id, n + 1 end
		end
		if n == 1 then return found end
		if n > 1 then return nil, "pick" end
	end
	return nil, "item"
end

local function fromBank(held)
	return held and { source = "shared", observedAt = held.time, author = held.author, set = "bank" } or nil
end

-- The line under the item box of a withdrawal: { text, info = the provenance of the snapshot (UI/Provenance.lua) or nil,
-- max = the most the request may ask, for an item the bank shows }.
function Mode.BankLine(text, picked)
	local Req = ns.BankRequests
	local items = Req and Req:BankItems() or {}
	local n, oldest = 0, nil
	for _, held in pairs(items) do
		n = n + 1
		if not oldest or held.time < oldest.time or (held.time == oldest.time and held.author < oldest.author) then oldest = held end
	end
	if n == 0 then return { text = L["BANKREQ_STOCK_EMPTY"] } end
	local id = Mode.Resolve("withdraw", text, picked)
	if not id then return { text = L["BANKREQ_STOCK_PICK"]:format(n), info = fromBank(oldest) } end
	local held = items[id]
	if not held then return { text = L["BANKREQ_STOCK_NONE"], info = fromBank(oldest) } end
	return { text = L["BANKREQ_STOCK"]:format(held.available), info = fromBank(held), max = Req:MaxCount("withdraw", id, items) }
end

-- The quantity box stops at what the bank holds: the capped text when `amountText` asks for more of the item, else nil.
function Mode.CappedAmount(itemText, amountText, picked)
	local Req = ns.BankRequests
	local number = tonumber((tostring(amountText or ""):gsub("%s", "")))
	local id = Mode.Resolve("withdraw", itemText, picked)
	if not (Req and id and number) then return nil end
	local most = Req:MaxCount("withdraw", id)
	if number > most then return tostring(most) end
	return nil
end

-- The tip as typed, in whole gold pieces: nil for none (empty or 0), the amount in copper, or false when it is not a whole
-- number the limit allows.
function Mode.ParseTip(text)
	local Req = ns.BankRequests
	text = (tostring(text or ""):gsub("%s", ""))
	if text == "" then return nil end
	if not (Req and text:find("^%d+$")) then return false end
	local gold = tonumber(text)
	if gold == 0 then return nil end
	local copper = gold * Req.COPPER_PER_GOLD
	if not Req.ValidTip(copper) then return false end
	return copper
end

---------------------------------------------------------------------------------------------------------------------
-- Rows and actions
---------------------------------------------------------------------------------------------------------------------
local function describe(r)
	r.what = Mode.WhatText(r)
	r.kindText, r.statusText = Mode.KindText(r.kind), Mode.StatusText(r.status)
	r.ago = ns.Shell and ns.Shell.Ago(max(0, now() - (r.created or 0))) or ""
	r.tipText = r.tip and View.MoneyText(r.tip) or nil
end

local function matches(r, query)
	return query == "" or lower(r.name):find(query, 1, true) or lower(r.what):find(query, 1, true) or lower(r.reason):find(query, 1, true)
end

-- The requests to list: open and approved ones, and the closed ones when showClosed; only this player's when onlyMine; the
-- panel search filters by requester name, item name or reason. Each row adds `what`, `kindText`, `statusText`, `ago`,
-- `tipText` (when the player may see a tip) and, for officers, `paid` (the deposit that looks like the tip's payment).
function Mode.Rows(opts)
	opts = opts or {}
	local Req = ns.BankRequests
	if not Req then return {} end
	local status = (not opts.showClosed) and OPEN_STATES or nil
	local query = lower(opts.search)
	local paid = ns.BankInbox and ns.BankInbox:Payments() or {}
	local out = {}
	for _, r in ipairs(Req:List({ status = status, own = opts.onlyMine })) do
		describe(r)
		r.paid = paid[r.id]
		if matches(r, query) then out[#out + 1] = r end
	end
	return out
end

-- Opens a request from the text of the form: spec = { kind, item, picked, amount, tip, reason } (strings as typed; picked is
-- Mode.picked). With an item `amount` is how many; without one it is gold (whole gold pieces). The tip (gold) counts for a
-- withdrawal only. Returns true, or false and the text to show.
function Mode.Submit(spec)
	local Req = ns.BankRequests
	if not Req then return false, L["BANKREQ_ERR_GUILD"] end
	local number = tonumber((tostring(spec.amount or ""):gsub("%s", "")))
	local request = { kind = spec.kind, reason = spec.reason }
	local id, bad = Mode.Resolve(spec.kind, spec.item, spec.picked)
	if bad then return false, L["BANKREQ_ERR_" .. bad:upper()] end
	if id then
		request.itemID = id
		request.count = number and floor(number) or 1
	else
		if not number then return false, L["BANKREQ_ERR_AMOUNT"] end
		request.amount = floor(number) * 10000
	end
	if spec.kind == "withdraw" then
		local tip = Mode.ParseTip(spec.tip)
		if tip == false then return false, L["BANKREQ_ERR_TIP"] end
		request.tip = tip
	end
	local rec, why, most = Req:Create(request)
	if not rec then
		if why == "stock" then return false, L["BANKREQ_ERR_STOCK"]:format(most) end
		local text = L["BANKREQ_ERR_" .. tostring(why):upper()]
		return false, text ~= "BANKREQ_ERR_" .. tostring(why):upper() and text or L["BANKREQ_ERR_OTHER"]:format(tostring(why))
	end
	if rec.tip then return true, L["BANKREQ_SENT_TIP"]:format(View.MoneyText(rec.tip)) end
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

-- Opens the Bank view on one request (a row of the Action Center): `where` is "inbox" (the officers' list, only for
-- officers) or "requests" (the player's own requests). The search is cleared, the list scrolls to the request and its row
-- is marked until the list is left.
function Mode.ShowRequest(id, where)
	local officer = ns.Role ~= nil and ns.Role:IsOfficer()
	if where ~= "inbox" or not officer then where = "requests" end
	View.search = ""
	local bar = ns.Shell and ns.Shell.content and ns.Shell.content.bar
	if bar then bar.search:SetText("") end
	if where == "requests" then Mode.onlyMine, Mode.showClosed = true, false end
	View.mode = where
	View.offset = 0
	local rows = where == "inbox" and Mode.InboxRows({ sort = Mode.inboxSort }) or Mode.Rows({ onlyMine = true })
	for i, r in ipairs(rows) do
		if r.id == id then View.offset = i - 1 break end
	end
	if not (ns.Shell and ns.Shell:OpenView("bank")) then return false end
	Mode.focus = id
	View:Redraw()
	return true
end

-- Opens the request form prefilled (the shopping list's "Ask the bank", SPEC-17 §5.8): a withdrawal of `item`, `count`
-- (the caller gives min(missing, available)) and `reason`; the player checks it and presses Send. spec = { item, name,
-- count, reason }. Returns true when the Bank view opened.
function Mode.Prefill(spec)
	if type(spec) ~= "table" or type(spec.item) ~= "number" then return false end
	Mode.kind = "withdraw"
	Mode.picked = { id = spec.item, text = spec.name or tostring(spec.item) }
	Mode.prefill = { item = Mode.picked.text, amount = spec.count and tostring(spec.count) or "",
		reason = ns.BankRequests.CleanText(spec.reason or ""):sub(1, ns.BankRequests.MAX_REASON) }
	View.search = ""
	local bar = ns.Shell and ns.Shell.content and ns.Shell.content.bar
	if bar then bar.search:SetText("") end
	Mode.onlyMine, Mode.showClosed = true, false
	View.mode = "requests"
	View.offset = 0
	if not (ns.Shell and ns.Shell:OpenView("bank")) then return false end
	View:Redraw()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local mode = {}

local function editBox(parent, width, maxLetters)
	return Widgets.EditBox(parent, { width = width, dense = true, maxLetters = maxLetters or 60 })
end

-- The lines of a row's tooltip: what, the reason, the tip and its payment hint, the history, the officer's note
-- (Widgets.Tooltip content).
function Mode.TooltipLines(d)
	if type(d) ~= "table" then return nil end
	local lines = { d.what or "" }
	if d.reason then lines[#lines + 1] = d.reason end
	if d.tipText then lines[#lines + 1] = { text = L["BANKREQ_GIFT_LINE"]:format(d.tipText), token = "accent-text" } end
	if d.suggestion then lines[#lines + 1] = { text = Mode.SuggestionText(d.suggestion), token = "ok" } end
	if d.paid then lines[#lines + 1] = { text = Mode.PaidText(d.paid), token = "ok" } end
	for _, h in ipairs(d.history or {}) do lines[#lines + 1] = { text = Mode.HistoryLine(h), token = "text-3" } end
	if d.note then lines[#lines + 1] = { text = L["BANKREQ_NOTE"]:format(d.note), token = "err" } end
	return lines
end

-- A cell of a row stays on its line: what does not fit is cut (the tooltip of the row says it whole).
local function oneLine(...)
	for i = 1, select("#", ...) do
		local fs = select(i, ...)
		if fs.SetWordWrap then fs:SetWordWrap(false) end
	end
end

-- The three buttons of a row (cancel and the officer's moves), `width` wide, at its right end.
local function addButtons(row, width, height)
	row.buttons = {}
	for n = 1, 3 do
		local b = Widgets.Button(row, { style = "tonal", width = width, height = height, onClick = function(self)
			local d = self:GetParent().data
			if not (d and self.action) then return end
			local ok, why = Mode.Act(d.id, self.action, Mode.noteText and Mode.noteText() or nil)
			if not ok then print_(L["BANKREQ_ERR_ACT"]:format(tostring(why))) end
			View:Redraw()
		end })
		b:SetPoint("RIGHT", row, "RIGHT", -(4 + (3 - n) * (width + 4)), 0)
		row.buttons[n] = b
	end
end

-- A row of an area: a button of the area's row height, with its tooltip and hover.
local function baseRow(area, i)
	local height = area.rowHeight or View.ROW_HEIGHT
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(height)
	row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * height)
	row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * height)
	Widgets.Tooltip.Attach(row, function(self) return Mode.TooltipLines(self.data) end, "RIGHT")
	Widgets.RowHover(row)
	row.focus = Widgets.Selection(row)   -- the request the Action Center opened: the selected row
	area.rows[i] = row
	return row
end

local function newRow(area, i)
	local row = baseRow(area, i)
	row.status = Widgets.Text(row, "Small", "text-2", "LEFT")
	row.status:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.status:SetWidth(74)
	row.name = Widgets.Text(row, "BodyMedium", "text-1", "LEFT")
	row.name:SetPoint("LEFT", row.status, "RIGHT", 4, 0)
	row.name:SetWidth(96)
	row.kind = Widgets.Text(row, "Small", "text-3", "LEFT")
	row.kind:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
	row.kind:SetWidth(66)
	row.what = Widgets.Text(row, "Body", "accent-text", "LEFT")
	row.what:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
	row.what:SetWidth(170)
	row.reason = Widgets.Text(row, "Small", "text-3", "LEFT")
	row.reason:SetPoint("LEFT", row.what, "RIGHT", 4, 0)
	row.reason:SetWidth(130)
	oneLine(row.name, row.what, row.reason)
	addButtons(row, 80, Widgets.HEIGHT.small)
	return row
end

local BUTTON_TEXT = { cancel = "BANKREQ_CANCEL", approved = "BANKREQ_APPROVE", rejected = "BANKREQ_REJECT", fulfilled = "BANKREQ_FULFILL" }

local function fillButtons(row, d)
	local actions = {}
	if d.canCancel then actions[#actions + 1] = "cancel" end
	for _, m in ipairs(d.moves) do actions[#actions + 1] = m end
	for n, b in ipairs(row.buttons) do
		local action = actions[n]
		b.action = action
		if action then
			b:SetLabel(L[BUTTON_TEXT[action]])
			b:Show()
		else
			b:Hide()
		end
	end
end

-- The texts of the selected row are on-secondary-container; the others keep their own colours.
local function paintRow(row, d, tokens)
	local on = Mode.focus == d.id
	row.focus:SetShown(on)
	for key, token in pairs(tokens) do Theme.Text(row[key], on and "on-secondary-container" or token) end
end

local function fillRow(row, d)
	row.data = d
	row.status:SetText(d.statusText)
	Theme.Text(row.status, STATUS_TOKEN[d.status] or "text-2")
	row.name:SetText(d.name or "?")
	row.kind:SetText(d.kindText)
	row.what:SetText(d.what)
	local reason = d.reason or ""
	if d.tipText then
		local tip = L["BANKREQ_GIFT_SHORT"]:format(d.tipText)
		reason = reason ~= "" and (tip .. " - " .. reason) or tip
	end
	row.reason:SetText(reason)
	fillButtons(row, d)
	paintRow(row, d, { status = STATUS_TOKEN[d.status] or "text-2", name = "text-1", kind = "text-3", what = "accent-text",
		reason = "text-3" })
	row:Show()
end

-- The list under the form (or at the top of a mode without one): virtual rows and the empty-list message.
local function buildArea(f, top)
	local area = CreateFrame("Frame", nil, f)
	area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
	area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	area:SetClipsChildren(true)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	area:SetScript("OnSizeChanged", function() View:Redraw() end)
	area:SetScript("OnHide", function() Mode.focus = nil end)
	area.rows = {}
	f.area = area
	f.message = Widgets.Text(f, "Body", "text-3", "CENTER")
	f.message:SetPoint("CENTER", area, "CENTER", 0, 0)
	f.message:SetWidth(380)
end

local function visibleRows(area)
	local h = area and area:GetHeight() or 0
	local row = area and area.rowHeight or View.ROW_HEIGHT
	if not h or h < row then return View.DEFAULT_ROWS end
	return max(1, floor(h / row))
end

local function drawRows(f, rows, emptyText)
	View.rowsShown = rows
	local total, visible = #rows, visibleRows(f.area)
	View.offset = max(0, min(View.offset or 0, max(0, total - visible)))
	local drawn = max(0, min(visible + 1, total - View.offset))
	local make, fill = f.area.newRow or newRow, f.area.fillRow or fillRow
	for i = 1, drawn do fill(f.area.rows[i] or make(f.area, i), rows[View.offset + i]) end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	if total == 0 then
		f.message:SetText(emptyText)
		f.message:Show()
	else
		f.message:Hide()
	end
	return total
end

local function caption(parent, text)
	local fs = Widgets.Text(parent, "Eyebrow", "text-3", "LEFT")
	if text then fs:SetText(text) end
	return fs
end

local function closePicker(f)
	if f.picker then f.picker:Hide() end
end

-- The line under the item box of a withdrawal: how many the bank holds, and how old that is.
local function updateBankLine(f)
	local withdraw = Mode.kind == "withdraw"
	f.stock:SetShown(withdraw)
	if not withdraw then
		f.prov:SetSource(nil)
		return
	end
	local line = Mode.BankLine(f.item:GetText(), Mode.picked)
	f.stock:SetText(line.text)
	f.prov:SetSource(line.info)
end

-- The quantity box stops at what the bank holds.
local function capAmount(f)
	if Mode.kind ~= "withdraw" then return end
	local capped = Mode.CappedAmount(f.item:GetText(), f.amount:GetText(), Mode.picked)
	if capped then f.amount:SetText(capped) end
end

-- The list under the item box: the bank items that match what is typed. Closed for a deposit or a donation, for a pasted
-- link, and when nothing matches.
local function openPicker(f)
	if Mode.kind ~= "withdraw" then return closePicker(f) end
	local text = f.item:GetText() or ""
	if Mode.picked and Mode.picked.text == text then text = "" end   -- a chosen item: the whole list again
	if text:find("item:", 1, true) then return closePicker(f) end
	local choices = Mode.Choices(text)
	if #choices == 0 then return closePicker(f) end
	local offset = f.picker:IsShown() and f.list.offset or 0
	f.list:SetChoices(choices)
	f.list:Scroll(offset)
	f.picker:Show()
end

local function pick(f, id)
	for _, c in ipairs(f.list.choices) do
		if c.id == id then
			local text = c.name or tostring(id)
			Mode.picked = { id = id, text = text }
			f.item:SetText(text)
			break
		end
	end
	f.list:Clear()
	closePicker(f)
	f.item:ClearFocus()
	capAmount(f)
	updateBankLine(f)
end

local function buildPicker(f)
	local picker = CreateFrame("Frame", nil, f)
	picker:SetFrameStrata("DIALOG")
	picker:SetToplevel(true)
	picker:SetSize(300, Mode.PICKER_ROWS * Widgets.HEIGHT.small + 8)
	picker:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -2)
	picker:Hide()
	local catcher = CreateFrame("Button", nil, picker)   -- a click anywhere else closes the list
	catcher:SetFrameStrata("DIALOG")
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameLevel(max(picker:GetFrameLevel() - 1, 0))
	catcher:SetScript("OnClick", function() closePicker(f) end)
	f.picker, f.catcher = picker, catcher
	f.list = Widgets.ChoiceList(picker, { rows = Mode.PICKER_ROWS, width = 300, menu = true, onSelect = function(id) pick(f, id) end })
	f.list:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, 0)
	f.item.edit:HookScript("OnEditFocusGained", function() openPicker(f) end)
	f.item.edit:HookScript("OnMouseDown", function() openPicker(f) end)
	f.item.edit:HookScript("OnEscapePressed", function() closePicker(f) end)
	f.item.edit:HookScript("OnEnterPressed", function() closePicker(f) end)
	f:HookScript("OnHide", function() closePicker(f) end)
end

-- The form is a card: the kind (chips) and its hint, the fields with their captions (the tip box for a withdrawal only),
-- Send, and the line of the bank under the item box; under the card the two filter chips and the list.
function mode.build(f)
	f.card = Widgets.Card(f, { height = Mode.FORM_HEIGHT - 44 })
	f.card:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.card:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	local card = f.card
	local kinds = ns.BankRequests and ns.BankRequests.KINDS or { "withdraw", "deposit", "donation" }
	f.kinds = Widgets.ChipRow(card, function(kind) Mode.kind = kind closePicker(f) View:Redraw() end)
	f.kinds:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -12)
	local items = {}
	for i, kind in ipairs(kinds) do items[i] = { id = kind, text = Mode.KindText(kind) } end
	f.kinds:SetItems(items, Mode.kind)
	f.kinds:SetWidth(f.kinds.width)
	f.kindButtons = f.kinds.buttons
	for i, b in ipairs(f.kindButtons) do b.kind = kinds[i] end
	f.tip = Widgets.Text(card, "Small", "text-3", "LEFT")
	f.tip:SetPoint("LEFT", f.kinds, "RIGHT", 12, 0)
	f.tip:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	f.itemLabel = caption(card)
	f.itemLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -52)
	f.item = Widgets.EditBox(card, { width = 200, dense = true, maxLetters = 120, onChange = function(_, user)
		if not f.picker then return end   -- the form is still being built
		if user then
			Mode.picked = nil
			openPicker(f)
			capAmount(f)
		end
		updateBankLine(f)
	end })
	f.item:SetPoint("TOPLEFT", f.itemLabel, "BOTTOMLEFT", 0, -4)
	f.amount = Widgets.EditBox(card, { width = 70, dense = true, maxLetters = 9, onChange = function(_, user)
		if user then capAmount(f) end
	end })
	f.amount:SetPoint("LEFT", f.item, "RIGHT", 10, 0)
	f.amountLabel = caption(card)
	f.amountLabel:SetPoint("BOTTOMLEFT", f.amount, "TOPLEFT", 0, 4)
	f.gift = editBox(card, 64, 6)
	f.gift:SetPoint("LEFT", f.amount, "RIGHT", 10, 0)
	f.giftLabel = caption(card, L["BANKREQ_GIFT"])
	f.giftLabel:SetPoint("BOTTOMLEFT", f.gift, "TOPLEFT", 0, 4)
	f.reason = editBox(card, 170, 120)
	f.reasonLabel = caption(card, L["BANKREQ_REASON"])
	f.reasonLabel:SetPoint("BOTTOMLEFT", f.reason, "TOPLEFT", 0, 4)
	f.send = Widgets.Button(card, { text = L["BANKREQ_SEND"], style = "filled", dense = true, onClick = function()
		closePicker(f)
		local ok, text = Mode.Submit({ kind = Mode.kind, item = f.item:GetText(), picked = Mode.picked, amount = f.amount:GetText(),
			tip = f.gift:GetText(), reason = f.reason:GetText() })
		f.status:SetText(text or "")
		Theme.Text(f.status, ok and "ok" or "err")
		if ok then
			Mode.picked = nil
			f.item:SetText("") f.amount:SetText("") f.gift:SetText("") f.reason:SetText("")
		end
		View:Redraw()
	end })
	f.send:SetPoint("LEFT", f.reason, "RIGHT", 10, 0)
	f.stock = Widgets.Text(card, "Small", "text-3", "LEFT")
	f.stock:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -6)
	f.prov = Widgets.Provenance(card)   -- who read the bank and how old the snapshot is (M7.2)
	f.prov:SetPoint("LEFT", f.stock, "RIGHT", 10, 0)
	buildPicker(f)
	f.mine = Widgets.Chip(f, { text = L["BANKREQ_ONLY_MINE"], onClick = function(chip)
		chip:SetSelected(not chip:IsSelected())
		Mode.onlyMine = chip:IsSelected() View.offset = 0 View:Redraw()
	end })
	f.mine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Mode.FORM_HEIGHT + 38)
	f.closed = Widgets.Chip(f, { text = L["BANKREQ_SHOW_CLOSED"], onClick = function(chip)
		chip:SetSelected(not chip:IsSelected())
		Mode.showClosed = chip:IsSelected() View.offset = 0 View:Redraw()
	end })
	f.closed:SetPoint("LEFT", f.mine, "RIGHT", 8, 0)
	-- what Send answered, on the line of the filters
	f.status = Widgets.Text(f, "Small", "text-2", "LEFT")
	f.status:SetPoint("LEFT", f.closed, "RIGHT", 16, 0)
	f.status:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	buildArea(f, Mode.FORM_HEIGHT)
	Mode.noteText = function() return f.reason:GetText() end
end

function mode.refresh(f)
	Mode.noteText = function() return f.reason:GetText() end
	local fill = Mode.prefill
	if fill then   -- Ask the bank of the shopping list (Mode.Prefill)
		Mode.prefill = nil
		f.item:SetText(fill.item)
		f.amount:SetText(fill.amount)
		f.gift:SetText("")
		f.reason:SetText(fill.reason)
		f.status:SetText(L["BANKREQ_PREFILLED"])
		Theme.Text(f.status, "text-2")
	end
	f.kinds:Select(Mode.kind)
	f.tip:SetText(L["BANKREQ_TIP_" .. Mode.kind:upper()])
	local withdraw = Mode.kind == "withdraw"
	f.itemLabel:SetText(L[withdraw and "BANKREQ_ITEM_BANK" or "BANKREQ_ITEM"])
	f.item:SetPlaceholder(L[withdraw and "BANKREQ_ITEM_HINT_BANK" or "BANKREQ_ITEM_HINT"])
	f.amountLabel:SetText(L["BANKREQ_AMOUNT_ITEM"])
	f.gift:SetShown(withdraw)
	f.giftLabel:SetShown(withdraw)
	f.reason:ClearAllPoints()
	f.reason:SetPoint("LEFT", withdraw and f.gift or f.amount, "RIGHT", 10, 0)
	if f.picker:IsShown() then openPicker(f) end
	updateBankLine(f)
	f.mine:SetSelected(Mode.onlyMine)
	f.closed:SetSelected(Mode.showClosed)
	local rows = Mode.Rows({ search = View.search, onlyMine = Mode.onlyMine, showClosed = Mode.showClosed })
	return drawRows(f, rows, View.search ~= "" and L["BANK_NO_MATCH"] or L["BANKREQ_EMPTY"])
end

---------------------------------------------------------------------------------------------------------------------
-- The officers' list (BANK-23, BANK-24, BANK-27)
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

-- "Looks paid: Bob deposited 5g, 1 h ago" for the deposit that looks like the payment of a tip (BANK-26).
function Mode.PaidText(e)
	local ago = ns.Shell and ns.Shell.Ago(max(0, now() - e.t)) or ""
	return L["BANKREQ_LOOKS_PAID"]:format(e.name, View.MoneyText(e.count), ago)
end

-- The rows of the officers' list: what needs an officer, sorted by opts.sort (BankInbox.Sort; oldest first by default),
-- with the proposals; each gets what Mode.Rows adds and the cells `dateText`, `itemText`, `countText` (empty for gold) and
-- `giftText` ("-" without a tip).
function Mode.InboxRows(opts)
	opts = opts or {}
	local Inbox = ns.BankInbox
	if not Inbox then return {} end
	local query = lower(opts.search)
	local out = {}
	for _, r in ipairs(Inbox:Rows({ sort = opts.sort })) do
		describe(r)
		r.dateText = r.created and date(Mode.DATE_FORMAT, r.created) or ""
		if r.itemID then
			r.itemText = View.ItemInfo(r.itemID).name or L["BANK_ITEM_LOADING"]:format(r.itemID)
			r.countText = tostring(r.count or 1)
		else
			r.itemText, r.countText = r.what, ""
		end
		r.giftText = r.tipText or "-"
		if matches(r, query) then out[#out + 1] = r end
	end
	return out
end

-- The columns of the officers' list: the left ones from the left edge, quantity and tip before the buttons.
local COL = { date = 6, dateWidth = 108, name = 118, nameWidth = 90, item = 212, count = 36, gift = 62, buttons = 3 * 80 + 8 }

-- The five cells of a line (a row, or the column titles) on `parent`, into `row`.
local function cells(parent, row, font, token, y)
	row.date = Widgets.Text(parent, font or "MonoSmall", token or "text-3", "LEFT")
	row.date:SetPoint("TOPLEFT", parent, "TOPLEFT", COL.date, y)
	row.date:SetWidth(COL.dateWidth)
	row.name = Widgets.Text(parent, font or "BodyMedium", token or "text-1", "LEFT")
	row.name:SetPoint("TOPLEFT", parent, "TOPLEFT", COL.name, y)
	row.name:SetWidth(COL.nameWidth)
	row.gift = Widgets.Text(parent, font or "MonoMedium", token or "accent-text", "RIGHT")
	row.gift:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -COL.buttons, y)
	row.gift:SetWidth(COL.gift)
	row.count = Widgets.Text(parent, font or "MonoMedium", token or "text-1", "RIGHT")
	row.count:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(COL.buttons + COL.gift + 6), y)
	row.count:SetWidth(COL.count)
	row.what = Widgets.Text(parent, font or "Body", token or "accent-text", "LEFT")
	row.what:SetPoint("TOPLEFT", parent, "TOPLEFT", COL.item, y)
	row.what:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(COL.buttons + COL.gift + COL.count + 14), y)
	oneLine(row.date, row.name, row.what, row.count, row.gift)
end

-- Two lines: the five columns, then the status and the reason (or the proposals).
local function newInboxRow(area, i)
	local row = baseRow(area, i)
	cells(row, row, nil, nil, -7)
	row.status = Widgets.Text(row, "Small", "text-2", "LEFT")
	row.status:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", COL.date, 7)
	row.status:SetWidth(COL.dateWidth)
	row.reason = Widgets.Text(row, "Small", "text-3", "LEFT")
	row.reason:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", COL.name, 7)
	row.reason:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -COL.buttons, 7)
	oneLine(row.status, row.reason)
	addButtons(row, 76, Widgets.HEIGHT.small)
	return row
end

local function fillInboxRow(row, d)
	row.data = d
	row.date:SetText(d.dateText)
	row.name:SetText(d.name or "?")
	row.what:SetText(d.itemText)
	row.count:SetText(d.countText)
	row.gift:SetText(d.giftText)
	row.status:SetText(d.statusText)
	Theme.Text(row.status, STATUS_TOKEN[d.status] or "text-2")
	local hints = {}
	if d.suggestion then hints[#hints + 1] = Mode.SuggestionText(d.suggestion) end
	if d.paid then hints[#hints + 1] = Mode.PaidText(d.paid) end
	if #hints > 0 then
		row.reason:SetText(table.concat(hints, "   "))
		Theme.Text(row.reason, "accent-text")
	else
		row.reason:SetText(d.reason and (d.kindText .. " - " .. d.reason) or d.kindText)
		Theme.Text(row.reason, "text-3")
	end
	fillButtons(row, d)
	paintRow(row, d, { date = "text-3", name = "text-1", what = "accent-text", count = "text-1", gift = "accent-text",
		status = STATUS_TOKEN[d.status] or "text-2", reason = #hints > 0 and "accent-text" or "text-3" })
	row:Show()
end

local inbox = {}
local SORT_TEXT = { oldest = "BANKREQ_SORT_OLDEST", newest = "BANKREQ_SORT_NEWEST", tip = "BANKREQ_SORT_GIFT" }

function inbox.build(f)
	f.explain = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.explain:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
	f.explain:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.explain:SetText(L["BANKREQ_INBOX_EXPLAIN"])
	f.sorts = Widgets.ChipRow(f, function(id) Mode.inboxSort = id View.offset = 0 View:Redraw() end)
	f.sorts:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -24)
	f.sorts:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -24)
	local items = {}
	for i, id in ipairs(ns.BankInbox and ns.BankInbox.SORTS or {}) do items[i] = { id = id, text = L[SORT_TEXT[id]] } end
	f.sorts:SetItems(items, Mode.inboxSort)
	f.head = CreateFrame("Frame", nil, f)
	f.head:SetHeight(32)
	f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(Mode.INBOX_TOP - 34))
	f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(Mode.INBOX_TOP - 34))
	f.head.fill = Theme.Slice(f.head, "rr_fill_8", "surface-2", "BACKGROUND")
	f.head.fill:SetAllPoints(f.head)
	f.columns = {}
	cells(f.head, f.columns, "label-medium", "text-3", -10)
	f.columns.date:SetText(L["BANKREQ_COL_DATE"])
	f.columns.name:SetText(L["BANKREQ_COL_WHO"])
	f.columns.what:SetText(L["BANKREQ_COL_ITEM"])
	f.columns.count:SetText(L["BANKREQ_COL_COUNT"])
	f.columns.gift:SetText(L["BANKREQ_COL_GIFT"])
	buildArea(f, Mode.INBOX_TOP)
	f.area.rowHeight, f.area.newRow, f.area.fillRow = Mode.INBOX_ROW, newInboxRow, fillInboxRow
	Mode.noteText = Mode.noteText or function() return "" end
end

function inbox.refresh(f)
	Mode.noteText = function() return Mode.inboxNote or "" end
	f.sorts:Select(Mode.inboxSort)
	local rows = Mode.InboxRows({ search = View.search, sort = Mode.inboxSort })
	return drawRows(f, rows, View.search ~= "" and L["BANK_NO_MATCH"] or L["BANKREQ_INBOX_EMPTY"])
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
		ns.Bus:On("GUILD_CHANGED", function() Mode.picked, Mode.focus = nil, nil end)
	end
end

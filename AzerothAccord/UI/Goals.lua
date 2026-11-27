-- GoalsView: the "Goals" page of the Economy destination and the New goal window (M13.9; SPEC-17 §7.3; SPEC-10 Q48;
-- ui-style §9.11). Lua 5.1.
-- Chips choose the open goals or those closed in the last 90 days. Every column of the table sorts (ui-style §9.9). A
-- click on a row selects it: the bar under the table has the first contributors, how fresh the bank log is, how many tabs
-- were counted, the note and, for officers, Edit and Cancel goal (the second click, Confirm, writes it). New goal, for
-- officers only, is the one filled button of the page. Only with the switch "econ".
--   View.ProgressText(row), View.EndsText(row), View.LogText(row), View.WhoText(row), View.TipLines(row)  plain texts
--   View:Press(id)             Cancel goal: first click "armed", second true, or false and a reason
--   View:OpenNew(), View:OpenEdit(id), View:Place()     the window
--   View:Open(id), View:Select(id)
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.GoalsView, ns.modules = View, ns.modules or {}
ns.modules.GoalsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, tostring, tonumber, floor, max = ipairs, tostring, tonumber, math.floor, math.max
local concat = table.concat

View.ROW_HEIGHT = 36
View.TOOLBAR_HEIGHT = 40
View.BAR_HEIGHT = 116        -- the goal, the contributors, the log and the note, the buttons
View.WIDTH, View.HEIGHT = 460, 500
View.ICON = 20
View.REFRESH_DELAY = 0.4

View.show = "open"           -- "open" | "closed"
View.search = ""
View.selected = nil          -- the id of the selected goal
View.armed = nil             -- the id whose Cancel goal was clicked once
View.editing = nil           -- the id the window edits (nil: a new goal)

local function G() return ns.Goals end
local function now() return ns.Compat.ServerTime() end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end
local function ago(t) return ns.Provenance.AgeText(max(0, now() - (t or now()))) end
local function money(copper) return ns.BankView.MoneyText(copper) end

local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-3")
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function View.Amount(row, n)
	if row.kind == "gold" then return money(n) end
	return tostring(n)
end

-- What is collected: the item or "Gold".
function View.WhatText(row)
	if row.kind == "gold" then return L["GOAL_KIND_GOLD"] end
	return escape(row.itemName)
end

-- "340 / 500 · 68 %" (never 100 % before the target is reached).
function View.ProgressText(row)
	local pct = floor(row.fraction * 100)
	return L["GOAL_PROGRESS"]:format(View.Amount(row, row.have), View.Amount(row, row.target), pct)
end

function View.EndsText(row)
	local day = ns.Orders.DayText
	if row.state == "reached" then return L["GOAL_REACHED_ON"]:format(day(ns.Timeline.DayOf(row.reachedAt))) end
	if row.state == "ended" then return L["GOAL_ENDED_ON"]:format(day(row.ends)) end
	if row.state == "cancelled" then return L["GOAL_CANCELLED"] end
	if row.daysLeft == 0 then return L["GOAL_LAST_DAY"] end
	if row.daysLeft == 1 then return L["GOAL_DAY_LEFT"] end
	return L["GOAL_DAYS_LEFT"]:format(row.daysLeft)
end

function View.EndsToken(row)
	if row.state == "reached" then return "ok" end
	if row.state ~= "open" then return "text-3" end
	return "text-1"
end

-- The age of the newest bank log the goal counts from.
function View.LogText(row)
	if not row.logAt then return L["GOAL_NO_LOG"] end
	return L["GOAL_LOG_AGE"]:format(ago(row.logAt))
end

-- "Counted from the logs you can see: 3 of 5 tabs", for a goal in items when a tab is missing; else nil.
function View.TabsText(row)
	if row.kind ~= "items" or row.tabsSeen >= row.tabsTotal then return nil end
	return L["GOAL_TABS"]:format(row.tabsSeen, row.tabsTotal)
end

-- The first contributors, or nil when the viewer may not see them or nobody gave yet.
function View.WhoText(row)
	local list = row.contributors
	if not (list and list[1]) then return nil end
	local parts = {}
	for i = 1, G().TOP do
		local c = list[i]
		if c then parts[#parts + 1] = L["GOAL_WHO_ONE"]:format(escape(c.name), View.Amount(row, c.amount)) end
	end
	return L["GOAL_WHO"]:format(concat(parts, ", "))
end

function View.TipLines(row)
	local out = { escape(row.title) }
	local function add(text, token) if text then out[#out + 1] = { text = text, token = token or "text-2" } end end
	add(View.WhatText(row) .. " · " .. View.ProgressText(row))
	add(L["GOAL_ABOUT"]:format(ns.Orders.DayText(row.start), ns.Orders.DayText(row.ends)))
	add(View.EndsText(row), View.EndsToken(row))
	add(View.WhoText(row))
	if row.note then add(escape(row.note), "text-1") end
	add(View.LogText(row), row.stale and "warn" or "text-3")
	add(View.TabsText(row), "text-3")
	return out
end

local ERRORS = { off = "GOAL_ERR_OTHER", guild = "NOT_IN_GUILD", authority = "GOAL_ERR_AUTHORITY", item = "WISH_ERR_ITEM",
	target = "GOAL_ERR_TARGET", days = "GOAL_ERR_DAYS", title = "GOAL_ERR_TITLE", note = "ORD_ERR_NOTE",
	limit = "GOAL_ERR_LIMIT", locked = "GOAL_ERR_LOCKED", missing = "GOAL_ERR_MISSING", state = "GOAL_ERR_STATE" }

function View.ErrorText(why, kind)
	local M = G()
	if why == "target" then return L[ERRORS[why]]:format(kind == "gold" and M.GOLD_MAX or M.ITEMS_MAX) end
	if why == "days" then return L[ERRORS[why]]:format(M.DAYS_MAX) end
	if why == "title" then return L[ERRORS[why]]:format(M.TITLE_MAX) end
	if why == "note" then return L[ERRORS[why]]:format(M.NOTE_MAX) end
	if why == "limit" then return L[ERRORS[why]]:format(M.MAX_OPEN) end
	return L[ERRORS[why] or "GOAL_ERR_OTHER"]
end

---------------------------------------------------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------------------------------------------------
function View:Redraw()
	local f = self.frame
	if f then self.refresh(f) end
end

-- The data changed: one redraw after the burst, only while the page is visible.
function View:Changed()
	if self.timer or not (self.frame and self.frame:IsVisible()) then return end
	self.timer = true
	local scheduled = ns.Compat.After(View.REFRESH_DELAY, function()
		View.timer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.timer = nil self:Redraw() end
end

function View:SetSearch(text)
	text = type(text) == "string" and text or ""
	if text == self.search then return end
	self.search = text
	self:Redraw()
end

function View:Select(id)
	if self.selected ~= id then self.selected, self.armed, self.error = id, nil, nil end
	self:Redraw()
end

-- Cancel goal: the first click asks (the button says Confirm), the second one writes it.
function View:Press(id)
	if self.armed ~= id then
		self:Select(id)
		self.armed, self.error = id, nil
		self:Redraw()
		return "armed"
	end
	self.armed = nil
	local rec, why = G():Cancel(id)
	self.error = not rec and View.ErrorText(why) or nil
	self:Redraw()
	if not rec then return false, why end
	return true
end

function View:Open(id)
	if not (G() and G().Enabled() and ns.Shell) then return false end
	local row = id and G():Get(id)
	if row then
		self.show = row.state == "open" and "open" or "closed"
		self.selected, self.armed, self.error, self.search = row.id, nil, nil, ""
	end
	local shown = ns.Shell:OpenView("goals") and true or false
	self:Redraw()
	return shown
end

---------------------------------------------------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------------------------------------------------
local function pos(i) return View.frame.table.pos and View.frame.table.pos[i] end

local function columns()
	local function col(id, key, opts)
		opts.id, opts.title = id, L[key]
		return opts
	end
	return {
		col("title", "GOAL_COL_TITLE", { flex = 1.6, text = function(r) return escape(r.title) end,
			token = function(r) return r.state == "open" and "text-1" or "text-3" end }),
		col("what", "GOAL_COL_WHAT", { flex = 1.4, value = function(r) return r.kind == "gold" and L["GOAL_KIND_GOLD"] or r.itemName end,
			render = function(cell, row, frame)
				cell:SetText(View.WhatText(row))
				Theme.Text(cell, "text-2")
				local p = pos(2)
				if p then
					cell:ClearAllPoints()
					cell:SetWidth(max(p.w - View.ICON - 16, 1))
					cell:SetPoint("LEFT", frame, "LEFT", p.x + View.ICON + 8, 0)
				end
			end }),
		-- the figures, with the bar under them (setupRow)
		col("progress", "GOAL_COL_PROGRESS", { flex = 1.8, value = function(r) return r.fraction end,
			render = function(cell, row, frame)
				cell:SetText(View.ProgressText(row))
				Theme.Text(cell, row.stale and row.state == "open" and "text-3" or "text-1")
				local p = pos(3)
				if p then
					cell:ClearAllPoints()
					cell:SetWidth(max(p.w - 8, 1))
					cell:SetPoint("LEFT", frame, "LEFT", p.x, 5)
				end
			end }),
		col("ends", "GOAL_COL_ENDS", { width = 160, text = View.EndsText, token = View.EndsToken,
			value = function(r) return r.state == "open" and r.ends or r.closedAt end }),
	}
end

local function setupRow(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(View.ICON, View.ICON)
	row.progress = Widgets.ThinBar(row, { height = 4, width = 120 })
	row:HookScript("OnEnter", function(self)
		if self.data then Widgets.Tooltip.Show(self, View.TipLines(self.data), "BOTTOM") end
	end)
	row:HookScript("OnLeave", function() Widgets.Tooltip.Hide() end)
end

local function updateRow(row, d)
	local what, p = pos(2), pos(3)
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", what and what.x or 8, 0)
	local icon = d.item and ns.Compat.Item.Icon(d.item) or nil
	if icon then row.icon:SetTexture(icon) row.icon:Show() else row.icon:Hide() end
	row.progress:ClearAllPoints()
	row.progress:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", p and p.x or 8, 6)
	if p then row.progress:SetWidth(max(p.w - 16, 1)) end
	row.progress:SetFraction(d.fraction)
	-- muted: closed, or the newest log is old (SPEC-17 §7.2)
	row.progress:SetAlpha((d.state == "open" and d.stale or d.state == "ended" or d.state == "cancelled") and 0.4 or 1)
end

local function buildBar(f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(View.BAR_HEIGHT)
	bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	bar.line = Widgets.Divider(bar, "BORDER")
	bar.line:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
	local function line(style, token, under, gap)
		local fs = Widgets.Text(bar, style, token, "LEFT")
		if under then fs:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -gap)
		else fs:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -10) end
		fs:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
		fs:SetWordWrap(false)
		return fs
	end
	bar.info = line("Body", "text-1")
	bar.who = line("Small", "text-2", bar.info, 6)
	bar.detail = line("Small", "text-3", bar.who, 6)
	bar.edit = Widgets.Button(bar, { text = L["GOAL_EDIT"], style = "tonal", dense = true, onClick = function()
		if View.selected then View:OpenEdit(View.selected) end
	end })
	bar.edit:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 4)
	bar.cancel = Widgets.Button(bar, { text = L["GOAL_CANCEL"], style = "outlined", dense = true, onClick = function()
		if View.selected then View:Press(View.selected) end
	end })
	bar.cancel:SetPoint("LEFT", bar.edit, "RIGHT", 8, 0)
	f.foot = bar
end

local function drawBar(f, row)
	local bar = f.foot
	if not row then
		say(bar.info, L["GOAL_PICK"], "text-3")
		say(bar.who, "")
		say(bar.detail, View.error or "", "err")
		bar.edit:Hide()
		bar.cancel:Hide()
		return
	end
	say(bar.info, L["GOAL_BAR_INFO"]:format(escape(row.title), View.ProgressText(row), View.EndsText(row)), "text-1")
	say(bar.who, View.WhoText(row) or (row.contributors and L["GOAL_NOBODY"] or ""), "text-2")
	if View.error then
		say(bar.detail, View.error, "err")
	elseif View.armed == row.id then
		say(bar.detail, L["GOAL_ASK_CANCEL"], "warn")
	else
		local parts = { View.LogText(row), View.TabsText(row) }
		if row.note then parts[#parts + 1] = escape(row.note) end
		say(bar.detail, concat(parts, " · "), row.stale and row.state == "open" and "warn" or "text-3")
	end
	bar.edit:SetShown(row.canEdit)
	bar.cancel:SetShown(row.canEdit)
	bar.cancel:SetLabel(View.armed == row.id and L["ORD_CONFIRM"] or L["GOAL_CANCEL"])
end

function View.build(f)
	View.frame = f
	f.filter = Widgets.ChipRow(f, function(id)
		View.show, View.selected, View.armed, View.error = id, nil, nil, nil
		if f.table then f.table.offset = 0 end
		View:Redraw()
	end)
	f.filter:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.filter:SetWidth(240)
	f.new = Widgets.Button(f, { text = L["GOAL_NEW"], style = "filled", dense = true, onClick = function() View:OpenNew() end })
	f.new:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	buildBar(f)
	f.table = Widgets.DataTable(f, columns(), { rowHeight = View.ROW_HEIGHT, pool = 10, maxPool = 40, memory = "economy.goals",
		emptyText = L["GOAL_EMPTY"], rowSetup = setupRow, rowUpdate = updateRow,
		isSelected = function(d) return d.id == View.selected end,
		onRowClick = function(d) View:Select(d.id) end })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.TOOLBAR_HEIGHT)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, View.BAR_HEIGHT + 4)
end

function View.refresh(f)
	f.filter:SetItems({ { id = "open", text = L["GOAL_SHOW_OPEN"] }, { id = "closed", text = L["GOAL_SHOW_CLOSED"] } }, View.show)
	f.new:SetShown(G().CanWrite())
	local list = G():List({ closed = View.show == "closed", search = View.search })
	View.rows = list
	local selected
	for _, row in ipairs(list) do if row.id == View.selected then selected = row end end
	if not selected then View.selected, View.armed = nil, nil end
	local key = View.search ~= "" and "GOAL_NO_MATCH" or (View.show == "closed" and "GOAL_EMPTY_CLOSED")
		or (G().CanWrite() and "GOAL_EMPTY_OFFICER" or "GOAL_EMPTY")
	f.table:SetEmptyText(L[key])
	f.table:SetData(list, true)
	drawBar(f, selected)
	View.drawn = (View.drawn or 0) + 1
end

if ns.Shell then
	ns.Shell:RegisterView("goals", { label = L["VIEW_GOALS"], order = 44, dest = "economy", search = true,
		visible = function() return G() ~= nil and G().Enabled() end,
		build = function(f)
			View.build(f)
			f:SetScript("OnShow", function() View:Redraw() end)
			View.refresh(f)
		end,
		onSearch = function(text) View:SetSearch(text) end })
end

---------------------------------------------------------------------------------------------------------------------
-- The "New goal" window (also "Edit goal": only the title, the note and a later end)
---------------------------------------------------------------------------------------------------------------------
local function buildDialog()
	local w = View.WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordGoalDialog", { width = w, height = View.HEIGHT })
	local card = d.card
	d:SetTitle("")
	local function label(key, x, y)
		local fs = Widgets.Text(card, "Small", "text-2", "LEFT")
		fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
		fs:SetText(L[key])
		return fs
	end
	local function field(y, x, width, letters, placeholder)
		local e = Widgets.EditBox(card, { width = width, dense = true, maxLetters = letters, placeholder = placeholder,
			onEnter = function() View:Place() end })
		e:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
		return e
	end
	d.kind = Widgets.Segmented(card, { { id = "items", text = L["GOAL_KIND_ITEMS"] }, { id = "gold", text = L["GOAL_KIND_GOLD"] } },
		function(id) View:KindChanged(id) end)
	d.kind:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -60)
	d.itemLabel = label("ORD_COL_ITEM", 24, 108)
	d.item = field(126, 24, w - 48, 200, L["WISH_ITEM_HINT"])
	d.targetLabel = label("GOAL_TARGET", 24, 172)
	d.target = field(190, 24, 140, 7)
	d.daysLabel = label("GOAL_DAYS", 184, 172)
	d.days = field(190, 184, 96, 3)
	label("GOAL_TITLE", 24, 236)
	d.titleBox = field(254, 24, w - 48, G().TITLE_MAX, L["GOAL_TITLE_HINT"])
	label("ORD_NOTE", 24, 300)
	d.note = field(318, 24, w - 48, G().NOTE_MAX)
	d.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.status:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -368)
	d.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.status:SetWordWrap(true)
	d.ok = Widgets.Button(card, { text = L["GOAL_CREATE"], style = "filled", onClick = function() View:Place() end })
	d.cancel = Widgets.Button(card, { text = L["ORD_CLOSE"], style = "outlined", onClick = function() d:Close() end })
	d:SetActions({ d.cancel, d.ok })
	return d
end

-- Items ask for an item and a number of units, gold for gold coins.
function View:KindChanged(kind)
	local d = self.dialog
	if not d then return end
	local items = kind == "items"
	d.item:SetShown(items)
	d.itemLabel:SetShown(items)
	d.targetLabel:SetText(L[items and "GOAL_TARGET" or "GOAL_TARGET_GOLD"])
end

local function open(self, row)
	local M = G()
	if not (M and M.Enabled() and M.CanWrite()) then return nil end
	if not self.dialog then self.dialog = buildDialog() end
	local d = self.dialog
	self.editing = row and row.id or nil
	d.title:SetText(L[row and "GOAL_EDIT_TITLE" or "GOAL_NEW_TITLE"])
	local kind = row and row.kind or "items"
	d.kind:Select(kind)
	self:KindChanged(kind)
	-- an edit changes neither what is collected nor the target
	d.kind:SetShown(not row)
	d.item:SetShown(not row and kind == "items")
	d.itemLabel:SetShown(not row and kind == "items")
	d.target:SetShown(not row)
	d.targetLabel:SetShown(not row)
	d.item:SetText("")
	d.target:SetText("")
	d.days:SetText(row and tostring(row.daysLeft) or tostring(M.DAYS))
	d.titleBox:SetText(row and row.title or "")
	d.note:SetText(row and row.note or "")
	d.ok:SetLabel(L[row and "GOAL_SAVE" or "GOAL_CREATE"])
	say(d.status, L[row and "GOAL_EDIT_HINT" or "GOAL_NEW_HINT"])
	d:Open()
	return d
end

function View:OpenNew() return open(self, nil) end

function View:OpenEdit(id)
	local row = G() and G():Get(id)
	if not (row and row.canEdit) then return nil end
	return open(self, row)
end

-- Writes what the window says. Returns the record, or false and a reason.
function View:Place()
	local d = self.dialog
	if not d then return false, "off" end
	local days = tonumber(d.days:GetText()) or -1
	local kind = d.kind:Active()
	local rec, why
	if self.editing then
		rec, why = G():Edit(self.editing, { title = d.titleBox:GetText(), note = d.note:GetText(), days = days })
	else
		local item = kind == "items" and ns.Wishlist and ns.Wishlist.ParseItem(d.item:GetText()) or nil
		if kind == "items" and not item then
			why = "item"
		else
			rec, why = G():Create({ kind = kind, item = item, target = tonumber(d.target:GetText()) or -1, days = days,
				title = d.titleBox:GetText(), note = d.note:GetText() })
		end
	end
	if not rec then
		say(d.status, View.ErrorText(why, kind), "err")
		return false, why
	end
	d:Close()
	self.selected, self.show, self.error = rec.id, "open", nil
	self:Redraw()
	return rec
end

if ns.addon then
	ns.addon.GoalsView = View
	LibStub("AceEvent-3.0"):Embed(View)
	-- the names of the items arrive later
	pcall(View.RegisterEvent, View, "GET_ITEM_INFO_RECEIVED", function()
		if G() and G().Enabled() then View:Changed() end
	end)
	if ns.Bus then
		ns.Bus:On("GOALS_CHANGED", function() View:Changed() end)
		ns.Bus:On("ROSTER_UPDATED", function() View:Changed() end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.show, View.search, View.selected, View.armed, View.error, View.editing = "open", "", nil, nil, nil, nil
			if View.dialog then View.dialog:Close() end
		end)
	end
end

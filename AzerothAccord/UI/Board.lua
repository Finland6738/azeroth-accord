-- BoardView: the "Board" mode of the Market view, the "New post" window and the posts on the member card (M13.5;
-- SPEC-17 §6.3, §8; SPEC-10 Q47). Lua 5.1.
-- Chips choose what is listed (All, Selling, Buying) and whether only what the player can help with shows; "New post"
-- opens the window. A click on a row selects it: the bar under the table has every step the viewer's side may take (the
-- author also picks who the deal is with), a note, Whisper and Hide posts. Every step asks once: the second click
-- (Confirm) writes it. A line warns that Accord does not trade, until "Got it". Only with the switch "econ".
-- Nothing here changes the game (ECO-01): Whisper only opens the chat box and the player writes and sends.
--   View.StatusText(row), View.StatusToken(row), View.UntilText(row), View.TipLines(row)   plain texts, tested offline
--   View:Press(id, action, guid)    first click: "armed"; second: true, or false and a reason
--   View:OpenNew(opts)              the New post window (opts = { kind, item }); View:Place()
--   View:Open(id), View:Select(id), View:Hide(guid), View:Whisper(guid)
--   View.CardLines(guid)            the lines of a character's open posts for the "Market" section of the member card
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.BoardView, ns.modules = View, ns.modules or {}
ns.modules.BoardView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, tonumber, max = type, ipairs, pairs, tostring, tonumber, math.max
local concat = table.concat

View.ROW_HEIGHT = 36
View.TOOLBAR_HEIGHT = 40
View.WARNING_HEIGHT = 36
View.BAR_HEIGHT = 136        -- the post, a line about it, the note and who, the buttons
View.WIDTH, View.HEIGHT = 460, 500
View.ICON = 20

View.side = "all"            -- "all" | "wts" | "wtb"
View.help = false
View.selected = nil          -- the id of the selected post
View.who = nil               -- the author's choice: the character the deal is with
View.armed = nil             -- { id, action, guid }: the step clicked once

local SIDES = { "all", "wts", "wtb" }

local function B() return ns.Board end
local function now() return ns.Compat.ServerTime() end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end
local function ago(t) return ns.Provenance.AgeText(max(0, now() - (t or now()))) end
local function redraw() if ns.MarketView then ns.MarketView:Redraw() end end

local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-3")
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function View.KindText(kind) return L["BRD_KIND_" .. tostring(kind):upper()] end

function View.ItemText(row) return L["ORD_ITEM"]:format(row.count, escape(row.itemName)) end

function View.UntilText(row)
	if row.state == "closed" then return "" end
	local days = math.floor(row.left / 86400)
	if days >= 1 then return L["BRD_DAYS_LEFT"]:format(days) end
	return L["BRD_HOURS_LEFT"]:format(max(1, math.floor(row.left / 3600)))
end

local function answerOf(row, guid)
	for _, a in ipairs(row.answers) do if a.guid == guid then return a end end
	return nil
end

-- The deal as the row says it: closed, confirmed by one side, who wants it, or nothing.
function View.StatusText(row)
	if row.state == "closed" then
		return L["BRD_CLOSED"]:format(escape(row.authorName), escape(row.closedName))
	end
	if row.state ~= "open" then return L["BRD_ST_" .. row.state:upper()] end
	if row.with and answerOf(row, row.with) then
		return L["BRD_HALF"]:format(escape(row.authorName), escape(row.withName))
	end
	local wanting, confirmed = {}, nil
	for _, a in ipairs(row.answers) do
		wanting[#wanting + 1] = a
		if a.state == "done" and (not confirmed or a.guid == (row.my and row.my.guid)) then confirmed = a end
	end
	if confirmed then return L["BRD_HALF"]:format(escape(confirmed.name), escape(row.authorName)) end
	if #wanting == 1 then return L["BRD_WANTS_ONE"]:format(escape(wanting[1].name)) end
	if #wanting > 1 then return L["BRD_WANTS_N"]:format(#wanting) end
	return L["BRD_NOBODY"]
end

function View.StatusToken(row)
	if row.state == "closed" then return "ok" end
	if row.state ~= "open" then return "text-3" end
	return #row.answers > 0 and "accent-text" or "text-3"
end

function View.TipLines(row)
	local out = { View.KindText(row.kind) .. " · " .. View.ItemText(row) }
	out[#out + 1] = { text = L["BRD_TIP_BY"]:format(escape(row.authorName), ago(row.posted)), token = "text-2" }
	if row.price then out[#out + 1] = { text = L["BRD_TIP_PRICE"]:format(escape(row.price)), token = "text-2" } end
	if row.note then out[#out + 1] = { text = L["ORD_NOTE_OF"]:format(escape(row.authorName), escape(row.note)) } end
	for _, a in ipairs(row.answers) do
		out[#out + 1] = { text = L[a.state == "done" and "BRD_TIP_CONFIRMED" or "BRD_WANTS_ONE"]:format(escape(a.name)),
			token = "text-3" }
		if a.note then out[#out + 1] = { text = L["ORD_NOTE_OF"]:format(escape(a.name), escape(a.note)) } end
	end
	out[#out + 1] = { text = View.StatusText(row), token = View.StatusToken(row) }
	return out
end

local ERRORS = { off = "BRD_ERR_OTHER", guild = "NOT_IN_GUILD", item = "WISH_ERR_ITEM", count = "ORD_ERR_COUNT",
	price = "ORD_ERR_PRICE", note = "ORD_ERR_NOTE", days = "WISH_ERR_DAYS", limit = "BRD_ERR_LIMIT", rate = "ORD_ERR_RATE",
	missing = "BRD_ERR_MISSING", state = "BRD_ERR_STATE" }

function View.ErrorText(why)
	local M = B()
	if why == "count" then return L[ERRORS[why]]:format(M.QTY_MAX) end
	if why == "price" then return L[ERRORS[why]]:format(M.PRICE_MAX) end
	if why == "note" then return L[ERRORS[why]]:format(M.NOTE_MAX) end
	if why == "days" then return L[ERRORS[why]]:format(M.DAYS_MAX) end
	if why == "limit" then return L[ERRORS[why]]:format(M.MAX_OPEN) end
	return L[ERRORS[why] or "BRD_ERR_OTHER"]
end

-- The label of a step's button; `name` is the other side.
function View.ActionText(row, action, name)
	if action == "confirm" then
		if name then return L["BRD_DO_CONFIRM_WITH"]:format(escape(name)) end
		return L["BRD_DO_CONFIRM"]
	end
	return L["BRD_DO_" .. action:upper()]
end

---------------------------------------------------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------------------------------------------------
function View:IsArmed(id, action, guid)
	local a = self.armed
	return a ~= nil and a.id == id and a.action == action and (guid == nil or a.guid == guid)
end

function View:Select(id)
	if self.selected ~= id then
		self.selected = id
		self.armed, self.error, self.who = nil, nil, nil
		if self.frame then self.frame.note:SetText("") end
	end
	redraw()
end

-- The first click on a step asks (the button says Confirm), the second one does it. "hide" hides the author's posts.
function View:Press(id, action, guid)
	if not self:IsArmed(id, action, guid) then
		self:Select(id)
		self.armed, self.error = { id = id, action = action, guid = guid }, nil
		redraw()
		return "armed"
	end
	self.armed = nil
	if action == "hide" then return self:Hide(guid) end
	local note = self.frame and self.selected == id and self.frame.note:GetText() or nil
	local rec, why = B():Act(id, action, guid, note)
	if not rec then
		self.error = View.ErrorText(why)
		redraw()
		return false, why
	end
	self.error = nil
	if self.frame then self.frame.note:SetText("") end
	redraw()
	return true
end

function View:Hide(guid)
	local ok = B():Hide(guid)
	if ok then
		self.selected, self.armed, self.error = nil, nil, nil
		if ns.addon then ns.addon:Print(L["BRD_HIDDEN"]:format(escape(B().NameOf(guid)))) end
	end
	redraw()
	return ok
end

function View:Whisper(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	local name = e and (e.name or e.short)
	return name ~= nil and ns.Compat.Chat.OpenWhisper(name, "") or false
end

function View:Open(id)
	if not (B() and B().Enabled() and ns.MarketView) then return false end
	local row = id and B():Get(id)
	if row then
		if self.side ~= "all" and self.side ~= row.kind then self.side = "all" end
		self.help = false
		self.selected, self.armed, self.error, self.who = row.id, nil, nil, nil
		ns.MarketView.search = ""
	end
	local shown = ns.MarketView:Open("board")
	redraw()
	return shown
end

---------------------------------------------------------------------------------------------------------------------
-- The mode of the Market view
---------------------------------------------------------------------------------------------------------------------
local function pos(i) return View.frame.table.pos and View.frame.table.pos[i] end

local function renderKind(cell) cell:SetText("") end

local function renderItem(cell, row, frame)
	cell:SetText(View.ItemText(row))
	Theme.Text(cell, View.selected == row.id and "on-secondary-container" or (row.state == "open" and "text-1" or "text-3"))
	local p = pos(2)
	if p then
		cell:ClearAllPoints()
		cell:SetWidth(max(p.w - View.ICON - 16, 1))
		cell:SetPoint("LEFT", frame, "LEFT", p.x + View.ICON + 8, 0)
	end
end

local function columns()
	local function col(id, key, opts)
		opts.id, opts.title, opts.sortable = id, key and L[key] or "", false
		return opts
	end
	return {
		col("kind", "BRD_COL_KIND", { width = 56, render = renderKind }),
		col("item", "ORD_COL_ITEM", { flex = 2, render = renderItem }),
		col("price", "ORD_COL_PRICE", { width = 96, mono = true, text = function(r) return escape(r.price or "") end }),
		col("author", "BRD_COL_AUTHOR", { flex = 1, text = function(r) return escape(r.authorName) end,
			token = function(r) return r.online and "text-1" or "text-3" end }),
		col("until", "WISH_COL_UNTIL", { width = 80, text = View.UntilText }),
		col("status", "BRD_COL_STATUS", { flex = 2, text = View.StatusText, token = View.StatusToken }),
		col("action", nil, { width = 112, render = function(cell) cell:SetText("") end }),
	}
end

-- The step a row's own button carries: the viewer's next one on somebody else's post ("Deal", "Deal done").
local function rowStep(d)
	if d.mine then return nil end
	local first = d.actions[1]
	if first and (first.action == "deal" or first.action == "confirm") then return first end
	return nil
end

local function setupRow(row)
	row.badge = Widgets.Badge(row, "WTS", "accent")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(View.ICON, View.ICON)
	row.step = Widgets.Button(row, { text = L["ORD_CONFIRM"], style = "tonal", width = 104, height = Widgets.HEIGHT.small,
		onClick = function(b)
			local d = b:GetParent().data
			if d and b.step then View:Press(d.id, b.step.action, b.step.guid) end
		end })
	row.step:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	row.step:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.step:Hide()
	row:HookScript("OnEnter", function(self)
		if self.data then Widgets.Tooltip.Show(self, View.TipLines(self.data), "BOTTOM") end
	end)
	row:HookScript("OnLeave", function() Widgets.Tooltip.Hide() end)
end

local function updateRow(row, d)
	local k, i = pos(1), pos(2)
	row.badge:SetBadge(View.KindText(d.kind), d.state == "open" and "accent" or "neutral")
	row.badge:ClearAllPoints()
	row.badge:SetPoint("LEFT", row, "LEFT", k and k.x or 8, 0)
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", i and i.x or 72, 0)
	local icon = ns.Compat.Item.Icon(d.item)
	if icon then row.icon:SetTexture(icon) row.icon:Show() else row.icon:Hide() end
	local step = rowStep(d)
	row.step.step = step
	if step then
		row.step:SetLabel(View:IsArmed(d.id, step.action, step.guid) and L["ORD_CONFIRM"] or View.ActionText(d, step.action))
		row.step:Show()
	else
		row.step:Hide()
	end
end

local function buildBar(f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(View.BAR_HEIGHT)
	bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	bar.line = Widgets.Divider(bar, "BORDER")
	bar.line:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
	bar.info = Widgets.Text(bar, "Body", "text-1", "LEFT")
	bar.info:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -10)
	bar.info:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar.info:SetWordWrap(false)
	bar.detail = Widgets.Text(bar, "Small", "text-3", "LEFT")
	bar.detail:SetPoint("TOPLEFT", bar.info, "BOTTOMLEFT", 0, -6)
	bar.detail:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar.detail:SetWordWrap(false)
	f.note = Widgets.EditBox(bar, { width = 360, dense = true, maxLetters = B().NOTE_MAX, placeholder = L["ORD_NOTE_HINT"] })
	f.note:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 48)
	-- the author's choice among who answered
	bar.who = Widgets.Select(bar, { width = 200, rows = 6, placeholder = L["BRD_WHO"],
		onSelect = function(id)
			View.who, View.armed, View.error = id, nil, nil
			redraw()
		end })
	bar.who:SetPoint("LEFT", f.note, "RIGHT", 8, 0)
	bar.whisper = Widgets.Button(bar, { text = L["NEW_WHISPER"], style = "text", dense = true, onClick = function()
		local row = View.selected and B():Get(View.selected)
		if not row then return end
		View:Whisper(row.mine and View.who or row.author)
	end })
	bar.hide = Widgets.Button(bar, { text = L["BRD_HIDE"], style = "text", dense = true, onClick = function()
		local row = View.selected and B():Get(View.selected)
		if row then View:Press(row.id, "hide", row.author) end
	end })
	bar.buttons = {}
	f.foot = bar
end

local function barButton(bar, action)
	local b = bar.buttons[action]
	if b then return b end
	local quiet = action == "withdraw" or action == "drop" or action == "unconfirm"
	b = Widgets.Button(bar, { text = L["ORD_CONFIRM"], style = quiet and "outlined" or "tonal", dense = true,
		onClick = function(self) if View.selected then View:Press(View.selected, action, self.guid) end end })
	bar.buttons[action] = b
	return b
end

-- The author's answers as choices; the one held, else the one confirmed with, else the first.
local function chooseWho(row)
	local choices, keep = {}, nil
	for _, a in ipairs(row.answers) do
		choices[#choices + 1] = { id = a.guid, text = escape(a.name) }
		if a.guid == View.who then keep = a.guid end
	end
	View.who = keep or (row.with and answerOf(row, row.with) and row.with) or (choices[1] and choices[1].id) or nil
	return choices
end

local function drawBar(f, row)
	local bar = f.foot
	for _, b in pairs(bar.buttons) do b:Hide() end
	if not row then
		say(bar.info, L["BRD_PICK"], "text-3")
		say(bar.detail, View.error or "", "err")
		f.note:Hide()
		bar.who:Hide()
		bar.whisper:Hide()
		bar.hide:Hide()
		return
	end
	say(bar.info, L["BRD_BAR_INFO"]:format(View.KindText(row.kind), View.ItemText(row), escape(row.authorName),
		View.StatusText(row)), "text-1")
	local choices = row.mine and row.state == "open" and chooseWho(row) or {}
	bar.who:SetShown(#choices > 0)
	if #choices > 0 then
		bar.who:SetChoices(choices)
		bar.who:Select(View.who, true)
	end
	-- the steps offered: of the author's, those about the chosen character
	local steps = {}
	for _, a in ipairs(row.actions) do
		local mineStep = row.mine and (a.action == "confirm" and a.guid == View.who
			or a.action == "unconfirm" or a.action == "withdraw")
		if not row.mine or mineStep then steps[#steps + 1] = a end
	end
	local armed = View.armed and View.armed.id == row.id and View.armed
	local notes = {}
	if row.note then notes[#notes + 1] = L["ORD_NOTE_OF"]:format(escape(row.authorName), escape(row.note)) end
	for _, a in ipairs(row.answers) do
		if a.note then notes[#notes + 1] = L["ORD_NOTE_OF"]:format(escape(a.name), escape(a.note)) end
	end
	if View.error then say(bar.detail, View.error, "err")
	elseif armed then say(bar.detail, L["BRD_ASK_" .. armed.action:upper()]:format(escape(B().NameOf(armed.guid))), "warn")
	else say(bar.detail, concat(notes, " · "), "text-3") end
	f.note:SetShown(#steps > 0)
	local last = nil
	for _, step in ipairs(steps) do
		local b = barButton(bar, step.action)
		b.guid = step.guid
		local name = row.mine and step.guid and B().NameOf(step.guid) or nil
		b:SetLabel(View:IsArmed(row.id, step.action, step.guid) and L["ORD_CONFIRM"]
			or View.ActionText(row, step.action, name))
		b:ClearAllPoints()
		if last then b:SetPoint("LEFT", last, "RIGHT", 8, 0)
		else b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 4) end
		b:Show()
		last = b
	end
	local other = not row.mine or View.who ~= nil
	bar.whisper:SetShown(other)
	bar.whisper:ClearAllPoints()
	bar.whisper:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 4)
	bar.hide:SetShown(not row.mine)
	bar.hide:SetLabel(View:IsArmed(row.id, "hide", row.author) and L["ORD_CONFIRM"] or L["BRD_HIDE"])
	bar.hide:ClearAllPoints()
	bar.hide:SetPoint("RIGHT", bar.whisper, "LEFT", -8, 0)
end

local mode = {}

function mode.build(f)
	View.frame = f
	f.filter = Widgets.ChipRow(f, function(id)
		View.side = id
		View.armed, View.error = nil, nil
		if f.table then f.table.offset = 0 end
		redraw()
	end)
	f.filter:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.filter:SetWidth(300)
	f.new = Widgets.Button(f, { text = L["BRD_NEW"], style = "tonal", dense = true, onClick = function() View:OpenNew() end })
	f.new:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.help = Widgets.Chip(f, { text = L["BRD_HELP"], onClick = function()
		View.help = not View.help
		redraw()
	end })
	f.help:SetPoint("TOPRIGHT", f.new, "TOPLEFT", -8, 0)
	f.warning = CreateFrame("Frame", nil, f)
	f.warning:SetHeight(View.WARNING_HEIGHT)
	f.warning:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.TOOLBAR_HEIGHT)
	f.warning:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -View.TOOLBAR_HEIGHT)
	f.warning.ok = Widgets.Button(f.warning, { text = L["BRD_GOT_IT"], style = "text", height = Widgets.HEIGHT.small,
		onClick = function() B():SetWarned() redraw() end })
	f.warning.ok:SetPoint("RIGHT", f.warning, "RIGHT", -4, 0)
	f.warning.text = Widgets.Text(f.warning, "Small", "warn", "LEFT")
	f.warning.text:SetPoint("LEFT", f.warning, "LEFT", 4, 0)
	f.warning.text:SetPoint("RIGHT", f.warning.ok, "LEFT", -8, 0)
	f.warning.text:SetText(L["BRD_WARNING"])
	buildBar(f)
	f.table = Widgets.DataTable(f, columns(), { rowHeight = View.ROW_HEIGHT, pool = 20, maxPool = 60,
		emptyText = L["BRD_EMPTY"], rowSetup = setupRow, rowUpdate = updateRow,
		isSelected = function(d) return d.id == View.selected end,
		onRowClick = function(d) View:Select(d.id) end })
end

function mode.refresh(f)
	local chips = {}
	for i, id in ipairs(SIDES) do chips[i] = { id = id, text = L["BRD_SIDE_" .. id:upper()] } end
	f.filter:SetItems(chips, View.side)
	f.help:SetSelected(View.help)
	local warn = not B():Warned()
	f.warning:SetShown(warn)
	local top = View.TOOLBAR_HEIGHT + (warn and View.WARNING_HEIGHT or 0)
	f.table:ClearAllPoints()
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, View.BAR_HEIGHT + 4)
	local search = ns.MarketView and ns.MarketView.search
	local list = B():List({ side = View.side, help = View.help, search = search })
	View.rows = list
	local selected = nil
	for _, row in ipairs(list) do if row.id == View.selected then selected = row end end
	if not selected then View.selected, View.armed, View.who = nil, nil, nil end
	local filtered = (search and search ~= "") or View.help or View.side ~= "all"
	f.table:SetEmptyText(L[filtered and "BRD_NO_MATCH" or "BRD_EMPTY"])
	f.table:SetData(list, true)
	drawBar(f, selected)
end

if ns.MarketView then
	ns.MarketView.AddMode("board", { label = L["MARKET_MODE_BOARD"], order = 40, build = mode.build, refresh = mode.refresh,
		available = function() return B() ~= nil and B().Enabled() end })
end

---------------------------------------------------------------------------------------------------------------------
-- The "New post" window
---------------------------------------------------------------------------------------------------------------------
local function buildNew()
	local w = View.WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordBoardDialog", { width = w, height = View.HEIGHT })
	local card = d.card
	d:SetTitle("")
	d.title:SetText(L["BRD_NEW_TITLE"])
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
	local items = {}
	for i, id in ipairs(B().KINDS) do items[i] = { id = id, text = L["BRD_SIDE_" .. id:upper()] } end
	d.kind = Widgets.Segmented(card, items)
	d.kind:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -60)
	label("ORD_COL_ITEM", 24, 108)
	d.item = field(126, 24, w - 48, 200, L["WISH_ITEM_HINT"])
	label("ORD_COUNT", 24, 172)
	d.count = field(190, 24, 96, 4)
	label("BRD_DAYS", 140, 172)
	d.days = field(190, 140, 96, 1, L["WISH_DAYS_HINT"]:format(B().DAYS))
	label("ORD_PRICE", 24, 236)
	d.price = field(254, 24, w - 48, B().PRICE_MAX, L["ORD_PRICE_HINT"])
	label("ORD_NOTE", 24, 300)
	d.note = field(318, 24, w - 48, B().NOTE_MAX)
	d.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.status:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -368)
	d.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.status:SetWordWrap(true)
	d.ok = Widgets.Button(card, { text = L["BRD_POST"], style = "filled", onClick = function() View:Place() end })
	d.cancel = Widgets.Button(card, { text = L["ORD_CLOSE"], style = "outlined", onClick = function() d:Close() end })
	d:SetActions({ d.cancel, d.ok })
	return d
end

function View:OpenNew(opts)
	local M = B()
	if not (M and M.Enabled()) then return nil end
	if not self.dialog then self.dialog = buildNew() end
	local d = self.dialog
	opts = opts or {}
	d.kind:Select(opts.kind or (View.side == "wtb" and "wtb") or "wts")
	d.item:SetText(opts.item and tostring(opts.item) or "")
	d.count:SetText("1")
	d.days:SetText("")
	d.price:SetText("")
	d.note:SetText("")
	say(d.status, L["BRD_NEW_HINT"])
	d:Open()
	return d
end

-- Writes the post of the window. Returns the record, or false and a reason.
function View:Place()
	local d = self.dialog
	if not d then return false, "off" end
	local item = ns.Wishlist and ns.Wishlist.ParseItem(d.item:GetText())
	local days = d.days:GetText()
	local rec, why
	if not item then why = "item"
	else
		rec, why = B():Post({ kind = d.kind:Active(), item = item, count = tonumber(d.count:GetText()) or -1,
			days = days ~= "" and (tonumber(days) or -1) or nil, price = d.price:GetText(), note = d.note:GetText() })
	end
	if not rec then
		say(d.status, View.ErrorText(why), "err")
		return false, why
	end
	d:Close()
	if ns.addon then ns.addon:Print(L["BRD_POSTED"]) end
	redraw()
	return rec
end

---------------------------------------------------------------------------------------------------------------------
-- The member card
---------------------------------------------------------------------------------------------------------------------
function View.CardLines(guid)
	local out = {}
	if not (B() and B().Enabled()) then return out end
	for _, row in ipairs(B():OfMember(guid)) do
		local id = row.id
		out[#out + 1] = { text = L["BRD_CARD_LINE"]:format(View.KindText(row.kind), View.ItemText(row), View.UntilText(row)),
			action = true, onClick = function() View:Open(id) end }
	end
	return out
end

if ns.addon then
	ns.addon.BoardView = View
	if ns.Bus then
		ns.Bus:On("BOARD_CHANGED", function()
			if not (B() and B().Enabled()) then return end
			if ns.MemberCard then ns.MemberCard:Refresh() end
			if ns.MarketView then ns.MarketView:Changed() end
		end)
		ns.Bus:On("INVENTORY_CHANGED", function()
			if View.help and ns.MarketView and ns.MarketView.mode == "board" then ns.MarketView:Changed() end
		end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.side, View.help, View.selected, View.armed, View.error, View.who = "all", false, nil, nil, nil, nil
			if View.dialog then View.dialog:Close() end
		end)
	end
end

-- OrdersView: the "Orders" mode of the Market view, the "New order" window and the "Market" section of the member card
-- (M13.2; SPEC-17 §3.5, §3.8, §8; SPEC-06 PRO-05). Lua 5.1.
-- Chips choose whose orders are listed (For me, Mine, Everyone) and whether the closed ones show too. A row carries the
-- next step of the viewer's side; a click on a row selects it and the bar under the table has every step it may take, a
-- note, and Whisper. Every step asks once: the second click (Confirm) writes it. The craft requests of M3 not yet turned
-- into orders are listed above the table, with "Make it an order" and "Dismiss". Only with the switch "econ".
-- Nothing here changes the game (ECO-01): no trade, no mail, no crafting order of the game; Whisper only opens the chat
-- box and the player writes and sends.
--   View.StateText(row), View.StateToken(row), View.WaitingText(row), View.StepText(row)   plain texts, tested offline
--   View:Open(id)                         the Market view on Orders, on that order
--   View:Press(id, action)                first click: "armed"; second: true, or false and a reason
--   View:OpenNew(crafter, recipe, opts)   the New order window (opts = { from = an earlier request }); View:Place()
--   View:Whisper(guid)
--   View.CardSection(entry)               "Market" on the member card: the open orders and the wishes of that character
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.OrdersView, ns.modules = View, ns.modules or {}
ns.modules.OrdersView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring, tonumber, max = type, ipairs, tostring, tonumber, math.max

View.ROW_HEIGHT = 36
View.FILTER_HEIGHT = 40
View.EARLIER = 3             -- earlier requests listed at once
View.EARLIER_ROW = 36
View.BAR_HEIGHT = 136        -- the order, a line about it, the note, the buttons
View.WIDTH, View.HEIGHT = 460, 560
View.ICON = 20

View.who = "all"             -- "forme" | "mine" | "all"
View.closed = false
View.selected = nil          -- the id of the selected order
View.armed = nil             -- { id, action }: the step clicked once

local WHO = { "forme", "mine", "all" }
local TOKEN = { requested = "accent-text", accepted = "text-2", progress = "text-2", ready = "ok", delivered = "ok",
	cancelled = "text-3" }
local QUIET = { cancel = true, decline = true }

local function O() return ns.Orders end
local function now() return ns.Compat.ServerTime() end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end
local function ago(t) return ns.Provenance.AgeText(max(0, now() - (t or now()))) end

local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-3")
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
-- Who has not confirmed a delivery confirmed by one side, as the state column says it; nil otherwise.
local function missingName(row)
	if row.missing == "buyer" then return not row.mine and escape(row.buyerName) or nil, row.mine end
	if row.missing == "crafter" then return not row.forMe and escape(row.crafterName) or nil, row.forMe end
	return nil, false
end

function View.StateText(row)
	if row.state == "cancelled" and row.why and row.why ~= "cancelled" then return L["ORD_ST_" .. row.why:upper()] end
	if row.state == "ready" and row.missing then
		local name, you = missingName(row)
		return you and L["ORD_ST_WAIT_YOU"] or L["ORD_ST_WAIT"]:format(name)
	end
	return L["ORD_ST_" .. row.state:upper()]
end

function View.StateToken(row) return TOKEN[row.state] or "text-2" end

-- A delivery confirmed by one side, in a sentence (SPEC-17 §3.2); nil otherwise.
function View.WaitingText(row)
	if row.state ~= "ready" or not row.missing then return nil end
	local done = row.missing == "buyer" and row.crafterName or row.buyerName
	local name, you = missingName(row)
	if you then return L["ORD_WAITING_YOU"]:format(escape(done)) end
	return L["ORD_WAITING"]:format(escape(done), name)
end

function View.MatsText(mats) return L["ORD_MATS_" .. tostring(mats):upper()] end

function View.ItemText(row) return L["ORD_ITEM"]:format(row.count, escape(row.recipeName)) end

-- The last step of the crafter, in words: "Bob accepted it, 2 d ago".
function View.StepText(row)
	local a = row.part
	if not a then return nil end
	return L["ORD_STEP_" .. a.state:upper()]:format(escape(row.crafterName), ago(a.at))
end

-- "Materials: 4 × Copper Bar, 2 × Linen Cloth" for `count` of a recipe, or nil while the game has not given them.
function View.MaterialsText(recipe, count)
	local mats = ns.Reagents and ns.Reagents:Ensure(recipe)
	if not (mats and ns.Wishlist) then return nil end
	local out = {}
	for i, slot in ipairs(mats.r) do
		out[i] = L["ORD_ITEM"]:format(slot[2] * count, escape(ns.Wishlist.ItemName(slot[1])))
	end
	return L["ORD_MATERIALS"]:format(table.concat(out, ", "))
end

-- The lines of a row's tooltip: both notes, the steps with their times, and who is missing.
function View.TipLines(row)
	local out = { View.ItemText(row) }
	out[#out + 1] = { text = L["ORD_PARTIES"]:format(escape(row.buyerName), escape(row.crafterName)), token = "text-2" }
	out[#out + 1] = { text = L["ORD_STEP_ORDERED"]:format(escape(row.buyerName), ago(row.created)), token = "text-3" }
	local step = View.StepText(row)
	if step then out[#out + 1] = { text = step, token = "text-3" } end
	local rec = row.rec
	if rec.state ~= "open" then
		out[#out + 1] = { text = L[rec.state == "received" and "ORD_STEP_RECEIVED" or "ORD_STEP_CANCELLED"]:format(
			escape(row.buyerName), ago(rec.closed)), token = "text-3" }
	end
	if rec.by then out[#out + 1] = { text = L["ORD_NEEDED_BY"]:format(O().DayText(rec.by)), token = "text-3" } end
	local mats = View.MaterialsText(row.recipe, row.count)
	if mats then out[#out + 1] = { text = mats, token = "text-2" } end
	if rec.note then out[#out + 1] = { text = L["ORD_NOTE_OF"]:format(escape(row.buyerName), escape(rec.note)) } end
	if row.part and row.part.note then
		out[#out + 1] = { text = L["ORD_NOTE_OF"]:format(escape(row.crafterName), escape(row.part.note)) }
	end
	local waiting = View.WaitingText(row)
	if waiting then out[#out + 1] = { text = waiting, token = "warn" } end
	return out
end

local ERRORS = { off = "ORD_ERR_OTHER", guild = "NOT_IN_GUILD", crafter = "ORD_ERR_CRAFTER", own = "ORD_ERR_OWN",
	count = "ORD_ERR_COUNT", price = "ORD_ERR_PRICE", note = "ORD_ERR_NOTE", by = "ORD_ERR_BY", limit = "ORD_ERR_LIMIT",
	rate = "ORD_ERR_RATE", missing = "ORD_ERR_MISSING", state = "ORD_ERR_STATE", owner = "ORD_ERR_STATE" }

function View.ErrorText(why)
	local M = O()
	if why == "count" then return L[ERRORS[why]]:format(M.MAX_COUNT) end
	if why == "price" then return L[ERRORS[why]]:format(M.PRICE_MAX) end
	if why == "note" then return L[ERRORS[why]]:format(M.NOTE_MAX) end
	if why == "by" then return L[ERRORS[why]]:format(M.BY_MAX) end
	if why == "limit" then return L[ERRORS[why]]:format(M.MAX_OPEN) end
	return L[ERRORS[why] or "ORD_ERR_OTHER"]
end

---------------------------------------------------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------------------------------------------------
local function redraw() if ns.MarketView then ns.MarketView:Redraw() end end

function View:IsArmed(id, action)
	local a = self.armed
	return a ~= nil and a.id == id and a.action == action
end

function View:Select(id)
	if self.selected ~= id then
		self.selected = id
		self.armed, self.error = nil, nil
		if self.frame then self.frame.note:SetText("") end
	end
	redraw()
end

-- The first click on a step asks (the button says Confirm), the second one writes it.
function View:Press(id, action)
	if not self:IsArmed(id, action) then
		self:Select(id)
		self.armed, self.error = { id = id, action = action }, nil
		redraw()
		return "armed"
	end
	self.armed = nil
	local note = self.frame and self.selected == id and self.frame.note:GetText() or nil
	local rec, why = O():Act(id, action, note)
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

function View:Whisper(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	local name = e and (e.name or e.short)
	return name ~= nil and ns.Compat.Chat.OpenWhisper(name, "") or false
end

-- The other side of an order, for Whisper: the crafter for the buyer and the buyer for the rest; the crafter for others.
local function otherSide(row)
	if row.forMe then return row.buyer end
	return row.crafter
end

function View:Open(id)
	if not (O() and O().Enabled() and ns.MarketView) then return false end
	local row = id and O():Get(id)
	if row then
		if (self.who == "forme" and not row.forMe) or (self.who == "mine" and not row.mine) then self.who = "all" end
		if not row.open then self.closed = true end
		self.selected, self.armed, self.error = row.id, nil, nil
		ns.MarketView.search = ""
	end
	local shown = ns.MarketView:Open("orders")
	redraw()
	return shown
end

---------------------------------------------------------------------------------------------------------------------
-- The mode of the Market view
---------------------------------------------------------------------------------------------------------------------
local function renderItem(cell, row, frame)
	cell:SetText(L["ORD_ITEM"]:format(row.count, escape(row.recipeName)))
	Theme.Text(cell, View.selected == row.id and "on-secondary-container" or (row.open and "text-1" or "text-3"))
	local pos = View.frame.table.pos and View.frame.table.pos[1]
	if pos then
		cell:ClearAllPoints()
		cell:SetWidth(max(pos.w - View.ICON - 16, 1))
		cell:SetPoint("LEFT", frame, "LEFT", pos.x + View.ICON + 8, 0)
	end
end

local function columns()
	local function col(id, key, opts)
		opts.id, opts.title, opts.sortable = id, key and L[key] or "", false
		return opts
	end
	return {
		col("item", "ORD_COL_ITEM", { flex = 2, render = renderItem }),
		col("buyer", "ORD_COL_BUYER", { flex = 1, text = function(r) return escape(r.buyerName) end }),
		col("crafter", "ORD_COL_CRAFTER", { flex = 1, text = function(r) return escape(r.crafterName) end }),
		col("state", "ORD_COL_STATE", { flex = 1.2, text = View.StateText, token = View.StateToken }),
		col("mats", "ORD_COL_MATS", { width = 80, text = function(r) return View.MatsText(r.mats) end }),
		col("price", "ORD_COL_PRICE", { width = 80, mono = true, text = function(r) return escape(r.price or "") end }),
		col("age", "ORD_COL_AGE", { width = 64, text = function(r) return ago(r.created) end }),
		col("action", nil, { width = 112, render = function(cell) cell:SetText("") end }),
	}
end

local function setupRow(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(View.ICON, View.ICON)
	row.step = Widgets.Button(row, { text = L["ORD_CONFIRM"], style = "tonal", width = 104, height = Widgets.HEIGHT.small,
		onClick = function(b)
			local d = b:GetParent().data
			if d and b.action then View:Press(d.id, b.action) end
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
	local info = ns.Recipes and ns.Recipes.SpellData(d.recipe)
	local pos = View.frame.table.pos and View.frame.table.pos[1]
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", pos and pos.x or 8, 0)
	if info and info.icon then row.icon:SetTexture(info.icon) row.icon:Show() else row.icon:Hide() end
	local action = d.actions[1]
	if action and not QUIET[action] then
		row.step.action = action
		row.step:SetLabel(L[View:IsArmed(d.id, action) and "ORD_CONFIRM" or ("ORD_DO_" .. action:upper())])
		row.step:Show()
	else
		row.step.action = nil
		row.step:Hide()
	end
end

local function earlierLine(f, i)
	local line = f.earlier.lines[i]
	if line then return line end
	line = CreateFrame("Frame", nil, f.earlier)
	line:SetHeight(View.EARLIER_ROW)
	line:SetPoint("TOPLEFT", f.earlier, "TOPLEFT", 0, -20 - (i - 1) * View.EARLIER_ROW)
	line:SetPoint("TOPRIGHT", f.earlier, "TOPRIGHT", 0, -20 - (i - 1) * View.EARLIER_ROW)
	line.dismiss = Widgets.Button(line, { text = L["ORD_DISMISS"], style = "text", height = Widgets.HEIGHT.small,
		onClick = function(b) O():Dismiss(b:GetParent().ask) redraw() end })
	line.dismiss:SetPoint("RIGHT", line, "RIGHT", -4, 0)
	line.make = Widgets.Button(line, { text = L["ORD_MAKE"], style = "tonal", height = Widgets.HEIGHT.small,
		onClick = function(b)
			local ask = b:GetParent().ask
			View:OpenNew(ask.guid, ask.recipeId, { from = ask })
		end })
	line.make:SetPoint("RIGHT", line.dismiss, "LEFT", -8, 0)
	line.text = Widgets.Text(line, "Body", "text-2", "LEFT")
	line.text:SetPoint("LEFT", line, "LEFT", 4, 0)
	line.text:SetPoint("RIGHT", line.make, "LEFT", -8, 0)
	line.text:SetWordWrap(false)
	f.earlier.lines[i] = line
	return line
end

-- The earlier requests; returns the height they take.
local function drawEarlier(f)
	local asks = O():Earlier()
	View.asks = asks
	local shown = math.min(#asks, View.EARLIER)
	for i = 1, shown do
		local ask, line = asks[i], earlierLine(f, i)
		line.ask = ask
		line.text:SetText(L["ORD_EARLIER_LINE"]:format(escape(ask.recipeName), escape(ask.name), ago(ask.at)))
		line:Show()
	end
	for i = shown + 1, #f.earlier.lines do f.earlier.lines[i]:Hide() end
	if shown == 0 then
		f.earlier:Hide()
		return 0
	end
	local more = #asks - shown
	f.earlier.title:SetText(more > 0 and L["ORD_EARLIER_MORE"]:format(more) or L["ORD_EARLIER"])
	local h = 20 + shown * View.EARLIER_ROW + 8
	f.earlier:SetHeight(h)
	f.earlier:Show()
	return h
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
	f.note = Widgets.EditBox(bar, { width = 360, dense = true, maxLetters = 80, placeholder = L["ORD_NOTE_HINT"] })
	f.note:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 48)
	bar.whisper = Widgets.Button(bar, { text = L["NEW_WHISPER"], style = "text", dense = true, onClick = function()
		local row = View.selected and O():Get(View.selected)
		if row then View:Whisper(otherSide(row)) end
	end })
	bar.buttons = {}
	f.foot = bar
end

local function barButton(bar, i, quiet)
	local key = i .. (quiet and "q" or "t")
	local b = bar.buttons[key]
	if b then return b end
	b = Widgets.Button(bar, { text = L["ORD_CONFIRM"], style = quiet and "outlined" or "tonal", dense = true,
		onClick = function(self) if View.selected and self.action then View:Press(View.selected, self.action) end end })
	bar.buttons[key] = b
	return b
end

local function drawBar(f, row)
	local bar = f.foot
	for _, b in pairs(bar.buttons) do b:Hide() end
	if not row then
		say(bar.info, L["ORD_PICK"], "text-3")
		say(bar.detail, View.error or "", "err")
		f.note:Hide()
		bar.whisper:Hide()
		return
	end
	say(bar.info, L["ORD_BAR_INFO"]:format(View.ItemText(row), escape(row.buyerName), escape(row.crafterName),
		View.StateText(row)), "text-1")
	local armed = View.armed and View.armed.id == row.id
	local notes = {}
	if row.rec.note then notes[#notes + 1] = L["ORD_NOTE_OF"]:format(escape(row.buyerName), escape(row.rec.note)) end
	if row.part and row.part.note then
		notes[#notes + 1] = L["ORD_NOTE_OF"]:format(escape(row.crafterName), escape(row.part.note))
	end
	local waiting = View.WaitingText(row)
	if View.error then say(bar.detail, View.error, "err")
	elseif armed then say(bar.detail, L["ORD_ASK_" .. View.armed.action:upper()], "warn")
	elseif waiting then say(bar.detail, waiting, "warn")
	else say(bar.detail, #notes > 0 and table.concat(notes, " · ") or View.StepText(row) or "", "text-3") end
	f.note:SetShown(#row.actions > 0)
	-- the steps from the left, under the note; Whisper at the right
	local last = nil
	for i, action in ipairs(row.actions) do
		local b = barButton(bar, i, QUIET[action])
		b.action = action
		b:SetLabel(L[View:IsArmed(row.id, action) and "ORD_CONFIRM" or ("ORD_DO_" .. action:upper())])
		b:ClearAllPoints()
		if last then b:SetPoint("LEFT", last, "RIGHT", 8, 0)
		else b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 4) end
		b:Show()
		last = b
	end
	bar.whisper:Show()
	bar.whisper:ClearAllPoints()
	bar.whisper:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 4)
end

local mode = {}

function mode.build(f)
	View.frame = f
	f.filter = Widgets.ChipRow(f, function(id)
		View.who = id
		View.armed, View.error = nil, nil
		if f.table then f.table.offset = 0 end
		redraw()
	end)
	f.filter:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.filter:SetWidth(300)
	f.closed = Widgets.Chip(f, { text = L["ORD_SHOW_CLOSED"], onClick = function()
		View.closed = not View.closed
		redraw()
	end })
	f.closed:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.earlier = CreateFrame("Frame", nil, f)
	f.earlier:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.FILTER_HEIGHT)
	f.earlier:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -View.FILTER_HEIGHT)
	f.earlier.title = Widgets.Text(f.earlier, "Small", "text-2", "LEFT")
	f.earlier.title:SetPoint("TOPLEFT", f.earlier, "TOPLEFT", 4, -2)
	f.earlier.lines = {}
	f.earlier:Hide()
	buildBar(f)
	f.table = Widgets.DataTable(f, columns(), { rowHeight = View.ROW_HEIGHT, pool = 20, maxPool = 60,
		emptyText = L["ORD_EMPTY"], rowSetup = setupRow, rowUpdate = updateRow,
		isSelected = function(d) return d.id == View.selected end,
		onRowClick = function(d) View:Select(d.id) end })
end

function mode.refresh(f)
	local chips = {}
	for i, id in ipairs(WHO) do chips[i] = { id = id, text = L["ORD_WHO_" .. id:upper()] } end
	if O().VISIBLE_TO ~= "everyone" then chips[3] = nil end
	f.filter:SetItems(chips, View.who)
	f.closed:SetSelected(View.closed)
	local top = View.FILTER_HEIGHT + drawEarlier(f)
	f.table:ClearAllPoints()
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, View.BAR_HEIGHT + 4)
	local search = ns.MarketView and ns.MarketView.search
	local list = O():List({ who = View.who, closed = View.closed, search = search })
	View.rows = list
	local selected = nil
	for _, row in ipairs(list) do if row.id == View.selected then selected = row end end
	if not selected then View.selected, View.armed = nil, nil end
	f.table:SetEmptyText(L[(search and search ~= "") and "ORD_NO_MATCH" or "ORD_EMPTY"])
	f.table:SetData(list, true)
	drawBar(f, selected)
end

if ns.MarketView then
	ns.MarketView.AddMode("orders", { label = L["MARKET_MODE_ORDERS"], order = 10, build = mode.build, refresh = mode.refresh,
		available = function() return O() ~= nil and O().Enabled() end })
end

---------------------------------------------------------------------------------------------------------------------
-- The "New order" window
---------------------------------------------------------------------------------------------------------------------
local function chosen(d)
	local guid = d.crafter:Selected()
	for _, c in ipairs(d.crafters or {}) do
		if c.guid == guid then return c end
	end
	return nil
end

-- The line about the chosen crafter and the whisper switch (off, and locked for somebody offline).
local function paintCrafter(d)
	local c = chosen(d)
	local online = c ~= nil and c.online
	say(d.offline, c and not online and L["ORD_OFFLINE"]:format(escape(c.name)) or "")
	d.whisper:SetEnabled(online)
	if not online then d.whisper:SetOn(false, true) end
	d.whisperText:SetText(c and L["ORD_ALSO_WHISPER"]:format(escape(c.name)) or "")
end

local function buildNew()
	local w = View.WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordOrderDialog", { width = w, height = View.HEIGHT })
	local card = d.card
	d:SetTitle("")
	d.title:SetText(L["ORD_NEW_TITLE"])
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
	d.icon = card:CreateTexture(nil, "ARTWORK")
	d.icon:SetSize(View.ICON, View.ICON)
	d.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -58)
	d.recipe = Widgets.Text(card, "BodyMedium", "text-1", "LEFT")
	d.recipe:SetPoint("LEFT", d.icon, "RIGHT", 8, 0)
	d.recipe:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	label("ORD_CRAFTER", 24, 90)
	d.crafter = Widgets.Select(card, { width = w - 48, rows = 8, placeholder = L["ORD_CRAFTER"],
		onSelect = function() paintCrafter(d) end })
	d.crafter:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -108)
	d.offline = Widgets.Text(card, "Small", "text-3", "LEFT")
	d.offline:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -146)
	d.offline:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	label("ORD_COUNT", 24, 166)
	d.count = field(184, 24, 96, 3)
	label("ORD_BY", 140, 166)
	d.by = field(184, 140, 180, 10, L["ORD_BY_HINT"])
	label("ORD_MATS", 24, 230)
	local items = {}
	for i, id in ipairs(O().MATS) do items[i] = { id = id, text = L["ORD_BRING_" .. id:upper()] } end
	d.mats = Widgets.Segmented(card, items)
	d.mats:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -248)
	label("ORD_PRICE", 24, 292)
	d.price = field(310, 24, w - 48, 24, L["ORD_PRICE_HINT"])
	label("ORD_NOTE", 24, 354)
	d.note = field(372, 24, w - 48, 80)
	d.whisper = Widgets.Switch(card, {})
	d.whisper:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -418)
	d.whisperText = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.whisperText:SetPoint("LEFT", d.whisper, "RIGHT", 8, 0)
	d.whisperText:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.status:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -460)
	d.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.status:SetWordWrap(true)
	d.ok = Widgets.Button(card, { text = L["ORD_PLACE"], style = "filled", onClick = function() View:Place() end })
	d.cancel = Widgets.Button(card, { text = L["ORD_CLOSE"], style = "outlined", onClick = function() d:Close() end })
	d:SetActions({ d.cancel, d.ok })
	return d
end

-- The window for one recipe and (chosen, may be changed) one crafter. Returns it, or nil while it cannot be ordered.
function View:OpenNew(crafter, recipe, opts)
	local M = O()
	if not (M and M.Enabled() and type(recipe) == "number") then return nil end
	if crafter ~= nil and not M:CanOrder(crafter) then return nil end
	local list = M:CraftersOf(recipe, crafter)
	if #list == 0 then return nil end
	if not self.dialog then self.dialog = buildNew() end
	local d = self.dialog
	d.recipeId, d.from, d.crafters = recipe, opts and opts.from or nil, list
	local info = ns.Recipes and ns.Recipes.SpellData(recipe)
	if info and info.icon then d.icon:SetTexture(info.icon) d.icon:Show() else d.icon:Hide() end
	d.recipe:SetText(escape(M.RecipeName(recipe)))
	local choices = {}
	for i, c in ipairs(list) do
		choices[i] = { id = c.guid, text = c.online and L["ORD_CHOICE_ONLINE"]:format(escape(c.name)) or escape(c.name) }
	end
	d.crafter:SetChoices(choices)
	d.crafter:Select(crafter or list[1].guid, true)
	d.count:SetText("1")
	d.by:SetText("")
	d.price:SetText("")
	d.note:SetText("")
	d.mats:Select("buyer")
	d.whisper:SetOn(false, true)   -- off by default (SPEC-17 §3.5)
	paintCrafter(d)
	say(d.status, L["ORD_NEW_HINT"])
	d:Open()
	return d
end

-- Places the order of the window. Returns the record, or false and a reason.
function View:Place()
	local d = self.dialog
	if not d then return false, "off" end
	local guid, recipe = d.crafter:Selected(), d.recipeId
	local rec, why = O():Create({ crafter = guid, recipe = recipe, count = tonumber(d.count:GetText()) or -1,
		mats = d.mats:Active(), price = d.price:GetText(), note = d.note:GetText(), by = d.by:GetText(), from = d.from })
	if not rec then
		say(d.status, View.ErrorText(why), "err")
		return false, why
	end
	local whisper = d.whisper:IsOn()
	d:Close()
	local name = O().NameOf(guid)
	if ns.addon then ns.addon:Print(L["ORD_PLACED"]:format(escape(name))) end
	if whisper then   -- the whisper of M3, written in the chat box: the player sends it
		local request = ns.Recipes and ns.Recipes:CraftRequest(guid, recipe)
		if not (request and ns.Compat.Chat.OpenWhisper(request.name, request.text)) and ns.addon then
			ns.addon:Print(L["CR_REQUEST_FAILED"])
		end
	end
	redraw()
	return rec
end

---------------------------------------------------------------------------------------------------------------------
-- The member card
---------------------------------------------------------------------------------------------------------------------
function View.CardSection(e)
	local M = O()
	if not (M and M.Enabled()) or type(e) ~= "table" or type(e.guid) ~= "string" or e.notInGuild then return nil end
	local buying, crafting = M:OfMember(e.guid)
	local wishes = ns.WishlistView and ns.WishlistView.CardLines(e.guid) or {}
	if #buying == 0 and #crafting == 0 and #wishes == 0 then return nil end
	local lines = {}
	local function add(list, key, side)
		for _, row in ipairs(list) do
			local id = row.id
			lines[#lines + 1] = { text = L[key]:format(View.ItemText(row), escape(row[side]), View.StateText(row)), action = true,
				onClick = function() View:Open(id) end }
		end
	end
	add(buying, "ORD_CARD_BUYING", "crafterName")
	add(crafting, "ORD_CARD_CRAFTING", "buyerName")
	for _, line in ipairs(wishes) do lines[#lines + 1] = line end   -- then the character's wishes (M13.3)
	return { id = "market", title = L["ORD_CARD_TITLE"], lines = lines }
end

if ns.MemberCard then ns.MemberCard.AddSection("market", 7.48, View.CardSection) end

if ns.addon then
	ns.addon.OrdersView = View
	if ns.Bus then
		ns.Bus:On("ORDERS_CHANGED", function()
			if not (O() and O().Enabled()) then return end
			if ns.MemberCard then ns.MemberCard:Refresh() end
			if ns.MarketView then ns.MarketView:Changed() end
		end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.who, View.closed, View.selected, View.armed, View.error = "all", false, nil, nil, nil
			if View.dialog then View.dialog:Close() end
		end)
	end
end

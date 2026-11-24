-- Settings view (SPEC-04 §4, M6.1; restyled in M6.14): the look of the addon (the Appearance card: theme, neon effects,
-- animations, font), the contacts the player shares with the guild (M2.5, SPEC-05 CON-01, CON-02), the main character,
-- the notices, the Roster columns, the sizes of the saved data with "Clear guild data", and the personal backup (M7.5,
-- SPEC-11 §4.3: Export and Import open UI/BackupBox.lua). Lua 5.1.
-- UI/SettingsModel.lua holds the options and the actions; this file only draws them, as a column of Widgets.Cards on a page that
-- scrolls. One builder, Settings.Build(parent), serves both places: the Settings view of the panel (a view of the Shell)
-- and the canvas panel in the game's Settings window (registered at login when the client has
-- Settings.RegisterCanvasLayoutCategory), so they always show the same.
--
-- The BattleTag is read from the game and shown here; the Discord user name is typed (at most 32 characters, no links)
-- and used when the server does not give it natively. Both are always shared with the guild (owner decision D3): the
-- text says so and there is no switch.
--   View.Build(parent) -> frame   the page selector (only with more than one page) and the pages; the Settings page's
--                                 controls are fields of the frame: .theme, .effects, .animations, .font (Appearance),
--                                 .battleTag, .discordEdit, .save, .status, .main, .checks[key], .columnChecks[i],
--                                 .sizes[i], .clear ...; frame:Refresh() re-reads every value
--   View.AddPage(id, def)         another page beside "Settings" (M6.15: Info): def = { label, order, build(frame, f) },
--                                 added while the files load, before any page is built; the selector (Widgets.Segmented)
--                                 appears once there are two pages
--   View.frame                    the frame of the Settings view of the panel (nil until it is shown once)
--   View.RegisterPanel()          adds the panel to the game's Settings window (once); false when the client has none
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.SettingsView, ns.modules = View, ns.modules or {}
ns.modules.SettingsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, type, pairs, max, min, floor, ceil = ipairs, type, pairs, math.max, math.min, math.floor, math.ceil

View.PAGE_WIDTH = 520
View.CARD_PAD = 24              -- inside a card
View.CARD_GAP = 16              -- between cards
View.PAGER_HEIGHT = 44          -- the page selector, when there is one
View.WHEEL_STEP = 40
View.CONFIRM_SECONDS = 8        -- how long "Click again to clear" waits
View.MAX_SIZE_LINES = 12
View.COLUMN_CHIPS_PER_LINE = 3
View.PANEL_FRAME = "AzerothAccordSettingsPanel"
View.instances = {}             -- every page built (the panel's view, the game's Settings panel): refreshed together
View.pages = {}                 -- { id, label, order, build } in order

local function Model() return ns.SettingsModel end

---------------------------------------------------------------------------------------------------------------------
-- Small parts
---------------------------------------------------------------------------------------------------------------------
local INNER = View.PAGE_WIDTH - 2 * View.CARD_PAD   -- the width of a card's content

-- A card whose items stack from the top: card:Add(region, gap, x) places the region `gap` points under the previous one;
-- card:Layout() places them (hidden ones take no room) and sets the card's height from what it holds.
local function stackCard(page)
	local c = Widgets.Card(page, { width = View.PAGE_WIDTH, height = 100 })
	c.items = {}
	function c:Add(region, gap, x)
		self.items[#self.items + 1] = { region = region, gap = gap or 8, x = x or 0 }
		return region
	end
	function c:Layout()
		local y, first = View.CARD_PAD - 4, true
		for _, it in ipairs(self.items) do
			local r = it.region
			if r:IsShown() then
				if not first then y = y + it.gap end
				first = false
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", self, "TOPLEFT", View.CARD_PAD + it.x, -y)
				local h
				if r.GetObjectType and r:GetObjectType() == "FontString" then h = r:GetStringHeight() else h = r:GetHeight() end
				y = y + (h or 0)
			end
		end
		self:SetHeight(y + View.CARD_PAD - 4)
		return self:GetHeight()
	end
	return c
end

local function text(parent, font, token, width)
	local fs = Widgets.Text(parent, font or "Body", token or "text-1", "LEFT")
	fs:SetWidth(width or INNER)
	fs:SetWordWrap(true)
	return fs
end

local function title(card, label)
	local fs = text(card, "H2", "text-1")
	fs:SetText(label)
	return card:Add(fs, 0)
end

-- A line with a label at the left and a Widgets.Switch at the right; a click anywhere on it flips the switch.
-- :GetChecked(), :SetChecked(v) (silent), :Click(); onChange(on) after the player flips it.
local function switchRow(parent, label, tip, onChange)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(INNER, 32)
	row.switch = Widgets.Switch(row, { onChange = function(on) onChange(on, row) end })
	row.switch:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.label = Widgets.Text(row, "Body", "text-1", "LEFT")
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label:SetPoint("RIGHT", row.switch, "LEFT", -12, 0)
	row.label:SetText(label)
	if tip then Widgets.Tooltip.Attach(row, tip, "RIGHT") end
	row:SetScript("OnClick", function(self) self.switch:Click() end)
	function row:GetChecked() return self.switch:IsOn() end
	function row:SetChecked(v) self.switch:SetOn(v, true) end
	return row
end

-- A line with a label at the left and a Widgets.Segmented at the right.
local function segmentRow(parent, label, items, onSelect)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(INNER, 32)
	row.seg = Widgets.Segmented(row, items, onSelect)
	row.seg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.label = Widgets.Text(row, "Body", "text-1", "LEFT")
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label:SetPoint("RIGHT", row.seg, "LEFT", -12, 0)
	row.label:SetText(label)
	return row
end

local function say(fs, msg, token)
	fs:SetText(msg or "")
	Theme.Text(fs, token or "text-2")
end

---------------------------------------------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------------------------------------------
local function refreshLook(f)
	local M = Model()
	f.theme.seg:Select(M.GetLook("theme"))
	f.font.seg:Select(M.GetLook("font"))
	f.effects:SetChecked(M.GetLook("effects"))
	f.animations:SetChecked(M.GetLook("animations"))
end

local function refreshContacts(f)
	local C = ns.Contacts
	local tag = C and C:OwnBattleTag()
	f.battleTag:SetText(tag and L["SET_BATTLETAG"]:format(tag) or L["SET_BATTLETAG_UNKNOWN"])
	local typed = C and C:OwnDiscord() or ""
	if not f.discordEdit:HasFocus() then f.discordEdit:SetText(typed) end
	local mine = ns.Roster and ns.Roster:ByGUID(ns.Compat.Player.GUID())
	f.native:SetShown(mine ~= nil and mine.discordSource == "native")
end

local function refreshMain(f)
	local choices = Model().MainChoices()
	f.mainChoices = choices
	local current
	for _, c in ipairs(choices) do if c.isMain then current = c end end
	if current then
		f.main:SetText(L["SET_MAIN_CURRENT"]:format(current.name or "?", current.level or 0))
	else
		f.main:SetText(L["SET_MAIN_NONE"])
	end
	f.mainChoose:SetEnabled(#choices > 1)
end

local function refreshNotices(f)
	local M = Model()
	for _, o in ipairs(M.OPTIONS) do
		local check = f.checks[o.key]
		if check then
			check:SetChecked(M.Get(o.key))
			check:SetShown(M.Visible(o.key))
		end
	end
end

local function refreshColumns(f)
	local choices = Model().ColumnChoices()
	f.columnChoices = choices
	local per = View.COLUMN_CHIPS_PER_LINE
	local cell = floor(INNER / per)
	for i, c in ipairs(choices) do
		local chip = f.columnChecks[i]
		if not chip then
			chip = Widgets.Chip(f.columnsBox, { height = 26, onClick = function(self)
				if self.columnId then Model().ToggleColumn(self.columnId) end
			end })
			f.columnChecks[i] = chip
		end
		chip.columnId = c.id
		chip:SetLabel(L[c.label])
		chip:SetSelected(c.on)
		chip:SetEnabled(not c.always)
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", f.columnsBox, "TOPLEFT", ((i - 1) % per) * cell, -floor((i - 1) / per) * 32)
		chip:Show()
	end
	for i = #choices + 1, #f.columnChecks do f.columnChecks[i]:Hide() end
	f.columnsBox:SetHeight(max(1, ceil(#choices / per) * 32 - 6))
	f.columnsBox:SetShown(#choices > 0)
	f.columnsReset:SetShown(#choices > 0)
	f.columnsNone:SetShown(#choices == 0)
end

-- The lines of the "Saved data" card.
function View.SizeLines()
	local M = Model()
	local s = M.Sizes()
	local lines = {
		L["SET_DATA_ACCOUNT"]:format(M.FormatBytes(s.account), s.guilds),
		L["SET_DATA_CHAR"]:format(M.FormatBytes(s.char)),
	}
	if not (ns.Role and ns.Role:InGuild()) then
		lines[#lines + 1] = L["SET_DATA_NOGUILD"]
	elseif not s.guild then
		lines[#lines + 1] = L["SET_DATA_NONE"]
	else
		lines[#lines + 1] = L["SET_DATA_GUILD"]:format(M.FormatBytes(s.guild))
		for _, p in ipairs(s.parts) do
			if #lines >= View.MAX_SIZE_LINES then break end
			if p.records then
				lines[#lines + 1] = "   " .. L["SET_DATA_PART_RECORDS"]:format(p.name, M.FormatBytes(p.bytes), p.records)
			else
				lines[#lines + 1] = "   " .. L["SET_DATA_PART"]:format(p.name, M.FormatBytes(p.bytes))
			end
		end
	end
	return lines
end

local function refreshData(f)
	local lines = View.SizeLines()
	for i, fs in ipairs(f.sizes) do
		fs:SetText(lines[i] or "")
		fs:SetShown(lines[i] ~= nil)
	end
	f.clear:SetEnabled(ns.Role ~= nil and ns.Role:InGuild() and ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil)
end

-- The Backup card (SPEC-11 §4.3): no export in the demo, no import in the demo nor with read-only data; the card says why.
local function refreshBackup(f)
	local B = ns.Backup
	local demo = ns.Demo ~= nil and ns.Demo:IsActive()
	local blocked = "db"
	if B then blocked = B:ImportBlocked() end
	f.backupExport:SetEnabled(B ~= nil and not demo)
	f.backupImport:SetEnabled(blocked == nil)
	if demo then
		say(f.backupNote, L["BACKUP_NO_DEMO"], "warn")
	elseif blocked == "read-only" then
		say(f.backupNote, L["BACKUP_READONLY"], "warn")
	else
		say(f.backupNote, "")
	end
	f.backupNote:SetShown((f.backupNote:GetText() or "") ~= "")
end

-- The cards take the height of what they show now, one under the other; the page is as tall as the column.
local function layout(f)
	local y = 0
	for _, card in ipairs(f.cards) do
		card:Layout()
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, -y)
		y = y + card:GetHeight() + View.CARD_GAP
	end
	f.pageHeight = max(1, y - View.CARD_GAP + 8)
	f.page:SetHeight(f.pageHeight)
	local range = max(0, f.pageHeight - (f.scroll:GetHeight() or 0))
	if (f.scroll:GetVerticalScroll() or 0) > range then f.scroll:SetVerticalScroll(range) end
end

local function refresh(f)
	refreshLook(f)
	refreshContacts(f)
	refreshMain(f)
	refreshNotices(f)
	refreshColumns(f)
	refreshData(f)
	refreshBackup(f)
	layout(f)
end

-- Refreshes every page that is on screen (a change in one is visible in the other). A hidden page refreshes when it is
-- shown: the sizes of a big guild take a moment to count, and nobody sees them while the page is hidden.
function View:Refresh()
	for _, f in ipairs(View.instances) do
		if f:IsVisible() then refresh(f) end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------------
-- A look value changed on the page: saved at once (Theme repaints on CONFIG_CHANGED); a refusal is said under the card.
function View:SetLook(f, key, value)
	local ok, why = Model().SetLook(key, value)
	if ok then
		say(f.lookStatus, "")
	else
		say(f.lookStatus, L["SET_LOOK_FAILED"]:format(tostring(why)), "err")
		refreshLook(f)
	end
	return ok
end

function View:Save(f)
	f = f or self.frame
	local ok, why = ns.Contacts:SetDiscord(f.discordEdit:GetText() or "")
	if ok then
		say(f.status, why == "cleared" and L["SET_CLEARED"] or L["SET_SAVED"], "ok")
	else
		say(f.status, L["SET_INVALID"], "err")
	end
	f.discordEdit:ClearFocus()
	return ok
end

function View:ChooseMain(f, anchor)
	local items = {}
	for _, c in ipairs(f.mainChoices or {}) do
		items[#items + 1] = { text = ("%s (%d)"):format(c.name or "?", c.level or 0), checked = c.isMain, onClick = function()
			local ok = Model().SetMain(c.guid)
			if ok then
				say(f.mainStatus, L["SET_MAIN_SAVED"]:format(c.name or "?"), "ok")
			else
				say(f.mainStatus, L["SET_MAIN_FAILED"], "err")
			end
			View:Refresh()
		end }
	end
	Widgets.Menu.Show(anchor, items)
end

-- Two clicks: the first one arms the button for CONFIRM_SECONDS and shows what will be freed, the second one clears.
function View:Clear(f)
	if not f.clearArmed then
		f.clearArmed = true
		local s = Model().Sizes()
		f.clear:SetLabel(L["SET_CLEAR_CONFIRM"]:format(Model().FormatBytes(s.guild or 0)))
		if ns.Compat then
			ns.Compat.After(View.CONFIRM_SECONDS, function() View:Disarm(f) end)
		end
		return "armed"
	end
	View:Disarm(f)
	local freed, why = Model().ClearGuildData()
	if freed == false then
		say(f.clearStatus, L["SET_CLEAR_FAILED"]:format(tostring(why)), "err")
		return "failed"
	end
	say(f.clearStatus, L["SET_CLEAR_DONE"]:format(Model().FormatBytes(freed)), "ok")
	View:Refresh()
	return "cleared"
end

-- `/accord backup`: the Settings page of the panel, scrolled to the Backup card.
function View:ShowBackup()
	local f = self.frame
	if not f then return false end
	self:ShowPage(f, "settings")
	refresh(f)
	local y = 0
	for _, card in ipairs(f.cards) do
		if card == f.backupCard then break end
		y = y + card:GetHeight() + View.CARD_GAP
	end
	local range = max(0, (f.pageHeight or 0) - (f.scroll:GetHeight() or 0))
	f.scroll:SetVerticalScroll(min(range, y))
	return true
end

function View:Disarm(f)
	if not f.clearArmed then return end
	f.clearArmed = false
	f.clear:SetLabel(L["SET_CLEAR"])
end

---------------------------------------------------------------------------------------------------------------------
-- Build: the Settings page
---------------------------------------------------------------------------------------------------------------------
local function buildLook(f, page)
	local M = Model()
	local card = stackCard(page)
	f.lookTitle = title(card, L["SET_LOOK_TITLE"])
	f.lookText = card:Add(text(card, "Small", "text-3"), 6)
	f.lookText:SetText(L["SET_LOOK_TEXT"])
	local themes = {}
	for i, id in ipairs(M.LOOK.theme.values) do themes[i] = { id = id, text = L["THEME_" .. id:upper()] } end
	f.theme = card:Add(segmentRow(card, L["SET_LOOK_THEME"], themes, function(id)
		if id ~= M.GetLook("theme") then View:SetLook(f, "theme", id) end
	end), 14)
	f.effects = card:Add(switchRow(card, L["SET_LOOK_EFFECTS"], { L["SET_LOOK_EFFECTS"], L["SET_LOOK_EFFECTS_TIP"] },
		function(on) View:SetLook(f, "effects", on) end), 8)
	f.animations = card:Add(switchRow(card, L["SET_LOOK_ANIMATIONS"], { L["SET_LOOK_ANIMATIONS"], L["SET_LOOK_ANIMATIONS_TIP"] },
		function(on) View:SetLook(f, "animations", on) end), 8)
	f.font = card:Add(segmentRow(card, L["SET_LOOK_FONT"], { { id = "addon", text = L["SET_LOOK_FONT_ADDON"] },
		{ id = "game", text = L["SET_LOOK_FONT_GAME"] } }, function(id)
		if id ~= M.GetLook("font") then View:SetLook(f, "font", id) end
	end), 8)
	f.fontNote = card:Add(text(card, "Small", "text-3"), 6)
	f.fontNote:SetText(L["SET_LOOK_FONT_NOTE"])
	f.lookStatus = card:Add(text(card, "Small", "text-2"), 6)
	return card
end

local function buildContacts(f, page)
	local card = stackCard(page)
	f.title = title(card, L["SET_CONTACTS"])
	f.explain = card:Add(text(card, "Body", "text-2"), 8)
	f.explain:SetText(L["SET_CONTACTS_TEXT"])
	f.battleTag = card:Add(text(card, "BodyMedium", "text-1"), 14)
	f.discordLabel = card:Add(text(card, "Eyebrow", "text-3"), 14)
	f.discordLabel:SetText(L["SET_DISCORD"])
	f.discordBox = card:Add(Widgets.EditBox(card, { width = 240, height = 32, maxLetters = ns.Contacts and ns.Contacts.DISCORD_MAX or 32,
		onEnter = function() View:Save(f) end }), 6)
	local edit = f.discordBox.edit
	edit:HookScript("OnEscapePressed", function() refresh(f) end)
	f.discordEdit = edit
	f.save = Widgets.Button(card, { text = L["SET_SAVE"], style = "primary", onClick = function() View:Save(f) end })
	f.save:SetPoint("LEFT", f.discordBox, "RIGHT", 10, 0)
	f.status = card:Add(text(card, "Small", "text-2"), 8)
	f.native = card:Add(text(card, "Small", "text-3"), 6)
	f.native:SetText(L["SET_DISCORD_NATIVE"])
	return card
end

local function buildMain(f, page)
	local card = stackCard(page)
	f.mainTitle = title(card, L["SET_MAIN_TITLE"])
	f.mainText = card:Add(text(card, "Body", "text-2"), 8)
	f.mainText:SetText(L["SET_MAIN_TEXT"])
	f.main = card:Add(text(card, "BodyMedium", "text-1"), 12)
	f.mainChoose = card:Add(Widgets.Button(card, { text = L["SET_MAIN_CHOOSE"], style = "secondary", onClick = function(b) View:ChooseMain(f, b) end }), 8)
	f.mainStatus = Widgets.Text(card, "Small", "text-2", "LEFT")
	f.mainStatus:SetPoint("LEFT", f.mainChoose, "RIGHT", 12, 0)
	return card
end

local function buildNotices(f, page)
	local card = stackCard(page)
	f.noticeTitle = title(card, L["SET_NOTIFY_TITLE"])
	for _, o in ipairs(Model().OPTIONS) do
		if o.group == "notifications" then
			f.checks[o.key] = card:Add(switchRow(card, L[o.label], { L[o.label], L[o.tip] },
				function(on) Model().Set(o.key, on) end), 6)
		end
	end
	f.noticeNote = card:Add(text(card, "Small", "text-3"), 8)
	f.noticeNote:SetText(L["SET_NOTIFY_NOTE"])
	return card
end

local function buildColumns(f, page)
	local card = stackCard(page)
	f.columnsTitle = title(card, L["SET_COLUMNS_TITLE"])
	f.columnsText = card:Add(text(card, "Body", "text-2"), 8)
	f.columnsText:SetText(L["SET_COLUMNS_TEXT"])
	f.columnsAnchor = f.columnsText
	f.columnsNone = card:Add(text(card, "Small", "text-3"), 8)
	f.columnsNone:SetText(L["SET_COLUMNS_NONE"])
	f.columnsBox = card:Add(CreateFrame("Frame", nil, card), 12)
	f.columnsBox:SetSize(INNER, 26)
	f.columnsReset = card:Add(Widgets.Button(card, { text = L["COLUMNS_RESET"], style = "ghost",
		onClick = function() Model().ResetColumns() View:Refresh() end }), 10)
	return card
end

local function buildData(f, page)
	local card = stackCard(page)
	f.dataTitle = title(card, L["SET_DATA_TITLE"])
	f.dataText = card:Add(text(card, "Body", "text-2"), 8)
	f.dataText:SetText(L["SET_DATA_TEXT"])
	for i = 1, View.MAX_SIZE_LINES do
		f.sizes[i] = card:Add(text(card, "MonoSmall", "text-2"), i == 1 and 10 or 3)
	end
	f.clear = card:Add(Widgets.Button(card, { text = L["SET_CLEAR"], style = "secondary", width = 240, onClick = function() View:Clear(f) end }), 14)
	Widgets.Tooltip.Attach(f.clear, { L["SET_CLEAR"], L["SET_CLEAR_TEXT"] }, "RIGHT")
	f.clearText = card:Add(text(card, "Small", "text-3"), 8)
	f.clearText:SetText(L["SET_CLEAR_TEXT"])
	f.clearStatus = card:Add(text(card, "Small", "text-2"), 6)
	return card
end

local function buildBackup(f, page)
	local card = stackCard(page)
	f.backupTitle = title(card, L["SET_BACKUP_TITLE"])
	f.backupText = card:Add(text(card, "Body", "text-2"), 8)
	f.backupText:SetText(L["SET_BACKUP_TEXT"])
	f.backupWarning = card:Add(text(card, "Small", "warn"), 8)
	f.backupWarning:SetText(L["BACKUP_WARNING"])
	f.backupExport = card:Add(Widgets.Button(card, { text = L["SET_BACKUP_EXPORT"], style = "secondary", width = 140,
		onClick = function() if ns.BackupBox then ns.BackupBox:OpenExport() end end }), 14)
	f.backupImport = Widgets.Button(card, { text = L["SET_BACKUP_IMPORT"], style = "secondary", width = 140,
		onClick = function() if ns.BackupBox then ns.BackupBox:OpenImport() end end })
	f.backupImport:SetPoint("LEFT", f.backupExport, "RIGHT", 12, 0)
	f.backupNote = card:Add(text(card, "Small", "text-2"), 8)
	return card
end

-- The Settings page: the cards on a page that scrolls with the wheel.
local function buildSettingsPage(holder, f)
	f.checks, f.columnChecks, f.sizes = {}, {}, {}
	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetAllPoints(holder)
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(View.PAGE_WIDTH, 100)
	scroll:SetScrollChild(page)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = max(0, (f.pageHeight or 0) - (self:GetHeight() or 0))
		local v = (self:GetVerticalScroll() or 0) - delta * View.WHEEL_STEP
		self:SetVerticalScroll(min(range, max(0, v)))
	end)
	f.scroll, f.page = scroll, page
	f.cards = { buildLook(f, page), buildContacts(f, page), buildMain(f, page), buildNotices(f, page), buildColumns(f, page),
		buildData(f, page), buildBackup(f, page) }
	f.lookCard = f.cards[1]
	f.backupCard = f.cards[#f.cards]
end

View.pages[1] = { id = "settings", label = L["VIEW_SETTINGS"], order = 10, build = buildSettingsPage }

-- Another page beside Settings (M6.15: Info). def = { label, order, build(frame, f) }: build draws into `frame` (the area
-- under the selector) and may keep fields on `f` (the outer frame). Pages are added while the files load.
function View.AddPage(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	for _, p in ipairs(View.pages) do if p.id == id then return false end end
	View.pages[#View.pages + 1] = { id = id, label = def.label or id, order = def.order or 100, build = def.build }
	table.sort(View.pages, function(a, b) return a.order < b.order end)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Build: the frame (the page selector and the pages)
---------------------------------------------------------------------------------------------------------------------
-- Shows page `id` of frame `f` (built the first time it is shown).
function View:ShowPage(f, id)
	local def
	for _, p in ipairs(View.pages) do if p.id == id then def = p end end
	if not def then return false end
	f.pageId = id
	for pid, holder in pairs(f.holders) do holder:SetShown(pid == id) end
	if not f.holders[id] then
		local holder = CreateFrame("Frame", nil, f)
		holder:SetPoint("TOPLEFT", f, "TOPLEFT", 0, f.pager and -View.PAGER_HEIGHT or 0)
		holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.holders[id] = holder
		def.build(holder, f)
	end
	if f.pager then f.pager:Select(id) end
	return true
end

function View.Build(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f.holders = {}
	if #View.pages > 1 then
		local items = {}
		for i, p in ipairs(View.pages) do items[i] = { id = p.id, text = p.label } end
		f.pager = Widgets.Segmented(f, items, function(id) View:ShowPage(f, id) end)
		f.pager:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	end
	View:ShowPage(f, "settings")
	f.Refresh = refresh
	f:SetScript("OnShow", function() refresh(f) end)
	View.instances[#View.instances + 1] = f
	refresh(f)
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- The view of the panel and the panel of the game's Settings window
---------------------------------------------------------------------------------------------------------------------
if ns.Shell then
	ns.Shell:RegisterView("settings", { label = L["VIEW_SETTINGS"], order = 90, build = function(f) View.frame = View.Build(f) end })
end

-- The canvas of the game's Settings window: the same page, built the first time the panel is shown. Blizzard sizes a
-- canvas itself; the page fills it, on the theme's background (the window around it stays Blizzard's).
local function makePanelFrame()
	local panel = CreateFrame("Frame", View.PANEL_FRAME, UIParent)
	panel:Hide()
	panel.fill = panel:CreateTexture(nil, "BACKGROUND")
	panel.fill:SetAllPoints(panel)
	Theme.Fill(panel.fill, "bg")
	local title = Widgets.Text(panel, "DisplaySmall", "accent-text", "LEFT")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
	title:SetText(L["ADDON_TITLE"])
	local body = CreateFrame("Frame", nil, panel)
	body:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -44)
	body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 8)
	panel:SetScript("OnShow", function() if not View.panelFrame then View.panelFrame = View.Build(body) end end)
	panel.default = function() end   -- the "Defaults" button of the Settings window: Accord's options apply as they change
	return panel
end

function View.RegisterPanel()
	return Model().RegisterPanel(makePanelFrame)
end

if ns.addon then
	ns.addon.SettingsView = View
	if ns.Bus then
		ns.Bus:On("FEATURE_CHANGED", function(id) if id == "battleTag" then View:Refresh() end end)
		ns.Bus:On("SETTINGS_CHANGED", function() View:Refresh() end)
		ns.Bus:On("ROLE_CHANGED", function() View:Refresh() end)
		ns.Bus:On("GUILD_CHANGED", function() View:Refresh() end)
		ns.Bus:On("DEMO_CHANGED", function() View:Refresh() end)
	end
	if ns.OnEnable then ns.OnEnable(function() View.RegisterPanel() end) end
end

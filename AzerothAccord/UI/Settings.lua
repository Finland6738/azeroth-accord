-- Settings view (SPEC-04 §4, M6.1): the contacts the player shares with the guild (M2.5, SPEC-05 CON-01, CON-02), the
-- main character, the notices, the Roster columns, and the sizes of the saved data with "Clear guild data". Lua 5.1.
-- UI/SettingsModel.lua holds the options and the actions; this file only draws them. One builder, Settings.Build(parent),
-- serves both places: the Settings view of the panel (a view of the Shell) and the canvas panel in the game's Settings
-- window (registered at login when the client has Settings.RegisterCanvasLayoutCategory), so they always show the same.
--
-- The BattleTag is read from the game and shown here; the Discord user name is typed (at most 32 characters, no links)
-- and used when the server does not give it natively. Both are always shared with the guild (owner decision D3): the
-- text says so and there is no switch.
--   View.Build(parent) -> frame   a scrolling page; frame.battleTag, .discordEdit, .save, .status, .main, .checks[key],
--                                 .columnChecks[id], .sizes[i], .clear ... are the controls; frame:Refresh() re-reads every value
--   View.frame                    the frame of the Settings view of the panel (nil until it is shown once)
--   View.RegisterPanel()          adds the panel to the game's Settings window (once); false when the client has none
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.SettingsView, ns.modules = View, ns.modules or {}
ns.modules.SettingsView = View

local L, W, Skin = ns.L, ns.Widgets, ns.Skin
local ipairs, type, pairs = ipairs, type, pairs

View.PAGE_WIDTH = 500
View.PAGE_HEIGHT = 860          -- the page is taller than the panel: it scrolls
View.WHEEL_STEP = 40
View.CONFIRM_SECONDS = 8        -- how long "Click again to clear" waits
View.MAX_SIZE_LINES = 12
View.PANEL_FRAME = "AzerothAccordSettingsPanel"
View.instances = {}             -- every page built (the panel's view, the game's Settings panel): refreshed together

local function Model() return ns.SettingsModel end

---------------------------------------------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------------------------------------------
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
		check:SetChecked(M.Get(o.key))
		local visible = M.Visible(o.key)
		check:SetShown(visible)
	end
end

local function refreshColumns(f)
	local choices = Model().ColumnChoices()
	f.columnChoices = choices
	local x, y = 0, 0
	local per = 3
	for i, c in ipairs(choices) do
		local check = f.columnChecks[i]
		if not check then
			check = W.Check(f.page, { text = "", width = 150, onClick = function(_, self)
				if self.columnId then Model().ToggleColumn(self.columnId) end
			end })
			f.columnChecks[i] = check
		end
		check.columnId = c.id
		check.label:SetText(L[c.label])
		check:SetChecked(c.on)
		if c.always then check:Disable() else check:Enable() end
		check:ClearAllPoints()
		check:SetPoint("TOPLEFT", f.columnsAnchor, "BOTTOMLEFT", ((i - 1) % per) * 160, -6 - math.floor((i - 1) / per) * 22)
		check:Show()
	end
	for i = #choices + 1, #f.columnChecks do f.columnChecks[i]:Hide() end
	local rows = math.ceil(#choices / per)
	f.columnsReset:ClearAllPoints()
	f.columnsReset:SetPoint("TOPLEFT", f.columnsAnchor, "BOTTOMLEFT", 0, -10 - rows * 22)
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

local function refresh(f)
	refreshContacts(f)
	refreshMain(f)
	refreshNotices(f)
	refreshColumns(f)
	refreshData(f)
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
local function say(f, text, color)
	f.status:SetText(text)
	f.status:SetTextColor(Skin.Color(color or "white"))
end

function View:Save(f)
	f = f or self.frame
	local ok, why = ns.Contacts:SetDiscord(f.discordEdit:GetText() or "")
	if ok then
		say(f, why == "cleared" and L["SET_CLEARED"] or L["SET_SAVED"], "green")
	else
		say(f, L["SET_INVALID"], "red")
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
				f.mainStatus:SetText(L["SET_MAIN_SAVED"]:format(c.name or "?"))
				f.mainStatus:SetTextColor(Skin.Color("green"))
			else
				f.mainStatus:SetText(L["SET_MAIN_FAILED"])
				f.mainStatus:SetTextColor(Skin.Color("red"))
			end
			View:Refresh()
		end }
	end
	W.ShowMenu(anchor, items)
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
		f.clearStatus:SetText(L["SET_CLEAR_FAILED"]:format(tostring(why)))
		f.clearStatus:SetTextColor(Skin.Color("red"))
		return "failed"
	end
	f.clearStatus:SetText(L["SET_CLEAR_DONE"]:format(Model().FormatBytes(freed)))
	f.clearStatus:SetTextColor(Skin.Color("green"))
	View:Refresh()
	return "cleared"
end

function View:Disarm(f)
	if not f.clearArmed then return end
	f.clearArmed = false
	f.clear:SetLabel(L["SET_CLEAR"])
end

---------------------------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------------------------
local function heading(page, anchor, text, gap)
	local h = W.Text(page, "title", "gold", "LEFT")
	h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 24))
	h:SetText(text)
	return h
end

local function paragraph(page, anchor, text, gap, style, color)
	local p = W.Text(page, style or "body", color, "LEFT")
	p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 8))
	p:SetWidth(View.PAGE_WIDTH - 30)
	p:SetText(text)
	return p
end

function View.Build(parent)
	local f = W.Frame(parent, 10, 10)
	f:SetAllPoints(parent)
	f.checks, f.columnChecks, f.sizes = {}, {}, {}

	-- the scrolling page
	local scroll = CreateFrame("ScrollFrame", nil, f)
	scroll:SetAllPoints(f)
	local page = W.Frame(scroll, View.PAGE_WIDTH, View.PAGE_HEIGHT)
	scroll:SetScrollChild(page)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, View.PAGE_HEIGHT - (self:GetHeight() or 0))
		local v = (self:GetVerticalScroll() or 0) - delta * View.WHEEL_STEP
		self:SetVerticalScroll(math.min(range, math.max(0, v)))
	end)
	f.scroll, f.page = scroll, page

	-- 1. contacts
	local top = W.Frame(page, 1, 1)
	top:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
	f.title = W.Text(page, "title", "gold", "LEFT")
	f.title:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
	f.title:SetText(L["SET_CONTACTS"])
	f.explain = paragraph(page, f.title, L["SET_CONTACTS_TEXT"], 8)
	f.battleTag = W.Text(page, "body", nil, "LEFT")
	f.battleTag:SetPoint("TOPLEFT", f.explain, "BOTTOMLEFT", 0, -16)
	f.discordLabel = W.Text(page, "body", nil, "LEFT")
	f.discordLabel:SetPoint("TOPLEFT", f.battleTag, "BOTTOMLEFT", 0, -14)
	f.discordLabel:SetText(L["SET_DISCORD"])
	local edit = W.Create("EditBox", nil, page, { "InputBoxTemplate", "" })
	edit:SetSize(220, 22)
	edit:SetPoint("TOPLEFT", f.discordLabel, "BOTTOMLEFT", 6, -6)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(ns.Contacts and ns.Contacts.DISCORD_MAX or 32)
	edit:SetScript("OnEnterPressed", function() View:Save(f) end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() refresh(f) end)
	f.discordEdit = edit
	f.save = W.Button(page, { text = L["SET_SAVE"], width = 90, onClick = function() View:Save(f) end })
	f.save:SetPoint("LEFT", edit, "RIGHT", 10, 0)
	f.status = W.Text(page, "small", nil, "LEFT")
	f.status:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -6, -8)
	f.native = paragraph(page, f.status, L["SET_DISCORD_NATIVE"], 6, "small", "grey")

	-- 2. main character
	f.mainTitle = heading(page, f.native, L["SET_MAIN_TITLE"])
	f.mainText = paragraph(page, f.mainTitle, L["SET_MAIN_TEXT"], 8)
	f.main = W.Text(page, "body", nil, "LEFT")
	f.main:SetPoint("TOPLEFT", f.mainText, "BOTTOMLEFT", 0, -12)
	f.mainChoose = W.Button(page, { text = L["SET_MAIN_CHOOSE"], width = 110, onClick = function(b) View:ChooseMain(f, b) end })
	f.mainChoose:SetPoint("TOPLEFT", f.main, "BOTTOMLEFT", 0, -6)
	f.mainStatus = W.Text(page, "small", nil, "LEFT")
	f.mainStatus:SetPoint("LEFT", f.mainChoose, "RIGHT", 10, 0)

	-- 3. notifications
	f.noticeTitle = heading(page, f.mainChoose, L["SET_NOTIFY_TITLE"])
	for i, o in ipairs(Model().OPTIONS) do
		local check = W.Check(page, { text = L[o.label], width = View.PAGE_WIDTH - 40, tooltip = { L[o.label], L[o.tip] },
			onClick = function(checked) Model().Set(o.key, checked) end })
		check:SetPoint("TOPLEFT", f.noticeTitle, "BOTTOMLEFT", 0, -8 - (i - 1) * 24)
		f.checks[o.key] = check
	end
	f.noticeNote = paragraph(page, f.noticeTitle, L["SET_NOTIFY_NOTE"], 8 + #Model().OPTIONS * 24 + 4, "small", "grey")

	-- 4. Roster columns
	f.columnsTitle = heading(page, f.noticeNote, L["SET_COLUMNS_TITLE"])
	f.columnsText = paragraph(page, f.columnsTitle, L["SET_COLUMNS_TEXT"], 8)
	f.columnsAnchor = f.columnsText
	f.columnsNone = W.Text(page, "small", "grey", "LEFT")
	f.columnsNone:SetPoint("TOPLEFT", f.columnsText, "BOTTOMLEFT", 0, -6)
	f.columnsNone:SetText(L["SET_COLUMNS_NONE"])
	f.columnsReset = W.Button(page, { text = L["COLUMNS_RESET"], width = 130, onClick = function() Model().ResetColumns() View:Refresh() end })

	-- 5. saved data
	f.dataTitle = W.Text(page, "title", "gold", "LEFT")
	f.dataTitle:SetPoint("TOPLEFT", f.columnsReset, "BOTTOMLEFT", 0, -26)
	f.dataTitle:SetText(L["SET_DATA_TITLE"])
	f.dataText = paragraph(page, f.dataTitle, L["SET_DATA_TEXT"], 8)
	local last = f.dataText
	for i = 1, View.MAX_SIZE_LINES do
		local fs = W.Text(page, "small", nil, "LEFT")
		fs:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -8 or -2)
		f.sizes[i] = fs
		last = fs
	end
	f.clear = W.Button(page, { text = L["SET_CLEAR"], width = 200, tooltip = { L["SET_CLEAR"], L["SET_CLEAR_TEXT"] },
		onClick = function() View:Clear(f) end })
	f.clear:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
	f.clearText = paragraph(page, f.clear, L["SET_CLEAR_TEXT"], 6, "small", "grey")
	f.clearStatus = W.Text(page, "small", nil, "LEFT")
	f.clearStatus:SetPoint("TOPLEFT", f.clearText, "BOTTOMLEFT", 0, -6)

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
-- canvas itself; the page fills it.
local function makePanelFrame()
	local panel = CreateFrame("Frame", View.PANEL_FRAME, UIParent)
	panel:Hide()
	local title = W.Text(panel, "title", "gold", "LEFT")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -12)
	title:SetText(L["ADDON_TITLE"])
	local body = W.Frame(panel, 10, 10)
	body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -40)
	body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
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
	end
	if ns.OnEnable then ns.OnEnable(function() View.RegisterPanel() end) end
end

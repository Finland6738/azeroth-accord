-- Shell: the Accord panel and its navigation (SPEC-04 §2-§4). Lua 5.1.
--
-- One content frame, shown in one host at a time: the panel of the Accord tab in the guild window (UI/GuildTab.lua) or
-- the standalone window (UI/Window.lua). The content has
--   * a top bar: the search box (once a view can search), the sync state (guildmates with the addon online, last
--     update) and "Pop out", which moves the panel from the guild window to the larger standalone window;
--   * the navigation on the left: one button per registered view (Roster, Professions, Reputation, Bank, Settings),
--     in order; views of later milestones register themselves, so a view that is not ready never shows;
--   * the body: the selected view, or a welcome text while no view exists (M1).
-- The panel holds no protected action, so it opens and closes in combat too (GT-06).
local ADDON_NAME, ns = ...
ns = ns or {}
local Shell = {}
ns.Shell, ns.modules = Shell, ns.modules or {}
ns.modules.Shell = Shell

local L, W, Skin = ns.L, ns.Widgets, ns.Skin
local type, pairs, ipairs, tostring, floor = type, pairs, ipairs, tostring, math.floor

Shell.NAME = "AzerothAccordShell"
Shell.TOP_BAR = 30
Shell.NAV_WIDTH = 140
Shell.STATUS_REFRESH = 30

Shell.views = {}        -- id -> { id, label, order, build(frame), frame, search }
Shell.host = nil        -- the host the content is in now: { frame, mode = "tab" | "window", name }

---------------------------------------------------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------------------------------------------------
-- A view of a later milestone registers itself: def = { label, order, build(frame) -> nil, search = bool }.
function Shell:RegisterView(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	def.id = id
	def.order = def.order or 100
	self.views[id] = def
	if self.content then self:Refresh() end
	return true
end

-- The text of a navigation button: the label and, when the view has a `badge` function that gives a number above 0, the number
-- in brackets (the Bank view: the requests waiting for an officer).
function Shell.NavLabel(view)
	local text = view.label or view.id
	if type(view.badge) == "function" then
		local ok, n = pcall(view.badge)
		if ok and type(n) == "number" and n > 0 then text = text .. " (" .. n .. ")" end
	end
	return text
end

-- Relabels the navigation buttons (a badge changed).
function Shell:UpdateBadges()
	local content = self.content
	if not content then return end
	for _, b in ipairs(content.nav.buttons) do
		local view = b.viewId and self.views[b.viewId]
		if view and b:IsShown() then b.label:SetText(Shell.NavLabel(view)) end
	end
end

function Shell:ViewList()
	local list = {}
	for _, v in pairs(self.views) do list[#list + 1] = v end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.id < b.id
	end)
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Sync state ("3 guildmates with Accord online · updated 2 min ago")
---------------------------------------------------------------------------------------------------------------------
function Shell.Ago(seconds)
	if type(seconds) ~= "number" or seconds < 60 then return L["AGO_NOW"] end
	if seconds < 3600 then return L["AGO_MINUTES"]:format(floor(seconds / 60)) end
	if seconds < 86400 then return L["AGO_HOURS"]:format(floor(seconds / 3600)) end
	return L["AGO_DAYS"]:format(floor(seconds / 86400))
end

function Shell.StatusText()
	local status = ns.Sync and ns.Sync.Status and ns.Sync:Status() or { peers = 0 }
	local peers = L["STATUS_PEERS"]:format(status.peers or 0)
	if not status.lastReceived then return peers .. " · " .. L["STATUS_NEVER"] end
	local now = ns.Compat and ns.Compat.ServerTime() or time()
	return peers .. " · " .. L["STATUS_UPDATED"]:format(Shell.Ago(now - status.lastReceived))
end

---------------------------------------------------------------------------------------------------------------------
-- The content frame
---------------------------------------------------------------------------------------------------------------------
local function buildNav(content)
	local nav = W.Frame(content, Shell.NAV_WIDTH, 10)
	nav:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -Shell.TOP_BAR)
	nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
	nav.buttons = {}
	content.nav = nav
end

local function navButton(nav, i)
	local b = nav.buttons[i]
	if b then return b end
	b = CreateFrame("Button", nil, nav)
	b:SetSize(Shell.NAV_WIDTH - 8, 24)
	b:SetPoint("TOPLEFT", nav, "TOPLEFT", 4, -4 - (i - 1) * 26)
	b.label = W.Text(b, "heading", nil, "LEFT")
	b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
	b.selected = b:CreateTexture(nil, "BACKGROUND")
	b.selected:SetAllPoints(b)
	b.selected:SetColorTexture(Skin.Color("navSelected", 0.25))
	b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
	b.highlight:SetAllPoints(b)
	b.highlight:SetColorTexture(1, 1, 1, 0.08)
	b:SetScript("OnClick", function(self) Shell:Select(self.viewId, true) end)
	nav.buttons[i] = b
	return b
end

local function buildTopBar(content)
	local bar = W.Frame(content, 10, Shell.TOP_BAR)
	bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	bar.search = W.SearchBox(bar, { width = 180, onChange = function(text) Shell:OnSearch(text) end })
	bar.search:SetPoint("LEFT", bar, "LEFT", 8, 0)
	bar.popOut = W.Button(bar, { text = L["POP_OUT"], width = 90, tooltip = { L["POP_OUT"], L["POP_OUT_TIP"] },
		onClick = function() Shell:PopOut() end })
	bar.popOut:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	bar.status = W.Text(bar, "small", nil, "RIGHT")
	bar.status:SetPoint("RIGHT", bar.popOut, "LEFT", -10, 0)
	content.bar = bar
end

local function buildBody(content)
	local body = W.Frame(content, 10, 10)
	body:SetPoint("TOPLEFT", content.nav, "TOPRIGHT", 4, 0)
	body:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
	content.body = body
	local empty = W.Frame(body, 10, 10)
	empty:SetAllPoints(body)
	empty.icon = empty:CreateTexture(nil, "ARTWORK")
	empty.icon:SetSize(56, 56)
	empty.icon:SetPoint("TOP", empty, "TOP", 0, -40)
	empty.icon:SetTexture(ns.Assets.logos.logo_64.path)
	empty.title = W.Text(empty, "title", "gold", "CENTER")
	empty.title:SetPoint("TOP", empty.icon, "BOTTOM", 0, -12)
	empty.title:SetText(L["EMPTY_TITLE"])
	empty.text = W.Text(empty, "body", nil, "CENTER")
	empty.text:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
	empty.text:SetWidth(380)
	empty.text:SetText(L["EMPTY_TEXT"])
	content.empty = empty
end

function Shell:Content()
	if self.content then return self.content end
	local content = CreateFrame("Frame", Shell.NAME, UIParent)
	content:Hide()
	W.Background(content, "panel", 0.92)
	buildTopBar(content)
	buildNav(content)
	buildBody(content)
	content:SetScript("OnShow", function() Shell:StartStatus() Shell:Refresh() end)
	content:SetScript("OnHide", function() Shell:StopStatus() end)
	self.content = content
	return content
end

---------------------------------------------------------------------------------------------------------------------
-- Refresh, selection, search
---------------------------------------------------------------------------------------------------------------------
function Shell:Refresh()
	local content = self.content
	if not content then return end
	local list = self:ViewList()
	local nav = content.nav
	for i, view in ipairs(list) do
		local b = navButton(nav, i)
		b.viewId = view.id
		b.label:SetText(Shell.NavLabel(view))
		b:Show()
	end
	for i = #list + 1, #nav.buttons do nav.buttons[i]:Hide() end
	nav:SetShown(#list > 0)
	if #list == 0 then
		self.selected = nil
		content.empty:Show()
	else
		if not (self.selected and self.views[self.selected]) then
			local last = ns.Config and ns.Config:Get("char.ui.lastView")
			self.selected = (last and self.views[last]) and last or list[1].id
		end
		content.empty:Hide()
		self:ShowSelected()
	end
	local searchable = false
	for _, v in ipairs(list) do if v.search then searchable = true end end
	content.bar.search:SetShown(searchable)
	content.bar.popOut:SetShown(self.host ~= nil and self.host.mode == "tab")
	self:UpdateStatus()
end

-- Draws a view for the first time. A view that raises while it is built (a game update changed an API, a bug of ours)
-- must not take the panel with it: the error goes to the game's error handler (and so to /accord debug), the view shows
-- a short text saying so, and the other views keep working. Selecting the view again tries to build it afresh.
local function buildView(content, view)
	local frame = W.Frame(content.body, 10, 10)
	frame:SetAllPoints(content.body)
	view.frame = frame
	local ok, err = xpcall(view.build, function(e)
		if geterrorhandler then pcall(geterrorhandler(), e) end
		return e
	end, frame)
	if ok then return true end
	view.failed = tostring(err)
	local title = W.Text(frame, "title", "red", "CENTER")
	title:SetPoint("TOP", frame, "TOP", 0, -60)
	title:SetText(L["VIEW_ERROR_TITLE"])
	local text = W.Text(frame, "body", nil, "CENTER")
	text:SetPoint("TOP", title, "BOTTOM", 0, -10)
	text:SetWidth(380)
	text:SetText(L["VIEW_ERROR_TEXT"])
	frame.errorTitle, frame.errorText = title, text
	return false
end

function Shell:ShowSelected()
	local content = self.content
	for i, b in ipairs(content.nav.buttons) do
		if b:IsShown() then b.selected:SetShown(b.viewId == self.selected) end
	end
	for id, view in pairs(self.views) do
		if id == self.selected then
			if not view.frame then buildView(content, view) end
			view.frame:Show()
		elseif view.frame then
			view.frame:Hide()
		end
	end
end

-- `retry` is true for a click on the navigation: a view whose build failed is then built afresh.
function Shell:Select(id, retry)
	local view = self.views[id]
	if not view then return false end
	if retry and view.failed and view.frame then
		view.frame:Hide()
		view.frame, view.failed = nil, nil
	end
	self.selected = id
	if ns.Config then ns.Config:Set("char.ui.lastView", id) end
	if self.content then self:ShowSelected() end
	return true
end

function Shell:OnSearch(text)
	local view = self.selected and self.views[self.selected]
	if view and type(view.onSearch) == "function" then view.onSearch(text) end
end

function Shell:UpdateStatus()
	if self.content then self.content.bar.status:SetText(Shell.StatusText()) end
end

function Shell:StartStatus()
	if self.statusTicker then return end
	self.statusTicker = ns.Compat and ns.Compat.NewTicker(Shell.STATUS_REFRESH, function() Shell:UpdateStatus() end)
end

function Shell:StopStatus()
	if self.statusTicker then self.statusTicker:Cancel() self.statusTicker = nil end
end

---------------------------------------------------------------------------------------------------------------------
-- Hosts: the guild tab panel and the standalone window
---------------------------------------------------------------------------------------------------------------------
-- Moves the content into `host` ({ frame, mode, name }) and shows it.
function Shell:Attach(host)
	local content = self:Content()
	if self.host and self.host ~= host and self.host.onLeave then self.host.onLeave() end
	self.host = host
	content:SetParent(host.frame)
	content:ClearAllPoints()
	content:SetAllPoints(host.frame)
	content:SetFrameLevel((host.frame:GetFrameLevel() or 1) + 1)
	content:Show()
	self:Refresh()
end

-- The host went away (its frame was hidden): the content hides with it.
function Shell:Detach(host)
	if self.host ~= host then return end
	self.host = nil
	if self.content then self.content:Hide() end
end

function Shell:IsShown()
	return self.content ~= nil and self.content:IsVisible() == true
end

local function inGuild()
	return ns.Role and ns.Role:InGuild()
end

-- /accord, the key binding and the AddOn Compartment: open or close the standalone window (SPEC-04 §3).
function Shell:Toggle()
	if not inGuild() then
		if ns.addon then ns.addon:Print(L["NOT_IN_GUILD"]) end
		return false
	end
	if ns.Window then return ns.Window:Toggle() end
	return false
end

-- /accord roster|professions|reputation|bank: open that view where the panel is, or in the standalone window.
function Shell:OpenView(id)
	if not inGuild() then
		if ns.addon then ns.addon:Print(L["NOT_IN_GUILD"]) end
		return false
	end
	if not self.views[id] then
		if ns.addon then ns.addon:Print(L["COMING_SOON"]) end
		return false
	end
	self.selected = id   -- before the window opens, so the first view built is this one
	if not self:IsShown() and ns.Window then ns.Window:Open() end
	return self:Select(id)
end

-- Pop out: from the guild window to the larger standalone window, on the same view.
function Shell:PopOut()
	if ns.GuildTab then ns.GuildTab:HidePanel() end
	if ns.Window then ns.Window:Open() end
end

-- The AddOn Compartment tooltip (Core/Init.lua adds the title).
function Shell.FillTooltip(tooltip)
	tooltip:AddLine(L["COMPARTMENT_HINT"], 1, 1, 1, true)
	if inGuild() then tooltip:AddLine(Shell.StatusText(), 0.6, 0.6, 0.6, true) end
	local waiting = ns.BankInbox and ns.BankInbox.PendingCount() or 0
	if waiting > 0 then tooltip:AddLine(L["BANKNOTE_WAITING"]:format(waiting), 1, 0.82, 0, true) end
end

if ns.addon then
	ns.addon.Shell = Shell
	if ns.Bus then
		local function update() Shell:UpdateStatus() end
		ns.Bus:On("SYNC_RECEIVED", update)
		ns.Bus:On("SYNC_HELLO", update)
		ns.Bus:On("GUILD_CHANGED", function(key)
			if not key then
				if ns.Window then ns.Window:Close() end
				if ns.GuildTab then ns.GuildTab:HidePanel() end
			end
		end)
	end
end

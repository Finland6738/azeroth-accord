-- Shell: the Accord panel and its tabs (SPEC-04 §2-§4, docs/specs/ui-style.md §3). Lua 5.1.
--
-- One content frame, shown in one host at a time: the panel of the Accord tab in the guild window (UI/GuildTab.lua) or
-- the standalone window (UI/Window.lua). The host draws what is around it (the window: its panel and title bar; the
-- guild window: a fill of the theme over Blizzard's content area). The content has
--   * the tab bar (ns.Widgets.Tabs, 44 pt, the 2 pt indicator under the active tab): one tab per registered view (Roster,
--     Professions, Reputation, Bank, Settings), in order; views of later milestones register themselves, so a view that
--     is not ready never shows; a view's `badge` function puts a count on its tab (the Bank: requests waiting);
--   * at the right of the tabs: the search box, while the selected view can search, and Pop out in the guild window;
--   * the body: the selected view, or a welcome text while no view exists;
--   * in the guild window only, a line under the body with the sync state (the window has it in its title bar).
-- Every colour is a token of UI/Theme.lua, so Theme.Apply repaints the shell without /reload. The views draw with
-- the widget kit: each gets a plain frame that fills the body.
-- The panel holds no protected action, so it opens and closes in combat too (GT-06).
local ADDON_NAME, ns = ...
ns = ns or {}
local Shell = {}
ns.Shell, ns.modules = Shell, ns.modules or {}
ns.modules.Shell = Shell

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, pairs, ipairs, tostring, floor, pcall = type, pairs, ipairs, tostring, math.floor, pcall

Shell.NAME = "AzerothAccordShell"
Shell.PAD = 16            -- between the edge of the host and the tabs, the body
Shell.TOP = 4             -- above the tab bar
Shell.TAB_BAR = 44        -- the height of Widgets.Tabs
Shell.GAP = 12            -- between the tab bar and the body
Shell.FOOTER = 24         -- the sync-state line of the guild window
Shell.SEARCH_WIDTH = { window = 200, tab = 150 }
Shell.STATUS_REFRESH = 30

Shell.views = {}        -- id -> { id, label, order, build(frame), frame, search, onSearch(text), badge() }
Shell.host = nil        -- the host the content is in now: { frame, mode = "tab" | "window", name, onLeave, onStatus }

---------------------------------------------------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------------------------------------------------
-- A view registers itself: def = { label, order, build(frame) -> nil, search = bool, onSearch(text), badge() -> n }.
function Shell:RegisterView(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	def.id = id
	def.order = def.order or 100
	self.views[id] = def
	if self.content then self:Refresh() end
	return true
end

-- The count on a view's tab: the number its `badge` function gives when above 0 ("99+" from 100), else nil (no badge).
function Shell.BadgeText(view)
	if type(view) ~= "table" or type(view.badge) ~= "function" then return nil end
	local ok, n = pcall(view.badge)
	if not ok or type(n) ~= "number" or n <= 0 then return nil end
	return n > 99 and "99+" or tostring(floor(n))
end

-- Puts the counts on the tabs again (a badge changed: Data/BankInbox.lua calls this).
function Shell:UpdateBadges()
	local tabs = self.content and self.content.tabs
	if not tabs then return end
	for id, view in pairs(self.views) do
		if tabs.buttons[id] then tabs:SetBadge(id, Shell.BadgeText(view), "accent") end
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
function Shell.Ago(seconds) return ns.Provenance.AgeText(seconds) end   -- one scale for every age (SPEC-11 §1.2)

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
local function buildBar(content)
	local bar = CreateFrame("Frame", nil, content)
	bar:SetHeight(Shell.TAB_BAR)
	bar:SetPoint("TOPLEFT", content, "TOPLEFT", Shell.PAD, -Shell.TOP)
	bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Shell.PAD, -Shell.TOP)
	-- the search box: the Widgets field is `searchField`; `search` is its edit box, where the views and the tests type
	bar.searchField = Widgets.EditBox(bar, { width = Shell.SEARCH_WIDTH.window, height = 28, placeholder = L["SEARCH_PLACEHOLDER"],
		onChange = function(text, user) if user then Shell:OnSearch(text or "") end end })
	bar.search = bar.searchField.edit
	bar.popOut = Widgets.Button(bar, { text = L["POP_OUT"], style = "secondary", height = 28, onClick = function() Shell:PopOut() end })
	bar.popOut:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	if Widgets.Tooltip then Widgets.Tooltip.Attach(bar.popOut, { L["POP_OUT"], L["POP_OUT_TIP"] }, "BOTTOM") end
	content.bar = bar
end

local function buildFooter(content)
	local footer = CreateFrame("Frame", nil, content)
	footer:SetHeight(Shell.FOOTER)
	footer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", Shell.PAD, 0)
	footer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Shell.PAD, 0)
	footer.line = footer:CreateTexture(nil, "BORDER")
	Theme.Fill(footer.line, "border-subtle")
	footer.line:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
	footer.line:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
	footer.line:SetHeight(Theme.Px(1))
	content.status = Theme.NewText(footer, "MonoSmall", "text-3")
	content.status:SetPoint("RIGHT", footer, "RIGHT", 0, -1)
	content.status:SetJustifyH("RIGHT")
	content.footer = footer
end

local function buildBody(content)
	local body = CreateFrame("Frame", nil, content)
	content.body = body
	local empty = CreateFrame("Frame", nil, body)
	empty:SetAllPoints(body)
	empty.icon = empty:CreateTexture(nil, "ARTWORK")
	empty.icon:SetSize(56, 56)
	empty.icon:SetPoint("TOP", empty, "TOP", 0, -40)
	empty.icon:SetTexture(ns.Assets.logos.logo_64.path)
	empty.title = Theme.NewText(empty, "H2", "text-1")
	empty.title:SetJustifyH("CENTER")
	empty.title:SetPoint("TOP", empty.icon, "BOTTOM", 0, -12)
	empty.title:SetText(L["EMPTY_TITLE"])
	empty.text = Theme.NewText(empty, "Body", "text-2")
	empty.text:SetJustifyH("CENTER")
	empty.text:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
	empty.text:SetWidth(380)
	empty.text:SetText(L["EMPTY_TEXT"])
	content.empty = empty
end

function Shell:Content()
	if self.content then return self.content end
	local content = CreateFrame("Frame", Shell.NAME, UIParent)
	content:Hide()
	buildBar(content)
	buildFooter(content)
	buildBody(content)
	content:SetScript("OnShow", function() Shell:StartStatus() Shell:Refresh() end)
	content:SetScript("OnHide", function() Shell:StopStatus() end)
	self.content = content
	return content
end

-- The tab bar for the views in `list`. Widgets.Tabs takes its tabs when it is made, so a view that registers later (or a
-- changed label) makes a new bar; the old one is hidden. A click on a tab goes through Shell:Select with `retry`, so a
-- click on the tab of a view that failed builds it again (the bar itself does not call back for the active tab).
local function tabsKey(list)
	local parts = {}
	for i, v in ipairs(list) do parts[i] = v.id .. "=" .. tostring(v.label or v.id) end
	return table.concat(parts, "\n")
end

local function buildTabs(content, list)
	local key = tabsKey(list)
	if content.tabs and content.tabsKey == key then return content.tabs end
	if content.tabs then content.tabs:Hide() end
	local defs = {}
	for i, v in ipairs(list) do defs[i] = { id = v.id, text = v.label or v.id } end
	local tabs = Widgets.Tabs(content.bar, defs)
	tabs:SetPoint("BOTTOMLEFT", content.bar, "BOTTOMLEFT", 0, 0)
	tabs:SetPoint("BOTTOMRIGHT", content.bar, "BOTTOMRIGHT", 0, 0)
	for id, b in pairs(tabs.buttons) do
		b:HookScript("OnClick", function() Shell:Select(id, true) end)
	end
	content.tabs, content.tabsKey = tabs, key
	-- the search box and Pop out lie over the right end of the bar (its line runs under them)
	local level = (tabs:GetFrameLevel() or 1) + 2
	content.bar.searchField:SetFrameLevel(level)
	content.bar.popOut:SetFrameLevel(level)
	return tabs
end

-- What depends on the host: Pop out and the footer only in the guild window, the width of the search box, the body.
local function layout(content, mode)
	local bar, tab = content.bar, mode == "tab"
	bar.popOut:SetShown(tab)
	local field = bar.searchField
	field:SetWidth(Shell.SEARCH_WIDTH[tab and "tab" or "window"])
	field:ClearAllPoints()
	if tab then field:SetPoint("RIGHT", bar.popOut, "LEFT", -8, 0)
	else field:SetPoint("RIGHT", bar, "RIGHT", 0, 0) end
	content.footer:SetShown(tab)
	local body = content.body
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -Shell.GAP)
	if tab then body:SetPoint("BOTTOMRIGHT", content.footer, "TOPRIGHT", 0, 4)
	else body:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Shell.PAD, Shell.PAD) end
	content.mode = tab and "tab" or "window"
end

---------------------------------------------------------------------------------------------------------------------
-- Refresh, selection, search
---------------------------------------------------------------------------------------------------------------------
function Shell:Refresh()
	local content = self.content
	if not content then return end
	layout(content, self.host and self.host.mode or "window")
	local list = self:ViewList()
	if #list == 0 then
		if content.tabs then content.tabs:Hide() end
		self.selected = nil
		content.empty:Show()
	else
		local tabs = buildTabs(content, list)
		tabs:Show()
		if not (self.selected and self.views[self.selected]) then
			local last = ns.Config and ns.Config:Get("char.ui.lastView")
			self.selected = (last and self.views[last]) and last or list[1].id
		end
		content.empty:Hide()
		self:UpdateBadges()
		self:ShowSelected()
	end
	self:UpdateSearch()
	self:UpdateStatus()
end

-- Draws a view for the first time. A view that raises while it is built (a game update changed an API, a bug of ours)
-- must not take the panel with it: the error goes to the game's error handler (and so to /accord debug), the view shows
-- a short text saying so, and the other views keep working. Clicking its tab again tries to build it afresh.
local function buildView(content, view)
	local frame = CreateFrame("Frame", nil, content.body)
	frame:SetAllPoints(content.body)
	view.frame = frame
	local ok, err = xpcall(view.build, function(e)
		if geterrorhandler then pcall(geterrorhandler(), e) end
		return e
	end, frame)
	if ok then return true end
	view.failed = tostring(err)
	local title = Theme.NewText(frame, "H2", "err")
	title:SetJustifyH("CENTER")
	title:SetPoint("TOP", frame, "TOP", 0, -60)
	title:SetText(L["VIEW_ERROR_TITLE"])
	local text = Theme.NewText(frame, "Body", "text-2")
	text:SetJustifyH("CENTER")
	text:SetPoint("TOP", title, "BOTTOM", 0, -10)
	text:SetWidth(380)
	text:SetText(L["VIEW_ERROR_TEXT"])
	frame.errorTitle, frame.errorText = title, text
	return false
end

function Shell:ShowSelected()
	local content = self.content
	if content.tabs and self.selected then content.tabs:Select(self.selected) end
	for id, view in pairs(self.views) do
		if id == self.selected then
			if not view.frame then buildView(content, view) end
			view.frame:Show()
		elseif view.frame then
			view.frame:Hide()
		end
	end
	self:UpdateSearch()
end

-- `retry` is true for a click on a tab: a view whose build failed is then built afresh.
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

-- The search box shows while the selected view can search; what is typed goes to that view.
function Shell:UpdateSearch()
	local content = self.content
	if not content then return end
	local view = self.selected and self.views[self.selected]
	content.bar.searchField:SetShown(view ~= nil and view.search == true)
end

function Shell:OnSearch(text)
	local view = self.selected and self.views[self.selected]
	if view and type(view.onSearch) == "function" then view.onSearch(text) end
end

-- The sync state: in the footer line of the guild window, and handed to the host (the window's title bar).
function Shell:UpdateStatus()
	local content = self.content
	if not content then return end
	local text = Shell.StatusText()
	content.status:SetText(text)
	if self.host and type(self.host.onStatus) == "function" then self.host.onStatus(text) end
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
-- Moves the content into `host` ({ frame, mode, name, onLeave, onStatus }) and shows it. The host it leaves is told
-- (onLeave): the guild panel unchecks its tab, the window closes.
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

-- /accord roster|professions|reputation|bank|settings: open that view where the panel is, or in the standalone window.
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

-- Pop in: from the standalone window back into the guild window. Only while the guild window is open on the guild (the
-- Accord tab shows): the addon never opens Blizzard's window itself (ADR 0003).
function Shell:CanPopIn()
	return ns.GuildTab ~= nil and type(ns.GuildTab.CanHost) == "function" and ns.GuildTab:CanHost() == true
end

function Shell:PopIn()
	if not self:CanPopIn() then return false end
	return ns.GuildTab:ShowPanel()
end

-- The AddOn Compartment tooltip (Core/Init.lua adds the title).
function Shell.FillTooltip(tooltip)
	local Theme = ns.Theme   -- the game's tooltip is Blizzard's dark frame: the game's own colours (Theme.GameColor)
	local r, g, b = Theme.GameColor("text")
	tooltip:AddLine(L["COMPARTMENT_HINT"], r, g, b, true)
	if inGuild() then
		r, g, b = Theme.GameColor("muted")
		tooltip:AddLine(Shell.StatusText(), r, g, b, true)
	end
	local waiting = ns.BankInbox and ns.BankInbox.PendingCount() or 0
	if waiting > 0 then
		r, g, b = Theme.GameColor("gold")
		tooltip:AddLine(L["BANKNOTE_WAITING"]:format(waiting), r, g, b, true)
	end
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

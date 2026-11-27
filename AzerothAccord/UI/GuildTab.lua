-- GuildTab: the Accord tab in Blizzard's guild window, CommunitiesFrame (SPEC-04 §1, ADR 0003). Lua 5.1.
--
--   GT-01  our own button, a child of CommunitiesFrame, under the LOWEST visible Blizzard tab as the window draws them, at
--          the same distance as theirs (measured; on Forever the tabs are not stacked in the order of their keys, and
--          a tab placed by key order covered the fourth one: owner, 2026-11-26), with the game's tab frame
--          (CommunitiesFrameTabTemplate) around the Accord logo and the tooltip "Azeroth Accord";
--   GT-02  shown only while the selected community is the guild and the window is not minimized;
--   GT-03  a click opens the larger Accord window where the guild window was and closes the guild window (owner,
--          2026-11-26: the guild window is too small for Accord's tables); with the setting "Open Accord inside the guild
--          window" (account.settings.guildPanel) it shows the Accord panel over the window instead and checks our tab; a
--          click on a Blizzard tab hides the panel (observed with HookScript), as do a change of display mode or club and
--          closing the window;
--   GT-04  never calls SetDisplayMode and never replaces a Blizzard function: only hooksecurefunc and HookScript, and
--          only on Blizzard frames; everything it changes is a frame it created;
--   GT-05  if CommunitiesFrame has none of the expected tabs, no tab is made: the standalone window stays, and the
--          feature "guildTab" says why in /accord debug;
--   GT-06  the panel holds no protected action: it opens and closes in combat too.
--   GT-07  while the panel is open the window around it is in the theme too (M6.18, UI/GuildSkin.lua): Blizzard's chrome is made
--          transparent and put back afterwards, a themed frame, the guild's name, the cross and the tab tiles are drawn.
-- The panel is a frame of the addon over the content area, filled with the theme's background (docs/specs/ui-style.md §3):
-- the Accord content with its tab bar and no title bar. Apart from GT-07 (alpha only), theme colours go only on the addon's
-- frames, never on Blizzard's.
-- Blizzard_Communities loads on demand: the tab is attached when it loads (ADDON_LOADED) or at login if it already is.
local ADDON_NAME, ns = ...
ns = ns or {}
local GuildTab = {}
ns.GuildTab, ns.modules = GuildTab, ns.modules or {}
ns.modules.GuildTab = GuildTab

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pcall, tostring = type, ipairs, pcall, tostring

GuildTab.TAB_KEYS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
-- The tab has the game's tab frame with the Accord logo inside (owner, 2026-11-26; M6.18 had the addon's own tile, which
-- stays as the fallback when the client does not know the template).
GuildTab.TEMPLATES = { "CommunitiesFrameTabTemplate", "" }
GuildTab.TAB_NAME, GuildTab.PANEL_NAME = "AzerothAccordGuildTab", "AzerothAccordGuildPanel"
GuildTab.GAP = 20                -- vertical space between our tab and the last Blizzard tab, like theirs
GuildTab.LEVEL_ABOVE = 60        -- the panel sits this many frame levels above the guild window (above its nested frames)

local function frame() return _G.CommunitiesFrame end

local function setFeature(state, detail)
	if ns.Compat and ns.Compat.SetFeature then ns.Compat:SetFeature("guildTab", state, detail) end
end

local function call(obj, method, ...)
	if type(obj) ~= "table" or type(obj[method]) ~= "function" then return false, nil end
	return pcall(obj[method], obj, ...)
end

-- The Blizzard side tabs that exist, in order.
function GuildTab.BlizzardTabs(cf)
	local tabs = {}
	for _, key in ipairs(GuildTab.TAB_KEYS) do
		local tab = cf and cf[key]
		if type(tab) == "table" and type(tab.HookScript) == "function" then tabs[#tabs + 1] = tab end
	end
	return tabs
end

-- The visible Blizzard side tabs: the known keys, plus any other check button of the window that stands outside its right
-- edge (a side tab this client has and the keys do not name). Never our own tab.
local function visibleTabs(cf)
	local list, seen = {}, {}
	local function add(tab)
		if tab and not seen[tab] and tab ~= GuildTab.tab then
			local ok, shown = call(tab, "IsShown")
			if ok and shown then list[#list + 1] = tab end
			seen[tab] = true
		end
	end
	for _, tab in ipairs(GuildTab.BlizzardTabs(cf)) do add(tab) end
	local okR, right = call(cf, "GetRight")
	if okR and type(right) == "number" and type(cf.GetChildren) == "function" then
		for _, child in ipairs({ cf:GetChildren() }) do
			local okT, kind = call(child, "GetObjectType")
			local okL, left = call(child, "GetLeft")
			if okT and kind == "CheckButton" and okL and type(left) == "number" and left >= right - 4 then add(child) end
		end
	end
	return list
end

local function edges(tab)
	local okT, top = call(tab, "GetTop")
	local okB, bottom = call(tab, "GetBottom")
	if okT and okB and type(top) == "number" and type(bottom) == "number" then return top, bottom end
end

-- The lowest visible tab and the space Blizzard leaves between its tabs. With real positions (the window is drawn) the
-- lowest is the one with the smallest bottom and the gap is the one measured between two neighbours; without them (not
-- drawn yet, or every tab reports the same place) the last visible one in key order and GAP.
function GuildTab.Lowest(cf)
	local tabs = visibleTabs(cf)
	if #tabs == 0 then return nil, GuildTab.GAP, "none" end
	local measured, distinct = {}, false
	for _, tab in ipairs(tabs) do
		local top, bottom = edges(tab)
		if not top then measured = nil break end
		measured[#measured + 1] = { tab = tab, top = top, bottom = bottom }
		if measured[1] and bottom ~= measured[1].bottom then distinct = true end
	end
	if not (measured and distinct) then return tabs[#tabs], GuildTab.GAP, "order" end
	table.sort(measured, function(a, b) return a.bottom > b.bottom end)   -- top to bottom
	local gap
	for i = 2, #measured do
		local d = measured[i - 1].bottom - measured[i].top
		if d >= 0 and d < 80 then gap = gap and math.min(gap, d) or d end
	end
	return measured[#measured].tab, gap or GuildTab.GAP, "measured"
end

function GuildTab:Anchor()
	local tab, cf = self.tab, frame()
	if not (tab and cf) then return end
	local last, gap, how = GuildTab.Lowest(cf)
	self.anchorHow = how
	tab:ClearAllPoints()
	if last then tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -gap)
	else tab:SetPoint("TOPLEFT", cf, "TOPRIGHT", 0, -36) end
end

-- Positions are known only once the window is drawn: anchor now, and again on the next frame.
function GuildTab:AnchorSoon()
	self:Anchor()
	if ns.Compat and ns.Compat.After then ns.Compat.After(0, function() GuildTab:Anchor() end) end
end

local function guildSelected(cf)
	local guildId = ns.Compat and ns.Compat.Guild.ClubId()
	local ok, selected = call(cf, "GetSelectedClubId")
	if not ok or selected == nil or guildId == nil then return guildId ~= nil end
	return selected == guildId
end

local function minimized(cf)
	local modes = _G.COMMUNITIES_FRAME_DISPLAY_MODES
	local ok, mode = call(cf, "GetDisplayMode")
	return ok and type(modes) == "table" and modes.MINIMIZED ~= nil and mode == modes.MINIMIZED
end

-- The standalone window offers Pop in only while the guild window can take the panel (UI/Window.lua).
local function updatePopIn()
	if ns.Window and ns.Window.UpdatePopIn then ns.Window:UpdatePopIn() end
end

-- True while the panel can open here: the guild window is open on the guild and the Accord tab shows.
function GuildTab:CanHost()
	local cf = frame()
	if not (self.tab and self.panel and cf) then return false end
	local ok, visible = call(self.tab, "IsVisible")
	return ok and visible == true
end

-- GT-02: shown only for the guild, not minimized, and only while the character has a guild.
function GuildTab:UpdateVisibility()
	local cf = self.tab and frame()
	if not cf then return end
	local show = ns.Role and ns.Role:InGuild() and guildSelected(cf) and not minimized(cf)
	self.tab:SetShown(show and true or false)
	if not show then self:HidePanel() end
	updatePopIn()
end

-- The Accord tab's click: the Accord window (default) or the panel inside the guild window (the setting).
function GuildTab.UsesPanel()
	return ns.Config ~= nil and ns.Config.db ~= nil and ns.Config:Get("account.settings.guildPanel") == true
end

function GuildTab:OnTabClick()
	if GuildTab.UsesPanel() or not ns.Window then return self:ShowPanel() end
	return self:OpenWindow()
end

-- Opens the Accord window where the guild window is (unless the player already placed it: a saved place wins) and closes
-- the guild window with Blizzard's own HideUIPanel, as its close button does.
function GuildTab:OpenWindow()
	local cf = frame()
	if self.tab then self.tab:SetChecked(false) end
	self:HidePanel()
	local f = ns.Window:Frame()
	local saved = ns.Config and ns.Config.db and ns.Config:Get("char.ui.windowPos")
	if cf and not saved and not f:IsShown() then
		local okL, left = call(cf, "GetLeft")
		local okT, top = call(cf, "GetTop")
		local okS, scale = call(cf, "GetEffectiveScale")
		local ui = _G.UIParent
		local uiScale = ui and ui.GetEffectiveScale and ui:GetEffectiveScale() or 1
		if okL and okT and type(left) == "number" and type(top) == "number" then
			local k = (okS and type(scale) == "number" and scale or 1) / (uiScale ~= 0 and uiScale or 1)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", ui, "BOTTOMLEFT", left * k, top * k)
		end
	end
	if cf and type(_G.HideUIPanel) == "function" then pcall(_G.HideUIPanel, cf) end
	ns.Window:Open()
	return true
end

function GuildTab:ShowPanel()
	if not self.panel then return false end
	self.panel:Show()
	self.tab:SetChecked(true)
	pcall(ns.GuildSkin.Apply, frame(), GuildTab.SkinnedTabs(), self.tab)   -- the window in the theme (M6.18)
	ns.Shell:Attach(self.host)
	return true
end

function GuildTab:HidePanel()
	if self.tab then self.tab:SetChecked(false) end
	if self.panel and self.panel:IsShown() then self.panel:Hide() end
	if ns.GuildSkin.IsActive() then pcall(ns.GuildSkin.Revert, GuildTab.SkinnedTabs()) end
end

-- The tabs the theme draws as tiles while the panel is open: Blizzard's, and ours too when it has the game's frame.
function GuildTab.SkinnedTabs()
	local tabs = GuildTab.BlizzardTabs(frame())
	if GuildTab.tab and GuildTab.template ~= "" then tabs[#tabs + 1] = GuildTab.tab end
	return tabs
end

function GuildTab:IsPanelShown() return self.panel ~= nil and self.panel:IsShown() end

-- The count of requests waiting for an officer (BANK-23): the badge of the widget kit (error colours: a thing to do) on
-- the tab; nothing for 0. The badge is the addon's own frame on the addon's own tab.
function GuildTab:SetBadge(count)
	self.badgeCount = count or 0
	local tab = self.tab
	if not tab then return end
	if not tab.badge then
		tab.badge = ns.Widgets.Badge(tab, "", "err")
		tab.badge:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 4, 4)
		tab.badge:SetFrameLevel((tab:GetFrameLevel() or 1) + 2)
	end
	local n = self.badgeCount
	tab.badge:SetBadge(n > 99 and "99+" or tostring(n))
	tab.badge:SetShown(n > 0)
end

-- CreateFrame with the first template the client accepts (CreateFrame raises on an unknown one: each is tried under pcall).
local function createTab(cf)
	for _, template in ipairs(GuildTab.TEMPLATES) do
		local ok, tab = pcall(CreateFrame, "CheckButton", GuildTab.TAB_NAME, cf, template ~= "" and template or nil)
		if ok and tab then return tab, template end
	end
	return CreateFrame("CheckButton", GuildTab.TAB_NAME, cf), ""
end

local function buildTab(cf)
	local tab, template = createTab(cf)
	GuildTab.template = template
	local okW, width = call(tab, "GetWidth")
	if template == "" or not (okW and type(width) == "number" and width > 0) then tab:SetSize(36, 36) end
	local icon = tab.Icon or tab.icon
	if not (icon and icon.SetTexture) then
		icon = tab:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, -4)
		icon:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 4)
		if template ~= "" then tab.Icon = icon end   -- the skin keeps a tab's Icon while it hides the rest of its art
	end
	if template == "" then
		-- no game frame: the logo in a circle on the addon's own tile (M6.18)
		if icon.SetMaskTexture then icon:SetMaskTexture(ns.Assets.textures.circle.path) end
		ns.GuildSkin.TileFor(cf, tab, true, true)
	end
	icon:SetTexture(ns.Assets.logos.logo_64.path)   -- the addon's logo (SPEC-10 Q2), inside the game's frame
	tab.accordIcon = icon
	tab.tooltip = L["ADDON_TITLE"]
	Widgets.Tooltip.Attach(tab, function() return { L["ADDON_TITLE"], L["TAB_TOOLTIP"] } end, "RIGHT")
	tab:SetScript("OnClick", function() GuildTab:OnTabClick() end)   -- a second click keeps the panel (like Blizzard's tabs)
	return tab
end

local function buildPanel(cf)
	local panel = CreateFrame("Frame", GuildTab.PANEL_NAME, cf)
	local inset = cf.Inset or cf.InsetFrame
	local list = cf.CommunitiesList
	if type(inset) == "table" and type(inset.GetObjectType) == "function" then
		-- the whole inside of the window, the list of communities too: nothing of Blizzard's shows through the panel
		if type(list) == "table" and type(list.GetObjectType) == "function" then
			panel:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
			panel:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
		else
			panel:SetAllPoints(inset)
		end
	else
		panel:SetPoint("TOPLEFT", cf, "TOPLEFT", 8, -64)
		panel:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -8, 8)
	end
	panel:SetFrameLevel((cf:GetFrameLevel() or 1) + GuildTab.LEVEL_ABOVE)
	panel:EnableMouse(true)   -- clicks on the panel do not fall through to the Blizzard content under it
	if panel.SetClipsChildren then panel:SetClipsChildren(true) end   -- a wide table never spills out of the window
	panel.fill = panel:CreateTexture(nil, "BACKGROUND")
	panel.fill:SetAllPoints(panel)
	Theme.Fill(panel.fill, "bg")   -- square: the corners of Blizzard's area stay covered
	panel:Hide()
	GuildTab.host = { frame = panel, mode = "tab", name = "guild window", onLeave = function() GuildTab:HidePanel() end }
	panel:SetScript("OnHide", function() ns.Shell:Detach(GuildTab.host) end)
	return panel
end

-- The hooks: observe Blizzard, never change it (GT-03, GT-04).
local function hook(cf)
	for _, tab in ipairs(GuildTab.BlizzardTabs(cf)) do
		tab:HookScript("OnClick", function() GuildTab:HidePanel() end)
		tab:HookScript("OnShow", function() GuildTab:AnchorSoon() end)
		tab:HookScript("OnHide", function() GuildTab:AnchorSoon() end)
	end
	if type(cf.SetDisplayMode) == "function" then
		hooksecurefunc(cf, "SetDisplayMode", function() GuildTab:HidePanel() GuildTab:UpdateVisibility() end)
	end
	if type(cf.SelectClub) == "function" then
		hooksecurefunc(cf, "SelectClub", function() GuildTab:UpdateVisibility() end)
	end
	cf:HookScript("OnShow", function() GuildTab:AnchorSoon() GuildTab:UpdateVisibility() end)
	cf:HookScript("OnHide", function() GuildTab:HidePanel() updatePopIn() end)
end

-- Creates the tab and the panel once CommunitiesFrame exists. Returns true when the tab is there.
function GuildTab:Attach()
	if self.tab then return true end
	local cf = frame()
	if type(cf) ~= "table" or type(cf.HookScript) ~= "function" then
		setFeature("unknown", "guild window not loaded yet")
		return false
	end
	if #GuildTab.BlizzardTabs(cf) == 0 then
		setFeature("missing", "the guild window has none of the expected tabs: use /accord (standalone window)")
		return false
	end
	local ok, err = pcall(function()
		self.tab = buildTab(cf)
		self.panel = buildPanel(cf)
		hook(cf)
	end)
	if not ok then
		self.tab, self.panel = nil, nil
		setFeature("missing", "could not attach: " .. tostring(err):sub(1, 80))
		if geterrorhandler then geterrorhandler()(err) end
		return false
	end
	self:AnchorSoon()
	self:UpdateVisibility()
	if self.badgeCount then self:SetBadge(self.badgeCount) end
	setFeature("available", "attached with template " .. (GuildTab.template ~= "" and GuildTab.template or "none"))
	return true
end

function GuildTab:DebugLines()
	local lines = { ("Guild tab: %s%s"):format(self.tab and "attached" or "not attached",
		self.tab and (", " .. (self.tab:IsShown() and "visible" or "hidden") .. (self:IsPanelShown() and ", panel open" or "")) or "") }
	local cf = frame()
	if self.tab and cf then
		-- where each side tab is: the owner reads these lines in game when the tab is not where it should be
		local parts = {}
		for _, tab in ipairs(visibleTabs(cf)) do
			local top, bottom = edges(tab)
			local key = "?"
			for _, k in ipairs(GuildTab.TAB_KEYS) do if cf[k] == tab then key = k end end
			parts[#parts + 1] = top and ("%s %.0f-%.0f"):format(key, top, bottom) or (key .. " not drawn")
		end
		local last, gap = GuildTab.Lowest(cf)
		lines[#lines + 1] = ("  side tabs: %s; under %s, gap %.0f (%s); template %s"):format(table.concat(parts, ", "),
			last and (function() for _, k in ipairs(GuildTab.TAB_KEYS) do if cf[k] == last then return k end end return "another tab" end)() or "none",
			gap, self.anchorHow or "?", GuildTab.template ~= "" and GuildTab.template or "none")
	end
	return lines
end

if ns.addon then
	ns.addon.GuildTab = GuildTab
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Guild tab", function() return GuildTab:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(GuildTab)
	GuildTab:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_Communities" then GuildTab:Attach() end
	end)
	if ns.Bus then
		ns.Bus:On("ROLE_CHANGED", function() GuildTab:UpdateVisibility() end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
			if loaded then GuildTab:Attach() end
		end)
	end
end

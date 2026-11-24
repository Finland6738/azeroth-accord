-- GuildTab: the Accord tab in Blizzard's guild window, CommunitiesFrame (SPEC-04 §1, ADR 0003). Lua 5.1.
--
--   GT-01  our own button, a child of CommunitiesFrame, under the last visible Blizzard tab, a plain button in the addon's
--          look (a themed tile, UI/GuildSkin.lua) and the tooltip "Azeroth Accord";
--   GT-02  shown only while the selected community is the guild and the window is not minimized;
--   GT-03  a click shows the Accord panel over the content area and checks our tab; a click on a Blizzard tab hides the
--          panel (observed with HookScript), as do a change of display mode or club and closing the window;
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
-- The tab is a plain button: its look is the addon's own tile (UI/GuildSkin.lua), not Blizzard's tab template (M6.18).
GuildTab.TEMPLATES = { "" }
GuildTab.TAB_NAME, GuildTab.PANEL_NAME = "AzerothAccordGuildTab", "AzerothAccordGuildPanel"
GuildTab.GAP = 20                -- vertical space between our tab and the last Blizzard tab, like theirs
GuildTab.LEVEL_ABOVE = 20        -- the panel sits this many frame levels above the guild window

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

-- The lowest visible Blizzard tab, or nil. Blizzard stacks its tabs in this order, so the last visible one in the list
-- is the lowest (positions are not read: they are not known before the window is drawn).
local function lastVisibleTab(cf)
	local last
	for _, tab in ipairs(GuildTab.BlizzardTabs(cf)) do
		local ok, shown = call(tab, "IsShown")
		if ok and shown then last = tab end
	end
	return last
end

function GuildTab:Anchor()
	local tab, cf = self.tab, frame()
	if not (tab and cf) then return end
	local last = lastVisibleTab(cf)
	tab:ClearAllPoints()
	if last then tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -GuildTab.GAP)
	else tab:SetPoint("TOPLEFT", cf, "TOPRIGHT", 0, -36) end
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

function GuildTab:ShowPanel()
	if not self.panel then return false end
	self.panel:Show()
	self.tab:SetChecked(true)
	pcall(ns.GuildSkin.Apply, frame(), GuildTab.BlizzardTabs(frame()), self.tab)   -- the window in the theme (M6.18)
	ns.Shell:Attach(self.host)
	return true
end

function GuildTab:HidePanel()
	if self.tab then self.tab:SetChecked(false) end
	if self.panel and self.panel:IsShown() then self.panel:Hide() end
	if ns.GuildSkin.IsActive() then pcall(ns.GuildSkin.Revert, GuildTab.BlizzardTabs(frame())) end
end

function GuildTab:IsPanelShown() return self.panel ~= nil and self.panel:IsShown() end

-- The count of requests waiting for an officer (BANK-23): a small round mark in the theme's accent with the number on
-- the tab; nothing for 0. The mark is the addon's own texture on the addon's own tab.
function GuildTab:SetBadge(count)
	self.badgeCount = count or 0
	local tab = self.tab
	if not tab then return end
	if not tab.badge then
		tab.badgeBg = tab:CreateTexture(nil, "OVERLAY")
		tab.badgeBg:SetTexture(ns.Assets.textures.circle.path)
		tab.badgeBg:SetSize(18, 18)
		tab.badgeBg:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 4, 4)
		Theme.Tint(tab.badgeBg, "accent")
		tab.badge = Theme.NewText(tab, "Th", "on-accent", "OVERLAY")
		tab.badge:SetJustifyH("CENTER")
		tab.badge:SetPoint("CENTER", tab.badgeBg, "CENTER", 0, 0)
	end
	local n = self.badgeCount
	tab.badge:SetText(n > 99 and "99+" or tostring(n))
	tab.badge:SetShown(n > 0)
	tab.badgeBg:SetShown(n > 0)
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
	tab:SetSize(36, 36)
	local icon = tab.Icon or tab.icon
	if not (icon and icon.SetTexture) then
		icon = tab:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, -4)
		icon:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 4)
	end
	icon:SetTexture(ns.Assets.logos.logo_64.path)   -- the addon's logo (SPEC-10 Q2)
	if icon.SetMaskTexture then icon:SetMaskTexture(ns.Assets.textures.circle.path) end
	ns.GuildSkin.TileFor(cf, tab, true)   -- the tab's themed tile: always, it is the addon's own button
	tab.accordIcon = icon
	tab.tooltip = L["ADDON_TITLE"]
	Widgets.Tooltip.Attach(tab, function() return { L["ADDON_TITLE"], L["TAB_TOOLTIP"] } end, "RIGHT")
	tab:SetScript("OnClick", function() GuildTab:ShowPanel() end)   -- a second click keeps the panel (like Blizzard's tabs)
	return tab
end

local function buildPanel(cf)
	local panel = CreateFrame("Frame", GuildTab.PANEL_NAME, cf)
	local inset = cf.Inset or cf.InsetFrame
	if type(inset) == "table" and type(inset.GetObjectType) == "function" then
		panel:SetAllPoints(inset)
	else
		panel:SetPoint("TOPLEFT", cf, "TOPLEFT", 8, -64)
		panel:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -8, 8)
	end
	panel:SetFrameLevel((cf:GetFrameLevel() or 1) + GuildTab.LEVEL_ABOVE)
	panel:EnableMouse(true)   -- clicks on the panel do not fall through to the Blizzard content under it
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
		tab:HookScript("OnShow", function() GuildTab:Anchor() end)
		tab:HookScript("OnHide", function() GuildTab:Anchor() end)
	end
	if type(cf.SetDisplayMode) == "function" then
		hooksecurefunc(cf, "SetDisplayMode", function() GuildTab:HidePanel() GuildTab:UpdateVisibility() end)
	end
	if type(cf.SelectClub) == "function" then
		hooksecurefunc(cf, "SelectClub", function() GuildTab:UpdateVisibility() end)
	end
	cf:HookScript("OnShow", function() GuildTab:Anchor() GuildTab:UpdateVisibility() end)
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
	self:Anchor()
	self:UpdateVisibility()
	if self.badgeCount then self:SetBadge(self.badgeCount) end
	setFeature("available", "attached with template " .. (GuildTab.template ~= "" and GuildTab.template or "none"))
	return true
end

function GuildTab:DebugLines()
	return { ("Guild tab: %s%s"):format(self.tab and "attached" or "not attached",
		self.tab and (", " .. (self.tab:IsShown() and "visible" or "hidden") .. (self:IsPanelShown() and ", panel open" or "")) or "") }
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

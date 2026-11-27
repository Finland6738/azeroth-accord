-- About: the Info page of Settings, `/accord about` and `/accord about chat` (SPEC-04 §4 "Informazioni", M6.15). Lua 5.1.
-- Tells who made the addon and with whom (Finland, with the Italian guild NEBULA), what it is for, the licence and where to
-- find the third-party notices, and how to reach the project. The game cannot open a web page, so every link is a read-only
-- copy box (click it, Ctrl+C). Words come from locale keys; the names and the links are constants of this file.
-- Adapted from Finland Dragon Credit Points (UI/Windows/About.lua), same owner, GPL-3.0 (ADR 0021).
--   About.Lines()                 the lines of the page as text: { title, version, purpose, purpose2, madeBy, guild, permission,
--                                 license, third, disclaimer }
--   About.Build(holder, f)        draws the page into `holder`; the parts are fields of f.info: .logo, .nebula (the logo of the
--                                 theme), .links[id] (copy boxes: .edit), .cards, .scroll, .page
--   About.Open() / .PrintToChat() / .Command(input)
-- Not verified in the real client: the look of the page and the copy boxes (docs/roadmap/M6-release.md, M6.15).
local ADDON_NAME, ns = ...
ns = ns or {}
local About = {}
ns.About, ns.modules = About, ns.modules or {}
ns.modules.About = About
if ns.addon then ns.addon.About = About end   -- also reachable from tests

local L, Widgets, Theme, Assets = ns.L, ns.Widgets, ns.Theme, ns.Assets
local ipairs, max, min = ipairs, math.max, math.min

About.AUTHOR = "Finland"
About.GUILD = "NEBULA"
About.LICENSE = "GPL-3.0"
About.PAGE_ID = "info"
-- The links, in the order of the page; the label is the locale key ABOUT_LINK_<ID>.
-- locale-key: ABOUT_LINK_REPO ABOUT_LINK_ISSUES ABOUT_LINK_SITE ABOUT_LINK_KOFI
About.LINKS = {
	{ id = "repo", url = "https://github.com/Finland6738/azeroth-accord" },
	{ id = "issues", url = "https://github.com/Finland6738/azeroth-accord/issues" },
	{ id = "site", url = "https://nebula-community.github.io/giochi/wow-forever/" },
	{ id = "kofi", url = "https://ko-fi.com/finland6738" },
}

local PAD, GAP, WIDTH = 24, 16, 520
local INNER = WIDTH - 2 * PAD
local LOGO, BADGE = 72, 64

local function version()
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	if type(v) ~= "string" or v == "" or v:find("@", 1, true) then return L["ABOUT_VERSION_DEV"] end
	return v
end

-- locale-key: ABOUT_VERSION ABOUT_PURPOSE ABOUT_PURPOSE2 ABOUT_MADE_BY ABOUT_GUILD ABOUT_PERMISSION ABOUT_LICENSE ABOUT_THIRD ABOUT_DISCLAIMER
function About.Lines()
	return {
		title = L["ADDON_TITLE"],
		version = L["ABOUT_VERSION"]:format(version()),
		purpose = L["ABOUT_PURPOSE"],
		purpose2 = L["ABOUT_PURPOSE2"],
		madeBy = L["ABOUT_MADE_BY"]:format(About.AUTHOR),
		guild = L["ABOUT_GUILD"]:format(About.GUILD),
		permission = L["ABOUT_PERMISSION"]:format(About.GUILD),
		license = L["ABOUT_LICENSE"]:format(About.LICENSE),
		third = L["ABOUT_THIRD"],
		disclaimer = L["ABOUT_DISCLAIMER"],
	}
end

---------------------------------------------------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------------------------------------------------
-- A card whose items stack from the top (the same as the Settings page's).
local function stackCard(page)
	local c = Widgets.Card(page, { width = WIDTH, height = 100 })
	c.items = {}
	function c:Add(region, gap, x)
		self.items[#self.items + 1] = { region = region, gap = gap or 8, x = x or 0 }
		return region
	end
	function c:Layout()
		local y, first = PAD - 4, true
		for _, it in ipairs(self.items) do
			local r = it.region
			if r:IsShown() then
				if not first then y = y + it.gap end
				first = false
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + it.x, -y)
				local h
				if r.GetObjectType and r:GetObjectType() == "FontString" then h = r:GetStringHeight() else h = r:GetHeight() end
				y = y + (h or 0)
			end
		end
		self:SetHeight(y + PAD - 4)
		return self:GetHeight()
	end
	return c
end

local function text(parent, font, token, str, width)
	local fs = Widgets.Text(parent, font, token, "LEFT")
	fs:SetWidth(width or INNER)
	fs:SetWordWrap(true)
	fs:SetText(str or "")
	return fs
end

-- A copy box: shows `url`, selects it on focus, and puts it back when the player types in it.
local function copyBox(parent, url)
	local box = Widgets.EditBox(parent, { width = INNER })
	box:SetText(url)
	box.edit:HookScript("OnTextChanged", function(self, user)
		if user and self:GetText() ~= url then self:SetText(url); self:HighlightText() end
	end)
	box.edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
	return box
end

-- A picture beside two texts: the logo of the addon, or the logo of the guild.
local function logoRow(card, size)
	local row = CreateFrame("Frame", nil, card)
	row:SetSize(INNER, size)
	row.logo = row:CreateTexture(nil, "ARTWORK")
	row.logo:SetSize(size, size)
	row.logo:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	return row
end

function About.Build(holder, f)
	local t = About.Lines()
	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetAllPoints(holder)
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(WIDTH, 100)
	scroll:SetScrollChild(page)
	scroll:EnableMouseWheel(true)
	local info = { scroll = scroll, page = page, links = {}, cards = {} }
	f.info = info
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = max(0, (info.height or 0) - (self:GetHeight() or 0))
		self:SetVerticalScroll(min(range, max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
	end)

	-- 1. the addon: logo, name, version, what it does
	local c1 = stackCard(page)
	local head = logoRow(c1, LOGO)
	head.logo:SetTexture(Assets.logos.logo_256.path)
	head.title = Widgets.Text(head, "DisplaySmall", "accent-text", "LEFT")
	head.title:SetPoint("TOPLEFT", head.logo, "TOPRIGHT", 16, -8)
	head.title:SetText(t.title)
	head.version = Widgets.Text(head, "Small", "text-3", "LEFT")
	head.version:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -6)
	head.version:SetText(t.version)
	c1:Add(head, 0)
	info.logo, info.title, info.version = head.logo, head.title, head.version
	info.purpose = c1:Add(text(c1, "Body", "text-2", t.purpose), 16)
	info.purpose2 = c1:Add(text(c1, "Body", "text-2", t.purpose2), 8)

	-- 2. who made it
	local c2 = stackCard(page)
	info.creditsTitle = c2:Add(text(c2, "H2", "text-1", L["ABOUT_CREDITS"]), 0)
	info.madeBy = c2:Add(text(c2, "Body", "text-1", t.madeBy), 12)
	local row = logoRow(c2, BADGE)
	row.logo:SetTexture(Assets.NebulaLogo(Theme.IsDark()).path)
	Theme.Call(row.logo, function(tex) tex:SetTexture(Assets.NebulaLogo(Theme.IsDark()).path) end)   -- follows the theme
	row.guild = text(row, "Body", "text-1", t.guild, INNER - BADGE - 16)
	row.guild:SetPoint("TOPLEFT", row.logo, "TOPRIGHT", 16, -4)
	row.permission = text(row, "Small", "text-3", t.permission, INNER - BADGE - 16)
	row.permission:SetPoint("TOPLEFT", row.guild, "BOTTOMLEFT", 0, -6)
	c2:Add(row, 12)
	info.nebula, info.guild, info.permission = row.logo, row.guild, row.permission

	-- 3. the links, in copy boxes
	local c3 = stackCard(page)
	info.linksTitle = c3:Add(text(c3, "H2", "text-1", L["ABOUT_LINKS"]), 0)
	info.linksHint = c3:Add(text(c3, "Small", "text-3", L["ABOUT_LINKS_HINT"]), 4)
	info.labels = {}
	for _, link in ipairs(About.LINKS) do
		info.labels[link.id] = c3:Add(text(c3, "Small", "text-2", L["ABOUT_LINK_" .. link.id:upper()]), 14)
		info.links[link.id] = c3:Add(copyBox(c3, link.url), 4)
	end

	-- 4. the licence and the notices
	local c4 = stackCard(page)
	info.legalTitle = c4:Add(text(c4, "H2", "text-1", L["ABOUT_LEGAL"]), 0)
	info.license = c4:Add(text(c4, "Body", "text-2", t.license), 8)
	info.third = c4:Add(text(c4, "Body", "text-2", t.third), 8)
	info.disclaimer = c4:Add(text(c4, "Small", "text-3", t.disclaimer), 12)

	local y = 0
	for i, c in ipairs({ c1, c2, c3, c4 }) do
		c:Layout()
		c:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
		y = y + c:GetHeight() + GAP
		info.cards[i] = c
	end
	info.height = y - GAP
	page:SetHeight(info.height)
	return info
end

---------------------------------------------------------------------------------------------------------------------
-- The commands
---------------------------------------------------------------------------------------------------------------------
-- The credits in the chat, links included (they can be selected and copied from the chat frame).
function About.PrintToChat()
	local ACC, t = ns.addon, About.Lines()
	ACC:Print(t.title .. " - " .. t.version)
	ACC:Print(t.madeBy)
	ACC:Print(t.guild)
	ACC:Print(t.permission)
	for _, link in ipairs(About.LINKS) do ACC:Print(L["ABOUT_LINK_" .. link.id:upper()] .. ": " .. link.url) end
	ACC:Print(t.license)
	ACC:Print(t.disclaimer)
end

function About.Open()
	if not (ns.Shell and ns.SettingsView and ns.Shell:OpenView("settings")) then return About.PrintToChat() end
	local f = ns.SettingsView.frame
	if f then ns.SettingsView:ShowPage(f, About.PAGE_ID) end
end

-- /accord about: opens the Info page; /accord about chat: prints the credits in the chat instead.
function About.Command(input)
	local _, arg = ns.addon:GetArgs(input or "", 2)
	if arg and arg:lower() == "chat" then return About.PrintToChat() end
	About.Open()
end

if ns.SettingsView then
	ns.SettingsView.AddPage(About.PAGE_ID, { label = L["ABOUT_TAB"], order = 20, build = About.Build })
end

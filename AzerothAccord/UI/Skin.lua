-- Skin: the look of the Accord panel (SPEC-04 §5): like Blizzard's guild window, so the tab feels native. Lua 5.1.
-- Adapted from Azeroth Guild Finder (UI/Skin.lua), same owner, GPL-3.0 (ADR 0018): the idea of one place for colours,
-- type and frame styles is kept, the custom parchment textures and fonts are not. Accord draws with the client's own
-- font objects, colours and frame templates; a template the client does not have falls back to a plain frame.
local ADDON_NAME, ns = ...
ns = ns or {}
local Skin = {}
ns.Skin, ns.modules = Skin, ns.modules or {}
ns.modules.Skin = Skin

local type, ipairs, pcall, floor, min, max = type, ipairs, pcall, math.floor, math.min, math.max

-- Colours (r, g, b): the gold of Blizzard's headings (NORMAL_FONT_COLOR), white text, the grey of disabled text, and
-- the dark backgrounds of the guild window's insets.
Skin.COLORS = {
	gold = { 1, 0.82, 0 },
	white = { 1, 1, 1 },
	grey = { 0.6, 0.6, 0.6 },
	green = { 0.25, 0.75, 0.25 },
	red = { 1, 0.3, 0.3 },
	panel = { 0.06, 0.05, 0.04 },
	navSelected = { 0.9, 0.75, 0.25 },
}

function Skin.Color(name, alpha)
	local c = Skin.COLORS[name] or Skin.COLORS.white
	return c[1], c[2], c[3], alpha or 1
end

-- "|cffRRGGBBtext|r" in a colour of the skin.
function Skin.Colored(name, text)
	local r, g, b = Skin.Color(name)
	local function byte(v) return floor(min(1, max(0, v)) * 255 + 0.5) end
	return ("|cff%02x%02x%02x%s|r"):format(byte(r), byte(g), byte(b), tostring(text))
end

-- Type styles -> the client's font objects (looked up when used: they exist once FrameXML has loaded).
Skin.FONTS = {
	title = "GameFontNormalLarge",
	heading = "GameFontNormal",
	body = "GameFontHighlight",
	small = "GameFontHighlightSmall",
	muted = "GameFontDisableSmall",
	mono = "ChatFontNormal",
}

function Skin.Font(style)
	local name = Skin.FONTS[style] or Skin.FONTS.body
	local font = _G[name]
	if font == nil and name ~= Skin.FONTS.body then font = _G[Skin.FONTS.body] end
	return font
end

-- Frame templates per role, best first; "" is a plain frame. CreateFrame raises on an unknown template, so each one
-- is tried under pcall (Widgets.Create).
Skin.TEMPLATES = {
	window = { "PortraitFrameTemplate", "ButtonFrameTemplate", "BasicFrameTemplateWithInset", "" },
	inset = { "InsetFrameTemplate", "" },
	button = { "UIPanelButtonTemplate", "" },
	close = { "UIPanelCloseButton", "" },
	search = { "SearchBoxTemplate", "InputBoxTemplate", "" },
	scroll = { "UIPanelScrollFrameTemplate", "" },
	guildTab = { "CommunitiesFrameTabTemplate", "CommunitiesTabTemplate", "SidebarTabTemplate", "" },
	navButton = { "" },
}

-- The icon of the Accord tab in the guild window (SPEC-10 Q2: the logo is proposed, the owner decides).
Skin.ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
Skin.ICON_FALLBACK = 134400   -- the question-mark icon, by file id
-- The addon's logo (Media/, tools/make_media.py): the AddOn Compartment icon (TOC ## IconTexture), the window's portrait
-- and the empty state. The path is ns.Assets.logos.logo_64.path (UI/Assets.lua), not a Skin field.

if ns.addon then ns.addon.Skin = Skin end

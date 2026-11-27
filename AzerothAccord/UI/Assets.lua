-- Assets: the one table of every texture, logo and font file of the addon (docs/specs/ui-style.md §1, §4, §7). Lua 5.1.
-- Adapted from Finland Dragon Credit Points (UI/Assets.lua), same owner, GPL-3.0 (ADR 0021).
-- * tools/check_addon.py reads this file: every path below exists in Media/ and every file of Media/ is listed here
--   (so each path is written out in full, not built from the addon name); the sizes are those of the TGA headers.
-- * All textures are white: the theme tints them (UI/Theme.lua). `slice` is the 9-slice margin in texels.
local ADDON_NAME, ns = ...
ns = ns or {}

local Assets = {}
ns.Assets = Assets
if ns.addon then ns.addon.Assets = Assets end   -- also reachable from tests

Assets.textures = {
	rr_fill_4   = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_fill_4.tga",   w = 64,  h = 64,  slice = 4 },
	rr_fill_8   = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_fill_8.tga",   w = 64,  h = 64,  slice = 8 },
	rr_fill_12  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_fill_12.tga",  w = 64,  h = 64,  slice = 12 },
	rr_fill_16  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_fill_16.tga",  w = 64,  h = 64,  slice = 16 },
	rr_fill_18  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_fill_18.tga",  w = 64,  h = 64,  slice = 18 },
	rr_fill_20  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_fill_20.tga",  w = 64,  h = 64,  slice = 20 },
	rr_fill_28  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_fill_28.tga",  w = 64,  h = 64,  slice = 28 },
	rr_ring_4   = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring_4.tga",   w = 64,  h = 64,  slice = 4 },
	rr_ring_8   = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring_8.tga",   w = 64,  h = 64,  slice = 8 },
	rr_ring_12  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring_12.tga",  w = 64,  h = 64,  slice = 12 },
	rr_ring_16  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring_16.tga",  w = 64,  h = 64,  slice = 16 },
	rr_ring_18  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring_18.tga",  w = 64,  h = 64,  slice = 18 },
	rr_ring_20  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring_20.tga",  w = 64,  h = 64,  slice = 20 },
	rr_ring_28  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring_28.tga",  w = 64,  h = 64,  slice = 28 },
	rr_ring2_4  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring2_4.tga",  w = 64,  h = 64,  slice = 4 },
	rr_ring2_16 = { path = "Interface\\AddOns\\AzerothAccord\\Media\\rr_ring2_16.tga", w = 64,  h = 64,  slice = 16 },
	shadow      = { path = "Interface\\AddOns\\AzerothAccord\\Media\\shadow.tga",      w = 128, h = 128, slice = 48 },
	glow_s      = { path = "Interface\\AddOns\\AzerothAccord\\Media\\glow_s.tga",      w = 128, h = 128, slice = 48 },
	glow_l      = { path = "Interface\\AddOns\\AzerothAccord\\Media\\glow_l.tga",      w = 128, h = 128, slice = 56 },
	pill        = { path = "Interface\\AddOns\\AzerothAccord\\Media\\pill.tga",        w = 64,  h = 32,  slice = 16 },
	circle      = { path = "Interface\\AddOns\\AzerothAccord\\Media\\circle.tga",      w = 64,  h = 64 },
	blob_radial = { path = "Interface\\AddOns\\AzerothAccord\\Media\\blob_radial.tga", w = 128, h = 128 },
	icons       = { path = "Interface\\AddOns\\AzerothAccord\\Media\\symbols.tga",     w = 512, h = 512, cell = 48 },
}

-- The addon's logo (the AddOn Compartment icon is the TOC's `## IconTexture`, logo_64) and the logos of the Italian
-- guild NEBULA for the credits (used with the guild's permission, docs/third-party.md): the dark one on the dark themes.
Assets.logos = {
	logo_256     = { path = "Interface\\AddOns\\AzerothAccord\\Media\\logo_256.tga",         w = 256, h = 256 },
	logo_64      = { path = "Interface\\AddOns\\AzerothAccord\\Media\\logo_64.tga",          w = 64,  h = 64 },
	nebula_dark  = { path = "Interface\\AddOns\\AzerothAccord\\Media\\nebula_dark_256.tga",  w = 256, h = 256 },
	nebula_light = { path = "Interface\\AddOns\\AzerothAccord\\Media\\nebula_light_256.tga", w = 256, h = 256 },
}

-- The icons: Google's Material Symbols Rounded (Apache 2.0, docs/third-party.md), in one atlas built by
-- tools/make_icons.py, whose lists these three mirror (tools/check_addon.py compares them).
-- Glyphs in the order of the cells, 10 per row: the outlined ones first...
Assets.glyphs = {
	"chevron_right", "check", "close", "south_east", "skull", "shield", "health_and_safety", "swords", "star",
	"settings", "arrow_upward", "arrow_downward", "lock", "visibility", "fiber_manual_record", "add", "info",
	"warning", "search", "filter_alt", "content_copy", "delete", "edit", "calendar_month", "schedule", "person",
	"group", "crown", "paid", "refresh", "download", "upload", "notifications", "flag", "remove", "diamond",
	"shopping_bag", "menu_book", "link", "arrow_back", "favorite", "home", "groups", "group_add", "construction",
	"account_balance", "celebration", "shield_person" }
-- ...then the filled ones, for the icons that show an active state (ui-style.md §9.10).
Assets.filledGlyphs = {
	"home", "groups", "swords", "group_add", "construction", "account_balance", "celebration", "shield_person",
	"settings", "notifications", "group", "favorite", "paid", "flag", "calendar_month", "schedule", "skull",
	"menu_book", "diamond", "crown", "star", "fiber_manual_record" }
-- Accord's name of an icon -> the glyph that draws it. A glyph's own name works too ("home", "groups").
Assets.iconNames = {
	chevron = "chevron_right", check = "check", cross = "close", dashed = "south_east", skull = "skull",
	shield = "shield", heal = "health_and_safety", sword = "swords", star = "star", gear = "settings",
	arrow_up = "arrow_upward", arrow_down = "arrow_downward", lock = "lock", eye = "visibility",
	dot = "fiber_manual_record", plus = "add", info = "info", warn = "warning", search = "search",
	filter = "filter_alt", copy = "content_copy", trash = "delete", edit = "edit", calendar = "calendar_month",
	clock = "schedule", user = "person", users = "group", crown = "crown", coin = "paid", refresh = "refresh",
	download = "download", upload = "upload", bell = "notifications", flag = "flag", minus = "remove",
	gem = "diamond", bag = "shopping_bag", book = "menu_book", link = "link", arrow_left = "arrow_back",
	heart = "favorite", hammer = "construction" }

-- Fonts (docs/third-party.md). Orbitron ships whole (it declares a Reserved Font Name): it is used for the title only, in
-- capitals, and has no middle dot or arrow. `fallback` is the game font used when SetFont fails or the player chose the
-- game's fonts ("FRIZQT" for the display face, "STANDARD" for the others).
Assets.fonts = {
	display      = { path = "Interface\\AddOns\\AzerothAccord\\Media\\Fonts\\Orbitron-Bold.ttf",         fallback = "FRIZQT" },
	text         = { path = "Interface\\AddOns\\AzerothAccord\\Media\\Fonts\\Outfit-Regular.ttf",        fallback = "STANDARD" },
	textMedium   = { path = "Interface\\AddOns\\AzerothAccord\\Media\\Fonts\\Outfit-Medium.ttf",         fallback = "STANDARD" },
	textSemiBold = { path = "Interface\\AddOns\\AzerothAccord\\Media\\Fonts\\Outfit-SemiBold.ttf",       fallback = "STANDARD" },
	mono         = { path = "Interface\\AddOns\\AzerothAccord\\Media\\Fonts\\JetBrainsMono-Regular.ttf", fallback = "STANDARD" },
	monoMedium   = { path = "Interface\\AddOns\\AzerothAccord\\Media\\Fonts\\JetBrainsMono-Medium.ttf",  fallback = "STANDARD" },
}

-- The logo that goes with a theme's credits: the NEBULA logo for a dark or a light surface.
function Assets.NebulaLogo(dark)
	return dark and Assets.logos.nebula_dark or Assets.logos.nebula_light
end

-- Every file path of the tables, sorted: for the offline check and the probes.
function Assets.AllPaths()
	local out = {}
	for _, group in ipairs({ Assets.textures, Assets.logos, Assets.fonts }) do
		for _, t in pairs(group) do out[#out + 1] = t.path end
	end
	table.sort(out)
	return out
end

-- Every texture file (textures and logos, not fonts): what the probes ask the client to load.
function Assets.TexturePaths()
	local out = {}
	for _, group in ipairs({ Assets.textures, Assets.logos }) do
		for _, t in pairs(group) do out[#out + 1] = t.path end
	end
	table.sort(out)
	return out
end

-- glyph -> its cell (1-based) in the atlas
local outlinedCell, filledCell = {}, {}
for i, glyph in ipairs(Assets.glyphs) do outlinedCell[glyph] = i end
for i, glyph in ipairs(Assets.filledGlyphs) do filledCell[glyph] = #Assets.glyphs + i end

-- An icon as an inline texture escape for a text ("|T...|t"), `size` points high (default 14); "" for an unknown name.
function Assets.IconText(name, size)
	local l, r, t, b = Assets.IconCoords(name)
	if not l then return "" end
	local sheet = Assets.textures.icons
	size = size or 14
	return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t"):format(sheet.path, size, size, sheet.w, sheet.h,
		l * sheet.w, r * sheet.w, t * sheet.h, b * sheet.h)
end

-- Texture coordinates of an icon in the atlas: left, right, top, bottom; nil for an unknown name. `filled` asks for the
-- filled variant; an icon that has none answers with the outlined one.
function Assets.IconCoords(name, filled)
	local glyph = Assets.iconNames[name] or name
	local i = (filled and filledCell[glyph]) or outlinedCell[glyph]
	if not i then return nil end
	local sheet = Assets.textures.icons
	local per = math.floor(sheet.w / sheet.cell)
	local col, row = (i - 1) % per, math.floor((i - 1) / per)
	local s = sheet.cell / sheet.w
	return col * s, (col + 1) * s, row * s, (row + 1) * s
end

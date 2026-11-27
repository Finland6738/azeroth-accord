-- Theme: the tokens of docs/specs/ui-style.md §4 in three themes, the registry of tinted regions, font objects, the Px()
-- helper and the 9-slice shapes (M6.10). Lua 5.1; UI only, no game data.
-- Adapted from Finland Dragon Credit Points (UI/Theme.lua), same owner, GPL-3.0 (ADR 0021). The look settings are saved
-- per ACCOUNT (account.settings.theme / effects / animations / font, docs/specs/ui-style.md §2).
-- * Every texture is white; a region that shows a token registers itself (Theme.Tint / Theme.Text / Theme.Call) and
--   Theme.Apply recolours all of them without /reload. The registry has weak keys: a region that is gone costs nothing.
-- * A font that fails to load falls back to the game's font (SetFont answers false); "Font: game" forces the fallback.
-- * Bus: THEME_CHANGED(themeId) after Apply; it listens to CONFIG_LOADED (reads the saved look) and CONFIG_CHANGED.
local ADDON_NAME, ns = ...
ns = ns or {}

local Theme = {}
ns.Theme = Theme
if ns.addon then ns.addon.Theme = Theme end   -- also reachable from tests

local Assets = ns.Assets
local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring

-- --- tokens ------------------------------------------------------------------------------------------------------------

local function hex(s)
	return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255, 1 }
end
local function rgba(r, g, b, a) return { r / 255, g / 255, b / 255, a } end

-- Token names, in the order of the spec's table. Every theme defines every one of them (tests check the parity).
Theme.TOKENS = { "bg", "surface-1", "surface-2", "surface-3", "raised", "border-subtle", "border", "border-strong",
	"text-1", "text-2", "text-3", "on-accent", "accent", "accent-hover", "accent-text", "accent-2", "neon", "neon-core",
	"ok", "warn", "err", "highlight", "scrim", "grad-1", "grad-2", "grad-3", "grad-4",
	-- the colour roles Accord adds for Material 3 (docs/specs/ui-style.md §9.1, M12.6)
	"secondary-container", "on-secondary-container", "inverse-surface", "inverse-on-surface", "on-error" }

local function lightBorders(r, g, b) return rgba(r, g, b, .07), rgba(r, g, b, .13), rgba(r, g, b, .24) end

Theme.themes = {
	nebula = {
		name = "Nebula", dark = true,
		bg = hex("#0B0612"), ["surface-1"] = hex("#110A1A"), ["surface-2"] = hex("#170F22"), ["surface-3"] = hex("#1E142C"),
		raised = hex("#2A1D3B"),
		["border-subtle"] = rgba(243, 238, 247, .08), border = rgba(243, 238, 247, .14), ["border-strong"] = rgba(243, 238, 247, .26),
		["text-1"] = hex("#F3EEF7"), ["text-2"] = hex("#C3B8D1"), ["text-3"] = hex("#9A8FAB"),
		["on-accent"] = hex("#1A0710"), accent = hex("#FC7E46"), ["accent-hover"] = hex("#FDA877"), ["accent-text"] = hex("#FC8C46"),
		["accent-2"] = hex("#EE4662"), neon = hex("#C45BC4"), ["neon-core"] = hex("#9A2A9A"),
		ok = hex("#46C28F"), warn = hex("#F2B33D"), err = hex("#FF6369"),
		highlight = rgba(255, 255, 255, .06), scrim = rgba(5, 2, 10, .72),
		["grad-1"] = hex("#FC8C46"), ["grad-2"] = hex("#EE4662"), ["grad-3"] = hex("#9A2A9A"), ["grad-4"] = hex("#702AA8"),
		-- M3 roles (§9.1): a muted plum tonal fill with a pale lilac on it, a light inverse surface, a dark ink on err
		["secondary-container"] = hex("#3B2A52"), ["on-secondary-container"] = hex("#EBDDF8"),
		["inverse-surface"] = hex("#E9E2F0"), ["inverse-on-surface"] = hex("#251B30"), ["on-error"] = hex("#3D0509"),
	},
	aurora = {
		name = "Aurora", dark = false,
		bg = hex("#F5F8FA"), ["surface-1"] = hex("#FFFFFF"), ["surface-2"] = hex("#EAF0F4"), ["surface-3"] = hex("#E1E9EF"),
		raised = hex("#FFFFFF"),
		["text-1"] = hex("#0B1B2B"), ["text-2"] = hex("#3C4E60"), ["text-3"] = hex("#526476"),
		["on-accent"] = hex("#FFFFFF"), accent = hex("#0054B6"), ["accent-hover"] = hex("#003F8A"), ["accent-text"] = hex("#0054B6"),
		["accent-2"] = hex("#00766C"), neon = hex("#008F84"), ["neon-core"] = hex("#009A9A"),   -- the site's #00A89A darkened to 3:1 on the light surface (M7-1)
		ok = hex("#1B7A50"), warn = hex("#8F5B00"), err = hex("#C0262D"),
		highlight = rgba(255, 255, 255, .6), scrim = rgba(11, 27, 43, .45),
		["grad-1"] = hex("#0054B6"), ["grad-2"] = hex("#007EA8"), ["grad-3"] = hex("#00A89A"), ["grad-4"] = hex("#70C446"),
		-- M3 roles (§9.1): a light blue tonal fill with a deep navy on it, a dark inverse surface, white on err
		["secondary-container"] = hex("#C8DAF0"), ["on-secondary-container"] = hex("#0A2A4F"),
		["inverse-surface"] = hex("#24303D"), ["inverse-on-surface"] = hex("#EEF3F7"), ["on-error"] = hex("#FFFFFF"),
	},
	accord = {
		name = "Accord", dark = true,
		bg = hex("#04171A"), ["surface-1"] = hex("#0A2327"), ["surface-2"] = hex("#102E31"), ["surface-3"] = hex("#16393B"),
		raised = hex("#1D4546"),
		["border-subtle"] = rgba(232, 243, 236, .08), border = rgba(232, 243, 236, .14), ["border-strong"] = rgba(232, 243, 236, .26),
		["text-1"] = hex("#E8F3EC"), ["text-2"] = hex("#BFD6CB"), ["text-3"] = hex("#8FB0A3"),
		["on-accent"] = hex("#261C00"), accent = hex("#D9B54E"), ["accent-hover"] = hex("#E8CB72"), ["accent-text"] = hex("#D9B54E"),
		["accent-2"] = hex("#4FBF8E"), neon = hex("#7DE8B5"), ["neon-core"] = hex("#3FB07F"),
		ok = hex("#5CCB8D"), warn = hex("#F2B33D"), err = hex("#FF6B5E"),
		highlight = rgba(255, 255, 255, .06), scrim = rgba(1, 10, 12, .72),
		["grad-1"] = hex("#D9B54E"), ["grad-2"] = hex("#9FE3A8"), ["grad-3"] = hex("#4FBF8E"), ["grad-4"] = hex("#1F7A64"),
		-- M3 roles (§9.1): a dark olive-gold tonal fill (the banner's gold, muted) with a pale gold on it, a light mint
		-- inverse surface, a dark ink on err
		["secondary-container"] = hex("#3D4426"), ["on-secondary-container"] = hex("#F1E7BE"),
		["inverse-surface"] = hex("#DDEBE3"), ["inverse-on-surface"] = hex("#10292A"), ["on-error"] = hex("#3D0702"),
	},
}
do
	local a = Theme.themes.aurora
	a["border-subtle"], a.border, a["border-strong"] = lightBorders(11, 27, 43)
end

Theme.ORDER = { "nebula", "aurora", "accord" }
Theme.DEFAULT = "nebula"

function Theme.Has(id) return Theme.themes[id] ~= nil end
function Theme.List() return Theme.ORDER end
function Theme.Name(id) return Theme.themes[id] and Theme.themes[id].name or id end

local current = Theme.DEFAULT
function Theme.Current() return current end
function Theme.IsDark() return Theme.themes[current].dark end

-- The colour of a token in the current theme (or of `themeId`): r, g, b, a. An unknown token is magenta, so a typo shows.
function Theme.Color(token, themeId)
	local c = (Theme.themes[themeId or current] or Theme.themes[Theme.DEFAULT])[token]
	if not c then return 1, 0, 1, 1 end
	return c[1], c[2], c[3], c[4]
end

-- The opacities of the Material 3 state layers (docs/specs/ui-style.md §9.2, M12.6): a layer in the colour of the
-- element's content (its on-... role, or its label's colour) over the container. Disabled shows no layer: the content at
-- 38 % and the container at 12 % of text-1. One layer at a time.
Theme.STATE = { hover = 0.08, focus = 0.10, pressed = 0.10, dragged = 0.16, disabledContent = 0.38, disabledContainer = 0.12 }

-- Series of a chart or a map (the communities of the group map, M6.14): tokens in an order where neighbours differ.
Theme.SERIES = { "accent", "neon", "ok", "warn", "accent-2", "grad-4", "err", "text-3" }

-- The colours of the game's own tooltip (GameTooltip is Blizzard's dark frame, not a themed one): white text, grey for a
-- note, gold for a highlight, from the game's colour objects when they exist. Returns r, g, b.
local GAME_COLOURS = {
	text = { "HIGHLIGHT_FONT_COLOR", 1, 1, 1 },
	muted = { "GRAY_FONT_COLOR", 0.5, 0.5, 0.5 },
	gold = { "NORMAL_FONT_COLOR", 1, 0.82, 0 },
	err = { "RED_FONT_COLOR", 1, 0.1, 0.1 },
}
function Theme.GameColor(name)
	local spec = GAME_COLOURS[name] or GAME_COLOURS.text
	local c = _G[spec[1]]
	if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
	return spec[2], spec[3], spec[4]
end

-- --- the registry of tinted regions -----------------------------------------------------------------------------------

-- region -> list of { kind, token, extra }. Weak keys: a destroyed or collected region drops out by itself.
local registry = setmetatable({}, { __mode = "k" })

local function applyOne(region, entry)
	local kind = entry.kind
	if kind == "vertex" then
		local r, g, b, a = Theme.Color(entry.token)
		region:SetVertexColor(r, g, b, (a or 1) * (entry.alpha or 1))
	elseif kind == "color" then
		local r, g, b, a = Theme.Color(entry.token)
		region:SetColorTexture(r, g, b, (a or 1) * (entry.alpha or 1))
	elseif kind == "text" then
		local r, g, b, a = Theme.Color(entry.token)
		region:SetTextColor(r, g, b, a or 1)
	elseif kind == "rgb" then
		region:SetTextColor(entry.r, entry.g, entry.b, 1)   -- a colour of the game (item quality), not of a theme
	elseif kind == "class" then
		if Theme.IsDark() then
			region:SetTextColor(entry.r, entry.g, entry.b, 1)   -- the class colour on a dark surface
		else
			local r, g, b, a = Theme.Color("text-1")            -- on a light surface only the square is coloured
			region:SetTextColor(r, g, b, a or 1)
		end
	elseif kind == "fn" then
		entry.fn(region, current)
	end
end

-- The colour of a text is one thing: a token ("text"), a class colour ("class") or a game colour ("rgb"); setting one
-- replaces the others, so a pooled row that is filled again never keeps the colour of its previous data.
local TEXT_COLOUR = { text = true, class = true, rgb = true }

local function add(region, entry)
	local list = registry[region]
	if not list then list = {}; registry[region] = list end
	-- one entry per kind: registering again replaces the token (a button that changes style)
	for i, e in ipairs(list) do
		if e.kind ~= "fn" and (e.kind == entry.kind or (TEXT_COLOUR[e.kind] and TEXT_COLOUR[entry.kind])) then
			list[i] = entry; applyOne(region, entry); return region
		end
	end
	list[#list + 1] = entry
	applyOne(region, entry)
	return region
end

-- A white texture shows `token` through SetVertexColor; `alpha` multiplies the token's own alpha.
function Theme.Tint(region, token, alpha) return add(region, { kind = "vertex", token = token, alpha = alpha }) end
-- A solid-colour texture (SetColorTexture) in `token`.
function Theme.Fill(region, token, alpha) return add(region, { kind = "color", token = token, alpha = alpha }) end
-- A FontString (or font object) coloured with `token`.
function Theme.Text(region, token) return add(region, { kind = "text", token = token }) end
-- A FontString in a colour of the game (r, g, b in 0..1): the item quality, the class of a player. It survives Apply.
function Theme.TextRGB(region, r, g, b) return add(region, { kind = "rgb", r = r, g = g, b = b }) end
-- A player's name: the class colour on the dark themes, text-1 on the light one (the square next to it carries the colour).
function Theme.ClassText(region, r, g, b) return add(region, { kind = "class", r = r, g = g, b = b }) end
-- A free function fn(region, themeId) that sets whatever a token cannot (a gradient, a blend mode); runs now and on Apply.
function Theme.Call(region, fn) return add(region, { kind = "fn", fn = fn }) end

function Theme.Count()
	local n = 0
	for _ in pairs(registry) do n = n + 1 end
	return n
end

-- The two preferences of the Settings (docs/specs/ui-style.md §2: "Neon effects", "Animations"), saved per account. Both
-- are on by default; before Config:Load (the first frames of a load) the answer is the default.
local function preference(name)
	local cfg = ns.Config
	if cfg and cfg.db then
		local v = cfg:Get("account.settings." .. name)
		if type(v) == "boolean" then return v end
	end
	return true
end
function Theme.EffectsOn() return preference("effects") end
function Theme.AnimationsOn() return preference("animations") end

-- A soft glow of Media/glow_s or glow_l behind `parent`, white and tinted with `token`. Dark themes add it to the picture
-- (blend mode ADD, the site's neon); the light theme draws it as an ordinary soft shadow at half strength. It is hidden
-- with the "Neon effects" preference off. opts: layer, alpha. Returns the texture; the caller anchors it.
function Theme.Glow(parent, key, token, opts)
	opts = opts or {}
	local tex = Theme.Slice(parent, key, token, opts.layer or "BACKGROUND", opts.alpha or 0.4)   -- no token: the caller tints it
	tex._glow = true
	Theme.Call(tex, function(region, id)
		local dark = Theme.themes[id].dark
		if region.SetBlendMode then region:SetBlendMode(dark and "ADD" or "BLEND") end
		region:SetShown(Theme.EffectsOn() and region._want ~= false)
		region._additive = dark
	end)
	return tex
end

-- Shows or hides a glow on purpose (the one neon element of a view): it still disappears with "Neon effects" off.
function Theme.GlowShow(tex, shown)
	tex._want = shown and true or false
	tex:SetShown(tex._want and Theme.EffectsOn())
end

-- A text glow for the one display title of a view: a coloured shadow of the font, dark themes and effects on only.
function Theme.TextGlow(fs, token)
	Theme.Call(fs, function(region, id)
		local on = Theme.themes[id].dark and Theme.EffectsOn()
		local r, g, b = Theme.Color(token or "accent", id)
		if region.SetShadowColor then region:SetShadowColor(r, g, b, on and 0.55 or 0) end
		if region.SetShadowOffset then region:SetShadowOffset(0, on and -1 or 0) end
		region._glowing = on
	end)
end

-- Switches the theme and recolours every registered region. Returns true when the theme exists.
function Theme.Apply(id)
	if id ~= nil then
		if not Theme.themes[id] then return false end
		current = id
	end
	for region, list in pairs(registry) do
		for _, entry in ipairs(list) do
			local ok, err = pcall(applyOne, region, entry)
			if not ok then   -- a region that fails to repaint never stops the others; /accord debug counts it (text only)
			Theme.applyFailures = (Theme.applyFailures or 0) + 1
			Theme.lastFailure = tostring(err):sub(1, 80)
		end
		end
	end
	if ns.Bus then ns.Bus:Emit("THEME_CHANGED", current) end
	return true
end

-- Reads the saved theme (account.settings.theme) and applies it; called when the saved data is loaded.
function Theme.Load()
	local id = ns.Config and ns.Config.db and ns.Config:Get("account.settings.theme") or Theme.DEFAULT
	if not Theme.themes[id] then id = Theme.DEFAULT end
	return Theme.Apply(id)
end

-- Saves and applies a theme. Returns ok, reason ("bad value", or what Config:Set refused: "read-only"...).
function Theme.Set(id)
	if not Theme.themes[id] then return false, "bad value" end
	if ns.Config and ns.Config.db and ns.Config.db.account then
		local ok, why = ns.Config:Set("account.settings.theme", id)
		if not ok then return false, why end
	end
	if current ~= id then Theme.Apply(id) end   -- Config's CONFIG_CHANGED has repainted already when it was on the bus
	return true
end

-- --- Px and snapping ---------------------------------------------------------------------------------------------------

-- One physical pixel in UI units of `frame` (UIParent by default): lines of 1 px stay sharp at any UI scale.
function Theme.PixelSize(frame)
	frame = frame or UIParent
	local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
	local physical
	if GetPhysicalScreenSize then
		local ok, _, h = pcall(GetPhysicalScreenSize)
		if ok and type(h) == "number" and h > 0 then physical = h end
	end
	if not scale or scale <= 0 then scale = 1 end
	return (768 / (physical or 768)) / scale
end

function Theme.Px(n, frame) return (n or 1) * Theme.PixelSize(frame) end

-- Turns off the engine's pixel snapping for a texture (thin lines at fractional scales); each call is guarded.
function Theme.Crisp(texture)
	if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
	if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
	return texture
end

-- --- fonts -------------------------------------------------------------------------------------------------------------

-- Font objects: id -> { key of Assets.fonts, size }. Names are AzerothAccordFont<Id> (docs/specs/ui-style.md §1).
Theme.fontSpecs = {
	Display = { "display", 22 }, DisplaySmall = { "display", 15 },
	TitleLarge = { "textSemiBold", 18 }, H1 = { "textSemiBold", 16 }, H2 = { "textSemiBold", 14 },
	BodyLarge = { "text", 14 }, Body = { "text", 13 }, BodyMedium = { "textMedium", 13 }, Small = { "text", 11 },
	Eyebrow = { "textMedium", 11 }, Th = { "textSemiBold", 10 }, Tab = { "textMedium", 14 }, Button = { "textMedium", 13 },
	Mono = { "mono", 13 }, MonoMedium = { "monoMedium", 13 }, MonoSmall = { "mono", 10 },
}

-- The Material 3 type roles (docs/specs/ui-style.md §9.4, M12.6) and the font object each one uses: body and label text
-- one point under M3, like the game's text. Theme.Font, Theme.NewText and Widgets.Text take a role name as well as a font
-- id, so a view can say "title-large" instead of picking a size. The old ids stay as they are.
Theme.TYPE_ROLES = {
	["headline-small"] = "Display",   -- 22: the title "AZEROTH ACCORD"
	["title-large"] = "TitleLarge",   -- 18: dialogs, the member card
	["title-medium"] = "H1",          -- 16: card titles
	["title-small"] = "H2",           -- 14: section titles (the tabs' labels use Tab, the same size)
	["body-large"] = "BodyLarge",     -- 14: long text (the handbook)
	["body-medium"] = "Body",         -- 13: text and table cells
	["body-small"] = "Small",         -- 11: help text, subtitles, tooltips
	["label-large"] = "Button",       -- 13: buttons, chips
	["label-medium"] = "Eyebrow",     -- 11: eyebrows, column headers
	["label-small"] = "Th",           -- 10: badges, small labels
}
-- The font id of a role or of an id ("title-large" -> "TitleLarge", "Body" -> "Body").
function Theme.FontId(idOrRole) return Theme.TYPE_ROLES[idOrRole] or idOrRole end
Theme.fontStatus = {}   -- id -> "addon" | "game"
Theme.fontObjects = {}  -- id -> font object

local function gameFontPath(key)
	if key == "FRIZQT" then return _G.UNIT_NAME_FONT or "Fonts\\FRIZQT__.TTF" end
	return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Builds or refreshes every font object. `source` is "addon" (the files of Media/Fonts) or "game"; a file that does not
-- load falls back to the game font for that object. Returns the number of objects that use the game font.
function Theme.SetupFonts(source)
	source = source or (ns.Config and ns.Config.db and ns.Config:Get("account.settings.font")) or "addon"
	local fallbacks = 0
	for id, spec in pairs(Theme.fontSpecs) do
		local asset = Assets.fonts[spec[1]]
		local obj = Theme.fontObjects[id]
		if not obj then
			obj = CreateFont(Theme.FontName(id))
			Theme.fontObjects[id] = obj
		end
		local ok = false
		if source ~= "game" then ok = obj:SetFont(asset.path, spec[2], "") and true or false end
		if not ok then
			obj:SetFont(gameFontPath(asset.fallback), spec[2], "")
			Theme.fontStatus[id] = "game"
			fallbacks = fallbacks + 1
		else
			Theme.fontStatus[id] = "addon"
		end
	end
	return fallbacks
end

-- The font objects exist before the first text: normally CONFIG_LOADED builds them, but a text made before (or after a
-- failed load) would have no font, and the client refuses SetText on a FontString without one ("Font not set").
local function ensureFonts()
	if next(Theme.fontObjects) == nil then Theme.SetupFonts() end
end
Theme.EnsureFonts = ensureFonts

function Theme.Font(id) ensureFonts() return Theme.fontObjects[Theme.FontId(id)] or Theme.fontObjects.Body end
function Theme.FontName(id) return "AzerothAccordFont" .. id end

-- A FontString of `parent` in font `id` and colour `token` (registered).
function Theme.NewText(parent, id, token, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	ensureFonts()
	fs:SetFontObject(Theme.fontObjects[Theme.FontId(id)] or Theme.fontObjects.Body)
	Theme.Text(fs, token or "text-1")
	return fs
end

-- --- shapes: 9-slice fills, rings, shadows and glows --------------------------------------------------------------------

local SLICE_STRETCHED = (Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched) or 0

-- A 9-slice texture of the Media sheet `key` on `parent`: white, tinted with `token`.
function Theme.Slice(parent, key, token, layer, alpha)
	local a = Assets.textures[key]
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetTexture(a.path)
	if a.slice and tex.SetTextureSliceMargins then
		tex:SetTextureSliceMargins(a.slice, a.slice, a.slice, a.slice)
		if tex.SetTextureSliceMode then tex:SetTextureSliceMode(SLICE_STRETCHED) end
	end
	Theme.Crisp(tex)
	tex._asset = key
	if token then Theme.Tint(tex, token, alpha) end
	return tex
end

local RADII = { [4] = true, [8] = true, [12] = true, [16] = true, [18] = true, [20] = true, [28] = true }

-- The Material 3 shape scale (docs/specs/ui-style.md §9.3, M12.6): shape name -> radius in points. "none" is a plain
-- square texture, "full" the pill. 18 and 20 are not in the scale: they draw the full shape of a control 36 and 40 points
-- high (Widgets.FullRadius, M12.7).
Theme.SHAPES = { none = 0, ["extra-small"] = 4, small = 8, medium = 12, large = 16, ["extra-large"] = 28, full = "full" }

-- The Media key of a shape: Theme.ShapeSlice("large") -> "rr_fill_16", Theme.ShapeSlice("small", "ring") -> "rr_ring_8".
-- `shape` is a name of Theme.SHAPES or a radius (4, 8, 12, 16, 18, 20, 28); kind is "fill" (default) or "ring". "full" is
-- the pill for a fill and has no ring (nil); "none" has no slice (nil: the caller uses a plain texture), nor has an
-- unknown shape.
function Theme.ShapeSlice(shape, kind)
	local r = Theme.SHAPES[shape] or shape
	kind = kind == "ring" and "ring" or "fill"
	if r == "full" then return kind == "fill" and "pill" or nil end
	if not RADII[r] then return nil end
	return "rr_" .. kind .. "_" .. r
end

-- Fill + 1 px ring (+ optional shadow) behind `frame`: returns the table of the regions. opts: radius (4|8|12|16|18|20|28),
-- fill token, border token, shadow (bool), shadowAlpha.
function Theme.Panel(frame, opts)
	opts = opts or {}
	local r = Theme.SHAPES[opts.radius] or opts.radius   -- a radius or an M3 shape name ("medium")
	r = RADII[r] and r or 12
	local p = {}
	if opts.shadow then
		p.shadow = Theme.Slice(frame, "shadow", "scrim", "BACKGROUND", opts.shadowAlpha or 0.6)
		p.shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -24, 16)
		p.shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 24, -32)
		Theme.Call(p.shadow, function(region) region:SetShown(Theme.EffectsOn()) end)   -- "Neon effects: off" is flat
	end
	if opts.fill ~= false then
		p.fill = Theme.Slice(frame, "rr_fill_" .. r, opts.fill or "surface-1", "BACKGROUND")
		p.fill:SetAllPoints(frame)
	end
	if opts.border ~= false then
		p.ring = Theme.Slice(frame, "rr_ring_" .. r, opts.border or "border", "BORDER")
		p.ring:SetAllPoints(frame)
	end
	if opts.highlight then
		-- "on the dark the depth comes from the light": a 1 px line of `highlight` along the top edge, inside the corners
		p.highlight = frame:CreateTexture(nil, "BORDER", nil, 1)
		Theme.Fill(p.highlight, "highlight")
		Theme.Crisp(p.highlight)
		p.highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", r, -1)
		p.highlight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -r, -1)
		p.highlight:SetHeight(Theme.Px(1, frame))
	end
	return p
end

-- What the saved data decides is read when it is loaded (login, /reload) and again when a value changes: the theme at
-- once, the effects (glows, shadows, text glow) at once, the fonts (a new font file is only read when the client starts).
if ns.Bus then
	ns.Bus:On("CONFIG_LOADED", function()
		Theme.Load()
		Theme.SetupFonts()
	end)
	ns.Bus:On("CONFIG_CHANGED", function(path)
		if path == "account.settings.theme" then Theme.Load()
		elseif path == "account.settings.effects" then Theme.Apply()
		elseif path == "account.settings.font" then Theme.SetupFonts() end
	end)
end

-- The probes of /accord debug (docs/specs/ui-style.md §7): what the client answered. Nothing here is a verdict: the owner
-- reads the lines in game.
function Theme.Probes()
	local res = {}
	res.scrollBox = _G.CreateScrollBoxListLinearView ~= nil and _G.ScrollUtil ~= nil
	res.dataProvider = _G.CreateDataProvider ~= nil
	local probe = Theme.probeFrame
	if not probe and CreateFrame then
		probe = CreateFrame("Frame")
		Theme.probeFrame = probe
		probe:Hide()
	end
	local tex = probe and probe:CreateTexture(nil, "BACKGROUND")
	res.slicing = tex ~= nil and tex.SetTextureSliceMargins ~= nil
	res.addBlend = tex ~= nil and tex.SetBlendMode ~= nil
	res.spriteSheet = tex ~= nil and tex.SetSpriteSheetCell ~= nil
	res.pixel = Theme.PixelSize()
	res.scale = UIParent and UIParent:GetEffectiveScale() or 1
	local refused = 0
	if tex then
		for _, path in ipairs(Assets.TexturePaths()) do
			if tex:SetTexture(path) == false then refused = refused + 1 end
		end
	end
	res.texturesRefused = refused
	return res
end

-- The section "Theme" of /accord debug: the look as saved and what the client answered to the probes (text and numbers only).
local function yesNo(v) return v and "yes" or "no" end
function Theme.DebugLines()
	local fallbacks, total = 0, 0
	for _, status in pairs(Theme.fontStatus) do
		total = total + 1
		if status == "game" then fallbacks = fallbacks + 1 end
	end
	local p = Theme.Probes()
	return {
		("Look: theme %s, effects %s, animations %s, font source %s; %d font object(s), %d use the game's font"):format(
			current, Theme.EffectsOn() and "on" or "off", Theme.AnimationsOn() and "on" or "off",
			(ns.Config and ns.Config.db and ns.Config:Get("account.settings.font")) or "addon", total, fallbacks),
		("Registered regions: %d; repaint failures: %d%s"):format(Theme.Count(), Theme.applyFailures or 0,
			Theme.lastFailure and (" (last: " .. Theme.lastFailure .. ")") or ""),
		("Client: 9-slice %s, blend modes %s, sprite sheets %s, ScrollBox %s, DataProvider %s"):format(yesNo(p.slicing),
			yesNo(p.addBlend), yesNo(p.spriteSheet), yesNo(p.scrollBox), yesNo(p.dataProvider)),
		("Screen: one pixel is %.4f UI units at scale %.2f; textures the client refused: %d"):format(p.pixel, p.scale, p.texturesRefused),
	}
end

if ns.addon and ns.addon.AddDebugSection then
	ns.addon:AddDebugSection("Theme", function() return Theme.DebugLines() end)
end

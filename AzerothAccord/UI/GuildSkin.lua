-- GuildSkin: the guild window (CommunitiesFrame) in the theme, while the Accord panel is open (M6.18, ADR 0003 update,
-- docs/specs/ui-style.md §3 "La finestra Gilda"). Lua 5.1; unprotected frames only.
-- The window around the panel (frame, title, close button, side tabs) takes the look of the rest of the interface:
--   * the Blizzard art of the frame is made transparent (SetAlpha 0, the old value is kept and put back when the panel
--     closes or another Blizzard tab is chosen): the frame's own textures, its NineSlice border, the title and the portrait;
--   * a themed frame of the addon (rounded fill, ring, shadow) is drawn behind everything, and the guild's name is written
--     in the theme's font; the close button keeps working and gets the theme's cross over it;
--   * each side tab, Blizzard's four and the Accord one, loses its Blizzard background and gets a themed tile (the selected one
--     in the accent colour); the icons of Blizzard's tabs stay, they are what the tabs do.
-- Nothing here replaces or calls a Blizzard function: only regions are made transparent and frames of the addon are drawn
-- (GT-04). Every part is looked up by name and by pcall, so a layout the addon does not know costs a part of the look and
-- never an error; /accord debug says which parts were found. Not verified in the real client (the names of the parts).
local ADDON_NAME, ns = ...
ns = ns or {}
local GuildSkin = {}
ns.GuildSkin, ns.modules = GuildSkin, ns.modules or {}
ns.modules.GuildSkin = GuildSkin
if ns.addon then ns.addon.GuildSkin = GuildSkin end

local L, Theme, Assets = ns.L, ns.Theme, ns.Assets
local type, ipairs, pairs, pcall, max = type, ipairs, pairs, pcall, math.max

-- Frames of the window that draw its Blizzard chrome (looked up by key on CommunitiesFrame and on its Inset).
GuildSkin.CHROME_KEYS = { "NineSlice", "TitleContainer", "PortraitContainer", "Bg", "TopTileStreaks", "TitleBg" }
GuildSkin.INSET_KEYS = { "NineSlice", "Bg" }
GuildSkin.TILE = 44    -- a side tab's tile
GuildSkin.TITLE_HEIGHT = 44

local function call(obj, method, ...)
	if type(obj) ~= "table" or type(obj[method]) ~= "function" then return false, nil end
	return pcall(obj[method], obj, ...)
end

local hidden = {}   -- region or frame -> its alpha before it was made transparent
local hooked = setmetatable({}, { __mode = "k" })   -- Blizzard buttons whose mouse scripts we already observe

-- Makes `region` transparent once, remembering its alpha. Returns true when it was one.
local function fade(region)
	if type(region) ~= "table" or type(region.SetAlpha) ~= "function" or hidden[region] ~= nil then return false end
	local ok, alpha = call(region, "GetAlpha")
	hidden[region] = (ok and type(alpha) == "number") and alpha or 1
	pcall(region.SetAlpha, region, 0)
	return true
end

local function restoreAll()
	for region, alpha in pairs(hidden) do
		pcall(region.SetAlpha, region, alpha)
		hidden[region] = nil
	end
end

-- Every texture a frame owns (its own regions), except `keep`.
local function fadeRegions(frame, keep)
	local n = 0
	if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return 0 end
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	if not ok then return 0 end
	for _, r in ipairs(regions) do
		if r ~= keep and type(r.GetObjectType) == "function" and r:GetObjectType() == "Texture" and fade(r) then n = n + 1 end
	end
	return n
end

local function icon(parent, name, size, token, layer)
	local t = parent:CreateTexture(nil, layer or "OVERLAY")
	t:SetTexture(Assets.textures.icons.path)
	t:SetTexCoord(Assets.IconCoords(name))
	t:SetSize(size, size)
	Theme.Tint(t, token)
	return t
end

---------------------------------------------------------------------------------------------------------------------
-- The tiles of the side tabs
---------------------------------------------------------------------------------------------------------------------
-- A themed tile behind `tab` (a frame child of `cf`, below the tab): fill + ring, the accent ring and the raised fill while
-- the tab is the checked one, a stronger ring under the mouse. `own`: the Accord tab (its checked state always counts).
-- `always`: shown all the time (the Accord tab without the game's frame); otherwise only while the skin is on, like the
-- tiles of Blizzard's tabs (the Accord tab with the game's frame, owner 2026-11-26).
local function newTile(cf, tab, own, always)
	-- the Accord tab's tile is a child of the tab (it hides with it); a Blizzard tab's is a child of the window
	local parent = own and tab or cf
	local tile = CreateFrame("Frame", nil, parent)
	tile:SetFrameLevel(max(0, (cf:GetFrameLevel() or 1)))   -- under the tab (level + 1)
	tile:SetSize(GuildSkin.TILE, GuildSkin.TILE)
	tile:SetPoint("CENTER", tab, "CENTER", 0, 0)
	tile.fill = Theme.Slice(tile, "rr_fill_12", "surface-2", "BACKGROUND")
	tile.fill:SetAllPoints(tile)
	tile.ring = Theme.Slice(tile, "rr_ring_12", "border", "BORDER")
	tile.ring:SetAllPoints(tile)
	-- the hover is a state layer; the tile of the selected tab is secondary-container, with no glow (§9)
	tile.over = ns.Widgets.StateLayer(tile, "text-1", { shape = "medium", layer = "BORDER", fade = false })
	tile.tab, tile.own, tile.always = tab, own and true or false, always and true or false
	function tile:Paint()
		local ok, c = call(self.tab, "GetChecked")
		local checked = ok and c and true or false
		-- while the Accord panel is open the Blizzard tab that was checked under it is not the selected one
		if checked and not self.own and GuildSkin.active then checked = false end
		self.checked = checked
		Theme.Tint(self.fill, checked and "secondary-container" or "surface-2")
		Theme.Tint(self.ring, "border")
		self.ring:SetShown(not checked)
		ns.Widgets.SetStateColor(self.over, checked and "on-secondary-container" or "text-1")
		ns.Widgets.SetState(self.over, self.hot and "hover" or nil)
	end
	function tile:Update()
		if not self.always then
			local ok, shown = call(self.tab, "IsShown")
			self:SetShown(GuildSkin.active == true and ok and shown == true)
		end
		self:Paint()
	end
	if type(tab.HookScript) == "function" then
		tab:HookScript("OnEnter", function() tile.hot = true tile:Paint() end)
		tab:HookScript("OnLeave", function() tile.hot = false tile:Paint() end)
		tab:HookScript("OnClick", function() tile:Paint() if ns.Compat and ns.Compat.After then ns.Compat.After(0, function() tile:Paint() end) end end)
		if not always then
			tab:HookScript("OnShow", function() tile:Update() end)
			tab:HookScript("OnHide", function() tile:Update() end)
		end
	end
	tile:Paint()
	return tile
end

-- The tile of `tab`, made on first use (also used by the Accord tab itself, which is always themed).
function GuildSkin.TileFor(cf, tab, own, always)
	GuildSkin.tiles = GuildSkin.tiles or {}
	local tile = GuildSkin.tiles[tab]
	if not tile then
		local ok, made = pcall(newTile, cf, tab, own, always)
		if not ok then return nil end
		tile = made
		GuildSkin.tiles[tab] = tile
	end
	return tile
end

---------------------------------------------------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------------------------------------------------
local function guildName(cf)
	local name = ns.Compat and ns.Compat.Guild and ns.Compat.Guild.GuildName and ns.Compat.Guild.GuildName()
	if type(name) == "string" and name ~= "" then return name end
	local title = type(cf) == "table" and cf.TitleContainer and cf.TitleContainer.TitleText
	local ok, text = call(title, "GetText")
	if ok and type(text) == "string" and text ~= "" then return text end
	return L["ADDON_TITLE"]
end

local function buildFrame(cf)
	local skin = CreateFrame("Frame", nil, cf)
	skin:SetAllPoints(cf)
	skin:SetFrameLevel(max(0, (cf:GetFrameLevel() or 1)))   -- under Blizzard's children (level + 1), over nothing
	skin.parts = Theme.Panel(skin, { radius = 12, fill = "bg", border = "border", shadow = true, highlight = true })
	skin.line = skin:CreateTexture(nil, "BORDER")
	Theme.Fill(skin.line, "border-subtle")
	skin.line:SetPoint("TOPLEFT", skin, "TOPLEFT", 12, -GuildSkin.TITLE_HEIGHT)
	skin.line:SetPoint("TOPRIGHT", skin, "TOPRIGHT", -12, -GuildSkin.TITLE_HEIGHT)
	skin.line:SetHeight(Theme.Px(1))
	skin.logo = skin:CreateTexture(nil, "OVERLAY")
	skin.logo:SetTexture(Assets.logos.logo_64.path)
	skin.logo:SetSize(24, 24)
	skin.logo:SetPoint("TOPLEFT", skin, "TOPLEFT", 14, -10)
	if skin.logo.SetMaskTexture then skin.logo:SetMaskTexture(Assets.textures.circle.path) end
	skin.title = Theme.NewText(skin, "H1", "text-1", "OVERLAY")
	skin.title:SetPoint("LEFT", skin.logo, "RIGHT", 10, 0)
	skin.title:SetJustifyH("LEFT")
	skin:Hide()
	return skin
end

-- Puts the theme's cross over Blizzard's close button (which keeps its job, a click goes through the overlay to it); without
-- one, the cross sits at the corner and the window closes with Esc as before.
local function placeCross(cf, skin)
	local close = cf.CloseButton
	if type(close) == "table" and type(close.SetAlpha) == "function" then
		if not skin.overlay then
			skin.overlay = CreateFrame("Frame", nil, cf)
			skin.overlay:EnableMouse(false)
			skin.overlay:SetSize(28, 28)
			skin.cross = icon(skin.overlay, "cross", 20, "text-2", "OVERLAY")
			skin.cross:SetPoint("CENTER", skin.overlay, "CENTER", 0, 0)
		end
		skin.overlay:ClearAllPoints()
		skin.overlay:SetPoint("CENTER", close, "CENTER", 0, 0)
		skin.overlay:SetFrameLevel((close:GetFrameLevel() or 1) + 1)
		skin.overlay:Show()
		skin.hasClose = true
		fade(close.Icon); fade(close.Border); fade(close.Background)
		fadeRegions(close)
		if type(close.HookScript) == "function" and not hooked[close] then
			hooked[close] = true
			close:HookScript("OnEnter", function() Theme.Tint(skin.cross, "text-1") end)
			close:HookScript("OnLeave", function() Theme.Tint(skin.cross, "text-2") end)
		end
	else
		if skin.overlay then skin.overlay:Hide() end
		skin.hasClose = false
	end
end

-- Dresses the window. `tabs` are the Blizzard side tabs that exist, `own` the Accord tab. Returns the number of parts found.
function GuildSkin.Apply(cf, tabs, own)
	if type(cf) ~= "table" then return 0 end
	GuildSkin.skin = GuildSkin.skin or buildFrame(cf)
	local skin, found = GuildSkin.skin, 0
	for _, key in ipairs(GuildSkin.CHROME_KEYS) do
		if fade(cf[key]) then found = found + 1 end
	end
	found = found + fadeRegions(cf)
	local inset = cf.Inset or cf.InsetFrame
	if type(inset) == "table" then
		for _, key in ipairs(GuildSkin.INSET_KEYS) do
			if fade(inset[key]) then found = found + 1 end
		end
		found = found + fadeRegions(inset)
	end
	placeCross(cf, skin)
	for _, tab in ipairs(tabs or {}) do
		-- the icon of a Blizzard tab stays; every other texture of the tab (its background, border, glow) goes
		local keep = tab.Icon or tab.icon
		fadeRegions(tab, keep)
		local tile = GuildSkin.TileFor(cf, tab, tab == own)
		if tile then found = found + 1 end
	end
	skin.title:SetText(guildName(cf))
	skin:Show()
	GuildSkin.active = true
	GuildSkin.found = found
	for _, tab in ipairs(tabs or {}) do
		local tile = GuildSkin.tiles and GuildSkin.tiles[tab]
		if tile then tile:Update() end
	end
	if own then GuildSkin.Repaint() end
	return found
end

-- Puts the Blizzard look back (another Blizzard tab chosen, the panel closed, the window closed).
function GuildSkin.Revert(tabs)
	if GuildSkin.skin then
		GuildSkin.skin:Hide()
		if GuildSkin.skin.overlay then GuildSkin.skin.overlay:Hide() end
	end
	restoreAll()
	GuildSkin.active = false
	for _, tab in ipairs(tabs or {}) do
		local tile = GuildSkin.tiles and GuildSkin.tiles[tab]
		if tile then tile:Update() end
	end
	GuildSkin.Repaint()
end

function GuildSkin.Repaint()
	for _, tile in pairs(GuildSkin.tiles or {}) do tile:Paint() end
end

function GuildSkin.IsActive() return GuildSkin.active == true end

function GuildSkin.DebugLines()
	local tiles = 0
	for _, tile in pairs(GuildSkin.tiles or {}) do if tile:IsShown() then tiles = tiles + 1 end end
	return { ("Guild window skin: %s, %d Blizzard part(s) made transparent, %d tab tile(s), close button %s"):format(
		GuildSkin.active and "on" or "off", GuildSkin.found or 0, tiles,
		GuildSkin.skin and (GuildSkin.skin.hasClose and "found" or "not found") or "not looked at yet") }
end

if ns.addon and ns.addon.AddDebugSection then ns.addon:AddDebugSection("Guild window skin", function() return GuildSkin.DebugLines() end) end

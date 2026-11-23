-- Widget kit, part 2: Switch, Slider, Select (a dropdown without UIDropDownMenu, which taints), Menu (a popup of checks, M6.13),
-- Snackbar, Skeleton and the class mark (the glowing square next to a player's name): the remaining components of docs/specs/ui-style.md §3 (M6.11).
-- Adapted from Finland Dragon Credit Points (UI/Widgets/Controls.lua), same owner, GPL-3.0 (ADR 0021). Ordinary unprotected
-- frames; every colour is a theme token; text comes in already translated. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Kit, Theme, Motion, Assets = ns.Kit, ns.Theme, ns.Motion, ns.Assets
local max, min, floor = math.max, math.min, math.floor

-- --- Switch -----------------------------------------------------------------------------------------------------------

-- A 44 x 26 pill: the track is surface-3 (accent when on), the thumb a circle that slides in 200 ms. opts: on (bool),
-- onChange(on) after a click or :SetOn(v) without `silent`. :IsOn(), :SetOn(v, silent), :SetEnabled(bool).
function Kit.Switch(parent, opts)
	opts = opts or {}
	local b = CreateFrame("CheckButton", nil, parent)
	b:SetSize(44, 26)
	b.track = Theme.Slice(b, "rr_fill_12", "surface-3", "BACKGROUND")
	b.track:SetAllPoints(b)
	b.ring = Theme.Slice(b, "rr_ring_12", "border", "BORDER")
	b.ring:SetAllPoints(b)
	b.thumb = b:CreateTexture(nil, "ARTWORK")
	b.thumb:SetTexture(Assets.textures.circle.path)
	b.thumb:SetSize(18, 18)
	Theme.Tint(b.thumb, "text-2")
	b.on = false
	local function thumbAt(x)
		b.thumb:ClearAllPoints()
		b.thumb:SetPoint("LEFT", b, "LEFT", x, 0)
	end
	thumbAt(4)
	local function paint()
		if b.on then
			Theme.Tint(b.track, "accent"); Theme.Tint(b.ring, "accent"); Theme.Tint(b.thumb, "on-accent")
		else
			Theme.Tint(b.track, "surface-3"); Theme.Tint(b.ring, "border"); Theme.Tint(b.thumb, "text-2")
		end
	end
	function b:IsOn() return self.on end
	function b:SetOn(v, silent)
		v = v and true or false
		if v == self.on then return end
		self.on = v
		paint()
		local to, from = v and 22 or 4, v and 4 or 22
		Motion.Slide(self.thumb, to - from, 0, Motion.BASE, function() thumbAt(to) end)
		if not silent and opts.onChange then opts.onChange(v) end
	end
	local setEnabled = b.SetEnabled
	function b:SetEnabled(enabled)
		setEnabled(self, enabled and true or false)
		self:SetAlpha(enabled and 1 or 0.45)
	end
	b:SetScript("OnClick", function(self)
		if self:IsEnabled() then self:SetOn(not self.on) end
	end)
	if opts.on then b.on = true; paint(); thumbAt(22) else paint() end
	return b
end

-- --- Slider -----------------------------------------------------------------------------------------------------------

-- A horizontal slider on a 4 pt track with the theme gradient and a round thumb. opts: min, max, step, value, width,
-- onChange(value, user). :Set(v) (silent), :GetValue(). The value is rounded to the step.
function Kit.Slider(parent, opts)
	opts = opts or {}
	local lo, hi, step = opts.min or 0, opts.max or 100, opts.step or 1
	local s = CreateFrame("Slider", nil, parent)
	s:SetSize(opts.width or 200, 20)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s.track = s:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(s.track, "border")
	s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.track:SetHeight(4)
	s.fill = s:CreateTexture(nil, "ARTWORK")
	Theme.Fill(s.fill, "accent")
	Theme.Call(s.fill, function(region)
		if region.SetGradient and CreateColor then
			local r1, g1, b1 = Theme.Color("accent")
			local r2, g2, b2 = Theme.Color("accent-2")
			region:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
		end
	end)
	s.fill:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.fill:SetHeight(4)
	s:SetThumbTexture(Assets.textures.circle.path)
	s.thumb = s:GetThumbTexture()
	if s.thumb then
		s.thumb:SetSize(16, 16)
		Theme.Tint(s.thumb, "text-1")
	end
	local function refresh()
		local v = s:GetValue()
		local span = hi - lo
		local f = span > 0 and (v - lo) / span or 0
		s.fill:SetWidth(max((s:GetWidth() or opts.width or 200) * f, 1))
	end
	function s:Set(v)   -- silent
		v = min(max(tonumber(v) or lo, lo), hi)
		if step > 0 then v = lo + floor((v - lo) / step + 0.5) * step end
		self:SetValue(v)
		refresh()
	end
	s:SetScript("OnValueChanged", function(self, value, user)
		refresh()
		if opts.onChange then opts.onChange(value, user and true or false) end
	end)
	s:SetScript("OnSizeChanged", refresh)
	s:Set(opts.value or lo)
	return s
end

-- --- Select (a dropdown without UIDropDownMenu) -------------------------------------------------------------------------

-- A field that shows the chosen text; a click opens a list below it (a ChoiceList on the DIALOG strata) and a click
-- outside closes it. choices = { { id, text, token? } }. opts: width, rows (6), choices, value, onSelect(id), placeholder.
-- :SetChoices(list), :Select(id, silent), :Selected(), :Open(), :Close(), :IsOpen().
function Kit.Select(parent, opts)
	opts = opts or {}
	local width, rows = opts.width or 200, opts.rows or 6
	local sel = CreateFrame("Button", nil, parent)
	sel:SetSize(width, 28)
	sel.fill = Theme.Slice(sel, "rr_fill_8", "surface-2", "BACKGROUND")
	sel.fill:SetAllPoints(sel)
	sel.ring = Theme.Slice(sel, "rr_ring_8", "border", "BORDER")
	sel.ring:SetAllPoints(sel)
	sel.label = Theme.NewText(sel, "Body", "text-1")
	sel.label:SetPoint("LEFT", sel, "LEFT", 10, 0)
	sel.label:SetPoint("RIGHT", sel, "RIGHT", -26, 0)
	sel.label:SetJustifyH("LEFT")
	sel.arrow = sel:CreateTexture(nil, "OVERLAY")
	sel.arrow:SetTexture(Assets.textures.icons.path)
	sel.arrow:SetTexCoord(Assets.IconCoords("chevron"))
	sel.arrow:SetSize(14, 14)
	sel.arrow:SetPoint("RIGHT", sel, "RIGHT", -8, 0)
	Theme.Tint(sel.arrow, "text-3")
	Motion.Rotate(sel.arrow, -math.pi / 2, 0)   -- the chevron points right in the sheet: down while closed
	sel.choices = opts.choices or {}

	-- the popup: a catcher over the screen (a click outside closes) and the list under the field
	sel.popup = CreateFrame("Frame", nil, sel)
	sel.popup:SetFrameStrata("DIALOG")
	sel.popup:SetToplevel(true)
	sel.popup:SetPoint("TOPLEFT", sel, "BOTTOMLEFT", 0, -4)
	sel.popup:Hide()
	sel.catcher = CreateFrame("Button", nil, sel.popup)
	sel.catcher:SetFrameStrata("DIALOG")
	sel.catcher:SetAllPoints(UIParent)
	sel.catcher:SetFrameLevel(sel.popup:GetFrameLevel() - 1)
	sel.catcher:SetScript("OnClick", function() sel:Close() end)
	sel.list = Kit.ChoiceList(sel.popup, { rows = rows, rowHeight = 24, width = width, onSelect = function(id) sel:Select(id) end })
	sel.list:SetPoint("TOPLEFT", sel.popup, "TOPLEFT", 0, 0)
	sel.popup:SetSize(width, rows * 24 + 8)
	Theme.Tint(sel.list.ring, "border-strong")

	local function textOf(id)
		for _, c in ipairs(sel.choices) do if c.id == id then return c.text end end
	end
	local function paint()
		local text = sel.value ~= nil and textOf(sel.value) or nil
		sel.label:SetText(text or opts.placeholder or "")
		Theme.Text(sel.label, text and "text-1" or "text-3")
	end
	function sel:SetChoices(list)
		self.choices = list or {}
		self.list:SetChoices(self.choices)
		if self.value ~= nil and textOf(self.value) == nil then self.value = nil end
		if self.value ~= nil then self.list:Select(self.value) end
		paint()
	end
	function sel:Select(id, silent)
		if textOf(id) == nil then return false end
		local changed = self.value ~= id
		self.value = id
		self.list:Select(id)
		paint()
		self:Close()
		if changed and not silent and opts.onSelect then opts.onSelect(id) end
		return true
	end
	function sel:Selected() return self.value end
	function sel:IsOpen() return self.popup:IsShown() end
	function sel:Open()
		if not self:IsEnabled() or #self.choices == 0 or self:IsOpen() then return end
		self.popup:Show()
		Motion.FadeIn(self.popup, Motion.BASE)
		Motion.Rotate(self.arrow, math.pi / 2, Motion.BASE)   -- up while open
		Theme.Tint(self.ring, "accent")
	end
	function sel:Close()
		if not self.popup:IsShown() then return end
		self.popup:Hide()
		Motion.Rotate(self.arrow, -math.pi / 2, Motion.BASE)
		Theme.Tint(self.ring, "border")
	end
	sel:SetScript("OnClick", function(self) if self:IsOpen() then self:Close() else self:Open() end end)
	sel:SetScript("OnHide", function(self) self:Close() end)
	sel:SetChoices(sel.choices)
	if opts.value ~= nil then sel:Select(opts.value, true) end
	return sel
end

-- --- Snackbar ---------------------------------------------------------------------------------------------------------

-- A message at the bottom right of `host` (380 wide, raised, a coloured dot for the tone), shown for 4 s with a fade.
-- tone: "accent" | "ok" | "warn" | "err". :Say(text, tone, seconds), :Dismiss(), :Message() (:Show and :Hide stay the
-- frame's own).
local TONES = { accent = "accent", ok = "ok", warn = "warn", err = "err" }
function Kit.Snackbar(host)
	local sb = CreateFrame("Frame", nil, host)
	sb:SetSize(380, 44)
	sb:SetFrameStrata("DIALOG")
	sb:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -20, 20)
	sb.parts = Theme.Panel(sb, { radius = 12, fill = "raised", border = "border-strong", shadow = true, highlight = true })
	sb.dot = sb:CreateTexture(nil, "ARTWORK")
	sb.dot:SetTexture(Assets.textures.circle.path)
	sb.dot:SetSize(10, 10)
	sb.dot:SetPoint("LEFT", sb, "LEFT", 16, 0)
	sb.text = Theme.NewText(sb, "Body", "text-1")
	sb.text:SetPoint("LEFT", sb, "LEFT", 36, 0)
	sb.text:SetPoint("RIGHT", sb, "RIGHT", -16, 0)
	sb.text:SetJustifyH("LEFT")
	sb.ticket = 0
	sb:Hide()
	function sb:Say(text, tone, seconds)
		self.ticket = self.ticket + 1
		local mine = self.ticket
		self.text:SetText(text or "")
		Theme.Tint(self.dot, TONES[tone or "accent"] or "accent")
		self:SetFrameLevel(host:GetFrameLevel() + 20)
		Motion.FadeIn(self, Motion.BASE)
		C_Timer.After(seconds or 4, function()
			if self.ticket == mine and self:IsShown() then Motion.FadeOut(self, Motion.BASE) end
		end)
	end
	function sb:Dismiss()
		self.ticket = self.ticket + 1
		Motion.Fade(self, 0, 0)
		self:Hide()
		self:SetAlpha(1)
	end
	function sb:Message() return self.text:GetText() end
	return sb
end

-- --- Skeleton ---------------------------------------------------------------------------------------------------------

-- A loading placeholder: a rounded surface-3 rectangle whose alpha pulses while it is shown (still with animations off).
-- The data of the addon is local, so this serves the few things that take a moment (a sync, the item cache).
function Kit.Skeleton(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width or 120, height or 14)
	f.fill = Theme.Slice(f, "rr_fill_8", "surface-3", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.pulse = Motion.Pulse(f, 0.35, 1, 0.9)
	f:SetScript("OnShow", function() f.pulse.Start() end)
	f:SetScript("OnHide", function() f.pulse.Stop() end)
	return f
end

-- --- Class mark -------------------------------------------------------------------------------------------------------

-- The square of 10 pt next to a player's name, with the small glow of the site ("the name in the class colour with a
-- square that shines"): returns the texture; `.glow` is the glow behind it. Both stay hidden until Kit.PaintClassMark gives
-- them the class colour (a colour of the game, not of a theme: Theme.Apply leaves it alone).
function Kit.ClassMark(parent, size)
	size = size or 10
	local square = Theme.Slice(parent, "rr_fill_8", nil, "ARTWORK")
	square:SetSize(size, size)
	square:Hide()
	square.glow = Theme.Glow(parent, "glow_s", nil, { layer = "BACKGROUND" })
	square.glow:SetSize(size * 2.6, size * 2.6)
	square.glow:SetPoint("CENTER", square, "CENTER", 0, 0)
	Theme.GlowShow(square.glow, false)
	return square
end

-- Colours the square and its glow (class colours come from the game: r, g, b in 0..1) and shows them.
function Kit.PaintClassMark(square, r, g, b)
	square:SetVertexColor(r, g, b, 1)
	square:Show()
	if square.glow then
		square.glow:SetVertexColor(r, g, b, 0.5)
		Theme.GlowShow(square.glow, true)
	end
end

-- Hides the square and its glow (a pooled row that shows no class).
function Kit.ClearClassMark(square)
	square:Hide()
	if square.glow then Theme.GlowShow(square.glow, false) end
end

-- --- Menu -------------------------------------------------------------------------------------------------------------

-- A popup list under an anchor, for the choices that are checks rather than one pick (the Roster's column chooser): no
-- UIDropDownMenu, which taints. items = { { text, checked, onClick(item), keepOpen, header, token? } }: a click runs onClick and
-- closes the menu, unless the item has keepOpen (its check flips and the menu stays: several columns in a row); a `header`
-- is a heading, not a choice. One menu is open at a time; a click anywhere else or Esc closes it.
-- Kit.Menu.Show(anchor, items, width) -> the frame, .Hide(), .IsOpen(), .frame (rows in .frame.rows, the items in .frame.items).
local Menu = {}
Kit.Menu = Menu
local MENU_ROW, MENU_WIDTH, MENU_NAME = 28, 220, "AzerothAccordKitMenu"

local function buildMenu()
	local menu = CreateFrame("Frame", MENU_NAME, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu.parts = Theme.Panel(menu, { radius = 8, fill = "raised", border = "border-strong", shadow = true })
	menu.rows, menu.items = {}, {}
	menu.catcher = CreateFrame("Button", nil, UIParent)
	menu.catcher:SetAllPoints(UIParent)
	menu.catcher:SetFrameStrata("FULLSCREEN")
	menu.catcher:SetScript("OnClick", function() Menu.Hide() end)
	menu.catcher:Hide()
	menu:SetScript("OnHide", function() menu.catcher:Hide() end)
	menu:Hide()
	Kit.CloseOnEscape(MENU_NAME)
	return menu
end

local function menuRow(menu, i)
	local row = CreateFrame("Button", nil, menu)
	row:SetHeight(MENU_ROW)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(row.hover, "surface-3", 0)
	row.hover:SetAllPoints(row)
	row.check = row:CreateTexture(nil, "ARTWORK")
	row.check:SetTexture(Assets.textures.icons.path)
	row.check:SetTexCoord(Assets.IconCoords("check"))
	row.check:SetSize(14, 14)
	row.check:SetPoint("LEFT", row, "LEFT", 10, 0)
	Theme.Tint(row.check, "accent-text")
	row.label = Theme.NewText(row, "Body", "text-1")
	row.label:SetPoint("LEFT", row, "LEFT", 32, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row.label:SetJustifyH("LEFT")
	row:SetScript("OnEnter", function(self) if self.item and not self.item.header then Theme.Fill(self.hover, "surface-3", 1) end end)
	row:SetScript("OnLeave", function(self) Theme.Fill(self.hover, "surface-3", 0) end)
	row:SetScript("OnClick", function(self)
		local it = self.item
		if not it or it.header then return end
		if it.onClick then it.onClick(it) end
		if it.keepOpen then
			it.checked = not it.checked
			self.check:SetShown(it.checked == true)
		else
			Menu.Hide()
		end
	end)
	menu.rows[i] = row
	return row
end

function Menu.Show(anchor, items, width)
	local menu = Menu.frame
	if not menu then menu = buildMenu(); Menu.frame = menu end
	menu.items, menu.width = items or {}, width or MENU_WIDTH
	menu:SetSize(menu.width, 12 + #menu.items * MENU_ROW)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	for i, item in ipairs(menu.items) do
		local row = menu.rows[i] or menuRow(menu, i)
		row.item = item
		row:SetWidth(menu.width - 8)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -6 - (i - 1) * MENU_ROW)
		row.check:SetShown(item.checked == true and not item.header)
		row.label:SetText(item.text or "")
		Theme.Text(row.label, item.header and "accent-text" or item.token or "text-1")
		Theme.Fill(row.hover, "surface-3", 0)
		row:Show()
	end
	for i = #menu.items + 1, #menu.rows do menu.rows[i].item = nil; menu.rows[i]:Hide() end
	menu:SetFrameLevel(max((anchor.GetFrameLevel and anchor:GetFrameLevel() or 1) + 10, 1))
	menu.catcher:Show()
	menu:Show()
	Motion.FadeIn(menu, Motion.FAST)
	return menu
end

function Menu.Hide()
	if Menu.frame then Menu.frame:Hide() end
end

function Menu.IsOpen()
	return Menu.frame ~= nil and Menu.frame:IsShown() == true
end

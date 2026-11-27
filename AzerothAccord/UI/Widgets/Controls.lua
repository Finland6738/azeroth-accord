-- Widget kit, part 2: Switch, Slider, Select (a dropdown without UIDropDownMenu, which taints), Menu (a popup of checks, M6.13),
-- Snackbar, Skeleton and the class mark (the glowing square next to a player's name): the remaining components of
-- docs/specs/ui-style.md §3 (M6.11), measured and coloured as §9.6 says (Material 3, M12.7).
-- Adapted from Finland Dragon Credit Points (UI/Widgets/Controls.lua), same owner, GPL-3.0 (ADR 0021). Ordinary unprotected
-- frames; every colour is a theme token; text comes in already translated. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme, Motion, Assets = ns.Widgets, ns.Theme, ns.Motion, ns.Assets
local max, min, floor = math.max, math.min, math.floor

-- --- Switch -----------------------------------------------------------------------------------------------------------

-- The switch of Material 3 (docs/specs/ui-style.md §9.6): a track of 52 x 32 with the full shape. Off: the track is
-- raised with an outline of 2 points (border-strong) and the handle (text-2) is 16 across; on: the track is accent and
-- the handle (on-accent) 24. The handle's centre slides from 16 to 36 points in 200 ms; a state layer of 40 around it
-- shows the mouse. Disabled: the handle at 38 %, the track and outline at 12 % of text-1. opts: on (bool), onChange(on)
-- after a click or :SetOn(v) without `silent`. :IsOn(), :SetOn(v, silent), :SetEnabled(bool).
local SWITCH = { off = { size = 16, centre = 16 }, on = { size = 24, centre = 36 } }
function Widgets.Switch(parent, opts)
	opts = opts or {}
	local b = CreateFrame("CheckButton", nil, parent)
	b:SetSize(52, 32)
	b.track = Theme.Slice(b, "rr_fill_16", "raised", "BACKGROUND")
	b.track:SetAllPoints(b)
	b.ring = Theme.Slice(b, "rr_ring2_16", "border-strong", "BORDER")
	b.ring:SetAllPoints(b)
	b.thumb = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.thumb:SetTexture(Assets.textures.circle.path)
	Theme.Tint(b.thumb, "text-2")
	b.over = Widgets.StateLayer(b, "text-1", { shape = "circle", layer = "ARTWORK" })
	b.over:ClearAllPoints()
	b.over:SetSize(40, 40)
	b.over:SetPoint("CENTER", b.thumb, "CENTER", 0, 0)
	Widgets.TrackState(b, b.over)
	b.on = false
	-- the handle as it is `on` or off, with its centre at `centre` points from the left
	local function thumbAt(centre)
		local look = b.on and SWITCH.on or SWITCH.off
		b.thumb:SetSize(look.size, look.size)
		b.thumb:ClearAllPoints()
		b.thumb:SetPoint("LEFT", b, "LEFT", centre - look.size / 2, 0)
	end
	local function paint()
		local off = not b:IsEnabled()
		if off then
			Theme.Tint(b.track, "text-1", Theme.STATE.disabledContainer)
			Theme.Tint(b.ring, "text-1", Theme.STATE.disabledContainer)
		else
			Theme.Tint(b.track, b.on and "accent" or "raised")
			Theme.Tint(b.ring, "border-strong")
		end
		b.ring:SetShown(not b.on)
		Theme.Tint(b.thumb, b.on and "on-accent" or "text-2")
		b.thumb:SetAlpha(off and Theme.STATE.disabledContent or 1)
		Widgets.SetStateColor(b.over, b.on and "accent" or "text-1")
	end
	function b:IsOn() return self.on end
	function b:SetOn(v, silent)
		v = v and true or false
		if v == self.on then return end
		local from = (self.on and SWITCH.on or SWITCH.off).centre
		self.on = v
		local to = (v and SWITCH.on or SWITCH.off).centre
		paint()
		thumbAt(from)
		Motion.Slide(self.thumb, to - from, 0, Motion.BASE, function() thumbAt(to) end)
		if not silent and opts.onChange then opts.onChange(v) end
	end
	local setEnabled = b.SetEnabled
	function b:SetEnabled(enabled)
		setEnabled(self, enabled and true or false)
		if not enabled then self.hot, self.pressed = false, false end
		paint()
		Widgets.SetState(self.over, Widgets.StateOf(self))
	end
	b:SetScript("OnClick", function(self)
		if self:IsEnabled() then self:SetOn(not self.on) end
	end)
	b.on = opts.on and true or false
	paint()
	thumbAt((b.on and SWITCH.on or SWITCH.off).centre)
	return b
end

-- --- Slider -----------------------------------------------------------------------------------------------------------

-- A horizontal slider: a track of 4 points in surface-3, a flat accent fill and a round thumb. opts: min, max, step, value, width,
-- onChange(value, user). :Set(v) (silent), :GetValue(). The value is rounded to the step.
function Widgets.Slider(parent, opts)
	opts = opts or {}
	local lo, hi, step = opts.min or 0, opts.max or 100, opts.step or 1
	local s = CreateFrame("Slider", nil, parent)
	s:SetSize(opts.width or 200, 20)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s.track = s:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(s.track, "surface-3")
	s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.track:SetHeight(4)
	s.fill = s:CreateTexture(nil, "ARTWORK")
	Theme.Fill(s.fill, "accent")
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

-- A field that shows the chosen text; a click opens a menu below it (a ChoiceList on the DIALOG strata) and a click
-- outside closes it. The field looks like a text field (docs/specs/ui-style.md §9.6): radius 4, surface-2, an outline of
-- 1 point and 2 points of accent while it is open; 32 high (it sits in toolbars and forms: the dense size). The menu is
-- as wide as the field, at least 112, with rows of 32, and no taller than its choices.
-- choices = { { id, text, token? } }. opts: width, height (32), rows (6), choices, value, onSelect(id), placeholder.
-- :SetChoices(list), :Select(id, silent), :Selected(), :Open(), :Close(), :IsOpen(), :SetEnabled(bool).
function Widgets.Select(parent, opts)
	opts = opts or {}
	local width, rows = opts.width or 200, opts.rows or 6
	local sel = CreateFrame("Button", nil, parent)
	sel:SetSize(width, opts.height or 32)
	sel.fill = Theme.Slice(sel, "rr_fill_4", "surface-2", "BACKGROUND")
	sel.fill:SetAllPoints(sel)
	sel.ring = Theme.Slice(sel, "rr_ring_4", "border", "BORDER")
	sel.ring:SetAllPoints(sel)
	sel.focusRing = Theme.Slice(sel, "rr_ring2_4", "accent", "BORDER")
	sel.focusRing:SetAllPoints(sel)
	sel.focusRing:Hide()
	sel.label = Theme.NewText(sel, "Body", "text-1")
	sel.label:SetPoint("LEFT", sel, "LEFT", 12, 0)
	sel.label:SetPoint("RIGHT", sel, "RIGHT", -34, 0)
	sel.label:SetJustifyH("LEFT")
	sel.arrow = Widgets.Icon(sel, "chevron", 18, "text-2", "OVERLAY")
	sel.arrow:SetPoint("RIGHT", sel, "RIGHT", -8, 0)
	Motion.Rotate(sel.arrow, -math.pi / 2, 0)   -- the chevron of the atlas points right: down while closed
	sel.choices = opts.choices or {}

	-- the popup: a catcher over the screen (a click outside closes) and the menu under the field
	local menuWidth = max(112, width)
	sel.popup = CreateFrame("Frame", nil, sel)
	sel.popup:SetFrameStrata("DIALOG")
	sel.popup:SetToplevel(true)
	sel.popup:SetClampedToScreen(true)
	sel.popup:SetPoint("TOPLEFT", sel, "BOTTOMLEFT", 0, -4)
	sel.popup:Hide()
	sel.catcher = CreateFrame("Button", nil, sel.popup)
	sel.catcher:SetFrameStrata("DIALOG")
	sel.catcher:SetAllPoints(UIParent)
	sel.catcher:SetFrameLevel(sel.popup:GetFrameLevel() - 1)
	sel.catcher:SetScript("OnClick", function() sel:Close() end)
	sel.list = Widgets.ChoiceList(sel.popup, { rows = rows, width = menuWidth, menu = true,
		onSelect = function(id) sel:Select(id) end })
	sel.list:SetPoint("TOPLEFT", sel.popup, "TOPLEFT", 0, 0)

	local function textOf(id)
		for _, c in ipairs(sel.choices) do if c.id == id then return c.text end end
	end
	local function size()
		local h = max(1, min(rows, #sel.choices)) * sel.list.rowH + 8
		sel.list:SetHeight(h)
		sel.popup:SetSize(menuWidth, h)
	end
	local function paint()
		local text = sel.value ~= nil and textOf(sel.value) or nil
		sel.label:SetText(text or opts.placeholder or "")
		Theme.Text(sel.label, text and "text-1" or "text-3")
	end
	local function outline()
		local off, open = not sel:IsEnabled(), sel.popup:IsShown()
		sel.focusRing:SetShown(open and not off)
		sel.ring:SetShown(not open or off)
		if off then Theme.Tint(sel.ring, "text-1", Theme.STATE.disabledContainer)
		else Theme.Tint(sel.ring, sel.hot and "border-strong" or "border") end
	end
	function sel:SetChoices(list)
		self.choices = list or {}
		self.list:SetChoices(self.choices)
		size()
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
		outline()
	end
	function sel:Close()
		if not self.popup:IsShown() then return end
		self.popup:Hide()
		Motion.Rotate(self.arrow, -math.pi / 2, Motion.BASE)
		outline()
	end
	local setEnabled = sel.SetEnabled
	function sel:SetEnabled(enabled)
		setEnabled(self, enabled and true or false)
		if not enabled then self.hot = false; self:Close() end
		self.label:SetAlpha(enabled and 1 or Theme.STATE.disabledContent)
		self.arrow:SetAlpha(enabled and 1 or Theme.STATE.disabledContent)
		outline()
	end
	sel:SetScript("OnClick", function(self) if self:IsOpen() then self:Close() else self:Open() end end)
	sel:SetScript("OnHide", function(self) self:Close() end)
	sel:SetScript("OnEnter", function(self) self.hot = true; outline() end)
	sel:SetScript("OnLeave", function(self) self.hot = false; outline() end)
	sel:SetChoices(sel.choices)
	if opts.value ~= nil then sel:Select(opts.value, true) end
	return sel
end

-- --- Snackbar ---------------------------------------------------------------------------------------------------------

-- A short confirmation at the bottom right of `host` (docs/specs/ui-style.md §9.6): 380 x 48, radius 4,
-- inverse-surface with the text in inverse-on-surface, shown for 4 s with a fade. :Say(text, tone, seconds) (the tone
-- of M6.11 is accepted and not drawn: a snackbar has one look), :Dismiss(), :Message() (:Show and :Hide stay the
-- frame's own).
function Widgets.Snackbar(host)
	local sb = CreateFrame("Frame", nil, host)
	sb:SetSize(380, 48)
	sb:SetFrameStrata("DIALOG")
	sb:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -16, 16)
	sb.parts = Theme.Panel(sb, { radius = "extra-small", fill = "inverse-surface", border = false, shadow = true })
	sb.text = Theme.NewText(sb, "Body", "inverse-on-surface")
	sb.text:SetPoint("LEFT", sb, "LEFT", 16, 0)
	sb.text:SetPoint("RIGHT", sb, "RIGHT", -16, 0)
	sb.text:SetJustifyH("LEFT")
	sb.ticket = 0
	sb:Hide()
	function sb:Say(text, _, seconds)
		self.ticket = self.ticket + 1
		local mine = self.ticket
		self.text:SetText(text or "")
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
function Widgets.Skeleton(parent, width, height)
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
-- square that shines"): returns the texture; `.glow` is the glow behind it. Both stay hidden until Widgets.PaintClassMark gives
-- them the class colour (a colour of the game, not of a theme: Theme.Apply leaves it alone).
function Widgets.ClassMark(parent, size)
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
function Widgets.PaintClassMark(square, r, g, b)
	square:SetVertexColor(r, g, b, 1)
	square:Show()
	if square.glow then
		square.glow:SetVertexColor(r, g, b, 0.5)
		Theme.GlowShow(square.glow, true)
	end
end

-- Hides the square and its glow (a pooled row that shows no class).
function Widgets.ClearClassMark(square)
	square:Hide()
	if square.glow then Theme.GlowShow(square.glow, false) end
end

-- --- Menu -------------------------------------------------------------------------------------------------------------

-- A popup list under an anchor, for the choices that are checks rather than one pick (the Roster's column chooser): no
-- UIDropDownMenu, which taints. The dense menu of Material 3 (docs/specs/ui-style.md §9.6): surface-2, radius 4, a
-- shadow, 112 to 280 wide (220 by default), rows of 32 with 12 points each side, the check (18) before the label.
-- items = { { text, checked, onClick(item), keepOpen, header, token? } }: a click runs onClick and closes the menu,
-- unless the item has keepOpen (its check flips and the menu stays: several columns in a row); a `header` is a heading,
-- not a choice. One menu is open at a time; a click anywhere else or Esc closes it.
-- Widgets.Menu.Show(anchor, items, width) -> the frame, .Hide(), .IsOpen(), .frame (rows in .frame.rows, the items in .frame.items).
local Menu = {}
Widgets.Menu = Menu
local MENU_ROW, MENU_WIDTH, MENU_MIN, MENU_MAX, MENU_NAME = 32, 220, 112, 280, "AzerothAccordKitMenu"

local function buildMenu()
	local menu = CreateFrame("Frame", MENU_NAME, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu.parts = Theme.Panel(menu, { radius = "extra-small", fill = "surface-2", border = false, shadow = true })
	menu.rows, menu.items = {}, {}
	menu.catcher = CreateFrame("Button", nil, UIParent)
	menu.catcher:SetAllPoints(UIParent)
	menu.catcher:SetFrameStrata("FULLSCREEN")
	menu.catcher:SetScript("OnClick", function() Menu.Hide() end)
	menu.catcher:Hide()
	menu:SetScript("OnHide", function() menu.catcher:Hide() end)
	menu:Hide()
	Widgets.CloseOnEscape(MENU_NAME)
	return menu
end

local function menuRow(menu, i)
	local row = CreateFrame("Button", nil, menu)
	row:SetHeight(MENU_ROW)
	-- the hover: a state layer of text-1 at 8 % (docs/specs/ui-style.md §9.2, M12.6)
	row.hover = Widgets.StateLayer(row, "text-1", { layer = "BACKGROUND", fade = false })
	row.check = Widgets.Icon(row, "check", 18, "accent-text")
	row.check:SetPoint("LEFT", row, "LEFT", 12, 0)
	row.label = Theme.NewText(row, "Body", "text-1")
	row.label:SetPoint("LEFT", row, "LEFT", 38, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	row.label:SetJustifyH("LEFT")
	row:SetScript("OnEnter", function(self) if self.item and not self.item.header then Widgets.SetState(self.hover, "hover") end end)
	row:SetScript("OnLeave", function(self) Widgets.SetState(self.hover, nil) end)
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
	menu.items, menu.width = items or {}, min(MENU_MAX, max(MENU_MIN, width or MENU_WIDTH))
	menu:SetSize(menu.width, 16 + #menu.items * MENU_ROW)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	for i, item in ipairs(menu.items) do
		local row = menu.rows[i] or menuRow(menu, i)
		row.item = item
		row:SetWidth(menu.width)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -8 - (i - 1) * MENU_ROW)
		row.check:SetShown(item.checked == true and not item.header)
		row.label:SetText(item.text or "")
		Theme.Text(row.label, item.header and "text-2" or item.token or "text-1")
		Widgets.SetState(row.hover, nil)
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

-- Widget kit, part 1: Button (filled, tonal, outlined, text) and IconButton, Card, Badge, Divider, Tabs, Segmented, Chip
-- (the filter chip), TitleBar, Dialog, SideSheet, EditBox and ChoiceList. The rest of the kit is in Controls.lua,
-- DataTable.lua, ThinBar.lua and Tooltip.lua. Lua 5.1.
-- Adapted from Finland Dragon Credit Points (UI/Widgets.lua), same owner, GPL-3.0 (ADR 0021). The look is FDCP's (colours and
-- fonts); the measurements, colour roles, states and shapes are those of docs/specs/ui-style.md §9.6 (Material 3, ADR 0027,
-- M12.7). Sizes are in points.
-- * Namespace: `ns.Widgets` (also `AzerothAccord.Widgets` for tests). Until M6.14 it was `ns.Widgets`, beside the old look of
--   UI/Skin.lua and UI/Widgets/Base.lua; M6.14 removed those two files and gave the kit the name.
-- * Every widget is made of ordinary frames and white textures tinted through UI/Theme.lua: a colour is a token, never a
--   value, and the theme follows Theme.Apply without /reload. States are Material 3 state layers in the colour of the
--   content (Widgets.StateLayer, docs/specs/ui-style.md §9.2, M12.6).
-- * Text comes in already translated by the caller (L[...]): a widget never contains a sentence. Unprotected frames only.
local ADDON_NAME, ns = ...
ns = ns or {}

local Widgets = ns.Widgets or {}
ns.Widgets = Widgets
ns.modules = ns.modules or {}
ns.modules.Widgets = Widgets
if ns.addon then ns.addon.Widgets = Widgets end   -- also reachable from tests

local Theme = ns.Theme
local Assets = ns.Assets
local Motion = ns.Motion
local max, min, ipairs, pairs = math.max, math.min, ipairs, pairs

-- Registers `name` in UISpecialFrames once: Esc closes the frame.
local function closeOnEscape(name)
	if not name or type(UISpecialFrames) ~= "table" then return false end
	for _, n in ipairs(UISpecialFrames) do if n == name then return true end end
	UISpecialFrames[#UISpecialFrames + 1] = name
	return true
end
Widgets.CloseOnEscape = closeOnEscape

-- The control heights of the views (docs/specs/ui-style.md §9.5 and §9.6, M12.8): a button of a dialog or a page, a
-- control of a toolbar or of a line of a form, and a button inside a row of a list (the smallest click area).
Widgets.HEIGHT = { button = 40, dense = 36, small = 32 }

-- The radius of the "full" shape (half the height) for a control `height` points high, among the slices of the media:
-- 20, 18 and 16 are exact for the 40, 36 and 32 point controls of §9.6; a lower one gets the nearest that still fits.
function Widgets.FullRadius(height)
	if height >= 40 then return 20 end
	if height >= 36 then return 18 end
	if height >= 32 then return 16 end
	if height >= 24 then return 12 end
	return 8
end

-- A square icon of the atlas (UI/Assets.lua), `size` points, tinted with `token`.
local function newIcon(parent, name, size, token, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(Assets.textures.icons.path)
	if name then t:SetTexCoord(Assets.IconCoords(name)) end
	t:SetSize(size, size)
	if token then Theme.Tint(t, token) end
	return t
end
Widgets.Icon = newIcon

-- --- State layers (Material 3, docs/specs/ui-style.md §9.2, M12.6) ------------------------------------------------------

-- The opacities are Theme.STATE; HOVER and PRESSED are kept for the callers of M6.11 (they were white 8 % and 12 %).
Widgets.HOVER, Widgets.PRESSED = Theme.STATE.hover, Theme.STATE.pressed

-- A state layer of `frame`: a texture between the container and the content, in the colour of the content (`token`),
-- invisible until a state shows it. opts: shape (a Theme.SHAPES name or radius: a 9-slice of that shape; "circle": the
-- round layer of an icon button or a switch; without it a plain square, the rows of a list), layer ("ARTWORK"), fade
-- (true: the opacity changes in Motion.FAST, 120 ms; false: at once), anchor (a region to cover instead of the whole
-- frame). Returns the texture; Widgets.SetState paints it.
function Widgets.StateLayer(frame, token, opts)
	opts = opts or {}
	local circle = opts.shape == "circle"
	local key = not circle and opts.shape ~= nil and Theme.ShapeSlice(opts.shape) or nil
	local tex
	if circle then
		tex = frame:CreateTexture(nil, opts.layer or "ARTWORK")
		tex:SetTexture(Assets.textures.circle.path)
		Theme.Tint(tex, token)
	elseif key then
		tex = Theme.Slice(frame, key, token, opts.layer or "ARTWORK")
	else
		tex = frame:CreateTexture(nil, opts.layer or "ARTWORK")
		Theme.Fill(tex, token)
	end
	tex:SetAllPoints(opts.anchor or frame)
	tex:SetAlpha(0)
	tex._stateToken, tex._stateFade, tex._sliced = token, opts.fade ~= false, circle or key ~= nil
	return tex
end

-- Shows `state` on a layer: nil (none), "hover", "focus", "pressed" or "dragged" (Theme.STATE). Returns the opacity.
function Widgets.SetState(tex, state)
	local a = state and Theme.STATE[state] or 0
	tex._state = state
	if tex._stateFade then Motion.Fade(tex, a, Motion.FAST) else tex:SetAlpha(a) end
	return a
end

-- The content of the element changed colour (a chip that is selected): the layer follows it.
function Widgets.SetStateColor(tex, token)
	if tex._stateToken == token then return end
	tex._stateToken = token
	if tex._sliced then Theme.Tint(tex, token) else Theme.Fill(tex, token) end
end

-- The state of a frame that has `.hot` (mouse over), `.pressed` and `.focused`: pressed wins over focus, focus over hover;
-- a disabled frame shows none.
function Widgets.StateOf(frame)
	if frame.IsEnabled and not frame:IsEnabled() then return nil end
	if frame.pressed then return "pressed" end
	if frame.focused then return "focus" end
	if frame.hot then return "hover" end
	return nil
end

-- Hover and press on `frame` paint `tex` (hooked: the frame keeps its own OnEnter / OnLeave). opts.press (true) adds the
-- pressed layer. Returns tex.
function Widgets.TrackState(frame, tex, opts)
	opts = opts or {}
	local function paint(self) Widgets.SetState(tex, Widgets.StateOf(self)) end
	frame:HookScript("OnEnter", function(self) self.hot = true; paint(self) end)
	frame:HookScript("OnLeave", function(self) self.hot, self.pressed = false, false; paint(self) end)
	if opts.press ~= false then
		frame:HookScript("OnMouseDown", function(self) self.pressed = true; paint(self) end)
		frame:HookScript("OnMouseUp", function(self) self.pressed = false; paint(self) end)
	end
	frame._statePaint = paint
	return tex
end

-- --- Button -----------------------------------------------------------------------------------------------------------

-- The four kinds of Material 3 (docs/specs/ui-style.md §9.6): fill and ring tokens, the content's token (`ink`), the
-- padding at each side, and the accent glow of the filled one (ADR 0027: the one effect a button keeps).
local BUTTON_KINDS = {
	filled   = { fill = "accent",              ink = "on-accent",              pad = 24, glow = "accent" },
	tonal    = { fill = "secondary-container", ink = "on-secondary-container", pad = 24 },
	outlined = { ring = "border",              ink = "text-2",                 pad = 24 },
	text     = { ink = "accent-text",                                          pad = 12 },
}
Widgets.BUTTON_KINDS = BUTTON_KINDS
-- opts: text, style ("filled" | "tonal" | "outlined" | "text"; default tonal: a view or a dialog has at most one filled
-- button), icon (an icon name of UI/Assets.lua, 20 points before the label), width (without it the button fits its
-- text), height (40; 36 with `dense`, the toolbars and the lines of a form;
-- Widgets.HEIGHT), onClick. Full shape, label large. Padding 24 (16 before an icon; 12
-- at each side of a text button), icon and label 8 apart. Hover lays a state layer in the label's colour at 8 % and
-- pressed 10 % (faded in 120 ms), a press shrinks the button to 0.97 (Motion.Press). Disabled: the content at 38 %, the
-- fill and ring at 12 % of text-1, no glow and no layer. :SetLabel(text), :GetLabel(), :SetEnabled(bool).
function Widgets.Button(parent, opts)
	opts = opts or {}
	local kind = BUTTON_KINDS[opts.style] and opts.style or "tonal"
	local style = BUTTON_KINDS[kind]
	local height = opts.height or (opts.dense and Widgets.HEIGHT.dense or Widgets.HEIGHT.button)
	local radius = Widgets.FullRadius(height)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(opts.width or 120, height)
	b.kind = kind
	if style.glow then
		b.glow = Theme.Glow(b, "glow_s", style.glow, { alpha = 0.3 })
		b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -18, 18)
		b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 18, -18)
	end
	if style.fill then
		b.fill = Theme.Slice(b, "rr_fill_" .. radius, style.fill, "BACKGROUND")
		b.fill:SetAllPoints(b)
	end
	if style.ring then
		b.ring = Theme.Slice(b, "rr_ring_" .. radius, style.ring, "BORDER")
		b.ring:SetAllPoints(b)
	end
	-- the state layer: the label's colour, hover 8 % and pressed 10 %, faded (M12.6)
	b.over = Widgets.StateLayer(b, style.ink, { shape = radius })
	b.label = Theme.NewText(b, "label-large", style.ink)
	local lead, trail, extra = style.pad, style.pad, 0
	if opts.icon then
		lead, extra = min(style.pad, 16), 20 + 8
		b.icon = newIcon(b, opts.icon, 20, style.ink, "OVERLAY")
		b.icon:SetPoint("RIGHT", b.label, "LEFT", -8, 0)
	end
	b.label:SetPoint("CENTER", b, "CENTER", (extra + lead - trail) / 2, 0)
	b.fit = opts.width == nil
	local function fitted() return max(64, lead + extra + b.label:GetStringWidth() + trail) end
	function b:SetLabel(text)
		self.label:SetText(text or "")
		if self.fit then self:SetWidth(fitted()) end
	end
	function b:GetLabel() return self.label:GetText() end
	b:SetLabel(opts.text)
	local function paint(self) Widgets.SetState(self.over, Widgets.StateOf(self)) end
	b:SetScript("OnEnter", function(self) self.hot = true; paint(self) end)
	b:SetScript("OnLeave", function(self) self.hot, self.pressed = false, false; paint(self) end)
	b:SetScript("OnMouseDown", function(self) self.pressed = true; paint(self) end)
	b:SetScript("OnMouseUp", function(self) self.pressed = false; paint(self) end)
	local setEnabled = b.SetEnabled
	local STATE = Theme.STATE
	function b:SetEnabled(enabled)
		enabled = enabled and true or false
		setEnabled(self, enabled)
		self.disabled = not enabled
		self.label:SetAlpha(enabled and 1 or STATE.disabledContent)
		if self.icon then self.icon:SetAlpha(enabled and 1 or STATE.disabledContent) end
		if self.fill then
			if enabled then Theme.Tint(self.fill, style.fill)
			else Theme.Tint(self.fill, "text-1", STATE.disabledContainer) end
		end
		if self.ring then
			if enabled then Theme.Tint(self.ring, style.ring)
			else Theme.Tint(self.ring, "text-1", STATE.disabledContainer) end
		end
		if self.glow then Theme.GlowShow(self.glow, enabled) end
		if not enabled then self.hot, self.pressed = false, false end
		paint(self)
	end
	Motion.Press(b)
	if opts.onClick then b:SetScript("OnClick", opts.onClick) end
	return b
end

-- --- Icon button ------------------------------------------------------------------------------------------------------

-- An icon alone: 40 points (32 with `dense`), the icon 20 in text-2, a round state layer. opts: icon (an icon name of
-- UI/Assets.lua), dense, size, ink (a token for the icon), tooltip (translated), onClick. :SetIcon(name), :SetEnabled(bool).
function Widgets.IconButton(parent, opts)
	opts = opts or {}
	local ink = opts.ink or "text-2"
	local size = opts.size or (opts.dense and 32 or 40)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.over = Widgets.TrackState(b, Widgets.StateLayer(b, ink, { shape = "circle", layer = "BACKGROUND" }))
	b.icon = newIcon(b, opts.icon, 20, ink, "OVERLAY")
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
	function b:SetIcon(name) self.icon:SetTexCoord(Assets.IconCoords(name)) end
	local setEnabled = b.SetEnabled
	function b:SetEnabled(enabled)
		enabled = enabled and true or false
		setEnabled(self, enabled)
		self.icon:SetAlpha(enabled and 1 or Theme.STATE.disabledContent)
		if not enabled then self.hot, self.pressed = false, false end
		Widgets.SetState(self.over, Widgets.StateOf(self))
	end
	if opts.onClick then b:SetScript("OnClick", opts.onClick) end
	if opts.tooltip and Widgets.Tooltip then Widgets.Tooltip.Attach(b, opts.tooltip, "BOTTOM") end
	return b
end

-- --- Card -------------------------------------------------------------------------------------------------------------

Widgets.CARD_PAD = 16

-- A card: radius 12, padding 16 (`.pad`). Filled (surface-1, no outline) or outlined (`outlined`: bg with a border ring),
-- the light line of the dark themes along its top edge, a shadow only when it floats (`shadow`). `hover`: a state layer
-- of text-1 (a card that is clicked). opts: width, height, fill (token), outlined, shadow, hover.
function Widgets.Card(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(opts.width or 200, opts.height or 100)
	c.parts = Theme.Panel(c, { radius = "medium", fill = opts.fill or (opts.outlined and "bg" or "surface-1"),
		border = opts.outlined and "border" or false, shadow = opts.shadow, highlight = true })
	c.pad = Widgets.CARD_PAD
	if opts.hover then
		c:EnableMouse(true)
		c.over = Widgets.TrackState(c, Widgets.StateLayer(c, "text-1", { shape = "medium" }), { press = false })
	end
	return c
end

-- --- Divider ----------------------------------------------------------------------------------------------------------

-- A line of one pixel in border-subtle between rows and sections; the caller anchors its two ends.
function Widgets.Divider(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	Theme.Fill(t, "border-subtle")
	Theme.Crisp(t)
	t:SetHeight(Theme.Px(1, parent))
	return t
end

-- --- Badge ------------------------------------------------------------------------------------------------------------

-- "err" is the badge of Material 3 (a thing to do, a count): on-error over a solid err fill. The other tones are the
-- status labels of Accord (online, main, a version): the tone's text over its colour at 16 %.
local BADGE_TONES = { err = "err", accent = "accent-text", ok = "ok", warn = "warn", neutral = "text-2" }
Widgets.BADGE_TONES = BADGE_TONES

-- A badge: 16 high, full shape. A count badge ("err", the default) is as wide as its text plus 4 points each side, from
-- 16 to 34; a status label has 8 points each side and no maximum. Without text it is the small badge, a dot of 6.
-- :SetBadge(text, tone) (a badge keeps the tone it last had).
function Widgets.Badge(parent, text, tone)
	local f = CreateFrame("Frame", nil, parent)
	f.fill = Theme.Slice(f, "rr_fill_8", "err", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.dot = f:CreateTexture(nil, "BACKGROUND")
	f.dot:SetTexture(Assets.textures.circle.path)
	f.dot:SetAllPoints(f)
	Theme.Tint(f.dot, "err")
	f.dot:Hide()
	f.label = Theme.NewText(f, "label-small", "on-error")
	f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
	function f:SetBadge(newText, newTone)
		tone = newTone or tone or "err"
		if not BADGE_TONES[tone] then tone = "neutral" end
		local token, count = BADGE_TONES[tone], tone == "err"
		self.tone = tone
		Theme.Tint(self.fill, token, count and 1 or 0.16)
		Theme.Tint(self.dot, token)
		Theme.Text(self.label, count and "on-error" or token)
		newText = newText or ""
		self.label:SetText(newText)
		local small = newText == ""
		self.dot:SetShown(small)
		self.fill:SetShown(not small)
		if small then
			self:SetSize(6, 6)
		else
			local w = max(16, self.label:GetStringWidth() + (count and 8 or 16))
			self:SetSize(count and min(34, w) or w, 16)
		end
	end
	f:SetBadge(text, tone)
	return f
end

-- --- Tabs (primary) ---------------------------------------------------------------------------------------------------

Widgets.TAB_HEIGHT = 48

-- tabs: { { id = "roster", text = "Roster", icon = "users"?, badge = "3"? }, ... }. Primary tabs of Material 3
-- (docs/specs/ui-style.md §9.6): 48 high, the active one's label (and icon) in accent-text, the others text-2, a state
-- layer over the whole tab, no box, no fill and no glow. Under the active tab's content lies the indicator: 3 high with
-- round top corners, as wide as the content less 2 points each side and at least 24, in accent; it slides to the next
-- tab in 200 ms. A divider (border) runs under the bar. A tab may carry a count badge (the requests waiting on the Bank
-- tab): the caller passes its text.
-- :Select(id), :Active(), :SetTabShown(id, bool), :SetBadge(id, text|nil), :SetTabText(id, text), :Layout().
-- onSelect(id) runs after a change.
-- When the tabs ask for more room than the bar has (its width less :SetReserve(points), what lies over its right end),
-- they are first drawn closer (8 points each side) and, if they are still too many, the ones that do not fit go into a
-- menu behind a last tab, opts.moreText, which carries the sum of their counts. The active tab always stays on the bar.
-- A bar whose width is not known yet shows every tab.
function Widgets.Tabs(parent, tabs, onSelect, opts)
	local HEIGHT = Widgets.TAB_HEIGHT
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(HEIGHT)
	bar.buttons, bar.order, bar.hidden, bar.overflow = {}, {}, {}, {}
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.line:SetHeight(Theme.Px(1))

	-- the indicator: a frame over the tabs, a bar with two quarter circles for its top corners (3, 3, 0, 0)
	local ind = CreateFrame("Frame", nil, bar)
	ind:SetHeight(3)
	ind:SetFrameLevel((bar:GetFrameLevel() or 1) + 4)
	ind.middle = ind:CreateTexture(nil, "ARTWORK")
	Theme.Fill(ind.middle, "accent")
	ind.middle:SetPoint("TOPLEFT", ind, "TOPLEFT", 3, 0)
	ind.middle:SetPoint("BOTTOMRIGHT", ind, "BOTTOMRIGHT", -3, 0)
	local function corner(point, left, right)
		local t = ind:CreateTexture(nil, "ARTWORK")
		t:SetTexture(Assets.textures.circle.path)
		t:SetTexCoord(left, right, 0, 0.5)
		t:SetSize(3, 3)
		t:SetPoint(point, ind, point, 0, 0)
		Theme.Tint(t, "accent")
		return t
	end
	ind.left, ind.right = corner("TOPLEFT", 0, 0.5), corner("TOPRIGHT", 0.5, 1)
	ind:Hide()
	bar.indicator = ind

	local PAD, TIGHT, ICON, ICON_GAP, BADGE_GAP = 16, 8, 20, 8, 4
	-- the width of a tab: its content (icon, text and the badge when it shows one) and `pad` points each side
	local function wanted(b, pad)
		local content = b.label:GetStringWidth()
		if b.icon then content = content + ICON + ICON_GAP end
		if b.badge and b.badge:IsShown() then content = content + b.badge:GetWidth() + BADGE_GAP end
		return max(64, content + 2 * pad), content
	end

	local function put(b, x, pad)
		local w, content = wanted(b, pad)
		b:SetWidth(w)
		b:Show()
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
		b.x, b.w, b.content = x, w, content
		b.label:ClearAllPoints()
		local left = (w - content) / 2
		if b.icon then
			b.icon:ClearAllPoints()
			b.icon:SetPoint("LEFT", b, "LEFT", left, 0)
			left = left + ICON + ICON_GAP
		end
		b.label:SetPoint("LEFT", b, "LEFT", left, 0)
		if b.badge and b.badge:IsShown() then
			b.badge:ClearAllPoints()
			b.badge:SetPoint("LEFT", b.label, "RIGHT", BADGE_GAP, 0)
		end
		return x + w
	end

	local function newTab(text)
		local b = CreateFrame("Button", nil, bar)
		b:SetHeight(HEIGHT)
		b.label = Theme.NewText(b, "Tab", "text-2")
		b.label:SetText(text or "")
		b.over = Widgets.TrackState(b, Widgets.StateLayer(b, "text-2"))
		return b
	end

	-- The tab that opens the menu of the ones without room; made the first time it is needed.
	local function moreButton()
		if bar.more then return bar.more end
		local more = newTab(opts and opts.moreText or "...")
		more:SetScript("OnClick", function(self)
			local items = {}
			for _, id in ipairs(bar.overflow) do
				local b = bar.buttons[id]
				local text = b.label:GetText() or id
				if b.count then text = text .. " (" .. b.count .. ")" end
				items[#items + 1] = { id = id, text = text, onClick = function() b:Click() end }
			end
			Widgets.Menu.Show(self, items)
		end)
		bar.more = more
		return more
	end

	-- the count on the More tab: the counts of the tabs behind it, added up
	local function moreCount(more)
		local sum, over = 0, false
		for _, id in ipairs(bar.overflow) do
			local count = bar.buttons[id].count
			if count then
				if tonumber(count) then sum = sum + tonumber(count) else over = true end
			end
		end
		local text = (over or sum > 99) and "99+" or (sum > 0 and tostring(sum)) or nil
		if text then
			if not more.badge then more.badge = Widgets.Badge(more, text) else more.badge:SetBadge(text) end
			more.badge:Show()
		elseif more.badge then
			more.badge:Hide()
		end
	end

	local function layout()
		local ids = {}
		for _, id in ipairs(bar.order) do
			if bar.hidden[id] then bar.buttons[id]:Hide() else ids[#ids + 1] = id end
		end
		local width = bar:GetWidth() or 0
		local room = width > 0 and width - (bar.reserve or 0) or nil
		local function total(pad)
			local sum = 0
			for _, id in ipairs(ids) do sum = sum + wanted(bar.buttons[id], pad) end
			return sum
		end
		local pad = PAD
		if room and total(pad) > room then pad = TIGHT end
		bar.overflow = {}
		local shown = ids
		if room and total(pad) > room then
			local more = moreButton()
			-- the More tab is measured with a count of two figures, so that a new count never pushes it over the end
			local left = room - max(64, more.label:GetStringWidth() + 2 * pad + 30)
			local active = bar.active and not bar.hidden[bar.active] and bar.buttons[bar.active]
			if active then left = left - wanted(active, pad) end
			local full = false
			shown = {}
			for _, id in ipairs(ids) do
				local need = wanted(bar.buttons[id], pad)
				if id == bar.active then
					shown[#shown + 1] = id
				elseif not full and need <= left then
					shown[#shown + 1] = id
					left = left - need
				else
					full = true
					bar.overflow[#bar.overflow + 1] = id
					bar.buttons[id]:Hide()
				end
			end
		end
		local x = 0
		for _, id in ipairs(shown) do x = put(bar.buttons[id], x, pad) end
		if #bar.overflow > 0 then
			moreCount(bar.more)
			put(bar.more, x, pad)
		elseif bar.more then
			bar.more:Hide()
		end
	end

	-- puts the indicator under the active tab; from `fromX` (its old place) it slides there, otherwise it appears
	local function place(fromX, fromW, changed)
		local b = bar.active and bar.buttons[bar.active]
		if not b or bar.hidden[bar.active] or not b.x then
			ind:Hide(); bar.ix, bar.iw = nil, nil
			return
		end
		local w = max(24, b.content - 4)
		local x = b.x + (b.w - w) / 2
		local barW = bar:GetWidth() or 0
		local function rest(px, pw)
			ind:ClearAllPoints()
			ind:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", px, 0)
			ind:SetWidth(pw)
			bar.ix, bar.iw, bar.ixBarW = px, pw, barW
		end
		-- slide only from a place measured in the SAME layout, and not over a slide still running: an old place from
		-- another width of the bar (the window resized, tabs moved into More, the first open) sent the indicator far
		-- away, even outside the window, before it came back (found in game, 2026-11-27)
		local sameLayout = bar.ixBarW == barW and fromX ~= nil and fromX >= 0 and (barW <= 0 or fromX <= barW)   -- 0: width unknown yet
		if fromX and ind:IsShown() and changed and sameLayout and not ind.sliding then
			rest(fromX, fromW or w)
			ind.sliding = true
			local started = Motion.Slide(ind, x - fromX, 0, Motion.BASE, function() ind.sliding = nil rest(x, w) end)   -- 200 ms
			if not started then ind.sliding = nil end
		else
			if ind.sliding then Motion.Stop(ind) ind.sliding = nil end
			rest(x, w)
			local wasShown = ind:IsShown()
			ind:Show()
			if changed and not wasShown then Motion.FadeIn(ind, Motion.BASE) end
		end
	end

	local function paint()
		for id, b in pairs(bar.buttons) do
			local ink = id == bar.active and "accent-text" or "text-2"
			Theme.Text(b.label, ink)
			Widgets.SetStateColor(b.over, ink)
			if b.icon then
				-- the chosen view's icon is the filled one (docs/specs/ui-style.md §9.10)
				b.icon:SetTexCoord(Assets.IconCoords(b.iconName, id == bar.active))
				Theme.Tint(b.icon, ink)
			end
		end
	end
	bar.Paint = paint

	function bar:Select(id)
		if not self.buttons[id] or self.hidden[id] then return false end
		local changed = self.active ~= id
		local fromX, fromW = self.ix, self.iw
		self.active = id
		paint(); layout(); place(fromX, fromW, changed)
		if changed and onSelect then onSelect(id) end
		return true
	end
	function bar:Active() return self.active end
	function bar:SetTabShown(id, shown)
		self.hidden[id] = not shown or nil
		if not shown and self.active == id then
			for _, other in ipairs(self.order) do
				if not self.hidden[other] then self:Select(other) break end
			end
		end
		layout(); place(nil, nil, false)
	end
	-- The count badge of a tab: `text` is what the caller wants to show ("3"); nil or "" takes the badge away. It is
	-- always the badge of Material 3 (err).
	function bar:SetBadge(id, text)
		local b = self.buttons[id]
		if not b then return false end
		b.count = (text ~= nil and text ~= "") and tostring(text) or nil
		if text == nil or text == "" then
			if b.badge then b.badge:Hide() end
		else
			if not b.badge then b.badge = Widgets.Badge(b, text) else b.badge:SetBadge(text) end
			b.badge:Show()
		end
		layout(); place(nil, nil, false)
		return true
	end
	function bar:SetTabText(id, text)
		local b = self.buttons[id]
		if not b then return false end
		b.label:SetText(text or "")
		layout(); place(nil, nil, false)
		return true
	end
	function bar:Layout() layout(); place(nil, nil, false) end
	-- The points at the right end of the bar that the tabs leave free.
	function bar:SetReserve(points)
		self.reserve = points or 0
		self:Layout()
	end
	bar:SetScript("OnSizeChanged", function(self) self:Layout() end)

	for _, t in ipairs(tabs) do
		local b = newTab(t.text)
		b.id = t.id
		if t.icon and Assets.IconCoords(t.icon) then
			b.icon, b.iconName = newIcon(b, t.icon, ICON, "text-2"), t.icon
		end
		b:SetScript("OnClick", function() bar:Select(t.id) end)
		bar.buttons[t.id] = b
		bar.order[#bar.order + 1] = t.id
		if t.badge ~= nil and t.badge ~= "" then
			b.count = tostring(t.badge)
			b.badge = Widgets.Badge(b, t.badge)
		end
	end
	layout()
	return bar
end

-- --- Segmented buttons ------------------------------------------------------------------------------------------------

-- items: { { id, text } }, 2 to 5 exclusive choices (docs/specs/ui-style.md §9.6): segments side by side in one
-- outline of 1 point (border) with the full shape, a divider between two of them; the chosen one is filled with
-- secondary-container and shows a check before its label (both on-secondary-container), the others are text-1. At least
-- 12 points each side of a label, the check 18 and 8 from it; a segment keeps the room of the check, so nothing moves
-- when the choice changes. 32 high (the dense size: Accord's segmented buttons sit in toolbars, pagers and forms),
-- 40 with opts.dense = false. :Select(id), :Active(), :Clear(), :SetEnabled(bool), :SetItemText(id, text).
-- onSelect(id) runs after a change.
function Widgets.Segmented(parent, items, onSelect, opts)
	local height = (opts and opts.dense == false) and 40 or 32
	local radius, half = Widgets.FullRadius(height), height / 2
	local CHECK, GAP, PAD = 18, 8, 12
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetHeight(height)
	seg.buttons, seg.order = {}, {}
	-- the outline lies over the segments, so their fills never cover it
	seg.edge = CreateFrame("Frame", nil, seg)
	seg.edge:SetAllPoints(seg)
	seg.edge:SetFrameLevel((seg:GetFrameLevel() or 1) + 5)
	seg.ring = Theme.Slice(seg.edge, "rr_ring_" .. radius, "border", "BORDER")
	seg.ring:SetAllPoints(seg.edge)

	local function paint()
		local off = seg.enabled == false
		for id, b in pairs(seg.buttons) do
			local on = id == seg.active
			local ink = on and "on-secondary-container" or "text-1"
			for _, part in ipairs(b.selection) do
				local paintPart = part == b.middle and Theme.Fill or Theme.Tint
				if off then paintPart(part, "text-1", Theme.STATE.disabledContainer) else paintPart(part, "secondary-container") end
				part:SetShown(on)
			end
			Theme.Text(b.label, ink)
			b.label:SetAlpha(off and Theme.STATE.disabledContent or 1)
			b.label:ClearAllPoints()
			b.label:SetPoint("CENTER", b, "CENTER", on and (CHECK + GAP) / 2 or 0, 0)
			b.check:SetShown(on)
			b.check:SetAlpha(off and Theme.STATE.disabledContent or 1)
			Widgets.SetStateColor(b.over, ink)
		end
		if off then Theme.Tint(seg.ring, "text-1", Theme.STATE.disabledContainer) else Theme.Tint(seg.ring, "border") end
	end

	function seg:Select(id)
		if not self.buttons[id] then return false end
		local changed = self.active ~= id
		self.active = id
		paint()
		if changed and onSelect then onSelect(id) end
		return true
	end
	function seg:Active() return self.active end
	-- No segment selected.
	function seg:Clear()
		self.active = nil
		paint()
	end
	-- Locked: the segments stop answering clicks and dim; the selection stays visible.
	function seg:SetEnabled(enabled)
		self.enabled = enabled ~= false
		for _, b in pairs(self.buttons) do
			b:SetEnabled(self.enabled)
			if not self.enabled then b.hot, b.pressed = false, false end
			Widgets.SetState(b.over, Widgets.StateOf(b))
		end
		paint()
	end

	local function widthOf(b) return max(48, b.label:GetStringWidth() + 2 * PAD + CHECK + GAP) end
	local function row()
		local x = 0
		for _, id in ipairs(seg.order) do
			local b = seg.buttons[id]
			b:SetWidth(widthOf(b))
			b:ClearAllPoints()
			b:SetPoint("LEFT", seg, "LEFT", x, 0)
			x = x + b:GetWidth()
		end
		seg:SetWidth(x)
	end

	for i, item in ipairs(items) do
		local first, last = i == 1, i == #items
		local b = CreateFrame("Button", nil, seg)
		b:SetHeight(height)
		-- the chosen segment's fill: a flat middle, closed by a half circle at an end of the row
		b.selection = {}
		local function cap(point, left, right)
			local t = b:CreateTexture(nil, "BACKGROUND")
			t:SetTexture(Assets.textures.circle.path)
			t:SetTexCoord(left, right, 0, 1)
			t:SetSize(half, height)
			t:SetPoint(point, b, point, 0, 0)
			b.selection[#b.selection + 1] = t
		end
		if first then cap("LEFT", 0, 0.5) end
		if last then cap("RIGHT", 0.5, 1) end
		local middle = b:CreateTexture(nil, "BACKGROUND")
		middle:SetPoint("TOPLEFT", b, "TOPLEFT", first and half or 0, 0)
		middle:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", last and -half or 0, 0)
		b.selection[#b.selection + 1] = middle
		b.middle = middle
		b.over = Widgets.TrackState(b, Widgets.StateLayer(b, "text-1", { shape = (first or last) and radius or nil }))
		if not first then
			b.divider = b:CreateTexture(nil, "OVERLAY")
			Theme.Fill(b.divider, "border")
			b.divider:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
			b.divider:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
			b.divider:SetWidth(Theme.Px(1))
		end
		b.label = Theme.NewText(b, "label-large", "text-1")
		b.label:SetText(item.text or "")
		b.check = newIcon(b, "check", CHECK, "on-secondary-container", "OVERLAY")
		b.check:SetPoint("RIGHT", b.label, "LEFT", -GAP, 0)
		b:SetScript("OnClick", function() seg:Select(item.id) end)
		seg.buttons[item.id] = b
		seg.order[#seg.order + 1] = item.id
	end
	row()
	paint()
	-- A new text for a segment (a count on a page's name): the segments move to make room.
	function seg:SetItemText(id, text)
		local b = self.buttons[id]
		if not b then return false end
		b.label:SetText(text or "")
		row()
		return true
	end
	return seg
end

-- --- Chip (filter) ----------------------------------------------------------------------------------------------------

-- The filter chip of Material 3 (docs/specs/ui-style.md §9.6): 32 high, radius 8. Off: a border outline, the label in
-- text-2, 16 points each side. Selected: secondary-container, no outline, a check of 18 at the left (8 from the edge, 8
-- from the label) and the label in on-secondary-container; the chip grows by the check and calls onResize(chip), so that a
-- caller that places chips by their width can place them again. Hover is a state layer in the label's colour (8 %);
-- disabled, the label is at 38 % and the container or outline at 12 % of text-1.
-- opts: text, onClick(chip), onResize(chip) (also settable as chip.onResize), height, font (a Theme font id or role).
-- :SetSelected(bool), :IsSelected(), :SetLabel(text), :SetEnabled(bool).
function Widgets.Chip(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(opts.height or 32)
	c.onResize = opts.onResize
	c.fill = Theme.Slice(c, "rr_fill_8", "secondary-container", "BACKGROUND")
	c.fill:SetAllPoints(c)
	c.ring = Theme.Slice(c, "rr_ring_8", "border", "BORDER")
	c.ring:SetAllPoints(c)
	c.over = Widgets.StateLayer(c, "text-2", { shape = "small", fade = false })
	c.check = newIcon(c, "check", 18, "on-secondary-container", "OVERLAY")
	c.check:SetPoint("LEFT", c, "LEFT", 8, 0)
	c.label = Theme.NewText(c, opts.font or "label-large", "text-2")
	function c:Fit()
		local lead = self.selected and (8 + 18 + 8) or 16
		self.label:ClearAllPoints()
		self.label:SetPoint("LEFT", self, "LEFT", lead, 0)
		local w = max(32, lead + self.label:GetStringWidth() + 16)
		if w ~= self.fitted then
			local had = self.fitted ~= nil
			self.fitted = w
			self:SetWidth(w)
			if had and self.onResize then self.onResize(self) end
		end
	end
	function c:Paint()
		local off, on = not self:IsEnabled(), self.selected == true
		local ink = on and "on-secondary-container" or "text-2"
		if off then
			Theme.Tint(self.fill, "text-1", Theme.STATE.disabledContainer)
			Theme.Tint(self.ring, "text-1", Theme.STATE.disabledContainer)
		else
			Theme.Tint(self.fill, "secondary-container")
			Theme.Tint(self.ring, "border")
		end
		self.fill:SetShown(on)
		self.ring:SetShown(not on)
		self.check:SetShown(on)
		self.check:SetAlpha(off and Theme.STATE.disabledContent or 1)
		Theme.Text(self.label, ink)
		self.label:SetAlpha(off and Theme.STATE.disabledContent or 1)
		Widgets.SetStateColor(self.over, ink)
		Widgets.SetState(self.over, Widgets.StateOf(self))
	end
	function c:SetLabel(text)
		self.label:SetText(text or "")
		self:Fit()
	end
	function c:SetSelected(selected)
		self.selected = selected and true or false
		self:Paint()
		self:Fit()
	end
	function c:IsSelected() return self.selected == true end
	local setEnabled = c.SetEnabled
	function c:SetEnabled(enabled)
		setEnabled(self, enabled and true or false)
		if not enabled then self.hot, self.pressed = false, false end
		self:Paint()
	end
	c:SetScript("OnEnter", function(self) if self:IsEnabled() then self.hot = true; self:Paint() end end)
	c:SetScript("OnLeave", function(self) self.hot, self.pressed = false, false; self:Paint() end)
	c:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.pressed = true; self:Paint() end end)
	c:SetScript("OnMouseUp", function(self) self.pressed = false; self:Paint() end)
	if opts.onClick then c:SetScript("OnClick", function(self) if self:IsEnabled() then opts.onClick(self) end end) end
	c:SetLabel(opts.text)
	c:Paint()
	return c
end

-- --- TitleBar ---------------------------------------------------------------------------------------------------------

-- The window's title bar: 52 pt, surface-1, round logo, the title in the display face (the one text glow of the view),
-- a mono subtitle and the close button (`.close`, a dense icon button: the caller anchors its own buttons to the left
-- of it). opts: title, subtitle, closeLabel (the tooltip of the close button, translated), onClose.
function Widgets.TitleBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(52)
	bar.fill = Theme.Slice(bar, "rr_fill_12", "surface-1", "BACKGROUND")
	bar.fill:SetAllPoints(bar)
	bar.line = Widgets.Divider(bar, "BORDER")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 12, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -12, 0)

	bar.logoGlow = Theme.Glow(bar, "glow_s", "accent", { layer = "ARTWORK", alpha = 0.35 })
	bar.logoGlow:SetSize(64, 64)
	bar.logoGlow:SetPoint("LEFT", bar, "LEFT", 6, 0)
	bar.logo = bar:CreateTexture(nil, "OVERLAY")
	bar.logo:SetTexture(Assets.logos.logo_64.path)
	bar.logo:SetSize(32, 32)
	bar.logo:SetPoint("LEFT", bar, "LEFT", 20, 0)
	if bar.logo.SetMaskTexture then bar.logo:SetMaskTexture(Assets.textures.circle.path) end

	bar.title = Theme.NewText(bar, "Display", "text-1")
	bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", 64, -9)
	bar.title:SetText(opts.title or "")
	-- the text glow of the site's title (approximated: a coloured shadow of the font and a soft glow behind it)
	Theme.TextGlow(bar.title, "accent")
	bar.titleGlow = Theme.Glow(bar, "glow_l", "accent", { layer = "ARTWORK", alpha = 0.16 })
	bar.titleGlow:SetPoint("TOPLEFT", bar.title, "TOPLEFT", -26, 18)
	bar.titleGlow:SetPoint("BOTTOMRIGHT", bar.title, "BOTTOMRIGHT", 26, -18)
	bar.subtitle = Theme.NewText(bar, "MonoSmall", "text-3")
	bar.subtitle:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -3)
	bar.subtitle:SetText(opts.subtitle or "")

	bar.close = Widgets.IconButton(bar, { icon = "cross", dense = true, onClick = opts.onClose, tooltip = opts.closeLabel })
	bar.close:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
	return bar
end

-- --- Dialog -----------------------------------------------------------------------------------------------------------

Widgets.DIALOG = { minWidth = 280, pad = 24, gap = 8 }

-- A modal base: a dark veil (scrim; no blur: the engine cannot) over `parent` with a centred card on the DIALOG strata:
-- surface-3, radius 28, a shadow, 24 points of padding (docs/specs/ui-style.md §9.6). It enters with Motion.Rise (alpha
-- and a 16 pt rise, 320 ms). Esc closes it (it is added to UISpecialFrames under `name`).
-- opts: width (420, at least 280), height (220). :Open(), :Close(), .card, .content (the card: the caller adds its own
-- children). :SetTitle(text) puts a title large at the top; :SetActions({ button, ... }) places the buttons of the
-- bottom right, 8 points apart, in the order given (the last one is the rightmost).
function Widgets.Dialog(parent, name, opts)
	opts = opts or {}
	local D = Widgets.DIALOG
	local d = CreateFrame("Frame", name, parent or UIParent)
	d:SetAllPoints(parent or UIParent)
	d:SetFrameStrata("DIALOG")
	d:EnableMouse(true)   -- the veil swallows clicks
	d.veil = d:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(d.veil, "scrim")
	d.veil:SetAllPoints(d)
	d.card = CreateFrame("Frame", nil, d)
	d.card:SetSize(max(D.minWidth, opts.width or 420), opts.height or 220)
	d.card:SetPoint("CENTER", d, "CENTER", 0, 0)
	d.card.parts = Theme.Panel(d.card, { radius = "extra-large", fill = "surface-3", border = false, shadow = true })
	d.content = d.card
	d:Hide()
	closeOnEscape(name)
	function d:SetTitle(text)
		if not self.title then
			self.title = Theme.NewText(self.card, "title-large", "text-1")
			self.title:SetJustifyH("LEFT")
			self.title:SetPoint("TOPLEFT", self.card, "TOPLEFT", D.pad, -D.pad)
			self.title:SetPoint("TOPRIGHT", self.card, "TOPRIGHT", -D.pad, -D.pad)
		end
		self.title:SetText(text or "")
		return self.title
	end
	function d:SetActions(buttons)
		local last
		for i = #buttons, 1, -1 do
			local b = buttons[i]
			b:ClearAllPoints()
			if last then b:SetPoint("RIGHT", last, "LEFT", -D.gap, 0)
			else b:SetPoint("BOTTOMRIGHT", self.card, "BOTTOMRIGHT", -D.pad, D.pad) end
			last = b
		end
	end
	-- the card rises 16 points while it fades in, 320 ms, the veil fades in 200 ms (both at once with animations off)
	function d:Open()
		self:Show()
		Motion.FadeIn(self.veil, Motion.BASE)
		Motion.Rise(self.card, 16, Motion.SLOW)
	end
	function d:Close() self:Hide() end
	return d
end

-- --- Side sheet -------------------------------------------------------------------------------------------------------

Widgets.SIDE_SHEET = { width = 400, pad = 24, densePad = 16, header = 72 }

-- The detail of one item beside a list (docs/specs/ui-style.md §9.6): surface-1, radius 16, a shadow, at most 400 wide,
-- a header of 72 with the title (title large), a subtitle and a close icon button; padding 24 (16 dense).
-- opts: width (400), height, pad, indent (room before the title, for a mark), onClose, closeLabel (the close button's
-- tooltip, translated). Fields .title, .subtitle,
-- .close, .pad, .header. :SetPad(pad) places the header again; :SetTitleEnd(points) is what the title leaves free at the
-- right (the close button, or a caller's own button).
function Widgets.SideSheet(parent, opts)
	opts = opts or {}
	local S = Widgets.SIDE_SHEET
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(min(opts.width or S.width, S.width), opts.height or 200)
	f.parts = Theme.Panel(f, { radius = "large", fill = "surface-1", border = false, shadow = true })
	f.header, f.indent = S.header, opts.indent or 0
	f.title = Theme.NewText(f, "title-large", "text-1")
	f.title:SetJustifyH("LEFT")
	if f.title.SetWordWrap then f.title:SetWordWrap(false) end
	f.subtitle = Theme.NewText(f, "body-small", "text-2")
	f.subtitle:SetJustifyH("LEFT")
	f.close = Widgets.IconButton(f, { icon = "cross", dense = true, onClick = opts.onClose, tooltip = opts.closeLabel })
	function f:SetTitleEnd(points)
		self.title:ClearAllPoints()
		self.title:SetPoint("TOPLEFT", self, "TOPLEFT", self.pad + self.indent, -16)
		self.title:SetPoint("RIGHT", self, "RIGHT", -points, 0)
	end
	function f:SetPad(pad)
		self.pad = pad
		self:SetTitleEnd(pad + 32)
		self.subtitle:ClearAllPoints()
		self.subtitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
		self.subtitle:SetPoint("RIGHT", self, "RIGHT", -pad, 0)
		self.close:ClearAllPoints()
		self.close:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(pad - 8), -(S.header - 32) / 2)
	end
	f:SetPad(opts.pad or S.pad)
	return f
end

-- --- EditBox ----------------------------------------------------------------------------------------------------------

-- A one-line text field (docs/specs/ui-style.md §9.6): 40 high (36 with `dense`), radius 4, surface-2 with an outline of 1 point (border;
-- border-strong under the mouse), 2 points of accent while it has the keyboard. opts: width, height, dense, maxLetters,
-- placeholder (text-3, shown while the field is empty and not focused), onChange(text, user) after every edit,
-- onEnter(text). :GetText(), :SetText(text), :Clear(), :SetPlaceholder(text), :SetFocus(), :ClearFocus(),
-- :SetEnabled(bool) (the text at 38 %, the outline at 12 % of text-1). The edit box itself is `.edit`.
function Widgets.EditBox(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 120, opts.height or (opts.dense and Widgets.HEIGHT.dense or Widgets.HEIGHT.button))
	f.fill = Theme.Slice(f, "rr_fill_4", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_4", "border", "BORDER")
	f.ring:SetAllPoints(f)
	f.focusRing = Theme.Slice(f, "rr_ring2_4", "accent", "BORDER")
	f.focusRing:SetAllPoints(f)
	f.focusRing:Hide()
	f.enabled = true
	local e = CreateFrame("EditBox", nil, f)
	e:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -2)
	e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 2)
	e:SetAutoFocus(false)
	if Theme.fontObjects.Body then e:SetFontObject(Theme.fontObjects.Body) end
	if opts.maxLetters then e:SetMaxLetters(opts.maxLetters) end
	Theme.Text(e, "text-1")
	f.placeholder = Theme.NewText(f, "Body", "text-3")
	f.placeholder:SetPoint("LEFT", f, "LEFT", 12, 0)
	f.placeholder:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	f.placeholder:SetJustifyH("LEFT")
	f.placeholder:SetText(opts.placeholder or "")
	local function hint()
		local empty = (e:GetText() or "") == "" and not f.focused
		f.placeholder:SetShown(empty and (f.placeholder:GetText() or "") ~= "")
	end
	local function paint()
		local on = f.focused == true and f.enabled
		f.focusRing:SetShown(on)
		f.ring:SetShown(not on)
		if not f.enabled then Theme.Tint(f.ring, "text-1", Theme.STATE.disabledContainer)
		else Theme.Tint(f.ring, f.hot and "border-strong" or "border") end
	end
	e:HookScript("OnEnter", function() f.hot = true; paint() end)
	e:HookScript("OnLeave", function() f.hot = false; paint() end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if opts.onEnter then opts.onEnter(self:GetText()) end
	end)
	e:SetScript("OnEditFocusGained", function() f.focused = true; paint(); hint() end)
	e:SetScript("OnEditFocusLost", function() f.focused = false; paint(); hint() end)
	e:SetScript("OnTextChanged", function(self, user)
		hint()
		if opts.onChange then opts.onChange(self:GetText(), user) end
	end)
	f.edit = e
	function f:GetText() return self.edit:GetText() end
	function f:SetText(text) self.edit:SetText(text or ""); hint() end
	function f:Clear() self.edit:SetText(""); hint() end
	function f:SetPlaceholder(text)
		self.placeholder:SetText(text or "")
		hint()
	end
	function f:SetFocus() self.edit:SetFocus() end
	function f:ClearFocus() self.edit:ClearFocus() end
	function f:SetEnabled(enabled)
		self.enabled = enabled and true or false
		if not self.enabled then self.hot = false; self.edit:ClearFocus() end
		self.edit:SetEnabled(self.enabled)
		self.edit:SetAlpha(self.enabled and 1 or Theme.STATE.disabledContent)
		paint()
	end
	hint()
	return f
end

-- The look of a text field around a box of more than one line (docs/specs/ui-style.md §9.6): radius 4, surface-2, an
-- outline of 1 point, 2 points of accent while the box has the keyboard. The caller anchors the frame, puts its scroll
-- frame and edit box inside and calls :Track(edit) once.
function Widgets.TextArea(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.fill = Theme.Slice(f, "rr_fill_4", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_4", "border", "BORDER")
	f.ring:SetAllPoints(f)
	f.focusRing = Theme.Slice(f, "rr_ring2_4", "accent", "BORDER")
	f.focusRing:SetAllPoints(f)
	f.focusRing:Hide()
	function f:Track(edit)
		local function paint(on)
			self.focusRing:SetShown(on)
			self.ring:SetShown(not on)
		end
		edit:HookScript("OnEditFocusGained", function() paint(true) end)
		edit:HookScript("OnEditFocusLost", function() paint(false) end)
	end
	return f
end

-- --- ChoiceList -------------------------------------------------------------------------------------------------------

-- A list of single-choice rows (a radio list: no UIDropDownMenu, which taints, docs/specs/ui-style.md §3) drawn as a
-- menu of Material 3 (§9.6): surface-2, radius 4, rows of 32 (the dense menu) with 12 points each side; the chosen row
-- is secondary-container, the one under the mouse has a state layer. choices = { { id, text, token? } }; `rows` rows
-- show at once and the mouse wheel scrolls the rest. opts: rows (6), rowHeight (32), width, onSelect(id), menu (a popup:
-- a shadow instead of the outline). :SetChoices(list), :Select(id), :Selected(), :Clear(), :Count(), :Scroll(delta).
function Widgets.ChoiceList(parent, opts)
	opts = opts or {}
	local rows, rowH = opts.rows or 6, opts.rowHeight or 32
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 240, rows * rowH + 8)
	if opts.menu then
		f.shadow = Theme.Panel(f, { radius = "extra-small", fill = false, border = false, shadow = true }).shadow
	end
	f.fill = Theme.Slice(f, "rr_fill_4", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_4", "border", "BORDER")
	f.ring:SetAllPoints(f)
	f.ring:SetShown(not opts.menu)
	f.choices, f.offset, f.rowH, f.rowsShown = {}, 0, rowH, rows
	f:EnableMouseWheel(true)
	f.rows = {}
	for i = 1, rows do
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(rowH)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4 - (i - 1) * rowH)
		b:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -4 - (i - 1) * rowH)
		b.mark = b:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(b.mark, "secondary-container")
		b.mark:SetAllPoints(b)
		b.mark:Hide()
		b.over = Widgets.TrackState(b, Widgets.StateLayer(b, "text-1", { layer = "BORDER", fade = false }))
		b.label = Theme.NewText(b, "Body", "text-1")
		b.label:SetPoint("LEFT", b, "LEFT", 12, 0)
		b.label:SetPoint("RIGHT", b, "RIGHT", -12, 0)
		b.label:SetJustifyH("LEFT")
		b:SetScript("OnClick", function(self) if self.choice then f:Select(self.choice.id) end end)
		b:Hide()
		f.rows[i] = b
	end
	local function paint()
		for i, b in ipairs(f.rows) do
			local c = f.choices[f.offset + i]
			b.choice = c
			if c then
				local on = f.selected ~= nil and c.id == f.selected
				b.label:SetText(c.text or "")
				Theme.Text(b.label, on and "on-secondary-container" or c.token or "text-1")
				b.mark:SetShown(on)
				Widgets.SetStateColor(b.over, on and "on-secondary-container" or "text-1")
				b:Show()
			else
				b:Hide()
			end
		end
	end
	local function has(id)
		for _, c in ipairs(f.choices) do if c.id == id then return true end end
		return false
	end
	function f:SetChoices(list)
		self.choices = list or {}
		self.offset = 0
		if self.selected ~= nil and not has(self.selected) then self.selected = nil end
		paint()
	end
	function f:Select(id)
		if not has(id) then return false end
		local changed = self.selected ~= id
		self.selected = id
		paint()
		if changed and opts.onSelect then opts.onSelect(id) end
		return true
	end
	function f:Selected() return self.selected end
	function f:Clear() self.selected = nil; paint() end
	function f:Count() return #self.choices end
	function f:Scroll(delta)
		self.offset = min(max(self.offset + delta, 0), max(#self.choices - rows, 0))
		paint()
	end
	f:SetScript("OnMouseWheel", function(self, delta) self:Scroll(-delta * 2) end)
	return f
end

-- --- Small helpers for the views (M6.14) ------------------------------------------------------------------------------

-- A FontString in font `id` (a Theme font id) and colour `token`, justified `justify` ("LEFT" | "CENTER" | "RIGHT").
function Widgets.Text(parent, id, token, justify, layer)
	local fs = Theme.NewText(parent, id or "Body", token or "text-1", layer)
	if justify then fs:SetJustifyH(justify) end
	return fs
end

-- The hover of a list row: a state layer of text-1 under the row's texts (8 % while the mouse is over it, 10 % pressed;
-- docs/specs/ui-style.md §9.6, M12.6), like the DataTable's. Hooked, so the row keeps its own OnEnter / OnLeave (a
-- tooltip). Returns the texture (`row.hover`).
function Widgets.RowHover(row)
	row.hover = Widgets.StateLayer(row, "text-1", { layer = "BACKGROUND", fade = false })
	return Widgets.TrackState(row, row.hover)
end

-- The selected row of a list that is not a DataTable (docs/specs/ui-style.md §9.6): secondary-container with radius 4,
-- under everything else of `row`, hidden until the view shows it. The row's plain texts go to on-secondary-container.
function Widgets.Selection(row)
	local t = Theme.Slice(row, "rr_fill_4", "secondary-container", "BACKGROUND")
	t:SetDrawLayer("BACKGROUND", -1)
	t:SetAllPoints(row)
	t:Hide()
	return t
end

-- A player's name in the class colour of the game (Theme.ClassText: text-1 on the light theme), text-1 for an unknown class.
function Widgets.PaintName(fs, classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then Theme.ClassText(fs, c.r, c.g, c.b) else Theme.Text(fs, "text-1") end
end

-- Places `items` (frames that have a width) left to right on `bar`, a new line when the next one does not fit in `width`.
-- Lines are `rowHeight` high (32), `gap` apart (8) both ways; `x`, `y` are where the first one starts. Returns the
-- height the lines take.
function Widgets.Flow(bar, items, width, rowHeight, gap, x, y)
	rowHeight, gap, x, y = rowHeight or Widgets.HEIGHT.small, gap or 8, x or 0, y or 0
	local at, line = 0, 0
	for _, item in ipairs(items) do
		local w = item:GetWidth() or 0
		if at > 0 and at + w > width then at, line = 0, line + 1 end
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", bar, "TOPLEFT", x + at, -y - line * (rowHeight + gap))
		at = at + w + gap
	end
	return #items > 0 and (line + 1) * (rowHeight + gap) - gap or 0
end

-- A row of chips of which one is selected: the modes of a view, the tabs of the bank, a period. onSelect(id) after a
-- click. :SetItems({ { id, text } }, activeId) makes, labels, places and selects the chips (the extra ones hide);
-- :Select(id) marks one (the selected chip grows by its check, so the row is placed again); `.buttons[i]` are the chips
-- in order (`.id` each), `.active` the selected id, `.width` the row's width. opts: height (32), gap (8).
function Widgets.ChipRow(parent, onSelect, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(opts.height or 32)
	bar.buttons, bar.gap, bar.count = {}, opts.gap or 8, 0
	local function place()
		local x = 0
		for i = 1, bar.count do
			local c = bar.buttons[i]
			c:ClearAllPoints()
			c:SetPoint("LEFT", bar, "LEFT", x, 0)
			x = x + c:GetWidth() + bar.gap
		end
		bar.width = max(0, x - bar.gap)
	end
	function bar:Select(id)
		self.active = id
		for _, c in ipairs(self.buttons) do c:SetSelected(c:IsShown() and c.id == id) end
		place()
	end
	function bar:SetItems(items, active)
		for i, item in ipairs(items) do
			local c = self.buttons[i]
			if not c then
				c = Widgets.Chip(self, { height = opts.height or 32, onClick = function(chip)
					bar:Select(chip.id)
					if onSelect then onSelect(chip.id) end
				end })
				self.buttons[i] = c
			end
			c.id = item.id
			c:SetLabel(item.text)
			c:Show()
		end
		for i = #items + 1, #self.buttons do self.buttons[i]:Hide() end
		self.count = #items
		self:Select(active)
	end
	return bar
end

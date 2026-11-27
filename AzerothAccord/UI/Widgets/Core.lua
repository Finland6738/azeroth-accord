-- Widget kit, part 1: Button (primary, secondary, ghost, neon), Card, Badge, Tabs (underline with the moving indicator and
-- an optional count badge), Segmented (pill selector), Chip, TitleBar, Dialog, EditBox and ChoiceList: the components of
-- docs/specs/ui-style.md §3 (M6.11). The rest of the kit is in Controls.lua, DataTable.lua, ThinBar.lua and Tooltip.lua. Lua 5.1.
-- Adapted from Finland Dragon Credit Points (UI/Widgets.lua), same owner, GPL-3.0 (ADR 0021).
-- * Namespace: `ns.Widgets` (also `AzerothAccord.Widgets` for tests). Until M6.14 it was `ns.Widgets`, beside the old look of
--   UI/Skin.lua and UI/Widgets/Base.lua; M6.14 removed those two files and gave the kit the name.
-- * Every widget is made of ordinary frames and white textures tinted through UI/Theme.lua: a colour is a token, never a
--   value, and the theme follows Theme.Apply without /reload. States are Material 3 state layers in the colour of the
--   content (Widgets.StateLayer, docs/specs/ui-style.md §9.2, M12.6), no longer white.
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

local function gradientColor(token)
	local r, g, b, a = Theme.Color(token)
	if CreateColor then return CreateColor(r, g, b, a) end
	return { r = r, g = g, b = b, a = a }
end

-- Registers `name` in UISpecialFrames once: Esc closes the frame.
local function closeOnEscape(name)
	if not name or type(UISpecialFrames) ~= "table" then return false end
	for _, n in ipairs(UISpecialFrames) do if n == name then return true end end
	UISpecialFrames[#UISpecialFrames + 1] = name
	return true
end
Widgets.CloseOnEscape = closeOnEscape

-- --- Button -----------------------------------------------------------------------------------------------------------

-- Button styles: fill token, text token, and what else the style adds.
local BUTTON_STYLES = {
	primary   = { fill = "accent",    ink = "on-accent", gradient = true, glow = "accent", glowAlpha = 0.3 },
	secondary = { fill = "surface-3", ink = "text-1",    ring = "border" },
	ghost     = { fill = nil,         ink = "text-2",    ring = nil },
	neon      = { fill = "surface-1", ink = "text-1",    ring = "neon", glow = "neon", glowAlpha = 0.5 },
}
Widgets.BUTTON_STYLES = BUTTON_STYLES

-- --- State layers (Material 3, docs/specs/ui-style.md §9.2, M12.6) ------------------------------------------------------

-- The opacities are Theme.STATE; HOVER and PRESSED are kept for the callers of M6.11 (they were white 8 % and 12 %).
Widgets.HOVER, Widgets.PRESSED = Theme.STATE.hover, Theme.STATE.pressed

-- A state layer of `frame`: a texture between the container and the content, in the colour of the content (`token`),
-- invisible until a state shows it. opts: shape (a Theme.SHAPES name or radius: a 9-slice of that shape; without it a
-- plain square, the rows of a list), layer ("ARTWORK"), fade (true: the opacity changes in Motion.FAST, 120 ms; false:
-- at once), anchor (a region to cover instead of the whole frame). Returns the texture; Widgets.SetState paints it.
function Widgets.StateLayer(frame, token, opts)
	opts = opts or {}
	local key = opts.shape ~= nil and Theme.ShapeSlice(opts.shape) or nil
	local tex
	if key then
		tex = Theme.Slice(frame, key, token, opts.layer or "ARTWORK")
	else
		tex = frame:CreateTexture(nil, opts.layer or "ARTWORK")
		Theme.Fill(tex, token)
	end
	tex:SetAllPoints(opts.anchor or frame)
	tex:SetAlpha(0)
	tex._stateToken, tex._stateFade, tex._sliced = token, opts.fade ~= false, key ~= nil
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

-- opts: text, style ("primary" | "secondary" | "ghost" | "neon"), width (without it the button fits its text), height,
-- onClick. The primary button has the glow of the accent (dark themes, "Neon effects"), the neon one a ring and a glow in
-- the neon colour; hover lays a state layer in the label's colour at 8 % over the shape and pressed 10 % (faded in 120 ms,
-- M12.6), a press shrinks the button to 0.97 (Motion.Press). Disabled: the label at 38 %, the fill and ring at 12 % of
-- text-1, no glow and no layer (docs/specs/ui-style.md §9.2). :SetLabel(text), :GetLabel(), :SetEnabled(bool).
function Widgets.Button(parent, opts)
	opts = opts or {}
	local style = BUTTON_STYLES[opts.style or "secondary"] or BUTTON_STYLES.secondary
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(opts.width or 120, opts.height or 32)
	b.style = opts.style or "secondary"
	if style.glow then
		b.glow = Theme.Glow(b, "glow_s", style.glow, { alpha = style.glowAlpha or 0.5 })
		b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -18, 18)
		b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 18, -18)
	end
	if style.fill then
		b.fill = Theme.Slice(b, "rr_fill_8", style.fill, "BACKGROUND")
		b.fill:SetAllPoints(b)
		if style.gradient then
			Theme.Call(b.fill, function(region)   -- accent -> accent-2, two colours (the spec: SetGradient); none while disabled
				if region.SetGradient and not b.disabled then
					region:SetGradient("HORIZONTAL", gradientColor("accent"), gradientColor("accent-2"))
				end
			end)
		end
	end
	if style.ring then
		b.ring = Theme.Slice(b, "rr_ring_8", style.ring, "BORDER")
		b.ring:SetAllPoints(b)
	end
	-- the state layer: the label's colour, hover 8 % and pressed 10 %, faded (M12.6)
	b.over = Widgets.StateLayer(b, style.ink, { shape = 8 })
	b.label = Theme.NewText(b, "Button", style.ink)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.fit = opts.width == nil
	function b:SetLabel(text)
		self.label:SetText(text or "")
		if self.fit then self:SetWidth(max(64, self.label:GetStringWidth() + 32)) end
	end
	function b:GetLabel() return self.label:GetText() end
	b:SetLabel(opts.text)
	if opts.width == nil then b:SetWidth(max(64, b.label:GetStringWidth() + 32)) end
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
		if self.fill then
			if enabled then
				Theme.Tint(self.fill, style.fill)
				if style.gradient and self.fill.SetGradient then
					self.fill:SetGradient("HORIZONTAL", gradientColor("accent"), gradientColor("accent-2"))
				end
			else
				Theme.Tint(self.fill, "text-1", STATE.disabledContainer)
			end
		end
		if self.ring then Theme.Tint(self.ring, enabled and style.ring or "text-1", not enabled and STATE.disabledContainer or nil) end
		if self.glow then Theme.GlowShow(self.glow, enabled) end
		if not enabled then self.hot, self.pressed = false, false end
		paint(self)
	end
	Motion.Press(b)
	if opts.onClick then b:SetScript("OnClick", opts.onClick) end
	return b
end

-- --- Card -------------------------------------------------------------------------------------------------------------

-- A card: surface-1 fill, subtle ring (strong on hover when `hover`), the light line of the dark themes along its top edge,
-- radius 18, optional shadow. Four regions at most. opts: width, height, fill (token), shadow, hover.
function Widgets.Card(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(opts.width or 200, opts.height or 100)
	c.parts = Theme.Panel(c, { radius = 18, fill = opts.fill or "surface-1", border = "border-subtle", shadow = opts.shadow, highlight = true })
	if opts.hover then
		c:EnableMouse(true)
		c:SetScript("OnEnter", function(self) Theme.Tint(self.parts.ring, "border-strong") end)
		c:SetScript("OnLeave", function(self) Theme.Tint(self.parts.ring, "border-subtle") end)
	end
	return c
end

-- --- Badge ------------------------------------------------------------------------------------------------------------

local BADGE_TONES = { accent = "accent-text", ok = "ok", warn = "warn", err = "err", neutral = "text-2" }
Widgets.BADGE_TONES = BADGE_TONES

-- A pill (24 high) whose width follows its text; the fill is the tone's colour at low alpha, the text the tone's.
-- :SetBadge(text, tone).
function Widgets.Badge(parent, text, tone)
	local token = BADGE_TONES[tone or "neutral"] or BADGE_TONES.neutral
	local f = CreateFrame("Frame", nil, parent)
	f.fill = Theme.Slice(f, "rr_fill_12", token, "BACKGROUND", 0.16)
	f.fill:SetAllPoints(f)
	-- a count of one or two figures is a round dot (owner, 2026-11-27: "the square counters round"); longer text a pill
	f.dot = f:CreateTexture(nil, "BACKGROUND")
	f.dot:SetTexture(Assets.textures.circle.path)
	f.dot:SetAllPoints(f)
	Theme.Tint(f.dot, token, 0.16)
	f.dot:Hide()
	f.label = Theme.NewText(f, "Th", token)
	f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
	function f:SetBadge(newText, newTone)
		tone = newTone or tone   -- a badge keeps the tone it last had
		local t = BADGE_TONES[tone or "neutral"] or BADGE_TONES.neutral
		Theme.Tint(self.fill, t, 0.16)
		Theme.Tint(self.dot, t, 0.16)
		Theme.Text(self.label, t)
		self.label:SetText(newText or "")
		local short = #(newText or "") <= 2
		self.dot:SetShown(short)
		self.fill:SetShown(not short)
		self:SetSize(short and 24 or max(24, self.label:GetStringWidth() + 20), 24)
	end
	f:SetBadge(text, tone)
	return f
end

-- --- Tabs (underline) -------------------------------------------------------------------------------------------------

-- tabs: { { id = "roster", text = "Roster", badge = "3"?, tone = "accent"? }, ... }. The active tab is text-1 with a 2 pt
-- accent bar under it that slides to the next one in 200 ms; the others text-3 (text-2 on hover). A tab may carry a count
-- badge (the requests waiting on the Bank tab): the caller passes its text.
-- :Select(id), :Active(), :SetTabShown(id, bool), :SetBadge(id, text|nil, tone), :SetTabText(id, text), :Layout().
-- onSelect(id) runs after a change.
-- When the tabs ask for more room than the bar has (its width less :SetReserve(points), what lies over its right end),
-- they are first drawn closer (10 points each side) and, if they are still too many, the ones that do not fit go into a
-- menu behind a last tab, opts.moreText, which carries the sum of their counts. The active tab always stays on the bar.
-- A bar whose width is not known yet shows every tab.
-- opts.boxed (owner, 2026-11-27): every tab is the same quiet rounded box (surface-2 with a border-subtle ring) with its
-- icon (t.icon, a name of the icon sheet) before the name. The active one differs only as Material Design 3 tabs do: the
-- 2 pt accent underline at the bottom of its box (it slides to the next tab) and its name and icon in text-1 instead of
-- text-2 / text-3. No glow, no accent ring, nothing that makes it look like a lit button (owner's follow-up the same day).
-- Later the same day the owner found the open tab too hard to tell ("the Bank tab is not orange"): its name and icon are
-- in accent-text and its box takes a light accent tint (ACTIVE_TINT), still without a glow or a ring.
Widgets.TAB_ACTIVE_TINT = 0.18   -- the accent's alpha on the open boxed tab's fill
function Widgets.Tabs(parent, tabs, onSelect, opts)
	local BOXED = opts and opts.boxed
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(44)
	bar.buttons, bar.order, bar.hidden, bar.overflow = {}, {}, {}, {}
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border-subtle")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.line:SetHeight(Theme.Px(1))
	bar.indicator = bar:CreateTexture(nil, "ARTWORK")
	Theme.Fill(bar.indicator, "accent")
	bar.indicator:SetHeight(2)
	bar.indicator:Hide()

	local GAP, PAD, TIGHT = BOXED and 6 or 4, BOXED and 14 or 16, 10
	local ICON, ICON_GAP = 14, 6
	-- the box of a boxed tab (fill, ring), 6 points below the bar's top and BOX_BOTTOM above its line
	local BOX_BOTTOM = 2
	local function box(b)
		b.fill = Theme.Slice(b, "rr_fill_8", "surface-2", "BACKGROUND")
		b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -6)
		b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, BOX_BOTTOM)
		b.ring = Theme.Slice(b, "rr_ring_8", "border-subtle", "BORDER")
		b.ring:SetAllPoints(b.fill)
	end
	-- the state layer of a tab (M12.6): the label's colour over the box (boxed) or over the whole tab
	local function stateLayer(b, ink)
		b.over = Widgets.TrackState(b, Widgets.StateLayer(b, ink, { shape = BOXED and 8 or nil, anchor = b.fill }))
	end
	Widgets.TabBox = box
	-- the width of a tab: its text, `pad` points each side, its icon, and the badge when it shows one
	local function wanted(b, pad)
		local w = b.label:GetStringWidth() + 2 * pad
		if b.icon then w = w + ICON + ICON_GAP end
		if b.badge and b.badge:IsShown() then w = w + b.badge:GetWidth() + 6 end
		return max(64, w), w
	end

	local function put(b, x, pad)
		local w, content = wanted(b, pad)
		b:SetWidth(w)
		b:Show()
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
		b.x, b.w = x, w
		b.label:ClearAllPoints()
		local left = (w - content) / 2 + pad
		if b.icon then
			b.icon:ClearAllPoints()
			b.icon:SetPoint("LEFT", b, "LEFT", left, BOXED and -2 or 1)
			left = left + ICON + ICON_GAP
		end
		b.label:SetPoint("LEFT", b, "LEFT", left, BOXED and -2 or 1)
		if b.badge and b.badge:IsShown() then
			b.badge:ClearAllPoints()
			b.badge:SetPoint("LEFT", b.label, "RIGHT", 6, 1)
		end
		return x + w + GAP
	end

	-- The tab that opens the menu of the ones without room; made the first time it is needed.
	local function moreButton()
		if bar.more then return bar.more end
		local more = CreateFrame("Button", nil, bar)
		more:SetHeight(44)
		if BOXED then box(more) end
		more.label = Theme.NewText(more, "Tab", BOXED and "text-2" or "text-3")
		more.label:SetText(opts and opts.moreText or "...")
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
		more:SetScript("OnEnter", function(self) Theme.Text(self.label, "text-2") end)
		more:SetScript("OnLeave", function(self) Theme.Text(self.label, "text-3") end)
		stateLayer(more, BOXED and "text-2" or "text-3")   -- after SetScript: its hooks would be replaced
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
			if not more.badge then more.badge = Widgets.Badge(more, text, "accent") else more.badge:SetBadge(text, "accent") end
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
			for _, id in ipairs(ids) do sum = sum + wanted(bar.buttons[id], pad) + GAP end
			return sum - GAP
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
			if active then left = left - wanted(active, pad) - GAP end
			local full = false
			shown = {}
			for _, id in ipairs(ids) do
				local need = wanted(bar.buttons[id], pad) + GAP
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
		local ind = bar.indicator
		local b = bar.active and bar.buttons[bar.active]
		if not b or bar.hidden[bar.active] or not b.x then
			ind:Hide(); bar.ix, bar.iw = nil, nil
			return
		end
		local inset = BOXED and 12 or 8   -- a boxed tab's underline sits on the bottom of its box, inside the round corners
		local x, w = b.x + inset, b.w - 2 * inset
		local function put(px, pw)
			ind:ClearAllPoints()
			ind:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", px, BOXED and BOX_BOTTOM or 0)
			ind:SetWidth(pw)
			bar.ix, bar.iw = px, pw
		end
		if fromX and ind:IsShown() and changed then
			put(fromX, fromW or w)
			Motion.Slide(ind, x - fromX, 0, Motion.BASE, function() put(x, w) end)   -- 200 ms
		else
			put(x, w)
			local wasShown = ind:IsShown()
			ind:Show()
			if changed and not wasShown then Motion.FadeIn(ind, Motion.BASE) end
		end
	end

	local function paint()
		for id, b in pairs(bar.buttons) do
			local on = id == bar.active
			Widgets.SetStateColor(b.over, on and (BOXED and "accent-text" or "text-1") or (BOXED and "text-2" or "text-3"))
			if BOXED then
				Theme.Text(b.label, on and "accent-text" or "text-2")
				if b.icon then Theme.Tint(b.icon, on and "accent-text" or "text-3") end
				if on then Theme.Tint(b.fill, "accent", Widgets.TAB_ACTIVE_TINT) else Theme.Tint(b.fill, "surface-2") end
				Theme.Tint(b.ring, b.hot and "border-strong" or "border-subtle")
			else
				Theme.Text(b.label, on and "text-1" or "text-3")
				if b.icon then Theme.Tint(b.icon, on and "text-1" or "text-3") end
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
	-- The count badge of a tab: `text` is what the caller wants to show ("3"); nil or "" takes the badge away.
	function bar:SetBadge(id, text, tone)
		local b = self.buttons[id]
		if not b then return false end
		b.count = (text ~= nil and text ~= "") and tostring(text) or nil
		if text == nil or text == "" then
			if b.badge then b.badge:Hide() end
		else
			if not b.badge then b.badge = Widgets.Badge(b, text, tone or "accent") else b.badge:SetBadge(text, tone or "accent") end
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
		local b = CreateFrame("Button", nil, bar)
		b.id = t.id
		b:SetHeight(44)
		if BOXED then box(b) end
		if t.icon and Assets.IconCoords(t.icon) then
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetTexture(Assets.textures.icons.path)
			b.icon:SetTexCoord(Assets.IconCoords(t.icon))
			b.icon:SetSize(ICON, ICON)
			Theme.Tint(b.icon, "text-3")
		end
		b.label = Theme.NewText(b, "Tab", BOXED and "text-2" or "text-3")
		b.label:SetText(t.text or "")
		b:SetScript("OnClick", function() bar:Select(t.id) end)
		b:SetScript("OnEnter", function(self)
			self.hot = true
			if bar.active ~= self.id then
				Theme.Text(self.label, BOXED and "text-1" or "text-2")
				if BOXED then Theme.Tint(self.ring, "border-strong") end
			end
		end)
		b:SetScript("OnLeave", function(self)
			self.hot = false
			if bar.active ~= self.id then
				Theme.Text(self.label, BOXED and "text-2" or "text-3")
				if BOXED then Theme.Tint(self.ring, "border-subtle") end
			end
		end)
		stateLayer(b, BOXED and "text-2" or "text-3")   -- after SetScript: its hooks would be replaced
		bar.buttons[t.id] = b
		bar.order[#bar.order + 1] = t.id
		if t.badge ~= nil and t.badge ~= "" then
			b.count = tostring(t.badge)
			b.badge = Widgets.Badge(b, t.badge, t.tone or "accent")
		end
	end
	layout()
	return bar
end

-- --- Segmented (pill selector) ----------------------------------------------------------------------------------------

-- items: { { id, text } }. A surface-2 pill with the selected segment raised; each segment has a state layer in its
-- label's colour (hover 8 %, pressed 10 %, M12.6). :Select(id), :Active(), :Clear(), :SetEnabled(bool) (locked: the labels
-- at 38 %), :SetItemText(id, text). onSelect(id) runs after a change.
function Widgets.Segmented(parent, items, onSelect)
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetHeight(32)
	seg.fill = Theme.Slice(seg, "rr_fill_12", "surface-2", "BACKGROUND")
	seg.fill:SetAllPoints(seg)
	seg.ring = Theme.Slice(seg, "rr_ring_12", "border", "BORDER")
	seg.ring:SetAllPoints(seg)
	seg.thumb = Theme.Slice(seg, "rr_fill_12", "raised", "ARTWORK")
	seg.thumb:Hide()
	seg.buttons, seg.order = {}, {}

	function seg:Select(id)
		local b = self.buttons[id]
		if not b then return false end
		local changed = self.active ~= id
		self.active = id
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		self.thumb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
		self.thumb:Show()
		for other, ob in pairs(self.buttons) do
			local ink = other == id and "text-1" or "text-3"
			Theme.Text(ob.label, ink)
			Widgets.SetStateColor(ob.over, ink)
		end
		if changed and onSelect then onSelect(id) end
		return true
	end
	function seg:Active() return self.active end
	-- No segment selected (the thumb goes away).
	function seg:Clear()
		self.active = nil
		self.thumb:Hide()
		for _, ob in pairs(self.buttons) do Theme.Text(ob.label, "text-3"); Widgets.SetStateColor(ob.over, "text-3") end
	end
	-- Locked: the segments stop answering clicks and dim; the selection stays visible.
	function seg:SetEnabled(enabled)
		self.enabled = enabled ~= false
		for _, ob in pairs(self.buttons) do
			ob:SetEnabled(self.enabled)
			ob.label:SetAlpha(self.enabled and 1 or Theme.STATE.disabledContent)
			if not self.enabled then ob.hot, ob.pressed = false, false end
			Widgets.SetState(ob.over, Widgets.StateOf(ob))
		end
	end

	local x = 4
	for _, item in ipairs(items) do
		local b = CreateFrame("Button", nil, seg)
		b.over = Widgets.TrackState(b, Widgets.StateLayer(b, "text-3", { shape = 12, layer = "OVERLAY" }))
		b.label = Theme.NewText(b, "BodyMedium", "text-3")
		b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.label:SetText(item.text or "")
		b:SetSize(max(48, b.label:GetStringWidth() + 24), 24)
		b:SetPoint("LEFT", seg, "LEFT", x, 0)
		x = x + b:GetWidth() + 2
		b:SetScript("OnClick", function() seg:Select(item.id) end)
		seg.buttons[item.id] = b
		seg.order[#seg.order + 1] = item.id
	end
	seg:SetWidth(x + 2)
	-- A new text for a segment (a count on a page's name): the segments move to make room.
	function seg:SetItemText(id, text)
		local b = self.buttons[id]
		if not b then return false end
		b.label:SetText(text or "")
		b:SetWidth(max(48, b.label:GetStringWidth() + 24))
		local at = 4
		for _, other in ipairs(self.order) do
			local ob = self.buttons[other]
			ob:ClearAllPoints()
			ob:SetPoint("LEFT", self, "LEFT", at, 0)
			at = at + ob:GetWidth() + 2
		end
		self:SetWidth(at + 2)
		return true
	end
	return seg
end

-- --- Chip (label) -----------------------------------------------------------------------------------------------------

-- A pill with a border (28 high), filled with the accent when selected (the site's filter chip). Hover is a state layer
-- in the label's colour (8 %, M12.6); disabled, the label is at 38 % and the ring at 12 % of text-1.
-- opts: text, onClick(chip), height, font (a Theme font id, default BodyMedium), pad (text padding, default 28).
-- :SetSelected(bool), :IsSelected(), :SetLabel(text), :SetEnabled(bool).
function Widgets.Chip(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(opts.height or 28)
	c.fill = Theme.Slice(c, "rr_fill_12", "surface-2", "BACKGROUND", 0)
	c.fill:SetAllPoints(c)
	c.ring = Theme.Slice(c, "rr_ring_12", "border", "BORDER")
	c.ring:SetAllPoints(c)
	c.over = Widgets.StateLayer(c, "text-2", { shape = 12, fade = false })
	c.label = Theme.NewText(c, opts.font or "BodyMedium", "text-2")
	c.label:SetPoint("CENTER", c, "CENTER", 0, 0)
	function c:Paint()
		local off = not self:IsEnabled()
		if self.selected then
			Theme.Tint(self.fill, "accent", 1)
			Theme.Tint(self.ring, "accent")
			Theme.Text(self.label, "on-accent")
			Widgets.SetStateColor(self.over, "on-accent")
		else
			Theme.Tint(self.fill, "surface-2", 0)
			if off then Theme.Tint(self.ring, "text-1", Theme.STATE.disabledContainer)
			else Theme.Tint(self.ring, self.hot and "border-strong" or "border") end
			Theme.Text(self.label, "text-2")
			Widgets.SetStateColor(self.over, "text-2")
		end
		self.label:SetAlpha(off and Theme.STATE.disabledContent or 1)
		Widgets.SetState(self.over, Widgets.StateOf(self))
	end
	function c:SetLabel(text)
		self.label:SetText(text or "")
		self:SetWidth(max(32, self.label:GetStringWidth() + (opts.pad or 28)))
	end
	function c:SetSelected(selected) self.selected = selected and true or false; self:Paint() end
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
-- a mono subtitle and the close button (`.close`: the caller anchors its own buttons to the left of it).
-- opts: title, subtitle, closeLabel (the tooltip of the close button, translated), onClose.
function Widgets.TitleBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(52)
	bar.fill = Theme.Slice(bar, "rr_fill_12", "surface-1", "BACKGROUND")
	bar.fill:SetAllPoints(bar)
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border-subtle")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 12, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -12, 0)
	bar.line:SetHeight(Theme.Px(1))

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

	bar.close = CreateFrame("Button", nil, bar)
	bar.close:SetSize(28, 28)
	bar.close:SetPoint("RIGHT", bar, "RIGHT", -14, 0)
	-- an icon button: a state layer in the icon's colour (M12.6), no fill of its own
	bar.close.bg = Widgets.TrackState(bar.close, Widgets.StateLayer(bar.close, "text-2", { shape = 8, layer = "BACKGROUND" }))
	bar.close.icon = bar.close:CreateTexture(nil, "OVERLAY")
	bar.close.icon:SetTexture(Assets.textures.icons.path)
	bar.close.icon:SetTexCoord(Assets.IconCoords("cross"))
	bar.close.icon:SetSize(16, 16)
	bar.close.icon:SetPoint("CENTER")
	Theme.Tint(bar.close.icon, "text-2")
	if opts.onClose then bar.close:SetScript("OnClick", opts.onClose) end
	if opts.closeLabel and Widgets.Tooltip then Widgets.Tooltip.Attach(bar.close, opts.closeLabel, "BOTTOM") end
	return bar
end

-- --- Dialog -----------------------------------------------------------------------------------------------------------

-- A modal base: a dark veil (no blur: the engine cannot) over `parent` with a centred card on the DIALOG strata; it enters
-- with Motion.Rise (alpha and a 16 pt rise, 320 ms). Esc closes it (it is added to UISpecialFrames under `name`).
-- opts: width (420), height (220). :Open(), :Close(), .card, .content (the card: the caller adds its own children).
function Widgets.Dialog(parent, name, opts)
	opts = opts or {}
	local d = CreateFrame("Frame", name, parent or UIParent)
	d:SetAllPoints(parent or UIParent)
	d:SetFrameStrata("DIALOG")
	d:EnableMouse(true)   -- the veil swallows clicks
	d.veil = d:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(d.veil, "scrim")
	d.veil:SetAllPoints(d)
	d.card = CreateFrame("Frame", nil, d)
	d.card:SetSize(opts.width or 420, opts.height or 220)
	d.card:SetPoint("CENTER", d, "CENTER", 0, 0)
	d.card.parts = Theme.Panel(d.card, { radius = 18, fill = "surface-1", border = "border", shadow = true, highlight = true })
	d.content = d.card
	d:Hide()
	closeOnEscape(name)
	-- the card rises 16 points while it fades in, 320 ms, the veil fades in 200 ms (both at once with animations off)
	function d:Open()
		self:Show()
		Motion.FadeIn(self.veil, Motion.BASE)
		Motion.Rise(self.card, 16, Motion.SLOW)
	end
	function d:Close() self:Hide() end
	return d
end

-- --- EditBox ----------------------------------------------------------------------------------------------------------

-- A one-line field: surface-2 fill, 1 pt ring (accent while it has the keyboard). opts: width, height, maxLetters,
-- placeholder (text-3, shown while the field is empty and not focused), onChange(text, user) after every edit,
-- onEnter(text). :GetText(), :SetText(text), :Clear(), :SetPlaceholder(text), :SetFocus(), :ClearFocus(). The edit box
-- itself is `.edit`.
function Widgets.EditBox(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 120, opts.height or 28)
	f.fill = Theme.Slice(f, "rr_fill_8", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_8", "border", "BORDER")
	f.ring:SetAllPoints(f)
	local e = CreateFrame("EditBox", nil, f)
	e:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -2)
	e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 2)
	e:SetAutoFocus(false)
	if Theme.fontObjects.Body then e:SetFontObject(Theme.fontObjects.Body) end
	if opts.maxLetters then e:SetMaxLetters(opts.maxLetters) end
	Theme.Text(e, "text-1")
	f.placeholder = Theme.NewText(f, "Body", "text-3")
	f.placeholder:SetPoint("LEFT", f, "LEFT", 10, 0)
	f.placeholder:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	f.placeholder:SetJustifyH("LEFT")
	f.placeholder:SetText(opts.placeholder or "")
	local function hint()
		local empty = (e:GetText() or "") == "" and not f.focused
		f.placeholder:SetShown(empty and (f.placeholder:GetText() or "") ~= "")
	end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if opts.onEnter then opts.onEnter(self:GetText()) end
	end)
	e:SetScript("OnEditFocusGained", function() f.focused = true; Theme.Tint(f.ring, "accent"); hint() end)
	e:SetScript("OnEditFocusLost", function() f.focused = false; Theme.Tint(f.ring, "border"); hint() end)
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
	hint()
	return f
end

-- --- ChoiceList -------------------------------------------------------------------------------------------------------

-- A list of single-choice rows (a radio list: no UIDropDownMenu, which taints, docs/specs/ui-style.md §3) inside a
-- surface-2 field. choices = { { id, text, token? } }; `rows` rows show at once and the mouse wheel scrolls the rest.
-- opts: rows (6), rowHeight (24), width, onSelect(id). :SetChoices(list), :Select(id), :Selected(), :Clear(), :Count(),
-- :Scroll(delta).
function Widgets.ChoiceList(parent, opts)
	opts = opts or {}
	local rows, rowH = opts.rows or 6, opts.rowHeight or 24
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 240, rows * rowH + 8)
	f.fill = Theme.Slice(f, "rr_fill_8", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_8", "border", "BORDER")
	f.ring:SetAllPoints(f)
	f.choices, f.offset, f.rowH, f.rowsShown = {}, 0, rowH, rows
	f:EnableMouseWheel(true)
	f.rows = {}
	for i = 1, rows do
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(rowH)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4 - (i - 1) * rowH)
		b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4 - (i - 1) * rowH)
		b.mark = b:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(b.mark, "raised", 0)
		b.mark:SetAllPoints(b)
		b.dot = b:CreateTexture(nil, "ARTWORK")
		Theme.Fill(b.dot, "accent", 0)
		b.dot:SetSize(6, 6)
		b.dot:SetPoint("LEFT", b, "LEFT", 8, 0)
		b.label = Theme.NewText(b, "Body", "text-2")
		b.label:SetPoint("LEFT", b, "LEFT", 22, 0)
		b.label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
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
				Theme.Text(b.label, on and "text-1" or c.token or "text-2")
				Theme.Fill(b.mark, "raised", on and 1 or 0)
				Theme.Fill(b.dot, "accent", on and 1 or 0)
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

-- A player's name in the class colour of the game (Theme.ClassText: text-1 on the light theme), text-1 for an unknown class.
function Widgets.PaintName(fs, classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then Theme.ClassText(fs, c.r, c.g, c.b) else Theme.Text(fs, "text-1") end
end

-- A row of chips of which one is selected: the modes of a view, the tabs of the bank, a period. onSelect(id) after a
-- click. :SetItems({ { id, text } }, activeId) makes, labels, places and selects the chips (the extra ones hide);
-- :Select(id) marks one; `.buttons[i]` are the chips in order (`.id` each), `.active` the selected id.
function Widgets.ChipRow(parent, onSelect, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(opts.height or 28)
	bar.buttons, bar.gap = {}, opts.gap or 8
	function bar:Select(id)
		self.active = id
		for _, c in ipairs(self.buttons) do c:SetSelected(c:IsShown() and c.id == id) end
	end
	function bar:SetItems(items, active)
		local x = 0
		for i, item in ipairs(items) do
			local c = self.buttons[i]
			if not c then
				c = Widgets.Chip(self, { height = opts.height or 28, onClick = function(chip)
					bar:Select(chip.id)
					if onSelect then onSelect(chip.id) end
				end })
				self.buttons[i] = c
			end
			c.id = item.id
			c:SetLabel(item.text)
			c:ClearAllPoints()
			c:SetPoint("LEFT", self, "LEFT", x, 0)
			x = x + c:GetWidth() + self.gap
			c:Show()
		end
		for i = #items + 1, #self.buttons do self.buttons[i]:Hide() end
		self.width = max(0, x - self.gap)
		self:Select(active)
	end
	return bar
end

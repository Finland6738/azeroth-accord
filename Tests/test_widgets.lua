-- The widget kit (M6.11): Button, IconButton, Card, Divider, Badge, Tabs, Segmented, Chip, ChipRow, TitleBar, Dialog,
-- SideSheet, EditBox, ChoiceList, Switch, Slider, Select, Snackbar, Skeleton, ClassMark, ThinBar, Tooltip, Menu and
-- DataTable (docs/specs/ui-style.md §3). Every widget builds in every theme, follows Theme.Apply without /reload, takes
-- its texts only from what the caller passes, and behaves with the effects and animations preferences off.
-- The measurements, colour roles and states of each component are those of ui-style §9.6 (Material 3, M12.7).
-- Adapted from FDCP's Tests/test_controls.lua and the widget parts of its UI tests, same owner, GPL-3.0 (ADR 0021).

local function Widgets() return AzerothAccord.Widgets end
local function Th() return AzerothAccord.Theme end
local function M() return AzerothAccord.Motion end
local function C() return AzerothAccord.Config end
local function groupOf(frame) return frame._animGroups and frame._animGroups[#frame._animGroups] end
local function first(group) return group._anims[1] end
-- the animation group of `frame` whose first animation is of `kind`
local function groupKind(frame, kind)
	for _, g in ipairs(frame._animGroups or {}) do
		if g._anims[1] and g._anims[1]._kind == kind then return g end
	end
end
local function r1(texture) return (texture:GetVertexColor()) end
local function token1(token, id) return (Th().Color(token, id)) end
-- the colour a texture shows, through its vertex colour or its solid colour
local function colourOf(texture)
	return type(texture._texture) == "table" and texture._texture or texture._vertex
end
local function shows(texture, token, what)
	local r, g, b = Th().Color(token)
	local got = colourOf(texture)
	truthy(got, (what or token) .. ": the texture has no colour")
	near(got[1], r, 1e-6, what or token); near(got[2], g, 1e-6, what or token); near(got[3], b, 1e-6, what or token)
end
local function alphaOf(texture) return colourOf(texture)[4] end
local function inks(fs, token, what)
	local r, g, b = Th().Color(token)
	local fr, fg, fb = fs:GetTextColor()
	near(fr, r, 1e-6, what or token); near(fg, g, 1e-6, what or token); near(fb, b, 1e-6, what or token)
end

-- every region of a frame and of its children, depth first
local function walk(frame, fn)
	fn(frame)
	for _, region in ipairs(frame._regions or {}) do fn(region) end
	for _, child in ipairs(frame._children or {}) do walk(child, fn) end
end
local function count(frame)
	local n = 0
	walk(frame, function() n = n + 1 end)
	return n
end
-- what the colours of a frame tree look like, as one string (textures: vertex colour and solid colour; texts: colour)
local function snapshot(frame)
	local parts = {}
	walk(frame, function(w)
		if w._type == "Texture" then
			local v = w._vertex or { 1, 1, 1, 1 }
			local s = ("T%.3f,%.3f,%.3f,%.3f"):format(v[1], v[2], v[3], v[4])
			if type(w._texture) == "table" then
				s = s .. ("|%.3f,%.3f,%.3f,%.3f"):format(w._texture[1], w._texture[2], w._texture[3], w._texture[4] or 1)
			end
			parts[#parts + 1] = s
		elseif w._type == "FontString" or w._type == "EditBox" then
			local c = w._textColor or { 1, 1, 1, 1 }
			parts[#parts + 1] = ("F%.3f,%.3f,%.3f,%.3f"):format(c[1], c[2], c[3], c[4])
		end
	end)
	return table.concat(parts, ";")
end
local function texts(frame)
	local out = {}
	walk(frame, function(w)
		if (w._type == "FontString" or w._type == "EditBox") and w._text and w._text ~= "" then out[#out + 1] = w._text end
	end)
	return out
end

-- Every widget once, with sentinel texts ("QZ<n>": capitals, so that DataTable's upper-casing of a title leaves them alone).
-- `text` is true when the widget shows text at all.
local function builders()
	local members = {}
	for i = 1, 5 do members[i] = { name = "QZ" .. i, level = i * 10 } end
	return {
		{ "Button filled", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "filled", icon = "plus" }) end },
		{ "Button tonal", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "tonal" }) end },
		{ "Button outlined", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "outlined" }) end },
		{ "Button text", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "text" }) end },
		{ "IconButton", false, function(p) return Widgets().IconButton(p, { icon = "cross" }) end },
		{ "Divider", false, function(p) local f = CreateFrame("Frame", nil, p); Widgets().Divider(f); return f end },
		{ "SideSheet", true, function(p)
			local f = Widgets().SideSheet(p, {})
			f.title:SetText("QZ1"); f.subtitle:SetText("QZ2")
			return f
		end },
		{ "ChipRow", true, function(p)
			local r = Widgets().ChipRow(p)
			r:SetItems({ { id = "a", text = "QZ1" }, { id = "b", text = "QZ2" } }, "a")
			return r
		end },
		{ "ModeMenu", true, function(p)
			local r = Widgets().ModeMenu(p, nil, { label = "QZ3" })
			r:SetItems({ { id = "a", text = "QZ1" }, { id = "b", text = "QZ2" } }, "a")
			return r
		end },
		{ "Card", false, function(p) return Widgets().Card(p, { hover = true, shadow = true }) end },
		{ "Badge", true, function(p) return Widgets().Badge(p, "QZ1", "ok") end },
		{ "Tabs", true, function(p)
			local t = Widgets().Tabs(p, { { id = "a", text = "QZ1", badge = "QZ2" }, { id = "b", text = "QZ3" } })
			t:Select("a")
			return t
		end },
		{ "Segmented", true, function(p)
			local s = Widgets().Segmented(p, { { id = "a", text = "QZ1" }, { id = "b", text = "QZ2" } })
			s:Select("a")
			return s
		end },
		{ "Chip", true, function(p) local c = Widgets().Chip(p, { text = "QZ1" }); c:SetSelected(true); return c end },
		{ "TitleBar", true, function(p) return Widgets().TitleBar(p, { title = "QZ1", subtitle = "QZ2", closeLabel = "QZ3" }) end },
		{ "Dialog", false, function(p) return Widgets().Dialog(p, nil, {}) end },
		{ "EditBox", true, function(p) return Widgets().EditBox(p, { placeholder = "QZ1" }) end },
		{ "ChoiceList", true, function(p)
			local l = Widgets().ChoiceList(p, {})
			l:SetChoices({ { id = 1, text = "QZ1" }, { id = 2, text = "QZ2" } })
			l:Select(1)
			return l
		end },
		{ "Switch", false, function(p) return Widgets().Switch(p, { on = true }) end },
		{ "Slider", false, function(p) return Widgets().Slider(p, { min = 0, max = 10, value = 4 }) end },
		{ "Select", true, function(p)
			return Widgets().Select(p, { placeholder = "QZ1", choices = { { id = "a", text = "QZ2" }, { id = "b", text = "QZ3" } } })
		end },
		{ "Menu", true, function(p)
			return Widgets().Menu.Show(p, { { text = "QZ1", header = true }, { text = "QZ2", checked = true }, { text = "QZ3" } })
		end },
		{ "Snackbar", true, function(p) local s = Widgets().Snackbar(p); s:Say("QZ1", "ok"); return s end },
		{ "Skeleton", false, function(p) return Widgets().Skeleton(p, 100, 12) end },
		{ "ThinBar", false, function(p) local b = Widgets().ThinBar(p, { width = 100 }); b:SetFraction(0.5); return b end },
		{ "DataTable", true, function(p)
			local t = Widgets().DataTable(p, {
				{ id = "name", title = "QZ1", text = function(d) return d.name end },
				{ id = "level", title = "QZ2", mono = true, align = "RIGHT", text = function(d) return "QZ" .. d.level end,
					value = function(d) return d.level end },
			}, { emptyText = "QZ9" })
			t:SetData(members)
			t:SortBy("name")
			return t
		end },
	}
end

describe("the kit", function()
	it("is ns.Widgets: the old look (Skin, Base) is gone (M6.14)", function()
		truthy(AzerothAccord.Widgets)
		isNil(rawget(AzerothAccord, "Kit"), "no second name for the kit (ns.Kit until M6.14)")
		isNil(AzerothAccord.Skin, "UI/Skin.lua is gone")
		for _, name in ipairs({ "Button", "Card", "Badge", "Tabs", "Segmented", "Chip", "TitleBar", "Dialog", "EditBox",
			"ChoiceList", "Switch", "Slider", "Select", "Snackbar", "Skeleton", "ClassMark", "PaintClassMark", "ThinBar",
			"DataTable", "Text", "RowHover", "PaintName", "ChipRow", "ModeMenu" }) do
			eq(type(Widgets()[name]), "function", name)
		end
		eq(type(Widgets().Tooltip.Show), "function")
		eq(type(Widgets().Menu.Show), "function")
		isNil(Widgets().ShowMenu, "the old menu is gone")
		isNil(Widgets().SetTooltip, "the old tooltip is gone")
	end)
end)

describe("every widget in every theme", function()
	it("builds without an error and without a failed repaint", function()
		for _, id in ipairs(Th().List()) do
			Th().Apply(id)
			local before = Th().applyFailures or 0
			local parent = CreateFrame("Frame")
			for _, b in ipairs(builders()) do
				local ok, frame = pcall(b[3], parent)
				truthy(ok, id .. " " .. b[1] .. ": " .. tostring(frame))
				truthy(frame:GetObjectType(), b[1])
			end
			Th().Apply(id)   -- a repaint of everything that was built
			eq(Th().applyFailures or 0, before, id .. ": a region failed to repaint (" .. tostring(Th().lastFailure) .. ")")
		end
	end)

	it("follows a change of theme: the colours change and come back, without /reload", function()
		local parent = CreateFrame("Frame")
		local built = {}
		for _, b in ipairs(builders()) do built[#built + 1] = { name = b[1], frame = b[3](parent) } end
		local before = {}
		for i, b in ipairs(built) do before[i] = snapshot(b.frame) end
		Th().Apply("aurora")
		for i, b in ipairs(built) do
			ne(snapshot(b.frame), before[i], b.name .. " did not follow the theme")
		end
		Th().Apply("nebula")
		for i, b in ipairs(built) do eq(snapshot(b.frame), before[i], b.name .. " did not come back") end
	end)

	it("shows tokens of the current theme: surfaces, text and the accent", function()
		local parent = CreateFrame("Frame")
		local card = Widgets().Card(parent, {})
		local badge = Widgets().Badge(parent, "QZ1", "err")
		local bar = Widgets().ThinBar(parent, { width = 100 })
		for _, id in ipairs(Th().List()) do
			Th().Apply(id)
			near(r1(card.parts.fill), token1("surface-1", id), 1e-6, id)
			near(r1(badge.fill), token1("err", id), 1e-6, id)
			near((badge.label:GetTextColor()), token1("on-error", id), 1e-6, id)
			near(bar.track._texture[1], token1("surface-3", id), 1e-6, id)
			near(bar.fill._texture[1], token1("accent", id), 1e-6, id)
		end
	end)
end)

describe("text comes only from the caller", function()
	it("no widget shows a word it was not given", function()
		local parent = CreateFrame("Frame")
		for _, b in ipairs(builders()) do
			local frame = b[3](parent)
			local seen = texts(frame)
			if b[2] then truthy(#seen > 0, b[1] .. " shows no text at all") end
			for _, text in ipairs(seen) do
				truthy(text:match("^QZ%d+$"), ("%s shows %q, which no caller passed"):format(b[1], text))
			end
		end
	end)

	it("a widget built without texts shows none", function()
		local parent = CreateFrame("Frame")
		local frames = {
			Widgets().Button(parent, {}), Widgets().Chip(parent, {}), Widgets().TitleBar(parent, {}), Widgets().EditBox(parent, {}),
			Widgets().Select(parent, {}), Widgets().Tabs(parent, { { id = "a" } }), Widgets().Segmented(parent, { { id = "a" } }),
			Widgets().DataTable(parent, { { id = "x", text = function() return nil end } }, {}),
		}
		for i, f in ipairs(frames) do eq(#texts(f), 0, "widget " .. i) end
	end)
end)

describe("button (ui-style §9.6)", function()
	local function button(style, opts)
		opts = opts or {}
		opts.text, opts.style = opts.text or "Go", style
		return Widgets().Button(CreateFrame("Frame"), opts)
	end

	it("is 40 high (36 in a toolbar) with the full shape, and its label is label large", function()
		local b = button("filled")
		eq(b:GetHeight(), 40)
		eq(b.fill._asset, "rr_fill_20")
		eq(button("filled", { dense = true }):GetHeight(), 36)
		eq(button("filled", { dense = true }).fill._asset, "rr_fill_18")
		eq(button("outlined", { height = 28 }).ring._asset, "rr_ring_12", "a lower button keeps its ends round")
		eq(b.label:GetFontObject(), Th().Font("label-large"))
	end)

	it("filled: accent and on-accent; tonal: secondary-container; outlined: a border and text-2; text: accent-text", function()
		local filled = button("filled")
		shows(filled.fill, "accent"); inks(filled.label, "on-accent"); falsy(filled.ring)
		local tonal = button("tonal")
		shows(tonal.fill, "secondary-container"); inks(tonal.label, "on-secondary-container"); falsy(tonal.ring)
		local outlined = button("outlined")
		falsy(outlined.fill); shows(outlined.ring, "border"); inks(outlined.label, "text-2")
		local plain = button("text")
		falsy(plain.fill); falsy(plain.ring); inks(plain.label, "accent-text")
	end)

	it("is one of the four kinds, tonal by default, 40 high or 36 dense (the names of M6.11 are gone, M12.8)", function()
		eq(button(nil).kind, "tonal")
		eq(button("primary").kind, "tonal")
		eq(button("filled"):GetHeight(), Widgets().HEIGHT.button)
		eq(button("filled", { dense = true }):GetHeight(), Widgets().HEIGHT.dense)
		isNil(Widgets().BUTTON_ALIASES)
	end)

	it("pads 24 at each side (16 before an icon, 12 for a text button) and fits its text unless given a width", function()
		local clicked = 0
		local b = button("filled", { text = "A longer label", onClick = function() clicked = clicked + 1 end })
		eq(b:GetWidth(), 24 + #"A longer label" * 6 + 24)
		eq(button("text", { text = "A longer label" }):GetWidth(), 12 + #"A longer label" * 6 + 12)
		local icon = button("tonal", { text = "A longer label", icon = "download" })
		eq(icon:GetWidth(), 16 + 20 + 8 + #"A longer label" * 6 + 24)
		eq(icon.icon:GetWidth(), 20)
		local _, relative, relPoint, x = icon.icon:GetPoint(1)
		eq(relative, icon.label); eq(relPoint, "LEFT"); eq(x, -8)
		inks(icon.label, "on-secondary-container"); shows(icon.icon, "on-secondary-container")
		b:SetLabel("Hi")
		eq(b:GetWidth(), 64)
		eq(b:GetLabel(), "Hi")
		local fixed = button("tonal", { width = 150 })
		fixed:SetLabel("A much longer label than the width")
		eq(fixed:GetWidth(), 150)
		Mock.RunScript(b, "OnClick")
		eq(clicked, 1)
	end)

	it("only the filled button has a glow (with the effects on)", function()
		truthy(button("filled").glow)
		for _, style in ipairs({ "tonal", "outlined", "text" }) do falsy(button(style).glow, style) end
	end)

	it("hover lays an 8 % state layer in the label's colour, pressed 10 %, both faded in 120 ms (M12.6)", function()
		local b = button("tonal")
		shows(b.over, "on-secondary-container")
		Mock.RunScript(b, "OnEnter")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.08)
		eq(first(groupOf(b.over)):GetDuration(), 0.12)
		Mock.RunScript(b, "OnMouseDown")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.10)
		Mock.RunScript(b, "OnMouseUp")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.08)   -- still over it
		Mock.RunScript(b, "OnLeave")
		eq(first(groupOf(b.over)):GetToAlpha(), 0)
	end)

	it("a disabled button shows its content at 38 %, its container at 12 % of text-1 and no layer (M12.6)", function()
		local b = button("tonal", { icon = "plus" })
		b:SetEnabled(false)
		near(b.label:GetAlpha(), 0.38, 1e-9)
		near(b.icon:GetAlpha(), 0.38, 1e-9)
		shows(b.fill, "text-1"); near(alphaOf(b.fill), 0.12, 1e-6)
		Mock.RunScript(b, "OnEnter")
		eq(first(groupOf(b.over)):GetToAlpha(), 0)
		b:SetEnabled(true)
		eq(b.label:GetAlpha(), 1)
		shows(b.fill, "secondary-container")
		local o = button("outlined")
		o:SetEnabled(false)
		shows(o.ring, "text-1"); near(alphaOf(o.ring), 0.12, 1e-6)
		local f = button("filled")
		f:SetEnabled(false)
		falsy(f.glow:IsShown(), "a disabled filled button has no glow")
		f:SetEnabled(true)
		truthy(f.glow:IsShown())
	end)

	it("the layer has the colour of the content: darker, not whiter, on Aurora (M12.6)", function()
		local b = button("outlined")
		shows(b.over, "text-2")
		Th().Apply("aurora")
		near(r1(b.over), token1("text-2", "aurora"), 1e-6)
		truthy(r1(b.over) < 0.3, "Aurora's text-2 is a dark blue")
		near(r1(button("filled").over), token1("on-accent", "aurora"), 1e-6)
		Th().Apply("nebula")
	end)

	it("a press shrinks the button to 0.97 in 120 ms and releases it in 120 ms", function()
		local b = button("filled")
		Mock.RunScript(b, "OnMouseDown")
		local down, up = groupKind(b, "Scale"), nil
		for _, g in ipairs(b._animGroups) do if g ~= down and g._anims[1]._kind == "Scale" then up = g end end
		truthy(down:IsPlaying())
		eq(first(down):GetDuration(), 0.12); eq(first(down):GetSmoothing(), "OUT")
		eq((first(down):GetScaleTo()), 0.97)
		Mock.RunScript(b, "OnMouseUp")
		falsy(down:IsPlaying()); truthy(up:IsPlaying())
		eq((first(up):GetScaleTo()), 1)
	end)

	it("with Animations off the layers and the press change nothing but the alpha, at once", function()
		C():Set("account.settings.animations", false)
		local b = button()
		Mock.RunScript(b, "OnEnter")
		near(b.over:GetAlpha(), 0.08, 1e-9)
		falsy(b.over._animGroups)
		Mock.RunScript(b, "OnMouseDown")
		near(b.over:GetAlpha(), 0.10, 1e-9)
		falsy(groupKind(b, "Scale"):IsPlaying())
		Mock.RunScript(b, "OnLeave")
		eq(b.over:GetAlpha(), 0)
	end)
end)

describe("icon button (ui-style §9.6)", function()
	it("is 40 (32 dense) with an icon of 20 in text-2 and a round state layer", function()
		local n = 0
		local b = Widgets().IconButton(CreateFrame("Frame"), { icon = "cross", onClick = function() n = n + 1 end })
		eq(b:GetWidth(), 40); eq(b:GetHeight(), 40)
		eq(b.icon:GetWidth(), 20); eq(b.icon:GetHeight(), 20)
		shows(b.icon, "text-2")
		eq(b.over:GetTexture(), AzerothAccord.Assets.textures.circle.path)
		shows(b.over, "text-2")
		eq(Widgets().IconButton(CreateFrame("Frame"), { icon = "cross", dense = true }):GetWidth(), 32)
		Mock.RunScript(b, "OnEnter")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.08)
		Mock.RunScript(b, "OnMouseDown")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.10)
		Mock.RunScript(b, "OnLeave")
		eq(first(groupOf(b.over)):GetToAlpha(), 0)
		b:Click()
		eq(n, 1)
		b:SetIcon("heart")
		local l, r, t, bottom = AzerothAccord.Assets.IconCoords("heart")
		deepEq(b.icon._texCoord, { l, r, t, bottom })
		b:SetEnabled(false)
		near(b.icon:GetAlpha(), 0.38, 1e-9)
		b:Click()
		eq(n, 1)
	end)

	it("says what it does in a tooltip when it is given one", function()
		local b = Widgets().IconButton(CreateFrame("Frame"), { icon = "cross", tooltip = "Close" })
		Mock.RunScript(b, "OnEnter")
		deepEq(Widgets().Tooltip.Lines(), { "Close" })
		Mock.RunScript(b, "OnLeave")
		falsy(Widgets().Tooltip.IsShown())
	end)
end)

describe("effects off", function()
	it("glows, shadows and the title glow go away and come back with the preference", function()
		local parent = CreateFrame("Frame")
		local primary = Widgets().Button(parent, { style = "filled" })
		local card = Widgets().Card(parent, { shadow = true })
		local bar = Widgets().TitleBar(parent, { title = "QZ1" })
		truthy(primary.glow:IsShown()); truthy(card.parts.shadow:IsShown()); truthy(bar.logoGlow:IsShown())
		C():Set("account.settings.effects", false)
		falsy(primary.glow:IsShown()); falsy(card.parts.shadow:IsShown()); falsy(bar.logoGlow:IsShown())
		falsy(bar.titleGlow:IsShown())
		local later = Widgets().Button(parent, { style = "filled" })
		falsy(later.glow:IsShown(), "a glow made while the effects are off is off")
		C():Set("account.settings.effects", true)
		truthy(primary.glow:IsShown()); truthy(card.parts.shadow:IsShown()); truthy(later.glow:IsShown())
	end)

	it("the light theme draws the glows as soft shadows, not additive light", function()
		local b = Widgets().Button(CreateFrame("Frame"), { style = "filled" })
		truthy(b.glow._additive)
		Th().Apply("aurora")
		falsy(b.glow._additive)
	end)
end)

describe("card and divider (ui-style §9.6)", function()
	it("a filled card is surface-1 with radius 12, padding 16 and no outline or shadow", function()
		local c = Widgets().Card(CreateFrame("Frame"), {})
		eq(c.parts.fill._asset, "rr_fill_12")
		shows(c.parts.fill, "surface-1")
		eq(c.pad, 16)
		falsy(c.parts.ring); falsy(c.parts.shadow)
		truthy(count(c) <= 12, "a card is a handful of regions")
	end)

	it("an outlined card is bg with a border ring; a floating one has a shadow", function()
		local c = Widgets().Card(CreateFrame("Frame"), { outlined = true, shadow = true })
		shows(c.parts.fill, "bg")
		eq(c.parts.ring._asset, "rr_ring_12")
		shows(c.parts.ring, "border")
		truthy(c.parts.shadow)
		shows(Widgets().Card(CreateFrame("Frame"), { fill = "surface-2" }).parts.fill, "surface-2")
	end)

	it("a card with hover shows a state layer of text-1 while the mouse is over it", function()
		local c = Widgets().Card(CreateFrame("Frame"), { hover = true })
		shows(c.over, "text-1")
		Mock.RunScript(c, "OnEnter")
		eq(first(groupOf(c.over)):GetToAlpha(), 0.08)
		Mock.RunScript(c, "OnLeave")
		eq(first(groupOf(c.over)):GetToAlpha(), 0)
	end)

	it("a divider is one pixel of border-subtle", function()
		local d = Widgets().Divider(CreateFrame("Frame"))
		eq(d:GetHeight(), Th().Px(1))
		shows(d, "border-subtle")
	end)
end)

describe("badge (ui-style §9.6)", function()
	local function badge(...) return Widgets().Badge(CreateFrame("Frame"), ...) end

	it("a count badge is the error role: 16 high, full, 4 points each side, from 16 to 34 wide", function()
		local b = badge("3")
		eq(b:GetHeight(), 16); eq(b:GetWidth(), 16)
		eq(b.fill._asset, "rr_fill_8", "radius 8 on 16 points is the full shape")
		shows(b.fill, "err"); near(alphaOf(b.fill), 1, 1e-6)
		inks(b.label, "on-error")
		eq(b.label:GetFontObject(), Th().Font("label-small"))
		b:SetBadge("99+")
		eq(b:GetWidth(), 3 * 6 + 8)
		b:SetBadge("1234567")
		eq(b:GetWidth(), 34)
	end)

	it("without text it is the small badge, a dot of 6", function()
		local b = badge("")
		eq(b:GetWidth(), 6); eq(b:GetHeight(), 6)
		truthy(b.dot:IsShown()); falsy(b.fill:IsShown())
		shows(b.dot, "err")
		b:SetBadge("2")
		falsy(b.dot:IsShown()); truthy(b.fill:IsShown())
	end)

	it("a status label takes its tone at 16 %, fits its text, and keeps the tone it last had", function()
		local b = badge("QZ1", "ok")
		eq(b:GetHeight(), 16); eq(b:GetWidth(), #"QZ1" * 6 + 16)
		shows(b.fill, "ok"); near(alphaOf(b.fill), 0.16, 1e-6); inks(b.label, "ok")
		b:SetBadge("A longer badge text", "warn")
		eq(b:GetWidth(), #"A longer badge text" * 6 + 16)
		inks(b.label, "warn")
		b:SetBadge("x")
		inks(b.label, "warn", "keeps the tone it last had")
		inks(badge("x", "nonsense").label, "text-2")
	end)
end)

describe("filter chip (ui-style §9.6)", function()
	local function chip(opts) return Widgets().Chip(CreateFrame("Frame"), opts or { text = "QZ1" }) end

	it("off: 32 high, radius 8, a border outline, the label in text-2 with 16 points each side", function()
		local c = chip()
		eq(c:GetHeight(), 32); eq(c:GetWidth(), 16 + 18 + 16)
		eq(c.ring._asset, "rr_ring_8"); eq(c.fill._asset, "rr_fill_8")
		truthy(c.ring:IsShown()); falsy(c.fill:IsShown()); falsy(c.check:IsShown())
		shows(c.ring, "border"); inks(c.label, "text-2")
		eq(c.label:GetFontObject(), Th().Font("label-large"))
		local _, _, _, x = c.label:GetPoint(1)
		eq(x, 16)
	end)

	it("selected: the tonal fill, no outline, a check of 18 at 8 from the edge and 8 from the label", function()
		local c = chip()
		c:SetSelected(true)
		truthy(c:IsSelected())
		truthy(c.fill:IsShown()); falsy(c.ring:IsShown()); truthy(c.check:IsShown())
		shows(c.fill, "secondary-container"); shows(c.check, "on-secondary-container")
		inks(c.label, "on-secondary-container")
		eq(c.check:GetWidth(), 18)
		local _, _, _, x = c.check:GetPoint(1)
		eq(x, 8)
		_, _, _, x = c.label:GetPoint(1)
		eq(x, 8 + 18 + 8)
		eq(c:GetWidth(), 8 + 18 + 8 + 18 + 16)
		c:SetSelected(false)
		eq(c:GetWidth(), 50); falsy(c.check:IsShown()); inks(c.label, "text-2")
	end)

	it("tells its caller when it grows or shrinks, once per change", function()
		local seen = {}
		local c = chip({ text = "QZ1", onResize = function(self) seen[#seen + 1] = self:GetWidth() end })
		deepEq(seen, {}, "not for its first size")
		c:SetSelected(true); c:SetSelected(true); c:SetSelected(false)
		deepEq(seen, { 68, 50 })
		c:SetLabel("QZ100")
		eq(seen[3], 62)
	end)

	it("hover is a state layer in the label's colour; clicks only while enabled; disabled 38 % and 12 %", function()
		local n = 0
		local c = chip({ text = "QZ1", onClick = function() n = n + 1 end })
		Mock.RunScript(c, "OnEnter")
		near(c.over:GetAlpha(), 0.08, 1e-9); shows(c.over, "text-2")
		Mock.RunScript(c, "OnMouseDown")
		near(c.over:GetAlpha(), 0.10, 1e-9)
		c:SetSelected(true)
		shows(c.over, "on-secondary-container")
		Mock.RunScript(c, "OnLeave")
		eq(c.over:GetAlpha(), 0)
		Mock.RunScript(c, "OnClick"); eq(n, 1)
		c:SetEnabled(false)
		Mock.RunScript(c, "OnClick"); eq(n, 1)
		near(c.label:GetAlpha(), 0.38, 1e-9)
		shows(c.fill, "text-1"); near(alphaOf(c.fill), 0.12, 1e-6)
		c:SetSelected(false)
		shows(c.ring, "text-1"); near(alphaOf(c.ring), 0.12, 1e-6)
	end)

	it("a row of chips selects one, 8 apart, and places them again when the selected one grows", function()
		local picked
		local row = Widgets().ChipRow(CreateFrame("Frame"), function(id) picked = id end)
		eq(row:GetHeight(), 32)
		row:SetItems({ { id = "a", text = "QZ1" }, { id = "b", text = "QZ2" } }, "a")
		local a, b = row.buttons[1], row.buttons[2]
		local function x(c) local _, _, _, at = c:GetPoint(1) return at end
		eq(x(a), 0); eq(x(b), 68 + 8); eq(row.width, 68 + 8 + 50)
		b:Click()
		eq(picked, "b"); eq(row.active, "b")
		truthy(b:IsSelected()); falsy(a:IsSelected())
		eq(x(b), 50 + 8); eq(row.width, 50 + 8 + 68)
		row:SetItems({ { id = "z", text = "QZ3" } }, "z")
		falsy(b:IsShown()); eq(row.width, 68)
	end)

	it("a Show menu holds the modes of a view in one menu (M13.7: no third row), with the calls of a chip row", function()
		local picked
		local menu = Widgets().ModeMenu(CreateFrame("Frame"), function(id) picked = id end, { label = "Show" })
		eq(menu.label:GetText(), "Show")
		eq(menu.select:GetHeight(), 32)
		menu:SetItems({ { id = "a", text = "QZ1" }, { id = "b", text = "QZ2" } }, "a")
		deepEq(menu.ids, { "a", "b" })
		eq(menu.active, "a"); eq(menu.select:Selected(), "a")
		eq(menu.select.label:GetText(), "QZ1")
		isNil(picked, "SetItems chooses without calling back")
		menu.select:Select("b")
		eq(picked, "b"); eq(menu.active, "b")
		menu:Select("a")
		eq(menu.select.label:GetText(), "QZ1"); eq(picked, "b", "Select from the view is silent")
		truthy(menu.width > menu.select:GetWidth())
	end)
end)

describe("tabs", function()
	local function tabs(onSelect)
		local bar = Widgets().Tabs(CreateFrame("Frame"), {
			{ id = "roster", text = "Roster" }, { id = "prof", text = "Professions" }, { id = "bank", text = "Bank" },
		}, onSelect)
		return bar
	end

	it("selects a tab, calls back once per change and refuses an unknown or hidden one", function()
		local seen = {}
		local bar = tabs(function(id) seen[#seen + 1] = id end)
		truthy(bar:Select("roster"))
		truthy(bar:Select("roster"))
		truthy(bar:Select("prof"))
		deepEq(seen, { "roster", "prof" })
		eq(bar:Active(), "prof")
		falsy(bar:Select("nope"))
		bar:SetTabShown("bank", false)
		falsy(bar:Select("bank"))
		falsy(bar.buttons.bank:IsShown())
	end)

	it("is 48 high with a divider, the active label in accent-text and the others text-2, no box and no glow", function()
		local bar = tabs()
		bar:Select("prof")
		eq(bar:GetHeight(), 48); eq(bar.buttons.prof:GetHeight(), 48)
		shows(bar.line, "border"); eq(bar.line:GetHeight(), Th().Px(1))
		inks(bar.buttons.prof.label, "accent-text")
		inks(bar.buttons.roster.label, "text-2")
		for _, b in pairs(bar.buttons) do
			falsy(b.fill); falsy(b.ring); falsy(b.glow)
		end
		eq(bar.buttons.prof.label:GetFontObject(), Th().Font("Tab"))
	end)

	it("a state layer in the tab's own colour shows the mouse; the label keeps its colour", function()
		local bar = tabs()
		bar:Select("prof")
		local off, on = bar.buttons.roster, bar.buttons.prof
		shows(off.over, "text-2"); shows(on.over, "accent-text")
		Mock.RunScript(off, "OnEnter")
		eq(first(groupOf(off.over)):GetToAlpha(), 0.08)
		inks(off.label, "text-2")
		Mock.RunScript(off, "OnMouseDown")
		eq(first(groupOf(off.over)):GetToAlpha(), 0.10)
		Mock.RunScript(off, "OnLeave")
		eq(first(groupOf(off.over)):GetToAlpha(), 0)
	end)

	it("a tab with an icon draws it 20 points before the name, in the name's colour, filled while chosen", function()
		local bar = Widgets().Tabs(CreateFrame("Frame"), { { id = "a", text = "Roster", icon = "users" }, { id = "b", text = "Bank" } })
		bar:Select("a")
		local b = bar.buttons.a
		eq(b.icon:GetWidth(), 20); eq(b.content, 20 + 8 + 36); eq(b.w, 64 + 32)
		shows(b.icon, "accent-text")
		deepEq(b.icon._texCoord, { AzerothAccord.Assets.IconCoords("users", true) })
		bar:Select("b")
		shows(b.icon, "text-2")
		deepEq(b.icon._texCoord, { AzerothAccord.Assets.IconCoords("users") })
	end)

	it("the indicator is 3 high with round top corners, under the content: 2 points in, at least 24 wide", function()
		local bar = tabs()
		bar:Select("roster")
		local b1, b2 = bar.buttons.roster, bar.buttons.prof
		eq(b1.x, 0); eq(b1.w, 68); eq(b2.x, 68, "the tabs abut"); eq(b2.w, 98)
		local ind = bar.indicator
		truthy(ind:IsShown())
		eq(ind:GetHeight(), 3)
		shows(ind.middle, "accent"); shows(ind.left, "accent"); shows(ind.right, "accent")
		eq(ind.left:GetWidth(), 3); eq(ind.left:GetHeight(), 3)
		eq(ind.left:GetTexture(), AzerothAccord.Assets.textures.circle.path)
		deepEq(ind.left._texCoord, { 0, 0.5, 0, 0.5 }); deepEq(ind.right._texCoord, { 0.5, 1, 0, 0.5 })
		local _, _, _, x, y = ind:GetPoint(1)
		eq(x, 18); eq(y, 0); eq(ind:GetWidth(), 36 - 4)
		bar:Select("bank")
		Mock.FinishAnimations()
		eq(ind:GetWidth(), 24, "a short name still has an indicator of 24")
		_, _, _, x = ind:GetPoint(1)
		eq(x, bar.buttons.bank.x + (64 - 24) / 2)
	end)

	it("the indicator slides to the next tab in 200 ms and rests under it", function()
		local bar = tabs()
		bar:Select("roster")
		Mock.FinishAnimations()
		bar:Select("prof")
		local g = groupKind(bar.indicator, "Translation")
		truthy(g and g:IsPlaying(), "a Translation group is playing")
		eq(first(g):GetDuration(), 0.2); eq(first(g):GetSmoothing(), "OUT")
		eq((first(g):GetOffset()), 86 - 18)
		Mock.FinishAnimations()
		local _, _, _, x = bar.indicator:GetPoint(1)
		eq(x, 86)
		eq(bar.indicator:GetWidth(), 62)
	end)

	it("after the bar changes width the indicator does not slide from its old place: it is simply there (2026-11-27)", function()
		local bar = tabs()
		bar:Select("roster")
		Mock.FinishAnimations()
		bar:SetWidth(bar:GetWidth() + 400)   -- the window was resized: the old place belongs to another layout
		bar:Select("prof")
		local g = groupKind(bar.indicator, "Translation")
		falsy(g and g:IsPlaying(), "no slide from a place of another layout")
		local _, _, _, x = bar.indicator:GetPoint(1)
		eq(x, 86)
	end)

	it("a second click during a slide does not start from the stale place: it stops and rests", function()
		local bar = tabs()
		bar:Select("roster")
		Mock.FinishAnimations()
		bar:Select("prof")
		bar:Select("bank")
		local _, _, _, x = bar.indicator:GetPoint(1)
		eq(x, 186)
		falsy(bar.indicator.sliding)
	end)

	it("with Animations off the indicator is simply there", function()
		C():Set("account.settings.animations", false)
		local bar = tabs()
		bar:Select("roster"); bar:Select("bank")
		falsy(bar.indicator._animGroups)
		local _, _, _, x = bar.indicator:GetPoint(1)
		eq(x, 186)
	end)

	it("a tab may carry a count badge (the error role): it widens the tab and goes away when the count is nil", function()
		local bar = tabs()
		bar:Select("bank")
		local w = bar.buttons.bank.w
		truthy(bar:SetBadge("bank", "3"))
		local badge = bar.buttons.bank.badge
		truthy(badge:IsShown()); eq(badge.label:GetText(), "3")
		eq(bar.buttons.bank.w, #"Bank" * 6 + 4 + badge:GetWidth() + 32)
		shows(badge.fill, "err"); inks(badge.label, "on-error")
		eq(bar.indicator:GetWidth(), bar.buttons.bank.content - 4, "the indicator follows the new width")
		bar:SetBadge("bank", "12")
		eq(badge.label:GetText(), "12")
		bar:SetBadge("bank", nil)
		falsy(badge:IsShown()); eq(bar.buttons.bank.w, w)
		falsy(bar:SetBadge("nope", "1"))
	end)

	it("a badge given with the tab is there from the start, and the tab text can change", function()
		local bar = Widgets().Tabs(CreateFrame("Frame"), { { id = "bank", text = "Bank", badge = "5" } })
		truthy(bar.buttons.bank.badge:IsShown())
		bar:SetTabText("bank", "Banca")
		eq(bar.buttons.bank.label:GetText(), "Banca")
		eq(bar.buttons.bank.w, #"Banca" * 6 + 4 + bar.buttons.bank.badge:GetWidth() + 32)
	end)

	it("hiding the active tab selects the next one that shows", function()
		local bar = tabs()
		bar:Select("roster")
		bar:SetTabShown("roster", false)
		eq(bar:Active(), "prof")
		eq(bar.buttons.prof.x, 0, "the tabs close the gap")
	end)
end)

describe("segmented buttons (ui-style §9.6)", function()
	local function make(onSelect, opts)
		return Widgets().Segmented(CreateFrame("Frame"), { { id = "a", text = "Settings" }, { id = "b", text = "Info" },
			{ id = "c", text = "Look" } }, onSelect, opts)
	end

	it("32 high (40 on request), one outline of the full shape, segments side by side with a divider", function()
		local seg = make()
		eq(seg:GetHeight(), 32)
		eq(seg.ring._asset, "rr_ring_16"); shows(seg.ring, "border")
		local a, b = seg.buttons.a, seg.buttons.b
		eq(a:GetWidth(), 12 + 18 + 8 + 48 + 12, "12 points each side and the room of the check")
		eq(b:GetWidth(), 12 + 18 + 8 + 24 + 12)
		eq(seg:GetWidth(), a:GetWidth() + b:GetWidth() + seg.buttons.c:GetWidth())
		local _, _, _, x = b:GetPoint(1)
		eq(x, a:GetWidth(), "the segments abut")
		falsy(a.divider); eq(b.divider:GetWidth(), Th().Px(1)); shows(b.divider, "border")
		local large = make(nil, { dense = false })
		eq(large:GetHeight(), 40); eq(large.ring._asset, "rr_ring_20"); eq(large.buttons.a:GetHeight(), 40)
	end)

	it("the chosen segment is secondary-container with a check; the others are text-1", function()
		local seg = make()
		local a, b = seg.buttons.a, seg.buttons.b
		falsy(a.check:IsShown()); falsy(a.middle:IsShown())
		seg:Select("a")
		truthy(a.check:IsShown()); eq(a.check:GetWidth(), 18)
		for _, part in ipairs(a.selection) do truthy(part:IsShown()); shows(part, "secondary-container") end
		eq(#a.selection, 2, "a half circle closes the first segment")
		eq(#b.selection, 1, "a middle segment is flat")
		eq(#seg.buttons.c.selection, 2)
		inks(a.label, "on-secondary-container"); inks(b.label, "text-1")
		local _, _, _, x = a.label:GetPoint(1)
		eq(x, (18 + 8) / 2, "the check and the label are centred together")
		local _, relative, relPoint, gap = a.check:GetPoint(1)
		eq(relative, a.label); eq(relPoint, "LEFT"); eq(gap, -8)
		falsy(b.check:IsShown())
		for _, part in ipairs(b.selection) do falsy(part:IsShown()) end
	end)

	it("selects one segment at a time, clears, shows the mouse and locks", function()
		local seen = {}
		local seg = make(function(id) seen[#seen + 1] = id end)
		truthy(seg:Select("a")); truthy(seg:Select("b")); truthy(seg:Select("b"))
		deepEq(seen, { "a", "b" })
		falsy(seg:Select("zzz"))
		seg:Clear()
		falsy(seg:Active()); falsy(seg.buttons.b.check:IsShown())
		Mock.RunScript(seg.buttons.a, "OnEnter")
		eq(first(groupOf(seg.buttons.a.over)):GetToAlpha(), 0.08)   -- faded in 120 ms
		Mock.RunScript(seg.buttons.a, "OnLeave")
		seg:Select("a")
		seg:SetEnabled(false)
		near(seg.buttons.a.label:GetAlpha(), 0.38, 1e-9)
		falsy(seg.buttons.a:IsEnabled())
		shows(seg.buttons.a.middle, "text-1"); near(alphaOf(seg.buttons.a.middle), 0.12, 1e-6)
		shows(seg.ring, "text-1")
		seg:SetEnabled(true)
		shows(seg.buttons.a.middle, "secondary-container")
	end)

	it("a new text moves the segments", function()
		local seg = make()
		local before = seg:GetWidth()
		truthy(seg:SetItemText("b", "Information"))
		eq(seg:GetWidth(), before + (11 - 4) * 6)
		falsy(seg:SetItemText("zzz", "x"))
	end)
end)

describe("title bar", function()
	it("has the logo, the title in the display face, the subtitle and a close button", function()
		local closed = 0
		local bar = Widgets().TitleBar(CreateFrame("Frame"), { title = "Azeroth Accord", subtitle = "sync", onClose = function() closed = closed + 1 end })
		eq(bar:GetHeight(), 52)
		eq(bar.logo:GetTexture(), AzerothAccord.Assets.logos.logo_64.path)
		eq(bar.title:GetText(), "Azeroth Accord"); eq(bar.subtitle:GetText(), "sync")
		eq(bar.title:GetFontObject(), Th().fontObjects.Display)
		eq(bar.close:GetWidth(), 32, "a dense icon button")
		eq(bar.close.icon:GetWidth(), 20)
		Mock.RunScript(bar.close, "OnClick")
		eq(closed, 1)
		local l, r, t, b = AzerothAccord.Assets.IconCoords("cross")
		deepEq(bar.close.icon._texCoord, { l, r, t, b })
	end)

	it("the title glow is a text shadow on the dark themes and none on the light one", function()
		local bar = Widgets().TitleBar(CreateFrame("Frame"), { title = "QZ1" })
		truthy(bar.title._glowing)
		Th().Apply("aurora")
		falsy(bar.title._glowing)
	end)

	it("the close button has a tooltip when it is given a label", function()
		local bar = Widgets().TitleBar(CreateFrame("Frame"), { title = "QZ1", closeLabel = "Close" })
		Mock.RunScript(bar.close, "OnEnter")
		truthy(Widgets().Tooltip.IsShown())
		deepEq(Widgets().Tooltip.Lines(), { "Close" })
		Mock.RunScript(bar.close, "OnLeave")
		falsy(Widgets().Tooltip.IsShown())
	end)
end)

describe("dialog", function()
	it("Esc closes it: its name is in UISpecialFrames, once", function()
		local d = Widgets().Dialog(nil, "AzerothAccordTestDialog", {})
		contains(UISpecialFrames, "AzerothAccordTestDialog")
		Widgets().CloseOnEscape("AzerothAccordTestDialog")
		local n = 0
		for _, name in ipairs(UISpecialFrames) do if name == "AzerothAccordTestDialog" then n = n + 1 end end
		eq(n, 1)
		falsy(d:IsShown())
		d:Open()
		truthy(d:IsShown())
		-- what the client does on Esc: it hides the visible frames of the list
		for _, name in ipairs(UISpecialFrames) do
			local f = _G[name]
			if f and f.IsShown and f:IsShown() then f:Hide() end
		end
		falsy(d:IsShown())
	end)

	it("a veil on the DIALOG strata with a centred card that rises while it fades in", function()
		local d = Widgets().Dialog(CreateFrame("Frame"), nil, { width = 300, height = 150 })
		eq(d:GetFrameStrata(), "DIALOG")
		eq(d.card:GetWidth(), 300); eq(d.card:GetHeight(), 150)
		near(d.veil._texture[1], token1("scrim"), 1e-6)
		d:Open()
		local _, _, _, _, y = d.card:GetPoint(1)
		eq(y, -16, "starts 16 points low")
		eq(first(groupKind(d.card, "Alpha")):GetDuration(), 0.32)
		Mock.FinishAnimations()
		_, _, _, _, y = d.card:GetPoint(1)
		eq(y, 0); eq(d.card:GetAlpha(), 1)
		d:Close()
		falsy(d:IsShown())
	end)

	it("with Animations off it opens at once, in place", function()
		C():Set("account.settings.animations", false)
		local d = Widgets().Dialog(CreateFrame("Frame"), nil, {})
		d:Open()
		local _, _, _, _, y = d.card:GetPoint(1)
		eq(y, 0); eq(d.card:GetAlpha(), 1)
		falsy(d.card._animGroups)
	end)

	it("is surface-3 with radius 28, a shadow and no outline; 420 wide, at least 280", function()
		local d = Widgets().Dialog(CreateFrame("Frame"), nil, {})
		eq(d.content, d.card)
		eq(d.card:GetWidth(), 420)
		eq(d.card.parts.fill._asset, "rr_fill_28")
		shows(d.card.parts.fill, "surface-3")
		truthy(d.card.parts.shadow); falsy(d.card.parts.ring)
		eq(Widgets().Dialog(CreateFrame("Frame"), nil, { width = 100 }).card:GetWidth(), 280)
	end)

	it("pads 24: a title large at the top, the buttons at the bottom right 8 apart", function()
		local d = Widgets().Dialog(CreateFrame("Frame"), nil, {})
		local title = d:SetTitle("Title")
		eq(title:GetText(), "Title"); eq(title:GetFontObject(), Th().Font("title-large")); inks(title, "text-1")
		local _, _, _, x, y = title:GetPoint(1)
		eq(x, 24); eq(y, -24)
		eq(d:SetTitle("Other"), title)
		local cancel = Widgets().Button(d.card, { style = "text", text = "No" })
		local ok = Widgets().Button(d.card, { style = "filled", text = "Yes" })
		d:SetActions({ cancel, ok })
		local point, relative, _, ox, oy = ok:GetPoint(1)
		eq(point, "BOTTOMRIGHT"); eq(relative, d.card); eq(ox, -24); eq(oy, 24)
		point, relative, _, ox = cancel:GetPoint(1)
		eq(point, "RIGHT"); eq(relative, ok); eq(ox, -8)
	end)
end)

describe("side sheet (ui-style §9.6)", function()
	it("is surface-1 with radius 16 and a shadow, at most 400 wide, with a header of 72 and padding 24 (16 dense)", function()
		local closed = 0
		local f = Widgets().SideSheet(CreateFrame("Frame"), { width = 600, indent = 20, onClose = function() closed = closed + 1 end })
		eq(f:GetWidth(), 400)
		eq(Widgets().SideSheet(CreateFrame("Frame"), { width = 300 }):GetWidth(), 300)
		eq(f.parts.fill._asset, "rr_fill_16"); shows(f.parts.fill, "surface-1")
		truthy(f.parts.shadow); falsy(f.parts.ring)
		eq(f.header, 72); eq(f.pad, 24)
		eq(f.title:GetFontObject(), Th().Font("title-large")); inks(f.title, "text-1")
		eq(f.subtitle:GetFontObject(), Th().Font("body-small")); inks(f.subtitle, "text-2")
		local _, _, _, x = f.title:GetPoint(1)
		eq(x, 24 + 20)
		eq(f.close:GetWidth(), 32)
		local _, _, _, cx, cy = f.close:GetPoint(1)
		eq(cx, -16); eq(cy, -20, "in the middle of the header")
		f.close:Click()
		eq(closed, 1)
		f:SetPad(16)
		_, _, _, x = f.title:GetPoint(1)
		eq(x, 16 + 20)
		_, _, _, cx = f.close:GetPoint(1)
		eq(cx, -8)
	end)
end)

describe("edit box", function()
	local function box(opts) return Widgets().EditBox(CreateFrame("Frame"), opts or {}) end

	it("shows its placeholder while empty and unfocused, and gets out of the way", function()
		local b = box({ placeholder = "Search" })
		truthy(b.placeholder:IsShown()); eq(b.placeholder:GetText(), "Search")
		b.edit:SetFocus()
		falsy(b.placeholder:IsShown())
		b.edit:ClearFocus()
		truthy(b.placeholder:IsShown())
		b:SetText("abc")
		falsy(b.placeholder:IsShown())
		b:Clear()
		truthy(b.placeholder:IsShown())
		b:SetPlaceholder("Other")
		eq(b.placeholder:GetText(), "Other")
		b:SetPlaceholder(nil)
		falsy(b.placeholder:IsShown())
	end)

	it("is 40 high with radius 4: a border outline, border-strong under the mouse, 2 points of accent with focus", function()
		local b = box()
		eq(b:GetHeight(), 40)
		eq(b.fill._asset, "rr_fill_4"); eq(b.ring._asset, "rr_ring_4"); eq(b.focusRing._asset, "rr_ring2_4")
		shows(b.fill, "surface-2"); shows(b.ring, "border")
		falsy(b.focusRing:IsShown())
		eq(b.placeholder:GetFontObject(), Th().Font("Body"))
		Mock.RunScript(b.edit, "OnEnter")
		shows(b.ring, "border-strong")
		Mock.RunScript(b.edit, "OnLeave")
		shows(b.ring, "border")
		b.edit:SetFocus()
		truthy(b.focusRing:IsShown()); falsy(b.ring:IsShown()); shows(b.focusRing, "accent")
		b.edit:ClearFocus()
		falsy(b.focusRing:IsShown()); truthy(b.ring:IsShown())
		b:SetEnabled(false)
		near(b.edit:GetAlpha(), 0.38, 1e-9)
		shows(b.ring, "text-1"); near(alphaOf(b.ring), 0.12, 1e-6)
		falsy(b.edit:IsEnabled())
	end)

	it("reports every edit with the text and whether the player typed it", function()
		local got = {}
		local b = box({ onChange = function(text, user) got[#got + 1] = { text, user } end })
		Mock.TypeInto(b.edit, "ab")
		b:SetText("c")
		deepEq(got, { { "ab", true }, { "c", false } })
		eq(b:GetText(), "c")
	end)

	it("Enter reports the text and leaves the field, Esc leaves it", function()
		local entered
		local b = box({ onEnter = function(text) entered = text end })
		b.edit:SetFocus()
		b:SetText("go")
		Mock.RunScript(b.edit, "OnEnterPressed")
		eq(entered, "go"); falsy(b.edit:HasFocus())
		b.edit:SetFocus()
		Mock.RunScript(b.edit, "OnEscapePressed")
		falsy(b.edit:HasFocus())
	end)
end)

describe("choice list", function()
	it("selects one row, reports a change once and scrolls the rest with the wheel", function()
		local picked = {}
		local list = Widgets().ChoiceList(CreateFrame("Frame"), { rows = 3, onSelect = function(id) picked[#picked + 1] = id end })
		local choices = {}
		for i = 1, 8 do choices[i] = { id = i, text = "Row " .. i } end
		list:SetChoices(choices)
		eq(list:Count(), 8)
		eq(list.rows[1]:IsShown(), true); eq(list.rows[1].label:GetText(), "Row 1")
		truthy(list:Select(2)); truthy(list:Select(2))
		deepEq(picked, { 2 })
		falsy(list:Select(99))
		inks(list.rows[2].label, "on-secondary-container")
		inks(list.rows[1].label, "text-1")
		truthy(list.rows[2].mark:IsShown()); falsy(list.rows[1].mark:IsShown())
		shows(list.rows[2].mark, "secondary-container")
		eq(list.rows[1]:GetHeight(), 32); eq(list:GetHeight(), 3 * 32 + 8)
		eq(list.fill._asset, "rr_fill_4"); shows(list.fill, "surface-2")
		local _, _, _, left = list.rows[1].label:GetPoint(1)
		eq(left, 12)
		Mock.RunScript(list.rows[1], "OnEnter")
		near(list.rows[1].over:GetAlpha(), 0.08, 1e-9); shows(list.rows[1].over, "text-1")
		Mock.RunScript(list.rows[1], "OnLeave")
		Mock.RunScript(list, "OnMouseWheel", -1)
		eq(list.rows[1].label:GetText(), "Row 3")
		list:Scroll(100)
		eq(list.rows[3].label:GetText(), "Row 8")
		list:Scroll(-100)
		eq(list.rows[1].label:GetText(), "Row 1")
		Mock.RunScript(list.rows[1], "OnClick")
		deepEq(picked, { 2, 1 })
		list:Clear()
		isNil(list:Selected())
	end)

	it("a new list keeps the selection only when it is still there", function()
		local list = Widgets().ChoiceList(CreateFrame("Frame"), { rows = 2 })
		list:SetChoices({ { id = "a", text = "A" }, { id = "b", text = "B" } })
		list:Select("b")
		list:SetChoices({ { id = "b", text = "B" } })
		eq(list:Selected(), "b")
		list:SetChoices({ { id = "c", text = "C" } })
		isNil(list:Selected())
		list:SetChoices(nil)
		eq(list:Count(), 0)
		falsy(list.rows[1]:IsShown())
	end)

	it("a choice can carry its own token for its text", function()
		local list = Widgets().ChoiceList(CreateFrame("Frame"), { rows = 2 })
		list:SetChoices({ { id = "a", text = "A", token = "err" } })
		near((list.rows[1].label:GetTextColor()), token1("err"), 1e-6)
	end)
end)

describe("switch (ui-style §9.6)", function()
	local function make(opts) return Widgets().Switch(CreateFrame("Frame"), opts or {}) end

	it("a track of 52 x 32; off: raised with 2 points of border-strong and a handle of 16", function()
		local s = make()
		eq(s:GetWidth(), 52); eq(s:GetHeight(), 32)
		eq(s.track._asset, "rr_fill_16"); eq(s.ring._asset, "rr_ring2_16")
		shows(s.track, "raised"); shows(s.ring, "border-strong"); truthy(s.ring:IsShown())
		shows(s.thumb, "text-2")
		eq(s.thumb:GetWidth(), 16); eq(s.thumb:GetHeight(), 16)
		local _, _, _, x = s.thumb:GetPoint(1)
		eq(x, 16 - 8)
	end)

	it("on: the accent track without outline and a handle of 24 in on-accent", function()
		local s = make({ on = true })
		truthy(s:IsOn())
		shows(s.track, "accent"); falsy(s.ring:IsShown()); shows(s.thumb, "on-accent")
		eq(s.thumb:GetWidth(), 24)
		local _, _, _, x = s.thumb:GetPoint(1)
		eq(x, 36 - 12)
		Th().Apply("accord")
		near(r1(s.track), token1("accent", "accord"), 1e-6)
		s:SetOn(false, true)
		near(r1(s.track), token1("raised", "accord"), 1e-6)
	end)

	it("toggles on click, reports the change and slides the handle", function()
		local seen
		local s = make({ onChange = function(on) seen = on end })
		falsy(s:IsOn())
		Mock.RunScript(s, "OnClick")
		truthy(s:IsOn()); eq(seen, true)
		eq(first(groupOf(s.thumb))._kind, "Translation")
		eq((first(groupOf(s.thumb)):GetOffset()), 20)
		Mock.FinishAnimations()
		local _, _, _, x = s.thumb:GetPoint(1)
		eq(x, 24)
		Mock.RunScript(s, "OnClick")
		falsy(s:IsOn()); eq(seen, false)
	end)

	it("a round state layer of 40 follows the handle", function()
		local s = make()
		eq(s.over:GetWidth(), 40)
		local _, relative = s.over:GetPoint(1)
		eq(relative, s.thumb)
		shows(s.over, "text-1")
		Mock.RunScript(s, "OnEnter")
		eq(first(groupOf(s.over)):GetToAlpha(), 0.08)
		s:SetOn(true, true)
		shows(s.over, "accent")
	end)

	it("SetOn with silent does not call back; disabled it ignores clicks, the handle at 38 % and the track at 12 %", function()
		local n = 0
		local s = make({ onChange = function() n = n + 1 end })
		s:SetOn(true, true)
		eq(n, 0); truthy(s:IsOn())
		s:SetEnabled(false)
		Mock.RunScript(s, "OnClick")
		truthy(s:IsOn()); eq(n, 0)
		near(s.thumb:GetAlpha(), 0.38, 1e-9)
		shows(s.track, "text-1"); near(alphaOf(s.track), 0.12, 1e-6)
		s:SetEnabled(true)
		shows(s.track, "accent")
	end)

	it("with Animations off the handle is at its place at once", function()
		C():Set("account.settings.animations", false)
		local s = make()
		s:SetOn(true)
		falsy(s.thumb._animGroups)
		local _, _, _, x = s.thumb:GetPoint(1)
		eq(x, 24)
	end)
end)

describe("slider", function()
	it("rounds to the step, clamps, and reports a user change", function()
		local got
		local s = Widgets().Slider(CreateFrame("Frame"), { min = 0, max = 10, step = 2, value = 3, onChange = function(v, user) got = { v, user } end })
		eq(s:GetValue(), 4)
		s:Set(99); eq(s:GetValue(), 10)
		s:Set(-5); eq(s:GetValue(), 0)
		Mock.RunScript(s, "OnValueChanged", 6, true)
		deepEq(got, { 6, true })
		Mock.RunScript(s, "OnValueChanged", 8, false)
		deepEq(got, { 8, false })
	end)

	it("the fill follows the value and the thumb takes the text colour", function()
		local s = Widgets().Slider(CreateFrame("Frame"), { min = 0, max = 100, value = 50, width = 200 })
		eq(s.fill:GetWidth(), 100)
		shows(s.track, "surface-3"); shows(s.fill, "accent")
		s:Set(100); eq(s.fill:GetWidth(), 200)
		s:Set(0); eq(s.fill:GetWidth(), 1)
		near(r1(s.thumb), token1("text-1"), 1e-6)
		Th().Apply("aurora")
		near(r1(s.thumb), token1("text-1", "aurora"), 1e-6)
	end)
end)

describe("select", function()
	local function make(onSelect)
		return Widgets().Select(CreateFrame("Frame"), { width = 160, onSelect = onSelect, placeholder = "Pick",
			choices = { { id = "a", text = "Alpha" }, { id = "b", text = "Beta" } } })
	end

	it("is a field of 32 with radius 4; its menu is surface-2, as wide as the field (at least 112), rows of 32", function()
		local s = make()
		eq(s:GetHeight(), 32); eq(s.fill._asset, "rr_fill_4"); shows(s.fill, "surface-2"); shows(s.ring, "border")
		eq(s.popup:GetWidth(), 160)
		eq(s.popup:GetHeight(), 2 * 32 + 8, "no taller than its choices")
		eq(s.list.rows[1]:GetHeight(), 32)
		truthy(s.list.shadow); falsy(s.list.ring:IsShown())
		eq(Widgets().Select(CreateFrame("Frame"), { width = 60 }).popup:GetWidth(), 112)
		Mock.RunScript(s, "OnEnter")
		shows(s.ring, "border-strong")
		s:SetEnabled(false)
		near(s.label:GetAlpha(), 0.38, 1e-9)
		shows(s.ring, "text-1"); near(alphaOf(s.ring), 0.12, 1e-6)
	end)

	it("shows the placeholder, opens a list on click and closes on a second click", function()
		local s = make()
		eq(s.label:GetText(), "Pick")
		near((s.label:GetTextColor()), token1("text-3"), 1e-6)
		Mock.RunScript(s, "OnClick")
		truthy(s:IsOpen())
		Mock.RunScript(s, "OnClick")
		falsy(s:IsOpen())
	end)

	it("choosing closes the list, shows the text and calls back once", function()
		local n, got = 0
		local s = make(function(id) n = n + 1; got = id end)
		s:Open()
		truthy(s:Select("b"))
		falsy(s:IsOpen())
		eq(s.label:GetText(), "Beta"); eq(got, "b")
		near((s.label:GetTextColor()), token1("text-1"), 1e-6)
		s:Select("b"); eq(n, 1)
		falsy(s:Select("zzz"))
		eq(s:Selected(), "b")
	end)

	it("clicking a row of the open list chooses it", function()
		local got
		local s = make(function(id) got = id end)
		s:Open()
		Mock.RunScript(s.list.rows[1], "OnClick")
		eq(got, "a"); falsy(s:IsOpen())
	end)

	it("a click outside (the catcher) closes it, and it does not use UIDropDownMenu", function()
		local s = make()
		s:Open()
		Mock.RunScript(s.catcher, "OnClick")
		falsy(s:IsOpen())
		falsy(s.popup._template)
		isNil(rawget(_G, "UIDropDownMenu_Initialize"))
		eq(s.popup:GetFrameStrata(), "DIALOG")
	end)

	it("hiding the field closes the list", function()
		local s = make()
		s:Open()
		s:Hide()
		falsy(s:IsOpen())
	end)

	it("the arrow turns while it opens, and a value given at the start is shown without a callback", function()
		local called = false
		local s = Widgets().Select(CreateFrame("Frame"), { value = "a", onSelect = function() called = true end,
			choices = { { id = "a", text = "Alpha" } } })
		eq(s.label:GetText(), "Alpha"); falsy(called)
		s:Open()
		eq(first(groupOf(s.arrow))._kind, "Rotation")
		truthy(s.focusRing:IsShown()); shows(s.focusRing, "accent"); falsy(s.ring:IsShown())
		s:Close()
		falsy(s.focusRing:IsShown()); truthy(s.ring:IsShown()); shows(s.ring, "border")
	end)

	it("a new list that lacks the value takes it back to the placeholder; an empty list does not open", function()
		local s = make()
		s:Select("a", true)
		s:SetChoices({ { id = "z", text = "Zed" } })
		isNil(s:Selected()); eq(s.label:GetText(), "Pick")
		s:SetChoices({})
		s:Open()
		falsy(s:IsOpen())
	end)

	it("a disabled field does not open", function()
		local s = make()
		s:SetEnabled(false)
		s:Open()
		falsy(s:IsOpen())
	end)
end)

describe("snackbar", function()
	it("is inverse-surface with radius 4 and inverse-on-surface text (ui-style §9.6)", function()
		local sb = Widgets().Snackbar(CreateFrame("Frame"))
		eq(sb:GetWidth(), 380); eq(sb:GetHeight(), 48)
		eq(sb.parts.fill._asset, "rr_fill_4"); shows(sb.parts.fill, "inverse-surface")
		falsy(sb.parts.ring)
		inks(sb.text, "inverse-on-surface")
	end)

	it("shows the text, fades in and goes away after 4 s", function()
		local sb = Widgets().Snackbar(CreateFrame("Frame"))
		falsy(sb:IsShown())
		sb:Say("Saved", "ok")
		truthy(sb:IsShown()); eq(sb:Message(), "Saved")
		Mock.FinishAnimations()
		Mock.Advance(4.1)
		Mock.FinishAnimations()
		falsy(sb:IsShown())
	end)

	it("a newer message is not cut short by the timer of the older one", function()
		local sb = Widgets().Snackbar(CreateFrame("Frame"))
		sb:Say("One", "ok", 4)
		Mock.Advance(3)
		sb:Say("Two", "err", 4)
		Mock.Advance(2)
		Mock.FinishAnimations()
		truthy(sb:IsShown()); eq(sb:Message(), "Two")
	end)

	it("Dismiss takes it away at once, with Animations off too", function()
		C():Set("account.settings.animations", false)
		local sb = Widgets().Snackbar(CreateFrame("Frame"))
		sb:Say("x", "warn")
		eq(sb:GetAlpha(), 1)
		sb:Dismiss()
		falsy(sb:IsShown())
	end)
end)

describe("skeleton, class mark and thin bar", function()
	it("a skeleton pulses while shown and stops when hidden", function()
		local sk = Widgets().Skeleton(CreateFrame("Frame"), 100, 12)
		Mock.RunScript(sk, "OnShow")
		truthy(groupOf(sk):IsPlaying())
		Mock.RunScript(sk, "OnHide")
		falsy(groupOf(sk):IsPlaying())
	end)

	it("a skeleton rests at the middle with Animations off", function()
		C():Set("account.settings.animations", false)
		local sk = Widgets().Skeleton(CreateFrame("Frame"), 100, 12)
		Mock.RunScript(sk, "OnShow")
		falsy(groupOf(sk):IsPlaying())
		near(sk:GetAlpha(), 0.675, 1e-9)
	end)

	it("the class mark is hidden until painted, then the colour of the class with a glow of the same colour", function()
		local f = CreateFrame("Frame")
		local m = Widgets().ClassMark(f)
		falsy(m:IsShown()); falsy(m.glow:IsShown())
		Widgets().PaintClassMark(m, 0.25, 0.78, 0.92)
		truthy(m:IsShown()); truthy(m.glow:IsShown())
		near(r1(m), 0.25, 1e-6)
		near((m.glow:GetVertexColor()), 0.25, 1e-6)
		truthy(m.glow._glow)
		eq(m:GetWidth(), 10)
		Widgets().ClearClassMark(m)
		falsy(m:IsShown()); falsy(m.glow:IsShown())
	end)

	it("the class colour is the game's, not the theme's: it survives a change of theme and the effects switch", function()
		local m = Widgets().ClassMark(CreateFrame("Frame"), 12)
		Widgets().PaintClassMark(m, 0.77, 0.12, 0.23)
		for _, id in ipairs(Th().List()) do
			Th().Apply(id)
			near(r1(m), 0.77, 1e-6, id)
		end
		C():Set("account.settings.effects", false)
		falsy(m.glow:IsShown())
		C():Set("account.settings.effects", true)
		truthy(m.glow:IsShown())
	end)

	it("a thin bar fills a fraction of its width, clamped, and hides its fill at zero", function()
		local bar = Widgets().ThinBar(CreateFrame("Frame"), { width = 200 })
		eq(bar:GetHeight(), 4)
		shows(bar.track, "surface-3"); shows(bar.fill, "accent")
		falsy(bar.fill:IsShown())
		bar:SetFraction(0.25); eq(bar.fill:GetWidth(), 50); truthy(bar.fill:IsShown())
		bar:SetFraction(7); eq(bar:GetFraction(), 1); eq(bar.fill:GetWidth(), 200)
		bar:SetFraction(-1); eq(bar:GetFraction(), 0); falsy(bar.fill:IsShown())
		bar:SetFraction("x"); eq(bar:GetFraction(), 0)
		bar:SetWidth(100); bar:SetFraction(0.5)
		Mock.RunScript(bar, "OnSizeChanged")
		eq(bar.fill:GetWidth(), 50)
	end)
end)

describe("tooltip", function()
	it("rich: surface-3, radius 12, padding 16, 8 under the title (in accent-text), the lines in text-1", function()
		local owner = CreateFrame("Frame")
		local tip = Widgets().Tooltip
		falsy(tip.IsShown())
		local f = tip.Show(owner, { "Title", "One line", { text = "Warning", token = "err" } })
		truthy(f); truthy(tip.IsShown()); eq(tip.Owner(), owner)
		deepEq(tip.Lines(), { "Title", "One line", "Warning" })
		truthy(f.isRich)
		eq(f.parts.fill._asset, "rr_fill_12"); shows(f.parts.fill, "surface-3")
		truthy(f.parts.fill:IsShown()); falsy(f.plain.fill:IsShown()); truthy(f.parts.shadow:IsShown())
		inks(f.lines[1], "accent-text"); inks(f.lines[2], "text-1"); inks(f.lines[3], "err")
		eq(f.lines[1]:GetFontObject(), Th().Font("BodyMedium")); eq(f.lines[2]:GetFontObject(), Th().Font("Body"))
		local function at(i) local _, _, _, x, y = f.lines[i]:GetPoint(1) return x, y end
		local x1, y1 = at(1)
		local _, y2 = at(2)
		local _, y3 = at(3)
		eq(x1, 16); eq(y1, -16); eq(y2, -(16 + 12 + 8)); eq(y3, y2 - 12 - 4)
		eq(f:GetHeight(), 16 + 12 + 8 + 12 + 4 + 12 + 16)
		eq(f:GetWidth(), 8 * 6 + 32)
		eq(f:GetFrameStrata(), "TOOLTIP")
		falsy(f:IsMouseEnabled(), "the pointer goes through it")
		Th().Apply("aurora")
		near(r1(f.parts.fill), token1("surface-3", "aurora"), 1e-6)
		near((f.lines[1]:GetTextColor()), token1("accent-text", "aurora"), 1e-6)
		tip.Hide()
		falsy(tip.IsShown()); isNil(tip.Owner())
	end)

	it("plain: one short line on inverse-surface, radius 4, body small, padding 8, at least 24 high", function()
		local tip = Widgets().Tooltip
		local owner = CreateFrame("Frame")
		local f = tip.Show(owner, "Shorter text")
		falsy(f.isRich)
		eq(f.parts.fill._asset, "rr_fill_4"); shows(f.parts.fill, "inverse-surface")
		falsy(f.rich.fill:IsShown()); falsy(f.rich.shadow:IsShown())
		inks(f.lines[1], "inverse-on-surface")
		eq(f.lines[1]:GetFontObject(), Th().Font("body-small"))
		eq(f:GetWidth(), #"Shorter text" * 6 + 16); eq(f:GetHeight(), 12 + 16)
		local _, _, _, x, y = f.lines[1]:GetPoint(1)
		eq(x, 8); eq(y, -8)
		truthy(f:GetHeight() >= 24)
		tip.Show(owner, { text = "Careful", token = "warn" })
		truthy(f.isRich, "a line with its own colour needs the rich box"); inks(f.lines[1], "warn")
		tip.Show(owner, string.rep("x", 200))
		truthy(f.isRich, "a long explanation too"); inks(f.lines[1], "text-1")
	end)

	it("grows to its longest line up to a maximum and anchors where asked", function()
		local owner = CreateFrame("Frame")
		local tip = Widgets().Tooltip
		local f = tip.Show(owner, { "Title", string.rep("x", 200) })
		eq(f:GetWidth(), tip.MAX_WIDTH + 32)
		local point, rel, relPoint = f:GetPoint(1)
		eq(point, "TOP"); eq(rel, owner); eq(relPoint, "BOTTOM")
		f = tip.Show(owner, "x", "RIGHT")
		point, _, relPoint = f:GetPoint(1)
		eq(point, "LEFT"); eq(relPoint, "RIGHT")
		f = tip.Show(owner, "x", "TOP")
		point, _, relPoint = f:GetPoint(1)
		eq(point, "BOTTOM"); eq(relPoint, "TOP")
		f = tip.Show(owner, "x", "LEFT")
		point, _, relPoint = f:GetPoint(1)
		eq(point, "RIGHT"); eq(relPoint, "LEFT")
	end)

	it("the same frame serves every tooltip: a shorter one hides the extra lines", function()
		local owner = CreateFrame("Frame")
		local tip = Widgets().Tooltip
		local f = tip.Show(owner, { "a", "b", "c" })
		local g = tip.Show(owner, { "d" })
		eq(f, g)
		deepEq(tip.Lines(), { "d" })
		eq(_G.AzerothAccordTooltip, f)
	end)

	it("Attach shows it on hover from a string, a list or a function, and hides it on leave and on hide", function()
		local owner = CreateFrame("Button")
		local tip = Widgets().Tooltip
		local nothing = false
		tip.Attach(owner, function(self) if nothing then return nil end return { "Live", tostring(self == owner) } end)
		Mock.RunScript(owner, "OnEnter")
		deepEq(tip.Lines(), { "Live", "true" })
		Mock.RunScript(owner, "OnLeave")
		falsy(tip.IsShown())
		Mock.RunScript(owner, "OnEnter")
		owner:Hide()
		falsy(tip.IsShown())
		owner:Show()
		nothing = true
		Mock.RunScript(owner, "OnEnter")
		falsy(tip.IsShown())
		local plain = CreateFrame("Button")
		tip.Attach(plain, "Plain text")
		Mock.RunScript(plain, "OnEnter")
		deepEq(tip.Lines(), { "Plain text" })
	end)

	it("nothing to show hides it, and a frame's own scripts survive Attach", function()
		local tip = Widgets().Tooltip
		local owner = CreateFrame("Button")
		local own = 0
		owner:SetScript("OnEnter", function() own = own + 1 end)
		tip.Attach(owner, "Text")
		Mock.RunScript(owner, "OnEnter")
		eq(own, 1); truthy(tip.IsShown())
		tip.Show(owner, nil)
		falsy(tip.IsShown())
		tip.Show(owner, {})
		falsy(tip.IsShown())
	end)

	it("the game's GameTooltip is for items only, and only through Item", function()
		local tip = Widgets().Tooltip
		local owner = CreateFrame("Button")
		truthy(tip.Item(owner, "item:19019"))
		truthy(GameTooltip:IsShown())
		eq(GameTooltip:GetOwner(), owner)
		tip.HideItem()
		falsy(GameTooltip:IsShown())
		falsy(tip.Item(owner, nil))
		local linkOwner = CreateFrame("Button")
		tip.AttachItem(linkOwner, function() return "item:2589" end, "ANCHOR_TOP")
		Mock.RunScript(linkOwner, "OnEnter")
		truthy(GameTooltip:IsShown())
		Mock.RunScript(linkOwner, "OnLeave")
		falsy(GameTooltip:IsShown())
		falsy(tip.IsShown(), "the addon's own tooltip was never used for the item")
	end)
end)

describe("data table", function()
	local function people(n)
		local list = {}
		for i = 1, n do
			list[i] = { name = ("Member%04d"):format((i * 7919) % 10007), level = (i * 37) % 60 + 1, class = (i % 3 == 0) and "Mage" or "Druid" }
		end
		return list
	end
	local function columns(calls)
		return {
			{ id = "name", title = "Name", flex = 2, text = function(d) return d.name end },
			{ id = "level", title = "Level", width = 60, align = "RIGHT", mono = true, text = function(d) return d.level end,
				value = function(d) if calls then calls.value = calls.value + 1 end return d.level end },
			{ id = "class", title = "Class", flex = 1, text = function(d) if calls then calls.text = calls.text + 1 end return d.class end },
		}
	end
	local function table_(n, opts, calls)
		local host = CreateFrame("Frame")
		host:SetSize(600, 500)
		local t = Widgets().DataTable(host, columns(calls), opts or { emptyText = "Nobody" })
		t:SetSize(600, 500)
		t:SetData(people(n or 100))
		return t
	end

	it("fixed columns wider than the table shrink to fit, and the table clips its children (found in game, 2026-11-26)", function()
		local cols = { { id = "name", title = "Name", flex = 1, text = function(d) return d.name end } }
		for i = 1, 10 do cols[#cols + 1] = { id = "c" .. i, title = "C" .. i, width = 120, text = function() return "x" end } end
		local host = CreateFrame("Frame")
		host:SetSize(1000, 400)
		local t = Widgets().DataTable(host, cols, {})
		t:SetSize(1000, 400)
		t:SetData(people(5))
		t:Layout()
		truthy(t:DoesClipChildren())
		truthy(t.shrink < 1)
		local last = t.pos[#t.pos]
		truthy(last.x + last.w <= 1000, "the last column ends inside the table")
		truthy(t.pos[1].w >= 60, "the flexible column keeps its minimum")
		-- a wide table keeps the widths it asked for
		t:SetSize(2000, 400)
		t:Layout()
		eq(t.shrink, 1)
		eq(t.pos[2].w, 120)
	end)

	it("has a header of 32 on surface-2 (radius 8, label medium in text-3) and rows of 32 (ui-style §9.6)", function()
		local t = table_(10)
		eq(t.head:GetHeight(), 32); eq(t.rows[1]:GetHeight(), 32)
		eq(t.head.fill._asset, "rr_fill_8"); shows(t.head.fill, "surface-2")
		eq(t.heads[1].label:GetFontObject(), Th().Font("label-medium"))
		inks(t.heads[1].label, "text-3")
		shows(t.rows[1].line, "border-subtle")
		falsy(t.rows[1].selection:IsShown())
	end)

	it("the selected row is secondary-container with radius 4, its cells on-secondary-container", function()
		local wanted = "y"
		local t = Widgets().DataTable(CreateFrame("Frame"), {
			{ id = "a", title = "A", text = function(d) return d.a end },
			{ id = "b", title = "B", render = function(cell, d) cell:SetText(d.a); Th().Text(cell, "warn") end },
		}, { isSelected = function(d) return d.a == wanted end })
		t:SetSize(600, 500)
		local data = { { a = "x" }, { a = "y" } }
		t:SetData(data)
		local one, two = t.rows[1], t.rows[2]
		falsy(one.selection:IsShown()); truthy(two.selection:IsShown())
		eq(two.selection._asset, "rr_fill_4"); shows(two.selection, "secondary-container")
		inks(two.cells[1], "on-secondary-container"); inks(one.cells[1], "text-1")
		inks(two.cells[2], "warn", "a cell the caller draws keeps its colour")
		Mock.RunScript(two, "OnEnter")
		shows(two.hover, "on-secondary-container")
		t:SetSelected(data[1])
		truthy(one.selection:IsShown()); falsy(two.selection:IsShown()); shows(two.hover, "text-1")
		truthy(t:IsSelected(data[1])); falsy(t:IsSelected(data[2]))
		t:SetSelected(nil)
		falsy(one.selection:IsShown()); inks(one.cells[1], "text-1")
	end)

	it("fills the visible rows only, from a pool, with the header outside the list", function()
		local t = table_(100)
		eq(#t.rows, 40)
		eq(t:Capacity(), 14)
		eq(#t:VisibleRows(), 14)
		eq(t:VisibleRows()[1].cells[1]:GetText(), t.sorted[1].name)
		eq(t.head:GetParent(), t); eq(t.list:GetParent(), t)
		eq(t.heads[1].label:GetText(), "NAME")
		falsy(t.empty:IsShown())
	end)

	it("sorts by a column, toggles the direction, keeps the order of equals and marks the column", function()
		local t = table_(100)
		truthy(t:SortBy("level"))
		local id, desc = t:GetSort()
		eq(id, "level"); eq(desc, false)
		local rows = t:GetData()
		for i = 2, #rows do truthy(rows[i - 1].level <= rows[i].level, "ascending at " .. i) end
		t:SortBy("level")
		eq(select(2, t:GetSort()), true)
		rows = t:GetData()
		for i = 2, #rows do truthy(rows[i - 1].level >= rows[i].level, "descending at " .. i) end
		t:SortBy("name", false)
		rows = t:GetData()
		for i = 2, #rows do truthy(rows[i - 1].name:lower() <= rows[i].name:lower(), "by name at " .. i) end
		near((t.heads[1].label:GetTextColor()), token1("accent-text"), 1e-6)
		near((t.heads[2].label:GetTextColor()), token1("text-3"), 1e-6)
		truthy(t.heads[1].arrow:IsShown()); falsy(t.heads[2].arrow:IsShown())
		falsy(t:SortBy("nope"))
		eq(t:VisibleRows()[1].cells[1]:GetText(), rows[1].name)
	end)

	it("equal keys keep their original order (a stable sort) and numbers sort before text", function()
		local host = CreateFrame("Frame")
		local t = Widgets().DataTable(host, { { id = "k", title = "K", text = function(d) return d.k end } }, {})
		t:SetData({ { k = "b", n = 1 }, { k = "a", n = 2 }, { k = "b", n = 3 }, { k = "a", n = 4 }, { k = "10", n = 5 }, { k = "9", n = 6 } })
		t:SortBy("k", false)
		local order = {}
		for _, d in ipairs(t:GetData()) do order[#order + 1] = d.n end
		deepEq(order, { 6, 5, 2, 4, 1, 3 })
		t:SortBy("k", true)
		order = {}
		for _, d in ipairs(t:GetData()) do order[#order + 1] = d.n end
		deepEq(order, { 1, 3, 2, 4, 5, 6 }, "descending reverses the keys, not the order of equals")
	end)

	it("scrolls with the wheel and with SetOffset, and clamps at both ends", function()
		local t = table_(100)
		t:SortBy("name", false)
		local data = t:GetData()
		Mock.RunScript(t.list, "OnMouseWheel", -1)
		eq(t.offset, 3)
		eq(t:VisibleRows()[1].cells[1]:GetText(), data[4].name)
		Mock.RunScript(t.list, "OnMouseWheel", 1)
		eq(t.offset, 0)
		t:SetOffset(-50); eq(t.offset, 0)
		t:SetOffset(500); eq(t.offset, 100 - t:Capacity())
		eq(t:VisibleRows()[#t:VisibleRows()].cells[1]:GetText(), data[100].name)
		truthy(t.scroll:IsShown())
		local short = table_(5)
		falsy(short.scroll:IsShown())
		eq(#short:VisibleRows(), 5)
	end)

	it("a thousand members: a sort or a scroll fills a pool of rows and creates no region", function()
		local calls = { value = 0, text = 0 }
		local t = table_(1000, { emptyText = "Nobody" }, calls)
		local regions = count(t)
		calls.value, calls.text = 0, 0
		t:SortBy("level")
		eq(calls.value, 1000, "each key is computed once per sort")
		truthy(calls.text <= 40, "cells are filled for the rows that show only")
		eq(count(t), regions); eq(#t.rows, 40)
		t:SortBy("level")
		t:SetOffset(600)
		t:SetData(people(1000))
		t:SortBy("name")
		eq(count(t), regions, "no region made while the data changed")
		eq(#t:GetData(), 1000)
		eq(#t:VisibleRows(), 14)
	end)

	it("the pool grows when the window gets taller, never while it is filled", function()
		local t = table_(200)
		eq(#t.rows, 40)
		t.list:SetHeight(50 * 32)
		Mock.RunScript(t, "OnSizeChanged")
		eq(#t.rows, 50)
		eq(t:Capacity(), 50)
		eq(#t:VisibleRows(), 50)
		t.list:SetHeight(500 * 32)
		Mock.RunScript(t, "OnSizeChanged")
		eq(#t.rows, 100, "capped by maxPool")
	end)

	it("shows the empty text the caller gave when there is nothing, and hides it with data", function()
		local t = table_(0)
		truthy(t.empty:IsShown()); eq(t.empty:GetText(), "Nobody")
		eq(#t:VisibleRows(), 0)
		t:SetEmptyText("Nothing here")
		eq(t.empty:GetText(), "Nothing here")
		t:SetData(people(3))
		falsy(t.empty:IsShown())
		eq(#t:VisibleRows(), 3)
		t:SetData(nil)
		truthy(t.empty:IsShown())
		local bare = Widgets().DataTable(CreateFrame("Frame"), columns(), {})
		eq(bare.empty:GetText(), "", "no text of its own")
	end)

	it("clicks, custom cells, row hooks, the colour of a cell and the fixed and flexible widths", function()
		local clicked, setups, updates = nil, 0, 0
		local host = CreateFrame("Frame")
		local t = Widgets().DataTable(host, {
			{ id = "a", title = "A", width = 100, text = function(d) return d.a end, token = function(d) return d.hot and "err" or nil end },
			{ id = "b", title = "B", flex = 1, render = function(cell, d) cell:SetText("<" .. d.a .. ">") end },
			{ id = "c", title = "C", flex = 3, text = function() return "c" end },
		}, { pool = 4, rowSetup = function() setups = setups + 1 end, rowUpdate = function() updates = updates + 1 end,
			onRowClick = function(d, row) clicked = { d, row } end })
		t:SetSize(916, 300)
		Mock.RunScript(t, "OnSizeChanged")
		t:SetData({ { a = "x" }, { a = "y", hot = true } })
		eq(setups, 4); eq(updates, 2)
		local rows = t:VisibleRows()
		eq(rows[2].cells[2]:GetText(), "<y>")
		near((rows[1].cells[1]:GetTextColor()), token1("text-1"), 1e-6)
		near((rows[2].cells[1]:GetTextColor()), token1("err"), 1e-6)
		Mock.RunScript(rows[2], "OnClick")
		eq(clicked[1].a, "y"); eq(clicked[2], rows[2])
		-- 916 wide: 16 of margins, 100 fixed, 800 for the flexible ones shared 1:3
		eq(t.pos[1].w, 100); eq(t.pos[2].w, 200); eq(t.pos[3].w, 600)
		eq(t.pos[2].x, 108); eq(t.pos[3].x, 308)
		Mock.RunScript(rows[1], "OnEnter")   -- a state layer of text-1 at 8 % (M12.6)
		near(rows[1].hover._texture[1], token1("text-1"), 1e-6)
		near(rows[1].hover:GetAlpha(), 0.08, 1e-6)
		Mock.RunScript(rows[1], "OnLeave")
		near(rows[1].hover:GetAlpha(), 0, 1e-6)
	end)

	it("a click on a header sorts, a column that says sortable = false does not", function()
		local t = Widgets().DataTable(CreateFrame("Frame"), {
			{ id = "a", title = "A", text = function(d) return d.a end },
			{ id = "b", title = "B", sortable = false, text = function(d) return d.a end },
		}, {})
		t:SetData({ { a = "2" }, { a = "1" } })
		Mock.RunScript(t.heads[1], "OnClick")
		eq(t:GetData()[1].a, "1")
		falsy(t.heads[2]:GetScript("OnClick"))
	end)

	it("follows a change of theme: rows, header and lines are repainted", function()
		local t = table_(30)
		t:SortBy("name")
		local a = snapshot(t)
		Th().Apply("aurora")
		ne(snapshot(t), a)
		near((t.heads[1].label:GetTextColor()), token1("accent-text", "aurora"), 1e-6)
		near(t.rows[1].line._texture[1], token1("border-subtle", "aurora"), 1e-6)
		Th().Apply("nebula")
		eq(snapshot(t), a)
	end)
end)

describe("menu", function()
	local function open(items, width)
		return Widgets().Menu.Show(CreateFrame("Frame"), items, width)
	end

	it("is surface-2 with radius 4 and a shadow, 112 to 280 wide, rows of 32 with 12 points each side (ui-style §9.6)", function()
		local m = open({ { text = "A", checked = true }, { text = "B" }, { text = "C" } })
		eq(m.parts.fill._asset, "rr_fill_4"); shows(m.parts.fill, "surface-2")
		truthy(m.parts.shadow); falsy(m.parts.ring)
		eq(m:GetWidth(), 220); eq(m:GetHeight(), 3 * 32 + 16)
		eq(m.rows[1]:GetHeight(), 32)
		local _, _, _, x = m.rows[1].check:GetPoint(1)
		eq(x, 12); eq(m.rows[1].check:GetWidth(), 18)
		eq(open({ { text = "A" } }, 60):GetWidth(), 112)
		eq(open({ { text = "A" } }, 900):GetWidth(), 280)
		Mock.RunScript(m.rows[1], "OnEnter")
		near(m.rows[1].hover:GetAlpha(), 0.08, 1e-9); shows(m.rows[1].hover, "text-1")
	end)

	it("lists the items under the anchor, with a check on the checked ones and a heading that is not a choice", function()
		local clicked = {}
		local m = open({
			{ text = "Columns", header = true },
			{ text = "Zone", checked = true, onClick = function() clicked[#clicked + 1] = "zone" end },
			{ text = "Rank", onClick = function() clicked[#clicked + 1] = "rank" end },
		})
		truthy(Widgets().Menu.IsOpen())
		eq(m, Widgets().Menu.frame)
		eq(m.rows[1].label:GetText(), "Columns")
		falsy(m.rows[1].check:IsShown(), "a heading has no check")
		truthy(m.rows[2].check:IsShown()); falsy(m.rows[3].check:IsShown())
		m.rows[1]:Click()
		eq(#clicked, 0)
		truthy(Widgets().Menu.IsOpen(), "a click on a heading changes nothing")
		m.rows[3]:Click()
		deepEq(clicked, { "rank" })
		falsy(Widgets().Menu.IsOpen(), "choosing closes it")
	end)

	it("keepOpen flips the check and keeps the menu open, a click outside or Esc closes it", function()
		local n = 0
		local m = open({ { text = "Zone", checked = false, keepOpen = true, onClick = function() n = n + 1 end } })
		m.rows[1]:Click()
		truthy(m.rows[1].check:IsShown()); truthy(Widgets().Menu.IsOpen()); eq(n, 1)
		m.rows[1]:Click()
		falsy(m.rows[1].check:IsShown()); eq(n, 2)
		Mock.RunScript(m.catcher, "OnClick")
		falsy(Widgets().Menu.IsOpen())
		falsy(m.catcher:IsShown())
		open({ { text = "A" } })
		truthy(Widgets().Menu.IsOpen())
		local registered = false
		for _, name in ipairs(UISpecialFrames) do if name == "AzerothAccordKitMenu" then registered = true end end
		truthy(registered, "Esc closes it")
	end)

	it("one menu serves every call: another list replaces the rows and the extra rows hide", function()
		local m = open({ { text = "A" }, { text = "B" }, { text = "C" } })
		local again = open({ { text = "Only" } })
		eq(m, again)
		eq(again.rows[1].label:GetText(), "Only")
		falsy(again.rows[2]:IsShown()); falsy(again.rows[3]:IsShown())
		truthy(again:GetHeight() < m.rows[1]:GetHeight() * 3)
	end)

	it("follows a change of theme", function()
		local m = open({ { text = "A", checked = true }, { text = "B" } })
		local before = snapshot(m)
		Th().Apply("aurora")
		ne(snapshot(m), before)
		Th().Apply("nebula")
		eq(snapshot(m), before)
	end)
end)

describe("data table for a caller that sorts and changes columns (M6.13)", function()
	local function make(sorted)
		local host = CreateFrame("Frame")
		host:SetSize(600, 500)
		local clicks = {}
		local t = Widgets().DataTable(host, {
			{ id = "name", title = "Name", flex = 1, text = function(d) return d.name end },
			{ id = "level", title = "Level", width = 60, text = function(d) return d.level end },
			{ id = "note", title = "Note", width = 60, sortable = false, text = function() return "" end },
		}, { onSort = function(id) clicks[#clicks + 1] = id end, pool = 10 })
		t:SetSize(600, 500)
		return t, clicks
	end
	local function data(n)
		local list = {}
		for i = 1, n do list[i] = { name = "Z" .. (100 - i), level = i } end   -- already in the order the caller wants
		return list
	end

	it("a click on a header calls the caller and does not sort; SetData keeps the given order", function()
		local t, clicks = make()
		t:SetData(data(30))
		Mock.RunScript(t.heads[2], "OnClick")
		deepEq(clicks, { "level" })
		eq(t:GetData()[1].level, 1)
		eq(t:GetData()[30].level, 30)
		falsy(t.heads[3]:GetScript("OnClick"), "a column that is not sortable has no click")
	end)

	it("SetSortMark paints the arrow and the title of the sorted column, and clears it for an unknown one", function()
		local t = make()
		truthy(t:SetSortMark("level", true))
		local id, desc = t:GetSort()
		eq(id, "level"); truthy(desc)
		truthy(t.heads[2].arrow:IsShown()); falsy(t.heads[1].arrow:IsShown())
		near((t.heads[2].label:GetTextColor()), token1("accent-text"), 1e-6)
		near((t.heads[1].label:GetTextColor()), token1("text-3"), 1e-6)
		falsy(t:SetSortMark("nope"))
		falsy(t.heads[2].arrow:IsShown())
		isNil(t:GetSort())
	end)

	it("SetData keeps the place in the list when the caller sorts, or when asked", function()
		local t = make()
		t:SetData(data(100))
		t:SetOffset(20)
		t:SetData(data(100))
		eq(t.offset, 20)
		t:SetData(data(10))
		eq(t.offset, 0, "clamped when the list got short")
		local plain = Widgets().DataTable(CreateFrame("Frame"), { { id = "a", title = "A", text = function(d) return d.level end } }, {})
		plain:SetSize(600, 500)
		plain:SetData(data(100))
		plain:SetOffset(20)
		plain:SetData(data(100))
		eq(plain.offset, 0, "a table that sorts starts at the top")
		plain:SetOffset(20)
		plain:SetData(data(100), true)
		eq(plain.offset, 20, "unless the caller asks to keep the place")
	end)

	it("SetColumns gives the table another set of columns, reusing the header buttons and the cells", function()
		local t = make()
		t:SetData(data(5))
		local head1, cell1 = t.heads[1], t.rows[1].cells[1]
		t:SetColumns({
			{ id = "level", title = "Lvl", width = 80, mono = true, text = function(d) return d.level end },
		})
		t:Refresh()
		eq(t.heads[1], head1); eq(t.rows[1].cells[1], cell1)
		eq(head1.label:GetText(), "LVL")
		falsy(t.heads[2]:IsShown()); falsy(t.heads[3]:IsShown())
		eq(t.rows[1].cells[1]:GetText(), "1")
		falsy(t.rows[1].cells[2]:IsShown()); falsy(t.rows[1].cells[3]:IsShown())
		eq(t.rows[1].cells[1]:GetFontObject(), Th().Font("Mono"))
		t:SetColumns({
			{ id = "name", title = "Name", flex = 1, text = function(d) return d.name end },
			{ id = "level", title = "Level", width = 60, text = function(d) return d.level end },
			{ id = "x", title = "X", width = 60, text = function() return "x" end },
		})
		t:Refresh()
		truthy(t.heads[3]:IsShown()); truthy(t.rows[1].cells[3]:IsShown())
		eq(t.rows[1].cells[3]:GetText(), "x")
		eq(t.rows[1].cells[1]:GetFontObject(), Th().Font("Body"))
	end)

	it("keeps the sort mark through SetColumns when the column is still there", function()
		local t = make()
		t:SetSortMark("level", false)
		t:SetColumns({ { id = "level", title = "L", width = 60, text = function(d) return d.level end },
			{ id = "name", title = "N", flex = 1, text = function(d) return d.name end } })
		truthy(t.heads[1].arrow:IsShown())
		t:SetColumns({ { id = "name", title = "N", flex = 1, text = function(d) return d.name end } })
		falsy(t.heads[1].arrow:IsShown())
		isNil(t:GetSort())
	end)
end)

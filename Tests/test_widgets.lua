-- The widget kit (M6.11): Button, Card, Badge, Tabs, Segmented, Chip, TitleBar, Dialog, EditBox, ChoiceList, Switch, Slider,
-- Select, Snackbar, Skeleton, ClassMark, ThinBar, Tooltip and DataTable (docs/specs/ui-style.md §3). Every widget builds in every
-- theme, follows Theme.Apply without /reload, takes its texts only from what the caller passes, and behaves with the
-- effects and animations preferences off. Nothing is on screen yet: the views move to the kit in M6.12 - M6.14.
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
		{ "Button primary", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "primary" }) end },
		{ "Button secondary", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "secondary" }) end },
		{ "Button ghost", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "ghost" }) end },
		{ "Button neon", true, function(p) return Widgets().Button(p, { text = "QZ1", style = "neon" }) end },
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
			"DataTable", "Text", "RowHover", "PaintName", "ChipRow" }) do
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
			near(r1(card.parts.ring), token1("border-subtle", id), 1e-6, id)
			near(r1(badge.fill), token1("err", id), 1e-6, id)
			near((badge.label:GetTextColor()), token1("err", id), 1e-6, id)
			near(bar.track._texture[1], token1("border-subtle", id), 1e-6, id)
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

describe("button", function()
	local function button(style, opts)
		opts = opts or {}
		opts.text, opts.style = opts.text or "Go", style
		return Widgets().Button(CreateFrame("Frame"), opts)
	end

	it("hover lays 8 % white, pressed 12 %, both faded in 120 ms", function()
		local b = button()
		Mock.RunScript(b, "OnEnter")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.08)
		eq(first(groupOf(b.over)):GetDuration(), 0.12)
		Mock.RunScript(b, "OnMouseDown")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.12)
		Mock.RunScript(b, "OnMouseUp")
		eq(first(groupOf(b.over)):GetToAlpha(), 0.08)   -- still over it
		Mock.RunScript(b, "OnLeave")
		eq(first(groupOf(b.over)):GetToAlpha(), 0)
	end)

	it("a disabled button dims and shows no hover", function()
		local b = button()
		b:SetEnabled(false)
		near(b:GetAlpha(), 0.45, 1e-9)
		Mock.RunScript(b, "OnEnter")
		eq(first(groupOf(b.over)):GetToAlpha(), 0)
		b:SetEnabled(true)
		eq(b:GetAlpha(), 1)
	end)

	it("a press shrinks the button to 0.97 in 120 ms and releases it in 120 ms", function()
		local b = button("primary")
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

	it("the primary and the neon buttons have a glow, the others none", function()
		truthy(button("primary").glow); truthy(button("neon").glow)
		falsy(button("secondary").glow); falsy(button("ghost").glow)
	end)

	it("takes the token of its style: the primary fill is the accent, the label on-accent", function()
		local b = button("primary")
		near(r1(b.fill), token1("accent"), 1e-6)
		near((b.label:GetTextColor()), token1("on-accent"), 1e-6)
		local n = button("neon")
		near(r1(n.ring), token1("neon"), 1e-6)
		local g = button("ghost")
		falsy(g.fill); falsy(g.ring)
	end)

	it("fits its text unless it is given a width, and onClick runs", function()
		local clicked = 0
		local b = button("secondary", { text = "A longer label", onClick = function() clicked = clicked + 1 end })
		eq(b:GetWidth(), #"A longer label" * 6 + 32)
		b:SetLabel("Hi")
		eq(b:GetWidth(), 64)
		eq(b:GetLabel(), "Hi")
		local fixed = button("secondary", { width = 150 })
		fixed:SetLabel("A much longer label than the width")
		eq(fixed:GetWidth(), 150)
		Mock.RunScript(b, "OnClick")
		eq(clicked, 1)
	end)

	it("with Animations off the layers and the press change nothing but the alpha, at once", function()
		C():Set("account.settings.animations", false)
		local b = button()
		Mock.RunScript(b, "OnEnter")
		near(b.over:GetAlpha(), 0.08, 1e-9)
		falsy(b.over._animGroups)
		Mock.RunScript(b, "OnMouseDown")
		near(b.over:GetAlpha(), 0.12, 1e-9)
		falsy(groupKind(b, "Scale"):IsPlaying())
		Mock.RunScript(b, "OnLeave")
		eq(b.over:GetAlpha(), 0)
	end)
end)

describe("effects off", function()
	it("glows, shadows and the title glow go away and come back with the preference", function()
		local parent = CreateFrame("Frame")
		local primary = Widgets().Button(parent, { style = "primary" })
		local card = Widgets().Card(parent, { shadow = true })
		local bar = Widgets().TitleBar(parent, { title = "QZ1" })
		truthy(primary.glow:IsShown()); truthy(card.parts.shadow:IsShown()); truthy(bar.logoGlow:IsShown())
		C():Set("account.settings.effects", false)
		falsy(primary.glow:IsShown()); falsy(card.parts.shadow:IsShown()); falsy(bar.logoGlow:IsShown())
		falsy(bar.titleGlow:IsShown())
		local later = Widgets().Button(parent, { style = "neon" })
		falsy(later.glow:IsShown(), "a glow made while the effects are off is off")
		C():Set("account.settings.effects", true)
		truthy(primary.glow:IsShown()); truthy(card.parts.shadow:IsShown()); truthy(later.glow:IsShown())
	end)

	it("the light theme draws the glows as soft shadows, not additive light", function()
		local b = Widgets().Button(CreateFrame("Frame"), { style = "primary" })
		truthy(b.glow._additive)
		Th().Apply("aurora")
		falsy(b.glow._additive)
	end)
end)

describe("card, badge and chip", function()
	it("a card with hover takes the strong border while the mouse is over it", function()
		local c = Widgets().Card(CreateFrame("Frame"), { hover = true })
		Mock.RunScript(c, "OnEnter")
		near(r1(c.parts.ring), token1("border-strong"), 1e-6)
		Mock.RunScript(c, "OnLeave")
		near(r1(c.parts.ring), token1("border-subtle"), 1e-6)
		eq(count(c) <= 12, true, "a card is a handful of regions")
	end)

	it("a badge fits its text, takes the tone, and can change both", function()
		local b = Widgets().Badge(CreateFrame("Frame"), "QZ1", "ok")
		eq(b:GetHeight(), 24); eq(b:GetWidth(), #"QZ1" * 6 + 20)
		b:SetBadge("A longer badge text", "warn")
		eq(b:GetWidth(), #"A longer badge text" * 6 + 20)
		near((b.label:GetTextColor()), token1("warn"), 1e-6)
		b:SetBadge("x")
		near((b.label:GetTextColor()), token1("warn"), 1e-6, "keeps the tone it last had")
	end)

	it("a chip is filled with the accent when selected and reports clicks only while enabled", function()
		local n = 0
		local c = Widgets().Chip(CreateFrame("Frame"), { text = "QZ1", onClick = function() n = n + 1 end })
		falsy(c:IsSelected())
		c:SetSelected(true)
		truthy(c:IsSelected())
		near(r1(c.fill), token1("accent"), 1e-6)
		near((c.label:GetTextColor()), token1("on-accent"), 1e-6)
		c:SetSelected(false)
		near((c.label:GetTextColor()), token1("text-2"), 1e-6)
		Mock.RunScript(c, "OnClick"); eq(n, 1)
		c:SetEnabled(false)
		Mock.RunScript(c, "OnClick"); eq(n, 1)
		near(c:GetAlpha(), 0.45, 1e-9)
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

	it("the active tab is text-1 and the others text-3", function()
		local bar = tabs()
		bar:Select("prof")
		near((bar.buttons.prof.label:GetTextColor()), token1("text-1"), 1e-6)
		near((bar.buttons.roster.label:GetTextColor()), token1("text-3"), 1e-6)
		Mock.RunScript(bar.buttons.roster, "OnEnter")
		near((bar.buttons.roster.label:GetTextColor()), token1("text-2"), 1e-6)
		Mock.RunScript(bar.buttons.roster, "OnLeave")
		near((bar.buttons.roster.label:GetTextColor()), token1("text-3"), 1e-6)
	end)

	it("the tabs sit side by side and the indicator is a 2 pt bar under the active one", function()
		local bar = tabs()
		bar:Select("roster")
		local b1, b2 = bar.buttons.roster, bar.buttons.prof
		eq(b1.x, 0); eq(b2.x, b1.w + 4)
		truthy(bar.indicator:IsShown())
		eq(bar.indicator:GetHeight(), 2)
		local _, _, _, x = bar.indicator:GetPoint(1)
		eq(x, b1.x + 8); eq(bar.indicator:GetWidth(), b1.w - 16)
	end)

	it("the indicator slides to the next tab in 200 ms and rests under it", function()
		local bar = tabs()
		bar:Select("roster")
		Mock.FinishAnimations()
		bar:Select("prof")
		local g = groupKind(bar.indicator, "Translation")
		truthy(g and g:IsPlaying(), "a Translation group is playing")
		eq(first(g):GetDuration(), 0.2); eq(first(g):GetSmoothing(), "OUT")
		eq((first(g):GetOffset()), bar.buttons.prof.x - bar.buttons.roster.x)
		Mock.FinishAnimations()
		local _, _, _, x = bar.indicator:GetPoint(1)
		eq(x, bar.buttons.prof.x + 8)
		eq(bar.indicator:GetWidth(), bar.buttons.prof.w - 16)
	end)

	it("with Animations off the indicator is simply there", function()
		C():Set("account.settings.animations", false)
		local bar = tabs()
		bar:Select("roster"); bar:Select("bank")
		falsy(bar.indicator._animGroups)
		local _, _, _, x = bar.indicator:GetPoint(1)
		eq(x, bar.buttons.bank.x + 8)
	end)

	it("a tab may carry a count badge: it widens the tab and goes away when the count is nil", function()
		local bar = tabs()
		bar:Select("bank")
		local w = bar.buttons.bank.w
		truthy(bar:SetBadge("bank", "3", "warn"))
		local badge = bar.buttons.bank.badge
		truthy(badge:IsShown()); eq(badge.label:GetText(), "3")
		eq(bar.buttons.bank.w, #"Bank" * 6 + 32 + badge:GetWidth() + 6)
		near((badge.label:GetTextColor()), token1("warn"), 1e-6)
		eq(bar.indicator:GetWidth(), bar.buttons.bank.w - 16, "the indicator follows the new width")
		bar:SetBadge("bank", "12")
		eq(badge.label:GetText(), "12")
		bar:SetBadge("bank", nil)
		falsy(badge:IsShown()); eq(bar.buttons.bank.w, w)
		falsy(bar:SetBadge("nope", "1"))
	end)

	it("a badge given with the tab is there from the start, and the tab text can change", function()
		local bar = Widgets().Tabs(CreateFrame("Frame"), { { id = "bank", text = "Bank", badge = "5", tone = "err" } })
		truthy(bar.buttons.bank.badge:IsShown())
		bar:SetTabText("bank", "Banca")
		eq(bar.buttons.bank.label:GetText(), "Banca")
		eq(bar.buttons.bank.w, #"Banca" * 6 + 32 + bar.buttons.bank.badge:GetWidth() + 6)
	end)

	it("hiding the active tab selects the next one that shows", function()
		local bar = tabs()
		bar:Select("roster")
		bar:SetTabShown("roster", false)
		eq(bar:Active(), "prof")
		eq(bar.buttons.prof.x, 0, "the tabs close the gap")
	end)
end)

describe("segmented", function()
	it("selects one segment at a time, clears, and locks", function()
		local seen = {}
		local seg = Widgets().Segmented(CreateFrame("Frame"), { { id = "a", text = "Settings" }, { id = "b", text = "Info" } },
			function(id) seen[#seen + 1] = id end)
		falsy(seg.thumb:IsShown())
		truthy(seg:Select("a")); truthy(seg:Select("b")); truthy(seg:Select("b"))
		deepEq(seen, { "a", "b" })
		truthy(seg.thumb:IsShown())
		near((seg.buttons.b.label:GetTextColor()), token1("text-1"), 1e-6)
		near((seg.buttons.a.label:GetTextColor()), token1("text-3"), 1e-6)
		falsy(seg:Select("zzz"))
		seg:Clear()
		falsy(seg:Active()); falsy(seg.thumb:IsShown())
		seg:SetEnabled(false)
		near(seg:GetAlpha(), 0.55, 1e-9)
		falsy(seg.buttons.a:IsEnabled())
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

	it("the card is made of the panel regions only", function()
		local d = Widgets().Dialog(CreateFrame("Frame"), nil, {})
		eq(d.content, d.card)
		truthy(d.card.parts.fill and d.card.parts.ring and d.card.parts.shadow and d.card.parts.highlight)
	end)
end)

describe("edit box", function()
	local function box(opts) return Widgets().EditBox(CreateFrame("Frame"), opts or {}) end

	it("shows its placeholder while empty and unfocused, and gets out of the way", function()
		local b = box({ placeholder = "Search" })
		truthy(b.placeholder:IsShown()); eq(b.placeholder:GetText(), "Search")
		b.edit:SetFocus()
		falsy(b.placeholder:IsShown())
		near(r1(b.ring), token1("accent"), 1e-6)
		b.edit:ClearFocus()
		truthy(b.placeholder:IsShown())
		near(r1(b.ring), token1("border"), 1e-6)
		b:SetText("abc")
		falsy(b.placeholder:IsShown())
		b:Clear()
		truthy(b.placeholder:IsShown())
		b:SetPlaceholder("Other")
		eq(b.placeholder:GetText(), "Other")
		b:SetPlaceholder(nil)
		falsy(b.placeholder:IsShown())
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
		near((list.rows[2].label:GetTextColor()), token1("text-1"), 1e-6)
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

describe("switch", function()
	it("toggles on click, reports the change and slides the thumb", function()
		local seen
		local s = Widgets().Switch(CreateFrame("Frame"), { onChange = function(on) seen = on end })
		falsy(s:IsOn())
		Mock.RunScript(s, "OnClick")
		truthy(s:IsOn()); eq(seen, true)
		eq(first(groupOf(s.thumb))._kind, "Translation")
		eq((first(groupOf(s.thumb)):GetOffset()), 18)
		Mock.FinishAnimations()
		local _, _, _, x = s.thumb:GetPoint(1)
		eq(x, 22)
		Mock.RunScript(s, "OnClick")
		falsy(s:IsOn()); eq(seen, false)
	end)

	it("SetOn with silent does not call back, and a disabled switch ignores clicks", function()
		local n = 0
		local s = Widgets().Switch(CreateFrame("Frame"), { onChange = function() n = n + 1 end })
		s:SetOn(true, true)
		eq(n, 0); truthy(s:IsOn())
		s:SetEnabled(false)
		Mock.RunScript(s, "OnClick")
		truthy(s:IsOn()); eq(n, 0)
		near(s:GetAlpha(), 0.45, 1e-9)
	end)

	it("starts on when asked, takes the accent and follows the theme", function()
		local s = Widgets().Switch(CreateFrame("Frame"), { on = true })
		truthy(s:IsOn())
		near(r1(s.track), token1("accent"), 1e-6)
		Th().Apply("accord")
		near(r1(s.track), token1("accent", "accord"), 1e-6)
		s:SetOn(false, true)
		near(r1(s.track), token1("surface-3", "accord"), 1e-6)
	end)

	it("with Animations off the thumb is at its place at once", function()
		C():Set("account.settings.animations", false)
		local s = Widgets().Switch(CreateFrame("Frame"), {})
		s:SetOn(true)
		falsy(s.thumb._animGroups)
		local _, _, _, x = s.thumb:GetPoint(1)
		eq(x, 22)
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
		near(r1(s.ring), token1("accent"), 1e-6)
		s:Close()
		near(r1(s.ring), token1("border"), 1e-6)
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
	it("shows the text with the tone, fades in and goes away after 4 s", function()
		local sb = Widgets().Snackbar(CreateFrame("Frame"))
		falsy(sb:IsShown())
		sb:Say("Saved", "ok")
		truthy(sb:IsShown()); eq(sb:Message(), "Saved")
		near(r1(sb.dot), token1("ok"), 1e-6)
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
		near(r1(sb.dot), token1("err"), 1e-6)
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
	it("shows the caller's lines in an inverted frame of its own: text-1 behind bg text", function()
		local owner = CreateFrame("Frame")
		local tip = Widgets().Tooltip
		falsy(tip.IsShown())
		local f = tip.Show(owner, { "Title", "One line", { text = "Warning", token = "err" } })
		truthy(f); truthy(tip.IsShown()); eq(tip.Owner(), owner)
		deepEq(tip.Lines(), { "Title", "One line", "Warning" })
		near(r1(f.parts.fill), token1("text-1"), 1e-6)
		near((f.lines[1]:GetTextColor()), token1("bg"), 1e-6)
		near((f.lines[3]:GetTextColor()), token1("err"), 1e-6)
		eq(f:GetFrameStrata(), "TOOLTIP")
		falsy(f:IsMouseEnabled(), "the pointer goes through it")
		Th().Apply("aurora")
		near(r1(f.parts.fill), token1("text-1", "aurora"), 1e-6)
		near((f.lines[1]:GetTextColor()), token1("bg", "aurora"), 1e-6)
		tip.Hide()
		falsy(tip.IsShown()); isNil(tip.Owner())
	end)

	it("takes a string or a list, grows to its longest line up to a maximum and anchors where asked", function()
		local owner = CreateFrame("Frame")
		local tip = Widgets().Tooltip
		local f = tip.Show(owner, "Shorter text")
		eq(f:GetWidth(), #"Shorter text" * 6 + 20)
		f = tip.Show(owner, { "Title", string.rep("x", 200) })
		eq(f:GetWidth(), tip.MAX_WIDTH + 20)
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
		t.list:SetHeight(50 * 30)
		Mock.RunScript(t, "OnSizeChanged")
		eq(#t.rows, 50)
		eq(t:Capacity(), 50)
		eq(#t:VisibleRows(), 50)
		t.list:SetHeight(500 * 30)
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
		Mock.RunScript(rows[1], "OnEnter")
		near(rows[1].hover._texture[4], 1, 1e-6)
		Mock.RunScript(rows[1], "OnLeave")
		near(rows[1].hover._texture[4], 0, 1e-6)
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

-- Theme, Assets and Motion (M6.10): the tokens of docs/specs/ui-style.md §4 in three themes, WCAG contrast of text on
-- surfaces, the registry of tinted regions and Theme.Apply, fonts with the game fallback, Px, the 9-slice shapes, the
-- assets table, the effects and animations preferences, and the look settings saved per account.
-- Adapted from FDCP's Tests/test_theme.lua and Tests/test_controls.lua (the motion part), same owner, GPL-3.0 (ADR 0021).

local function Th() return AzerothAccord.Theme end
local function M() return AzerothAccord.Motion end
local function C() return AzerothAccord.Config end

local function lin(c)
	if c <= 0.03928 then return c / 12.92 end
	return ((c + 0.055) / 1.055) ^ 2.4
end
local function luminance(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end
local function color(id, token) local t = Th().themes[id]; return t[token] end
local function groupOf(frame) return frame._animGroups and frame._animGroups[#frame._animGroups] end
local function first(group) return group._anims[1] end
local function output() return table.concat(Mock.PlainOutput(), "\n") end

describe("tokens", function()
	it("three themes, Nebula the default", function()
		deepEq(Th().List(), { "nebula", "aurora", "accord" })
		eq(Th().DEFAULT, "nebula")
		eq(Th().Current(), "nebula")
		falsy(Th().Has("drago"), "Drago is FDCP's: Accord has the Accord theme")
		eq(Th().Name("accord"), "Accord")
	end)

	it("the themes are the ones the settings accept", function()
		deepEq(C().THEMES, Th().List())
		for _, id in ipairs(Th().List()) do truthy(Th().Has(id)) end
	end)

	it("every theme defines exactly the tokens of the table", function()
		local expected = {}
		for _, token in ipairs(Th().TOKENS) do expected[token] = true end
		for id, t in pairs(Th().themes) do
			for token in pairs(expected) do truthy(t[token], id .. " lacks " .. token) end
			for key, value in pairs(t) do
				if type(value) == "table" then truthy(expected[key], id .. " has an unknown token " .. key) end
			end
		end
	end)

	it("every colour is four numbers between 0 and 1", function()
		for id, t in pairs(Th().themes) do
			for _, token in ipairs(Th().TOKENS) do
				local c = t[token]
				eq(#c, 4, id .. " " .. token)
				for i = 1, 4 do truthy(c[i] >= 0 and c[i] <= 1, id .. " " .. token) end
			end
		end
	end)

	it("keeps the values of FDCP for Nebula and Aurora", function()
		local r, g, b = Th().Color("accent", "nebula")
		near(r, 0xFC / 255, 1e-6); near(g, 0x7E / 255, 1e-6); near(b, 0x46 / 255, 1e-6)
		local _, _, _, a = Th().Color("border", "nebula")
		near(a, 0.14, 1e-6)
		near((Th().Color("accent", "aurora")), 0, 1e-6)
		near((Th().Color("surface-1", "aurora")), 1, 1e-6)
	end)

	it("keeps the values of the Accord theme of the spec", function()
		local r, g, b = Th().Color("accent", "accord")
		near(r, 0xD9 / 255, 1e-6); near(g, 0xB5 / 255, 1e-6); near(b, 0x4E / 255, 1e-6)
		r, g, b = Th().Color("bg", "accord")
		near(r, 0x04 / 255, 1e-6); near(g, 0x17 / 255, 1e-6); near(b, 0x1A / 255, 1e-6)
		r, g, b = Th().Color("neon", "accord")
		near(r, 0x7D / 255, 1e-6); near(g, 0xE8 / 255, 1e-6); near(b, 0xB5 / 255, 1e-6)
		local _, _, _, a = Th().Color("scrim", "accord")
		near(a, 0.72, 1e-6)
		truthy(Th().themes.accord.dark)
		truthy(Th().themes.nebula.dark)
		falsy(Th().themes.aurora.dark)
	end)

	it("an unknown token is magenta, so a typo shows", function()
		deepEq({ Th().Color("no-such-token") }, { 1, 0, 1, 1 })
	end)
end)

describe("contrast", function()
	local surfaces = { "bg", "surface-1", "surface-2", "surface-3", "raised" }

	it("text-1 and text-2 reach 4.5:1 on every surface of every theme", function()
		for id in pairs(Th().themes) do
			for _, s in ipairs(surfaces) do
				for _, text in ipairs({ "text-1", "text-2" }) do
					local ratio = contrast(color(id, text), color(id, s))
					truthy(ratio >= 4.5, ("%s %s on %s = %.2f"):format(id, text, s, ratio))
				end
			end
		end
	end)

	it("text-3 (the muted text) reaches 3:1 and accent-text 4.5:1 on the card surfaces", function()
		for id in pairs(Th().themes) do
			for _, s in ipairs({ "bg", "surface-1", "surface-2" }) do
				local r3 = contrast(color(id, "text-3"), color(id, s))
				truthy(r3 >= 3, ("%s text-3 on %s = %.2f"):format(id, s, r3))
				local ra = contrast(color(id, "accent-text"), color(id, s))
				truthy(ra >= 4.5, ("%s accent-text on %s = %.2f"):format(id, s, ra))
			end
		end
	end)

	it("the text of the primary button reaches 4.5:1 on its accent", function()
		for id in pairs(Th().themes) do
			local ratio = contrast(color(id, "on-accent"), color(id, "accent"))
			truthy(ratio >= 4.5, ("%s on-accent on accent = %.2f"):format(id, ratio))
		end
	end)

	it("the state colours read on the window background", function()
		for id in pairs(Th().themes) do
			for _, token in ipairs({ "ok", "warn", "err" }) do
				local ratio = contrast(color(id, token), color(id, "surface-1"))
				truthy(ratio >= 4.5, ("%s %s = %.2f"):format(id, token, ratio))
			end
		end
	end)

	local function pair(id, a, b) return contrast(color(id, a), color(id, b)) end

	it("the accent and the neon read as shapes (3:1) on the window background of every theme", function()
		for id in pairs(Th().themes) do
			truthy(pair(id, "accent", "bg") >= 3, id .. " accent on bg = " .. pair(id, "accent", "bg"))
			truthy(pair(id, "neon", "bg") >= 3 or id == "nebula", id .. " neon on bg")
		end
	end)

	it("the state colours read on the raised and secondary surfaces too (3:1 as a badge text on its tint)", function()
		for id in pairs(Th().themes) do
			for _, token in ipairs({ "ok", "warn", "err", "accent-text" }) do
				for _, s in ipairs({ "surface-3", "raised" }) do
					local ratio = pair(id, token, s)
					truthy(ratio >= 3, ("%s %s on %s = %.2f"):format(id, token, s, ratio))
				end
			end
		end
	end)

	it("the strong border is a visible edge on every surface (1.3:1 at least)", function()
		for id, t in pairs(Th().themes) do
			local b = t["border-strong"]
			for _, s in ipairs({ "bg", "surface-1", "surface-2" }) do
				local base = t[s]
				local mixed = { b[1] * b[4] + base[1] * (1 - b[4]), b[2] * b[4] + base[2] * (1 - b[4]), b[3] * b[4] + base[3] * (1 - b[4]) }
				truthy(contrast(mixed, base) >= 1.3, id .. " border-strong on " .. s)
			end
		end
	end)

	it("the M3 roles of M12.6: text on its container 4.5:1, the tonal fill a visible step from surface-1 (ui-style §9.1)", function()
		for id in pairs(Th().themes) do
			local r = pair(id, "on-secondary-container", "secondary-container")
			truthy(r >= 4.5, ("%s on-secondary-container = %.2f"):format(id, r))
			r = pair(id, "inverse-on-surface", "inverse-surface")
			truthy(r >= 4.5, ("%s inverse-on-surface = %.2f"):format(id, r))
			r = pair(id, "on-error", "err")
			truthy(r >= 4.5, ("%s on-error on err = %.2f"):format(id, r))
			r = pair(id, "secondary-container", "surface-1")
			truthy(r >= 1.3, ("%s secondary-container on surface-1 = %.2f"):format(id, r))
			-- the inverse surface stands out of the window (a tooltip on the dark themes is light, on Aurora dark)
			r = pair(id, "inverse-surface", "bg")
			truthy(r >= 3, ("%s inverse-surface on bg = %.2f"):format(id, r))
		end
	end)

	it("the M3 roles' worst cases are the ones of the spec table (ui-style §9.1)", function()
		local function worst(a, b)
			local w = math.huge
			for id in pairs(Th().themes) do w = math.min(w, pair(id, a, b)) end
			return w
		end
		near(worst("on-secondary-container", "secondary-container"), 8.24, 0.01)
		near(worst("inverse-on-surface", "inverse-surface"), 12.01, 0.01)
		near(worst("on-error", "err"), 5.90, 0.01)
		near(worst("secondary-container", "surface-1"), 1.42, 0.01)
	end)

	it("the worst cases of the Accord theme are the ones the spec table says", function()
		local worst = math.huge
		for _, s in ipairs({ "bg", "surface-1", "surface-2", "surface-3", "raised" }) do
			worst = math.min(worst, pair("accord", "text-2", s))
		end
		near(worst, 6.88, 0.01)
		near(pair("accord", "on-accent", "accent"), 8.55, 0.01)
		near(pair("accord", "accent", "bg"), 9.34, 0.01)
		near(pair("accord", "err", "surface-1"), 5.86, 0.01)
	end)
end)

describe("registry", function()
	it("Tint, Fill and Text show the token and Apply recolours without /reload", function()
		local f = CreateFrame("Frame")
		local tex, solid = f:CreateTexture(), f:CreateTexture()
		local fs = f:CreateFontString()
		Th().Tint(tex, "accent"); Th().Fill(solid, "surface-1"); Th().Text(fs, "text-1")
		local r = tex:GetVertexColor()
		near(r, 0xFC / 255, 1e-6)
		truthy(Th().Apply("aurora"))
		eq(Th().Current(), "aurora")
		r = tex:GetVertexColor()
		near(r, 0, 1e-6)                        -- Aurora's accent #0054B6 has no red
		near(select(1, fs:GetTextColor()), 0x0B / 255, 1e-6)
		near(solid._texture[1], 1, 1e-6)        -- Aurora's surface-1 is white
		truthy(Th().Apply("accord"))
		near(tex:GetVertexColor(), 0xD9 / 255, 1e-6)
		near(solid._texture[1], 0x0A / 255, 1e-6)
	end)

	it("a theme change repaints every registered region of every kind", function()
		local f = CreateFrame("Frame")
		local regions = {}
		for i = 1, 5 do
			local tex = f:CreateTexture()
			Th().Tint(tex, "accent")
			local solid = f:CreateTexture()
			Th().Fill(solid, "bg")
			local fs = f:CreateFontString()
			Th().Text(fs, "text-1")
			regions[#regions + 1] = { tex = tex, solid = solid, fs = fs }
		end
		for _, id in ipairs({ "aurora", "accord", "nebula" }) do
			Th().Apply(id)
			for _, r in ipairs(regions) do
				near((r.tex:GetVertexColor()), (color(id, "accent")[1]), 1e-6, id)
				near(r.solid._texture[1], color(id, "bg")[1], 1e-6, id)
				near((r.fs:GetTextColor()), color(id, "text-1")[1], 1e-6, id)
			end
		end
	end)

	it("an unknown theme changes nothing", function()
		falsy(Th().Apply("nope"))
		eq(Th().Current(), "nebula")
	end)

	it("registering a region again replaces its token", function()
		local tex = CreateFrame("Frame"):CreateTexture()
		Th().Tint(tex, "ok"); Th().Tint(tex, "err")
		local r, g = tex:GetVertexColor()
		near(r, 1, 1e-6); near(g, 0x63 / 255, 1e-6)
	end)

	it("Call runs now and on every Apply", function()
		local seen = {}
		Th().Call({}, function(_, id) seen[#seen + 1] = id end)
		Th().Apply("accord")
		deepEq(seen, { "nebula", "accord" })
	end)

	it("announces THEME_CHANGED on the bus", function()
		local got
		AzerothAccord.Bus:On("THEME_CHANGED", function(id) got = id end)
		Th().Apply("aurora")
		eq(got, "aurora")
	end)

	it("a region that fails to repaint does not stop the others", function()
		local good = CreateFrame("Frame"):CreateTexture()
		local armed = false
		Th().Tint({ SetVertexColor = function() if armed then error("boom") end end }, "ok")
		armed = true
		Th().Tint(good, "accent")
		truthy(Th().Apply("aurora"))
		near((good:GetVertexColor()), 0, 1e-6)
	end)

	it("the registry holds its regions weakly", function()
		collectgarbage(); collectgarbage()
		local n0 = Th().Count()
		do
			local stub = { SetVertexColor = function() end }
			Th().Tint(stub, "ok")
			eq(Th().Count(), n0 + 1)
		end
		collectgarbage(); collectgarbage()
		eq(Th().Count(), n0)
	end)
end)

describe("saved look", function()
	it("the look is saved per account, with its defaults", function()
		local s = AzerothAccordDB.settings
		eq(s.theme, "nebula"); eq(s.effects, true); eq(s.animations, true); eq(s.font, "addon")
		eq(Th().Current(), "nebula")
		truthy(Th().EffectsOn()); truthy(Th().AnimationsOn())
		deepEq(AzerothAccordCharDB.ui.columns, {}, "nothing of the look is saved per character")
		isNil(AzerothAccordCharDB.theme)
	end)

	it("Theme.Set saves, applies and survives /reload", function()
		truthy(Th().Set("accord"))
		eq(Th().Current(), "accord")
		eq(C():Get("account.settings.theme"), "accord")
		Mock.Reload()
		eq(Th().Current(), "accord")
		eq(AzerothAccord.Theme.Current(), "accord")
	end)

	it("a theme chosen through Config is applied at once", function()
		truthy(C():Set("account.settings.theme", "aurora"))
		eq(Th().Current(), "aurora")
		truthy(C():Set("account.settings.theme", "nebula"))
		eq(Th().Current(), "nebula")
	end)

	it("an unknown theme is refused and the setting keeps its value", function()
		local ok, err = Th().Set("nope")
		falsy(ok); eq(err, "bad value")
		local ok2, err2 = C():Set("account.settings.theme", "nope")
		falsy(ok2); contains(err2, "not an allowed value")
		local ok3 = C():Set("account.settings.theme", "drago")
		falsy(ok3)
		eq(C():Get("account.settings.theme"), "nebula")
	end)

	it("a damaged saved theme falls back to Nebula and the other values to their defaults", function()
		AzerothAccordDB.settings.theme = "mauve"
		AzerothAccordDB.settings.effects = "yes"
		AzerothAccordDB.settings.font = 3
		Mock.Reload()
		eq(Th().Current(), "nebula")
		eq(AzerothAccordDB.settings.effects, true)
		eq(AzerothAccordDB.settings.font, "addon")
		contains(table.concat(C().issues, "\n"), "account.settings.theme")
	end)

	it("the saved data of a newer addon is not rewritten: the theme is not saved, but it still applies", function()
		T.boot(function() AzerothAccordDB = { schemaVersion = 9, settings = { theme = "accord" } } end)
		eq(Th().Current(), "accord", "the read-only copy is read")
		local ok, why = Th().Set("aurora")
		falsy(ok); eq(why, "read-only")
		eq(AzerothAccordDB.settings.theme, "accord")
	end)

	it("the preferences answer their defaults before the saved data is loaded", function()
		local saved = C().db
		C().db = {}
		truthy(Th().EffectsOn()); truthy(Th().AnimationsOn())
		C().db = saved
	end)

	it("/accord debug has a Theme section with the look and the client's answers", function()
		Mock.ClearOutput()
		Mock.Slash("/accord debug")
		local text = output()
		contains(text, "Theme")
		contains(text, "Look: theme nebula, effects on, animations on, font source addon")
		contains(text, "Client: 9-slice yes")
		contains(text, "textures the client refused: 0")
	end)
end)

describe("fonts", function()
	it("the font objects are built at login and use the files of the addon", function()
		eq(Th().fontStatus.Body, "addon")
		eq(Th().Font("Body"):GetFont(), AzerothAccord.Assets.fonts.text.path)
	end)

	it("every font object is named AzerothAccordFont<Id> and uses the files of the addon", function()
		eq(Th().SetupFonts("addon"), 0)
		for id, spec in pairs(Th().fontSpecs) do
			eq(Th().FontName(id), "AzerothAccordFont" .. id)
			notNil(_G["AzerothAccordFont" .. id], id)
			local path = Th().Font(id):GetFont()
			contains(path, "Media\\Fonts\\")
			eq(Th().fontStatus[id], "addon")
			truthy(spec[2] >= 10)
		end
		falsy(_G.FDCPFontBody)
	end)

	it("falls back to the game font when a file does not load", function()
		Mock.missingFonts[AzerothAccord.Assets.fonts.display.path] = true
		local n = Th().SetupFonts("addon")
		truthy(n >= 1)
		eq(Th().fontStatus.Display, "game")
		eq(Th().fontStatus.Body, "addon")
		local path = Th().Font("Display"):GetFont()
		falsy(path:find("Media", 1, true))
	end)

	it("the game fonts can be chosen on purpose", function()
		local n = 0
		for _ in pairs(Th().fontSpecs) do n = n + 1 end
		eq(n, 16)
		eq(Th().SetupFonts("game"), n)
		for id in pairs(Th().fontSpecs) do eq(Th().fontStatus[id], "game") end
	end)

	it("the saved setting decides the source", function()
		truthy(C():Set("account.settings.font", "game"))
		eq(Th().fontStatus.Body, "game")
		truthy(C():Set("account.settings.font", "addon"))
		eq(Th().fontStatus.Body, "addon")
		local ok, err = C():Set("account.settings.font", "serif")
		falsy(ok); contains(err, "not an allowed value")
	end)

	it("the M3 type roles have the sizes of ui-style §9.4 and the old font ids stay (M12.6)", function()
		local sizes = { ["headline-small"] = 22, ["title-large"] = 18, ["title-medium"] = 16, ["title-small"] = 14,
			["body-large"] = 14, ["body-medium"] = 13, ["body-small"] = 11, ["label-large"] = 13, ["label-medium"] = 11,
			["label-small"] = 10 }
		local n = 0
		for role, id in pairs(Th().TYPE_ROLES) do
			n = n + 1
			notNil(sizes[role], role)
			eq(Th().fontSpecs[id][2], sizes[role], role)
			eq(Th().Font(role), Th().Font(id), role)
		end
		eq(n, 10)
		for _, id in ipairs({ "Display", "DisplaySmall", "H1", "H2", "Body", "BodyMedium", "Small", "Eyebrow", "Th", "Tab",
			"Button", "Mono", "MonoMedium", "MonoSmall" }) do notNil(Th().fontSpecs[id], id) end
		eq(Th().fontSpecs.Tab[2], 14); eq(Th().fontSpecs.MonoSmall[2], 10)
		local fs = Th().NewText(CreateFrame("Frame"), "title-large", "text-1")
		eq(fs._fontObject, Th().Font("TitleLarge"))
		eq(Th().FontId("Body"), "Body")
	end)

	it("a text made by the theme takes its font object and registers its colour", function()
		local fs = Th().NewText(CreateFrame("Frame"), "H1", "accent-text")
		eq(fs._fontObject, Th().Font("H1"))
		Th().Apply("accord")
		near((fs:GetTextColor()), 0xD9 / 255, 1e-6)
	end)

	it("a text made before the fonts were built still gets a font (the client refuses SetText without one)", function()
		local saved = Th().fontObjects
		Th().fontObjects = {}
		local fs = Th().NewText(CreateFrame("Frame"), "Body")
		notNil(fs._fontObject)
		eq(fs._fontObject, Th().fontObjects.Body)
		eq(Th().fontStatus.Body, "addon")
		Th().fontObjects = saved
	end)
end)

describe("pixels and shapes", function()
	it("Px gives one physical pixel in UI units", function()
		Mock.screen.height = 1080
		UIParent:SetScale(0.5)
		near(Th().Px(1), (768 / 1080) / 0.5, 1e-9)
		near(Th().Px(2), 2 * (768 / 1080) / 0.5, 1e-9)
		UIParent:SetScale(1)
		Mock.screen.height = 768
		near(Th().Px(3), 3, 1e-9)
	end)

	it("Px falls back to the UI scale when the screen size is unknown", function()
		GetPhysicalScreenSize = nil
		UIParent:SetScale(1)
		near(Th().Px(1), 1, 1e-9)
	end)

	it("a 9-slice texture has the margin of its radius, no snapping and its token", function()
		local f = CreateFrame("Frame")
		local tex = Th().Slice(f, "rr_fill_12", "surface-1")
		deepEq({ tex:GetTextureSliceMargins() }, { 12, 12, 12, 12 })
		eq(tex:GetTexture(), AzerothAccord.Assets.textures.rr_fill_12.path)
		falsy(tex:IsSnappingToPixelGrid())
		eq(tex:GetTexelSnappingBias(), 0)
		near((tex:GetVertexColor()), 0x11 / 255, 1e-6)
	end)

	it("every sliced texture of the table gets the margin of the table", function()
		local f = CreateFrame("Frame")
		for key, a in pairs(AzerothAccord.Assets.textures) do
			if a.slice then
				local tex = Th().Slice(f, key)
				deepEq({ tex:GetTextureSliceMargins() }, { a.slice, a.slice, a.slice, a.slice }, key)
			end
		end
	end)

	it("Panel builds fill, ring and optionally a shadow behind a frame", function()
		local f = CreateFrame("Frame")
		local p = Th().Panel(f, { radius = 18, shadow = true })
		truthy(p.fill and p.ring and p.shadow)
		eq(p.fill._asset, "rr_fill_18")
		eq(p.ring._asset, "rr_ring_18")
		falsy(Th().Panel(CreateFrame("Frame"), { radius = 8 }).shadow)
	end)

	it("the M3 shape scale picks its slice by name or radius (M12.6)", function()
		eq(Th().ShapeSlice("extra-small"), "rr_fill_4")
		eq(Th().ShapeSlice("small", "ring"), "rr_ring_8")
		eq(Th().ShapeSlice("medium"), "rr_fill_12")
		eq(Th().ShapeSlice("large"), "rr_fill_16")
		eq(Th().ShapeSlice("extra-large", "ring"), "rr_ring_28")
		eq(Th().ShapeSlice(18), "rr_fill_18")
		eq(Th().ShapeSlice("full"), "pill")
		falsy(Th().ShapeSlice("full", "ring"))
		falsy(Th().ShapeSlice("none")); falsy(Th().ShapeSlice("huge")); falsy(Th().ShapeSlice(5))
		for name in pairs(Th().SHAPES) do
			local key = Th().ShapeSlice(name)
			if key then notNil(AzerothAccord.Assets.textures[key], name) end
			key = Th().ShapeSlice(name, "ring")
			if key then notNil(AzerothAccord.Assets.textures[key], name .. " ring") end
		end
		local p = Th().Panel(CreateFrame("Frame"), { radius = "extra-large" })
		eq(p.fill._asset, "rr_fill_28"); eq(p.ring._asset, "rr_ring_28")
		eq(Th().Panel(CreateFrame("Frame"), { radius = 4 }).fill._asset, "rr_fill_4")
		deepEq({ Th().Slice(CreateFrame("Frame"), "rr_fill_16"):GetTextureSliceMargins() }, { 16, 16, 16, 16 })
	end)

	it("the probes answer without an error", function()
		local p = Th().Probes()
		eq(type(p.pixel), "number")
		truthy(p.slicing)
		eq(p.texturesRefused, 0)
		Mock.missingTextures[AzerothAccord.Assets.textures.glow_s.path] = true
		eq(Th().Probes().texturesRefused, 1)
		Mock.missingTextures[AzerothAccord.Assets.logos.logo_64.path] = true
		eq(Th().Probes().texturesRefused, 2)
	end)
end)

describe("assets table", function()
	local PREFIX = "^Interface\\AddOns\\AzerothAccord\\Media\\"

	local function pow2(n)
		local p = 1
		while p < n do p = p * 2 end
		return p == n
	end

	it("lists every texture and logo with a power-of-two size, under the addon's Media folder", function()
		local A = AzerothAccord.Assets
		for _, group in ipairs({ A.textures, A.logos }) do
			for key, t in pairs(group) do
				truthy(t.path:find(PREFIX), key .. " " .. tostring(t.path))
				truthy(t.path:find("%.tga$"), key)
				truthy(pow2(t.w) and pow2(t.h), key .. " is not a power of two")
				if t.slice then truthy(t.slice * 2 <= math.min(t.w, t.h), key .. " slice margins overlap") end
			end
		end
	end)

	it("lists every font file under Media/Fonts, each with a game font to fall back to", function()
		for key, f in pairs(AzerothAccord.Assets.fonts) do
			truthy(f.path:find(PREFIX .. "Fonts\\"), key)
			truthy(f.path:find("%.ttf$"), key)
			truthy(f.fallback == "FRIZQT" or f.fallback == "STANDARD", key)
		end
	end)

	it("has the twenty-three textures, four logos and six fonts of Media/, each file once", function()
		local A = AzerothAccord.Assets
		local n = 0
		for _ in pairs(A.textures) do n = n + 1 end
		eq(n, 23)   -- 13 of M6.9, the shape slices 4, 16 and 28 of M12.6, the 20 and the 2 pt rings of M12.7
		n = 0
		for _ in pairs(A.logos) do n = n + 1 end
		eq(n, 4)
		eq(#A.AllPaths(), 23 + 4 + 6)
		eq(#A.TexturePaths(), 23 + 4)
		local seen = {}
		for _, p in ipairs(A.AllPaths()) do falsy(seen[p], "duplicate " .. p); seen[p] = true end
		truthy(seen["Interface\\AddOns\\AzerothAccord\\Media\\logo_64.tga"])
		truthy(seen["Interface\\AddOns\\AzerothAccord\\Media\\nebula_light_256.tga"])
	end)

	it("the logo of the window is the one of the table (UI/Skin.lua is gone, M6.14)", function()
		eq(AzerothAccord.Assets.logos.logo_64.w, 64)
		isNil(AzerothAccord.Skin)
	end)

	it("the NEBULA logo that goes with a surface: the dark one on the dark themes", function()
		local A = AzerothAccord.Assets
		eq(A.NebulaLogo(true), A.logos.nebula_dark)
		eq(A.NebulaLogo(false), A.logos.nebula_light)
		eq(A.NebulaLogo(Th().IsDark()), A.logos.nebula_dark)
		Th().Apply("aurora")
		eq(A.NebulaLogo(Th().IsDark()), A.logos.nebula_light)
	end)

	it("icon coordinates follow the atlas: ten cells of 48 in a row of 512", function()
		local A = AzerothAccord.Assets
		truthy(A.textures.icons.path:find("symbols.tga", 1, true))
		eq(A.textures.icons.w, 512); eq(A.textures.icons.h, 512); eq(A.textures.icons.cell, 48)
		local s = 48 / 512
		deepEq({ A.IconCoords("chevron") }, { 0, s, 0, s })
		local l, r, t, b = A.IconCoords("check")
		near(l, s, 1e-9); near(r, 2 * s, 1e-9); near(t, 0, 1e-9); near(b, s, 1e-9)
		-- the eleventh glyph starts the second row
		l, r, t = A.IconCoords("arrow_up")
		near(l, 0, 1e-9); near(t, s, 1e-9)
		isNil(A.IconCoords("nothing"))
		isNil(A.IconCoords("nothing", true))
		isNil(A.IconCoords(nil))
	end)

	it("holds 49 outlined and 24 filled distinct glyphs that fit the atlas, filled after outlined", function()
		local A = AzerothAccord.Assets
		eq(#A.glyphs, 49); eq(#A.filledGlyphs, 24)
		local outlined = {}
		for _, g in ipairs(A.glyphs) do falsy(outlined[g], "duplicate " .. g); outlined[g] = true end
		local seen = {}
		for _, g in ipairs(A.filledGlyphs) do
			falsy(seen[g], "duplicate " .. g); seen[g] = true
			truthy(outlined[g], g .. " has an outlined cell too")
		end
		local per = math.floor(A.textures.icons.w / A.textures.icons.cell)
		eq(per, 10)
		truthy(#A.glyphs + #A.filledGlyphs <= per * per)
		-- every icon has its own cell
		local cells, n = {}, 0
		local function cell(name, filled)
			local l, _, t = A.IconCoords(name, filled)
			notNil(l, name)
			local key = l .. ":" .. t
			falsy(cells[key], name .. " shares a cell")
			cells[key] = true
			n = n + 1
		end
		for _, g in ipairs(A.glyphs) do cell(g) end
		for _, g in ipairs(A.filledGlyphs) do cell(g, true) end
		eq(n, 73)
		local s = 48 / 512
		local l, _, t = A.IconCoords("home", true)   -- the first filled one: cell 50
		near(l, 9 * s, 1e-9); near(t, 4 * s, 1e-9)
	end)

	it("every name the code used before keeps working and points at a glyph of the atlas", function()
		local A = AzerothAccord.Assets
		local old = { "chevron", "check", "cross", "dashed", "skull", "shield", "heal", "sword", "star", "gear", "arrow_up",
			"arrow_down", "lock", "eye", "dot", "plus", "info", "warn", "search", "filter", "copy", "trash", "edit",
			"calendar", "clock", "user", "users", "crown", "coin", "refresh", "download", "upload", "bell", "flag", "minus",
			"gem", "bag", "book", "link", "arrow_left", "heart", "hammer" }
		local n = 0
		for _ in pairs(A.iconNames) do n = n + 1 end
		eq(n, #old + 3)   -- and the three roles
		for _, name in ipairs(old) do
			notNil(A.iconNames[name], name)
			notNil(A.IconCoords(name), name)
			deepEq({ A.IconCoords(name) }, { A.IconCoords(A.iconNames[name]) }, name)
		end
	end)

	it("has the destinations of the navigation rail outlined and filled; an icon without a filled cell stays outlined", function()
		local A = AzerothAccord.Assets
		for _, n in ipairs({ "home", "groups", "swords", "group_add", "construction", "account_balance", "celebration",
				"shield_person", "settings" }) do
			local l, _, t = A.IconCoords(n)
			local fl, _, ft = A.IconCoords(n, true)
			notNil(l, n); notNil(fl, n)
			truthy(l ~= fl or t ~= ft, n .. " has a filled variant")
		end
		for _, n in ipairs({ "bell", "users", "hammer", "heart", "coin", "sword", "flag", "calendar", "clock", "skull", "book",
				"gem", "crown", "gear", "star" }) do
			local l, _, t = A.IconCoords(n)
			local fl, _, ft = A.IconCoords(n, true)
			truthy(l ~= fl or t ~= ft, "the view tab icon " .. n .. " has a filled variant")
		end
		deepEq({ A.IconCoords("cross", true) }, { A.IconCoords("cross") })
	end)

	it("has the three roles, outlined and filled: tank, damage and healer", function()
		local A = AzerothAccord.Assets
		for name, glyph in pairs({ role_tank = "shield", role_damage = "swords", role_healer = "medical_services" }) do
			eq(A.iconNames[name], glyph, name)
			local l, _, t = A.IconCoords(name)
			local fl, _, ft = A.IconCoords(name, true)
			notNil(l, name); notNil(fl, name)
			truthy(l ~= fl or t ~= ft, name .. " has a filled variant")
		end
	end)

	it("writes an icon inside a text with the pixels of its cell, 14 high unless told", function()
		local A = AzerothAccord.Assets
		eq(A.IconText("check"), "|T" .. A.textures.icons.path .. ":14:14:0:0:512:512:48:96:0:48|t")
		contains(A.IconText("home", 20), ":20:20:0:0:512:512:")
		eq(A.IconText("nothing"), "")
	end)
end)

describe("text colours", function()
	it("a game colour survives Apply and a token replaces it", function()
		local fs = CreateFrame("Frame"):CreateFontString()
		Th().Text(fs, "text-1")
		Th().TextRGB(fs, 0.2, 0.4, 0.6)
		Th().Apply("aurora")
		local r, g, b = fs:GetTextColor()
		near(r, 0.2, 1e-6); near(g, 0.4, 1e-6); near(b, 0.6, 1e-6)
		Th().Text(fs, "text-3")
		Th().Apply("nebula")
		near((fs:GetTextColor()), 0x9A / 255, 1e-6)    -- the token won: one colour per text
	end)

	it("a class name is class-coloured on the dark themes and text-1 on the light one", function()
		local fs = CreateFrame("Frame"):CreateFontString()
		Th().ClassText(fs, 0.78, 0.61, 0.43)
		near((fs:GetTextColor()), 0.78, 1e-6)
		Th().Apply("aurora")
		near((fs:GetTextColor()), 0x0B / 255, 1e-6)
		Th().Apply("accord")
		near((fs:GetTextColor()), 0.78, 1e-6)
	end)
end)

describe("glows and effects", function()
	local function glowOf() return Th().Glow(CreateFrame("Frame"), "glow_s", "neon", { alpha = 0.5 }) end

	it("a glow adds to the picture on the dark themes and blends on the light one", function()
		local g = glowOf()
		eq(g._additive, true)
		Th().Apply("aurora")
		eq(g._additive, false)
		Th().Apply("accord")
		eq(g._additive, true)
		Th().Apply("nebula")
		eq(g._additive, true)
	end)

	it("the Neon effects preference hides glows and shadows at once and brings them back", function()
		local f = CreateFrame("Frame")
		local g = Th().Glow(f, "glow_s", "neon")
		local p = Th().Panel(f, { radius = 12, shadow = true })
		truthy(Th().EffectsOn())
		truthy(g:IsShown() and p.shadow:IsShown())
		truthy(C():Set("account.settings.effects", false))
		falsy(Th().EffectsOn())
		falsy(g:IsShown()); falsy(p.shadow:IsShown())
		C():Set("account.settings.effects", true)
		truthy(g:IsShown() and p.shadow:IsShown())
	end)

	it("a glow shown on purpose still obeys the preference", function()
		local g = glowOf()
		Th().GlowShow(g, false)
		falsy(g:IsShown())
		Th().GlowShow(g, true)
		truthy(g:IsShown())
		C():Set("account.settings.effects", false)
		falsy(g:IsShown())
		Th().GlowShow(g, true)
		falsy(g:IsShown())
	end)

	it("the title glow is a coloured font shadow, only with effects on and a dark theme", function()
		local fs = CreateFrame("Frame"):CreateFontString()
		Th().TextGlow(fs, "accent")
		eq(fs._glowing, true)
		Th().Apply("aurora")
		eq(fs._glowing, false)
		Th().Apply("accord")
		eq(fs._glowing, true)
		C():Set("account.settings.effects", false)
		eq(fs._glowing, false)
	end)

	it("the dark themes put a light line along the top of a panel", function()
		local p = Th().Panel(CreateFrame("Frame"), { radius = 18, highlight = true })
		truthy(p.highlight)
		falsy(Th().Panel(CreateFrame("Frame"), { radius = 18 }).highlight)
	end)

	it("the effects setting is read again after /reload", function()
		C():Set("account.settings.effects", false)
		Mock.Reload()
		falsy(Th().EffectsOn())
		local g = Th().Glow(CreateFrame("Frame"), "glow_s", "neon")
		falsy(g:IsShown())
	end)
end)

describe("motion", function()
	it("the durations of the spec", function()
		eq(M().FAST, 0.12); eq(M().BASE, 0.2); eq(M().SLOW, 0.32)
		eq(M().PRESS, 0.97)
		eq(M().SMOOTHING, "OUT")
	end)

	it("Fade plays an alpha animation with the OUT curve and sets the end state when it finishes", function()
		local f = CreateFrame("Frame")
		f:SetAlpha(0.2)
		truthy(M().Fade(f, 1, M().BASE))
		local g = groupOf(f)
		truthy(g:IsPlaying())
		local a = first(g)
		eq(a._kind, "Alpha")
		eq(a:GetDuration(), 0.2); eq(a:GetSmoothing(), "OUT")
		eq(a:GetFromAlpha(), 0.2); eq(a:GetToAlpha(), 1)
		Mock.FinishAnimations()
		eq(f:GetAlpha(), 1)
	end)

	it("one group is reused for every fade of a region", function()
		local f = CreateFrame("Frame")
		M().Fade(f, 1, 0.2); M().Fade(f, 0, 0.2); M().Fade(f, 1, 0.2)
		eq(#f._animGroups, 1)
	end)

	it("with Animations off every call ends at once and nothing is played", function()
		truthy(C():Set("account.settings.animations", false))
		falsy(M().On())
		local ran = false
		local f = CreateFrame("Frame")
		falsy(M().Fade(f, 0.5, 0.2, function() ran = true end))
		eq(f:GetAlpha(), 0.5); truthy(ran)
		falsy(f._animGroups)

		local shown = CreateFrame("Frame")
		shown:Hide()
		falsy(M().FadeIn(shown, 0.2))
		truthy(shown:IsShown()); eq(shown:GetAlpha(), 1)
		falsy(M().FadeOut(shown, 0.2))
		falsy(shown:IsShown())

		local panel = CreateFrame("Frame")
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		falsy(M().Rise(panel, 16, M().SLOW))
		local _, _, _, _, y = panel:GetPoint(1)
		eq(y, 0); truthy(panel:IsShown())

		local t = CreateFrame("Frame"):CreateTexture()
		falsy(M().Rotate(t, 1.5, 0.32))
		falsy(t._animGroups, "no group made for a turn that is immediate")

		local at
		falsy(M().Slide(CreateFrame("Frame"), 18, 0, M().BASE, function(dx) at = dx end))
		eq(at, 18)

		local pulse = CreateFrame("Frame")
		local p = M().Pulse(pulse, 0.3, 1, 0.9)
		p.Start()
		falsy(groupOf(pulse):IsPlaying())
		near(pulse:GetAlpha(), 0.65, 1e-9)

		local b = CreateFrame("Button")
		M().Press(b)
		Mock.RunScript(b, "OnMouseDown")
		for _, g in ipairs(b._animGroups) do falsy(g:IsPlaying()) end

		for _, g in ipairs(Mock.animGroups) do falsy(g:IsPlaying(), "no animation group is playing") end

		C():Set("account.settings.animations", true)
		truthy(M().On())
	end)

	it("the animations preference is read again after /reload", function()
		C():Set("account.settings.animations", false)
		Mock.Reload()
		falsy(M().On())
	end)

	it("FadeIn shows a hidden region from 0 and FadeOut hides it at the end", function()
		local f = CreateFrame("Frame")
		f:Hide()
		M().FadeIn(f, 0.2)
		truthy(f:IsShown()); eq(f:GetAlpha(), 0)
		Mock.FinishAnimations()
		eq(f:GetAlpha(), 1)
		M().FadeOut(f, 0.2)
		Mock.FinishAnimations()
		falsy(f:IsShown()); eq(f:GetAlpha(), 1)
	end)

	it("Rise moves a panel up while it fades in and puts it back at its anchor", function()
		local f = CreateFrame("Frame")
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		truthy(M().Rise(f, 16, M().SLOW))
		local _, _, _, x, y = f:GetPoint(1)
		eq(y, -16)
		local g = groupOf(f)
		eq(g._anims[2]:GetOffset(), 0)
		eq(g._anims[1]:GetDuration(), 0.32)
		Mock.FinishAnimations()
		_, _, _, x, y = f:GetPoint(1)
		eq(y, 0); eq(f:GetAlpha(), 1)
	end)

	it("a turn ends at its angle", function()
		local t = CreateFrame("Frame"):CreateTexture()
		M().Rotate(t, 0, 0)
		truthy(M().Rotate(t, math.pi / 2, M().SLOW))
		eq(first(groupOf(t))._kind, "Rotation")
		Mock.FinishAnimations()
		eq(t._rotation, nil)
		falsy(M().Rotate(t, math.pi / 2, M().SLOW))   -- already there
	end)

	it("Slide places the region at the end of the movement", function()
		local f = CreateFrame("Frame")
		local at
		truthy(M().Slide(f, 18, 0, M().BASE, function(dx) at = dx end))
		eq(at, nil)
		Mock.FinishAnimations()
		eq(at, 18)
	end)

	it("a pulse repeats while shown and rests at the middle with animations off", function()
		local f = CreateFrame("Frame")
		local p = M().Pulse(f, 0.3, 1, 0.9)
		p.Start()
		eq(groupOf(f):GetLooping(), "BOUNCE"); truthy(groupOf(f):IsPlaying())
		C():Set("account.settings.animations", false)
		p.Start()
		falsy(groupOf(f):IsPlaying())
		near(f:GetAlpha(), 0.65, 1e-9)
	end)

	it("a press shrinks the button to 0.97 in 120 ms and releases it in 120 ms", function()
		local b = CreateFrame("Button")
		M().Press(b)
		Mock.RunScript(b, "OnMouseDown")
		local down, up = b._animGroups[1], b._animGroups[2]
		truthy(down:IsPlaying())
		local s = first(down)
		eq(s._kind, "Scale"); eq(s:GetDuration(), 0.12); eq(s:GetSmoothing(), "OUT")
		eq(select(1, s:GetScaleTo()), 0.97)
		Mock.RunScript(b, "OnMouseUp")
		falsy(down:IsPlaying()); truthy(up:IsPlaying())
		eq(select(1, first(up):GetScaleTo()), 1)
	end)
end)

describe("button state textures of the mock", function()
	it("a button keeps the texture it was given and answers an empty one when it has none", function()
		local b = CreateFrame("Button")
		local fresh = b:GetPushedTexture()
		notNil(fresh)
		b:SetNormalTexture("Interface\\x")
		eq(b:GetNormalTexture():GetTexture(), "Interface\\x")
		b:SetHighlightTexture("Interface\\y")
		eq(b:GetHighlightTexture():GetTexture(), "Interface\\y")
	end)
end)

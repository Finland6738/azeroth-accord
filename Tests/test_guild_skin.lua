-- The guild window in the theme while the Accord panel is open (M6.18; UI/GuildSkin.lua, ADR 0003 update, ui-style.md §3).
local function A() return AzerothAccord end
local function Tab() return A().GuildTab end
local function Skin() return A().GuildSkin end
local function guild() Mock.guild.Set{ name = "Accord", myRank = 3 } end
local function text() return table.concat(Mock.PlainOutput(), "\n") end
local function chromeParts(cf)
	return { cf.NineSlice, cf.TitleContainer, cf.PortraitContainer, cf.Bg, cf.TopTileStreaks, cf.CloseButton.Border,
		cf.Inset.NineSlice, cf.Inset.Bg }
end

describe("the guild window skin (M6.18)", function()
	-- the skin is for the panel inside the guild window, which the setting turns on (the default opens the Accord window)
	before_boot(function(M) guild() AzerothAccordDB = { schemaVersion = 4, settings = { guildPanel = true } } end)

	it("is off until the Accord tab is clicked, and the window is Blizzard's then", function()
		Mock.communities.Open()
		falsy(Skin().IsActive())
		local cf = CommunitiesFrame
		for _, part in ipairs(chromeParts(cf)) do ne(part:GetAlpha(), 0) end
		falsy(Skin().skin and Skin().skin:IsShown())
	end)

	it("makes the Blizzard chrome transparent and draws the themed frame, the name and the cross", function()
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Skin().IsActive())
		local cf = CommunitiesFrame
		for i, part in ipairs(chromeParts(cf)) do eq(part:GetAlpha(), 0, "part " .. i .. " is transparent") end
		local skin = Skin().skin
		truthy(skin:IsShown())
		eq(skin:GetParent(), cf)
		truthy(skin.parts.fill and skin.parts.ring)
		eq(skin.title:GetText(), "Accord", "the guild's name, in the theme's font")
		truthy(skin.overlay:IsShown(), "the cross sits over the close button")
		local _, relative = skin.overlay:GetPoint(1)
		eq(relative, cf.CloseButton)
		falsy(skin.overlay:IsMouseEnabled(), "a click goes through to Blizzard's button")
		ne(cf.CloseButton:GetAlpha(), nil)
	end)

	it("gives each tab a themed tile, keeps the icons of Blizzard's tabs and hides their backgrounds", function()
		Mock.communities.Open()
		Tab().tab:Click()
		local cf = CommunitiesFrame
		for _, key in ipairs(Mock.communities.TAB_KEYS) do
			local tab = cf[key]
			local tile = Skin().tiles[tab]
			notNil(tile, key)
			truthy(tile:IsShown(), key)
			eq(tab.Background:GetAlpha(), 0, key .. " background goes")
			ne(tab.Icon:GetAlpha(), 0, key .. " icon stays")
		end
		local own = Skin().tiles[Tab().tab]
		truthy(own:IsShown())
		eq(own:GetParent(), Tab().tab, "the Accord tile belongs to the Accord tab")
	end)

	it("the selected tab is tonal, without a glow: Accord's while the panel is open, a Blizzard one after it", function()
		Mock.communities.Open()
		local tonal, plain = A().Theme.Color("secondary-container"), A().Theme.Color("surface-2")
		Tab().tab:Click()
		local own = Skin().tiles[Tab().tab]   -- with the game's frame the tile comes with the skin (owner, 2026-11-26)
		eq((own.fill:GetVertexColor()), tonal)
		falsy(own.ring:IsShown()); isNil(own.glow)
		local roster = Skin().tiles[CommunitiesFrame.RosterTab]
		roster.tab:SetChecked(true)   -- Blizzard keeps its own tab checked under our panel
		Skin().Repaint()
		eq((roster.fill:GetVertexColor()), plain, "the Blizzard tab under the panel is not drawn as selected")
		Mock.communities.ClickTab("RosterTab")
		eq((own.fill:GetVertexColor()), plain)
		truthy(own.ring:IsShown())
	end)

	it("puts everything back when a Blizzard tab is clicked, the window closes or another community is chosen", function()
		local cf
		for _, how in ipairs({ "tab", "close", "club" }) do
			cf = Mock.communities.Open()
			local before = {}
			for i, part in ipairs(chromeParts(cf)) do before[i] = part:GetAlpha() end
			Tab().tab:Click()
			eq(chromeParts(cf)[1]:GetAlpha(), 0)
			if how == "tab" then Mock.communities.ClickTab("RosterTab")
			elseif how == "close" then Mock.communities.Close()
			else Mock.communities.SelectClub(1234) end
			falsy(Skin().IsActive(), how)
			falsy(Skin().skin:IsShown(), how)
			for i, part in ipairs(chromeParts(cf)) do eq(part:GetAlpha(), before[i], how .. " part " .. i) end
			falsy(Skin().skin.overlay:IsShown(), how)
			for _, key in ipairs(Mock.communities.TAB_KEYS) do falsy(Skin().tiles[cf[key]]:IsShown(), how .. " " .. key) end
			truthy(Skin().tiles[Tab().tab], "the Accord tab keeps its tile")
			Mock.communities.SelectClub(C_Club.GetGuildClubId())
			Mock.communities.Close()
		end
		eq(#Mock.errors, 0)
	end)

	it("follows the theme: the frame, the tiles and the cross are repainted", function()
		Mock.communities.Open()
		Tab().tab:Click()
		local skin = Skin().skin
		eq((skin.parts.fill:GetVertexColor()), (A().Theme.Color("bg")))
		A().Theme.Apply("aurora")
		eq((skin.parts.fill:GetVertexColor()), (A().Theme.Color("bg", "aurora")))
		eq((Skin().tiles[Tab().tab].fill:GetVertexColor()), (A().Theme.Color("secondary-container", "aurora")))
	end)

	it("a Blizzard tab that hides loses its tile too", function()
		Mock.communities.Open()
		Tab().tab:Click()
		local tile = Skin().tiles[CommunitiesFrame.GuildInfoTab]
		truthy(tile:IsShown())
		CommunitiesFrame.GuildInfoTab:Hide()
		falsy(tile:IsShown())
	end)

	it("a window without the template's art costs only the look: no error, no tile for a missing part", function()
		T.boot(function(M) guild() M.communities.withoutChrome = true end)
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Skin().IsActive())
		falsy(Skin().skin.hasClose)
		eq(#Mock.errors, 0)
		Mock.Slash("/accord debug")
		contains(text(), "Guild window skin: on")
		contains(text(), "close button not found")
	end)

	it("/accord debug reports the skin", function()
		Mock.communities.Open()
		Tab().tab:Click()
		Mock.Slash("/accord debug")
		contains(text(), "Guild window skin: on")
		contains(text(), "5 tab tile")
	end)

	it("the source only reads Blizzard's fields: nothing is assigned to the window and no function is called but alpha", function()
		local source = Mock.ReadSource("AzerothAccord/UI/GuildSkin.lua")
		notNil(source)
		local code = source:gsub("%-%-[^\n]*", "")
		falsy(code:find(":SetDisplayMode(", 1, true))
		falsy(code:find("cf%.[%w_]+%s*=[^=]"))
		falsy(code:find("cf%[[^%]]+%]%s*=[^=]"))
		falsy(code:find("hooksecurefunc", 1, true), "no function of Blizzard's is hooked here")
	end)
end)

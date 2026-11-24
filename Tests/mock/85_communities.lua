-- Mock client, part 11 (Accord, M1.8): the guild window, CommunitiesFrame of the load-on-demand Blizzard_Communities.
--
-- Imitates what the Accord tab touches (ADR 0003, SPEC-04 §1): the frame with its four side tabs ChatTab, RosterTab,
-- GuildBenefitsTab, GuildInfoTab, its Inset and CommunitiesList, the methods GetSelectedClubId, SelectClub,
-- GetDisplayMode, SetDisplayMode, and the table COMMUNITIES_FRAME_DISPLAY_MODES. These are FrameXML names, not in the API
-- dump; the M0 probe (check S1) dumps the real structure. The tab template CommunitiesFrameTabTemplate is accepted by
-- the mock's CreateFrame like any template.
--
-- Controls (Mock.communities, kept across Mock.Reload except the frame itself, which the client rebuilds):
--   Mock.communities.Load()            loads Blizzard_Communities: builds the frame, fires ADDON_LOADED
--   Mock.communities.Open() / Close()  shows or hides the window (loading it first)
--   Mock.communities.ClickTab(key)     the player clicks a Blizzard tab ("RosterTab", ...): SetDisplayMode, as Blizzard does
--   Mock.communities.SelectClub(id)    the player selects a community in the list (the guild is C_Club.GetGuildClubId())
--   Mock.communities.Minimize()        the player shrinks the window (display mode MINIMIZED)
--   Mock.communities.withoutTabs       when true at Load, the frame has no side tabs (a changed layout, GT-05)
--   Mock.communities.withoutChrome     when true at Load, the frame has none of the template's art (NineSlice, title, close button...)
--   Mock.communities.setDisplayModeCalls  how many times SetDisplayMode ran, and Mock.communities.addonCalls how many of
--                                      them did not come from the mock itself (an addon called it: forbidden, GT-04)
local Mock, H = ...
local W = Mock.world

W.communities = W.communities or { loaded = false, withoutTabs = false, withoutChrome = false, setDisplayModeCalls = 0, addonCalls = 0 }
local cm = W.communities
Mock.communities = cm
cm.loaded = false   -- the Lua state is new: the load-on-demand addon is not loaded again until something opens it

COMMUNITIES_FRAME_DISPLAY_MODES = { MINIMIZED = 1, CHAT = 2, ROSTER = 3, GUILD_FINDER = 4, GUILD_BENEFITS = 5, GUILD_INFO = 6 }
local TAB_MODES = { ChatTab = "CHAT", RosterTab = "ROSTER", GuildBenefitsTab = "GUILD_BENEFITS", GuildInfoTab = "GUILD_INFO" }
Mock.communities.TAB_KEYS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }

local fromMock = false

local function build()
	local cf = CreateFrame("Frame", "CommunitiesFrame", UIParent, "PortraitFrameTemplate")
	cf:SetSize(814, 426)
	cf:SetFrameLevel(10)
	cf:Hide()
	cf.Inset = CreateFrame("Frame", nil, cf, "InsetFrameTemplate")
	cf.Inset:SetPoint("TOPLEFT", cf, "TOPLEFT", 4, -60)
	cf.Inset:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -6, 26)
	cf.CommunitiesList = CreateFrame("Frame", nil, cf)
	if not cm.withoutChrome then
		-- the parts of PortraitFrameTemplate that the guild window skin of the addon makes transparent (M6.18, UI/GuildSkin.lua)
		cf.NineSlice = CreateFrame("Frame", nil, cf)
		cf.TitleContainer = CreateFrame("Frame", nil, cf)
		cf.TitleContainer.TitleText = cf.TitleContainer:CreateFontString(nil, "OVERLAY")
		cf.TitleContainer.TitleText:SetText("Lantern Company")
		cf.PortraitContainer = CreateFrame("Frame", nil, cf)
		cf.Bg = cf:CreateTexture(nil, "BACKGROUND")
		cf.TopTileStreaks = cf:CreateTexture(nil, "BACKGROUND")
		cf.CloseButton = CreateFrame("Button", nil, cf)
		cf.CloseButton:SetSize(24, 24)
		cf.CloseButton.Border = cf.CloseButton:CreateTexture(nil, "BACKGROUND")
		cf.Inset.NineSlice = CreateFrame("Frame", nil, cf.Inset)
		cf.Inset.Bg = cf.Inset:CreateTexture(nil, "BACKGROUND")
	end
	cf.selectedClub = C_Club.GetGuildClubId()
	cf.displayMode = COMMUNITIES_FRAME_DISPLAY_MODES.ROSTER
	function cf:GetSelectedClubId() return self.selectedClub end
	function cf:SelectClub(clubId) self.selectedClub = clubId end
	function cf:GetDisplayMode() return self.displayMode end
	function cf:SetDisplayMode(mode)
		cm.setDisplayModeCalls = cm.setDisplayModeCalls + 1
		if not fromMock then cm.addonCalls = cm.addonCalls + 1 end
		self.displayMode = mode
	end
	if not cm.withoutTabs then
		local previous
		for _, key in ipairs(Mock.communities.TAB_KEYS) do
			local tab = CreateFrame("CheckButton", nil, cf, "CommunitiesFrameTabTemplate")
			tab:SetSize(36, 36)
			if previous then tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -20)
			else tab:SetPoint("TOPLEFT", cf, "TOPRIGHT", 0, -36) end
			local mode = TAB_MODES[key]
			tab:SetScript("OnClick", function()
				fromMock = true
				cf:SetDisplayMode(COMMUNITIES_FRAME_DISPLAY_MODES[mode])
				fromMock = false
			end)
			tab.Icon = tab:CreateTexture(nil, "ARTWORK")
			tab.Background = tab:CreateTexture(nil, "BACKGROUND")
			cf[key] = tab
			previous = tab
		end
	end
	return cf
end

function cm.Load()
	if cm.loaded then return CommunitiesFrame end
	local cf = build()
	cm.loaded = true
	Mock.Fire("ADDON_LOADED", "Blizzard_Communities")
	return cf
end

function cm.Open()
	cm.Load()
	CommunitiesFrame:Show()
	return CommunitiesFrame
end

function cm.Close()
	if CommunitiesFrame then CommunitiesFrame:Hide() end
end

function cm.ClickTab(key)
	local tab = CommunitiesFrame[key]
	tab:Click()
end

-- The player selects a community: Blizzard's own code calls SelectClub (and shows the chat of that community).
function cm.SelectClub(clubId)
	fromMock = true
	CommunitiesFrame:SelectClub(clubId)
	fromMock = false
end

function cm.Minimize()
	fromMock = true
	CommunitiesFrame:SetDisplayMode(COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED)
	fromMock = false
end

-- The load-on-demand addon counts as loaded once Load ran.
local addonLoaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(name)
	if name == "Blizzard_Communities" then return cm.loaded end
	return addonLoaded(name)
end
function IsAddOnLoaded(name) return C_AddOns.IsAddOnLoaded(name) end

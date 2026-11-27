-- The Accord tab, the panel and the standalone window (M1.8; SPEC-04, ADR 0003) on the mock guild window
-- (Tests/mock/85_communities.lua). GT-01..GT-06 of SPEC-04 §1 each have a group below. M6.12: the window, its title bar
-- and the tab bar in the look of docs/specs/ui-style.md §3, and the themed panel inside the guild window.
local function A() return AzerothAccord end
-- The Accord tab opens the Accord window by default; these tests are about the panel inside the guild window (the setting).
local function panelMode() AzerothAccordDB = { schemaVersion = 4, settings = { guildPanel = true } } end
local function Tab() return A().GuildTab end
local function Shell() return A().Shell end
local function Win() return A().Window end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local function guild() Mock.guild.Set{ name = "Accord", myRank = 3 } end

-- Every field of the guild window and its tabs, to prove later that nothing was replaced.
local function snapshot()
	local cf = CommunitiesFrame
	local snap = { cf = {}, tabs = {}, scripts = {} }
	for k, v in pairs(cf) do snap.cf[k] = v end
	for _, key in ipairs(Mock.communities.TAB_KEYS) do
		local tab = cf[key]
		snap.tabs[key] = {}
		for k, v in pairs(tab) do snap.tabs[key][k] = v end
		snap.scripts[key] = tab:GetScript("OnClick")
	end
	return snap
end

local function changedFields(before, now)
	local changed = {}
	for k, v in pairs(now) do
		if before[k] ~= v and type(v) == "function" and not Mock.secureHooks[v] then changed[#changed + 1] = tostring(k) end
	end
	for k, v in pairs(before) do
		if type(v) == "function" and now[k] ~= v and not Mock.secureHooks[now[k]] then changed[#changed + 1] = tostring(k) end
	end
	return changed
end

describe("GT-01: the tab in the guild window", function()
	before_boot(function(M) guild() end)

	it("is not there before the guild window loads, then attaches when Blizzard_Communities loads", function()
		isNil(Tab().tab)
		eq(A().Compat:Feature("guildTab"), "unknown")
		Mock.communities.Open()
		notNil(Tab().tab)
		eq(Tab().tab:GetParent(), CommunitiesFrame)
		eq(Tab().tab:GetName(), "AzerothAccordGuildTab")
		eq(A().Compat:Feature("guildTab"), "available")
	end)

	it("sits under the last visible Blizzard tab and moves when a Blizzard tab hides", function()
		Mock.communities.Open()
		local point, relative, relPoint = Tab().tab:GetPoint(1)
		eq(point, "TOPLEFT"); eq(relative, CommunitiesFrame.GuildInfoTab); eq(relPoint, "BOTTOMLEFT")
		CommunitiesFrame.GuildInfoTab:Hide()
		local _, relative2 = Tab().tab:GetPoint(1)
		eq(relative2, CommunitiesFrame.GuildBenefitsTab)
	end)

	it("has the Accord logo and the Azeroth Accord tooltip", function()
		Mock.communities.Open()
		eq(Tab().tab.accordIcon:GetTexture(), AzerothAccord.Assets.logos.logo_64.path, "the addon's logo")
		Mock.RunScript(Tab().tab, "OnEnter")
		truthy(AzerothAccord.Widgets.Tooltip.IsShown())
		eq(AzerothAccord.Widgets.Tooltip.Lines()[1], "Azeroth Accord")
		Mock.RunScript(Tab().tab, "OnLeave")
		falsy(AzerothAccord.Widgets.Tooltip.IsShown())
	end)

	it("attaches at login when the guild window is already loaded, and again after /reload", function()
		T.boot(function(M) guild() M.communities.Load() end)
		notNil(Tab().tab)
		Mock.Reload()
		Mock.communities.Open()
		notNil(Tab().tab)
		eq(#Mock.errors, 0)
	end)
end)

describe("GT-03: the Accord tab opens the Accord window (owner, 2026-11-26)", function()
	before_boot(function(M) guild() end)

	it("by default a click opens the larger Accord window where the guild window was and closes the guild window", function()
		local cf = Mock.communities.Open()
		cf.GetLeft = function() return 120 end
		cf.GetTop = function() return 700 end
		Tab().tab:Click()
		truthy(A().Window:IsShown(), "the Accord window")
		falsy(Tab():IsPanelShown(), "no panel inside the guild window")
		falsy(Tab().tab:GetChecked())
		falsy(cf:IsShown(), "the guild window is closed")
		local point, _, relPoint, x, y = A().Window:Frame():GetPoint(1)
		eq(point, "TOPLEFT"); eq(relPoint, "BOTTOMLEFT"); eq(x, 120); eq(y, 700)
	end)

	it("a place the player chose for the Accord window wins", function()
		A().Config:Set("char.ui.windowPos", { point = "CENTER", relPoint = "CENTER", x = 10, y = 20 })
		Mock.communities.Open()
		Tab().tab:Click()
		local point, _, _, x, y = A().Window:Frame():GetPoint(1)
		eq(point, "CENTER"); eq(x, 10); eq(y, 20)
	end)

	it("with the setting on, the tab opens the panel inside the guild window as before", function()
		truthy(A().Config:Set("account.settings.guildPanel", true))
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Tab():IsPanelShown())
		falsy(A().Window:IsShown())
	end)
end)

describe("GT-02: when the tab shows", function()
	before_boot(function(M) guild() panelMode() end)

	it("only while the guild is the selected community", function()
		Mock.communities.Open()
		truthy(Tab().tab:IsShown())
		Mock.communities.SelectClub(1234)
		falsy(Tab().tab:IsShown())
		Mock.communities.SelectClub(C_Club.GetGuildClubId())
		truthy(Tab().tab:IsShown())
	end)

	it("not in the minimized window, and the panel closes", function()
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Tab():IsPanelShown())
		Mock.communities.Minimize()
		falsy(Tab().tab:IsShown())
		falsy(Tab():IsPanelShown())
	end)

	it("not without a guild", function()
		Mock.communities.Open()
		Mock.guild.Leave()
		falsy(Tab().tab:IsShown())
	end)
end)

describe("GT-03: the panel", function()
	before_boot(function(M) guild() panelMode() end)

	it("opens over the content area with the Accord content and checks the tab", function()
		Shell().views = {}   -- the Roster view of M2.3 registers itself: this test is about the welcome text
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Tab():IsPanelShown())
		truthy(Tab().tab:GetChecked())
		local content = Shell().content
		eq(content:GetParent(), Tab().panel)
		truthy(content:IsVisible())
		truthy(content.empty:IsShown(), "no view yet: the welcome text")
		eq(content.empty.title:GetText(), "Welcome to Azeroth Accord")
		truthy(Tab().panel:GetFrameLevel() > CommunitiesFrame:GetFrameLevel())
		-- the whole inside of the window, the list of communities too (in game a Blizzard box showed through, 2026-11-26)
		local _, list = Tab().panel:GetPoint(1)
		eq(list, CommunitiesFrame.CommunitiesList)
		local _, inset = Tab().panel:GetPoint(2)
		eq(inset, CommunitiesFrame.Inset)
		truthy(Tab().panel:DoesClipChildren(), "a wide table never spills out of the window")
	end)

	it("closes when the player clicks any Blizzard tab, and Blizzard's own click still works", function()
		Mock.communities.Open()
		for _, key in ipairs(Mock.communities.TAB_KEYS) do
			Tab().tab:Click()
			truthy(Tab():IsPanelShown())
			Mock.communities.ClickTab(key)
			falsy(Tab():IsPanelShown(), key)
			falsy(Tab().tab:GetChecked())
		end
		eq(Mock.communities.setDisplayModeCalls, 4, "Blizzard's tabs changed the display mode themselves")
	end)

	it("closes with the guild window and when another community is chosen", function()
		Mock.communities.Open()
		Tab().tab:Click()
		Mock.communities.Close()
		falsy(Tab():IsPanelShown())
		Mock.communities.Open()
		Tab().tab:Click()
		Mock.communities.SelectClub(1234)
		falsy(Tab():IsPanelShown())
	end)
end)

describe("GT-04: nothing of Blizzard's is replaced or driven", function()
	before_boot(function(M) guild() end)

	it("only hooks: no function replaced, the tabs' scripts untouched, SetDisplayMode never called by the addon", function()
		T.boot(function(M) guild() end)
		Mock.communities.Load()
		-- the addon attached during Load: compare with a fresh copy of the frame built the same way
		local cf = CommunitiesFrame
		for _, key in ipairs({ "SetDisplayMode", "SelectClub" }) do
			truthy(Mock.secureHooks[cf[key]], key .. " is a hooksecurefunc wrapper, not a replacement")
		end
		for _, name in ipairs({ "GetDisplayMode", "GetSelectedClubId" }) do
			falsy(Mock.secureHooks[cf[name]], name .. " untouched")
		end
		local before = snapshot()
		Mock.communities.Open()
		Tab().tab:Click()
		for _, key in ipairs(Mock.communities.TAB_KEYS) do Mock.communities.ClickTab(key) Tab().tab:Click() end
		Mock.communities.Minimize()
		Mock.communities.SelectClub(1234)
		Mock.communities.SelectClub(C_Club.GetGuildClubId())
		Mock.communities.Close()
		local after = snapshot()
		deepEq(changedFields(before.cf, after.cf), {})
		for _, key in ipairs(Mock.communities.TAB_KEYS) do
			eq(after.scripts[key], before.scripts[key], key .. " OnClick is Blizzard's own")
			deepEq(changedFields(before.tabs[key], after.tabs[key]), {})
		end
		eq(Mock.communities.addonCalls, 0, "SetDisplayMode was never called by the addon")
	end)

	it("the addon's source never calls SetDisplayMode nor assigns to a Blizzard frame", function()
		for _, file in ipairs({ "AzerothAccord/UI/GuildTab.lua", "AzerothAccord/UI/GuildSkin.lua", "AzerothAccord/UI/Shell.lua", "AzerothAccord/UI/Window.lua" }) do
			local source = Mock.ReadSource(file)
			notNil(source, file)
			local code = source:gsub("%-%-[^\n]*", "")
			falsy(code:find(":SetDisplayMode(", 1, true), file .. " calls SetDisplayMode")
			falsy(code:find("cf%.[%w_]+%s*=[^=]"), file .. " assigns to a field of CommunitiesFrame")
			falsy(code:find("CommunitiesFrame%.[%w_]+%s*=[^=]"), file .. " assigns to a field of CommunitiesFrame")
		end
	end)
end)

describe("GT-05: a changed guild window", function()
	it("without the expected tabs: no tab, the standalone window still works, /accord debug says why", function()
		T.boot(function(M) guild() M.communities.withoutTabs = true end)
		Mock.communities.Open()
		isNil(Tab().tab)
		eq(A().Compat:Feature("guildTab"), "missing")
		Mock.Slash("/accord")
		truthy(Win():IsShown())
		Mock.Slash("/accord debug")
		contains(text(), "[missing] guildTab - the guild window has none of the expected tabs")
		eq(#Mock.errors, 0)
	end)

	it("the Accord tab has the game's tab frame with the Accord logo inside (owner, 2026-11-26)", function()
		Mock.communities.Open()
		notNil(Tab().tab)
		eq(Tab().template, "CommunitiesFrameTabTemplate")
		eq(Tab().tab.accordIcon:GetTexture(), AzerothAccord.Assets.logos.logo_64.path)
		isNil(A().GuildSkin.tiles and A().GuildSkin.tiles[Tab().tab], "no own tile: the game's frame is the look")
		local skinned = Tab().SkinnedTabs()
		eq(skinned[#skinned], Tab().tab, "while the panel is open it is drawn like the Blizzard tabs")
	end)

	it("without the template it falls back to the addon's own tile (M6.18)", function()
		local saved = Tab().TEMPLATES
		Tab().TEMPLATES = { "" }   -- what is left when the client refuses the template (CreateFrame raises)
		Mock.communities.Open()
		Tab().TEMPLATES = saved
		notNil(Tab().tab)
		notNil(A().GuildSkin.tiles[Tab().tab])
	end)

	it("sits under the LOWEST tab as drawn, at the measured distance, not under the last key (Forever)", function()
		Mock.communities.Open()
		local cf = CommunitiesFrame
		-- drawn order on Forever: Chat, Roster, Info, Benefits (Benefits is the lowest although its key comes before Info)
		local place = { ChatTab = 400, RosterTab = 338, GuildInfoTab = 276, GuildBenefitsTab = 214 }
		for key, top in pairs(place) do
			local tab = cf[key]
			tab.GetTop = function() return top end
			tab.GetBottom = function() return top - 36 end
		end
		Tab():Anchor()
		local point, relative, relPoint, _, y = Tab().tab:GetPoint(1)
		eq(point, "TOPLEFT"); eq(relative, cf.GuildBenefitsTab); eq(relPoint, "BOTTOMLEFT")
		eq(y, -26, "the gap Blizzard leaves between its tabs (62 - 36)")
		Mock.Slash("/accord debug")
		contains(text(), "under GuildBenefitsTab, gap 26 (measured)")
	end)
end)

describe("GT-06: combat", function()
	before_boot(function(M) guild() panelMode() end)

	it("the tab, the panel and the window open and close in combat", function()
		Mock.world.inCombat = true
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Tab():IsPanelShown())
		Mock.communities.ClickTab("RosterTab")
		falsy(Tab():IsPanelShown())
		Mock.Slash("/accord")
		truthy(Win():IsShown())
		Mock.Slash("/accord")
		falsy(Win():IsShown())
		eq(#Mock.errors, 0)
	end)
end)

describe("the standalone window (SPEC-04 §3, ui-style.md §3)", function()
	before_boot(function(M) guild() end)

	it("/accord opens and closes it with the panel inside; /acc, the key binding and the Compartment too", function()
		Mock.Slash("/accord")
		truthy(Win():IsShown())
		eq(Shell().content:GetParent(), Win().frame.body)
		falsy(Shell().content.bar.popOut:IsShown(), "no pop out inside the window")
		Mock.Slash("/acc")
		falsy(Win():IsShown())
		AzerothAccord_ToggleBinding()
		truthy(Win():IsShown())
		AzerothAccord_OnAddonCompartmentClick()
		falsy(Win():IsShown())
	end)

	it("is a window of the addon: a Theme panel with shadow, the 52-point title bar, no Blizzard template", function()
		Mock.Slash("/accord")
		local f = Win().frame
		isNil(f._template, "no Blizzard window template")
		notNil(f.parts.fill); notNil(f.parts.ring); notNil(f.parts.shadow)
		eq(f.parts.fill._asset, "rr_fill_12", "radius 12")
		local bar = f.titleBar
		eq(bar:GetHeight(), 52)
		eq(bar.title:GetText(), "AZEROTH ACCORD")
		eq(bar.title:GetFontObject(), A().Theme.Font("Display"))
		eq(bar.logo:GetTexture(), A().Assets.logos.logo_64.path)
		eq(bar.subtitle:GetText(), "0 guildmate(s) with Accord online · no data received yet", "the sync state under the title")
		bar.close:Click()
		falsy(Win():IsShown())
	end)

	it("says so without a guild and opens nothing", function()
		T.boot(function(M) M.guild.Leave() end)
		Mock.Slash("/accord")
		falsy(Win():IsShown())
		contains(text(), "You are not in a guild.")
	end)

	it("closes with Esc and when the character leaves the guild", function()
		Mock.Slash("/accord")
		local n = 0
		for _, name in ipairs(UISpecialFrames) do if name == "AzerothAccordWindow" then n = n + 1 end end
		eq(n, 1, "Esc closes it (registered once)")
		Mock.guild.Leave()
		falsy(Win():IsShown())
	end)

	it("moves by its title bar, resizes from the grip within its bounds and remembers where it was and how big", function()
		Mock.Slash("/accord")
		local f = Win().frame
		truthy(f:IsMovable()); truthy(f:IsResizable()); truthy(f._clamped)
		deepEq(f._bounds, { 720, 460, 1600, 1000 })
		eq(f:GetWidth(), 1380); eq(f:GetHeight(), 720)
		eq(f.grip.icon:GetTexture(), A().Assets.textures.icons.path, "the grip is the kit's icon, no Blizzard texture")
		Mock.RunScript(f.titleBar, "OnDragStart", "LeftButton")
		truthy(f._moving, "dragging the title bar moves the window")
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -80)
		Mock.RunScript(f.titleBar, "OnDragStop")
		Mock.RunScript(f.grip, "OnMouseDown")
		truthy(f._sizing)
		f:SetSize(1000, 640)
		Mock.RunScript(f.grip, "OnMouseUp")
		falsy(f._sizing)
		Mock.Reload()
		Mock.Slash("/accord")
		local point, _, _, x, y = Win().frame:GetPoint(1)
		eq(point, "TOPLEFT"); eq(x, 100); eq(y, -80)
		eq(Win().frame:GetWidth(), 1000); eq(Win().frame:GetHeight(), 640)
		Win():ResetPosition()
		eq(Win().frame:GetWidth(), 1380)
		isNil(AzerothAccordCharDB.ui.windowPos)
	end)

	it("a size saved below today's minimum opens at the minimum", function()
		A().Config:Set("char.ui.windowSize", { w = 640, h = 400, v = 3 })
		Mock.Slash("/accord")
		eq(Win().frame:GetWidth(), 720); eq(Win().frame:GetHeight(), 460)
	end)

	it("a size saved before the wider default (2026-11-27) is not reused: the window opens at 1380 x 720", function()
		A().Config:Set("char.ui.windowSize", { w = 920, h = 600 })
		Mock.Slash("/accord")
		eq(Win().frame:GetWidth(), 1380); eq(Win().frame:GetHeight(), 720)
	end)

	it("the default never opens wider than the screen", function()
		UIParent._width = 1100
		Mock.Slash("/accord")
		UIParent._width = 1920
		eq(Win().frame:GetWidth(), 1060)
	end)

	it("pop out moves the panel from the guild window to the window, pop in moves it back", function()
		A().Config:Set("account.settings.guildPanel", true)
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Shell().content.bar.popOut:IsShown())
		Shell().content.bar.popOut:Click()
		falsy(Tab():IsPanelShown())
		truthy(Win():IsShown())
		eq(Shell().content:GetParent(), Win().frame.body)
		local popIn = Win().frame.titleBar.popIn
		truthy(popIn:IsShown(), "the guild window is open: pop in is offered")
		popIn:Click()
		falsy(Win():IsShown(), "the window closes")
		truthy(Tab():IsPanelShown())
		eq(Shell().content:GetParent(), Tab().panel)
		eq(#Mock.errors, 0)
	end)

	it("pop in shows only while the guild window can take the panel; a click on the tab takes it and closes the window", function()
		A().Config:Set("account.settings.guildPanel", true)
		Mock.Slash("/accord")
		falsy(Win().frame.titleBar.popIn:IsShown(), "no guild window: no pop in (the addon never opens it)")
		Mock.communities.Open()
		truthy(Win().frame.titleBar.popIn:IsShown())
		Mock.communities.SelectClub(1234)
		falsy(Win().frame.titleBar.popIn:IsShown(), "another community: the Accord tab is hidden")
		Mock.communities.SelectClub(C_Club.GetGuildClubId())
		truthy(Win().frame.titleBar.popIn:IsShown())
		Mock.communities.Close()
		falsy(Win().frame.titleBar.popIn:IsShown())
		falsy(Shell():PopIn())
		truthy(Win():IsShown())
		Mock.communities.Open()
		Tab().tab:Click()
		eq(Shell().content:GetParent(), Tab().panel)
		falsy(Win():IsShown(), "the window does not stay open and empty")
	end)

	it("the Compartment tooltip has the title, the hint and the sync state", function()
		AzerothAccord_OnAddonCompartmentEnter(nil, UIParent)
		local lines = GameTooltip._lines or {}
		contains(table.concat(lines, "\n"), "Click to open or close the Accord window.")
		contains(table.concat(lines, "\n"), "guildmate(s) with Accord online")
	end)
end)

describe("the panel in the guild window (ui-style.md §3, ADR 0003)", function()
	before_boot(function(M) guild() panelMode() end)

	it("is the addon's own frame with the theme's fill, the same tabs, no title bar, Pop out and the sync state", function()
		Mock.communities.Open()
		Tab().tab:Click()
		local panel, content = Tab().panel, Shell().content
		eq(panel:GetParent(), CommunitiesFrame)
		local r, g, b = A().Theme.Color("bg")
		deepEq({ panel.fill._texture[1], panel.fill._texture[2], panel.fill._texture[3] }, { r, g, b })
		isNil(panel.titleBar); isNil(content.titleBar)
		truthy(content.tabs:IsVisible())
		eq(content.tabs:GetParent(), content.bar)
		truthy(content.bar.popOut:IsShown())
		truthy(content.footer:IsShown())
		eq(content.status:GetText(), "0 guildmate(s) with Accord online · no data received yet")
		eq(content.bar.searchField:GetWidth(), 150, "a narrower search box in the narrower area")
		-- the same content in the window: no footer (the title bar has the state), the wider search box
		Shell().content.bar.popOut:Click()
		falsy(content.footer:IsShown())
		eq(content.bar.searchField:GetWidth(), 200)
	end)

	it("the badge of the Accord tab is the kit's count badge, repainted by a theme change", function()
		Mock.communities.Open()
		Tab():SetBadge(3)
		local badge = Tab().tab.badge
		eq(badge.label:GetText(), "3")
		eq(badge.tone, "err")
		eq((badge.fill:GetVertexColor()), (A().Theme.Color("err")))
		A().Theme.Apply("aurora")
		eq((badge.fill:GetVertexColor()), (A().Theme.Color("err", "aurora")))
		Tab():SetBadge(0)
		falsy(badge:IsShown())
		Tab():SetBadge(150)
		eq(badge.label:GetText(), "99+")
	end)
end)

describe("the rail and the pages (SPEC-04 §2, ui-style.md §9.11, M13.7)", function()
	before_boot(function(M) guild() end)

	local function rail() return Shell().content.rail end
	local function item(id) return rail().items[id] end
	local function keys(list) local out = {} for i, p in ipairs(list) do out[i] = p.key end return out end

	it("shows no rail icon, no tabs and the welcome text while no view exists; view commands say coming soon", function()
		Shell().views = {}   -- the views register themselves: here none exists
		Mock.Slash("/accord")
		isNil(Shell().content.tabs)
		deepEq(rail().order, {})
		truthy(Shell().content.empty:IsShown())
		eq(Shell().content.empty.title:GetText(), "Welcome to Azeroth Accord")
		falsy(Shell().content.bar.searchField:IsShown(), "no search without a view that can search")
		Mock.ClearOutput()
		Mock.Slash("/accord professions")
		contains(text(), "coming soon")
	end)

	it("a view gets the icon of its destination and a tab of its row; one page shows only the destination's name", function()
		Shell().views = {}
		local built = {}
		Shell():RegisterView("roster", { label = "Roster", order = 1, search = true, build = function(f) built.roster = f end })
		Shell():RegisterView("bank", { label = "Bank", order = 4, build = function(f) built.bank = f end })
		Mock.Slash("/accord bank")
		truthy(Win():IsShown())
		local content = Shell().content
		deepEq(rail().order, { "guild", "economy" })
		eq(content.dest, "economy")
		eq(content.bar.title:GetText(), "Economy", "the destination's name at the start of the row")
		isNil(content.tabs, "a destination with one page has no tabs")
		truthy(item("economy").active)
		isNil(item("economy").indicator, "nothing behind the active icon")
		eq((item("economy").icon:GetVertexColor()), (A().Theme.Color("accent-text")), "the active icon in the accent")
		eq((item("guild").icon:GetVertexColor()), (A().Theme.Color("text-2")))
		notNil(built.bank)
		isNil(built.roster, "a view is built when first shown")
		eq(built.bank:GetParent(), content.body, "the view's frame fills the body")
		falsy(content.bar.searchField:IsShown(), "Bank cannot search here")
		item("guild"):Click()
		notNil(built.roster)
		eq(Shell().selected, "roster")
		eq(content.bar.title:GetText(), "Guild")
		truthy(item("guild").active); falsy(item("economy").active)
		truthy(content.bar.searchField:IsShown())
		eq(AzerothAccordCharDB.ui.lastView, "roster")
		-- a second page of the Guild destination: now the row has tabs, after the name
		Shell():RegisterView("reputation", { label = "Reputation", order = 3, build = function() end })
		local tabs = content.tabs
		notNil(tabs)
		eq(tabs:GetParent(), content.bar)
		deepEq(tabs.order, { "roster", "reputation" })
		eq(tabs.buttons.roster.label:GetText(), "Roster")
		eq(tabs:Active(), "roster")
		truthy(tabs.indicator:IsShown(), "the active tab has the accent indicator (ui-style §9.6)")
		eq(content.bar:GetHeight(), 48)
		isNil(tabs.buttons.reputation.ring, "no box (M12.7)")
		isNil(tabs.buttons.reputation.fill, "no fill")
		tabs.buttons.reputation:Click()
		eq(Shell().selected, "reputation")
		eq(AzerothAccordCharDB.ui.lastView, "reputation")
		-- back to the economy and to the guild: the rail opens the page shown last
		item("economy"):Click()
		isNil(content.tabs)
		item("guild"):Click()
		eq(Shell().selected, "reputation")
		eq(content.tabs:Active(), "reputation")
	end)

	it("every rail icon has its name in a tooltip, at the right of the rail", function()
		Mock.Slash("/accord")
		for _, id in ipairs(rail().order) do
			local it = item(id)
			Mock.RunScript(it, "OnEnter")
			truthy(A().Widgets.Tooltip.IsShown(), id)
			deepEq(A().Widgets.Tooltip.Lines(), { A().Shell.Destination(id).label }, id)
			Mock.RunScript(it, "OnLeave")
			falsy(A().Widgets.Tooltip.IsShown())
		end
	end)

	it("a background shows only under the mouse, on the clicked item too, after a change of destination and of theme", function()
		local Th, STATE = A().Theme, A().Theme.STATE
		local function clean(where)   -- a recolour must not raise a layer's opacity (the white pill, 2026-11-27)
			for _, id in ipairs(rail().order) do eq(item(id).over:GetAlpha(), 0, where .. ": " .. id) end
		end
		Mock.Slash("/accord roster")
		for _, id in ipairs({ "raid", "guild", "economy" }) do item(id):Click() end
		clean("after the clicks")
		for _, theme in ipairs(Th.ORDER) do
			Th.Apply(theme)
			clean(theme)
			eq((item("economy").icon:GetVertexColor()), (Th.Color("accent-text", theme)), theme)
		end
		-- the pointed item, through a click and out
		local raid = item("raid")
		Mock.RunScript(raid, "OnEnter")
		Mock.RunScript(raid, "OnMouseDown")
		Mock.RunScript(raid, "OnMouseUp")
		raid:Click()
		raid.over:SetAlpha(STATE.hover)   -- where the 120 ms fade ends
		A().Widgets.SetStateColor(raid.over, "text-2")
		eq(raid.over:GetAlpha(), STATE.hover, "a recolour under the mouse keeps the hover opacity")
		A().Widgets.SetStateColor(raid.over, "accent-text")
		Mock.RunScript(raid, "OnLeave")
		eq(raid.over._state, nil, "gone when the mouse leaves")
		Mock.RunScript(raid, "OnEnter")
		eq(raid.over._state, "hover")
		Mock.Slash("/accord")
		falsy(Win():IsShown())
		Mock.RunScript(raid, "OnHide")
		eq(raid.over._state, nil, "an item hidden under the mouse comes back without the layer")
	end)

	it("what is typed in the search box goes to the selected view only", function()
		Shell().views = {}
		local got = {}
		Shell():RegisterView("roster", { label = "Roster", order = 1, search = true, build = function() end,
			onSearch = function(t) got.roster = t end })
		Shell():RegisterView("reputation", { label = "Reputation", order = 3, search = true, build = function() end,
			onSearch = function(t) got.reputation = t end })
		Mock.Slash("/accord roster")
		Mock.TypeInto(Shell().content.bar.search, "mira")
		eq(got.roster, "mira"); isNil(got.reputation)
		Shell().content.bar.search:SetText("set by a view")
		eq(got.roster, "mira", "text a view sets is not sent back to it")
		eq(Shell().content.bar.searchField:GetText(), "set by a view")
	end)

	-- The map of ui-style §9.11 with the switches as they ship (econ off: no Market, Orders, Shopping list).
	local MAP = {
		home = { "actions:inbox", "actions:notices" },
		guild = { "roster", "reputation", "mentors", "addons" },
		raid = { "season", "events", "raid", "availability" },
		groups = { "groups:list", "groups:form", "groups:mine", "rallies" },
		professions = { "professions" },
		economy = { "bank" },
		community = { "handbook" },
		settings = { "settings:settings", "settings:share", "settings:info" },
	}

	it("the destinations and their pages are those of the map, and every page opens from the rail and its tab", function()
		Mock.Slash("/accord")
		deepEq(rail().order, { "home", "guild", "raid", "groups", "professions", "economy", "community", "settings" },
			"a member sees 7 icons and Settings")
		local names = {}
		for i, id in ipairs(rail().order) do names[i] = item(id).name end
		deepEq(names, { "Home", "Guild", "Raid", "Groups", "Professions", "Economy", "Community", "Settings" })
		for _, dest in ipairs(rail().order) do
			deepEq(keys(Shell():PageList(dest)), MAP[dest], dest)
			item(dest):Click()
			eq(Shell().content.dest, dest)
			for _, key in ipairs(MAP[dest]) do
				local tabs = Shell().content.tabs
				if #MAP[dest] > 1 then
					tabs.buttons[key]:Click()
					eq(tabs:Active(), key, key)
				else
					isNil(tabs, dest .. ": one page, only the name")
				end
				local id = Shell().SplitKey(key)
				eq(Shell().selected, id)
				eq(Shell():KeyOf(id), key)
				truthy(Shell().views[id].frame:IsVisible(), key .. " shows")
				isNil(Shell().views[id].failed, key .. " built")
				isNil(Shell().views[id].frame.pager, key .. ": no second row of navigation in the view")
			end
		end
		Mock.Slash("/accord")
		falsy(Win():IsShown())
		for _, id in ipairs({ "roster", "professions", "reputation", "bank", "settings" }) do
			Mock.Slash("/accord " .. id)
			truthy(Win():IsShown(), "/accord " .. id)
			eq(Shell().selected, id, "/accord " .. id)
			truthy(Shell().views[id].frame:IsVisible())
		end
		eq(#Mock.errors, 0)
	end)

	it("the active page is in its tab and its destination at a glance; the page is remembered as view:page", function()
		Mock.Slash("/accord settings")
		local tabs = Shell().content.tabs
		eq(Shell().content.bar.title:GetText(), "Settings")
		deepEq(tabs.order, { "settings:settings", "settings:share", "settings:info" })
		eq(tabs.buttons["settings:settings"].label:GetText(), "General")
		tabs.buttons["settings:info"]:Click()
		eq(AzerothAccordCharDB.ui.lastView, "settings:info")
		truthy(item("settings").active)
		eq(A().SettingsView.frame.pageId, "info")
		-- a view that changes its own page (a link of the Action Center): the row follows
		Mock.Slash("/accord groups")
		A().GroupsView:ShowMine()
		eq(Shell().content.tabs:Active(), "groups:mine")
		eq(AzerothAccordCharDB.ui.lastView, "groups:mine")
		-- after /reload the same page opens
		local saved = AzerothAccordCharDB
		T.boot(function(M) guild() AzerothAccordCharDB = saved end)
		Mock.Slash("/accord")
		eq(Shell().selected, "groups")
		eq(Shell().content.tabs:Active(), "groups:mine")
	end)

	it("an old remembered view (before M13.7) opens its page; one that cannot show falls back to the first", function()
		T.boot(function(M) guild() AzerothAccordCharDB = { schemaVersion = 1, ui = { lastView = "events" } } end)
		Mock.Slash("/accord")
		eq(Shell().selected, "events")
		eq(Shell().content.dest, "raid")
		T.boot(function(M) guild() AzerothAccordCharDB = { schemaVersion = 1, ui = { lastView = "officers:queue" } } end)
		Mock.Slash("/accord")
		eq(Shell().selected, "actions", "a member cannot see the Officers: the first page of Home")
	end)

	it("the Officers icon only for those allowed", function()
		Mock.Slash("/accord")
		isNil(Shell().views.officers.frame)
		falsy(item("officers"):IsShown())
		T.boot(function(M) Mock.guild.Set{ name = "Accord", myRank = 0 } end)
		Mock.Slash("/accord")
		truthy(item("officers"):IsShown())
		deepEq(rail().order, { "home", "guild", "raid", "groups", "professions", "economy", "community", "officers", "settings" })
		item("officers"):Click()
		local tabs = Shell().content.tabs
		eq(Shell().content.bar.title:GetText(), "Officers")
		truthy(#tabs.order >= 2)
		for _, key in ipairs(tabs.order) do
			tabs.buttons[key]:Click()
			truthy(Shell().views.officers.frame:IsVisible(), key)
			eq(A().OfficersView.pageId, select(2, Shell().SplitKey(key)))
		end
		eq(#Mock.errors, 0)
	end)

	it("every page opens from its tab in the guild window too", function()
		Mock.communities.Open()
		Tab().tab:Click()
		for _, dest in ipairs(rail().order) do
			item(dest):Click()
			for _, p in ipairs(Shell():PageList(dest)) do
				Shell():Select(p.key, true)
				local view = Shell().views[p.view]
				truthy(view.frame:IsVisible(), p.key)
				eq(view.frame:GetParent(), Shell().content.body)
			end
		end
		eq(#Mock.errors, 0)
	end)

	it("a view that fails shows its error text; a click on its tab tries again", function()
		Shell().views = {}
		local fail = true
		Shell():RegisterView("roster", { label = "Roster", order = 1, build = function() end })
		Shell():RegisterView("reputation", { label = "Reputation", order = 4, build = function(f) if fail then error("broken") end end })
		Mock.Slash("/accord reputation")
		local frame = Shell().views.reputation.frame
		eq(frame.errorTitle:GetText(), "This view could not be drawn")
		contains(frame.errorText:GetText(), "clicking its tab again tries again")
		Mock.ClearErrors()   -- the error went to the game's handler, as it should
		fail = false
		Shell().content.tabs.buttons.reputation:Click()
		isNil(Shell().views.reputation.failed)
		truthy(Shell().views.reputation.frame ~= frame)
	end)

	it("a view's badge is on its tab, the sum of its destination's on the rail, and goes away at 0", function()
		Shell().views = {}
		local n, m = 3, 2
		Shell():RegisterView("roster", { label = "Roster", order = 1, build = function() end })
		Shell():RegisterView("reputation", { label = "Reputation", order = 2, build = function() end, badge = function() return m end })
		Shell():RegisterView("bank", { label = "Bank", order = 4, build = function() end, badge = function() return n end })
		Mock.Slash("/accord roster")
		local tabs = Shell().content.tabs
		eq(tabs.buttons.reputation.label:GetText(), "Reputation", "the count is a badge, not part of the label")
		eq(tabs.buttons.reputation.badge.label:GetText(), "2")
		isNil(tabs.buttons.roster.badge)
		eq(item("economy").badge.label:GetText(), "3")
		eq(item("guild").badge.label:GetText(), "2")
		eq(item("guild").badge.tone, "err", "the M3 badge")
		m, n = 4, 0
		Shell():UpdateBadges()
		eq(item("guild").badge.label:GetText(), "4")
		falsy(item("economy").badge:IsShown())
		n = 250
		Shell():UpdateBadges()
		eq(item("economy").badge.label:GetText(), "99+")
		eq(Shell().BadgeText({ badge = function() error("x") end }), nil, "a badge that raises shows nothing")
	end)

	it("a page's own badge: the applicants on My group, the open manual actions on Queue", function()
		Mock.Slash("/accord")
		local groups = Shell().views.groups
		local list = groups.pageBadge
		eq(type(list), "function")
		eq(list("list"), 0)
		eq(type(Shell().views.officers.pageBadge), "function")
		eq(type(Shell().views.actions.pageBadge), "function")
	end)

	it("the sync state and Ago", function()
		Mock.Slash("/accord")
		eq(Shell().content.status:GetText(), "0 guildmate(s) with Accord online · no data received yet")
		eq(Win().frame.titleBar.subtitle:GetText(), Shell().content.status:GetText())
		eq(Shell().Ago(30), "just now")
		eq(Shell().Ago(120), "2 min ago")
		eq(Shell().Ago(7200), "2 h ago")
		eq(Shell().Ago(3 * 86400), "3 d ago")
	end)

	it("in Italian: the rail, the row, title bar and search box", function()
		T.boot(function(M) M.player.locale = "itIT" guild() end)
		Mock.communities.Open()
		Tab().tab:Click()
		local content = Shell().content
		eq(content.rail.items.settings.name, "Impostazioni")
		eq(content.rail.items.guild.name, "Gilda")
		Shell():OpenView("settings")
		eq(content.bar.title:GetText(), "Impostazioni")
		eq(content.tabs.buttons["settings:settings"].label:GetText(), "Generali")
		eq(content.bar.searchField.placeholder:GetText(), "Cerca")
		eq(content.bar.popOut:GetLabel(), "Stacca")
		content.bar.popOut:Click()
		eq(Win().frame.titleBar.popIn:GetLabel(), "Riaggancia")
		eq(Win().frame.titleBar.title:GetText(), "AZEROTH ACCORD")
	end)
end)

describe("a theme change repaints the shell without /reload", function()
	before_boot(function(M) guild() end)

	it("window, title bar, tabs, status and the guild panel follow Theme.Apply", function()
		local Th = A().Theme
		Mock.communities.Open()
		Mock.Slash("/accord")
		local f, content = Win().frame, Shell().content
		local function r(tex) return (tex:GetVertexColor()) end
		eq(r(f.parts.fill), (Th.Color("bg", "nebula")))
		eq(r(f.titleBar.fill), (Th.Color("surface-1", "nebula")))
		eq(content.tabs.indicator.middle._texture[1], (Th.Color("accent", "nebula")))
		for _, id in ipairs({ "aurora", "accord" }) do
			truthy(Th.Apply(id))
			eq(r(f.parts.fill), (Th.Color("bg", id)), id .. " window fill")
			eq(r(f.titleBar.fill), (Th.Color("surface-1", id)), id .. " title bar")
			eq(content.tabs.indicator.middle._texture[1], (Th.Color("accent", id)), id .. " indicator")
			eq((content.tabs.buttons[content.tabs:Active()].label:GetTextColor()), (Th.Color("accent-text", id)), id .. " active tab (orange, 2026-11-27)")
			eq((content.status:GetTextColor()), (Th.Color("text-3", id)), id .. " status")
			eq((content.bar.searchField.fill:GetVertexColor()), (Th.Color("surface-2", id)), id .. " search box")
			eq(Tab().panel.fill._texture[1], (Th.Color("bg", id)), id .. " guild panel")
		end
		eq(#Mock.errors, 0)
	end)
end)

describe("the diagnostics box", function()
	before_boot(function(M) guild() end)

	it("/accord debug opens the report, selected and read-only", function()
		Mock.Slash("/accord debug")
		local box = A().DiagnosticsBox
		truthy(box:IsShown())
		contains(box:GetText(), "Azeroth Accord diagnostics")
		contains(box:GetText(), "== Guild tab ==")
		Mock.TypeInto(box.frame.edit, "typed")
		eq(box.frame.edit:GetText(), box:GetText(), "typing is undone")
		box.frame.close:Click()
		falsy(box:IsShown())
		contains(table.concat(UISpecialFrames, ","), "AzerothAccordDiagnosticsBox")
	end)
end)

describe("more pages than the row has room for (M9.10; the Guild destination, M13.7)", function()
	before_boot(function(M) guild() end)

	-- The mock measures a text at 6 points a letter and knows no anchored width: the width of the bar is given here.
	local function open(width)
		Mock.Slash("/accord roster")
		local tabs = Shell().content.tabs
		tabs:SetWidth(width)
		tabs:Layout()
		return tabs
	end

	local function onBar(tabs)
		local list = {}
		for _, id in ipairs(tabs.order) do if tabs.buttons[id]:IsShown() then list[#list + 1] = id end end
		return list
	end

	local function rightEnd(tabs)
		local right = 0
		for _, id in ipairs(onBar(tabs)) do right = math.max(right, tabs.buttons[id].x + tabs.buttons[id].w) end
		if tabs.more and tabs.more:IsShown() then right = math.max(right, tabs.more.x + tabs.more.w) end
		return right
	end

	it("shows every page of the destination when there is room, and no More tab", function()
		local tabs = open(2000)
		deepEq(tabs.order, { "roster", "reputation", "mentors", "addons" })
		deepEq(onBar(tabs), tabs.order)
		isNil(tabs.more)
	end)

	it("puts what does not fit into the More menu, beside the search box and never over it", function()
		local tabs = open(400)
		truthy(tabs.more:IsShown())
		eq(tabs.more.label:GetText(), "More")
		eq(#onBar(tabs) + #tabs.overflow, #tabs.order)
		truthy(#tabs.overflow > 0)
		truthy(rightEnd(tabs) <= 400 - Shell().TabReserve(Shell().content), "ends before the search box")
	end)

	it("every view without room opens from the menu and takes its place on the bar", function()
		local tabs = open(400)
		local hidden = {}
		for i, id in ipairs(tabs.overflow) do hidden[i] = id end
		for _, id in ipairs(hidden) do
			tabs.more:Click()
			local menu = A().Widgets.Menu
			truthy(menu.IsOpen())
			local row
			for i, item in ipairs(menu.frame.items) do if item.id == id then row = menu.frame.rows[i] end end
			notNil(row, id .. " is in the menu")
			row:Click()
			falsy(menu.IsOpen())
			eq(Shell().selected, id)
			eq(tabs:Active(), id)
			truthy(tabs.buttons[id]:IsShown(), id .. " is on the bar while open")
			truthy(Shell().views[id].frame:IsVisible(), id)
			truthy(rightEnd(tabs) <= 400 - Shell().TabReserve(Shell().content), id)
		end
		eq(#Mock.errors, 0)
	end)

	it("adds up the counts of the tabs behind More", function()
		local tabs = open(400)
		local last, before = tabs.order[#tabs.order], tabs.overflow[#tabs.overflow - 1]
		eq(last, "addons")
		tabs:SetBadge(last, "2")
		tabs:SetBadge(before, "3")
		eq(tabs.more.badge.label:GetText(), "5")
		tabs:SetBadge(last, "99+")
		eq(tabs.more.badge.label:GetText(), "99+")
		tabs:SetBadge(last, nil)
		tabs:SetBadge(before, nil)
		falsy(tabs.more.badge:IsShown())
	end)

	it("keeps the room when the window grows or shrinks, and says Altro in Italian", function()
		local tabs = open(400)
		tabs:SetWidth(2000)
		tabs:GetScript("OnSizeChanged")(tabs, 2000, 44)
		falsy(tabs.more:IsShown())
		eq(#onBar(tabs), #tabs.order)
		T.boot(function(M) M.player.locale = "itIT" guild() end)
		eq(open(400).more.label:GetText(), "Altro")
	end)
end)

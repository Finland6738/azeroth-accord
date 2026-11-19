-- The Accord tab, the panel and the standalone window (M1.8; SPEC-04, ADR 0003) on the mock guild window
-- (Tests/mock/85_communities.lua). GT-01..GT-06 of SPEC-04 §1 each have a group below.
local function A() return AzerothAccord end
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

	it("has the Accord icon and the Azeroth Accord tooltip", function()
		Mock.communities.Open()
		eq(Tab().tab.accordIcon:GetTexture(), "Interface\\Icons\\INV_Shirt_GuildTabard_01")
		Mock.RunScript(Tab().tab, "OnEnter")
		truthy(GameTooltip:IsShown())
		eq(GameTooltip:GetText(), "Azeroth Accord")
		Mock.RunScript(Tab().tab, "OnLeave")
		falsy(GameTooltip:IsShown())
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

describe("GT-02: when the tab shows", function()
	before_boot(function(M) guild() end)

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
	before_boot(function(M) guild() end)

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
		local _, inset = Tab().panel:GetPoint(1)
		eq(inset, CommunitiesFrame.Inset)
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
		for _, file in ipairs({ "AzerothAccord/UI/GuildTab.lua", "AzerothAccord/UI/Shell.lua", "AzerothAccord/UI/Window.lua" }) do
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

	it("a template the client lacks falls back to a plain button", function()
		T.boot(function(M)
			guild()
			local create = CreateFrame
			CreateFrame = function(kind, name, parent, template)
				if template == "CommunitiesFrameTabTemplate" and name == "AzerothAccordGuildTab" then error("Couldn't find inherited node") end
				return create(kind, name, parent, template)
			end
		end)
		Mock.communities.Open()
		notNil(Tab().tab)
		ne(Tab().template, "CommunitiesFrameTabTemplate")
	end)
end)

describe("GT-06: combat", function()
	before_boot(function(M) guild() end)

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

describe("the standalone window (SPEC-04 §3)", function()
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

	it("says so without a guild and opens nothing", function()
		T.boot(function(M) M.guild.Leave() end)
		Mock.Slash("/accord")
		falsy(Win():IsShown())
		contains(text(), "You are not in a guild.")
	end)

	it("closes with Esc and when the character leaves the guild", function()
		Mock.Slash("/accord")
		contains(table.concat(UISpecialFrames, ","), "AzerothAccordWindow")
		Mock.guild.Leave()
		falsy(Win():IsShown())
	end)

	it("remembers where it was and how big", function()
		Mock.Slash("/accord")
		local f = Win().frame
		Mock.Drag(f, "TOPLEFT", 100, -80)
		f:SetSize(900, 600)
		Mock.RunScript(f.grip, "OnMouseUp")
		Mock.Reload()
		Mock.Slash("/accord")
		local point, _, _, x, y = Win().frame:GetPoint(1)
		eq(point, "TOPLEFT"); eq(x, 100); eq(y, -80)
		eq(Win().frame:GetWidth(), 900)
		Win():ResetPosition()
		eq(Win().frame:GetWidth(), 820)
	end)

	it("pop out moves the panel from the guild window to the window", function()
		Mock.communities.Open()
		Tab().tab:Click()
		truthy(Shell().content.bar.popOut:IsShown())
		Shell().content.bar.popOut:Click()
		falsy(Tab():IsPanelShown())
		truthy(Win():IsShown())
		eq(Shell().content:GetParent(), Win().frame.body)
		-- and back: the tab takes the panel from the window
		Tab().tab:Click()
		eq(Shell().content:GetParent(), Tab().panel)
	end)

	it("the Compartment tooltip has the title, the hint and the sync state", function()
		AzerothAccord_OnAddonCompartmentEnter(nil, UIParent)
		local lines = GameTooltip._lines or {}
		contains(table.concat(lines, "\n"), "Click to open or close the Accord window.")
		contains(table.concat(lines, "\n"), "guildmate(s) with Accord online")
	end)
end)

describe("navigation and views (SPEC-04 §2)", function()
	before_boot(function(M) guild() end)

	it("shows no navigation and the welcome text while no view exists; view commands say coming soon", function()
		Shell().views = {}   -- the Roster view of M2.3 registers itself: here no view exists
		Mock.Slash("/accord")
		falsy(Shell().content.nav:IsShown())
		falsy(Shell().content.bar.search:IsShown(), "no search before a view can search")
		Mock.ClearOutput()
		Mock.Slash("/accord professions")
		contains(text(), "coming soon")
	end)

	it("a registered view gets a button, opens with its command and is remembered", function()
		local built = {}
		Shell():RegisterView("roster", { label = "Roster", order = 1, search = true, build = function(f) built.roster = f end })
		Shell():RegisterView("bank", { label = "Bank", order = 4, build = function(f) built.bank = f end })
		Mock.Slash("/accord bank")
		truthy(Win():IsShown())
		truthy(Shell().content.nav:IsShown())
		eq(Shell().content.nav.buttons[1].label:GetText(), "Roster")
		eq(Shell().content.nav.buttons[2].label:GetText(), "Bank")
		notNil(built.bank)
		isNil(built.roster, "a view is built when first shown")
		falsy(Shell().content.empty:IsShown())
		truthy(Shell().content.bar.search:IsShown())
		Shell().content.nav.buttons[1]:Click()
		notNil(built.roster)
		eq(AzerothAccordCharDB.ui.lastView, "roster")
	end)

	it("the top bar shows the sync state", function()
		Mock.Slash("/accord")
		eq(Shell().content.bar.status:GetText(), "0 guildmate(s) with Accord online · no data received yet")
		eq(Shell().Ago(30), "just now")
		eq(Shell().Ago(120), "2 min ago")
		eq(Shell().Ago(7200), "2 h ago")
		eq(Shell().Ago(3 * 86400), "3 d ago")
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

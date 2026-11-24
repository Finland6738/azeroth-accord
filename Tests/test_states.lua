-- Empty, loading and error states (M6.3): every view says what is going on when there is nothing to show, and a client
-- that lacks APIs, or a view that raises, never takes the panel down. Plus the memory line of /accord debug.
local function A() return AzerothAccord end

-- Every text a frame shows right now (shown font strings of shown frames, depth first).
local function shownTexts(frame, out)
	out = out or {}
	if not frame:IsShown() then return out end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetText and region:IsShown() then
			local t = region:GetText()
			if type(t) == "string" and t ~= "" then out[#out + 1] = t end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do shownTexts(child, out) end
	return out
end

local function viewText(id)
	A().Shell:OpenView(id)
	Mock.Advance(2)
	local view = A().Shell.views[id]
	return table.concat(shownTexts(view.frame), "\n")
end

describe("a guild whose roster has not loaded yet", function()
	before_boot(function()
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {} }
		GetNumGuildMembers = function() return 0, 0, 0 end   -- the client has not sent the roster yet
		GetGuildRosterInfo = function() return nil end
	end)

	it("the Roster says it is waiting for the roster, not an empty table", function()
		contains(viewText("roster"), "The guild roster is not loaded yet.")
	end)

	it("Reputation says so, Bank explains how its data arrives, Professions explains what to type", function()
		contains(viewText("reputation"), "The guild roster is not loaded yet.")
		contains(viewText("bank"), "No bank data yet")
		matches(viewText("professions"), "Type the name of an item or a recipe")
	end)

	it("the Bank log, donations, money and requests each explain why they are empty", function()
		A().Shell:OpenView("bank")
		local View = A().BankView
		local function mode(name)
			View:SetMode(name)
			Mock.Advance(1)
			return table.concat(shownTexts(A().Shell.views.bank.frame), "\n")
		end
		contains(mode("log"), "No log yet")
		contains(mode("donations"), "No deposits in this period yet.")
		contains(mode("money"), "No money history yet")
		contains(mode("requests"), "No open requests.")
	end)

	it("every view and the report open without a Lua error", function()
		for _, id in ipairs({ "roster", "professions", "reputation", "bank", "raid", "settings" }) do viewText(id) end
		Mock.Slash("/accord debug")
		eq(#Mock.errors, 0)
	end)
end)

describe("a client that lacks the optional APIs", function()
	local GONE = { "C_Club", "C_Spell", "C_TradeSkillUI", "C_GuildInfo", "C_Item", "GetGuildBankTabInfo", "GetGuildBankMoney",
		"BNGetInfo", "BNet_GetBattleTagSelf", "C_PartyInfo", "GetRaidRosterInfo", "UnitGUID", "GetItemInfo", "C_AddOns" }

	before_boot(function(M)
		M.guild.Set{ name = "Accord", myRank = 1, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = "Player-1-00000B0B" },
		} }
		for _, name in ipairs(GONE) do _G[name] = nil end
	end)

	it("opens every view, the member card, the report and the Settings page without a Lua error", function()
		for _, id in ipairs({ "roster", "professions", "reputation", "bank", "raid", "settings" }) do
			truthy(A().Shell:OpenView(id), id)
			Mock.Advance(2)
		end
		A().Shell:OpenView("roster")
		local rows = A().RosterView.frame.table.rows
		for _, r in ipairs(rows) do if r:IsShown() then r:Click() break end end
		Mock.Advance(1)
		Mock.Slash("/accord debug")
		contains(A().DiagnosticsBox:GetText(), "== Saved data ==")
		eq(#Mock.errors, 0, "errors: " .. table.concat((function() local t = {} for i, e in ipairs(Mock.errors) do t[i] = tostring(e) end return t end)(), " | "))
	end)

	it("the report still lists the sections", function()
		Mock.Slash("/accord debug")
		local text = A().DiagnosticsBox:GetText()
		contains(text, "== Sending ==")
		contains(text, "== Last errors ==")
	end)
end)

describe("a view that raises while it is built", function()
	before_boot(function() Mock.guild.Set{ name = "Accord", myRank = 3, members = {} } end)

	local function register()
		A().Shell:RegisterView("broken", { label = "Broken", order = 95, build = function() error("boom in AzerothAccord view") end })
	end

	it("shows an error text in that view only, keeps the panel and the other views, and records the error", function()
		register()
		Mock.ClearErrors()
		truthy(A().Shell:OpenView("broken"))
		local view = A().Shell.views.broken
		notNil(view.failed)
		contains(table.concat(shownTexts(view.frame), "\n"), "This view could not be drawn")
		contains(table.concat(shownTexts(view.frame), "\n"), "/accord debug")
		contains(A().Diagnostics.Report(), "boom in AzerothAccord view")
		eq(#Mock.errors, 1, "the error went to the game's error handler once")
		Mock.ClearErrors()
		-- the others still open
		truthy(A().Shell:OpenView("roster"))
		contains(viewText("roster"), "members")
	end)

	it("selecting the view again builds it afresh, and a view that works then shows normally", function()
		local fail = true
		local built = 0
		A().Shell:RegisterView("flaky", { label = "Flaky", order = 96, build = function(f)
			built = built + 1
			if fail then error("first try fails in AzerothAccord") end
			local t = f:CreateFontString(nil, "OVERLAY")
			t:SetText("It works now")
		end })
		Mock.ClearErrors()
		A().Shell:OpenView("flaky")
		eq(built, 1)
		notNil(A().Shell.views.flaky.failed)
		fail = false
		Mock.ClearErrors()
		A().Shell:Select("roster")
		A().Shell:Select("flaky", true)
		eq(built, 2)
		isNil(A().Shell.views.flaky.failed)
		contains(table.concat(shownTexts(A().Shell.views.flaky.frame), "\n"), "It works now")
		falsy(table.concat(shownTexts(A().Shell.views.flaky.frame), "\n"):find("could not be drawn", 1, true))
	end)

	it("the text is Italian in an Italian client", function()
		T.boot(function(M)
			M.player.locale = "itIT"
			M.guild.Set{ name = "Accord", myRank = 3, members = {} }
		end)
		A().Shell:RegisterView("broken", { label = "Rotta", order = 95, build = function() error("boom in AzerothAccord view") end })
		A().Shell:OpenView("broken")
		contains(table.concat(shownTexts(A().Shell.views.broken.frame), "\n"), "Non è stato possibile disegnare questa vista")
		Mock.ClearErrors()
	end)
end)

describe("the memory line of /accord debug", function()
	before_boot(function() Mock.guild.Set{ name = "Accord", myRank = 3, members = {} } end)

	it("gives the game's figure for the addon", function()
		Mock.player.addonMemory = 3072
		eq(A().Compat.Addon.MemoryKB(), 3072)
		Mock.Slash("/accord debug")
		contains(A().DiagnosticsBox:GetText(), "Memory: about 3.0 MB in use by the addon")
	end)

	it("says unknown when the game gives none, or the call is missing", function()
		Mock.player.addonMemory = false
		isNil(A().Compat.Addon.MemoryKB())
		Mock.Slash("/accord debug")
		contains(A().DiagnosticsBox:GetText(), "Memory: unknown")
		GetAddOnMemoryUsage = nil
		isNil(A().Compat.Addon.MemoryKB())
		eq(#Mock.errors, 0)
	end)
end)

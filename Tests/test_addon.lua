-- The addon as a whole (M1.2): loading in TOC order, the Forever check, the slash commands and the /reload round trip
-- of the SavedVariables. Adapted from Azeroth Guild Finder (Tests/test_addon.lua), same owner, GPL-3.0 (ADR 0018).
-- `Mock` is the fake client; the game's globals (AzerothAccord, LibStub, ...) are plain globals here too. Read them
-- inside the test, not at the top of the file: every test boots a fresh client.

describe("loading", function()
	it("loads every TOC file in order without a Lua error", function()
		eq(#Mock.errors, 0)
		local order = {}
		for i, name in ipairs(Mock.loadedFiles) do order[name] = i end
		local libStub = order["AzerothAccord/Libs/Ace3/LibStub/LibStub.lua"]
		local aceAddon = order["AzerothAccord/Libs/Ace3/AceAddon-3.0/AceAddon-3.0.lua"]
		local english = order["AzerothAccord/Locale/enUS.lua"]
		local italian = order["AzerothAccord/Locale/itIT.lua"]
		local init = order["AzerothAccord/Core/Init.lua"]
		truthy(libStub and aceAddon and english and italian and init, "the libraries, locales and Init were loaded")
		truthy(libStub < aceAddon and aceAddon < english and english < italian and italian < init, "TOC order is kept")
	end)

	it("creates the addon object and enables it at login", function()
		local ACC = LibStub("AceAddon-3.0"):GetAddon("AzerothAccord")
		eq(ACC, AzerothAccord)
		truthy(ACC:IsEnabled(), "enabled after PLAYER_LOGIN")
	end)

	it("recognises Forever and stays quiet", function()
		truthy(AzerothAccord:IsForever())
		eq(#Mock.output, 0, "nothing printed at login")
	end)

	it("warns when the client is not Forever", function()
		-- the setup runs after the mock client is built and before the addon's files load
		T.boot(function() WOW_PROJECT_ID = WOW_PROJECT_MAINLINE end)
		falsy(AzerothAccord:IsForever())
		contains(table.concat(Mock.PlainOutput(), "\n"), "built for WoW Forever")
	end)

	it("falls back to the Interface number when the project constants are missing", function()
		T.boot(function() WOW_PROJECT_ID, WOW_PROJECT_CAMELOT = nil, nil end)
		truthy(AzerothAccord:IsForever(), "interface 16001 counts as Forever")
	end)

	it("speaks Italian in an Italian client", function()
		T.boot(function(M) M.player.locale = "itIT" end)
		Mock.Slash("/accord help")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Comandi:")
	end)
end)

describe("slash commands", function()
	it("/accord help prints every command", function()
		truthy(Mock.Slash("/accord help"))
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Commands:")
		for _, command in ipairs({ "/accord roster", "/accord professions", "/accord reputation", "/accord bank",
			"/accord debug", "/accord help" }) do
			contains(text, command)
		end
	end)

	it("/acc is an alias of /accord", function()
		truthy(Mock.Slash("/acc help"))
		contains(table.concat(Mock.PlainOutput(), "\n"), "Commands:")
	end)

	it("an unknown command is reported and the help follows", function()
		Mock.Slash("/accord frobnicate")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Unknown command 'frobnicate'")
		contains(text, "Commands:")
	end)

	it("a command with no handler yet says so", function()
		local commands = AzerothAccord.commands
		commands[#commands + 1] = { name = "later", help = "not there yet" }
		Mock.Slash("/accord later")
		contains(table.concat(Mock.PlainOutput(), "\n"), "coming soon")
	end)

	it("the key binding and the AddOn Compartment entry points exist", function()
		eq(type(AzerothAccord_ToggleBinding), "function")
		eq(type(AzerothAccord_OnAddonCompartmentClick), "function")
		eq(BINDING_HEADER_AZACCORD, "Azeroth Accord")
		AzerothAccord_OnAddonCompartmentEnter(nil, UIParent)
		truthy(GameTooltip:IsShown())
		AzerothAccord_OnAddonCompartmentLeave()
		falsy(GameTooltip:IsShown())
	end)
end)

describe("/reload", function()
	it("passes SavedVariables from one run to the next", function()
		AzerothAccordDB = { counter = 1, nested = { "a", "b" } }
		AzerothAccordCharDB = { seen = true }
		Mock.Reload()
		-- Config merges its defaults around the test values (from M1.4); the values themselves are kept
		eq(AzerothAccordDB.counter, 1)
		deepEq(AzerothAccordDB.nested, { "a", "b" })
		eq(AzerothAccordCharDB.seen, true)
		AzerothAccordDB.counter = AzerothAccordDB.counter + 1
		Mock.Reload()
		eq(AzerothAccordDB.counter, 2)
	end)

	it("rebuilds the Lua state: values that are not saved are gone", function()
		AzerothAccordDB = { kept = "yes" }
		SomeRuntimeValue = "lost"
		local before = AzerothAccord
		Mock.Reload()
		isNil(SomeRuntimeValue)
		ne(AzerothAccord, before, "a new addon object")
		eq(AzerothAccordDB.kept, "yes")
		eq(#Mock.errors, 0)
	end)

	it("keeps the world: clock, player and guild", function()
		Mock.guild.Set({ name = "Keepers", myRank = 2 })
		Mock.Advance(30)
		local now = GetTime()
		Mock.Reload()
		eq(GetTime(), now)
		eq(GetGuildInfo("player"), "Keepers")
	end)

	it("the slash commands work again after a reload", function()
		Mock.Reload()
		Mock.ClearOutput()
		truthy(Mock.Slash("/accord help"))
		contains(table.concat(Mock.PlainOutput(), "\n"), "Commands:")
	end)

	it("fires PLAYER_LOGOUT first and PLAYER_ENTERING_WORLD with isReloadingUi after", function()
		local seen = {}
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("PLAYER_LOGOUT")
		frame:SetScript("OnEvent", function(_, event) seen[#seen + 1] = event end)
		AzerothAccordDB = {}
		Mock.Reload()
		deepEq(seen, { "PLAYER_LOGOUT" })
		local reloading
		local f2 = CreateFrame("Frame")
		f2:RegisterEvent("PLAYER_ENTERING_WORLD")
		f2:SetScript("OnEvent", function(_, _, isInitialLogin, isReloadingUi) reloading = isReloadingUi end)
		Mock.Fire("PLAYER_ENTERING_WORLD", false, true)
		eq(reloading, true)
	end)

	it("refuses SavedVariables the client could not store", function()
		AzerothAccordDB = { handler = function() end }
		local err = raises(function() Mock.Reload() end)
		contains(err, "cannot be saved")
	end)
end)

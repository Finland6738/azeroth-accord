-- Diagnostics (M1.3): the report of `/accord debug` (Core/Diagnostics.lua): its sections, the absence of names and the
-- error ring buffer. Adapted from Azeroth Guild Finder (Tests/test_diagnostics.lua), same owner, GPL-3.0 (ADR 0018).
local function A() return AzerothAccord end
local function D() return A().Diagnostics end

local function report() return D().Report() end
local function sectionTitles(text)
	local titles = {}
	for title in text:gmatch("\n== ([^\n]-) ==") do titles[#titles + 1] = title end
	return titles
end
local function has(list, value) for _, v in ipairs(list) do if v == value then return true end end return false end

describe("the report", function()
	it("starts with the addon, client and interface versions", function()
		local text = report()
		contains(text, "Azeroth Accord diagnostics")
		contains(text, "addon: ")
		contains(text, "client: ")
		contains(text, "interface: 16001")
		contains(text, "project id: ")
	end)

	it("has the sending, errors and Compat sections", function()
		local titles = sectionTitles(report())
		for _, wanted in ipairs({ "Sending", "Last errors", "Compat" }) do
			truthy(has(titles, wanted), "missing section " .. wanted)
		end
		contains(report(), "Features:")
	end)

	it("Format is plain data to text and needs no client", function()
		local text = D().Format({ header = { "h1", "h2" }, sections = { { title = "A", lines = { "a1", "a2" } }, { title = "B", lines = {} } } })
		eq(text, "h1\nh2\n\n== A ==\na1\na2\n\n== B ==")
	end)

	it("reports a failing section instead of raising", function()
		A():AddDebugSection("Broken", function() error("boom") end)
		local text = report()
		contains(text, "== Broken ==")
		contains(text, "error: ")
	end)

	it("/accord debug prints the report in the chat while there is no copy box", function()
		Mock.ClearOutput()
		Mock.Slash("/accord debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Azeroth Accord diagnostics")
		contains(text, "== Compat ==")
	end)
end)

describe("no names in the report", function()
	local NAMES = { "Jaina", "Garrosh", "Frostwolves", "Hero#1234", "jaina_discord" }

	it("holds no player, guild, BattleTag or Discord name", function()
		Mock.player.battleTag = "Hero#1234"
		Mock.club.fill.professions, Mock.club.fill.discord = true, true
		Mock.guild.Set{ name = "Frostwolves", myRank = 0, members = { { name = "Jaina", rank = 1, discord = "jaina_discord" }, { name = "Garrosh", rank = 3 } } }
		A().Compat:Probe()
		local text = report()
		for _, name in ipairs(NAMES) do
			falsy(text:find(name, 1, true), "the report contains " .. name)
		end
	end)

	it("holds neither the character's name nor the realm", function()
		local text = report()
		local name = UnitName("player")
		truthy(name and name ~= "")
		falsy(text:find(name, 1, true), "the report contains the character name")
		local realm = GetRealmName and GetRealmName()
		if realm and realm ~= "" then falsy(text:find(realm, 1, true), "the report contains the realm") end
	end)
end)

describe("the error ring buffer", function()
	it("is empty at first and the report says so", function()
		eq(#D().Errors(), 0)
		contains(report(), "no addon errors recorded this session")
	end)

	it("keeps an error without the player's folders", function()
		D().Record("C:\\Games\\WoW\\_classic_\\Interface\\AddOns\\AzerothAccord\\Net\\Sync.lua:12: attempt to index nil")
		eq(D().Errors()[1].text, "AzerothAccord/Net/Sync.lua:12: attempt to index nil")
		D().Record("D:\\Users\\SomeOne\\Documents\\x.lua:3: bad")
		falsy(D().Errors()[2].text:find("SomeOne", 1, true))
		falsy(D().Errors()[2].text:find("D:", 1, true))
		D().Record("/ho" .. "me/someone/wow/Interface/AddOns/AzerothAccord/UI/Main.lua:9: bad")
		falsy(D().Errors()[3].text:find("someone", 1, true))
		contains(report(), "Sync.lua:12")
		falsy(report():find("Games", 1, true))
	end)

	it("counts the same error repeated and keeps one line", function()
		for _ = 1, 5 do D().Record("AzerothAccord/Data/Catalog.lua:1: boom") end
		eq(#D().Errors(), 1)
		eq(D().Errors()[1].count, 5)
		contains(report(), "x5 AzerothAccord/Data/Catalog.lua:1: boom")
	end)

	it("keeps the latest ten, dropping the oldest", function()
		for i = 1, 14 do D().Record("AzerothAccord: error number " .. i) end
		eq(#D().Errors(), D().MAX_ERRORS)
		eq(D().Errors()[1].text, "AzerothAccord: error number 5")
		eq(D().Errors()[10].text, "AzerothAccord: error number 14")
		eq(D().ErrorLines()[1], "AzerothAccord: error number 14")   -- latest first
	end)

	it("cuts a long error and drops its newlines", function()
		D().Record("AzerothAccord: " .. ("x"):rep(1000) .. "\nsecond line")
		local text = D().Errors()[1].text
		truthy(#text <= D().MAX_LENGTH)
		falsy(text:find("\n", 1, true))
		D().ClearErrors()
		D().Record("AzerothAccord: first\nsecond")
		contains(D().Errors()[1].text, "first | second")
	end)

	it("catches only this addon's errors through the game's error handler and passes them on", function()
		local handler = geterrorhandler()
		handler("Interface\\AddOns\\AzerothAccord\\Core\\Bus.lua:5: listener failed")
		handler("Interface\\AddOns\\SomeOtherAddon\\x.lua:5: not ours")
		eq(#D().Errors(), 1)
		eq(D().Errors()[1].text, "AzerothAccord/Core/Bus.lua:5: listener failed")
		eq(#Mock.errors, 2, "both errors went on to the game's handler")
		Mock.ClearErrors()
	end)
end)

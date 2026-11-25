-- The feature switches (Core/Features.lua): with "raid" off, as every release ships it, nothing of M10.2 and M11.7 is
-- visible, no FDCP callback is registered and nothing of it is written or sent, even with FDCP loaded and a guild
-- choice of FDCP left over from a development build. The switches of M9 (actions, groups, census) are on since M9.10:
-- their features are there with the shipped code, and each switch still hides its own when a test turns it off.
local function A() return AzerothAccord end

local FOLDER, GLOBAL = "FinlandDragonCreditPoints", "FinlandDragonCreditPointsAPI"
local OFF, BOB = "Player-1-000000FF", "Player-1-00000B0B"

local function fake()
	local f = { calls = 0 }
	f.api = setmetatable({}, { __index = function(_, k)
		f.calls = f.calls + 1
		if k == "API_VERSION" then return 1 end
		return function() f.calls = f.calls + 1 return true end
	end })
	return f
end

local function withFDCP(M)
	M.guild.Set{ name = "Accord", myRank = 1, members = {
		{ name = "Officer", rank = 1, guid = OFF }, { name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
	} }
	M.addons[FOLDER] = { loaded = true, version = "1.0.2" }
end

local function leftover()
	local records = A().Store:Records("guildcfg")
	records.sources = { id = "sources", author = OFF, rev = 1, time = GetServerTime(), raid = "fdcp", loot = "fdcp" }
end

describe("the raid switch, off", function()
	before_boot(withFDCP)

	it("is off in the shipped code", function()
		eq(A().Features.raid, false)
		falsy(A().Features.On("raid"))
		falsy(A().Features.On("unknown"))
	end)

	it("has no Raid view and no Raid tab", function()
		Mock.Slash("/accord")
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "raid") end
		isNil(A().Shell.content.tabs.buttons.raid)
		falsy(A().Shell:Select("raid"))
		falsy(A().Shell:OpenView("raid"))
		isNil(A().RaidView.frame)
	end)

	it("falls back to another view when the last one saved was the Raid view", function()
		A().Config:Set("char.ui.lastView", "raid")
		Mock.Slash("/accord")
		eq(A().Shell.selected, "actions", "the first tab")
	end)

	it("has no /accord raid command, in the help or when typed", function()
		Mock.Slash("/accord help")
		local help = table.concat(Mock.PlainOutput(), "\n")
		contains(help, "/accord bank")
		falsy(help:find("/accord raid", 1, true))
		Mock.Slash("/accord raid")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Unknown command 'raid'")
		isNil(A().RaidView.frame)
	end)

	it("adds no Loot (FDCP) row to the member card", function()
		FinlandDragonCreditPointsAPI = fake().api
		leftover()
		local entry = A().Roster:ByGUID(BOB)
		notNil(entry)
		isNil(A().RaidView.CardSection(entry))
	end)

	it("detects nothing, calls nothing of FDCP and registers no callback", function()
		local f = fake()
		boot(function(M)
			withFDCP(M)
			FinlandDragonCreditPointsAPI = f.api
		end)
		leftover()
		Mock.Fire("ADDON_LOADED", FOLDER)
		A().Bus:Emit("SOURCES_CHANGED")
		A().Bus:Emit("INTEGRATIONS_CHANGED")
		Mock.Advance(5)
		eq(f.calls, 0)
		isNil(A().FDCP.watching)
		eq(A().FDCP.stats.registered, 0)
	end)

	it("takes no guild setting for the sources, local or received, and counts none", function()
		local ok, why = A().Integrations:SetSource("raid", "fdcp")
		falsy(ok); eq(why, "off")
		falsy(A().Store.IsActive("guildcfg"))
		local rec = { id = "sources", author = OFF, rev = 1, time = GetServerTime(), raid = "fdcp", loot = "fdcp" }
		ok, why = A().Store:Accept("guildcfg", rec, { sender = "Officer" })
		falsy(ok); eq(why, "set")
		isNil((A().Store:Put("guildcfg", "sources", { raid = "fdcp", loot = "fdcp" })))
		isNil(A().Store:Get("guildcfg", "sources"))
	end)

	it("shows nothing of it in /accord debug: no section of its own, no set in the store line", function()
		A().Integrations:Refresh()
		for _, section in ipairs(A().Diagnostics.Collect().sections) do
			truthy(section.title ~= "Integrations" and section.title ~= "FDCP", section.title)
		end
		falsy(table.concat(A().Store:DebugLines(), " "):find("guildcfg", 1, true))
	end)
end)

describe("the raid switch, on", function()
	before_boot(function(M)
		withFDCP(M)
		M.features = { raid = true }
	end)

	it("brings the view, the command and the debug sections back, through a /reload too", function()
		Mock.Reload()
		truthy(A().Features.On("raid"))
		truthy(A().Shell:OpenView("raid"))
		eq(A().Shell.selected, "raid")
		Mock.Slash("/accord help")
		contains(table.concat(Mock.PlainOutput(), "\n"), "/accord raid")
		contains(A().Diagnostics.Report(), "Integrations")
	end)
end)

describe("the raid switch, off, in demo mode", function()
	it("shows no Raid view in the invented guild either", function()
		Mock.Slash("/accord demo")
		for _, view in ipairs(AzerothAccord.VIEWS) do Mock.Slash("/accord " .. view) end
		Mock.Advance(2)
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "raid") end
		isNil(A().RaidView.frame)
		eq(#Mock.errors, 0)
	end)
end)

describe("the switches of M9, as shipped (M9.10)", function()
	before_boot(withFDCP)

	local M9 = { { "actions", "inbox" }, { "groups", "groups" }, { "addons", "addons" } }

	it("are on, and raid stays off", function()
		for _, name in ipairs({ "actions", "groups", "census" }) do
			eq(A().Features[name], true)
			truthy(A().Features.On(name), name)
		end
		eq(A().Features.raid, false)
		truthy(A().Store.IsActive("groups"))
		truthy(A().Store.IsActive("addons"))
		falsy(A().Store.IsActive("guildcfg"))
	end)

	it("show their views, commands and help lines, and no Raid", function()
		Mock.Slash("/accord help")
		local help = table.concat(Mock.PlainOutput(), "\n")
		for _, pair in ipairs(M9) do
			contains(help, "/accord " .. pair[2])
			Mock.Slash("/accord " .. pair[2])
			eq(A().Shell.selected, pair[1])
			truthy(A().Shell.views[pair[1]].frame:IsVisible(), pair[1])
			isNil(A().Shell.views[pair[1]].failed, pair[1])
		end
		falsy(help:find("/accord raid", 1, true))
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "raid") end
		eq(#Mock.errors, 0)
	end)

	it("show the Compartment line, the notice modules, the sharing switch and the debug sections", function()
		A().Store:Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(),
			requester = BOB, kind = "withdraw", status = "open", amount = 10000, created = GetServerTime(), history = {} }
		A().Bus:Emit("STORE_CHANGED", "bankreq", BOB .. ":1", "remote")
		Mock.Advance(65)
		local tip = { lines = {} }
		function tip:AddLine(t) self.lines[#self.lines + 1] = t end
		A().Shell.FillTooltip(tip)
		contains(table.concat(tip.lines, "\n"), "Action Center")
		local modules = {}
		for _, def in ipairs(A().SettingsModel.NoticeModules()) do modules[def.id] = true end
		truthy(modules.bank); truthy(modules.groups); truthy(modules.digest)
		truthy(A().SettingsModel.Visible("shareAddons"))
		local share = false
		for _, section in ipairs(A().ShareModel.Describe()) do if section.id == "addons" then share = true end end
		truthy(share, "What I share lists the addons")
		local titles = {}
		for _, section in ipairs(A().Diagnostics.Collect().sections) do titles[section.title] = true end
		for _, title in ipairs({ "Actions", "Notify", "Digest", "Groups", "Game finder", "Census" }) do truthy(titles[title], title) end
		falsy(titles.Integrations); falsy(titles.FDCP)
	end)
end)

describe("the actions switch, off", function()
	before_boot(function(M)
		M.features = { actions = false }
		M.guild.Set{ name = "Accord", myRank = 1, members = {
			{ name = "Officer", rank = 1, guid = OFF }, { name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = true },
		} }
	end)

	local function request()
		A().Store:Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(), requester = BOB,
			kind = "withdraw", status = "open", amount = 10000, created = GetServerTime(), history = {} }
		A().Bus:Emit("STORE_CHANGED", "bankreq", BOB .. ":1", "remote")
		Mock.Advance(65)
	end

	it("is off when the switch says so", function()
		eq(A().Features.actions, false)
		falsy(A().Features.On("actions"))
	end)

	it("has no Action Center view, command, help line or tooltip line, and lists nothing", function()
		request()
		Mock.Slash("/accord")
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "actions") end
		isNil(A().Shell.content.tabs.buttons.actions)
		falsy(A().Shell:Select("actions"))
		Mock.Slash("/accord help")
		falsy(table.concat(Mock.PlainOutput(), "\n"):find("/accord inbox", 1, true))
		Mock.Slash("/accord inbox")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Unknown command 'inbox'")
		eq(#A().Actions:Rows(), 0)
		eq(A().Actions:Count(), 0)
		local tip = { lines = {} }
		function tip:AddLine(t) self.lines[#self.lines + 1] = t end
		A().Shell.FillTooltip(tip)
		falsy(table.concat(tip.lines, "\n"):find("Action Center", 1, true))
		isNil(A().ActionsView.frame)
		falsy(A().Diagnostics.Report():find("Actions:", 1, true))
	end)

	it("keeps no craft reminder", function()
		ChatFrame_OpenChat = function() end
		C_Spell.GetSpellLink = nil
		Mock.spells.known[2330] = { name = "Minor Healing Potion", icon = 1 }
		truthy((A().Recipes:OpenCraftRequest(BOB, 2330)))
		isNil(A().GuildKey:Data().craftAsks)
	end)
end)

describe("the switch groups (M9.6) is off", function()
	before_boot(function(M)
		M.features = { groups = false }
		M.guild.Set{ name = "Accord", myRank = 1, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = true },
		} }
	end)

	it("switched off: the set takes nothing, GAPP and GASK are ignored, nothing is sent", function()
		eq(A().Features.groups, false)
		falsy(A().Features.On("groups"))
		falsy(A().Store.IsActive("groups"))
		local t = GetServerTime()
		local rec = { id = BOB .. ":1", author = BOB, rev = 1, time = t, kind = "quest", act = "x", min = 1, max = 60, size = 5,
			have = 1, need = { d = 1 }, created = t, ends = t + 3600, status = "open" }
		eq(A().Store:Receive("groups", { rec }, "Bob", "GUILD"), 0)
		local before = #Mock.chat.sent
		A().Bus:Emit("NET_MESSAGE", { t = "GASK", h = "" }, "Bob", "GUILD")
		A().Bus:Emit("NET_MESSAGE", { t = "GAPP", g = "x", k = "apply", r = "t" }, "Bob", "WHISPER")
		falsy(A().Groups:Post({ kind = "quest", act = "x", need = { d = 1 } }))
		Mock.Advance(120)
		eq(#Mock.chat.sent, before)
		eq(A().Store:Count("groups"), 0)
	end)
end)

describe("the switch census (M9.9) is off", function()
	before_boot(function(M)
		M.features = { census = false }
		M.guild.Set{ name = "Accord", myRank = 1, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = true },
		} }
	end)

	-- the whole behaviour with the switch off and on is in Tests/test_addons_census.lua
	it("switched off: no view, and nothing of the addon census is sent", function()
		eq(A().Features.census, false)
		falsy(A().Features.On("census"))
		falsy(A().Store.IsActive("addons"))
		local before = #Mock.chat.sent
		A().Bus:Emit("SYNC_HELLO", true)
		Mock.Advance(200)
		eq(#Mock.chat.sent, before)
		eq(A().Store:Count("addons"), 0)
		for _, v in ipairs(A().Shell:ViewList()) do truthy(v.id ~= "addons") end
	end)
end)

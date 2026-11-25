-- The feature switches (Core/Features.lua): with "raid" off, as every release ships it, nothing of M10.2 and M11.7 is
-- visible, no FDCP callback is registered and nothing of it is written or sent, even with FDCP loaded and a guild
-- choice of FDCP left over from a development build.
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
		eq(A().Shell.selected, "roster")
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

-- The "Choose your main" window (owner, 2026-11-28): when it opens, that it cannot be put off, and what Confirm saves.
local function A() return AzerothAccord end
local function P() return AzerothAccord.MainPrompt end

local function alt(level)
	truthy(A().Accounts:Register({ guid = "Player-1-0000BEEF", name = "Althea", level = level or 20 }))
end

describe("the Choose your main window", function()
	before_boot(function(M)
		M.guild.Set{ name = "Accord", myRank = 3, members = {} }
	end)

	it("does not open for an account with one character", function()
		A().Accounts:RegisterSelf()
		falsy(P().Needed())
		truthy(A().Shell:OpenView("roster"))
		truthy(P().dialog == nil or not P().dialog:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("opens with the panel, preselects the highest and saves the choice", function()
		A().Accounts:RegisterSelf()
		alt(1)
		truthy(P().Needed())
		truthy(A().Shell:OpenView("roster"))
		local d = P().dialog
		truthy(d and d:IsShown())
		eq(P().chosen, (A().Accounts:Main()))
		P().chosen = "Player-1-0000BEEF"
		eq(P():Confirm(), true)
		falsy(d:IsShown())
		local guid, source = A().Accounts:Main()
		eq(guid, "Player-1-0000BEEF")
		eq(source, "chosen")
		falsy(P().Needed())
		eq(#Mock.errors, 0)
	end)

	it("has no way to put it off and comes back until a main is chosen", function()
		A().Accounts:RegisterSelf()
		alt()
		A().Shell:OpenView("roster")
		local d = P().dialog
		isNil(d.cancel)
		A().Window:Toggle()
		A().Window:Toggle()
		truthy(d:IsShown())
	end)

	it("waits while in combat", function()
		A().Accounts:RegisterSelf()
		alt()
		A().Compat.InCombat = function() return true end
		isNil(P():MaybeShow(A().Shell:Content()))
	end)
end)

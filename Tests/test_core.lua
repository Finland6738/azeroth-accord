-- Bus, Role and GuildKey (M1.4). The Bus and Role groups are adapted from Azeroth Guild Finder (Tests/test_core.lua),
-- same owner, GPL-3.0 (ADR 0018).
local function bus() return AzerothAccord.Bus end
local function role() return AzerothAccord.Role end
local function GK() return AzerothAccord.GuildKey end

describe("Bus", function()
	it("delivers arguments in subscription order", function()
		local seen = {}
		bus():On("T_A", function(a, b) seen[#seen + 1] = "1" .. a .. b end)
		bus():On("T_A", function(a, b) seen[#seen + 1] = "2" .. a .. b end)
		eq(bus():Emit("T_A", "x", "y"), 2)
		deepEq(seen, { "1xy", "2xy" })
	end)

	it("registers a function once and removes it with Off", function()
		local n = 0
		local fn = function() n = n + 1 end
		truthy(bus():On("T_B", fn))
		falsy(bus():On("T_B", fn))
		bus():Emit("T_B")
		eq(n, 1)
		truthy(bus():Off("T_B", fn))
		falsy(bus():Off("T_B", fn))
		bus():Emit("T_B")
		eq(n, 1)
	end)

	it("Off without a function removes every listener of the event", function()
		bus():On("T_C", function() end)
		bus():On("T_C", function() end)
		truthy(bus():Off("T_C"))
		eq(bus():ListenerCount("T_C"), 0)
	end)

	it("isolates a failing listener and records the error for /accord debug", function()
		bus():On("T_D", function() error("listener broke") end)
		local reached = false
		bus():On("T_D", function() reached = true end)
		eq(bus():Emit("T_D"), 1)
		truthy(reached)
		eq(bus().errorCount, 1)
		contains(table.concat(bus():DebugLines(), "\n"), "listener broke")
	end)

	it("allows a listener to unsubscribe itself while delivering", function()
		local n = 0
		local fn
		fn = function() n = n + 1; bus():Off("T_E", fn) end
		bus():On("T_E", fn)
		bus():Emit("T_E")
		bus():Emit("T_E")
		eq(n, 1)
	end)

	it("ignores bad arguments and unknown events", function()
		falsy(bus():On(nil, function() end))
		falsy(bus():On("T_F", "not a function"))
		eq(bus():Emit("T_NOBODY"), 0)
	end)
end)

describe("Role", function()
	local function track()
		local events = {}
		bus():On("ROLE_CHANGED", function(r, key, oldR, oldKey) events[#events + 1] = { r, key, oldR, oldKey } end)
		return events
	end

	it("is none without a guild, with no guild key", function()
		eq(role():Get(), "none")
		isNil(role():GuildKey())
		falsy(role():InGuild())
	end)

	it("computes member, officer and gm from the rank", function()
		Mock.guild.Set{ name = "G", myRank = 3 }
		eq(role():Get(), "member")
		falsy(role():IsOfficer())
		Mock.guild.SetMyRank(1)
		eq(role():Get(), "officer")
		truthy(role():IsOfficer())
		Mock.guild.SetMyRank(0)
		eq(role():Get(), "gm")
		truthy(role():IsOfficer())
	end)

	it("emits ROLE_CHANGED for every transition, and not when nothing changed", function()
		local events = track()
		Mock.guild.Set{ name = "G", myRank = 3 }
		Mock.guild.SetMyRank(1)
		Mock.Fire("GUILD_ROSTER_UPDATE")
		Mock.guild.Leave()
		eq(#events, 3)
		deepEq(events[1], { "member", "TestRealm/G", "none", nil })
		deepEq(events[2], { "officer", "TestRealm/G", "member", "TestRealm/G" })
		deepEq(events[3], { "none", nil, "officer", "TestRealm/G" })
	end)

	it("emits GUILD_CHANGED only when the guild changes", function()
		local changes = {}
		bus():On("GUILD_CHANGED", function(key, old) changes[#changes + 1] = tostring(key) .. "<" .. tostring(old) end)
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.guild.SetMyRank(1)
		Mock.guild.Set{ name = "Beta", myRank = 1 }
		Mock.guild.Leave()
		deepEq(changes, { "TestRealm/Alpha<nil", "TestRealm/Beta<TestRealm/Alpha", "nil<TestRealm/Beta" })
	end)

	it("recomputes on each of the guild events", function()
		Mock.guild.Set{ name = "G", myRank = 3 }
		for _, event in ipairs({ "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_RANKS_UPDATE", "PLAYER_ENTERING_WORLD" }) do
			Mock.guild.myRank = (Mock.guild.myRank == 3) and 1 or 3
			Mock.Fire(event)
			eq(role():Get(), Mock.guild.myRank == 1 and "officer" or "member", event)
		end
	end)

	it("survives a missing guild API (none, no error)", function()
		IsInGuild, GetGuildInfo, IsGuildLeader, C_Club = nil, nil, nil, nil
		role():Refresh()
		eq(role():Get(), "none")
		eq(#Mock.errors, 0)
	end)
end)

describe("GuildKey", function()
	it("builds <realm>/<guild> with the realm normalized", function()
		eq(GK().Make("Test Realm", "Night Watch"), "TestRealm/Night Watch")
		eq(GK().Make("Azjol-Nerub", "G"), "AzjolNerub/G")
		eq(GK().Make("Kel'Thuzad", "G"), "KelThuzad/G")
		isNil(GK().Make(nil, "G"))
		isNil(GK().Make("R", ""))
		local realm, name = GK().Split("TestRealm/Night Watch")
		eq(realm, "TestRealm"); eq(name, "Night Watch")
	end)

	it("uses the guild's own realm on connected realms", function()
		Mock.guild.Set{ name = "G", realm = "Other Realm", myRank = 3 }
		eq(GK():Current(), "OtherRealm/G")
	end)

	it("hands out one table per guild and never mixes them", function()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		local alpha = GK():Data()
		alpha.records = { "a1" }
		Mock.guild.Set{ name = "Beta", myRank = 3 }
		local beta = GK():Data()
		ne(beta, alpha)
		isNil(beta.records, "the other guild starts empty")
		beta.records = { "b1" }
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		deepEq(GK():Data().records, { "a1" }, "coming back finds the old data")
		deepEq(GK():Known(), { "TestRealm/Alpha", "TestRealm/Beta" })
	end)

	it("has no data without a guild", function()
		isNil(GK():Data())
	end)

	it("keeps each guild's data across a reload", function()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		GK():Data().records = { "a1" }
		Mock.Reload()
		deepEq(GK():Data().records, { "a1" })
		deepEq(AzerothAccordDB.guilds["TestRealm/Alpha"].records, { "a1" })
	end)

	it("shows the size of the current guild's data without its name", function()
		Mock.guild.Set{ name = "Hidden Name", myRank = 3 }
		GK():Data().records = { ("x"):rep(2048) }
		Mock.ClearOutput()
		Mock.Slash("/accord debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Current guild: about 2.")
		contains(text, "records 2.")
		falsy(text:find("Hidden Name", 1, true))
	end)
end)

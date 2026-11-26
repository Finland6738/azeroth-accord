-- Compat layer (M1.3): guarded calls, missing / erroring / secret APIs, guild with the C_Club fallback, club fields,
-- player, group, trade skills, guild bank, restrictions, time, encoding, the capability probe and /accord debug.
-- The first groups are adapted from Azeroth Guild Finder (Tests/test_compat.lua), same owner, GPL-3.0 (ADR 0018).
-- Tests replace client globals AFTER login; the capability table is rebuilt with Compat:Probe() when a test needs it.
local function compat()
	return AzerothAccord.Compat
end

local function debugText()
	Mock.ClearOutput()
	truthy(Mock.Slash("/accord debug"))
	return table.concat(Mock.PlainOutput(), "\n")
end

describe("Resolve and Call", function()
	it("resolves dotted names and returns nil for nothing", function()
		local C = compat()
		eq(C.Resolve("C_ChatInfo.InChatMessagingLockdown"), C_ChatInfo.InChatMessagingLockdown)
		eq(C.Resolve("Enum.Base64Variant.Standard"), 0)
		eq(C.Resolve("Nope.Nothing.Here"), nil)
		eq(C.Resolve(""), nil)
		eq(C.Resolve(42), nil)
	end)

	it("reports an available function with its values", function()
		local state, a, b = compat().Call("GetBuildInfo")
		eq(state, "available")
		eq(a, "1.60.1")
		eq(b, "70170")
	end)

	it("reports a missing function", function()
		local state, v = compat().Call("C_Club.DoesNotExist")
		eq(state, "missing")
		eq(v, nil)
	end)

	it("catches an erroring function", function()
		function BoomGlobal() error("kaput") end
		eq((compat().Call("BoomGlobal")), "error")
	end)

	it("classes a restriction error as restricted", function()
		function RestrictedGlobal() error("action restricted by the client") end
		eq((compat().Call("RestrictedGlobal")), "restricted")
	end)

	it("drops secret values and reports restricted", function()
		function SecretGlobal() return Mock.SECRET, 5 end
		local state, a, b = compat().Call("SecretGlobal")
		eq(state, "restricted")
		eq(a, nil)
		eq(b, 5)
		truthy(compat().IsSecret(Mock.SECRET))
		eq(compat().Readable(Mock.SECRET), nil)
		eq(compat().Readable(7), 7)
	end)

	it("honours canaccessvalue", function()
		local hidden = {}
		function canaccessvalue(v) return v ~= hidden end
		truthy(compat().IsSecret(hidden))
		falsy(compat().IsSecret({}))
	end)

	it("works when the secret functions do not exist", function()
		issecretvalue, canaccessvalue, issecrettable = nil, nil, nil
		falsy(compat().IsSecret({}))
		eq((compat().Call("GetBuildInfo")), "available")
	end)

	it("ReadableCopy keeps plain fields and drops secrets, functions and deep tables", function()
		local copy = compat().ReadableCopy({ a = 1, s = Mock.SECRET, f = print, t = { x = 2, deep = { y = 3 } } })
		eq(copy.a, 1)
		isNil(copy.s)
		isNil(copy.f)
		eq(copy.t.x, 2)
		isNil(copy.t.deep)
		isNil(compat().ReadableCopy(Mock.SECRET))
	end)
end)

describe("guild helpers", function()
	it("reads guild, rank and roster from the classic API", function()
		local C = compat()
		Mock.guild.Set{ name = "Test Guild", myRank = 0, members = { { name = "Bob", level = 40, rank = 2, online = false,
			lastOnline = { 0, 1, 2, 3 }, note = "alt: Bobby", guid = "Player-1-B0B" } } }
		truthy(C.Guild.InGuild())
		eq(C.Guild.GuildName(), "Test Guild")
		truthy(C.Guild.IsGuildLeader())
		truthy(C.Guild.IsOfficer())
		eq((C.Guild.RosterCount()), 2)
		local row = C.Guild.RosterRow(2)
		eq(row.name, "Bob")
		eq(row.level, 40)
		eq(row.online, false)
		eq(row.note, "alt: Bobby")
		eq(row.guid, "Player-1-B0B")
		eq(row.rankName, "Veteran")
		eq(row.source, "roster")
		eq(row.lastOnlineHours, 720 + 48 + 3)
		eq(C.Guild.LastOnline(2), 771)
		eq(C.Guild.LastOnline(1), nil)
		eq(C.Guild.RosterRow(9), nil)
		eq(#C.Guild.Roster(), 2)
	end)

	it("an officer who is not the leader is an officer", function()
		Mock.guild.Set{ name = "G", myRank = 1 }
		falsy(compat().Guild.IsGuildLeader())
		truthy(compat().Guild.IsOfficer())
		Mock.guild.SetMyRank(3)
		falsy(compat().Guild.IsOfficer())
	end)

	it("knows which roster members are officers, by name with or without realm", function()
		Mock.guild.Set{ name = "G", myRank = 3, members = { { name = "Boss", rank = 0 }, { name = "Off", rank = 1 }, { name = "Grunt", rank = 3 } } }
		local G = compat().Guild
		truthy(G.MemberIsOfficer("Boss"))
		truthy(G.MemberIsOfficer("off-TestRealm"))
		falsy(G.MemberIsOfficer("Grunt"))
		falsy(G.MemberIsOfficer("Stranger"))
		eq(G.MemberRankIndex("Grunt-Other"), 3)
		eq(G.RankIsOfficer(nil), nil)
	end)

	it("officer rank flags degrade to unknown", function()
		C_GuildInfo.GuildControlGetRankFlags = nil
		Mock.guild.Set{ name = "G", myRank = 3, members = { { name = "Off", rank = 1 } } }
		eq(compat().Guild.RankIsOfficer(1), nil)
		truthy(compat().Guild.RankIsOfficer(0), "the Guild Master is always an officer")
		falsy(compat().Guild.MemberIsOfficer("Off"))
	end)

	it("no guild", function()
		Mock.guild.Leave()
		falsy(compat().Guild.InGuild())
		eq(compat().Guild.GuildName(), nil)
		eq((compat().Guild.RosterCount()), 0)
		deepEq(compat().Guild.Roster(), {})
	end)

	it("falls back to C_Club when the classic functions are missing", function()
		local members = {
			[11] = { name = "Ann", level = 30, classID = 5, guid = "Player-1-A", guildRankOrder = 2 },
			[12] = { name = "Cid", level = 50, classID = 1, guid = "Player-1-C", guildRankOrder = 4,
				lastOnlineYear = 0, lastOnlineMonth = 0, lastOnlineDay = 3, lastOnlineHour = 4 },
		}
		IsInGuild, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, GetGuildRosterLastOnline, IsGuildLeader = nil, nil, nil, nil, nil, nil
		C_Club = {
			GetGuildClubId = function() return 7 end,
			GetClubInfo = function(id) return id == 7 and { name = "Club Guild" } or nil end,
			GetClubMembers = function() return { 11, 12 } end,
			GetMemberInfo = function(_, id) return members[id] end,
		}
		local C = compat()
		truthy(C.Guild.InGuild())
		eq(C.Guild.GuildName(), "Club Guild")
		eq((C.Guild.RosterCount()), 2)
		local a, c = C.Guild.RosterRow(1), C.Guild.RosterRow(2)
		eq(a.name, "Ann"); eq(a.rankIndex, 1); eq(a.online, true); eq(a.lastOnlineHours, nil); eq(a.source, "club")
		eq(c.classID, 1); eq(c.online, false); eq(c.lastOnlineHours, 76)
		eq(C.Guild.RosterRow(3), nil)
	end)

	it("degrades to nothing when neither API exists", function()
		IsInGuild, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, IsGuildLeader, C_Club = nil, nil, nil, nil, nil, nil
		local C = compat()
		falsy(C.Guild.InGuild())
		eq(C.Guild.GuildName(), nil)
		eq((C.Guild.RosterCount()), 0)
		eq(C.Guild.RosterRow(1), nil)
		falsy(C.Guild.IsGuildLeader())
	end)

	it("an erroring GetGuildInfo does not raise", function()
		function GetGuildInfo() error("no") end
		eq(compat().Guild.GuildName(), nil)
	end)

	it("a secret officer note is dropped, the row stays", function()
		Mock.guild.Set{ name = "G", myRank = 3, members = { { name = "Bob" } } }
		local original = GetGuildRosterInfo
		GetGuildRosterInfo = function(i)
			local v = { original(i) }
			v[8] = Mock.SECRET
			return unpack(v, 1, 17)
		end
		local row = compat().Guild.RosterRow(2)
		eq(row.name, "Bob")
		eq(row.source, "roster")
		isNil(row.officerNote)
	end)
end)

describe("club fields [verify S2]", function()
	local function guild()
		Mock.guild.Set{ name = "G", myRank = 1, myProfessions = { { id = 171, name = "Alchemy", rank = 250 } }, myDiscord = "me_1",
			members = { { name = "Bob", professions = { { id = 164, name = "Blacksmithing", rank = 300 }, { id = 186, name = "Mining", rank = 290 } },
				discord = "bob_2" } } }
	end

	it("reads professions and Discord when the server fills them", function()
		guild()
		Mock.club.fill.professions, Mock.club.fill.discord = true, true
		local C = compat()
		local members = C.Club.GuildMembers()
		eq(#members, 2)
		local bob = members[2]
		deepEq(C.Club.Professions(bob), { { id = 164, name = "Blacksmithing", rank = 300 }, { id = 186, name = "Mining", rank = 290 } })
		eq(C.Club.Discord(bob), "bob_2")
		eq(bob.online, true)
		C:Probe()
		eq(C:Feature("clubProfessions"), "available")
		eq(C:Feature("clubDiscord"), "available")
	end)

	it("empty fields leave the features unknown, never an error", function()
		guild()
		local C = compat()
		local bob = C.Club.GuildMembers()[2]
		deepEq(C.Club.Professions(bob), {})
		eq(C.Club.Discord(bob), nil)
		C:Probe()
		eq(C:Feature("clubProfessions"), "unknown")
		eq(C:Feature("clubDiscord"), "unknown")
	end)

	it("Discord as a plain string or an unknown table shape", function()
		local C = compat()
		eq(C.Club.Discord({ discordInfo = "plain" }), "plain")
		eq(C.Club.Discord({ discordInfo = { displayName = "shown" } }), "shown")
		eq(C.Club.Discord({ discordInfo = { other = 3 } }), nil)
		eq(C.Club.Discord({ discordInfo = Mock.SECRET }), nil)
		eq(C.Club.Discord(nil), nil)
	end)

	it("a missing club API turns the features off", function()
		C_Club = nil
		local C = compat()
		eq(C.Club.GuildMembers(), nil)
		C:Probe()
		eq(C:Feature("clubProfessions"), "missing")
	end)

	it("BattleTag friend requests go through the club", function()
		guild()
		eq(compat().Club.SendBattleTagFriendRequest(9001, 2), "available")
		deepEq(Mock.club.friendRequests, { 2 })
		C_Club.SendBattleTagFriendRequest = nil
		eq(compat().Club.SendBattleTagFriendRequest(9001, 2), "missing")
	end)
end)

describe("player helpers", function()
	it("reads the player", function()
		local C = compat()
		eq(C.Player.Faction(), "Horde")
		eq(C.Player.Name(), "Testchar")
		eq(C.Player.Realm(), "TestRealm")
		eq(C.Player.RealmDisplay(), "Test Realm")
		eq(C.Player.GUID(), "Player-1-0000A001")
		eq(C.Player.Level(), 60)
		eq(C.Player.ClassID(), 1)
		eq(C.Player.ClassFile(), "WARRIOR")
	end)

	it("missing player APIs return nil", function()
		UnitFactionGroup, UnitLevel, UnitClass, GetNormalizedRealmName, GetRealmName, UnitGUID, UnitName = nil, nil, nil, nil, nil, nil, nil
		local C = compat()
		eq(C.Player.Faction(), nil); eq(C.Player.Level(), nil); eq(C.Player.ClassID(), nil)
		eq(C.Player.Realm(), nil); eq(C.Player.GUID(), nil); eq(C.Player.Name(), nil)
	end)

	it("realm falls back to GetRealmName", function()
		GetNormalizedRealmName = nil
		eq(compat().Player.Realm(), "TestRealm")
	end)

	it("BattleTag [verify S8]: own tag, BNGetInfo fallback, nothing when offline from Battle.net", function()
		local C = compat()
		eq(C.Player.BattleTag(), nil)
		Mock.player.battleTag = "Hero#1234"
		eq(C.Player.BattleTag(), "Hero#1234")
		BNet_GetBattleTagSelf = nil
		eq(C.Player.BattleTag(), "Hero#1234")
		BNGetInfo = function() error("no bnet") end
		eq(C.Player.BattleTag(), nil)
		BNet_GetBattleTagSelf = function() return "NoHash" end
		eq(C.Player.BattleTag(), nil)
	end)
end)

describe("group helpers [verify S7]", function()
	local members = {
		{ name = "Ally", guid = "Player-1-0A", inGuild = true },
		{ name = "Stranger", guid = "Player-1-0B", inGuild = false, realm = "Other" },
	}

	it("alone: no units", function()
		local G = compat().Group
		falsy(G.InGroup())
		eq(G.Size(), 0)
		deepEq(G.Units(), {})
		deepEq(G.Members(), {})
	end)

	it("a party: units, GUIDs, names and guild membership", function()
		Mock.guild.Set{ name = "G" }
		Mock.group.Set{ members = members }
		local G = compat().Group
		truthy(G.InGroup()); falsy(G.InRaid())
		eq(G.Size(), 3)
		deepEq(G.Units(), { "party1", "party2" })
		local list = G.Members()
		eq(list[1].guid, "Player-1-0A"); eq(list[1].name, "Ally"); eq(list[1].inGuild, true)
		eq(list[2].name, "Stranger-Other"); eq(list[2].inGuild, false)
	end)

	it("a raid leaves the player out and reads the raid roster", function()
		Mock.guild.Set{ name = "G" }
		Mock.group.Set{ raid = true, members = members }
		local G = compat().Group
		deepEq(G.Units(), { "raid1", "raid2" })
		local row = G.RaidRosterRow(1)
		eq(row.name, "Ally"); eq(row.classFile, "WARRIOR"); eq(row.online, true)
		eq(G.RaidRosterRow(9), nil)
	end)

	it("secret GUIDs and names come back as nil, the member still counts", function()
		Mock.guild.Set{ name = "G" }
		Mock.group.Set{ raid = true, members = members }
		Mock.group.secretGUIDs = true
		local G = compat().Group
		local list = G.Members()
		eq(#list, 2)
		isNil(list[1].guid)
		isNil(list[1].name)
		eq(G.RaidRosterRow(1), nil)
	end)

	it("missing group APIs mean alone", function()
		IsInGroup, IsInRaid, GetNumGroupMembers, UnitIsInMyGuild, GetRaidRosterInfo = nil, nil, nil, nil, nil
		local G = compat().Group
		falsy(G.InGroup()); eq(G.Size(), 0); deepEq(G.Units(), {})
		eq(G.Member("party1").inGuild, nil)
		eq(G.RaidRosterRow(1), nil)
	end)
end)

describe("trade skills [verify S3, S4]", function()
	local function own()
		Mock.tradeskill.own = { { name = "Alchemy", skillLine = 171, rank = 250, maxRank = 300, recipes = { 2330, 2332 } },
			{ name = "Herbalism", skillLine = 182, rank = 300, maxRank = 300 } }
	end

	it("reads the own professions", function()
		own()
		deepEq(compat().TradeSkill.OwnProfessions(), {
			{ index = 1, name = "Alchemy", rank = 250, maxRank = 300, skillLine = 171 },
			{ index = 2, name = "Herbalism", rank = 300, maxRank = 300, skillLine = 182 },
		})
	end)

	it("reads the own skill LEVELS from the skill lines (WoW Forever's Skills panel), not the other skills", function()
		own()
		Mock.tradeskill.skillLines = true
		local got = compat().TradeSkill.OwnProfessions()
		Mock.tradeskill.skillLines = nil
		deepEq(got, {
			{ name = "Alchemy", rank = 250, maxRank = 300, skillLine = 171, source = "skills" },
			{ name = "Herbalism", rank = 300, maxRank = 300, skillLine = 182, source = "skills" },
		})
	end)

	it("recipe ids need GetAllRecipeIDs, which is not in the dump", function()
		own()
		Mock.tradeskill.open = 1
		local TS = compat().TradeSkill
		eq(TS.RecipeIDs(), nil, "the function does not exist in the mock by default")
		C_TradeSkillUI.GetFilteredRecipeIDs = function() return { 2330, "bad", 2332 } end
		deepEq(TS.RecipeIDs(), { 2330, 2332 })
		eq(TS.BaseProfessionInfo().professionID, 171)
		eq(TS.RecipeInfo(2330).learned, true)
	end)

	it("GetAllRecipeIDs is used when the client has it", function()
		Mock.tradeskill.AddAllRecipeIDs()
		own()
		Mock.tradeskill.open = 1
		deepEq(compat().TradeSkill.RecipeIDs(), { 2330, 2332 })
	end)

	it("the guild recipe directory answers when enabled", function()
		Mock.tradeskill.guildEnabled = true
		Mock.tradeskill.guildRecipes = { ["Player-1-B0B"] = { [164] = { 2660, 2663 } } }
		local TS = compat().TradeSkill
		eq(TS.GuildRecipesEnabled(), true)
		eq(TS.QueryGuildMemberRecipes("Player-1-B0B", 164), "available")
		Mock.Advance(0.2)
		local line, recipes = TS.GuildMemberRecipes()
		eq(line, 164)
		deepEq(recipes, { 2660, 2663 })
		eq(TS.QueryGuildMemberRecipes(nil, 164), "missing")
	end)

	it("everything degrades when the APIs are missing or fail", function()
		GetProfessions, GetGuildMemberRecipes = nil, nil
		C_TradeSkillUI.IsGuildTradeSkillsEnabled = function() error("nope") end
		C_GuildInfo.QueryGuildMemberRecipes = nil
		local TS = compat().TradeSkill
		deepEq(TS.OwnProfessions(), {})
		eq(TS.GuildRecipesEnabled(), nil)
		eq(TS.QueryGuildMemberRecipes("Player-1-B0B", 164), "missing")
		eq(TS.GuildMemberRecipes(), nil)
		compat():Probe()
		eq(compat():Feature("guildRecipesNative"), "missing")
	end)

	it("the directory feature follows IsGuildTradeSkillsEnabled", function()
		local C = compat()
		eq(C:Feature("guildRecipesNative"), "missing")
		Mock.tradeskill.guildEnabled = true
		C:Probe()
		eq(C:Feature("guildRecipesNative"), "unknown")
	end)
end)

describe("guild bank [verify S9]", function()
	local function vault()
		Mock.bank.tabs = {
			{ name = "Mats", icon = 1, items = { [1] = { itemID = 2589, count = 20 }, [5] = { itemID = 2592, count = 7 } },
				log = { { "deposit", "Bob", 2589, 20, nil, nil, 0, 0, 1, 2 } } },
			{ name = "Officers", icon = 2, viewable = false, items = { [1] = { itemID = 1, count = 1 } } },
		}
		Mock.bank.money = 123456
		Mock.bank.moneyLog = { { "deposit", "Bob", 10000, 0, 0, 0, 3 } }
	end

	it("reads tabs, items, money and logs while the vault is open", function()
		vault()
		Mock.bank.Open()
		local B = compat().Bank
		truthy(B.Enabled())
		eq(B.NumTabs(), 2)
		eq(B.TabInfo(1).name, "Mats")
		falsy(B.TabInfo(2).isViewable)
		local item = B.Item(1, 5)
		eq(item.itemID, 2592); eq(item.count, 7)
		eq(B.Item(1, 2), nil)
		eq(B.Item(2, 1), nil, "a tab the player may not view gives nothing")
		eq(B.Money(), 123456)
		local log = B.ItemLog(1)
		eq(#log, 1); eq(log[1].kind, "deposit"); eq(log[1].count, 20); eq(log[1].hours, 2)
		eq(B.MoneyLog()[1].amount, 10000)
		eq(B.QueryTab(1), "available")
	end)

	it("a closed vault gives no items and no logs, without errors", function()
		vault()
		local B = compat().Bank
		eq(B.Item(1, 1), nil)
		deepEq(B.ItemLog(1), {})
		deepEq(B.MoneyLog(), {})
	end)

	it("missing bank APIs degrade", function()
		C_GuildBank, GetNumGuildBankTabs, GetGuildBankItemInfo, GetNumGuildBankTransactions, GetGuildBankMoney = nil, nil, nil, nil, nil
		local B = compat().Bank
		truthy(B.Enabled())
		eq(B.NumTabs(), 0)
		eq(B.Item(1, 1), nil)
		deepEq(B.ItemLog(1), {})
		eq(B.Money(), nil)
		compat():Probe()
		eq(compat():Feature("bankLogs"), "missing")
	end)
end)

describe("restrictions", function()
	local function install(states)
		Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 }
		C_RestrictedActions = { GetAddOnRestrictionState = function(kind) return states[kind] or 0 end }
	end

	it("chat lockdown and outgoing restriction follow the client", function()
		local C = compat()
		falsy(C.Chat.InChatLockdown())
		falsy(C.Chat.OutgoingAddonRestricted())
		Mock.chat.lockdown, Mock.chat.restricted = true, true
		truthy(C.Chat.InChatLockdown())
		truthy(C.Chat.OutgoingAddonRestricted())
	end)

	it("a missing lockdown API is not a lockdown, an erroring one is", function()
		C_ChatInfo.InChatMessagingLockdown = nil
		falsy(compat().Chat.InChatLockdown())
		C_ChatInfo.InChatMessagingLockdown = function() error("x") end
		truthy(compat().Chat.InChatLockdown())
	end)

	it("a secret lockdown result counts as locked", function()
		C_ChatInfo.InChatMessagingLockdown = function() return Mock.SECRET end
		truthy(compat().Chat.InChatLockdown())
	end)

	it("reads the restriction states", function()
		install({ [1] = 2 })
		local C = compat()
		local active, state = C.Chat.RestrictionActive("Encounter")
		truthy(active); eq(state, 2)
		falsy((C.Chat.RestrictionActive("Combat")))
		eq(C.Chat.RestrictionAny(), "Encounter")
		falsy(C.Chat.CanSend())
	end)

	it("no enum or no function means no restriction", function()
		Enum.AddOnRestrictionType = nil
		falsy((compat().Chat.RestrictionActive("Combat")))
		eq(compat().Chat.RestrictionAny(), nil)
		truthy(compat().Chat.CanSend())
	end)

	it("an erroring state function counts as restricted; IsAddOnRestrictionActive is the fallback", function()
		install({})
		C_RestrictedActions.GetAddOnRestrictionState = function() error("boom") end
		truthy((compat().Chat.RestrictionActive("Combat")))
		C_RestrictedActions.GetAddOnRestrictionState = nil
		C_RestrictedActions.IsAddOnRestrictionActive = function(kind) return kind == 3 end
		truthy((compat().Chat.RestrictionActive("PvPMatch")))
		falsy((compat().Chat.RestrictionActive("Combat")))
	end)

	it("opens a whisper only for a plain name", function()
		local typed
		ChatFrame_OpenChat = function(text) typed = text end
		truthy(compat().Chat.OpenWhisper("Bob-Realm"))
		eq(typed, "/w Bob-Realm ")
		falsy(compat().Chat.OpenWhisper("Bob |cff"))
		ChatFrame_OpenChat = nil
		falsy(compat().Chat.OpenWhisper("Bob"))
	end)
end)

describe("time and encoding", function()
	it("server time falls back to os time", function()
		eq(type(compat().ServerTime()), "number")
		GetServerTime = nil
		eq(type(compat().ServerTime()), "number")
	end)

	it("Now follows the client clock and falls back to the wall clock", function()
		local C = compat()
		eq(C.Now(), GetTime())
		local before = C.Now()
		Mock.Advance(2)
		near(C.Now() - before, 2, 0.001)
		GetTime = nil
		eq(type(C.Now()), "number")
	end)

	it("After and NewTicker wrap C_Timer and degrade to nothing", function()
		local C = compat()
		local fired, ticks = 0, 0
		truthy(C.After(1, function() fired = fired + 1 end))
		local ticker = C.NewTicker(0.5, function() ticks = ticks + 1 end)
		truthy(ticker)
		Mock.Advance(2.05)
		eq(fired, 1)
		eq(ticks, 4)
		ticker:Cancel()
		Mock.Advance(2)
		eq(ticks, 4)
		C_Timer = nil
		falsy(C.After(1, function() end))
		eq(C.NewTicker(1, function() end), nil)
	end)

	it("encoding round trip through the wrappers", function()
		local C = compat()
		local cbor = C.CBOR.Encode({ a = 1, b = "x" })
		deepEq(C.CBOR.Decode(cbor), { a = 1, b = "x" })
		local packed = C.Compress.Deflate(("abc"):rep(100))
		eq(C.Compress.Inflate(packed), ("abc"):rep(100))
		eq(C.Base64.Decode(C.Base64.Encode("hello")), "hello")
	end)

	it("encoding wrappers return nil and a text, never raise", function()
		local C = compat()
		local v, err = C.Base64.Decode("###")
		eq(v, nil)
		contains(err, "error")
		C_EncodingUtil = nil
		v, err = C.CBOR.Encode({})
		eq(v, nil)
		contains(err, "missing")
	end)
end)

describe("every [verify] API degrades without errors", function()
	-- The [verify] APIs of SPEC-05..08 and the probe checks S2-S9, and the Compat helper that reads each one.
	local VERIFY = {
		{ "GetGuildRosterLastOnline", function(C) return C.Guild.LastOnline(2) end },
		{ "C_Club.GetMemberInfo", function(C) return C.Club.GuildMembers() end },
		{ "C_Club.SendBattleTagFriendRequest", function(C) return C.Club.SendBattleTagFriendRequest(9001, 1) end },
		{ "BNet_GetBattleTagSelf", function(C) return C.Player.BattleTag() end },
		{ "BNGetInfo", function(C) return C.Player.BattleTag() end },
		{ "UnitGUID", function(C) return C.Group.Members() end },
		{ "UnitIsInMyGuild", function(C) return C.Group.Members() end },
		{ "GetRaidRosterInfo", function(C) return C.Group.RaidRosterRow(1) end },
		{ "C_TradeSkillUI.IsGuildTradeSkillsEnabled", function(C) return C.TradeSkill.GuildRecipesEnabled() end },
		{ "C_GuildInfo.QueryGuildMemberRecipes", function(C) return C.TradeSkill.QueryGuildMemberRecipes("Player-1-B0B", 164) end },
		{ "GetGuildMemberRecipes", function(C) return C.TradeSkill.GuildMemberRecipes() end },
		{ "C_TradeSkillUI.GetFilteredRecipeIDs", function(C) return C.TradeSkill.RecipeIDs() end },
		{ "C_TradeSkillUI.GetBaseProfessionInfo", function(C) return C.TradeSkill.BaseProfessionInfo() end },
		{ "GetGuildBankTransaction", function(C) return C.Bank.ItemLog(1) end },
		{ "GetGuildBankMoneyTransaction", function(C) return C.Bank.MoneyLog() end },
		{ "GetGuildBankItemInfo", function(C) return C.Bank.Item(1, 1) end },
		{ "C_ChatInfo.InChatMessagingLockdown", function(C) return C.Chat.CanSend() end },
	}
	local KINDS = {
		missing = function() return nil end,
		erroring = function() return function() error("broken by the test") end end,
		secret = function() return function() return Mock.SECRET, Mock.SECRET end end,
	}

	local function setup()
		Mock.guild.Set{ name = "G", myRank = 1, members = { { name = "Bob", online = false, guid = "Player-1-B0B" } } }
		Mock.group.Set{ raid = true, members = { { name = "Ally", inGuild = true } } }
		Mock.bank.tabs = { { name = "T", items = { [1] = { itemID = 5, count = 1 } }, log = { { "deposit", "Bob", 5, 1, nil, nil, 0, 0, 0, 1 } } } }
		Mock.bank.moneyLog = { { "deposit", "Bob", 1, 0, 0, 0, 1 } }
		Mock.bank.Open()
	end

	local function replace(path, value)
		local parent, key = _G, path
		local dot = path:find(".", 1, true)
		if dot then parent, key = _G[path:sub(1, dot - 1)], path:sub(dot + 1) end
		parent[key] = value
	end

	for kind, make in pairs(KINDS) do
		it("when each one is " .. kind, function()
			for _, entry in ipairs(VERIFY) do
				T.boot()
				setup()
				replace(entry[1], make())
				local C = compat()
				local ok, err = pcall(entry[2], C)
				truthy(ok, entry[1] .. " " .. kind .. " raised: " .. tostring(err))
				local probed, perr = pcall(function() return C:Probe() end)
				truthy(probed, entry[1] .. " " .. kind .. " broke the probe: " .. tostring(perr))
				local lines = C:DebugLines()
				truthy(#lines > 10)
				eq(#Mock.errors, 0, entry[1] .. " " .. kind)
			end
		end)
	end
end)

describe("capability probe and /accord debug", function()
	it("probes at login", function()
		local C = compat()
		truthy(C.probed)
		eq(C:State("guild.IsInGuild"), "available")
		eq(C:State("tradeskill.GetAllRecipeIDs"), "missing")
		truthy(C:IsAvailable("encoding.roundTrip"))
		for _, id in ipairs(C.FEATURES) do notNil(C:Feature(id), id) end
	end)

	it("marks missing, restricted and erroring APIs", function()
		T.boot(function()
			GetGuildRosterLastOnline = nil
			C_ChatInfo.InChatMessagingLockdown = function() return true end
			C_GuildInfo.IsGuildOfficer = function() error("bad") end
			Enum.AddOnRestrictionType = { Combat = 0 }
			C_RestrictedActions = { GetAddOnRestrictionState = function() return 1 end }
		end)
		local C = compat()
		eq(C:State("guild.GetGuildRosterLastOnline"), "missing")
		eq(C:State("chat.InChatMessagingLockdown"), "restricted")
		eq(C:State("guild.IsGuildOfficer"), "error")
		eq(C:State("restriction.Combat"), "restricted")
		eq(C:State("restriction.Encounter"), "missing")
	end)

	it("a feature set by a module survives the next probe and goes on the Bus", function()
		local C = compat()
		local seen
		if AzerothAccord.Bus then AzerothAccord.Bus:On("FEATURE_CHANGED", function(id, state) seen = id .. "=" .. state end) end
		truthy(C:SetFeature("officerAddonChannel", "available", "own OFFICER message came back"))
		falsy(C:SetFeature("officerAddonChannel", "available"))
		C:Probe()
		eq(C:Feature("officerAddonChannel"), "available")
		if AzerothAccord.Bus then eq(seen, "officerAddonChannel=available") end
	end)

	it("/accord debug prints build, project id, features and every API, without names", function()
		Mock.guild.Set{ name = "Secret Guild Name" }
		Mock.player.battleTag = "Hidden#9999"
		local text = debugText()
		contains(text, "Azeroth Accord diagnostics")
		contains(text, "1.60.1 (build 70170), interface 16001, project id 99 (Forever)")
		contains(text, "[available] guild.IsInGuild")
		contains(text, "Features:")
		contains(text, "guildTab")
		contains(text, "APIs:")
		contains(text, "sending: allowed")
		for _, id in ipairs(compat().capOrder) do contains(text, id) end
		falsy(text:find("Testchar", 1, true), "no player name")
		falsy(text:find("Secret Guild Name", 1, true), "no guild name")
		falsy(text:find("Hidden#9999", 1, true), "no BattleTag")
	end)

	it("/accord debug probes when the login probe did not run", function()
		compat().probed = false
		contains(debugText(), "[available] guild.IsInGuild")
	end)

	it("/accord debug says when sending is held", function()
		Mock.chat.lockdown = true
		contains(debugText(), "sending: held (lockdown yes")
	end)
end)

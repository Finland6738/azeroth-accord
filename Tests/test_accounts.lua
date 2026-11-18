-- Accounts (M2.2; SPEC-05 §3, SPEC-03 §1, ADR 0006): the own list of characters and its record, the main, stale
-- characters (ACC-04), the groups of other players by MUTUAL listing, characters outside the guild, the hints of public
-- notes (ACC-05), and three simulated accounts seen by a fourth client (alts grouped, a forged list refused).
local function A() return AzerothAccord.Accounts end
local function S() return AzerothAccord.Store end
local function cfg() return AzerothAccord.Config.db.account end

local ME = "Player-1-0000A001"
local ALT, ALT2 = "Player-1-0000A002", "Player-1-0000A003"
local BOB, BOBALT, MAL, OFF = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000BAD", "Player-1-000000FF"
local OUT = "Player-1-0000CC01"   -- a character that is not in the guild

local function guild(extra)
	local members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB }, { name = "Bobalt", level = 30, rank = 4, guid = BOBALT },
		{ name = "Mallory", rank = 3, guid = MAL }, { name = "Officer", rank = 1, guid = OFF },
		{ name = "Altone", level = 20, rank = 4, guid = ALT },
	}
	for _, m in ipairs(extra or {}) do members[#members + 1] = m end
	Mock.guild.Set{ name = "Accord", myRank = 3, members = members }
end

local function R(fields)
	local r = { rev = 1, time = GetServerTime() }
	for k, v in pairs(fields) do r[k] = v end
	return r
end

local function acct(guid, chars, extra)
	local list = {}
	for i, c in ipairs(chars or { guid }) do list[i] = type(c) == "table" and c or { guid = c } end
	local rec = R{ id = guid, author = guid, token = "T" .. guid:sub(-3), chars = list }
	for k, v in pairs(extra or {}) do rec[k] = v end
	return rec
end

local function accept(rec, sender) return S():Accept("accounts", rec, { sender = sender }) end

local function bobAccount()
	truthy(accept(acct(BOB, { { guid = BOB, name = "Bob", level = 60 }, { guid = BOBALT, name = "Bobalt", level = 30 } }, { token = "BOBTOKEN" }), "Bob"))
	truthy(accept(acct(BOBALT, { { guid = BOBALT, name = "Bobalt", level = 30 }, { guid = BOB, name = "Bob", level = 60 } }, { token = "BOBTOKEN" }), "Bobalt"))
end

local function names(list)
	local out = {}
	for i, m in ipairs(list) do out[i] = m.name end
	return out
end

describe("the own list of characters (ACC-01)", function()
	before_boot(function(M) guild() end)

	it("adds the logged-in character with name, class, level and the guild", function()
		local e = A():RegisterSelf()
		eq(e.name, "Testchar"); eq(e.level, 60); eq(e.classID, 1)
		eq(e.guild, "TestRealm/Accord")
		notNil(cfg().chars.TestRealm[ME])
	end)

	it("keeps the characters of the account on this realm and the ones seen in this guild on another", function()
		A():RegisterSelf()
		A():Register{ guid = ALT, name = "Altone", realm = "TestRealm", classID = 5, level = 20 }
		A():Register{ guid = ALT2, name = "Faraway", realm = "OtherRealm", classID = 5, level = 70, guild = "TestRealm/Accord" }
		A():Register{ guid = OUT, name = "Elsewhere", realm = "OtherRealm", classID = 5, level = 70, guild = "OtherRealm/Else" }
		local list = A():OwnChars()
		deepEq(names(list), { "Testchar", "Faraway", "Altone" })
		truthy(list[1].isSelf)
		truthy(list[2].inGuild == false, "Faraway is not in this guild's roster")
		truthy(list[3].inGuild)
	end)

	it("refuses a bad character and does not touch a read-only account", function()
		eq(select(2, A():Register{ guid = "x", name = "A" }), "guid")
		eq(select(2, A():Register{ guid = ALT, name = "" }), "name")
		AzerothAccord.Config.readOnly.account = true
		eq(select(2, A():Register{ guid = ALT, name = "Altone" }), "read-only")
	end)

	it("the main is the choice of the player, else the highest level, then the one added first", function()
		A():RegisterSelf()
		A():Register{ guid = ALT, name = "Altone", classID = 5, level = 70 }
		eq(A():Main(), ALT)
		eq(select(2, A():Main()), "default")
		truthy(A():SetMain(ME))
		eq(A():Main(), ME)
		eq(select(2, A():Main()), "chosen")
		falsy(A():SetMain("Player-1-00000000"))
		cfg().chars.TestRealm[ALT].added = 1
		cfg().chars.TestRealm[ME].added = 1
		cfg().mains.TestRealm = nil
		eq(A():Main(), ALT)
		A():Register{ guid = ALT2, name = "Tie", classID = 5, level = 70 }
		eq(A():Main(), ALT, "a tie keeps the one added first")
	end)
end)

describe("the own record", function()
	before_boot(function(M) guild() end)

	it("publishes the token, the characters, the main and the version, through the Store", function()
		A():Register{ guid = ALT, name = "Altone", classID = 5, level = 20 }
		truthy(A():Publish())
		local rec = S():Get("accounts", ME)
		eq(rec.id, ME); eq(rec.author, ME)
		eq(rec.token, AzerothAccord.Config:Token())
		eq(#rec.chars, 2)
		eq(rec.chars[1].guid, ME)
		eq(rec.main, ME)
		truthy(rec.chars[2].inGuild)
	end)

	it("lists characters outside the guild too, marked as such (ACC-03)", function()
		A():Register{ guid = OUT, name = "Elsewhere", realm = "TestRealm", classID = 5, level = 10 }
		A():Publish()
		local rec = S():Get("accounts", ME)
		for _, c in ipairs(rec.chars) do if c.guid == OUT then falsy(c.inGuild) return end end
		fail("the character outside the guild is not listed")
	end)

	it("is always shared: no setting turns it off (D3)", function()
		isNil(AzerothAccord.Config.rules["account.settings.shareAccount"])
		isNil(AzerothAccord.Config.defaults.account.settings.shareAccount)
		truthy(A():Publish())
	end)

	it("writes a new revision only when something changed", function()
		truthy(A():Publish())
		eq(S():Get("accounts", ME).rev, 1)
		falsy(A():Publish())
		eq(S():Get("accounts", ME).rev, 1)
		A():Register{ guid = ALT, name = "Altone", classID = 5, level = 20 }
		truthy(A():Publish())
		eq(S():Get("accounts", ME).rev, 2)
		falsy(A():Publish())
		truthy(A():SetMain(ALT))
		eq(S():Get("accounts", ME).main, ALT)
		eq(S():Get("accounts", ME).rev, 3)
	end)

	it("follows a level up", function()
		A().AUTO = true
		A():Publish()
		Mock.player.level = 61
		Mock.Fire("PLAYER_LEVEL_UP", 61)
		Mock.Advance(3)
		eq(S():Get("accounts", ME).chars[1].level, 61)
	end)

	it("publishes by itself after login, once the roster has loaded", function()
		A().AUTO = true
		isNil(S():Get("accounts", ME))
		truthy(A():Start())
		Mock.Advance(10)
		notNil(S():Get("accounts", ME))
	end)

	it("keeps the record inside the size limit and always lists the character itself", function()
		for i = 1, 60 do
			A():Register{ guid = ("Player-1-%08X"):format(0x9000 + i), name = "Alt" .. i, classID = 5, level = 1 + i % 70 }
		end
		truthy(A():Publish())
		local rec = S():Get("accounts", ME)
		truthy(#rec.chars <= A().MAX_CHARS, #rec.chars .. " characters")
		eq(rec.chars[1].guid, ME)
		truthy(AzerothAccord.Config.EstimateSize(rec) <= S().SETS.accounts.maxBytes)
	end)

	it("is not published without a guild", function()
		Mock.guild.Leave()
		falsy(A():Publish())
	end)
end)

describe("ACC-04: renamed and stale characters", function()
	before_boot(function(M) guild() end)
	local DAY = 86400

	local function twoAlts()
		A():RegisterSelf()
		A():Register{ guid = ALT, name = "Altone", classID = 5, level = 20 }
		A():Register{ guid = ALT2, name = "Gone", classID = 5, level = 20 }
	end

	it("follows a rename when the client knows the character", function()
		twoAlts()
		Mock.playerInfo[ALT] = { name = "Renamed", level = 25 }
		A():Prune()
		eq(cfg().chars.TestRealm[ALT].name, "Renamed")
		eq(cfg().chars.TestRealm[ALT].level, 25)
	end)

	it("drops a character the client has not answered for in 30 days, once the API has proved it can answer", function()
		twoAlts()
		Mock.playerInfo[ALT] = { name = "Altone" }
		Mock.SetServerTime(GetServerTime() + 31 * DAY)
		eq(A():Prune(), 1)
		notNil(cfg().chars.TestRealm[ALT])
		isNil(cfg().chars.TestRealm[ALT2])
		notNil(cfg().chars.TestRealm[ME])
	end)

	it("keeps a character that has been silent for less than 30 days", function()
		twoAlts()
		Mock.playerInfo[ALT] = { name = "Altone" }
		Mock.SetServerTime(GetServerTime() + 20 * DAY)
		eq(A():Prune(), 0)
		notNil(cfg().chars.TestRealm[ALT2])
	end)

	it("never drops anything while the client has not answered for any other character", function()
		twoAlts()
		Mock.SetServerTime(GetServerTime() + 90 * DAY)
		eq(A():Prune(), 0)
		notNil(cfg().chars.TestRealm[ALT])
		Mock.playerInfo.disabled = true
		eq(A():Prune(), 0)
	end)

	it("a silent character is kept alive by answering again", function()
		twoAlts()
		Mock.playerInfo[ALT] = { name = "Altone" }
		Mock.SetServerTime(GetServerTime() + 25 * DAY)
		A():Prune()
		Mock.SetServerTime(GetServerTime() + 25 * DAY)
		eq(A():Prune(), 1, "only the one that never answered")
		notNil(cfg().chars.TestRealm[ALT])
	end)
end)

describe("the groups of other players (mutual listing)", function()
	before_boot(function(M) guild() end)

	it("groups two characters that list each other, main first", function()
		bobAccount()
		local g = A():GroupOf(BOB)
		eq(A():GroupOf(BOBALT), g)
		eq(#g.members, 2)
		eq(g.main, BOB)
		eq(g.mainSource, "default")
		deepEq(names(A():Alts(BOBALT)), { "Bob" })
		eq(A():MainOf(BOBALT).guid, BOB)
		eq(g.token, "BOBTOKEN")
		falsy(g.conflict)
	end)

	it("does not group a character that lists another without being listed back (a forged list)", function()
		bobAccount()
		-- Mallory publishes a record that lists Bob and copies his token: Bob's record does not list her
		truthy(accept(acct(MAL, { MAL, { guid = BOB, name = "Bob" } }, { token = "BOBTOKEN" }), "Mallory"))
		eq(#A():GroupOf(BOB).members, 2)
		falsy(A():GroupOf(BOB).byGUID[MAL])
		eq(#A():GroupOf(MAL).members, 1, "Mallory is alone in her own group: nothing is mutual")
		deepEq(names(A():Alts(MAL)), {})
	end)

	it("refuses a record for somebody else's character at the Store, so it cannot reach the groups", function()
		bobAccount()
		local why = select(2, accept(acct(BOB, { BOB, MAL }, { token = "X", rev = 9 }), "Mallory"))
		eq(why, "relay")
		eq(#A():GroupOf(BOB).members, 2)
	end)

	it("shows characters outside the guild as claimed by the members who list them (ACC-03)", function()
		truthy(accept(acct(BOB, { { guid = BOB, name = "Bob", level = 60 }, { guid = OUT, name = "Elsewhere", level = 12, classID = 3 } }), "Bob"))
		local g = A():GroupOf(BOB)
		eq(#g.members, 2)
		local out = g.byGUID[OUT]
		truthy(out.claimed); falsy(out.inGuild)
		eq(out.name, "Elsewhere"); eq(out.level, 12)
		eq(A():GroupOf(OUT), g)
	end)

	it("ignores a guild member who is listed but does not list back", function()
		truthy(accept(acct(BOB, { BOB, { guid = BOBALT, name = "Bobalt" } }), "Bob"))
		falsy(A():GroupOf(BOB).byGUID[BOBALT])
		isNil(A():GroupOf(BOBALT))
	end)

	it("takes the main from the newest record that names a member, else the highest level", function()
		bobAccount()
		eq(A():GroupOf(BOB).mainSource, "default")
		truthy(accept(acct(BOBALT, { { guid = BOBALT, name = "Bobalt", level = 30 }, { guid = BOB, name = "Bob", level = 60 } },
			{ token = "BOBTOKEN", main = BOBALT, rev = 2, time = GetServerTime() + 5 }), "Bobalt"))
		local g = A():GroupOf(BOB)
		eq(g.main, BOBALT); eq(g.mainSource, "chosen")
		truthy(A():MainOf(BOB).isMain)
		truthy(accept(acct(BOB, { { guid = BOB, name = "Bob", level = 60 }, { guid = BOBALT, name = "Bobalt", level = 30 } },
			{ token = "BOBTOKEN", main = MAL, rev = 2, time = GetServerTime() + 9 }), "Bob"))
		eq(A():GroupOf(BOB).main, BOB, "a main that is not a member of the group is ignored")
	end)

	it("marks a group whose members publish different tokens", function()
		truthy(accept(acct(BOB, { BOB, BOBALT }, { token = "ONE" }), "Bob"))
		truthy(accept(acct(BOBALT, { BOBALT, BOB }, { token = "TWO" }), "Bobalt"))
		truthy(A():GroupOf(BOB).conflict)
	end)

	it("uses the roster's own name and level, and rebuilds after a store change", function()
		bobAccount()
		eq(A():GroupOf(BOB).byGUID[BOBALT].level, 30)
		local seen = 0
		AzerothAccord.Bus:On("ACCOUNTS_UPDATED", function() seen = seen + 1 end)
		A():Groups()
		eq(seen, 0)
		truthy(accept(acct(BOB, { { guid = BOB, name = "Bob", level = 61 }, { guid = BOBALT, name = "Bobalt" } }, { rev = 2, token = "BOBTOKEN" }), "Bob"))
		A():Groups()
		eq(seen, 1)
		eq(A():GroupOf(BOB).byGUID[BOB].level, 60, "the roster wins over what the record says")
	end)

	it("is empty without records", function()
		eq(#A():Groups(), 0)
		isNil(A():GroupOf(BOB))
		isNil(A():MainOf(BOB))
		isNil(A():TokenOf(BOB))
	end)

	it("reports itself in /accord debug without names", function()
		bobAccount()
		local text = table.concat(A():DebugLines(), "\n")
		matches(text, "1 group%(s%)")
		falsy(text:find("Bob", 1, true))
	end)
end)

describe("ACC-05: hints from public notes", function()
	it("reads 'main: Name' and 'alt: Name' at the start of a note", function()
		local P = AzerothAccord.Accounts.ParseNote
		deepEq({ P("main: Bob") }, { "main", "Bob" })
		deepEq({ P("Alt: Bobby - tank") }, { "alt", "Bobby" })
		deepEq({ P("  ALT : Bob-Realm, healer") }, { "alt", "Bob-Realm" })
		deepEq({ P("main:Bob.") }, { "main", "Bob" })
		isNil(P("my main is Bob"))
		isNil(P("maintank: Bob"))
		isNil(P("altoholic"))
		isNil(P(""))
		isNil(P(nil))
		isNil(P("main:"))
	end)

	before_boot(function(M)
		guild{ { name = "Hinted", level = 15, rank = 4, note = "main: Bob" }, { name = "Declarer", level = 40, rank = 3, note = "alt: Bobalt" },
			{ name = "Lost", level = 10, rank = 4, note = "alt: Nobody" } }
	end)

	it("groups a member with a note under the member it names, marked as a hint", function()
		local g = A():GroupOf(Mock.guild.members[6].guid)   -- Hinted
		notNil(g)
		eq(#g.members, 2)
		local hinted = g.byGUID[Mock.guild.members[6].guid]
		truthy(hinted.hint)
		eq(g.main, BOB)
		eq(g.mainSource, "hint")
		eq(A():MainOf(Mock.guild.members[6].guid).name, "Bob")
	end)

	it("'alt: Name' makes the writer the main and the named member its alt", function()
		local declarer = Mock.guild.members[7].guid
		local g = A():GroupOf(declarer)
		eq(g.main, declarer)
		truthy(g.byGUID[BOBALT])
	end)

	it("adds to the group of a member who has the addon, and ignores an unknown name", function()
		bobAccount()
		local hinted = Mock.guild.members[6].guid
		local g = A():GroupOf(hinted)
		eq(g, A():GroupOf(BOB))
		eq(#g.members, 4, "Bob, Bobalt, Hinted ('main: Bob') and Declarer ('alt: Bobalt')")
		isNil(A():GroupOf(Mock.guild.members[8].guid))
	end)

	it("never overrides a character that has its own record", function()
		bobAccount()
		truthy(accept(acct(ALT, { ALT }), "Altone"))
		Mock.guild.members[1].note = "main: Altone"   -- Bob's note says something else
		Mock.Fire("GUILD_ROSTER_UPDATE")
		local g = A():GroupOf(BOB)
		falsy(g.byGUID[ALT])
	end)
end)

-----------------------------------------------------------------------------------------------------------------------
-- Several clients (Tests/sim): the third client sees the alts of two accounts grouped
-----------------------------------------------------------------------------------------------------------------------
local TOKEN_X, TOKEN_Y = "XXXXXXXXXXXXXXXXXXXXXXXX", "YYYYYYYYYYYYYYYYYYYYYYYY"

-- a and b (client indexes) are characters of one account: each client knows both in its account-wide saved data
local function link(sim, token, ...)
	local idx = { ... }
	for _, i in ipairs(idx) do
		local c = sim:client(i)
		c:addon().Config.db.account.token = token
		for _, j in ipairs(idx) do
			c:addon().Accounts:Register{ guid = Sim.guidOf(j), name = Sim.nameOf(j), realm = "TestRealm", classID = 1, level = 60 - j }
		end
	end
end

describe("alts of simulated accounts", function()
	it("two accounts of two characters are grouped on a third client, and a forged list is refused", function()
		local sim = Sim.new{ clients = 6, officers = { 1 }, seed = 11, latency = { 0.05, 0.3 }, accounts = true }
		link(sim, TOKEN_X, 1, 2)
		link(sim, TOKEN_Y, 3, 4)
		-- client 6 is a modified addon: it lists client 1 and copies account X's token (client 1 never lists it back)
		local forger = sim:client(6):addon()
		forger.Config.db.account.token = TOKEN_X
		forger.Accounts:Register{ guid = Sim.guidOf(1), name = Sim.nameOf(1), realm = "TestRealm", classID = 1, level = 59 }
		local observer = sim:client(5):addon()
		local ok, took = sim:advanceUntil(function()
			local gx, gy = observer.Accounts:GroupOf(Sim.guidOf(1)), observer.Accounts:GroupOf(Sim.guidOf(3))
			return gx ~= nil and #gx.members >= 2 and gy ~= nil and #gy.members >= 2 and observer.Store:Get("accounts", Sim.guidOf(6)) ~= nil
		end, 180)
		truthy(ok, "the observer received the records")
		truthy(took < 120, "took " .. took .. " s")
		local gx, gy = observer.Accounts:GroupOf(Sim.guidOf(1)), observer.Accounts:GroupOf(Sim.guidOf(3))
		eq(#gx.members, 2); eq(#gy.members, 2)
		eq(observer.Accounts:GroupOf(Sim.guidOf(2)), gx)
		eq(observer.Accounts:GroupOf(Sim.guidOf(4)), gy)
		ne(gx, gy)
		eq(gx.main, Sim.guidOf(1)); eq(gy.main, Sim.guidOf(3))
		eq(gx.token, TOKEN_X); eq(gy.token, TOKEN_Y)
		falsy(gx.byGUID[Sim.guidOf(6)], "the forger is not in account X")
		-- the forger has a record of its own (it is a member), alone in its group: it did not become an alt of client 1
		eq(#observer.Accounts:GroupOf(Sim.guidOf(6)).members, 1)
		eq(#observer.Accounts:Alts(Sim.guidOf(2)), 1)
		eq(observer.Accounts:Alts(Sim.guidOf(2))[1].guid, Sim.guidOf(1))
	end)

	it("the same grouping holds on every client after a logout and login of an alt", function()
		local sim = Sim.new{ clients = 5, seed = 4, latency = 0.1, accounts = true }
		link(sim, TOKEN_X, 1, 2)
		sim:advance(60)
		sim:client(2):logout()
		sim:advance(120)
		sim:client(2):login()
		sim:advance(60)
		for _, i in ipairs({ 1, 2, 3, 4, 5 }) do
			local g = sim:client(i):addon().Accounts:GroupOf(Sim.guidOf(1))
			notNil(g, "client " .. i)
			eq(#g.members, 2, "client " .. i)
		end
	end)
end)

describe("the cost of the account records (SPEC-02 §4 budget)", function()
	it("30 clients that all publish their own record converge and stay quiet afterwards", function()
		local N = 30
		local sim = Sim.new{ clients = N, officers = { 1, 2 }, seed = 23, latency = { 0.05, 0.4 }, accounts = true }
		for i = 1, N, 2 do link(sim, ("%024d"):format(i), i, i + 1) end   -- 15 accounts of two characters
		local function complete()
			for i = 1, N do
				local S = sim:client(i):addon().Store
				for j = 1, N do if not S:Get("accounts", Sim.guidOf(j)) then return false end end
			end
			return true
		end
		local ok, took = sim:advanceUntil(complete, 10 * 60)
		truthy(ok, "every client holds the 30 records")
		truthy(took <= 5 * 60, "took " .. took .. " s")
		for i = 1, N do eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing") end
		sim:advance(120)
		sim:resetStats()
		sim:advance(25 * 60)
		local steady = sim:stats()
		T.log(("30 clients, account records: converged after %.0f s; steady %.0f B/min per client on average, %.0f at most"):format(
			took, steady.avg.bytesPerMinute, steady.max.bytesPerMinute))
		truthy(steady.avg.bytesPerMinute <= 100, "steady average " .. steady.avg.bytesPerMinute)
		truthy(steady.max.bytesPerMinute <= 200, "steady busiest client " .. steady.max.bytesPerMinute)
		local g = sim:client(N):addon().Accounts:GroupOf(Sim.guidOf(1))
		eq(#g.members, 2)
	end)
end)

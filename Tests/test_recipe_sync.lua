-- Recipe sync (M3.3; SPEC-06, SPEC-02 §4): the shared lists in the store, the lookup that puts the native answer before the
-- shared list, the on-demand request when a view needs a member's list, and a recipe list reaching 20 clients inside the
-- traffic budget (network simulator).
local function A() return AzerothAccord end
local function R() return AzerothAccord.Recipes end
local function S() return AzerothAccord.Store end

local ME, BOB, ANN = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44"
local ALCHEMY, SMITHING = 171, 164

local function put(guid, line, ids, extra)
	local id = guid .. ":" .. line
	local old = S():Get("recipes", id)
	local rec = { id = id, author = guid, rev = (old and old.rev or 0) + 1, time = GetServerTime(), char = guid, skillLine = line,
		name = "Alchemy", rank = 200, maxRank = 300, ids = R().Encode(ids), n = #ids }
	for k, v in pairs(extra or {}) do rec[k] = v end
	S():Records("recipes")[id] = rec
	return rec
end

describe("the shared list in the lookup", function()
	before_boot(function()
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB },
			{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN },
		} }
	end)

	it("returns the decoded shared list with its source, age, rank and name", function()
		put(BOB, ALCHEMY, { 2332, 2330, 3447 })
		local e = R():Lookup(BOB, ALCHEMY)
		deepEq(e.ids, { 2330, 2332, 3447 })
		eq(e.source, "shared"); eq(e.time, GetServerTime()); eq(e.rank, 200); eq(e.maxRank, 300); eq(e.name, "Alchemy"); eq(e.n, 3)
		isNil(R():Lookup(BOB, SMITHING)); isNil(R():Lookup(ANN, ALCHEMY))
	end)

	it("the native answer wins over the shared list, and carries the age of the shared one too", function()
		put(BOB, ALCHEMY, { 2330 })
		Mock.tradeskill.guildEnabled = true
		Mock.tradeskill.guildRecipes = { [BOB] = { [ALCHEMY] = { 2330, 2332, 3447, 4000 } } }
		R():RequestNative(BOB, ALCHEMY)
		Mock.Advance(0.5)
		local e = R():Lookup(BOB, ALCHEMY)
		eq(e.source, "native"); eq(#e.ids, 4)
		eq(e.sharedTime, GetServerTime()); eq(e.rank, 200)
	end)

	it("falls back to the shared list when the native source is off or has no answer", function()
		put(BOB, ALCHEMY, { 2330, 2332 })
		Mock.tradeskill.guildEnabled = false
		eq(R():Lookup(BOB, ALCHEMY).source, "shared")
	end)

	it("the player's own list is the own scan and says so", function()
		put(ME, ALCHEMY, { 2330, 2332 })
		eq(R():Lookup(ME, ALCHEMY).source, "own")
		eq(#Mock.tradeskill.queries, 0, "the directory is never asked about the own character")
	end)

	it("a record that cannot be read, or was deleted, gives nothing and raises nothing", function()
		put(BOB, ALCHEMY, { 2330 }, { ids = "not base64!" })
		isNil(R():Lookup(BOB, ALCHEMY))
		put(BOB, SMITHING, { 2660 }, { del = true })
		isNil(R():Lookup(BOB, SMITHING))
		put(ANN, ALCHEMY, { 2330 }, { ids = { 2332, 2330 } })
		deepEq(R():Lookup(ANN, ALCHEMY).ids, { 2330, 2332 }, "a list of ids is read too")
	end)

	it("decodes a list once per revision", function()
		put(BOB, ALCHEMY, { 2330, 2332 })
		local first = R():Lookup(BOB, ALCHEMY).ids
		eq(R():Lookup(BOB, ALCHEMY).ids, first, "the same table")
		put(BOB, ALCHEMY, { 2330, 2332, 3447 })
		eq(#R():Lookup(BOB, ALCHEMY).ids, 3, "a new revision is decoded again")
	end)

	it("lists the professions a member shared, by skill line", function()
		put(BOB, SMITHING, { 2660 }, { name = "Blacksmithing" })
		put(BOB, ALCHEMY, { 2330, 2332 })
		put(ANN, ALCHEMY, { 2330 })
		local list = R():ProfessionsOf(BOB)
		eq(#list, 2)
		eq(list[1].skillLine, SMITHING); eq(list[1].name, "Blacksmithing"); eq(list[1].n, 1)
		eq(list[2].skillLine, ALCHEMY); eq(list[2].n, 2); eq(list[2].rank, 200)
		deepEq(R():ProfessionsOf("nobody"), {})
	end)

	it("tells the views when a record arrives, from the store", function()
		local heard = {}
		A().Bus:On("RECIPES_UPDATED", function(guid, line, source) heard[#heard + 1] = { guid, line, source } end)
		local rec = put(BOB, ALCHEMY, { 2330 })
		A().Bus:Emit("STORE_CHANGED", "recipes", rec.id, "remote")
		A().Bus:Emit("STORE_CHANGED", "contacts", BOB, "remote")
		deepEq(heard, { { BOB, ALCHEMY, "shared" } })
	end)
end)

describe("a view asks for a list (Ensure)", function()
	before_boot(function()
		Mock.guild.Set{ name = "Accord", myRank = 3, members = { { name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB } } }
	end)

	it("says what each source did: no native source, nobody to ask for the shared list", function()
		local r = R():Ensure(BOB, ALCHEMY)
		eq(r.native, "unavailable"); eq(r.shared, "nobody")
	end)

	it("a shared list that is already here is not asked again, a stale one is", function()
		put(BOB, ALCHEMY, { 2330 })
		eq(R():Ensure(BOB, ALCHEMY).shared, "have")
		A().Sync.state.present = {}
		Mock.SetServerTime(GetServerTime() + R().SHARED_REFRESH + 10)
		eq(R():Ensure(BOB, ALCHEMY).shared, "nobody", "old: it would be asked for again, but nobody is there")
	end)

	it("asks the native source too when it is usable", function()
		Mock.tradeskill.guildEnabled = true
		Mock.tradeskill.guildRecipes = { [BOB] = { [ALCHEMY] = { 2330 } } }
		eq(R():Ensure(BOB, ALCHEMY).native, "queued")
		Mock.Advance(0.5)
		eq(R():Ensure(BOB, ALCHEMY).native, "cached")
	end)

	it("the own character needs no request", function()
		local r = R():Ensure(ME, ALCHEMY)
		eq(r.native, "self"); eq(r.shared, "own")
	end)
end)

describe("asking for one set of one author (Sync:RequestSet)", function()
	local function recipeRecord(c, ids, line)
		local S2, guid = c:addon().Store, c:guid()
		local rec = S2:Put("recipes", guid .. ":" .. (line or ALCHEMY), { char = guid, skillLine = line or ALCHEMY, name = "Alchemy", rank = 250,
			maxRank = 300, ids = c:addon().Recipes.Encode(ids), n = #ids })
		truthy(rec)
		return rec
	end

	local function numbers(n) local t = {} for i = 1, n do t[i] = 2000 + i * 3 end return t end

	-- Client `victim` hears the others' HELLOs (so it knows who is there) but no GUILD record, and its own HELLOs are lost, so
	-- nobody pushes to it: only a request can bring it the list.
	local function deaf(victim)
		return function(from, to, entry)
			if to.index == victim and entry.chatType == "GUILD" and entry.message:find("|REC|", 1, true) then return true end
			return from.index == victim and entry.chatType == "GUILD" and entry.message:find("|HELLO|", 1, true) ~= nil
		end
	end

	it("sends one small WHISPER REQ to the author when it is online, and gets the author's records of that set only", function()
		local sim = Sim.new{ clients = 4, seed = 31, loss = deaf(3) }
		recipeRecord(sim:client(1), numbers(120))
		sim:client(1):addon().Store:Put("contacts", sim:client(1):guid(), { battleTag = "One#1" })
		sim:advance(40)
		local c3 = sim:client(3):addon()
		isNil(c3.Store:Get("recipes", sim:client(1):guid() .. ":171"), "the broadcast never reached client 3")
		sim:resetStats()
		local status, name = c3.Sync:RequestSet("recipes", sim:client(1):guid())
		eq(status, "sent"); eq(name, Sim.nameOf(1))
		local ok = sim:advanceUntil(function() return c3.Store:Get("recipes", sim:client(1):guid() .. ":171") ~= nil end, 10)
		truthy(ok, "the answer arrived")
		isNil(c3.Store:Get("contacts", sim:client(1):guid()), "only the set that was asked for")
		deepEq(c3.Recipes:Lookup(sim:client(1):guid(), ALCHEMY).ids, numbers(120))
		eq(sim:client(1):addon().Sync.state.stats.asksAnswered, 1)
		local st = sim:stats()
		eq(st.byDist.GUILD.msgs, 0, "nothing was broadcast")
		truthy(st.sent.bytes < 1200, "the request and its answer: " .. st.sent.bytes .. " bytes")
	end)

	it("the same request is not repeated within five minutes, and an unknown set or author is refused", function()
		local sim = Sim.new{ clients = 3, seed = 33, loss = deaf(3) }
		recipeRecord(sim:client(1), numbers(10))
		sim:advance(40)
		local Sync = sim:client(3):addon().Sync
		eq(Sync:RequestSet("recipes", sim:client(1):guid()), "sent")
		eq(Sync:RequestSet("recipes", sim:client(1):guid()), "recent")
		sim:advance(Sync.ASK_COOLDOWN + 1)
		eq(Sync:RequestSet("recipes", sim:client(1):guid()), "sent")
		eq(Sync:RequestSet("nonsense", sim:client(1):guid()), "invalid")
		eq(Sync:RequestSet("recipes", nil), "invalid")
		eq(Sync:RequestSet("recipes", sim:client(3):guid()), "own")
	end)

	it("with the author offline an officer is asked and answers from the copy it holds", function()
		local sim = Sim.new{ clients = 5, officers = { 2 }, seed = 35, loss = deaf(4) }
		recipeRecord(sim:client(1), numbers(30))
		sim:advance(60)
		truthy(sim:client(2):addon().Store:Get("recipes", sim:client(1):guid() .. ":171"), "the officer holds the record")
		sim:client(1):logout()
		sim:advance(40)
		local c4 = sim:client(4):addon()
		isNil(c4.Store:Get("recipes", sim:client(1):guid() .. ":171"))
		local status, name = c4.Sync:RequestSet("recipes", sim:client(1):guid())
		eq(status, "sent"); eq(name, Sim.nameOf(2))
		local ok = sim:advanceUntil(function() return c4.Store:Get("recipes", sim:client(1):guid() .. ":171") ~= nil end, 10)
		truthy(ok, "relayed by the officer")
		eq(c4.Store.stats.rejected, 0)
	end)

	it("nobody online that may deliver means nothing is sent, and the next try is not held back", function()
		local sim = Sim.new{ clients = 3, seed = 37, loss = deaf(3) }
		recipeRecord(sim:client(1), numbers(10))
		sim:advance(40)
		sim:client(1):logout()
		sim:advance(40)
		local Sync = sim:client(3):addon().Sync
		eq(Sync:RequestSet("recipes", sim:client(1):guid()), "nobody", "client 2 is a member, not an officer: it never relays")
		sim:resetStats()
		sim:advance(5)
		eq(sim:stats().byDist.WHISPER.msgs, 0)
		sim:client(1):login()
		sim:advance(60)   -- its HELLO tells client 3 that it is back
		eq(Sync:RequestSet("recipes", sim:client(1):guid()), "sent")
	end)

	it("a member that is not an officer does not answer for somebody else's records", function()
		local sim = Sim.new{ clients = 3, seed = 39 }
		recipeRecord(sim:client(1), numbers(10))
		sim:advance(40)
		sim:client(1):logout()
		sim:advance(20)
		-- client 3 sends the request straight to client 2, a plain member holding a copy
		local Transport = sim:client(3):addon().Transport
		Transport:Send("WHISPER", { t = "REQ", s = "recipes", a = { sim:client(3):addon().Sync.KeyOf(sim:client(1):guid()) } },
			{ target = Sim.nameOf(2) })
		sim:advance(10)
		eq(sim:client(2):addon().Sync.state.stats.asksAnswered, 0)
	end)

	it("answers at most 20 set requests per minute to one sender", function()
		local sim = Sim.new{ clients = 2, seed = 41 }
		recipeRecord(sim:client(1), numbers(5))
		sim:advance(40)
		local c2, key = sim:client(2):addon(), sim:client(2):addon().Sync.KeyOf(sim:client(1):guid())
		for i = 1, 30 do
			c2.Transport:Send("WHISPER", { t = "REQ", s = "recipes", a = { key } }, { target = Sim.nameOf(1), key = "x" .. i })
		end
		sim:advance(30)
		local st = sim:client(1):addon().Sync.state.stats
		eq(st.asksAnswered, 20)
		eq(st.asksLimited, 10)
	end)

	it("a request for every set ('*') still gets the GUILD answer for everyone", function()
		local sim = Sim.new{ clients = 3, seed = 43, loss = deaf(3) }
		recipeRecord(sim:client(1), numbers(10))
		sim:advance(40)
		local c3 = sim:client(3):addon()
		c3.Transport:Send("WHISPER", { t = "REQ", s = "*", a = { c3.Sync.KeyOf(sim:client(1):guid()) } }, { target = Sim.nameOf(1) })
		sim:advance(10)
		truthy(sim:client(1):addon().Sync.state.stats.answers >= 1, "answered on GUILD")
		eq(sim:client(1):addon().Sync.state.stats.asksAnswered, 0, "and not as a set request")
	end)
end)

describe("a recipe list reaches the whole guild inside the traffic budget (M3.3)", function()
	-- client 1 owns 1500-line-class professions: a 400-recipe Alchemy list as the profession window reports it
	local function bigList()
		local ids, id, seed = {}, 2000, 12345
		for i = 1, 400 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			id = id + 1 + math.floor(seed / 65536) % 1500   -- gaps of 1 to 1500: one or two varint bytes
			ids[i] = id
		end
		return ids
	end

	it("one scan of one member reaches 20 clients, in one or two messages and a few KB for the whole guild", function()
		local ids = bigList()
		local sim = Sim.new{ clients = 20, officers = { 1, 11 }, latency = { 0.05, 0.5 }, seed = 47, setup = function(M, i)
			if i == 1 then
				M.tradeskill.AddAllRecipeIDs()
				M.tradeskill.own = { { name = "Alchemy", skillLine = ALCHEMY, rank = 285, maxRank = 300, recipes = ids } }
			end
		end }
		sim:advance(60)   -- the first HELLOs go by
		sim:resetStats()
		sim:client(1).Mock.tradeskill.open = 1
		sim:client(1).Mock.Fire("TRADE_SKILL_SHOW")
		local ok, took = sim:advanceUntil(function()
			for i = 1, 20 do
				if not sim:client(i):addon().Store:Get("recipes", sim:client(1):guid() .. ":171") then return false end
			end
			return true
		end, 60)
		truthy(ok, "all 20 clients hold the list")
		local st = sim:stats()
		for i = 2, 20 do
			local e = sim:client(i):addon().Recipes:Lookup(sim:client(1):guid(), ALCHEMY)
			deepEq(e.ids, ids, "client " .. i)
			eq(e.source, "shared"); eq(e.rank, 285)
			eq(sim:client(i):addon().Store.stats.rejected, 0)
		end
		T.log(("list of 400 recipes: %.1f s to reach 20 clients, %d message(s), %d bytes sent in all"):format(took, st.sent.msgs, st.sent.bytes))
		truthy(took <= 15, "took " .. took)
		truthy(st.perClient[1].sent.bytes <= 2500, "the author sent " .. st.perClient[1].sent.bytes .. " bytes")
		truthy(st.sent.bytes <= 4000, "the whole guild sent " .. st.sent.bytes .. " bytes")
	end)

	it("a client that logs in later gets it from the author's account or an officer, inside the login budget", function()
		local ids = bigList()
		local sim = Sim.new{ clients = 20, officers = { 1, 11 }, offline = { 20 }, latency = { 0.05, 0.5 }, seed = 49, setup = function(M, i)
			if i == 1 then
				M.tradeskill.AddAllRecipeIDs()
				M.tradeskill.own = { { name = "Alchemy", skillLine = ALCHEMY, rank = 285, maxRank = 300, recipes = ids } }
			end
		end }
		sim:advance(60)
		sim:client(1).Mock.tradeskill.open = 1
		sim:client(1).Mock.Fire("TRADE_SKILL_SHOW")
		sim:advance(30)
		sim:resetStats()
		sim:client(20):login()
		local c20 = sim:client(20):addon()
		local ok, took = sim:advanceUntil(function() return c20.Store:Get("recipes", sim:client(1):guid() .. ":171") ~= nil end, 120)
		truthy(ok, "the late client got the list")
		deepEq(c20.Recipes:Lookup(sim:client(1):guid(), ALCHEMY).ids, ids)
		sim:advance(30)
		local st = sim:stats()
		T.log(("late login with a 400-recipe list in the guild: %.0f s, %.1f KB for the whole guild"):format(took, st.sent.bytes / 1024))
		truthy(st.sent.bytes <= 8 * 1024, "within the 8 KB cost of a login (SPEC-02 §4): " .. st.sent.bytes)
	end)

	it("a list that did not change adds no traffic at all", function()
		local ids = bigList()
		local sim = Sim.new{ clients = 10, officers = { 1 }, seed = 51, setup = function(M, i)
			if i == 1 then
				M.tradeskill.AddAllRecipeIDs()
				M.tradeskill.own = { { name = "Alchemy", skillLine = ALCHEMY, rank = 285, maxRank = 300, recipes = ids } }
			end
		end }
		sim:advance(60)
		sim:client(1).Mock.tradeskill.open = 1
		sim:client(1).Mock.Fire("TRADE_SKILL_SHOW")
		sim:advance(60)
		sim:resetStats()
		for _ = 1, 5 do
			sim:client(1).Mock.Fire("TRADE_SKILL_LIST_UPDATE")
			sim:advance(30)
		end
		eq(sim:client(1):addon().Store:Get("recipes", sim:client(1):guid() .. ":171").rev, 1)
		local st = sim:stats()
		truthy(st.sent.bytes < 1500, "only the regular HELLOs: " .. st.sent.bytes)
	end)
end)

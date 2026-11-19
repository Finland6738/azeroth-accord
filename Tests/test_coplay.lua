-- CoPlay (M2.6; SPEC-07 §3.1 SOC-01..03, ADR 0008): one minute every 60 s to every pair of guild members in the group,
-- per realm day, published hourly in chunks, merged with the maximum, kept 90 days. No view: only /accord debug counts.
local function A() return AzerothAccord end
local function P() return AzerothAccord.CoPlay end
local function S() return AzerothAccord.Store end

local ME = "Player-1-0000A001"
local function g(i) return ("Player-1-%08X"):format(0x7000 + i) end

local function guild(n)
	local list = {}
	for i = 1, n or 6 do list[i] = { name = "G" .. i, level = 60, class = "MAGE", rank = 3, guid = g(i) } end
	list[#list + 1] = { name = "Officer", rank = 1, guid = "Player-1-000000FF" }
	Mock.guild.Set{ name = "Accord", myRank = 3, members = list }
end

-- the other members of the party: guild members G<i> (inGuild) and strangers
local function party(guildIds, strangers, raid)
	local members = {}
	for _, i in ipairs(guildIds) do members[#members + 1] = { name = "G" .. i, guid = g(i), inGuild = true } end
	for i = 1, strangers or 0 do members[#members + 1] = { name = "Stranger" .. i, guid = "Player-9-" .. ("%08X"):format(i), inGuild = false } end
	Mock.group.Set{ raid = raid, members = members }
end

local function day() return A().Compat.ServerDay() end

local function minutes(a, b)
	local d = P().state.days[day()]
	return d and d.pairs[P().PairKey(a, b)] or 0
end

local function pairCount()
	local n = 0
	for _ in pairs(P().state.days[day()].pairs) do n = n + 1 end
	return n
end

describe("SOC-01: the count", function()
	before_boot(function() guild() end)

	it("adds a minute to every pair of the guild members in the group, the player included", function()
		party({ 1, 2 })
		eq(P():Tick(), 3)
		eq(minutes(ME, g(1)), 1); eq(minutes(ME, g(2)), 1); eq(minutes(g(1), g(2)), 1)
		P():Tick()
		eq(minutes(g(1), g(2)), 2)
		eq(pairCount(), 3)
	end)

	it("writes the pair with the two GUIDs in order", function()
		eq(P().PairKey("b", "a"), "a:b")
		eq(P().PairKey("a", "b"), "a:b")
	end)

	it("leaves out members who are not in the guild, and counts nothing for a group of strangers", function()
		party({ 1 }, 2)
		eq(P():Tick(), 1)
		eq(minutes(ME, g(1)), 1)
		party({}, 3)
		eq(P():Tick(), 0)
	end)

	it("counts nothing alone, or without a guild", function()
		Mock.group.Leave()
		eq(P():Tick(), 0)
		party({ 1 })
		Mock.guild.Leave()
		eq(P():Tick(), 0)
	end)

	it("counts in a raid, and inside instances (SOC-02)", function()
		party({ 1, 2, 3, 4 }, 3, true)
		eq(P():Tick(), 10)
		Mock.group.secretGUIDs = false
		eq(pairCount(), 10)
	end)

	it("does not guess when GUIDs and names are hidden (secret values in an instance)", function()
		party({ 1, 2 })
		Mock.group.secretGUIDs = true
		eq(P():Tick(), 0, "only the player is known")
		eq(P().state.unreadable, 2)
		Mock.group.secretGUIDs = false
		P():Tick()
		eq(P().state.unreadable, 2)
	end)

	it("identifies a member with a hidden GUID by name, through the guild roster", function()
		A().Compat.Group.Members = function()
			return { { name = "G1-TestRealm", guid = nil, inGuild = nil }, { name = "G2", guid = g(2), inGuild = nil }, { name = "Nobody", guid = nil, inGuild = nil } }
		end
		Mock.group.Set{ members = { { name = "x", guid = "Player-1-1" } } }
		eq(P():Tick(), 3)
		eq(minutes(ME, g(1)), 1)
		eq(P().state.unreadable, 1, "Nobody is in no roster")
	end)

	it("falls back to the roster when UnitIsInMyGuild is missing", function()
		UnitIsInMyGuild = nil
		party({ 1, 2 }, 1)
		eq(P():Tick(), 3)
	end)

	it("a pair cannot have more than a day of minutes", function()
		party({ 1 })
		P():Tick()
		P().state.days[day()].pairs[P().PairKey(ME, g(1))] = P().MAX_MINUTES
		eq(P():Tick(), 0)
		eq(minutes(ME, g(1)), P().MAX_MINUTES)
	end)

	it("tells the groupGUIDs capability that guild members can be told apart in a group", function()
		eq(A().Compat:Feature("groupGUIDs"), "unknown")
		party({ 1 })
		P():Tick()
		eq(A().Compat:Feature("groupGUIDs"), "available")
	end)

	it("counts by itself every 60 seconds once started", function()
		P().AUTO = true
		party({ 1 })
		truthy(P():Start())
		falsy(P():Start())
		Mock.Advance(59)
		eq(P().state.ticks, 0)
		Mock.Advance(2)
		eq(P().state.ticks, 1)
		Mock.Advance(120)
		eq(P().state.ticks, 3)
		eq(minutes(ME, g(1)), 3)
		P():Stop()
		Mock.Advance(300)
		eq(P().state.ticks, 3)
	end)
end)

describe("SOC-03: publishing", function()
	before_boot(function() guild(45) end)

	local function ids(prefix)
		local out = {}
		for id in pairs(S():Records("coplay")) do out[#out + 1] = id end
		table.sort(out)
		return out
	end

	it("writes the own record of the day with the observer, the day and the pairs; nothing before a publication", function()
		party({ 1, 2 })
		P():Tick()
		eq(#ids(), 0)
		eq(P():Publish(), 1)
		local rec = S():Get("coplay", ("%s:%d:1"):format(ME, day()))
		eq(rec.author, ME); eq(rec.observer, ME); eq(rec.day, day())
		eq(rec.pairs[P().PairKey(ME, g(1))], 1)
		eq(rec.rev, 1)
	end)

	it("rewrites only what changed", function()
		party({ 1 })
		P():Tick()
		P():Publish()
		eq(P():Publish(), 0)
		P():Tick()
		eq(P():Publish(), 1)
		eq(S():Get("coplay", ("%s:%d:1"):format(ME, day())).rev, 2)
	end)

	it("publishes hourly while counting, at logout and when the day changes", function()
		P().AUTO = true
		party({ 1 })
		P():Start()
		Mock.Advance(59 * 60)
		eq(#ids(), 0, "not before the hour")
		Mock.Advance(2 * 60)
		eq(#ids(), 1)
		local first = S():Get("coplay", ids()[1]).pairs[P().PairKey(ME, g(1))]
		Mock.Advance(10 * 60)
		Mock.Fire("PLAYER_LOGOUT")
		truthy(S():Get("coplay", ids()[1]).pairs[P().PairKey(ME, g(1))] > first)
		-- the next day: yesterday's last minutes go out at the first count
		P():Stop()
		local yesterday = day()
		P():Tick()
		Mock.SetServerTime(GetServerTime() + 86400)
		P():Tick()
		notNil(S():Get("coplay", ("%s:%d:1"):format(ME, yesterday)))
		eq(day() ~= yesterday, true)
		eq(P().state.days[yesterday].dirty, false)
	end)

	it("splits a big raid into chunks that fit, each with a pair of the observer (NET-13)", function()
		local members = {}
		for i = 1, 39 do members[i] = i end
		party(members, 0, true)
		eq(P():Tick(), 780)
		eq(P():Publish(), 8)
		local seen, total = {}, 0
		for _, id in ipairs(ids()) do
			local rec = S():Get("coplay", id)
			local n, mine = 0, false
			for key in pairs(rec.pairs) do
				n = n + 1
				if key:find(ME, 1, true) then mine = true end
				seen[key] = (seen[key] or 0) + 1
			end
			truthy(n <= P().CHUNK_PAIRS, id .. " has " .. n)
			truthy(mine, id .. " has no pair of the observer")
			truthy(A().Config.EstimateSize(rec) <= S().SETS.coplay.maxBytes, id .. " is too big")
			total = total + n
		end
		eq(total, 780)
		for _, c in pairs(seen) do eq(c, 1) end
		-- a second observer's client accepts every chunk
		for _, id in ipairs(ids()) do
			local _, why = S():Accept("coplay", S().Copy(S():Get("coplay", id)), { sender = "Testchar" })
			falsy(why == "observer", id .. " refused as an observation")
		end
	end)

	it("continues after a /reload from what was published", function()
		party({ 1 })
		for _ = 1, 5 do P():Tick() end
		P():Publish()
		Mock.Reload()
		party({ 1 })
		P():Tick()
		eq(minutes(ME, g(1)), 6)
	end)

	it("is not published without a guild", function()
		party({ 1 })
		P():Tick()
		Mock.guild.Leave()
		eq(P():Publish(), 0)
	end)

	it("keeps the records for 90 days", function()
		party({ 1 })
		P():Tick()
		P():Publish()
		Mock.SetServerTime(GetServerTime() + 91 * 86400)
		eq(S():Prune() >= 1, true)
		eq(#ids(), 0)
	end)

	it("reports itself in /accord debug, counts only", function()
		party({ 1 })
		P():Tick()
		local text = table.concat(P():DebugLines(), "\n")
		matches(text, "1 count%(s%), 1 with guild members, 1 pair%(s%) today")
		falsy(text:find("G1", 1, true)); falsy(text:find(ME, 1, true))
	end)
end)

describe("ADR 0008: observers are combined with the maximum", function()
	before_boot(function() guild() end)

	it("two observers of the same group give the maximum, not the sum", function()
		local key = P().PairKey(g(1), g(2))
		local function obs(observer, name, minutesSeen)
			return S():Accept("coplay", { id = observer .. ":" .. day() .. ":1", author = observer, observer = observer, rev = 1, time = GetServerTime(),
				day = day(), pairs = { [key] = minutesSeen } }, { sender = name })   -- both observers are in the pair
		end
		truthy(obs(g(1), "G1", 30))
		truthy(obs(g(2), "G2", 45))
		eq(P():Merged(day())[key], 45)
		-- the player's own observation of the same pair joins the maximum
		S():Records("coplay")[ME .. ":" .. day() .. ":1"] = { id = ME .. ":" .. day() .. ":1", author = ME, observer = ME, rev = 1,
			time = GetServerTime(), day = day(), pairs = { [key] = 20, [P().PairKey(ME, g(1))] = 3 } }
		eq(P():Merged(day())[key], 45)
	end)

	it("an observer who was not in the pair is refused", function()
		local key = P().PairKey(g(1), g(2))
		local ok, why = S():Accept("coplay", { id = g(3) .. ":" .. day() .. ":1", author = g(3), observer = g(3), rev = 1, time = GetServerTime(),
			day = day(), pairs = { [key] = 99 } }, { sender = "G3" })
		falsy(ok); eq(why, "observer")
	end)
end)

describe("three clients in one group (simulator)", function()
	it("each records the same minutes; every client merges them to one count, not three", function()
		local sim = Sim.new{ clients = 4, seed = 41, latency = { 0.05, 0.3 }, coplay = true }
		for i = 1, 3 do
			local c = sim:client(i)
			local others = {}
			for j = 1, 3 do
				if j ~= i then others[#others + 1] = { name = Sim.nameOf(j), guid = Sim.guidOf(j), inGuild = true } end
			end
			c.Mock.group.Set{ members = others }
		end
		sim:advance(10 * 60 + 5)
		for i = 1, 3 do sim:client(i).world.E.AzerothAccord.CoPlay:Publish() end
		sim:advance(30)
		local observer = sim:client(4):addon()
		local day = observer.Compat.ServerDay()
		local merged = observer.CoPlay:Merged(day)
		local key = observer.CoPlay.PairKey(Sim.guidOf(1), Sim.guidOf(2))
		eq(merged[key], 10, "ten minutes, not thirty")
		eq(observer.Store:Count("coplay"), 3, "three observers' records")
		eq(observer.Store.stats.rejected, 0)
		local count = 0
		for _ in pairs(merged) do count = count + 1 end
		eq(count, 3)
	end)
end)

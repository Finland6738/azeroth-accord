-- The group map (M4.6; SPEC-07 SOC-10..SOC-12, SPEC-10 Q3): weighted label propagation, modularity and its reading, the
-- communities with minutes inside and outside, the circle layout, and the Groups mode of the Reputation view for officers.
local function A() return AzerothAccord end
local function G() return AzerothAccord.GroupMap end
local function V() return AzerothAccord.GroupMapView end
local function S() return AzerothAccord.Store end

-- A symmetric graph from a list of { a, b, minutes }.
local function graph(edges)
	local g = {}
	for _, e in ipairs(edges) do
		g[e[1]] = g[e[1]] or {}
		g[e[2]] = g[e[2]] or {}
		g[e[1]][e[2]] = (g[e[1]][e[2]] or 0) + e[3]
		g[e[2]][e[1]] = (g[e[2]][e[1]] or 0) + e[3]
	end
	return g
end

-- Two triangles of 10-minute pairs joined by a 1-minute bridge.
local function twoTriangles()
	return graph({ { "a", "b", 10 }, { "b", "c", 10 }, { "a", "c", 10 }, { "d", "e", 10 }, { "e", "f", 10 }, { "d", "f", 10 }, { "c", "d", 1 } })
end

local function sets(communities)
	local out = {}
	for i, c in ipairs(communities) do
		local m = {}
		for j, k in ipairs(c.members) do m[j] = k end
		table.sort(m)
		out[i] = table.concat(m, "")
	end
	table.sort(out)
	return out
end

describe("communities and modularity", function()
	it("finds the two triangles", function()
		local g = twoTriangles()
		local labels = G().Propagate(g)
		deepEq(sets(G().Communities(g, labels)), { "abc", "def" })
	end)

	it("computes the modularity of the partition: Q = Σ L/m − (d/2m)²", function()
		local g = twoTriangles()
		local labels = G().Propagate(g)
		-- m = 61; each triangle: L = 30, d = 61 → Q = 2 × (30/61 − 1/4)
		near(G().Modularity(g, labels), 2 * (30 / 61 - 0.25), 1e-12)
		near(G().Modularity(g, labels), 0.483607, 1e-6)
	end)

	it("one community is a modularity of 0, and a graph without pairs too", function()
		local g = graph({ { "a", "b", 5 }, { "b", "c", 5 }, { "a", "c", 5 } })
		near(G().Modularity(g, { a = 1, b = 1, c = 1 }), 0, 1e-12)
		eq(G().Modularity({}, {}), 0)
		local m = G().Build(g)
		eq(#m.communities, 1)
		eq(m.mixing, "low")
	end)

	it("reads the modularity: low, medium, high", function()
		eq(G().Mixing(0.1), "low"); eq(G().Mixing(0.3), "medium"); eq(G().Mixing(0.49), "medium"); eq(G().Mixing(0.5), "high")
		eq(G().Build(twoTriangles()).mixing, "medium")
	end)

	it("counts the minutes inside each community (each pair once) and towards the others", function()
		local m = G().Build(twoTriangles())
		eq(#m.communities, 2)
		for _, c in ipairs(m.communities) do eq(c.inside, 30); eq(c.outside, 1) end
		eq(m.minutes, 61); eq(m.accounts, 6)
		eq(m.communities[1].members[1], "c", "the bridge player has the most minutes of its group")
	end)

	it("four separate cliques are cliques", function()
		local edges = {}
		for c = 0, 3 do
			local base = string.char(97 + c * 4)
			for i = 0, 3 do
				for j = i + 1, 3 do edges[#edges + 1] = { string.char(97 + c * 4 + i), string.char(97 + c * 4 + j), 60 } end
			end
		end
		edges[#edges + 1] = { "a", "e", 1 }
		local m = G().Build(graph(edges))
		eq(#m.communities, 4)
		eq(m.mixing, "high")
	end)

	it("is deterministic: the same data gives the same groups on every client", function()
		local a = G().Build(twoTriangles())
		local b = G().Build(graph({ { "d", "f", 10 }, { "c", "d", 1 }, { "e", "f", 10 }, { "a", "c", 10 }, { "b", "c", 10 }, { "d", "e", 10 }, { "a", "b", 10 } }))
		deepEq(a.labels, b.labels)
		eq(a.modularity, b.modularity)
	end)

	it("200 accounts in a few milliseconds", function()
		local edges = {}
		for i = 1, 200 do
			for k = 1, 6 do
				local j = (i * 7 + k * 31) % 200 + 1
				if j ~= i then edges[#edges + 1] = { ("P%03d"):format(i), ("P%03d"):format(j), (i + k) % 90 + 10 } end
			end
		end
		local t0 = Mock.RealClock()
		local m = G().Build(graph(edges))
		local ms = (Mock.RealClock() - t0) * 1000
		T.log(("group map of 200 accounts: %d communities in %d rounds, %.0f ms offline"):format(#m.communities, m.rounds, ms))
		truthy(ms < 2000)
	end)
end)

describe("the layout", function()
	it("puts each community on its own circle inside the box, larger for more players", function()
		local m = G().Build(graph({ { "a", "b", 10 }, { "b", "c", 10 }, { "a", "c", 10 }, { "a", "d", 10 }, { "x", "y", 5 } }))
		local lay = G().Layout(m.communities, 400, 200)
		eq(#lay.circles, 2)
		truthy(lay.circles[1].r > lay.circles[2].r)
		for key, p in pairs(lay.points) do
			truthy(p.x >= 0 and p.x <= 400 and p.y >= 0 and p.y <= 200, key)
		end
		local single = G().Layout({ { id = "z", members = { "z" } } }, 100, 100)
		eq(single.circles[1].r, 0)
		deepEq(G().Layout({}, 100, 100).circles, {})
	end)
end)

describe("the Groups mode", function()
	local ME = "Player-1-0000A001"
	local BOB, CAT, DAN, EVE = "Player-1-00000B0B", "Player-1-00000CA7", "Player-1-00000DA1", "Player-1-00000E0E"
	local function guild(rank)
		Mock.guild.Set{ name = "Accord", myRank = rank, members = {
			{ name = "Bob", class = "MAGE", rank = 3, guid = BOB }, { name = "Cat", class = "ROGUE", rank = 3, guid = CAT },
			{ name = "Dan", class = "HUNTER", rank = 3, guid = DAN }, { name = "Eve", class = "PRIEST", rank = 3, guid = EVE },
		} }
	end
	local function pk(a, b) if a > b then a, b = b, a end return a .. ":" .. b end
	local function data()
		S():Records("coplay")["x"] = { id = "x", author = ME, rev = 1, time = GetServerTime(), day = A().Compat.ServerDay(), observer = ME,
			pairs = { [pk(ME, BOB)] = 300, [pk(ME, CAT)] = 300, [pk(BOB, CAT)] = 300, [pk(DAN, EVE)] = 400, [pk(CAT, DAN)] = 10 } }
		A().Social:ComputeNow()
	end

	describe("for an officer", function()
		before_boot(function() guild(1) end)

		it("summarises the mixing and lists the groups with their players and minutes", function()
			data()
			local lines = V().Lines(G():Current())
			contains(lines[1].text, "modularity")
			eq(lines[2].text, "5 players with group play in the last 30 days, 2 groups, 21.8 h together in all")
			eq(lines[3].text, "Group 1 (3): Cat, Bob, Testchar")
			eq(lines[4].text, "15.0 h inside the group, 0.2 h with the rest of the guild")
			eq(lines[5].text, "Group 2 (2): Dan, Eve")
		end)

		it("draws one dot per player with the name on hover; a click opens the card", function()
			data()
			Mock.Slash("/accord reputation")
			truthy(A().ReputationView:SetMode("groups"))
			eq(V().dotsShown, 5)
			local dot
			for _, d in ipairs(V().frame.canvas.dots) do if d:IsShown() and d.key == DAN then dot = d end end
			eq(dot.name, "Dan")
			dot:Click()
			eq(A().MemberCard.entry.guid, DAN)
		end)

		it("is built once per social result", function()
			data()
			local first = G():Current()
			eq(G():Current(), first)
			A().Social:ComputeNow()
			ne(G():Current(), first)
		end)

		it("says so when there is no data", function()
			eq(V().Lines(nil)[1].text, "The group map needs the social index: it is being computed, or there is no group play in the last 30 days.")
		end)
	end)

	describe("for a member", function()
		before_boot(function() guild(3) end)

		it("has no Groups mode and no map (SPEC-10 Q3)", function()
			data()
			isNil(G():Current())
			Mock.Slash("/accord reputation")
			falsy(A().ReputationView:SetMode("groups"))
			for _, id in ipairs(A().ReputationView.frame.bar.ids) do ne(id, "groups") end
		end)
	end)
end)

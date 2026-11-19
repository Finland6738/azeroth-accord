-- GroupMap: the communities of the guild and how mixed it is (SPEC-07 SOC-10..SOC-12; ADR 0008). Lua 5.1.
--
-- Input: the account graph of the social index (Data/Social.lua): graph[a][b] = minutes accounts a and b played together in
-- the last 30 days (symmetric). Output:
--   communities  weighted label propagation: every account starts with its own label; in rounds, each account (in a
--                fixed order) takes the label with the largest total of minutes among its partners, keeping its own label
--                on a tie with it, else the smallest label on a tie; it stops when a round changes nothing (at most
--                MAX_ROUNDS). Deterministic: every client with the same data finds the same groups.
--   modularity   Q = Σ_c [ L_c / m − (d_c / 2m)² ] with m the total minutes of all pairs, L_c the minutes inside c and d_c
--                the sum of the minutes of c's accounts. Near 0: everyone plays with everyone; high (≥ HIGH): cliques.
--   list         per community: its accounts (by minutes), minutes inside and minutes towards the rest of the guild.
--   layout       a simple drawing: each community a circle of dots, the circles on a grid, sized by the members.
-- Computed on demand from the last social result, once per result. SOC-12 / SPEC-10 Q3: the view shows it only to those
-- who may see the others' index (officers and the Guild Master until the owner answers Q3).
local ADDON_NAME, ns = ...
ns = ns or {}
local GroupMap = {}
ns.GroupMap, ns.modules = GroupMap, ns.modules or {}
ns.modules.GroupMap = GroupMap

local type, pairs, ipairs, tostring, next = type, pairs, ipairs, tostring, next
local floor, ceil, sqrt, max, min, cos, sin, pi = math.floor, math.ceil, math.sqrt, math.max, math.min, math.cos, math.sin, math.pi
local sort = table.sort

GroupMap.MAX_ROUNDS = 30
GroupMap.LOW, GroupMap.HIGH = 0.3, 0.5     -- modularity: below LOW well mixed, from HIGH cliques

---------------------------------------------------------------------------------------------------------------------
-- Pure functions
---------------------------------------------------------------------------------------------------------------------
local function nodesOf(graph)
	local nodes = {}
	for a in pairs(graph) do nodes[#nodes + 1] = a end
	sort(nodes)
	return nodes
end

-- Weighted label propagation. Returns labels { [node] = label } and the number of rounds.
function GroupMap.Propagate(graph)
	local nodes = nodesOf(graph)
	local labels = {}
	for _, a in ipairs(nodes) do labels[a] = a end
	local rounds = 0
	for round = 1, GroupMap.MAX_ROUNDS do
		rounds = round
		local changed = false
		for _, a in ipairs(nodes) do
			local weight = {}
			for b, w in pairs(graph[a]) do
				if b ~= a and w > 0 then
					local l = labels[b] or b
					weight[l] = (weight[l] or 0) + w
				end
			end
			local own = labels[a]
			local best, bestW = own, weight[own] or -1
			for l, w in pairs(weight) do
				if w > bestW or (w == bestW and l ~= own and best ~= own and l < best) then best, bestW = l, w end
			end
			if best ~= own and bestW > (weight[own] or 0) then
				labels[a] = best
				changed = true
			end
		end
		if not changed then break end
	end
	return labels, rounds
end

-- The modularity of a partition (labels) of the graph; 0 for an empty graph.
function GroupMap.Modularity(graph, labels)
	local twoM, inside, degree = 0, {}, {}
	for a, row in pairs(graph) do
		local la = labels[a]
		for b, w in pairs(row) do
			if b ~= a and w > 0 then
				twoM = twoM + w
				degree[la] = (degree[la] or 0) + w
				if labels[b] == la then inside[la] = (inside[la] or 0) + w end
			end
		end
	end
	if twoM <= 0 then return 0 end
	local q = 0
	for c, d in pairs(degree) do
		-- `inside` counts each internal pair twice (a→b and b→a), so it is 2·L_c
		q = q + (inside[c] or 0) / twoM - (d / twoM) ^ 2
	end
	return q
end

-- "low" (well mixed), "medium" or "high" (cliques).
function GroupMap.Mixing(q)
	if q >= GroupMap.HIGH then return "high" end
	if q >= GroupMap.LOW then return "medium" end
	return "low"
end

-- The communities of a partition: a list (largest first) of { id, members = { key, ... } (by minutes), inside, outside },
-- with the minutes inside (each pair once) and towards other communities.
function GroupMap.Communities(graph, labels)
	local byLabel = {}
	local list = {}
	local minutesOf = {}
	for a, row in pairs(graph) do
		local total = 0
		for b, w in pairs(row) do if b ~= a then total = total + w end end
		minutesOf[a] = total
		local l = labels[a]
		local c = byLabel[l]
		if not c then c = { id = l, members = {}, inside = 0, outside = 0 } byLabel[l] = c list[#list + 1] = c end
		c.members[#c.members + 1] = a
		for b, w in pairs(row) do
			if b ~= a then
				if labels[b] == l then c.inside = c.inside + w / 2 else c.outside = c.outside + w end
			end
		end
	end
	for _, c in ipairs(list) do
		sort(c.members, function(x, y) if minutesOf[x] ~= minutesOf[y] then return minutesOf[x] > minutesOf[y] end return x < y end)
	end
	sort(list, function(x, y)
		if #x.members ~= #y.members then return #x.members > #y.members end
		if x.inside ~= y.inside then return x.inside > y.inside end
		return tostring(x.id) < tostring(y.id)
	end)
	return list
end

-- A drawing in a width × height box: each community a circle (radius from its size) holding its members as points on
-- the circle; circles on a grid of columns. Returns { circles = { { cx, cy, r, community } }, points = { [key] = { x, y } } }.
function GroupMap.Layout(communities, width, height)
	local out = { circles = {}, points = {} }
	local n = #communities
	if n == 0 or width <= 0 or height <= 0 then return out end
	local cols = max(1, ceil(sqrt(n * width / height)))
	local rows = ceil(n / cols)
	local cellW, cellH = width / cols, height / rows
	local maxR = max(4, min(cellW, cellH) / 2 - 14)
	local biggest = 1
	for _, c in ipairs(communities) do biggest = max(biggest, #c.members) end
	for i, c in ipairs(communities) do
		local col, row = (i - 1) % cols, floor((i - 1) / cols)
		local cx, cy = (col + 0.5) * cellW, (row + 0.5) * cellH
		local r = #c.members == 1 and 0 or max(6, maxR * sqrt(#c.members / biggest))
		out.circles[i] = { cx = cx, cy = cy, r = r, community = c }
		for j, key in ipairs(c.members) do
			local angle = 2 * pi * (j - 1) / #c.members - pi / 2
			out.points[key] = { x = cx + r * cos(angle), y = cy + r * sin(angle) }
		end
	end
	return out
end

-- Everything for one graph: { communities, modularity, mixing, rounds, accounts, minutes }.
function GroupMap.Build(graph)
	local labels, rounds = GroupMap.Propagate(graph)
	local q = GroupMap.Modularity(graph, labels)
	local total, accounts = 0, 0
	for a, row in pairs(graph) do
		accounts = accounts + 1
		for b, w in pairs(row) do if b ~= a then total = total + w end end
	end
	return { communities = GroupMap.Communities(graph, labels), modularity = q, mixing = GroupMap.Mixing(q), rounds = rounds,
		accounts = accounts, minutes = total / 2, labels = labels }
end

---------------------------------------------------------------------------------------------------------------------
-- The module: one map per social result
---------------------------------------------------------------------------------------------------------------------
local cache = { source = nil, map = nil }

-- The map of the last social result, or nil (nothing computed yet, or this player may not see it: SPEC-10 Q3).
function GroupMap:Current()
	local S = ns.Social
	if not (S and S:CanSeeOthers()) then return nil end
	local r = S:Result()
	if not r then return nil end
	if cache.source ~= r then cache.source, cache.map = r, GroupMap.Build(r.graph) end
	return cache.map
end

function GroupMap:Reset() cache.source, cache.map = nil, nil end

function GroupMap:DebugLines()
	local m = cache.map
	if not m then return { "GroupMap: not built yet" } end
	return { ("GroupMap: %d account(s), %d communit%s, modularity %.2f (%s), %d round(s)"):format(m.accounts, #m.communities,
		#m.communities == 1 and "y" or "ies", m.modularity, m.mixing, m.rounds) }
end

if ns.addon then
	ns.addon.GroupMap = GroupMap
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("GroupMap", function() return GroupMap:DebugLines() end) end
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() GroupMap:Reset() end) end
end

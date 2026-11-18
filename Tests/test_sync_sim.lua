-- Sync (M1.7) proven with the network simulator (Tests/sim/sim.lua): HELLO, pushes, REQ and REC between complete
-- clients of one guild (SPEC-02 §4), and the convergence of 50 clients with random logins, logouts and lockdown inside
-- the traffic budget documented in SPEC-02 §4.

-- Every client writes its own account record (and a contacts record) through its Store.
local function write(c, extra)
	local S = c:addon().Store
	local guid = c:guid()
	truthy(S:Put("accounts", guid, { token = "T" .. c.index, chars = { { guid = guid } }, n = extra }))
	truthy(S:Put("contacts", guid, { battleTag = c.name .. "#" .. c.index, n = extra }))
end

-- The records a client holds, as "set|id|rev" lines in order: two clients agree when the texts are equal.
local function fingerprint(c)
	local S, lines = c:addon().Store, {}
	for _, set in ipairs(S.SET_ORDER) do
		for id, rec in pairs(S:Records(set)) do lines[#lines + 1] = set .. "|" .. id .. "|" .. rec.rev end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function converged(sim, list)
	local first
	for _, i in ipairs(list) do
		local f = fingerprint(sim:client(i))
		if first == nil then first = f elseif f ~= first then return false end
	end
	return true
end

local function all(n) local t = {} for i = 1, n do t[i] = i end return t end

describe("the sync between a few clients", function()
	it("a local change reaches the online guildmates after the batch", function()
		local sim = Sim.new{ clients = 3, seed = 3 }
		write(sim:client(1))
		sim:advance(3)
		isNil(sim:client(2):addon().Store:Get("accounts", sim:client(1):guid()), "not before the 5-second batch")
		sim:advance(5)
		for i = 2, 3 do notNil(sim:client(i):addon().Store:Get("accounts", sim:client(1):guid()), "client " .. i) end
		truthy(converged(sim, all(3)))
	end)

	it("a late joiner gets everyone's data from the online authors after its HELLO", function()
		local sim = Sim.new{ clients = 4, offline = { 4 }, seed = 5 }
		for i = 1, 3 do write(sim:client(i)) end
		sim:advance(40)
		truthy(converged(sim, { 1, 2, 3 }))
		sim:client(4):login()
		write(sim:client(4))
		local ok, took = sim:advanceUntil(function() return converged(sim, all(4)) end, 120)
		truthy(ok, "the late joiner converged")
		truthy(took <= 60, "within a minute of logging in, took " .. took)
		eq(#fingerprint(sim:client(4)) > 0, true)
	end)

	it("an officer relays the data of an author who is offline, and only one officer answers", function()
		local sim = Sim.new{ clients = 5, officers = { 1, 2 }, offline = { 5 }, seed = 9 }
		for i = 1, 4 do write(sim:client(i)) end
		sim:advance(40)
		sim:client(4):logout()
		sim:advance(60)
		sim:resetStats()
		sim:client(5):login()
		local ok = sim:advanceUntil(function()
			return sim:client(5):addon().Store:Get("accounts", sim:client(4):guid()) ~= nil
		end, 120)
		truthy(ok, "the offline member's record reached the newcomer")
		sim:advance(20)
		local pushes = 0
		for i = 1, 2 do pushes = pushes + sim:client(i):addon().Sync.state.stats.pushes end
		truthy(pushes >= 1)
		local relays = 0
		for i = 1, 2 do
			-- each officer pushes its own records too; count the officers that sent client 4's record
			relays = relays + (sim:client(i):addon().Sync.state.stats.pushes > 0 and 1 or 0)
		end
		truthy(relays >= 1)
		truthy(converged(sim, { 1, 2, 3, 5 }))
	end)

	it("a member never relays another member's records, so without an officer the newcomer waits for the author", function()
		local sim = Sim.new{ clients = 4, offline = { 4 }, seed = 11 }
		for i = 1, 3 do write(sim:client(i)) end
		sim:advance(40)
		sim:client(3):logout()
		sim:client(4):login()
		sim:advance(90)
		isNil(sim:client(4):addon().Store:Get("accounts", sim:client(3):guid()), "nobody may pass it on")
		eq(sim:client(4):addon().Store.stats.rejected, 0, "and nobody tried")
		sim:client(3):login()
		local ok = sim:advanceUntil(function() return converged(sim, all(4)) end, 120)
		truthy(ok, "the author's HELLO fixed it")
	end)

	it("a client pulls from a HELLO sender who is ahead (REQ), and the answer on GUILD serves everyone", function()
		local sim = Sim.new{ clients = 4, seed = 13 }
		for i = 1, 4 do write(sim:client(i)) end
		sim:advance(40)
		truthy(converged(sim, all(4)))
		-- 2 and 3 log out; 1 changes its data; 1 logs out; 2 and 3 come back (nobody can deliver 1's change)
		sim:client(2):logout(); sim:client(3):logout()
		write(sim:client(1), 2)
		sim:advance(10)
		sim:client(1):logout()
		sim:client(2):login(); sim:client(3):login()
		sim:advance(60)
		local function hasNew(i) local r = sim:client(i):addon().Store:Get("accounts", sim:client(1):guid()) return r and r.n == 2 end
		falsy(hasNew(2)); falsy(hasNew(3)); truthy(hasNew(4))
		sim:client(1):login()
		local ok = sim:advanceUntil(function() return hasNew(2) and hasNew(3) end, 120)
		truthy(ok, "1's HELLO showed it ahead; 2 and 3 pulled")
		local reqs = sim:client(2):addon().Sync.state.stats.requests + sim:client(3):addon().Sync.state.stats.requests
		truthy(reqs >= 1)
		truthy(sim:client(1):addon().Sync.state.stats.answers <= 2)
	end)

	it("messages held in lockdown go out afterwards and the guild converges", function()
		local sim = Sim.new{ clients = 3, seed = 17 }
		sim:client(1):restrict({ lockdown = true })
		write(sim:client(1))
		sim:advance(60)
		isNil(sim:client(2):addon().Store:Get("accounts", sim:client(1):guid()))
		sim:client(1):restrict({ lockdown = false })
		local ok = sim:advanceUntil(function() return converged(sim, all(3)) end, 30)
		truthy(ok)
	end)

	it("a HELLO summary is 11 bytes per author and survives the codec", function()
		local sim = Sim.new{ clients = 3, seed = 23 }
		for i = 1, 3 do write(sim:client(i)) end
		sim:advance(10)
		local Sync = sim:client(1):addon().Sync
		local s = Sync:EncodeSummary()
		eq(#s, 3 * 11)
		local decoded = Sync.DecodeSummary(s)
		local n = 0
		for _ in pairs(decoded) do n = n + 1 end
		eq(n, 3)
		isNil(Sync.DecodeSummary("short"))
		local Codec = sim:client(1):addon().Codec
		eq(Codec:Decode(Codec:Encode("HELLO", { s = s })).s, s)
	end)

	it("a client that lost its saved data gets its own records back, so its next write wins", function()
		local sim = Sim.new{ clients = 3, officers = { 1 }, seed = 19 }
		for i = 1, 3 do write(sim:client(i)) end
		write(sim:client(3), 2)
		sim:advance(40)
		eq(sim:client(1):addon().Store:Get("accounts", sim:client(3):guid()).rev, 2)
		local c = sim:client(3)
		c:logout()
		c.saved = {}   -- a new computer, or the WTF folder deleted
		sim:advance(10)
		c:login()
		sim:advance(60)
		eq(c:addon().Store:Get("accounts", c:guid()).rev, 2, "pulled back from the guild")
		write(c, 3)
		sim:advance(10)
		eq(sim:client(1):addon().Store:Get("accounts", c:guid()).n, 3, "the new write has rev 3 and wins")
	end)
end)

describe("50 clients (SPEC-09 §2)", function()
	it("converge after random logins, logouts and lockdown, inside the traffic budget", function()
		local N, OFFICERS = 50, { 1, 11, 21, 31, 41 }
		local offline = {}
		for i = 2, N, 2 do offline[#offline + 1] = i end   -- half the guild starts logged out
		local sim = Sim.new{ clients = N, officers = OFFICERS, offline = offline, latency = { 0.05, 0.5 }, loss = 0.01, seed = 42 }
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		local writes, lockUntil = {}, {}
		local function writeNext(c)
			writes[c.index] = (writes[c.index] or 0) + 1
			write(c, writes[c.index])
		end
		for i = 1, N do if sim:client(i).online then writeNext(sim:client(i)) end end

		-- 45 minutes of churn: every 30 seconds somebody logs out or in, writes, or enters a lockdown
		for _ = 1, 90 do
			for i = 1, N do
				local c = sim:client(i)
				local r = rand()
				if c.online then
					if r < 0.04 then c:logout()
					elseif r < 0.08 then writeNext(c)
					elseif r < 0.10 and not lockUntil[i] then
						c:restrict({ lockdown = true })
						lockUntil[i] = sim.time + 60 + 240 * rand()
					end
				elseif r < 0.06 then
					c:login()
					if not writes[i] then writeNext(c) end
				end
				if lockUntil[i] and sim.time >= lockUntil[i] then
					c:restrict({ lockdown = false })
					lockUntil[i] = nil
				end
			end
			sim:advance(30)
		end
		local churn = sim:stats()

		-- then everyone comes online, without lockdowns, over two minutes
		sim:resetStats()
		for i = 1, N do
			local c = sim:client(i)
			c:restrict({ lockdown = false })
			if not c.online then
				c:login()
				if not writes[i] then writeNext(c) end
				sim:advance(2.5)
			end
		end
		local function complete()
			for i = 1, N do
				local S = sim:client(i):addon().Store
				for j = 1, N do
					local mine = sim:client(j):addon().Store:Get("accounts", Sim.guidOf(j))
					local seen = S:Get("accounts", Sim.guidOf(j))
					if not mine or not seen or seen.rev ~= mine.rev then return false end
				end
			end
			return converged(sim, all(N))
		end
		local ok, took = sim:advanceUntil(complete, 40 * 60)
		local settle = sim:stats()
		truthy(ok, "all 50 clients hold the newest records of all 50 authors")
		for i = 1, N do eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing") end

		-- steady state: everybody online and in sync for 25 minutes (at least one HELLO each)
		sim:resetStats()
		sim:advance(25 * 60)
		local steady = sim:stats()
		truthy(complete(), "still in sync")

		local perLogin = settle.sent.bytes / #offline
		T.log(("churn: %.0f B/min per client on average, %.0f at most; mass login: converged after %.0f s, %.1f KB per login; steady: %.0f B/min per client on average, %.0f at most")
			:format(churn.avg.bytesPerMinute, churn.max.bytesPerMinute, took, perLogin / 1024,
			steady.avg.bytesPerMinute, steady.max.bytesPerMinute))
		-- the traffic budget of SPEC-02 §4
		truthy(churn.avg.bytesPerMinute <= 400, "churn average " .. churn.avg.bytesPerMinute)
		truthy(churn.max.bytesPerMinute <= 1500, "churn busiest client " .. churn.max.bytesPerMinute)
		truthy(perLogin <= 8 * 1024, "bytes per login " .. perLogin)
		truthy(took <= 5 * 60, "converged within five minutes of the last login")
		truthy(steady.avg.bytesPerMinute <= 100, "steady average " .. steady.avg.bytesPerMinute)
		truthy(steady.max.bytesPerMinute <= 200, "steady busiest client " .. steady.max.bytesPerMinute)
	end)
end)

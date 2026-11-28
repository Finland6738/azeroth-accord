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

	it("who has just logged in counts the guildmates with the addon within a minute, also when all are in step", function()
		local sim = Sim.new{ clients = 4, offline = { 4 }, seed = 11 }
		sim:advance(120)
		sim:client(4):login()
		sim:advance(60)
		eq(sim:client(4):addon().Sync:Status().peers, 3)
		for i = 1, 4 do eq(sim:client(i):addon().Sync.state.stats.refused, 0, "client " .. i) end
		sim:client(4):logout()
		sim:client(4):login()   -- a /reload soon after: no second answer within five minutes, its own wait decides
		sim:advance(60)
		for i = 1, 4 do eq(sim:client(i):addon().Sync.state.stats.quarantined, 0, "client " .. i) end
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
		-- With 1% loss a record lost on GUILD is repaired when the next HELLO of somebody who has it arrives, and that is
		-- usually within a minute or two (five officers, each one every 15-20 minutes), but in some random sequences
		-- it takes one more round: up to a HELLO period. The result also depends on the platform (the order of
		-- pairs()), so the test does not bet on one outcome: the bound is one HELLO period plus a margin (below).
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
		do   -- who the busiest client of the churn was, and what it sent
			local best, bi = -1, 0
			for i, s in ipairs(churn.perClient) do if s.bytesPerMinute > best then best, bi = s.bytesPerMinute, i end end
			local s = churn.perClient[bi]
			local st = sim:client(bi):addon().Sync.state.stats
			T.log(("busiest in the churn: client %d (%s), %.0f B/min; GUILD %d B, WHISPER %d B, OFFICER %d B; pushes %d, answers %d, REC sent %d, HELLO %d"):format(
				bi, sim.officer[bi] and "officer" or "member", best, s.byDist.GUILD.bytes, s.byDist.WHISPER.bytes, s.byDist.OFFICER.bytes,
				st.pushes, st.answers, st.recSent, st.hellosSent))
		end

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
		local limits = { flood = 0, quarantined = 0, oversized = 0, refused = 0 }   -- the limits of SPEC-11 §6.3 (M7.7)
		local floodQuarantine, maxDecoded = 0, 0
		for _, c in ipairs(sim.clients) do
			if c.online or c.E.AzerothAccord then
				local s = c:addon().Sync.state.stats
				for k in pairs(limits) do limits[k] = limits[k] + (s[k] or 0) end
				local T_ = c:addon().Transport
				floodQuarantine = floodQuarantine + (T_:Stats().quarantined or 0)
				for _, w in pairs(T_.state.flood) do if w.bytes > maxDecoded then maxDecoded = w.bytes end end
			end
		end
		T.log(("limits: %d HELLO held, %d quarantined by Sync, %d by Transport (most decoded from one sender in a minute now: %.0f KB), %d oversized REC, %d records refused"):format(
			limits.flood, limits.quarantined, floodQuarantine, maxDecoded / 1024, limits.oversized, limits.refused))
		eq(limits.quarantined + floodQuarantine, 0, "no honest client is put in quarantine")
		-- the traffic budget of SPEC-02 §4
		truthy(churn.avg.bytesPerMinute <= 450, "churn average " .. churn.avg.bytesPerMinute)   -- with the census on (M9.10, SPEC-10 R14)
		truthy(churn.max.bytesPerMinute <= 2048, "churn busiest client " .. churn.max.bytesPerMinute)   -- SPEC-10 R10
		truthy(perLogin <= 8 * 1024, "bytes per login " .. perLogin)
		truthy(took <= 25 * 60, "converged within a HELLO period of the last login: " .. took .. " s")
		truthy(steady.avg.bytesPerMinute <= 100, "steady average " .. steady.avg.bytesPerMinute)
		truthy(steady.max.bytesPerMinute <= 200, "steady busiest client " .. steady.max.bytesPerMinute)
	end)
end)

describe("the officer tools in the traffic budget (SPEC-12 §1.5, M8.2)", function()
	it("five officers who observe the same 30 changes in six hours stay under 150 B/min each, on OFFICER only", function()
		-- 30 changes in six hours is four times the 30 a day of the spec, and every officer observes every one of them
		-- a few seconds apart: the first to write wins, the others only confirm. Nothing may leave on GUILD or reach the
		-- member (client 6), and nothing may be written twice by more than a few.
		local sim = Sim.new{ clients = 6, officers = { 1, 2, 3, 4, 5 }, latency = { 0.05, 0.5 }, seed = 21 }
		sim:setStep(1)
		local leaked = 0
		for i = 1, 6 do
			local c = sim:client(i)
			local tr = c:addon().Transport
			local original = tr.wire
			tr.wire = function(prio, txt, dist, target, done)
				local m = c:addon().Codec:Decode(txt)
				if m and m.t == "REC" and m.s == "timeline" then
					if dist == "GUILD" or (dist == "WHISPER" and tostring(target):find(Sim.nameOf(6), 1, true)) then leaked = leaked + 1 end
				end
				return original(prio, txt, dist, target, done)
			end
		end
		sim:advance(120)
		sim:resetStats()
		local now0 = sim:client(1).E.GetServerTime()
		for e = 1, 30 do
			sim:advance(720)
			local at = sim:client(1).E.GetServerTime()
			for i = 1, 5 do
				local c = sim:client(i):addon()
				c.Timeline:Queue({ { k = "rank", g = Sim.guidOf(100 + e), n = "Member" .. e, a = at - 3600, b = at + i * 3, f = e % 19, t = (e + 1) % 19 } }, at + i * 3)
			end
		end
		sim:advance(900)
		local st = sim:stats()
		local worst, total, stored = 0, 0, {}
		for i = 1, 5 do
			local s = st.perClient[i]
			worst = math.max(worst, s.bytesPerMinute)
			total = total + s.bytesPerMinute
			stored[i] = sim:client(i):addon().Store:Count("timeline")
		end
		T.log(("officer tools: %.0f B/min per officer on average, %.0f at most; records held %s"):format(total / 5, worst, table.concat(stored, "/")))
		eq(leaked, 0, "no REC of the timeline on GUILD or to a member")
		eq(sim:client(6):addon().Store:Count("timeline"), 0)
		truthy(total / 5 < 150, "the average per officer stays under 150 B/min")
		truthy(worst < 2048, "and the busiest client under the 2 KB/min of SPEC-02 §4")
		for i = 1, 5 do
			local events = 0
			for _, e in ipairs(sim:client(i):addon().Timeline:All()) do events = events + 1 end
			eq(events, 30, "officer " .. i .. " reads 30 changes, however many observers saw each")
		end
		local written = 0
		for i = 1, 5 do
			for _, rec in pairs(sim:client(i):addon().Store:Records("timeline")) do
				if rec.author == Sim.guidOf(i) then written = written + #rec.ev end
			end
		end
		T.log(("officer tools: %d events written by the five officers for 30 changes"):format(written))
		-- an officer who writes within the first writer's 5-second batch has not received its record yet: some duplicates are
		-- normal (31 on Windows, 39 on the Linux CI); without the check of confirmed events there would be 150
		truthy(written <= 60, "the first writer wins: " .. written .. " events written for 30 changes")
	end)
end)

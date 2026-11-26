-- A large guild end to end (M6.3; SPEC-09 §5, M0 check S11 offline): 1000 members, 400 of them with the addon, two
-- recipe lists each, 90 days of co-play, a likes ledger, bank snapshots, logs and requests. It measures what a player's
-- computer has to carry: the size of the saved file, the memory, the time to load it, and the time of every heavy
-- operation. The numbers go to the log (`python -X utf8 Tests/run_tests.py large_guild -v` shows them) and the budgets
-- are about twice what an ordinary development PC needs, so a slow CI machine does not fail them but a change that makes
-- something ten times worse does. They are OFFLINE numbers from lupa's Lua 5.1, not the game's: the in-game S11 numbers
-- come with the release check.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end

local MEMBERS, USERS, ACCOUNTS = 1000, 400, 160
local function guid(i) return ("Player-1-%08X"):format(0x10000 + i) end
local ME = "Player-1-0000A001"
local DAY = 86400

local function build()
	local members = {}
	for i = 1, MEMBERS do
		members[i] = { name = "M" .. i, level = 1 + i % 60, class = (i % 2 == 0) and "MAGE" or "WARRIOR", rank = 2 + i % 3,
			online = i % 5 == 0, guid = guid(i), lastOnline = { 0, 0, i % 20, 0 },
			professions = { { id = 171, name = "Alchemy", rank = i % 300 }, { id = 164, name = "Blacksmithing", rank = 1 } },
			discord = (i % 3 == 0) and ("d" .. i) or nil }
	end
	Mock.guild.Set{ name = "Accord", myRank = 1, members = members }
end

-- The synthetic data of a busy guild, written straight into the store (what the sync would have delivered).
local function populate()
	local t = GetServerTime()
	local recs = S():Records("accounts")
	local groups, per = {}, USERS / ACCOUNTS
	for i = 1, USERS do
		local g = (i - 1) % ACCOUNTS + 1
		groups[g] = groups[g] or {}
		groups[g][#groups[g] + 1] = i
	end
	for g, list in pairs(groups) do
		local chars = {}
		for _, i in ipairs(list) do chars[#chars + 1] = { guid = guid(i), name = "M" .. i, realm = "TestRealm", classID = 8, level = 1 + i % 60, inGuild = true } end
		for _, i in ipairs(list) do
			recs[guid(i)] = { id = guid(i), author = guid(i), rev = 1, time = t, token = ("T%023d="):format(g), chars = chars, main = chars[1].guid, addonVersion = "1.0.0" }
		end
	end
	local contacts = S():Records("contacts")
	for i = 1, USERS do
		contacts[guid(i)] = { id = guid(i), author = guid(i), rev = 1, time = t, account = ("T%023d="):format((i - 1) % ACCOUNTS + 1),
			battleTag = "Player" .. i .. "#" .. (1000 + i), discord = "discord_user_" .. i }
	end
	local recipes = S():Records("recipes")
	Mock.randomseed(7)
	for i = 1, USERS do
		for _, line in ipairs({ 171, 164 }) do
			local ids, id = {}, 1000
			for k = 1, 250 do id = id + math.random(1, 40) ids[k] = id end
			local rid = guid(i) .. ":" .. line
			recipes[rid] = { id = rid, author = guid(i), rev = 1, time = t - DAY, char = guid(i), skillLine = line, name = line == 171 and "Alchemy" or "Blacksmithing",
				rank = 250, maxRank = 300, ids = A().Recipes.Encode(ids), n = #ids }
		end
	end
	local coplay = S():Records("coplay")
	for day = 0, 89 do
		for o = 1, 60 do
			if (o * 7 + day * 3) % 10 < 3 then
				local p = {}
				for k = 1, 30 do
					local a, b = guid((o * 13 + k * 7 + day) % USERS + 1), guid((o * 17 + k * 11 + day * 5) % USERS + 1)
					if a ~= b then
						if a > b then a, b = b, a end
						p[a .. ":" .. b] = 5 + k
					end
				end
				local d = ("%08d"):format(20260101 + day)
				local id = guid(o) .. ":" .. d
				coplay[id] = { id = id, author = guid(o), rev = 1, time = t - day * DAY, day = tonumber(d), observer = guid(o), pairs = p }
			end
		end
	end
	local likes = S():Records("likes")
	for n = 1, 2000 do
		local p = ("%016x%016x"):format(n * 2654435761, n)
		local target = guid(n % USERS + 1)
		likes[p:sub(1, 16) .. ":" .. target] = { id = p:sub(1, 16) .. ":" .. target, author = guid(1), rev = 1, time = t, pseudonym = p, tag = ("%016x"):format(n), target = target, day = 20260101 }
	end
	local bank = S():Records("bank")
	for author = 1, 3 do
		for tab = 1, 6 do
			local items = {}
			for slot = 1, 98 do items[#items + 1] = { slot = slot, itemID = 2000 + slot * 3 + tab, count = 1 + slot % 20 } end
			local id = guid(author) .. ":t" .. tab
			bank[id] = { id = id, author = guid(author), rev = 1, time = t - author * 3600, kind = "tab", tab = tab, name = "Tab " .. tab, rank = 3,
				it = A().Bank.EncodeItems(items), n = #items }
		end
		local entries = {}
		for k = 1, 25 do entries[#entries + 1] = { kind = k % 2 == 0 and "deposit" or "withdraw", name = "M" .. (k * 3), itemID = 2000 + k, count = k, t = t - k * 600 } end
		for tab = 1, 6 do
			local id = guid(author) .. ":log:" .. tab
			bank[id] = { id = id, author = guid(author), rev = 1, time = t, kind = "log", tab = tab, rank = 3, e = A().BankLog.Encode(entries), n = #entries }
		end
		bank[guid(author) .. ":money"] = { id = guid(author) .. ":money", author = guid(author), rev = 1, time = t, kind = "money", money = 123456789 }
	end
	local reqs = S():Records("bankreq")
	for n = 1, 120 do
		local id = guid(n) .. ":" .. n
		reqs[id] = { id = id, author = guid(n), rev = 1, time = t - n * 3600, requester = guid(n), kind = "withdraw", status = n % 6 == 0 and "open" or "fulfilled",
			itemID = 2000 + n, count = 5, created = t - n * 3600, history = { { s = "open", by = guid(n), t = t - n * 3600 } } }
		if reqs[id].status ~= "open" then reqs[id].author = guid(1) end
	end
	A().Roster:MarkDirty()
	A().Accounts:MarkDirty()
end

local function KB() collectgarbage() collectgarbage() return collectgarbage("count") end

local function timed(name, budget, fn)
	local t0 = Mock.RealClock()
	local result = fn()
	local ms = (Mock.RealClock() - t0) * 1000
	T.log(("%-34s %6.0f ms (budget %d ms)"):format(name, ms, budget))
	truthy(ms < budget, name .. " took " .. math.floor(ms) .. " ms, budget " .. budget .. " ms")
	return result, ms
end

describe("a busy guild of 1000 members", function()
	before_boot(function() build() end)

	it("keeps the saved file, the memory and the time of every heavy step inside the budgets", function()
		local before = KB()
		populate()
		local after = KB()
		T.log(("memory of the populated store: +%.1f MB"):format((after - before) / 1024))

		local size = A().Config.EstimateSize(A().Config.db.account.guilds["TestRealm/Accord"] or A().GuildKey:Data())
		T.log(("estimated size of the guild's data: %.2f MB"):format(size / 1024 / 1024))

		-- the saved file as the game would write it, and the time a /reload takes with it
		local _, reloadMs = timed("reload with the saved file", 4000, function() Mock.Reload() end)
		local fileBytes = #Mock.savedText.AzerothAccordDB
		T.log(("AzerothAccordDB written: %.2f MB"):format(fileBytes / 1024 / 1024))
		truthy(fileBytes < 8 * 1024 * 1024, "the saved file is " .. fileBytes .. " bytes")
		truthy(KB() - before < 80 * 1024, "memory after the reload grew by " .. (KB() - before) / 1024 .. " MB")

		timed("roster build (1000 members)", 1500, function() A().Roster:MarkDirty() return A().Roster:Members() end)
		timed("account groups", 1000, function() A().Accounts:MarkDirty() return A().Accounts:Groups() end)
		timed("Roster view: open, sort, group", 2000, function()
			A().Shell:OpenView("roster")
			Mock.Advance(2)
			local m = A().RosterView:Model()
			m:SetSort("level", true)
			m:SetGrouped(true)
			return m:Count()
		end)
		timed("social index and group map", 2000, function()
			A().Social:ComputeNow()
			return A().GroupMap
		end)
		timed("who can craft: first search", 2000, function() return A().Crafters:Search("recipe") end)
		timed("Reputation view", 1500, function() A().Shell:OpenView("reputation") Mock.Advance(2) end)
		timed("Bank view", 1000, function() A().Shell:OpenView("bank") Mock.Advance(2) end)
		timed("Settings page with the sizes", 1500, function()
			A().Shell:OpenView("settings")
			A().SettingsView:Refresh()
			return A().SettingsModel.Sizes()
		end)
		timed("retention pass (Store:Prune)", 500, function() return S():Prune() end)

		local s = A().SettingsModel.Sizes()
		for _, p in ipairs(s.parts) do
			T.log(("  %-10s %8s  %s"):format(p.name, A().SettingsModel.FormatBytes(p.bytes), p.records and (p.records .. " records") or ""))
		end
		eq(#Mock.errors, 0)
		T.log(("memory at the end: +%.1f MB over the empty client"):format((KB() - before) / 1024))
	end)
end)

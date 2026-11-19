-- Social: the social breadth index (SPEC-07 §3.2, SOC-04..SOC-06; ADR 0008). Lua 5.1.
--
-- From the co-play records (Data/CoPlay.lua: minutes per pair of characters and realm day, one record per observer), for
-- the last WINDOW_DAYS days:
--   1. per day and pair of characters, the MAXIMUM over the observers (NET-13: never the sum);
--   2. characters become accounts (Accounts:AccountKey: the proved characters of an account, ADR 0006; a hint from a note
--      merges nothing); a pair inside one account (two of its characters in one group) is left out; minutes are summed over
--      the days and over the characters: m[a][b] = minutes account a played with account b;
--   3. for each account a: M = Σ_b m_ab (minutes with guildmates, counted per partner: an hour with four guildmates counts
--      four hours), p_b = m_ab / M, effective partners N = exp(-Σ p_b ln p_b), distinct partners, the top five shares;
--   4. A = the accounts with at least ACTIVE_MINUTES in the window; index = min(100, round(100 · N / (A − 1))), only for an
--      account with at least ENOUGH_MINUTES (5 hours, SOC-04: below that the index is "not enough data") and A ≥ 2.
-- SOC-06: computed locally, at most once every MIN_INTERVAL seconds unless asked again, in steps of STEP records or pairs
-- per frame (a coroutine driven by C_Timer.After(0)), so a big guild never freezes the client. The result also keeps the
-- account graph (m) for the group map and the suggestions.
-- Bus: SOCIAL_UPDATED() when a computation ended.
local ADDON_NAME, ns = ...
ns = ns or {}
local Social = {}
ns.Social, ns.modules = Social, ns.modules or {}
ns.modules.Social = Social

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, exp, log, min = math.floor, math.exp, math.log, math.min
local sort = table.sort

Social.AUTO = true                -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Social.WINDOW_DAYS = 30
Social.ACTIVE_MINUTES = 60        -- an account counts in A with at least this many minutes in the window
Social.ENOUGH_MINUTES = 300       -- SOC-04: 5 hours
Social.MIN_INTERVAL = 600         -- SOC-06: at most once every 10 minutes
Social.STEP = 40                  -- records (or days of pairs) per frame
Social.TOP = 5                    -- SOC-05
Social.START_DELAY = 90           -- seconds after login before the first computation

local function compat() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

---------------------------------------------------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------------------------------------------------
-- Days since 1970-01-01 of a civil date, and back (proleptic Gregorian; Howard Hinnant's algorithm).
local function daysFromCivil(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local function civilFromDays(z)
	z = z + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then y = y + 1 end
	return y, m, d
end

-- The day number YYYYMMDD that is `offset` days from `day` (YYYYMMDD).
function Social.AddDays(day, offset)
	local y, m, d = floor(day / 10000), floor(day / 100) % 100, day % 100
	local y2, m2, d2 = civilFromDays(daysFromCivil(y, m, d) + offset)
	return y2 * 10000 + m2 * 100 + d2
end

-- The first day of the window that ends with `today` (both included).
function Social.CutoffDay(today)
	return Social.AddDays(today, -(Social.WINDOW_DAYS - 1))
end

-- Effective partners of a { [partner] = minutes } table: N = exp(entropy of the shares), the total minutes M and the
-- number of distinct partners (minutes > 0).
function Social.Effective(minutesByPartner)
	local total, count = 0, 0
	for _, x in pairs(minutesByPartner) do
		if x > 0 then total, count = total + x, count + 1 end
	end
	if total <= 0 then return 0, 0, 0 end
	local h = 0
	for _, x in pairs(minutesByPartner) do
		if x > 0 then
			local p = x / total
			h = h - p * log(p)
		end
	end
	return exp(h), total, count
end

-- index = min(100, round(100 · N / (A − 1))), nil when fewer than two accounts are active.
function Social.IndexOf(n, active)
	if type(n) ~= "number" or type(active) ~= "number" or active < 2 then return nil end
	return min(100, floor(100 * n / (active - 1) + 0.5))
end

-- The whole computation. `records`: a list of co-play records; `accountOf(guid)` -> account key; `cutoff`: the first day
-- (YYYYMMDD) of the window; `yield`: called every STEP items when the computation runs in steps (nil: in one go).
-- Returns { accounts = { [key] = { key, minutes, partners, effective, enough, index, top = { { key, minutes, share } } } },
--           graph = { [a] = { [b] = minutes } }, active, cutoff, days }.
function Social.Build(records, accountOf, cutoff, yield)
	local step = 0
	local function tick()
		step = step + 1
		if yield and step % Social.STEP == 0 then yield() end
	end
	-- 1. the maximum over the observers, per day and pair
	local days, dayCount = {}, 0
	for _, rec in ipairs(records) do
		local day = type(rec) == "table" and tonumber(rec.day)
		if day and day >= cutoff and type(rec.pairs) == "table" then
			local d = days[day]
			if not d then d = {} days[day] = d dayCount = dayCount + 1 end
			for pair, minutes in pairs(rec.pairs) do
				if type(minutes) == "number" and minutes > 0 and minutes > (d[pair] or 0) then d[pair] = minutes end
			end
		end
		tick()
	end
	-- 2. accounts, summed over days and characters
	local keyOf = {}
	local function acc(guid)
		local k = keyOf[guid]
		if k == nil then
			k = accountOf(guid) or guid
			keyOf[guid] = k
		end
		return k
	end
	local graph = {}
	local function add(a, b, minutes)
		local row = graph[a]
		if not row then row = {} graph[a] = row end
		row[b] = (row[b] or 0) + minutes
	end
	for _, d in pairs(days) do
		for pair, minutes in pairs(d) do
			local ga, gb = pair:match("^([^:]+):([^:]+)$")
			if ga and gb then
				local a, b = acc(ga), acc(gb)
				if a ~= b then add(a, b, minutes) add(b, a, minutes) end
			end
		end
		tick()
	end
	-- 3. per account
	local accounts, active = {}, 0
	for a, partners in pairs(graph) do
		local n, total, count = Social.Effective(partners)
		local list = {}
		for b, minutes in pairs(partners) do list[#list + 1] = { key = b, minutes = minutes } end
		sort(list, function(x, y) if x.minutes ~= y.minutes then return x.minutes > y.minutes end return x.key < y.key end)
		local top = {}
		for i = 1, min(Social.TOP, #list) do
			top[i] = { key = list[i].key, minutes = list[i].minutes, share = list[i].minutes / total }
		end
		accounts[a] = { key = a, minutes = total, partners = count, effective = n, top = top, enough = total >= Social.ENOUGH_MINUTES }
		if total >= Social.ACTIVE_MINUTES then active = active + 1 end
		tick()
	end
	-- 4. the index (A is known only now)
	for _, e in pairs(accounts) do
		if e.enough then e.index = Social.IndexOf(e.effective, active) end
	end
	return { accounts = accounts, graph = graph, active = active, cutoff = cutoff, days = dayCount }
end

---------------------------------------------------------------------------------------------------------------------
-- The module: computation in steps, results by character
---------------------------------------------------------------------------------------------------------------------
local state
local function resetState()
	state = { result = nil, computedAt = nil, stale = true, job = nil, runs = 0, lastSteps = 0, lastMs = nil }
	Social.state = state
end
resetState()

local function now() return compat().ServerTime() end

local function accountOf(guid)
	return ns.Accounts and ns.Accounts:AccountKey(guid) or guid
end

local function inputs()
	local list = {}
	for _, rec in pairs(ns.Store and ns.Store:Records("coplay") or {}) do list[#list + 1] = rec end
	return list, Social.CutoffDay(compat().ServerDay())
end

-- Computes now, in one go (tests, /accord debug). Returns the result.
function Social:ComputeNow()
	local records, cutoff = inputs()
	local started = debugprofilestop and debugprofilestop() or nil
	local result = Social.Build(records, accountOf, cutoff)
	state.lastMs = started and (debugprofilestop() - started) or nil
	state.result, state.computedAt, state.stale = result, now(), false
	state.runs = state.runs + 1
	emit("SOCIAL_UPDATED")
	return result
end

local function finish(result, steps)
	state.job = nil
	state.result, state.computedAt, state.stale = result, now(), false
	state.runs, state.lastSteps = state.runs + 1, steps
	emit("SOCIAL_UPDATED")
end

-- Starts a computation in steps when the data changed and the last one is older than MIN_INTERVAL (or `force`).
-- Returns "started", "running", "recent" (nothing new or computed less than MIN_INTERVAL ago) or "done" (no timers:
-- computed in one go).
function Social:Refresh(force)
	if state.job then return "running" end
	if not force and state.result and (not state.stale or now() - (state.computedAt or 0) < Social.MIN_INTERVAL) then
		return "recent"
	end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return "recent" end
	local records, cutoff = inputs()
	local co = coroutine.create(function() return Social.Build(records, accountOf, cutoff, coroutine.yield) end)
	local job = { co = co, steps = 0 }
	state.job = job
	local function step()
		if state.job ~= job then return end   -- a change of guild dropped it
		job.steps = job.steps + 1
		local ok, result = coroutine.resume(co)
		if not ok then
			state.job = nil
			if geterrorhandler then geterrorhandler()(result) end
			return
		end
		if coroutine.status(co) == "dead" then
			finish(result, job.steps)
		elseif not compat().After(0, step) then
			step()
		end
	end
	if not compat().After(0, step) then
		step()
		return "done"
	end
	return "started"
end

-- The last result (nil before the first computation); asks for a new one in the background when it is out of date.
function Social:Result()
	self:Refresh(false)
	return state.result
end

-- The social data of the account of `guid`: { key, minutes, partners, effective, enough, index, top }, or nil when it has
-- no group play in the window (or nothing is computed yet).
function Social:ForGUID(guid)
	local r = state.result
	if not (r and type(guid) == "string") then return nil end
	return r.accounts[accountOf(guid)]
end

-- The index of the account of `guid`, or nil ("not enough data", no data, or nothing computed yet).
function Social:Index(guid)
	local e = self:ForGUID(guid)
	return e and e.index or nil
end

-- Minutes the account of `a` played with the account of `b` in the window (0 when none).
function Social:MinutesBetween(a, b)
	local r = state.result
	if not r then return 0 end
	local row = r.graph[accountOf(a)]
	return row and row[accountOf(b)] or 0
end

function Social:Active() return state.result and state.result.active or 0 end

function Social:MarkStale() state.stale = true end

function Social:Start()
	if not self.AUTO then return false end
	compat().After(Social.START_DELAY, function() Social:Refresh(false) end)
	return true
end

function Social:DebugLines()
	local r = state.result
	if not r then return { "Social: not computed yet" .. (state.job and " (running)" or "") } end
	local n, enough = 0, 0
	for _, e in pairs(r.accounts) do
		n = n + 1
		if e.enough then enough = enough + 1 end
	end
	return {
		("Social: %d account(s) with group play in %d day(s), %d active, %d with enough data; computed %s ago in %d step(s)%s%s"):format(
			n, r.days, r.active, enough, tostring(now() - (state.computedAt or now())) .. " s", state.lastSteps or 0,
			state.lastMs and (", " .. floor(state.lastMs) .. " ms") or "", state.stale and ", data changed since" or ""),
	}
end

if ns.addon then
	ns.addon.Social = Social
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Social", function() return Social:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set) if set == "coplay" or set == "accounts" then state.stale = true end end)
		ns.Bus:On("GUILD_CHANGED", function(key)
			resetState()
			if key then Social:Start() end
		end)
	end
	if ns.OnEnable then ns.OnEnable(function() Social:Start() end) end
end

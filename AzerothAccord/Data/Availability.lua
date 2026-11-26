-- Availability: when members usually play, from their presence online over time (M10.8; SPEC-14 §8; SPEC-10 Q23;
-- ADR 0022). Lua 5.1.
--
-- What is measured  ONLY the minutes this account has a character online, per hour of the week (168 cells, Monday 00:00
--                   first, the realm's clock), for the last WEEKS weeks: AzerothAccordDB.avail = { since = week,
--                   weeks = { [week] = { [cell] = minutes } } }, per account, not per guild (characters of other guilds
--                   count: they tell when the person plays). Nothing else is read or kept: not where the player is, not
--                   what they do, not a group, an instance or a raid. Accord counts no attendance (integration rule 7).
-- Levels            a week counts for a cell when the account was online at least MIN_MINUTES of that hour. Over the
--                   weeks measured (at most WEEKS; an hour of this week counts once it is over, or once present): 0 never,
--                   1 less than one week in four, 2 up to half, 3 more than half.
-- Record            the data set `avail` (Net/Store.lua): id = the character's GUID, author = a character of the same
--                   account, { p = the 168 levels, two bits each, in BYTES bytes, w = weeks measured } or { del = true }.
--                   First hand or relayed by an officer; removed RETENTION seconds after it was written.
-- When it goes out  FIRST_DELAY seconds after the first HELLO of a session, then looked at every CHECK_EVERY seconds.
--                   A record is written only when `p` differs from the account's newest record, or when that record is
--                   older than REFRESH_AGE (so that it does not expire while its player keeps the same habits); and at
--                   most once every PUBLISH_EVERY seconds per account (once every FIRST_WEEK_EVERY while only one week
--                   is measured, when the map still fills up). A changed record makes the guild's clients fetch its
--                   author's data again: this is what keeps the traffic low (SPEC-14 §11).
-- Switch off        "Share when I usually play" (account.settings.shareAvailability, on by default, Q23): every record
--                   of this account that is still published gets one `del`, then nothing more. The local count goes on:
--                   the player still sees their own map.
-- Who sees what     Q23: everybody sees the counts per cell; WHO is online in a cell only the officers and the Guild
--                   Master, and everybody their own account. Availability.NAMES_VISIBLE_TO is the one place. It is a rule
--                   of the interface: the records reach the whole guild. :Map() holds no name; :Who() applies it.
-- With FDCP         while FDCP is the source of the season roster, :Declared() gives an officer the days FDCP's members
--                   declared (its public API, `avail`): a declaration, never mixed with the measured counts.
-- Switch: Features.On("season") (Core/Features.lua), on since M10.10. Off: nothing is counted, written, accepted or
-- sent. Demo mode publishes nothing.
-- Bus: AVAILABILITY_CHANGED() when the guild's map or the own one may have changed, collected for EMIT_DELAY seconds.
local ADDON_NAME, ns = ...
ns = ns or {}
local Availability = {}
ns.Availability, ns.modules = Availability, ns.modules or {}
ns.modules.Availability = Availability

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, random, max, min = math.floor, math.random, math.max, math.min
local byte, char, sort, concat = string.byte, string.char, table.sort, table.concat

local DAY = 86400
Availability.SET = "avail"
Availability.AUTO = true                   -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Availability.TICK = 60                     -- seconds between two counts
Availability.CELLS = 168                   -- 7 days of 24 hours
Availability.BYTES = 42                    -- 168 levels of two bits
Availability.WEEKS = 8                     -- the weeks measured (Q23)
Availability.MIN_MINUTES = 10              -- minutes of an hour that make its week count
Availability.USUAL = 2                     -- the level from which a member is "usually online" in a cell
Availability.RETENTION = 30 * DAY
Availability.PUBLISH_EVERY = 7 * DAY       -- at most one record a week per account (the shared traffic budget)
Availability.FIRST_WEEK_EVERY = DAY        -- the same while only one week is measured
Availability.REFRESH_AGE = 14 * DAY        -- an unchanged record is written again after this (before RETENTION)
Availability.FIRST_DELAY = { 120, 240 }    -- after the first HELLO: the own record has had time to come back
Availability.CHECK_EVERY = 3600
Availability.SWITCH_DELAY = 5
Availability.EMIT_DELAY = 1
Availability.NAMES_VISIBLE_TO = "officers" -- "officers" or "members" (SPEC-10 Q23): the one place
Availability.FDCP_DAYS = { MON = 1, TUE = 2, WED = 3, THU = 4, FRI = 5, SAT = 6, SUN = 7 }

local state

local function resetState()
	for _, key in ipairs({ "first", "switch" }) do
		if state and state[key] then state[key]:Cancel() end
	end
	local ticker = state and state.ticker
	state = { ticker = ticker, armed = false, ready = false, lastCheck = nil, cache = nil, emitting = false,
		stats = { ticks = 0, published = 0, unchanged = 0, withdrawn = 0 }, last = nil }
	Availability.state = state
end
resetState()

local function compat() return ns.Compat end
local function store() return ns.Store end
local function serverTime() return compat().ServerTime() end
local function ownGUID() return compat().Player.GUID() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function demo() return ns.Demo ~= nil and ns.Demo:IsActive() end

function Availability.Enabled() return ns.Features ~= nil and ns.Features.On("season") end

-- "Share when I usually play": on unless the player switched it off (a damaged value counts as the default).
function Availability.Sharing()
	local C = ns.Config
	return not (C and C.db and C.db.account and C:Get("account.settings.shareAvailability") == false)
end

---------------------------------------------------------------------------------------------------------------------
-- Weeks, cells and levels (pure)
---------------------------------------------------------------------------------------------------------------------
-- The week (Monday first) and the cell 0..167 of a realm date and hour; `day` counts days since 1970-01-01, a Thursday.
function Availability.Cell(day, hour)
	return floor((day + 3) / 7), (day + 3) % 7 * 24 + hour
end

-- The week and the cell of now on the realm's clock (the server time read as UTC when the client does not say).
function Availability.Now()
	local C = compat()
	local t = C.RealmTime()
	local stamp = t and ns.Calendar.Stamp(t.year, t.month, t.day, t.hour, 0) or C.ServerTime()
	local day = floor(stamp / DAY)
	return Availability.Cell(day, floor((stamp - day * DAY) / 3600))
end

local function whole(v, low, high) return type(v) == "number" and v == floor(v) and v >= low and v <= high end

-- The saved count within its rules, seen from week `week`: weeks out of the window (or from a clock that ran ahead) and
-- damaged values are dropped.
function Availability.Clean(data, week)
	if type(data) ~= "table" then data = {} end
	local weeks = {}
	for k, cells in pairs(type(data.weeks) == "table" and data.weeks or {}) do
		if whole(k, 0, 100000) and k <= week and k >= week - Availability.WEEKS and type(cells) == "table" then
			for cell, minutes in pairs(cells) do
				if not (whole(cell, 0, Availability.CELLS - 1) and whole(minutes, 1, 60)) then cells[cell] = nil end
			end
			weeks[k] = cells
		end
	end
	data.weeks = weeks
	if not whole(data.since, 0, 100000) or data.since > week then data.since = week end
	return data
end

-- The 168 levels of a count seen at (week, cell): a table [0..167] = 0..3, and how many weeks were measured.
function Availability.Levels(data, week, cell)
	local N, need = Availability.WEEKS, Availability.MIN_MINUTES
	local levels = {}
	for h = 0, Availability.CELLS - 1 do
		local present, total = 0, 0
		local k = week
		while k >= data.since and k >= week - N and total < N do
			local minutes = data.weeks[k] and data.weeks[k][h] or 0
			local there = minutes >= need
			-- an hour of this week that is not over counts only once the account was there
			if k < week or h < cell or there then
				total = total + 1
				if there then present = present + 1 end
			end
			k = k - 1
		end
		local level = 0
		if present > 0 then
			if present * 4 < total then level = 1
			elseif present * 2 <= total then level = 2
			else level = 3 end
		end
		levels[h] = level
	end
	return levels, max(1, min(N, week - data.since + 1))
end

local POW = { [0] = 1, 4, 16, 64 }

-- 168 levels -> 42 bytes (the first cell in the low bits of the first byte).
function Availability.Encode(levels)
	local out = {}
	for i = 0, Availability.BYTES - 1 do
		local b = 0
		for j = 0, 3 do b = b + (levels[i * 4 + j] or 0) * POW[j] end
		out[i + 1] = char(b)
	end
	return concat(out)
end

-- 42 bytes -> the levels [0..167], or nil.
function Availability.Decode(p)
	if type(p) ~= "string" or #p ~= Availability.BYTES then return nil end
	local levels = {}
	for i = 0, Availability.BYTES - 1 do
		local b = byte(p, i + 1)
		for j = 0, 3 do levels[i * 4 + j] = floor(b / POW[j]) % 4 end
	end
	return levels
end

---------------------------------------------------------------------------------------------------------------------
-- The record
---------------------------------------------------------------------------------------------------------------------
local FIELDS = { id = true, author = true, rev = true, time = true }

-- The owner rule of the set (Net/Store.lua): a character of the author's account, and nothing but the levels and the
-- weeks measured (or the withdrawal).
function Availability.ValidRecord(rec, s)
	s = s or store()
	if type(rec) ~= "table" or type(rec.id) ~= "string" or not rec.id:find(s.GUID_PATTERN) then return false end
	if not s:SameAccount(rec.id, rec.author) then return false end
	local withdrawn = rec.del ~= nil
	for k in pairs(rec) do
		if not (FIELDS[k] or (withdrawn and k == "del") or (not withdrawn and (k == "p" or k == "w"))) then return false end
	end
	if withdrawn then return rec.del == true end
	return type(rec.p) == "string" and #rec.p == Availability.BYTES and whole(rec.w, 1, Availability.WEEKS)
end

function Availability.Expired(rec, t)
	return (rec.time or 0) < t - Availability.RETENTION
end

---------------------------------------------------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------------------------------------------------
-- The account's own count (AzerothAccordDB.avail), cleaned; nil while the saved data may not be written or is not
-- loaded.
local function localData(week)
	local C = ns.Config
	local db = C and C.db and C.db.account
	if not db then return nil end
	if type(db.avail) ~= "table" then db.avail = {} end
	return Availability.Clean(db.avail, week)
end

-- One count: a minute online in the cell of now. Returns true when it was counted. Looks at publishing once an hour.
function Availability:Tick()
	if not Availability.Enabled() then return false end
	local week, cell = Availability.Now()
	local data = localData(week)
	if not data then return false end
	local cells = data.weeks[week]
	if not cells then cells = {} data.weeks[week] = cells end
	local minutes = cells[cell] or 0
	state.stats.ticks = state.stats.ticks + 1
	if minutes < 60 then
		cells[cell] = minutes + 1
		-- the own map changes when an hour starts to count
		if minutes + 1 == Availability.MIN_MINUTES then self:Changed() end
	end
	if state.ready and (not state.lastCheck or compat().Now() - state.lastCheck >= Availability.CHECK_EVERY) then
		state.lastCheck = compat().Now()
		self:Publish()
	end
	return true
end

-- The own levels now: levels [0..167], weeks measured; nil without saved data.
function Availability:Own()
	if not Availability.Enabled() then return nil end
	local week, cell = Availability.Now()
	local data = localData(week)
	if not data then return nil end
	return Availability.Levels(data, week, cell)
end

---------------------------------------------------------------------------------------------------------------------
-- Publishing
---------------------------------------------------------------------------------------------------------------------
local function done(ok, why)
	state.last = why or (ok and "published") or nil
	return ok, why
end

-- The records of this account in the guild's store, sorted by id.
local function ownRecords()
	local S, me = store(), ownGUID()
	local out = {}
	for id, rec in pairs(S:Records(Availability.SET)) do
		if type(rec) == "table" and S:SameAccount(me, id) then out[#out + 1] = rec end
	end
	sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- Takes every published record of this account back (one `del` each). Returns true and how many, or false and "nothing".
function Availability:Withdraw()
	local n = 0
	for _, rec in ipairs(ownRecords()) do
		if rec.del ~= true and store():Put(Availability.SET, rec.id, { del = true }) then n = n + 1 end
	end
	if n == 0 then return done(false, "nothing") end
	state.stats.withdrawn = state.stats.withdrawn + n
	state.last = "withdrawn"
	return true, n
end

-- Writes the account's levels when due, or takes them back when sharing is off. Returns true when it wrote, or false and
-- the reason: "off", "demo", "guild", "player", "data", "nothing", "unchanged", "recent", or a reason of Store:Put.
function Availability:Publish()
	if not Availability.Enabled() then return false, "off" end
	if demo() then return false, "demo" end
	local S = store()
	if not (S and ns.GuildKey and ns.GuildKey:Current()) then return done(false, "guild") end
	local me = ownGUID()
	if not me then return done(false, "player") end
	if not Availability.Sharing() then return self:Withdraw() end
	local levels, weeks = self:Own()
	if not levels then return done(false, "data") end
	local p = Availability.Encode(levels)
	local newest
	for _, rec in ipairs(ownRecords()) do
		if not newest or (rec.time or 0) > (newest.time or 0) then newest = rec end
	end
	local published = newest ~= nil and newest.del ~= true
	-- nothing to say yet
	if not published and p == ("\0"):rep(Availability.BYTES) then return done(false, "nothing") end
	if published then
		local age = serverTime() - (newest.time or 0)
		if newest.p == p and age <= Availability.REFRESH_AGE then
			state.stats.unchanged = state.stats.unchanged + 1
			return done(false, "unchanged")
		end
		local every = weeks > 1 and Availability.PUBLISH_EVERY or Availability.FIRST_WEEK_EVERY
		if age < every then return done(false, "recent") end
	end
	local rec, why = S:Put(Availability.SET, me, { p = p, w = weeks })
	if not rec then return done(false, why) end
	state.stats.published = state.stats.published + 1
	return done(true)
end

local function schedule(key, seconds, fn)
	if state[key] then state[key]:Cancel() end
	state[key] = compat().NewTimer(seconds, function()
		state[key] = nil
		fn()
	end)
end

-- The first HELLO of a session (or of a new guild) starts the first check; the ticks look again afterwards.
function Availability:OnHello()
	if not Availability.Enabled() or state.armed or demo() then return false end
	state.armed = true
	local r = Availability.FIRST_DELAY
	schedule("first", r[1] + (r[2] - r[1]) * random(), function()
		state.ready, state.lastCheck = true, compat().Now()
		Availability:Publish()
	end)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Reading (the view)
---------------------------------------------------------------------------------------------------------------------
local function accountOf(guid)
	return ns.Accounts and ns.Accounts:AccountKey(guid) or guid
end

local function inGuild(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	if e and not e.notInGuild then return e end
	return nil
end

local function nameOf(guid)
	local main = ns.Accounts and ns.Accounts:MainOf(guid)
	local e = (main and inGuild(main.guid)) or inGuild(guid)
	return e and (e.short or e.name) or "?"
end

-- The members who share, one per account (the newest record of its characters in the guild; a withdrawal hides it):
-- { { account, guid, levels, weeks }, ... } by account.
local function build()
	if ns.Accounts then ns.Accounts:Groups() end   -- rebuilt first: it announces itself, which drops the cache
	local S, t = store(), serverTime()
	local newest = {}
	for id, rec in pairs(S and S:Records(Availability.SET) or {}) do
		if type(rec) == "table" and not Availability.Expired(rec, t) and inGuild(id) then
			local key = accountOf(id)
			local held = newest[key]
			local a, b = rec.time or 0, held and held.time or 0
			if not held or a > b or (a == b and id < held.id) then newest[key] = rec end
		end
	end
	local out = {}
	for key, rec in pairs(newest) do
		local levels = rec.del ~= true and Availability.Decode(rec.p)
		if levels then out[#out + 1] = { account = key, guid = rec.id, levels = levels, weeks = rec.w } end
	end
	sort(out, function(a, b) return a.account < b.account end)
	return out
end

local function members()
	if not state.cache then
		local built = build()
		state.cache = built
	end
	return state.cache
end

-- The guild's map as everybody may see it, without names: { total = accounts that share, own = whether this account is
-- one of them, max = the highest count of a cell, cells = { [0..167] = { n = accounts usually online (level >= USUAL),
-- levels = { [1] = , [2] = , [3] = } } } }.
function Availability:Map()
	local cells = {}
	for h = 0, Availability.CELLS - 1 do cells[h] = { n = 0, levels = { 0, 0, 0 } } end
	local out = { total = 0, own = false, max = 0, cells = cells }
	if not Availability.Enabled() then return out end
	local me = ownGUID()
	local mine = me and accountOf(me)
	for _, m in ipairs(members()) do
		out.total = out.total + 1
		if m.account == mine then out.own = true end
		for h = 0, Availability.CELLS - 1 do
			local level = m.levels[h]
			if level > 0 then
				local c = cells[h]
				c.levels[level] = c.levels[level] + 1
				if level >= Availability.USUAL then
					c.n = c.n + 1
					if c.n > out.max then out.max = c.n end
				end
			end
		end
	end
	return out
end

-- true when this character may see who is online in a cell (not only its own account).
function Availability.CanSeeNames()
	local who = Availability.NAMES_VISIBLE_TO
	if who == "members" then return ns.Role ~= nil and ns.Role:InGuild() end
	if who ~= "officers" then return false end
	return ns.Role ~= nil and ns.Role:IsOfficer() == true
end

-- In how many cells both accounts are usually online (level >= USUAL), for whoever may see who is online (Q23); 0 else,
-- and for an account that shares nothing.
function Availability:Common(a, b)
	if not (Availability.Enabled() and Availability.CanSeeNames()) then return 0 end
	local x, y
	for _, m in ipairs(members()) do
		if m.account == a then x = m.levels end
		if m.account == b then y = m.levels end
	end
	if not (x and y) then return 0 end
	local n = 0
	for h = 0, Availability.CELLS - 1 do
		if x[h] >= Availability.USUAL and y[h] >= Availability.USUAL then n = n + 1 end
	end
	return n
end

-- Who has played in the cell, as far as this character may see it: { { account, name (the main's), level, weeks, own },
-- ... }, the most often first. Officers and the Guild Master get every account; anybody else only the own one.
function Availability:Who(cell)
	local out = {}
	if not Availability.Enabled() or not whole(cell, 0, Availability.CELLS - 1) then return out end
	local me = ownGUID()
	local mine = me and accountOf(me)
	local all = Availability.CanSeeNames()
	for _, m in ipairs(members()) do
		local level = m.levels[cell]
		if level > 0 and (all or m.account == mine) then
			out[#out + 1] = { account = m.account, name = nameOf(m.guid), level = level, weeks = m.weeks, own = m.account == mine }
		end
	end
	sort(out, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		local x, y = a.name:lower(), b.name:lower()
		if x ~= y then return x < y end
		return a.account < b.account
	end)
	return out
end

-- FDCP's declared days, for officers while FDCP is the source of the season roster: { [1 (Monday)..7] = { names } }, or
-- nil (another source, not an officer, no pool, no day declared). A declaration, not a measurement.
function Availability:Declared()
	if not (Availability.Enabled() and Availability.CanSeeNames()) then return nil end
	local I = ns.Integrations
	if not (I and I:Source("raid") == "fdcp" and I:Level("fdcp") == 1 and ns.FDCP and ns.FDCP.Ready()) then return nil end
	local out, any = { {}, {}, {}, {}, {}, {}, {} }, false
	for _, e in ipairs(ns.FDCP.Pool() or {}) do
		for _, token in ipairs(e.avail or {}) do
			local d = Availability.FDCP_DAYS[token]
			if d then
				local list = out[d]
				list[#list + 1] = (compat().SplitName(e.name))
				any = true
			end
		end
	end
	return any and out or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Changes
---------------------------------------------------------------------------------------------------------------------
function Availability:Changed()
	if not Availability.Enabled() then return end
	state.cache = nil
	if state.emitting then return end
	state.emitting = true
	local mine = state
	compat().After(Availability.EMIT_DELAY, function()
		if state ~= mine then return end
		state.emitting = false
		state.cache = nil
		emit("AVAILABILITY_CHANGED")
	end)
end

function Availability:OnStoreChanged(set, id, origin)
	if not Availability.Enabled() then return end
	if set ~= Availability.SET and set ~= "accounts" then return end
	self:Changed()
	-- a record of this account came back while sharing is off: take it back too
	if set == Availability.SET and origin == "remote" and id and not Availability.Sharing() then
		local me = ownGUID()
		if me and store():SameAccount(me, id) then
			schedule("switch", Availability.SWITCH_DELAY, function() Availability:Publish() end)
		end
	end
end

function Availability:OnSetting(key)
	if not Availability.Enabled() then return end
	if key == "shareAvailability" or key == "backup" then   -- a backup may bring the switch of another computer
		schedule("switch", Availability.SWITCH_DELAY, function() Availability:Publish() end)
		self:Changed()
	elseif key == "clear" then
		self:Changed()
	end
end

function Availability:OnGuildChanged()
	resetState()
	self:Changed()
end

function Availability:Start()
	if not (self.AUTO and Availability.Enabled()) or state.ticker then return false end
	state.ticker = compat().NewTicker(Availability.TICK, function() Availability:Tick() end)
	return state.ticker ~= nil
end

function Availability:DebugLines()
	local s = state.stats
	local _, weeks = self:Own()
	return {
		("Availability: %d record(s) held; sharing %s, %s week(s) measured, %d count(s); published %d, unchanged %d, withdrawn %d, last %s"):format(
			store() and store():Count(Availability.SET) or 0, Availability.Sharing() and "on" or "off", tostring(weeks or "?"),
			s.ticks, s.published, s.unchanged, s.withdrawn, tostring(state.last)),
	}
end

if ns.addon then
	ns.addon.Availability = Availability
	if ns.Bus then
		ns.Bus:On("SYNC_HELLO", function(sent) if sent then Availability:OnHello() end end)
		ns.Bus:On("STORE_CHANGED", function(set, id, origin) Availability:OnStoreChanged(set, id, origin) end)
		ns.Bus:On("SETTINGS_CHANGED", function(key) Availability:OnSetting(key) end)
		ns.Bus:On("GUILD_CHANGED", function() Availability:OnGuildChanged() end)
		for _, event in ipairs({ "ROSTER_UPDATED", "ACCOUNTS_UPDATED", "DEMO_CHANGED", "BACKUP_IMPORTED", "ROLE_CHANGED", "SOURCES_CHANGED", "FDCP_CHANGED" }) do
			ns.Bus:On(event, function() Availability:Changed() end)
		end
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Availability.Enabled() then return end
			Availability:Start()
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Availability", function() return Availability:DebugLines() end) end
		end)
	end
end

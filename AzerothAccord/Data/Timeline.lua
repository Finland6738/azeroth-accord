-- Timeline: the roster changes an officer observed, with their date and observer (SPEC-12 §2, M8.2). Lua 5.1.
--
--   Observation  An officer's client keeps a snapshot of the roster (GuildKey:Data().officer.snap) and compares each complete
--                read with it: join, leave, rank, level and public note changes become events { k, g, n, a, b, ... } with
--                `a` = the last time the old value was seen and `b` = the time of this read (TL-03). The first read is the
--                base and makes no event (TL-02); an incomplete read, or a change of a big part of the guild that no second
--                read confirms, changes nothing (TL-01, TL-04). A member's client observes nothing.
--   Events       Wait 60-300 s (Timeline.WAIT) in `officer.pend`, then are written into the officer's own records of the set
--                `timeline` (one record per observer, day and part: at most 60 events and 8 KB each, four parts a day, TL-05),
--                unless another observer already wrote the same change (`confirmed`, §2.3). A character's level-ups of one
--                day are one event (TL-06). A record is deleted 365 days after its day (TL-07).
--   Two observers  The same change seen by two officers is ONE event when it is read (Timeline:Events, TL-08, TL-09): the same
--                kind, character and values, and intervals that overlap within 300 s; the merged event has the narrowest
--                interval and lists every observer.
--   Visibility   Officer.CanSee("timeline"): nothing here is returned to a member, and a member's client holds no record
--                (OFF-01, Net/Store.lua). Sharing is the sync's business (Net/Sync.lua): on OFFICER, only once S5 is proven.
-- Bus: TIMELINE_CHANGED() when the events of the guild changed (a write or an accepted record).
local ADDON_NAME, ns = ...
ns = ns or {}
local Timeline = {}
ns.Timeline, ns.modules = Timeline, ns.modules or {}
ns.modules.Timeline = Timeline

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, abs, min, max, random = math.floor, math.abs, math.min, math.max, math.random
local sort, insert = table.sort, table.insert

Timeline.AUTO = true                 -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Timeline.SET = "timeline"
Timeline.WAIT = { 60, 300 }          -- seconds an observed event waits before it is written (TL-§2.1)
Timeline.TOLERANCE = 300             -- seconds each interval is widened by when two events are compared (TL-08)
Timeline.RETENTION = 365             -- days a record is kept, counted from its day (TL-07)
Timeline.GONE_DAYS = 400             -- days `gone` is kept
Timeline.MAX_EVENTS = 60             -- events in one part (TL-05)
Timeline.MAX_PARTS = 4               -- parts in one day
Timeline.PUBLISH_EVERY = 600         -- the record of a day goes out on OFFICER at most this often (Store.SETS.timeline.publishEvery)
Timeline.MASS_COUNT, Timeline.MASS_FRACTION, Timeline.MASS_CONFIRM = 10, 0.25, 120   -- TL-04
Timeline.READ_MIN = 30               -- seconds between two reads of the roster
Timeline.READ_DELAY = 5              -- seconds the read waits after GUILD_ROSTER_UPDATE (it comes in bursts)
Timeline.POLL = 900                  -- the roster is asked for this often while the character is an officer
Timeline.SHOWN = 10                  -- lines of the member card before "Show all"
Timeline.NOTE_MAX, Timeline.NAME_MAX, Timeline.RANK_MAX = 64, 48, 32
Timeline.KINDS = { "join", "leave", "rank", "level", "note" }

local DAY = 86400

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function store() return ns.Store end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function myGUID() return compat().Player.GUID() end

local state
local function resetState()
	state = {
		index = nil,                 -- the events of the store by character, rebuilt when the store changed
		merged = nil,                -- the merged events of every character, from the same index
		readTimer = nil, flushTimer = nil, flushAt = nil, ticker = nil, lastRead = nil,
		stats = { reads = 0, bases = 0, applied = 0, incomplete = 0, held = 0, observed = 0, written = 0, confirmed = 0,
			dropped = 0, invalid = 0, grouped = 0 },
	}
	Timeline.state = state
end
resetState()

---------------------------------------------------------------------------------------------------------------------
-- Days
---------------------------------------------------------------------------------------------------------------------
-- Days since 1970-01-01 of a civil date (proleptic Gregorian).
local function daysFromCivil(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- The number of days since 1970-01-01 of a day written YYYYMMDD, or nil when it is not a date (2000..2099).
function Timeline.DayNumber(day)
	if type(day) ~= "number" or day ~= floor(day) then return nil end
	local y, m, d = floor(day / 10000), floor(day / 100) % 100, day % 100
	if y < 2000 or y > 2099 or m < 1 or m > 12 or d < 1 then return nil end
	local dim = MONTH_DAYS[m]
	if m == 2 and (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) then dim = 29 end
	if d > dim then return nil end
	return daysFromCivil(y, m, d)
end

-- The UTC day of a server time, as YYYYMMDD.
function Timeline.DayOf(t)
	return tonumber(date("!%Y%m%d", t))
end

-- true when the record's day is more than RETENTION days old (the store's `expires`, TL-07: by the day, not the write time).
function Timeline.Expired(rec, t)
	local n = type(rec) == "table" and Timeline.DayNumber(rec.day)
	if not n then return false end
	return floor(t / DAY) - n > Timeline.RETENTION
end

---------------------------------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------------------------------
-- `text` without control characters, cut to `limit` bytes at a character boundary (UTF-8).
function Timeline.Clean(text, limit)
	if type(text) ~= "string" then return "" end
	text = text:gsub("%c", "")
	if #text <= limit then return text end
	local at = limit
	while at > 0 do
		local nextByte = text:byte(at + 1)
		if nextByte and nextByte >= 0x80 and nextByte < 0xC0 then at = at - 1 else break end
	end
	return text:sub(1, at)
end
local clean = Timeline.Clean

---------------------------------------------------------------------------------------------------------------------
-- Shape of events and records (OFF-03: the owner rule of the set)
---------------------------------------------------------------------------------------------------------------------
local function isInt(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end
local function isName(v, max) return type(v) == "string" and #v >= 1 and #v <= max and not v:find("%c") end
local function isText(v) return type(v) == "string" and #v <= Timeline.NOTE_MAX and not v:find("%c") end

local CHECK = {
	idx = function(v) return isInt(v, 0, 19) end,
	level = function(v) return isInt(v, 1, 200) end,
	name = function(v) return isName(v, Timeline.RANK_MAX) end,
	text = isText,
}
local FIELDS = {
	join = { r = "idx", rn = "name", l = "level" },
	leave = { rn = "name", l = "level" },
	rank = { f = "idx", t = "idx", fn = "name", tn = "name" },
	level = { f = "level", t = "level" },
	note = { f = "text", t = "text" },
}
local REQUIRED = { rank = { "f", "t" }, level = { "f", "t" }, note = { "f", "t" } }
local COMMON = { k = true, g = true, n = true, a = true, b = true }

-- true when `ev` is a well-formed event; `day` (YYYYMMDD) is the day of the record it sits in.
function Timeline.ValidEvent(ev, day)
	if type(ev) ~= "table" then return false end
	local fields = FIELDS[ev.k]
	if not fields then return false end
	if not (type(ev.g) == "string" and #ev.g <= 40 and ev.g:find(store().GUID_PATTERN)) then return false end
	if not isName(ev.n, Timeline.NAME_MAX) then return false end
	if not (isInt(ev.a, 0, 4294967295) and isInt(ev.b, 0, 4294967295) and ev.a <= ev.b) then return false end
	if day ~= nil and Timeline.DayOf(ev.b) ~= day then return false end
	for key, value in pairs(ev) do
		if not COMMON[key] then
			local kind = fields[key]
			if not kind or not CHECK[kind](value) then return false end
		end
	end
	for _, key in ipairs(REQUIRED[ev.k] or {}) do
		if ev[key] == nil then return false end
	end
	return true
end

local ALLOWED = { id = true, author = true, rev = true, time = true, observer = true, day = true, ev = true }

-- The owner rule of the set `timeline` (Store.SETS.timeline.owner): the observer wrote it itself, in the day and the part
-- its id says, and every event is well-formed.
function Timeline.ValidRecord(rec)
	if type(rec) ~= "table" then return false end
	for key in pairs(rec) do if not ALLOWED[key] then return false end end
	if type(rec.observer) ~= "string" or rec.observer ~= rec.author then return false end
	if not Timeline.DayNumber(rec.day) then return false end
	local part = type(rec.id) == "string" and rec.id:match("^" .. rec.observer:gsub("%p", "%%%0") .. ":" .. rec.day .. ":(%d)$")
	part = tonumber(part)
	if not part or part < 1 or part > Timeline.MAX_PARTS then return false end
	local list = rec.ev
	if type(list) ~= "table" or #list > Timeline.MAX_EVENTS then return false end
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	if n ~= #list then return false end
	for _, ev in ipairs(list) do
		if not Timeline.ValidEvent(ev, rec.day) then return false end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Identity and merging (TL-08, TL-09)
---------------------------------------------------------------------------------------------------------------------
local function sameValues(x, y)
	if x.k ~= y.k or x.g ~= y.g then return false end
	local k = x.k
	if k == "rank" or k == "note" then return x.f == y.f and x.t == y.t end
	if k == "level" then return x.t == y.t end
	return true
end

local function overlap(xa, xb, ya, yb)
	local tol = Timeline.TOLERANCE
	return xa - tol <= yb + tol and ya - tol <= xb + tol
end

-- true when two events are the same change (TL-08).
function Timeline.Same(x, y)
	return sameValues(x, y) and overlap(x.a, x.b, y.a, y.b)
end

local function copyEvent(ev)
	local out = {}
	for k, v in pairs(ev) do out[k] = v end
	return out
end

local function byB(x, y)
	if x.ev.b ~= y.ev.b then return x.ev.b < y.ev.b end
	if x.obs ~= y.obs then return x.obs < y.obs end
	return x.ev.a < y.ev.a
end

-- The events of one character as the officers saw them (`entries` = { { ev, obs }, ... }), merged: the same change seen by
-- several observers is one event with the narrowest interval and every observer (TL-09). Newest first.
function Timeline.Merge(entries)
	local list = {}
	for i, e in ipairs(entries) do list[i] = e end
	sort(list, byB)
	local clusters = {}
	for _, e in ipairs(list) do
		local ev = e.ev
		local best, bestDistance
		for _, c in ipairs(clusters) do
			if not c.has[e.obs] and sameValues(c, ev) and overlap(c.a, c.b, ev.a, ev.b) then
				local d = abs(c.b - ev.b)
				if not best or d < bestDistance then best, bestDistance = c, d end
			end
		end
		if best then
			best.a, best.b = max(best.a, ev.a), min(best.b, ev.b)
			if best.a > best.b then best.a = best.b end
			if best.k == "level" and ev.f < best.f then best.f = ev.f end
			best.has[e.obs] = true
			best.observers[#best.observers + 1] = { guid = e.obs, b = ev.b }
		else
			local c = copyEvent(ev)
			c.has, c.observers = { [e.obs] = true }, { { guid = e.obs, b = ev.b } }
			clusters[#clusters + 1] = c
		end
	end
	for _, c in ipairs(clusters) do c.has = nil end
	sort(clusters, function(x, y)
		if x.b ~= y.b then return x.b > y.b end
		return (x.g .. x.k) < (y.g .. y.k)
	end)
	return clusters
end

---------------------------------------------------------------------------------------------------------------------
-- Reading the store
---------------------------------------------------------------------------------------------------------------------
-- character GUID -> { { ev, obs, rec }, ... } over every record of the set, rebuilt after a change of the set.
local function buildIndex()
	local byG = {}
	for _, rec in pairs(store():Records(Timeline.SET)) do
		if type(rec) == "table" and type(rec.ev) == "table" then
			local obs = rec.observer or rec.author
			for _, ev in ipairs(rec.ev) do
				if type(ev) == "table" and type(ev.g) == "string" then
					local list = byG[ev.g]
					if not list then list = {} byG[ev.g] = list end
					list[#list + 1] = { ev = ev, obs = obs, rec = rec }
				end
			end
		end
	end
	return byG
end

function Timeline:Index()
	if not state.index then state.index = buildIndex() end
	return state.index
end

function Timeline:Invalidate()
	state.index, state.merged = nil, nil
end

-- The merged events of one character, newest first (empty for whoever may not see the timeline).
function Timeline:Events(guid)
	if not ns.Officer.CanSee("timeline") or type(guid) ~= "string" then return {} end
	local list = self:Index()[guid]
	if not list then return {} end
	return Timeline.Merge(list)
end

-- Every merged event of the guild, newest first.
function Timeline:All()
	if not ns.Officer.CanSee("timeline") then return {} end
	if state.merged then return state.merged end
	local out = {}
	for _, list in pairs(self:Index()) do
		for _, e in ipairs(Timeline.Merge(list)) do out[#out + 1] = e end
	end
	sort(out, function(x, y)
		if x.b ~= y.b then return x.b > y.b end
		return (x.g .. x.k) < (y.g .. y.k)
	end)
	state.merged = out
	return out
end

-- The merged events of several characters (the characters of one account), newest first.
function Timeline:EventsOf(guids)
	local out = {}
	for _, guid in ipairs(guids or {}) do
		for _, e in ipairs(self:Events(guid)) do out[#out + 1] = e end
	end
	sort(out, function(x, y)
		if x.b ~= y.b then return x.b > y.b end
		return (x.g .. x.k) < (y.g .. y.k)
	end)
	return out
end

-- The time of the oldest known join among `events` (nil when none): "Member since".
function Timeline.OldestJoin(events)
	local oldest
	for _, e in ipairs(events or {}) do
		if e.k == "join" and (not oldest or e.b < oldest) then oldest = e.b end
	end
	return oldest
end

---------------------------------------------------------------------------------------------------------------------
-- Observation (§2.1)
---------------------------------------------------------------------------------------------------------------------
local function entryOf(row)
	return {
		n = clean(row.name, Timeline.NAME_MAX), r = row.rankIndex, rn = row.rankName and clean(row.rankName, Timeline.RANK_MAX) or nil,
		l = row.level, p = clean(row.note, Timeline.NOTE_MAX),
	}
end

local function validIndex(r) return type(r) == "number" and r == floor(r) and r >= 0 and r <= 19 end
local function validLevel(l) return type(l) == "number" and l == floor(l) and l >= 1 and l <= 200 end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- true when the observer works now: an officer's character, in a guild, outside demo mode, with a writable account.
function Timeline:Eligible()
	if ns.Demo and ns.Demo:IsActive() then return false end
	if not (ns.Role and ns.Role:IsOfficer() and ns.GuildKey and ns.GuildKey:Current()) then return false end
	if ns.Config and ns.Config.IsReadOnly and ns.Config:IsReadOnly("account") then return false end
	return myGUID() ~= nil
end

-- The roster read as the snapshot needs it: rows = { { guid, name, rankIndex, rankName, level, note } }, complete = true when
-- the client's count equals the rows read and every row has a GUID (TL-01).
function Timeline.ReadRoster()
	local G = compat().Guild
	local rows = G.Roster()
	local total = tonumber((G.RosterCount())) or 0
	local complete = total > 0 and #rows == total
	if complete then
		for _, row in ipairs(rows) do
			if type(row.guid) ~= "string" or type(row.name) ~= "string" or row.name == "" then complete = false break end
		end
	end
	return rows, complete
end

local function signature(leaves, ranks)
	sort(leaves)
	sort(ranks)
	return ns.Hash.Fast(table.concat(leaves, ",") .. "|" .. table.concat(ranks, ","))
end

-- Compares a complete read with the snapshot. Returns "off" (cannot observe), "incomplete", "base" (the first read), "held" (a
-- mass change waiting for a second read, TL-04) or "applied" (events queued, the snapshot updated), plus the number of events.
function Timeline:Observe(rows, t, complete)
	local O = ns.Officer:Data()
	if not O then return "off", 0 end
	state.stats.reads = state.stats.reads + 1
	if complete ~= true then
		state.stats.incomplete = state.stats.incomplete + 1
		return "incomplete", 0
	end
	t = floor(t)
	local current = {}
	for _, row in ipairs(rows) do
		if type(row.guid) == "string" then current[row.guid] = entryOf(row) end
	end
	local snap = O.snap
	if type(snap) ~= "table" or type(snap.m) ~= "table" then
		O.snap, O.gone, O.hold = { at = t, m = current }, O.gone or {}, nil
		state.stats.bases = state.stats.bases + 1
		return "base", 0
	end
	local events, leaves, ranks = {}, {}, {}
	local from, to = floor(snap.at or t), t
	if from > to then from = to end
	local function ev(k, guid, name, fields)
		local e = { k = k, g = guid, n = (type(name) == "string" and name ~= "") and name or "?", a = from, b = to }
		for key, value in pairs(fields or {}) do e[key] = value end
		events[#events + 1] = e
		return e
	end
	for guid, new in pairs(current) do
		local old = snap.m[guid]
		if not old then
			ev("join", guid, new.n, { r = validIndex(new.r) and new.r or nil, rn = new.rn ~= "" and new.rn or nil,
				l = validLevel(new.l) and new.l or nil })
		else
			if validIndex(old.r) and validIndex(new.r) and old.r ~= new.r then
				ranks[#ranks + 1] = guid .. ":" .. new.r
				ev("rank", guid, new.n, { f = old.r, t = new.r, fn = old.rn ~= "" and old.rn or nil, tn = new.rn ~= "" and new.rn or nil })
			end
			if validLevel(old.l) and validLevel(new.l) and old.l ~= new.l then
				ev("level", guid, new.n, { f = old.l, t = new.l })
			end
			if (old.p or "") ~= new.p then
				ev("note", guid, new.n, { f = old.p or "", t = new.p })
			end
		end
	end
	for guid, old in pairs(snap.m) do
		if not current[guid] then
			leaves[#leaves + 1] = guid
			ev("leave", guid, (old.n and old.n ~= "") and old.n or "?", { rn = (old.rn and old.rn ~= "") and old.rn or nil,
				l = validLevel(old.l) and old.l or nil })
		end
	end
	-- TL-04: a big part of the guild gone or re-ranked at once is not believed until a second complete read agrees
	local total = count(snap.m)
	local mass = (#leaves > Timeline.MASS_COUNT and #leaves > total * Timeline.MASS_FRACTION)
		or (#ranks > Timeline.MASS_COUNT and #ranks > total * Timeline.MASS_FRACTION)
	if mass then
		local sig = signature(leaves, ranks)
		local hold = O.hold
		if not (type(hold) == "table" and hold.sig == sig and t - (hold.at or t) >= Timeline.MASS_CONFIRM) then
			if not (type(hold) == "table" and hold.sig == sig) then O.hold = { sig = sig, at = t } end
			state.stats.held = state.stats.held + 1
			return "held", 0
		end
	end
	O.hold = nil
	O.snap = { at = t, m = current }
	O.gone = O.gone or {}
	for _, guid in ipairs(leaves) do O.gone[guid] = O.gone[guid] or t end
	for guid in pairs(current) do O.gone[guid] = nil end
	state.stats.applied = state.stats.applied + 1
	if #events > 0 then self:Queue(events, t) end
	return "applied", #events
end

-- Puts observed events in the queue that is saved with the guild's officer data; they are written after WAIT.
function Timeline:Queue(events, t)
	local O = ns.Officer:Data()
	if not O then return end
	if type(O.pend) ~= "table" then O.pend = {} end
	sort(events, function(x, y)
		if x.g ~= y.g then return x.g < y.g end
		return x.k < y.k
	end)
	local due = floor(t + Timeline.WAIT[1] + (Timeline.WAIT[2] - Timeline.WAIT[1]) * random())
	for _, ev in ipairs(events) do
		local merged = false
		if ev.k == "level" then   -- TL-06: a character's level-ups of one waiting batch are one event
			for _, p in ipairs(O.pend) do
				local q = p.ev
				if q.k == "level" and q.g == ev.g and Timeline.DayOf(q.b) == Timeline.DayOf(ev.b) then
					q.t, q.b, q.n = ev.t, ev.b, ev.n
					merged = true
					state.stats.grouped = state.stats.grouped + 1
					break
				end
			end
		end
		if not merged then
			O.pend[#O.pend + 1] = { due = due, ev = ev }
			state.stats.observed = state.stats.observed + 1
		end
	end
	self:Schedule()
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (§2.2, §2.3)
---------------------------------------------------------------------------------------------------------------------
-- true when an event equal to `ev` (TL-08) is already held, from any observer; `list` is the held events of the character.
local function held(list, ev)
	for _, e in ipairs(list or {}) do
		if Timeline.Same(e.ev, ev) then return true end
	end
	return false
end

-- Writes `events` (observed here, waiting time over) into this observer's records of their days. Returns the number of
-- events stored. Events another observer already wrote are only counted (`confirmed`).
function Timeline:Write(events)
	local S, me = store(), myGUID()
	if not (me and ns.Officer:Data()) or #events == 0 then return 0 end
	local def = S.SETS[Timeline.SET]
	local index = self:Index()   -- kept up to date here: the store's events during this write do not rebuild it
	local byDay, days = {}, {}
	for _, ev in ipairs(events) do
		local day = Timeline.DayOf(ev.b)
		if not byDay[day] then byDay[day] = {} days[#days + 1] = day end
		insert(byDay[day], ev)
	end
	sort(days)
	local stored = 0
	for _, day in ipairs(days) do
		-- the observer's own parts of this day, as lists plus the running size of each record
		local parts, sizes, changed = {}, {}, {}
		for p = 1, Timeline.MAX_PARTS do
			local rec = S:Get(Timeline.SET, me .. ":" .. day .. ":" .. p)
			parts[p] = rec and S.Copy(rec.ev) or {}
			local shell = { id = me .. ":" .. day .. ":" .. p, author = me, rev = (rec and rec.rev or 0) + 1, time = now(),
				observer = me, day = day, ev = parts[p] }
			sizes[p] = ns.Config.EstimateSize(shell)
		end
		for _, ev in ipairs(byDay[day]) do
			local done = false
			if ev.k == "level" then   -- TL-06: one level event per character and day for this observer
				for p = 1, Timeline.MAX_PARTS do
					for _, old in ipairs(parts[p]) do
						if old.k == "level" and old.g == ev.g then
							old.t, old.b, old.n = ev.t, ev.b, ev.n
							changed[p], done = true, true
							state.stats.grouped = state.stats.grouped + 1
							break
						end
					end
					if done then break end
				end
			end
			if not done and held(index[ev.g], ev) then
				state.stats.confirmed = state.stats.confirmed + 1
				done = true
			end
			if not done then
				local cost = ns.Config.EstimateSize(ev) + 12
				for p = 1, Timeline.MAX_PARTS do
					if #parts[p] < Timeline.MAX_EVENTS and sizes[p] + cost <= def.maxBytes then
						parts[p][#parts[p] + 1] = ev
						sizes[p], changed[p], done = sizes[p] + cost, true, true
						local list = index[ev.g]
						if not list then list = {} index[ev.g] = list end
						list[#list + 1] = { ev = ev, obs = me, rec = false }
						stored = stored + 1
						break
					end
				end
				if not done then state.stats.dropped = state.stats.dropped + 1 end
			end
		end
		for p = 1, Timeline.MAX_PARTS do
			if changed[p] then
				local rec, why = S:Put(Timeline.SET, me .. ":" .. day .. ":" .. p, { observer = me, day = day, ev = parts[p] })
				if rec then state.stats.written = state.stats.written + 1
				else
					state.stats.invalid = state.stats.invalid + 1
					if ns.addon and ns.addon.Debug then ns.addon:Debug("timeline: record not stored (" .. tostring(why) .. ")") end
				end
			end
		end
	end
	state.index, state.merged = nil, nil
	emit("TIMELINE_CHANGED")
	return stored
end

-- Writes the events whose waiting time is over (all of them when `force`). Returns the number written.
function Timeline:Flush(force)
	local O = ns.Officer:Peek()
	if not O or type(O.pend) ~= "table" then return 0 end
	if not self:Eligible() then return 0 end
	local t = now()
	local due, rest = {}, {}
	for _, p in ipairs(O.pend) do
		if force or p.due <= t then due[#due + 1] = p.ev else rest[#rest + 1] = p end
	end
	O.pend = #rest > 0 and rest or nil
	local stored = self:Write(due)
	self:Schedule()
	return stored
end

-- Sets the timer of the next flush (one timer, for the earliest due time).
function Timeline:Schedule()
	local O = ns.Officer:Peek()
	if not O or type(O.pend) ~= "table" or #O.pend == 0 then return end
	local first
	for _, p in ipairs(O.pend) do if not first or p.due < first then first = p.due end end
	if state.flushAt and state.flushAt <= first and state.flushTimer then return end
	if state.flushTimer then state.flushTimer:Cancel() state.flushTimer = nil end
	local delay = max(1, first - now())
	state.flushAt = first
	state.flushTimer = compat().NewTimer(delay, function()
		state.flushTimer, state.flushAt = nil, nil
		Timeline:Flush()
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Reading the roster by itself (the observation does not depend on a view being open)
---------------------------------------------------------------------------------------------------------------------
-- Reads the roster now and compares it. Returns what Observe returns, or "off".
function Timeline:Read()
	if not self:Eligible() then
		if ns.Officer and ns.Role and not ns.Role:IsOfficer() then ns.Officer:CheckDemotion() end
		return "off", 0
	end
	state.lastRead = compat().Now()
	local rows, complete = Timeline.ReadRoster()
	return self:Observe(rows, now(), complete)
end

-- GUILD_ROSTER_UPDATE comes in bursts: one read after READ_DELAY, and never more than one per READ_MIN seconds.
function Timeline:OnRosterEvent()
	if not self.AUTO or state.readTimer then return end
	local wait = Timeline.READ_DELAY
	if state.lastRead then wait = max(wait, Timeline.READ_MIN - (compat().Now() - state.lastRead)) end
	state.readTimer = compat().NewTimer(wait, function()
		state.readTimer = nil
		Timeline:Read()
	end)
end

-- Asks the server for a fresh roster (the answer is a GUILD_ROSTER_UPDATE), with the limit of ROS-03.
function Timeline.AskRoster()
	if ns.Roster then ns.Roster:Request() else compat().Guild.RequestRoster() end
end

-- Starts the observation (at login and when the role or the guild changes): asks for the roster now and then, and writes
-- the events that were waiting when the game closed.
function Timeline:Start()
	if not self.AUTO or not self:Eligible() then return false end
	if not state.ticker then
		state.ticker = compat().NewTicker(Timeline.POLL, function()
			if Timeline:Eligible() then Timeline.AskRoster() end
		end)
	end
	Timeline.AskRoster()
	self:Schedule()
	self:Prune()
	return true
end

-- Retention: records of days older than RETENTION days, `gone` older than GONE_DAYS.
function Timeline:Prune()
	local removed = store():Prune()
	local O = ns.Officer:Peek()
	if O and type(O.gone) == "table" then
		local limit = now() - Timeline.GONE_DAYS * DAY
		for guid, at in pairs(O.gone) do
			if type(at) ~= "number" or at < limit then O.gone[guid] = nil end
		end
	end
	if removed > 0 then self:Invalidate() end
	return removed
end

---------------------------------------------------------------------------------------------------------------------
-- Text of a line (§2.4)
---------------------------------------------------------------------------------------------------------------------
local function stamp(t) return date("!%Y-%m-%d %H:%M", t) end
local function dayStamp(t) return date("!%Y-%m-%d", t) end

-- The time text of an event: its day and minute, or "between" two days when the interval is longer than a day.
function Timeline.WhenText(ev)
	local L = ns.L
	if ev.b - ev.a > DAY then return L["TL_BETWEEN"]:format(dayStamp(ev.a), dayStamp(ev.b)) end
	return stamp(ev.b)
end

local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (text:gsub("|", "||")) end

-- What happened, without the name and the time: "joined the guild", "level 20 → 27".
function Timeline.WhatText(ev)
	local L = ns.L
	local k = ev.k
	if k == "join" then return L["TL_JOINED"] end
	if k == "leave" then return L["TL_LEFT"] end
	if k == "rank" then
		return L["TL_RANK"]:format(escape(ev.fn or tostring(ev.f)), escape(ev.tn or tostring(ev.t)))
	end
	if k == "level" then return L["TL_LEVEL"]:format(ev.f, ev.t) end
	if k == "note" then return L["TL_NOTE"]:format(escape(ev.f or ""), escape(ev.t or "")) end
	return "?"
end

-- The line of an event: "2026-11-24 21:10 · Name level 20 → 27". `name` overrides the name the event carries (the
-- character's current name from the roster).
function Timeline.LineText(ev, name)
	return ns.L["TL_LINE"]:format(Timeline.WhenText(ev), escape(name or ev.n or "?"), Timeline.WhatText(ev))
end

-- The names of the observers of a merged event, for the tooltip: this player as "you", a member of the roster by name, anyone
-- else as "a former officer" (never a GUID).
function Timeline.ObserverNames(ev)
	local L, names = ns.L, {}
	local me = myGUID()
	for _, o in ipairs(ev.observers or {}) do
		if o.guid == me then names[#names + 1] = L["TL_YOU"]
		else
			local entry = ns.Roster and ns.Roster:ByGUID(o.guid)
			names[#names + 1] = entry and escape(entry.short or entry.name) or L["TL_FORMER"]
		end
	end
	return names
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
function Timeline:DebugLines()
	local s = state.stats
	local O = ns.GuildKey and ns.GuildKey:Current() and ns.Officer:Peek()
	local waiting = O and type(O.pend) == "table" and #O.pend or 0
	local parts = ns.Store and ns.GuildKey and ns.GuildKey:Current() and ns.Store:Count(Timeline.SET) or 0
	return {
		("Timeline: %s, %d record(s), %d event(s) waiting, snapshot %s"):format(self.AUTO and "automatic" or "manual", parts, waiting,
			O and O.snap and "held" or "none"),
		("  reads %d (base %d, applied %d, incomplete %d, held %d); observed %d, written %d records, confirmed %d, grouped %d, dropped %d, invalid %d"):format(
			s.reads, s.bases, s.applied, s.incomplete, s.held, s.observed, s.written, s.confirmed, s.grouped, s.dropped, s.invalid),
	}
end

if ns.addon then
	ns.addon.Timeline = Timeline
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Timeline", function() return Timeline:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Timeline)
	Timeline:RegisterEvent("GUILD_ROSTER_UPDATE", function() Timeline:OnRosterEvent() end)
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set) if set == Timeline.SET then Timeline:Invalidate() emit("TIMELINE_CHANGED") end end)
		ns.Bus:On("GUILD_CHANGED", function()
			for _, key in ipairs({ "readTimer", "flushTimer", "ticker" }) do
				if state[key] then state[key]:Cancel() end
			end
			resetState()
			Timeline:Start()
		end)
		ns.Bus:On("ROLE_CHANGED", function() Timeline:Start() end)
		ns.Bus:On("DEMO_CHANGED", function() Timeline:Invalidate() end)
		ns.Bus:On("BACKUP_IMPORTED", function() Timeline:Invalidate() end)
	end
	if ns.OnEnable then ns.OnEnable(function() Timeline:Start() end) end
end

-- Rallies: PvP and world rallies, a quick call to the guild with a meeting point in words (SPEC-14 §9, M10.9). Lua 5.1.
--
-- Any member with the addon may call one (SPEC-10 Q24); a character has one open rally and calls at most PER_HOUR in an
-- hour; only the caller changes or closes it. No officer moderation. Accord never reads the position of the player and a
-- record takes no field but those below: no coordinate and no map ever travels.
--
-- Rally   a record of the data set `rally` (Net/Store.lua): id "<caller GUID>:<n>", author = the caller, and
--           kind    pvp | world
--           text    the meeting point in words, 1-60 characters (no "|", no control characters, trimmed)
--           created server time of the call
--           start   created .. created + 2 hours
--           ends    start + 15 minutes .. start + 2 hours
--           closed  true once the caller closed it (also when the caller calls another)
-- Answer  a record of the same set: id "<rally id>:<GUID>", author = the character that answers, and
--           answer  yes | no
--           ends    the end of the rally when answered (retention when the rally itself is not held)
-- The set is short-lived like the group finder's (SPEC-13 GRP-03): never in a summary, never pushed or asked for, never
-- in a backup or an export; a local change goes out on GUILD after the 5-second batch, and only first hand.
-- Expiry  every client decides by itself (Rallies:Status): past `ends` it is "expired", and GRACE seconds later the
--           rally and its answers are dropped. No message is needed. A closed one goes GRACE seconds after it closed.
-- Limits  held by the caller's client, and again by every receiver: only the newest open rally of a caller counts
--           ("replaced"), and a fifth one within an hour does not ("limit").
-- RASK    (GUILD, NORMAL) h = 4-byte fingerprints of the rallies and answers the asker holds, at most ASK_MAX; a =
--           true also asks for the answers. Each client answers the asker with a WHISPER REC of what is not in `h`: its
--           own open rally and, when `a`, its own answers to open rallies. Two kinds of question, each sent at most once
--           per ASK_EVERY and handled once per sender per ASK_HANDLE: ASK_AFTER_HELLO seconds after the first HELLO of a
--           login, while the notice is on, for the rallies only (so only the callers answer); when the Rallies page
--           opens, with the answers. A message of its own, not the group finder's GASK: a v0.9.0 client would answer that
--           one with its group listings.
--
-- Also registered here: the notice `rally.called` (chat line by default) and the Action Center provider `rally` (one row
-- per open rally), both shown only while the switch `actions` is on. The view is UI/Rallies.lua, a page of Events.
-- Switch: Features.On("season"). Off: the set takes and sends nothing, RASK is ignored, no event is registered. Demo mode
-- sends nothing. Boss encounters: Net/Transport.lua holds the messages (SPEC-14 §10).
-- Bus: RALLY_CHANGED(id) a rally, or an answer to it, changed (nil: several).
local ADDON_NAME, ns = ...
ns = ns or {}
local Rallies = {}
ns.Rallies, ns.modules = Rallies, ns.modules or {}
ns.modules.Rallies = Rallies

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, random, max = math.floor, math.random, math.max
local concat, sort = table.concat, table.sort

Rallies.KINDS = { "pvp", "world" }
Rallies.ANSWERS = { "yes", "no" }
Rallies.MAX_TEXT = 60
Rallies.MAX_AHEAD = 7200                          -- a rally starts within 2 hours of the call (Q24)
Rallies.MIN_DURATION, Rallies.MAX_DURATION = 900, 7200   -- 15 minutes, 2 hours
Rallies.AHEAD, Rallies.DURATION = 900, 1800       -- preselected: in 15 minutes, for 30 minutes
Rallies.PER_HOUR = 4
Rallies.GRACE = 600           -- seconds an ended or closed rally is still shown and kept
Rallies.SKEW = 300            -- how far ahead of this client's server time `created` may be
Rallies.MAX_REV = 100
Rallies.MAX_ANSWER_REV = 20
Rallies.REWRITE_GAP = 10      -- seconds between two changes of the own rally
Rallies.ASK_EVERY = 600       -- one RASK of each kind sent per this many seconds
Rallies.ASK_HANDLE = 300      -- one RASK of each kind handled per sender per this many seconds
Rallies.ASK_MAX = 60          -- fingerprints in a RASK
Rallies.ANSWER_DELAY = { 0.5, 5 }
Rallies.ASK_AFTER_HELLO = { 30, 60 }
Rallies.TICK = 30
Rallies.AUTO = true           -- the question after a login goes by itself (tests switch it off)

local KIND, ANSWER = { pvp = true, world = true }, { yes = true, no = true }
local RALLY_FIELDS = { id = true, author = true, rev = true, time = true, kind = true, text = true, created = true,
	start = true, ends = true, closed = true }
local ANSWER_FIELDS = { id = true, author = true, rev = true, time = true, answer = true, ends = true }

if ns.Codec then ns.Codec:RegisterType("RASK", {}) end

local function compat() return ns.Compat end
local function store() return ns.Store end
local function serverTime() return compat().ServerTime() end
local function ownGUID() return compat().Player.GUID() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function between(r) return r[1] + (r[2] - r[1]) * random() end
local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end
local function lower(s) return type(s) == "string" and s:lower() or "?" end

function Rallies.Enabled() return ns.Features ~= nil and ns.Features.On("season") end

local function demo() return ns.Demo ~= nil and ns.Demo:IsActive() end

---------------------------------------------------------------------------------------------------------------------
-- The rules the Store applies (Net/Store.lua)
---------------------------------------------------------------------------------------------------------------------
-- "rally", the id of the rally itself; "answer", the id of its rally; or nil.
function Rallies.KindOf(rec)
	local id = type(rec) == "table" and rec.id
	if type(id) ~= "string" then return nil end
	if id:match("^[^:]+:%d+$") then return "rally", id end
	local rally = id:match("^([^:]+:%d+):[^:]+$")
	if rally then return "answer", rally end
	return nil
end

local function only(rec, fields)
	for k in pairs(rec) do
		if not fields[k] then return false end
	end
	return true
end

-- The owner rule of the set `rally`: the id carries the author's GUID, every field as above, and no other field.
function Rallies.ValidRecord(rec)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.author) ~= "string" or type(rec.rev) ~= "number" then
		return false
	end
	local kind = Rallies.KindOf(rec)
	local latest = serverTime() + Rallies.SKEW
	if kind == "rally" then
		local caller, n = rec.id:match("^([^:]+):(%d+)$")
		if caller ~= rec.author or #n > 9 or rec.rev > Rallies.MAX_REV or not only(rec, RALLY_FIELDS) then return false end
		if not KIND[rec.kind] or not (ns.Groups and ns.Groups.ValidText(rec.text, Rallies.MAX_TEXT, 1)) then return false end
		if not int(rec.created, 0, latest) then return false end
		if not int(rec.start, rec.created, rec.created + Rallies.MAX_AHEAD) then return false end
		if not int(rec.ends, rec.start + Rallies.MIN_DURATION, rec.start + Rallies.MAX_DURATION) then return false end
		if type(rec.time) == "number" and rec.time < rec.created then return false end
		return rec.closed == nil or rec.closed == true
	elseif kind == "answer" then
		local who = rec.id:match("^[^:]+:%d+:([^:]+)$")
		if who ~= rec.author or rec.rev > Rallies.MAX_ANSWER_REV or not only(rec, ANSWER_FIELDS) then return false end
		return ANSWER[rec.answer] == true and int(rec.ends, 0, latest + Rallies.MAX_AHEAD + Rallies.MAX_DURATION)
	end
	return false
end

-- Retention: GRACE seconds after the end, or after the write that closed it; an answer goes with its rally, or by the
-- end it carries when the rally is not held.
function Rallies.Expired(rec, t)
	if type(rec) ~= "table" then return true end
	local kind, id = Rallies.KindOf(rec)
	if kind == "answer" then
		local rally = store():Get("rally", id)
		if not rally then return (tonumber(rec.ends) or 0) + Rallies.GRACE < t end
		rec = rally
	end
	if rec.closed then return (rec.time or 0) + Rallies.GRACE < t end
	return (tonumber(rec.ends) or 0) + Rallies.GRACE < t
end

---------------------------------------------------------------------------------------------------------------------
-- State of this character (char.rally) and of the session
---------------------------------------------------------------------------------------------------------------------
local state
local function fresh()
	return {
		calls = {},         -- author -> { [rally id] = created }: the calls seen, for PER_HOUR
		writtenAt = nil,    -- server time of the last change of the own rally
		askHeard = {},      -- lower-case sender and kind -> when its last RASK was handled
		askedAt = {},       -- kind (with the answers or not) -> when this client last sent that RASK
		shown = {},         -- rally id -> the status last announced
		loginAsk = false,   -- a login happened: one RASK after the first HELLO while the notice is on
		stats = { called = 0, closed = 0, answered = 0, asks = 0, asksHeard = 0, asksAnswered = 0, ignored = 0, pruned = 0 },
	}
end
state = fresh()
Rallies.state = state

-- char.rally = { next, calls = { server times of this character's calls } }: the id counter and the hourly limit.
local function db()
	local C = ns.Config and ns.Config.db and ns.Config.db.char
	if type(C) ~= "table" then return nil end
	local r = C.rally
	if type(r) ~= "table" then r = {} C.rally = r end
	if type(r.next) ~= "number" then r.next = 0 end
	if type(r.calls) ~= "table" then r.calls = {} end
	return r
end
Rallies.DB = db

local function ready()
	return Rallies.Enabled() and ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil and ownGUID() ~= nil
end

local function send(dist, msg, opts)
	if not Rallies.Enabled() or demo() or not ns.Transport then return nil, "off" end
	return ns.Transport:Send(dist, msg, opts)
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function remember(rec)
	local calls = state.calls[rec.author]
	if not calls then calls = {} state.calls[rec.author] = calls end
	calls[rec.id] = tonumber(rec.created) or 0
end

local function number(id) return tonumber(id:match(":(%d+)$")) or 0 end

-- true when `a` was called after `b` by the same caller.
local function later(aCreated, aId, bCreated, bId)
	if aCreated ~= bCreated then return aCreated > bCreated end
	return number(aId) > number(bId)
end

-- "soon" (not started), "on", or why it is over: "expired", "closed", "replaced" (the caller has a newer one), "limit"
-- (a call beyond PER_HOUR in an hour). The same answer on every client that holds the same records.
function Rallies:Status(rec, t)
	if type(rec) ~= "table" then return "closed" end
	t = t or serverTime()
	if rec.closed then return "closed" end
	if t >= (tonumber(rec.ends) or 0) then return "expired" end
	local created = tonumber(rec.created) or 0
	for id, other in pairs(store():Records("rally")) do
		if id ~= rec.id and type(other) == "table" and other.author == rec.author and not other.closed
			and Rallies.KindOf(other) == "rally" and (tonumber(other.ends) or 0) > t
			and later(tonumber(other.created) or 0, id, created, rec.id) then
			return "replaced"
		end
	end
	local before = 0
	for id, at in pairs(state.calls[rec.author] or {}) do
		if id ~= rec.id and at > created - 3600 and later(created, rec.id, at, id) then before = before + 1 end
	end
	if before >= Rallies.PER_HOUR then return "limit" end
	return t < (tonumber(rec.start) or 0) and "soon" or "on"
end

function Rallies:IsOpen(rec, t)
	local s = self:Status(rec, t)
	return s == "soon" or s == "on"
end

function Rallies:Get(id)
	if not Rallies.Enabled() then return nil end
	local rec = store():Get("rally", id)
	return rec and Rallies.KindOf(rec) == "rally" and rec or nil
end

-- The rallies held, the next to start first: { rec, status }. Empty while the switch is off.
function Rallies:List()
	local out = {}
	if not Rallies.Enabled() then return out end
	local t = serverTime()
	for _, rec in pairs(store():Records("rally")) do
		if type(rec) == "table" and Rallies.KindOf(rec) == "rally" and not Rallies.Expired(rec, t) then
			local status = self:Status(rec, t)
			if status ~= "replaced" and status ~= "limit" then out[#out + 1] = { rec = rec, status = status } end
		end
	end
	sort(out, function(a, b)
		local sa, sb = tonumber(a.rec.start) or 0, tonumber(b.rec.start) or 0
		if sa ~= sb then return sa < sb end
		return tostring(a.rec.id) < tostring(b.rec.id)
	end)
	return out
end

-- The answers to rally `id`: { yes = { GUIDs }, no = { GUIDs } }, each sorted.
function Rallies:Answers(id)
	local out = { yes = {}, no = {} }
	if not Rallies.Enabled() or type(id) ~= "string" then return out end
	for _, rec in pairs(store():Records("rally")) do
		if type(rec) == "table" then
			local kind, rally = Rallies.KindOf(rec)
			if kind == "answer" and rally == id and out[rec.answer] then
				out[rec.answer][#out[rec.answer] + 1] = rec.author
			end
		end
	end
	sort(out.yes)
	sort(out.no)
	return out
end

-- This character's answer to rally `id`: "yes", "no" or nil.
function Rallies:Mine(id)
	local me = ownGUID()
	if not (Rallies.Enabled() and id and me) then return nil end
	local rec = store():Get("rally", id .. ":" .. me)
	return rec and rec.answer or nil
end

-- This character's open rally, or nil.
function Rallies:Own()
	if not ready() then return nil end
	local me = ownGUID()
	for _, e in ipairs(self:List()) do
		if e.rec.author == me and (e.status == "soon" or e.status == "on") then return e.rec end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The caller
---------------------------------------------------------------------------------------------------------------------
local function fieldsOf(rec)
	return { kind = rec.kind, text = rec.text, created = rec.created, start = rec.start, ends = rec.ends, closed = rec.closed }
end

local function write(id, fields)
	local rec, why = store():Put("rally", id, fields)
	if not rec then return nil, why end
	remember(rec)
	emit("RALLY_CHANGED", id)
	return rec
end

local function own(id)
	local rec = store():Get("rally", id)
	if not rec or rec.author ~= ownGUID() or Rallies.KindOf(rec) ~= "rally" then return nil end
	return rec
end

local function highestOwn(me)
	local highest = 0
	for id in pairs(store():Records("rally")) do
		local n = type(id) == "string" and id:sub(1, #me + 1) == me .. ":" and tonumber(id:sub(#me + 2))
		if n and n > highest then highest = n end
	end
	return highest
end

-- The calls of this character in the last hour (the older ones are forgotten).
local function recentCalls(r, t)
	local kept = {}
	for _, at in ipairs(r.calls) do
		if type(at) == "number" and at > t - 3600 then kept[#kept + 1] = at end
	end
	r.calls = kept
	return #kept
end

local function check(spec, keep)
	local out = {}
	out.kind = spec.kind or (keep and keep.kind)
	if not KIND[out.kind] then return nil, "kind" end
	out.text = keep and keep.text
	if spec.text ~= nil or not keep then out.text = ns.Groups.CleanText(spec.text, Rallies.MAX_TEXT) end
	if out.text == "" then return nil, "text" end
	return out
end

-- Calls a rally. spec = { kind, text, ahead (seconds from now to the start), duration (seconds) }. The caller's older
-- open rally closes. Returns the record, or false and a reason ("off", "kind", "text", "start", "duration", "limit", or
-- a Store reason).
function Rallies:Call(spec)
	if not ready() then return false, "off" end
	if type(spec) ~= "table" then return false, "kind" end
	local f, why = check(spec)
	if not f then return false, why end
	local ahead, duration = spec.ahead or Rallies.AHEAD, spec.duration or Rallies.DURATION
	if not int(ahead, 0, Rallies.MAX_AHEAD) then return false, "start" end
	if not int(duration, Rallies.MIN_DURATION, Rallies.MAX_DURATION) then return false, "duration" end
	local me, t = ownGUID(), serverTime()
	local r = db()
	if not r then return false, "off" end
	if recentCalls(r, t) >= Rallies.PER_HOUR then return false, "limit" end
	for id, rec in pairs(store():Records("rally")) do
		if type(rec) == "table" and rec.author == me and not rec.closed and Rallies.KindOf(rec) == "rally"
			and (tonumber(rec.ends) or 0) > t then
			self:Close(id)
		end
	end
	f.created, f.start, f.ends = t, t + ahead, t + ahead + duration
	local n = max(r.next, highestOwn(me)) + 1
	local rec, err = write(me .. ":" .. n, f)
	if not rec then return false, err end
	r.next = n
	r.calls[#r.calls + 1] = t
	state.writtenAt = t
	state.stats.called = state.stats.called + 1
	return rec
end

-- The caller changes its open rally: changes = { kind, text, ahead (from now), duration }, each one optional. The start
-- stays within 2 hours of the call. Returns the record, or false and a reason ("off", "missing", "status", "wait", ...).
function Rallies:Update(id, changes)
	if not ready() then return false, "off" end
	local rec = own(id)
	if not rec then return false, "missing" end
	if not self:IsOpen(rec) then return false, "status" end
	if rec.rev >= Rallies.MAX_REV - 1 then return false, "rev" end   -- the last revision is kept for closing
	local t = serverTime()
	if state.writtenAt and t - state.writtenAt < Rallies.REWRITE_GAP then return false, "wait" end
	changes = type(changes) == "table" and changes or {}
	local f, why = check(changes, rec)
	if not f then return false, why end
	f.created, f.start = rec.created, rec.start
	local duration = changes.duration or (rec.ends - rec.start)
	if changes.ahead ~= nil then
		if not int(changes.ahead, 0, Rallies.MAX_AHEAD) then return false, "start" end
		f.start = t + changes.ahead
		if f.start > rec.created + Rallies.MAX_AHEAD then return false, "start" end
	end
	if not int(duration, Rallies.MIN_DURATION, Rallies.MAX_DURATION) then return false, "duration" end
	f.ends = f.start + duration
	if f.ends <= t then return false, "duration" end
	local written, err = write(id, f)
	if not written then return false, err end
	state.writtenAt = t
	return written
end

-- The caller closes its rally.
function Rallies:Close(id)
	if not ready() then return false, "off" end
	local rec = own(id)
	if not rec then return false, "missing" end
	if rec.closed or serverTime() >= rec.ends then return false, "status" end
	local f = fieldsOf(rec)
	f.closed = true
	local written, err = write(id, f)
	if not written then return false, err end
	state.stats.closed = state.stats.closed + 1
	return written
end

---------------------------------------------------------------------------------------------------------------------
-- Answering
---------------------------------------------------------------------------------------------------------------------
-- "Coming" (yes) or "not coming" (no) to an open rally of somebody else. Returns true, or false and a reason ("off",
-- "answer", "missing", "status", "own", "rev", or a Store reason).
function Rallies:Answer(id, answer)
	if not ready() then return false, "off" end
	if not ANSWER[answer] then return false, "answer" end
	local rec = self:Get(id)
	if not rec then return false, "missing" end
	if not self:IsOpen(rec) then return false, "status" end
	local me = ownGUID()
	if rec.author == me then return false, "own" end
	local key = id .. ":" .. me
	local held = store():Get("rally", key)
	if held and held.answer == answer then return true end
	if held and held.rev >= Rallies.MAX_ANSWER_REV then return false, "rev" end
	local written, why = store():Put("rally", key, { answer = answer, ends = rec.ends })
	if not written then return false, why end
	state.stats.answered = state.stats.answered + 1
	emit("RALLY_CHANGED", id)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- RASK: who comes later
---------------------------------------------------------------------------------------------------------------------
-- The records of the open rallies held, with their answers: { rec }.
local function openRecords()
	local records, open, t = store():Records("rally"), {}, serverTime()
	local out = {}
	for id, rec in pairs(records) do
		if type(rec) == "table" and Rallies.KindOf(rec) == "rally" and Rallies:IsOpen(rec, t) then
			open[id] = true
			out[#out + 1] = rec
		end
	end
	for _, rec in pairs(records) do
		if type(rec) == "table" then
			local kind, rally = Rallies.KindOf(rec)
			if kind == "answer" and open[rally] then out[#out + 1] = rec end
		end
	end
	return out
end

-- Sends a RASK with the fingerprints of what is held; `answers` asks for the answers too. Returns true, or false and a
-- reason ("off", "recent").
function Rallies:Ask(answers)
	if not ready() or demo() then return false, "off" end
	answers = answers and true or false
	local t, last = compat().Now(), state.askedAt[answers]
	if last and t - last < Rallies.ASK_EVERY then return false, "recent" end
	local prints = {}
	for _, rec in ipairs(openRecords()) do
		prints[#prints + 1] = ns.Groups.Fingerprint(rec)
		if #prints >= Rallies.ASK_MAX then break end
	end
	local ok, why = send("GUILD", { t = "RASK", h = concat(prints), a = answers or nil })
	if not ok then return false, why end
	state.askedAt[answers] = t
	state.stats.asks = state.stats.asks + 1
	return true
end

function Rallies:OnAsk(msg, sender, dist)
	if dist ~= "GUILD" or not ready() then return end
	if ns.Transport and ns.Transport.IsSelf(sender) then return end
	if not store():Member(sender) then return end
	local answers = msg.a == true
	local key, t = lower(sender) .. (answers and "|a" or ""), compat().Now()
	local heard = state.askHeard[key]
	if heard and t - heard < Rallies.ASK_HANDLE then
		state.stats.ignored = state.stats.ignored + 1
		return
	end
	state.askHeard[key] = t
	state.stats.asksHeard = state.stats.asksHeard + 1
	local have = {}
	local h = type(msg.h) == "string" and msg.h or ""
	if #h % 4 == 0 and #h <= 4 * Rallies.ASK_MAX then
		for at = 1, #h, 4 do have[h:sub(at, at + 3)] = true end
	end
	local me = ownGUID()
	local function wanted()
		local out = {}
		for _, rec in ipairs(openRecords()) do
			if rec.author == me and (answers or Rallies.KindOf(rec) == "rally") and not have[ns.Groups.Fingerprint(rec)] then
				out[#out + 1] = rec
			end
		end
		sort(out, function(a, b) return a.id < b.id end)
		return out
	end
	if #wanted() == 0 then return end
	compat().NewTimer(between(Rallies.ANSWER_DELAY), function()
		if not ready() then return end
		local records = wanted()
		if #records == 0 then return end
		if send("WHISPER", { t = "REC", s = "rally", r = records }, { target = sender, key = "RALLY|" .. key }) then
			state.stats.asksAnswered = state.stats.asksAnswered + 1
		end
	end)
end

-- The first HELLO of a login: one RASK ASK_AFTER_HELLO seconds later, while the notice of a new rally is on.
function Rallies:OnHello()
	if not Rallies.AUTO or not state.loginAsk or not ready() then return end
	state.loginAsk = false
	local off = ns.Config and ns.Config:Get("account.settings.notify.rally.off")
	if type(off) == "table" and off.called == true then return end
	compat().NewTimer(between(Rallies.ASK_AFTER_HELLO), function() Rallies:Ask(false) end)
end

---------------------------------------------------------------------------------------------------------------------
-- The notice and the Action Center (SPEC-13 §3.2)
---------------------------------------------------------------------------------------------------------------------
local function name(guid) return ns.Groups and ns.Groups.ShortName(guid) or "?" end

-- The time of day of a server time, as the client's clock writes it.
function Rallies.Clock(t) return date("%H:%M", t) end

local function openView(id)
	if ns.RalliesView then ns.RalliesView:Open(id) end
end

-- One notice per rally of another account, when it first arrives open.
function Rallies:NoticeCalled(id)
	local N = ns.Notify
	if not (id and ready() and N and N.Enabled()) then return end
	local rec = self:Get(id)
	if not rec or not self:IsOpen(rec) or store():SameAccount(ownGUID(), rec.author) then return end
	local book = N:Seen("rally")
	if not book or book[id] then return end
	book[id] = true
	N:Post("rally", "called", { key = "called#" .. id, text = "RALLY_NOTICE_" .. rec.kind:upper(),
		args = { name(rec.author), Rallies.Clock(rec.start), rec.text }, view = "events", page = "rallies",
		char = ownGUID(), still = function()
			local held = Rallies:Get(id)
			return held ~= nil and Rallies:IsOpen(held)
		end })
end

-- Forgets the rallies that are gone, so the book does not grow.
function Rallies:NoticeCheck()
	local N = ns.Notify
	local book = ready() and N and N.Enabled() and N:Seen("rally")
	if not book then return end
	local records = store():Records("rally")
	for id in pairs(book) do
		if not records[id] then book[id] = nil end
	end
end

-- The Action Center rows: one per open rally, urgency 2.
function Rallies:ActionRows()
	local rows = {}
	if not ready() then return rows end
	for _, e in ipairs(self:List()) do
		local rec = e.rec
		if e.status == "soon" or e.status == "on" then
			local who, mine = name(rec.author), self:Mine(rec.id)
			local answer = rec.author == ownGUID() and ns.L["RALLY_YOURS"]
				or ns.L["RALLY_MINE_" .. (mine and mine:upper() or "NONE")]
			rows[#rows + 1] = { key = number(rec.id) .. ":" .. rec.author:sub(1, 48), urgency = 2, time = rec.created,
				mark = rec.rev .. (mine or ""), who = who,
				title = ns.L["RALLY_ROW_" .. rec.kind:upper()]:format(rec.text),
				detail = ns.L["RALLY_ROW_DETAIL"]:format(who, Rallies.Clock(rec.start), answer),
				open = function() openView(rec.id) end }
		end
	end
	return rows
end

if ns.Notify then
	ns.Notify:Register("rally", { label = "ACT_PROVIDER_RALLY", order = 25, feature = "season",
		open = function(entry) openView(type(entry.key) == "string" and entry.key:match("^called#(.+)$") or nil) end,
		check = function() Rallies:NoticeCheck() end, kinds = {
			{ id = "called", level = "alert", off = "SET_NOTICE_RALLY_CALLED", group = "RALLY_NOTICE_MANY" },
		} })
end

if ns.Actions then
	ns.Actions:Register("rally", { label = "ACT_PROVIDER_RALLY", order = 6, feature = "season",
		events = { "RALLY_CHANGED", "ROSTER_UPDATED" }, items = function() return Rallies:ActionRows() end })
end

---------------------------------------------------------------------------------------------------------------------
-- Clean-up and changes
---------------------------------------------------------------------------------------------------------------------
-- Drops what retention expires and announces the rallies whose status changed (a start or an end changes it without any
-- message). Returns the number of records removed.
function Rallies:Tick()
	if not ready() then return 0 end
	local S, t = store(), serverTime()
	local records = S:Records("rally")
	-- the answers first: theirs depends on the rally still being there
	local gone = {}
	for id, rec in pairs(records) do
		if Rallies.Expired(rec, t) then gone[#gone + 1] = id end
	end
	for _, id in ipairs(gone) do
		records[id] = nil
		if state.shown[id] ~= nil then
			state.shown[id] = nil
			emit("RALLY_CHANGED", id)
		end
	end
	state.stats.pruned = state.stats.pruned + #gone
	for author, calls in pairs(state.calls) do
		for id, at in pairs(calls) do
			if at < t - 4 * 3600 then calls[id] = nil end
		end
		if not next(calls) then state.calls[author] = nil end
	end
	for id, rec in pairs(records) do
		if Rallies.KindOf(rec) == "rally" then
			local status = self:Status(rec, t)
			if state.shown[id] ~= status then
				local before = state.shown[id]
				state.shown[id] = status
				if before ~= nil then emit("RALLY_CHANGED", id) end
			end
		end
	end
	return #gone
end

function Rallies:OnStoreChanged(set, id, origin)
	if set ~= "rally" or not Rallies.Enabled() or not id then return end
	local rec = store():Get("rally", id)
	if not rec then return end
	local kind, rally = Rallies.KindOf(rec)
	if kind == "rally" then
		remember(rec)
		state.shown[id] = self:Status(rec)
	end
	if origin == "remote" then
		emit("RALLY_CHANGED", rally)
		if kind == "rally" then self:NoticeCalled(id) end
	end
end

function Rallies:OnGuildChanged(key)
	local loginAsk, stats = state.loginAsk, state.stats
	state = fresh()
	state.loginAsk, state.stats = loginAsk, stats
	Rallies.state = state
	if key and Rallies.Enabled() then
		for _, rec in pairs(store():Records("rally")) do
			if Rallies.KindOf(rec) == "rally" then remember(rec) end
		end
		emit("RALLY_CHANGED", nil)
	end
end

function Rallies:Start()
	if self.ticker or not compat().NewTicker then return end
	self.ticker = compat().NewTicker(Rallies.TICK, function() Rallies:Tick() end)
	self:Tick()
end

function Rallies:DebugLines()
	local s = state.stats
	local n = #self:List()
	return { ("Rallies: %d held; called %d, closed %d, answered %d; RASK sent %d, heard %d, answered %d; ignored %d, pruned %d"):format(
		n, s.called, s.closed, s.answered, s.asks, s.asksHeard, s.asksAnswered, s.ignored, s.pruned) }
end

if ns.addon then
	ns.addon.Rallies = Rallies
	if ns.Bus then
		ns.Bus:On("NET_MESSAGE", function(msg, sender, dist)
			if type(msg) == "table" and msg.t == "RASK" and Rallies.Enabled() then Rallies:OnAsk(msg, sender, dist) end
		end)
		ns.Bus:On("STORE_CHANGED", function(set, id, origin) Rallies:OnStoreChanged(set, id, origin) end)
		ns.Bus:On("GUILD_CHANGED", function(key) Rallies:OnGuildChanged(key) end)
		ns.Bus:On("SYNC_HELLO", function(sent) if sent then Rallies:OnHello() end end)
	end
	LibStub("AceEvent-3.0"):Embed(Rallies)
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Rallies.Enabled() then return end
			Rallies:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin) if isLogin then state.loginAsk = true end end)
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Rallies", function() return Rallies:DebugLines() end) end
			Rallies:Start()
		end)
	end
end

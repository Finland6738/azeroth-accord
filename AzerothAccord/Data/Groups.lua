-- Groups: the guild group finder, its listings and applications (SPEC-13 §6, ADR 0024, M9.6). Lua 5.1.
--
-- Like the game's premade groups panel, but for the guild only. Any member with the addon may post (SPEC-10 Q18); a
-- character has one open listing at a time; only its leader changes or closes it.
--
-- Listing  a record of the data set `groups` (Net/Store.lua): id "<leader GUID>:<n>", author = the leader, and
--            kind     dungeon | raid | quest | elite | pvp | farm | prof | help | other
--            act      dungeon and raid: the mapID of the instance (Data/GroupActivities.lua); the others: a text of 1-40
--                     characters (a quest, a zone, a battleground...); help: the name of the zone only
--            min, max levels, 1 .. the game's highest level, min <= max
--            size     2-40 (dungeon and raid: at most the table's size for that instance when the leader posts)
--            need     { t, h, d } tanks, healers and damage still wanted; their sum <= size - have
--            have     players already in the group, the leader included: 1 .. size
--            note     0-80 characters; meet: 0-40 characters, the meeting point in words, never a position
--            created  server time of the post; ends: the end of the listing, created + 30 minutes .. created + 4 hours
--            status   open | full | closed; why (closed): leader | logout | replaced
--          Texts carry no "|" (the game's escape sequences), no control characters and no spaces at either end.
--          The set is short-lived (GRP-03): never in a summary, never pushed or asked for, never in a backup or an export;
--          a local change goes out on GUILD after the 5-second batch, and only first hand (GRP-02: an officer cannot
--          relay it). Who comes later asks with GASK (below).
-- Open     every client decides by itself, with the same data (GRP-04, Groups:Status): status open, not past `ends`, the
--          leader online in the last read of the roster, someone still needed and room left, and the leader's newest open
--          listing. Otherwise it shows closed for GRACE seconds (full, expired, offline, closed, replaced), then goes.
--          The leader's client also writes the status: full (nobody needed any more, or the game's group reached `size`),
--          closed/logout at the next login (never after a /reload), closed/replaced when it posts another, closed/leader.
-- GAPP     (WHISPER only, ALERT) g = listing id, k = apply | cancel (candidate -> leader; apply with r = role t|h|d,
--          c = comment, l = level) or accept | decline | full (leader -> candidate). GRP-05: an application goes only to the
--          leader's character, never on GUILD. GRP-06: the leader takes one only from a roster member of another account,
--          for its own open listing, at most APPLY_RATE per sender and MAX_APPLICANTS waiting per listing (beyond: `full`).
--          The waiting ones are saved per character (char.groups.apps), never in the Store, never synced. A candidate
--          takes an answer only from the listing's author character and only for a listing it applied to.
-- Invite   GRP-07: Groups:Accept runs in the leader's click: Compat.Group.CanInvite, room in the game's group, never
--          ConvertToRaid, then Compat.Group.Invite (C_PartyInfo.InviteUnit) [verify on Forever, also in an instance during
--          the chat lockdown]; need and have are rewritten (at most once per REWRITE_GAP seconds, merged).
-- GASK     (GUILD, NORMAL) h = 4-byte fingerprints (Hash.Fast(id .. ":" .. rev)) of the open listings the asker holds,
--          at most ASK_MAX. Each client with its own open listing that is not in `h` sends it to the asker as a WHISPER REC
--          after ANSWER_DELAY seconds. One GASK sent per ASK_EVERY; one handled per sender per ASK_HANDLE; one answer per
--          asker per ASK_ANSWER. Asked when the Groups view opens (M9.7), or ASK_AFTER_HELLO seconds after the first HELLO
--          of a login when the notice `groups.match` is on. Nothing is sent at login.
--
-- Switch: Features.On("groups") (Core/Features.lua), off until M9.10. Off: the set takes and sends nothing (Store), GAPP and
-- GASK are ignored, nothing is sent, no event is registered. Demo mode sends nothing.
-- Bus: GROUPS_CHANGED(id) a listing changed (nil: several); APPLICANTS_CHANGED(id) the applications of a listing changed on
-- the leader's or the candidate's client.
local ADDON_NAME, ns = ...
ns = ns or {}
local Groups = {}
ns.Groups, ns.modules = Groups, ns.modules or {}
ns.modules.Groups = Groups

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, random, max, min = math.floor, math.random, math.max, math.min
local byte, char, concat, sort = string.byte, string.char, table.concat, table.sort

Groups.KINDS = { "dungeon", "raid", "quest", "elite", "pvp", "farm", "prof", "help", "other" }
Groups.ROLES = { "t", "h", "d" }
Groups.MAX_ACT, Groups.MAX_NOTE, Groups.MAX_MEET, Groups.MAX_COMMENT = 40, 80, 40, 60
Groups.MIN_SIZE, Groups.MAX_SIZE = 2, 40
Groups.MIN_DURATION, Groups.MAX_DURATION, Groups.DURATION = 1800, 14400, 7200   -- 30 minutes, 4 hours, 2 hours (Q18)
Groups.GRACE = 600            -- seconds a closed listing still shows, and is kept after `ends` or after it closed
Groups.MAX_REV = 100
Groups.REWRITE_GAP = 10       -- seconds between two writes of have/need by the leader's client (merged)
Groups.APPLY_RATE = { 10, 60 }   -- GAPP handled per sender per window of seconds
Groups.MAX_APPLICANTS = 40    -- waiting applications per listing
Groups.MAX_MINE = 3           -- waiting applications of one candidate
Groups.DECLINE_WAIT = 600     -- seconds before applying again to a listing that declined
Groups.ASK_EVERY = 600        -- one GASK sent per this many seconds
Groups.ASK_HANDLE = 300       -- one GASK handled per sender per this many seconds
Groups.ASK_ANSWER = 60        -- one answer per asker per this many seconds
Groups.ASK_MAX = 60           -- fingerprints in a GASK
Groups.ANSWER_DELAY = { 0.5, 3 }
Groups.ASK_AFTER_HELLO = { 60, 90 }
Groups.TICK = 60              -- seconds between two passes of the clean-up
Groups.KEPT = 3600            -- an answered application of the candidate is forgotten this long after its listing went

local KIND, ROLE = {}, { t = true, h = true, d = true }
for _, k in ipairs(Groups.KINDS) do KIND[k] = true end
local INSTANCE = { dungeon = true, raid = true }
local STATUS = { open = true, full = true, closed = true }
local WHY = { leader = true, logout = true, replaced = true }

if ns.Codec then
	ns.Codec:RegisterType("GAPP", { g = "string", k = "string" })
	ns.Codec:RegisterType("GASK", {})
end

local function compat() return ns.Compat end
local function store() return ns.Store end
local function serverTime() return compat().ServerTime() end
local function ownGUID() return compat().Player.GUID() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function between(r) return r[1] + (r[2] - r[1]) * random() end
local function int(v, lo, hi) return type(v) == "number" and v == floor(v) and v >= lo and v <= hi end
local function lower(s) return type(s) == "string" and s:lower() or "?" end

function Groups.Enabled() return ns.Features ~= nil and ns.Features.On("groups") end

local function demo() return ns.Demo ~= nil and ns.Demo:IsActive() end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
-- Drops an incomplete UTF-8 sequence at the end of a cut text.
local function utf8Tail(s)
	local i = #s
	while i > 0 and byte(s, i) >= 128 and byte(s, i) < 192 do i = i - 1 end
	if i == 0 then return s end
	local lead = byte(s, i)
	if lead < 192 then return s end
	local need = lead >= 240 and 4 or lead >= 224 and 3 or 2
	if #s - i + 1 < need then return s:sub(1, i - 1) end
	return s
end

-- A text of a form or a comment: no control characters and no "|", one space between words, trimmed, at most `limit`
-- bytes (never cut inside a character).
function Groups.CleanText(value, limit)
	if type(value) ~= "string" then return "" end
	value = value:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if #value > limit then value = utf8Tail(value:sub(1, limit)):gsub(" $", "") end
	return value
end

-- true for a text the owner rule accepts: a string of at most `limit` bytes (at least `least`) that CleanText leaves as is.
function Groups.ValidText(value, limit, least)
	if type(value) ~= "string" or #value > limit or #value < (least or 0) then return false end
	return not value:find("[%c|]") and not value:find("^%s") and not value:find("%s$")
end

---------------------------------------------------------------------------------------------------------------------
-- The rules the Store applies (Net/Store.lua)
---------------------------------------------------------------------------------------------------------------------
local function maxLevel() return compat() and compat().Player.MaxLevel() or 60 end

local function needSum(need) return (need.t or 0) + (need.h or 0) + (need.d or 0) end

-- The owner rule of the set `groups` (SPEC-13 §6.2): the id starts with the author's GUID, every field as above.
function Groups.ValidRecord(rec)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.author) ~= "string" then return false end
	local n = rec.id:sub(#rec.author + 1):match("^:(%d+)$")
	if rec.id:sub(1, #rec.author) ~= rec.author or not n or #n > 9 then return false end
	if type(rec.rev) ~= "number" or rec.rev > Groups.MAX_REV then return false end
	if not KIND[rec.kind] then return false end
	if INSTANCE[rec.kind] then
		if not int(rec.act, 1, ns.GroupActivities and ns.GroupActivities.MAX_MAP or 1000000) then return false end
	elseif not Groups.ValidText(rec.act, Groups.MAX_ACT, 1) then
		return false
	end
	local top = maxLevel()
	if not (int(rec.min, 1, top) and int(rec.max, 1, top) and rec.min <= rec.max) then return false end
	if not int(rec.size, Groups.MIN_SIZE, Groups.MAX_SIZE) or not int(rec.have, 1, rec.size) then return false end
	local need = rec.need
	if type(need) ~= "table" then return false end
	for k, v in pairs(need) do
		if not ROLE[k] or not int(v, 0, Groups.MAX_SIZE) then return false end
	end
	if needSum(need) > rec.size - rec.have then return false end
	if rec.note ~= nil and not Groups.ValidText(rec.note, Groups.MAX_NOTE) then return false end
	if rec.meet ~= nil and not Groups.ValidText(rec.meet, Groups.MAX_MEET) then return false end
	if not (int(rec.created, 0, 4294967295) and int(rec.ends, 0, 4294967295)) then return false end
	local length = rec.ends - rec.created
	if length < Groups.MIN_DURATION or length > Groups.MAX_DURATION then return false end
	if type(rec.time) == "number" and rec.time < rec.created then return false end
	if not STATUS[rec.status] then return false end
	if rec.status == "closed" then
		if not WHY[rec.why] then return false end
	elseif rec.why ~= nil then
		return false
	end
	return true
end

-- Retention: GRACE seconds after `ends`, or GRACE seconds after the write that closed it.
function Groups.Expired(rec, t)
	if type(rec) ~= "table" then return true end
	if rec.status ~= "open" then return (rec.time or 0) + Groups.GRACE < t end
	return (tonumber(rec.ends) or 0) + Groups.GRACE < t
end

---------------------------------------------------------------------------------------------------------------------
-- State of this character (char.groups): the counter of ids, the applications it holds as a leader and as a candidate
---------------------------------------------------------------------------------------------------------------------
local state
local function fresh()
	return {
		writes = {},        -- id -> server time of the last write of have/need
		pending = {},       -- id -> fields waiting for REWRITE_GAP
		timers = {},        -- id -> timer of a pending write
		applyRate = {},     -- lower-case sender -> { start, count }
		askHeard = {},      -- lower-case sender -> when its last GASK was handled
		answered = {},      -- lower-case asker -> when this client last answered it
		askedAt = nil,      -- when this client last sent a GASK
		shown = {},         -- id -> the status last announced with GROUPS_CHANGED
		loginClose = false, -- a login happened: own listings still open are closed (logout) once the guild is known
		loginAsk = false,   -- a login happened: one GASK after the first HELLO when `groups.match` is on
		stats = { posted = 0, closed = 0, applied = 0, appsHeard = 0, appsRefused = 0, answersHeard = 0, invited = 0,
			asks = 0, asksHeard = 0, asksAnswered = 0, ignored = 0, pruned = 0 },
	}
end
state = fresh()
Groups.state = state

-- char.groups = { guild, next, apps = { [id] = { [name] = { r, c, l, at, guid } } }, mine = { [id] = { r, at, state,
-- author, leader, done } } }, for the current guild (another guild empties apps and mine; `next` stays).
local function db()
	local C = ns.Config and ns.Config.db and ns.Config.db.char
	if type(C) ~= "table" then return nil end
	local g = C.groups
	if type(g) ~= "table" then g = {} C.groups = g end
	if type(g.next) ~= "number" then g.next = 0 end
	if type(g.apps) ~= "table" then g.apps = {} end
	if type(g.mine) ~= "table" then g.mine = {} end
	local key = ns.GuildKey and ns.GuildKey:Current()
	if key and g.guild ~= key then
		g.guild, g.apps, g.mine = key, {}, {}
	end
	return g
end
Groups.DB = db

local function ready()
	return Groups.Enabled() and ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil and ownGUID() ~= nil
end

local function send(dist, msg, opts)
	if not Groups.Enabled() or demo() or not ns.Transport then return nil, "off" end
	return ns.Transport:Send(dist, msg, opts)
end

local function gapp(target, id, k, extra)
	local msg = { t = "GAPP", g = id, k = k }
	for key, v in pairs(extra or {}) do msg[key] = v end
	return send("WHISPER", msg, { target = target, key = "GAPP|" .. k .. "|" .. id .. "|" .. lower(target) })
end

---------------------------------------------------------------------------------------------------------------------
-- Open or closed (GRP-04)
---------------------------------------------------------------------------------------------------------------------
local function leaderOnline(author)
	if author == ownGUID() then return true end
	local member = store():MemberByGUID(author)
	return member ~= nil and member.online == true
end

-- true when `rec` is the newest open listing of its leader (by `created`, then by id).
local function newestOpen(rec, t)
	for id, other in pairs(store():Records("groups")) do
		if id ~= rec.id and type(other) == "table" and other.author == rec.author and other.status == "open"
			and (tonumber(other.ends) or 0) > t then
			local oc, rc = tonumber(other.created) or 0, tonumber(rec.created) or 0
			if oc > rc or (oc == rc and tostring(id) > tostring(rec.id)) then return false end
		end
	end
	return true
end

-- "open", or why it shows closed: "full", "expired", "offline" (the leader left the game or the guild), "replaced",
-- "closed". The same answer on every client that holds the same record and the same roster.
function Groups:Status(rec, t)
	if type(rec) ~= "table" then return "closed" end
	t = t or serverTime()
	if rec.status == "full" then return "full" end
	if rec.status == "closed" then
		if rec.why == "replaced" then return "replaced" end
		if rec.why == "logout" then return "offline" end
		return "closed"
	end
	if t >= (tonumber(rec.ends) or 0) then return "expired" end
	if type(rec.need) ~= "table" or needSum(rec.need) <= 0 or rec.have >= rec.size then return "full" end
	if not leaderOnline(rec.author) then return "offline" end
	if not newestOpen(rec, t) then return "replaced" end
	return "open"
end

function Groups:IsOpen(rec, t) return self:Status(rec, t) == "open" end

-- The listings held, newest first: { rec, status } (status as Groups:Status). Empty while the switch is off.
function Groups:List()
	local out = {}
	if not Groups.Enabled() then return out end
	local t = serverTime()
	for _, rec in pairs(store():Records("groups")) do
		if type(rec) == "table" and not Groups.Expired(rec, t) then
			out[#out + 1] = { rec = rec, status = self:Status(rec, t) }
		end
	end
	sort(out, function(a, b)
		local ca, cb = tonumber(a.rec.created) or 0, tonumber(b.rec.created) or 0
		if ca ~= cb then return ca > cb end
		return tostring(a.rec.id) < tostring(b.rec.id)
	end)
	return out
end

function Groups:Get(id)
	if not Groups.Enabled() then return nil end
	return store():Get("groups", id)
end

-- The fingerprint of a listing version: 4 bytes of Hash.Fast(id .. ":" .. rev).
function Groups.Fingerprint(rec)
	local h = ns.Hash.Fast(tostring(rec.id) .. ":" .. tostring(rec.rev)) % 4294967296
	local out = {}
	for i = 4, 1, -1 do
		out[i] = char(h % 256)
		h = floor(h / 256)
	end
	return concat(out)
end

---------------------------------------------------------------------------------------------------------------------
-- The leader
---------------------------------------------------------------------------------------------------------------------
local function own(id)
	local rec = store():Get("groups", id)
	if not rec or rec.author ~= ownGUID() then return nil end
	return rec
end

local function fieldsOf(rec)
	local f = store().Copy(rec)
	f.id, f.author, f.rev, f.time = nil, nil, nil, nil
	return f
end

local function cancelPending(id)
	local timer = state.timers[id]
	if timer and timer.Cancel then timer:Cancel() end
	state.timers[id], state.pending[id] = nil, nil
end

-- Writes the fields of listing `id` now. Returns the record, or nil and a reason.
local function write(id, fields)
	cancelPending(id)
	local rec, why = store():Put("groups", id, fields)
	if not rec then return nil, why end
	state.writes[id] = serverTime()
	emit("GROUPS_CHANGED", id)
	return rec
end

-- The fields as they will be written: the pending ones, else the record's.
local function current(id)
	if state.pending[id] then return state.pending[id] end
	local rec = own(id)
	return rec and fieldsOf(rec) or nil
end

-- A write of have/need/texts: at most one per REWRITE_GAP seconds; a change inside the gap waits and merges.
local function rewrite(id, fields)
	local last = state.writes[id]
	local t = serverTime()
	if last and t - last < Groups.REWRITE_GAP then
		state.pending[id] = fields
		if not state.timers[id] then
			state.timers[id] = compat().NewTimer(Groups.REWRITE_GAP - (t - last) + 0.05, function()
				state.timers[id] = nil
				local waiting = state.pending[id]
				state.pending[id] = nil
				if waiting and own(id) then write(id, waiting) end
			end)
		end
		return true
	end
	return write(id, fields)
end

-- The applications of one own listing: { [name] = { r, c, l, at, guid } }.
local function appsOf(id, create)
	local g = db()
	if not g then return nil end
	local apps = g.apps[id]
	if not apps and create then apps = {} g.apps[id] = apps end
	return apps
end

-- Tells every waiting candidate of `id` that the listing closed, and forgets them.
local function closeApps(id, tell)
	local g = db()
	local apps = g and g.apps[id]
	if not apps then return end
	if tell then for name in pairs(apps) do gapp(name, id, "full") end end
	g.apps[id] = nil
	emit("APPLICANTS_CHANGED", id)
end

-- Closes own listing `id`: why = "leader" (the button), "replaced" or "logout". The waiting candidates hear `full`, except
-- at a logout (they see the leader offline by themselves).
function Groups:Close(id, why)
	if not ready() then return false, "off" end
	why = WHY[why] and why or "leader"
	local fields = current(id)
	if not fields then return false, "missing" end
	if fields.status ~= "open" then return false, "status" end
	fields.status, fields.why = "closed", why
	local rec, err = write(id, fields)
	if not rec then return false, err end
	state.stats.closed = state.stats.closed + 1
	closeApps(id, why ~= "logout")
	return rec
end

-- The listing is full (nobody needed any more, or the game's group reached its size): status full, the others hear it.
local function markFull(id, fields)
	fields.status, fields.why = "full", nil
	local rec = write(id, fields)
	closeApps(id, true)
	return rec
end

local function highestOwn(me)
	local highest = 0
	for id in pairs(store():Records("groups")) do
		if type(id) == "string" and id:sub(1, #me + 1) == me .. ":" then
			local n = tonumber(id:sub(#me + 2))
			if n and n > highest then highest = n end
		end
	end
	return highest
end

-- Posts a listing. spec = { kind, act, min, max, size, need = { t, h, d }, have, note, meet, duration }. The leader's
-- older open listing closes (replaced). Returns the record, or false and a reason ("off", "kind", "act", "level", "size",
-- "need", "have", "duration", or a Store reason).
function Groups:Post(spec)
	if not ready() then return false, "off" end
	if type(spec) ~= "table" or not KIND[spec.kind] then return false, "kind" end
	local me, t = ownGUID(), serverTime()
	local f = { kind = spec.kind, status = "open" }
	local row
	if INSTANCE[spec.kind] then
		row = ns.GroupActivities and ns.GroupActivities:Get(spec.act)
		if not row or row.kind ~= spec.kind then return false, "act" end
		f.act = spec.act
	else
		local act = Groups.CleanText(spec.act, Groups.MAX_ACT)
		if act == "" and spec.kind == "help" then
			local _, zone = compat().Call("GetRealZoneText")
			act = Groups.CleanText(zone, Groups.MAX_ACT)
		end
		if act == "" then return false, "act" end
		f.act = act
	end
	local top = maxLevel()
	f.min = spec.min or (row and row.min) or 1
	f.max = spec.max or (row and min(row.max, top)) or top
	if not (int(f.min, 1, top) and int(f.max, 1, top) and f.min <= f.max) then return false, "level" end
	f.size = spec.size or (row and row.size) or 5
	if not int(f.size, Groups.MIN_SIZE, row and row.size or Groups.MAX_SIZE) then return false, "size" end
	f.have = spec.have or max(1, compat().Group.Size())
	if not int(f.have, 1, f.size - 1) then return false, "have" end
	local need = type(spec.need) == "table" and spec.need or {}
	f.need = {}
	for _, r in ipairs(Groups.ROLES) do
		local v = need[r] or 0
		if not int(v, 0, Groups.MAX_SIZE) then return false, "need" end
		f.need[r] = v
	end
	local sum = needSum(f.need)
	if sum < 1 or sum > f.size - f.have then return false, "need" end
	local note, meet = Groups.CleanText(spec.note, Groups.MAX_NOTE), Groups.CleanText(spec.meet, Groups.MAX_MEET)
	f.note = note ~= "" and note or nil
	f.meet = meet ~= "" and meet or nil
	local duration = spec.duration or Groups.DURATION
	if not int(duration, Groups.MIN_DURATION, Groups.MAX_DURATION) then return false, "duration" end
	f.created, f.ends = t, t + duration
	-- one open listing per character: the older one closes first
	for id, rec in pairs(store():Records("groups")) do
		if type(rec) == "table" and rec.author == me and rec.status == "open" and not Groups.Expired(rec, t) then
			self:Close(id, "replaced")
		end
	end
	local g = db()
	local n = max(g and g.next or 0, highestOwn(me)) + 1
	local rec, why = write(me .. ":" .. n, f)
	if not rec then return false, why end
	if g then g.next = n end
	state.stats.posted = state.stats.posted + 1
	return rec
end

-- The leader changes its open listing: need, have, min, max, note, meet. Returns true (written, or merged into the write
-- that waits for REWRITE_GAP), or false and a reason.
function Groups:Update(id, changes)
	if not ready() then return false, "off" end
	local fields = current(id)
	if not fields then return false, "missing" end
	if fields.status ~= "open" then return false, "status" end
	local rec = own(id)
	if rec.rev >= Groups.MAX_REV - 1 then return false, "rev" end   -- the last revision is kept for closing
	changes = type(changes) == "table" and changes or {}
	if changes.need ~= nil then
		if type(changes.need) ~= "table" then return false, "need" end
		local need = {}
		for _, r in ipairs(Groups.ROLES) do need[r] = changes.need[r] or 0 end
		fields.need = need
	end
	for _, key in ipairs({ "have", "min", "max" }) do
		if changes[key] ~= nil then fields[key] = changes[key] end
	end
	if changes.note ~= nil then
		local v = Groups.CleanText(changes.note, Groups.MAX_NOTE)
		fields.note = v ~= "" and v or nil
	end
	if changes.meet ~= nil then
		local v = Groups.CleanText(changes.meet, Groups.MAX_MEET)
		fields.meet = v ~= "" and v or nil
	end
	local check = store().Copy(fields)
	check.id, check.author, check.rev, check.time = id, rec.author, rec.rev + 1, serverTime()
	if not Groups.ValidRecord(check) then return false, "invalid" end
	if needSum(fields.need) == 0 or fields.have >= fields.size then
		markFull(id, fields)
		return true
	end
	return rewrite(id, fields) and true or false
end

-- The applications waiting for own listing `id`: a list of { name, r, c, l, at, guid }, oldest first.
function Groups:Applicants(id)
	local out = {}
	if not Groups.Enabled() then return out end
	for name, a in pairs(appsOf(id) or {}) do
		out[#out + 1] = { name = name, r = a.r, c = a.c, l = a.l, at = a.at, guid = a.guid }
	end
	sort(out, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.name < b.name
	end)
	return out
end

-- GRP-07: the leader's click on Accept. Checks that the player may invite and that the group has room (never converts a
-- party to a raid: "raid"), invites through Compat, then rewrites need and have and answers the candidate. Returns true,
-- or false and a reason ("off", "missing", "status", "applicant", "leader", "full", "raid", "invite").
function Groups:Accept(id, name)
	if not ready() then return false, "off" end
	local fields = current(id)
	if not fields then return false, "missing" end
	if fields.status ~= "open" or self:Status(own(id)) ~= "open" then return false, "status" end
	local apps = appsOf(id)
	local app = apps and apps[name]
	if not app then return false, "applicant" end
	local G = compat().Group
	if not G.CanInvite() then return false, "leader" end
	local size = G.Size()
	if size >= fields.size then return false, "full" end
	if size >= 5 and fields.size > 5 and not G.InRaid() then return false, "raid" end
	if not G.Invite(name) then return false, "invite" end
	state.stats.invited = state.stats.invited + 1
	apps[name] = nil
	gapp(name, id, "accept")
	if (fields.need[app.r] or 0) > 0 then fields.need[app.r] = fields.need[app.r] - 1 end
	fields.have = min(fields.have + 1, fields.size)
	if needSum(fields.need) == 0 or fields.have >= fields.size then
		markFull(id, fields)
	else
		rewrite(id, fields)
		emit("APPLICANTS_CHANGED", id)
	end
	return true
end

-- The leader declines an application: the candidate hears it, the application goes.
function Groups:Decline(id, name)
	if not ready() then return false, "off" end
	local apps = appsOf(id)
	if not (apps and apps[name]) then return false, "applicant" end
	apps[name] = nil
	gapp(name, id, "decline")
	emit("APPLICANTS_CHANGED", id)
	return true
end

-- The game's group changed: an own open listing whose group reached its size is full.
function Groups:OnGroupRoster()
	if not ready() then return end
	local size = compat().Group.Size()
	local me = ownGUID()
	for id, rec in pairs(store():Records("groups")) do
		if type(rec) == "table" and rec.author == me and rec.status == "open" and size >= rec.size then
			markFull(id, current(id) or fieldsOf(rec))
		end
	end
end

-- At a login (not a /reload), once the guild is known: own listings still open are closed (logout), so who comes later
-- reads them closed (§6.3).
function Groups:CloseOnLogin()
	if not state.loginClose or not ready() then return 0 end
	state.loginClose = false
	local me, t, n = ownGUID(), serverTime(), 0
	for id, rec in pairs(store():Records("groups")) do
		if type(rec) == "table" and rec.author == me and rec.status == "open" and (tonumber(rec.ends) or 0) > t then
			if self:Close(id, "logout") then n = n + 1 end
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- The candidate
---------------------------------------------------------------------------------------------------------------------
local function waitingMine(g, except)
	local n = 0
	for id, m in pairs(g.mine) do
		if id ~= except and m.state == "waiting" then n = n + 1 end
	end
	return n
end

-- GRP-05: applies to listing `id` with role r ("t", "h" or "d") and an optional comment. The application goes to the
-- leader's character only. Returns true, or false and a reason ("off", "missing", "status", "own", "offline", "level",
-- "role", "wait", "limit", or a Transport reason).
function Groups:Apply(id, role, comment)
	if not ready() then return false, "off" end
	local rec = store():Get("groups", id)
	if not rec then return false, "missing" end
	if self:Status(rec) ~= "open" then return false, "status" end
	local me = ownGUID()
	if store():SameAccount(me, rec.author) then return false, "own" end
	local leader = store():MemberByGUID(rec.author)
	if not (leader and leader.online and type(leader.name) == "string") then return false, "offline" end
	local level = compat().Player.Level()
	if not (level and level >= rec.min and level <= rec.max) then return false, "level" end
	if not ROLE[role] or (rec.need[role] or 0) <= 0 then return false, "role" end
	local g = db()
	if not g then return false, "off" end
	local before = g.mine[id]
	if before and before.state == "declined" and serverTime() - (before.at or 0) < Groups.DECLINE_WAIT then return false, "wait" end
	if waitingMine(g, id) >= Groups.MAX_MINE then return false, "limit" end
	local c = Groups.CleanText(comment, Groups.MAX_COMMENT)
	local ok, why = gapp(leader.name, id, "apply", { r = role, c = c ~= "" and c or nil, l = level })
	if not ok then return false, why end
	g.mine[id] = { r = role, at = serverTime(), state = "waiting", author = rec.author, leader = leader.name }
	state.stats.applied = state.stats.applied + 1
	emit("APPLICANTS_CHANGED", id)
	return true
end

-- The candidate withdraws its waiting application.
function Groups:Withdraw(id)
	if not ready() then return false, "off" end
	local g = db()
	local m = g and g.mine[id]
	if not (m and m.state == "waiting") then return false, "missing" end
	g.mine[id] = nil
	gapp(m.leader, id, "cancel")
	emit("APPLICANTS_CHANGED", id)
	return true
end

-- This character's application to listing `id`: { r, at, state = waiting | accepted | declined | closed }, or nil.
function Groups:Mine(id)
	if not Groups.Enabled() then return nil end
	local g = db()
	return g and g.mine[id] or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving GAPP
---------------------------------------------------------------------------------------------------------------------
local function withinApplyRate(sender)
	local key, t = lower(sender), compat().Now()
	local w = state.applyRate[key]
	if not w or t - w.start >= Groups.APPLY_RATE[2] then
		w = { start = t, count = 0 }
		state.applyRate[key] = w
	end
	w.count = w.count + 1
	return w.count <= Groups.APPLY_RATE[1]
end

-- GRP-06: an application or its withdrawal reaches the leader.
local function onApply(msg, sender, member)
	local me = ownGUID()
	if not withinApplyRate(sender) then
		state.stats.appsRefused = state.stats.appsRefused + 1
		return
	end
	if store():SameAccount(me, member.guid) then return end
	local rec = own(msg.g)
	if not rec then return end   -- not this character's listing: nothing to say
	local name = member.name
	if msg.k == "cancel" then
		local apps = appsOf(msg.g)
		if apps and apps[name] then
			apps[name] = nil
			emit("APPLICANTS_CHANGED", msg.g)
		end
		return
	end
	if not ROLE[msg.r] then return end
	if Groups:Status(rec) ~= "open" or (rec.need[msg.r] or 0) <= 0 then
		gapp(name, msg.g, "full")
		return
	end
	local apps = appsOf(msg.g, true)
	if not apps then return end
	if not apps[name] then
		local n = 0
		for _ in pairs(apps) do n = n + 1 end
		if n >= Groups.MAX_APPLICANTS then
			state.stats.appsRefused = state.stats.appsRefused + 1
			gapp(name, msg.g, "full")
			return
		end
	end
	local c = type(msg.c) == "string" and Groups.CleanText(msg.c, Groups.MAX_COMMENT) or nil
	apps[name] = { r = msg.r, c = c ~= "" and c or nil, l = int(msg.l, 1, maxLevel()) and msg.l or nil, at = serverTime(),
		guid = member.guid }
	state.stats.appsHeard = state.stats.appsHeard + 1
	emit("APPLICANTS_CHANGED", msg.g)
end

local ANSWER = { accept = "accepted", decline = "declined", full = "closed" }

-- An answer of the leader reaches the candidate: only from the listing's author character, only for an application.
local function onAnswer(msg, member)
	local g = db()
	local m = g and g.mine[msg.g]
	if not m or m.state ~= "waiting" then return end
	local rec = store():Get("groups", msg.g)
	local author = rec and rec.author or m.author
	if member.guid ~= author or author ~= m.author then return end
	m.state, m.at = ANSWER[msg.k], serverTime()
	state.stats.answersHeard = state.stats.answersHeard + 1
	emit("APPLICANTS_CHANGED", msg.g)
end

function Groups:OnApp(msg, sender, dist)
	if dist ~= "WHISPER" or not ready() then return end
	if type(msg.g) ~= "string" or #msg.g > 64 then return end
	local member = store():Member(sender)
	if not (member and type(member.guid) == "string") then
		state.stats.ignored = state.stats.ignored + 1
		return
	end
	if msg.k == "apply" or msg.k == "cancel" then onApply(msg, sender, member)
	elseif ANSWER[msg.k] then onAnswer(msg, member)
	else state.stats.ignored = state.stats.ignored + 1 end
end

---------------------------------------------------------------------------------------------------------------------
-- GASK: who comes later
---------------------------------------------------------------------------------------------------------------------
-- Sends a GASK with the fingerprints of the open listings held. Returns true, or false and a reason ("off", "recent").
function Groups:Ask()
	if not ready() or demo() then return false, "off" end
	local t = compat().Now()
	if state.askedAt and t - state.askedAt < Groups.ASK_EVERY then return false, "recent" end
	local prints = {}
	for _, e in ipairs(self:List()) do
		if e.status == "open" then
			prints[#prints + 1] = Groups.Fingerprint(e.rec)
			if #prints >= Groups.ASK_MAX then break end
		end
	end
	local ok, why = send("GUILD", { t = "GASK", h = concat(prints) })
	if not ok then return false, why end
	state.askedAt = t
	state.stats.asks = state.stats.asks + 1
	return true
end

function Groups:OnAsk(msg, sender, dist)
	if dist ~= "GUILD" or not ready() then return end
	if ns.Transport and ns.Transport.IsSelf(sender) then return end
	local member = store():Member(sender)
	if not member then return end
	local key, t = lower(sender), compat().Now()
	local heard = state.askHeard[key]
	if heard and t - heard < Groups.ASK_HANDLE then
		state.stats.ignored = state.stats.ignored + 1
		return
	end
	state.askHeard[key] = t
	state.stats.asksHeard = state.stats.asksHeard + 1
	local have = {}
	local h = type(msg.h) == "string" and msg.h or ""
	if #h % 4 == 0 and #h <= 4 * Groups.ASK_MAX then
		for at = 1, #h, 4 do have[h:sub(at, at + 3)] = true end
	end
	local me, wanted = ownGUID(), {}
	for id, rec in pairs(store():Records("groups")) do
		if type(rec) == "table" and rec.author == me and self:Status(rec) == "open" and not have[Groups.Fingerprint(rec)] then
			wanted[#wanted + 1] = id
		end
	end
	if #wanted == 0 then return end
	local last = state.answered[key]
	if last and t - last < Groups.ASK_ANSWER then return end
	state.answered[key] = t
	compat().NewTimer(between(Groups.ANSWER_DELAY), function()
		if not ready() then return end
		local records = {}
		for _, id in ipairs(wanted) do
			local rec = own(id)
			if rec and Groups:Status(rec) == "open" then records[#records + 1] = rec end
		end
		if #records == 0 then return end
		if send("WHISPER", { t = "REC", s = "groups", r = records }, { target = sender, key = "GROUPS|" .. key }) then
			state.stats.asksAnswered = state.stats.asksAnswered + 1
		end
	end)
end

-- The first HELLO of a login: one GASK ASK_AFTER_HELLO seconds later, only when the notice `groups.match` is on.
function Groups:OnHello()
	if not state.loginAsk or not ready() then return end
	state.loginAsk = false
	local acc = ns.Config and ns.Config.db and ns.Config.db.account
	local off = acc and acc.settings and acc.settings.notify and acc.settings.notify.groups and acc.settings.notify.groups.off
	if type(off) == "table" and off.match == true then return end
	compat().NewTimer(between(Groups.ASK_AFTER_HELLO), function() Groups:Ask() end)
end

---------------------------------------------------------------------------------------------------------------------
-- Clean-up and changes
---------------------------------------------------------------------------------------------------------------------
-- Drops what retention expires, forgets the applications of listings that are no longer open, and announces the
-- listings whose status changed (an expiry or a leader who went offline changes it without any message). Returns the
-- number of records removed.
function Groups:Tick()
	if not ready() then return 0 end
	local S, t = store(), serverTime()
	local records = S:Records("groups")
	local removed = 0
	for id, rec in pairs(records) do
		if Groups.Expired(rec, t) then
			records[id] = nil
			removed = removed + 1
			if state.shown[id] ~= nil then
				state.shown[id] = nil
				emit("GROUPS_CHANGED", id)
			end
		end
	end
	state.stats.pruned = state.stats.pruned + removed
	for id, rec in pairs(records) do
		local status = self:Status(rec, t)
		if state.shown[id] ~= status then
			local before = state.shown[id]
			state.shown[id] = status
			if before ~= nil then emit("GROUPS_CHANGED", id) end
		end
	end
	local g = db()
	if g then
		for id in pairs(g.apps) do
			local rec = records[id]
			if not rec or rec.author ~= ownGUID() or self:Status(rec, t) ~= "open" then
				g.apps[id] = nil
				emit("APPLICANTS_CHANGED", id)
			end
		end
		for id, m in pairs(g.mine) do
			local rec = records[id]
			if m.state == "waiting" and (not rec or self:Status(rec, t) ~= "open") then
				m.state, m.at = "closed", t
				emit("APPLICANTS_CHANGED", id)
			elseif m.state ~= "waiting" and not rec and t - (m.at or 0) > Groups.KEPT then
				g.mine[id] = nil
			end
		end
	end
	return removed
end

function Groups:OnStoreChanged(set, id, origin)
	if set ~= "groups" or not Groups.Enabled() then return end
	local rec = id and store():Get("groups", id)
	if rec then state.shown[id] = self:Status(rec) end
	if origin == "remote" then emit("GROUPS_CHANGED", id) end
	-- a candidate whose listing closed (or was replaced by a newer one of its leader) stops waiting at once
	local g = db()
	if not g then return end
	for mid, m in pairs(g.mine) do
		if m.state == "waiting" then
			local held = store():Get("groups", mid)
			if held and self:Status(held) ~= "open" then
				m.state, m.at = "closed", serverTime()
				emit("APPLICANTS_CHANGED", mid)
			end
		end
	end
end

function Groups:OnGuildChanged(key)
	for id in pairs(state.timers) do cancelPending(id) end
	local loginClose, loginAsk, stats = state.loginClose, state.loginAsk, state.stats
	state = fresh()
	state.loginClose, state.loginAsk, state.stats = loginClose, loginAsk, stats
	Groups.state = state
	if key and Groups.Enabled() then
		self:CloseOnLogin()
		emit("GROUPS_CHANGED", nil)
	end
end

function Groups:OnEnteringWorld(isLogin)
	if not isLogin then return end
	state.loginClose, state.loginAsk = true, true
	self:CloseOnLogin()
end

function Groups:Start()
	if self.ticker or not compat().NewTicker then return end
	self.ticker = compat().NewTicker(Groups.TICK, function() Groups:Tick() end)
	self:Tick()
end

function Groups:DebugLines()
	local s = state.stats
	local n, open = 0, 0
	for _, e in ipairs(self:List()) do
		n = n + 1
		if e.status == "open" then open = open + 1 end
	end
	return { ("Groups: %d listing(s), %d open; posted %d, closed %d, applied %d, applications heard %d (refused %d), answers %d, invited %d"):format(
			n, open, s.posted, s.closed, s.applied, s.appsHeard, s.appsRefused, s.answersHeard, s.invited),
		("  GASK sent %d, heard %d, answered %d; ignored %d, pruned %d"):format(s.asks, s.asksHeard, s.asksAnswered, s.ignored, s.pruned) }
end

if ns.addon then
	ns.addon.Groups = Groups
	if ns.Bus then
		ns.Bus:On("NET_MESSAGE", function(msg, sender, dist)
			if type(msg) ~= "table" or not Groups.Enabled() then return end
			if msg.t == "GAPP" then Groups:OnApp(msg, sender, dist)
			elseif msg.t == "GASK" then Groups:OnAsk(msg, sender, dist) end
		end)
		ns.Bus:On("STORE_CHANGED", function(set, id, origin) Groups:OnStoreChanged(set, id, origin) end)
		ns.Bus:On("GUILD_CHANGED", function(key) Groups:OnGuildChanged(key) end)
		ns.Bus:On("SYNC_HELLO", function(sent) if sent then Groups:OnHello() end end)
	end
	LibStub("AceEvent-3.0"):Embed(Groups)
	if ns.OnEnable then
		-- OnEnable runs at PLAYER_LOGIN, before the first PLAYER_ENTERING_WORLD
		ns.OnEnable(function()
			if not Groups.Enabled() then return end
			Groups:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin) Groups:OnEnteringWorld(isLogin) end)
			Groups:RegisterEvent("GROUP_ROSTER_UPDATE", function() Groups:OnGroupRoster() end)
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Groups", function() return Groups:DebugLines() end) end
			Groups:Start()
		end)
	end
end

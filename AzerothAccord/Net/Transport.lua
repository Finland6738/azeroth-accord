-- Transport: the queue between the codec and the wire (SPEC-02 §1, §5, ADR 0004). Lua 5.1.
-- Adapted from Azeroth Guild Finder (Net/Transport.lua), same owner, GPL-3.0 (ADR 0018): the queue, priorities, keys,
-- lockdown hold, throttle retries and the ChatThrottleLib wire come from there. Accord has no public channel, so the
-- channel gap, byte budget and listen-only mode are left out; new here are the per-distribution gap, the guild stamp
-- of every message, the queue saved at logout and restored at login, and the own-echo check of OFFICER.
--
--   Transport:Send(dist, msg, opts)   dist = GUILD | OFFICER | WHISPER, msg = { t = "REC", ... fields ... },
--                                     opts = { target, prio = ALERT|NORMAL|BULK, key, ttl, rateGroup, onSent, onFail }
--   Receive: AceComm (prefix AzAccord) -> Transport:OnReceive -> Codec:Decode -> Bus NET_MESSAGE(msg, sender, dist).
--
-- Rules (all numbers are fields of Transport and are read on every use):
--   * one message per GAP[dist] seconds on each distribution; ChatThrottleLib paces the bytes below that;
--   * RATE[type] = { count, seconds }: at most that many messages of the type (HELLO: one per five minutes, NET-04);
--     messages sent with the same opts.rateGroup count once;
--   * NET-05: nothing is handed to the client during a chat lockdown or an addon restriction: the messages wait, the
--     latest one per `key` wins, BULK ones older than BULK_TTL are dropped; a lockdown refusal of the client is a wait;
--   * SPEC-14 §10: during a boss encounter only ALERT messages go, the others wait (switch "season", M10.5);
--   * a throttle result retries after RETRY_DELAY seconds, at most MAX_RETRIES times;
--   * every message carries the guild key it was written for: it waits while the guild is not known yet and is dropped
--     if the character is in another guild by then (a message of one guild never reaches another);
--   * at logout the waiting messages are saved in AzerothAccordCharDB.outbox and queued again at the next login
--     (without their callbacks), so nothing is lost while the game is closed (SPEC-02 §5);
--   * receiving (SPEC-11 §6.3): a sender that makes this client decode more than FLOOD[1] bytes in FLOOD[2] seconds is in
--     quarantine for QUARANTINE seconds: every message of it is dropped before decoding. Net/Sync.lua puts a sender in
--     quarantine too (too many refused records). The counters start again at every change of guild. Receiving never
--     touches the send queue.
--
-- Bus events: NET_MESSAGE(msg, sender, dist), PROTOCOL_NEWER() once per session, TRANSPORT_READ_ONLY(active).
-- Sender names go to the Bus and nowhere else: never printed, never stored here.
local ADDON_NAME, ns = ...
ns = ns or {}
local Transport = {}
ns.Transport, ns.modules = Transport, ns.modules or {}
ns.modules.Transport = Transport

local type, pairs, ipairs, pcall, tostring, tonumber = type, pairs, ipairs, pcall, tostring, tonumber
local sub, match = string.sub, string.match
local tinsert, tremove, sort = table.insert, table.remove, table.sort

---------------------------------------------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------------------------------------------
Transport.GAP = { GUILD = 1.0, OFFICER = 1.0, WHISPER = 0.25 }   -- seconds between two messages of a distribution
Transport.BULK_TTL = 600          -- a BULK message waiting longer than this is dropped
Transport.MAX_RETRIES = 3
Transport.RETRY_DELAY = 5         -- seconds after a throttle result
Transport.TICK = 0.2              -- pass interval of the queue while it holds messages
Transport.QUEUE_MAX = 200         -- pending messages (all distributions together)
Transport.LOCKDOWN_RECHECK = 1    -- seconds to wait after the client refused a message with "lockdown"
Transport.SAVED_MAX_AGE = 86400   -- a saved message older than this (server time) is not sent again
-- type -> { count, seconds }; DIGEST: at most one every 2 s, the others wait in the queue with their key (SPEC-11 §6.4)
-- GASK (the group finder's question of who comes later, SPEC-13 §6.7): at most one every 10 minutes
Transport.RATE = { HELLO = { 1, 300 }, BHELLO = { 1, 300 }, OHELLO = { 1, 300 }, DIGEST = { 1, 2 }, GASK = { 1, 600 } }
Transport.FLOOD = { 262144, 60 }  -- decoded bytes a sender may make this client decode per window of seconds
Transport.QUARANTINE = 600        -- seconds every message of a flooding sender is dropped before decoding

Transport.DISTS = { GUILD = true, OFFICER = true, WHISPER = true }
local RANK = { ALERT = 1, NORMAL = 2, BULK = 3 }

-- Default priority per message type; types the table does not list go NORMAL.
Transport.PRIORITY = {
	REQ = "ALERT", VOTE = "ALERT", SALT = "ALERT", LEDGER = "ALERT", GAPP = "ALERT",
	HELLO = "NORMAL", GASK = "NORMAL", BHELLO = "NORMAL", OHELLO = "NORMAL", REC = "NORMAL", DIGEST = "NORMAL",
}

-- Retail codes; the client's own Enum.SendAddonMessageResult wins when it exists (M0 S5 reads the real values).
local CODES = {
	Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4, NotInGroup = 5,
	TargetRequiresGuild = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9, AddOnMessageLockdown = 11,
	TargetOffline = 12,
}
local function codes()
	local enum = ns.Compat and ns.Compat.Resolve("Enum.SendAddonMessageResult")
	if type(enum) ~= "table" then return CODES end
	local merged = {}
	for name, code in pairs(CODES) do merged[name] = type(enum[name]) == "number" and enum[name] or code end
	return merged
end

local function codeName(code)
	for name, value in pairs(codes()) do
		if value == code then return name end
	end
	return tostring(code)
end

-- AceComm-3.0 multipart markers.
local MSG_MULTI_FIRST, MSG_MULTI_NEXT, MSG_MULTI_LAST, MSG_ESCAPE = "\001", "\002", "\003", "\004"
-- The client limit is 255 bytes of text; until M0 measures whether the prefix counts, the chunks stay below 255 minus
-- the prefix: a few bytes lost per chunk, no risk of InvalidMessage.
Transport.WIRE_LIMIT = 255
local function maxWire() return Transport.WIRE_LIMIT - #(Transport.PREFIX or "") end

---------------------------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------------------------
local function newStats()
	return {
		sent = 0, sentBytes = 0, failed = 0, throttled = 0, retried = 0, coalesced = 0, restored = 0, saved = 0,
		dropped = 0, droppedBy = {}, demoRefused = 0,     -- send side: reason -> count; refused in demo mode (M7.4)
		received = 0, rxDropped = 0, rxReasons = {}, rxNewer = 0, echoes = 0, quarantined = 0,
		encodeFailed = 0, callbackErrors = 0,
		sentBy = { GUILD = 0, OFFICER = 0, WHISPER = 0 }, bytesBy = { GUILD = 0, OFFICER = 0, WHISPER = 0 },
	}
end

local state
local function resetState()
	state = {
		queue = {}, seq = 0, keys = {},            -- pending items sorted by (rank, seq); key -> item
		inflight = 0, ticker = nil,
		lastAt = {}, typeLog = {}, holdUntil = {},
		held = nil, readOnly = false,                -- why nothing is handed to the client right now
		newerNotified = false,
		flood = {}, quarantine = {},                 -- lower-case sender -> { start, bytes } / time the quarantine ends
		stats = newStats(),
	}
	Transport.state = state
end
resetState()

local function compat() return ns.Compat end
local function now() return compat().Now() end
local function serverNow() return compat().ServerTime() end
local function guildKey() return ns.GuildKey and ns.GuildKey:Current() or nil end

local function callUser(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then
		state.stats.callbackErrors = state.stats.callbackErrors + 1
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) end
	end
end

local function emit(event, ...)
	if ns.Bus then ns.Bus:Emit(event, ...) end
end

---------------------------------------------------------------------------------------------------------------------
-- The wire: ChatThrottleLib with the AceComm framing
---------------------------------------------------------------------------------------------------------------------

-- The chunks of `text` in the AceComm-3.0 wire format (chunk size: see maxWire).
function Transport.Frame(text)
	local MAX_WIRE = maxWire()
	local len = #text
	local forceMultipart = false
	if match(text, "^[\001-\009]") then
		if len + 1 > MAX_WIRE then forceMultipart = true else text, len = MSG_ESCAPE .. text, len + 1 end
	end
	if not forceMultipart and len <= MAX_WIRE then return { text } end
	local size = MAX_WIRE - 1
	local chunks = { MSG_MULTI_FIRST .. sub(text, 1, size) }
	local pos = 1 + size
	while pos + size <= len do
		chunks[#chunks + 1] = MSG_MULTI_NEXT .. sub(text, pos, pos + size - 1)
		pos = pos + size
	end
	chunks[#chunks + 1] = MSG_MULTI_LAST .. sub(text, pos)
	return chunks
end

-- Default wire: wire(prio, text, dist, target, done). `done(result)` is called once: the result code of the client
-- (0 = accepted), the first refusal of a multipart message, or a string when the message never reached the client.
-- Messages are handed to ChatThrottleLib directly (not through AceComm's send) because AceComm's callback loses the
-- result code. The test suite and the network simulator replace this function.
function Transport.wire(prio, text, dist, target, done)
	local CTL = compat().Resolve("ChatThrottleLib")
	if type(CTL) ~= "table" or type(CTL.SendAddonMessage) ~= "function" then return done("nolib") end
	local chunks = Transport.Frame(text)
	local reported, count = false, 0
	local function onChunk(_, didSend, sendResult)
		if reported then return end
		count = count + 1
		local result = sendResult
		if type(result) ~= "number" then
			-- an old ChatThrottleLib reports nothing (taken as sent), a newer one a boolean or the code
			if didSend == false then result = CODES.GeneralError else result = CODES.Success end
		end
		if result ~= CODES.Success then
			reported = true
			return done(result)
		end
		if count >= #chunks then
			reported = true
			return done(CODES.Success)
		end
	end
	local queueName = Transport.PREFIX .. "\t" .. dist
	for _, chunk in ipairs(chunks) do
		local ok, err = pcall(CTL.SendAddonMessage, CTL, prio, Transport.PREFIX, chunk, dist, target, queueName, onChunk, #chunk)
		if not ok then
			if not reported then reported = true; done("error: " .. tostring(err):sub(1, 80)) end
			return
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Queue helpers
---------------------------------------------------------------------------------------------------------------------
local function before(a, b)
	if a.rank ~= b.rank then return a.rank < b.rank end
	return a.seq < b.seq
end

local function insertSorted(item)
	local queue = state.queue
	local at = #queue + 1
	for i = 1, #queue do
		if before(item, queue[i]) then at = i break end
	end
	tinsert(queue, at, item)
	if item.key then state.keys[item.key] = item end
end

local function removeFromQueue(item)
	local queue = state.queue
	for i = 1, #queue do
		if queue[i] == item then
			tremove(queue, i)
			if item.key and state.keys[item.key] == item then state.keys[item.key] = nil end
			return true
		end
	end
	return false
end

local function stopTicker()
	if state.ticker then state.ticker:Cancel() state.ticker = nil end
end

local pass   -- forward

local function ensureTicker()
	if state.ticker or #state.queue == 0 then return end
	state.ticker = compat().NewTicker(Transport.TICK, function() pass() end)
end

-- A message that leaves the transport without having been sent (or after a final refusal).
local function settle(item, reason)
	local s = state.stats
	if reason == "replaced" then
		s.coalesced = s.coalesced + 1
	elseif reason ~= "cancelled" then
		s.dropped = s.dropped + 1
		s.droppedBy[reason] = (s.droppedBy[reason] or 0) + 1
	end
	callUser(item.onFail, reason)
end

local function drop(item, reason)
	removeFromQueue(item)
	settle(item, reason)
end

local function prune(log, t, window)
	local keep = 1
	for i = 1, #log do
		local e = log[i]
		if not e.dead and t - e.time < window then log[keep] = e keep = keep + 1 end
	end
	for i = #log, keep, -1 do log[i] = nil end
end

-- The live entry of `group` in a rate log, if any.
local function groupEntry(log, group)
	if not group then return nil end
	for _, e in ipairs(log) do
		if e.group == group then return e end
	end
	return nil
end

local function rateFits(item, t)
	local rate = Transport.RATE[item.t]
	if not rate then return true end
	local log = state.typeLog[item.t]
	if not log then return true end
	prune(log, t, rate[2])
	if groupEntry(log, item.rateGroup) then return true end   -- the group already paid for its slot
	return #log < rate[1]
end

local function setGate(held, readOnly)
	state.held = held
	if state.readOnly ~= readOnly then
		state.readOnly = readOnly
		emit("TRANSPORT_READ_ONLY", readOnly)
	end
end

function Transport:IsReadOnly() return state.readOnly end

-- SPEC-14 §10 (M10.5): during a boss encounter (ENCOUNTER_START to ENCOUNTER_END, or while the client says one is in
-- progress) NORMAL and BULK messages wait in the queue; only ALERT ones go. Behind the switch "season" until M10.10.
function Transport.BossSilence()
	if not (ns.Features and ns.Features.On("season")) then return false end
	return compat().EncounterInProgress() and true or false
end
function Transport:Held() return state.held end

---------------------------------------------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------------------------------------------

-- Adds a ready item (from Send or from the saved outbox) to the queue, applying the key and the size bound.
local function enqueue(item)
	local old = item.key and state.keys[item.key]
	if old then drop(old, "replaced") end   -- only the latest message per key is kept
	local queue = state.queue
	if #queue >= Transport.QUEUE_MAX then
		-- the queue is sorted by priority then age: drop the oldest message of the lowest priority present
		local victim = queue[#queue]
		for i = #queue, 1, -1 do
			if queue[i].rank ~= victim.rank then break end
			victim = queue[i]
		end
		if victim.rank >= item.rank then
			drop(victim, "overflow")
		else
			settle(item, "overflow")
			return nil, "full"
		end
	end
	insertSorted(item)
	ensureTicker()
	return item
end

-- true when a message of the officer tools (opts.officerOnly, SPEC-12 OFF-05) may go to `dist` / `target` now: never on
-- GUILD, on OFFICER always, by WHISPER only to a character that is an officer in this client's roster.
local function officerAllowed(dist, target)
	if dist == "OFFICER" then return true end
	if dist ~= "WHISPER" then return false end
	local member = ns.Store and ns.Store:Member(target)
	return member ~= nil and member.officer == true
end

-- Queues `msg` ({ t = type, ...fields }). Returns the pending item (a handle for Cancel), or nil plus a reason:
-- "dist", "shape", "target", "prio", "encode: ...", "size", "full", "officerOnly" (opts.officerOnly and the destination is
-- not for officers).
function Transport:Send(dist, msg, opts)
	-- demo mode (SPEC-11 §3.1): nothing is sent, nothing is queued; the messages already waiting stay as they are
	if ns.Demo and ns.Demo:IsActive() then
		state.stats.demoRefused = state.stats.demoRefused + 1
		return nil, "demo"
	end
	opts = type(opts) == "table" and opts or {}
	if not Transport.DISTS[dist] then return nil, "dist" end
	if type(msg) ~= "table" then return nil, "shape" end
	if dist == "WHISPER" and (type(opts.target) ~= "string" or opts.target == "") then return nil, "target" end
	if opts.officerOnly == true and not officerAllowed(dist, opts.target) then
		state.stats.dropped = state.stats.dropped + 1
		state.stats.droppedBy.officerOnly = (state.stats.droppedBy.officerOnly or 0) + 1
		return nil, "officerOnly"
	end
	local prio = opts.prio or Transport.PRIORITY[msg.t] or "NORMAL"
	if not RANK[prio] then return nil, "prio" end
	local Codec = ns.Codec
	if not Codec then return nil, "encode: nocodec" end
	local payload, err = Codec:Encode(msg.t, msg)
	if not payload then
		state.stats.encodeFailed = state.stats.encodeFailed + 1
		return nil, "encode: " .. tostring(err)
	end
	if #payload > Codec.MAX_TEXT then return nil, "size" end

	state.seq = state.seq + 1
	return enqueue({
		seq = state.seq, dist = dist, target = dist == "WHISPER" and opts.target or nil, t = msg.t, payload = payload,
		size = #payload, prio = prio, rank = RANK[prio], key = type(opts.key) == "string" and opts.key or nil,
		bornAt = now(), bornServer = serverNow(), ttl = tonumber(opts.ttl) or (prio == "BULK" and Transport.BULK_TTL or nil),
		rateGroup = (type(opts.rateGroup) == "string" or type(opts.rateGroup) == "number") and opts.rateGroup or nil,
		attempts = 0, notBefore = 0, onSent = opts.onSent, onFail = opts.onFail, guild = guildKey(),
		officerOnly = opts.officerOnly == true or nil,
	})
end

-- Withdraws a message that is still waiting. Returns true when it was.
function Transport:Cancel(item)
	if type(item) ~= "table" or not removeFromQueue(item) then return false end
	settle(item, "cancelled")
	return true
end

function Transport:Pending(dist)
	if not dist then return #state.queue end
	local n = 0
	for _, item in ipairs(state.queue) do if item.dist == dist then n = n + 1 end end
	return n
end

local function expire(t)
	local doomed
	for _, item in ipairs(state.queue) do
		if item.ttl and t - item.bornAt >= item.ttl then
			doomed = doomed or {}
			doomed[#doomed + 1] = item
		end
	end
	for _, item in ipairs(doomed or {}) do drop(item, "expired") end
end

-- Messages written for another guild are dropped; nil when the current guild is not known yet (they wait).
local function guildCheck(current)
	local doomed
	for _, item in ipairs(state.queue) do
		if item.guild and current and item.guild ~= current then
			doomed = doomed or {}
			doomed[#doomed + 1] = item
		end
	end
	for _, item in ipairs(doomed or {}) do drop(item, "guild") end
end

-- The first message that may go now, in priority order; nil when none may. During a boss encounter only ALERT goes.
local function pick(t, current, boss)
	for _, item in ipairs(state.queue) do
		local gap = Transport.GAP[item.dist] or 1
		local last = state.lastAt[item.dist]
		local ok = item.notBefore <= t and (state.holdUntil[item.dist] or 0) <= t
			and (not boss or item.prio == "ALERT")
			and (last == nil or t - last >= gap - 1e-9)
			and (item.guild == nil or item.guild == current)
		if ok and not rateFits(item, t) then ok = false end
		if ok then return item end
	end
	return nil
end

local function giveBack(item)
	if item.typeEntry then item.typeEntry.dead = true item.typeEntry = nil end
end

local function onResult(item, result)
	state.inflight = state.inflight - 1
	local t, s, c = now(), state.stats, codes()
	if result == c.Success then
		s.sent, s.sentBytes = s.sent + 1, s.sentBytes + item.size
		s.sentBy[item.dist] = s.sentBy[item.dist] + 1
		s.bytesBy[item.dist] = s.bytesBy[item.dist] + item.size
		callUser(item.onSent)
		return
	end

	giveBack(item)
	local requeueAt
	if result == c.ChannelThrottle or result == c.AddonMessageThrottle then
		s.throttled = s.throttled + 1
		if item.attempts - 1 < Transport.MAX_RETRIES then
			requeueAt = t + Transport.RETRY_DELAY
			s.retried = s.retried + 1
		end
	elseif result == c.AddOnMessageLockdown then
		item.attempts = item.attempts - 1   -- the client refused before trying: not a try
		requeueAt = t + Transport.LOCKDOWN_RECHECK
	end

	if requeueAt then
		item.notBefore = requeueAt
		state.holdUntil[item.dist] = requeueAt
		insertSorted(item)
		ensureTicker()
		return
	end
	s.failed = s.failed + 1
	settle(item, type(result) == "number" and codeName(result) or tostring(result))
end

local function dispatch(item, t)
	removeFromQueue(item)
	item.attempts = item.attempts + 1
	state.lastAt[item.dist] = t
	if Transport.RATE[item.t] then
		local log = state.typeLog[item.t]
		if not log then log = {} state.typeLog[item.t] = log end
		if not groupEntry(log, item.rateGroup) then
			item.typeEntry = { time = t, group = item.rateGroup }
			log[#log + 1] = item.typeEntry
		end
	end
	state.inflight = state.inflight + 1
	local answered = false
	Transport.wire(item.prio, item.payload, item.dist, item.target, function(result)
		if answered then return end
		answered = true
		onResult(item, result)
	end)
end

-- One pass of the queue: expiry, the guild check, the client gate (lockdown, restrictions), then what may go.
pass = function()
	if ns.Demo and ns.Demo:IsActive() then return end   -- the queue waits for the exit from demo mode (SPEC-11 §3.1)
	local t = now()
	expire(t)
	local current = guildKey()
	guildCheck(current)
	local Chat = compat().Chat
	local held = (Chat.InChatLockdown() and "lockdown") or Chat.RestrictionAny() or nil
	local readOnly = Chat.OutgoingAddonRestricted()
	setGate(held, readOnly)
	local boss = Transport.BossSilence()
	state.boss = boss
	if not held and not readOnly then
		for _ = 1, Transport.QUEUE_MAX do
			local item = pick(t, current, boss)
			if not item then break end
			if item.officerOnly and not officerAllowed(item.dist, item.target) then
				drop(item, "officerOnly")   -- checked again as it leaves: the target may have been demoted while it waited
			else
				dispatch(item, t)
				t = now()
			end
		end
	end
	if #state.queue == 0 then stopTicker() end
end
Transport.Pass = function() pass() end   -- the ticker does this; tests and the simulator may call it directly

function Transport:Reset()
	stopTicker()
	resetState()
end

---------------------------------------------------------------------------------------------------------------------
-- The saved queue (SPEC-02 §5)
---------------------------------------------------------------------------------------------------------------------
local function outbox()
	local char = ns.Demo and ns.Demo:Real("char") or (ns.Config and ns.Config.db.char)   -- in demo mode: the saved table, not the copy
	if type(char) ~= "table" then return nil end
	if type(char.outbox) ~= "table" then char.outbox = {} end
	return char.outbox
end

-- PLAYER_LOGOUT: the waiting messages go to AzerothAccordCharDB.outbox (plain fields only: no callbacks).
function Transport:SaveQueue()
	local box = outbox()
	if not box then return 0 end
	for i = #box, 1, -1 do box[i] = nil end
	local t, server = now(), serverNow()
	for _, item in ipairs(state.queue) do
		local ttlLeft = item.ttl and (item.ttl - (t - item.bornAt)) or nil
		-- the officer tools' messages are never kept in the saved variables: the next session's sync repairs (OFF-05)
		if not item.officerOnly and (ttlLeft == nil or ttlLeft > 0) then
			box[#box + 1] = { dist = item.dist, target = item.target, t = item.t, payload = item.payload, prio = item.prio,
				key = item.key, guild = item.guild, saved = server, born = item.bornServer, ttl = ttlLeft and math.floor(ttlLeft) or nil }
		end
	end
	state.stats.saved = #box
	return #box
end

-- Login: the saved messages go back in the queue, then the outbox is emptied. A message older than SAVED_MAX_AGE, or
-- one whose time to live ran out while the game was closed, is dropped.
function Transport:RestoreQueue()
	local box = outbox()
	if not box or #box == 0 then return 0 end
	local server, t, restored = serverNow(), now(), 0
	for _, e in ipairs(box) do
		local valid = type(e) == "table" and Transport.DISTS[e.dist] and type(e.payload) == "string" and RANK[e.prio]
			and type(e.saved) == "number" and (e.dist ~= "WHISPER" or type(e.target) == "string")
		if valid then
			local away = server - e.saved
			local tooOld = server - (tonumber(e.born) or e.saved) > Transport.SAVED_MAX_AGE
			local ttl = tonumber(e.ttl)
			if not tooOld and (ttl == nil or ttl - away > 0) then
				state.seq = state.seq + 1
				if enqueue({ seq = state.seq, dist = e.dist, target = e.target, t = e.t, payload = e.payload, size = #e.payload,
					prio = e.prio, rank = RANK[e.prio], key = type(e.key) == "string" and e.key or nil, bornAt = t,
					bornServer = tonumber(e.born) or e.saved, ttl = ttl and (ttl - away) or nil, attempts = 0, notBefore = 0,
					guild = type(e.guild) == "string" and e.guild or nil, restored = true }) then
					restored = restored + 1
				end
			end
		end
	end
	for i = #box, 1, -1 do box[i] = nil end
	state.stats.restored = state.stats.restored + restored
	return restored
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------------------------------------------------

-- true when `sender` ("Name" or "Name-Realm", as the client gives it) is this character.
function Transport.IsSelf(sender)
	if type(sender) ~= "string" then return false end
	local C = compat()
	local name, realm = C.SplitName(sender)   -- "Name Surname-Realm": the realm after the last hyphen (SPEC-11 §6.6)
	if not name or name ~= C.Player.Name() then return false end
	return realm == nil or realm == C.Player.Realm()
end

local function senderKey(sender) return type(sender) == "string" and sender:lower() or "?" end

-- Puts `sender` in quarantine for QUARANTINE seconds (SPEC-11 §6.3): its messages are dropped before decoding. The
-- name stays in this table only, never in /accord debug.
function Transport:Quarantine(sender)
	local key = senderKey(sender)
	if not ((state.quarantine[key] or 0) > now()) then state.stats.quarantined = state.stats.quarantined + 1 end
	state.quarantine[key] = now() + Transport.QUARANTINE
	state.flood[key] = nil
end

function Transport:IsQuarantined(sender)
	local key = senderKey(sender)
	local untilAt = state.quarantine[key]
	if untilAt and untilAt <= now() then state.quarantine[key], untilAt = nil, nil end
	return untilAt ~= nil
end

-- How many senders are in quarantine now.
function Transport:QuarantineCount()
	local n, t = 0, now()
	for key, untilAt in pairs(state.quarantine) do
		if untilAt > t then n = n + 1 else state.quarantine[key] = nil end
	end
	return n
end

-- The counters per sender start again (a change of guild).
function Transport:ResetFlood()
	state.flood, state.quarantine = {}, {}
end

-- Adds `bytes` decoded for `sender`; true when the sender went over FLOOD and is now in quarantine.
local function countDecoded(sender, bytes)
	local key, t = senderKey(sender), now()
	local w = state.flood[key]
	if not w or t - w.start >= Transport.FLOOD[2] then
		w = { start = t, bytes = 0 }
		state.flood[key] = w
	end
	w.bytes = w.bytes + (tonumber(bytes) or 0)
	if w.bytes > Transport.FLOOD[1] then
		Transport:Quarantine(sender)
		return true
	end
	return false
end

-- Called by AceComm with a whole (reassembled) text. Returns true when a message went to the Bus.
function Transport:OnReceive(text, dist, sender)
	local s = state.stats
	s.received = s.received + 1
	if ns.Demo and ns.Demo:IsActive() then   -- demo mode: what arrives is dropped, counted as "demo"
		s.rxDropped = s.rxDropped + 1
		s.rxReasons.demo = (s.rxReasons.demo or 0) + 1
		return false, "demo"
	end
	if Transport.DISTS[dist] and Transport.IsSelf(sender) then
		-- the client echoes GUILD and OFFICER messages to the sender: an OFFICER echo proves the channel carries
		-- addon messages (M0 S5); the echo itself is not a message from someone else
		s.echoes = s.echoes + 1
		if dist == "OFFICER" and compat().Feature and compat():Feature("officerAddonChannel") ~= "available" then
			compat():SetFeature("officerAddonChannel", "available", "own OFFICER message came back")
		end
		return false, "self"
	end
	if Transport:IsQuarantined(sender) then   -- dropped before decoding (SPEC-11 §6.3)
		s.rxDropped = s.rxDropped + 1
		s.rxReasons.quarantine = (s.rxReasons.quarantine or 0) + 1
		return false, "quarantine"
	end
	local Codec = ns.Codec
	local msg, reason, size
	if not Transport.DISTS[dist] then
		msg, reason = nil, "dist"
	elseif not Codec then
		msg, reason = nil, "nocodec"
	else
		msg, reason, size = Codec:Decode(text)
		if countDecoded(sender, size or (type(text) == "string" and #text or 0)) then
			msg, reason = nil, "flood"
		end
	end
	if not msg then
		if reason == "newer" then
			s.rxNewer = s.rxNewer + 1
			if Codec:ConsumeNewer() and not state.newerNotified then
				state.newerNotified = true
				emit("PROTOCOL_NEWER")
			end
		else
			s.rxDropped = s.rxDropped + 1
			s.rxReasons[reason] = (s.rxReasons[reason] or 0) + 1
		end
		return false, reason
	end
	if dist == "OFFICER" and compat():Feature("officerAddonChannel") ~= "available" then
		compat():SetFeature("officerAddonChannel", "available", "an OFFICER message arrived")
	end
	emit("NET_MESSAGE", msg, sender, dist)
	return true
end

-- Registers the prefix and the AceComm callback (once). Returns false when AceComm is not there.
function Transport:Register()
	if Transport.registered then return true end
	local AceComm = LibStub and LibStub("AceComm-3.0", true)
	if not AceComm then return false end
	AceComm.RegisterComm(Transport, Transport.PREFIX, function(_, text, dist, sender)
		Transport:OnReceive(text, dist, sender)
	end)
	Transport.registered = true
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Statistics and /accord debug
---------------------------------------------------------------------------------------------------------------------
local function copyCounts(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

-- queued, sent, dropped, throttled (and the rest) as a plain table.
function Transport:Stats()
	local s = state.stats
	local by = { GUILD = 0, OFFICER = 0, WHISPER = 0 }
	for _, item in ipairs(state.queue) do by[item.dist] = by[item.dist] + 1 end
	return {
		queued = #state.queue, queuedBy = by, inflight = state.inflight,
		sent = s.sent, sentBytes = s.sentBytes, sentBy = copyCounts(s.sentBy), bytesBy = copyCounts(s.bytesBy),
		failed = s.failed, throttled = s.throttled, retried = s.retried, coalesced = s.coalesced, restored = s.restored,
		saved = s.saved, dropped = s.dropped, droppedBy = copyCounts(s.droppedBy), demoRefused = s.demoRefused,
		received = s.received, rxDropped = s.rxDropped, rxReasons = copyCounts(s.rxReasons), rxNewer = s.rxNewer,
		quarantined = s.quarantined, quarantinedNow = Transport:QuarantineCount(),
		echoes = s.echoes, encodeFailed = s.encodeFailed, callbackErrors = s.callbackErrors,
		readOnly = state.readOnly, held = state.held,
	}
end

local function countsText(t)
	local parts = {}
	for k, v in pairs(t) do parts[#parts + 1] = k .. " " .. v end
	sort(parts)
	return #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
end

function Transport:DebugLines()
	local st = self:Stats()
	local mode = "normal"
	if st.readOnly then mode = mode .. ", read-only" end
	if st.held then mode = mode .. ", held (" .. tostring(st.held) .. ")" end
	return {
		("Transport: %s, prefix %s, registered %s"):format(mode, tostring(Transport.PREFIX), Transport.registered and "yes" or "no"),
		("  queued %d (guild %d, officer %d, whisper %d), in flight %d, restored at login %d"):format(st.queued,
			st.queuedBy.GUILD, st.queuedBy.OFFICER, st.queuedBy.WHISPER, st.inflight, st.restored),
		("  sent %d (%d bytes; guild %d, officer %d, whisper %d), failed %d, throttled %d, retried %d, replaced by key %d, dropped %d%s"):format(
			st.sent, st.sentBytes, st.sentBy.GUILD, st.sentBy.OFFICER, st.sentBy.WHISPER, st.failed, st.throttled, st.retried,
			st.coalesced, st.dropped, countsText(st.droppedBy)),
		("  received %d, own echoes %d, rejected %d%s, newer protocol %d"):format(st.received, st.echoes, st.rxDropped,
			countsText(st.rxReasons), st.rxNewer),
		("  senders in quarantine: %d now, %d this session"):format(st.quarantinedNow, st.quarantined),
		st.demoRefused > 0 and ("  refused in demo mode: %d"):format(st.demoRefused) or nil,
	}
end

Transport.PREFIX = ns.Codec and ns.Codec.PREFIX or "AzAccord"
Transport:Register()

if ns.addon then
	ns.addon.Transport = Transport
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Transport", function() return Transport:DebugLines() end) end
	-- each module embeds AceEvent itself: one handler per event and object, so modules never replace each other's
	LibStub("AceEvent-3.0"):Embed(Transport)
	Transport:RegisterEvent("PLAYER_LOGOUT", function() Transport:SaveQueue() end)
	Transport:RegisterEvent("ENCOUNTER_START", function() if ns.Compat then ns.Compat.encounter = true end end)
	Transport:RegisterEvent("ENCOUNTER_END", function()
		if ns.Compat then ns.Compat.encounter = nil end
		if #state.queue > 0 then pass() end
	end)
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() Transport:ResetFlood() end) end
	if ns.OnEnable then ns.OnEnable(function() Transport:RestoreQueue() end) end
end

-- Sync: how the clients of a guild converge on the same records (SPEC-02 §4). Lua 5.1.
--
-- The trust rules (Net/Store.lua) decide WHO may pass a record on: its author's account (first hand) or an officer
-- (relay). So the sync works per author:
--
--   Summary   for every author a client holds records of: key (a 32-bit hash of the author GUID), digest (24 bits of a
--             hash of the author's records: set, id, rev, time) and the newest record time. 11 bytes per author.
--   HELLO     (GUILD) the summary, 10-30 s after login and then every 15-20 minutes (at most one per 5 minutes, NET-04).
--   push      a client that sees a HELLO and is AHEAD of the sender for an author it may deliver sends those records to
--             the sender by WHISPER after a random 0.5-3 s: its own account's authors always; an officer also the
--             authors whose account has nobody online, but only the one officer designated for that sender (the
--             smallest hash of officer GUID and sender GUID among the officers heard recently), so officers never
--             answer twice.
--   REQ       (WHISPER) a client that sees a HELLO from someone AHEAD of it, who may deliver that author (same account
--             or officer), asks for that author after a random 1-5 s, unless the records arrived meanwhile.
--   REC       records of one set. Answers to REQ go on GUILD with a queue key per author and set, so the same request
--             from many clients goes out once and everyone who missed it catches up; local changes go on GUILD after a
--             5-second batch; pushes go by WHISPER.
--   OHELLO    (OFFICER) the same summary for the records that only officers hold (the bank tabs an officer read:
--             Store.IsRestricted). Those records never travel on GUILD and never count in a GUILD summary, so a member's
--             summary and an officer's agree on everything a member may hold. A local change of such a record goes out as
--             REC on OFFICER; an officer who is ahead of an OHELLO sender pushes the missing ones by WHISPER (only the
--             officer designated for that sender, or the author's own account), exactly as for a HELLO.
--             The officer tools' records (SPEC-12, the `timeline` set: Store.IsOfficerTool) are a third class, summarised by
--             GROUP (the month of a day) in the field `m` of OHELLO, not by author: they go on OFFICER or by WHISPER to an
--             officer (Transport `officerOnly`), and only once this client has seen the officer channel work (S5, OFF-07):
--             until then they stay on this computer and reach the others through the comparison of `m` later (OFF-09).
--   BHELLO    (GUILD, SPEC-11 §6.4) a client that holds more than BLOCK_OVER authors sends, instead of the HELLO, the
--             summary in BLOCKS blocks of 3 bytes (an author is in block BlockOf(key), a Fibonacci hash of its key; a
--             block's digest is the sum modulo 2^24 of a hash of key, digest and time of each of its authors), when every
--             officer heard recently runs a version that knows it (`av` from 0.7.0). Who receives it compares its own
--             blocks; when some differ, only the officer designated for the sender answers (with every author of those
--             blocks) and a character of the sender's own account (with its account's authors only, `o` set).
--   DIGEST    (WHISPER) that answer: d = { [block] = the per-author summary of the block }, key DIGEST|<sender>, at most
--             one every 2 s (Transport.RATE). The BHELLO sender then works author by author as with a HELLO: it asks with
--             REQ for what the other is ahead in, and pushes what it is ahead in when it may deliver it (its own account,
--             or it is an officer). A DIGEST nobody asked for (no BHELLO sent in the last BHELLO_ANSWER seconds) is ignored.
--   askSync:RequestSet(set, author): a view needs one author's records of ONE set now (a member's recipes), so it
--             sends a REQ for just that set by WHISPER to a peer that may deliver (the author's own account if online, else
--             up to two officers heard recently); the answer is a WHISPER REC with only those records, not a GUILD one.
--             Asked at most once per ASK_COOLDOWN seconds per author and set.
--
-- Received records always go through Store:Receive, so a client that is not allowed to pass something on is simply
-- refused by the others. Every timer is cancelled on a change of guild. Bus: SYNC_HELLO(sent), SYNC_RECEIVED(set, n).
--
-- Limits per sender against a bad or broken client (SPEC-11 §6.1, §6.3; the counters start again at a change of guild):
-- a REC with more than MAX_REC records is dropped whole; one HELLO or BHELLO per HELLO_EVERY seconds is handled, the
-- others are ignored (`flood`); REQ of every set at most REQ_ALL_RATE; more than REFUSED_LIMIT refused records (not the
-- ones simply not newer) put the sender in quarantine (Transport:Quarantine). The first HELLO after login waits
-- HELLO_DELAY[1] + random(0, HELLO_DELAY[2] + authors / 10) seconds, so a thousand logins after a restart spread out.
local ADDON_NAME, ns = ...
ns = ns or {}
local Sync = {}
ns.Sync, ns.modules = Sync, ns.modules or {}
ns.modules.Sync = Sync

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, random, min, max = math.floor, math.random, math.min, math.max
local byte, char, sort, concat = string.byte, string.char, table.sort, table.concat

Sync.AUTO = true                    -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Sync.HELLO_DELAY = { 10, 20 }       -- seconds after login: [1] + random(0, [2] + authors / 10) (SPEC-11 §6.4)
Sync.HELLO_PERIOD = { 900, 1200 }   -- seconds between two HELLOs while online
Sync.PUSH_DELAY = { 0.5, 3 }
Sync.REQ_DELAY = { 1, 5 }
Sync.BATCH = 5                      -- seconds a local change waits, so several changes go out together
Sync.PRESENCE = 1500                -- a peer counts as online this long after its last message
Sync.REC_BYTES = 2500               -- estimated size of the records in one REC (the codec limit is far above)
Sync.ENTRY = 11                     -- bytes per author in a summary
Sync.ASK_COOLDOWN = 300             -- seconds before the same set of the same author is asked for again
Sync.ASK_OFFICERS = 2               -- officers asked when the author's account is not online
Sync.ASK_RATE = { 20, 60 }          -- answers to set requests: at most 20 per sender per 60 seconds
Sync.REQ_ALL_RATE = { 10, 60 }      -- requests of every set ("*") handled per sender per 60 seconds
Sync.HELLO_EVERY = 60               -- seconds: one HELLO or BHELLO per sender is handled in this time
Sync.MAX_REC = 100                  -- records in one REC; a bigger one is dropped whole
Sync.REFUSED_LIMIT = { 50, 600 }    -- refused records per sender in this many seconds before its quarantine
Sync.BLOCK_OVER = 200               -- more authors than this: BHELLO instead of HELLO
Sync.BLOCKS = 96                    -- blocks of a BHELLO, 3 bytes each: the message stays under 512 B (SPEC-11 §6.5)
Sync.BLOCK_SINCE = { 0, 7, 0 }      -- the first version that knows BHELLO
Sync.DIGEST_MAX = 1400              -- entries in one DIGEST (11 bytes each: the message stays under Codec.MAX_DECODED)
Sync.BHELLO_ANSWER = 600            -- seconds after a BHELLO in which a DIGEST is expected

if ns.Codec then ns.Codec:RegisterType("BHELLO", { b = "string" }) end

local function compat() return ns.Compat end
local function store() return ns.Store end
local function hash() return ns.Hash end
local function now() return compat().Now() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function between(r) return r[1] + (r[2] - r[1]) * random() end

local state
local function resetState()
	if state then
		for _, t in pairs(state.timers or {}) do if t.Cancel then t:Cancel() end end
	end
	state = {
		present = {},          -- sender name -> { guid, at, officer }
		push = {},             -- target name -> { authors = { [guid] = true }, timer }
		req = {},              -- target name -> { keys = { [key] = true }, theirs = summary, timer }
		dirty = {},            -- set -> { [id] = true }: local changes waiting for the batch
		officerSent = {},      -- set of an officer tool -> when its records last went out on OFFICER (publishEvery)
		asked = {},            -- "<set>|<author>" -> when this client asked for it (RequestSet)
		answering = {},        -- sender name -> { start, count }: the rate of the set requests answered
		rates = {},            -- "<what>|<lower-case sender>" -> { start, count }: the limits per sender (SPEC-11 §6.3)
		heard = {},            -- lower-case sender -> when its last HELLO or BHELLO was handled
		waiting = {},          -- lower-case sender -> { msg, sender, handler }: its latest HELLO or BHELLO, held to the minute's end
		versions = {},         -- sender name -> the `av` of its last HELLO or BHELLO
		digested = {},         -- lower-case sender -> true: its DIGEST to the current BHELLO was handled
		bhelloAt = nil,        -- when this client last sent a BHELLO
		batchTimer = nil, helloTimer = nil, timers = {},
		groups = nil,          -- [restricted] = author -> group, kept up to date record by record (Sync:Groups)
		owner = {},            -- "<set>|<id>" -> { author, restricted }: where each record sits in `groups`
		pending = {}, pendingCount = 0, rebuild = true,   -- records changed since, or a full rebuild is due
		version = 0, blocks = nil,
		stats = { hellosSent = 0, hellosHeard = 0, pushes = 0, requests = 0, answers = 0, recSent = 0, recReceived = 0,
			accepted = 0, refused = 0, asks = 0, asksAnswered = 0, asksLimited = 0,
			bhellosSent = 0, bhellosHeard = 0, digestsSent = 0, digestsHeard = 0, flood = 0, oversized = 0, quarantined = 0 },
	}
	Sync.state = state
end
resetState()

---------------------------------------------------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------------------------------------------------
local keyCache = {}
function Sync.KeyOf(guid)
	local k = keyCache[guid]
	if not k then
		k = hash().Fast(guid)
		keyCache[guid] = k
	end
	return k
end

-- The hashes already computed, by text (an author whose records did not change gives the same text again: the full
-- read before each HELLO costs no hashing for it). Emptied when it grows past FAST_MEMO entries.
local fastMemo, fastMemoSize, FAST_MEMO = {}, 0, 6000
local function fast(text)
	local h = fastMemo[text]
	if not h then
		h = hash().Fast(text)
		if fastMemoSize >= FAST_MEMO then fastMemo, fastMemoSize = {}, 0 end
		fastMemo[text], fastMemoSize = h, fastMemoSize + 1
	end
	return h
end

-- The key, digest, newest time, block hash (h) and record list of a group from its records (byId).
local function finishGroup(author, g)
	local parts, records, t = {}, {}, 0
	for _, e in pairs(g.byId) do
		local set, rec, id = e[1], e[2], e[3]
		records[#records + 1] = e
		parts[#parts + 1] = set .. "|" .. tostring(id) .. "|" .. tostring(rec.rev) .. "|" .. tostring(rec.time)
		if (rec.time or 0) > t then t = rec.time end
	end
	if #parts > 1 then
		sort(parts)
		sort(records, function(a, b) return a[4] < b[4] end)   -- a stable order: the same records give the same messages
	end
	g.records, g.t = records, t
	g.key = Sync.KeyOf(author)
	g.d = fast(concat(parts, "\n")) % 16777216
	g.h = fast(g.key .. "|" .. g.d .. "|" .. max(0, min(floor(t), 4294967295)))
end

local function ownerKey(set, id) return set .. "|" .. tostring(id) end

-- The three classes of groups: false (what a member may hold, per author), true (the officers' bank tabs, per author) and
-- "officer" (the officer tools, per group name).
local CLASSES = { false, true, "officer" }

-- The class of a record and the key of its group in that class.
local function classOf(set, rec)
	local S = store()
	if S.IsOfficerTool(set) then
		local def = S.SETS[set]
		local ok, name = pcall(def.group or function() return set end, rec)
		return "officer", ok and name or set
	end
	return S.IsRestricted(set, rec), rec.author
end

-- Puts record `id` of `set` (as the store holds it now) in its group; returns the key of the group (the author, or the
-- group name of an officer tool) and its class, or nil.
local function place(groups, set, id, rec)
	local author = type(rec) == "table" and rec.author
	if type(author) ~= "string" then return nil end
	local class, key = classOf(set, rec)
	local into = groups[class]
	local g = into[key]
	if not g then g = { byId = {} } into[key] = g end
	local k = ownerKey(set, id)
	g.byId[k] = { set, rec, id, k }
	state.owner[k] = { key, class }
	return key, class
end

-- Every group again from the whole store: at the first use, before every HELLO sent, after a change of many records.
local function rebuildGroups()
	local S = store()
	local groups = { [false] = {}, [true] = {}, officer = {} }
	state.owner = {}
	for _, set in ipairs(S.SET_ORDER) do
		for id, rec in pairs(S:Records(set)) do place(groups, set, id, rec) end
	end
	for _, r in ipairs(CLASSES) do
		for author, g in pairs(groups[r]) do finishGroup(author, g) end
	end
	state.groups, state.rebuild = groups, false
	state.pending, state.pendingCount = {}, 0
end

-- Only the groups of the records that changed (their old author and their new one) are computed again.
local function updateGroups()
	local groups, touched = state.groups, { [false] = {}, [true] = {}, officer = {} }
	local S = store()
	for k, e in pairs(state.pending) do
		local was = state.owner[k]
		if was then
			local g = groups[was[2]][was[1]]
			if g then g.byId[k] = nil end
			touched[was[2]][was[1]] = true
			state.owner[k] = nil
		end
		local key, class = place(groups, e[1], e[2], S:Get(e[1], e[2]))
		if key then touched[class][key] = true end
	end
	for _, r in ipairs(CLASSES) do
		local into = groups[r]
		for key in pairs(touched[r]) do
			local g = into[key]
			if g and next(g.byId) then finishGroup(key, g) else into[key] = nil end
		end
	end
	state.pending, state.pendingCount = {}, 0
end

-- The summary must be exact again: the next Groups() reads the whole store (a backup import, the demo, cleared data).
function Sync:Invalidate()
	state.rebuild = true
	state.version = state.version + 1
end

-- author GUID -> { key, d, t, h, records = { { set, rec, id }, ... } } over every data set of the current guild. The
-- records for officers only (Store.IsRestricted) are left out, unless `restricted` is true: then only those are
-- grouped; `"officer"` gives the officer tools' records by group name (SPEC-12 §1.5). Kept up to date record by record from STORE_CHANGED, so a guild of a thousand authors does not compute them
-- all again for each record that arrives (SPEC-11 §6.5); read whole again before each HELLO sent.
function Sync:Groups(class)
	if state.rebuild or not state.groups then rebuildGroups()
	elseif state.pendingCount > 0 then updateGroups() end
	if class == "officer" then return state.groups.officer end
	return state.groups[class == true]
end

local function be(n, bytes)
	local out = {}
	for i = bytes, 1, -1 do
		out[i] = char(n % 256)
		n = floor(n / 256)
	end
	return concat(out)
end

local function readBE(s, at, bytes)
	local n = 0
	for i = at, at + bytes - 1 do n = n * 256 + byte(s, i) end
	return n
end

-- The summary as a byte string: entries sorted by key, each key (4 bytes), digest (3), newest time (4).
function Sync:EncodeSummary(groups)
	local entries = {}
	for _, g in pairs(groups or self:Groups()) do entries[#entries + 1] = g end
	sort(entries, function(a, b) return a.key < b.key end)
	local out = {}
	for i, g in ipairs(entries) do
		out[i] = be(g.key, 4) .. be(g.d, 3) .. be(max(0, min(floor(g.t), 4294967295)), 4)
	end
	return concat(out)
end

-- key -> { d, t } from a summary string, or nil when it is malformed.
function Sync.DecodeSummary(s)
	if type(s) ~= "string" or #s % Sync.ENTRY ~= 0 or #s > Sync.ENTRY * 2000 then return nil end
	local out = {}
	for at = 1, #s, Sync.ENTRY do
		out[readBE(s, at, 4)] = { d = readBE(s, at + 4, 3), t = readBE(s, at + 7, 4) }
	end
	return out
end

-- The block of an author key: its place in BLOCKS equal parts of key x 2654435761 mod 2^32 (Fibonacci hashing). Not of
-- the key itself: Hash.Fast gives nearly the same high bits to GUIDs that differ only in their last digits, as the
-- characters of one realm do, and they would all fall in a few blocks. Exact in Lua's doubles (16-bit halves).
local FIB = 2654435761
function Sync.BlockOf(key)
	local lo, hi = key % 65536, floor(key / 65536)
	local mixed = (lo * FIB + (hi * FIB % 65536) * 65536) % 4294967296
	return floor(mixed / 4294967296 * Sync.BLOCKS)
end

-- The digest of each block of `groups` (block -> 24-bit number, 0 for an empty block), cached until the store changes
-- when `groups` is the current summary.
function Sync:BlockSums(groups)
	local current = groups == nil
	groups = groups or self:Groups()
	if current and state.blocks and state.blocks.version == state.version then return state.blocks.sums end
	local sums, H = {}, hash()
	for b = 0, Sync.BLOCKS - 1 do sums[b] = 0 end
	for _, g in pairs(groups) do
		local b = Sync.BlockOf(g.key)
		local h = g.h or H.Fast(g.key .. "|" .. g.d .. "|" .. max(0, min(floor(g.t), 4294967295)))
		sums[b] = (sums[b] + h) % 16777216
	end
	if current then state.blocks = { version = state.version, sums = sums } end
	return sums
end

-- The blocks of a BHELLO as a byte string: BLOCKS digests of 3 bytes, block 0 first (cached with the sums for the
-- current summary).
function Sync:EncodeBlocks(groups)
	local sums, out = self:BlockSums(groups), {}
	local current = groups == nil and state.blocks
	if current and current.text then return current.text end
	for b = 0, Sync.BLOCKS - 1 do out[b + 1] = be(sums[b], 3) end
	local text = concat(out)
	if current then current.text = text end
	return text
end

-- block -> digest from a BHELLO's `b`, or nil when it is malformed.
function Sync.DecodeBlocks(s)
	if type(s) ~= "string" or #s ~= Sync.BLOCKS * 3 then return nil end
	local out = {}
	for b = 0, Sync.BLOCKS - 1 do
		local x, y, z = byte(s, b * 3 + 1, b * 3 + 3)
		out[b] = (x * 256 + y) * 256 + z
	end
	return out
end

-- true when an addon version (`av` of a HELLO) knows BHELLO: from BLOCK_SINCE on, or a source checkout (its version
-- field is not filled in: it runs the newest code).
function Sync.KnowsBlocks(av)
	if type(av) ~= "string" then return false end
	if av == "@project-version@" then return true end
	local a, b, c = av:match("(%d+)%.(%d+)%.?(%d*)")
	if not a then return false end
	local v = { tonumber(a), tonumber(b), tonumber(c) or 0 }
	for i = 1, 3 do
		if v[i] ~= Sync.BLOCK_SINCE[i] then return v[i] > Sync.BLOCK_SINCE[i] end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Limits per sender (SPEC-11 §6.3)
---------------------------------------------------------------------------------------------------------------------
local function lowerName(sender) return type(sender) == "string" and sender:lower() or "?" end

-- Counts one event `what` of `sender`; true while it stays within { count, seconds }.
local function within(what, sender, rate, n)
	local key, t = what .. "|" .. lowerName(sender), now()
	local w = state.rates[key]
	if not w or t - w.start >= rate[2] then
		w = { start = t, count = 0 }
		state.rates[key] = w
	end
	w.count = w.count + (n or 1)
	return w.count <= rate[1]
end

-- `n` records of `sender` were refused: over REFUSED_LIMIT the sender goes in quarantine.
local function refusedBy(sender, n)
	if n <= 0 then return end
	if not within("refused", sender, Sync.REFUSED_LIMIT, n) and ns.Transport and ns.Transport.Quarantine then
		if not ns.Transport:IsQuarantined(sender) then state.stats.quarantined = state.stats.quarantined + 1 end
		ns.Transport:Quarantine(sender)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Peers
---------------------------------------------------------------------------------------------------------------------
local function myGUID() return compat().Player.GUID() end

local function touch(sender)
	local member = store():Member(sender)
	if not member or type(member.guid) ~= "string" then return nil end
	state.present[sender] = { guid = member.guid, at = now(), officer = member.officer == true }
	return member
end

-- The peers with the addon that are online: heard within PRESENCE seconds and not offline in the roster (the roster
-- tells at once when somebody logs out; the last message alone would keep them "present" for minutes).
local function presentPeers()
	local t, out, S = now(), {}, store()
	for name, p in pairs(state.present) do
		local member = S:Member(name)
		if t - p.at > Sync.PRESENCE or (member and member.online == false) then
			state.present[name] = nil
		else
			out[name] = p
		end
	end
	return out
end

-- The GUIDs whose account has somebody online right now (this character and the peers heard recently).
local function onlineAccounts()
	local S, set = store(), {}
	local function mark(guid)
		set[guid] = true
		local rec = S:Get("accounts", guid)
		if rec and type(rec.chars) == "table" then
			for _, c in ipairs(rec.chars) do
				local g = type(c) == "table" and c.guid or c
				if type(g) == "string" and S:SameAccount(guid, g) then set[g] = true end
			end
		end
	end
	local me = myGUID()
	if me then mark(me) end
	for _, p in pairs(presentPeers()) do mark(p.guid) end
	return set
end

local function iAmOfficer() return ns.Role and ns.Role:IsOfficer() or false end

-- true when this client has seen an addon message arrive on OFFICER in this session (S5, SPEC-12 §1.4): the only time the
-- officer tools' records may leave this computer.
local function proven() return ns.Officer ~= nil and ns.Officer.ChannelProven() end

-- true when this client is the officer designated to relay to `targetGUID` (NET-04: one answer, not one per officer).
local function designated(targetGUID)
	if not iAmOfficer() then return false end
	local me = myGUID()
	local H = hash()
	local best, bestGUID = H.Fast(me .. targetGUID), me
	for _, p in pairs(presentPeers()) do
		if p.officer and p.guid ~= targetGUID then
			local v = H.Fast(p.guid .. targetGUID)
			if v < best or (v == best and p.guid < bestGUID) then best, bestGUID = v, p.guid end
		end
	end
	return bestGUID == me
end

-- true when `mine` (a group or nil) is ahead of `theirs` (a summary entry or nil).
local function ahead(mine, theirs)
	if not mine then return false end
	if not theirs then return true end
	if mine.t ~= theirs.t then return mine.t > theirs.t end
	return mine.d ~= theirs.d
end

---------------------------------------------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------------------------------------------
local function send(dist, msg, opts)
	if not ns.Transport then return nil end
	return ns.Transport:Send(dist, msg, opts)
end

-- REC messages for a list of { set, rec } entries, split by set and by size.
local function sendRecords(entries, dist, target, keyPrefix)
	local bySet = {}
	for _, e in ipairs(entries) do
		local list = bySet[e[1]]
		if not list then list = {} bySet[e[1]] = list end
		list[#list + 1] = e[2]
	end
	local Config = ns.Config
	local count = 0
	for _, set in ipairs(store().SET_ORDER) do
		local list = bySet[set]
		if list then
			sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
			local batch, size, part = {}, 0, 0
			local function flush()
				if #batch == 0 then return end
				part = part + 1
				send(dist, { t = "REC", s = set, r = batch }, {
					target = target, key = keyPrefix and (keyPrefix .. "|" .. set .. "|" .. part) or nil,
					officerOnly = store().IsOfficerTool(set) or nil,   -- never on GUILD, only to an officer (OFF-05)
				})
				count = count + 1
				state.stats.recSent = state.stats.recSent + 1
				batch, size = {}, 0
			end
			for _, rec in ipairs(list) do
				local bytes = Config and Config.EstimateSize(rec) or 200
				if size > 0 and (size + bytes > Sync.REC_BYTES or #batch >= Sync.MAX_REC) then flush() end
				batch[#batch + 1] = rec
				size = size + bytes
			end
			flush()
		end
	end
	return count
end

local function recordsOf(authors, class)
	local groups, entries = Sync:Groups(class), {}
	for author in pairs(authors) do
		local g = groups[author]
		if g then for _, e in ipairs(g.records) do entries[#entries + 1] = e end end
	end
	return entries
end

-- A cancellable one-shot timer, remembered so a change of guild cancels it.
local function after(seconds, fn)
	local timer
	timer = compat().NewTimer(seconds, function()
		if timer then state.timers[timer] = nil end
		fn()
	end)
	if timer then state.timers[timer] = timer end
	return timer
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- true when this client may send a BHELLO: every officer heard recently (and still online) whose HELLO told its version
-- runs one that knows it (SPEC-11 §6.4). An officer heard only through other messages so far (a REC it answered
-- before its own first HELLO, as after a restart of the server) does not count until its HELLO says its version: an
-- older client sends `av` too, so it is recognised at its first HELLO. Without any officer heard it may.
function Sync:BlocksAllowed()
	for name, p in pairs(presentPeers()) do
		local av = state.versions[name]
		if p.officer and av ~= nil and not Sync.KnowsBlocks(av) then return false end
	end
	return true
end

-- Sends a HELLO with the current summary, or a BHELLO with its blocks when this client holds more than BLOCK_OVER
-- authors and every officer heard knows it (the transport keeps either to one per five minutes).
function Sync:SendHello()
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false end
	local version = ns.addon and C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	local av = type(version) == "string" and version:sub(1, 20) or nil
	Sync:Invalidate()   -- the summary sent is read from the whole store (a change without its event cannot linger)
	local groups = self:Groups()
	local authors = count(groups)
	local ok
	if authors > Sync.BLOCK_OVER and self:BlocksAllowed() then
		ok = send("GUILD", { t = "BHELLO", b = self:EncodeBlocks(groups), n = authors, av = av }, { key = "HELLO" })
		if ok then
			state.stats.bhellosSent = state.stats.bhellosSent + 1
			state.bhelloAt, state.digested = now(), {}
		end
	else
		ok = send("GUILD", { t = "HELLO", d = {}, s = self:EncodeSummary(groups), av = av }, { key = "HELLO" })
	end
	if ok then
		state.stats.hellosSent = state.stats.hellosSent + 1
		emit("SYNC_HELLO", true)
	end
	-- the officers also tell each other what they hold of the restricted records (OFFICER, never GUILD)
	-- the officer tools' records have a summary of their own, `m` (by group; it carries no data, so it goes even before
	-- the channel is proven, OFF-08)
	if iAmOfficer() then
		send("OFFICER", { t = "OHELLO", s = self:EncodeSummary(self:Groups(true)), m = self:EncodeSummary(self:Groups("officer")) },
			{ key = "OHELLO" })
	end
	return ok and true or false
end

local function scheduleHello(range)
	if state.helloTimer then state.helloTimer:Cancel() end
	state.helloTimer = after(between(range), function()
		state.helloTimer = nil
		Sync:SendHello()
		scheduleHello(Sync.HELLO_PERIOD)
	end)
end

-- Starts the HELLO cycle (at login, or when the character joins a guild).
function Sync:Start()
	if not self.AUTO then return false end
	if ns.Demo and ns.Demo:IsActive() then return false end   -- demo mode sends nothing: no timer (SPEC-11 §3.1)
	scheduleHello(Sync.FirstHelloDelay())
	return true
end

-- The range of the wait before the first HELLO after login: the more authors a guild has, the more the logins after a
-- server restart spread out (SPEC-11 §6.4: 1000 authors, 10 to 130 seconds).
function Sync.FirstHelloDelay(authors)
	authors = authors or count(Sync:Groups())
	return { Sync.HELLO_DELAY[1], Sync.HELLO_DELAY[1] + Sync.HELLO_DELAY[2] + authors / 10 }
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------------------------------------------------
-- Pushes the records of `authors` to `sender` by WHISPER after PUSH_DELAY (one batch per sender).
local function schedulePush(sender, authors)
	if not next(authors) then return end
	local entry = state.push[sender]
	if not entry then
		entry = { authors = {} }
		state.push[sender] = entry
		entry.timer = after(between(Sync.PUSH_DELAY), function()
			state.push[sender] = nil
			local n = sendRecords(recordsOf(entry.authors), "WHISPER", sender)
			if n > 0 then state.stats.pushes = state.stats.pushes + 1 end
		end)
	end
	for a in pairs(authors) do entry.authors[a] = true end
end

-- Asks `sender` (REQ by WHISPER after REQ_DELAY) for the author keys in `wanted` that `theirs` (its summary, or the part
-- of it a DIGEST gave) has newer, unless they arrived meanwhile.
local function scheduleReq(sender, theirs, wanted)
	if not next(wanted) then return end
	local entry = state.req[sender]
	if not entry then
		entry = { keys = {}, theirs = {} }
		state.req[sender] = entry
		entry.timer = after(between(Sync.REQ_DELAY), function()
			state.req[sender] = nil
			local still, list = Sync:Groups(), {}
			local byKey = {}
			for _, g in pairs(still) do byKey[g.key] = g end
			for key in pairs(entry.keys) do
				local mine, other = byKey[key], entry.theirs[key]
				if other and (mine == nil or other.t > mine.t) then list[#list + 1] = key end
			end
			if #list == 0 then return end
			sort(list)
			send("WHISPER", { t = "REQ", s = "*", a = list }, { target = sender })
			state.stats.requests = state.stats.requests + 1
		end)
	end
	for key in pairs(wanted) do
		entry.keys[key] = true
		entry.theirs[key] = theirs[key]
	end
end

-- The keys of `theirs` (key -> { d, t }) that this client is behind on and `member` may deliver (the same author, its
-- account, or `member` is an officer), compared with `groups` (this client's summary, or the part a DIGEST covers).
local function behindOn(theirs, member, groups)
	local S, target = store(), member.guid
	local myKeys = {}
	for author, g in pairs(groups) do myKeys[g.key] = author end
	local senderOfficer = member.officer == true
	local wanted = {}
	for key, entryTheirs in pairs(theirs) do
		local author = myKeys[key]
		local mine = author and groups[author]
		if mine == nil or entryTheirs.t > mine.t then
			local canDeliver = senderOfficer or key == Sync.KeyOf(target)
				or (author ~= nil and S:SameAccount(target, author))
			-- this includes the client's own records: after a lost or older saved file it gets its versions back,
			-- so its next write does not start again from rev 1
			if canDeliver then wanted[key] = true end
		end
	end
	return wanted
end

-- Remembers the version a sender announced and asks the server for a fresh roster now and then (it answers later,
-- throttled): the roster says who is online.
local function heardHello(msg, sender, member)
	if member.officer and type(msg.av) == "string" then state.versions[sender] = msg.av:sub(1, 20) end
	local t = now()
	if not state.rosterAsked or t - state.rosterAsked > 60 then
		state.rosterAsked = t
		compat().Guild.RequestRoster()
	end
end

-- true when a HELLO or BHELLO of `sender` may be handled now: one per HELLO_EVERY seconds (SPEC-11 §6.3). One that comes
-- sooner is counted (`flood`) but not lost: only the latest is kept and handled when the time is up, because an honest
-- client that logs in again (a /reload) sends its next HELLO within the minute.
local function helloAllowed(msg, sender, handler)
	local key, t = lowerName(sender), now()
	local last = state.heard[key]
	if last and t - last < Sync.HELLO_EVERY then
		state.stats.flood = state.stats.flood + 1
		local wait = state.waiting[key]
		if wait then
			wait.msg, wait.sender, wait.handler = msg, sender, handler
		else
			wait = { msg = msg, sender = sender, handler = handler }
			state.waiting[key] = wait
			after(Sync.HELLO_EVERY - (t - last) + 0.05, function()
				if state.waiting[key] ~= wait then return end
				state.waiting[key] = nil
				wait.handler(wait.msg, wait.sender)
			end)
		end
		return false
	end
	state.heard[key] = t
	return true
end

local function onHello(msg, sender)
	local theirs = Sync.DecodeSummary(msg.s)
	if not theirs then return end
	local member = touch(sender)
	if not member then return end
	if not helloAllowed(msg, sender, onHello) then return end
	state.stats.hellosHeard = state.stats.hellosHeard + 1
	heardHello(msg, sender, member)
	local target, S = member.guid, store()
	local me = myGUID()
	local groups = Sync:Groups()
	local accountsOnline = onlineAccounts()
	local isDesignated = nil

	-- push what the sender lacks and this client may deliver
	local pushAuthors = {}
	for author, g in pairs(groups) do
		if ahead(g, theirs[g.key]) then
			local targetsOwn = author == target or S:SameAccount(author, target)
			if me and S:SameAccount(me, author) and not targetsOwn then
				pushAuthors[author] = true
			elseif targetsOwn or not accountsOnline[author] then
				-- an offline author, or the sender's own records that it lost (a new computer): one officer relays
				if isDesignated == nil then isDesignated = designated(target) end
				if isDesignated then pushAuthors[author] = true end
			end
		end
	end
	schedulePush(sender, pushAuthors)

	-- ask for what the sender has newer and may deliver
	scheduleReq(sender, theirs, behindOn(theirs, member, groups))
end

-- A BHELLO (SPEC-11 §6.4): when blocks differ, the designated officer answers with every author of those blocks, a
-- character of the sender's own account with its account's authors only. Everybody else stays silent.
local function onBlockHello(msg, sender)
	if type(msg.b) ~= "string" or #msg.b ~= Sync.BLOCKS * 3 then return end
	local member = touch(sender)
	if not member then return end
	if not helloAllowed(msg, sender, onBlockHello) then return end
	state.stats.bhellosHeard = state.stats.bhellosHeard + 1
	heardHello(msg, sender, member)
	if msg.b == Sync:EncodeBlocks() then return end   -- the usual case: in step, nothing to compare (SPEC-11 §6.5: <= 1 ms)
	local theirs = Sync.DecodeBlocks(msg.b)
	local target, S, me = member.guid, store(), myGUID()
	local mine = Sync:BlockSums()
	local differ, any = {}, false
	for b = 0, Sync.BLOCKS - 1 do
		if theirs[b] ~= mine[b] then differ[b], any = true, true end
	end
	if not any then return end
	local all = designated(target)
	local own = not all and me ~= nil and me ~= target and S:SameAccount(me, target)
	if not (all or own) then return end
	local byBlock = {}
	for b in pairs(differ) do byBlock[b] = {} end
	for author, g in pairs(Sync:Groups()) do
		local list = byBlock[Sync.BlockOf(g.key)]
		if list and (all or S:SameAccount(me, author)) then list[#list + 1] = g end
	end
	local blocks = {}
	for b in pairs(byBlock) do blocks[#blocks + 1] = b end
	sort(blocks)
	local d, entries = {}, 0
	for _, b in ipairs(blocks) do
		local list = byBlock[b]
		if entries + #list > Sync.DIGEST_MAX then break end   -- the rest waits for the next BHELLO
		entries = entries + #list
		d[b] = Sync:EncodeSummary(list)
	end
	if not next(d) then return end
	if send("WHISPER", { t = "DIGEST", d = d, o = own and 1 or nil }, { target = sender, key = "DIGEST|" .. sender }) then
		state.stats.digestsSent = state.stats.digestsSent + 1
	end
end

-- The answer to this client's BHELLO: author by author, as with a HELLO, for the blocks it lists.
local function onDigest(msg, sender)
	if type(msg.d) ~= "table" then return end
	if not state.bhelloAt or now() - state.bhelloAt > Sync.BHELLO_ANSWER then return end   -- nobody asked
	local key = lowerName(sender)
	if state.digested[key] then return end   -- one answer per sender and BHELLO
	local member = touch(sender)
	if not member then return end
	local theirs, blocks, entries = {}, {}, 0
	for k, s in pairs(msg.d) do
		local b = tonumber(k)
		if not (b and b == floor(b) and b >= 0 and b < Sync.BLOCKS) then return end
		local part = Sync.DecodeSummary(s)
		if not part then return end
		blocks[b] = true
		for authorKey, e in pairs(part) do
			if Sync.BlockOf(authorKey) == b then
				theirs[authorKey] = e
				entries = entries + 1
			end
		end
		if entries > 2000 then return end
	end
	if not next(blocks) then return end
	state.digested[key] = true
	state.stats.digestsHeard = state.stats.digestsHeard + 1
	local S, me = store(), myGUID()
	local ownOnly = msg.o ~= nil
	local groups, part = Sync:Groups(), {}
	for author, g in pairs(groups) do
		if blocks[Sync.BlockOf(g.key)] and (not ownOnly or (me and S:SameAccount(me, author))) then part[author] = g end
	end
	-- push what this client is ahead in and may deliver: its own account always, everything when it is an officer
	local officer, pushAuthors = iAmOfficer(), {}
	for author, g in pairs(part) do
		if ahead(g, theirs[g.key]) and (officer or (me and S:SameAccount(me, author))) then pushAuthors[author] = true end
	end
	schedulePush(sender, pushAuthors)
	scheduleReq(sender, theirs, behindOn(theirs, member, part))
end

-- An officer's OHELLO: the restricted records (bank tabs read by an officer) are pushed to an officer who lacks them. Only
-- officers speak and listen here; a member never holds such a record.
local function onOfficerHello(msg, sender)
	if not iAmOfficer() then return end
	local theirs = Sync.DecodeSummary(msg.s)
	if not theirs then return end
	local member = touch(sender)
	if not (member and member.officer) then return end
	local target, S, me = member.guid, store(), myGUID()
	local groups = Sync:Groups(true)
	local pushAuthors, isDesignated = {}, nil
	for author, g in pairs(groups) do
		if ahead(g, theirs[g.key]) then
			if me and S:SameAccount(me, author) and author ~= target and not S:SameAccount(author, target) then
				pushAuthors[author] = true
			else
				if isDesignated == nil then isDesignated = designated(target) end
				if isDesignated and author ~= target then pushAuthors[author] = true end
			end
		end
	end
	-- the officer tools' records (`m`): by group, only the officer designated for the sender, and only when this client has
	-- seen the officer channel work (an OFFICER message just arrived, so it has; the check keeps the rule in one place)
	local pushGroups = {}
	local mine = Sync.DecodeSummary(msg.m)
	if mine and proven() then
		for name, g in pairs(Sync:Groups("officer")) do
			if ahead(g, mine[g.key]) then
				if isDesignated == nil then isDesignated = designated(target) end
				if isDesignated then pushGroups[name] = true end
			end
		end
	end
	if not next(pushAuthors) and not next(pushGroups) then return end
	local key = "O|" .. sender
	local entry = state.push[key]
	if not entry then
		entry = { authors = {}, groups = {} }
		state.push[key] = entry
		entry.timer = after(between(Sync.PUSH_DELAY), function()
			state.push[key] = nil
			local records = recordsOf(entry.authors, true)
			if proven() then
				for _, e in ipairs(recordsOf(entry.groups, "officer")) do records[#records + 1] = e end
			end
			local n = sendRecords(records, "WHISPER", sender)
			if n > 0 then state.stats.pushes = state.stats.pushes + 1 end
		end)
	end
	for a in pairs(pushAuthors) do entry.authors[a] = true end
	for name in pairs(pushGroups) do entry.groups[name] = true end
end

-- true while `sender` has not used up its share of set requests (ASK_RATE).
local function withinAskRate(sender)
	local t = now()
	local w = state.answering[sender]
	if not w or t - w.start >= Sync.ASK_RATE[2] then
		w = { start = t, count = 0 }
		state.answering[sender] = w
	end
	w.count = w.count + 1
	return w.count <= Sync.ASK_RATE[1]
end

local function onReq(msg, sender)
	if type(msg.a) ~= "table" then return end
	local member = touch(sender)
	if not member then return end
	local S, me = store(), myGUID()
	local single = msg.s ~= "*" and S.SETS[msg.s] and msg.s or nil
	if single and not withinAskRate(sender) then
		state.stats.asksLimited = state.stats.asksLimited + 1
		return
	end
	if not single and not within("reqall", sender, Sync.REQ_ALL_RATE) then   -- SPEC-11 §6.3
		state.stats.flood = state.stats.flood + 1
		return
	end
	local groups = Sync:Groups()
	local byKey = {}
	for author, g in pairs(groups) do byKey[g.key] = author end
	local officer = iAmOfficer()
	local count = 0
	for i, key in ipairs(msg.a) do
		if i > (single and 20 or 500) then break end
		local author = type(key) == "number" and byKey[key]
		if author and (officer or (me and S:SameAccount(me, author))) then
			local entries = {}
			for _, e in ipairs(groups[author].records) do
				if not single or e[1] == single then entries[#entries + 1] = e end
			end
			if single then
				-- a request for one set came from a view that needs it now: the answer goes to that client only
				if #entries > 0 then count = count + sendRecords(entries, "WHISPER", sender) end
			else
				count = count + sendRecords(entries, "GUILD", nil, "REC|" .. key)
			end
		end
	end
	if count > 0 then
		if single then state.stats.asksAnswered = state.stats.asksAnswered + 1
		else state.stats.answers = state.stats.answers + 1 end
	end
end

local function onRec(msg, sender, dist)
	touch(sender)
	local S = store()
	if not S.SETS[msg.s] then return end
	if type(msg.r) ~= "table" or count(msg.r) > Sync.MAX_REC then   -- dropped whole (SPEC-11 §6.1, `count`)
		state.stats.oversized = state.stats.oversized + 1
		state.stats.refused = state.stats.refused + 1
		refusedBy(sender, 1)
		return
	end
	if dist == "GUILD" and S.IsOfficerTool(msg.s) then   -- never travels there (OFF-04): dropped, not counted against the sender
		state.stats.officerGuild = (state.stats.officerGuild or 0) + 1
		return
	end
	local accepted, refused = S:Receive(msg.s, msg.r, sender, dist)
	state.stats.recReceived = state.stats.recReceived + 1
	state.stats.accepted = state.stats.accepted + accepted
	state.stats.refused = state.stats.refused + refused
	refusedBy(sender, refused)
	if accepted > 0 then
		state.lastReceived = compat().ServerTime()
		emit("SYNC_RECEIVED", msg.s, accepted)
	end
end

function Sync:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" then return end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return end
	if msg.t == "HELLO" and dist == "GUILD" then onHello(msg, sender)
	elseif msg.t == "BHELLO" and dist == "GUILD" then onBlockHello(msg, sender)
	elseif msg.t == "REQ" and dist == "WHISPER" then onReq(msg, sender)
	elseif msg.t == "REC" then onRec(msg, sender, dist)
	elseif msg.t == "OHELLO" and dist == "OFFICER" then onOfficerHello(msg, sender)
	elseif msg.t == "DIGEST" and dist == "WHISPER" then onDigest(msg, sender) end
end

---------------------------------------------------------------------------------------------------------------------
-- Local changes
---------------------------------------------------------------------------------------------------------------------
local flushLocal
flushLocal = function()
	state.batchTimer = nil
	local S, entries = store(), {}
	for set, ids in pairs(state.dirty) do
		for id in pairs(ids) do
			local rec = S:Get(set, id)
			if rec then entries[#entries + 1] = { set, rec } end
		end
	end
	state.dirty = {}
	-- the records for officers only never go on GUILD: they go on OFFICER (and nowhere when nobody can hear them)
	local open, closed, tools, wait = {}, {}, {}, nil
	for _, e in ipairs(entries) do
		if S.IsOfficerTool(e[1]) then
			-- OFF-07: before the channel is proven the record stays here (it reaches the others with the summary `m`, OFF-09);
			-- a set that grows at every event goes out at most every `publishEvery` seconds (TL: 10 minutes)
			if proven() and iAmOfficer() then
				local every, last = S.SETS[e[1]].publishEvery, state.officerSent[e[1]]
				local t = now()
				if every and last and t - last < every then
					local ids = state.dirty[e[1]]
					if not ids then ids = {} state.dirty[e[1]] = ids end
					ids[e[2].id] = true
					wait = max(wait or 0, every - (t - last))
				else
					tools[#tools + 1] = e
				end
			end
		elseif S.IsRestricted(e[1], e[2]) then closed[#closed + 1] = e else open[#open + 1] = e end
	end
	if #open > 0 then sendRecords(open, "GUILD") end
	if #closed > 0 and iAmOfficer() then sendRecords(closed, "OFFICER") end
	if #tools > 0 then
		for _, e in ipairs(tools) do state.officerSent[e[1]] = now() end
		sendRecords(tools, "OFFICER")
	end
	if wait and not state.toolTimer then   -- its own timer: the other sets' changes keep their 5-second batch
		state.toolTimer = after(wait + 0.05, function()
			state.toolTimer = nil
			flushLocal()
		end)
	end
end

function Sync:OnStoreChanged(set, id, origin)
	state.version = state.version + 1
	if id == nil or not store().SETS[set] or state.pendingCount >= 500 then   -- many at once: read all again
		state.rebuild = true
	else
		local k = ownerKey(set, id)
		if not state.pending[k] then
			state.pending[k] = { set, id }
			state.pendingCount = state.pendingCount + 1
		end
	end
	if origin ~= "local" then return end
	local ids = state.dirty[set]
	if not ids then ids = {} state.dirty[set] = ids end
	ids[id] = true
	if not state.batchTimer then state.batchTimer = after(Sync.BATCH, flushLocal) end
end

function Sync:OnGuildChanged(key)
	resetState()
	if key then Sync:Start() end
end

-- Asks for one author's records of one set because a view needs them (the recipes of a member). Returns "sent" and the
-- name asked, "own" (the author is this player's own account: nothing to ask), "recent" (asked within ASK_COOLDOWN),
-- "nobody" (no peer that may deliver them is online and known: nothing is sent and nothing is remembered, so the next
-- call tries again), "blocked" (the transport refused), "guild" or "invalid".
function Sync:RequestSet(set, author)
	if not (ns.GuildKey and ns.GuildKey:Current()) then return "guild" end
	local S = store()
	if not S.SETS[set] or type(author) ~= "string" or author == "" then return "invalid" end
	local me = myGUID()
	if me and (author == me or S:SameAccount(me, author)) then return "own" end
	local key = set .. "|" .. author
	local t = now()
	local last = state.asked[key]
	if last and t - last < Sync.ASK_COOLDOWN then return "recent" end
	local own, officers = {}, {}
	for name, p in pairs(presentPeers()) do
		if p.guid == author or S:SameAccount(p.guid, author) then own[#own + 1] = name
		elseif p.officer then officers[#officers + 1] = { name = name, rank = hash().Fast((p.guid or "") .. (me or "")) } end
	end
	local targets = {}
	if #own > 0 then
		sort(own)
		targets[1] = own[1]
	else
		sort(officers, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.name < b.name end)
		for i = 1, min(Sync.ASK_OFFICERS, #officers) do targets[i] = officers[i].name end
	end
	if #targets == 0 then return "nobody" end
	local sentTo
	for _, name in ipairs(targets) do
		if send("WHISPER", { t = "REQ", s = set, a = { Sync.KeyOf(author) } }, { target = name, key = "ASK|" .. key .. "|" .. name }) then
			sentTo = sentTo or name
		end
	end
	if not sentTo then return "blocked" end
	state.asked[key] = t
	state.stats.asks = state.stats.asks + 1
	return "sent", sentTo
end

-- The guildmates with the addon heard recently and still online in the roster: name -> { guid, officer }. A copy, for
-- the modules that pick one of them (the notary of the likes, Data/Notary.lua).
function Sync:Peers()
	local out = {}
	for name, p in pairs(presentPeers()) do out[name] = { guid = p.guid, officer = p.officer } end
	return out
end

-- For the top bar of the panel: how many guildmates with the addon are online, when records last arrived.
function Sync:Status()
	local n = 0
	for _ in pairs(presentPeers()) do n = n + 1 end
	return { peers = n, lastReceived = state.lastReceived }
end

---------------------------------------------------------------------------------------------------------------------
-- /accord debug
---------------------------------------------------------------------------------------------------------------------
function Sync:DebugLines()
	local s = state.stats
	local peers, officers = 0, 0
	for _, p in pairs(presentPeers()) do
		peers = peers + 1
		if p.officer then officers = officers + 1 end
	end
	local authors = 0
	if ns.GuildKey and ns.GuildKey:Current() then for _ in pairs(self:Groups()) do authors = authors + 1 end end
	return {
		("Sync: %s, %d author(s) known, %d peer(s) with the addon heard recently (%d officer(s))"):format(
			self.AUTO and "automatic" or "manual", authors, peers, officers),
		("  HELLO sent %d, heard %d; pushes %d, requests %d, answers %d; REC sent %d, received %d (accepted %d, refused %d)"):format(
			s.hellosSent, s.hellosHeard, s.pushes, s.requests, s.answers, s.recSent, s.recReceived, s.accepted, s.refused),
		("  set requests: asked %d, answered %d, over the rate limit %d"):format(s.asks, s.asksAnswered, s.asksLimited),
		("  block summaries: BHELLO sent %d, heard %d; DIGEST sent %d, heard %d"):format(s.bhellosSent, s.bhellosHeard,
			s.digestsSent, s.digestsHeard),
		("  limits: ignored for flooding %d, oversized REC %d, senders put in quarantine %d"):format(s.flood, s.oversized,
			s.quarantined),
	}
end

if ns.addon then
	ns.addon.Sync = Sync
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Sync", function() return Sync:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("NET_MESSAGE", function(msg, sender, dist) Sync:OnMessage(msg, sender, dist) end)
		ns.Bus:On("STORE_CHANGED", function(set, id, origin) Sync:OnStoreChanged(set, id, origin) end)
		ns.Bus:On("GUILD_CHANGED", function(key) Sync:OnGuildChanged(key) end)
		-- many records changed at once, or the store was swapped: the summary is read whole again
		ns.Bus:On("DEMO_CHANGED", function() Sync:Invalidate() end)
		ns.Bus:On("BACKUP_IMPORTED", function() Sync:Invalidate() end)
		ns.Bus:On("SETTINGS_CHANGED", function(key) if key == "clear" then Sync:Invalidate() end end)
	end
	if ns.OnEnable then
		ns.OnEnable(function() if ns.GuildKey and ns.GuildKey:Current() then Sync:Start() end end)
	end
end

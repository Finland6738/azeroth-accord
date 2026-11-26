-- The network simulator (M1.7): N complete addon instances in one guild, connected by GUILD, OFFICER and WHISPER
-- routing, on one shared clock. Loaded by Tests/lib/harness.lua; test files see it as the global `Sim`.
-- Adapted from Azeroth Guild Finder (Tests/sim/sim.lua), same owner, GPL-3.0 (ADR 0018): the public channel is gone,
-- every client shares one guild roster, and clients log out and in for real (SavedVariables written and read back).
--
-- Every client is a full copy of the game as the harness builds it (H.newWorld): its own game environment, mock client
-- (clock, timers, chat, guild, SavedVariables) and copy of the addon, so a client knows nothing about the others
-- except what arrives as CHAT_MSG_ADDON. A Lua error in any client fails the test.
--
--   local sim = Sim.new{ clients = 10, officers = { 1, 2 }, latency = { 0.05, 0.3 }, loss = 0.02, seed = 7 }
--   local a = sim:client(1)
--   sim:advance(60)                    -- seconds of simulated time; every online client runs frame by frame
--   a:logout(); sim:advance(600); a:login()
--   local st = sim:stats()             -- messages and bytes sent per client and per minute
--
-- Sim.new options (all optional):
--   clients   number of clients (default 2); client i is the character Sim.nameOf(i) with GUID Sim.guidOf(i)
--   officers  list of client indexes that are officers (rank 1); index 1 is also accepted as { 1 } (default: none)
--   latency   seconds a message takes: a number, or { min, max } drawn per delivery (default 0.1)
--   loss      probability that one delivery is lost (0..1), or function(from, to, entry) -> true (default 0)
--   seed      seed of the simulator and of math.random inside the clients (default 1)
--   step      length of a frame in seconds (default 0.1); bigger is faster and coarser
--   echo      the sender also receives its own GUILD / OFFICER message, as the client does (default true)
--   offline   list of client indexes that start logged out (they never ran: no SavedVariables)
--   names     list of character names by client index (default Sim.nameOf(i)); a Forever full name may have a space
--   lean      clients load only the libraries, Core, the guild key and the network layer (Sim.lean): a guild of a
--             thousand clients fits in memory (the 1000-login scenario of SPEC-11 §6.5)
--   sync      the guild sync starts by itself after login, as in the game (default true)
--   accounts  every client registers itself and publishes its own `accounts` record after login, as in the game (default
--             false: tests that write their own records keep exact control of the store)
--   contacts  the same for the `contacts` record (BattleTag and Discord), default false
--   coplay    the one-minute co-play recording and its hourly publication (Data/CoPlay.lua), default false
--   availability  the one-minute count of the time online and its publication (Data/Availability.lua), default false
--   rallies       the question for the open rallies after a login (Data/Rallies.lua), default false
--   notary    officers ask for and share the guild salt of the likes after login (Data/Notary.lua), default false
--   timeline  officers observe the roster and write the timeline by themselves (Data/Timeline.lua), default false
--   likes     waiting votes are delivered to a notary every 15 s (Data/Likes.lua), and every client starts with its own
--             account token (the same clock would give them all the same one), default false
--   officerChannel  false: OFFICER addon messages reach nobody, not even the sender's echo (S5 failing); default true
--   setup     function(Mock, i, client) called after the mock client is built, before the addon loads
--   loginWithin  seconds: every client logs in (boots) for the first time at a random moment of this window instead of
--             at once; the roster shows everyone online from the start (a restart of the server: they are all coming)
--   ready     function(client) called right after a client's first login (its addon is running, before any frame)
--   skip      function(from, to, type) -> true to leave out the delivery of a message of that type (a scenario that
--             proves the receiver would do nothing with it may spare the simulator the work); counted in sim.skipped
-- Time starts at 0 when the clients exist; sim:resetStats() starts a fresh measurement.
local H, T = ...

local Sim = {}
Sim.__index = Sim
local Client = {}
Client.__index = Client

local DISTS = { "WHISPER", "GUILD", "OFFICER" }
local GUILD_NAME = "Sim Guild"

local function letters(i)
	local out = ""
	i = i - 1
	repeat
		out = string.char(97 + i % 26) .. out
		i = math.floor(i / 26) - 1
	until i < 0
	return out
end

local function newCounters()
	local c = {}
	for _, d in ipairs(DISTS) do c[d] = { msgs = 0, bytes = 0 } end
	return c
end

function Sim.nameOf(i) return "Sim" .. letters(i) end
-- The character name of client i in this simulation (the option `names`, else Sim.nameOf).
function Sim:charName(i) return (self.names and self.names[i]) or Sim.nameOf(i) end
function Sim.guidOf(i) return ("Player-1-%08X"):format(0xA000 + i) end

---------------------------------------------------------------------------------------------------------------------
-- Clients
---------------------------------------------------------------------------------------------------------------------
function Client:fullName() return self.name .. "-" .. self.realmKey end
function Client:slash(line) return self.Mock.Slash(line) end
function Client:output() return self.Mock.PlainOutput() end
function Client:addon() return self.E.AzerothAccord end
function Client:guid() return Sim.guidOf(self.index) end

-- Restrictions of this client's sending (each field a boolean; left out = unchanged): lockdown (chat messaging
-- lockdown) and restricted (outgoing addon messages restricted). It still receives everything.
function Client:restrict(r)
	local chat = self.Mock.chat
	if r.lockdown ~= nil then chat.lockdown = r.lockdown end
	if r.restricted ~= nil then chat.restricted = r.restricted end
end

-- Every other client's roster shows this character online or offline (GUILD_ROSTER_UPDATE in each).
local function setRosterOnline(sim, who, online)
	for _, c in ipairs(sim.clients) do
		if c ~= who then
			for _, m in ipairs(c.Mock.guild.members) do
				if m.name == who.name then m.online = online end
			end
			if c.online then c.Mock.Fire("GUILD_ROSTER_UPDATE") end
		end
	end
end

-- Logs out: PLAYER_LOGOUT, the SavedVariables are written; the client stops running and receives nothing.
function Client:logout()
	if not self.online then return end
	self.saved = self.world.logout()
	self.online = false
	setRosterOnline(self.sim, self, false)
end

-- Logs in again: the client is rebuilt with the SavedVariables it wrote (the world keeps the player, guild and chat),
-- its clocks first catch up with the time it spent logged out.
function Client:login()
	if self.online then return end
	local sim = self.sim
	self.Mock.SetTime(1000 + sim.time)
	self.Mock.SetServerTime(sim.epoch + math.floor(sim.time))
	self.world.boot({ carry = true, saved = self.saved or {}, isReload = false })
	self.cursor = #self.Mock.chat.sent
	self.online = true
	setRosterOnline(sim, self, true)
end

function Client:stats()
	local sim = self.sim
	local minutes = math.max((sim.time - sim.statsFrom) / 60, 1e-9)
	local sent, recv = { msgs = 0, bytes = 0 }, { msgs = 0, bytes = 0 }
	for _, d in ipairs(DISTS) do
		sent.msgs, sent.bytes = sent.msgs + self.sent[d].msgs, sent.bytes + self.sent[d].bytes
		recv.msgs, recv.bytes = recv.msgs + self.recv[d].msgs, recv.bytes + self.recv[d].bytes
	end
	return {
		sent = sent, received = recv, byDist = self.sent, receivedByDist = self.recv,
		msgsPerMinute = sent.msgs / minutes, bytesPerMinute = sent.bytes / minutes,
		receivedBytesPerMinute = recv.bytes / minutes,
	}
end

local function resetClientStats(c)
	c.sent, c.recv = newCounters(), newCounters()
end

---------------------------------------------------------------------------------------------------------------------
-- The network
---------------------------------------------------------------------------------------------------------------------
local function draw(sim)
	-- 31-bit linear congruential generator: deterministic and independent of math.random (the clients use that one)
	sim.rngState = (sim.rngState * 1103515245 + 12345) % 2147483648
	return sim.rngState / 2147483648
end
Sim.draw = draw

local function latencyOf(sim)
	local l = sim.latency
	if type(l) == "table" then return l[1] + (l[2] - l[1]) * draw(sim) end
	return l
end

local function lostDelivery(sim, from, to, entry)
	local loss = sim.loss
	if type(loss) == "function" then return loss(from, to, entry) and true or false end
	return loss > 0 and draw(sim) < loss
end

-- Messages from one client to another arrive in the order they were sent (the chunks of an AceComm multipart message
-- depend on it): a delivery is never due before the previous one of the same pair.
local function schedule(sim, to, entry, from)
	local due = sim.time + latencyOf(sim)
	local slot = math.max(math.ceil(due / sim.step - 1e-9), sim.slot + 1)
	local pair = from.index .. ">" .. to.index
	local previous = sim.lastSlot[pair]
	if previous and previous > slot then slot = previous end
	sim.lastSlot[pair] = slot
	local bucket = sim.inflight[slot]
	if not bucket then bucket = {} sim.inflight[slot] = bucket end
	bucket[#bucket + 1] = { to = to, from = from, entry = entry }
end

local function receivers(sim, from, entry)
	local out = {}
	local kind = entry.chatType
	if kind == "WHISPER" then
		local target = tostring(entry.target):lower():gsub("%-[^%-]*$", "")   -- the realm is after the last hyphen
		for _, c in ipairs(sim.clients) do
			if c ~= from and c.name:lower() == target then out[1] = c break end
		end
	elseif kind == "GUILD" or kind == "OFFICER" then
		for _, c in ipairs(sim.clients) do
			if (c ~= from or sim.echo) and (kind == "GUILD" or (sim.officer[c.index] and sim.officerChannel)) then out[#out + 1] = c end
		end
	end
	return out
end

-- The message type of a piece on the wire ("BHELLO", "REC", ...): read from the header of a whole message or of the
-- first piece of a multipart one, remembered per sender and distribution for the pieces that follow.
local function typeOf(sim, from, entry)
	local m = entry.message
	local first = m:byte(1)
	local key = from.index .. entry.chatType
	if first == 2 or first == 3 then return sim.pieceType[key] end
	local t = ((first == 1 or first == 4) and m:sub(2) or m):match("^%d+|(%u[%u%d]*)|")
	sim.pieceType[key] = t
	return t
end

local function route(sim, from, entry)
	local size = #entry.message + #entry.prefix
	local counters = from.sent[entry.chatType]
	if counters then counters.msgs, counters.bytes = counters.msgs + 1, counters.bytes + size end
	if not from.online then sim.lost = sim.lost + 1 return end
	local t = sim.skip and typeOf(sim, from, entry)
	for _, to in ipairs(receivers(sim, from, entry)) do
		if t and to ~= from and sim.skip(from, to, t) then
			sim.skipped = sim.skipped + 1
		elseif to ~= from and (not to.online or lostDelivery(sim, from, to, entry)) then
			sim.lost = sim.lost + 1
		else
			schedule(sim, to, entry, from)
		end
	end
end

local function deliver(sim, item)
	local to, entry = item.to, item.entry
	if not to.online then sim.lost = sim.lost + 1 return end
	local counters = to.recv[entry.chatType]
	if counters then counters.msgs, counters.bytes = counters.msgs + 1, counters.bytes + #entry.message + #entry.prefix end
	sim.delivered = sim.delivered + 1
	to.Mock.chat.Receive(entry.prefix, entry.message, entry.chatType, item.from:fullName(), "")
end

-- One frame: deliver what is due, let every online client run a frame, route what they sent. Logged-out clients only
-- see their clocks move.
local function frame(sim)
	sim.slot = sim.slot + 1
	sim.time = sim.slot * sim.step
	local due = sim.inflight[sim.slot]
	if due then
		sim.inflight[sim.slot] = nil
		for _, item in ipairs(due) do deliver(sim, item) end
	end
	if sim.pendingLogins then
		local rest = {}
		for _, c in ipairs(sim.pendingLogins) do
			if c.loginAt <= sim.time then c:firstLogin() else rest[#rest + 1] = c end
		end
		sim.pendingLogins = #rest > 0 and rest or nil
	end
	for _, c in ipairs(sim.clients) do
		if c.online then
			c.Mock.Advance(sim.step, sim.step)
			local sent = c.Mock.chat.sent
			for i = c.cursor + 1, #sent do route(sim, c, sent[i]) end
			c.cursor = #sent
		elseif not c.boot then   -- a client that never logged in yet has no clock
			c.Mock.StepClock(sim.step)
		end
	end
end

function Sim:advance(seconds)
	local target = self.slot + math.floor(seconds / self.step + 0.5)
	while self.slot < target do frame(self) end
end

-- Runs until fn() is true (checked every frame), at most `limit` seconds. Returns true when it became true, and the
-- simulated seconds that passed.
function Sim:advanceUntil(fn, limit)
	local start, target = self.time, self.slot + math.floor((limit or 60) / self.step + 0.5)
	while self.slot < target do
		if fn() then return true, self.time - start end
		frame(self)
	end
	return fn() and true or false, self.time - start
end

-- Changes the frame length between two advance calls (what is in flight keeps its due time).
function Sim:setStep(step)
	local old, slots, inflight = self.step, {}, {}
	for slot in pairs(self.inflight) do slots[#slots + 1] = slot end
	table.sort(slots)
	self.slot = math.floor(self.time / step + 1e-9)
	self.time = self.slot * step
	for _, slot in ipairs(slots) do
		local to = math.max(math.ceil(slot * old / step - 1e-9), self.slot + 1)
		local bucket = inflight[to]
		if not bucket then bucket = {} inflight[to] = bucket end
		for _, item in ipairs(self.inflight[slot]) do bucket[#bucket + 1] = item end
	end
	self.inflight, self.lastSlot, self.step = inflight, {}, step
end

function Sim:client(i) return self.clients[i] end
function Sim:count() return #self.clients end
function Sim:setLoss(loss) self.loss = loss end

function Sim:resetStats()
	self.statsFrom, self.delivered, self.lost = self.time, 0, 0
	for _, c in ipairs(self.clients) do resetClientStats(c) end
end

-- { elapsed, delivered, lost, sent = { msgs, bytes }, perClient, avg = { msgsPerMinute, bytesPerMinute },
--   max = { msgsPerMinute, bytesPerMinute, receivedBytesPerMinute } } since the start or the last resetStats().
function Sim:stats()
	local out = {
		elapsed = self.time - self.statsFrom, delivered = self.delivered, lost = self.lost,
		sent = { msgs = 0, bytes = 0 }, byDist = newCounters(), perClient = {},
		avg = { msgsPerMinute = 0, bytesPerMinute = 0 }, max = { msgsPerMinute = 0, bytesPerMinute = 0, receivedBytesPerMinute = 0 },
	}
	for i, c in ipairs(self.clients) do
		local s = c:stats()
		out.perClient[i] = s
		out.sent.msgs, out.sent.bytes = out.sent.msgs + s.sent.msgs, out.sent.bytes + s.sent.bytes
		for _, d in ipairs(DISTS) do
			out.byDist[d].msgs, out.byDist[d].bytes = out.byDist[d].msgs + c.sent[d].msgs, out.byDist[d].bytes + c.sent[d].bytes
		end
		out.avg.msgsPerMinute, out.avg.bytesPerMinute = out.avg.msgsPerMinute + s.msgsPerMinute, out.avg.bytesPerMinute + s.bytesPerMinute
		out.max.msgsPerMinute = math.max(out.max.msgsPerMinute, s.msgsPerMinute)
		out.max.bytesPerMinute = math.max(out.max.bytesPerMinute, s.bytesPerMinute)
		out.max.receivedBytesPerMinute = math.max(out.max.receivedBytesPerMinute, s.receivedBytesPerMinute)
	end
	local n = math.max(#self.clients, 1)
	out.avg.msgsPerMinute, out.avg.bytesPerMinute = out.avg.msgsPerMinute / n, out.avg.bytesPerMinute / n
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------------------------------
local function rosterFor(sim, i)
	local members = {}
	for j = 1, sim.size do
		if j ~= i then
			members[#members + 1] = { name = sim:charName(j), guid = Sim.guidOf(j), rank = sim.officer[j] and 1 or 3 }
		end
	end
	return members
end

-- Lean clients: one row per member in the mock's own shape, shared by every client's roster (a list of references
-- without the client itself), so a thousand rosters of a thousand members do not take a million tables.
local function sharedRowsFor(sim, i)
	if not sim.rows then
		sim.rows = {}
		for j = 1, sim.size do
			sim.rows[j] = { name = sim:charName(j), level = 60, class = "WARRIOR", rank = sim.officer[j] and 1 or 3, online = true,
				zone = "Orgrimmar", note = "", officerNote = "", guid = Sim.guidOf(j) }
		end
	end
	local list = {}
	for j = 1, sim.size do if j ~= i then list[#list + 1] = sim.rows[j] end end
	return list
end

-- The files a lean client loads (Sim.new option `lean`): the libraries, Core, the guild key and the network layer.
local LEAN = { "^AzerothAccord/Libs/", "^AzerothAccord/Locale/", "^AzerothAccord/Core/[^D]", "^AzerothAccord/Core/Diagnostics%.lua$",
	"^AzerothAccord/Data/GuildKey%.lua$", "^AzerothAccord/Net/" }
function Sim.lean(name)
	for _, pattern in ipairs(LEAN) do if name:find(pattern) then return true end end
	return false
end

-- A client of `loginWithin` logs in for the first time: the world boots with its clocks at the simulator's time.
function Client:firstLogin()
	local sim = self.sim
	self.boot()
	self.boot = nil
	self.cursor = #self.Mock.chat.sent
	self.online = true
	if sim.ready then sim.ready(self) end
end

-- Lean clients share the results of the mock's pure decoding functions (the same text reaches a thousand clients: it
-- is decoded once). A decoded CBOR table is copied for each caller, because the codec writes into it.
local function copyDeep(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = copyDeep(x) end
	return out
end

local function shareDecoding(sim, E)
	local enc = E.C_EncodingUtil
	if not enc then return end
	local memo = sim.memo
	local function wrap(name, copy)
		local original = enc[name]
		local cache = memo[name] or {}
		memo[name] = cache
		enc[name] = function(source, extra)
			if type(source) ~= "string" or extra ~= nil and name ~= "DecompressString" then return original(source, extra) end
			local hit = cache[source]
			if hit == nil then
				local ok, value = pcall(original, source, extra)
				if not ok then error(value, 2) end
				if memo.size > 20000 then for _, c in pairs(memo) do if type(c) == "table" then for k in pairs(c) do c[k] = nil end end end memo.size = 0 end
				cache[source], memo.size = value, memo.size + 1
				hit = value
			end
			if copy then return copyDeep(hit) end
			return hit
		end
	end
	wrap("DecodeBase64", false)
	wrap("DecompressString", false)
	wrap("DeserializeCBOR", true)
end

local function bootClient(sim, i, opts)
	local world = H.newWorld(sim.lean and { only = Sim.lean } or nil)
	H.worlds[#H.worlds + 1] = world
	world.autoSync = sim.sync
	world.autoAccounts = sim.accounts
	world.autoContacts = sim.contacts
	world.autoCoPlay = sim.coplay
	world.autoAvailability = sim.availability
	world.autoRallies = sim.rallies
	world.autoNotary = sim.notary
	world.autoLikes = sim.likes
	world.autoTimeline = sim.timeline
	local c = setmetatable({
		sim = sim, index = i, world = world, E = world.E, Mock = world.Mock, name = sim:charName(i), realmKey = sim.realmKey,
		online = true, cursor = 0,
	}, Client)
	resetClientStats(c)
	local deferred = opts.loginWithin ~= nil
	local boot = function() world.boot{ setups = { function(Mock)
		Mock.player.name = c.name
		Mock.player.realm = sim.realm
		Mock.player.guid = Sim.guidOf(i)
		if deferred then Mock.SetTime(1000 + sim.time) end
		Mock.SetServerTime(sim.epoch + math.floor(sim.time))
		-- every client would draw the same account token (the same clock, the same seed): real accounts never do, and
		-- the likes' pseudonyms are made from it, so with `likes` each client starts with its own
		if sim.likes then world.E.AzerothAccordDB = { token = ("SimTokenClient%010d"):format(i) } end
		Mock.guild.Set{ name = GUILD_NAME, myRank = sim.officer[i] and 1 or 3, officerRanks = 1, members = not sim.lean and rosterFor(sim, i) or nil,
			rows = sim.lean and sharedRowsFor(sim, i) or nil }
		if opts.setup then opts.setup(Mock, i, c) end
		if sim.lean then shareDecoding(sim, world.E) end
	end } } end
	if deferred then
		c.boot, c.online = boot, false
		c.loginAt = draw(sim) * opts.loginWithin
	else
		boot()
	end
	return c
end

function Sim.new(opts)
	opts = opts or {}
	local sim = setmetatable({
		time = 0, slot = 0, step = opts.step or 0.1, latency = opts.latency or 0.1, loss = opts.loss or 0,
		echo = opts.echo ~= false, realm = opts.realm or "Test Realm", clients = {}, inflight = {}, lastSlot = {},
		rngState = (opts.seed or 1) % 2147483648, statsFrom = 0, delivered = 0, lost = 0, sync = opts.sync ~= false, accounts = opts.accounts == true, contacts = opts.contacts == true, coplay = opts.coplay == true, availability = opts.availability == true, rallies = opts.rallies == true,
		notary = opts.notary == true, timeline = opts.timeline == true, lean = opts.lean == true, names = opts.names, likes = opts.likes == true, officerChannel = opts.officerChannel ~= false,
		officer = {}, size = opts.clients or 2, epoch = 1767225600, ready = opts.ready, memo = { size = 0 },
		skip = opts.skip, skipped = 0, pieceType = {},
	}, Sim)
	for _, i in ipairs(opts.officers or {}) do sim.officer[i] = true end
	sim.realmKey = sim.realm:gsub("[%s%-']", "")
	math.randomseed(opts.seed or 1)
	for i = 1, sim.size do sim.clients[i] = bootClient(sim, i, opts) end
	if opts.loginWithin then
		sim.pendingLogins = {}
		for _, c in ipairs(sim.clients) do sim.pendingLogins[#sim.pendingLogins + 1] = c end
	end
	for _, i in ipairs(opts.offline or {}) do
		local c = sim.clients[i]
		c.saved = {}
		c.online = false
		setRosterOnline(sim, c, false)
	end
	sim:resetStats()
	return sim
end

return Sim

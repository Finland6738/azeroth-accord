-- Recipes: the recipe lists of guild members (SPEC-06, ADR 0010: native first, shared as the fallback). Lua 5.1.
--
-- Two sources sit behind this module and the views ask only here:
--
--   native   the game's guild recipe directory: C_GuildInfo.QueryGuildMemberRecipes(guid, skillLine) asks the server,
--            GUILD_RECIPE_KNOWN_BY_MEMBERS says the answer is ready, GetGuildMemberRecipes() reads it. It covers every
--            member, also those without the addon. [verify S3] The probe results (M0.4) are not in yet, so this source
--            sits behind a capability check (`guildRecipesNative`: IsGuildTradeSkillsEnabled and the three functions)
--            and the shared lists (M3.2 / M3.3) are a complete fallback that works on its own; M0.4 will confirm which
--            one is the main source.
--   shared   what the members' addons publish (the `recipes` records): see M3.2 / M3.3.
--
-- The native source answers one member and one profession per query and the event carries no payload, so queries go
-- one at a time: a queue (at most NATIVE_QUEUE jobs, no duplicates), at least NATIVE_GAP seconds between two queries
-- (the server throttles guild queries), an answer that does not come within NATIVE_TIMEOUT seconds is dropped, and after
-- NATIVE_MAX_TIMEOUTS unanswered queries in a row the source rests for NATIVE_REST seconds. An answer is kept in
-- memory for NATIVE_TTL seconds (a view that asks again inside that time costs nothing); it is never saved to disk.
--
-- GetGuildMemberRecipes has no signature in the API dump. What is read here: the first value is the skill line, then a
-- list of spell ids (or a set { [id] = true }). A bitfield string is recognised but not decoded: that answer turns the
-- native source off ("missing", with the reason) and the shared lists carry on alone.
--
-- Bus: RECIPES_UPDATED(guid, skillLine, source) when a list arrives ("native", "shared", or "own" for the player's own scan).
local ADDON_NAME, ns = ...
ns = ns or {}
local Recipes = {}
ns.Recipes, ns.modules = Recipes, ns.modules or {}
ns.modules.Recipes = Recipes

local type, pairs, ipairs, tostring, tonumber, select, floor = type, pairs, ipairs, tostring, tonumber, select, math.floor
local sort = table.sort

Recipes.NATIVE_GAP = 2            -- seconds between two native queries
Recipes.NATIVE_TIMEOUT = 8        -- seconds a query waits for its answer
Recipes.NATIVE_TTL = 900          -- seconds an answer stays fresh
Recipes.NATIVE_QUEUE = 20         -- jobs waiting at most
Recipes.NATIVE_MAX_TIMEOUTS = 5   -- unanswered queries in a row before the source rests
Recipes.NATIVE_REST = 600         -- seconds of rest
Recipes.NATIVE_UNUSABLE_MAX = 2   -- answers in a shape that cannot be read before the source is switched off
Recipes.CACHE_MAX = 300           -- native answers kept in memory
Recipes.MAX_IDS = 3000            -- recipes per profession accepted from any source
Recipes.MAX_SPELL_ID = 2147483647

Recipes.EVENT = "GUILD_RECIPE_KNOWN_BY_MEMBERS"

-- The secondary professions: they have recipes (cooking is the one guilds ask for) but are not one of the two
-- primary professions the roster shows in a member's profession cells. Skill line ids of the client.
Recipes.SECONDARY = { [129] = true, [185] = true, [356] = true, [794] = true }   -- First Aid, Cooking, Fishing, Archaeology
function Recipes.IsPrimary(skillLine) return type(skillLine) == "number" and not Recipes.SECONDARY[skillLine] end

local native
local function resetNative(previous)
	native = {
		queue = {}, queued = {}, inflight = nil, lastSent = nil, pumping = false,
		cache = {}, count = 0, timeouts = 0, unusable = 0, restUntil = nil, epoch = ((previous and previous.epoch) or 0) + 1, seq = 0,
		stats = { queries = 0, answers = 0, timeouts = 0, unusable = 0, stale = 0, failed = 0, cached = 0, dropped = 0 },
	}
	Recipes.native = native
end
resetNative()

local function compat() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

-- The id of a record and the key of a cache entry: "<GUID>:<skill line>" (SPEC-03 §3).
function Recipes.Key(guid, skillLine)
	if type(guid) ~= "string" or guid == "" or type(skillLine) ~= "number" then return nil end
	return guid .. ":" .. floor(skillLine)
end

---------------------------------------------------------------------------------------------------------------------
-- Spell id lists
---------------------------------------------------------------------------------------------------------------------
-- A sorted list without duplicates of the valid spell ids in `list` (a list, or a set { [id] = true }); nil when it is
-- not a table. Anything that is not a whole number from 1 up is dropped; at most MAX_IDS are kept.
function Recipes.Normalize(list)
	if type(list) ~= "table" then return nil end
	local seen, out = {}, {}
	local function add(id)
		if type(id) == "number" and id == id and id >= 1 and id <= Recipes.MAX_SPELL_ID and id == floor(id) and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	for _, id in ipairs(list) do add(id) end
	if #out == 0 then
		for id, on in pairs(list) do if on == true then add(id) end end   -- a set
	end
	sort(out)
	while #out > Recipes.MAX_IDS do out[#out] = nil end
	return out
end

-- Reads the values GetGuildMemberRecipes gave (a table with `n`): returns skillLine, ids, or nil, nil and a reason
-- ("none", "bitfield", "shape").
function Recipes.ParseNative(values)
	if type(values) ~= "table" then return nil, nil, "none" end
	local n = values.n or #values
	if n == 0 then return nil, nil, "none" end
	local line = type(values[1]) == "number" and values[1] or nil
	local sawString = false
	for i = 1, n do
		local v = values[i]
		if type(v) == "table" then
			local ids = Recipes.Normalize(v)
			if ids then return line, ids end
		elseif type(v) == "string" and v ~= "" then
			sawString = true
		end
	end
	return line, nil, sawString and "bitfield" or "shape"
end

---------------------------------------------------------------------------------------------------------------------
-- The wire and saved form of a list (SPEC-03 §3): sorted spell ids as differences, each a varint (7 bits per byte, the
-- high bit says another byte follows), the bytes in Base64 so the text is plain ASCII in SavedVariables and in the
-- addon message. About 1.5 bytes per recipe before Base64 for a profession of a few hundred recipes.
---------------------------------------------------------------------------------------------------------------------
-- The Base64 text of a list of spell ids ("" for an empty list), or nil plus a reason ("nobase64").
function Recipes.Encode(ids)
	ids = Recipes.Normalize(ids)
	if not ids then return nil, "shape" end
	if #ids == 0 then return "" end
	local bytes, previous = {}, 0
	for _, id in ipairs(ids) do
		local delta = id - previous
		previous = id
		while delta >= 128 do
			bytes[#bytes + 1] = string.char(delta % 128 + 128)
			delta = floor(delta / 128)
		end
		bytes[#bytes + 1] = string.char(delta)
	end
	local C = compat()
	local text = C and C.Base64.Encode(table.concat(bytes))
	if not text then return nil, "nobase64" end
	return text
end

-- The list a text stands for, or nil plus a reason ("shape", "base64", "varint", "range", "count"). Never raises and
-- never trusts the text: it came from another client.
function Recipes.Decode(text)
	if type(text) ~= "string" or #text > 16384 then return nil, "shape" end
	if text == "" then return {} end
	if text:find("[^A-Za-z0-9+/=]") then return nil, "base64" end
	local C = compat()
	local raw = C and C.Base64.Decode(text)
	if type(raw) ~= "string" or raw == "" then return nil, "base64" end
	local ids, id, value, shift = {}, 0, 0, 0
	for i = 1, #raw do
		local b = raw:byte(i)
		value = value + (b % 128) * 2 ^ shift
		if b < 128 then
			if value < 1 then return nil, "range" end   -- a list has no repeated or unordered ids
			id = id + value
			if id > Recipes.MAX_SPELL_ID then return nil, "range" end
			if #ids >= Recipes.MAX_IDS then return nil, "count" end
			ids[#ids + 1] = id
			value, shift = 0, 0
		else
			shift = shift + 7
			if shift > 28 then return nil, "varint" end
		end
	end
	if shift ~= 0 then return nil, "varint" end   -- the last number was cut off
	return ids
end

-- The fingerprint of a published list: changes when the recipes or the skill rank change (PRO-06). A 32-bit fast hash,
-- like the sync digests: a collision can only delay a publication.
function Recipes.HashOf(skillLine, rank, maxRank, text)
	local H = ns.Hash
	if not H then return 0 end
	return H.Fast(("%s|%s|%s|%s"):format(tostring(skillLine), tostring(rank or 0), tostring(maxRank or 0), text or ""))
end

---------------------------------------------------------------------------------------------------------------------
-- The native source: capability, queue, answers
---------------------------------------------------------------------------------------------------------------------
-- true when the game's guild recipe directory can be asked now: the client says it is enabled and has the functions,
-- and the source is neither switched off by what it answered nor resting after unanswered queries.
function Recipes:NativeUsable()
	local C = compat()
	if not C then return false, "compat" end
	if native.off then return false, native.off end
	if native.restUntil and C.Now() < native.restUntil then return false, "rest" end
	local enabled = C.TradeSkill.GuildRecipesEnabled()
	local hasApi = type(C.Resolve("C_GuildInfo.QueryGuildMemberRecipes")) == "function"
		and type(C.Resolve("GetGuildMemberRecipes")) == "function"
	if enabled ~= true or not hasApi then
		if C:Feature("guildRecipesNative") ~= "missing" then
			C:SetFeature("guildRecipesNative", "missing", hasApi and "IsGuildTradeSkillsEnabled does not return true" or "API missing")
		end
		return false, hasApi and "disabled" or "api"
	end
	if C:Feature("guildRecipesNative") == "missing" then
		C:SetFeature("guildRecipesNative", "unknown", "enabled, no answer seen yet")
	end
	return true
end

local function pack(...) return { n = select("#", ...), ... } end

local function ownGUID() return compat() and compat().Player.GUID() end

local function evict()
	if native.count <= Recipes.CACHE_MAX then return end
	local oldestKey, oldest
	for key, e in pairs(native.cache) do
		if not oldest or e.at < oldest then oldestKey, oldest = key, e.at end
	end
	if oldestKey then
		native.cache[oldestKey] = nil
		native.count = native.count - 1
	end
end

local function store(job, ids)
	local C = compat()
	if native.cache[job.key] == nil then native.count = native.count + 1 end
	native.cache[job.key] = { ids = ids, time = C.ServerTime(), at = C.Now(), guid = job.guid, skillLine = job.skillLine }
	evict()
end

local pump

local function schedulePump(delay)
	if native.pumping then return end
	native.pumping = true
	local epoch = native.epoch
	local ok = compat().After(delay, function()
		if epoch ~= native.epoch then return end
		native.pumping = false
		pump()
	end)
	if not ok then native.pumping = false end
end

-- Sends the next job when nothing is in flight and the gap since the last query has passed.
pump = function()
	local C = compat()
	if not C or native.inflight or #native.queue == 0 then return end
	if not Recipes:NativeUsable() then
		native.stats.dropped = native.stats.dropped + #native.queue
		native.queue, native.queued = {}, {}
		return
	end
	local wait = native.lastSent and (native.lastSent + Recipes.NATIVE_GAP - C.Now()) or 0
	if wait > 0 then schedulePump(wait) return end
	local job = table.remove(native.queue, 1)
	native.queued[job.key] = nil
	native.seq = native.seq + 1
	job.seq = native.seq
	native.lastSent = C.Now()
	native.stats.queries = native.stats.queries + 1
	local state = C.TradeSkill.QueryGuildMemberRecipes(job.guid, job.skillLine)
	if state ~= C.AVAILABLE then
		native.stats.failed = native.stats.failed + 1
		schedulePump(Recipes.NATIVE_GAP)
		return
	end
	native.inflight = job
	local epoch, seq = native.epoch, job.seq
	C.After(Recipes.NATIVE_TIMEOUT, function()
		if epoch ~= native.epoch or not native.inflight or native.inflight.seq ~= seq then return end
		native.inflight = nil
		native.stats.timeouts = native.stats.timeouts + 1
		native.timeouts = native.timeouts + 1
		if native.timeouts >= Recipes.NATIVE_MAX_TIMEOUTS then
			native.restUntil = C.Now() + Recipes.NATIVE_REST
			native.timeouts = 0
			C:SetFeature("guildRecipesNative", C:Feature("guildRecipesNative") == "available" and "available" or "unknown",
				("no answer to %d queries in a row, resting"):format(Recipes.NATIVE_MAX_TIMEOUTS))
		end
		pump()
	end)
end

-- Asks the game for the recipes of `guid` in `skillLine`. Returns "queued", "pending" (already asked), "cached" (an
-- answer is fresh), "self" (the player's own lists come from the own scan), "full" (the queue is full), "invalid" or
-- "unavailable" (the native source cannot be used now; the shared list is the only one).
function Recipes:RequestNative(guid, skillLine)
	local key = Recipes.Key(guid, skillLine)
	if not key then return "invalid" end
	if guid == ownGUID() then return "self" end
	if not self:NativeUsable() then return "unavailable" end
	local e = native.cache[key]
	if e and compat().Now() - e.at < Recipes.NATIVE_TTL then
		native.stats.cached = native.stats.cached + 1
		return "cached"
	end
	if native.queued[key] or (native.inflight and native.inflight.key == key) then return "pending" end
	if #native.queue >= Recipes.NATIVE_QUEUE then return "full" end
	local job = { key = key, guid = guid, skillLine = floor(skillLine) }
	native.queue[#native.queue + 1] = job
	native.queued[key] = job
	pump()
	return "queued"
end

-- GUILD_RECIPE_KNOWN_BY_MEMBERS: the answer to the query in flight. An answer with nothing in flight (the game's own
-- window asked) or for another skill line is not ours and is ignored.
function Recipes:OnNativeAnswer()
	local C = compat()
	local job = native.inflight
	if not C or not job then return end
	local line, ids, why = Recipes.ParseNative(pack(C.TradeSkill.GuildMemberRecipes(job.guid, job.skillLine)))
	if line ~= nil and line ~= job.skillLine then
		native.stats.stale = native.stats.stale + 1
		return
	end
	native.inflight = nil
	native.timeouts = 0
	if ids then
		native.stats.answers = native.stats.answers + 1
		native.unusable = 0
		store(job, ids)
		C:SetFeature("guildRecipesNative", "available", "answers read")
		emit("RECIPES_UPDATED", job.guid, job.skillLine, "native")
	else
		native.stats.unusable = native.stats.unusable + 1
		native.unusable = native.unusable + 1
		if native.unusable >= Recipes.NATIVE_UNUSABLE_MAX then
			native.off = why == "bitfield" and "bitfield" or "shape"
			C:SetFeature("guildRecipesNative", "missing", why == "bitfield"
				and "answers are a bitfield this version cannot read" or "answers in a shape this version cannot read")
		end
	end
	pump()
end

-- The native answer for a member and profession, or nil: { ids, time (server time), source = "native", fresh }.
function Recipes:Native(guid, skillLine)
	local key = Recipes.Key(guid, skillLine)
	local e = key and native.cache[key]
	if not e then return nil end
	return { ids = e.ids, time = e.time, source = "native", skillLine = e.skillLine, guid = e.guid,
		fresh = compat().Now() - e.at < Recipes.NATIVE_TTL }
end

---------------------------------------------------------------------------------------------------------------------
-- The shared source: the `recipes` records the members' addons publish (M3.2 writes them, the sync carries them)
---------------------------------------------------------------------------------------------------------------------
local decoded = { map = {}, count = 0 }   -- record id -> { rev, time, ids }: a list is decoded once per revision
Recipes.DECODE_CACHE_MAX = 1500             -- decoded lists kept (a guild of 400 members with 2-3 professions each)

local function decodedList(rec)
	local e = decoded.map[rec.id]
	if e and e.rev == rec.rev and e.time == rec.time then return e.ids end
	local ids
	if type(rec.ids) == "string" then ids = Recipes.Decode(rec.ids)
	elseif type(rec.ids) == "table" then ids = Recipes.Normalize(rec.ids) end
	if not ids then return nil end
	if not e then
		if decoded.count >= Recipes.DECODE_CACHE_MAX then decoded.map, decoded.count = {}, 0 end
		decoded.count = decoded.count + 1
	end
	decoded.map[rec.id] = { rev = rec.rev, time = rec.time, ids = ids }
	return ids
end

local function recordOf(guid, skillLine)
	local key = Recipes.Key(guid, skillLine)
	local S = ns.Store
	local rec = key and S and S:Get("recipes", key)
	if type(rec) ~= "table" or rec.del == true then return nil end
	return rec
end

-- The shared list of a member and profession, or nil: { ids, time, rank, maxRank, name, n, source = "shared" }; the
-- player's own character reads its own scan and says source = "own".
function Recipes:Shared(guid, skillLine)
	local rec = recordOf(guid, skillLine)
	if not rec then return nil end
	local ids = decodedList(rec)
	if not ids then return nil end
	return { ids = ids, time = rec.time, rank = rec.rank, maxRank = rec.maxRank, name = rec.name, n = #ids, guid = guid, author = rec.author,
		skillLine = floor(skillLine), source = guid == ownGUID() and "own" or "shared" }
end

-- Every list known now, one per member and profession: the native answers first (they win, ADR 0010), then the shared
-- records; each { guid, skillLine, ids, source, time, rank, maxRank, name }. For the "who can craft" index.
function Recipes:AllLists()
	local out, seen, S, me = {}, {}, ns.Store, ownGUID()
	for key, e in pairs(native.cache) do
		local shared = recordOf(e.guid, e.skillLine)
		out[#out + 1] = { guid = e.guid, skillLine = e.skillLine, ids = e.ids, source = "native", time = e.time,
			rank = shared and shared.rank, maxRank = shared and shared.maxRank, name = shared and shared.name }
		seen[key] = true
	end
	if S then
		for id, rec in pairs(S:Records("recipes")) do
			if not seen[id] and type(rec) == "table" and rec.del ~= true and type(rec.char) == "string" and type(rec.skillLine) == "number" then
				local ids = decodedList(rec)
				if ids then
					out[#out + 1] = { guid = rec.char, skillLine = rec.skillLine, ids = ids, source = rec.char == me and "own" or "shared",
						time = rec.time, rank = rec.rank, maxRank = rec.maxRank, name = rec.name }
				end
			end
		end
	end
	return out
end

-- The professions a member has shared lists of: { { skillLine, name, rank, maxRank, time, n }, ... } by skill line.
function Recipes:ProfessionsOf(guid)
	local out, S = {}, ns.Store
	if type(guid) ~= "string" or not S then return out end
	for _, rec in pairs(S:Records("recipes")) do
		if type(rec) == "table" and rec.char == guid and type(rec.skillLine) == "number" and rec.del ~= true then
			out[#out + 1] = { skillLine = rec.skillLine, name = rec.name, rank = rec.rank, maxRank = rec.maxRank, time = rec.time,
				n = tonumber(rec.n) or 0 }
		end
	end
	table.sort(out, function(a, b) return a.skillLine < b.skillLine end)
	return out
end

-- The list the views show for a member and profession (ADR 0010: native first, shared fills the gaps): the game's
-- answer when there is one, else the member's shared list, else nil. The result is the source's own table plus
-- `sharedTime` (when the shared list was written, if there is one) so the view can say both ages.
function Recipes:Lookup(guid, skillLine)
	local shared = self:Shared(guid, skillLine)
	local own = shared and shared.source == "own"
	local nat = not own and self:Native(guid, skillLine) or nil
	if nat then
		nat.sharedTime = shared and shared.time or nil
		nat.rank, nat.maxRank, nat.name = shared and shared.rank, shared and shared.maxRank, shared and shared.name
		return nat
	end
	return shared
end

-- A view needs the list of a member's profession: asks every source that can give it and says what each one did.
-- Returns { native = <RequestNative status>, shared = "have" | <Sync:RequestSet status> }. A shared list that is
-- already here is "have" (and is not asked again before it is old); the native list is asked whenever it is not fresh.
Recipes.SHARED_REFRESH = 6 * 3600   -- a shared list older than this is asked for again when a view opens it
function Recipes:Ensure(guid, skillLine)
	local out = { native = self:RequestNative(guid, skillLine) }
	local shared = self:Shared(guid, skillLine)
	local C, Sync = compat(), ns.Sync
	if shared and shared.source ~= "own" and C and C.ServerTime() - (shared.time or 0) < Recipes.SHARED_REFRESH then
		out.shared = "have"
	elseif shared and shared.source == "own" then
		out.shared = "own"
	elseif guid == ownGUID() then
		out.shared = "own"
	elseif Sync then
		out.shared = Sync:RequestSet("recipes", guid)
	else
		out.shared = "nobody"
	end
	return out
end

-- Kept for callers of M3.1: makes sure the native list is being fetched when none is fresh.
function Recipes:Refresh(guid, skillLine)
	return self:RequestNative(guid, skillLine)
end

---------------------------------------------------------------------------------------------------------------------
-- Names, icons and links of recipes (a recipe id is a spell id)
---------------------------------------------------------------------------------------------------------------------
Recipes.NAME_CACHE_MAX = 6000
Recipes.LOAD_RETRY = 60             -- seconds before the client is asked again for a spell it has no data for
Recipes.LOAD_BURST = { 150, 5 }     -- at most 150 spell data requests per 5 seconds (a first search over every list)
local names = { map = {}, count = 0, asked = {}, missing = 0, windowStart = 0, windowCount = 0 }

-- { name, icon } of a recipe, cached; nil while the client has no data for it. The first miss asks the client to load
-- it (and once per LOAD_RETRY seconds after that); SPELL_DATA_LOAD_RESULT then emits RECIPE_NAMES_UPDATED.
function Recipes.SpellData(id)
	local e = names.map[id]
	if e then return e end
	local C = compat()
	if not C or type(id) ~= "number" then return nil end
	local info = C.Spell.Info(id)
	if info then
		if names.count >= Recipes.NAME_CACHE_MAX then names.map, names.count = {}, 0 end
		names.map[id] = info
		names.count = names.count + 1
		return info
	end
	local t, last = C.Now(), names.asked[id]
	if not last or t - last >= Recipes.LOAD_RETRY then
		if t - names.windowStart >= Recipes.LOAD_BURST[2] then names.windowStart, names.windowCount = t, 0 end
		if names.windowCount < Recipes.LOAD_BURST[1] then
			names.windowCount = names.windowCount + 1
			names.asked[id] = t
			C.Spell.RequestData(id)
		end
	end
	return nil
end

-- The name of a recipe, or nil while it is not known.
function Recipes.NameOf(id)
	local info = Recipes.SpellData(id)
	return info and info.name or nil
end

-- The chat link of a recipe ("|Hspell:...|h[Name]|h"), or a link built from the name, or nil.
function Recipes.LinkOf(id)
	local C = compat()
	local link = C and C.Spell.Link(id)
	if link then return link end
	local name = Recipes.NameOf(id)
	if name and not name:find("[|%c]") then return ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(id, name) end
	return nil
end

local function onSpellData(id, success)
	if type(id) ~= "number" or names.asked[id] == nil then return end
	names.asked[id] = nil
	if success ~= false and Recipes.SpellData(id) then emit("RECIPE_NAMES_UPDATED", id) end
end

---------------------------------------------------------------------------------------------------------------------
-- Request craft (PRO-05)
---------------------------------------------------------------------------------------------------------------------
-- The whisper for asking a member to craft a recipe: { name = <name to whisper>, text = <the message, with the recipe
-- link>, link, recipe } or nil plus a reason ("member" not in the roster, "self", "offline", "noname" the recipe has no
-- name yet). Nothing is sent: the player opens the chat box with it and sends it (V2 turns this into a recorded order).
function Recipes:CraftRequest(guid, recipeId)
	local Ro, L = ns.Roster, ns.L
	local e = Ro and type(guid) == "string" and Ro:ByGUID(guid)
	if not e or type(e.name) ~= "string" then return nil, "member" end
	if e.isSelf then return nil, "self" end
	if e.online ~= true then return nil, "offline" end
	local link = Recipes.LinkOf(recipeId)
	local name = Recipes.NameOf(recipeId)
	if not (link or name) then return nil, "noname" end
	return { name = e.name, short = e.short or e.name, link = link, recipe = name,
		text = L["CR_WHISPER"]:format(link or ("[" .. name .. "]")) }
end

-- Opens the chat box for that whisper. Returns true, or false and the reason (CraftRequest's, or "chat").
function Recipes:OpenCraftRequest(guid, recipeId)
	local request, why = self:CraftRequest(guid, recipeId)
	if not request then return false, why end
	local C = compat()
	if not (C and C.Chat.OpenWhisper(request.name, request.text)) then return false, "chat" end
	self:RememberAsk(guid, recipeId)
	emit("CRAFT_REQUESTED", guid, recipeId)
	return true, request
end

---------------------------------------------------------------------------------------------------------------------
-- The reminders of the craft requests (SPEC-13 §2.3, SPEC-10 Q19)
---------------------------------------------------------------------------------------------------------------------
-- A craft request is only a whisper, so the Action Center keeps a reminder for the one who asked, on this computer only:
-- GuildKey:Data().craftAsks = { { guid, recipeId, at }, ... }, the oldest first. Never sent, never in the backup.
-- M13.2 replaces it with the orders.
Recipes.MAX_ASKS = 20
Recipes.ASK_DAYS = 7

local function askValid(a, t)
	return type(a) == "table" and type(a.guid) == "string" and type(a.recipeId) == "number" and type(a.at) == "number"
		and t - a.at < Recipes.ASK_DAYS * 86400
end

-- Writes the list again without the reminder of `guid` and `recipeId`, without the old ones and with `add` at its end.
local function writeAsks(guid, recipeId, add)
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	if not data then return false end
	local t, list, found = compat().ServerTime(), {}, false
	for _, a in ipairs(type(data.craftAsks) == "table" and data.craftAsks or {}) do
		if askValid(a, t) then
			if a.guid == guid and a.recipeId == recipeId then found = true else list[#list + 1] = a end
		end
	end
	if add then list[#list + 1] = { guid = guid, recipeId = recipeId, at = t } end
	while #list > Recipes.MAX_ASKS do table.remove(list, 1) end
	data.craftAsks = #list > 0 and list or nil
	return found
end

-- A request was written in the chat box: asking the same member for the same recipe again renews the reminder. Nothing is
-- kept while the switch `actions` is off.
function Recipes:RememberAsk(guid, recipeId)
	if not (ns.Features and ns.Features.On("actions")) then return false end
	if type(guid) ~= "string" or type(recipeId) ~= "number" then return false end
	writeAsks(guid, recipeId, true)
	return true
end

-- The player closes a reminder ("Done"). Returns true when there was one.
function Recipes:ForgetAsk(guid, recipeId)
	return writeAsks(guid, recipeId, false)
end

-- The profession of a member that has the recipe in a list we know, else the first one the member shared; nil for none.
function Recipes:SkillLineWith(guid, recipeId)
	for _, list in ipairs(self:AllLists()) do
		if list.guid == guid then
			for _, id in ipairs(list.ids) do
				if id == recipeId then return list.skillLine end
			end
		end
	end
	local first = self:ProfessionsOf(guid)[1]
	return first and first.skillLine or nil
end

-- The rows of the provider `craft`: the reminders of the last ASK_DAYS days. It only reads.
function Recipes:ActionRows(t)
	local rows = {}
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	if not data or type(data.craftAsks) ~= "table" then return rows end
	t = t or compat().ServerTime()
	local L = ns.L
	for _, a in ipairs(data.craftAsks) do
		if askValid(a, t) then
			local guid, recipeId = a.guid, a.recipeId
			local e = ns.Roster and ns.Roster:ByGUID(guid)
			local name = e and (e.short or e.name) or "?"
			local recipe = Recipes.NameOf(recipeId) or L["RV_RECIPE_ID"]:format(recipeId)
			rows[#rows + 1] = { key = guid .. ":" .. recipeId, urgency = 1, time = a.at, who = name,
				title = L["ACT_CRAFT"]:format(name, recipe),
				open = function()
					if ns.RecipeView then ns.RecipeView:Open(guid, Recipes:SkillLineWith(guid, recipeId), "craft") end
				end,
				dismiss = function() Recipes:ForgetAsk(guid, recipeId) end }
		end
	end
	return rows
end

-- A shared record arrived or changed: views that show it learn about it through the same event as a native answer.
local function onStoreChanged(set, id, origin)
	if set ~= "recipes" or type(id) ~= "string" then return end
	local guid, line = id:match("^(.-):(%d+)$")
	if guid then emit("RECIPES_UPDATED", guid, tonumber(line), origin == "local" and "own" or "shared") end
end

-- Forgets the native queue and cache (a change of guild); the epoch makes timers of the old guild do nothing.
function Recipes:Reset()
	resetNative(native)
end

function Recipes:NativeStatus()
	return { queued = #native.queue, inflight = native.inflight ~= nil, cached = native.count, off = native.off,
		resting = native.restUntil ~= nil and compat() ~= nil and compat().Now() < native.restUntil }
end

function Recipes:DebugLines()
	local s, C = native.stats, compat()
	local usable, why = self:NativeUsable()
	return {
		("Recipes: native source %s%s; %d answer(s) cached, %d queued"):format(usable and "usable" or "not usable",
			usable and "" or (" (" .. tostring(why) .. ")"), native.count, #native.queue),
		("  native queries %d, answers %d, timeouts %d, unreadable %d, stale %d, failed %d, served from cache %d, dropped %d"):format(
			s.queries, s.answers, s.timeouts, s.unusable, s.stale, s.failed, s.cached, s.dropped),
	}
end

if ns.Actions then
	ns.Actions:Register("craft", { label = "ACT_PROVIDER_CRAFT", order = 20,
		events = { "CRAFT_REQUESTED", "ROSTER_UPDATED", "RECIPE_NAMES_UPDATED" },
		items = function(t) return Recipes:ActionRows(t) end })
end

if ns.addon then
	ns.addon.Recipes = Recipes
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Recipes", function() return Recipes:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Recipes)
	Recipes:RegisterEvent(Recipes.EVENT, function() Recipes:OnNativeAnswer() end)
	pcall(Recipes.RegisterEvent, Recipes, "SPELL_DATA_LOAD_RESULT", function(_, id, success) onSpellData(id, success) end)
	if ns.Bus then
		ns.Bus:On("GUILD_CHANGED", function() Recipes:Reset() decoded.map, decoded.count = {}, 0 end)
		ns.Bus:On("STORE_CHANGED", onStoreChanged)
	end
end

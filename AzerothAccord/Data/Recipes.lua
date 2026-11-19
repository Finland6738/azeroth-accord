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
-- Bus: RECIPES_UPDATED(guid, skillLine, source) when a list arrives.
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

-- The list the views show for a member and profession: today the native answer; the shared lists join in M3.3.
function Recipes:Lookup(guid, skillLine)
	return self:Native(guid, skillLine)
end

-- Makes sure a list is being fetched when none is fresh: returns what RequestNative says.
function Recipes:Refresh(guid, skillLine)
	return self:RequestNative(guid, skillLine)
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

if ns.addon then
	ns.addon.Recipes = Recipes
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Recipes", function() return Recipes:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Recipes)
	Recipes:RegisterEvent(Recipes.EVENT, function() Recipes:OnNativeAnswer() end)
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() Recipes:Reset() end) end
end

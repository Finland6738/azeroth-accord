-- RecipeCatalogue: every recipe of a profession, learned by somebody in the guild or not (SPEC-06 §1.5, SPEC-03 §3.1).
-- Lua 5.1.
--
-- With a profession window open the client lists the WHOLE profession (C_TradeSkillUI.GetAllRecipeIDs: 593 ids for
-- Leatherworking on WoW Forever, owner 2026-11-27), and GetRecipeInfo(id).learned says which ones the character knows.
-- RecipeScan publishes the learned ones (the `recipes` set); this module keeps the whole list, once per profession for
-- the guild, in the set `recipecat`:
--
--   id = "<skill line>"   { skillLine, name, ids = Recipes.Encode(all ids), lv = the required skill levels, n, h }
--
--   lv      one varint per id of `ids`, in the same order (0 = the client did not say), in Base64; absent when no level
--           is known. TradeSkillRecipeInfo has no fields in the dump, so the level is read from the names a client may
--           use (Compat.TradeSkill.RequiredLevel) [verify S4].
--   merge   a catalogue only GROWS: a new read is merged with the record held (the union of the ids; a level fills a 0 but
--           never replaces a known one), and it is written only when the union adds an id or a level. So two members
--           whose clients answer a little differently never take turns rewriting it, and a filtered or partial window
--           can only add. At most one write per profession every PUBLISH_MIN seconds (like PRO-06).
--   trust   any member may write it, first hand (an officer may relay it), but only for a profession the AUTHOR has: the
--           store holds the author's own `recipes` record of that skill line, or the roster shows the profession. A
--           catalogue that arrives before its author's list waits for it (`wait`, at most WAIT seconds, WAIT_MAX records).
--           Size: at most Recipes.MAX_IDS ids and maxBytes (Net/Store.lua); the text is never trusted (Recipes.Decode).
--   names   never in the record: the views read them from the client (Recipes.SpellData), in the player's language.
--
-- Bus: RECIPES_UPDATED(nil, skillLine, "catalogue") when a catalogue arrives or changes.
local ADDON_NAME, ns = ...
ns = ns or {}
local Cat = {}
ns.RecipeCatalogue, ns.modules = Cat, ns.modules or {}
ns.modules.RecipeCatalogue = Cat

local type, pairs, ipairs, tostring, tonumber, floor = type, pairs, ipairs, tostring, tonumber, math.floor

Cat.SET = "recipecat"
Cat.MAX_LEVEL = 1000
Cat.PUBLISH_MIN = 600       -- seconds between two writes of one profession's catalogue by this client
Cat.WAIT = 600              -- seconds a catalogue waits for its author's recipe list
Cat.WAIT_MAX = 50           -- catalogues waiting at most (the oldest go first)

local function compat() return ns.Compat end
local function S() return ns.Store end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return compat() and compat().Now() or 0 end
local function isLine(v) return type(v) == "number" and v == floor(v) and v > 0 and v < 100000 end

function Cat.Id(skillLine)
	if not isLine(skillLine) then return nil end
	return tostring(floor(skillLine))
end

---------------------------------------------------------------------------------------------------------------------
-- The levels: one varint per id, in the order of the sorted ids
---------------------------------------------------------------------------------------------------------------------
-- The Base64 text of the levels of `ids` (a sorted list) from `levels` ({ [id] = level }), or nil when none is known.
function Cat.EncodeLevels(ids, levels)
	if type(ids) ~= "table" or type(levels) ~= "table" then return nil end
	local bytes, any = {}, false
	for _, id in ipairs(ids) do
		local v = levels[id]
		v = (type(v) == "number" and v >= 1 and v <= Cat.MAX_LEVEL) and floor(v) or 0
		if v > 0 then any = true end
		while v >= 128 do
			bytes[#bytes + 1] = string.char(v % 128 + 128)
			v = floor(v / 128)
		end
		bytes[#bytes + 1] = string.char(v)
	end
	if not any then return nil end
	local C = compat()
	return C and C.Base64.Encode(table.concat(bytes)) or nil
end

-- The list of `n` levels a text stands for, or nil plus a reason. Never trusts the text.
function Cat.DecodeLevels(text, n)
	if type(text) ~= "string" or #text > 16384 or type(n) ~= "number" then return nil, "shape" end
	if text:find("[^A-Za-z0-9+/=]") then return nil, "base64" end
	local C = compat()
	local raw = C and C.Base64.Decode(text)
	if type(raw) ~= "string" then return nil, "base64" end
	local out, value, shift = {}, 0, 0
	for i = 1, #raw do
		local b = raw:byte(i)
		value = value + (b % 128) * 2 ^ shift
		if b < 128 then
			if value > Cat.MAX_LEVEL then return nil, "range" end
			if #out >= n then return nil, "count" end
			out[#out + 1] = value
			value, shift = 0, 0
		else
			shift = shift + 7
			if shift > 14 then return nil, "varint" end
		end
	end
	if shift ~= 0 or #out ~= n then return nil, "count" end
	return out
end

function Cat.HashOf(skillLine, ids, lv)
	local H = ns.Hash
	if not H then return 0 end
	return H.Fast(("cat|%s|%s|%s"):format(tostring(skillLine), ids or "", lv or ""))
end

---------------------------------------------------------------------------------------------------------------------
-- Trust (Net/Store.lua calls these)
---------------------------------------------------------------------------------------------------------------------
-- true when `guid` has the profession `skillLine`: its own `recipes` record is held, or the roster shows it.
function Cat.HasProfession(guid, skillLine)
	if type(guid) ~= "string" or not isLine(skillLine) then return false end
	local rec = S() and S():Get("recipes", guid .. ":" .. floor(skillLine))
	if type(rec) == "table" and rec.del ~= true and rec.char == guid then return true end
	local e = ns.Roster and ns.Roster.ByGUID and ns.Roster:ByGUID(guid)
	for _, p in ipairs(e and e.professions or {}) do
		if p.id == skillLine then return true end
	end
	return false
end

-- The shape of a catalogue record and its author's profession. Returns true, or false and "owner", "size" or "wait".
function Cat.ValidRecord(rec)
	if type(rec) ~= "table" or not isLine(rec.skillLine) or rec.id ~= Cat.Id(rec.skillLine) then return false, "owner" end
	if rec.name ~= nil and not (type(rec.name) == "string" and #rec.name <= 64) then return false, "owner" end
	local R = ns.Recipes
	if not R then return false, "owner" end
	local ids
	if type(rec.ids) == "string" then
		ids = R.Decode(rec.ids)
		if ids and rec.lv ~= nil and not Cat.DecodeLevels(rec.lv, #ids) then return false, "owner" end
	elseif type(rec.ids) == "table" then   -- plain lists, as the demo keeps them (Recipes reads both forms too)
		ids = R.Normalize(rec.ids)
		if ids and #ids ~= #rec.ids then return false, "owner" end
		if ids and rec.lv ~= nil then
			if type(rec.lv) ~= "table" or #rec.lv ~= #ids then return false, "owner" end
			for _, v in ipairs(rec.lv) do
				if type(v) ~= "number" or v < 0 or v > Cat.MAX_LEVEL then return false, "owner" end
			end
		end
	end
	if not ids or #ids == 0 then return false, "owner" end
	if not Cat.HasProfession(rec.author, rec.skillLine) then return false, "wait" end
	return true
end

-- A catalogue whose author's list has not arrived yet: kept aside, tried again when a list or the roster changes.
Cat.waiting = {}
function Cat.Wait(rec, ctx)
	local w = Cat.waiting
	w[#w + 1] = { rec = S().Copy(rec), sender = ctx and ctx.sender, dist = ctx and ctx.dist, at = now() }
	while #w > Cat.WAIT_MAX do table.remove(w, 1) end
end

function Cat.Retry()
	local w, t = Cat.waiting, now()
	if #w == 0 then return 0 end
	Cat.waiting = {}
	local taken = 0
	for _, e in ipairs(w) do
		if t - e.at <= Cat.WAIT then
			if Cat.HasProfession(e.rec.author, e.rec.skillLine) then
				if S():Accept(Cat.SET, e.rec, { sender = e.sender, dist = e.dist }) then taken = taken + 1 end
			else
				Cat.waiting[#Cat.waiting + 1] = e
			end
		end
	end
	return taken
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local decoded = {}   -- id -> { rev, time, author, value }

-- The catalogue of a profession, or nil: { skillLine, ids (sorted), levels = { [id] = level }, n, name, time, author,
-- hasLevels }. Decoded once per revision.
function Cat:Get(skillLine)
	local id = Cat.Id(skillLine)
	local rec = id and S() and S():Get(Cat.SET, id)
	if type(rec) ~= "table" or rec.del == true then return nil end
	local e = decoded[id]
	if e and e.rev == rec.rev and e.time == rec.time and e.author == rec.author then return e.value end
	local ids, lv
	if type(rec.ids) == "table" then   -- demo mode (Data/Demo.lua) keeps plain lists
		ids = ns.Recipes.Normalize(rec.ids)
		lv = type(rec.lv) == "table" and #rec.lv == #rec.ids and rec.lv or nil
	else
		ids = ns.Recipes.Decode(rec.ids)
		lv = ids and type(rec.lv) == "string" and Cat.DecodeLevels(rec.lv, #ids) or nil
	end
	if not ids then return nil end
	local levels, hasLevels = {}, false
	if lv then
		for i, v in ipairs(lv) do
			if v > 0 then levels[ids[i]] = v hasLevels = true end
		end
	end
	local value = { skillLine = floor(skillLine), ids = ids, levels = levels, hasLevels = hasLevels, n = #ids, name = rec.name,
		time = rec.time, author = rec.author }
	decoded[id] = { rev = rec.rev, time = rec.time, author = rec.author, value = value }
	return value
end

-- The skill lines that have a catalogue.
function Cat:Lines()
	local out = {}
	for _, rec in pairs(S() and S():Records(Cat.SET) or {}) do
		if type(rec) == "table" and rec.del ~= true and isLine(rec.skillLine) then out[#out + 1] = rec.skillLine end
	end
	table.sort(out)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (RecipeScan calls Publish after every read of the own window)
---------------------------------------------------------------------------------------------------------------------
-- The fields of the merge of `read` ({ skillLine, name, all = ids, levels = { [id] = level } }) with the catalogue held,
-- or nil and "unchanged" (the read adds nothing) or another reason.
function Cat.Merge(held, read)
	local R = ns.Recipes
	local all = R.Normalize(read and read.all)
	if not all or #all == 0 then return nil, "empty" end
	local union, levels, added = {}, {}, 0
	local seen = {}
	for _, id in ipairs(held and held.ids or {}) do
		seen[id] = true
		union[#union + 1] = id
		levels[id] = held.levels[id]
	end
	for _, id in ipairs(all) do
		if not seen[id] then
			seen[id] = true
			union[#union + 1] = id
			added = added + 1
		end
		local v = read.levels and read.levels[id]
		if not levels[id] and type(v) == "number" and v >= 1 and v <= Cat.MAX_LEVEL then
			levels[id] = floor(v)
			if held and held.levels and not held.levels[id] then added = added + 1 end
		end
	end
	if held and added == 0 then return nil, "unchanged" end
	union = R.Normalize(union)
	local text, why = R.Encode(union)
	if not text then return nil, why end
	local lv = Cat.EncodeLevels(union, levels)
	local name = type(read.name) == "string" and #read.name <= 64 and read.name or (held and held.name) or nil
	return { skillLine = floor(read.skillLine), name = name, ids = text, lv = lv, n = #union, h = Cat.HashOf(read.skillLine, text, lv) }
end

local state
local function resetState()
	state = { lastPublish = {}, pending = {}, flushing = {}, epoch = ((state and state.epoch) or 0) + 1,
		stats = { published = 0, unchanged = 0, deferred = 0, failed = 0 }, last = nil }
	Cat.state = state
end
resetState()

-- Merges a read of the own window into the profession's catalogue and writes it when it grew. Returns true, or false
-- and "unchanged", "deferred" or why it could not be written.
function Cat:Publish(read, force)
	local C = compat()
	if not (C and S() and type(read) == "table" and isLine(read.skillLine)) then return false, "read" end
	local line = floor(read.skillLine)
	local fields, why = Cat.Merge(self:Get(line), read)
	if not fields then
		if why == "unchanged" then
			state.stats.unchanged = state.stats.unchanged + 1
			state.pending[line] = nil
		end
		state.last = ("catalogue of skill line %d: %s"):format(line, tostring(why))
		return false, why
	end
	local t = C.Now()
	local last = state.lastPublish[line]
	if not force and last and t - last < Cat.PUBLISH_MIN then
		state.pending[line] = read
		state.stats.deferred = state.stats.deferred + 1
		state.last = ("catalogue of skill line %d: waits for the 10-minute pause"):format(line)
		if not state.flushing[line] then
			state.flushing[line] = true
			local epoch = state.epoch
			local ok = C.After(last + Cat.PUBLISH_MIN - t + 1, function()
				if epoch ~= state.epoch then return end
				state.flushing[line] = nil
				local pending = state.pending[line]
				if pending then Cat:Publish(pending, true) end
			end)
			if not ok then state.flushing[line] = nil end
		end
		return false, "deferred"
	end
	local rec, err = S():Put(Cat.SET, Cat.Id(line), fields)
	if not rec then
		state.stats.failed = state.stats.failed + 1
		state.last = ("catalogue of skill line %d not written: %s"):format(line, tostring(err))
		return false, err
	end
	state.lastPublish[line] = t
	state.pending[line] = nil
	state.stats.published = state.stats.published + 1
	state.last = ("catalogue of skill line %d: %d recipe(s) written"):format(line, fields.n)
	return true
end

function Cat:Reset()
	resetState()
	Cat.waiting = {}
	decoded = {}
end

function Cat:DebugLines()
	local s = state.stats
	return { ("RecipeCatalogue: %d profession(s) held, %d written, %d unchanged, %d deferred, %d failed, %d waiting for a list; last: %s"):format(
		#self:Lines(), s.published, s.unchanged, s.deferred, s.failed, #Cat.waiting, state.last or "nothing yet") }
end

local function onStoreChanged(set, id)
	if set == Cat.SET then
		local line = tonumber(id)
		if line then emit("RECIPES_UPDATED", nil, line, "catalogue") end
	elseif set == "recipes" and #Cat.waiting > 0 then
		Cat.Retry()
	end
end

if ns.addon then
	ns.addon.RecipeCatalogue = Cat
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("RecipeCatalogue", function() return Cat:DebugLines() end) end
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", onStoreChanged)
		ns.Bus:On("ROSTER_UPDATED", function() if #Cat.waiting > 0 then Cat.Retry() end end)
		ns.Bus:On("GUILD_CHANGED", function() Cat:Reset() end)
	end
end

-- RecipeScan: the player's own recipe lists, read from the profession window and published to the guild (SPEC-06 §1, §3,
-- SPEC-03 §3, PRO-06). Lua 5.1.
--
-- Whenever a profession window opens or its list changes (TRADE_SKILL_SHOW, TRADE_SKILL_LIST_UPDATE; many events come
-- in a burst, so the scan waits DEBOUNCE seconds after the last one) the open profession is read:
--
--   skill line   C_TradeSkillUI.GetBaseProfessionInfo(); matched to one of the character's own professions (by id, else by
--                name) so it is the same id the roster shows; a window that is closed or not a profession is skipped.
--   recipes      GetAllRecipeIDs (else GetFilteredRecipeIDs) [verify S4: neither is in the dump], kept when
--                GetRecipeInfo(id).learned is true; a client that gives no `learned` flag at all counts every id as known,
--                one that gives no recipe info at all is not read (nothing is published from a guess).
--   filtered     the filtered list follows the window's search box and may be partial: a scan from it can only ADD to what
--                was published, never remove.
--   not ours     a window that shows somebody else's recipes (a profession link, the guild's view of a member, an NPC:
--                Compat.TradeSkill.IsOthersWindow) or a primary profession the character does not have is not read: its
--                "learned" flags are not the player's.
--   catalogue    the whole list (learned or not) and each recipe's required skill level, when the client gives it, go to
--                the profession's catalogue (Data/RecipeCatalogue.lua), which grows only when the read adds something.
--
-- A scan becomes one `recipes` record per character and profession (id = "<GUID>:<skill line>", SPEC-03 §3):
-- { char, skillLine, name, rank, maxRank, ids = Recipes.Encode(list), n = count, h = hash }. PRO-06: it is published when
-- its hash differs from the one held, at most once every PUBLISH_MIN (10 minutes) per profession; a change that comes
-- sooner waits and goes out when the time is up, with the latest state. Always shared (owner decision D3 covers the
-- character list; the recipes follow the same rule: no setting). Recipes of other characters are never touched here.
local ADDON_NAME, ns = ...
ns = ns or {}
local Scan = {}
ns.RecipeScan, ns.modules = Scan, ns.modules or {}
ns.modules.RecipeScan = Scan

local type, pairs, ipairs, tostring, floor = type, pairs, ipairs, tostring, math.floor

Scan.EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }
Scan.DEBOUNCE = 2          -- seconds after the last window event
Scan.PUBLISH_MIN = 600     -- PRO-06: at most one publication per profession in this many seconds

local state
local function resetState()
	state = {
		lastPublish = {},       -- skill line -> Now() of the last publication of this session
		pending = {},           -- skill line -> a scan that waits for its turn
		flushing = {},          -- skill line -> true while a timer for it is set
		waiting = false,        -- a debounce timer is set
		epoch = ((state and state.epoch) or 0) + 1,
		stats = { scans = 0, published = 0, unchanged = 0, deferred = 0, skipped = 0, failed = 0 },
		last = nil,             -- the outcome of the last scan, for /accord debug
	}
	Scan.state = state
end
resetState()

local function compat() return ns.Compat end
local function num(v) return type(v) == "number" and v == v and v or nil end

---------------------------------------------------------------------------------------------------------------------
-- Reading the open profession window
---------------------------------------------------------------------------------------------------------------------
-- Matches the window's profession to one of the player's own, so the id is the one the roster uses. The fifth value is
-- false when the character has primary professions, none of them is this one, and this one is primary too (the window
-- shows somebody else's profession); a secondary profession (Cooking...) is never in that list and is taken as it is.
local function resolveProfession(base)
	local C = compat()
	local id, name = num(base.professionID), type(base.professionName) == "string" and base.professionName or nil
	local own = C.TradeSkill.OwnProfessions()
	for _, p in ipairs(own) do
		if p.skillLine == id then return p.skillLine, p.name or name, p.rank, p.maxRank, true end
	end
	if name then
		for _, p in ipairs(own) do
			if p.name == name and p.skillLine then return p.skillLine, p.name, p.rank, p.maxRank, true end
		end
	end
	local primary = C.TradeSkill.PRIMARY_LINES and C.TradeSkill.PRIMARY_LINES[id or -1]
	return id, name, nil, nil, not (primary and #own > 0)
end

-- The field names of a recipe info table, for /accord debug: TradeSkillRecipeInfo has no fields in the dump [verify S4].
local function fieldNames(info)
	local keys = {}
	for k, v in pairs(info) do
		if type(k) == "string" and (type(v) == "number" or type(v) == "boolean") then keys[#keys + 1] = k end
	end
	table.sort(keys)
	while #keys > 40 do keys[#keys] = nil end
	return table.concat(keys, ", ")
end

-- What the open window shows: { skillLine, name, rank, maxRank, ids (learned), all (every id), levels = { [id] = the
-- required skill level }, filtered }, or nil plus a reason ("closed", "others", "notown", "norecipes", "noinfo").
function Scan:Read()
	local C = compat()
	if not C then return nil, "compat" end
	local base = C.TradeSkill.BaseProfessionInfo()
	if not base or not num(base.professionID) or base.professionID == 0 then return nil, "closed" end
	if C.TradeSkill.IsOthersWindow and C.TradeSkill.IsOthersWindow() then return nil, "others" end
	local skillLine, name, rank, maxRank, own = resolveProfession(base)
	if not own then return nil, "notown" end
	rank = rank or num(base.skillLevel)
	maxRank = maxRank or num(base.maxSkillLevel)
	local all, via = C.TradeSkill.RecipeIDs()
	if not all then
		if C:Feature("ownRecipes") ~= "available" then C:SetFeature("ownRecipes", "missing", "no recipe list API") end
		return nil, "norecipes"
	end
	local known, flagged, learned, levels, withLevel = 0, 0, {}, {}, 0
	local requiredLevel = C.TradeSkill.RequiredLevel
	for _, id in ipairs(all) do
		local info = C.TradeSkill.RecipeInfo(id)
		if info then
			known = known + 1
			if known == 1 then state.fields = fieldNames(info) end
			if info.learned ~= nil then
				flagged = flagged + 1
				if info.learned == true then learned[#learned + 1] = id end
			end
			local level = requiredLevel and requiredLevel(info)
			if level then levels[id] = level withLevel = withLevel + 1 end
		end
	end
	if known == 0 and #all > 0 then return nil, "noinfo" end
	local ids = flagged == 0 and all or learned
	state.read = ("skill line %d: %d id(s), %d with info, %d learned, %d with a required level"):format(
		floor(skillLine), #all, known, #ids, withLevel)
	return { skillLine = floor(skillLine), name = name, rank = rank, maxRank = maxRank, ids = ids, all = all, levels = levels,
		filtered = via == "filtered" }
end

---------------------------------------------------------------------------------------------------------------------
-- Publishing (PRO-06)
---------------------------------------------------------------------------------------------------------------------
local function ownGUID() return compat() and compat().Player.GUID() end

-- The record fields for a read, merged with the published list when the scan was filtered. Returns fields, ids.
local function build(read, old)
	local ids = read.ids
	if read.filtered and old and old.ids then
		local before = ns.Recipes.Decode(old.ids)
		if before then
			local union = {}
			for _, id in ipairs(before) do union[#union + 1] = id end
			for _, id in ipairs(ids) do union[#union + 1] = id end
			ids = union
		end
	end
	ids = ns.Recipes.Normalize(ids) or {}
	local text, why = ns.Recipes.Encode(ids)
	if not text then return nil, why end
	return {
		char = ownGUID(), skillLine = read.skillLine, name = read.name, rank = read.rank, maxRank = read.maxRank,
		ids = text, n = #ids, h = ns.Recipes.HashOf(read.skillLine, read.rank, read.maxRank, text),
	}
end

local function write(id, fields, now)
	local rec, why = ns.Store:Put("recipes", id, fields)
	if not rec then
		state.stats.failed = state.stats.failed + 1
		state.last = "not published: " .. tostring(why)
		return false, why
	end
	state.lastPublish[fields.skillLine] = now
	state.pending[fields.skillLine] = nil
	state.stats.published = state.stats.published + 1
	state.last = ("published %d recipe(s) of skill line %d"):format(fields.n, fields.skillLine)
	return true
end

local flush

-- Publishes a read when it is new and its profession is not in the 10-minute pause; otherwise keeps it for later.
-- Returns true when a record was written, or false and "unchanged", "deferred" or the reason it could not be written.
function Scan:Publish(read, force)
	local C, S = compat(), ns.Store
	local me = ownGUID()
	if not (C and S and me) then return false, "player" end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local id = me .. ":" .. read.skillLine
	local old = S:Get("recipes", id)
	local fields, why = build(read, old and old.del ~= true and old or nil)
	if not fields then
		state.stats.failed = state.stats.failed + 1
		state.last = "not published: " .. tostring(why)
		return false, why
	end
	if old and old.del ~= true and old.h == fields.h then
		state.stats.unchanged = state.stats.unchanged + 1
		state.pending[read.skillLine] = nil
		state.last = ("unchanged: skill line %d"):format(read.skillLine)
		return false, "unchanged"
	end
	local now = C.Now()
	local last = state.lastPublish[read.skillLine]
	if not force and last and now - last < Scan.PUBLISH_MIN then
		state.pending[read.skillLine] = read
		state.stats.deferred = state.stats.deferred + 1
		state.last = ("deferred: skill line %d waits for the 10-minute pause"):format(read.skillLine)
		if not state.flushing[read.skillLine] then
			state.flushing[read.skillLine] = true
			local epoch, line = state.epoch, read.skillLine
			local scheduled = C.After(last + Scan.PUBLISH_MIN - now + 1, function()
				if epoch ~= state.epoch then return end
				state.flushing[line] = nil
				flush(line)
			end)
			if not scheduled then state.flushing[read.skillLine] = nil end
		end
		return false, "deferred"
	end
	return write(id, fields, now)
end

-- The pause is over: publishes what waited for it.
flush = function(skillLine)
	local read = state.pending[skillLine]
	if read then Scan:Publish(read, true) end
end

---------------------------------------------------------------------------------------------------------------------
-- Running a scan
---------------------------------------------------------------------------------------------------------------------
-- Reads the open window and publishes. Returns what Publish returns, or false and why the window was not read.
function Scan:Run()
	state.stats.scans = state.stats.scans + 1
	local read, why = self:Read()
	if not read then
		state.stats.skipped = state.stats.skipped + 1
		state.last = "skipped: " .. tostring(why)
		return false, why
	end
	local C = compat()
	if C:Feature("ownRecipes") ~= "available" then C:SetFeature("ownRecipes", "available", "a profession window was read") end
	local ok, why = self:Publish(read)
	-- after the own list, so the store already holds the proof that this character has the profession
	if ns.RecipeCatalogue and ns.GuildKey and ns.GuildKey:Current() then ns.RecipeCatalogue:Publish(read) end
	return ok, why
end

-- A window event: the scan runs DEBOUNCE seconds after the last one of a burst.
function Scan:OnEvent()
	local C = compat()
	if not C then return end
	if state.waiting then return end
	state.waiting = true
	local epoch = state.epoch
	local scheduled = C.After(Scan.DEBOUNCE, function()
		if epoch ~= state.epoch then return end
		state.waiting = false
		Scan:Run()
	end)
	if not scheduled then
		state.waiting = false
		Scan:Run()
	end
end

-- A change of guild: nothing waits any more (the timers of the old guild do nothing).
function Scan:Reset()
	resetState()
end

function Scan:DebugLines()
	local s = state.stats
	local waiting = 0
	for _ in pairs(state.pending) do waiting = waiting + 1 end
	return {
		("RecipeScan: %d scan(s), %d published, %d unchanged, %d deferred, %d skipped, %d failed; %d waiting for the pause"):format(
			s.scans, s.published, s.unchanged, s.deferred, s.skipped, s.failed, waiting),
		("  last: %s"):format(state.last or "no profession window read yet"),
		("  last read: %s"):format(state.read or "none"),
		("  recipe info fields: %s"):format(state.fields or "none seen yet"),
	}
end

if ns.addon then
	ns.addon.RecipeScan = Scan
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("RecipeScan", function() return Scan:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Scan)
	for _, event in ipairs(Scan.EVENTS) do
		pcall(Scan.RegisterEvent, Scan, event, function() Scan:OnEvent() end)
	end
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() Scan:Reset() end) end
end

-- Actions: the Action Center, one list of what waits on the player (SPEC-13 §2, M9.2). Lua 5.1.
--
-- Nothing is saved here: every row comes, each time, from a provider that reads the data of its own module, so a thing
-- resolved in its view leaves the list because its provider no longer returns it (ACT-04: this module resolves nothing).
-- A module registers its provider with Actions:Register(id, def); this file knows no module.
--
--   def = { label,    -- locale key of the provider's name (its filter chip, the tooltip of a row)
--           order,    -- order among providers at equal urgency and time
--           events,   -- Bus events after which the list is read again
--           feature,  -- optional: a switch of Core/Features.lua; off, the provider is not there
--           visible,  -- optional: function() -> false = the provider is not there for this character
--           items }   -- function(now) -> rows; it only reads (ACT-01)
--
--   row = { key,      -- unique in the provider, at most KEY_MAX characters
--           urgency,  -- 3 now, 2 to do, 1 reminder (SPEC-13 §2.2)
--           time,     -- server time the thing has been waiting since
--           title,    -- already in the interface language, cut at TITLE_MAX characters
--           detail,   -- optional, cut at DETAIL_MAX
--           who,      -- optional: the name to show
--           open,     -- function(): opens the view that resolves the row
--           dismiss } -- optional: function(), only for local reminders the player closes by hand
--
-- A provider (or its `visible`, or a row's `open` / `dismiss`) that raises is caught with pcall, skipped for that read and
-- recorded for /accord debug. While the switch `actions` is off the list is empty and no timer runs.
-- Bus: ACTIONS_CHANGED() when the list changed (the keys, urgencies and titles).
local ADDON_NAME, ns = ...
ns = ns or {}
local Actions = {}
ns.Actions, ns.modules = Actions, ns.modules or {}
ns.modules.Actions = Actions

local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall
local sort, concat = table.sort, table.concat

Actions.FEATURE = "actions"
Actions.PER_PROVIDER = 50    -- ACT-02: more rows become one "and N more" row
Actions.TOTAL = 200
Actions.DELAY = 0.5          -- seconds the events are collected before the list is read again (ACT-03)
Actions.TICK = 60            -- and read again this often: the urgencies that depend on the hour
Actions.KEY_MAX = 64
Actions.TITLE_MAX = 80
Actions.DETAIL_MAX = 120
Actions.TODO = 2             -- the urgencies counted on the badge are this one and above
Actions.MAX_ERRORS = 10

Actions.providers = {}       -- id -> def
local state = { rows = nil, print = nil, timer = false, ticker = nil, epoch = 0 }
Actions.errors = {}          -- the last MAX_ERRORS: { id = , message = }
Actions.errorCount = 0

local function compat() return ns.Compat end

function Actions.Enabled()
	return ns.Features ~= nil and ns.Features.On(Actions.FEATURE)
end

local function inGuild()
	return ns.Role ~= nil and ns.Role:InGuild() and ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil
end

local function record(id, message)
	Actions.errorCount = Actions.errorCount + 1
	Actions.errors[#Actions.errors + 1] = { id = id, message = tostring(message):sub(1, 160) }
	if #Actions.errors > Actions.MAX_ERRORS then table.remove(Actions.errors, 1) end
end

---------------------------------------------------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------------------------------------------------
local function onEvent() Actions:Changed() end

function Actions:Register(id, def)
	if type(id) ~= "string" or id == "" or type(def) ~= "table" or type(def.items) ~= "function" then return false end
	def.id = id
	def.order = def.order or 100
	self.providers[id] = def
	if ns.Bus then
		for _, event in ipairs(def.events or {}) do ns.Bus:On(event, onEvent) end
	end
	self:Changed()
	return true
end

-- Whether a provider is there for this character now.
local function present(def)
	if def.feature ~= nil and not (ns.Features and ns.Features.On(def.feature)) then return false end
	if def.visible == nil then return true end
	local ok, yes = pcall(def.visible)
	if not ok then record(def.id, yes) return false end
	return yes ~= false
end

-- The providers present, in their order.
function Actions:Providers()
	local out = {}
	if not Actions.Enabled() then return out end
	for _, def in pairs(self.providers) do
		if present(def) then out[#out + 1] = def end
	end
	sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.id < b.id
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------------------------
-- `text` cut at `max` characters (UTF-8), with dots.
function Actions.Cut(text, max)
	local n, i, keep = 0, 1, nil
	while i <= #text do
		local b = text:byte(i)
		local size = b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1
		n = n + 1
		if n == max - 2 then keep = i - 1 end   -- the last byte that leaves room for the three dots
		if n > max then return text:sub(1, keep) .. "..." end
		i = i + size
	end
	return text
end

-- SPEC-13 §2.2: the most urgent first, then who has been waiting longest, then the provider, then the key.
function Actions.Before(a, b)
	if a.urgency ~= b.urgency then return a.urgency > b.urgency end
	if a.time ~= b.time then return a.time < b.time end
	if a.order ~= b.order then return a.order < b.order end
	if a.key ~= b.key then return a.key < b.key end
	return a.provider < b.provider
end

-- The row of a provider as the list keeps it, or nil for one that is not well formed.
local function clean(def, r)
	if type(r) ~= "table" then return nil end
	local u = r.urgency
	if type(r.key) ~= "string" or r.key == "" or #r.key > Actions.KEY_MAX then return nil end
	if not (u == 1 or u == 2 or u == 3) or type(r.time) ~= "number" or type(r.title) ~= "string" or r.title == "" then return nil end
	if type(r.open) ~= "function" then return nil end
	return {
		provider = def.id, order = def.order, label = def.label, key = r.key, urgency = u, time = r.time,
		title = Actions.Cut(r.title, Actions.TITLE_MAX),
		detail = type(r.detail) == "string" and r.detail ~= "" and Actions.Cut(r.detail, Actions.DETAIL_MAX) or nil,
		who = type(r.who) == "string" and r.who ~= "" and r.who or nil,
		open = r.open, dismiss = type(r.dismiss) == "function" and r.dismiss or nil,
	}
end

-- The rows of one provider, sorted, at most PER_PROVIDER plus the "and N more" row.
local function rowsOf(def, t)
	local ok, list = pcall(def.items, t)
	if not ok then record(def.id, list) return {} end
	if type(list) ~= "table" then record(def.id, "items() returned no list") return {} end
	local rows, seen = {}, {}
	for _, r in ipairs(list) do
		local row = clean(def, r)
		if row and not seen[row.key] then
			seen[row.key] = true
			rows[#rows + 1] = row
		end
	end
	sort(rows, Actions.Before)
	local extra = #rows - Actions.PER_PROVIDER
	if extra > 0 then
		local first = rows[Actions.PER_PROVIDER + 1]
		for i = #rows, Actions.PER_PROVIDER + 1, -1 do rows[i] = nil end
		-- it sorts right after the rows kept, and opens the view of the first row left out
		rows[#rows + 1] = { provider = def.id, order = def.order, label = def.label, key = "~more", urgency = first.urgency,
			time = first.time, title = ns.L["ACT_MORE"]:format(extra), open = first.open, more = extra }
	end
	return rows
end

-- Reads every provider now.
function Actions:Compute(t)
	local out = {}
	if not (Actions.Enabled() and inGuild()) then return out end
	t = t or compat().ServerTime()
	for _, def in ipairs(self:Providers()) do
		for _, row in ipairs(rowsOf(def, t)) do out[#out + 1] = row end
	end
	sort(out, Actions.Before)
	for i = #out, Actions.TOTAL + 1, -1 do out[i] = nil end
	return out
end

local function fingerprint(rows)
	local parts = {}
	for i, r in ipairs(rows) do parts[i] = concat({ r.provider, r.key, r.urgency, r.title }, "\1") end
	return concat(parts, "\2")
end

-- Reads the list again and says so when it changed. Returns the rows.
function Actions:Refresh(t)
	local rows = self:Compute(t)
	local print_ = fingerprint(rows)
	local before = state.print or ""
	state.rows, state.print = rows, print_
	if print_ ~= before and ns.Bus then ns.Bus:Emit("ACTIONS_CHANGED") end
	return rows
end

-- The list as last read (read now when it never was).
function Actions:Rows()
	if not state.rows then return self:Refresh() end
	return state.rows
end

-- How many rows are to do or urgent: the number on the tab and in the tooltip of the Compartment.
function Actions:Count()
	if not Actions.Enabled() then return 0 end
	local n = 0
	for _, r in ipairs(self:Rows()) do
		if r.urgency >= Actions.TODO then n = n + 1 end
	end
	return n
end

-- Something changed: one read after the burst.
function Actions:Changed()
	if state.timer or not Actions.Enabled() then return end
	state.timer = true
	local epoch = state.epoch
	local scheduled = compat() and compat().After(Actions.DELAY, function()
		if epoch ~= state.epoch then return end
		state.timer = false
		Actions:Refresh()
	end)
	if not scheduled then state.timer = false self:Refresh() end
end

-- A click on a row: opens the view that resolves it. Returns true when it did not raise.
function Actions:Open(row)
	if type(row) ~= "table" or type(row.open) ~= "function" then return false end
	local ok, err = pcall(row.open)
	if not ok then record(row.provider, err) end
	return ok
end

-- The Done button of a local reminder. Returns false for a row that cannot be closed by hand.
function Actions:Dismiss(row)
	if type(row) ~= "table" or type(row.dismiss) ~= "function" then return false end
	local ok, err = pcall(row.dismiss)
	if not ok then record(row.provider, err) end
	self:Refresh()
	return ok
end

-- The role or the guild changed: what is listed may not be for this character any more, so it goes at once and the list
-- is read again after the burst, when the other modules have dropped what they held of the old role or guild.
function Actions:Reset()
	state.epoch, state.timer = state.epoch + 1, false
	local had = state.print ~= nil and state.print ~= ""
	state.rows, state.print = {}, ""
	if had and ns.Bus then ns.Bus:Emit("ACTIONS_CHANGED") end
	self:Start()
	self:Changed()
end

function Actions:Start()
	if state.ticker or not Actions.Enabled() or not compat() then return end
	state.ticker = compat().NewTicker(Actions.TICK, function() Actions:Refresh() end)
end

-- Ids and counts only: never a name or a title.
function Actions:DebugLines()
	local ids = {}
	for _, def in ipairs(self:Providers()) do ids[#ids + 1] = def.id end
	local lines = { ("Actions: %d row(s), %d to do, providers: %s, %d error(s)"):format(#(state.rows or {}), self:Count(),
		#ids > 0 and concat(ids, ", ") or "none", self.errorCount) }
	for _, e in ipairs(self.errors) do lines[#lines + 1] = ("  error in %s: %s"):format(e.id, e.message) end
	return lines
end

if ns.addon then
	ns.addon.Actions = Actions
	if ns.addon.AddDebugSection then
		-- the section exists only while the switch is on (Core/Features.lua)
		if ns.OnEnable then
			ns.OnEnable(function()
				if Actions.Enabled() then ns.addon:AddDebugSection("Actions", function() return Actions:DebugLines() end) end
			end)
		end
	end
	if ns.Bus then
		local function reset() Actions:Reset() end
		ns.Bus:On("ROLE_CHANGED", reset)
		ns.Bus:On("GUILD_CHANGED", reset)
	end
	if ns.OnEnable then ns.OnEnable(function() Actions:Start() Actions:Changed() end) end
end

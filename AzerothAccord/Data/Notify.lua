-- Notify: the notification centre (SPEC-13 §3, M9.3). Lua 5.1.
--
-- A module registers its kinds of notice once, with Notify:Register(module, def), and publishes one with
-- Notify:Post(module, kind, n); this file knows no module.
--
--   def  = { label,   -- locale key of the module's name (the Notices page, the Settings card)
--            order,
--            feature, -- optional: a switch of Core/Features.lua; off, the module has no row in the Settings card
--            kinds,   -- array of { id, level, group, option, off, optIn }:
--                     --   level  "alert" | "normal" | "quiet" (quiet: history only, never an output)
--                     --   group  locale key of the text of many notices of this kind ("%d new bank requests")
--                     --   option key of UI/SettingsModel.lua that switches the kind (the two M5 bank options)
--                     --   off    locale key of the switch of a kind without `option` (account.settings.notify.<m>.off.<id>)
--                     --   optIn  true: off by default; its muted entries do not count in the login digest
--            outputs, -- optional: the outputs the module has, of OUTPUTS (default: all three)
--            open,    -- optional: function(entry), opens the view of an entry; the default opens entry.view
--            check }  -- optional: function(), called every TICK seconds and at the start (notices nothing announces)
--   n    = { key,     -- identity of the notice: an unread entry with the same key is updated, not repeated (NTF-07)
--            text,    -- locale key; args: at most ARGS strings or numbers, so the history reads in today's language
--            args, level (default: the kind's), view, page,
--            char,    -- the character the notice is for; nil = the whole account
--            still }  -- optional: function() -> false = the thing is gone, so a waiting notice does not come out
--
-- History: GuildKey:Data().notify = { list = { entry, ... oldest first }, n = last entry number, seen = { [module] = book } }.
-- An entry: { n, module, kind, level, text, args, view, page, key, time, char, read, muted, count }. At most MAX entries
-- and DAYS days (NTF-03). Nothing is marked read by itself.
-- Outputs, per module (account.settings.notify.<module> = { chat, toast, sound }): a chat line, a toast of the addon
-- (UI/Toast.lua) and one game sound. Notices of one burst come out together after NOTICE_WAIT seconds (MAX_LINES chat
-- lines at most). A kind that is switched off, or whose module has no output on, is kept as `muted` (NTF-01).
-- Floods: NTF-05 from the login until HELLO_WAIT seconds after the first HELLO (LOGIN_MAX at most) the notices are
-- grouped per kind and come out at the end of that window; NTF-06 more than BURST of a kind in BURST_SECONDS become one
-- entry; NTF-08 at most SESSION_MAX notices come out per session.
-- Quiet hours (SPEC-13 §4, M9.4): nothing comes out while the player fights, is in an instance (account.settings.quiet
-- .instances) or inside their quiet hours (local time, .on, .from, .to). A held notice is in the history at once and
-- stays in the queue; when nothing holds any more (RELEASE_COMBAT / RELEASE_INSTANCE seconds after the event, the TICK
-- check for the end of the hours) the held ones come out once, in order of arrival, as one burst with one toast; one that
-- was read, is gone (`still`) or waited more than HELD_MAX seconds stays in the history only. The queue is of the
-- session: after a /reload or a logout the held notices are only in the history.
-- While the switch `actions` is off (Core/Features.lua) nothing here writes, prints or listens: the bank notices of M5
-- are printed by Data/BankInbox.lua as before.
-- Bus: NOTICE_POSTED(entry) a new entry; NOTICES_CHANGED() the history changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Notify = {}
ns.Notify, ns.modules = Notify, ns.modules or {}
ns.modules.Notify = Notify

local type, pairs, ipairs, tostring, pcall, unpack = type, pairs, ipairs, tostring, pcall, unpack
local min, sort, remove = math.min, table.sort, table.remove

Notify.FEATURE = "actions"
Notify.OUTPUTS = { "chat", "toast", "sound" }
Notify.LEVELS = { quiet = 1, normal = 2, alert = 3 }
Notify.NOTICE_WAIT = 3        -- seconds a notice waits for the rest of its burst
Notify.MAX_LINES = 3
Notify.MAX = 200              -- NTF-03
Notify.DAYS = 30
Notify.ARGS = 4
Notify.HELLO_WAIT = 120       -- NTF-05
Notify.LOGIN_MAX = 300
Notify.BURST = 20             -- NTF-06
Notify.BURST_SECONDS = 60
Notify.SESSION_MAX = 30       -- NTF-08
Notify.SOUND_GAP = 10
Notify.TICK = 60
Notify.RELEASE_COMBAT = 3     -- QUI-03: seconds from the end of combat to the release
Notify.RELEASE_INSTANCE = 5   -- the same after leaving an instance
Notify.HELD_MAX = 12 * 3600
Notify.INSTANCES = { party = true, raid = true, pvp = true, arena = true, scenario = true }
Notify.PREFIX = "|cffd4af37Accord:|r "

Notify.modules_ = {}          -- id -> def
Notify.errorCount = 0

local state
local function fresh(old)
	return {
		pending = {}, timer = nil,                 -- pending: { entry, still, held = server time or nil }, in order
		waiting = {},                              -- of WhenFree: { fn, held = server time }, in order
		serial = old and old.serial or 0,          -- of the flush timers: only the last one armed flushes
		fighting = old and old.fighting or false,  -- between PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED
		window = nil,                              -- { limit, ends, hello, groups = { [m.k] = group }, order = {} }
		bursts = {},                               -- [m.k] = { times, entries, group }
		sent = old and old.sent or 0,              -- outputs of the session
		saidMore = old and old.saidMore or false,
		lastSound = old and old.lastSound,
		ticker = old and old.ticker,
		epoch = (old and old.epoch or 0) + 1,
	}
end
state = fresh()

local function compat() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function serverTime() return compat().ServerTime() end
local function clock() return compat().Now() end

function Notify.Enabled()
	return ns.Features ~= nil and ns.Features.On(Notify.FEATURE)
end

---------------------------------------------------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------------------------------------------------
function Notify:Register(id, def)
	if type(id) ~= "string" or id == "" or type(def) ~= "table" or type(def.kinds) ~= "table" then return false end
	def.id, def.order, def.byKind = id, def.order or 100, {}
	for _, k in ipairs(def.kinds) do def.byKind[k.id] = k end
	self.modules_[id] = def
	return true
end

function Notify:Module(id) return self.modules_[id] end

-- The registered modules, in their order.
function Notify:Modules()
	local out = {}
	for _, def in pairs(self.modules_) do out[#out + 1] = def end
	sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.id < b.id
	end)
	return out
end

-- Whether a module has any notice that can come out (a quiet one never does).
function Notify.HasOutputs(def)
	for _, k in ipairs(def.kinds) do if k.level ~= "quiet" then return true end end
	return false
end

local function settings(module)
	local all = ns.Config and ns.Config:Get("account.settings.notify")
	local t = type(all) == "table" and all[module] or nil
	return type(t) == "table" and t or {}
end

-- The saved choice of an output of a module.
function Notify:Output(module, output)
	return settings(module)[output] == true
end

-- false when the player switched this kind off.
function Notify:Wanted(module, kind)
	local def = self.modules_[module]
	local k = def and def.byKind[kind]
	if not k then return false end
	if k.option then
		local M = ns.SettingsModel
		return M == nil or M.Get(k.option) ~= false
	end
	local off = settings(module).off
	return not (type(off) == "table" and off[kind] == true)
end

local function anyOutput(module)
	for _, o in ipairs(Notify.OUTPUTS) do
		if Notify:Output(module, o) then return true end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- The history
---------------------------------------------------------------------------------------------------------------------
local function book(create)
	if not Notify.Enabled() then return nil end
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.notify) ~= "table" then
		if not create then return nil end
		data.notify = {}
	end
	local b = data.notify
	if type(b.list) ~= "table" then b.list = {} end
	if type(b.seen) ~= "table" then b.seen = {} end
	if type(b.n) ~= "number" then b.n = 0 end
	return b
end

-- What a module has already announced in this guild (its own table, kept by Clear guild data). The bank notices of M5
-- (GuildKey:Data().bank.seen) move here the first time, so nothing already announced comes back as new.
function Notify:Seen(module)
	local b = book(true)
	if not b then return nil end
	if type(b.seen[module]) ~= "table" then b.seen[module] = {} end
	local seen = b.seen[module]
	if module == "bank" then
		local data = ns.GuildKey:Data()
		local old = type(data.bank) == "table" and data.bank.seen
		if type(old) == "table" then
			for id, status in pairs(old) do
				if seen[id] == nil then seen[id] = status end
			end
			data.bank.seen = nil
		end
	end
	return seen
end

-- NTF-03: the entries older than DAYS go, then the oldest above MAX. Returns how many went.
local function prune(b)
	local list, limit, gone = b.list, serverTime() - Notify.DAYS * 86400, 0
	for i = #list, 1, -1 do
		if type(list[i]) ~= "table" or (list[i].time or 0) < limit then
			remove(list, i)
			gone = gone + 1
		end
	end
	while #list > Notify.MAX do
		remove(list, 1)
		gone = gone + 1
	end
	return gone
end

local function indexOf(list, entry)
	for i = #list, 1, -1 do
		if list[i] == entry then return i end
	end
	return nil
end

local function mine(entry)
	if entry.char == nil then return true end
	return entry.char == (compat() and compat().Player.GUID())
end

-- The entries of the connected character and of the whole account, the newest first.
function Notify:Entries(unreadOnly)
	local out, b = {}, book(false)
	if not b then return out end
	prune(b)
	for i = #b.list, 1, -1 do
		local e = b.list[i]
		if mine(e) and not (unreadOnly and e.read) then out[#out + 1] = e end
	end
	return out
end

function Notify:Unread() return #self:Entries(true) end

-- The unread entry with this key, or nil.
function Notify:Find(module, key)
	local b = book(false)
	if not (b and key) then return nil end
	for i = #b.list, 1, -1 do
		local e = b.list[i]
		if e.module == module and e.key == key and not e.read then return e end
	end
	return nil
end

function Notify:MarkRead(entry)
	if type(entry) ~= "table" or entry.read then return false end
	entry.read = true
	emit("NOTICES_CHANGED")
	return true
end

function Notify:MarkAllRead()
	local list = self:Entries(true)
	for _, e in ipairs(list) do e.read = true end
	if #list > 0 then emit("NOTICES_CHANGED") end
	return #list
end

-- Empties the history; what was announced stays announced.
function Notify:Clear()
	local b = book(false)
	if not b then return false end
	b.list = {}
	state.pending, state.bursts = {}, {}
	if state.window then state.window.groups, state.window.order = {}, {} end
	emit("NOTICES_CHANGED")
	return true
end

-- The text of an entry in the language of today.
function Notify.Text(entry)
	if type(entry) ~= "table" or type(entry.text) ~= "string" then return "" end
	local ok, text = pcall(function() return ns.L[entry.text]:format(unpack(entry.args or {})) end)
	return ok and text or entry.text
end

-- A click on a notice: it is read, and its view opens.
function Notify:Open(entry)
	if type(entry) ~= "table" then return false end
	self:MarkRead(entry)
	local def = self.modules_[entry.module]
	if def and def.open then
		local ok = pcall(def.open, entry)
		if not ok then Notify.errorCount = Notify.errorCount + 1 end
		return ok
	end
	if entry.view and ns.Shell then return ns.Shell:OpenView(entry.view) and true or false end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Outputs
---------------------------------------------------------------------------------------------------------------------
local function stillThere(item)
	if not item.still then return true end
	local ok, yes = pcall(item.still)
	return not ok or yes ~= false
end

local function say(text) compat().ChatLine(Notify.PREFIX .. text) end

---------------------------------------------------------------------------------------------------------------------
-- Quiet hours (SPEC-13 §4)
---------------------------------------------------------------------------------------------------------------------
-- Whether `hour` is in [from, to), also across midnight.
function Notify.InHours(hour, from, to)
	if from < to then return hour >= from and hour < to end
	return hour >= from or hour < to
end

-- QUI-01: why notices are held now ("combat", "instance" or "hours"), or nil.
function Notify:Holding()
	if not Notify.Enabled() then return nil end
	if state.fighting or compat().InCombat() then return "combat" end
	local q = ns.Config and ns.Config:Get("account.settings.quiet")
	if type(q) ~= "table" then return nil end
	if q.instances == true then
		local inside, kind = compat().InInstance()
		if inside and Notify.INSTANCES[kind] then return "instance" end
	end
	if q.on == true then
		local hour = compat().LocalHour()
		if hour and Notify.InHours(hour, q.from, q.to) then return "hours" end
	end
	return nil
end

local function flush()
	state.timer = nil
	if #state.pending == 0 or not Notify.Enabled() then return end
	if Notify:Holding() then   -- they stay in the queue, in order
		local t = serverTime()
		for _, item in ipairs(state.pending) do item.held = item.held or t end
		return
	end
	local items = state.pending
	state.pending = {}
	local lines, toasts, sound, over, released = {}, {}, nil, false, false
	for _, item in ipairs(items) do
		local e = item.entry
		local late = item.held ~= nil and serverTime() - item.held > Notify.HELD_MAX
		released = released or item.held ~= nil
		if not late and not e.muted and not e.read and anyOutput(e.module) and stillThere(item) then
			if state.sent >= Notify.SESSION_MAX then
				over = true
			else
				state.sent = state.sent + 1
				if Notify:Output(e.module, "chat") then lines[#lines + 1] = Notify.Text(e) end
				if Notify:Output(e.module, "toast") then toasts[#toasts + 1] = e end
				if Notify:Output(e.module, "sound") and (not sound or Notify.LEVELS[e.level] > Notify.LEVELS[sound]) then
					sound = e.level
				end
			end
		end
	end
	for i = 1, min(#lines, Notify.MAX_LINES) do say(lines[i]) end
	if #lines > Notify.MAX_LINES then say(ns.L["NOTICE_MORE"]:format(#lines - Notify.MAX_LINES)) end
	if over and not state.saidMore then
		state.saidMore = true
		say(ns.L["NOTICE_SESSION_MORE"])
	end
	if released and #toasts > 1 then   -- QUI-03: one toast, the last alert (without one, the last)
		local one = toasts[#toasts]
		for i = #toasts, 1, -1 do
			if toasts[i].level == "alert" then one = toasts[i] break end
		end
		toasts = { one }
	end
	if ns.Toast then
		ns.Toast:Resume()
		for _, e in ipairs(toasts) do ns.Toast:Push(e) end
	end
	if sound and (not state.lastSound or clock() - state.lastSound >= Notify.SOUND_GAP) then
		state.lastSound = clock()
		compat().Sound.Play(sound)
	end
end

local function queue(entry, still)
	if entry.muted or entry.level == "quiet" then return end
	state.pending[#state.pending + 1] = { entry = entry, still = still }
	if state.timer then return end
	state.serial = state.serial + 1
	local epoch, id = state.epoch, state.serial
	state.timer = id
	local scheduled = compat().After(Notify.NOTICE_WAIT, function()
		if epoch == state.epoch and state.timer == id then flush() end
	end)
	if not scheduled then flush() end
end

-- Runs what waited in WhenFree, in order; what waited more than HELD_MAX seconds is dropped, like a notice.
local function runWaiting()
	local list = state.waiting
	state.waiting = {}
	for _, item in ipairs(list) do
		if serverTime() - item.held <= Notify.HELD_MAX then
			local ok = pcall(item.fn)
			if not ok then Notify.errorCount = Notify.errorCount + 1 end
		end
	end
end

-- For an output that is not a notice of the history (the login digest, SPEC-13 §5): `fn` runs now, or, while notices are
-- held, once at the release, after the held ones.
function Notify:WhenFree(fn)
	if not Notify.Enabled() then return false end
	state.waiting[#state.waiting + 1] = { fn = fn, held = serverTime() }
	if not self:Holding() then runWaiting() end
	return true
end

-- QUI-03: lets the held notices out when nothing holds any more. True when it let notices out.
function Notify:Release()
	if not Notify.Enabled() or self:Holding() then return false end
	if ns.Toast then ns.Toast:Resume() end
	local out = false
	for _, item in ipairs(state.pending) do
		if item.held then
			flush()
			out = true
			break
		end
	end
	runWaiting()
	return out
end

local function releaseIn(seconds)
	local epoch = state.epoch
	compat().After(seconds, function() if epoch == state.epoch then Notify:Release() end end)
end

function Notify:OnCombat(fighting)
	if not Notify.Enabled() then return end
	state.fighting = fighting and true or false
	if not state.fighting then releaseIn(Notify.RELEASE_COMBAT) end
end

-- A loading screen or another area: the player may have left an instance.
function Notify:OnZone()
	if Notify.Enabled() then releaseIn(Notify.RELEASE_INSTANCE) end
end

local function unqueue(entry)
	for i = #state.pending, 1, -1 do
		if state.pending[i].entry == entry then remove(state.pending, i) end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Posting
---------------------------------------------------------------------------------------------------------------------
local function argsOf(list)
	local out = {}
	for i = 1, Notify.ARGS do
		local v = type(list) == "table" and list[i] or nil
		if type(v) ~= "string" and type(v) ~= "number" then break end
		out[i] = v
	end
	return out
end

local function add(b, entry)
	b.n = b.n + 1
	entry.n = b.n
	b.list[#b.list + 1] = entry
end

-- Turns `entry` into the group of its kind with `count` notices.
local function regroup(entry, k, count)
	entry.count, entry.text, entry.args, entry.key = count, k.group, { count }, nil
	entry.time = serverTime()
end

-- Moves an entry to the top of the history (it is the newest thing now).
local function bump(b, entry)
	local i = indexOf(b.list, entry)
	if i then remove(b.list, i) end
	b.list[#b.list + 1] = entry
end

-- NTF-05: inside the window after the login, one entry per kind (muted ones apart); it comes out when the window ends.
local function gather(b, k, entry, still, key)
	local w = state.window
	local id = entry.module .. "." .. entry.kind .. (entry.muted and ".muted" or "")
	local g = w.groups[id]
	if g and not g.entry.read and indexOf(b.list, g.entry) then
		if key == nil or not g.keys[key] then
			if key then g.keys[key] = true end
			regroup(g.entry, k, (g.entry.count or 1) + 1)
			g.still = nil
			bump(b, g.entry)
		end
		return g.entry, false
	end
	add(b, entry)
	g = { entry = entry, still = still, keys = {} }
	if key then g.keys[key] = true end
	w.groups[id] = g
	w.order[#w.order + 1] = g
	return entry, true
end

-- NTF-06: more than BURST notices of one kind in BURST_SECONDS become one entry.
local function burst(b, k, entry, still)
	local id = entry.module .. "." .. entry.kind .. (entry.muted and ".muted" or "")
	local s = state.bursts[id]
	local t = clock()
	if not s or t - s.last > Notify.BURST_SECONDS then
		s = { times = {}, entries = {} }
		state.bursts[id] = s
	end
	while s.times[1] and t - s.times[1] > Notify.BURST_SECONDS do
		remove(s.times, 1)
		remove(s.entries, 1)
	end
	s.last = t
	s.times[#s.times + 1] = t
	if s.group and not s.group.read and indexOf(b.list, s.group) then
		s.entries[#s.entries + 1] = false
		regroup(s.group, k, s.group.count + 1)
		bump(b, s.group)
		return s.group, false
	end
	s.group = nil
	s.entries[#s.entries + 1] = entry
	if #s.times <= Notify.BURST then
		add(b, entry)
		queue(entry, still)
		return entry, true
	end
	local count = 1
	for i, e in ipairs(s.entries) do
		if e and e ~= entry and not e.read then
			local at = indexOf(b.list, e)
			if at then
				remove(b.list, at)
				unqueue(e)
				count = count + 1
			end
		end
		s.entries[i] = false
	end
	regroup(entry, k, count)
	add(b, entry)
	s.group = entry
	queue(entry)
	return entry, true
end

-- Publishes a notice. Returns its entry, or nil when the switch is off, the guild is unknown or the notice is not well
-- formed.
function Notify:Post(module, kind, n)
	local def = self.modules_[module]
	local k = def and def.byKind[kind]
	if not (k and type(n) == "table" and type(n.text) == "string") then return nil end
	local b = book(true)
	if not b then return nil end
	local level = Notify.LEVELS[n.level] and n.level or k.level
	local key = type(n.key) == "string" and n.key or nil
	local old = key and self:Find(module, key)
	if old then   -- NTF-07: the same thing again
		old.text, old.args, old.level, old.view, old.page = n.text, argsOf(n.args), level, n.view, n.page
		old.time = serverTime()
		bump(b, old)
		emit("NOTICES_CHANGED")
		return old
	end
	local entry = {
		module = module, kind = kind, level = level, text = n.text, args = argsOf(n.args), view = n.view, page = n.page,
		key = key, char = n.char, time = serverTime(),
		muted = (level ~= "quiet" and not (self:Wanted(module, kind) and anyOutput(module))) or nil,
	}
	local isNew
	if state.window and clock() < state.window.ends then
		entry, isNew = gather(b, k, entry, n.still, key)
	else
		entry, isNew = burst(b, k, entry, n.still)
	end
	prune(b)
	if isNew then emit("NOTICE_POSTED", entry) end
	emit("NOTICES_CHANGED")
	return entry
end

---------------------------------------------------------------------------------------------------------------------
-- The window after the login, the checks
---------------------------------------------------------------------------------------------------------------------
local function closeWindow()
	local w = state.window
	if not w then return end
	state.window = nil
	for _, g in ipairs(w.order) do queue(g.entry, g.still) end
end

local function armWindow()
	local w, epoch = state.window, state.epoch
	local ends = w.ends
	compat().After(ends - clock(), function()
		if epoch == state.epoch and state.window == w and w.ends == ends then closeWindow() end
	end)
end

function Notify:OnLogin()
	if not Notify.Enabled() then return end
	local limit = clock() + Notify.LOGIN_MAX
	state.window = { limit = limit, ends = limit, groups = {}, order = {} }
	armWindow()
end

-- The first HELLO of the login shortens the window.
function Notify:OnHello()
	local w = state.window
	if not w or w.hello then return end
	w.hello = true
	w.ends = min(w.limit, clock() + Notify.HELLO_WAIT)
	armWindow()
end

function Notify:Check()
	if not (Notify.Enabled() and ns.GuildKey and ns.GuildKey:Current()) then return end
	self:Release()   -- the quiet hours end with no event
	for _, def in ipairs(self:Modules()) do
		if def.check then
			local ok = pcall(def.check)
			if not ok then Notify.errorCount = Notify.errorCount + 1 end
		end
	end
end

function Notify:Start()
	if not Notify.Enabled() then return end
	if not state.ticker then state.ticker = compat().NewTicker(Notify.TICK, function() Notify:Check() end) end
	self:Check()
end

-- Another guild: what waited belongs to the old one. The window of the login stays open.
function Notify:Reset()
	local window = state.window
	state = fresh(state)
	if window then
		window.groups, window.order = {}, {}
		state.window = window
		armWindow()
	end
	if ns.Toast then ns.Toast:Reset() end
end

-- Counts only: never a name or a text.
function Notify:DebugLines()
	return { ("Notify: %d entr(ies), %d unread, %d waiting, %d sent this session, login window %s, held by %s, %d error(s)"):format(
		#self:Entries(), self:Unread(), #state.pending, state.sent, state.window and "open" or "closed",
		self:Holding() or "nothing", self.errorCount) }
end

if ns.addon then
	ns.addon.Notify = Notify
	if ns.Bus then
		ns.Bus:On("SYNC_HELLO", function(sent) if sent then Notify:OnHello() end end)
		ns.Bus:On("CONFIG_CHANGED", function(path)
			if type(path) == "string" and path:find("account.settings.quiet.", 1, true) == 1 then Notify:Release() end
		end)
		ns.Bus:On("GUILD_CHANGED", function(key)
			Notify:Reset()
			if Notify.Enabled() then
				if key then Notify:Check() end
				emit("NOTICES_CHANGED")
			end
		end)
	end
	LibStub("AceEvent-3.0"):Embed(Notify)
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Notify.Enabled() then return end
			-- NTF-05 is about a login (PLAYER_ENTERING_WORLD follows PLAYER_LOGIN): a /reload opens no window
			Notify:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin)
				if isLogin then Notify:OnLogin() end
				state.fighting = compat().InCombat()
				Notify:OnZone()
			end)
			Notify:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Notify:OnZone() end)
			Notify:RegisterEvent("PLAYER_REGEN_DISABLED", function() Notify:OnCombat(true) end)
			Notify:RegisterEvent("PLAYER_REGEN_ENABLED", function() Notify:OnCombat(false) end)
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Notify", function() return Notify:DebugLines() end) end
			Notify:Start()
		end)
	end
end

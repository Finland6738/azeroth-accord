-- Onboarding: the welcome checklist of a new member (M12.4; SPEC-16 §5, ONB-01..ONB-04; ADR 0026). Lua 5.1.
--
-- Only on this computer: nothing here writes a record or sends a message, and officers see nothing (SPEC-10 Q36). It reads
-- data the client already holds. Kept in GuildKey:Data().onboarding[GUID]:
--   { none = true }                          the character is not new: never checked again
--   { joined, how = "seen" | "log",          the join is known (ONB-01): this client saw the character's guild change, or
--     known?, done = { [item] = time },      the game's guild log says so; `known` once the client holds a record of
--     dismissed?, notified?, completed? }    another account older than the join (ONB-02): only then is the member new
--
--   Onboarding:Entry()          the entry of this character in this guild, or nil
--   Onboarding:Active()         true while the list shows by itself: new, not dismissed, at most SHOW_DAYS after the join,
--                               and not completed in an earlier session
--   Onboarding:Items()          the items that can be done in this guild, in order: { { id, done, target? } }; once ticked
--                               an item stays ticked (ONB-04)
--   Onboarding:Progress(items)  done, shown
--   Onboarding:Dismiss()        closes the list for good for this character
--   Onboarding:Refresh()        confirms, ticks, says the chat line once; ONBOARDING_CHANGED when something changed
--   Onboarding:Joined(guid, from, to)  the character's guild changed on this client (Data/Accounts.lua)
--   Onboarding:Start()          reads the guild log LOG_DELAY after the first login in a guild without an entry
-- Switch: Core/Features.lua "recruit" (M12). The items ask "raid" and "season" themselves.
local ADDON_NAME, ns = ...
ns = ns or {}
local Onboarding = {}
ns.Onboarding, ns.modules = Onboarding, ns.modules or {}
ns.modules.Onboarding = Onboarding

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local concat = table.concat

local DAY = 86400
Onboarding.NEW_DAYS = 14        -- a join of the guild log this recent counts (ONB-01)
Onboarding.SHOW_DAYS = 30       -- the list goes away this long after the join
Onboarding.LOG_DELAY = 60       -- seconds after the first login in the guild before the guild log is read
Onboarding.LOG_WAIT = 10        -- seconds given to the server to answer QueryGuildEventLog
Onboarding.KNOWN_MARGIN = 60    -- guild data older than this at the join: the account already knew the guild
Onboarding.DELAY = 0.5          -- seconds the events are collected before the list is read again
Onboarding.PAGES = { "info", "rules" }
Onboarding.ITEMS = { "read", "main", "discord", "season" }

local state = { finished = {}, scanned = setmetatable({}, { __mode = "k" }), timer = false, reading = {}, announcing = {},
	print = "" }

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function me() return compat() and compat().Player.GUID() end
local function on(name) return ns.Features ~= nil and ns.Features.On(name) end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

function Onboarding.Enabled() return on("recruit") end

local function guildKey()
	if not (ns.Role and ns.Role:InGuild() and ns.GuildKey) then return nil end
	return ns.GuildKey:Current()
end

-- The table of the entries of guild `key`, and the guild's data; nil without them.
local function list(key)
	local data = key and ns.GuildKey:Data(key)
	if not data then return nil end
	if type(data.onboarding) ~= "table" then data.onboarding = {} end
	return data.onboarding, data
end

local function held(key, guid)
	local entries = list(key)
	local e = entries and guid and entries[guid]
	return type(e) == "table" and e or nil
end

function Onboarding:Entry()
	if not Onboarding.Enabled() then return nil end
	return held(guildKey(), me())
end

local function candidate(e) return e ~= nil and e.none ~= true and type(e.joined) == "number" end

-- New, open and recent: what is common to the checks and to Active().
local function open(e, key)
	if not candidate(e) or e.dismissed then return false end
	if now() - e.joined > Onboarding.SHOW_DAYS * DAY then return false end
	return e.completed == nil or state.finished[key] == true
end

function Onboarding:Active()
	local e = self:Entry()
	return e ~= nil and e.known == true and open(e, guildKey())
end

---------------------------------------------------------------------------------------------------------------------
-- Who is new (SPEC-16 §5.1)
---------------------------------------------------------------------------------------------------------------------
local function ownChars()
	local db = ns.Config and ns.Config.db.account
	local out = {}
	for _, chars in pairs(db and type(db.chars) == "table" and db.chars or {}) do
		if type(chars) == "table" then
			for guid, e in pairs(chars) do
				if type(e) == "table" then out[guid] = e end
			end
		end
	end
	return out
end

-- ONB-03: another character of the account was in this guild before the join.
local function isAlt(guid, key, joined)
	for other, e in pairs(ownChars()) do
		if other ~= guid and e.guild == key then
			local since = e.guildSince or e.guildAt
			if type(since) == "number" and since < joined then return true end
		end
	end
	return false
end

-- ONB-02: a record of another account of the guild, written before the join.
local function older(rec, joined, mine, guid)
	if type(rec) ~= "table" or type(rec.time) ~= "number" or rec.time >= joined then return false end
	local author = rec.author
	if type(author) ~= "string" or author == guid or mine[author] then return false end
	return not ns.Store:SameAccount(guid, author)
end

local function addonWasThere(e, guid)
	local S = ns.Store
	if not S then return false end
	local mine = ownChars()
	for _, set in ipairs(S.SET_ORDER) do
		for _, rec in pairs(S:Records(set) or {}) do
			if older(rec, e.joined, mine, guid) then return true end
		end
	end
	return false
end

local function write(key, guid, joined, how)
	local entries = list(key)
	if not entries then return end
	if joined == nil or isAlt(guid, key, joined) then
		entries[guid] = { none = true }
	else
		entries[guid] = { joined = joined, how = how, done = {} }
	end
	Onboarding:Changed()
end

-- ONB-01, "seen": the guild this client held for the character was another one, or none, and now is this one. Guild data
-- the account already had says it knew the guild before: not a first join (also a "no guild" read before the game was
-- ready never makes an old member new).
function Onboarding:Joined(guid, from, to)
	if not Onboarding.Enabled() or guid ~= me() or type(from) ~= "string" or type(to) ~= "string" or to == "" or from == to then
		return false
	end
	if to ~= guildKey() or held(to, guid) then return false end
	local _, data = list(to)
	if not data then return false end
	local t = now()
	local knew = type(data.firstSeen) == "number" and data.firstSeen < t - Onboarding.KNOWN_MARGIN
	if knew then write(to, guid, nil) else write(to, guid, t, "seen") end
	return true
end

-- The seconds since this character joined, from the guild log: the most recent "join" of its name, or nil.
local function loggedJoin()
	local C = compat()
	local name = C.Player.Name()
	local want = name and (C.SplitName(name)):lower()
	local best
	for _, ev in ipairs(want and C.Guild.EventLog() or {}) do
		if ev.type == "join" and ev.name and (C.SplitName(ev.name)):lower() == want then
			local age = ev.hours * 3600
			if not best or age < best then best = age end
		end
	end
	return best
end

local function readLog(key, guid)
	if not Onboarding.Enabled() or guildKey() ~= key or me() ~= guid or held(key, guid) then return end
	local age = loggedJoin()
	if age and age <= Onboarding.NEW_DAYS * DAY then write(key, guid, now() - age, "log") else write(key, guid, nil) end
end

-- ONB-01, "log": read once, for a character of this guild without an entry. Without the game's functions the sign is
-- missing and only "seen" is left.
function Onboarding:Start()
	if not Onboarding.Enabled() then return false end
	local key, guid = guildKey(), me()
	if not (key and guid) then return false end
	self:Changed()
	if held(key, guid) or state.reading[key] then return false end
	state.reading[key] = true
	compat().After(Onboarding.LOG_DELAY, function()
		if guildKey() ~= key or held(key, guid) then state.reading[key] = nil return end
		if not compat().Guild.QueryEventLog() then
			state.reading[key] = nil
			readLog(key, guid)
			return
		end
		compat().After(Onboarding.LOG_WAIT, function()
			state.reading[key] = nil
			readLog(key, guid)
		end)
	end)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The items (SPEC-16 §5.2)
---------------------------------------------------------------------------------------------------------------------
local checks = {}

-- Both pages that exist and are published, read by this account; the target is the first unread one.
checks.read = function()
	local H = ns.Handbook
	if not (on("raid") and H) then return nil end
	local byId = {}
	for _, rec in ipairs(H:Pages()) do byId[rec.id] = rec end
	local found, unread, first = 0, nil, nil
	for _, slug in ipairs(Onboarding.PAGES) do
		local rec = byId[H.PageId(slug)]
		if rec then
			found = found + 1
			first = first or rec.id
			if not unread and H:IsUpdated(rec) then unread = rec.id end
		end
	end
	if found == 0 then return nil end
	return { done = unread == nil, target = unread or first }
end

checks.main = function()
	local A = ns.Accounts
	if not A then return nil end
	local _, source = A:Main()
	return { done = source == "chosen" or #A:OwnChars() == 1 }
end

checks.discord = function()
	local C = ns.Contacts
	if not C then return nil end
	local contact = C:Of(me())
	return { done = C:OwnDiscord() ~= nil or (contact ~= nil and contact.discord ~= nil) }
end

checks.season = function()
	local Season = ns.Season
	if not (on("season") and Season) then return nil end
	local source = Season.Source()
	if source == "accord" then
		local cur = Season:Current()
		if not cur then return nil end
		return { done = Season:Own(cur.n) ~= nil, target = "accord" }
	end
	local F = ns.FDCP
	if not (F and source == F.ID and F.API() and F.Ready()) then return nil end
	local season = F.Season()
	if not season or season.state == "CLOSED" then return nil end
	local done = false
	for _, c in ipairs(ns.Accounts and ns.Accounts:OwnChars() or {}) do
		if F.Member(c.name) then done = true break end
	end
	return { done = done, target = "fdcp" }
end

function Onboarding:Items()
	local out = {}
	if not (Onboarding.Enabled() and guildKey() and me()) then return out end
	local e = self:Entry()
	local done = e and type(e.done) == "table" and e.done or {}
	for _, id in ipairs(Onboarding.ITEMS) do
		local item = checks[id]()
		if item then
			item.id = id
			if done[id] then item.done = true end
			out[#out + 1] = item
		end
	end
	return out
end

function Onboarding:Progress(items)
	items = items or self:Items()
	local n = 0
	for _, item in ipairs(items) do if item.done then n = n + 1 end end
	return n, #items
end

---------------------------------------------------------------------------------------------------------------------
-- Keeping it up to date
---------------------------------------------------------------------------------------------------------------------
-- The chat line, once (after the quiet hours when something holds the notices).
local function announce(key, guid)
	if state.announcing[key] then return end
	state.announcing[key] = true
	local function say()
		state.announcing[key] = nil
		local e = held(key, guid)
		if guildKey() ~= key or me() ~= guid or not e or e.notified or not open(e, key) then return end
		e.notified = true
		local _, name = ns.GuildKey.Split(key)
		if ns.addon then ns.addon:Print(ns.L["WELCOME_CHAT"]:format((tostring(name):gsub("|", "||")))) end
	end
	if not (ns.Notify and ns.Notify:WhenFree(say)) then say() end
end

function Onboarding:Refresh()
	local key, guid = guildKey(), me()
	local e = self:Entry()
	local line = ""
	if e and open(e, key) then
		-- the whole store once per entry and session; what arrives later comes one record at a time (STORE_CHANGED)
		if not e.known and not state.scanned[e] then
			state.scanned[e] = true
			if addonWasThere(e, guid) then e.known = true end
		end
		if e.known then
			if type(e.done) ~= "table" then e.done = {} end
			local items = self:Items()
			local parts = { key }
			for _, item in ipairs(items) do
				if item.done and not e.done[item.id] then e.done[item.id] = now() end
				parts[#parts + 1] = item.id .. (item.done and "+" or "-")
			end
			local done, shown = self:Progress(items)
			if shown > 0 and done == shown then
				if e.completed == nil then e.completed, state.finished[key] = now(), true end
			elseif not e.notified then
				announce(key, guid)
			end
			line = concat(parts, " ")
		end
	end
	if line ~= state.print then
		state.print = line
		emit("ONBOARDING_CHANGED")
	end
end

-- Something changed: one read after the burst.
function Onboarding:Changed()
	if state.timer or not Onboarding.Enabled() then return end
	state.timer = true
	local scheduled = compat() and compat().After(Onboarding.DELAY, function()
		state.timer = false
		Onboarding:Refresh()
	end)
	if not scheduled then state.timer = false self:Refresh() end
end

function Onboarding:Dismiss()
	local e = self:Entry()
	if not candidate(e) or e.dismissed then return false end
	e.dismissed = now()
	state.print = ""
	emit("ONBOARDING_CHANGED")
	return true
end

-- The Action Center row (urgency 1) while the list is open and something is left to do.
function Onboarding:ActionRows()
	local rows = {}
	if not self:Active() then return rows end
	local done, shown = self:Progress()
	if done >= shown then return rows end
	rows[1] = { key = "welcome", urgency = 1, time = self:Entry().joined, mark = done,
		title = ns.L["WELCOME_ROW"]:format(done, shown),
		open = function() if ns.OnboardingView then ns.OnboardingView:ShowList() end end }
	return rows
end

-- The sign used and whether the game has the guild log (SPEC-16 §8): never a name.
function Onboarding:DebugLine()
	local e = self:Entry()
	local sign = not e and "not checked" or e.none and "none" or tostring(e.how)
	return ("  welcome: sign %s%s%s, guild log functions %s"):format(sign,
		candidate(e) and (e.known and ", new member" or ", no older record yet") or "",
		self:Active() and ", list open" or "",
		compat().Guild.HasEventLog() and "yes" or "no")
end

if ns.Actions then
	ns.Actions:Register("welcome", { label = "ACT_PROVIDER_WELCOME", order = 3, feature = "recruit",
		visible = function() return Onboarding:Active() end,
		events = { "ONBOARDING_CHANGED" },
		items = function() return Onboarding:ActionRows() end })
end

if ns.addon then
	ns.addon.Onboarding = Onboarding
	if ns.Bus then
		ns.Bus:On("CHARACTER_GUILD_CHANGED", function(guid, from, to) Onboarding:Joined(guid, from, to) end)
		ns.Bus:On("GUILD_CHANGED", function()
			state.print = ""
			Onboarding:Start()
			emit("ONBOARDING_CHANGED")
		end)
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if not Onboarding.Enabled() then return end
			-- ONB-02 asks about the one record that arrived: the whole store is read only by Refresh
			local e = Onboarding:Entry()
			if candidate(e) and not e.known and id ~= nil
				and older(ns.Store:Get(set, id), e.joined, ownChars(), me()) then
				e.known = true
			end
			Onboarding:Changed()
		end)
		for _, event in ipairs({ "HANDBOOK_READ", "HANDBOOK_CHANGED", "ACCOUNTS_UPDATED", "SETTINGS_CHANGED", "CONFIG_CHANGED",
			"SEASON_CHANGED", "SOURCES_CHANGED", "FDCP_CHANGED", "ROSTER_UPDATED" }) do
			ns.Bus:On(event, function() Onboarding:Changed() end)
		end
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Onboarding.Enabled() then return end
			if ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Welcome", function() return { Onboarding:DebugLine() } end)
			end
			Onboarding:Start()
		end)
	end
end

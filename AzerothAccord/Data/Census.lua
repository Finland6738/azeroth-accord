-- Census: the addon census, which addons the guild's members have loaded (SPEC-13 §8, M9.9; SPEC-10 Q11, Q17). Lua 5.1.
--
-- What is shared   CEN-01: the LOADED addons of this character, read through Compat.Addon.Loaded (C_AddOns): the folder
--                  name (at most FOLDER_MAX), the version (at most VERSION_MAX, else none) and the title without colour
--                  codes, icons and any other "|" sequence (at most TITLE_MAX characters, left out when it is the folder
--                  name). Blizzard's own addons (security "SECURE" or a folder "Blizzard_...") and addons that are not
--                  loaded are left out; Accord itself is in.
-- Record           the data set `addons` (Net/Store.lua): id = the character's GUID, author = a character of the same
--                  account, { l = { { folder, version, title }, ... } sorted by folder ("" = no version), more = how many
--                  were left out } or { del = true }. At most MAX_ENTRIES entries and the size limit of the set: the
--                  first ones by folder are kept. An ordinary set (first hand, officer relay, saved, summarised apart from
--                  the older sets: SPEC-13 §8.2); removed RETENTION seconds after it was written.
-- When it goes out CEN-03: a check FIRST_DELAY seconds after the first HELLO of a session, which publishes only when the
--                  list differs from the own record, or when that record is older than REFRESH_AGE; again RECHECK_DELAY
--                  seconds after an addon loads during the session, or after a record of this account arrives, at most once
--                  every RECHECK_EVERY seconds; and SWITCH_DELAY seconds after the player flips the switch (or imports a
--                  backup, which may carry it).
-- Switch off       "Share my addon list" (account.settings.shareAddons, on by default): every census record of this account
--                  that is still published gets one `del` record, then nothing more; an account that never published
--                  writes nothing. Switched on again, the next check publishes.
-- Counting         per account (the proved characters of Data/Accounts.lua): an account uses an addon when a record of one
--                  of its characters in the guild lists it (the newest one gives its version). The share is out of the
--                  accounts with at least one record: members without Accord, or who share nothing, are not known.
-- Who sees names   Q11: everybody sees the counts and the versions; WHO uses an addon only the officers and the Guild
--                  Master, and everybody their own account. Census.NAMES_VISIBLE_TO is the one place. It is a rule of the
--                  interface (Q17): the records reach the whole guild. :Summary() never holds a name; :Who() applies it.
-- Switch: Features.On("census") (Core/Features.lua), off until M9.10. Off: the addon list is not read, the set takes and
-- sends nothing (Store), no timer starts. Demo mode publishes nothing.
-- Bus: CENSUS_CHANGED() when what :Summary() or :Who() give may have changed, collected for EMIT_DELAY seconds.
local ADDON_NAME, ns = ...
ns = ns or {}
local Census = {}
ns.Census, ns.modules = Census, ns.modules or {}
ns.modules.Census = Census

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, random, max = math.floor, math.random, math.max
local byte, sort = string.byte, table.sort

local DAY = 86400
Census.SET = "addons"
Census.MAX_ENTRIES = 120
Census.FOLDER_MAX, Census.VERSION_MAX, Census.TITLE_MAX = 64, 40, 48
Census.RETENTION = 60 * DAY
Census.REFRESH_AGE = 30 * DAY
Census.FIRST_DELAY = { 60, 120 }
Census.RECHECK_DELAY = 60
Census.RECHECK_EVERY = 600
Census.SWITCH_DELAY = 5
Census.EMIT_DELAY = 1
Census.NAMES_VISIBLE_TO = "officers"     -- "officers" or "members" (SPEC-10 Q11, Q17): the one place

local state

local function resetState()
	for _, key in ipairs({ "first", "recheck", "switch" }) do
		if state and state[key] then state[key]:Cancel() end
	end
	state = { armed = false, lastCheck = nil, cache = nil, emitting = false,
		stats = { published = 0, unchanged = 0, withdrawn = 0 }, last = nil }
	Census.state = state
end
resetState()

local function compat() return ns.Compat end
local function store() return ns.Store end
local function serverTime() return compat().ServerTime() end
local function ownGUID() return compat().Player.GUID() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function demo() return ns.Demo ~= nil and ns.Demo:IsActive() end

function Census.Enabled() return ns.Features ~= nil and ns.Features.On("census") end

-- "Share my addon list": on unless the player switched it off (a damaged value counts as the default).
function Census.Sharing()
	local C = ns.Config
	return not (C and C.db and C.db.account and C:Get("account.settings.shareAddons") == false)
end

---------------------------------------------------------------------------------------------------------------------
-- What an entry may hold
---------------------------------------------------------------------------------------------------------------------
-- ASCII classes only: %s and %c follow the C locale, which may take a byte of a UTF-8 letter.
local BAD = "[%z\1-\31\127|]"

local function characters(text)
	local n = 0
	for i = 1, #text do
		local b = byte(text, i)
		if b < 128 or b >= 192 then n = n + 1 end
	end
	return n
end

-- At most `limit` UTF-8 characters of `text`, never cut inside one.
local function cut(text, limit)
	local n = 0
	for i = 1, #text do
		local b = byte(text, i)
		if b < 128 or b >= 192 then
			n = n + 1
			if n > limit then return text:sub(1, i - 1) end
		end
	end
	return text
end

-- A TOC text without the game's "|" sequences (colours, icons, links) and control characters, one space between words.
local function plain(text)
	local s = text:gsub("||", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
		:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|n", " "):gsub("|[%a]", ""):gsub(BAD, " ")
		:gsub(" +", " "):gsub("^ ", ""):gsub(" $", "")
	return s
end

function Census.ValidFolder(v)
	return type(v) == "string" and v ~= "" and #v <= Census.FOLDER_MAX and not v:find(BAD) and v:sub(1, 9) ~= "Blizzard_"
end

function Census.ValidVersion(v)
	return type(v) == "string" and v ~= "" and #v <= Census.VERSION_MAX and not v:find(BAD)
end

function Census.ValidTitle(v)
	return type(v) == "string" and v ~= "" and #v <= Census.TITLE_MAX * 4 and not v:find(BAD)
		and characters(v) <= Census.TITLE_MAX
end

-- The title as it is shared, or nil when nothing is left of it or it says no more than the folder name.
function Census.CleanTitle(title, folder)
	if type(title) ~= "string" then return nil end
	local s = cut(plain(title), Census.TITLE_MAX):gsub(" $", "")
	if s == "" or s == folder or not Census.ValidTitle(s) then return nil end
	return s
end

function Census.CleanVersion(version)
	if type(version) ~= "string" then return nil end
	local s = plain(version)
	return Census.ValidVersion(s) and s or nil
end

-- The entries to share from what Compat.Addon.Loaded gives: { { folder, version | "" | nil, title | nil }, ... } by folder.
function Census.Entries(list)
	local out, seen = {}, {}
	for _, a in ipairs(list or {}) do
		if a.security ~= "SECURE" and Census.ValidFolder(a.name) and not seen[a.name] then
			seen[a.name] = true
			local version, title = Census.CleanVersion(a.version), Census.CleanTitle(a.title, a.name)
			out[#out + 1] = { a.name, version or (title and "" or nil), title }
		end
	end
	sort(out, function(x, y) return x[1] < y[1] end)
	return out
end

-- The entries that fit one record of `guid`: the first ones, and how many were left out (nil: none).
function Census.Fit(entries, guid)
	local size = ns.Config.EstimateSize
	local limit = store().SETS[Census.SET].maxBytes
	local l = {}
	local used = size({ id = guid, author = guid, rev = 1, time = 0, l = l, more = 1 })
	for i, e in ipairs(entries) do
		local cost = size(i) + size(e) + 4
		if i > Census.MAX_ENTRIES or used + cost > limit then break end
		l[i] = e
		used = used + cost
	end
	local more = #entries - #l
	return l, more > 0 and more or nil
end

-- The owner rule of the set (Net/Store.lua): a character of the author's account, and every entry well formed.
function Census.ValidRecord(rec, s)
	s = s or store()
	if type(rec) ~= "table" or type(rec.id) ~= "string" or not rec.id:find(s.GUID_PATTERN) then return false end
	if not s:SameAccount(rec.id, rec.author) then return false end
	if rec.del ~= nil then return rec.del == true and rec.l == nil and rec.more == nil end
	local l, more = rec.l, rec.more
	if type(l) ~= "table" or #l > Census.MAX_ENTRIES then return false end
	local keys = 0
	for k in pairs(l) do
		if type(k) ~= "number" or k ~= floor(k) or k < 1 or k > #l then return false end
		keys = keys + 1
	end
	if keys ~= #l then return false end
	for i = 1, #l do
		local e = l[i]
		if type(e) ~= "table" or not Census.ValidFolder(e[1]) then return false end
		for k in pairs(e) do
			if k ~= 1 and k ~= 2 and k ~= 3 then return false end
		end
		if e[2] ~= nil and e[2] ~= "" and not Census.ValidVersion(e[2]) then return false end
		if e[3] ~= nil and not Census.ValidTitle(e[3]) then return false end
	end
	return more == nil or (type(more) == "number" and more == floor(more) and more >= 1 and more <= 100000)
end

function Census.Expired(rec, t)
	return (rec.time or 0) < t - Census.RETENTION
end

---------------------------------------------------------------------------------------------------------------------
-- Publishing
---------------------------------------------------------------------------------------------------------------------
-- The entries this character has loaded now, or nil when the client cannot list its addons.
function Census:Own()
	local C = compat()
	local list = C and C.Addon.Loaded()
	if not list then return nil end
	return Census.Entries(list)
end

local function sameList(rec, l, more)
	if rec.del == true or type(rec.l) ~= "table" or #rec.l ~= #l or rec.more ~= more then return false end
	for i, e in ipairs(l) do
		local old = rec.l[i]
		if type(old) ~= "table" or old[1] ~= e[1] or (old[2] or "") ~= (e[2] or "") or old[3] ~= e[3] then return false end
	end
	return true
end

local function done(ok, why)
	state.last = why or (ok and "published") or nil
	return ok, why
end

-- Takes every published census record of this account back (one `del` each). Returns true and how many, or false and
-- "nothing".
function Census:Withdraw()
	local S, me = store(), ownGUID()
	local ids = {}
	for id, rec in pairs(S:Records(Census.SET)) do
		if type(rec) == "table" and rec.del ~= true and S:SameAccount(me, id) then ids[#ids + 1] = id end
	end
	sort(ids)
	local n = 0
	for _, id in ipairs(ids) do
		if S:Put(Census.SET, id, { del = true }) then n = n + 1 end
	end
	if n == 0 then return done(false, "nothing") end
	state.stats.withdrawn = state.stats.withdrawn + n
	state.last = "withdrawn"
	return true, n
end

-- Brings the own record in step with the loaded addons, or takes it back when sharing is off. Returns true when it wrote,
-- or false and the reason: "off", "demo", "guild", "player", "api", "unchanged", "nothing", or a reason of Store:Put.
function Census:Publish()
	if not Census.Enabled() then return false, "off" end
	if demo() then return false, "demo" end
	local S = store()
	if not (S and ns.GuildKey and ns.GuildKey:Current()) then return done(false, "guild") end
	local me = ownGUID()
	if not me then return done(false, "player") end
	if not Census.Sharing() then return self:Withdraw() end
	local entries = self:Own()
	if not entries then return done(false, "api") end
	local l, more = Census.Fit(entries, me)
	local old = S:Get(Census.SET, me)
	if old and sameList(old, l, more) and serverTime() - (old.time or 0) <= Census.REFRESH_AGE then
		state.stats.unchanged = state.stats.unchanged + 1
		return done(false, "unchanged")
	end
	local rec, why = S:Put(Census.SET, me, { l = l, more = more })
	if not rec then return done(false, why) end
	state.stats.published = state.stats.published + 1
	return done(true)
end

local function between(r) return r[1] + (r[2] - r[1]) * random() end

local function schedule(key, seconds, fn)
	if state[key] then state[key]:Cancel() end
	state[key] = compat().NewTimer(seconds, function()
		state[key] = nil
		fn()
	end)
end

local function check()
	state.lastCheck = compat().Now()
	Census:Publish()
end

-- The first HELLO of a session (or of a new guild) starts the first check.
function Census:OnHello()
	if not Census.Enabled() or state.armed or demo() then return false end
	state.armed = true
	schedule("first", between(Census.FIRST_DELAY), check)
	return true
end

-- Something may have changed the list: look again, soon but not more often than RECHECK_EVERY. Nothing before the first
-- check has run (it will see the change).
function Census:Recheck()
	if not Census.Enabled() or not state.armed or state.first or state.recheck or demo() then return false end
	local wait = Census.RECHECK_DELAY
	if state.lastCheck then wait = max(wait, state.lastCheck + Census.RECHECK_EVERY - compat().Now()) end
	schedule("recheck", wait, check)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Counting (the read API of the view and of Data/Integrations.lua)
---------------------------------------------------------------------------------------------------------------------
-- The key of the account of a character.
local function accountOf(guid)
	return ns.Accounts and ns.Accounts:AccountKey(guid) or guid
end

local function inGuild(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	if e and not e.notInGuild then return e end
	return nil
end

-- { accounts = n, users = { [folder] = { [account] = { version, guids } } }, titles = { [folder] = title },
--   keys = { [account] = a character of it } }
local function build()
	if ns.Accounts then ns.Accounts:Groups() end   -- rebuilt first: it announces itself, which drops the cache
	local S, t = store(), serverTime()
	local list = {}
	for id, rec in pairs(S and S:Records(Census.SET) or {}) do
		if type(rec) == "table" and rec.del ~= true and type(rec.l) == "table" and not Census.Expired(rec, t) and inGuild(id) then
			list[#list + 1] = { id = id, rec = rec }
		end
	end
	sort(list, function(a, b)   -- the newest first: it gives the account's version and the title
		if (a.rec.time or 0) ~= (b.rec.time or 0) then return (a.rec.time or 0) > (b.rec.time or 0) end
		return a.id < b.id
	end)
	local out = { accounts = 0, users = {}, titles = {}, keys = {} }
	for _, item in ipairs(list) do
		local key = accountOf(item.id)
		if not out.keys[key] then
			out.keys[key] = item.id
			out.accounts = out.accounts + 1
		end
		for _, e in ipairs(item.rec.l) do
			local folder = type(e) == "table" and e[1]
			if type(folder) == "string" then
				local users = out.users[folder]
				if not users then users = {} out.users[folder] = users end
				local u = users[key]
				if not u then
					u = { version = e[2] ~= "" and e[2] or nil, guids = {} }
					users[key] = u
				end
				u.guids[#u.guids + 1] = item.id
				if e[3] and not out.titles[folder] then out.titles[folder] = e[3] end
			end
		end
	end
	return out
end

local function data()
	if not state.cache then
		local built = build()
		state.cache = built
	end
	return state.cache
end

-- The addons of this character by folder (nil in demo mode, where the real ones are not mixed with the invented guild).
local function loadedHere()
	if demo() then return {} end
	local out = {}
	for _, e in ipairs(Census:Own() or {}) do
		out[e[1]] = { version = e[2] ~= "" and e[2] or nil, title = e[3] }
	end
	return out
end

-- The census as everybody may see it: { total = accounts that share, own = whether this account is one of them, rows =
-- { { folder, title, name, users, share (percent), versions = { { version | nil, n }, ... } most used first,
--     mine = this account is counted, here = loaded on this character }, ... } sorted by name }. No names of members.
function Census:Summary()
	if not Census.Enabled() then return { total = 0, own = false, rows = {} } end
	local d = data()
	local me = ownGUID()
	local mine = me and accountOf(me)
	local here = loadedHere()
	local rows = {}
	for folder, users in pairs(d.users) do
		local n, counts = 0, {}
		for _, u in pairs(users) do
			n = n + 1
			local v = u.version or ""
			counts[v] = (counts[v] or 0) + 1
		end
		local versions = {}
		for v, c in pairs(counts) do versions[#versions + 1] = { version = v ~= "" and v or nil, n = c } end
		sort(versions, function(a, b)
			if a.n ~= b.n then return a.n > b.n end
			return (a.version or "") > (b.version or "")
		end)
		local title = d.titles[folder]
		rows[#rows + 1] = { folder = folder, title = title, name = title or folder, users = n,
			share = d.accounts > 0 and floor(n * 100 / d.accounts + 0.5) or 0, versions = versions,
			mine = mine ~= nil and users[mine] ~= nil, here = here[folder] ~= nil }
	end
	sort(rows, function(a, b)
		local x, y = a.name:lower(), b.name:lower()
		if x ~= y then return x < y end
		return a.folder < b.folder
	end)
	return { total = d.accounts, own = mine ~= nil and d.keys[mine] ~= nil, rows = rows }
end

-- true when this character may see who uses an addon (not only its own account).
function Census.CanSeeNames()
	local who = Census.NAMES_VISIBLE_TO
	if who == "members" then return ns.Role ~= nil and ns.Role:InGuild() end
	if who ~= "officers" then return false end
	return ns.Role ~= nil and ns.Role:IsOfficer() == true
end

local function rosterName(guid)
	local e = inGuild(guid)
	return e and (e.short or e.name) or nil
end

-- Who uses the addon `folder`, as far as this character may see it: { { account, name (the main's, else a character's),
-- chars = { names of the characters whose list has it }, version, own, shared }, ... } by name. Officers and the Guild
-- Master get every account; anybody else only the own one. The own account is there too when only this character has it
-- loaded and nothing says so yet (shared = false: not counted).
function Census:Who(folder)
	if not Census.Enabled() or type(folder) ~= "string" then return {} end
	local d = data()
	local me = ownGUID()
	local mine = me and accountOf(me)
	local all = Census.CanSeeNames()
	local out, listed = {}, false
	local function add(key, version, guids, shared)
		local main = ns.Accounts and ns.Accounts:MainOf(guids[1])
		local chars = {}
		for _, g in ipairs(guids) do chars[#chars + 1] = rosterName(g) end
		sort(chars)
		out[#out + 1] = { account = key, name = (main and rosterName(main.guid)) or chars[1] or "?", chars = chars,
			version = version, own = key == mine, shared = shared }
	end
	for key, u in pairs(d.users[folder] or {}) do
		if all or key == mine then
			add(key, u.version, u.guids, true)
			if key == mine then listed = true end
		end
	end
	if not listed and me then
		local here = loadedHere()[folder]
		if here then add(mine, here.version, { me }, false) end
	end
	sort(out, function(a, b)
		local x, y = a.name:lower(), b.name:lower()
		if x ~= y then return x < y end
		return tostring(a.account) < tostring(b.account)
	end)
	return out
end

-- How many accounts use `folder`, and out of how many that share.
function Census:Count(folder)
	if not Census.Enabled() then return 0, 0 end
	local d = data()
	local n = 0
	for _ in pairs(d.users[folder] or {}) do n = n + 1 end
	return n, d.accounts
end

---------------------------------------------------------------------------------------------------------------------
-- Changes
---------------------------------------------------------------------------------------------------------------------
-- What the counts are read from changed: drop them, and tell the views once after EMIT_DELAY.
function Census:Changed()
	if not Census.Enabled() then return end
	state.cache = nil
	if state.emitting then return end
	state.emitting = true
	local mine = state
	compat().After(Census.EMIT_DELAY, function()
		if state ~= mine then return end
		state.emitting = false
		state.cache = nil
		emit("CENSUS_CHANGED")
	end)
end

function Census:OnStoreChanged(set, id, origin)
	if not Census.Enabled() then return end
	if set ~= Census.SET and set ~= "accounts" then return end
	self:Changed()
	-- a record of this account came from the guild (a computer that lost its data, or another one): compare again
	if set == Census.SET and origin == "remote" and id then
		local me = ownGUID()
		if me and store():SameAccount(me, id) then self:Recheck() end
	end
end

function Census:OnSetting(key)
	if not Census.Enabled() then return end
	if key == "shareAddons" or key == "backup" then   -- a backup may bring the switch of another computer
		schedule("switch", Census.SWITCH_DELAY, function() Census:Publish() end)
		self:Changed()
	elseif key == "clear" then
		self:Changed()
		self:Recheck()
	end
end

function Census:OnGuildChanged()
	resetState()
	self:Changed()
end

function Census:DebugLines()
	local s = state.stats
	local entries = self:Own()
	return {
		("Census: %d record(s) held; sharing %s, own list %s; published %d, unchanged %d, withdrawn %d, last %s"):format(
			store() and store():Count(Census.SET) or 0, Census.Sharing() and "on" or "off",
			entries and (#entries .. " addon(s)") or "not readable", s.published, s.unchanged, s.withdrawn, tostring(state.last)),
	}
end

if ns.addon then
	ns.addon.Census = Census
	if ns.Bus then
		ns.Bus:On("SYNC_HELLO", function(sent) if sent then Census:OnHello() end end)
		ns.Bus:On("STORE_CHANGED", function(set, id, origin) Census:OnStoreChanged(set, id, origin) end)
		ns.Bus:On("SETTINGS_CHANGED", function(key) Census:OnSetting(key) end)
		ns.Bus:On("GUILD_CHANGED", function() Census:OnGuildChanged() end)
		for _, event in ipairs({ "ROSTER_UPDATED", "ACCOUNTS_UPDATED", "DEMO_CHANGED", "BACKUP_IMPORTED", "ROLE_CHANGED" }) do
			ns.Bus:On(event, function() Census:Changed() end)
		end
	end
	LibStub("AceEvent-3.0"):Embed(Census)
	if ns.OnEnable then
		ns.OnEnable(function()
			if not Census.Enabled() then return end
			Census:RegisterEvent("ADDON_LOADED", function() Census:Recheck() end)
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Census", function() return Census:DebugLines() end) end
		end)
	end
end

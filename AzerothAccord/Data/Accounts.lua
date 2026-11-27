-- Accounts: which characters belong to the same player (SPEC-05 §3, SPEC-03 §1, ADR 0006). Lua 5.1.
--
-- Two sides:
--
--   Own account  Every character that logs in with the addon is added to AzerothAccordDB.chars[realm][guid] (ACC-01),
--                which is account-wide. At login and when something changes the character publishes ITS OWN `accounts`
--                record (id = its GUID): the account token, the list of the account's characters on this realm
--                (whether they are in the guild or not) and the main. The list is shared with the guild always (owner
--                decision D3, ADR 0006: no opt-out, so there is no setting to turn it off).
--
--   Other players  The characters of one account are grouped from the records the guild holds. Two characters are one
--                account only when EACH one's own record lists the other (mutual listing, ADR 0006 note): the token is
--                public and a client can list anybody, so neither proves anything. A character that is not in the guild
--                cannot publish a record, so it appears as "claimed" by the members who list it (ACC-03, shown as not
--                in the guild); a guild member somebody lists without being listed back is ignored. For members
--                without the addon a public note `main: <name>` ("my main is ...") or `alt: <name>` ("<name> is my
--                alt") is a hint (ACC-05), shown as "declared in the note".
--
-- Alts outside the guild (SPEC-11 §2, M7.3): the local `chars` entry keeps `guild` (a guild key, or "" for no guild) with
--   `guildAt` (when it was read), `guildSince` (since when it reads the same; local only) and `seen`; the record lists, for characters outside the guild only, `guild` (the NAME,
--   or "" = no guild) and `seen` (the day of the last login with the addon). Old clients ignore both fields.
--
-- Group: { id, members = { { guid, name, realm, classID, classFile, level, inGuild, claimed, hint, isMain,
--                            altGuild = { guild = name | "" | nil, seen, author, time } }, ... },
--          main = guid, mainSource = "chosen"|"default"|"hint", token, conflict }.
-- Main: the player's choice (Accounts:SetMain, saved per realm), else the highest level, then the character added first
-- (the time played would need /played, which writes in the chat).
-- Bus: CHARACTER_GUILD_CHANGED(guid, from, to) when a character's guild reads differently than before (M12.4);
--   ACCOUNTS_UPDATED() after the groups are rebuilt; the own record goes through Store:Put like any other.
local ADDON_NAME, ns = ...
ns = ns or {}
local Accounts = {}
ns.Accounts, ns.modules = Accounts, ns.modules or {}
ns.modules.Accounts = Accounts

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor = math.floor

local DAY = 86400
Accounts.STALE_DAYS = 30        -- ACC-04: a character the client no longer knows for this long is dropped
Accounts.MAX_CHARS = 40         -- the record has to fit the size limit of the set (Store.SETS.accounts.maxBytes)
Accounts.MAX_BYTES = 3600
Accounts.PUBLISH_DELAY = 8      -- seconds after login (the roster has loaded by then)
Accounts.REPUBLISH_MIN = 600    -- seconds between two publications caused by a change of the guild roster
Accounts.AUTO = true            -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Accounts.GUID_PATTERN = "^Player%-%d+%-%x+$"
Accounts.GUILD_NAME_MAX = 24    -- characters, as in the game (SPEC-11 §2.2); longer is cut

local function compat() return ns.Compat end
local function now() return compat() and compat().ServerTime() or time() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function lower(s) return type(s) == "string" and s:lower() or nil end
local function isGUID(v) return type(v) == "string" and #v <= 40 and v:find(Accounts.GUID_PATTERN) ~= nil end
local function accountDB() return ns.Config and ns.Config.db and ns.Config.db.account or nil end

-- At most `max` UTF-8 characters of `text` (never cuts inside a character: accents take two bytes).
local function cutChars(text, max)
	local count = 0
	for i = 1, #text do
		local b = text:byte(i)
		if b < 0x80 or b >= 0xC0 then
			count = count + 1
			if count > max then return text:sub(1, i - 1) end
		end
	end
	return text
end

-- A guild name read from a record, made safe to show (SPEC-11 §2.4): control characters out, cut to the game's length,
-- `|` doubled so that nothing in it is a link or a colour. nil when nothing is left of a non-empty name.
function Accounts.SafeGuildName(text)
	if type(text) ~= "string" then return nil end
	if text == "" then return "" end
	text = cutChars(text:gsub("[%c]", ""), Accounts.GUILD_NAME_MAX)
	if text == "" then return nil end
	return (text:gsub("|", "||"))
end

local state = { dirty = true, groups = {}, byGUID = {}, list = {}, lastPublish = nil, publishedOnce = false,
	proved = false, pruned = 0, stats = { published = 0, skipped = 0 } }
Accounts.state = state

---------------------------------------------------------------------------------------------------------------------
-- Own account: the characters of this player (ACC-01), the main, stale characters (ACC-04)
---------------------------------------------------------------------------------------------------------------------
local function validEntry(e)
	return type(e) == "table" and type(e.name) == "string" and e.name ~= "" and #e.name <= 48
end

-- Adds or updates a character of this account: info = { guid, name, realm, classID, level, guild }. Returns the stored
-- entry, or nil plus a reason ("db", "guid", "name", "read-only").
function Accounts:Register(info)
	local db = accountDB()
	if not db then return nil, "db" end
	if type(info) ~= "table" or not isGUID(info.guid) then return nil, "guid" end
	if type(info.name) ~= "string" or info.name == "" then return nil, "name" end
	if ns.Config:IsReadOnly("account") then return nil, "read-only" end
	local realm = info.realm or (compat() and compat().Player.RealmKey())
	if type(realm) ~= "string" or realm == "" then return nil, "realm" end
	if type(db.chars) ~= "table" then db.chars = {} end
	local list = db.chars[realm]
	if type(list) ~= "table" then list = {} db.chars[realm] = list end
	local entry = list[info.guid]
	if type(entry) ~= "table" then entry = { added = now() } list[info.guid] = entry end
	entry.name = info.name
	entry.classID = tonumber(info.classID) or entry.classID
	entry.level = tonumber(info.level) or entry.level
	local before = entry.guild
	if info.guild ~= nil then
		-- since when this guild is read for the character (ONB-03, SPEC-16 §5.1): kept while it stays the same
		if before ~= info.guild then entry.guildSince = now()
		elseif entry.guildSince == nil then entry.guildSince = entry.guildAt end
		entry.guild, entry.guildAt = info.guild, now()
	end
	entry.seen = now()
	entry.answered = entry.seen
	state.dirtyOwn = true
	if info.guild ~= nil and before ~= nil and before ~= info.guild then
		emit("CHARACTER_GUILD_CHANGED", info.guid, before, info.guild)
	end
	return entry
end

-- The character that is logged in now, added to the account's list. Its guild is read every time (SPEC-11 §2.1): the guild
-- key, "" when the game says it is in no guild, and unchanged while it is in a guild whose name has not arrived yet.
function Accounts:RegisterSelf()
	local entry, why = self:RegisterSelfNow()
	state.lastRegister = entry and "ok" or tostring(why)   -- /accord debug says why the own list stays empty
	return entry, why
end

-- WoW Forever has no realm: every character belongs under Player.NO_REALM. Builds of 2026-11-27 stored them under their
-- SURNAME as if it were a realm (and the guild key with it); this moves them back once, keeping the newest entry of a GUID,
-- and points their guild at the guild key without that surname.
function Accounts.MergeNoRealm(C)
	if C.Player.Realm() then return 0 end
	local db = accountDB()
	if not db or type(db.chars) ~= "table" or ns.Config:IsReadOnly("account") then return 0 end
	local home = C.Player.NO_REALM
	local into = type(db.chars[home]) == "table" and db.chars[home] or {}
	local moved = 0
	for r, list in pairs(db.chars) do
		if r ~= home and type(list) == "table" then
			for guid, e in pairs(list) do
				local old = into[guid]
				if type(e) == "table" and (type(old) ~= "table" or (e.seen or 0) > (old.seen or 0)) then
					if type(e.guild) == "string" and e.guild ~= "" then
						local _, gname = ns.GuildKey.Split(e.guild)
						if gname then e.guild = ns.GuildKey.Make(home, gname) end
					end
					into[guid] = e
				end
				moved = moved + 1
			end
			db.chars[r] = nil
		end
	end
	db.chars[home] = into
	return moved
end

function Accounts:RegisterSelfNow()
	local C = compat()
	if not C then return nil, "compat" end
	local guid, name = C.Player.GUID(), (C.Player.FullName and C.Player.FullName()) or C.Player.Name()
	if not guid then return nil, "no GUID from the game" end
	Accounts.MergeNoRealm(C)
	if not name then return nil, "no name from the game" end
	local guild = ns.GuildKey and ns.GuildKey:Current() or nil
	if guild == nil and not C.Guild.InGuild() then guild = "" end
	return self:Register{ guid = guid, name = name, realm = (C.Player.RealmKey and C.Player.RealmKey()) or C.Player.Realm(), classID = C.Player.ClassID(), level = C.Player.Level(),
		guild = guild }
end

-- The characters this account lists for the current guild: every character of this realm and the ones last seen in this
-- guild on another realm; the logged-in one always first in line. Sorted by level, then name, then GUID.
function Accounts:OwnChars()
	local db, out = accountDB(), {}
	if not db or type(db.chars) ~= "table" then return out end
	local C = compat()
	local realm, me = C and C.Player.RealmKey(), C and C.Player.GUID()
	local key = ns.GuildKey and ns.GuildKey:Current() or nil
	local R = ns.Roster
	local rosterLoaded = R and R:Count() > 1
	for r, list in pairs(db.chars) do
		if type(list) == "table" then
			for guid, e in pairs(list) do
				if isGUID(guid) and validEntry(e) and (r == realm or (key ~= nil and e.guild == key)) then
					local inGuild
					if guid == me then inGuild = key ~= nil
					elseif rosterLoaded then inGuild = R:ByGUID(guid) ~= nil
					else inGuild = key ~= nil and e.guild == key end
					out[#out + 1] = { guid = guid, name = e.name, realm = r, classID = e.classID, level = e.level, inGuild = inGuild,
						added = e.added or 0, isSelf = guid == me, guildKey = e.guild, guildAt = e.guildAt, seen = e.seen }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.isSelf ~= b.isSelf then return a.isSelf end
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		if a.name ~= b.name then return a.name < b.name end
		return a.guid < b.guid
	end)
	return out
end

-- The main of this account on the current realm: the player's choice when it is still a character of the account, else
-- the highest level (ties: added first, then GUID). Returns guid, "chosen" | "default".
function Accounts:Main()
	local list = self:OwnChars()
	if #list == 0 then return nil end
	local db = accountDB()
	local C = compat()
	local realm = C and C.Player.RealmKey()
	local chosen = db and type(db.mains) == "table" and realm and db.mains[realm]
	if chosen then
		for _, e in ipairs(list) do if e.guid == chosen then return chosen, "chosen" end end
	end
	local best
	for _, e in ipairs(list) do
		if not best or (e.level or 0) > (best.level or 0)
			or ((e.level or 0) == (best.level or 0) and (e.added < best.added or (e.added == best.added and e.guid < best.guid))) then
			best = e
		end
	end
	return best.guid, "default"
end

-- The player's choice of main (one of this account's characters on this realm), published at once.
function Accounts:SetMain(guid)
	local db = accountDB()
	local C = compat()
	local realm = C and C.Player.RealmKey()
	if not db or not realm then return false, "db" end
	if ns.Config:IsReadOnly("account") then return false, "read-only" end
	local found = false
	for _, e in ipairs(self:OwnChars()) do if e.guid == guid then found = true end end
	if not found then return false, "unknown" end
	if type(db.mains) ~= "table" then db.mains = {} end
	db.mains[realm] = guid
	self:Publish()
	return true
end

-- ACC-04: renamed characters follow their new name; a character the client no longer answers for, during STALE_DAYS,
-- is dropped. Without proof that the API answers for characters other than the logged-in one (state.proved) nothing is
-- ever dropped: an alt that is simply not played must stay. Returns the number dropped.
function Accounts:Prune()
	local db, C = accountDB(), compat()
	if not db or not C or type(db.chars) ~= "table" or ns.Config:IsReadOnly("account") then return 0 end
	local me, t, removed = C.Player.GUID(), now(), 0
	local answers = {}
	for _, list in pairs(db.chars) do
		for guid in pairs(list) do
			if guid ~= me then
				local info = C.Player.InfoByGUID(guid)
				answers[guid] = info or false
				if info then state.proved = true end
			end
		end
	end
	for realm, list in pairs(db.chars) do
		if type(list) == "table" then
			for guid, e in pairs(list) do
				if type(e) ~= "table" then
					list[guid] = nil
				elseif guid ~= me then
					local info = answers[guid]
					if info then
						e.answered = t
						if info.name and info.name ~= e.name then e.name = info.name state.dirtyOwn = true end
						if info.level then e.level = info.level end
					elseif state.proved and t - (e.answered or e.seen or t) > Accounts.STALE_DAYS * DAY then
						list[guid] = nil
						removed = removed + 1
						state.dirtyOwn = true
					end
				end
			end
		end
	end
	state.pruned = state.pruned + removed
	return removed
end

-- The guild of a character outside this guild, as the record says it (SPEC-11 §2.1-2.2): its name, "" for no guild, nil when
-- unknown (an entry written before M7.3 has no `guildAt`, and a stale key of this very guild says nothing about another one).
function Accounts.SharedGuild(e, key)
	if type(e.guildAt) ~= "number" or type(e.guildKey) ~= "string" then return nil end
	if e.guildKey == "" then return "" end
	if key ~= nil and e.guildKey == key then return nil end
	local _, name = ns.GuildKey.Split(e.guildKey)
	if type(name) ~= "string" or name == "" then return nil end
	return cutChars(name, Accounts.GUILD_NAME_MAX)
end

-- The fields of this character's own `accounts` record.
function Accounts:BuildRecord()
	local C, db = compat(), accountDB()
	local me = C and C.Player.GUID()
	if not me or not db then return nil end
	local token = ns.Config:Token()
	if type(token) ~= "string" or token == "" then return nil end
	local list = self:OwnChars()
	local key = ns.GuildKey and ns.GuildKey:Current() or nil
	local entries = {}
	for i, e in ipairs(list) do
		entries[i] = { guid = e.guid, name = e.name, realm = e.realm, classID = e.classID, level = e.level, inGuild = e.inGuild }
		if not e.inGuild then   -- SPEC-11 §2.2: only characters outside this guild carry their guild and last login
			entries[i].guild = Accounts.SharedGuild(e, key)
			if type(e.seen) == "number" then entries[i].seen = e.seen - e.seen % DAY end
		end
	end
	-- who stays when the list does not fit (SPEC-11 §2.3): the character itself, the guild's characters (the mutual
	-- listing needs them), then the ones outside by most recent login; whole entries go from the end of that order
	local order = {}
	for i, e in ipairs(list) do order[i] = i end
	table.sort(order, function(x, y)
		local a, b = list[x], list[y]
		if a.isSelf ~= b.isSelf then return a.isSelf end
		if a.inGuild ~= b.inGuild then return a.inGuild end
		if not a.inGuild and (entries[x].seen or 0) ~= (entries[y].seen or 0) then return (entries[x].seen or 0) > (entries[y].seen or 0) end
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		if a.name ~= b.name then return a.name < b.name end
		return a.guid < b.guid
	end)
	local kept = {}
	for n = 1, math.min(#order, Accounts.MAX_CHARS) do kept[n] = order[n] end
	local function build()
		local keep, out = {}, {}
		for _, i in ipairs(kept) do keep[i] = true end
		for i, e in ipairs(entries) do if keep[i] then out[#out + 1] = e end end
		return out
	end
	local chars = build()
	while #kept > 1 and ns.Config.EstimateSize(chars) > Accounts.MAX_BYTES do
		table.remove(kept)
		chars = build()
	end
	local mine = false
	for _, c in ipairs(chars) do if c.guid == me then mine = true end end
	if not mine then return nil end   -- the owner rule: a record lists its own character
	local main = self:Main()
	local listed = false
	for _, c in ipairs(chars) do if c.guid == main then listed = true end end
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or nil
	return { token = token, chars = chars, main = listed and main or me, addonVersion = type(version) == "string" and version or nil }
end

local function sameChars(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
	for i, x in ipairs(a) do
		local y = b[i]
		if type(y) ~= "table" or x.guid ~= y.guid or x.name ~= y.name or x.realm ~= y.realm or x.classID ~= y.classID
			or x.level ~= y.level or x.inGuild ~= y.inGuild or x.guild ~= y.guild or x.seen ~= y.seen then return false end
	end
	return true
end

-- Publishes this character's own record when it differs from the one held (no new `rev` for an identical record).
-- Returns true when a new revision was written, false plus a reason otherwise.
function Accounts:Publish()
	local S, C = ns.Store, compat()
	if not (S and C) or not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local me = C.Player.GUID()
	if not me then return false, "player" end
	self:RegisterSelf()
	local fields = self:BuildRecord()
	if not fields then return false, "record" end
	local old = S:Get("accounts", me)
	if old and old.token == fields.token and old.main == fields.main and old.addonVersion == fields.addonVersion
		and sameChars(old.chars, fields.chars) then
		state.stats.skipped = state.stats.skipped + 1
		return false, "unchanged"
	end
	local rec, why = S:Put("accounts", me, fields)
	if not rec then return false, why end
	state.stats.published = state.stats.published + 1
	state.lastPublish, state.publishedOnce, state.dirtyOwn = now(), true, false
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Other players: the groups (mutual listing) and the hints of the notes
---------------------------------------------------------------------------------------------------------------------
-- A public note's declaration: "main: Name" (this character's main is Name) or "alt: Name" (Name is this character's
-- alt), case-insensitive, at the start of the note. A Forever full name may have a space ("alt: Name Surname, tank"):
-- with `lookup(name) -> roster entry`, the prefix of 3, then 2, then 1 word before the first separator (, ; | / or the
-- end of the note) that names a roster member wins (SPEC-11 §6.6). Returns kind ("main"|"alt"), name, the entry; or
-- nil. Without `lookup` the name is the first word.
function Accounts.ParseNote(note, lookup)
	if type(note) ~= "string" then return nil end
	local word, rest = note:match("^%s*(%a+)%s*:%s*(.*)$")
	local kind = lower(word)
	if kind ~= "main" and kind ~= "alt" then return nil end
	local words = {}
	for w in rest:match("^[^,;|/]*"):gmatch("%S+") do
		words[#words + 1] = w
		if #words == 3 then break end
	end
	for n = lookup and #words or math.min(1, #words), 1, -1 do
		local name = table.concat(words, " ", 1, n):gsub("[%.!]+$", "")
		if name ~= "" then
			if not lookup then return kind, name end
			local target = lookup(name)
			if target then return kind, name, target end
		end
	end
	return nil
end

local function find(parent, x)
	while parent[x] ~= x do
		parent[x] = parent[parent[x]]
		x = parent[x]
	end
	return x
end

local function memberFrom(guid, entryOfRecord, rosterEntry, claimed)
	local m = { guid = guid, inGuild = rosterEntry ~= nil, claimed = claimed or nil }
	if entryOfRecord then
		m.name, m.realm, m.classID, m.level = entryOfRecord.name, entryOfRecord.realm, entryOfRecord.classID, entryOfRecord.level
	end
	if rosterEntry then
		m.name = rosterEntry.name or m.name
		m.classID = rosterEntry.classID or m.classID
		m.classFile = rosterEntry.classFile
		m.level = rosterEntry.level or m.level
	end
	return m
end

local function entryFor(rec, guid)
	for _, c in ipairs(rec.chars) do
		if type(c) == "table" and c.guid == guid then return c end
	end
	return nil
end

-- What the records say about a character outside the guild (SPEC-11 §2.4): from the entry with the highest `seen` among
-- the records of the account (a tie goes to the newest record, then the smaller author), cleaned like any text of others.
-- { guild = name | "" | nil, seen = number | nil, author, time }, or nil when no record knows anything.
function Accounts.AltGuildOf(guid, guids, recs)
	local best
	for _, id in ipairs(guids) do
		local rec = recs[id]
		for _, c in ipairs(rec.chars) do
			if type(c) == "table" and c.guid == guid and c.inGuild ~= true then
				local seen = type(c.seen) == "number" and c.seen >= 0 and c.seen < 2 ^ 40 and c.seen or nil
				local name = Accounts.SafeGuildName(c.guild)
				if name ~= nil or seen ~= nil then
					local better = not best or (seen or -1) > (best.seen or -1)
						or ((seen or -1) == (best.seen or -1) and (rec.time or 0) > (best.time or 0))
					if better then best = { guild = name, seen = seen, author = rec.author, time = rec.time } end
				end
			end
		end
	end
	return best
end

-- Rebuilds the groups from the store and the roster.
function Accounts:Rebuild()
	local S, R = ns.Store, ns.Roster
	local recs = {}
	for id, rec in pairs(S and S:Records("accounts") or {}) do
		if type(rec) == "table" and rec.id == id and rec.author == id and type(rec.chars) == "table" and rec.del ~= true then recs[id] = rec end
	end
	local parent = {}
	for guid in pairs(recs) do parent[guid] = guid end
	for guid, rec in pairs(recs) do
		for _, c in ipairs(rec.chars) do
			local other = type(c) == "table" and c.guid or c
			if other ~= guid and recs[other] and S.Lists(recs[other], guid) then
				local a, b = find(parent, guid), find(parent, other)
				if a ~= b then
					if a < b then parent[b] = a else parent[a] = b end
				end
			end
		end
	end
	local rosterOf = function(guid) return R and R:ByGUID(guid) or nil end
	local comps = {}
	for guid in pairs(recs) do
		local root = find(parent, guid)
		local comp = comps[root]
		if not comp then comp = { id = root, guids = {} } comps[root] = comp end
		comp.guids[#comp.guids + 1] = guid
	end

	local groups, byGUID = {}, {}
	for root, comp in pairs(comps) do
		table.sort(comp.guids)
		local g = { id = root, members = {}, byGUID = {}, conflict = false }
		local newest
		for _, guid in ipairs(comp.guids) do
			local rec = recs[guid]
			local m = memberFrom(guid, entryFor(rec, guid), rosterOf(guid), false)
			g.members[#g.members + 1], g.byGUID[guid] = m, m
			if not g.token then g.token = rec.token elseif g.token ~= rec.token then g.conflict = true end
			if not newest or (rec.time or 0) > (newest.time or 0) then newest = rec end
		end
		-- characters the members list that the guild cannot vouch for: out of the guild, not holders of a record
		for _, guid in ipairs(comp.guids) do
			for _, c in ipairs(recs[guid].chars) do
				local cg = type(c) == "table" and c.guid or nil
				if cg and isGUID(cg) and not recs[cg] and not g.byGUID[cg] and not rosterOf(cg) and validEntry(c) then
					local m = memberFrom(cg, c, nil, true)
					g.members[#g.members + 1], g.byGUID[cg] = m, m
				end
			end
		end
		-- the guild and last login of the members outside the guild (SPEC-11 §2.4)
		for _, m in ipairs(g.members) do
			if not m.inGuild then m.altGuild = Accounts.AltGuildOf(m.guid, comp.guids, recs) end
		end
		-- the main: the choice in the newest record, else the highest level
		g.main, g.mainSource = nil, "default"
		if newest and type(newest.main) == "string" and g.byGUID[newest.main] then g.main, g.mainSource = newest.main, "chosen" end
		table.sort(g.members, function(a, b)
			if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
			if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
			return a.guid < b.guid
		end)
		if newest then g.time, g.author = newest.time, newest.author end   -- the record the group is read from (M7.2 label)
		if not g.main then g.main = g.members[1].guid end
		groups[#groups + 1] = g
	end

	-- hints from public notes, for roster members who are in no group (ACC-05)
	if R then
		local function groupFor(guid)
			for _, g in ipairs(groups) do if g.byGUID[guid] then return g end end
		end
		for _, e in ipairs(R:Members()) do
			if e.guid and not recs[e.guid] and not groupFor(e.guid) then
				local kind, _, target = Accounts.ParseNote(e.note, function(name) return R:ByName(name) end)
				if target and target.guid and target.guid ~= e.guid then
					local g = groupFor(target.guid)
					if not g then
						g = { id = target.guid, members = {}, byGUID = {}, conflict = false, hintOnly = true }
						local m = memberFrom(target.guid, nil, target, false)
						m.hint = true
						g.members[1], g.byGUID[target.guid] = m, m
						g.main, g.mainSource = target.guid, "hint"
						groups[#groups + 1] = g
					end
					local m = memberFrom(e.guid, nil, e, false)
					m.hint = true
					g.members[#g.members + 1], g.byGUID[e.guid] = m, m
					if kind == "alt" and g.mainSource == "hint" and g.hintOnly then
						g.main = e.guid   -- "alt: Name" means this character is the main and Name its alt
					end
				end
			end
		end
	end

	table.sort(groups, function(a, b) return a.id < b.id end)
	local list = {}
	for _, g in ipairs(groups) do
		for _, m in ipairs(g.members) do
			m.isMain = m.guid == g.main
			byGUID[m.guid] = g
		end
		list[#list + 1] = g
	end
	state.groups, state.byGUID, state.list, state.dirty = groups, byGUID, list, false
	emit("ACCOUNTS_UPDATED", #list)
	return #list
end

function Accounts:MarkDirty() state.dirty = true end

-- Every group, sorted by id (a hash of nothing: the order is stable, not meaningful); a caller sorts for display.
function Accounts:Groups()
	if state.dirty then self:Rebuild() end
	return state.list
end

-- The group of a character, or nil when it is in none (a member without the addon and without a note).
function Accounts:GroupOf(guid)
	if state.dirty then self:Rebuild() end
	return guid and state.byGUID[guid] or nil
end

-- The other characters of the same account (members of the group except `guid`), main first; an empty list when none.
function Accounts:Alts(guid)
	local g = self:GroupOf(guid)
	local out = {}
	if not g then return out end
	for _, m in ipairs(g.members) do if m.guid ~= guid then out[#out + 1] = m end end
	table.sort(out, function(a, b)
		if a.isMain ~= b.isMain then return a.isMain end
		return false
	end)
	return out
end

-- The main of the group of `guid`: the member table, or nil.
function Accounts:MainOf(guid)
	local g = self:GroupOf(guid)
	return g and g.byGUID[g.main] or nil
end

-- The characters that count as one account for the likes and the social index (SPEC-07): the PROVED characters of the
-- group of `guid` (mutual listing, and the characters outside the guild they list), or the character alone when it is in
-- no group or joined to one only by a note (a hint is shown in the roster, it never merges likes or minutes).
function Accounts:ProvedChars(guid)
	local g = self:GroupOf(guid)
	local m = g and g.byGUID[guid]
	if not g or not m or m.hint then return { guid } end
	local out = {}
	for _, x in ipairs(g.members) do
		if not x.hint then out[#out + 1] = x.guid end
	end
	return out
end

-- A stable key of the account of `guid` for the likes and the social index: the smallest GUID of its proved characters.
function Accounts:AccountKey(guid)
	if type(guid) ~= "string" then return nil end
	local key = guid
	for _, g in ipairs(self:ProvedChars(guid)) do if g < key then key = g end end
	return key
end

-- The account token of a character (its own record), for contacts; nil without an addon record.
function Accounts:TokenOf(guid)
	local g = self:GroupOf(guid)
	if g and g.token then return g.token end
	return ns.Store and ns.Store:TokenOf(guid) or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Start and events
---------------------------------------------------------------------------------------------------------------------
local function schedule(seconds, fn)
	local C = compat()
	if C then C.After(seconds, fn) end
end

-- At login (once the guild is known): add the character, check the stale ones, publish.
function Accounts:Start()
	if not self.AUTO then return false end
	self:RegisterSelf()   -- also without a guild: the other characters of the account show "No guild" (SPEC-11 §2.1)
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false end
	schedule(Accounts.PUBLISH_DELAY, function()
		if not (ns.GuildKey and ns.GuildKey:Current()) then return end
		Accounts:Prune()
		Accounts:Publish()
	end)
	return true
end

function Accounts:DebugLines()
	local groups = self:Groups()
	local multi, claimed, hints = 0, 0, 0
	for _, g in ipairs(groups) do
		if #g.members > 1 then multi = multi + 1 end
		for _, m in ipairs(g.members) do
			if m.claimed then claimed = claimed + 1 end
			if m.hint then hints = hints + 1 end
		end
	end
	local db = accountDB() or {}
	local own = 0
	for _, list in pairs(type(db.chars) == "table" and db.chars or {}) do for _ in pairs(list) do own = own + 1 end end
	return {
		("Accounts: %d group(s), %d with several characters, %d claimed outside the guild, %d from notes"):format(#groups, multi, claimed, hints),
		("  own list: %d character(s); published %d, unchanged %d; dropped as stale %d%s"):format(own, state.stats.published,
			state.stats.skipped, state.pruned, state.proved and "" or " (never: no proof the client answers for other characters)"),
		("  own character: %s"):format(state.lastRegister and ("last registration " .. state.lastRegister) or "not registered yet"),
	}
end

if ns.addon then
	ns.addon.Accounts = Accounts
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Accounts", function() return Accounts:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Accounts)
	Accounts:RegisterEvent("PLAYER_LEVEL_UP", function()
		if Accounts.AUTO and ns.GuildKey and ns.GuildKey:Current() then
			Accounts:RegisterSelf()
			schedule(2, function() Accounts:Publish() end)
		end
	end)
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set) if set == "accounts" then Accounts:MarkDirty() end end)
		ns.Bus:On("ROSTER_UPDATED", function()
			Accounts:MarkDirty()
			-- somebody joined or left the guild: the "in guild" flags of the own list may have changed
			if Accounts.AUTO and state.publishedOnce and state.lastPublish and now() - state.lastPublish >= Accounts.REPUBLISH_MIN then
				Accounts:Publish()
			end
		end)
		ns.Bus:On("GUILD_CHANGED", function(key)
			state.dirty, state.publishedOnce, state.lastPublish = true, false, nil
			Accounts:Start()
		end)
	end
	if ns.OnEnable then ns.OnEnable(function() Accounts:Start() end) end
end

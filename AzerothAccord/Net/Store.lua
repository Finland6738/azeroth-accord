-- Store: the versioned records of each data set, per guild, and the trust rules that decide what a client accepts
-- (SPEC-02 §3, §6; ADR 0005, 0006). Lua 5.1.
--
-- A record is a plain table { id, author, rev, time, ...fields }: `author` is the GUID of the character that wrote it,
-- `rev` grows by one at every write of that id, `time` is the server time of the write. For one id the higher `rev`
-- wins; on equal `rev` the later `time`, then the greater author GUID (so every client keeps the same one).
-- Records live in GuildKey:Data().store.sets[<set>][<id>]: the data of two guilds never mixes.
--
-- Trust (checked on every record that arrives; the sender name is set by the server and cannot be faked):
--   NET-10 first hand  the sender is the author, or a character of the author's account. "Same account" needs MUTUAL
--                      listing: each character has its own record in the set `accounts` (id = its GUID, accepted only
--                      first hand), and two characters are of one account only when each one's record lists the other.
--                      The account token is published and could be copied, so it never proves anything by itself; a
--                      client cannot claim somebody else's character as its alt, because that character's own record
--                      would have to list it back.
--   NET-11 relay       a record of another author is accepted only when the sender is an officer in this client's roster.
--   NET-12 authority   records that need an authority (the likes ledger, bank request decisions, restricted bank tabs)
--                      are accepted only when both the sender and the author are officers. The likes ledger is the
--                      exception for the author: an entry stays valid after its notary left the guild or was demoted
--                      (SPEC-07 LIKE-07), so only the sender must be an officer (`authorAny`).
--   append-only        the likes ledger (`immutable`): an id is written once, with rev 1, and never replaced; a different
--                      record with an id already held is refused ("immutable").
--   NET-13 observation co-play is accepted only from its observer (author == observer) who appears in at least one of the
--                      observed pairs; observers are combined with a maximum (Store.MergeMax), never a sum.
-- Plus shape checks (id, author GUID, rev, time not in the future, size per set) and the owner rule of each set (an
-- author writes only its own character, its own account, its own observations).
--
-- Officer tools (SPEC-12 §1.2, ADR 0023): the sets with `officerTool = true` are restricted for every record (a member's
--                    client refuses them, an officer accepts them only from an officer sender, `authorAny`) and travel on
--                    OFFICER or by WHISPER to an officer only, once the channel is proven (OFF-01..OFF-09). The one
--                    exception (`firstHand`): a member's own declared absence reaches an officer by WHISPER from its account.
--
-- The addon census (`addons`, SPEC-13 §8.2) is an ordinary set (first hand, officer relay, saved) whose records are
-- summarised apart from the older sets (`summary = "extra"`, Net/Sync.lua), so that a client which does not know the set
-- compares the same summaries as before.
--
-- Short-lived sets (`volatile`, SPEC-13 GRP-03): the group finder's listings travel only first hand (`firstHandOnly`: no
--                    relay, not even by an officer) and are left out of every summary.
--
-- The season roster (`season`, SPEC-14 §4) mixes both: its seasons need officers (NET-12, `authorAny`), its declarations
-- are first hand (an officer may relay them); a declaration cannot change its specs after its lock (`transition` "locked")
-- and one that arrives before its season waits for it (`wait`, Data/Season.lua). Events and sign-ups (`raidev`, SPEC-14
-- §5.5) are the same: the events of the addon and the Raid-Helper imports need officers, a role or an answer is first hand.
-- The availability map (`avail`, SPEC-14 §8.2) is an ordinary set (first hand, officer relay, saved): one small record per
-- character, the 168 levels of when its account is online, or its withdrawal.
--
-- The guild handbook (`handbook`, SPEC-15 §3) is an ordinary set (first hand, officer relay, saved) with three rules of
-- its own: only a writer (Data/Handbook.lua: the Guild Master, the officers and the ranks the officers chose) passes a page
-- first hand (`writer`, HBK-01: refused as "authority"); a receiver takes at most Handbook.WRITES_PER_HOUR new revisions
-- of an author an hour (`rate`, HBK-05); and the record a revision replaces is handed to its module first (`replaced`), so
-- the client keeps its past revisions and sees a conflict (SPEC-15 §3.5). A deleted page stays for ever (`keepDeleted`).
-- Its records are summarised apart (`summary = "handbook"`) and never pushed (Net/Sync.lua).
--
-- Retention (SPEC-01 §4, SPEC-03): co-play 90 days, bank snapshots 90 days, bank logs 365 days, closed bank requests and deletions 60 days.
-- The observed roster timeline has no age limit (SPEC-12 TL-07, the owner's answer to SPEC-10 Q14): only its size limits.
-- An extended note is kept forever, also after its character left the guild (SPEC-12 §5.1, Q14); a deletion expires after 60 days.
--
-- Bus: STORE_CHANGED(set, id, origin) with origin "local" (a write of this client) or "remote" (an accepted record).
local ADDON_NAME, ns = ...
ns = ns or {}
local Store = {}
ns.Store, ns.modules = Store, ns.modules or {}
ns.modules.Store = Store

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor = math.floor

local DAY = 86400
Store.MAX_REV = 2147483647
Store.MAX_FUTURE = 3600            -- a record time more than an hour ahead of this client's clock is refused
Store.GUID_PATTERN = "^Player%-%d+%-%x+$"

local function now() return ns.Compat and ns.Compat.ServerTime() or time() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function str(v, max) return type(v) == "string" and v ~= "" and #v <= (max or 64) end

---------------------------------------------------------------------------------------------------------------------
-- Identity: who is who in this client's roster, and which characters share an account
---------------------------------------------------------------------------------------------------------------------
local roster = { dirty = true, byName = {}, byShort = {}, byGUID = {} }

local function lower(s) return s and s:lower() or nil end
local function split(name)
	if ns.Compat and ns.Compat.SplitName then return ns.Compat.SplitName(name) end
	return name, nil
end
local function short(name) return name and (split(name)) or nil end

-- Rebuilds the name / GUID index of the guild roster (on demand after GUILD_ROSTER_UPDATE).
function Store:IndexRoster()
	local C = ns.Compat
	roster.byName, roster.byShort, roster.byGUID = {}, {}, {}
	local officerRank = {}
	for _, row in ipairs(C and C.Guild.Roster() or {}) do
		if type(row.name) == "string" then
			local rank = row.rankIndex
			if rank ~= nil and officerRank[rank] == nil then officerRank[rank] = C.Guild.RankIsOfficer(rank) == true end
			local entry = { name = row.name, guid = row.guid, rankIndex = rank, officer = rank ~= nil and officerRank[rank] or false,
				online = row.online ~= false }
			roster.byName[lower(row.name)] = entry
			local s = lower(short(row.name))
			if roster.byShort[s] == nil then roster.byShort[s] = entry else roster.byShort[s] = false end   -- ambiguous
			if type(row.guid) == "string" then roster.byGUID[row.guid] = entry end
		end
	end
	roster.dirty = false
end

function Store:RosterChanged() roster.dirty = true end

-- The roster entry of a sender name ("Name" or "Name-Realm"), or nil (not a member, ambiguous, roster not loaded).
function Store:Member(name)
	if type(name) ~= "string" or name == "" then return nil end
	if roster.dirty then self:IndexRoster() end
	local entry = roster.byName[lower(name)]
	if entry then return entry end
	-- "Name" means the player's realm; a roster name without a realm also means the player's realm
	local player = ns.Compat and ns.Compat.Player.Realm()
	local _, senderRealm = split(name)
	if not senderRealm then
		entry = player and roster.byName[lower(name .. "-" .. player)]
		if entry then return entry end
	end
	entry = roster.byShort[lower(short(name))]
	if not entry then return nil end
	local _, entryRealm = split(entry.name)
	if senderRealm == nil and (entryRealm == nil or entryRealm == player) then return entry end
	if senderRealm ~= nil and entryRealm == nil and senderRealm == player then return entry end
	return nil
end

function Store:MemberByGUID(guid)
	if roster.dirty then self:IndexRoster() end
	return roster.byGUID[guid]
end

-- The account token a character published about itself (its own `accounts` record), or nil. For grouping and display
-- only: the token is public, so it proves nothing (see SameAccount).
function Store:TokenOf(guid)
	local rec = self:Get("accounts", guid)
	return rec and type(rec.token) == "string" and rec.token or nil
end

-- true when the `chars` list of an accounts record names `guid` (entries are { guid = ... } or plain GUID strings).
function Store.Lists(rec, guid)
	if type(rec) ~= "table" or type(rec.chars) ~= "table" then return false end
	for _, c in ipairs(rec.chars) do
		if c == guid or (type(c) == "table" and c.guid == guid) then return true end
	end
	return false
end

-- true when two characters are the same one, or each one's own account record lists the other (NET-10).
function Store:SameAccount(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	if a == b then return true end
	return Store.Lists(self:Get("accounts", a), b) and Store.Lists(self:Get("accounts", b), a)
end

local function ownGUID() return ns.Compat and ns.Compat.Player.GUID() or nil end

---------------------------------------------------------------------------------------------------------------------
-- Data sets (SPEC-02 §3, SPEC-03)
---------------------------------------------------------------------------------------------------------------------
-- Each set: restricted(rec) -> true for a record that only officers may hold and that travels on OFFICER only (the bank
-- tabs that an officer read), maxBytes (estimated size of one record), owner(rec, store) -> true when the author may write this record
-- first hand (nil = any author), authority(rec) -> true when the record needs officers (NET-12), authorAny = true when
-- the author of an authority record need not be an officer any more, immutable = true for append-only sets, observation =
-- true for NET-13, expires(rec, now) -> true when retention removes it. The owner rule is checked for authority records too.
-- true when `rec` of `set` is for officers only: it travels on OFFICER and a member's client refuses it.
function Store.IsRestricted(set, rec)
	local def = Store.SETS[set]
	return def ~= nil and def.restricted ~= nil and type(rec) == "table" and def.restricted(rec) == true
end

-- true when the records of `set` are summarised apart from the older sets (SPEC-13 §8.2: the addon census).
function Store.IsExtraSummary(set)
	local def = Store.SETS[set]
	return def ~= nil and def.summary == "extra"
end

-- The summary a set's records go to apart from the older sets: "extra" (the addon census), "handbook" (the guild
-- handbook, SPEC-15 §3.6) or nil (the summary per author).
function Store.SummaryKind(set)
	local def = Store.SETS[set]
	return def ~= nil and def.summary or nil
end

-- true when `set` is one of the officer tools' sets (SPEC-12 §1.2): its records are never sent on GUILD and are summarised
-- by group, not by author.
-- true when `set` is short-lived (SPEC-13 GRP-03): its records are written and sent like the others, but never counted in a
-- summary, pushed, asked for, backed up or exported (Net/Sync.lua leaves them out of its groups).
function Store.IsVolatile(set)
	local def = Store.SETS[set]
	return def ~= nil and def.volatile == true
end

function Store.IsOfficerTool(set)
	local def = Store.SETS[set]
	return def ~= nil and def.officerTool == true
end

-- false for an unknown set, and for the set of a feature whose switch is off (Core/Features.lua): such a set takes no
-- record, local or received, and is not summarised or sent (Net/Sync.lua).
function Store.IsActive(set)
	local def = Store.SETS[set]
	if def == nil then return false end
	return def.feature == nil or (ns.Features ~= nil and ns.Features.On(def.feature))
end

local function closedBankRequest(rec)
	return rec.status == "fulfilled" or rec.status == "rejected" or rec.status == "cancelled"
end

Store.SETS = {
	accounts = {   -- one record per character: id = its GUID, { token, chars = { { guid, ... }, ... }, main, addonVersion }
		maxBytes = 4096,
		owner = function(rec) return rec.id == rec.author and type(rec.token) == "string" and Store.Lists(rec, rec.author) end,
	},
	contacts = {   -- one record per character: id = its GUID, { account = token, battleTag, discord }; the newest
		maxBytes = 512, -- record of an account's characters is the account's contacts
		owner = function(rec, s) return s:SameAccount(rec.id, rec.author) end,
	},
	recipes = {    -- one record per character and profession: id = "<GUID>:<skillLine>", { char, skillLine, ids, ... }
		maxBytes = 8192,
		owner = function(rec, s)
			return type(rec.char) == "string" and type(rec.skillLine) == "number" and rec.id == rec.char .. ":" .. rec.skillLine
				and s:SameAccount(rec.char, rec.author)
		end,
	},
	coplay = {     -- one record per observer and day: id = "<observer GUID>:<YYYYMMDD>", { day, pairs, observer }
		maxBytes = 8192,
		observation = true,
		expires = function(rec, t) return (rec.time or 0) < t - 90 * DAY end,
	},
	likes = {      -- the ledger (Data/Likes.lua): id = "<16 hex of the pseudonym>:<target GUID>", { pseudonym, tag, target, day }
		maxBytes = 512, -- written by officers (the notaries) only, once, never changed
		authority = function() return true end,
		authorAny = true,
		immutable = true,
		owner = function(rec) return ns.Likes ~= nil and ns.Likes.ValidEntry(rec) end,
	},
	bank = {       -- snapshots of tabs, money and logs (Data/Bank.lua); id = "<author GUID>:t<tab>" | ":money" | ":log:<tab>"
		maxBytes = 12288,
		authority = function(rec) return rec.restricted == true end,   -- an officer's snapshot: officers only (NET-12)
		restricted = function(rec) return rec.restricted == true end,  -- never on GUILD, never held by a member (SPEC-08 BANK-02)
		owner = function(rec) return ns.Bank ~= nil and ns.Bank.ValidRecord(rec) end,
		expires = function(rec, t) return (rec.time or 0) < t - (rec.kind == "log" and 365 or 90) * DAY end,
	},
	bankreq = {    -- requests (Data/BankRequests.lua): the author opens or cancels its own, officers decide; id = "<requester>:<n>"
		maxBytes = 1536,
		authority = function(rec) return rec.status ~= nil and rec.status ~= "open" and rec.status ~= "cancelled" end,
		owner = function(rec, s) return ns.BankRequests ~= nil and ns.BankRequests.ValidRecord(rec, s) end,
		compare = function(a, b) return ns.BankRequests.Compare(a, b) end,          -- the highest status wins, not the highest rev
		transition = function(held, rec) return ns.BankRequests.Transition(held, rec) end,   -- the content of a request never changes
		expires = function(rec, t) return closedBankRequest(rec) and (rec.time or 0) < t - 60 * DAY end,
	},
	guildcfg = {   -- guild settings of officers: "sources" { raid, loot } (Data/Integrations.lua), "target" (Data/Composition.lua),
		feature = "season",                       -- "handbook" the writers' ranks (Data/Handbook.lua, only with "raid")
		maxBytes = 768,                           -- Core/Features.lua (M10; also on with "raid"): off, neither written, accepted nor sent
		authority = function() return true end,   -- written and passed on only by officers (NET-12)
		authorAny = true,                         -- the choice stays valid after its officer left or was demoted
		owner = function(rec) return ns.Integrations ~= nil and ns.Integrations.ValidRecord(rec) end,
	},
	handbook = {   -- the guild handbook (Data/Handbook.lua, M11.2, SPEC-15 §3): "P:<slug>" a page, "seeded" the default pages' seeding
		feature = "raid",                         -- Core/Features.lua: with the switch off, neither written, accepted nor sent
		maxBytes = 6144,
		summary = "handbook",                     -- its own entries in the summaries, never pushed by WHISPER (SPEC-15 §3.6)
		keepDeleted = true,                       -- a deleted page stays a `del` record for ever: it does not come back (§7.2)
		aloneOver = 1024,                         -- a page bigger than this travels alone in its REC (§3.6 point 3)
		bulk = true,                              -- its REC go as BULK
		writer = function(rec, member) return ns.Handbook ~= nil and ns.Handbook.IsWriter(member) end,   -- HBK-01
		rate = function(rec) return ns.Handbook ~= nil and ns.Handbook.Within(rec) end,                  -- HBK-05
		replaced = function(held, rec, origin) if ns.Handbook then ns.Handbook.Replaced(held, rec, origin) end end,
		owner = function(rec) if not ns.Handbook then return false end return ns.Handbook.ValidRecord(rec) end,   -- HBK-02
	},
	timeline = {   -- the roster changes an officer observed (Data/Timeline.lua, M8.2): id = "<observer GUID>:<day>:<part>", { observer, day, ev }
		maxBytes = 8192,
		officerTool = true,
		restricted = function() return true end,
		authority = function() return true end,
		authorAny = true,                          -- the history stays valid after its observer was demoted
		owner = function(rec) return ns.Timeline ~= nil and ns.Timeline.ValidRecord(rec) end,
		group = function(rec) return "timeline:" .. floor(rec.day / 100) end,   -- the summary of OHELLO `m`: one group per month
		publishEvery = 600,                        -- a record that grows every event goes out at most every 10 minutes
	},
	absence = {    -- declared absences (Data/Absence.lua, M8.3): id = "<GUID>:self" | "<GUID>:off", { char, from, until }
		maxBytes = 256,
		officerTool = true,
		restricted = function() return true end,
		authority = function() return true end,
		authorAny = true,
		-- the one exception to "officers only" (OFF-02): a member's own declaration, first hand from its account, by WHISPER
		firstHand = function(rec) return ns.Absence ~= nil and ns.Absence.KindOf(rec) == "self" and rec.char or nil end,
		owner = function(rec, s) return ns.Absence ~= nil and ns.Absence.ValidRecord(rec, s) end,
		group = function() return "absence" end,
		expires = function(rec, t) return ns.Absence ~= nil and ns.Absence.Expired(rec, t) end,
	},
	onotes = {     -- the officers' extended notes (Data/OfficerNotes.lua, M8.5): id = character GUID, { char, text }
		maxBytes = 1280,
		officerTool = true,
		restricted = function() return true end,
		authority = function() return true end,
		authorAny = true,                          -- a note stays valid after its author was demoted
		owner = function(rec) return ns.OfficerNotes ~= nil and ns.OfficerNotes.ValidRecord(rec) end,
		group = function(rec) return ns.OfficerNotes.Group(rec) end,   -- 32 groups by a hash of the GUID (SPEC-12 §1.5)
		expires = function(rec, t) return ns.OfficerNotes ~= nil and ns.OfficerNotes.Expired(rec, t) end,   -- deletions only
	},
	groups = {     -- the guild group finder (Data/Groups.lua, M9.6): id = "<leader GUID>:<n>", one listing of a leader
		feature = "groups",                        -- Core/Features.lua: with the switch off, neither written, accepted nor sent
		maxBytes = 384,
		volatile = true,                           -- short-lived: never in a summary, never pushed or asked for (SPEC-13 GRP-03)
		firstHandOnly = true,                      -- only its leader's account sends it; an officer cannot relay it (GRP-02)
		owner = function(rec) return ns.Groups ~= nil and ns.Groups.ValidRecord(rec) end,
		expires = function(rec, t) return ns.Groups ~= nil and ns.Groups.Expired(rec, t) end,
	},
	addons = {     -- the addon census (Data/Census.lua, M9.9): id = character GUID, { l = { { folder, version, title } }, more } or { del }
		feature = "census",                        -- Core/Features.lua: with the switch off, neither written, accepted nor sent
		maxBytes = 6144,
		summary = "extra",                         -- its own entries in the summaries (SPEC-13 §8.2)
		owner = function(rec, s) return ns.Census ~= nil and ns.Census.ValidRecord(rec, s) end,
		expires = function(rec, t) return ns.Census ~= nil and ns.Census.Expired(rec, t) end,
	},
	season = {     -- the season roster (Data/Season.lua, M10.3, SPEC-14 §4): "S:<n>" a season (officers), "E:<n>:<GUID>" a declaration
		feature = "season",                       -- Core/Features.lua: with the switch off, neither written, accepted nor sent
		maxBytes = 512,
		authority = function(rec) return ns.Season ~= nil and ns.Season.KindOf(rec) == "S" end,   -- seasons: officers (Q21)
		authorAny = true,                         -- a season stays valid after its officer was demoted
		owner = function(rec, s) if not ns.Season then return false end return ns.Season.ValidRecord(rec, s) end,   -- SEA-01/03/04
		transition = function(held, rec) return ns.Season.Transition(held, rec) end,   -- SEA-02: "locked"
		expires = function(rec, t) return ns.Season ~= nil and ns.Season.Expired(rec, t) end,     -- current + 3 previous (Q20)
		wait = function(rec, ctx) if ns.Season then ns.Season.Wait(rec, ctx) end end,             -- an entry before its season
	},
	raidev = {     -- events and sign-ups (Data/Calendar.lua, M10.5, SPEC-14 §5.5): "R:<key>:<GUID>" a role, "F:<GUID>:<n>" an
		feature = "season",                       -- event only of the addon (officers), "A:<key>:<GUID>" an answer to one, "H:<id>" a
		maxBytes = 12288,                         -- Raid-Helper import, "C:<key>" a line-up (officers). Each kind has its own size
		authority = function(rec) return ns.Calendar ~= nil and ns.Calendar.Authority(rec) end,   -- F:, H:, C: officers (NET-12)
		authorAny = true,                         -- an event stays valid after its officer was demoted
		owner = function(rec, s) if not ns.Calendar then return false end return ns.Calendar.ValidRecord(rec, s) end,
		expires = function(rec, t) return ns.Calendar ~= nil and ns.Calendar.Expired(rec, t) end,   -- 2 days after the event
	},
	avail = {      -- when members usually play (Data/Availability.lua, M10.8, SPEC-14 §8): id = character GUID, { p, w } or { del }
		feature = "season",                       -- Core/Features.lua: with the switch off, neither written, accepted nor sent
		maxBytes = 256,
		owner = function(rec, s) return ns.Availability ~= nil and ns.Availability.ValidRecord(rec, s) end,
		expires = function(rec, t) return ns.Availability ~= nil and ns.Availability.Expired(rec, t) end,   -- 30 days
	},
	rally = {      -- PvP and world rallies (Data/Rallies.lua, M10.9, SPEC-14 §9): "<caller GUID>:<n>" a rally,
		feature = "season",                       -- "<rally id>:<GUID>" an answer to one
		maxBytes = 384,
		volatile = true,                          -- short-lived: never in a summary, never pushed or asked for
		firstHandOnly = true,                     -- only the author's account sends it; an officer cannot relay it
		owner = function(rec) return ns.Rallies ~= nil and ns.Rallies.ValidRecord(rec) end,
		expires = function(rec, t) return ns.Rallies ~= nil and ns.Rallies.Expired(rec, t) end,
	},
	ocfg = {       -- the officers' choices (Data/Inactivity.lua, M8.3): id = "tiers", { tiers = { n1, n2, n3, n4 } }
		maxBytes = 256,
		officerTool = true,
		restricted = function() return true end,
		authority = function() return true end,
		authorAny = true,
		owner = function(rec) return ns.Inactivity ~= nil and ns.Inactivity.ValidConfig(rec) end,
		group = function() return "ocfg" end,
	},
}
Store.SET_ORDER = { "accounts", "contacts", "recipes", "coplay", "likes", "bank", "bankreq", "guildcfg", "timeline", "absence", "onotes", "ocfg", "groups", "addons", "season", "raidev", "avail", "rally", "handbook" }

---------------------------------------------------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------------------------------------------------
local stats = { accepted = 0, unchanged = 0, rejected = 0, reasons = {}, written = 0, pruned = 0 }
Store.stats = stats

-- The store table of the current guild ({ sets = { [set] = { [id] = record } } }), or nil without a guild.
local function root(create)
	local data = ns.GuildKey and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.store) ~= "table" then
		if not create then return nil end
		data.store = { sets = {} }
	end
	if type(data.store.sets) ~= "table" then data.store.sets = {} end
	return data.store
end

-- The records of `set` in the current guild: { [id] = record } (an empty table without a guild).
function Store:Records(set)
	local r = root(true)
	if not r then return {} end
	local t = r.sets[set]
	if type(t) ~= "table" then
		t = {}
		r.sets[set] = t
	end
	return t
end

function Store:Get(set, id)
	if not Store.SETS[set] or id == nil then return nil end
	local r = root(false)
	local t = r and r.sets[set]
	return t and t[id] or nil
end

local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = copy(x) end
	return out
end
Store.Copy = copy

-- 1 when `a` should replace `b`, -1 when `b` wins, 0 when they are the same version.
function Store.Compare(a, b)
	if b == nil then return 1 end
	if a.rev ~= b.rev then return a.rev > b.rev and 1 or -1 end
	local ta, tb = a.time or 0, b.time or 0
	if ta ~= tb then return ta > tb and 1 or -1 end
	if a.author ~= b.author then return tostring(a.author) > tostring(b.author) and 1 or -1 end
	return 0
end

-- A write of this client: the record `id` of `set` with `fields`; author, rev and time are set here. Returns the stored
-- record, or nil plus a reason ("set", "guild", "id", "player", "size", "owner").
function Store:Put(set, id, fields)
	local def = Store.SETS[set]
	if not def or not Store.IsActive(set) then return nil, "set" end
	if not str(id) then return nil, "id" end
	local author = ownGUID()
	if not author then return nil, "player" end
	local records = root(true) and self:Records(set)
	if not records then return nil, "guild" end
	local old = records[id]
	if old and def.immutable then return nil, "immutable" end
	local rec = copy(fields or {})
	rec.id, rec.author, rec.time = id, author, now()
	rec.rev = (old and old.rev or 0) + 1
	if ns.Config and ns.Config.EstimateSize(rec) > def.maxBytes then return nil, "size" end
	if def.owner and not def.owner(rec, self) then return nil, "owner" end
	if def.replaced and old then def.replaced(old, rec, "local") end
	records[id] = rec
	stats.written = stats.written + 1
	emit("STORE_CHANGED", set, id, "local")
	return rec
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving and the trust rules
---------------------------------------------------------------------------------------------------------------------
local function reject(reason)
	stats.rejected = stats.rejected + 1
	stats.reasons[reason] = (stats.reasons[reason] or 0) + 1
	return false, reason
end

local function validShape(rec, def)
	if type(rec) ~= "table" then return "shape" end
	if not str(rec.id) then return "id" end
	if not (str(rec.author, 40) and rec.author:find(Store.GUID_PATTERN)) then return "author" end
	local rev = rec.rev
	if type(rev) ~= "number" or rev ~= floor(rev) or rev < 1 or rev > Store.MAX_REV then return "rev" end
	if type(rec.time) ~= "number" or rec.time ~= rec.time or rec.time < 0 then return "time" end
	if rec.time > now() + Store.MAX_FUTURE then return "future" end
	if ns.Config and ns.Config.EstimateSize(rec) > def.maxBytes then return "size" end
	return nil
end

-- The shape reason of a record of `set` (nil when the shape is right): the checks every received record passes first.
-- Data/Backup.lua checks the records of a backup with it.
function Store.ValidShape(set, rec)
	local def = Store.SETS[set]
	if not def then return "set" end
	return validShape(rec, def)
end

-- The trust decision for one record of `set` that came from `sender` (ctx caches the sender's roster entry).
-- Returns true, or false plus a reason ("set", shape reasons, "sender" (not in the roster), "relay" (not first hand
-- and the sender is no officer), "authority", "observer", "owner").
function Store:Check(set, rec, ctx)
	local def = Store.SETS[set]
	if not def or not Store.IsActive(set) then return false, "set" end
	local bad = validShape(rec, def)
	if bad then return false, bad end
	if def.restricted and def.restricted(rec) and not (ns.Role and ns.Role:IsOfficer()) then return false, "restricted" end
	local member = ctx.member
	if member == nil then
		member = self:Member(ctx.sender) or false
		ctx.member = member
	end
	if not member or type(member.guid) ~= "string" then return false, "sender" end
	local senderGUID, senderOfficer = member.guid, member.officer == true

	if def.authority and def.authority(rec) then
		if not senderOfficer then
			local char = ctx.dist == "WHISPER" and def.firstHand and def.firstHand(rec)
			if not (char and self:SameAccount(senderGUID, char)) then return false, "authority" end
		elseif not def.authorAny then
			local author = self:MemberByGUID(rec.author)
			if not (author and author.officer) then return false, "authority" end
		end
		if def.owner then
			local ok, why = def.owner(rec, self)
			if not ok then return false, why or "owner" end
		end
		return true
	end

	-- the alts of an account may pass on each other's records; "same account" is read from the records already held,
	-- never from the record being checked
	local firstHand = self:SameAccount(senderGUID, rec.author)
	if not firstHand and (not senderOfficer or def.firstHandOnly) then
		-- somebody else's record from a member who is not an officer: a relay (NET-11) or a forged author (NET-10); a set
		-- that only travels first hand (the group finder, GRP-02) takes no relay, not even from an officer
		return false, "relay"
	end
	-- a set with writers (the handbook, HBK-01): first hand, the author must be a writer in this client's roster now; an
	-- officer's relay of somebody else's record stays valid after its author lost the rank (authorAny)
	if def.writer and firstHand then
		local author = self:MemberByGUID(rec.author)
		if not (author and def.writer(rec, author)) then return false, "authority" end
	end

	if def.observation then
		if rec.observer ~= rec.author or type(rec.pairs) ~= "table" then return false, "observer" end
		local present = false
		for pair in pairs(rec.pairs) do
			if type(pair) == "string" and pair:find(rec.author, 1, true) then present = true break end
		end
		if not present then return false, "observer" end
	end
	if def.owner then
		local ok, why = def.owner(rec, self)
		if not ok then return false, why or "owner" end
	end
	return true
end

-- Stores one received record when the trust rules allow it and it is newer than the one held. Returns true when it
-- changed the store, or false plus a reason ("older" and "same" are not errors: nothing to do).
function Store:Accept(set, rec, ctx)
	local ok, why = self:Check(set, rec, ctx)
	if not ok then
		-- a record that waits for another one (a season entry before its season, SPEC-14 SEA-03) is kept aside by its module
		local def = Store.SETS[set]
		if why == "wait" and def and def.wait then def.wait(rec, ctx) end
		return reject(why)
	end
	local records = root(true) and self:Records(set)
	if not records then return reject("guild") end
	local held = records[rec.id]
	if held and Store.SETS[set].immutable then
		-- append-only: the entry held stays; the same entry again is nothing to do, a different one is refused
		if Store.Compare(rec, held) == 0 then
			stats.unchanged = stats.unchanged + 1
			return false, "same"
		end
		return reject("immutable")
	end
	local def = Store.SETS[set]
	if held and def.transition then
		local okT, whyT = def.transition(held, rec)
		if not okT then return reject(whyT or "transition") end
	end
	local cmp = def.compare and held and def.compare(rec, held) or Store.Compare(rec, held)
	if cmp <= 0 then
		stats.unchanged = stats.unchanged + 1
		return false, cmp == 0 and "same" or "older"
	end
	if def.expires and def.expires(rec, now()) then return reject("expired") end
	if def.rate and not def.rate(rec) then return reject("rate") end
	if def.replaced and held then def.replaced(held, rec, "remote") end
	records[rec.id] = copy(rec)
	stats.accepted = stats.accepted + 1
	emit("STORE_CHANGED", set, rec.id, "remote")
	return true
end

-- A batch of records of one set from `sender` (as AceComm gives it) over `dist`. Returns accepted, rejected (records
-- that were simply not newer count as neither).
function Store:Receive(set, records, sender, dist)
	if type(records) ~= "table" then return 0, 1 end
	local ctx = { sender = sender, dist = dist }
	local accepted, rejected = 0, 0
	for _, rec in ipairs(records) do
		local ok, why = self:Accept(set, rec, ctx)
		if ok then accepted = accepted + 1
		elseif why ~= "same" and why ~= "older" then rejected = rejected + 1 end
	end
	return accepted, rejected
end

---------------------------------------------------------------------------------------------------------------------
-- Derived helpers and retention
---------------------------------------------------------------------------------------------------------------------
-- NET-13: the co-play minutes per pair over every observer of `day`, taking the maximum, never the sum.
function Store:MergeMax(day)
	local out = {}
	for _, rec in pairs(self:Records("coplay")) do
		if rec.day == day and type(rec.pairs) == "table" then
			for pair, minutes in pairs(rec.pairs) do
				if type(minutes) == "number" and minutes > (out[pair] or 0) then out[pair] = minutes end
			end
		end
	end
	return out
end

-- Drops what the retention rules expire in the current guild. Returns the number removed.
function Store:Prune()
	local r = root(false)
	if not r then return 0 end
	local t, removed = now(), 0
	for set, def in pairs(Store.SETS) do
		local records = r.sets[set]
		if type(records) == "table" then
			for id, rec in pairs(records) do
				local gone = type(rec) ~= "table"
					or (def.expires and def.expires(rec, t))
					or (rec.del == true and not def.keepDeleted and (rec.time or 0) < t - 60 * DAY)
				if gone then
					records[id] = nil
					removed = removed + 1
				end
			end
		end
	end
	stats.pruned = stats.pruned + removed
	return removed
end

function Store:Count(set)
	local n = 0
	for _ in pairs(self:Records(set)) do n = n + 1 end
	return n
end

function Store:DebugLines()
	local parts = {}
	if root(false) then
		for _, set in ipairs(Store.SET_ORDER) do
			if Store.IsActive(set) then parts[#parts + 1] = set .. " " .. self:Count(set) end
		end
	end
	local reasons = {}
	for k, v in pairs(stats.reasons) do reasons[#reasons + 1] = k .. " " .. v end
	table.sort(reasons)
	return {
		("Store: %s"):format(#parts > 0 and table.concat(parts, ", ") or "no guild data"),
		("  accepted %d, unchanged %d, written %d, pruned %d, refused %d%s"):format(stats.accepted, stats.unchanged,
			stats.written, stats.pruned, stats.rejected, #reasons > 0 and (" (" .. table.concat(reasons, ", ") .. ")") or ""),
	}
end

if ns.addon then
	ns.addon.Store = Store
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Store", function() return Store:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Store)
	Store:RegisterEvent("GUILD_ROSTER_UPDATE", function() Store:RosterChanged() end)
	Store:RegisterEvent("PLAYER_GUILD_UPDATE", function() Store:RosterChanged() end)
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() Store:RosterChanged() end) end
	if ns.OnEnable then ns.OnEnable(function() Store:Prune() end) end
end

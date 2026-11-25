-- DemoData: the invented guild of demo mode (SPEC-11 §3.3, M7.4). Lua 5.1.
-- Pure data and a deterministic generator: no call to the game client and no other module, so it also loads outside
-- the game. Every name below is invented (no real player or guild, ADR 0019); the only things taken from the game
-- are numbers a view looks up through the client later (spell ids of recipes, item ids of the bank, whose names the
-- client gives). The same file could feed the mockup tools of ADR 0019 (tools/make_mockups.py, through lupa): names
-- and values would then come from here instead of from a list of their own. M7.4 does not need that.
--
-- DemoData.Build(now) returns everything the mode puts in place, with every time counted back from `now` (an epoch):
--   guildName, realm, key        "Demo Guild", "Demo", "Demo/Demo Guild"
--   ranks                        { { name, officer }, ... } by rank index (0 = Guild Master)
--   player                       { guid, name, classFile, classID, level, rankIndex }
--   roster                       the rows Compat.Guild.RosterRow gives, in roster order
--   token, ownChars, main        the account of the player: its token, its characters ([guid] = the entry
--                                AzerothAccordDB.chars keeps) and the main
--   sets                         [set] = { [id] = record }: the records of the guild (accounts, contacts, recipes, coplay,
--                                likes, bank, bankreq, guildcfg, timeline, absence, onotes; ocfg stays empty: the default tiers), written as the clients would hold them
--   guildData                    what GuildKey:Data() holds besides the store: { likes, bank, officer, craftAsks }
--   saltBytes                    32 bytes for the notary's salt (the player is an officer, so the like button works)
-- The same call twice with the same `now` gives the same data.
local ADDON_NAME, ns = ...
ns = ns or {}
local DemoData = {}
ns.DemoData, ns.modules = DemoData, ns.modules or {}
ns.modules.DemoData = DemoData
if ns.addon then ns.addon.DemoData = DemoData end   -- also reachable from tests

local floor, char, format = math.floor, string.char, string.format
local DAY, HOUR = 86400, 3600

DemoData.GUILD_NAME, DemoData.REALM = "Demo Guild", "Demo"
DemoData.KEY = DemoData.REALM .. "/" .. DemoData.GUILD_NAME
DemoData.OTHER_GUILD = "Wandering Stars"
DemoData.MAX_LEVEL = 70
DemoData.MEMBERS = 60
DemoData.ONLINE = 15
DemoData.ACCOUNTS = 20
DemoData.RANKS = {
	{ name = "Guild Master", officer = true }, { name = "Officer", officer = true }, { name = "Veteran" },
	{ name = "Member" }, { name = "Initiate" },
}
-- The first member index of each rank: 1 Guild Master, 2-6 officers, 7-20 veterans, 21-45 members, 46-60 initiates.
local RANK_FROM = { 1, 2, 7, 21, 46 }
local LEVEL_BASE = { 70, 70, 68, 58, 38 }   -- the level a rank starts from (then lowered by a spread)

local CLASSES = {
	{ "WARRIOR", 1 }, { "PALADIN", 2 }, { "HUNTER", 3 }, { "ROGUE", 4 }, { "PRIEST", 5 }, { "DEATHKNIGHT", 6 },
	{ "SHAMAN", 7 }, { "MAGE", 8 }, { "WARLOCK", 9 }, { "DRUID", 11 },
}
local ZONES = { "Stormwind City", "Orgrimmar", "Dalaran", "Shattrath City", "Ironforge", "Thunder Bluff", "Elwynn Forest",
	"Durotar", "Hellfire Peninsula", "Borean Tundra" }

-- 60 invented names; the two with a space are a name and a surname (SPEC-11 §6.6).
local NAMES = {
	"Tarvelon", "Mirabeth", "Quillon", "Odrenna", "Vaskel", "Ilyndra", "Brannoc", "Sorvak", "Thessaly", "Gormund",
	"Elowen", "Kaldris", "Pennivar", "Rhosyn", "Dunmara", "Ostrel", "Yvaine", "Corvane", "Lissandre", "Halvric",
	"Nerissa", "Tobrek", "Wendolyn", "Zarith", "Aelin Duskmere", "Brynhild", "Cassivor", "Doranel", "Eswyth", "Fenwick",
	"Galdrin", "Hesperia", "Iolanthe", "Jorvik", "Kestrane", "Lumeria", "Morvaine", "Nethara", "Orsolo", "Pelagia",
	"Quenby", "Ravenna", "Silvaren", "Torvald", "Ulrica", "Vessalin", "Brom Hollowtree", "Xanthe", "Yorrick", "Zephine",
	"Ambriel", "Bastien", "Calyxa", "Dravenor", "Evandrin", "Fiorella", "Garrick", "Hildrun", "Ismeral", "Jessamine",
}
-- Out of the guild (the alts that live elsewhere).
local WANDERER, DRIFTER, OLDTIMER, SIDEKICK = "Wanderel", "Driftmoor", "Ashgrove", "Tinkerlo"

local VERSIONS = { "0.7.0", "0.7.0", "0.7.1", "0.6.2" }
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Members that are the main of one of the 20 accounts, the in-guild alts and the account each alt belongs to (an index
-- into MAINS). Member 2 is the player (an officer); member 31 is its alt in the guild.
local MAINS = { 1, 2, 3, 4, 5, 6, 7, 9, 12, 15, 18, 22, 25, 28, 33, 38, 44, 47, 52, 55 }
local ALTS = { { 30, 1 }, { 31, 2 }, { 34, 3 }, { 36, 4 }, { 40, 7 }, { 42, 8 }, { 46, 9 }, { 49, 10 }, { 53, 12 }, { 57, 13 }, { 58, 14 } }
local PLAYER_INDEX = 2
local NOADDON_ALT_NOTE = 60   -- a member without the addon whose public note says whose alt it is

---------------------------------------------------------------------------------------------------------------------
-- The generator (Park-Miller: the products stay below 2^53, so it gives the same numbers on every Lua)
---------------------------------------------------------------------------------------------------------------------
local function newRandom(seed)
	local s = seed
	return function(n)   -- 1..n
		s = (s * 16807) % 2147483647
		return 1 + s % n
	end
end

local function guidOf(n) return format("Player-9999-%08X", 0x1000 + n) end
local function dayOf(t) return tonumber((date or os.date)("!%Y%m%d", t)) end   -- `date` is the game's global
local function hex(rand, n)
	local out = {}
	for i = 1, n do out[i] = format("%x", rand(16) - 1) end
	return table.concat(out)
end
local function token(rand)
	local out = {}
	for i = 1, 22 do local k = rand(64) out[i] = ALPHABET:sub(k, k) end
	return table.concat(out) .. "=="
end

local function copyList(list)
	local out = {}
	for i, e in ipairs(list) do
		local c = {}
		for k, v in pairs(e) do c[k] = v end
		out[i] = c
	end
	return out
end

local function battleTagOf(name)
	return (name:match("^[^%s]+")) .. "#" .. format("%04d", (#name * 977) % 9000 + 1000)
end

---------------------------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------------------------
function DemoData.Build(now)
	now = floor(tonumber(now) or 0)
	local rand = newRandom(20260524)
	local D = { guildName = DemoData.GUILD_NAME, realm = DemoData.REALM, key = DemoData.KEY, ranks = DemoData.RANKS, sets = {},
		guildData = { likes = { given = {}, queue = {} }, bank = { history = {} } } }
	local sets = D.sets
	for _, set in ipairs({ "accounts", "contacts", "recipes", "coplay", "likes", "bank", "bankreq", "guildcfg", "timeline", "absence", "onotes", "ocfg" }) do sets[set] = {} end

	-- The roster ------------------------------------------------------------------------------------------------------
	local members = {}
	for i = 1, DemoData.MEMBERS do
		local rank = 0
		for r = 1, #RANK_FROM do if i >= RANK_FROM[r] then rank = r - 1 end end
		local class = CLASSES[(i * 7) % #CLASSES + 1]
		local level = LEVEL_BASE[rank + 1] - ((i * 11) % 25) + rand(5)
		level = math.max(10, math.min(DemoData.MAX_LEVEL, level))
		if i <= 6 then level = DemoData.MAX_LEVEL end
		local online = i % 4 == 2   -- 15 of the 60, the player among them
		local m = { index = i, name = NAMES[i], guid = guidOf(i), rankIndex = rank, rankName = DemoData.RANKS[rank + 1].name,
			level = level, classFile = class[1], classID = class[2], zone = ZONES[(i * 3) % #ZONES + 1], online = online }
		if not online then m.lastOnlineHours = 1 + ((i * 53) % 90) * 24 + (i * 7) % 24 end
		members[i] = m
	end
	-- a few notes: the public note of one member without the addon says whose alt it is (ACC-05)
	members[1].note, members[3].note, members[8].note = "Raid leader", "Tank, ask for runs", "Herbalist"
	members[NOADDON_ALT_NOTE].note = "alt: " .. members[MAINS[9]].name
	members[1].officerNote = "Founder"
	members[4].officerNote = "Keeps the bank"
	D.members = members

	local rows = {}
	for i, m in ipairs(members) do
		rows[i] = { name = m.name, rankName = m.rankName, rankIndex = m.rankIndex, level = m.level, classFile = m.classFile,
			zone = m.zone, note = m.note, officerNote = m.officerNote, online = m.online, guid = m.guid,
			lastOnlineHours = m.lastOnlineHours, source = "roster" }
	end
	D.roster = rows

	local me = members[PLAYER_INDEX]
	D.player = { guid = me.guid, name = me.name, classFile = me.classFile, classID = me.classID, level = me.level, rankIndex = me.rankIndex }

	-- The accounts ------------------------------------------------------------------------------------------------------
	local accounts = {}   -- [n] = { token, chars = { entries }, main = guid, members = { indexes } }
	for n, idx in ipairs(MAINS) do
		accounts[n] = { token = token(rand), chars = {}, main = members[idx].guid, members = { idx }, version = VERSIONS[(n - 1) % #VERSIONS + 1] }
	end
	for _, alt in ipairs(ALTS) do table.insert(accounts[alt[2]].members, alt[1]) end
	local function entry(m, inGuild)
		return { guid = m.guid, name = m.name, realm = DemoData.REALM, classID = m.classID, level = m.level, inGuild = inGuild }
	end
	for _, acc in ipairs(accounts) do
		for _, idx in ipairs(acc.members) do acc.chars[#acc.chars + 1] = entry(members[idx], true) end
	end
	-- characters of an account that live outside the guild (SPEC-11 §2): another guild, no guild, and a stale one
	local outsiders = {
		{ account = 5, n = 61, name = WANDERER, class = 8, level = 61, guild = DemoData.OTHER_GUILD, seenAgo = 3 },
		{ account = 7, n = 62, name = DRIFTER, class = 4, level = 34, guild = "", seenAgo = 10 },
		{ account = 8, n = 63, name = OLDTIMER, class = 3, level = 70, guild = "Old Banner", seenAgo = 45 },
		{ account = 2, n = 64, name = SIDEKICK, class = 9, level = 22, guild = "", seenAgo = 2 },   -- the player's own third character
	}
	D.outsiders = {}
	for _, o in ipairs(outsiders) do
		local day = (now - o.seenAgo * DAY)
		local e = { guid = guidOf(o.n), name = o.name, realm = DemoData.REALM, classID = o.class, level = o.level, inGuild = false,
			guild = o.guild, seen = day - day % DAY }
		table.insert(accounts[o.account].chars, e)
		D.outsiders[#D.outsiders + 1] = e
	end
	D.accounts = accounts

	-- the account of the player: its token, its characters as AzerothAccordDB keeps them, its main
	local mine = accounts[2]
	D.token, D.main = mine.token, me.guid
	D.ownChars = {}
	for k, e in ipairs(mine.chars) do
		local seen = e.seen or now
		D.ownChars[e.guid] = { name = e.name, classID = e.classID, level = e.level, guild = e.inGuild and DemoData.KEY or e.guild,
			guildAt = seen, seen = seen, added = now - (200 - k * 30) * DAY, answered = seen }
	end

	-- every character in the guild with the addon publishes its own `accounts` record, and a `contacts` one for some
	for n, acc in ipairs(accounts) do
		for k, idx in ipairs(acc.members) do
			local m = members[idx]
			local time = now - (k * 3 + n) * HOUR
			sets.accounts[m.guid] = { id = m.guid, author = m.guid, rev = 1 + (n % 3), time = time, token = acc.token, chars = copyList(acc.chars),
				main = acc.main, addonVersion = acc.version }
			if k == 1 and n % 3 ~= 0 then
				local c = { id = m.guid, author = m.guid, rev = 1, time = time, account = acc.token }
				c.battleTag = battleTagOf(m.name)
				if n % 2 == 0 then c.discord = m.name:lower():gsub("%s", "_") .. "_" .. (n * 7) end
				sets.contacts[m.guid] = c
			end
		end
	end
	D.hasAddon = {}
	for _, acc in ipairs(accounts) do for _, idx in ipairs(acc.members) do D.hasAddon[members[idx].guid] = true end end

	-- Professions: three, each with real spell ids of the game (the client gives the names) ----------------------------
	local PROFESSIONS = {
		{ line = 171, name = "Alchemy", ids = { 2329, 2330, 2331, 2332, 2333, 2334, 2335, 2336, 3170, 3171, 3172, 3173, 3174,
			3175, 3176, 3177, 3447, 3448, 3449, 3450, 3451, 3452, 3453, 3454, 4508 } },
		{ line = 164, name = "Blacksmithing", ids = { 2660, 2661, 2662, 2663, 2664, 2665, 2666, 2667, 2668, 2670, 2671, 2672,
			2673, 2737, 2738, 2739, 2740, 2741, 3115, 3116, 3117, 3293, 3294, 3295 } },
		{ line = 333, name = "Enchanting", ids = { 7418, 7420, 7426, 7428, 7454, 7457, 7745, 7766, 7771, 7779, 7782, 7788, 7793,
			7795, 7857, 7859, 7861, 7863 } },
	}
	local crafters = { 1, 3, 5, 7, 9, 12, 15, 18, 22, 25, 28, 33, 38, 44, 47, 52 }   -- member indexes
	for k, idx in ipairs(crafters) do
		local m = members[idx]
		for p = 0, (k % 2) do
			local prof = PROFESSIONS[(k + p) % #PROFESSIONS + 1]
			local ids = {}
			local keep = 8 + (k * 5 + p * 3) % (#prof.ids - 7)
			for j = 1, math.min(keep, #prof.ids) do ids[j] = prof.ids[j] end
			local id = m.guid .. ":" .. prof.line
			local age = (k == 6 and p == 0) and 70 * DAY or (k * 2 + p) * HOUR   -- one list is old (dimmed)
			sets.recipes[id] = { id = id, author = m.guid, rev = 1, time = now - age, char = m.guid, skillLine = prof.line,
				ids = ids, rank = 150 + (k * 11) % 150, maxRank = 300, name = prof.name }
		end
	end

	-- Co-play: 30 days of observations, with two groups of friends who play together ------------------------------------
	local groupA, groupB = { 1, 3, 5, 7, 9, 12 }, { 15, 18, 22, 25, 28 }
	local function pairKey(a, b) if a > b then a, b = b, a end return a .. ":" .. b end
	for d = 1, 30 do
		local t = now - d * DAY
		local day = dayOf(t)
		for g, group in ipairs({ groupA, groupB }) do
			if (d + g) % 4 ~= 0 then   -- some days a group does not meet
				local observer = members[group[(d % #group) + 1]]
				local pairs_ = {}
				for i = 1, #group do
					for j = i + 1, #group do
						if rand(5) > 1 then pairs_[pairKey(members[group[i]].guid, members[group[j]].guid)] = 20 + rand(100) end
					end
				end
				if g == 1 and d % 5 == 0 then   -- a little mixing between the groups
					pairs_[pairKey(members[groupA[1]].guid, members[groupB[1]].guid)] = 15 + rand(30)
				end
				-- the observer must be in at least one pair
				local mineSome = false
				for key in pairs(pairs_) do if key:find(observer.guid, 1, true) then mineSome = true end end
				if not mineSome then
					local other = members[group[((d + 1) % #group) + 1]]
					if other.guid ~= observer.guid then pairs_[pairKey(observer.guid, other.guid)] = 30 end
				end
				local id = observer.guid .. ":" .. day .. ":1"
				sets.coplay[id] = { id = id, author = observer.guid, rev = 1, time = t, day = day, observer = observer.guid, pairs = pairs_ }
			end
		end
	end

	-- Likes: 40 entries of the ledger, written by the officers (the notaries); the pseudonyms are invented -----------------
	local voters = {}
	for i = 1, 14 do voters[i] = hex(rand, 32) end
	local targets = {}
	for _, acc in ipairs(accounts) do targets[#targets + 1] = acc.main end
	local n = 0
	while n < 40 do
		local target = targets[(rand(#targets) * rand(3)) % #targets + 1]
		local pseudonym = voters[rand(#voters)]
		local id = pseudonym:sub(1, 16) .. ":" .. target
		if not sets.likes[id] then
			local notary = members[1 + (n % 6)].guid   -- the Guild Master and the five officers
			local t = now - rand(60) * DAY
			sets.likes[id] = { id = id, author = notary, rev = 1, time = t, pseudonym = pseudonym, tag = hex(rand, 16), target = target, day = dayOf(t) }
			n = n + 1
		end
	end
	D.guildData.likes.given[members[4].guid] = now - 12 * DAY   -- the player already liked one member

	-- The bank: three tabs (one for officers only), money, logs of 30 days, six requests ------------------------------------
	local reader = members[22]      -- a member (rank 3) captured the open tabs
	local officer = members[4]      -- an officer captured the officers' tab
	local function items(list)
		local parts = {}
		for slot, it in ipairs(list) do parts[slot] = format("%d.%d.%d", slot, it[1], it[2]) end
		return table.concat(parts, ","), #list
	end
	local TABS = {
		{ tab = 1, name = "Consumables", icon = "Interface\\Icons\\INV_Potion_54", author = reader, items = {
			{ 118, 20 }, { 929, 12 }, { 3827, 8 }, { 2455, 15 }, { 858, 10 }, { 1710, 9 }, { 3387, 4 }, { 5634, 6 }, { 6049, 5 }, { 2459, 7 } } },
		{ tab = 2, name = "Materials", icon = "Interface\\Icons\\INV_Ore_Copper_01", author = reader, items = {
			{ 2589, 200 }, { 2592, 160 }, { 4306, 90 }, { 2770, 180 }, { 2771, 120 }, { 2772, 75 }, { 765, 60 }, { 2447, 45 },
			{ 2840, 100 }, { 3575, 66 }, { 5498, 12 }, { 3820, 30 } } },
		{ tab = 3, name = "Officers", icon = "Interface\\Icons\\INV_Misc_Coin_01", author = officer, restricted = true, items = {
			{ 12662, 3 }, { 7078, 4 }, { 7076, 6 }, { 7910, 2 }, { 13926, 1 } } },
	}
	for k, t in ipairs(TABS) do
		local text, count = items(t.items)
		local id = t.author.guid .. ":t" .. t.tab
		sets.bank[id] = { id = id, author = t.author.guid, rev = 1, time = now - (k * 5 + 2) * HOUR, kind = "tab", tab = t.tab, name = t.name,
			icon = t.icon, rank = t.author.rankIndex, restricted = t.restricted, it = text, n = count }
	end
	local GOLD = 10000
	local money = 4835 * GOLD + 4200
	sets.bank[reader.guid .. ":money"] = { id = reader.guid .. ":money", author = reader.guid, rev = 1, time = now - 3 * HOUR, kind = "money", money = money }
	-- money over time and the logs
	local history, level = {}, money - 600 * GOLD
	for d = 30, 0, -1 do
		level = level + (rand(40) - 12) * GOLD
		history[#history + 1] = { t = now - d * DAY, m = math.max(level, 100 * GOLD) }
	end
	history[#history].m = money
	D.guildData.bank.history = history
	local MONEY_KINDS = { "deposit", "deposit", "withdraw", "repair", "deposit" }
	local logMoney, logItems = {}, { {}, {}, {} }
	local ITEM_KINDS = { "deposit", "withdraw", "deposit", "move" }
	for i = 1, 36 do
		local who = members[MAINS[(i * 5) % #MAINS + 1]].name
		local t = now - (i * 20 + rand(15)) * HOUR
		local kind = MONEY_KINDS[i % #MONEY_KINDS + 1]
		logMoney[#logMoney + 1] = format("%s,%s,0,%d,%d", kind, who, (kind == "deposit" and 25 or 12) * GOLD + rand(90) * 100, t)
		local tab = i % 2 + 1
		local list = TABS[tab].items
		local it = list[rand(#list)]
		logItems[tab][#logItems[tab] + 1] = format("%s,%s,%d,%d,%d", ITEM_KINDS[i % #ITEM_KINDS + 1], who, it[1], 1 + rand(10), t)
	end
	local function logRecord(tab, author, entries, restricted)
		local id = author.guid .. ":log:" .. tab
		sets.bank[id] = { id = id, author = author.guid, rev = 1, time = now - 4 * HOUR, kind = "log", tab = tab, rank = tab > 0 and author.rankIndex or nil,
			restricted = restricted, e = table.concat(entries, ";"), n = #entries }
	end
	logRecord(0, reader, logMoney)
	logRecord(1, reader, logItems[1])
	logRecord(2, reader, logItems[2])
	logRecord(3, officer, { format("deposit,%s,12662,3,%d", members[1].name, now - 5 * DAY), format("withdraw,%s,7078,2,%d", officer.name, now - 9 * DAY) }, true)
	-- the requests: one in every state, the player's own among them
	local function request(requester, n, fields, history, status, decider)
		local id = requester.guid .. ":" .. n
		local rec = { id = id, requester = requester.guid, created = fields.created, kind = fields.kind, itemID = fields.itemID, count = fields.count,
			amount = fields.amount, tip = fields.tip, reason = fields.reason, note = fields.note, status = status, history = history }
		rec.author = decider and decider.guid or requester.guid
		rec.rev = decider and 2 or 1
		rec.time = history[#history].t
		sets.bankreq[id] = rec
	end
	local function hist(...) -- { status, by, ago in hours }, ...
		local out = {}
		for i, h in ipairs({ ... }) do out[i] = { s = h[1], by = h[2].guid, t = now - h[3] * HOUR } end
		return out
	end
	local a, b, c = members[7], members[PLAYER_INDEX], members[12]
	request(a, 1, { kind = "withdraw", itemID = 2840, count = 40, reason = "Copper bars for the new smiths", tip = 2 * GOLD,
		created = now - 30 * HOUR },
		hist({ "open", a, 30 }), "open")
	request(c, 1, { kind = "withdraw", amount = 150 * GOLD, reason = "Repair bill after the raid", created = now - 80 * HOUR },
		hist({ "open", c, 80 }), "open")
	request(b, 1, { kind = "deposit", itemID = 4306, count = 30, reason = "Silk from the weekend farming", created = now - 50 * HOUR },
		hist({ "open", b, 50 }), "open")
	request(members[9], 1, { kind = "withdraw", itemID = 929, count = 5, reason = "Potions for the new tank", tip = 5 * GOLD,
		created = now - 120 * HOUR },
		hist({ "open", members[9], 120 }, { "approved", members[1], 100 }), "approved", members[1])
	request(members[15], 1, { kind = "donation", amount = 80 * GOLD, reason = "A gift for the guild", created = now - 200 * HOUR },
		hist({ "open", members[15], 200 }, { "approved", members[3], 190 }, { "fulfilled", members[4], 150 }), "fulfilled", members[4])
	local rejected = members[18]
	request(rejected, 1, { kind = "withdraw", itemID = 12662, count = 2, reason = "For my alt", note = "Officers' tab, ask again after the raid",
		created = now - 260 * HOUR }, hist({ "open", rejected, 260 }, { "rejected", members[5], 240 }), "rejected", members[5])
	request(members[25], 1, { kind = "withdraw", itemID = 2589, count = 50, reason = "No longer needed", created = now - 300 * HOUR },
		hist({ "open", members[25], 300 }, { "cancelled", members[25], 290 }), "cancelled")

	-- The settings the officers chose ------------------------------------------------------------------------------------
	sets.guildcfg.sources = { id = "sources", author = members[1].guid, rev = 1, time = now - 40 * DAY, raid = "accord", loot = "none" }

	-- The timeline (SPEC-12 §7): changes of the roster seen by two officers, the Guild Master and the player. Some were seen by
	-- both, the first one over a few minutes and the other one over days (they are one event when read, TL-09).
	local obsA, obsB = members[1], members[PLAYER_INDEX]
	local ghostGUID = guidOf(70)
	local seen = {}   -- observer guid -> day -> { events }
	local function observe(observer, ev)
		local day = dayOf(ev.b)
		seen[observer.guid] = seen[observer.guid] or {}
		seen[observer.guid][day] = seen[observer.guid][day] or {}
		table.insert(seen[observer.guid][day], ev)
	end
	local function change(ago, who, kind, fields, both)
		local m = type(who) == "number" and members[who] or nil
		local g, name = m and m.guid or ghostGUID, m and m.name or "Vexmoor"
		local at = now - ago * DAY - 7 * HOUR
		local function make(a, b)
			local e = { k = kind, g = g, n = name, a = a, b = b }
			for k, v in pairs(fields) do e[k] = v end
			return e
		end
		observe(obsA, make(at - 1800, at))
		if both then observe(obsB, make(at - 3 * DAY, at + 4 * HOUR)) end
	end
	for k, who in ipairs({ 58, 59, 60 }) do
		local m = members[who]
		change(40 - (k - 1) * 14, who, "join", { r = m.rankIndex, rn = m.rankName, l = math.max(1, m.level - 4) }, k ~= 2)
	end
	change(15, "gone", "leave", { rn = "Member", l = 55 }, true)
	change(30, 25, "rank", { f = 4, t = 3, fn = "Initiate", tn = "Member" }, true)
	change(12, 9, "rank", { f = 3, t = 2, fn = "Member", tn = "Veteran" }, false)
	change(5, 31, "level", { f = members[31].level - 3, t = members[31].level }, false)
	change(2, 12, "level", { f = members[12].level - 1, t = members[12].level }, true)
	change(10, 60, "note", { f = "", t = members[60].note }, false)
	change(1, 33, "note", { f = "Looking for a guild", t = "Raider" }, false)
	for _, observer in ipairs({ obsA, obsB }) do
		local days = {}
		for day in pairs(seen[observer.guid] or {}) do days[#days + 1] = day end
		table.sort(days)
		for _, day in ipairs(days) do
			local list, last = seen[observer.guid][day], 0
			for _, e in ipairs(list) do last = math.max(last, e.b) end
			local id = observer.guid .. ":" .. day .. ":1"
			sets.timeline[id] = { id = id, author = observer.guid, rev = 1, time = last + 600, observer = observer.guid, day = day, ev = list }
		end
	end

	-- Three declared absences (SPEC-12 §7), for members who have not been online for two weeks or more: one declared by the
	-- member, two set by the Guild Master
	local away = 0
	for i = 6, DemoData.MEMBERS do
		local m = members[i]
		if away < 3 and not m.online and m.lastOnlineHours >= 14 * 24 then
			away = away + 1
			local kind = away == 1 and "self" or "off"
			local written = now - (away * 2) * DAY
			sets.absence[m.guid .. ":" .. kind] = { id = m.guid .. ":" .. kind, author = kind == "self" and m.guid or members[1].guid,
				rev = 1, time = written, char = m.guid, from = dayOf(written), ["until"] = dayOf(now + (away * 9) * DAY) }
		end
	end

	-- Five extended notes of the officers (SPEC-12 §5, §7), written by the Guild Master and two officers; one is two lines long
	do
		local texts = {
			{ 7, 1, "Raid leader on Thursdays. Keeps the loot list.\nAsk before changing the raid times." },
			{ 12, 3, "Recruited from the trade channel, very helpful with new players." },
			{ 25, 4, "Asked for a break: exams until the end of the month." },
			{ 33, 1, "Alt of a former member, rejoined in the spring." },
			{ 40, 3, "Enchanter: wants the materials sent by mail, not traded." },
		}
		for k, n in ipairs(texts) do
			local m, author = members[n[1]], members[n[2]]
			sets.onotes[m.guid] = { id = m.guid, author = author.guid, rev = 1, time = now - (k * 3) * DAY, char = m.guid, text = n[3] }
		end
	end

	-- The officer's queue (SPEC-12 §7): four entries of the player, three still to do and one the roster showed done
	do
		local idle = {}
		for i = 21, DemoData.MEMBERS do
			local m = members[i]
			if not m.online and m.lastOnlineHours >= 14 * 24 and i ~= 31 then idle[#idle + 1] = m end
		end
		table.sort(idle, function(a, b)
			if a.lastOnlineHours ~= b.lastOnlineHours then return a.lastOnlineHours > b.lastOnlineHours end
			return a.index < b.index
		end)
		local queue = {}
		local function entry(m, daysAgo, op, fields)
			local e = { n = #queue + 1, g = m.guid, name = m.name, op = op, created = now - daysAgo * DAY, by = members[PLAYER_INDEX].guid,
				status = "open" }
			for k, v in pairs(fields or {}) do e[k] = v end
			queue[#queue + 1] = e
		end
		entry(members[25], 4, "demote", { fromRank = 3, toRank = 4 })
		entry(idle[1] or members[59], 3, "remove", { fromRank = (idle[1] or members[59]).rankIndex })
		entry(idle[2] or members[58], 2, "note", { noteKind = "public", text = "Away since the summer" })
		local done = members[9]
		entry(done, 12, "promote", { fromRank = done.rankIndex + 1, toRank = done.rankIndex, status = "done", closed = now - 2 * DAY })
		D.guildData.officer = { queue = queue, queueSeq = #queue }
	end

	-- Two craft requests the player wrote to crafters of the lists above: the reminders of the Action Center (SPEC-13)
	D.guildData.craftAsks = {
		{ guid = members[7].guid, recipeId = 2660, at = now - 2 * DAY },
		{ guid = members[3].guid, recipeId = 7418, at = now - 3 * HOUR },
	}

	-- Six listings of the guild group finder and two applications to the player's own (SPEC-13 §6.10), outside D.sets:
	-- Core/Demo.lua puts them in place only while the switch `groups` is on.
	do
		local player = members[PLAYER_INDEX]
		local listings = {}
		local function listing(m, n, minutesAgo, fields)
			local created = now - minutesAgo * 60
			local rec = { id = m.guid .. ":" .. n, author = m.guid, rev = 1, time = created, created = created, ends = created + 2 * HOUR,
				status = "open", have = 1, size = 5, min = 1, max = 60 }
			for k, v in pairs(fields) do rec[k] = v end
			listings[rec.id] = rec
			return rec
		end
		local own = listing(player, 1, 12, { kind = "dungeon", act = 329, min = 55, max = 60, have = 2, need = { t = 1, h = 1, d = 1 },
			note = "Full clear, quests welcome", meet = "At the bank" })
		local online = {}
		for _, m in ipairs(members) do
			if m.online and m ~= player then online[#online + 1] = m end
		end
		listing(online[1], 1, 4, { kind = "dungeon", act = 36, min = 15, max = 25, need = { t = 0, h = 1, d = 2 }, have = 2,
			note = "Quests first, then the full run" })
		listing(online[2], 1, 18, { kind = "raid", act = 409, size = 40, min = 60, have = 22, need = { t = 1, h = 4, d = 8 },
			note = "Bring fire resistance", meet = "Entrance, 20:45" })
		listing(online[3], 1, 27, { kind = "quest", act = "Stranglethorn Vale", min = 30, max = 45, need = { t = 0, h = 0, d = 2 } })
		listing(online[4], 1, 41, { kind = "help", act = "Elwynn Forest", size = 2, need = { t = 0, h = 0, d = 1 },
			note = "Need a hand with an elite" })
		listing(online[5], 1, 55, { kind = "farm", act = "Un'Goro Crater", min = 48, need = { t = 0, h = 1, d = 2 } })
		local apps = {}
		apps[online[6].name] = { r = "t", c = "I know the place", l = 60, at = now - 6 * 60, guid = online[6].guid }
		apps[online[7].name] = { r = "h", l = 58, at = now - 2 * 60, guid = online[7].guid }
		D.groups = { listings = listings, own = own.id, apps = apps }
	end

	-- 32 bytes for the notary's salt
	local salt = {}
	for i = 1, 32 do salt[i] = char(rand(256) - 1) end
	D.saltBytes = table.concat(salt)
	return D
end

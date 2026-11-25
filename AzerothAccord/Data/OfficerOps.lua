-- OfficerOps: the cleanup review and the queue of actions to do by hand (SPEC-12 §4, M8.4, ADR 0023). Lua 5.1.
--
--   Nothing here changes the roster (OPS-01): the review only fills a queue, the officer does each action in the game's own
--   windows or by typing the game's command, and an entry is ticked when a complete roster read shows it done (OPS-02).
--   Tests/test_officer_ops.lua fails when a function that changes the roster is named anywhere in the addon.
--
--   Review     Ops:Proposal({ minTier, reviewed, unknown }) -> { groups = { { tier = 4..1 | nil (unknown), accounts } }, count }:
--              the accounts of Data/Inactivity.lua by tier, never the ones away or with an officer character. Ops:Draft(account)
--              holds the choice for one account (and the ones of single characters, draft.per); Ops:Plan(drafts) says what the
--              choices would add; Ops:Apply(drafts) adds it, and marks the accounts kept whole as reviewed for 30 days.
--   Queue      GuildKey:Data().officer.queue, of this account, never sent. Entry: { n, g, name, op ("promote" | "demote" |
--              "remove" | "note"), fromRank, toRank, noteKind ("public" | "officer"), text, created, by, status ("open" |
--              "done" | "gone" | "expired" | "cancelled"), closed }. At most MAX_OPEN open ones; a new entry for the same
--              character and op replaces the open one. Open for EXPIRE seconds -> "expired"; a closed one is deleted KEEP
--              seconds after it was closed (OPS-03).
--   Visibility only an officer's character reads or writes any of it; a demoted officer loses it (Officer:Purge, OFF-10).
-- Bus: OPS_CHANGED() when the queue or the reviewed accounts changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Ops = {}
ns.OfficerOps, ns.modules = Ops, ns.modules or {}
ns.modules.OfficerOps = Ops

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor = math.floor
local sort, remove = table.sort, table.remove

local DAY = 86400
Ops.MAX_OPEN = 200
Ops.EXPIRE = 14 * DAY            -- an entry open this long expires (OPS-03)
Ops.KEEP = 7 * DAY               -- a closed entry stays this long
Ops.REVIEWED = 30 * DAY          -- an account kept in a review is not proposed again for this long
Ops.NOTE_MAX = 31                -- characters of a note in the game's window [verify]
Ops.DEFAULT_TIER = 4
Ops.EVENTS = 3                   -- timeline lines of an account in the review
Ops.ACTIONS = { "keep", "remove", "demote", "promote", "note" }

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

function Ops.Allowed()
	return ns.Role ~= nil and ns.Role:IsOfficer() == true
end

-- The officer table to read (nil for a member, and while nothing was ever stored).
local function peek()
	if not Ops.Allowed() then return nil end
	return ns.Officer:Peek()
end

local function data()
	if not Ops.Allowed() then return nil end
	return ns.Officer:Data()
end

local function trim(text) return (text:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")) end

---------------------------------------------------------------------------------------------------------------------
-- Reviewed accounts
---------------------------------------------------------------------------------------------------------------------
-- The key an account is remembered by: Accounts:AccountKey of its main.
function Ops.KeyOf(account)
	local guid = account.main.guid
	return ns.Accounts and ns.Accounts:AccountKey(guid) or guid
end

function Ops:ReviewedAt(key, t)
	local O = peek()
	local at = O and type(O.reviewed) == "table" and O.reviewed[key]
	if type(at) ~= "number" or (t or now()) - at >= Ops.REVIEWED then return nil end
	return at
end

---------------------------------------------------------------------------------------------------------------------
-- The review: proposal and choices
---------------------------------------------------------------------------------------------------------------------
-- The accounts to review, grouped by tier, the longest away first. filter: minTier (4), reviewed (include the accounts
-- reviewed in the last 30 days), unknown (include the accounts of which no date is known).
function Ops:Proposal(filter, t)
	filter = filter or {}
	t = t or now()
	local out = { groups = {}, count = 0 }
	if not Ops.Allowed() then return out end
	local minTier = filter.minTier or Ops.DEFAULT_TIER
	local rows = ns.Inactivity:Rows({ minTier = minTier, away = false, unknown = filter.unknown == true }, t)
	local byTier = {}
	for _, a in ipairs(rows) do
		if not a.officer and not a.away and (filter.reviewed or not self:ReviewedAt(Ops.KeyOf(a), t)) then
			local tier = (not a.unknown) and a.tier or 0
			if not byTier[tier] then byTier[tier] = {} end
			byTier[tier][#byTier[tier] + 1] = a
			out.count = out.count + 1
		end
	end
	for _, tier in ipairs({ 4, 3, 2, 1, 0 }) do
		if byTier[tier] then
			out.groups[#out.groups + 1] = { tier = tier > 0 and tier or nil, accounts = byTier[tier] }
		end
	end
	return out
end

function Ops:Draft(account)
	return { account = account, action = "keep", rank = nil, noteKind = "public", text = "", per = {} }
end

-- The choice that counts for one character: its own, or the account's.
function Ops.ChoiceOf(draft, guid)
	return draft.per[guid] or draft
end

function Ops.MyRank()
	local _, _, rank = compat().Guild.PlayerRank()
	return rank
end

-- The ranks an officer may move a character to: those below their own, above (`op` "promote") or below ("demote") the
-- character's rank. { { index, name }, ... } by rank index.
function Ops:RankChoices(op, rankIndex)
	local out = {}
	local mine = Ops.MyRank()
	if not mine or (rankIndex ~= nil and rankIndex <= mine) then return out end
	for _, rank in ipairs(compat().Guild.Ranks()) do
		local i = rank.index
		if i > mine and (rankIndex == nil or (op == "promote" and i < rankIndex) or (op == "demote" and i > rankIndex)) then
			out[#out + 1] = rank
		end
	end
	return out
end

-- The text of a note as the queue keeps it, or nil when it does not fit the game's window.
function Ops.CleanNote(text)
	if type(text) ~= "string" then return nil end
	text = trim(text)
	if text:find("%c") then return nil end
	local _, chars = text:gsub("[^\128-\191]", "")
	if chars > Ops.NOTE_MAX or #text > Ops.NOTE_MAX * 4 then return nil end
	return text
end

-- What the choice for the character `guid` adds to the queue: the entry's fields, or nil and why not ("keep", "gone",
-- "permission" (the game says this officer may not), "rank" (no such rank change), "same" (nothing would change),
-- "long" (the note is too long)).
function Ops:Resolve(draft, guid)
	local choice = Ops.ChoiceOf(draft, guid)
	local op = choice.action
	if op == "keep" or op == nil then return nil, "keep" end
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	if not e then return nil, "gone" end
	local G = compat().Guild
	local kind = op == "note" and (choice.noteKind == "officer" and "officer" or "public") or nil
	if G.MayDo(op, kind) == false then return nil, "permission" end
	local spec = { g = guid, name = e.short or e.name, op = op }
	if e.realm and e.realm ~= compat().Player.Realm() then spec.name = e.name end
	if op == "note" then
		local text = Ops.CleanNote(choice.text)
		if not text then return nil, "long" end
		local current
		if kind == "officer" then current = G.CanViewOfficerNote() and e.officerNote or nil
		else current = e.note or "" end
		if current and trim(current) == text then return nil, "same" end
		spec.noteKind, spec.text = kind, text
		return spec
	end
	local from, mine = e.rankIndex, Ops.MyRank()
	if not (from and mine) or from <= mine then return nil, "rank" end
	spec.fromRank = from
	if op == "remove" then return spec end
	local to = choice.rank or (op == "promote" and from - 1 or from + 1)
	for _, rank in ipairs(self:RankChoices(op, from)) do
		if rank.index == to then
			spec.toRank = to
			return spec
		end
	end
	return nil, "rank"
end

-- What the choices would do: { add = { spec }, kept = { draft }, skipped = { { g, name, op, why } } }.
function Ops:Plan(drafts)
	local plan = { add = {}, kept = {}, skipped = {} }
	for _, draft in ipairs(drafts or {}) do
		local keptWhole = true
		for _, guid in ipairs(draft.account.chars) do
			local spec, why = self:Resolve(draft, guid)
			if why ~= "keep" then keptWhole = false end
			if spec then plan.add[#plan.add + 1] = spec
			elseif why ~= "keep" then
				local e = ns.Roster and ns.Roster:ByGUID(guid)
				plan.skipped[#plan.skipped + 1] = { g = guid, name = e and (e.short or e.name) or draft.account.name,
					op = Ops.ChoiceOf(draft, guid).action, why = why }
			end
		end
		if keptWhole then plan.kept[#plan.kept + 1] = draft end
	end
	return plan
end

-- Step 3 of the review. Returns { added, replaced, refused (the queue is full), kept, skipped }, or nil for a member.
function Ops:Apply(drafts, t)
	local O = data()
	if not O then return nil end
	t = t or now()
	local plan = self:Plan(drafts)
	local result = { added = 0, replaced = 0, refused = 0, kept = #plan.kept, skipped = #plan.skipped }
	for _, spec in ipairs(plan.add) do
		local entry, replaced = self:Add(spec, t, true)
		if entry then
			result.added = result.added + 1
			if replaced then result.replaced = result.replaced + 1 end
		else
			result.refused = result.refused + 1
		end
	end
	if type(O.reviewed) ~= "table" then O.reviewed = {} end
	for key, at in pairs(O.reviewed) do
		if type(at) ~= "number" or t - at >= Ops.REVIEWED then O.reviewed[key] = nil end
	end
	for _, draft in ipairs(plan.kept) do O.reviewed[Ops.KeyOf(draft.account)] = t end
	emit("OPS_CHANGED")
	return result
end

---------------------------------------------------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------------------------------------------------
local function queueOf(O) return O and type(O.queue) == "table" and O.queue or nil end

local function close(entry, status, t)
	entry.status, entry.closed = status, t
end

-- OPS-03: expires what was open too long, deletes what was closed long enough. true when something changed.
function Ops:Sweep(t, silent)
	local list = queueOf(peek())
	if not list then return false end
	t = t or now()
	local changed = false
	for i = #list, 1, -1 do
		local e = list[i]
		if e.status == "open" then
			if t - e.created >= Ops.EXPIRE then
				close(e, "expired", t)
				changed = true
			end
		elseif t - (e.closed or e.created) >= Ops.KEEP then
			remove(list, i)
			changed = true
		end
	end
	if changed and not silent then emit("OPS_CHANGED") end
	return changed
end

-- Adds one entry. Returns it and true when it replaced an open one of the same character and op; nil and "full" | "off".
function Ops:Add(spec, t, silent)
	local O = data()
	if not O then return nil, "off" end
	t = t or now()
	if type(O.queue) ~= "table" then O.queue = {} end
	self:Sweep(t, true)
	local list, open, old = O.queue, 0, nil
	for i, e in ipairs(list) do
		if e.status == "open" then
			if e.g == spec.g and e.op == spec.op then old = i else open = open + 1 end
		end
	end
	if open >= Ops.MAX_OPEN then return nil, "full" end
	if old then remove(list, old) end
	O.queueSeq = (O.queueSeq or 0) + 1
	local entry = { n = O.queueSeq, g = spec.g, name = spec.name, op = spec.op, fromRank = spec.fromRank, toRank = spec.toRank,
		noteKind = spec.noteKind, text = spec.text, created = floor(t), by = compat().Player.GUID(), status = "open" }
	list[#list + 1] = entry
	if not silent then emit("OPS_CHANGED") end
	return entry, old ~= nil
end

-- The open entries, the oldest first, then the closed ones, the last closed first.
function Ops:Entries(t)
	self:Sweep(t, true)
	local open, closed = {}, {}
	for _, e in ipairs(queueOf(peek()) or {}) do
		if e.status == "open" then open[#open + 1] = e else closed[#closed + 1] = e end
	end
	sort(open, function(a, b)
		if a.created ~= b.created then return a.created < b.created end
		return a.n < b.n
	end)
	sort(closed, function(a, b)
		if a.closed ~= b.closed then return a.closed > b.closed end
		return a.n > b.n
	end)
	for _, e in ipairs(closed) do open[#open + 1] = e end
	return open
end

function Ops:OpenCount(t)
	self:Sweep(t, true)
	local n = 0
	for _, e in ipairs(queueOf(peek()) or {}) do if e.status == "open" then n = n + 1 end end
	return n
end

function Ops:Get(n)
	for _, e in ipairs(queueOf(peek()) or {}) do if e.n == n then return e end end
	return nil
end

-- Closes an open entry by hand.
function Ops:Cancel(n)
	local e = self:Get(n)
	if not e or e.status ~= "open" then return false end
	close(e, "cancelled", now())
	emit("OPS_CHANGED")
	return true
end

-- The rows of the Action Center for the queue (SPEC-13 §2.3): one per kind of action still to do, with how many, waiting
-- since the oldest of them. Only for who may see the queue; it only reads (an entry past EXPIRE is left out, not swept).
function Ops:ActionRows(t)
	local rows = {}
	if not (ns.Officer and ns.Officer.CanSee("inactivity")) then return rows end
	t = t or now()
	local count, oldest = {}, {}
	for _, e in ipairs(queueOf(peek()) or {}) do
		if e.status == "open" and t - e.created < Ops.EXPIRE then
			count[e.op] = (count[e.op] or 0) + 1
			if not oldest[e.op] or e.created < oldest[e.op] then oldest[e.op] = e.created end
		end
	end
	for _, op in ipairs(Ops.ACTIONS) do
		if count[op] then
			local key = "ACT_OPS_" .. op:upper() .. (count[op] == 1 and "_ONE" or "")
			rows[#rows + 1] = { key = "queue:" .. op, urgency = 2, time = oldest[op], title = ns.L[key]:format(count[op]),
				open = function() if ns.OfficersView then ns.OfficersView:OpenPage("queue") end end }
		end
	end
	return rows
end

-- Only a change of the officers' note, for an officer who may not read it, cannot be ticked from the roster (OPS-02).
function Ops:CanMarkDone(entry)
	return entry ~= nil and entry.status == "open" and entry.op == "note" and entry.noteKind == "officer"
		and not compat().Guild.CanViewOfficerNote()
end

function Ops:MarkDone(n)
	local e = self:Get(n)
	if not self:CanMarkDone(e) then return false end
	close(e, "done", now())
	emit("OPS_CHANGED")
	return true
end

-- The new status of an open entry given the character's row in a complete read (nil when it is not there), or nil.
local function outcome(e, row, seesOfficerNote)
	if e.op == "remove" then return (not row) and "done" or nil end
	if not row then return "gone" end
	if e.op == "promote" or e.op == "demote" then
		return row.rankIndex == e.toRank and "done" or nil
	end
	local current
	if e.noteKind == "officer" then
		if not seesOfficerNote then return nil end
		current = row.officerNote
		-- the client may answer nothing for an empty note, and nothing too when it has not told it: only a text ticks
		if current == nil then return nil end
	else
		current = row.note or ""
	end
	return trim(current) == e.text and "done" or nil
end

-- OPS-02: ticks the open entries from a COMPLETE roster read (Data/Timeline.lua calls this with the rows of Compat). An
-- action another officer did is ticked too. Returns the number of entries closed.
function Ops:CheckRoster(rows, t)
	local list = queueOf(peek())
	if not list or #list == 0 then return 0 end
	t = floor(t or now())
	local changed = self:Sweep(t, true)
	local byG = {}
	for _, row in ipairs(rows) do if row.guid then byG[row.guid] = row end end
	local sees = compat().Guild.CanViewOfficerNote()
	local n = 0
	for _, e in ipairs(list) do
		if e.status == "open" then
			local status = outcome(e, byG[e.g], sees)
			if status then
				close(e, status, t)
				n = n + 1
			end
		end
	end
	if n > 0 or changed then emit("OPS_CHANGED") end
	return n
end

-- What the officer types in the chat for a rank change or a removal [verify that Forever has these commands]; for a note,
-- the text to paste in the game's window. The addon never runs any of it.
Ops.COMMANDS = { remove = "/gremove ", promote = "/gpromote ", demote = "/gdemote " }
function Ops.Command(entry)
	local prefix = Ops.COMMANDS[entry.op]
	if prefix then return prefix .. entry.name end
	return entry.text or ""
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
-- Counts only: never a name, a GUID or a text (SPEC-09 §6).
function Ops:DebugLine()
	local counts = { open = 0, done = 0, gone = 0, expired = 0, cancelled = 0 }
	for _, e in ipairs(queueOf(peek()) or {}) do
		if counts[e.status] then counts[e.status] = counts[e.status] + 1 end
	end
	return ("  queue: open %d, done %d, gone %d, expired %d, cancelled %d"):format(counts.open, counts.done, counts.gone,
		counts.expired, counts.cancelled)
end

-- The provider `officer`: the queue (officers) and the absences (officers, and the member's own one).
if ns.Actions then
	ns.Actions:Register("officer", { label = "ACT_PROVIDER_OFFICER", order = 30,
		events = { "OPS_CHANGED", "STORE_CHANGED", "ROSTER_UPDATED", "ACCOUNTS_UPDATED", "OFFICER_PURGED" },
		items = function(t)
			local rows = Ops:ActionRows(t)
			for _, row in ipairs(ns.Absence and ns.Absence:ActionRows(t) or {}) do rows[#rows + 1] = row end
			return rows
		end })
end

if ns.addon then ns.addon.OfficerOps = Ops end

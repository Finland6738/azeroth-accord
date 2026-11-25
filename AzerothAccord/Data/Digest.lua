-- Digest: the short summary of the login, "since your last session" (SPEC-13 §5, M9.5). Lua 5.1.
--
-- Only after the first login of a session (never after a /reload, never in demo mode): RUN_DELAY seconds after the first
-- complete read of the roster, RUN_MAX seconds after the login at the latest. What it compares with is what was saved the
-- last time the account was in the game in this guild:
--   GuildKey:Data().digest = { at,        -- server time, renewed every TOUCH seconds and at PLAYER_LOGOUT
--                              roster,    -- { [GUID] = name } of the last complete read, at most ROSTER_MAX
--                              cut,       -- true when the guild did not fit: no roster lines
--                              pending,   -- { ["provider\1key"] = mark }: the rows to do of the Action Center
--                              money,     -- the gold of the guild bank in copper
--                              moves,     -- { [tab] = encoded entries of the last GRACE of that bank log }
--                              card }     -- { since, rows, closed }: the card of the Inbox page, until the next login
-- Nothing of it is renewed before the summary of this login ran, so a logout right after logging in loses nothing.
-- The first time in a guild the picture is only taken.
--
-- Lines, each only when it is not zero, in this order (each carries the view it opens): "joined", "left" (roster),
-- "pending" (rows to do of the Action Center), "likes" (the NUMBER only: Likes:ReceivedSince returns nothing else),
-- "bank" (the gold and the new entries of the logs), "notices" (unread, since the last session). Things that wait are no
-- change by themselves: when nothing else changed and none of them is new or different since the last session, the digest
-- is empty, silent and without a card (DIG-03).
--
-- What was done while the player was away arrives with the sync after the login: until CATCH_UP seconds after the login
-- the lines are read again when something arrives. The chat line (DIG-02: numbers only, the output `chat` of the notice
-- module `digest`) is said once, at the summary, or at the end of the catch-up when there was nothing before; it waits
-- like a notice in combat, in instances and in the quiet hours (Notify:WhenFree), not in the grouping window of the login.
-- While the switch `actions` is off nothing here reads, saves, prints or listens.
-- Bus: DIGEST_CHANGED() the card changed (new lines, closed, another guild).
local ADDON_NAME, ns = ...
ns = ns or {}
local Digest = {}
ns.Digest, ns.modules = Digest, ns.modules or {}
ns.modules.Digest = Digest

local type, pairs, ipairs, tostring, floor, abs = type, pairs, ipairs, tostring, math.floor, math.abs
local sort, concat = table.sort, table.concat

Digest.RUN_DELAY = 10         -- seconds after the first complete read of the roster (DIG-01)
Digest.RUN_MAX = 60           -- seconds after the login at the latest
Digest.CATCH_UP = 150         -- seconds after the login while what the sync brings still counts
Digest.REFRESH = 2            -- seconds a change waits for the rest of its burst
Digest.TOUCH = 300            -- `at` and the picture are renewed this often
Digest.ROSTER_GAP = 30        -- seconds between two saved pictures of the roster
Digest.ROSTER_MAX = 1000
Digest.NAMES = 3              -- names on a roster line, then "and N more"
Digest.MANY = 50              -- more joined and left than this together: numbers only
Digest.OLD = 90 * 86400       -- away longer than this: numbers only
Digest.GRACE = 2 * 86400      -- the times of the bank log are rounded down, by up to a day

local state
local function fresh(old)
	return {
		-- nil before the login is known, "login" waiting for the summary, "run" the catch-up, "done"
		phase = nil, epoch = (old and old.epoch or 0) + 1, guild = nil, base = nil, diff = nil,
		armed = false, said = false, timer = false, rosterAt = nil, ticker = old and old.ticker,
	}
end
state = fresh()

local function compat() return ns.Compat end
local function serverTime() return compat().ServerTime() end
local function emit(event) if ns.Bus then ns.Bus:Emit(event) end end

function Digest.Enabled()
	return ns.Notify ~= nil and ns.Notify.Enabled()
end

local function active()
	return Digest.Enabled() and not (ns.Demo and ns.Demo:IsActive())
end

-- The saved table of the current guild, or nil.
local function saved(create)
	if not active() then return nil end
	local data = ns.GuildKey and ns.GuildKey:Current() and ns.GuildKey:Data()
	if not data then return nil end
	if type(data.digest) ~= "table" then
		if not create then return nil end
		data.digest = {}
	end
	return data.digest
end

local function after(seconds, fn)
	local epoch = state.epoch
	compat().After(seconds, function() if epoch == state.epoch then fn() end end)
end

---------------------------------------------------------------------------------------------------------------------
-- The picture
---------------------------------------------------------------------------------------------------------------------
-- The complete roster as { [GUID] = name } with its size, or nil for a partial read.
local function readRoster()
	if not ns.Timeline then return nil end
	local rows, complete = ns.Timeline.ReadRoster()
	if not complete then return nil end
	local map, n = {}, 0
	for _, row in ipairs(rows) do
		if map[row.guid] == nil then n = n + 1 end
		map[row.guid] = row.name
	end
	return map, n
end

local function saveRoster(d, map, n)
	d.cut = n > Digest.ROSTER_MAX or nil
	if d.cut then
		local guids = {}
		for guid in pairs(map) do guids[#guids + 1] = guid end
		sort(guids)
		local kept = {}
		for i = 1, Digest.ROSTER_MAX do kept[guids[i]] = map[guids[i]] end
		map = kept
	end
	d.roster = map
end

local function pendingKey(row) return row.provider .. "\1" .. row.key end
local function pendingMark(row) return tostring(row.mark or true) end

-- The entries of the bank logs this player may see that are not older than `from`, by tab.
local function movesSince(from)
	local out = {}
	for _, e in ipairs(ns.BankLog and ns.BankLog:Entries() or {}) do
		if e.t >= from then
			local list = out[e.tab]
			if not list then list = {} out[e.tab] = list end
			list[#list + 1] = e
		end
	end
	return out
end

-- Renews `at` and the picture (not the roster: only a complete read does that). Not before the summary of this login ran.
function Digest:Touch()
	if state.phase ~= "run" and state.phase ~= "done" then return false end
	local d = saved(true)
	if not d then return false end
	local t = serverTime()
	d.at = t
	local pending = {}
	for _, row in ipairs(ns.Actions and ns.Actions:Rows() or {}) do
		if row.urgency >= ns.Actions.TODO then pending[pendingKey(row)] = pendingMark(row) end
	end
	d.pending = pending
	local money = ns.Bank and ns.Bank:Money()
	if money then d.money = money.money end
	local moves = {}
	for tab, list in pairs(movesSince(t - Digest.GRACE)) do moves[tab] = ns.BankLog.Encode(list) end
	d.moves = moves
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------------------------------------------------
-- Who joined and who left between the picture and a complete read: { joined = { names }, left = { names } }.
local function rosterDiff(base, map, n)
	if type(base.roster) ~= "table" or base.cut or n > Digest.ROSTER_MAX then return { joined = {}, left = {} } end
	local joined, left = {}, {}
	local function short(name) return (compat().SplitName(name)) or name end
	for guid, name in pairs(map) do
		if base.roster[guid] == nil then joined[#joined + 1] = short(name) end
	end
	for guid, name in pairs(base.roster) do
		if map[guid] == nil then left[#left + 1] = short(name) end
	end
	sort(joined)
	sort(left)
	return { joined = joined, left = left }
end

local function rosterLines(out, diff, numbersOnly)
	numbersOnly = numbersOnly or #diff.joined + #diff.left > Digest.MANY
	for _, id in ipairs({ "joined", "left" }) do
		local list = diff[id]
		if #list > 0 then
			local names
			if not numbersOnly then
				names = {}
				for i = 1, math.min(#list, Digest.NAMES) do names[i] = list[i] end
			end
			out[#out + 1] = { id = id, n = #list, names = names, view = "roster" }
		end
	end
end

local function newMoves(base)
	if type(base.moves) ~= "table" or not ns.BankLog then return 0 end
	local Log, from, n = ns.BankLog, base.at - Digest.GRACE, 0
	for tab, list in pairs(movesSince(from)) do
		local old = {}
		for _, e in ipairs(base.moves[tab] and Log.Decode(base.moves[tab]) or {}) do
			if e.t >= from then old[#old + 1] = e end
		end
		n = n + math.max(0, #Log.Merge(old, list) - #old)
	end
	return n
end

-- The lines now, against the picture `base`: an array in the order of SPEC-13 §5.2, and whether anything changed.
function Digest:Lines(base, diff)
	local out, changed = {}, false
	if diff then rosterLines(out, diff, serverTime() - base.at > Digest.OLD) end
	changed = #out > 0

	if ns.Actions then
		local n, news = 0, false
		for _, row in ipairs(ns.Actions:Refresh()) do
			if row.urgency >= ns.Actions.TODO then
				n = n + 1
				if (base.pending or {})[pendingKey(row)] ~= pendingMark(row) then news = true end
			end
		end
		if n > 0 then out[#out + 1] = { id = "pending", n = n, view = "actions", page = "inbox" } end
		changed = changed or news
	end

	local likes = ns.Likes and ns.Likes:ReceivedSince(base.at) or 0
	if likes > 0 then
		out[#out + 1] = { id = "likes", n = likes, view = "reputation" }
		changed = true
	end

	local money = ns.Bank and ns.Bank:Money()
	local gold
	if money and (money.time or 0) > base.at and type(base.money) == "number" and money.money ~= base.money then
		gold = money.money - base.money
	end
	local moves = newMoves(base)
	if gold or moves > 0 then
		out[#out + 1] = { id = "bank", n = moves, money = gold, view = "bank" }
		changed = true
	end

	local unread = 0
	for _, e in ipairs(ns.Notify:Entries(true)) do
		local def = ns.Notify:Module(e.module)
		local kind = def and def.byKind[e.kind]
		-- a notice the player never asked for (a kind that is off until switched on) brings up no summary
		if (e.time or 0) > base.at and not (e.muted and kind and kind.optIn) then unread = unread + 1 end
	end
	if unread > 0 then
		out[#out + 1] = { id = "notices", n = unread, view = "actions", page = "notices" }
		changed = true
	end
	return out, changed
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
local function counted(key, n)
	return ns.L[n == 1 and (key .. "_ONE") or key]:format(n)
end

local function bankText(line)
	local parts = {}
	if line.money then
		local text = ns.BankView and ns.BankView.MoneyText(abs(line.money)) or tostring(abs(line.money))
		parts[#parts + 1] = (line.money < 0 and "-" or "+") .. text
	end
	if line.n > 0 then parts[#parts + 1] = counted("DIGEST_MOVES", line.n) end
	return concat(parts, ", ")
end

-- The text of a line of the card.
function Digest.Text(line)
	if line.id == "bank" then return ns.L["DIGEST_BANK"]:format(bankText(line)) end
	if line.id == "likes" then return counted("DIGEST_LIKES", line.n) end
	local text = counted("DIGEST_" .. line.id:upper(), line.n)
	if line.names and #line.names > 0 then
		local names = {}
		for i, name in ipairs(line.names) do
			names[i] = ns.Contacts and ns.Contacts.Escape(name) or (name:gsub("|", "||"))
		end
		text = text .. ": " .. concat(names, ", ")
		if line.n > #names then text = text .. ", " .. ns.L["ACT_MORE"]:format(line.n - #names) end
	end
	return text
end

-- The one chat line (DIG-02): numbers only.
function Digest.ChatText(lines)
	local parts = {}
	for i, line in ipairs(lines) do
		if line.id == "bank" then parts[i] = ns.L["DIGEST_CHAT_BANK"]:format(bankText(line))
		elseif line.id == "likes" then parts[i] = counted("DIGEST_CHAT_LIKES", line.n)
		else parts[i] = counted("DIGEST_" .. line.id:upper(), line.n) end
	end
	return ns.L["DIGEST_CHAT"]:format(concat(parts, ", "))
end

---------------------------------------------------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------------------------------------------------
-- The card of the Inbox page: { since, rows }, or nil (nothing changed, closed, or the switch is off).
function Digest:Card()
	local d = saved(false)
	local card = d and d.card
	if type(card) ~= "table" or card.closed or type(card.rows) ~= "table" or #card.rows == 0 then return nil end
	return card
end

-- The player closes the card: it stays closed until the next login.
function Digest:Close()
	local card = self:Card()
	if not card then return false end
	card.closed = true
	emit("DIGEST_CHANGED")
	return true
end

-- A click on a line: opens its view. Returns true when it did.
function Digest:Open(line)
	if type(line) ~= "table" or not (line.view and ns.Shell) then return false end
	if not ns.Shell:OpenView(line.view) then return false end
	if line.view == "actions" and ns.ActionsView then ns.ActionsView:ShowPage(line.page or "inbox") end
	return true
end

local function say()
	if state.said then return end
	local d = saved(false)
	local card = d and d.card
	if not card or card.closed or #card.rows == 0 then return end
	state.said = true
	local guild = state.guild
	ns.Notify:WhenFree(function()
		-- read when it comes out: what arrived or was closed while it waited counts
		local held = ns.GuildKey and ns.GuildKey:Current() == guild and Digest:Card()
		if held and ns.Notify:Output("digest", "chat") then
			compat().ChatLine(ns.Notify.PREFIX .. Digest.ChatText(held.rows))
		end
	end)
end

-- Reads the lines again and puts them on the card; none while nothing changed.
local function compute()
	local d = saved(true)
	local base = state.base
	if not (d and base) then return false end
	if not state.diff then
		local map, n = readRoster()
		if map then
			state.diff = rosterDiff(base, map, n)
			saveRoster(d, map, n)
		end
	end
	local rows, changed = Digest:Lines(base, state.diff)
	if changed then
		d.card = { since = base.at, rows = rows, closed = d.card and d.card.closed or nil }
		emit("DIGEST_CHANGED")
		return true
	end
	if d.card then
		d.card = nil
		emit("DIGEST_CHANGED")
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- The login
---------------------------------------------------------------------------------------------------------------------
-- The summary (once per login).
function Digest:Run()
	if state.phase ~= "login" or not state.base then return false end
	if not active() or ns.GuildKey:Current() ~= state.guild then return false end
	if not state.base.at then   -- the first time in this guild: the picture only
		state.phase, state.base = "done", nil
		local map, n = readRoster()
		local d = saved(true)
		if map then saveRoster(d, map, n) end
		self:Touch()
		return false
	end
	state.phase = "run"
	local changed = compute()
	self:Touch()
	if changed then say() end
	return changed
end

-- The end of the catch-up: the last read, and the chat line when nothing was said yet.
local function finish()
	if state.phase == "login" then
		Digest:Run()
		if state.phase == "login" then state.phase = "done" end   -- no guild known by now: no summary for this login
	end
	if state.phase ~= "run" then return end
	if ns.GuildKey:Current() == state.guild and compute() then say() end
	state.phase, state.base, state.diff = "done", nil, nil
end

-- A complete read of the roster while the summary waits arms it.
local function arm()
	if state.phase ~= "login" or state.armed or not state.base or not readRoster() then return end
	state.armed = true
	after(Digest.RUN_DELAY, function() Digest:Run() end)
end

-- Takes the picture to compare with, once the guild is known. The card of the last session goes.
local function begin()
	if state.phase ~= "login" or state.base or not active() then return end
	local key = ns.GuildKey and ns.GuildKey:Current()
	local d = key and saved(true)
	if not d then return end
	state.guild = key
	state.base = { at = type(d.at) == "number" and d.at or nil, roster = d.roster, cut = d.cut, pending = d.pending,
		money = d.money, moves = d.moves }
	if d.card then
		d.card = nil
		emit("DIGEST_CHANGED")
	end
	if ns.Roster then ns.Roster:Request() end
	arm()
end

-- PLAYER_ENTERING_WORLD: the first of a login starts the summary; after a /reload there is none.
function Digest:OnEnteringWorld(isLogin)
	if not Digest.Enabled() then return end
	if isLogin and state.phase == nil then
		state.phase = "login"
		after(Digest.RUN_MAX, function() Digest:Run() end)
		after(Digest.CATCH_UP, finish)
		begin()
	elseif state.phase == nil then
		state.phase = "done"
	end
end

function Digest:OnRoster()
	if not Digest.Enabled() then return end
	if state.phase == "login" then
		begin()
		arm()
	elseif state.phase == "run" and not state.diff then
		self:Changed()
	elseif state.phase == "done" or state.phase == "run" then
		local t = compat().Now()
		if state.rosterAt and t - state.rosterAt < Digest.ROSTER_GAP then return end
		local d = saved(true)
		if not d then return end
		local map, n = readRoster()
		if map then
			state.rosterAt = t
			saveRoster(d, map, n)
		end
	end
end

-- Something arrived during the catch-up: one read after the burst.
function Digest:Changed()
	if state.phase ~= "run" or state.timer then return end
	state.timer = true
	after(Digest.REFRESH, function()
		state.timer = false
		if state.phase == "run" and ns.GuildKey:Current() == state.guild then compute() end
	end)
end

-- Another guild than the one the summary was started for: there is none for this login any more.
function Digest:OnGuildChanged(key)
	if not Digest.Enabled() then return end
	if state.phase == "login" and not state.base then
		begin()
	elseif state.guild and key ~= state.guild then
		state = fresh(state)
		state.phase = "done"
	end
	state.rosterAt = nil
	emit("DIGEST_CHANGED")
end

function Digest:Start()
	if state.ticker or not Digest.Enabled() then return end
	state.ticker = compat().NewTicker(Digest.TOUCH, function() Digest:Touch() end)
end

-- Phase and counts only: never a name.
function Digest:DebugLines()
	local card = self:Card()
	return { ("Digest: %s, %d line(s) on the card"):format(state.phase or "before the login", card and #card.rows or 0) }
end

if ns.Notify then
	-- the one chat line; the module has no other output (SPEC-13 §3.2)
	ns.Notify:Register("digest", { label = "NOTICE_MODULE_DIGEST", order = 50, outputs = { "chat" },
		kinds = { { id = "digest", level = "normal" } } })
end

if ns.addon then
	ns.addon.Digest = Digest
	if ns.Bus then
		local function changed() Digest:Changed() end
		ns.Bus:On("STORE_CHANGED", changed)
		ns.Bus:On("NOTICES_CHANGED", changed)
		ns.Bus:On("ACTIONS_CHANGED", changed)
		ns.Bus:On("ROLE_CHANGED", changed)
		ns.Bus:On("GUILD_CHANGED", function(key) Digest:OnGuildChanged(key) end)
	end
	LibStub("AceEvent-3.0"):Embed(Digest)
	if ns.OnEnable then
		-- OnEnable runs at PLAYER_LOGIN, before the first PLAYER_ENTERING_WORLD
		ns.OnEnable(function()
			if not Digest.Enabled() then return end
			Digest:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin) Digest:OnEnteringWorld(isLogin) end)
			Digest:RegisterEvent("GUILD_ROSTER_UPDATE", function() Digest:OnRoster() end)
			Digest:RegisterEvent("PLAYER_LOGOUT", function() Digest:Touch() end)
			if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Digest", function() return Digest:DebugLines() end) end
			Digest:Start()
		end)
	end
end

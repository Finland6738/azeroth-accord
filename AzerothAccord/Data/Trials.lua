-- Trials: the officers follow a new member on trial (M12.3; SPEC-16 §4, TRI-01..TRI-05; ADR 0026). Lua 5.1.
--
-- The set `trials` is one of the officer tools (SPEC-12 §1.2): restricted for every record, travels on OFFICER or by
-- WHISPER to an officer only, once the channel is proven, and a demoted officer's client deletes it (OFF-10). Two kinds of
-- record:
--   T:<GUID>:<start>                 a trial: { char, start (day YYYYMMDD), days (1..MAX_DAYS), ends (day, start + days, later
--                                    after an extension, at most start + MAX_SPAN), state = open | passed | failed | cancelled,
--                                    closed (day, only with a closed state) }; any officer writes it (authorAny)
--   N:<GUID>:<start>:<officer GUID>  the note of one officer about one trial: { char, text }; only that officer writes it, with
--                                    the limits of the extended notes (ONT-02); "" = deleted, which expires after 60 days
-- A trial is never reopened, shortened or moved (TRI-04, "locked"); a closed trial is kept for ever (SPEC-10 Q35). Nothing
-- here changes the game (RC-02): "Passed" may only add a promotion to this officer's queue of manual actions (M8.4).
-- Who sees it: Officer.VISIBLE_TO.trials (the officers and the Guild Master). The member on trial sees nothing.
--
--   Trials.ValidRecord(rec)          the owner rule of the set (TRI-03)
--   Trials.Transition(held, rec)     TRI-04: an extension or a closing, else false and "locked"
--   Trials:Get(id), Trials:Of(guid)  a trial; the trials of a character (open first, the farthest end first, then closed)
--   Trials:Rows(t)                   the Trials page: { open = { row }, closed = { row } } with row = { id, rec, guid, name,
--                                    others (other open trials of the character), notes, left, daysLeft }
--   Trials:Start(guid, days, start)  a new trial (start: day YYYYMMDD, default today); returns the record or nil and a reason
--   Trials:Extend(id, more)          `more` days later, at most start + MAX_SPAN
--   Trials:Close(id, state, promote) "passed" | "failed" | "cancelled"; promote = true adds a promotion to the queue (M8.4)
--   Trials:Notes(id)                 the notes of a trial with a text, the own first; Trials:Note(id) the own one
--   Trials:SetNote(id, text)         the own note ("" deletes it); Trials:DeleteNote(id)
--   Trials:Due(t)                    the open trials whose end day is today or past: the Action Center and the notice
--   Trials:Notice()                  the notice `trials.ended`, once per trial and end day (key "<id>:<ends>")
-- Switch: Core/Features.lua "recruit" (store def `feature = "recruit"`). Bus: TRIALS_CHANGED(guid).
local ADDON_NAME, ns = ...
ns = ns or {}
local Trials = {}
ns.Trials, ns.modules = Trials, ns.modules or {}
ns.modules.Trials = Trials

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, sort = math.floor, table.sort
local DAY = 86400

Trials.SET = "trials"
Trials.DEFAULT_DAYS = 14         -- SPEC-10 Q35
Trials.MAX_DAYS = 60             -- the length chosen when a trial starts
Trials.MAX_SPAN = 120            -- an extension moves the end at most this many days after the start
Trials.PAST_DAYS = 30            -- a trial may start at most this many days before the day it is written
Trials.FUTURE_DAYS = 14          -- and at most this many days after it
Trials.CLOSED_SHOWN = 90         -- the Trials page lists the trials closed in the last 90 days (older: the member card)
Trials.TRIAL_BYTES = 256         -- the size of a trial record; a note takes the set's maxBytes (1280)
Trials.STATES = { open = true, passed = true, failed = true, cancelled = true }
Trials.CLOSING = { "passed", "failed", "cancelled" }

local function store() return ns.Store end
local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function me() return compat().Player.GUID() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function notes() return ns.OfficerNotes end

function Trials.Enabled() return ns.Features ~= nil and ns.Features.On("recruit") end

-- true when the connected character may see the trials: the switch is on, and an officer or the GM (Q35).
function Trials.CanSee()
	return Trials.Enabled() and ns.Officer ~= nil and ns.Officer.CanSee("trials")
end

local function canWrite() return Trials.CanSee() and ns.Role ~= nil and ns.Role:IsOfficer() == true end

---------------------------------------------------------------------------------------------------------------------
-- Days
---------------------------------------------------------------------------------------------------------------------
-- The number of a day YYYYMMDD (days since 1970-01-01), or nil for an invalid day.
function Trials.Number(day) return ns.Timeline.DayNumber(day) end
-- The day YYYYMMDD of a day number.
function Trials.DayOfNumber(n) return ns.Timeline.DayOf(n * DAY) end
function Trials.Today(t) return ns.Timeline.DayOf(t or now()) end

-- "2026-12-31"
function Trials.DayText(day)
	if type(day) ~= "number" then return "?" end
	return ("%04d-%02d-%02d"):format(floor(day / 10000), floor(day / 100) % 100, day % 100)
end

-- The day typed as "YYYY-MM-DD", or nil.
function Trials.ParseDay(text)
	if type(text) ~= "string" then return nil end
	local y, m, d = text:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
	if not y then return nil end
	local day = tonumber(y) * 10000 + tonumber(m) * 100 + tonumber(d)
	return Trials.Number(day) and day or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Records (TRI-03, TRI-04)
---------------------------------------------------------------------------------------------------------------------
local function isGUID(g) return type(g) == "string" and #g <= 40 and g:find(store().GUID_PATTERN) ~= nil end
local function isInt(v) return type(v) == "number" and v == floor(v) end

-- "T" or "N" of a record (by its id), or nil.
function Trials.KindOf(rec)
	local id = type(rec) == "table" and rec.id
	if type(id) ~= "string" then return nil end
	return id:match("^([TN]):")
end

function Trials.TrialId(guid, start) return "T:" .. tostring(guid) .. ":" .. tostring(start) end
function Trials.NoteId(trialId, officer) return "N:" .. tostring(trialId):sub(3) .. ":" .. tostring(officer) end

-- The character and the start day of a trial id or a note id, and the officer of a note id.
function Trials.Parse(id)
	if type(id) ~= "string" then return nil end
	local guid, start = id:match("^T:([^:]+):(%d%d%d%d%d%d%d%d)$")
	if guid then return guid, tonumber(start) end
	local g, s, officer = id:match("^N:([^:]+):(%d%d%d%d%d%d%d%d):([^:]+)$")
	if g then return g, tonumber(s), officer end
	return nil
end

local TRIAL_FIELDS = { id = true, author = true, rev = true, time = true, char = true, start = true, days = true, ends = true,
	state = true, closed = true }
local NOTE_FIELDS = { id = true, author = true, rev = true, time = true, char = true, text = true }

local function validTrial(rec)
	for key in pairs(rec) do if not TRIAL_FIELDS[key] then return false end end
	if not isGUID(rec.char) or rec.id ~= Trials.TrialId(rec.char, rec.start) then return false end
	local s, e = Trials.Number(rec.start), Trials.Number(rec.ends)
	if not (s and e) then return false end
	if not (isInt(rec.days) and rec.days >= 1 and rec.days <= Trials.MAX_DAYS) then return false end
	if e < s + rec.days or e > s + Trials.MAX_SPAN then return false end
	if not Trials.STATES[rec.state] then return false end
	if rec.state == "open" then
		if rec.closed ~= nil then return false end
	elseif not Trials.Number(rec.closed) then
		return false
	end
	if ns.Config and ns.Config.EstimateSize(rec) > Trials.TRIAL_BYTES then return false end
	return true
end

local function validNote(rec)
	for key in pairs(rec) do if not NOTE_FIELDS[key] then return false end end
	local guid, start, officer = Trials.Parse(rec.id)
	if not (guid and officer and isGUID(guid) and isGUID(officer) and Trials.Number(start)) then return false end
	if rec.char ~= guid or rec.author ~= officer then return false end   -- only the officer of its id writes it
	return notes().Check(rec.text) == true
end

function Trials.ValidRecord(rec)
	if type(rec) ~= "table" then return false end
	local kind = Trials.KindOf(rec)
	if kind == "T" then return validTrial(rec) end
	if kind == "N" then return validNote(rec) end
	return false
end

-- TRI-04: a newer revision of a trial extends it (a later end, still open) or closes it (open -> a closed state). It
-- never reopens, shortens or moves it. An older revision is let through: the store then keeps the record it holds.
function Trials.Transition(held, rec)
	if Trials.KindOf(rec) ~= "T" or type(held) ~= "table" then return true end
	if store().Compare(rec, held) <= 0 then return true end
	if rec.char ~= held.char or rec.start ~= held.start or rec.days ~= held.days then return false, "locked" end
	if (Trials.Number(rec.ends) or 0) < (Trials.Number(held.ends) or 0) then return false, "locked" end
	if held.state ~= "open" then
		if rec.state ~= held.state or rec.ends ~= held.ends or rec.closed ~= held.closed then return false, "locked" end
	end
	return true
end

function Trials.Expired(rec, t)
	return type(rec) ~= "table" or (Trials.KindOf(rec) == "N" and rec.text == ""
		and (rec.time or 0) < t - notes().DELETE_DAYS * DAY)
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
-- The name of a character: the roster's or its account's (OfficerNotes.NameOf), else the one the timeline saw last (a
-- member who left the guild during the trial), else "?".
function Trials.NameOf(guid)
	local name = notes().NameOf(guid)
	if name ~= "?" then return name end
	for _, ev in ipairs(ns.Timeline and ns.Timeline:Events(guid) or {}) do
		if type(ev.n) == "string" and ev.n ~= "?" then return ev.n end
	end
	return name
end

function Trials:Get(id)
	if not Trials.CanSee() then return nil end
	local rec = store():Get(Trials.SET, id)
	if rec and Trials.KindOf(rec) == "T" then return rec end
	return nil
end

local function laterFirst(a, b)
	local ea, eb = Trials.Number(a.ends) or 0, Trials.Number(b.ends) or 0
	if ea ~= eb then return ea > eb end
	return a.id > b.id
end

-- Every trial (all characters), or those of one character.
local function trials(guid)
	local out = {}
	if not Trials.CanSee() then return out end
	for _, rec in pairs(store():Records(Trials.SET)) do
		if Trials.KindOf(rec) == "T" and (guid == nil or rec.char == guid) then out[#out + 1] = rec end
	end
	return out
end

function Trials:Of(guid)
	local open, closed = {}, {}
	for _, rec in ipairs(trials(guid)) do
		if rec.state == "open" then open[#open + 1] = rec else closed[#closed + 1] = rec end
	end
	sort(open, laterFirst)
	sort(closed, function(a, b)
		if a.closed ~= b.closed then return (a.closed or 0) > (b.closed or 0) end
		return a.id > b.id
	end)
	for _, rec in ipairs(closed) do open[#open + 1] = rec end
	return open
end

-- The open trial with the farthest end of a character and how many others it has open.
function Trials:Current(guid)
	local list = self:Of(guid)
	local first = list[1]
	if not (first and first.state == "open") then return nil, 0 end
	local others = 0
	for i = 2, #list do if list[i].state == "open" then others = others + 1 end end
	return first, others
end

-- The notes of a trial with a text: the own one first, then by name of the author.
function Trials:Notes(id)
	local out = {}
	if not Trials.CanSee() or type(id) ~= "string" then return out end
	local prefix = "N:" .. id:sub(3) .. ":"
	for nid, rec in pairs(store():Records(Trials.SET)) do
		if nid:sub(1, #prefix) == prefix and type(rec.text) == "string" and rec.text ~= "" then out[#out + 1] = rec end
	end
	local mine = me()
	sort(out, function(a, b)
		if (a.author == mine) ~= (b.author == mine) then return a.author == mine end
		return tostring(Trials.NameOf(a.author)) < tostring(Trials.NameOf(b.author))
	end)
	return out
end

function Trials:Note(id)
	if not Trials.CanSee() or type(id) ~= "string" then return nil end
	local rec = store():Get(Trials.SET, Trials.NoteId(id, me()))
	if rec and type(rec.text) == "string" and rec.text ~= "" then return rec end
	return nil
end

local function rosterRead() return ns.Roster ~= nil and ns.Roster:Count() > 0 end

-- One row of the Trials page.
local function rowOf(self, rec, others, today)
	local entry = ns.Roster and ns.Roster:ByGUID(rec.char)
	local e = Trials.Number(rec.ends) or today
	return { id = rec.id, rec = rec, guid = rec.char, name = Trials.NameOf(rec.char), rank = entry and entry.rankName or nil,
		others = others or 0, notes = #self:Notes(rec.id), left = rosterRead() and entry == nil, daysLeft = e - today }
end

function Trials:Rows(t)
	local out = { open = {}, closed = {} }
	if not Trials.CanSee() then return out end
	local today = Trials.Number(Trials.Today(t)) or 0
	local seen = {}
	for _, rec in ipairs(trials()) do
		if rec.state == "open" and not seen[rec.char] then
			seen[rec.char] = true
			local first, others = self:Current(rec.char)
			out.open[#out.open + 1] = rowOf(self, first, others, today)
		elseif rec.state ~= "open" and today - (Trials.Number(rec.closed) or 0) <= Trials.CLOSED_SHOWN then
			out.closed[#out.closed + 1] = rowOf(self, rec, 0, today)
		end
	end
	sort(out.open, function(a, b)
		if a.daysLeft ~= b.daysLeft then return a.daysLeft < b.daysLeft end
		return tostring(a.name) < tostring(b.name)
	end)
	sort(out.closed, function(a, b)
		if a.rec.closed ~= b.rec.closed then return a.rec.closed > b.rec.closed end
		return tostring(a.name) < tostring(b.name)
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (officers only)
---------------------------------------------------------------------------------------------------------------------
-- Starts a trial of `guid` (a member of the roster) for `days` days from `start`. Returns the record, or nil and
-- "officer" | "unknown" | "days" | "start" | "exists" (an open trial with the same start) | "locked" (a closed one) | a
-- reason of Store:Put.
function Trials:Start(guid, days, start, t)
	if not canWrite() then return nil, "officer" end
	if not (isGUID(guid) and ns.Roster and ns.Roster:ByGUID(guid)) then return nil, "unknown" end
	days = days == nil and Trials.DEFAULT_DAYS or tonumber(days)
	if not (isInt(days) and days >= 1 and days <= Trials.MAX_DAYS) then return nil, "days" end
	local today = Trials.Number(Trials.Today(t))
	start = start == nil and Trials.DayOfNumber(today) or tonumber(start)
	local s = Trials.Number(start)
	if not s or s < today - Trials.PAST_DAYS or s > today + Trials.FUTURE_DAYS then return nil, "start" end
	local id = Trials.TrialId(guid, start)
	local held = store():Get(Trials.SET, id)
	if held then return nil, held.state == "open" and "exists" or "locked" end
	local rec, why = store():Put(Trials.SET, id, { char = guid, start = start, days = days, ends = Trials.DayOfNumber(s + days),
		state = "open" })
	return rec, why
end

-- Moves the end of an open trial `more` days later. Returns the record, or nil and "officer" | "unknown" | "closed" |
-- "days" | "max" (past start + MAX_SPAN).
function Trials:Extend(id, more)
	if not canWrite() then return nil, "officer" end
	local held = self:Get(id)
	if not held then return nil, "unknown" end
	if held.state ~= "open" then return nil, "closed" end
	more = tonumber(more)
	if not (isInt(more) and more >= 1) then return nil, "days" end
	local e = Trials.Number(held.ends) + more
	if e > Trials.Number(held.start) + Trials.MAX_SPAN then return nil, "max" end
	local fields = store().Copy(held)
	fields.id, fields.author, fields.rev, fields.time = nil, nil, nil, nil
	fields.ends = Trials.DayOfNumber(e)
	return store():Put(Trials.SET, id, fields)
end

-- The nearest rank above the character's that this officer may give, or nil.
local function rankAbove(entry)
	local Ops = ns.OfficerOps
	if not (Ops and entry and entry.rankIndex) then return nil end
	local choices = Ops:RankChoices("promote", entry.rankIndex)
	return choices[#choices]
end

-- Closes an open trial. With state "passed" and `promote`, a promotion to the nearest rank above goes to this officer's
-- queue of manual actions (M8.4); nothing changes in the game. Returns the record and the queue entry (or a reason why
-- there is none: "gone" | "rank" | a reason of OfficerOps:Add), or nil and "officer" | "unknown" | "closed" | "state".
function Trials:Close(id, state, promote, t)
	if not canWrite() then return nil, "officer" end
	local closing = false
	for _, s in ipairs(Trials.CLOSING) do if s == state then closing = true end end
	if not closing then return nil, "state" end
	local held = self:Get(id)
	if not held then return nil, "unknown" end
	if held.state ~= "open" then return nil, "closed" end
	local fields = store().Copy(held)
	fields.id, fields.author, fields.rev, fields.time = nil, nil, nil, nil
	fields.state, fields.closed = state, Trials.Today(t)
	local rec, why = store():Put(Trials.SET, id, fields)
	if not rec then return nil, why end
	if state ~= "passed" or not promote then return rec end
	local entry = ns.Roster and ns.Roster:ByGUID(held.char)
	if not entry then return rec, "gone" end
	local rank = rankAbove(entry)
	if not rank then return rec, "rank" end
	local queued, qwhy = ns.OfficerOps:Add({ g = held.char, name = entry.short or entry.name, op = "promote",
		fromRank = entry.rankIndex, toRank = rank.index })
	return rec, queued or qwhy
end

-- The own note about a trial. Returns the record (or the one held, when the text is the same), or nil and "officer" |
-- "unknown" | "empty" | a reason of OfficerNotes.Check or Store:Put.
function Trials:SetNote(id, text)
	if not canWrite() then return nil, "officer" end
	local trial = self:Get(id)
	if not trial then return nil, "unknown" end
	text = notes().Clean(text)
	local ok, why = notes().Check(text)
	if not ok then return nil, why end
	local nid = Trials.NoteId(id, me())
	local held = store():Get(Trials.SET, nid)
	if held and held.text == text then return held end
	if (not held or held.text == "") and text == "" then return nil, "empty" end
	return store():Put(Trials.SET, nid, { char = trial.char, text = text })
end

function Trials:DeleteNote(id)
	if not self:Note(id) then return nil, "empty" end
	return self:SetNote(id, "")
end

-- How many trials and trial notes this character wrote (the What I share panel: counts, never a text).
function Trials:WrittenBy(guid)
	local t, n = 0, 0
	for _, rec in pairs(store():Records(Trials.SET)) do
		if rec.author == guid then
			local kind = Trials.KindOf(rec)
			if kind == "T" then t = t + 1 elseif kind == "N" and rec.text ~= "" then n = n + 1 end
		end
	end
	return t, n
end

local ERRORS = { officer = "TRI_ERR_OFFICER", unknown = "TRI_ERR_UNKNOWN", days = "TRI_ERR_DAYS", start = "TRI_ERR_START",
	exists = "TRI_ERR_EXISTS", locked = "TRI_ERR_LOCKED", closed = "TRI_ERR_CLOSED", max = "TRI_ERR_MAX" }

function Trials.ErrorText(why, text)
	local L, key = ns.L, ERRORS[why]
	if why == "days" then return L[key]:format(Trials.MAX_DAYS) end
	if why == "max" then return L[key]:format(Trials.MAX_SPAN) end
	if why == "start" then return L[key]:format(Trials.PAST_DAYS, Trials.FUTURE_DAYS) end
	if key then return L[key] end
	return notes().ErrorText(why, text)
end

---------------------------------------------------------------------------------------------------------------------
-- The end of a trial: the Action Center and the notice (SPEC-16 §4.4)
---------------------------------------------------------------------------------------------------------------------
-- The open trials whose end day is today or before: { rec, name, left }. Nothing before the end day.
function Trials:Due(t)
	local out = {}
	if not Trials.CanSee() then return out end
	local today = Trials.Number(Trials.Today(t)) or 0
	local read = rosterRead()
	for _, rec in ipairs(trials()) do
		if rec.state == "open" and (Trials.Number(rec.ends) or today + 1) <= today then
			out[#out + 1] = { rec = rec, name = Trials.NameOf(rec.char), left = read and not ns.Roster:ByGUID(rec.char) }
		end
	end
	sort(out, function(a, b)
		if a.rec.ends ~= b.rec.ends then return a.rec.ends < b.rec.ends end
		return a.rec.id < b.rec.id
	end)
	return out
end

local function openTrial(id) if ns.TrialsView then ns.TrialsView:Open(id) end end

function Trials:ActionRows(t)
	local L, rows = ns.L, {}
	for _, d in ipairs(self:Due(t)) do
		local rec, name = d.rec, d.name
		local id = rec.id
		rows[#rows + 1] = { key = id, urgency = d.left and 1 or 2, time = Trials.Number(rec.ends) * DAY, who = name,
			title = d.left and L["TRI_ROW_LEFT"]:format(name) or L["TRI_ROW_ENDED"]:format(name, Trials.DayText(rec.ends)),
			mark = rec.rev, open = function() openTrial(id) end }
	end
	return rows
end

-- The notice of a trial that ended: once per trial and end day, also after a /reload or another login (the book of
-- Data/Notify.lua is saved); an extension gives a new one on the new end day.
function Trials:Notice(t)
	local N = ns.Notify
	if not (N and N.Enabled() and Trials.CanSee()) then return 0 end
	local book = N:Seen("trials")
	if not book then return 0 end
	local due, posted = {}, 0
	for _, d in ipairs(self:Due(t)) do
		local rec = d.rec
		local key = rec.id .. ":" .. rec.ends
		due[key] = true
		if not book[key] then
			book[key] = true
			posted = posted + 1
			local id = rec.id
			N:Post("trials", "ended", { key = key, text = d.left and "TRI_ROW_LEFT" or "TRI_ROW_ENDED",
				args = d.left and { d.name } or { d.name, Trials.DayText(rec.ends) }, view = "officers", page = "trials",
				char = me(), still = function()
					local held = Trials:Get(id)
					return held ~= nil and held.state == "open"
				end })
		end
	end
	for key in pairs(book) do if not due[key] then book[key] = nil end end   -- closed or extended: the key is not due again
	return posted
end

---------------------------------------------------------------------------------------------------------------------
-- Debug and wiring
---------------------------------------------------------------------------------------------------------------------
-- Counts only (SPEC-09 §6).
function Trials:DebugLine()
	local open, closed, n = 0, 0, 0
	for _, rec in pairs(store():Records(Trials.SET)) do
		local kind = Trials.KindOf(rec)
		if kind == "T" then
			if rec.state == "open" then open = open + 1 else closed = closed + 1 end
		elseif kind == "N" and rec.text ~= "" then
			n = n + 1
		end
	end
	return ("  trials: open %d, closed %d, notes %d"):format(open, closed, n)
end

if ns.Actions then
	ns.Actions:Register("trials", { label = "ACT_PROVIDER_TRIALS", order = 32, feature = "recruit",
		visible = function() return Trials.CanSee() end,
		events = { "TRIALS_CHANGED", "ROSTER_UPDATED", "OFFICER_PURGED" },
		items = function(t) return Trials:ActionRows(t) end })
end

if ns.Notify then
	ns.Notify:Register("trials", { label = "ACT_PROVIDER_TRIALS", order = 32, feature = "recruit",
		open = function(entry)
			local id = type(entry.key) == "string" and entry.key:match("^(T:[^:]+:%d+):") or nil
			openTrial(id)
		end,
		check = function() Trials:Notice() end,
		kinds = { { id = "ended", level = "normal", off = "SET_NOTICE_TRIALS_ENDED", group = "TRI_NOTICE_MANY" } } })
end

if ns.addon then
	ns.addon.Trials = Trials
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set, id)
			if set ~= Trials.SET then return end
			emit("TRIALS_CHANGED", (Trials.Parse(id)))
			if Trials.CanSee() then Trials:Notice() end
		end)
		ns.Bus:On("OFFICER_PURGED", function() emit("TRIALS_CHANGED", nil) end)
	end
end

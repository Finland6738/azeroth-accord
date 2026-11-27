-- Events view: the guild's events and the own sign-up on the game calendar (M10.5; SPEC-14 §5; M10 integration rule 2).
-- Lua 5.1.
--
-- At the top, the event picker (the guild events of the game calendar from 7 days ago to 14 days ahead, whoever created
-- them, then the events only of the addon, marked) and "Open game calendar". Below, for the chosen event: the role
-- (preselected from the season declaration's MS1, or MS2 when MS1's role is already covered and MS2's is not, else from
-- the class: a member without a declaration signs up all the same) and Sign up, Tentative and Decline. A click writes the
-- answer into the game calendar (Data/Calendar.lua), so the game, FDCP and the other addons see the same answer; one
-- given in the game's calendar shows here when the calendar is read again. When the client refuses the call from an
-- addon, the game's calendar opens instead and the view says so.
-- Only when the client has no usable calendar, officers (Raid.WRITERS) create events here (title, date and time, size),
-- always marked "Not in the game calendar", and members answer here.
-- Raid-Helper (M10.6, Data/RaidHelper.lua): officers paste an event's export ("Import from Raid-Helper"). An imported
-- event shows with the calendar event of its date and time, else on its own, "From Discord". Every member sees the own
-- state on Discord; officers also the sign-ups, the roles next to the season roster and the target composition, who is on
-- Discord and not in the game calendar and the reverse, the names that matched nobody (with a hand match), "Put into the
-- game calendar" (a confirming second click) and the export back to Discord.
--
-- Line-up (M10.7, Data/Composition.lua): every member sees the own place, the raid and the bench; officers also the roles
-- against the target, who signed up and is not placed, who could fill a short role with MS2, and a row to place them in
-- the raid or on the bench, take them out and "Write to calendar" (a confirming second click). With FDCP as the source
-- of the raid there is nothing to write: a line says the line-up is FDCP's, with FDCP's night where it gives one.
-- View.Model(key) reads everything now; View.Lines(model) is a plain function of it (tested offline); the frames only draw.
-- While Core/Features.lua "season" is off there is no tab, no command and nothing is redrawn.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.EventsView, ns.modules = View, ns.modules or {}
ns.modules.EventsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor, max, min, concat = math.floor, math.max, math.min, table.concat

View.ROW_HEIGHT = 20
View.WHEEL_STEP = 3
View.REFRESH_DELAY = 0.4
View.SEP = " · "
View.NAMES_PER_LINE = 8

local function on() return ns.Features ~= nil and ns.Features.On("season") end
View.Enabled = on

local function short(name)
	if type(name) ~= "string" then return "?" end
	return (ns.Compat.SplitName(name))
end

-- A start (the realm's clock read as UTC) -> "2026-11-27 20:00".
local function whenText(t)
	if type(t) ~= "number" then return "?" end
	return date("!%Y-%m-%d %H:%M", t)
end
View.WhenText = whenText

-- "2026-11-27 20:00" -> the start, or nil.
function View.ParseWhen(text)
	if type(text) ~= "string" then return nil end
	local y, m, d, h, mi = text:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s+(%d%d?):(%d%d)%s*$")
	if not y then return nil end
	h, mi = tonumber(h), tonumber(mi)
	if h > 23 or mi > 59 then return nil end
	return ns.Calendar.Stamp(tonumber(y), tonumber(m), tonumber(d), h, mi)
end

local function raidSource() return ns.Integrations and ns.Integrations:Source("raid") or "accord" end

local function roleText(role) return role and (L["SEASON_ROLE_" .. tostring(role):upper()] or tostring(role)) or "?" end
local function answerText(answer) return answer and L["EVENTS_ANSWER_" .. answer:upper()] or L["EVENTS_ANSWER_NONE"] end
View.AnswerText = answerText

---------------------------------------------------------------------------------------------------------------------
-- The model and its lines
---------------------------------------------------------------------------------------------------------------------
-- Everything the lines need; `key` the chosen event (nil: the next one to come, else the first).
function View.Model(key)
	local C = ns.Calendar
	local m = { state = C.State(), now = ns.Compat.ServerTime(), canCreate = C:CanCreateLocal() }
	m.events = {}
	for _, e in ipairs(C.events) do m.events[#m.events + 1] = e end
	for _, e in ipairs(C:LocalEvents()) do m.events[#m.events + 1] = e end
	-- the imports of Raid-Helper: with the calendar event of their date and time, else on their own
	local RH = ns.RaidHelper
	m.officer = RH ~= nil and RH.CanImport()
	local linked = {}
	if RH then
		for i, e in ipairs(m.events) do
			if not e.addonOnly then
				local id = RH:ForEvent(e)
				if id then
					local copy = {}
					for k, v in pairs(e) do copy[k] = v end
					copy.importId = id
					m.events[i], linked[id] = copy, true
				end
			end
		end
		for _, row in ipairs(RH:List()) do
			if not linked[row.id] then
				m.events[#m.events + 1] = { key = "h" .. row.id, title = row.rec.title, start = row.rec.start, importId = row.id,
					discordOnly = true, game = RH:EventAt(row.rec) }
			end
		end
	end
	local I = ns.Integrations
	m.fdcp = I ~= nil and (I:Source("raid") == "fdcp" or I:Source("loot") == "fdcp")
	local chosen
	for _, e in ipairs(m.events) do if e.key == key then chosen = e end end
	if not chosen and type(key) == "string" and key:sub(1, 1) == "h" then
		-- the import is now shown with its calendar event
		for _, e in ipairs(m.events) do if e.importId == key:sub(2) then chosen = e end end
	end
	if not chosen then
		for _, e in ipairs(m.events) do
			if e.start >= m.now - 3 * 3600 and (not chosen or e.start < chosen.start) then chosen = e end
		end
		chosen = chosen or m.events[1]
	end
	m.event = chosen
	if chosen and chosen.importId then m.rh = View.ImportModel(chosen, m.officer) end
	if chosen then View.LineupModel(m, chosen) end
	if chosen and not chosen.discordOnly then
		local me = ns.Compat.Player.GUID()
		m.role, m.roleFrom = C:SuggestRole(chosen.key)
		m.outcome = C.outcome[chosen.key]
		m.counts = C:RoleCounts(chosen.key, me)
		if chosen.addonOnly then
			m.answers = C:LocalAnswers(chosen.key)
			for _, a in ipairs(m.answers) do if a.mine or a.guid == me then m.answer = a.answer end end
		else
			m.answer = chosen.answer
			local inv = C.invites[chosen.key]
			m.invites = inv and inv.list or nil
			m.blocked = C:Blocked()
		end
		local own = me and C:RoleOf(chosen.key, me)
		if own and (m.answer == "yes" or m.answer == "maybe") then m.counts[own] = (m.counts[own] or 0) + 1 end
	end
	return m
end

-- The counts of the season roster by MS1, of the guild's source, or nil without one.
local function seasonCounts()
	local C, rows = ns.Composition, nil
	if ns.Season.Source() == "accord" then
		local cur = ns.Season:Current()
		if cur then rows = C.FromAccord(ns.Season:Entries(cur.n)) end
	elseif ns.FDCP then
		local pool = ns.FDCP.Pool()
		if pool and #pool > 0 then rows = (C.FromPool(pool)) end
	end
	return rows and C.Count(rows).ms1 or nil
end

-- What the view shows of an imported event: the own state for everybody, the rest for officers.
function View.ImportModel(event, officer)
	local RH = ns.RaidHelper
	local rec = RH:Get(event.importId)
	if not rec then return nil end
	local own = RH:Own(rec)
	local out = { id = event.importId, at = rec.at, matched = #rec.s, own = own }
	if not officer then return out end
	out.states = {}
	for _, s in ipairs(rec.s) do
		local member = ns.Roster:ByGUID(s.g)
		local name = short(member and member.name or s.g)
		if s.role then name = L["EVENTS_NAME_ROLE"]:format(name, L["SEASON_ROLE_" .. s.role:upper()]) end
		local list = out.states[s.st] or {}
		list[#list + 1] = name
		out.states[s.st] = list
	end
	out.roles, out.season, out.target = RH.Roles(rec), seasonCounts(), ns.Composition:Target()
	out.compare = not event.discordOnly and RH:Compare(rec, event) or nil
	out.unmatched = RH:Unmatched(event.importId)
	out.result = RH.result[event.importId]
	return out
end

-- m.lineupFDCP = { night? } with FDCP as the source; else m.lineup (Composition:Model), m.myPlace (the own person) and,
-- for officers, m.editor (they may place) and m.write (the outcome of the last write into the calendar).
function View.LineupModel(m, event)
	local C = ns.Composition
	if not C then return end
	if raidSource() == "fdcp" then
		local F = ns.FDCP
		local state = F and ns.Integrations:State("fdcp")
		local ready = state and state.level == 1 and F.Ready()
		m.lineupFDCP = { night = ready and F.Night() or nil }
		return
	end
	local lineup = C:Model(event)
	if not lineup then return end
	m.lineup = lineup
	local where, guid = C.PlaceOf(lineup.rec, ns.Compat.Player.GUID())
	for _, p in ipairs(where and lineup[where] or {}) do
		if p.guid == guid then m.myPlace = p end
	end
	m.editor = C:CanEdit() == true and not event.discordOnly
	if m.officer then m.write = ns.RaidHelper.result[C.WriteId(event.key)] end
end

local function nameLines(out, head, names)
	if #names == 0 then return end
	out[#out + 1] = { text = head:format(#names), sub = true }
	for i = 1, #names, View.NAMES_PER_LINE do
		local part = {}
		for j = i, min(#names, i + View.NAMES_PER_LINE - 1) do part[#part + 1] = names[j] end
		out[#out + 1] = { text = concat(part, ", "), indent = true }
	end
end

local function shorten(names)
	local out = {}
	for i, name in ipairs(names) do out[i] = short(name) end
	return out
end

local function stateText(state) return L["RH_STATE_" .. state:upper()] end

-- The outcome of "Put into the game calendar".
local function resultLines(out, res)
	local function add(text, kind) local l = { text = text } if kind then l[kind] = true end out[#out + 1] = l end
	if res.pending then return add(L["RH_RESULT_PENDING"], "muted") end
	if res.created then add(L["RH_RESULT_CREATED"], "muted") end
	if res.ok then add(L["RH_RESULT_DONE"]:format(res.invited, #res.written))
	else add(L["RH_RESULT_STOPPED"]:format(ns.RaidHelperBox.Reason(res.why)), "warn") end
	nameLines(out, L["RH_RESULT_ANSWERED"], shorten(res.answered))
	nameLines(out, L["RH_RESULT_MEMBER"], shorten(res.member))
	nameLines(out, L["RH_RESULT_LEFT"], shorten(res.left))
end

local function personText(p)
	local name = short(p.name)
	if p.role then name = L["EVENTS_NAME_ROLE"]:format(name, roleText(p.role)) end
	if p.roleFrom == "ms2" then name = name .. " " .. L["LINEUP_MARK_MS2"] end
	if p.gone then name = name .. " " .. L["LINEUP_MARK_GONE"] end
	return name
end

local function people(list)
	local out = {}
	for i, p in ipairs(list) do out[i] = personText(p) end
	return out
end

local function placeText(place) return L["LINEUP_PLACE_" .. (place and place:upper() or "NONE")] end

-- The line-up of the chosen event: the own place, the raid and the bench for everybody; the rest for officers.
local function lineupLines(out, m)
	local function add(text, kind) local l = { text = text } if kind then l[kind] = true end out[#out + 1] = l end
	if m.lineupFDCP then
		add(L["LINEUP_TITLE"], "sub")
		add(L["LINEUP_FDCP"], "muted")
		local n = m.lineupFDCP.night
		if n then
			add(L["RAID_NIGHT"]:format(n.instance or "?", n.size and tostring(n.size) or "?", tostring(n.date or "?")), "muted")
			nameLines(out, L["LINEUP_RAID"], shorten(n.raid))
			nameLines(out, L["LINEUP_BENCH"], shorten(n.bench))
		end
		return
	end
	local l = m.lineup
	if not l then return end
	if m.event.discordOnly then
		if m.officer then add(L["LINEUP_NEEDS_GAME"], "muted") end
		return
	end
	-- a member sees the section once there is a line-up
	if not l.rec and not m.editor then return end
	add(L["LINEUP_TITLE"], "sub")
	local mine = m.myPlace
	if mine then
		local text = L["LINEUP_YOURS_" .. mine.place:upper()]
		if mine.role then text = L["LINEUP_YOURS_AS"]:format(text, short(mine.name), roleText(mine.role)) end
		add(text)
	elseif l.rec then
		add(L["LINEUP_YOURS_NONE"], "muted")
	else
		add(L["LINEUP_NONE"], "muted")
	end
	if l.size then add(L["LINEUP_COUNT"]:format(#l.raid, l.size, #l.bench), "muted")
	else add(L["LINEUP_COUNT_NOSIZE"]:format(#l.raid, #l.bench), "muted") end
	local parts = {}
	for _, role in ipairs(ns.Specs.ROLES) do
		local text = L["SEASON_COUNT"]:format(L["SEASON_FIELD_" .. role:upper()], l.roles.raid[role])
		if l.target then text = text .. " " .. L["LINEUP_OF"]:format(l.target[role]) end
		parts[#parts + 1] = text
	end
	out[#out + 1] = { text = concat(parts, View.SEP), indent = true }
	if l.unknown > 0 then add(L["RH_ROLE_UNKNOWN"]:format(l.unknown), "muted") end
	nameLines(out, L["LINEUP_RAID"], people(l.raid))
	nameLines(out, L["LINEUP_BENCH"], people(l.bench))
	if not m.editor then return end
	if m.write then resultLines(out, m.write) end
	nameLines(out, L["LINEUP_FREE"], people(l.free))
	local offers = {}
	for i, o in ipairs(l.offers) do
		offers[i] = L["LINEUP_OFFER"]:format(short(o.person.name), roleText(o.role), placeText(o.person.place))
	end
	nameLines(out, L["LINEUP_OFFERS"], offers)
	if not l.read then add(L["EVENTS_ANSWERS_LATER"], "muted")
	elseif #l.raid + #l.bench + #l.free == 0 then add(L["LINEUP_NOBODY"], "muted") end
end

-- The Raid-Helper part of the chosen event.
local function importLines(out, m)
	local r = m.rh
	if not r then return end
	local function add(text, kind) local l = { text = text } if kind then l[kind] = true end out[#out + 1] = l end
	add(L["RH_SECTION"], "sub")
	add(L["RH_IMPORTED"]:format(whenText(r.at), r.matched), "muted")
	if r.own then
		local detail = {}
		if r.own.class then detail[#detail + 1] = ns.Roster.ClassName(r.own.class) end
		if r.own.role then detail[#detail + 1] = roleText(r.own.role) end
		add(L["RH_YOURS"]:format(stateText(r.own.st)) .. (#detail > 0 and (" (" .. concat(detail, ", ") .. ")") or ""))
	else
		add(L["RH_YOURS_NONE"], "muted")
	end
	if not r.states then return end
	if r.result then resultLines(out, r.result) end
	add(L["RH_ROLES"], "sub")
	for _, role in ipairs(ns.Specs.ROLES) do
		local parts = { L["SEASON_COUNT"]:format(L["SEASON_FIELD_" .. role:upper()], r.roles.signed[role]) }
		if r.roles.tentative[role] > 0 then parts[#parts + 1] = L["RH_ROLE_TENTATIVE"]:format(r.roles.tentative[role]) end
		if r.roles.bench[role] > 0 then parts[#parts + 1] = L["RH_ROLE_BENCH"]:format(r.roles.bench[role]) end
		if r.season then parts[#parts + 1] = L["RH_ROLE_SEASON"]:format(r.season[role]) end
		if r.target then parts[#parts + 1] = L["SEASON_COUNT_TARGET"]:format(r.target[role]) end
		out[#out + 1] = { text = concat(parts, View.SEP), indent = true }
	end
	if r.roles.unknown > 0 then add(L["RH_ROLE_UNKNOWN"]:format(r.roles.unknown), "muted") end
	for _, state in ipairs(ns.RaidHelper.STATE_ORDER) do
		nameLines(out, stateText(state) .. " (%d)", r.states[state] or {})
	end
	local c = r.compare
	if c then
		add(L["RH_COMPARE"], "sub")
		nameLines(out, L["RH_ONLY_DISCORD"], shorten(c.onlyDiscord))
		nameLines(out, L["RH_ONLY_GAME"], shorten(c.onlyGame))
		local differ = {}
		for i, d in ipairs(c.differ) do
			differ[i] = L["RH_DIFFER_NAME"]:format(short(d.name), stateText(d.discord), answerText(d.game))
		end
		nameLines(out, L["RH_DIFFER"], differ)
		if #c.onlyDiscord + #c.onlyGame + #c.differ == 0 then add(L["RH_AGREE"], "muted") end
	elseif m.event and not m.event.discordOnly then
		add(L["RH_COMPARE_LATER"], "muted")
	end
	if r.unmatched and #r.unmatched > 0 then
		nameLines(out, L["RH_UNMATCHED"], r.unmatched)
		add(L["RH_UNMATCHED_HINT"], "muted")
	end
end

local OUTCOME = { blocked = "EVENTS_ERR_BLOCKED", shown = "EVENTS_ERR_SHOWN", pending = "EVENTS_ERR_PENDING", busy = "EVENTS_ERR_PENDING",
	combat = "EVENTS_ERR_COMBAT", encounter = "EVENTS_ERR_COMBAT", calendar = "EVENTS_ERR_CALENDAR", timeout = "EVENTS_ERR_TIMEOUT",
	error = "EVENTS_ERR_SERVER", server = "EVENTS_ERR_SERVER", open = "EVENTS_ERR_MISSING", missing = "EVENTS_ERR_MISSING",
	officer = "EVENTS_ERR_OFFICER", title = "EVENTS_ERR_TITLE", start = "EVENTS_ERR_START", size = "EVENTS_ERR_SIZE",
	note = "EVENTS_ERR_TITLE", role = "EVENTS_ERR_ROLE", off = "EVENTS_ERR_OFF" }
function View.ReasonText(why)
	return L[OUTCOME[why] or "EVENTS_ERR_OTHER"]
end

local function eventLine(e, chosen)
	local parts = { whenText(e.start), e.title or "?" }
	if e.addonOnly then parts[#parts + 1] = L["EVENTS_NOT_IN_GAME"] end
	if e.discordOnly then parts[#parts + 1] = e.game and L["RH_LIST_DISCORD"] or L["RH_LIST_DISCORD_ONLY"]
	elseif e.importId then parts[#parts + 1] = L["RH_LIST_LINKED"] end
	return { text = concat(parts, View.SEP), member = true, selected = chosen or nil }
end

-- { { text, heading?, sub?, muted?, warn?, indent? } } for a model.
function View.Lines(m)
	local out = {}
	local function add(text, kind)
		local l = { text = text }
		if kind then l[kind] = true end
		out[#out + 1] = l
	end
	add(L["EVENTS_TITLE"], "heading")
	if m.state == "available" then add(L["EVENTS_FROM_GAME"], "muted")
	elseif m.state == "missing" then add(m.canCreate and L["EVENTS_NO_CALENDAR_OFFICER"] or L["EVENTS_NO_CALENDAR"], "warn")
	else add(L["EVENTS_WAITING"], "muted") end
	if #m.events == 0 then
		add(m.state == "missing" and L["EVENTS_NONE_LOCAL"] or L["EVENTS_NONE"], "muted")
		return out
	end
	add(L["EVENTS_LIST"]:format(#m.events), "sub")
	for _, e in ipairs(m.events) do
		local l = eventLine(e, m.event ~= nil and e.key == m.event.key)
		if e.key == (m.event and m.event.key) then l.text = L["EVENTS_CHOSEN"]:format(l.text) end
		out[#out + 1] = l
	end
	local e = m.event
	if not e then return out end
	add(L["EVENTS_EVENT"]:format(e.title or "?", whenText(e.start)), "sub")
	if e.discordOnly then
		if not e.game then add(L["RH_NOT_IN_GAME"], "warn") end
		lineupLines(out, m)
		importLines(out, m)
		return out
	end
	if e.addonOnly then
		add(L["EVENTS_NOT_IN_GAME_LONG"], "warn")
		if m.fdcp then add(L["EVENTS_FDCP_NOTE"], "warn") end
		if e.note then add(L["EVENTS_NOTE"]:format(e.note), "muted") end
		add(L["EVENTS_SIZE"]:format(e.size or 0), "muted")
	end
	add(L["EVENTS_YOURS"]:format(answerText(m.answer)))
	if m.role then
		add(L["EVENTS_ROLE"]:format(roleText(m.role), m.roleFrom and L["EVENTS_ROLE_FROM_" .. m.roleFrom:upper()] or ""), "muted")
	end
	local o = m.outcome
	if o then
		if o.pending then add(L["EVENTS_SENDING"], "muted")
		elseif o.ok then add(L["EVENTS_DONE"]:format(answerText(o.answer)), "muted")
		elseif o.why then add(View.ReasonText(o.why), "warn") end
	end
	local parts = {}
	for _, role in ipairs(ns.Specs.ROLES) do
		parts[#parts + 1] = L["SEASON_COUNT"]:format(L["SEASON_FIELD_" .. role:upper()], m.counts and m.counts[role] or 0)
	end
	add(L["EVENTS_ROLES"], "sub")
	out[#out + 1] = { text = concat(parts, View.SEP), indent = true }
	-- the answers of everybody
	local groups = { yes = {}, maybe = {}, no = {} }
	local list = e.addonOnly and m.answers or m.invites
	if list then
		for _, a in ipairs(list) do
			if a.answer and groups[a.answer] then
				local name = short(a.name or a.guid)
				local role = a.role or (a.guid and ns.Calendar:RoleOf(e.key, a.guid))
				if role and a.answer ~= "no" then name = L["EVENTS_NAME_ROLE"]:format(name, roleText(role)) end
				local g = groups[a.answer]
				g[#g + 1] = name
			end
		end
		nameLines(out, L["EVENTS_YES"], groups.yes)
		nameLines(out, L["EVENTS_MAYBE"], groups.maybe)
		nameLines(out, L["EVENTS_NO"], groups.no)
		if #groups.yes + #groups.maybe + #groups.no == 0 then add(L["EVENTS_NOBODY"], "muted") end
	elseif not e.addonOnly then
		add(m.blocked and View.ReasonText(m.blocked) or L["EVENTS_ANSWERS_LATER"], "muted")
	end
	lineupLines(out, m)
	importLines(out, m)
	return out
end

-- The choices of the officer's row: everybody signed up or placed, then the MS2 offers. id = GUID, or GUID .. ":ms2".
function View.PlaceChoices(m)
	local out, l = {}, m.lineup
	if not l then return out end
	for _, list in ipairs({ l.free, l.raid, l.bench }) do
		for _, p in ipairs(list) do
			out[#out + 1] = { id = p.guid, text = L["LINEUP_CHOICE"]:format(personText(p), placeText(p.place)) }
		end
	end
	for _, o in ipairs(l.offers) do
		out[#out + 1] = { id = o.person.guid .. ":ms2",
			text = L["LINEUP_OFFER"]:format(short(o.person.name), roleText(o.role), placeText(o.person.place)) }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------------
function View:Say(text)
	local f = self.frame
	if f then f.message:SetText(text or "") end
	self.said = text
end

-- The player's answer to the chosen event, from a click.
function View:Answer(answer)
	local m = View.Model(self.chosen)
	local e = m.event
	if not e then return false, "missing" end
	local role = self.frame and self.frame.role:Selected() or m.role
	local ok, why = ns.Calendar:Answer(e.key, answer, role)
	if ok then
		self:Say(why == "pending" and L["EVENTS_SENDING"] or L["EVENTS_DONE"]:format(answerText(answer)))
	else
		self:Say(View.ReasonText(why))
	end
	self:Redraw()
	return ok, why
end

-- An officer creates an event of the addon (only without a usable calendar).
function View:Create(title, when, size, note)
	local rec, why = ns.Calendar:CreateLocal(title, View.ParseWhen(when), tonumber(size), note)
	if rec then
		self.chosen = nil
		self:Say(L["EVENTS_CREATED"]:format(rec.title))
		if self.frame then self.frame.title:Clear() end
	else
		self:Say(View.ReasonText(why))
	end
	self:Redraw()
	return rec, why
end

function View.LineupReason(why)
	return rawget(L, "LINEUP_ERR_" .. tostring(why):upper()) or ns.RaidHelperBox.Reason(why)
end

-- An officer places the chosen person (from a click): where = "raid" | "bench" | nil (taken out). `choice` is an id of
-- View.PlaceChoices.
function View:Place(choice, where)
	local m = View.Model(self.chosen)
	if not m.event then return false, "missing" end
	if type(choice) ~= "string" then
		self:Say(L["LINEUP_ERR_CHOOSE"])
		return false, "choose"
	end
	local guid = choice:match("^(.-):ms2$")
	self.confirm = nil
	local ok, why = ns.Composition:Place(m.event, guid or choice, where, guid ~= nil)
	self:Say(ok and "" or View.LineupReason(why))
	self:Redraw()
	return ok, why
end

-- What the officer confirms before the line-up goes into the game calendar.
function View.LineupConfirmText(plan)
	local parts = { L["LINEUP_CONFIRM"]:format(plan.members) }
	if plan.total > plan.members then parts[#parts + 1] = L["RH_CONFIRM_MORE"]:format(plan.total - plan.members) end
	parts[#parts + 1] = L["RH_CONFIRM_PRESS"]
	return concat(parts, " ")
end

-- What the second click confirms: this version of this event's line-up (a changed one is confirmed again).
local function lineupToken(m) return "C:" .. m.event.key .. ":" .. m.lineup.rec.rev end

-- "Write to calendar": the first click says what will happen, the second does it.
function View:PushLineup()
	local m = View.Model(self.chosen)
	if not (m.event and m.lineup and m.lineup.rec) then return false, "empty" end
	local token = lineupToken(m)
	if self.confirm ~= token then
		local plan, why = ns.Composition:Plan(m.event)
		if not plan then
			self:Say(View.LineupReason(why))
			self:Redraw()
			return false, why
		end
		self.confirm = token
		self:Say(View.LineupConfirmText(plan))
		self:Redraw()
		return false, "confirm"
	end
	self.confirm = nil
	local ok, why = ns.Composition:Push(m.event)
	self:Say(ok and "" or View.LineupReason(why))
	self:Redraw()
	return ok, why
end

function View:Choose(key)
	if key ~= self.chosen then self.confirm = nil end
	self.chosen = key
	local e = ns.Calendar:Event(key)
	if e then ns.Calendar:LoadInvites(key) end
	self:Redraw()
end

-- Opens the view on an event (the row of the Action Center).
function View:Open(key)
	if ns.Shell and not ns.Shell:OpenView("events") then return false end
	self:ShowPage("events")
	self:Choose(key)
	return true
end

-- The box imported event `id`: it is chosen, with its calendar event when there is one.
function View:Imported(id, title)
	local rec = ns.RaidHelper:Get(id)
	local e = rec and ns.RaidHelper:EventAt(rec)
	self:Say(L["RH_DONE_IMPORT"]:format(title or "?"))
	local key = "h" .. id
	if e and ns.Calendar:Event(e.key) then key = e.key end
	self:Choose(key)
end

-- What the officer confirms before Accord writes into the game calendar.
function View.ConfirmText(plan)
	local parts = { (plan.create and L["RH_CONFIRM_CREATE"] or L["RH_CONFIRM_WRITE"]):format(plan.members) }
	if plan.total > plan.members then parts[#parts + 1] = L["RH_CONFIRM_MORE"]:format(plan.total - plan.members) end
	if plan.other then parts[#parts + 1] = L["RH_CONFIRM_OTHER"]:format(plan.other) end
	parts[#parts + 1] = L["RH_CONFIRM_PRESS"]
	return concat(parts, " ")
end

-- "Put into the game calendar": the first click says what will happen, the second does it.
function View:Push()
	local m = View.Model(self.chosen)
	local id = m.event and m.event.importId
	if not id then return false, "missing" end
	if self.confirm ~= id then
		local plan, why = ns.RaidHelper:Plan(id)
		if not plan then
			self:Say(ns.RaidHelperBox.Reason(why))
			self:Redraw()
			return false, why
		end
		self.confirm = id
		self:Say(View.ConfirmText(plan))
		self:Redraw()
		return false, "confirm"
	end
	self.confirm = nil
	local ok, why = ns.RaidHelper:Push(id)
	self:Say(ok and "" or ns.RaidHelperBox.Reason(why))
	self:Redraw()
	return ok, why
end

-- A hand match of a name that matched nobody.
function View:Match(name, member)
	local m = View.Model(self.chosen)
	local id = m.event and m.event.importId
	if not (id and name) then
		self:Say(L["RH_ERR_NAME"])
		return false, "name"
	end
	local ok, why = ns.RaidHelper:SetMatch(id, name, member)
	if ok then
		self:Say(why == "added" and L["RH_MATCHED"]:format(name) or L["RH_MATCHED_PASTE"]:format(name))
		if self.frame then self.frame.member:Clear() end
	else
		self:Say(ns.RaidHelperBox.Reason(why))
	end
	self:Redraw()
	return ok, why
end

-- The export back to Discord of the chosen event (officers). Returns the text, or nil and a reason.
function View:Export()
	local m = View.Model(self.chosen)
	local e = m.event
	-- an event only of the addon is exported once it has a line-up
	if not e or (e.addonOnly and not (m.lineup and m.lineup.rec)) then return nil, "missing" end
	local rec = e.importId and ns.RaidHelper:Get(e.importId) or nil
	local rows = ns.RaidHelper:ExportRows(not e.discordOnly and e or nil, rec)
	if #rows == 0 then
		self:Say(L["RH_EXPORT_NONE"])
		return nil, "empty"
	end
	rows.subject = L["EVENTS_EVENT"]:format((e.title or "?"):gsub("||", "|"), whenText(e.start))
	return ns.ExportBox:Open("event", rows)
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local function visibleRows(list)
	local h = list and list:GetHeight() or 0
	return h >= View.ROW_HEIGHT and floor(h / View.ROW_HEIGHT) or 16
end

function View:Build(f)
	self.frame = f
	f.picker = Widgets.Select(f, { width = 320, rows = 8, onSelect = function(id)
		if View.painting then return end
		View:Choose(id)
	end })
	f.picker:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.game = Widgets.Button(f, { text = L["EVENTS_OPEN_GAME"], style = "secondary", height = 28, onClick = function()
		ns.Compat.Calendar.ShowGame()
	end })
	f.game:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

	-- the own answer
	f.answer = CreateFrame("Frame", nil, f)
	f.answer:SetHeight(32)
	f.role = Widgets.Select(f.answer, { width = 120, rows = 4 })
	f.role:SetPoint("TOPLEFT", f.answer, "TOPLEFT", 0, 0)
	local roles = {}
	for _, r in ipairs(ns.Specs.ROLES) do roles[#roles + 1] = { id = r, text = roleText(r) } end
	f.role:SetChoices(roles)
	f.yes = Widgets.Button(f.answer, { text = L["EVENTS_SIGN_UP"], style = "primary", height = 28, onClick = function() View:Answer("yes") end })
	f.yes:SetPoint("LEFT", f.role, "RIGHT", 8, 0)
	f.maybe = Widgets.Button(f.answer, { text = L["EVENTS_TENTATIVE"], style = "secondary", height = 28, onClick = function() View:Answer("maybe") end })
	f.maybe:SetPoint("LEFT", f.yes, "RIGHT", 8, 0)
	f.no = Widgets.Button(f.answer, { text = L["EVENTS_DECLINE"], style = "secondary", height = 28, onClick = function() View:Answer("no") end })
	f.no:SetPoint("LEFT", f.maybe, "RIGHT", 8, 0)

	-- officers, without a usable calendar: an event of the addon
	f.create = CreateFrame("Frame", nil, f)
	f.create:SetHeight(32)
	f.title = Widgets.EditBox(f.create, { width = 200, height = 28, maxLetters = ns.Calendar.TITLE_MAX, placeholder = L["EVENTS_TITLE_HINT"] })
	f.title:SetPoint("TOPLEFT", f.create, "TOPLEFT", 0, 0)
	f.when = Widgets.EditBox(f.create, { width = 140, height = 28, maxLetters = 16, placeholder = L["EVENTS_WHEN_HINT"] })
	f.when:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
	f.size = Widgets.Select(f.create, { width = 110, rows = 4 })
	f.size:SetPoint("LEFT", f.when, "RIGHT", 8, 0)
	local sizes = {}
	for _, n in ipairs({ 10, 20, 25, 40 }) do sizes[#sizes + 1] = { id = tostring(n), text = L["SEASON_TARGET_SIZE"]:format(n) } end
	f.size:SetChoices(sizes)
	f.size:Select("40", true)
	f.createButton = Widgets.Button(f.create, { text = L["EVENTS_CREATE"], style = "primary", height = 28, onClick = function()
		View:Create(f.title:GetText(), f.when:GetText(), f.size:Selected())
	end })
	f.createButton:SetPoint("LEFT", f.size, "RIGHT", 8, 0)

	-- officers: Raid-Helper (M10.6)
	f.rhRow = CreateFrame("Frame", nil, f)
	f.rhRow:SetHeight(32)
	f.import = Widgets.Button(f.rhRow, { text = L["RH_IMPORT_BUTTON"], style = "secondary", height = 28, onClick = function()
		ns.RaidHelperBox:Open()
	end })
	f.push = Widgets.Button(f.rhRow, { text = L["RH_PUSH"], style = "secondary", height = 28, onClick = function() View:Push() end })
	f.export = Widgets.Button(f.rhRow, { text = L["EXPORT_BUTTON"], style = "secondary", height = 28, onClick = function() View:Export() end })
	f.matchRow = CreateFrame("Frame", nil, f)
	f.matchRow:SetHeight(32)
	f.unmatched = Widgets.Select(f.matchRow, { width = 200, rows = 8, placeholder = L["RH_MATCH_NAME"] })
	f.unmatched:SetPoint("TOPLEFT", f.matchRow, "TOPLEFT", 0, 0)
	f.member = Widgets.EditBox(f.matchRow, { width = 180, height = 28, maxLetters = 64, placeholder = L["RH_MATCH_MEMBER"] })
	f.member:SetPoint("LEFT", f.unmatched, "RIGHT", 8, 0)
	f.match = Widgets.Button(f.matchRow, { text = L["RH_MATCH"], style = "secondary", height = 28, onClick = function()
		View:Match(f.unmatched:Selected(), f.member:GetText())
	end })
	f.match:SetPoint("LEFT", f.member, "RIGHT", 8, 0)
	-- officers: the line-up and the bench (M10.7)
	f.placeRow = CreateFrame("Frame", nil, f)
	f.placeRow:SetHeight(32)
	f.person = Widgets.Select(f.placeRow, { width = 240, rows = 10, placeholder = L["LINEUP_CHOOSE"] })
	f.person:SetPoint("TOPLEFT", f.placeRow, "TOPLEFT", 0, 0)
	f.toRaid = Widgets.Button(f.placeRow, { text = L["LINEUP_TO_RAID"], style = "primary", height = 28, onClick = function()
		View:Place(f.person:Selected(), "raid")
	end })
	f.toRaid:SetPoint("LEFT", f.person, "RIGHT", 8, 0)
	f.toBench = Widgets.Button(f.placeRow, { text = L["LINEUP_TO_BENCH"], style = "secondary", height = 28, onClick = function()
		View:Place(f.person:Selected(), "bench")
	end })
	f.toBench:SetPoint("LEFT", f.toRaid, "RIGHT", 8, 0)
	f.takeOut = Widgets.Button(f.placeRow, { text = L["LINEUP_REMOVE"], style = "secondary", height = 28, onClick = function()
		View:Place(f.person:Selected(), nil)
	end })
	f.takeOut:SetPoint("LEFT", f.toBench, "RIGHT", 8, 0)
	f.write = Widgets.Button(f.placeRow, { text = L["LINEUP_WRITE"], style = "secondary", height = 28, onClick = function()
		View:PushLineup()
	end })
	f.write:SetPoint("LEFT", f.takeOut, "RIGHT", 8, 0)
	f.message = Widgets.Text(f, "Small", "text-3", "LEFT")

	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.list:SetClipsChildren(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	f.list.lines = {}
	f.offset = 0
	f:SetScript("OnShow", function()
		if ns.Calendar.Enabled() then ns.Calendar:Start() end
		View:Redraw()
	end)
	self:Redraw()
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local m = View.Model(self.chosen)
	self.model = m
	self.painting = true
	local choices = {}
	for _, e in ipairs(m.events) do
		local text = whenText(e.start) .. "  " .. (e.title or "?")
		if e.addonOnly or e.discordOnly then text = text .. "  *" end
		choices[#choices + 1] = { id = e.key, text = text }
	end
	f.picker:SetChoices(choices)
	f.picker:SetShown(#choices > 0)
	if m.event then f.picker:Select(m.event.key, true) end
	f.game:SetShown(m.state ~= "missing")

	local y = -40
	local answers = m.event ~= nil and not m.event.discordOnly
	f.answer:SetShown(answers)
	if answers then
		f.answer:ClearAllPoints()
		f.answer:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		f.answer:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		local roleKey = m.event.key .. ":" .. tostring(m.role)
		if self.roleKey ~= roleKey and m.role then
			self.roleKey = roleKey
			f.role:Select(m.role, true)
		end
		y = y - 40
	end
	f.create:SetShown(m.canCreate)
	if m.canCreate then
		f.create:ClearAllPoints()
		f.create:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		f.create:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		y = y - 40
	end
	-- officers: import a Raid-Helper event, put it into the game calendar, export the event back to Discord
	f.rhRow:SetShown(m.officer == true)
	if m.officer then
		f.rhRow:ClearAllPoints()
		f.rhRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		f.rhRow:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		local shown = { f.import }
		local push = m.rh ~= nil and m.state == "available"
		local export = m.event ~= nil and (not m.event.addonOnly or (m.lineup ~= nil and m.lineup.rec ~= nil))
		f.push:SetShown(push)
		f.export:SetShown(export)
		if push then
			f.push:SetLabel(self.confirm == m.rh.id and L["RH_CONFIRM"] or L["RH_PUSH"])
			shown[#shown + 1] = f.push
		end
		if export then shown[#shown + 1] = f.export end
		for i, button in ipairs(shown) do
			button:ClearAllPoints()
			if i == 1 then button:SetPoint("TOPLEFT", f.rhRow, "TOPLEFT", 0, 0)
			else button:SetPoint("LEFT", shown[i - 1], "RIGHT", 8, 0) end
		end
		y = y - 40
	end
	local unmatched = m.officer and m.rh and m.rh.unmatched or nil
	f.matchRow:SetShown(unmatched ~= nil and #unmatched > 0)
	if unmatched and #unmatched > 0 then
		f.matchRow:ClearAllPoints()
		f.matchRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		f.matchRow:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		local names = {}
		for i, name in ipairs(unmatched) do names[i] = { id = name, text = name } end
		f.unmatched:SetChoices(names)
		y = y - 40
	end
	f.placeRow:SetShown(m.editor == true)
	if m.editor then
		f.placeRow:ClearAllPoints()
		f.placeRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		f.placeRow:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		f.person:SetChoices(View.PlaceChoices(m))
		local write = m.lineup.rec ~= nil and not m.event.addonOnly and m.state == "available"
		f.write:SetShown(write)
		if write then f.write:SetLabel(self.confirm == lineupToken(m) and L["RH_CONFIRM"] or L["LINEUP_WRITE"]) end
		y = y - 40
	end
	self.painting = false
	f.message:ClearAllPoints()
	f.message:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
	f.message:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.message:SetText(self.said or "")
	y = y - 20
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)

	local lines = View.Lines(m)
	self.shown = lines
	local list = f.list
	local visible = visibleRows(list)
	f.offset = max(0, min(f.offset or 0, max(0, #lines - visible)))
	local drawn = max(0, min(visible, #lines - f.offset))
	for i = 1, drawn do
		local l = lines[f.offset + i]
		local fs = list.lines[i]
		if not fs then
			fs = Widgets.Text(list, "Body", "text-1", "LEFT")
			fs:SetWordWrap(false)
			list.lines[i] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", list, "TOPLEFT", (l.indent or l.member) and 12 or 0, -(i - 1) * View.ROW_HEIGHT)
		fs:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		fs:SetText(l.text)
		fs:SetFontObject(Theme.Font(l.heading and "H2" or l.sub and "BodyMedium" or "Body"))
		if l.heading then Theme.Text(fs, "text-1")
		elseif l.warn then Theme.Text(fs, "warn")
		elseif l.muted then Theme.Text(fs, "text-3")
		elseif l.selected then Theme.Text(fs, "text-1")
		else Theme.Text(fs, "text-2") end
		fs:Show()
	end
	for i = drawn + 1, #list.lines do list.lines[i]:Hide() end
end

function View:Scroll(delta)
	local f = self.frame
	if not f then return false end
	local total = self.shown and #self.shown or 0
	local target = max(0, min((f.offset or 0) + delta, max(0, total - visibleRows(f.list))))
	if target == f.offset then return false end
	f.offset = target
	self:Redraw()
	return true
end

function View:Changed()
	if self.refreshTimer or not (self.frame and self.frame:IsVisible()) then return end
	self.refreshTimer = true
	local scheduled = ns.Compat and ns.Compat.After(View.REFRESH_DELAY, function()
		View.refreshTimer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.refreshTimer = nil self:Redraw() end
end

---------------------------------------------------------------------------------------------------------------------
-- The two pages of the view: the events (above) and the rallies (UI/Rallies.lua, M10.9)
---------------------------------------------------------------------------------------------------------------------
View.PAGER_HEIGHT = 44
View.pageId = "events"

function View:ShowPage(id)
	if id ~= "events" and id ~= "rallies" then return false end
	self.pageId = id
	local f = self.root
	if not f then return true end
	local holder = f.holders[id]
	if not holder then
		holder = CreateFrame("Frame", nil, f)
		holder:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.PAGER_HEIGHT)
		holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		holder:Hide()   -- built hidden, so showing it runs the page's OnShow
		f.holders[id] = holder
		if id == "events" then self:Build(holder) else ns.RalliesView:Build(holder) end
	end
	for pid, other in pairs(f.holders) do
		if pid ~= id then other:Hide() end
	end
	holder:Show()
	f.pager:Select(id)
	return true
end

function View:BuildPages(f)
	self.root = f
	f.holders = {}
	f.pager = Widgets.Segmented(f, { { id = "events", text = L["EVENTS_PAGE_EVENTS"] }, { id = "rallies", text = L["EVENTS_PAGE_RALLIES"] } },
		function(id) if id ~= View.pageId then View:ShowPage(id) end end)
	f.pager:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	self:ShowPage(self.pageId)
end

if ns.Shell then
	ns.Shell:RegisterView("events", { label = L["VIEW_EVENTS"], order = 46, visible = on, build = function(f) View:BuildPages(f) end })
end

if ns.addon then
	ns.addon.EventsView = View
	if ns.Bus then
		local function changed() if on() then View:Changed() end end
		for _, event in ipairs({ "CALENDAR_CHANGED", "EVENT_CHANGED", "SEASON_CHANGED", "SOURCES_CHANGED", "ROLE_CHANGED",
			"ROSTER_UPDATED", "ACCOUNTS_UPDATED", "FEATURE_CHANGED", "FDCP_CHANGED" }) do
			ns.Bus:On(event, changed)
		end
	end
end

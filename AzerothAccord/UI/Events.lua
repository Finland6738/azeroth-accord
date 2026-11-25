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
--
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
	local I = ns.Integrations
	m.fdcp = I ~= nil and (I:Source("raid") == "fdcp" or I:Source("loot") == "fdcp")
	local chosen
	for _, e in ipairs(m.events) do if e.key == key then chosen = e end end
	if not chosen then
		for _, e in ipairs(m.events) do
			if not chosen and e.start >= m.now - 3 * 3600 then chosen = e end
		end
		chosen = chosen or m.events[1]
	end
	m.event = chosen
	if chosen then
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

local function nameLines(out, head, names)
	if #names == 0 then return end
	out[#out + 1] = { text = head:format(#names), sub = true }
	for i = 1, #names, View.NAMES_PER_LINE do
		local part = {}
		for j = i, min(#names, i + View.NAMES_PER_LINE - 1) do part[#part + 1] = names[j] end
		out[#out + 1] = { text = concat(part, ", "), indent = true }
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

function View:Choose(key)
	self.chosen = key
	local e = ns.Calendar:Event(key)
	if e then ns.Calendar:LoadInvites(key) end
	self:Redraw()
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
	f.title = Widgets.EditBox(f.create, { width = 200, maxLetters = ns.Calendar.TITLE_MAX, placeholder = L["EVENTS_TITLE_HINT"] })
	f.title:SetPoint("TOPLEFT", f.create, "TOPLEFT", 0, 0)
	f.when = Widgets.EditBox(f.create, { width = 140, maxLetters = 16, placeholder = L["EVENTS_WHEN_HINT"] })
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
		if e.addonOnly then text = text .. "  *" end
		choices[#choices + 1] = { id = e.key, text = text }
	end
	f.picker:SetChoices(choices)
	f.picker:SetShown(#choices > 0)
	if m.event then f.picker:Select(m.event.key, true) end
	f.game:SetShown(m.state ~= "missing")

	local y = -40
	f.answer:SetShown(m.event ~= nil)
	if m.event then
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

if ns.Shell then
	ns.Shell:RegisterView("events", { label = L["VIEW_EVENTS"], order = 46, visible = on, build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.EventsView = View
	if ns.Bus then
		local function changed() if on() then View:Changed() end end
		for _, event in ipairs({ "CALENDAR_CHANGED", "EVENT_CHANGED", "SEASON_CHANGED", "SOURCES_CHANGED", "ROLE_CHANGED",
			"ROSTER_UPDATED", "FEATURE_CHANGED" }) do
			ns.Bus:On(event, changed)
		end
	end
end

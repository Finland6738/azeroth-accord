-- Season view: the guild's season roster (M10.3; SPEC-14 §3, §4.4; M10 integration rules; ADR 0022). Lua 5.1.
--
-- At the top, the source of the season roster (Data/Integrations.lua, the guild setting of M10.2): "Accord" or "FDCP",
-- a Widgets.Segmented only officers can change, the season picker (older seasons stay readable) and "Open FDCP" while
-- FDCP is loaded on this client. Below, depending on the source:
--   * Accord: officers (Raid.WRITERS, SPEC-10 Q21) open a season with a name (it starts today) or close the current one;
--     each raider declares for the current season MS1 with its role, MS2, OS and a note, or "Not sure yet". Saving asks
--     a second click that repeats the lock (SPEC-14 §4.4). After Season.LOCK the specs show locked, the note can still
--     change. The list shows every declaration of the chosen season, one per account (SEA-05).
--   * FDCP: Accord asks for no declaration (SEA-06): FDCP's season and pool, read from its public API at level 1 (the
--     lines of UI/Raid.lua, M11.7), or why there is nothing and the Open FDCP button at level 0.
-- At the end, "Raid and loot addons in the guild" (M10.2): the same lines as the Raid view (UI/Raid.lua).
--
-- View.Model(n) reads everything now; View.Lines(model) is a plain function of it (tested offline); the frames only draw.
-- The officers' counts, the gaps and the export come with M10.4.
-- While Core/Features.lua "season" is off there is no tab, no command and nothing is redrawn.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.SeasonView, ns.modules = View, ns.modules or {}
ns.modules.SeasonView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring, floor, max, min, concat = type, ipairs, tostring, math.floor, math.max, math.min, table.concat

View.ROW_HEIGHT = 20
View.WHEEL_STEP = 3
View.REFRESH_DELAY = 0.4
View.SEP = " · "
View.NONE = "-"                 -- the "no spec" choice of the MS2 and OS pickers

local function on() return ns.Features ~= nil and ns.Features.On("season") end
View.Enabled = on

local function short(name)
	if type(name) ~= "string" then return "?" end
	return (ns.Compat.SplitName(name))
end

-- 20261125 -> "2026-11-25"
local function dayText(d)
	if type(d) ~= "number" then return "?" end
	return ("%04d-%02d-%02d"):format(floor(d / 10000), floor(d / 100) % 100, d % 100)
end
View.DayText = dayText

local function timeText(t)
	if type(t) ~= "number" then return "?" end
	return date("!%Y-%m-%d %H:%M", t)
end

local function roleText(role) return L["SEASON_ROLE_" .. tostring(role):upper()] or tostring(role) end

-- "Arms (melee)"
local function pickText(p)
	if type(p) ~= "table" then return nil end
	return L["SEASON_PICK"]:format(ns.Specs.Name(p.spec), roleText(p.role))
end
View.PickText = pickText

---------------------------------------------------------------------------------------------------------------------
-- The model and its lines
---------------------------------------------------------------------------------------------------------------------
-- Everything the lines need, for season `n` (nil: the current one, else the newest).
function View.Model(n)
	local I, Se = ns.Integrations, ns.Season
	local m = { raid = I and I:Source("raid") or "accord", canChoose = I ~= nil and I:CanChoose(), now = ns.Compat.ServerTime() }
	m.fdcp = I and I:State("fdcp") or nil
	m.canOpen = Se:CanOpen()
	m.seasons = Se:List()
	m.current = Se:Current()
	local chosen = n and Se:Get(n) or m.current or m.seasons[1]
	m.season = chosen
	if m.raid == "fdcp" then
		if m.fdcp and m.fdcp.level == 1 and ns.FDCP then
			m.ready = ns.FDCP.Ready()
			if m.ready then m.source, m.version, m.fdcpSeason, m.pool = ns.FDCP.Source(), ns.FDCP.Version(), ns.FDCP.Season(), ns.FDCP.Pool() end
		end
	elseif chosen then
		m.entries = Se:Entries(chosen.n)
		m.own = Se:Own(chosen.n)
		m.isCurrent = m.current ~= nil and chosen.n == m.current.n
		if m.isCurrent then m.canDeclare, m.why = Se:CanDeclare() end
	end
	if ns.RaidView and ns.RaidView.AddonsModel then ns.RaidView.AddonsModel(m) end
	return m
end

local function entryLine(row)
	local r = row.rec
	local parts = { short(row.name or row.guid) }
	local className = r.class and ns.Roster and ns.Roster.ClassName(r.class)
	if className then parts[#parts + 1] = className end
	if r.unsure then
		parts[#parts + 1] = L["SEASON_UNSURE"]
	else
		parts[#parts + 1] = L["RAID_MS1"]:format(pickText(r.ms1))
		if r.ms2 then parts[#parts + 1] = L["RAID_MS2"]:format(pickText(r.ms2)) end
		if r.os then parts[#parts + 1] = L["RAID_OS"]:format(pickText(r.os)) end
	end
	if r.note then parts[#parts + 1] = L["SEASON_NOTE_LINE"]:format(r.note) end
	return { text = concat(parts, View.SEP), member = row.name }
end
View.EntryLine = entryLine

local function ownLines(m, add)
	local own = m.own
	if not m.isCurrent then
		if own then add(L["SEASON_OWN_OLD"]:format(entryLine({ rec = own, name = ns.Compat.Player.Name() }).text), "sub") end
		return
	end
	if m.why == "account" and own then
		local member = ns.Roster and ns.Roster:ByGUID(ns.Season.EntryChar(own))
		add(L["SEASON_OWN_ALT"]:format(short(member and member.name or "?")), "muted")
		return
	end
	if not own then
		add(L["SEASON_OWN_NONE"], "muted")
	elseif ns.Season.IsLocked(own, m.now) then
		add(L["SEASON_OWN_LOCKED"]:format(timeText(own.first + ns.Season.LOCK)), "sub")
		if own.unsure and not own.conv then add(L["SEASON_OWN_UNSURE_ONCE"], "muted") end
	else
		local left = max(1, floor((own.first + ns.Season.LOCK - m.now) / 60 + 0.5))
		add(L["SEASON_OWN_WINDOW"]:format(left), "sub")
	end
	add(L["SEASON_HOLDS"], "muted")
end

-- { { text, heading?, sub?, muted?, warn?, indent? } } for a model.
function View.Lines(m)
	local out = {}
	local function add(text, kind)
		local l = { text = text }
		if kind then l[kind] = true end
		out[#out + 1] = l
	end
	add(L["RAID_SEASON"], "heading")
	if m.raid == "fdcp" then
		add(L["SEASON_FDCP_SOURCE"], "muted")
		if #(m.seasons or {}) > 0 then add(L["SEASON_FDCP_HIDDEN"], "muted") end
		local RV = ns.RaidView
		local why = RV.Problem(m)
		if why then
			add(why, "warn")
		else
			add(L["FDCP_STATUS"]:format(m.version or "?", m.source == "LEDGER" and L["FDCP_FROM_LEDGER"] or L["FDCP_FROM_SNAPSHOT"]), "muted")
			local s = m.fdcpSeason
			if s then
				local state = s.state == "OPEN" and L["SEASON_OPEN"] or s.state == "CLOSED" and L["SEASON_CLOSED"] or "?"
				add(L["RAID_SEASON_LINE"]:format(s.name or tostring(s.id or "?"), state))
			end
			if m.pool == nil then add(L["RAID_NO_POOL"], "muted")
			elseif #m.pool == 0 then add(L["RAID_POOL_EMPTY"], "muted")
			else
				add(L["RAID_POOL"]:format(#m.pool), "sub")
				if m.source == "SNAPSHOT" then add(L["RAID_POOL_MEMBER"], "muted") end
				for _, e in ipairs(m.pool) do out[#out + 1] = RV.MemberLine(e) end
			end
		end
	else
		local s = m.season
		if not s then
			add(m.canOpen and L["SEASON_NONE_OFFICER"] or L["SEASON_NONE"], "muted")
		else
			local state = s.closed and L["SEASON_CLOSED"] or L["SEASON_OPEN"]
			add(L["SEASON_LINE"]:format(s.name, state, dayText(s.start)))
			if not m.current then add(m.canOpen and L["SEASON_NONE_OFFICER"] or L["SEASON_NONE"], "muted") end
			ownLines(m, add)
			add(L["SEASON_LIST"]:format(#m.entries), "sub")
			if #m.entries == 0 then add(L["SEASON_EMPTY"], "muted") end
			local hidden = 0
			for _, row in ipairs(m.entries) do
				out[#out + 1] = entryLine(row)
				hidden = hidden + #row.hidden
			end
			if hidden > 0 then add(L["SEASON_HIDDEN_ALTS"]:format(hidden), "muted") end
		end
	end
	if m.addons and ns.RaidView.AddonsLines then ns.RaidView.AddonsLines(out, m, add) end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The declaration form (pure helpers, tested offline)
---------------------------------------------------------------------------------------------------------------------
-- The spec choices for a class: { { id = "ARMS", text = "Arms" } }, with "-" first when `optional`.
function View.SpecChoices(classFile, optional)
	local out = {}
	if optional then out[1] = { id = View.NONE, text = L["SEASON_NO_SPEC"] } end
	for _, s in ipairs(ns.Specs.Of(classFile)) do out[#out + 1] = { id = s.spec, text = ns.Specs.Name(s.spec) } end
	return out
end

function View.RoleChoices(classFile, spec)
	local out = {}
	for _, r in ipairs(ns.Specs.Roles(classFile, spec) or {}) do out[#out + 1] = { id = r, text = roleText(r) } end
	return out
end

-- The declaration from the form's values: { ms1 = { spec, role }, ms2?, os?, note }.
function View.Declaration(v)
	local function p(spec, role)
		if spec == nil or spec == View.NONE or role == nil then return nil end
		return { spec = spec, role = role }
	end
	return { ms1 = p(v.ms1, v.ms1role), ms2 = p(v.ms2, v.ms2role), os = p(v.os, v.osrole), note = v.note, unsure = v.unsure }
end

local REASONS = { off = "SEASON_ERR_OFF", source = "SEASON_ERR_SOURCE", season = "SEASON_ERR_SEASON", account = "SEASON_ERR_ACCOUNT",
	class = "SEASON_ERR_CLASS", content = "SEASON_ERR_CONTENT", locked = "SEASON_ERR_LOCKED", officer = "SEASON_ERR_OFFICER",
	name = "SEASON_ERR_NAME" }
function View.ReasonText(why)
	return L[REASONS[why] or "SEASON_ERR_OTHER"]
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local function label(f, text, x, y)
	local t = Widgets.Text(f, "BodyMedium", "text-2", "LEFT")
	t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 8)
	t:SetText(text)
	return t
end

local function pair(f, x, y, optional, key)
	local spec = Widgets.Select(f, { width = 120, rows = 4, onSelect = function() View:SpecPicked(key) end })
	spec:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
	local role = Widgets.Select(f, { width = 90, rows = 4 })
	role:SetPoint("LEFT", spec, "RIGHT", 6, 0)
	spec.optional = optional
	return spec, role
end

function View:Build(f)
	self.frame = f
	f.sourceLabel = label(f, L["SOURCE_RAID"], 0, 0)
	f.sourceSeg = Widgets.Segmented(f, { { id = "accord", text = L["SOURCE_ACCORD"] }, { id = "fdcp", text = L["SOURCE_FDCP"] } },
		function(id)
			if View.painting then return end
			local ok = ns.Integrations and ns.Integrations:SetSource("raid", id)
			if not ok then View:Redraw() end
		end)
	f.sourceSeg:SetPoint("TOPLEFT", f, "TOPLEFT", 130, 0)
	f.picker = Widgets.Select(f, { width = 180, rows = 5, onSelect = function(id)
		if View.painting then return end
		View.chosen = tonumber(id)
		View:Redraw()
	end })
	f.picker:SetPoint("TOPLEFT", f.sourceSeg, "TOPRIGHT", 16, 0)
	f.open = Widgets.Button(f, { text = L["FDCP_OPEN"], style = "secondary", height = 28, onClick = function() ns.FDCP.Open() end })
	f.open:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

	-- officers: open or close a season
	f.officer = CreateFrame("Frame", nil, f)
	f.officer:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -40)
	f.officer:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.officer:SetHeight(32)
	f.seasonName = Widgets.EditBox(f.officer, { width = 200, maxLetters = ns.Season.NAME_MAX, placeholder = L["SEASON_NAME_HINT"] })
	f.seasonName:SetPoint("TOPLEFT", f.officer, "TOPLEFT", 0, 0)
	f.openSeason = Widgets.Button(f.officer, { text = L["SEASON_OPEN_BUTTON"], style = "primary", height = 28, onClick = function()
		View:OpenSeason(f.seasonName:GetText())
	end })
	f.openSeason:SetPoint("LEFT", f.seasonName, "RIGHT", 8, 0)
	f.closeSeason = Widgets.Button(f.officer, { text = L["SEASON_CLOSE_BUTTON"], style = "secondary", height = 28, onClick = function()
		View:CloseSeason()
	end })
	f.closeSeason:SetPoint("LEFT", f.openSeason, "RIGHT", 8, 0)

	-- the own declaration
	f.form = CreateFrame("Frame", nil, f)
	f.form:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.form:SetHeight(72)
	label(f.form, L["SEASON_MS1"], 0, 0)
	f.ms1, f.ms1role = pair(f.form, 40, 0, false, "ms1")
	label(f.form, L["SEASON_MS2"], 270, 0)
	f.ms2, f.ms2role = pair(f.form, 310, 0, true, "ms2")
	label(f.form, L["SEASON_OS"], 540, 0)
	f.os, f.osrole = pair(f.form, 570, 0, true, "os")
	f.note = Widgets.EditBox(f.form, { width = 300, maxLetters = ns.Season.NOTE_MAX, placeholder = L["SEASON_NOTE_HINT"] })
	f.note:SetPoint("TOPLEFT", f.form, "TOPLEFT", 0, -38)
	f.unsure = Widgets.Button(f.form, { text = L["SEASON_UNSURE_BUTTON"], style = "secondary", height = 28, onClick = function() View:Save(true) end })
	f.unsure:SetPoint("LEFT", f.note, "RIGHT", 8, 0)
	f.save = Widgets.Button(f.form, { text = L["SEASON_SAVE"], style = "primary", height = 28, onClick = function() View:Save(false) end })
	f.save:SetPoint("LEFT", f.unsure, "RIGHT", 8, 0)
	f.saveNote = Widgets.Button(f.form, { text = L["SEASON_SAVE_NOTE"], style = "secondary", height = 28, onClick = function() View:SaveNote() end })
	f.saveNote:SetPoint("LEFT", f.save, "RIGHT", 8, 0)
	f.message = Widgets.Text(f, "Small", "text-3", "LEFT")

	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.list:SetClipsChildren(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	f.list.lines = {}
	f.offset = 0
	f:SetScript("OnShow", function() View:Redraw() end)
	self:Redraw()
end

function View:Say(text)
	local f = self.frame
	if f then f.message:SetText(text or "") end
	self.said = text
end

function View:SpecPicked(key)
	local f = self.frame
	if not f or self.painting then return end
	local spec = f[key]:Selected()
	local roleSel = f[key .. "role"]
	roleSel:SetChoices(View.RoleChoices(self.class, spec))
	local roles = ns.Specs.Roles(self.class, spec)
	if roles then roleSel:Select(roles[1], true) end
	self.confirming = nil
	f.save:SetLabel(L["SEASON_SAVE"])
end

function View:OpenSeason(name)
	local rec, why = ns.Season:Open(name)
	if rec then
		self.chosen = nil
		if self.frame then self.frame.seasonName:Clear() end
		self:Say(L["SEASON_OPENED"]:format(rec.name))
	else
		self:Say(View.ReasonText(why))
	end
	self:Redraw()
	return rec, why
end

function View:CloseSeason()
	local cur = ns.Season:Current()
	if not cur then return false end
	local ok, why = ns.Season:Close(cur.n)
	self:Say(ok and L["SEASON_CLOSED_DONE"]:format(cur.name) or View.ReasonText(why))
	self:Redraw()
	return ok
end

-- The form's values now.
function View:FormValues()
	local f = self.frame
	return { ms1 = f.ms1:Selected(), ms1role = f.ms1role:Selected(), ms2 = f.ms2:Selected(), ms2role = f.ms2role:Selected(),
		os = f.os:Selected(), osrole = f.osrole:Selected(), note = f.note:GetText() }
end

-- Saving needs a second click that repeats the lock (SPEC-14 §4.4).
function View:Save(unsure)
	local f = self.frame
	if not f then return nil end
	local mode = unsure and "unsure" or "declare"
	if self.confirming ~= mode then
		self.confirming = mode
		local button = unsure and f.unsure or f.save
		button:SetLabel(L["SEASON_CONFIRM"])
		self:Say(L["SEASON_CONFIRM_HINT"])
		return nil, "confirm"
	end
	self.confirming = nil
	local v = self:FormValues()
	v.unsure = unsure
	local rec, why = ns.Season:Declare(View.Declaration(v))
	self:Say(rec and L["SEASON_SAVED"] or View.ReasonText(why))
	self:Redraw()
	return rec, why
end

function View:SaveNote()
	local rec, why = ns.Season:SetNote(self.frame and self.frame.note:GetText() or "")
	self:Say(rec and L["SEASON_SAVED"] or View.ReasonText(why))
	self:Redraw()
	return rec, why
end

local function visibleRows(list)
	local h = list and list:GetHeight() or 0
	return h >= View.ROW_HEIGHT and floor(h / View.ROW_HEIGHT) or 16
end

local function fillForm(f, own, class)
	local function set(sel, roleSel, p, optional)
		sel:SetChoices(View.SpecChoices(class, optional))
		local spec = p and p.spec or (optional and View.NONE or nil)
		if spec then sel:Select(spec, true) end
		roleSel:SetChoices(View.RoleChoices(class, p and p.spec))
		if p then roleSel:Select(p.role, true) end
	end
	set(f.ms1, f.ms1role, own and own.ms1, false)
	set(f.ms2, f.ms2role, own and own.ms2, true)
	set(f.os, f.osrole, own and own.os, true)
	f.note:SetText(own and own.note or "")
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local m = View.Model(self.chosen)
	self.model = m
	self.painting = true
	f.sourceSeg:Select(m.raid)
	local choices = {}
	for _, s in ipairs(m.seasons) do
		choices[#choices + 1] = { id = tostring(s.n), text = s.closed and L["SEASON_PICK_CLOSED"]:format(s.name) or s.name }
	end
	f.picker:SetChoices(choices)
	if m.season then f.picker:Select(tostring(m.season.n), true) end
	f.sourceSeg:SetEnabled(m.canChoose)
	f.picker:SetShown(m.raid ~= "fdcp" and #choices > 0)
	f.open:SetShown(m.fdcp ~= nil and m.fdcp.level ~= nil)

	local y = -40
	local officer = m.raid ~= "fdcp" and m.canOpen
	f.officer:SetShown(officer)
	if officer then
		f.closeSeason:SetShown(m.current ~= nil)
		y = y - 40
	end
	local own = m.own
	local declare = m.raid ~= "fdcp" and m.isCurrent and m.canDeclare == true
	f.form:SetShown(declare)
	if declare then
		f.form:ClearAllPoints()
		f.form:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		f.form:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		local me = ns.Compat.Player.GUID()
		local member = me and ns.Roster and ns.Roster:ByGUID(me)
		self.class = member and member.classFile or (UnitClass and select(2, UnitClass("player"))) or nil
		local formKey = tostring(own and own.rev) .. ":" .. tostring(m.current and m.current.n)
		if self.formKey ~= formKey then
			self.formKey = formKey
			fillForm(f, own, self.class)
		end
		local locked = own ~= nil and ns.Season.IsLocked(own, m.now)
		local convertible = own ~= nil and own.unsure == true and not own.conv
		local specsOpen = not locked or convertible
		for _, k in ipairs({ "ms1", "ms1role", "ms2", "ms2role", "os", "osrole" }) do f[k]:SetEnabled(specsOpen) end
		f.save:SetEnabled(specsOpen)
		f.unsure:SetEnabled(not locked)
		f.saveNote:SetShown(own ~= nil)
		if self.confirming == nil then
			f.save:SetLabel(L["SEASON_SAVE"])
			f.unsure:SetLabel(L["SEASON_UNSURE_BUTTON"])
		end
		y = y - 76
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
	ns.Shell:RegisterView("season", { label = L["VIEW_SEASON"], order = 45, visible = on, build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.SeasonView = View
	if ns.Bus then
		local function changed() if on() then View:Changed() end end
		for _, event in ipairs({ "SEASON_CHANGED", "SOURCES_CHANGED", "INTEGRATIONS_CHANGED", "FDCP_CHANGED", "ROLE_CHANGED", "CENSUS_CHANGED" }) do
			ns.Bus:On(event, changed)
		end
	end
end

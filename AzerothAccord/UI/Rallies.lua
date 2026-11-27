-- Rallies page of the Events view: call a PvP or world rally and answer one (M10.9; SPEC-14 §9). Lua 5.1.
--
-- At the top the caller's form: PvP or World, the meeting point in words, when it starts and how long it lasts, with Call
-- a rally and, while the character has an open one, Change and Close. Below, the picker of the rallies held, Coming and
-- Not coming, and for the chosen one the meeting point, the times and who answered. UI/Events.lua builds the page in its
-- own pager. Nothing here reads the player's position.
-- View.Model(id) reads everything now; View.Lines(model) is a plain function of it (tested offline); the frames only draw.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.RalliesView, ns.modules = View, ns.modules or {}
ns.modules.RalliesView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring = type, ipairs, tostring
local floor, max, min, ceil, concat = math.floor, math.max, math.min, math.ceil, table.concat

View.ROW_HEIGHT = 20
View.WHEEL_STEP = 3
View.TICK = 30
View.NAMES_PER_LINE = 8
View.AHEADS = { 0, 900, 1800, 3600, 7200 }
View.DURATIONS = { 900, 1800, 3600, 7200 }

local function R() return ns.Rallies end
local function on() return R() ~= nil and R().Enabled() end
local function name(guid) return ns.Groups.ShortName(guid) end

function View.KindText(kind) return L["RALLY_KIND_" .. tostring(kind):upper()] end

-- "now", "15 min", "1 h"
function View.SpanText(seconds)
	if seconds <= 0 then return L["RALLY_NOW"] end
	local m = ceil(seconds / 60)
	if m < 60 then return L["GRP_MINUTES"]:format(m) end
	return L["GRP_HOURS"]:format(floor(m / 60), m % 60)
end

function View.ErrorText(why)
	return rawget(L, "RALLY_ERR_" .. tostring(why):upper()) or L["RALLY_ERR_OTHER"]:format(tostring(why))
end

-- What the state of a rally says: "starts in 12 min", "on, ends in 20 min", "ended", "closed".
function View.StateText(rec, status, t)
	if status == "soon" then return L["RALLY_STATE_SOON"]:format(View.SpanText(rec.start - t)) end
	if status == "on" then return L["RALLY_STATE_ON"]:format(View.SpanText(rec.ends - t)) end
	return L["RALLY_STATE_" .. status:upper()]
end

-- Everything the page shows, for the rally `id` (nil or gone: the first one).
function View.Model(id)
	local Rm = R()
	local m = { rallies = Rm:List(), own = Rm:Own(), now = ns.Compat.ServerTime() }
	for _, e in ipairs(m.rallies) do
		if e.rec.id == id then m.chosen = e end
	end
	m.chosen = m.chosen or m.rallies[1]
	if m.chosen then
		local rec = m.chosen.rec
		local answers = Rm:Answers(rec.id)
		m.coming, m.notComing = {}, {}
		for i, guid in ipairs(answers.yes) do m.coming[i] = name(guid) end
		for i, guid in ipairs(answers.no) do m.notComing[i] = name(guid) end
		m.mine = Rm:Mine(rec.id)
		m.isOwn = rec.author == ns.Compat.Player.GUID()
		m.canAnswer = not m.isOwn and (m.chosen.status == "soon" or m.chosen.status == "on")
	end
	return m
end

-- { { text, heading?, sub?, muted?, indent? } } under the picker.
function View.Lines(m)
	local out = {}
	local function add(text, kind)
		local l = { text = text }
		if kind then l[kind] = true end
		out[#out + 1] = l
	end
	local e = m.chosen
	if not e then
		add(L["RALLY_NONE"], "muted")
		return out
	end
	local rec = e.rec
	add(L["RALLY_ROW_" .. rec.kind:upper()]:format(rec.text), "heading")
	add(L["RALLY_BY"]:format(name(rec.author), ns.Rallies.Clock(rec.start), ns.Rallies.Clock(rec.ends)))
	add(View.StateText(rec, e.status, m.now), "sub")
	if m.isOwn then add(L["RALLY_YOURS"], "muted")
	elseif m.mine then add(L["RALLY_MINE_" .. m.mine:upper()], "muted") end
	local function names(head, list)
		add(head:format(#list), "sub")
		for i = 1, #list, View.NAMES_PER_LINE do
			local part = {}
			for j = i, min(#list, i + View.NAMES_PER_LINE - 1) do part[#part + 1] = list[j] end
			add(concat(part, ", "), "indent")
		end
	end
	names(L["RALLY_COMING_LIST"], m.coming)
	names(L["RALLY_NOT_COMING_LIST"], m.notComing)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------------
function View:Say(text)
	self.said = text
	if self.frame then self.frame.message:SetText(text or "") end
end

local function result(self, ok, why, done)
	self:Say(ok and done or View.ErrorText(why))
	self:Redraw()
	return ok, why
end

-- The values of the form; a start or a duration not chosen is nil (the default of a call, "unchanged" for a change).
function View:Values()
	local f = self.frame
	if not f then return {} end
	return { kind = self.kind, text = f.where:GetText(), ahead = self.ahead, duration = self.duration }
end

function View:Call(values)
	local rec, why = R():Call(values or self:Values())
	if rec then self.chosen, self.ahead, self.duration, self.loaded = rec.id, nil, nil, nil end
	return result(self, rec and true or false, why, L["RALLY_CALLED"])
end

function View:Change(values)
	local own = R():Own()
	if not own then return result(self, false, "missing") end
	local rec, why = R():Update(own.id, values or self:Values())
	if rec then self.chosen, self.ahead, self.duration = rec.id, nil, nil end
	return result(self, rec and true or false, why, L["RALLY_CHANGED_DONE"])
end

function View:Close()
	local own = R():Own()
	if not own then return result(self, false, "missing") end
	local ok, why = R():Close(own.id)
	return result(self, ok and true or false, why, L["RALLY_CLOSED_DONE"])
end

function View:Answer(answer)
	local m = View.Model(self.chosen)
	if not m.chosen then return result(self, false, "missing") end
	local ok, why = R():Answer(m.chosen.rec.id, answer)
	return result(self, ok, why, L["RALLY_MINE_" .. answer:upper()])
end

function View:Choose(id)
	self.chosen = id
	if self.frame then self.frame.offset = 0 end
	self:Redraw()
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local function visibleRows(list)
	local h = list and list:GetHeight() or 0
	return h >= View.ROW_HEIGHT and floor(h / View.ROW_HEIGHT) or 10
end

local function opened(f)
	if not f.ticker then
		if ns.Roster then ns.Roster:Watch() end
		f.ticker = ns.Compat.NewTicker(View.TICK, function() View:Redraw() end) or true
	end
	R():Ask(true)   -- the rallies called while this client was away, with their answers
	View:Redraw()
end

local function closed(f)
	if not f.ticker then return end
	if ns.Roster then ns.Roster:Unwatch() end
	if type(f.ticker) == "table" then f.ticker:Cancel() end
	f.ticker = nil
end

function View:Build(f)
	self.frame = f
	self.kind = self.kind or R().KINDS[1]
	local function label(key, y)
		local fs = Widgets.Text(f, "Small", "text-3", "LEFT")
		fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y - 8)
		fs:SetText(L[key])
		return fs
	end
	local function spans(list, onSelect, y)
		local items = {}
		for i, s in ipairs(list) do items[i] = { id = s, text = View.SpanText(s) } end
		local seg = Widgets.Segmented(f, items, onSelect)
		seg:SetPoint("TOPLEFT", f, "TOPLEFT", 90, y)
		return seg
	end
	f.kind = Widgets.Segmented(f, { { id = "pvp", text = View.KindText("pvp") }, { id = "world", text = View.KindText("world") } },
		function(id) View.kind = id end)
	f.kind:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.kind:Select(self.kind)
	f.where = Widgets.EditBox(f, { width = 360, dense = true, maxLetters = R().MAX_TEXT, placeholder = L["RALLY_WHERE_HINT"] })
	f.where:SetPoint("LEFT", f.kind, "RIGHT", 8, 0)
	label("RALLY_FIELD_START", -44)
	f.ahead = spans(View.AHEADS, function(s) View.ahead = s end, -44)
	label("RALLY_FIELD_DURATION", -84)
	f.duration = spans(View.DURATIONS, function(s) View.duration = s end, -84)
	f.call = Widgets.Button(f, { text = L["RALLY_CALL"], style = "filled", dense = true, onClick = function() View:Call() end })
	f.call:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -124)
	f.change = Widgets.Button(f, { text = L["RALLY_CHANGE"], style = "tonal", dense = true, onClick = function() View:Change() end })
	f.change:SetPoint("LEFT", f.call, "RIGHT", 8, 0)
	f.close = Widgets.Button(f, { text = L["RALLY_CLOSE"], style = "outlined", dense = true, onClick = function() View:Close() end })
	f.close:SetPoint("LEFT", f.change, "RIGHT", 8, 0)
	f.message = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.message:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -168)
	f.message:SetPoint("RIGHT", f, "RIGHT", 0, 0)

	f.picker = Widgets.Select(f, { width = 360, rows = 8, onSelect = function(id)
		if View.painting then return end
		View:Choose(id)
	end })
	f.picker:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -190)
	f.yes = Widgets.Button(f, { text = L["RALLY_COMING"], style = "tonal", dense = true, onClick = function() View:Answer("yes") end })
	f.yes:SetPoint("LEFT", f.picker, "RIGHT", 8, 0)
	f.no = Widgets.Button(f, { text = L["RALLY_NOT_COMING"], style = "outlined", dense = true, onClick = function() View:Answer("no") end })
	f.no:SetPoint("LEFT", f.yes, "RIGHT", 8, 0)

	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -232)
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.list:SetClipsChildren(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	f.list.lines = {}
	f.offset = 0
	f:SetScript("OnShow", function() opened(f) end)
	f:SetScript("OnHide", function() closed(f) end)
	opened(f)   -- the shell builds the page on screen: no OnShow comes first
end

-- The form follows the character's open rally the first time it shows, and again when that rally changes.
local function fill(f, own)
	local id = own and own.id or "none"
	if View.loaded == id then return end
	View.loaded = id
	if own then
		View.kind = own.kind
		f.kind:Select(own.kind)
		f.where:SetText(own.text)
	end
	View.ahead, View.duration = nil, nil
	f.ahead:Clear()
	f.duration:Clear()
	if not own then   -- a new call shows what it will be; a change leaves the times as they are unless chosen
		f.ahead:Select(R().AHEAD)
		f.duration:Select(R().DURATION)
	end
end

function View:Redraw()
	local f = self.frame
	if not (f and on()) then return end
	local m = View.Model(self.chosen)
	self.model = m
	self.painting = true
	fill(f, m.own)
	local choices = {}
	for i, e in ipairs(m.rallies) do
		choices[i] = { id = e.rec.id, text = ns.Rallies.Clock(e.rec.start) .. "  " .. View.KindText(e.rec.kind) .. "  " .. e.rec.text }
	end
	f.picker:SetChoices(choices)
	f.picker:SetShown(#choices > 0)
	if m.chosen then f.picker:Select(m.chosen.rec.id, true) end
	self.painting = false
	f.yes:SetShown(m.canAnswer == true)
	f.no:SetShown(m.canAnswer == true)
	f.change:SetShown(m.own ~= nil)
	f.close:SetShown(m.own ~= nil)
	f.message:SetText(self.said or "")

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
		fs:SetPoint("TOPLEFT", list, "TOPLEFT", l.indent and 12 or 0, -(i - 1) * View.ROW_HEIGHT)
		fs:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		fs:SetText(l.text)
		fs:SetFontObject(Theme.Font(l.heading and "H2" or l.sub and "BodyMedium" or "Body"))
		if l.heading then Theme.Text(fs, "text-1")
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

-- Opens the Rallies page (the Groups destination since M13.7), with rally `id` chosen (the notice, the row of the
-- Action Center).
function View:Open(id)
	if not on() then return false end
	if id then self.chosen = id end
	if not (ns.Shell and ns.Shell:OpenView("rallies")) then return false end
	if self.frame and self.frame:IsVisible() then self:Redraw() end
	return true
end

function View:Changed()
	if self.frame and self.frame:IsVisible() then self:Redraw() end
end

if ns.Shell then
	ns.Shell:RegisterView("rallies", { label = L["EVENTS_PAGE_RALLIES"], order = 48, dest = "groups", visible = on,
		build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.RalliesView = View
	if ns.Bus then
		local function changed() if on() then View:Changed() end end
		ns.Bus:On("RALLY_CHANGED", changed)
		ns.Bus:On("ROSTER_UPDATED", changed)
		ns.Bus:On("GUILD_CHANGED", function()
			View.chosen, View.said, View.loaded = nil, nil, nil
		end)
	end
end

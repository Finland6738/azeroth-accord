-- TrialsView: the "Trials" page of the Officers tab, the dialogs of a trial and the "Trial" section of the member card
-- (M12.3; SPEC-16 §4.5). Lua 5.1.
-- A third tab of the page shows the mentors suggested to the new members (M12.5, UI/Mentors.lua).
-- Only the officers and the Guild Master see any of it (Trials.CanSee), and only with the switch "recruit". Nothing on
-- these frames changes the game (RC-02): Passed may add a promotion to the officer's own queue of manual actions (M8.4).
--   View.RowText(row, column, t)   the text of a cell of the page (plain, tested offline)
--   View.InfoText(rec)             "From 2026-11-01 to 2026-11-15 (14 days)"
--   View:Open(id)                  the Officers tab on the Trials page and the dialog of trial `id`
--   View:OpenStart(guid)           the dialog that starts a trial (guid: the member chosen, optional)
--   View:Begin(guid, days, start)  starts it from the dialog's values (or these); the dialog closes when it started
--   View:Press(action)             "extend" | "passed" | "failed" | "cancelled" in the dialog of a trial: the first click of a
--                                  closing asks, the second one (Confirm) closes; returns "armed", true or false and a reason
--   View:OpenNote(id)              the own note about a trial, in the dialog of the extended notes (UI/OfficerNotes.lua)
--   View.CardSection(entry)        the section "Trial" of the member card
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.TrialsView, ns.modules = View, ns.modules or {}
ns.modules.TrialsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, tonumber = type, ipairs, pairs, tostring, tonumber

View.WIDTH, View.HEIGHT = 520, 470
View.START_WIDTH, View.START_HEIGHT = 420, 330
View.tab = "open"

local function T() return ns.Trials end
local function now() return ns.Compat.ServerTime() end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end

local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-3")
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function View.RankName(index)
	for _, rank in ipairs(ns.Compat.Guild.Ranks()) do
		if rank.index == index then return escape(rank.name) end
	end
	return tostring(index)
end

function View.StateText(state) return L["TRI_ST_" .. tostring(state):upper()] end

function View.InfoText(rec)
	local Tr = T()
	local span = (Tr.Number(rec.ends) or 0) - (Tr.Number(rec.start) or 0)
	if span ~= rec.days then
		return L["TRI_INFO_EXTENDED"]:format(Tr.DayText(rec.start), Tr.DayText(rec.ends), span, rec.days)
	end
	return L["TRI_INFO"]:format(Tr.DayText(rec.start), Tr.DayText(rec.ends), span)
end

-- How long is left: "5 days", "Ends today", "Ended", or "Left the guild".
function View.LeftText(row)
	if row.left then return L["TRI_LEFT_GUILD"] end
	local n = row.daysLeft or 0
	if n < 0 then return L["TRI_OVERDUE"] end
	if n == 0 then return L["TRI_ENDS_TODAY"] end
	if n == 1 then return L["TRI_DAYS_LEFT_ONE"] end
	return L["TRI_DAYS_LEFT"]:format(n)
end

function View.RowText(row, column)
	local Tr, rec = T(), row.rec
	if column == "name" then
		local name = escape(row.name)
		if (row.others or 0) > 0 then name = name .. " (" .. L["TRI_MORE_OPEN"]:format(row.others + 1) .. ")" end
		return name
	end
	if column == "rank" then return escape(row.rank or "") end
	if column == "start" then return Tr.DayText(rec.start) end
	if column == "ends" then return Tr.DayText(rec.ends) end
	if column == "left" then return View.LeftText(row) end
	if column == "notes" then return tostring(row.notes or 0) end
	if column == "closed" then return Tr.DayText(rec.closed) end
	if column == "state" then return View.StateText(rec.state) end
	return ""
end

---------------------------------------------------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------------------------------------------------
local function columns(tab)
	local function col(id, key, opts)
		opts.id, opts.title, opts.sortable = id, L[key], false
		opts.text = function(r) return View.RowText(r, id) end
		return opts
	end
	if tab == "closed" then
		return { col("name", "COL_TRI_NAME", { flex = 2 }), col("start", "COL_TRI_START", { flex = 1, mono = true }),
			col("closed", "COL_TRI_CLOSED", { flex = 1, mono = true }), col("state", "COL_TRI_STATE", { flex = 1 }),
			col("notes", "COL_TRI_NOTES", { width = 60 }) }
	end
	return { col("name", "COL_TRI_NAME", { flex = 2 }), col("rank", "COL_TRI_RANK", { flex = 1 }),
		col("start", "COL_TRI_START", { flex = 1, mono = true }), col("ends", "COL_TRI_ENDS", { flex = 1, mono = true }),
		col("left", "COL_TRI_LEFT", { flex = 1 }), col("notes", "COL_TRI_NOTES", { width = 60 }) }
end

local function buildPage(f, officers)
	f.help = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.help:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.help:SetPoint("RIGHT", f, "RIGHT", -140, 0)
	f.help:SetWordWrap(true)
	f.help:SetText(L["TRI_HELP"])
	f.start = Widgets.Button(f, { text = L["TRI_START"], style = "primary", height = 26, onClick = function() View:OpenStart() end })
	f.start:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.tabs = Widgets.ChipRow(f, function(id)
		View.tab = id
		officers:Redraw()
	end, { height = 26, gap = 6 })
	f.tabs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -officers.FILTER_HEIGHT)
	f.tabs:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.shownTab = View.tab
	f.table = Widgets.DataTable(f, columns(View.tab), { emptyText = L["TRI_EMPTY_OPEN"],
		onRowClick = function(row) View:Open(row.id) end })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 * officers.FILTER_HEIGHT)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
	f.count = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
	if ns.MentorsView then
		f.pairs = ns.MentorsView.BuildPairs(f)
		f.pairs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 * officers.FILTER_HEIGHT)
		f.pairs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
		f.pairs:Hide()
	end
end

-- The rows the page shows now, with the search of the panel.
function View.PageRows(tab, search, t)
	local all = T():Rows(t)
	local needle = search and search ~= "" and search:lower() or nil
	local out = {}
	for _, row in ipairs(all[tab == "closed" and "closed" or "open"]) do
		if not needle or tostring(row.name):lower():find(needle, 1, true) then out[#out + 1] = row end
	end
	return out, all
end

local function refreshPage(f, officers)
	local mentors = f.pairs ~= nil and ns.Mentors.CanSeePairs()
	if View.tab == "mentors" and not mentors then View.tab = "open" end
	local tabs = { { id = "open", text = L["TRI_TAB_OPEN"] }, { id = "closed", text = L["TRI_TAB_CLOSED"] } }
	if mentors then tabs[3] = { id = "mentors", text = L["TRI_TAB_MENTORS"] } end
	f.tabs:SetItems(tabs, View.tab)
	local onPairs = View.tab == "mentors"
	f.table:SetShown(not onPairs)
	if f.pairs then f.pairs:SetShown(onPairs) end
	if onPairs then
		View.rows = {}
		f.count:SetText(L["MEN_PAIRS_COUNT"]:format(ns.MentorsView.RefreshPairs(f.pairs, officers.search)))
		return
	end
	if f.shownTab ~= View.tab then
		f.shownTab = View.tab
		f.table:SetColumns(columns(View.tab))
	end
	f.table:SetEmptyText(L[View.tab == "closed" and "TRI_EMPTY_CLOSED" or "TRI_EMPTY_OPEN"])
	local rows, all = View.PageRows(View.tab, officers.search)
	View.rows = rows
	f.table:SetData(rows, true)
	f.count:SetText(L["TRI_COUNT"]:format(#all.open, #all.closed))
end

if ns.OfficersView then
	ns.OfficersView.AddPage("trials", { label = L["OFF_PAGE_TRIALS"], order = 40, build = buildPage, refresh = refreshPage,
		visible = function() return T() ~= nil and T().CanSee() end })
end

---------------------------------------------------------------------------------------------------------------------
-- The dialog that starts a trial
---------------------------------------------------------------------------------------------------------------------
local function members()
	local out = {}
	for _, e in ipairs(ns.Roster and ns.Roster:Members() or {}) do
		if e.guid then out[#out + 1] = { id = e.guid, text = escape(e.short or e.name) } end
	end
	table.sort(out, function(a, b) return a.text:lower() < b.text:lower() end)
	return out
end

local function buildStart()
	local w = View.START_WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordTrialStartDialog", { width = w, height = View.START_HEIGHT })
	local card = d.card
	d.title = Widgets.Text(card, "H2", "text-1", "LEFT")
	d.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -22)
	d.title:SetText(L["TRI_START_TITLE"])
	d.member = Widgets.Select(card, { width = w - 48, rows = 8, placeholder = L["TRI_MEMBER"] })
	d.member:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -18)
	d.lengthLabel = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.lengthLabel:SetPoint("TOPLEFT", d.member, "BOTTOMLEFT", 0, -16)
	d.lengthLabel:SetText(L["TRI_LENGTH"])
	d.length = Widgets.EditBox(card, { width = 120, height = 28, maxLetters = 3 })
	d.length:SetPoint("TOPLEFT", d.lengthLabel, "BOTTOMLEFT", 0, -6)
	d.fromLabel = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.fromLabel:SetPoint("TOPLEFT", d.length, "BOTTOMLEFT", 0, -12)
	d.fromLabel:SetText(L["TRI_FROM"])
	d.from = Widgets.EditBox(card, { width = 160, height = 28, maxLetters = 10 })
	d.from:SetPoint("TOPLEFT", d.fromLabel, "BOTTOMLEFT", 0, -6)
	d.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.status:SetPoint("TOPLEFT", d.from, "BOTTOMLEFT", 0, -10)
	d.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.ok = Widgets.Button(card, { text = L["TRI_START_OK"], style = "primary", onClick = function() View:Begin() end })
	d.ok:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "ghost", onClick = function() d:Close() end })
	d.close:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 20)
	return d
end

function View:OpenStart(guid)
	local Tr = T()
	if not (Tr and Tr.CanSee() and ns.Role and ns.Role:IsOfficer()) then return nil end
	if not self.startDialog then self.startDialog = buildStart() end
	local d = self.startDialog
	d.member:SetChoices(members())
	if guid then d.member:Select(guid, true) end
	d.length:SetText(tostring(Tr.DEFAULT_DAYS))
	d.from:SetText(Tr.DayText(Tr.Today()))
	say(d.status, ns.Officer.ChannelProven() and "" or L["TL_LOCAL_ONLY"])
	d:Open()
	return d
end

function View:Begin(guid, days, start)
	local d = self.startDialog
	if d then
		guid = guid or d.member:Selected()
		days = days or tonumber(d.length:GetText()) or -1
		if start == nil then
			start = T().ParseDay(d.from:GetText())
			if not start then say(d.status, T().ErrorText("start"), "err") return false, "start" end
		end
	end
	local rec, why = T():Start(guid, days, start)
	if not rec then
		if d then say(d.status, T().ErrorText(why), "err") end
		return false, why
	end
	if d then d:Close() end
	return true, rec
end

---------------------------------------------------------------------------------------------------------------------
-- The dialog of a trial
---------------------------------------------------------------------------------------------------------------------
local function buildTrial()
	local w, h = View.WIDTH, View.HEIGHT
	local d = Widgets.Dialog(UIParent, "AzerothAccordTrialDialog", { width = w, height = h })
	local card = d.card
	d.title = Widgets.Text(card, "H2", "text-1", "LEFT")
	d.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -22)
	d.title:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.info = Widgets.Text(card, "Body", "text-2", "LEFT")
	d.info:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -8)
	d.info:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.info:SetWordWrap(true)
	d.notesTitle = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.notesTitle:SetPoint("TOPLEFT", d.info, "BOTTOMLEFT", 0, -14)
	d.notesTitle:SetText(L["TRI_NOTES"])
	d.notes = Widgets.Text(card, "Body", "text-1", "LEFT")
	d.notes:SetPoint("TOPLEFT", d.notesTitle, "BOTTOMLEFT", 0, -6)
	d.notes:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.notes:SetPoint("BOTTOM", card, "BOTTOM", 0, 170)
	d.notes:SetWordWrap(true)
	d.notes:SetJustifyV("TOP")
	d.note = Widgets.Button(card, { text = L["TRI_NOTE_WRITE"], style = "secondary", height = 26,
		onClick = function() View:OpenNote(d.id) end })
	d.note:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 132)
	d.more = Widgets.EditBox(card, { width = 80, height = 26, maxLetters = 3, placeholder = L["TRI_EXTEND_HINT"],
		onEnter = function() View:Press("extend") end })
	d.more:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -112, 132)
	d.extend = Widgets.Button(card, { text = L["TRI_EXTEND"], style = "secondary", height = 26, width = 80,
		onClick = function() View:Press("extend") end })
	d.extend:SetPoint("LEFT", d.more, "RIGHT", 8, 0)
	d.promote = Widgets.Switch(card, {})
	d.promote:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 96)
	d.promoteText = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.promoteText:SetPoint("LEFT", d.promote, "RIGHT", 8, 0)
	d.promoteText:SetText(L["TRI_PROMOTE"])
	d.passed = Widgets.Button(card, { text = L["TRI_PASSED"], style = "primary", onClick = function() View:Press("passed") end })
	d.passed:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
	d.failed = Widgets.Button(card, { text = L["TRI_FAILED"], style = "secondary", onClick = function() View:Press("failed") end })
	d.failed:SetPoint("RIGHT", d.passed, "LEFT", -8, 0)
	d.cancel = Widgets.Button(card, { text = L["TRI_CANCEL"], style = "secondary", onClick = function() View:Press("cancelled") end })
	d.cancel:SetPoint("RIGHT", d.failed, "LEFT", -8, 0)
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "ghost", onClick = function() d:Close() end })
	d.close:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 20)
	d.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.status:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 64)
	d.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.status:SetWordWrap(true)
	return d
end

local BUTTONS = { passed = { "passed", "TRI_PASSED" }, failed = { "failed", "TRI_FAILED" }, cancelled = { "cancel", "TRI_CANCEL" } }

-- The notes of a trial as text: "Name: text" per note, | doubled (ONT-02).
function View.NotesText(id)
	local lines = {}
	for _, rec in ipairs(T():Notes(id)) do
		local who = rec.author == ns.Compat.Player.GUID() and L["ONT_BY_YOU"] or ns.Provenance.AuthorName(rec.author)
		lines[#lines + 1] = L["TRI_NOTE_LINE"]:format(escape(who), escape(rec.text)) .. " (" .. ns.Provenance.AgeText(now()
			- (rec.time or 0)) .. ")"
	end
	if #lines == 0 then return L["TRI_NO_NOTES"] end
	return table.concat(lines, "\n")
end

-- Fills the dialog from the record held now.
function View:Fill(keepStatus)
	local d = self.dialog
	local rec = d and d.id and T():Get(d.id)
	if not rec then return false end
	local name = T().NameOf(rec.char)
	d.title:SetText(L["TRI_DIALOG_TITLE"]:format(escape(name)))
	local info = View.InfoText(rec)
	if rec.state ~= "open" then
		info = info .. "\n" .. L["TRI_CLOSED_ON"]:format(View.StateText(rec.state), T().DayText(rec.closed))
	end
	d.info:SetText(info)
	d.notes:SetText(View.NotesText(rec.id))
	d.note:SetLabel(L[T():Note(rec.id) and "TRI_NOTE_EDIT" or "TRI_NOTE_WRITE"])
	local open = rec.state == "open"
	for action, b in pairs(BUTTONS) do
		local button = d[b[1]]
		button:SetShown(open)
		button:SetLabel(L[d.armed == action and "TRI_CONFIRM" or b[2]])
	end
	d.more:SetShown(open)
	d.extend:SetShown(open)
	d.promote:SetShown(open)
	d.promoteText:SetShown(open)
	if not keepStatus then
		say(d.status, ns.Officer.ChannelProven() and "" or L["TL_LOCAL_ONLY"])
	end
	return true
end

function View:OpenDialog(id)
	local Tr = T()
	if not (Tr and Tr.CanSee() and Tr:Get(id)) then return nil end
	if not self.dialog then self.dialog = buildTrial() end
	local d = self.dialog
	d.id, d.armed = id, nil
	d.more:SetText("")
	d.promote:SetOn(false, true)   -- off by default (SPEC-16 §4.5)
	self:Fill()
	d:Open()
	return d
end

-- The Officers tab on the Trials page, and the dialog of the trial.
function View:Open(id)
	local O = ns.OfficersView
	if O then O:OpenPage("trials") end
	if id then return self:OpenDialog(id) end
	return nil
end

local PROMOTE_WHY = { gone = "TRI_PROMOTE_GONE", rank = "TRI_PROMOTE_RANK", full = "TRI_PROMOTE_FULL" }

function View:Press(action)
	local d = self.dialog
	if not (d and d.id) then return false, "unknown" end
	if action == "extend" then
		local rec, why = T():Extend(d.id, tonumber(d.more:GetText()))
		if not rec then say(d.status, T().ErrorText(why), "err") return false, why end
		d.more:SetText("")
		d.armed = nil
		self:Fill()
		return true
	end
	if not BUTTONS[action] then return false, "state" end
	if d.armed ~= action then   -- the first click asks (Confirm)
		d.armed = action
		self:Fill(true)
		say(d.status, L["TRI_ASK"], "warn")
		return "armed"
	end
	d.armed = nil
	local promote = action == "passed" and d.promote:IsOn()
	local rec, extra = T():Close(d.id, action, promote)
	if not rec then
		self:Fill(true)
		say(d.status, T().ErrorText(extra), "err")
		return false, extra
	end
	self:Fill()
	if promote then
		if type(extra) == "table" then
			say(d.status, L["TRI_PROMOTE_ADDED"]:format(View.RankName(extra.toRank)), "text-2")
		else
			say(d.status, L[PROMOTE_WHY[extra] or "TRI_PROMOTE_FULL"], "warn")
		end
	end
	return true, extra
end

function View:OpenNote(id)
	local Tr = T()
	local rec = id and Tr:Get(id)
	if not (rec and ns.OfficerNotesView) then return nil end
	local name = Tr.NameOf(rec.char)
	return ns.OfficerNotesView:Open(rec.char, name, { title = L["TRI_NOTE_DIALOG"]:format(escape(name)),
		get = function() return Tr:Note(id) end, set = function(text) return Tr:SetNote(id, text) end,
		delete = function() return Tr:DeleteNote(id) end })
end

---------------------------------------------------------------------------------------------------------------------
-- The member card (officers only)
---------------------------------------------------------------------------------------------------------------------
function View.CardSection(e)
	local Tr = T()
	if not (Tr and Tr.CanSee()) or type(e) ~= "table" or type(e.guid) ~= "string" then return nil end
	local lines = {}
	local list = Tr:Of(e.guid)
	local rec = list[1]
	if rec and rec.state == "open" then
		local today = Tr.Number(Tr.Today()) or 0
		local row = { daysLeft = (Tr.Number(rec.ends) or today) - today }
		lines[#lines + 1] = { text = L["TRI_CARD_OPEN"]:format(Tr.DayText(rec.ends), View.LeftText(row)) }
	elseif rec then
		lines[#lines + 1] = { text = L["TRI_CARD_LAST"]:format(L["TRI_CLOSED_ON"]:format(View.StateText(rec.state),
			Tr.DayText(rec.closed))) }
	else
		lines[#lines + 1] = { text = L["TRI_CARD_NONE"], muted = true }
	end
	if rec then
		lines[#lines + 1] = { text = View.InfoText(rec), muted = true }
		for _, n in ipairs(Tr:Notes(rec.id)) do
			local who = n.author == ns.Compat.Player.GUID() and L["ONT_BY_YOU"] or ns.Provenance.AuthorName(n.author)
			lines[#lines + 1] = { text = L["TRI_NOTE_LINE"]:format(escape(who), escape(n.text)),
				prov = { source = n.author == ns.Compat.Player.GUID() and "own" or "shared", observedAt = n.time, author = n.author } }
		end
	end
	if ns.Role and ns.Role:IsOfficer() then
		if rec then
			local id = rec.id
			lines[#lines + 1] = { text = L["TRI_CARD_SHOW"], action = true, onClick = function() View:Open(id) end }
		end
		if not (rec and rec.state == "open") and ns.Roster and ns.Roster:ByGUID(e.guid) then
			local guid = e.guid
			lines[#lines + 1] = { text = L["TRI_CARD_START"], action = true, onClick = function() View:OpenStart(guid) end }
		end
	end
	return { id = "trial", title = L["TRI_CARD_TITLE"], lines = lines }
end

if ns.MemberCard then ns.MemberCard.AddSection("trial", 7.45, View.CardSection) end

if ns.addon then
	ns.addon.TrialsView = View
	if ns.Bus then
		ns.Bus:On("TRIALS_CHANGED", function()
			if ns.MemberCard then ns.MemberCard:Refresh() end
			if ns.OfficersView then ns.OfficersView:Changed() end
			if View.dialog and View.dialog:IsShown() then View:Fill(true) end
		end)
		local function close()
			for _, d in ipairs({ View.dialog, View.startDialog }) do if d then d:Close() end end
		end
		ns.Bus:On("ROLE_CHANGED", function() if not (T() and T().CanSee()) then close() end end)
		ns.Bus:On("GUILD_CHANGED", close)
		ns.Bus:On("OFFICER_PURGED", close)
	end
end

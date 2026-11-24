-- OfficersOps: the "Queue" page of the Officers tab, the dialog of one entry and the cleanup review (SPEC-12 §4, M8.4).
-- Lua 5.1.
--
-- Nothing on these frames changes the roster (OPS-01): the review fills the queue (Data/OfficerOps.lua), the dialog of an
-- entry shows what to type or paste in the game, and the roster ticks it.
--   View.OpText(entry)               "Demote to Initiate", "Change the officer note"
--   View.QueueText(entry, column)    the text of a cell of the Queue page (plain, tested offline)
--   View:OpenEntry(n)                what to do by hand for one entry
--   View:OpenReview()                the review: step 1 (which accounts), 2 (one choice per account), 3 (summary)
--   View:ReviewStep(step)            moves between the steps; View:ApplyReview() adds the actions to the queue
--   View:SelectAccount(key), View:SelectTarget(guid), View:SetAction(op), View:SetRank(index), View:SetNote(kind, text)
local ADDON_NAME, ns = ...
ns = ns or {}
local View = ns.OfficersView

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, pairs, tostring = ipairs, pairs, tostring
local concat, sort = table.concat, table.sort

View.reviewFilter = { minTier = ns.OfficerOps.DEFAULT_TIER, reviewed = false, unknown = false }
View.REVIEW_WIDTH, View.REVIEW_HEIGHT = 780, 580
View.ENTRY_WIDTH = 460

local ACTION_KEYS = { keep = "OPS_KEEP", remove = "OPS_REMOVE", demote = "OPS_DEMOTE", promote = "OPS_PROMOTE", note = "OPS_NOTE" }
local STATUS_KEYS = { open = "OPS_ST_OPEN", done = "OPS_ST_DONE", gone = "OPS_ST_GONE", expired = "OPS_ST_EXPIRED",
	cancelled = "OPS_ST_CANCELLED" }
local WHY_KEYS = { gone = "OPS_WHY_GONE", permission = "OPS_WHY_PERMISSION", rank = "OPS_WHY_RANK", same = "OPS_WHY_SAME",
	long = "OPS_WHY_LONG" }

local function now() return ns.Compat.ServerTime() end
local function ops() return ns.OfficerOps end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text):gsub("|", "||")) end

local function rankName(index)
	for _, rank in ipairs(ns.Compat.Guild.Ranks()) do
		if rank.index == index then return escape(rank.name) end
	end
	return tostring(index)
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function View.OpText(e)
	if e.op == "remove" then return L["OPS_REMOVE"] end
	if e.op == "promote" then return L["OPS_PROMOTE_TO"]:format(rankName(e.toRank)) end
	if e.op == "demote" then return L["OPS_DEMOTE_TO"]:format(rankName(e.toRank)) end
	if e.noteKind == "officer" then return L["OPS_NOTE_OFFICER"] end
	return L["OPS_NOTE_PUBLIC"]
end

function View.QueueText(e, column, t)
	if column == "name" then return escape(e.name) end
	if column == "op" then return View.OpText(e) end
	if column == "hand" then
		if e.op == "note" and e.text == "" then return L["OPS_NOTE_EMPTY"] end
		return escape(ops().Command(e))
	end
	if column == "added" then return ns.Provenance.AgeText((t or now()) - e.created) end
	if column == "status" then return L[STATUS_KEYS[e.status]] end
	return ""
end

-- The text of a choice: of an account's draft, or of one character.
function View.ChoiceText(choice)
	local op = choice.action or "keep"
	if (op == "promote" or op == "demote") and choice.rank then
		return L[op == "promote" and "OPS_PROMOTE_TO" or "OPS_DEMOTE_TO"]:format(rankName(choice.rank))
	end
	if op == "note" then return L[choice.noteKind == "officer" and "OPS_NOTE_OFFICER" or "OPS_NOTE_PUBLIC"] end
	return L[ACTION_KEYS[op]]
end

function View.DraftText(draft)
	local n = 0
	for _ in pairs(draft.per) do n = n + 1 end
	local text = View.ChoiceText(draft)
	if n > 0 then text = text .. " " .. L["OPS_DIFFER"]:format(n) end
	return text
end

---------------------------------------------------------------------------------------------------------------------
-- The Queue page
---------------------------------------------------------------------------------------------------------------------
local function column(id, key, opts, text, token)
	opts.id, opts.title, opts.sortable, opts.text, opts.token = id, L[key], false, text, token
	return opts
end

local function queueColumns()
	local function col(id, key, opts)
		return column(id, key, opts, function(e) return View.QueueText(e, id) end,
			function(e) return e.status ~= "open" and "text-3" or nil end)
	end
	return {
		col("name", "COL_OPS_NAME", { flex = 1.5 }),
		col("op", "COL_OPS_ACTION", { flex = 1.5 }),
		col("hand", "COL_OPS_HAND", { flex = 2 }),
		col("added", "COL_OPS_ADDED", { flex = 1 }),
		col("status", "COL_OPS_STATUS", { width = 90 }),
	}
end

local function buildQueue(f, self)
	f.help = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.help:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.help:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.help:SetWordWrap(true)
	f.help:SetText(L["OPS_QUEUE_HELP"])
	f.table = Widgets.DataTable(f, queueColumns(), { emptyText = L["OPS_QUEUE_EMPTY"],
		onRowClick = function(e) self:OpenEntry(e.n) end })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.FILTER_HEIGHT)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
	f.count = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
end

local function refreshQueue(f, self)
	local needle = self.search ~= "" and self.search:lower() or nil
	local rows, open = {}, 0
	for _, e in ipairs(ops():Entries()) do
		if not needle or e.name:lower():find(needle, 1, true) then
			rows[#rows + 1] = e
			if e.status == "open" then open = open + 1 end
		end
	end
	self.queueRows = rows
	f.table:SetData(rows, true)
	f.count:SetText(L["OPS_QUEUE_COUNT"]:format(open, #rows - open))
end

View.AddPage("queue", { label = L["OFF_PAGE_QUEUE"], order = 20, build = buildQueue, refresh = refreshQueue })

---------------------------------------------------------------------------------------------------------------------
-- Dialog helpers
---------------------------------------------------------------------------------------------------------------------
-- A field whose text is selected and cannot be changed: the player copies it with Ctrl+C.
local function copyField(card, width)
	local field = Widgets.EditBox(card, { width = width, height = 32, maxLetters = 128 })
	local edit = field.edit
	edit:HookScript("OnTextChanged", function(self, user)
		if user and self:GetText() ~= field.value then
			self:SetText(field.value or "")
			self:HighlightText()
		end
	end)
	edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
	function field:Put(value)
		self.value = value
		self:SetText(value)
		self.edit:SetCursorPosition(0)
	end
	return field
end

local function label(card, font, token, x, y, width)
	local fs = Theme.NewText(card, font, token)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
	fs:SetWidth(width)
	return fs
end

---------------------------------------------------------------------------------------------------------------------
-- One entry
---------------------------------------------------------------------------------------------------------------------
local function buildEntryDialog()
	local w = View.ENTRY_WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordOpsEntryDialog", { width = w, height = 330 })
	local card = d.card
	d.title = label(card, "H2", "text-1", 24, 22, w - 48)
	d.nameLabel = label(card, "Eyebrow", "text-3", 24, 58, w - 48)
	d.nameLabel:SetText(L["OPS_ENTRY_NAME"])
	d.name = copyField(card, w - 48)
	d.name:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -76)
	d.handLabel = label(card, "Eyebrow", "text-3", 24, 120, w - 48)
	d.hand = copyField(card, w - 48)
	d.hand:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -138)
	d.text = label(card, "Small", "text-3", 24, 182, w - 48)
	d.guildWindow = Widgets.Button(card, { text = L["OPS_OPEN_GUILD"], style = "secondary", onClick = function()
		if not ns.Compat.Guild.ToggleWindow() then d.text:SetText(L["OPS_OPEN_GUILD_NO"]) end
	end })
	d.guildWindow:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 62)
	d.done = Widgets.Button(card, { text = L["OPS_MARK_DONE"], style = "primary", onClick = function()
		if ops():MarkDone(d.n) then d:Close() end
	end })
	d.done:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 62)
	d.cancel = Widgets.Button(card, { text = L["OPS_CANCEL_ENTRY"], style = "secondary", onClick = function()
		if ops():Cancel(d.n) then d:Close() end
	end })
	d.cancel:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "ghost", onClick = function() d:Close() end })
	d.close:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 20)
	return d
end

function View:OpenEntry(n)
	local e = ops():Get(n)
	if not e then return nil end
	if not self.entryDialog then self.entryDialog = buildEntryDialog() end
	local d = self.entryDialog
	d.n = n
	d.title:SetText(View.OpText(e) .. ": " .. escape(e.name))
	d.name:Put(e.name)
	local note = e.op == "note"
	d.handLabel:SetText(L[note and "OPS_ENTRY_TEXT" or "OPS_ENTRY_COMMAND"])
	d.hand:Put(ops().Command(e))
	local open = e.status == "open"
	if open then d.text:SetText(L[note and "OPS_ENTRY_HELP_NOTE" or "OPS_ENTRY_HELP_COMMAND"])
	else d.text:SetText(View.QueueText(e, "status")) end
	d.cancel:SetShown(open)
	d.done:SetShown(ops():CanMarkDone(e))
	d:Open()
	return d
end

---------------------------------------------------------------------------------------------------------------------
-- The review: state and rows
---------------------------------------------------------------------------------------------------------------------
local function draftList(r)
	local out = {}
	for _, group in ipairs(r.proposal.groups) do
		for _, a in ipairs(group.accounts) do out[#out + 1] = r.drafts[a.key] end
	end
	return out
end

-- Takes the accounts of the filter again; the choices already made for an account stay.
local function propose(r)
	r.proposal = ops():Proposal(View.reviewFilter)
	local old = r.drafts or {}
	r.drafts = {}
	for _, group in ipairs(r.proposal.groups) do
		for _, a in ipairs(group.accounts) do
			local draft = old[a.key] or ops():Draft(a)
			draft.account = a
			r.drafts[a.key] = draft
		end
	end
	if not (r.selected and r.drafts[r.selected]) then
		local first = r.proposal.groups[1]
		r.selected, r.target = first and first.accounts[1].key or nil, nil
	end
end

-- The rows of step 2: a header per tier, then its accounts.
function View.ReviewRows(r)
	local out = {}
	for _, group in ipairs(r.proposal.groups) do
		local tier = group.tier and View.TierText(group.tier) or L["INA_UNKNOWN"]
		out[#out + 1] = { header = L["OPS_GROUP"]:format(tier, #group.accounts) }
		for _, a in ipairs(group.accounts) do out[#out + 1] = { draft = r.drafts[a.key] } end
	end
	return out
end

-- The characters of an account: name, rank, level, last seen and the choice that counts.
function View.CharRows(draft, t)
	local out = {}
	t = t or now()
	for _, guid in ipairs(draft.account.chars) do
		local e = ns.Roster:ByGUID(guid)
		if e then
			local last
			if e.online then last = L["ONLINE"]
			else
				local seen = ns.Inactivity.LastSeen(guid, e, nil, nil, t)
				last = seen and ns.Provenance.AgeText(t - seen) or L["INA_UNKNOWN"]
			end
			out[#out + 1] = { guid = guid, name = escape(e.short or e.name), rank = e.rankName and escape(e.rankName) or "",
				level = e.level, last = last, choice = View.ChoiceText(ops().ChoiceOf(draft, guid)),
				own = draft.per[guid] ~= nil }
		end
	end
	return out
end

-- The last timeline lines of an account.
function View.EventLines(draft)
	local out = {}
	local events = ns.Timeline:EventsOf(draft.account.chars)
	for i = 1, ops().EVENTS do
		if events[i] then out[#out + 1] = ns.Timeline.LineText(events[i]) end
	end
	return out
end

-- The summary of step 3: one line per entry to add and per choice left out.
function View.SummaryRows(plan)
	local out = {}
	for _, spec in ipairs(plan.add) do
		local text = View.OpText(spec)
		if spec.op == "note" then text = text .. ": " .. (spec.text == "" and L["OPS_NOTE_EMPTY"] or escape(spec.text)) end
		out[#out + 1] = { name = escape(spec.name), text = text }
	end
	for _, s in ipairs(plan.skipped) do
		out[#out + 1] = { name = escape(s.name), text = L["OPS_SKIPPED"]:format(L[ACTION_KEYS[s.op]], L[WHY_KEYS[s.why]]), muted = true }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The review: choices
---------------------------------------------------------------------------------------------------------------------
local function current(self)
	local r = self.review
	local draft = r and r.selected and r.drafts[r.selected]
	return r, draft
end

-- The choice the options edit: the account's, or the target character's own one (made from the account's when asked).
local function choiceFor(r, draft, create)
	if not r.target then return draft end
	if not draft.per[r.target] and create then
		draft.per[r.target] = { action = draft.action, rank = draft.rank, noteKind = draft.noteKind, text = draft.text }
	end
	return draft.per[r.target] or draft
end

function View:SelectAccount(key)
	local r = self.review
	if not (r and r.drafts and r.drafts[key]) then return false end
	r.selected, r.target = key, nil
	self:DrawReview()
	return true
end

-- What the options edit: one character of the selected account (`guid`), or the whole account (nil).
function View:SelectTarget(guid)
	local r, draft = current(self)
	if not draft then return false end
	r.target = guid
	self:DrawReview()
	return true
end

function View:SetAction(op)
	local r, draft = current(self)
	if not draft then return false end
	local choice = choiceFor(r, draft, true)
	if choice.action ~= op then choice.action, choice.rank = op, nil end
	self:DrawReview()
	return true
end

-- A character goes back to the choice of its account.
function View:ClearTarget()
	local r, draft = current(self)
	if not (draft and r.target) then return false end
	draft.per[r.target] = nil
	r.target = nil
	self:DrawReview()
	return true
end

function View:SetRank(index)
	local r, draft = current(self)
	if not draft then return false end
	choiceFor(r, draft, true).rank = index
	self:DrawReview()
	return true
end

function View:SetNote(kind, text)
	local r, draft = current(self)
	if not draft then return false end
	local choice = choiceFor(r, draft, true)
	if kind then choice.noteKind = kind end
	if text then choice.text = text end
	self:DrawReview(text ~= nil)   -- while typing, the field keeps its text
	return true
end

-- The ranks offered for the target: of one character, or any rank that fits one of the account's characters.
function View:RankOptions()
	local r, draft = current(self)
	if not draft then return {} end
	local choice = choiceFor(r, draft)
	local guids = r.target and { r.target } or draft.account.chars
	local seen, out = {}, {}
	for _, guid in ipairs(guids) do
		local e = ns.Roster:ByGUID(guid)
		if e and e.rankIndex then
			for _, rank in ipairs(ops():RankChoices(choice.action, e.rankIndex)) do
				if not seen[rank.index] then
					seen[rank.index] = true
					out[#out + 1] = rank
				end
			end
		end
	end
	sort(out, function(a, b) return a.index < b.index end)
	return out
end

local function rankMenu(self, anchor)
	local items = { { text = L["OPS_RANK_NEXT"], onClick = function() self:SetRank(nil) end } }
	for _, rank in ipairs(self:RankOptions()) do
		items[#items + 1] = { text = escape(rank.name), onClick = function() self:SetRank(rank.index) end }
	end
	Widgets.Menu.Show(anchor, items, 220)
end

local function charMenu(self, data, row)
	local items = { { text = data.name, header = true } }
	items[#items + 1] = { text = L["OPS_AS_ACCOUNT"], onClick = function()
		self:SelectTarget(data.guid)
		self:ClearTarget()
	end }
	for _, op in ipairs(ops().ACTIONS) do
		items[#items + 1] = { text = L[ACTION_KEYS[op]], onClick = function()
			self:SelectTarget(data.guid)
			self:SetAction(op)
		end }
	end
	Widgets.Menu.Show(row, items, 220)
end

---------------------------------------------------------------------------------------------------------------------
-- The review: frames
---------------------------------------------------------------------------------------------------------------------
local function buildStep1(f, self, w)
	f.text = label(f, "Small", "text-3", 0, 0, w)
	f.text:SetText(L["OPS_STEP1_TEXT"])
	f.tierLabel = label(f, "Eyebrow", "text-3", 0, 48, w)
	f.tierLabel:SetText(L["OPS_MIN_TIER"])
	f.tiers = Widgets.ChipRow(f, function(id)
		View.reviewFilter.minTier = id
		self:DrawReview()
	end, { height = 26, gap = 6 })
	f.tiers:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -68)
	f.tiers:SetWidth(10)
	local function toggle(key, text, y)
		local chip = Widgets.Chip(f, { text = text, height = 26, onClick = function()
			View.reviewFilter[key] = not View.reviewFilter[key]
			self:DrawReview()
		end })
		chip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
		return chip
	end
	f.reviewed = toggle("reviewed", L["OPS_INCLUDE_REVIEWED"], 112)
	f.unknown = toggle("unknown", L["OPS_INCLUDE_UNKNOWN"], 146)
	f.count = label(f, "Body", "text-1", 0, 196, w)
end

local function buildStep2(f, self, w)
	f.accounts = Widgets.DataTable(f, {
		column("account", "COL_OPS_ACCOUNT", { flex = 2 },
			function(d) return d.header or escape(d.draft.account.name) end,
			function(d) return d.header and "accent-text" or nil end),
		column("days", "COL_INA_DAYS", { width = 60, align = "RIGHT", mono = true },
			function(d) return d.draft and d.draft.account.days and tostring(d.draft.account.days) or "" end),
		column("choice", "COL_OPS_ACTION", { flex = 2 }, function(d) return d.draft and View.DraftText(d.draft) or "" end),
	}, { rowHeight = 24, onRowClick = function(d) if d.draft then self:SelectAccount(d.draft.account.key) end end })
	f.accounts:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.accounts:SetSize(w, 150)
	f.selected = label(f, "BodyMedium", "text-1", 0, 158, w)
	f.chars = Widgets.DataTable(f, {
		column("name", "COL_OPS_NAME", { flex = 1.5 }, function(d) return d.name end),
		column("rank", "COL_INA_RANK", { flex = 1 }, function(d) return d.rank end),
		column("level", "COL_OPS_LEVEL", { width = 50, align = "RIGHT", mono = true },
			function(d) return d.level and tostring(d.level) or "" end),
		column("last", "COL_INA_LAST", { flex = 1 }, function(d) return d.last end),
		column("choice", "COL_OPS_ACTION", { flex = 1.5 }, function(d) return d.choice end,
			function(d) return not d.own and "text-3" or nil end),
	}, { rowHeight = 24, onRowClick = function(d, row) charMenu(self, d, row) end })
	f.chars:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -178)
	f.chars:SetSize(w, 104)
	f.events = label(f, "Small", "text-3", 0, 288, w)
	f.target = label(f, "Eyebrow", "text-3", 0, 340, w - 180)
	f.wholeAccount = Widgets.Button(f, { text = L["OPS_AS_ACCOUNT"], style = "ghost", height = 22,
		onClick = function() self:ClearTarget() end })
	f.wholeAccount:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -334)
	f.actions = Widgets.ChipRow(f, function(id) self:SetAction(id) end, { height = 26, gap = 6 })
	f.actions:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -360)
	f.actions:SetWidth(10)
	f.rank = Widgets.Button(f, { text = L["OPS_RANK_NEXT"], style = "secondary", height = 26,
		onClick = function() rankMenu(self, f.rank) end })
	f.rank:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -394)
	f.kinds = Widgets.ChipRow(f, function(id) self:SetNote(id) end, { height = 26, gap = 6 })
	f.kinds:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -394)
	f.kinds:SetWidth(10)
	f.note = Widgets.EditBox(f, { width = 320, height = 28, maxLetters = ops().NOTE_MAX, placeholder = L["OPS_NOTE_HINT"],
		onChange = function(text, user) if user then self:SetNote(nil, text) end end })
	f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -428)
end

local function buildStep3(f, self, w)
	f.text = label(f, "Small", "text-3", 0, 0, w)
	f.list = Widgets.DataTable(f, {
		column("name", "COL_OPS_NAME", { flex = 1 }, function(d) return d.name end,
			function(d) return d.muted and "text-3" or nil end),
		column("what", "COL_OPS_ACTION", { flex = 2.5 }, function(d) return d.text end,
			function(d) return d.muted and "text-3" or nil end),
	}, { rowHeight = 24, emptyText = L["OPS_NOTHING"] })
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -52)
	f.list:SetSize(w, 390)
end

local STEPS = { buildStep1, buildStep2, buildStep3 }

local function buildReviewDialog(self)
	local w, h = View.REVIEW_WIDTH, View.REVIEW_HEIGHT
	local d = Widgets.Dialog(UIParent, "AzerothAccordReviewDialog", { width = w, height = h })
	local card = d.card
	d.title = label(card, "H2", "text-1", 24, 18, w - 48)
	d.steps = {}
	for i, build in ipairs(STEPS) do
		local f = CreateFrame("Frame", nil, card)
		f:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -52)
		f:SetSize(w - 48, h - 112)
		build(f, self, w - 48)
		d.steps[i] = f
	end
	d.next = Widgets.Button(card, { text = L["OPS_NEXT"], style = "primary", width = 240, onClick = function()
		local r = self.review
		if not r then return end
		if r.step == 3 then self:ApplyReview() else self:ReviewStep(r.step + 1) end
	end })
	d.next:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 18)
	d.back = Widgets.Button(card, { text = L["OPS_BACK"], style = "secondary",
		onClick = function() if self.review then self:ReviewStep(self.review.step - 1) end end })
	d.back:SetPoint("RIGHT", d.next, "LEFT", -8, 0)
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "ghost", onClick = function() d:Close() end })
	d.close:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 18)
	return d
end

local function drawStep1(f, r)
	local tiers = ns.Inactivity:Tiers()
	local items = {}
	for i = 1, 4 do items[i] = { id = i, text = L["INA_TIER"]:format(tiers[i]) } end
	f.tiers:SetItems(items, View.reviewFilter.minTier)
	f.tiers:SetWidth(f.tiers.width or 10)
	f.reviewed:SetSelected(View.reviewFilter.reviewed)
	f.unknown:SetSelected(View.reviewFilter.unknown)
	f.count:SetText(L["OPS_PROPOSED"]:format(r.proposal.count))
end

local function drawStep2(self, f, r, typing)
	f.accounts:SetData(View.ReviewRows(r), true)
	local draft = r.selected and r.drafts[r.selected]
	if not draft then return end
	f.selected:SetText(escape(draft.account.name))
	f.chars:SetData(View.CharRows(draft), true)
	local lines = View.EventLines(draft)
	f.events:SetText(#lines > 0 and concat(lines, "\n") or L["OPS_NO_EVENTS"])
	local choice = choiceFor(r, draft)
	local e = r.target and ns.Roster:ByGUID(r.target)
	f.target:SetText(e and L["OPS_TARGET_CHAR"]:format(escape(e.short or e.name)) or L["OPS_TARGET_ACCOUNT"])
	f.wholeAccount:SetShown(r.target ~= nil)
	local items = {}
	for i, op in ipairs(ops().ACTIONS) do items[i] = { id = op, text = L[ACTION_KEYS[op]] } end
	f.actions:SetItems(items, choice.action)
	f.actions:SetWidth(f.actions.width or 10)
	local ranked = choice.action == "promote" or choice.action == "demote"
	f.rank:SetShown(ranked)
	if ranked then f.rank:SetLabel(choice.rank and rankName(choice.rank) or L["OPS_RANK_NEXT"]) end
	local note = choice.action == "note"
	f.kinds:SetShown(note)
	f.note:SetShown(note)
	if note then
		local kinds = { { id = "public", text = L["OPS_KIND_PUBLIC"] } }
		if ns.Compat.Guild.CanViewOfficerNote() then kinds[2] = { id = "officer", text = L["OPS_KIND_OFFICER"] } end
		f.kinds:SetItems(kinds, choice.noteKind)
		f.kinds:SetWidth(f.kinds.width or 10)
		if not typing then f.note:SetText(choice.text or "") end
	end
end

local function drawStep3(f, r)
	local plan = ops():Plan(draftList(r))
	r.plan = plan
	f.text:SetText(L["OPS_SUMMARY"]:format(#plan.add, #plan.kept))
	f.list:SetData(View.SummaryRows(plan), true)
end

function View:DrawReview(typing)
	local d, r = self.reviewDialog, self.review
	if not (d and r) then return end
	d.title:SetText(L["OPS_REVIEW_TITLE"]:format(r.step))
	for i, f in ipairs(d.steps) do f:SetShown(i == r.step) end
	local f = d.steps[r.step]
	if r.step == 1 then
		propose(r)
		drawStep1(f, r)
		d.next:SetLabel(L["OPS_NEXT"])
		d.next:SetEnabled(r.proposal.count > 0)
	elseif r.step == 2 then
		drawStep2(self, f, r, typing)
		d.next:SetLabel(L["OPS_NEXT"])
		d.next:SetEnabled(true)
	else
		drawStep3(f, r)
		d.next:SetLabel(L["OPS_ADD"]:format(#r.plan.add))
		d.next:SetEnabled(true)
	end
	d.back:SetShown(r.step > 1)
end

function View:OpenReview()
	if not ops().Allowed() then return nil end
	if not self.reviewDialog then self.reviewDialog = buildReviewDialog(self) end
	self.review = { step = 1 }
	local d = self.reviewDialog
	self:DrawReview()
	d:Open()
	return d
end

function View:ReviewStep(step)
	local r = self.review
	if not r or step < 1 or step > 3 or (step > 1 and r.proposal.count == 0) then return false end
	Widgets.Menu.Hide()
	r.step = step
	self:DrawReview()
	return true
end

-- Adds the actions to the queue and shows it. Returns the result of Ops:Apply, or nil.
function View:ApplyReview()
	local r = self.review
	if not r or r.step ~= 3 then return nil end
	local result = ops():Apply(draftList(r))
	if not result then return nil end
	self.review = nil
	self.reviewDialog:Close()
	if ns.addon then
		ns.addon:Print(L["OPS_ADDED"]:format(result.added, result.kept))
		if result.refused > 0 then ns.addon:Print(L["OPS_FULL"]:format(result.refused, ops().MAX_OPEN)) end
	end
	if result.added > 0 then self:ShowPage("queue") else self:Redraw() end
	return result
end

function View:CloseOps()
	self.review = nil
	if self.entryDialog then self.entryDialog:Close() end
	if self.reviewDialog then self.reviewDialog:Close() end
	Widgets.Menu.Hide()
end

if ns.addon and ns.Bus then
	ns.Bus:On("OPS_CHANGED", function()
		if ns.Shell then ns.Shell:UpdateBadges() end
		View:Changed()
	end)
	ns.Bus:On("OFFICER_PURGED", function()
		View:CloseOps()
		if ns.Shell then ns.Shell:UpdateBadges() end
	end)
	ns.Bus:On("ROLE_CHANGED", function() if not ops().Allowed() then View:CloseOps() end end)
	ns.Bus:On("GUILD_CHANGED", function() View:CloseOps() end)
	ns.Bus:On("DEMO_CHANGED", function() View:CloseOps() end)
end

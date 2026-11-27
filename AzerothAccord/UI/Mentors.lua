-- MentorsView: the "Mentors" mode of the Reputation view, the dialog of the own offer, and, for the officers, the mentors
-- suggested to the new members: the third tab of the Trials page and a section of the member card (M12.5; SPEC-16 §6).
-- Lua 5.1.
-- The list is for every member; the pairs only for who may see them (Mentors.CanSeePairs). Only with the switch "recruit".
-- Whisper opens the chat box with "/w Name": the player writes and sends, the addon sends nothing (RC-01, SOC-20).
--   View.ListRows(opts)          the offers the mode shows: opts = { topic, search }
--   View.PairLines(data, search) the lines of the suggestions: { { text, heading, muted, guid (Whisper) } }
--   View.Reasons(candidate)      why a mentor is suggested
--   View:Offer() / View:Leave()  one click each
--   View:OpenDialog()            the own offer: View:Toggle(topic), View:Save(note)
--   View:Whisper(guid)
--   View.CardSection(entry)      "Suggested mentors" on the card of a new member
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.MentorsView, ns.modules = View, ns.modules or {}
ns.modules.MentorsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, floor, max, min = type, ipairs, pairs, tostring, math.floor, math.max, math.min

View.ROW_HEIGHT = 44
View.LINE_HEIGHT = 36
View.TOP = 84                  -- the own offer and the topic filter
View.WIDTH, View.HEIGHT = 460, 330
View.topic = nil               -- the topic filter (nil: all)
View.offset = 0

local function M() return ns.Mentors end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end

local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-3")
end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function View.TopicText(id) return L["MEN_TOPIC_" .. tostring(id):upper()] end

function View.TopicsText(topics)
	local out = {}
	for i, id in ipairs(topics or {}) do out[i] = View.TopicText(id) end
	if #out == 0 then return L["MEN_NO_TOPICS"] end
	return table.concat(out, ", ")
end

local ERRORS = { account = "MEN_ERR_ACCOUNT", note = "MEN_ERR_NOTE", rate = "MEN_ERR_RATE", guild = "NOT_IN_GUILD" }

function View.ErrorText(why)
	if why == "note" then return L["MEN_ERR_NOTE"]:format(M().NOTE_MAX) end
	return L[ERRORS[why] or "MEN_ERR_OTHER"]
end

-- A change refused outside the mode (the switch of What I share): said in chat.
function View.Refused(why)
	if ns.addon then ns.addon:Print(View.ErrorText(why)) end
end

function View.Reasons(c)
	local out = {}
	if (c.together or 0) > 0 then
		out[#out + 1] = L["MEN_WHY_TOGETHER"]:format(L["SOC_HOURS"]:format(floor(c.together / 6 + 0.5) / 10))
	end
	if (c.shared or 0) > 0 then out[#out + 1] = L["MEN_WHY_SHARED"] end
	if c.sameGroup then out[#out + 1] = L["MEN_WHY_GROUP"] end
	if #out == 0 then out[1] = L["MEN_WHY_NONE"] end
	if (c.hours or 0) > 0 then out[#out + 1] = L["MEN_WHY_HOURS"] end
	return table.concat(out, " · ")
end

local function newcomerText(row)
	local parts = {}
	if row.trial then parts[#parts + 1] = L["MEN_NEW_TRIAL"] end
	if row.joined then parts[#parts + 1] = L["MEN_NEW_JOINED"]:format(date("!%Y-%m-%d", row.joined)) end
	return L["MEN_NEW_LINE"]:format(escape(row.name), table.concat(parts, " · "))
end

local function mentorText(c)
	return L[c.first and "MEN_FIRST" or "MEN_ALSO"]:format(escape(c.name), View.Reasons(c))
end

-- The lines of the suggestions; `search` filters by the name of the new member or of a mentor.
function View.PairLines(data, search)
	local out = {}
	local needle = search and search ~= "" and search:lower() or nil
	local function matches(row)
		if not needle or tostring(row.name):lower():find(needle, 1, true) then return true end
		for _, c in ipairs(row.mentors) do
			if tostring(c.name):lower():find(needle, 1, true) then return true end
		end
		return false
	end
	if #data.rows == 0 then
		out[1] = { text = L["MEN_PAIRS_EMPTY"]:format(M().NEW_DAYS), muted = true }
		return out
	end
	if data.computing then out[#out + 1] = { text = L["MEN_PAIRS_COMPUTING"], muted = true } end
	if data.mentors == 0 then out[#out + 1] = { text = L["MEN_PAIRS_NO_MENTOR"], muted = true } end
	for _, row in ipairs(data.rows) do
		if matches(row) then
			out[#out + 1] = { text = newcomerText(row), heading = true, guid = row.guid }
			local first = false
			for _, c in ipairs(row.mentors) do
				first = first or c.first
				out[#out + 1] = { text = mentorText(c), guid = c.guid }
			end
			if #row.mentors > 0 and not first then
				out[#out + 1] = { text = L["MEN_FULL"]:format(M().MAX_PER_MENTOR), muted = true }
			end
		end
	end
	return out
end

function View:Whisper(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	local name = e and (e.name or e.short)
	return name ~= nil and ns.Compat.Chat.OpenWhisper(name, "") or false
end

---------------------------------------------------------------------------------------------------------------------
-- The own offer
---------------------------------------------------------------------------------------------------------------------
local function result(ok, why)
	View.error = not ok and View.ErrorText(why) or nil
	if ns.ReputationView then ns.ReputationView:Changed() end
	if ok then return true end
	return false, why
end

-- One click: on the list, with no topic and no note yet (Edit adds them).
function View:Offer()
	local rec, why = M():Join()
	return result(rec ~= nil, why)
end

function View:Leave()
	local ok, why = M():Leave()
	if self.dialog then self.dialog:Close() end
	return result(ok == true, why)
end

local function byteCount(d)
	local n = #M().CleanNote(d.note:GetText())
	say(d.count, L["MEN_NOTE_COUNT"]:format(n, M().NOTE_MAX), n > M().NOTE_MAX and "err" or "text-3")
end

local function buildDialog()
	local w = View.WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordMentorDialog", { width = w, height = View.HEIGHT })
	local card = d.card
	d:SetTitle("")
	d.title:SetText(L["MEN_DIALOG_TITLE"])
	d.topicsLabel = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.topicsLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -58)
	d.topicsLabel:SetText(L["MEN_TOPICS"])
	d.chips = {}
	local order = {}
	-- the chips flow in the width of the dialog (a chosen one grows by its check) and what follows moves under them
	local function placeChips()
		local h = Widgets.Flow(card, order, w - 48, Widgets.HEIGHT.small, 8, 24, 80)
		local y = 80 + h + 12
		d.noteLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -y)
		d.note:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -(y + 20))
		d.count:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -(y + 64))
		d.status:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -(y + 84))
		card:SetHeight(math.max(View.HEIGHT, y + 84 + 32 + 64))
	end
	for i, id in ipairs(M().TOPICS) do
		local chip = Widgets.Chip(card, { text = View.TopicText(id), onClick = function() View:Toggle(id) end })
		d.chips[id], order[i] = chip, chip
	end
	d.noteLabel = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.noteLabel:SetText(L["MEN_NOTE"])
	d.note = Widgets.EditBox(card, { width = w - 48, dense = true, maxLetters = 80,
		onChange = function() if View.dialog then byteCount(View.dialog) end end,
		onEnter = function() View:Save() end })
	d.count = Widgets.Text(card, "Small", "text-3", "LEFT")
	d.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.status:SetWordWrap(true)
	d.ok = Widgets.Button(card, { text = L["MEN_SAVE"], style = "filled", onClick = function() View:Save() end })
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "text", onClick = function() d:Close() end })
	d:SetActions({ d.close, d.ok })
	placeChips()
	for _, chip in ipairs(order) do chip.onResize = placeChips end
	return d
end

-- The dialog of the account's offer (only while it is on the list). Returns it, or nil.
function View:OpenDialog()
	local rec = M() and M():Own()
	if not rec then return nil end
	if not self.dialog then self.dialog = buildDialog() end
	local d = self.dialog
	d.topics = {}
	for _, id in ipairs(rec.topics or {}) do d.topics[id] = true end
	for id, chip in pairs(d.chips) do chip:SetSelected(d.topics[id] == true) end
	d.note:SetText(rec.note or "")
	byteCount(d)
	say(d.status, L["MEN_PAIRS_NOTE"])
	d:Open()
	return d
end

function View:Toggle(id)
	local d = self.dialog
	if not (d and d.chips[id]) then return false end
	d.topics[id] = not d.topics[id] or nil
	d.chips[id]:SetSelected(d.topics[id] == true)
	return d.topics[id] == true
end

function View:Save(note)
	local d = self.dialog
	if not d then return false, "none" end
	local topics = {}
	for _, id in ipairs(M().TOPICS) do if d.topics[id] then topics[#topics + 1] = id end end
	local rec, why = M():Edit(topics, note or d.note:GetText())
	if not rec then
		say(d.status, View.ErrorText(why), "err")
		return false, why
	end
	d:Close()
	return result(true)
end

---------------------------------------------------------------------------------------------------------------------
-- The mode of the Reputation view
---------------------------------------------------------------------------------------------------------------------
function View.ListRows(opts)
	opts = opts or {}
	local needle = opts.search and opts.search ~= "" and opts.search:lower() or nil
	local out = {}
	for _, m in ipairs(M():List(opts.topic)) do
		if not needle or m.name:lower():find(needle, 1, true) or m.main:lower():find(needle, 1, true) then out[#out + 1] = m end
	end
	return out
end

-- The line about the own offer.
function View.OwnText()
	local rec = M():Own()
	if not rec then return L["MEN_NOT_LISTED"] end
	local text = L["MEN_YOURS"]:format(View.TopicsText(rec.topics))
	if rec.note then text = text .. " · " .. escape(rec.note) end
	return text
end

local mode = {}

function mode.build(f)
	View.frame = f
	f.own = Widgets.Text(f, "Body", "text-1", "LEFT")
	f.own:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -6)
	f.own:SetPoint("RIGHT", f, "RIGHT", -340, 0)
	f.own:SetWordWrap(false)
	f.offer = Widgets.Button(f, { text = L["MEN_OFFER"], style = "filled", dense = true, onClick = function() View:Offer() end })
	f.offer:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.leave = Widgets.Button(f, { text = L["MEN_LEAVE"], style = "outlined", dense = true, onClick = function() View:Leave() end })
	f.leave:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.edit = Widgets.Button(f, { text = L["MEN_EDIT"], style = "tonal", dense = true, width = 90,
		onClick = function() View:OpenDialog() end })
	f.edit:SetPoint("RIGHT", f.leave, "LEFT", -8, 0)
	f.filter = Widgets.ChipRow(f, function(id)
		View.topic = id ~= "all" and id or nil
		View.offset = 0
		if ns.ReputationView then ns.ReputationView:Redraw() end
	end)
	f.filter:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -44)
	f.filter:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.area = CreateFrame("Frame", nil, f)
	f.area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.TOP)
	f.area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
	f.area:SetClipsChildren(true)
	f.area:EnableMouseWheel(true)
	f.area:SetScript("OnMouseWheel", function(_, delta)
		View.offset = max(0, View.offset - delta)
		if ns.ReputationView then ns.ReputationView:Redraw() end
	end)
	f.area.rows = {}
	f.message = Widgets.Text(f, "Body", "text-3", "CENTER")
	f.message:SetPoint("CENTER", f.area, "CENTER", 0, 0)
	f.message:SetWidth(380)
	f.foot = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 2)
	f.foot:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.foot:SetWordWrap(false)
end

local function newRow(area, i)
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(View.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
	row.mark = Widgets.ClassMark(row, 8)
	row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -10)
	row.name = Widgets.Text(row, "BodyMedium", "text-1", "LEFT")
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -6)
	row.name:SetWidth(140)
	row.topics = Widgets.Text(row, "Small", "text-2", "LEFT")
	row.topics:SetPoint("TOPLEFT", row, "TOPLEFT", 170, -7)
	row.topics:SetPoint("RIGHT", row, "RIGHT", -180, 0)
	row.topics:SetWordWrap(false)
	row.note = Widgets.Text(row, "Small", "text-3", "LEFT")
	row.note:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -25)
	row.note:SetPoint("RIGHT", row, "RIGHT", -180, 0)
	row.note:SetWordWrap(false)
	row.whisper = Widgets.Button(row, { text = L["NEW_WHISPER"], style = "tonal", width = 90, height = Widgets.HEIGHT.small,
		onClick = function(b) View:Whisper(b:GetParent().guid) end })
	row.whisper:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.online = Widgets.Text(row, "Small", "text-3", "RIGHT")
	row.online:SetPoint("RIGHT", row.whisper, "LEFT", -10, 0)
	row:SetScript("OnClick", function(self)
		if ns.ReputationView then ns.ReputationView:OpenCard({ guid = self.guid }) end
	end)
	Widgets.RowHover(row)
	area.rows[i] = row
	return row
end

local function fillRow(row, m)
	row.guid = m.guid
	row.name:SetText(m.name)
	Widgets.PaintName(row.name, m.classFile)
	local c = RAID_CLASS_COLORS and m.classFile and RAID_CLASS_COLORS[m.classFile]
	if c then Widgets.PaintClassMark(row.mark, c.r, c.g, c.b) else Widgets.ClearClassMark(row.mark) end
	local topics = View.TopicsText(m.topics)
	if m.main ~= m.name then topics = L["MEN_MAIN"]:format(m.main) .. " · " .. topics end
	row.topics:SetText(topics)
	row.note:SetText(escape(m.note or ""))
	say(row.online, L[m.online and "MEN_ONLINE" or "MEN_OFFLINE"], m.online and "ok" or "text-3")
	row.whisper:SetShown(not m.own)
	row:Show()
end

function mode.refresh(f)
	local mine = M():Own() ~= nil
	say(f.own, View.error or View.OwnText(), View.error and "err" or "text-1")
	View.error = nil
	f.offer:SetShown(not mine)
	f.leave:SetShown(mine)
	f.edit:SetShown(mine)
	local chips = { { id = "all", text = L["MEN_ALL"] } }
	for _, id in ipairs(M().TOPICS) do chips[#chips + 1] = { id = id, text = View.TopicText(id) } end
	f.filter:SetItems(chips, View.topic or "all")
	local search = ns.ReputationView and ns.ReputationView.search
	local list = View.ListRows({ topic = View.topic, search = search })
	View.shown = list
	local h = f.area:GetHeight() or 0
	local visible = h >= View.ROW_HEIGHT and floor(h / View.ROW_HEIGHT) or 8
	View.offset = max(0, min(View.offset, max(0, #list - visible)))
	local drawn = max(0, min(visible, #list - View.offset))
	for i = 1, drawn do fillRow(f.area.rows[i] or newRow(f.area, i), list[View.offset + i]) end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	f.message:SetShown(#list == 0)
	f.message:SetText(L[(View.topic or (search and search ~= "")) and "MEN_NO_MATCH" or "MEN_EMPTY"])
	f.foot:SetText(L["MEN_EXPLAIN"])
end

if ns.ReputationView then
	ns.ReputationView.AddMode("mentors", { label = L["REP_MODE_MENTORS"], order = 50, build = mode.build, refresh = mode.refresh,
		search = true, available = function() return M() ~= nil and M().Enabled() end })
end

---------------------------------------------------------------------------------------------------------------------
-- The suggestions (the third tab of the Trials page)
---------------------------------------------------------------------------------------------------------------------
local function line(f, i)
	local row = f.lines[i]
	if row then return row end
	row = CreateFrame("Frame", nil, f)
	row:SetHeight(View.LINE_HEIGHT)
	row.text = Widgets.Text(row, "Body", "text-2", "LEFT")
	row.text:SetPoint("RIGHT", row, "RIGHT", -100, 0)
	row.text:SetWordWrap(false)
	row.whisper = Widgets.Button(row, { text = L["NEW_WHISPER"], style = "tonal", width = 90, height = Widgets.HEIGHT.small,
		onClick = function(b) View:Whisper(b:GetParent().guid) end })
	row.whisper:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	f.lines[i] = row
	return row
end

local function drawLines(f)
	local list = f.list or {}
	local h = f.area:GetHeight() or 0
	local visible = h >= View.LINE_HEIGHT and floor(h / View.LINE_HEIGHT) or 12
	f.offset = max(0, min(f.offset or 0, max(0, #list - visible)))
	local drawn = max(0, min(visible, #list - f.offset))
	for i = 1, drawn do
		local l = list[f.offset + i]
		local row = line(f, i)
		row.guid = l.guid
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f.area, "TOPLEFT", 0, -(i - 1) * View.LINE_HEIGHT)
		row:SetPoint("TOPRIGHT", f.area, "TOPRIGHT", 0, -(i - 1) * View.LINE_HEIGHT)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", row, "LEFT", (l.heading or not l.guid) and 4 or 20, 0)
		row.text:SetPoint("RIGHT", row, "RIGHT", -100, 0)
		row.text:SetFontObject(Theme.Font(l.heading and "BodyMedium" or "Body"))
		say(row.text, l.text, l.heading and "text-1" or l.muted and "text-3" or "text-2")
		row.whisper:SetShown(l.guid ~= nil and l.guid ~= ns.Compat.Player.GUID())
		row:Show()
	end
	for i = drawn + 1, #f.lines do f.lines[i]:Hide() end
end

function View.BuildPairs(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.help = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.help:SetPoint("TOPLEFT", f, "TOPLEFT", 4, 0)
	f.help:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.help:SetWordWrap(true)
	f.help:SetText(L["MEN_PAIRS_HELP"])
	f.area = CreateFrame("Frame", nil, f)
	f.area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
	f.area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.area:SetClipsChildren(true)
	f.area:EnableMouseWheel(true)
	f.area:SetScript("OnMouseWheel", function(_, delta)
		f.offset = max(0, (f.offset or 0) - delta * 3)
		drawLines(f)
	end)
	f.lines = {}
	View.pairs = f
	return f
end

-- Computes and draws the suggestions; returns how many new members there are.
function View.RefreshPairs(f, search)
	local data = M():Pairs()
	f.list = View.PairLines(data, search)
	drawLines(f)
	return #data.rows
end

---------------------------------------------------------------------------------------------------------------------
-- The member card (officers only)
---------------------------------------------------------------------------------------------------------------------
function View.CardSection(e)
	local Mn = M()
	if not (Mn and Mn.CanSeePairs()) or type(e) ~= "table" or type(e.guid) ~= "string" or e.notInGuild then return nil end
	local row, data = Mn:PairsFor(e.guid)
	if not row then return nil end
	local lines = {}
	if data.computing then lines[#lines + 1] = { text = L["MEN_PAIRS_COMPUTING"], muted = true } end
	if #row.mentors == 0 then lines[#lines + 1] = { text = L["MEN_PAIRS_NO_MENTOR"], muted = true } end
	for _, c in ipairs(row.mentors) do
		local guid = c.guid
		lines[#lines + 1] = { text = mentorText(c) }
		if guid ~= ns.Compat.Player.GUID() then
			lines[#lines + 1] = { text = L["MEN_CARD_WHISPER"]:format(escape(c.name)), action = true,
				onClick = function() View:Whisper(guid) end }
		end
	end
	return { id = "mentors", title = L["MEN_CARD_TITLE"], lines = lines }
end

if ns.MemberCard then ns.MemberCard.AddSection("mentors", 7.47, View.CardSection) end

if ns.addon then
	ns.addon.MentorsView = View
	if ns.Bus then
		ns.Bus:On("MENTORS_CHANGED", function()
			if ns.MemberCard then ns.MemberCard:Refresh() end
			if ns.ReputationView then ns.ReputationView:Changed() end
			if ns.OfficersView then ns.OfficersView:Changed() end
			if View.dialog and View.dialog:IsShown() and not M():Own() then View.dialog:Close() end
		end)
		ns.Bus:On("SOCIAL_UPDATED", function()
			if M() and M().CanSeePairs() and ns.OfficersView then ns.OfficersView:Changed() end
		end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.topic, View.offset, View.error = nil, 0, nil
			if View.dialog then View.dialog:Close() end
		end)
	end
end

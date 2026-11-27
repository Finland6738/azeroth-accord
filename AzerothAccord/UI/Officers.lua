-- Officers: the Officers tab (SPEC-12 §8), its pages, the dialogs of the absences and of the tiers, and the "Absence"
-- section of the member card. Lua 5.1.
--
-- The tab shows only to officers (Officer.CanSee), with a page selector: "Inactive" (§3.5, M8.3), "Queue" (§4.2, M8.4,
-- UI/OfficersOps.lua, which also holds the cleanup review), "Timeline" (§2.4) and "Trials" (SPEC-16 §4.5, M12.3,
-- UI/Trials.lua, only with the switch "recruit"). The search box of the panel filters both pages by name.
--   View.InactiveText(account, column)  the text of a cell of the Inactive page (plain, tested offline)
--   View.InactiveTip(account)           the lines of the row's tooltip
--   View.TimelineRows(filter, t)        the events of the Timeline page: filter = { kind, days (7|30|90|365), search, guids }
--   View:OpenTimeline(guid, name)       the Timeline page on one account ("Show all" of the member card)
--   View:OpenPage(id)                   the tab on one of its pages (a row of the Action Center)
--   View:OpenAbsence(guid, name)        the dialog an officer sets a return date in
--   View:OpenTiers()                    the dialog of the four tiers
--   View:OpenExport(kind)               the export box of the Inactive or the Timeline page ("inactive" | "timeline")
--   View.CardSection(entry)             the section "Absence" of the member card
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.OfficersView, ns.modules = View, ns.modules or {}
ns.modules.OfficersView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, tonumber = type, ipairs, pairs, tostring, tonumber
local concat = table.concat

View.CHANNEL_HEIGHT = 24      -- the line over the pages that says where officer data travels
View.FILTER_HEIGHT = 44
View.FOOTER = 36
View.REFRESH_DELAY = 0.4
View.PERIODS = { 7, 30, 90, 365 }
View.DEFAULT_PERIOD = 30
View.SOURCE_KEYS = { native = "INA_SOURCE_GAME", shared = "INA_SOURCE_SHARED", own = "INA_SOURCE_OWN" }

View.pages = {}                -- { id, label, order, build(frame, view), refresh(view) }
View.pageId = "inactive"
View.search = ""
View.inactive = { minTier = 1, away = false, unknown = true }
View.timeline = { kind = "all", days = View.DEFAULT_PERIOD, guids = nil, who = nil }

local function now() return ns.Compat.ServerTime() end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text):gsub("|", "||")) end

function View.AddPage(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	for _, p in ipairs(View.pages) do if p.id == id then return false end end
	def.id = id
	View.pages[#View.pages + 1] = def
	table.sort(View.pages, function(a, b) return (a.order or 100) < (b.order or 100) end)
	return true
end

-- Whoever may see one of the two pages sees the tab.
function View.Allowed()
	local O = ns.Officer
	return O ~= nil and (O.CanSee("inactivity") or O.CanSee("timeline"))
end

---------------------------------------------------------------------------------------------------------------------
-- The Inactive page: texts
---------------------------------------------------------------------------------------------------------------------
-- "14+ days"
function View.TierText(tier)
	if tier == nil then return L["INA_UNKNOWN"] end
	if tier == 0 then return L["INA_ACTIVE"] end
	local tiers = ns.Inactivity:Tiers()
	return L["INA_TIER"]:format(tiers[tier])
end

-- The mark of an account with an extended note (SPEC-12 §5.2), on the Inactive page and in the review.
function View.NotesMark()
	return ns.Assets and ns.Assets.IconText("book", 14) or ""
end

local function nameText(a)
	local marks = {}
	if a.officer then marks[#marks + 1] = L["INA_MARK_OFFICER"] end
	if a.byNote then marks[#marks + 1] = L["INA_MARK_NOTE"] end
	local text = escape(a.name)
	if #marks > 0 then text = text .. " (" .. concat(marks, ", ") .. ")" end
	-- an extended note on one of the account's characters (SPEC-12 §5.2): the book icon after the name
	if ns.OfficerNotes and ns.OfficerNotes:AnyOf(a.chars) then text = text .. " " .. View.NotesMark() end
	return text
end

local function lastText(a, t)
	if a.unknown then return L["INA_UNKNOWN"] end
	if a.online then return L["INA_LAST_ONLINE"]:format(escape(a.lastName or "?")) end
	return L["INA_LAST_ON"]:format(ns.Provenance.AgeText((t or now()) - a.last), escape(a.lastName or "?"))
end

local function awayText(a)
	if a.away then return L["INA_AWAY"]:format(ns.Absence.DayText(a.absence.day)) end
	if a.back then return L["INA_BACK"]:format(ns.Absence.DayText(a.absence.day)) end
	return ""
end

function View.InactiveText(a, column, t)
	if column == "name" then return nameText(a) end
	if column == "chars" then return tostring(#a.chars) end
	if column == "rank" then return a.rankName and escape(a.rankName) or "" end
	if column == "days" then return a.days and tostring(a.days) or "" end
	if column == "tier" then return a.away and "" or View.TierText(a.tier) end
	if column == "last" then return lastText(a, t) end
	if column == "away" then return awayText(a) end
	return ""
end

function View.InactiveTip(a, t)
	local tip = { escape(a.name) }
	tip[#tip + 1] = L["INA_TIP_CHARS"]:format(#a.chars)
	if a.officer then tip[#tip + 1] = L["INA_TIP_OFFICER"] end
	if a.byNote then tip[#tip + 1] = L["INA_TIP_NOTE"] end
	if ns.OfficerNotes and ns.OfficerNotes:AnyOf(a.chars) then tip[#tip + 1] = L["ONT_TIP_HAS"] end
	tip[#tip + 1] = lastText(a, t)
	local key = a.lastSource and View.SOURCE_KEYS[a.lastSource]
	if key then tip[#tip + 1] = L["INA_TIP_SOURCE"]:format(L[key]) end
	if a.absence then
		tip[#tip + 1] = awayText(a)
		tip[#tip + 1] = View.AbsenceBy(a.absence.rec)
	end
	return tip
end

-- Who declared an absence: the member, this player, or an officer (never a GUID).
function View.AbsenceBy(rec)
	if rec.author == ns.Compat.Player.GUID() then return L["ABS_BY_YOU"] end
	if ns.Absence.KindOf(rec) == "self" then return L["ABS_BY_MEMBER"] end
	local entry = ns.Roster and ns.Roster:ByGUID(rec.author)
	return L["ABS_BY_OFFICER"]:format(entry and escape(entry.short or entry.name) or L["TL_FORMER"])
end

-- The state of the officer channel, with what it means for what this client writes (SPEC-12 §1.4).
function View.ChannelText()
	if ns.Officer.ChannelProven() then return L["TL_CHANNEL_OK"] end
	return L["TL_CHANNEL_NO"] .. ". " .. L["TL_LOCAL_ONLY"]
end

---------------------------------------------------------------------------------------------------------------------
-- The Timeline page: rows
---------------------------------------------------------------------------------------------------------------------
local function eventName(ev)
	local entry = ns.Roster and ns.Roster:ByGUID(ev.g)
	return entry and (entry.short or entry.name) or ev.n or "?"
end

-- { { ev, name } } newest first: of the last `days` days, of one kind (or "all"), of the characters `guids` (or all).
function View.TimelineRows(filter, t)
	filter = filter or {}
	local T = ns.Timeline
	local events
	if filter.guids then events = T:EventsOf(filter.guids) else events = T:All() end
	local since = (t or now()) - (filter.days or View.DEFAULT_PERIOD) * 86400
	local needle = type(filter.search) == "string" and filter.search ~= "" and filter.search:lower() or nil
	local kind = filter.kind ~= "all" and filter.kind or nil
	local out = {}
	for _, ev in ipairs(events) do
		if ev.b >= since and (not kind or ev.k == kind) then
			local name = eventName(ev)
			if not needle or name:lower():find(needle, 1, true) then out[#out + 1] = { ev = ev, name = name } end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------------------------------------------------
local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-2")
end

local function dialogText(card, font, token, anchor, gap, width)
	local fs = Theme.NewText(card, font, token)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetWidth(width)
	if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
	else fs:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -gap) end
	return fs
end

View.DIALOG_WIDTH = 420

local function buildAbsenceDialog()
	local w = View.DIALOG_WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordAbsenceDialog", { width = w, height = 270 })
	local card = d.card
	d:SetTitle("")
	d.text = dialogText(card, "Small", "text-3", d.title, 8, w - 48)
	d.text:SetText(L["ABS_DIALOG_TEXT"])
	d.field = Widgets.EditBox(card, { width = 160, maxLetters = 10, placeholder = L["ABS_DATE_HINT"],
		onEnter = function() View:SaveAbsence() end })
	d.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -112)
	d.status = dialogText(card, "Small", "text-2", d.field, 10, w - 48)
	d.save = Widgets.Button(card, { text = L["ABS_SAVE"], style = "filled", onClick = function() View:SaveAbsence() end })
	d.clear = Widgets.Button(card, { text = L["ABS_CLEAR_OFFICER"], style = "outlined", onClick = function() View:SaveAbsence(0) end })
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "text", onClick = function() d:Close() end })
	d:SetActions({ d.close, d.clear, d.save })
	return d
end

-- The dialog for the absence of one character (it counts for the whole account, INA-06).
function View:OpenAbsence(guid, name)
	if not (ns.Role and ns.Role:IsOfficer()) or type(guid) ~= "string" then return nil end
	if not self.absenceDialog then self.absenceDialog = buildAbsenceDialog() end
	local d = self.absenceDialog
	d.guid = guid
	d.title:SetText(L["ABS_DIALOG_TITLE"]:format(escape(name or "?")))
	local current = ns.Absence:AccountOf(guid)
	d.field:SetText(current and current.away and ns.Absence.DayText(current.day) or "")
	d.clear:SetEnabled(current ~= nil and current.away == true)
	say(d.status, ns.Officer.ChannelProven() and "" or L["TL_LOCAL_ONLY"], "text-3")
	d:Open()
	return d
end

-- Saves the typed date, or `day` (0 clears). The dialog closes when it was saved.
function View:SaveAbsence(day)
	local d = self.absenceDialog
	if not d or not d.guid then return false end
	if day == nil then
		local why
		day, why = ns.Absence.ParseDate(d.field:GetText() or "")
		if not day then say(d.status, ns.Absence.ErrorText(why), "err") return false, why end
	end
	local ok, why = ns.Absence:SetFor(d.guid, day)
	if not ok then say(d.status, ns.Absence.ErrorText(why), "err") return false, why end
	d:Close()
	return true
end

local function buildTiersDialog()
	local w = View.DIALOG_WIDTH
	local d = Widgets.Dialog(UIParent, "AzerothAccordTiersDialog", { width = w, height = 270 })
	local card = d.card
	d:SetTitle("")
	d.title:SetText(L["TIERS_TITLE"])
	d.text = dialogText(card, "Small", "text-3", d.title, 8, w - 48)
	d.text:SetText(L["TIERS_TEXT"])
	d.fields = {}
	for i = 1, 4 do
		local label = Theme.NewText(card, "Eyebrow", "text-3")
		label:SetPoint("TOPLEFT", card, "TOPLEFT", 24 + (i - 1) * 94, -100)
		label:SetText(L["TIERS_N"]:format(i))
		local field = Widgets.EditBox(card, { width = 80, maxLetters = 3, onEnter = function() View:SaveTiers() end })
		field:SetPoint("TOPLEFT", card, "TOPLEFT", 24 + (i - 1) * 94, -118)
		d.fields[i] = field
	end
	d.status = dialogText(card, "Small", "text-2", nil, 168, w - 48)
	d.save = Widgets.Button(card, { text = L["ABS_SAVE"], style = "filled", onClick = function() View:SaveTiers() end })
	d.reset = Widgets.Button(card, { text = L["TIERS_RESET"], style = "outlined", onClick = function() View:SaveTiers(true) end })
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "text", onClick = function() d:Close() end })
	d:SetActions({ d.close, d.reset, d.save })
	return d
end

function View:OpenTiers()
	if not (ns.Role and ns.Role:IsOfficer()) then return nil end
	if not self.tiersDialog then self.tiersDialog = buildTiersDialog() end
	local d = self.tiersDialog
	local tiers = ns.Inactivity:Tiers()
	for i = 1, 4 do d.fields[i]:SetText(tostring(tiers[i])) end
	say(d.status, ns.Officer.ChannelProven() and "" or L["TL_LOCAL_ONLY"], "text-3")
	d:Open()
	return d
end

function View:SaveTiers(reset)
	local d = self.tiersDialog
	if not d then return false end
	local ok, why
	if reset then
		ok, why = ns.Inactivity:ResetTiers()
	else
		local list = {}
		for i = 1, 4 do list[i] = tonumber((d.fields[i]:GetText() or ""):match("^%s*(%d+)%s*$")) or 0 end
		ok, why = ns.Inactivity:SetTiers(list)
	end
	if not ok then
		say(d.status, why == "tiers" and L["TIERS_ERR"] or L["ABS_ERR_OTHER"]:format(tostring(why)), "err")
		return false, why
	end
	d:Close()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The member card
---------------------------------------------------------------------------------------------------------------------
-- "Absence" on the card of a guild member, for officers: the account's declared absence and the two actions.
function View.CardSection(e)
	if not (ns.Officer and ns.Officer.CanSee("absences")) then return nil end
	if type(e) ~= "table" or type(e.guid) ~= "string" or e.notInGuild then return nil end
	local lines = {}
	local a = ns.Absence:AccountOf(e.guid)
	if a then
		local day = ns.Absence.DayText(a.day)
		lines[#lines + 1] = { text = a.away and L["ABS_AWAY"]:format(day) or L["ABS_BACK"]:format(day), muted = a.back or nil }
		lines[#lines + 1] = { text = View.AbsenceBy(a.rec), muted = true }
		if a.rec.author == ns.Compat.Player.GUID() and not ns.Officer.ChannelProven() then
			lines[#lines + 1] = { text = L["TL_LOCAL_ONLY"], muted = true }
		end
	else
		lines[#lines + 1] = { text = L["ABS_NONE"], muted = true }
	end
	local name = e.short or e.name or "?"
	lines[#lines + 1] = { text = L["ABS_SET"], action = true, onClick = function() View:OpenAbsence(e.guid, name) end }
	if a and a.away then
		lines[#lines + 1] = { text = L["ABS_CLEAR_OFFICER"], action = true, onClick = function() ns.Absence:SetFor(e.guid, 0) end }
	end
	return { id = "absence", title = L["ABS_TITLE"], lines = lines }
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: the Inactive page
---------------------------------------------------------------------------------------------------------------------
local function rowMenu(a, row)
	local items = { { text = escape(a.name), header = true } }
	items[#items + 1] = { text = L["ABS_SET"], onClick = function() View:OpenAbsence(a.main.guid, a.name) end }
	if a.away then
		items[#items + 1] = { text = L["ABS_CLEAR_OFFICER"], onClick = function() ns.Absence:SetFor(a.main.guid, 0) end }
	end
	items[#items + 1] = { text = L["INA_MENU_CARD"], onClick = function() View:OpenCard(a.chars[1], a.main.guid) end }
	Widgets.Menu.Show(row, items, 220)
end

-- The member card of the account: the main's when the main is in the guild.
function View:OpenCard(first, main)
	local guid = (ns.Roster and ns.Roster:ByGUID(main)) and main or first
	if not (ns.Shell and ns.Shell:Select("roster")) then return false end
	return ns.MemberCard ~= nil and ns.MemberCard:ShowGUID(guid) or false
end

local function inactiveColumns()
	local function col(id, key, opts)
		opts.id, opts.title = id, L[key]
		opts.text = function(a) return View.InactiveText(a, id) end
		return opts
	end
	return {
		col("name", "COL_INA_MAIN", { flex = 2, value = function(a) return a.name end }),
		col("chars", "COL_INA_CHARS", { width = 50, align = "RIGHT", mono = true, value = function(a) return #a.chars end }),
		col("rank", "COL_INA_RANK", { flex = 1, value = function(a) return a.rankIndex or a.rankName end }),
		col("days", "COL_INA_DAYS", { width = 48, align = "RIGHT", mono = true, value = function(a) return a.days end }),
		col("tier", "COL_INA_TIER", { width = 80, value = function(a) return not a.away and a.tier or nil end }),
		-- by how long ago: the ones seen now first
		col("last", "COL_INA_LAST", { flex = 2, value = function(a)
			if a.unknown then return nil end
			if a.online then return 0 end
			return a.last and now() - a.last
		end }),
		col("away", "COL_INA_AWAY", { flex = 1.5, value = function(a)
			return (a.away or a.back) and a.absence and a.absence.day or nil
		end }),
	}
end

local function buildInactive(f, self)
	f.tierChips = Widgets.ChipRow(f, function(id)
		self.inactive.minTier = id
		self:Redraw()
	end)
	f.tierChips:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.tierChips:SetWidth(10)
	f.tiers = Widgets.Button(f, { text = L["INA_TIERS"], style = "outlined", dense = true, onClick = function() self:OpenTiers() end })
	f.tiers:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.review = Widgets.Button(f, { text = L["OPS_REVIEW"], style = "filled", dense = true, onClick = function() self:OpenReview() end })
	f.review:SetPoint("RIGHT", f.tiers, "LEFT", -8, 0)
	f.export = Widgets.Button(f, { text = L["EXPORT_BUTTON"], style = "tonal", dense = true,
		onClick = function() self:OpenExport("inactive") end })
	-- under the review and the tiers, at the right of the "show" chips
	f.export:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -View.FILTER_HEIGHT)
	local function toggle(key, label)
		return Widgets.Chip(f, { text = label, onClick = function(chip)
			self.inactive[key] = not self.inactive[key]
			chip:SetSelected(self.inactive[key])
			self:Redraw()
		end })
	end
	f.away = toggle("away", L["INA_SHOW_AWAY"])
	f.away:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.FILTER_HEIGHT)
	f.unknown = toggle("unknown", L["INA_SHOW_UNKNOWN"])
	f.unknown:SetPoint("LEFT", f.away, "RIGHT", 6, 0)
	f.table = Widgets.DataTable(f, inactiveColumns(), { emptyText = L["INA_EMPTY"], onRowClick = rowMenu,
		memory = "officers.inactive",
		rowSetup = function(row)
			Widgets.Tooltip.Attach(row, function(r) return r.data and View.InactiveTip(r.data) or nil end, "LEFT")
		end })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 * View.FILTER_HEIGHT)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
	f.count = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
end

local function refreshInactive(f, self)
	local tiers = ns.Inactivity:Tiers()
	local items = {}
	for i = 1, 4 do items[i] = { id = i, text = L["INA_TIER"]:format(tiers[i]) } end
	f.tierChips:SetItems(items, self.inactive.minTier)
	f.tierChips:SetWidth(f.tierChips.width or 10)
	f.review:SetShown(ns.OfficerOps.Allowed())
	f.export:SetShown(ns.Export.Allowed())
	f.away:SetSelected(self.inactive.away)
	f.unknown:SetSelected(self.inactive.unknown)
	local filter = self.inactive
	self.rows = ns.Inactivity:Rows({ minTier = filter.minTier, away = filter.away, unknown = filter.unknown, search = self.search })
	f.table:SetData(self.rows, true)
	f.count:SetText(L["INA_COUNT"]:format(#self.rows))
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: the Timeline page
---------------------------------------------------------------------------------------------------------------------
local function timelineColumns()
	local function col(id, key, opts, text)
		opts.id, opts.title, opts.text = id, L[key], text
		return opts
	end
	return {
		col("when", "COL_TL_WHEN", { flex = 1.5, mono = true, value = function(r) return r.ev.b end },
			function(r) return ns.Timeline.WhenText(r.ev) end),
		col("name", "COL_TL_NAME", { flex = 1 }, function(r) return escape(r.name) end),
		col("event", "COL_TL_EVENT", { flex = 2.5 }, function(r) return ns.Timeline.WhatText(r.ev) end),
	}
end

local function buildTimeline(f, self)
	f.kinds = Widgets.ChipRow(f, function(id)
		self.timeline.kind = id
		self:Redraw()
	end)
	f.kinds:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.kinds:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.periods = Widgets.ChipRow(f, function(id)
		self.timeline.days = id
		self:Redraw()
	end)
	f.periods:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.FILTER_HEIGHT)
	f.periods:SetWidth(10)
	-- "Only <name>": the page was opened from a member card; a click shows the whole guild again
	f.only = Widgets.Chip(f, { text = "", onClick = function()
		self.timeline.guids, self.timeline.who = nil, nil
		self:Redraw()
	end })
	f.only:SetPoint("LEFT", f.periods, "RIGHT", 16, 0)
	f.export = Widgets.Button(f, { text = L["EXPORT_BUTTON"], style = "tonal", dense = true,
		onClick = function() self:OpenExport("timeline") end })
	f.export:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -View.FILTER_HEIGHT)
	f.table = Widgets.DataTable(f, timelineColumns(), { emptyText = L["TLP_EMPTY"], memory = "officers.timeline",
		rowSetup = function(row)
			Widgets.Tooltip.Attach(row, function(r)
				return r.data and ns.TimelineCard and ns.TimelineCard.TipOf(r.data.ev) or nil
			end, "LEFT")
		end })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 * View.FILTER_HEIGHT)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
	f.count = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
end

local function refreshTimeline(f, self)
	local filter = self.timeline
	local kinds = { { id = "all", text = L["TLP_ALL"] } }
	for _, k in ipairs(ns.Timeline.KINDS) do kinds[#kinds + 1] = { id = k, text = L["TLP_KIND_" .. k:upper()] } end
	f.kinds:SetItems(kinds, filter.kind)
	local periods = {}
	for _, days in ipairs(View.PERIODS) do periods[#periods + 1] = { id = days, text = L["TLP_DAYS"]:format(days) } end
	f.periods:SetItems(periods, filter.days)
	f.periods:SetWidth(f.periods.width or 10)
	if filter.guids then f.only:SetLabel(L["TLP_ONLY"]:format(escape(filter.who or "?"))) end
	f.only:SetShown(filter.guids ~= nil)
	f.export:SetShown(ns.Export.Allowed())
	self.rows = View.TimelineRows({ kind = filter.kind, days = filter.days, guids = filter.guids, search = self.search })
	f.table:SetData(self.rows, true)
	f.count:SetText(L["TLP_COUNT"]:format(#self.rows))
end

View.AddPage("inactive", { label = L["OFF_PAGE_INACTIVE"], order = 10, build = buildInactive, refresh = refreshInactive })
View.AddPage("timeline", { label = L["OFF_PAGE_TIMELINE"], order = 30, build = buildTimeline, refresh = refreshTimeline })

---------------------------------------------------------------------------------------------------------------------
-- Frames: the view
---------------------------------------------------------------------------------------------------------------------
-- A page may have `visible()` (the Trials page of M12.3: the switch "recruit"); a hidden page is not in the selector.
local function shown(p) return p.visible == nil or p.visible() == true end

local function pageOf(id)
	for _, p in ipairs(View.pages) do if p.id == id and shown(p) then return p end end
	return nil
end

function View:ShowPage(id)
	local def = pageOf(id)
	if not def then return false end
	self.pageId = id
	local f = self.frame
	if not f then return true end
	if not f.holders[id] then
		local holder = CreateFrame("Frame", nil, f)
		holder:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.CHANNEL_HEIGHT)
		holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.holders[id] = holder
		def.build(holder, self)
	end
	for pid, holder in pairs(f.holders) do holder:SetShown(pid == id) end
	if ns.Shell then ns.Shell:PageShown("officers", id) end
	self:Redraw()
	return true
end

function View:Build(f)
	self.frame = f
	f.holders = {}
	f.channel = Widgets.Text(f, "Small", "text-3", "RIGHT")
	f.channel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
	f.channel:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
	f.channel:SetWordWrap(false)
	f:SetScript("OnShow", function()
		if ns.Roster and not f.watching then f.watching = true ns.Roster:Watch() end
		View:Redraw()
	end)
	f:SetScript("OnHide", function()
		if ns.Roster and f.watching then f.watching = nil ns.Roster:Unwatch() end
		Widgets.Menu.Hide()
	end)
	if ns.Roster then f.watching = true ns.Roster:Watch() end
	if not pageOf(self.pageId) then self.pageId = "inactive" end
	self:ShowPage(self.pageId)
end

function View:Redraw()
	local f = self.frame
	if not f or not View.Allowed() then return end
	local holder, def = f.holders[self.pageId], pageOf(self.pageId)
	if not (holder and def) then return end
	f.channel:SetText(View.ChannelText())
	def.refresh(holder, self)
end

function View:OnSearch(text)
	self.search = text or ""
	self:Redraw()
end

-- Opens the tab on one of its pages (the Action Center: "queue", "inactive").
function View:OpenPage(id)
	if not (View.Allowed() and pageOf(id)) then return false end
	self.pageId = id
	if not (ns.Shell and ns.Shell:OpenView("officers")) then return false end
	return self:ShowPage(id)
end

-- The Timeline page on the account of `guid` ("Show all" of the member card).
function View:OpenTimeline(guid, name)
	if not View.Allowed() then return false end
	self.timeline.guids = ns.TimelineCard.GUIDsOf(guid)
	self.timeline.who = name
	self.timeline.kind, self.timeline.days = "all", View.PERIODS[#View.PERIODS]
	self.pageId = "timeline"
	if not (ns.Shell and ns.Shell:Select("officers")) then return false end
	self:ShowPage("timeline")
	return true
end

-- The export of what the page shows now, with its filters and the search (SPEC-12 §6).
function View:OpenExport(kind)
	if not (ns.Export.Allowed() and View.Allowed()) then return nil end
	local items
	if kind == "inactive" then
		local f = self.inactive
		items = ns.Inactivity:Rows({ minTier = f.minTier, away = f.away, unknown = f.unknown, search = self.search })
	elseif kind == "timeline" then
		local f = self.timeline
		items = View.TimelineRows({ kind = f.kind, days = f.days, guids = f.guids, search = self.search })
	else
		return nil
	end
	return ns.ExportBox:Open(kind, items)
end

-- The data changed: one redraw after the burst, only while the view is visible. An officer demoted meanwhile: nothing of
-- the officer data stays on screen.
function View:Changed()
	if self.refreshTimer or not (self.frame and self.frame:IsVisible()) then return end
	self.refreshTimer = true
	local scheduled = ns.Compat and ns.Compat.After(View.REFRESH_DELAY, function()
		View.refreshTimer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.refreshTimer = nil self:Redraw() end
end

if ns.MemberCard then ns.MemberCard.AddSection("absence", 7.5, View.CardSection) end

if ns.Shell then
	ns.Shell:RegisterView("officers", { label = L["VIEW_OFFICERS"], order = 80, search = true, visible = View.Allowed,
		badge = function() return ns.OfficerOps and ns.OfficerOps:OpenCount() or 0 end,
		onSearch = function(text) View:OnSearch(text) end, build = function(f) View:Build(f) end,
		-- the pages are tabs of the Officers destination (M13.7); the open manual actions are on Queue
		pages = function()
			local list = {}
			for _, p in ipairs(View.pages) do if shown(p) then list[#list + 1] = { id = p.id, label = p.label } end end
			return list
		end,
		page = function() return View.pageId end, showPage = function(id) View:ShowPage(id) end,
		pageBadge = function(id) return id == "queue" and ns.OfficerOps and ns.OfficerOps:OpenCount() or 0 end })
end

if ns.addon then
	ns.addon.OfficersView = View
	if ns.Bus then
		local function changed() View:Changed() end
		for _, event in ipairs({ "ROSTER_UPDATED", "ACCOUNTS_UPDATED", "TIMELINE_CHANGED", "OFFICER_PURGED", "DEMO_CHANGED" }) do
			ns.Bus:On(event, changed)
		end
		ns.Bus:On("STORE_CHANGED", function(set)
			if set == "absence" or set == "ocfg" then
				View:Changed()
				if ns.MemberCard then ns.MemberCard:Refresh() end
			end
		end)
		ns.Bus:On("ROLE_CHANGED", function()
			if not View.Allowed() then
				if View.absenceDialog then View.absenceDialog:Close() end
				if View.tiersDialog then View.tiersDialog:Close() end
			end
			View:Changed()
		end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.timeline.guids, View.timeline.who = nil, nil
			if View.absenceDialog then View.absenceDialog:Close() end
			if View.tiersDialog then View.tiersDialog:Close() end
		end)
	end
end

-- Groups: the "Groups" tab, the guild's premade groups panel (SPEC-13 §6.10, M9.7). Lua 5.1.
--
-- Three pages: Groups (the list with its filters and, under it, the chosen listing with Apply or Withdraw), Post a group
-- (the form: Post, Update, Close) and My group (the leader's listing and its applicants, Accept and Decline). The frames
-- only draw: what they show and do is UI/GroupsModel.lua, over Data/Groups.lua. Opening the view asks the guild for the
-- open listings (GASK, at most once every 10 minutes). The tab is there only while the switch `groups` is on.
--   View:ShowPage(id)      "list" | "form" | "mine"
--   View:ShowListing(id)   opens the view on the list with that listing chosen
--   View:ShowMine()        opens the view on the leader's applicants
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.GroupsView, ns.modules = View, ns.modules or {}
ns.modules.GroupsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring
local max = math.max

View.PAGER_HEIGHT = 44
View.CHIP_HEIGHT = 24
View.ROW = 34                 -- a line of the form
View.DETAIL_HEIGHT = 118
View.TICK = 30                -- the ages and the time left move on while the view shows
View.CONFIRM_SECONDS = 8

View.pageId = "list"
View.selected = nil           -- the listing chosen in the list
View.role = nil               -- the role chosen for Apply
View.status = {}              -- page id -> { text, token }: what the last action answered

local function model() return ns.GroupsModel end
local function enabled() return ns.Groups ~= nil and ns.Groups.Enabled() end

local function say(self, page, ok, text)
	self.status[page] = { text = text, token = ok and "ok" or "err" }
end

local function showStatus(fs, status)
	fs:SetText(status and status.text or "")
	Theme.Text(fs, status and status.token or "text-3")
end

-- Chips placed left to right, wrapping at the width of `bar`; each one is on or off by itself. Returns the height used.
local function flowChips(bar, items, onClick)
	bar.buttons = bar.buttons or {}
	local width = bar:GetWidth() or 0
	if width < 100 then width = 700 end
	local x, y = 0, 0
	for i, item in ipairs(items) do
		local c = bar.buttons[i]
		if not c then
			c = Widgets.Chip(bar, { height = View.CHIP_HEIGHT, pad = 18, onClick = function(chip) bar.click(chip.id) end })
			bar.buttons[i] = c
		end
		c.id = item.id
		c:SetLabel(item.text)
		c:SetSelected(item.on)
		local w = c:GetWidth()
		if x > 0 and x + w > width then x, y = 0, y + View.CHIP_HEIGHT + 4 end
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -y)
		x = x + w + 6
		c:Show()
	end
	for i = #items + 1, #bar.buttons do bar.buttons[i]:Hide() end
	bar.click = onClick
	bar:SetHeight(y + View.CHIP_HEIGHT)
	return y + View.CHIP_HEIGHT
end

local function oneLine(fs)
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end

---------------------------------------------------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------------------------------------------------
local function listColumns()
	local function col(id, key, opts)
		opts.id, opts.title, opts.sortable = id, key and L[key] or "", false
		opts.text = opts.text or function(row) return model().Text(row, id) end
		opts.token = opts.token or function(row) return row.status == "open" and "text-1" or "text-3" end
		return opts
	end
	return {
		col("kind", "GRP_COL_KIND", { width = 96 }),
		col("activity", "GRP_COL_ACTIVITY", { flex = 3 }),
		col("levels", "GRP_COL_LEVELS", { width = 56, mono = true }),
		col("roles", "GRP_COL_ROLES", { width = 104 }),
		col("size", "GRP_COL_SIZE", { width = 48, mono = true }),
		col("leader", "GRP_COL_LEADER", { flex = 2 }),
		col("age", "GRP_COL_AGE", { width = 72, mono = true }),
		col("left", "GRP_COL_LEFT", { width = 72, mono = true }),
		col("state", "GRP_COL_STATE", { flex = 2, token = function(row)
			if row.app or row.mine then return "accent-text" end
			return "text-3"
		end }),
	}
end

local function buildDetail(f, self)
	local d = Widgets.Card(f)
	d:SetHeight(View.DETAIL_HEIGHT)
	d:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	local function line(font, token, y)
		local fs = oneLine(Widgets.Text(d, font, token, "LEFT"))
		fs:SetPoint("TOPLEFT", d, "TOPLEFT", 14, y)
		fs:SetPoint("RIGHT", d, "RIGHT", -14, 0)
		return fs
	end
	d.title = line("BodyMedium", "text-1", -10)
	d.title:SetPoint("RIGHT", d, "RIGHT", -304, 0)   -- the state of the application sits at its right
	d.info = line("Small", "text-2", -32)
	d.note = line("Small", "text-3", -50)
	d.roles = Widgets.ChipRow(d, function(id) self.role = id end, { height = 24, gap = 6 })
	d.roles:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 12)
	d.roles:SetSize(240, 24)
	d.comment = Widgets.EditBox(d, { width = 200, height = 28, maxLetters = ns.Groups.MAX_COMMENT, placeholder = L["GRP_COMMENT"] })
	d.comment:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 262, 10)
	d.apply = Widgets.Button(d, { text = L["GRP_APPLY"], style = "primary", height = 28, width = 110, onClick = function()
		say(self, "list", model().Apply(self.selected, self.role, d.comment:GetText()))
		self:Redraw()
	end })
	d.apply:SetPoint("BOTTOMLEFT", d.comment, "BOTTOMRIGHT", 8, 0)
	d.withdraw = Widgets.Button(d, { text = L["GRP_WITHDRAW"], style = "secondary", height = 28, width = 110, onClick = function()
		say(self, "list", model().Withdraw(self.selected))
		self:Redraw()
	end })
	d.withdraw:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 10)
	d.manage = Widgets.Button(d, { text = L["GRP_MANAGE"], style = "secondary", height = 28, width = 160,
		onClick = function() self:ShowPage("mine") end })
	d.manage:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 10)
	d.status = oneLine(Widgets.Text(d, "Small", "text-3", "RIGHT"))
	d.status:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -12)
	d.status:SetWidth(280)
	d:Hide()
	return d
end

local function placeList(f)
	local top = f.kinds:GetHeight() + 8
	f.activity:ClearAllPoints()
	f.activity:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
	f.fits:ClearAllPoints()
	f.fits:SetPoint("LEFT", f.activity, "RIGHT", 8, 0)
	f.roles:ClearAllPoints()
	f.roles:SetPoint("LEFT", f.fits, "RIGHT", 16, 0)
	f.table:ClearAllPoints()
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top - 36)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, f.detail:IsShown() and View.DETAIL_HEIGHT + 8 or 0)
end

local function buildList(f, self)
	f.kinds = CreateFrame("Frame", nil, f)
	f.kinds:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.kinds:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.kinds:SetHeight(View.CHIP_HEIGHT)
	f.kinds:SetScript("OnSizeChanged", function(bar)
		-- only a new width moves the chips: their own height changes while they are placed
		local width = bar:GetWidth()
		if width == bar.width then return end
		bar.width = width
		if f.table then self:Redraw() end
	end)
	f.activity = Widgets.Select(f, { width = 220, rows = 8, onSelect = function(id)
		model().SetActivity(id)
		self:Redraw()
	end })
	f.fits = Widgets.Chip(f, { text = L["GRP_FITS"], height = 28, onClick = function()
		model().SetFits(not model().Filter().fits)
		self:Redraw()
	end })
	f.roles = CreateFrame("Frame", nil, f)
	f.roles:SetSize(300, View.CHIP_HEIGHT)
	f.detail = buildDetail(f, self)
	f.table = Widgets.DataTable(f, listColumns(), { emptyText = L["GRP_EMPTY"],
		onRowClick = function(row) self:Choose(row.id) end,
		rowSetup = function(row)
			row.mark = row:CreateTexture(nil, "BACKGROUND")
			Theme.Fill(row.mark, "accent", 0.16)
			row.mark:SetAllPoints(row)
			row.mark:Hide()
			Widgets.Tooltip.Attach(row, function(r) return r.data and model().TipLines(r.data) or nil end, "LEFT")
		end,
		rowUpdate = function(row, data) row.mark:SetShown(data.id == self.selected) end })
	placeList(f)
end

local function refreshDetail(f, self)
	local d = f.detail
	local info = self.selected and model().Detail(self.selected)
	if not info then
		self.selected = nil
		d:Hide()
		return
	end
	d:Show()
	d.title:SetText(info.title)
	d.info:SetText(info.info)
	d.note:SetText(info.note)
	local known = false
	for _, r in ipairs(info.roles) do
		if r.id == self.role then known = true end
	end
	if not known then self.role = info.preselect end
	d.roles:SetItems(info.roles, self.role)
	d.roles:SetShown(info.canApply)
	d.comment:SetShown(info.canApply)
	d.apply:SetShown(info.canApply)
	d.withdraw:SetShown(info.canWithdraw)
	d.manage:SetShown(info.own and info.row.status == "open")
	local status = self.status.list
	if not status then
		local text = info.hint or info.state
		status = text ~= "" and { text = text, token = info.hint and "text-3" or "accent-text" } or nil
	end
	showStatus(d.status, status)
end

local function refreshList(f, self)
	flowChips(f.kinds, model().KindChips(), function(id)
		model().ToggleKind(id)
		self:Redraw()
	end)
	f.activity:SetChoices(model().ActivityChoices())
	f.activity:Select(model().session.act, true)
	f.fits:SetSelected(model().Filter().fits)
	flowChips(f.roles, model().RoleChoices(), function(id)
		model().ToggleRole(id)
		self:Redraw()
	end)
	refreshDetail(f, self)
	placeList(f)
	self.shown = model().Rows()
	f.table:SetData(self.shown, true)
end

-- A click on a row: that listing shows under the table, with the role preselected for it.
function View:Choose(id)
	if self.selected ~= id then
		self.selected, self.role, self.status.list = id, nil, nil
		local f = self.frame and self.frame.holders.list
		if f then f.detail.comment:SetText("") end
	end
	self:Redraw()
end

---------------------------------------------------------------------------------------------------------------------
-- The form
---------------------------------------------------------------------------------------------------------------------
local FIELDS = { "min", "max", "size", "have", "t", "h", "d", "note", "meet" }

local function formValues(f)
	local v = { kind = f.kind:Selected(), duration = f.chosenDuration }
	if v.kind == "dungeon" or v.kind == "raid" then v.act = f.instance:Selected() else v.act = f.actText:GetText() end
	for _, key in ipairs(FIELDS) do v[key] = f.boxes[key]:GetText() end
	return v
end

local function fillForm(f, v)
	f.kind:Select(v.kind, true)
	local isInstance = v.kind == "dungeon" or v.kind == "raid"
	f.instance:SetShown(isInstance)
	f.actText:SetShown(not isInstance)
	if isInstance then
		f.instance:SetChoices(model().ActivityList(v.kind))
		if v.act then f.instance:Select(v.act, true) end
	else
		f.actText:SetText(type(v.act) == "string" and v.act or "")
	end
	for _, key in ipairs(FIELDS) do f.boxes[key]:SetText(v[key] or "") end
	f.chosenDuration = v.duration
	f.duration:Clear()
	for _, s in ipairs(model().DURATIONS) do
		if s == v.duration then f.duration:Select(s) end
	end
end

local function disarm(f)
	f.armed = false
	f.post:SetLabel(L["GRP_POST"])
end

local function buildForm(f, self)
	local function label(key, x, row)
		local fs = oneLine(Widgets.Text(f, "Small", "text-3", "LEFT"))
		fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(row - 1) * View.ROW - 8)
		fs:SetText(L[key])
		return fs
	end
	local function place(region, x, row)
		region:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(row - 1) * View.ROW - 2)
		return region
	end
	f.boxes = {}
	local function box(key, labelKey, x, row, width, letters, labelWidth)
		local fs = label(labelKey, x, row)
		fs:SetWidth(labelWidth - 6)
		f.boxes[key] = place(Widgets.EditBox(f, { width = width, height = 28, maxLetters = letters }), x + labelWidth, row)
		return f.boxes[key]
	end
	local G = ns.Groups
	local kinds = {}
	for i, kind in ipairs(G.KINDS) do kinds[i] = { id = kind, text = model().KindText(kind) } end

	label("GRP_FIELD_KIND", 0, 1)
	f.kind = place(Widgets.Select(f, { width = 150, rows = 9, choices = kinds, onSelect = function(kind)
		self.status.form = nil
		local v, old = model().Defaults(kind), formValues(f)
		v.note, v.meet, v.duration = old.note, old.meet, old.duration or v.duration
		fillForm(f, v)
		self:Redraw()
	end }), 90, 1)
	label("GRP_FIELD_ACTIVITY", 256, 1)
	f.instance = place(Widgets.Select(f, { width = 270, rows = 8, onSelect = function(id)
		local v, old = model().Defaults(f.kind:Selected(), id), formValues(f)
		f.boxes.min:SetText(v.min)
		f.boxes.max:SetText(v.max)
		f.boxes.size:SetText(v.size)
		for _, r in ipairs(ns.Groups.ROLES) do f.boxes[r]:SetText(v[r]) end
		f.chosenDuration = old.duration
	end }), 336, 1)
	f.actText = place(Widgets.EditBox(f, { width = 270, height = 28, maxLetters = G.MAX_ACT }), 336, 1)

	box("min", "GRP_FIELD_MIN", 0, 2, 50, 3, 90)
	box("max", "GRP_FIELD_MAX", 150, 2, 50, 3, 80)
	box("size", "GRP_FIELD_SIZE", 290, 2, 50, 2, 80)
	box("have", "GRP_FIELD_HAVE", 430, 2, 50, 2, 126)
	f.boxes.have:SetPlaceholder(L["GRP_AUTO"])
	box("t", "GRP_FIELD_TANKS", 0, 3, 50, 2, 90)
	box("h", "GRP_FIELD_HEALERS", 150, 3, 50, 2, 80)
	box("d", "GRP_FIELD_DAMAGE", 290, 3, 50, 2, 80)
	box("note", "GRP_FIELD_NOTE", 0, 4, 516, G.MAX_NOTE, 90)
	box("meet", "GRP_FIELD_MEET", 0, 5, 320, G.MAX_MEET, 90)

	label("GRP_FIELD_DURATION", 0, 6)
	local durations = {}
	for i, s in ipairs(model().DURATIONS) do durations[i] = { id = s, text = model().LeftText(s) } end
	f.duration = place(Widgets.Segmented(f, durations, function(s) f.chosenDuration = s end), 90, 6)

	f.post = place(Widgets.Button(f, { text = L["GRP_POST"], style = "primary", height = 28, width = 210, onClick = function()
		local ok, text, ask = model().Submit(formValues(f), f.armed)
		if ask then
			f.armed = true
			f.post:SetLabel(L["GRP_POST_CONFIRM"])
			ns.Compat.After(View.CONFIRM_SECONDS, function() disarm(f) end)
		else
			disarm(f)
		end
		say(self, "form", ok, text)
		if ask then self.status.form.token = "warn" end
		self:Redraw()
	end }), 90, 7)
	f.update = Widgets.Button(f, { text = L["GRP_UPDATE"], style = "secondary", height = 28, width = 110, onClick = function()
		say(self, "form", model().Update(formValues(f), f.original))
		self:Redraw()
	end })
	f.update:SetPoint("LEFT", f.post, "RIGHT", 8, 0)
	f.close = Widgets.Button(f, { text = L["GRP_CLOSE"], style = "ghost", height = 28, width = 110, onClick = function()
		say(self, "form", model().Close())
		self:Redraw()
	end })
	f.close:SetPoint("LEFT", f.update, "RIGHT", 8, 0)
	f.status = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 90, -7 * View.ROW - 4)
	f.status:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.loaded = false
end

-- What was typed stays: the fields are filled the first time, and again when the player's open listing changes.
local function refreshForm(f, self)
	local own = model().Own()
	local id = own and own.id or "none"
	if f.loaded ~= id then
		local first = f.loaded == false
		f.loaded = id
		if own then
			f.original = model().Values(own)
			fillForm(f, f.original)
		else
			f.original = nil
			if first then fillForm(f, model().Defaults("dungeon")) end
		end
	elseif own then
		-- the group changed (an applicant accepted): the fields the leader did not touch follow it
		local fresh = model().Values(own)
		for _, key in ipairs(FIELDS) do
			if f.boxes[key]:GetText() == f.original[key] then
				f.boxes[key]:SetText(fresh[key])
				f.original[key] = fresh[key]
			end
		end
	end
	f.update:SetShown(own ~= nil)
	f.close:SetShown(own ~= nil)
	showStatus(f.status, self.status.form or (own and { text = L["GRP_OWN_HINT"], token = "text-3" }))
end

---------------------------------------------------------------------------------------------------------------------
-- My group
---------------------------------------------------------------------------------------------------------------------
local function applicantColumns()
	local function col(id, key, opts)
		opts.id, opts.title, opts.sortable = id, key and L[key] or "", false
		opts.text = opts.text or function(a) return model().ApplicantText(a, id) end
		return opts
	end
	return {
		col("name", "GRP_COL_NAME", { flex = 2, render = function(fs, a)
			fs:SetText(model().ApplicantText(a, "name"))
			Widgets.PaintName(fs, a.classFile)
		end }),
		col("class", "GRP_COL_CLASS", { flex = 1 }),
		col("level", "GRP_COL_LEVEL", { width = 52, mono = true }),
		col("role", "GRP_COL_ROLE", { width = 96 }),
		col("comment", "GRP_COL_COMMENT", { flex = 3, token = function() return "text-2" end }),
		col("age", "GRP_COL_AGE", { width = 72, mono = true, token = function() return "text-3" end }),
		col("buttons", nil, { width = 176, text = function() return "" end }),
	}
end

local function applicantRow(self, row)
	local function button(key, style, x, action)
		local b = Widgets.Button(row, { text = L[key], style = style, height = 22, width = 80, onClick = function()
			if not row.data then return end
			say(self, "mine", model()[action](row.data.applicant))
			self:Redraw()
		end })
		b:SetPoint("RIGHT", row, "RIGHT", x, 0)
		return b
	end
	row.decline = button("GRP_DECLINE", "ghost", -8, "Decline")
	row.accept = button("GRP_ACCEPT", "primary", -92, "Accept")
end

local function buildMine(f, self)
	f.title = oneLine(Widgets.Text(f, "BodyMedium", "text-1", "LEFT"))
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
	f.title:SetPoint("RIGHT", f, "RIGHT", -150, 0)
	f.info = oneLine(Widgets.Text(f, "Small", "text-2", "LEFT"))
	f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -26)
	f.info:SetPoint("RIGHT", f, "RIGHT", -150, 0)
	f.close = Widgets.Button(f, { text = L["GRP_CLOSE"], style = "secondary", height = 28, width = 140, onClick = function()
		say(self, "mine", model().Close())
		self:Redraw()
	end })
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -6)
	f.table = Widgets.DataTable(f, applicantColumns(), { emptyText = L["GRP_NO_APPLICANTS"],
		rowSetup = function(row)
			applicantRow(self, row)
			Widgets.Tooltip.Attach(row, function(r)
				local a = r.data
				return a and { model().ApplicantText(a, "name"), a.comment and model().ApplicantText(a, "comment") or nil } or nil
			end, "LEFT")
		end })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -50)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
	f.status = oneLine(Widgets.Text(f, "Small", "text-3", "LEFT"))
	f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	f.status:SetPoint("RIGHT", f, "RIGHT", 0, 0)
end

local function refreshMine(f, self)
	local own = model().Own()
	if own then
		local d = model().Detail(own.id)
		f.title:SetText(d.title)
		f.info:SetText(d.info)
		f.table.empty:SetText(L["GRP_NO_APPLICANTS"])
	else
		f.title:SetText(L["GRP_NO_OWN"])
		f.info:SetText("")
		f.table.empty:SetText("")
	end
	f.close:SetShown(own ~= nil)
	self.shownApplicants = model().ApplicantRows()
	f.table:SetData(self.shownApplicants, true)
	showStatus(f.status, self.status.mine)
end

---------------------------------------------------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------------------------------------------------
View.pages = {
	{ id = "list", label = "GRP_PAGE_LIST", build = buildList, refresh = refreshList },
	{ id = "form", label = "GRP_PAGE_FORM", build = buildForm, refresh = refreshForm },
	{ id = "mine", label = "GRP_PAGE_MINE", build = buildMine, refresh = refreshMine },
}

local function pageOf(id)
	for _, p in ipairs(View.pages) do
		if p.id == id then return p end
	end
	return nil
end

function View:ShowPage(id)
	local def = pageOf(id)
	if not def then return false end
	if self.pageId ~= id then self.status = {} end
	self.pageId = id
	local f = self.frame
	if not f then return true end
	if not f.holders[id] then
		local holder = CreateFrame("Frame", nil, f)
		holder:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.PAGER_HEIGHT)
		holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.holders[id] = holder
		def.build(holder, self)
	end
	for pid, holder in pairs(f.holders) do holder:SetShown(pid == id) end
	f.pager:Select(id)
	self:Redraw()
	return true
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local n = model().ApplicantCount()
	f.pager:SetItemText("mine", n > 0 and L["GRP_PAGE_MINE_COUNT"]:format(n) or L["GRP_PAGE_MINE"])
	local holder, def = f.holders[self.pageId], pageOf(self.pageId)
	if holder and def then def.refresh(holder, self) end
end

-- While the view is on screen the roster is watched (who is online decides what is open) and the ages move on.
local function watch(f, on)
	if on and not f.ticker then
		if ns.Roster then ns.Roster:Watch() end
		f.ticker = ns.Compat.NewTicker(View.TICK, function() View:Redraw() end) or true
	elseif not on and f.ticker then
		if ns.Roster then ns.Roster:Unwatch() end
		if type(f.ticker) == "table" then f.ticker:Cancel() end
		f.ticker = nil
	end
end

local function opened(f)
	watch(f, true)
	ns.Groups:Ask()   -- the listings posted while this client was away (SPEC-13 §6.7)
	View:Redraw()
end

function View:Build(f)
	self.frame = f
	f.holders = {}
	local items = {}
	for i, p in ipairs(View.pages) do items[i] = { id = p.id, text = L[p.label] } end
	f.pager = Widgets.Segmented(f, items, function(id) if id ~= View.pageId then View:ShowPage(id) end end)
	f.pager:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f:SetScript("OnShow", function() opened(f) end)
	f:SetScript("OnHide", function() watch(f, false) end)
	self:ShowPage(self.pageId)
	opened(f)
end

function View:Search(text)
	model().SetSearch(text)
	if self.pageId ~= "list" then self:ShowPage("list") else self:Redraw() end
end

function View:Open(page)
	self.pageId = page
	self.status = {}
	if not (ns.Shell and ns.Shell:OpenView("groups")) then return false end
	return self:ShowPage(page)
end

function View:ShowListing(id)
	if not enabled() then return false end
	if id then
		-- the filters must not hide the listing a notice is about
		model().ResetSession()
		self.selected, self.role = id, nil
	end
	return self:Open("list")
end

function View:ShowMine()
	if not enabled() then return false end
	return self:Open("mine")
end

-- A listing, an application or the roster changed: the badge, and the page when it is on screen.
function View:Changed()
	if not enabled() then return end
	if ns.Shell then ns.Shell:UpdateBadges() end
	if self.frame and self.frame:IsVisible() then self:Redraw() end
end

if ns.Shell then
	ns.Shell:RegisterView("groups", { label = L["VIEW_GROUPS"], order = 40, search = true, visible = enabled,
		badge = function() return enabled() and model().ApplicantCount() or 0 end,
		onSearch = function(text) View:Search(text) end, build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.GroupsView = View
	if ns.Bus then
		ns.Bus:On("GROUPS_CHANGED", function() View:Changed() end)
		ns.Bus:On("APPLICANTS_CHANGED", function() View:Changed() end)
		ns.Bus:On("ROSTER_UPDATED", function() View:Changed() end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.selected, View.role, View.status = nil, nil, {}
			local form = View.frame and View.frame.holders.form
			if form then form.loaded = false end
		end)
	end
end

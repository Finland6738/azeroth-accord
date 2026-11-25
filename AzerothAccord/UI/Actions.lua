-- Actions: the "Action Center" tab and its Inbox page (SPEC-13 §2.4, M9.2). Lua 5.1.
--
-- On top the chips of the providers (All, then one per provider present), under them the table: the mark of the urgency
-- (err now, accent to do, text-3 reminder), what, the detail, who and since when. A click on a row opens the view that
-- resolves it; Done shows only on a local reminder. Further pages (Notices, M9.3) register with View.AddPage and a
-- selector appears. The tab is there only while the switch `actions` is on.
--   View.Rows(filter)           the rows of the list, of one provider or of all ("all")
--   View.Chips()                the filter chips: { { id, text } }
--   View.Text(row, column, t)   the text of a cell (plain, tested offline)
--   View.TipLines(row)          the lines of a row's tooltip
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.ActionsView, ns.modules = View, ns.modules or {}
ns.modules.ActionsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring = type, ipairs, tostring

View.PAGER_HEIGHT = 44
View.FILTER_HEIGHT = 36
View.MARK_SIZE = 8
View.URGENCY_TOKEN = { [1] = "text-3", [2] = "accent", [3] = "err" }

View.pages = {}            -- { id, label, order, build(frame, view), refresh(frame, view) }
View.pageId = "inbox"
View.filter = "all"

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

local function enabled() return ns.Actions ~= nil and ns.Actions.Enabled() end

---------------------------------------------------------------------------------------------------------------------
-- Rows and texts
---------------------------------------------------------------------------------------------------------------------
function View.Chips()
	local out = { { id = "all", text = L["ACT_ALL"] } }
	for _, def in ipairs(ns.Actions and ns.Actions:Providers() or {}) do
		out[#out + 1] = { id = def.id, text = def.label and L[def.label] or def.id }
	end
	return out
end

function View.Rows(filter)
	local out = {}
	for _, r in ipairs(ns.Actions and ns.Actions:Rows() or {}) do
		if filter == nil or filter == "all" or r.provider == filter then out[#out + 1] = r end
	end
	return out
end

function View.UrgencyText(urgency) return L["ACT_URGENCY_" .. tostring(urgency)] end

function View.Text(r, column, t)
	if column == "title" then return escape(r.title) end
	if column == "detail" then return r.detail and escape(r.detail) or "" end
	if column == "who" then return r.who and escape(r.who) or "" end
	if column == "age" then return ns.Provenance.AgeText(math.max(0, (t or now()) - r.time)) end
	return ""
end

function View.TipLines(r)
	local tip = { escape(r.title), { text = View.UrgencyText(r.urgency), token = View.URGENCY_TOKEN[r.urgency] } }
	if r.detail then tip[#tip + 1] = escape(r.detail) end
	if r.who then tip[#tip + 1] = escape(r.who) end
	if r.label then tip[#tip + 1] = { text = L[r.label], token = "text-3" } end
	return tip
end

---------------------------------------------------------------------------------------------------------------------
-- Frames: the Inbox page
---------------------------------------------------------------------------------------------------------------------
local function columns()
	local function col(id, key, opts)
		opts.id, opts.title, opts.sortable = id, key and L[key] or "", false
		opts.text = opts.text or function(r) return View.Text(r, id) end
		return opts
	end
	return {
		-- the mark and the Done button are drawn by rowSetup and rowUpdate: their cells stay empty
		col("mark", nil, { width = 20, text = function() return "" end }),
		col("title", "ACT_COL_WHAT", { flex = 3 }),
		col("detail", "ACT_COL_DETAIL", { flex = 2, token = function() return "text-3" end }),
		col("who", "ACT_COL_WHO", { flex = 1 }),
		col("age", "ACT_COL_AGE", { width = 80, mono = true, token = function() return "text-3" end }),
		col("done", nil, { width = 80, text = function() return "" end }),
	}
end

local function setupRow(self, row)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetSize(View.MARK_SIZE, View.MARK_SIZE)
	row.mark:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.mark:SetTexture(ns.Assets.textures.circle.path)
	row.done = Widgets.Button(row, { text = L["ACT_DONE"], style = "secondary", height = 22, width = 68, onClick = function()
		if row.data then ns.Actions:Dismiss(row.data) end
		self:Redraw()
	end })
	row.done:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.done:Hide()
	Widgets.Tooltip.Attach(row, function(r) return r.data and View.TipLines(r.data) or nil end, "LEFT")
end

local function updateRow(row, data)
	Theme.Tint(row.mark, View.URGENCY_TOKEN[data.urgency] or "text-3")
	row.done:SetShown(data.dismiss ~= nil)
end

local function buildInbox(f, self)
	f.chips = Widgets.ChipRow(f, function(id)
		self.filter = id
		self:Redraw()
	end, { height = 26, gap = 6 })
	f.chips:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.chips:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.table = Widgets.DataTable(f, columns(), { emptyText = L["ACT_EMPTY"],
		onRowClick = function(r) ns.Actions:Open(r) end,
		rowSetup = function(row) setupRow(self, row) end, rowUpdate = updateRow })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.FILTER_HEIGHT)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

local function refreshInbox(f, self)
	local chips, known = View.Chips(), false
	for _, c in ipairs(chips) do if c.id == self.filter then known = true end end
	if not known then self.filter = "all" end
	f.chips:SetItems(chips, self.filter)
	self.shown = View.Rows(self.filter)
	f.table:SetData(self.shown, true)
end

View.AddPage("inbox", { label = L["ACT_PAGE_INBOX"], order = 10, build = buildInbox, refresh = refreshInbox })

---------------------------------------------------------------------------------------------------------------------
-- Frames: the view
---------------------------------------------------------------------------------------------------------------------
local function pageOf(id)
	for _, p in ipairs(View.pages) do if p.id == id then return p end end
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
		holder:SetPoint("TOPLEFT", f, "TOPLEFT", 0, f.pager and -View.PAGER_HEIGHT or 0)
		holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.holders[id] = holder
		def.build(holder, self)
	end
	for pid, holder in pairs(f.holders) do holder:SetShown(pid == id) end
	if f.pager then f.pager:Select(id) end
	self:Redraw()
	return true
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local holder, def = f.holders[self.pageId], pageOf(self.pageId)
	if holder and def then def.refresh(holder, self) end
end

-- While the view is on screen the roster is watched (names) and the ages move on once a minute.
local function watch(f, on)
	if on and not f.ticker then
		if ns.Roster then ns.Roster:Watch() end
		f.ticker = ns.Compat.NewTicker(ns.Actions.TICK, function() View:Redraw() end) or true
	elseif not on and f.ticker then
		if ns.Roster then ns.Roster:Unwatch() end
		if type(f.ticker) == "table" then f.ticker:Cancel() end
		f.ticker = nil
	end
end

function View:Build(f)
	self.frame = f
	f.holders = {}
	if #View.pages > 1 then
		local items = {}
		for i, p in ipairs(View.pages) do items[i] = { id = p.id, text = p.label } end
		f.pager = Widgets.Segmented(f, items, function(id) if id ~= View.pageId then View:ShowPage(id) end end)
		f.pager:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	end
	f:SetScript("OnShow", function()
		watch(f, true)
		ns.Actions:Refresh()   -- ACT-03: read again when the view opens
		View:Redraw()
	end)
	f:SetScript("OnHide", function() watch(f, false) end)
	watch(f, true)
	ns.Actions:Refresh()
	self:ShowPage(self.pageId)
end

-- The list changed: the badge, and the table when it is on screen (the events are already collected by Data/Actions.lua).
function View:Changed()
	if ns.Shell then ns.Shell:UpdateBadges() end
	if self.frame and self.frame:IsVisible() then self:Redraw() end
end

if ns.Shell then
	ns.Shell:RegisterView("actions", { label = L["VIEW_ACTIONS"], order = 5, visible = enabled,
		badge = function() return ns.Actions:Count() end, build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.ActionsView = View
	-- an item name that arrives late changes the title of a bank row
	LibStub("AceEvent-3.0"):Embed(View)
	pcall(View.RegisterEvent, View, "GET_ITEM_INFO_RECEIVED", function() if ns.Actions then ns.Actions:Changed() end end)
	if ns.Bus then
		ns.Bus:On("ACTIONS_CHANGED", function() View:Changed() end)
		ns.Bus:On("GUILD_CHANGED", function() View.filter = "all" end)
	end
end

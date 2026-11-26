-- Handbook view: the page list and the reader of the guild handbook (M11.3, SPEC-15 §5). Lua 5.1.
--
-- Left   the pages in their order, each with its mark (Updated; for a writer also Template and Over the limit), or the
--        results while the search box of the panel holds 2 characters or more; under them "Mark all as read".
-- Right  Back (after a link), the title, "Updated <date> by <name>", and the text in a frame that scrolls: one SimpleHTML
--        per block (Data/HandbookText.lua), so the reader knows where each heading and line is. A link to a page the
--        reader cannot open is grey text; a web address opens the copy box (the game opens no browser).
-- Read   a page that stays open for READ_DELAY seconds is marked read (Data/Handbook.lua), never by passing through.
-- Every member reads every published page from what this client holds, with or without anybody else online. What a
-- writer gets on top of this (the editor, the revisions, New page, Writers: M11.4) is UI/HandbookEditor.lua; the loot
-- page's fixed part (M11.6) comes later. This file writes no page.
-- Everything is behind the switch "raid" (Core/Features.lua): off, there is no tab and no command.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.HandbookView, ns.modules = View, ns.modules or {}
ns.modules.HandbookView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tonumber, floor, ceil, max, min = type, ipairs, tonumber, math.floor, math.ceil, math.max, math.min
local date, remove = date, table.remove

View.READ_DELAY = 2         -- seconds a page stays open before it counts as read
View.HISTORY = 20           -- steps Back remembers
View.ROW_HEIGHT = 30
View.RESULT_HEIGHT = 44
View.LIST_WIDTH, View.LIST_NARROW, View.NARROW = 220, 170, 640
View.GAP = 16               -- between the list and the reader
View.HEADER = 58            -- the reader's title and its line
View.WIDTH = 420            -- the text's width while the frame has none yet
View.WHEEL_STEP = 40

View.search = ""
View.history = {}
View.version = 0            -- of the pages held: the reader draws again when it moves

local function enabled() return ns.Handbook ~= nil and ns.Handbook.Enabled() end
local function book() return ns.Handbook end

---------------------------------------------------------------------------------------------------------------------
-- What the view shows
---------------------------------------------------------------------------------------------------------------------
-- The pages this character reads, in order: { { id, rec, title, mark = "over" | "template" | "updated" | nil } }, and
-- the same by id. A writer also sees the templates and the pages over the limit.
function View.Rows()
	local rows, byId = {}, {}
	if not enabled() then return rows, byId end
	local writer = book():CanWrite()
	local pages, _, over = book():Pages(writer)
	local function add(rec, mark)
		local row = { id = rec.id, rec = rec, title = rec.title, mark = mark }
		rows[#rows + 1], byId[rec.id] = row, row
	end
	for _, rec in ipairs(pages) do
		add(rec, rec.tpl and "template" or (book():IsUpdated(rec) and "updated") or nil)
	end
	if writer then
		for _, rec in ipairs(over) do add(rec, "over") end
	end
	return rows, byId
end

-- What a link or a web address of a page shows: its label, and the target when it can be followed.
function View.Resolve(part, byId)
	if part.kind == "url" then return part.text, { url = part.url } end
	local link = part.link
	if link.special == "season" then
		local views = ns.Shell and ns.Shell.views or {}
		local there = ns.Shell ~= nil and ns.Shell.Visible(views.season)
		return link.label or L["VIEW_SEASON"], there and { season = true } or nil
	end
	byId = byId or select(2, View.Rows())
	local row = byId["P:" .. link.slug]
	-- a template is not published: nobody follows a link to it
	if row and not row.rec.tpl then
		return link.label or row.title, { id = row.id, heading = link.heading }
	end
	return link.label or link.heading or link.slug, nil
end

-- The matches of the search box, or nil while it holds too little.
function View.Results(rows)
	local pages = {}
	for i, row in ipairs(rows) do pages[i] = row.rec end
	local byId = {}
	for _, row in ipairs(rows) do byId[row.id] = row end
	return ns.HandbookText.Search(View.search, pages, function(part) return (View.Resolve(part, byId)) end)
end

function View.Meta(rec)
	return L["HANDBOOK_META"]:format(date("%Y-%m-%d", rec.time), book().NameOf(rec.author))
end

local function hex(token)
	local r, g, b = Theme.Color(token)
	return ("%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

---------------------------------------------------------------------------------------------------------------------
-- Scrolling
---------------------------------------------------------------------------------------------------------------------
local function scroller(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(View.WIDTH, 1)
	scroll:SetScrollChild(page)
	scroll:EnableMouseWheel(true)
	scroll.page, scroll.height = page, 0
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:ScrollTo((self:GetVerticalScroll() or 0) - delta * View.WHEEL_STEP)
	end)
	function scroll:ScrollTo(y)
		local range = max(0, self.height - (self:GetHeight() or 0))
		self:SetVerticalScroll(min(range, max(0, y)))
	end
	function scroll:SetContentHeight(h)
		self.height = h
		self.page:SetHeight(max(1, h))
		if self.UpdateScrollChildRect then self:UpdateScrollChildRect() end
		self:ScrollTo(self:GetVerticalScroll() or 0)
	end
	return scroll
end

---------------------------------------------------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------------------------------------------------
local MARKS = {
	updated = { key = "HANDBOOK_UPDATED", token = "accent-text" },
	template = { key = "HANDBOOK_TEMPLATE", token = "warn" },
	over = { key = "HANDBOOK_OVER", token = "err" },
	deleted = { key = "HANDBOOK_DELETED", token = "err" },
}

local function listRow(f, i)
	local b = f.rows[i]
	if b then return b end
	b = CreateFrame("Button", nil, f.list.page)
	b.selected = b:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(b.selected, "accent", 0.16)
	b.selected:SetAllPoints(b)
	Widgets.RowHover(b)
	b.mark = Widgets.Text(b, "Small", "accent-text", "RIGHT")
	b.mark:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -9)
	b.label = Widgets.Text(b, "Body", "text-1", "LEFT")
	b.label:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -8)
	b.label:SetWordWrap(false)
	b.sub = Widgets.Text(b, "Small", "text-3", "LEFT")
	b.sub:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -26)
	b.sub:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -26)
	b.sub:SetWordWrap(false)
	b:SetScript("OnClick", function(self)
		if not self.id then return end
		if self.deleted then View:OpenRevisions(self.id) else View:Show(self.id, { line = self.line }) end
	end)
	f.rows[i] = b
	return b
end

local function drawList(f, rows)
	local results = View.Results(rows)
	View.results = results
	local items = results or rows
	local editor = ns.HandbookEditor
	if editor and not results then items = editor:ListItems(rows) end
	local selected = View.revisions and View.revisions.id or View.selected
	local height = results and View.RESULT_HEIGHT or View.ROW_HEIGHT
	for i, item in ipairs(items) do
		local b = listRow(f, i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f.list.page, "TOPLEFT", 0, -(i - 1) * height)
		b:SetPoint("TOPRIGHT", f.list.page, "TOPRIGHT", 0, -(i - 1) * height)
		b:SetHeight(height)
		b.id, b.line, b.deleted = item.id, results and item.line or nil, item.deleted
		local mark = not results and item.mark and MARKS[item.mark]
		b.mark:SetText(mark and L[mark.key] or "")
		if mark then Theme.Text(b.mark, mark.token) end
		b.label:SetPoint("TOPRIGHT", b.mark, "TOPLEFT", -6, 1)
		b.label:SetText(item.heading and (item.title .. " · " .. item.heading) or item.title)
		b.sub:SetText(results and item.text or "")
		b.sub:SetShown(results ~= nil)
		Theme.Text(b.label, item.header and "accent-text" or "text-1")
		b.selected:SetShown(not results and item.id ~= nil and item.id == selected)
		b:Show()
		if editor then editor:Row(f, b, item, results ~= nil) end
	end
	for i = #items + 1, #f.rows do f.rows[i]:Hide() end
	local note = ""
	if results and #results == 0 then note = L["HANDBOOK_NO_MATCH"]
	elseif not results and View.search:match("%S") then note = L["HANDBOOK_SEARCH_SHORT"] end
	f.note:SetText(note)
	f.note:SetShown(note ~= "")
	-- the hint of a short search sits under the pages, "nothing found" where the results would be
	f.note:ClearAllPoints()
	local y = -(#items * height) - 8
	f.note:SetPoint("TOPLEFT", f.list.page, "TOPLEFT", 8, y)
	f.note:SetPoint("TOPRIGHT", f.list.page, "TOPRIGHT", -8, y)
	f.list:SetContentHeight(#items * height + (note ~= "" and 28 or 0))
end

---------------------------------------------------------------------------------------------------------------------
-- The reader
---------------------------------------------------------------------------------------------------------------------
-- Per kind: the space above, and the height of a line when the game does not say how high the block is.
local KINDS = {
	h1 = { above = 14, line = 20 }, h2 = { above = 12, line = 18 }, p = { above = 8, line = 16 },
	li = { above = 3, line = 16 }, oli = { above = 3, line = 16 },
}
local INDENT = 14

local function estimate(block, width)
	local perLine = max(1, floor(width / 7))
	return max(1, ceil(#block.text / perLine)) * KINDS[block.kind].line
end

local function paintBlock(h)
	local r, g, b = Theme.Color("text-1")
	h:SetTextColor("p", r, g, b)
	h:SetTextColor("h1", r, g, b)
	h:SetTextColor("h2", r, g, b)
	if not h.block then return end
	local html, links = ns.HandbookText.HTML(h.block, function(part) return View.Resolve(part, View.byId) end,
		{ link = hex("accent-text"), missing = hex("text-3") })
	h.links = links
	h:SetText(html)
end

local function blockFrame(f, i)
	local h = f.blocks[i]
	if h then return h end
	h = CreateFrame("SimpleHTML", nil, f.text.page)
	h:SetFontObject("p", Theme.Font("Body"))
	h:SetFontObject("h1", Theme.Font("H1"))
	h:SetFontObject("h2", Theme.Font("H2"))
	if h.SetHyperlinksEnabled then h:SetHyperlinksEnabled(true) end
	h:SetScript("OnHyperlinkClick", function(self, link)
		local n = type(link) == "string" and tonumber(link:match("^acc:(%d+)$"))
		if not (n and self.links and self.links[n]) then return end
		if f.follow then f.follow(self.links[n]) else View:Follow(self.links[n]) end
	end)
	f.blocks[i] = h
	Theme.Call(h, paintBlock)
	return h
end

-- Puts the blocks one under the other, at the height the game gives each.
local function placeBlocks(f)
	local width = f.textWidth or View.WIDTH
	local y = 0
	for i = 1, f.shown or 0 do
		local h = f.blocks[i]
		local block = h.block
		local indent = block.level and (block.level - 1) * INDENT + 6 or 0
		if i > 1 then y = y + KINDS[block.kind].above end
		local height = h.GetContentHeight and h:GetContentHeight()
		if type(height) ~= "number" or height <= 0 then height = estimate(block, width - indent) end
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", f.text.page, "TOPLEFT", indent, -y)
		h:SetSize(width - indent, height)
		h.y = y
		y = y + height
	end
	f.text:SetContentHeight(y + 8)
end

local function drawText(f, rec)
	local width = f.text:GetWidth() or 0
	if width <= 0 then width = View.WIDTH end
	local key = table.concat({ rec.id, rec.rev, rec.time, View.version, floor(width) }, "|")
	if f.textKey == key then return end
	local same = f.textId == rec.id
	f.textKey, f.textId, f.textWidth = key, rec.id, width
	f.text.page:SetWidth(width)
	local blocks = ns.HandbookText.Blocks(ns.HandbookText.Clean(rec.body))
	for i, block in ipairs(blocks) do
		local h = blockFrame(f, i)
		local indent = block.level and (block.level - 1) * INDENT + 6 or 0
		h.block = block
		h:SetSize(width - indent, estimate(block, width - indent))
		paintBlock(h)
		h:Show()
	end
	for i = #blocks + 1, #f.blocks do
		f.blocks[i].block = nil
		f.blocks[i]:Hide()
	end
	f.shown = #blocks
	f.blank:SetShown(#blocks == 0)
	if not same then f.text:SetVerticalScroll(0) end
	placeBlocks(f)
	-- the game knows the height of a new text only once it has laid it out
	ns.Compat.After(0, function()
		if f.textKey == key then placeBlocks(f) end
	end)
end

-- Scrolls to the heading or the line asked for when the page was opened.
function View:ApplyAnchor()
	local f, a = self.frame, self.anchor
	if not (f and a and a.id == f.textId) then return end
	local fold = ns.HandbookText.Fold
	for i = 1, f.shown or 0 do
		local h = f.blocks[i]
		local block = h.block
		local hit
		if a.heading then
			hit = (block.kind == "h1" or block.kind == "h2")
				and fold(ns.HandbookText.Plain(block.text)) == fold(a.heading)
		elseif a.line then
			hit = a.line >= block.line and a.line <= block.last
		end
		if hit then
			f.text:ScrollTo(h.y or 0)
			return
		end
	end
end

-- The editor and the revisions draw their previews with the reader's parts. A `pane` is a table with `text` (a
-- Scroller), `blocks` = {}, `blank` (shown for an empty text) and optionally `follow(target)` for its links.
View.Scroller, View.DrawText = scroller, drawText

local function drawReader(f, row)
	f.reader:SetShown(row ~= nil)
	if not row then return end
	local rec = row.rec
	local back = #View.history > 0
	f.back:SetShown(back)
	f.title:ClearAllPoints()
	if back then f.title:SetPoint("TOPLEFT", f.back, "TOPRIGHT", 10, -4)
	else f.title:SetPoint("TOPLEFT", f.reader, "TOPLEFT", 0, -4) end
	f.title:SetPoint("TOPRIGHT", f.reader, "TOPRIGHT", 0, -4)
	f.title:SetText(rec.title)
	local meta = View.Meta(rec)
	if rec.tpl then meta = meta .. " · " .. L["HANDBOOK_TEMPLATE_NOTE"] end
	f.meta:SetText(meta)
	drawText(f, rec)
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
function View:StopReading()
	if self.timer then self.timer:Cancel() end
	self.timer, self.timerKey = nil, nil
end

-- Starts the clock of the open page when it is updated; the same page and revision keep their clock.
function View:Watch()
	local f = self.frame
	local rec = f and f:IsVisible() and not (self.editor or self.revisions) and self.selected and enabled()
		and book():Get(self.selected)
	if not (rec and book():IsUpdated(rec)) then return self:StopReading() end
	local id, key = rec.id, rec.id .. "#" .. rec.rev
	if self.timerKey == key then return end
	self:StopReading()
	self.timerKey = key
	self.timer = ns.Compat.NewTimer(View.READ_DELAY, function()
		View.timer, View.timerKey = nil, nil
		local held = View.frame and View.frame:IsVisible() and View.selected == id and book():Get(id)
		if held and held.rev == rec.rev then book():MarkRead(id) end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------------------------------------------------
local function layout(f)
	local width = f:GetWidth() or 0
	local list = (width > 0 and width < View.NARROW) and View.LIST_NARROW or View.LIST_WIDTH
	f.list:ClearAllPoints()
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, f.listBottom or 40)
	f.list:SetWidth(list)
	f.list.page:SetWidth(list)
	f.listWidth = list
end
View.Layout = layout

function View:Redraw()
	local f = self.frame
	if not (f and enabled()) then return end
	local rows, byId = View.Rows()
	self.byId = byId
	if not (self.selected and byId[self.selected]) then
		local hb = book().LocalData()
		local last = hb and hb.last
		self.selected = (last and byId[last] and last) or (rows[1] and rows[1].id) or nil
	end
	local editor = ns.HandbookEditor
	-- the editor takes the whole view while it is open
	if editor and editor:Cover(f) then return self:Watch() end
	local empty = #rows == 0 and not (editor and #editor:ListItems(rows) > 0)
	f.empty:SetShown(#rows == 0 and not self.revisions)
	f.list:SetShown(not empty)
	f.markAll:SetShown(not empty)
	f.markAll:SetEnabled(#book():Updated() > 0)
	if empty then
		f.reader:Hide()
	else
		drawList(f, rows)
		drawReader(f, byId[self.selected])
	end
	if editor then editor:Decorate(f, byId[self.selected]) end
	self:Watch()
end

local function remember(id)
	local hb = book().LocalData()
	if hb then hb.last = id end
end

-- Opens a page in the reader. opts: heading, line (where to scroll), follow (a link: Back returns here).
function View:Show(id, opts)
	opts = opts or {}
	local byId = select(2, View.Rows())
	if not byId[id] then return false end
	local f = self.frame
	if opts.follow then
		if self.selected and self.selected ~= id then
			local h = self.history
			h[#h + 1] = { id = self.selected, scroll = f and f.text:GetVerticalScroll() or 0 }
			while #h > View.HISTORY do remove(h, 1) end
		end
	else
		self.history = {}
	end
	self.selected, self.revisions = id, nil
	self.anchor = (opts.heading or opts.line) and { id = id, heading = opts.heading, line = opts.line } or nil
	remember(id)
	if f then
		if not self.anchor then f.text:SetVerticalScroll(0) end
		self:Redraw()
		self:ApplyAnchor()
		-- once more when the game has laid the text out, and then the page is the reader's to scroll
		local anchor = self.anchor
		if anchor then
			ns.Compat.After(0, function()
				if View.anchor ~= anchor then return end
				View:ApplyAnchor()
				View.anchor = nil
			end)
		end
	end
	return true
end

-- A click on a link or a web address of the text.
function View:Follow(target)
	if target.url then
		if ns.CopyBox then ns.CopyBox:Open(target.url, L["HANDBOOK_LINK_URL"]) end
	elseif target.season then
		if ns.Shell then ns.Shell:Select("season") end
	elseif target.id then
		self:Show(target.id, { heading = target.heading, follow = true })
	end
end

-- Back to the page a link was followed from (a page that is gone meanwhile is skipped).
function View:Back()
	local byId = select(2, View.Rows())
	while #self.history > 0 do
		local step = remove(self.history)
		if byId[step.id] then
			self.selected, self.anchor = step.id, nil
			remember(step.id)
			self:Redraw()
			if self.frame then self.frame.text:ScrollTo(step.scroll or 0) end
			return true
		end
	end
	self:Redraw()
	return false
end

-- Opens the panel on this view, on the page `id` when given (the Action Center, the conflict notice).
function View:Open(id)
	if not (ns.Shell and ns.Shell:OpenView("handbook")) then return false end
	if id then return self:Show(id) end
	return true
end

-- `/accord handbook [slug]`
function View.Command(input)
	local slug = type(input) == "string" and input:match("^%s*%S+%s+(%S+)") or nil
	if not (View:Open() and slug) then return end
	if not View:Show("P:" .. slug:lower()) and ns.addon then ns.addon:Print(L["HANDBOOK_NO_PAGE"]:format(slug)) end
end

function View:Search(text)
	self.search = text or ""
	if self.frame then
		self.frame.list:SetVerticalScroll(0)
		self:Redraw()
	end
end

-- While the view is on screen the roster is watched: it gives the writers' names and ranks.
local function watch(f, on)
	if on and not f.watching then
		f.watching = true
		if ns.Roster then ns.Roster:Watch() end
	elseif not on and f.watching then
		f.watching = false
		if ns.Roster then ns.Roster:Unwatch() end
	end
end

function View:Build(f)
	self.frame = f
	f.rows, f.blocks = {}, {}
	f.empty = Widgets.Text(f, "Body", "text-2", "CENTER")
	f.empty:SetPoint("TOP", f, "TOP", 0, -60)
	f.empty:SetText(L["HANDBOOK_EMPTY"])
	f.list = scroller(f)
	f.note = Widgets.Text(f.list.page, "Small", "text-3", "LEFT")
	f.markAll = Widgets.Button(f, { text = L["HANDBOOK_MARK_ALL"], style = "secondary", height = 28,
		onClick = function() book():MarkAllRead() end })
	f.markAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 4)
	layout(f)
	f.reader = CreateFrame("Frame", nil, f)
	f.reader:SetPoint("TOPLEFT", f.list, "TOPRIGHT", View.GAP, 0)
	f.reader:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.back = Widgets.Button(f.reader, { text = L["HANDBOOK_BACK"], style = "ghost", height = 26,
		onClick = function() View:Back() end })
	f.back:SetPoint("TOPLEFT", f.reader, "TOPLEFT", 0, 0)
	f.title = Widgets.Text(f.reader, "H1", "text-1", "LEFT")
	f.title:SetWordWrap(false)
	f.meta = Widgets.Text(f.reader, "Small", "text-3", "LEFT")
	f.meta:SetPoint("TOPLEFT", f.reader, "TOPLEFT", 0, -34)
	f.meta:SetPoint("TOPRIGHT", f.reader, "TOPRIGHT", 0, -34)
	f.text = scroller(f.reader)
	f.text:SetPoint("TOPLEFT", f.reader, "TOPLEFT", 0, -View.HEADER)
	f.text:SetPoint("BOTTOMRIGHT", f.reader, "BOTTOMRIGHT", 0, 0)
	f.blank = Widgets.Text(f.text.page, "Body", "text-3", "LEFT")
	f.blank:SetPoint("TOPLEFT", f.text.page, "TOPLEFT", 0, 0)
	f.blank:SetText(L["HANDBOOK_EMPTY_PAGE"])
	f.text:SetScript("OnSizeChanged", function() View:Changed() end)
	f:SetScript("OnSizeChanged", function(self) layout(self) View:Changed() end)
	f:SetScript("OnShow", function() watch(f, true) View:Redraw() end)
	f:SetScript("OnHide", function() watch(f, false) View:StopReading() end)
	watch(f, true)
	self:Redraw()
end

function View:Changed()
	if enabled() and self.frame and self.frame:IsVisible() then self:Redraw() end
end

if ns.Shell then
	ns.Shell:RegisterView("handbook", { label = L["VIEW_HANDBOOK"], order = 55, search = true, visible = enabled,
		onSearch = function(text) View:Search(text) end, build = function(f) View:Build(f) end,
		badge = function() return enabled() and #book():Updated() or 0 end })
end

if ns.addon then
	ns.addon.HandbookView = View
	if ns.Bus then
		local function badges() if enabled() and ns.Shell then ns.Shell:UpdateBadges() end end
		ns.Bus:On("HANDBOOK_CHANGED", function()
			View.version = View.version + 1
			View:Changed()
			badges()
		end)
		ns.Bus:On("HANDBOOK_READ", function() View:Changed() badges() end)
		ns.Bus:On("ROLE_CHANGED", function() View:Changed() badges() end)
		ns.Bus:On("ROSTER_UPDATED", function() View:Changed() badges() end)
		ns.Bus:On("GUILD_CHANGED", function()
			View:StopReading()
			View.selected, View.anchor, View.history, View.search = nil, nil, {}, ""
			View.editor, View.revisions, View.deleting = nil, nil, nil
			View.version = View.version + 1
			View:Changed()
		end)
	end
end

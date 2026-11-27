-- Reputation view (SPEC-07 LIKE-04, LIKE-08; SPEC-04 §2). Lua 5.1.
--
-- The view has modes, chosen in the "Show" menu of its toolbar (Widgets.ModeMenu, M13.7); a mode is { label, order, available() -> bool, build(frame),
-- refresh(frame) } and later steps add theirs with View.AddMode (the social index, the group map, suggested teammates).
-- A mode that is not available (for example a part reserved to officers, SPEC-10 Q3) is not in the menu.
--
-- Likes (LIKE-08): one row per account of the guild, sorted by likes (or by name), visible to every member. The total of
-- an account is the same on every one of its characters and never says who gave it (LIKE-04). A row shows the account's
-- main (or its character in the guild with the highest level), how many of its characters are in the guild, its place,
-- the total, and what the player can do: [Like] (a second click within LIKE_CONFIRM seconds gives it: a like cannot be
-- taken back), "pending" (waiting for an officer, LIKE-05), "liked" or "you" for the player's own account. A click on a
-- row opens the member card in the Roster view. The panel's search box filters by any character name.
--
-- View.LikeRows(opts) is a plain function of the roster, the account groups and the ledger (tested offline); the frames
-- only draw what it returns. The member card gets a Likes section from here too (LIKE-01, LIKE-04).
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.ReputationView, ns.modules = View, ns.modules or {}
ns.modules.ReputationView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, floor, max, min = type, ipairs, pairs, tostring, math.floor, math.max, math.min

View.ROW_HEIGHT = 36
View.HEAD_HEIGHT = 32
View.TOOLBAR_HEIGHT = 40
View.DEFAULT_ROWS = 14
View.WHEEL_STEP = 3
View.REFRESH_DELAY = 0.4
View.LIKE_CONFIRM = 8          -- seconds a first click on [Like] waits for the second one
View.HEART_WIDTH, View.CONFIRM_WIDTH = 32, 100   -- the Like button: a heart, then "Confirm" while armed

View.modes = {}                -- id -> { id, label, order, available, build, refresh, frame }
View.mode = "likes"
View.sort = { key = "likes", desc = true }
View.search = ""
View.offset = 0
View.armed = nil               -- { guid, at }: the [Like] clicked once

local function lower(s) return type(s) == "string" and s:lower() or "" end
local function now() return ns.Compat and ns.Compat.Now() or 0 end
local function classColor(classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

---------------------------------------------------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------------------------------------------------
function View.AddMode(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	def.id = id
	def.order = def.order or 100
	View.modes[id] = def
	if View.frame then View:Redraw() end
	return true
end

-- The modes that are available now, in order.
function View:ModeList()
	local list = {}
	for _, m in pairs(self.modes) do
		if m.available == nil or m.available() then list[#list + 1] = m end
	end
	table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
	return list
end

function View:SetMode(id)
	local m = self.modes[id]
	if not m or (m.available and not m.available()) then return false end
	self.mode = id
	self.offset = 0
	if self.frame then self:Redraw() end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Likes: the rows (a plain function, tested offline)
---------------------------------------------------------------------------------------------------------------------
-- One row per account with at least one character in the guild:
--   { key, guid (the character shown), name, classFile, level, online, chars (in the guild), names (every name, for the
--     search), total, state ("can" | "given" | "pending" | "self" | "nobody"), place (1-based by likes, ties share it) }
-- opts.search filters by any character name; opts.sort = { key = "likes" | "name", desc }.
function View.LikeRows(opts)
	opts = opts or {}
	local R, Likes = ns.Roster, ns.Likes
	if not (R and Likes) then return {} end
	local byKey, list = {}, {}
	for _, e in ipairs(R:Members()) do
		if type(e.guid) == "string" and not e.notInGuild then
			local chars = Likes:AccountChars(e.guid)
			local key = chars[1]
			for _, g in ipairs(chars) do if g < key then key = g end end
			local row = byKey[key]
			if not row then
				row = { key = key, chars = 0, names = {}, total = Likes:Total(e.guid), state = Likes:StateOf(e.guid) }
				byKey[key] = row
				list[#list + 1] = row
			end
			row.chars = row.chars + 1
			row.names[#row.names + 1] = e.short or e.name or "?"
			if e.online then row.online = true end
			-- the character shown: the account's main when it is in the guild, else the highest level
			local main = ns.Accounts and ns.Accounts:MainOf(e.guid)
			local isMain = main ~= nil and main.guid == e.guid and not main.hint and #chars > 1
			if not row.guid or isMain or (not row.isMain and (e.level or 0) > (row.level or 0)) then
				row.guid, row.name, row.classFile, row.level, row.isMain = e.guid, e.short or e.name or "?", e.classFile, e.level, isMain
			end
		end
	end
	local ranked = {}
	for i, row in ipairs(list) do ranked[i] = row end
	table.sort(ranked, function(a, b) return a.total > b.total end)
	for i, row in ipairs(ranked) do
		if i > 1 and row.total == ranked[i - 1].total then row.place = ranked[i - 1].place else row.place = i end
	end
	local query = lower(opts.search)
	local out = {}
	for _, row in ipairs(list) do
		local keep = query == ""
		if not keep then
			for _, n in ipairs(row.names) do if lower(n):find(query, 1, true) then keep = true break end end
		end
		if keep then out[#out + 1] = row end
	end
	local sort = opts.sort or View.sort
	table.sort(out, function(a, b)
		if sort.key == "name" then
			if lower(a.name) ~= lower(b.name) then
				if sort.desc then return lower(a.name) > lower(b.name) end
				return lower(a.name) < lower(b.name)
			end
		elseif a.total ~= b.total then
			if sort.desc == false then return a.total < b.total end
			return a.total > b.total
		end
		if lower(a.name) ~= lower(b.name) then return lower(a.name) < lower(b.name) end
		return a.key < b.key
	end)
	return out
end

-- The text and colour (a theme token) of the action column for a state other than "can".
function View.StateText(state)
	if state == "given" then return L["REP_LIKED"], "ok" end
	if state == "pending" then return L["REP_PENDING"], "text-3" end
	if state == "self" then return L["REP_YOU"], "text-3" end
	return "", "text-3"
end

-- The first click on [Like] arms it, the second one within LIKE_CONFIRM seconds gives the like. Returns "armed",
-- "given" or the reason Likes:Give refused it.
function View:LikeClicked(guid)
	local a = self.armed
	if not (a and a.guid == guid and now() - a.at <= View.LIKE_CONFIRM) then
		self.armed = { guid = guid, at = now() }
		if self.frame and self.frame:IsVisible() then self:Redraw() end   -- the button says "Confirm?" at once
		if ns.MemberCard then ns.MemberCard:Refresh() end
		return "armed"
	end
	self.armed = nil
	local ok, why = ns.Likes:Give(guid)
	if ns.addon then
		local e = ns.Roster and ns.Roster:ByGUID(guid)
		local name = e and (e.short or e.name) or "?"
		if ok then
			ns.addon:Print((ns.Likes:StateOf(guid) == "given" and L["REP_GIVEN_MSG"] or L["REP_QUEUED_MSG"]):format(name))
		end
	end
	self:Changed()
	if ns.MemberCard then ns.MemberCard:Refresh() end
	return ok and "given" or why
end

function View:IsArmed(guid)
	local a = self.armed
	return a ~= nil and a.guid == guid and now() - a.at <= View.LIKE_CONFIRM
end

---------------------------------------------------------------------------------------------------------------------
-- Likes: the frame
---------------------------------------------------------------------------------------------------------------------
local likes = {}

local function likesRows() return View.LikeRows({ search = View.search, sort = View.sort }) end

function likes.SortBy(key)
	if View.sort.key == key then View.sort.desc = not View.sort.desc
	else View.sort = { key = key, desc = key == "likes" } end
	View.offset = 0
	View:Redraw()
end

local function newRow(area, i)
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(View.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * View.ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(i - 1) * View.ROW_HEIGHT)
	row.place = Widgets.Text(row, "MonoSmall", "text-3", "RIGHT")
	row.place:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.place:SetWidth(28)
	row.mark = Widgets.ClassMark(row, 8)
	row.mark:SetPoint("LEFT", row.place, "RIGHT", 10, 0)
	row.name = Widgets.Text(row, "BodyMedium", "text-1", "LEFT")
	row.name:SetPoint("LEFT", row.mark, "RIGHT", 8, 0)
	row.name:SetWidth(140)
	row.chars = Widgets.Text(row, "Small", "text-3", "LEFT")
	row.chars:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.chars:SetWidth(110)
	-- one line each: a long Forever name is cut with dots, never wrapped onto the next row (found in game, 2026-11-26)
	for _, fs in ipairs({ row.name, row.chars }) do
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		if fs.SetMaxLines then fs:SetMaxLines(1) end
	end
	row.total = Widgets.Text(row, "MonoMedium", "accent-text", "RIGHT")
	row.total:SetPoint("LEFT", row.chars, "RIGHT", 6, 0)
	row.total:SetWidth(50)
	-- the Like button is a heart (owner, 2026-11-26); armed, it says "Confirm" until the second click
	row.like = Widgets.Button(row, { text = "", style = "tonal", width = View.HEART_WIDTH, height = Widgets.HEIGHT.small,
		onClick = function(b) View:LikeClicked(b:GetParent().data.guid) end })
	row.like.heart = row.like:CreateTexture(nil, "OVERLAY")
	row.like.heart:SetTexture(ns.Assets.textures.icons.path)
	row.like.heart:SetTexCoord(ns.Assets.IconCoords("heart"))
	row.like.heart:SetSize(20, 20)
	row.like.heart:SetPoint("CENTER", row.like, "CENTER", 0, 0)
	Theme.Tint(row.like.heart, "on-secondary-container")
	row.like:SetPoint("LEFT", row.total, "RIGHT", 14, 0)
	Widgets.Tooltip.Attach(row.like, { L["REP_LIKE"], L["REP_LIKE_TIP"] }, "RIGHT")
	row.state = Widgets.Text(row, "Small", "text-3", "LEFT")
	row.state:SetPoint("LEFT", row.total, "RIGHT", 14, 0)
	row:SetScript("OnClick", function(self) View:OpenCard(self.data) end)
	Widgets.RowHover(row)
	area.rows[i] = row
	return row
end

local function fillRow(row, d)
	row.data = d
	row.place:SetText(tostring(d.place))
	row.name:SetText(d.name)
	Widgets.PaintName(row.name, d.classFile)
	local c = RAID_CLASS_COLORS and d.classFile and RAID_CLASS_COLORS[d.classFile]
	if c then Widgets.PaintClassMark(row.mark, c.r, c.g, c.b) else Widgets.ClearClassMark(row.mark) end
	row.chars:SetText(d.chars > 1 and L["REP_CHARS"]:format(d.chars) or "")
	row.total:SetText(tostring(d.total))
	if d.state == "can" then
		local armed = View:IsArmed(d.guid)
		row.like:SetLabel(armed and L["REP_CONFIRM"] or "")
		row.like:SetWidth(armed and View.CONFIRM_WIDTH or View.HEART_WIDTH)
		row.like.heart:SetShown(not armed)
		row.like.armed = armed
		row.like:Show()
		row.state:Hide()
	else
		row.like:Hide()
		local text, token = View.StateText(d.state)
		row.state:SetText(text)
		Theme.Text(row.state, token)
		row.state:Show()
	end
	row:Show()
end

-- A header button of the list (the look of the DataTable header: Th, text-3; accent-text with an arrow when sorted).
local function headButton(head, text, width, onClick)
	local b = CreateFrame("Button", nil, head)
	b:SetSize(width, View.HEAD_HEIGHT)
	b.label = Widgets.Text(b, "label-medium", "text-3", "LEFT")
	b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
	b.label:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

function likes.build(f)
	f.explain = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.explain:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
	f.explain:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.explain:SetText(L["REP_LIKES_EXPLAIN"])
	local head = CreateFrame("Frame", nil, f)
	head:SetHeight(View.HEAD_HEIGHT)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -36)
	head.fill = Theme.Slice(head, "rr_fill_8", "surface-2", "BACKGROUND")
	head.fill:SetAllPoints(head)
	head.name = headButton(head, L["REP_COL_NAME"], 150, function() likes.SortBy("name") end)
	head.name:SetPoint("LEFT", head, "LEFT", 58, 0)
	head.likes = headButton(head, L["REP_COL_LIKES"], 50, function() likes.SortBy("likes") end)
	head.likes:SetPoint("LEFT", head, "LEFT", 320, 0)
	head.likes.label:ClearAllPoints()
	head.likes.label:SetPoint("RIGHT", head.likes, "RIGHT", 0, 0)   -- over the right-aligned totals
	f.head = head
	local area = CreateFrame("Frame", nil, f)
	area:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
	area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	area:SetScript("OnSizeChanged", function() View:Redraw() end)
	area:SetClipsChildren(true)   -- the last row is drawn even when it is cut
	area.rows = {}
	f.area = area
	f.message = Widgets.Text(f, "Body", "text-3", "CENTER")
	f.message:SetPoint("CENTER", area, "CENTER", 0, 0)
	f.message:SetWidth(380)
end

-- The sorted column of the header in accent-text.
local function paintHead(head)
	Theme.Text(head.name.label, View.sort.key == "name" and "accent-text" or "text-3")
	Theme.Text(head.likes.label, View.sort.key == "likes" and "accent-text" or "text-3")
end

local function visibleRows(area)
	local h = area and area:GetHeight() or 0
	if not h or h < View.ROW_HEIGHT then return View.DEFAULT_ROWS end
	return max(1, floor(h / View.ROW_HEIGHT))
end

function likes.refresh(f)
	local rows = likesRows()
	View.rowsShown = rows
	paintHead(f.head)
	local total, visible = #rows, visibleRows(f.area)
	View.offset = max(0, min(View.offset or 0, max(0, total - visible)))
	local drawn = max(0, min(visible + 1, total - View.offset))
	for i = 1, drawn do fillRow(f.area.rows[i] or newRow(f.area, i), rows[View.offset + i]) end
	for i = drawn + 1, #f.area.rows do f.area.rows[i]:Hide() end
	if total == 0 then
		f.message:SetText(View.search ~= "" and L["REP_NO_MATCH"] or L["REP_EMPTY"])
		f.message:Show()
	else
		f.message:Hide()
	end
	return total
end

View.AddMode("likes", { label = L["REP_MODE_LIKES"], order = 10, build = likes.build, refresh = likes.refresh, search = true })

---------------------------------------------------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------------------------------------------------
function View:OpenCard(d)
	if not (d and d.guid) then return false end
	if ns.Shell then ns.Shell:OpenView("roster") end
	return ns.MemberCard and ns.MemberCard:ShowGUID(d.guid) or false
end

function View:Build(f)
	self.frame = f
	local bar = Widgets.ModeMenu(f, function(id) View:SetMode(id) end, { label = L["NAV_SHOW"] })
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.bar = bar
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.TOOLBAR_HEIGHT)
	f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f:SetScript("OnShow", function() View:Redraw() end)
	self:Redraw()
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local list = self:ModeList()
	local current = self.modes[self.mode]
	if not current or (current.available and not current.available()) then
		current = list[1]
		self.mode = current and current.id or "likes"
	end
	local items = {}
	for i, m in ipairs(list) do items[i] = { id = m.id, text = m.label } end
	f.bar:SetItems(items, self.mode)
	f.bar:SetShown(#list > 1)
	f.body:ClearAllPoints()
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, #list > 1 and -View.TOOLBAR_HEIGHT or 0)
	f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	for id, m in pairs(self.modes) do
		if m.frame and id ~= self.mode then m.frame:Hide() end
	end
	if current then
		if not current.frame then
			current.frame = CreateFrame("Frame", nil, f.body)
			current.frame:SetAllPoints(f.body)
			current.build(current.frame)
		end
		current.frame:Show()
		if current.refresh then current.refresh(current.frame) end
	end
	self.drawn = (self.drawn or 0) + 1
end

function View:Scroll(delta)
	local total = self.rowsShown and #self.rowsShown or 0
	local m = self.modes[self.mode]
	local area = m and m.frame and m.frame.area
	local limit = max(0, total - visibleRows(area))
	local target = max(0, min((self.offset or 0) + delta, limit))
	if target == self.offset then return false end
	self.offset = target
	self:Redraw()
	return true
end

function View:SetSearch(text)
	text = type(text) == "string" and text or ""
	if text == self.search then return end
	self.search = text
	self.offset = 0
	self:Redraw()
end

-- The data changed: one redraw after the burst, only while the view is visible.
function View:Changed()
	if self.refreshTimer or not (self.frame and self.frame:IsVisible()) then return end
	self.refreshTimer = true
	local scheduled = ns.Compat and ns.Compat.After(View.REFRESH_DELAY, function()
		View.refreshTimer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.refreshTimer = nil self:Redraw() end
end

---------------------------------------------------------------------------------------------------------------------
-- The Likes section of the member card
---------------------------------------------------------------------------------------------------------------------
function View.CardSection(e)
	local Likes = ns.Likes
	if not (Likes and type(e) == "table" and e.guid) or e.notInGuild then return nil end
	local lines = {}
	local total = Likes:Total(e.guid)
	lines[1] = { text = L["CARD_LIKES_TOTAL"]:format(total) }
	local newest = total > 0 and Likes:Newest(e.guid) or nil
	if newest then lines[1].prov = { source = "shared", observedAt = newest.time, author = newest.author } end
	local state = Likes:StateOf(e.guid)
	if state == "can" then
		local guid = e.guid
		lines[#lines + 1] = { text = View:IsArmed(guid) and L["CARD_LIKE_CONFIRM"] or L["CARD_LIKE"], action = true,
			onClick = function() View:LikeClicked(guid) end }
	elseif state == "pending" then
		lines[#lines + 1] = { text = L["CARD_LIKE_PENDING"], muted = true }
	elseif state == "given" then
		lines[#lines + 1] = { text = L["CARD_LIKE_GIVEN"], muted = true }
	end
	return { id = "likes", title = L["CARD_LIKES"], lines = lines }
end

if ns.MemberCard then ns.MemberCard.AddSection("likes", 5, View.CardSection) end

if ns.Shell then
	ns.Shell:RegisterView("reputation", {
		label = L["VIEW_REPUTATION"], order = 30, search = true,
		build = function(f) View:Build(f) end,
		onSearch = function(text) View:SetSearch(text) end,
	})
end

if ns.addon then
	ns.addon.ReputationView = View
	if ns.Bus then
		local function changed() View:Changed() end
		ns.Bus:On("LIKES_UPDATED", function()
			changed()
			if ns.MemberCard then ns.MemberCard:Refresh() end
			if ns.RosterView and ns.RosterView.model then ns.RosterView.model:Invalidate() end
			if ns.RosterView and ns.RosterView.frame and ns.RosterView.frame:IsVisible() then ns.RosterView:Changed() end
		end)
		ns.Bus:On("LIKE_RESULT", function(guid, result)
			local reason = result == "self" and L["REP_REASON_SELF"] or (result == "target" and L["REP_REASON_TARGET"])
				or (result == "conflict" and L["REP_REASON_CONFLICT"]) or nil
			if reason and ns.addon then
				local e = ns.Roster and ns.Roster:ByGUID(guid)
				ns.addon:Print(L["REP_REFUSED_MSG"]:format(e and (e.short or e.name) or "?", reason))
			end
		end)
		ns.Bus:On("ROSTER_UPDATED", changed)
		ns.Bus:On("ACCOUNTS_UPDATED", changed)
		ns.Bus:On("GUILD_CHANGED", function()
			View.search, View.offset, View.armed = "", 0, nil
			if View.frame then View:Redraw() end
		end)
	end
end

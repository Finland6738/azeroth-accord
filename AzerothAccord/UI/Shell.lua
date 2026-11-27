-- Shell: the Accord panel, its navigation rail and its pages (SPEC-04 §2-§4, docs/specs/ui-style.md §3, §9.11). Lua 5.1.
--
-- One content frame, shown in one host at a time: the panel of the Accord tab in the guild window (UI/GuildTab.lua) or
-- the standalone window (UI/Window.lua). The host draws what is around it (the window: its panel and title bar; the
-- guild window: a fill of the theme over Blizzard's content area). Navigation has two levels (ui-style §9.11, M13.7):
--   * level 1, the navigation rail at the left: one icon per destination of Shell.DESTINATIONS (Home, Guild, Raid,
--     Groups, Professions, Economy, Community, Officers, and Settings at the bottom), 24 pt icons on 56 pt items, the name
--     in a tooltip; the active one has its icon filled and the secondary-container indicator behind it; a destination
--     carries the sum of its views' badges. A destination without a visible view has no icon (Officers for a member);
--   * level 2, one row at the top of the content: the destination's name, then one tab (ns.Widgets.Tabs) per page of it.
--     A page is a registered view (Roster, Bank...) or, for a view that has pages of its own (`pages`), one of them
--     (Officers: Inactive, Queue, Timeline...). A destination with one page shows only its name;
--   * at the right of that row: the search box, while the selected view can search, and Pop out in the guild window;
--   * the body: the selected view, or a welcome text while no view exists;
--   * in the guild window only, a line under the body with the sync state (the window has it in its title bar).
-- There is no third row: what a view shows inside a page is chosen with filter chips or a "Show" menu.
-- Every colour is a token of UI/Theme.lua, so Theme.Apply repaints the shell without /reload. The views draw with
-- the widget kit: each gets a plain frame that fills the body.
-- The panel holds no protected action, so it opens and closes in combat too (GT-06).
local ADDON_NAME, ns = ...
ns = ns or {}
local Shell = {}
ns.Shell, ns.modules = Shell, ns.modules or {}
ns.modules.Shell = Shell

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, pairs, ipairs, tostring, floor, pcall = type, pairs, ipairs, tostring, math.floor, pcall

Shell.NAME = "AzerothAccordShell"
Shell.PAD = 16            -- between the rail and the row of pages, the body; at the right edge of the host
Shell.TOP = 4             -- above the tab bar
Shell.TAB_BAR = Widgets.TAB_HEIGHT   -- the height of the tabs (48)
Shell.STRIP = 40          -- the Demo strip above the tab bar (demo mode, SPEC-11 §3.1)
Shell.GAP = 12            -- between the tab bar and the body
Shell.FOOTER = 24         -- the sync-state line of the guild window
Shell.SEARCH_WIDTH = { window = 200, tab = 150 }
Shell.STATUS_REFRESH = 30
Shell.RAIL = 80           -- the width of the navigation rail (ui-style §9.11)
Shell.RAIL_ITEM = 56      -- the height of one of its items
Shell.RAIL_ICON = 24
Shell.RAIL_TOP = 8        -- above its first item and under its last (Settings)
Shell.INDICATOR = { 56, 32 }   -- the active destination's indicator, a pill behind the icon (M3)
Shell.TITLE_GAP = 24      -- between the destination's name and its first tab

-- The destinations of the rail (owner, 2026-11-27, ui-style §9.11): id, Material Symbols icon, name, order. A new
-- milestone adds pages to one of them, never an icon (a new destination needs the owner's consent).
Shell.DESTINATIONS = {
	{ id = "home", icon = "home", label = L["NAV_HOME"] },
	{ id = "guild", icon = "groups", label = L["NAV_GUILD"] },
	{ id = "raid", icon = "swords", label = L["NAV_RAID"] },
	{ id = "groups", icon = "group_add", label = L["NAV_GROUPS"] },
	{ id = "professions", icon = "construction", label = L["NAV_PROFESSIONS"] },
	{ id = "economy", icon = "account_balance", label = L["NAV_ECONOMY"] },
	{ id = "community", icon = "celebration", label = L["NAV_COMMUNITY"] },
	{ id = "officers", icon = "shield_person", label = L["NAV_OFFICERS"] },
	{ id = "settings", icon = "settings", label = L["NAV_SETTINGS"], bottom = true },
}

-- The destination of each view of the map; a view may say its own (`dest`). One that says nothing goes to Community.
Shell.VIEW_DEST = {
	actions = "home",
	roster = "guild", reputation = "guild", mentors = "guild", addons = "guild",
	season = "raid", events = "raid", raid = "raid", availability = "raid",
	groups = "groups", quests = "groups", rallies = "groups",
	professions = "professions", orders = "professions", shopping = "professions",
	bank = "economy", market = "economy", goals = "economy",
	handbook = "community",
	officers = "officers",
	settings = "settings",
}
Shell.DEFAULT_DEST = "community"

Shell.views = {}        -- id -> { id, label, order, dest, build(frame), frame, search, onSearch(text), badge(), pages... }
Shell.pageOf = {}       -- view id -> the page shown last of a view with pages
Shell.destLast = {}     -- destination id -> the key of its page shown last
Shell.host = nil        -- the host the content is in now: { frame, mode = "tab" | "window", name, onLeave, onStatus }

---------------------------------------------------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------------------------------------------------
-- A view registers itself: def = { label, order, build(frame) -> nil, search = bool, onSearch(text), badge() -> n,
-- visible() -> bool (a view without it always shows; one that says no has no tab and cannot be selected), dest (the
-- destination, default Shell.VIEW_DEST), pageLabel (its tab's text when not `label`) }. A view with pages of its own
-- adds pages() -> { { id, label } } (the visible ones, in order), showPage(id) (shows that page; the view then calls
-- Shell:PageShown) and page() -> id (the one it shows), and may add pageBadge(id) -> n. Each page gets a tab.
function Shell:RegisterView(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	def.id = id
	def.order = def.order or 100
	self.views[id] = def
	if self.content then self:Refresh() end
	return true
end

-- The number a badge function gives (0 when it has none or raises).
local function count(fn, ...)
	if type(fn) ~= "function" then return 0 end
	local ok, n = pcall(fn, ...)
	if not ok or type(n) ~= "number" or n <= 0 then return 0 end
	return floor(n)
end

local function countText(n) if n <= 0 then return nil end return n > 99 and "99+" or tostring(n) end

-- The count on a view's tab: the number its `badge` function gives when above 0 ("99+" from 100), else nil (no badge).
function Shell.BadgeText(view)
	if type(view) ~= "table" then return nil end
	return countText(count(view.badge))
end

-- Puts the counts on the rail and on the tabs again (a badge changed: Data/BankInbox.lua calls this).
function Shell:UpdateBadges()
	local content = self.content
	if not content then return end
	local sums = {}
	for _, view in pairs(self.views) do
		if Shell.Visible(view) then
			local d = Shell.DestOf(view)
			sums[d] = (sums[d] or 0) + count(view.badge)
		end
	end
	if content.rail then
		for id, item in pairs(content.rail.items) do item:SetCount(countText(sums[id] or 0)) end
	end
	local tabs = content.tabs
	if not tabs or not content.pageList then return end
	for _, p in ipairs(content.pageList) do
		if tabs.buttons[p.key] then
			local view = self.views[p.view]
			local n = p.page and count(view and view.pageBadge, p.page) or count(view and view.badge)
			tabs:SetBadge(p.key, countText(n))
		end
	end
end

-- true when the view may show now.
function Shell.Visible(view)
	if not view then return false end
	if type(view.visible) ~= "function" then return true end
	local ok, yes = pcall(view.visible)
	return ok and yes == true
end

function Shell:ViewList()
	local list = {}
	for _, v in pairs(self.views) do if Shell.Visible(v) then list[#list + 1] = v end end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.id < b.id
	end)
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Destinations and pages
---------------------------------------------------------------------------------------------------------------------
local DEST = {}
for i, d in ipairs(Shell.DESTINATIONS) do d.order = i DEST[d.id] = d end

function Shell.Destination(id) return DEST[id] end

function Shell.DestOf(view)
	local d = type(view) == "table" and (view.dest or Shell.VIEW_DEST[view.id]) or nil
	return DEST[d] and d or Shell.DEFAULT_DEST
end

-- The pages of a view that has some ({ { id, label } }), else nil.
function Shell.PagesOf(view)
	if type(view) ~= "table" or type(view.pages) ~= "function" then return nil end
	local ok, list = pcall(view.pages)
	if not ok or type(list) ~= "table" or #list == 0 then return nil end
	return list
end

-- "officers:queue" -> "officers", "queue"; "roster" -> "roster", nil.
function Shell.SplitKey(key)
	if type(key) ~= "string" then return nil, nil end
	local id, page = key:match("^([^:]+):(.+)$")
	if id then return id, page end
	return key, nil
end

local function hasPage(view, page)
	for _, p in ipairs(Shell.PagesOf(view) or {}) do if p.id == page then return true end end
	return false
end

-- The page a view with pages shows: the one chosen last (a tab, or the view itself through Shell:PageShown), else the
-- one the view says, else its first.
function Shell:CurrentPage(view)
	local pages = Shell.PagesOf(view)
	if not pages then return nil end
	if hasPage(view, self.pageOf[view.id]) then return self.pageOf[view.id] end
	local now = type(view.page) == "function" and select(2, pcall(view.page)) or nil
	if hasPage(view, now) then return now end
	return pages[1].id
end

-- The key of the tab of a view: its id, or "id:page" for a view with pages.
function Shell:KeyOf(id)
	local view = self.views[id]
	local page = view and self:CurrentPage(view)
	return page and (id .. ":" .. page) or id
end

-- The tabs of destination `dest`: { { key, view, page?, text } } in order.
function Shell:PageList(dest)
	local list = {}
	for _, v in ipairs(self:ViewList()) do
		if Shell.DestOf(v) == dest then
			local pages = Shell.PagesOf(v)
			if pages then
				for _, p in ipairs(pages) do
					list[#list + 1] = { key = v.id .. ":" .. p.id, view = v.id, page = p.id, text = p.label or p.id }
				end
			else
				list[#list + 1] = { key = v.id, view = v.id, text = v.pageLabel or v.label or v.id }
			end
		end
	end
	return list
end

-- The destinations that have a visible view, in the order of the rail.
function Shell:DestList()
	local has = {}
	for _, v in pairs(self.views) do if Shell.Visible(v) then has[Shell.DestOf(v)] = true end end
	local list = {}
	for _, d in ipairs(Shell.DESTINATIONS) do if has[d.id] then list[#list + 1] = d end end
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Sync state ("3 guildmates with Accord online · updated 2 min ago")
---------------------------------------------------------------------------------------------------------------------
function Shell.Ago(seconds) return ns.Provenance.AgeText(seconds) end   -- one scale for every age (SPEC-11 §1.2)

function Shell.StatusText()
	if ns.Demo and ns.Demo:IsActive() then return L["DEMO_STATUS"] end   -- the sync state means nothing in the demo
	local status = ns.Sync and ns.Sync.Status and ns.Sync:Status() or { peers = 0 }
	local peers = L["STATUS_PEERS"]:format(status.peers or 0)
	if not status.lastReceived then return peers .. " · " .. L["STATUS_NEVER"] end
	local now = ns.Compat and ns.Compat.ServerTime() or time()
	return peers .. " · " .. L["STATUS_UPDATED"]:format(Shell.Ago(now - status.lastReceived))
end

---------------------------------------------------------------------------------------------------------------------
-- The content frame
---------------------------------------------------------------------------------------------------------------------
local function buildBar(content)
	local bar = CreateFrame("Frame", nil, content)
	bar:SetHeight(Shell.TAB_BAR)
	-- the destination's name at the start of the row (ui-style §9.11), and the divider under the whole row
	bar.title = Theme.NewText(bar, "TitleLarge", "text-1")
	bar.title:SetPoint("LEFT", bar, "LEFT", 0, 0)
	bar.title:SetJustifyH("LEFT")
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.line:SetHeight(Theme.Px(1))
	-- the search box: the Widgets field is `searchField`; `search` is its edit box, where the views and the tests type
	bar.searchField = Widgets.EditBox(bar, { width = Shell.SEARCH_WIDTH.window, dense = true, placeholder = L["SEARCH_PLACEHOLDER"],
		onChange = function(text, user) if user then Shell:OnSearch(text or "") end end })
	bar.search = bar.searchField.edit
	bar.popOut = Widgets.Button(bar, { text = L["POP_OUT"], style = "outlined", dense = true, onClick = function() Shell:PopOut() end })
	bar.popOut:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	if Widgets.Tooltip then Widgets.Tooltip.Attach(bar.popOut, { L["POP_OUT"], L["POP_OUT_TIP"] }, "BOTTOM") end
	content.bar = bar
end

---------------------------------------------------------------------------------------------------------------------
-- The navigation rail (ui-style §9.11; M3 navigation rail, icons only)
---------------------------------------------------------------------------------------------------------------------
local function newRailItem(rail, dest)
	local item = CreateFrame("Button", nil, rail)
	item:SetSize(Shell.RAIL, Shell.RAIL_ITEM)
	item.id, item.name, item.iconName = dest.id, dest.label or dest.id, dest.icon
	local w, h = Shell.INDICATOR[1], Shell.INDICATOR[2]
	-- the indicator: a pill of secondary-container behind the icon, shown on the active destination; the state layer
	-- (hover, press) has the same shape, in the colour of the icon
	item.indicator = Theme.Slice(item, Theme.ShapeSlice("full"), "secondary-container", "BACKGROUND")
	item.indicator:SetSize(w, h)
	item.indicator:SetPoint("CENTER", item, "CENTER", 0, 0)
	item.indicator:Hide()
	local hit = CreateFrame("Frame", nil, item)
	hit:SetSize(w, h)
	hit:SetPoint("CENTER", item, "CENTER", 0, 0)
	item.over = Widgets.TrackState(item, Widgets.StateLayer(item, "text-2", { shape = "full", anchor = hit, layer = "BORDER" }))
	item.icon = Widgets.Icon(item, dest.icon, Shell.RAIL_ICON, "text-2", "ARTWORK")
	item.icon:SetPoint("CENTER", item, "CENTER", 0, 0)
	function item:SetActive(on)
		on = on and true or false
		self.active = on
		self.indicator:SetShown(on)
		self.icon:SetTexCoord(ns.Assets.IconCoords(self.iconName, on))
		Theme.Tint(self.icon, on and "on-secondary-container" or "text-2")
		Widgets.SetStateColor(self.over, on and "on-secondary-container" or "text-2")
	end
	-- the M3 badge: the count at the top right of the icon (the err badge of the kit)
	function item:SetCount(text)
		if not text then
			if self.badge then self.badge:Hide() end
			return
		end
		if not self.badge then
			self.badge = Widgets.Badge(self, text)
			self.badge:SetFrameLevel((self:GetFrameLevel() or 1) + 3)
			self.badge:SetPoint("BOTTOMLEFT", self.icon, "TOPRIGHT", -10, -8)
		else
			self.badge:SetBadge(text)
		end
		self.badge:Show()
	end
	if Widgets.Tooltip then Widgets.Tooltip.Attach(item, function(self) return self.name end, "RIGHT") end
	item:SetScript("OnClick", function(self) Shell:SelectDest(self.id, true) end)
	item:SetActive(false)
	return item
end

local function buildRail(content)
	local rail = CreateFrame("Frame", nil, content)
	rail:SetWidth(Shell.RAIL)
	rail.line = rail:CreateTexture(nil, "BORDER")
	Theme.Fill(rail.line, "border-subtle")
	rail.line:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
	rail.line:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)
	rail.line:SetWidth(Theme.Px(1))
	rail.items = {}
	for _, d in ipairs(Shell.DESTINATIONS) do rail.items[d.id] = newRailItem(rail, d) end
	content.rail = rail
end

-- Shows the icons of the destinations that have a visible view: from the top, Settings at the bottom.
local function layoutRail(content, list)
	local rail = content.rail
	local shown = {}
	for _, d in ipairs(list) do shown[d.id] = d end
	local y = -Shell.RAIL_TOP
	rail.order = {}
	for _, d in ipairs(Shell.DESTINATIONS) do
		local item = rail.items[d.id]
		item:ClearAllPoints()
		item:SetShown(shown[d.id] ~= nil)
		if shown[d.id] then
			if d.bottom then
				item:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, Shell.RAIL_TOP)
			else
				item:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, y)
				y = y - Shell.RAIL_ITEM
			end
			rail.order[#rail.order + 1] = d.id
		end
	end
end

-- The strip of demo mode, over the row of pages: the warning colour, what the mode does and the way out.
local function buildStrip(content)
	local strip = CreateFrame("Frame", nil, content)
	strip:SetHeight(Shell.STRIP)
	strip.fill = strip:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(strip.fill, "warn", 0.16)
	strip.fill:SetAllPoints(strip)
	strip.line = strip:CreateTexture(nil, "BORDER")
	Theme.Fill(strip.line, "warn")
	strip.line:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
	strip.line:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
	strip.line:SetHeight(Theme.Px(1))
	strip.exit = Widgets.Button(strip, { text = L["DEMO_EXIT"], style = "outlined", height = Widgets.HEIGHT.small,
		onClick = function() if ns.Demo then ns.Demo:Exit() end end })
	strip.exit:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
	strip.text = Theme.NewText(strip, "Body", "warn")
	strip.text:SetPoint("LEFT", strip, "LEFT", 10, 0)
	strip.text:SetPoint("RIGHT", strip.exit, "LEFT", -8, 0)
	strip.text:SetJustifyH("LEFT")
	strip.text:SetText(L["DEMO_STRIP"])
	content.strip = strip
	return strip
end

-- The left edge of what lies right of the rail.
local function leftEdge() return Shell.RAIL + Shell.PAD end

-- The strip shows while demo mode is on, and the row of pages moves down under it.
local function layoutDemo(content)
	local on = ns.Demo ~= nil and ns.Demo:IsActive()
	if on and not content.strip then buildStrip(content) end
	if content.strip then
		content.strip:SetShown(on)
		content.strip:ClearAllPoints()
		content.strip:SetPoint("TOPLEFT", content, "TOPLEFT", leftEdge(), -Shell.TOP)
		content.strip:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Shell.PAD, -Shell.TOP)
	end
	local top = Shell.TOP + (on and (Shell.STRIP + 4) or 0)
	local bar = content.bar
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", content, "TOPLEFT", leftEdge(), -top)
	bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Shell.PAD, -top)
end

local function buildFooter(content)
	local footer = CreateFrame("Frame", nil, content)
	footer:SetHeight(Shell.FOOTER)
	footer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", Shell.PAD, 0)
	footer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Shell.PAD, 0)
	footer.line = footer:CreateTexture(nil, "BORDER")
	Theme.Fill(footer.line, "border-subtle")
	footer.line:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
	footer.line:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
	footer.line:SetHeight(Theme.Px(1))
	content.status = Theme.NewText(footer, "MonoSmall", "text-3")
	content.status:SetPoint("RIGHT", footer, "RIGHT", 0, -1)
	content.status:SetJustifyH("RIGHT")
	content.footer = footer
end

local function buildBody(content)
	local body = CreateFrame("Frame", nil, content)
	content.body = body
	local empty = CreateFrame("Frame", nil, body)
	empty:SetAllPoints(body)
	empty.icon = empty:CreateTexture(nil, "ARTWORK")
	empty.icon:SetSize(56, 56)
	empty.icon:SetPoint("TOP", empty, "TOP", 0, -40)
	empty.icon:SetTexture(ns.Assets.logos.logo_64.path)
	empty.title = Theme.NewText(empty, "H2", "text-1")
	empty.title:SetJustifyH("CENTER")
	empty.title:SetPoint("TOP", empty.icon, "BOTTOM", 0, -12)
	empty.title:SetText(L["EMPTY_TITLE"])
	empty.text = Theme.NewText(empty, "Body", "text-2")
	empty.text:SetJustifyH("CENTER")
	empty.text:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
	empty.text:SetWidth(380)
	empty.text:SetText(L["EMPTY_TEXT"])
	content.empty = empty
end

function Shell:Content()
	if self.content then return self.content end
	local content = CreateFrame("Frame", Shell.NAME, UIParent)
	content:Hide()
	buildRail(content)
	buildBar(content)
	buildFooter(content)
	buildBody(content)
	content.tabsCache = {}
	content:SetScript("OnShow", function() Shell:StartStatus() Shell:Refresh() end)
	content:SetScript("OnHide", function() Shell:StopStatus() end)
	self.content = content
	return content
end

-- The row of tabs for the pages in `list` (one destination). Widgets.Tabs takes its tabs when it is made, so each set of
-- pages has its own bar, kept and shown again when the destination comes back (a view that registers later or a changed
-- label makes a new one). A click on a tab goes through Shell:Select with `retry`, so a click on the tab of a view that
-- failed builds it again (the bar itself does not call back for the active tab).
local function tabsKey(list)
	local parts = {}
	for i, p in ipairs(list) do parts[i] = p.key .. "=" .. tostring(p.text) end
	return table.concat(parts, "\n")
end

local function buildTabs(content, list)
	local key = tabsKey(list)
	if content.tabs and content.tabsKey == key then return content.tabs end
	if content.tabs then content.tabs:Hide() end
	local tabs = content.tabsCache[key]
	if not tabs then
		local defs = {}
		for i, p in ipairs(list) do defs[i] = { id = p.key, text = p.text } end
		tabs = Widgets.Tabs(content.bar, defs, nil, { moreText = L["TABS_MORE"] })
		tabs:SetPoint("BOTTOMLEFT", content.bar, "BOTTOMLEFT", 0, 0)
		tabs:SetPoint("BOTTOMRIGHT", content.bar, "BOTTOMRIGHT", 0, 0)
		for id, b in pairs(tabs.buttons) do
			b:HookScript("OnClick", function() Shell:Select(id, true) end)
		end
		content.tabsCache[key] = tabs
	end
	content.tabs, content.tabsKey = tabs, key
	-- the search box and Pop out lie over the right end of the row (its line runs under them)
	local level = (tabs:GetFrameLevel() or 1) + 2
	content.bar.searchField:SetFrameLevel(level)
	content.bar.popOut:SetFrameLevel(level)
	return tabs
end

-- What depends on the host: Pop out and the footer only in the guild window, the width of the search box, the rail, the
-- body.
local function layout(content, mode)
	layoutDemo(content)
	local bar, tab = content.bar, mode == "tab"
	bar.popOut:SetShown(tab)
	local field = bar.searchField
	field:SetWidth(Shell.SEARCH_WIDTH[tab and "tab" or "window"])
	field:ClearAllPoints()
	if tab then field:SetPoint("RIGHT", bar.popOut, "LEFT", -8, 0)
	else field:SetPoint("RIGHT", bar, "RIGHT", 0, 0) end
	content.footer:SetShown(tab)
	local rail = content.rail
	rail:ClearAllPoints()
	rail:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	if tab then rail:SetPoint("BOTTOMLEFT", content.footer, "TOPLEFT", -Shell.PAD, 0)
	else rail:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0) end
	local body = content.body
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -Shell.GAP)
	if tab then body:SetPoint("BOTTOMRIGHT", content.footer, "TOPRIGHT", 0, 4)
	else body:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Shell.PAD, Shell.PAD) end
	content.mode = tab and "tab" or "window"
end

-- The room the tabs leave at the right of the row: the search box (also while the selected view has none, so that the
-- tabs do not move from one page to the next) and, in the guild window, Pop out.
function Shell.TabReserve(content)
	local tab = content.mode == "tab"
	local reserve = Shell.SEARCH_WIDTH[tab and "tab" or "window"] + 8
	if tab then reserve = reserve + (content.bar.popOut:GetWidth() or 0) + 8 end
	return reserve
end

---------------------------------------------------------------------------------------------------------------------
-- Refresh, selection, search
---------------------------------------------------------------------------------------------------------------------
-- The view to show when none is chosen: the one remembered (char.ui.lastView: a view id, or "id:page" since M13.7),
-- else the first page of the first destination.
function Shell:DefaultKey()
	local last = ns.Config and ns.Config:Get("char.ui.lastView")
	local id, page = Shell.SplitKey(last)
	if id and Shell.Visible(self.views[id]) then
		if page and hasPage(self.views[id], page) then self.pageOf[id] = page end
		return id
	end
	local dests = self:DestList()
	local first = dests[1] and self:PageList(dests[1].id)[1]
	if first and first.page then self.pageOf[first.view] = first.page end
	return first and first.view or nil
end

-- The row of the selected view's destination: its name, and its tabs when it has more than one page.
local function showRow(self, content)
	local view = self.selected and self.views[self.selected]
	local dest = view and Shell.DestOf(view)
	local d = DEST[dest]
	content.dest = dest
	content.bar.title:SetText(d and d.label or "")
	local list = dest and self:PageList(dest) or {}
	content.pageList = list
	if #list > 1 then
		local tabs = buildTabs(content, list)
		tabs:ClearAllPoints()
		tabs:SetPoint("BOTTOMLEFT", content.bar, "BOTTOMLEFT", (content.bar.title:GetStringWidth() or 0) + Shell.TITLE_GAP, 0)
		tabs:SetPoint("BOTTOMRIGHT", content.bar, "BOTTOMRIGHT", 0, 0)
		tabs:Show()
		tabs:SetReserve(Shell.TabReserve(content))
		tabs:Select(self:KeyOf(self.selected))
	elseif content.tabs then
		content.tabs:Hide()
		content.tabs, content.tabsKey = nil, nil
	end
	for id, item in pairs(content.rail.items) do item:SetActive(id == dest) end
	if dest then self.destLast[dest] = self:KeyOf(self.selected) end
end

function Shell:Refresh()
	local content = self.content
	if not content then return end
	layout(content, self.host and self.host.mode or "window")
	layoutRail(content, self:DestList())
	local list = self:ViewList()
	if #list == 0 then
		if content.tabs then content.tabs:Hide() end
		content.tabs, content.tabsKey, content.pageList = nil, nil, nil
		content.bar.title:SetText("")
		for _, item in pairs(content.rail.items) do item:SetActive(false) end
		self.selected = nil
		content.empty:Show()
	else
		if not (self.selected and Shell.Visible(self.views[self.selected])) then
			self.selected = self:DefaultKey()
		end
		content.empty:Hide()
		self:ShowSelected()
	end
	self:UpdateSearch()
	self:UpdateStatus()
end

-- Draws a view for the first time. A view that raises while it is built (a game update changed an API, a bug of ours)
-- must not take the panel with it: the error goes to the game's error handler (and so to /accord debug), the view shows
-- a short text saying so, and the other views keep working. Clicking its tab again tries to build it afresh.
local function buildView(content, view)
	local frame = CreateFrame("Frame", nil, content.body)
	frame:SetAllPoints(content.body)
	view.frame = frame
	local ok, err = xpcall(view.build, function(e)
		if geterrorhandler then pcall(geterrorhandler(), e) end
		return e
	end, frame)
	if ok then return true end
	view.failed = tostring(err)
	local title = Theme.NewText(frame, "H2", "err")
	title:SetJustifyH("CENTER")
	title:SetPoint("TOP", frame, "TOP", 0, -60)
	title:SetText(L["VIEW_ERROR_TITLE"])
	local text = Theme.NewText(frame, "Body", "text-2")
	text:SetJustifyH("CENTER")
	text:SetPoint("TOP", title, "BOTTOM", 0, -10)
	text:SetWidth(380)
	text:SetText(L["VIEW_ERROR_TEXT"])
	frame.errorTitle, frame.errorText = title, text
	return false
end

function Shell:ShowSelected()
	local content = self.content
	local selected = self.selected and self.views[self.selected]
	for id, view in pairs(self.views) do
		if id == self.selected then
			if not view.frame then
				-- while a view is built it shows its own first page: the page chosen is shown just below
				self.building = true
				buildView(content, view)
				self.building = nil
			end
			view.frame:Show()
		elseif view.frame then
			view.frame:Hide()
		end
	end
	-- a view with pages shows the page chosen (it calls Shell:PageShown back)
	if selected and not selected.failed and Shell.PagesOf(selected) and type(selected.showPage) == "function" then
		self.showing = true
		pcall(selected.showPage, self:CurrentPage(selected))
		self.showing = nil
	end
	showRow(self, content)
	self:UpdateBadges()
	self:UpdateSearch()
end

-- Selects `key`: a view id, or "id:page" for a page of a view with pages. `retry` is true for a click on a tab or on the
-- rail: a view whose build failed is then built afresh.
function Shell:Select(key, retry)
	local id, page = Shell.SplitKey(key)
	local view = id and self.views[id]
	if not Shell.Visible(view) then return false end
	if page and not hasPage(view, page) then return false end
	if retry and view.failed and view.frame then
		view.frame:Hide()
		view.frame, view.failed = nil, nil
	end
	self.selected = id
	if page then self.pageOf[id] = page end
	-- a click on the tab may put the view back on its start (`onTabClick`: the Professions view shows the guild's recipes)
	if retry and type(view.onTabClick) == "function" then pcall(view.onTabClick) end
	if self.content then self:ShowSelected() end
	if ns.Config then ns.Config:Set("char.ui.lastView", self:KeyOf(id)) end
	return true
end

-- A click on the rail: the destination's page shown last, else its first.
function Shell:SelectDest(dest, retry)
	local list = self:PageList(dest)
	if #list == 0 then return false end
	local last = self.destLast[dest]
	for _, p in ipairs(list) do
		if p.key == last then return self:Select(last, retry) end
	end
	return self:Select(list[1].key, retry)
end

-- A view with pages changed its page itself (View:OpenPage, a link of the Action Center): the tabs follow.
function Shell:PageShown(id, page)
	local view = self.views[id]
	if not (view and hasPage(view, page)) then return false end
	if self.building then return true end
	self.pageOf[id] = page
	if self.showing or self.selected ~= id then return true end
	if ns.Config then ns.Config:Set("char.ui.lastView", id .. ":" .. page) end
	local content = self.content
	if content then
		showRow(self, content)
		self:UpdateBadges()
	end
	return true
end

-- The search box shows while the selected view can search; what is typed goes to that view.
function Shell:UpdateSearch()
	local content = self.content
	if not content then return end
	local view = self.selected and self.views[self.selected]
	content.bar.searchField:SetShown(view ~= nil and view.search == true)
end

function Shell:OnSearch(text)
	local view = self.selected and self.views[self.selected]
	if view and type(view.onSearch) == "function" then view.onSearch(text) end
end

-- The sync state: in the footer line of the guild window, and handed to the host (the window's title bar).
function Shell:UpdateStatus()
	local content = self.content
	if not content then return end
	local text = Shell.StatusText()
	content.status:SetText(text)
	if self.host and type(self.host.onStatus) == "function" then self.host.onStatus(text) end
end

function Shell:StartStatus()
	if self.statusTicker then return end
	self.statusTicker = ns.Compat and ns.Compat.NewTicker(Shell.STATUS_REFRESH, function() Shell:UpdateStatus() end)
end

function Shell:StopStatus()
	if self.statusTicker then self.statusTicker:Cancel() self.statusTicker = nil end
end

---------------------------------------------------------------------------------------------------------------------
-- Hosts: the guild tab panel and the standalone window
---------------------------------------------------------------------------------------------------------------------
-- Moves the content into `host` ({ frame, mode, name, onLeave, onStatus }) and shows it. The host it leaves is told
-- (onLeave): the guild panel unchecks its tab, the window closes.
function Shell:Attach(host)
	local content = self:Content()
	if self.host and self.host ~= host and self.host.onLeave then self.host.onLeave() end
	self.host = host
	content:SetParent(host.frame)
	content:ClearAllPoints()
	content:SetAllPoints(host.frame)
	content:SetFrameLevel((host.frame:GetFrameLevel() or 1) + 1)
	content:Show()
	self:Refresh()
end

-- The host went away (its frame was hidden): the content hides with it.
function Shell:Detach(host)
	if self.host ~= host then return end
	self.host = nil
	if self.content then self.content:Hide() end
end

function Shell:IsShown()
	return self.content ~= nil and self.content:IsVisible() == true
end

local function inGuild()
	return ns.Role and ns.Role:InGuild()
end

-- /accord, the key binding and the AddOn Compartment: open or close the standalone window (SPEC-04 §3).
function Shell:Toggle()
	if not inGuild() then
		if ns.addon then ns.addon:Print(L["NOT_IN_GUILD"]) end
		return false
	end
	if ns.Window then return ns.Window:Toggle() end
	return false
end

-- /accord roster|professions|reputation|bank|settings: open that view where the panel is, or in the standalone window.
-- `key` is a view id or "id:page".
function Shell:OpenView(key)
	if not inGuild() then
		if ns.addon then ns.addon:Print(L["NOT_IN_GUILD"]) end
		return false
	end
	local id, page = Shell.SplitKey(key)
	if not Shell.Visible(self.views[id]) then
		if ns.addon then ns.addon:Print(L["COMING_SOON"]) end
		return false
	end
	self.selected = id   -- before the window opens, so the first view built is this one
	if page then self.pageOf[id] = page end
	if not self:IsShown() and ns.Window then ns.Window:Open() end
	return self:Select(key)
end

-- Pop out: from the guild window to the larger standalone window, on the same view.
function Shell:PopOut()
	if ns.GuildTab then ns.GuildTab:HidePanel() end
	if ns.Window then ns.Window:Open() end
end

-- Pop in: from the standalone window back into the guild window. Only while the guild window is open on the guild (the
-- Accord tab shows): the addon never opens Blizzard's window itself (ADR 0003).
function Shell:CanPopIn()
	return ns.GuildTab ~= nil and type(ns.GuildTab.CanHost) == "function" and ns.GuildTab:CanHost() == true
end

function Shell:PopIn()
	if not self:CanPopIn() then return false end
	return ns.GuildTab:ShowPanel()
end

-- The AddOn Compartment tooltip (Core/Init.lua adds the title).
function Shell.FillTooltip(tooltip)
	local Theme = ns.Theme   -- the game's tooltip is Blizzard's dark frame: the game's own colours (Theme.GameColor)
	local r, g, b = Theme.GameColor("text")
	tooltip:AddLine(L["COMPARTMENT_HINT"], r, g, b, true)
	if inGuild() then
		r, g, b = Theme.GameColor("muted")
		tooltip:AddLine(Shell.StatusText(), r, g, b, true)
	end
	local waiting = ns.BankInbox and ns.BankInbox.PendingCount() or 0
	if waiting > 0 then
		r, g, b = Theme.GameColor("gold")
		tooltip:AddLine(L["BANKNOTE_WAITING"]:format(waiting), r, g, b, true)
	end
	local todo = ns.Actions and ns.Actions:Count() or 0   -- 0 while the switch `actions` is off
	if todo > 0 then
		r, g, b = Theme.GameColor("gold")
		tooltip:AddLine(L["ACT_TOOLTIP"]:format(todo), r, g, b, true)
	end
end

if ns.addon then
	ns.addon.Shell = Shell
	if ns.Bus then
		local function update() Shell:UpdateStatus() end
		ns.Bus:On("SYNC_RECEIVED", update)
		ns.Bus:On("SYNC_HELLO", update)
		ns.Bus:On("DEMO_CHANGED", function() Shell:Refresh() end)
		ns.Bus:On("ROLE_CHANGED", function() Shell:Refresh() end)   -- a view may be for officers only
		ns.Bus:On("GUILD_CHANGED", function(key)
			if not key then
				if ns.Window then ns.Window:Close() end
				if ns.GuildTab then ns.GuildTab:HidePanel() end
			end
		end)
	end
end

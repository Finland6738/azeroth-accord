-- MarketView: the "Market" view of the guild economy (M13.2; SPEC-17 §2.2). Lua 5.1.
-- The view has modes, one chip each in its toolbar when there are several; a mode is { label, order, available() -> bool,
-- build(frame), refresh(frame) }. The steps of M13 add theirs with View.AddMode: Orders (UI/Orders.lua, M13.2), then
-- Wishlist, Demand, Board and Goals. Only with the switch "econ" (Core/Features.lua): off, there is no tab.
--   View.AddMode(id, def), View:SetMode(id), View:Open(mode), View:SetSearch(text), View:Changed()
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.MarketView, ns.modules = View, ns.modules or {}
ns.modules.MarketView = View

local L, Widgets = ns.L, ns.Widgets
local type, ipairs, pairs = type, ipairs, pairs

View.TOOLBAR_HEIGHT = 40
View.REFRESH_DELAY = 0.4

View.modes = {}          -- id -> { id, label, order, available, build, refresh, frame }
View.mode = "orders"
View.search = ""

local function on() return ns.Features ~= nil and ns.Features.On("econ") end

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
	if self.frame then self:Redraw() end
	return true
end

-- The Market view on mode `mode` (the one shown last when nil). False while the switch is off.
function View:Open(mode)
	if not on() then return false end
	if mode and not self:SetMode(mode) then return false end
	return ns.Shell ~= nil and ns.Shell:OpenView("market") and true or false
end

function View:Build(f)
	self.frame = f
	f.bar = Widgets.ChipRow(f, function(id) View:SetMode(id) end)
	f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.body = CreateFrame("Frame", nil, f)
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
		self.mode = current and current.id or "orders"
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

function View:SetSearch(text)
	text = type(text) == "string" and text or ""
	if text == self.search then return end
	self.search = text
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

if ns.Shell then
	ns.Shell:RegisterView("market", { label = L["VIEW_MARKET"], order = 42, search = true, visible = on,
		build = function(f) View:Build(f) end,
		onSearch = function(text) View:SetSearch(text) end })
end

if ns.addon then
	ns.addon.MarketView = View
	if ns.Bus then
		ns.Bus:On("ROSTER_UPDATED", function() View:Changed() end)
		ns.Bus:On("RECIPE_NAMES_UPDATED", function() View:Changed() end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.search = ""
			if View.frame then View:Redraw() end
		end)
	end
end

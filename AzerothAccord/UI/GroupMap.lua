-- The group map in the Reputation view (SPEC-07 SOC-11, SOC-12; SPEC-10 Q3). Lua 5.1.
-- A "Groups" mode, only for those who may see the others' index (officers and the Guild Master until Q3 is answered):
--   * a summary: how mixed the guild is (modularity and its reading: everyone plays with everyone / some groups /
--     cliques), the active accounts and the communities;
--   * a simple drawing: each community a circle of coloured dots (one per player, the name on hover, a click opens the
--     card), larger circles for larger communities;
--   * the list of communities: their players (by time together), minutes inside and minutes with the rest of the guild.
-- View.Lines(map) is a plain function (tested offline); the frames only draw it.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.GroupMapView, ns.modules = View, ns.modules or {}
ns.modules.GroupMapView = View

local L, W, Skin = ns.L, ns.Widgets, ns.Skin
local type, ipairs, pairs, tostring, floor, max, min = type, ipairs, pairs, tostring, math.floor, math.max, math.min

View.ROW_HEIGHT = 18
View.NAMES = 6               -- names written per community before "and N more"
View.DOT = 8
View.PALETTE = {
	{ 0.95, 0.75, 0.2 }, { 0.35, 0.7, 1 }, { 0.5, 0.9, 0.4 }, { 1, 0.45, 0.45 }, { 0.8, 0.5, 1 }, { 0.3, 0.9, 0.85 },
	{ 1, 0.6, 0.25 }, { 0.75, 0.75, 0.75 },
}

local function hours(minutes) return L["SOC_HOURS"]:format(floor((minutes or 0) / 6 + 0.5) / 10) end
local function nameOf(key)
	if ns.SocialUI then return ns.SocialUI.NameOf(key) end
	return key
end

-- The summary and list lines of a map: { { text, heading, muted } }.
function View.Lines(map)
	local out = {}
	if not map then
		out[1] = { text = L["MAP_NONE"], muted = true }
		return out
	end
	out[#out + 1] = { text = L["MAP_MIXING_" .. map.mixing:upper()]:format(map.modularity), heading = true }
	out[#out + 1] = { text = L["MAP_SUMMARY"]:format(map.accounts, #map.communities, hours(map.minutes)), muted = true }
	for i, c in ipairs(map.communities) do
		local names = {}
		for j, key in ipairs(c.members) do
			if j > View.NAMES then break end
			names[#names + 1] = (nameOf(key))
		end
		local more = #c.members - #names
		local who = table.concat(names, ", ") .. (more > 0 and L["MAP_MORE"]:format(more) or "")
		out[#out + 1] = { text = L["MAP_GROUP"]:format(i, #c.members, who), community = i }
		out[#out + 1] = { text = L["MAP_GROUP_TIME"]:format(hours(c.inside), hours(c.outside)), muted = true }
	end
	return out
end

local function colorOf(i)
	local c = View.PALETTE[(i - 1) % #View.PALETTE + 1]
	return c[1], c[2], c[3]
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local mode = {}

function mode.build(f)
	View.frame = f
	f.canvas = W.Frame(f, 10, 10)
	f.canvas:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
	f.canvas:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -4)
	f.canvas:SetHeight(220)
	W.Background(f.canvas, "grey", 0.08)
	f.canvas.dots, f.canvas.labels = {}, {}
	f.list = W.Frame(f, 10, 10)
	f.list:SetPoint("TOPLEFT", f.canvas, "BOTTOMLEFT", 0, -6)
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 0)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * 3) end)
	f.list.lines = {}
	f.offset = 0
end

local function dot(canvas, i)
	local d = canvas.dots[i]
	if d then return d end
	d = CreateFrame("Button", nil, canvas)
	d:SetSize(View.DOT, View.DOT)
	d.tex = d:CreateTexture(nil, "ARTWORK")
	d.tex:SetAllPoints(d)
	W.SetTooltip(d, function(self) return self.name end)
	d:SetScript("OnClick", function(self)
		if self.key and ns.ReputationView then ns.ReputationView:OpenCard({ guid = self.key }) end
	end)
	canvas.dots[i] = d
	return d
end

local function label(canvas, i)
	local t = canvas.labels[i]
	if t then return t end
	t = W.Text(canvas, "small", "white", "CENTER")
	canvas.labels[i] = t
	return t
end

function View:Draw(f, map)
	local canvas = f.canvas
	local width, height = canvas:GetWidth() or 0, canvas:GetHeight() or 0
	if width < 50 then width = 500 end
	if height < 50 then height = 220 end
	local layout = map and ns.GroupMap.Layout(map.communities, width, height) or { circles = {}, points = {} }
	local n = 0
	for i, circle in ipairs(layout.circles) do
		local r, g, b = colorOf(i)
		for _, key in ipairs(circle.community.members) do
			local p = layout.points[key]
			n = n + 1
			local d = dot(canvas, n)
			d:ClearAllPoints()
			d:SetPoint("CENTER", canvas, "TOPLEFT", p.x, -p.y)
			d.tex:SetColorTexture(r, g, b, 1)
			d.key, d.name = key, (nameOf(key))
			d:Show()
		end
		local t = label(canvas, i)
		t:ClearAllPoints()
		t:SetPoint("CENTER", canvas, "TOPLEFT", circle.cx, -circle.cy)
		t:SetText(tostring(i))
		t:SetTextColor(r, g, b)
		t:Show()
	end
	for i = n + 1, #canvas.dots do canvas.dots[i]:Hide() end
	for i = #layout.circles + 1, #canvas.labels do canvas.labels[i]:Hide() end
	self.dotsShown = n
	-- the list
	local lines = View.Lines(map)
	self.shown = lines
	local list = f.list
	local h = list:GetHeight() or 0
	local visible = h >= View.ROW_HEIGHT and floor(h / View.ROW_HEIGHT) or 16
	f.offset = max(0, min(f.offset or 0, max(0, #lines - visible)))
	local drawn = max(0, min(visible, #lines - f.offset))
	for i = 1, drawn do
		local l = lines[f.offset + i]
		local fs = list.lines[i]
		if not fs then
			fs = W.Text(list, "body", nil, "LEFT")
			list.lines[i] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", list, "TOPLEFT", l.muted and l.community == nil and 12 or 0, -(i - 1) * View.ROW_HEIGHT)
		fs:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		fs:SetText(l.text)
		if l.heading then fs:SetTextColor(Skin.Color("gold"))
		elseif l.community then fs:SetTextColor(colorOf(l.community))
		else fs:SetTextColor(Skin.Color(l.muted and "grey" or "white")) end
		fs:Show()
	end
	for i = drawn + 1, #list.lines do list.lines[i]:Hide() end
end

function mode.refresh(f)
	View:Draw(f, ns.GroupMap and ns.GroupMap:Current() or nil)
end

function View:Scroll(delta)
	local f = self.frame
	if not f then return false end
	f.offset = max(0, (f.offset or 0) + delta)
	mode.refresh(f)
	return true
end

if ns.ReputationView then
	ns.ReputationView.AddMode("groups", { label = L["REP_MODE_GROUPS"], order = 30, build = mode.build, refresh = mode.refresh,
		available = function() return ns.Social ~= nil and ns.Social:CanSeeOthers() end })
end

if ns.addon then ns.addon.GroupMapView = View end

-- SharePanel: the "What I share" page of Settings (SPEC-11 §5, M7.6). One card per data set this character publishes, with
-- who receives it, when it goes out and its current content (UI/ShareModel.lua reads the records the client last sent).
-- The switches are "Record time played together" on the co-play card (account.settings.shareCoplay) and, while the addon
-- census is switched on (M9.9), "Share my addon list" on its card (account.settings.shareAddons).
-- Fields of the frame `f.share`: .cards[id] = { card, to, content, updated, note, switch }, .intro, .empty. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local L, Widgets = ns.L, ns.Widgets
local Panel = {}
ns.SharePanel, ns.modules = Panel, ns.modules or {}
ns.modules.SharePanel = Panel

local ipairs, max, min = ipairs, math.max, math.min
Panel.PAGE_ID = "share"
local WIDTH, PAD, GAP = 520, 24, 16
local INNER = WIDTH - 2 * PAD

local function text(parent, font, token)
	local fs = Widgets.Text(parent, font, token, "LEFT")
	fs:SetWidth(INNER)
	fs:SetWordWrap(true)
	return fs
end

-- A card whose items stack from the top (as in UI/Settings.lua).
local function stack(page)
	local c = Widgets.Card(page, { width = WIDTH, height = 100 })
	c.items = {}
	function c:Add(region, gap) self.items[#self.items + 1] = { region = region, gap = gap or 8 } return region end
	function c:Layout()
		local y, first = PAD - 4, true
		for _, it in ipairs(self.items) do
			local r = it.region
			if r:IsShown() then
				if not first then y = y + it.gap end
				first = false
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
				y = y + ((r.GetObjectType and r:GetObjectType() == "FontString") and r:GetStringHeight() or r:GetHeight() or 0)
			end
		end
		self:SetHeight(y + PAD - 4)
	end
	return c
end

local function newCard(f, id)
	local info = f.share
	local c = stack(info.page)
	local k = { card = c }
	k.title = c:Add(text(c, "H2", "text-1"), 0)
	k.to = c:Add(text(c, "Small", "text-3"), 4)
	k.content = c:Add(text(c, "Body", "text-2"), 10)
	k.updated = c:Add(text(c, "Small", "text-3"), 8)
	k.note = c:Add(text(c, "Small", "warn"), 8)
	k.switchRow = CreateFrame("Button", nil, c)
	k.switchRow:SetSize(INNER, 32)
	k.switch = Widgets.Switch(k.switchRow, { onChange = function(on) ns.ShareModel.SetSwitch(k.switchKey, on) end })
	k.switch:SetPoint("RIGHT", k.switchRow, "RIGHT", 0, 0)
	k.switchLabel = Widgets.Text(k.switchRow, "Body", "text-1", "LEFT")
	k.switchLabel:SetPoint("LEFT", k.switchRow, "LEFT", 0, 0)
	k.switchLabel:SetPoint("RIGHT", k.switch, "LEFT", -12, 0)
	k.switchRow:SetScript("OnClick", function(self) k.switch:Click() end)
	Widgets.Tooltip.Attach(k.switchRow, function()
		return k.switchTip and { k.switchText, k.switchTip } or nil
	end, "RIGHT")
	c:Add(k.switchRow, 12)
	info.cards[id] = k
	return k
end

-- Fills the cards from the model (the records last sent) and stacks them.
function Panel.Refresh(f)
	local info = f.share
	if not info then return end
	local rows = ns.ShareModel.Describe()
	info.rows = rows
	for _, k in pairs(info.cards) do k.card:Hide() end
	info.empty:SetShown(#rows == 0)
	local y = info.intro:GetStringHeight() + GAP
	if #rows == 0 then y = y + info.empty:GetStringHeight() + GAP end
	for _, row in ipairs(rows) do
		local k = info.cards[row.id] or newCard(f, row.id)
		k.title:SetText(row.title)
		k.to:SetText(row.to .. " · " .. row.when .. (row.always and (" · " .. L["SHARE_ALWAYS"]) or ""))
		k.content:SetText(table.concat(row.lines, "\n"))
		k.updated:SetText(row.age and (row.age .. " · " .. L["SHARE_REVISION"]:format(row.rev)) or "")
		k.updated:SetShown(row.age ~= nil)
		k.note:SetText(row.note or "")
		k.note:SetShown(row.note ~= nil)
		k.switchKey = row.switch
		k.switchRow:SetShown(row.switch ~= nil)
		if row.switch then
			k.switchText, k.switchTip = row.switchLabel, row.switchTip
			k.switchLabel:SetText(row.switchLabel)
			k.switch:SetOn(row.on, true)
		end
		k.card:Show()
		k.card:Layout()
		k.card:ClearAllPoints()
		k.card:SetPoint("TOPLEFT", info.page, "TOPLEFT", 0, -y)
		y = y + k.card:GetHeight() + GAP
	end
	info.height = max(1, y - GAP + 8)
	info.page:SetHeight(info.height)
	local range = max(0, info.height - (info.scroll:GetHeight() or 0))
	if (info.scroll:GetVerticalScroll() or 0) > range then info.scroll:SetVerticalScroll(range) end
end

function Panel.Build(holder, f)
	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetAllPoints(holder)
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(WIDTH, 100)
	scroll:SetScrollChild(page)
	scroll:EnableMouseWheel(true)
	local info = { scroll = scroll, page = page, cards = {}, rows = {} }
	f.share = info
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = max(0, (info.height or 0) - (self:GetHeight() or 0))
		self:SetVerticalScroll(min(range, max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
	end)
	info.intro = text(page, "Body", "text-2")
	info.intro:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	info.intro:SetWidth(WIDTH)
	info.intro:SetText(L["SHARE_INTRO"])
	info.empty = text(page, "Body", "text-3")
	info.empty:SetWidth(WIDTH)
	info.empty:SetPoint("TOPLEFT", info.intro, "BOTTOMLEFT", 0, -GAP)
	info.empty:SetText(L["SHARE_EMPTY"])
	holder:SetScript("OnShow", function() Panel.Refresh(f) end)
	Panel.Refresh(f)
end

-- Every page built is refreshed when what it shows changes and it is on screen.
local function refreshVisible()
	local V = ns.SettingsView
	if not V then return end
	for _, f in ipairs(V.instances) do
		local holder = f.holders and f.holders[Panel.PAGE_ID]
		if holder and holder:IsVisible() then Panel.Refresh(f) end
	end
end

if ns.SettingsView then
	ns.SettingsView.AddPage(Panel.PAGE_ID, { label = L["SHARE_TAB"], order = 15, build = Panel.Build })
end
if ns.Bus then
	ns.Bus:On("SETTINGS_CHANGED", refreshVisible)
	ns.Bus:On("STORE_CHANGED", function(_, _, origin) if origin == "local" or origin == "backup" then refreshVisible() end end)
	ns.Bus:On("GUILD_CHANGED", refreshVisible)
	ns.Bus:On("ROLE_CHANGED", refreshVisible)
end
if ns.addon then ns.addon.SharePanel = Panel end

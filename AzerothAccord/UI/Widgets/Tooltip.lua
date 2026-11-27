-- Widget kit, part 5: the addon's own Tooltip (docs/specs/ui-style.md §3, §9.6): one frame for the whole addon, in the
-- two forms of Material 3 (M12.7):
--   plain  one short line (the name of an icon, a hint): inverse-surface with the text in inverse-on-surface, radius 4,
--          body small, 8 points of padding, at least 24 high;
--   rich   several lines, a line with its own token, or one too long for a single line: surface-3, radius 12, a shadow,
--          16 points of padding; the first of several lines is the title (medium, accent-text), 8 points over the text.
-- It shows lines the caller already translated;
-- the game's GameTooltip is used for ITEMS only (Tooltip.Item: the comparison and the link) and is never reskinned.
-- M6.11, new in Azeroth Accord (FDCP only describes it). Lua 5.1; one unprotected frame made on first use.
--   Widgets.Tooltip.Show(owner, content, anchor)   content: "text" | { "title", "line", { text = "...", token = "ok" } ... }
--   Widgets.Tooltip.Hide()
--   Widgets.Tooltip.Attach(frame, source, anchor)  source: content | function(owner) -> content (nil shows nothing)
--   Widgets.Tooltip.Item(owner, link, anchor) / Widgets.Tooltip.HideItem() / Widgets.Tooltip.AttachItem(frame, function(owner) -> link)
-- anchor: "BOTTOM" (default, under the owner), "TOP", "RIGHT", "LEFT", or a point { point, relativeTo, relativePoint, x, y }
-- (2026-11-27: a recipe's tooltip next to its name, not at the far end of the row).
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme = ns.Widgets, ns.Theme
local type, ipairs, tostring, max, min = type, ipairs, tostring, math.max, math.min

local Tooltip = {}
Widgets.Tooltip = Tooltip

Tooltip.MAX_WIDTH, Tooltip.MAX_LINES = 280, 16
-- padding, the room under a title, the room between two lines of text, the smallest height
local PLAIN = { pad = 8, minHeight = 24 }
local RICH = { pad = 16, titleGap = 8, lineGap = 4 }
local OFFSET = 6

local frame   -- made on first use

local function build()
	local f = CreateFrame("Frame", "AzerothAccordTooltip", UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetClampedToScreen(true)
	f:EnableMouse(false)   -- it never takes a click: the pointer goes through to what is under it
	f.plain = Theme.Panel(f, { radius = "extra-small", fill = "inverse-surface", border = false })
	f.rich = Theme.Panel(f, { radius = "medium", fill = "surface-3", border = false, shadow = true })
	f.lines = {}
	f:Hide()
	return f
end

-- Draws the box in one of the two forms; `.parts` are the regions of the one on screen.
local function form(f, rich)
	f.isRich = rich
	f.parts = rich and f.rich or f.plain
	f.plain.fill:SetShown(not rich)
	f.rich.fill:SetShown(rich)
	f.rich.shadow:SetShown(rich and Theme.EffectsOn())
end

local function line(f, i)
	local fs = f.lines[i]
	if not fs then
		fs = Theme.NewText(f, "Body", "text-1")
		fs:SetJustifyH("LEFT")
		if fs.SetWordWrap then fs:SetWordWrap(true) end
		f.lines[i] = fs
	end
	return fs
end

local function normalise(content)
	local list = {}
	if type(content) == "table" and content.text == nil then
		for i = 1, min(#content, Tooltip.MAX_LINES) do list[i] = content[i] end
	elseif content ~= nil then
		list[1] = content
	end
	return list
end

local function textOf(entry) return type(entry) == "table" and tostring(entry.text or "") or tostring(entry) end

-- Shows `content` next to `owner`. Returns the frame, or nil when there is nothing to show.
function Tooltip.Show(owner, content, anchor)
	local list = normalise(content)
	if #list == 0 then Tooltip.Hide(); return nil end
	frame = frame or build()
	local f = frame
	-- one line without a colour of its own may be a plain tooltip, if it fits one line
	local rich = #list > 1 or type(list[1]) == "table" and list[1].token ~= nil
	local widest = 0
	local function write(i, font, token)
		local fs = line(f, i)
		fs:SetFontObject(Theme.Font(font))
		fs:SetWidth(0)   -- natural width first
		fs:SetText(textOf(list[i]))
		Theme.Text(fs, token)
		return fs:GetStringWidth() or 0
	end
	if not rich then
		widest = write(1, "body-small", "inverse-on-surface")
		rich = widest > Tooltip.MAX_WIDTH
	end
	if rich then
		widest = 0
		for i, entry in ipairs(list) do
			local title = i == 1 and #list > 1
			local token = type(entry) == "table" and entry.token or (title and "accent-text" or "text-1")
			widest = max(widest, write(i, title and "BodyMedium" or "Body", token))
		end
	end
	form(f, rich)
	for i = #list + 1, #f.lines do f.lines[i]:SetText(""); f.lines[i]:Hide() end
	local box = rich and RICH or PLAIN
	local width = min(max(widest, 24), Tooltip.MAX_WIDTH)
	local y = box.pad
	for i = 1, #list do
		local fs = f.lines[i]
		if i > 1 then y = y + (i == 2 and RICH.titleGap or RICH.lineGap) end
		fs:ClearAllPoints()
		fs:SetWidth(width)
		fs:SetPoint("TOPLEFT", f, "TOPLEFT", box.pad, -y)
		fs:Show()
		y = y + (fs:GetStringHeight() or 14)
	end
	f:SetSize(width + box.pad * 2, max(box.minHeight or 0, y + box.pad))
	f.owner = owner
	f:ClearAllPoints()
	anchor = anchor or "BOTTOM"
	if type(anchor) == "table" then f:SetPoint(unpack(anchor))
	elseif anchor == "TOP" then f:SetPoint("BOTTOM", owner, "TOP", 0, OFFSET)
	elseif anchor == "RIGHT" then f:SetPoint("LEFT", owner, "RIGHT", OFFSET, 0)
	elseif anchor == "LEFT" then f:SetPoint("RIGHT", owner, "LEFT", -OFFSET, 0)
	else f:SetPoint("TOP", owner, "BOTTOM", 0, -OFFSET) end
	f:Show()
	return f
end

function Tooltip.Hide()
	if frame then frame.owner = nil; frame:Hide() end
end

function Tooltip.IsShown() return frame ~= nil and frame:IsShown() end
function Tooltip.Owner() return frame and frame.owner end
function Tooltip.Frame() return frame end
function Tooltip.Lines()
	local out = {}
	if frame then
		for _, fs in ipairs(frame.lines) do if fs:IsShown() then out[#out + 1] = fs:GetText() end end
	end
	return out
end

-- Shows the tooltip while the mouse is over `frame` (a hook: the frame keeps its own scripts). `source` is a content or
-- a function(owner) returning one.
function Tooltip.Attach(target, source, anchor)
	target:HookScript("OnEnter", function(self)
		local content = source
		if type(source) == "function" then content = source(self) end   -- nil: nothing to show (not `and/or`: it would fall back)
		if content ~= nil then Tooltip.Show(self, content, anchor) end
	end)
	target:HookScript("OnLeave", function() Tooltip.Hide() end)
	target:HookScript("OnHide", function(self) if Tooltip.Owner() == self then Tooltip.Hide() end end)
end

-- --- items: the game's own tooltip ------------------------------------------------------------------------------------

-- The tooltip of an item (a link or an item id): the game's GameTooltip, which has the comparison with what is worn.
function Tooltip.Item(owner, link, anchor)
	if not GameTooltip or not link then return false end
	if type(anchor) == "table" then
		GameTooltip:SetOwner(owner, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint(unpack(anchor))
	else
		GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	end
	if type(link) == "number" and GameTooltip.SetItemByID then GameTooltip:SetItemByID(link)
	elseif GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(link) end
	GameTooltip:Show()
	return true
end

function Tooltip.HideItem()
	if GameTooltip then GameTooltip:Hide() end
end

function Tooltip.AttachItem(target, source, anchor)
	target:HookScript("OnEnter", function(self)
		local link = source
		if type(source) == "function" then link = source(self) end
		if link ~= nil then Tooltip.Item(self, link, anchor) end
	end)
	target:HookScript("OnLeave", function() Tooltip.HideItem() end)
end

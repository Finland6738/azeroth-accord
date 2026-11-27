-- Window: the standalone Accord window (SPEC-04 §3, docs/specs/ui-style.md §3, ADR 0003 point 3). Lua 5.1.
-- The same panel as the guild tab, in a window of the addon's own (no Blizzard window template): a Theme panel of radius
-- 12 with its shadow, the 52-point title bar of the kit (logo, "AZEROTH ACCORD", the sync state under it, Pop in while
-- the guild window can take the panel back, close) and the panel under it. Opened by /accord, the AddOn Compartment,
-- the key binding or "Pop out"; movable by its title bar, resizable from the grip in the corner (920 x 600 at first,
-- 720 x 460 at least). It remembers its position and size per character (AzerothAccordCharDB.ui), closes with Esc and
-- is the fallback when the guild window cannot host the tab (GT-05). Every colour is a theme token: Theme.Apply repaints it.
local ADDON_NAME, ns = ...
ns = ns or {}
local Window = {}
ns.Window, ns.modules = Window, ns.modules or {}
ns.modules.Window = Window

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, tonumber, min, max = type, tonumber, math.min, math.max

Window.NAME = "AzerothAccordWindow"
-- 1380 × 720 since 2026-11-27 (920 × 600 was too narrow for the Roster in game); never wider than the screen
Window.WIDTH, Window.HEIGHT = 1380, 720   -- 1380 since 2026-11-27 (owner: 100 more)
Window.SIZE_VERSION = 3       -- a size saved before the new default (no `v`) is not reused once
Window.MIN_WIDTH, Window.MIN_HEIGHT = 720, 460
Window.MAX_WIDTH, Window.MAX_HEIGHT = 1600, 1000
Window.TITLE_BAR = 52

local function config() return ns.Config end

local function savePosition(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	if type(point) == "string" and type(x) == "number" and type(y) == "number" and config() then
		config():Set("char.ui.windowPos", { point = point, relPoint = type(relPoint) == "string" and relPoint or point, x = x, y = y })
	end
end

local function saveSize(f)
	local w, h = f:GetWidth(), f:GetHeight()
	if type(w) == "number" and type(h) == "number" and config() then
		config():Set("char.ui.windowSize", { w = w, h = h, v = Window.SIZE_VERSION })
	end
end

-- A saved size inside the bounds (a size saved before M6.12 may be below today's minimum).
function Window.ClampSize(w, h)
	w = min(Window.MAX_WIDTH, max(Window.MIN_WIDTH, tonumber(w) or Window.WIDTH))
	h = min(Window.MAX_HEIGHT, max(Window.MIN_HEIGHT, tonumber(h) or Window.HEIGHT))
	return w, h
end

local function place(f)
	local pos = config() and config():Get("char.ui.windowPos")
	local size = config() and config():Get("char.ui.windowSize")
	if size and size.v ~= Window.SIZE_VERSION then size = nil end   -- saved with the old, smaller default
	local w, h = Window.ClampSize(size and size.w, size and size.h)
	local sw, sh = UIParent and UIParent:GetWidth(), UIParent and UIParent:GetHeight()
	if not size and type(sw) == "number" and sw > 0 then   -- the default fits the screen
		w = max(Window.MIN_WIDTH, min(w, sw - 40))
		if type(sh) == "number" and sh > 0 then h = max(Window.MIN_HEIGHT, min(h, sh - 80)) end
	end
	f:SetSize(w, h)
	f:ClearAllPoints()
	if pos then f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
	else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

local function buildTitleBar(f)
	local bar = Widgets.TitleBar(f, { title = L["WINDOW_TITLE"], subtitle = "", closeLabel = L["WINDOW_CLOSE"],
		onClose = function() Window:Close() end })
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	-- the window moves by its title bar (and by any free spot of the panel)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePosition(f) end)
	-- Pop in, left of the close button, only while the guild window can take the panel (Window:UpdatePopIn)
	bar.popIn = Widgets.Button(bar, { text = L["POP_IN"], style = "text", dense = true, onClick = function() ns.Shell:PopIn() end })
	bar.popIn:SetPoint("RIGHT", bar.close, "LEFT", -8, 0)
	bar.popIn:Hide()
	if Widgets.Tooltip then Widgets.Tooltip.Attach(bar.popIn, { L["POP_IN"], L["POP_IN_TIP"] }, "BOTTOM") end
	f.titleBar = bar
end

-- The resize grip in the bottom-right corner: the kit's "dashed" icon tinted text-3, the accent under the mouse.
local function buildGrip(f)
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel((f:GetFrameLevel() or 1) + 30)   -- over the views in the body
	grip.icon = grip:CreateTexture(nil, "OVERLAY")
	grip.icon:SetTexture(ns.Assets.textures.icons.path)
	grip.icon:SetTexCoord(ns.Assets.IconCoords("dashed"))
	grip.icon:SetAllPoints(grip)
	Theme.Tint(grip.icon, "text-3", 0.6)
	grip:SetScript("OnEnter", function(self) Theme.Tint(self.icon, "accent-text") end)
	grip:SetScript("OnLeave", function(self) Theme.Tint(self.icon, "text-3", 0.6) end)
	if Widgets.Tooltip then Widgets.Tooltip.Attach(grip, L["WINDOW_RESIZE"], "TOP") end
	grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() saveSize(f) savePosition(f) end)
	f.grip = grip
end

local function build()
	local f = CreateFrame("Frame", Window.NAME, UIParent)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(Window.MIN_WIDTH, Window.MIN_HEIGHT, Window.MAX_WIDTH, Window.MAX_HEIGHT) end
	f:EnableMouse(true)   -- clicks on the window do not fall through to the world
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition(self) end)
	f.parts = Theme.Panel(f, { radius = 12, fill = "bg", border = "border", shadow = true, highlight = true })
	buildTitleBar(f)

	-- the area under the title bar where the panel goes
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Window.TITLE_BAR)
	f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	buildGrip(f)

	Window.host = {
		frame = f.body, mode = "window", name = "window",
		onLeave = function() Window:Close() end,                       -- the guild tab took the panel
		onStatus = function(text) f.titleBar.subtitle:SetText(text) end, -- the sync state under the title
	}
	f:SetScript("OnShow", function() ns.Shell:Attach(Window.host) Window:UpdatePopIn() end)
	f:SetScript("OnHide", function() ns.Shell:Detach(Window.host) end)
	Widgets.CloseOnEscape(Window.NAME)
	f:Hide()
	place(f)
	return f
end

function Window:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

function Window:Open()
	local f = self:Frame()
	if not f:IsShown() then f:Show() end
	if f.Raise then f:Raise() end
	return f
end

function Window:Close()
	if self.frame and self.frame:IsShown() then self.frame:Hide() end
end

function Window:Toggle()
	if self.frame and self.frame:IsShown() then self:Close() return false end
	self:Open()
	return true
end

function Window:IsShown() return self.frame ~= nil and self.frame:IsShown() end

-- Pop in shows while the guild window is open on the guild (UI/GuildTab.lua calls this when that changes).
function Window:UpdatePopIn()
	local f = self.frame
	if not f then return end
	f.titleBar.popIn:SetShown(ns.Shell ~= nil and ns.Shell:CanPopIn())
end

-- Back to the default size in the middle of the screen (and forget the saved place).
function Window:ResetPosition()
	if config() then
		config():Set("char.ui.windowPos", nil)
		config():Set("char.ui.windowSize", nil)
	end
	if self.frame then place(self.frame) end
end

if ns.addon then ns.addon.Window = Window end

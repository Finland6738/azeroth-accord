-- Window: the standalone Accord window (SPEC-04 §3, ADR 0003 point 3). Lua 5.1.
-- The same panel as the guild tab, in a movable and resizable window opened by /accord, the AddOn Compartment, the key
-- binding or "Pop out". It remembers its position and size per character (AzerothAccordCharDB.ui), closes with Esc and
-- is the fallback when the guild window cannot host the tab (GT-05).
local ADDON_NAME, ns = ...
ns = ns or {}
local Window = {}
ns.Window, ns.modules = Window, ns.modules or {}
ns.modules.Window = Window

local L, W = ns.L, ns.Widgets
local type, pcall = type, pcall

Window.NAME = "AzerothAccordWindow"
Window.WIDTH, Window.HEIGHT = 820, 520
Window.MIN_WIDTH, Window.MIN_HEIGHT = 640, 400
Window.MAX_WIDTH, Window.MAX_HEIGHT = 1600, 1000

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
		config():Set("char.ui.windowSize", { w = w, h = h })
	end
end

local function place(f)
	local pos = config() and config():Get("char.ui.windowPos")
	local size = config() and config():Get("char.ui.windowSize")
	f:SetSize(size and size.w or Window.WIDTH, size and size.h or Window.HEIGHT)
	f:ClearAllPoints()
	if pos then f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
	else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

-- The title of a Blizzard window template (several layouts exist), or a font string of our own.
local function setTitle(f, text)
	local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
	if title and title.SetText then
		title:SetText(text)
	else
		f.ownTitle = f.ownTitle or W.Text(f, "heading", "gold", "CENTER")
		f.ownTitle:SetPoint("TOP", f, "TOP", 0, -6)
		f.ownTitle:SetText(text)
	end
end

local function setPortrait(f)
	local portrait = f.portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
	if portrait and portrait.SetTexture then pcall(portrait.SetTexture, portrait, ns.Assets.logos.logo_64.path) end
end

local function build()
	local f, template = W.Create("Frame", Window.NAME, UIParent, "window")
	f.template = template
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(Window.MIN_WIDTH, Window.MIN_HEIGHT, Window.MAX_WIDTH, Window.MAX_HEIGHT) end
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition(self) end)
	if template == "" then W.Background(f, "panel", 0.95) end
	setTitle(f, L["ADDON_TITLE"])
	setPortrait(f)
	if not f.CloseButton then
		f.CloseButton = W.CloseButton(f, function() Window:Close() end)
		f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	end

	-- the area under the title where the panel goes
	f.body = W.Frame(f, 10, 10)
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
	f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

	-- the resize grip in the bottom-right corner
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
	pcall(grip.SetNormalTexture, grip, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	pcall(grip.SetHighlightTexture, grip, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	pcall(grip.SetPushedTexture, grip, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() saveSize(f) savePosition(f) end)
	f.grip = grip

	Window.host = { frame = f.body, mode = "window", name = "window" }
	f:SetScript("OnShow", function() ns.Shell:Attach(Window.host) end)
	f:SetScript("OnHide", function() ns.Shell:Detach(Window.host) end)
	W.CloseOnEscape(f)
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

-- Back to the default size in the middle of the screen (and forget the saved place).
function Window:ResetPosition()
	if config() then
		config():Set("char.ui.windowPos", nil)
		config():Set("char.ui.windowSize", nil)
	end
	if self.frame then place(self.frame) end
end

if ns.addon then ns.addon.Window = Window end

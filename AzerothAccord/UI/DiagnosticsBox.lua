-- Diagnostics box: `/accord debug` opens the report (Core/Diagnostics.lua) in a read-only multi-line edit box, selected,
-- so the player presses Ctrl+C and pastes it into a bug report (addons cannot reach the clipboard). Esc closes it.
-- Adapted from Azeroth Guild Finder (UI/DiagnosticsBox.lua), same owner, GPL-3.0 (ADR 0018), drawn with the client's
-- own window template. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.DiagnosticsBox, ns.modules = Box, ns.modules or {}
ns.modules.DiagnosticsBox = Box

local L, W, Skin = ns.L, ns.Widgets, ns.Skin
Box.NAME = "AzerothAccordDiagnosticsBox"
Box.WIDTH, Box.HEIGHT = 640, 460

local function build()
	local f, template = W.Create("Frame", Box.NAME, UIParent, { "BasicFrameTemplateWithInset", "" })
	f:SetSize(Box.WIDTH, Box.HEIGHT)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
	f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
	if template == "" then W.Background(f, "panel", 0.97) end

	f.title = W.Text(f, "heading", "gold", "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -6)
	f.title:SetText(L["DIAG_TITLE"])
	f.hint = W.Text(f, "small", nil, "LEFT")
	f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.hint:SetText(L["DIAG_HINT"])

	local scroll = W.Create("ScrollFrame", nil, f, "scroll")
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -56)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 46)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	local font = Skin.Font("mono")
	if font then edit:SetFontObject(font) end
	edit:SetWidth(Box.WIDTH - 60)
	scroll:SetScrollChild(edit)
	f.scroll, f.edit = scroll, edit

	-- read-only: typing is undone at once and the text stays selected
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= f.text then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() Box:Hide() end)

	f.selectAll = W.Button(f, { text = L["DIAG_SELECT"], width = 120, onClick = function() Box:SelectAll() end })
	f.selectAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
	f.close = W.Button(f, { text = L["DIAG_CLOSE"], width = 100, onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	W.CloseOnEscape(f)
	f:Hide()
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

-- Opens the box with `text` (a fresh report when nil), selected, ready for Ctrl+C. Returns the text.
function Box:Open(text)
	local f = self:Frame()
	text = text or ns.Diagnostics.Report()
	f.text = text
	f.edit:SetText(text)
	f.edit:SetCursorPosition(0)
	f.scroll:SetVerticalScroll(0)
	f:Show()
	self:SelectAll()
	return text
end

function Box:SelectAll()
	local f = self.frame
	if not f then return end
	f.edit:SetFocus()
	f.edit:HighlightText()
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.frame and self.frame.text or nil end

if ns.addon then ns.addon.DiagnosticsBox = Box end

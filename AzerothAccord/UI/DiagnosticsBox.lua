-- Diagnostics box: `/accord debug` opens the report (Core/Diagnostics.lua) in a read-only multi-line edit box, selected,
-- so the player presses Ctrl+C and pastes it into a bug report (addons cannot reach the clipboard). Esc closes it.
-- Adapted from Azeroth Guild Finder (UI/DiagnosticsBox.lua), same owner, GPL-3.0 (ADR 0018); drawn as a Widgets.Dialog (the veil
-- and the centred card of the CopyBox, M6.14). Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.DiagnosticsBox, ns.modules = Box, ns.modules or {}
ns.modules.DiagnosticsBox = Box

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
Box.NAME = "AzerothAccordDiagnosticsBox"
Box.WIDTH, Box.HEIGHT = 640, 460
Box.WHEEL_STEP = 40

local function build()
	local f = Widgets.Dialog(UIParent, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT })
	local card = f.card
	f.title = Widgets.Text(card, "H2", "text-1", "LEFT")
	f.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -22)
	f.title:SetText(L["DIAG_TITLE"])
	f.hint = Widgets.Text(card, "Small", "text-3", "LEFT")
	f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.hint:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.hint:SetText(L["DIAG_HINT"])

	-- the report: a multi-line edit box in a surface-2 field that scrolls with the wheel
	f.field = CreateFrame("Frame", nil, card)
	f.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -72)
	f.field:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 64)
	f.field.fill = Theme.Slice(f.field, "rr_fill_8", "surface-2", "BACKGROUND")
	f.field.fill:SetAllPoints(f.field)
	f.field.ring = Theme.Slice(f.field, "rr_ring_8", "border", "BORDER")
	f.field.ring:SetAllPoints(f.field)
	local scroll = CreateFrame("ScrollFrame", nil, f.field)
	scroll:SetPoint("TOPLEFT", f.field, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", f.field, "BOTTOMRIGHT", -10, 8)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local v = (self:GetVerticalScroll() or 0) - delta * Box.WHEEL_STEP
		self:SetVerticalScroll(math.min(range, math.max(0, v)))
	end)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(Theme.Font("MonoSmall"))
	Theme.Text(edit, "text-1")
	edit:SetWidth(Box.WIDTH - 68)
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

	f.selectAll = Widgets.Button(card, { text = L["DIAG_SELECT"], style = "secondary", onClick = function() Box:SelectAll() end })
	f.selectAll:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 20)
	f.size = Widgets.Text(card, "MonoSmall", "text-3", "CENTER")
	f.size:SetPoint("BOTTOM", card, "BOTTOM", 0, 30)
	f.close = Widgets.Button(card, { text = L["DIAG_CLOSE"], style = "primary", onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
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
	local lines = select(2, text:gsub(string.char(10), "")) + 1
	f.size:SetText(L["DIAG_SIZE"]:format(lines, #text))
	f.edit:SetText(text)
	f.edit:SetCursorPosition(0)
	f.scroll:SetVerticalScroll(0)
	f:Open()
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

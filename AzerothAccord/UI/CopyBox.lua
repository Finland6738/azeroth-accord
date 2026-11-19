-- CopyBox: a small box with one text already selected, so the player presses Ctrl+C (addons cannot reach the clipboard)
-- (SPEC-05 CON-03: a click on a contact opens it). Read-only: typing is undone at once. Esc closes it. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.CopyBox, ns.modules = Box, ns.modules or {}
ns.modules.CopyBox = Box

local L, W = ns.L, ns.Widgets
Box.NAME = "AzerothAccordCopyBox"
Box.WIDTH, Box.HEIGHT = 340, 120

local function build()
	local f, template = W.Create("Frame", Box.NAME, UIParent, { "BasicFrameTemplateWithInset", "" })
	f:SetSize(Box.WIDTH, Box.HEIGHT)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	if template == "" then W.Background(f, "panel", 0.97) end
	f.title = W.Text(f, "heading", "gold", "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -6)
	f.hint = W.Text(f, "small", nil, "LEFT")
	f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.hint:SetText(L["COPY_HINT"])
	local edit = CreateFrame("EditBox", nil, f)
	edit:SetSize(Box.WIDTH - 40, 22)
	edit:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -56)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(64)
	local font = ns.Skin.Font("body")
	if font then edit:SetFontObject(font) end
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= f.text then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() Box:Hide() end)
	f.edit = edit
	f.close = W.Button(f, { text = L["COPY_CLOSE"], width = 90, onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
	W.CloseOnEscape(f)
	f:Hide()
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

-- Opens the box with `text` selected; `title` says what it is ("Battle.net name"). Returns the frame.
function Box:Open(text, title)
	local f = self:Frame()
	f.text = tostring(text or "")
	f.title:SetText(title or "")
	f.edit:SetText(f.text)
	f.edit:SetCursorPosition(0)
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
	return f
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.frame and self.frame.text or nil end

if ns.addon then ns.addon.CopyBox = Box end

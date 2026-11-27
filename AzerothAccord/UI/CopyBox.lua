-- CopyBox: a small box with one text already selected, so the player presses Ctrl+C (addons cannot reach the clipboard)
-- (SPEC-05 CON-03: a click on a contact opens it). Read-only: typing is undone at once. Esc closes it. Lua 5.1.
-- CopyBox.Area is the field of the long texts (the personal backup, SPEC-11 §4, and the exports, SPEC-12 §6).
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.CopyBox, ns.modules = Box, ns.modules or {}
ns.modules.CopyBox = Box

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
Box.NAME = "AzerothAccordCopyBox"
Box.WIDTH, Box.HEIGHT = 380, 196
Box.WHEEL_STEP = 40

-- A multi-line edit box in the look of a text field (Widgets.TextArea) that scrolls with the wheel: returns the field (the caller places it), the
-- scroll frame and the edit box. The edit box has no limit of letters; the caller sets the scripts and checks the length.
function Box.Area(parent, width)
	local field = Widgets.TextArea(parent)
	local scroll = CreateFrame("ScrollFrame", nil, field)
	scroll:SetPoint("TOPLEFT", field, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -10, 8)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local v = (self:GetVerticalScroll() or 0) - delta * Box.WHEEL_STEP
		self:SetVerticalScroll(math.min(range, math.max(0, v)))
	end)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(Theme.Font("MonoSmall"))
	Theme.Text(edit, "text-1")
	edit:SetWidth(width)
	scroll:SetScrollChild(edit)
	field:Track(edit)   -- the focus ring (hooked: a caller hooks its own focus scripts too, a SetScript would drop these)
	return field, scroll, edit
end

-- A Widgets.Dialog (a veil over the screen and a centred card, Esc closes it): the title, the hint, one read-only field with
-- its text selected, and a Close button.
local function build()
	local f = Widgets.Dialog(UIParent, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT })
	local card = f.card
	f:SetTitle("")
	f.hint = Theme.NewText(card, "Small", "text-3")
	f.hint:SetJustifyH("LEFT")
	f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.hint:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.hint:SetText(L["COPY_HINT"])
	f.field = Widgets.EditBox(card, { width = Box.WIDTH - 48, maxLetters = 64 })
	f.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -76)
	local edit = f.field.edit
	-- read-only: what the player types is undone at once and the text stays selected
	edit:HookScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= f.text then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:HookScript("OnEscapePressed", function() Box:Hide() end)
	f.edit = edit
	f.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "tonal", onClick = function() Box:Hide() end })
	f:SetActions({ f.close })
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
	f.edit:SetMaxLetters(math.max(64, #f.text))   -- a long web address is not cut
	f.edit:SetText(f.text)
	f.edit:SetCursorPosition(0)
	f:Open()
	f.edit:SetFocus()
	f.edit:HighlightText()
	return f
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.frame and self.frame.text or nil end

if ns.addon then ns.addon.CopyBox = Box end

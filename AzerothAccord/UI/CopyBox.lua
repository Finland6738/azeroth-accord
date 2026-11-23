-- CopyBox: a small box with one text already selected, so the player presses Ctrl+C (addons cannot reach the clipboard)
-- (SPEC-05 CON-03: a click on a contact opens it). Read-only: typing is undone at once. Esc closes it. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.CopyBox, ns.modules = Box, ns.modules or {}
ns.modules.CopyBox = Box

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
Box.NAME = "AzerothAccordCopyBox"
Box.WIDTH, Box.HEIGHT = 380, 196

-- A Widgets.Dialog (a veil over the screen and a centred card, Esc closes it): the title, the hint, one read-only field with
-- its text selected, and a Close button.
local function build()
	local f = Widgets.Dialog(UIParent, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT })
	local card = f.card
	f.title = Theme.NewText(card, "H2", "text-1")
	f.title:SetJustifyH("LEFT")
	f.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -22)
	f.title:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.hint = Theme.NewText(card, "Small", "text-3")
	f.hint:SetJustifyH("LEFT")
	f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.hint:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.hint:SetText(L["COPY_HINT"])
	f.field = Widgets.EditBox(card, { width = Box.WIDTH - 48, height = 32, maxLetters = 64 })
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
	f.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "secondary", onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
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
	f:Open()
	f.edit:SetFocus()
	f.edit:HighlightText()
	return f
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:GetText() return self.frame and self.frame.text or nil end

if ns.addon then ns.addon.CopyBox = Box end

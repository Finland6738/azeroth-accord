-- BackupBox: the box of the personal backup (SPEC-11 §4.3-4.5, M7.5). Lua 5.1.
-- Export: the text, read-only and already selected (Ctrl+C), under the warning that it holds the account token.
-- Import: an empty box to paste into (Ctrl+V) and Check; a valid text shows the preview of what changes, then Import /
-- Cancel; a refused one says why and nothing changes. Esc closes it. Data/Backup.lua does the work; this file only draws.
-- The text is never printed or logged: it lives in the edit box and in this frame until the box closes.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.BackupBox, ns.modules = Box, ns.modules or {}
ns.modules.BackupBox = Box

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
Box.NAME = "AzerothAccordBackupBox"
Box.WIDTH, Box.HEIGHT = 640, 480
Box.WHEEL_STEP = 40

local function B() return ns.Backup end

local function say(fs, msg, token)
	fs:SetText(msg or "")
	Theme.Text(fs, token or "text-2")
end

local function build()
	local f = Widgets.Dialog(UIParent, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT })
	local card = f.card
	f.title = Widgets.Text(card, "H2", "text-1", "LEFT")
	f.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -22)
	f.warning = Widgets.Text(card, "Small", "warn", "LEFT")
	f.warning:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.warning:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.hint = Widgets.Text(card, "Small", "text-3", "LEFT")
	f.hint:SetPoint("TOPLEFT", f.warning, "BOTTOMLEFT", 0, -4)
	f.hint:SetPoint("RIGHT", card, "RIGHT", -24, 0)

	-- the text: a multi-line edit box in a surface-2 field that scrolls with the wheel
	f.field = CreateFrame("Frame", nil, card)
	f.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -96)
	f.field:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 88)
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
	edit:SetMaxLetters(0)   -- no limit: the length is checked by Data/Backup.lua (256 KB)
	edit:SetFontObject(Theme.Font("MonoSmall"))
	Theme.Text(edit, "text-1")
	edit:SetWidth(Box.WIDTH - 68)
	scroll:SetScrollChild(edit)
	f.scroll, f.edit = scroll, edit

	-- export and preview are read-only (typing is undone at once); in the paste step the player writes freely
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and f.readOnly and self:GetText() ~= f.text then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self) if f.readOnly then self:HighlightText() end end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() Box:Hide() end)

	f.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	f.status:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 68)
	f.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)

	f.left = Widgets.Button(card, { text = L["BACKUP_SELECT"], style = "secondary", width = 140, onClick = function() Box:Left() end })
	f.left:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 20)
	f.right = Widgets.Button(card, { text = L["BACKUP_CLOSE"], style = "primary", width = 140, onClick = function() Box:Right() end })
	f.right:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
	f:HookScript("OnHide", function() Box:Forget() end)
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

-- Puts `text` in the field; read-only text is selected.
local function fill(f, text, readOnly)
	f.readOnly = readOnly
	f.text = text or ""
	f.edit:SetText(f.text)
	f.edit:SetCursorPosition(0)
	f.scroll:SetVerticalScroll(0)
	if readOnly then
		f.edit:SetFocus()
		f.edit:HighlightText()
	end
end

-- The steps: "export", "paste", "preview", "done".
local function step(f, name)
	f.step = name
	if name == "export" then
		f.left:SetLabel(L["BACKUP_SELECT"])
		f.right:SetLabel(L["BACKUP_CLOSE"])
	elseif name == "paste" then
		f.left:SetLabel(L["BACKUP_CANCEL"])
		f.right:SetLabel(L["BACKUP_CHECK"])
	elseif name == "preview" then
		f.left:SetLabel(L["BACKUP_CANCEL"])
		f.right:SetLabel(L["BACKUP_APPLY"])
	else
		f.left:SetLabel(L["BACKUP_SELECT"])
		f.right:SetLabel(L["BACKUP_CLOSE"])
	end
	f.left:SetShown(name ~= "done")
end

-- Export: the text of this account, selected. Returns the text, or nil and the reason.
function Box:OpenExport()
	local f = self:Frame()
	f.title:SetText(L["BACKUP_EXPORT_TITLE"])
	f.warning:SetText(L["BACKUP_WARNING"])
	f.hint:SetText(L["BACKUP_EXPORT_HINT"])
	step(f, "export")
	f:Open()
	local text, info = B():Export()
	if not text then
		fill(f, "", true)
		say(f.status, B().Message(info), "err")
		return nil, info
	end
	fill(f, text, true)
	say(f.status, L["BACKUP_EXPORT_SIZE"]:format(info.length, info.chars, info.records), "text-3")
	return text
end

-- Import: an empty box to paste into.
function Box:OpenImport()
	local f = self:Frame()
	f.title:SetText(L["BACKUP_IMPORT_TITLE"])
	f.warning:SetText(L["BACKUP_WARNING"])
	f.hint:SetText(L["BACKUP_IMPORT_HINT"])
	f.pasted, f.result = nil, nil
	step(f, "paste")
	f:Open()
	fill(f, "", false)
	f.edit:SetFocus()
	local blocked = B():ImportBlocked()
	if blocked then
		say(f.status, B().Message(blocked), "err")
		f.right:SetEnabled(false)
	else
		say(f.status, "")
		f.right:SetEnabled(true)
	end
	return f
end

-- Check: validates what was pasted; a valid text shows the preview, a refused one says why.
function Box:Check(text)
	local f = self:Frame()
	text = text or f.edit:GetText() or ""
	local result = B():Check(text)
	if not result.ok then
		say(f.status, B().Message(result), "err")
		return result
	end
	f.pasted, f.result = text, result
	f.hint:SetText(L["BACKUP_PREVIEW_HINT"])
	fill(f, table.concat(B().PreviewLines(result.preview), "\n"), true)
	f.edit:ClearFocus()
	say(f.status, "")
	step(f, "preview")
	return result
end

-- Import after the preview: applies and says the result in one line.
function Box:Apply()
	local f = self:Frame()
	if not f.result then return nil, "check" end
	local summary, why = B():Apply(f.result.content)
	f.pasted, f.result = nil, nil
	if not summary then
		say(f.status, B().Message(why), "err")
		step(f, "done")
		return nil, why
	end
	fill(f, "", true)
	say(f.status, L["BACKUP_DONE"]:format(summary.chars, summary.settings, summary.records), "ok")
	step(f, "done")
	return summary
end

-- Cancel in the preview goes back to the paste step, with the text pasted before.
function Box:Back()
	local f = self:Frame()
	local text = f.pasted or ""
	f.pasted, f.result = nil, nil
	f.hint:SetText(L["BACKUP_IMPORT_HINT"])
	fill(f, text, false)
	say(f.status, "")
	step(f, "paste")
end

function Box:Left()
	local f = self:Frame()
	if f.step == "paste" then return self:Hide() end
	if f.step == "preview" then return self:Back() end
	f.edit:SetFocus()
	f.edit:HighlightText()
end

function Box:Right()
	local f = self:Frame()
	if f.step == "paste" then return self:Check() end
	if f.step == "preview" then return self:Apply() end
	return self:Hide()
end

-- Nothing of the text stays in the frame after it closes.
function Box:Forget()
	local f = self.frame
	if not f then return end
	f.pasted, f.result, f.text = nil, nil, ""
	f.edit:SetText("")
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end
function Box:Step() return self.frame and self.frame.step or nil end

if ns.addon then ns.addon.BackupBox = Box end

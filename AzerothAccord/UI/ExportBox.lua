-- ExportBox: the box of the officers' exports (SPEC-12 §6, M8.6). Lua 5.1.
-- The same field as the personal backup (CopyBox.Area): the text, read-only and already selected (Ctrl+C), under the
-- warning that it leaves the game, with a "CSV · Discord" selector. Data/Export.lua writes the text; this file only shows
-- it. The text is never printed, logged or saved: it lives in the edit box until the box closes. It closes by itself
-- when the character stops being an officer or changes guild.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.ExportBox, ns.modules = Box, ns.modules or {}
ns.modules.ExportBox = Box

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
Box.NAME = "AzerothAccordExportBox"
Box.WIDTH, Box.HEIGHT = 640, 480
Box.format = "csv"    -- the last choice, kept for the session

local function build()
	local f = Widgets.Dialog(UIParent, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT })
	local card = f.card
	f.title = Widgets.Text(card, "H2", "text-1", "LEFT")
	f.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -22)
	f.formats = Widgets.Segmented(card, {
		{ id = "csv", text = L["EXPORT_CSV"] }, { id = "discord", text = L["EXPORT_DISCORD"] },
	}, function(id) if id ~= Box.format then Box:SetFormat(id) end end)
	f.formats:SetPoint("TOPRIGHT", card, "TOPRIGHT", -24, -18)
	f.warning = Widgets.Text(card, "Small", "warn", "LEFT")
	f.warning:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -58)
	f.warning:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.warning:SetText(L["EXPORT_WARNING"])
	f.hint = Widgets.Text(card, "Small", "text-3", "LEFT")
	f.hint:SetPoint("TOPLEFT", f.warning, "BOTTOMLEFT", 0, -4)
	f.hint:SetPoint("RIGHT", card, "RIGHT", -24, 0)

	local scroll, edit
	f.field, scroll, edit = ns.CopyBox.Area(card, Box.WIDTH - 68)
	f.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -96)
	f.field:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 88)
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

	f.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	f.status:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 68)
	f.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.select = Widgets.Button(card, { text = L["BACKUP_SELECT"], style = "secondary", width = 140, onClick = function() Box:SelectAll() end })
	f.select:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 20)
	f.close = Widgets.Button(card, { text = L["BACKUP_CLOSE"], style = "primary", width = 140, onClick = function() Box:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
	f:HookScript("OnHide", function() Box:Forget() end)
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

function Box:SelectAll()
	local f = self:Frame()
	f.edit:SetFocus()
	f.edit:HighlightText()
end

-- Writes the text of the current kind and format into the field, selected.
local function draw(self)
	local f = self.frame
	local text, info = ns.Export.Build(self.kind, self.format, self.items)
	if not text then self:Hide() return nil, info end
	self.text, self.info = text, info
	f.text = ns.Export.Display(text)
	f.hint:SetText(self.format == "discord" and L["EXPORT_HINT_DISCORD"] or L["EXPORT_HINT_CSV"])
	f.edit:SetText(f.text)
	f.edit:SetCursorPosition(0)
	f.scroll:SetVerticalScroll(0)
	-- the rows left out are said here, never inside the exported text
	if info.left > 0 then
		f.status:SetText(L["EXPORT_LEFT_OUT"]:format(info.left))
		Theme.Text(f.status, "warn")
	else
		f.status:SetText(L["EXPORT_ROWS"]:format(info.rows))
		Theme.Text(f.status, "text-3")
	end
	self:SelectAll()
	return text
end

-- Opens the box on `items` (what the page shows now): kind "roster" | "inactive" | "timeline" | "season". Officers only.
-- Returns the text of the export, or nil and the reason.
function Box:Open(kind, items)
	if not ns.Export.Allowed() then return nil, "officer" end
	local f = self:Frame()
	f:Open()
	self.kind, self.items = kind, items or {}
	f.title:SetText(L["EXPORT_TITLE"]:format(L["EXPORT_" .. tostring(kind):upper()]))
	f.formats:Select(self.format)
	return draw(self)
end

-- "csv" | "discord": the same rows, written again.
function Box:SetFormat(format)
	if format ~= "csv" and format ~= "discord" then return false end
	self.format = format
	if not (self.frame and self.items) then return true end
	self.frame.formats:Select(format)
	return draw(self)
end

-- The text of the export that is open (before the doubling of "|"), or nil.
function Box:GetText() return self.text end

-- Nothing of the text stays after the box closes.
function Box:Forget()
	self.items, self.text, self.info, self.kind = nil, nil, nil, nil
	local f = self.frame
	if not f then return end
	f.text = ""
	f.edit:SetText("")
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end

if ns.addon then
	ns.addon.ExportBox = Box
	if ns.Bus then
		ns.Bus:On("ROLE_CHANGED", function() if not ns.Export.Allowed() then Box:Hide() end end)
		for _, event in ipairs({ "GUILD_CHANGED", "OFFICER_PURGED", "DEMO_CHANGED" }) do
			ns.Bus:On(event, function() Box:Hide() end)
		end
	end
end

-- RecruitView: the window of the recruitment text (M12.2; SPEC-16 §3.4, §3.5; REC-01). Lua 5.1.
-- The format ("Chat line" / "Discord"), the officer's contact and extra line, the text (read-only, selected by a click,
-- CopyBox.Area) with its length and the parts it misses. Data/Recruit.lua builds the text; this file only shows it.
-- Nothing here sends it: the officer copies it with Ctrl+C. The open window writes it again REBUILD_DELAY after the
-- season, the source, FDCP or the handbook changed, and at once after a change of format or of a line; the count then
-- pulses. It closes when the character may no longer see it or changes guild.
-- Opened by the button of the Season view and by `/accord recruit`. Switch: Core/Features.lua "recruit".
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.RecruitView, ns.modules = View, ns.modules or {}
ns.modules.RecruitView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, concat = ipairs, table.concat

View.NAME = "AzerothAccordRecruitBox"
View.WIDTH, View.HEIGHT = 640, 500
View.REBUILD_DELAY = 0.5
View.FLASH = 1.2             -- seconds the count pulses after the text changed under the officer

local function book() return ns.Recruit end

local MISSING = {
	description = { raid = "RECRUIT_NO_HANDBOOK", page = "RECRUIT_NO_PAGE" },
	gaps = { season = "RECRUIT_NO_SEASON_VIEW", closed = "RECRUIT_NO_SEASON", fdcp = "RECRUIT_NO_FDCP",
		target = "RECRUIT_NO_TARGET", full = "RECRUIT_NO_GAPS" },
}

-- The sentence of a missing part ({ part, why } of Recruit:Build).
function View.MissingText(m)
	local key = MISSING[m.part] and MISSING[m.part][m.why]
	return key and L[key] or nil
end

local function select_(edit)
	edit:SetFocus()
	edit:HighlightText()
end

local function lineBox(card, y, labelKey, key, limit, placeholder)
	local label = Widgets.Text(card, "BodyMedium", "text-2", "LEFT")
	label:SetPoint("TOPLEFT", card, "TOPLEFT", 24, y - 13)
	label:SetText(L[labelKey])
	local box
	box = Widgets.EditBox(card, { width = View.WIDTH - 188, maxLetters = limit, placeholder = placeholder,
		onChange = function(text, user)
			if not user then return end
			book():Set(key, text)
			-- over the limit in bytes (accented letters count more than one): the box shows what is kept
			if #text > limit then box:SetText(book():Settings()[key] or "") end
			View:Draw()
		end })
	box:SetPoint("TOPLEFT", card, "TOPLEFT", 164, y)
	return box
end

local function build()
	local f = Widgets.Dialog(UIParent, View.NAME, { width = View.WIDTH, height = View.HEIGHT })
	local card = f.card
	f:SetTitle("")
	f.title:SetText(L["RECRUIT_TITLE"])
	f.formats = Widgets.Segmented(card, {
		{ id = "chat", text = L["RECRUIT_CHAT"] }, { id = "discord", text = L["RECRUIT_DISCORD"] },
	}, function(id) if not View.painting then View:SetFormat(id) end end)
	f.formats:SetPoint("TOPRIGHT", card, "TOPRIGHT", -24, -18)
	f.warning = Widgets.Text(card, "Small", "warn", "LEFT")
	f.warning:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -58)
	f.warning:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.warning:SetText(L["RECRUIT_WARNING"])

	f.contact = lineBox(card, -76, "RECRUIT_CONTACT", "contact", book().CONTACT_MAX,
		L["RECRUIT_WHISPER"]:format(ns.Compat.Player.Name() or "?"))
	f.extra = lineBox(card, -124, "RECRUIT_EXTRA", "extra", book().EXTRA_MAX, L["RECRUIT_EXTRA_HINT"])

	local scroll, edit
	f.field, scroll, edit = ns.CopyBox.Area(card, View.WIDTH - 68)
	f.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -174)
	f.field:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 116)
	f.scroll, f.edit = scroll, edit
	-- read-only: typing is undone at once and the text stays selected
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= f.text then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnMouseUp", function(self) select_(self) end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() View:Hide() end)

	f.count = Widgets.Text(card, "Small", "text-2", "LEFT")
	f.count:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 96)
	f.count:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.missing = Widgets.Text(card, "Small", "text-3", "LEFT")
	f.missing:SetPoint("TOPLEFT", f.count, "BOTTOMLEFT", 0, -4)
	f.missing:SetPoint("RIGHT", card, "RIGHT", -24, 0)

	f.select = Widgets.Button(card, { text = L["BACKUP_SELECT"], style = "outlined", width = 140,
		onClick = function() View:SelectAll() end })
	f.select:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 24)
	f.close = Widgets.Button(card, { text = L["BACKUP_CLOSE"], style = "filled", width = 140,
		onClick = function() View:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 24)
	f:HookScript("OnHide", function() View:Forget() end)
	return f
end

function View:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

function View:SelectAll()
	if self.frame then select_(self.frame.edit) end
end

local function flash(self)
	local count = self.frame.count
	if not ns.Motion then return end
	local pulse = ns.Motion.Pulse(count)
	pulse.Start()
	self.flashes = (self.flashes or 0) + 1
	local mine = self.flashes
	ns.Compat.After(View.FLASH, function()
		if mine == self.flashes then pulse.Stop() end
	end)
end

-- Writes the text of now into the box. Returns it, or nil and the reason (the window then closes).
function View:Draw()
	local f = self.frame
	if not (f and f:IsShown()) then return nil end
	local text, info = book():Build()
	if not text then self:Hide() return nil, info end
	local changed = self.text ~= nil and self.text ~= text
	self.text, self.info = text, info
	f.text = text
	if f.edit:GetText() ~= text then
		f.edit:SetText(text)
		f.edit:SetCursorPosition(0)
		f.edit:HighlightText(0, 0)
		f.scroll:SetVerticalScroll(0)
	end
	local key = info.format == "chat" and "RECRUIT_COUNT_BYTES" or "RECRUIT_COUNT_CHARS"
	f.count:SetText(L[key]:format(info.length, info.max))
	local lines = {}
	for _, m in ipairs(info.missing) do lines[#lines + 1] = View.MissingText(m) end
	f.missing:SetText(concat(lines, "\n"))
	if changed then flash(self) end
	return text
end

-- "chat" | "discord": remembered on this computer.
function View:SetFormat(format)
	if not book():Set("format", format) then return false end
	local f = self.frame
	if f then
		self.painting = true
		f.formats:Select(format)
		self.painting = false
		self:Draw()
		self:SelectAll()
	end
	return true
end

-- Opens the window with the text selected. Officers only (Recruit.VISIBLE_TO). Returns the text, or nil and the reason.
function View:Open()
	local text, why = book():Build()
	if not text then return nil, why end
	local f = self:Frame()
	local settings = book():Settings()
	self.painting = true
	f.formats:Select(settings.format)
	f.contact:SetText(settings.contact or "")
	f.extra:SetText(settings.extra or "")
	self.painting = false
	self.text = nil
	f:Open()
	text = self:Draw()
	self:SelectAll()
	return text
end

-- /accord recruit
function View.Command()
	local text, why = View:Open()
	if not text and ns.addon then
		ns.addon:Print(L[why == "guild" and "RECRUIT_ERR_GUILD" or "RECRUIT_ERR_OFFICER"])
	end
	return text
end

-- The data changed: one redraw REBUILD_DELAY later for everything that came meanwhile.
function View:Changed()
	if self.waiting or not self:IsShown() then return end
	self.waiting = true
	local scheduled = ns.Compat and ns.Compat.After(View.REBUILD_DELAY, function()
		View.waiting = nil
		View:Draw()
	end)
	if not scheduled then self.waiting = nil self:Draw() end
end

function View:GetText() return self.text end

-- Nothing of the text stays after the window closes.
function View:Forget()
	self.text, self.info = nil, nil
	local f = self.frame
	if not f then return end
	f.text = ""
	f.edit:SetText("")
end

function View:Hide() if self.frame then self.frame:Hide() end end
function View:IsShown() return self.frame ~= nil and self.frame:IsShown() end

if ns.addon then
	ns.addon.RecruitView = View
	if ns.Bus then
		for _, event in ipairs({ "SEASON_CHANGED", "SOURCES_CHANGED", "FDCP_CHANGED", "HANDBOOK_CHANGED" }) do
			ns.Bus:On(event, function() View:Changed() end)
		end
		ns.Bus:On("ROLE_CHANGED", function() if View:IsShown() and not ns.Recruit:CanSee() then View:Hide() end end)
		for _, event in ipairs({ "GUILD_CHANGED", "DEMO_CHANGED" }) do
			ns.Bus:On(event, function() View:Hide() end)
		end
	end
end

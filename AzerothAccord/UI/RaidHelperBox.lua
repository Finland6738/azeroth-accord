-- RaidHelperBox: the box an officer pastes a Raid-Helper export into (M10.6; SPEC-14 §6). Lua 5.1.
-- Paste the export (Ctrl+V) and press Check: the box says what it read and who matched; Import brings it into Accord.
-- A text Accord does not understand is refused with the reason and nothing changes. The title and the date and time are
-- optional: they replace the export's (a CSV export has none). Esc closes. Data/RaidHelper.lua does the work; this file
-- only draws. The text is never printed, logged or saved: it lives in the edit box until the box closes.
local ADDON_NAME, ns = ...
ns = ns or {}
local Box = {}
ns.RaidHelperBox, ns.modules = Box, ns.modules or {}
ns.modules.RaidHelperBox = Box

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, concat = ipairs, table.concat

Box.NAME = "AzerothAccordRaidHelperBox"
Box.WIDTH, Box.HEIGHT = 640, 520
Box.NAMES_SHOWN = 6       -- unmatched names written in the preview; the rest are counted

local function say(f, text, token)
	f.status:SetText(text or "")
	Theme.Text(f.status, token or "text-2")
end

-- Why a text or an import was refused, in the language of the interface.
function Box.Reason(why)
	-- rawget: a reason without a text of its own is no missing string
	return rawget(L, "RH_ERR_" .. tostring(why):upper()) or L["RH_ERR_OTHER"]
end

-- The lines of a preview of RaidHelper:Check.
function Box.PreviewLines(p)
	local out = {}
	out[#out + 1] = L["RH_PREVIEW_EVENT"]:format(p.title, ns.EventsView.WhenText(p.start))
	local counts = {}
	for _, s in ipairs(p.signups) do counts[s.state] = (counts[s.state] or 0) + 1 end
	local states = {}
	for _, state in ipairs(ns.RaidHelper.STATE_ORDER) do
		if counts[state] then states[#states + 1] = L["SEASON_COUNT"]:format(L["RH_STATE_" .. state:upper()], counts[state]) end
	end
	out[#out + 1] = L["RH_PREVIEW_MATCHED"]:format(#p.signups) .. (#states > 0 and (" (" .. concat(states, ", ") .. ")") or "")
	if #p.unmatched > 0 then
		local names = {}
		for i = 1, math.min(#p.unmatched, Box.NAMES_SHOWN) do names[i] = p.unmatched[i] end
		local text = concat(names, ", ")
		if #p.unmatched > #names then text = text .. ", ..." end
		out[#out + 1] = L["RH_PREVIEW_UNMATCHED"]:format(#p.unmatched, text)
	end
	if p.ambiguous > 0 then out[#out + 1] = L["RH_PREVIEW_AMBIGUOUS"]:format(p.ambiguous) end
	if p.twice > 0 then out[#out + 1] = L["RH_PREVIEW_TWICE"]:format(p.twice) end
	if p.over > 0 then out[#out + 1] = L["RH_PREVIEW_OVER"]:format(p.over, ns.RaidHelper.RECORD_MAX) end
	if p.ignored > 0 then out[#out + 1] = L["RH_PREVIEW_IGNORED"]:format(p.ignored) end
	return out
end

local function build()
	local f = Widgets.Dialog(UIParent, Box.NAME, { width = Box.WIDTH, height = Box.HEIGHT })
	local card = f.card
	f:SetTitle("")
	f.title:SetText(L["RH_BOX_TITLE"])
	f.hint = Widgets.Text(card, "Small", "text-3", "LEFT")
	f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.hint:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	f.hint:SetText(L["RH_BOX_HINT"])

	local function edited() if not f.filling then Box:Stale() end end
	f.eventTitle = Widgets.EditBox(card, { width = 400, maxLetters = 64, placeholder = L["RH_BOX_NAME_HINT"], onChange = edited })
	f.eventTitle:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -92)
	f.when = Widgets.EditBox(card, { width = 184, maxLetters = 16, placeholder = L["EVENTS_WHEN_HINT"], onChange = edited })
	f.when:SetPoint("LEFT", f.eventTitle, "RIGHT", 8, 0)

	local scroll, edit
	f.field, scroll, edit = ns.CopyBox.Area(card, Box.WIDTH - 68)
	f.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -140)
	f.field:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 176)
	f.scroll, f.edit = scroll, edit
	edit:SetScript("OnTextChanged", edited)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() Box:Hide() end)

	f.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	f.status:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 24, 168)
	f.status:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 72)
	f.status:SetJustifyV("TOP")
	f.status:SetWordWrap(true)

	f.cancel = Widgets.Button(card, { text = L["BACKUP_CANCEL"], style = "outlined", width = 140, onClick = function() Box:Hide() end })
	f.cancel:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 24)
	f.import = Widgets.Button(card, { text = L["RH_BOX_IMPORT"], style = "filled", width = 140, onClick = function() Box:Import() end })
	f.import:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 24)
	f.check = Widgets.Button(card, { text = L["RH_BOX_CHECK"], style = "tonal", width = 140, onClick = function() Box:Check() end })
	f.check:SetPoint("RIGHT", f.import, "LEFT", -8, 0)
	f:HookScript("OnHide", function() Box:Forget() end)
	return f
end

function Box:Frame()
	if not self.frame then self.frame = build() end
	return self.frame
end

-- Officers only. Returns true, or false and the reason.
function Box:Open()
	if not ns.RaidHelper.CanImport() then return false, "officer" end
	local f = self:Frame()
	f.filling = true
	f.eventTitle:Clear()
	f.when:Clear()
	f.edit:SetText("")
	f.filling = false
	self.event, self.opts, self.preview = nil, nil, nil
	f.import:SetEnabled(false)
	say(f, "")
	f:Open()
	f.edit:SetFocus()
	return true
end

-- The text or a field changed: what was checked no longer holds.
function Box:Stale()
	if not self.event then return end
	self.event, self.opts, self.preview = nil, nil, nil
	local f = self.frame
	f.import:SetEnabled(false)
	say(f, L["RH_BOX_AGAIN"], "text-3")
end

local function options(f)
	local opts = { title = f.eventTitle:GetText() }
	local when = f.when:GetText() or ""
	if when:find("%S") then
		opts.start = ns.EventsView.ParseWhen(when)
		if not opts.start then return nil, "when" end
	end
	return opts
end

-- Reads the pasted text. Returns the preview, or nil and the reason.
function Box:Check()
	local f = self:Frame()
	self.event, self.opts, self.preview = nil, nil, nil
	f.import:SetEnabled(false)
	local opts, why = options(f)
	local preview, event
	if opts then
		preview, event = ns.RaidHelper:Check(f.edit:GetText() or "", opts)
		if not preview then why = event end
	end
	if not preview then
		say(f, Box.Reason(why), "err")
		return nil, why
	end
	self.event, self.opts, self.preview = event, opts, preview
	say(f, concat(Box.PreviewLines(preview), "\n"))
	f.import:SetEnabled(true)
	return preview
end

-- Imports what was checked and shows it in the Events view. Returns the id, or nil and the reason.
function Box:Import()
	if not self.event then return nil, "check" end
	local id, why = ns.RaidHelper:Import(self.event, self.opts)
	if not id then
		say(self.frame, Box.Reason(why), "err")
		return nil, why
	end
	local title = why.title
	self:Hide()
	if ns.EventsView then ns.EventsView:Imported(id, title) end
	return id
end

-- Nothing of the pasted text stays after the box closes (the parsed event is in RaidHelper's memory only after Import).
function Box:Forget()
	self.event, self.opts, self.preview = nil, nil, nil
	local f = self.frame
	if not f then return end
	f.filling = true
	f.edit:SetText("")
	f.eventTitle:Clear()
	f.when:Clear()
	f.filling = false
end

function Box:Hide() if self.frame then self.frame:Hide() end end
function Box:IsShown() return self.frame ~= nil and self.frame:IsShown() end

if ns.addon then
	ns.addon.RaidHelperBox = Box
	if ns.Bus then
		-- closes by itself when the character stops being an officer or changes guild
		local function check() if Box:IsShown() and not ns.RaidHelper.CanImport() then Box:Hide() end end
		ns.Bus:On("ROLE_CHANGED", check)
		ns.Bus:On("GUILD_CHANGED", function() Box:Hide() end)
		ns.Bus:On("FEATURE_CHANGED", check)
	end
end

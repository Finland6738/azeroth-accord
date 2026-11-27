-- OfficerNotesView: the "Officer notes" section of the member card and the dialog an officer writes an extended note in
-- (SPEC-12 §5.2, M8.5). Lua 5.1.
-- The section shows the note of the character (with its author and age, M7.2), "Left the guild on <date>" for a character
-- who left, and, read-only, the notes of the other proved characters of the account. A member never gets the section:
-- Officer.CanSee("notes") is false and the function returns nothing.
--   View.CardSection(entry)    the section, a plain description (tested offline)
--   View:Open(guid, name, backend)  the dialog: a multi-line field (500 characters, 20 lines), the count, Save, Delete,
--                              Close; `backend` (optional) = { title, get(), set(text), delete() } writes another note with
--                              the same limits (a trial note, M12.3, UI/Trials.lua); without it, the extended note of `guid`
--   View:Save(text)            saves what the field holds (or `text`); the dialog closes when it was saved
--   View:DeleteNote()          writes the empty text (a deletion that reaches every officer)
--   View.CountText(text)       "123 / 500 characters · 130 / 1000 bytes"
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.OfficerNotesView, ns.modules = View, ns.modules or {}
ns.modules.OfficerNotesView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring = type, ipairs, tostring

View.WIDTH, View.HEIGHT = 480, 420
View.WHEEL_STEP = 28

local function N() return ns.OfficerNotes end
local function me() return ns.Compat.Player.GUID() end
local function escape(text) return (tostring(text or ""):gsub("|", "||")) end   -- ONT-02: the | is doubled when shown

-- The provenance of a note (M7.2): who wrote the latest version and when.
function View.ProvOf(rec)
	return { source = rec.author == me() and "own" or "shared", observedAt = rec.time, author = rec.author }
end

-- "By Name, 3 d ago" (never a GUID).
function View.ByText(rec)
	local who = rec.author == me() and L["ONT_BY_YOU"] or ns.Provenance.AuthorName(rec.author)
	return L["ONT_BY"]:format(escape(who), ns.Provenance.AgeText(ns.Compat.ServerTime() - (rec.time or 0)))
end

-- The day a character was seen leaving (the roster snapshot of the timeline, SPEC-12 §2.1), or nil.
local function goneAt(guid)
	local O = ns.Officer and ns.Officer:Peek()
	local t = O and type(O.gone) == "table" and O.gone[guid]
	return type(t) == "number" and t or nil
end

function View.CardSection(e)
	local Notes = N()
	if not (Notes and ns.Officer and ns.Officer.CanSee("notes")) then return nil end
	if type(e) ~= "table" or type(e.guid) ~= "string" then return nil end
	local lines = {}
	local rec = Notes:Get(e.guid)
	if rec then
		lines[#lines + 1] = { text = escape(rec.text), prov = View.ProvOf(rec), tip = { L["ONT_TITLE"], View.ByText(rec) } }
		lines[#lines + 1] = { text = View.ByText(rec), muted = true }
		if rec.author == me() and not ns.Officer.ChannelProven() then
			lines[#lines + 1] = { text = L["TL_LOCAL_ONLY"], muted = true }
		end
	else
		lines[#lines + 1] = { text = L["ONT_NONE"], muted = true }
	end
	local gone = goneAt(e.guid)
	if gone then
		lines[#lines + 1] = { text = L["ONT_LEFT_ON"]:format(date("!%Y-%m-%d", gone)), muted = true }
	elseif e.notInGuild then
		lines[#lines + 1] = { text = L["ONT_NOT_IN_GUILD"], muted = true }
	end
	local name = e.short or e.name or "?"
	if ns.Role and ns.Role:IsOfficer() then
		lines[#lines + 1] = { text = rec and L["ONT_EDIT"] or L["ONT_WRITE"], action = true, onClick = function() View:Open(e.guid, name) end }
		if rec then
			lines[#lines + 1] = { text = L["ONT_DELETE"], action = true, onClick = function() Notes:Delete(e.guid) end }
		end
	end
	for _, other in ipairs(Notes:OfAccount(e.guid)) do
		lines[#lines + 1] = { text = L["ONT_OTHER"]:format(escape(other.name), escape(other.rec.text)), prov = View.ProvOf(other.rec),
			tip = { escape(other.name), View.ByText(other.rec) } }
	end
	return { id = "onotes", title = L["ONT_TITLE"], lines = lines }
end

function View.CountText(text)
	text = tostring(text or "")
	return L["ONT_COUNT"]:format(N().Length(text), N().MAX_CHARS, #text, N().MAX_BYTES)
end

---------------------------------------------------------------------------------------------------------------------
-- The dialog
---------------------------------------------------------------------------------------------------------------------
local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-3")
end

local function build()
	local w, h = View.WIDTH, View.HEIGHT
	local d = Widgets.Dialog(UIParent, "AzerothAccordOfficerNoteDialog", { width = w, height = h })
	local card = d.card
	d:SetTitle("")
	d.hint = Widgets.Text(card, "Small", "text-3", "LEFT")
	d.hint:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -6)
	d.hint:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.hint:SetText(L["ONT_HINT"])
	-- a multi-line field in a surface-2 frame that scrolls with the wheel (as the backup box)
	d.field = Widgets.TextArea(card)
	d.field:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -84)
	d.field:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 112)
	local scroll = CreateFrame("ScrollFrame", nil, d.field)
	scroll:SetPoint("TOPLEFT", d.field, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", d.field, "BOTTOMRIGHT", -10, 8)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local v = (self:GetVerticalScroll() or 0) - delta * View.WHEEL_STEP
		self:SetVerticalScroll(math.min(range, math.max(0, v)))
	end)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(N().MAX_CHARS)   -- ONT-02: the box stops at 500 characters; the bytes are checked when saving
	if Theme.fontObjects and Theme.fontObjects.Body then edit:SetFontObject(Theme.fontObjects.Body) end
	Theme.Text(edit, "text-1")
	edit:SetWidth(w - 68)
	scroll:SetScrollChild(edit)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() d:Close() end)
	edit:SetScript("OnTextChanged", function(self) say(d.count, View.CountText(self:GetText())) end)
	d.scroll, d.edit = scroll, edit
	d.field:Track(edit)
	d.count = Widgets.Text(card, "Small", "text-3", "LEFT")
	d.count:SetPoint("TOPLEFT", d.field, "BOTTOMLEFT", 0, -8)
	d.status = Widgets.Text(card, "Small", "text-2", "LEFT")
	d.status:SetPoint("TOPLEFT", d.count, "BOTTOMLEFT", 0, -4)
	d.status:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.save = Widgets.Button(card, { text = L["ABS_SAVE"], style = "filled", onClick = function() View:Save() end })
	d.delete = Widgets.Button(card, { text = L["ONT_DELETE"], style = "outlined", onClick = function() View:DeleteNote() end })
	d.close = Widgets.Button(card, { text = L["COPY_CLOSE"], style = "text", onClick = function() d:Close() end })
	d:SetActions({ d.close, d.delete, d.save })
	return d
end

-- The extended note of a character, as a backend of the dialog.
local function noteBackend(guid)
	return { get = function() return N():Get(guid) end, set = function(text) return N():Set(guid, text) end,
		delete = function() return N():Delete(guid) end }
end

function View:Open(guid, name, backend)
	if not (ns.Role and ns.Role:IsOfficer()) or type(guid) ~= "string" then return nil end
	if not backend and not ns.Officer.CanSee("notes") then return nil end
	if not self.dialog then self.dialog = build() end
	local d = self.dialog
	d.guid, d.backend = guid, backend or noteBackend(guid)
	d.title:SetText(backend and backend.title or L["ONT_DIALOG_TITLE"]:format(escape(name)))
	local rec = d.backend.get()
	d.edit:SetText(rec and rec.text or "")
	d.edit:SetCursorPosition(0)
	d.scroll:SetVerticalScroll(0)
	say(d.count, View.CountText(rec and rec.text or ""))
	say(d.status, ns.Officer.ChannelProven() and (rec and View.ByText(rec) or "") or L["TL_LOCAL_ONLY"])
	d.delete:SetEnabled(rec ~= nil)
	d:Open()
	d.edit:SetFocus()
	return d
end

function View:Save(text)
	local d = self.dialog
	if not d or not d.guid then return false end
	text = text or d.edit:GetText() or ""
	local clean = N().Clean(text)
	if clean == "" then
		if not d.backend.get() then d:Close() return true end
		return self:DeleteNote()
	end
	local rec, why = d.backend.set(clean)
	if not rec then say(d.status, N().ErrorText(why, clean), "err") return false, why end
	d:Close()
	return true
end

function View:DeleteNote()
	local d = self.dialog
	if not d or not d.guid then return false end
	local rec, why = d.backend.delete()
	if not rec and why ~= "empty" then say(d.status, N().ErrorText(why), "err") return false, why end
	d:Close()
	return true
end

if ns.MemberCard then ns.MemberCard.AddSection("onotes", 7.4, View.CardSection) end

if ns.addon then
	ns.addon.OfficerNotesView = View
	if ns.Bus then
		ns.Bus:On("STORE_CHANGED", function(set)
			if set == "onotes" then
				if ns.MemberCard then ns.MemberCard:Refresh() end
				if ns.OfficersView then ns.OfficersView:Changed() end
			end
		end)
		local function close() if View.dialog then View.dialog:Close() end end
		ns.Bus:On("ROLE_CHANGED", function() if not (ns.Officer and ns.Officer.CanSee("notes")) then close() end end)
		ns.Bus:On("GUILD_CHANGED", close)
		ns.Bus:On("OFFICER_PURGED", function() close() if ns.MemberCard then ns.MemberCard:Refresh() end end)
	end
end

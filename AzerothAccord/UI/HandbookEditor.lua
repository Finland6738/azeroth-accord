-- Handbook editor: what a writer gets in the Handbook view (M11.4, SPEC-15 §3.5, §5.2, §6). Lua 5.1.
--
-- List     "Create the default pages" while the guild has never had one (Data/HandbookDefaults.lua), "New page", "Writers" (officers: the ranks that write besides the officers), arrows on the chosen page to move
--          it, and the deleted pages this client can restore.
-- Reader   "Edit", "Revisions" and "Delete" (a second click confirms) under the text.
-- Editor   takes the whole view: the title, a text box of several lines, the length after cleaning against the limits,
--          "Preview", "Save", "Cancel" (a second click when the text changed). A save over the limit is not possible.
--          A page saved by somebody else meanwhile is shown, with "Keep mine" and "Discard mine". One draft per account
--          is kept while typing and offered again. The editor does not open in combat.
-- Revisions the revisions this client saw, a preview, "Restore" (a new revision) and "Dismiss" for a lost one.
-- Only writers (Handbook:CanWrite) see any of it; a writer who stops being one loses it at once. Everything is behind the
-- switch "raid" with the view itself (UI/Handbook.lua).
local ADDON_NAME, ns = ...
ns = ns or {}
local Editor = {}
ns.HandbookEditor, ns.modules = Editor, ns.modules or {}
ns.modules.HandbookEditor = Editor

local View = ns.HandbookView
local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring, max, min = type, ipairs, tostring, math.max, math.min
local date = date

Editor.REVISION_ROW = 32
Editor.REVISION_ROWS = 6       -- the current one and Handbook.KEEP_REVISIONS past ones
Editor.WRITERS_WIDTH = 260

local function book() return ns.Handbook end
local function clean(s, title) return ns.HandbookText.Clean(s, title) end
local function writer() return book() ~= nil and book():CanWrite() end

-- 21400 -> "21 400"
function Editor.Number(n)
	local s = tostring(n)
	while true do
		local out, found = s:gsub("^(%d+)(%d%d%d)", "%1 %2")
		s = out
		if found == 0 then return s end
	end
end
local group = Editor.Number

-- The sentence for a reason that stops a save (Handbook:Check, Handbook:Save).
function Editor.Reason(reason, over)
	if reason == "title_empty" then return L["HANDBOOK_NEED_TITLE"] end
	if reason == "title" and over then return L["HANDBOOK_TITLE_LONG"]:format(group(over)) end
	if reason == "body" and over then return L["HANDBOOK_BODY_LONG"]:format(group(over)) end
	if reason == "total" and over then return L["HANDBOOK_TOTAL_LONG"]:format(group(over)) end
	if reason == "pages" then return L["HANDBOOK_PAGES_FULL"]:format(book().MAX_PAGES) end
	if reason == "rate" then return L["HANDBOOK_ERR_RATE"] end
	if reason == "writer" then return L["HANDBOOK_ERR_WRITER"] end
	if reason == "changed" then return L["HANDBOOK_ERR_CHANGED"] end
	return L["HANDBOOK_ERR"]:format(tostring(reason))
end

local function say(fs, text, token)
	fs:SetText(text or "")
	Theme.Text(fs, token or "text-3")
end

local function button(parent, key, style, onClick, width)
	return Widgets.Button(parent, { text = L[key], style = style or "tonal", dense = true, width = width,
		onClick = onClick })
end

-- A preview with the reader's parts: web addresses open the copy box, links to pages stay where they are.
local function previewPane(parent)
	local pane = { text = View.Scroller(parent), blocks = {} }
	pane.blank = Widgets.Text(pane.text.page, "Body", "text-3", "LEFT")
	pane.blank:SetPoint("TOPLEFT", pane.text.page, "TOPLEFT", 0, 0)
	pane.blank:SetText(L["HANDBOOK_EMPTY_PAGE"])
	pane.follow = function(target) if target.url then View:Follow(target) end end
	return pane
end

local function preview(pane, body)
	if pane.body ~= body then pane.body, pane.textKey, pane.textId = body, nil, nil end
	View.DrawText(pane, { id = "preview", rev = 0, time = 0, body = body })
end

---------------------------------------------------------------------------------------------------------------------
-- The editor
---------------------------------------------------------------------------------------------------------------------
local function buildEditor(f)
	local p = CreateFrame("Frame", nil, f)
	p:SetAllPoints(f)
	p.heading = Widgets.Text(p, "H2", "text-1", "LEFT")
	p.heading:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -4)
	p.heading:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -4)
	p.title = Widgets.EditBox(p, { dense = true, placeholder = L["HANDBOOK_TITLE_HINT"],
		onChange = function() Editor:Typed() end })
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -28)
	p.title:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -28)
	p.hint = Widgets.Text(p, "Small", "text-3", "LEFT")
	p.hint:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -68)
	p.hint:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -68)
	p.hint:SetText((L["HANDBOOK_SYNTAX"]:gsub("|", "||")))
	-- a multi-line box that scrolls with the wheel and follows the cursor
	p.field = Widgets.TextArea(p)
	p.field:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -86)
	p.field:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 80)
	local scroll = CreateFrame("ScrollFrame", nil, p.field)
	scroll:SetPoint("TOPLEFT", p.field, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", p.field, "BOTTOMRIGHT", -10, 8)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local v = (self:GetVerticalScroll() or 0) - delta * View.WHEEL_STEP
		self:SetVerticalScroll(min(range, max(0, v)))
	end)
	-- no SetMaxBytes or SetMaxLetters: a longer pasted text is shown whole and cannot be saved, never cut in silence
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	if Theme.fontObjects and Theme.fontObjects.Body then edit:SetFontObject(Theme.fontObjects.Body) end
	Theme.Text(edit, "text-1")
	edit:SetWidth(View.WIDTH)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnSizeChanged", function(self, width) if width and width > 0 then edit:SetWidth(width) end end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnTextChanged", function() Editor:Typed() end)
	edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
		local top, height = scroll:GetVerticalScroll() or 0, scroll:GetHeight() or 0
		local line = -(y or 0)
		if line < top then scroll:SetVerticalScroll(line)
		elseif height > 0 and line + (h or 0) > top + height then scroll:SetVerticalScroll(line + (h or 0) - height) end
	end)
	p.field:EnableMouse(true)
	p.field:SetScript("OnMouseDown", function() edit:SetFocus() end)
	p.scroll, p.edit = scroll, edit
	p.field:Track(edit)
	p.pane = previewPane(p)
	p.pane.text:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -32)
	p.pane.text:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 80)
	p.status = Widgets.Text(p, "Small", "text-2", "LEFT")
	p.status:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 60)
	p.status:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 60)
	p.count = Widgets.Text(p, "Small", "text-3", "LEFT")
	p.count:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 44)
	p.total = Widgets.Text(p, "Small", "text-3", "RIGHT")
	p.total:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 44)
	p.save = button(p, "HANDBOOK_SAVE", "filled", function() Editor:Save() end)
	p.save:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 4)
	p.cancel = button(p, "HANDBOOK_CANCEL", "outlined", function() Editor:Cancel() end)
	p.cancel:SetPoint("RIGHT", p.save, "LEFT", -8, 0)
	p.toggle = button(p, "HANDBOOK_PREVIEW", "tonal", function() Editor:TogglePreview() end)
	p.toggle:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 4)
	p.draft = button(p, "HANDBOOK_DRAFT", "tonal", function() Editor:RestoreDraft() end)
	p.draft:SetPoint("LEFT", p.toggle, "RIGHT", 8, 0)
	p.keep = button(p, "HANDBOOK_KEEP_MINE", "filled", function() Editor:Save() end)
	p.keep:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 4)
	p.discard = button(p, "HANDBOOK_DISCARD_MINE", "outlined", function() Editor:DiscardMine() end)
	p.discard:SetPoint("RIGHT", p.keep, "LEFT", -8, 0)
	f.editorPanel = p
	return p
end

local function panel() return View.frame and View.frame.editorPanel end

local function typed()
	local p = panel()
	return p.title:GetText() or "", p.edit:GetText() or ""
end

local function setTexts(e, title, body)
	local p = panel()
	e.loading = true
	p.title:SetText(title)
	p.edit:SetText(body)
	p.edit:SetCursorPosition(0)
	p.scroll:SetVerticalScroll(0)
	e.loading = nil
end

local function dirty(e)
	local title, body = typed()
	return clean(title, true) ~= e.title0 or clean(body) ~= e.body0
end

local function draftKey(e) return e.id or book().NEW_DRAFT end

-- Drops the draft this editor wrote; a draft that was offered and never restored takes its place again.
local function release(e)
	if not e.drafted then return end
	local d = e.offer
	if d then book():SaveDraft(d.id, d.base, d.title, d.body) else book():ClearDraft(draftKey(e)) end
	e.drafted = nil
end

function Editor:Paint()
	local e, p = View.editor, panel()
	if not (e and p) then return end
	local rawTitle, rawBody = typed()
	local title, body = clean(rawTitle, true), clean(rawBody)
	local check = book():Check(e.id, title, body)
	local conflict = e.conflict
	local previewing = e.preview or conflict ~= nil
	local shownTitle, shownBody = title, body
	if conflict then shownTitle, shownBody = conflict.title or title, conflict.body or "" end
	p.heading:SetText(previewing and shownTitle or L[e.id and "HANDBOOK_EDIT_PAGE" or "HANDBOOK_EDIT_NEW"])
	p.title:SetShown(not previewing)
	p.hint:SetShown(not previewing)
	p.field:SetShown(not previewing)
	p.pane.text:SetShown(previewing)
	if previewing then preview(p.pane, shownBody) end

	local B = book()
	local over = check.reason == "body" or check.reason == "total"
	say(p.count, L["HANDBOOK_COUNT"]:format(group(check.body), group(B.BODY_MAX)),
		check.body > B.BODY_MAX and "err" or "text-3")
	say(p.total, L["HANDBOOK_COUNT_ALL"]:format(group(check.total), group(B.TOTAL_MAX)),
		check.total > B.TOTAL_MAX and "err" or "text-3")
	local why = check.reason and Editor.Reason(check.reason, check.over)
	if conflict then
		local who, when = B.NameOf(conflict.author), date("%Y-%m-%d %H:%M", conflict.time or 0)
		local text = L[conflict.del and "HANDBOOK_DELETED_BY" or "HANDBOOK_CHANGED_BY"]:format(who, when)
		say(p.status, why and (text .. " " .. why) or text, "warn")
	elseif e.armed then say(p.status, L["HANDBOOK_CANCEL_ASK"], "warn")
	elseif e.error then say(p.status, e.error, "err")
	elseif why then say(p.status, why, (over or check.reason ~= "title_empty") and "err" or "text-2")
	elseif e.offer then say(p.status, L["HANDBOOK_DRAFT_NOTE"], "text-2")
	else say(p.status, "") end

	p.save:SetShown(not conflict)
	p.cancel:SetShown(not conflict)
	p.toggle:SetShown(not conflict)
	p.draft:SetShown(not conflict and e.offer ~= nil)
	p.keep:SetShown(conflict ~= nil)
	p.discard:SetShown(conflict ~= nil)
	p.save:SetEnabled(check.reason == nil)
	p.keep:SetEnabled(check.reason == nil)
	p.cancel:SetLabel(L[e.armed and "HANDBOOK_CONFIRM" or "HANDBOOK_CANCEL"])
	p.toggle:SetLabel(L[e.preview and "HANDBOOK_WRITE" or "HANDBOOK_PREVIEW"])
end

-- Every change of the title or the text: the draft is kept, and the counts follow.
function Editor:Typed()
	local e = View.editor
	if not e or e.loading or e.conflict then return end
	e.armed, e.error = nil, nil
	if dirty(e) then
		local title, body = typed()
		book():SaveDraft(draftKey(e), e.base, title, body)
		e.drafted = true
	else
		release(e)
	end
	self:Paint()
end

function Editor:TogglePreview()
	local e = View.editor
	if not e then return end
	e.preview = not e.preview
	if e.preview then panel().edit:ClearFocus() panel().title:ClearFocus() end
	self:Paint()
end

function Editor:RestoreDraft()
	local e = View.editor
	local d = e and e.offer
	if not d then return end
	e.offer, e.armed, e.error = nil, nil, nil
	-- the revision the draft started from: a page saved since then is shown before anything is written
	if e.id then e.base = d.base end
	setTexts(e, d.title, d.body)
	book():SaveDraft(d.id, d.base, d.title, d.body)
	e.drafted = true
	self:Paint()
end

local function close(id)
	View.editor = nil
	if not (id and View:Show(id)) then View:Redraw() end
end

-- "Save", and "Keep mine" over a page that changed meanwhile. Returns the record written, true when there was nothing
-- to write, or false and the reason.
function Editor:Save()
	local e = View.editor
	if not e then return false end
	local rawTitle, rawBody = typed()
	local title, body = clean(rawTitle, true), clean(rawBody)
	local B = book()
	local check = B:Check(e.id, title, body)
	if check.reason then
		self:Paint()
		return false, check.reason
	end
	local held = e.id and B:Get(e.id)
	local conflict = e.conflict
	-- nothing changed: no new revision, unless it publishes a template
	if not conflict and held and not e.tpl and held.rev == e.base and not dirty(e) then
		release(e)
		close(e.id)
		return true
	end
	local id = e.id or B:NewId(title)
	local opts = { base = e.base }
	if conflict then opts = { base = conflict.rev, force = conflict.rev == nil } end
	local order = (held and held.order) or e.order
	local rec, why, now = B:Save(id, { title = title, body = body, order = order }, opts)
	if rec then
		if e.drafted then B:ClearDraft(draftKey(e)) end
		close(id)
		return rec
	end
	if why == "changed" then
		e.conflict, e.error, e.armed = now or {}, nil, nil
		panel().edit:ClearFocus()
		panel().title:ClearFocus()
	else
		e.error = Editor.Reason(why)
	end
	self:Paint()
	return false, why
end

-- The writer's text stays among the page's revisions, marked lost; the page keeps what the other writer saved.
function Editor:DiscardMine()
	local e = View.editor
	if not (e and e.conflict) then return end
	local title, body = typed()
	book():Discard(e.id, clean(title, true), clean(body), e.base)
	if e.drafted then book():ClearDraft(draftKey(e)) end
	close(e.id)
end

function Editor:Cancel()
	local e = View.editor
	if not e then return end
	if dirty(e) and not e.armed then
		e.armed = true
		return self:Paint()
	end
	release(e)
	close()
end

-- Opens the editor on the page `id`, or on a new page without one. Returns true when it opened.
function View:Edit(id)
	local f = self.frame
	if not (f and writer()) or self.editor then return false end
	if ns.Compat.InCombat() then
		if ns.addon then ns.addon:Print(L["HANDBOOK_COMBAT"]) end
		return false
	end
	local held = id and book():Get(id)
	if id and not (held and not held.del) then return false end
	local title, body = held and held.title or "", held and held.body or ""
	local e = { id = id, base = held and held.rev, tpl = held and held.tpl, order = held and held.order or book():NextOrder(),
		title0 = clean(title, true), body0 = clean(body) }
	local d = book():Draft(id or book().NEW_DRAFT)
	if d and (clean(d.title, true) ~= e.title0 or clean(d.body) ~= e.body0) then e.offer = d end
	if not f.editorPanel then buildEditor(f) end
	self.editor, self.revisions, self.deleting = e, nil, nil
	setTexts(e, title, body)
	self:Redraw()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Revisions
---------------------------------------------------------------------------------------------------------------------
local REVISION_TABLE = 35 + Editor.REVISION_ROWS * Editor.REVISION_ROW   -- the header and the rows

local function revisionColumns()
	local function token(r) return r.lost and "warn" or "text-1" end
	return {
		{ id = "rev", title = L["HANDBOOK_COL_REV"], width = 90, mono = true, value = function(r) return r.rev end,
			text = function(r) return tostring(r.rev) end, token = token },
		{ id = "author", title = L["HANDBOOK_COL_AUTHOR"], flex = 1, text = function(r) return book().NameOf(r.author) end,
			token = token },
		{ id = "date", title = L["HANDBOOK_COL_DATE"], width = 140, mono = true, value = function(r) return r.time or 0 end,
			text = function(r) return date("%Y-%m-%d %H:%M", r.time or 0) end, token = token },
		{ id = "size", title = L["HANDBOOK_COL_SIZE"], width = 80, align = "RIGHT", mono = true,
			value = function(r) return #(r.body or "") end, text = function(r) return group(#(r.body or "")) end, token = token },
		{ id = "state", title = L["HANDBOOK_COL_STATE"], width = 90, token = token, text = function(r)
			if r.current then return L["HANDBOOK_REV_CURRENT"] end
			return r.lost and L["HANDBOOK_REV_LOST"] or ""
		end },
	}
end
local function buildRevisions(f)
	local p = CreateFrame("Frame", nil, f)
	p:SetPoint("TOPLEFT", f.list, "TOPRIGHT", View.GAP, 0)
	p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	p.title = Widgets.Text(p, "H2", "text-1", "LEFT")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -4)
	p.title:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -4)
	p.title:SetWordWrap(false)
	p.note = Widgets.Text(p, "Small", "text-3", "LEFT")
	p.note:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -28)
	p.note:SetText(L["HANDBOOK_REV_NOTE"])
	p.table = Widgets.DataTable(p, revisionColumns(), { rowHeight = Editor.REVISION_ROW, pool = Editor.REVISION_ROWS,
		maxPool = Editor.REVISION_ROWS + 4, memory = "handbook.revisions", sort = { id = "rev", desc = true },
		isSelected = function(d)
			local pick = View.revisions and View.revisions.pick
			return pick ~= nil and (d == pick or (d.current and pick.current) == true)
		end,
		onRowClick = function(r)
			local v = View.revisions
			if not v then return end
			v.rev, v.time, v.author, v.error = r.rev, r.time, r.author, nil
			Editor:PaintRevisions()
		end })
	p.table:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -46)
	p.table:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -46)
	p.table:SetHeight(REVISION_TABLE)
	local top = -52 - REVISION_TABLE
	p.name = Widgets.Text(p, "H2", "text-1", "LEFT")
	p.name:SetPoint("TOPLEFT", p, "TOPLEFT", 0, top)
	p.name:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, top)
	p.pane = previewPane(p)
	p.pane.text:SetPoint("TOPLEFT", p, "TOPLEFT", 0, top - 24)
	p.pane.text:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 64)
	p.status = Widgets.Text(p, "Small", "err", "LEFT")
	p.status:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 44)
	p.restore = button(p, "HANDBOOK_RESTORE", "filled", function() Editor:Restore() end)
	p.restore:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 4)
	p.dismiss = button(p, "HANDBOOK_DISMISS", "outlined", function() Editor:Dismiss() end)
	p.dismiss:SetPoint("RIGHT", p.restore, "LEFT", -8, 0)
	p.close = button(p, "HANDBOOK_CLOSE", "text", function()
		View.revisions = nil
		View:Redraw()
	end)
	p.close:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 4)
	f.revPanel = p
	return p
end

-- The revision chosen in the list: the one clicked; else the lost one asked for (a conflict); else the newest.
local function picked(list, v)
	if v.time then
		for _, r in ipairs(list) do
			if r.rev == v.rev and r.time == v.time and r.author == v.author then return r end
		end
	elseif v.rev then
		for _, r in ipairs(list) do if r.lost and r.open and r.rev == v.rev then return r end end
	end
	return list[1]
end

function Editor:PaintRevisions()
	local f, v = View.frame, View.revisions
	local p = f and f.revPanel
	if not (p and v) then return end
	local list = book():Revisions(v.id)
	local pick = picked(list, v)
	if not pick then return end
	v.pick = pick
	-- a past revision stays chosen, also once it is dismissed or another arrives
	if not pick.current then v.rev, v.time, v.author = pick.rev, pick.time, pick.author end
	p.title:SetText(L["HANDBOOK_REV_TITLE"]:format(list[1].title))
	p.table:SetData(list, true)
	p.name:SetText(pick.title)
	preview(p.pane, pick.body or "")
	p.status:SetText(v.error or "")
	p.restore:SetShown(not pick.current)
	p.dismiss:SetShown(pick.lost == true and pick.open == true)
end

-- The chosen revision written as a new revision.
function Editor:Restore()
	local v = View.revisions
	local r = v and v.pick
	if not r or r.current then return false end
	local rec, why = book():Restore(v.id, r.rev, r.time, r.author)
	if not rec then
		v.error = Editor.Reason(why)
		self:PaintRevisions()
		return false, why
	end
	View.revisions = nil
	if not View:Show(v.id) then View:Redraw() end
	return rec
end

function Editor:Dismiss()
	local v = View.revisions
	if not (v and v.pick) then return end
	book():Dismiss(v.id, v.pick.rev)
	View:Redraw()
end

-- Opens the revisions of the page `id` (live or deleted); `rev`: with the lost revision of that number chosen.
function View:OpenRevisions(id, rev)
	if not (self.frame and writer()) or self.editor or #book():Revisions(id) == 0 then return false end
	local rec = book():Get(id)
	if rec and not rec.del then self.selected, self.history = id, {} end
	self.revisions, self.deleting = { id = id, rev = rev }, nil
	self:Redraw()
	return true
end

-- The Action Center row and the notice of a conflict: the writer's lost text, to restore or dismiss.
function View:OpenConflict(id, rev)
	if not self:Open() then return false end
	if id and not self:OpenRevisions(id, rev) then self:Show(id) end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The list and the reader of a writer
---------------------------------------------------------------------------------------------------------------------
-- The pages of the list, then for a writer the deleted pages this client can restore.
function Editor:ListItems(rows)
	if not writer() then return rows end
	local deleted = book():Deleted()
	if #deleted == 0 then return rows end
	local out = {}
	for i, row in ipairs(rows) do out[i] = row end
	out[#out + 1] = { header = true, title = L["HANDBOOK_DELETED_PAGES"] }
	for _, d in ipairs(deleted) do out[#out + 1] = { id = d.id, title = d.title, mark = "deleted", deleted = true } end
	return out
end

local function move(id, step)
	local ok, why = book():Move(id, step)
	if not ok and why ~= "id" and ns.addon then ns.addon:Print(Editor.Reason(why)) end
	View:Redraw()
end

local function arrow(b, key, icon, step)
	return Widgets.IconButton(b, { icon = icon, dense = true, tooltip = L[key],
		onClick = function() if b.id then move(b.id, step) end end })
end

-- The arrows of the chosen page, in the place of its mark.
function Editor:Row(f, b, item, searching)
	local show = not searching and not item.deleted and item.mark ~= "over" and item.id ~= nil
		and item.id == View.selected and not View.revisions and writer() and View:OwnOrder()
	if show and not b.up then
		b.up = arrow(b, "HANDBOOK_MOVE_UP", "arrow_up", -1)
		b.down = arrow(b, "HANDBOOK_MOVE_DOWN", "arrow_down", 1)
		b.down:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
		b.up:SetPoint("RIGHT", b.down, "LEFT", 0, 0)
	end
	if not b.up then return end
	b.up:SetShown(show)
	b.down:SetShown(show)
	if show then
		for a, step in pairs({ [b.up] = -1, [b.down] = 1 }) do
			a:SetEnabled(book():MovePlan(item.id, step) ~= nil)
		end
		b.mark:SetText("")
		b.label:SetPoint("TOPRIGHT", b.up, "TOPLEFT", -6, -9)
	end
end

local function toggleRank(index)
	local set = {}
	for _, r in ipairs(book():ChosenRanks()) do
		if book():RankStillValid(r) then set[r.i] = true end
	end
	set[index] = not set[index] or nil
	local list = {}
	for i = 1, 9 do if set[i] then list[#list + 1] = i end end
	local ok, why = book():SetWriters(list)
	if not ok and ns.addon then ns.addon:Print(Editor.Reason(why)) end
end

-- The officers' choice of the ranks that write besides them.
function Editor:ShowWriters(anchor)
	if not (writer() and ns.Role and ns.Role:IsOfficer()) then return end
	local chosen = {}
	for _, r in ipairs(book():ChosenRanks()) do
		if book():RankStillValid(r) then chosen[r.i] = true end
	end
	local items = { { text = L["HANDBOOK_WRITERS_HEADER"], header = true } }
	for _, rank in ipairs(ns.Compat.Guild.Ranks()) do
		local i = rank.index
		if i >= 1 and i <= 9 then
			if ns.Compat.Guild.RankIsOfficer(i) then
				items[#items + 1] = { text = L["HANDBOOK_WRITERS_OFFICER"]:format(rank.name), header = true }
			else
				items[#items + 1] = { text = rank.name, checked = chosen[i] == true, keepOpen = true, rank = i,
					onClick = function() toggleRank(i) end }
			end
		end
	end
	Widgets.Menu.Show(anchor, items, Editor.WRITERS_WIDTH)
end

local function staleRanks()
	for _, r in ipairs(book():ChosenRanks()) do
		if not book():RankStillValid(r) then return true end
	end
	return false
end

-- "Delete", then "Confirm".
local function delete()
	local rec = View.selected and book():Get(View.selected)
	if not rec then return end
	local armed = View.deleting
	if not (armed and armed.id == rec.id) then
		View.deleting = { id = rec.id, rev = rec.rev }
	else
		local ok, why = book():Delete(armed.id, armed.rev)
		View.deleting = nil
		if not ok and ns.addon then ns.addon:Print(Editor.Reason(why)) end
	end
	View:Redraw()
end

-- "Create the default pages" (M11.5), once for the guild.
local function seed()
	local ok, why = ns.HandbookDefaults:Seed()
	if not ok and why ~= "seeded" and ns.addon then ns.addon:Print(Editor.Reason(why)) end
	View:Redraw()
end

local function buildWriter(f)
	f.seed = button(f, "HANDBOOK_SEED", "filled", seed)
	f.seed:SetPoint("TOP", f, "TOP", 0, -90)
	f.newPage = button(f, "HANDBOOK_NEW", "tonal", function() View:Edit() end, 100)
	f.writers = button(f, "HANDBOOK_WRITERS", "text", function() Editor:ShowWriters(f.writers) end, 80)
	f.stale = Widgets.Text(f, "Small", "warn", "LEFT")
	f.stale:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 86)
	f.stale:SetText(L["HANDBOOK_WRITERS_STALE"])
	f.edit = button(f.reader, "HANDBOOK_EDIT", "tonal", function() View:Edit(View.selected) end)
	f.edit:SetPoint("BOTTOMLEFT", f.reader, "BOTTOMLEFT", 0, 4)
	f.revisionsButton = button(f.reader, "HANDBOOK_REVISIONS", "outlined", function()
		View:OpenRevisions(View.selected)
	end)
	f.revisionsButton:SetPoint("LEFT", f.edit, "RIGHT", 8, 0)
	f.delete = button(f.reader, "HANDBOOK_DELETE", "text", delete)
	f.delete:SetPoint("LEFT", f.revisionsButton, "RIGHT", 8, 0)
	f.deleteNote = Widgets.Text(f.reader, "Small", "warn", "LEFT")
	f.deleteNote:SetPoint("BOTTOMLEFT", f.reader, "BOTTOMLEFT", 0, 44)
	f.deleteNote:SetText(L["HANDBOOK_DELETE_ASK"])
end

local function hideAll(f)
	f.list:Hide()
	f.reader:Hide()
	f.empty:Hide()
	f.markAll:Hide()
	f.sort:Hide()
	if f.newPage then f.newPage:Hide() f.writers:Hide() f.stale:Hide() f.seed:Hide() end
	if f.revPanel then f.revPanel:Hide() end
end

-- Called by View:Redraw before it draws: true while the editor takes the whole view.
function Editor:Cover(f)
	if not writer() then
		View.editor, View.revisions, View.deleting = nil, nil, nil
		if Widgets.Menu.IsOpen() and f.writers and f.writers:IsShown() then Widgets.Menu.Hide() end
	end
	local on = View.editor ~= nil
	if f.editorPanel then f.editorPanel:SetShown(on) end
	if not on then return false end
	hideAll(f)
	self:Paint()
	return true
end

-- Called by View:Redraw after the list and the reader (`row`: the page the reader shows).
function Editor:Decorate(f, row)
	local may = writer()
	local officer = may and ns.Role ~= nil and ns.Role:IsOfficer()
	if may and not f.newPage then buildWriter(f) end
	local stale = officer and staleRanks()
	local bottom = may and (stale and 112 or 84) or View.LIST_BOTTOM
	if (f.listBottom or View.LIST_BOTTOM) ~= bottom then
		f.listBottom = bottom
		View.Layout(f)
	end
	local textBottom = may and 64 or 0
	if (f.textBottom or 0) ~= textBottom then
		f.textBottom = textBottom
		f.text:ClearAllPoints()
		f.text:SetPoint("TOPLEFT", f.reader, "TOPLEFT", 0, -View.HEADER)
		f.text:SetPoint("BOTTOMRIGHT", f.reader, "BOTTOMRIGHT", 0, textBottom)
	end
	if f.newPage then
		f.newPage:SetShown(may)
		f.seed:SetShown(may and ns.HandbookDefaults:CanSeed() and View.revisions == nil)
		f.newPage:ClearAllPoints()
		f.newPage:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 44)
		f.writers:ClearAllPoints()
		f.writers:SetPoint("LEFT", f.newPage, "RIGHT", 6, 0)
		f.writers:SetShown(officer == true)
		f.stale:SetWidth(f.listWidth or View.LIST_WIDTH)
		f.stale:SetShown(stale == true)
		local page = may and row ~= nil
		f.edit:SetShown(page)
		f.revisionsButton:SetShown(page)
		f.delete:SetShown(page)
		if View.deleting and not (row and View.deleting.id == row.id) then View.deleting = nil end
		f.delete:SetLabel(L[View.deleting and "HANDBOOK_CONFIRM" or "HANDBOOK_DELETE"])
		f.deleteNote:SetShown(page and View.deleting ~= nil)
	end
	local v = View.revisions
	if v and #book():Revisions(v.id) == 0 then View.revisions, v = nil, nil end
	if v and not f.revPanel then buildRevisions(f) end
	if f.revPanel then f.revPanel:SetShown(v ~= nil) end
	if v then
		f.reader:Hide()
		self:PaintRevisions()
	end
end

if ns.addon then
	ns.addon.HandbookEditor = Editor
	if ns.Bus then
		-- the chosen ranks are a record of `guildcfg`
		ns.Bus:On("STORE_CHANGED", function(set) if set == "guildcfg" then View:Changed() end end)
	end
end

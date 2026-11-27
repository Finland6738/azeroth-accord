-- Loot page: the fixed part above the text of the handbook's loot page (M11.6, SPEC-15 §8.2-§8.6; SPEC-10 Q30-Q33).
-- Lua 5.1.
--
-- From the top  the loot system; the loot addon with its state on this client (and "Open FDCP"); the address to download
--               it, in a read-only copy box (not loaded here, or for a writer); who has it (counts for everybody, names
--               and who lacks it for officers and the Guild Master); with FDCP as the loot source, the player's credits
--               and FDCP's rules, read when drawn and never copied into the page. Without an addon chosen nothing about
--               addons is shown and nothing is checked: writers get the FDCP suggestion (a locale text), officers
--               "Choose FDCP". Officers change the system and the addon in a small form (Data/Loot.lua writes).
-- Where         inside the Handbook view's reader (LootPage.Attach), and in the Raid view while the loot page cannot be
--               read (deleted, never written, or still a template): UI/Raid.lua.
-- Parts         LootPage.Model() reads everything now; LootPage.Lines(model, form) is a plain function of it (tested
--               offline): { { text?, sub?, muted?, warn?, indent?, button?, copy?, form? } }; LootPage.Create(parent)
--               gives the frame that draws the lines.
local ADDON_NAME, ns = ...
ns = ns or {}
local Page = {}
ns.LootPage, ns.modules = Page, ns.modules or {}
ns.modules.LootPage = Page

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, floor, max, concat = type, ipairs, pairs, tostring, math.floor, math.max, table.concat

Page.WIDTH = 420
Page.GAP = 4
Page.AFTER = 16               -- between the fixed part and the page's text
Page.INDENT = 12
Page.MENU_WIDTH = 220
Page.BUTTON_HEIGHT = Widgets.HEIGHT.dense
Page.FIELD_PITCH = Widgets.HEIGHT.dense + 8   -- one line of the forms
Page.NAMES = 40               -- names written without the addon before "and N more"

-- locale-key: LOOT_SYSTEM_NONE LOOT_SYSTEM_ROLLS LOOT_SYSTEM_SOFTRES LOOT_SYSTEM_COUNCIL LOOT_SYSTEM_DKP
-- locale-key: LOOT_SYSTEM_CREDITS LOOT_SYSTEM_OTHER
-- locale-key: LOOT_ERR_SYSTEMNAME LOOT_ERR_ADDONNAME LOOT_ERR_ADDONFOLDER LOOT_ERR_URL
local BUTTONS = {
	system = "LOOT_CHANGE", addon = "LOOT_CHANGE", pick = "LOOT_CHOOSE_ADDON", open = "FDCP_OPEN", fdcp = "LOOT_CHOOSE_FDCP",
}
-- locale-key: LOOT_CHANGE LOOT_CHOOSE_ADDON FDCP_OPEN LOOT_CHOOSE_FDCP

local function loot() return ns.Loot end

-- The name of a system, with the guild's own for "other".
function Page.SystemName(system, own)
	if system == "other" and own then return own end
	return L["LOOT_SYSTEM_" .. tostring(system or "none"):upper()]
end

-- The name of a value of `addon`.
function Page.AddonName(id)
	if id == "none" then return L["LOOT_ADDON_NONE"] end
	if id == "other" then return L["LOOT_ADDON_OTHER"] end
	local def = loot().Known(id)
	return def and (def.name or def.folder) or tostring(id)
end

---------------------------------------------------------------------------------------------------------------------
-- The model and its lines
---------------------------------------------------------------------------------------------------------------------
function Page.Model()
	local Loot, I = loot(), ns.Integrations
	local g = Loot:Get()
	local m = { officer = Loot:CanChoose(), writer = ns.Handbook ~= nil and ns.Handbook:CanWrite() == true,
		system = g.system, systemName = g.systemName, addonId = g.addon }
	m.addon = Loot:Addon()
	if m.addon then
		m.state = Loot:State()
		m.holders = Loot:Holders()
	end
	-- FDCP beside the page: only while it is the loot source (SPEC-15 §8.6)
	if m.addon and m.addon.id == "fdcp" and I:Source("loot") == "fdcp" then
		local F = ns.FDCP
		local f = { fdcp = m.state, source = nil }
		if f.fdcp and f.fdcp.level == 1 and F then
			f.ready = F.Ready()
			if f.ready then
				f.source = F.Source()
				f.rules = F.Rules()
				local me = ns.Compat.Player.Name()
				f.mine = me and F.Credits(me) or nil
			end
		end
		m.fdcp = f
	end
	return m
end

local function short(name)
	if type(name) ~= "string" then return "?" end
	return (ns.Compat.SplitName(name))
end

-- "Loaded 7.1", "Not loaded", "Not installed" or "Folder not confirmed".
function Page.StateText(st)
	if st.status == "loaded" then
		return st.version and L["LOOT_ST_LOADED_V"]:format(st.version) or L["LOOT_ST_LOADED"]
	end
	if st.status == "disabled" or st.status == "installed" then return L["LOOT_ST_NOT_LOADED"] end
	-- a folder Accord has not seen in game: "missing" may only mean the name is wrong
	if not st.confirmed then return L["LOOT_ST_UNCONFIRMED"] end
	return L["LOOT_ST_MISSING"]
end

local function download(out, url)
	out[#out + 1] = { text = L["LOOT_DOWNLOAD"], muted = true }
	out[#out + 1] = { copy = url }
end

local function holders(out, m)
	local h, R = m.holders, ns.RaidView
	out[#out + 1] = { text = L["LOOT_WHO"], sub = true }
	if h.off then
		out[#out + 1] = { text = L["INTEG_CENSUS_OFF"], muted = true }
		return
	end
	if h.total == 0 then out[#out + 1] = { text = L["ADDONS_NOBODY"], muted = true } end
	if not h.sharing then out[#out + 1] = { text = L["ADDONS_NOT_SHARING"], muted = true } end
	if h.total > 0 then
		if m.addon.id == "other" and not h.found then
			out[#out + 1] = { text = L["LOOT_FOLDER_UNKNOWN"]:format(m.addon.folder) }
		else
			local text = L["LOOT_COUNT"]:format(h.users, h.total)
			local versions = {}
			for i, v in ipairs(h.versions) do
				if i > R.VERSIONS then break end
				versions[#versions + 1] = L["INTEG_VERSION_N"]:format(v.version or L["ADDONS_NO_VERSION"], v.n)
			end
			if #versions > 0 then
				local list = concat(versions, ", ")
				if #h.versions > #versions then list = list .. L["RAID_MORE"]:format(#h.versions - #versions) end
				text = text .. R.SEP .. L["INTEG_VERSIONS"]:format(list)
			end
			out[#out + 1] = { text = text }
		end
	end
	if not h.officer then out[#out + 1] = { text = L["INTEG_NAMES_OFFICERS"], muted = true } end
	for _, w in ipairs(h.who or {}) do out[#out + 1] = R.HolderLine(w) end
	if h.officer then
		if #h.without > 0 then
			local names = {}
			for i, w in ipairs(h.without) do
				if i > Page.NAMES then break end
				names[#names + 1] = short(w.name)
			end
			local list = concat(names, ", ")
			if #h.without > #names then list = list .. L["RAID_MORE"]:format(#h.without - #names) end
			out[#out + 1] = { text = L["LOOT_WITHOUT"]:format(#h.without, list), indent = true }
		end
		if (h.unknown or 0) > 0 then out[#out + 1] = { text = L["LOOT_UNKNOWN"]:format(h.unknown), muted = true } end
	else
		for _, w in ipairs(h.without) do
			if w.own then out[#out + 1] = { text = L["LOOT_YOU_WITHOUT"]:format(short(w.name)), indent = true } end
		end
	end
end

local function fdcpLines(out, m)
	local f, R = m.fdcp, ns.RaidView
	if not (f.fdcp and f.fdcp.level == 1) then return end
	if not (f.ready and f.source) then
		out[#out + 1] = { text = R.Problem(f), muted = true }
		return
	end
	local c = f.mine
	if c then
		if c.place then out[#out + 1] = { text = L["LOOT_MINE"]:format(R.Num(c.credits), c.place, c.of or c.place) }
		else out[#out + 1] = { text = L["LOOT_MINE_NO_PLACE"]:format(R.Num(c.credits)) } end
	else
		out[#out + 1] = { text = L["LOOT_MINE_NONE"], muted = true }
	end
	if f.rules then R.RulesLines(out, f.rules) else out[#out + 1] = { text = L["RULES_NONE"], muted = true } end
end

-- The lines of the fixed part. `form` = "system" | "addon" | nil: the form an officer has open, in place of that button.
function Page.Lines(m, form)
	local out = {}
	if not m.officer then form = nil end
	local function change(id) if m.officer and form ~= id then return id end end
	if m.system ~= "none" or m.writer then
		local name = m.system == "none" and L["LOOT_NOT_SET"] or Page.SystemName(m.system, m.systemName)
		out[#out + 1] = { text = L["LOOT_SYSTEM"]:format(name), button = change("system") }
	end
	if form == "system" then out[#out + 1] = { form = "system" } end

	local a = m.addon
	if not a then
		-- nothing about addons: the suggestion for writers, the choice for officers (SPEC-10 Q33)
		if m.writer then
			local def = loot().Known("fdcp")
			out[#out + 1] = { text = L["LOOT_SUGGEST_FDCP"] }
			if def and def.url then download(out, def.url) end
		end
		if m.officer then
			out[#out + 1] = { button = "fdcp" }
			if form ~= "addon" then out[#out + 1] = { button = "pick" } end
		end
		if form == "addon" then out[#out + 1] = { form = "addon" } end
		return out
	end
	out[#out + 1] = { text = L["LOOT_ADDON"]:format(a.name), button = change("addon") }
	if form == "addon" then out[#out + 1] = { form = "addon" } end
	out[#out + 1] = { text = L["LOOT_ON_CLIENT"]:format(Page.StateText(m.state)), muted = m.state.status ~= "loaded" }
	if a.id == "fdcp" and m.state.level ~= nil then out[#out + 1] = { button = "open" } end
	if a.url and (m.state.status ~= "loaded" or m.writer) then download(out, a.url) end
	holders(out, m)
	if m.fdcp then fdcpLines(out, m) end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------------------------------------------------
local function button(w, key, onClick, style)
	return Widgets.Button(w, { text = L[key], style = style or "tonal", height = Page.BUTTON_HEIGHT, onClick = onClick })
end

-- A read-only copy box: selects its text on focus and puts it back when the player types in it.
local function copyBox(w)
	local box = Widgets.EditBox(w, { dense = true })
	box.edit:HookScript("OnTextChanged", function(self, user)
		if user and self:GetText() ~= box.value then
			self:SetText(box.value or "")
			self:HighlightText()
		end
	end)
	box.edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
	return box
end

local FIELDS = {
	system = { { id = "systemName", hint = "LOOT_SYSTEM_NAME_HINT", max = 32 } },
	addon = {
		{ id = "addonName", hint = "LOOT_ADDON_NAME_HINT", max = 32 },
		{ id = "addonFolder", hint = "LOOT_FOLDER_HINT", max = 64 },
		{ id = "url", hint = "LOOT_URL_HINT", max = 120 },
	},
}
-- locale-key: LOOT_SYSTEM_NAME_HINT LOOT_ADDON_NAME_HINT LOOT_FOLDER_HINT LOOT_URL_HINT

local function buildForm(w, what)
	local f = CreateFrame("Frame", nil, w)
	f.value = button(f, "LOOT_CHANGE", function() w:ShowChoices(what) end)
	f.value:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.fields = {}
	for i, def in ipairs(FIELDS[what]) do
		local box = Widgets.EditBox(f, { dense = true, maxLetters = def.max, placeholder = L[def.hint] })
		box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -i * Page.FIELD_PITCH)
		box:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -i * Page.FIELD_PITCH)
		f.fields[def.id] = box
	end
	f.error = Widgets.Text(f, "Small", "err", "LEFT")
	f.save = button(f, "HANDBOOK_SAVE", function() w:Save() end, "filled")
	f.cancel = button(f, "HANDBOOK_CANCEL", function() w:CloseForm() end, "outlined")
	w.forms[what] = f
	return f
end

local function paintForm(w, what, width)
	local f = w.forms[what] or buildForm(w, what)
	local form = w.form
	f.value:SetLabel(what == "system" and Page.SystemName(form.value) or Page.AddonName(form.value))
	local other = form.value == "other"
	local rows = 1
	for _, def in ipairs(FIELDS[what]) do
		f.fields[def.id]:SetShown(other)
		if other then rows = rows + 1 end
	end
	local y = -rows * Page.FIELD_PITCH
	f.error:SetText(form.error or "")
	f.error:SetShown(form.error ~= nil)
	f.error:ClearAllPoints()
	f.error:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
	f.error:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
	if form.error then y = y - 20 end
	f.save:ClearAllPoints()
	f.save:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
	f.cancel:ClearAllPoints()
	f.cancel:SetPoint("LEFT", f.save, "RIGHT", 8, 0)
	f:SetSize(width, -y + Page.BUTTON_HEIGHT + 6)
	return f
end

-- The table of FDCP's costs, `y` below the top: every row shown, as high as they are. Returns the height it takes.
local function costsTable(w, rows, y, x)
	local t = w.costs
	if not t then
		local columns = {}
		for i, c in ipairs(ns.RaidView.Tables["raid.costs"].columns) do
			local id, col = c.id, {}
			for k, v in pairs(c) do col[k] = v end
			col.text = function(l) return l.cells[id] end
			col.value = function(l)
				local key = l.keys and l.keys[id]
				if key ~= nil then return key end
				return l.cells[id]
			end
			columns[i] = col
		end
		t = Widgets.DataTable(w, columns, { pool = 1, memory = "raid.costs", noScrollbar = true, onWheel = function() end })
		w.costs = t
	end
	local height = 35 + #rows * 32
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", w, "TOPLEFT", x, -y)
	t:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -y)
	t:SetHeight(height)
	t.window = #rows
	t:SetData(rows, true)
	t:SetWindow(#rows, 0)
	t:Show()
	return height + Page.GAP
end

-- Draws the lines for the model, `width` wide. Returns the height.
local function update(w, model, width)
	width = (width and width > 0) and width or Page.WIDTH
	w.model = model
	if w.form and not model.officer then w.form = nil end
	local lines = Page.Lines(model, w.form and w.form.what)
	w.lines = lines
	for _, b in pairs(w.buttons) do b:Hide() end
	for _, f in pairs(w.forms) do f:Hide() end
	w.copy:Hide()
	local y, n = 0, 0
	-- the lines with a table (FDCP's costs, UI/Raid.lua) are its rows (ui-style §9.9)
	local costs = {}
	for _, line in ipairs(lines) do if line.table == "raid.costs" then costs[#costs + 1] = line end end
	if w.costs then w.costs:Hide() end
	for _, line in ipairs(lines) do
		local x = line.indent and Page.INDENT or 0
		if line.table == "raid.costs" then
			if line == costs[1] then y = y + costsTable(w, costs, y, x) end
			line = {}   -- drawn as a row of the table
		end
		local b = line.button and w.buttons[line.button]
		if line.button and not b then
			local id = line.button
			b = button(w, BUTTONS[id], function() w:Press(id) end)
			w.buttons[id] = b
		end
		if line.text then
			n = n + 1
			local fs = w.texts[n]
			if not fs then
				fs = Widgets.Text(w, "Body", "text-1", "LEFT")
				w.texts[n] = fs
			end
			local room = width - x - (b and (b:GetWidth() or 0) + 8 or 0)
			fs:SetFontObject(Theme.Font(line.sub and "BodyMedium" or "Body"))
			fs:SetWidth(room)
			fs:SetWordWrap(true)
			fs:SetText(line.text)
			Theme.Text(fs, line.warn and "warn" or line.muted and "text-3" or line.sub and "text-1" or "text-2")
			if line.sub and y > 0 then y = y + 8 end
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", w, "TOPLEFT", x, -y - (b and 5 or 0))
			fs:Show()
			if b then
				b:ClearAllPoints()
				b:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -y)
				b:Show()
			end
			local h = fs:GetStringHeight()
			if type(h) ~= "number" or h <= 0 then h = 16 end
			y = y + max(h, b and Page.BUTTON_HEIGHT or 0) + Page.GAP
		elseif b then
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", w, "TOPLEFT", x, -y)
			b:Show()
			y = y + Page.BUTTON_HEIGHT + Page.GAP
		elseif line.copy then
			w.copy.value = line.copy
			w.copy:SetText(line.copy)
			w.copy.edit:SetCursorPosition(0)
			w.copy:ClearAllPoints()
			w.copy:SetPoint("TOPLEFT", w, "TOPLEFT", x, -y)
			w.copy:SetWidth(width - x)
			w.copy:Show()
			y = y + Widgets.HEIGHT.dense + Page.GAP
		elseif line.form then
			local f = paintForm(w, line.form, width)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -y)
			f:Show()
			y = y + (f:GetHeight() or 0) + Page.GAP
		end
	end
	for i = n + 1, #w.texts do w.texts[i]:Hide() end
	local height = floor(y + 0.5)
	w:SetSize(width, max(1, height))
	w.contentHeight = height
	return height
end

-- A frame that shows the fixed part. :Update(model, width) -> height; :Press(button id), :Choose(value), :Save(),
-- :CloseForm(). `onResize` is called after a click that changed what it shows.
function Page.Create(parent, onResize)
	local w = CreateFrame("Frame", nil, parent)
	w.texts, w.buttons, w.forms = {}, {}, {}
	w.copy = copyBox(w)
	w.copy:Hide()
	w.Update = update

	local function redraw()
		if onResize then onResize() else update(w, Page.Model(), w:GetWidth()) end
	end

	function w:OpenForm(what)
		local g = loot():Get()
		self.form = { what = what, value = g[what] }
		local f = self.forms[what] or buildForm(self, what)
		-- the texts are set only here: a redraw while the officer types leaves them alone
		for _, def in ipairs(FIELDS[what]) do f.fields[def.id]:SetText(g[def.id] or "") end
		redraw()
	end

	function w:CloseForm()
		self.form = nil
		Widgets.Menu.Hide()
		redraw()
	end

	function w:Choose(value)
		if not self.form then return end
		self.form.value, self.form.error = value, nil
		redraw()
	end

	function w:ShowChoices(what)
		local items = {}
		for _, v in ipairs(what == "system" and loot().SYSTEMS or loot().Addons()) do
			items[#items + 1] = { text = what == "system" and Page.SystemName(v) or Page.AddonName(v),
				checked = self.form ~= nil and self.form.value == v, value = v, onClick = function() self:Choose(v) end }
		end
		Widgets.Menu.Show(self.forms[what].value, items, Page.MENU_WIDTH)
	end

	-- One click, no confirmation: it can be changed again.
	function w:Save()
		local form = self.form
		if not form then return false end
		local f = self.forms[form.what]
		local changes = { [form.what] = form.value }
		if form.value == "other" then
			for _, def in ipairs(FIELDS[form.what]) do changes[def.id] = f.fields[def.id]:GetText() or "" end
		end
		local ok, why = loot():Set(changes)
		if not ok then
			local known = { systemName = true, addonName = true, addonFolder = true, url = true }
			form.error = known[why] and L["LOOT_ERR_" .. why:upper()] or L["LOOT_ERR"]:format(tostring(why))
			redraw()
			return false, why
		end
		self.form = nil
		redraw()
		return true
	end

	function w:Press(id)
		if id == "open" then
			if ns.FDCP then ns.FDCP.Open() end
		elseif id == "fdcp" then
			local ok, why = loot():Set({ addon = "fdcp" })
			if not ok and ns.addon then ns.addon:Print(L["LOOT_ERR"]:format(tostring(why))) end
			self.form = nil
			redraw()
		elseif id == "pick" then
			self:OpenForm("addon")
		else
			self:OpenForm(id)
		end
	end

	return w
end

-- The fixed part inside the Handbook view's reader (`f`): above the text of the loot page, nothing on any other page.
-- Returns the height it takes, which the text starts under.
function Page.Attach(f, rec)
	local w = f.loot
	if not (rec and rec.id == loot().PAGE and loot().Enabled()) then
		if w then
			w.form = nil
			w:Hide()
		end
		return 0
	end
	if not w then
		w = Page.Create(f.text.page, function() if ns.HandbookView then ns.HandbookView:Redraw() end end)
		w:SetPoint("TOPLEFT", f.text.page, "TOPLEFT", 0, 0)
		f.loot = w
	end
	local width = f.text:GetWidth() or 0
	local height = w:Update(Page.Model(), width > 0 and width or ns.HandbookView.WIDTH)
	w:SetShown(height > 0)
	return height > 0 and height + Page.AFTER or 0
end

if ns.addon then ns.addon.LootPage = Page end

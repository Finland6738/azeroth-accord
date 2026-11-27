-- GuildAddons: the "Guild addons" tab, which addons the guild's members use (SPEC-13 §8.6, M9.9; SPEC-10 Q11). Lua 5.1.
--
-- The sentence on top says out of how many members the counts are: those who run Accord and share their list. The table
-- has one row per addon: name (its title, else the folder; the folder is in the tooltip), members, share and versions in
-- use (the most used and "+N"), sorted by any column (members, most first, to begin with) and filtered by the panel's
-- search box. A row of an addon of one's own is marked. A click on a row shows under the table who uses it: officers and
-- the Guild Master everybody, anybody else only their own entry (Data/Census.lua decides: Census:Who). The frames only
-- draw: the data comes from Census:Summary and Census:Who and the plain functions below. The tab is there only while the
-- switch `census` is on.
--   View.Rows(search)        the rows of Census:Summary that match, and the summary
--   View.Text(row, column)   the text of a cell ("name", "users", "share", "versions")
--   View.Sentence(total)     the denominator in words
--   View.TipLines(row)       the tooltip of a row
--   View:Choose(folder)      shows (or, a second time, hides) who uses an addon
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.GuildAddonsView, ns.modules = View, ns.modules or {}
ns.modules.GuildAddonsView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring = type, ipairs, tostring
local concat = table.concat

View.HEAD_HEIGHT = 44
View.DETAIL_HEIGHT = 224
View.TIP_VERSIONS = 8        -- versions a tooltip lists

View.selected = nil          -- the folder whose users are shown
View.search = ""

local function enabled() return ns.Census ~= nil and ns.Census.Enabled() end
local function lower(s) return type(s) == "string" and s:lower() or "" end

---------------------------------------------------------------------------------------------------------------------
-- What is shown (plain functions, tested offline)
---------------------------------------------------------------------------------------------------------------------
function View.Rows(search)
	local summary = ns.Census:Summary()
	local query = lower(search)
	if query == "" then return summary.rows, summary end
	local out = {}
	for _, row in ipairs(summary.rows) do
		if lower(row.name):find(query, 1, true) or lower(row.folder):find(query, 1, true) then out[#out + 1] = row end
	end
	return out, summary
end

local function versionText(version) return version or L["ADDONS_NO_VERSION"] end

function View.Text(row, column)
	if column == "name" then return row.name end
	if column == "users" then return tostring(row.users) end
	if column == "share" then return ("%d%%"):format(row.share) end
	if column == "versions" then
		local first = row.versions[1]
		if not first then return "" end
		local text = versionText(first.version)
		if #row.versions > 1 then text = ("%s (+%d)"):format(text, #row.versions - 1) end
		return text
	end
	return ""
end

function View.Sentence(total)
	if total <= 0 then return L["ADDONS_NOBODY"] end
	if total == 1 then return L["ADDONS_OUT_OF_ONE"] end
	return L["ADDONS_OUT_OF"]:format(total)
end

function View.TipLines(row)
	local lines = { row.name, { text = L["ADDONS_FOLDER"]:format(row.folder) } }
	for i, v in ipairs(row.versions) do
		if i > View.TIP_VERSIONS then
			lines[#lines + 1] = L["ADDONS_OTHER_VERSIONS"]:format(#row.versions - View.TIP_VERSIONS)
			break
		end
		lines[#lines + 1] = L["ADDONS_VERSION_LINE"]:format(versionText(v.version), v.n)
	end
	if row.mine then lines[#lines + 1] = L["ADDONS_YOURS"]
	elseif row.here then lines[#lines + 1] = L["ADDONS_YOURS_NOT_SHARED"] end
	return lines
end

-- The rows of the table under the list: { name, chars, version } as texts.
function View.WhoRows(folder)
	local out = {}
	for _, w in ipairs(ns.Census:Who(folder)) do
		local name = w.name
		if w.own then name = (w.shared and L["ADDONS_YOU"] or L["ADDONS_YOU_NOT_SHARED"]):format(name) end
		out[#out + 1] = { name = name, chars = concat(w.chars, ", "), version = versionText(w.version), own = w.own }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------------------------------------------------
local function columns()
	local function col(id, key, opts)
		opts.id, opts.title = id, L[key]
		opts.text = function(row) return View.Text(row, id) end
		return opts
	end
	return {
		col("name", "ADDONS_COL_NAME", { flex = 3, value = function(row) return lower(row.name) end,
			token = function(row) return (row.mine or row.here) and "accent-text" or "text-1" end }),
		col("users", "ADDONS_COL_USERS", { width = 96, mono = true, value = function(row) return row.users end }),
		col("share", "ADDONS_COL_SHARE", { width = 80, mono = true, value = function(row) return row.share end }),
		-- sorted by how many versions are in use, then by the most used one
		col("versions", "ADDONS_COL_VERSIONS", { flex = 2, value = function(row)
			return ("%04d %s"):format(#row.versions, lower(row.versions[1] and row.versions[1].version))
		end }),
	}
end

local function whoColumns()
	local function col(id, key, flex)
		return { id = id, title = L[key], flex = flex, text = function(row) return row[id] end,
			token = function(row) return row.own and "accent-text" or "text-1" end }
	end
	return { col("name", "ADDONS_COL_WHO", 2), col("chars", "ADDONS_COL_CHARS", 3), col("version", "ADDONS_COL_VERSION", 1) }
end

local function place(f)
	f.table:ClearAllPoints()
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.HEAD_HEIGHT)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, f.detail:IsShown() and View.DETAIL_HEIGHT + 8 or 0)
end

local function buildDetail(f)
	local d = Widgets.Card(f)
	d:SetHeight(View.DETAIL_HEIGHT)
	d:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	d.title = Widgets.Text(d, "BodyMedium", "text-1", "LEFT")
	d.title:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -10)
	d.title:SetPoint("RIGHT", d, "RIGHT", -110, 0)
	if d.title.SetWordWrap then d.title:SetWordWrap(false) end
	d.close = Widgets.Button(d, { text = L["ADDONS_CLOSE"], style = "text", height = Widgets.HEIGHT.small, width = 90,
		onClick = function() View:Choose(nil) end })
	d.close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -8, -6)
	d.note = Widgets.Text(d, "Small", "text-3", "LEFT")
	d.note:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -32)
	d.note:SetPoint("RIGHT", d, "RIGHT", -110, 0)
	if d.note.SetWordWrap then d.note:SetWordWrap(false) end
	d.table = Widgets.DataTable(d, whoColumns(), { pool = 8, emptyText = "" })
	d.table:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -52)
	d.table:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -8, 8)
	d:Hide()
	return d
end

local function refreshDetail(f, byFolder)
	local d = f.detail
	local row = View.selected and byFolder[View.selected]
	if not row then
		View.selected = nil
		d:Hide()
		return
	end
	d:Show()
	local officer = ns.Census.CanSeeNames()
	d.title:SetText((officer and L["ADDONS_WHO"] or L["ADDONS_WHO_OWN"]):format(row.name))
	local rows = View.WhoRows(row.folder)
	if officer then d.note:SetText(L["ADDONS_WHO_NOTE"])
	elseif #rows == 0 then d.note:SetText(L["ADDONS_WHO_NOT_YOURS"])
	else d.note:SetText(L["ADDONS_WHO_ONLY_OFFICERS"]) end
	d.table:SetData(rows, true)
end

function View:Redraw()
	local f = self.frame
	if not (f and enabled()) then return end
	local rows, summary = View.Rows(View.search)
	local byFolder = {}
	for _, row in ipairs(summary.rows) do byFolder[row.folder] = row end
	f.sentence:SetText(View.Sentence(summary.total))
	local sharing = ns.Census.Sharing()
	f.note:SetText(sharing and "" or L["ADDONS_NOT_SHARING"])
	f.note:SetShown(not sharing)
	refreshDetail(f, byFolder)
	place(f)
	self.shown = rows
	f.table:SetEmptyText(View.search ~= "" and L["ADDONS_NO_MATCH"] or L["ADDONS_EMPTY"])
	f.table:SetData(rows, true)
end

function View:Choose(folder)
	if folder == self.selected then folder = nil end
	self.selected = folder
	if self.frame then
		self.frame.detail.table:SetOffset(0)
		self:Redraw()
	end
end

-- While the view is on screen the roster is watched: the counts are of the members it lists.
local function watch(f, on)
	if on and not f.watching then
		f.watching = true
		if ns.Roster then ns.Roster:Watch() end
	elseif not on and f.watching then
		f.watching = false
		if ns.Roster then ns.Roster:Unwatch() end
	end
end

function View:Build(f)
	self.frame = f
	f.sentence = Widgets.Text(f, "Body", "text-2", "LEFT")
	f.sentence:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
	f.sentence:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.note = Widgets.Text(f, "Small", "warn", "LEFT")
	f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -22)
	f.note:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.detail = buildDetail(f)
	f.table = Widgets.DataTable(f, columns(), { emptyText = L["ADDONS_EMPTY"],
		onRowClick = function(row) View:Choose(row.folder) end,
		-- the add-on whose users are shown below; the player's own ones have their name in accent-text
		isSelected = function(row) return row.folder == View.selected end,
		rowSetup = function(row)
			Widgets.Tooltip.Attach(row, function(r) return r.data and View.TipLines(r.data) or nil end, "LEFT")
		end })
	place(f)
	f.table:SortBy("users", true)
	f:SetScript("OnShow", function() watch(f, true) View:Redraw() end)
	f:SetScript("OnHide", function() watch(f, false) end)
	watch(f, true)
	self:Redraw()
end

function View:Search(text)
	self.search = text or ""
	if self.frame then
		self.frame.table:SetOffset(0)
		self:Redraw()
	end
end

function View:Changed()
	if enabled() and self.frame and self.frame:IsVisible() then self:Redraw() end
end

if ns.Shell then
	ns.Shell:RegisterView("addons", { label = L["VIEW_ADDONS"], order = 70, search = true, visible = enabled,
		onSearch = function(text) View:Search(text) end, build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.GuildAddonsView = View
	if ns.Bus then
		ns.Bus:On("CENSUS_CHANGED", function() View:Changed() end)
		ns.Bus:On("ROLE_CHANGED", function() View:Changed() end)
		ns.Bus:On("SETTINGS_CHANGED", function() View:Changed() end)
		ns.Bus:On("GUILD_CHANGED", function() View.selected = nil View:Changed() end)
	end
end

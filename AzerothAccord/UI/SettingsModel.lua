-- SettingsModel: the options of Azeroth Accord, the sizes of the saved data and "Clear guild data" (M6.1, SPEC-04 §4).
-- Pure Lua, no frame: UI/Settings.lua draws it in the Settings view of the panel and in the game's Settings window.
-- Lua 5.1. The option table is the one definition: key, saved path, default, who sees it and the texts. Defaults come
-- from Config.defaults, so a damaged value falls back to the same default the wiki lists.
--
-- Options saved per ACCOUNT (AzerothAccordDB.settings), so every character of the player behaves the same:
--   notifyOfficer   a chat line when a bank request arrives that an officer has not seen (officers only)
--   notifyDecision  a chat line when a bank request of the player was approved, rejected or fulfilled
--   shareCoplay     record and publish the time played together (M7.6; Data/CoPlay.lua), on the "What I share" page
--   shareAvailability  publish when this account usually plays (M10.8; Data/Availability.lua), on the same two places as
--                   shareAddons; only while the switch `season` is on
--   shareAddons     publish the list of the loaded addons (M9.9; Data/Census.lua), on the "What I share" page and in the
--                   contacts card of Settings; only while the switch `census` is on (Core/Features.lua)
-- The look (theme, effects, animations, font: account.settings.*, M6.14) has its own small table, Model.LOOK, read by the
-- Appearance card; UI/Theme.lua applies a change at once.
-- Elsewhere, and only listed here for the page: the Discord name (account.settings.discord, Data/Contacts.lua), the main
-- character (Data/Accounts.lua) and the Roster columns (char.ui.columns, per character, UI/RosterModel.lua).
-- Bus: SETTINGS_CHANGED(key) after a change of an option, a look value, a main character or the columns.
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.SettingsModel, ns.modules = Model, ns.modules or {}
ns.modules.SettingsModel = Model

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring

Model.PANEL_NAME = "Azeroth Accord"

Model.OPTIONS = {
	{ key = "notifyOfficer", path = "account.settings.notifyOfficer", label = "SET_NOTIFY_OFFICER", tip = "SET_NOTIFY_OFFICER_TIP",
		group = "notifications", officersOnly = true },
	{ key = "notifyDecision", path = "account.settings.notifyDecision", label = "SET_NOTIFY_DECISION", tip = "SET_NOTIFY_DECISION_TIP",
		group = "notifications" },
	-- the only switch of "What I share" (M7.6, SPEC-11 §5): shown on that page, not in the notices card
	{ key = "shareCoplay", path = "account.settings.shareCoplay", label = "SHARE_COPLAY_SWITCH", tip = "SHARE_COPLAY_SWITCH_TIP",
		group = "sharing" },
	-- the addon census (M9.9, SPEC-13 §8.3): on "What I share" and in the contacts card
	{ key = "shareAddons", path = "account.settings.shareAddons", label = "SHARE_ADDONS_SWITCH", tip = "SHARE_ADDONS_SWITCH_TIP",
		group = "sharing", feature = "census" },
	-- when this account usually plays (M10.8, SPEC-14 §8.3): on "What I share" and in the contacts card
	{ key = "shareAvailability", path = "account.settings.shareAvailability", label = "SHARE_AVAIL_SWITCH",
		tip = "SHARE_AVAIL_SWITCH_TIP", group = "sharing", feature = "season" },
}

local byKey = {}
for _, o in ipairs(Model.OPTIONS) do byKey[o.key] = o end
Model.OPTION = byKey

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

local function defaultAt(path)
	local node = ns.Config and ns.Config.defaults
	for part in path:gmatch("[^.]+") do
		if type(node) ~= "table" then return nil end
		node = node[part]
	end
	return node
end

function Model.Default(key)
	local o = byKey[key]
	return o and defaultAt(o.path) or nil
end

-- The saved value; an option that was never saved (or damaged) is its default.
function Model.Get(key)
	local o = byKey[key]
	if not o then return nil end
	local v = ns.Config and ns.Config:Get(o.path)
	if type(v) ~= "boolean" then return Model.Default(key) end
	return v
end

function Model.IsDefault(key) return Model.Get(key) == Model.Default(key) end

-- Saves an option. Returns true, or false and the reason (unknown option, read-only saved data, a rule).
function Model.Set(key, value)
	local o = byKey[key]
	if not o then return false, "unknown" end
	if type(value) ~= "boolean" then return false, "expected boolean" end
	local ok, why = ns.Config:Set(o.path, value)
	if not ok then return false, why end
	emit("SETTINGS_CHANGED", key)
	return true
end

-- Whether the player sees an option at all (the officer notice means nothing to a member).
function Model.Visible(key)
	local o = byKey[key]
	if not o then return false end
	if o.feature and not (ns.Features and ns.Features.On(o.feature)) then return false end
	if o.officersOnly then return ns.Role ~= nil and ns.Role:IsOfficer() end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The outputs of the notices (SPEC-13 §3.2, M9.3): account.settings.notify.<module>, read by Data/Notify.lua
---------------------------------------------------------------------------------------------------------------------
-- The modules the Notices card offers choices for: the registered ones with a notice that can come out.
function Model.NoticeModules()
	local out = {}
	local N = ns.Notify
	for _, def in ipairs(N and N:Modules() or {}) do
		-- a module of a feature that is switched off (Core/Features.lua) has no row
		local there = def.feature == nil or (ns.Features ~= nil and ns.Features.On(def.feature))
		if there and N.HasOutputs(def) then out[#out + 1] = def end
	end
	return out
end

function Model.GetOutput(module, output)
	return ns.Config ~= nil and ns.Config:Get("account.settings.notify." .. module .. "." .. output) == true
end

function Model.SetOutput(module, output, value)
	if type(value) ~= "boolean" then return false, "expected boolean" end
	local ok, why = ns.Config:Set("account.settings.notify." .. module .. "." .. output, value)
	if not ok then return false, why end
	emit("SETTINGS_CHANGED", "notify")
	return true
end

-- The switch of a kind of notice that has no option of its own (true = on).
function Model.GetKind(module, kind)
	local off = ns.Config and ns.Config:Get("account.settings.notify." .. module .. ".off")
	return not (type(off) == "table" and off[kind] == true)
end

function Model.SetKind(module, kind, on)
	local path = "account.settings.notify." .. module .. ".off"
	local old = ns.Config and ns.Config:Get(path)
	if type(old) ~= "table" or type(on) ~= "boolean" then return false, "unknown" end
	local off = {}
	for k, v in pairs(old) do off[k] = v end
	off[kind] = not on
	local ok, why = ns.Config:Set(path, off)
	if not ok then return false, why end
	emit("SETTINGS_CHANGED", "notify")
	return true
end

-- The quiet hours (SPEC-13 §4, M9.4): account.settings.quiet = { on, from, to, instances }.
function Model.GetQuiet(key)
	local v = ns.Config and ns.Config:Get("account.settings.quiet." .. key)
	if v == nil then return defaultAt("account.settings.quiet." .. key) end
	return v
end

-- Saves one of them. Returns true, or false and the reason ("same": the window would start when it ends).
function Model.SetQuiet(key, value)
	if (key == "from" and value == Model.GetQuiet("to")) or (key == "to" and value == Model.GetQuiet("from")) then
		return false, "same"
	end
	local ok, why = ns.Config:Set("account.settings.quiet." .. key, value)
	if not ok then return false, why end
	emit("SETTINGS_CHANGED", "quiet")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Appearance (M6.14, docs/specs/ui-style.md §2): the look, saved per account; UI/Theme.lua repaints on CONFIG_CHANGED
---------------------------------------------------------------------------------------------------------------------
-- key -> { path, values (the allowed strings) | nil for a boolean }. The values come from Config (THEMES, FONT_SOURCES).
Model.LOOK = {
	theme = { path = "account.settings.theme", values = ns.Config and ns.Config.THEMES or { "nebula", "aurora", "accord" } },
	effects = { path = "account.settings.effects" },
	animations = { path = "account.settings.animations" },
	guildPanel = { path = "account.settings.guildPanel" },   -- the Accord tab opens the panel in the guild window (UI/GuildTab.lua)
	font = { path = "account.settings.font", values = ns.Config and ns.Config.FONT_SOURCES or { "addon", "game" } },
}
Model.LOOK_ORDER = { "theme", "effects", "animations", "guildPanel", "font" }

local function allowed(spec, value)
	if not spec.values then return type(value) == "boolean" end
	for _, v in ipairs(spec.values) do if v == value then return true end end
	return false
end

-- The saved look value; a value never saved or damaged is its default.
function Model.GetLook(key)
	local spec = Model.LOOK[key]
	if not spec then return nil end
	local v = ns.Config and ns.Config.db and ns.Config:Get(spec.path)
	if v == nil or not allowed(spec, v) then return defaultAt(spec.path) end
	return v
end

-- Saves a look value: Config emits CONFIG_CHANGED (the theme, the effects and the font repaint at once), then
-- SETTINGS_CHANGED(key) for the pages. Returns true, or false and the reason.
function Model.SetLook(key, value)
	local spec = Model.LOOK[key]
	if not spec then return false, "unknown" end
	if not allowed(spec, value) then return false, "bad value" end
	local ok, why = ns.Config:Set(spec.path, value)
	if not ok then return false, why end
	emit("SETTINGS_CHANGED", key)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Main character (Data/Accounts.lua)
---------------------------------------------------------------------------------------------------------------------
-- The characters the player may pick as main, the chosen one first-marked: { { guid, name, level, classID, isMain }, ... }.
function Model.MainChoices()
	local A = ns.Accounts
	local out = {}
	if not A then return out end
	local main = A:Main()
	for _, e in ipairs(A:OwnChars()) do
		out[#out + 1] = { guid = e.guid, name = e.name, level = e.level, classID = e.classID, isMain = e.guid == main }
	end
	return out
end

function Model.SetMain(guid)
	local A = ns.Accounts
	if not A then return false, "unavailable" end
	local ok, why = A:SetMain(guid)
	if ok then emit("SETTINGS_CHANGED", "main") end
	return ok, why
end

---------------------------------------------------------------------------------------------------------------------
-- Roster columns (UI/RosterModel.lua, saved per character)
---------------------------------------------------------------------------------------------------------------------
-- { { id, label, on, always }, ... } for the columns that exist now.
function Model.ColumnChoices()
	local RM = ns.RosterModel
	local view = ns.RosterView
	if not (RM and view and view.Model) then return {} end
	local model = view:Model()
	local out = {}
	for _, c in ipairs(RM.AvailableColumns()) do
		out[#out + 1] = { id = c.id, label = c.label, on = model:HasColumn(c.id), always = c.always == true }
	end
	return out
end

function Model.ToggleColumn(id)
	local view = ns.RosterView
	if not (view and view.Model) then return false end
	local model = view:Model()
	local def = ns.RosterModel and ns.RosterModel.COLUMN[id]
	if not def or def.always then return false end
	model:ToggleColumn(id)
	model:Save()
	if view.Changed then view:Changed(true) end
	emit("SETTINGS_CHANGED", "columns")
	return true
end

function Model.ResetColumns()
	local view = ns.RosterView
	if not (view and view.Model) then return false end
	local model = view:Model()
	model:SetColumns(model:DefaultColumns())
	model:Save()
	if view.Changed then view:Changed(true) end
	emit("SETTINGS_CHANGED", "columns")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Sizes of the saved data (SPEC-01 §4, SPEC-09 §5)
---------------------------------------------------------------------------------------------------------------------
-- A size as the page says it: "512 B", "12.3 KB", "1.2 MB".
function Model.FormatBytes(bytes)
	bytes = tonumber(bytes) or 0
	if bytes < 1024 then return ("%d B"):format(bytes) end
	if bytes < 1024 * 1024 then return ("%.1f KB"):format(bytes / 1024) end
	return ("%.1f MB"):format(bytes / 1024 / 1024)
end

-- The numbers behind the "Saved data" card: { account = bytes, char = bytes, guilds = number of guilds held, guild =
-- bytes of the current guild or nil, parts = { { name, bytes, records }, ... } }. `records` is the number of records of a
-- store set (the data sets of SPEC-03), nil for other tables. Estimates of the saved file, not measured on disk.
function Model.Sizes()
	local C = ns.Config
	local out = { account = 0, char = 0, guilds = 0, parts = {} }
	if not (C and C.db) then return out end
	out.account = C.EstimateSize(C.db.account or {})
	out.char = C.EstimateSize(C.db.char or {})
	for _ in pairs(C.db.account and C.db.account.guilds or {}) do out.guilds = out.guilds + 1 end
	local GK = ns.GuildKey
	if not GK then return out end
	local parts, total = GK:SizeParts()
	if not parts then return out end
	out.guild = total
	local data = GK:Data()
	local sets = data and data.store and data.store.sets
	for _, p in ipairs(parts) do
		if p.name == "store" and type(sets) == "table" then
			-- the store is the bulk of the data: one line per data set instead of one for the whole store
			for _, set in ipairs(ns.Store and ns.Store.SET_ORDER or {}) do
				local records = sets[set]
				if type(records) == "table" and ns.Store.IsActive(set) then
					local n = 0
					for _ in pairs(records) do n = n + 1 end
					out.parts[#out.parts + 1] = { name = set, bytes = C.EstimateSize(records), records = n }
				end
			end
		else
			out.parts[#out.parts + 1] = { name = p.name, bytes = p.bytes }
		end
	end
	table.sort(out.parts, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.name < b.name
	end)
	return out
end

-- Clears what the addon holds about the current guild (GuildKey:Clear keeps what only this computer knows: the notary's
-- salts, the account's likes memory, the bank money history and the notices already seen; the history of notices goes). Returns the bytes freed, or false and the reason.
function Model.ClearGuildData()
	local GK = ns.GuildKey
	if not GK then return false, "unavailable" end
	local freed, why = GK:Clear()
	if freed == false then return false, why end
	emit("SETTINGS_CHANGED", "clear")
	return freed
end

---------------------------------------------------------------------------------------------------------------------
-- The panel in the game's Settings window
---------------------------------------------------------------------------------------------------------------------
-- Registers a canvas category when the client has the API; `makeFrame(name)` is called only then and returns the canvas
-- frame. Never raises. Returns true, or false and why: "unavailable" (no Settings API) or "failed".
function Model.RegisterPanel(makeFrame, api)
	if Model.category then return true end
	api = api or (ns.Compat and ns.Compat.Resolve("Settings"))
	if type(api) ~= "table" or type(api.RegisterCanvasLayoutCategory) ~= "function"
		or type(api.RegisterAddOnCategory) ~= "function" then
		Model.panelStatus = "unavailable"
		return false, "unavailable"
	end
	local ok, category = pcall(function()
		local frame = makeFrame(Model.PANEL_NAME)
		local cat = api.RegisterCanvasLayoutCategory(frame, Model.PANEL_NAME)
		api.RegisterAddOnCategory(cat)
		return cat
	end)
	if not ok or not category then
		Model.panelStatus = "failed"
		return false, "failed"
	end
	Model.category, Model.api, Model.panelStatus = category, api, "registered"
	return true
end

-- Opens the game's Settings window on our panel. Returns false when there is none.
function Model.OpenPanel()
	local api, category = Model.api, Model.category
	if not (api and category and type(api.OpenToCategory) == "function") then return false end
	local id = category.GetID and category:GetID() or category.ID or category
	return pcall(api.OpenToCategory, id) and true or false
end

function Model.DebugLines()
	local parts = {}
	for _, o in ipairs(Model.OPTIONS) do
		parts[#parts + 1] = ("%s=%s%s"):format(o.key, tostring(Model.Get(o.key)), Model.IsDefault(o.key) and "" or " (changed)")
	end
	return { "Settings: " .. table.concat(parts, ", ") .. "; game panel: " .. tostring(Model.panelStatus or "not tried") }
end

if ns.addon then
	ns.addon.SettingsModel = Model
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Settings", function() return Model.DebugLines() end) end
end

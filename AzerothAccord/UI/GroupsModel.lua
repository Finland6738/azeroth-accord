-- GroupsModel: what the Groups view shows and does, without a frame (SPEC-13 §6.10, M9.7). Lua 5.1, tested offline.
--
--   List        Model.Filter / ToggleKind / SetFits / ToggleRole / SetActivity / SetSearch, KindChips, RoleChoices,
--               ActivityChoices, Rows, Text, Detail(id, t), Apply, Withdraw
--   Post        Model.ActivityList(kind), Defaults(kind, act), Values(rec), ReadForm(values), Submit(values, confirmed),
--               Update(values), Close()
--   My group    Model.Own(), ApplicantRows(), ApplicantText, ApplicantCount(), Accept(name), Decline(name)
--   Game finder Model.GameButton(), GameList(), GameRemove() (M9.8, Data/GameFinder.lua): only from the leader's click
-- Every action answers `true, text` or `false, text`: the text is what the view says under its buttons. Nothing here
-- sends or writes by itself: Data/Groups.lua does, and checks everything again.
local ADDON_NAME, ns = ...
ns = ns or {}
local Model = {}
ns.GroupsModel, ns.modules = Model, ns.modules or {}
ns.modules.GroupsModel = Model

local L = ns.L
local type, ipairs, pairs, tostring, tonumber, next = type, ipairs, pairs, tostring, tonumber, next
local floor, max, min = math.floor, math.max, math.min
local sort, concat = table.sort, table.concat

Model.KIND_ICON = { dungeon = "skull", raid = "crown", quest = "book", elite = "star", pvp = "sword", farm = "bag",
	prof = "gem", help = "info", other = "flag" }
Model.ROLE_ICON = { t = "shield", h = "heal", d = "sword" }
Model.DURATIONS = { 1800, 3600, 7200, 14400 }

-- What is not saved: the activity chosen and the text of the search box.
Model.session = { act = "", search = "" }

local function G() return ns.Groups end
local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function lower(s) return type(s) == "string" and s:lower() or "" end
local function escape(s) return ns.Contacts and ns.Contacts.Escape(s) or (tostring(s):gsub("|", "||")) end
local function instance(kind) return kind == "dungeon" or kind == "raid" end
-- The click that may have closed the guild listing also removes its private listing in the game's finder (LFG-05).
local function gameClose() if ns.GameFinder then ns.GameFinder:CloseWith() end end

function Model.KindText(kind) return L["GRP_KIND_" .. tostring(kind):upper()] end
function Model.RoleText(role) return L["GRP_ROLE_" .. tostring(role):upper()] end

local function icon(name)
	return ns.Assets and ns.Assets.IconText(name, 14) or ""
end

-- The roles still wanted as icons with a number: "[shield]1 [heal]1 [sword]2".
function Model.RolesText(need)
	local out = {}
	for _, r in ipairs(G().ROLES) do
		local n = need and need[r] or 0
		if n > 0 then out[#out + 1] = icon(Model.ROLE_ICON[r]) .. n end
	end
	return concat(out, "  ")
end

-- The same in words: "Tank 1, Healer 1".
function Model.RolesWords(need)
	local out = {}
	for _, r in ipairs(G().ROLES) do
		local n = need and need[r] or 0
		if n > 0 then out[#out + 1] = Model.RoleText(r) .. " " .. n end
	end
	return concat(out, ", ")
end

function Model.LevelsText(rec)
	if rec.min == rec.max then return tostring(rec.min) end
	return rec.min .. "-" .. rec.max
end

-- "45 min", "1 h 20 min": the time left, rounded up to the minute.
function Model.LeftText(seconds)
	local m = floor((max(0, seconds) + 59) / 60)
	if m < 60 then return L["GRP_MINUTES"]:format(m) end
	return L["GRP_HOURS"]:format(floor(m / 60), m % 60)
end

local ERRORS = { off = true, kind = true, act = true, level = true, size = true, need = true, have = true, duration = true,
	invalid = true, rev = true, missing = true, status = true, own = true, offline = true, role = true, wait = true,
	limit = true, applicant = true, leader = true, full = true, raid = true, invite = true, mylevel = true }

function Model.ErrorText(why)
	if ERRORS[why] then return L["GRP_ERR_" .. why:upper()] end
	return L["GRP_ERR_OTHER"]:format(tostring(why))
end

---------------------------------------------------------------------------------------------------------------------
-- The list and its filters
---------------------------------------------------------------------------------------------------------------------
function Model.Filter()
	local f = G():Filter()
	f.act, f.search = Model.session.act, Model.session.search
	return f
end

local function save(change)
	local f = G():Filter()
	change(f)
	G():SetFilter(f)
	return f
end

-- A kind chip: "all" clears the choice, another one is added or taken away.
function Model.ToggleKind(kind)
	return save(function(f)
		if kind == "all" then f.kinds = {} else f.kinds[kind] = (not f.kinds[kind]) or nil end
	end)
end

function Model.SetFits(on) return save(function(f) f.fits = on and true or false end) end
function Model.ToggleRole(role) return save(function(f) f.roles[role] = (not f.roles[role]) or nil end) end
function Model.SetActivity(id) Model.session.act = id or "" end
function Model.SetSearch(text) Model.session.search = lower(text) end

function Model.ResetSession() Model.session.act, Model.session.search = "", "" end

function Model.KindChips()
	local f = G():Filter()
	local out = { { id = "all", text = L["GRP_ALL"], on = next(f.kinds) == nil } }
	for _, kind in ipairs(G().KINDS) do
		out[#out + 1] = { id = kind, text = Model.KindText(kind), on = f.kinds[kind] == true }
	end
	return out
end

-- The role chips: only the roles the player's class can take.
function Model.RoleChoices()
	local f = G():Filter()
	local out = {}
	for _, r in ipairs(G().ClassRoles()) do out[#out + 1] = { id = r, text = Model.RoleText(r), on = f.roles[r] == true } end
	return out
end

local function activityID(rec) return rec.kind .. ":" .. tostring(rec.act) end

-- "All activities" and one choice per activity among the listings held.
function Model.ActivityChoices()
	local seen, out = {}, {}
	for _, e in ipairs(G():List()) do
		local id = activityID(e.rec)
		if not seen[id] then
			seen[id] = true
			out[#out + 1] = { id = id, text = escape(G().ActivityName(e.rec)) }
		end
	end
	if Model.session.act ~= "" and not seen[Model.session.act] then Model.session.act = "" end
	sort(out, function(a, b)
		if a.text ~= b.text then return a.text < b.text end
		return a.id < b.id
	end)
	table.insert(out, 1, { id = "", text = L["GRP_ACT_ALL"] })
	return out
end

local function leaderName(guid)
	if guid == compat().Player.GUID() then return compat().Player.Name() or "?" end
	return G().ShortName(guid)
end

local function describe(rec, status)
	local me = compat().Player.GUID()
	return { id = rec.id, rec = rec, status = status, name = G().ActivityName(rec), leader = leaderName(rec.author),
		mine = rec.author == me, app = G():Mine(rec.id) }
end

-- Whether a row passes the filters (`level`: the player's). The role filter keeps the listings that still need one of
-- the roles chosen; the search looks at the activity, the leader, the note and the meeting point.
function Model.Matches(row, f, level)
	local rec = row.rec
	if next(f.kinds) and not f.kinds[rec.kind] then return false end
	if f.act and f.act ~= "" and activityID(rec) ~= f.act then return false end
	if f.fits and level and not row.mine and not G().LevelFits(rec, level) then return false end
	if next(f.roles) then
		local wanted = false
		for r in pairs(f.roles) do
			if (rec.need[r] or 0) > 0 then wanted = true end
		end
		if not wanted then return false end
	end
	if f.search and f.search ~= "" then
		local hay = lower(concat({ row.name, row.leader, rec.note or "", rec.meet or "" }, "\n"))
		if not hay:find(f.search, 1, true) then return false end
	end
	return true
end

-- The listings of the table, the newest first.
function Model.Rows()
	local f, level = Model.Filter(), compat().Player.Level()
	local out = {}
	for _, e in ipairs(G():List()) do
		local row = describe(e.rec, e.status)
		if Model.Matches(row, f, level) then out[#out + 1] = row end
	end
	return out
end

-- The state of the player's application to a listing, or nil.
function Model.AppText(app)
	if not app then return nil end
	if app.state == "waiting" then return L["GRP_APP_WAITING"]:format(Model.RoleText(app.r)) end
	if app.state == "accepted" then return L["GRP_APP_ACCEPTED"] end
	if app.state == "declined" then return L["GRP_APP_DECLINED"] end
	return L["GRP_APP_CLOSED"]
end

function Model.StatusText(row)
	local app = Model.AppText(row.app)
	if app then return app end
	if row.status ~= "open" then return L["GRP_STATUS_" .. row.status:upper()] end
	return row.mine and L["GRP_YOURS"] or ""
end

function Model.Text(row, column, t)
	local rec = row.rec
	if column == "kind" then return icon(Model.KIND_ICON[rec.kind]) .. " " .. Model.KindText(rec.kind) end
	if column == "activity" then return escape(row.name) end
	if column == "levels" then return Model.LevelsText(rec) end
	if column == "roles" then return row.status == "open" and Model.RolesText(rec.need) or "" end
	if column == "size" then return rec.have .. "/" .. rec.size end
	if column == "leader" then return escape(row.leader) end
	if column == "age" then return ns.Provenance.AgeText(max(0, (t or now()) - rec.created)) end
	if column == "left" then return row.status == "open" and Model.LeftText(rec.ends - (t or now())) or "" end
	if column == "state" then return Model.StatusText(row) end
	return ""
end

-- The lines of a row's tooltip.
function Model.TipLines(row, t)
	local rec = row.rec
	local tip = { escape(row.name), { text = Model.KindText(rec.kind) .. " - " .. Model.LevelsText(rec), token = "text-3" } }
	if row.status == "open" then tip[#tip + 1] = L["GRP_NEEDS"]:format(Model.RolesWords(rec.need)) end
	if rec.note then tip[#tip + 1] = escape(rec.note) end
	if rec.meet then tip[#tip + 1] = L["GRP_MEET_LINE"]:format(escape(rec.meet)) end
	tip[#tip + 1] = { text = L["GRP_LED_BY"]:format(escape(row.leader), Model.Text(row, "age", t)), token = "text-3" }
	local state = Model.StatusText(row)
	if state ~= "" then tip[#tip + 1] = { text = state, token = "accent-text" } end
	return tip
end

-- The panel under the table for one listing: nil when it is gone, else { row, title, info, note, state, own, roles =
-- { { id, text } } (the needed ones), preselect, canApply, canWithdraw, hint (why Apply is not offered) }.
function Model.Detail(id)
	local rec = id and G():Get(id)
	if not rec or G().Expired(rec, now()) then return nil end
	local row = describe(rec, G():Status(rec))
	local d = { row = row, own = row.mine, roles = {}, canApply = false, canWithdraw = false }
	d.title = L["GRP_DETAIL_TITLE"]:format(escape(row.name), escape(row.leader))
	local info = { Model.KindText(rec.kind), L["GRP_LEVELS_LINE"]:format(Model.LevelsText(rec)), rec.have .. "/" .. rec.size }
	if row.status == "open" then info[#info + 1] = L["GRP_NEEDS"]:format(Model.RolesWords(rec.need)) end
	d.info = concat(info, " - ")
	local note = {}
	if rec.note then note[#note + 1] = escape(rec.note) end
	if rec.meet then note[#note + 1] = L["GRP_MEET_LINE"]:format(escape(rec.meet)) end
	d.note = concat(note, " - ")
	d.state = Model.StatusText(row)
	d.canWithdraw = row.app ~= nil and row.app.state == "waiting"
	if row.mine or d.canWithdraw or row.status ~= "open" or (row.app and row.app.state == "accepted") then return d end
	if ns.Store:SameAccount(compat().Player.GUID(), rec.author) then
		d.hint = L["GRP_ERR_OWN"]
	elseif not G().LevelFits(rec, compat().Player.Level()) then
		d.hint = L["GRP_ERR_MYLEVEL"]
	else
		for _, r in ipairs(G().ROLES) do
			if (rec.need[r] or 0) > 0 then d.roles[#d.roles + 1] = { id = r, text = Model.RoleText(r) } end
		end
		d.preselect = G().PreferredRole(rec)
		d.canApply = #d.roles > 0
	end
	return d
end

function Model.Apply(id, role, comment)
	if not role then return false, L["GRP_PICK_ROLE"] end
	local ok, why = G():Apply(id, role, comment)
	if ok then return true, L["GRP_APPLIED"] end
	return false, Model.ErrorText(why == "level" and "mylevel" or why)
end

function Model.Withdraw(id)
	local ok, why = G():Withdraw(id)
	if ok then return true, L["GRP_WITHDRAWN"] end
	return false, Model.ErrorText(why)
end

---------------------------------------------------------------------------------------------------------------------
-- The form
---------------------------------------------------------------------------------------------------------------------
-- The instances of a kind for the Select: the ones for the player's level first, then the others, each by level.
function Model.ActivityList(kind)
	local out, others = {}, {}
	if not (instance(kind) and ns.GroupActivities) then return out end
	local level = compat().Player.Level()
	for _, row in ipairs(ns.GroupActivities:List(kind)) do
		local text = L["GRP_ACT_CHOICE"]:format(escape(ns.GroupActivities:Name(row.mapID)), Model.LevelsText(row))
		local into = (level and level >= row.min and level <= row.max) and out or others
		into[#into + 1] = { id = row.mapID, text = text }
	end
	for _, c in ipairs(others) do out[#out + 1] = c end
	return out
end

-- The values a new listing of `kind` starts with (`act`: the instance, or nil), as the form holds them: texts.
function Model.Defaults(kind, act)
	local top = compat().Player.MaxLevel()
	local v = { kind = kind, act = "", min = "1", max = tostring(top), size = "5", have = "", t = "0", h = "0", d = "1",
		note = "", meet = "", duration = G().DURATION }
	if instance(kind) then
		local list = Model.ActivityList(kind)
		local id = act or (list[1] and list[1].id)
		local row = id and ns.GroupActivities:Get(id)
		v.act = row and id or nil
		if row then
			v.min, v.max = tostring(min(row.min, top)), tostring(min(row.max, top))
			v.size = tostring(row.size)
		end
		-- every free place of the instance, shared among the roles (the leader holds one)
		v.t, v.h, v.d = "1", "1", "2"
		if kind == "raid" and row then
			local healers = max(1, floor(row.size / 5))
			v.t, v.h, v.d = "2", tostring(healers), tostring(max(0, row.size - 3 - healers))
		end
	elseif kind == "help" then
		local state, zone = compat().Call("GetRealZoneText")
		v.act = state == compat().AVAILABLE and G().CleanText(zone, G().MAX_ACT) or ""
		v.size = "2"
	end
	return v
end

-- The values of the own listing, to change it.
function Model.Values(rec)
	return { kind = rec.kind, act = rec.act, min = tostring(rec.min), max = tostring(rec.max), size = tostring(rec.size),
		have = tostring(rec.have), t = tostring(rec.need.t or 0), h = tostring(rec.need.h or 0), d = tostring(rec.need.d or 0),
		note = rec.note or "", meet = rec.meet or "", duration = rec.ends - rec.created }
end

-- A whole number as typed: nil for an empty box, false for anything else that is not one.
function Model.Number(text)
	text = (tostring(text or ""):gsub("%s", ""))
	if text == "" then return nil end
	if not text:find("^%d%d?%d?%d?$") then return false end
	return tonumber(text)
end

-- The spec Groups:Post takes, from the values of the form; or nil and the field that is wrong.
function Model.ReadForm(v)
	local spec = { kind = v.kind, act = v.act, note = v.note, meet = v.meet, duration = v.duration, need = {} }
	for _, f in ipairs({ { "min", "level" }, { "max", "level" }, { "size", "size" }, { "have", "have" } }) do
		local n = Model.Number(v[f[1]])
		if n == false then return nil, f[2] end
		spec[f[1]] = n
	end
	for _, r in ipairs(G().ROLES) do
		local n = Model.Number(v[r])
		if n == false then return nil, "need" end
		spec.need[r] = n or 0
	end
	if instance(v.kind) then
		if type(v.act) ~= "number" then return nil, "act" end
	elseif v.kind ~= "help" and G().CleanText(v.act, G().MAX_ACT) == "" then
		return nil, "act"
	end
	return spec
end

-- The player's open listing, or nil.
function Model.Own()
	local me = compat().Player.GUID()
	for _, e in ipairs(G():List()) do
		if e.rec.author == me and e.status == "open" then return e.rec end
	end
	return nil
end

-- Post. With an open listing the first click only asks (`false, text, true`): the second one, `confirmed`, closes it
-- and posts the new one.
function Model.Submit(values, confirmed)
	local spec, bad = Model.ReadForm(values)
	if not spec then return false, Model.ErrorText(bad) end
	if Model.Own() and not confirmed then return false, L["GRP_CONFIRM_REPLACE"], true end
	local rec, why = G():Post(spec)
	gameClose()
	if not rec then return false, Model.ErrorText(why) end
	return true, L["GRP_POSTED"]
end

-- Update: the roles, the players already there, the levels, the note and the meeting point of the own listing. With
-- `original` (the values the form was filled with) only what the leader changed is sent, so an Accept made meanwhile,
-- also one still waiting to be written, is not undone.
function Model.Update(values, original)
	local own = Model.Own()
	if not own then return false, Model.ErrorText("missing") end
	local spec, bad = Model.ReadForm(values)
	if not spec then return false, Model.ErrorText(bad) end
	local function touched(key) return original == nil or values[key] ~= original[key] end
	local changes = {}
	if touched("t") or touched("h") or touched("d") then changes.need = spec.need end
	for _, key in ipairs({ "have", "min", "max", "note", "meet" }) do
		if touched(key) then changes[key] = spec[key] end
	end
	local ok, why = G():Update(own.id, changes)
	gameClose()
	if not ok then return false, Model.ErrorText(why) end
	return true, L["GRP_UPDATED"]
end

function Model.Close()
	local own = Model.Own()
	if not own then return false, Model.ErrorText("missing") end
	local rec, why = G():Close(own.id)
	gameClose()
	if not rec then return false, Model.ErrorText(why) end
	return true, L["GRP_CLOSED_DONE"]
end

---------------------------------------------------------------------------------------------------------------------
-- The game's Group Finder, privately (SPEC-13 §7, M9.8)
---------------------------------------------------------------------------------------------------------------------
-- The button of My group: { action = "GameList" | "GameRemove", text, tip = { lines } }, or nil when nothing is offered
-- (LFG-07: without the capability no button and no text).
function Model.GameButton()
	local GF = ns.GameFinder
	if not (GF and GF.Enabled()) then return nil end
	if GF:CanRemove() then
		return { action = "GameRemove", text = L["GRP_GAME_REMOVE"], enabled = not compat().InCombat(),
			tip = { L["GRP_GAME_REMOVE"], L["GRP_GAME_REMOVE_TIP"] } }
	end
	local own = Model.Own()
	if own and GF:Offer(own) then
		return { action = "GameList", text = L["GRP_GAME_LIST"], enabled = true,
			tip = { L["GRP_GAME_LIST"], L["GRP_GAME_TIP_PRIVATE"], L["GRP_GAME_TIP_FRIENDS"] } }
	end
	return nil
end

local function gameError(why)
	if why == "combat" then return L["GRP_GAME_ERR_COMBAT"] end
	return L["GRP_GAME_ERR"]:format(tostring(why))
end

-- The leader's click on "Also list in the game's finder" (LFG-02).
function Model.GameList()
	local own = Model.Own()
	if not own then return false, Model.ErrorText("missing") end
	local ok, why = ns.GameFinder:List(own.id)
	if not ok then return false, gameError(why) end
	return true, L["GRP_GAME_LISTED"]
end

-- The leader's click on "Remove from the game's finder".
function Model.GameRemove()
	local ok, why = ns.GameFinder:Remove()
	if not ok then return false, gameError(why) end
	return true, L["GRP_GAME_REMOVED"]
end

---------------------------------------------------------------------------------------------------------------------
-- The leader's applicants
---------------------------------------------------------------------------------------------------------------------
-- The client's name of a class ("Mage"), or "".
local function className(file)
	for _, c in ipairs(file and compat().Classes() or {}) do
		if c.file == file then return c.name or "" end
	end
	return ""
end

function Model.ApplicantRows()
	local own = Model.Own()
	if not own then return {} end
	local out = {}
	for _, a in ipairs(G():Applicants(own.id)) do
		local e = ns.Roster and a.guid and ns.Roster:ByGUID(a.guid)
		out[#out + 1] = { id = own.id, applicant = a.name, name = G().ShortName(a.guid, a.name), classFile = e and e.classFile,
			className = className(e and e.classFile), level = a.l or (e and e.level), role = a.r, comment = a.c, at = a.at }
	end
	return out
end

function Model.ApplicantCount()
	local own = Model.Own()
	return own and #G():Applicants(own.id) or 0
end

function Model.ApplicantText(a, column, t)
	if column == "name" then return escape(a.name) end
	if column == "class" then return a.className or "" end
	if column == "level" then return a.level and tostring(a.level) or "" end
	if column == "role" then return icon(Model.ROLE_ICON[a.role]) .. " " .. Model.RoleText(a.role) end
	if column == "comment" then return a.comment and escape(a.comment) or "" end
	if column == "age" then return ns.Provenance.AgeText(max(0, (t or now()) - a.at)) end
	return ""
end

-- Accept runs in the leader's click (GRP-07): Data/Groups.lua invites there.
function Model.Accept(name)
	local own = Model.Own()
	if not own then return false, Model.ErrorText("missing") end
	local ok, why = G():Accept(own.id, name)
	gameClose()
	if ok then return true, L["GRP_ACCEPTED_DONE"] end
	return false, Model.ErrorText(why)
end

function Model.Decline(name)
	local own = Model.Own()
	if not own then return false, Model.ErrorText("missing") end
	local ok, why = G():Decline(own.id, name)
	if ok then return true, L["GRP_DECLINED_DONE"] end
	return false, Model.ErrorText(why)
end

if ns.addon then
	ns.addon.GroupsModel = Model
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() Model.ResetSession() end) end
end

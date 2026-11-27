-- "Play with someone new" (SPEC-07 SOC-20). Lua 5.1.
-- A mode of the Reputation view for every member: guildmates who are ONLINE now, of a compatible level (at most
-- LEVEL_GAP levels apart), with whom the player played less than NEW_MINUTES in the last 30 days (the account graph of the
-- social index: all characters of both players count), one row per player (their character that is online, the closest
-- in level). The fewest minutes first, until a header sorts the table (ui-style §9.9). Each row has Whisper (opens the chat box with "/w Name": the player writes and sends)
-- and Invite (C_PartyInfo.InviteUnit: a click of the player). The addon never sends anything by itself.
-- Suggest.List(opts) is a plain function of the roster and the social result (tested offline).
local ADDON_NAME, ns = ...
ns = ns or {}
local Suggest = {}
ns.Suggest, ns.modules = Suggest, ns.modules or {}
ns.modules.Suggest = Suggest

local L, Widgets = ns.L, ns.Widgets
local type, ipairs, pairs, tostring, abs = type, ipairs, pairs, tostring, math.abs

Suggest.LEVEL_GAP = 5
Suggest.NEW_MINUTES = 30
Suggest.LIMIT = 12
Suggest.ROW_HEIGHT = 36

-- The suggestions: { guid, name, classFile, level, zone, minutes } sorted by minutes together, then level closeness, then
-- name. opts.limit (default LIMIT).
function Suggest.List(opts)
	opts = opts or {}
	local R, C, A, S = ns.Roster, ns.Compat, ns.Accounts, ns.Social
	if not (R and C) then return {} end
	local me = C.Player.GUID()
	local myLevel = C.Player.Level() or 0
	local myKey = A and me and A:AccountKey(me) or me
	local best = {}
	for _, e in ipairs(R:Members()) do
		if type(e.guid) == "string" and e.online and not e.notInGuild and not e.isSelf and e.guid ~= me then
			local key = A and A:AccountKey(e.guid) or e.guid
			if key ~= myKey and e.level and abs(e.level - myLevel) <= Suggest.LEVEL_GAP then
				local minutes = S and me and S:MinutesBetween(me, e.guid) or 0
				if minutes < Suggest.NEW_MINUTES then
					local old = best[key]
					if not old or abs(e.level - myLevel) < abs(old.level - myLevel) then
						best[key] = { guid = e.guid, name = e.short or e.name or "?", classFile = e.classFile, level = e.level, zone = e.zone,
							minutes = minutes }
					end
				end
			end
		end
	end
	local out = {}
	for _, s in pairs(best) do out[#out + 1] = s end
	table.sort(out, function(a, b)
		if a.minutes ~= b.minutes then return a.minutes < b.minutes end
		local da, db = abs(a.level - myLevel), abs(b.level - myLevel)
		if da ~= db then return da < db end
		if a.name ~= b.name then return a.name < b.name end
		return a.guid < b.guid
	end)
	local limit = opts.limit or Suggest.LIMIT
	for i = #out, limit + 1, -1 do out[i] = nil end
	return out
end

-- The roster name to whisper or invite ("Name" on the player's realm, else "Name-Realm").
local function targetName(guid)
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	return e and (e.name or e.short) or nil
end

function Suggest:Whisper(guid)
	local name = targetName(guid)
	return name ~= nil and ns.Compat.Chat.OpenWhisper(name, "") or false
end

function Suggest:Invite(guid)
	local name = targetName(guid)
	local ok = name ~= nil and ns.Compat.Group.Invite(name) or false
	if ns.addon then
		local e = ns.Roster and ns.Roster:ByGUID(guid)
		ns.addon:Print((ok and L["NEW_INVITED"] or L["NEW_INVITE_FAILED"]):format(e and (e.short or e.name) or "?"))
	end
	return ok
end

---------------------------------------------------------------------------------------------------------------------
-- The mode of the Reputation view
---------------------------------------------------------------------------------------------------------------------
local mode = {}

function Suggest.MinutesText(minutes)
	if not minutes or minutes <= 0 then return L["NEW_NEVER"] end
	return L["NEW_MINUTES"]:format(minutes)
end

local function columns(f)
	local function muted() return "text-3" end
	return {
		{ id = "name", title = L["COL_NAME"], flex = 1.4, value = function(s) return s.name end,
			render = function(cell, s, row) ns.ReputationView.RenderName(f.table, 1, cell, s, row) end },
		{ id = "level", title = L["COL_LEVEL"], width = 56, align = "RIGHT", mono = true,
			value = function(s) return s.level end, text = function(s) return tostring(s.level) end },
		{ id = "zone", title = L["COL_ZONE"], flex = 1.2, text = function(s) return s.zone or "?" end, token = muted },
		{ id = "together", title = L["NEW_COL_TOGETHER"], flex = 1, value = function(s) return s.minutes or 0 end,
			text = function(s) return Suggest.MinutesText(s.minutes) end, token = muted },
		{ id = "actions", title = "", width = 200, sortable = false, text = function() return "" end },
	}
end

local function rowSetup(row)
	row.mark = Widgets.ClassMark(row, 8)
	row.invite = Widgets.Button(row, { text = L["NEW_INVITE"], style = "tonal", width = 90, height = Widgets.HEIGHT.small,
		onClick = function(b) Suggest:Invite(b:GetParent().data.guid) end })
	row.invite:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	row.invite:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.whisper = Widgets.Button(row, { text = L["NEW_WHISPER"], style = "outlined", width = 90, height = Widgets.HEIGHT.small,
		onClick = function(b) Suggest:Whisper(b:GetParent().data.guid) end })
	row.whisper:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	row.whisper:SetPoint("RIGHT", row.invite, "LEFT", -8, 0)
end

function mode.build(f)
	Suggest.frame = f
	f.explain = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.explain:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
	f.explain:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.explain:SetText(L["NEW_EXPLAIN"]:format(Suggest.LEVEL_GAP, Suggest.NEW_MINUTES))
	f.table = Widgets.DataTable(f, columns(f), { rowHeight = Suggest.ROW_HEIGHT, pool = Suggest.LIMIT, maxPool = 30,
		memory = "reputation.new", sort = { id = "together" }, emptyText = L["NEW_NONE"], rowSetup = rowSetup })
	f.table:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -40)
	f.table:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

function mode.refresh(f)
	local list = Suggest.List()
	Suggest.shown = list
	f.table:SetData(list, true)
end

if ns.ReputationView then
	ns.ReputationView.AddMode("new", { label = L["REP_MODE_NEW"], order = 40, build = mode.build, refresh = mode.refresh })
end

if ns.addon then ns.addon.Suggest = Suggest end

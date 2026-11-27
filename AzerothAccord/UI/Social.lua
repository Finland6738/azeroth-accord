-- The social index in the interface (SPEC-07 SOC-04, SOC-05, SOC-12; SPEC-10 Q3). Lua 5.1.
--
--   Member card   a "Social index" section: the index out of 100 (with a tooltip that explains what it measures), the
--                 effective partners out of the active players, the different partners, the time with guildmates, and the
--                 five players played with most with their share (SOC-05); "not enough data" under 5 hours (SOC-04).
--   Roster        the Social column (the index, a dash under 5 hours), only for those who may see the others' index.
--   Reputation    a "Social" mode: the player's own index with the same breakdown, and for those who may see the others a
--                 table of every player, by index until a header sorts it (ui-style §9.9).
-- Who sees what is Social:CanSee / CanSeeOthers (Data/Social.lua): the SPEC-10 Q3 proposal, everyone their own, officers
-- and the Guild Master everyone's, until the owner answers Q3.
--
-- Describe(guid) is a plain function (tested offline): { title, lines = { { text, muted, tip } } } or nil.
local ADDON_NAME, ns = ...
ns = ns or {}
local UI = {}
ns.SocialUI, ns.modules = UI, ns.modules or {}
ns.modules.SocialUI = UI

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, floor, max, min = type, ipairs, pairs, tostring, math.floor, math.max, math.min

UI.ROW_HEIGHT = 32
UI.LIST_MAX = 400

local function hours(minutes)
	return L["SOC_HOURS"]:format(floor((minutes or 0) / 6 + 0.5) / 10)
end

-- The name to show for an account key: its main (or the character itself) when known, else "a former member".
function UI.NameOf(key)
	local A, R = ns.Accounts, ns.Roster
	local main = A and A:MainOf(key)
	if main and main.name then return main.name, main.classFile end
	local e = R and R:ByGUID(key)
	if e then return e.short or e.name or "?", e.classFile end
	return L["SOC_FORMER"], nil
end

function UI.Tip()
	return { L["SOC_TIP_TITLE"], L["SOC_TIP_1"], L["SOC_TIP_2"], L["SOC_TIP_3"] }
end

-- The lines of the social data of `guid`, or nil when this player may not see it (SPEC-10 Q3).
function UI.Describe(guid)
	local S = ns.Social
	if not (S and type(guid) == "string" and S:CanSee(guid)) then return nil end
	local tip = UI.Tip()
	local lines = {}
	local r = S:Result()
	if not r then
		lines[1] = { text = L["SOC_COMPUTING"], muted = true, tip = tip }
		return { title = L["SOC_SECTION"], lines = lines }
	end
	local e = S:ForGUID(guid)
	if not e then
		lines[1] = { text = L["SOC_NO_DATA"], muted = true, tip = tip }
		return { title = L["SOC_SECTION"], lines = lines }
	end
	if e.index then
		lines[1] = { text = L["SOC_INDEX"]:format(e.index), tip = tip }
	else
		lines[1] = { text = L["SOC_NOT_ENOUGH"]:format(hours(e.minutes)), muted = true, tip = tip }
	end
	lines[#lines + 1] = { text = L["SOC_EFFECTIVE"]:format(e.effective, r.active), tip = tip }
	lines[#lines + 1] = { text = L["SOC_DISTINCT"]:format(e.partners) }
	lines[#lines + 1] = { text = L["SOC_MINUTES"]:format(hours(e.minutes)), muted = true }
	if #e.top > 0 then
		lines[#lines + 1] = { text = L["SOC_TOP"] }
		for _, p in ipairs(e.top) do
			lines[#lines + 1] = { text = L["SOC_TOP_LINE"]:format(UI.NameOf(p.key), floor(p.share * 100 + 0.5)), muted = true }
		end
	end
	return { title = L["SOC_SECTION"], lines = lines }
end

-- The card section (order 6, after the likes).
function UI.CardSection(entry)
	if type(entry) ~= "table" or entry.notInGuild then return nil end
	local d = UI.Describe(entry.guid)
	if not d then return nil end
	return { id = "social", title = d.title, lines = d.lines }
end

-- Every account with social data, by index (accounts without enough data last): { key, name, classFile, index,
-- effective, partners, minutes }. Empty for a player who may not see the others.
function UI.Rows()
	local S = ns.Social
	local out = {}
	if not (S and S:CanSeeOthers()) then return out end
	local r = S:Result()
	if not r then return out end
	for key, e in pairs(r.accounts) do
		local name, classFile = UI.NameOf(key)
		out[#out + 1] = { key = key, name = name, classFile = classFile, index = e.index, effective = e.effective, partners = e.partners,
			minutes = e.minutes }
	end
	table.sort(out, function(a, b)
		if (a.index ~= nil) ~= (b.index ~= nil) then return a.index ~= nil end
		if a.index and a.index ~= b.index then return a.index > b.index end
		if a.effective ~= b.effective then return a.effective > b.effective end
		return a.key < b.key
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The "Social" mode of the Reputation view
---------------------------------------------------------------------------------------------------------------------
local mode = {}

local function paintLine(fs, l)
	fs:SetFontObject(Theme.Font(l.heading and "H2" or "Body"))
	Theme.Text(fs, l.heading and "text-1" or l.muted and "text-3" or "text-2")
end

local function playerTable()
	local function mono(id, key, width)
		return { id = id, title = L[key], width = width, align = "RIGHT", mono = true }
	end
	return {
		columns = {
			{ id = "name", title = L["REP_COL_NAME"], flex = 1.4, render = function(cell, l)
				cell:SetText(l.cells.name)
				Widgets.PaintName(cell, l.classFile)
			end },
			mono("index", "SOC_COL_INDEX", 80), mono("effective", "SOC_COL_EFFECTIVE", 90),
			mono("partners", "SOC_COL_PARTNERS", 90), mono("time", "SOC_COL_TIME", 120),
		},
		memory = "reputation.social",
		onRowClick = function(l) if ns.ReputationView then ns.ReputationView:OpenCard({ guid = l.key }) end end,
		rowSetup = function(row)
			Widgets.Tooltip.Attach(row, function(r) return r.data and r.data.tip or nil end, "RIGHT")
		end,
	}
end

function mode.build(f)
	f.card = Widgets.Card(f, {})
	f.card:SetAllPoints(f)
	f.sheet = Widgets.Sheet(f.card, { rowHeight = UI.ROW_HEIGHT, defaultRows = 20, paint = paintLine,
		tables = { social = playerTable() } })
	f.sheet:SetPoint("TOPLEFT", f.card, "TOPLEFT", 20, -16)
	f.sheet:SetPoint("BOTTOMRIGHT", f.card, "BOTTOMRIGHT", -20, 12)
	UI.frame = f
end

-- The lines of the mode: the own section, then the table of everyone (officers).
function UI.ModeLines()
	local out = {}
	local me = ns.Compat and ns.Compat.Player.GUID()
	out[#out + 1] = { text = L["SOC_YOURS"], heading = true }
	local own = me and UI.Describe(me)
	for _, l in ipairs(own and own.lines or {}) do out[#out + 1] = l end
	local rows = UI.Rows()
	if ns.Social and ns.Social:CanSeeOthers() then
		out[#out + 1] = { text = " " }
		out[#out + 1] = { text = L["SOC_LIST_TITLE"], heading = true }
		out[#out + 1] = { text = L["SOC_LIST_NOTE"], muted = true }
		for i, r in ipairs(rows) do
			if i > UI.LIST_MAX then break end
			out[#out + 1] = { table = "social", text = r.name, classFile = r.classFile, key = r.key, tip = UI.Tip(),
				-- under the 5 hours there is no index (SOC-04): a dash, sorted last
				cells = { name = r.name, index = r.index and tostring(r.index) or "-",
					effective = r.index and ("%.1f"):format(r.effective) or "-",
					partners = r.index and tostring(r.partners) or "-", time = hours(r.minutes) },
				keys = { index = r.index or "", effective = r.index and r.effective or "",
					partners = r.index and r.partners or "", time = r.minutes or 0 } }
		end
	else
		out[#out + 1] = { text = " " }
		out[#out + 1] = { text = L["SOC_OWN_ONLY"], muted = true }
	end
	return out
end

function mode.refresh(f)
	local list = UI.ModeLines()
	UI.shown = list
	f.sheet:SetLines(list)
end

function UI:Scroll(delta)
	local f = self.frame
	return f ~= nil and f.sheet:Scroll(delta)
end

if ns.ReputationView then
	ns.ReputationView.AddMode("social", { label = L["REP_MODE_SOCIAL"], order = 20, build = mode.build, refresh = mode.refresh,
		available = function() return ns.Social ~= nil end })
end
if ns.MemberCard then ns.MemberCard.AddSection("social", 6, UI.CardSection) end

if ns.addon then
	ns.addon.SocialUI = UI
	if ns.Bus then
		ns.Bus:On("SOCIAL_UPDATED", function()
			if ns.MemberCard then ns.MemberCard:Refresh() end
			if ns.ReputationView then ns.ReputationView:Changed() end
			local R = ns.RosterView
			if R and R.model then R.model:Invalidate() end
			if R and R.frame and R.frame:IsVisible() then R:Changed() end
		end)
	end
end

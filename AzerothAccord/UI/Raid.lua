-- Raid view: the guild's sources for the raid and loot data, and what FDCP publishes when the officers chose it (M11.7;
-- M10 integration rules; ADR 0022). Lua 5.1.
--
-- At the top, the source of the season roster (Data/Integrations.lua): "Season roster" (Accord | FDCP), a
-- Widgets.Segmented that only officers can change (members see it locked); under it the guild's loot addon, which is
-- chosen on the handbook's loot page (M11.6): "Loot page" opens it, or, while that page cannot be read (never written,
-- deleted, or still a template for a member), shows its fixed part (UI/LootPage.lua) here in place of the list. "Open
-- FDCP" while FDCP is loaded on this client (level 0 or 1). Below, a list of lines, read only from FDCP's public API
-- (Data/FDCP.lua):
--   * FDCP's state: version and where its data comes from (an officer's ledger, or the table an officer sent to a member),
--     or why there is nothing (FDCP missing, switched off, an API version Accord does not know, not ready, no data yet);
--   * Season roster: the season and its pool, one line per main (class, role, MS1, MS2, OS, trial or inactive); a member's
--     client has no MS2 or OS, and the view says so instead of showing them empty;
--   * Lineup and bench: the open night of FDCP (raid and bench names only); a member's client has none, and the view says
--     the lineup is on officers' clients;
--   * Loot: the player's own credits and place; FDCP's rules are on the handbook's loot page (M11.6), beside its text.
--     View.RulesLines draws them there.
--   * Raid and loot addons in the guild (M10.2): per known addon of Data/Integrations.lua, its detection on this client
--     (status, version, level, folder name confirmed or not) and, from the addon census (Data/Census.lua, through
--     Integrations:Holders), how many members who share their list have it loaded, out of how many, with the versions.
--     Who has it, by name, only as Census:Who allows (SPEC-10 Q11, Q17): officers and the Guild Master everybody, anybody
--     else only the own entry. With the census switched off, nobody sharing yet, or the player not sharing, one line
--     says so instead of an empty list.
-- Nothing about attendance is shown: FDCP does not expose it and Accord keeps none.
-- With Accord as the source of the season roster, the view says that Accord's own season roster comes later (M10.3).
--
-- View.Model() reads the sources and FDCP now; View.Lines(model) is a plain function of it (tested offline); the frames
-- only draw the lines. View.CardSection(entry) adds "Loot (FDCP)" to the member card: the member's credits and place in
-- the loot queue as FDCP shows them, when the guild chose FDCP for the loot and this client has them.
-- The view redraws on SOURCES_CHANGED, INTEGRATIONS_CHANGED, FDCP_CHANGED, ROLE_CHANGED and CENSUS_CHANGED, only while it
-- is visible.
-- While Core/Features.lua "raid" is off there is no tab (the view says it is not visible), no card section and nothing is
-- redrawn. Its functions stay available to the Season view (UI/Season.lua, switch "season"), which shows the season part of
-- FDCP and the addons in the guild from the M10 switch alone.
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.RaidView, ns.modules = View, ns.modules or {}
ns.modules.RaidView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, floor, max, min, concat = type, ipairs, pairs, tostring, math.floor, math.max, math.min, table.concat

View.ROW_HEIGHT = 20
View.HEADER = 84            -- the source selector and the loot row
View.WHEEL_STEP = 3
View.REFRESH_DELAY = 0.4
View.NAMES = 40             -- names written in a raid or bench line before "and N more"
View.VERSIONS = 3           -- versions written in an addon's guild line before "and N more"
View.SEP = " · "

-- FDCP's codes that have a text; an unknown code is shown as it is.
View.CODES = {
	ROLE = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGER" },
	PRESET = { PATTO = "FDCP_PRESET_PATTO", ROLL_ONLY = "FDCP_PRESET_ROLL_ONLY", LOOT_COUNCIL = "FDCP_PRESET_LOOT_COUNCIL",
		EPGP_SIMPLE = "FDCP_PRESET_EPGP_SIMPLE" },
	METRIC = { credits = "FDCP_METRIC_CREDITS", creditsPerNight = "FDCP_METRIC_PER_NIGHT", roll = "FDCP_METRIC_ROLL" },
	AWARD = { confirm = "FDCP_AWARD_CONFIRM", auto = "FDCP_AWARD_AUTO", council = "FDCP_AWARD_COUNCIL" },
	LATE = { average = "FDCP_LATE_AVERAGE", min = "FDCP_LATE_MIN", zero = "FDCP_LATE_ZERO", fixed = "FDCP_LATE_FIXED" },
	BENCH = { none = "FDCP_BENCH_NONE", bonus = "FDCP_BENCH_BONUS", malus = "FDCP_BENCH_MALUS" },
	KIND = { loot = "INTEG_KIND_LOOT", raid = "INTEG_KIND_RAID", both = "INTEG_KIND_BOTH" },
	STATUS = { loaded = "INTEG_LOADED", disabled = "INTEG_DISABLED", installed = "INTEG_INSTALLED", missing = "INTEG_MISSING" },
	CATEGORY = { weapon = "FDCP_CAT_WEAPON", offhand = "FDCP_CAT_OFFHAND", trinket = "FDCP_CAT_TRINKET", quest = "FDCP_CAT_QUEST",
		jewelry = "FDCP_CAT_JEWELRY", armor = "FDCP_CAT_ARMOR", cosmetic = "FDCP_CAT_COSMETIC", other = "FDCP_CAT_OTHER" },
}
View.CATEGORY_ORDER = { "weapon", "offhand", "trinket", "quest", "jewelry", "armor", "cosmetic", "other" }

local function code(kind, value)
	if value == nil then return "?" end
	local key = View.CODES[kind] and View.CODES[kind][value]
	if key then return L[key] end
	return tostring(value)
end
View.Code = code

-- 12 -> "12", 1.5 -> "1.5"
local function num(n)
	if type(n) ~= "number" then return "?" end
	if n == floor(n) then return tostring(n) end
	return ("%.1f"):format(n)
end
View.Num = num

local function short(name)
	if type(name) ~= "string" then return "?" end
	return (ns.Compat.SplitName(name))
end

local function spec(id)
	if type(id) ~= "number" then return nil end
	return ns.Compat and ns.Compat.SpecName(id) or ("#" .. id)
end

local function namesText(list)
	local out = {}
	for i, n in ipairs(list) do
		if i > View.NAMES then break end
		out[#out + 1] = short(n)
	end
	local more = #list - #out
	local text = concat(out, ", ")
	if more > 0 then text = text .. L["RAID_MORE"]:format(more) end
	return text
end

local function on() return ns.Features ~= nil and ns.Features.On("raid") end

---------------------------------------------------------------------------------------------------------------------
-- The model and its lines
---------------------------------------------------------------------------------------------------------------------
-- Everything the lines need, read now: sources, FDCP's state and, at level 1, its data.
function View.Model()
	local I, F = ns.Integrations, ns.FDCP
	local m = { raid = I and I:Source("raid") or "accord", loot = I and I:Source("loot") or "none",
		canChoose = I ~= nil and I:CanChoose() }
	m.usesFDCP = m.raid == "fdcp" or m.loot == "fdcp"
	local addon = on() and ns.Loot and ns.Loot:Addon()
	m.addonName = addon and addon.name or nil
	m.fdcp = I and I:State("fdcp") or nil
	if m.usesFDCP and m.fdcp and m.fdcp.level == 1 and F then
		m.ready = F.Ready()
		if m.ready then
			m.source, m.version, m.season = F.Source(), F.Version(), F.Season()
			if m.raid == "fdcp" then m.pool, m.night = F.Pool(), F.Night() end
			if m.loot == "fdcp" then
				local me = ns.Compat and ns.Compat.Player.Name()
				m.mine = me and F.Credits(me) or nil
			end
		end
	end
	View.AddonsModel(m)
	return m
end

-- The raid and loot addons: this client's detection and, while the census is on, who in the guild has each one.
function View.AddonsModel(m)
	local I, C = ns.Integrations, ns.Census
	if not I then return m end
	m.census = C ~= nil and C.Enabled()
	local versions = {}
	if m.census then
		m.sharing = C.Sharing()
		m.names = C.CanSeeNames()
		m.namesNote = m.names and C.NAMES_VISIBLE_TO == "officers"
		for _, r in ipairs(C:Summary().rows) do versions[r.folder] = r.versions end
	end
	m.addons = {}
	for _, def in ipairs(I.KNOWN) do
		local a = { id = def.id, name = def.name or def.folder, kind = def.kind, state = I:State(def.id) }
		if m.census then
			a.who, a.users, a.total = I:Holders(def.id)
			a.versions = versions[def.folder] or {}
			m.total = a.total
		end
		m.addons[#m.addons + 1] = a
	end
	return m
end

-- The reason FDCP gives nothing here, or nil when its data can be read.
local function problem(m)
	local st = m.fdcp
	if not st or st.level == nil then
		if st and st.status == "disabled" then return L["FDCP_DISABLED"] end
		return L["FDCP_MISSING"]
	end
	if st.level == 0 then
		if st.reason == "version" then return L["FDCP_API_VERSION"]:format(tostring(st.apiVersion or "?")) end
		return L["FDCP_API_ABSENT"]
	end
	if not m.ready then return L["FDCP_NOT_READY"] end
	if not m.source then return L["FDCP_NO_DATA"] end
	return nil
end
View.Problem = problem

local function memberLine(e)
	local parts = { short(e.name) }
	local who = {}
	local className = e.class and ns.Roster and ns.Roster.ClassName(e.class)
	if className then who[#who + 1] = className end
	if e.role then who[#who + 1] = code("ROLE", e.role) end
	if #who > 0 then parts[#parts + 1] = concat(who, " ") end
	if e.ms1 then parts[#parts + 1] = L["RAID_MS1"]:format(spec(e.ms1)) end
	if e.ms2 then parts[#parts + 1] = L["RAID_MS2"]:format(spec(e.ms2)) end
	if e.os then parts[#parts + 1] = L["RAID_OS"]:format(spec(e.os)) end
	if e.status == "TRIAL" then parts[#parts + 1] = L["RAID_TRIAL"]
	elseif e.status == "INACTIVE" then parts[#parts + 1] = L["RAID_INACTIVE"] end
	return { text = concat(parts, View.SEP), member = e.name }
end
View.MemberLine = memberLine

local function cellText(v)
	if v == "council" then return L["FDCP_COST_COUNCIL"] end
	if type(v) == "number" then return num(v) end
	return "-"
end

local function rulesLines(out, r)
	out[#out + 1] = { text = L["RULES_HEAD"], sub = true }
	out[#out + 1] = { text = r.source == "GUILD" and L["RULES_GUILD"] or L["RULES_DEFAULT"], muted = true }
	local preset = code("PRESET", r.preset)
	if r.custom then preset = preset .. L["RULES_CUSTOM"] end
	out[#out + 1] = { text = L["RULES_PRESET"]:format(preset) }
	if r.metric then out[#out + 1] = { text = L["RULES_METRIC"]:format(code("METRIC", r.metric)) } end
	if r.startCredits then out[#out + 1] = { text = L["RULES_START"]:format(num(r.startCredits)) } end
	if r.awardMode then out[#out + 1] = { text = L["RULES_AWARD"]:format(code("AWARD", r.awardMode)) } end
	local cats, seen = {}, {}
	for _, c in ipairs(View.CATEGORY_ORDER) do
		if r.costs[c] then cats[#cats + 1] = c seen[c] = true end
	end
	local extra = {}
	for c in pairs(r.costs) do if not seen[c] then extra[#extra + 1] = c end end
	table.sort(extra)
	for _, c in ipairs(extra) do cats[#cats + 1] = c end
	if #cats > 0 then out[#out + 1] = { text = L["RULES_COSTS"] } end
	for _, c in ipairs(cats) do
		local row = r.costs[c]
		out[#out + 1] = { text = L["RULES_COST"]:format(code("CATEGORY", c), cellText(row[3]), cellText(row[4]), cellText(row[5])), indent = true }
	end
	local rm = r.responseMultiplier
	if rm and (rm.MS or rm.OS or rm.TMOG) then
		out[#out + 1] = { text = L["RULES_RESPONSES"]:format(num(rm.MS), num(rm.OS), num(rm.TMOG)) }
	end
	if r.lateJoin then out[#out + 1] = { text = L["RULES_LATE"]:format(code("LATE", r.lateJoin)) } end
	if r.bench and r.bench.effect then
		local text = code("BENCH", r.bench.effect)
		if r.bench.effect ~= "none" and r.bench.amount then text = text .. " " .. num(r.bench.amount) end
		out[#out + 1] = { text = L["RULES_BENCH"]:format(text) }
	end
	out[#out + 1] = { text = L["RULES_READONLY"], muted = true }
end
View.RulesLines = rulesLines      -- the loot page's fixed part (UI/LootPage.lua)

-- "This client: loaded 7.1 · detection only (level 0) · folder name not confirmed in game yet"
local function hereText(st)
	local status = code("STATUS", st.status)
	if st.version and st.status ~= "missing" then status = status .. " " .. st.version end
	local parts = { status }
	if st.level == 1 then parts[#parts + 1] = L["INTEG_LEVEL_1"]
	elseif st.level == 0 then parts[#parts + 1] = L["INTEG_LEVEL_0"] end
	if not st.confirmed then parts[#parts + 1] = L["INTEG_UNCONFIRMED"] end
	return L["INTEG_HERE"]:format(concat(parts, View.SEP))
end
View.HereText = hereText

-- "7.1 (2), 7.0 (1) and 1 more"
local function versionsText(list)
	local out = {}
	for i, v in ipairs(list) do
		if i > View.VERSIONS then break end
		out[#out + 1] = L["INTEG_VERSION_N"]:format(v.version or L["ADDONS_NO_VERSION"], v.n)
	end
	local text = concat(out, ", ")
	if #list > #out then text = text .. L["RAID_MORE"]:format(#list - #out) end
	return text
end

-- One member who has the addon: "Bob (you) · 7.1 · characters: Bob, Ann"
local function holderLine(w)
	local name = short(w.name)
	if w.own then name = (w.shared and L["ADDONS_YOU"] or L["ADDONS_YOU_NOT_SHARED"]):format(name) end
	local parts = { name, w.version or L["ADDONS_NO_VERSION"] }
	local chars = w.chars or {}
	if #chars > 1 or (chars[1] and chars[1] ~= w.name) then
		local list = {}
		for i, c in ipairs(chars) do list[i] = short(c) end
		parts[#parts + 1] = L["INTEG_CHARS"]:format(concat(list, ", "))
	end
	return { text = concat(parts, View.SEP), indent = true }
end
View.HolderLine = holderLine

local function addonsLines(out, m, add)
	add(L["INTEG_HEAD"], "heading")
	if not m.census then
		add(L["INTEG_CENSUS_OFF"], "muted")
	else
		if (m.total or 0) == 0 then add(L["ADDONS_NOBODY"], "muted") end
		if not m.sharing then add(L["ADDONS_NOT_SHARING"], "muted") end
		if not m.names then add(L["INTEG_NAMES_OFFICERS"], "muted")
		elseif m.namesNote then add(L["ADDONS_WHO_NOTE"], "muted") end
	end
	for _, a in ipairs(m.addons) do
		add(L["INTEG_ADDON"]:format(a.name, code("KIND", a.kind)), "sub")
		out[#out + 1] = { text = hereText(a.state), indent = true, muted = a.state.level == nil }
		if m.census and (a.total or 0) > 0 then
			local text
			if a.users > 0 then
				text = L["INTEG_GUILD"]:format(a.users, a.total, floor(a.users * 100 / a.total + 0.5))
				if #a.versions > 0 then text = text .. View.SEP .. L["INTEG_VERSIONS"]:format(versionsText(a.versions)) end
			else
				text = L["INTEG_GUILD_NONE"]:format(a.total)
			end
			out[#out + 1] = { text = text, indent = true, muted = a.users == 0 }
		end
		for _, w in ipairs(a.who or {}) do out[#out + 1] = holderLine(w) end
	end
end
View.AddonsLines = addonsLines   -- the Season view (M10.3) ends with the same section

-- { { text, heading?, sub?, muted?, indent? } } for a model.
function View.Lines(m)
	local out = {}
	local function add(text, kind)
		local l = { text = text }
		if kind then l[kind] = true end
		out[#out + 1] = l
	end
	local why = m.usesFDCP and problem(m) or nil
	if m.usesFDCP then
		if why then add(why, "warn")
		else
			local from = m.source == "LEDGER" and L["FDCP_FROM_LEDGER"] or L["FDCP_FROM_SNAPSHOT"]
			add(L["FDCP_STATUS"]:format(m.version or "?", from), "muted")
		end
	end

	-- the season roster
	add(L["RAID_SEASON"], "heading")
	if m.raid ~= "fdcp" then
		add(L["RAID_OWN_SOON"], "muted")
	elseif why then
		add(L["RAID_FDCP_UNAVAILABLE"], "muted")
	else
		local s = m.season
		if s then
			local state = s.state == "OPEN" and L["SEASON_OPEN"] or s.state == "CLOSED" and L["SEASON_CLOSED"] or "?"
			add(L["RAID_SEASON_LINE"]:format(s.name or tostring(s.id or "?"), state))
		end
		if m.pool == nil then
			add(L["RAID_NO_POOL"], "muted")
		elseif #m.pool == 0 then
			add(L["RAID_POOL_EMPTY"], "muted")
		else
			add(L["RAID_POOL"]:format(#m.pool), "sub")
			if m.source == "SNAPSHOT" then add(L["RAID_POOL_MEMBER"], "muted") end
			for _, e in ipairs(m.pool) do out[#out + 1] = memberLine(e) end
		end
		-- the lineup and the bench of the open night
		add(L["RAID_LINEUP"], "heading")
		local n = m.night
		if not n then
			add(m.source == "SNAPSHOT" and L["RAID_NIGHT_OFFICERS"] or L["RAID_NO_NIGHT"], "muted")
		else
			add(L["RAID_NIGHT"]:format(n.instance or "?", num(n.size), tostring(n.date or "?")))
			add(L["RAID_IN_RAID"]:format(#n.raid, namesText(n.raid)))
			add(L["RAID_ON_BENCH"]:format(#n.bench, namesText(n.bench)))
		end
	end

	-- the loot
	add(L["RAID_LOOT"], "heading")
	if m.loot ~= "fdcp" then
		add(m.addonName and L["RAID_LOOT_ADDON"]:format(m.addonName) or L["LOOT_NONE"], "muted")
	elseif why then
		add(L["RAID_FDCP_UNAVAILABLE"], "muted")
	else
		local c = m.mine
		if c then
			if c.place then add(L["LOOT_MINE"]:format(num(c.credits), c.place, c.of or c.place))
			else add(L["LOOT_MINE_NO_PLACE"]:format(num(c.credits))) end
		else
			add(L["LOOT_MINE_NONE"], "muted")
		end
		add(L["RAID_LOOT_RULES"], "muted")
	end

	-- the raid and loot addons in the guild
	if m.addons then addonsLines(out, m, add) end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The member card
---------------------------------------------------------------------------------------------------------------------
function View.CardSection(e)
	local I = ns.Integrations
	if not (on() and I and type(e) == "table") or e.notInGuild or I:Source("loot") ~= "fdcp" then return nil end
	local lines = {}
	local st = I:State("fdcp")
	if not (st and st.level == 1 and ns.FDCP) then
		lines[1] = { text = L["CARD_FDCP_UNAVAILABLE"], muted = true }
	else
		local c = ns.FDCP.Credits(e.name)
		if not c then
			lines[1] = { text = L["CARD_FDCP_NONE"], muted = true }
		else
			lines[1] = { text = L["CARD_FDCP_CREDITS"]:format(num(c.credits)) }
			if c.place then lines[2] = { text = L["CARD_FDCP_PLACE"]:format(c.place, c.of or c.place) }
			else lines[2] = { text = L["CARD_FDCP_NO_PLACE"], muted = true } end
			if c.viaAlt then lines[#lines + 1] = { text = L["CARD_FDCP_VIA"]:format(short(c.name)), muted = true } end
		end
	end
	return { id = "fdcp", title = L["CARD_FDCP"], lines = lines }
end

---------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------
local function selector(f, label, datum, items, y)
	local t = Widgets.Text(f, "BodyMedium", "text-2", "LEFT")
	t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y - 8)
	t:SetText(label)
	local seg = Widgets.Segmented(f, items, function(id)
		if View.painting then return end
		local ok = ns.Integrations and ns.Integrations:SetSource(datum, id)
		if not ok then View:Redraw() end
	end)
	seg:SetPoint("TOPLEFT", f, "TOPLEFT", 130, y)
	return seg, t
end

function View:Build(f)
	self.frame = f
	f.raidSeg, f.raidLabel = selector(f, L["SOURCE_RAID"], "raid",
		{ { id = "accord", text = L["SOURCE_ACCORD"] }, { id = "fdcp", text = L["SOURCE_FDCP"] } }, 0)
	f.lootLabel = Widgets.Text(f, "BodyMedium", "text-2", "LEFT")
	f.lootLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -48)
	f.lootLabel:SetText(L["SOURCE_LOOT"])
	f.lootPage = Widgets.Button(f, { text = L["RAID_LOOT_PAGE"], style = "tonal", dense = true,
		onClick = function() View:ToggleLoot() end })
	f.lootPage:SetPoint("TOPLEFT", f, "TOPLEFT", 130, -40)
	f.lootName = Widgets.Text(f, "Body", "text-1", "LEFT")
	f.lootName:SetPoint("LEFT", f.lootPage, "RIGHT", 10, 0)
	f.lootName:SetWordWrap(false)
	f.lootName:SetWidth(200)
	f.open = Widgets.Button(f, { text = L["FDCP_OPEN"], style = "outlined", dense = true, onClick = function() ns.FDCP.Open() end })
	f.open:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.who = Widgets.Text(f, "Small", "text-3", "RIGHT")
	f.who:SetPoint("TOPRIGHT", f.open, "BOTTOMRIGHT", 0, -10)
	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.HEADER)
	f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.list:SetClipsChildren(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta) View:Scroll(-delta * View.WHEEL_STEP) end)
	f.list.lines = {}
	f.offset = 0
	f:SetScript("OnShow", function() View:Redraw() end)
	self:Redraw()
end

local function visibleRows(list)
	local h = list and list:GetHeight() or 0
	return h >= View.ROW_HEIGHT and floor(h / View.ROW_HEIGHT) or 16
end

function View:Redraw()
	local f = self.frame
	if not f then return end
	local m = View.Model()
	self.model = m
	self.painting = true
	f.raidSeg:Select(m.raid)
	self.painting = false
	f.raidSeg:SetEnabled(m.canChoose)
	f.who:SetText(m.canChoose and L["SOURCE_OFFICERS_YOU"] or L["SOURCE_OFFICERS"])
	local st = m.fdcp
	f.open:SetShown(st ~= nil and st.level ~= nil)
	f.lootName:SetText(m.addonName or L["LOOT_NOT_SET"])
	if View.LootReadable() then self.lootShown = false end
	f.lootPage:SetLabel(L[self.lootShown and "RAID_LOOT_BACK" or "RAID_LOOT_PAGE"])
	f.list:SetShown(not self.lootShown)
	if f.lootPane then f.lootPane:SetShown(self.lootShown == true) end
	if self.lootShown then self:DrawLoot(f) end
	local lines = View.Lines(m)
	self.shown = lines
	local list = f.list
	local visible = visibleRows(list)
	f.offset = max(0, min(f.offset or 0, max(0, #lines - visible)))
	local drawn = max(0, min(visible, #lines - f.offset))
	for i = 1, drawn do
		local l = lines[f.offset + i]
		local fs = list.lines[i]
		if not fs then
			fs = Widgets.Text(list, "Body", "text-1", "LEFT")
			fs:SetWordWrap(false)
			list.lines[i] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", list, "TOPLEFT", (l.indent or l.member) and 12 or 0, -(i - 1) * View.ROW_HEIGHT)
		fs:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		fs:SetText(l.text)
		fs:SetFontObject(Theme.Font(l.heading and "H2" or l.sub and "BodyMedium" or "Body"))
		if l.heading then Theme.Text(fs, "text-1")
		elseif l.warn then Theme.Text(fs, "warn")
		elseif l.muted then Theme.Text(fs, "text-3")
		else Theme.Text(fs, "text-2") end
		fs:Show()
	end
	for i = drawn + 1, #list.lines do list.lines[i]:Hide() end
end

-- true when this character can read the handbook's loot page: then the loot page opens there.
function View.LootReadable()
	local H = ns.HandbookView
	if not (H and ns.Loot) then return false end
	return select(2, H.Rows())[ns.Loot.PAGE] ~= nil
end

-- "Loot page": the handbook's, or its fixed part here, so the choice is never out of reach (SPEC-15 §8).
function View:ToggleLoot()
	if View.LootReadable() then
		ns.HandbookView:Open(ns.Loot.PAGE)
		return
	end
	self.lootShown = not self.lootShown
	if not self.lootShown and self.frame and self.frame.loot then self.frame.loot.form = nil end
	self:Redraw()
end

function View:DrawLoot(f)
	if not f.lootPane then
		local pane = ns.HandbookView.Scroller(f)
		pane:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -View.HEADER)
		pane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.lootPane = pane
		f.loot = ns.LootPage.Create(pane.page, function() View:Redraw() end)
		f.loot:SetPoint("TOPLEFT", pane.page, "TOPLEFT", 0, 0)
	end
	f.lootPane:Show()
	local width = f.lootPane:GetWidth() or 0
	if width <= 0 then width = ns.LootPage.WIDTH end
	f.lootPane.page:SetWidth(width)
	local height = f.loot:Update(ns.LootPage.Model(), width)
	f.lootPane:SetContentHeight(height + 8)
end

function View:Scroll(delta)
	local f = self.frame
	if not f then return false end
	local total = self.shown and #self.shown or 0
	local target = max(0, min((f.offset or 0) + delta, max(0, total - visibleRows(f.list))))
	if target == f.offset then return false end
	f.offset = target
	self:Redraw()
	return true
end

-- The data changed: one redraw after the burst, only while the view is visible.
function View:Changed()
	if self.refreshTimer or not (self.frame and self.frame:IsVisible()) then return end
	self.refreshTimer = true
	local scheduled = ns.Compat and ns.Compat.After(View.REFRESH_DELAY, function()
		View.refreshTimer = nil
		if View.frame and View.frame:IsVisible() then View:Redraw() end
	end)
	if not scheduled then self.refreshTimer = nil self:Redraw() end
end

if ns.MemberCard then ns.MemberCard.AddSection("fdcp", 7, View.CardSection) end

if ns.Shell then
	ns.Shell:RegisterView("raid", { label = L["VIEW_RAID"], order = 50, visible = on, build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.RaidView = View
	if ns.Bus then
		local function changed()
			if not on() then return end
			View:Changed()
			if ns.MemberCard and ns.MemberCard.Refresh then ns.MemberCard:Refresh() end
		end
		for _, event in ipairs({ "SOURCES_CHANGED", "INTEGRATIONS_CHANGED", "FDCP_CHANGED", "ROLE_CHANGED", "CENSUS_CHANGED",
			"HANDBOOK_CHANGED" }) do
			ns.Bus:On(event, changed)
		end
	end
end

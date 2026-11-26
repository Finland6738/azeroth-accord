-- HandbookDefaults: the default pages of the guild handbook and their one seeding (M11.5, SPEC-15 §7). Lua 5.1.
--
-- Templates  six pages with a fixed slug and order; the body holds only headings, each with an empty line under it, and
--            two links to the season view ([[season]]: the Season view shows the roster of the source the officers chose,
--            Accord's or FDCP's). No text of any guild (HB-03). Titles, headings and the link's words are interface
--            strings (Locale), so they are written in the language of the writer who seeds.
-- Seeding    by a writer's click on "Create the default pages", never by itself: the six pages with tpl = true and the
--            record "seeded" { at, by }. A template is not published: members see it once a writer saves it.
-- Once       offered only while this client holds no record of the handbook at all (no "seeded", no page, live or
--            deleted), and SEED_WAIT seconds after login or after joining the guild, so the first sync has come. A late
--            seeding writes revision 1, which loses to every later revision and deletion: a deleted page never comes back.
-- Switch     Core/Features.lua "raid", with the handbook (Data/Handbook.lua).
local ADDON_NAME, ns = ...
ns = ns or {}
local Defaults = {}
ns.HandbookDefaults, ns.modules = Defaults, ns.modules or {}
ns.modules.HandbookDefaults = Defaults

local ipairs, concat, next = ipairs, table.concat, next

Defaults.SEED_WAIT = 120      -- seconds after login before the seeding is offered (SPEC-15 §7.3)
Defaults.VERSION_MAX = 20     -- bytes of the `by` of the seeded record

local SEASON = "[[season]]"
local SPEC_LINK = "[[season\194\166%s]]"   -- the link with its own words, after "¦" (Data/HandbookText.lua)

-- slug, order, the locale key of the title, and the headings: a key, or { key, link = "season" | "spec" }.
Defaults.PAGES = {
	{ slug = "info", order = 10, title = "HANDBOOK_TPL_INFO", headings = {
		"HANDBOOK_TPL_ABOUT", "HANDBOOK_TPL_SCHEDULE", "HANDBOOK_TPL_COMMUNICATION", "HANDBOOK_TPL_OFFICERS" } },
	{ slug = "rules", order = 20, title = "HANDBOOK_TPL_RULES", headings = {
		"HANDBOOK_TPL_GENERAL", "HANDBOOK_TPL_CHAT", "HANDBOOK_TPL_RAIDS_DUNGEONS", "HANDBOOK_TPL_BANK",
		"HANDBOOK_TPL_SANCTIONS" } },
	{ slug = "faq", order = 30, title = "HANDBOOK_TPL_FAQ", headings = { "HANDBOOK_TPL_QUESTIONS" } },
	{ slug = "raid", order = 40, title = "HANDBOOK_TPL_RAID", headings = {
		"HANDBOOK_TPL_SCHEDULE", "HANDBOOK_TPL_SIGNUPS", "HANDBOOK_TPL_COMPOSITION", "HANDBOOK_TPL_PREPARATION",
		"HANDBOOK_TPL_DURING" } },
	{ slug = "roster", order = 50, title = "HANDBOOK_TPL_ROSTER", headings = {
		{ "HANDBOOK_TPL_SEASON_ROSTER", link = "season" }, "HANDBOOK_TPL_RANKS", "HANDBOOK_TPL_ALTS",
		"HANDBOOK_TPL_INACTIVITY" } },
	{ slug = "loot", order = 60, title = "HANDBOOK_TPL_LOOT", headings = {
		{ "HANDBOOK_TPL_LOOT_SYSTEM", link = "spec" }, "HANDBOOK_TPL_LOOT_RULES", "HANDBOOK_TPL_QUESTIONS" } },
}

local function book() return ns.Handbook end

-- The page `def` (an entry of PAGES) as it is seeded: { title, body, order, tpl }.
function Defaults.Template(def)
	local L = ns.L
	local lines = {}
	for _, h in ipairs(def.headings) do
		local key, link = h, nil
		if type(h) == "table" then key, link = h[1], h.link end
		lines[#lines + 1] = "# " .. L[key]
		if link == "season" then lines[#lines + 1] = SEASON
		elseif link == "spec" then lines[#lines + 1] = SPEC_LINK:format(L["HANDBOOK_TPL_SPEC_LINK"]) end
		lines[#lines + 1] = ""
	end
	return { title = L[def.title], body = concat(lines, "\n"), order = def.order, tpl = true }
end

local waits = 0   -- the waits started: only the last one ends

-- Starts the wait before the seeding is offered; the views draw again when it ends.
function Defaults:Start()
	waits = waits + 1
	local mine = waits
	self.waited = false
	ns.Compat.After(Defaults.SEED_WAIT, function()
		if mine ~= waits then return end
		Defaults.waited = true
		if book().Enabled() and ns.Bus then ns.Bus:Emit("HANDBOOK_CHANGED") end
	end)
end

-- true when this character may create the default pages now.
function Defaults:CanSeed()
	if not (book() and book():CanWrite()) then return false end
	if not self.waited then return false end
	return next(ns.Store:Records(book().SET)) == nil
end

local function version()
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	v = tostring(v or "?"):sub(1, Defaults.VERSION_MAX)
	return book().IsClean(v) and v or "?"
end

-- Writes the templates and the record "seeded". Returns the number of pages written, or false and "seeded" (not
-- offered now) or a reason of Store:Put.
function Defaults:Seed()
	if not self:CanSeed() then return false, "seeded" end
	local B, written = book(), 0
	for _, def in ipairs(Defaults.PAGES) do
		local rec, why = ns.Store:Put(B.SET, B.PageId(def.slug), Defaults.Template(def))
		if not rec then return false, why end
		B.Within(rec)
		written = written + 1
	end
	local rec, why = ns.Store:Put(B.SET, B.SEEDED_ID, { at = ns.Compat.ServerTime(), by = version() })
	if not rec then return false, why end
	B.Within(rec)
	return written
end

if ns.addon then
	ns.addon.HandbookDefaults = Defaults
	if ns.OnEnable then ns.OnEnable(function() Defaults:Start() end) end
	if ns.Bus then ns.Bus:On("GUILD_CHANGED", function() Defaults:Start() end) end
end

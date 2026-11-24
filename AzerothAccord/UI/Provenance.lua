-- Provenance: where a shown value comes from and how old it is (SPEC-11 §1, M7.2). Plain functions, tested offline
-- (Tests/test_provenance.lua); the widget that draws the label is UI/Widgets/Provenance.lua. Lua 5.1.
--   info = { source = "native" | "shared" | "own" | "note", observedAt, author (GUID, shared only), set (a Provenance.DIM_DAYS key),
--            member (the name the "note" tooltip speaks of) }
--   Provenance.AgeText(seconds)      "just now" / "5 min ago" / "3 h ago" / "3 d ago" / "4 mo ago" / "2 y ago" (SPEC-11 §1.2)
--   Provenance.Age(observedAt, now)  seconds, never negative (a time up to an hour in the future is age zero)
--   Provenance.IsDim(info, now)      true for a `shared` value older than the threshold of its `set` (SPEC-11 §1.4)
--   Provenance.Describe(info, now)   { label, lines = { tooltip lines }, dim }
--   Provenance.SeenText(seen, now)   "today" for the day of `seen`, else the age in whole days (SPEC-11 §2.4)
--   Provenance.AltGuildText(altGuild, now)  "Other guild: X · seen 3 d ago" / "No guild · seen today" / "not in guild" (M7.3)
--   Provenance.AltGuildInfo(altGuild)       the `info` of that line: shared, observed at the last login, dimmed after 30 days
--   Provenance.AuthorName(guid)      roster name, else the author's own record, else "a former guild member"; never the GUID
local ADDON_NAME, ns = ...
ns = ns or {}
local L = ns.L
local floor, max = math.floor, math.max
local type, tostring = type, tostring

local Provenance = {}
ns.Provenance = Provenance
ns.modules = ns.modules or {}
ns.modules.Provenance = Provenance
if ns.addon then ns.addon.Provenance = Provenance end

local DAY = 86400

-- Days after which a `shared` value is dimmed, per kind of datum (one row to change a threshold).
Provenance.DIM_DAYS = { bank = 7, recipes = 60, altGuild = 30, addonVersion = 30, contacts = 180 }

local function now() return ns.Compat and ns.Compat.ServerTime() or time() end

function Provenance.AgeText(seconds)
	if type(seconds) ~= "number" or seconds < 60 then return L["AGO_NOW"] end
	if seconds < 3600 then return L["AGO_MINUTES"]:format(floor(seconds / 60)) end
	if seconds < DAY then return L["AGO_HOURS"]:format(floor(seconds / 3600)) end
	local days = floor(seconds / DAY)
	if days < 60 then return L["AGO_DAYS"]:format(days) end
	if days < 730 then return L["AGO_MONTHS"]:format(floor(days / 30)) end
	return L["AGO_YEARS"]:format(floor(days / 365))
end

function Provenance.Age(observedAt, at)
	if type(observedAt) ~= "number" then return nil end
	return max(0, (at or now()) - observedAt)
end

-- Whole days of age, for the threshold and the tooltip ("Not updated for 9 days").
local function ageDays(info, at)
	local age = Provenance.Age(info.observedAt, at)
	return age and floor(age / DAY) or nil, age
end

function Provenance.IsDim(info, at)
	if type(info) ~= "table" or info.source ~= "shared" then return false end
	local limit = Provenance.DIM_DAYS[info.set]
	local age = Provenance.Age(info.observedAt, at)
	if not (limit and age) then return false end
	return age > limit * DAY
end

-- The name of a record's author for a tooltip: the same cleaning as the contacts (control characters out, "|" doubled).
local function clean(text)
	text = tostring(text):gsub("[%c]", "")
	return (text:gsub("|", "||"))
end

function Provenance.AuthorName(guid)
	if type(guid) == "string" then
		local e = ns.Roster and ns.Roster.ByGUID and ns.Roster:ByGUID(guid)
		local name = e and (e.short or e.name)
		if not name then
			local m = ns.Store and ns.Store.MemberByGUID and ns.Store:MemberByGUID(guid)
			name = m and m.name
		end
		if not name and ns.Store and ns.Store.Get then
			local rec = ns.Store:Get("accounts", guid)
			if rec and type(rec.chars) == "table" then
				for _, c in ipairs(rec.chars) do
					if type(c) == "table" and c.guid == guid and type(c.name) == "string" and c.name ~= "" then name = c.name break end
				end
			end
		end
		if type(name) == "string" and name ~= "" then return clean(name) end
	end
	return L["PROV_AUTHOR_FORMER"]
end

function Provenance.Describe(info, at)
	if type(info) ~= "table" then return nil end
	at = at or now()
	local _, age = ageDays(info, at)
	local ageText = age and Provenance.AgeText(age) or nil
	local label, lines, dim = "", {}, false
	if info.source == "native" then
		label = L["PROV_GAME"]
		lines[1] = L["PROV_TIP_NATIVE"]
	elseif info.source == "shared" then
		label = ageText or L["PROV_SHARED"]
		lines[1] = ageText and L["PROV_TIP_SHARED"]:format(Provenance.AuthorName(info.author), ageText)
			or L["PROV_TIP_SHARED_NOAGE"]:format(Provenance.AuthorName(info.author))
		dim = Provenance.IsDim(info, at)
		if dim then lines[2] = L["PROV_TIP_STALE"]:format(floor(age / DAY)) end
	elseif info.source == "own" then
		label = L["PROV_YOU"]
		lines[1] = ageText and L["PROV_TIP_OWN"]:format(ageText) or L["PROV_TIP_OWN_NOAGE"]
	elseif info.source == "note" then
		label = L["PROV_NOTE"]
		lines[1] = L["PROV_TIP_NOTE"]:format(clean(info.member or "?"))
	else
		return nil
	end
	return { label = label, lines = lines, dim = dim }
end

-- Just the tooltip lines (for a cell or a row that has no room for the label itself).
function Provenance.TipLines(info, at)
	local d = Provenance.Describe(info, at)
	return d and d.lines or {}
end

-- When an alt outside the guild last logged in, to the day: `seen` is the start of a UTC day, so the same day is "today".
function Provenance.SeenText(seen, at)
	at = at or now()
	if type(seen) ~= "number" or at - seen < DAY then return L["AGE_TODAY"] end
	return Provenance.AgeText(floor((at - seen) / DAY) * DAY)
end

-- The line for a character outside the guild (SPEC-11 §2.4); `altGuild` is the table Accounts:Rebuild gives a member.
function Provenance.AltGuildText(ag, at)
	if type(ag) ~= "table" or ag.guild == nil then return L["NOT_IN_GUILD_SHORT"] end
	local text = ag.guild == "" and L["ALT_GUILD_NONE"] or L["ALT_GUILD_OTHER"]:format(ag.guild)
	if type(ag.seen) == "number" then text = L["ALT_GUILD_SEEN"]:format(text, Provenance.SeenText(ag.seen, at)) end
	return text
end

-- Shared by the author of the record the line was read from; its age is the last login, so it dims after a month.
function Provenance.AltGuildInfo(ag)
	if type(ag) ~= "table" or ag.guild == nil then return nil end
	return { source = "shared", observedAt = ag.seen or ag.time, author = ag.author, set = "altGuild" }
end

-- The `info` of a profession of the Roster entry (`source` native | shared | own, `time`, `author`).
function Provenance.ProfessionInfo(p)
	if type(p) ~= "table" then return nil end
	return { source = p.source or "native", observedAt = p.time, author = p.author, set = "recipes" }
end

-- Exports (M8.6; SPEC-12 §6): the roster, the inactive accounts and the timeline as CSV (read back with a strict RFC 4180
-- reader) and as text for Discord; the formula and "|" escaping; the size limit; that no token, GUID, guild key or officer
-- note is ever in them; and that only officers and the Guild Master get them.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function X() return AzerothAccord.Export end
local function Box() return AzerothAccord.ExportBox end
local function V() return AzerothAccord.OfficersView end
local function RV() return AzerothAccord.RosterView end
local function I() return AzerothAccord.Inactivity end
local function L() return LibStub("AceLocale-3.0"):GetLocale("AzerothAccord", true) end

local ME = "Player-1-0000A001"
local BOB, BOBALT, ANN, GONE = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000A01", "Player-1-00000090"
local FAR, OFF, OUT = "Player-1-00000FA1", "Player-1-000000FF", "Player-1-0000CC01"
local DAY = 86400

local TOKEN = "BOBTOKENBOBTOKENBOBTOKEN"
local GAME_NOTE, EXTENDED = "SECRET-GAME-NOTE", "SECRET-EXTENDED-NOTE"

-- public notes that test the escaping
local NOTES = {
	[BOB] = 'main tank, "the wall", since 2020',
	[BOBALT] = "=1+1",
	[ANN] = "  spaced  ",
	[GONE] = "@everyone ```ping``` |cffff0000red|r",
	[FAR] = "città, perché: è così",
	[OFF] = "-5 DKP",
}

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = false, lastOnline = { 0, 0, 100, 0 }, note = NOTES[BOB], officerNote = GAME_NOTE },
		{ name = "Brom Hollowtree", level = 30, class = "WARRIOR", rank = 4, guid = BOBALT, online = false, lastOnline = { 0, 0, 50, 0 }, note = NOTES[BOBALT] },
		{ name = "Ànnà", level = 50, class = "PRIEST", rank = 3, guid = ANN, online = false, lastOnline = { 0, 0, 40, 0 }, note = NOTES[ANN] },
		{ name = "Gone", level = 20, class = "ROGUE", rank = 3, guid = GONE, online = false, lastOnline = {}, note = NOTES[GONE] },
		{ name = "Zoë-OtherRealm", level = 44, class = "DRUID", rank = 3, guid = FAR, online = false, lastOnline = { 0, 0, 20, 0 }, note = NOTES[FAR] },
		{ name = "Officer", level = 60, class = "ROGUE", rank = 1, guid = OFF, note = NOTES[OFF] },
	} }
	if A() then A().Role:Refresh() A().Roster:MarkDirty() end
end

local function record(set, id, author, fields)
	local r = { id = id, author = author, rev = 1, time = GetServerTime() }
	for k, v in pairs(fields or {}) do r[k] = v end
	S():Records(set)[id] = r
	return r
end

local function day(offset) return A().Timeline.DayOf(GetServerTime() + (offset or 0) * DAY) end

local function event(k, g, name, ago, extra)
	local b = GetServerTime() - ago
	local e = { k = k, g = g, n = name, a = b - 600, b = b }
	for key, v in pairs(extra or {}) do e[key] = v end
	return e
end

-- Everything an export reads, and everything it must never write.
local function fill()
	local chars = { { guid = BOB, name = "Bob" }, { guid = BOBALT, name = "Brom Hollowtree" },
		{ guid = OUT, name = "Elsewhere", inGuild = false, guild = "", seen = GetServerTime() - 60 * DAY } }
	record("accounts", BOB, BOB, { token = TOKEN, chars = chars, main = BOB })
	record("accounts", BOBALT, BOBALT, { token = TOKEN, chars = chars, main = BOB })
	record("contacts", BOB, BOB, { account = TOKEN, discord = "bob_disc" })
	record("onotes", BOB, OFF, { char = BOB, text = EXTENDED })
	record("onotes", ANN, OFF, { char = ANN, text = EXTENDED .. "-2" })
	record("absence", ANN .. ":off", OFF, { char = ANN, from = day(), ["until"] = day(10) })
	local id = OFF .. ":" .. day() .. ":1"
	record("timeline", id, OFF, { observer = OFF, day = day(), ev = {
		event("note", BOB, "Bob", 100, { f = 'old "quoted", text', t = NOTES[BOB] }),
		event("note", ANN, "Ànnà", 200, { f = "line one\nline two", t = "=cmd|' /C calc'!A0" }),
		event("rank", BOBALT, "Brom Hollowtree", 300, { f = 3, t = 4, fn = "Member, old", tn = "Initiate" }),
		event("level", FAR, "Zoë-OtherRealm", 400, { f = 20, t = 27 }),
		event("join", GONE, "Gone", 500, { r = 3, rn = "Member", l = 20 }),
		event("leave", "Player-1-00000DEA", "Left Behind", 600, { rn = "Member", l = 9 }),
	} })
	A().Timeline:Invalidate()
	A().Accounts:MarkDirty()
	A().Roster:MarkDirty()
	I():Invalidate()
end

local function entries() return A().RosterModel.new():Entries() end
local function rows() return I():Rows({ minTier = 1, away = true, unknown = true }) end
local function changes() return V().TimelineRows({ days = 365 }) end
-- the season roster's declarations (M10.4): the rows of Data/Composition.lua, built from two entries
local function declarations()
	local out = {}
	for _, guid in ipairs({ BOB, ANN }) do
		local member = A().Roster:ByGUID(guid)
		out[#out + 1] = { guid = guid, name = member and member.name,
			rec = { class = "MAGE", ms1 = { spec = "FROST", role = "ranged" }, unsure = false, first = GetServerTime() } }
	end
	return A().Composition.FromAccord(out)
end
local ITEMS = { roster = entries, inactive = rows, timeline = changes, season = declarations }

local function build(kind, format) return X().Build(kind, format, ITEMS[kind]()) end

local function csv(kind)
	local text, info = build(kind, "csv")
	local header, records = CSV.records(text)
	eq(table.concat(header, ","), table.concat(X().CSV[kind], ","), "the columns, in order")
	eq(#records, info.rows)
	return records, text, info
end

local function by(records, column, value)
	for _, r in ipairs(records) do if r[column] == value then return r end end
	error("no row with " .. column .. " = " .. value, 2)
end

local function realmDay(ago) return date("!%Y-%m-%d", GetServerTime() - ago * DAY) end

describe("EXP-02, EXP-03: one value", function()
	before_boot(function() guild() end)

	it("quotes what RFC 4180 needs quoted and doubles the quotes", function()
		eq(X().CSVValue("plain name"), "plain name")
		eq(X().CSVValue("a,b"), '"a,b"')
		eq(X().CSVValue('say "hi"'), '"say ""hi"""')
		eq(X().CSVValue("two\nlines"), '"two\nlines"')
		eq(X().CSVValue(" lead"), '" lead"')
		eq(X().CSVValue("trail "), '"trail "')
		eq(X().CSVValue(""), "")
		eq(X().CSVValue("città"), "città")
	end)

	it("puts an apostrophe before a text that looks like a formula, never before a number", function()
		for _, v in ipairs({ "=1+1", "+39", "-x", "@here", "\tx", "\rx" }) do
			local out = X().CSVValue(v)
			local read = CSV.parse(out)[1][1]
			eq(read, "'" .. v)
		end
		eq(X().CSVValue("=a,b"), "\"'=a,b\"", "the apostrophe goes inside the quotes")
		eq(X().CSVValue(-5), "-5")
		eq(X().CSVValue("a=b"), "a=b")
	end)

	it("the strict reader refuses a broken file", function()
		raises(function() CSV.parse('a,"b') end, "never closed")
		raises(function() CSV.parse('a,b"c') end, "unquoted")
		raises(function() CSV.parse('"a"b') end, "after a closing quote")
	end)
end)

describe("Roster", function()
	before_boot(function() guild() end)

	it("round-trips through a CSV reader: one row per character in the guild", function()
		fill()
		local records, text, info = csv("roster")
		eq(info.left, 0)
		eq(#records, 7, "six members and the player; the character outside the guild has no row")
		falsy(text:find("Elsewhere,", 1, true))
		local bob = by(records, "name", "Bob")
		eq(bob.realm, ""); eq(bob.main, ""); eq(bob.class, "MAGE"); eq(bob.level, "60")
		eq(bob.public_note, NOTES[BOB])
		eq(bob.last_seen_date, realmDay(100)); eq(bob.days_inactive, "100")
		eq(bob.account_days_inactive, "50", "the alt counts"); eq(bob.tier, "2"); eq(bob.has_addon, "yes")
		local brom = by(records, "name", "Brom Hollowtree")
		eq(brom.main, "Bob"); eq(brom.public_note, "'=1+1"); eq(brom.days_inactive, "50")
		local ann = by(records, "name", "Ànnà")
		eq(ann.public_note, NOTES[ANN]); eq(ann.away_until, A().Absence.DayText(day(10))); eq(ann.has_addon, "no")
		local gone = by(records, "name", "Gone")
		eq(gone.days_inactive, ""); eq(gone.account_days_inactive, ""); eq(gone.tier, ""); eq(gone.last_seen_date, "")
		eq(gone.public_note, "'" .. NOTES[GONE], "the logical text: one |, read as text, not as a formula")
		local zoe = by(records, "name", "Zoë")
		eq(zoe.realm, "OtherRealm"); eq(zoe.public_note, NOTES[FAR])
		eq(by(records, "name", "Officer").public_note, "'-5 DKP")
		eq(by(records, "name", "Officer").tier, "0")
	end)

	it("holds what the view shows: its search, its filters, and the alts of the closed accounts", function()
		fill()
		local m = A().RosterModel.new()
		m:SetSearch("brom")
		eq(#m:Entries(), 1)
		m:SetSearch("")
		m:SetGrouped(true)
		local list = m:Entries()
		eq(#list, 7, "the alt of a closed account is exported, the character outside the guild is not")
		falsy(next(m.expanded), "the view stays closed")
		m:SetFilter("mains", true)
		eq(#m:Entries(), 6)
	end)
end)

describe("Inactive accounts", function()
	before_boot(function() guild() end)

	it("round-trips through a CSV reader: one row per account", function()
		fill()
		local records = csv("inactive")
		local bob = by(records, "main", "Bob")
		eq(bob.characters, "Bob; Brom Hollowtree"); eq(bob.days_inactive, "50"); eq(bob.tier, "2")
		eq(bob.last_seen_date, realmDay(50)); eq(bob.last_seen_character, "Brom Hollowtree")
		eq(bob.last_seen_source, "game"); eq(bob.grouped_by_note, "no"); eq(bob.away_until, "")
		eq(bob.highest_rank, "Member")
		local ann = by(records, "main", "Ànnà")
		eq(ann.away_until, A().Absence.DayText(day(10)))
		local gone = by(records, "main", "Gone")
		eq(gone.days_inactive, ""); eq(gone.tier, ""); eq(gone.last_seen_date, ""); eq(gone.last_seen_source, "")
		local zoe = by(records, "main", "Zoë")
		eq(zoe.realm, "OtherRealm"); eq(zoe.characters, "Zoë-OtherRealm")
	end)

	it("exports what the page shows, with its filters and the search", function()
		fill()
		Mock.Slash("/accord officers")
		A().Shell:Select("officers")
		V().inactive.away, V().inactive.unknown = false, false
		V():OnSearch("bo")
		truthy(V():OpenExport("inactive"))
		local _, records = CSV.records(Box():GetText())
		eq(#records, 1); eq(records[1].main, "Bob")
	end)
end)

describe("Timeline", function()
	before_boot(function() guild() end)

	it("round-trips through a CSV reader: one row per merged event", function()
		fill()
		local records = csv("timeline")
		eq(#records, 6)
		local note = by(records, "to", "'=cmd|' /C calc'!A0")
		eq(note.name, "Ànnà"); eq(note.event, "note"); eq(note.from, "line one\nline two"); eq(note.observers, "1")
		eq(note.date_utc, date("!%Y-%m-%d %H:%M", GetServerTime() - 200))
		eq(note.since_utc, date("!%Y-%m-%d %H:%M", GetServerTime() - 800))
		local quoted = by(records, "from", 'old "quoted", text')
		eq(quoted.to, NOTES[BOB])
		local rank = by(records, "event", "rank")
		eq(rank.name, "Brom Hollowtree"); eq(rank.from, "Member, old"); eq(rank.to, "Initiate")
		local level = by(records, "event", "level")
		eq(level.name, "Zoë"); eq(level.realm, "OtherRealm"); eq(level.from, "20"); eq(level.to, "27")
		local join = by(records, "event", "join")
		eq(join.from, ""); eq(join.to, "")
		eq(by(records, "event", "leave").name, "Left Behind")
	end)

	it("exports the kind, the period and the account the page is filtered on", function()
		fill()
		Mock.Slash("/accord officers")
		A().Shell:Select("officers")
		V():ShowPage("timeline")
		V().timeline.kind = "rank"
		truthy(V():OpenExport("timeline"))
		local _, records = CSV.records(Box():GetText())
		eq(#records, 1); eq(records[1].event, "rank")
	end)
end)

describe("EXP-01: nothing secret", function()
	before_boot(function() guild() end)

	local function check(forbidden)
		local texts = 0
		for _, kind in ipairs(X().KINDS) do
			for _, format in ipairs(X().FORMATS) do
				local text, info = build(kind, format)
				truthy(info.rows > 0, kind .. " has rows")
				for what, needle in pairs(forbidden) do
					falsy(text:find(needle, 1, true), kind .. " " .. format .. " holds " .. what .. ": " .. needle)
				end
				texts = texts + 1
			end
		end
		eq(texts, 8)
	end

	it("no token, no GUID, no guild key, no officer note of either kind", function()
		fill()
		local mine = A().Config:Token()
		notNil(mine)
		check({ guid = "Player-", token = TOKEN, mine = mine, key = A().GuildKey:Current(), note = GAME_NOTE, extended = EXTENDED,
			contact = "bob_disc" })
	end)

	it("not even for a character nothing names", function()
		fill()
		local a = { chars = { "Player-1-0000DEAD" }, main = { guid = "Player-1-0000DEAD" }, name = "?", unknown = true }
		local text = X().Build("inactive", "csv", { a })
		falsy(text:find("Player-", 1, true))
	end)

	it("nor in a full demo guild", function()
		Mock.Slash("/accord demo")
		truthy(A().Demo:IsActive())
		local forbidden = { guid = "Player-" }
		local n = 0
		local function add(v)
			if type(v) == "string" and #v > 3 then n = n + 1 forbidden["secret " .. n] = v end
		end
		for _, rec in pairs(S():Records("accounts")) do add(rec.token) end
		for _, rec in pairs(S():Records("contacts")) do add(rec.account) end
		for _, rec in pairs(S():Records("onotes")) do add(rec.text) end
		for _, row in ipairs(A().Compat.Guild.Roster()) do add(row.officerNote) end
		add(A().Config:Token())
		truthy(n > 10, "the demo holds tokens and notes")
		check(forbidden)
	end)
end)

describe("EXP-05: Discord", function()
	before_boot(function() guild() end)

	local function parts(text)
		local out = {}
		for block in (text .. "\n\n"):gmatch("(.-\n```)\n\n") do out[#out + 1] = block end
		return out
	end

	it("is one code block with a title and aligned columns; backticks and mentions stay text", function()
		fill()
		local text = build("roster", "discord")
		local all = parts(text)
		eq(#all, 1)
		matches(text, "^```\nRoster · Accord · %d%d%d%d%-%d%d%-%d%d\nName ")
		matches(text, "\n```$")
		local _, fences = text:gsub("```", "")
		eq(fences, 2, "no backtick of a value closes the block")
		local lines = {}
		for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
		eq(#lines, 3 + 7 + 1)
		local column = X().Length(lines[3]:match("^(.-)Lvl"))
		for i = 4, 10 do
			local before = lines[i]:match("^(.-%s)%d%d%s")
			eq(X().Length(before), column, "aligned: " .. lines[i])
		end
	end)

	it("shows the events with from and to, long names and notes cut", function()
		fill()
		S():Records("timeline")[OFF .. ":" .. day() .. ":1"].ev = {
			event("note", BOB, "Bob", 100, { f = ("é"):rep(40), t = "`tick`" }),
			event("join", "Player-1-00000DEA", "Abcdefghij Klmnopqrstuvwxyz", 600, {}),
		}
		A().Timeline:Invalidate()
		local text = build("timeline", "discord")
		contains(text, ("é"):rep(29) .. "…\" → \"'tick'\"")
		falsy(text:find(("é"):rep(30), 1, true))
		contains(text, "Abcdefghij Klmnopqrstuv…")
		contains(text, "joined the guild")
	end)

	it("splits into parts of at most 1900 characters without breaking a row", function()
		local list = {}
		for i = 1, 150 do
			list[i] = { ev = { k = "join", g = BOB, n = "Bob", a = GetServerTime() - i, b = GetServerTime() - i, observers = {} }, name = "Bob" }
		end
		local text, info = X().Build("timeline", "discord", list)
		local all = parts(text)
		truthy(#all >= 3)
		eq(info.rows, 150); eq(info.left, 0)
		local counted = 0
		for i, block in ipairs(all) do
			truthy(X().Length(block) <= 1900, "part " .. i .. ": " .. X().Length(block))
			matches(block, "^```\n")
			contains(block, ("(%d/%d)"):format(i, #all))
			for line in block:gmatch("[^\n]+") do
				if line:find("joined the guild", 1, true) then
					matches(line, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d  Bob +joined the guild$")
					counted = counted + 1
				end
			end
		end
		eq(counted, 150)
	end)

	it("an account away has no tier, an unknown one says so", function()
		fill()
		local text = build("inactive", "discord")
		matches(text, "Gone[^\n]*" .. L()["INA_UNKNOWN"])
		falsy(text:match("Ànnà[^\n]*30%+"))
	end)
end)

describe("the size limit", function()
	before_boot(function() guild() end)

	it("keeps whole rows and counts the others, outside the text", function()
		fill()
		local whole = build("roster", "csv")
		for _, format in ipairs(X().FORMATS) do
			X().MAX_TEXT = 400
			local text, info = build("roster", format)
			truthy(#text <= 400, format .. " " .. #text)
			truthy(info.rows > 0 and info.left > 0, format .. " " .. info.rows .. " " .. info.left)
			eq(info.rows + info.left, 7)
			if format == "csv" then
				local _, records = CSV.records(text)
				eq(#records, info.rows)
				eq(whole:sub(1, #text), text, "the first rows, unchanged")
			end
		end
		Box():Open("roster", entries())
		local _, info = X().Build("roster", Box().format, entries())
		eq(Box().frame.status:GetText(), L()["EXPORT_LEFT_OUT"]:format(info.left))
		falsy(Box().frame.edit:GetText():find("left out", 1, true))
		X().MAX_TEXT = 262144
	end)
end)

describe("the box", function()
	before_boot(function() guild() end)

	it("shows the warning, the text selected and read-only, with | doubled (EXP-04)", function()
		fill()
		local text = Box():Open("roster", entries())
		truthy(Box():IsShown())
		eq(Box().frame.warning:GetText(), L()["EXPORT_WARNING"])
		eq(Box().format, "csv")
		eq(Box():GetText(), text)
		contains(text, "|cffff0000red|r")
		local shown = Box().frame.edit:GetText()
		contains(shown, "||cffff0000red||r")
		eq((shown:gsub("||", "|")), text)
		Box().frame.edit:SetText("typed over")
		Box().frame.edit:GetScript("OnTextChanged")(Box().frame.edit, true)
		eq(Box().frame.edit:GetText(), shown)
		Box():Hide()
		eq(Box().frame.edit:GetText(), "", "nothing of the text stays")
		isNil(Box():GetText())
	end)

	it("switches between CSV and Discord", function()
		fill()
		Box():Open("inactive", rows())
		Box().frame.formats.buttons.discord:Click()
		matches(Box():GetText(), "^```\nInactive accounts · Accord · ")
		eq(Box().frame.hint:GetText(), L()["EXPORT_HINT_DISCORD"])
		Box().frame.formats.buttons.csv:Click()
		matches(Box():GetText(), "^main,realm,")
	end)

	it("opens from the three pages for an officer", function()
		fill()
		Mock.Slash("/accord roster")
		local bar = RV().frame.toolbar
		truthy(bar.export:IsShown())
		bar.export:Click()
		matches(Box():GetText(), "^name,realm,")
		Box():Hide()
		A().Shell:Select("officers")
		V().frame.holders.inactive.export:Click()
		matches(Box():GetText(), "^main,realm,")
		Box():Hide()
		V():ShowPage("timeline")
		V().frame.holders.timeline.export:Click()
		matches(Box():GetText(), "^date_utc,")
	end)
end)

describe("officers and the Guild Master only (SPEC-10 Q13)", function()
	before_boot(function() guild(3) end)

	it("gives a member nothing: no button, no text, no box", function()
		fill()
		falsy(X().Allowed())
		for _, kind in ipairs(X().KINDS) do
			for _, format in ipairs(X().FORMATS) do
				local text, why = X().Build(kind, format, { A().Roster:ByGUID(BOB) })
				isNil(text); eq(why, "officer")
			end
		end
		isNil(Box():Open("roster", entries()))
		falsy(Box():IsShown())
		Mock.Slash("/accord roster")
		falsy(RV().frame.toolbar.export:IsShown())
		isNil(RV():OpenExport())
		isNil(V():OpenExport("inactive"))
		isNil(V():OpenExport("timeline"))
	end)

	it("lets the Guild Master export", function()
		Mock.guild.SetMyRank(0)
		A().Role:Refresh()
		fill()
		truthy(X().Allowed())
		notNil((build("roster", "csv")))
	end)

	it("shows the button on promotion and closes the box on demotion", function()
		fill()
		Mock.Slash("/accord roster")
		Mock.guild.SetMyRank(1)
		A().Role:Refresh()
		truthy(RV().frame.toolbar.export:IsShown())
		RV().frame.toolbar.export:Click()
		truthy(Box():IsShown())
		Mock.guild.SetMyRank(3)
		A().Role:Refresh()
		falsy(Box():IsShown())
		isNil(Box():GetText())
		falsy(RV().frame.toolbar.export:IsShown())
	end)
end)

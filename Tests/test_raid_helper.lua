-- Raid-Helper events from Discord (M10.6; SPEC-14 §6; ADR 0022 points 13-14): the reader of the pasted JSON and CSV (every
-- state, unknown fields ignored, broken, unknown and oversized text refused, nothing run); the matching by Discord name
-- across alts and the hand match; the names that matched nobody kept on this computer only and dropped after the event;
-- the record H: and its trust rules (officers only); the write into a fake game calendar (Tests/mock/62_calendar.lua)
-- with and without permission, never over an answer given in the game, at most 40 members per confirmation, one call at
-- a time; the Action Center row; the Events view, the export back to Discord and the paste box; the switch off.
-- Every name here is invented.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function C() return AzerothAccord.Calendar end
local function R() return AzerothAccord.RaidHelper end
local function T() return AzerothAccord.RaidHelperText end
local function V() return AzerothAccord.EventsView end
local function Box() return AzerothAccord.RaidHelperBox end

local ME = "Player-1-0000A001"
local TILDA, ORSO, PASTELLO = "Player-1-0000B001", "Player-1-0000B002", "Player-1-0000B003"
local NUVOLA, RUGGINE, CAPITANO = "Player-1-0000B004", "Player-1-0000B005", "Player-1-0000B006"
local QUERCIA, MUSCHIO, OFF = "Player-1-0000B007", "Player-1-0000B008", "Player-1-0000B009"
local DAY = 86400

local function minute(t) return t - t % 60 end

local MEMBERS = {
	{ name = "Tilda", class = "WARRIOR", rank = 3, guid = TILDA },
	{ name = "Orsetto", class = "MAGE", rank = 3, guid = ORSO },
	{ name = "Pastello", class = "PRIEST", rank = 3, guid = PASTELLO },
	{ name = "Nuvola", class = "DRUID", rank = 3, guid = NUVOLA },
	{ name = "Ruggine", class = "ROGUE", rank = 3, guid = RUGGINE, discord = "rusty_r" },
	{ name = "Capitano", class = "PALADIN", rank = 3, guid = CAPITANO },
	{ name = "Quercia", class = "HUNTER", rank = 3, guid = QUERCIA },
	{ name = "Muschio", class = "SHAMAN", rank = 3, guid = MUSCHIO },
	{ name = "Ufficiale", class = "PALADIN", rank = 1, guid = OFF },
}

local function setup(myRank, cfg, features, members)
	return function(M)
		M.features = features or { season = true }
		M.club.fill.discord = true
		M.guild.Set{ name = "Accord", myRank = myRank or 1, members = members or MEMBERS }
		M.calendar.Set(cfg or {})
	end
end

-- Orsetto and Pastello are one account; Orsetto shares the Discord name "orso", Nuvola "cloudy.n".
local function ready()
	Mock.Advance(15)
	local t = GetServerTime()
	for _, g in ipairs({ ORSO, PASTELLO }) do
		S():Records("accounts")[g] = { id = g, author = g, rev = 1, time = t, token = "TO", chars = { { guid = ORSO }, { guid = PASTELLO } } }
	end
	S():Records("contacts")[ORSO] = { id = ORSO, author = ORSO, rev = 1, time = t, account = "TO", discord = "orso" }
	S():Records("contacts")[NUVOLA] = { id = NUVOLA, author = NUVOLA, rev = 1, time = t, account = "TN", discord = "cloudy.n" }
	A().Accounts:MarkDirty()
end

local function startAt() return minute(GetServerTime()) + 2 * DAY end

local function json(start, id)
	return ([==[{"id":"%s","title":"Notte di Naxx","description":"whatever","leaderName":"Capo","startTime":%d,"endTime":%d,
"classes":[{"name":"Tank","specs":[{"name":"Protection"}]}],"roles":[],"someNewField":{"a":[1,2.5,-3e2,{"b":null,"c":false}]},
"signUps":[
 {"name":"Tilda","userId":"100000000000000001","className":"Tank","specName":"Protection","roleName":"Tanks","status":"primary","position":1,"entryTime":1,"extra":true},
 {"name":"@Orso","className":"Priest","specName":"Holy","roleName":"Healers","status":"primary","position":2},
 {"name":"cloudy.n","className":"Late","specName":"Restoration","roleName":"Healers","status":"primary","position":3},
 {"name":"Rusty_R#0000","className":"Bench","specName":"Combat","roleName":"Melee","status":"primary","position":4},
 {"name":"Capitano","className":"Tentative","position":5},
 {"name":"Quercia","className":"Absence","position":6},
 {"name":"Forestiero","className":"Mage","specName":"Frost","roleName":"Ranged","status":"primary","position":7}
]}]==]):format(id or "1234567890123456789", start, start + 10800)
end

local function import(start, id)
	local preview, event = R():Check(json(start or startAt(), id))
	truthy(preview, tostring(event))
	local done, why = R():Import(event)
	truthy(done, tostring(why))
	return done
end

local function stateOf(rec, guid)
	for _, e in ipairs(rec.s) do
		if e.g == guid then return e.st, e end
	end
	return nil
end

local function names(list)
	local out = {}
	for i, n in ipairs(list) do out[i] = (n:match("^([^%-]+)")) end
	table.sort(out)
	return table.concat(out, ",")
end

local function writes(call)
	local out = {}
	for _, w in ipairs(Mock.calendar.writes) do
		if w.call == call then out[#out + 1] = w end
	end
	return out
end

-- The invite status of a character in a calendar event of the fake client.
local function inviteOf(e, name)
	for _, i in ipairs(e.invites or {}) do
		if i.name:match("^([^%-]+)") == name then return i.inviteStatus end
	end
	return nil
end

local function lines(key)
	local out = {}
	for _, l in ipairs(V().Lines(V().Model(key))) do out[#out + 1] = l.text end
	return table.concat(out, "\n")
end

describe("reading an export", function()
	before_boot(setup(1))

	it("reads the title, the start and every state of a JSON export, ignoring what it does not know", function()
		local ev = T().Parse(json(1800000000))
		truthy(ev)
		eq(ev.format, "json"); eq(ev.id, "1234567890123456789"); eq(ev.title, "Notte di Naxx"); eq(ev.start, 1800000000)
		eq(#ev.signups, 7)
		local s = ev.signups
		eq(s[1].name, "Tilda"); eq(s[1].state, "signed"); eq(s[1].role, "tank"); eq(s[1].spec, "PROTECTION")
		isNil(s[1].class, "a Tank row names no class")
		truthy(s[1].classes.WARRIOR); truthy(s[1].classes.PALADIN); isNil(s[1].classes.MAGE)
		eq(s[2].class, "PRIEST"); eq(s[2].role, "healer"); eq(s[2].spec, "HOLY")
		eq(s[3].state, "late"); eq(s[4].state, "bench"); eq(s[5].state, "tentative"); eq(s[6].state, "absence")
		isNil(s[5].role)
	end)

	it("knows queued and secondary sign-ups, milliseconds, and the spec's own role", function()
		local ev = T().Parse([==[{"title":"A\u0000b | c","startTime":1800000000000,"signUps":[
			{"name":"Due","className":"Druid","specName":"Guardian","status":"secondary"},
			{"name":"Uno","className":"Warrior","specName":"Protection1","status":"queued"},
			{"className":"Mage"}, "text"]}]==])
		truthy(ev)
		eq(ev.start, 1800000000); isNil(ev.id)
		eq(ev.title, "A b || c", "control characters out, | doubled")
		eq(ev.ignored, 2)
		eq(ev.signups[1].name, "Uno", "the primary sign-ups first"); eq(ev.signups[1].state, "bench")
		eq(ev.signups[1].spec, "PROTECTION"); eq(ev.signups[1].role, "tank")
		eq(ev.signups[2].spec, "FERAL"); eq(ev.signups[2].role, "tank"); falsy(ev.signups[2].primary)
	end)

	it("cuts a long text at 64 characters, never inside a character", function()
		local ev = T().Parse(('{"title":"%s","startTime":1800000000,"signUps":[]}'):format(("é"):rep(100)))
		eq(ev.title, ("é"):rep(64))
	end)

	it("reads a CSV export by its header, with quotes and other columns", function()
		local ev = T().Parse('Name;Class;Spec;Role;Status;Note\r\nTilda;Warrior;Arms;Melee;;"yes; ""sure"""\r\n' ..
			'"Orso";Priest;Shadow;Ranged;Tentative;x\r\n\r\nQuercia;Absence;;;;\r\n;Mage;;;;\r\n')
		truthy(ev)
		eq(ev.format, "csv"); isNil(ev.title); isNil(ev.start)
		eq(#ev.signups, 3); eq(ev.ignored, 1)
		eq(ev.signups[1].state, "signed"); eq(ev.signups[1].class, "WARRIOR"); eq(ev.signups[1].spec, "ARMS")
		eq(ev.signups[2].state, "tentative"); eq(ev.signups[2].role, "ranged")
		eq(ev.signups[3].state, "absence")
		local comma = T().Parse("discord name,state\nNuvola,late")
		eq(comma.signups[1].state, "late")
	end)

	it("takes a pipe the edit box doubled", function()
		local ev = T().Parse('{"title":"A || B","startTime":1800000000,"signUps":[]}')
		eq(ev.title, "A || B")
	end)

	it("refuses broken, unknown and oversized text with the reason, and runs nothing", function()
		local function why(text)
			local ev, reason = T().Parse(text)
			isNil(ev, tostring(text):sub(1, 40))
			return reason
		end
		eq(why(""), "empty"); eq(why("  \n "), "empty"); eq(why(nil), "empty")
		eq(why('{"title":"x","signUps":['), "broken")
		eq(why('{"title":"x","signUps":[]} and more'), "broken")
		eq(why('{"title":"x","signUps":[],}'), "broken")
		eq(why('{"title":"x\nx","signUps":[]}'), "broken")
		eq(why('{"title":"\\ud800","signUps":[]}'), "broken")
		eq(why('{"title":os.exit(),"signUps":[]}'), "broken")
		eq(why('{"title":"x"}'), "unknown")
		eq(why('{"signUps":[]}'), "unknown")
		eq(why('{"title":"x","signUps":{"a":1}}'), "unknown")
		eq(why('{"title":"x","signUps":[{"userId":"1"}]}'), "unknown")
		eq(why('[1,2]'), "unknown")
		eq(why("<html><body></body></html>"), "unknown")
		eq(why("os.exit() -- run me"), "unknown")
		eq(why("a,b,c\n1,2,3"), "unknown")
		eq(why("Name,Note\nTilda,x"), "unknown")
		eq(why("Name,Role\n"), "unknown")
		eq(why('Name,Role\n"Tilda,Tank'), "broken")
		eq(why("Name,Role\nTilda,Tank,extra"), "broken")
		eq(why(("x"):rep(T().MAX_TEXT + 1)), "long")
		eq(why('{"title":"x","signUps":[],"a":' .. ("["):rep(9) .. ("]"):rep(9) .. "}"), "deep")
		truthy(T().Parse('{"title":"x","signUps":[],"a":' .. ("["):rep(7) .. ("]"):rep(7) .. "}"))
		local many = {}
		for i = 1, 201 do many[i] = ('{"name":"N%d"}'):format(i) end
		eq(why('{"title":"x","signUps":[' .. table.concat(many, ",") .. "]}"), "many")
		local rows = { "Name,Role" }
		for i = 1, 201 do rows[#rows + 1] = "N" .. i .. ",Tank" end
		eq(why(table.concat(rows, "\n")), "many")
	end)
end)

describe("matching and importing", function()
	before_boot(setup(1))

	it("matches by hand, Discord name and character name, to the character of the account with the class", function()
		ready()
		local start = startAt()
		local preview, event = R():Check(json(start))
		truthy(preview, tostring(event))
		eq(#preview.signups, 6)
		eq(names(preview.unmatched), "Forestiero")
		local id = R():Import(event)
		eq(id, "1234567890123456789")
		local rec = R():Get(id)
		eq(rec.title, "Notte di Naxx"); eq(rec.start, start); eq(rec.at, GetServerTime()); eq(rec.author, ME)
		eq(stateOf(rec, TILDA), "signed", "by character name")
		local st, e = stateOf(rec, PASTELLO)
		eq(st, "signed", "the priest of Orsetto's account"); eq(e.role, "healer"); eq(e.class, "PRIEST")
		isNil(stateOf(rec, ORSO))
		eq(stateOf(rec, NUVOLA), "late", "by the shared Discord name")
		eq(stateOf(rec, RUGGINE), "bench", "by the game's Discord name")
		eq(stateOf(rec, CAPITANO), "tentative"); eq(stateOf(rec, QUERCIA), "absence")
		local _, tilda = stateOf(rec, TILDA)
		eq(tilda.class, "WARRIOR", "a Tank row takes the member's class")
	end)

	it("counts an account once, and matches nobody with a name of two accounts", function()
		ready()
		S():Records("contacts")[MUSCHIO] = { id = MUSCHIO, author = MUSCHIO, rev = 1, time = GetServerTime(), account = "TM", discord = "cloudy.n" }
		local preview = R():Check("Name,Class\norso,Mage\nPastello,Priest\ncloudy.n,Druid", { title = "Doppio", start = startAt() })
		eq(#preview.signups, 1); eq(preview.signups[1].guid, ORSO); eq(preview.twice, 1)
		eq(preview.ambiguous, 1); eq(names(preview.unmatched), "cloudy.n")
	end)

	it("needs a title and a start for a CSV, and refuses an old date", function()
		ready()
		local _, why = R():Check("Name,Role\nTilda,Tank")
		eq(why, "title")
		_, why = R():Check("Name,Role\nTilda,Tank", { title = "Serata" })
		eq(why, "start")
		_, why = R():Check("Name,Role\nTilda,Tank", { title = "Serata", start = GetServerTime() - 3 * DAY })
		eq(why, "start")
		local start = startAt()
		local preview, event = R():Check("Name,Role\nTilda,Tank", { title = "Serata", start = start })
		truthy(preview)
		local id = R():Import(event, { title = "Serata", start = start })
		eq(id, "t" .. start)
		eq(R():Get(id).title, "Serata")
		-- the same date and time again replaces it
		eq(R():Import(event, { title = "Serata 2", start = start }), id)
		eq(#R():List(), 1); eq(R():Get(id).title, "Serata 2")
	end)

	it("reads the start in the realm's clock", function()
		ready()
		local now = GetServerTime()
		C_DateAndTime = C_DateAndTime or {}
		local old = C_DateAndTime.GetCurrentCalendarTime
		C_DateAndTime.GetCurrentCalendarTime = function()
			local d = date("!*t", now + 3600)
			return { year = d.year, month = d.month, monthDay = d.day, hour = d.hour, minute = d.min }
		end
		local start = startAt()
		eq(R().RealmStart(start), start + 3600)
		C_DateAndTime.GetCurrentCalendarTime = old
	end)

	it("keeps the unmatched names on this computer only, and drops them after the event", function()
		ready()
		local start = startAt()
		local id = import(start)
		eq(names(R():Unmatched(id)), "Forestiero")
		local function has(t)
			if type(t) ~= "table" then return tostring(t):find("Forestiero") ~= nil end
			for k, v in pairs(t) do
				if has(k) or has(v) then return true end
			end
			return false
		end
		local data = A().GuildKey:Data()
		falsy(has(data.store), "nothing of it in a synced record")
		truthy(has(data.raidHelper))
		falsy(has(A().Backup:Content()))
		for _, l in ipairs(R():DebugLines()) do falsy(l:find("Forestiero")) end
		Mock.SetServerTime(start + 2 * DAY - 60)
		eq(#R():Unmatched(id), 1)
		Mock.SetServerTime(start + 2 * DAY + 60)
		eq(#R():Unmatched(id), 0)
		falsy(has(data.raidHelper))
	end)

	it("remembers a hand match, applies it, and forgets it when the character left the guild", function()
		ready()
		local id = import()
		local ok, why = R():SetMatch(id, "Forestiero", "Nessuno")
		falsy(ok); eq(why, "member")
		ok, why = R():SetMatch(id, "Forestiero", "Muschio")
		truthy(ok, why); eq(why, "added")
		eq(stateOf(R():Get(id), MUSCHIO), "signed")
		eq(#R():Unmatched(id), 0)
		eq(A().GuildKey:Data().raidHelper.manual.forestiero, MUSCHIO)
		-- a later event
		local other = import(startAt() + DAY, "999")
		eq(stateOf(R():Get(other), MUSCHIO), "signed")
		-- after a reload the export is not in memory any more
		R():Reset()
		ok, why = R():SetMatch(id, "Qualcuno", "Tilda")
		truthy(ok); eq(why, "paste")
		local rest = {}
		for _, m in ipairs(MEMBERS) do
			if m.guid ~= MUSCHIO then rest[#rest + 1] = m end
		end
		Mock.guild.Set{ name = "Accord", myRank = 1, members = rest }
		Mock.Advance(15)
		R():Prune()
		isNil(A().GuildKey:Data().raidHelper.manual.forestiero)
		eq(A().GuildKey:Data().raidHelper.manual.qualcuno, TILDA)
	end)

	it("takes the record only from officers, and refuses a wrong one", function()
		ready()
		local t = GetServerTime()
		local function rec(extra)
			local r = { id = "H:55", author = OFF, rev = 1, time = t, title = "A || B", start = t + DAY, at = t,
				s = { { g = TILDA, st = "signed", role = "tank", class = "WARRIOR", spec = "PROTECTION" } } }
			for k, v in pairs(extra or {}) do r[k] = v end
			return r
		end
		local ok, why = S():Accept("raidev", rec({ author = TILDA }), { sender = "Tilda" })
		falsy(ok); eq(why, "authority")
		for _, bad in ipairs({ { id = "H:abc" }, { title = "A | B" }, { title = "" }, { start = "x" }, { s = "x" },
			{ s = { { g = "x", st = "signed" } } }, { s = { { g = TILDA, st = "maybe" } } },
			{ s = { { g = TILDA, st = "signed" }, { g = TILDA, st = "late" } } },
			{ s = { { g = TILDA, st = "signed", role = "boss" } } } }) do
			falsy(S():Accept("raidev", rec(bad), { sender = "Ufficiale" }))
		end
		local many = {}
		for i = 1, 81 do many[i] = { g = ("Player-1-%08X"):format(i), st = "signed" } end
		falsy(S():Accept("raidev", rec({ s = many }), { sender = "Ufficiale" }))
		truthy(S():Accept("raidev", rec(), { sender = "Ufficiale" }))
		truthy(C().Expired(rec({ start = t - 3 * DAY }), t))
		falsy(C().Expired(rec({ at = t - 3 * DAY }), t))
		-- the other records of the set keep their small size
		ok = S():Accept("raidev", { id = "F:" .. OFF .. ":1", author = OFF, rev = 1, time = t, title = "Raid", start = t + DAY,
			size = 40, junk = ("x"):rep(600) }, { sender = "Ufficiale" })
		falsy(ok)
	end)

	it("holds 80 matched members in one record", function()
		local record = { id = "H:1234567890123456789", author = "Player-5818-0A1B2C3D", rev = 100, time = GetServerTime(),
			title = ("é"):rep(64), start = GetServerTime(), at = GetServerTime(), s = {} }
		for i = 1, 80 do
			record.s[i] = { g = ("Player-5818-%08X"):format(i), st = "tentative", role = "healer", class = "WARLOCK", spec = "BEAST_MASTERY" }
		end
		truthy(R().ValidRecord(record))
		truthy(A().Config.EstimateSize(record) <= R().MAX_BYTES, tostring(A().Config.EstimateSize(record)))
		eq(S().SETS.raidev.maxBytes, R().MAX_BYTES)
		-- and goes through the codec in one message
		local wire = A().Codec:Encode("REC", { s = "raidev", r = { record } })
		truthy(wire)
		local msg, why = A().Codec:Decode(wire)
		truthy(msg, tostring(why)); eq(#msg.r[1].s, 80)
	end)
end)

describe("into the game calendar", function()
	before_boot(setup(1))

	it("creates the event after the confirmation, invites the matched members and writes their state, one call at a time", function()
		ready()
		local start = startAt()
		local id = import(start)
		eq(#Mock.calendar.writes, 0, "importing writes nothing into the calendar")
		local plan = R():Plan(id)
		truthy(plan.create); eq(plan.members, 6)
		truthy(R():Push(id))
		Mock.Advance(30)
		local res = R().result[id]
		truthy(res.ok, tostring(res.why)); truthy(res.created); eq(res.invited, 6); eq(#res.written, 6); eq(#res.left, 0)
		local e = Mock.calendar.events[1]
		eq(e.title, "Notte di Naxx"); eq(e.at, start); eq(e.calendarType, "GUILD_EVENT"); eq(e.eventType, 0)
		eq(e.description, "Imported from Raid-Helper")
		local st = Mock.calendar.STATUS
		eq(inviteOf(e, "Tilda"), st.Confirmed); eq(inviteOf(e, "Pastello"), st.Confirmed)
		eq(inviteOf(e, "Nuvola"), st.Confirmed); eq(inviteOf(e, "Ruggine"), st.Confirmed)
		eq(inviteOf(e, "Capitano"), st.Tentative); eq(inviteOf(e, "Quercia"), st.Declined)
		isNil(inviteOf(e, "Muschio"), "only the matched members")
		eq(#writes("AddEvent"), 1); eq(#writes("EventInvite"), 6); eq(#writes("EventSetInviteStatus"), 6)
		eq(Mock.calendar.maxFlight, 1)
		isNil(Mock.calendar.open); isNil(C().open); isNil(R().job)
		-- a second confirmation finds nothing to do
		truthy(R():Push(id))
		Mock.Advance(10)
		eq(#Mock.calendar.writes, 13)
	end)

	it("uses the event of that date and time and never changes an answer given in the game", function()
		local start = startAt()
		local st = Mock.calendar.STATUS
		local e = Mock.calendar.Add{ eventID = 201, title = "Naxx", at = start, mine = true, invites = {
			{ name = "Tilda", guid = TILDA, classFilename = "WARRIOR", inviteStatus = st.Declined },
			{ name = "Nuvola", guid = NUVOLA, classFilename = "DRUID", inviteStatus = st.Signedup },
			{ name = "Ruggine", guid = RUGGINE, classFilename = "ROGUE", inviteStatus = st.Invited },
			{ name = "Muschio", guid = MUSCHIO, classFilename = "SHAMAN", inviteStatus = st.Signedup },
		} }
		ready()
		local id = import(start)
		local plan = R():Plan(id)
		falsy(plan.create)
		truthy(R():Push(id))
		Mock.Advance(30)
		local res = R().result[id]
		truthy(res.ok, tostring(res.why)); falsy(res.created)
		eq(inviteOf(e, "Tilda"), st.Declined); eq(inviteOf(e, "Nuvola"), st.Signedup)
		eq(inviteOf(e, "Ruggine"), st.Confirmed)
		eq(names(res.answered), "Nuvola,Tilda")
		eq(res.invited, 3)
		eq(#writes("AddEvent"), 0)
		for _, w in ipairs(Mock.calendar.writes) do truthy(w.name ~= "Tilda" and w.name ~= "Nuvola") end
		-- who is where
		local cmp = R():Compare(R():Get(id), C():Event("c201"))
		truthy(cmp, "the answers were read when the write ended")
		eq(names(cmp.onlyGame), "Muschio")
		eq(#cmp.onlyDiscord, 0)
		eq(#cmp.differ, 1); eq(cmp.differ[1].name:match("^([^%-]+)"), "Tilda"); eq(cmp.differ[1].game, "no")
	end)

	it("only invites where it may not write a state, and says who answers in the game", function()
		ready()
		Mock.calendar.Set({ status = false })
		local id = import()
		truthy(R():Push(id))
		Mock.Advance(30)
		local res = R().result[id]
		truthy(res.ok, tostring(res.why))
		eq(res.invited, 6); eq(#res.written, 0); eq(#res.member, 6)
		eq(#writes("EventSetInviteStatus"), 0)
		eq(inviteOf(Mock.calendar.events[1], "Tilda"), Mock.calendar.STATUS.Invited)
	end)

	it("invites nobody where invites are not allowed", function()
		ready()
		Mock.calendar.Set({ invite = false })
		local id = import()
		truthy(R():Push(id))
		Mock.Advance(30)
		eq(#writes("EventInvite"), 0); eq(#writes("EventSetInviteStatus"), 0)
		eq(#R().result[id].member, 6)
	end)

	it("says when it cannot create or edit the event, or may not open it now", function()
		ready()
		local start = startAt()
		local id = import(start)
		Mock.calendar.Set({ create = false })
		local plan, why = R():Plan(id)
		isNil(plan); eq(why, "nocreate")
		Mock.calendar.Set({})
		Mock.calendar.ShowFrame(true)
		_, why = R():Plan(id)
		eq(why, "shown")
		Mock.calendar.ShowFrame(false)
		Mock.Fire("ENCOUNTER_START", 1, "Boss", 9, 40)
		_, why = R():Plan(id)
		eq(why, "encounter")
		Mock.Fire("ENCOUNTER_END", 1, "Boss", 9, 40, 1)
		Mock.calendar.Add{ eventID = 301, title = "Not mine", at = start }
		Mock.calendar.Set({ edit = false })
		truthy(R():Push(id))
		Mock.Advance(20)
		eq(R().result[id].why, "noedit"); eq(#R().result[id].left, 6)
		eq(#Mock.calendar.writes, 0)
		isNil(Mock.calendar.open)
	end)

	it("stops at an error of the server and says who was left out", function()
		ready()
		Mock.calendar.Set({ refuseWrite = 4 })
		local id = import()
		truthy(R():Push(id))
		Mock.Advance(30)
		local res = R().result[id]
		falsy(res.ok); eq(res.why, "error")
		eq(#Mock.calendar.writes, 4, "nothing after the refusal")
		eq(#res.written, 1); eq(#res.left, 5)
		isNil(R().job); isNil(C().open); isNil(Mock.calendar.open)
	end)

	it("stops when the server does not answer, and when the game's window opens", function()
		ready()
		Mock.calendar.Set({ silentWrite = 2 })
		local id = import()
		truthy(R():Push(id))
		local ok, why = R():Push(id)
		falsy(ok); eq(why, "busy")
		Mock.Advance(30)
		eq(R().result[id].why, "timeout"); eq(#Mock.calendar.writes, 2)
		isNil(R().job)
		Mock.calendar.pending = false
		Mock.calendar.flight = 0
		Mock.calendar.Set({})
		truthy(R():Push(id))
		Mock.calendar.ShowFrame(true)
		Mock.Advance(30)
		eq(R().result[id].why, "shown")
	end)

	it("is refused by a client that protects the calls, without looping", function()
		ready()
		Mock.calendar.Set({ protected = true })
		local id = import()
		local ok, why = R():Push(id)
		falsy(ok); eq(why, "blocked")
		eq(#Mock.calendar.writes, 0)
		isNil(R().job); isNil(C().open)
	end)

	it("says when the day already has another raid event", function()
		ready()
		local start = startAt()
		Mock.calendar.Add{ eventID = 401, title = "Prima serata", at = start + 3600, eventType = 0 }
		local id = import(start)
		local plan = R():Plan(id)
		truthy(plan.create); eq(plan.other, "Prima serata")
		contains(V().ConfirmText(plan), "first raid event of the day")
	end)
end)

describe("at most 40 members per confirmation", function()
	local many = {}
	for i = 1, 45 do many[i] = { name = ("Soldato%02d"):format(i), class = "WARRIOR", rank = 3, guid = ("Player-1-0000C%03d"):format(i) } end
	before_boot(setup(1, {}, nil, many))

	it("writes 40, leaves the rest for the next one", function()
		Mock.Advance(15)
		local rows = { "Name,Role" }
		for i = 1, 45 do rows[#rows + 1] = ("Soldato%02d,Melee"):format(i) end
		local start = startAt()
		local _, event = R():Check(table.concat(rows, "\n"), { title = "Grande", start = start })
		local id = R():Import(event, { title = "Grande", start = start })
		eq(#R():Get(id).s, 45)
		local plan = R():Plan(id)
		eq(plan.members, 40); eq(plan.total, 45)
		truthy(R():Push(id))
		Mock.Advance(120)
		local res = R().result[id]
		truthy(res.ok, tostring(res.why))
		eq(#writes("EventInvite"), 40); eq(res.invited, 40); eq(#res.left, 5)
		truthy(R():Push(id))
		Mock.Advance(60)
		eq(#writes("EventInvite"), 45); eq(#R().result[id].left, 0)
	end)
end)

describe("a member's client", function()
	before_boot(setup(3))

	local function received(start)
		local t = GetServerTime()
		truthy(S():Accept("raidev", { id = "H:77", author = OFF, rev = 1, time = t, title = "Notte di Naxx", start = start, at = t,
			s = { { g = ME, st = "late", role = "melee", class = "WARRIOR" }, { g = TILDA, st = "signed", role = "tank" } } },
			{ sender = "Ufficiale" }))
	end

	it("cannot import, match or write", function()
		ready()
		received(startAt())
		local _, why = R():Check(json(startAt()))
		eq(why, "officer")
		_, why = R():Import({ signups = {} })
		eq(why, "officer")
		_, why = R():SetMatch("77", "x", "Tilda")
		eq(why, "officer")
		_, why = R():Plan("77")
		eq(why, "officer")
		_, why = Box():Open()
		eq(why, "officer")
	end)

	it("sees the own state on Discord, and nothing of the officers' lists", function()
		ready()
		received(startAt())
		local t = lines("h77")
		contains(t, "You on Discord: Late"); contains(t, "melee dps"); contains(t, "Not in the game calendar yet")
		falsy(t:find("Tilda"), "no list of the others")
		falsy(t:find("Not matched"))
		falsy(V().Model("h77").officer)
	end)

	it("finds a row in the Action Center until the game calendar has an answer", function()
		local start = startAt()
		Mock.calendar.Add{ eventID = 501, title = "Notte di Naxx", at = start }
		ready()
		received(start)
		local rows = R():ActionRows()
		eq(#rows, 1)
		eq(rows[1].title, "Answer in the game calendar: Notte di Naxx"); eq(rows[1].detail, "On Discord: Late")
		eq(rows[1].key, "h77")
		truthy(A().Actions.providers.events)
		rows[1].open()
		eq(V().chosen, "c501")
		truthy(Mock.calendar.GameAnswer(501, Mock.calendar.STATUS.Signedup))
		eq(#R():ActionRows(), 0)
	end)
end)

describe("the Events view of an officer", function()
	before_boot(setup(1))

	it("shows the sign-ups, the roles next to the season and the target, and both differences", function()
		local start = startAt()
		local st = Mock.calendar.STATUS
		Mock.calendar.Add{ eventID = 601, title = "Notte di Naxx", at = start, mine = true, invites = {
			{ name = "Muschio", guid = MUSCHIO, classFilename = "SHAMAN", inviteStatus = st.Signedup },
			{ name = "Tilda", guid = TILDA, classFilename = "WARRIOR", inviteStatus = st.Signedup },
		} }
		ready()
		truthy(A().Season:Open("Naxx"))
		truthy(A().Composition:SetTarget({ size = 40, tank = 4, healer = 8, melee = 10, ranged = 10 }))
		local id = import(start)
		local m = V().Model("c601")
		eq(m.event.importId, id)
		eq(#m.events, 1, "the import shows with its calendar event")
		eq(V().Model("h" .. id).event.key, "c601")
		V():Choose("c601")
		Mock.Advance(2)
		local t = lines("c601")
		contains(t, "From Discord (Raid-Helper)")
		contains(t, "Tank: 1 · season MS1 0 · target 4")
		contains(t, "Healers: 2 · season MS1 0 · target 8")
		contains(t, "Late (1)"); contains(t, "Bench (1)"); contains(t, "Absence (1)")
		contains(t, "On Discord, not in the game calendar (4)")
		contains(t, "In the game calendar, not on Discord (1)")
		contains(t, "Not matched to a member (1)"); contains(t, "Forestiero")
	end)

	it("writes only after the second click, and exports back to Discord", function()
		ready()
		local id = import()
		V():Choose("h" .. id)
		local ok, why = V():Push()
		falsy(ok); eq(why, "confirm"); contains(V().said, "Create the event in the game calendar and invite 6 members?")
		eq(#Mock.calendar.writes, 0)
		ok = V():Push()
		truthy(ok)
		Mock.Advance(30)
		truthy(R().result[id].ok)
		local key = "c" .. Mock.calendar.events[1].eventID
		V():Choose(key)
		Mock.Advance(2)
		contains(lines(key), "Done: 6 invited, 6 answers written.")
		local text = V():Export()
		truthy(text)
		contains(text, "name,realm,class,role,game_answer,discord")
		contains(text, "Tilda,,WARRIOR,tank,yes,signed")
		contains(text, "Quercia,,HUNTER,,no,absence")
		A().ExportBox:SetFormat("discord")
		contains(A().ExportBox:GetText(), "Notte di Naxx")
		contains(A().ExportBox:GetText(), "Event sign-ups")
	end)

	it("checks and imports from the box, which forgets the text", function()
		ready()
		truthy(Box():Open())
		local f = Box().frame
		falsy(f.import:IsEnabled())
		f.edit:SetText("nonsense")
		local _, why = Box():Check()
		eq(why, "unknown"); contains(f.status:GetText(), "not a Raid-Helper event export")
		f.edit:SetText(json(startAt()))
		truthy(Box():Check())
		contains(f.status:GetText(), "Members matched: 6"); contains(f.status:GetText(), "Forestiero")
		truthy(f.import:IsEnabled())
		local id = Box():Import()
		truthy(id); falsy(Box():IsShown()); eq(f.edit:GetText(), "")
		eq(V().chosen, "h" .. id)
	end)

	it("matches a name by hand from the view", function()
		ready()
		local id = import()
		V():Choose("h" .. id)
		local ok, why = V():Match("Forestiero", "Muschio")
		truthy(ok, why); eq(stateOf(R():Get(id), MUSCHIO), "signed")
	end)

	it("draws the officer's buttons and the hand match in the view", function()
		ready()
		local id = import()
		truthy(V():Open("h" .. id))
		local f = V().frame
		truthy(f, "the view was built")
		V():Redraw()
		truthy(f.rhRow:IsShown()); truthy(f.import:IsShown()); truthy(f.push:IsShown()); truthy(f.export:IsShown())
		falsy(f.answer:IsShown(), "no answer to an event that is only on Discord")
		truthy(f.matchRow:IsShown())
		f.unmatched:Select("Forestiero")
		f.member:SetText("Muschio")
		f.match:Click()
		eq(stateOf(R():Get(id), MUSCHIO), "signed")
		falsy(f.matchRow:IsShown(), "nobody left to match")
		f.push:Click()
		eq(f.push:GetLabel(), "Confirm")
		f.push:Click()
		Mock.Advance(30)
		truthy(R().result[id].ok, tostring(R().result[id].why))
		f.import:Click()
		truthy(Box():IsShown())
	end)
end)

describe("with the switch season off", function()
	before_boot(setup(1, {}, {}))

	it("imports, writes, accepts and shows nothing", function()
		ready()
		local _, why = R():Check(json(startAt()))
		eq(why, "off")
		local ok
		ok, why = R():Push("1")
		falsy(ok); eq(why, "off")
		local t = GetServerTime()
		ok, why = S():Accept("raidev", { id = "H:77", author = OFF, rev = 1, time = t, title = "x", start = t + DAY, at = t, s = {} },
			{ sender = "Ufficiale" })
		falsy(ok); eq(why, "set")
		eq(#R():List(), 0); eq(#R():ActionRows(), 0)
		eq(#Mock.calendar.writes, 0)
		isNil(A().GuildKey:Data().raidHelper)
	end)
end)

-- The /accord debug report in a guild full of names (M6.4): it holds none of them, whatever the modules have stored; a
-- name inside an error message is replaced by a placeholder; the header carries the facts the bug report form asks for;
-- the report is capped; the box shows its size.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end

local ME = "Player-1-0000A001"
local JAINA, GARROSH, THRALL = "Player-1-00000B01", "Player-1-00000B02", "Player-1-00000B03"
local NAMES = { "Jainaxx", "Garroshx", "Thrallz", "Frostwolvesx", "jaina_discord", "garrosh_discord", "Hero#1234", "Jainaxx#4321" }

local function populate()
	Mock.player.battleTag = "Hero#1234"
	Mock.club.fill.professions, Mock.club.fill.discord = true, true
	Mock.guild.Set{ name = "Frostwolvesx", myRank = 1, members = {
		{ name = "Jainaxx", level = 60, class = "MAGE", rank = 1, guid = JAINA, discord = "jaina_discord", note = "main: Thrallz" },
		{ name = "Garroshx", level = 60, class = "WARRIOR", rank = 3, guid = GARROSH, discord = "garrosh_discord", officerNote = "ask Jainaxx" },
		{ name = "Thrallz", level = 30, class = "SHAMAN", rank = 4, guid = THRALL, note = "alt of Jainaxx" },
	} }
	A().Roster:MarkDirty()
	local t = GetServerTime()
	S():Records("accounts")[JAINA] = { id = JAINA, author = JAINA, rev = 1, time = t, token = "TOKENJAINA0000000000000=", main = JAINA,
		chars = { { guid = JAINA, name = "Jainaxx", realm = "Realm" }, { guid = THRALL, name = "Thrallz", realm = "Realm" } } }
	S():Records("contacts")[JAINA] = { id = JAINA, author = JAINA, rev = 1, time = t, account = "TOKENJAINA0000000000000=", battleTag = "Jainaxx#4321", discord = "jaina_discord" }
	S():Records("bankreq")[GARROSH .. ":1"] = { id = GARROSH .. ":1", author = GARROSH, rev = 1, time = t, requester = GARROSH, kind = "withdraw", status = "open",
		itemID = 2589, count = 20, created = t, note = "for Jainaxx in Frostwolvesx", history = { { s = "open", by = GARROSH, t = t } } }
	S():Records("bank")[JAINA .. ":log:1"] = { id = JAINA .. ":log:1", author = JAINA, rev = 1, time = t, kind = "log", tab = 1, rank = 3,
		e = A().BankLog.Encode({ { kind = "deposit", name = "Garroshx", itemID = 2589, count = 5, t = t - 100 } }), n = 1 }
	A().Notary:OnRoleChanged()
	A().Social:ComputeNow()
	A().Likes:Invalidate()
	A().Accounts:MarkDirty()
	A().Roster:MarkDirty()
	Mock.Advance(2)
	A().Shell:OpenView("roster")
	A().Shell:OpenView("bank")
	Mock.Advance(2)
end

describe("no names in the report", function()
	before_boot(function() Mock.guild.Set{ name = "Frostwolvesx", myRank = 1, members = {} } end)

	it("a guild with names everywhere puts none of them in the report", function()
		populate()
		local text = A().Diagnostics.Report()
		truthy(#text > 2000, "the report has real content")
		for _, name in ipairs(NAMES) do falsy(text:find(name, 1, true), "the report contains " .. name) end
		falsy(text:find("TOKENJAINA", 1, true), "the report contains an account token")
		falsy(text:find(A().Config:Token(), 1, true), "the report contains this account's token")
		falsy(text:find("Player%-%d+%-%x+"), "the report contains a character id")
		falsy(text:find("%w+#%d%d%d%d"), "the report contains something shaped like a BattleTag")
		falsy(text:find(UnitName("player"), 1, true), "the report contains the character name")
		falsy(text:find(GetRealmName(), 1, true), "the report contains the realm")
	end)

	it("a name inside an error message becomes a placeholder", function()
		populate()
		local D = A().Diagnostics
		D.Record("AzerothAccord/Data/Notary.lua:9: no record for Jainaxx in Frostwolvesx (asked by Garroshx and Testchar)")
		D.Record("AzerothAccord/Data/Social.lua:3: Jainaxx#4321 jaina_discord")
		local text = D.Report()
		contains(text, "no record for <player> in <guild> (asked by <player> and <player>)")
		for _, name in ipairs(NAMES) do falsy(text:find(name, 1, true), "the report contains " .. name) end
		falsy(text:find("Testchar", 1, true))
	end)

	it("Redact replaces whole words only, longest name first, and leaves short names and plain text alone", function()
		populate()
		local D = A().Diagnostics
		eq(D.Redact("Jainaxx-Realm and Jainaxx"), "<player> and <player>")
		eq(D.Redact("Jainaxxy is not Jainaxx"), "Jainaxxy is not <player>")
		eq(D.Redact("nothing to hide here"), "nothing to hide here")
		eq(D.Redact(""), "")
		eq(D.Redact(nil), nil)
		D.MIN_NAME = 99
		eq(D.Redact("Jainaxx"), "Jainaxx", "names shorter than the minimum are left alone")
		D.MIN_NAME = 3
	end)
end)

describe("the report header and size", function()
	before_boot(function() Mock.guild.Set{ name = "Accord", myRank = 3, members = {} } end)

	it("starts with the facts of the bug report form: addon, client, language, role and guild size", function()
		local lines = A().Diagnostics.HeaderLines()
		local text = table.concat(lines, "\n")
		for _, key in ipairs({ "addon:", "client:", "locale:", "role:", "guild size:" }) do contains(text, key) end
		contains(text, "role: member")
		matches(text, "guild size: %d+")
		Mock.guild.Set{ name = "Accord", myRank = 0, members = {} }
		A().Role:Refresh()
		contains(table.concat(A().Diagnostics.HeaderLines(), "\n"), "role: guild master")
		Mock.guild.Leave()
		A().Role:Refresh()
		contains(table.concat(A().Diagnostics.HeaderLines(), "\n"), "role: none")
	end)

	it("is cut at the limit, keeping the first sections, and says so", function()
		A():AddDebugSection("Huge", function()
			local lines = {}
			for i = 1, 6000 do lines[i] = "line number " .. i .. " of a very long section" end
			return lines
		end)
		local text = A().Diagnostics.Report()
		truthy(#text <= A().Diagnostics.MAX_CHARS + 80, "length " .. #text)
		contains(text, "... report cut at 30000 characters")
		contains(text, "== Sending ==")
		contains(text, "== Last errors ==")
		falsy(text:find("line number 6000 ", 1, true))
		-- the cut falls on a line boundary
		falsy(text:find("line number %d+ of a very long sec\n"))
	end)

	it("the box shows how many lines and characters it holds", function()
		Mock.Slash("/accord debug")
		local f = A().DiagnosticsBox.frame
		local text = A().DiagnosticsBox:GetText()
		local lines = select(2, text:gsub("\n", "")) + 1
		eq(f.size:GetText(), ("%d lines, %d characters"):format(lines, #text))
	end)

	it("the Italian box says it in Italian", function()
		T.boot(function(M) M.player.locale = "itIT" M.guild.Set{ name = "Accord", myRank = 3, members = {} } end)
		Mock.Slash("/accord debug")
		matches(A().DiagnosticsBox.frame.size:GetText(), "^%d+ righe, %d+ caratteri$")
	end)
end)

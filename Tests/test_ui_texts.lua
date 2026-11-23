-- No text reaches the screen without a locale key (M6.14; docs/specs/ui-style.md, ADR 0015). Two checks:
--   * the sources: no file of UI/ gives a widget a sentence of its own (SetText / SetLabel / text = / a tooltip with a
--     literal that holds a word): every word comes from L[...];
--   * the screen: an Italian client opens every view, every mode of Reputation and Bank, the member card, the Settings
--     page, the copy box and the report box; every text that is shown is made of Italian locale strings and of the
--     guild's own data (names, items, tabs). An English word that came from nowhere would be left over.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end

-- Runs a locale file against a stand-in for AceLocale and returns its plain table of strings.
local function loadLocale(name)
	local tbl = {}
	local env = { LibStub = function() return { NewLocale = function() return tbl end } end }
	local chunk = assert(loadstring(Mock.ReadSource("AzerothAccord/Locale/" .. name), "@Locale/" .. name))
	setfenv(chunk, env)
	chunk("AzerothAccord")
	return tbl
end

-- A word: three letters or more (the "x" of "x20", "g s c" of money and the "h" of ages are not words).
local function hasWord(s) return s:find("%a%a%a") ~= nil end

-- The code part of a line: the comment and the text of the strings are not code... except the strings we look at.
local function code(line)
	local out, i, n, quote = {}, 1, #line, nil
	while i <= n do
		local c = line:sub(i, i)
		if quote then
			if c == "\\" then out[#out + 1] = line:sub(i, i + 1); i = i + 1
			elseif c == quote then quote = nil; out[#out + 1] = c
			else out[#out + 1] = c end
		elseif c == '"' or c == "'" then quote = c; out[#out + 1] = c
		elseif line:sub(i, i + 1) == "--" then break
		else out[#out + 1] = c end
		i = i + 1
	end
	return table.concat(out)
end

-- A literal shown as it is: placeholders removed, it must not hold a word.
local function literalWords(s) return hasWord((s:gsub("%%[%-%+ #0]*%d*%.?%d*[sdfxXq]", ""))) end

local SHOWN_LITERAL = {
	":SetText%(%s*\"([^\"]*)\"", ":SetText%(%s*'([^']*)'",
	":SetLabel%(%s*\"([^\"]*)\"", ":SetLabel%(%s*'([^']*)'",
	":SetPlaceholder%(%s*\"([^\"]*)\"",
	"[{,%s]text%s*=%s*\"([^\"]*)\"", "[{,%s]placeholder%s*=%s*\"([^\"]*)\"",
	"Tooltip%.Show%([^,]+,%s*\"([^\"]*)\"", "Tooltip%.Attach%([^,]+,%s*\"([^\"]*)\"",
	":AddLine%(%s*\"([^\"]*)\"", ":SetFormattedText%(%s*\"([^\"]*)\"",
}

describe("the sources of the interface", function()
	it("never give a widget a word of their own: every word is a locale key", function()
		local seen, found = 0, {}
		for _, name in ipairs(Mock.loadedFiles) do
			if name:find("^AzerothAccord/UI/") then
				seen = seen + 1
				local n = 0
				for line in (Mock.ReadSource(name) or ""):gmatch("[^\n]*") do
					n = n + 1
					local c = code(line)
					for _, pattern in ipairs(SHOWN_LITERAL) do
						for literal in c:gmatch(pattern) do
							if literalWords(literal) then found[#found + 1] = name .. ":" .. n .. ": \"" .. literal .. "\"" end
						end
					end
				end
			end
		end
		truthy(seen >= 20, "the UI files were really read")
		deepEq(found, {})
	end)

	it("the check itself finds a sentence written in the code", function()
		local c = code([[  fs:SetText("Hello there") -- fs:SetText("in a comment")]])
		local hits = 0
		for _, pattern in ipairs(SHOWN_LITERAL) do
			for literal in c:gmatch(pattern) do if literalWords(literal) then hits = hits + 1 end end
		end
		eq(hits, 1)
		falsy(literalWords("%s (%d)")); falsy(literalWords("   ")); falsy(literalWords("x"))
	end)
end)

describe("an Italian client on screen", function()
	local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000C0C"
	local LINEN, POTION = 2589, 118
	local DATA = { "Accord", "Bob", "Boss", "Testchar", "Linen Cloth", "Minor Healing Potion", "Consumables", "Alchemy",
		"Azeroth Accord", "AZEROTH ACCORD",
		"Finland", "NEBULA", "GPL-3.0", "https://github.com/Finland6738/azeroth-accord", "https://github.com/Finland6738/azeroth-accord/issues",
		"https://nebula-community.github.io/giochi/wow-forever/", "https://ko-fi.com/finland6738" }

	before_boot(function(M)
		M.player.locale = "itIT"
		M.guild.Set{ name = "Accord", myRank = 1, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, professions = { { name = "Alchemy", rank = 285, max = 300 } } },
			{ name = "Boss", level = 58, class = "PRIEST", rank = 1, guid = OFF },
		} }
	end)

	-- Every text shown now under `frame` (shown font strings of shown frames, depth first).
	local function shownTexts(frame, out)
		out = out or {}
		if not (frame and frame:IsShown()) then return out end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsShown() then
				local t = region:GetText()
				if type(t) == "string" and t ~= "" then out[#out + 1] = t end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do shownTexts(child, out) end
		return out
	end

	-- The pieces of Italian text a screen may hold: every Italian string cut at its placeholders, longest first.
	local function pieces()
		local it = loadLocale("itIT.lua")
		local list, seen = {}, {}
		for _, v in pairs(it) do
			for piece in (v:gsub("%%[%-%+ #0]*%d*%.?%d*[sdfxXq]", "\1")):gmatch("[^\1]+") do
				piece = piece:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
				-- as written, and in capitals (the table headers and the eyebrows are shown in capitals)
				for _, form in ipairs({ piece, piece:upper() }) do
					if hasWord(form) and not seen[form] then seen[form] = true; list[#list + 1] = form end
				end
			end
		end
		for _, d in ipairs(DATA) do list[#list + 1] = d end
		-- the guild's own data, as the game and the guildmates give it: every text of a roster entry (name, class, rank,
		-- zone, notes), the reasons typed in requests, and the names of the saved data sets (Settings > Saved data)
		for _, e in ipairs(A().Roster:Members()) do
			for _, v in pairs(e) do if type(v) == "string" then list[#list + 1] = v end end
			list[#list + 1] = A().Roster.ClassName(e.classFile)   -- the class name the game gives in its own language
		end
		for _, rec in pairs(S():Records("bankreq")) do if rec.reason then list[#list + 1] = rec.reason end end
		for _, set in ipairs(A().Store.SET_ORDER) do list[#list + 1] = set end
		for key in pairs(A().GuildKey:Data() or {}) do list[#list + 1] = tostring(key) end
		table.sort(list, function(a, b) return #a > #b end)
		return list
	end

	-- What is left of a text once its Italian pieces and the guild's data are taken out.
	local function leftover(text, list)
		local rest = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
		for _, piece in ipairs(list) do
			local at = rest:find(piece, 1, true)
			while at do
				rest = rest:sub(1, at - 1) .. "\1" .. rest:sub(at + #piece)
				at = rest:find(piece, 1, true)
			end
		end
		return rest
	end

	local function world()
		Mock.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
		Mock.items.info[POTION] = { name = "Minor Healing Potion", quality = 1, icon = 134830 }
		for id in pairs(Mock.items.info) do Mock.items.cached[id] = true end
		local rec = { id = BOB .. ":t1", author = BOB, rev = 1, time = GetServerTime() - 7200, kind = "tab", tab = 1, name = "Consumables",
			rank = 3, it = A().Bank.EncodeItems({ { slot = 1, itemID = LINEN, count = 20 }, { slot = 2, itemID = POTION, count = 3 } }), n = 2 }
		S():Records("bank")[rec.id] = rec
		S():Records("bank")[BOB .. ":money"] = { id = BOB .. ":money", author = BOB, rev = 1, time = GetServerTime() - 60, kind = "money", money = 123456 }
		S():Records("bankreq")[BOB .. ":1"] = { id = BOB .. ":1", author = BOB, rev = 1, time = GetServerTime(), requester = BOB, kind = "withdraw",
			status = "open", itemID = LINEN, count = 5, reason = "raid", created = GetServerTime(), history = { { s = "open", by = BOB, t = GetServerTime() } } }
		A().Bus:Emit("STORE_CHANGED", "bank", rec.id, "remote")
		A().Bus:Emit("STORE_CHANGED", "bankreq", BOB .. ":1", "remote")
	end

	it("shows only Italian words and the guild's own data in every view, mode, card and box", function()
		world()
		local list = pieces()
		local screens = {}
		local function look(label, ...)
			Mock.Advance(1)
			local texts = {}
			for _, root in ipairs({ ... }) do shownTexts(root, texts) end
			screens[#screens + 1] = { label = label, texts = texts }
		end
		local content = function() return A().Shell.content end
		for _, view in ipairs({ "roster", "professions", "settings" }) do
			truthy(A().Shell:OpenView(view), view)
			look(view, content())
		end
		A().SettingsView:ShowPage(A().SettingsView.frame, "info")   -- the Info page (M6.15)
		look("settings info", content())
		A().Shell:OpenView("reputation")
		for _, m in ipairs(A().ReputationView:ModeList()) do
			A().ReputationView:SetMode(m.id)
			look("reputation " .. m.id, content())
		end
		A().Shell:OpenView("bank")
		for _, m in ipairs(A().BankView:ModeList()) do
			A().BankView:SetMode(m.id)
			look("bank " .. m.id, content())
		end
		A().Shell:OpenView("roster")
		A().MemberCard:ShowGUID(BOB)
		look("member card", content())
		A().CopyBox:Open("Bob#1234", loadLocale("itIT.lua").CARD_BATTLETAG)
		look("copy box", A().CopyBox.frame)
		A().CopyBox:Hide()
		A().DiagnosticsBox:Open("report")
		look("report box", A().DiagnosticsBox.frame)
		eq(#Mock.errors, 0)
		local bad, total = {}, 0
		for _, screen in ipairs(screens) do
			for _, text in ipairs(screen.texts) do
				total = total + 1
				local rest = leftover(text, list)
				if hasWord(rest) then bad[#bad + 1] = screen.label .. ": \"" .. text .. "\"" end
			end
		end
		truthy(hasWord(leftover("Click to close the window", list)), "an English sentence would be left over")
		falsy(hasWord(leftover("Bob", list)), "a name is data")
		truthy(#screens >= 15, "every view and mode was looked at")
		truthy(total > 100, "the screens were really read")
		if #bad > 0 then fail(#bad .. " text(s) with a word from nowhere: " .. table.concat(bad, " | ")) end
	end)
end)

-- The recruitment text (M12.2; SPEC-16 §3; REC-01..REC-03; SPEC-10 Q34): built from the MS1 gaps of the season roster
-- against the target composition (Accord's or a fake FDCP's) and the first paragraph of the handbook's Guild info page,
-- with the officer's own two lines; 255 bytes for chat, 1900 characters for Discord; officers only; nothing is ever
-- sent; the switch "recruit".

local function A() return AzerothAccord end
local function R() return AzerothAccord.Recruit end
local function V() return AzerothAccord.RecruitView end
local function S() return AzerothAccord.Store end
local function Se() return AzerothAccord.Season end
local function C() return AzerothAccord.Composition end
local function H() return AzerothAccord.Handbook end

local ME, BOB, ANN, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A77", "Player-1-000000FF"
local FOLDER, GLOBAL = "FinlandDragonCreditPoints", "FinlandDragonCreditPointsAPI"

-- every function that could send a message to a person: calling one fails the test (REC-01)
local sent
local function forbidSending(M)
	sent = {}
	local function stub(name)
		return function() sent[#sent + 1] = name error("REC-01: " .. name .. " was called") end
	end
	C_ChatInfo.SendChatMessage = stub("C_ChatInfo.SendChatMessage")
	SendChatMessage = stub("SendChatMessage")
	BNSendWhisper = stub("BNSendWhisper")
	BNSendGameData = stub("BNSendGameData")
	C_BattleNet.SendWhisper = stub("C_BattleNet.SendWhisper")
	C_BattleNet.SendGameData = stub("C_BattleNet.SendGameData")
	C_Club = C_Club or {}
	C_Club.SendMessage = stub("C_Club.SendMessage")
end

local function setup(myRank, features)
	return function(M)
		M.features = features or { recruit = true }
		M.guild.Set{ name = "Accord", myRank = myRank or 1, members = {
			{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
			{ name = "Ann", level = 60, class = "DRUID", rank = 3, guid = ANN },
			{ name = "Officer", level = 60, class = "PALADIN", rank = 1, guid = OFF },
		} }
	end
end

local function declare(guid, sender, class, spec, role, ms2)
	local t = GetServerTime()
	local rec = { id = "E:1:" .. guid, author = guid, rev = 1, time = t, kind = "entry", n = 1, unsure = false, first = t,
		class = class, ms1 = { spec = spec, role = role }, ms2 = ms2 }
	local ok, why = S():Accept("season", rec, { sender = sender })
	truthy(ok, why)
end

local function season(target)
	truthy(Se():Open("Naxx"))
	truthy(C():SetTarget(target or { size = 10, tank = 2, healer = 1, melee = 0, ranged = 3 }))
end

local function page(body, tpl)
	local ok, why = H():Save("P:info", { title = "Guild info", body = body, order = 10, tpl = tpl },
		{ base = (H():Get("P:info") or {}).rev, force = true })
	truthy(ok, why)
end

local function missing(info)
	local out = {}
	for _, m in ipairs(info.missing) do out[#out + 1] = m.part .. ":" .. m.why end
	return table.concat(out, " ")
end

local DASH = " \226\128\147 "

describe("the recruitment text", function()
	before_boot(setup(1))

	it("puts the head, the description, the gaps and the contact on one chat line", function()
		season()
		page("# About us\nA calm guild.\nWe raid on Wednesday.\n\nSecond paragraph.\n\n# Schedule\nNever this.")
		local text, info = R():Build("chat")
		eq(text, "Accord (Horde, Test Realm)" .. DASH .. "A calm guild. We raid on Wednesday." .. DASH
			.. "Looking for: 2 tanks, 1 healer, 3 ranged" .. DASH .. "Whisper Testchar")
		eq(info.format, "chat"); eq(info.length, #text); eq(info.max, 255)
		eq(missing(info), "")
		falsy(text:find("|", 1, true)); falsy(text:find("\n", 1, true))
	end)

	it("changes when the gaps change: a declaration, the target, a closed season", function()
		season()
		local before = R():Build("chat")
		contains(before, "Looking for: 2 tanks, 1 healer, 3 ranged")
		declare(BOB, "Bob", "MAGE", "FROST", "ranged")
		contains(R():Build("chat"), "Looking for: 2 tanks, 1 healer, 2 ranged")
		truthy(C():SetTarget({ size = 10, tank = 1, healer = 0, melee = 1, ranged = 1 }))
		contains(R():Build("chat"), "Looking for: 1 tank, 1 melee")
		truthy(C():SetTarget({ size = 10, tank = 0, healer = 0, melee = 0, ranged = 1 }))
		local text, info = R():Build("chat")
		falsy(text:find("Looking for", 1, true))
		eq(missing(info), "description:page gaps:full")
		truthy(Se():Close(1))
		local _, closed = R():Build("chat")
		eq(missing(closed), "description:page gaps:closed")
	end)

	it("counts the gaps of MS1: what MS2 would cover is still looked for", function()
		season({ size = 10, tank = 1, healer = 1, melee = 0, ranged = 0 })
		declare(ANN, "Ann", "DRUID", "FERAL", "tank", { spec = "RESTORATION", role = "healer" })
		eq(C().Count(C().FromAccord(Se():Entries(1))).ms2.healer, 1)
		contains(R():Build("chat"), "Looking for: 1 healer" .. DASH)
	end)

	it("says why a part is missing", function()
		local text, info = R():Build("chat")
		eq(text, "Accord (Horde, Test Realm)" .. DASH .. "Whisper Testchar")
		eq(missing(info), "description:page gaps:closed")
		truthy(Se():Open("Naxx"))
		local _, noTarget = R():Build("chat")
		eq(missing(noTarget), "description:page gaps:target")
		page("# About us\n", nil)
		eq(missing(select(2, R():Build("chat"))), "description:page gaps:target", "an empty paragraph")
		page("# About us\nStill the template.", true)
		eq(missing(select(2, R():Build("chat"))), "description:page gaps:target", "a template")
		page("# About us\nWritten.")
		contains(R():Build("chat"), "Written.")
		truthy(H():Delete("P:info", H():Get("P:info").rev, true))
		eq(missing(select(2, R():Build("chat"))), "description:page gaps:target", "a deleted page")
		for _, m in ipairs({ { "description", "raid" }, { "description", "page" }, { "gaps", "season" }, { "gaps", "closed" },
			{ "gaps", "fdcp" }, { "gaps", "target" }, { "gaps", "full" } }) do
			truthy(V().MissingText({ part = m[1], why = m[2] }), m[1] .. " " .. m[2])
		end
	end)

	it("reads the first paragraph under the first heading as plain text", function()
		truthy(H():Save("P:rules", { title = "Our rules", body = "Be kind.", order = 20 }, {}))
		local F = R().FirstParagraph
		eq(F("Intro line.\n# About us\nRead [[rules¦the rules]] and [[rules]], see [[season]].\n\nNo."),
			"Read the rules and Our rules, see.")
		eq(F("# About us\n[[loot]]\n\nThen this."), "Then this.")
		eq(F("# About us\n- raids\n- dungeons\n  - and quests\n\n# Next\n- no"), "raids; dungeons; and quests")
		eq(F("We offer:\n- raids\n- help\n\nNo."), "We offer: raids; help")
		eq(F("No heading here,\nsame paragraph.\n\nNot this."), "No heading here, same paragraph.")
		eq(F("# Empty\n\n# Full\nText"), "", "nothing under the first heading")
		eq(F(""), "")
		eq(F("# About\n[[unknown-page]] and [[unknown#Part]]"), "unknown-page and Part")
	end)

	it("keeps the officer's contact and extra line on this computer, cleaned and cut", function()
		eq(R():Settings().format, "chat")
		isNil(R():Settings().contact)
		eq(R():Set("contact", "  Discord: boss|r#1\n "), "Discord: boss#1")
		eq(R():Set("extra", "Raids Wed | Sun"), "Raids Wed \194\166 Sun")
		local text = R():Build("chat")
		contains(text, "Raids Wed \194\166 Sun" .. DASH .. "Discord: boss#1")
		falsy(text:find("Whisper", 1, true)); falsy(text:find("|", 1, true))
		local long = R():Set("contact", string.rep("\195\168", 40))   -- 80 bytes
		eq(#long, 48)
		eq(#R():Set("extra", string.rep("x", 150)), 100)
		isNil(R():Set("contact", "   "))
		contains(R():Build("chat"), "Whisper Testchar")
		isNil(R():Set("format", "html")); isNil(R():Set("other", "x"))
		eq(R():Set("format", "discord"), "discord")
		eq(select(2, R():Build()).format, "discord")
		eq(A().GuildKey:Data().recruit.format, "discord")
		Mock.Reload()
		eq(R():Settings().format, "discord")
		eq(R():Settings().extra, string.rep("x", 100))
	end)

	it("writes the Discord text on several lines, one role each", function()
		season()
		page("# About us\nA calm guild.")
		R():Set("extra", "Raids on Wednesday")
		local text, info = R():Build("discord")
		eq(text, "**Accord (Horde, Test Realm)**\nA calm guild.\nLooking for:\n- 2 tanks\n- 1 healer\n- 3 ranged\n"
			.. "Raids on Wednesday\nWhisper Testchar")
		eq(info.max, 1900); eq(info.length, R().Characters(text))
	end)

	it("stays within 255 bytes in chat and 1900 characters on Discord, cutting the description on a word", function()
		season({ size = 40, tank = 10, healer = 10, melee = 10, ranged = 10 })
		local sentence = "Siamo una gilda tranquilla e perci\195\178 cerchiamo pi\195\185 giocatori. "
		page("# Chi siamo\n" .. string.rep(sentence, 20))
		R():Set("contact", string.rep("c", 48))
		local text, info = R():Build("chat")
		truthy(#text <= 255, #text)
		eq(info.length, #text)
		contains(text, "Siamo una gilda")
		contains(text, "\226\128\166" .. DASH .. "Looking for: 10 tanks, 10 healers, 10 melee, 10 ranged" .. DASH)
		local cut = text:match(DASH .. "(.-)\226\128\166")
		eq(sentence:rep(20):sub(#cut + 1, #cut + 1):match("[ ,]") ~= nil, true, "whole words: " .. cut)
		-- the extra line goes next: first the whole description, then the end of the extra line
		R():Set("extra", string.rep("orari ", 16))
		local realHead, long = R().Head, string.rep("G", 60)
		R().Head = function() return long end
		local full = R():Build("chat")
		R().Head = realHead
		truthy(#full <= 255, #full)
		falsy(full:find("Siamo", 1, true))
		contains(full, "orari\226\128\166" .. DASH .. string.rep("c", 48))
		contains(full, long .. DASH .. "Looking for: 10 tanks, 10 healers, 10 melee, 10 ranged" .. DASH)
		R():Set("extra", "")
		local discord, di = R():Build("discord")
		truthy(di.length <= 1900)
		local described = discord:match("\n(Siamo.-)\n")
		truthy(#described <= 600 and #described > 500, #described)
		contains(described, "\226\128\166")
		-- a cut never splits a letter
		local accented = "perci\195\178 pi\195\185 citt\195\160 e gi\195\185"
		for n = 1, 40 do
			local s = R().CutWords(accented, n)
			truthy(#s <= n)
			if s ~= "" and s ~= accented then
				eq(s:sub(-3), "\226\128\166")
				local kept = s:sub(1, -4)
				eq(accented:sub(1, #kept + 1), kept .. " ", "whole words at " .. n)
			end
		end
		eq(R().CutWords("unbreakable", 6), "")
		eq(R().CutWords("short", 20), "short")
	end)

	it("never calls a function that sends a message, whatever the parts are (REC-01)", function()
		forbidSending(Mock)
		local function every()
			for _, format in ipairs(R().FORMATS) do
				truthy(V():SetFormat(format) ~= nil)
				truthy(V():Open())
				V():SelectAll()
				V():Draw()
				V():Hide()
			end
		end
		every()                                   -- no season, no page
		truthy(Se():Open("Naxx")); every()        -- no target
		truthy(C():SetTarget({ size = 10, tank = 1, healer = 1, melee = 1, ranged = 1 })); every()
		page("# About us\nHello."); every()
		R():Set("contact", "someone"); R():Set("extra", "more"); every()
		declare(BOB, "Bob", "MAGE", "FROST", "ranged"); every()
		Mock.Advance(5)
		eq(#sent, 0)
		eq(#Mock.errors, 0)
		for _, file in ipairs({ "AzerothAccord/Data/Recruit.lua", "AzerothAccord/UI/Recruit.lua" }) do
			local source = Mock.ReadSource(file):gsub("%-%-[^\r\n]*", "")
			falsy(source:find("Send", 1, true), file)
			falsy(source:find("Transport", 1, true), file)
		end
	end)

	it("shows the text in a read-only box that follows the gaps and the officer's lines", function()
		season()
		local text = V():Open()
		local f = V().frame
		truthy(V():IsShown())
		eq(f.edit:GetText(), text)
		contains(f.count:GetText(), "/ 255 bytes")
		contains(f.missing:GetText(), "Guild info")
		f.edit:SetText("typed over")
		f.edit:GetScript("OnTextChanged")(f.edit, true)
		eq(f.edit:GetText(), text, "read-only")
		declare(BOB, "Bob", "MAGE", "FROST", "ranged")
		eq(f.edit:GetText(), text, "collected for half a second")
		Mock.Advance(1)
		contains(f.edit:GetText(), "2 ranged")
		truthy(C():SetTarget({ size = 10, tank = 1, healer = 0, melee = 0, ranged = 0 }))
		Mock.Advance(1)
		contains(f.edit:GetText(), "Looking for: 1 tank" .. DASH)
		page("# About us\nNew words.")
		Mock.Advance(1)
		contains(f.edit:GetText(), "New words.")
		f.extra.edit:SetText("Sunday")
		f.extra.edit:GetScript("OnTextChanged")(f.extra.edit, true)
		contains(f.edit:GetText(), "Sunday")
		eq(R():Settings().extra, "Sunday")
		V():SetFormat("discord")
		contains(f.edit:GetText(), "**Accord")
		contains(f.count:GetText(), "characters")
		V():Hide()
		eq(f.edit:GetText(), "")
		Mock.Advance(5)
		eq(#Mock.errors, 0)
	end)

	it("opens from /accord recruit and from the Season view", function()
		Mock.Slash("/accord recruit")
		truthy(V():IsShown())
		V():Hide()
		Mock.Slash("/accord help")
		contains(table.concat(Mock.PlainOutput(), "\n"), "/accord recruit")
		Mock.Slash("/accord season")
		local f = A().SeasonView.frame
		truthy(A().SeasonView.Model().canRecruit)
		truthy(f.recruit:IsShown())
		f.recruit:GetScript("OnClick")(f.recruit, "LeftButton")
		truthy(V():IsShown())
		eq(#Mock.errors, 0)
	end)

	it("saves and sends nothing of the text (REC-02)", function()
		season()
		V():Open()
		Mock.Advance(120)
		local data = A().GuildKey:Data()
		isNil(data.recruit, "no line written, nothing kept")
		for _, e in ipairs(Mock.chat.sent) do falsy(e.message:find("Looking for", 1, true)) end
		eq(#Mock.chat.messages, 0)
	end)
end)

describe("the recruitment text for a member", function()
	before_boot(setup(3))

	it("is refused: no text, no button, no window", function()
		falsy(R():CanSee())
		local text, why = R():Build("chat")
		isNil(text); eq(why, "officer")
		isNil(R():Set("contact", "me"))
		Mock.Slash("/accord recruit")
		contains(table.concat(Mock.PlainOutput(), "\n"), "for officers")
		falsy(V():IsShown())
		Mock.Slash("/accord season")
		falsy(A().SeasonView.frame.recruit:IsShown())
		eq(#Mock.errors, 0)
	end)

	it("is for every member when the one place says so", function()
		R().VISIBLE_TO = "members"
		truthy(R():Build("chat"))
		truthy(V():Open())
	end)
end)

describe("the recruitment text with the switch off", function()
	before_boot(setup(1, { recruit = false }))

	it("has no command, no button and no text", function()
		Mock.Slash("/accord help")
		falsy(table.concat(Mock.PlainOutput(), "\n"):find("/accord recruit", 1, true))
		Mock.Slash("/accord recruit")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Unknown command 'recruit'")
		local text, why = R():Build("chat")
		isNil(text); eq(why, "off")
		Mock.Slash("/accord season")
		falsy(A().SeasonView.frame.recruit:IsShown())
		isNil(V().frame)
		eq(#Mock.errors, 0)
	end)

	it("adds nothing to the demo guild", function()
		Mock.Slash("/accord demo")
		isNil(S():Get("season", "S:1"))
		isNil(S():Get("handbook", "P:info"))
		isNil(S():Get("guildcfg", "target"))
	end)
end)

describe("the recruitment text without the season and the handbook", function()
	before_boot(setup(1, { recruit = true, season = false, raid = false }))

	it("says both parts are switched off", function()
		local text, info = R():Build("chat")
		eq(text, "Accord (Horde, Test Realm)" .. DASH .. "Whisper Testchar")
		eq(missing(info), "description:raid gaps:season")
	end)
end)

describe("the recruitment text without the handbook only", function()
	before_boot(setup(1, { recruit = true, season = true, raid = false }))

	it("keeps the gaps and misses the description", function()
		season()
		local text, info = R():Build("chat")
		contains(text, "Looking for: 2 tanks")
		eq(missing(info), "description:raid")
	end)
end)

describe("the recruitment text with FDCP as the source", function()
	before_boot(setup(1))

	it("takes the gaps of FDCP's pool and follows its changes", function()
		truthy(C():SetTarget({ size = 10, tank = 2, healer = 1, melee = 0, ranged = 1 }))
		truthy(A().Integrations:SetSource("raid", "fdcp"))
		eq(missing(select(2, R():Build("chat"))), "description:page gaps:fdcp", "FDCP not loaded")
		local state, pool = "OPEN", { { name = "Bob-TestRealm", class = "MAGE", role = "DAMAGER", ms1 = 64, status = "ACTIVE" } }
		local callbacks = {}
		local api = { API_VERSION = 1,
			IsReady = function() return true end, GetVersion = function() return "1.0.2" end,
			GetSource = function() return "LEDGER" end, GetSeason = function() return { id = "S3", name = "S3", state = state } end,
			GetPool = function() return pool end, GetNight = function() end,
			RegisterCallback = function(...)
				for i = 1, select("#", ...) do
					local a = select(i, ...)
					if type(a) == "function" then callbacks[#callbacks + 1] = a end
				end
				return true
			end,
			UnregisterCallback = function() return true end }
		Mock.addons[FOLDER] = { loaded = true, version = "1.0.2" }
		_G[GLOBAL] = api
		A().Integrations:Refresh()
		V():Open()
		contains(V():GetText(), "Looking for: 2 tanks, 1 healer" .. DASH)
		pool[2] = { name = "Ann-TestRealm", class = "DRUID", role = "TANK", ms1 = 104, status = "ACTIVE" }
		A().Bus:Emit("FDCP_CHANGED")
		Mock.Advance(1)
		contains(V():GetText(), "Looking for: 1 tank, 1 healer")
		state = "CLOSED"
		eq(missing(select(2, R():Build("chat"))), "description:page gaps:closed")
		eq(#Mock.errors, 0)
	end)
end)

describe("the recruitment text in the demo guild", function()
	before_boot(function(M) M.features = { recruit = true } end)

	it("has two gaps and a description", function()
		Mock.Slash("/accord demo")
		local text, info = R():Build("chat")
		eq(missing(info), "")
		contains(text, "Demo Guild")
		contains(text, "A relaxed guild")
		contains(text, "Looking for: 1 tank, 1 healer" .. DASH)
		eq(#Mock.chat.sent, 0)
		eq(#Mock.errors, 0)
	end)
end)

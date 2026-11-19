-- "Play with someone new" (M4.7; SPEC-07 SOC-20): online guildmates of a compatible level with whom the player played less
-- than 30 minutes in the last 30 days, one per player, fewest minutes first, with Whisper and Invite.
local function A() return AzerothAccord end
local function N() return AzerothAccord.Suggest end
local function S() return AzerothAccord.Store end

local ME = "Player-1-0000A001"
local MYALT = "Player-1-0000A002"
local BOB, BOBALT, CAT, DAN, EVE, FAY = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000CA7", "Player-1-00000DA1", "Player-1-00000E0E",
	"Player-1-00000FA1"

local function guild()
	Mock.guild.Set{ name = "Accord", myRank = 3, members = {
		{ name = "Myalt", level = 60, class = "MAGE", rank = 4, guid = MYALT, online = true },
		{ name = "Bob", level = 52, class = "MAGE", rank = 3, guid = BOB, online = true, zone = "Tanaris" },
		{ name = "Bobalt", level = 59, class = "WARRIOR", rank = 4, guid = BOBALT, online = true, zone = "Ironforge" },
		{ name = "Cat", level = 60, class = "ROGUE", rank = 3, guid = CAT, online = true, zone = "Stormwind" },
		{ name = "Dan", level = 58, class = "HUNTER", rank = 3, guid = DAN, online = true, zone = "Winterspring" },
		{ name = "Eve", level = 60, class = "PRIEST", rank = 3, guid = EVE, online = false },
		{ name = "Fay", level = 40, class = "DRUID", rank = 3, guid = FAY, online = true },
	} }
end

local function account(guid, chars)
	local list = {}
	for i, g in ipairs(chars) do list[i] = { guid = g, name = "c" .. i } end
	S():Records("accounts")[guid] = { id = guid, author = guid, rev = 1, time = GetServerTime(), token = "T" .. chars[1], chars = list }
	A().Accounts:MarkDirty()
end

local function pk(a, b) if a > b then a, b = b, a end return a .. ":" .. b end

local function world()
	account(ME, { ME, MYALT }); account(MYALT, { MYALT, ME })
	account(BOB, { BOB, BOBALT }); account(BOBALT, { BOBALT, BOB })
	S():Records("coplay")["x"] = { id = "x", author = ME, rev = 1, time = GetServerTime(), day = A().Compat.ServerDay(), observer = ME,
		pairs = { [pk(ME, CAT)] = 120, [pk(ME, DAN)] = 20 } }
	A().Social:ComputeNow()
end

local function names(list)
	local out = {}
	for i, s in ipairs(list) do out[i] = s.name .. ":" .. s.minutes end
	return out
end

describe("the suggestions", function()
	before_boot(function() guild() end)

	it("online, within 5 levels, under 30 minutes together, one per player, fewest minutes first", function()
		world()
		-- Cat: 120 minutes (out); Dan: 20; Eve: offline; Fay: level 40; Myalt: own account; Bob's account: Bobalt (59) is closer
		deepEq(names(N().List()), { "Bobalt:0", "Dan:20" })
		local first = N().List()[1]
		eq(first.guid, BOBALT); eq(first.zone, "Ironforge"); eq(first.level, 59)
	end)

	it("without a social result every online guildmate of the level counts as new", function()
		account(ME, { ME, MYALT }); account(MYALT, { MYALT, ME })
		deepEq(names(N().List()), { "Cat:0", "Bobalt:0", "Dan:0" }, "closest level first; Bob (52) is 8 levels away")
		eq(#N().List({ limit = 2 }), 2)
	end)

	it("Whisper opens the chat box for the player to write; Invite asks the game and says so", function()
		world()
		local opened
		ChatFrame_OpenChat = function(text) opened = text end
		truthy(N():Whisper(DAN))
		eq(opened, "/w Dan ")
		truthy(N():Invite(DAN))
		deepEq(Mock.group.invites, { "Dan" })
		contains(table.concat(Mock.PlainOutput(), " "), "Invitation sent to Dan.")
		C_PartyInfo = nil
		falsy(N():Invite(DAN))
		contains(table.concat(Mock.PlainOutput(), " "), "The game did not let the addon invite Dan.")
	end)

	it("the Someone new mode shows the rows with their buttons, or says nobody", function()
		world()
		Mock.Slash("/accord reputation")
		truthy(A().ReputationView:SetMode("new"))
		local f = N().frame
		local shown = {}
		for _, row in ipairs(f.area.rows) do if row:IsShown() then shown[#shown + 1] = row end end
		eq(#shown, 2)
		eq(shown[1].name:GetText(), "Bobalt")
		eq(shown[1].detail:GetText(), "level 59, Ironforge - together: never")
		eq(shown[2].detail:GetText(), "level 58, Winterspring - together: 20 min")
		shown[2].invite:Click()
		deepEq(Mock.group.invites, { "Dan" })
		falsy(f.message:IsShown())
		for _, m in ipairs(Mock.guild.members) do m.online = false end
		Mock.Fire("GUILD_ROSTER_UPDATE")
		A().Roster:MarkDirty()
		A().ReputationView:Redraw()
		truthy(f.message:IsShown())
	end)
end)

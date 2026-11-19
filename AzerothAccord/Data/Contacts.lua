-- Contacts: how to reach a member (SPEC-05 §4, SPEC-03 §2, owner decision D3: always shared). Lua 5.1.
--
--   BattleTag  read from the game (BNet_GetBattleTagSelf, else BNGetInfo) [verify S8], always published.
--   Discord    the native `discordInfo` of C_Club.GetMemberInfo when the server fills it [verify S2] (read by Data/Roster.lua
--              for every member, with or without the addon); otherwise the user name the player typed in the settings
--              (Contacts:SetDiscord, at most 32 characters, no links), published like the BattleTag.
-- The own record is one `contacts` record (id = the character's GUID, { account = token, battleTag, discord }); the
-- contacts of an account are the newest records of its characters (Contacts:Of). What other clients publish is data, not
-- text to trust: every value is validated and escaped (`|` would start a colour or link escape in the game's text) before
-- it is shown. The native Discord name wins over a shared one (ADR 0010).
-- "Add BattleTag friend" (CON-04) is the player's own click, answered by C_Club.SendBattleTagFriendRequest.
local ADDON_NAME, ns = ...
ns = ns or {}
local Contacts = {}
ns.Contacts, ns.modules = Contacts, ns.modules or {}
ns.modules.Contacts = Contacts

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

Contacts.AUTO = true            -- the offline tests switch the automatic start off (Tests/lib/harness.lua)
Contacts.DISCORD_MAX = 32
Contacts.BATTLETAG_MAX = 40
Contacts.PUBLISH_DELAY = 10     -- seconds after login; the BattleTag may need a retry (the Battle.net service starts late)
Contacts.RETRY_DELAY = 70
Contacts.EVENTS = { "BN_CONNECTED", "BN_INFO_CHANGED" }

local state = { stats = { published = 0, skipped = 0, friendRequests = 0, friendFailed = 0 } }
Contacts.state = state

local function compat() return ns.Compat end
local function lower(s) return type(s) == "string" and s:lower() or "" end

---------------------------------------------------------------------------------------------------------------------
-- Validation: nothing from another client is shown as it came
---------------------------------------------------------------------------------------------------------------------
-- A BattleTag "Name#1234": a name without spaces or '#', a number; at most BATTLETAG_MAX bytes. Returns it or nil.
function Contacts.ValidateBattleTag(text)
	if type(text) ~= "string" or #text > Contacts.BATTLETAG_MAX then return nil end
	local name, number = text:match("^([^#%s|]+)#(%d+)$")
	if not name or #name < 2 or #number > 8 then return nil end
	return text
end

-- A Discord user name as the player may type it: at most 32 characters, no spaces, no link, no '@'. A leading '@'
-- and the surrounding spaces are removed. Returns the clean name, or nil and a reason ("empty", "long", "short",
-- "invalid").
function Contacts.ValidateDiscord(text)
	if type(text) ~= "string" then return nil, "invalid" end
	text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", "")
	if text == "" then return nil, "empty" end
	if #text > Contacts.DISCORD_MAX then return nil, "long" end
	if #text < 2 then return nil, "short" end
	if text:find("[%s/\\:@|<>%[%]{}()\"'%c]") then return nil, "invalid" end
	local l = text:lower()
	if l:find("http", 1, true) or l:find("www.", 1, true) or l:find(".gg", 1, true) then return nil, "invalid" end
	return text
end

-- Text that came from the network, made safe to show: only what passed the validation above, `|` doubled.
function Contacts.Escape(text)
	if type(text) ~= "string" then return nil end
	return (text:gsub("|", "||"))
end

---------------------------------------------------------------------------------------------------------------------
-- The own contacts
---------------------------------------------------------------------------------------------------------------------
function Contacts:OwnBattleTag()
	local C = compat()
	local tag = C and C.Player.BattleTag()
	tag = tag and Contacts.ValidateBattleTag(tag) or nil
	if C then
		if tag then C:SetFeature("battleTag", "available", "own BattleTag read")
		elseif C.Resolve("BNet_GetBattleTagSelf") ~= nil and C:Feature("battleTag") ~= "available" then
			C:SetFeature("battleTag", "unknown", "the game gave no BattleTag yet")
		end
	end
	return tag
end

-- The Discord name the player typed (settings), or nil.
function Contacts:OwnDiscord()
	local name = ns.Config and ns.Config:Get("account.settings.discord")
	if type(name) ~= "string" then return nil end
	return (Contacts.ValidateDiscord(name))
end

-- Saves the typed Discord name ("" removes it) and publishes. Returns true, or false and the reason.
function Contacts:SetDiscord(text)
	local C = ns.Config
	if not C then return false, "config" end
	if type(text) == "string" and text:gsub("%s", ""):gsub("^@", "") == "" then
		local ok, why = C:Set("account.settings.discord", nil)
		if not ok then return false, why end
		self:Publish()
		return true, "cleared"
	end
	local clean, why = Contacts.ValidateDiscord(text)
	if not clean then return false, why end
	local ok, setWhy = C:Set("account.settings.discord", clean)
	if not ok then return false, setWhy end
	self:Publish()
	return true, "saved"
end

function Contacts:BuildRecord()
	local token = ns.Config and ns.Config:Token()
	if type(token) ~= "string" or token == "" then return nil end
	return { account = token, battleTag = self:OwnBattleTag(), discord = self:OwnDiscord() }
end

-- Publishes the own record when it differs from the one held; a record is also written to take back what was removed
-- (the Discord name erased), never an empty one for a player who has nothing.
function Contacts:Publish()
	local S, C = ns.Store, compat()
	if not (S and C) or not (ns.GuildKey and ns.GuildKey:Current()) then return false, "guild" end
	local me = C.Player.GUID()
	if not me then return false, "player" end
	local fields = self:BuildRecord()
	if not fields then return false, "record" end
	local old = S:Get("contacts", me)
	if not old and not fields.battleTag and not fields.discord then return false, "nothing" end
	if old and old.account == fields.account and old.battleTag == fields.battleTag and old.discord == fields.discord then
		state.stats.skipped = state.stats.skipped + 1
		return false, "unchanged"
	end
	local rec, why = S:Put("contacts", me, fields)
	if not rec then return false, why end
	state.stats.published = state.stats.published + 1
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Other members' contacts
---------------------------------------------------------------------------------------------------------------------
-- The contacts of the account of `guid`: { battleTag, discord, discordSource = "native"|"shared", time, battleTagSource =
-- "shared" } with only what validates; nil when nothing is known. Native Discord first (ADR 0010), else the newest shared.
function Contacts:Of(guid)
	if type(guid) ~= "string" then return nil end
	local S, R, A = ns.Store, ns.Roster, ns.Accounts
	local guids = { guid }
	local group = A and A:GroupOf(guid)
	if group then
		guids = {}
		for _, m in ipairs(group.members) do guids[#guids + 1] = m.guid end
	end
	local records = {}
	for _, g in ipairs(guids) do
		local rec = S and S:Get("contacts", g)
		if type(rec) == "table" and rec.del ~= true then records[#records + 1] = rec end
	end
	table.sort(records, function(a, b)
		if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) > (b.time or 0) end
		return tostring(a.author) < tostring(b.author)
	end)
	local out = {}
	for _, rec in ipairs(records) do
		if not out.battleTag and Contacts.ValidateBattleTag(rec.battleTag) then out.battleTag, out.time = rec.battleTag, rec.time end
		if not out.sharedDiscord then
			local d = Contacts.ValidateDiscord(rec.discord)
			if d then out.sharedDiscord, out.time = d, out.time or rec.time end
		end
	end
	local native
	if R then
		for _, g in ipairs(guids) do
			local e = R:ByGUID(g)
			if e and e.discord and e.discordSource == "native" then native = Contacts.ValidateDiscord(e.discord) if native then break end end
		end
	end
	if native then out.discord, out.discordSource = native, "native"
	elseif out.sharedDiscord then out.discord, out.discordSource = out.sharedDiscord, "shared" end
	out.sharedDiscord = nil
	if out.battleTag then out.battleTagSource = "shared" end
	if not out.battleTag and not out.discord then return nil end
	return out
end

-- The table cell: "BT DC", "BT", "DC" or "".
function Contacts:Summary(guid)
	local c = self:Of(guid)
	if not c then return "" end
	local L = ns.L
	local parts = {}
	if c.battleTag then parts[#parts + 1] = L["CONTACT_BT_SHORT"] end
	if c.discord then parts[#parts + 1] = L["CONTACT_DISCORD_SHORT"] end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------------------------------------------------
-- Add BattleTag friend (CON-04)
---------------------------------------------------------------------------------------------------------------------
-- true when the button can be offered for this roster entry: a guild member (club id known) who is not the player.
function Contacts:CanSendFriendRequest(entry)
	local C = compat()
	if not (C and type(entry) == "table") or entry.isSelf or entry.notInGuild or entry.clubMemberId == nil then return false end
	return C.Guild.ClubId() ~= nil and C:State("club.SendBattleTagFriendRequest") == C.AVAILABLE
end

-- The player's own click: C_Club.SendBattleTagFriendRequest(guild club, member). Prints the outcome. Returns the call
-- state ("available" when the game accepted the call; the game's own message says what became of the request).
function Contacts:SendFriendRequest(entry)
	local C, L = compat(), ns.L
	if not self:CanSendFriendRequest(entry) then
		if ns.addon then ns.addon:Print(L["FRIEND_UNAVAILABLE"]) end
		return "unavailable"
	end
	local result = C.Club.SendBattleTagFriendRequest(C.Guild.ClubId(), entry.clubMemberId)
	if result == C.AVAILABLE then
		state.stats.friendRequests = state.stats.friendRequests + 1
		if ns.addon then ns.addon:Print(L["FRIEND_SENT"]:format(entry.short or entry.name or "?")) end
	else
		state.stats.friendFailed = state.stats.friendFailed + 1
		if ns.addon then ns.addon:Print(L["FRIEND_FAILED"]) end
	end
	return result
end

---------------------------------------------------------------------------------------------------------------------
-- Start and events
---------------------------------------------------------------------------------------------------------------------
local function schedule(seconds, fn)
	local C = compat()
	if C then C.After(seconds, fn) end
end

function Contacts:Start()
	if not self.AUTO then return false end
	if not (ns.GuildKey and ns.GuildKey:Current()) then return false end
	schedule(Contacts.PUBLISH_DELAY, function() Contacts:Publish() end)
	-- the Battle.net service can come up late: one more look, then the BN events do the rest
	schedule(Contacts.RETRY_DELAY, function() Contacts:Publish() end)
	return true
end

function Contacts:DebugLines()
	local S = ns.Store
	local records = S and S:Count("contacts") or 0
	local C = compat()
	return {
		("Contacts: %d record(s) held; own BattleTag %s, own Discord %s; published %d, unchanged %d"):format(records,
			(C and C.Player.BattleTag()) and "known" or "not available", self:OwnDiscord() and "typed" or "not set",
			state.stats.published, state.stats.skipped),
		("  friend requests: %d sent, %d failed"):format(state.stats.friendRequests, state.stats.friendFailed),
	}
end

if ns.addon then
	ns.addon.Contacts = Contacts
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Contacts", function() return Contacts:DebugLines() end) end
	LibStub("AceEvent-3.0"):Embed(Contacts)
	for _, event in ipairs(Contacts.EVENTS) do
		pcall(Contacts.RegisterEvent, Contacts, event, function()
			if Contacts.AUTO then schedule(2, function() Contacts:Publish() end) end
		end)
	end
	if ns.Bus then
		ns.Bus:On("GUILD_CHANGED", function(key) if key then Contacts:Start() end end)
	end
	if ns.OnEnable then ns.OnEnable(function() Contacts:Start() end) end
end

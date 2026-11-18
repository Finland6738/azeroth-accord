-- AzAc Probe, M0.3: S2 (ClubMemberInfo of the guild), S8 (BattleTag), S10 (account-wide SavedVariables, realms).
-- Lua 5.1. Every game API call goes through pcall. Never record names: only counts, types, field names and shapes.
-- Player GUIDs are stored only as short hashes, to tell characters apart without keeping an identifier.

local Probe = _G.AzAc_Probe
if not Probe then
    return
end

local call = Probe.Call

local PRESENCE_OFFLINE, PRESENCE_UNKNOWN = 3, 0
do
    local ok, e = pcall(function() return Enum.ClubMemberPresence end)
    if ok and type(e) == "table" then
        PRESENCE_OFFLINE = e.Offline or PRESENCE_OFFLINE
        PRESENCE_UNKNOWN = e.Unknown or PRESENCE_UNKNOWN
    end
end

local function isSecret(v)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, r = pcall(issecretvalue, v)
    return ok and r == true
end

--- true when the value carries information: non-empty string, non-zero number, true, non-empty table.
local function filled(v)
    local t = type(v)
    if t == "string" then
        return v ~= ""
    elseif t == "number" then
        return v ~= 0
    elseif t == "boolean" then
        return v
    elseif t == "table" then
        return next(v) ~= nil
    end
    return false
end

local function shortHash(s)
    local h = 5381
    for i = 1, #tostring(s) do
        h = (h * 33 + tostring(s):byte(i)) % 1000003
    end
    return h
end

local function guildClubId()
    if not (C_Club and C_Club.GetGuildClubId) then
        return nil
    end
    local ok, id = call(C_Club.GetGuildClubId)
    return ok and id or nil
end

-- S2 ---------------------------------------------------------------------------------------------------------------
local lastScan -- summary of the last roster scan, reused by S10 (realm part of the names)

--- Reads every member of the guild club and aggregates field statistics (counts, never values).
local function scanRoster(clubId)
    local ok, members = call(C_Club.GetClubMembers, clubId)
    if not ok or type(members) ~= "table" then
        return nil, "GetClubMembers failed"
    end
    local groups = { all = {}, online = {}, offline = {} }
    local counts = { all = 0, online = 0, offline = 0, noInfo = 0, secret = 0 }
    local keyTypes = {}      -- key -> { type -> count }
    local discordShape = {}  -- discordInfo key -> type counts
    local bnetIds, bnetDup = {}, 0
    local namesWithRealm, realmParts, namesOtherRealm = 0, {}, 0
    local ownRealm = select(2, call(GetNormalizedRealmName))
    local nameTypes = {}
    for _, memberId in ipairs(members) do
        local okI, info = call(C_Club.GetMemberInfo, clubId, memberId)
        if not okI or type(info) ~= "table" then
            counts.noInfo = counts.noInfo + 1
        else
            local group = (info.presence == PRESENCE_OFFLINE) and "offline"
                or (info.presence == PRESENCE_UNKNOWN and "unknown" or "online")
            counts.all = counts.all + 1
            if group ~= "unknown" then
                counts[group] = counts[group] + 1
            end
            for _, g in ipairs({ "all", group }) do
                local stats = groups[g]
                if stats then
                    for k, v in pairs(info) do
                        local s = stats[k] or { present = 0, filled = 0 }
                        stats[k] = s
                        s.present = s.present + 1
                        if isSecret(v) then
                            counts.secret = counts.secret + 1
                        elseif filled(v) then
                            s.filled = s.filled + 1
                        end
                    end
                end
            end
            for k, v in pairs(info) do
                local kt = keyTypes[k] or {}
                keyTypes[k] = kt
                kt[type(v)] = (kt[type(v)] or 0) + 1
            end
            if type(info.discordInfo) == "table" then
                for k, v in pairs(info.discordInfo) do
                    local d = discordShape[k] or { present = 0, filled = 0 }
                    discordShape[k] = d
                    d.present = d.present + 1
                    if filled(v) then d.filled = d.filled + 1 end
                end
            end
            if info.bnetAccountId then
                bnetIds[info.bnetAccountId] = (bnetIds[info.bnetAccountId] or 0) + 1
            end
            nameTypes[type(info.name)] = (nameTypes[type(info.name)] or 0) + 1
            if type(info.name) == "string" and not isSecret(info.name) then
                local realm = info.name:match("%-(.+)$")
                if realm then
                    namesWithRealm = namesWithRealm + 1
                    realmParts[realm] = true
                    if type(ownRealm) == "string" and realm ~= ownRealm then
                        namesOtherRealm = namesOtherRealm + 1
                    end
                end
            end
        end
    end
    local accountsWithAlts, accountsTotal = 0, 0
    for _, n in pairs(bnetIds) do
        accountsTotal = accountsTotal + 1
        if n > 1 then accountsWithAlts = accountsWithAlts + 1 end
    end
    local realmCount = 0
    for _ in pairs(realmParts) do realmCount = realmCount + 1 end
    return {
        members = #members, counts = counts, groups = groups, keyTypes = keyTypes, discordShape = discordShape,
        accountsTotal = accountsTotal, accountsWithAlts = accountsWithAlts, namesWithRealm = namesWithRealm,
        namesOtherRealm = namesOtherRealm, realmCount = realmCount, nameTypes = nameTypes,
    }
end

local function fieldLine(stats, key)
    local s = stats[key]
    return s and (s.filled .. "/" .. s.present) or "absent"
end

local function logScan(r)
    local function add(l) Probe:Log("S2 fields", l) end
    add(string.format("members=%d read=%d online=%d offline=%d noInfo=%d secretValues=%d", r.members, r.counts.all,
        r.counts.online, r.counts.offline, r.counts.noInfo, r.counts.secret))
    local keys = {}
    for k in pairs(r.groups.all) do keys[#keys + 1] = k end
    table.sort(keys)
    add("field | filled/present: all | online | offline | types")
    for _, k in ipairs(keys) do
        local types = {}
        for t, n in pairs(r.keyTypes[k] or {}) do types[#types + 1] = t .. "=" .. n end
        table.sort(types)
        add(string.format("%s | %s | %s | %s | %s", k, fieldLine(r.groups.all, k), fieldLine(r.groups.online, k),
            fieldLine(r.groups.offline, k), table.concat(types, ",")))
    end
    local dk = {}
    for k, d in pairs(r.discordShape) do dk[#dk + 1] = k .. " filled " .. d.filled .. "/" .. d.present end
    table.sort(dk)
    add("discordInfo keys: " .. (#dk > 0 and table.concat(dk, "; ") or "none seen"))
    add(string.format("bnetAccountId: distinct accounts=%d, accounts with 2+ members=%d", r.accountsTotal, r.accountsWithAlts))
    add(string.format("names with a realm part=%d, of them other than own realm=%d, distinct realm parts=%d",
        r.namesWithRealm, r.namesOtherRealm, r.realmCount))
    local nt = {}
    for t, n in pairs(r.nameTypes) do nt[#nt + 1] = t .. "=" .. n end
    add("name value types: " .. table.concat(nt, ","))
end

local scanning = false

Probe:Register("S2", "C_Club member info for the guild: profession1/2Name/Rank, discordInfo, bnetAccountId, guid; offline too",
    function()
        if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then
            return "fail", "C_Club.GetGuildClubId / GetClubMembers / GetMemberInfo missing"
        end
        local clubId = guildClubId()
        if not clubId then
            return "info", "no guild club id: log in with a guilded character (the guild window may need to be opened once)"
        end
        if scanning then
            return "info", "a scan is already running"
        end
        -- Ask the server for fresh data: roster request and a members subscription, then read after a few seconds.
        call(C_GuildInfo and C_GuildInfo.GuildRoster)
        call(C_Club.FocusMembers, clubId)
        local first = scanRoster(clubId)
        scanning = true
        local function finish()
            scanning = false
            local r, err = scanRoster(clubId)
            call(C_Club.UnfocusMembers, clubId)
            if not r then
                Probe:Record("S2", "fail", err)
                Probe.Print("S2 [fail] " .. tostring(err))
                return
            end
            lastScan = r
            logScan(r)
            local function f(key) return fieldLine(r.groups.all, key) end
            local details = string.format(
                "members=%d (online %d, offline %d); filled/present: guid %s, bnetAccountId %s, profession1Name %s, "
                .. "profession1Rank %s, profession2Name %s, discordInfo %s, classID %s, level %s; accounts %d, with alts %d; "
                .. "first read before the wait: %s members (full table in the S2 fields log)",
                r.counts.all, r.counts.online, r.counts.offline, f("guid"), f("bnetAccountId"), f("profession1Name"),
                f("profession1Rank"), f("profession2Name"), f("discordInfo"), f("classID"), f("level"),
                r.accountsTotal, r.accountsWithAlts, first and tostring(first.counts.all) or "?")
            Probe:Record("S2", "info", details)
            Probe.Print("S2 [info] " .. details)
        end
        if C_Timer and C_Timer.After then
            local okT = pcall(C_Timer.After, 5, finish)
            if okT then
                return "info", "scan started, the final line appears in about 5 seconds"
            end
        end
        finish()
        return "info", "scan finished (no timer)"
    end)

-- S8 ---------------------------------------------------------------------------------------------------------------
local function tagShape(v)
    if type(v) ~= "string" then
        return type(v)
    end
    if isSecret(v) then
        return "secret"
    end
    local name, digits = v:match("^(.+)#(%d+)$")
    if name then
        return string.format("battletag-format(name length %d, %d digits)", #name, #digits)
    end
    return "string(no #digits suffix, length " .. #v .. ")"
end

local function battleTagSelfLines()
    local lines = {}
    local function add(l) lines[#lines + 1] = l end
    add("BNet_GetBattleTagSelf = " .. type(rawget(_G, "BNet_GetBattleTagSelf")))
    if type(BNet_GetBattleTagSelf) == "function" then
        local ok, v = call(BNet_GetBattleTagSelf)
        add("BNet_GetBattleTagSelf(): " .. (ok and tagShape(v) or "error"))
    end
    add("BNGetInfo = " .. type(rawget(_G, "BNGetInfo")))
    if type(BNGetInfo) == "function" then
        local r = { call(BNGetInfo) }
        if r[1] then
            local parts = {}
            for i = 2, #r do
                parts[#parts + 1] = "#" .. (i - 1) .. ":" .. (type(r[i]) == "string" and tagShape(r[i]) or type(r[i]))
            end
            add("BNGetInfo() returns " .. table.concat(parts, " "))
        else
            add("BNGetInfo(): error")
        end
    end
    add("BNConnected = " .. (type(BNConnected) == "function" and tostring(select(2, call(BNConnected))) or "missing"))
    add("BNFeaturesEnabledAndConnected = " .. (type(BNFeaturesEnabledAndConnected) == "function"
        and tostring(select(2, call(BNFeaturesEnabledAndConnected))) or "missing"))
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and UnitGUID then
        local okG, guid = call(UnitGUID, "player")
        local ok, info = call(C_BattleNet.GetAccountInfoByGUID, okG and guid or "")
        if ok and type(info) == "table" then
            local fields = {}
            for k, v in pairs(info) do
                fields[#fields + 1] = k .. ":" .. (k == "battleTag" and tagShape(v) or type(v))
            end
            table.sort(fields)
            add("C_BattleNet.GetAccountInfoByGUID(player): " .. table.concat(fields, ","))
        else
            add("C_BattleNet.GetAccountInfoByGUID(player): " .. (ok and "nil" or "error"))
        end
    else
        add("C_BattleNet.GetAccountInfoByGUID: missing")
    end
    add("C_Club.SendBattleTagFriendRequest = " .. type(C_Club and C_Club.SendBattleTagFriendRequest))
    return lines
end

Probe:Register("S8", "BNet_GetBattleTagSelf, C_Club.SendBattleTagFriendRequest", function()
    local lines = battleTagSelfLines()
    for _, l in ipairs(lines) do
        Probe:Log("S8 battletag", l)
    end
    local gotTag = false
    for _, l in ipairs(lines) do
        if l:find("battletag%-format") then gotTag = true end
    end
    return "info", (gotTag and "own BattleTag readable in the format Name#digits" or "own BattleTag NOT readable in the "
        .. "expected format") .. "; friend request still to test with /aacp btag friend (see the S8 log in the export)"
end)

-- /aacp btag [self|friend]: "friend" sends a REAL friend request to the character you are targeting (a volunteer).
Probe.commands.btag = function(arg)
    if arg == "friend" then
        local clubId = guildClubId()
        local okG, guid = call(UnitGUID, "target")
        if not clubId or not okG or not guid then
            Probe.Print("btag friend: be in a guild and target the volunteer first")
            return
        end
        local okM, members = call(C_Club.GetClubMembers, clubId)
        local found
        if okM and type(members) == "table" then
            for _, memberId in ipairs(members) do
                local okI, info = call(C_Club.GetMemberInfo, clubId, memberId)
                if okI and type(info) == "table" and info.guid == guid and not info.isSelf then
                    found = { id = memberId, hasBnet = info.bnetAccountId ~= nil }
                    break
                end
            end
        end
        if not found then
            Probe.Print("btag friend: the target is not a guild member (or is you)")
            return
        end
        local ok, err = call(C_Club.SendBattleTagFriendRequest, clubId, found.id)
        local line = string.format("SendBattleTagFriendRequest on the targeted volunteer (bnetAccountId present: %s): %s",
            tostring(found.hasBnet), ok and "call ok" or ("error: " .. tostring(err)))
        Probe:Log("S8 battletag", line)
        Probe.Print(line .. ". Ask the volunteer whether a friend request arrived, and note it: /aacp note S8 <text>")
    else
        local lines = battleTagSelfLines()
        for _, l in ipairs(lines) do
            Probe:Log("S8 battletag", l)
            Probe.Print(l)
        end
    end
end

-- Log the friend-request related events and club errors while the probe runs (counts and ids only).
local ev = CreateFrame("Frame")
for _, e in ipairs({ "CLUB_ERROR", "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_REMOVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "CLUB_ERROR" then
        Probe:Log("S8 battletag", "CLUB_ERROR action=" .. tostring(a1) .. " error=" .. tostring(a2) .. " type=" .. tostring(a3))
    else
        Probe:Log("S8 battletag", event .. " (args not stored)")
    end
end)

-- S10 --------------------------------------------------------------------------------------------------------------
Probe:Register("S10", "Account-wide SavedVariables across characters and realms; GetRealmName, connected realms in member names",
    function()
        local d = Probe.DB()
        d.accountStamps = d.accountStamps or {}
        local okG, guid = call(UnitGUID, "player")
        local charKey = tostring(okG and shortHash(guid) or "noguid")
        local okR, realm = call(GetRealmName)
        local okN, normalized = call(GetNormalizedRealmName)
        local realmKey = tostring(okR and shortHash(realm) or "norealm")
        local others, realms, sameRealmOthers = 0, {}, 0
        for key, stamp in pairs(d.accountStamps) do
            if key ~= charKey then
                others = others + 1
                realms[stamp.realm] = true
                if stamp.realm == realmKey then sameRealmOthers = sameRealmOthers + 1 end
            end
        end
        local otherRealms = 0
        for r in pairs(realms) do
            if r ~= realmKey then otherRealms = otherRealms + 1 end
        end
        local previouslyThisChar = d.accountStamps[charKey] ~= nil
        d.accountStamps[charKey] = { realm = realmKey, time = date("%Y-%m-%d %H:%M:%S") }
        local total = 0
        for _ in pairs(d.accountStamps) do total = total + 1 end
        local lines = {}
        lines[#lines + 1] = string.format("character <hash %s>, realm <hash %s>, previously stamped: %s", charKey, realmKey,
            tostring(previouslyThisChar))
        lines[#lines + 1] = string.format("GetRealmName: %s (has space: %s); GetNormalizedRealmName: %s (has space: %s)",
            okR and type(realm) or "error", tostring(okR and type(realm) == "string" and realm:find(" ") ~= nil),
            okN and type(normalized) or "error", tostring(okN and type(normalized) == "string" and normalized:find(" ") ~= nil))
        local okC, connected = call(GetAutoCompleteRealms)
        lines[#lines + 1] = "GetAutoCompleteRealms (connected realms): " .. (okC and type(connected) == "table"
            and (#connected .. " entries") or (okC and type(connected) or "error"))
        local okI, realmId = call(GetRealmID)
        lines[#lines + 1] = "GetRealmID: " .. (okI and type(realmId) or "error")
        if lastScan then
            lines[#lines + 1] = string.format("last S2 scan: names with a realm part=%d, other than own realm=%d, distinct realm parts=%d",
                lastScan.namesWithRealm, lastScan.namesOtherRealm, lastScan.realmCount)
        else
            lines[#lines + 1] = "no S2 scan yet in this session: run /aacp run S2 and then S10 again to add the realm-part counts"
        end
        for _, l in ipairs(lines) do
            Probe:Log("S10 account", l)
        end
        return "info", string.format("stamps stored for %d characters; seen from earlier characters: %d (on %d other realms, "
            .. "%d on this realm). Pass only when run again on a second character and it sees the first. See the S10 log.",
            total, others, otherRealms, sameRealmOthers)
    end)

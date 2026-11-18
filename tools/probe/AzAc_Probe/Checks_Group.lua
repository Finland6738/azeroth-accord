-- AzAc Probe, M0.6: S7, group and raid roster: UnitGUID, UnitIsInMyGuild, GetRaidRosterInfo, secret values, timing.
-- Lua 5.1. Every game API call goes through pcall. Never record names or GUIDs: only counts, types and shapes.
-- Secret values (issecretvalue) are only tested and counted, never compared, concatenated or printed.

local Probe = _G.AzAc_Probe
if not Probe then
    return
end

local call = Probe.Call

local function now()
    return (type(debugprofilestop) == "function" and debugprofilestop()) or 0
end

local function isSecret(v)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, r = pcall(issecretvalue, v)
    return ok and r == true
end

local function fnOrNil(name)
    local f = rawget(_G, name)
    return type(f) == "function" and f or nil
end

local function boolCall(fn, ...)
    if not fn then
        return nil
    end
    local ok, v = call(fn, ...)
    if ok then
        return v
    end
    return nil
end

--- Set of GUIDs of the guild club members (only used for counting matches, never stored).
local guidCache -- { time, set, n }: the club roster is read at most every 30 seconds (events can come in bursts)

local function guildGuidSet()
    if guidCache and now() - guidCache.time < 30000 then
        return guidCache.set, guidCache.n
    end
    local set, n = {}, 0
    local okG, clubId = call(C_Club and C_Club.GetGuildClubId)
    if not (okG and clubId) then
        return set, 0
    end
    local okM, members = call(C_Club.GetClubMembers, clubId)
    if not okM or type(members) ~= "table" then
        return set, 0
    end
    for _, memberId in ipairs(members) do
        local okI, info = call(C_Club.GetMemberInfo, clubId, memberId)
        if okI and type(info) == "table" and type(info.guid) == "string" and not isSecret(info.guid) then
            set[info.guid] = true
            n = n + 1
        end
    end
    guidCache = { time = now(), set = set, n = n }
    return set, n
end

local function unitList()
    local units = { "player" }
    local inRaid = boolCall(fnOrNil("IsInRaid"))
    local inGroup = boolCall(fnOrNil("IsInGroup"))
    local size = boolCall(fnOrNil("GetNumGroupMembers")) or 0
    local kind
    if inRaid == true then
        kind = "raid"
        units = {}
        for i = 1, math.max(size, 1) do
            units[#units + 1] = "raid" .. i
        end
    elseif inGroup == true or size > 1 then
        kind = "party"
        for i = 1, math.max(size - 1, 0) do
            units[#units + 1] = "party" .. i
        end
    else
        kind = "solo"
    end
    return units, kind, size
end

local function shape(v)
    if v == nil then
        return "nil"
    end
    if isSecret(v) then
        return "secret"
    end
    return type(v)
end

--- One scan of the group: aggregates, no names. Returns the summary table and a one-line text.
local function scan(label)
    local t0 = now()
    local units, kind, size = unitList()
    local guildGuids, guildCount = guildGuidSet()
    local r = { kind = kind, size = size, units = 0, exists = 0, guidReadable = 0, guidSecret = 0, guidNil = 0,
        inGuildTrue = 0, inGuildFalse = 0, inGuildSecret = 0, inGuildError = 0, guidMatchesClub = 0, guidPrefix = {},
        isPlayer = 0, nameSecret = 0, fullNameRealm = 0, raidInfoRows = 0, raidInfoSecretFields = 0, raidInfoFields = 0,
        identitySecret = 0, identityApi = 0 }
    local isInGuildFn = fnOrNil("UnitIsInMyGuild")
    local fullNameFn = fnOrNil("UnitFullName")
    local identityFn = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
    for i, unit in ipairs(units) do
        r.units = r.units + 1
        local okE, exists = call(UnitExists, unit)
        if okE and exists == true then
            r.exists = r.exists + 1
            local okG, guid = call(UnitGUID, unit)
            if not okG or guid == nil then
                r.guidNil = r.guidNil + 1
            elseif isSecret(guid) then
                r.guidSecret = r.guidSecret + 1
            else
                r.guidReadable = r.guidReadable + 1
                local prefix = type(guid) == "string" and guid:match("^(%a+)%-") or type(guid)
                r.guidPrefix[prefix] = (r.guidPrefix[prefix] or 0) + 1
                if guildGuids[guid] then r.guidMatchesClub = r.guidMatchesClub + 1 end
            end
            if isInGuildFn then
                local ok, v = call(isInGuildFn, unit)
                if not ok then
                    r.inGuildError = r.inGuildError + 1
                elseif isSecret(v) then
                    r.inGuildSecret = r.inGuildSecret + 1
                elseif v == true then
                    r.inGuildTrue = r.inGuildTrue + 1
                else
                    r.inGuildFalse = r.inGuildFalse + 1
                end
            end
            local okP, isPlayer = call(UnitIsPlayer, unit)
            if okP and not isSecret(isPlayer) and isPlayer == true then r.isPlayer = r.isPlayer + 1 end
            local okN, name = call(UnitName, unit)
            if okN and isSecret(name) then r.nameSecret = r.nameSecret + 1 end
            if fullNameFn then
                local okF, n2, realm = call(fullNameFn, unit)
                if okF and not isSecret(realm) and type(realm) == "string" and realm ~= "" then
                    r.fullNameRealm = r.fullNameRealm + 1
                end
            end
            if identityFn then
                local okS, sec = call(identityFn, unit)
                if okS then
                    r.identityApi = r.identityApi + 1
                    if sec == true then r.identitySecret = r.identitySecret + 1 end
                end
            end
        end
    end
    -- GetRaidRosterInfo(index): present only in a raid; count the returned fields and the secret ones
    local raidFn = fnOrNil("GetRaidRosterInfo")
    if kind == "raid" and raidFn then
        for i = 1, size do
            local res = { call(raidFn, i) }
            if res[1] then
                r.raidInfoRows = r.raidInfoRows + 1
                for k = 2, #res do
                    r.raidInfoFields = r.raidInfoFields + 1
                    if isSecret(res[k]) then r.raidInfoSecretFields = r.raidInfoSecretFields + 1 end
                end
                if r.raidInfoRows == 1 then
                    local types = {}
                    for k = 2, #res do types[#types + 1] = shape(res[k]) end
                    r.raidInfoShape = table.concat(types, ",")
                end
            end
        end
    end
    r.ms = now() - t0
    r.guildMembersKnown = guildCount
    local prefixes = {}
    for k, n in pairs(r.guidPrefix) do prefixes[#prefixes + 1] = k .. "=" .. n end
    table.sort(prefixes)
    local inInstance, instType = select(2, call(IsInInstance))
    local line = string.format(
        "[%s] %s size=%d units=%d exist=%d | UnitGUID readable=%d secret=%d nil=%d prefixes{%s} matchGuildClub=%d (club members known %d) | "
        .. "UnitIsInMyGuild true=%d false=%d secret=%d error=%d%s | UnitIsPlayer=%d nameSecret=%d fullNameWithRealm=%d | "
        .. "ShouldUnitIdentityBeSecret asked=%d yes=%d | GetRaidRosterInfo rows=%d fields=%d secretFields=%d shape=%s | "
        .. "instance=%s/%s encounter=%s HasSecretRestrictions=%s | scan %.1f ms",
        label, kind, size, r.units, r.exists, r.guidReadable, r.guidSecret, r.guidNil, table.concat(prefixes, ","),
        r.guidMatchesClub, guildCount, r.inGuildTrue, r.inGuildFalse, r.inGuildSecret, r.inGuildError,
        isInGuildFn and "" or " (UnitIsInMyGuild missing)", r.isPlayer, r.nameSecret, r.fullNameRealm, r.identityApi,
        r.identitySecret, r.raidInfoRows, r.raidInfoFields, r.raidInfoSecretFields, tostring(r.raidInfoShape),
        tostring(inInstance), tostring(instType),
        tostring(boolCall(C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress)),
        tostring(boolCall(C_Secrets and C_Secrets.HasSecretRestrictions)), r.ms)
    return r, line
end

-- Timing of GROUP_ROSTER_UPDATE and the delayed re-scans ---------------------------------------------------------------
local lastEventMs
local watching = false

local function after(seconds, fn)
    if C_Timer and C_Timer.After then
        pcall(C_Timer.After, seconds, fn)
    end
end

local function miniLine(r)
    return string.format("size=%d exist=%d guidReadable=%d guidSecret=%d inMyGuild=%d inMyGuildSecret=%d", r.size, r.exists,
        r.guidReadable, r.guidSecret, r.inGuildTrue, r.inGuildSecret)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "RAID_ROSTER_UPDATE", "ENCOUNTER_START", "ENCOUNTER_END" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    local t = now()
    local gap = lastEventMs and string.format("%.0f ms since the previous group event", t - lastEventMs) or "first group event"
    if event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        lastEventMs = t
        local size = boolCall(fnOrNil("GetNumGroupMembers")) or 0
        Probe:Log("S7 group", string.format("%s: group size %d (%s)", event, size, gap))
        if watching then
            for _, delay in ipairs({ 0, 1, 3 }) do
                after(delay, function()
                    local r = scan("event+" .. delay .. "s")
                    Probe:Log("S7 group", string.format("  after %s+%ds: %s", event, delay, miniLine(r)))
                end)
            end
        end
    else
        if watching then
            local r = scan(event)
            Probe:Log("S7 group", string.format("%s (boss id %s): %s", event, tostring(a1), miniLine(r)))
        else
            Probe:Log("S7 group", event .. " (watching is off)")
        end
    end
end)

-- /aacp group [<label> | watch on|off]
Probe.commands.group = function(arg, rest)
    if arg == "watch" then
        watching = (rest ~= "off")
        Probe.Print("group watching (scans after roster changes and at boss start/end): " .. tostring(watching))
        return
    end
    local label = (arg .. " " .. rest):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then label = "unlabelled" end
    local r, line = scan(label)
    Probe:Log("S7 group", line)
    Probe.Print(string.format("group scan [%s] stored: kind=%s size=%d guidReadable=%d guidSecret=%d inMyGuild=%d (%.1f ms)", label,
        r.kind, r.size, r.guidReadable, r.guidSecret, r.inGuildTrue, r.ms))
end

Probe:Register("S7", "Party and raid: UnitGUID, UnitIsInMyGuild, GetRaidRosterInfo, secret values in instances", function()
    watching = true
    local r, line = scan("run S7")
    Probe:Log("S7 group", line)
    local missing = {}
    for _, name in ipairs({ "UnitGUID", "UnitIsInMyGuild", "GetRaidRosterInfo", "IsInRaid", "IsInGroup", "GetNumGroupMembers",
        "UnitFullName" }) do
        if not fnOrNil(name) then missing[#missing + 1] = name end
    end
    return "info", string.format("kind=%s size=%d; UnitGUID readable=%d secret=%d; UnitIsInMyGuild true=%d secret=%d; "
        .. "GetRaidRosterInfo rows=%d; missing functions: %s. Watching ON: join a party, a raid, an instance, a boss "
        .. "and use /aacp group <label>; everything is in the S7 group log", r.kind, r.size, r.guidReadable, r.guidSecret,
        r.inGuildTrue, r.inGuildSecret, r.raidInfoRows, #missing > 0 and table.concat(missing, ",") or "none")
end)

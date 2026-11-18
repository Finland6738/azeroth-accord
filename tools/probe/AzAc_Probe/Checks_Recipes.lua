-- AzAc Probe, M0.4: S3 (native guild recipe directory) and S4 (own recipes, profession window open or closed).
-- Lua 5.1. Every game API call goes through pcall. Never record names: only counts, ids of recipes and professions,
-- types and shapes. Guild members are chosen by position and referred to as <player n>; GUIDs are never stored.

local Probe = _G.AzAc_Probe
if not Probe then
    return
end

local call = Probe.Call
local describe = Probe.Describe

local function now()
    return (type(debugprofilestop) == "function" and debugprofilestop()) or (GetTime and GetTime() * 1000) or 0
end

--- Finds an API by name in the global table and in the namespaces that might hold it. Returns fn, where.
local function findApi(name, namespaces)
    local g = rawget(_G, name)
    if type(g) == "function" then
        return g, "global"
    end
    for _, ns in ipairs(namespaces) do
        local t = rawget(_G, ns)
        if type(t) == "table" and type(t[name]) == "function" then
            return t[name], ns
        end
    end
    return nil, "missing"
end

local NS = { "C_GuildInfo", "C_TradeSkillUI", "C_Club" }

local function presence(names)
    local parts = {}
    for _, name in ipairs(names) do
        local _, where = findApi(name, NS)
        parts[#parts + 1] = name .. "=" .. where
    end
    return table.concat(parts, ", ")
end

local function describeResults(r)
    if not r[1] then
        return "error"
    end
    local parts = {}
    for i = 2, #r do
        local v = r[i]
        if type(v) == "table" then
            local n = #v
            local first = v[1]
            parts[#parts + 1] = string.format("table(n=%d%s)", n, first ~= nil and (", first is " .. describe(first)) or "")
        else
            parts[#parts + 1] = describe(v)
        end
    end
    return #parts > 0 and table.concat(parts, " / ") or "no return"
end

-- S3: the native guild recipe directory -------------------------------------------------------------------------------
local guildState = { events = 0, firstEventMs = nil, queryMs = nil }

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GUILD_RECIPE_KNOWN_BY_MEMBERS", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "SKILL_LINES_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

local ownScan -- forward declaration, defined in the S4 part

local autoCount = 0 -- automatic scans since the profession window opened (TRADE_SKILL_LIST_UPDATE can fire often)

ev:SetScript("OnEvent", function(_, event)
    if event == "GUILD_RECIPE_KNOWN_BY_MEMBERS" then
        guildState.events = guildState.events + 1
        if guildState.queryMs and not guildState.firstEventMs then
            guildState.firstEventMs = now() - guildState.queryMs
        end
        Probe:Log("S3 guild recipes", string.format("event GUILD_RECIPE_KNOWN_BY_MEMBERS #%d%s", guildState.events,
            guildState.queryMs and string.format(" (%.0f ms after the last query)", now() - guildState.queryMs) or ""))
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE" then
        Probe:Log("S4 own recipes", event .. " (profession window)")
        if event == "TRADE_SKILL_SHOW" then
            autoCount = 0
        end
        if event == "TRADE_SKILL_SHOW" and ownScan and Probe.autoScan then
            -- the list may not be ready yet: scan now and again when TRADE_SKILL_LIST_UPDATE arrives
            ownScan("window open (TRADE_SKILL_SHOW)")
        end
    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        if ownScan and Probe.autoScan and autoCount < 6 then
            autoCount = autoCount + 1
            ownScan("window open (" .. event .. ")")
        end
    end
end)

--- Distinct profession ids (skill lines) found in the guild roster, and up to `max` online members that have one.
local function rosterProfessions(max)
    local ids, picks = {}, {}
    local okG, clubId = call(C_Club and C_Club.GetGuildClubId)
    if not (okG and clubId) then
        return ids, picks, "no guild club id"
    end
    local okM, members = call(C_Club.GetClubMembers, clubId)
    if not okM or type(members) ~= "table" then
        return ids, picks, "GetClubMembers failed"
    end
    local offlineValue = 3
    pcall(function() offlineValue = Enum.ClubMemberPresence.Offline end)
    for _, memberId in ipairs(members) do
        local okI, info = call(C_Club.GetMemberInfo, clubId, memberId)
        if okI and type(info) == "table" and not info.isSelf then
            local mine = {}
            for _, k in ipairs({ "profession1ID", "profession2ID" }) do
                local id = info[k]
                if type(id) == "number" and id ~= 0 then
                    ids[id] = (ids[id] or 0) + 1
                    mine[#mine + 1] = id
                end
            end
            if #picks < max and #mine > 0 and info.guid and info.presence ~= offlineValue then
                picks[#picks + 1] = { guid = info.guid, skillLines = mine }
            end
        end
    end
    return ids, picks, nil
end

local function guildStatic()
    local lines = {}
    local function add(l) lines[#lines + 1] = l end
    add("API presence: " .. presence({ "IsGuildTradeSkillsEnabled", "QueryGuildMemberRecipes", "QueryGuildMembersForRecipe",
        "GetGuildMemberRecipes", "GetGuildTradeSkillInfo", "GetNumGuildTradeSkill", "GetGuildRecipeInfo",
        "GetGuildMembersForRecipe" }))
    local fn = findApi("IsGuildTradeSkillsEnabled", NS)
    local ok, enabled = call(fn)
    add("IsGuildTradeSkillsEnabled(): " .. (ok and tostring(enabled) or "error/missing"))
    return lines, ok and enabled
end

--- Calls every plausible getter with a few argument shapes and describes the results.
local function tryGetters(label, member, skillLineID, recipeSpellID)
    for _, name in ipairs({ "GetGuildMemberRecipes", "GetGuildRecipeInfo" }) do
        local fn, where = findApi(name, NS)
        if fn then
            for _, args in ipairs({ { member.guid, skillLineID }, { skillLineID, member.guid }, { member.guid } }) do
                local r = { call(fn, unpack(args)) }
                Probe:Log("S3 guild recipes", string.format("%s: %s(%s) from %s -> %s", label, name,
                    #args == 1 and "<guid>" or (args[1] == member.guid and "<guid>, skillLine" or "skillLine, <guid>"), where,
                    describeResults(r)))
            end
        end
    end
    local numFn = findApi("GetNumGuildTradeSkill", NS)
    local infoFn = findApi("GetGuildTradeSkillInfo", NS)
    if numFn then
        local r = { call(numFn) }
        Probe:Log("S3 guild recipes", label .. ": GetNumGuildTradeSkill() -> " .. describeResults(r))
        if infoFn and r[1] and type(r[2]) == "number" and r[2] > 0 then
            local r1 = { call(infoFn, 1) }
            Probe:Log("S3 guild recipes", label .. ": GetGuildTradeSkillInfo(1) -> " .. describeResults(r1))
        end
    end
    if recipeSpellID then
        local fn = findApi("QueryGuildMembersForRecipe", NS)
        if fn then
            local r = { call(fn, skillLineID, recipeSpellID) }
            Probe:Log("S3 guild recipes", label .. ": QueryGuildMembersForRecipe(skillLine, recipe) -> " .. describeResults(r))
        end
    end
end

--- /aacp recipes guild [n]: asks the guild directory about up to n online members' professions, waits, reads back.
local function guildQuery(n)
    local static = guildStatic()
    for _, l in ipairs(static) do
        Probe:Log("S3 guild recipes", l)
    end
    local ids, picks, err = rosterProfessions(n)
    if err then
        Probe.Print("recipes guild: " .. err)
        return
    end
    local idList = {}
    for id, count in pairs(ids) do idList[#idList + 1] = id .. "x" .. count end
    table.sort(idList)
    Probe:Log("S3 guild recipes", "profession ids seen in the roster (id x members): " .. table.concat(idList, " "))
    if #picks == 0 then
        Probe.Print("recipes guild: no online guildmate with a profession found")
        return
    end
    local queryFn = findApi("QueryGuildMemberRecipes", NS)
    if not queryFn then
        Probe.Print("recipes guild: QueryGuildMemberRecipes missing")
        return
    end
    guildState.events, guildState.firstEventMs = 0, nil
    guildState.queryMs = now()
    for i, pick in ipairs(picks) do
        for _, skillLine in ipairs(pick.skillLines) do
            local ok, e = call(queryFn, pick.guid, skillLine)
            Probe:Log("S3 guild recipes", string.format("QueryGuildMemberRecipes(<player %d>, skillLine %d): %s", i, skillLine,
                ok and "call ok" or ("error: " .. tostring(e))))
        end
    end
    Probe.Print(string.format("recipes guild: queried %d guildmates, reading back in 6 seconds", #picks))
    local function readBack()
        for i, pick in ipairs(picks) do
            for _, skillLine in ipairs(pick.skillLines) do
                tryGetters(string.format("<player %d> skillLine %d", i, skillLine), pick, skillLine, nil)
            end
        end
        local details = string.format("queried %d online guildmates; GUILD_RECIPE_KNOWN_BY_MEMBERS fired %d times (first after %s ms)",
            #picks, guildState.events, guildState.firstEventMs and string.format("%.0f", guildState.firstEventMs) or "never")
        Probe:Record("S3", "info", details .. " (getter results in the S3 guild recipes log)")
        Probe.Print("S3 [info] " .. details)
    end
    if C_Timer and C_Timer.After and pcall(C_Timer.After, 6, readBack) then
        return
    end
    readBack()
end

Probe:Register("S3", "Native guild recipe directory (IsGuildTradeSkillsEnabled, QueryGuildMemberRecipes, GUILD_RECIPE_KNOWN_BY_MEMBERS, GetGuildMemberRecipes, GetGuildTradeSkillInfo)",
    function()
        local lines, enabled = guildStatic()
        for _, l in ipairs(lines) do
            Probe:Log("S3 guild recipes", l)
        end
        return "info", lines[1] .. "; enabled=" .. tostring(enabled)
            .. ". Now run /aacp recipes guild to query online guildmates (the answer is in the S3 log)."
    end)

-- S4: own recipes -------------------------------------------------------------------------------------------------------
local OWN_FUNCS = { "GetAllRecipeIDs", "GetFilteredRecipeIDs", "GetBaseProfessionInfo", "GetChildProfessionInfos",
    "GetAllProfessionTradeSkillLines", "GetProfessionInfoBySkillLineID", "GetRecipeInfo", "GetRecipeSchematic",
    "OpenTradeSkill", "GetProfessionSkillLineID", "GetProfessionChildSkillLineID", "GetProfessionSpells",
    "GetCategories", "GetSubCategories" }

local scans = {} -- label -> last summary (also stored in the result)

ownScan = function(label)
    local t0 = now()
    local T = C_TradeSkillUI
    if not T then
        Probe:Log("S4 own recipes", label .. ": C_TradeSkillUI missing")
        return
    end
    local parts = {}
    local okB, base = call(T.GetBaseProfessionInfo)
    if okB and type(base) == "table" then
        local keys = {}
        for k, v in pairs(base) do
            if type(v) == "number" or type(v) == "boolean" then
                keys[#keys + 1] = k .. "=" .. tostring(v)
            else
                keys[#keys + 1] = k .. ":" .. type(v)
            end
        end
        table.sort(keys)
        parts[#parts + 1] = "base profession {" .. table.concat(keys, ",") .. "}"
    else
        parts[#parts + 1] = "GetBaseProfessionInfo: " .. (okB and describe(base) or "error/missing")
    end
    local idsFn = T.GetAllRecipeIDs or T.GetFilteredRecipeIDs
    local idsName = T.GetAllRecipeIDs and "GetAllRecipeIDs" or (T.GetFilteredRecipeIDs and "GetFilteredRecipeIDs" or "none")
    local total, learned, keys = 0, 0, {}
    if idsFn then
        local ok, ids = call(idsFn)
        if ok and type(ids) == "table" then
            total = #ids
            for i = 1, math.min(total, 3000) do
                local okR, info = call(T.GetRecipeInfo, ids[i])
                if okR and type(info) == "table" then
                    if info.learned then learned = learned + 1 end
                    if i == 1 then
                        for k, v in pairs(info) do keys[#keys + 1] = k .. ":" .. type(v) end
                        table.sort(keys)
                    end
                end
            end
        else
            parts[#parts + 1] = idsName .. ": " .. (ok and describe(ids) or "error")
        end
    end
    local lines = {}
    local okL, lineIds = call(T.GetAllProfessionTradeSkillLines)
    if okL and type(lineIds) == "table" then
        lines[#lines + 1] = "GetAllProfessionTradeSkillLines n=" .. #lineIds
    end
    local okC, children = call(T.GetChildProfessionInfos)
    if okC and type(children) == "table" then
        lines[#lines + 1] = "GetChildProfessionInfos n=" .. #children
    end
    local ms = now() - t0
    local summary = string.format("%s: %s; ids from %s: %d, learned %d, scan %.1f ms; %s; GetRecipeInfo keys: %s",
        label, table.concat(parts, "; "), idsName, total, learned, ms, table.concat(lines, ", "),
        #keys > 0 and table.concat(keys, ",") or "none read")
    scans[label] = summary
    Probe:Log("S4 own recipes", summary)
    return total, learned, ms
end

Probe:Register("S4", "Own recipes from the profession window (GetAllRecipeIDs, GetRecipeInfo, GetBaseProfessionInfo); is the window needed open?",
    function()
        Probe:Log("S4 own recipes", "API presence in C_TradeSkillUI: " .. (function()
            local parts = {}
            for _, name in ipairs(OWN_FUNCS) do
                parts[#parts + 1] = name .. "=" .. ((C_TradeSkillUI and type(C_TradeSkillUI[name]) == "function") and "yes" or "no")
            end
            return table.concat(parts, ", ")
        end)())
        local isOpen = false
        pcall(function() isOpen = TradeSkillFrame and TradeSkillFrame:IsShown() or false end)
        local total, learned, ms = ownScan(isOpen and "window OPEN, manual run" or "window CLOSED, manual run")
        Probe.autoScan = true -- from now on every profession window opening is scanned and logged
        return "info", string.format("manual scan with the window %s: %s recipe ids, %s learned, %.1f ms. Automatic scans are now "
            .. "ON: open each profession window, then /aacp export", isOpen and "open" or "closed", tostring(total),
            tostring(learned), ms or 0)
    end)

-- /aacp recipes [guild [n] | own | open <skillLineID> | auto on|off]
Probe.commands.recipes = function(arg, rest)
    if arg == "guild" then
        guildQuery(tonumber(rest) or 3)
    elseif arg == "own" then
        ownScan("manual /aacp recipes own")
        Probe.Print("scan stored in the S4 own recipes log (/aacp export)")
    elseif arg == "open" then
        local id = tonumber(rest)
        if not id then
            Probe.Print("usage: /aacp recipes open <skillLineID> (ids: /aacp recipes own, or the S3 profession ids)")
            return
        end
        local ok, r = call(C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill, id)
        Probe:Log("S4 own recipes", string.format("OpenTradeSkill(%d): %s", id, ok and tostring(r) or ("error: " .. tostring(r))))
        Probe.Print("OpenTradeSkill: " .. (ok and tostring(r) or "error") .. " (an ADDON_ACTION_BLOCKED would be logged)")
    elseif arg == "auto" then
        Probe.autoScan = (rest ~= "off")
        Probe.Print("automatic scan on profession window events: " .. tostring(Probe.autoScan))
    else
        Probe.Print("usage: /aacp recipes guild [n] | own | open <skillLineID> | auto on|off")
    end
end

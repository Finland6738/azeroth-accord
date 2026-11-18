-- AzAc Probe, M0.7: S9 (guild bank: tabs, items, money, logs, events) and S11 (performance on generated data).
-- Lua 5.1. Every game API call goes through pcall. Never record names: tab names become <tab n>, log names are dropped.
-- S11 runs on generated data only (placeholders such as "Name123"), nothing from the real guild.

local Probe = _G.AzAc_Probe
if not Probe then
    return
end

local call = Probe.Call
local describe = Probe.Describe

local function now()
    return (type(debugprofilestop) == "function" and debugprofilestop()) or (GetTime and GetTime() * 1000) or 0
end

local function fnOrNil(name)
    local f = rawget(_G, name)
    return type(f) == "function" and f or nil
end

-- S9: guild bank -------------------------------------------------------------------------------------------------------
local bank = { openedAt = nil, counts = {}, lastEvent = {}, tabEvents = {} }

local BANK_EVENTS = { "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANKLOG_UPDATE",
    "GUILDBANK_UPDATE_TABS", "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_WITHDRAWMONEY", "GUILDBANK_UPDATE_TEXT",
    "GUILDBANK_TEXT_CHANGED", "GUILDBANK_ITEM_LOCK_CHANGED" }

local ev = CreateFrame("Frame")
for _, e in ipairs(BANK_EVENTS) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    local t = now()
    bank.counts[event] = (bank.counts[event] or 0) + 1
    bank.lastEvent[event] = t
    if event == "GUILDBANKFRAME_OPENED" then
        bank.openedAt = t
    elseif event == "GUILDBANKFRAME_CLOSED" then
        bank.openedAt = nil
    end
    local since = bank.openedAt and string.format("%.0f ms after the vault opened", t - bank.openedAt) or "vault not open"
    if bank.counts[event] <= 25 then
        Probe:Log("S9 bank events", string.format("%s #%d (%s)", event, bank.counts[event], since))
    end
end)

local BANK_FUNCS = { "GetNumGuildBankTabs", "GetGuildBankTabInfo", "GetGuildBankItemInfo", "GetGuildBankItemLink",
    "GetGuildBankMoney", "GetGuildBankWithdrawMoney", "GetCurrentGuildBankTab", "SetCurrentGuildBankTab", "QueryGuildBankTab",
    "QueryGuildBankLog", "GetNumGuildBankTransactions", "GetGuildBankTransaction", "GetNumGuildBankMoneyTransactions",
    "GetGuildBankMoneyTransaction", "QueryGuildBankText", "GetGuildBankText", "GetGuildBankTabPermissions",
    "GetGuildBankWithdrawGoldLimit", "CanWithdrawGuildBankMoney", "CanGuildBankRepair", "GetNumGuildBankTabsPurchased" }

local function presenceLine()
    local parts = {}
    for _, name in ipairs(BANK_FUNCS) do
        local where = "missing"
        if fnOrNil(name) then
            where = "global"
        elseif C_GuildBank and type(C_GuildBank[name]) == "function" then
            where = "C_GuildBank"
        end
        parts[#parts + 1] = name .. "=" .. where
    end
    return table.concat(parts, ", ")
end

local function roleLine()
    local okO, officer = call(C_GuildInfo and C_GuildInfo.IsGuildOfficer)
    local okL, leader = call(fnOrNil("IsGuildLeader"))
    local rank
    local r = { call(GetGuildInfo, "player") }
    if r[1] then rank = r[4] end
    return string.format("role: officer=%s leader=%s rankIndex=%s", okO and tostring(officer) or "n/a",
        okL and tostring(leader) or "n/a", tostring(rank))
end

local function wait(seconds, fn)
    if C_Timer and C_Timer.After and pcall(C_Timer.After, seconds, fn) then
        return
    end
    fn()
end

local MONEY_LOG_TAB -- the money log is queried with tab number MAX_GUILDBANK_TABS + 1
do
    local max = rawget(_G, "MAX_GUILDBANK_TABS")
    MONEY_LOG_TAB = (type(max) == "number" and max or 8) + 1
end

--- Reads the log of one tab (or the money log): count, shape of first/last entries, never names.
local function readLog(tab, label)
    local isMoney = (tab == MONEY_LOG_TAB)
    local numFn = fnOrNil(isMoney and "GetNumGuildBankMoneyTransactions" or "GetNumGuildBankTransactions")
    local getFn = fnOrNil(isMoney and "GetGuildBankMoneyTransaction" or "GetGuildBankTransaction")
    if not (numFn and getFn) then
        Probe:Log("S9 bank", label .. ": log getters missing")
        return
    end
    local okN, n = call(numFn, not isMoney and tab or nil)
    if not okN or type(n) ~= "number" then
        Probe:Log("S9 bank", label .. ": count error (" .. describe(n) .. ")")
        return
    end
    local function entry(i)
        local r = { call(getFn, not isMoney and tab or i, not isMoney and i or nil) }
        if not r[1] then return "error" end
        local parts = {}
        for k = 2, #r do
            local v = r[k]
            if type(v) == "string" then
                parts[#parts + 1] = k - 1 .. ":string(" .. (v:find("|H") and "itemlink" or "text") .. ")"
            else
                parts[#parts + 1] = k - 1 .. ":" .. tostring(v)
            end
        end
        return table.concat(parts, " ")
    end
    Probe:Log("S9 bank", string.format("%s: %d entries; first [%s]; last [%s] (fields: type, name dropped, item/amount, count, tab1, tab2, "
        .. "year, month, day, hour as returned)", label, n, n >= 1 and entry(1) or "-", n >= 1 and entry(n) or "-"))
    return n
end

--- /aacp bank: reads the open guild vault tab by tab (permissions, items, money, logs) with timings.
local function bankScan()
    local tabsFn = fnOrNil("GetNumGuildBankTabs")
    if not tabsFn then
        Probe.Print("bank: GetNumGuildBankTabs missing (see /aacp run S9 for the API presence)")
        return
    end
    Probe:Log("S9 bank", "--- scan " .. date("%H:%M:%S") .. " " .. roleLine())
    local okT, numTabs = call(tabsFn)
    if not okT or type(numTabs) ~= "number" or numTabs == 0 then
        Probe:Log("S9 bank", "no tabs readable: GetNumGuildBankTabs -> " .. describe(numTabs) .. " (is the vault window open?)")
        Probe.Print("bank: no tabs readable, open the guild vault first")
        return
    end
    Probe:Log("S9 bank", "tabs: " .. numTabs)
    local money = select(2, call(fnOrNil("GetGuildBankMoney")))
    local withdraw = select(2, call(fnOrNil("GetGuildBankWithdrawMoney")))
    Probe:Log("S9 bank", string.format("money: type %s value %s copper; withdraw allowance: type %s value %s",
        type(money), tostring(money), type(withdraw), tostring(withdraw)))
    local viewable = {}
    for i = 1, numTabs do
        local r = { call(fnOrNil("GetGuildBankTabInfo"), i) }
        if r[1] then
            -- name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals
            Probe:Log("S9 bank", string.format("<tab %d>: info fields %d | name:%s icon:%s isViewable=%s canDeposit=%s numWithdrawals=%s "
                .. "remainingWithdrawals=%s", i, #r - 1, type(r[2]), type(r[3]), tostring(r[4]), tostring(r[5]), tostring(r[6]),
                tostring(r[7])))
            if r[4] then viewable[#viewable + 1] = i end
        else
            Probe:Log("S9 bank", string.format("<tab %d>: GetGuildBankTabInfo error", i))
        end
    end
    Probe:Log("S9 bank", string.format("viewable tabs: %d of %d", #viewable, numTabs))
    local summary = { tabs = numTabs, viewable = #viewable, items = {} }
    -- one tab at a time: select it, query it, wait for GUILDBANKBAGSLOTS_CHANGED (or 3 s), count the filled slots, read the log
    local index = 0
    local function nextTab()
        index = index + 1
        if index > #viewable then
            -- money log last
            local q = fnOrNil("QueryGuildBankLog")
            if q then call(q, MONEY_LOG_TAB) end
            wait(2, function()
                readLog(MONEY_LOG_TAB, "money log")
                local text = string.format("%s; tabs %d (viewable %d); items per viewable tab {%s}; money %s", roleLine(), numTabs,
                    #viewable, table.concat(summary.items, ", "), tostring(money))
                Probe:Record("S9", "info", text)
                Probe.Print("S9 [info] " .. text)
            end)
            return
        end
        local tab = viewable[index]
        local before = bank.counts["GUILDBANKBAGSLOTS_CHANGED"] or 0
        local t0 = now()
        call(fnOrNil("SetCurrentGuildBankTab"), tab)
        call(fnOrNil("QueryGuildBankTab"), tab)
        local logQuery = fnOrNil("QueryGuildBankLog")
        if logQuery then call(logQuery, tab) end
        wait(2.5, function()
            local after = bank.counts["GUILDBANKBAGSLOTS_CHANGED"] or 0
            local filled, links = 0, 0
            local slots = 98
            local infoFn, linkFn = fnOrNil("GetGuildBankItemInfo"), fnOrNil("GetGuildBankItemLink")
            local firstShape
            for slot = 1, slots do
                local r = { call(infoFn, tab, slot) }
                if r[1] and r[2] ~= nil then
                    filled = filled + 1
                    if not firstShape then
                        local types = {}
                        for k = 2, #r do types[#types + 1] = type(r[k]) end
                        firstShape = table.concat(types, ",")
                    end
                    if linkFn then
                        local okL, link = call(linkFn, tab, slot)
                        if okL and link then links = links + 1 end
                    end
                end
            end
            summary.items[#summary.items + 1] = string.format("tab%d:%d", tab, filled)
            Probe:Log("S9 bank", string.format("<tab %d>: %d filled slots of %d (item links %d, GetGuildBankItemInfo shape %s); "
                .. "GUILDBANKBAGSLOTS_CHANGED +%d after %s", tab, filled, slots, links, tostring(firstShape), after - before,
                bank.lastEvent["GUILDBANKBAGSLOTS_CHANGED"] and string.format("%.0f ms", bank.lastEvent["GUILDBANKBAGSLOTS_CHANGED"] - t0)
                or "no event"))
            readLog(tab, string.format("<tab %d> log", tab))
            nextTab()
        end)
    end
    Probe.Print(string.format("bank: reading %d viewable tabs (about %.0f seconds), the final line follows", #viewable, #viewable * 2.5 + 3))
    nextTab()
end

Probe.commands.bank = function(arg)
    if arg == "presence" then
        Probe:Log("S9 bank", "API presence: " .. presenceLine())
        Probe.Print("presence stored")
    else
        bankScan()
    end
end

Probe:Register("S9", "Guild bank: tabs visible to a member and an officer, items, money, logs (time format, length), events", function()
    local line = presenceLine()
    Probe:Log("S9 bank", "API presence: " .. line)
    local okE, en = call(C_GuildBank and C_GuildBank.IsGuildBankEnabled)
    local missing = 0
    for _ in line:gmatch("=missing") do missing = missing + 1 end
    local events = {}
    for e, n in pairs(bank.counts) do events[#events + 1] = e .. "=" .. n end
    table.sort(events)
    return "info", string.format("%s; C_GuildBank.IsGuildBankEnabled=%s; %d of %d legacy functions missing; vault events seen: %s. "
        .. "Open the vault and run /aacp bank (as a member, then as an officer)", roleLine(), okE and tostring(en) or "n/a", missing,
        #BANK_FUNCS, #events > 0 and table.concat(events, ",") or "none")
end)

-- S11: performance on generated data ---------------------------------------------------------------------------------------
local seed = 12345
local function rnd(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n + 1
end

local function memKb()
    return collectgarbage("count")
end

--- Social index of SPEC-07 §3.2 for every account, plus the weighted label propagation of §3.3. Returns timings in ms.
local function perfIndex(accounts)
    local t = {}
    local days, pairsPerAccountPerDay = 30, 6
    local mem0 = memKb()

    -- 1. generate pair-day minutes as seen by two observers and merge with the maximum (SOC-03)
    local t0 = now()
    local pairDay = {} -- key "a:b:day" -> minutes (max of the observers)
    local entries = 0
    for day = 1, days do
        for a = 1, accounts do
            for _ = 1, pairsPerAccountPerDay do
                local b = rnd(accounts)
                if b ~= a then
                    local lo, hi = math.min(a, b), math.max(a, b)
                    local key = (lo * 4096 + hi) * 32 + day -- accounts < 4096, day < 32
                    local m1, m2 = rnd(120), rnd(120)
                    local cur = pairDay[key]
                    local m = math.max(m1, m2)
                    if not cur then entries = entries + 1 end
                    if not cur or m > cur then pairDay[key] = m end
                end
            end
        end
    end
    t.generateMerge = now() - t0

    -- 2. aggregate to minutes per pair (sum over days)
    t0 = now()
    local minutes = {} -- minutes[a][b]
    for a = 1, accounts do minutes[a] = {} end
    for key, m in pairs(pairDay) do
        local day = key % 32
        local rest = (key - day) / 32
        local hi = rest % 4096
        local lo = (rest - hi) / 4096
        local a, b = lo, hi
        if a >= 1 and a <= accounts and b >= 1 and b <= accounts then
            minutes[a][b] = (minutes[a][b] or 0) + m
            minutes[b][a] = (minutes[b][a] or 0) + m
        end
    end
    t.aggregate = now() - t0

    -- 3. index for every account
    t0 = now()
    local active = 0
    local total = {}
    for a = 1, accounts do
        local sum = 0
        for _, m in pairs(minutes[a]) do sum = sum + m end
        total[a] = sum
        if sum >= 60 then active = active + 1 end
    end
    local indexSum = 0
    for a = 1, accounts do
        local M = total[a]
        local H = 0
        if M > 0 then
            for _, m in pairs(minutes[a]) do
                local p = m / M
                H = H - p * math.log(p)
            end
        end
        local N = math.exp(H)
        local idx = math.min(100, math.floor(100 * N / math.max(1, active - 1) + 0.5))
        indexSum = indexSum + idx
    end
    t.index = now() - t0
    t.indexPerAccount = t.index / accounts
    t.meanIndex = indexSum / accounts

    -- 4. label propagation (10 iterations) and modularity
    t0 = now()
    local label = {}
    for a = 1, accounts do label[a] = a end
    local order = {}
    for a = 1, accounts do order[a] = a end
    for _ = 1, 10 do
        local changed = 0
        for _, a in ipairs(order) do
            local weights, best, bestW = {}, label[a], -1
            for b, m in pairs(minutes[a]) do
                local l = label[b]
                weights[l] = (weights[l] or 0) + m
            end
            for l, w in pairs(weights) do
                if w > bestW then best, bestW = l, w end
            end
            if best ~= label[a] then label[a] = best; changed = changed + 1 end
        end
        if changed == 0 then break end
    end
    local twoM = 0
    for a = 1, accounts do twoM = twoM + total[a] end
    local Q = 0
    local communities = {}
    for a = 1, accounts do
        communities[label[a]] = true
        for b, m in pairs(minutes[a]) do
            if label[a] == label[b] then
                Q = Q + (m - total[a] * total[b] / math.max(1, twoM))
            end
        end
    end
    t.communities = 0
    for _ in pairs(communities) do t.communities = t.communities + 1 end
    t.modularity = Q / math.max(1, twoM)
    t.labelPropagation = now() - t0

    -- 5. serialize the merged pair-day data as the sync snapshot would ("lo:hi:day:min" per entry)
    t0 = now()
    local parts = {}
    for key, m in pairs(pairDay) do parts[#parts + 1] = key .. ":" .. m end
    local blob = table.concat(parts, ";")
    t.serialize = now() - t0
    t.entries, t.blobBytes = entries, #blob
    t.memKb = memKb() - mem0
    return t
end

local ROW_CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "DRUID", "SHAMAN", "PALADIN", "WARLOCK" }

--- Roster of `n` generated members: build, sort by several columns, filter, format the visible rows.
local function perfRoster(n)
    local t = {}
    local mem0 = memKb()
    local t0 = now()
    local rows = {}
    for i = 1, n do
        rows[i] = { name = "Name" .. rnd(1000000), class = ROW_CLASSES[rnd(#ROW_CLASSES)], level = rnd(60), rank = rnd(6),
            zone = "Zone" .. rnd(80), ap = rnd(20000), prof1 = rnd(12), prof2 = rnd(12), rank1 = rnd(300), rank2 = rnd(300),
            lastOnline = rnd(5000), account = rnd(math.max(1, math.floor(n / 3))), online = rnd(4) == 1 }
    end
    t.build = now() - t0

    local function timeSort(label, cmp)
        local copy = {}
        for i = 1, n do copy[i] = rows[i] end
        local s = now()
        table.sort(copy, cmp)
        t[label] = now() - s
    end
    timeSort("sortName", function(a, b) return a.name < b.name end)
    timeSort("sortLevel", function(a, b) if a.level ~= b.level then return a.level > b.level end return a.name < b.name end)
    timeSort("sortLastOnline", function(a, b) if a.online ~= b.online then return a.online end return a.lastOnline < b.lastOnline end)

    t0 = now()
    local matches = 0
    for i = 1, n do
        local r = rows[i]
        if r.name:lower():find("name1", 1, true) or r.zone:lower():find("zone7", 1, true) then matches = matches + 1 end
    end
    t.filter = now() - t0

    t0 = now()
    local visible = 30
    local text = {}
    for i = 1, visible do
        local r = rows[i]
        text[i] = string.format("%s  %d  %s  %d/%d  %s", r.name, r.level, r.class, r.rank1, r.rank2, r.zone)
    end
    t.formatVisible = now() - t0

    -- alts grouped by account (SPEC-05): one pass building the account -> characters map
    t0 = now()
    local byAccount = {}
    for i = 1, n do
        local r = rows[i]
        local l = byAccount[r.account] or {}
        byAccount[r.account] = l
        l[#l + 1] = r
    end
    t.groupAccounts = now() - t0
    t.memKb = memKb() - mem0
    t.matches = matches
    return t
end

local function ms(v) return string.format("%.1f", v or 0) end

--- /aacp perf [sizes...]: runs the roster and index tests for each size and stores the lines.
local function runPerf(sizes)
    local lines = {}
    for _, size in ipairs(sizes) do
        collectgarbage()
        local r = perfRoster(size)
        local i = perfIndex(size)
        local line = string.format("size %d | roster: build %s, sort name %s, sort level %s, sort lastOnline %s, filter %s, format 30 "
            .. "visible rows %s, group accounts %s ms, memory +%.0f KB | index: generate+merge %s, aggregate %s, index for all %s "
            .. "(%s ms per account), label propagation %s (%d communities, Q=%.2f), serialize %s ms (%d pair-day entries, %d bytes), "
            .. "memory +%.0f KB",
            size, ms(r.build), ms(r.sortName), ms(r.sortLevel), ms(r.sortLastOnline), ms(r.filter), ms(r.formatVisible),
            ms(r.groupAccounts), r.memKb, ms(i.generateMerge), ms(i.aggregate), ms(i.index), ms(i.indexPerAccount),
            ms(i.labelPropagation), i.communities, i.modularity, ms(i.serialize), i.entries, i.blobBytes, i.memKb)
        lines[#lines + 1] = line
        Probe:Log("S11 perf", line)
        collectgarbage()
    end
    return lines
end

Probe.commands.perf = function(arg, rest)
    local sizes = {}
    for token in ((arg or "") .. " " .. (rest or "")):gmatch("%d+") do
        sizes[#sizes + 1] = math.min(tonumber(token), 3000)
    end
    if #sizes == 0 then
        sizes = { 500, 1000 }
    end
    Probe.Print("perf: running " .. table.concat(sizes, ", ") .. " members on generated data (the game may freeze for a moment)")
    local ok, lines = pcall(runPerf, sizes)
    if not ok then
        Probe.Print("perf error: " .. tostring(lines))
        return
    end
    for _, l in ipairs(lines) do
        Probe.Print(l)
    end
end

Probe:Register("S11", "Performance: social index and 500+ member roster on generated data", function()
    local ok, lines = pcall(runPerf, { 500 })
    if not ok then
        return "fail", "error: " .. tostring(lines)
    end
    return "info", lines[1] .. " | /aacp perf 1000 2000 for bigger guilds; compare with the budget in SPEC-07 (about 10 minutes between runs, in chunks)"
end)

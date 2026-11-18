-- AzAc Probe, M0.5: S5 (addon messages on GUILD and OFFICER, rate, lockdown) and S6 (addon WHISPER between guildmates).
-- Lua 5.1. Every game API call goes through pcall. Only the TEST prefix "AzAcP" is ever registered or sent.
-- Never record names: senders are only compared with the own name ("self" / "other"); whisper targets are never stored.

local Probe = _G.AzAc_Probe
if not Probe then
    return
end

local call = Probe.Call
local PREFIX = Probe:AssertTestPrefix(Probe.TEST_PREFIX)
local MAX_BURST, MAX_SIZE = 200, 255

local function db()
    local d = Probe.DB()
    d.msg = d.msg or { sent = {}, codes = {}, recv = {}, echo = {}, runs = {}, locked = {}, secret = 0 }
    return d.msg
end

local function now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function isSecret(v)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, r = pcall(issecretvalue, v)
    return ok and r == true
end

-- Result codes: the client returns an Enum.SendAddonMessageResult value (or a boolean); keep the raw value and its name.
local codeNames
local function codeName(v)
    if codeNames == nil then
        codeNames = {}
        pcall(function()
            for name, value in pairs(Enum.SendAddonMessageResult) do
                codeNames[value] = name
            end
        end)
    end
    if type(v) == "boolean" then
        return "bool:" .. tostring(v)
    end
    return tostring(v) .. (codeNames[v] and ("=" .. codeNames[v]) or "")
end

local ownName
local function isSelf(sender)
    if type(sender) ~= "string" then
        return false
    end
    if not ownName then
        local ok, n = call(UnitName, "player")
        ownName = ok and n or false
    end
    return ownName and sender:match("^[^-]+") == ownName or false
end

local registerResult
local function ensureRegistered()
    if registerResult == nil then
        local fn = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
        local ok, r = call(fn, PREFIX)
        registerResult = ok and ("RegisterAddonMessagePrefix(" .. PREFIX .. "): " .. tostring(r)) or "RegisterAddonMessagePrefix failed"
        Probe:Log("S5 messaging", registerResult)
    end
    return registerResult
end

local function count(t, key)
    t[key] = (t[key] or 0) + 1
end

--- Sends one test message; returns the raw result and the name. `target` is only used for WHISPER and never stored.
local function send(channel, text, target)
    ensureRegistered()
    local m = db()
    local ok, r = call(C_ChatInfo and C_ChatInfo.SendAddonMessage, PREFIX, text, channel, target)
    local code = ok and codeName(r) or "error"
    count(m.sent, channel)
    count(m.codes, channel .. " " .. code)
    return code, ok and r or nil
end

local sentAt = {}
local runEcho = {} -- run -> own messages echoed back by the server

local function payload(kind, run, seq, label, size)
    local head = string.format("%s|%s|%d|%s|", kind, run, seq, label)
    local pad = math.max(0, math.min(size or 0, MAX_SIZE) - #head)
    return head .. string.rep("x", pad)
end

-- Receive side ----------------------------------------------------------------------------------------------------------
local pongOn = false

local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "CHAT_MSG_ADDON_LOGGED", "ADDON_RESTRICTION_STATE_CHANGED", "ENCOUNTER_START",
    "ENCOUNTER_END", "PLAYER_ENTERING_WORLD", "GROUP_JOINED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

local function lockdownLine()
    local parts = {}
    local function add(label, fn, ...)
        local ok, v = call(fn, ...)
        parts[#parts + 1] = label .. "=" .. (ok and tostring(v) or "n/a")
    end
    add("InChatMessagingLockdown", C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
    add("OutgoingAddonChatRestricted", C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
    add("InCombatLockdown", InCombatLockdown)
    add("IsEncounterInProgress", C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress)
    add("IsChallengeModeActive", C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive)
    add("IsBattleground", C_PvP and C_PvP.IsBattleground)
    local okI, inInst, instType = call(IsInInstance)
    parts[#parts + 1] = "IsInInstance=" .. (okI and (tostring(inInst) .. "/" .. tostring(instType)) or "n/a")
    local R = C_RestrictedActions
    if R and R.IsAddOnRestrictionActive then
        local types = {}
        pcall(function()
            for name, value in pairs(Enum.AddOnRestrictionType) do types[#types + 1] = { name, value } end
        end)
        if #types == 0 then
            for v = 0, 6 do types[#types + 1] = { "type" .. v, v } end
        end
        table.sort(types, function(a, b) return a[2] < b[2] end)
        for _, t in ipairs(types) do
            local ok, active = call(R.IsAddOnRestrictionActive, t[2])
            parts[#parts + 1] = "restriction." .. t[1] .. "=" .. (ok and tostring(active) or "n/a")
        end
    else
        parts[#parts + 1] = "C_RestrictedActions missing"
    end
    return table.concat(parts, " ")
end

ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" or event == "CHAT_MSG_ADDON_LOGGED" then
        local prefix, text, channel, sender = a1, a2, a3, a4
        if isSecret(prefix) or isSecret(text) or isSecret(channel) or isSecret(sender) then
            db().secret = db().secret + 1
            return
        end
        if prefix ~= PREFIX then
            return
        end
        local m = db()
        local mine = isSelf(sender)
        count(m.recv, tostring(channel) .. (mine and " self" or " other") .. (event == "CHAT_MSG_ADDON_LOGGED" and " logged" or ""))
        local kind, run, seq, label = tostring(text):match("^(%u+)|([^|]*)|(%d+)|([^|]*)|")
        if not kind then
            return
        end
        seq = tonumber(seq)
        if mine then
            local t0 = sentAt[run .. ":" .. seq]
            if t0 then
                runEcho[run] = (runEcho[run] or 0) + 1
                local e = m.echo[channel] or { n = 0, sum = 0, max = 0 }
                m.echo[channel] = e
                local ms = (now() - t0) * 1000
                e.n, e.sum, e.max = e.n + 1, e.sum + ms, math.max(e.max, ms)
            end
        else
            local r = m.runs[run] or { channel = channel, kind = label, n = 0, min = seq, max = seq, bytes = #tostring(text), from = "other" }
            m.runs[run] = r
            r.n, r.min, r.max = r.n + 1, math.min(r.min, seq), math.max(r.max, seq)
            if kind == "PING" and label == "ping" and pongOn then
                send(channel, payload("PONG", run, seq, "pong", 40), channel == "WHISPER" and sender or nil)
            end
            if kind == "PONG" then
                Probe:Log("S5 messaging", string.format("PONG received on %s for run %s", tostring(channel), run))
            end
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        Probe:Log("S5 lockdown", string.format("ADDON_RESTRICTION_STATE_CHANGED type=%s state=%s | %s", tostring(a1), tostring(a2),
            lockdownLine()))
    elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        Probe:Log("S5 lockdown", event .. " (boss id " .. tostring(a1) .. ") | " .. lockdownLine())
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_JOINED" then
        Probe:Log("S5 lockdown", event .. " | " .. lockdownLine())
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        Probe:Log("S5 lockdown", event .. " | " .. lockdownLine())
    end
end)

-- Commands ---------------------------------------------------------------------------------------------------------------
local function channelFrom(arg)
    arg = arg:upper()
    if arg == "GUILD" or arg == "OFFICER" then
        return arg
    end
end

local function newRun()
    return string.format("%d", math.floor(now() * 1000) % 1000000)
end

local bursting

local function stopBurst(why)
    if bursting then
        bursting.stop = true
        Probe.Print("burst stopped: " .. why)
    end
end

--- Final line of a burst, 5 seconds after the last message, when the echoes have arrived.
local function finishBurst(b)
    local m = db()
    local e = m.echo[b.channel]
    local codes = {}
    for k, n in pairs(b.codes) do codes[#codes + 1] = k .. " x" .. n end
    table.sort(codes)
    local line = string.format("burst %s n=%d gap=%.2fs size=%d: sent %d, codes {%s}; own echoes received %d%s", b.channel, b.n, b.gap,
        b.size, b.sent, table.concat(codes, ", "), b.echoes or 0,
        e and string.format(" (echo latency avg %.0f ms, max %.0f ms)", e.sum / math.max(1, e.n), e.max) or "")
    Probe:Log("S5 messaging", line)
    Probe.Print(line)
    Probe:Record("S5", "info", line)
end

local function startBurst(channel, n, gap, size)
    local run = newRun()
    local b = { channel = channel, n = n, gap = gap, size = size, sent = 0, codes = {}, run = run, echoes = 0 }
    bursting = b
    local function step(i)
        if b.stop or i > n then
            C_Timer.After(5, function()
                b.echoes = runEcho[run] or 0
                finishBurst(b)
                if bursting == b then bursting = nil end
            end)
            return
        end
        sentAt[run .. ":" .. i] = now()
        local code = send(channel, payload("PING", run, i, "burst", size))
        b.sent = b.sent + 1
        b.codes[code] = (b.codes[code] or 0) + 1
        if i == 1 or i % 10 == 0 then
            Probe:Log("S5 messaging", string.format("burst %s run %s message %d/%d -> %s", channel, run, i, n, code))
        end
        if gap <= 0 then
            step(i + 1)
        else
            C_Timer.After(gap, function() step(i + 1) end)
        end
    end
    step(1)
end

Probe.commands.ping = function(arg)
    local channel = channelFrom(arg)
    if not channel then
        Probe.Print("usage: /aacp ping guild|officer")
        return
    end
    local run = newRun()
    sentAt[run .. ":1"] = now()
    local code = send(channel, payload("PING", run, 1, "ping", 60))
    local okO, officer = call(C_GuildInfo and C_GuildInfo.IsGuildOfficer)
    local line = string.format("ping on %s: result %s (guild officer: %s, in guild: %s)", channel, code,
        okO and tostring(officer) or "n/a", tostring(select(2, call(IsInGuild))))
    Probe:Log("S5 messaging", line)
    Probe.Print(line .. ". Answers (PONG) and echoes appear in the counters: /aacp msgs")
end

Probe.commands.pong = function(arg)
    pongOn = (arg ~= "off")
    Probe.Print("automatic PONG reply to single pings from other clients: " .. (pongOn and "ON" or "OFF"))
end

Probe.commands.burst = function(arg, rest)
    if arg == "stop" then
        stopBurst("by command")
        return
    end
    local channel = channelFrom(arg)
    local n, gap, size = rest:match("^(%d+)%s+([%d%.]+)%s*(%d*)")
    n, gap, size = tonumber(n), tonumber(gap), tonumber(size) or 200
    if not channel or not n or not gap then
        Probe.Print("usage: /aacp burst guild|officer <n> <gapSeconds> [bytes]   (n <= " .. MAX_BURST .. ", bytes <= " .. MAX_SIZE .. "); /aacp burst stop")
        return
    end
    if bursting and not bursting.stop then
        Probe.Print("a burst is already running: /aacp burst stop")
        return
    end
    n, size = math.min(n, MAX_BURST), math.min(size, MAX_SIZE)
    Probe.Print(string.format("burst: %d messages of %d bytes on %s, gap %.2fs", n, size, channel, gap))
    startBurst(channel, n, gap, size)
end

--- Sends messages of growing sizes to find the accepted maximum.
Probe.commands.msgsize = function(arg)
    local channel = channelFrom(arg)
    if not channel then
        Probe.Print("usage: /aacp msgsize guild|officer")
        return
    end
    local sizes = { 100, 200, 240, 254, 255, 256, 300 }
    local out = {}
    for _, size in ipairs(sizes) do
        ensureRegistered()
        local ok, r = call(C_ChatInfo and C_ChatInfo.SendAddonMessage, PREFIX,
            string.rep("x", size), channel)
        out[#out + 1] = size .. ":" .. (ok and codeName(r) or "error")
    end
    local line = "message size test on " .. channel .. " (payload bytes: result): " .. table.concat(out, ", ")
    Probe:Log("S5 messaging", line)
    Probe.Print(line)
end

Probe.commands.msgs = function()
    local m = db()
    local function dump(t)
        local keys = {}
        for k, v in pairs(t) do keys[#keys + 1] = k .. "=" .. tostring(v) end
        table.sort(keys)
        return #keys > 0 and table.concat(keys, ", ") or "none"
    end
    Probe.Print("sent: " .. dump(m.sent))
    Probe.Print("result codes: " .. dump(m.codes))
    Probe.Print("received: " .. dump(m.recv))
    Probe.Print("secret/skipped messages: " .. tostring(m.secret))
end

Probe.commands.whisper = function(arg)
    if arg == "" then
        Probe.Print("usage: /aacp whisper <character name> (the name is used once and never stored)")
        return
    end
    local run = newRun()
    sentAt[run .. ":1"] = now()
    local code = send("WHISPER", payload("PING", run, 1, "ping", 60), arg)
    local lvl = select(2, call(UnitLevel, "player"))
    local line = string.format("addon WHISPER to <target>: result %s (own level %s)", code, tostring(lvl))
    Probe:Log("S6 whisper", line)
    Probe.Print(line .. ". The other client must have /aacp pong on (or just count it with /aacp msgs)")
end

--- Lockdown snapshot with a test GUILD message: records what the restriction APIs say and whether a send is accepted.
Probe.commands.snapshot = function(arg, rest)
    local label = (arg .. " " .. rest):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then
        Probe.Print("usage: /aacp snapshot <label>   (outside, combat, dungeon, boss, battleground, ...)")
        return
    end
    local run = newRun()
    sentAt[run .. ":1"] = now()
    local code = send("GUILD", payload("PING", run, 1, "snap", 40))
    local line = string.format("[%s] test GUILD send: %s | %s", label, code, lockdownLine())
    Probe:Log("S5 lockdown", line)
    local m = db()
    m.locked[label] = line
    Probe.Print("snapshot stored: " .. line)
end

-- Checks -----------------------------------------------------------------------------------------------------------------
local function dumpTable(t)
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = k .. "=" .. tostring(v) end
    table.sort(keys)
    return table.concat(keys, ", ")
end

Probe.exportHooks[#Probe.exportHooks + 1] = function()
    local m = db()
    local lines = { "-- messaging counters", "sent: " .. dumpTable(m.sent), "result codes: " .. dumpTable(m.codes),
        "received: " .. dumpTable(m.recv), "secret/skipped: " .. tostring(m.secret) }
    for ch, e in pairs(m.echo) do
        lines[#lines + 1] = string.format("own echo %s: n=%d avg %.0f ms max %.0f ms", ch, e.n, e.sum / math.max(1, e.n), e.max)
    end
    local n = 0
    for run, r in pairs(m.runs) do
        n = n + 1
        if n <= 40 then
            lines[#lines + 1] = string.format("received run %s on %s (%s): %d messages, seq %d..%d (missing %d)", run, tostring(r.channel),
                tostring(r.kind), r.n, r.min, r.max, math.max(0, r.max - r.min + 1 - r.n))
        end
    end
    return lines
end

Probe:Register("S5", "Addon messages on GUILD and OFFICER: result codes, size, safe rate, plain member receiving OFFICER, lockdown in instances and bosses",
    function()
        local reg = ensureRegistered()
        local okO, officer = call(C_GuildInfo and C_GuildInfo.IsGuildOfficer)
        local okS, canSpeak = call(C_GuildInfo and C_GuildInfo.CanSpeakInGuildChat)
        local m = db()
        local function dump(t) return dumpTable(t) ~= "" and dumpTable(t) or "none" end
        return "info", string.format("%s; officer=%s canSpeakInGuildChat=%s; sent {%s}; codes {%s}; received {%s}; %s. "
            .. "Steps: /aacp ping guild|officer, /aacp msgsize, /aacp burst, /aacp snapshot <label> (see the README)", reg,
            okO and tostring(officer) or "n/a", okS and tostring(canSpeak) or "n/a", dump(m.sent), dump(m.codes), dump(m.recv),
            lockdownLine())
    end)

Probe:Register("S6", "Addon WHISPER between guildmates, also from a low-level character", function()
    local m = db()
    local sent, recv = 0, 0
    for k, v in pairs(m.codes) do if k:find("^WHISPER") then sent = sent + v end end
    for k, v in pairs(m.recv) do if k:find("^WHISPER") then recv = recv + v end end
    local lvl = select(2, call(UnitLevel, "player"))
    local codes = {}
    for k, v in pairs(m.codes) do if k:find("^WHISPER") then codes[#codes + 1] = k .. " x" .. v end end
    table.sort(codes)
    return "info", string.format("own level %s; WHISPER sent %d {%s}; WHISPER received %d (needs a second client running the probe, "
        .. "ideally with /aacp pong on). Use /aacp whisper <name>.", tostring(lvl), sent, table.concat(codes, ", "), recv)
end)

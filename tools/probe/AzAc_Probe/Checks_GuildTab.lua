-- AzAc Probe, M0.2: S1, an Accord test tab in the guild window (CommunitiesFrame), using only hooks.
-- Lua 5.1. Every game API call goes through pcall. Never record names: only frame keys, types, counts, shapes.
-- The probe NEVER calls CommunitiesFrame:SetDisplayMode and never replaces a Blizzard function: it only observes
-- Blizzard code with hooksecurefunc / HookScript (ADR 0003). It logs ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN.

local Probe = _G.AzAc_Probe
if not Probe then
    return
end

local call = Probe.Call
local LOG = "S1"

local state = { tab = nil, panel = nil, hooked = {}, template = nil, blocked = 0, forbidden = 0, panelShows = 0 }

local function frameOrNil()
    return _G.CommunitiesFrame
end

local function logf(fmt, ...)
    Probe:Log(LOG, string.format(fmt, ...))
end

local function pointText(frame)
    local n = select(2, call(frame.GetNumPoints, frame))
    if type(n) ~= "number" then
        return "points?"
    end
    local parts = {}
    for i = 1, n do
        local ok, point, rel, relPoint, x, y = call(frame.GetPoint, frame, i)
        if ok then
            local relName = "nil"
            if rel then
                local okN, nm = call(rel.GetName, rel)
                relName = (okN and nm) or ((rel == _G.UIParent) and "UIParent") or "anon"
            end
            parts[#parts + 1] = string.format("%s>%s:%s %.0f,%.0f", tostring(point), relName, tostring(relPoint),
                tonumber(x) or 0, tonumber(y) or 0)
        end
    end
    return table.concat(parts, " | ")
end

local function describeFrame(key, f)
    if type(f) ~= "table" then
        return key .. ": " .. type(f)
    end
    local okT, typ = call(f.GetObjectType, f)
    local okS, shown = call(f.IsShown, f)
    local okW, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
    local okP, pts = pcall(pointText, f)
    return string.format("%s: %s shown=%s size=%s points=[%s]", key, okT and typ or "?", okS and tostring(shown) or "?",
        okW and string.format("%.0fx%.0f", w or 0, h or 0) or "?", okP and pts or "?")
end

--- Lists the frame-like children of CommunitiesFrame whose key matches interesting words.
local function structureLines()
    local cf = frameOrNil()
    local lines = {}
    if not cf then
        return { "CommunitiesFrame: missing (open the guild window once, or Blizzard_Communities is not loaded)" }
    end
    lines[#lines + 1] = describeFrame("CommunitiesFrame", cf)
    local keys = {}
    for k, v in pairs(cf) do
        if type(k) == "string" and type(v) == "table" and type(v.GetObjectType) == "function"
            and (k:find("Tab") or k:find("Inset") or k:find("Detail") or k:find("Display") or k:find("Maximize")
                or k:find("Roster") or k:find("Chat") or k:find("Guild")) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        lines[#lines + 1] = describeFrame("CommunitiesFrame." .. k, cf[k])
    end
    local modes = rawget(_G, "COMMUNITIES_FRAME_DISPLAY_MODES")
    if type(modes) == "table" then
        local ks = {}
        for k, v in pairs(modes) do
            ks[#ks + 1] = tostring(k) .. ":" .. type(v)
        end
        table.sort(ks)
        lines[#lines + 1] = "COMMUNITIES_FRAME_DISPLAY_MODES keys: " .. table.concat(ks, ",")
    else
        lines[#lines + 1] = "COMMUNITIES_FRAME_DISPLAY_MODES: " .. type(modes)
    end
    for _, m in ipairs({ "GetDisplayMode", "SetDisplayMode", "GetSelectedClubId", "SelectClub", "Minimize", "Maximize",
        "SetMinimized", "IsMinimized", "UpdateCommunitiesTabs" }) do
        lines[#lines + 1] = "CommunitiesFrame:" .. m .. " = " .. type(cf[m])
    end
    local okD, mode = call(cf.GetDisplayMode, cf)
    if okD then
        lines[#lines + 1] = "current display mode type: " .. type(mode) .. "=" .. tostring(mode)
    end
    local okMin, minimized = pcall(function()
        local f = cf.IsMinimized
        return type(f) == "function" and f(cf) or (cf.MaximizeMinimizeFrame and cf.MaximizeMinimizeFrame.isMinimized)
    end)
    lines[#lines + 1] = "minimized: " .. (okMin and tostring(minimized) or "unknown")
    local gm = cf.GuildMemberDetailFrame
    lines[#lines + 1] = "GuildMemberDetailFrame: " .. (gm and "present" or "missing")
    return lines
end

--- issecurevariable() on a few keys, to see whether anything of the window is tainted (taintedBy = an addon name).
local function taintLines()
    local lines = {}
    local cf = frameOrNil()
    if not cf or type(issecurevariable) ~= "function" then
        return { "taint: CommunitiesFrame or issecurevariable missing" }
    end
    local keys = { "displayMode", "clubId", "selectedClubId", "selectedStreamId", "GuildMemberDetailFrame",
        "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "SetDisplayMode" }
    for _, k in ipairs(keys) do
        local ok, secure, by = call(issecurevariable, cf, k)
        lines[#lines + 1] = string.format("issecurevariable(CommunitiesFrame, %s) = %s%s", k,
            ok and tostring(secure) or "error", (ok and not secure) and (" taintedBy=" .. tostring(by)) or "")
    end
    local ok, secure, by = call(issecurevariable, "CommunitiesFrame")
    lines[#lines + 1] = string.format("issecurevariable(\"CommunitiesFrame\") = %s%s", ok and tostring(secure) or "error",
        (ok and not secure) and (" taintedBy=" .. tostring(by)) or "")
    return lines
end

local function lastBlizzardTab(cf)
    local best, bestBottom
    for _, k in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        local f = cf[k]
        if type(f) == "table" and type(f.GetBottom) == "function" then
            local ok, shown = call(f.IsShown, f)
            local okB, bottom = call(f.GetBottom, f)
            if ok and shown and okB and bottom and (not bestBottom or bottom < bestBottom) then
                best, bestBottom = f, bottom
            end
        end
    end
    return best
end

local function hidePanel(why)
    if state.panel and state.panel:IsShown() then
        state.panel:Hide()
        logf("panel hidden (%s)", why)
    end
end

local function hookOnce(id, fn)
    if not state.hooked[id] then
        state.hooked[id] = true
        local ok, err = pcall(fn)
        if not ok then
            logf("hook %s failed: %s", id, tostring(err))
        end
    end
end

local function selectedIsGuild(cf)
    local okG, guildId = call(C_Club and C_Club.GetGuildClubId)
    local okS, selected = call(cf.GetSelectedClubId, cf)
    if okG and okS and guildId and selected then
        return selected == guildId
    end
    return true -- unknown: show the tab anyway, the log says it
end

local function updateTabVisibility()
    local cf = frameOrNil()
    if not (cf and state.tab) then
        return
    end
    local show = AzAc_ProbeDB and AzAc_ProbeDB.tabEnabled and selectedIsGuild(cf)
    if show then
        state.tab:Show()
    else
        state.tab:Hide()
        hidePanel("tab hidden")
    end
end

local function createTabAndPanel()
    local cf = frameOrNil()
    if not cf then
        return false, "CommunitiesFrame missing: open the guild window first (the probe retries when it loads)"
    end
    if state.tab then
        updateTabVisibility()
        return true, "tab already created"
    end
    local anchorTab = lastBlizzardTab(cf)
    local tab
    local templates = { "CommunitiesFrameTabTemplate", "CommunitiesTabTemplate", "SidebarTabTemplate", "" }
    for _, tpl in ipairs(templates) do
        local ok, f = pcall(CreateFrame, "Button", "AzAc_ProbeTab", cf, tpl ~= "" and tpl or nil)
        if ok and f then
            tab, state.template = f, (tpl ~= "" and tpl or "plain Button")
            break
        end
    end
    if not tab then
        return false, "could not create the tab button"
    end
    logf("tab created with template: %s", state.template)
    if state.template == "plain Button" then
        tab:SetSize(36, 36)
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 4, -4)
        icon:SetPoint("BOTTOMRIGHT", -4, 4)
        icon:SetTexture(134400) -- generic question mark icon
        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.2)
    end
    tab:ClearAllPoints()
    if anchorTab then
        tab:SetPoint("TOP", anchorTab, "BOTTOM", 0, -4)
        logf("tab anchored below the last visible Blizzard tab")
    else
        tab:SetPoint("TOPLEFT", cf, "TOPRIGHT", 0, -200)
        logf("no Blizzard tab found: tab anchored to the frame edge")
    end
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Azeroth Accord (probe test tab)")
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    state.tab = tab

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local panel = CreateFrame("Frame", "AzAc_ProbePanel", cf, template)
    local inset = cf.Inset or cf.InsetFrame
    if type(inset) == "table" and inset.GetObjectType then
        panel:SetAllPoints(inset)
    else
        panel:SetPoint("TOPLEFT", cf, "TOPLEFT", 8, -64)
        panel:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -8, 8)
    end
    panel:SetFrameLevel((cf:GetFrameLevel() or 1) + 20)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetText("Accord test panel\n(promote, invite, edit a note: the probe logs any block)")
    panel:Hide()
    panel:SetScript("OnShow", function() state.panelShows = state.panelShows + 1; logf("panel shown") end)
    state.panel = panel

    tab:SetScript("OnClick", function()
        panel:Show()
        logf("Accord tab clicked, panel shown (combat=%s)", tostring(InCombatLockdown and InCombatLockdown()))
    end)

    -- Hooks only: clicking a Blizzard tab, changing the display mode, closing the window or changing club hides the panel.
    for _, k in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        local f = cf[k]
        if type(f) == "table" and type(f.HookScript) == "function" then
            hookOnce("click" .. k, function()
                f:HookScript("OnClick", function() hidePanel("Blizzard tab " .. k .. " clicked") end)
            end)
        end
    end
    hookOnce("SetDisplayMode", function()
        if type(cf.SetDisplayMode) == "function" then
            hooksecurefunc(cf, "SetDisplayMode", function() hidePanel("SetDisplayMode observed") end)
        end
    end)
    for _, m in ipairs({ "Minimize", "Maximize", "SetMinimized" }) do
        hookOnce(m, function()
            if type(cf[m]) == "function" then
                hooksecurefunc(cf, m, function()
                    logf("%s observed (panel shown=%s)", m, tostring(state.panel:IsShown()))
                end)
            end
        end)
    end
    hookOnce("SelectClub", function()
        if type(cf.SelectClub) == "function" then
            hooksecurefunc(cf, "SelectClub", function() updateTabVisibility() end)
        end
    end)
    hookOnce("OnHide", function()
        cf:HookScript("OnHide", function() hidePanel("window closed") end)
    end)
    updateTabVisibility()
    return true, "tab created"
end

local function enableTab()
    AzAc_ProbeDB = AzAc_ProbeDB or {}
    AzAc_ProbeDB.tabEnabled = true
    local ok, msg = createTabAndPanel()
    Probe.Print("tab: " .. tostring(msg))
end

Probe.commands.tab = function(arg)
    if arg == "off" then
        AzAc_ProbeDB = AzAc_ProbeDB or {}
        AzAc_ProbeDB.tabEnabled = false
        updateTabVisibility()
        Probe.Print("tab hidden and not recreated at login")
    elseif arg == "dump" then
        local lines = structureLines()
        for _, l in ipairs(lines) do
            Probe:Log("S1 structure", l)
        end
        Probe.Print("structure dump stored (" .. #lines .. " lines): /aacp export")
    elseif arg == "taint" then
        local lines = taintLines()
        for _, l in ipairs(lines) do
            Probe:Log("S1 taint", l)
        end
        Probe.Print("taint check stored (" .. #lines .. " lines): /aacp export")
    else
        enableTab()
    end
end

-- Event log: ADDON_ACTION_BLOCKED / FORBIDDEN are recorded from login on, whatever the owner is doing.
local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if event == "ADDON_ACTION_BLOCKED" then
            state.blocked = state.blocked + 1
        else
            state.forbidden = state.forbidden + 1
        end
        -- a1 = addon name, a2 = function name: these are addon and API names, not player data
        Probe:Log("S1 blocked", string.format("%s addon=%s function=%s tabShown=%s panelShown=%s combat=%s", event,
            tostring(a1), tostring(a2), tostring(state.tab and state.tab:IsShown()),
            tostring(state.panel and state.panel:IsShown()), tostring(InCombatLockdown and InCombatLockdown())))
        Probe.Print(event .. " logged: addon=" .. tostring(a1) .. " function=" .. tostring(a2))
    elseif event == "PLAYER_REGEN_DISABLED" then
        if state.tab then logf("combat started (tab shown=%s)", tostring(state.tab:IsShown())) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.tab then logf("combat ended (tab shown=%s)", tostring(state.tab:IsShown())) end
    elseif event == "ADDON_LOADED" and a1 == "Blizzard_Communities" then
        if AzAc_ProbeDB and AzAc_ProbeDB.tabEnabled then
            pcall(C_Timer.After, 0, function() createTabAndPanel() end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if AzAc_ProbeDB and AzAc_ProbeDB.tabEnabled and frameOrNil() then
            local ok, msg = createTabAndPanel()
            logf("login/reload: %s", tostring(msg))
        end
    end
end)

Probe:Register("S1", "Accord tab on CommunitiesFrame below the 4 existing tabs, a panel, back to Blizzard tabs, without taint",
    function()
        local cf = frameOrNil()
        if not cf then
            return "info", "CommunitiesFrame missing: open the guild window once, then run /aacp tab and /aacp run S1"
        end
        local taint = taintLines()
        for _, l in ipairs(taint) do
            Probe:Log("S1 taint", l)
        end
        local tainted = 0
        for _, l in ipairs(taint) do
            if l:find("taintedBy=") then
                tainted = tainted + 1
            end
        end
        local structure = structureLines()
        for _, l in ipairs(structure) do
            Probe:Log("S1 structure", l)
        end
        local details = string.format("tab=%s template=%s panelShows=%d ADDON_ACTION_BLOCKED=%d ADDON_ACTION_FORBIDDEN=%d "
            .. "taintedKeys=%d (see the S1 logs in the export)", state.tab and "created" or "not created",
            tostring(state.template), state.panelShows, state.blocked, state.forbidden, tainted)
        return "info", details
    end)

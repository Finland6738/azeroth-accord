-- AzAc Probe: throwaway spike addon for Azeroth Accord (milestone M0). Never distributed.
-- Answers checks S1-S11 (docs/specs/SPEC-09-quality-release.md, section 1) in the real client.
-- Lua 5.1. Every game API call goes through pcall. Never print or store player, guild or BattleTag names:
-- use placeholders (<player 1>), counts, types, field names and shapes.

local ADDON_NAME = ...

-- The REAL addon-message prefix is "AzAccord": this probe must NEVER register or send it. Only the test prefix below.
local TEST_PREFIX = "AzAcP"
local REAL_PREFIX = "AzAccord"

-- commands[name] = function(arg, rest): slash subcommands added by the Checks_*.lua files.
-- exportHooks: functions returning extra export lines. exportTexts[name]: text for "/aacp export <name>".
local Probe = { checks = {}, order = {}, commands = {}, exportHooks = {}, exportTexts = {}, TEST_PREFIX = TEST_PREFIX }
_G.AzAc_Probe = Probe

local PREFIX = "|cff66ccffAzAc Probe:|r "
local RESULTS = { pass = true, fail = true, info = true, todo = true }

local function out(msg)
    print(PREFIX .. tostring(msg))
end
Probe.Print = out

--- Safe call of a game API: returns ok, ...results (never raises). Use this for every game API call.
function Probe.Call(fn, ...)
    if type(fn) ~= "function" then
        return false, "API missing"
    end
    return pcall(fn, ...)
end

--- Refuses the real prefix. Call it with any prefix before registering or sending.
function Probe:AssertTestPrefix(prefix)
    if prefix == REAL_PREFIX then
        error("the probe must never use the real prefix " .. REAL_PREFIX)
    end
    return prefix
end

--- Describes a value without leaking text: strings become a placeholder, tables list "key:type" pairs.
function Probe.Describe(v, placeholder)
    local t = type(v)
    if t == "string" then
        return placeholder or "string<text>"
    elseif t == "table" then
        local keys = {}
        for k, val in pairs(v) do
            keys[#keys + 1] = tostring(k) .. ":" .. type(val)
        end
        table.sort(keys)
        return "table{" .. table.concat(keys, ",") .. "}"
    elseif t == "nil" then
        return "nil"
    end
    return t .. "=" .. tostring(v)
end

local function db()
    AzAc_ProbeDB = AzAc_ProbeDB or {}
    AzAc_ProbeDB.results = AzAc_ProbeDB.results or {}
    return AzAc_ProbeDB
end
Probe.DB = db

local function buildString()
    local ok, version, build = pcall(GetBuildInfo)
    if ok then
        return tostring(version) .. "." .. tostring(build)
    end
    return "unknown"
end
Probe.BuildString = buildString

--- Registers a check (or replaces its stub). fn(probe) returns result ("pass"|"fail"|"info"|"todo"), details (string).
function Probe:Register(id, description, fn)
    assert(type(id) == "string" and type(fn) == "function", "Register(id, description, fn)")
    if not self.checks[id] then
        self.order[#self.order + 1] = id
    end
    self.checks[id] = { id = id, description = description, fn = fn }
end

--- Stores a result in AzAc_ProbeDB.results[id].
function Probe:Record(id, result, details)
    if not RESULTS[result] then
        result = "info"
    end
    local entry = {
        id = id,
        result = result,
        details = tostring(details or ""),
        build = buildString(),
        time = date("%Y-%m-%d %H:%M:%S"),
    }
    db().results[id] = entry
    return entry
end

--- Appends a line to AzAc_ProbeDB.log[name] (capped at 400 lines), included in the export.
function Probe:Log(name, line)
    local d = db()
    d.log = d.log or {}
    local l = d.log[name] or {}
    d.log[name] = l
    l[#l + 1] = date("%H:%M:%S") .. " " .. tostring(line)
    while #l > 400 do
        table.remove(l, 1)
    end
end

--- Runs one check inside pcall and stores its result.
function Probe:Run(id)
    local check = self.checks[id]
    if not check then
        out("unknown check '" .. tostring(id) .. "' (try /aacp list)")
        return
    end
    local ok, result, details = pcall(check.fn, self)
    if not ok then
        result, details = "fail", "error: " .. tostring(result)
    end
    local entry = self:Record(id, result, details)
    out(string.format("%s [%s] %s", id, entry.result, entry.details))
    return entry
end

function Probe:List()
    for _, id in ipairs(self.order) do
        local check, last = self.checks[id], db().results[id]
        out(string.format("%s - %s - %s", id, check.description,
            last and (last.result .. ": " .. last.details) or "no result"))
    end
end

function Probe:ExportText()
    local lines = { "AzAc Probe results (build " .. buildString() .. ")" }
    for _, id in ipairs(self.order) do
        local r = db().results[id]
        if r then
            lines[#lines + 1] = string.format("%s | %s | %s | build %s | %s", id, r.result, r.details, r.build, r.time)
        else
            lines[#lines + 1] = id .. " | no result"
        end
    end
    for name, l in pairs(db().log or {}) do
        lines[#lines + 1] = "-- log: " .. name
        for _, line in ipairs(l) do
            lines[#lines + 1] = line
        end
    end
    for _, hook in ipairs(self.exportHooks) do
        local ok, extra = pcall(hook, self)
        if ok and type(extra) == "table" then
            for _, l in ipairs(extra) do
                lines[#lines + 1] = l
            end
        end
    end
    return table.concat(lines, "\n")
end

function Probe:Reset()
    AzAc_ProbeDB = { results = {} }
    out("results cleared")
end

local exportFrame
--- Opens the export frame with the results, or with `text` when given (a string).
function Probe:Export(text)
    if not exportFrame then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local f = CreateFrame("Frame", "AzAc_ProbeExportFrame", UIParent, template)
        f:SetSize(560, 340)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 8, right = 8, top = 8, bottom = 8 },
            })
        end
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -14)
        title:SetText("AzAc Probe export (Ctrl+C to copy, drag to move)")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        local scroll = CreateFrame("ScrollFrame", "AzAc_ProbeExportScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -40)
        scroll:SetPoint("BOTTOMRIGHT", -36, 18)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(500)
        pcall(edit.SetMaxLetters, edit, 0) -- 0 = no limit
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        exportFrame = f
    end
    exportFrame.edit:SetText(text or self:ExportText())
    exportFrame:Show()
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

-- Checks S1-S11: stubs in M0.1; M0.2-M0.7 replace them by calling Probe:Register with the same id.
local STUBS = {
    { "S1", "Accord tab on CommunitiesFrame below the 4 existing tabs, a panel, back to Blizzard tabs, without taint" },
    { "S2", "C_Club member info for the guild: profession1/2Name/Rank, discordInfo, bnetAccountId, guid; offline too" },
    { "S3", "Native guild recipe directory (IsGuildTradeSkillsEnabled, QueryGuildMemberRecipes, GUILD_RECIPE_KNOWN_BY_MEMBERS, GetGuildMemberRecipes, GetGuildTradeSkillInfo)" },
    { "S4", "Own recipes from the profession window (GetAllRecipeIDs, GetRecipeInfo, GetBaseProfessionInfo); is the window needed open?" },
    { "S5", "Addon messages on GUILD and OFFICER: result codes, size, safe rate, plain member receiving OFFICER, lockdown in instances and bosses" },
    { "S6", "Addon WHISPER between guildmates, also from a low-level character" },
    { "S7", "Party and raid: UnitGUID, UnitIsInMyGuild, GetRaidRosterInfo, secret values in instances" },
    { "S8", "BNet_GetBattleTagSelf, C_Club.SendBattleTagFriendRequest" },
    { "S9", "Guild bank: tabs visible to a member and an officer, items, money, logs (time format, length), events" },
    { "S10", "Account-wide SavedVariables across characters and realms; GetRealmName, connected realms in member names" },
    { "S11", "Performance: social index and 500+ member roster on generated data" },
}
for _, stub in ipairs(STUBS) do
    Probe:Register(stub[1], stub[2], function()
        return "todo", "not implemented yet"
    end)
end

local USAGE = "/aacp [list] | run <id> | export | reset | note <id> <text>"

SLASH_AZACPROBE1 = "/aacp"
SlashCmdList["AZACPROBE"] = function(msg)
    local cmd, arg, rest = (msg or ""):match("^%s*(%S*)%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "list" then
        Probe:List()
    elseif cmd == "run" and arg ~= "" then
        Probe:Run(arg:upper())
    elseif cmd == "export" then
        local textFn = Probe.exportTexts[arg:lower()]
        if arg ~= "" and not textFn then
            out("unknown export '" .. arg .. "' (plain /aacp export has everything)")
        elseif textFn then
            local ok, text = pcall(textFn)
            Probe:Export(ok and text or ("export error: " .. tostring(text)))
        else
            Probe:Export()
        end
    elseif cmd == "reset" then
        Probe:Reset()
    elseif Probe.commands[cmd] then
        local ok, err = pcall(Probe.commands[cmd], arg, rest)
        if not ok then
            out("error in /aacp " .. cmd .. ": " .. tostring(err))
        end
    else
        out(Probe.Usage and Probe.Usage() or USAGE)
    end
end

-- /aacp note S1 <text>: a free-text observation of the owner, stored in the log and exported (never write names in it).
Probe.commands.note = function(arg, rest)
    if arg == "" then
        out("usage: /aacp note <id> <text> (no player or guild names, please)")
        return
    end
    Probe:Log("notes", arg:upper() .. ": " .. rest)
    out("note stored")
end

--- Command names added by Checks files, listed in the usage line.
function Probe.Usage()
    local names = {}
    for name in pairs(Probe.commands) do
        names[#names + 1] = name
    end
    table.sort(names)
    return USAGE .. (#names > 0 and (" | " .. table.concat(names, " | ")) or "")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name == ADDON_NAME then
        db()
        out("loaded (development only). " .. Probe.Usage())
    end
end)

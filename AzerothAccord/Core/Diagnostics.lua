-- Diagnostics: the structured report behind `/accord debug` (SPEC-04 §4), plus a small ring buffer of the addon's own
-- Lua errors. Adapted from Azeroth Guild Finder (Core/Diagnostics.lua), same owner, GPL-3.0 (ADR 0018).
-- Pure Lua: Diagnostics.Format() turns plain data into text and touches no frame. Diagnostics.Show() hands the text to
-- the copy box when the interface has one (ns.DiagnosticsBox), else prints it in the chat.
-- The report never holds a player name, a guild name, a token or a folder of the player's PC: every section only counts
-- and names states, and the errors are cleaned (Diagnostics.CleanError) before they are kept.
local ADDON_NAME, ns = ...
ns = ns or {}
local Diag = {}
ns.Diagnostics, ns.modules = Diag, ns.modules or {}
ns.modules.Diagnostics = Diag

local type, tostring, pcall, ipairs = type, tostring, pcall, ipairs
local concat = table.concat

Diag.MAX_ERRORS = 10        -- distinct errors kept (the oldest goes first)
Diag.MAX_LENGTH = 300       -- characters kept of one error
Diag.MAX_COUNT = 9999

local errors = {}           -- { { text, count, at }, ... } oldest first
local installed, inside = false, false
Diag.errors = errors

---------------------------------------------------------------------------------------------------------------------
-- Error ring buffer
---------------------------------------------------------------------------------------------------------------------
-- The error text without the player's folders: `Interface\AddOns\AzerothAccord\Net\Sync.lua:12: boom` becomes
-- `AzerothAccord/Net/Sync.lua:12: boom`; any other drive or home path becomes `<path>`; no newlines, a length limit.
function Diag.CleanError(message)
	local text = tostring(message == nil and "" or message)
	text = text:gsub("\r", ""):gsub("\n", " | ")
	text = text:gsub("\\", "/")                                  -- one kind of separator from here on
	text = text:gsub("%a:/[^\n]-/AddOns/", "")                   -- C:/Games/WoW/_classic_/Interface/AddOns/
	text = text:gsub("/[^%s:]-/Interface/AddOns/", "")           -- a Unix home folder before Interface/AddOns/
	text = text:gsub("Interface/AddOns/", "")
	text = text:gsub("%a:/[^%s:\"']*", "<path>")                 -- any other drive path
	text = text:gsub("/[Uu]sers/[^%s:\"']*", "<path>")
	text = text:gsub("/[Hh]ome/[^%s:\"']*", "<path>")
	if #text > Diag.MAX_LENGTH then text = text:sub(1, Diag.MAX_LENGTH - 3) .. "..." end
	return text
end

local function now()
	local c = ns.Compat
	return c and c.Now and c.Now() or 0
end

-- Keeps one error. The same text as the latest one only raises its counter.
function Diag.Record(message)
	local text = Diag.CleanError(message)
	local last = errors[#errors]
	if last and last.text == text then
		if last.count < Diag.MAX_COUNT then last.count = last.count + 1 end
		last.at = now()
		return
	end
	errors[#errors + 1] = { text = text, count = 1, at = now() }
	while #errors > Diag.MAX_ERRORS do table.remove(errors, 1) end
end

function Diag.Errors() return errors end
function Diag.ClearErrors() for i = #errors, 1, -1 do errors[i] = nil end end

-- Wraps the game's error handler once: an error whose text names this addon is kept, then goes on to the previous
-- handler unchanged. Errors of other addons are not recorded.
function Diag.Install()
	if installed or type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then return false end
	installed = true
	local previous = geterrorhandler()
	seterrorhandler(function(message, ...)
		if not inside then
			inside = true
			pcall(function()
				if tostring(message):find(ADDON_NAME, 1, true) then Diag.Record(message) end
			end)
			inside = false
		end
		if previous then return previous(message, ...) end
		return message
	end)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------------------------------------------------
-- data = { header = { "line", ... }, sections = { { title, lines }, ... } }  ->  the report text.
function Diag.Format(data)
	local out = {}
	for _, line in ipairs(data.header or {}) do out[#out + 1] = line end
	for _, section in ipairs(data.sections or {}) do
		out[#out + 1] = ""
		out[#out + 1] = "== " .. tostring(section.title) .. " =="
		for _, line in ipairs(section.lines or {}) do out[#out + 1] = tostring(line) end
	end
	return concat(out, "\n")
end

local function addonVersion()
	local c = ns.Compat
	if not (c and c.Call) then return nil end
	local ok, _, version = pcall(c.Call, "C_AddOns.GetAddOnMetadata", ADDON_NAME, "Version")
	if ok and type(version) == "string" then return version end
	return nil
end

function Diag.HeaderLines()
	local c = ns.Compat
	local build = c and c.BuildInfo and c.BuildInfo() or {}
	local version = addonVersion()
	return {
		"Azeroth Accord diagnostics",
		("addon: %s"):format(tostring(version or "unknown")),
		("client: %s (build %s)"):format(tostring(build.version or "?"), tostring(build.build or "?")),
		("interface: %s"):format(tostring(build.interface or "?")),
		("project id: %s%s"):format(tostring(build.projectID or "?"), build.isForever and " (WoW Forever)" or ""),
		("locale: %s"):format(type(GetLocale) == "function" and tostring(GetLocale()) or "?"),
	}
end

-- Whether the addon can send right now: lockdown, restrictions, read-only (the Transport section has the details).
function Diag.SendingLines()
	local C = ns.Compat
	if not (C and C.Chat) then return { "sending: unknown (Compat not loaded)" } end
	local lockdown, readOnly, restriction = C.Chat.InChatLockdown(), C.Chat.OutgoingAddonRestricted(), C.Chat.RestrictionAny()
	if not lockdown and not readOnly and not restriction then return { "sending: allowed" } end
	return { ("sending: held (lockdown %s, read-only %s, restriction %s)"):format(lockdown and "yes" or "no",
		readOnly and "yes" or "no", tostring(restriction or "none")) }
end

function Diag.ErrorLines()
	if #errors == 0 then return { "no addon errors recorded this session" } end
	local lines = {}
	for i = #errors, 1, -1 do   -- latest first
		local e = errors[i]
		lines[#lines + 1] = ("%s%s"):format(e.count > 1 and ("x" .. e.count .. " ") or "", e.text)
	end
	return lines
end

-- Collects the header and every /accord debug section (a failing section is reported, never raised).
function Diag.Collect()
	local sections = {}
	local addon = ns.addon
	local list = addon and addon.debugSections or {}
	local first = { { title = "Sending", lines = Diag.SendingLines() },
		{ title = "Last errors", lines = Diag.ErrorLines() } }
	for _, s in ipairs(first) do sections[#sections + 1] = s end
	for _, section in ipairs(list) do
		local ok, lines = pcall(section.linesFn)
		if not ok then lines = { "error: " .. Diag.CleanError(lines) } end
		sections[#sections + 1] = { title = section.title, lines = lines or {} }
	end
	return { header = Diag.HeaderLines(), sections = sections }
end

function Diag.Report() return Diag.Format(Diag.Collect()) end

-- /accord debug: the copy box when there is one, else the report line by line in the chat.
function Diag.Show()
	local text = Diag.Report()
	if ns.DiagnosticsBox and ns.DiagnosticsBox.Open then return ns.DiagnosticsBox:Open(text) end
	local addon = ns.addon
	for line in (text .. "\n"):gmatch("(.-)\n") do
		if addon and addon.Print then addon:Print(line) else print(line) end
	end
end

if ns.addon then ns.addon.Diagnostics = Diag end

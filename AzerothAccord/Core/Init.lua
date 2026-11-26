-- Init: the addon object, the Forever check and the slash commands (SPEC-01 §3, SPEC-04 §4). Lua 5.1.
-- Adapted from Azeroth Guild Finder (Core/Init.lua), same owner, GPL-3.0 (ADR 0018).
-- Later modules attach themselves to the private namespace `ns` and, when they need to be reachable from tests or
-- the key binding, to the addon object (AzerothAccord.Compat, .Config, ...).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local ACC = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
ns.addon, ns.L = ACC, L
_G.AzerothAccord = ACC

local FOREVER_MIN_INTERFACE, FOREVER_MAX_INTERFACE = 16001, 19999

-- True on WoW Forever: the project id constant when the client has it, else the Interface number.
function ACC:IsForever()
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CAMELOT ~= nil then
		return WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
	end
	local build = select(4, GetBuildInfo())
	return type(build) == "number" and build >= FOREVER_MIN_INTERFACE and build <= FOREVER_MAX_INTERFACE
end

function ACC:Print(msg)
	self:Printf("|cffd4af37%s|r %s", L["ADDON_TITLE"], msg)
end

-- The views of the panel (SPEC-04 §2); `/accord <view>` opens one. UI/Shell.lua does the opening (M1.8).
ACC.VIEWS = { "roster", "professions", "reputation", "bank", "season", "events", "availability", "raid", "handbook", "settings" }

local function viewCommand(view)
	return function(self) self:OpenView(view) end
end

-- The commands in help order. A command without a handler answers "coming soon".
ACC.commands = {
	{ name = "inbox", feature = "actions", help = L["HELP_INBOX"], handler = viewCommand("actions") },
	{ name = "roster", help = L["HELP_ROSTER"], handler = viewCommand("roster") },
	{ name = "professions", help = L["HELP_PROFESSIONS"], handler = viewCommand("professions") },
	{ name = "reputation", help = L["HELP_REPUTATION"], handler = viewCommand("reputation") },
	{ name = "bank", help = L["HELP_BANK"], handler = viewCommand("bank") },
	{ name = "groups", feature = "groups", help = L["HELP_GROUPS"], handler = viewCommand("groups") },
	{ name = "season", feature = "season", help = L["HELP_SEASON"], handler = viewCommand("season") },
	{ name = "events", feature = "season", help = L["HELP_EVENTS"], handler = viewCommand("events") },
	{ name = "availability", feature = "season", help = L["HELP_AVAILABILITY"], handler = viewCommand("availability") },
	{ name = "raid", feature = "raid", help = L["HELP_RAID"], handler = viewCommand("raid") },
	{ name = "handbook", feature = "raid", help = L["HELP_HANDBOOK"],
		handler = function(self, input)
			if ns.HandbookView then return ns.HandbookView.Command(input) end
		end },
	{ name = "recruit", feature = "recruit", help = L["HELP_RECRUIT"],
		handler = function() if ns.RecruitView then ns.RecruitView.Command() end end },
	{ name = "welcome", feature = "recruit", help = L["HELP_WELCOME"],
		handler = function() if ns.OnboardingView then ns.OnboardingView.Command() end end },
	{ name = "addons", feature = "census", help = L["HELP_ADDONS"], handler = viewCommand("addons") },
	{ name = "settings", help = L["HELP_SETTINGS"], handler = viewCommand("settings") },
	{ name = "away", help = L["HELP_AWAY"], handler = function(self, input) if ns.Absence then ns.Absence.Command(input) end end },
	{ name = "about", help = L["HELP_ABOUT"], handler = function(self, input) if ns.About then ns.About.Command(input) end end },
	{ name = "backup", help = L["HELP_BACKUP"], handler = function(self, input) if ns.Backup then ns.Backup.Command(input) end end },
	{ name = "demo", help = L["HELP_DEMO"], handler = function(self, input) if ns.Demo then ns.Demo.Command(input) end end },
	{ name = "debug", help = L["HELP_DEBUG"], handler = function(self, input) self:OnDebugCommand(input) end },
	{ name = "help", help = L["HELP_HELP"], handler = function(self) self:PrintHelp() end },
}

-- /accord debug sections: modules add a function returning text lines (never player or guild names).
ACC.debugSections = {}
function ACC:AddDebugSection(title, linesFn)
	for _, s in ipairs(self.debugSections) do
		if s.title == title then s.linesFn = linesFn return end
	end
	self.debugSections[#self.debugSections + 1] = { title = title, linesFn = linesFn }
end

-- The report: in a copy box when the UI has one (Core/Diagnostics.lua + UI), else in the chat.
function ACC:OnDebugCommand()
	if ns.Diagnostics and ns.Diagnostics.Show then return ns.Diagnostics.Show() end
	self:PrintDebug()
end

function ACC:PrintDebug()
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	self:Print("Debug - version " .. tostring(version or "?"))
	for _, section in ipairs(self.debugSections) do
		local ok, lines = pcall(section.linesFn)
		if not ok then lines = { "error: " .. tostring(lines):sub(1, 120) } end
		self:Print(section.title .. ":")
		for _, line in ipairs(lines or {}) do self:Print(line) end
	end
end

-- Opens or closes the standalone window: /accord, the key binding and the AddOn Compartment (UI/Shell.lua, M1.8).
function ACC:Toggle()
	if ns.Shell then return ns.Shell:Toggle() end
	self:Print(L["COMING_SOON"])
end

function ACC:OpenView(view)
	if ns.Shell then return ns.Shell:OpenView(view) end
	self:Print(L["COMING_SOON"])
end

-- False for the command of a feature whose switch is off (Core/Features.lua): it is then like no command at all.
local function available(c)
	return c.feature == nil or (ns.Features ~= nil and ns.Features.On(c.feature))
end

function ACC:PrintHelp()
	self:Print(L["HELP_HEADER"])
	self:Print("/accord - " .. L["HELP_TOGGLE"])
	for _, c in ipairs(self.commands) do
		if available(c) then self:Print("/accord " .. c.name .. " - " .. c.help) end
	end
end

function ACC:OnSlashCommand(input)
	local cmd = (self:GetArgs(input or "", 1) or ""):lower()
	if cmd == "" then
		return self:Toggle()
	end
	for _, c in ipairs(self.commands) do
		if c.name == cmd and available(c) then
			if c.handler then
				return c.handler(self, input)
			end
			return self:Print(L["COMING_SOON"])
		end
	end
	self:Print(L["UNKNOWN_COMMAND"]:format(cmd))
	self:PrintHelp()
end

function ACC:OnInitialize()
	if ns.Config then ns.Config:Load() end   -- ADDON_LOADED: SavedVariables are available now
	self:RegisterChatCommand("accord", "OnSlashCommand")
	self:RegisterChatCommand("acc", "OnSlashCommand")
	if not self:IsForever() then
		self:Print(L["WARN_NOT_FOREVER"])   -- OnInitialize runs once per session
	end
end

function ACC:OnEnable()
	if ns.Diagnostics then ns.Diagnostics.Install() end   -- keeps the addon's own Lua errors for /accord debug
	if ns.Compat then ns.Compat:Probe() end               -- PLAYER_LOGIN: the capability table (SPEC-01 §5)
	for _, module in ipairs(ns.onEnable or {}) do        -- modules that start at login register here
		local ok, err = pcall(module)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

-- Modules that need PLAYER_LOGIN call this at load time; the functions run in order from OnEnable.
function ns.OnEnable(fn)
	ns.onEnable = ns.onEnable or {}
	ns.onEnable[#ns.onEnable + 1] = fn
end

-- Key binding and AddOn Compartment entry points (globals named in the TOC and Bindings.xml).
BINDING_HEADER_AZACCORD = L["ADDON_TITLE"]
BINDING_NAME_AZACCORD_TOGGLE = L["BINDING_TOGGLE"]

function AzerothAccord_ToggleBinding()
	ACC:Toggle()
end

function AzerothAccord_OnAddonCompartmentClick()
	ACC:Toggle()
end

function AzerothAccord_OnAddonCompartmentEnter(_, menuButtonFrame)
	if not GameTooltip then return end
	GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
	GameTooltip:SetText(L["ADDON_TITLE"])
	if ns.Shell and ns.Shell.FillTooltip then ns.Shell.FillTooltip(GameTooltip) end
	GameTooltip:Show()
end

function AzerothAccord_OnAddonCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end

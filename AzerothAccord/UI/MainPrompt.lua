-- MainPrompt: the "Choose your main" window (owner, 2026-11-28; SPEC-05 §3, ACC-02). Lua 5.1.
-- It opens over the addon's panel when the panel opens and the account has at least two characters and no main chosen
-- yet. The choice is required: there is no way to put it off, only Confirm. The highest character is preselected. It
-- never opens in combat or in the demo guild, nor when the saved data cannot be written (it opens the next time).
--   Prompt.Needed()          true when the choice is missing
--   Prompt:MaybeShow(host)   opens it over `host` (the panel) when needed; returns the window, or nil
--   Prompt:Confirm()         saves the chosen character; true, or false and a reason
local ADDON_NAME, ns = ...
ns = ns or {}
local Prompt = {}
ns.MainPrompt, ns.modules = Prompt, ns.modules or {}
ns.modules.MainPrompt = Prompt

local L, Widgets = ns.L, ns.Widgets
local ipairs = ipairs

Prompt.WIDTH, Prompt.HEIGHT = 400, 250
Prompt.chosen = nil          -- the GUID chosen in the window

function Prompt.Needed()
	local A, C = ns.Accounts, ns.Config
	if not (A and C) or C:IsReadOnly("account") then return false end
	if ns.Demo and ns.Demo:IsActive() then return false end
	local _, source = A:Main()
	return source == "default" and #A:OwnChars() >= 2
end

local function build(host)
	local d = Widgets.Dialog(host, nil, { width = Prompt.WIDTH, height = Prompt.HEIGHT })
	local card = d.card
	d:SetTitle(L["MAIN_PROMPT_TITLE"])
	d.text = Widgets.Text(card, "Body", "text-2", "LEFT")
	d.text:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -64)
	d.text:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	d.text:SetWordWrap(true)
	d.text:SetText(L["SET_MAIN_TEXT"])
	d.who = Widgets.Select(card, { width = Prompt.WIDTH - 48, rows = 8, onSelect = function(id) Prompt.chosen = id end })
	d.who:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 80)
	d.status = Widgets.Text(card, "Small", "err", "LEFT")
	d.status:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 36)
	d.ok = Widgets.Button(card, { text = L["MAIN_PROMPT_CONFIRM"], style = "filled", onClick = function() Prompt:Confirm() end })
	d:SetActions({ d.ok })
	return d
end

function Prompt:MaybeShow(host)
	if not host then return nil end
	if not Prompt.Needed() then
		if self.dialog then self.dialog:Close() end
		return nil
	end
	if ns.Compat.InCombat() then return nil end
	if not self.dialog then self.dialog = build(host) end
	local d = self.dialog
	d:SetParent(host)
	d:ClearAllPoints()
	d:SetAllPoints(host)
	d:SetFrameStrata("DIALOG")
	local choices, keep, main = {}, false, nil
	for _, c in ipairs(ns.SettingsModel.MainChoices()) do
		choices[#choices + 1] = { id = c.guid, text = L["MAIN_PROMPT_CHOICE"]:format(c.name or "?", c.level or 0) }
		if c.guid == self.chosen then keep = true end
		if c.isMain then main = c.guid end
	end
	if not keep then self.chosen = main end
	d.who:SetChoices(choices)
	d.who:Select(self.chosen, true)
	d.status:SetText("")
	d:Open()
	return d
end

function Prompt:Confirm()
	if not (self.dialog and self.chosen) then return false, "unknown" end
	local ok, why = ns.SettingsModel.SetMain(self.chosen)
	if not ok then
		self.dialog.status:SetText(L["SET_MAIN_FAILED"])
		return false, why
	end
	self.dialog:Close()
	return true
end

if ns.addon then
	ns.addon.MainPrompt = Prompt
	if ns.Bus then
		ns.Bus:On("SETTINGS_CHANGED", function(key)
			if key == "main" and Prompt.dialog then Prompt.dialog:Close() end
		end)
	end
end

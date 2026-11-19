-- Settings view: for now the contacts the player shares with the guild (SPEC-05 CON-01, CON-02). Lua 5.1.
-- The BattleTag is read from the game and shown here; the Discord user name is typed (at most 32 characters, no links)
-- and used when the server does not give it natively. Both are always shared with the guild (owner decision D3): the
-- text says so and there is no switch. Later milestones add the other settings (M6).
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.SettingsView, ns.modules = View, ns.modules or {}
ns.modules.SettingsView = View

local L, W, Skin = ns.L, ns.Widgets, ns.Skin

function View:Refresh()
	local f = self.frame
	if not f then return end
	local C = ns.Contacts
	local tag = C and C:OwnBattleTag()
	f.battleTag:SetText(tag and L["SET_BATTLETAG"]:format(tag) or L["SET_BATTLETAG_UNKNOWN"])
	local typed = C and C:OwnDiscord() or ""
	if not f.discordEdit:HasFocus() then f.discordEdit:SetText(typed) end
	local mine = ns.Roster and ns.Roster:ByGUID(ns.Compat.Player.GUID())
	f.native:SetShown(mine ~= nil and mine.discordSource == "native")
end

function View:Save()
	local f = self.frame
	local ok, why = ns.Contacts:SetDiscord(f.discordEdit:GetText() or "")
	if ok then
		f.status:SetText(why == "cleared" and L["SET_CLEARED"] or L["SET_SAVED"])
		f.status:SetTextColor(Skin.Color("green"))
	else
		f.status:SetText(L["SET_INVALID"])
		f.status:SetTextColor(Skin.Color("red"))
	end
	f.discordEdit:ClearFocus()
	return ok
end

function View:Build(f)
	self.frame = f
	local pad = 16
	f.title = W.Text(f, "title", "gold", "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
	f.title:SetText(L["SET_CONTACTS"])
	f.explain = W.Text(f, "body", nil, "LEFT")
	f.explain:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	f.explain:SetWidth(460)
	f.explain:SetText(L["SET_CONTACTS_TEXT"])
	f.battleTag = W.Text(f, "body", nil, "LEFT")
	f.battleTag:SetPoint("TOPLEFT", f.explain, "BOTTOMLEFT", 0, -22)
	f.discordLabel = W.Text(f, "body", nil, "LEFT")
	f.discordLabel:SetPoint("TOPLEFT", f.battleTag, "BOTTOMLEFT", 0, -18)
	f.discordLabel:SetText(L["SET_DISCORD"])
	local edit = W.Create("EditBox", nil, f, { "InputBoxTemplate", "" })
	edit:SetSize(220, 22)
	edit:SetPoint("TOPLEFT", f.discordLabel, "BOTTOMLEFT", 6, -6)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(ns.Contacts and ns.Contacts.DISCORD_MAX or 32)
	edit:SetScript("OnEnterPressed", function() View:Save() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() View:Refresh() end)
	f.discordEdit = edit
	f.save = W.Button(f, { text = L["SET_SAVE"], width = 90, onClick = function() View:Save() end })
	f.save:SetPoint("LEFT", edit, "RIGHT", 10, 0)
	f.status = W.Text(f, "small", nil, "LEFT")
	f.status:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -6, -8)
	f.native = W.Text(f, "small", "grey", "LEFT")
	f.native:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -8)
	f.native:SetWidth(460)
	f.native:SetText(L["SET_DISCORD_NATIVE"])
	f:SetScript("OnShow", function() View:Refresh() end)
	self:Refresh()
end

if ns.Shell then
	ns.Shell:RegisterView("settings", { label = L["VIEW_SETTINGS"], order = 90, build = function(f) View:Build(f) end })
end

if ns.addon then
	ns.addon.SettingsView = View
	if ns.Bus then
		ns.Bus:On("FEATURE_CHANGED", function(id) if id == "battleTag" then View:Refresh() end end)
	end
end

-- OnboardingView: the Welcome card and `/accord welcome` (M12.4; SPEC-16 §5.2, §5.3). Lua 5.1.
-- The card sits on top of the Inbox page of the Action Center while the list is open (UI/Actions.lua asks for it);
-- `/accord welcome` shows the same card in a small window, for anyone, also after Dismiss. A click on an item opens the
-- view that does it. Data/Onboarding.lua decides who is new and what is done; nothing here sends anything.
--   View.Model()       { guild, items = { { id, text, done, target? } }, done, total, count, complete, active }
--   View:Go(item)      opens the view of an item
--   View:ShowList()    the card in the Action Center (the row of the provider), else the window
-- Switch: Core/Features.lua "recruit".
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.OnboardingView, ns.modules = View, ns.modules or {}
ns.modules.OnboardingView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local ipairs, tostring = ipairs, tostring

View.NAME = "AzerothAccordWelcomeBox"
View.WIDTH, View.HEIGHT = 520, 320
View.HEAD = 40           -- the card: its title line, each item under it, the note, the room under the last line
View.LINE = 26
View.NOTE = 24
View.GAP = 12
View.MARK_SIZE = 8

local TEXT = { read = "WELCOME_ITEM_READ", main = "WELCOME_ITEM_MAIN", discord = "WELCOME_ITEM_DISCORD",
	season = "WELCOME_ITEM_SEASON" }

local function book() return ns.Onboarding end

function View.Model()
	local O = book()
	local items = O:Items()
	for _, item in ipairs(items) do item.text = L[TEXT[item.id]] end
	local done, total = O:Progress(items)
	local guild = ns.Compat.Guild.GuildName()
	guild = guild and (tostring(guild):gsub("|", "||")) or "?"
	return { guild = guild, items = items, done = done, total = total, count = L["WELCOME_COUNT"]:format(done, total),
		complete = total > 0 and done == total, active = O:Active() }
end

function View:Go(item)
	if type(item) ~= "table" then return false end
	self:Hide()
	if item.id == "read" then
		return ns.HandbookView ~= nil and ns.HandbookView:Open(item.target) ~= false
	elseif item.id == "main" or item.id == "discord" then
		return ns.SettingsView ~= nil and ns.SettingsView:ShowCard(item.id == "main" and "main" or "contacts")
	elseif item.id == "season" then
		if item.target == "fdcp" then return ns.FDCP ~= nil and ns.FDCP.Open() end
		return ns.Shell ~= nil and ns.Shell:OpenView("season")
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------------------------------------------------
local function buildCard(parent)
	local card = Widgets.Card(parent)
	card.title = Widgets.Text(card, "Eyebrow", "text-3", "LEFT")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
	card.title:SetText(L["WELCOME_TITLE"])
	card.dismiss = Widgets.Button(card, { text = L["WELCOME_DISMISS"], style = "ghost", height = 22, width = 80, onClick = function()
		book():Dismiss()
		View:Changed()
	end })
	card.dismiss:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
	card.count = Widgets.Text(card, "Small", "text-2", "RIGHT")
	card.count:SetPoint("TOPRIGHT", card, "TOPRIGHT", -100, -13)
	card.note = Widgets.Text(card, "Small", "text-3", "LEFT")
	card.lines = {}
	return card
end

local function cardLine(card, i)
	local row = card.lines[i]
	if row then return row end
	row = CreateFrame("Button", nil, card)
	row:SetHeight(View.LINE)
	local y = -View.HEAD - (i - 1) * View.LINE
	row:SetPoint("TOPLEFT", card, "TOPLEFT", 8, y)
	row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, y)
	Widgets.RowHover(row)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetSize(View.MARK_SIZE, View.MARK_SIZE)
	row.mark:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.mark:SetTexture(ns.Assets.textures.circle.path)
	row.label = Widgets.Text(row, "Body", "text-1", "LEFT")
	row.label:SetPoint("LEFT", row, "LEFT", 24, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -90, 0)
	row.label:SetWordWrap(false)
	row.state = Widgets.Text(row, "Small", "text-3", "RIGHT")
	row.state:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row:SetScript("OnClick", function(r) View:Go(r.item) end)
	card.lines[i] = row
	return row
end

-- Writes the model into the card and returns its height.
local function fill(card, model, dismissable)
	for i, item in ipairs(model.items) do
		local row = cardLine(card, i)
		row.item = item
		row.label:SetText(item.text)
		row.state:SetText(item.done and L["WELCOME_DONE"] or "")
		Theme.Tint(row.mark, item.done and "ok" or "text-3")
		row:Show()
	end
	for i = #model.items + 1, #card.lines do card.lines[i]:Hide() end
	card.count:SetText(model.total > 0 and model.count or "")
	card.dismiss:SetShown(dismissable)
	local note = model.complete and L["WELCOME_ALL_DONE"]:format(model.guild)
		or model.total == 0 and L["WELCOME_NOTHING"] or L["WELCOME_LOCAL"]
	local y = View.HEAD + #model.items * View.LINE + 4
	card.note:ClearAllPoints()
	card.note:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -y)
	card.note:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	card.note:SetText(note)
	local height = y + View.NOTE + 8
	card:SetHeight(height)
	return height
end

-- The card on top of the Inbox page `holder`: returns the room it takes (0 while the list is not open).
function View:InboxCard(holder)
	if not (book() and book():Active()) then
		if holder.welcome then holder.welcome:Hide() end
		return 0
	end
	if not holder.welcome then
		holder.welcome = buildCard(holder)
		holder.welcome:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		holder.welcome:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
	end
	local height = fill(holder.welcome, View.Model(), true)
	holder.welcome:Show()
	return height + View.GAP
end

---------------------------------------------------------------------------------------------------------------------
-- The window (`/accord welcome`)
---------------------------------------------------------------------------------------------------------------------
local function build()
	local f = Widgets.Dialog(UIParent, View.NAME, { width = View.WIDTH, height = View.HEIGHT })
	f.body = buildCard(f.card)
	f.body:SetPoint("TOPLEFT", f.card, "TOPLEFT", 20, -20)
	f.body:SetPoint("TOPRIGHT", f.card, "TOPRIGHT", -20, -20)
	f.close = Widgets.Button(f.card, { text = L["BACKUP_CLOSE"], style = "primary", width = 140,
		onClick = function() View:Hide() end })
	f.close:SetPoint("BOTTOMRIGHT", f.card, "BOTTOMRIGHT", -20, 20)
	return f
end

function View:Draw()
	local f = self.frame
	if not (f and f:IsShown()) then return end
	fill(f.body, View.Model(), book():Active())
end

-- Opens the window, for anyone in a guild. Returns true, or false.
function View:Open()
	if not (book() and book().Enabled() and ns.Role and ns.Role:InGuild()) then return false end
	book():Refresh()
	if not self.frame then self.frame = build() end
	self.frame:Open()
	self:Draw()
	return true
end

function View:ShowList()
	if ns.Actions and ns.Actions.Enabled() and book():Active() and ns.Shell and ns.Shell:OpenView("actions") then
		if ns.ActionsView then ns.ActionsView:ShowPage("inbox") end
		return true
	end
	return self:Open()
end

-- /accord welcome
function View.Command()
	local ok = View:Open()
	if not ok and ns.addon then ns.addon:Print(L["NOT_IN_GUILD"]) end
	return ok
end

function View:Hide() if self.frame then self.frame:Hide() end end
function View:IsShown() return self.frame ~= nil and self.frame:IsShown() end

function View:Changed()
	self:Draw()
	if ns.ActionsView then ns.ActionsView:Changed() end
end

if ns.addon then
	ns.addon.OnboardingView = View
	if ns.Bus then
		ns.Bus:On("ONBOARDING_CHANGED", function() View:Changed() end)
		for _, event in ipairs({ "GUILD_CHANGED", "DEMO_CHANGED" }) do
			ns.Bus:On(event, function() View:Hide() end)
		end
	end
end

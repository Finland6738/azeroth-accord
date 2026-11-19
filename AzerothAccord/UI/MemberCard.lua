-- MemberCard: the card of the selected member (SPEC-05 §2). Lua 5.1.
-- A click on a row of the Roster table (Bus: ROSTER_SELECT) opens the card: to the right of the table in a wide panel,
-- over the table in a narrow one (the guild tab), with a Back button there.
--
-- Card.Describe(entry) is a plain function of the roster entry, the account groups and the notes permission, so the
-- content is covered by offline tests; the frame only draws what it returns:
--   { guid, title, subtitle, classFile, notInGuild, sections = { { id, title, lines = { { text, muted, guid } } } } }
-- Sections: Details (zone, last online, rank, public note, the officers' note only when the game lets the player read it,
-- the addon), Professions (each with where it comes from: the game, the member's own addon, the player's own),
-- Characters of the same account (all of them, also outside the guild; a line with a `guid` opens that character's card),
-- and what later steps add with Card.AddSection (contacts, likes, social index).
local ADDON_NAME, ns = ...
ns = ns or {}
local Card = {}
ns.MemberCard, ns.modules = Card, ns.modules or {}
ns.modules.MemberCard = Card

local L, W, Skin, Model = ns.L, ns.Widgets, ns.Skin, ns.RosterModel
local type, ipairs, pairs, max = type, ipairs, pairs, math.max

Card.WIDTH = 270
Card.WIDE = 760            -- a panel at least this wide has room for the card beside the table
Card.PAD = 10
Card.LINE_GAP = 3

Card.extra = {}            -- later steps: { { id, order, fn(entry) -> section | nil } }

-- A module adds a section to every card: fn(entry) returns { id, title, lines } or nil.
function Card.AddSection(id, order, fn)
	for _, s in ipairs(Card.extra) do
		if s.id == id then s.order, s.fn = order, fn return end
	end
	Card.extra[#Card.extra + 1] = { id = id, order = order, fn = fn }
end

-- A line of a section: text, muted (grey), guid (a click opens that character's card) or onClick (any other action;
-- `action` colours it like a button).
local function line(text, muted, guid, onClick, action)
	return { text = text, muted = muted or nil, guid = guid, onClick = onClick, action = action or nil }
end

local function now() return ns.Compat and ns.Compat.ServerTime() or time() end

---------------------------------------------------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------------------------------------------------
-- "native" (the game), "shared" (the member's own addon, with its age), "own" (the player's own professions).
local function sourceText(p)
	if p.source == "shared" then
		if p.time then return L["CARD_SRC_SHARED_AGE"]:format(ns.Shell.Ago(now() - p.time)) end
		return L["CARD_SRC_SHARED"]
	elseif p.source == "own" then
		return L["CARD_SRC_OWN"]
	end
	return L["CARD_SRC_NATIVE"]
end

local function detailsSection(e)
	local lines = {}
	if e.notInGuild then
		lines[#lines + 1] = line(L["CARD_NOT_IN_GUILD"], true)
	else
		if e.zone and e.zone ~= "" then lines[#lines + 1] = line(L["CARD_ZONE"]:format(e.zone)) end
		if e.online then lines[#lines + 1] = line(L["CARD_ONLINE"])
		else lines[#lines + 1] = line(L["CARD_LAST_ONLINE"]:format(Model.LastOnlineText(e.lastOnlineHours)), true) end
		if e.rankName then lines[#lines + 1] = line(L["CARD_RANK"]:format(e.rankName)) end
		if e.note and e.note ~= "" then lines[#lines + 1] = line(L["CARD_NOTE"]:format(e.note)) end
		-- the officers' note only for those the game lets read it (the client may hand it over anyway)
		local canView = ns.Compat and ns.Compat.Guild.CanViewOfficerNote()
		if canView and e.officerNote and e.officerNote ~= "" then lines[#lines + 1] = line(L["CARD_OFFICER_NOTE"]:format(e.officerNote)) end
	end
	if e.hasAddon then
		lines[#lines + 1] = line(e.addonVersion and L["CARD_ADDON_VERSION"]:format(e.addonVersion) or L["CARD_ADDON"], true)
	elseif not e.notInGuild then
		lines[#lines + 1] = line(L["CARD_NO_ADDON"], true)
	end
	return { id = "details", title = L["CARD_DETAILS"], lines = lines }
end

local function professionsSection(e)
	local lines = {}
	for _, p in ipairs(e.professions or {}) do
		-- a click opens the member's recipes for this profession (PRO-02)
		local open = e.guid and function()
			if ns.RecipeView then ns.RecipeView:Open(e.guid, ns.RecipeView.SkillLineOf(e, p)) end
		end or nil
		lines[#lines + 1] = line(("%s (%s)"):format(Model.ProfessionText(p), sourceText(p)), p.source == "shared", nil, open)
	end
	if #lines == 0 then lines[1] = line(e.hasAddon and L["CARD_NO_PROF_ADDON"] or L["CARD_NO_PROF"], true) end
	return { id = "professions", title = L["CARD_PROFESSIONS"], lines = lines }
end

local function accountSection(e)
	local g = ns.Accounts and e.guid and ns.Accounts:GroupOf(e.guid) or nil
	local lines = {}
	if g then
		for _, m in ipairs(g.members) do
			if m.guid ~= e.guid then
				local re = ns.Roster and ns.Roster:ByGUID(m.guid)
				local classFile = m.classFile or (re and re.classFile) or (m.classID and ns.Roster.ClassFile(m.classID)) or nil
				local what = {}
				if m.level then what[#what + 1] = tostring(m.level) end
				local className = classFile and ns.Roster.ClassName(classFile)
				if className then what[#what + 1] = className end
				local text = (m.name or "?") .. (#what > 0 and (" (" .. table.concat(what, " ") .. ")") or "")
				local tags = {}
				if m.isMain then tags[#tags + 1] = L["CARD_MAIN"] end
				if not m.inGuild then tags[#tags + 1] = L["NOT_IN_GUILD_SHORT"] end
				if m.hint then tags[#tags + 1] = L["CARD_HINT"] end
				if #tags > 0 then text = text .. " - " .. table.concat(tags, ", ") end
				lines[#lines + 1] = line(text, not m.inGuild, m.guid)
			end
		end
	end
	if #lines == 0 then
		lines[1] = line(L["CARD_NO_ALTS"], true)
	elseif g.main == e.guid then
		table.insert(lines, 1, line(L["CARD_THIS_IS_MAIN"], true))
	end
	-- one of the player's own characters: it can be made the main of the account (Accounts:SetMain, shared at once)
	local A = ns.Accounts
	if A and e.guid and A:Main() ~= e.guid then
		for _, c in ipairs(A:OwnChars()) do
			if c.guid == e.guid then
				lines[#lines + 1] = line(L["CARD_MAKE_MAIN"], false, nil, function()
					if A:SetMain(e.guid) then Card:Refresh() end
				end, true)
				break
			end
		end
	end
	return { id = "account", title = L["CARD_ACCOUNT"], lines = lines }
end

-- Contacts (SPEC-05 §4): the BattleTag and Discord name a click copies, and the friend request button.
local function contactsSection(e)
	local C = ns.Contacts
	if not C or e.notInGuild then return nil end
	local lines = {}
	local c = C:Of(e.guid)
	local function copy(text, title) return function() if ns.CopyBox then ns.CopyBox:Open(text, title) end end end
	if c and c.battleTag then
		lines[#lines + 1] = line(L["CARD_BATTLETAG"]:format(C.Escape(c.battleTag)), false, nil, copy(c.battleTag, L["COPY_TITLE_BATTLETAG"]))
	end
	if c and c.discord then
		local fmt = c.discordSource == "native" and L["CARD_DISCORD_NATIVE"] or L["CARD_DISCORD"]
		lines[#lines + 1] = line(fmt:format(C.Escape(c.discord)), false, nil, copy(c.discord, L["COPY_TITLE_DISCORD"]))
	end
	if #lines == 0 then lines[1] = line(e.hasAddon and L["CARD_NO_CONTACTS"] or L["CARD_NO_CONTACTS_ADDON"], true) end
	if C:CanSendFriendRequest(e) then
		lines[#lines + 1] = line(L["CARD_ADD_FRIEND"], false, nil, function() C:SendFriendRequest(e) end, true)
	end
	return { id = "contacts", title = L["CARD_CONTACTS"], lines = lines }
end

function Card.Describe(e)
	if type(e) ~= "table" then return nil end
	local classColor = e.classFile
	local className = ns.Roster.ClassName(e.classFile)
	local parts = {}
	if e.level then parts[#parts + 1] = L["CARD_LEVEL"]:format(e.level) end
	if className then parts[#parts + 1] = className end
	local d = {
		guid = e.guid, title = e.short or e.name or "?", subtitle = table.concat(parts, " "), classFile = classColor,
		notInGuild = e.notInGuild == true, sections = {},
	}
	d.sections[1] = detailsSection(e)
	d.sections[2] = professionsSection(e)
	d.sections[3] = accountSection(e)
	local contacts = contactsSection(e)
	if contacts then d.sections[4] = contacts end
	local extras = {}
	for _, x in ipairs(Card.extra) do extras[#extras + 1] = x end
	table.sort(extras, function(a, b) return a.order < b.order end)
	for _, x in ipairs(extras) do
		local ok, section = pcall(x.fn, e)
		if ok and type(section) == "table" and type(section.lines) == "table" then d.sections[#d.sections + 1] = section end
	end
	return d
end

-- The entry to describe for a GUID: the roster's, else a character the account lists outside the guild.
function Card.EntryFor(guid)
	if type(guid) ~= "string" then return nil end
	local e = ns.Roster and ns.Roster:ByGUID(guid)
	if e then return e end
	local g = ns.Accounts and ns.Accounts:GroupOf(guid)
	local m = g and g.byGUID[guid]
	if m then return Model.PseudoEntry(m) end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------------------------------------------------
local function classColor(classFile)
	local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

function Card:Build(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:Hide()
	f:EnableMouse(true)
	W.Background(f, "panel", 0.97)
	f.title = W.Text(f, "title", nil, "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD, -Card.PAD)
	f.title:SetPoint("RIGHT", f, "RIGHT", -34, 0)
	f.subtitle = W.Text(f, "small", "grey", "LEFT")
	f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
	f.close = W.CloseButton(f, function() Card:Close() end)
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.back = W.Button(f, { text = L["CARD_BACK"], width = 70, onClick = function() Card:Close() end })
	f.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -6)
	f.items = {}
	self.frame = f
	f:SetScript("OnShow", function() Card:Layout() end)
	return f
end

-- Items are pooled: headings and text lines are font strings, a line that opens another character is a button.
local function item(f, i)
	local it = f.items[i]
	if it then return it end
	it = CreateFrame("Button", nil, f)
	it.text = W.Text(it, "small", nil, "LEFT")
	it.text:SetPoint("TOPLEFT", it, "TOPLEFT", 0, 0)
	it.highlight = it:CreateTexture(nil, "HIGHLIGHT")
	it.highlight:SetAllPoints(it)
	it.highlight:SetColorTexture(1, 1, 1, 0.08)
	it:SetScript("OnClick", function(self)
		if self.guid then Card:ShowGUID(self.guid)
		elseif self.onClick then self.onClick(self) end
	end)
	f.items[i] = it
	return it
end

function Card:Layout()
	local f, d = self.frame, self.description
	if not f or not d then return end
	local width = (f:GetWidth() or 0)
	if width < 100 then width = Card.WIDTH end
	local inner = width - 2 * Card.PAD
	f.title:SetText(d.title)
	f.title:SetTextColor(classColor(d.classFile))
	f.subtitle:SetText(d.subtitle or "")
	f.back:SetShown(self.narrow == true)
	f.close:SetShown(self.narrow ~= true)
	local y, n = 48, 0
	for _, section in ipairs(d.sections) do
		n = n + 1
		local head = item(f, n)
		head.guid, head.onClick = nil, nil
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD, -y)
		head:SetSize(inner, 16)
		head.text:SetWidth(inner)
		head.text:SetText(section.title)
		head.text:SetTextColor(Skin.Color("gold"))
		head:EnableMouse(false)
		head:Show()
		y = y + 18
		for _, ln in ipairs(section.lines) do
			n = n + 1
			local it = item(f, n)
			it.guid, it.onClick = ln.guid, ln.onClick
			it:ClearAllPoints()
			it:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD + 4, -y)
			it.text:SetWidth(inner - 4)
			it.text:SetText(ln.text)
			it.text:SetTextColor(Skin.Color(ln.action and "gold" or (ln.guid and "white" or (ln.muted and "grey" or "white"))))
			local h = max(12, it.text:GetStringHeight() or 12)
			it:SetSize(inner - 4, h)
			it:EnableMouse(ln.guid ~= nil or ln.onClick ~= nil)
			it:Show()
			y = y + h + Card.LINE_GAP
		end
		y = y + 6
	end
	for i = n + 1, #f.items do f.items[i]:Hide() end
	self.contentHeight = y
end

-- Where the card goes: beside the table when the panel is wide, over it when narrow.
function Card:Place()
	local f, v = self.frame, ns.RosterView and ns.RosterView.frame
	if not f or not v then return end
	local width = v:GetWidth() or 0
	self.narrow = width > 0 and width < Card.WIDE
	f:ClearAllPoints()
	if self.narrow then
		f:SetPoint("TOPLEFT", v.toolbar, "BOTTOMLEFT", 0, 0)
		f:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)
	else
		f:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, 0)
		f:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)
		f:SetWidth(Card.WIDTH)
	end
	f:SetFrameLevel((v:GetFrameLevel() or 1) + 20)
end

function Card:Inset()
	if self.frame and self.frame:IsShown() and not self.narrow then return Card.WIDTH + 4 end
	return 0
end

function Card:Show(entry)
	local v = ns.RosterView
	if not (v and v.frame) or not entry then return false end
	if not self.frame then self:Build(v.frame) end
	self.entry = entry
	self.description = Card.Describe(entry)
	self:Place()
	self.frame:Show()
	self:Layout()
	v:Reflow()
	return true
end

function Card:ShowGUID(guid)
	local e = Card.EntryFor(guid)
	if not e then return false end
	if ns.RosterView then ns.RosterView.selected = guid end
	return self:Show(e)
end

function Card:Close()
	if not self.frame then return end
	self.frame:Hide()
	self.entry, self.description = nil, nil
	if ns.RosterView then
		ns.RosterView.selected = nil
		ns.RosterView:Reflow()
		ns.RosterView:Redraw()
	end
end

function Card:IsShown() return self.frame ~= nil and self.frame:IsShown() end

-- The data behind the open card changed: describe it again.
function Card:Refresh()
	if not self:IsShown() or not self.entry then return end
	local e = Card.EntryFor(self.entry.guid)
	if not e then self:Close() return end
	self.entry = e
	self.description = Card.Describe(e)
	self:Layout()
end

if ns.addon then
	ns.addon.MemberCard = Card
	if ns.Bus then
		ns.Bus:On("ROSTER_SELECT", function(_, entry) Card:Show(entry) end)
		ns.Bus:On("ROSTER_UPDATED", function() Card:Refresh() end)
		ns.Bus:On("ACCOUNTS_UPDATED", function() Card:Refresh() end)
		ns.Bus:On("GUILD_CHANGED", function() Card:Close() end)
	end
end

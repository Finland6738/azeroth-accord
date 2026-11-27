-- MemberCard: the card of the selected member (SPEC-05 §2). Lua 5.1.
-- A click on a row of the Roster table (Bus: ROSTER_SELECT) opens the card. In the Accord window it is a detail window of
-- its own beside the window (owner, 2026-11-27: the table keeps its whole width), on the right, or on the left when the
-- screen has no room; in the guild window's panel it goes to the right of the table in a wide panel, over the table in a
-- narrow one, with a Back button there.
--
-- Card.Describe(entry) is a plain function of the roster entry, the account groups and the notes permission, so the
-- content is covered by offline tests; the frame only draws what it returns:
--   { guid, title, subtitle, classFile, notInGuild, badges = { { text, tone } },
--     sections = { { id, title, count?, lines = { { text, muted, guid } } } } }
-- Drawn with the widget kit (M6.13): a Widgets.Card with the class mark, the name in the class colour, Widgets.Badges (online, main,
-- alt, addon) and one inner Widgets.Card per section; a long card scrolls with the mouse wheel.
-- Sections: Details (zone, last online, rank, public note, the officers' note only when the game lets the player read it,
-- the addon), Professions (each with where it comes from: the game, the member's own addon, the player's own),
-- Characters of the same account (all of them, also outside the guild; a line with a `guid` opens that character's card),
-- and what later steps add with Card.AddSection (contacts, likes, social index).
local ADDON_NAME, ns = ...
ns = ns or {}
local Card = {}
ns.MemberCard, ns.modules = Card, ns.modules or {}
ns.modules.MemberCard = Card

local L, Widgets, Theme, Assets, Model = ns.L, ns.Widgets, ns.Theme, ns.Assets, ns.RosterModel
local type, ipairs, pairs, max, min = type, ipairs, pairs, math.max, math.min

Card.WIDTH = 290
Card.DETACHED_WIDTH = 340  -- the detail window beside the Accord window
Card.DETACH = true         -- in the Accord window the card is a window of its own (the tests switch it off for the panel)
Card.GAP = 8
Card.WIDE = 760            -- a panel at least this wide has room for the card beside the table
Card.PAD = 16
Card.INNER = 12            -- padding inside a section card
Card.LINE_GAP = 4
Card.SECTION_GAP = 10
Card.WHEEL = 36            -- pixels per wheel notch

Card.extra = {}            -- later steps: { { id, order, fn(entry) -> section | nil } }

-- A module adds a section to every card: fn(entry) returns { id, title, lines } or nil.
function Card.AddSection(id, order, fn)
	for _, s in ipairs(Card.extra) do
		if s.id == id then s.order, s.fn = order, fn return end
	end
	Card.extra[#Card.extra + 1] = { id = id, order = order, fn = fn }
end

-- A line of a section: text, muted (grey), guid (a click opens that character's card) or onClick (any other action;
-- `action` colours it like a button); a line may also carry `tip` (tooltip lines shown on hover) and `prov` (a provenance
-- info, UI/Provenance.lua: the line gets the label of its source at the right, M7.2).
local function line(text, muted, guid, onClick, action, prov)
	return { text = text, muted = muted or nil, guid = guid, onClick = onClick, action = action or nil, prov = prov }
end

local function now() return ns.Compat and ns.Compat.ServerTime() or time() end

---------------------------------------------------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------------------------------------------------
local function detailsSection(e)
	local lines = {}
	if e.notInGuild then
		lines[#lines + 1] = line(L["CARD_NOT_IN_GUILD"], true)
		-- the guild the character's own account says it is in, and when it last logged in (SPEC-11 §2.4)
		local P = ns.Provenance
		if e.altGuild and e.altGuild.guild ~= nil then
			lines[#lines + 1] = line(P.AltGuildText(e.altGuild), true, nil, nil, nil, P.AltGuildInfo(e.altGuild))
		end
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
		lines[#lines + 1] = line(e.addonVersion and L["CARD_ADDON_VERSION"]:format(e.addonVersion) or L["CARD_ADDON"], true, nil, nil, nil,
			e.addonVersion and { source = "shared", observedAt = e.addonTime, author = e.addonAuthor, set = "addonVersion" } or nil)
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
		lines[#lines + 1] = line(Model.ProfessionText(p), p.source == "shared", nil, open, nil, ns.Provenance.ProfessionInfo(p))
	end
	local count = #lines
	if #lines == 0 then lines[1] = line(e.hasAddon and L["CARD_NO_PROF_ADDON"] or L["CARD_NO_PROF"], true) end
	return { id = "professions", title = L["CARD_PROFESSIONS"], lines = lines, count = count > 0 and count or nil }
end

local function accountSection(e)
	local g = ns.Accounts and e.guid and ns.Accounts:GroupOf(e.guid) or nil
	local lines = {}
	if g then
		for _, m in ipairs(g.members) do
			if m.guid ~= e.guid then
				local re = ns.Roster and ns.Roster:ByGUID(m.guid)
				local classFile = m.classFile or (re and re.classFile) or (m.classID and ns.Roster.ClassFile(m.classID)) or nil
				-- the name in the class colour with only the level; main, guild and hint on a smaller line under it
				-- (owner, 2026-11-27: the class name was redundant with the colour, the guild status crowded the line)
				local text = (m.name or "?") .. (m.level and (" (" .. tostring(m.level) .. ")") or "")
				local tags = {}
				if m.isMain then tags[#tags + 1] = L["CARD_MAIN"] end
				local ag = not m.inGuild and not m.hint and m.altGuild or nil
				if not m.inGuild then tags[#tags + 1] = ns.Provenance.AltGuildText(ag) end
				if m.hint then tags[#tags + 1] = L["CARD_HINT"] end
				local ln = line(text, not m.inGuild, m.guid, nil, nil,
					m.hint and { source = "note", member = m.name } or ns.Provenance.AltGuildInfo(ag)
					or { source = "shared", observedAt = g.time, author = g.author })
				ln.classFile = classFile
				ln.sub = #tags > 0 and table.concat(tags, " · ") or nil
				lines[#lines + 1] = ln
			end
		end
	end
	local others = #lines
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
	return { id = "account", title = L["CARD_ACCOUNT"], lines = lines, count = others > 0 and others or nil }
end

-- Contacts (SPEC-05 §4): the BattleTag and Discord name a click copies, and the friend request button.
local function contactsSection(e)
	local C = ns.Contacts
	if not C or e.notInGuild then return nil end
	local lines = {}
	local c = C:Of(e.guid)
	local function copy(text, title) return function() if ns.CopyBox then ns.CopyBox:Open(text, title) end end end
	if c and c.battleTag then
		lines[#lines + 1] = line(L["CARD_BATTLETAG"]:format(C.Escape(c.battleTag)), false, nil, copy(c.battleTag, L["COPY_TITLE_BATTLETAG"]), nil,
			{ source = "shared", observedAt = c.battleTagTime, author = c.battleTagAuthor, set = "contacts" })
	end
	if c and c.discord then
		local fmt = c.discordSource == "native" and L["CARD_DISCORD_NATIVE"] or L["CARD_DISCORD"]
		lines[#lines + 1] = line(fmt:format(C.Escape(c.discord)), false, nil, copy(c.discord, L["COPY_TITLE_DISCORD"]), nil,
			c.discordSource == "native" and { source = "native" }
			or { source = "shared", observedAt = c.discordTime, author = c.discordAuthor, set = "contacts" })
	end
	if #lines == 0 then lines[1] = line(e.hasAddon and L["CARD_NO_CONTACTS"] or L["CARD_NO_CONTACTS_ADDON"], true) end
	if C:CanSendFriendRequest(e) then
		lines[#lines + 1] = line(L["CARD_ADD_FRIEND"], false, nil, function() C:SendFriendRequest(e) end, true)
	end
	return { id = "contacts", title = L["CARD_CONTACTS"], lines = lines }
end

-- The badges under the name: where the member stands (online / not in the guild), their place in the account (main / alt)
-- and the addon. Texts are short and shown in capitals by the badge.
function Card.Badges(e)
	local out = {}
	if e.notInGuild then out[#out + 1] = { text = L["NOT_IN_GUILD_SHORT"], tone = "warn" }
	elseif e.online then out[#out + 1] = { text = L["ONLINE"], tone = "ok" } end
	local g = ns.Accounts and e.guid and ns.Accounts:GroupOf(e.guid) or nil
	if g and #g.members > 1 then
		if g.main == e.guid then out[#out + 1] = { text = L["CARD_MAIN"], tone = "accent" }
		else out[#out + 1] = { text = L["CARD_ALT"], tone = "neutral" } end
	end
	if e.hasAddon then out[#out + 1] = { text = e.addonVersion or L["COL_ADDON"], tone = "neutral" } end
	return out
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
	d.badges = Card.Badges(e)
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

local HEADER = 96       -- the part above the scrolling sections: the name, its subtitle, the badges

function Card:Build(parent)
	local f = Widgets.Card(parent, { width = Card.WIDTH, height = 200, shadow = true })
	f:Hide()
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f.mark = Widgets.ClassMark(f, 12)
	f.mark:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD, -23)
	f.title = Theme.NewText(f, "H1", "text-1")
	f.title:SetJustifyH("LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD + 22, -18)
	f.subtitle = Theme.NewText(f, "Small", "text-3")
	f.subtitle:SetJustifyH("LEFT")
	f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.subtitle:SetPoint("RIGHT", f, "RIGHT", -Card.PAD, 0)
	-- close (a cross) and, on a narrow panel, the Back button
	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(28, 28)
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
	f.close.bg = Theme.Slice(f.close, "rr_fill_8", "surface-3", "BACKGROUND", 0)
	f.close.bg:SetAllPoints(f.close)
	f.close.icon = f.close:CreateTexture(nil, "OVERLAY")
	f.close.icon:SetTexture(Assets.textures.icons.path)
	f.close.icon:SetTexCoord(Assets.IconCoords("cross"))
	f.close.icon:SetSize(14, 14)
	f.close.icon:SetPoint("CENTER")
	Theme.Tint(f.close.icon, "text-2")
	f.close:SetScript("OnEnter", function(self) Theme.Tint(self.bg, "surface-3", 1) end)
	f.close:SetScript("OnLeave", function(self) Theme.Tint(self.bg, "surface-3", 0) end)
	f.close:SetScript("OnClick", function() Card:Close() end)
	f.back = Widgets.Button(f, { text = L["CARD_BACK"], style = "ghost", height = 28, onClick = function() Card:Close() end })
	f.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
	f.badges = {}
	-- the sections scroll under the header: a clipping frame holds them and their lines
	f.content = CreateFrame("Frame", nil, f)
	f.content:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER)
	f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 12)
	if f.content.SetClipsChildren then f.content:SetClipsChildren(true) end
	f.sections, f.items = {}, {}
	f.thumb = f:CreateTexture(nil, "ARTWORK")
	Theme.Fill(f.thumb, "border-strong")
	f.thumb:SetWidth(3)
	f.thumb:Hide()
	f:SetScript("OnMouseWheel", function(_, delta) Card:ScrollBy(-delta * Card.WHEEL) end)
	f:SetScript("OnShow", function() Card:Layout() end)
	self.frame = f
	return f
end

-- An inner card per section, pooled: a surface-2 card with the heading (and a count badge) at its top.
local function section(f, i)
	local s = f.sections[i]
	if s then return s end
	s = Widgets.Card(f.content, { fill = "surface-2" })
	s:SetFrameLevel((f.content:GetFrameLevel() or 1) + 1)
	s.heading = Theme.NewText(s, "Eyebrow", "accent-text")
	s.heading:SetJustifyH("LEFT")
	s.heading:SetPoint("TOPLEFT", s, "TOPLEFT", Card.INNER, -Card.INNER)
	s.count = Widgets.Badge(s, "", "neutral")
	s.count:SetPoint("TOPRIGHT", s, "TOPRIGHT", -Card.INNER, -Card.INNER + 4)
	s.count:Hide()
	f.sections[i] = s
	return s
end

-- Items are pooled: a line of a section is a button (a link to another character, an action, a tooltip) with its text.
local function item(f, i)
	local it = f.items[i]
	if it then return it end
	it = CreateFrame("Button", nil, f.content)
	it:SetFrameLevel((f.content:GetFrameLevel() or 1) + 3)
	it.text = Theme.NewText(it, "Small", "text-1")
	it.text:SetJustifyH("LEFT")
	it.text:SetPoint("TOPLEFT", it, "TOPLEFT", 0, 0)
	it.sub = Theme.NewText(it, "MonoSmall", "text-3")   -- the second, smaller line of a character (guild, main)
	it.sub:SetJustifyH("LEFT")
	it.sub:SetPoint("TOPLEFT", it.text, "BOTTOMLEFT", 0, -2)
	it.sub:Hide()
	it.prov = Widgets.Provenance(it)   -- the label of the source, at the right of a line that has `prov` (M7.2)
	it.prov:SetPoint("TOPRIGHT", it, "TOPRIGHT", 0, 0)
	it.highlight = it:CreateTexture(nil, "HIGHLIGHT")
	Theme.Fill(it.highlight, "highlight")
	it.highlight:SetAllPoints(it)
	it:SetScript("OnClick", function(self)
		if self.guid then Card:ShowGUID(self.guid)
		elseif self.onClick then self.onClick(self) end
	end)
	Widgets.Tooltip.Attach(it, function(self) return self.tip end, "LEFT")
	f.items[i] = it
	return it
end

-- The token of a line: actions and links to other characters are the accent, muted lines text-3, the rest text-1.
local function lineToken(ln)
	if ln.action or ln.guid then return "accent-text" end
	return ln.muted and "text-3" or "text-1"
end

local function layoutBadges(f, d)
	local x = Card.PAD
	for i, b in ipairs(d.badges or {}) do
		local badge = f.badges[i]
		if not badge then
			badge = Widgets.Badge(f, b.text:upper(), b.tone)
			f.badges[i] = badge
		end
		badge:SetBadge(b.text:upper(), b.tone)
		badge:ClearAllPoints()
		badge:SetPoint("TOPLEFT", f, "TOPLEFT", x, -64)
		badge:Show()
		x = x + (badge:GetWidth() or 40) + 6
	end
	for i = #(d.badges or {}) + 1, #f.badges do f.badges[i]:Hide() end
end

function Card:Layout()
	local f, d = self.frame, self.description
	if not f or not d then return end
	local width = (f:GetWidth() or 0)
	if width < 100 then width = Card.WIDTH end
	local inner = width - 2 * Card.PAD
	local text = inner - 2 * Card.INNER
	f.title:SetText(d.title)
	f.title:ClearAllPoints()
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD + 22, -18)
	f.title:SetPoint("RIGHT", f, "RIGHT", self.narrow and -(Card.PAD + 84) or -48, 0)
	Theme.ClassText(f.title, classColor(d.classFile))
	if d.classFile then Widgets.PaintClassMark(f.mark, classColor(d.classFile)) else Widgets.ClearClassMark(f.mark) end
	f.subtitle:SetText(d.subtitle or "")
	f.back:SetShown(self.narrow == true)
	f.close:SetShown(self.narrow ~= true)
	layoutBadges(f, d)
	local y, n = 0, 0
	for si, sec in ipairs(d.sections) do
		local card = section(f, si)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", f.content, "TOPLEFT", Card.PAD, -(y - (self.scroll or 0)))
		card:SetWidth(inner)
		card.heading:SetText((sec.title or ""):upper())
		if sec.count then card.count:SetBadge(tostring(sec.count), "neutral") card.count:Show() else card.count:Hide() end
		local top = y
		local ly = y + Card.INNER + 20
		for _, ln in ipairs(sec.lines) do
			n = n + 1
			local it = item(f, n)
			it.guid, it.onClick, it.tip = ln.guid, ln.onClick, ln.tip
			it:ClearAllPoints()
			it:SetPoint("TOPLEFT", f.content, "TOPLEFT", Card.PAD + Card.INNER, -(ly - (self.scroll or 0)))
			it.prov:SetSource(ln.prov)
			local dim = it.prov:IsDim()
			it.text:SetWidth(ln.prov and max(60, text - (it.prov:GetWidth() or 0) - 8) or text)
			it.text:SetText(ln.text)
			if ln.classFile and not dim then Theme.ClassText(it.text, classColor(ln.classFile))
			else Theme.Text(it.text, dim and "text-3" or lineToken(ln)) end
			local h = max(14, it.text:GetStringHeight() or 14)
			if ln.sub then
				it.sub:SetWidth(it.text:GetWidth())
				it.sub:SetText(ln.sub)
				it.sub:Show()
				h = h + 2 + max(12, it.sub:GetStringHeight() or 12)
			else
				it.sub:SetText("")
				it.sub:Hide()
			end
			it:SetSize(text, h)
			it:EnableMouse(ln.guid ~= nil or ln.onClick ~= nil or ln.tip ~= nil)
			it:Show()
			ly = ly + h + Card.LINE_GAP
		end
		local h = ly - top + Card.INNER - Card.LINE_GAP
		card:SetHeight(h)
		card:Show()
		y = top + h + Card.SECTION_GAP
	end
	for si = #d.sections + 1, #f.sections do f.sections[si]:Hide() end
	for i = n + 1, #f.items do f.items[i]:Hide() end
	self.contentHeight = y
	self:PaintThumb()
end

-- How far the sections can scroll: what does not fit under the header.
function Card:MaxScroll()
	local f = self.frame
	local view = f and f.content and f.content:GetHeight() or 0
	if not view or view <= 0 or not self.contentHeight then return 0 end
	return max(0, self.contentHeight - view)
end

function Card:PaintThumb()
	local f = self.frame
	if not f then return end
	local limit = self:MaxScroll()
	if limit <= 0 then f.thumb:Hide() return end
	local view = f.content:GetHeight()
	local size = max(16, view * view / self.contentHeight)
	local top = (view - size) * ((self.scroll or 0) / limit)
	f.thumb:ClearAllPoints()
	f.thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -(HEADER + top))
	f.thumb:SetHeight(size)
	f.thumb:Show()
end

function Card:ScrollBy(delta)
	local target = max(0, min((self.scroll or 0) + delta, self:MaxScroll()))
	if target == (self.scroll or 0) then return false end
	self.scroll = target
	self:Layout()
	return true
end

-- Where the card goes: beside the table when the panel is wide, over it when narrow.
function Card:Place()
	local f, v = self.frame, ns.RosterView and ns.RosterView.frame
	if not f or not v then return end
	local host = ns.Shell and ns.Shell.host
	local win = ns.Window and ns.Window.frame
	self.detached = Card.DETACH and host ~= nil and host.mode == "window" and win ~= nil and win:IsShown() == true
	f:ClearAllPoints()
	if self.detached then
		-- a detail window of its own, beside the Accord window, as tall as it; it follows the window when it moves
		self.narrow = false
		f:SetWidth(Card.DETACHED_WIDTH)
		local right, screen = win:GetRight(), UIParent and UIParent:GetWidth()
		local room = not (type(right) == "number" and type(screen) == "number" and screen > 0)
			or right + Card.GAP + Card.DETACHED_WIDTH <= screen
		if room then
			f:SetPoint("TOPLEFT", win, "TOPRIGHT", Card.GAP, 0)
			f:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", Card.GAP, 0)
		else
			f:SetPoint("TOPRIGHT", win, "TOPLEFT", -Card.GAP, 0)
			f:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", -Card.GAP, 0)
		end
		if f.SetFrameStrata and win.GetFrameStrata then f:SetFrameStrata(win:GetFrameStrata()) end
		f:SetFrameLevel((win:GetFrameLevel() or 1) + 5)
		return
	end
	local width = v:GetWidth() or 0
	self.narrow = width > 0 and width < Card.WIDE
	if self.narrow then
		f:SetPoint("TOPLEFT", v.toolbar, "BOTTOMLEFT", 0, -8)
		f:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)
	else
		f:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, 0)
		f:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", 0, 0)
		f:SetWidth(Card.WIDTH)
	end
	f:SetFrameLevel((v:GetFrameLevel() or 1) + 20)
end

function Card:Inset()
	if self.frame and self.frame:IsShown() and not self.narrow and not self.detached then return Card.WIDTH + 8 end
	return 0
end

function Card:Show(entry)
	local v = ns.RosterView
	if not (v and v.frame) or not entry then return false end
	if not self.frame then self:Build(v.frame) end
	if not self.entry or self.entry.guid ~= entry.guid then self.scroll = 0 end
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

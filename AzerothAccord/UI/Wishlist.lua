-- WishlistView: the "Wishlist" mode of the Market view and the wishes on the member card (M13.3; SPEC-17 §4.2, §8).
-- Lua 5.1.
-- At the top the player's own list: an item (a pasted link, a number, or the name of an item the game knows), how many,
-- for how many days, a note for the whole list, and Remove on each row. Below, the guild's wishes by item: who wants it
-- (online first), how many, until when, and "I have some", which only opens the chat box with a whisper typed in (the
-- player sends it). Only with the switch "econ".
--   View.LeftText(left), View.ErrorText(why), View.WhisperText(row)     plain texts, tested offline
--   View:Add()                    writes what the form holds: true, or false and a reason
--   View:Remove(item), View:SaveNote(), View:Offer(row)
--   View.CardLines(guid)          the lines of a character's wishes for the "Market" section of the member card
--   View.Tip(row)                 the tooltip of a guild row
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.WishlistView, ns.modules = View, ns.modules or {}
ns.modules.WishlistView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, tostring, tonumber, max = type, ipairs, tostring, tonumber, math.max

View.ROW_HEIGHT = 32
View.OWN_HEIGHT = 140          -- the own list: its header and three rows (it scrolls)
View.ICON = 20

local function W() return ns.Wishlist end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end
local function redraw() if ns.MarketView then ns.MarketView:Redraw() end end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function View.LeftText(left)
	if left <= 1 then return L["WISH_TODAY"] end
	return L["WISH_DAYS_LEFT"]:format(left)
end

local ERRORS = { guild = "NOT_IN_GUILD", item = "WISH_ERR_ITEM", count = "WISH_ERR_COUNT", days = "WISH_ERR_DAYS",
	full = "WISH_ERR_FULL", note = "WISH_ERR_NOTE", rate = "ORD_ERR_RATE" }

function View.ErrorText(why)
	local M = W()
	if why == "count" then return L[ERRORS[why]]:format(M.QTY_MAX) end
	if why == "days" then return L[ERRORS[why]]:format(M.DAYS_MAX) end
	if why == "full" then return L[ERRORS[why]]:format(M.MAX) end
	if why == "note" then return L[ERRORS[why]]:format(M.NOTE_MAX) end
	return L[ERRORS[why] or "WISH_ERR_OTHER"]
end

-- The whisper of "I have some": the item's name, no link, so the chat box takes it as typed.
function View.WhisperText(row) return L["WISH_WHISPER"]:format(row.itemName) end

function View.Tip(row)
	local out = { escape(row.itemName) }
	out[#out + 1] = { text = L["WISH_TIP_WANTS"]:format(escape(row.name), row.n), token = "text-2" }
	out[#out + 1] = { text = L["WISH_TIP_UNTIL"]:format(ns.Orders.DayText(row.day), View.LeftText(row.left)), token = "text-3" }
	if row.source == "sl" then out[#out + 1] = { text = L["WISH_FROM_LIST"], token = "text-3" } end
	if row.note then out[#out + 1] = { text = L["ORD_NOTE_OF"]:format(escape(row.name), escape(row.note)) } end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------------
local function status(text, token)
	View.status, View.statusToken = text, token
	redraw()
end

local function done(rec, why, text)
	if not rec then
		status(View.ErrorText(why), "err")
		return false, why
	end
	status(text, "text-3")
	return true
end

function View:Add()
	local f = self.frame
	if not f then return false, "off" end
	local item = W().ParseItem(f.item:GetText())
	if not item then return done(nil, "item") end
	local n, days = f.count:GetText(), f.days:GetText()
	n = n == "" and 1 or tonumber(n) or -1
	days = days == "" and W().DAYS or tonumber(days) or -1
	local rec, why = W():Add(item, n, days)
	if rec then
		f.item:SetText("")
		f.count:SetText("")
		f.days:SetText("")
	end
	return done(rec, why, L["WISH_ADDED"])
end

function View:Remove(item)
	local rec, why = W():Remove(item)
	return done(rec, why, L["WISH_REMOVED"])
end

function View:SaveNote()
	local f = self.frame
	if not f then return false, "off" end
	local rec, why = W():SetNote(f.note:GetText())
	if not rec and why == nil then   -- an empty note and no list yet: nothing to write
		status(nil)
		return true
	end
	return done(rec, why, L["WISH_NOTE_SAVED"])
end

-- "I have some": the chat box with the whisper typed in; the player sends it.
function View:Offer(row)
	local e = ns.Roster and ns.Roster:ByGUID(row.guid)
	local name = e and (e.name or e.short)
	local ok = name ~= nil and ns.Compat.Chat.OpenWhisper(name, View.WhisperText(row))
	if not ok and ns.addon then ns.addon:Print(L["CR_REQUEST_FAILED"]) end
	return ok == true
end

---------------------------------------------------------------------------------------------------------------------
-- The mode of the Market view
---------------------------------------------------------------------------------------------------------------------
-- The item cell: the icon, then the name after it.
local function renderItem(list)
	return function(cell, row, frame)
		cell:SetText(escape(row.itemName))
		Theme.Text(cell, "text-1")
		local tableOf = View.frame and View.frame[list]
		local pos = tableOf and tableOf.pos and tableOf.pos[1]
		if pos then
			cell:ClearAllPoints()
			cell:SetWidth(max(pos.w - View.ICON - 16, 1))
			cell:SetPoint("LEFT", frame, "LEFT", pos.x + View.ICON + 8, 0)
		end
	end
end

local function col(id, key, opts)
	opts.id, opts.title, opts.sortable = id, key and L[key] or "", false
	return opts
end

local function untilText(r) return View.LeftText(r.left) end

local function ownColumns()
	return {
		col("item", "ORD_COL_ITEM", { flex = 2, render = renderItem("own") }),
		col("n", "WISH_COL_COUNT", { width = 80, mono = true, text = function(r) return tostring(r.n) end }),
		col("left", "WISH_COL_UNTIL", { width = 96, text = untilText }),
		col("source", nil, { flex = 1, text = function(r) return r.source == "sl" and L["WISH_FROM_LIST"] or "" end,
			token = function() return "text-3" end }),
		col("action", nil, { width = 112, render = function(cell) cell:SetText("") end }),
	}
end

local function guildColumns()
	return {
		col("item", "ORD_COL_ITEM", { flex = 2, render = renderItem("guild") }),
		col("who", "WISH_COL_WHO", { flex = 1, text = function(r) return escape(r.name) end,
			token = function(r) return r.online and "text-1" or "text-3" end }),
		col("n", "WISH_COL_COUNT", { width = 80, mono = true, text = function(r) return tostring(r.n) end }),
		col("left", "WISH_COL_UNTIL", { width = 96, text = untilText }),
		-- what the player owns of it (M13.4): whether they can help
		col("mine", "SHOP_COL_YOURS", { width = 72, mono = true, text = function(r)
			return ns.DemandView and ns.DemandView.YoursText(r) or ""
		end }),
		col("action", nil, { width = 112, render = function(cell) cell:SetText("") end }),
	}
end

local function setIcon(row, d, list)
	local pos = View.frame[list].pos and View.frame[list].pos[1]
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", pos and pos.x or 8, 0)
	local icon = ns.Compat.Item.Icon(d.item)
	if icon then row.icon:SetTexture(icon) row.icon:Show() else row.icon:Hide() end
end

local function setup(label, style, onClick, tip)
	return function(row)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(View.ICON, View.ICON)
		row.action = Widgets.Button(row, { text = L[label], style = style, width = 104, height = Widgets.HEIGHT.small,
			onClick = function(b)
				local d = b:GetParent().data
				if d then onClick(d) end
			end })
		row.action:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
		row.action:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		if tip then
			row:HookScript("OnEnter", function(self)
				if self.data then Widgets.Tooltip.Show(self, tip(self.data), "BOTTOM") end
			end)
			row:HookScript("OnLeave", function() Widgets.Tooltip.Hide() end)
		end
	end
end

local function label(f, key, y)
	local fs = Widgets.Text(f, "Small", "text-2", "LEFT")
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -y)
	fs:SetText(L[key])
	return fs
end

local mode = {}

function mode.build(f)
	View.frame = f
	local function enter() View:Add() end
	f.add = Widgets.Button(f, { text = L["WISH_ADD"], style = "filled", dense = true, width = 120, onClick = enter })
	f.add:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.days = Widgets.EditBox(f, { width = 80, dense = true, maxLetters = 2, onEnter = enter,
		placeholder = L["WISH_DAYS_HINT"]:format(W().DAYS) })
	f.days:SetPoint("TOPRIGHT", f.add, "TOPLEFT", -8, 0)
	f.count = Widgets.EditBox(f, { width = 80, dense = true, maxLetters = 3, onEnter = enter, placeholder = L["WISH_COUNT_HINT"] })
	f.count:SetPoint("TOPRIGHT", f.days, "TOPLEFT", -8, 0)
	f.item = Widgets.EditBox(f, { width = 240, dense = true, maxLetters = 200, onEnter = enter, placeholder = L["WISH_ITEM_HINT"] })
	f.item:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.item:SetPoint("TOPRIGHT", f.count, "TOPLEFT", -8, 0)
	f.status = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -40)
	f.status:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.status:SetWordWrap(false)
	label(f, "WISH_MINE", 60)
	f.own = Widgets.DataTable(f, ownColumns(), { rowHeight = View.ROW_HEIGHT, pool = 6, maxPool = 30,
		emptyText = L["WISH_MINE_EMPTY"],
		rowSetup = setup("WISH_REMOVE", "text", function(d) View:Remove(d.item) end),
		rowUpdate = function(row, d) setIcon(row, d, "own") end })
	f.own:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -78)
	f.own:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -78)
	f.own:SetHeight(View.OWN_HEIGHT)
	local y = 78 + View.OWN_HEIGHT + 8
	f.note = Widgets.EditBox(f, { width = 360, dense = true, maxLetters = W().NOTE_MAX, placeholder = L["WISH_NOTE_HINT"],
		onEnter = function() View:SaveNote() end })
	f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
	label(f, "WISH_GUILD", y + 44)
	f.guild = Widgets.DataTable(f, guildColumns(), { rowHeight = View.ROW_HEIGHT, pool = 14, maxPool = 60,
		emptyText = L["WISH_GUILD_EMPTY"],
		rowSetup = setup("WISH_HAVE", "tonal", function(d) View:Offer(d) end, View.Tip),
		rowUpdate = function(row, d)
			setIcon(row, d, "guild")
			row.action:SetShown(not d.own)
		end })
	f.guild:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(y + 62))
	f.guild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

function mode.refresh(f)
	local list, note = W():Own()
	for _, e in ipairs(list) do e.itemName = W().ItemName(e.item) end
	View.ownRows = list
	f.own:SetData(list, true)
	local search = ns.MarketView and ns.MarketView.search
	local rows = W():Guild(search)
	View.rows = rows
	f.guild:SetEmptyText(L[(search and search ~= "") and "WISH_NO_MATCH" or "WISH_GUILD_EMPTY"])
	f.guild:SetData(rows, true)
	-- the note is not overwritten while it is being typed
	if not f.note.focused and View.noteShown ~= (note or "") then
		View.noteShown = note or ""
		f.note:SetText(View.noteShown)
	end
	f.status:SetText(View.status or L["WISH_HINT"])
	Theme.Text(f.status, View.status and View.statusToken or "text-3")
end

if ns.MarketView then
	ns.MarketView.AddMode("wishlist", { label = L["MARKET_MODE_WISHLIST"], order = 20, build = mode.build, refresh = mode.refresh,
		available = function() return W() ~= nil and W().Enabled() end })
end

---------------------------------------------------------------------------------------------------------------------
-- The member card
---------------------------------------------------------------------------------------------------------------------
function View.CardLines(guid)
	local out = {}
	if not (W() and W().Enabled()) then return out end
	for _, e in ipairs(W().Live(ns.Store:Get(W().SET, W().IdOf(guid)))) do
		out[#out + 1] = { text = L["WISH_CARD_LINE"]:format(escape(W().ItemName(e.item)), e.n, View.LeftText(e.left)),
			action = true, onClick = function() if ns.MarketView then ns.MarketView:Open("wishlist") end end }
	end
	return out
end

if ns.addon then
	ns.addon.WishlistView = View
	if ns.Bus then
		ns.Bus:On("WISHLIST_CHANGED", function()
			if not (W() and W().Enabled()) then return end
			if ns.MemberCard then ns.MemberCard:Refresh() end
			if ns.MarketView then ns.MarketView:Changed() end
		end)
		ns.Bus:On("GUILD_CHANGED", function()
			View.status, View.statusToken, View.noteShown = nil, nil, nil
			if View.frame then
				for _, key in ipairs({ "item", "count", "days", "note" }) do View.frame[key]:SetText("") end
			end
		end)
	end
end

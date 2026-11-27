-- ShoppingView: the "Shopping list" page of the Professions view (M13.4; SPEC-17 §5.6, §5.8; ui-style §9, ADR 0027).
-- Lua 5.1.
-- At the top the recipes picked (from the catalogue's "Add to list", or here: a profession, a recipe of it filtered by the
-- panel's search box, how many), each with how many times, the pieces it makes, - / + and Remove; then the switch "Break
-- down intermediate materials" and the chips Missing only, Count alts, Count mail; then one row per material: the icon and
-- the name in its quality's colour, a ThinBar owned/needed, "12 / 40" in mono, "Missing 28" in err, the guild bank's
-- column (dimmed with age) and, with Auctionator, the price. At the bottom how many are missing, the estimated cost, and the
-- tonal buttons Ask the bank and Ask the guild (no filled button: the page concludes nothing). Only with the switch "econ".
--   View.CountText(r), View.MissingText(r), View.BankText(r), View.PriceText(r), View.SummaryText(result),
--   View.MaterialTip(r), View.GuildText(plan)        plain texts, tested offline
--   View:Add(recipe, n, line)                        "Add to list" (the catalogue calls it): true or false, why
--   View:AskGuild() / View:ConfirmGuild()            the confirmation, then the wishlist written
--   View:BankList() / View:Request(bankRow)          the Ask the bank list; Request prefills the bank request form
local ADDON_NAME, ns = ...
ns = ns or {}
local View = {}
ns.ShoppingView, ns.modules = View, ns.modules or {}
ns.modules.ShoppingView = View

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme
local type, ipairs, pairs, tostring, tonumber, max, min = type, ipairs, pairs, tostring, tonumber, math.max, math.min

View.ROW_HEIGHT = 32
View.LIST_HEIGHT = 32 * 4 + 34   -- the recipes: the header and four rows (it scrolls)
View.ICON = 20
View.BANK_ROWS = 8
View.GUILD_LINES = 12            -- items named in the confirmation, the rest summed up

local function S() return ns.Shopping end
local function escape(text) return ns.Contacts and ns.Contacts.Escape(text) or (tostring(text or ""):gsub("|", "||")) end
local function now() return ns.Compat.ServerTime() end
local function ago(t) return t and ns.Provenance.AgeText(max(0, now() - t)) or nil end
local function money(c) return ns.BankView and ns.BankView.MoneyText(c) or tostring(c) end

function View.Enabled() return S() ~= nil and S().Enabled() end

---------------------------------------------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------------------------------------------
function View.CountText(r) return ("%d / %d"):format(min(r.owned, r.need), r.need) end

function View.MissingText(r)
	if r.missing > 0 then return L["SHOP_MISSING"]:format(r.missing) end
	if r.broken > 0 then return L["SHOP_BROKEN"]:format(min(r.owned, r.need), r.broken) end
	return L["SHOP_ENOUGH"]
end

function View.BankText(r)
	if not r.guildBank or r.guildBank <= 0 then return "" end
	return L["SHOP_BANK_N"]:format(r.guildBank)
end

function View.PriceText(r)
	if not r.price then return "" end
	return money(r.price)
end

function View.SummaryText(result)
	local parts = {}
	if #result.rows == 0 and #result.unknown == 0 then return L["SHOP_EMPTY"] end
	parts[#parts + 1] = result.missingRows > 0 and L["SHOP_SUMMARY_MISSING"]:format(result.missingRows) or L["SHOP_SUMMARY_DONE"]
	if result.pricesOn and result.priced > 0 then
		local age = result.costAge and L["SHOP_COST_AGE"]:format(result.costAge) or ""
		parts[#parts + 1] = L["SHOP_COST"]:format(money(result.cost), age)
	elseif not result.pricesOn then
		parts[#parts + 1] = L["SHOP_NO_PRICES"]
	end
	if #result.unknown > 0 then parts[#parts + 1] = L["SHOP_UNKNOWN"]:format(#result.unknown) end
	return table.concat(parts, " · ")
end

local function part(label, n, at, never)
	if never then return L["SHOP_PART_NEVER"]:format(label) end
	local age = ago(at)
	return age and L["SHOP_PART_AGE"]:format(label, n, age) or L["SHOP_PART"]:format(label, n)
end

local function charName(guid)
	for _, c in ipairs(ns.Inventory and ns.Inventory:Characters() or {}) do
		if c.guid == guid then return c.name end
	end
	return "?"
end

-- The tooltip of a material: every part with its age, the alts, the guild bank, the price, the alternatives.
function View.MaterialTip(r)
	local c = r.count or {}
	local ages = c.ages or {}
	local out = { escape(r.name) }
	out[#out + 1] = { text = L["SHOP_TIP_NEED"]:format(r.need, r.owned), token = "text-2" }
	local parts = { part(L["SHOP_BAGS"], c.bags or 0, ages.bags, ages.bags == nil),
		part(L["SHOP_BANK"], c.bank or 0, ages.bank, ages.bank == nil) }
	local opts = S():Options()
	if opts.mail and ns.Inventory and ns.Inventory.READ_MAIL then parts[#parts + 1] = part(L["SHOP_MAIL"], c.mail or 0, ages.mail, ages.mail == nil) end
	if (c.account or 0) > 0 then parts[#parts + 1] = L["SHOP_PART"]:format(L["SHOP_ACCOUNT_BANK"], c.account) end
	out[#out + 1] = { text = table.concat(parts, ", "), token = "text-3" }
	local alts = {}
	for guid, n in pairs(c.alts or {}) do alts[#alts + 1] = L["SHOP_PART"]:format(escape(charName(guid)), n) end
	table.sort(alts)
	if #alts > 0 then out[#out + 1] = { text = L["SHOP_TIP_ALTS"]:format(table.concat(alts, ", ")), token = "text-3" } end
	local others = {}
	for guid, n in pairs(c.others or {}) do others[#others + 1] = L["SHOP_PART"]:format(escape(charName(guid)), n) end
	table.sort(others)
	if #others > 0 then out[#out + 1] = { text = L["SHOP_TIP_OTHERS"]:format(table.concat(others, ", ")), token = "text-3" } end
	if r.guildBank and r.guildBank > 0 then
		out[#out + 1] = { text = L["SHOP_TIP_GUILD"]:format(r.guildBank, ago(r.guildBankAt) or "?"), token = "text-3" }
	end
	if r.price then
		out[#out + 1] = { text = L["SHOP_TIP_PRICE"]:format(money(r.price), r.priceAge or 0), token = "text-3" }
	end
	if r.broken > 0 then out[#out + 1] = { text = L["SHOP_TIP_BROKEN"]:format(r.broken), token = "text-3" } end
	out[#out + 1] = { text = L["SHOP_TIP_MAIL_NOTE"], token = "text-3" }
	return out
end

-- The confirmation of Ask the guild: what the guild will see.
function View.GuildText(plan)
	local names = {}
	for i, w in ipairs(plan.asked) do
		if i > View.GUILD_LINES then
			names[#names + 1] = L["SHOP_GUILD_MORE"]:format(#plan.asked - View.GUILD_LINES)
			break
		end
		names[#names + 1] = L["SHOP_GUILD_ITEM"]:format(escape((ns.Wishlist.ItemName(w.item))), w.n)
	end
	local text = L["SHOP_GUILD_SEE"]:format(table.concat(names, ", "))
	if plan.left > 0 then text = text .. "\n" .. L["SHOP_GUILD_LEFT"]:format(plan.left, ns.Wishlist.MAX) end
	return text
end

local ERRORS = { full = "SHOP_ERR_FULL", count = "SHOP_ERR_COUNT", recipe = "SHOP_ERR_RECIPE", off = "SHOP_ERR_RECIPE",
	guild = "NOT_IN_GUILD", rate = "ORD_ERR_RATE", empty = "SHOP_ERR_EMPTY" }

function View.ErrorText(why)
	local key = ERRORS[why] or "SHOP_ERR_OTHER"
	if why == "full" then return L[key]:format(S().MAX_RECIPES) end
	if why == "count" then return L[key]:format(S().QTY_MAX) end
	if key == "SHOP_ERR_OTHER" then return L[key]:format(tostring(why)) end
	return L[key]
end

---------------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------------
local function setStatus(text, token)
	View.status, View.statusToken = text, token
	if View.frame and View.frame:IsVisible() then View:Refresh() end
end

function View:Add(recipe, n, line)
	local e, why = S():Add(recipe, n, line)
	if not e then
		setStatus(View.ErrorText(why), "err")
		if ns.addon then ns.addon:Print(View.ErrorText(why)) end
		return false, why
	end
	local name = ns.Recipes and ns.Recipes.NameOf(recipe) or tostring(recipe)
	setStatus(L["SHOP_ADDED"]:format(escape(name), e.n), "text-3")
	return true
end

-- Opens the page of the Professions view.
function View:Open()
	if not View.Enabled() or not ns.RecipeView then return false end
	local shown = ns.Shell and ns.Shell:OpenView("professions")
	ns.RecipeView:SetMode("shopping")
	return shown ~= false
end

function View:AskGuild()
	local plan, why = S():PlanGuild()
	if not plan then return false, why end
	if #plan.asked == 0 then
		setStatus(View.ErrorText("empty"), "text-3")
		return false, "empty"
	end
	View.plan = plan
	if self.guildDialog or self.BuildGuildDialog then
		local d = self:BuildGuildDialog()
		d.body:SetText(View.GuildText(plan))
		d:Open()
	end
	return true, plan
end

function View:ConfirmGuild()
	if self.guildDialog then self.guildDialog:Close() end
	local rec, plan = S():AskGuild()
	if not rec then
		setStatus(View.ErrorText(plan), "err")
		return false, plan
	end
	setStatus(L["SHOP_GUILD_DONE"]:format(#plan.asked), "ok")
	return true, plan
end

function View:BankList()
	local rows = S():BankRows()
	View.bankRows = rows
	if self.BuildBankDialog then
		local d = self:BuildBankDialog()
		View.FillBank(d, rows)
		d:Open()
	end
	return rows
end

-- Opens the guild bank's request form prefilled: a withdrawal of this item, min(missing, available), the reason.
function View:Request(row)
	if self.bankDialog then self.bankDialog:Close() end
	local BRV = ns.BankRequestsView
	if not (BRV and BRV.Prefill) then return false end
	return BRV.Prefill({ item = row.item, name = row.name, count = row.n, reason = S():Reason() })
end

---------------------------------------------------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------------------------------------------------
function View:BuildGuildDialog()
	if self.guildDialog then return self.guildDialog end
	local d = Widgets.Dialog(UIParent, "AzerothAccordShoppingGuildDialog", { width = 460, height = 240 })
	d:SetTitle(L["SHOP_ASK_GUILD"])
	d.body = Widgets.Text(d.card, "Small", "text-2", "LEFT")
	d.body:SetPoint("TOPLEFT", d.card, "TOPLEFT", Widgets.DIALOG.pad, -64)
	d.body:SetPoint("BOTTOMRIGHT", d.card, "BOTTOMRIGHT", -Widgets.DIALOG.pad, 64)
	d.body:SetJustifyV("TOP")
	d.cancel = Widgets.Button(d.card, { text = L["SHOP_CANCEL"], style = "text", dense = true, onClick = function() d:Close() end })
	d.ok = Widgets.Button(d.card, { text = L["SHOP_ASK_GUILD"], style = "filled", dense = true, width = 140,
		onClick = function() View:ConfirmGuild() end })
	d:SetActions({ d.cancel, d.ok })
	self.guildDialog = d
	return d
end

function View:BuildBankDialog()
	if self.bankDialog then return self.bankDialog end
	local h = 120 + View.BANK_ROWS * View.ROW_HEIGHT
	local d = Widgets.Dialog(UIParent, "AzerothAccordShoppingBankDialog", { width = 520, height = h })
	d:SetTitle(L["SHOP_ASK_BANK"])
	d.hint = Widgets.Text(d.card, "Small", "text-3", "LEFT")
	d.hint:SetPoint("TOPLEFT", d.card, "TOPLEFT", Widgets.DIALOG.pad, -56)
	d.hint:SetPoint("RIGHT", d.card, "RIGHT", -Widgets.DIALOG.pad, 0)
	d.hint:SetText(L["SHOP_BANK_HINT"])
	d.rows = {}
	for i = 1, View.BANK_ROWS do
		local row = CreateFrame("Frame", nil, d.card)
		row:SetHeight(View.ROW_HEIGHT)
		row:SetPoint("TOPLEFT", d.card, "TOPLEFT", Widgets.DIALOG.pad, -76 - (i - 1) * View.ROW_HEIGHT)
		row:SetPoint("RIGHT", d.card, "RIGHT", -Widgets.DIALOG.pad, 0)
		row.text = Widgets.Text(row, "Small", "text-1", "LEFT")
		row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.text:SetPoint("RIGHT", row, "RIGHT", -120, 0)
		row.button = Widgets.Button(row, { text = L["SHOP_REQUEST"], style = "tonal", width = 104, height = Widgets.HEIGHT.small,
			onClick = function() if row.data then View:Request(row.data) end end })
		row.button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.note = Widgets.Text(row, "Small", "text-3", "RIGHT")
		row.note:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		d.rows[i] = row
	end
	d.empty = Widgets.Text(d.card, "Small", "text-3", "LEFT")
	d.empty:SetPoint("TOPLEFT", d.card, "TOPLEFT", Widgets.DIALOG.pad, -80)
	d.close = Widgets.Button(d.card, { text = L["SHOP_CLOSE"], style = "text", dense = true, onClick = function() d:Close() end })
	d:SetActions({ d.close })
	self.bankDialog = d
	return d
end

function View.FillBank(d, rows)
	for i, row in ipairs(d.rows) do
		local r = rows[i]
		row.data = r
		row:SetShown(r ~= nil)
		if r then
			row.text:SetText(L["SHOP_BANK_ROW"]:format(escape(r.name), r.missing, r.available, ago(r.at) or "?"))
			row.button:SetShown(not r.requested)
			row.note:SetShown(r.requested)
			row.note:SetText(r.requested and L["SHOP_ALREADY"] or "")
		end
	end
	d.empty:SetShown(#rows == 0)
	d.empty:SetText(L["SHOP_BANK_NONE"])
end

---------------------------------------------------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------------------------------------------------
local function col(id, key, opts)
	opts.id, opts.title, opts.sortable = id, key and L[key] or "", false
	return opts
end

local function placeAfterIcon(t, cell, frame)
	local pos = t.pos and t.pos[1]
	if pos then
		cell:ClearAllPoints()
		cell:SetWidth(max(pos.w - View.ICON - 16, 1))
		cell:SetPoint("LEFT", frame, "LEFT", pos.x + View.ICON + 8, 0)
	end
end

local function recipeColumns()
	return {
		col("recipe", "RV_COL_RECIPE", { flex = 2, render = function(cell, d, row)
			cell:SetText(escape(d.name))
			Theme.Text(cell, d.resolved and "text-1" or "text-3")
			placeAfterIcon(View.frame.recipes, cell, row)
		end }),
		col("n", "SHOP_COL_TIMES", { width = 150, mono = true, text = function(d)
			return d.made and d.made > 1 and L["SHOP_TIMES_PIECES"]:format(d.n, d.n * d.made) or L["SHOP_TIMES"]:format(d.n)
		end }),
		col("action", nil, { width = 196, render = function(cell) cell:SetText("") end }),
	}
end

local function materialColumns()
	return {
		col("item", "ORD_COL_ITEM", { flex = 2, render = function(cell, r, row)
			cell:SetText(escape(r.name))
			local info = ns.Compat.Item.Info(r.item)
			if r.broken > 0 and r.missing == 0 then Theme.Text(cell, "text-3")
			elseif ns.BankView and ns.BankView.PaintQuality then ns.BankView.PaintQuality(cell, info and info.quality)
			else Theme.Text(cell, "text-1") end
			placeAfterIcon(View.frame.mats, cell, row)
		end }),
		col("bar", nil, { width = 120, render = function(cell) cell:SetText("") end }),
		col("count", "SHOP_COL_OWNED", { width = 90, mono = true, align = "RIGHT", text = View.CountText }),
		col("missing", "SHOP_COL_MISSING", { width = 150, text = View.MissingText,
			token = function(r) return r.missing > 0 and "err" or (r.broken > 0 and "text-3" or "ok") end }),
		col("bank", "SHOP_COL_BANK", { width = 90, text = View.BankText, token = function(r)
			local old = r.guildBankAt and now() - r.guildBankAt > (ns.Provenance.DIM_DAYS.bank or 7) * 86400
			return old and "text-3" or "text-2"
		end }),
		col("price", "SHOP_COL_PRICE", { width = 100, align = "RIGHT", text = View.PriceText, token = function(r)
			return (r.priceAge and r.priceAge > ns.Prices.STALE) and "text-3" or "text-2"
		end }),
	}
end

local function setIcon(row, d, t)
	local pos = t.pos and t.pos[1]
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", pos and pos.x or 8, 0)
	if d.icon then row.icon:SetTexture(d.icon) row.icon:Show() else row.icon:Hide() end
end

local function smallButton(row, text, style, width, onClick)
	local b = Widgets.Button(row, { text = text, style = style, width = width, height = Widgets.HEIGHT.small,
		onClick = function(btn) local d = btn:GetParent().data if d then onClick(d) end end })
	b:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	return b
end

local function recipeSetup(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(View.ICON, View.ICON)
	row.remove = smallButton(row, L["SHOP_REMOVE"], "text", 84, function(d) S():Remove(d.recipe) end)
	row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.plus = smallButton(row, "+", "text", 40, function(d) S():Set(d.recipe, min(d.n + 1, S().QTY_MAX)) end)
	row.plus:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
	row.minus = smallButton(row, "-", "text", 40, function(d) if d.n > 1 then S():Set(d.recipe, d.n - 1) end end)
	row.minus:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
end

local function materialSetup(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(View.ICON, View.ICON)
	row.bar = Widgets.ThinBar(row, { width = 104 })
	row:HookScript("OnEnter", function(self)
		if self.data then Widgets.Tooltip.Show(self, View.MaterialTip(self.data), "BOTTOM") end
	end)
	row:HookScript("OnLeave", function() Widgets.Tooltip.Hide() end)
end

local function materialUpdate(row, r)
	local t = View.frame.mats
	r.icon = ns.Compat.Item.Icon(r.item)
	setIcon(row, r, t)
	local pos = t.pos and t.pos[2]
	row.bar:ClearAllPoints()
	row.bar:SetPoint("LEFT", row, "LEFT", (pos and pos.x or 0) + 8, 0)
	row.bar:SetWidth(max((pos and pos.w or 120) - 16, 8))
	local f = r.need > 0 and min(r.owned + r.broken, r.need) / r.need or 1
	row.bar:SetFraction(f)
	Theme.Fill(row.bar.fill, f >= 1 and "ok" or "accent")
	-- a material just completed flashes once (Motion, off with the animations)
	local was = View.lastMissing and View.lastMissing[r.item]
	if was and was > 0 and r.missing == 0 and ns.Motion and ns.Motion.On() then ns.Motion.Pulse(row.bar, 0.4, 1, 0.4) end
end

local function label(f, text, anchor, y)
	local fs = Widgets.Text(f, "Small", "text-2", "LEFT")
	fs:SetPoint("TOPLEFT", anchor or f, anchor and "BOTTOMLEFT" or "TOPLEFT", 0, y or 0)
	fs:SetText(text)
	return fs
end

-- The recipes of the chosen profession that match the panel's search, for the recipe Select.
function View.RecipeChoices(line, search)
	local out = {}
	local cat = line and ns.RecipeCatalogue and ns.RecipeCatalogue:Get(line)
	local needle = type(search) == "string" and search ~= "" and search:lower() or nil
	for _, id in ipairs(cat and cat.ids or {}) do
		local name = ns.Recipes.NameOf(id)
		if name and (not needle or name:lower():find(needle, 1, true)) then out[#out + 1] = { id = id, text = name } end
	end
	table.sort(out, function(a, b) if a.text ~= b.text then return a.text < b.text end return a.id < b.id end)
	return out
end

function View:Build(f)
	self.frame = f
	local opts = S():Options()
	-- the header: back to the guild's recipes, the title
	f.back = Widgets.Button(f, { text = L["CAT_BACK"], style = "text", dense = true, onClick = function()
		if ns.RecipeView then ns.RecipeView:SetMode("catalogue") end
	end })
	f.back:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.title = Theme.NewText(f, "H1", "text-1")
	f.title:SetJustifyH("LEFT")
	f.title:SetPoint("LEFT", f.back, "RIGHT", 16, 0)
	f.title:SetText(L["SHOP_TITLE"])
	f.private = Widgets.Text(f, "Small", "text-3", "RIGHT")
	f.private:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -10)
	f.private:SetText(L["SHOP_PRIVATE"])
	-- adding a recipe: the profession, the recipe (filtered by the panel's search box), how many
	f.profession = Widgets.Select(f, { width = 200, rows = 10, placeholder = L["CAT_PROFESSION"], onSelect = function(id)
		S():SetOption("skill", id)
		View:Refresh()
	end })
	f.profession:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -48)
	f.recipe = Widgets.Select(f, { width = 260, rows = 10, placeholder = L["SHOP_PICK_RECIPE"] })
	f.recipe:SetPoint("LEFT", f.profession, "RIGHT", 8, 0)
	f.count = Widgets.EditBox(f, { width = 64, dense = true, maxLetters = 3, placeholder = "1" })
	f.count:SetPoint("LEFT", f.recipe, "RIGHT", 8, 0)
	f.add = Widgets.Button(f, { text = L["SHOP_ADD"], style = "tonal", dense = true, width = 96, onClick = function()
		local id = f.recipe:Selected()
		if not id then return setStatus(L["SHOP_ERR_PICK"], "err") end
		local n = f.count:GetText()
		n = n == "" and 1 or tonumber(n) or -1
		if View:Add(id, n, f.profession:Selected()) then f.count:SetText("") end
	end })
	f.add:SetPoint("LEFT", f.count, "RIGHT", 8, 0)
	f.clear = Widgets.Button(f, { text = L["SHOP_CLEAR"], style = "text", dense = true, width = 96, onClick = function()
		View:ConfirmClear()
	end })
	f.clear:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -48)
	-- the recipes
	f.recipes = Widgets.DataTable(f, recipeColumns(), { rowHeight = View.ROW_HEIGHT, pool = 4, maxPool = 20,
		emptyText = L["SHOP_LIST_EMPTY"], rowSetup = recipeSetup,
		rowUpdate = function(row, d) setIcon(row, d, View.frame.recipes) end })
	f.recipes:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -92)
	f.recipes:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -92)
	f.recipes:SetHeight(View.LIST_HEIGHT)
	-- the switch and the chips
	local y = -(92 + View.LIST_HEIGHT + 8)
	f.breakdown = Widgets.Switch(f, { on = opts.breakdown, onChange = function(on) S():SetBreakdown(on) end })
	f.breakdown:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
	f.breakdownLabel = Widgets.Text(f, "Small", "text-1", "LEFT")
	f.breakdownLabel:SetPoint("LEFT", f.breakdown, "RIGHT", 8, 0)
	f.breakdownLabel:SetText(L["SHOP_BREAKDOWN"])
	Widgets.Tooltip.Attach(f.breakdown, { L["SHOP_BREAKDOWN"], L["SHOP_BREAKDOWN_TIP"] }, "BOTTOM")
	local function chip(key, text, anchor)
		local c = Widgets.Chip(f, { text = text, onClick = function(ch)
			S():SetOption(key, not ch:IsSelected())
		end })
		c:SetPoint("LEFT", anchor, "RIGHT", anchor == f.breakdownLabel and 24 or 8, 0)
		return c
	end
	f.missingOnly = chip("missingOnly", L["SHOP_MISSING_ONLY"], f.breakdownLabel)
	f.alts = chip("alts", L["SHOP_COUNT_ALTS"], f.missingOnly)
	f.mail = chip("mail", L["SHOP_COUNT_MAIL"], f.alts)
	Widgets.Tooltip.Attach(f.alts, { L["SHOP_COUNT_ALTS"], L["SHOP_COUNT_ALTS_TIP"] }, "BOTTOM")
	Widgets.Tooltip.Attach(f.mail, { L["SHOP_COUNT_MAIL"], L["SHOP_COUNT_MAIL_TIP"] }, "BOTTOM")
	-- the materials
	f.mats = Widgets.DataTable(f, materialColumns(), { rowHeight = View.ROW_HEIGHT, pool = 12, maxPool = 60,
		emptyText = L["SHOP_MATS_EMPTY"], rowSetup = materialSetup, rowUpdate = materialUpdate })
	f.mats:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y - 44)
	f.mats:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 52)
	-- the footer
	f.askGuild = Widgets.Button(f, { text = L["SHOP_ASK_GUILD"], style = "tonal", dense = true, width = 140,
		onClick = function() View:AskGuild() end })
	f.askGuild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 8)
	Widgets.Tooltip.Attach(f.askGuild, { L["SHOP_ASK_GUILD"], L["SHOP_ASK_GUILD_TIP"] }, "TOP")
	f.askBank = Widgets.Button(f, { text = L["SHOP_ASK_BANK"], style = "tonal", dense = true, width = 140,
		onClick = function() View:BankList() end })
	f.askBank:SetPoint("RIGHT", f.askGuild, "LEFT", -8, 0)
	Widgets.Tooltip.Attach(f.askBank, { L["SHOP_ASK_BANK"], L["SHOP_ASK_BANK_TIP"] }, "TOP")
	f.summary = Widgets.Text(f, "Small", "text-2", "LEFT")
	f.summary:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 30)
	f.summary:SetPoint("RIGHT", f.askBank, "LEFT", -12, 0)
	f.summary:SetWordWrap(false)
	f.status = Widgets.Text(f, "Small", "text-3", "LEFT")
	f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 10)
	f.status:SetPoint("RIGHT", f.askBank, "LEFT", -12, 0)
	f.status:SetWordWrap(false)
end

function View:ConfirmClear()
	if not self.clearDialog then
		local d = Widgets.Dialog(UIParent, "AzerothAccordShoppingClearDialog", { width = 420, height = 180 })
		d:SetTitle(L["SHOP_CLEAR"])
		d.body = Widgets.Text(d.card, "Small", "text-2", "LEFT")
		d.body:SetPoint("TOPLEFT", d.card, "TOPLEFT", Widgets.DIALOG.pad, -64)
		d.body:SetPoint("RIGHT", d.card, "RIGHT", -Widgets.DIALOG.pad, 0)
		d.body:SetText(L["SHOP_CLEAR_ASK"])
		d.cancel = Widgets.Button(d.card, { text = L["SHOP_CANCEL"], style = "text", dense = true, onClick = function() d:Close() end })
		d.ok = Widgets.Button(d.card, { text = L["SHOP_CLEAR"], style = "filled", dense = true, width = 120, onClick = function()
			d:Close()
			S():Clear()
		end })
		d:SetActions({ d.cancel, d.ok })
		self.clearDialog = d
	end
	self.clearDialog:Open()
	return self.clearDialog
end

-- The recipes of the list as rows of the first table.
function View.RecipeRows()
	local out = {}
	for _, e in ipairs(S():List()) do
		local data = ns.Recipes.SpellData(e.recipe)
		local mats = ns.Reagents and ns.Reagents:Get(e.recipe)
		out[#out + 1] = { recipe = e.recipe, n = e.n, name = data and data.name or L["RV_RECIPE_ID"]:format(e.recipe),
			resolved = data ~= nil, icon = data and data.icon or nil, made = mats and mats.made or nil }
	end
	return out
end

function View:Refresh()
	local f = self.frame
	if not f then return end
	local opts = S():Options()
	local profs, chosen = {}, opts.skill
	for _, p in ipairs(ns.RecipeModel and ns.RecipeModel.Professions() or {}) do
		profs[#profs + 1] = { id = p.skillLine, text = p.name }
		if not chosen then chosen = p.skillLine end
	end
	f.profession:SetChoices(profs)
	if chosen then f.profession:Select(chosen, true) end
	f.recipe:SetChoices(View.RecipeChoices(chosen, View.search))
	f.recipes:SetData(View.RecipeRows(), true)
	f.breakdown:SetOn(opts.breakdown, true)
	f.missingOnly:SetSelected(opts.missingOnly)
	f.alts:SetSelected(opts.alts)
	f.mail:SetSelected(opts.mail)
	f.mail:SetShown(ns.Inventory == nil or ns.Inventory.READ_MAIL)
	local result = S():Compute()
	View.result = result
	local rows = result.rows
	if View.search and View.search ~= "" then   -- the panel's search filters the materials too
		local needle, keep = View.search:lower(), {}
		for _, r in ipairs(rows) do if r.name:lower():find(needle, 1, true) then keep[#keep + 1] = r end end
		rows = keep
	end
	f.mats:SetData(rows, true)
	local last = {}
	for _, r in ipairs(result.rows) do last[r.item] = r.missing end
	View.lastMissing = last
	f.summary:SetText(View.SummaryText(result))
	f.status:SetText(View.status or L["SHOP_HINT"])
	Theme.Text(f.status, View.status and View.statusToken or "text-3")
	local missing = result.missingRows > 0
	f.askGuild:SetEnabled(missing and ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil)
	f.askBank:SetEnabled(missing and ns.GuildKey ~= nil and ns.GuildKey:Current() ~= nil)
end

function View:SetSearch(text)
	text = type(text) == "string" and text or ""
	if text == (View.search or "") then return end
	View.search = text
	if self.frame then self:Refresh() end
end

if ns.addon then
	ns.addon.ShoppingView = View
	if ns.Bus then
		ns.Bus:On("SHOPPING_CHANGED", function()
			if View.frame and View.frame:IsVisible() then View:Refresh() end
		end)
		ns.Bus:On("GUILD_CHANGED", function() View.status, View.statusToken, View.plan = nil, nil, nil end)
	end
end

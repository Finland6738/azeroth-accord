-- The views under Material 3 (M12.8, docs/specs/ui-style.md §9): every view, page and dialog of the invented guild of
-- demo mode, with every feature switch on, shows at most one filled button, and its buttons, filter chips and text
-- fields have the heights of §9.5 and §9.6.
local function A() return AzerothAccord end

-- Every shown frame under `frame`, itself included.
local function walk(frame, visit)
	if not frame:IsShown() then return end
	visit(frame)
	for _, child in ipairs({ frame:GetChildren() }) do walk(child, visit) end
end

-- Checks what shows under `frame` and adds what was seen to `seen`.
local function check(frame, where, seen)
	local W = A().Widgets
	local filled = {}
	walk(frame, function(f)
		if f.kind and W.BUTTON_KINDS[f.kind] and f.label then
			seen.buttons = seen.buttons + 1
			local h = f:GetHeight()
			truthy(h == W.HEIGHT.button or h == W.HEIGHT.dense or h == W.HEIGHT.small,
				where .. ": button " .. tostring(f:GetLabel()) .. " is " .. h .. " high")
			if f.kind == "filled" then filled[#filled + 1] = tostring(f:GetLabel()) end
		elseif f.IsSelected and f.check and f.ring then
			seen.chips = seen.chips + 1
			eq(f:GetHeight(), 32, where .. ": chip " .. tostring(f.label:GetText()))
		elseif f.edit and f.focusRing and f.placeholder then
			seen.fields = seen.fields + 1
			local h = f:GetHeight()
			truthy(h == W.HEIGHT.button or h == W.HEIGHT.dense, where .. ": a field is " .. h .. " high")
		end
	end)
	truthy(#filled <= 1, where .. ": more than one filled button: " .. table.concat(filled, ", "))
end

local function newSeen() return { buttons = 0, chips = 0, fields = 0 } end

describe("every view follows ui-style §9", function()
	before_boot(function(M)
		M.features = { season = true, raid = true, actions = true, groups = true, census = true, recruit = true, econ = true }
	end)

	local function demo()
		Mock.Slash("/accord demo")
		Mock.Advance(2)
	end

	local function open(id)
		truthy(A().Shell:OpenView(id), id .. " opens")
		Mock.Advance(2)
		return A().Shell.views[id].frame
	end

	it("each view: one filled button at most, the control heights", function()
		demo()
		local seen = newSeen()
		for _, view in ipairs(A().Shell:ViewList()) do check(open(view.id), view.id, seen) end
		truthy(seen.buttons > 20 and seen.chips > 5 and seen.fields > 5, "the views were walked")
		eq(#Mock.errors, 0)
	end)

	it("each page and mode of the views that have several", function()
		demo()
		local seen = newSeen()
		local function pages(id, list, show)
			local frame = open(id)
			for _, page in ipairs(list()) do
				show(page)
				Mock.Advance(2)
				check(frame, id .. "/" .. page, seen)
			end
		end
		local function ids(defs)
			return function()
				local out = {}
				for key, def in pairs(defs) do out[#out + 1] = type(def) == "table" and def.id or key end
				table.sort(out)
				return out
			end
		end
		pages("events", function() return { "events", "rallies" } end, function(p) A().EventsView:ShowPage(p) end)
		pages("groups", function() return { "list", "form", "mine" } end, function(p) A().GroupsView:ShowPage(p) end)
		pages("actions", ids(A().ActionsView.pages), function(p) A().ActionsView:ShowPage(p) end)
		pages("officers", ids(A().OfficersView.pages), function(p) A().OfficersView:ShowPage(p) end)
		pages("bank", ids(A().BankView.modes), function(p) A().BankView:SetMode(p) end)
		pages("market", ids(A().MarketView.modes), function(p) A().MarketView:SetMode(p) end)
		-- every order selected in turn: the buttons of the bar under the table
		for _, row in ipairs(A().Orders:List()) do
			A().OrdersView:Select(row.id)
			check(open("market"), "market/orders " .. row.id, seen)
		end
		-- and every post of the board (M13.5)
		A().MarketView:SetMode("board")
		for _, row in ipairs(A().Board:List()) do
			A().BoardView:Select(row.id)
			check(open("market"), "market/board " .. row.id, seen)
		end
		pages("professions", function() return { "catalogue", "craft", "shopping" } end, function(p) A().RecipeView:SetMode(p) end)
		pages("reputation", ids(A().ReputationView.modes), function(p) A().ReputationView:SetMode(p) end)
		pages("settings", ids(A().SettingsView.pages), function(p) A().SettingsView:ShowPage(p) end)
		truthy(seen.buttons > 10 and seen.chips > 10, "the pages were walked")
		eq(#Mock.errors, 0)
	end)

	it("each dialog", function()
		demo()
		open("officers")
		local seen = newSeen()
		local me = A().Compat.Player.GUID()
		local dialogs = {
			absence = function() return A().OfficersView:OpenAbsence(me, "Someone") end,
			tiers = function() A().OfficersView:OpenTiers() return A().OfficersView.tiersDialog end,
			review = function() A().OfficersView:OpenReview() return A().OfficersView.reviewDialog end,
			copy = function() return A().CopyBox:Open("QZ", "QZ") end,
			diagnostics = function() A().DiagnosticsBox:Open("QZ") return A().DiagnosticsBox.frame end,
			recruit = function() A().RecruitView:Open() return A().RecruitView.frame end,
			trial = function() return A().TrialsView:OpenStart() end,
			order = function() return A().OrdersView:OpenNew(nil, 2330) end,
			post = function() return A().BoardView:OpenNew() end,
			shopGuild = function() local d = A().ShoppingView:BuildGuildDialog() d:Open() return d end,
			shopBank = function() A().ShoppingView:BankList() return A().ShoppingView.bankDialog end,
			shopClear = function() return A().ShoppingView:ConfirmClear() end,
		}
		for name, show in pairs(dialogs) do
			local d = show()
			notNil(d, name)
			Mock.Advance(1)
			check(d, name, seen)
			d:Hide()
		end
		truthy(seen.buttons >= 10, "the dialogs were walked")
		eq(#Mock.errors, 0)
	end)
end)

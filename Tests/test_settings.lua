-- The options, the Settings view and the game's Settings panel (M6.1; SPEC-04 §4): the notice options, the main
-- character, the Roster columns, the sizes of the saved data, "Clear guild data" and the panel registered in the game's
-- Settings window.
local function A() return AzerothAccord end
local function M() return AzerothAccord.SettingsModel end
local function S() return AzerothAccord.Store end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000C0C"
local LINEN = 2589

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function request(requester, n, status)
	Mock.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
	Mock.items.cached[LINEN] = true
	local id = requester .. ":" .. n
	local rec = { id = id, author = requester, rev = 1, time = GetServerTime(), requester = requester, kind = "withdraw", status = status or "open",
		itemID = LINEN, count = 20, created = GetServerTime(), history = { { s = "open", by = requester, t = GetServerTime() } } }
	if rec.status ~= "open" then rec.author = OFF end
	S():Records("bankreq")[id] = rec
	A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
end

local function open()
	A().Shell:OpenView("settings")
	return A().SettingsView.frame
end

describe("the options", function()
	before_boot(function() guild(3) end)

	it("start at the defaults and are saved in the account settings", function()
		eq(M().Get("notifyOfficer"), true)
		eq(M().Get("notifyDecision"), true)
		truthy(M().IsDefault("notifyOfficer"))
		truthy(M().Set("notifyDecision", false))
		eq(A().Config:Get("account.settings.notifyDecision"), false)
		falsy(M().IsDefault("notifyDecision"))
		truthy(M().Set("notifyDecision", true))
		truthy(M().IsDefault("notifyDecision"))
	end)

	it("refuse an unknown option and a value that is not a boolean, and announce a change on the Bus", function()
		local heard = {}
		A().Bus:On("SETTINGS_CHANGED", function(key) heard[#heard + 1] = key end)
		local ok, why = M().Set("nothing", true)
		falsy(ok); eq(why, "unknown")
		ok, why = M().Set("notifyOfficer", "yes")
		falsy(ok); eq(why, "expected boolean")
		eq(#heard, 0)
		M().Set("notifyOfficer", false)
		deepEq(heard, { "notifyOfficer" })
	end)

	it("a damaged saved value is its default again, and read-only saved data refuses a change", function()
		A().Config.db.account.settings.notifyOfficer = "garbage"
		eq(M().Get("notifyOfficer"), true)
		A().Config.readOnly.account = true
		local ok, why = M().Set("notifyOfficer", false)
		falsy(ok); eq(why, "read-only")
	end)

	it("survive a /reload, and are sanitized when damaged in the file", function()
		M().Set("notifyDecision", false)
		Mock.Reload()
		eq(M().Get("notifyDecision"), false)
		A().Config.db.account.settings.notifyOfficer = 7
		Mock.Reload()
		eq(M().Get("notifyOfficer"), true)
		eq(A().Config:Get("account.settings.notifyOfficer"), true, "the damaged value was reset, not just ignored")
	end)

	it("the officer option is for officers only", function()
		falsy(M().Visible("notifyOfficer"))
		truthy(M().Visible("notifyDecision"))
		guild(1)
		A().Role:Refresh()
		truthy(M().Visible("notifyOfficer"))
		falsy(M().Visible("nothing"))
	end)
end)

describe("the notices follow the options", function()
	before_boot(function() guild(1) end)

	it("an officer hears a new request, unless the option is off", function()
		request(BOB, 1)
		Mock.Advance(A().BankInbox.NOTICE_WAIT + 1)
		contains(text(), "New bank request from")
		Mock.ClearOutput()
		M().Set("notifyOfficer", false)
		request(BOB, 2)
		Mock.Advance(A().BankInbox.NOTICE_WAIT + 1)
		falsy(text():find("New bank request", 1, true))
		eq(A().BankInbox.PendingCount(), 2, "the counter still counts what waits")
	end)

	it("the requester hears a decision, unless the option is off", function()
		request(ME, 1)
		request(ME, 1, "approved")
		Mock.Advance(A().BankInbox.NOTICE_WAIT + 1)
		contains(text(), "was approved")
		Mock.ClearOutput()
		M().Set("notifyDecision", false)
		request(ME, 2)
		request(ME, 2, "rejected")
		Mock.Advance(A().BankInbox.NOTICE_WAIT + 1)
		falsy(text():find("rejected", 1, true))
	end)
end)

describe("the Settings view", function()
	before_boot(function() guild(3) end)

	it("is a view of the panel, last in the navigation, and shows every card", function()
		local f = open()
		notNil(f)
		matches(f.mainTitle:GetText(), "Main character")
		matches(f.noticeTitle:GetText(), "Notifications")
		matches(f.columnsTitle:GetText(), "Roster columns")
		matches(f.dataTitle:GetText(), "Saved data")
		eq(A().Shell:ViewList()[#A().Shell:ViewList()].id, "settings")
		eq(#Mock.errors, 0)
	end)

	it("the notice switches follow the saved options, and a click saves", function()
		local f = open()
		falsy(f.checks.notifyOfficer:IsShown(), "a member has no officer notice")
		truthy(f.checks.notifyDecision:IsShown())
		truthy(f.checks.notifyDecision:GetChecked())
		f.checks.notifyDecision:Click()
		eq(A().Config:Get("account.settings.notifyDecision"), false)
		falsy(f.checks.notifyDecision:GetChecked())
		M().Set("notifyDecision", true)
		truthy(f.checks.notifyDecision:GetChecked(), "a change from elsewhere shows at once")
	end)

	it("an officer sees the officer notice", function()
		guild(1)
		A().Role:Refresh()
		local f = open()
		truthy(f.checks.notifyOfficer:IsShown())
	end)

	it("scrolls with the mouse wheel, never above the top or below the bottom", function()
		local f = open()
		f:SetSize(500, 400)
		f.scroll:SetSize(500, 400)
		Mock.RunScript(f.scroll, "OnMouseWheel", -1)
		eq(f.scroll:GetVerticalScroll(), A().SettingsView.WHEEL_STEP)
		Mock.RunScript(f.scroll, "OnMouseWheel", 1)
		Mock.RunScript(f.scroll, "OnMouseWheel", 1)
		eq(f.scroll:GetVerticalScroll(), 0)
		for _ = 1, 100 do Mock.RunScript(f.scroll, "OnMouseWheel", -1) end
		eq(f.scroll:GetVerticalScroll(), f.pageHeight - 400)
	end)
end)

describe("the Appearance card (M6.14)", function()
	before_boot(function() guild(3) end)

	local function Th() return AzerothAccord.Theme end

	it("is the first card and shows the saved look: Nebula, effects and animations on, Accord's fonts", function()
		local f = open()
		eq(f.cards[1], f.lookCard)
		eq(f.lookTitle:GetText(), "Appearance")
		eq(f.theme.seg:Active(), "nebula")
		eq(f.font.seg:Active(), "addon")
		truthy(f.effects:GetChecked()); truthy(f.animations:GetChecked())
		local labels = {}
		for _, id in ipairs(f.theme.seg.order) do labels[#labels + 1] = f.theme.seg.buttons[id].label:GetText() end
		deepEq(labels, { "Nebula", "Aurora", "Accord" })
	end)

	it("a theme chosen on the card is saved for the account, applied at once and announced as SETTINGS_CHANGED", function()
		local f = open()
		local heard = {}
		A().Bus:On("SETTINGS_CHANGED", function(key) heard[#heard + 1] = key end)
		f.theme.seg.buttons.aurora:Click()
		eq(A().Config:Get("account.settings.theme"), "aurora")
		eq(Th().Current(), "aurora")
		deepEq(heard, { "theme" })
		eq((f.lookTitle:GetTextColor()), (Th().Color("text-1", "aurora")), "the page itself is repainted")
		f.theme.seg.buttons.accord:Click()
		eq(Th().Current(), "accord")
		Mock.Reload()
		eq(A().Theme.Current(), "accord", "kept after /reload")
	end)

	it("the switches save the neon effects and the animations", function()
		local f = open()
		local heard = {}
		A().Bus:On("SETTINGS_CHANGED", function(key) heard[#heard + 1] = key end)
		f.effects:Click()
		eq(A().Config:Get("account.settings.effects"), false)
		falsy(Th().EffectsOn())
		f.animations:Click()
		eq(A().Config:Get("account.settings.animations"), false)
		falsy(Th().AnimationsOn())
		deepEq(heard, { "effects", "animations" })
		f.effects:Click()
		truthy(Th().EffectsOn())
	end)

	it("the game font replaces the addon's fonts at once", function()
		local f = open()
		f.font.seg.buttons.game:Click()
		eq(A().Config:Get("account.settings.font"), "game")
		eq(M().GetLook("font"), "game")
		for id, status in pairs(Th().fontStatus) do eq(status, "game", id) end
	end)

	it("a value from elsewhere shows on every page, and wrong values are refused", function()
		local f = open()
		truthy(M().SetLook("theme", "aurora"))
		eq(f.theme.seg:Active(), "aurora")
		truthy(M().SetLook("animations", false))
		falsy(f.animations:GetChecked())
		local ok, why = M().SetLook("theme", "pink")
		falsy(ok); eq(why, "bad value")
		ok, why = M().SetLook("effects", "yes")
		falsy(ok); eq(why, "bad value")
		ok, why = M().SetLook("size", 3)
		falsy(ok); eq(why, "unknown")
		A().Config.db.account.settings.theme = "garbage"
		eq(M().GetLook("theme"), "nebula", "a damaged value reads as its default")
	end)

	it("read-only saved data refuses the change, says so and keeps the shown value", function()
		local f = open()
		A().Config.readOnly.account = true
		f.theme.seg.buttons.aurora:Click()
		eq(Th().Current(), "nebula")
		eq(f.theme.seg:Active(), "nebula")
		matches(f.lookStatus:GetText(), "^The change could not be saved %(read%-only%)")
		eq(#Mock.errors, 0)
	end)
end)

describe("the main character", function()
	before_boot(function() guild(3) end)

	local function second()
		A().Accounts:RegisterSelf()
		A().Accounts:Register{ guid = "Player-1-0000A002", name = "Otherchar", realm = A().Compat.Player.Realm(), classID = 8, level = 70,
			guild = A().GuildKey:Current() }
	end

	it("lists the characters of the account and says which is the main", function()
		second()
		local choices = M().MainChoices()
		eq(#choices, 2)
		local main
		for _, c in ipairs(choices) do if c.isMain then main = c end end
		notNil(main)
		eq(main.name, "Otherchar", "the highest level leads until the player chooses")
	end)

	it("a click on the menu makes a character the main and says so", function()
		second()
		local f = open()
		matches(f.main:GetText(), "^Main: Otherchar %(level 70%)")
		A().SettingsView:ChooseMain(f, f.mainChoose)
		local menu = A().Widgets.Menu.frame
		truthy(menu:IsShown())
		local picked
		for i, it in ipairs(menu.items) do
			if it.text:find("Testchar", 1, true) then picked = it end
		end
		notNil(picked)
		picked.onClick(picked)
		eq(A().Accounts:Main(), ME)
		matches(f.main:GetText(), "^Main: Testchar")
		eq(f.mainStatus:GetText(), "Testchar is now your main.")
	end)

	it("with a single character there is nothing to choose", function()
		A().Accounts:RegisterSelf()
		local f = open()
		falsy(f.mainChoose._enabled)
	end)

	it("read-only saved data says so", function()
		second()
		local f = open()
		A().Config.readOnly.account = true
		A().SettingsView:ChooseMain(f, f.mainChoose)
		local menu = A().Widgets.Menu.frame
		for _, it in ipairs(menu.items) do
			if it.text:find("Testchar", 1, true) then it.onClick(it) end
		end
		eq(f.mainStatus:GetText(), "The main could not be changed (the saved data is read-only).")
	end)
end)

describe("the Roster columns", function()
	before_boot(function() guild(3) end)

	it("are listed once the Roster exists, and a click saves the choice for the character", function()
		local f = open()
		truthy(#f.columnChoices > 0)
		local before = #A().RosterView:Model():VisibleColumns()
		local zone
		for i, c in ipairs(f.columnChoices) do if c.id == "zone" then zone = i end end
		notNil(zone)
		truthy(f.columnChecks[zone]:IsSelected())
		f.columnChecks[zone]:Click()
		local now = A().Config:Get("char.ui.columns")
		for _, id in ipairs(now) do ne(id, "zone") end
		eq(#now, before - 1)
		falsy(A().RosterView:Model():HasColumn("zone"))
	end)

	it("the name column cannot be switched off, and the default button puts everything back", function()
		local f = open()
		falsy(M().ToggleColumn("name"))
		M().ToggleColumn("zone")
		M().ToggleColumn("level")
		f.columnsReset:Click()
		truthy(A().RosterView:Model():HasColumn("zone"))
		truthy(A().RosterView:Model():HasColumn("level"))
	end)
end)

describe("the sizes of the saved data", function()
	before_boot(function() guild(3) end)

	it("formats a size", function()
		eq(M().FormatBytes(0), "0 B")
		eq(M().FormatBytes(512), "512 B")
		eq(M().FormatBytes(2048), "2.0 KB")
		eq(M().FormatBytes(3 * 1024 * 1024), "3.0 MB")
	end)

	it("counts the account, the character, the guild and each data set", function()
		request(BOB, 1)
		local s = M().Sizes()
		truthy(s.account > 0)
		truthy(s.char > 0)
		eq(s.guilds, 1)
		truthy(s.guild > 0)
		local found
		for _, p in ipairs(s.parts) do if p.name == "bankreq" then found = p end end
		notNil(found)
		eq(found.records, 1)
		truthy(found.bytes > 0)
		for i = 2, #s.parts do truthy(s.parts[i - 1].bytes >= s.parts[i].bytes, "biggest first") end
	end)

	it("shows the lines on the page without the name of the guild or of a player", function()
		request(BOB, 1)
		local f = open()
		local lines = {}
		for _, fs in ipairs(f.sizes) do if fs:IsShown() then lines[#lines + 1] = fs:GetText() end end
		matches(lines[1], "^Account: ")
		matches(lines[2], "^This character: ")
		matches(lines[3], "^This guild: ")
		local all = table.concat(lines, "\n")
		matches(all, "bankreq: .* %(1 records%)")
		falsy(all:find("Accord", 1, true), "no guild name")
		falsy(all:find("Bob", 1, true), "no player name")
	end)

	it("says so without a guild", function()
		Mock.guild.Leave()
		A().Role:Refresh()
		local lines = A().SettingsView.SizeLines()
		eq(lines[#lines], "You are not in a guild.")
	end)

	it("/accord debug lists the options", function()
		M().Set("notifyDecision", false)
		Mock.Slash("/accord debug")
		contains(A().DiagnosticsBox:GetText(), "notifyDecision=false (changed)")
		contains(A().DiagnosticsBox:GetText(), "game panel: ")
	end)
end)

describe("Clear guild data", function()
	before_boot(function() guild(3) end)

	local function fill()
		request(BOB, 1)
		local data = A().GuildKey:Data()
		data.salts = { abc = { k = "c2FsdA==", at = 1 } }
		data.likes = { given = { [BOB] = true }, queue = {} }
		data.bank = { seen = { x = "open" } }
		return data
	end

	it("forgets the guild's records but keeps the notary's salts, the likes memory, the account and the settings", function()
		local data = fill()
		M().Set("notifyDecision", false)
		local token = A().Config:Token()
		local freed = M().ClearGuildData()
		truthy(freed > 0)
		eq(S():Count("bankreq"), 0)
		eq(A().GuildKey:Data().bank.seen.x, "open", "the bank notices already shown are kept")
		notNil(A().GuildKey:Data().salts.abc)
		eq(A().GuildKey:Data().likes.given[BOB], true)
		eq(A().Config:Token(), token)
		eq(A().Config:Get("account.settings.notifyDecision"), false)
		notNil(A().Config:Get("char.ui"))
		notNil(data.firstSeen)
	end)

	it("announces the guild again so the modules reset and the guild resends", function()
		fill()
		local changes = {}
		A().Bus:On("GUILD_CHANGED", function(key, old) changes[#changes + 1] = { key, old } end)
		M().ClearGuildData()
		eq(#changes, 1)
		eq(changes[1][1], changes[1][2])
		notNil(changes[1][1])
	end)

	it("the button needs two clicks, and the first one says how much will go", function()
		fill()
		local f = open()
		local View = A().SettingsView
		eq(View:Clear(f), "armed")
		matches(f.clear.label and f.clear.label:GetText() or f.clear:GetText(), "^Click again to clear %(")
		eq(S():Count("bankreq"), 1, "nothing is cleared by the first click")
		eq(View:Clear(f), "cleared")
		eq(S():Count("bankreq"), 0)
		matches(f.clearStatus:GetText(), "^Cleared .*Guildmates will send their data again%.$")
		matches(f.clear.label and f.clear.label:GetText() or f.clear:GetText(), "^Clear guild data$")
	end)

	it("the first click is taken back after a few seconds", function()
		fill()
		local f = open()
		local View = A().SettingsView
		View:Clear(f)
		Mock.Advance(View.CONFIRM_SECONDS + 1)
		eq(View:Clear(f), "armed", "a late second click only arms it again")
		eq(S():Count("bankreq"), 1)
	end)

	it("is refused for read-only saved data and without a guild", function()
		fill()
		A().Config.readOnly.account = true
		local ok, why = M().ClearGuildData()
		falsy(ok); eq(why, "read-only")
		eq(S():Count("bankreq"), 1)
		A().Config.readOnly.account = nil
		local freed, why2 = A().GuildKey:Clear("Nowhere/Nothing")
		eq(freed, 0, "a guild with no data has nothing to free")
		freed, why2 = A().GuildKey:Clear(nil)
		notNil(freed)
	end)

	it("never touches another guild's data", function()
		fill()
		A().Config.db.account.guilds["Realm/Other"] = { firstSeen = 1, store = { sets = { bankreq = { x = { id = "x" } } } } }
		M().ClearGuildData()
		notNil(A().Config.db.account.guilds["Realm/Other"].store.sets.bankreq.x)
	end)
end)

describe("the panel in the game's Settings window", function()
	local registered

	before_boot(function()
		guild(3)
		registered = {}
		Settings = {
			RegisterCanvasLayoutCategory = function(frame, name)
				registered.frame, registered.name = frame, name
				return { GetID = function() return 77 end, ID = 77 }
			end,
			RegisterAddOnCategory = function(category) registered.category = category end,
			OpenToCategory = function(id) registered.opened = id end,
		}
	end)

	it("is registered at login with the addon's name, and the page is built when it is first shown", function()
		eq(registered.name, "Azeroth Accord")
		notNil(registered.frame)
		eq(registered.frame:GetName(), "AzerothAccordSettingsPanel")
		isNil(A().SettingsView.panelFrame, "nothing is built before the panel is shown")
		registered.frame:Show()
		notNil(A().SettingsView.panelFrame)
		notNil(A().SettingsView.panelFrame.discordEdit)
		eq(M().panelStatus, "registered")
	end)

	it("opens the game's Settings window on its category", function()
		truthy(M().OpenPanel())
		eq(registered.opened, 77)
	end)

	it("shows the same options as the panel's view, and a change in one shows in the other", function()
		registered.frame:Show()
		local panel = A().SettingsView.panelFrame
		local view = open()
		M().Set("notifyDecision", false)
		falsy(panel.checks.notifyDecision:GetChecked())
		falsy(view.checks.notifyDecision:GetChecked())
		panel.checks.notifyDecision:Click()
		truthy(view.checks.notifyDecision:GetChecked())
		eq(#Mock.errors, 0)
	end)

	it("the Defaults button of the Settings window does nothing harmful", function()
		M().Set("notifyDecision", false)
		registered.frame.default()
		eq(M().Get("notifyDecision"), false)
	end)
end)

describe("a client without the Settings API, or one that raises", function()
	before_boot(function() guild(3) end)

	it("has no panel and says so in /accord debug, without an error", function()
		eq(M().panelStatus, "unavailable")
		falsy(M().OpenPanel())
		eq(#Mock.errors, 0)
	end)

	it("a registration that raises is caught", function()
		M().category = nil
		local ok, why = M().RegisterPanel(function() error("boom") end, {
			RegisterCanvasLayoutCategory = function() end, RegisterAddOnCategory = function() end })
		falsy(ok); eq(why, "failed")
		eq(M().panelStatus, "failed")
	end)
end)

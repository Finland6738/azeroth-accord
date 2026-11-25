-- Quiet hours (M9.4; SPEC-13 §4): notices are held during combat, in instances and in the player's quiet hours (also
-- across midnight), they are in the history at once, and come out once, in order, when nothing holds any more. With the
-- switch `actions` off nothing is held: the bank notices of M5 come out as released.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Notify() return AzerothAccord.Notify end
local function M() return AzerothAccord.SettingsModel end
local function Toast() return AzerothAccord.Toast end
local function text() return table.concat(Mock.PlainOutput(), "\n") end

local ME, BOB, OFF = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000C0C"
local LINEN = 2589
local HOUR = 3600
local MIDNIGHT = 1767225600   -- 2026-01-01 00:00:00, the computer's clock of the mock

local function guild()
	Mock.guild.Set{ name = "Accord", myRank = 1, members = {
		{ name = "Bob", level = 60, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF },
	} }
end

local function items(Mk)
	Mk.items.info[LINEN] = { name = "Linen Cloth", quality = 1, icon = 132889 }
	Mk.items.cached[LINEN] = true
end

local function on(Mk) Mk.features = { actions = true } guild() items(Mk) end
local function off(Mk) Mk.features = { actions = false } guild() items(Mk) end

local function late() Mock.Advance(Notify().LOGIN_MAX + 5) end
local function wait() Mock.Advance(Notify().NOTICE_WAIT + 1) end

-- The computer's clock shows hour:minute (no timer runs).
local function clockAt(hour, minute) Mock.SetServerTime(MIDNIGHT + 10 * 86400 + hour * HOUR + (minute or 0) * 60) end

local function fight()
	Mock.world.inCombat = true
	Mock.Fire("PLAYER_REGEN_DISABLED")
end
local function peace()
	Mock.world.inCombat = false
	Mock.Fire("PLAYER_REGEN_ENABLED")
end
local function enter(kind)
	Mock.world.inInstance, Mock.world.instanceType = true, kind or "party"
	Mock.Fire("PLAYER_ENTERING_WORLD", false, false)
end
local function leave()
	Mock.world.inInstance, Mock.world.instanceType = false, nil
	Mock.Fire("PLAYER_ENTERING_WORLD", false, false)
end

-- A module of the test, with the outputs asked for.
local function module(id, outputs)
	truthy(Notify():Register(id, { label = "ACT_PROVIDER_BANK", order = 90, kinds = {
		{ id = "x", level = "normal", group = "NOTICE_BANK_OFFICER_MANY" },
		{ id = "now", level = "alert", group = "NOTICE_BANK_OFFICER_MANY" },
	} }))
	local o = { chat = true, toast = false, sound = false, off = {} }
	for k, v in pairs(outputs or {}) do o[k] = v end
	A().Config.db.account.settings.notify[id] = o
end

local function post(n, extra, kind)
	local def = { key = "n" .. n, text = "BANKNOTE_NEW", args = { "N" .. n, "thing" } }
	for k, v in pairs(extra or {}) do def[k] = v end
	return Notify():Post("t", kind or "x", def)
end

-- The notices printed, in order: "1,2,3".
local function printed()
	local out = {}
	for _, line in ipairs(Mock.PlainOutput()) do
		local n = line:match("New bank request from N(%d+)")
		if n then out[#out + 1] = n end
	end
	return table.concat(out, ",")
end

local function count(pattern)
	local n = 0
	for _, line in ipairs(Mock.PlainOutput()) do
		if line:find(pattern, 1, true) then n = n + 1 end
	end
	return n
end

describe("held in combat", function()
	before_boot(on)

	it("come out once, in order, 3 seconds after the fight, and are in the history at once", function()
		late()
		module("t")
		fight()
		post(1)
		Mock.Advance(5)
		post(2)
		Mock.Advance(30)
		post(3)
		wait()
		eq(printed(), "")
		eq(Notify():Unread(), 3, "QUI-02")
		eq(Notify():Holding(), "combat")
		contains(A().Diagnostics.Report(), "held by combat")
		peace()
		Mock.Advance(Notify().RELEASE_COMBAT - 1)
		eq(printed(), "")
		Mock.Advance(2)
		eq(printed(), "1,2,3")
		Mock.Advance(600)
		fight()
		peace()
		Mock.Advance(600)
		eq(printed(), "1,2,3", "once")
		eq(#Notify():Entries(), 3)
		eq(#Mock.errors, 0)
	end)

	it("a notice posted just before the fight waits too", function()
		late()
		module("t")
		post(1)
		Mock.Advance(1)
		fight()
		wait()
		eq(printed(), "")
		peace()
		Mock.Advance(10)
		eq(printed(), "1")
	end)

	it("a new fight inside the 3 seconds holds them on", function()
		late()
		module("t")
		fight()
		post(1)
		wait()
		peace()
		Mock.Advance(1)
		fight()
		Mock.Advance(60)
		post(2)
		wait()
		eq(printed(), "")
		peace()
		Mock.Advance(10)
		eq(printed(), "1,2")
	end)

	it("one burst: three lines and the rest counted, one toast (the last alert), one sound", function()
		late()
		module("t", { toast = true, sound = true })
		fight()
		post(1)
		post(2, nil, "now")
		post(3, nil, "now")
		post(4)
		post(5)
		Mock.Advance(20)
		isNil(Toast().frame, "nothing pops up")
		eq(#Mock.sounds, 0)
		peace()
		Mock.Advance(5)
		eq(printed(), "1,2,3")
		contains(text(), "and 2 more")
		contains(Toast().frame.text:GetText(), "N3")
		eq(#Toast().queue, 0)
		eq(#Mock.sounds, 1)
	end)

	it("a notice read, gone or older than 12 hours stays in the history only", function()
		late()
		module("t")
		fight()
		local read = post(1)
		local there = true
		post(2, { still = function() return there end })
		post(3)
		wait()
		Mock.StepClock(Notify().HELD_MAX + 60)
		post(4)
		local fifth = post(5, { still = function() return false end })
		wait()
		Notify():MarkRead(read)
		there = false
		peace()
		Mock.Advance(10)
		eq(printed(), "4")
		eq(#Notify():Entries(), 5)
		falsy(fifth.read)
	end)

	it("the same notice again while held comes out once, with the last words", function()
		late()
		module("t")
		fight()
		post(1)
		wait()
		post(1, { args = { "N9", "thing" } })
		wait()
		peace()
		Mock.Advance(10)
		eq(printed(), "9")
		eq(#Notify():Entries(), 1)
	end)

	it("a toast waiting behind the one on screen does not pop up in the fight", function()
		late()
		module("t", { chat = false, toast = true })
		post(1)
		post(2)
		wait()
		fight()
		Mock.Advance(Toast().SECONDS + 1)
		falsy(Toast().frame:IsShown())
		post(3)
		Mock.Advance(30)
		falsy(Toast().frame:IsShown())
		peace()
		Mock.Advance(5)
		contains(Toast().frame.text:GetText(), "N2")
		Mock.Advance(Toast().SECONDS)
		contains(Toast().frame.text:GetText(), "N3")
		Mock.Advance(Toast().SECONDS)
		falsy(Toast().frame:IsShown())
	end)

	it("the grouped notices of the login window are held as well", function()
		module("t")
		fight()
		post(1)
		post(2)
		Mock.Advance(Notify().LOGIN_MAX + 30)
		eq(count("2 new bank requests"), 0)
		peace()
		Mock.Advance(10)
		eq(count("2 new bank requests"), 1)
	end)
end)

describe("held in an instance", function()
	before_boot(on)

	it("come out once, in order, 5 seconds after leaving, in every kind of instance", function()
		late()
		module("t")
		local n = 0
		for _, kind in ipairs({ "party", "raid", "pvp", "arena", "scenario" }) do
			Mock.ClearOutput()
			enter(kind)
			post(n + 1)
			post(n + 2)
			Mock.Advance(120)
			eq(printed(), "", kind)
			leave()
			Mock.Advance(Notify().RELEASE_INSTANCE - 1)
			eq(printed(), "", kind)
			Mock.Advance(2)
			eq(printed(), (n + 1) .. "," .. (n + 2), kind)
			n = n + 2
		end
	end)

	it("also when only the area change says so, and a fight inside releases nothing", function()
		late()
		module("t")
		enter("raid")
		fight()
		post(1)
		wait()
		peace()
		Mock.Advance(60)
		eq(printed(), "")
		Mock.world.inInstance = false
		Mock.Fire("ZONE_CHANGED_NEW_AREA")
		Mock.Advance(6)
		eq(printed(), "1")
	end)

	it("the switch for instances off lets them out inside, at once when it is turned off", function()
		late()
		module("t")
		enter()
		post(1)
		wait()
		eq(printed(), "")
		truthy(M().SetQuiet("instances", false))
		eq(printed(), "1")
		post(2)
		wait()
		eq(printed(), "1,2")
		fight()
		post(3)
		wait()
		eq(printed(), "1,2", "combat always holds")
	end)
end)

describe("held in the quiet hours", function()
	before_boot(on)

	local function hours(from, to)
		A().Config.db.account.settings.quiet = { on = true, from = from, to = to, instances = true }
	end

	it("are off by default, from 23 to 8", function()
		deepEq(A().Config:Get("account.settings.quiet"), { on = false, from = 23, to = 8, instances = true })
		late()
		module("t")
		clockAt(2)
		post(1)
		wait()
		eq(printed(), "1")
	end)

	it("a window across midnight holds from 23:00 to 7:59 and releases once, in order", function()
		late()
		module("t")
		M().SetQuiet("on", true)
		clockAt(22, 58)
		post(1)
		wait()
		eq(printed(), "1")
		clockAt(23)
		post(2)
		wait()
		clockAt(23, 59)
		Mock.Advance(120)   -- over midnight
		post(3)
		wait()
		clockAt(7, 55)
		post(4)
		Mock.Advance(3 * 60)
		eq(printed(), "1")
		eq(Notify():Holding(), "hours")
		Mock.Advance(3 * 60)   -- past 8:00: the check of every minute
		eq(printed(), "1,2,3,4")
		Mock.Advance(600)
		eq(printed(), "1,2,3,4")
		eq(#Notify():Entries(), 4)
	end)

	it("a window inside one day holds from its start to the hour before its end", function()
		local F = Notify().InHours
		falsy(F(11, 12, 14)); truthy(F(12, 12, 14)); truthy(F(13, 12, 14)); falsy(F(14, 12, 14))
		falsy(F(22, 23, 8)); truthy(F(23, 23, 8)); truthy(F(0, 23, 8)); truthy(F(7, 23, 8)); falsy(F(8, 23, 8))
		late()
		module("t")
		hours(12, 14)
		clockAt(13)
		post(1)
		wait()
		eq(printed(), "")
		clockAt(13, 59)
		Mock.Advance(120)
		eq(printed(), "1")
	end)

	it("a fight at the end of the hours holds them until it ends", function()
		late()
		module("t")
		hours(23, 8)
		clockAt(7, 58)
		post(1)
		wait()
		fight()
		Mock.Advance(5 * 60)
		eq(printed(), "")
		peace()
		Mock.Advance(5)
		eq(printed(), "1")
	end)

	it("turning them off lets the held ones out at once; a notice after the end goes with them, in order", function()
		late()
		module("t")
		hours(23, 8)
		clockAt(1)
		post(1)
		wait()
		M().SetQuiet("on", false)
		eq(printed(), "1")
		M().SetQuiet("on", true)
		post(2)
		wait()
		Mock.StepClock(7 * HOUR)
		post(3)
		wait()
		eq(printed(), "1,2,3")
	end)

	it("a login inside them holds the grouped notices", function()
		hours(23, 8)
		clockAt(3)
		module("t")
		post(1)
		Mock.Advance(Notify().LOGIN_MAX + 30)
		eq(printed(), "")
		clockAt(8)
		Mock.Advance(Notify().TICK + 1)
		eq(printed(), "1")
	end)

	it("a muted notice stays silent after the hours, and Clear drops what waits", function()
		late()
		module("t")
		hours(23, 8)
		clockAt(1)
		A().Config.db.account.settings.notify.t.chat = false
		post(1)
		A().Config.db.account.settings.notify.t.chat = true
		post(2)
		wait()
		Notify():Clear()
		post(3)
		wait()
		M().SetQuiet("on", false)
		eq(printed(), "3")
	end)
end)

describe("the settings of the quiet hours", function()
	before_boot(on)

	it("the card offers them, saved per account, and the two ends never meet", function()
		Mock.Slash("/accord settings")
		local q = A().SettingsView.frame.quiet
		for _, key in ipairs({ "head", "on", "from", "to", "instances" }) do truthy(q[key]:IsShown(), key) end
		falsy(q.on:GetChecked())
		truthy(q.instances:GetChecked())
		eq(q.from.select:Selected(), 23)
		eq(q.to.select:Selected(), 8)
		eq(#q.from.select.choices, 23)
		q.on:Click()
		eq(A().Config:Get("account.settings.quiet.on"), true)
		truthy(q.from.select:Select(21))
		eq(A().Config:Get("account.settings.quiet.from"), 21)
		falsy(q.to.select:Select(21), "the start is not offered as the end")
		local ok, why = M().SetQuiet("to", 21)
		falsy(ok)
		eq(why, "same")
		falsy(M().SetQuiet("to", 24))
		falsy(M().SetQuiet("from", 7.5))
		eq(A().Config:Get("account.settings.quiet.to"), 8)
		eq(#Mock.errors, 0)
	end)

	it("schema 4 adds them; equal or damaged hours go back to the default", function()
		T.boot(function() AzerothAccordDB = { schemaVersion = 3, settings = {} } end)
		deepEq(AzerothAccordDB.settings.quiet, { on = false, from = 23, to = 8, instances = true })
		T.boot(function()
			AzerothAccordDB = { schemaVersion = 4, settings = { quiet = { on = true, from = 5, to = 5, instances = false } } }
		end)
		deepEq(AzerothAccordDB.settings.quiet, { on = false, from = 23, to = 8, instances = true })
		T.boot(function()
			AzerothAccordDB = { schemaVersion = 4, settings = { quiet = { on = true, from = "late", to = 23, instances = false } } }
		end)
		deepEq(AzerothAccordDB.settings.quiet, { on = false, from = 23, to = 8, instances = true })
		T.boot(function()
			AzerothAccordDB = { schemaVersion = 4, settings = { quiet = { on = true, from = 20, to = 99, instances = false } } }
		end)
		deepEq(AzerothAccordDB.settings.quiet, { on = true, from = 20, to = 8, instances = false })
	end)
end)

describe("with the switch off, nothing is held", function()
	before_boot(off)

	it("the bank notices of M5 come out in combat, in an instance and in the saved hours, and the card has no quiet hours", function()
		A().Config.db.account.settings.quiet.on = true
		clockAt(2)
		fight()
		enter("raid")
		local t = GetServerTime()
		local id = BOB .. ":1"
		S():Records("bankreq")[id] = { id = id, author = BOB, rev = 1, time = t, requester = BOB, kind = "withdraw", status = "open",
			itemID = LINEN, count = 20, created = t, history = { { s = "open", by = BOB, t = t } } }
		A().Bus:Emit("STORE_CHANGED", "bankreq", id, "remote")
		wait()
		contains(text(), "New bank request from Bob: Linen Cloth x20.")
		isNil(Notify():Holding())
		falsy(Notify():Release())
		isNil(A().GuildKey:Data().notify)
		Mock.Slash("/accord settings")
		local q = A().SettingsView.frame.quiet
		for _, key in ipairs({ "head", "on", "from", "to", "instances" }) do falsy(q[key]:IsShown(), key) end
		eq(#Mock.errors, 0)
	end)
end)

describe("in Italian", function()
	before_boot(function(Mk) Mk.player.locale = "itIT" on(Mk) end)

	it("names the settings in Italian", function()
		Mock.Slash("/accord settings")
		local q = A().SettingsView.frame.quiet
		eq(q.on.label:GetText(), "Ore di quiete")
		eq(q.from.label:GetText(), "Dalle")
		eq(#Mock.errors, 0)
	end)
end)

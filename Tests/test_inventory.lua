-- The inventory of the account (M13.4; SPEC-17 §5.4, §5.5; ECO-05; SPEC-10 Q44): owned = bags + bank + mail of the
-- character and the alts of the same realm and faction, read from the mock client and kept on this computer; the guild
-- bank only in its own field; partial mail and cash on delivery; the read after BAG_UPDATE_DELAYED, never in combat; never
-- in a record or a message; the switch "econ".
local function A() return AzerothAccord end
local function I() return AzerothAccord.Inventory end

local ME, ALT, FAR, ENEMY = "Player-1-0000A001", "Player-1-0000A0A1", "Player-2-0000A0F1", "Player-1-0000A0E1"
local LINEN, SILK, WOOL = 2589, 4306, 2592
local DAY = 86400

local function setup(features)
	return function(M)
		M.features = features or { econ = true }
		M.containers.Set(0, { { LINEN, 10 }, { SILK, 3 } })
		M.containers.Set(1, { { LINEN, 5 } })
		M.containers.Set(6, { { LINEN, 20 } })              -- a bank tab
		M.guild.Set{ name = "Accord", myRank = 3, members = {
			{ name = "Testchar", rank = 3, guid = ME, level = 60, class = "WARRIOR", online = true },
		} }
	end
end

local function owned(item, opts) return I():Count(item, opts).owned end

-- Logs in with another character of the same account (`change` alters the world while out of the game).
local function as(guid, name, fields)
	Mock.Relog(60, function()
		Mock.player.guid, Mock.player.name = guid, name
		for k, v in pairs(fields or {}) do Mock.player[k] = v end
	end)
	Mock.Advance(2)
end

---------------------------------------------------------------------------------------------------------------------
describe("the bags, the bank and an alt (the criterion of M13.4)", function()
	before_boot(setup())

	it("reads the bags at login, the bank only while it is open", function()
		Mock.Advance(2)
		local c = I():Count(LINEN)
		eq(c.bags, 15); eq(c.bank, 0); eq(c.owned, 15)
		isNil(c.ages.bank, "the bank was never read")
		Mock.containers.OpenBank()
		c = I():Count(LINEN)
		eq(c.bank, 20); eq(c.owned, 35)
		truthy(c.ages.bags and c.ages.bank)
		Mock.containers.CloseBank()
		Mock.containers.Set(6, {})
		Mock.containers.Changed()
		Mock.Advance(1)
		eq(owned(LINEN), 35, "the bank stays as last read while closed")
	end)

	it("the bank's single container when no tab has slots", function()
		Mock.containers.bags[6] = nil
		Mock.containers.Set(-2, { { WOOL, 7 } })
		Mock.Advance(2)
		Mock.containers.OpenBank()
		eq(I():Count(WOOL).bank, 7)
	end)

	it("an alt of the same realm and faction counts; another realm or faction does not", function()
		Mock.Advance(2)
		Mock.containers.OpenBank()
		Mock.containers.CloseBank()
		as(ALT, "Altchar")                         -- same realm, same faction
		Mock.containers.Set(0, { { LINEN, 4 } }); Mock.containers.Set(1, {}); Mock.containers.Set(6, {})
		Mock.containers.Changed(); Mock.Advance(1)
		as(FAR, "Farchar", { realm = "Other Realm" })
		Mock.containers.Set(0, { { LINEN, 100 } }); Mock.containers.Changed(); Mock.Advance(1)
		as(ENEMY, "Enemychar", { realm = "Test Realm", faction = "Alliance" })
		Mock.containers.Set(0, { { LINEN, 200 } }); Mock.containers.Changed(); Mock.Advance(1)
		as(ME, "Testchar", { faction = "Horde" })
		Mock.containers.Set(0, { { LINEN, 10 } }); Mock.containers.Set(1, { { LINEN, 5 } })
		Mock.containers.Changed(); Mock.Advance(1)
		local c = I():Count(LINEN)
		eq(c.bags, 15); eq(c.bank, 20)
		eq(c.alts[ALT], 4)
		eq(c.owned, 39, "bags 15 + bank 20 + the alt's 4")
		eq(c.others[ENEMY], 200, "another faction: seen, not counted")
		isNil(c.alts[ENEMY]); isNil(c.alts[FAR]); eq(c.others[FAR], 100, "another realm: seen, not counted")
		eq(owned(LINEN, { alts = false }), 35, "Count alts off")
		eq(I():Characters()[1].guid, ME, "the connected character first")
	end)

	it("the guild bank is only in its own field", function()
		Mock.Advance(2)
		A().BankRequests.BankItems = function() return { [LINEN] = { itemID = LINEN, available = 50, time = GetServerTime() - DAY } } end
		local c = I():Count(LINEN, { guildBank = true })
		eq(c.guildBank, 50); eq(c.owned, 15)
		isNil(I():Count(LINEN).guildBank, "not asked: nil")
	end)

	it("CountMany answers each item once", function()
		Mock.Advance(2)
		local m = I():CountMany({ LINEN, SILK, LINEN, WOOL })
		eq(m[LINEN].owned, 15); eq(m[SILK].owned, 3); eq(m[WOOL].owned, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the mail", function()
	before_boot(setup())

	it("adds the attachments read when the mailbox opens, without cash on delivery", function()
		Mock.mail.messages = {
			{ daysLeft = 20, items = { { LINEN, 5 }, { SILK, 2 } } },
			{ cod = 5000, daysLeft = 3, items = { { LINEN, 100 } } },   -- cash on delivery: not counted
			{ daysLeft = 1, items = {} },
		}
		Mock.Advance(2)
		eq(owned(LINEN), 15, "not read before the mailbox opens")
		Mock.mail.Open()
		local c = I():Count(LINEN)
		eq(c.mail, 5); eq(c.owned, 20)
		eq(owned(LINEN, { mail = false }), 15, "Count mail off")
		Mock.mail.messages[1].items = { { SILK, 2 } }   -- taken out
		Mock.mail.Update()
		eq(owned(LINEN), 15)
		Mock.mail.Close()
	end)

	it("a message that expired between two visits no longer counts", function()
		Mock.mail.messages = { { daysLeft = 1, items = { { LINEN, 5 } } } }
		Mock.Advance(2)
		Mock.mail.Open(); Mock.mail.Close()
		eq(owned(LINEN), 20)
		Mock.Advance(DAY + 3600)
		eq(owned(LINEN), 15)
	end)

	it("says when the game holds more messages than it shows", function()
		Mock.mail.messages = { { items = { { LINEN, 1 } } } }
		Mock.mail.total = 60
		Mock.Advance(2)
		Mock.mail.Open()
		truthy(I():Characters()[1].mailPartial)
		Mock.mail.total = nil
		Mock.mail.Update()
		isNil(I():Characters()[1].mailPartial)
	end)

	it("READ_MAIL off: the part is not read", function()
		I().READ_MAIL = false
		Mock.mail.messages = { { items = { { LINEN, 9 } } } }
		Mock.Advance(2)
		Mock.mail.Open()
		eq(owned(LINEN), 15)
		I().READ_MAIL = true
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("while playing (SPEC-17 §5.5)", function()
	before_boot(setup())

	it("reads the bags once after a burst of BAG_UPDATE_DELAYED, with INVENTORY_CHANGED", function()
		Mock.Advance(2)
		local events = 0
		A().Bus:On("INVENTORY_CHANGED", function(guid) eq(guid, ME) events = events + 1 end)
		local reads = I().state.reads.bags
		Mock.containers.Set(0, { { LINEN, 12 }, { SILK, 3 } })
		for _ = 1, 5 do Mock.containers.Changed() end
		eq(owned(LINEN), 15, "not yet")
		Mock.Advance(1)
		eq(I().state.reads.bags, reads + 1, "one read")
		eq(owned(LINEN), 17)
		eq(events, 1)
		Mock.containers.Changed(); Mock.Advance(1)
		eq(events, 1, "nothing changed: no event")
	end)

	it("waits for the end of combat", function()
		Mock.Advance(2)
		Mock.combat = true
		local lockdown = InCombatLockdown
		InCombatLockdown = function() return true end
		Mock.containers.Set(0, { { LINEN, 1 } })
		Mock.containers.Changed(); Mock.Advance(1)
		eq(owned(LINEN), 15)
		InCombatLockdown = lockdown or function() return false end
		Mock.Fire("PLAYER_REGEN_ENABLED")
		eq(owned(LINEN), 6)
	end)

	it("reads at logout, and the counts survive a /reload", function()
		Mock.Advance(2)
		Mock.containers.Set(0, { { LINEN, 2 } })
		Mock.Reload()
		eq(A().Config.db.account.inventory[A().Compat.Player.RealmKey()][ME].bags[LINEN], 7)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("only on this computer (ECO-05)", function()
	before_boot(setup())

	it("never a record, never a message, never in the backup", function()
		Mock.Advance(2)
		Mock.containers.OpenBank()
		Mock.mail.messages = { { items = { { LINEN, 5 } } } }
		Mock.mail.Open()
		Mock.Advance(5)
		eq(#Mock.chat.sent, 0)
		for set in pairs(A().Store.SETS) do
			for _, rec in pairs(A().Store:Records(set)) do
				isNil(rec.bags); isNil(rec.inventory)
			end
		end
		local text = A().Backup and A().Backup.Export and A().Backup:Export() or ""
		falsy(tostring(text):find("inventory", 1, true), "not in the backup")
	end)

	it("/accord debug gives counts only", function()
		Mock.Advance(2)
		local lines = table.concat(I():DebugLines(), "\n")
		matches(lines, "1 character")
		falsy(lines:find("Testchar", 1, true)); falsy(lines:find(ME, 1, true))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the switch econ off", function()
	before_boot(setup({ econ = false }))

	it("reads nothing", function()
		Mock.Advance(2)
		Mock.containers.OpenBank()
		Mock.mail.Open()
		isNil(A().Config.db.account.inventory)
		eq(I():Count(LINEN).owned, 0)
	end)
end)

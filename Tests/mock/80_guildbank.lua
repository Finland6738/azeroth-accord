-- Mock client, part 10: the guild bank (Accord, M1.3).
--
-- Imitates: C_GuildBank.IsGuildBankEnabled (dump), and the api.json globals GetNumGuildBankTabs, GetGuildBankTabInfo,
-- GetGuildBankItemInfo, GetGuildBankItemLink, GetGuildBankMoney, GetCurrentGuildBankTab, QueryGuildBankTab,
-- QueryGuildBankLog, GetNumGuildBankTransactions, GetGuildBankTransaction, GetNumGuildBankMoneyTransactions,
-- GetGuildBankMoneyTransaction; events GUILDBANKFRAME_OPENED / CLOSED, GUILDBANKBAGSLOTS_CHANGED, GUILDBANKLOG_UPDATE.
-- What is readable while the vault is closed, and the time format of the logs, are M0 check S9 [verify]: here the
-- data is readable only while Mock.bank.isOpen, and log times are years, months, days, hours ago.
--
-- Configure (kept across Mock.Reload):
--   Mock.bank.tabs = { { name = "Tab 1", icon = 133784, viewable = true, deposit = true,
--                        items = { [slot] = { itemID = 2589, count = 20 } },
--                        log = { { "deposit", "Name", 2589, 20, nil, nil, 0, 0, 1, 2 } } }, ... }
--   Mock.bank.money, Mock.bank.moneyLog = { { "deposit", "Name", 10000, 0, 0, 0, 3 } }
--   Mock.bank.Open() / Mock.bank.Close()
local Mock, H = ...
local W = Mock.world

W.bank = W.bank or { tabs = {}, money = 0, moneyLog = {}, isOpen = false, current = 1, enabled = true }
local bank = W.bank
Mock.bank = bank

-- Mock.bank.viaInteraction = true: the client opens and closes the vault only through the interaction manager, as WoW
-- Forever does (found in game, 2026-11-27); otherwise the old GUILDBANKFRAME_* events.
function bank.Open()
	bank.isOpen = true
	if bank.viaInteraction then Mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
	else Mock.Fire("GUILDBANKFRAME_OPENED") end
end

function bank.Close()
	bank.isOpen = false
	if bank.viaInteraction then Mock.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
	else Mock.Fire("GUILDBANKFRAME_CLOSED") end
end

C_GuildBank = { IsGuildBankEnabled = function() return bank.enabled end }

local function tab(i) return bank.isOpen and bank.tabs[i] or nil end

function GetNumGuildBankTabs() return #bank.tabs end
function GetCurrentGuildBankTab() return bank.current end

-- name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals, filtered
function GetGuildBankTabInfo(i)
	local t = bank.tabs[i]
	if not t then return nil end
	return t.name, t.icon, t.viewable ~= false, t.deposit ~= false, 5, 5, false
end

local function link(itemID) return ("|cffffffff|Hitem:%d::::::::60:::::|h[Item %d]|h|r"):format(itemID, itemID) end

-- texture, itemCount, locked, isFiltered, quality
function GetGuildBankItemInfo(i, slot)
	local t = tab(i)
	local item = t and t.viewable ~= false and t.items and t.items[slot]
	if not item then return nil end
	return 133784, item.count or 1, false, false, 1
end

function GetGuildBankItemLink(i, slot)
	local t = tab(i)
	local item = t and t.viewable ~= false and t.items and t.items[slot]
	return item and link(item.itemID) or nil
end

function GetGuildBankMoney() return bank.money end

function QueryGuildBankTab(i)
	bank.current = i
	C_Timer.After(0, function() Mock.Fire("GUILDBANKBAGSLOTS_CHANGED") end)
end

function QueryGuildBankLog(i)
	C_Timer.After(0, function() Mock.Fire("GUILDBANKLOG_UPDATE") end)
end

function GetNumGuildBankTransactions(i)
	local t = tab(i)
	return t and t.log and #t.log or 0
end

-- type, name, itemLink, count, tab1, tab2, year, month, day, hour
function GetGuildBankTransaction(i, index)
	local t = tab(i)
	local e = t and t.log and t.log[index]
	if not e then return nil end
	return e[1], e[2], e[3] and link(e[3]) or nil, e[4], e[5], e[6], e[7], e[8], e[9], e[10]
end

function GetNumGuildBankMoneyTransactions() return bank.isOpen and #bank.moneyLog or 0 end

-- type, name, amount, year, month, day, hour
function GetGuildBankMoneyTransaction(index)
	local e = bank.isOpen and bank.moneyLog[index]
	if not e then return nil end
	return e[1], e[2], e[3], e[4], e[5], e[6], e[7]
end

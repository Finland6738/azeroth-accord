-- Mock client, part 10c: bags, bank and the mailbox (Accord, M13.4; SPEC-17 §5.4).
--
-- Imitates: C_Container.GetContainerNumSlots / GetContainerItemInfo (dump: system Container, ContainerItemInfo with
-- itemID and stackCount), the bank events BANKFRAME_OPENED / BANKFRAME_CLOSED / PLAYERBANKSLOTS_CHANGED, BAG_UPDATE_DELAYED,
-- and the mailbox globals GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem (api.json lists them, without a signature:
-- the classic client's returns are used) with MAIL_SHOW / MAIL_INBOX_UPDATE / MAIL_CLOSED.
--
-- Configure (kept across Mock.Reload):
--   Mock.containers.bags = { [bag index] = { [slot] = { itemID, count } } }   slots: Mock.containers.slots[bag] (default 16
--       for a bag that has a table, 0 otherwise); bank tabs are the indexes 6-14, the account bank 15-23
--   Mock.containers.Set(bag, { { itemID, count }, ... })   fills a bag from slot 1
--   Mock.containers.OpenBank() / CloseBank(), Mock.containers.Changed() (BAG_UPDATE_DELAYED)
--   Mock.mail.messages = { { cod = 0, daysLeft = 30, items = { { itemID, count } } } }, Mock.mail.total (nil = #messages)
--   Mock.mail.Open() / Close() / Update()
local Mock, H = ...
local W = Mock.world

W.containers = W.containers or { bags = {}, slots = {} }
local cont = W.containers
Mock.containers = cont
W.mail = W.mail or { messages = {}, total = nil }
local mail = W.mail
Mock.mail = mail

function cont.Set(bag, list)
	local slots = {}
	for i, it in ipairs(list or {}) do slots[i] = { itemID = it[1], count = it[2] } end
	cont.bags[bag] = slots
end

C_Container = {}
function C_Container.GetContainerNumSlots(bag)
	if cont.slots[bag] then return cont.slots[bag] end
	return cont.bags[bag] and 16 or 0
end
function C_Container.GetContainerItemInfo(bag, slot)
	local it = cont.bags[bag] and cont.bags[bag][slot]
	if not it then return nil end
	return { iconFileID = 134400, stackCount = it.count, isLocked = false, isReadable = false, hasLoot = false,
		hyperlink = ("|Hitem:%d|h[x]|h"):format(it.itemID), isFiltered = false, hasNoValue = false, itemID = it.itemID,
		isBound = false, itemName = "x" }
end

function cont.OpenBank() Mock.Fire("BANKFRAME_OPENED") end
function cont.CloseBank() Mock.Fire("BANKFRAME_CLOSED") end
function cont.Changed() Mock.Fire("BAG_UPDATE_DELAYED") end

function GetInboxNumItems()
	return #mail.messages, mail.total or #mail.messages
end
-- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated,
-- canReply, isGM
function GetInboxHeaderInfo(i)
	local m = mail.messages[i]
	if not m then return nil end
	local has = m.items and #m.items > 0 and #m.items or nil
	return nil, nil, "Sender", "Subject", 0, m.cod or 0, m.daysLeft or 30, has, false, false, false, true, false
end
-- name, itemID, texture, count, quality, canUse
function GetInboxItem(i, a)
	local m = mail.messages[i]
	local it = m and m.items and m.items[a]
	if not it then return nil end
	return "Item", it[1], 134400, it[2], 1, true
end
ATTACHMENTS_MAX_RECEIVE = 16

function mail.Open() Mock.Fire("MAIL_SHOW") Mock.Fire("MAIL_INBOX_UPDATE") end
function mail.Update() Mock.Fire("MAIL_INBOX_UPDATE") end
function mail.Close() Mock.Fire("MAIL_CLOSED") end

-- Inventory: what the characters of this account own, read from the game and kept on this computer only (M13.4;
-- SPEC-17 §5.4, §5.5; ECO-05; SPEC-10 Q44). THE MODULE M17 REUSES (the professions assistant). Lua 5.1.
--
-- Config.db.account.inventory[realm key][GUID] = { name, faction, bags = { [item] = n }, bank = { [item] = n },
--     mail = { { i = item, n, x = server time the message expires } }, bagsAt, bankAt, mailAt, mailPartial }
-- Config.db.account.inventory["*"] = { bank = { [item] = n }, bankAt }: the account bank (Accountbanktab), when the client
--     has one [verify], counted once for every character.
-- Never a record, never sent, never in the backup or a summary; "Delete guild data" (M6.1) leaves it (it belongs to no guild).
--
--   bags   the bags 0-5 (Enum.BagIndex Backpack..ReagentBag): at login, BAG_UPDATE_DELAYED (after DELAY seconds, the
--          burst gathered) and PLAYER_LOGOUT
--   bank   with the bank open (BANKFRAME_OPENED, or the interaction manager's Banker): the character bank tabs 6-14, else
--          the single container -2 [verify]; read again on PLAYERBANKSLOTS_CHANGED and BAG_UPDATE_DELAYED while it is open
--   mail   with the mailbox open (MAIL_SHOW, MAIL_INBOX_UPDATE): the attachments of every message except cash on delivery;
--          `mailPartial` when the game holds more messages than it shows. READ_MAIL = false switches the part off.
--   No read in combat lockdown: it waits for PLAYER_REGEN_ENABLED.
--
--   Inventory:Count(item, opts) -> { owned, bags, bank, mail, account, alts = { [GUID] = n }, others = { [GUID] = n },
--       guildBank, guildBankAt, ages = { bags, bank, mail } }
--       opts = { alts = true, mail = true, guildBank = false } (nil = those defaults). owned = bags + bank + mail of the
--       character + account bank + the alts that count (the same realm and faction: the ones mail can reach); the other
--       alts are in `others` and never in owned; the guild bank (Accord's snapshot, M5) only in its own field.
--   Inventory:CountMany(items, opts) -> { [item] = Count }
--   Inventory:Characters() -> { { guid, name, realm, faction, counts (same realm and faction), own, bagsAt, bankAt,
--       mailAt, mailPartial } }, the connected character first
--   Inventory:ReadBags(), :ReadBank(), :ReadMail()   (the event handlers call them; the tests too)
-- Switch: Core/Features.lua "econ" (off: nothing is read). Bus: INVENTORY_CHANGED(guid) when a part of a character changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Inv = {}
ns.Inventory, ns.modules = Inv, ns.modules or {}
ns.modules.Inventory = Inv

local type, pairs, ipairs, next = type, pairs, ipairs, next

Inv.READ_MAIL = true       -- the one switch of the mail part (SPEC-17 §5.4: off when M13.11 finds it unreliable)
Inv.DELAY = 0.5            -- seconds BAG_UPDATE_DELAYED bursts are gathered
Inv.ACCOUNT_KEY = "*"
-- Enum.PlayerInteractionType when the client has no Enum [verify]: Banker 8, MailInfo 17, AccountBanker 68.
Inv.BANKER, Inv.MAILBOX, Inv.ACCOUNT_BANKER = 8, 17, 68
Inv.EVENTS = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED",
	"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }

local state
local function resetState()
	state = { bankOpen = false, mailOpen = false, pending = {}, timer = false, reads = { bags = 0, bank = 0, mail = 0 },
		epoch = ((state and state.epoch) or 0) + 1 }
	Inv.state = state
end
resetState()

local function compat() return ns.Compat end
local function now() return compat().ServerTime() end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

function Inv.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

---------------------------------------------------------------------------------------------------------------------
-- The saved table
---------------------------------------------------------------------------------------------------------------------
local function root(create)
	local account = ns.Config and ns.Config.db.account
	if not account then return nil end
	if type(account.inventory) ~= "table" then
		if not create then return nil end
		account.inventory = {}
	end
	return account.inventory
end

local function realmKey() return compat().Player.RealmKey() end

-- The entry of the connected character (made when `create`).
local function mine(create)
	local guid = compat().Player.GUID()
	local r = guid and root(create)
	if not r then return nil, guid end
	local key = realmKey()
	if type(r[key]) ~= "table" then
		if not create then return nil, guid end
		r[key] = {}
	end
	local e = r[key][guid]
	if type(e) ~= "table" then
		if not create then return nil, guid end
		e = {}
		r[key][guid] = e
	end
	if create then e.name, e.faction = compat().Player.FullName(), compat().Player.Faction() end
	return e, guid
end

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function sameMail(a, b)
	if type(a) ~= "table" or #a ~= #b then return false end
	for i, m in ipairs(a) do
		local o = b[i]
		if m.i ~= o.i or m.n ~= o.n or m.x ~= o.x then return false end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------------------------------
local function ready()
	if not Inv.Enabled() then return false end
	if ns.Demo ~= nil and ns.Demo:IsActive() then return false end   -- the demo shows invented counts (SPEC-17 §11)
	if compat().InCombat() then return false end
	return true
end

function Inv:ReadBags()
	if not ready() then
		if Inv.Enabled() then state.pending.bags = true end
		return false
	end
	local e, guid = mine(true)
	if not e then return false end
	local counts = compat().Container.Count(compat().Container.BAGS)
	local changed = not same(e.bags, counts)
	e.bags, e.bagsAt = counts, now()
	state.reads.bags = state.reads.bags + 1
	if changed then emit("INVENTORY_CHANGED", guid) end
	return true
end

function Inv:ReadBank()
	if not (state.bankOpen and ready()) then
		if state.bankOpen and Inv.Enabled() then state.pending.bank = true end
		return false
	end
	local e, guid = mine(true)
	if not e then return false end
	local C = compat().Container
	local counts, used = C.Count(C.BANK_TABS)
	if used == 0 then counts = C.Count({ C.BANK }) end
	local changed = not same(e.bank, counts)
	e.bank, e.bankAt = counts, now()
	local shared, sharedUsed = C.Count(C.ACCOUNT_TABS)
	if sharedUsed == 0 then shared, sharedUsed = C.Count({ C.ACCOUNT }) end
	if sharedUsed > 0 then
		local r = root(true)
		local acc = type(r[Inv.ACCOUNT_KEY]) == "table" and r[Inv.ACCOUNT_KEY] or {}
		r[Inv.ACCOUNT_KEY] = acc
		if not same(acc.bank, shared) then changed = true end
		acc.bank, acc.bankAt = shared, now()
	end
	state.reads.bank = state.reads.bank + 1
	if changed then emit("INVENTORY_CHANGED", guid) end
	return true
end

function Inv:ReadMail()
	if not (Inv.READ_MAIL and state.mailOpen and ready()) then
		if Inv.READ_MAIL and state.mailOpen and Inv.Enabled() then state.pending.mail = true end
		return false
	end
	local e, guid = mine(true)
	if not e then return false end
	local M, t = compat().Mail, now()
	local shown, total = M.Count()
	local list, max = {}, M.MaxAttachments()
	for i = 1, shown do
		local h = M.Header(i)
		if h and h.hasItem and h.cod <= 0 then
			local x = h.daysLeft and (t + math.floor(h.daysLeft * 86400)) or nil
			for a = 1, max do
				local id, n = M.Item(i, a)
				if id then list[#list + 1] = { i = id, n = n, x = x } end
			end
		end
	end
	local partial = total > shown or nil
	local changed = not sameMail(e.mail, list) or e.mailPartial ~= partial
	e.mail, e.mailAt, e.mailPartial = list, t, partial
	state.reads.mail = state.reads.mail + 1
	if changed then emit("INVENTORY_CHANGED", guid) end
	return true
end

-- Gathers a burst of BAG_UPDATE_DELAYED: one read DELAY seconds after the last.
local function later()
	if state.timer then return end
	state.timer = true
	local epoch = state.epoch
	local function fire()
		if epoch ~= state.epoch then return end
		state.timer = false
		Inv:ReadBags()
		if state.bankOpen then Inv:ReadBank() end
	end
	if not compat().After(Inv.DELAY, fire) then fire() end
end

local function interaction(kind)
	local enum = type(Enum) == "table" and Enum.PlayerInteractionType or nil
	local banker = type(enum) == "table" and enum.Banker or Inv.BANKER
	local account = type(enum) == "table" and enum.AccountBanker or Inv.ACCOUNT_BANKER
	local mail = type(enum) == "table" and enum.MailInfo or Inv.MAILBOX
	if kind == banker or kind == account then return "bank" end
	if kind == mail then return "mail" end
	return nil
end

function Inv:OnEvent(event, arg)
	if not Inv.Enabled() then return end
	if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE_DELAYED" then
		later()
	elseif event == "PLAYER_LOGOUT" then
		self:ReadBags()
		if state.bankOpen then self:ReadBank() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		local p = state.pending
		state.pending = {}
		if p.bags then self:ReadBags() end
		if p.bank then self:ReadBank() end
		if p.mail then self:ReadMail() end
	elseif event == "BANKFRAME_OPENED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and interaction(arg) == "bank") then
		state.bankOpen = true
		self:ReadBank()
	elseif event == "BANKFRAME_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and interaction(arg) == "bank") then
		if state.bankOpen then self:ReadBank() end
		state.bankOpen = false
	elseif event == "PLAYERBANKSLOTS_CHANGED" then
		self:ReadBank()
	elseif event == "MAIL_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and interaction(arg) == "mail") then
		state.mailOpen = true
		self:ReadMail()
	elseif event == "MAIL_INBOX_UPDATE" then
		self:ReadMail()
	elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and interaction(arg) == "mail") then
		state.mailOpen = false
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------------------------------------------------
local function mailOf(e, item, t)
	local n = 0
	for _, m in ipairs(type(e.mail) == "table" and e.mail or {}) do
		if m.i == item and (not m.x or m.x > t) then n = n + m.n end
	end
	return n
end

local function partOf(e, key, item) return type(e[key]) == "table" and e[key][item] or 0 end

local function defaults(opts)
	opts = opts or {}
	return { alts = opts.alts ~= false, mail = opts.mail ~= false and Inv.READ_MAIL, guildBank = opts.guildBank == true }
end

-- The characters of the account the inventory knows: `counts` says whether their parts may be added (same realm and
-- faction as the connected character).
function Inv:Characters()
	local out = {}
	local r = root(false)
	if not r then return out end
	local myGuid, myRealm, myFaction = compat().Player.GUID(), realmKey(), compat().Player.Faction()
	for realm, chars in pairs(r) do
		if realm ~= Inv.ACCOUNT_KEY and type(chars) == "table" then
			for guid, e in pairs(chars) do
				if type(e) == "table" then
					local own = guid == myGuid
					out[#out + 1] = { guid = guid, name = e.name or "?", realm = realm, faction = e.faction, own = own,
						counts = own or (realm == myRealm and (e.faction == nil or myFaction == nil or e.faction == myFaction)),
						bagsAt = e.bagsAt, bankAt = e.bankAt, mailAt = e.mailAt, mailPartial = e.mailPartial, entry = e }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.own ~= b.own then return a.own end
		if a.counts ~= b.counts then return a.counts end
		if a.name ~= b.name then return a.name < b.name end
		return a.guid < b.guid
	end)
	return out
end

local function countWith(chars, acc, guildItems, item, o, t)
	local out = { owned = 0, bags = 0, bank = 0, mail = 0, account = 0, alts = {}, others = {}, ages = {} }
	for _, c in ipairs(chars) do
		local e = c.entry
		local mail = o.mail and mailOf(e, item, t) or 0
		local n = partOf(e, "bags", item) + partOf(e, "bank", item) + mail
		if c.own then
			out.bags, out.bank, out.mail = partOf(e, "bags", item), partOf(e, "bank", item), mail
			out.ages = { bags = e.bagsAt, bank = e.bankAt, mail = o.mail and e.mailAt or nil }
			out.owned = out.owned + n
		elseif n > 0 then
			if c.counts and o.alts then
				out.alts[c.guid] = n
				out.owned = out.owned + n
			else
				out.others[c.guid] = n
			end
		end
	end
	if acc then
		out.account = partOf(acc, "bank", item)
		out.owned = out.owned + out.account
	end
	if guildItems then
		local held = guildItems[item]
		out.guildBank = held and held.available or 0
		out.guildBankAt = held and held.time or nil
	end
	return out
end

local function guildItems(o)
	if not (o.guildBank and ns.BankRequests and ns.GuildKey and ns.GuildKey:Current()) then return nil end
	return ns.BankRequests:BankItems()
end

local function account()
	local r = root(false)
	local acc = r and r[Inv.ACCOUNT_KEY]
	return type(acc) == "table" and acc or nil
end

function Inv:Count(item, opts)
	local o = defaults(opts)
	return countWith(self:Characters(), account(), guildItems(o), item, o, now())
end

function Inv:CountMany(items, opts)
	local o, out = defaults(opts), {}
	local chars, acc, guild, t = self:Characters(), account(), guildItems(defaults(opts)), now()
	for _, item in ipairs(type(items) == "table" and items or {}) do
		if not out[item] then out[item] = countWith(chars, acc, guild, item, o, t) end
	end
	return out
end

function Inv:Reset() resetState() end

-- Counts only (SPEC-09 §6): never names, GUIDs or items.
function Inv:DebugLines()
	local chars, parts, partial = 0, 0, 0
	for _, c in ipairs(self:Characters()) do
		chars = chars + 1
		for _, at in ipairs({ c.bagsAt or false, c.bankAt or false, c.mailAt or false }) do if at then parts = parts + 1 end end
		if c.mailPartial then partial = partial + 1 end
	end
	return { ("Inventory: %d character(s), %d part(s) read, %d partial mailbox(es), account bank %s; reads %d/%d/%d; mail %s"):format(
		chars, parts, partial, account() and "read" or "not read", state.reads.bags, state.reads.bank, state.reads.mail,
		Inv.READ_MAIL and "on" or "off") }
end

if ns.addon then
	ns.addon.Inventory = Inv
	LibStub("AceEvent-3.0"):Embed(Inv)
	for _, event in ipairs(Inv.EVENTS) do
		pcall(Inv.RegisterEvent, Inv, event, function(ev, arg) Inv:OnEvent(ev, arg) end)
	end
	if ns.OnEnable then
		ns.OnEnable(function()
			if Inv.Enabled() then
				if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Inventory", function() return Inv:DebugLines() end) end
				later()
			end
		end)
	end
end

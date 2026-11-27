-- Prices: auction prices read from Auctionator, when it is installed (M13.4; SPEC-17 §5.7; ECO-06; ADR 0022, ADR 0028).
-- Reused by M17. Lua 5.1.
--
-- Read only, through Auctionator's public, versioned API (Auctionator.API.v1), never its saved variables; never required,
-- never stored, never sent (not in a record, not in the wishlist, not on the board).
--   level 0   Auctionator is loaded (Compat.Addon.State)
--   level 1   Auctionator.API.v1 has GetAuctionPriceByItemID(callerID, itemID) (copper or nil); GetAuctionAgeByItemID
--             (days since the price was seen) and RegisterForDBUpdate(callerID, callback) are used when present
-- Every call is protected (pcall): an error or a missing function drops to level 0 for the session, silently. The names
-- are those of Auctionator's public API documentation [verify on Forever: the addon's folder and version, SPEC-10 R24].
--
--   Prices:Level() -> 0 | 1          Prices:Available() -> level == 1
--   Prices:Get(item) -> copper, age (days) | nil
--   Prices.STALE = 7                 a price older than this many days is shown dimmed
-- Switch: Core/Features.lua "econ" (off: Auctionator is never called). Bus: PRICES_CHANGED() after Auctionator's database
-- changed (its callback).
local ADDON_NAME, ns = ...
ns = ns or {}
local Prices = {}
ns.Prices, ns.modules = Prices, ns.modules or {}
ns.modules.Prices = Prices

local type, pcall = type, pcall

Prices.ADDON = "Auctionator"
Prices.CALLER = "Azeroth Accord"
Prices.STALE = 7

local state
local function resetState() state = { broken = false, registered = false, calls = 0, errors = 0 } Prices.state = state end
resetState()

function Prices.Enabled() return ns.Features ~= nil and ns.Features.On("econ") end

local function api()
	local A = rawget(_G, "Auctionator")
	local v1 = type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil
	return type(v1) == "table" and v1 or nil
end

local function loaded()
	local C = ns.Compat
	local s = C and C.Addon and C.Addon.State and C.Addon.State(Prices.ADDON)
	return s ~= nil and s.loaded == true
end

local function broke()
	state.broken = true
	state.errors = state.errors + 1
end

local function register(v1)
	if state.registered or type(v1.RegisterForDBUpdate) ~= "function" then return end
	state.registered = true
	local ok = pcall(v1.RegisterForDBUpdate, Prices.CALLER, function()
		if Prices.Enabled() and ns.Bus then ns.Bus:Emit("PRICES_CHANGED") end
	end)
	if not ok then state.errors = state.errors + 1 end
end

function Prices:Level()
	if not Prices.Enabled() or state.broken or not loaded() then return 0 end
	local v1 = api()
	if not (v1 and type(v1.GetAuctionPriceByItemID) == "function") then return 0 end
	register(v1)
	return 1
end

function Prices:Available() return self:Level() == 1 end

function Prices:Get(item)
	if type(item) ~= "number" or self:Level() < 1 then return nil end
	local v1 = api()
	state.calls = state.calls + 1
	local ok, copper = pcall(v1.GetAuctionPriceByItemID, Prices.CALLER, item)
	if not ok then broke() return nil end
	if type(copper) ~= "number" or copper <= 0 then return nil end
	local age
	if type(v1.GetAuctionAgeByItemID) == "function" then
		local fine, days = pcall(v1.GetAuctionAgeByItemID, Prices.CALLER, item)
		if fine and type(days) == "number" and days >= 0 then age = days end
	end
	return math.floor(copper), age
end

function Prices:Reset() resetState() end

-- The level and the functions found (SPEC-17 §11): never prices or items.
function Prices:DebugLines()
	local v1, found = api(), {}
	for _, name in ipairs({ "GetAuctionPriceByItemID", "GetAuctionAgeByItemID", "RegisterForDBUpdate" }) do
		if v1 and type(v1[name]) == "function" then found[#found + 1] = name end
	end
	return { ("Prices (Auctionator): level %d, loaded %s, functions: %s; %d call(s), %d error(s)%s"):format(self:Level(),
		tostring(loaded()), #found > 0 and table.concat(found, ", ") or "none", state.calls, state.errors,
		state.broken and ", off for this session" or "") }
end

if ns.addon then
	ns.addon.Prices = Prices
	if ns.OnEnable then
		ns.OnEnable(function()
			if Prices.Enabled() and ns.addon.AddDebugSection then
				ns.addon:AddDebugSection("Prices", function() return Prices:DebugLines() end)
			end
		end)
	end
end

-- Mock client, part 10b: item information for the bank view (Accord, M5.3).
--
-- Imitates: C_Item.GetItemInfo, C_Item.GetItemIconByID, C_Item.RequestLoadItemDataByID (dump: system Item) and the event
-- GET_ITEM_INFO_RECEIVED. The client knows an item's name only after it was requested (the cache); the icon is known
-- at once, as in the client (GetItemIconByID works for any id).
--
-- Configure (kept across Mock.Reload):
--   Mock.items.info = { [itemID] = { name = "Linen Cloth", quality = 1, icon = 132889 } }
--   Mock.items.cached = { [itemID] = true }   -- ids whose names are already loaded
--   Mock.items.requests                       -- the ids asked for with RequestLoadItemDataByID, in order
local Mock, H = ...
local W = Mock.world

W.items = W.items or { info = {}, cached = {}, requests = {} }
local items = W.items
Mock.items = items

local function link(id, info)
	return ("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(id, info.name)
end

C_Item = {}

-- itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture
function C_Item.GetItemInfo(id)
	if type(id) == "string" then   -- a name: only an item already loaded is found, as in the client
		local name = id:lower()
		for itemID, i in pairs(items.info) do
			if items.cached[itemID] and i.name:lower() == name then id = itemID end
		end
	end
	local info = items.info[id]
	if not info or not items.cached[id] then return nil end
	return info.name, link(id, info), info.quality or 1, 1, 1, "Miscellaneous", "Junk", 20, "", info.icon or 134400
end

function C_Item.GetItemIconByID(id)
	local info = items.info[id]
	return info and info.icon or 134400
end

function C_Item.RequestLoadItemDataByID(id)
	items.requests[#items.requests + 1] = id
	if items.info[id] then
		C_Timer.After(0, function()
			items.cached[id] = true
			Mock.Fire("GET_ITEM_INFO_RECEIVED", id, true)
		end)
	end
end

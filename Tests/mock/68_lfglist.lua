-- Mock client, part 6e: the game's Group Finder (Accord, M9.8; SPEC-13 §7).
--
-- Imitates the part of C_LFGList that Accord reads and writes: IsPremadeGroupFinderEnabled, GetAvailableCategories,
-- GetLfgCategoryInfo, GetAvailableActivities, GetActivityInfoTable, CreateListing, RemoveListing, HasActiveEntryInfo,
-- GetActiveEntryInfo, with the events LFG_LIST_ACTIVE_ENTRY_UPDATE, LFG_LIST_ENTRY_EXPIRED_TIMEOUT and
-- ADDON_ACTION_BLOCKED. Dump: all of them are in the LFGList system of the Forever dump, RemoveListing among the client's
-- globals. The dump does not mark protected functions: here CreateListing and RemoveListing are protected, the strict
-- case. Outside a click (Widget:Click, Tests/mock/20_frames.lua, sets Mock.hardware) they do nothing, fire
-- ADDON_ACTION_BLOCKED and count in Mock.lfg.blocked.
--
-- C_LFGList is missing by default (the other tests see a client without it). Configure (kept across Mock.Reload):
--   Mock.lfg.Set{ enabled = true,           -- IsPremadeGroupFinderEnabled
--                 private = "keep",         -- the entry's privateGroup: "keep" the flag sent, "ignore" it (false),
--                                           -- "absent" (no field at all)
--                 noRemove = true }         -- leave RemoveListing out of the client
--   Mock.lfg.Off()        C_LFGList is gone
--   Mock.lfg.created      the createData of every CreateListing that went through (copies)
--   Mock.lfg.removed      RemoveListing calls that went through; Mock.lfg.updated: UpdateListing calls
--   Mock.lfg.blocked      protected calls made outside a click
--   Mock.lfg.entry        the active entry, or nil; Mock.lfg.Expire() the game takes it away (timeout)
-- A created entry appears one frame later (the server answers), with LFG_LIST_ACTIVE_ENTRY_UPDATE(true).
local Mock, H = ...
local W = Mock.world

W.lfg = W.lfg or { on = false }
local lfg = W.lfg
Mock.lfg = lfg
lfg.created, lfg.removed, lfg.updated, lfg.blocked = lfg.created or {}, lfg.removed or 0, lfg.updated or 0, lfg.blocked or 0

lfg.CATEGORIES = { [2] = { name = "Dungeons" }, [114] = { name = "Raids", isRaid = true } }
lfg.ACTIVITIES = {
	[2] = { 1001, 1002 },
	[114] = { 1101 },
}
lfg.ACTIVITY = {
	[1001] = { fullName = "The Deadmines", mapID = 36, categoryID = 2 },
	[1002] = { fullName = "The Stockade", mapID = 34, categoryID = 2 },
	[1101] = { fullName = "Molten Core", mapID = 409, categoryID = 114 },
}

local function copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = copy(v) end
	return out
end

local function protected(name)
	if (Mock.hardware or 0) > 0 then return true end
	lfg.blocked = lfg.blocked + 1
	Mock.Fire("ADDON_ACTION_BLOCKED", "AzerothAccord", "C_LFGList." .. name .. "()")
	return false
end

local function install()
	local api = {}
	function api.IsPremadeGroupFinderEnabled() return lfg.enabled == true end
	function api.GetAvailableCategories()
		local out = {}
		for id in pairs(lfg.CATEGORIES) do out[#out + 1] = id end
		table.sort(out)
		return out
	end
	function api.GetLfgCategoryInfo(id) return copy(lfg.CATEGORIES[id]) end
	function api.GetAvailableActivities(category) return copy(lfg.ACTIVITIES[category] or {}) end
	function api.GetActivityInfoTable(id) return copy(lfg.ACTIVITY[id]) end
	function api.HasActiveEntryInfo() return lfg.entry ~= nil end
	function api.GetActiveEntryInfo() return copy(lfg.entry) end
	function api.CreateListing(data)
		if not protected("CreateListing") then return false end
		if lfg.entry or type(data) ~= "table" then return false end
		lfg.created[#lfg.created + 1] = copy(data)
		local entry = { activityIDs = copy(data.activityIDs), name = "", comment = "", autoAccept = data.isAutoAccept == true }
		if lfg.private == "keep" then entry.privateGroup = data.isPrivateGroup == true
		elseif lfg.private == "ignore" then entry.privateGroup = false end
		C_Timer.After(0, function()
			lfg.entry = entry
			Mock.Fire("LFG_LIST_ACTIVE_ENTRY_UPDATE", true)
		end)
		return true
	end
	function api.UpdateListing() lfg.updated = lfg.updated + 1 return true end
	if not lfg.noRemove then
		function api.RemoveListing()
			if not protected("RemoveListing") then return end
			lfg.removed = lfg.removed + 1
			lfg.entry = nil
			Mock.Fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
		end
	end
	C_LFGList = api
end

function lfg.Set(config)
	config = config or {}
	lfg.on = true
	lfg.enabled = config.enabled ~= false
	lfg.private = config.private or "keep"
	lfg.noRemove = config.noRemove == true
	install()
end

function lfg.Off()
	lfg.on, lfg.entry = false, nil
	C_LFGList = nil
end

function lfg.Expire()
	if not lfg.entry then return end
	lfg.entry = nil
	Mock.Fire("LFG_LIST_ENTRY_EXPIRED_TIMEOUT")
	Mock.Fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
end

if lfg.on then install() end

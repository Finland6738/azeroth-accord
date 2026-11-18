-- Role: what the character is in its guild (SPEC-00 §5) and which guild its data belongs to. Lua 5.1.
-- Adapted from Azeroth Guild Finder (Core/Role.lua), same owner, GPL-3.0 (ADR 0018); the panel matrix of the original
-- is left out (every Accord view is for every member; officer actions are checked where they happen).
-- The role comes only from the client, through Compat. It is recomputed on the guild events (and once the roster is
-- loaded at login); ROLE_CHANGED is emitted on the Bus only when the role or the guild key changed, and GUILD_CHANGED
-- when the guild key changed.
local ADDON_NAME, ns = ...
ns = ns or {}
local Role = {}
ns.Role, ns.modules = Role, ns.modules or {}
ns.modules.Role = Role

Role.NONE, Role.MEMBER, Role.OFFICER, Role.GM = "none", "member", "officer", "gm"

Role.EVENTS = { "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_RANKS_UPDATE", "PLAYER_ENTERING_WORLD" }

local current = { role = "none", guildKey = nil }
local computed = false

-- Reads the client: role, guildKey (nil without a guild or while the guild name is not known yet).
function Role.Compute()
	local Compat = ns.Compat
	local role = "none"
	if Compat and Compat.Guild.InGuild() then
		if Compat.Guild.IsGuildLeader() then role = "gm"
		elseif Compat.Guild.IsOfficer() then role = "officer"
		else role = "member" end
	end
	local key = role ~= "none" and ns.GuildKey and ns.GuildKey.Compute() or nil
	return role, key
end

-- Recomputes; emits ROLE_CHANGED (and GUILD_CHANGED) only on a change. Returns true when something changed.
function Role:Refresh()
	local role, key = Role.Compute()
	local oldRole, oldKey = current.role, current.guildKey
	local changed = role ~= oldRole or key ~= oldKey
	current.role, current.guildKey, computed = role, key, true
	if changed and ns.Bus then
		ns.Bus:Emit("ROLE_CHANGED", role, key, oldRole, oldKey)
		if key ~= oldKey then ns.Bus:Emit("GUILD_CHANGED", key, oldKey) end
	end
	return changed
end

function Role:Get()
	if not computed then Role:Refresh() end
	return current.role
end

function Role:GuildKey()
	if not computed then Role:Refresh() end
	return current.guildKey
end

function Role:InGuild() return Role:Get() ~= "none" end

-- Officers and the Guild Master: the notary of the likes, bank approvals (SPEC-00 §5).
function Role:IsOfficer()
	local role = Role:Get()
	return role == "officer" or role == "gm"
end

function Role:DebugLines()
	return { "Role: " .. Role:Get() .. ", guild key known: " .. (Role:GuildKey() and "yes" or "no") }
end

if ns.addon then
	ns.addon.Role = Role
	for _, event in ipairs(Role.EVENTS) do
		ns.addon:RegisterEvent(event, function() Role:Refresh() end)
	end
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Role", function() return Role:DebugLines() end) end
end

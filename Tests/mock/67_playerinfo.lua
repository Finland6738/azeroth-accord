-- Mock client, part 7c: what the client knows of a player by GUID (Accord, M2.2).
--
-- Imitates: GetPlayerInfoByGUID(guid) -> localizedClass, englishClass, localizedRace, englishRace, sex, name, realmName,
-- level (api.json globals). The real client answers only for players it has seen or has cached [verify: ACC-04].
-- Mock.playerInfo = { [guid] = { name =, realm =, class =, level = } } (kept across Mock.Reload); the player is always
-- known. Mock.playerInfo.disabled = true makes the function return nothing for everyone (a client that never answers).
local Mock, H = ...
local W = Mock.world

W.playerInfo = W.playerInfo or {}
Mock.playerInfo = W.playerInfo

function GetPlayerInfoByGUID(guid)
	local p = W.player
	if W.playerInfo.disabled then return nil end
	if guid == p.guid then
		return p.classFile, p.classFile, p.race, p.raceFile, 2, p.name, nil, p.level
	end
	local info = W.playerInfo[guid]
	if type(info) ~= "table" then return nil end
	return info.class or "WARRIOR", info.class or "WARRIOR", "Orc", "Orc", 2, info.name, info.realm, info.level or 60
end

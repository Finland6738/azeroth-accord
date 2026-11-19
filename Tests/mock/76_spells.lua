-- Mock client, part 9b: spells (Accord, M3.4): the name, icon and link of a recipe.
--
-- Imitates (all in the API dump): C_Spell.GetSpellInfo, C_Spell.GetSpellLink, C_Spell.RequestLoadSpellData and the event
-- SPELL_DATA_LOAD_RESULT.
--
-- Configure (kept across Mock.Reload):
--   Mock.spells.known = { [2330] = { name = "Minor Healing Potion", icon = 134830 }, ... }   what the client has data for
--   Mock.spells.loadable = { [3447] = { name = "...", icon = 1 } }   data that arrives after RequestLoadSpellData (next frame)
--   Mock.spells.requests = { 3447, ... }                     what the addon asked to load
local Mock, H = ...
local W = Mock.world

W.spells = W.spells or { known = {}, loadable = {}, requests = {} }
local sp = W.spells
Mock.spells = sp

C_Spell = C_Spell or {}

function C_Spell.GetSpellInfo(id)
	local s = type(id) == "number" and sp.known[id]
	if not s then return nil end
	return { name = s.name, iconID = s.icon, originalIconID = s.icon, spellID = id }
end

function C_Spell.GetSpellLink(id)
	local s = type(id) == "number" and sp.known[id]
	if not s then return nil end
	return ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(id, s.name)
end

function C_Spell.RequestLoadSpellData(id)
	sp.requests[#sp.requests + 1] = id
	local later = sp.loadable[id]
	if later then
		C_Timer.After(0, function()
			sp.known[id] = later
			sp.loadable[id] = nil
			Mock.Fire("SPELL_DATA_LOAD_RESULT", id, true)
		end)
	end
end

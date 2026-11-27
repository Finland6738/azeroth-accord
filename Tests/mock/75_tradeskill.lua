-- Mock client, part 9: professions and recipes (Accord, M1.3).
--
-- Imitates: GetProfessions, GetProfessionInfo (api.json globals); C_TradeSkillUI.IsGuildTradeSkillsEnabled,
-- GetBaseProfessionInfo, GetRecipeInfo, OpenTradeSkill (C_TradeSkillUI in the dump); C_TradeSkillUI.GetAllRecipeIDs
-- (NOT in the dump: present only when Mock.tradeskill.allRecipeIDs is true) [verify S4]; the guild recipe directory
-- C_GuildInfo.QueryGuildMemberRecipes, GetGuildMemberRecipes, GetNumGuildTradeSkill and the event
-- GUILD_RECIPE_KNOWN_BY_MEMBERS [verify S3].
--
-- Configure (kept across Mock.Reload):
--   Mock.tradeskill.own = { { name = "Alchemy", skillLine = 171, rank = 250, maxRank = 300, recipes = { 2330, 2332 } }, ... }
--   Mock.tradeskill.open = <index into own> | nil      the profession window shows that profession
--   Mock.tradeskill.guildEnabled = false               what IsGuildTradeSkillsEnabled answers
--   Mock.tradeskill.guildRecipes = { [guid] = { [skillLine] = { 2330, ... } } }   what the directory answers
--   Mock.tradeskill.AddAllRecipeIDs()                  adds C_TradeSkillUI.GetAllRecipeIDs (absent by default)
--   Mock.tradeskill.skillLines = true                  C_SkillInfo lists the own professions among other skill lines
--                                                      (a header, a weapon skill), as WoW Forever's Skills panel does
--   own[i].unlearned = { 2334, ... }                   recipes of the profession the character has NOT learned: GetAllRecipeIDs
--                                                      lists them too and GetRecipeInfo says learned = false (WoW Forever,
--                                                      2026-11-27: the whole profession, 593 ids for Leatherworking)
--   own[i].levels = { [2330] = 1, ... }                the required skill level GetRecipeInfo gives, in the field
--   Mock.tradeskill.levelField = "requiredSkillLevel"  named here (TradeSkillRecipeInfo has no fields in the dump)
--   Mock.tradeskill.linked = true                      the window shows somebody else's recipes (IsTradeSkillLinked)
local Mock, H = ...
local W = Mock.world

W.tradeskill = W.tradeskill or { own = {}, open = nil, guildEnabled = false, guildRecipes = {}, queries = {} }
local ts = W.tradeskill
Mock.tradeskill = ts

-- GetProfessions: prof1, prof2, archaeology, fishing, cooking (indexes into the spellbook; here 1 and 2).
function GetProfessions()
	return ts.own[1] and 1 or nil, ts.own[2] and 2 or nil, nil, nil, nil
end

-- name, texture, rank, maxRank, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset
function GetProfessionInfo(index)
	local p = ts.own[index]
	if not p then return nil end
	return p.name, 134400 + index, p.rank or 1, p.maxRank or 300, 1, 0, p.skillLine, 0, -1, 0
end

C_SkillInfo = {}
local function skillLines()
	if not ts.skillLines then return {} end
	local lines = { { skillID = 0, name = "Professions", isHeader = true, rank = 0, maxRank = 0 } }
	for _, p in ipairs(ts.own) do
		lines[#lines + 1] = { skillID = p.skillLine, name = p.name, isHeader = false, rank = p.rank or 1, maxRank = p.maxRank or 300 }
	end
	lines[#lines + 1] = { skillID = 0, name = "Weapon Skills", isHeader = true, rank = 0, maxRank = 0 }
	lines[#lines + 1] = { skillID = 45, name = "Bows", isHeader = false, rank = 180, maxRank = 185 }
	return lines
end
function C_SkillInfo.GetNumSkillLines() return #skillLines() end
function C_SkillInfo.GetSkillLineInfo(i) return skillLines()[i] end

C_TradeSkillUI = {}
function C_TradeSkillUI.IsGuildTradeSkillsEnabled() return ts.guildEnabled == true end
function C_TradeSkillUI.OpenTradeSkill(skillLine)
	for i, p in ipairs(ts.own) do
		if p.skillLine == skillLine then ts.open = i; Mock.Fire("TRADE_SKILL_SHOW"); return true end
	end
	return false
end

function C_TradeSkillUI.GetBaseProfessionInfo()
	local p = ts.open and ts.own[ts.open]
	if not p then return { professionID = 0, skillLevel = 0, maxSkillLevel = 0 } end
	return { professionID = p.skillLine, professionName = p.name, skillLevel = p.rank or 1, maxSkillLevel = p.maxRank or 300 }
end

local function info(p, id, learned)
	local t = { recipeID = id, name = "Recipe " .. id, learned = learned }
	if p.levels and p.levels[id] then t[ts.levelField or "requiredSkillLevel"] = p.levels[id] end
	return t
end

function C_TradeSkillUI.GetRecipeInfo(spellID)
	local p = ts.open and ts.own[ts.open]
	if not p then return nil end
	for _, id in ipairs(p.recipes or {}) do
		if id == spellID then return info(p, id, true) end
	end
	for _, id in ipairs(p.unlearned or {}) do
		if id == spellID then return info(p, id, false) end
	end
	return nil
end

function C_TradeSkillUI.IsTradeSkillLinked() return ts.linked == true end

-- Added only on request (the function is not in the dump): Mock.tradeskill.AddAllRecipeIDs().
function ts.AddAllRecipeIDs()
	function C_TradeSkillUI.GetAllRecipeIDs()
		local p = ts.open and ts.own[ts.open]
		local out = {}
		for _, id in ipairs(p and p.recipes or {}) do out[#out + 1] = id end
		for _, id in ipairs(p and p.unlearned or {}) do out[#out + 1] = id end
		return out
	end
end

-- Mock.tradeskill.schematics = { [recipe] = <CraftingRecipeSchematic as the modern client gives it> }: what
-- GetRecipeSchematic answers (the structure's fields are not in the dump). With schematicNeedsWindow it answers only for
-- the recipes of the open profession window. Mock.tradeskill.Schematic(out, made, { itemID, n }, ...) builds one.
ts.schematics = ts.schematics or {}
ts.schematicCalls = ts.schematicCalls or {}
function ts.Schematic(out, made, ...)
	local slots = {}
	for i, s in ipairs({ ... }) do
		slots[i] = { reagentType = 1, required = true, quantityRequired = s[2], reagents = { { itemID = s[1] } } }
	end
	return { outputItemID = out, quantityMin = made, quantityMax = made, reagentSlotSchematics = slots }
end
function C_TradeSkillUI.GetRecipeSchematic(spellID, isRecraft)
	assert(isRecraft == false, "isRecraft is not nilable")
	ts.schematicCalls[#ts.schematicCalls + 1] = spellID
	if ts.schematicNeedsWindow and not C_TradeSkillUI.GetRecipeInfo(spellID) then return nil end
	return ts.schematics[spellID]
end

-- The guild recipe directory: a query answers on a later frame with GUILD_RECIPE_KNOWN_BY_MEMBERS, when enabled.
local lastAnswer
C_GuildInfo = C_GuildInfo or {}
function C_GuildInfo.QueryGuildMemberRecipes(guid, skillLine)
	ts.queries[#ts.queries + 1] = { guid = guid, skillLine = skillLine }
	if not ts.guildEnabled then return end
	local byLine = ts.guildRecipes[guid]
	C_Timer.After(0, function()
		lastAnswer = { skillLine = skillLine, recipes = byLine and byLine[skillLine] or {} }
		Mock.Fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
	end)
end

function GetGuildMemberRecipes()
	if not lastAnswer then return nil end
	return lastAnswer.skillLine, lastAnswer.recipes
end

function GetNumGuildTradeSkill()
	if not ts.guildEnabled then return 0 end
	local n = 0
	for _ in pairs(ts.guildRecipes) do n = n + 1 end
	return n
end

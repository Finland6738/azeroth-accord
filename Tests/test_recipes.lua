-- Recipes, the native source (M3.1; SPEC-06 §1, ADR 0010): the guild recipe directory behind a capability check, one
-- query at a time with pacing, a timeout, a cache, and a fallback to the shared lists when the game does not answer.
local function R() return AzerothAccord.Recipes end
local function C() return AzerothAccord.Compat end

local ME, BOB, ANN = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44"
local ALCHEMY, SMITHING = 171, 164

local function directory()
	Mock.tradeskill.guildEnabled = true
	Mock.tradeskill.guildRecipes = {
		[BOB] = { [ALCHEMY] = { 2330, 2332, 3447 }, [SMITHING] = { 2660, 2663 } },
		[ANN] = { [ALCHEMY] = { 2330 } },
	}
end

local function listen()
	local heard = {}
	AzerothAccord.Bus:On("RECIPES_UPDATED", function(guid, line, source) heard[#heard + 1] = { guid, line, source } end)
	return heard
end

describe("reading what the game answers", function()
	it("normalizes a list: sorted, no duplicates, only whole spell ids", function()
		deepEq(R().Normalize({ 2332, 2330, 2330, 0, -4, 1.5, "x", 3447, 2 ^ 40 }), { 2330, 2332, 3447 })
		deepEq(R().Normalize({}), {})
		isNil(R().Normalize("bits"))
		isNil(R().Normalize(nil))
	end)

	it("reads a set { [id] = true } as well as a list", function()
		deepEq(R().Normalize({ [2332] = true, [2330] = true, [5] = false }), { 2330, 2332 })
	end)

	it("keeps at most MAX_IDS recipes", function()
		local big = {}
		for i = 1, R().MAX_IDS + 50 do big[i] = i end
		eq(#R().Normalize(big), R().MAX_IDS)
	end)

	it("takes the skill line first and the list from whichever value is a table", function()
		local line, ids = R().ParseNative({ n = 2, 164, { 2663, 2660 } })
		eq(line, 164); deepEq(ids, { 2660, 2663 })
		line, ids = R().ParseNative({ n = 3, 164, 2, { 2660, 2663 } })
		eq(line, 164); deepEq(ids, { 2660, 2663 })
		line, ids = R().ParseNative({ n = 2, 164, {} })
		eq(line, 164); deepEq(ids, {}, "a member with the profession and no recipe")
	end)

	it("recognises a bitfield string without decoding it, and refuses anything else", function()
		local line, ids, why = R().ParseNative({ n = 3, 164, 12, "\255\3" })
		eq(line, 164); isNil(ids); eq(why, "bitfield")
		line, ids, why = R().ParseNative({ n = 1, 164 })
		isNil(ids); eq(why, "shape")
		line, ids, why = R().ParseNative({ n = 0 })
		isNil(ids); eq(why, "none")
		line, ids, why = R().ParseNative(nil)
		isNil(ids); eq(why, "none")
	end)

	it("a key is the character GUID and the skill line, like the id of a shared record", function()
		eq(R().Key(BOB, 171), BOB .. ":171")
		isNil(R().Key(nil, 171)); isNil(R().Key(BOB, "171")); isNil(R().Key("", 171))
	end)
end)

describe("the capability check", function()
	it("the native source is not usable while the client says the directory is off", function()
		Mock.tradeskill.guildEnabled = false
		local ok, why = R():NativeUsable()
		falsy(ok); eq(why, "disabled")
		eq(C():Feature("guildRecipesNative"), "missing")
		eq(R():RequestNative(BOB, ALCHEMY), "unavailable")
		eq(#Mock.tradeskill.queries, 0, "nothing was asked")
	end)

	it("it is usable once the client enables it, and the feature says it is waiting for the first answer", function()
		directory()
		truthy(R():NativeUsable())
		eq(C():Feature("guildRecipesNative"), "unknown")
	end)

	it("a client without the functions is not usable and nothing raises", function()
		directory()
		GetGuildMemberRecipes = nil
		local ok, why = R():NativeUsable()
		falsy(ok); eq(why, "api")
		eq(R():RequestNative(BOB, ALCHEMY), "unavailable")
		isNil(R():Lookup(BOB, ALCHEMY))
	end)

	it("a function that errors only makes the query fail", function()
		directory()
		C_GuildInfo.QueryGuildMemberRecipes = function() error("boom") end
		eq(R():RequestNative(BOB, ALCHEMY), "queued")
		Mock.Advance(3)
		eq(R().native.stats.failed, 1)
		isNil(R():Lookup(BOB, ALCHEMY))
		falsy(R():NativeStatus().inflight)
	end)

	it("the own character is never asked: its lists come from the own scan", function()
		directory()
		eq(R():RequestNative(ME, ALCHEMY), "self")
		eq(R():RequestNative(nil, ALCHEMY), "invalid")
		eq(R():RequestNative(BOB, "x"), "invalid")
		eq(#Mock.tradeskill.queries, 0)
	end)
end)

describe("asking the guild recipe directory", function()
	it("one query, then the answer arrives with the event and is cached, with its source and time", function()
		directory()
		local heard = listen()
		eq(R():RequestNative(BOB, SMITHING), "queued")
		eq(#Mock.tradeskill.queries, 1)
		eq(Mock.tradeskill.queries[1].guid, BOB); eq(Mock.tradeskill.queries[1].skillLine, SMITHING)
		isNil(R():Lookup(BOB, SMITHING), "not before the answer")
		Mock.Advance(0.5)
		local e = R():Lookup(BOB, SMITHING)
		notNil(e)
		deepEq(e.ids, { 2660, 2663 })
		eq(e.source, "native"); eq(e.skillLine, SMITHING); eq(e.guid, BOB)
		eq(e.time, GetServerTime()); truthy(e.fresh)
		eq(#heard, 1); deepEq(heard[1], { BOB, SMITHING, "native" })
		eq(C():Feature("guildRecipesNative"), "available")
	end)

	it("a second request for the same list is served from the cache while it is fresh", function()
		directory()
		R():RequestNative(BOB, ALCHEMY)
		Mock.Advance(0.5)
		eq(R():RequestNative(BOB, ALCHEMY), "cached")
		eq(#Mock.tradeskill.queries, 1)
		eq(R():Refresh(BOB, ALCHEMY), "cached")
	end)

	it("after the TTL the list is asked again and the old answer stays until the new one comes", function()
		directory()
		R():RequestNative(BOB, ALCHEMY)
		Mock.Advance(0.5)
		Mock.Advance(R().NATIVE_TTL + 1)
		falsy(R():Lookup(BOB, ALCHEMY).fresh, "stale but still there")
		eq(R():RequestNative(BOB, ALCHEMY), "queued")
		Mock.Advance(0.5)
		truthy(R():Lookup(BOB, ALCHEMY).fresh)
		eq(#Mock.tradeskill.queries, 2)
	end)

	it("queries go one at a time, at least NATIVE_GAP seconds apart, without duplicates", function()
		directory()
		eq(R():RequestNative(BOB, ALCHEMY), "queued")
		eq(R():RequestNative(BOB, SMITHING), "queued")
		eq(R():RequestNative(ANN, ALCHEMY), "queued")
		eq(R():RequestNative(BOB, SMITHING), "pending")
		eq(#Mock.tradeskill.queries, 1, "only the first goes out at once")
		Mock.Advance(1)
		eq(#Mock.tradeskill.queries, 1, "the gap has not passed")
		Mock.Advance(1.5)
		eq(#Mock.tradeskill.queries, 2)
		Mock.Advance(2.1)
		eq(#Mock.tradeskill.queries, 3)
		eq(Mock.tradeskill.queries[2].skillLine, SMITHING); eq(Mock.tradeskill.queries[3].guid, ANN)
		notNil(R():Lookup(ANN, ALCHEMY)); notNil(R():Lookup(BOB, ALCHEMY)); notNil(R():Lookup(BOB, SMITHING))
		eq(R():NativeStatus().queued, 0)
	end)

	it("the queue holds at most NATIVE_QUEUE jobs", function()
		directory()
		local answers = {}
		for i = 1, R().NATIVE_QUEUE + 3 do
			answers[#answers + 1] = R():RequestNative(("Player-1-%08X"):format(0x100 + i), ALCHEMY)
		end
		eq(answers[1], "queued")
		eq(answers[#answers], "full")
		eq(R():NativeStatus().queued, R().NATIVE_QUEUE)
	end)

	it("an answer for another skill line is not ours: it is ignored and the query keeps waiting", function()
		directory()
		R():RequestNative(BOB, ALCHEMY)
		local real = GetGuildMemberRecipes
		GetGuildMemberRecipes = function() return SMITHING, { 9999 } end
		Mock.Fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
		GetGuildMemberRecipes = real
		eq(R().native.stats.stale, 1)
		isNil(R():Lookup(BOB, ALCHEMY))
		isNil(R():Lookup(BOB, SMITHING))
		truthy(R():NativeStatus().inflight)
		Mock.Advance(0.5)
		deepEq(R():Lookup(BOB, ALCHEMY).ids, { 2330, 2332, 3447 })
	end)

	it("an event with nothing asked (the game's own window) is ignored", function()
		directory()
		Mock.Fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
		eq(R().native.stats.answers, 0)
		eq(R():NativeStatus().cached, 0)
	end)

	it("a query nobody answers times out, and the next one goes out", function()
		directory()
		local real = C_GuildInfo.QueryGuildMemberRecipes
		C_GuildInfo.QueryGuildMemberRecipes = function(guid, line) if guid ~= BOB then real(guid, line) end end
		R():RequestNative(BOB, ALCHEMY)
		R():RequestNative(ANN, ALCHEMY)
		Mock.Advance(R().NATIVE_TIMEOUT + 0.5)
		eq(R().native.stats.timeouts, 1)
		Mock.Advance(1)
		notNil(R():Lookup(ANN, ALCHEMY))
		isNil(R():Lookup(BOB, ALCHEMY))
		eq(R().native.timeouts, 0, "an answer clears the count of unanswered queries")
	end)

	it("after NATIVE_MAX_TIMEOUTS unanswered queries in a row the source rests, and then works again", function()
		directory()
		local real = C_GuildInfo.QueryGuildMemberRecipes
		C_GuildInfo.QueryGuildMemberRecipes = function() end
		for i = 1, R().NATIVE_MAX_TIMEOUTS do
			eq(R():RequestNative(("Player-1-%08X"):format(0x200 + i), ALCHEMY), "queued")
			Mock.Advance(R().NATIVE_TIMEOUT + 2.5)
		end
		eq(R().native.stats.timeouts, R().NATIVE_MAX_TIMEOUTS)
		local ok, why = R():NativeUsable()
		falsy(ok); eq(why, "rest")
		eq(R():RequestNative(BOB, ALCHEMY), "unavailable")
		eq(C():Feature("guildRecipesNative"), "unknown", "never an answer, so still unknown, not missing")
		C_GuildInfo.QueryGuildMemberRecipes = real
		Mock.Advance(R().NATIVE_REST + 1)
		truthy(R():NativeUsable())
		eq(R():RequestNative(BOB, ALCHEMY), "queued")
		Mock.Advance(0.5)
		notNil(R():Lookup(BOB, ALCHEMY))
	end)

	it("an answer the addon cannot read (a bitfield) turns the native source off and the shared lists carry on", function()
		directory()
		GetGuildMemberRecipes = function() return ALCHEMY, 3, "\255\3" end
		R():RequestNative(BOB, ALCHEMY)
		Mock.Advance(0.5)
		eq(C():Feature("guildRecipesNative"), "unknown", "one unreadable answer is not proof")
		R():RequestNative(ANN, ALCHEMY)
		Mock.Advance(2.5)
		eq(R().native.stats.unusable, 2)
		eq(C():Feature("guildRecipesNative"), "missing")
		local ok, why = R():NativeUsable()
		falsy(ok); eq(why, "bitfield")
		eq(R():RequestNative(BOB, SMITHING), "unavailable")
		isNil(R():Lookup(BOB, ALCHEMY))
	end)

	it("the cache keeps at most CACHE_MAX answers, dropping the oldest", function()
		directory()
		local real = GetGuildMemberRecipes
		GetGuildMemberRecipes = function() return ALCHEMY, { 2330 } end
		for i = 1, R().CACHE_MAX + 5 do
			R():RequestNative(("Player-1-%08X"):format(0x300 + i), ALCHEMY)
			Mock.Advance(2.1)
		end
		GetGuildMemberRecipes = real
		eq(R():NativeStatus().cached, R().CACHE_MAX)
		isNil(R():Lookup(("Player-1-%08X"):format(0x301), ALCHEMY), "the oldest is gone")
		notNil(R():Lookup(("Player-1-%08X"):format(0x300 + R().CACHE_MAX + 5), ALCHEMY))
	end)

	it("a change of guild forgets the queue and the cache, and a timer of the old guild does nothing", function()
		directory()
		R():RequestNative(BOB, ALCHEMY)
		R():RequestNative(ANN, ALCHEMY)
		Mock.Advance(0.5)
		notNil(R():Lookup(BOB, ALCHEMY))
		AzerothAccord.Bus:Emit("GUILD_CHANGED", "Realm/Other")
		isNil(R():Lookup(BOB, ALCHEMY))
		eq(R():NativeStatus().queued, 0)
		Mock.Advance(10)
		eq(#Mock.tradeskill.queries, 1, "the queued query of the old guild never went out")
	end)

	it("/accord debug reports the source", function()
		directory()
		R():RequestNative(BOB, ALCHEMY)
		Mock.Advance(0.5)
		local text = table.concat(R():DebugLines(), "\n")
		truthy(text:find("native source usable", 1, true))
		truthy(text:find("answers 1", 1, true))
		truthy(AzerothAccord.Diagnostics.Report():find("Recipes:", 1, true), "in the diagnostics report")
	end)
end)

-- Hardening (M7.7; SPEC-11 §6): what a bad or broken guildmate's client can send, and Forever full names with a space.
-- Every case of §6.1-§6.3 must be refused without a Lua error (the harness fails a test on any error the client's
-- handler caught), without blocking the send queue and without changing the data already held. The guild has a member
-- and its alt (Bob, Bobalt), a cheater (Mallory), an officer and the Guild Master; the player is Testchar (ME).
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function Tr() return AzerothAccord.Transport end
local function Sy() return AzerothAccord.Sync end
local function Codec() return AzerothAccord.Codec end

local ME = "Player-1-0000A001"
local BOB, BOBALT, MAL, OFF, GM = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000BAD", "Player-1-000000FF", "Player-1-000000AA"

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank or 3, members = {
		{ name = "Bob", rank = 3, guid = BOB }, { name = "Bobalt", rank = 4, guid = BOBALT },
		{ name = "Mallory", rank = 3, guid = MAL }, { name = "Officer", rank = 1, guid = OFF }, { name = "Boss", rank = 0, guid = GM },
	} }
end

local function R(fields)
	local r = { rev = 1, time = GetServerTime() }
	for k, v in pairs(fields) do r[k] = v end
	return r
end

local function acct(guid, chars, extra)
	local list = {}
	for i, g in ipairs(chars or { guid }) do list[i] = { guid = g } end
	local r = R{ id = guid, author = guid, token = "T" .. guid:sub(-3), chars = list }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

-- The text of a message as a peer's client would send it, and its arrival from `sender` over `dist` (GUILD by default).
local function text(t, fields) return assert(Codec():Encode(t, fields)) end
local function arrive(t, fields, sender, dist) return Tr():OnReceive(text(t, fields), dist or "GUILD", sender) end
local function arriveRaw(raw, sender, dist) return Tr():OnReceive(raw, dist or "GUILD", sender) end
-- "1|<T>|" + Base64(flag .. payload): any bytes, as a broken or hostile client could send them.
local function wrap(t, flag, payload) return "1|" .. t .. "|" .. C_EncodingUtil.EncodeBase64(flag .. payload) end
local function cbor(v) return C_EncodingUtil.SerializeCBOR(v) end
local function deflate(s) return C_EncodingUtil.CompressString(s) end

-- The whole store of the guild as one text: a refused case must leave it exactly as it was.
local function canon(value)
	local t = type(value)
	if t == "string" then return ("%q"):format(value) end
	if t ~= "table" then return tostring(value) end
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) if type(a) ~= type(b) then return type(a) < type(b) end return a < b end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. canon(k) .. "]=" .. canon(value[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end
local function snapshot()
	local out = {}
	for _, set in ipairs(S().SET_ORDER) do out[set] = S():Records(set) end
	return canon(out)
end

-- The send queue still moves: a message queued now goes out on the wire within a few seconds.
local function queueMoves()
	local calls = {}
	Tr().wire = function(prio, txt, dist, target, done) calls[#calls + 1] = dist done(0) end
	truthy(Tr():Send("GUILD", { t = "REQ", s = "accounts" }), "queued")
	Mock.Advance(3)
	eq(#calls >= 1, true, "the queue sent nothing")
	eq(Tr():Pending(), 0)
end

-- Bob and Bobalt are one account: each publishes its own record listing both.
local function bobAccount()
	truthy(S():Accept("accounts", acct(BOB, { BOB, BOBALT }), { sender = "Bob" }))
	truthy(S():Accept("accounts", acct(BOBALT, { BOBALT, BOB }), { sender = "Bobalt" }))
end

---------------------------------------------------------------------------------------------------------------------
-- §6.1 sizes
---------------------------------------------------------------------------------------------------------------------
describe("sizes (SPEC-11 §6.1)", function()
	before_boot(function() guild() end)

	it("a text over Codec.MAX_TEXT is dropped before any decoding", function()
		local before = snapshot()
		local ok, why = arriveRaw("1|REC|" .. ("A"):rep(Codec().MAX_TEXT), "Bob")
		falsy(ok); eq(why, "size")
		eq(snapshot(), before)
		queueMoves()
	end)

	it("CBOR over 16 KB after decompression is dropped (a small deflate 'bomb')", function()
		local payload = cbor({ s = "accounts", r = { { id = BOB, pad = ("z"):rep(20000) } } })
		local raw = wrap("REC", "\1", deflate(payload))
		truthy(#raw < 1000, "the text is small")
		local ok, why = arriveRaw(raw, "Bob")
		falsy(ok); eq(why, "size")
		queueMoves()
	end)

	it("a REC with more than 100 records is dropped whole; 100 pass", function()
		local many = {}
		for i = 1, 101 do many[i] = R{ id = BOB .. ":" .. i, author = BOB, char = BOB, skillLine = i, ids = {} } end
		local before = snapshot()
		truthy(arrive("REC", { s = "recipes", r = many }, "Bob"), "it decodes: the limit is the sync's")
		eq(snapshot(), before)
		eq(Sy().state.stats.oversized, 1)
		eq(S().stats.accepted, 0, "not one record of it was even looked at")
		many[101] = nil
		arrive("REC", { s = "recipes", r = many }, "Bob")
		eq(S():Count("recipes"), 100)
		queueMoves()
	end)

	it("a table deeper than 8 levels is dropped; 8 levels pass", function()
		local function nest(levels)
			local t = { leaf = true }
			for _ = 2, levels do t = { t } end
			return t
		end
		-- the message is level 1, r level 2, the record level 3: x adds the rest
		local ok8 = Codec():Decode(text("REC", { s = "accounts", r = { { id = "a", x = nest(5) } } }))
		notNil(ok8, "8 levels")
		local msg, why = Codec():Decode(text("REC", { s = "accounts", r = { { id = "a", x = nest(6) } } }))
		isNil(msg); eq(why, "depth")
		falsy(arrive("REC", { s = "accounts", r = { { id = "a", x = nest(40) } } }, "Bob"))
		queueMoves()
	end)

	it("a summary longer than 2000 entries or of a broken length is ignored", function()
		isNil(Sy().DecodeSummary(("\0"):rep(11 * 2001)))
		isNil(Sy().DecodeSummary(("\0"):rep(12)))
		notNil(Sy().DecodeSummary(""))
		isNil(Sy().DecodeBlocks(("\0"):rep(287)))
		notNil(Sy().DecodeBlocks(("\0"):rep(288)))
	end)

	it("a record over the size of its set is refused, the others of the REC are kept", function()
		local big = acct(BOB, nil, { pad = ("x"):rep(5000) })
		local small = acct(BOBALT)
		arrive("REC", { s = "accounts", r = { big } }, "Bob")
		arrive("REC", { s = "accounts", r = { small } }, "Bobalt")
		isNil(S():Get("accounts", BOB))
		notNil(S():Get("accounts", BOBALT))
		eq(S().stats.reasons.size, 1)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- §6.2 malformed messages, forged authors, replayed revisions
---------------------------------------------------------------------------------------------------------------------
describe("malformed messages (SPEC-11 §6.2)", function()
	before_boot(function() guild() end)

	it("each broken form is dropped by the codec with its reason", function()
		local good = text("REC", { s = "accounts", r = { acct(BOB) } })
		local body = good:match("^1|REC|(.*)$")
		local cases = {
			{ "1|REC|@@@@", "base64" },                                           -- not Base64
			{ good:sub(1, #good - 5), nil },                                       -- truncated (base64, cbor or inflate)
			{ "1|REC|" .. body:sub(1, 8), nil },                                   -- truncated hard
			{ wrap("REC", "\2", cbor({ s = "accounts", r = {} })), "flag" },      -- unknown format byte
			{ wrap("REC", "\0", "\255\255\255"), "cbor" },                        -- broken CBOR
			{ wrap("REC", "\1", "not deflate at all"), "inflate" },              -- broken compression
			{ wrap("REC", "\0", cbor({ s = "accounts" })), "invalid" },          -- required field missing
			{ wrap("REC", "\0", cbor({ s = "accounts", r = "x" })), "invalid" }, -- required field of the wrong type
			{ wrap("REC", "\0", cbor({ s = 5, r = {} })), "invalid" },
			{ wrap("REC", "\0", cbor("just a string")), "shape" },               -- not a table
			{ "REC|1|abc", "shape" }, { "1|rec|AAAA", "shape" }, { "", "size" },
		}
		local before = snapshot()
		for i, c in ipairs(cases) do
			local ok, why = arriveRaw(c[1], "Bob")
			falsy(ok, "case " .. i)
			if c[2] then eq(why, c[2], "case " .. i) end
		end
		eq(snapshot(), before)
		queueMoves()
	end)

	it("survives garbage and random mutations of a good message", function()
		local good = text("REC", { s = "accounts", r = { acct(BOB, { BOB, BOBALT }) } })
		local seed = 12345
		local function rnd(n)
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n
		end
		for _ = 1, 300 do
			local bytes = {}
			for j = 1, rnd(300) + 1 do bytes[j] = string.char(rnd(256)) end
			arriveRaw(table.concat(bytes), "Mallory")
			arriveRaw("1|REC|" .. table.concat(bytes), "Mallory")
			local pos = rnd(#good) + 1
			arriveRaw(good:sub(1, pos - 1) .. string.char(rnd(256)) .. good:sub(pos + 1), "Bob")
			arriveRaw(good:sub(1, rnd(#good)), "Bob")
		end
		eq(#Mock.errors, 0)
		queueMoves()
	end)

	it("wrong types inside a well-formed message are refused, never an error", function()
		local before = snapshot()
		arrive("REC", { s = "accounts", r = { "string", 5, true, { 1, 2 }, { id = {} }, { id = "x", author = 7 } } }, "Bob")
		arrive("REC", { s = "nope", r = { acct(BOB) } }, "Bob")
		arrive("REC", { s = "accounts", r = { [5] = acct(BOB) } }, "Bob")
		arrive("HELLO", { s = "short" }, "Bob")
		arrive("BHELLO", { b = "short" }, "Bobalt")
		arrive("REQ", { s = "*", a = { "x", {}, 1.5, -1 } }, "Bob", "WHISPER")
		arrive("REQ", { s = "accounts", a = "x" }, "Bob", "WHISPER")
		arrive("DIGEST", { d = { [999] = "x", y = 5 } }, "Officer", "WHISPER")
		arrive("OHELLO", { s = "abc" }, "Officer", "OFFICER")
		eq(snapshot(), before)
		queueMoves()
	end)

	it("a truncated multipart text through the real AceComm path delivers nothing and blocks nothing", function()
		local seen = {}
		A().Bus:On("NET_MESSAGE", function(msg) seen[#seen + 1] = msg end)
		local pad = {}
		local x = 7
		for i = 1, 900 do   -- letters that do not compress away
			x = (x * 1103515245 + 12345) % 2147483648
			pad[i] = string.char(97 + math.floor(x / 65536) % 26)
		end
		local long = text("REC", { s = "accounts", r = { acct(BOB, nil, { pad = table.concat(pad) }) } })
		local chunks = Tr().Frame(long)
		truthy(#chunks >= 3)
		Mock.chat.Receive("AzAccord", chunks[1], "GUILD", "Bob")
		Mock.chat.Receive("AzAccord", chunks[2], "GUILD", "Bob")   -- the last part never comes
		eq(#seen, 0)
		Mock.chat.Receive("AzAccord", "\003garbage-last", "GUILD", "Mallory")
		Mock.chat.Receive("AzAccord", "\002orphan-middle", "GUILD", "Mallory")
		eq(#seen, 0)
		Mock.chat.Receive("AzAccord", text("REQ", { s = "accounts" }), "GUILD", "Bobalt")
		eq(#seen, 1, "the next whole message goes through")
		queueMoves()
	end)

	it("a forged author is refused as a relay; the true author's record stays", function()
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB) } }, "Bob"))
		local before = snapshot()
		local forged = acct(BOB, { BOB, MAL }, { rev = 2, time = GetServerTime() + 5 })
		arrive("REC", { s = "accounts", r = { forged } }, "Mallory")
		eq(snapshot(), before)
		eq(S().stats.reasons.relay, 1)
	end)

	it("an accounts record that lists somebody else's character joins nothing", function()
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB) } }, "Bob"))
		truthy(arrive("REC", { s = "accounts", r = { acct(MAL, { MAL, BOB }) } }, "Mallory"))
		notNil(S():Get("accounts", MAL), "accepted as Mallory's own record")
		falsy(S():SameAccount(MAL, BOB), "but Bob's record does not list Mallory")
		-- so Mallory cannot pass on Bob's records either
		arrive("REC", { s = "contacts", r = { R{ id = BOB, author = BOB, battleTag = "Bob#1" } } }, "Mallory")
		isNil(S():Get("contacts", BOB))
	end)

	it("an author that is not a GUID, a rev that is not an integer, a time an hour ahead", function()
		local before = snapshot()
		arrive("REC", { s = "accounts", r = {
			acct(BOB, nil, { author = "Bob" }), acct(BOB, nil, { rev = 1.5 }), acct(BOB, nil, { rev = 0 }),
			acct(BOB, nil, { time = GetServerTime() + 3700 }), acct(BOB, nil, { rev = S().MAX_REV + 1 }),
		} }, "Bob")
		eq(snapshot(), before)
		local reasons = S().stats.reasons
		eq(reasons.author, 1); eq(reasons.rev, 3); eq(reasons.future, 1)
	end)

	it("a replayed or older revision changes nothing and is not a refusal", function()
		local three = acct(BOB, nil, { rev = 3 })
		truthy(arrive("REC", { s = "accounts", r = { three } }, "Bob"))
		local before = snapshot()
		for _ = 1, 120 do arrive("REC", { s = "accounts", r = { three, acct(BOB, nil, { rev = 2 }) } }, "Bob") end
		eq(snapshot(), before)
		eq(S().stats.rejected, 0)
		eq(Sy().state.stats.refused, 0)
		falsy(Tr():IsQuarantined("Bob"), "replays never put an honest sender in quarantine")
		queueMoves()
	end)

	it("the same rev with another content: the later time wins, and only from the author's account", function()
		local t = GetServerTime()
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB, nil, { rev = 3, time = t, main = BOB }) } }, "Bob"))
		arrive("REC", { s = "accounts", r = { acct(BOB, nil, { rev = 3, time = t + 10, main = MAL }) } }, "Mallory")
		eq(S():Get("accounts", BOB).main, BOB, "Mallory may not send it")
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB, nil, { rev = 3, time = t + 10, main = BOBALT }) } }, "Bob"))
		eq(S():Get("accounts", BOB).main, BOBALT)
		arrive("REC", { s = "accounts", r = { acct(BOB, nil, { rev = 3, time = t + 5, main = BOB }) } }, "Bob")
		eq(S():Get("accounts", BOB).main, BOBALT, "an earlier time of the same rev loses")
	end)

	it("rev = MAX_REV only 'locks' an id its sender may write", function()
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB) } }, "Bob"))
		truthy(arrive("REC", { s = "accounts", r = { acct(MAL, nil, { rev = S().MAX_REV }) } }, "Mallory"), "its own id: fine")
		arrive("REC", { s = "accounts", r = { acct(BOB, nil, { rev = S().MAX_REV }) } }, "Mallory")
		eq(S():Get("accounts", BOB).rev, 1, "Bob's record is untouched")
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB, nil, { rev = 2 }) } }, "Bob"))
		eq(S():Get("accounts", BOB).rev, 2)
	end)

	it("a Lua error in a handler is caught by the Bus and the next message is handled", function()
		local errorsBefore = A().Bus.errorCount
		local handler = geterrorhandler()
		seterrorhandler(function() end)   -- the Bus reports to the game's handler: the test only counts here
		A().Bus:On("NET_MESSAGE", function() error("a broken listener") end)
		arrive("REC", { s = "accounts", r = { acct(BOB) } }, "Bob")
		arrive("REC", { s = "accounts", r = { acct(BOBALT) } }, "Bobalt")
		seterrorhandler(handler)
		notNil(S():Get("accounts", BOB))
		notNil(S():Get("accounts", BOBALT), "the next message was handled")
		eq(A().Bus.errorCount - errorsBefore, 2)
		for i = #Mock.errors, 1, -1 do Mock.errors[i] = nil end
		queueMoves()
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- §6.3 floods
---------------------------------------------------------------------------------------------------------------------
describe("floods (SPEC-11 §6.3)", function()
	before_boot(function() guild(1) end)   -- the player is an officer: it answers every request

	it("one HELLO and one BHELLO per sender per minute are handled; only the latest early one waits", function()
		for _ = 1, 5 do arrive("HELLO", { s = "" }, "Bob") end
		eq(Sy().state.stats.hellosHeard, 1)
		eq(Sy().state.stats.flood, 4)
		arrive("HELLO", { s = "" }, "Bobalt")
		eq(Sy().state.stats.hellosHeard, 2, "another sender has its own counter")
		for _ = 1, 3 do arrive("BHELLO", { b = ("\0"):rep(288) }, "Bob") end
		eq(Sy().state.stats.bhellosHeard, 0, "HELLO and BHELLO share the minute")
		eq(Sy().state.stats.flood, 7)
		Mock.Advance(61)
		eq(Sy().state.stats.bhellosHeard, 1, "the latest one (a BHELLO) is handled when the minute is over")
		eq(Sy().state.stats.hellosHeard, 2, "the earlier ones of the minute are dropped")
		Mock.Advance(120)
		eq(Sy().state.stats.bhellosHeard + Sy().state.stats.hellosHeard, 3, "nothing more")
		queueMoves()
	end)

	it("a client that logs in again within the minute is still heard (a /reload)", function()
		arrive("HELLO", { s = "" }, "Bob")
		Mock.Advance(20)
		arrive("HELLO", { s = "" }, "Bob")   -- after a /reload: a new HELLO 20 s later
		eq(Sy().state.stats.hellosHeard, 1)
		Mock.Advance(41)
		eq(Sy().state.stats.hellosHeard, 2)
	end)

	it("REQ of every set: 10 per sender per minute", function()
		truthy(S():Put("accounts", ME, { token = "TOKEN", chars = { { guid = ME } } }))
		local key = Sy().KeyOf(ME)
		for _ = 1, 15 do arrive("REQ", { s = "*", a = { key } }, "Bob", "WHISPER") end
		eq(Sy().state.stats.answers, 10)
		Mock.Advance(61)
		arrive("REQ", { s = "*", a = { key } }, "Bob", "WHISPER")
		eq(Sy().state.stats.answers, 11)
		queueMoves()
	end)

	it("REQ of one set: 20 per sender per minute (M1.8)", function()
		truthy(S():Put("accounts", ME, { token = "TOKEN", chars = { { guid = ME } } }))
		local key = Sy().KeyOf(ME)
		for _ = 1, 25 do arrive("REQ", { s = "accounts", a = { key } }, "Bob", "WHISPER") end
		eq(Sy().state.stats.asksAnswered, 20)
		eq(Sy().state.stats.asksLimited, 5)
	end)

	it("more than 256 KB decoded in a minute puts the sender in quarantine for 10 minutes", function()
		local bomb = wrap("REC", "\1", deflate(cbor({ s = "accounts", r = { { id = "x", pad = ("q"):rep(15000) } } })))
		local decodedBefore = Codec().stats.decoded
		for _ = 1, 17 do arriveRaw(bomb, "Mallory") end
		falsy(Tr():IsQuarantined("Mallory"), "17 x 15 KB is under 256 KB")
		arriveRaw(bomb, "Mallory")
		truthy(Tr():IsQuarantined("Mallory"))
		local decoded = Codec().stats.decoded
		eq(decoded - decodedBefore, 18, "the one over the budget was decoded, then dropped")
		-- every message of Mallory is dropped before decoding, even a good one; the others go through
		local ok, why = arrive("REC", { s = "accounts", r = { acct(MAL) } }, "Mallory")
		falsy(ok); eq(why, "quarantine")
		eq(Codec().stats.decoded, decoded)
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB) } }, "Bob"))
		queueMoves()
		Mock.Advance(601)
		falsy(Tr():IsQuarantined("Mallory"))
		truthy(arrive("REC", { s = "accounts", r = { acct(MAL) } }, "Mallory"))
	end)

	it("more than 50 refused records in 10 minutes put the sender in quarantine", function()
		local function forged(n)
			local list = {}
			for i = 1, n do list[i] = acct(BOB, nil, { rev = i }) end   -- Bob's records from Mallory: relay
			return list
		end
		for _ = 1, 5 do arrive("REC", { s = "accounts", r = forged(10) }, "Mallory") end
		falsy(Tr():IsQuarantined("Mallory"), "50 refused: still listened to")
		arrive("REC", { s = "accounts", r = forged(1) }, "Mallory")
		truthy(Tr():IsQuarantined("Mallory"))
		eq(Sy().state.stats.quarantined, 1)
		falsy(arrive("REC", { s = "accounts", r = { acct(MAL) } }, "Mallory"))
		isNil(S():Get("accounts", MAL))
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB) } }, "Bob"), "an honest sender is not affected")
		-- an officer in quarantine stays an officer: only its messages are dropped
		queueMoves()
		Mock.Advance(601)
		truthy(arrive("REC", { s = "accounts", r = { acct(MAL) } }, "Mallory"))
	end)

	it("/accord debug counts the senders in quarantine, never names them", function()
		Tr():Quarantine("Mallory")
		Mock.ClearOutput()
		Mock.Slash("/accord debug")
		local out = table.concat(Mock.PlainOutput(), "\n")
		contains(out, "senders in quarantine: 1 now")
		falsy(out:find("Mallory", 1, true))
	end)

	it("a change of guild starts the counters again", function()
		Tr():Quarantine("Mallory")
		for _ = 1, 3 do arrive("HELLO", { s = "" }, "Bob") end
		A().Bus:Emit("GUILD_CHANGED", nil, A().GuildKey:Current())
		falsy(Tr():IsQuarantined("Mallory"))
		eq(Tr():QuarantineCount(), 0)
	end)

	it("a flood never stops the client's own sending", function()
		local calls = {}
		Tr().wire = function(prio, txt, dist, target, done) calls[#calls + 1] = dist done(0) end
		Tr():Send("GUILD", { t = "REQ", s = "accounts" })
		for _ = 1, 200 do arriveRaw("1|REC|@@@@", "Mallory") end
		for _ = 1, 30 do arrive("HELLO", { s = "" }, "Bob") end
		Tr():Send("OFFICER", { t = "SALT", k = "q" })
		Mock.Advance(3)
		eq(#calls, 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The block summary (SPEC-11 §6.4), between a few real clients
---------------------------------------------------------------------------------------------------------------------
describe("block summary (SPEC-11 §6.4)", function()
	it("knows which versions understand BHELLO", function()
		local K = Sy().KnowsBlocks
		truthy(K("0.7.0")); truthy(K("v0.7.1")); truthy(K("1.0.0")); truthy(K("0.10.0")); truthy(K("@project-version@"))
		falsy(K("0.6.9")); falsy(K("v0.6.0")); falsy(K(nil)); falsy(K("beta")); falsy(K(7))
	end)

	it("spreads the first HELLO after login with the number of authors", function()
		deepEq(Sy().FirstHelloDelay(0), { 10, 30 })
		deepEq(Sy().FirstHelloDelay(1000), { 10, 130 })
	end)

	it("the authors of one realm spread over the blocks; a block digest changes with any record of it", function()
		-- GUIDs of one realm differ only in their last digits: their keys must still fill the blocks evenly
		local per, used = {}, 0
		for i = 1, 1000 do
			local b = Sy().BlockOf(Sy().KeyOf(("Player-1096-%08X"):format(0x0A1B2C00 + i)))
			truthy(b >= 0 and b < Sy().BLOCKS and b == math.floor(b))
			if not per[b] then used = used + 1 end
			per[b] = (per[b] or 0) + 1
		end
		eq(used, Sy().BLOCKS, "every block holds some of 1000 authors")
		for b = 0, Sy().BLOCKS - 1 do truthy(per[b] <= 25, "block " .. b .. " holds " .. per[b]) end
		eq(Sy().BlockOf(0), 0); eq(Sy().BlockOf(4294967295), Sy().BlockOf(4294967295))
		local ka, kb = 5, 2 ^ 31 + 12345
		local g1 = { a = { key = ka, d = 1, t = 100 }, b = { key = kb, d = 2, t = 100 } }
		local g2 = { a = { key = ka, d = 9, t = 100 }, b = { key = kb, d = 2, t = 100 } }
		local s1, s2 = Sy():BlockSums(g1), Sy():BlockSums(g2)
		ne(s1[Sy().BlockOf(ka)], s2[Sy().BlockOf(ka)])
		if Sy().BlockOf(kb) ~= Sy().BlockOf(ka) then eq(s1[Sy().BlockOf(kb)], s2[Sy().BlockOf(kb)]) end
		eq(#Sy():EncodeBlocks(g1), 288)
	end)

	-- Every client of the simulator holds the records of `n` authors (written straight into each store: all aligned).
	local function fill(sim, n, skip)
		local now = sim:client(1).Mock.ServerTime and sim:client(1).Mock.ServerTime() or 1767225600
		for _, c in ipairs(sim.clients) do
			c:addon().Sync.BLOCK_OVER = 5
			local records = c:addon().Store:Records("accounts")
			for i = 1, n do
				local guid = ("Player-1-%08X"):format(0x50000 + i)
				if not (skip and skip[c.index] and skip[c.index][i]) then
					records[guid] = { id = guid, author = guid, rev = 1, time = 1767225000, token = "T", chars = { { guid = guid } } }
				end
			end
			c:addon().Sync:Invalidate()
		end
	end

	it("a client with many authors sends a BHELLO, under the threshold a HELLO", function()
		local sim = Sim.new{ clients = 2, sync = false, seed = 3 }
		fill(sim, 3)
		local a = sim:client(1)
		a:addon().Sync:SendHello()
		sim:advance(2)
		local types = {}
		for _, e in ipairs(a.Mock.chat.sent) do types[#types + 1] = e.message:match("^%d+|(%u+)|") end
		contains(types, "HELLO")
		local sim2 = Sim.new{ clients = 2, sync = false, seed = 4 }
		fill(sim2, 10)
		local b = sim2:client(1)
		b:addon().Sync:SendHello()
		sim2:advance(5)
		local parts = {}
		for _, e in ipairs(b.Mock.chat.sent) do parts[#parts + 1] = e.message:sub(2) end   -- the AceComm marker of each piece
		local wire = table.concat(parts)
		contains(wire, "BHELLO")
		truthy(#wire <= 512, "a BHELLO is at most 512 B, here " .. #wire)
		truthy(#b.Mock.chat.sent <= 3, "in at most 3 pieces")
	end)

	it("falls back to the per-author HELLO while an officer of an older version is online", function()
		local sim = Sim.new{ clients = 2, officers = { 2 }, sync = false, seed = 5 }
		fill(sim, 10)
		local a = sim:client(1)
		a:addon().Sync.state.present[sim:client(2).name .. "-" .. sim.realmKey] = { guid = sim:client(2):guid(), at = a.Mock.Now and a.Mock.Now() or GetTime(), officer = true }
		truthy(a:addon().Sync:BlocksAllowed(), "an officer heard only through other messages does not count yet")
		a:addon().Sync.state.versions[sim:client(2).name .. "-" .. sim.realmKey] = "0.6.2"
		falsy(a:addon().Sync:BlocksAllowed())
		a:addon().Sync.state.versions[sim:client(2).name .. "-" .. sim.realmKey] = "0.7.0"
		truthy(a:addon().Sync:BlocksAllowed())
	end)

	it("only the designated officer answers a BHELLO, and the sender catches up", function()
		-- client 1 lacks author 3 and has an older author 4; the officers (2, 3) hold everything
		local sim = Sim.new{ clients = 4, officers = { 2, 3 }, sync = false, seed = 7 }
		fill(sim, 12, { [1] = { [3] = true } })
		local four = ("Player-1-%08X"):format(0x50000 + 4)
		for i = 2, 4 do
			local r = sim:client(i):addon().Store:Records("accounts")[four]
			r.rev, r.time = 2, 1767225100
			sim:client(i):addon().Sync:OnStoreChanged("accounts", four, "remote")
		end
		-- the officers know each other and the sender (as after their HELLOs)
		for i = 2, 4 do sim:client(i):addon().Sync:SendHello() end
		sim:advance(70)
		local a = sim:client(1)
		a:addon().Sync:SendHello()
		sim:advance(30)
		local digests = 0
		for i = 2, 4 do digests = digests + sim:client(i):addon().Sync.state.stats.digestsSent end
		eq(digests, 1, "one officer answered")
		eq(a:addon().Sync.state.stats.digestsHeard, 1)
		sim:advance(30)
		local S1 = a:addon().Store
		notNil(S1:Get("accounts", ("Player-1-%08X"):format(0x50000 + 3)), "the missing author arrived")
		eq(S1:Get("accounts", four).rev, 2, "the newer record arrived")
	end)

	it("the summary kept record by record equals the one read whole", function()
		guild(1)   -- an officer: relays and restricted bank tabs are accepted
		local function shot()
			local out = {}
			for _, r in ipairs({ false, true }) do
				for author, g in pairs(Sy():Groups(r)) do out[#out + 1] = tostring(r) .. author .. g.key .. "|" .. g.d .. "|" .. g.t .. "|" .. #g.records end
			end
			table.sort(out)
			return table.concat(out, "\n")
		end
		local function same()
			local kept = shot()
			Sy():Invalidate()
			eq(kept, shot())
		end
		same()
		truthy(S():Put("accounts", ME, { token = "TOKEN", chars = { { guid = ME } } }))
		same()
		bobAccount()
		same()
		truthy(arrive("REC", { s = "accounts", r = { acct(BOB, { BOB, BOBALT }, { rev = 2, time = GetServerTime() + 1 }) } }, "Officer"))
		same()
		-- the contacts record of an id written first by one character of the account, then by the other
		truthy(arrive("REC", { s = "contacts", r = { R{ id = BOB, author = BOB, battleTag = "Bob#1" } } }, "Bob"))
		same()
		truthy(arrive("REC", { s = "contacts", r = { R{ id = BOB, author = BOBALT, rev = 2, battleTag = "Bob#2" } } }, "Bobalt"))
		same()
		eq(Sy():Groups()[BOB] and #Sy():Groups()[BOB].records, 1, "Bob keeps only his accounts record")
		for i = 1, 30 do truthy(S():Put("recipes", ME .. ":" .. i, { char = ME, skillLine = i, ids = { i } })) end
		same()
	end)

	it("an unasked DIGEST is ignored", function()
		guild(3)
		local summary = Sy():EncodeSummary({ { key = 5, d = 1, t = 1 } })
		arrive("DIGEST", { d = { [0] = summary } }, "Officer", "WHISPER")
		eq(Sy().state.stats.digestsHeard, 0)
		eq(Tr():Pending(), 0, "nothing asked, nothing pushed")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- §6.6 Forever full names with a space
---------------------------------------------------------------------------------------------------------------------
local ANNA, LUCA, MARIA = "Player-1-0000A001", "Player-1-00000C01", "Player-1-00000C02"

local function spacedGuild()
	Mock.player.name = "Anna Rossi"
	Mock.guild.Set{ name = "Accord", myRank = 1, members = {
		{ name = "Luca Bianchi", rank = 3, guid = LUCA, level = 60, note = "main: Maria De Santis" },
		{ name = "Maria De Santis-OtherRealm", rank = 4, guid = MARIA, level = 58 },
		{ name = "Bob", rank = 3, guid = BOB, level = 60, note = "alt: luca bianchi, tank" },
		{ name = "Mallory", rank = 3, guid = MAL, level = 60 },
	} }
end

describe("names with a space (SPEC-11 §6.6)", function()
	before_boot(function() spacedGuild() end)

	it("splits the realm at the last hyphen, in one place", function()
		local C = A().Compat
		deepEq({ C.SplitName("Name Surname-Realm") }, { "Name Surname", "Realm" })
		deepEq({ C.SplitName("Name Surname") }, { "Name Surname" })
		deepEq({ C.SplitName("Bob-Realm") }, { "Bob", "Realm" })
		deepEq({ C.SplitName("Bob") }, { "Bob" })
		deepEq({ A().Roster.SplitName("Maria De Santis-OtherRealm") }, { "Maria De Santis", "OtherRealm" })
		truthy(C.PlainName("Name Surname")); truthy(C.PlainName("Bob-Realm"))
		falsy(C.PlainName(" Name")); falsy(C.PlainName("Name  Surname")); falsy(C.PlainName("Name|cff")); falsy(C.PlainName(""))
	end)

	it("the sender: the player itself, a roster member, with and without the realm", function()
		local T_ = Tr()
		truthy(T_.IsSelf("Anna Rossi")); truthy(T_.IsSelf("Anna Rossi-TestRealm"))
		falsy(T_.IsSelf("Anna Rossi-OtherRealm")); falsy(T_.IsSelf("Anna")); falsy(T_.IsSelf("Rossi"))
		eq(S():Member("Luca Bianchi").guid, LUCA)
		eq(S():Member("Luca Bianchi-TestRealm").guid, LUCA)
		eq(S():Member("Maria De Santis-OtherRealm").guid, MARIA)
		isNil(S():Member("Maria De Santis"), "another realm's member needs its realm")
		isNil(S():Member("Luca"))
		eq(A().Roster:ByName("luca bianchi").guid, LUCA)
		eq(A().Roster:ByGUID(MARIA).short, "Maria De Santis")
		-- the player's own echo is no message from someone else
		eq(select(2, Tr():OnReceive(text("REQ", { s = "x" }), "GUILD", "Anna Rossi")), "self")
	end)

	it("public notes: the 3-, then 2-, then 1-word name of a roster member", function()
		local P = A().Accounts.ParseNote
		local roster = { ["luca bianchi"] = 1, ["maria de santis"] = 2, ["bob"] = 3, ["ann"] = 4, ["ann lee"] = 5 }
		local function look(n) return roster[n:lower()] end
		deepEq({ P("alt: Luca Bianchi, tank", look) }, { "alt", "Luca Bianchi", 1 })
		deepEq({ P("main: Maria De Santis | healer", look) }, { "main", "Maria De Santis", 2 })
		deepEq({ P("Main: bob the tank", look) }, { "main", "bob", 3 })
		deepEq({ P("alt: Ann Lee/Ann", look) }, { "alt", "Ann Lee", 5 }, "the longer name wins")
		deepEq({ P("alt: Ann; Lee", look) }, { "alt", "Ann", 4 })
		deepEq({ P("main: Luca Bianchi.", look) }, { "main", "Luca Bianchi", 1 })
		isNil(P("alt: Nobody Here", look))
		isNil(P("main: Luca", look))
		-- the groups read them: Luca's note names Maria (main), Bob's note names Luca (alt)
		local groups = A().Accounts:Groups()
		local found
		for _, g in ipairs(groups) do if g.byGUID[LUCA] and g.byGUID[MARIA] and g.byGUID[BOB] then found = g end end
		notNil(found, "one hinted group of Maria De Santis, Luca Bianchi and Bob")
	end)

	it("/accord debug hides the whole name and each of its words", function()
		local Diag = A().Diagnostics
		local out = Diag.Redact("Anna Rossi-TestRealm whispered Luca Bianchi; Rossi and Bianchi and De Santis left, Maria too")
		falsy(out:find("Anna", 1, true)); falsy(out:find("Rossi", 1, true))
		falsy(out:find("Luca", 1, true)); falsy(out:find("Bianchi", 1, true))
		falsy(out:find("Santis", 1, true)); falsy(out:find("Maria", 1, true))
		contains(out, "De", "a word under 3 characters stays")
		contains(out, "whispered")
	end)

	it("a whisper and an invitation take the whole name", function()
		local told, invited
		ChatFrame_SendTellWithMessage = function(name, msg) told = { name, msg } end
		C_PartyInfo = C_PartyInfo or {}
		local oldInvite = C_PartyInfo.InviteUnit
		C_PartyInfo.InviteUnit = function(name) invited = name end
		truthy(A().Compat.Chat.OpenWhisper("Luca Bianchi", "hello"))
		deepEq(told, { "Luca Bianchi", "hello" })
		truthy(A().Compat.Group.Invite("Luca Bianchi-TestRealm"))
		eq(invited, "Luca Bianchi-TestRealm")
		ChatFrame_SendTellWithMessage = nil
		falsy(A().Compat.Chat.OpenWhisper("Luca Bianchi", "hello"), "no '/w Luca Bianchi hello': it would whisper Luca")
		C_PartyInfo.InviteUnit = oldInvite
	end)

	it("the co-play suggestions show and whisper the whole name", function()
		local told
		ChatFrame_SendTell = function(name) told = name end
		local list = A().Suggest.List({ limit = 10 })
		local names = {}
		for _, s in ipairs(list) do names[#names + 1] = s.name end
		contains(names, "Luca Bianchi")
		truthy(A().Suggest:Whisper(LUCA))
		eq(told, "Luca Bianchi")
		ChatFrame_SendTell = nil
	end)

	it("table cells cut a long name on one line", function()
		local Widgets = A().Widgets
		local t = Widgets.DataTable(UIParent, { { id = "name", title = "Name", width = 60, text = function(d) return d.name end } }, {})
		t:SetData({ { name = "Maria De Santis-OtherRealm" } })
		t:Refresh()
		local cell = t.rows[1].cells[1]
		eq(cell._wordWrap, false)
		cell.IsTruncated = function() return true end
		deepEq(t.CutTexts(t.rows[1]), { "Maria De Santis-OtherRealm" })
	end)
end)

describe("names with a space round-trip through every data set (SPEC-11 §6.6)", function()
	before_boot(function() spacedGuild() end)

	-- a record through the wire: encoded by the codec, decoded, checked by the store
	local function through(set, rec, sender)
		local ok, why = arrive("REC", { s = set, r = { rec } }, sender)
		truthy(ok, why)
		return S():Get(set, rec.id)
	end

	it("accounts: the character names of a record", function()
		local rec = R{ id = LUCA, author = LUCA, token = "TLUCA", main = LUCA,
			chars = { { guid = LUCA, name = "Luca Bianchi", realm = "TestRealm" }, { guid = MAL, name = "Luca Secondo", inGuild = false, guild = "Other Guild" } } }
		local back = through("accounts", rec, "Luca Bianchi")
		deepEq(back.chars, rec.chars)
		-- and the player's own record, as Accounts writes it
		truthy(A().Accounts:RegisterSelf())
		A().Accounts:Publish()
		local own = S():Get("accounts", ANNA)
		notNil(own)
		eq(own.chars[1].name, "Anna Rossi")
	end)

	it("bank logs: 'kind,name,...' with a full name", function()
		local Log = A().BankLog
		local entries = { { kind = "withdraw", name = "Luca Bianchi-TestRealm", itemID = 2589, count = 5, t = 1767225600 },
			{ kind = "deposit", name = "Maria De Santis", itemID = 0, count = 1000, t = 1767222000 } }
		local list = Log.Decode(Log.Encode(entries))
		eq(#list, 2)
		local names = { list[1].name, list[2].name }
		contains(names, "Luca Bianchi-TestRealm"); contains(names, "Maria De Santis")
	end)

	it("bank requests: the requester's name", function()
		local id = LUCA .. ":1"
		through("bankreq", R{ id = id, author = LUCA, requester = LUCA, kind = "withdraw", status = "open", itemID = 2589, count = 2,
			created = GetServerTime(), history = { { s = "open", by = LUCA, t = GetServerTime() } } }, "Luca Bianchi")
		local list = A().BankRequests:List({})
		local found
		for _, r in ipairs(list) do if r.id == id then found = r end end
		notNil(found)
		eq(found.name, "Luca Bianchi")
	end)

	it("the personal backup", function()
		local Acc = A().Accounts
		Acc:RegisterSelf()
		Acc:Register{ guid = "Player-1-0000A002", name = "Anna Seconda", classID = 5, level = 40, guild = A().GuildKey:Current() }
		local exported = A().Backup:Export()
		local content = A().Backup.Decode(exported)
		notNil(content)
		local chars = content.account.chars[GetNormalizedRealmName()]
		eq(chars[ANNA].name, "Anna Rossi")
		eq(chars["Player-1-0000A002"].name, "Anna Seconda")
	end)

	it("the demo guild has two full names and they read back", function()
		local D = A().DemoData.Build(GetServerTime())
		local spaced = {}
		for _, m in ipairs(D.roster or D.members or {}) do if m.name and m.name:find(" ") then spaced[#spaced + 1] = m.name end end
		eq(#spaced >= 2, true)
		for _, n in ipairs(spaced) do eq((A().Compat.SplitName(n)), n:match("^(.-)%-") or n) end
	end)
end)

describe("names with a space between real clients (simulator)", function()
	it("records and pushes by whisper reach a full name", function()
		local sim = Sim.new{ clients = 3, names = { "Anna Rossi", "Luca Bianchi", "Maria De Santis" }, officers = { 3 }, seed = 21 }
		for i = 1, 3 do
			local c = sim:client(i)
			local guid = c:guid()
			truthy(c:addon().Store:Put("accounts", guid, { token = "T" .. i, chars = { { guid = guid, name = c.name } } }))
		end
		sim:advance(400)
		for i = 1, 3 do
			local S_ = sim:client(i):addon().Store
			for j = 1, 3 do
				local r = S_:Get("accounts", sim:client(j):guid())
				notNil(r, i .. " has " .. j)
				eq(r.chars[1].name, sim:client(j).name)
			end
		end
		-- a client that lost its data gets it back by whisper from the officer
		local b = sim:client(2)
		b:logout()
		b.saved = {}
		b:login()
		sim:advance(400)
		notNil(b:addon().Store:Get("accounts", sim:client(1):guid()), "pushed by WHISPER to 'Luca Bianchi'")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- §6.5 the 1000 logins
---------------------------------------------------------------------------------------------------------------------
-- A guild of BURST members, all with the addon (the worst case), 10 officers, all aligned before a restart of the
-- server; they all log in within 60 seconds; in the first 10 minutes 50 of them write something; 1% of the messages are
-- lost, latency 0.05-0.5 s. The clients are lean (Sim option `lean`: libraries, Core and the network layer, which is all
-- that sends anything here) and hold the same record tables (each store indexes its own copy of the references), so a
-- thousand of them fit in memory (with one shared set of roster rows, and the mock's pure decoding shared between
-- them: Sim option `lean`); the roster does not change during the burst, so the server's answer to a roster request
-- (GUILD_ROSTER_UPDATE) is left out. It runs with --long (the Long tests workflow): 3-5 GB of memory and a few minutes.
local BURST = 1000

describe("the 1000 logins (SPEC-11 §6.5)", function()
	it("stay inside the traffic budget and converge", function()
		if not T.long then
			T.log("skipped: a long scenario (3-5 GB of memory, a few minutes); run_tests.py --long or AZACCORD_LONG=1 runs it, so does the Long tests workflow")
			return
		end
		local t0 = Mock.RealClock()
		local N, WRITERS = BURST, 50
		local officers, isOfficer = {}, {}
		for k = 1, 10 do
			officers[k] = math.floor((k - 1) * N / 10) + 1
			isOfficer[officers[k]] = true
		end
		local shared = {}
		for i = 1, N do
			local guid = Sim.guidOf(i)
			shared[guid] = { id = guid, author = guid, rev = 1, time = 1767225000, token = "T" .. i, chars = { { guid = guid } } }
		end
		local sim = Sim.new{ clients = N, officers = officers, lean = true, loginWithin = 60, latency = { 0.05, 0.5 }, loss = 0.01,
			seed = 1000, step = 0.5,
			setup = function(M, i, c) c.E.C_GuildInfo.GuildRoster = function() end end,
			-- a BHELLO is answered only by the designated officer and by the sender's own account (§6.4); here every
			-- character is its own account, so a member that is no officer does nothing with one: its million
			-- deliveries are left out (what one costs a member is measured below, "to handle one")
			skip = function(from, to, t) return t == "BHELLO" and not isOfficer[to.index] and not isOfficer[from.index] end,
			ready = function(c)
				local A_ = c:addon()
				local records = A_.Store:Records("accounts")
				for guid, rec in pairs(shared) do records[guid] = rec end
				A_.Sync:Invalidate()
				A_.Sync:Start()   -- the first HELLO waits with the number of authors it holds now
			end }
		local tBoot = Mock.RealClock()
		-- 50 writers, each once, between the 60th second and the 10th minute
		local writes, order = {}, {}
		for k = 1, WRITERS do
			local i = math.floor(Sim.draw(sim) * N) + 1
			while writes[i] do i = i % N + 1 end
			writes[i] = 60 + Sim.draw(sim) * 540
			order[#order + 1] = i
		end
		table.sort(order, function(a, b) return writes[a] < writes[b] end)
		local maxQueue, nextWrite, lastWrite = 0, 1, 0
		local function sample()
			for _, c in ipairs(sim.clients) do
				if c.online then
					local q = c:addon().Transport:Pending()
					if q > maxQueue then maxQueue = q end
				end
			end
		end
		local function doWrites()
			while order[nextWrite] and writes[order[nextWrite]] <= sim.time do
				local c = sim:client(order[nextWrite])
				local guid = c:guid()
				truthy(c:addon().Store:Put("accounts", guid, { token = "T" .. c.index, chars = { { guid = guid } }, n = 1 }))
				lastWrite = sim.time
				nextWrite = nextWrite + 1
			end
		end
		local function converged()
			for _, i in ipairs(order) do
				local guid = Sim.guidOf(i)
				for _, c in ipairs(sim.clients) do
					local r = c:addon().Store:Get("accounts", guid)
					if not (r and r.rev == 2) then return false end
				end
			end
			return true
		end
		-- the first 30 minutes, in 10-second steps; after the last write, every 30 s: does every client hold every write?
		local done, convergedAt = false, nil
		for step = 1, 180 do
			sim:advance(10)
			doWrites()
			sample()
			if not done and nextWrite > WRITERS and step % 3 == 0 then
				done = converged()
				if done then convergedAt = sim.time end
			end
			if step % 30 == 0 then
				T.log(("  minute %d: %.0f s so far, %.0f MB of Lua heap"):format(step / 6, Mock.RealClock() - t0, collectgarbage("count") / 1024))
			end
		end
		local st = sim:stats()
		local tRun = Mock.RealClock()
		-- then, if needed, until 25 minutes after the last write
		while not done and sim.time < lastWrite + 25 * 60 do
			sim:advance(30)
			sample()
			done = converged()
			if done then convergedAt = sim.time end
		end
		local convergedAfter = (convergedAt or sim.time) - lastWrite
		-- the BHELLO on the wire, and the time to handle one with the blocks in cache
		local c1 = sim:client(2)
		local A1 = c1:addon()
		local bhello = A1.Codec:Encode("BHELLO", { b = A1.Sync:EncodeBlocks(), n = N, av = "@project-version@" })
		local pieces = #A1.Transport.Frame(bhello)
		A1.Sync:BlockSums()
		local msg = A1.Codec:Decode(bhello)
		local tCpu = Mock.RealClock()
		local handled = 0
		for i = 3, math.min(N, 502) do
			A1.Sync:OnMessage(msg, sim:client(i).name, "GUILD")
			handled = handled + 1
		end
		local perBhello = (Mock.RealClock() - tCpu) / handled * 1000
		local dropped, bulk = 0, 0
		local bhellos, digests = 0, 0
		for _, c in ipairs(sim.clients) do
			local ts = c:addon().Transport:Stats()
			dropped = dropped + (ts.droppedBy.overflow or 0)
			bulk = bulk + (ts.droppedBy.expired or 0)
			bhellos = bhellos + c:addon().Sync.state.stats.bhellosSent
			digests = digests + c:addon().Sync.state.stats.digestsSent
		end
		T.log(("%d clients: boot %.0f s, 30 min simulated in %.0f s; BHELLO %d B on the wire (%d pieces), %.3f ms to handle one"):format(
			N, tBoot - t0, tRun - tBoot, #bhello, pieces, perBhello))
		T.log(("  sent per client %.0f B/min on average, %.0f B/min at most; %d BHELLO, %d DIGEST; queue at most %d; converged %.0f s after the last write"):format(
			st.avg.bytesPerMinute, st.max.bytesPerMinute, bhellos, digests, maxQueue, convergedAfter))
		T.log(("  deliveries: %d made, %d lost, %d BHELLO to members left out"):format(sim.delivered, sim.lost, sim.skipped))
		truthy(#bhello <= 512 and pieces <= 3, "BHELLO " .. #bhello .. " B in " .. pieces .. " pieces")
		truthy(st.avg.bytesPerMinute <= 400, "average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 3072, "busiest client " .. st.max.bytesPerMinute)
		truthy(maxQueue <= 100, "queue " .. maxQueue)
		eq(dropped, 0, "nothing dropped for a full queue")
		eq(bulk, 0, "no BULK message expired")
		truthy(done, "converged within 25 minutes of the last write")
		truthy(perBhello <= 1, "a BHELLO took " .. perBhello .. " ms")
	end)
end)

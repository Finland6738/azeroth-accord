-- Likes (M4.2; SPEC-07 §2, LIKE-01..LIKE-09, ADR 0007): the ledger entry and its append-only rules in the store, the
-- notary's checks (double vote, self and alt votes, a new token, another salt), the voter's queue and receipts, totals
-- by distinct pseudonym and the merge after alt linking, and the network simulator (queued votes delivered when an
-- officer logs in, a forged ledger refused, every client showing the same total).
local function A() return AzerothAccord end
local function L() return AzerothAccord.Likes end
local function S() return AzerothAccord.Store end

local ME = "Player-1-0000A001"
local OFF, OFF2 = "Player-1-000000FF", "Player-1-000000F2"
local BOB, BOBALT, CAT, CATALT, DAN, NOADD = "Player-1-00000B0B", "Player-1-00000B0C", "Player-1-00000CA7", "Player-1-00000CA8",
	"Player-1-00000DA1", "Player-1-00000E01"

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank, members = {
		{ name = "Officer", level = 60, rank = 1, guid = OFF }, { name = "Second", level = 60, rank = 1, guid = OFF2 },
		{ name = "Bob", level = 60, rank = 3, guid = BOB }, { name = "Bobalt", level = 20, rank = 4, guid = BOBALT },
		{ name = "Cat", level = 60, rank = 3, guid = CAT }, { name = "Catalt", level = 30, rank = 4, guid = CATALT },
		{ name = "Dan", level = 55, rank = 3, guid = DAN }, { name = "Noaddon", level = 40, rank = 3, guid = NOADD },
	} }
end

-- An `accounts` record as the character itself publishes it, written straight into the store.
local function account(guid, chars, token)
	local list = {}
	for i, g in ipairs(chars or { guid }) do list[i] = { guid = g, name = "C" .. i } end
	local old = S():Get("accounts", guid)
	S():Records("accounts")[guid] = { id = guid, author = guid, rev = (old and old.rev or 0) + 1, time = GetServerTime(),
		token = token or ("TOKEN" .. guid:sub(-4)), chars = list }
	A().Accounts:MarkDirty()
	A().Bus:Emit("STORE_CHANGED", "accounts", guid, "remote")
end

local function world()
	account(ME, { ME }, "MYTOKEN")
	account(BOB, { BOB, BOBALT }, "BOBTOKEN"); account(BOBALT, { BOBALT, BOB }, "BOBTOKEN")
	account(CAT, { CAT, CATALT }, "CATTOKEN"); account(CATALT, { CATALT, CAT }, "CATTOKEN")
	account(DAN, { DAN }, "DANTOKEN")
end

local function salt(byteValue) return A().Config.Base64(string.rep(string.char(byteValue), 32)) end

local function capture()
	local sent = {}
	local T = A().Transport
	local orig = T.Send
	T.Send = function(self, dist, msg, opts)
		sent[#sent + 1] = { dist = dist, msg = msg, opts = opts or {} }
		return orig(self, dist, msg, opts)
	end
	return sent
end

local function present(list)
	local p = {}
	for _, e in ipairs(list) do p[e[1]] = { guid = e[2], at = GetTime(), officer = e[3] == true } end
	A().Sync.state.present = p
end

local function entry(p, target, author, extra)
	local r = { id = p:sub(1, 16) .. ":" .. target, author = author or OFF, rev = 1, time = GetServerTime(), pseudonym = p, target = target,
		day = 20260101 }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

local function put(rec)
	S():Records("likes")[rec.id] = rec
	A().Bus:Emit("STORE_CHANGED", "likes", rec.id, "remote")
end

local P1, P2, P3 = ("1a"):rep(16), ("2b"):rep(16), ("3c"):rep(16)

describe("the ledger entry", function()
	before_boot(function() guild(3) end)

	it("is well formed only with a 32-digit pseudonym, an optional 16-digit tag, a GUID, a day and the id they make", function()
		truthy(L().ValidEntry(entry(P1, CAT)))
		truthy(L().ValidEntry(entry(P1, CAT, OFF, { tag = ("ab"):rep(8) })))
		falsy(L().ValidEntry(entry(P1, CAT, OFF, { tag = "short" })))
		falsy(L().ValidEntry(entry(P1:upper(), CAT)))
		falsy(L().ValidEntry(entry(P1:sub(1, 30), CAT)))
		falsy(L().ValidEntry(entry(P1, "Cat")))
		falsy(L().ValidEntry(entry(P1, CAT, OFF, { day = 1 })))
		falsy(L().ValidEntry(entry(P1, CAT, OFF, { day = 20260101.5 })))
		falsy(L().ValidEntry(entry(P1, CAT, OFF, { rev = 2 })))
		falsy(L().ValidEntry(entry(P1, CAT, OFF, { del = true })))
		falsy(L().ValidEntry(entry(P1, CAT, OFF, { id = P1:sub(1, 16) .. ":" .. DAN })))
	end)

	it("is append-only: never replaced, never revised, and the same entry again is nothing", function()
		local e = entry(P1, CAT)
		truthy(S():Accept("likes", e, { sender = "Officer" }))
		local changed = entry(P1, CAT, OFF, { day = 20260202, time = GetServerTime() + 5 })
		eq(select(2, S():Accept("likes", changed, { sender = "Officer" })), "immutable")
		eq(select(2, S():Accept("likes", entry(P1, CAT, OFF, { rev = 2 }), { sender = "Officer" })), "owner", "an entry has rev 1 only")
		eq(select(2, S():Accept("likes", entry(P1, CAT), { sender = "Second" })), "same")
		eq(S():Get("likes", e.id).day, 20260101)
	end)

	it("a forged ledger is refused: from a member, with a made-up id, or with a deletion", function()
		eq(select(2, S():Accept("likes", entry(P1, CAT), { sender = "Bob" })), "authority")
		eq(select(2, S():Accept("likes", entry(P1, CAT, BOB), { sender = "Bob" })), "authority")
		eq(select(2, S():Accept("likes", entry(P1, CAT, OFF, { id = "x:" .. CAT }), { sender = "Officer" })), "owner")
		eq(select(2, S():Accept("likes", entry(P1, CAT, OFF, { del = true }), { sender = "Officer" })), "owner")
		eq(S():Count("likes"), 0)
	end)

	it("the pseudonym is the first 128 bits of HMAC-SHA256(salt, token)", function()
		local key = string.rep("\11", 20)
		eq(L().Pseudonym(key, "Hi There"), "b0344c61d8db38535ca8afceaf0bf12b")
		eq(#L().Tag(key, BOB), 16)
	end)
end)

describe("totals", function()
	before_boot(function() guild(3) end)

	it("count distinct pseudonyms over every character of the account, on every character", function()
		world()
		put(entry(P1, CAT)); put(entry(P2, CAT)); put(entry(P1, CATALT)); put(entry(P3, DAN))
		eq(L():Total(CAT), 2)
		eq(L():Total(CATALT), 2, "the total shows on every character of the account")
		eq(L():Total(DAN), 1)
		eq(L():Total(BOB), 0)
	end)

	it("merge after alt linking without counting a voter twice", function()
		world()
		account(DAN, { DAN }, "DANTOKEN")
		put(entry(P1, DAN)); put(entry(P1, NOADD)); put(entry(P2, NOADD))
		eq(L():Total(DAN), 1); eq(L():Total(NOADD), 2)
		-- the member installs the addon and the two characters list each other
		account(DAN, { DAN, NOADD }, "DANTOKEN"); account(NOADD, { NOADD, DAN }, "DANTOKEN")
		eq(L():Total(DAN), 2); eq(L():Total(NOADD), 2)
	end)

	it("a member without the addon receives likes on the character (LIKE-09)", function()
		put(entry(P1, NOADD))
		eq(L():Total(NOADD), 1)
	end)

	it("a note that names a main does not join the likes", function()
		world()
		for _, m in ipairs(Mock.guild.members) do if m.name == "Noaddon" then m.note = "main: Dan" end end
		Mock.Fire("GUILD_ROSTER_UPDATE")
		A().Roster:MarkDirty()
		A().Accounts:MarkDirty()
		put(entry(P1, DAN))
		truthy(A().Accounts:GroupOf(NOADD))
		eq(L():Total(NOADD), 0)
		eq(L():Total(DAN), 1)
	end)
end)

describe("the notary", function()
	before_boot(function() guild(1) end)

	local function ready()
		world()
		truthy(A().Notary:AddSalt(salt(7), 1000))
	end

	it("records a vote as one entry with the pseudonym of the voter's token", function()
		ready()
		local r, rec = L():Notarize(BOB, CAT)
		eq(r, "ok")
		local raw = A().Notary:Current()
		eq(rec.pseudonym, L().Pseudonym(raw, "BOBTOKEN"))
		eq(rec.tag, L().Tag(raw, BOB))
		eq(rec.target, CAT); eq(rec.author, ME); eq(rec.day, A().Compat.ServerDay()); eq(rec.rev, 1)
		isNil(rec.voter); isNil(rec.token)
		eq(L():Total(CAT), 1); eq(L():Total(CATALT), 1)
	end)

	it("refuses a double vote: again, from an alt, to an alt", function()
		ready()
		eq(L():Notarize(BOB, CAT), "ok")
		eq(L():Notarize(BOB, CAT), "dup")
		eq(L():Notarize(BOBALT, CAT), "dup")
		eq(L():Notarize(BOB, CATALT), "dup")
		eq(L():Notarize(BOBALT, CATALT), "dup")
		eq(L():Total(CAT), 1)
		eq(L():Notarize(DAN, CAT), "ok")
		eq(L():Total(CAT), 2)
	end)

	it("refuses a double vote after the voter's token changed (a new computer)", function()
		ready()
		eq(L():Notarize(BOB, CAT), "ok")
		account(BOB, { BOB, BOBALT }, "NEWTOKEN"); account(BOBALT, { BOBALT, BOB }, "NEWTOKEN")
		eq(L():Notarize(BOB, CAT), "dup")
		eq(L():Notarize(BOBALT, CAT), "dup")
	end)

	it("refuses a double vote given under another salt of the ring", function()
		ready()
		eq(L():Notarize(BOB, CAT), "ok")
		truthy(A().Notary:AddSalt(salt(3), 500))   -- an older salt shows up: it becomes the current one
		ne(A().Notary:Current(), A().Notary:Salts()[2].raw)
		eq(L():Notarize(BOB, CAT), "dup")
		eq(L():Notarize(DAN, CAT), "ok")
	end)

	it("refuses self and alt votes", function()
		ready()
		eq(L():Notarize(BOB, BOB), "self")
		eq(L():Notarize(BOB, BOBALT), "self")
		eq(L():Notarize(BOBALT, BOB), "self")
		account(DAN, { DAN }, "BOBTOKEN")
		eq(L():Notarize(BOB, DAN), "conflict", "another account publishes the voter's token: nothing is recorded")
		eq(L():Notarize(DAN, CAT), "conflict")
		eq(S():Count("likes"), 0)
	end)

	it("refuses a target outside the guild, an unknown voter, and works only with a salt", function()
		world()
		eq(L():Notarize(BOB, CAT), "nosalt")
		truthy(A().Notary:AddSalt(salt(7), 1000))
		eq(L():Notarize(BOB, "Player-1-00099999"), "target")
		eq(L():Notarize(BOB, "nonsense"), "target")
		eq(L():Notarize(NOADD, CAT), "unknown", "no account record: a member without the addon cannot vote (LIKE-09)")
		eq(L():Notarize("Player-1-00099999", CAT), "unknown")
	end)

	it("answers a VOTE by whisper with a receipt carrying the entry, at most 20 a minute per sender", function()
		ready()
		local sent = capture()
		L():OnMessage({ t = "VOTE", g = CAT, n = "abcd0001" }, "Bob", "WHISPER")
		Mock.Advance(1)
		local receipt = sent[#sent]
		eq(receipt.dist, "WHISPER"); eq(receipt.opts.target, "Bob")
		eq(receipt.msg.t, "LEDGER"); eq(receipt.msg.r, "ok"); eq(receipt.msg.g, CAT); eq(receipt.msg.n, "abcd0001")
		eq(receipt.msg.e.target, CAT)
		for i = 1, 20 do L():OnMessage({ t = "VOTE", g = DAN, n = "x" }, "Bob", "WHISPER") end
		eq(sent[#sent].msg.r, "rate")
		L():OnMessage({ t = "VOTE", g = CAT }, "Bob", "GUILD")
		eq(L().state.stats.votesHeard, 21, "a vote on GUILD is not even heard")
	end)

	it("a member's client never notarizes", function()
		ready()
		Mock.guild.SetMyRank(3)
		local sent = capture()
		L():OnMessage({ t = "VOTE", g = CAT, n = "1" }, "Bob", "WHISPER")
		eq(#sent, 0)
		eq(L():Notarize(BOB, CAT), "nosalt")
	end)
end)

describe("the voter", function()
	before_boot(function() guild(3) end)

	it("queues a vote while no officer is online and shows it as pending (LIKE-05)", function()
		world()
		local sent = capture()
		truthy(L():Give(CAT))
		eq(L():StateOf(CAT), "pending"); eq(L():StateOf(CATALT), "pending")
		deepEq(L():Pending(), { CAT })
		eq(#sent, 0)
		eq(select(2, L():Give(CAT)), "pending")
		eq(select(2, L():Give(CATALT)), "pending")
	end)

	it("never likes itself, its own alts, or somebody outside the guild", function()
		world()
		account(ME, { ME, "Player-1-0000A002" }, "MYTOKEN")
		eq(select(2, L():Give(ME)), "self")
		eq(L():StateOf("Player-1-0000A002"), "self")
		eq(select(2, L():Give("Player-1-00099999")), "nobody")
		eq(L():StateOf(BOB), "can")
	end)

	it("whispers the vote to one officer and settles on the receipt: the button goes from every character", function()
		world()
		present({ { "Officer", OFF, true }, { "Bob", BOB, false } })
		local sent = capture()
		truthy(L():Give(CAT))
		Mock.Advance(1)
		local votes = {}
		for _, e in ipairs(sent) do if e.msg.t == "VOTE" then votes[#votes + 1] = e end end
		eq(#votes, 1)
		eq(votes[1].dist, "WHISPER"); eq(votes[1].opts.target, "Officer"); eq(votes[1].msg.g, CAT)
		eq(votes[1].opts.ttl, L().VOTE_TTL)
		local results = {}
		A().Bus:On("LIKE_RESULT", function(g, r) results[#results + 1] = r end)
		L():OnMessage({ t = "LEDGER", g = CAT, n = votes[1].msg.n, r = "ok", e = entry(P1, CAT) }, "Officer", "WHISPER")
		eq(L():StateOf(CAT), "given"); eq(L():StateOf(CATALT), "given")
		deepEq(L():Pending(), {})
		deepEq(results, { "ok" })
		eq(L():Total(CAT), 1, "the entry in the receipt counts at once")
		eq(select(2, L():Give(CATALT)), "given")
	end)

	it("ignores receipts from a member, for another nonce, or for a vote it did not give", function()
		world()
		present({ { "Officer", OFF, true } })
		local sent = capture()
		L():Give(CAT)
		local n = sent[#sent].msg.n
		L():OnMessage({ t = "LEDGER", g = CAT, n = n, r = "ok" }, "Bob", "WHISPER")
		L():OnMessage({ t = "LEDGER", g = CAT, n = "other", r = "ok" }, "Officer", "WHISPER")
		L():OnMessage({ t = "LEDGER", g = DAN, n = n, r = "ok" }, "Officer", "WHISPER")
		L():OnMessage({ t = "LEDGER", g = CAT, n = n, r = "weird" }, "Officer", "WHISPER")
		eq(L():StateOf(CAT), "pending")
		eq(L().state.stats.ignored, 4)
	end)

	it("a refusal as dup still hides the button; self and conflict drop the vote", function()
		world()
		present({ { "Officer", OFF, true } })
		local sent = capture()
		L():Give(CAT); L():Give(DAN); L():Give(BOB)
		local n = {}
		for _, e in ipairs(sent) do n[e.msg.g] = e.msg.n end
		L():OnMessage({ t = "LEDGER", g = CAT, n = n[CAT], r = "dup" }, "Officer", "WHISPER")
		L():OnMessage({ t = "LEDGER", g = DAN, n = n[DAN], r = "self" }, "Officer", "WHISPER")
		L():OnMessage({ t = "LEDGER", g = BOB, n = n[BOB], r = "conflict" }, "Officer", "WHISPER")
		eq(L():StateOf(CAT), "given")
		eq(L():StateOf(DAN), "can")
		eq(L():StateOf(BOB), "can")
		deepEq(L():Pending(), {})
	end)

	it("tries the next officer when one has no salt or does not answer", function()
		world()
		L().AUTO = true
		present({ { "Officer", OFF, true }, { "Second", OFF2, true } })
		local sent = capture()
		L():Give(CAT)
		local first = sent[#sent]
		L():OnMessage({ t = "LEDGER", g = CAT, n = first.msg.n, r = "nosalt" }, first.opts.target, "WHISPER")
		Mock.Advance(L().TICK + 1)
		local second = sent[#sent]
		eq(second.msg.t, "VOTE"); ne(second.opts.target, first.opts.target)
		-- the second officer says nothing: it is skipped for RETRY_SILENT, while the first one (no salt yet) is asked
		-- again after RETRY_SOON
		Mock.Advance(L().WAIT_RECEIPT + L().TICK)
		local third = sent[#sent]
		eq(third.msg.t, "VOTE"); eq(third.opts.target, first.opts.target)
		eq(L():StateOf(CAT), "pending")
	end)

	it("an officer holding the salt notarizes its own vote", function()
		Mock.guild.SetMyRank(1)
		world()
		truthy(A().Notary:AddSalt(salt(7), 1000))
		local sent = capture()
		truthy(L():Give(CAT))
		eq(L():StateOf(CAT), "given")
		eq(L():Total(CAT), 1)
		for _, e in ipairs(sent) do ne(e.msg.t, "VOTE") end
	end)

	it("the queue and the given likes survive a reload, for every character of the account", function()
		world()
		L():Give(CAT)
		Mock.Reload()
		eq(L():StateOf(CAT), "pending")
		deepEq(L():Pending(), { CAT })
	end)
end)

describe("likes in the network simulator", function()
	-- client 1 is the officer; 2 and 3 vote for 4; 5 only watches
	local function totals(sim, target)
		local out = {}
		for i = 1, sim:count() do
			local c = sim:client(i)
			if c.online then out[#out + 1] = c:addon().Likes:Total(target) end
		end
		return out
	end

	it("votes wait while no officer is online, then two clients like a third and every client shows the same total", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 1 }, seed = 61, latency = { 0.05, 0.3 }, accounts = true,
			notary = true, likes = true }
		sim:advance(60)
		local target = sim:client(4):guid()
		truthy(sim:client(2):addon().Likes:Give(target))
		truthy(sim:client(3):addon().Likes:Give(target))
		sim:advance(60)
		eq(sim:client(2):addon().Likes:StateOf(target), "pending")
		eq(sim:client(2):addon().Likes:Total(target), 0)
		sim:client(1):login()
		local done = sim:advanceUntil(function()
			for _, t in ipairs(totals(sim, target)) do if t ~= 2 then return false end end
			return true
		end, 600)
		truthy(done, "totals: " .. table.concat(totals(sim, target), ","))
		eq(sim:client(2):addon().Likes:StateOf(target), "given")
		eq(sim:client(3):addon().Likes:StateOf(target), "given")
		eq(sim:client(1):addon().Store:Count("likes"), 2)
		-- the ledger names no voter
		for _, rec in pairs(sim:client(5):addon().Store:Records("likes")) do
			isNil(rec.voter); ne(rec.author, sim:client(2):guid()); ne(rec.author, sim:client(3):guid())
		end
	end)

	it("a forged ledger sent on GUILD by a member is refused everywhere; a second vote through another officer is a dup", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, seed = 67, latency = 0.1, accounts = true, notary = true, likes = true }
		sim:advance(120)
		local target = sim:client(4):guid()
		truthy(sim:client(3):addon().Likes:Give(target))
		truthy(sim:advanceUntil(function() return sim:client(4):addon().Likes:Total(target) == 1 end, 300))
		-- both officers hold the same entry and the same salt; the other one refuses the same voter again
		local other = sim:client(1):addon().Store:Count("likes") == 1 and sim:client(2) or sim:client(1)
		truthy(sim:advanceUntil(function() return other:addon().Store:Count("likes") == 1 end, 120))
		eq(other:addon().Likes:Notarize(sim:client(3):guid(), target), "dup")
		-- client 3 (a member) forges an entry
		local fake = { id = ("ee"):rep(8) .. ":" .. target, author = sim:client(1):guid(), rev = 1, time = 1767225700,
			pseudonym = ("ee"):rep(16), target = target, day = 20260101 }
		sim:client(3):addon().Transport:Send("GUILD", { t = "REC", s = "likes", r = { fake } })
		sim:advance(10)
		for i = 1, 4 do
			if i ~= 3 then eq(sim:client(i):addon().Likes:Total(target), 1, "client " .. i) end
		end
		truthy(sim:client(4):addon().Store.stats.reasons.authority >= 1)
	end)
end)

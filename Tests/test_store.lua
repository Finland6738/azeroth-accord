-- Store (M1.6): data sets, versions, the trust rules NET-10..NET-13 of SPEC-02 §6 (ADR 0005, 0006) and retention.
-- The guild below has a member and its alt (Bob, Bobalt), a cheater (Mallory), an officer and the Guild Master.
-- Sender names are what AceComm gives: "Name" for the same realm, "Name-Realm" otherwise.
local function S() return AzerothAccord.Store end

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

local function acct(guid, chars, token)
	local list = {}
	for i, g in ipairs(chars or { guid }) do list[i] = { guid = g } end
	return R{ id = guid, author = guid, token = token or ("T" .. guid:sub(-3)), chars = list }
end

local function accept(set, rec, sender)
	return S():Accept(set, rec, { sender = sender })
end

-- Bob and Bobalt are one account: each publishes its own record listing both.
local function bobAccount()
	truthy(accept("accounts", acct(BOB, { BOB, BOBALT }, "BOBTOKEN"), "Bob"))
	truthy(accept("accounts", acct(BOBALT, { BOBALT, BOB }, "BOBTOKEN"), "Bobalt"))
end

describe("shape and sender", function()
	before_boot(function(M) M.guild.Set{ name = "Accord", myRank = 3, members = { { name = "Bob", rank = 3, guid = BOB } } } end)

	it("refuses malformed records", function()
		local cases = {
			{ R{ author = BOB }, "id" },
			{ R{ id = BOB, author = "Bob" }, "author" },
			{ R{ id = BOB, author = BOB, rev = 0 }, "rev" },
			{ R{ id = BOB, author = BOB, rev = 1.5 }, "rev" },
			{ R{ id = BOB, author = BOB, time = "now" }, "time" },
			{ R{ id = BOB, author = BOB, time = GetServerTime() + 7200 }, "future" },
			{ R{ id = BOB, author = BOB, token = "T", chars = { { guid = BOB } }, pad = ("x"):rep(5000) }, "size" },
		}
		for _, c in ipairs(cases) do
			local ok, why = accept("accounts", c[1], "Bob")
			falsy(ok)
			eq(why, c[2])
		end
		eq(select(2, accept("nope", acct(BOB), "Bob")), "set")
	end)

	it("refuses a sender who is not in this client's roster", function()
		eq(select(2, accept("accounts", acct(BOB), "Stranger")), "sender")
		eq(select(2, accept("accounts", acct(BOB), "Bob-OtherRealm")), "sender")
		truthy(accept("accounts", acct(BOB), "Bob-TestRealm"))
	end)
end)

describe("NET-10: first hand", function()
	before_boot(function(M) guild() end)

	it("accepts a character's own account record and puts it on the Bus", function()
		local seen = {}
		AzerothAccord.Bus:On("STORE_CHANGED", function(set, id, origin) seen[#seen + 1] = set .. "|" .. id .. "|" .. origin end)
		truthy(accept("accounts", acct(BOB), "Bob"))
		deepEq(seen, { "accounts|" .. BOB .. "|remote" })
		eq(S():Get("accounts", BOB).token, "TB0B")
	end)

	it("refuses an account record that does not list its own character", function()
		eq(select(2, accept("accounts", acct(BOB, { BOBALT }), "Bob")), "owner")
	end)

	it("refuses an account record sent by somebody else (a forged author)", function()
		eq(select(2, accept("accounts", acct(BOB), "Mallory")), "relay")
		isNil(S():Get("accounts", BOB))
	end)

	it("proves an account only by mutual listing", function()
		bobAccount()
		truthy(S():SameAccount(BOB, BOBALT))
		truthy(S():SameAccount(BOBALT, BOB))
		-- Mallory copies Bob's public token and lists Bob as her alt: Bob's own record does not list her back
		truthy(accept("accounts", acct(MAL, { MAL, BOB }, "BOBTOKEN"), "Mallory"))
		falsy(S():SameAccount(MAL, BOB))
		eq(S():TokenOf(MAL), S():TokenOf(BOB), "the token alone proves nothing")
	end)

	it("an alt may pass on its account's records", function()
		bobAccount()
		truthy(accept("recipes", R{ id = BOB .. ":171", author = BOB, char = BOB, skillLine = 171, ids = { 2330 } }, "Bobalt"))
		truthy(accept("contacts", R{ id = BOB, author = BOBALT, account = "BOBTOKEN", battleTag = "Bob#1" }, "Bobalt"))
	end)

	it("refuses records written for another account, whoever claims to be the author", function()
		bobAccount()
		truthy(accept("accounts", acct(MAL, { MAL, BOB }, "BOBTOKEN"), "Mallory"))
		-- Mallory as the author of Bob's contacts: Bob is not her account
		eq(select(2, accept("contacts", R{ id = BOB, author = MAL, battleTag = "Evil#666" }, "Mallory")), "owner")
		-- Mallory with Bob as the author: not first hand
		eq(select(2, accept("contacts", R{ id = BOB, author = BOB, battleTag = "Evil#666" }, "Mallory")), "relay")
		eq(select(2, accept("recipes", R{ id = BOB .. ":171", author = BOB, char = BOB, skillLine = 171 }, "Mallory")), "relay")
		eq(select(2, accept("recipes", R{ id = BOB .. ":171", author = MAL, char = BOB, skillLine = 171 }, "Mallory")), "owner")
		isNil(S():Get("contacts", BOB))
		isNil(S():Get("recipes", BOB .. ":171"))
		eq(S().stats.reasons.relay, 2)
	end)
end)

describe("NET-11: relays only from officers", function()
	before_boot(function(M) guild() end)

	it("an officer may pass on another member's records", function()
		truthy(accept("accounts", acct(BOB), "Officer"))
		truthy(accept("accounts", acct(BOBALT, { BOBALT, BOB }), "Boss"))
	end)

	it("a member may not", function()
		eq(select(2, accept("accounts", acct(BOB), "Bobalt")), "relay", "not before the account is proved")
		eq(select(2, accept("accounts", acct(OFF), "Bob")), "relay")
	end)

	it("an officer relay still follows the owner rule of the set", function()
		eq(select(2, accept("contacts", R{ id = BOB, author = MAL, battleTag = "Evil#666" }, "Officer")), "owner")
	end)

	it("follows the receiver's own roster: a demoted officer relays no more", function()
		truthy(accept("accounts", acct(BOB), "Officer"))
		for _, m in ipairs(Mock.guild.members) do if m.name == "Officer" then m.rank = 3 end end
		Mock.Fire("GUILD_ROSTER_UPDATE")
		eq(select(2, accept("accounts", acct(BOBALT), "Officer")), "relay")
	end)
end)

describe("NET-12: authority", function()
	before_boot(function(M) guild() end)

	it("accepts the likes ledger only from officers; an entry stays valid after its notary stopped being one", function()
		local P = ("ab"):rep(16)
		local function entry(p, author, target)
			return R{ id = p:sub(1, 16) .. ":" .. target, author = author, pseudonym = p, target = target, day = 20260101 }
		end
		eq(select(2, accept("likes", entry(P, OFF, BOB), "Bob")), "authority")
		truthy(accept("likes", entry(P, OFF, BOB), "Boss"))
		truthy(accept("likes", entry(("cd"):rep(16), "Player-1-00000999", BOB), "Officer"), "the notary left the guild (LIKE-07)")
		eq(select(2, accept("likes", R{ id = "L2", author = OFF, pseudonym = P, target = MAL, day = 20260101 }, "Officer")), "owner",
			"an id that does not follow from the entry")
	end)

	it("lets a member open and cancel a request, and only officers decide it", function()
		truthy(accept("bankreq", R{ id = "Q1", author = BOB, requester = BOB, status = "open", kind = "withdraw" }, "Bob"))
		eq(select(2, accept("bankreq", R{ id = "Q1", author = BOB, requester = BOB, status = "approved", rev = 2 }, "Bob")), "authority")
		truthy(accept("bankreq", R{ id = "Q1", author = OFF, requester = BOB, status = "approved", rev = 2 }, "Officer"))
		eq(select(2, accept("bankreq", R{ id = "Q2", author = MAL, requester = BOB, status = "open" }, "Mallory")), "owner")
		truthy(accept("bankreq", R{ id = "Q1", author = BOB, requester = BOB, status = "cancelled", rev = 3 }, "Bob"))
	end)

	it("restricted bank tabs come only from officers", function()
		local function tab(author, n, extra)
			return R{ id = author .. ":t" .. n, author = author, kind = "tab", tab = n, rank = 3, it = "1.2589.20", n = 1, restricted = extra }
		end
		truthy(accept("bank", tab(BOB, 1), "Bob"))
		eq(select(2, accept("bank", tab(BOB, 6, true), "Bob")), "restricted", "a member's client never holds an officer's tab")
		eq(select(2, accept("bank", tab(OFF, 6, true), "Officer")), "restricted")
		guild(1)   -- the same checks on an officer's client
		AzerothAccord.Role:Refresh()
		eq(select(2, accept("bank", tab(BOB, 6, true), "Bob")), "authority", "a member is no authority")
		truthy(accept("bank", tab(OFF, 6, true), "Officer"))
		eq(select(2, accept("bank", R{ id = BOB .. ":t2", author = OFF, kind = "tab", tab = 2, it = "", n = 0 }, "Officer")), "owner",
			"an id that is not the author's")
	end)
end)

describe("NET-13: co-play observations", function()
	before_boot(function(M) guild() end)

	local function obs(observer, pairsTable, day, sender)
		return accept("coplay", R{ id = observer .. ":" .. day, author = observer, observer = observer, day = day, pairs = pairsTable }, sender)
	end

	it("accepts an observer who is in an observed pair", function()
		truthy(obs(BOB, { [BOB .. ":" .. MAL] = 30, [MAL .. ":" .. OFF] = 30 }, 20260101, "Bob"))
	end)

	it("refuses an observer who is in no pair, or an observation in somebody else's name", function()
		eq(select(2, obs(BOB, { [MAL .. ":" .. OFF] = 30 }, 20260101, "Bob")), "observer")
		eq(select(2, accept("coplay", R{ id = "x", author = BOB, observer = MAL, pairs = { [BOB .. ":" .. MAL] = 5 } }, "Bob")), "observer")
		eq(select(2, obs(BOB, { [BOB .. ":" .. MAL] = 30 }, 20260101, "Mallory")), "relay")
	end)

	it("combines observers with the maximum, never the sum", function()
		local pair = BOB .. ":" .. MAL
		truthy(obs(BOB, { [pair] = 30 }, 20260101, "Bob"))
		truthy(obs(MAL, { [pair] = 45 }, 20260101, "Mallory"))
		truthy(obs(MAL, { [pair] = 99 }, 20260102, "Mallory"))
		deepEq(S():MergeMax(20260101), { [pair] = 45 })
	end)
end)

describe("versions", function()
	before_boot(function(M) guild() end)

	it("keeps the highest rev, ignores older and equal versions", function()
		truthy(accept("accounts", acct(BOB), "Bob"))
		local newer = acct(BOB)
		newer.rev, newer.main = 3, BOB
		truthy(accept("accounts", newer, "Bob"))
		local ok, why = accept("accounts", acct(BOB), "Bob")
		falsy(ok); eq(why, "older")
		ok, why = accept("accounts", newer, "Bob")
		falsy(ok); eq(why, "same")
		eq(S():Get("accounts", BOB).rev, 3)
		eq(S().stats.rejected, 0, "older and equal versions are not refusals")
	end)

	it("breaks a tie of rev by time, then by author, the same way on every client", function()
		local a, b = { rev = 2, time = 10, author = "A" }, { rev = 2, time = 11, author = "A" }
		eq(S().Compare(b, a), 1)
		eq(S().Compare(a, b), -1)
		eq(S().Compare({ rev = 2, time = 10, author = "B" }, a), 1)
		eq(S().Compare(a, { rev = 2, time = 10, author = "A" }), 0)
		eq(S().Compare(a, nil), 1)
	end)

	it("Receive takes a batch and counts what it refused", function()
		local accepted, rejected = S():Receive("accounts", { acct(BOB), acct(MAL), acct(BOB) }, "Bob", "GUILD")
		eq(accepted, 1)
		eq(rejected, 1)
		eq(select(2, S():Receive("accounts", "junk", "Bob")), 1)
	end)
end)

describe("local writes", function()
	before_boot(function(M) guild() end)

	it("Put sets author, rev and time and goes on the Bus as local", function()
		local seen
		AzerothAccord.Bus:On("STORE_CHANGED", function(set, id, origin) seen = origin end)
		local rec = S():Put("accounts", ME, { token = "MINE", chars = { { guid = ME } } })
		eq(rec.author, ME); eq(rec.rev, 1); eq(rec.time, GetServerTime())
		eq(seen, "local")
		eq(S():Put("accounts", ME, { token = "MINE", chars = { { guid = ME } } }).rev, 2)
	end)

	it("Put refuses what the owner rule refuses and what is too large", function()
		eq(select(2, S():Put("accounts", BOB, { token = "X", chars = { { guid = BOB } } })), "owner")
		eq(select(2, S():Put("contacts", ME, { note = ("x"):rep(600) })), "size")
		eq(select(2, S():Put("nope", "x", {})), "set")
	end)

	it("needs a guild", function()
		Mock.guild.Leave()
		eq(select(2, S():Put("accounts", ME, { token = "MINE", chars = { { guid = ME } } })), "guild")
	end)
end)

describe("per guild and retention", function()
	it("keeps the records of each guild apart", function()
		guild()
		truthy(accept("accounts", acct(BOB), "Bob"))
		Mock.guild.Set{ name = "Other", myRank = 3, members = { { name = "Bob", rank = 3, guid = BOB } } }
		isNil(S():Get("accounts", BOB))
		eq(S():Count("accounts"), 0)
		guild()
		notNil(S():Get("accounts", BOB))
	end)

	it("drops old co-play, closed requests, old bank logs and deletions, and keeps the rest", function()
		guild(1)
		local now, day = GetServerTime(), 86400
		local sets = AzerothAccord.GuildKey:Data().store and AzerothAccord.GuildKey:Data().store.sets or nil
		S():Records("coplay")["old"] = { id = "old", time = now - 91 * day }
		S():Records("coplay")["new"] = { id = "new", time = now - 89 * day }
		S():Records("bankreq")["closed"] = { id = "closed", status = "fulfilled", time = now - 61 * day }
		S():Records("bankreq")["open"] = { id = "open", status = "open", time = now - 200 * day }
		S():Records("bank")["log"] = { id = "log", kind = "log", time = now - 366 * day }
		S():Records("bank")["tab"] = { id = "tab", kind = "tab", time = now - 89 * day }
		S():Records("bank")["oldtab"] = { id = "oldtab", kind = "tab", time = now - 91 * day }
		S():Records("contacts")["gone"] = { id = "gone", del = true, time = now - 61 * day }
		eq(S():Prune(), 5)
		isNil(S():Get("coplay", "old")); notNil(S():Get("coplay", "new"))
		isNil(S():Get("bankreq", "closed")); notNil(S():Get("bankreq", "open"))
		isNil(S():Get("bank", "log")); notNil(S():Get("bank", "tab")); isNil(S():Get("bank", "oldtab"))
		isNil(S():Get("contacts", "gone"))
	end)

	it("refuses a received record that retention would drop at once", function()
		guild()
		local old = { id = BOB .. ":1", author = BOB, observer = BOB, rev = 1, time = GetServerTime() - 100 * 86400, day = 1,
			pairs = { [BOB .. ":" .. MAL] = 5 } }
		eq(select(2, accept("coplay", old, "Bob")), "expired")
	end)

	it("survives a reload and reports counts without names", function()
		guild()
		truthy(accept("accounts", acct(BOB), "Bob"))
		Mock.Reload()
		notNil(S():Get("accounts", BOB))
		Mock.ClearOutput()
		Mock.Slash("/accord debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Store: accounts 1")
		falsy(text:find("Bob", 1, true))
		falsy(text:find(BOB, 1, true))
	end)
end)

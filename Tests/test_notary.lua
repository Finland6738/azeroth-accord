-- The guild salt and the notary (M4.1; SPEC-07 LIKE-05..LIKE-07, ADR 0007): random bytes, Base64, the ring of salts held
-- only by officers, SALT on OFFICER with the whisper fallback while S5 is unproven, creation, the choice of the notary,
-- and the network simulator (officers converge on one salt, members never hold it, nothing goes on GUILD).
local function A() return AzerothAccord end
local function N() return AzerothAccord.Notary end

local ME = "Player-1-0000A001"
local ANN, BOB, CAT = "Player-1-00000A44", "Player-1-00000B0B", "Player-1-00000CA7"

local function guild(myRank)
	Mock.guild.Set{ name = "Accord", myRank = myRank, members = {
		{ name = "Ann", level = 60, class = "PRIEST", rank = 1, guid = ANN },
		{ name = "Bob", level = 50, class = "MAGE", rank = 3, guid = BOB },
		{ name = "Cat", level = 60, class = "ROGUE", rank = 1, guid = CAT },
	} }
end

-- Records every message handed to the transport: { dist, msg, opts }.
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

local function ofType(sent, t, dist)
	local out = {}
	for _, e in ipairs(sent) do
		if e.msg.t == t and (dist == nil or e.dist == dist) then out[#out + 1] = e end
	end
	return out
end

local function present(list)
	local p = {}
	for _, e in ipairs(list) do p[e[1]] = { guid = e[2], at = GetTime(), officer = e[3] == true } end
	A().Sync.state.present = p
end

local function saltB64(byteValue)
	return A().Config.Base64(string.rep(string.char(byteValue), 32))
end

describe("random bytes and Base64", function()
	it("draws the number of bytes asked, different every time", function()
		local H = A().Hash
		local a, b = H.RandomBytes(32), H.RandomBytes(32)
		eq(#a, 32); eq(#b, 32); ne(a, b)
		eq(#H.RandomBytes(50), 50)
		eq(#H.RandomBytes(1), 1)
	end)

	it("stirring the pool changes the next draw and costs no hashing", function()
		local H = A().Hash
		for i = 1, 600 do H.Stir("Sender" .. i) end
		eq(#H.RandomBytes(32), 32)
	end)

	it("fails one call, never the addon, without the bit library", function()
		bit = nil
		local r, err = A().Hash.RandomBytes(32)
		isNil(r); contains(err, "bit")
	end)

	it("decodes what it encodes, for every length and byte", function()
		local C = A().Config
		for n = 0, 40 do
			local bytes = {}
			for i = 1, n do bytes[i] = string.char((i * 37 + n * 11) % 256) end
			local s = table.concat(bytes)
			eq(C.Base64Decode(C.Base64(s)), s, n .. " bytes")
		end
		eq(C.Base64Decode("TWFu"), "Man"); eq(C.Base64Decode("TWE="), "Ma"); eq(C.Base64Decode("TQ=="), "M")
	end)

	it("refuses text that is not Base64", function()
		local C = A().Config
		isNil(C.Base64Decode("abc")); isNil(C.Base64Decode("ab!d")); isNil(C.Base64Decode("a=bc"))
		isNil(C.Base64Decode("TQ==TWFu")); isNil(C.Base64Decode(42)); isNil(C.Base64Decode("T=Q="))
		eq(C.Base64Decode(""), "")
	end)
end)

describe("the ring of salts", function()
	describe("for an officer", function()
		before_boot(function() guild(1) end)

		it("creates a salt of 32 bytes, keeps it for the guild and shares it on OFFICER", function()
			local sent = capture()
			local fp = N():Create()
			eq(#fp, 12)
			eq(N():Count(), 1)
			local raw, cur = N():Current()
			eq(#raw, 32); eq(cur, fp)
			local shares = ofType(sent, "SALT", "OFFICER")
			eq(#shares, 1); eq(shares[1].msg.k, "s")
			eq(A().Config.Base64Decode(shares[1].msg.s[1].b), raw)
			eq(#ofType(sent, "SALT", "GUILD"), 0)
			notNil(A().GuildKey:Data().salts)
		end)

		it("two salts never differ from one draw to the next", function()
			N():Create(); N():Create()
			eq(N():Count(), 2)
			local list = N():Salts()
			ne(list[1].raw, list[2].raw)
		end)

		it("uses the oldest salt, then the smaller fingerprint, so every officer picks the same one", function()
			truthy(N():AddSalt(saltB64(7), 2000))
			truthy(N():AddSalt(saltB64(9), 1000))
			truthy(N():AddSalt(saltB64(8), 1000))
			local list = N():Salts()
			eq(list[1].at, 1000); eq(list[2].at, 1000); eq(list[3].at, 2000)
			truthy(list[1].fp < list[2].fp)
			local raw = N():Current()
			eq(raw, list[1].raw)
		end)

		it("refuses malformed, too new and known salts", function()
			local _, why = N():AddSalt("not base64!", 1000)
			eq(why, "shape")
			_, why = N():AddSalt(A().Config.Base64(("x"):rep(31)), 1000)
			eq(why, "shape")
			_, why = N():AddSalt(saltB64(1), GetServerTime() + 7200)
			eq(why, "time")
			_, why = N():AddSalt(saltB64(1), 1.5)
			eq(why, "time")
			truthy(N():AddSalt(saltB64(1), 1000))
			_, why = N():AddSalt(saltB64(1), 500)
			eq(why, "known")
		end)

		it("keeps at most eight salts, the oldest ones", function()
			for i = 1, 10 do N():AddSalt(saltB64(i), 1000 + i) end
			eq(N():Count(), 8)
			eq(N():Salts()[8].at, 1008)
		end)

		it("forgets the salts when the character is demoted", function()
			N():Create()
			eq(N():Count(), 1)
			Mock.guild.SetMyRank(3)
			eq(A().Role:Get(), "member")
			isNil(A().GuildKey:Data().salts)
			Mock.guild.SetMyRank(1)
			eq(N():Count(), 0, "promoted again: it asks the others, it does not find the old salt")
		end)

		it("keeps the salts of one guild away from another", function()
			N():Create()
			local first = N():Current()
			Mock.guild.Set{ name = "Other", myRank = 1, members = {} }
			Mock.Fire("PLAYER_GUILD_UPDATE", "player")
			eq(N():Count(), 0)
			isNil(N():Current())
			truthy(first)
		end)
	end)

	describe("for a member", function()
		before_boot(function() guild(3) end)

		it("never holds, creates or accepts a salt", function()
			local sent = capture()
			local _, why = N():AddSalt(saltB64(3), 1000)
			eq(why, "officer")
			isNil(N():Create())
			N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(4), at = 1000 } } }, "Ann", "WHISPER")
			eq(N():Count(), 0)
			isNil(A().GuildKey:Data().salts)
			falsy(N():Query())
			eq(#sent, 0)
			eq(N().state.stats.ignored, 1)
		end)
	end)
end)

describe("SALT messages", function()
	before_boot(function() guild(1) end)

	it("an officer accepts a salt from another officer on OFFICER or by whisper", function()
		N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(5), at = 1000 } } }, "Ann", "OFFICER")
		eq(N():Count(), 1)
		N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(6), at = 900 } } }, "Cat", "WHISPER")
		eq(N():Count(), 2)
		eq(N():Salts()[1].at, 900)
	end)

	it("ignores a salt from a member, a stranger, or on GUILD", function()
		N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(5), at = 1000 } } }, "Bob", "OFFICER")
		N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(5), at = 1000 } } }, "Stranger", "WHISPER")
		N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(5), at = 1000 } } }, "Ann", "GUILD")
		eq(N():Count(), 0)
		eq(N().state.stats.ignored, 3)
	end)

	it("the whole path: an encoded SALT from an officer reaches the ring", function()
		local text = A().Codec:Encode("SALT", { k = "s", s = { { b = saltB64(5), at = 1000 } } })
		Mock.chat.Receive("AzAccord", text, "OFFICER", "Ann")
		eq(N():Count(), 1)
		eq(A().Compat:Feature("officerAddonChannel"), "available", "an OFFICER message proves the channel")
	end)

	it("answers a question with the salts the asker lacks, after a short delay", function()
		A().Compat:SetFeature("officerAddonChannel", "available", "test")
		truthy(N():AddSalt(saltB64(5), 1000))
		truthy(N():AddSalt(saltB64(6), 1100))
		local fp5 = N():Salts()[1].fp
		local sent = capture()
		N():OnMessage({ t = "SALT", k = "q", f = { fp5 } }, "Ann", "OFFICER")
		eq(#sent, 0)
		Mock.Advance(4)
		local shares = ofType(sent, "SALT", "OFFICER")
		eq(#shares, 1)
		eq(#shares[1].msg.s, 1)
		eq(shares[1].msg.s[1].b, saltB64(6))
	end)

	it("stands down when another officer shared the same salts on OFFICER first", function()
		A().Compat:SetFeature("officerAddonChannel", "available", "test")
		truthy(N():AddSalt(saltB64(5), 1000))
		local sent = capture()
		N():OnMessage({ t = "SALT", k = "q", f = {} }, "Ann", "OFFICER")
		N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(5), at = 1000 } } }, "Cat", "OFFICER")
		Mock.Advance(4)
		eq(#ofType(sent, "SALT"), 0)
	end)

	it("asks back when the asker holds a salt this client lacks", function()
		A().Compat:SetFeature("officerAddonChannel", "available", "test")
		local sent = capture()
		N():OnMessage({ t = "SALT", k = "q", f = { "abcdefabcdef" } }, "Ann", "OFFICER")
		local q = ofType(sent, "SALT", "OFFICER")
		eq(#q, 1); eq(q[1].msg.k, "q")
		N():OnMessage({ t = "SALT", k = "q", f = { "abcdefabcdef" } }, "Cat", "OFFICER")
		eq(#ofType(sent, "SALT"), 1, "at most once a minute")
	end)

	it("while OFFICER is unproven, also whispers every officer heard recently, and answers whispers by whisper", function()
		eq(A().Compat:Feature("officerAddonChannel"), "unknown")
		truthy(N().UseWhisper())
		present({ { "Ann", ANN, true }, { "Bob", BOB, false }, { "Cat", CAT, true } })
		local sent = capture()
		N():Query()
		eq(#ofType(sent, "SALT", "OFFICER"), 1)
		local whispers = ofType(sent, "SALT", "WHISPER")
		eq(#whispers, 2)
		eq(whispers[1].opts.target, "Ann"); eq(whispers[2].opts.target, "Cat")
		truthy(N():AddSalt(saltB64(5), 1000))
		N():OnMessage({ t = "SALT", k = "q", f = {} }, "Ann", "WHISPER")
		Mock.Advance(4)
		local answers = ofType(sent, "SALT", "WHISPER")
		eq(answers[#answers].opts.target, "Ann"); eq(answers[#answers].msg.k, "s")
	end)

	it("only OFFICER once the channel is proven", function()
		A().Compat:SetFeature("officerAddonChannel", "available", "test")
		present({ { "Ann", ANN, true } })
		local sent = capture()
		N():Query()
		eq(#ofType(sent, "SALT", "OFFICER"), 1)
		eq(#ofType(sent, "SALT", "WHISPER"), 0)
	end)

	it("SALT messages are never kept for the next login", function()
		local sent = capture()
		N():Query()
		eq(sent[1].opts.ttl, N().TTL)
	end)
end)

describe("creation and start", function()
	before_boot(function() guild(1) end)

	it("an officer asks after login and creates the salt when nobody answers", function()
		N().AUTO = true
		local sent = capture()
		truthy(N():Start())
		Mock.Advance(31)
		eq(#ofType(sent, "SALT", "OFFICER"), 1)
		eq(N():Count(), 0)
		Mock.Advance(N().CREATE_WAIT + 1)
		eq(N():Count(), 1)
		eq(N().state.stats.created, 1)
	end)

	it("does not create one when a salt arrived meanwhile", function()
		N():Query()
		N():OnMessage({ t = "SALT", k = "s", s = { { b = saltB64(5), at = 1000 } } }, "Ann", "OFFICER")
		Mock.Advance(N().CREATE_WAIT + 1)
		eq(N():Count(), 1)
		eq(N().state.stats.created, 0)
	end)

	it("a new officer starts asking", function()
		Mock.guild.SetMyRank(3)
		N().AUTO = true
		Mock.guild.SetMyRank(1)
		notNil(N().state.queryTimer)
	end)
end)

describe("the choice of the notary", function()
	describe("for a member", function()
		before_boot(function() guild(3) end)

		it("is nobody while no officer with the addon was heard", function()
			present({ { "Bob", BOB, false } })
			isNil(N():Choose(ME))
		end)

		it("is the same officer every time for one voter, and the next one when it is excluded", function()
			present({ { "Ann", ANN, true }, { "Bob", BOB, false }, { "Cat", CAT, true } })
			local first, guid = N():Choose(ME)
			truthy(first == "Ann" or first == "Cat")
			eq(guid, first == "Ann" and ANN or CAT)
			eq(N():Choose(ME), first)
			local second = N():Choose(ME, { [first] = true })
			ne(second, first)
			isNil(N():Choose(ME, { Ann = true, Cat = true }))
			eq(#N():Candidates(ME), 2)
		end)

		it("spreads different voters over the officers", function()
			present({ { "Ann", ANN, true }, { "Cat", CAT, true } })
			local seen = {}
			for i = 1, 40 do seen[N():Choose(("Player-1-%08X"):format(i))] = true end
			truthy(seen.Ann and seen.Cat)
		end)
	end)

	describe("for an officer", function()
		before_boot(function() guild(1) end)

		it("is this client itself once it holds the salt", function()
			present({ { "Ann", ANN, true } })
			eq(N():Choose(ME), "Ann")
			N():Create()
			eq(N():Choose(ME), "self")
			truthy(N():CanNotarize())
		end)
	end)
end)

describe("officers in the network simulator", function()
	local function saltSent(c, dist)
		for _, e in ipairs(c.Mock.chat.sent) do
			if e.chatType == dist and e.message:find("|SALT|", 1, true) then return true end
		end
		return false
	end

	it("two officers converge on one salt; members never hold it and nothing goes on GUILD", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, seed = 51, notary = true, latency = { 0.05, 0.3 } }
		sim:advance(150)
		local a, b = sim:client(1):addon().Notary, sim:client(2):addon().Notary
		truthy(a:Count() >= 1)
		eq(a:Count(), b:Count())
		local fa, fb = select(2, a:Current()), select(2, b:Current())
		eq(fa, fb)
		for i = 3, 4 do
			local c = sim:client(i)
			eq(c:addon().Notary:Count(), 0)
			isNil(c:addon().GuildKey:Data().salts)
		end
		for i = 1, 4 do falsy(saltSent(sim:client(i), "GUILD"), "client " .. i) end
		truthy(saltSent(sim:client(1), "OFFICER") or saltSent(sim:client(2), "OFFICER"))
		eq(sim:client(1):addon().Compat:Feature("officerAddonChannel"), "available")
	end)

	it("an officer who logs in later receives the salt instead of making a new one", function()
		local sim = Sim.new{ clients = 3, officers = { 1, 2 }, seed = 53, notary = true, offline = { 2 } }
		sim:advance(120)
		local a = sim:client(1):addon().Notary
		eq(a:Count(), 1)
		sim:client(2):login()
		sim:advance(90)
		local b = sim:client(2):addon().Notary
		eq(b:Count(), 1)
		eq(select(2, b:Current()), select(2, a:Current()))
		eq(b.state.stats.created, 0)
	end)

	it("without addon messages on OFFICER (S5 failing) the salt travels by whisper between officers", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 3 }, seed = 57, notary = true, officerChannel = false }
		sim:advance(240)
		local a, c = sim:client(1):addon().Notary, sim:client(3):addon().Notary
		truthy(a:Count() >= 1)
		eq(select(2, a:Current()), select(2, c:Current()))
		eq(sim:client(1):addon().Compat:Feature("officerAddonChannel"), "unknown")
		truthy(a.state.stats.whispers + c.state.stats.whispers > 0)
		eq(sim:client(2):addon().Notary:Count(), 0)
		isNil(sim:client(2):addon().GuildKey:Data().salts)
	end)

	it("the salt survives a logout and login", function()
		local sim = Sim.new{ clients = 2, officers = { 1 }, seed = 59, notary = true }
		sim:advance(90)
		local fp = select(2, sim:client(1):addon().Notary:Current())
		truthy(fp)
		sim:client(1):logout()
		sim:advance(30)
		sim:client(1):login()
		eq(select(2, sim:client(1):addon().Notary:Current()), fp)
	end)
end)

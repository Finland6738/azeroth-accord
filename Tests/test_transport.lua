-- Transport (M1.5): the send queue over GUILD, OFFICER and WHISPER (SPEC-02 §1, §5): validation, per-distribution gap,
-- type rates, lockdown and restriction hold, keys, expiry, retries, the guild stamp, the queue saved across /reload and
-- logout, and the receive path. Adapted from Azeroth Guild Finder (Tests/test_transport.lua), same owner, GPL-3.0
-- (ADR 0018). Most tests replace the wire with a recorder so every timing is exact; the last groups run through the
-- real ChatThrottleLib and the mock client.
local function Tr() return AzerothAccord.Transport end
local function Bus() return AzerothAccord.Bus end
local function Codec() return AzerothAccord.Codec end
-- the game is not built yet when this file loads: look the codes up when a test runs
local R = setmetatable({}, { __index = function(_, name) return Enum.SendAddonMessageResult[name] end })

local function rec(n, pad) return { t = "REC", s = "accounts", r = { { id = "r" .. (n or 1), note = pad and ("abcdefgh"):rep(pad) or nil } } } end
local function req() return { t = "REQ", s = "accounts" } end
local function hello() return { t = "HELLO", s = "" } end

-- Replaces the wire with a recorder. `results` (optional) are the codes of the next sends, "hold" keeps a send
-- unanswered (call W.answer(n, code) later); anything left over answers Success.
local function fakeWire(results)
	local W = { calls = {}, results = results or {}, open = {} }
	Tr().wire = function(prio, text, dist, target, done)
		W.calls[#W.calls + 1] = { prio = prio, text = text, dist = dist, target = target, time = GetTime(), bytes = #text }
		local r = table.remove(W.results, 1)
		if r == "hold" then W.open[#W.calls] = done return end
		done(r == nil and R.Success or r)
	end
	function W.answer(n, code) W.open[n](code) W.open[n] = nil end
	function W.msg(n) return (Codec():Decode(W.calls[n].text)) end
	function W.types()
		local out = {}
		for i = 1, #W.calls do out[i] = W.msg(i).t end
		return out
	end
	return W
end

local function listen(event)
	local seen = {}
	Bus():On(event, function(...) seen[#seen + 1] = { ... } end)
	return seen
end

describe("Send", function()
	it("rejects a bad distribution, shape, priority and whisper target", function()
		eq(select(2, Tr():Send("CHANNEL", req())), "dist", "no public channel (ADR 0004)")
		eq(select(2, Tr():Send("PARTY", req())), "dist")
		eq(select(2, Tr():Send("GUILD", "x")), "shape")
		eq(select(2, Tr():Send("GUILD", req(), { prio = "URGENT" })), "prio")
		eq(select(2, Tr():Send("WHISPER", req())), "target")
		eq(select(2, Tr():Send("WHISPER", req(), { target = "" })), "target")
		eq(Tr():Pending(), 0)
	end)

	it("rejects what the codec rejects and counts it", function()
		local item, why = Tr():Send("GUILD", { t = "WHAT" })
		isNil(item)
		contains(why, "encode: type")
		eq(Tr():Stats().encodeFailed, 1)
	end)

	it("hands the message to the wire with its priority, distribution and target", function()
		local W = fakeWire()
		Tr():Send("WHISPER", req(), { target = "Friend-Realm" })
		Tr():Send("OFFICER", { t = "SALT", k = "q" })
		Tr():Send("GUILD", rec())
		Mock.Advance(1)
		eq(#W.calls, 3)
		eq(W.calls[1].dist, "WHISPER"); eq(W.calls[1].target, "Friend-Realm"); eq(W.calls[1].prio, "ALERT")
		eq(W.calls[2].dist, "OFFICER"); eq(W.calls[2].prio, "ALERT")
		eq(W.calls[3].dist, "GUILD"); eq(W.calls[3].prio, "NORMAL"); isNil(W.calls[3].target)
		eq(W.msg(3).r[1].id, "r1")
	end)

	it("calls onSent once the wire says it went out; a failing callback goes to the error handler", function()
		fakeWire()
		local sent = 0
		Tr():Send("GUILD", rec(), { onSent = function() sent = sent + 1 end })
		Tr():Send("GUILD", rec(2), { onSent = function() error("callback broke") end })
		Mock.Advance(3)
		eq(sent, 1)
		eq(Tr():Stats().callbackErrors, 1)
		eq(#Mock.errors, 1)
		Mock.ClearErrors()
	end)

	it("Cancel withdraws a waiting message and the timer stops with an empty queue", function()
		fakeWire()
		Mock.chat.lockdown = true
		local why
		local item = Tr():Send("GUILD", rec(), { onFail = function(r) why = r end })
		truthy(Tr():Cancel(item))
		falsy(Tr():Cancel(item))
		eq(why, "cancelled")
		Mock.Advance(1)
		isNil(Tr().state.ticker)
	end)
end)

describe("pacing", function()
	it("sends one message per gap on each distribution, the distributions side by side", function()
		local W = fakeWire()
		for i = 1, 3 do Tr():Send("GUILD", rec(i)) end
		for _ = 1, 3 do Tr():Send("WHISPER", req(), { target = "F" }) end
		Mock.Advance(1.05)
		local guild, whisper = 0, 0
		for _, c in ipairs(W.calls) do if c.dist == "GUILD" then guild = guild + 1 else whisper = whisper + 1 end end
		eq(guild, 1, "one GUILD message in the first second")
		eq(whisper, 3, "the whispers do not wait for the guild gap")
		Mock.Advance(2.1)
		eq(#W.calls, 6)
		for i = 2, #W.calls do
			local a, b = W.calls[i - 1], W.calls[i]
			if a.dist == "GUILD" and b.dist == "GUILD" then truthy(b.time - a.time >= 1 - 1e-6) end
		end
	end)

	it("reads the gap as a setting", function()
		local W = fakeWire()
		Tr().GAP.GUILD = 5
		Tr():Send("GUILD", rec(1))
		Tr():Send("GUILD", rec(2))
		Mock.Advance(4)
		eq(#W.calls, 1)
		Mock.Advance(1.2)
		eq(#W.calls, 2)
	end)

	it("sends at most one HELLO every five minutes (NET-04)", function()
		local W = fakeWire()
		Tr():Send("GUILD", hello())
		Tr():Send("GUILD", hello())
		Mock.Advance(60)
		eq(#W.calls, 1)
		Mock.Advance(241)
		eq(#W.calls, 2)
	end)

	it("gives the HELLO allowance back when the send fails", function()
		local W = fakeWire({ R.GeneralError })
		Tr():Send("GUILD", hello())
		Mock.Advance(2)
		Tr():Send("GUILD", hello())
		Mock.Advance(2)
		eq(#W.calls, 2)
	end)
end)

describe("lockdown, restrictions, keys and expiry (NET-05)", function()
	it("holds every message during a chat lockdown and releases them afterwards by priority", function()
		local W = fakeWire()
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec())
		Tr():Send("GUILD", hello(), { prio = "BULK" })
		Tr():Send("WHISPER", req(), { target = "P" })
		Mock.Advance(30)
		eq(#W.calls, 0)
		eq(Tr():Pending(), 3)
		eq(Tr():Stats().held, "lockdown")
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#W.calls, 3)
		isNil(Tr():Stats().held)
		deepEq(W.types(), { "REQ", "REC", "HELLO" })
	end)

	it("holds during an active addon restriction (combat, encounter...)", function()
		local W = fakeWire()
		Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1 }
		local active = true
		C_RestrictedActions = { GetAddOnRestrictionState = function(kind) return (kind == 1 and active) and 1 or 0 end }
		Tr():Send("GUILD", rec())
		Mock.Advance(5)
		eq(#W.calls, 0)
		eq(Tr():Stats().held, "Encounter")
		active = false
		Mock.Advance(1)
		eq(#W.calls, 1)
	end)

	it("reports the read-only state, holds, and releases", function()
		local W = fakeWire()
		local events = listen("TRANSPORT_READ_ONLY")
		Mock.chat.restricted = true
		Tr():Send("GUILD", rec())
		Mock.Advance(3)
		eq(#W.calls, 0)
		truthy(Tr():IsReadOnly())
		eq(#events, 1); eq(events[1][1], true)
		Mock.chat.restricted = false
		Mock.Advance(1)
		falsy(Tr():IsReadOnly())
		eq(#W.calls, 1)
		eq(events[2][1], false)
	end)

	it("keeps only the latest message per key", function()
		local W = fakeWire()
		Mock.chat.lockdown = true
		local replaced = {}
		local function opts() return { key = "REC|accounts", onFail = function(r) replaced[#replaced + 1] = r end } end
		Tr():Send("GUILD", rec(1), opts())
		Tr():Send("GUILD", rec(2), opts())
		Tr():Send("GUILD", rec(3), opts())
		eq(Tr():Pending(), 1)
		deepEq(replaced, { "replaced", "replaced" })
		eq(Tr():Stats().coalesced, 2)
		Mock.chat.lockdown = false
		Mock.Advance(1)
		eq(W.msg(1).r[1].id, "r3")
	end)

	it("drops BULK messages older than ten minutes and honours a caller's lifetime", function()
		fakeWire()
		Mock.chat.lockdown = true
		local why = {}
		Tr():Send("GUILD", rec(1), { prio = "BULK", onFail = function(r) why[#why + 1] = r end })
		Tr():Send("GUILD", rec(2))
		Tr():Send("GUILD", rec(3), { ttl = 30 })
		Mock.Advance(31)
		eq(Tr():Pending(), 2)
		Mock.Advance(570)
		eq(Tr():Pending(), 1)
		deepEq(why, { "expired" })
		eq(Tr():Stats().droppedBy.expired, 2)
	end)

	it("treats a lockdown refusal of the client as a wait, not a failure or a try", function()
		local W = fakeWire({ R.AddOnMessageLockdown, R.AddOnMessageLockdown })
		local sent = 0
		Tr():Send("GUILD", rec(), { onSent = function() sent = sent + 1 end })
		Mock.Advance(5)
		eq(#W.calls, 3)
		eq(sent, 1)
		eq(Tr():Stats().failed, 0)
		eq(Tr():Stats().retried, 0)
	end)

	it("is bounded: a full queue drops the oldest message of the lowest priority", function()
		fakeWire()
		Mock.chat.lockdown = true
		Tr().QUEUE_MAX = 2
		local why = {}
		Tr():Send("GUILD", rec(1), { prio = "BULK", onFail = function(r) why[#why + 1] = "1:" .. r end })
		Tr():Send("GUILD", rec(2))
		Tr():Send("GUILD", req())
		deepEq(why, { "1:overflow" })
		Tr():Send("GUILD", req())
		local refused, reason = Tr():Send("GUILD", rec(5), { prio = "BULK" })
		isNil(refused); eq(reason, "full")
	end)
end)

describe("throttle results", function()
	it("retries after the delay and reports success", function()
		local W = fakeWire({ R.AddonMessageThrottle })
		local sent = 0
		Tr():Send("GUILD", rec(), { onSent = function() sent = sent + 1 end })
		Mock.Advance(10)
		eq(#W.calls, 2)
		truthy(W.calls[2].time - W.calls[1].time >= Tr().RETRY_DELAY - 1e-6)
		eq(sent, 1)
		local st = Tr():Stats()
		eq(st.throttled, 1); eq(st.retried, 1); eq(st.failed, 0); eq(st.sent, 1)
	end)

	it("gives up after three retries, and does not retry other errors", function()
		local W = fakeWire({ R.AddonMessageThrottle, R.AddonMessageThrottle, R.AddonMessageThrottle, R.AddonMessageThrottle, R.TargetOffline })
		local reasons = {}
		Tr():Send("GUILD", rec(), { onFail = function(r) reasons[#reasons + 1] = r end })
		Mock.Advance(60)
		eq(#W.calls, 4)
		Tr():Send("WHISPER", req(), { target = "Gone", onFail = function(r) reasons[#reasons + 1] = r end })
		Mock.Advance(10)
		deepEq(reasons, { "AddonMessageThrottle", "TargetOffline" })
		eq(Tr():Stats().failed, 2)
	end)

	it("reports a wire that never reached the client", function()
		local reason
		Tr().wire = function(_, _, _, _, done) done("nolib") end
		Tr():Send("GUILD", rec(), { onFail = function(r) reason = r end })
		Mock.Advance(1)
		eq(reason, "nolib")
	end)
end)

describe("the guild stamp", function()
	it("drops a message written for a guild the character has left for another", function()
		local W = fakeWire()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		local why
		Tr():Send("GUILD", rec(), { onFail = function(r) why = r end })
		Mock.guild.Set{ name = "Beta", myRank = 3 }
		Mock.chat.lockdown = false
		Mock.Advance(2)
		eq(#W.calls, 0)
		eq(why, "guild")
	end)

	it("a message waits while the guild is not known yet", function()
		local W = fakeWire()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec())
		local saved = AzerothAccord.Role.GuildKey
		AzerothAccord.Role.GuildKey = function() return nil end
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#W.calls, 0)
		eq(Tr():Pending(), 1)
		AzerothAccord.Role.GuildKey = saved
		Mock.Advance(1)
		eq(#W.calls, 1)
	end)
end)

describe("the saved queue (SPEC-02 §5)", function()
	it("a message survives lockdown and /reload and goes out afterwards", function()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(7), { key = "REC|7" })
		Tr():Send("WHISPER", req(), { target = "Friend-Realm" })
		Mock.Advance(5)
		eq(#Mock.chat.sent, 0)
		Mock.Reload()
		eq(#AzerothAccordCharDB.outbox, 0, "the outbox is emptied once restored")
		eq(Tr():Pending(), 2)
		eq(Tr():Stats().restored, 2)
		Mock.chat.lockdown = false
		Mock.Advance(10)
		local out = Mock.chat.SentWithPrefix("AzAccord")
		eq(#out, 2)
		local types = {}
		for _, e in ipairs(out) do
			local msg = Codec():Decode(e.message)
			types[msg.t] = e.chatType
		end
		eq(types.REC, "GUILD")
		eq(types.REQ, "WHISPER")
	end)

	it("keeps the key, so a newer message replaces the restored one", function()
		local W = fakeWire()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(1), { key = "K" })
		Mock.Reload()
		W = fakeWire()
		Tr():Send("GUILD", rec(2), { key = "K" })
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#W.calls, 1)
		eq(W.msg(1).r[1].id, "r2")
	end)

	it("drops what was written for another guild, what expired and what is too old", function()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(1))
		Tr():Send("GUILD", rec(2), { ttl = 60 })
		Mock.Fire("PLAYER_LOGOUT")
		eq(#AzerothAccordCharDB.outbox, 2)
		-- the game stays closed two minutes: the 60-second message is gone; the other goes to the guild it was for
		local box = {}
		for i, e in ipairs(AzerothAccordCharDB.outbox) do
			box[i] = {}
			for k, v in pairs(e) do box[i][k] = v end
			box[i].saved, box[i].born = e.saved - 120, e.born - 120
		end
		T.boot(function(M)
			M.guild.Set{ name = "Alpha", myRank = 3 }
			M.chat.lockdown = true
			AzerothAccordCharDB = { schemaVersion = 1, outbox = box }
		end)
		eq(Tr():Pending(), 1)
		Mock.guild.Set{ name = "Beta", myRank = 3 }
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#Mock.chat.SentWithPrefix("AzAccord"), 0)
		eq(Tr():Stats().droppedBy.guild, 1)
	end)

	it("a saved message older than a day is not sent again", function()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(1))
		Mock.Fire("PLAYER_LOGOUT")
		Mock.SetServerTime(GetServerTime() + 2 * 86400)
		Mock.Reload()
		eq(Tr():Pending(), 0)
	end)

	it("ignores a damaged outbox", function()
		T.boot(function() AzerothAccordCharDB = { schemaVersion = 1, outbox = { "x", { dist = "CHANNEL", payload = "y" }, { dist = "GUILD" } } } end)
		eq(Tr():Pending(), 0)
		eq(#Mock.errors, 0)
	end)
end)

describe("receive path", function()
	local function text(t, fields) return Codec():Encode(t, fields) end

	it("decodes a message from AceComm and puts it on the Bus with the sender and the distribution", function()
		local seen = listen("NET_MESSAGE")
		truthy(Mock.chat.Receive("AzAccord", text("REQ", { s = "accounts" }), "GUILD", "Sender-Realm"))
		eq(#seen, 1)
		eq(seen[1][1].t, "REQ"); eq(seen[1][1].s, "accounts")
		eq(seen[1][2], "Sender-Realm")
		eq(seen[1][3], "GUILD")
		eq(Tr():Stats().received, 1)
	end)

	it("ignores its own echo and learns from an OFFICER echo that the officer channel works", function()
		local seen = listen("NET_MESSAGE")
		local C = AzerothAccord.Compat
		eq(C:Feature("officerAddonChannel"), "unknown")
		Mock.chat.Receive("AzAccord", text("REQ", { s = "x" }), "GUILD", "Testchar-TestRealm")
		eq(C:Feature("officerAddonChannel"), "unknown")
		Mock.chat.Receive("AzAccord", text("SALT", { k = "q" }), "OFFICER", "Testchar")
		eq(#seen, 0)
		eq(Tr():Stats().echoes, 2)
		eq(C:Feature("officerAddonChannel"), "available")
	end)

	it("an OFFICER message from someone else also proves the channel", function()
		Mock.chat.Receive("AzAccord", text("SALT", { k = "q" }), "OFFICER", "Officer-TestRealm")
		eq(AzerothAccord.Compat:Feature("officerAddonChannel"), "available")
	end)

	it("a namesake on another realm is not the player", function()
		local seen = listen("NET_MESSAGE")
		Mock.chat.Receive("AzAccord", text("REQ", { s = "x" }), "GUILD", "Testchar-OtherRealm")
		eq(#seen, 1)
	end)

	it("drops invalid, unknown and foreign-distribution messages silently", function()
		local seen = listen("NET_MESSAGE")
		Mock.ClearOutput()
		Mock.chat.Receive("AzAccord", "###", "GUILD", "S-R")
		Mock.chat.Receive("AzAccord", "1|LATER|AAAA", "GUILD", "S-R")
		Mock.chat.Receive("AzAccord", text("REQ", { s = "x" }), "PARTY", "S-R")
		Mock.chat.Receive("AzAccord", "", "GUILD", "S-R")
		eq(#seen, 0)
		local st = Tr():Stats()
		eq(st.rxDropped, 4)
		eq(st.rxReasons.type, 1); eq(st.rxReasons.dist, 1)
		eq(#Mock.PlainOutput(), 0)
		eq(#Mock.errors, 0)
	end)

	it("announces a newer protocol once per session and does not deliver it", function()
		local seen, newer = listen("NET_MESSAGE"), listen("PROTOCOL_NEWER")
		local future = "2|REQ|" .. C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR({ s = "x" }))
		Mock.chat.Receive("AzAccord", future, "GUILD", "S-R")
		Mock.chat.Receive("AzAccord", future, "GUILD", "S-R")
		eq(#seen, 0)
		eq(#newer, 1)
		eq(Tr():Stats().rxNewer, 2)
	end)

	it("never writes the sender anywhere it can be read", function()
		Mock.chat.Receive("AzAccord", text("REQ", { s = "x" }), "GUILD", "Hidden-Realm")
		Mock.chat.Receive("AzAccord", "###", "GUILD", "Hidden-Realm")
		Mock.ClearOutput()
		Mock.Slash("/accord debug")
		local out = table.concat(Mock.PlainOutput(), "\n")
		contains(out, "Transport:")
		falsy(out:find("Hidden", 1, true))
	end)
end)

describe("through ChatThrottleLib and the mock client", function()
	local function warm() Mock.Advance(6) end   -- ChatThrottleLib clamps hard for five seconds after start-up

	it("sends GUILD, OFFICER and WHISPER messages with the AzAccord prefix", function()
		Mock.guild.Set({ name = "G", myRank = 1 })
		warm()
		local sent = {}
		Tr():Send("GUILD", rec(), { onSent = function() sent[#sent + 1] = "guild" end })
		Tr():Send("OFFICER", { t = "SALT", k = "q" }, { onSent = function() sent[#sent + 1] = "officer" end })
		Tr():Send("WHISPER", req(), { target = "Friend-Realm", onSent = function() sent[#sent + 1] = "whisper" end })
		Mock.Advance(3)
		local out = Mock.chat.SentWithPrefix("AzAccord")
		eq(#out, 3)
		local byType = {}
		for _, e in ipairs(out) do byType[e.chatType] = e end
		eq(byType.WHISPER.target, "Friend-Realm")
		eq(Codec():Decode(byType.OFFICER.message).t, "SALT")
		eq(#sent, 3)
		truthy(C_ChatInfo.IsAddonMessagePrefixRegistered("AzAccord"))
	end)

	it("splits a long message like AceComm and AceComm puts it back together", function()
		Mock.guild.Set({ name = "G" })
		warm()
		local recs, seed = {}, 11
		for i = 1, 60 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			recs[i] = { id = "r" .. i, author = "Player-1-" .. seed, rev = seed % 1000 }
		end
		Tr():Send("GUILD", { t = "REC", s = "accounts", r = recs })
		Mock.Advance(5)
		local out = Mock.chat.SentWithPrefix("AzAccord")
		truthy(#out >= 3, "chunks " .. #out)
		eq(out[1].message:sub(1, 1), "\1")
		eq(out[#out].message:sub(1, 1), "\3")
		for _, e in ipairs(out) do truthy(#e.prefix + #e.message <= 255) end
		eq(Tr():Stats().sent, 1)

		local seen = listen("NET_MESSAGE")
		for _, e in ipairs(out) do Mock.chat.Receive("AzAccord", e.message, "GUILD", "Other-Realm") end
		eq(#seen, 1)
		deepEq(seen[1][1].r, recs)
	end)

	it("Frame leaves room for the prefix", function()
		local L = 255 - #Tr().PREFIX
		eq(#Tr().Frame(("x"):rep(L)), 1)
		local chunks = Tr().Frame(("x"):rep(L + 1))
		eq(#chunks, 2)
		eq(#chunks[1], L)
		eq(chunks[1]:sub(1, 1), "\1")
		eq(chunks[2], "\3xx")
	end)

	it("reports a missing library as a failure", function()
		Mock.guild.Set({ name = "G" })
		local reason
		ChatThrottleLib = nil
		Tr():Send("GUILD", rec(), { onFail = function(r) reason = r end })
		Mock.Advance(2)
		eq(reason, "nolib")
		eq(#Mock.errors, 0)
	end)
end)

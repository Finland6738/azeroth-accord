-- The guild handbook's data (M11.2; SPEC-15 §3; ADR 0025; SPEC-10 Q27-Q29): the data set `handbook` behind the switch
-- "raid"; who writes (the Guild Master, the officers, the ranks the officers chose, while the rank keeps its name); a
-- page from a non-writer is refused, also as a revision of a valid page; an ex-writer's pages stay, its new revisions do
-- not; the limits (body, title, pages, total, rate); the past revisions kept on this client without traffic; a save over
-- a revision that changed does not replace it silently; two edits of the same revision keep the later on every client and
-- only the losing author is told; the summary apart, ignored by a client that does not know it; pages asked for, never
-- pushed, and answered once on GUILD for everybody waiting; and the traffic of 50 clients in the simulator (SPEC-15 §3.7).
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function H() return AzerothAccord.Handbook end

local ME, BOB, ANN, OFF, LEAD = "Player-1-0000A001", "Player-1-00000B0B", "Player-1-00000A44", "Player-1-00000C0C",
	"Player-1-00000D0D"

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank or 3, members = {
		{ name = "Bob", level = 30, class = "MAGE", rank = 3, guid = BOB, online = true },
		{ name = "Ann", level = 60, class = "PRIEST", rank = 2, guid = ANN, online = true },
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = OFF, online = true },
		{ name = "Lead", level = 60, class = "WARRIOR", rank = 0, guid = LEAD, online = true },
	} }
end

local function member(Mk) Mk.features = { raid = true } guild(3) end
local function officer(Mk) Mk.features = { raid = true } guild(1) end
local function off(Mk) Mk.features = { raid = false, season = true } guild(1) end

local function capture()
	local out, T_ = {}, A().Transport
	local original = T_.Send
	T_.Send = function(self, dist, msg, opts)
		out[#out + 1] = { dist = dist, msg = msg, target = opts and opts.target, prio = opts and opts.prio }
		return original(self, dist, msg, opts)
	end
	return out
end

local function hear(msg, sender, dist) A().Bus:Emit("NET_MESSAGE", msg, sender, dist or "GUILD") end

-- A page as a writer's client would send it.
local function page(author, slug, fields)
	local rec = { id = "P:" .. slug, author = author, rev = 1, time = GetServerTime(), title = "Rules", body = "# General\n\nBe kind.",
		order = 20 }
	for k, v in pairs(fields or {}) do rec[k] = v end
	return rec
end

local function check(rec, sender) return select(2, S():Check("handbook", rec, { sender = sender, dist = "GUILD" })) end

local function writers(ranks)
	local t = GetServerTime()
	return { id = "handbook", author = OFF, rev = 1, time = t, ranks = ranks }
end

-- Deterministic text with accents and line breaks, `bytes` long, that compresses like real writing.
local WORDS = { "la", "gilda", "raid", "è", "il", "loot", "segue", "regole", "officer", "più", "settimana", "membri",
	"città", "ogni", "giovedì", "prima", "dopo", "turno", "panchina", "priorità", "spec", "chiedete", "sempre", "perché" }
local function prose(bytes, seed)
	local out, n, x = {}, 0, seed or 7
	while n < bytes do
		x = (x * 1103515245 + 12345) % 2147483648
		local w = WORDS[x % #WORDS + 1]
		local sep = (x % 13 == 0) and "\n" or " "
		out[#out + 1] = w .. sep
		n = n + #w + 1
	end
	return table.concat(out):sub(1, bytes)
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

---------------------------------------------------------------------------------------------------------------------
describe("the handbook with the switch `raid` off", function()
	before_boot(off)

	it("takes, sends and shows nothing", function()
		falsy(S().IsActive("handbook"))
		local sent = capture()
		local rec, why = H():Save("P:rules", { title = "Rules", body = "x", order = 20 })
		isNil(rec); eq(why, "off")
		isNil((S():Put("handbook", "P:rules", { title = "Rules", body = "x", order = 20 })))
		eq(check(page(OFF, "rules"), "Boss"), "set")
		falsy(A().Integrations.ValidRecord(writers({ { i = 2, n = "Veteran" } })), "the writers' record is an M11 record")
		falsy(H():SetWriters({ 2 }))
		eq(#H():Pages(true), 0)
		falsy(H():CanWrite())
		A().Sync:SendHello()
		Mock.Advance(30)
		for _, e in ipairs(sent) do
			isNil(e.msg.hb, "no handbook summary in a HELLO"); isNil(e.msg.hbb)
			truthy(e.msg.s ~= "handbook")
		end
		for _, row in ipairs(A().Actions:Rows()) do truthy(row.provider ~= "handbook") end
		falsy(A().Diagnostics.Report():find("Handbook:", 1, true))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the shape of a page (HBK-02)", function()
	before_boot(member)

	it("accepts a well formed page, a deletion and the seeding, and refuses every bad field", function()
		local V = H().ValidRecord
		truthy(V(page(OFF, "rules")))
		truthy(V(page(OFF, "raid-management", { body = "", order = 99, tpl = true })))
		truthy(V(page(OFF, "faq", { body = prose(4000), title = ("t"):rep(40) })))
		truthy(V({ id = "P:rules", author = OFF, rev = 3, time = 1, del = true }))
		truthy(V({ id = "seeded", author = OFF, rev = 1, time = 1, at = 1, by = "0.11.0" }))
		local bad = {
			{ id = "rules" }, { id = "P:Rules" }, { id = "P:" }, { id = "P:" .. ("a"):rep(25) }, { id = "P:a b" },
			{ title = "" }, { title = "a\nb" }, { title = "a|cffff0000b" }, { body = "a|Hitem:1|h[x]|h" }, { body = "a\tb" },
			{ body = "a\rb" }, { body = 5 }, { order = 0 }, { order = 100 }, { order = 1.5 }, { tpl = false },
			{ del = true }, { color = "red" }, { html = "<b>" },
		}
		for i, change in ipairs(bad) do falsy(V(page(OFF, "rules", change)), "bad field " .. i) end
		eq(select(2, V(page(OFF, "rules", { body = prose(4001) }))), "size")
		eq(select(2, V(page(OFF, "rules", { title = ("t"):rep(41) }))), "size")
		falsy(V({ id = "P:rules", author = OFF, rev = 3, time = 1, del = true, title = "x" }))
		falsy(V({ id = "seeded", author = OFF, rev = 1, time = 1, at = 1, extra = 1 }))
	end)

	it("refuses a page over the limits as `size` when it arrives", function()
		eq(check(page(OFF, "rules", { body = prose(4001) }), "Boss"), "size")
		eq(check(page(OFF, "rules", { title = ("t"):rep(41) }), "Boss"), "size")
		eq(check(page(OFF, "rules", { body = "a|r" }), "Boss"), "owner")
	end)

	it("makes page ids from titles, without accents, with a number when taken", function()
		eq(H().Slug("Regolamento della gilda"), "regolamento-della-gilda")
		eq(H().Slug("Perché è così? FAQ!"), "perche-e-cosi-faq")
		eq(H().Slug("ÀÉÌ"), "aei")
		eq(H().Slug("???"), "page")
		eq(#H().Slug(("abc "):rep(20)) <= 24, true)
		truthy(S():Receive("handbook", { page(OFF, "rules") }, "Boss", "GUILD") == 1)
		eq(H():NewId("Rules"), "P:rules-2")
		eq(H():NewId("FAQ"), "P:faq")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("who writes (HBK-01, SPEC-15 §3.3)", function()
	before_boot(member)

	it("takes pages of the Guild Master and the officers, and refuses a non-writer's as `authority`", function()
		eq(S():Receive("handbook", { page(OFF, "rules") }, "Boss", "GUILD"), 1)
		eq(S():Receive("handbook", { page(LEAD, "faq") }, "Lead", "GUILD"), 1)
		eq(check(page(BOB, "bob"), "Bob"), "authority")
		-- not even as a revision of a valid page
		eq(check(page(BOB, "rules", { rev = 2, time = GetServerTime() + 1, body = "Bob rules." }), "Bob"), "authority")
		-- somebody else's page from a member is a relay, refused as ever
		eq(check(page(OFF, "rules", { rev = 2 }), "Bob"), "relay")
		eq(S():Get("handbook", "P:rules").author, OFF)
		eq(S().stats.reasons.authority, nil, "Check does not count; Receive does")
		eq(select(2, S():Receive("handbook", { page(BOB, "bob") }, "Bob", "GUILD")), 1)
		eq(S().stats.reasons.authority, 1)
	end)

	it("lets a rank the officers chose write, until the rank is renamed or moved", function()
		eq(check(page(ANN, "ann"), "Ann"), "authority")
		eq(S():Receive("guildcfg", { writers({ { i = 2, n = "Veteran" } }) }, "Boss", "GUILD"), 1)
		truthy(check(page(ANN, "ann"), "Ann") == nil)
		eq(check(page(BOB, "bob"), "Bob"), "authority", "rank 3 was not chosen")
		truthy(H().IsWriter({ rankIndex = 2 }))
		-- the guild renames rank 2: the choice no longer counts until an officer makes it again
		Mock.guild.ranks[2] = "Elder"
		S():RosterChanged()
		eq(check(page(ANN, "ann"), "Ann"), "authority")
		falsy(H().IsWriter({ rankIndex = 2 }))
		Mock.guild.ranks[2] = "Veteran"
		truthy(H().IsWriter({ rankIndex = 2 }))
	end)

	it("refuses a writers' record from a member, and a bad one", function()
		eq(select(2, S():Check("guildcfg", writers({ { i = 2, n = "Veteran" } }), { sender = "Bob", dist = "GUILD" })), "authority")
		local V = A().Integrations.ValidRecord
		truthy(V(writers({})))
		truthy(V(writers({ { i = 2, n = "Veteran" }, { i = 3, n = "Member" } })))
		for i, ranks in ipairs({ { { i = 0, n = "Guild Master" } }, { { i = 10, n = "X" } }, { { i = 2 } }, { { i = 2, n = "" } },
			{ { i = 2, n = ("n"):rep(33) } }, { { i = 2, n = "a|r" } }, { { i = 2, n = "A" }, { i = 2, n = "B" } },
			{ { i = 2, n = "A", x = 1 } }, "Veteran" }) do
			falsy(V(writers(ranks)), "bad ranks " .. i)
		end
		local many = {}
		for i = 1, 10 do many[i] = { i = i % 9 + 1, n = "R" .. i } end
		falsy(V(writers(many)))
	end)

	it("keeps an ex-writer's pages, and refuses its new revisions first hand", function()
		eq(S():Receive("guildcfg", { writers({ { i = 2, n = "Veteran" } }) }, "Boss", "GUILD"), 1)
		eq(S():Receive("handbook", { page(ANN, "ann") }, "Ann", "GUILD"), 1)
		eq(S():Receive("guildcfg", { writers({}) }, "Boss", "GUILD") + 0, 0, "same rev 1: not newer")
		local t = GetServerTime() + 1
		eq(S():Receive("guildcfg", { { id = "handbook", author = OFF, rev = 2, time = t, ranks = {} } }, "Boss", "GUILD"), 1)
		notNil(S():Get("handbook", "P:ann"), "the page stays")
		eq(check(page(ANN, "ann", { rev = 2, time = t }), "Ann"), "authority")
		-- an officer's relay of the page as it was stays valid (authorAny)
		truthy(check(page(ANN, "ann2"), "Boss") == nil)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("an officer writes", function()
	before_boot(officer)

	it("saves, revises and deletes, a page at a time, and the revision is the page's", function()
		truthy(H():CanWrite())
		local rec = H():Save("P:rules", { title = "Rules", body = "One.", order = 20 })
		eq(rec.rev, 1); eq(rec.author, ME)
		-- another officer revises it: the next revision of this client is 3, whoever wrote 2
		eq(S():Receive("handbook", { page(OFF, "rules", { rev = 2, time = GetServerTime() + 1, body = "Two." }) }, "Boss", "GUILD"), 1)
		Mock.Advance(5)
		local three = H():Save("P:rules", { title = "Rules", body = "Three." }, { base = 2 })
		eq(three.rev, 3); eq(three.order, 20)
		local pages = H():Pages()
		eq(#pages, 1); eq(pages[1].body, "Three.")
		local del = H():Delete("P:rules", 3)
		eq(del.rev, 4); eq(del.del, true)
		eq(#H():Pages(true), 0)
		-- a deleted page stays for ever: retention never drops it
		Mock.Advance(90 * 86400)
		S():Prune()
		eq(S():Get("handbook", "P:rules").del, true)
	end)

	it("does not replace a revision that changed while editing, unless the writer keeps theirs", function()
		H():Save("P:rules", { title = "Rules", body = "Mine 1.", order = 20 })
		eq(S():Receive("handbook", { page(OFF, "rules", { rev = 2, time = GetServerTime() + 1, body = "Theirs." }) }, "Boss", "GUILD"), 1)
		local rec, why, held = H():Save("P:rules", { title = "Rules", body = "Mine 2." }, { base = 1 })
		isNil(rec); eq(why, "changed"); eq(held.author, OFF); eq(held.body, "Theirs.")
		eq(S():Get("handbook", "P:rules").body, "Theirs.", "nothing replaced silently")
		eq(select(2, H():Save("P:new", { title = "New", body = "" }, { base = 1 })), "changed", "a page that is gone")
		eq(select(2, H():Save("P:rules", { title = "Rules", body = "Mine 2." })), "changed", "no base over a page held")
		-- Discard mine: the text stays among the revisions, marked lost, with no row to act on
		truthy(H():Discard("P:rules", "Rules", "Mine 2.", 2))
		local revs = H():Revisions("P:rules")
		eq(revs[1].current, true); eq(revs[1].body, "Theirs.")
		local lost
		for _, r in ipairs(revs) do if r.lost then lost = r end end
		eq(lost.body, "Mine 2."); isNil(lost.open)
		eq(#H():Conflicts(), 0)
		-- Keep mine: written over the revision held
		Mock.Advance(5)
		local kept = H():Save("P:rules", { title = "Rules", body = "Mine 2." }, { base = 1, force = true })
		eq(kept.rev, 3)
	end)

	it("refuses a write over the limits", function()
		eq(select(2, H():Save("P:a", { title = ("t"):rep(41), body = "", order = 1 })), "size")
		eq(select(2, H():Save("P:a", { title = "A", body = prose(4001), order = 1 })), "size")
		eq(select(2, H():Save("P:a", { title = "A", body = "a|cffffffff", order = 1 })), "owner")
		eq(select(2, H():Save("P:A", { title = "A", body = "", order = 1 })), "id")
		-- the total: 8 pages of 4000 bytes are 32 000
		for i = 1, 8 do truthy(H():Save("P:p" .. i, { title = "P" .. i, body = prose(4000, i), order = i })) end
		eq(select(2, H():Save("P:p9", { title = "P9", body = "x", order = 9 })), "size")
		-- a page may grow only into what the others leave
		truthy(H():Save("P:p8", { title = "P8", body = prose(3000, 8) }, { base = 1 }))
		truthy(H():Save("P:p9", { title = "P9", body = prose(1000, 9), order = 9 }))
		-- the pages: 20 live at most (deleted pages do not count)
		for i = 10, 20 do truthy(H():Save("P:p" .. i, { title = "P" .. i, body = "", order = i }), "page " .. i) end
		eq(select(2, H():Save("P:p21", { title = "P21", body = "", order = 21 })), "pages")
		truthy(H():Delete("P:p20", 1))
		truthy(H():Save("P:p21", { title = "P21", body = "", order = 21 }))
		local _, bytes = H():Usage()
		eq(bytes, 32000)
	end)

	it("writes at most 30 revisions an hour, and a receiver takes no more than that from an author (HBK-05)", function()
		H():ResetRates()
		for i = 1, 30 do truthy(H():Save("P:r" .. (i % 5), { title = "R", body = tostring(i), order = 1 }, { force = true }), "write " .. i) end
		eq(select(2, H():Save("P:r1", { title = "R", body = "31", order = 1 }, { force = true })), "rate")
		Mock.Advance(3601)
		truthy(H():Save("P:r1", { title = "R", body = "later", order = 1 }, { force = true }))
		-- received: 30 new revisions of one author in an hour, the 31st is refused as `rate`
		local t = GetServerTime()
		local list = {}
		for i = 1, 31 do list[i] = page(OFF, "o" .. i, { time = t - i }) end
		local accepted, refused = S():Receive("handbook", list, "Boss", "GUILD")
		eq(accepted, 30); eq(refused, 1)
		eq(S().stats.reasons.rate, 1)
		-- old revisions (a first sync) do not count: they were written over a longer time
		local old = {}
		for i = 1, 40 do old[i] = page(LEAD, "l" .. i, { time = t - 7200 - i }) end
		eq((S():Receive("handbook", old, "Lead", "GUILD")), 40)
	end)

	it("keeps the last 5 past revisions on this client, and sends none of them", function()
		local sent = capture()
		H():Save("P:rules", { title = "Rules", body = "v1", order = 20 })
		for i = 2, 8 do
			truthy(H():Save("P:rules", { title = "Rules", body = "v" .. i }, { base = i - 1 }))
		end
		local revs = H():Revisions("P:rules")
		eq(#revs, 6, "the current one and 5 past")
		eq(revs[1].body, "v8"); eq(revs[1].current, true)
		eq(revs[2].body, "v7"); eq(revs[6].body, "v3")
		Mock.Advance(10)
		local recs = 0
		for _, e in ipairs(sent) do
			if e.msg.t == "REC" and e.msg.s == "handbook" then
				recs = recs + 1
				eq(e.dist, "GUILD"); eq(e.prio, "BULK")
				for _, r in ipairs(e.msg.r) do eq(r.body, "v8", "only the current revision travels") end
			end
		end
		eq(recs, 1, "the 8 saves went out once, after the batch")
		-- nothing of the revisions is in the store's record
		isNil(S():Get("handbook", "P:rules").revs)
		-- restore writes a new revision
		local back = H():Restore("P:rules", 4)
		eq(back.rev, 9); eq(back.body, "v4")
	end)

	it("sends a long page alone and short ones together", function()
		local sent = capture()
		H():Save("P:long", { title = "Long", body = prose(4000), order = 1 })
		H():Save("P:a", { title = "A", body = "short", order = 2 })
		H():Save("P:b", { title = "B", body = "short", order = 3 })
		Mock.Advance(10)
		local sizes = {}
		for _, e in ipairs(sent) do
			if e.msg.t == "REC" and e.msg.s == "handbook" then sizes[#sizes + 1] = #e.msg.r end
		end
		table.sort(sizes)
		deepEq(sizes, { 1, 2 })
	end)

	it("lets an officer choose the ranks that write", function()
		falsy(H().IsWriter({ rankIndex = 3 }))
		truthy(H():SetWriters({ 3, 2, 3 }))
		local rec = S():Get("guildcfg", "handbook")
		deepEq(rec.ranks, { { i = 2, n = "Veteran" }, { i = 3, n = "Member" } })
		truthy(H().IsWriter({ rankIndex = 3 }))
		eq(select(2, H():SetWriters({ 12 })), "rank")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a member who is not a writer", function()
	before_boot(member)

	it("cannot write, and reads what writers wrote", function()
		falsy(H():CanWrite())
		eq(select(2, H():Save("P:rules", { title = "Rules", body = "x", order = 1 })), "writer")
		eq(select(2, H():SetWriters({ 3 })), "officer")
		eq(S():Receive("handbook", { page(OFF, "rules"), page(OFF, "faq", { title = "FAQ", order = 30, tpl = true }) }, "Boss", "GUILD"), 2)
		eq(#H():Pages(), 1, "a template is not shown to members")
		eq(#H():Pages(true), 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("two edits of the same revision (HBK-04)", function()
	before_boot(officer)

	it("keep the later one, and tell its author when theirs lost", function()
		Mock.Advance(300)   -- past the grouping of the notices after a login
		H():Save("P:rules", { title = "Rules", body = "Base.", order = 20 })
		Mock.Advance(5)
		local mine = H():Save("P:rules", { title = "Rules", body = "Mine." }, { base = 1 })
		eq(mine.rev, 2)
		-- an older edit of the same revision does not replace mine, and is no conflict
		eq((S():Receive("handbook", { page(OFF, "rules", { rev = 2, time = mine.time - 1, body = "Older." }) }, "Boss", "GUILD")), 0)
		eq(#H():Conflicts(), 0)
		-- a later one does: mine is kept as a lost revision, the notice and the Action Center row follow
		local conflicts = {}
		A().Bus:On("HANDBOOK_CONFLICT", function(id) conflicts[#conflicts + 1] = id end)
		eq(S():Receive("handbook", { page(OFF, "rules", { rev = 2, time = mine.time + 3, body = "Theirs." }) }, "Boss", "GUILD"), 1)
		eq(S():Get("handbook", "P:rules").body, "Theirs.")
		deepEq(conflicts, { "P:rules" })
		local list = H():Conflicts()
		eq(#list, 1); eq(list[1].winner, OFF); eq(list[1].title, "Rules")
		local lost
		for _, r in ipairs(H():Revisions("P:rules")) do if r.lost then lost = r end end
		eq(lost.body, "Mine."); eq(lost.rev, 2); eq(lost.author, ME)
		local notice
		for _, e in ipairs(A().Notify:Entries()) do if e.module == "handbook" then notice = e end end
		notNil(notice); eq(notice.kind, "conflict"); eq(notice.level, "alert")
		contains(A().Notify.Text(notice), "Boss")
		local row
		for _, r in ipairs(A().Actions:Refresh()) do if r.provider == "handbook" then row = r end end
		notNil(row); eq(row.urgency, 2)
		-- restore: a new revision with my text; the row goes
		Mock.Advance(5)
		local back = H():Restore("P:rules", 2, lost.time)
		eq(back.rev, 3); eq(back.body, "Mine.")
		eq(#H():Conflicts(), 0)
	end)

	it("dismisses a conflict, keeping the text", function()
		H():Save("P:faq", { title = "FAQ", body = "Mine.", order = 30 })
		eq(S():Receive("handbook", { page(OFF, "faq", { title = "FAQ", time = GetServerTime() + 2, body = "Theirs." }) }, "Boss", "GUILD"), 1)
		eq(#H():Conflicts(), 1)
		H():Dismiss("P:faq")
		eq(#H():Conflicts(), 0)
		local lost = 0
		for _, r in ipairs(H():Revisions("P:faq")) do if r.lost then lost = lost + 1 end end
		eq(lost, 1)
	end)

	it("is not a conflict when a later revision replaces mine", function()
		H():Save("P:info", { title = "Info", body = "Mine.", order = 10 })
		eq(S():Receive("handbook", { page(OFF, "info", { rev = 2, title = "Info", time = GetServerTime() + 2 }) }, "Boss", "GUILD"), 1)
		eq(#H():Conflicts(), 0)
		eq(#H():Revisions("P:info"), 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the handbook's summary", function()
	before_boot(officer)

	it("goes apart, in `hb`, and only when this client holds pages", function()
		local sent = capture()
		A().Sync:SendHello()
		local hello
		for _, e in ipairs(sent) do if e.msg.t == "HELLO" then hello = e.msg end end
		eq(hello.t, "HELLO"); isNil(hello.hb)
		local s0 = hello.s
		H():Save("P:rules", { title = "Rules", body = "x", order = 1 })
		Mock.Advance(400)
		A().Sync:SendHello()
		local last
		for _, e in ipairs(sent) do if e.msg.t == "HELLO" then last = e.msg end end
		eq(#last.hb, 11, "one entry: this writer")
		eq(last.s, s0, "the summary per author did not change: an older client sees nothing new")
		-- a BHELLO carries its 12 blocks
		A().Sync.BLOCK_OVER = -1
		Mock.Advance(400)
		A().Sync:SendHello()
		local bh
		for _, e in ipairs(sent) do if e.msg.t == "BHELLO" then bh = e.msg end end
		eq(#bh.hbb, 3)
		A().Sync.BLOCK_OVER = 200
	end)

	it("keeps a BHELLO of a large guild with the three summaries under 512 B (SPEC-11 §6.5)", function()
		local Sy, groups = A().Sync, {}
		for i = 1, 1000 do
			local guid = ("Player-1-%08X"):format(0x50000 + i)
			groups[guid] = { key = Sy.KeyOf(guid), d = i * 7919 % 16777216, t = 1767225600 + i, author = guid }
			local extra = Sy.ExtraName(guid)
			groups[extra] = { key = Sy.KeyOf(extra), d = i * 104729 % 16777216, t = 1767225600 + i, author = guid, extra = true }
			if i <= 12 then   -- a dozen writers
				local hb = Sy.HandbookName(guid)
				groups[hb] = { key = Sy.KeyOf(hb), d = i * 15485863 % 16777216, t = 1767225600 + i, author = guid, extra = "hb" }
			end
		end
		local msg = { b = Sy:EncodeBlocks(groups), cb = Sy:EncodeBlocks(groups, true), hbb = Sy:EncodeBlocks(groups, "hb"),
			n = 1000, av = "0.11.0" }
		eq(#msg.b, 288); eq(#msg.cb, 36); eq(#msg.hbb, 3)
		local wire = A().Codec:Encode("BHELLO", msg)
		T.log(("handbook: a BHELLO with the three summaries is %d B"):format(#wire))
		truthy(#wire <= 512, "BHELLO " .. #wire)
	end)

	it("is never pushed: a HELLO without pages gets no WHISPER of them", function()
		H():Save("P:rules", { title = "Rules", body = "x", order = 1 })
		Mock.Advance(10)
		local sent = capture()
		hear({ t = "HELLO", d = {}, s = "", av = "0.11.0" }, "Bob")
		hear({ t = "HELLO", d = {}, s = "", hb = "", av = "0.11.0" }, "Ann")
		Mock.Advance(30)
		for _, e in ipairs(sent) do truthy(not (e.msg.t == "REC" and e.msg.s == "handbook"), "nothing of the handbook goes") end
	end)

	it("asks once for pages it is behind on, and answers on GUILD once a minute per author", function()
		local key = A().Sync.KeyOf("#" .. OFF)
		local entry = string.char(math.floor(key / 16777216) % 256, math.floor(key / 65536) % 256, math.floor(key / 256) % 256, key % 256)
			.. "\0\0\1" .. "\127\0\0\0"
		local sent = capture()
		hear({ t = "HELLO", d = {}, s = "", hb = entry, av = "0.11.0" }, "Boss")
		Mock.Advance(25)
		local reqs = {}
		for _, e in ipairs(sent) do if e.msg.t == "REQ" then reqs[#reqs + 1] = e end end
		eq(#reqs, 1); eq(reqs[1].msg.s, "handbook"); eq(reqs[1].msg.g, 1); eq(reqs[1].target, "Boss"); eq(reqs[1].dist, "WHISPER")
		deepEq(reqs[1].msg.a, { key })
		-- this officer answers a request for its own pages on GUILD, and not again within a minute
		H():Save("P:rules", { title = "Rules", body = "x", order = 1 })
		Mock.Advance(10)
		local mineKey = A().Sync.KeyOf("#" .. ME)
		sent = capture()
		hear({ t = "REQ", s = "handbook", g = 1, a = { mineKey } }, "Bob", "WHISPER")
		hear({ t = "REQ", s = "handbook", g = 1, a = { mineKey } }, "Ann", "WHISPER")
		Mock.Advance(10)
		local recs = {}
		for _, e in ipairs(sent) do if e.msg.t == "REC" and e.msg.s == "handbook" then recs[#recs + 1] = e end end
		eq(#recs, 1); eq(recs[1].dist, "GUILD")
		eq(A().Sync.state.stats.hbServedSkipped, 1)
		Mock.Advance(61)
		hear({ t = "REQ", s = "handbook", g = 1, a = { mineKey } }, "Ann", "WHISPER")
		Mock.Advance(10)
		recs = 0
		for _, e in ipairs(sent) do if e.msg.t == "REC" and e.msg.s == "handbook" then recs = recs + 1 end end
		eq(recs, 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The simulator
local function simulated(Mk) Mk.features = { raid = true } end

local function holdsAll(sim, list, ids)
	for _, i in ipairs(list) do
		local S_ = sim:client(i):addon().Store
		for _, id in ipairs(ids) do
			if not S_:Get("handbook", id) then return false end
		end
	end
	return true
end

local function watchWire(sim)
	local seen = {}
	for i, c in ipairs(sim.clients) do
		local T_ = c:addon().Transport
		local original = T_.Send
		T_.Send = function(self, dist, msg, opts)
			if msg.s == "handbook" then seen[#seen + 1] = { from = i, dist = dist, t = msg.t, n = msg.r and #msg.r } end
			return original(self, dist, msg, opts)
		end
	end
	return seen
end

describe("the handbook between clients", function()
	it("two writers saving from the same revision: everybody keeps the later, only the other author is told", function()
		local sim = Sim.new{ clients = 4, officers = { 1, 2 }, setup = simulated, latency = { 0.05, 0.3 }, seed = 51 }
		sim:advance(60)
		truthy(sim:client(1):addon().Handbook:Save("P:rules", { title = "Rules", body = "Base.", order = 20 }))
		truthy(sim:advanceUntil(function() return holdsAll(sim, { 2, 3, 4 }, { "P:rules" }) end, 60))
		-- both save from revision 1 before seeing each other's edit
		truthy(sim:client(1):addon().Handbook:Save("P:rules", { title = "Rules", body = "One." }, { base = 1 }))
		sim:advance(1)
		truthy(sim:client(2):addon().Handbook:Save("P:rules", { title = "Rules", body = "Two." }, { base = 1 }))
		sim:advance(30)
		for i = 1, 4 do
			local rec = sim:client(i):addon().Store:Get("handbook", "P:rules")
			eq(rec.rev, 2, "client " .. i); eq(rec.body, "Two.", "client " .. i)
		end
		eq(#sim:client(1):addon().Handbook:Conflicts(), 1, "the losing author is told")
		for i = 2, 4 do eq(#sim:client(i):addon().Handbook:Conflicts(), 0, "client " .. i) end
		for i = 1, 4 do eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i) end
	end)

	it("brings the pages to who comes later, asked for and sent once on GUILD, never by WHISPER", function()
		local sim = Sim.new{ clients = 5, officers = { 1 }, offline = { 4, 5 }, setup = simulated, latency = { 0.05, 0.3 }, seed = 53 }
		sim:advance(60)
		local HB = sim:client(1):addon().Handbook
		truthy(HB:Save("P:rules", { title = "Rules", body = prose(4000), order = 20 }))
		truthy(HB:Save("P:faq", { title = "FAQ", body = "Ask.", order = 30 }))
		truthy(HB:Save("P:info", { title = "Info", body = "We.", order = 10 }))
		local ids = { "P:rules", "P:faq", "P:info" }
		truthy(sim:advanceUntil(function() return holdsAll(sim, { 2, 3 }, ids) end, 60))
		sim:client(4):login()
		sim:client(5):login()
		local seen = watchWire(sim)
		truthy(sim:advanceUntil(function() return holdsAll(sim, { 4, 5 }, ids) end, 25 * 60), "the newcomers hold the handbook")
		sim:advance(5)
		local guildRec, whisperRec, reqs = 0, 0, 0
		for _, e in ipairs(seen) do
			if e.t == "REC" and e.dist == "GUILD" then guildRec = guildRec + 1 end
			if e.t == "REC" and e.dist == "WHISPER" then whisperRec = whisperRec + 1 end
			if e.t == "REQ" then reqs = reqs + 1 end
		end
		eq(whisperRec, 0, "never by WHISPER")
		eq(guildRec, 2, "the long page alone and the two short ones together, once for both newcomers")
		truthy(reqs >= 1 and reqs <= 2, "requests " .. reqs)
		for i = 1, 5 do eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i) end
	end)

	it("works with block summaries too", function()
		local sim = Sim.new{ clients = 3, officers = { 1 }, offline = { 3 }, setup = simulated, seed = 55 }
		for i = 1, 2 do sim:client(i):addon().Sync.BLOCK_OVER = -1 end
		sim:advance(60)
		truthy(sim:client(1):addon().Handbook:Save("P:rules", { title = "Rules", body = "x", order = 20 }))
		truthy(sim:advanceUntil(function() return holdsAll(sim, { 2 }, { "P:rules" }) end, 60))
		sim:client(3):login()
		sim:client(3):addon().Sync.BLOCK_OVER = -1
		truthy(sim:advanceUntil(function() return holdsAll(sim, { 3 }, { "P:rules" }) end, 25 * 60), "the DIGEST told it")
		truthy(sim:client(3):addon().Sync.state.stats.hbRequests >= 1)
	end)

	it("leaves a client without the switch alone: it ignores the summary and asks for nothing", function()
		local function mixed(Mk, i) if i < 3 then simulated(Mk) else Mk.features = { raid = false } end end
		local sim = Sim.new{ clients = 3, officers = { 1 }, setup = mixed, seed = 57 }
		sim:advance(60)
		truthy(sim:client(1):addon().Handbook:Save("P:rules", { title = "Rules", body = "x", order = 20 }))
		local seen = watchWire(sim)
		sim:advance(45 * 60)
		truthy(holdsAll(sim, { 2 }, { "P:rules" }))
		local old = sim:client(3):addon()
		eq(old.Store:Count("handbook"), 0)
		eq(old.Sync.state.stats.hbRequests, 0)
		for _, e in ipairs(seen) do truthy(e.from ~= 3, "the older client sends nothing of it") end
		eq(old.Store.stats.rejected, 0, "and refuses nothing: the set is unknown to it")
		-- its summary per author equals the others': nothing is asked forever
		eq(old.Sync:EncodeSummary(), sim:client(2):addon().Sync:EncodeSummary())
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The traffic (SPEC-15 §3.7): the 45 minutes of churn of 50 clients of Tests/test_availability.lua, first exchange
-- (half the guild never ran), with the availability maps, without and with the largest handbook (20 pages, 32 000 bytes).
describe("the handbook's traffic", function()
	local function seedMap(c)
		local db = c:addon().Config.db.account
		if db.avail and next(db.avail.weeks) then return end
		local week = c:addon().Availability.Now()
		local data = { since = week - 3, weeks = {} }
		for w = week - 3, week - 1 do
			local cells = {}
			for k = 1, 30 do cells[(c.index * 11 + k * 5) % 168] = 45 end
			data.weeks[w] = cells
		end
		db.avail = data
	end

	local function churn(handbook)
		local N, OFFICERS = 50, { 1, 11, 21, 31, 41 }
		local offline = {}
		for i = 2, N, 2 do offline[#offline + 1] = i end
		local sim = Sim.new{ clients = N, officers = OFFICERS, setup = simulated, offline = offline, availability = true,
			latency = { 0.05, 0.5 }, loss = 0.01, seed = 42 }
		sim:setStep(0.5)
		local rand = function() return Sim.draw(sim) end
		local writes, lockUntil = {}, {}
		local function writeNext(c)
			writes[c.index] = (writes[c.index] or 0) + 1
			local S_, guid = c:addon().Store, c:guid()
			truthy(S_:Put("accounts", guid, { token = "T" .. c.index, chars = { { guid = guid } }, n = writes[c.index] }))
			truthy(S_:Put("contacts", guid, { battleTag = c.name .. "#" .. c.index, n = writes[c.index] }))
		end
		for i = 1, N do
			local c = sim:client(i)
			if c.online then
				writeNext(c)
				seedMap(c)
			end
		end
		if handbook then
			-- the officers wrote the largest handbook before: 20 pages of 1600 bytes, held by its writer only
			local HB = sim:client(1):addon().Handbook
			for p = 1, 20 do truthy(HB:Save("P:page-" .. p, { title = "Page " .. p, body = prose(1600, p), order = p }), "page " .. p) end
		end
		for step = 1, 90 do
			for i = 1, N do
				local c = sim:client(i)
				local r = rand()
				if c.online then
					if r < 0.04 then c:logout()
					elseif r < 0.08 then writeNext(c)
					elseif r < 0.10 and not lockUntil[i] then
						c:restrict({ lockdown = true })
						lockUntil[i] = sim.time + 60 + 240 * rand()
					end
				elseif r < 0.06 then
					c:login()
					seedMap(c)
					if not writes[i] then writeNext(c) end
				end
				if lockUntil[i] and sim.time >= lockUntil[i] then
					c:restrict({ lockdown = false })
					lockUntil[i] = nil
				end
			end
			sim:advance(30)
		end
		local st = sim:stats()
		local holders = 0
		for i = 1, N do
			local c = sim:client(i)
			if c.online then
				eq(c:addon().Store.stats.rejected, 0, "client " .. i .. " refused nothing")
				if c:addon().Store:Count("handbook") == 20 then holders = holders + 1 end
			end
		end
		return st, holders
	end

	it("50 clients: the first exchange of the largest handbook stays inside the peak the owner accepted (SPEC-10 Q26)", function()
		local base = churn(false)
		local st, holders = churn(true)
		T.log(("handbook, first exchange with the maps: %.0f B/min per client on average (%.0f without the handbook), %.0f at most (%.0f); %d online clients hold all 20 pages"):format(
			st.avg.bytesPerMinute, base.avg.bytesPerMinute, st.max.bytesPerMinute, base.max.bytesPerMinute, holders))
		truthy(holders >= 10, "the handbook spread: " .. holders)
		truthy(st.avg.bytesPerMinute <= 550, "first exchange average " .. st.avg.bytesPerMinute)
		truthy(st.max.bytesPerMinute <= 2560, "first exchange busiest client " .. st.max.bytesPerMinute)
	end)
end)

-- The default pages of the handbook (M11.5; SPEC-15 §7) behind the switch "raid": a writer creates them once with a
-- click, headings and links to the season only, in the writer's language; members see a template only once it is saved;
-- a deleted page never comes back, also after a late or a double seeding between clients.
local function A() return AzerothAccord end
local function S() return AzerothAccord.Store end
local function H() return AzerothAccord.Handbook end
local function D() return AzerothAccord.HandbookDefaults end
local function V() return AzerothAccord.HandbookView end

local SLUGS = { "info", "rules", "faq", "raid", "roster", "loot" }

local function guild(rank)
	Mock.guild.Set{ name = "Accord", myRank = rank, members = {
		{ name = "Boss", level = 60, class = "PRIEST", rank = 1, guid = "Player-1-00000C0C", online = false },
	} }
end
local function member(Mk) Mk.features = { raid = true } guild(3) end
local function officer(Mk) Mk.features = { raid = true } guild(1) end
local function italian(Mk) Mk.player.locale = "itIT" officer(Mk) end
local function off(Mk) Mk.features = { raid = false, season = true } guild(1) end

local function open()
	truthy(A().Shell:OpenView("handbook"))
	return V().frame
end

local function later() Mock.Advance(D().SEED_WAIT + 1) end

local function slugs(pages)
	local out = {}
	for i, rec in ipairs(pages) do out[i] = H().SlugOf(rec.id) end
	return out
end

---------------------------------------------------------------------------------------------------------------------
describe("the default pages with the switch off", function()
	before_boot(off)
	it("are neither offered nor written", function()
		later()
		falsy(D():CanSeed())
		local ok, why = D():Seed()
		falsy(ok); eq(why, "seeded")
		isNil(next(S():Records("handbook")))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a member and the default pages", function()
	before_boot(member)
	it("is not offered them", function()
		later()
		local f = open()
		falsy(D():CanSeed()); falsy(D():Seed())
		isNil(f.seed)
		truthy(f.empty:IsShown())
		eq(#Mock.errors, 0)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("a writer creates the default pages", function()
	before_boot(officer)

	it("waits 2 minutes after login, then writes them once with a click", function()
		local f = open()
		falsy(D():CanSeed()); falsy(f.seed:IsShown())
		later()
		truthy(f.seed:IsShown(), "the view draws again when the wait ends")
		f.seed:Click()
		Mock.Advance(1)
		local pages = H():Pages(true)
		deepEq(slugs(pages), SLUGS)
		for i, rec in ipairs(pages) do
			eq(rec.rev, 1); eq(rec.tpl, true); eq(rec.order, i * 10)
		end
		local seeded = S():Get("handbook", "seeded")
		truthy(seeded and seeded.at > 0 and type(seeded.by) == "string")
		falsy(f.seed:IsShown()); falsy(D():CanSeed()); falsy(D():Seed())
		eq(#H():Pages(), 0, "no template is published")
		eq(#H():Updated(), 0)
		eq(#Mock.errors, 0)
	end)

	it("holds only headings and the season links, already clean and valid", function()
		later()
		eq(D():Seed(), 6)
		local links = {}
		for _, rec in ipairs(H():Pages(true)) do
			eq(A().HandbookText.Clean(rec.body), rec.body)
			truthy(H().ValidRecord({ id = rec.id, title = rec.title, body = rec.body, order = rec.order, tpl = true }))
			for line in rec.body:gmatch("[^\n]+") do
				if not line:match("^# ") then links[#links + 1] = H().SlugOf(rec.id) .. " " .. line end
			end
		end
		deepEq(links, { "roster [[season]]", "loot [[season¦Loot follows the declared spec]]" })
		eq(H():Get("P:faq").body, "# Questions\n")
		eq(H():Get("P:roster").title, "Roster management")
		truthy(H():Get("P:roster").body:find("# The season roster\n[[season]]\n\n# Ranks\n", 1, true))
	end)

	it("does not bring back a deleted page, and not even all of them", function()
		later()
		D():Seed()
		Mock.Advance(1)
		truthy(H():Delete("P:faq", 1))
		Mock.Advance(1)
		falsy(D():CanSeed())
		eq(#H():Pages(true), 5)
		for _, slug in ipairs(SLUGS) do
			local rec = S():Get("handbook", "P:" .. slug)
			if not rec.del then truthy(H():Delete(rec.id, rec.rev)) end
		end
		Mock.Advance(1)
		falsy(D():CanSeed()); falsy(D():Seed())
		falsy(open().seed:IsShown())
		eq(#H():Pages(true), 0)
	end)

	it("is not offered once the guild has a page of its own", function()
		truthy(H():Save("P:own", { title = "Own", body = "x", order = 10 }))
		later()
		falsy(D():CanSeed())
	end)

	it("publishes a template when it is saved", function()
		later()
		D():Seed()
		local rec = H():Get("P:rules")
		truthy(H():Save(rec.id, { title = rec.title, body = rec.body, order = rec.order }, { base = 1 }))
		deepEq(slugs(H():Pages()), { "rules" })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
describe("the default pages in Italian", function()
	before_boot(italian)
	it("are written in the writer's language", function()
		later()
		eq(D():Seed(), 6)
		eq(H():Get("P:rules").title, "Regolamento")
		truthy(H():Get("P:loot").body:find("[[season¦Il loot segue la specializzazione dichiarata]]", 1, true))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
local function simulated(Mk) Mk.features = { raid = true } end

describe("the default pages between clients", function()
	it("a late seeding never brings a deleted page back", function()
		local sim = Sim.new{ clients = 3, officers = { 1, 2 }, offline = { 2 }, setup = simulated,
			latency = { 0.05, 0.3 }, seed = 61 }
		sim:advance(200)
		local one = sim:client(1):addon()
		eq(one.HandbookDefaults:Seed(), 6)
		sim:advance(10)
		truthy(one.Handbook:Delete("P:faq", 1))
		sim:advance(10)
		sim:client(2):login()
		sim:advance(1)
		local two = sim:client(2):addon()
		isNil(two.Store:Get("handbook", "seeded"), "not synced yet")
		two.HandbookDefaults.waited = true   -- a client that did not wait for the sync
		eq(two.HandbookDefaults:Seed(), 6)
		sim:advance(3600)
		for i = 1, 3 do
			local rec = sim:client(i):addon().Store:Get("handbook", "P:faq")
			truthy(rec and rec.del, "client " .. i)
			eq(#sim:client(i):addon().Handbook:Pages(true), 5, "client " .. i)
			eq(sim:client(i):addon().Store.stats.rejected, 0, "client " .. i)
			eq(#sim:client(i):addon().Handbook:Conflicts(), 0, "client " .. i)
		end
	end)

	it("two writers seeding at once leave six pages and tell nobody of a conflict", function()
		local sim = Sim.new{ clients = 3, officers = { 1, 2 }, setup = simulated, latency = { 0.5, 1 }, seed = 63 }
		sim:advance(200)
		eq(sim:client(1):addon().HandbookDefaults:Seed(), 6)
		sim:advance(0.1)
		eq(sim:client(2):addon().HandbookDefaults:Seed(), 6)
		sim:advance(3600)
		local author = sim:client(1):addon().Store:Get("handbook", "P:rules").author
		for i = 1, 3 do
			local a = sim:client(i):addon()
			eq(#a.Handbook:Pages(true), 6, "client " .. i)
			eq(a.Store:Get("handbook", "P:rules").author, author, "client " .. i)
			eq(#a.Handbook:Conflicts(), 0, "client " .. i)
		end
	end)
end)

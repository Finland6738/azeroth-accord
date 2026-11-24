-- Provenance (M7.2; SPEC-11 §1): the age text, the dimming thresholds, the author name, the label widget and the places
-- that use it. Plain functions of a record plus one frame test.
local function P() return AzerothAccord.Provenance end
local DAY = 86400
local NOW = 1000000000

describe("Provenance age text (SPEC-11 §1.2)", function()
	it("walks the scale at its edges", function()
		eq(P().AgeText(0), "just now")
		eq(P().AgeText(59), "just now")
		eq(P().AgeText(60), "1 min ago")
		eq(P().AgeText(3599), "59 min ago")
		eq(P().AgeText(3600), "1 h ago")
		eq(P().AgeText(DAY - 1), "23 h ago")
		eq(P().AgeText(DAY), "1 d ago")
		eq(P().AgeText(59 * DAY + 5), "59 d ago")
		eq(P().AgeText(60 * DAY), "2 mo ago")
		eq(P().AgeText(729 * DAY), "24 mo ago")
		eq(P().AgeText(730 * DAY), "2 y ago")
		eq(P().AgeText(nil), "just now")
	end)
	it("a time up to an hour in the future is age zero; no time, no age", function()
		eq(P().Age(NOW + 3600, NOW), 0)
		eq(P().Age(NOW - 90, NOW), 90)
		isNil(P().Age(nil, NOW))
	end)
	it("Shell.Ago is the same scale", function()
		eq(AzerothAccord.Shell.Ago(40 * DAY), P().AgeText(40 * DAY))
		eq(AzerothAccord.Shell.Ago(100 * DAY), "3 mo ago")
	end)
end)

describe("Provenance dimming (SPEC-11 §1.4)", function()
	it("every threshold, a second before and a second after", function()
		for set, days in pairs(P().DIM_DAYS) do
			local info = { source = "shared", set = set }
			info.observedAt = NOW - days * DAY
			falsy(P().IsDim(info, NOW), set .. " at the limit")
			info.observedAt = NOW - days * DAY - 1
			truthy(P().IsDim(info, NOW), set .. " a second later")
		end
		eq(P().DIM_DAYS.bank, 7)
		eq(P().DIM_DAYS.recipes, 60)
		eq(P().DIM_DAYS.altGuild, 30)
		eq(P().DIM_DAYS.addonVersion, 30)
		eq(P().DIM_DAYS.contacts, 180)
	end)
	it("native, own and note never dim; a shared value without a set or a time does not either", function()
		for _, source in ipairs({ "native", "own", "note" }) do
			falsy(P().IsDim({ source = source, set = "bank", observedAt = NOW - 999 * DAY }, NOW))
		end
		falsy(P().IsDim({ source = "shared", observedAt = NOW - 999 * DAY }, NOW))
		falsy(P().IsDim({ source = "shared", set = "bank" }, NOW))
		falsy(P().IsDim(nil, NOW))
	end)
end)

describe("Provenance label (SPEC-11 §1.3)", function()
	local ME, BOB = "Player-1-0000AA01", "Player-1-0000BB02"
	it("the four sources and their tooltips", function()
		local d = P().Describe({ source = "native" }, NOW)
		eq(d.label, "game"); deepEq(d.lines, { "From the game, read now." })
		d = P().Describe({ source = "own", observedAt = NOW - 3 * DAY }, NOW)
		eq(d.label, "you"); deepEq(d.lines, { "Read from your own character, 3 d ago." })
		d = P().Describe({ source = "note", member = "Ann" }, NOW)
		eq(d.label, "note"); deepEq(d.lines, { "Declared in Ann's public note. Accord cannot check it." })
		d = P().Describe({ source = "shared", observedAt = NOW - 3 * DAY, author = "Player-1-0000EE99" }, NOW)
		eq(d.label, "3 d ago"); eq(d.lines[1], "Shared by a former guild member, updated 3 d ago."); falsy(d.dim)
		isNil(P().Describe({ source = "other" }, NOW))
		isNil(P().Describe(nil, NOW))
	end)
	it("an old shared value is dimmed and says how long", function()
		local d = P().Describe({ source = "shared", set = "bank", observedAt = NOW - 9 * DAY - 5, author = BOB }, NOW)
		truthy(d.dim)
		eq(d.lines[2], "Not updated for 9 days: it may be out of date.")
	end)
	it("the author is the roster name, then the author's own record, never the GUID; the name is cleaned", function()
		local A = AzerothAccord
		Mock.guild.Set{ name = "Accord", myRank = 3, members = {} }
		A.Store:Records("accounts")[BOB] = { id = BOB, author = BOB, rev = 1, time = NOW, token = "T", chars = { { guid = BOB, name = "Bo|b" } } }
		eq(P().AuthorName(BOB), "Bo||b")
		eq(P().AuthorName("Player-1-0000EE99"), "a former guild member")
		eq(P().AuthorName(nil), "a former guild member")
	end)
	it("the widget shows the label, dims through IsDim and hides without a source", function()
		local parent = CreateFrame("Frame", nil, UIParent)
		local w = AzerothAccord.Widgets.Provenance(parent)
		w:SetSource({ source = "native" })
		eq(w.text:GetText(), "game"); truthy(w:IsShown()); falsy(w:IsDim())
		w:SetSource({ source = "shared", set = "bank", observedAt = GetServerTime() - 8 * DAY })
		truthy(w:IsDim())
		w:SetSource(nil)
		falsy(w:IsShown()); eq(w.text:GetText(), "")
	end)
	it("the roster tooltip uses it", function()
		local lines = P().TipLines(P().ProfessionInfo({ source = "own" }), NOW)
		eq(lines[1], "Read from your own character.")
	end)
end)

describe("Provenance in Italian", function()
	it("has every key", function()
		local L = LibStub("AceLocale-3.0"):GetLocale("AzerothAccord", true)
		for _, k in ipairs({ "PROV_GAME", "PROV_YOU", "PROV_NOTE", "PROV_AUTHOR_FORMER", "PROV_TIP_NATIVE", "PROV_TIP_SHARED", "PROV_TIP_OWN", "PROV_TIP_NOTE", "PROV_TIP_STALE" }) do
			truthy(L[k] and L[k] ~= k, k)
		end
	end)
end)

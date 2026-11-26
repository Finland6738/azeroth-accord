-- Features: the switches that keep an unfinished feature out of a release. Lua 5.1.
-- A release carries no half-finished feature (owner's decision, 2026-11-25): code that landed ahead of its milestone
-- stays in the addon, tested, with its switch off. While a switch is off, nothing of the feature is visible, it
-- registers no callback and it sends nothing. The modules ask Features.On(name) when they act, never once at load.
--
--   season the M10 features (docs/roadmap/M10-calendar-raids.md, SPEC-14): the detection of the raid and loot addons and
--          the guild's choice of the source of the season roster (M10.2, the data set `guildcfg`), the seasons and the
--          declarations (M10.3, the data set `season`, the Season view and `/accord season`), and the steps of M10 that
--          follow (the last one the rallies, M10.9, the data set `rally`). Off: nothing of it is detected, shown, written,
--          accepted or sent. On since M10.10.
--   raid   the M11 features read from FDCP (M11.7: the Raid view, `/accord raid`, the member card's "Loot (FDCP)", the
--          choice of the loot source) and the guild handbook (M11.2-M11.6: the data set `handbook`, the Handbook view and
--          `/accord handbook`). It builds on M10, so while it is on `season` is on too (Features.IMPLIES).
--          On since M11.8.
--   actions  the Action Center, the notices, quiet hours and the login digest (M9.2-M9.5, SPEC-13): the view,
--          `/accord inbox`, the line in the Compartment tooltip and the craft reminders. On since M9.10.
--   groups   the guild group finder (M9.6-M9.8, SPEC-13 §6): the data set `groups`, the applications (GAPP), the
--          question of who comes later (GASK), the Groups view and `/accord groups`. Off: nothing of it is shown,
--          written, accepted, sent or answered. Its Action Center rows and notices also need `actions`. On since M9.10.
--   census  the addon census (M9.9, SPEC-13 §8): the data set `addons` (the list of its own loaded addons that each
--          character publishes), the "Guild addons" view, `/accord addons`, the switch "Share my addon list" and its row
--          in "What I share". Off: the list is not read, and nothing of it is written, accepted, sent or shown.
--          On since M9.10.
--   recruit the M12 features (docs/roadmap/M12-recruitment.md, SPEC-16): the recruitment text (M12.2: its button in the
--          Season view, its window and `/accord recruit`) and the steps that follow (trials, onboarding, mentors). It
--          turns on no other switch: each part asks `season`, `raid` or `actions` itself and says what is missing.
--          Off: nothing of it is shown, written, accepted or sent. Off until M12.6.
local ADDON_NAME, ns = ...
local ipairs = ipairs
ns = ns or {}
local Features = { season = true, raid = true, actions = true, groups = true, census = true, recruit = false }
ns.Features, ns.modules = Features, ns.modules or {}
ns.modules.Features = Features

-- A switch that is also on while another one is: the M11 features need those of M10 under them.
local IMPLIES = { season = { "raid" } }
Features.IMPLIES = IMPLIES

-- True while the switch `name` is on (or a switch that implies it); false for a name without a switch.
function Features.On(name)
	if Features[name] == true then return true end
	for _, other in ipairs(IMPLIES[name] or {}) do
		if Features[other] == true then return true end
	end
	return false
end

if ns.addon then ns.addon.Features = Features end

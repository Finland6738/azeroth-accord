-- Features: the switches that keep an unfinished feature out of a release. Lua 5.1.
-- A release carries no half-finished feature (owner's decision, 2026-11-25): code that landed ahead of its milestone
-- stays in the addon, tested, with its switch off. While a switch is off, nothing of the feature is visible, it
-- registers no callback and it sends nothing. The modules ask Features.On(name) when they act, never once at load.
--
--   raid   the raid and loot addons (M10.2: detection, the guild's choice of a source per datum, the data set
--          `guildcfg`) and the reading of FDCP (M11.7: the Raid view, `/accord raid`, the member card's "Loot (FDCP)").
--          Switched on when M10 and M11 are complete (docs/roadmap/M10-calendar-raids.md, M11-loot-handbook.md).
--   actions  the Action Center, the notices, quiet hours and the login digest (M9.2-M9.5, SPEC-13): the view,
--          `/accord inbox`, the line in the Compartment tooltip and the craft reminders. On since M9.10.
--   groups   the guild group finder (M9.6-M9.8, SPEC-13 §6): the data set `groups`, the applications (GAPP), the
--          question of who comes later (GASK), the Groups view and `/accord groups`. Off: nothing of it is shown,
--          written, accepted, sent or answered. Its Action Center rows and notices also need `actions`. On since M9.10.
--   census  the addon census (M9.9, SPEC-13 §8): the data set `addons` (the list of its own loaded addons that each
--          character publishes), the "Guild addons" view, `/accord addons`, the switch "Share my addon list" and its row
--          in "What I share". Off: the list is not read, and nothing of it is written, accepted, sent or shown.
--          On since M9.10.
local ADDON_NAME, ns = ...
ns = ns or {}
local Features = { raid = false, actions = true, groups = true, census = true }
ns.Features, ns.modules = Features, ns.modules or {}
ns.modules.Features = Features

-- True while the switch `name` is on; false for a name without a switch.
function Features.On(name)
	return Features[name] == true
end

if ns.addon then ns.addon.Features = Features end

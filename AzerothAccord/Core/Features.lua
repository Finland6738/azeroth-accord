-- Features: the switches that keep an unfinished feature out of a release. Lua 5.1.
-- A release carries no half-finished feature (owner's decision, 2026-11-25): code that landed ahead of its milestone
-- stays in the addon, tested, with its switch off. While a switch is off, nothing of the feature is visible, it
-- registers no callback and it sends nothing. The modules ask Features.On(name) when they act, never once at load.
--
--   raid   the raid and loot addons (M10.2: detection, the guild's choice of a source per datum, the data set
--          `guildcfg`) and the reading of FDCP (M11.7: the Raid view, `/accord raid`, the member card's "Loot (FDCP)").
--          Switched on when M10 and M11 are complete (docs/roadmap/M10-calendar-raids.md, M11-loot-handbook.md).
local ADDON_NAME, ns = ...
ns = ns or {}
local Features = { raid = false }
ns.Features, ns.modules = Features, ns.modules or {}
ns.modules.Features = Features

-- True while the switch `name` is on; false for a name without a switch.
function Features.On(name)
	return Features[name] == true
end

if ns.addon then ns.addon.Features = Features end

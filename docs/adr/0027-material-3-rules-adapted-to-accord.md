# 0027. Material 3 rules adapted to Accord

- Status: Accepted
- Date: 2026-11-27

## Context

The owner looked at the real client on 2026-11-26 and 2026-11-27. Several screens needed changes: the tabs, the bank pages, the roster's width and the member card. Separate sessions restyled the tabs in contradicting ways on the same day (PR #158: accent underline only; PR #160: orange tab). [ADR 0021](0021-interface-follows-the-ecosystem-style-of-fdcp.md) gives the look (FDCP's colours and fonts) but few rules for **structure**: sizes, states, shapes and when to use which component. On 2026-11-27 the owner asked to follow Google's Material Design 3 ([m3.material.io](https://m3.material.io)) to improve every window, tab and component.

## Decision

1. **Material 3 gives the rules; FDCP keeps the look.** The three themes (Nebula, Aurora, Accord), their colour values and the fonts (Orbitron, Outfit, JetBrains Mono) stay as ADR 0021 says. Material 3 decides, for every widget:
   - the colour **role** each part uses;
   - the **state layers**;
   - the **shape** scale;
   - the **type roles**;
   - the component **measurements**;
   - which component fits which job.

   Where the two disagree on structure, Material 3 wins. The rules are in [ui-style §9](../specs/ui-style.md#9-le-regole-di-material-3-adr-0027).
2. **Colour roles over the existing tokens.** Accord's tokens are mapped to M3 roles (surface, the surface containers, on-surface, on-surface-variant, outline, outline-variant, primary, on-primary, error, scrim). Accord adds only the roles it lacks: `secondary-container` and `on-secondary-container` (the tonal fill of filter chips, segmented buttons, tonal buttons and selected rows), `inverse-surface` and `inverse-on-surface` (plain tooltips, snackbars), and `on-error`. Each theme gets values that pass the contrast rules of ui-style §4.2.
3. **States as M3 state layers.** The overlay takes the colour of the element's content, not white: hover 8 %, focus 10 %, pressed 10 %, dragged 16 %. Disabled shows the content at 38 % and the container at 12 %. This replaces the white 8 % / 12 % layers of M6.11.
4. **The M3 shape scale.** Radii are 0, 4, 8, 12, 16, 28 or full, mapped per component in ui-style §9.3. The missing slices (4, 16, 28) are added to the media.
5. **Density for a mouse UI inside a game.** Measurements are M3's, in points. Tables, toolbars and menus use M3's dense variants, down to 32-point controls. The 48-point touch target does not apply, because the addon is used with a mouse. Body and label text is one point under M3 (13 instead of 14), like the game's own text.
6. **Effects become a brand accent, not a widget style.** The neon glow and the gradient stay for the title bar and the logo while "Neon effects" is on. Buttons, tabs and chips are flat, as in M3, with one exception: the filled button keeps the accent glow when effects are on.
7. **Applied through the widget kit.** The rules go into `UI/Theme.lua` and `UI/Widgets/` first, so every view follows. The views and previews are then reviewed. The steps are M12.6 to M12.8 of the [M12 roadmap](../roadmap/M12-recruitment.md), before the in-game check of M12 (now M12.9) and `v0.12.0`.

## Alternatives considered

- **Keep restyling view by view.** That gave contradicting results within a single day.
- **Adopt M3 completely**: Roboto, dynamic colour, the baseline purple scheme, 48-point targets and spring motion. This would break the FDCP family look the owner chose (ADR 0021) and waste space inside the game.

## Consequences

- Positive: one reference for every session. Clear selected states: filter chips with a check mark, the tonal fill. Consistent sizes and corners across the windows.
- Negative: the widget kit changes under every view, so many offline tests that check colours or sizes must be updated. The look changes for players who already used `v0.11.0`. Nothing of it is checked in the real client until the M12 check.
- ADR 0021 stays: it decides the look, this ADR the structure.

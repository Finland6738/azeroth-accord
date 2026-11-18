# 0017. Licence: GNU GPL v3.0

- Status: Accepted
- Date: 2026-11-18 (the owner's choice, decision D5)

## Decision

The code and the documentation are released under the **GNU General Public License v3.0** (`LICENSE`), like the other Azeroth projects. Whoever modifies and redistributes the addon must publish their source under the same licence. Third-party parts keep their own licences: Ace3, LibDataBroker and LibDBIcon (their own terms, embedded by the packager). Game textures are referenced by fileID or atlas name and never redistributed.

## Consequences

- Positive: improvements stay open; code can move freely between the owner's GPL projects.
- Negative: closed-source forks are not allowed.

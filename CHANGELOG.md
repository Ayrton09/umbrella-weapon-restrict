# Changelog

## [1.0.1] - 2026-08-05

### Fixed
- The C4 is no longer managed by the plugin. Restricting it (for example with `sm_restrict all 0`) removed the bomb from the map and blocked pickups, breaking the objective on bomb maps.

## [1.0.0] - 2026-06-21

Initial release.

### Added
- Weapon restriction for CS:S and CS:GO by team, weapon, and weapon group.
- Admin menu integration and `sm_restrict` / `sm_unrestrict` commands.
- Buy and pickup blocking with chat notifications and anti-spam protection.
- Optional per-player restrictions based on current player count.
- Configurable block sound with path-traversal protection.
- Translations in 9 languages: English, Spanish, Portuguese, Chinese, Russian, French, German, Turkish, Polish.

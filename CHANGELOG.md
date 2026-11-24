# Changelog

## [1.0.2] - 2026-11-23

### Fixed
- Automatic removal of weapons over the limit (round start, limit changes, per-player changes) stopped working for the rest of the session after the first map change when `sm_uwr_perplayer_enabled 1` was set.
- CS:GO: the USP-S, M4A1-S, CZ75-Auto and R8 Revolver were counted as the P2000, M4A1, P250 and Desert Eagle on pickups and removals. Weapons are now identified by their item definition index.
- Grenade limits counted players carrying the grenade instead of grenades, so a team could hold more flashbangs than its limit. Removal now also trims the carried amount.
- Standing on two or more restricted weapons at once flooded the chat and repeated the block sound every tick.
- With `sm_uwr_perplayer_count_specs 0`, the per-player count lagged one team change behind.
- CS:GO: the `[UWR]` chat prefix was shown without color.
- Restricted spawn items (for example the default pistol) were left lying on the floor. They are now removed.
- Removing a restricted assault suit also took the kevlar when kevlar was allowed. Removing heavy armor (CS:GO) left the armor above 100.
- Danger Zone fists and melee weapons were managed and got blocked by `sm_restrict all 0`.

### Changed
- All cvars have descriptions, so the generated `cfg/sourcemod/umbrella_weapon_restrict.cfg` documents each setting. An existing cfg is not regenerated; delete it to get the commented version.
- Plugin info links to the GitHub repository.
- Rewrote the README with a full command and cvar reference, weapon group contents and counting rules.

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

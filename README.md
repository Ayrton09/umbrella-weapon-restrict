# Umbrella Weapon Restrict

![Version](https://img.shields.io/badge/version-1.0.2-blue)
![SourceMod](https://img.shields.io/badge/SourceMod-1.12%2B-orange)
![Games](https://img.shields.io/badge/games-CS%3AS%20%7C%20CS%3AGO-lightgrey)
![License](https://img.shields.io/badge/license-GPLv3-green)

Weapon restriction plugin for Counter-Strike: Source and Counter-Strike: Global Offensive.
Limit how many of each weapon, grenade or armor a team can have, block them completely, or scale the limits with the number of players on the server.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Cvars](#cvars)
- [How limits work](#how-limits-work)
- [Weapon groups](#weapon-groups)
- [Per-player limits](#per-player-limits)
- [Admin immunity](#admin-immunity)
- [Block sound](#block-sound)
- [Translations](#translations)
- [Building from source](#building-from-source)
- [Changelog](#changelog)
- [License](#license)

## Features

- Per-team limits for every weapon, grenade and armor type, each with its own cvar.
- Group commands for pistols, SMGs, shotguns, rifles, snipers, grenades and armor.
- Blocks buys before the weapon is given, so no money is lost.
- Blocks pickups from the ground (optional).
- Removes weapons over the limit when a limit is lowered and at every round start.
- Grenade limits count grenades, not players carrying them.
- Optional limits that change with the player count.
- Admin menu integration, plus a standalone menu.
- Optional admin immunity.
- Chat notifications with anti-spam and a configurable block sound.
- 9 languages, with fallback to the server language.

## Requirements

- SourceMod 1.12 or newer.
- A Counter-Strike: Source or Counter-Strike: Global Offensive dedicated server.

The plugin uses only extensions that ship with SourceMod (SDKTools, SDKHooks, CStrike). The admin menu is optional.

## Installation

1. Download the latest zip from [Releases](https://github.com/Ayrton09/umbrella-weapon-restrict/releases).
2. Extract it into your game folder (`cstrike/` or `csgo/`). The `addons` folder merges with yours.
3. Restart the server or change the map.

Installed files:

```text
addons/sourcemod/plugins/umbrella_weapon_restrict.smx
addons/sourcemod/scripting/umbrella_weapon_restrict.sp
addons/sourcemod/translations/umbrella_weapon_restrict.phrases.txt
addons/sourcemod/configs/umbrella_weapon_restrict/perplayerrestrict.txt
```

On the first map with the plugin, SourceMod generates `cfg/sourcemod/umbrella_weapon_restrict.cfg` with every cvar and its description. Edit that file to make your limits permanent.

> Updating from 1.0.1 or older: the existing cfg keeps working but has no descriptions. Delete it (after noting your values) to let SourceMod generate the commented version.

## Quick start

Block the AWP for both teams:

```text
sm_restrict awp 0
```

Allow at most 2 AWPs per team, 1 auto-sniper per team and no grenades for T:

```text
sm_restrict awp 2
sm_restrict g3sg1 1 t
sm_restrict sg550 1 ct
sm_restrict grenades 0 t
```

Knife round (everything blocked except the knife, the C4 is never touched):

```text
sm_restrict all 0
```

Back to normal:

```text
sm_unrestrict all
```

Commands change the cvars for the current session. To keep a limit after a restart, put it in `cfg/sourcemod/umbrella_weapon_restrict.cfg`:

```cfg
sm_restrict_awp_t "1"
sm_restrict_awp_ct "1"
```

## Commands

All commands require the `ADMFLAG_CONVARS` flag (`i`). They can be run from the server console.

| Command | Description |
| --- | --- |
| `sm_restrictmenu` | Open the restriction menu (in-game only). Also listed in the admin menu. |
| `sm_wrmenu` | Alias of `sm_restrictmenu`. |
| `sm_restrict <weapon\|group\|all> [amount] [t\|ct\|both]` | Set a limit. `amount` defaults to `0` (blocked), team defaults to `both`. |
| `sm_unrestrict <weapon\|group\|all> [t\|ct\|both]` | Remove a limit (same as setting it to `-1`). |
| `sm_remove_restricted` | Remove weapons over the current limits right now. |

Arguments:

- **weapon**: a weapon alias, the same name used in its cvar, with or without the `weapon_` prefix (`awp`, `weapon_awp`, `ak47`, `flashbang`, `kevlar`, `assaultsuit`...).
- **group**: `pistols`, `smgs`, `shotguns`, `rifles`, `snipers`, `grenades`, `armor` (singular forms work too). See [Weapon groups](#weapon-groups).
- **amount**: `-1` unlimited, `0` blocked, `1` to `64` maximum per team.
- **team**: `t`, `ct` or `both`.

Examples:

```text
sm_restrict awp 0 both
sm_restrict ak47 2 t
sm_restrict snipers 1
sm_unrestrict grenades t
sm_unrestrict all
```

## Cvars

### General

| Cvar | Default | Description |
| --- | --- | --- |
| `sm_uwr_enabled` | `1` | Enable weapon restrictions. |
| `sm_uwr_allow_restricted_pickup` | `0` | `1` lets players pick up restricted weapons from the ground. Buys are still blocked. |
| `sm_uwr_admin_immunity` | `0` | `1` makes admins with the immunity override ignore restrictions. See [Admin immunity](#admin-immunity). |
| `sm_uwr_notify` | `1` | Print a chat message when a buy or pickup is blocked. |
| `sm_uwr_restricted_sound` | `sound/buttons/weapon_cant_buy.wav` | Sound played to the player when a buy or pickup is blocked. Empty disables it. |
| `sm_uwr_perplayer_enabled` | `0` | Use the limits from `perplayerrestrict.txt`. See [Per-player limits](#per-player-limits). |
| `sm_uwr_perplayer_count_bots` | `1` | Count bots for per-player limits. |
| `sm_uwr_perplayer_count_specs` | `1` | Count spectators and unassigned players for per-player limits. |
| `sm_umbrella_weaponrestrict_version` | `1.0.2` | Plugin version (read only). |

### Per-weapon limits

Every managed weapon gets two cvars, one per team:

```cfg
sm_restrict_<alias>_t  -1
sm_restrict_<alias>_ct -1
```

| Value | Meaning |
| --- | --- |
| `-1` | Unlimited (default). |
| `0` | Blocked. |
| `1` to `64` | Maximum the team can have at the same time. |

The alias is the one the game uses. On CS:S the cvars are:

```text
glock usp p228 deagle elite fiveseven
tmp mac10 mp5navy ump45 p90
m3 xm1014
galil famas ak47 m4a1 sg552 aug m249
scout awp sg550 g3sg1
hegrenade flashbang smokegrenade
kevlar assaultsuit
```

For example `sm_restrict_awp_t`, `sm_restrict_flashbang_ct` or `sm_restrict_assaultsuit_t`. CS:GO adds its own weapons (`ssg08`, `scar20`, `m4a1_silencer`, `usp_silencer`, `cz75a`, `revolver`, `molotov`, `incgrenade`, `decoy`, `taser`, `heavyassaultsuit`...). Run `cvarlist sm_restrict_` in the server console to see the exact list for your game.

## How limits work

- **Buys**: a buy that would go over the limit is cancelled before the weapon is given, so no money is taken.
- **Pickups**: touching a ground weapon over the limit does nothing, unless `sm_uwr_allow_restricted_pickup 1`.
- **Removal**: weapons over the limit are removed when a limit is lowered (command, menu, cvar or per-player change), at every round start, and with `sm_remove_restricted`.
- **Owned weapons**: a player who already has a weapon can pick up or buy the same one again at the limit, since it does not add to the team count.
- **Grenades**: the limit is the total number of grenades of that type the team carries. With `sm_restrict_flashbang_t 3`, two players with 2 flashbangs each go over the limit, and removal trims the second player down to 1.
- **Armor**: `kevlar` is armor without helmet and `assaultsuit` is armor with helmet. When the assault suit is restricted but kevlar is not, removal takes only the helmet. Heavy armor (CS:GO) is reduced to a normal assault suit.
- **Spawn items**: items given to a player that are over the limit (for example the default pistol, or a weapon from another plugin) are removed instead of being dropped on the floor.
- **Notifications**: each blocked weapon is reported once, at most once every 1.5 seconds, so standing on a pile of weapons does not flood the chat.

Never managed: knives, the C4, defuse kits and rescue kits, night vision, healthshots, tablets, and the CS:GO Danger Zone fists and melee weapons. `sm_restrict all 0` leaves them alone, which keeps bomb maps playable during knife rounds.

## Weapon groups

Groups are shortcuts: they set the same limit on every weapon of the group. They do not have their own cvars, and the limit applies to each weapon separately (`sm_restrict snipers 1` allows 1 AWP **and** 1 Scout, not 1 sniper in total).

| Group | CS:S | CS:GO |
| --- | --- | --- |
| `pistols` | glock, usp, p228, deagle, elite, fiveseven | glock, hkp2000, usp_silencer, p250, cz75a, deagle, revolver, elite, fiveseven, tec9 |
| `smgs` | tmp, mac10, mp5navy, ump45, p90 | mac10, mp9, mp7, ump45, p90, bizon |
| `shotguns` | m3, xm1014 | nova, xm1014, mag7, sawedoff |
| `rifles` | galil, famas, ak47, m4a1, sg552, aug, m249 | galilar, famas, ak47, m4a1, m4a1_silencer, sg556, aug, m249, negev |
| `snipers` | scout, awp, sg550, g3sg1 | ssg08, awp, scar20, g3sg1 |
| `grenades` | hegrenade, flashbang, smokegrenade | hegrenade, flashbang, smokegrenade, molotov, incgrenade, decoy, tagrenade |
| `armor` | kevlar, assaultsuit | kevlar, assaultsuit, heavyassaultsuit |

Machine guns (`m249`, `negev`) are in `rifles`. The CS:GO Zeus (`taser`) has no group; restrict it by name. The CS:GO names are the game's own aliases; `cvarlist sm_restrict_` shows the exact ones.

## Per-player limits

Per-player limits change a weapon's limit with the number of players on the server. They are defined in:

```text
addons/sourcemod/configs/umbrella_weapon_restrict/perplayerrestrict.txt
```

Each section is a weapon alias. `default` is the limit below the first threshold, and each number is the player count from which the next limit applies:

```text
"PerPlayer"
{
	"awp"
	{
		"default"	"0"
		"10"		"1"
		"20"		"2"
	}

	"g3sg1"
	{
		"default"	"0"
		"16"		"1"
	}
}
```

With this file, the AWP is blocked with up to 9 players, limited to 1 from 10 players and to 2 from 20 players.

Enable it with:

```cfg
sm_uwr_perplayer_enabled 1
```

Things to know:

- A per-player limit applies to **both teams** and overrides the `sm_restrict_<alias>_t` and `_ct` cvars of that weapon while the mode is enabled. Commands and menu changes to that weapon are replaced by the per-player value.
- Weapons not listed in the file keep their normal cvars.
- The count is updated when players join, leave or change team, and at round start. Over-limit weapons are removed when the limit goes down.
- Disabling the mode or unloading the plugin restores the cvar values.
- The file is read on every map start. Invalid weapon names are logged to the SourceMod error log.
- Use `sm_uwr_perplayer_count_bots` and `sm_uwr_perplayer_count_specs` to choose who is counted.

## Admin immunity

```cfg
sm_uwr_admin_immunity 1
```

Admins with access to the `umbrella_weapon_restrict_immunity` override can buy and pick up anything, are never stripped, and their weapons do not count towards the team limit. By default the override requires the root flag (`z`). To give it to another flag, add it in `addons/sourcemod/configs/admin_overrides.cfg`:

```text
Overrides
{
	"umbrella_weapon_restrict_immunity"	"b"
}
```

## Block sound

`sm_uwr_restricted_sound` takes a path relative to the game's `sound/` folder, with or without the `sound/` prefix:

```cfg
sm_uwr_restricted_sound "sound/buttons/weapon_cant_buy.wav"
sm_uwr_restricted_sound "buttons/weapon_cant_buy.wav"
sm_uwr_restricted_sound ""
```

The file must exist on the server. Custom sounds are added to the downloads table automatically. Absolute paths, backslashes, `:`, `..` and `//` are rejected and logged.

## Translations

All messages are in `addons/sourcemod/translations/umbrella_weapon_restrict.phrases.txt`.

| Code | Language |
| --- | --- |
| `en` | English |
| `es` | Spanish |
| `pt` | Portuguese (Brazil) |
| `chi` | Chinese |
| `ru` | Russian |
| `fr` | French |
| `de` | German |
| `tr` | Turkish |
| `pl` | Polish |

Players whose game language is not in the list see the server language.

## Building from source

Compile with the SourceMod 1.12 compiler; only the includes that ship with SourceMod are needed:

```text
spcomp addons/sourcemod/scripting/umbrella_weapon_restrict.sp -o umbrella_weapon_restrict.smx
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

Released under the GNU General Public License v3.0. See [LICENSE](LICENSE).

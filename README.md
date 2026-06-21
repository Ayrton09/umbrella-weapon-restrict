# Umbrella Weapon Restrict

Umbrella Weapon Restrict is a SourceMod plugin for Counter-Strike: Source and Counter-Strike: Global Offensive. It restricts weapon buys and pickups by team, weapon, weapon group, and optional player-count thresholds.

## Features

- CS:S and CS:GO support.
- Admin menu integration.
- Per-team weapon limits.
- Weapon group restrictions (pistols, smgs, shotguns, rifles, snipers, grenades, armor).
- Optional per-player restrictions based on current player count.
- Configurable block sound with path-traversal protection.
- Chat notifications with anti-spam protection for blocked buys and pickups.
- Fallback to the server language for unsupported client languages.
- Single translation file with 9 supported languages.

## Requirements

- SourceMod 1.12 stable or newer.
- Counter-Strike: Source or Counter-Strike: Global Offensive server.

## Installation

Copy the `addons` folder into your game server root.

Installed files:

```text
addons/sourcemod/plugins/umbrella_weapon_restrict.smx
addons/sourcemod/scripting/umbrella_weapon_restrict.sp
addons/sourcemod/translations/umbrella_weapon_restrict.phrases.txt
addons/sourcemod/configs/umbrella_weapon_restrict/perplayerrestrict.txt
```

The generated plugin config is created by SourceMod at:

```text
cfg/sourcemod/umbrella_weapon_restrict.cfg
```

## Commands

All commands require the `ADMFLAG_CONVARS` admin flag.

```text
sm_restrictmenu
sm_wrmenu
sm_restrict <weapon|group|all> [amount] [t|ct|both]
sm_unrestrict <weapon|group|all> [t|ct|both]
sm_remove_restricted
```

Examples:

```text
sm_restrict awp 0 both
sm_restrict ak47 2 t
sm_restrict snipers 1 both
sm_unrestrict grenades t
sm_unrestrict awp both
```

## Cvars

Core cvars:

```cfg
sm_uwr_enabled 1
sm_uwr_allow_restricted_pickup 0
sm_uwr_admin_immunity 0
sm_uwr_notify 1
sm_uwr_restricted_sound sound/buttons/weapon_cant_buy.wav
sm_uwr_perplayer_enabled 0
sm_uwr_perplayer_count_bots 1
sm_uwr_perplayer_count_specs 1
```

Version cvar:

```cfg
sm_umbrella_weaponrestrict_version 1.0.0
```

Per-weapon cvars are generated automatically:

```cfg
sm_restrict_<weapon>_t -1
sm_restrict_<weapon>_ct -1
```

Examples:

```cfg
sm_restrict_awp_t -1
sm_restrict_awp_ct -1
sm_restrict_flashbang_t -1
sm_restrict_flashbang_ct -1
```

Restriction values:

```text
-1 = unrestricted
 0 = blocked
>0 = maximum amount allowed for that team
```

## How It Works

- **Buy block:** when a restricted weapon would exceed its limit, the buy command is cancelled before the weapon is given, so no money is deducted.
- **Pickup block:** picking up a ground weapon over the limit is denied (unless `sm_uwr_allow_restricted_pickup 1`).
- **Enforcement:** when a limit is lowered (admin command, menu, per-player change, or round start), already-owned weapons over the new limit are removed.

## Sound

`sm_uwr_restricted_sound` accepts a relative sound path with or without the `sound/` prefix.

Examples:

```cfg
sm_uwr_restricted_sound sound/buttons/weapon_cant_buy.wav
sm_uwr_restricted_sound buttons/weapon_cant_buy.wav
sm_uwr_restricted_sound ""
```

An empty value disables the sound. For safety, absolute paths, backslashes, `:`, `..`, and double slashes are rejected.

## Weapon Groups

The following group names can be used in commands and the admin menu:

```text
pistols
smgs
shotguns
rifles
snipers
grenades
armor
```

Group restrictions do not create separate cvars. They apply the selected limit to each managed weapon in that group.

## Per-Player Restrictions

Per-player rules are configured in:

```text
addons/sourcemod/configs/umbrella_weapon_restrict/perplayerrestrict.txt
```

Example:

```text
"PerPlayer"
{
	// Example only. Uncomment and edit to enable per-player limits.
	// "awp"
	// {
	// 	"default"	"0"
	// 	"10"		"1"
	// 	"20"		"2"
	// }
}
```

If the example is uncommented, `awp` is blocked until 9 counted players, limited to 1 from 10 players, and limited to 2 from 20 players.

Enable per-player mode with:

```cfg
sm_uwr_perplayer_enabled 1
```

Counting behavior:

```cfg
sm_uwr_perplayer_count_bots 1
sm_uwr_perplayer_count_specs 1
```

## Translations

The plugin uses one translation file:

```text
addons/sourcemod/translations/umbrella_weapon_restrict.phrases.txt
```

Supported languages:

```text
en  English
es  Spanish
pt  Portuguese (Brazil)
chi Chinese
ru  Russian
fr  French
de  German
tr  Turkish
pl  Polish
```

If the client language is not supported, the plugin falls back to the server language.

## Admin Immunity

Admin immunity is controlled by:

```cfg
sm_uwr_admin_immunity 1
```

The plugin checks the command access override:

```text
umbrella_weapon_restrict_immunity
```

By default, the fallback flag is root.

## License

Released under the GNU General Public License v3.0. See [LICENSE](LICENSE).

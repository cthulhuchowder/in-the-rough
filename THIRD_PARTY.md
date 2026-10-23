# Third-party components

Everything not listed here (code, models, textures, shaders, procedural sounds and ambience) is
original to this project and covered by its MIT [LICENSE](LICENSE).

## Engine and libraries

| Component | Where | Version | Licence |
|---|---|---|---|
| Godot Engine | not bundled; you build with it, and exported games embed it | 4.7.2 | MIT (https://godotengine.org/license) |
| GodotSteam (GDExtension) | `game/addons/godotsteam/` (`libgodotsteam.*`) | 4.23.1 | MIT, see `game/addons/godotsteam/license.md` |
| Steamworks SDK redistributables | `game/addons/godotsteam/win64/steam_api64.dll`, `game/addons/godotsteam/osx/libsteam_api.dylib` | SDK 1.65 | **Proprietary (Valve).** Redistribution is governed by the Steamworks SDK Access Agreement, not an open licence. ⚠ Flagged: check before publishing |

## Fonts

None bundled. The UI uses Godot's built-in default font, which ships inside the engine under the
engine's licences.

## Sound effects: Kenney (CC0)

The files below are **CC0 1.0** (public domain dedication,
https://creativecommons.org/publicdomain/zero/1.0/): free to use, no attribution required.
Credited anyway: **Kenney** (www.kenney.nl). Each pack's licence file is in `game/audio/licenses/`.

### Files (game/audio/)

| File | Pack | Kenney file name | Licence |
|---|---|---|---|
| `club_driver.ogg` | Kenney — Impact Sounds | `impactPlate_heavy_001.ogg` | CC0 |
| `club_iron.ogg` | Kenney — Impact Sounds | `impactMetal_medium_000.ogg` | CC0 |
| `club_wedge.ogg` | Kenney — Impact Sounds | `impactMetal_light_001.ogg` | CC0 |
| `putter_tock.ogg` | Kenney — Impact Sounds | `impactWood_light_000.ogg` | CC0 |
| `land_fairway.ogg` | Kenney — Impact Sounds | `impactSoft_medium_000.ogg` | CC0 |
| `land_rough.ogg` | Kenney — Impact Sounds | `impactSoft_heavy_000.ogg` | CC0 |
| `land_sand.ogg` | Kenney — Impact Sounds | `footstep_snow_000.ogg` | CC0 |
| `hit_tree.ogg` | Kenney — Impact Sounds | `impactWood_heavy_000.ogg` | CC0 |
| `hit_stone.ogg` | Kenney — Impact Sounds | `impactGeneric_light_000.ogg` | CC0 |
| `cup_rattle.ogg` | Kenney — Impact Sounds | `impactTin_medium_000.ogg` | CC0 |
| `cup_drop.ogg` | Kenney — Impact Sounds | `impactPlate_light_000.ogg` | CC0 |
| `ui_hover.ogg` | Kenney — UI Audio | `rollover2.ogg` | CC0 |
| `ui_click.ogg` | Kenney — UI Audio | `click1.ogg` | CC0 |
| `ui_back.ogg` | Kenney — Interface Sounds | `back_001.ogg` | CC0 |
| `shop_buy.ogg` | Kenney — Interface Sounds | `confirmation_001.ogg` | CC0 |
| `shop_equip.ogg` | Kenney — Interface Sounds | `toggle_001.ogg` | CC0 |
| `coin_clink.ogg` | Kenney — Casino Audio | `chips-collide-1.ogg` | CC0 |
| `chat_blip.ogg` | Kenney — Interface Sounds | `pluck_001.ogg` | CC0 |
| `scorecard_pop.ogg` | Kenney — Interface Sounds | `open_001.ogg` | CC0 |

Licence files: `game/audio/licenses/kenney-impact-sounds.txt`, `kenney-interface-sounds.txt`, `kenney-ui-audio.txt`, `kenney-casino-audio.txt`.


## Original sounds (not third-party)

- **Biome ambience** (`game/audio/ambience/`): every file there is synthesised by this project
  (`game/art/soundscape_render.gd`, from filtered noise and simple oscillators). Original work
  under the project's licence.
- **Comedy and crowd sounds** (crow caw, applause, goose honk, squeaks, club swish, water splash, shoe
  slap): generated at run time in code by `game/scripts/placeholder_sounds.gd`. No files, no
  third-party content.

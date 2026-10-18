# Ability Draft (Civilization VI)

A multiplayer lobby draft for **Civilization VI: Gathering Storm**. Instead of picking a ready-made leader with
their civilization, every player builds their own combination: a leader, a civilization and four unique items
are picked separately, each from its own menu.

Version 0.1.1 · author: enjoymyragga ([github.com/maksdk87](https://github.com/maksdk87)) · license: MIT (see below)

## What it does

- In the multiplayer lobby (LAN or internet) each player row has six menus: **leader**, **civilization**,
  **unique district**, **unique building**, **unique improvement**, **unique unit**.
- The leader brings only the leader ability, the civilization only the civilization ability; the picked unique
  items become the player's own (the game itself handles costs, placement rules, the replaced base item,
  techs and civics, repairs and the Civilopedia).
- Leaders are unique per game; civilizations and items may repeat between players.
- Any menu can be **Random**: it is rolled when the player readies up and stays secret until the game starts.
  The host rolls the AI slots too (also AI slots added after the host readied up).
- An ability that names a district or building works with every district or building of that kind — a unique
  one or the one it replaces (Gaul's campus bonus works with a Seowon, Lincoln's industrial zone with a Hansa,
  and so on).
- Korea and the Maya: the mine/farm bonus next to the Seowon/Observatory belongs to the civilization ability,
  +1 for each adjacent district of the kind.
- Game option **Stock binding** (off by default): unique items named in the ability of the leader or the
  civilization stay with them in the draft (Kristina: Queen's Bibliotheque, Korea: Seowon). If both name an item
  of the same type, the leader's item stays.
- With **Better Balanced Starts (BBS)** the start positions follow the draft: sea-related picks pull the start to
  the coast, the Open-Air Museum works like Sweden's "King of the North", Menelik keeps the hills preference and
  Lady Six Sky keeps "away from the sea".
- Lobby texts in all 12 languages of the game (English and Russian checked, the others are not reviewed by
  native speakers yet).

## Requirements and limits

- Gathering Storm rules only. With other rules the draft menus are hidden and the game starts as usual.
- Multiplayer (LAN / internet) only. Single player and hot seat are not supported.
- Up to 12 players (the multiplayer limit of the game).
- Not compatible with **Multiplayer Helper** (both replace the staging room).
- All players need the same version of the mod.

## Installation

Subscribe in the Steam Workshop (link will follow), or copy the folder `PoC_DraftTransport` from this repository
into

```
Documents\My Games\Sid Meier's Civilization VI\Mods
```

Restart the game completely after installing or updating the mod. The folder name and the mod id are kept from the
prototype ("PoC Draft Transport"), so saves and subscriptions stay valid.

## How it works

1. The lobby (`UI/StagingRoom.lua`, `Lua/PlayerSetupLogic.lua` — modified copies of the game's own files) adds the
   five menus as player parameters; the leader menu is the game's own.
2. When the launch countdown starts, the host writes every slot's pick numbers into the game settings as bits:
   `POCD_S<slot>_<L|C|D|B|I|U>_B<bit> = 1`.
3. For every such bit the `.modinfo` has a `ConfigurationValueMatches` criterion and a tiny `UpdateDatabase`
   action (`Data/S/*.sql`, 476 files for 14 slots) that inserts one row into `POCD_SlotBits`.
4. `Data/POCD_Apply.sql` turns the bits back into picks and swaps the traits; `Data/POCD_Abilities.sql` makes the
   abilities work with the drafted items; `Data/POCD_StartBias.sql` and `Maps/Utility/MapEnums.lua` pass the draft
   to BBS.

Nothing is changed in a game without the draft (all changes depend on the drafted slots).

## Repository layout

| Path | What |
|---|---|
| `PoC_DraftTransport/` | the mod, exactly as it is uploaded to the Workshop |
| `tools/build_mod.py` | generator of the per-slot files (see below) |

## Generator (`tools/build_mod.py`)

Regenerates only the generated parts of the mod: `Data/S/*.sql`, the `C_POCD_S*` criteria, `A_POCD_S*` actions and
the `Data/S/` file list in the `.modinfo`, the pick index (`POCD_Index`) in `Data/POCD_Schema.sql` and
`Config/POCD_Config.sql`, the bits per menu and the number of slots. Everything else in the `.modinfo` is edited by
hand. Needed when the item pool, the number of slots or the load criteria change.

```
python tools/build_mod.py PoC_DraftTransport --check          # report what would change
python tools/build_mod.py PoC_DraftTransport                  # keep the index, regenerate the rest
python tools/build_mod.py PoC_DraftTransport --pool-db DebugConfiguration.sqlite   # rebuild the index from a game database
```

## Bug reports

Please use **Discussions → Ability Draft Bugs**. Helpful to attach:

- the logs from `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\Logs`: `Lua.log`, `Database.log`,
  `Modding.log` (they are overwritten at every game start, so copy them right after the problem);
- the list of enabled mods, the map type and size, the number of players;
- the picks of the affected player and what you expected to happen.

## Credits

Thanks to:

- the Better Balanced Game team ([github.com/CivilizationVIBetterBalancedGame](https://github.com/CivilizationVIBetterBalancedGame))
  and the BBG Expanded authors;
- 57F@n and D. / Jack The Narrator — Better Balanced Starts ([github.com/57fan/Civ6-BBS-2](https://github.com/57fan/Civ6-BBS-2));
- BaNiPouZ and Talasta — Better Balanced Map;
- Cisco and D. / Jack The Narrator — Multiplayer Helper;
- Lee "LeeS" Shipp — Civilization 6 Modding Guide;
- the editors of the Civilization Wiki (Fandom);
- Firaxis Games, whose own lobby scripts this lobby is built on.

Made with the help of Claude Opus 5.5 by Anthropic (model `claude-opus-5-5`), effort: Extra.

## License

The mod's own code is under the MIT license (see `LICENSE`).
`UI/StagingRoom.lua`, `UI/StagingRoom.xml`, `Lua/PlayerSetupLogic.lua` and `Maps/Utility/MapEnums.lua` are modified
copies of Civilization VI files; those parts remain the property of Firaxis Games / 2K and are not covered by the
MIT license. Civilization, Firaxis and 2K are trademarks of their respective owners.

---

## Кратко на русском

Драфт для сетевого лобби Civilization VI: Gathering Storm. Каждый игрок отдельно выбирает лидера, цивилизацию,
уникальные район, здание, улучшение и юнит; лидер даёт только свою способность, цивилизация — только свою. Любое
меню может быть тайным «Случайным». Настройка «Стоковая привязка» закрепляет объекты, названные в способностях.
С BBS стартовые позиции учитывают драфт. Только GS, только сетевая игра, до 12 игроков, несовместим с Multiplayer
Helper. Установка — папку `PoC_DraftTransport` в `Документы\My Games\Sid Meier's Civilization VI\Mods`, затем
полный перезапуск игры. Ошибки — в Discussions, тема «Ability Draft Bugs», с файлами `Lua.log`, `Database.log`,
`Modding.log`.

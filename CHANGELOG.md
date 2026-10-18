# Changelog

All notable changes of **Ability Draft** (Civilization VI: Gathering Storm). Versions are the `<Version>` of the
`.modinfo`; the Workshop item is [3822159719](https://steamcommunity.com/sharedfiles/filedetails/?id=3822159719).
Bug reports: [Ability Draft Bugs](https://github.com/maksdk87/Ability-Draft-Civilization-VI/discussions/1).

## 0.1.2 — 2026-10-18 (test version)

### Fixed
- **Doubled and tripled ability bonuses for districts and buildings.** An ability bonus that names a district or
  building (adjacency, great work slots, culture bomb, free units…) was copied by the mod for every other district or
  building of the same kind. The game already applies such a bonus to the whole kind, so the copies stacked:
  Brazil got +9 instead of +3 for three rainforests next to a campus, the Suguba got a doubled bonus, a Sukiennice got
  4 writing slots from Sundiata instead of 2. The copies are removed; requirements of abilities still accept every
  district or building of the kind (Lincoln with a Hansa, Sweden with an Electronics Factory…).
- **Players without the draft menus had no draft.** A player who got the mod by automatic download while joining a
  lobby sees the game's own lobby (see *Known limitations*); his menus stayed "Random" and nothing rolled them, so he
  played his leader's civilization without drafted items and without its own unique items; stock binding did not
  apply. Now the host rolls such menus secretly when the launch countdown starts and right before launch
  (stock binding is honoured), and the civilization of the player's leader counts as the drafted one.
- **Better Balanced Starts could fail** with a civilization nobody picked in the civilization menu (for example
  Mongolia: horses at tier 2): the start bias fixes for Mongolia, Scythia, the Maya and Ethiopia now apply to every
  player's civilization, also when it comes from the leader.

### Added
- Every computer with the draft lobby marks its player in the lobby settings; when a player without the draft menus
  readies up, the host writes a note to the lobby chat (English + Russian): leave the lobby and join again, no game
  restart needed.
- `Lua.log` of the host: stock binding on/off, menus rolled by the host for each slot, and whether the slot had the
  draft lobby.

### Changed
- Description: "restart the game after subscribing" replaced with the rejoin note; changelog link.

## 0.1.1 — 2026-10-18 (first public version)

- Lobby draft for **Gathering Storm** network games (LAN / internet): six menus in every player row — leader,
  civilization, unique district, building, improvement and unit.
- The leader brings only the leader ability, the civilization only the civilization ability; the drafted unique
  items become the player's own (costs, placement rules, replaced base item, techs, civics, repairs and the
  Civilopedia work as in the base game).
- Leaders are unique per game; civilizations and items may repeat.
- Any menu can be **Random**: rolled when the player readies up, kept secret until the game starts; the host rolls
  the AI slots (also AI slots added after the host readied up).
- Abilities that need a district or building of a kind accept every member of the kind.
- Korea and the Maya: the mine/farm bonus next to the Seowon/Observatory belongs to the civilization ability, +1 for
  each adjacent district of the kind.
- Game option **Stock binding** (off by default): unique items named in the ability of the leader or the
  civilization stay with them (leader first).
- **Better Balanced Starts:** start biases follow the draft (sea-related picks pull the start to the coast, the
  Open-Air Museum works like Sweden's "King of the North", Menelik keeps the hills, Lady Six Sky keeps "away from
  the sea").
- Limits: Gathering Storm rules only (other rules: menus hidden, normal game), no single player / hot seat /
  cloud games, up to 12 players, not compatible with Multiplayer Helper.
- Lobby texts in all 12 languages of the game.

## Prototype "PoC Draft Transport" (v1 – v27.5, 2026-10-14 … 2026-10-18)

Not published. Main steps:
- v10–v12: swapping the items in Lua during the game — rejected (base items visible again in the production list,
  costs and placement rules of unique items not applied, a pillaged unique district could not be repaired).
- v13: the picks reach the game as database changes at game load (conditional `UpdateDatabase` actions on
  game settings) — the approach used since.
- v14–v16: the drafted leader at the head of the civilization chosen in the lobby.
- v18: up to 14 slots — every pick number written as bits into the game settings.
- v19–v22: network lobby with six menus, compact rows, secret "Random", first test with a live player.
- v23–v25: stock binding, abilities working with every district of a kind, Korea/Maya bonus counted per district.
- v26–v27.5: start biases from the draft for Better Balanced Starts, name "Ability Draft".

---

## Кратко на русском

- **0.1.2 (тестовая):** убраны двойные и тройные бонусы способностей к районам и зданиям (кампус Бразилии +9,
  4 ячейки письменности в суконных рядах у Сундиаты); игрокам, которые скачали мод при входе в лобби и не видят
  меню драфта, хост тайно разыгрывает 4 объекта (со «Стоковой привязкой»), их цивилизация — цивилизация лидера,
  исправления стартов для BBS действуют на всех; хост пишет таким игрокам в чат «перезайдите в лобби»; больше данных
  в Lua.log.
- **0.1.1:** первая публичная версия.

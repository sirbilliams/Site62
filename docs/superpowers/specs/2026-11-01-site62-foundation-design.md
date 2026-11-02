# Site 62: Foundation Design (Milestone 1)

Date: 2026-11-01. Status: approved in chat section by section; awaiting spec review.

## Intent
- **What Bill said:**
  - Not a toy. A real foundation for a wave-based co-op zombie shooter in the genre of Call of Duty Zombies.
  - PC first, AYN Thor later. Godot 4. CC0 art to start.
  - Milestone 1 includes the core loop, online co-op for 1–4 players, power-ups and machines, and data-driven content.
  - Setting: a Cold War lab outbreak.
  - The perk machines are called **Ethereal-Suds**, with an early-70s soda feel.
- **Constraint:** it is an original game in the genre. It has its own setting, lore, names, numbers and art. Nothing is taken from Call of Duty: no names, assets, maps or exact tuning values.
- **Success:** 1–4 friends can play a full match on Site 62 over the LAN, and it feels responsive. New guns and enemies can be added as data files without code.

## Decisions
- **Approach A:** a new standalone project. It reuses proven patterns from Neutron Arena (server-authoritative ENet, sender checks, the headless multi-client test harness, Android export and signing later) but shares no code with it.
- **Rejected:**
  - Extracting a shared library from Neutron Arena: it is built for 5v5 PvP, and the extraction would risk a working game.
  - Starting from a single-player FPS template: every state-changing system would need rewriting for co-op. Template pieces that don't change game state (camera feel, weapon sway, interact prompts) may still be borrowed if they are MIT or CC0 licensed.
- **Engine and tools:** Godot 4.7 (flatpak) and GDScript. The repo is `~/Projects/site62`, private on GitHub until Bill decides.
- Working title: **Site 62**.

## 1. Architecture
The host is authoritative. Clients send **inputs** and receive **state** (about 20 Hz) plus **events**. Solo play is a host with one player: there is one code path.

| Unit | Folder | Job |
|---|---|---|
| Net | `net/` | Host and join, LAN browser, player registry, input and state channels, sender validation |
| Player | `player/` | First-person movement with client prediction, camera, health and down state, inventory (2 guns, knife, grenades) |
| Weapons | `weapons/` | Data-driven firing: hitscan, spread, recoil, ADS, reload, ammo; host-side lag-compensated hit checks |
| Enemies | `enemies/` | Zombie AI (navigation, barricade breaking, attacks) from `EnemyData`; runs on the host only |
| Director | `director/` | Rounds and spawning: count, health and speed per round, spawn points by open zone, break timer |
| Economy | `economy/` | Points and every buy interaction, validated by the host |
| Map kit | `mapkit/` | Drop-in scenes for spawns, barricades, doors, wall-buys, machines, power switch, player starts |
| UI | `ui/` | HUD, menus, host and join, scoreboard, game-over summary |
| Content | `content/` | `.tres` data files and the CC0 art |

Each unit talks to the others through signals or small public methods. No unit reaches into another's internals.

## 2. Game systems
### Round loop
- The Director spawns each wave from the spawn zones of open areas.
- Zombie count and health scale up each round. Speed moves from shamble to jog to sprint as rounds go up.
- When the last zombie dies there is a short break, then the next round starts.
- Zombies enter through **barricades** (boarded windows). Players rebuild the boards and earn points for it.

### Economy
- **Earning:** points per hit and per kill, a melee or headshot bonus, and points for repairing boards.
- **Spending:**
  - **Wall guns:** buy the gun, or buy ammo for a gun you already own.
  - **Bulkhead doors:** open new zones.
  - **Requisition Crate:** a random weapon for a fixed price. It moves to another spawn spot after several uses.
  - **Ethereal-Suds:** groovy early-70s soda machines. Each player can hold up to 4 Suds. Final soda names are set in the content files and approved by Bill. The four effects:
    - more health;
    - faster reload;
    - faster revive, plus self-revive in solo;
    - faster fire rate.
  - **Isotope Refit station:** upgrades a weapon into a stronger, renamed version with more ammo.
  - **Power switch:** Suds machines and the Refit station work only after it is thrown.

### Power-ups
Kills drop power-ups, with a cap per round. Each lasts 30 s where it has a duration.

| Name | Effect |
|---|---|
| Bonus Ration | Double points |
| Resupply | Full ammo for everyone |
| Purge | Kills all zombies on the map, gives flat points |
| Overload | One-hit kills |
| Fortify | Rebuilds every barricade |
| Requisition Voucher | Next crate is free |

### Down and revive
- At 0 HP the player goes **down**: pistol only, with a bleed-out timer running.
- A teammate revives them by holding interact.
- If the timer runs out, the player bleeds out. They spectate until the next round and respawn with a pistol and no Suds.
- When every player is down, the game ends. A summary screen shows rounds, kills, downs, revives and points.

## 3. Networking
- **Transport:** ENet, 1–4 players, LAN browser first. Internet play works via port forwarding; a dedicated server on Proxmox comes later.
- **Movement:**
  - Clients send inputs at about 60 Hz.
  - The local player is predicted and reconciled against host corrections.
  - Remote players and zombies are interpolated about 100 ms in the past.
- **Shooting:**
  - The client shows the shot (muzzle flash, tracer, hit marker) immediately.
  - The host rewinds hitboxes to the shooter's fire time, using a 250 ms history buffer, then decides damage, points and kills.
  - The host rejects impossible shots: no ammo, firing faster than the fire rate allows, or line of sight blocked.
- **Zombies:** the host runs all AI. Clients get compact snapshots (position, yaw, animation state) for up to about 40 active zombies, plus events: spawn, death, attack, barricade hit.
- **Economy and objects:** every buy, door, Suds, crate, Refit and power-up pickup is a request. The host checks points, distance and state, then broadcasts the result.
- **Late join:** the joining player receives a full snapshot (round, doors, power, all players' points and kits) and spawns at the next round.

## 4. Content, map kit, testing
### Data (Godot Resources, editable in the inspector)
- **WeaponData:**
  - damage and falloff;
  - fire rate and fire mode;
  - magazine and reserve ammo;
  - reload time;
  - spread and recoil pattern;
  - ADS zoom;
  - cost;
  - model and sounds;
  - its Isotope Refit upgraded version (also a WeaponData).
- **EnemyData:** health curve, speed per round band, attack damage and rate, barricade behaviour. Milestone 1 has one basic zombie. New types are new data files plus scenes, not new systems.
- **SudsData**, **PowerupData**, and **RoundCurve** (count and health per round, spawn rate, max alive, break length).
- Adding a gun means adding a `.tres` file and a model, with no code change.

### Map kit and first map
- Map kit scenes:
  - SpawnZone (tied to the zone it belongs to);
  - Barricade;
  - BulkheadDoor (cost, unlocks zones);
  - WallBuy;
  - CrateSpot;
  - SudsMachine;
  - RefitStation;
  - PowerSwitch;
  - PlayerStart.
- Navigation is baked per map. Doors toggle navigation links when they open.
- **First map, "Site 62":** about 5 zones (entrance lab, cafeteria, offices, reactor wing, and the Refit chamber behind power). It is greyboxed first, then dressed with CC0 art.

### Testing
Headless tests run the host and clients in one process with a `timeout`. They cover:
- economy: buy, door, crate, Suds, Refit, power;
- round flow and spawning;
- down, revive, bleed-out and game over;
- lag-compensated hit validation under simulated latency and packet loss;
- late join;
- that every content file loads and validates.

Screenshot tools capture every HUD and machine screen, and Claude reviews them before each release.

## Milestone 1: done when
1. 1–4 players play Site 62 over the LAN from round 1 to game over, and it feels responsive.
2. Wall-buys, doors, the crate, 4 Ethereal-Suds, Isotope Refit, the power switch, 6 power-ups and down/revive all work in co-op.
3. At least 6 guns and 1 zombie type exist, all defined as data.
4. All tests pass, and Linux and Windows PC builds exist.
5. The GitHub repo is private.

## Not in Milestone 1
The Thor/Android port, more zombie types, easter-egg quests, wonder weapons, a dedicated Proxmox server, progression and unlocks.

## Risks
- **Game feel on a first build:** tune early and playtest each phase on PC.
- **Lag compensation bugs:** test with simulated latency from day one.
- **CC0 art consistency:** pick one or two packs with matching styles (Quaternius-style low-poly) and record each asset's licence in `content/CREDITS.md`.

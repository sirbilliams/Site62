# Site 62 Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable 1–4 player LAN co-op wave-survival shooter on the Site 62 map, with all Milestone 1 systems built from data files.

**Architecture:** Godot 4.7 project. The host is authoritative over ENet. Gameplay rules live in pure, node-free classes that unit tests can exercise directly: motor, weapon state, director math, wallet, rules. Thin node wrappers handle networking and presentation. Multi-process tests run a real host and real clients.

**Tech Stack:** Godot 4.7 (flatpak `org.godotengine.Godot`), GDScript, ENet high-level multiplayer, NavigationServer3D, CC0 art (Quaternius / Kenney / Poly Haven).

**Spec:** `docs/superpowers/specs/2026-11-01-site62-foundation-design.md`

## Global Constraints
- Original game. No Call of Duty names, assets, maps or tuning. Use the names from the spec: Ethereal-Suds, Requisition Crate, Isotope Refit, Bonus Ration, Resupply, Purge, Overload, Fortify, Requisition Voucher.
- The host is authoritative. A client never changes shared game state itself; it sends a request and the host broadcasts the result. Every RPC that runs on the host checks `multiplayer.get_remote_sender_id()`.
- Players: 1–4. Solo is a host with one player.
- Network rates:
  - Input is sent at 60 Hz.
  - State snapshots at 20 Hz.
  - Interpolation delay is 100 ms.
  - The lag-compensation history is 250 ms.
  - At most 40 zombies are alive at once.
- Gameplay values live only in `content/*.tres` or `content/balance.tres`. They are never hard-coded in systems.
- Art: CC0 only. Every asset is listed in `content/CREDITS.md` with its source URL and licence.
- Every test command uses `timeout`. The unit runner is `tests/run_unit.sh`. Multi-process tests are `tests/run_<name>_net.sh`, and each one takes `PORT` and `BP` (LAN beacon port) environment variables.
- The repo is private on GitHub. Commit after every task.

### Balance values (`content/balance.tres`, Task 2), pinned for the tests
| Key | Value |
|---|---|
| start_points | 500 |
| pts_hit / pts_kill / pts_headshot_bonus / pts_melee_kill | 10 / 60 / 40 / 120 |
| pts_board / board_cap_per_round | 10 / 400 |
| player_hp / downed_bleedout_s / revive_hold_s | 100 / 30 / 4.0 |
| max_suds | 4 |
| powerup_drop_chance / powerup_max_per_round / powerup_duration_s | 0.03 / 4 / 30 |
| crate_cost / crate_moves_after_uses | 950 / 6 |
| refit_cost | 5000 |
| fire_rate_tolerance | 0.10 |

### Round curve (`content/round_curve.tres`)
- `count(r, p) = int((5 + 3*r) * (1.0 + 0.5*(p-1)))`.
- `health(r) = 120 + 80*(r-1)` for r ≤ 10. From r = 11 on, `health(r) = health(r-1) * 1.08`, rounded down.
- `speed_band(r)`: 0 (shamble) for r ≤ 3, 1 (jog) for 4–7, 2 (sprint) for r ≥ 8.
- `break_s` = 10. Spawn interval = `max(0.4, 2.0 - 0.1*r)` s.

## Review Focus
1. **A player disconnects while down, carrying the Overload timer, or mid-buy:** the host must remove them cleanly. The round and game-over checks count only connected players. Test in Task 11.
2. **Two players buy the same door or crate in the same tick:** exactly one payment happens and the other player keeps their points. Test in Task 8.
3. **A client sends inputs or fire events for another player's id, or for a dead or downed player:** the host ignores them. Test in Task 3 / Task 5.
4. **A bad or missing `.tres` value** (negative cost, an upgrade pointing at itself, an empty spread array): the content validator reports the file and field at startup, and the game does not crash mid-match. Test in Task 2.
5. **The host rewinds hitboxes for a shot whose timestamp is older than 250 ms or in the future:** clamp the timestamp to the history window and never hit a zombie spawned after the shot time. Test in Task 5.

---

### Task 1: Project scaffold and test harness
**Files:**
- Create: `project.godot`, `.gitignore`, `README.md`, `scenes/main.tscn`, `scripts/main.gd`
- Create: `tests/run_unit.sh`, `tests/unit_runner.gd`, `tests/unit/test_smoke.gd`, `tests/lib/test_case.gd`

**Interfaces:**
- Produces:
  - `TestCase` (class_name). Test files extend it and define `func test_*()`.
  - Assertion helpers: `assert_eq(a, b, msg := "")`, `assert_true(c, msg := "")`, `assert_near(a: float, b: float, eps := 1e-4, msg := "")`.
  - The runner prints `UNIT PASS n` or `UNIT FAIL <file>::<test>: <msg>` and exits with code 0 or 1.
  - `tests/run_unit.sh [filter]` runs: `timeout 300 flatpak run org.godotengine.Godot --headless --path . -s tests/unit_runner.gd -- <filter>`.

- [ ] Step 1: Write `tests/unit/test_smoke.gd`, containing `test_true()` with `assert_eq(1 + 1, 2)` and `test_fail_reports()`, which only checks that `TestCase` records failures.
- [ ] Step 2: Run `tests/run_unit.sh`. Expected: it fails because the runner doesn't exist yet.
- [ ] Step 3: Implement `unit_runner.gd` (`SceneTree` script: load every `tests/unit/test_*.gd`, call its `test_*` methods, collect failures) and `test_case.gd`. Set `project.godot` to Forward+ renderer, 1920×1080 window with stretch mode `canvas_items`, and main scene `scenes/main.tscn`.
- [ ] Step 4: Run `tests/run_unit.sh`. Expected: `UNIT PASS 2`.
- [ ] Step 5: Commit with "scaffold: project, unit test runner".

### Task 2: Content data and validator
**Files:**
- Create: `content/types/weapon_data.gd`, `enemy_data.gd`, `suds_data.gd`, `powerup_data.gd`, `round_curve.gd`, `balance.gd`
- Create: `content/content_db.gd` (autoload `Content`)
- Create: `content/balance.tres`, `content/round_curve.tres`, `content/weapons/*.tres` (6 base guns plus 6 refit versions), `content/enemies/shambler.tres`, `content/suds/*.tres` (4), `content/powerups/*.tres` (6)
- Test: `tests/unit/test_content.gd`

**Interfaces:**
- Produces:
  - **`WeaponData`** (Resource) with these fields:
    - `id: StringName`, `display_name: String`;
    - `damage: float`, `falloff_start: float`, `falloff_end: float`, `falloff_min_mult: float`;
    - `fire_rate_rpm: float`, `mode: int` (0 semi, 1 auto, 2 burst);
    - `mag: int`, `reserve: int`, `reload_s: float`;
    - `spread_hip_deg: float`, `spread_ads_deg: float`, `recoil: PackedVector2Array`;
    - `ads_fov: float`, `cost: int`, `ammo_cost: int`;
    - `scene: PackedScene`, `refit: WeaponData`, `is_wall_buy: bool`.
  - **`EnemyData`**: `id`, `speed_by_band: PackedFloat32Array` (3 values), `attack_damage: float`, `attack_interval_s: float`, `board_tear_s: float`, `scene: PackedScene`.
  - **`SudsData`**: `id`, `display_name`, `cost: int`, `effect: StringName` (`&"max_hp"`, `&"reload_mult"`, `&"revive"`, `&"fire_rate_mult"`), `value: float`, `color: Color`, `jingle: AudioStream`.
  - **`PowerupData`**: `id`, `display_name`, `kind: StringName` (`&"double_points"`, `&"max_ammo"`, `&"purge"`, `&"overload"`, `&"fortify"`, `&"voucher"`), `duration_s: float`.
  - **`RoundCurve`**:
    - `count(r: int, players: int) -> int`
    - `health(r: int) -> int`
    - `speed_band(r: int) -> int`
    - `spawn_interval(r: int) -> float`
    - `break_s: float`
  - **`Balance`**: the fields from the Global Constraints balance table.
  - **`Content`** (autoload):
    - `weapons: Dictionary` (StringName → WeaponData), `enemies`, `suds`, `powerups`, `curve: RoundCurve`, `balance: Balance`;
    - `validate() -> PackedStringArray` (empty means OK);
    - `weapon(id: StringName) -> WeaponData`.

- [ ] Step 1: Write the tests:
  - `test_round_curve_values`:
    - `count(1,1)==8`, `count(1,4)==20`, `count(10,2)==52`;
    - `health(1)==120`, `health(10)==840`, `health(11)==907`;
    - `speed_band(3)==0`, `speed_band(4)==1`, `speed_band(8)==2`;
    - `assert_near(spawn_interval(20), 0.4)`.
  - `test_all_content_valid`: `Content.validate().is_empty()`, `weapons.size()==12`, `suds.size()==4`, `powerups.size()==6`.
  - `test_validator_catches_bad_data`: a WeaponData with `cost=-1` and `refit=self` gives errors mentioning `"cost"` and `"refit"`.
  - `test_validator_empty_recoil`: an empty `recoil` array is reported.
- [ ] Step 2: Run `tests/run_unit.sh content`. Expected: FAIL.
- [ ] Step 3: Implement the types, `Content` and the validator. Validator rules: every cost ≥ 0, `refit != self`, refit weapons have `refit == null`, `mag > 0`, `recoil` not empty, `speed_by_band.size() == 3`.
- [ ] Step 4: Author the `.tres` files. Six guns: M1911-style sidearm "Sentinel .45", SMG "Hornet", rifle "Garand-K", shotgun "Thresher", LMG "Bulwark-60", and the crate-only "Ray-Lancer" prototype. Each gets a refit version with ×2 damage, ×1.5 reserve and an `"Isotope"` name prefix. Four Suds, with placeholder soda names for Bill to rename:
  - **Groovy Grape Bulwark:** `max_hp`, value 220, cost 2500.
  - **Snapback Fizz:** `reload_mult`, value 0.5, cost 3000.
  - **Second-Wind Root Beer:** `revive`, value 0.5 (revive time multiplier, plus solo self-revive), cost 1500.
  - **Overclock Orange:** `fire_rate_mult`, value 1.33, cost 2000.
- [ ] Step 5: Run the content tests. Expected: PASS. Commit with "content: data types, validator, M1 content".

### Task 3: Net session, players and sender checks
**Files:**
- Create: `net/net_session.gd` (autoload `Net`), `net/lan_beacon.gd`, `net/player_registry.gd`
- Test: `tests/net/net_basic.gd`, `tests/run_basic_net.sh`

**Interfaces:**
- Produces:
  - **`Net`**:
    - `host(port: int) -> Error`, `join(ip: String, port: int) -> Error`, `leave()`;
    - `is_host() -> bool`, `local_id() -> int`;
    - signals `player_joined(id: int)`, `player_left(id: int)`, `session_ready()`;
    - `players: PlayerRegistry`.
  - **`PlayerRegistry`**:
    - `ids() -> PackedInt32Array`, `has(id) -> bool`, `info(id) -> Dictionary` (`name`, `slot` 0–3);
    - at most 4 players; a fifth join is refused with reason `"full"`.
  - **`Net.sender_is(id: int) -> bool`**: true when the RPC sender is `id`, or when the call is local on the host.
  - **`LanBeacon`**: the host broadcasts on `BP` once a second; `found(ip, port, name, players)`.
- [ ] Step 1: Write `net_basic.gd`, run as `--test=basic --role=host|client`:
  - the host plus 3 clients connect and all four see `ids().size()==4`;
  - a fifth client gets `"full"`;
  - client 2 calls `Net.rpc_id(1, "debug_claim", 3)`, which the host rejects via `sender_is`;
  - a client leaves and everyone sees `player_left`.
  - Output: `BASIC NET PASS`.
- [ ] Step 2: Run `PORT=26100 BP=7800 tests/run_basic_net.sh`. Expected: FAIL.
- [ ] Step 3: Implement it, porting the pattern from Neutron Arena `scripts/main.gd`, `lan_beacon.gd` and `world.gd` (sender checks).
- [ ] Step 4: Run it. Expected: `BASIC NET PASS`. Commit with "net: session, registry, LAN beacon".

### Task 4: Player motor, prediction and reconciliation
**Files:**
- Create: `player/motor.gd` (pure), `player/player.gd` + `player/player.tscn`, `player/input_frame.gd`
- Test: `tests/unit/test_motor.gd`, `tests/net/net_move.gd`, `tests/run_move_net.sh`

**Interfaces:**
- Produces:
  - **`InputFrame`**: `seq: int`, `move: Vector2`, `look_yaw: float`, `look_pitch: float`, `buttons: int` (bit flags `JUMP=1, SPRINT=2, CROUCH=4, FIRE=8, ADS=16, RELOAD=32, USE=64, MELEE=128, GRENADE=256, NEXT_WEAPON=512`), `t: float` (client clock).
  - **`Motor.step(state: Dictionary, f: InputFrame, dt: float, space: PhysicsDirectSpaceState3D) -> Dictionary`**: deterministic movement. Speeds: walk 4.5, sprint 6.8, crouch 2.2 m/s. Jump 4.8 m/s. Gravity 14.
  - **`Player`** (CharacterBody3D):
    - `peer_id: int`, `hp: float`, `state: int` (`ALIVE`, `DOWN`, `DEAD`), `points: int` (host-owned, replicated);
    - `apply_snapshot(s: Dictionary)`;
    - the local player keeps a ring of unacknowledged InputFrames and replays them after each host correction.
- [ ] Step 1: Write the unit tests:
  - `test_walk_speed`: one second of forward input moves 4.5 ± 0.05 m on a flat floor.
  - `test_sprint_speed`: 6.8 m/s.
  - `test_deterministic`: the same inputs twice give an identical state.
- [ ] Step 2: Write `net_move.gd` with a simulated 120 ms RTT. A client holds forward for 2 s. Check that the client's predicted position matches the host's within 0.15 m after the last ack, and that the remote view on another client stays within 0.3 m of the host's position delayed by 100 ms. Output: `MOVE NET PASS`.
- [ ] Step 3: Run both. Expected: FAIL.
- [ ] Step 4: Implement it. Inputs go to the host at 60 Hz in batches of the last 3 frames, for loss tolerance. The host acks `seq` in 20 Hz snapshots. Remote players interpolate between snapshots 100 ms behind.
- [ ] Step 5: Run both. Expected: PASS. Commit with "player: motor, prediction, interpolation".

### Task 5: Weapons and lag-compensated hits
**Files:**
- Create: `weapons/weapon_state.gd` (pure), `weapons/hit_history.gd`, `weapons/weapon_service.gd` (host), `weapons/weapon_view.gd` (client visuals)
- Test: `tests/unit/test_weapon_state.gd`, `tests/unit/test_hit_history.gd`, `tests/net/net_shoot.gd`, `tests/run_shoot_net.sh`

**Interfaces:**
- Consumes: `WeaponData`, `Content.balance`, `InputFrame.t`, `Net.sender_is`.
- Produces:
  - **`WeaponState`**:
    - `data: WeaponData`, `mag: int`, `reserve: int`;
    - `can_fire(now: float, rate_mult := 1.0) -> bool`, `fire(now) -> bool`, `start_reload(now, mult := 1.0)`, `update(now)`;
    - `damage_at(dist: float) -> float`, `refill()`.
  - **`HitHistory`**: `record(now: float, id: int, xform: Transform3D, alive: bool)` and `pose_at(id: int, t: float) -> Variant` (Transform3D or null). Keeps 0.25 s of history.
  - **`WeaponService`** (host):
    - `request_fire(shooter: int, origin: Vector3, dir: Vector3, t: float)` (RPC);
    - signals `hit(shooter: int, target: int, dmg: float, headshot: bool)`, `fire_rejected(shooter: int, reason: StringName)`.
- [ ] Step 1: Write the unit tests:
  - `test_fire_rate_limit`: at 600 rpm, a second fire 0.05 s later fails and one at 0.1 s succeeds.
  - `test_reload_moves_ammo`: mag 0, reserve 40, mag size 30, then reload gives mag 30 and reserve 10.
  - `test_falloff`: `damage_at` gives full damage before `falloff_start` and `damage*falloff_min_mult` after `falloff_end`.
  - `test_history_interpolates`: halfway between two poses returns the midpoint.
  - `test_history_clamps_old_and_future` (Review Focus 5): t = now − 1 s returns the oldest pose; a future t returns the newest.
  - `test_no_hit_on_entity_spawned_after_t`: `pose_at` returns null for times before the first record.
- [ ] Step 2: Write `net_shoot.gd` with a 150 ms RTT. A client fires at a moving dummy target it sees on screen, and the host records a hit (lag compensation works). The host rejects:
  - a client firing for another id (Review Focus 3): `fire_rejected` reason `&"sender"`;
  - firing with an empty mag: `&"ammo"`;
  - firing faster than rpm × (1 + fire_rate_tolerance): `&"rate"`;
  - firing through a wall: `&"los"`.
  - Output: `SHOOT NET PASS`.
- [ ] Step 3: Run them. Expected: FAIL.
- [ ] Step 4: Implement it. The client fires locally right away (muzzle flash, tracer, predicted hit marker). The host rewinds the targets' hitboxes to clamp(t, now − 0.25, now) and raycasts against them. The client's hit marker is confirmed or removed by the `hit` event.
- [ ] Step 5: Run them. Expected: PASS. Commit with "weapons: state, lag-comp hits, host validation".

### Task 6: Zombies and barricades
**Files:**
- Create: `enemies/zombie.gd` + `zombie.tscn`, `enemies/zombie_brain.gd` (host), `enemies/zombie_sync.gd` (snapshots and interpolation), `mapkit/barricade.gd` + `.tscn`
- Test: `tests/unit/test_barricade.gd`, `tests/net/net_zombie.gd`, `tests/run_zombie_net.sh`

**Interfaces:**
- Consumes: `EnemyData`, `RoundCurve.speed_band`, `HitHistory.record`, `WeaponService.hit`.
- Produces:
  - **`Zombie`**: `zid: int`, `hp: float`, `data: EnemyData`; `take_damage(dmg, from: int, headshot: bool)` (host); signal `died(zid, killer: int, headshot: bool, melee: bool, pos: Vector3)`.
  - **`Barricade`**: `boards: int` (max 6), `tear_one()`, `repair_one(by: int) -> bool`; signal `board_repaired(by: int)`; navigation link enabled only when `boards == 0`.
  - Snapshot entries: `[zid, pos: Vector3, yaw: float, anim: int]`, with at most 40 live entries.
- [ ] Step 1: Write the unit tests:
  - `test_barricade_tear_and_repair`: 6 boards, 6 tears, open, then a repair gives 1 board.
  - `test_repair_full_fails`: repairing at 6 boards returns false.
- [ ] Step 2: Write `net_zombie.gd`: the host spawns 40 zombies on a test map. They path to the nearest player through a barricade (it tears down and they pass). Clients receive every spawn, death and position within 0.5 m. A 41st spawn request is queued, not spawned. Output: `ZOMBIE NET PASS`.
- [ ] Step 3: Run them. Expected: FAIL.
- [ ] Step 4: Implement it. Zombies use NavigationAgent3D, and re-path no more than every 0.5 s. A zombie at a barricade with boards tears one every `board_tear_s`; at 0 boards it climbs through. Melee hits the player for `attack_damage` every `attack_interval_s`.
- [ ] Step 5: Run them. Expected: PASS. Commit with "enemies: zombie AI, barricades, sync".

### Task 7: Round director
**Files:**
- Create: `director/round_director.gd` (host), `mapkit/spawn_zone.gd` + `.tscn`, `mapkit/zone.gd`
- Test: `tests/unit/test_director.gd`

**Interfaces:**
- Consumes: `RoundCurve`, `Net.players`, `Zombie.died`.
- Produces:
  - **`RoundDirector`**:
    - `round: int`, `remaining: int`, `alive: int`;
    - `start_match()`, `tick(dt: float)`;
    - signals `round_started(r: int)`, `round_ended(r: int)`, `spawn_requested(zone: SpawnZone, health: int, band: int)`.
  - **`SpawnZone`**: `zone_id: StringName`, `active: bool`.
  - **`Zone`**: `zone_id: StringName`, `open: bool`.
- [ ] Step 1: Write the tests, using a fake clock and a fake spawner:
  - `test_round1_spawns_count`: 1 player gives 8 spawns.
  - `test_alive_cap_40`: on a round with 60 zombies, alive never exceeds 40.
  - `test_spawns_only_open_zones`.
  - `test_break_then_next_round`: the next round starts 10 s after the last death.
  - `test_health_per_round`: spawn health equals `curve.health(r)`.
- [ ] Step 2: Run `tests/run_unit.sh director`. Expected: FAIL.
- [ ] Step 3: Implement it. The player count is taken at round start.
- [ ] Step 4: Run them. Expected: PASS. Commit with "director: round loop and spawning".

### Task 8: Economy, wall-buys and doors
**Files:**
- Create: `economy/wallet.gd` (pure), `economy/economy_service.gd` (host), `mapkit/interactable.gd` (base), `mapkit/wall_buy.gd` + `.tscn`, `mapkit/bulkhead_door.gd` + `.tscn`
- Test: `tests/unit/test_wallet.gd`, `tests/net/net_economy.gd`, `tests/run_economy_net.sh`

**Interfaces:**
- Consumes: `Content.balance`, `Zombie.died`, `WeaponService.hit`, `Barricade.board_repaired`.
- Produces:
  - **`Wallet`**: `points: int`, `add(n: int, double_points: bool)`, `try_spend(cost: int) -> bool`, `board_points_this_round: int`.
  - **`EconomyService`**:
    - `request_use(player: int, interactable_path: NodePath)` (RPC); the host checks the sender, a distance ≤ 2.0 m and the cost;
    - signals `points_changed(player, points)`, `purchase(player, what: StringName, cost: int)`.
  - **`Interactable`**: `prompt(player: Player) -> String`, `cost_for(player) -> int`, `use(player) -> bool` (host).
  - **`BulkheadDoor`**: `cost: int`, `unlocks: Array[StringName]` (zone ids); when opened it sets `Zone.open` and enables the navigation link.
- [ ] Step 1: Write the unit tests:
  - `test_points_hit_kill_headshot_melee`: points of 10 / 60 / 100 / 120.
  - `test_board_cap`: board points stop at 400 per round.
  - `test_double_points`: a hit while double points is active gives 20.
- [ ] Step 2: Write `net_economy.gd`:
  - a client buys a wall gun and gets the weapon and the deducted points;
  - buying the same gun again buys ammo at `ammo_cost`;
  - two clients use the same 750 door in the same tick (Review Focus 2): exactly one pays and the other keeps 500;
  - a buy from 5 m away is rejected;
  - doors stay open for a client that joins afterwards.
  - Output: `ECONOMY NET PASS`.
- [ ] Step 3: Run them. Expected: FAIL.
- [ ] Step 4: Implement it. All interactable state is host-owned, and the host processes requests one at a time in arrival order.
- [ ] Step 5: Run them. Expected: PASS. Commit with "economy: points, wall-buys, doors".

### Task 9: Power switch, Ethereal-Suds, Requisition Crate, Isotope Refit
**Files:**
- Create: `scripts/game.gd` (autoload `Game`: `power: bool`, replicated by the host), `mapkit/power_switch.gd`, `mapkit/suds_machine.gd`, `mapkit/crate_spot.gd`, `mapkit/refit_station.gd` (each with a `.tscn`), `player/suds_effects.gd`
- Test: `tests/unit/test_suds_effects.gd`, `tests/net/net_machines.gd`, `tests/run_machines_net.sh`

**Interfaces:**
- Consumes: `Interactable`, `EconomyService`, `SudsData`, `WeaponData.refit`.
- Produces:
  - **`PowerSwitch`**: signal `power_on()`, global `Game.power: bool`.
  - **`SudsMachine`**: `suds: SudsData`. It requires power, refuses a duplicate Suds, and refuses at `max_suds`.
  - **`SudsEffects`**: `max_hp(base) -> float`, `reload_mult() -> float`, `revive_mult() -> float`, `fire_rate_mult() -> float`, `can_self_revive(solo: bool) -> bool`.
  - **`CrateSpot`**:
    - `use` charges 950 (or 0 with a voucher) and rolls a weapon from the crate pool (all non-wall-buy weapons plus wall-buys, never the player's current guns), using a host-seeded RNG;
    - after 6 uses it moves to another `CrateSpot`; signal `crate_moved(to: NodePath)`.
  - **`RefitStation`**: requires power, costs 5000, replaces the held weapon with `data.refit`, and refuses if `refit == null`.
- [ ] Step 1: Write the unit tests:
  - `test_suds_stack_effects`: all four Suds give max_hp 220, reload ×0.5, revive ×0.5, fire rate ×1.33.
  - `test_self_revive_only_solo`.
- [ ] Step 2: Write `net_machines.gd`:
  - Suds are refused before power is on;
  - power on, buy a Suds, and its effect shows on the host and every client;
  - a 5th Suds is refused;
  - a crate roll is identical on all peers and never duplicates a held gun;
  - the crate moves after 6 uses;
  - refit swaps in the upgraded weapon and refuses an already refitted one.
  - Output: `MACHINES NET PASS`.
- [ ] Step 3: Run them. Expected: FAIL.
- [ ] Step 4: Implement it.
- [ ] Step 5: Run them. Expected: PASS. Commit with "machines: power, Ethereal-Suds, crate, Isotope Refit".

### Task 10: Power-ups
**Files:**
- Create: `economy/powerup_service.gd` (host), `mapkit/powerup_pickup.gd` + `.tscn`
- Test: `tests/unit/test_powerup_rules.gd`, `tests/net/net_powerups.gd`, `tests/run_powerups_net.sh`

**Interfaces:**
- Consumes: `Zombie.died`, `PowerupData`, `Content.balance`, `Barricade`, `CrateSpot`, `RoundDirector`.
- Produces:
  - **`PowerupService`**:
    - `active: Dictionary` (kind → end time);
    - `is_active(kind) -> bool`;
    - `force_drop(kind, pos)` (tests and debug only);
    - signals `dropped(kind, pos)`, `collected(kind, by)`.
  - **Effects:**
    - `double_points` and `overload` last 30 s;
    - `max_ammo` refills every player;
    - `purge` kills every zombie and gives each player 400 points; those kills don't count toward drops;
    - `fortify` sets every barricade to 6;
    - `voucher` makes the next crate free.
- [ ] Step 1: Write the unit tests:
  - `test_drop_cap_per_round`: at most 4 drops per round, even at a 100 % chance.
  - `test_overload_one_hit`: with overload active, any damage kills.
- [ ] Step 2: Write `net_powerups.gd`: force each of the 6 drops, then check its effect on the host and all clients. The pickup disappears for everyone, and timed effects end at 30 s. Output: `POWERUPS NET PASS`.
- [ ] Step 3: Run them. Expected: FAIL.
- [ ] Step 4: Implement it. Pickups despawn after 25 s.
- [ ] Step 5: Run them. Expected: PASS. Commit with "powerups: six drops".

### Task 11: Down, revive, bleed-out, game over, disconnects
**Files:**
- Create: `player/life_rules.gd` (pure), `director/match_state.gd` (host)
- Test: `tests/unit/test_life_rules.gd`, `tests/net/net_life.gd`, `tests/run_life_net.sh`

**Interfaces:**
- Consumes: `Player.state`, `SudsEffects`, `Content.balance`, `Net.player_left`, `RoundDirector.round_started`.
- Produces:
  - **`LifeRules`**: `on_damage(p, dmg) -> int` (new state), `revive_progress(t_held, mult) -> float`, `bleedout_left(t_down) -> float`.
  - **`MatchState`**: `game_over: bool`; signal `game_over_reached(stats: Dictionary)`. Stats per player: `rounds`, `kills`, `downs`, `revives`, `points`.
  - Going down drops all Suds and switches the player to the sidearm.
  - Bled-out players respawn at the next round with the sidearm and no Suds.
- [ ] Step 1: Write the unit tests:
  - `test_down_at_zero`;
  - `test_revive_4s_or_2s_with_suds`;
  - `test_bleedout_30s`;
  - `test_solo_self_revive_with_suds`.
- [ ] Step 2: Write `net_life.gd`:
  - a player goes down and a teammate holds use for 4 s to revive them;
  - another player bleeds out and respawns at the next round;
  - all players down triggers `game_over_reached` on every peer with matching stats;
  - **Review Focus 1:** a client disconnects while down and the match does not end while others are alive; a disconnect while Overload is active leaves no stale state; the last connected player going down ends the game.
  - Output: `LIFE NET PASS`.
- [ ] Step 3: Run them. Expected: FAIL.
- [ ] Step 4: Implement it.
- [ ] Step 5: Run them. Expected: PASS. Commit with "life: down/revive/bleedout/game over".

### Task 12: Late join snapshot
**Files:**
- Create: `net/world_snapshot.gd`
- Modify: `net/net_session.gd` (send the snapshot on `player_joined` when a match is running)
- Test: `tests/net/net_latejoin.gd`, `tests/run_latejoin_net.sh`

**Interfaces:**
- Produces: `WorldSnapshot.capture() -> Dictionary` (round, power, doors, barricades, crate spot, every player's points/kit/Suds/state, active power-ups) and `WorldSnapshot.apply(d: Dictionary)`.
- [ ] Step 1: Write `net_latejoin.gd`: in round 3 with power on, 2 doors open and a Suds bought, a 4th client joins. Its state matches the host on every field, and it spawns when round 4 starts. Output: `LATEJOIN NET PASS`.
- [ ] Step 2: Run it. Expected: FAIL.
- [ ] Step 3: Implement it.
- [ ] Step 4: Run it. Expected: PASS. Commit with "net: late join snapshot".

### Task 13: Site 62 map (greybox, then CC0 art)
**Files:**
- Create: `maps/site62/site62.tscn`, `maps/site62/README.md` (zone layout)
- Create: `content/art/**` (CC0 imports), `content/CREDITS.md`
- Test: `tests/unit/test_map_site62.gd`

**Interfaces:**
- Consumes: every map kit scene.
- Produces a map with 5 zones:
  - `entrance_lab` (start; 2 barricades, Sentinel wall-buy);
  - `cafeteria` (door 750);
  - `offices` (door 1000);
  - `reactor_wing` (door 1250, power switch);
  - `refit_chamber` (door 1500, Isotope Refit).
- 4 Suds machines spread across zones, 3 crate spots, 4 player starts, at least 2 spawn zones per area, and baked navigation.
- [ ] Step 1: Write the map tests:
  - `test_map_has_required_nodes`: counts by group match the list above.
  - `test_all_zones_reachable_after_doors`: a navigation path exists from start to every zone with all doors open, and to none behind a closed door.
  - `test_every_asset_credited`: every file under `content/art` has a line in `CREDITS.md`.
- [ ] Step 2: Run them. Expected: FAIL.
- [ ] Step 3: Build the greybox, then dress it in the Cold War lab style with CC0 packs (Quaternius zombie and guns, Kenney / Poly Haven materials). Ethereal-Suds machines get a 70s soda look.
- [ ] Step 4: Run them. Expected: PASS. Commit with "map: Site 62".

### Task 14: UI (menus, HUD, game over)
**Files:**
- Create: `ui/main_menu.gd/.tscn` (Host, Join with LAN list, Settings, Quit), `ui/hud.gd/.tscn` (points, ammo, round, Suds icons, interact prompt, hit marker, down/revive bar, power-up timers, teammates' points), `ui/game_over.gd/.tscn`, `ui/settings.gd` (sensitivity, FOV, volume, key rebinds saved to `user://settings.cfg`)
- Create: `tools/shots_ui.gd/.tscn` (captures every screen and HUD state)
- Test: `tests/unit/test_hud_format.gd`

**Interfaces:**
- Consumes the signals from Tasks 3–11.
- Produces `Hud.format_points(n) -> String` (thousands separator) and `Hud.prompt_text(i: Interactable, p: Player) -> String` (for example "Hold F: Hornet [1200]", "Need power", "Hold F: Ammo [600]").
- [ ] Step 1: Write the unit tests for prompt texts: wall-buy, ammo, door, Suds without power, crate, voucher crate "Free", and refit.
- [ ] Step 2: Run them. Expected: FAIL.
- [ ] Step 3: Implement the UI, which must work with gamepad and keyboard/mouse.
- [ ] Step 4: Run the tests, then `tools/shots_ui` under the virtual display. Review every PNG before committing. Commit with "ui: menus, HUD, game over".

### Task 15: Full-match bot soak, lag/loss, PC exports
**Files:**
- Create: `tests/net/net_soak.gd`, `tests/run_soak_net.sh` (host + 3 bot clients using simple scripted inputs), `net/link_sim.gd` (drops and delays packets on the test transport), `export_presets.cfg` (Linux, Windows), `tools/export_pc.sh`
- Modify: `README.md` (how to play, controls, credits)

**Interfaces:**
- Consumes everything above.
- [ ] Step 1: Write `net_soak.gd` with a 120 ms RTT and 3 % loss. Bots shoot the nearest zombie, buy the first door when they can afford it, and revive downed teammates. Run to round 8 or game over. Every 5 s, check that all peers agree on round, points, doors and Suds. Output: `SOAK PASS rounds=N`.
- [ ] Step 2: Run it. Expected: FAIL until the bot client exists. Then implement the bot client and LinkSim.
- [ ] Step 3: Run it. Expected: `SOAK PASS` with N ≥ 5.
- [ ] Step 4: Run `tools/export_pc.sh`. It produces `build/Site62.x86_64` and `build/Site62.exe`. Launch the Linux build, host a match, and confirm it reaches round 2 with no errors in the log.
- [ ] Step 5: Run every test (`tests/run_unit.sh` and every `tests/run_*_net.sh` with distinct ports). Expected: all PASS. Commit with "M1: soak test, PC exports". Push to the private GitHub repo.

## Execution order and parallelism
- Tasks 1 → 2 → 3 must run in sequence.
- Task 4 and Task 7 can run in parallel.
- Task 5 needs Task 4. Task 6 needs Task 5.
- Tasks 8–11 run in sequence, because they share the economy.
- Task 12 runs after Task 11. Tasks 13 and 14 can run in parallel after Task 9. Task 15 comes last.

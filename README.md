# Site 62

Original wave-based co-op zombie shooter for 1 to 4 players (Godot 4.7, GDScript). A Cold War lab complex is overrun;
hold the entrance, earn points, open the bulkheads and push deeper. Gameplay values live in `content/*.tres`.

## How to play

- Run the exported build (`build/Site62.x86_64` or `build/Site62.exe`, see Export) or open the project in Godot 4.7.2.
- **Host:** main menu, Host. The game listens on **UDP 7862**. Wait in the lobby for friends, then press Start.
- **Join:** main menu, Join. Hosts on the same LAN show up in the list (LAN beacon, **UDP 7800**), or type the host's IP
  (port 7862). Joiners during a running match spectate until the next round starts.
- Allow UDP 7862 and 7800 through the host's firewall. There is no internet matchmaking or NAT traversal in Milestone 1.

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / look | WASD / mouse | left stick / right stick |
| Fire / aim down sights | left / right mouse button | right / left trigger |
| Reload | R | X |
| Use (buy, open, repair, revive: hold) | F | left bumper |
| Melee / grenade / swap weapon | V / G / Q | right stick click / right bumper / Y |
| Jump / sprint / crouch | Space / Shift / Ctrl | A / left stick click / B |
| Pause | Esc | Start |

All bindings can be changed in Settings.

## Licence

Copyright (c) 2026 sirbilliams. All rights reserved (see [LICENSE](LICENSE)). Third-party assets keep their own licences.
Textures and models are CC0 (Poly Haven and others); the two UI fonts are SIL OFL 1.1. [content/CREDITS.md](content/CREDITS.md)
lists every file, author, source and licence.

## Tests

- Unit: `tests/run_unit.sh [filter]`
- Multi-process network tests: `tests/run_*_net.sh` (each takes `PORT`, several take `RTT`/`LOSS`). Only
  `run_basic_net.sh` reads `BP` (LAN beacon port); every other test switches the beacon off (`Net.beacon_port = 0`), so
  `BP` has no effect there. The test hooks (`--test=...`, `--smoke=...`) exist only in debug builds and the "Linux Smoke"
  export.
- Run any of them under `timeout`, for example `timeout 600 env PORT=26410 tests/run_hostquit_net.sh`.
- Full-match soak: `tests/run_soak_net.sh` runs the real game on a host plus 3 bot clients at 120 ms RTT and 3 % loss
  (`LOSS=0` for a clean link) and prints `SOAK PASS rounds=N`.

## Export

Install the Godot 4.7.2 Linux and Windows export templates (official `Godot_v4.7.2-stable_export_templates.tpz`, checked
against the release's `SHA512-SUMS.txt`), then run `tools/export_pc.sh`. Output goes to `build/` (gitignored). Presets:
"Linux" and "Windows Desktop" in `export_presets.cfg` (no test code), plus "Linux Smoke" (`build/Site62_smoke.x86_64`, keeps the scripted
bot for `tools/smoke_build.sh`). The Windows build is exported but has not been run on Windows.

## Milestone 1 status / known gaps

Working: lobby and LAN join with ready handshake and late join, one map (Site 62: 5 zones, 4 bulkheads, power, 3 Suds
machines plus crates, Isotope Refit), the round director with zombie waves, points economy, weapons with lag
compensation, down and revive, power-ups, HUD, menus, settings, game over.

Known gaps:
- One enemy type, one map, placeholder-quality animation, sound and music are minimal.
- The soak bots exercise combat, ammo, every bulkhead door, the Requisition Crate, grenades, barricade repair and revives; they do not use the power switch, Suds machines or the Isotope Refit, and the soak ends when the bots die (rounds 5 to 7 so far), not at round 8.
- Movement uses a single wall ray plus a short push-out ring; very thin or odd collision can still let a player clip. A host-side kill plane (Y < -20) returns a fallen player to their last safe spot, and a zombie that stalls for 5 s is relocated to a spawn point.
- Network model is host-authoritative on UDP with no encryption, no NAT traversal and no dedicated server.
- Only the Linux build was launched and checked; the Windows export is untested, and neither build is signed.
- Gamepad support is implemented but has had little hands-on play time.
- Balance is a first pass; rounds beyond about 8 are untested.

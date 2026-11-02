class_name MatchState
extends Node
## Host-side life cycle of the players: down, revive, bleed-out, respawn, game over. Clients hold a node of the
## same name only to receive `game_over_reached` (reliable, same stats on every peer).
##  - hp 0 (zombie hits lower Player.hp; tick() notices, or call damage()) -> DOWN: Suds dropped (Game.clear_suds),
##    sidearm in hand (WeaponService.force_sidearm). A downed player crawls at Balance.downed_move_mult and may
##    fire only the sidearm. Zombies ignore DOWN / DEAD players; power-ups cannot be picked up by them.
##  - Revive: an ALIVE teammate within Balance.use_range holding USE for revive_hold_s x their revive_mult.
##    Releasing USE or stepping away resets the progress. Back with Balance.revive_hp_frac of max hp.
##  - Solo (the only connected player) with the revive Suds: self revive after revive_hold_s, the Suds is used up.
##  - Downed for downed_bleedout_s -> DEAD (no movement). The next round start respawns them at net.spawn with
##    the sidearm only, no Suds, full hp; points are kept.
##  - Game over: no connected player is ALIVE (a lone downed player who can still self revive counts as alive).
## A player leaving drops all of their per-player state, revive progress included.

signal game_over_reached(stats: Dictionary)
signal player_downed(peer: int)
signal player_revived(peer: int, by: int)
signal player_died(peer: int)
signal player_respawned(peer: int)

const VIEW_EVERY := 6                # physics ticks between revive messages (10 Hz)
const VIEW_FRESH_MS := 700

var net: PlayerNet
var weapons: WeaponService
var economy                          # EconomyService (or null: points come from Player.points)
var powerups                         # PowerupService (or null)
var game_over := false
var final_stats := {}                # peer -> {rounds, kills, downs, revives, points}; set when the game ends
var round := 0
var stats := {}                      # host: peer -> {rounds, kills, downs, revives}
var _down_t := {}                    # host: downed peer -> seconds since going down
var _rev := {}                       # host: downed peer -> {by, t} (teammate revive in progress)
var _view := {}                      # client: the latest revive message {downed, by, progress, bleed, at} (msec)
var _ticks := 0

func _ready() -> void:
	name = "MatchState"

func _enter_tree() -> void:
	if not Net.player_left.is_connected(_on_left):
		Net.player_left.connect(_on_left)

func _exit_tree() -> void:
	if Net.player_left.is_connected(_on_left):
		Net.player_left.disconnect(_on_left)

## Wire to the other services. `round_source` has a round_started(int) signal (Match / RoundDirector).
func bind(pn: PlayerNet, svc: WeaponService, eco, zs: ZombieSync, pu = null, round_source: Object = null) -> void:
	net = pn
	weapons = svc
	economy = eco
	powerups = pu
	if zs != null:
		zs.zombie_died.connect(func(_zid, killer, _h, _m, _p): _count(killer, "kills"))
	if round_source != null:
		round_source.round_started.connect(on_round_started)

## Fresh run (host and clients).
func reset() -> void:
	game_over = false
	final_stats = {}
	round = 0
	stats.clear()
	_down_t.clear()
	_rev.clear()
	_view = {}

func tracked(peer: int) -> bool:
	return stats.has(peer) or _down_t.has(peer) or _rev.has(peer)

## Host: seconds the reviver of `peer` has held USE, as 0..1 progress (0 when nobody is reviving).
func revive_progress_of(peer: int) -> float:
	if not _rev.has(peer):
		return 0.0
	return LifeRules.revive_progress(_rev[peer].t, Game.suds_of(_rev[peer].by).revive_mult())

# ---------------------------------------------------------------- host loop

func _physics_process(dt: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	tick(dt)

func tick(dt: float) -> void:
	if not Net.is_host() or net == null or game_over:
		return
	var ids := _ids()
	for id in ids:
		_stat(id)
		var p: Player = net.players[id]
		if p.state == Player.ALIVE and p.hp <= 0.0:
			_go_down(id, p)
	for id in ids:
		var p2: Player = net.players[id]
		if p2.state == Player.DOWN:
			_tick_down(id, p2, dt, ids.size() == 1)
	_check_game_over()
	_ticks += 1
	if _ticks % VIEW_EVERY == 0:
		_send_views()

## Host: apply `dmg` (a source other than zombies; they lower hp directly and tick() notices).
func damage(peer: int, dmg: float) -> void:
	var p: Player = net.players.get(peer) if net != null else null
	if p == null or game_over:
		return
	if LifeRules.on_damage(p, dmg) == Player.DOWN:
		_go_down(peer, p)
		_check_game_over()

## Host: a player joined mid-match. They watch (DEAD: no movement, not counted for game over, ignored by
## zombies and pickups) until the next round start respawns them with the starting kit.
func spectate(id: int) -> void:
	var p: Player = net.players.get(id) if net != null else null
	if p == null:
		return
	p.state = Player.DEAD
	p.hp = 0.0
	_stat(id)

func on_round_started(r: int) -> void:
	round = r
	if not Net.is_host() or net == null or game_over:
		return
	for id in _ids():
		_stat(id).rounds = r
		var p: Player = net.players[id]
		if p.state == Player.DEAD:
			_respawn(id, p)

# ---------------------------------------------------------------- revive bars (HUD)

## Fraction (0..1) of the bleed-out time a downed `peer` has left (host).
func bleed_left_of(peer: int) -> float:
	if not _down_t.has(peer):
		return 0.0
	return LifeRules.bleedout_left(_down_t[peer]) / maxf(Content.balance.downed_bleedout_s, 0.001)

## Host: tell each downed player, and whoever is reviving them, the progress (unreliable, 10 Hz). The host
## itself reads _rev directly in view_for.
func _send_views() -> void:
	for id in _down_t.keys():
		var by: int = _rev[id].by if _rev.has(id) else 0
		var msg := [id, by, revive_progress_of(id), bleed_left_of(id)]
		if id != Net.local_id():
			Net.send_unreliable(self, &"_rx_revive", id, msg)
		if by != 0 and by != id and by != Net.local_id():
			Net.send_unreliable(self, &"_rx_revive", by, msg)

@rpc("authority", "unreliable")
func _rx_revive(downed, by, progress, bleed) -> void:
	if Net.is_host():
		return
	apply_revive(downed, by, progress, bleed)

## Client (and tests): take one revive message.
func apply_revive(downed, by, progress, bleed) -> void:
	if typeof(downed) != TYPE_INT or typeof(by) != TYPE_INT:
		return
	for v in [progress, bleed]:
		if not (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) or not is_finite(float(v)):
			return
	_view = {"downed": downed, "by": by, "progress": clampf(float(progress), 0.0, 1.0),
		"bleed": clampf(float(bleed), 0.0, 1.0), "at": Time.get_ticks_msec()}

## What the HUD shows for `peer`: {role: "downed" | "reviver" | "", other: peer id (0 none), progress, bleed}.
## "downed": my own bars (bleed-out left, revive progress by `other`). "reviver": I am reviving `other`.
func view_for(peer: int) -> Dictionary:
	if not _view.is_empty() and Time.get_ticks_msec() - int(_view.at) <= VIEW_FRESH_MS:
		if _view.downed == peer:
			return {"role": "downed", "other": _view.by, "progress": _view.progress, "bleed": _view.bleed}
		if _view.by == peer and _view.by != _view.downed:
			return {"role": "reviver", "other": _view.downed, "progress": _view.progress, "bleed": _view.bleed}
	if _down_t.has(peer):
		var by: int = _rev[peer].by if _rev.has(peer) else 0
		var prog := revive_progress_of(peer)
		if by == 0 and _ids().size() == 1:
			prog = LifeRules.self_revive_progress(_down_t[peer], Game.suds_of(peer), true)
		return {"role": "downed", "other": by, "progress": prog, "bleed": bleed_left_of(peer)}
	for d in _rev:
		if _rev[d].by == peer and d != peer:
			return {"role": "reviver", "other": d, "progress": revive_progress_of(d), "bleed": bleed_left_of(d)}
	return {"role": "", "other": 0, "progress": 0.0, "bleed": 0.0}

# ---------------------------------------------------------------- transitions (host)

func _go_down(id: int, p: Player) -> void:
	p.state = Player.DOWN
	p.hp = 0.0
	_down_t[id] = 0.0
	_rev.erase(id)
	_count(id, "downs")
	# alone, the revive Suds survives so the solo self revive can use it; in a team every Suds is dropped
	Game.clear_suds(id, p, [&"revive"] if _ids().size() == 1 else [])
	p.hp = 0.0
	if weapons != null:
		weapons.force_sidearm(id)
	player_downed.emit(id)

func _tick_down(id: int, p: Player, dt: float, solo: bool) -> void:
	var t: float = _down_t.get(id, 0.0) + dt
	_down_t[id] = t
	if LifeRules.bleedout_left(t) <= 0.0:
		_die(id, p)
		return
	var by := _find_reviver(id, p)
	if by != 0:
		var r: Dictionary = _rev.get(id, {})
		if r.is_empty() or r.by != by:
			r = {"by": by, "t": 0.0}      # a different reviver starts over
		r.t += dt
		_rev[id] = r
		if LifeRules.revive_progress(r.t, Game.suds_of(by).revive_mult()) >= 1.0:
			_revive(id, p, by)
		return
	_rev.erase(id)                         # released or walked away
	if solo and LifeRules.self_revive_progress(t, Game.suds_of(id), true) >= 1.0:
		Game.consume_effect(id, &"revive", p)
		_revive(id, p, id)

func _find_reviver(id: int, p: Player) -> int:
	var use_range := Content.balance.use_range
	for rid in _ids():
		if rid == id:
			continue
		var r: Player = net.players[rid]
		if r.state != Player.ALIVE or not (_buttons_of(rid) & InputFrame.USE):
			continue
		var d := r.position - p.position
		if Vector2(d.x, d.z).length() <= use_range and absf(d.y) < 3.0:
			return rid
	return 0

func _buttons_of(id: int) -> int:
	return net.local_buttons if id == Net.local_id() else int(net.last_buttons.get(id, 0))

func _revive(id: int, p: Player, by: int) -> void:
	p.state = Player.ALIVE
	p.hp = LifeRules.revive_hp(p.max_health())
	_down_t.erase(id)
	_rev.erase(id)
	if by != id:
		_count(by, "revives")
	player_revived.emit(id, by)

func _die(id: int, p: Player) -> void:
	p.state = Player.DEAD
	p.hp = 0.0
	_down_t.erase(id)
	_rev.erase(id)
	player_died.emit(id)

func _respawn(id: int, p: Player) -> void:
	Game.clear_suds(id, p)                 # normally already empty; makes the respawn rule unconditional
	p.state = Player.ALIVE
	p.hp = p.max_health()
	p.teleport(net.spawn)
	if weapons != null:
		weapons.reset_kit(id)
	player_respawned.emit(id)

func _on_left(id: int) -> void:
	stats.erase(id)
	_down_t.erase(id)
	_rev.erase(id)
	for k in _rev.keys():
		if _rev[k].by == id:
			_rev.erase(k)                  # the reviver is gone: progress starts over
	if Net.is_host() and net != null and not game_over:
		_check_game_over()

# ---------------------------------------------------------------- game over

func _ids() -> Array:
	var out: Array = []
	if net == null:
		return out
	for id in Net.players.ids():
		if net.players.has(id):
			out.append(id)
	return out

func _check_game_over() -> void:
	var ids := _ids()
	if ids.is_empty() or game_over:
		return
	for id in ids:
		var p: Player = net.players[id]
		if p.state == Player.ALIVE:
			return
		if p.state == Player.DOWN and Game.suds_of(id).can_self_revive(ids.size() == 1):
			return
	game_over = true
	var out := {}
	for id in ids:
		var s := _stat(id)
		out[id] = {"rounds": maxi(int(s.rounds), round), "kills": s.kills, "downs": s.downs, "revives": s.revives,
			"points": _points_of(id)}
	final_stats = out
	if powerups != null:
		powerups.end_all()
	Net.send_reliable(self, &"_rx_game_over", 0, [out])
	game_over_reached.emit(out)

func _points_of(id: int) -> int:
	if economy != null:
		return economy.wallet(id).points
	return (net.players[id] as Player).points

func _stat(id: int) -> Dictionary:
	if not stats.has(id):
		stats[id] = {"rounds": round, "kills": 0, "downs": 0, "revives": 0}
	return stats[id]

func _count(id: int, key: String) -> void:
	if net != null and Net.is_host() and net.players.has(id):
		_stat(id)[key] += 1

@rpc("authority", "reliable")
func _rx_game_over(s) -> void:
	if Net.is_host() or typeof(s) != TYPE_DICTIONARY or game_over:
		return
	var clean := {}
	for k in s:
		var v = s[k]
		if typeof(k) != TYPE_INT or typeof(v) != TYPE_DICTIONARY:
			return
		for f in ["rounds", "kills", "downs", "revives", "points"]:
			if typeof(v.get(f)) != TYPE_INT:
				return
		clean[k] = {"rounds": v.rounds, "kills": v.kills, "downs": v.downs, "revives": v.revives, "points": v.points}
	game_over = true
	final_stats = clean
	game_over_reached.emit(clean)

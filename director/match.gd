class_name Match
extends Node
## Host-side orchestrator. Only wires existing pieces; the rules stay in RoundDirector / ZombieSync / EconomyService.
##  - RoundDirector.spawn_requested -> ZombieSync.spawn at that SpawnZone with the curve's health and band.
##  - ZombieSync.zombie_died -> RoundDirector.on_zombie_died. ZombieSync.despawn emits no zombie_died, so a
##    despawn never counts as a death: the director only learns about kills (a cleanup despawn of a director
##    zombie is the caller's job to follow with director.on_zombie_died()).
##  - round_started -> EconomyService.reset_round (board cap reset + grenade refill).
##  - Zone.opened -> the SpawnZones with that zone_id turn active.
##  - Director player count = connected players (Net.players) unless `player_count` is set.
## Clients hold a Match node of the same name only to receive `round` and `phase` (reliable). A late joiner gets
## them from the WorldSnapshot, not from here.

signal round_started(r: int)
signal round_ended(r: int)

const PLAYING := &"playing"
const BREAK := &"break"

var zombies                         # ZombieSync (or a fake with spawn() and zombie_died)
var economy                         # EconomyService (or a fake with reset_round())
var curve: RoundCurve               # null = Content.curve
var player_count := Callable()      # () -> int; invalid = Net.players
var enemy_id: StringName = &"shambler"
var round := 0
var phase: StringName = &""
var director: RoundDirector
var running := false
var _zones: Array[Zone] = []
var _spawn_zones: Array[SpawnZone] = []

func _ready() -> void:
	name = "Match"

func state() -> Dictionary:
	return {"round": round, "phase": String(phase)}

## Host: wire everything under `map_root` and begin round 1.
func start(map_root: Node) -> void:
	if not Net.is_host():
		push_warning("Match.start ignored: only the host runs the match")
		return
	stop()
	_zones.clear()
	_spawn_zones.clear()
	_collect(map_root)
	director = RoundDirector.new()
	add_child(director)
	director.set_curve(curve if curve != null else Content.curve)
	var zs: Array[SpawnZone] = _spawn_zones
	director.set_zones(zs)
	if player_count.is_valid():
		director.set_player_count_provider(player_count)
	director.spawn_requested.connect(_on_spawn_requested)
	director.round_started.connect(_on_round_started)
	director.round_ended.connect(_on_round_ended)
	zombies.zombie_died.connect(_on_zombie_died)
	for z in _zones:
		z.opened.connect(_sync_zones)
	_sync_zones()
	running = true
	director.start_match()

func stop() -> void:
	running = false
	if director != null:
		if zombies != null and zombies.zombie_died.is_connected(_on_zombie_died):
			zombies.zombie_died.disconnect(_on_zombie_died)
		for z in _zones:
			if is_instance_valid(z) and z.opened.is_connected(_sync_zones):
				z.opened.disconnect(_sync_zones)
		director.queue_free()
		director = null

func _collect(n: Node) -> void:
	if n is Zone:
		_zones.append(n)
	elif n is SpawnZone:
		_spawn_zones.append(n)
	for c in n.get_children():
		_collect(c)

func _sync_zones() -> void:
	var open := {}
	for z in _zones:
		if z.open:
			open[z.zone_id] = true
	for sz in _spawn_zones:
		sz.active = open.has(sz.zone_id)

func tick(dt: float) -> void:
	if running:
		director.tick(dt)

func _physics_process(dt: float) -> void:
	if running and Net.is_host():
		tick(dt)

func _on_spawn_requested(zone: SpawnZone, health: int, band: int) -> void:
	zombies.spawn(zone.position if not zone.is_inside_tree() else zone.global_position, enemy_id, float(health), band)

func _on_zombie_died(_zid, _killer, _head, _melee, _pos) -> void:
	director.on_zombie_died()

func _on_round_started(r: int) -> void:
	round = r
	phase = PLAYING
	if economy != null:
		economy.reset_round()
	_broadcast(0)
	round_started.emit(r)

func _on_round_ended(r: int) -> void:
	phase = BREAK
	_broadcast(0)
	round_ended.emit(r)

func _broadcast(peer: int) -> void:
	Net.send_reliable(self, &"_rx_state", peer, [round, String(phase)])

@rpc("authority", "reliable")
func _rx_state(r, p) -> void:
	if not Net.is_host():
		apply_state(r, p)

## Client: take round and phase from the host (a round message or the late join WorldSnapshot).
func apply_state(r, p) -> void:
	if Net.is_host() or not (r is int and p is String) or r < 0:
		return
	if p != String(PLAYING) and p != String(BREAK):
		return
	round = r
	phase = StringName(p)

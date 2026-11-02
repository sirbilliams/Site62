class_name ZombieBrain
extends RefCounted
## Host-side zombie AI: nearest living player -> NavigationAgent3D path (re-pathed at most every
## Balance.repath_s) -> tears a closed barricade between it and the target (one board per board_tear_s) ->
## follows the agent path through the barricade's NavigationLink3D once it is open (slower there, CLIMB anim)
## -> melee for attack_damage every attack_interval_s.

const MELEE_RANGE := 1.5
const WINDUP_S := 0.4
const CLIMB_SPEED_MULT := 0.5

var z: Zombie
var repaths := 0
var min_repath_gap := INF          # smallest spacing between two path requests (tests)
var _clock := 0.0
var _last_repath := -INF
var _repath_in := 0.0
var _attack_cd := WINDUP_S
var _tear_cd := 0.0
var _tearing: Barricade
var watch := StallWatch.new()
var _cross_door: BulkheadDoor     # open door whose link the zombie is crossing (committed direction in _cross_to)
var _cross_to := Vector3.ZERO
var walking := false          # this tick the zombie was chasing a target on foot (not meleeing, tearing or idle): the stall watchdog counts it

## True when `b` stands between a zombie at `zpos` and its target at `tpos` and the zombie is in tearing reach.
static func wants_tear(b: Barricade, zpos: Vector3, tpos: Vector3) -> bool:
	return b.boards > 0 and b.is_outside(zpos) and not b.is_outside(tpos) and b.distance_to(zpos) <= Barricade.TEAR_REACH

## players: peer id -> Player. barricades: Array[Barricade].
func tick(dt: float, players: Dictionary, barricades: Array, doors: Array = []) -> void:
	_clock += dt
	walking = false
	var target := _nearest(players)
	if target == null:
		z.anim = Zombie.Anim.IDLE
		return
	var tp := target.global_position
	var to := tp - z.position
	to.y = 0.0
	if to.length() <= MELEE_RANGE:
		_stop_tearing()
		_melee(dt, target, to)
		return
	_attack_cd = WINDUP_S
	var link_b := _link_zone(barricades)
	var door_b := _door_zone(doors)
	if door_b == null:
		if _cross_door != null:
			_cross_door = null
			_repath_in = 0.0           # off the link: a fresh path from the mesh
	if link_b == null and door_b == null:       # between the link ends the zombie is off the nav mesh: keep the path
		_repath_in -= dt
		if _repath_in <= 0.0:
			_repath(tp)
	for b: Barricade in barricades:
		if wants_tear(b, z.position, tp):
			_tear(dt, b)
			return
	_stop_tearing()
	walking = true
	if door_b != null:
		_cross(dt, door_b, tp)
	else:
		_walk(dt, link_b != null)

func _repath(tp: Vector3) -> void:
	_repath_in = Content.balance.repath_s
	z.agent.target_position = tp
	repaths += 1
	min_repath_gap = minf(min_repath_gap, _clock - _last_repath)
	_last_repath = _clock

## The open barricade whose window the zombie is crossing (inside the link ends, near its axis), or null.
func _link_zone(barricades: Array) -> Barricade:
	for b: Barricade in barricades:
		if b.boards == 0:
			var d := z.position - b.global_position
			if absf(d.dot(b.outside_dir())) <= Barricade.LINK_REACH + 0.3 and absf(d.dot(b.global_transform.basis.x)) <= 1.5:
				return b
	return null

## The open bulkhead whose link the zombie is between the ends of (off the nav mesh), or null.
## Without this the zombie re-paths from the middle of the link: its closest mesh point flips between the two ends and a slow
## zombie ping-pongs at the door forever (found with tools/repro_door3.gd; every zombie behind it stacks up).
func _door_zone(doors: Array) -> BulkheadDoor:
	for d: BulkheadDoor in doors:
		if not d.is_open or d.link == null:
			continue
		var ends := d.link_ends()
		var ab: Vector3 = ends[1] - ends[0]
		ab.y = 0.0
		var len2 := ab.length_squared()
		if len2 < 0.01:
			continue
		var zp: Vector3 = z.position - ends[0]
		zp.y = 0.0
		var t := zp.dot(ab) / len2
		var lateral := absf(zp.x * ab.z - zp.z * ab.x) / sqrt(len2)
		if t > 0.05 and t < 0.95 and lateral <= 1.5:
			return d
	return null

## Cross the link in one committed direction (towards the end nearer the target), straight, no path queries.
func _cross(dt: float, door: BulkheadDoor, tp: Vector3) -> void:
	if _cross_door != door:
		_cross_door = door
		var ends := door.link_ends()
		var da := Vector2(ends[0].x - tp.x, ends[0].z - tp.z).length()
		var db := Vector2(ends[1].x - tp.x, ends[1].z - tp.z).length()
		_cross_to = ends[0] if da < db else ends[1]
	var d := _cross_to - z.position
	d.y = 0.0
	z.anim = Zombie.Anim.WALK
	z.position += d.normalized() * minf(z.speed() * dt, d.length())
	_face(d)

func _nearest(players: Dictionary) -> Player:
	var best: Player = null
	var bd := INF
	for p: Player in players.values():
		if p.state != Player.ALIVE or p.hp <= 0.0:
			continue
		var d := p.global_position.distance_squared_to(z.position)
		if d < bd:
			bd = d
			best = p
	return best

func _tear(dt: float, b: Barricade) -> void:
	if _tearing != b:
		_stop_tearing()
		_tearing = b
		_tear_cd = z.data.board_tear_s
	if not b.try_claim(z.zid):
		z.anim = Zombie.Anim.IDLE       # queue behind the zombie that is tearing
		return
	z.anim = Zombie.Anim.TEAR
	_face(b.global_position - z.position)
	_tear_cd -= dt
	if _tear_cd <= 0.0:
		_tear_cd = z.data.board_tear_s
		b.tear_one()
		if b.boards == 0:
			b.release(z.zid)

func _stop_tearing() -> void:
	if _tearing != null:
		_tearing.release(z.zid)
		_tearing = null

func release_all() -> void:
	_stop_tearing()

func _melee(dt: float, target: Player, to: Vector3) -> void:
	z.anim = Zombie.Anim.ATTACK
	_face(to)
	_attack_cd -= dt
	if _attack_cd <= 0.0:
		_attack_cd = z.data.attack_interval_s
		target.hp = maxf(0.0, target.hp - z.data.attack_damage)   # MatchState.tick() sees hp 0 and downs the player

func _walk(dt: float, crossing: bool) -> void:
	var next := z.agent.get_next_path_position()
	var d := next - z.position
	z.anim = Zombie.Anim.CLIMB if crossing else Zombie.Anim.WALK
	if Vector2(d.x, d.z).length() < 0.02:
		return
	var spd := z.speed() * (CLIMB_SPEED_MULT if crossing else 1.0)
	z.position += d.normalized() * minf(spd * dt, d.length())
	_face(d)

func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.01:
		z.yaw = atan2(-dir.x, -dir.z)
		z.rotation.y = z.yaw

## Host: the zombie was put somewhere else (stall watchdog): forget the old path and the stall window.
func relocated() -> void:
	_repath_in = 0.0
	watch.reset()

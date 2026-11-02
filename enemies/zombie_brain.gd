class_name ZombieBrain
extends RefCounted
## Host-side zombie AI: nearest living player -> NavigationAgent3D path (re-pathed at most every
## Balance.repath_s) -> tears a closed barricade in front of it (one board per board_tear_s) -> climbs
## through the open window -> melee for attack_damage every attack_interval_s.

const MELEE_RANGE := 1.5
const WINDUP_S := 0.4
const CLIMB_SPEED_MULT := 0.5

var z: Zombie
var repaths := 0
var _repath_in := -1.0
var _attack_cd := WINDUP_S
var _tear_cd := 0.0
var _tearing: Barricade
var _force_repath := false
var _climb: Array = []             # waypoints through an open window; the nav mesh has a gap there, so no re-pathing

## players: peer id -> Player. barricades: Array[Barricade].
func tick(dt: float, players: Dictionary, barricades: Array) -> void:
	var target := _nearest(players)
	if target == null:
		z.anim = Zombie.Anim.IDLE
		return
	var tp := target.global_position
	var to := tp - z.position
	to.y = 0.0
	if to.length() <= MELEE_RANGE:
		_stop_tearing()
		_climb.clear()
		_melee(dt, target, to)
		return
	_attack_cd = WINDUP_S
	if not _climb.is_empty():
		_climb_step(dt)
		return
	_repath_in -= dt
	if _repath_in <= 0.0 or _force_repath:
		_repath_in = Content.balance.repath_s
		_force_repath = false
		z.agent.target_position = tp
		repaths += 1
	var b := _blocking_barricade(barricades)
	if b != null:
		_tear(dt, b)
		return
	_stop_tearing()
	for ob: Barricade in barricades:
		if ob.boards == 0 and ob.is_outside(z.position) and ob.distance_to(z.position) <= Barricade.TEAR_REACH:
			_climb = [ob.to_global(ob.link.start_position), ob.to_global(ob.link.end_position)]
			_climb_step(dt)
			return
	_walk(dt)

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

func _blocking_barricade(barricades: Array) -> Barricade:
	for b: Barricade in barricades:
		if b.boards > 0 and b.is_outside(z.position) and b.distance_to(z.position) <= Barricade.TEAR_REACH:
			return b
	return null

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
			_force_repath = true         # the link just opened

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
		target.hp = maxf(0.0, target.hp - z.data.attack_damage)   # down/revive: Task 11

func _walk(dt: float) -> void:
	var next := z.agent.get_next_path_position()
	var d := next - z.position
	z.anim = Zombie.Anim.WALK
	if Vector2(d.x, d.z).length() < 0.02:
		return
	z.position += d.normalized() * minf(z.speed() * dt, d.length())
	_face(d)

func _climb_step(dt: float) -> void:
	z.anim = Zombie.Anim.CLIMB
	var d: Vector3 = _climb[0] - z.position
	_face(d)
	var step := z.speed() * dt * CLIMB_SPEED_MULT
	if d.length() <= step:
		z.position = _climb[0]
		_climb.pop_front()
		if _climb.is_empty():
			_force_repath = true
	else:
		z.position += d.normalized() * step

func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.01:
		z.yaw = atan2(-dir.x, -dir.z)
		z.rotation.y = z.yaw

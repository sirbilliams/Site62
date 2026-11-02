class_name SoakBot
extends RefCounted
## A scripted player for the soak: produces real InputFrames (move / look / buttons) for PlayerNet.input_source and
## presses the "use" action so the real InteractController does the buying and repairing. No host-side shortcuts.
##   1. a downed teammate nearby (and no zombie close): walk there and hold USE (revive)
##   2. a zombie in line of sight: face it and fire, keep some distance, reload when empty
##   3. no zombie: walk to the first affordable bulkhead door and buy it
##   4. otherwise repair the nearest damaged barricade, else wait in the entrance lab

const FIRE_RANGE := 30.0
const KEEP_AWAY := 4.0
const EYE := 1.6

var g: GameRoot
var frames := 0
var shots := 0
var revives_tried := 0
var doors_bought := 0
var _path := PackedVector3Array()
var _path_goal := Vector3.INF
var _path_t := -10.0
var _using := false
var _strafe := 1.0
var _yaw := 0.0
var _pitch := 0.0
var _last_pos := Vector3.ZERO
var _stuck_t := 0.0
var _reach_t := -10.0
var _reach := false
var _last_nade := -1000
var branch := ""
var goal_dbg := Vector3.INF

func _init(game: GameRoot) -> void:
	g = game

func frame() -> InputFrame:
	var f := InputFrame.new()
	frames += 1
	f.look_yaw = _yaw
	f.look_pitch = _pitch
	var me := g.net.local_player()
	if me == null or me.state == Player.DEAD or g.mt.round < 1 or g.state != GameRoot.PLAYING:
		_set_use(false)
		return f
	var pos: Vector3 = me.motor_state.pos
	var eye := pos + Vector3(0, EYE, 0)
	var st := g.svc.state_for(Net.local_id())
	var zt := _nearest_zombie(pos)
	var z_los := false
	var zpos := Vector3.ZERO
	if zt != null:
		zpos = zt.position + Vector3(0, 1.62, 0)               # head
		z_los = pos.distance_to(zt.position) <= FIRE_RANGE and _clear(eye, zpos)
	var down: Player = _downed_teammate(pos)
	var ammo_buy := _ammo_buy(me, st)
	var no_ammo: bool = st.mag + st.reserve <= 0
	var near_threat: bool = zt != null and pos.distance_to(zt.position) < 8.0
	var goal := Vector3.INF
	var want_use := false
	var downed := me.state == Player.DOWN
	var faced := false
	if down != null and not near_threat and not downed:
		branch = "revive"
		goal = down.position
		var dist := Vector2(goal.x - pos.x, goal.z - pos.z).length()
		_face(f, down.position + Vector3(0, 0.3, 0) - eye)
		faced = true
		if dist <= 1.4:
			want_use = true
			goal = Vector3.INF
			revives_tried += 1
	elif z_los and not (no_ammo and ammo_buy != null):
		branch = "fire"
		var d := zpos - eye
		_face(f, d)
		faced = true
		var flat := Vector2(d.x, d.z)
		if st.mag > 0 and not st.reloading:
			# semi-auto needs a release between shots: pulse 3 ticks on / 3 off (robust when render frames skip physics ticks)
			if st.data.mode == 1 or frames % 6 < 3:
				f.buttons |= InputFrame.FIRE
				shots += 1
		if st.mag <= 0 and not st.reloading:
			f.buttons |= InputFrame.RELOAD if st.reserve > 0 else InputFrame.MELEE
			if st.reserve <= 0 and frames % 30 == 0:
				f.buttons |= InputFrame.NEXT_WEAPON
		if flat.length() < KEEP_AWAY:
			f.move = _local_move(f, -flat.normalized())   # back off
		elif frames % 90 == 0:
			_strafe = -_strafe
		if flat.length() >= KEEP_AWAY:
			f.move = _local_move(f, Vector2(flat.y, -flat.x).normalized() * _strafe) * 0.5
		if flat.length() < 1.6:
			f.buttons |= InputFrame.MELEE
		if frames - _last_nade > 600 and _crowd(zt.position) >= 4 and flat.length() > 5.0:
			f.buttons |= InputFrame.GRENADE
			_last_nade = frames
	elif zt != null and not near_threat and not no_ammo and pos.distance_to(zt.position) < 18.0 and _zombie_reachable(pos, zt):
		branch = "closein"
		goal = zt.position                                  # no line of sight: close in
	else:
		branch = "idle"
		if st.mag < st.data.mag and not st.reloading and st.reserve > 0 and (frames % 60 == 0):
			f.buttons |= InputFrame.RELOAD
		var door := _door_goal(me, pos)
		var crate := _crate_goal(me, pos)
		if ammo_buy != null and not downed:
			branch = "ammo"
			goal = ammo_buy.global_position
			_face(f, goal + Vector3(0, 1.0, 0) - eye)
			faced = true
			if Vector2(goal.x - pos.x, goal.z - pos.z).length() <= 1.3:
				want_use = true
				goal = Vector3.INF
		elif crate != null:
			branch = "crate"
			goal = crate.global_position
			_face(f, goal + Vector3(0, 1.0, 0) - eye)
			faced = true
			if Vector2(goal.x - pos.x, goal.z - pos.z).length() <= 1.3:
				want_use = true
				goal = Vector3.INF
		elif door != null:
			branch = "door"
			goal = door.global_position
			var dd := Vector2(goal.x - pos.x, goal.z - pos.z).length()
			_face(f, goal + Vector3(0, 1.0, 0) - eye)
			faced = true
			if dd <= 1.3:
				want_use = true
				goal = Vector3.INF
		else:
			var b := _damaged_barricade(pos) if g.zs.live_count() == 0 else null     # never while zombies tear boards: that is a stalemate
			if b != null:
				branch = "repair"
				var inside := b.global_position + b.outside_dir() * -1.3
				goal = inside
				_face(f, b.global_position + Vector3(0, 1.0, 0) - eye)
				faced = true
				if Vector2(inside.x - pos.x, inside.z - pos.z).length() <= 0.8:
					want_use = true
					goal = Vector3.INF
			else:
				goal = Vector3(0, 0, 8)
				if Vector2(goal.x - pos.x, goal.z - pos.z).length() < 2.5:
					goal = Vector3.INF
	goal_dbg = goal
	if goal.is_finite():
		var wp := _steer(pos, goal)
		var dir := Vector2(wp.x - pos.x, wp.z - pos.z)
		if dir.length() > 0.05:
			if not faced:
				_face_dir(f, dir)
			f.move = _local_move(f, dir.normalized())
	if want_use:
		f.buttons |= InputFrame.USE
	_set_use(want_use)
	_unstick(f, pos)
	_yaw = f.look_yaw
	_pitch = f.look_pitch
	return f

# ---------------------------------------------------------------- targets

func _nearest_zombie(pos: Vector3) -> Zombie:
	var best: Zombie
	var bd := INF
	for z: Zombie in g.zs.zombies.values():
		if not is_instance_valid(z) or not z.alive:
			continue
		var d := pos.distance_to(z.position)
		if d < bd:
			bd = d
			best = z
	return best

## Is the zombie reachable on foot (closed barricades and doors cut the navigation mesh)? Cached for 0.5 s.
func _zombie_reachable(pos: Vector3, z: Zombie) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _reach_t > 0.5:
		_reach_t = now
		_reach = _reachable(pos, z.position)
	return _reach

## Live zombies within 4 m of `p`.
func _crowd(p: Vector3) -> int:
	var n := 0
	for z: Zombie in g.zs.zombies.values():
		if is_instance_valid(z) and z.alive and z.position.distance_to(p) < 4.0:
			n += 1
	return n

func _downed_teammate(pos: Vector3) -> Player:
	var best: Player
	var bd := INF
	for id in g.net.players:
		var p: Player = g.net.players[id]
		if id == Net.local_id() or p.state != Player.DOWN:
			continue
		var d := pos.distance_to(p.position)
		if d < bd:
			bd = d
			best = p
	return best

## The wall buy that refills the held gun when ammo is low and affordable (else null).
func _ammo_buy(me: Player, st: WeaponState) -> Interactable:
	if me.state != Player.ALIVE or st.mag + st.reserve > 7 * st.data.mag:
		return null
	if g.zs.live_count() > 0 and st.mag + st.reserve > st.data.mag:
		return null                                         # mid-fight: only a (nearly) empty gun justifies the walk
	for it: Interactable in g.get_tree().get_nodes_in_group(&"interactables"):
		if it is WallBuy and it.weapon_id == st.data.id:
			it.weapons = g.svc
			if it.reject_reason(me) == &"" and me.points >= it.cost_for(me):
				return it
	return null

## The active Requisition Crate when affordable and the second gun slot is still empty (once per bot).
func _crate_goal(me: Player, pos: Vector3) -> Interactable:
	var kit := g.svc.kit_for(Net.local_id())
	if me.state != Player.ALIVE or kit.slots[1] != null and kit.slots[0] != null:
		return null
	for c: CrateSpot in g.get_tree().get_nodes_in_group(&"crate_spots"):
		c.weapons = g.svc
		if c.active and c.reject_reason(me) == &"" and me.points >= c.cost_for(me) + 300 and _reachable(pos, c.global_position):
			return c
	return null

func _door_goal(me: Player, pos: Vector3) -> BulkheadDoor:
	if me.state != Player.ALIVE:
		return null
	var doors: Array = g.get_tree().get_nodes_in_group(&"doors")
	doors.sort_custom(func(a, b): return a.cost < b.cost)
	for d: BulkheadDoor in doors:
		if d.is_open:
			return null          # one door only: with the later doors open, zombies jam at Door_offices (28, 20) - see the report
	for d: BulkheadDoor in doors:
		if d.is_open or me.points < d.cost:
			continue
		if _reachable(pos, d.global_position):
			return d
	return null

func _damaged_barricade(pos: Vector3) -> Barricade:
	var best: Barricade
	var bd := INF
	for b: Barricade in g.get_tree().get_nodes_in_group(&"barricades"):
		if b.boards >= b.max_boards:
			continue
		var d := pos.distance_to(b.global_position)
		if d < bd:
			bd = d
			best = b
	return best

# ---------------------------------------------------------------- movement helpers

func _clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return g.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _nav_map() -> RID:
	return g.get_world_3d().navigation_map

func _reachable(from: Vector3, to: Vector3) -> bool:
	var p := NavigationServer3D.map_get_path(_nav_map(), from, to, true)
	if p.is_empty():
		return false
	return Vector2(p[p.size() - 1].x - to.x, p[p.size() - 1].z - to.z).length() < 2.4

## Next waypoint towards `goal` along the navigation mesh (re-planned every 0.4 s).
func _steer(pos: Vector3, goal: Vector3) -> Vector3:
	var now := Time.get_ticks_msec() / 1000.0
	if _path.is_empty() or goal.distance_to(_path_goal) > 1.0 or now - _path_t > 0.4:
		_path = NavigationServer3D.map_get_path(_nav_map(), pos, goal, true)
		_path_goal = goal
		_path_t = now
	# string pulling: aim at the furthest of the next waypoints that is in a clear straight line (a bot standing between the two
	# ends of a door's navigation link would otherwise walk back to the link start again and again)
	var best := goal
	var found := false
	var lim := mini(_path.size(), 9)
	for i in lim:
		var p := _path[i]
		if Vector2(p.x - pos.x, p.z - pos.z).length() < 0.7:
			continue
		if not found or _clear(pos + Vector3(0, 0.6, 0), p + Vector3(0, 0.6, 0)):
			best = p
			found = true
		else:
			break
	return best

func _face(f: InputFrame, d: Vector3) -> void:
	f.look_yaw = atan2(-d.x, -d.z)
	f.look_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.4, 1.4)

func _face_dir(f: InputFrame, d: Vector2) -> void:
	f.look_yaw = atan2(-d.x, -d.y)
	f.look_pitch = 0.0

## World (x, z) direction -> frame move vector for the frame's yaw.
func _local_move(f: InputFrame, w: Vector2) -> Vector2:
	var v := Vector3(w.x, 0, w.y).rotated(Vector3.UP, -f.look_yaw)
	return Vector2(v.x, -v.z)

func _unstick(f: InputFrame, pos: Vector3) -> void:
	if f.move.length() > 0.1 and pos.distance_to(_last_pos) < 0.02:
		_stuck_t += 1.0 / 60.0
	else:
		_stuck_t = 0.0
	_last_pos = pos
	if _stuck_t > 1.5:
		f.move.x = _strafe
		if _stuck_t > 3.0:
			_stuck_t = 0.0
			_strafe = -_strafe

func _set_use(on: bool) -> void:
	if on == _using:
		return
	_using = on
	if on:
		Input.action_press(&"use")
	else:
		Input.action_release(&"use")

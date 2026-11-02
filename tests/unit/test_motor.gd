extends TestCase

func _run(buttons: int, secs: float, move := Vector2(0, 1)) -> Dictionary:
	var s := Motor.initial_state(Vector3.ZERO)
	var bal: Balance = Content.balance
	for i in int(round(secs * 60.0)):
		var f := InputFrame.new()
		f.seq = i
		f.move = move
		f.buttons = buttons
		s = Motor.step(s, f, 1.0 / 60.0, null, bal)
	return s

func test_walk_speed() -> void:
	var s := _run(0, 1.0)
	assert_near(Vector2(s.pos.x, s.pos.z).length(), 4.5, 0.05, "walk")

func test_sprint_speed() -> void:
	var s := _run(InputFrame.SPRINT, 1.0)
	assert_near(Vector2(s.pos.x, s.pos.z).length(), 6.8, 0.05, "sprint")

func test_crouch_speed() -> void:
	var s := _run(InputFrame.CROUCH | InputFrame.SPRINT, 1.0)
	assert_near(Vector2(s.pos.x, s.pos.z).length(), 2.2, 0.05, "crouch")

func test_deterministic() -> void:
	var a := _run(InputFrame.JUMP | InputFrame.SPRINT, 2.0, Vector2(0.3, 1))
	var b := _run(InputFrame.JUMP | InputFrame.SPRINT, 2.0, Vector2(0.3, 1))
	assert_eq(a.pos, b.pos)
	assert_eq(a.vy, b.vy)

func test_jump_lands() -> void:
	var s := Motor.initial_state(Vector3.ZERO)
	var f := InputFrame.new()
	f.buttons = InputFrame.JUMP
	var peak := 0.0
	for i in 120:
		s = Motor.step(s, f, 1.0 / 60.0, null, Content.balance)
		peak = maxf(peak, s.pos.y)
		f.buttons = 0
	assert_true(peak > 0.7 and peak < 0.9, "peak %s" % peak)
	assert_true(s.grounded, "landed")
	assert_near(s.pos.y, 0.0, 0.001)

func test_frame_roundtrip() -> void:
	var f := InputFrame.new()
	f.seq = 7; f.move = Vector2(0.3, -0.5); f.look_yaw = 1.5; f.look_pitch = -0.2; f.buttons = 5; f.t = 3.25
	var g := InputFrame.from_array(f.to_array())
	assert_eq(g.seq, 7)
	assert_eq(g.buttons, 5)
	assert_near(g.look_yaw, 1.5, 1e-5)
	assert_near(g.move.x, 0.3, 1e-5)

func test_link_sim_drop_and_delay() -> void:
	var ls := LinkSim.new()
	ls.configure(100.0, 1.0)
	ls.submit(func(): pass)
	assert_eq(ls.pending(), 0, "all dropped")
	ls.configure(100.0, 0.0)
	ls.submit(func(): pass)
	assert_eq(ls.pending(), 1, "queued")
	ls.free()

# ---- _push_out (needs a real physics space: a wall box on layer 1 in the main loop's world)
func _wall(x_face: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1, 3, 10)
	cs.shape = bs
	b.add_child(cs)
	b.position = Vector3(x_face + 0.5, 1.5, 0)
	return b

func _space() -> PhysicsDirectSpaceState3D:
	var tree := Engine.get_main_loop() as SceneTree
	for i in 3:
		await tree.physics_frame
	return tree.root.get_world_3d().direct_space_state

func test_push_out_moves_a_body_off_a_wall() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var w := _wall(0.5)                                  # wall face at x = 0.5
	tree.root.add_child(w)
	var space: PhysicsDirectSpaceState3D = await _space()
	var free_push: Vector3 = Motor._push_out(Vector3(-2, 0, 0), space)
	assert_eq(free_push, Vector3.ZERO, "clear of the wall: no push")
	var push: Vector3 = Motor._push_out(Vector3(0.3, 0, 0), space)      # 0.2 from the face, radius 0.35
	assert_near(push.x, -0.245, 0.005, "pushed back: the 0.15 straight-on overlap plus the two diagonal rays")
	assert_near(push.y, 0.0, 1e-6, "horizontal only")
	assert_near(push.z, 0.0, 0.001, "no sideways push on a flat wall")
	var close: Vector3 = Motor._push_out(Vector3(0.45, 0, 0), space)    # 0.05 from the face: every wall-side ray hits
	assert_near(close.length(), Motor.BODY_RADIUS, 1e-4, "capped at the body radius")
	assert_true(close.x < 0.0, "away from the wall")
	w.free()

func test_step_into_a_wall_never_ends_inside_it() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var w := _wall(2.0)
	tree.root.add_child(w)
	var fl := StaticBody3D.new()
	fl.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(40, 2, 40)
	fcs.shape = fbs
	fl.add_child(fcs)
	fl.position = Vector3(0, -1, 0)
	tree.root.add_child(fl)
	var space: PhysicsDirectSpaceState3D = await _space()
	var s := Motor.initial_state(Vector3.ZERO)
	var f := InputFrame.new()
	f.move = Vector2(1, 0)                               # strafe +x into the wall
	f.look_yaw = 0.0
	for i in 180:
		f.seq = i
		s = Motor.step(s, f, 1.0 / 60.0, space, Content.balance)
	assert_true(s.pos.x <= 2.0 - Motor.BODY_RADIUS + 0.05, "stopped at the wall, x=%f" % s.pos.x)
	assert_true(s.pos.x > 1.0, "and did reach it, x=%f" % s.pos.x)
	w.free()
	fl.free()

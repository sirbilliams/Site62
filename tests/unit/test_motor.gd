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

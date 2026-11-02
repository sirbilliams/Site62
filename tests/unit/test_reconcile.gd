extends TestCase

const DT := 1.0 / 60.0

func _frame(seq: int, fwd := 1.0) -> InputFrame:
	var f := InputFrame.new()
	f.seq = seq
	f.move = Vector2(0, fwd)
	return f

func _local_player() -> Player:
	var p := Player.new()
	p.setup(5, Content.balance, false)
	p.is_local = true               # set after setup so no Camera3D is made
	return p

func _snap(pos: Vector3, ack: int) -> Dictionary:
	return {"pos": pos, "vy": 0.0, "grounded": true, "ack": ack}

func test_reconcile_replays_pending() -> void:
	var p := _local_player()
	for i in 10:
		p.simulate(_frame(i), null, DT, true)
	p.motor_state = Motor.initial_state(Vector3(50, 0, 50))  # perturb
	var host_pos := Vector3(1, 0, -2)
	var expect := Motor.initial_state(host_pos)
	for i in range(5, 10):
		expect = Motor.step(expect, _frame(i), DT, null, Content.balance)
	p.apply_snapshot(_snap(host_pos, 4), null, DT)
	assert_near((p.motor_state.pos as Vector3).distance_to(expect.pos), 0.0, 1e-5, "pos = host + replay")
	assert_eq(p.pending.size(), 5, "pending trimmed")
	assert_eq(p.pending[0].seq, 5, "first pending")
	assert_eq(p.last_ack, 4)
	p.free()

func test_stale_ack_ignored() -> void:
	var p := _local_player()
	for i in 10:
		p.simulate(_frame(i), null, DT, true)
	p.apply_snapshot(_snap(Vector3.ZERO, 6), null, DT)
	var before: Vector3 = p.motor_state.pos
	var n := p.pending.size()
	p.apply_snapshot(_snap(Vector3(99, 0, 99), 3), null, DT)
	assert_eq(p.motor_state.pos, before, "stale ignored")
	assert_eq(p.pending.size(), n)
	assert_eq(p.last_ack, 6)
	p.free()

func test_correction_is_smoothed_visually() -> void:
	var p := _local_player()
	p.simulate(_frame(0, 0.0), null, DT, true)
	p.apply_snapshot(_snap(Vector3(1, 0, 0), 0), null, DT)
	assert_near(p.motor_state.pos.x, 1.0, 1e-4, "motor snaps")
	assert_near(p.position.x, 0.0, 1e-3, "visual stays")
	p._process(0.05)
	assert_true(p.position.x > 0.3 and p.position.x < 0.7, "half blended %s" % p.position.x)
	p._process(0.05)
	assert_near(p.position.x, 1.0, 1e-3, "blended")
	p.free()

func test_from_array_rejects_bad_data() -> void:
	assert_true(InputFrame.from_array([1, 0.0, 1.0, 0.0, 0.0, 0, 0.0]) != null, "good")
	assert_true(InputFrame.from_array([1, NAN, 1.0, 0.0, 0.0, 0, 0.0]) == null, "nan move")
	assert_true(InputFrame.from_array([1, 0.0, 1.0, INF, 0.0, 0, 0.0]) == null, "inf yaw")
	assert_true(InputFrame.from_array([1, 0.0, 1.0, 0.0, NAN, 0, 0.0]) == null, "nan pitch")
	assert_true(InputFrame.from_array([1, "x", 1.0, 0.0, 0.0, 0, 0.0]) == null, "string")
	assert_true(InputFrame.from_array([1, null, 1.0, 0.0, 0.0, 0, 0.0]) == null, "null")
	assert_true(InputFrame.from_array([1, 0.0]) == null, "short")
	assert_true(InputFrame.from_array("nope") == null, "not array")

# ---- host side ----
func _host_net(id: int) -> PlayerNet:
	Net.players.remove(id)
	Net.players.add(id, "")
	var n := PlayerNet.new()
	return n

func _done(n: PlayerNet, id: int) -> void:
	Net.players.remove(id)
	n.free()

func _batch(seqs: Array) -> Array:
	var b: Array = []
	for s in seqs:
		b.append(_frame(s).to_array())
	return b

func test_host_overlap_duplicate_reorder() -> void:
	var n := _host_net(7)
	assert_eq(n._apply_batch(7, _batch([0, 1, 2])), 3)
	assert_eq(n._apply_batch(7, _batch([1, 2, 3])), 1, "overlap")
	assert_eq(n._apply_batch(7, _batch([3, 3, 3])), 0, "duplicates")
	for i in 5:
		n._refill_credit()
	assert_eq(n._apply_batch(7, _batch([6, 4, 5])), 3, "reordered, sorted")
	assert_eq(n._apply_batch(7, _batch([2, 4])), 0, "old")
	assert_eq(n._last_seq[7], 6)
	assert_near((n.players[7].motor_state.pos as Vector3).length(), 7 * 4.5 / 60.0, 0.01, "7 frames applied")
	_done(n, 7)

func test_host_rate_cap() -> void:
	var n := _host_net(8)
	var seqs: Array = []
	for i in 8:
		seqs.append(i)
	var applied := n._apply_batch(8, _batch(seqs))
	assert_eq(applied, int(PlayerNet.CREDIT_MAX), "burst capped at credit")
	assert_eq(n._apply_batch(8, _batch([8, 9, 10])), 0, "no credit left in the same tick")
	n._refill_credit()
	n._refill_credit()
	n._refill_credit()
	n._refill_credit()
	assert_eq(n._apply_batch(8, _batch([8, 9, 10, 11, 12])), 5, "credit refills with host ticks")
	_done(n, 8)

func test_host_seq_jump_and_nan_ignored() -> void:
	var n := _host_net(9)
	n._apply_batch(9, _batch([0]))
	assert_eq(n._apply_batch(9, _batch([0 + PlayerNet.MAX_SEQ_JUMP + 1])), 0, "jump ignored")
	assert_eq(n._last_seq[9], 0)
	assert_eq(n._apply_batch(9, _batch([PlayerNet.MAX_SEQ_JUMP])), 1, "boundary ok")
	var bad := [[5, NAN, 1.0, 0.0, 0.0, 0, 0.0], "junk", 3]
	assert_eq(n._apply_batch(9, bad), 0, "malformed dropped")
	var pos: Vector3 = n.players[9].motor_state.pos
	assert_true(is_finite(pos.x) and is_finite(pos.z), "finite")
	_done(n, 9)

func test_no_ghost_players() -> void:
	var n := PlayerNet.new()
	assert_true(n.ensure_player(12345) == null, "not in roster")
	n.free()

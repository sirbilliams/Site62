extends TestCase

func _xf(x: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))

func test_history_interpolates() -> void:
	var h := HitHistory.new()
	h.record(1.0, 7, _xf(0.0), true)
	h.record(1.1, 7, _xf(2.0), true)
	var p = h.pose_at(7, 1.05)
	assert_true(p != null, "pose")
	assert_near((p as Transform3D).origin.x, 1.0, 1e-4, "midpoint")

func test_history_clamps_old_and_future() -> void:
	var h := HitHistory.new()
	for i in 21:
		h.record(i * 0.1, 3, _xf(float(i)), true)   # 0..2.0 s, only 0.25 s kept
	var old = h.pose_at(3, 2.0 - 1.0)
	assert_true(old != null, "old pose exists")
	var oldest_x: float = (old as Transform3D).origin.x
	assert_true(oldest_x >= 17.0 and oldest_x <= 18.0, "oldest retained, got %s" % oldest_x)
	var fut = h.pose_at(3, 5.0)
	assert_near((fut as Transform3D).origin.x, 20.0, 1e-4, "newest")

func test_no_hit_on_entity_spawned_after_t() -> void:
	var h := HitHistory.new()
	h.record(5.0, 9, _xf(1.0), true)
	h.record(5.1, 9, _xf(2.0), true)
	assert_true(h.pose_at(9, 4.9) == null, "before first record")
	assert_true(h.pose_at(9, 5.0) != null, "at first record")
	assert_true(h.pose_at(404, 5.0) == null, "unknown id")

func test_dead_entity_has_no_pose() -> void:
	var h := HitHistory.new()
	h.record(1.0, 1, _xf(0.0), true)
	h.record(1.1, 1, _xf(0.0), false)
	h.record(1.2, 1, _xf(0.0), false)
	assert_true(h.pose_at(1, 1.0) != null, "alive then")
	assert_true(h.pose_at(1, 1.15) == null, "dead")
	h.forget(1)
	assert_true(h.pose_at(1, 1.0) == null, "forgotten")

extends TestCase

func _run(w: StallWatch, secs: float, pos: Vector3, active := true) -> bool:
	var hit := false
	for i in int(secs * 10.0):
		hit = w.update(0.1, pos, active, 5.0, 0.5) or hit
	return hit

func test_stuck_zombie_trips_after_window() -> void:
	var w := StallWatch.new()
	assert_true(not _run(w, 4.5, Vector3(3, 0, 3)), "not yet")
	assert_true(_run(w, 1.0, Vector3(3, 0, 3)), "5 s without 0.5 m of progress")

func test_moving_zombie_never_trips() -> void:
	var w := StallWatch.new()
	var hit := false
	for i in 300:
		hit = w.update(0.1, Vector3(i * 0.06, 0, 0), true, 5.0, 0.5) or hit      # 0.6 m/s
	assert_true(not hit, "slow but moving")

func test_inactive_resets_the_window() -> void:
	var w := StallWatch.new()
	_run(w, 4.0, Vector3.ZERO)
	_run(w, 3.0, Vector3.ZERO, false)                       # meleeing / tearing: not counted
	assert_true(not _run(w, 4.0, Vector3.ZERO), "window restarted")
	assert_true(_run(w, 1.5, Vector3.ZERO), "and trips 5 s after it restarted")

func test_trip_resets() -> void:
	var w := StallWatch.new()
	assert_true(_run(w, 5.5, Vector3.ZERO), "trips")
	assert_true(not _run(w, 3.0, Vector3.ZERO), "needs a fresh window")

extends TestCase

func test_same_seed_same_offset() -> void:
	var a := Spread.offset_dir(Vector3(0, 0, -1), 3.0, 4242, 17)
	var b := Spread.offset_dir(Vector3(0, 0, -1), 3.0, 4242, 17)
	assert_true(a.is_equal_approx(b), "same (id, seq)")
	var c := Spread.offset_dir(Vector3(0, 0, -1), 3.0, 4242, 18)
	assert_true(not a.is_equal_approx(c), "different seq differs")
	var d := Spread.offset_dir(Vector3(0, 0, -1), 3.0, 99, 17)
	assert_true(not a.is_equal_approx(d), "different shooter differs")

func test_offset_inside_cone() -> void:
	for i in 300:
		var dir := Vector3(0.3, 0.2, -1).normalized()
		var o := Spread.offset_dir(dir, 2.5, 7, i)
		assert_true(rad_to_deg(dir.angle_to(o)) <= 2.5 + 1e-3, "inside cone seq %d" % i)
		assert_near(o.length(), 1.0, 1e-4, "unit")

func test_ads_cone_narrower() -> void:
	var w := Content.weapon(&"sentinel_45")
	assert_true(Spread.cone_deg(w, true) < Spread.cone_deg(w, false), "ads narrower")
	var worst_ads := 0.0
	var worst_hip := 0.0
	for i in 300:
		worst_ads = maxf(worst_ads, Vector3(0, 0, -1).angle_to(Spread.offset_dir(Vector3(0, 0, -1), Spread.cone_deg(w, true), 1, i)))
		worst_hip = maxf(worst_hip, Vector3(0, 0, -1).angle_to(Spread.offset_dir(Vector3(0, 0, -1), Spread.cone_deg(w, false), 1, i)))
	assert_true(worst_ads < worst_hip, "ads worst case tighter")

func test_recoil_pattern_advances_and_resets() -> void:
	var r := Recoil.new(PackedVector2Array([Vector2(0.0, 1.2), Vector2(0.2, 1.0)]))
	assert_eq(r.kick(0.0), Vector2(0.0, 1.2), "first")
	assert_eq(r.kick(0.1), Vector2(0.2, 1.0), "second")
	assert_eq(r.kick(0.2), Vector2(0.2, 1.0), "last repeats")
	assert_eq(r.kick(5.0), Vector2(0.0, 1.2), "burst reset")

func test_recoil_recovers() -> void:
	var r := Recoil.new(PackedVector2Array([Vector2(0.0, 1.2)]))
	r.kick(0.0)
	var back := Vector2.ZERO
	for i in 60:
		back += r.recover(1.0 / 60.0)
	assert_near(back.y, 1.2, 1e-4, "all recovered")
	assert_eq(r.accum, Vector2.ZERO, "settled")

extends TestCase

func _target(z: float, svc: WeaponService, id: int, alive: bool) -> HitTarget:
	var t := HitTarget.new()
	t.add_box(Vector3(0, 0.8, 0), Vector3(1, 1.6, 1))
	t.alive = alive
	svc.register_target(id, t)
	svc.history.record(1.0, id, Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), alive)
	return t

func test_shot_through_corpse_hits_live_zombie_behind() -> void:
	var svc := WeaponService.new()
	var corpse := _target(-5.0, svc, -1, false)
	var live := _target(-10.0, svc, -2, true)
	var r := svc.pick_target(Vector3(0, 0.8, 0), Vector3(0, 0, -1), 1.0)
	assert_true(r.found, "found")
	assert_eq(r.id, -2, "the live zombie, not the corpse")
	corpse.free(); live.free(); svc.free()

func test_only_corpse_is_a_miss() -> void:
	var svc := WeaponService.new()
	var corpse := _target(-5.0, svc, -1, false)
	assert_true(not svc.pick_target(Vector3(0, 0.8, 0), Vector3(0, 0, -1), 1.0).found, "miss")
	corpse.free(); svc.free()

extends TestCase

func test_swap_flood_bounded_replies() -> void:
	# The token bucket that gates request_swap: a flood of 200 requests yields at most BUCKET_MAX + a refill trickle.
	var svc := WeaponService.new()
	var granted := 0
	for i in 200:
		if svc._take_token(7):
			granted += 1
	assert_true(granted <= int(WeaponService.BUCKET_MAX) + 2, "granted %d" % granted)
	svc._forget_peer(7)
	assert_true(not svc._bucket.has(7), "forgotten on leave")
	svc.free()

func test_forget_peer_clears_state() -> void:
	var svc := WeaponService.new()
	svc.kit_for(5)
	svc._melees[5] = Melee.new()
	svc._next_throw[5] = 1.0
	svc._swap_count[5] = 2
	svc._next_seq(5)
	svc._forget_peer(5)
	for d in [svc.kits, svc._melees, svc._next_throw, svc._swap_count, svc._counters, svc._bucket]:
		assert_true(not d.has(5), "erased")
	svc.free()

func test_set_weapon_refuses_duplicate() -> void:
	var svc := WeaponService.new()
	assert_true(not svc.set_weapon(3, &"sentinel_45"), "already held")
	assert_true(svc.set_weapon(3, &"hornet"), "new gun")
	assert_true(not svc.set_weapon(3, &"hornet"), "duplicate")
	svc.free()

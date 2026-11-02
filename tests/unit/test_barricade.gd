extends TestCase

func test_barricade_tear_and_repair() -> void:
	var b := Barricade.new()
	assert_eq(b.boards, 6)
	assert_true(not b.link.enabled, "closed barricade: link off")
	for i in 6:
		assert_true(b.tear_one(), "tear %d" % i)
	assert_eq(b.boards, 0)
	assert_true(b.link.enabled, "open barricade: link on")
	assert_true(not b.tear_one(), "nothing left to tear")
	var got := []
	b.board_repaired.connect(func(by): got.append(by))
	assert_true(b.repair_one(7), "repair")
	assert_eq(b.boards, 1)
	assert_eq(got, [7])
	assert_true(not b.link.enabled, "one board closes the link")
	b.free()

func test_repair_full_fails() -> void:
	var b := Barricade.new()
	var got := []
	b.board_repaired.connect(func(by): got.append(by))
	assert_true(not b.repair_one(1), "full barricade refuses")
	assert_eq(b.boards, 6)
	assert_eq(got.size(), 0)
	b.free()

func test_tear_claim_single_tearer() -> void:
	var b := Barricade.new()
	assert_true(b.try_claim(1), "first claims")
	assert_true(b.try_claim(1), "holder keeps")
	assert_true(not b.try_claim(2), "second waits")
	b.release(1)
	assert_true(b.try_claim(2), "free after release")
	b.free()

func test_outside_side() -> void:
	var b := Barricade.new()
	b.position = Vector3(0, 0, 0)
	assert_true(b.is_outside(Vector3(0, 0, 3)), "+z is outside")
	assert_true(not b.is_outside(Vector3(0, 0, -3)), "-z is inside")
	b.free()

func test_zombie_chasing_outside_player_never_tears() -> void:
	var b := Barricade.new()
	var z := Vector3(0.5, 0, 1.5)          # outside, within tearing reach
	assert_true(ZombieBrain.wants_tear(b, z, Vector3(0, 0, -10)), "target behind the wall: tear")
	assert_true(not ZombieBrain.wants_tear(b, z, Vector3(8, 0, 6)), "target outside: walk past")
	assert_true(not ZombieBrain.wants_tear(b, Vector3(0, 0, -3), Vector3(0, 0, -10)), "already inside")
	assert_true(not ZombieBrain.wants_tear(b, Vector3(0, 0, 9), Vector3(0, 0, -10)), "out of reach")
	for i in 6:
		b.tear_one()
	assert_true(not ZombieBrain.wants_tear(b, z, Vector3(0, 0, -10)), "open: nothing to tear")
	b.free()

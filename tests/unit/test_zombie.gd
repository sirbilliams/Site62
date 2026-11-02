extends TestCase

func _z(hp := 100.0) -> Zombie:
	var z := Zombie.new()
	z.setup(5, Content.enemies[&"shambler"], hp, 1, false)
	return z

func test_hit_id_never_collides_with_peers() -> void:
	assert_true(Zombie.hit_id(5) < 0, "negative range")
	assert_eq(Zombie.zid_of(Zombie.hit_id(5)), 5)

func test_take_damage_kills_once() -> void:
	var z := _z(100.0)
	var got := []
	z.died.connect(func(zid, killer, head, melee, pos): got.append([zid, killer, head, melee]))
	z.take_damage(60.0, 3, false)
	assert_true(z.alive, "still alive")
	z.take_damage(60.0, 3, true)
	z.take_damage(60.0, 4, false)
	assert_true(not z.alive, "dead")
	assert_eq(got, [[5, 3, true, false]])
	z.free()

func test_hitboxes_head_above_body() -> void:
	var z := _z()
	var xf := Transform3D(Basis.IDENTITY, Vector3(0, 0, -10))
	var head := z.ray_at(xf, Vector3(0, 1.8, 0), Vector3(0, 0, -1))
	var body := z.ray_at(xf, Vector3(0, 0.6, 0), Vector3(0, 0, -1))
	assert_true(not head.is_empty() and head.head, "head ray")
	assert_true(not body.is_empty() and not body.head, "body ray")
	z.free()

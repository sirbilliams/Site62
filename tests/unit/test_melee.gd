extends TestCase

const EYE := Vector3(0, 1.6, 0)
const FWD := Vector3(0, 0, -1)

func test_cone_and_range() -> void:
	var r := 1.6
	var c := 45.0
	assert_true(Melee.in_reach(EYE, FWD, Vector3(0, 1.4, -1.0), r, c), "in front")
	assert_true(not Melee.in_reach(EYE, FWD, Vector3(0, 1.4, -1.7), r, c), "too far")
	assert_true(not Melee.in_reach(EYE, FWD, Vector3(0, 1.4, 1.0), r, c), "behind")
	assert_true(not Melee.in_reach(EYE, FWD, Vector3(1.0, 1.6, -0.5), r, c), "outside the cone")
	assert_true(Melee.in_reach(EYE, FWD, Vector3(0.5, 1.6, -1.0), r, c), "26 degrees off")

func test_pick_nearest() -> void:
	var cands := [
		{"id": -1, "points": [Vector3(0, 1.0, -1.5)]},
		{"id": -2, "points": [Vector3(0, 1.0, -0.8)]},
		{"id": -3, "points": [Vector3(0, 1.0, -4.0)]}]
	assert_eq(Melee.pick(EYE, FWD, cands, 1.6, 45.0, Callable()), -2, "nearest in reach")
	assert_eq(Melee.pick(EYE, FWD, [cands[2]], 1.6, 45.0, Callable()), 0, "none in reach")

func test_wall_blocks() -> void:
	var cands := [{"id": -1, "points": [Vector3(0, 1.0, -0.8)]}, {"id": -2, "points": [Vector3(0, 1.0, -1.4)]}]
	var blocked := func(_from: Vector3, to: Vector3): return to.z > -1.0
	assert_eq(Melee.pick(EYE, FWD, cands, 1.6, 45.0, blocked), -2, "near one behind a wall is skipped")

func test_cooldown() -> void:
	var m := Melee.new()
	assert_true(m.ready(0.0, 0.7), "first swing")
	m.swing(0.0)
	assert_true(not m.ready(0.5, 0.7), "cooling down")
	assert_true(m.ready(0.7, 0.7), "ready again")
	assert_true(m.ready(0.66, 0.7, 0.1), "tolerance")

func test_grenade_falloff() -> void:
	var d := Content.throwable(&"frag")
	assert_near(Grenade.damage_at(0.0, d), 300.0, 1e-3, "centre")
	assert_near(Grenade.damage_at(2.5, d), 150.0, 1e-3, "half radius")
	assert_near(Grenade.damage_at(5.0, d), 0.0, 1e-3, "edge")
	assert_near(Grenade.damage_at(6.0, d), 0.0, 1e-3, "outside")

func test_grenade_blast_wall_block() -> void:
	var d := Content.throwable(&"frag")
	var targets := [
		{"id": -1, "pos": Vector3(1, 0, 0)},
		{"id": -2, "pos": Vector3(0, 0, 2)},       # behind the wall
		{"id": -3, "pos": Vector3(6, 0, 0)}]       # out of range
	var wall := func(_from: Vector3, to: Vector3): return to.z > 1.0
	var out := Grenade.blast(Vector3.ZERO, targets, d, wall)
	assert_eq(out.size(), 1, "only the open one")
	assert_eq(out[0].id, -1, "id")
	assert_near(out[0].dmg, 240.0, 1e-3, "linear falloff")

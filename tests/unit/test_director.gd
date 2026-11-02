extends TestCase

class Spawner:
	var count := 0
	var zones: Array = []
	var last_health := 0
	var last_band := -1
	func on_spawn(zone, health: int, band: int) -> void:
		count += 1
		zones.append(zone)
		last_health = health
		last_band = band

class Counter:
	var n := 1
	func get_n() -> int:
		return n

func _zone(id: StringName, active: bool) -> SpawnZone:
	var z := SpawnZone.new()
	z.zone_id = id
	z.active = active
	return z

func _curve(interval := 0.1) -> RoundCurve:
	var c := RoundCurve.new()
	c.spawn_base_s = interval
	c.spawn_step_s = 0.0
	c.spawn_min_s = interval
	c.break_s = 10.0
	return c

func _make(curve: RoundCurve, zones: Array[SpawnZone], players := 1) -> Array:
	var d := RoundDirector.new()
	var sp := Spawner.new()
	var ctr := Counter.new()
	ctr.n = players
	d.set_curve(curve)
	d.set_zones(zones)
	d.set_player_count_provider(Callable(ctr, "get_n"))
	d.spawn_requested.connect(sp.on_spawn)
	return [d, sp, ctr]

func test_round1_spawns_count() -> void:
	var zs: Array[SpawnZone] = [_zone(&"a", true)]
	var m := _make(_curve(), zs)
	var d: RoundDirector = m[0]
	var sp: Spawner = m[1]
	d.start_match()
	assert_eq(d.remaining, 8, "round1 1 player queue")
	for i in 100:
		d.tick(0.1)
	assert_eq(sp.count, 8, "round1 spawns 8")
	assert_eq(d.alive, 8, "alive 8")

func test_spawn_pacing() -> void:
	var zs: Array[SpawnZone] = [_zone(&"a", true)]
	var m := _make(_curve(2.0), zs)
	var d: RoundDirector = m[0]
	var sp: Spawner = m[1]
	d.start_match()
	d.tick(0.1)
	assert_eq(sp.count, 1, "immediate first spawn")
	for i in 18:
		d.tick(0.1)  # t=1.9
	assert_eq(sp.count, 1, "no spawn before interval")
	for i in 3:
		d.tick(0.1)  # t=2.2
	assert_eq(sp.count, 2, "spawn after interval")
	for i in 20:
		d.tick(0.1)  # t=4.2
	assert_eq(sp.count, 3, "third spawn at 4s")

func test_alive_cap_40() -> void:
	var zs: Array[SpawnZone] = [_zone(&"a", true)]
	var m := _make(_curve(), zs)
	var d: RoundDirector = m[0]
	var sp: Spawner = m[1]
	d.start_match()
	d.remaining = 60
	for i in 2000:
		d.tick(0.1)
	assert_eq(sp.count, 40, "exactly 40 spawned")
	assert_eq(d.alive, 40, "alive 40")
	assert_eq(d.remaining, 20, "20 queued")
	d.on_zombie_died()
	d.on_zombie_died()
	for i in 20:
		d.tick(0.1)
	assert_eq(sp.count, 42, "queued spawn as slots free")
	assert_eq(d.alive, 40, "alive back to 40")

func test_spawns_only_active_zones() -> void:
	var off := _zone(&"off", false)
	var on := _zone(&"on", true)
	var zs: Array[SpawnZone] = [off, on]
	var m := _make(_curve(), zs)
	var d: RoundDirector = m[0]
	var sp: Spawner = m[1]
	d.start_match()
	for i in 100:
		d.tick(0.1)
	assert_true(sp.count > 0, "spawned something")
	for z in sp.zones:
		assert_true(z == on, "only active zone used")
	var zs2: Array[SpawnZone] = [_zone(&"x", false)]
	var m2 := _make(_curve(), zs2)
	m2[0].start_match()
	for i in 50:
		m2[0].tick(0.1)
	assert_eq(m2[1].count, 0, "no active zones, no spawns")

func test_break_then_next_round() -> void:
	var zs: Array[SpawnZone] = [_zone(&"a", true)]
	var m := _make(_curve(), zs)
	var d: RoundDirector = m[0]
	var sp: Spawner = m[1]
	d.start_match()
	d.remaining = 1
	d.tick(0.1)
	assert_eq(sp.count, 1, "spawned last")
	d.on_zombie_died()
	assert_eq(d.round, 1)
	d.tick(9.8)
	assert_eq(d.round, 1, "still in break at 9.8s")
	d.tick(0.3)
	assert_eq(d.round, 2, "next round after 10s")

func test_health_and_band_per_round() -> void:
	var zs: Array[SpawnZone] = [_zone(&"a", true)]
	var c := _curve()
	var m := _make(c, zs)
	var d: RoundDirector = m[0]
	var sp: Spawner = m[1]
	d.start_match()
	d.tick(0.1)
	assert_eq(sp.last_health, c.health(1), "r1 health")
	assert_eq(sp.last_band, c.speed_band(1), "r1 band")
	d._start_round(9)
	d.tick(0.1)
	assert_eq(sp.last_health, c.health(9), "r9 health")
	assert_eq(sp.last_band, c.speed_band(9), "r9 band")

func test_player_count_read_each_round() -> void:
	var zs: Array[SpawnZone] = [_zone(&"a", true)]
	var c := _curve()
	var m := _make(c, zs, 1)
	var d: RoundDirector = m[0]
	var ctr: Counter = m[2]
	d.start_match()
	assert_eq(d.remaining, c.count(1, 1), "round1 with 1 player")
	ctr.n = 3
	assert_eq(d.remaining, c.count(1, 1), "mid-round change ignored")
	d._start_round(2)
	assert_eq(d.remaining, c.count(2, 3), "round2 with 3 players")
	assert_true(c.count(2, 3) != c.count(2, 1), "counts differ")

extends TestCase

class FakeSpawner:
	var spawn_count: int = 0
	var last_zone: SpawnZone
	var last_health: int = 0
	var last_band: int = 0
	
	func _on_spawn_requested(zone: SpawnZone, health: int, band: int) -> void:
		spawn_count += 1
		last_zone = zone
		last_health = health
		last_band = band

class FakeHealthSpawner:
	var last_health: int = 0
	var last_band: int = 0
	
	func _on_spawn_requested(zone: SpawnZone, health: int, band: int) -> void:
		last_health = health
		last_band = band

func _create_spawn_zone(id: StringName, active: bool) -> SpawnZone:
	var zone := SpawnZone.new()
	zone.zone_id = id
	zone.active = active
	return zone

func test_round1_spawns_count() -> void:
	var curve := RoundCurve.new()
	curve.base_count = 5
	curve.count_per_round = 3
	curve.coop_count_bonus = 0.5
	curve.break_s = 10.0
	
	var zone_a := _create_spawn_zone(&"zone_a", true)
	var zone_b := _create_spawn_zone(&"zone_b", true)
	var zones: Array[SpawnZone] = [zone_a, zone_b]
	
	var director := RoundDirector.new()
	director.set_curve(curve)
	director.set_zones(zones)
	director._player_count = 1
	director._start_round(1)
	
	assert_eq(director.remaining, 8, "Round 1 with 1 player should give 8 zombies")
	assert_eq(director.round, 1)

func test_alive_cap_40() -> void:
	var curve := RoundCurve.new()
	curve.base_count = 5
	curve.count_per_round = 3
	curve.coop_count_bonus = 0.5
	curve.base_health = 120
	curve.health_per_round = 80
	curve.linear_health_until = 10
	curve.health_growth = 1.08
	curve.spawn_base_s = 0.1
	curve.spawn_step_s = 0.0
	curve.spawn_min_s = 0.0
	curve.break_s = 10.0
	
	var zone_a := _create_spawn_zone(&"zone_a", true)
	var zones: Array[SpawnZone] = [zone_a]
	
	var director := RoundDirector.new()
	director.set_curve(curve)
	director.set_zones(zones)
	director._player_count = 1
	director._start_round(30)
	
	director._zombies_remaining = 60
	director.remaining = 60
	
	for i in 60:
		if director._zombies_remaining > 0:
			director._spawn_zombie()
	
	assert_eq(director.alive, 40, "Alive should be capped at 40")
	assert_true(director.alive <= 40, "Alive never exceeds 40")

func test_spawns_only_open_zones() -> void:
	var curve := RoundCurve.new()
	curve.base_count = 5
	curve.count_per_round = 3
	curve.coop_count_bonus = 0.5
	curve.break_s = 10.0
	curve.spawn_base_s = 0.1
	curve.spawn_step_s = 0.0
	curve.spawn_min_s = 0.0
	
	var zone_a := _create_spawn_zone(&"zone_a", false)
	var zone_b := _create_spawn_zone(&"zone_b", false)
	var zones: Array[SpawnZone] = [zone_a, zone_b]
	
	var spawner := FakeSpawner.new()
	
	var director := RoundDirector.new()
	director.set_curve(curve)
	director.set_zones(zones)
	director._player_count = 1
	director.connect("spawn_requested", Callable(spawner, "_on_spawn_requested"))
	director._start_round(5)
	
	director.tick(10.0)
	
	assert_eq(spawner.spawn_count, 0, "No spawns when no zones are active")

func test_break_then_next_round() -> void:
	var curve := RoundCurve.new()
	curve.base_count = 5
	curve.count_per_round = 3
	curve.coop_count_bonus = 0.5
	curve.base_health = 120
	curve.health_per_round = 80
	curve.linear_health_until = 10
	curve.health_growth = 1.08
	curve.spawn_base_s = 0.1
	curve.spawn_step_s = 0.0
	curve.spawn_min_s = 0.0
	curve.break_s = 10.0
	
	var zone_a := _create_spawn_zone(&"zone_a", true)
	var zones: Array[SpawnZone] = [zone_a]
	
	var director := RoundDirector.new()
	director.set_curve(curve)
	director.set_zones(zones)
	director._player_count = 1
	director._start_round(1)
	
	director._zombies_remaining = 1
	director.remaining = 1
	director.tick(0.1)
	director.on_zombie_died()
	assert_eq(director.alive, 0, "Last zombie died")
	director.tick(10.0)
	assert_true(director._break_deadline > 0, "Break active")
	director.tick(10.0)
	assert_eq(director.round, 2, "Next round starts 10s after last death")

func test_health_per_round() -> void:
	var curve := RoundCurve.new()
	curve.base_count = 5
	curve.count_per_round = 3
	curve.coop_count_bonus = 0.5
	curve.base_health = 120
	curve.health_per_round = 80
	curve.linear_health_until = 10
	curve.health_growth = 1.08
	curve.spawn_base_s = 0.1
	curve.spawn_step_s = 0.0
	curve.spawn_min_s = 0.0
	curve.break_s = 10.0
	
	var zone_a := _create_spawn_zone(&"zone_a", true)
	var zones: Array[SpawnZone] = [zone_a]
	
	var spawner := FakeHealthSpawner.new()
	
	var director := RoundDirector.new()
	director.set_curve(curve)
	director.set_zones(zones)
	director._player_count = 1
	
	director.connect("spawn_requested", Callable(spawner, "_on_spawn_requested"))
	director._start_round(1)
	
	director._spawn_zombie()
	
	assert_eq(spawner.last_health, 120, "Health should equal curve.health(r) for round 1")

extends SceneTree
# stress: random zombies in/near the Door_offices doorway, random static target either side; who never arrives?
func _initialize() -> void:
	var map = (load("res://maps/site62/site62.tscn") as PackedScene).instantiate()
	root.add_child(map)
	var door = map.get_node("Door_offices")
	var ZS = load("res://enemies/zombie.gd")
	var P = load("res://player/player.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	door.set_open(true)
	for i in 30: await physics_frame
	var fails := 0
	var trials := 0
	for batch in 6:
		var tz: Vector3 = [Vector3(28, 0.2, 12.0), Vector3(28, 0.2, 30.0), Vector3(27.2, 0.2, 20.0), Vector3(28.8, 0.2, 20.3), Vector3(28, 0.2, 18.5), Vector3(28, 0.2, 23.0)][batch]
		var p = P.new()
		p.set_physics_process(false)
		p.position = tz
		root.add_child(p)
		var zs := []
		for i in 12:
			var z = ZS.new()
			z.setup(i + 1, root.get_node("Content").enemies[&"shambler"], 100.0, rng.randi() % 3, true)
			z.position = Vector3(rng.randf_range(26.4, 29.6), 0.2, rng.randf_range(16.5, 23.5))
			root.add_child(z)
			z.brain._repath_in = rng.randf() * 0.5
			zs.append(z)
		var players := {1: p}
		for i in 1200:
			await physics_frame
			p.hp = 100.0
			for z in zs:
				z.brain.tick(1.0 / 60.0, players, [], [door])
		var s := ""
		for z in zs:
			trials += 1
			var d := Vector2(z.position.x - tz.x, z.position.z - tz.z).length()
			if d > 1.6:
				fails += 1
				s += " (%.1f,%.1f d=%.1f b%d)" % [z.position.x, z.position.z, d, z.band]
		print("batch ", batch, " target ", tz, " unreached:", s)
		p.queue_free()
		for z in zs: z.queue_free()
		await physics_frame
	print("FAILS ", fails, "/", trials)
	quit()

extends TestCase

func _setup(n := 2) -> EconomyService:
	var e := EconomyService.new()
	e.weapons = WeaponService.new()
	for i in n:
		var p := Player.new()
		p.peer_id = i + 1
		e.players[i + 1] = p
	return e

func _free(e: EconomyService) -> void:
	for p in e.players.values():
		p.free()
	e.weapons.free()
	e.free()

func test_door_opens_and_zone() -> void:
	var e := _setup()
	var z := Zone.new()
	z.zone_id = &"lab"
	var d := BulkheadDoor.new()
	d.cost = 800
	d.unlocks = [&"lab"]
	e.wallet(1).points = 1000
	var r := e.handle_use(1, d, Vector3.ZERO)
	d.unlock([z])                       # the tree lookup in use() needs a scene tree
	assert_eq(r, &"", "door bought")
	assert_true(d.is_open, "open")
	assert_true(z.open, "zone opened")
	assert_eq(e.wallet(1).points, 200)
	z.free(); d.free()
	_free(e)

func test_same_frame_door_contention() -> void:
	var e := _setup()
	var d := BulkheadDoor.new()
	d.cost = 800
	e.wallet(1).points = 1000
	e.wallet(2).points = 1000
	var bought := []
	e.purchase.connect(func(p, what, cost): bought.append([p, what, cost]))
	var r1 := e.handle_use(1, d, Vector3.ZERO)      # two requests, same frame, arrival order
	var r2 := e.handle_use(2, d, Vector3.ZERO)
	assert_eq(r1, &"", "first buyer gets the door")
	assert_eq(r2, &"already_open", "second is told it is open")
	assert_eq(e.wallet(1).points, 200)
	assert_eq(e.wallet(2).points, 1000, "second keeps their points")
	assert_eq(bought.size(), 1, "exactly one purchase")
	d.free()
	_free(e)

func test_door_not_enough_points() -> void:
	var e := _setup()
	var d := BulkheadDoor.new()
	d.cost = 800
	assert_eq(e.handle_use(1, d, Vector3.ZERO), &"points")
	assert_true(not d.is_open)
	assert_eq(e.wallet(1).points, Content.balance.start_points)
	d.free()
	_free(e)

func test_range_and_unknown_player() -> void:
	var e := _setup()
	var d := BulkheadDoor.new()
	d.cost = 100
	d.position = Vector3(5, 0, 0)
	assert_eq(e.handle_use(1, d, Vector3.ZERO), &"far", "5 m away")
	assert_true(not d.is_open)
	assert_eq(e.handle_use(1, d, Vector3(4, 0, 0)), &"", "1 m away")
	assert_eq(e.handle_use(77, d, Vector3(4, 0, 0)), &"player", "not a player")
	d.free()
	_free(e)

func test_wall_buy_weapon_then_ammo() -> void:
	var e := _setup()
	var w := WallBuy.new()
	w.weapon_id = &"hornet"
	e.wallet(1).points = 1600
	assert_eq(w.cost_for(e.players[1]), Content.weapon(&"hornet").cost, "not owned: full price")
	assert_eq(e.handle_use(1, w, Vector3.ZERO), &"", "buy the gun")
	assert_eq(e.wallet(1).points, 500)
	assert_eq(e.weapons.state_for(1).data.id, &"hornet")
	assert_eq(e.handle_use(1, w, Vector3.ZERO), &"ammo_full", "full: nothing to buy")
	assert_eq(e.wallet(1).points, 500, "refused: no charge")
	var st := e.weapons.state_for(1)
	st.mag = 0
	st.reserve = 0
	assert_eq(w.cost_for(e.players[1]), st.data.ammo_cost, "owning it: ammo price")
	assert_eq(e.handle_use(1, w, Vector3.ZERO), &"", "buy ammo")
	assert_eq(e.wallet(1).points, 60)
	assert_eq(st.mag, st.data.mag)
	assert_eq(st.reserve, st.data.reserve)
	w.free()
	_free(e)

func test_wall_buy_rejects_non_wall_weapon() -> void:
	var e := _setup()
	var w := WallBuy.new()
	w.weapon_id = &"cathode_carbine"
	assert_eq(e.handle_use(1, w, Vector3.ZERO), &"invalid")
	w.free()
	_free(e)

func test_hit_on_dead_or_gone_zombie_pays_nothing() -> void:
	var e := _setup()
	var zs := ZombieSync.new()
	e.zombies_sync = zs
	var z := Zombie.new()
	zs.zombies[5] = z
	e.wallet(1).points = 0
	e.on_hit(1, Zombie.hit_id(5), 10.0, false)
	assert_eq(e.wallet(1).points, 5, "live zombie pays")
	z.alive = false
	e.on_hit(1, Zombie.hit_id(5), 10.0, false)
	assert_eq(e.wallet(1).points, 5, "corpse pays nothing")
	e.on_hit(1, Zombie.hit_id(6), 10.0, false)
	assert_eq(e.wallet(1).points, 5, "despawned zombie pays nothing")
	z.free(); zs.free()
	_free(e)

func test_use_flood_limit() -> void:
	var e := _setup()
	assert_true(e.use_allowed(1, 1000), "first")
	assert_true(not e.use_allowed(1, 1050), "50 ms later: dropped")
	assert_true(e.use_allowed(2, 1050), "other peer unaffected")
	assert_true(e.use_allowed(1, 1100), "100 ms later")
	_free(e)

func test_bind_wiring_with_real_signals() -> void:
	var e := _setup()
	var pn := PlayerNet.new()
	var zs := ZombieSync.new()
	var old: Array = e.players.values()
	e.bind(pn, e.weapons, zs)
	var p: Player = Player.new()
	p.peer_id = 3
	pn.players[3] = p
	assert_true(e.players.has(3), "players shared with PlayerNet")
	var z := Zombie.new()
	zs.zombies[9] = z
	e.wallet(3).points = 0
	e.weapons.hit.emit(3, Zombie.hit_id(9), 20.0, false)
	assert_eq(e.wallet(3).points, 5, "hit")
	zs.zombie_died.emit(9, 3, true, false, Vector3.ZERO)
	assert_eq(e.wallet(3).points, 85, "killing headshot: hit + kill + bonus")
	var b := Barricade.new()
	e.hook_barricade(b)
	b.tear_one()
	b.repair_one(3)
	assert_eq(e.wallet(3).points, 100, "board")
	Net.player_left.emit(3)
	assert_true(not e.wallets.has(3), "wallet dropped on leave")
	for o in old:
		o.free()
	b.free(); z.free(); pn.free(); zs.free()
	_free(e)           # frees p through the shared players dict

func test_wall_buy_two_slots() -> void:
	var e := _setup()
	var h := WallBuy.new()
	h.weapon_id = &"hornet"
	var g := WallBuy.new()
	g.weapon_id = &"garand_k"
	var s := WallBuy.new()
	s.weapon_id = &"sentinel_45"
	e.wallet(1).points = 5000
	var kit := e.weapons.kit_for(1)
	assert_eq(e.handle_use(1, h, Vector3.ZERO), &"", "hornet into the empty slot")
	assert_eq(kit.slots[0].data.id, &"sentinel_45", "start gun kept")
	assert_eq(kit.slots[1].data.id, &"hornet", "slot 1")
	assert_eq(e.handle_use(1, g, Vector3.ZERO), &"", "third gun replaces the held one")
	assert_eq(kit.slots[1].data.id, &"garand_k", "held slot replaced")
	assert_eq(kit.slots[0].data.id, &"sentinel_45", "other slot kept")
	kit.slots[0].mag = 0
	kit.slots[0].reserve = 0
	s.weapons = e.weapons
	assert_eq(s.cost_for(e.players[1]), Content.weapon(&"sentinel_45").ammo_cost, "ammo price for the gun in the other slot")
	assert_eq(e.handle_use(1, s, Vector3.ZERO), &"", "ammo for the NOT held gun")
	assert_eq(kit.slots[0].mag, kit.slots[0].data.mag, "refilled in its slot")
	assert_eq(kit.held, 1, "held unchanged")
	assert_eq(kit.slots[1].data.id, &"garand_k", "held gun untouched")
	h.free(); g.free(); s.free()
	_free(e)

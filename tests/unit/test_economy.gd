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
	d.cost = 750
	d.unlocks = [&"lab"]
	e.wallet(1).points = 1000
	var r := e.handle_use(1, d, Vector3.ZERO)
	d.unlock([z])                       # the tree lookup in use() needs a scene tree
	assert_eq(r, &"", "door bought")
	assert_true(d.is_open, "open")
	assert_true(z.open, "zone opened")
	assert_eq(e.wallet(1).points, 250)
	z.free(); d.free()
	_free(e)

func test_same_frame_door_contention() -> void:
	var e := _setup()
	var d := BulkheadDoor.new()
	d.cost = 750
	e.wallet(1).points = 1000
	e.wallet(2).points = 1000
	var bought := []
	e.purchase.connect(func(p, what, cost): bought.append([p, what, cost]))
	var r1 := e.handle_use(1, d, Vector3.ZERO)      # two requests, same frame, arrival order
	var r2 := e.handle_use(2, d, Vector3.ZERO)
	assert_eq(r1, &"", "first buyer gets the door")
	assert_eq(r2, &"already_open", "second is told it is open")
	assert_eq(e.wallet(1).points, 250)
	assert_eq(e.wallet(2).points, 1000, "second keeps their points")
	assert_eq(bought.size(), 1, "exactly one purchase")
	d.free()
	_free(e)

func test_door_not_enough_points() -> void:
	var e := _setup()
	var d := BulkheadDoor.new()
	d.cost = 750
	assert_eq(e.handle_use(1, d, Vector3.ZERO), &"points")
	assert_true(not d.is_open)
	assert_eq(e.wallet(1).points, 500)
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
	e.wallet(1).points = 1500
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
	assert_eq(e.wallet(1).points, 0)
	assert_eq(st.mag, st.data.mag)
	assert_eq(st.reserve, st.data.reserve)
	w.free()
	_free(e)

func test_wall_buy_rejects_non_wall_weapon() -> void:
	var e := _setup()
	var w := WallBuy.new()
	w.weapon_id = &"ray_lancer"
	assert_eq(e.handle_use(1, w, Vector3.ZERO), &"invalid")
	w.free()
	_free(e)

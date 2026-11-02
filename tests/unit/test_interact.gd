extends TestCase

class Thing extends Interactable:
	var used := 0
	var label := "Thing"
	func prompt(_p: Player) -> String:
		return label
	func use(_p: Player) -> bool:
		used += 1
		return true

func _rig() -> Dictionary:
	await Engine.get_main_loop().process_frame           # the root joins the tree after _initialize
	var root: Node = Engine.get_main_loop().root
	var net := PlayerNet.new()
	var me := Player.new()
	me.peer_id = 1
	net.players[1] = me
	var eco := EconomyService.new()
	eco.players = net.players
	eco.weapons = WeaponService.new()
	eco.wallet(1).points = 5000
	var ic := InteractController.new()
	ic.bind(net, eco, eco.weapons, null)
	for n in [net, eco, ic, eco.weapons]:
		root.add_child(n)
	root.add_child(me)
	return {"net": net, "me": me, "eco": eco, "ic": ic, "root": root}

func _drop(r: Dictionary, extra: Array) -> void:
	for n in extra + [r.ic, r.eco.weapons, r.eco, r.net, r.me]:
		n.queue_free()

func _thing(at: Vector3, root: Node) -> Thing:
	var t := Thing.new()
	root.add_child(t)
	t.global_position = at
	return t

func test_hold_fires_once_then_needs_release() -> void:
	var r: Dictionary = await _rig()
	var t := _thing(Vector3(1, 0, 0), r.root)
	var ic: InteractController = r.ic
	ic._update(0.2, true)
	assert_eq(t.used, 0, "not yet")
	assert_true(ic.hold > 0.4 and ic.hold < 1.0, "progress")
	assert_eq(ic.prompt, "Hold F: Thing")
	ic._update(0.2, true)
	assert_eq(t.used, 1, "fired after interact_hold_s")
	ic._update(0.5, true)
	ic._update(0.5, true)
	assert_eq(t.used, 1, "no repeat while the key stays down")
	ic._update(0.1, false)
	ic._update(0.2, true)
	ic._update(0.2, true)
	assert_eq(t.used, 2, "released and held again")
	_drop(r, [t])

func test_target_change_resets_hold() -> void:
	var r: Dictionary = await _rig()
	var a := _thing(Vector3(1, 0, 0), r.root)
	var b := _thing(Vector3(-1.5, 0, 0), r.root)
	var ic: InteractController = r.ic
	ic._update(0.3, true)
	assert_true(ic.hold > 0.5, "holding a")
	a.global_position = Vector3(1.9, 0, 0)               # b is now the nearer one
	ic._update(0.05, true)
	assert_true(ic.target == b, "target switched")
	assert_true(ic.hold < 0.2, "hold restarted: %f" % ic.hold)
	assert_eq(a.used + b.used, 0, "nothing fired")
	_drop(r, [a, b])

func test_nothing_in_reach_or_down() -> void:
	var r: Dictionary = await _rig()
	var t := _thing(Vector3(9, 0, 0), r.root)
	var ic: InteractController = r.ic
	ic._update(1.0, true)
	assert_eq(ic.prompt, "")
	assert_eq(t.used, 0)
	t.global_position = Vector3(1, 0, 0)
	r.me.state = Player.DOWN
	ic._update(1.0, true)
	assert_eq(t.used, 0, "downed players cannot use")
	_drop(r, [t])

func test_request_repair_ignores_local_and_floods() -> void:
	# a direct call has no remote sender (id 0), so it is dropped; the flood limit is per peer
	await Engine.get_main_loop().process_frame
	var e := EconomyService.new()
	Engine.get_main_loop().root.add_child(e)               # in the tree, so multiplayer exists
	var p := Player.new()
	p.peer_id = 1
	e.players[1] = p
	var b := Barricade.new()
	b.tear_one()
	e.request_repair(1, NodePath("/root/none"))
	assert_eq(b.boards, 5, "nothing repaired by a bad call")
	assert_true(e.use_allowed(7, 1000), "first request passes")
	assert_true(not e.use_allowed(7, 1050), "second inside the interval is dropped")
	assert_true(e.use_allowed(8, 1050), "another peer is not limited")
	assert_true(e.use_allowed(7, 1000 + int(Content.balance.use_min_interval_s * 1000.0) + 10), "later passes")
	b.free()
	p.free()
	e.free()

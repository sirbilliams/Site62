extends TestCase

func test_client_view_roles() -> void:
	var ms := MatchState.new()
	ms.apply_revive(2, 3, 0.5, 0.8)
	var d := ms.view_for(2)
	assert_eq(d.role, "downed")
	assert_eq(d.other, 3)
	assert_near(d.progress, 0.5)
	assert_near(d.bleed, 0.8)
	var r := ms.view_for(3)
	assert_eq(r.role, "reviver")
	assert_eq(r.other, 2)
	assert_eq(ms.view_for(9).role, "", "uninvolved peers see nothing")
	ms.free()

func test_bad_messages_are_ignored() -> void:
	var ms := MatchState.new()
	ms.apply_revive("x", 3, 0.5, 0.8)
	ms.apply_revive(2, 3, NAN, 0.8)
	ms.apply_revive(2, 3, null, 0.8)
	assert_eq(ms.view_for(2).role, "")
	ms.apply_revive(2, 0, 7.0, -4.0)
	assert_near(ms.view_for(2).progress, 1.0, 1e-4, "clamped")
	assert_near(ms.view_for(2).bleed, 0.0, 1e-4, "clamped")
	ms.free()

func test_view_expires() -> void:
	var ms := MatchState.new()
	ms.apply_revive(2, 3, 0.5, 0.8)
	ms._view.at -= MatchState.VIEW_FRESH_MS + 50
	assert_eq(ms.view_for(2).role, "", "stale message dropped")
	ms.free()

func test_host_view_from_internal_state() -> void:
	var ms := MatchState.new()
	ms._down_t[2] = 6.0
	ms._rev[2] = {"by": 1, "t": 2.0}
	var d := ms.view_for(2)
	assert_eq(d.role, "downed")
	assert_eq(d.other, 1)
	assert_near(d.progress, 2.0 / Content.balance.revive_hold_s, 1e-3)
	assert_near(d.bleed, 1.0 - 6.0 / Content.balance.downed_bleedout_s, 1e-3)
	var r := ms.view_for(1)
	assert_eq(r.role, "reviver")
	assert_eq(r.other, 2)
	ms.free()

extends TestCase

func test_starting_kit() -> void:
	var inv := Inventory.new()
	assert_eq(inv.slots.size(), 2, "two slots")
	assert_eq(inv.slots[0].data.id, &"sentinel_45", "slot 0")
	assert_true(inv.slots[1] == null, "slot 1 empty")
	assert_eq(inv.held, 0, "held")
	assert_eq(inv.grenades, Content.balance.grenades_start, "grenades")

func test_give_fills_empty_then_replaces_held() -> void:
	var inv := Inventory.new()
	assert_eq(inv.give(Content.weapon(&"hornet")), 1, "empty slot used")
	assert_eq(inv.held, 1, "new gun held")
	assert_eq(inv.slots[0].data.id, &"sentinel_45", "slot 0 kept")
	assert_eq(inv.give(Content.weapon(&"garand_k")), 1, "held replaced")
	assert_eq(inv.slots[1].data.id, &"garand_k", "replaced")
	assert_eq(inv.slots[0].data.id, &"sentinel_45", "other slot untouched")
	inv.swap(0.0)
	assert_eq(inv.give(Content.weapon(&"bulwark_60")), 0, "held slot 0 replaced")
	assert_eq(inv.slots[1].data.id, &"garand_k", "slot 1 kept")

func test_swap_and_ammo_preserved() -> void:
	var inv := Inventory.new()
	assert_true(not inv.swap(0.0), "nothing to swap to")
	inv.slots[0].mag = 3
	inv.give(Content.weapon(&"hornet"))
	inv.held_state().mag = 5
	assert_true(inv.swap(10.0), "swap")
	assert_eq(inv.held, 0, "held 0")
	assert_eq(inv.held_state().mag, 3, "slot 0 mag kept")
	assert_true(inv.swap(11.0), "swap back")
	assert_eq(inv.held_state().mag, 5, "slot 1 mag kept")

func test_swap_blocks_firing_and_cancels_reload() -> void:
	var inv := Inventory.new()
	inv.give(Content.weapon(&"hornet"))
	inv.slots[1].mag = 1
	inv.slots[1].start_reload(0.0)
	assert_true(inv.swap(5.0), "swap")
	assert_true(not inv.slots[1].reloading, "reload cancelled")
	assert_true(inv.swap_blocked(5.0), "blocked at once")
	assert_true(inv.swap_blocked(5.0 + Content.balance.swap_s - 0.01), "blocked until swap_s")
	assert_true(not inv.swap_blocked(5.0 + Content.balance.swap_s + 0.01), "free after")
	assert_true(not inv.swap(5.1), "cannot swap again mid-swap")

func test_has_weapon_and_state_of() -> void:
	var inv := Inventory.new()
	assert_true(inv.has_weapon(&"sentinel_45"), "has start gun")
	assert_true(not inv.has_weapon(&"hornet"), "no hornet")
	inv.give(Content.weapon(&"hornet"))
	assert_true(inv.has_weapon(&"hornet"), "has hornet")
	assert_eq(inv.state_of(&"sentinel_45"), inv.slots[0], "state_of")

func test_grenade_refill_cap() -> void:
	var inv := Inventory.new()
	inv.grenades = 0
	inv.refill_grenades()
	assert_eq(inv.grenades, 2, "+2")
	inv.refill_grenades()
	assert_eq(inv.grenades, 4, "+2 more")
	inv.refill_grenades()
	assert_eq(inv.grenades, Content.balance.grenades_max, "capped")
	assert_true(inv.take_grenade(), "take")
	assert_eq(inv.grenades, 3, "decremented")
	inv.grenades = 0
	assert_true(not inv.take_grenade(), "none left")

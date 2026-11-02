class_name SudsEffects
extends RefCounted
## The Ethereal-Suds one player holds. Pure data: stacks the four effects (max_hp, reload_mult, revive, fire_rate_mult).
## `revive` is only stored/queried here; the down/revive flow itself belongs to Task 11.

var _owned := {}            # suds id -> {effect, value}

## Add a Suds. False (nothing changes) if the player already has that one.
func add(s: SudsData) -> bool:
	return add_raw(s.id, s.effect, s.value)

func add_raw(id: StringName, effect: StringName, value: float) -> bool:
	if _owned.has(id):
		return false
	_owned[id] = {"effect": effect, "value": value}
	return true

func has(id: StringName) -> bool:
	return _owned.has(id)

func count() -> int:
	return _owned.size()

func ids() -> Array:
	return _owned.keys()

func _fold(effect: StringName, start: float, multiply: bool) -> float:
	var v := start
	for o in _owned.values():
		if o.effect == effect:
			v = v * o.value if multiply else maxf(v, o.value)
	return v

## The max hp value of the Suds replaces the base (it is the total, not a bonus).
func max_hp(base: float) -> float:
	return _fold(&"max_hp", base, false)

## Multiplier on reload TIME (0.5 = twice as fast).
func reload_mult() -> float:
	return _fold(&"reload_mult", 1.0, true)

## Multiplier on revive TIME.
func revive_mult() -> float:
	return _fold(&"revive", 1.0, true)

## Multiplier on the fire RATE (1.33 = 33 percent faster).
func fire_rate_mult() -> float:
	return _fold(&"fire_rate_mult", 1.0, true)

## A downed player may revive themselves only when playing alone and holding the revive Suds.
func can_self_revive(solo: bool) -> bool:
	return solo and _owned.values().any(func(o): return o.effect == &"revive")

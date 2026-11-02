class_name LifeRules
extends RefCounted
## Pure down / revive / bleed-out rules. Values come from Content.balance only.

## Apply `dmg` to an ALIVE player's hp (floored at 0) and return the state it should now be in.
## DOWN / DEAD players take no further damage here. The caller assigns the state.
static func on_damage(p: Player, dmg: float) -> int:
	if p.state != Player.ALIVE:
		return p.state
	p.hp = maxf(0.0, p.hp - dmg)
	return Player.DOWN if p.hp <= 0.0 else Player.ALIVE

## 0..1 revive progress after holding USE for `t_held` seconds; `mult` is the reviver's revive_mult (0.5 = twice as fast).
static func revive_progress(t_held: float, mult: float) -> float:
	var need := maxf(Content.balance.revive_hold_s * mult, 0.001)
	return clampf(t_held / need, 0.0, 1.0)

## Seconds left before a downed player bleeds out, `t_down` seconds after going down.
static func bleedout_left(t_down: float) -> float:
	return maxf(Content.balance.downed_bleedout_s - t_down, 0.0)

## Solo self revive: needs the revive Suds and no teammates; takes the plain revive_hold_s (the Suds is consumed).
static func self_revive_progress(t_down: float, suds: SudsEffects, solo: bool) -> float:
	if not suds.can_self_revive(solo):
		return 0.0
	return clampf(t_down / maxf(Content.balance.revive_hold_s, 0.001), 0.0, 1.0)

## hp a revived player comes back with.
static func revive_hp(max_hp: float) -> float:
	return max_hp * Content.balance.revive_hp_frac

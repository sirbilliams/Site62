class_name InteractController
extends Node
## Local player's "use" key: finds what is in reach, tells the HUD the prompt, and asks the host after the key was
## held Balance.interact_hold_s (Hold F). Buying/opening fires once per press; repairing a barricade repeats while held.
## Reviving needs no request: MatchState reads the USE button of the frames; here it only shows "Hold F: Revive".

var net: PlayerNet
var eco: EconomyService
var weapons: WeaponService
var match_state: MatchState
var enabled := true
var prompt := ""                 # HUD text ("" = none)
var hold := 0.0                  # 0..1 hold progress
var target: Node                 # Interactable / Barricade / Player (downed) in reach
var _t := 0.0
var _need_release := false
var _last_target: Node

func bind(pn: PlayerNet, e: EconomyService, svc: WeaponService, ms: MatchState) -> void:
	net = pn
	eco = e
	weapons = svc
	match_state = ms

func _process(dt: float) -> void:
	_update(dt, Input.is_action_pressed(&"use") if InputMap.has_action(&"use") else false)

## Testable core: `pressed` = the use key is down.
func _update(dt: float, pressed: bool) -> void:
	var me: Player = net.local_player() if net != null else null
	target = null
	prompt = ""
	if me == null or me.state != Player.ALIVE or not enabled:
		_t = 0.0
		hold = 0.0
		return
	var reach := Content.balance.use_range
	var best := INF
	for p: Player in net.players.values():                    # a downed teammate: reviving beats shopping
		if p != me and p.state == Player.DOWN and _near(me, p.position, reach):
			var d := me.position.distance_to(p.position)
			if d < best:
				best = d
				target = p
				prompt = "Hold %s: Revive" % Settings.key_label(&"use")
	if target == null:
		for it: Interactable in get_tree().get_nodes_in_group(&"interactables"):
			if not _near(me, it.global_position, reach):
				continue
			it.weapons = weapons
			var txt := HudText.prompt_text(it, me)
			var d := me.position.distance_to(it.global_position)
			if txt != "" and d < best:
				best = d
				target = it
				prompt = txt
	if target == null:
		for b: Barricade in get_tree().get_nodes_in_group(&"barricades"):
			var d := me.position.distance_to(b.global_position)
			if b.boards < b.max_boards and d <= EconomyService.REPAIR_REACH and not b.is_outside(me.position) and d < best:
				best = d
				target = b
				prompt = "Hold %s: Repair barricade" % Settings.key_label(&"use")
	if target != _last_target:                              # a new target starts its hold from zero
		_last_target = target
		_t = 0.0
		hold = 0.0
	if not pressed:
		_t = 0.0
		hold = 0.0
		_need_release = false
		return
	if target == null or target is Player or _need_release:
		_t = 0.0
		hold = 0.0
		return
	_t += dt
	var need := maxf(Content.balance.interact_hold_s, 0.01)
	hold = clampf(_t / need, 0.0, 1.0)
	if _t < need:
		return
	_t = 0.0
	hold = 0.0
	if target is Barricade:
		eco.repair_local(target)                            # repeats while the key stays down
	else:
		eco.use_local(target)
		_need_release = true

func _near(me: Player, at: Vector3, reach: float) -> bool:
	return Vector2(at.x - me.position.x, at.z - me.position.z).length() <= reach and absf(at.y - me.position.y) <= 3.0

extends Node
## Autoload "Game": match-wide state the host owns and replicates reliably.
##  power    - the generator switch (PowerSwitch); Suds machines and the Isotope Refit need it.
##  suds_of  - the Ethereal-Suds of every player (host and clients mirror it).
##  vouchers - host: peers whose next Requisition Crate is free (Task 10's voucher power-up gives one).
## A late joiner gets power, every Suds and the vouchers in the WorldSnapshot (snapshot / apply_snapshot below).

signal power_changed(on: bool)
signal suds_changed(peer: int)

var power := false
var rng := RandomNumberGenerator.new()      # host-seeded; the crate roll is made on the host only
var _suds := {}                              # peer -> SudsEffects
var vouchers := {}                           # host: peer -> true

func _ready() -> void:
	name = "Game"
	rng.randomize()
	Net.player_left.connect(forget_peer)

func forget_peer(peer: int) -> void:
	_suds.erase(peer)
	vouchers.erase(peer)

## Back to a fresh match (tests, new run).
func reset() -> void:
	rng.randomize()
	_apply_power(false)
	_suds.clear()
	vouchers.clear()

func seed_rng(s: int) -> void:
	rng.seed = s

func suds_of(peer: int) -> SudsEffects:
	if not _suds.has(peer):
		_suds[peer] = SudsEffects.new()
	return _suds[peer]

## The local player's hp ceiling.
func max_hp_of(peer: int, base: float) -> float:
	return suds_of(peer).max_hp(base)

# ---------------------------------------------------------------- late join

## Host: power, the Suds of each peer in `peers`, and the peers holding a voucher.
func snapshot(peers: Array) -> Dictionary:
	var suds := {}
	for id in peers:
		suds[id] = suds_of(id).to_list()
	var v: Array = []
	for id in peers:
		if vouchers.has(id):
			v.append(id)
	return {"power": power, "suds": suds, "vouchers": v}

## Client: mirror a snapshot() of the host.
func apply_snapshot(d: Dictionary) -> void:
	if Net.is_host():
		return
	if typeof(d.get("power")) == TYPE_BOOL:
		_apply_power(d.power)
	var suds = d.get("suds")
	if suds is Dictionary:
		for peer in suds:
			var list = suds[peer]
			if typeof(peer) != TYPE_INT or not list is Array:
				continue
			var fresh := SudsEffects.new()
			for e in list:
				if e is Array and e.size() == 3 and typeof(e[0]) == TYPE_STRING and typeof(e[1]) == TYPE_STRING \
						and (typeof(e[2]) == TYPE_FLOAT or typeof(e[2]) == TYPE_INT) and Content.SUDS_EFFECTS.has(StringName(e[1])):
					fresh.add_raw(StringName(e[0]), StringName(e[1]), float(e[2]))
			_suds[peer] = fresh
			suds_changed.emit(peer)
	var v = d.get("vouchers")
	if v is Array:
		vouchers.clear()
		for id in v:
			if typeof(id) == TYPE_INT:
				vouchers[id] = true

# ---------------------------------------------------------------- vouchers (host)

func give_voucher(peer: int) -> void:
	vouchers[peer] = true
	if Net.is_host():
		Net.send_reliable(self, &"_rx_voucher", 0, [peer, true])

func has_voucher(peer: int) -> bool:
	return vouchers.get(peer, false)

## Host: use up the voucher; true if there was one.
func take_voucher(peer: int) -> bool:
	var had := vouchers.erase(peer)
	if had and Net.is_host():
		Net.send_reliable(self, &"_rx_voucher", 0, [peer, false])
	return had

@rpc("authority", "reliable")
func _rx_voucher(peer, has) -> void:
	if Net.is_host() or typeof(peer) != TYPE_INT or typeof(has) != TYPE_BOOL:
		return
	if has:
		vouchers[peer] = true
	else:
		vouchers.erase(peer)

# ---------------------------------------------------------------- power (host)

func set_power(on: bool) -> void:
	if not Net.is_host():
		return
	_apply_power(on)
	Net.send_reliable(self, &"_rx_power", 0, [on])

func _apply_power(on: bool) -> void:
	if power == on:
		return
	power = on
	power_changed.emit(on)

@rpc("authority", "reliable")
func _rx_power(on) -> void:
	if Net.is_host() or typeof(on) != TYPE_BOOL:
		return
	_apply_power(on)

# ---------------------------------------------------------------- suds (host decides, everyone mirrors)

## Host: drop every Suds of `peer` (death, new run) except those giving an effect in `keep`, and tell everyone.
## `p` (that peer's Player, if the host has it) gets its hp clamped to the new ceiling.
func clear_suds(peer: int, p: Player = null, keep: Array = []) -> void:
	if not Net.is_host():
		return
	_apply_clear(peer, keep)
	if p != null:
		p.hp = minf(p.hp, p.max_health())
	Net.send_reliable(self, &"_rx_clear_suds", 0, [peer, keep.map(func(e): return String(e))])

## Host: a Suds effect is used up (the solo self revive) and everyone mirrors it.
func consume_effect(peer: int, effect: StringName, p: Player = null) -> void:
	if not Net.is_host():
		return
	_apply_consume(peer, effect)
	if p != null:
		p.hp = minf(p.hp, p.max_health())
	Net.send_reliable(self, &"_rx_consume_suds", 0, [peer, String(effect)])

func _apply_consume(peer: int, effect: StringName) -> void:
	if _suds.has(peer) and not suds_of(peer).remove_effect(effect).is_empty():
		suds_changed.emit(peer)

@rpc("authority", "reliable")
func _rx_consume_suds(peer, effect) -> void:
	if Net.is_host() or typeof(peer) != TYPE_INT or typeof(effect) != TYPE_STRING:
		return
	_apply_consume(peer, StringName(effect))

func _apply_clear(peer: int, keep: Array = []) -> void:
	if _suds.has(peer) and suds_of(peer).count() > 0:
		var before := suds_of(peer).count()
		suds_of(peer).clear_except(keep)
		if suds_of(peer).count() != before:
			suds_changed.emit(peer)

@rpc("authority", "reliable")
func _rx_clear_suds(peer, keep = []) -> void:
	if Net.is_host() or typeof(peer) != TYPE_INT or typeof(keep) != TYPE_ARRAY:
		return
	var k: Array = []
	for e in keep:
		if typeof(e) == TYPE_STRING and Content.SUDS_EFFECTS.has(StringName(e)):
			k.append(StringName(e))
	_apply_clear(peer, k)

## Host: record a bought Suds and tell everyone. False if the player already has it.
func grant_suds(peer: int, s: SudsData) -> bool:
	if not suds_of(peer).add(s):
		return false
	suds_changed.emit(peer)
	Net.send_reliable(self, &"_rx_suds", 0, [peer, String(s.id), String(s.effect), s.value])
	return true

@rpc("authority", "reliable")
func _rx_suds(peer, id, effect, value) -> void:
	if Net.is_host() or typeof(peer) != TYPE_INT or typeof(id) != TYPE_STRING or typeof(effect) != TYPE_STRING \
			or not (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT):
		return
	if not Content.SUDS_EFFECTS.has(StringName(effect)):
		return
	if suds_of(peer).add_raw(StringName(id), StringName(effect), float(value)):
		suds_changed.emit(peer)

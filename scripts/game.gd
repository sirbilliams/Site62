extends Node
## Autoload "Game": match-wide state the host owns and replicates reliably.
##  power    - the generator switch (PowerSwitch); Suds machines and the Isotope Refit need it.
##  suds_of  - the Ethereal-Suds of every player (host and clients mirror it).
##  vouchers - host: peers whose next Requisition Crate is free (Task 10's voucher power-up gives one).
## Late join resync is Task 12.

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
	power = false
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

# ---------------------------------------------------------------- vouchers (host)

func give_voucher(peer: int) -> void:
	vouchers[peer] = true

func has_voucher(peer: int) -> bool:
	return vouchers.get(peer, false)

## Host: use up the voucher; true if there was one.
func take_voucher(peer: int) -> bool:
	return vouchers.erase(peer)

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

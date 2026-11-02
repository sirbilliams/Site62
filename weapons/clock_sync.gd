class_name ClockSync
extends RefCounted
## Host-side per-peer clock model. Converts a client clock stamp into the host time of the world
## the shooter was looking at (for lag compensation).
## Input frame sample = client_t - host_recv = offset - one_way_delay; the max (slowly decaying) is the
## least-delayed frame, then + rtt/2 gives the offset.

const DECAY := 0.01       # per-sample pull toward a worse (more delayed) sample
const MAX_REWIND := 0.25

var _est := {}        # id -> float estimate of (client_t - host_recv) at the least delay
var _rtt := {}        # id -> float (seconds)

## A faster sample (less delay) replaces the estimate at once; slower ones only pull it slowly,
## so the estimate never jumps when the best sample would otherwise age out of a window.
func observe(id: int, client_t: float, host_now: float) -> void:
	var v := client_t - host_now
	if not _est.has(id) or v >= _est[id]:
		_est[id] = v
	else:
		_est[id] = lerpf(_est[id], v, DECAY)

func set_rtt(id: int, rtt: float) -> void:
	_rtt[id] = rtt

func rtt(id: int) -> float:
	return _rtt.get(id, 0.0)

func forget(id: int) -> void:
	_est.erase(id)
	_rtt.erase(id)

func has(id: int) -> bool:
	return _est.has(id)

## client clock - host clock.
func offset(id: int) -> float:
	if not _est.has(id):
		return 0.0
	return _est[id] + rtt(id) * 0.5

## Host time of the world state the shooter saw when stamping `client_t`:
## fire time on the host clock, minus snapshot transit (rtt/2), minus the view interpolation delay.
## Clamped to [host_now - MAX_REWIND, host_now].
func rewind_time(id: int, client_t: float, host_now: float, view_delay: float) -> float:
	if not has(id):
		return host_now
	var t := client_t - offset(id) - rtt(id) * 0.5 - view_delay
	return clampf(t, host_now - MAX_REWIND, host_now)

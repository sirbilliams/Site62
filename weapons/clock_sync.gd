class_name ClockSync
extends RefCounted
## Host-side per-peer clock model. Converts a client clock stamp into the host time of the world
## the shooter was looking at (for lag compensation).
## Input frame sample = client_t - host_recv = offset - one_way_delay; the max over a window is the
## least-delayed frame, then + rtt/2 gives the offset.

const WINDOW := 120
const MAX_REWIND := 0.25

var _samples := {}    # id -> Array[float]
var _rtt := {}        # id -> float (seconds)

func observe(id: int, client_t: float, host_now: float) -> void:
	var a: Array = _samples.get(id, [])
	a.append(client_t - host_now)
	if a.size() > WINDOW:
		a.pop_front()
	_samples[id] = a

func set_rtt(id: int, rtt: float) -> void:
	_rtt[id] = rtt

func rtt(id: int) -> float:
	return _rtt.get(id, 0.0)

func forget(id: int) -> void:
	_samples.erase(id)
	_rtt.erase(id)

func has(id: int) -> bool:
	return not _samples.get(id, []).is_empty()

## client clock - host clock.
func offset(id: int) -> float:
	var a: Array = _samples.get(id, [])
	if a.is_empty():
		return 0.0
	var best: float = a[0]
	for v in a:
		best = maxf(best, v)
	return best + rtt(id) * 0.5

## Host time of the world state the shooter saw when stamping `client_t`:
## fire time on the host clock, minus snapshot transit (rtt/2), minus the view interpolation delay.
## Clamped to [host_now - MAX_REWIND, host_now].
func rewind_time(id: int, client_t: float, host_now: float, view_delay: float) -> float:
	if not has(id):
		return host_now
	var t := client_t - offset(id) - rtt(id) * 0.5 - view_delay
	return clampf(t, host_now - MAX_REWIND, host_now)

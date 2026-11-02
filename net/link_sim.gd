class_name LinkSim
extends Node
## Test-only link shim: delays (rtt/2) and drops (loss) this process's outgoing game messages.
## Off by default; enabled by --rtt_ms= / --loss= user args. Net.send_unreliable routes through it.

var rtt_ms := 0.0
var loss := 0.0
var _queue: Array = []   # [due_msec, Callable]
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 62

func enabled() -> bool:
	return rtt_ms > 0.0 or loss > 0.0

func configure(rtt: float, p_loss: float) -> void:
	rtt_ms = rtt
	loss = p_loss

func configure_from_args() -> void:
	var rtt := 0.0
	var l := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rtt_ms="):
			rtt = float(a.substr(9))
		elif a.begins_with("--loss="):
			l = float(a.substr(7))
	configure(rtt, l)

func pending() -> int:
	return _queue.size()

## `lossy` false = reliable channel: delayed like everything else but never dropped.
func submit(send: Callable, lossy := true) -> void:
	if lossy and loss > 0.0 and _rng.randf() < loss:
		return
	_queue.append([Time.get_ticks_msec() + rtt_ms * 0.5, send])

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	while not _queue.is_empty() and _queue[0][0] <= now:
		var item: Array = _queue.pop_front()
		(item[1] as Callable).call()

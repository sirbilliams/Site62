class_name Wallet
extends RefCounted
## One player's points. Pure. Board-repair points are capped per round (the cap counts base points, not doubled).

var points := 0
var board_points_this_round := 0
var board_cap := 400

func _init(start := 0, cap := 400) -> void:
	points = start
	board_cap = cap

func add(n: int, double_points: bool) -> void:
	points += n * 2 if double_points else n

## Points for a board repair, limited by the per-round cap. Returns what was actually awarded (before doubling).
func add_board(n: int, double_points: bool) -> int:
	var allowed := clampi(board_cap - board_points_this_round, 0, n)
	board_points_this_round += allowed
	if allowed > 0:
		add(allowed, double_points)
	return allowed

func try_spend(cost: int) -> bool:
	if cost < 0 or cost > points:
		return false
	points -= cost
	return true

func reset_round() -> void:
	board_points_this_round = 0

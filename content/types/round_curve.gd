class_name RoundCurve
extends Resource

@export var break_s: float = 10.0
@export var base_count: int = 5
@export var count_per_round: int = 3
@export var coop_count_bonus: float = 0.5
@export var base_health: int = 120
@export var health_per_round: int = 80
@export var linear_health_until: int = 10
@export var health_growth: float = 1.08
@export var jog_from_round: int = 4
@export var sprint_from_round: int = 8
@export var spawn_base_s: float = 2.0
@export var spawn_step_s: float = 0.1
@export var spawn_min_s: float = 0.4

func count(r: int, players: int) -> int:
	return int((base_count + count_per_round * r) * (1.0 + coop_count_bonus * (players - 1)))

func health(r: int) -> int:
	var h := base_health + health_per_round * (mini(r, linear_health_until) - 1)
	for i in range(linear_health_until + 1, r + 1):
		h = int(floor(h * health_growth))
	return h

func speed_band(r: int) -> int:
	if r >= sprint_from_round:
		return 2
	if r >= jog_from_round:
		return 1
	return 0

func spawn_interval(r: int) -> float:
	return maxf(spawn_min_s, spawn_base_s - spawn_step_s * r)

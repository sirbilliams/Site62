class_name Balance
extends Resource

@export var start_points: int = 500
@export var pts_hit: int = 10
@export var pts_kill: int = 60
@export var pts_headshot_bonus: int = 40
@export var pts_melee_kill: int = 120
@export var pts_board: int = 10
@export var board_cap_per_round: int = 400
@export var player_hp: float = 100.0
@export var downed_bleedout_s: float = 30.0
@export var revive_hold_s: float = 4.0
@export var max_suds: int = 4
@export var powerup_drop_chance: float = 0.03
@export var powerup_max_per_round: int = 4
@export var powerup_duration_s: float = 30.0
@export var crate_cost: int = 950
@export var crate_moves_after_uses: int = 6
@export var refit_cost: int = 5000
@export var fire_rate_tolerance: float = 0.10
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 6.8
@export var crouch_speed: float = 2.2
@export var jump_speed: float = 4.8
@export var gravity: float = 14.0
@export var max_alive: int = 40
@export var headshot_mult: float = 2.0
@export var shot_origin_tolerance: float = 2.5
@export var max_shot_range: float = 100.0
@export var barricade_boards: int = 6
@export var repath_s: float = 0.5

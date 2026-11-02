class_name Zombie
extends HitTarget
## One zombie. Host: runs ZombieBrain (NavigationAgent3D), owns hp. Client: a visual copy moved by ZombieSync.
## Hit ids: peers use positive ids and the weapon dummy uses 1000, so a zombie registers in WeaponService and
## HitHistory under the NEGATIVE id -zid (hit_id). Peer ids can never be negative, so they cannot collide.

signal died(zid: int, killer: int, headshot: bool, melee: bool, pos: Vector3)

enum Anim { IDLE, WALK, TEAR, ATTACK, CLIMB }

var zid := 0
var hp := 100.0
var data: EnemyData
var band := 1
var anim := Anim.IDLE
var yaw := 0.0
var agent: NavigationAgent3D      # host only
var brain: ZombieBrain            # host only

static func hit_id(z: int) -> int:
	return -z

static func zid_of(hit: int) -> int:
	return -hit

func setup(id: int, d: EnemyData, health: float, speed_band: int, host: bool) -> void:
	zid = id
	data = d
	hp = health
	band = clampi(speed_band, 0, d.speed_by_band.size() - 1)
	name = "Z%d" % id
	boxes.clear()
	add_box(Vector3(0, 0.7, 0), Vector3(0.7, 1.4, 0.5))
	add_box(Vector3(0, 1.65, 0), Vector3(0.4, 0.4, 0.4), true)
	if host:
		agent = NavigationAgent3D.new()
		agent.path_desired_distance = 0.3
		agent.target_desired_distance = 0.8
		agent.avoidance_enabled = false
		add_child(agent)
		brain = ZombieBrain.new()
		brain.z = self

func speed() -> float:
	return data.speed_by_band[band]

func _ready() -> void:
	build_physics()
	var mi := MeshInstance3D.new()      # placeholder art: capsule
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	mi.mesh = cap
	mi.position.y = 0.9
	add_child(mi)

## Host only.
func take_damage(dmg: float, from: int, headshot: bool, melee := false) -> void:
	if not alive:
		return
	hp -= dmg
	if hp <= 0.0:
		alive = false
		died.emit(zid, from, headshot, melee, position)

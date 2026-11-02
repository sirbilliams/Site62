class_name SudsMachine
extends Interactable
## Ethereal-Suds dispenser. Needs power; refuses a Suds the player already has and a player at max_suds.
## The effect (max hp, reload, revive, fire rate) lives in Game.suds_of(peer), mirrored on every peer.

@export var suds: SudsData

func reject_reason(player: Player) -> StringName:
	if suds == null:
		return &"invalid"
	if not Game.power:
		return &"no_power"
	var have := Game.suds_of(player.peer_id)
	if have.has(suds.id):
		return &"owned"
	if have.count() >= Content.balance.max_suds:
		return &"max_suds"
	return &""

func cost_for(_player: Player) -> int:
	return suds.cost if suds != null else 0

func prompt(player: Player) -> String:
	if suds == null:
		return ""
	if not Game.power:
		return "%s (no power)" % suds.display_name
	return "Buy %s [%d]" % [suds.display_name, suds.cost]

func what(_player: Player) -> StringName:
	return suds.id if suds != null else &"suds"

func use(player: Player) -> bool:
	var before := player.max_health()
	if not Game.grant_suds(player.peer_id, suds):
		return false
	player.hp += maxf(player.max_health() - before, 0.0)     # the new ceiling is filled in
	return true

## 70s soda-machine look, built at runtime from SudsData.color: rounded body, chrome trim, glowing sign, bottle window.
## Local +Z is the front.
func _ready() -> void:
	if get_node_or_null("Look") != null:
		return
	var col := suds.color if suds != null else Color(0.8, 0.8, 0.8)
	var look := Node3D.new()
	look.name = "Look"
	add_child(look)
	var body := _mesh(look, BoxMesh.new(), Vector3(1.1, 1.7, 0.8), Vector3(0, 0.85, 0), _paint(col, 0.35, 0.3))
	body.name = "Body"
	var cap := CylinderMesh.new()                                   # rounded top: a cylinder lying along X
	cap.top_radius = 0.4
	cap.bottom_radius = 0.4
	cap.height = 1.1
	var top := _mesh(look, cap, Vector3.ONE, Vector3(0, 1.7, 0), _paint(col, 0.35, 0.3))
	top.rotation.z = PI / 2.0
	_mesh(look, BoxMesh.new(), Vector3(1.16, 0.12, 0.86), Vector3(0, 0.06, 0), _paint(Color(0.75, 0.75, 0.78), 0.9, 0.2))   # chrome base
	_mesh(look, BoxMesh.new(), Vector3(1.16, 0.06, 0.86), Vector3(0, 1.1, 0), _paint(Color(0.75, 0.75, 0.78), 0.9, 0.2))    # chrome band
	_mesh(look, BoxMesh.new(), Vector3(0.7, 0.6, 0.04), Vector3(-0.1, 0.75, 0.41), _paint(Color(0.05, 0.08, 0.1), 0.2, 0.1))  # bottle window
	var glow := StandardMaterial3D.new()
	glow.albedo_color = col.lightened(0.5)
	glow.emission_enabled = true
	glow.emission = col.lightened(0.4)
	glow.emission_energy_multiplier = 2.2
	_mesh(look, BoxMesh.new(), Vector3(0.95, 0.34, 0.05), Vector3(0, 1.45, 0.42), glow).name = "Sign"
	var lbl := Label3D.new()
	lbl.text = suds.display_name if suds != null else "Ethereal-Suds"
	lbl.font_size = 32
	lbl.pixel_size = 0.0028
	lbl.modulate = Color(0.05, 0.03, 0.03)
	lbl.position = Vector3(0, 1.45, 0.455)
	lbl.width = 320
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	look.add_child(lbl)
	for i in 3:                                                      # buttons
		_mesh(look, BoxMesh.new(), Vector3(0.1, 0.1, 0.05), Vector3(0.38, 0.95 - i * 0.2, 0.42), glow)
	var light := OmniLight3D.new()
	light.light_color = col.lightened(0.3)
	light.light_energy = 0.8
	light.omni_range = 3.5
	light.position = Vector3(0, 1.4, 0.8)
	look.add_child(light)

static func _paint(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m

static func _mesh(parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

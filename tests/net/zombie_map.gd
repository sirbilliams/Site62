extends RefCounted
## Test map built in code: a floor, a wall at z=0 with one window (x in [-1,1]) holding a Barricade, and a
## hand-made navigation mesh: outside area (z 1..20) and inside area (z -20..-1) that are NOT connected except
## through the barricade's NavigationLink3D (enabled only at 0 boards).

static func build(parent: Node3D) -> Barricade:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position.y = -1.0
	floor_body.add_child(cs)
	parent.add_child(floor_body)
	for sx in [-1.0, 1.0]:                       # wall segments either side of the window
		var w := StaticBody3D.new()
		w.collision_layer = 1
		var wc := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(11, 3, 2)
		wc.shape = wb
		w.position = Vector3(sx * 6.5, 1.5, 0)
		w.add_child(wc)
		parent.add_child(w)
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([
		Vector3(-12, 0, 1), Vector3(12, 0, 1), Vector3(12, 0, 20), Vector3(-12, 0, 20),
		Vector3(-12, 0, -20), Vector3(12, 0, -20), Vector3(12, 0, -1), Vector3(-12, 0, -1)])
	nm.add_polygon(PackedInt32Array([0, 3, 2, 1]))
	nm.add_polygon(PackedInt32Array([4, 7, 6, 5]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	parent.add_child(region)
	var b: Barricade = load("res://mapkit/barricade.tscn").instantiate()
	parent.add_child(b)
	return b

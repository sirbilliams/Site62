extends TestCase

func _dummy() -> HitTarget:
	var t := HitTarget.new()
	t.add_box(Vector3(0, 0.8, 0), Vector3(1, 1.6, 1))
	t.add_box(Vector3(0, 1.8, 0), Vector3(0.4, 0.4, 0.4), true)
	return t

func test_body_and_head_rays() -> void:
	var t := _dummy()
	var xf := Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))
	var body := t.ray_at(xf, Vector3(0, 0.8, 0), Vector3.RIGHT)
	assert_true(not body.is_empty() and not body.head, "body")
	assert_near(body.t, 4.5, 1e-3, "body dist")
	var head := t.ray_at(xf, Vector3(0, 1.8, 0), Vector3.RIGHT)
	assert_true(not head.is_empty() and head.head, "head")
	assert_true(t.ray_at(xf, Vector3(0, 3.0, 0), Vector3.RIGHT).is_empty(), "over the top")
	assert_true(t.ray_at(xf, Vector3(0, 0.8, 0), Vector3.LEFT).is_empty(), "behind")
	t.free()

func test_rotated_pose() -> void:
	var t := _dummy()
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, -5))
	var h := t.ray_at(xf, Vector3(0, 0.8, 0), Vector3(0, 0, -1))
	assert_true(not h.is_empty(), "rotated hit")
	assert_near(h.t, 4.5, 1e-3, "dist")
	t.free()

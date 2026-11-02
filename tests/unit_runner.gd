extends SceneTree

func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var passed := 0
	var failed := 0
	var dir := DirAccess.open("res://tests/unit")
	var files: Array[String] = []
	if dir:
		for f in dir.get_files():
			if f.begins_with("test_") and f.ends_with(".gd") and (filter == "" or f.contains(filter)):
				files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_"):
				methods.append(m.name)
		methods.sort()
		for name in methods:
			var inst = script.new()
			inst.call(name)
			if inst.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for msg in inst.failures:
					print("UNIT FAIL %s::%s: %s" % [f, name, msg])
	if failed == 0:
		print("UNIT PASS %d" % passed)
	quit(0 if failed == 0 else 1)

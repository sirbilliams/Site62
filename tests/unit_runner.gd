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
		if script == null:
			failed += 1
			print("UNIT FAIL %s: load error" % f)
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_"):
				methods.append(m.name)
		methods.sort()
		for method in methods:
			var inst = script.new()
			inst.call(method)
			if inst.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for msg in inst.failures:
					print("UNIT FAIL %s::%s: %s" % [f, method, msg])
	if passed + failed == 0:
		print("UNIT FAIL no tests matched")
		quit(1)
		return
	if failed == 0:
		print("UNIT PASS %d" % passed)
	quit(0 if failed == 0 else 1)

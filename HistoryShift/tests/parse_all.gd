extends SceneTree
## すべての .gd を読み込んでパースエラーを検出する: godot --headless --path . -s tests/parse_all.gd

func _initialize() -> void:
	var bad := 0
	var files := _collect("res://scripts")
	for f in files:
		var s = load(f)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
			print("PARSE FAIL: ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit(1 if bad else 0)


func _collect(dir: String) -> Array:
	var out: Array = []
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_collect(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out

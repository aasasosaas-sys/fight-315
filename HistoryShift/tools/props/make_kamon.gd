extends SceneTree
## 家紋の画像を焼く（Figures.kamon_image の手続き生成 → PNG）。
##   godot --headless --path . -s res://tools/props/make_kamon.gd
## 出力: res://assets/characters/props/kamon/<名>.png（256px、白＝紋、黒＝墨、透明＝地）と一覧 _sheet.png
## 焼いた後は `godot --headless --import` で取り込む。

const OUT := "res://assets/characters/props/kamon/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var kinds: Array = Figures.KAMON_KINDS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		kinds = Array(args)
	var cols := 6
	var cell := 128
	var sheet := Image.create(cols * cell, int(ceil(kinds.size() / float(cols))) * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.18, 0.32))
	var i := 0
	for kd: String in kinds:
		var img := Figures.kamon_image(kd, 256, 2)
		img.save_png(ProjectSettings.globalize_path(OUT + kd + ".png"))
		var sm := img.duplicate() as Image
		sm.resize(cell - 8, cell - 8, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(sm, Rect2i(0, 0, cell - 8, cell - 8), Vector2i((i % cols) * cell + 4, (i / cols) * cell + 4))
		print("kamon: ", kd)
		i += 1
	if args.size() == 0:
		sheet.save_png(ProjectSettings.globalize_path(OUT + "_sheet.png"))
	quit()

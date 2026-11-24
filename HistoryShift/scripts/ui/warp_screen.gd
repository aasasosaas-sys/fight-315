extends Control
## 時空跳躍の全画面演出。covered（画面が完全に覆われた）→ 呼び出し側が裏で Session を生成 → finish() で抜ける。

signal covered
signal finished

var title := ""
var subtitle := ""
var caption := "時空跳躍"
var _mat: ShaderMaterial
var _text_box: VBoxContainer
var _progress_tw: Tween
var _flash: ColorRect


func _ready() -> void:
	theme = JSUI.theme()
	JSUI.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var r := ColorRect.new()
	JSUI.full_rect(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/ui/shaders/warp.gdshader")
	_mat.set_shader_parameter("progress", 0.0)
	_mat.set_shader_parameter("strength", 0.0)
	r.material = _mat
	add_child(r)
	var c := CenterContainer.new()
	JSUI.full_rect(c)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	_text_box = JSUI.vbox(6)
	_text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(_text_box)
	var cap := JSUI.label("―  %s  ―" % caption, 28, Color.WHITE, JSUI.sans_bold())
	cap.add_theme_constant_override("outline_size", 10)
	cap.add_theme_color_override("font_outline_color", Color(0.02, 0.1, 0.18, 0.9))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_box.add_child(cap)
	var t := JSUI.label(title, 96, Color.WHITE, JSUI.serif_bold())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", Color(0.02, 0.1, 0.18, 0.85))
	t.add_theme_constant_override("shadow_outline_size", 30)
	t.add_theme_color_override("font_shadow_color", Color(JSUI.CYAN, 0.45))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	_text_box.add_child(t)
	var s := JSUI.label(subtitle, 34, Color(JSUI.CYAN, 0.95), JSUI.sans_bold())
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_constant_override("outline_size", 8)
	s.add_theme_color_override("font_outline_color", Color(0.02, 0.1, 0.18, 0.85))
	_text_box.add_child(s)
	_text_box.modulate.a = 0.0
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	JSUI.full_rect(_flash)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	UISfx.play("warp")
	var tw := create_tween()
	tw.tween_method(func(x: float): _mat.set_shader_parameter("strength", x), 0.0, 1.0, 0.35)
	tw.tween_callback(func(): covered.emit())
	_progress_tw = create_tween()
	_progress_tw.tween_method(func(x: float): _mat.set_shader_parameter("progress", x), 0.0, 0.75, 1.8).set_trans(Tween.TRANS_SINE)
	var tt := create_tween()
	tt.tween_interval(0.3)
	tt.tween_property(_text_box, "modulate:a", 1.0, 0.4)
	_text_box.scale = Vector2(1.15, 1.15)
	_text_box.pivot_offset = Vector2(400, 80)
	tt.parallel().tween_property(_text_box, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func set_progress_now(p: float) -> void:
	_mat.set_shader_parameter("progress", p)
	_mat.set_shader_parameter("strength", 1.0)
	_text_box.modulate.a = 1.0


func finish() -> void:
	if _progress_tw:
		_progress_tw.kill()
	var tw := create_tween()
	tw.tween_method(func(x: float): _mat.set_shader_parameter("progress", x), float(_mat.get_shader_parameter("progress")), 1.0, 0.35)
	tw.parallel().tween_property(_flash, "color:a", 1.0, 0.35)
	tw.tween_callback(func():
		_text_box.visible = false
		_mat.set_shader_parameter("strength", 0.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE)
	tw.tween_property(_flash, "color:a", 0.0, 0.45)
	tw.tween_callback(func():
		finished.emit()
		queue_free())

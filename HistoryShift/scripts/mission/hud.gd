class_name Hud
extends CanvasLayer
## ゲーム中のHUD。照準・体力・弾数・手配度・目標・目標マーカー・方位・会話・トースト・ポーズ・死亡画面。

signal dialog_finished
signal pause_resume
signal pause_abort

const INK := Color(0.07, 0.05, 0.1, 0.78)
const GOLD := Color(0.95, 0.78, 0.35)
const CYAN := Color(0.37, 0.91, 1.0)
const RED := Color(0.86, 0.24, 0.2)
const HP_OK := Color(0.42, 0.9, 0.62)

var target_world: Variant = null   # Vector3 or null
var target_label := ""
var extra_markers: Array = []      # Array[Node3D]（ミッション対象の敵）
var compass_points: Dictionary = {} # name -> Vector3
var is_free_roam := false

var _root: Control
var _cross: Control
var _hit: Label
var _hp_bar: ProgressBar
var _ammo: Label
var _veh: Label
var _stars: Label
var _obj_title: Label
var _obj_text: Label
var _obj_counter: Label
var _timer: Label
var _toast_box: VBoxContainer
var _prompt: Label
var _dialog: PanelContainer
var _dialog_name: Label
var _dialog_text: Label
var _dialog_lines: Array = []
var _dialog_i := 0
var _vignette: ColorRect
var _marker_layer: Control
var _compass: Control
var _pause: Control
var _death: Control
var _banner: Label
var _hit_t := 0.0
var _vig := 0.0
var _bold: Font
var _tool: Label                  # 破壊ツール表示（左下）
var _destr: Label                 # 自由探索の破壊カウンタ（右上）
var _shift: PanelContainer        # 「歴史が揺らいだ！」通知
var _shift_head: Label
var _shift_text: Label
var _shift_detail: Label
var _shift_fx: ColorRect          # 画面のゆらぎ（色収差風の走査線）
var _shift_queue: Array = []
var _shift_busy := false
var _weapon: Label                # 手にしている武器（左下）
var _dur_bar: ProgressBar         # 武器の耐久
var _money: Label                 # 所持金（右上）
var _serif: Font
var _obj_panel: Control
var _banner_line: Control         # 見出しの飾り線
var _banner_spread := 0.0
var _shift_lines: Control         # 改変通知の上下の光の線
var _shift_col := Color(0.37, 0.91, 1.0)
var _shift_line_k := 1.0


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bold = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	_serif = load("res://assets/fonts/NotoSerifJP-Bold.ttf")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; uniform float amount = 0.0; void fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.25, 0.75, length(d) * 1.2); COLOR = vec4(0.7, 0.02, 0.02, v * amount); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_vignette.material = sm
	_root.add_child(_vignette)

	_marker_layer = Control.new()
	_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.draw.connect(_draw_markers)
	_root.add_child(_marker_layer)

	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	_root.add_child(_cross)
	_hit = _label("✕", 40, Color(1, 1, 1, 0))
	_hit.set_anchors_preset(Control.PRESET_CENTER)
	_hit.position = Vector2(-14, -30)

	# 左下：体力・武器・弾（箱ではなく、左から薄れる帯の上に細いバー）
	var bl := _strip(Control.PRESET_BOTTOM_LEFT, Vector2(0, -172), Vector2(520, 140))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	bl.add_child(v)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 10)
	v.add_child(hp_row)
	var hp_tag := _label("体", 15, Color(1, 1, 1, 0.75), hp_row)
	hp_tag.add_theme_font_override("font", _bold)
	_shadowed(hp_tag, 4)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(300, 7)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.show_percentage = false
	var fill := StyleBoxFlat.new(); fill.bg_color = HP_OK; fill.set_corner_radius_all(4)
	fill.border_color = Color(1, 1, 1, 0.35); fill.border_width_top = 1
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.05, 0.04, 0.09, 0.45); bg.set_corner_radius_all(4)
	bg.border_color = Color(1, 1, 1, 0.18); bg.set_border_width_all(1)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_bar.add_theme_stylebox_override("background", bg)
	hp_row.add_child(_hp_bar)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 14)
	v.add_child(wrow)
	_ammo = _label("30 / ∞", 34, Color.WHITE, wrow)
	_ammo.add_theme_font_override("font", _bold)
	_shadowed(_ammo, 6)
	var wcol := VBoxContainer.new()
	wcol.add_theme_constant_override("separation", 0)
	wcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(wcol)
	_weapon = _label("", 18, GOLD, wcol)
	_weapon.add_theme_font_override("font", _bold)
	_shadowed(_weapon, 4)
	_dur_bar = ProgressBar.new()
	_dur_bar.custom_minimum_size = Vector2(130, 3)
	_dur_bar.show_percentage = false
	_dur_bar.max_value = 1.0
	var dfill := StyleBoxFlat.new(); dfill.bg_color = Color(0.92, 0.86, 0.66); dfill.set_corner_radius_all(2)
	var dbg := StyleBoxFlat.new(); dbg.bg_color = Color(1, 1, 1, 0.15); dbg.set_corner_radius_all(2)
	_dur_bar.add_theme_stylebox_override("fill", dfill)
	_dur_bar.add_theme_stylebox_override("background", dbg)
	_dur_bar.visible = false
	wcol.add_child(_dur_bar)
	_veh = _label("", 18, Color(1, 1, 1, 0.85), v)
	_shadowed(_veh, 4)
	_tool = _label("", 17, CYAN, v)
	_shadowed(_tool, 4)

	# 右上：手配度・破壊・所持金（文字だけ、柔らかい影）
	_stars = _label("", 32, GOLD)
	_stars.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stars.position = Vector2(-330, 22)
	_stars.custom_minimum_size = Vector2(300, 44)
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shadowed(_stars, 7)
	_money = _label("", 18, Color(1, 0.92, 0.7))
	_money.anchor_left = 1.0
	_money.anchor_right = 1.0
	_money.offset_left = -660.0
	_money.offset_right = -32.0
	_money.offset_top = 100.0
	_money.offset_bottom = 126.0
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shadowed(_money, 5)
	_destr = _label("", 18, Color(1, 0.84, 0.66))
	_destr.anchor_left = 1.0
	_destr.anchor_right = 1.0
	_destr.offset_left = -660.0
	_destr.offset_right = -32.0
	_destr.offset_top = 70.0
	_destr.offset_bottom = 98.0
	_destr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shadowed(_destr, 5)

	# 左上：目標（金の細い縦線＋文字。背景は左から薄れる帯だけ）
	var tl := _strip(Control.PRESET_TOP_LEFT, Vector2(0, 26), Vector2(500, 0))
	_obj_panel = tl
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	tl.add_child(th)
	var accent := ColorRect.new()
	accent.color = GOLD
	accent.custom_minimum_size = Vector2(3, 0)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(accent)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	th.add_child(tv)
	_obj_title = _label("", 17, GOLD, tv)
	_obj_title.add_theme_font_override("font", _bold)
	_shadowed(_obj_title, 4)
	_obj_text = _label("", 20, Color(1, 1, 1, 0.96), tv)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_text.custom_minimum_size = Vector2(430, 0)
	_obj_text.add_theme_constant_override("line_spacing", -2)
	_shadowed(_obj_text, 5)
	_obj_counter = _label("", 17, CYAN, tv)
	_obj_counter.add_theme_font_override("font", _bold)
	_shadowed(_obj_counter, 4)
	_timer = _label("", 24, Color(1, 0.5, 0.45), tv)
	_timer.add_theme_font_override("font", _bold)
	_shadowed(_timer, 5)

	# 方位（細い線と目盛り）
	_compass = Control.new()
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-300, 14)
	_compass.custom_minimum_size = Vector2(600, 40)
	_compass.size = Vector2(600, 40)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	_root.add_child(_compass)

	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position = Vector2(-450, 78)
	_toast_box.custom_minimum_size = Vector2(900, 0)
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_box)

	_banner = _label("", 64, GOLD)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-600, -190)
	_banner.custom_minimum_size = Vector2(1200, 100)
	_banner.pivot_offset = Vector2(600, 50)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_override("font", _serif)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.75))
	_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_banner.add_theme_constant_override("shadow_offset_y", 4)
	_banner.add_theme_constant_override("shadow_outline_size", 16)
	_banner.modulate.a = 0.0
	# 見出しの上下に細い飾り線（左右へ広がる）
	_banner_line = Control.new()
	_banner_line.set_anchors_preset(Control.PRESET_CENTER)
	_banner_line.position = Vector2(-600, -190)
	_banner_line.size = Vector2(1200, 100)
	_banner_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_line.draw.connect(_draw_banner_line)
	_root.add_child(_banner_line)
	_root.move_child(_banner_line, _banner.get_index())

	_prompt = _label("", 22, Color.WHITE)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-400, -250)
	_prompt.custom_minimum_size = Vector2(800, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_override("font", _bold)
	_prompt.add_theme_stylebox_override("normal", _pill(Color(0.05, 0.04, 0.09, 0.55)))
	_shadowed(_prompt, 4)

	# 会話（下の帯。名前は金の札）
	_dialog = PanelContainer.new()
	_dialog.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialog.position = Vector2(-680, -232)
	_dialog.custom_minimum_size = Vector2(1360, 176)
	var dbox := _box(Color(0.05, 0.04, 0.09, 0.8))
	dbox.set_border_width_all(0)
	dbox.border_width_top = 2
	dbox.border_color = Color(GOLD, 0.8)
	dbox.set_corner_radius_all(6)
	dbox.content_margin_left = 34; dbox.content_margin_right = 34; dbox.content_margin_top = 14
	_dialog.add_theme_stylebox_override("panel", dbox)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	_dialog.add_child(dv)
	_dialog_name = _label("", 26, GOLD, dv)
	_dialog_name.add_theme_font_override("font", _serif)
	_dialog_text = _label("", 27, Color.WHITE, dv)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(1290, 84)
	var hint := _label("E / クリック で次へ  ▼", 16, Color(1, 1, 1, 0.5), dv)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dialog.visible = false
	_root.add_child(_dialog)

	_build_shift()
	_build_pause()
	_build_death()


func _box(c: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(12)
	s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 12; s.content_margin_bottom = 12
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(2)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	return s


## 丸い札（プロンプト・トースト）
func _pill(c: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(40)
	s.content_margin_left = 22; s.content_margin_right = 22; s.content_margin_top = 4; s.content_margin_bottom = 6
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(1)
	return s


## 左右どちらかから透明へ薄れる帯（箱の代わり）
func _fade_box(from_left := true, alpha := 0.5, margin_l := 34.0) -> StyleBoxTexture:
	var g := Gradient.new()
	var ink := Color(0.04, 0.03, 0.08)
	g.set_color(0, Color(ink, alpha))
	g.set_color(1, Color(ink, 0.0))
	g.add_point(0.55, Color(ink, alpha * 0.55))
	if not from_left:
		g.reverse()
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	var st := StyleBoxTexture.new()
	st.texture = gt
	st.content_margin_left = margin_l
	st.content_margin_right = 60
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	return st


func _strip(preset: int, pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(preset)
	p.position = pos
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _fade_box(true, 0.42))
	_root.add_child(p)
	return p


func _panel(pos: Vector2, size: Vector2, preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(preset)
	p.position = pos
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _box(INK))
	_root.add_child(p)
	return p


## 背景の上でも読める柔らかい縁取り（黒ではなく墨色）
func _shadowed(l: Label, outline: int) -> void:
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", outline + 4)


func _label(t: String, size: int, c: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _root).add_child(l)
	return l


func _button(parent: Node, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(420, 64)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_stylebox_override("normal", _box(Color(0.15, 0.13, 0.2, 0.95)))
	b.add_theme_stylebox_override("hover", _box(Color(0.25, 0.2, 0.32, 0.95), GOLD))
	b.add_theme_stylebox_override("pressed", _box(Color(0.1, 0.08, 0.14, 0.95), GOLD))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_shift() -> void:
	_shift_fx = ColorRect.new()
	_shift_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shift_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.37, 0.91, 1.0, 1.0);
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	float wob = sin(UV.y * 90.0 + TIME * 40.0) * 0.004 * amount;
	float band = step(0.82, fract(UV.y * 6.0 - TIME * 1.7)) * amount;
	vec2 off = vec2(0.006 * amount + wob + band * 0.012, 0.0);
	vec3 c;
	c.r = texture(screen_tex, SCREEN_UV + off).r;
	c.g = texture(screen_tex, SCREEN_UV).g;
	c.b = texture(screen_tex, SCREEN_UV - off).b;
	float edge = smoothstep(0.35, 0.8, length(UV - 0.5) * 1.3);
	c = mix(c, tint.rgb, (edge * 0.45 + band * 0.12) * amount);
	COLOR = vec4(c, 1.0);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_shift_fx.material = sm
	_shift_fx.visible = false
	_root.add_child(_shift_fx)
	# 「歴史が揺らいだ」: 画面幅の帯（中央が濃く左右へ薄れる）＋上下の細い光の線。見出しは明朝
	_shift = PanelContainer.new()
	_shift.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_shift.position = Vector2(-760, 170)
	_shift.custom_minimum_size = Vector2(1520, 0)
	_shift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	var ink := Color(0.03, 0.03, 0.08)
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.5, 0.78, 1.0])
	g.colors = PackedColorArray([Color(ink, 0.0), Color(ink, 0.62), Color(ink, 0.78), Color(ink, 0.62), Color(ink, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 512
	gt.height = 4
	var st := StyleBoxTexture.new()
	st.texture = gt
	st.content_margin_left = 260; st.content_margin_right = 260; st.content_margin_top = 18; st.content_margin_bottom = 20
	_shift.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_shift.add_child(v)
	var kicker := _label("― 時 空 改 変 ―", 15, Color(1, 1, 1, 0.6), v)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_override("font", _bold)
	_shift_head = _label("歴史が揺らいだ！", 46, CYAN, v)
	_shift_head.add_theme_font_override("font", _serif)
	_shift_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shift_head.add_theme_constant_override("outline_size", 6)
	_shift_head.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.1, 0.8))
	_shift_head.add_theme_color_override("font_shadow_color", Color(CYAN, 0.35))
	_shift_head.add_theme_constant_override("shadow_offset_y", 0)
	_shift_head.add_theme_constant_override("shadow_outline_size", 22)
	_shift_text = _label("", 21, Color(1, 1, 1, 0.95), v)
	_shift_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shift_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shift_text.custom_minimum_size = Vector2(1000, 0)
	_shadowed(_shift_text, 4)
	_shift_detail = _label("", 19, GOLD, v)
	_shift_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shift_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shift_detail.custom_minimum_size = Vector2(1000, 0)
	_shift_detail.add_theme_font_override("font", _bold)
	_shadowed(_shift_detail, 4)
	_shift.visible = false
	_root.add_child(_shift)
	_shift_lines = Control.new()
	_shift_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shift_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shift_lines.draw.connect(_draw_shift_lines)
	_shift.add_child(_shift_lines)


func _draw_shift_lines() -> void:
	# この Control は帯の内側（余白の内）に置かれるので、帯の左上を原点に直して描く
	var o := -_shift_lines.position
	var w := _shift.size.x
	var h := _shift.size.y
	var c: Color = _shift_col
	for y in [1.0, h - 1.0]:
		# 中央が明るく左右へ消える光の線（細い区間を重ねて描く）
		var n := 24
		for i in n:
			var x0 := w * (0.08 + 0.84 * float(i) / n)
			var x1 := w * (0.08 + 0.84 * float(i + 1) / n)
			var t := absf((float(i) + 0.5) / n - 0.5) * 2.0
			_shift_lines.draw_line(o + Vector2(x0, y), o + Vector2(x1, y), Color(c, (1.0 - t * t) * 0.9 * _shift_line_k), 2.0)
	# 見出しの左右の菱形
	for sx in [w * 0.5 - 330.0 * _shift_line_k, w * 0.5 + 330.0 * _shift_line_k]:
		var cy := 64.0
		_shift_lines.draw_colored_polygon(PackedVector2Array([o + Vector2(sx, cy - 6), o + Vector2(sx + 6, cy), o + Vector2(sx, cy + 6), o + Vector2(sx - 6, cy)]), Color(c, 0.85 * _shift_line_k))


func _draw_banner_line() -> void:
	var k := _banner.modulate.a
	if k <= 0.01:
		return
	var c := _banner.get_theme_color("font_color")
	var w := _banner_line.size.x
	var cy := _banner_line.size.y * 0.5
	var half := 230.0 + 240.0 * _banner_spread
	for side in [-1.0, 1.0]:
		var n := 12
		for i in n:
			var a0 := 300.0 + (half - 300.0 + 260.0) * float(i) / n
			var a1 := 300.0 + (half - 300.0 + 260.0) * float(i + 1) / n
			var t := float(i) / n
			_banner_line.draw_line(Vector2(w * 0.5 + side * a0, cy + 2), Vector2(w * 0.5 + side * a1, cy + 2), Color(c, (1.0 - t) * 0.8 * k), 2.0)


func _build_pause() -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0.03, 0.02, 0.05, 0.72)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-210, -200)
	v.add_theme_constant_override("separation", 16)
	_pause.add_child(v)
	var t := _label("一時停止", 56, GOLD, v)
	t.add_theme_font_override("font", load("res://assets/fonts/NotoSerifJP-Bold.ttf"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(v, "再開", _on_resume)
	_button(v, "ミッションを中断してハブへ", _on_abort)
	var help := _label("WASD 移動 / Shift ダッシュ / Space ジャンプ / 左クリック 攻撃（長押しで強い振り・弓を引く）/ 右クリック 受け・エイム\nR 装填 / 1 持ち替え / 2〜5 爆弾など / F 乗り物 / E 話す・工房 / Tab 時空鞄 / 飛行機: W・S スロットル, マウス 進路", 20, Color(1, 1, 1, 0.7), v)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_death() -> void:
	_death = ColorRect.new()
	(_death as ColorRect).color = Color(0.15, 0.0, 0.0, 0.55)
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	_root.add_child(_death)
	var l := _label("任務失敗", 96, Color(1, 0.4, 0.35), _death)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-400, -80)
	l.custom_minimum_size = Vector2(800, 120)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", load("res://assets/fonts/NotoSerifJP-Bold.ttf"))


func _on_resume() -> void:
	set_paused(false)
	pause_resume.emit()


func _on_abort() -> void:
	set_paused(false)
	pause_abort.emit()


func set_paused(on: bool) -> void:
	_pause.visible = on
	get_tree().paused = on
	Game.input_blocked = on
	Game.lock_mouse(not on)


func show_death(reason: String) -> void:
	_death.visible = true
	(_death.get_child(0) as Label).text = "任務失敗\n" + reason


# ---- 公開 API ----
func toast(t: String, dur := 3.0) -> void:
	_chip(t, Color.WHITE, Color(1, 1, 1, 0.22), false, dur)


## トースト 1 枚（中央寄せの丸い札。ふわっと出て消える）
func _chip(t: String, c: Color, border: Color, bold: bool, dur: float) -> void:
	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(row)
	var l := _label(t, 21, c, row)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_stylebox_override("normal", _pill(Color(0.05, 0.04, 0.09, 0.58), border))
	if bold:
		l.add_theme_font_override("font", _bold)
	_shadowed(l, 3)
	row.modulate.a = 0.0
	var tw := row.create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.18)
	tw.tween_interval(dur)
	tw.tween_property(row, "modulate:a", 0.0, 0.5)
	tw.tween_callback(row.queue_free)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).free()


## 技能が上がったときの知らせ（金色）
func skill_toast(t: String, up := true) -> void:
	_chip(("▲ " if up else "") + t, GOLD if up else Color(0.8, 0.8, 0.8), Color(GOLD, 0.55) if up else Color(1, 1, 1, 0.2), true, 3.0)


func banner(t: String, color := GOLD, dur := 3.0) -> void:
	_banner.text = t
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(1.08, 1.08)
	_banner_spread = 0.0
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_banner_spread, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_method(_set_banner_spread, 1.0, 1.0, 0.6)


## 自由探索の混乱で歴史が変わったときの派手な通知。text の1行目が見出し、detail は設問の ○× 一覧。
## broke_answer = true なら確定解答が崩れた（赤）、false なら青。
func history_shift(text: String, broke_answer: bool, detail := "") -> void:
	_shift_queue.append([text, broke_answer, detail])
	if not _shift_busy:
		_next_shift()


func _set_banner_spread(x: float) -> void:
	_banner_spread = x
	_banner_line.queue_redraw()


func _set_shift_line(x: float) -> void:
	_shift_line_k = x
	_shift_lines.queue_redraw()


func is_history_shift_showing() -> bool:
	return _shift_busy


func _next_shift() -> void:
	if _shift_queue.is_empty():
		_shift_busy = false
		return
	_shift_busy = true
	var item: Array = _shift_queue.pop_front()
	var broke: bool = item[1]
	var col := Color(1, 0.42, 0.38) if broke else CYAN
	_shift_head.text = "歴史が揺らいだ" + ("　―　解答が崩れた" if broke else "")
	_shift_head.add_theme_color_override("font_color", col.lightened(0.15))
	_shift_head.add_theme_color_override("font_shadow_color", Color(col, 0.35))
	_shift_col = col
	_shift_text.text = item[0]
	_shift_detail.text = item[2]
	_shift_detail.visible = item[2] != ""
	_shift.visible = true
	_shift.modulate.a = 0.0
	_shift.pivot_offset = Vector2(760, 60)
	_shift.scale = Vector2(1.0, 0.2)
	_shift_line_k = 0.0
	var tw := _shift.create_tween()
	tw.tween_property(_shift, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_shift, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_shift_line, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(5.5)
	tw.tween_property(_shift, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(_shift, "scale", Vector2(1.04, 0.9), 0.6)
	tw.tween_callback(func():
		_shift.visible = false
		_next_shift())
	# 画面のゆらぎ
	var sm := _shift_fx.material as ShaderMaterial
	sm.set_shader_parameter("tint", Color(1, 0.3, 0.25) if broke else CYAN)
	_shift_fx.visible = true
	var fx := _shift_fx.create_tween()
	fx.tween_method(func(x: float): sm.set_shader_parameter("amount", x), 1.0, 0.0, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fx.tween_callback(func(): _shift_fx.visible = false)
	Sfx.play(get_tree(), Sfx.warp(), -6.0)


func damage_flash(amount: float) -> void:
	_vig = clampf(_vig + amount / 40.0, 0.0, 1.0)


func hit_marker(kill: bool) -> void:
	_hit_t = 0.25
	_hit.add_theme_color_override("font_color", RED if kill else Color.WHITE)


func set_objective(title: String, text: String, counter := "") -> void:
	_obj_title.text = title
	_obj_text.text = text
	_obj_counter.text = counter
	_obj_panel.visible = title != "" or text != ""
	_obj_title.visible = title != ""
	_obj_counter.visible = counter != ""


func set_counter(t: String) -> void:
	_obj_counter.text = t
	_obj_counter.visible = t != ""


func set_timer(sec: float) -> void:
	_timer.text = "" if sec < 0 else "残り %d:%02d" % [int(sec) / 60, int(sec) % 60]
	_timer.visible = sec >= 0


func set_prompt(t: String) -> void:
	_prompt.text = t
	_prompt.visible = t != ""


func dialog(npc_name: String, lines: Array) -> void:
	_dialog_name.text = npc_name
	_dialog_lines = lines
	_dialog_i = 0
	_dialog_text.text = lines[0] if lines.size() > 0 else ""
	_dialog.visible = true
	Game.input_blocked = true


func advance_dialog() -> void:
	if not _dialog.visible:
		return
	_dialog_i += 1
	if _dialog_i >= _dialog_lines.size():
		_dialog.visible = false
		Game.input_blocked = false
		dialog_finished.emit()
	else:
		_dialog_text.text = _dialog_lines[_dialog_i]


func is_dialog_open() -> bool:
	return _dialog.visible


func _input(event: InputEvent) -> void:
	if _dialog.visible:
		var adv: bool = event.is_action_pressed("interact") or event.is_action_pressed("jump") or (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
		if adv:
			get_viewport().set_input_as_handled()
			advance_dialog()
		return
	if event.is_action_pressed("pause") and not _death.visible and get_tree().get_nodes_in_group("game_modal").is_empty():
		get_viewport().set_input_as_handled()
		set_paused(not _pause.visible)


func _process(dt: float) -> void:
	var p = Game.player
	if p and is_instance_valid(p):
		_hp_bar.max_value = p.max_hp
		_hp_bar.value = p.hp
		var fill := _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			fill.bg_color = HP_OK if p.hp > p.max_hp * 0.35 else RED
		var in_plane: bool = p.in_vehicle() and p.vehicle.get("kind") == "plane"
		var arms = p.get("arms")
		if arms != null and not in_plane:
			_ammo.text = arms.ammo_text()
			_weapon.text = arms.weapon_name()
			var dr: float = arms.durability_ratio()
			_dur_bar.visible = dr >= 0.0
			_dur_bar.value = maxf(dr, 0.0)
			(_dur_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.85, 0.8, 0.6) if dr > 0.25 else RED
		else:
			_ammo.text = ("リロード中…" if p.reloading else "%d / ∞" % p.ammo) if not in_plane else "機銃 ∞"
			_weapon.text = ""
			_dur_bar.visible = false
		if Game.profile and Game.world and "era_id" in Game.world:
			_money.text = "所持金 " + CraftDB.money_text(Game.profile.money, str(Game.world.era_id))
		if p.in_vehicle():
			var sp: float = p.vehicle.get_speed() * 3.6
			_veh.text = "%s  %d km/h" % [p.vehicle.get("display_name"), int(sp)]
			if in_plane:
				var w = Game.world
				var alt: float = p.vehicle.global_position.y - (w.height_at(p.vehicle.global_position.x, p.vehicle.global_position.z) if w else 0.0)
				_veh.text += "  高度 %d m  出力 %d%%" % [int(alt), int(p.vehicle.get("throttle") * 100.0)]
				if not p.vehicle.get("airborne"):
					_veh.text += "  （速度を上げてマウスを上へ → 離陸）"
		else:
			_veh.text = "F：乗り物に乗る" if _near_vehicle(p) else ""
	if p and is_instance_valid(p) and p.get("tools") != null:
		_tool.text = "" if p.in_vehicle() else p.tools.hud_text()
	var dm = Destruction.current
	_destr.text = dm.summary_text() if dm != null and is_instance_valid(dm) and (is_free_roam or int(dm.stats["units"]) > 0) else ""
	if Wanted.civil_count > 0:   # 民間人への危害（設定オン時のみ）：数は誇示せず、静かに記す
		_destr.text += ("\n" if _destr.text != "" else "") + "犠牲者 %d人" % Wanted.civil_count
	var s := Wanted.stars()
	_stars.text = "★".repeat(s) + "☆".repeat(5 - s) if s > 0 else ""
	_hit_t = maxf(0.0, _hit_t - dt)
	_hit.modulate.a = _hit_t / 0.25
	_vig = maxf(0.0, _vig - dt * 0.8)
	var low: float = 0.0
	if p and is_instance_valid(p):
		low = clampf(1.0 - p.hp / (p.max_hp * 0.4), 0.0, 1.0) * 0.5
	(_vignette.material as ShaderMaterial).set_shader_parameter("amount", maxf(_vig, low))
	_cross.queue_redraw()
	_marker_layer.queue_redraw()
	_compass.queue_redraw()


func _near_vehicle(p) -> bool:
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.get("driver") == null and (v as Node3D).global_position.distance_to(p.global_position) < 5.0:
			return true
	return false


func _draw_cross() -> void:
	var p = Game.player
	var in_plane: bool = p != null and is_instance_valid(p) and p.in_vehicle() and p.vehicle.get("kind") == "plane"
	if in_plane:
		_cross.draw_arc(Vector2.ZERO, 26, 0, TAU, 48, Color(1, 1, 1, 0.8), 2.0)
		_cross.draw_circle(Vector2.ZERO, 3, Color(1, 1, 1, 0.9))
		# 機首方向
		var cam := get_viewport().get_camera_3d()
		if cam:
			var nose: Vector3 = p.vehicle.global_position - p.vehicle.global_basis.z * 300.0
			if (cam.global_transform.affine_inverse() * nose).z < -1.0:
				var sp := cam.unproject_position(nose) - get_viewport().get_visible_rect().size * 0.5
				_cross.draw_rect(Rect2(sp - Vector2(10, 10), Vector2(20, 20)), CYAN, false, 2.0)
		return
	var gap := 7.0
	var ln := 10.0
	var c := Color(1, 1, 1, 0.9)
	var arms = p.get("arms") if p != null and is_instance_valid(p) else null
	if arms != null:
		var k: String = arms.kind()
		if k == "bow":
			var f: float = arms.draw_fraction()
			if f > 0.0:
				_cross.draw_arc(Vector2.ZERO, 22, -PI / 2, -PI / 2 + TAU * f, 32, GOLD if f >= 1.0 else Color(1, 1, 1, 0.8), 3.0)
		elif k in ["melee", "fists"]:
			_cross.draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.8))
			if arms.blocking:
				_cross.draw_arc(Vector2.ZERO, 18, PI * 0.15, PI * 0.85, 16, CYAN, 3.0)
			return
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_cross.draw_line(d * gap, d * (gap + ln), Color(0, 0, 0, 0.6), 4.0)
		_cross.draw_line(d * gap, d * (gap + ln), c, 2.0)
	_cross.draw_circle(Vector2.ZERO, 1.6, c)


func _draw_markers() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if target_world != null:
		_draw_marker(cam, target_world, vs, GOLD, target_label, true)
	for e in extra_markers:
		if is_instance_valid(e) and not e.get("dead"):
			_draw_marker(cam, (e as Node3D).global_position + Vector3.UP * 2.2, vs, RED, "", false)


func _draw_marker(cam: Camera3D, wp: Vector3, vs: Vector2, c: Color, text: String, big: bool) -> void:
	var local := cam.global_transform.affine_inverse() * wp
	var behind := local.z > -0.2
	var margin := 60.0
	var center := vs * 0.5
	var off := false
	var sp := center
	if behind:
		var d2 := Vector2(local.x, -local.y)
		sp = center + (d2.normalized() if d2.length() > 0.001 else Vector2.DOWN) * vs.length()
	else:
		sp = cam.unproject_position(wp)
	if behind or sp.x < margin or sp.y < margin or sp.x > vs.x - margin or sp.y > vs.y - margin:
		off = true
		var d := (sp - center)
		var k := minf((vs.x * 0.5 - margin) / maxf(absf(d.x), 0.001), (vs.y * 0.5 - margin) / maxf(absf(d.y), 0.001))
		sp = center + d * minf(k, 1.0)
	var r := 14.0 if big else 7.0
	var pts := PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
	_marker_layer.draw_colored_polygon(pts, Color(c, 0.85))
	if off:
		var dir := (sp - center).normalized()
		_marker_layer.draw_line(sp + dir * (r + 2), sp + dir * (r + 16), c, 3.0)
	if big:
		var dist := cam.global_position.distance_to(wp)
		var font := _bold
		var s := "%s  %dm" % [text, int(dist)]
		_marker_layer.draw_string_outline(font, sp + Vector2(-160, -24), s, HORIZONTAL_ALIGNMENT_CENTER, 320, 22, 6, Color(0, 0, 0, 0.9))
		_marker_layer.draw_string(font, sp + Vector2(-160, -24), s, HORIZONTAL_ALIGNMENT_CENTER, 320, 22, Color.WHITE)


func _draw_compass() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := _compass.size.x
	var fwd := -cam.global_basis.z
	var heading := atan2(fwd.x, -fwd.z)   # 北 = -Z
	var font := _bold
	var span := PI / 2.2
	var ink := Color(0.03, 0.02, 0.06, 0.55)
	# 細い基線（中央が濃く、左右へ消える）
	var n := 20
	for i in n:
		var t := absf((float(i) + 0.5) / n - 0.5) * 2.0
		_compass.draw_line(Vector2(w * float(i) / n, 30), Vector2(w * float(i + 1) / n, 30), Color(1, 1, 1, (1.0 - t * t) * 0.55), 1.5)
	# 目盛り（15° ごと）
	for k in 24:
		var a := wrapf(k * PI / 12.0 - heading, -PI, PI)
		if absf(a) < span:
			var x := w * 0.5 + a / span * w * 0.5
			var fade := 1.0 - absf(a) / span
			var major := k % 6 == 0
			var h := 9.0 if major else 5.0
			_compass.draw_line(Vector2(x, 30 - h), Vector2(x, 30), Color(1, 1, 1, 0.7 * fade), 1.5 if major else 1.0)
	var marks := {"北": 0.0, "東": PI / 2, "南": PI, "西": -PI / 2}
	for k in marks:
		var a: float = wrapf(marks[k] - heading, -PI, PI)
		if absf(a) < span:
			var x := w * 0.5 + a / span * w * 0.5
			var fade := 1.0 - absf(a) / span * 0.7
			var col := Color(1.0, 0.45, 0.4, fade) if k == "北" else Color(1, 1, 1, fade)
			_compass.draw_string_outline(font, Vector2(x - 12, 18), k, HORIZONTAL_ALIGNMENT_CENTER, 24, 18, 5, ink)
			_compass.draw_string(font, Vector2(x - 12, 18), k, HORIZONTAL_ALIGNMENT_CENTER, 24, 18, col)
	# 正面の印
	_compass.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 33), Vector2(w * 0.5 - 4, 39), Vector2(w * 0.5 + 4, 39)]), Color(1, 1, 1, 0.8))
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	for cname in compass_points:
		var to: Vector3 = compass_points[cname] - p.global_position
		var a2 := wrapf(atan2(to.x, -to.z) - heading, -PI, PI)
		if absf(a2) < span:
			var x2 := w * 0.5 + a2 / span * w * 0.5
			var is_t: bool = target_world != null and (compass_points[cname] as Vector3).distance_to(target_world) < 5.0
			_compass.draw_circle(Vector2(x2, 30), 3.5 if is_t else 2.5, GOLD if is_t else Color(1, 1, 1, 0.6))
	if target_world != null:
		var to2: Vector3 = target_world - p.global_position
		var a3 := wrapf(atan2(to2.x, -to2.z) - heading, -PI, PI)
		var x3 := w * 0.5 + clampf(a3 / span, -1, 1) * w * 0.5
		_compass.draw_colored_polygon(PackedVector2Array([Vector2(x3, 22), Vector2(x3 - 6, 14), Vector2(x3 + 6, 14)]), GOLD)

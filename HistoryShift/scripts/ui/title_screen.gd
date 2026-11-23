extends Control
## タイトル画面。背景は Flow が 3D バックドロップ（Session.start_backdrop）を出すか、無ければ動く 2D 背景。

const EraPicker := preload("res://scripts/ui/era_picker.gd")

signal new_game
signal continue_game
signal free_roam(era_id: String)
signal open_settings
signal open_credits
signal quit_game

var has_backdrop := false
var backdrop_era := ""
var _era_label: Label
var _menu: VBoxContainer
var _logo_box: VBoxContainer
var _dial: Control


func _ready() -> void:
	theme = JSUI.theme()
	JSUI.full_rect(self)
	if has_backdrop:
		# 3D の上に左から墨のグラデーションを敷いて文字を読みやすく
		var g := TextureRect.new()
		JSUI.full_rect(g)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var grad := Gradient.new()
		grad.set_color(0, Color(JSUI.INK, 0.94))
		grad.set_color(1, Color(JSUI.INK, 0.0))
		grad.add_point(0.45, Color(JSUI.INK, 0.72))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(1, 0)
		g.texture = gt
		g.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(g)
	else:
		add_child(JSUI.background("title"))
	_dial = TimeDial.new()
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dial.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_dial.position = Vector2(-760, -380)
	_dial.custom_minimum_size = Vector2(760, 760)
	_dial.size = Vector2(760, 760)
	_dial.modulate.a = 0.55 if has_backdrop else 0.9
	add_child(_dial)

	var m := JSUI.margin(0)
	JSUI.full_rect(m)
	m.add_theme_constant_override("margin_left", 150)
	m.add_theme_constant_override("margin_top", 80)
	m.add_theme_constant_override("margin_bottom", 56)
	add_child(m)
	var col := JSUI.vbox(0)
	m.add_child(col)

	# ---- ロゴ
	_logo_box = JSUI.vbox(0)
	col.add_child(_logo_box)
	var eyebrow := JSUI.label("TIME-ALTERING  HISTORY  EXAMINATION", 20, JSUI.CYAN, _spaced(JSUI.sans_bold(), 6))
	_logo_box.add_child(eyebrow)
	_logo_box.add_child(JSUI.gap(14))
	var top := JSUI.hbox(22)
	_logo_box.add_child(top)
	var seal := _seal()
	top.add_child(seal)
	var kv := JSUI.vbox(-6)
	top.add_child(kv)
	var sub := JSUI.label("時空改変", 58, JSUI.SHU, _spaced(JSUI.serif_bold(), 12))
	sub.add_theme_constant_override("outline_size", 0)
	kv.add_child(sub)
	var main := JSUI.label("共通テスト日本史", 112, Color.WHITE, _spaced(JSUI.serif_bold(), 4))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 4)
	main.add_theme_constant_override("shadow_outline_size", 10)
	main.add_theme_color_override("font_shadow_color", Color(JSUI.CYAN, 0.25))
	kv.add_child(main)
	var en := JSUI.hbox(18)
	_logo_box.add_child(en)
	en.add_child(JSUI.gap(150))
	var bar1 := ColorRect.new(); bar1.color = JSUI.GOLD; bar1.custom_minimum_size = Vector2(70, 3); bar1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	en.add_child(bar1)
	en.add_child(JSUI.label("JIDAI SHIFT", 50, JSUI.GOLD, _spaced(JSUI.sans_bold(), 16)))
	var bar2 := ColorRect.new(); bar2.color = JSUI.GOLD; bar2.custom_minimum_size = Vector2(70, 3); bar2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	en.add_child(bar2)
	_logo_box.add_child(JSUI.gap(18))
	var tag := JSUI.label("解答は、もう確定した。間違えたなら――歴史のほうを書き換えろ。", 27, Color(JSUI.TEXT, 0.85), JSUI.serif())
	var tagrow := JSUI.hbox(0)
	tagrow.add_child(JSUI.gap(150))
	tagrow.add_child(tag)
	_logo_box.add_child(tagrow)

	col.add_child(JSUI.spacer(false))

	# ---- メニュー
	_menu = JSUI.vbox(4)
	col.add_child(_menu)
	var can_continue: bool = HistoryState.has_save() and Game.state.exam_submitted
	if can_continue:
		_add_item("つづきから", "採点ハブへ戻り、歴史改変を続ける", func(): continue_game.emit(), true)
	_add_item("はじめから", "新しく共通テストを受験する", _on_new, not can_continue)
	_add_item("自由探索", "ミッションなしで時代を歩く", func(): EraPicker.open(self, func(id): free_roam.emit(id)))
	_add_item("設定", "画質・感度・音量", func(): open_settings.emit())
	_add_item("クレジット", "素材とライセンス", func(): open_credits.emit())
	_add_item("終了", "", func(): quit_game.emit())

	# ---- フッター
	var foot := JSUI.label("※ 収録問題はすべて本作オリジナルです（実際の大学入学共通テストの過去問ではありません）", 18, JSUI.DIM)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position += Vector2(-40, -28)
	foot.add_theme_constant_override("outline_size", 6)
	foot.add_theme_color_override("font_outline_color", Color(JSUI.INK, 0.8))
	add_child(foot)
	_era_label = JSUI.label("", 20, Color(JSUI.CYAN, 0.8), JSUI.sans_bold())
	_era_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_era_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_era_label.position += Vector2(-48, 40)
	_era_label.add_theme_constant_override("outline_size", 8)
	_era_label.add_theme_color_override("font_outline_color", Color(JSUI.INK, 0.85))
	add_child(_era_label)
	set_backdrop_era(backdrop_era)

	# 登場演出
	JSUI.fade_in(eyebrow, 0.6, 0.1)
	JSUI.fade_in(top, 0.8, 0.25)
	JSUI.fade_in(en, 0.7, 0.6)
	JSUI.fade_in(tagrow, 0.7, 0.85)
	var i := 0
	for c in _menu.get_children():
		JSUI.fade_in(c, 0.35, 1.0 + i * 0.07)
		i += 1


func set_backdrop_era(era_id: String) -> void:
	backdrop_era = era_id
	if _era_label == null:
		return
	var era := Game.db.get_era(era_id) if era_id != "" else {}
	_era_label.text = ("◆ 現在の時空座標：%s" % era["eraName"]) if not era.is_empty() else ""


func _on_new() -> void:
	if HistoryState.has_save() and Game.state.exam_submitted:
		JSUI.confirm(self, "はじめから受験する", "現在の歴史改変の記録と答案はすべて失われ、世界は本来の史実に戻ります。よろしいですか？", "はじめから", "やめる", func(): new_game.emit(), true)
	else:
		new_game.emit()


func _add_item(text: String, desc: String, cb: Callable, focus := false) -> void:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(560, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := StyleBoxFlat.new(); n.bg_color = Color(0, 0, 0, 0); n.set_content_margin_all(0)
	var h := StyleBoxFlat.new(); h.bg_color = Color(JSUI.CYAN, 0.10); h.border_width_left = 5; h.border_color = JSUI.CYAN
	h.corner_radius_top_right = 10; h.corner_radius_bottom_right = 10; h.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	var row := JSUI.hbox(20)
	JSUI.full_rect(row)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(JSUI.gap(18))
	var t := JSUI.label(text, 33, Color.WHITE, JSUI.serif_bold())
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.custom_minimum_size = Vector2(200, 0)
	t.size_flags_vertical = Control.SIZE_FILL
	row.add_child(t)
	var d := JSUI.label(desc, 20, JSUI.MUTED)
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	d.size_flags_vertical = Control.SIZE_FILL
	row.add_child(d)
	for c in row.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hl := func(on: bool):
		t.add_theme_color_override("font_color", JSUI.CYAN if on else Color.WHITE)
		d.add_theme_color_override("font_color", JSUI.TEXT if on else JSUI.MUTED)
		var tw := b.create_tween()
		tw.tween_property(row, "position:x", 14.0 if on else 0.0, 0.12)
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): UISfx.play("hover"); hl.call(true))
	b.focus_exited.connect(func(): hl.call(false))
	b.pressed.connect(func(): UISfx.play("click"); cb.call())
	_menu.add_child(b)
	if focus:
		b.call_deferred("grab_focus")


func _seal() -> Control:
	var p := JSUI.panel(JSUI.sb(JSUI.SHU, 10, 0, Color.TRANSPARENT, 10, 0))
	p.custom_minimum_size = Vector2(128, 128)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var inner := JSUI.panel(JSUI.sb(Color.TRANSPARENT, 6, 3, Color(1, 1, 1, 0.85), 0, 0))
	p.add_child(inner)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.set_content_margin_all(8)
	var l := JSUI.label("改", 84, Color.WHITE, JSUI.serif_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.add_child(l)
	p.pivot_offset = Vector2(64, 64)
	p.rotation = deg_to_rad(-6)
	return p


static func _spaced(f: Font, spacing: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = f
	fv.spacing_glyph = spacing
	return fv


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()


## 背景の時計の文字盤（ゆっくり回る目盛り）
class TimeDial extends Control:
	var t := 0.0
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.48
		draw_arc(c, r, 0, TAU, 160, Color(JSUI.CYAN, 0.25), 2.0, true)
		draw_arc(c, r * 0.82, 0, TAU, 160, Color(JSUI.GOLD, 0.18), 1.5, true)
		draw_arc(c, r * 0.55, t * 0.3, t * 0.3 + PI * 1.2, 80, Color(JSUI.SHU, 0.35), 3.0, true)
		for i in 120:
			var a := -t * 0.05 + TAU * i / 120.0
			var long := i % 10 == 0
			var p1 := c + Vector2.from_angle(a) * r
			var p2 := c + Vector2.from_angle(a) * (r - (26.0 if long else 10.0))
			draw_line(p1, p2, Color(JSUI.CYAN, 0.5 if long else 0.22), 2.0 if long else 1.0, true)
		for i in 12:
			var a := t * 0.08 + TAU * i / 12.0
			draw_circle(c + Vector2.from_angle(a) * r * 0.82, 4.0, Color(JSUI.GOLD, 0.5))
		var hand := Vector2.from_angle(-PI / 2 + t * 0.6) * r * 0.7
		draw_line(c, c + hand, Color(JSUI.CYAN, 0.45), 2.0, true)
		draw_line(c, c + Vector2.from_angle(-PI / 2 - t * 0.1) * r * 0.45, Color(JSUI.GOLD, 0.45), 4.0, true)
		draw_circle(c, 6.0, Color(JSUI.CYAN, 0.7))

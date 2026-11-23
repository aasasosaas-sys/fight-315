extends Control
## エンディング：compose_ending() のタイトルと本文をタイプライター＋スクロールで見せる。

signal to_title
signal replay

const CPS := 38.0   # 1秒あたりの文字数

var _rt: RichTextLabel
var _scroll: ScrollContainer
var _typing := false
var _chars := 0.0
var _total := 0
var _bottom: Control


func _ready() -> void:
	theme = JSUI.theme()
	JSUI.full_rect(self)
	add_child(JSUI.background("ending"))
	var ending := Game.state.compose_ending()
	var m := JSUI.margin(60)
	JSUI.full_rect(m)
	m.add_theme_constant_override("margin_left", 260)
	m.add_theme_constant_override("margin_right", 260)
	add_child(m)
	var v := JSUI.vbox(18)
	m.add_child(v)
	var eb := JSUI.label("ENDING  ―  令和八年、この世界の日本", 22, JSUI.GOLD, JSUI.sans_bold())
	eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(eb)
	var title := JSUI.label(ending[0], 92, Color.WHITE, JSUI.serif_bold())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(JSUI.GOLD, 0.22))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 5)
	v.add_child(title)
	var line := JSUI.hline(Color(JSUI.GOLD, 0.5), 2)
	v.add_child(line)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_rt = RichTextLabel.new()
	_rt.bbcode_enabled = true
	_rt.fit_content = true
	_rt.scroll_active = false
	_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rt.add_theme_font_override("normal_font", JSUI.serif())
	_rt.add_theme_font_override("bold_font", JSUI.serif_bold())
	_rt.add_theme_font_size_override("normal_font_size", 30)
	_rt.add_theme_font_size_override("bold_font_size", 32)
	_rt.add_theme_color_override("default_color", JSUI.TEXT)
	_rt.add_theme_constant_override("line_separation", 6)
	_rt.text = _to_bbcode(ending[1])
	_rt.visible_characters = 0
	_scroll.add_child(_rt)
	# 統計 + ボタン
	_bottom = JSUI.vbox(18)
	v.add_child(_bottom)
	var stats := JSUI.hbox(60)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	var altered := Game.db.questions.filter(func(q): return Game.state.is_altered(q)).size()
	stats.add_child(_stat("書き換えた史実", "%d / %d" % [altered, Game.db.questions.size()]))
	stats.add_child(_stat("改変数", str(Game.state.alterations)))
	stats.add_child(_stat("修復数", str(Game.state.restorations)))
	stats.add_child(_stat("最終得点", "%d点" % Game.state.score()))
	_bottom.add_child(stats)
	var row := JSUI.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := JSUI.button("タイトルへ", "ghost", 26, 260)
	t.pressed.connect(func(): UISfx.play("back"); to_title.emit())
	row.add_child(t)
	var again := JSUI.button("もう一度（リセット）", "gold", 26, 340)
	again.pressed.connect(func():
		JSUI.confirm(self, "もう一度受験する", "この世界の記録をすべて消去し、本来の史実に戻した上で新しく受験します。", "リセットして受験", "やめる", func(): replay.emit(), true))
	row.add_child(again)
	_bottom.add_child(row)
	_bottom.modulate.a = 0.0
	# 演出
	title.modulate.a = 0.0
	eb.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(eb, "modulate:a", 1.0, 0.8)
	tw.tween_property(title, "modulate:a", 1.0, 1.2)
	tw.tween_callback(func(): _typing = true)
	_total = _rt.get_total_character_count()
	UISfx.play("success")


func _stat(title: String, value: String) -> Control:
	var v := JSUI.vbox(0)
	var a := JSUI.label(title, 19, JSUI.MUTED)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var b := JSUI.label(value, 38, JSUI.GOLD, JSUI.serif_bold())
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	return v


static func _to_bbcode(text: String) -> String:
	var out: PackedStringArray = []
	for ln in text.split("\n"):
		var esc := ln.replace("[", "[lb]")
		if ln.begins_with("■"):
			out.append("[color=#F2C75A][b]%s[/b][/color]" % esc)
		elif ln.begins_with("・"):
			out.append("[indent]%s[/indent]" % esc)
		else:
			out.append(esc)
	return "\n".join(out)


func _process(delta: float) -> void:
	if not _typing:
		return
	_total = _rt.get_total_character_count()
	_chars += delta * CPS
	_rt.visible_characters = int(_chars)
	var ratio := clampf(_chars / maxf(_total, 1), 0.0, 1.0)
	var target := _rt.size.y * ratio - _scroll.size.y * 0.6
	_scroll.scroll_vertical = int(maxf(target, 0.0))
	if _chars >= _total:
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	_rt.visible_characters = -1
	if _bottom.modulate.a < 1.0:
		create_tween().tween_property(_bottom, "modulate:a", 1.0, 0.6)


func _gui_input(event: InputEvent) -> void:
	if _typing and event is InputEventMouseButton and event.pressed:
		_finish_typing()


func _unhandled_input(event: InputEvent) -> void:
	if _typing and (event is InputEventKey and event.pressed):
		_finish_typing()
		accept_event()

extends Control
## 共通テスト（試験冊子 + マークシート）。提出で解答が確定する。

signal submitted

const TIME_LIMIT := 90 * 60.0

var index := 0
var time_left := TIME_LIMIT
var running := false
var show_intro := true

var _qs: Array = []
var _num_l: Label
var _era_box: HBoxContainer
var _text_l: Label
var _choices_box: VBoxContainer
var _choice_cards: Array = []
var _timer_l: Label
var _timer_panel: PanelContainer
var _count_l: Label
var _page_l: Label
var _prev_b: Button
var _next_b: Button
var _rows: Array = []
var _scroll: ScrollContainer
var _paper_v: VBoxContainer
var _done := false


func _ready() -> void:
	theme = JSUI.theme()
	JSUI.full_rect(self)
	_qs = Game.db.questions
	add_child(JSUI.background("desk"))
	var m := JSUI.margin(36)
	JSUI.full_rect(m)
	m.add_theme_constant_override("margin_left", 48)
	m.add_theme_constant_override("margin_right", 48)
	add_child(m)
	var v := JSUI.vbox(22)
	m.add_child(v)
	v.add_child(_top_bar())
	var body := JSUI.hbox(28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	body.add_child(_paper())
	body.add_child(_sheet())
	_show_q(0, false)
	_update_timer()
	if show_intro:
		call_deferred("_intro")
	else:
		running = true


# ------------------------------------------------------------------ 構築
func _top_bar() -> Control:
	var bar := JSUI.hbox(20)
	var seal := JSUI.pill("日本史", JSUI.SHU, Color.WHITE, 22)
	bar.add_child(seal)
	var tv := JSUI.vbox(-4)
	tv.add_child(JSUI.label("令和8年度　大学入学共通テスト（時空改変版）", 18, JSUI.MUTED))
	tv.add_child(JSUI.label("日本史探究　― JIDAI SHIFT ―", 34, Color.WHITE, JSUI.serif_bold()))
	bar.add_child(tv)
	bar.add_child(JSUI.spacer())
	_count_l = JSUI.label("", 24, JSUI.TEXT, JSUI.sans_bold())
	_count_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_count_l)
	bar.add_child(JSUI.gap(12))
	_timer_panel = JSUI.panel(JSUI.sb(Color(JSUI.INK, 0.9), 14, 2, Color(JSUI.CYAN, 0.45), 8, 10))
	var st: StyleBoxFlat = _timer_panel.get_theme_stylebox("panel")
	st.content_margin_left = 22; st.content_margin_right = 22
	var th := JSUI.hbox(14)
	_timer_panel.add_child(th)
	var tl := JSUI.label("残り時間", 20, JSUI.MUTED)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(tl)
	_timer_l = JSUI.label("90:00", 40, JSUI.CYAN, JSUI.sans_bold())
	th.add_child(_timer_l)
	bar.add_child(_timer_panel)
	return bar


func _paper() -> Control:
	var paper := JSUI.panel(JSUI.sb(JSUI.PAPER, 6, 0, Color.TRANSPARENT, 26, 0))
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pm := JSUI.margin(0)
	pm.add_theme_constant_override("margin_left", 72)
	pm.add_theme_constant_override("margin_right", 72)
	pm.add_theme_constant_override("margin_top", 36)
	pm.add_theme_constant_override("margin_bottom", 30)
	paper.add_child(pm)
	var pv := JSUI.vbox(14)
	pm.add_child(pv)
	# 見出し
	var head := JSUI.hbox(22)
	pv.add_child(head)
	var numbox := JSUI.panel(JSUI.sb(JSUI.PAPER_INK, 4, 0, Color.TRANSPARENT, 0, 6))
	var nst: StyleBoxFlat = numbox.get_theme_stylebox("panel")
	nst.content_margin_left = 18; nst.content_margin_right = 18
	_num_l = JSUI.label("", 40, JSUI.PAPER, JSUI.serif_bold())
	numbox.add_child(_num_l)
	numbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(numbox)
	_era_box = JSUI.hbox(0)
	_era_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_era_box)
	head.add_child(JSUI.spacer())
	_page_l = JSUI.label("", 22, Color(JSUI.PAPER_INK, 0.55), JSUI.serif())
	_page_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_page_l)
	pv.add_child(JSUI.hline(Color(JSUI.PAPER_INK, 0.8), 3))
	# 本文 + 選択肢（長い問題に備えてスクロール）
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(_scroll)
	_paper_v = JSUI.vbox(18)
	_paper_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_paper_v)
	_paper_v.add_child(JSUI.gap(4))
	_text_l = JSUI.label("", 27, JSUI.PAPER_INK, JSUI.serif(), true)
	_text_l.add_theme_constant_override("line_spacing", 7)
	_text_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paper_v.add_child(_text_l)
	_choices_box = JSUI.vbox(9)
	_paper_v.add_child(_choices_box)
	for i in 4:
		var card := _choice_card(i)
		_choices_box.add_child(card)
		_choice_cards.append(card)
	# フッター
	pv.add_child(JSUI.hline(Color(JSUI.PAPER_INK, 0.15), 2))
	var foot := JSUI.hbox(16)
	pv.add_child(foot)
	_prev_b = JSUI.button("◀  前の問題", "ghost", 24, 220)
	_paper_button(_prev_b)
	_prev_b.pressed.connect(func(): _go(index - 1))
	foot.add_child(_prev_b)
	foot.add_child(JSUI.spacer())
	var hint := JSUI.label("キー  1〜4：選択　←/→：移動", 20, Color(JSUI.PAPER_INK, 0.5))
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	foot.add_child(JSUI.spacer())
	_next_b = JSUI.button("次の問題  ▶", "ghost", 24, 220)
	_paper_button(_next_b)
	_next_b.pressed.connect(func(): _go(index + 1))
	foot.add_child(_next_b)
	return paper


func _paper_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", JSUI.sb(JSUI.PAPER2, 10, 2, Color(JSUI.PAPER_INK, 0.25), 0, 12))
	b.add_theme_stylebox_override("hover", JSUI.sb(Color.WHITE, 10, 2, JSUI.SHU, 4, 12))
	b.add_theme_stylebox_override("pressed", JSUI.sb(JSUI.PAPER2, 10, 2, JSUI.SHU, 0, 12))
	b.add_theme_stylebox_override("disabled", JSUI.sb(Color(JSUI.PAPER2, 0.5), 10, 1, Color(JSUI.PAPER_INK, 0.1), 0, 12))
	b.add_theme_stylebox_override("focus", JSUI.sb(Color.TRANSPARENT, 10, 2, Color(JSUI.SHU, 0.5), 0, 12))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, JSUI.PAPER_INK)
	b.add_theme_color_override("font_disabled_color", Color(JSUI.PAPER_INK, 0.3))


func _choice_card(i: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := JSUI.hbox(22)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	var bub := JSUI.label(JSUI.circled(i), 34, JSUI.PAPER_INK, JSUI.serif_bold())
	bub.custom_minimum_size = Vector2(52, 0)
	bub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bub.size_flags_vertical = Control.SIZE_FILL
	bub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bub)
	var t := JSUI.label("", 25, JSUI.PAPER_INK, JSUI.serif(), true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_vertical = Control.SIZE_FILL
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	var tag := JSUI.pill("選択中", JSUI.SHU, Color.WHITE, 18)
	tag.visible = false
	h.add_child(tag)
	card.set_meta("bubble", bub)
	card.set_meta("text", t)
	card.set_meta("tag", tag)
	card.set_meta("hover", false)
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(i))
	card.mouse_entered.connect(func(): card.set_meta("hover", true); _style_choices(); UISfx.play("hover"))
	card.mouse_exited.connect(func(): card.set_meta("hover", false); _style_choices())
	return card


func _sheet() -> Control:
	var col := JSUI.vbox(18)
	col.custom_minimum_size = Vector2(500, 0)
	var sheet := JSUI.panel(JSUI.sb(Color("#FBF6EC"), 8, 0, Color.TRANSPARENT, 20, 18))
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sheet)
	var sv := JSUI.vbox(10)
	sheet.add_child(sv)
	var sh := JSUI.hbox(10)
	sv.add_child(sh)
	sh.add_child(JSUI.label("解答用紙", 28, JSUI.SHU_DARK, JSUI.serif_bold()))
	var mk := JSUI.label("マークシート", 18, Color(JSUI.SHU_DARK, 0.7))
	mk.size_flags_vertical = Control.SIZE_SHRINK_END
	sh.add_child(mk)
	sh.add_child(JSUI.spacer())
	var lg := JSUI.label("● 解答済　○ 未解答", 16, Color(JSUI.SHU_DARK, 0.7))
	lg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(lg)
	sv.add_child(JSUI.hline(Color(JSUI.SHU, 0.6), 2))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)
	var half := ceili(_qs.size() / 2.0)
	for c in 2:
		var colv := JSUI.vbox(0)
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(colv)
		for k in range(c * half, mini((c + 1) * half, _qs.size())):
			var row := MarkRow.new()
			row.number = k + 1
			row.custom_minimum_size = Vector2(0, 30)
			row.size_flags_vertical = Control.SIZE_EXPAND_FILL
			row.size_flags_stretch_ratio = 1.0
			row.picked.connect(func(n: int): _go(n - 1))
			colv.add_child(row)
			_rows.append(row)
	var submit := JSUI.button("答案を提出する", "primary", 30)
	submit.custom_minimum_size = Vector2(0, 84)
	submit.add_theme_font_override("font", JSUI.serif_bold())
	submit.pressed.connect(_ask_submit)
	col.add_child(submit)
	return col


# ------------------------------------------------------------------ 表示
func _show_q(i: int, anim := true) -> void:
	index = clampi(i, 0, _qs.size() - 1)
	var q: Dictionary = _qs[index]
	_num_l.text = "問 %d" % (index + 1)
	for c in _era_box.get_children():
		c.queue_free()
	var era: Dictionary = q["era"]
	_era_box.add_child(JSUI.pill(String(era["eraName"]).split("（")[0], JSUI.era_color(era["eraId"]).darkened(0.25), Color.WHITE, 20))
	_page_l.text = "%d / %d" % [index + 1, _qs.size()]
	_text_l.text = q["text"]
	for k in 4:
		var t: Label = _choice_cards[k].get_meta("text")
		t.text = q["choices"][k]
	_prev_b.disabled = index == 0
	_next_b.disabled = index == _qs.size() - 1
	_style_choices()
	_refresh_sheet()
	_scroll.scroll_vertical = 0
	if anim:
		_paper_v.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_paper_v, "modulate:a", 1.0, 0.18)


func _style_choices() -> void:
	var a := Game.state.answer(_qs[index])
	for k in 4:
		var card: PanelContainer = _choice_cards[k]
		var sel := a == k
		var hov: bool = card.get_meta("hover")
		var st: StyleBoxFlat
		if sel:
			st = JSUI.sb(Color("#FBE3DC"), 10, 3, JSUI.SHU, 6, 18)
		elif hov:
			st = JSUI.sb(Color.WHITE, 10, 2, Color(JSUI.SHU, 0.55), 4, 18)
		else:
			st = JSUI.sb(Color(1, 1, 1, 0.35), 10, 1, Color(JSUI.PAPER_INK, 0.14), 0, 18)
		st.content_margin_left = 20; st.content_margin_right = 20
		st.content_margin_top = 12; st.content_margin_bottom = 12
		card.add_theme_stylebox_override("panel", st)
		var bub: Label = card.get_meta("bubble")
		bub.add_theme_color_override("font_color", JSUI.SHU if sel else JSUI.PAPER_INK)
		(card.get_meta("tag") as Control).visible = sel


func _refresh_sheet() -> void:
	var n := 0
	for k in _qs.size():
		var a := Game.state.answer(_qs[k])
		if a >= 0:
			n += 1
		var row: MarkRow = _rows[k]
		row.answer = a
		row.current = k == index
		row.queue_redraw()
	_count_l.text = "解答済  %d / %d" % [n, _qs.size()]


func _select(k: int) -> void:
	if _done:
		return
	Game.state.set_answer(_qs[index], k)
	UISfx.play("mark")
	_style_choices()
	_refresh_sheet()
	var card: Control = _choice_cards[k]
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.985, 0.985)
	create_tween().tween_property(card, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK)


func _go(i: int) -> void:
	if i < 0 or i >= _qs.size() or i == index:
		return
	UISfx.play("tick")
	_show_q(i)


func _unanswered() -> int:
	var n := 0
	for q in _qs:
		if Game.state.answer(q) < 0:
			n += 1
	return n


# ------------------------------------------------------------------ タイマー・入力
func _process(delta: float) -> void:
	if not running or _done:
		return
	time_left = maxf(time_left - delta, 0.0)
	_update_timer()
	if time_left <= 0.0:
		_done = true
		JSUI.toast(self, "試験時間終了。答案を回収します。", JSUI.SHU)
		get_tree().create_timer(1.2).timeout.connect(func(): submitted.emit())


func _update_timer() -> void:
	var s := ceili(time_left)
	_timer_l.text = "%02d:%02d" % [s / 60, s % 60]
	var warn := time_left < 300.0
	_timer_l.add_theme_color_override("font_color", JSUI.SHU if warn else JSUI.CYAN)
	if warn:
		_timer_l.modulate.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 160.0)


func _input(event: InputEvent) -> void:
	if not running or _done or not is_visible_in_tree() or JSUI.modal_open(self):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			_select(k - KEY_1); accept_event()
		elif k >= KEY_KP_1 and k <= KEY_KP_4:
			_select(k - KEY_KP_1); accept_event()
		elif k == KEY_LEFT:
			_go(index - 1); accept_event()
		elif k == KEY_RIGHT:
			_go(index + 1); accept_event()


func _intro() -> void:
	var r := JSUI.modal(self, 960, "受験上の注意")
	var overlay: Control = r[0]
	var v: VBoxContainer = r[1]
	var items := [
		"この試験は全%d問、各問4つの選択肢（①〜④）から1つを選ぶ形式です。" % _qs.size(),
		"試験時間は90分。時間切れになると答案は自動的に回収されます。",
		"提出した解答は変更できません。未解答の設問は、提出時に時空の揺らぎによってランダムにマークされます。",
		"採点は「提出後の世界の史実」に対して行われます。間違えた問題は……過去へ跳んで、史実のほうをあなたの解答に合わせてください。",
	]
	for i in items.size():
		var h := JSUI.hbox(14)
		var n := JSUI.label(JSUI.circled(i), 26, JSUI.GOLD, JSUI.serif_bold())
		n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(n)
		var l := JSUI.label(items[i], 25, JSUI.TEXT, null, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		v.add_child(h)
	v.add_child(JSUI.gap(6))
	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var go := JSUI.button("試験開始", "primary", 28, 280)
	go.add_theme_font_override("font", JSUI.serif_bold())
	go.pressed.connect(func():
		UISfx.play("confirm")
		JSUI.close_modal(overlay)
		running = true)
	row.add_child(go)
	v.add_child(row)
	go.call_deferred("grab_focus")


func _ask_submit() -> void:
	if _done:
		return
	var n := _unanswered()
	var body := "提出すると解答は確定し、二度と変更できません。\n"
	if n > 0:
		body += "未解答：%d問（提出時にランダムにマークされます）" % n
	else:
		body += "全%d問に解答済みです。" % _qs.size()
	JSUI.confirm(self, "答案を提出しますか？", body, "提出する", "見直す", func():
		_done = true
		submitted.emit())


## マークシートの1行（番号 + ①〜④の楕円）
class MarkRow extends Control:
	signal picked(n: int)
	var number := 1
	var answer := -1
	var current := false
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())
		tooltip_text = "問 %d へ移動" % number

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(number)

	func _draw() -> void:
		var h := size.y
		var red := Color("#D2493C")
		if current:
			draw_rect(Rect2(Vector2.ZERO, size), Color(JSUI.CYAN, 0.18))
			draw_rect(Rect2(0, 0, 4, h), Color("#1E9DB5"))
		elif _hover:
			draw_rect(Rect2(Vector2.ZERO, size), Color(red, 0.07))
		draw_line(Vector2(0, h - 0.5), Vector2(size.x, h - 0.5), Color(red, 0.18), 1.0)
		var f := JSUI.sans_bold()
		var fs := int(clampf(h * 0.55, 12, 20))
		var num := str(number)
		draw_string(f, Vector2(10, h * 0.5 + fs * 0.36), num, HORIZONTAL_ALIGNMENT_RIGHT, 32, fs, JSUI.PAPER_INK if answer >= 0 else red)
		var bw := clampf((size.x - 56) / 4.0, 20, 40)
		var eh := clampf(h * 0.62, 10, 22)
		for k in 4:
			var cx := 56.0 + bw * k + bw * 0.5
			var r := Rect2(cx - bw * 0.3, h * 0.5 - eh * 0.5, bw * 0.6, eh)
			if answer == k:
				_ellipse(r, JSUI.PAPER_INK, true)
			else:
				_ellipse(r, Color(red, 0.85), false)
				var d := str(k + 1)
				var dfs := int(eh * 0.72)
				draw_string(f, Vector2(r.position.x, r.position.y + eh * 0.5 + dfs * 0.36), d, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, dfs, Color(red, 0.85))

	func _ellipse(r: Rect2, col: Color, filled: bool) -> void:
		var pts := PackedVector2Array()
		var c := r.get_center()
		for i in 33:
			var a := TAU * i / 32.0
			pts.append(c + Vector2(cos(a) * r.size.x * 0.5, sin(a) * r.size.y * 0.5))
		if filled:
			draw_colored_polygon(pts, col)
		else:
			draw_polyline(pts, col, 1.4, true)

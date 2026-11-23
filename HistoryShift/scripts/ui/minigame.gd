class_name Minigame
extends Control
## 工房の稽古（ミニゲーム）。10〜20 秒で終わる。終わると finished(score 0〜1)。
##  hammer   左右に動く印が金の幅に入った瞬間に打つ（5 回）。剣術道場の「受けと返し」もこれ
##  heat     押している間だけ火が強まる。針を幅の中に合計 3 秒保つ（上げすぎると焼ける）
##  assembly 手順の次の一手を 3 つから選ぶ（間違えると減点）
##  mix      配合を ±で合わせて「決定」
##  target   揺れる照準が的に重なった瞬間に撃つ（5 発）。技能が高いほど揺れが小さい
## 技能が上がるほど当たりの幅が狭くなる（Skills.lesson_zone）＝入門→中伝→奥伝。
## キー: E / Space / 左クリック / ゲームパッド A（＝決める・打つ）。テストは finish(score) を直接呼べる。

signal finished(score: float)

var game := "hammer"
var lesson: Dictionary = {}
var level := 0.0
var _t := 0.0
var _done := false
var _scores: Array = []
var _x := 0.0
var _dir := 1.0
var _zone_c := 0.5
var _zone_w := 0.2
var _heat := 0.2
var _inband := 0.0
var _burnt := 0.0
var _steps: Array = []
var _step_i := 0
var _mistakes := 0
var _mix: Array = [34, 33, 33]
var _target: Array = [75, 10, 15]
var _labels: Array = []
var _sway := Vector2.ZERO
var _flash := 0.0
var _info: Label
var _box: VBoxContainer
var _canvas: Control
var _font: Font

const STRIKES := 5


func setup(p_game: String, p_lesson: Dictionary, p_level: float) -> void:
	game = p_game
	lesson = p_lesson
	level = p_level


func _ready() -> void:
	custom_minimum_size = Vector2(860, 380)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = JSUI.sans_bold()
	_zone_w = Skills.lesson_zone(level)
	var v := JSUI.vbox(10)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	var title := JSUI.label(str(lesson.get("title", "稽古")), 34, JSUI.GOLD, JSUI.serif_bold())
	v.add_child(title)
	var txt := JSUI.label(str(lesson.get("text", "")), 21, JSUI.TEXT, null, true)
	txt.custom_minimum_size = Vector2(840, 0)
	v.add_child(txt)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(840, 170)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_canvas)
	v.add_child(_canvas)
	_info = JSUI.label("", 22, JSUI.CYAN, JSUI.sans_bold())
	v.add_child(_info)
	_box = JSUI.vbox(6)
	v.add_child(_box)
	match game:
		"hammer":
			_new_zone()
		"heat":
			_zone_c = randf_range(0.55, 0.72)
		"assembly":
			_steps = lesson.get("steps", ["材料を用意する", "形を整える", "仕上げる"])
			_canvas.custom_minimum_size = Vector2(840, 10)
			_build_choices()
		"mix":
			_target = lesson.get("target", [75, 10, 15])
			_labels = lesson.get("labels", ["一", "二", "三"])
			_canvas.custom_minimum_size = Vector2(840, 10)
			_build_mix()
		"target":
			_zone_c = 0.0
	_update_info()


func _new_zone() -> void:
	_zone_c = randf_range(0.25 + _zone_w * 0.5, 0.75 - _zone_w * 0.5)


func _action_pressed(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		return true
	return ev.is_action_pressed("interact") or ev.is_action_pressed("jump")


func _input(ev: InputEvent) -> void:
	if _done or not is_visible_in_tree():
		return
	if game in ["hammer", "target"] and _action_pressed(ev):
		get_viewport().set_input_as_handled()
		if game == "hammer":
			_strike()
		else:
			_shoot()


func _holding() -> bool:
	return Input.is_action_pressed("interact") or Input.is_action_pressed("jump") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _process(dt: float) -> void:
	if _done:
		return
	_t += dt
	_flash = maxf(0.0, _flash - dt * 3.0)
	match game:
		"hammer":
			var spd := 0.85 + level * 0.012
			_x += _dir * spd * dt
			if _x > 1.0:
				_x = 1.0; _dir = -1.0
			elif _x < 0.0:
				_x = 0.0; _dir = 1.0
		"heat":
			var up := 0.55 if _holding() else -0.38
			_heat = clampf(_heat + (up + sin(_t * 2.7) * 0.12) * dt, 0.0, 1.0)
			if absf(_heat - _zone_c) <= _zone_w * 0.65:
				_inband += dt
			if _heat > 0.97:
				_burnt += dt
			if _inband >= 3.0 or _t >= 12.0:
				var sc := clampf(_inband / 3.0, 0.0, 1.0) * clampf(1.25 - _t / 12.0, 0.55, 1.0) - _burnt * 0.15
				finish(clampf(sc, 0.0, 1.0))
		"target":
			var amp := 0.06 + 0.3 * pow(1.0 - level / 100.0, 1.2)
			_sway = Vector2(sin(_t * 1.3) + 0.5 * sin(_t * 3.1), sin(_t * 1.7 + 0.7) + 0.4 * cos(_t * 2.6)) * amp * 0.6
	_update_info()
	_canvas.queue_redraw()


func _strike() -> void:
	var d := absf(_x - _zone_c)
	var half := _zone_w * 0.5
	var sc := (1.0 - 0.4 * d / half) if d <= half else maxf(0.0, 0.4 - (d - half) * 2.0)
	_scores.append(sc)
	_flash = 1.0
	Sfx.play(get_tree(), Sfx.hit(), -6.0 if sc > 0.5 else -12.0)
	if _scores.size() >= STRIKES:
		finish(_avg())
	else:
		_new_zone()


func _shoot() -> void:
	var r := _zone_w * 0.7
	var d := _sway.length()
	var sc := (1.0 - 0.5 * d / r) if d <= r else maxf(0.0, 0.5 - (d - r) * 3.0)
	_scores.append(sc)
	_flash = 1.0
	Sfx.play(get_tree(), Sfx.shot() if lesson.get("skill", "") != "kyujutsu" else Sfx.bow(), -10.0)
	if _scores.size() >= STRIKES:
		finish(_avg())


func _avg() -> float:
	var s := 0.0
	for x in _scores:
		s += float(x)
	return s / maxf(1.0, float(_scores.size()))


func _update_info() -> void:
	match game:
		"hammer":
			_info.text = "打て！（E / Space / クリック）　%d / %d" % [_scores.size(), STRIKES]
		"target":
			_info.text = "照準が的に重なった瞬間に撃て（E / Space / クリック）　%d / %d" % [_scores.size(), STRIKES]
		"heat":
			_info.text = "押している間だけ火が強まる。幅の中に保て　%.1f / 3.0 秒" % _inband
		"assembly":
			_info.text = "次の手順は？（%d / %d）　誤り %d" % [_step_i, _steps.size(), _mistakes]
		"mix":
			var tot := 0
			for x in _mix:
				tot += int(x)
			_info.text = "合計 %d（100 にそろえて決定）" % tot


func _draw_canvas() -> void:
	var w := _canvas.size.x
	var h := _canvas.size.y
	match game:
		"hammer":
			var y := h * 0.5
			_canvas.draw_rect(Rect2(20, y - 18, w - 40, 36), Color(1, 1, 1, 0.08))
			var zx := 20 + (w - 40) * (_zone_c - _zone_w * 0.5)
			_canvas.draw_rect(Rect2(zx, y - 18, (w - 40) * _zone_w, 36), Color(JSUI.GOLD, 0.55 + 0.4 * _flash))
			var mx := 20 + (w - 40) * _x
			_canvas.draw_rect(Rect2(mx - 4, y - 30, 8, 60), Color.WHITE)
			for i in _scores.size():
				var c := JSUI.OK if float(_scores[i]) > 0.6 else (JSUI.GOLD if float(_scores[i]) > 0.3 else JSUI.SHU)
				_canvas.draw_circle(Vector2(30 + i * 34, 20), 11, c)
		"heat":
			var x0 := 60.0
			var bw := w - 120.0
			_canvas.draw_rect(Rect2(x0, h * 0.5 - 16, bw, 32), Color(1, 1, 1, 0.08))
			var lo := clampf(_zone_c - _zone_w * 0.65, 0, 1)
			var hi := clampf(_zone_c + _zone_w * 0.65, 0, 1)
			_canvas.draw_rect(Rect2(x0 + bw * lo, h * 0.5 - 16, bw * (hi - lo), 32), Color(1.0, 0.6, 0.2, 0.55))
			var hc := Color(0.3, 0.3, 0.35).lerp(Color(1.0, 0.45, 0.1), _heat).lerp(Color(1, 1, 0.85), maxf(0.0, _heat - 0.8) * 4.0)
			_canvas.draw_rect(Rect2(x0, h * 0.5 - 8, bw * _heat, 16), hc)
			_canvas.draw_string(_font, Vector2(x0, h * 0.5 + 46), "低", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, JSUI.MUTED)
			_canvas.draw_string(_font, Vector2(x0 + bw - 20, h * 0.5 + 46), "高", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, JSUI.MUTED)
			if _burnt > 0.0:
				_canvas.draw_string(_font, Vector2(x0 + bw * 0.4, 24), "熱すぎる！", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, JSUI.SHU)
		"target":
			var c := Vector2(w * 0.5, h * 0.5)
			var scale := h * 1.2
			var r := _zone_w * 0.7 * scale
			_canvas.draw_circle(c, r * 2.2, Color(1, 1, 1, 0.08))
			_canvas.draw_circle(c, r, Color(JSUI.SHU, 0.6))
			_canvas.draw_circle(c, r * 0.35, Color(1, 1, 1, 0.8))
			var p := c + _sway * scale
			_canvas.draw_arc(p, 16, 0, TAU, 24, Color(JSUI.CYAN, 0.9 + 0.1 * _flash), 3.0)
			_canvas.draw_line(p - Vector2(24, 0), p + Vector2(24, 0), JSUI.CYAN, 2.0)
			_canvas.draw_line(p - Vector2(0, 24), p + Vector2(0, 24), JSUI.CYAN, 2.0)
			for i in _scores.size():
				_canvas.draw_circle(Vector2(30 + i * 34, 20), 11, JSUI.OK if float(_scores[i]) > 0.6 else (JSUI.GOLD if float(_scores[i]) > 0.3 else JSUI.SHU))


# ------------------------------------------------------------------ 手順
func _build_choices() -> void:
	for c in _box.get_children():
		c.queue_free()
	if _step_i >= _steps.size():
		finish(clampf(1.0 - float(_mistakes) / maxf(1.0, float(_steps.size())), 0.0, 1.0))
		return
	var done_txt := ""
	for i in _step_i:
		done_txt += "%d. %s\n" % [i + 1, _steps[i]]
	if done_txt != "":
		_box.add_child(JSUI.label(done_txt.strip_edges(), 19, JSUI.MUTED, null, true))
	var opts: Array = [_steps[_step_i]]
	var rest: Array = _steps.slice(_step_i + 1)
	rest.shuffle()
	for x in rest.slice(0, 2):
		opts.append(x)
	opts.shuffle()
	var first: Button = null
	for o in opts:
		var b := JSUI.button(str(o), "normal", 22, 820)
		var ok: bool = str(o) == str(_steps[_step_i])
		b.pressed.connect(func(): _choose(ok))
		_box.add_child(b)
		if first == null:
			first = b
	if first:
		first.call_deferred("grab_focus")


func _choose(ok: bool) -> void:
	if _done:
		return
	if ok:
		_step_i += 1
		Sfx.play(get_tree(), Sfx.click(), -6.0)
	else:
		_mistakes += 1
		Sfx.play(get_tree(), Sfx.fail(), -12.0)
	_build_choices()


# ------------------------------------------------------------------ 配合
func _build_mix() -> void:
	for c in _box.get_children():
		c.queue_free()
	var first: Button = null
	for i in 3:
		var row := JSUI.hbox(10)
		var l := JSUI.label("%s　%d" % [_labels[i] if i < _labels.size() else str(i), int(_mix[i])], 26, JSUI.TEXT, JSUI.sans_bold())
		l.custom_minimum_size = Vector2(240, 0)
		row.add_child(l)
		for d in [-5, -1, 1, 5]:
			var b := JSUI.button(("%+d" % d), "normal", 22, 90)
			var idx := i
			var dd: int = d
			b.pressed.connect(func(): _mix[idx] = clampi(int(_mix[idx]) + dd, 0, 100); _build_mix())
			row.add_child(b)
			if first == null:
				first = b
		_box.add_child(row)
	var ok := JSUI.button("決定", "primary", 24, 240)
	ok.pressed.connect(_mix_done)
	_box.add_child(ok)
	if first:
		first.call_deferred("grab_focus")


func _mix_done() -> void:
	var err := 0.0
	for i in 3:
		err += absf(float(_mix[i]) - float(_target[i]))
	var tol := lerpf(0.06, 0.02, level / 100.0)   # 上達するほど厳しく見られる
	finish(clampf(1.0 - maxf(0.0, err / 200.0 - tol) * 4.0, 0.0, 1.0))


# ------------------------------------------------------------------ 終わり
func finish(score: float) -> void:
	if _done:
		return
	_done = true
	finished.emit(clampf(score, 0.0, 1.0))

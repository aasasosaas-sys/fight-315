class_name ActorInteract
extends Node
## 自由探索で歴史上の人物（HistFigure）に近づいて E で開く会話メニュー。
## 説得する（論点を選ぶ）／未来を語る（関わる問題の選択肢へ導く）／渡す（未来の品）／守る（刺客を退ける）／
## 連れて行く（別の名所まで同行させる）／書状を盗む・偽の書状を渡す。結果は Game.chaos.act() で歴史に反映される。
## T キーで「この人物は第N問に関わる」ヒントの表示を切り替える。

var session: Node
var hud
var figures: Array = []
var _near: HistFigure = null
var _menu_fig: HistFigure = null
var _layer: CanvasLayer
var _panel: PanelContainer
var _title: Label
var _line: Label
var _box: VBoxContainer
var _escort: HistFigure = null
var _escort_t := 0.0
var _assassins: Array = []
var _protect_fig: HistFigure = null
var hints_on := true

const TALK_RANGE := 3.8
const ESCORT_RADIUS := 30.0


func setup(p_session: Node, p_hud, p_figures: Array) -> void:
	session = p_session
	hud = p_hud
	figures = p_figures


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.position = Vector2(-640, -330)
	_panel.custom_minimum_size = Vector2(600, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.93)
	sb.border_color = Color(0.95, 0.78, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22; sb.content_margin_right = 22; sb.content_margin_top = 16; sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	_title = _mk_label(v, 32, Color(0.95, 0.78, 0.35))
	_title.add_theme_font_override("font", load("res://assets/fonts/NotoSerifJP-Bold.ttf"))
	_line = _mk_label(v, 22, Color.WHITE)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(556, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	v.add_child(_box)
	_panel.visible = false
	_layer.add_child(_panel)


func _mk_label(parent: Node, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l


func _button(t: String, cb: Callable, enabled := true) -> void:
	var b := Button.new()
	b.text = t
	b.disabled = not enabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(556, 46)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	_box.add_child(b)


func is_open() -> bool:
	return _panel.visible


# ------------------------------------------------------------------ 毎フレーム
func _process(dt: float) -> void:
	if session == null or Game.player == null or not is_instance_valid(Game.player):
		return
	figures = figures.filter(func(f): return is_instance_valid(f))
	if not is_open():
		_near = _nearest()
		if hud and not hud.is_dialog_open():
			hud.set_prompt(("E：%sと話す" % _near.figure_name) if _near else "")
	_tick_escort(dt)
	_tick_protect()


func _nearest() -> HistFigure:
	var p: Node3D = Game.player
	if p.in_vehicle():
		return null
	var best: HistFigure = null
	var bd := TALK_RANGE
	for f in figures:
		if f.dead:
			continue
		var d := (f as Node3D).global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = f
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_T and not is_open():
		hints_on = not hints_on
		for f in figures:
			if is_instance_valid(f):
				f.hint_on = hints_on
				f.refresh_hint()
		if hud:
			hud.toast("ヒント表示：" + ("ON" if hints_on else "OFF"), 2.0)
		return
	if event.is_action_pressed("interact"):
		if is_open():
			close()
			get_viewport().set_input_as_handled()
		elif _near and not Game.input_blocked:
			open(_near)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and is_open():
		close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ メニュー
func open(f: HistFigure) -> void:
	_menu_fig = f
	f.talking = true
	_panel.visible = true
	Game.input_blocked = true
	Game.lock_mouse(false)
	_main_page()


func close() -> void:
	if _menu_fig and is_instance_valid(_menu_fig):
		_menu_fig.talking = false
	_menu_fig = null
	_panel.visible = false
	Game.input_blocked = false
	Game.lock_mouse(true)


func _clear() -> void:
	for c in _box.get_children():
		c.queue_free()


func _actor() -> Dictionary:
	return _menu_fig.actor if _menu_fig else {}


func _main_page(msg := "") -> void:
	_clear()
	var f := _menu_fig
	var a := _actor()
	var title := String(Figures.spec_for(f.figure_name).get("title", "")) if not a.is_empty() else ""
	_title.text = f.figure_name + (("　―　" + title) if title != "" else "")
	_line.text = msg if msg != "" else ("%s「%s」" % [f.figure_name, str(f.lines[0]) if not f.lines.is_empty() else "……何用か。"])
	var verbs: Array = HistoryActors.verbs_for(a) if not a.is_empty() else ["persuade", "give", "escort"]
	_button("説得する", _persuade_page)
	if not f.questions.is_empty():
		_button("未来を語る", _steer_page)
	_button("未来の品を渡す", _give_page)
	if "protect" in verbs:
		_button("守る（刺客から命を救う）", _start_protect, _protect_fig == null)
	if _escort == f:
		_button("ここに残ってもらう", func(): _escort = null; f.follow_target = null; _main_page("「ここで待とう」"))
	else:
		_button("連れて行く（別の名所まで同行させる）", _start_escort)
	if "steal" in verbs:
		var doc: Dictionary = a.get("doc", {})
		_button("書状を盗む" + ("（%s）" % doc["name"] if doc.has("name") else ""), func(): _do("steal", {}))
		_button("偽の書状を渡す", func(): _do("forge", {}))
	_button("立ち去る", close)


func _persuade_page() -> void:
	_clear()
	_line.text = "何を説く？（相手の性格によっては、はねつけられる）"
	for arg in HistoryActors.ARGS:
		_button(arg, func(): _do("persuade", {"arg": arg}))
	_button("戻る", _main_page)


func _give_page() -> void:
	_clear()
	_line.text = "時空鞄から何を渡す？（渡すと信頼も得られる）"
	for it in HistoryActors.ITEMS:
		_button(it, func(): _do("give", {"item": it}))
	_button("戻る", _main_page)


func _steer_page() -> void:
	_clear()
	_line.text = "どの出来事の未来を語る？"
	for qid in _menu_fig.questions:
		var q: Dictionary = Game.db.by_id.get(qid, {})
		if q.is_empty():
			continue
		var n := Game.db.questions.find(q) + 1
		var mark := "" if Game.state.answer(q) < 0 else ("　○" if Game.state.is_correct(q) else "　×")
		_button("第%d問『%s』%s" % [n, q["topic"], mark], func(): _steer_choices(q))
	_button("戻る", _main_page)


func _steer_choices(q: Dictionary) -> void:
	_clear()
	_line.text = "%s を、どの未来へ導く？" % q["topic"]
	for c in 4:
		var t: String = q["choices"][c]
		if t.length() > 34:
			t = t.substr(0, 33) + "…"
		var tag := "（今の史実）" if Game.state.world_choice(q) == c else ""
		_button("%s %s%s" % [JSUI.circled(c), t, tag], func(): _do("steer", {"q": q["id"], "choice": c}))
	_button("戻る", _steer_page)


func _do(verb: String, info: Dictionary) -> void:
	if _menu_fig == null:
		return
	var hit: Dictionary = Game.chaos.act(verb, _menu_fig.figure_name, info) if Game.chaos else {}
	for f in figures:
		if is_instance_valid(f):
			f.refresh_hint()
	if hit.get("refused", false):
		_main_page(str(hit.get("title", "……")))
		return
	if hit.is_empty():
		_main_page("%s「……ふむ」（歴史は動かなかった）" % _menu_fig.figure_name)
		return
	close()


# ------------------------------------------------------------------ 連れて行く
func _start_escort() -> void:
	var f := _menu_fig
	if _escort and is_instance_valid(_escort):
		_escort.follow_target = null
	_escort = f
	f.follow_target = Game.player
	_escort_t = 0.0
	close()
	if hud:
		hud.toast("%sがついてくる。別の名所まで連れて行こう" % f.figure_name, 3.5)


func _tick_escort(dt: float) -> void:
	if _escort == null or not is_instance_valid(_escort) or _escort.dead:
		_escort = null
		return
	var w = Game.world
	if w == null:
		return
	var here := ""
	for k in HistoryDB.LANDMARK_KEYS:
		if (_escort as Node3D).global_position.distance_to(w.landmark_pos(k)) < ESCORT_RADIUS:
			here = k
	var home_key := str(_escort.actor.get("spawn", ""))
	if here != "" and (_escort.home.distance_to(w.landmark_pos(here)) > ESCORT_RADIUS * 1.5) and here != home_key:
		_escort_t += dt
		if _escort_t > 2.0:
			var f := _escort
			_escort = null
			f.follow_target = null
			f.home = f.global_position
			Game.chaos.act("escort", f.figure_name, {"to": here})
	else:
		_escort_t = 0.0


# ------------------------------------------------------------------ 守る
func _start_protect() -> void:
	var f := _menu_fig
	close()
	_protect_fig = f
	_assassins.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := 4
	for i in n:
		var ang := TAU * i / n
		var p: Vector3 = Game.world.random_ground_point_near(f.global_position + Vector3(cos(ang), 0, sin(ang)) * 24.0, 4.0, rng)
		var e := Enemy.spawn(session, p + Vector3.UP * 0.5, "刺客", f.era_id, i == 0)
		e.aggro_range = 120.0
		_assassins.append(e)
	if hud:
		hud.extra_markers = hud.extra_markers + _assassins
		hud.toast("%sを狙う刺客が現れた！ すべて倒して命を救え" % f.figure_name, 4.0)
		hud.set_objective("歴史を書き換える：%sを守れ" % f.figure_name, "史実では非業の死を遂げる%sを、刺客から守り抜け。" % f.figure_name, "刺客 %d / %d" % [0, n])


func _tick_protect() -> void:
	if _protect_fig == null:
		return
	if not is_instance_valid(_protect_fig) or _protect_fig.dead:
		_protect_fig = null
		if hud:
			hud.toast("守りきれなかった……", 3.0)
			hud.set_objective("自由探索", "好きに暴れろ。人物に近づいて E で話せる。", "")
		return
	var left := _assassins.filter(func(e): return is_instance_valid(e) and not e.dead).size()
	if hud:
		hud.set_counter("刺客 %d / %d" % [_assassins.size() - left, _assassins.size()])
	if left == 0:
		var f := _protect_fig
		_protect_fig = null
		if hud:
			hud.set_objective("自由探索", "好きに暴れろ。人物に近づいて E で話せる。", "")
		Game.chaos.act("protect", f.figure_name, {})

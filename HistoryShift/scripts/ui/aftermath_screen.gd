extends Control
## ミッション結果。成功時は改変の余波・令和への影響・因果の連鎖（1件ずつ表示）・得点の変化。失敗時はリトライ。

signal to_hub
signal retry

var success := true
var q: Dictionary = {}
var changes: Array = []
var reason := ""
var score_before := 0
var correct_before := 0
var chaos_hits: Array = []      # 自由探索の混乱（ChaosTracker.session_hits）。空でなければ混乱版の画面になる
var chaos_era := ""

var _chain_box: VBoxContainer
var _score_l: Label


func _ready() -> void:
	theme = JSUI.theme()
	JSUI.full_rect(self)
	add_child(JSUI.background("ink"))
	if not chaos_hits.is_empty():
		_build_chaos()
	elif success:
		_build_success()
	else:
		_build_failure()


func _build_success() -> void:
	var choice: int = changes[0]["to"] if not changes.is_empty() else Game.state.world_choice(q)
	var mission := Game.db.mission_for(q, choice) if not q.is_empty() else {}
	var restore: bool = not q.is_empty() and choice == q["real"]
	var m := JSUI.margin(40)
	JSUI.full_rect(m)
	m.add_theme_constant_override("margin_left", 90)
	m.add_theme_constant_override("margin_right", 90)
	add_child(m)
	var v := JSUI.vbox(18)
	m.add_child(v)
	var eyebrow := JSUI.label("HISTORY RESTORED" if restore else "HISTORY ALTERED", 22, JSUI.CYAN, JSUI.sans_bold())
	v.add_child(eyebrow)
	var head := JSUI.label("史実修復 成功" if restore else "歴史改変 成功", 84, Color.WHITE, JSUI.serif_bold())
	head.add_theme_constant_override("outline_size", 10)
	head.add_theme_color_override("font_outline_color", Color(JSUI.CYAN, 0.22))
	head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	head.add_theme_constant_override("shadow_offset_y", 5)
	v.add_child(head)
	head.pivot_offset = Vector2(400, 60)
	head.scale = Vector2(1.2, 1.2)
	head.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(head, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "modulate:a", 1.0, 0.3)
	UISfx.play("success")
	if not q.is_empty():
		v.add_child(JSUI.label("%s　%s　―　%s" % [JSUI.year_text(q["year"]), q["topic"], mission.get("title", "")], 26, JSUI.MUTED, null, true))
	v.add_child(JSUI.hline(Color(JSUI.CYAN, 0.3), 2))

	var body := JSUI.hbox(40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var left_col := JSUI.vbox(14)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left_col)
	var left_sc := ScrollContainer.new()
	left_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(left_sc)
	var left := JSUI.vbox(18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_sc.add_child(left)
	if not q.is_empty():
		var newfact := JSUI.panel(JSUI.sb(Color(JSUI.CYAN, 0.08), 12, 0, Color.TRANSPARENT, 0, 18))
		var nst: StyleBoxFlat = newfact.get_theme_stylebox("panel")
		nst.border_width_left = 6; nst.border_color = JSUI.CYAN
		var nv := JSUI.vbox(2)
		newfact.add_child(nv)
		nv.add_child(JSUI.label("この世界の新しい史実", 20, JSUI.CYAN, JSUI.sans_bold()))
		nv.add_child(JSUI.label("%s %s" % [JSUI.circled(choice), q["choices"][choice]], 28, Color.WHITE, JSUI.serif_bold(), true))
		left.add_child(newfact)
	var after := JSUI.label(mission.get("aftermath", ""), 25, JSUI.TEXT, JSUI.serif(), true)
	after.add_theme_constant_override("line_spacing", 8)
	left.add_child(after)
	JSUI.fade_in(after, 0.5, 0.5)
	var legacy: String = mission.get("legacy", "")
	if legacy != "":
		var lp := JSUI.panel(JSUI.sb(Color(JSUI.GOLD, 0.07), 12, 0, Color.TRANSPARENT, 0, 18))
		var lst: StyleBoxFlat = lp.get_theme_stylebox("panel")
		lst.border_width_left = 6; lst.border_color = JSUI.GOLD
		var lv := JSUI.vbox(4)
		lp.add_child(lv)
		lv.add_child(JSUI.label("令和（2026年）への影響", 20, JSUI.GOLD, JSUI.sans_bold()))
		lv.add_child(JSUI.label(legacy, 24, JSUI.TEXT, null, true))
		left.add_child(lp)
		JSUI.fade_in(lp, 0.5, 0.9)
	# その後の歴史（この時代以降で、史実から変わった時代の流れ）
	if not q.is_empty():
		var started := false
		var tl_lines: PackedStringArray = []
		for item in Game.state.era_timeline():
			var e: Dictionary = item["era"]
			if e["eraId"] == q["era"]["eraId"]:
				started = true
			if started and item["changed"]:
				tl_lines.append("■ %s　%s" % [e["eraName"], " ".join(item["lines"])])
		if not tl_lines.is_empty():
			var tp := JSUI.panel(JSUI.sb(Color(JSUI.CYAN, 0.06), 12, 0, Color.TRANSPARENT, 0, 18))
			var tst2: StyleBoxFlat = tp.get_theme_stylebox("panel")
			tst2.border_width_left = 6; tst2.border_color = JSUI.CYAN
			var tv2 := JSUI.vbox(6)
			tp.add_child(tv2)
			tv2.add_child(JSUI.label("その後の歴史", 20, JSUI.CYAN, JSUI.sans_bold()))
			for t in tl_lines.slice(0, 4):
				tv2.add_child(JSUI.label(t, 21, JSUI.TEXT, null, true))
			left.add_child(tp)
			JSUI.fade_in(tp, 0.5, 1.2)
	# 得点
	left = left_col
	var sc := JSUI.hbox(18)
	var new_score := Game.state.score()
	var delta := new_score - score_before
	sc.add_child(JSUI.label("得点", 26, JSUI.MUTED))
	sc.add_child(JSUI.label("%d点" % score_before, 40, JSUI.MUTED, JSUI.serif_bold()))
	sc.add_child(JSUI.label("→", 40, JSUI.MUTED))
	_score_l = JSUI.label("%d点" % score_before, 64, JSUI.GOLD, JSUI.serif_bold())
	sc.add_child(_score_l)
	var dl := JSUI.label("（%s%d）" % ["+" if delta >= 0 else "", delta], 34, JSUI.CYAN if delta >= 0 else JSUI.SHU, JSUI.sans_bold())
	sc.add_child(dl)
	for c in sc.get_children():
		(c as Label).size_flags_vertical = Control.SIZE_SHRINK_END
	left.add_child(sc)
	left.add_child(JSUI.label("正答 %d → %d / %d" % [correct_before, Game.state.correct_count(), Game.db.questions.size()], 22, JSUI.TEXT))
	dl.modulate.a = 0.0
	var stw := create_tween()
	stw.tween_interval(0.8 + changes.size() * 0.45)
	stw.tween_method(func(x: float): _score_l.text = "%d点" % roundi(x), float(score_before), float(new_score), 0.9).set_trans(Tween.TRANS_CUBIC)
	stw.tween_property(dl, "modulate:a", 1.0, 0.3)

	# 右：因果の連鎖
	var right := JSUI.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := JSUI.vbox(12)
	right.add_child(rv)
	var rh := JSUI.hbox(12)
	rh.add_child(JSUI.label("因果の連鎖", 28, JSUI.CYAN, JSUI.serif_bold()))
	rh.add_child(JSUI.spacer())
	var chained := changes.filter(func(c): return int(c["depth"]) > 0).size()
	rh.add_child(JSUI.label("連鎖 %d 件" % chained, 22, JSUI.MUTED, JSUI.sans_bold()))
	rv.add_child(rh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_chain_box = JSUI.vbox(10)
	_chain_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_chain_box)
	if changes.size() <= 1:
		var none := JSUI.label("波及なし ― この改変は他の設問の史実を変えなかった。", 22, JSUI.MUTED, null, true)
		_chain_box.add_child(none)
	for i in changes.size():
		var row := _chain_row(changes[i])
		_chain_box.add_child(row)
		JSUI.fade_in(row, 0.35, 0.7 + i * 0.45)
		if i > 0:
			get_tree().create_timer(0.7 + i * 0.45).timeout.connect(func(): UISfx.play("tick"))
	body.add_child(right)

	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var hub := JSUI.button("ハブへ", "primary", 28, 300)
	hub.add_theme_font_override("font", JSUI.serif_bold())
	hub.pressed.connect(func(): UISfx.play("confirm"); to_hub.emit())
	row.add_child(hub)
	v.add_child(row)
	hub.call_deferred("grab_focus")


## 自由探索で暴れた結果、変わってしまった歴史
func _build_chaos() -> void:
	var broken := Game.state.chaos_broken()
	var m := JSUI.margin(40)
	JSUI.full_rect(m)
	m.add_theme_constant_override("margin_left", 90)
	m.add_theme_constant_override("margin_right", 90)
	add_child(m)
	var v := JSUI.vbox(18)
	m.add_child(v)
	v.add_child(JSUI.label("HISTORY DISRUPTED", 22, JSUI.SHU, JSUI.sans_bold()))
	var civil_n := Wanted.civil_count   # 民間人への危害（設定オン時のみ）。犠牲は功績として扱わない
	var head := JSUI.label("失われた命は、戻らない。" if civil_n > 0 else "それで、未来が変わっちゃった！", 76, Color.WHITE, JSUI.serif_bold())
	head.add_theme_constant_override("outline_size", 10)
	head.add_theme_color_override("font_outline_color", Color(JSUI.SHU, 0.25))
	head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	head.add_theme_constant_override("shadow_offset_y", 5)
	v.add_child(head)
	head.pivot_offset = Vector2(400, 60)
	head.scale = Vector2(1.2, 1.2)
	head.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(head, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "modulate:a", 1.0, 0.3)
	UISfx.play("error" if not broken.is_empty() else "success")
	var era := Game.db.get_era(chaos_era)
	v.add_child(JSUI.label("%s での自由探索 ― 歴史の揺らぎ %d 件" % [era.get("eraName", chaos_era), chaos_hits.size()], 26, JSUI.MUTED, null, true))
	v.add_child(JSUI.hline(Color(JSUI.SHU, 0.35), 2))
	var body := JSUI.hbox(40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var left_col := JSUI.vbox(14)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left_col)
	var left_sc := ScrollContainer.new()
	left_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(left_sc)
	var left := JSUI.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_sc.add_child(left)
	if civil_n > 0:
		var cp := JSUI.panel(JSUI.sb(Color(0.6, 0.62, 0.7, 0.08), 12, 0, Color.TRANSPARENT, 0, 16))
		var cpv := JSUI.vbox(4)
		cp.add_child(cpv)
		cpv.add_child(JSUI.label("犠牲者 %d人" % civil_n, 24, JSUI.MUTED, JSUI.sans_bold(), true))
		cpv.add_child(JSUI.label("この時代に暮らしていた名もない人々が、あなたのせいで命を落とした。下の揺らぎは、その喪失が残された人々の暮らしと国に残した傷跡である。", 21, JSUI.TEXT, JSUI.serif(), true))
		left.add_child(cp)
	for i in chaos_hits.size():
		var h: Dictionary = chaos_hits[i]
		var col := JSUI.SHU if h.get("broke", false) else JSUI.GOLD
		if h.get("civil", false):
			col = JSUI.MUTED
		var p := JSUI.panel(JSUI.sb(Color(col, 0.08), 12, 0, Color.TRANSPARENT, 0, 16))
		var pst: StyleBoxFlat = p.get_theme_stylebox("panel")
		pst.border_width_left = 6; pst.border_color = col
		var pv := JSUI.vbox(4)
		p.add_child(pv)
		pv.add_child(JSUI.label(("犠牲の波紋：" if h.get("civil", false) else "歴史が揺らいだ：") + str(h.get("title", "")), 24, col, JSUI.sans_bold(), true))
		var tl := JSUI.label(str(h.get("text", "")), 22, JSUI.TEXT, JSUI.serif(), true)
		tl.add_theme_constant_override("line_spacing", 6)
		pv.add_child(tl)
		left.add_child(p)
		JSUI.fade_in(p, 0.35, 0.4 + i * 0.3)
	# その後の歴史（この時代以降で、史実から変わった時代の流れ）
	var started := false
	var tl_lines: PackedStringArray = []
	for item in Game.state.era_timeline():
		var e: Dictionary = item["era"]
		if e["eraId"] == chaos_era:
			started = true
		if started and item["changed"]:
			tl_lines.append("■ %s　%s" % [e["eraName"], " ".join(item["lines"])])
	if not tl_lines.is_empty():
		var tp := JSUI.panel(JSUI.sb(Color(JSUI.CYAN, 0.06), 12, 0, Color.TRANSPARENT, 0, 18))
		var tst: StyleBoxFlat = tp.get_theme_stylebox("panel")
		tst.border_width_left = 6; tst.border_color = JSUI.CYAN
		var tv := JSUI.vbox(6)
		tp.add_child(tv)
		tv.add_child(JSUI.label("その後の歴史", 20, JSUI.CYAN, JSUI.sans_bold()))
		for t in tl_lines.slice(0, 4):
			tv.add_child(JSUI.label(t, 21, JSUI.TEXT, null, true))
		left.add_child(tp)
		JSUI.fade_in(tp, 0.5, 0.6 + chaos_hits.size() * 0.3)
	# 得点
	var sc := JSUI.hbox(18)
	var new_score := Game.state.score()
	var delta := new_score - score_before
	sc.add_child(JSUI.label("得点", 26, JSUI.MUTED))
	sc.add_child(JSUI.label("%d点" % score_before, 40, JSUI.MUTED, JSUI.serif_bold()))
	sc.add_child(JSUI.label("→", 40, JSUI.MUTED))
	_score_l = JSUI.label("%d点" % new_score, 64, JSUI.GOLD if delta >= 0 else JSUI.SHU, JSUI.serif_bold())
	sc.add_child(_score_l)
	sc.add_child(JSUI.label("（%s%d）" % ["+" if delta >= 0 else "", delta], 34, JSUI.CYAN if delta >= 0 else JSUI.SHU, JSUI.sans_bold()))
	for c in sc.get_children():
		(c as Label).size_flags_vertical = Control.SIZE_SHRINK_END
	left_col.add_child(sc)
	var wt := Game.state.war_tier()
	if wt != "":
		var wb0 := ""
		for h0 in chaos_hits:
			if str(h0.get("war_before", "")) != "":
				wb0 = str(h0["war_before"])
				break
		left_col.add_child(JSUI.label(("戦局予測：%s → %s" % [wb0, wt]) if wb0 != "" and wb0 != wt else ("戦局予測：" + wt), 24, JSUI.GOLD, JSUI.sans_bold(), true))
	var spts: Array = Game.state.standing.get("points", [])
	if not spts.is_empty():
		var chg: PackedStringArray = []
		for sp in spts:
			if sp["tier"] != sp["base_tier"]:
				chg.append("%d年 %s" % [sp["year"], sp["tier"]])
		if not chg.is_empty():
			left_col.add_child(JSUI.label("国際的地位：" + "、".join(chg) + "（史実と違う）", 21, JSUI.CYAN, null, true))
	if not broken.is_empty():
		left_col.add_child(JSUI.label("混乱のせいで %d 問の確定解答が崩れた。ハブから時空跳躍して史実を修復しよう（古い時代から直すのが近道）。" % broken.size(), 22, JSUI.SHU, null, true))
	elif Game.state.exam_submitted:
		left_col.add_child(JSUI.label("確定解答は無事だった。……今のところは。", 22, JSUI.CYAN, null, true))
	# 右：因果の連鎖
	var right := JSUI.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := JSUI.vbox(12)
	right.add_child(rv)
	var rh := JSUI.hbox(12)
	rh.add_child(JSUI.label("書き換わった設問", 28, JSUI.SHU, JSUI.serif_bold()))
	rh.add_child(JSUI.spacer())
	rh.add_child(JSUI.label("%d 問" % changes.size(), 22, JSUI.MUTED, JSUI.sans_bold()))
	rv.add_child(rh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_chain_box = JSUI.vbox(10)
	_chain_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_chain_box)
	if changes.is_empty():
		_chain_box.add_child(JSUI.label("試験の設問の史実は変わらなかった。だが、その後の歴史の流れは確かに変わっている。", 22, JSUI.MUTED, null, true))
	for i in changes.size():
		var row := _chain_row(changes[i])
		_chain_box.add_child(row)
		JSUI.fade_in(row, 0.35, 0.7 + i * 0.3)
	body.add_child(right)
	var row2 := JSUI.hbox()
	row2.alignment = BoxContainer.ALIGNMENT_END
	var hub := JSUI.button("ハブへ" if Game.state.exam_submitted else "戻る", "primary", 28, 300)
	hub.add_theme_font_override("font", JSUI.serif_bold())
	hub.pressed.connect(func(): UISfx.play("confirm"); to_hub.emit())
	row2.add_child(hub)
	v.add_child(row2)
	hub.call_deferred("grab_focus")


func _chain_row(c: Dictionary) -> Control:
	var cq: Dictionary = c["question"]
	var depth := int(c["depth"])
	var col := JSUI.GOLD if depth == 0 else JSUI.CYAN
	var p := JSUI.panel(JSUI.sb(Color(col, 0.07), 10, 0, Color.TRANSPARENT, 0, 14))
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.border_width_left = 5; st.border_color = col
	st.content_margin_left = 14 + mini(depth, 4) * 22
	var v := JSUI.vbox(4)
	p.add_child(v)
	var h := JSUI.hbox(10)
	v.add_child(h)
	var is_chaos: bool = c.get("chaos", false)
	h.add_child(JSUI.pill(("時空の混乱" if is_chaos else "直接改変") if depth == 0 else ("混乱の波及" if is_chaos else "連鎖 %d" % depth), Color(col, 0.22), col, 16))
	var t := JSUI.label("%s『%s』" % [JSUI.year_text(cq["year"]), cq["topic"]], 22, Color.WHITE, JSUI.sans_bold())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(t)
	var ok := Game.state.is_correct(cq)
	if Game.state.answer(cq) < 0:
		h.add_child(JSUI.label("－", 28, JSUI.MUTED, JSUI.sans_bold()))
	else:
		h.add_child(JSUI.label("✓" if ok else "×", 28, JSUI.CYAN if ok else JSUI.SHU, JSUI.sans_bold()))
	var from := int(c["from"]); var to := int(c["to"])
	v.add_child(JSUI.label("%s %s　→　%s %s" % [JSUI.circled(from), cq["choices"][from], JSUI.circled(to), cq["choices"][to]], 19, JSUI.TEXT, null, true))
	if depth > 0 or c.get("chaos", false):
		v.add_child(JSUI.label(String(c.get("cause", "")), 18, JSUI.MUTED, null, true))
	return p


func _build_failure() -> void:
	var c := CenterContainer.new()
	JSUI.full_rect(c)
	add_child(c)
	var v := JSUI.vbox(22)
	v.custom_minimum_size = Vector2(1100, 0)
	c.add_child(v)
	v.add_child(JSUI.label("MISSION FAILED", 22, JSUI.SHU, JSUI.sans_bold()))
	var head := JSUI.label("ミッション失敗", 100, Color.WHITE, JSUI.serif_bold())
	head.add_theme_constant_override("outline_size", 10)
	head.add_theme_color_override("font_outline_color", Color(JSUI.SHU, 0.22))
	head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	head.add_theme_constant_override("shadow_offset_y", 5)
	v.add_child(head)
	UISfx.play("error")
	if not q.is_empty():
		v.add_child(JSUI.label("%s　%s" % [JSUI.year_text(q["year"]), q["topic"]], 26, JSUI.MUTED))
	v.add_child(JSUI.hline(Color(JSUI.SHU, 0.4), 2))
	v.add_child(JSUI.label(reason if reason != "" else "歴史の修正力に押し返された。", 30, JSUI.TEXT, JSUI.serif(), true))
	v.add_child(JSUI.label("歴史は変わらなかった。態勢を立て直して再挑戦しよう。", 22, JSUI.MUTED, null, true))
	v.add_child(JSUI.gap(20))
	var row := JSUI.hbox(18)
	var hub := JSUI.button("ハブへ戻る", "ghost", 28, 260)
	hub.pressed.connect(func(): UISfx.play("back"); to_hub.emit())
	row.add_child(hub)
	var re := JSUI.button("リトライ", "primary", 30, 320)
	re.add_theme_font_override("font", JSUI.serif_bold())
	re.pressed.connect(func(): UISfx.play("confirm"); retry.emit())
	row.add_child(re)
	v.add_child(row)
	re.call_deferred("grab_focus")
	JSUI.fade_in(v, 0.4)

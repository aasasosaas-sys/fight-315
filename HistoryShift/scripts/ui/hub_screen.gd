extends Control
## 採点ハブ。現在の世界の史実で答案を採点し、誤答の時代へ跳ぶ。

const EraPicker := preload("res://scripts/ui/era_picker.gd")

signal jump(q: Dictionary)
signal free_roam(era_id: String)
signal go_ending
signal go_title
signal reset_all
signal open_settings

var select_qid := ""
var reveal := false

var _rows := {}            # qid -> Button
var _detail: VBoxContainer
var _detail_scroll: ScrollContainer
var _jump_b: Button
var _score_l: Label
var _sel: Dictionary = {}


func _ready() -> void:
	theme = JSUI.theme()
	JSUI.full_rect(self)
	add_child(JSUI.background("ink"))
	var m := JSUI.margin(32)
	JSUI.full_rect(m)
	m.add_theme_constant_override("margin_left", 44)
	m.add_theme_constant_override("margin_right", 44)
	add_child(m)
	var v := JSUI.vbox(20)
	m.add_child(v)
	v.add_child(_header())
	var body := JSUI.hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	body.add_child(_list())
	body.add_child(_detail_pane())
	v.add_child(_footer())
	var q := _initial_selection()
	if not q.is_empty():
		_select(q, false)


func _initial_selection() -> Dictionary:
	if select_qid != "" and Game.db.by_id.has(select_qid):
		return Game.db.by_id[select_qid]
	for q in Game.db.questions:
		if not Game.state.is_correct(q):
			return q
	return Game.db.questions[0] if not Game.db.questions.is_empty() else {}


# ------------------------------------------------------------------ ヘッダー
func _header() -> Control:
	var p := JSUI.panel(JSUI.sb(Color(JSUI.INK2, 0.92), 20, 1, JSUI.INK4, 16, 0))
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 36; st.content_margin_right = 36; st.content_margin_top = 18; st.content_margin_bottom = 18
	var h := JSUI.hbox(36)
	p.add_child(h)
	var tv := JSUI.vbox(0)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(JSUI.label("SCORING HUB", 18, JSUI.CYAN, JSUI.sans_bold()))
	tv.add_child(JSUI.heading("採点ハブ", 46))
	tv.add_child(JSUI.label("あなたの確定解答を「この世界の史実」で採点", 20, JSUI.MUTED))
	h.add_child(tv)
	h.add_child(_vsep())
	# 得点
	var sc := JSUI.hbox(6)
	sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var score := Game.state.score()
	_score_l = JSUI.label(str(score), 104, JSUI.GOLD if score < 100 else JSUI.CYAN, JSUI.serif_bold())
	sc.add_child(_score_l)
	var unit := JSUI.vbox(-8)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	unit.add_child(JSUI.label("点", 40, JSUI.GOLD if score < 100 else JSUI.CYAN, JSUI.serif_bold()))
	unit.add_child(JSUI.label("/100", 24, JSUI.MUTED, JSUI.sans_bold()))
	unit.add_child(JSUI.gap(14))
	sc.add_child(unit)
	h.add_child(sc)
	if reveal:
		var tw := create_tween()
		tw.tween_method(func(x: float): _score_l.text = str(roundi(x)), 0.0, float(score), 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var total := Game.db.questions.size()
	var cc := Game.state.correct_count()
	h.add_child(_stat("正答", "%d / %d" % [cc, total], JSUI.CYAN))
	h.add_child(_stat("誤答", str(total - cc), JSUI.SHU if total - cc > 0 else JSUI.MUTED))
	h.add_child(_stat("歴史改変", "%d 回" % Game.state.alterations, JSUI.GOLD))
	h.add_child(_stat("史実修復", "%d 回" % Game.state.restorations, JSUI.TEXT))
	var cb := Game.state.chaos_broken().size()
	if cb > 0 or Game.state.chaos_count > 0:
		h.add_child(_stat("混乱で崩壊", "%d 問" % cb, JSUI.SHU if cb > 0 else JSUI.MUTED))
	h.add_child(JSUI.spacer())
	var end_b := JSUI.button("エンディングへ", "gold", 28, 300)
	end_b.add_theme_font_override("font", JSUI.serif_bold())
	end_b.custom_minimum_size.y = 76
	end_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	end_b.disabled = not Game.state.perfect()
	end_b.tooltip_text = "満点（100点）で解放" if end_b.disabled else "この世界の結末を見る"
	end_b.pressed.connect(func(): UISfx.play("confirm"); go_ending.emit())
	if not end_b.disabled:
		var tw2 := end_b.create_tween().set_loops()
		tw2.tween_property(end_b, "modulate", Color(1.2, 1.2, 1.2), 0.7)
		tw2.tween_property(end_b, "modulate", Color.WHITE, 0.7)
	var ev := JSUI.vbox(4)
	ev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ev.add_child(end_b)
	var el := JSUI.label("満点で解放" if end_b.disabled else "満点達成！", 18, JSUI.MUTED if end_b.disabled else JSUI.GOLD)
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ev.add_child(el)
	h.add_child(ev)
	return p


func _vsep() -> Control:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.1)
	r.custom_minimum_size = Vector2(2, 90)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _stat(title: String, value: String, col: Color) -> Control:
	var v := JSUI.vbox(0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(JSUI.label(title, 19, JSUI.MUTED))
	v.add_child(JSUI.label(value, 34, col, JSUI.sans_bold()))
	return v


# ------------------------------------------------------------------ 一覧
func _list() -> Control:
	var p := JSUI.panel(JSUI.sb(Color(JSUI.INK2, 0.88), 18, 1, JSUI.INK4, 10, 0))
	p.custom_minimum_size = Vector2(800, 0)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 14; st.content_margin_right = 8; st.content_margin_top = 14; st.content_margin_bottom = 14
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var v := JSUI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var n := 0
	var number := {}
	for i in Game.db.questions.size():
		number[Game.db.questions[i]["id"]] = i + 1
	for era in Game.db.eras:
		var qs: Array = Game.db.questions.filter(func(q): return q["era"]["eraId"] == era["eraId"])
		if qs.is_empty():
			continue
		var ok := 0
		for q in qs:
			if Game.state.is_correct(q):
				ok += 1
		v.add_child(_era_header(era, ok, qs.size()))
		for q in qs:
			var row := _row(q, number[q["id"]])
			v.add_child(row)
			if reveal:
				JSUI.fade_in(row, 0.25, 0.25 + n * 0.025)
			n += 1
		v.add_child(JSUI.gap(6))
	return p


func _era_header(era: Dictionary, ok: int, total: int) -> Control:
	var h := JSUI.hbox(12)
	var col := JSUI.era_color(era["eraId"])
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(6, 34)
	h.add_child(bar)
	var nm := JSUI.label(era["eraName"], 26, Color.WHITE, JSUI.serif_bold())
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	var cnt := JSUI.label("%d / %d" % [ok, total], 22, JSUI.CYAN if ok == total else JSUI.MUTED, JSUI.sans_bold())
	h.add_child(cnt)
	h.add_child(JSUI.gap(10))
	return h


func _row(q: Dictionary, number: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 58)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_ALL
	var h := JSUI.hbox(14)
	JSUI.full_rect(h)
	h.offset_left = 14; h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var correct := Game.state.is_correct(q)
	var mark := JSUI.label("✓" if correct else "×", 30, JSUI.CYAN if correct else JSUI.SHU, JSUI.sans_bold())
	mark.custom_minimum_size = Vector2(30, 0)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(mark)
	h.add_child(JSUI.label("問%02d" % number, 20, JSUI.MUTED, JSUI.sans_bold()))
	var topic := JSUI.label(q["topic"], 23, JSUI.TEXT)
	topic.clip_text = true
	topic.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	topic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(topic)
	if Game.state.is_chaos_touched(q):
		h.add_child(JSUI.pill("混乱で崩壊" if not correct else "時空の混乱", Color(JSUI.SHU, 0.25), JSUI.SHU if not correct else JSUI.GOLD, 16))
	elif Game.state.is_altered(q):
		h.add_child(JSUI.pill("改変済", Color(JSUI.GOLD, 0.2), JSUI.GOLD, 16))
	h.add_child(_ans_chip("解答", Game.state.answer(q), JSUI.TEXT))
	h.add_child(_ans_chip("世界", Game.state.world_choice(q), JSUI.CYAN if correct else JSUI.SHU))
	for c in h.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if c is Label:
			(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			(c as Label).size_flags_vertical = Control.SIZE_FILL
	b.set_meta("correct", correct)
	_style_row(b, false)
	b.pressed.connect(func(): UISfx.play("tick"); _select(q))
	b.mouse_entered.connect(func(): UISfx.play("hover"))
	_rows[q["id"]] = b
	return b


func _ans_chip(title: String, c: int, col: Color) -> Control:
	var h := JSUI.hbox(4)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := JSUI.label(title, 16, JSUI.DIM)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	h.add_child(JSUI.label(JSUI.circled(c), 28, col, JSUI.serif_bold()))
	h.custom_minimum_size = Vector2(76, 0)
	return h


func _style_row(b: Button, selected: bool) -> void:
	var correct: bool = b.get_meta("correct")
	var base := Color(JSUI.INK3, 0.75) if correct else Color("#2E1C26")
	var n := JSUI.sb(base, 10, 0, Color.TRANSPARENT, 0, 6)
	n.border_width_left = 4
	n.border_color = Color(JSUI.CYAN, 0.5) if correct else Color(JSUI.SHU, 0.8)
	var hv := JSUI.sb(base.lightened(0.08), 10, 1, Color(JSUI.CYAN, 0.4), 0, 6)
	hv.border_width_left = 4
	var sel := JSUI.sb(Color("#203A4A"), 10, 2, JSUI.CYAN, 6, 6)
	sel.border_width_left = 6
	b.add_theme_stylebox_override("normal", sel if selected else n)
	b.add_theme_stylebox_override("hover", sel if selected else hv)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("focus", JSUI.sb(Color.TRANSPARENT, 10, 1, Color(JSUI.CYAN, 0.35), 0, 6))


# ------------------------------------------------------------------ 詳細
func _detail_pane() -> Control:
	var p := JSUI.panel(JSUI.sb(Color(JSUI.INK2, 0.92), 18, 1, JSUI.INK4, 10, 0))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 34; st.content_margin_right = 20; st.content_margin_top = 26; st.content_margin_bottom = 22
	var v := JSUI.vbox(16)
	p.add_child(v)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_detail_scroll)
	var inner := JSUI.margin(0)
	inner.add_theme_constant_override("margin_right", 18)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(inner)
	_detail = JSUI.vbox(16)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_detail)
	var jr := JSUI.margin(0)
	jr.add_theme_constant_override("margin_right", 14)
	v.add_child(jr)
	_jump_b = JSUI.button("時　空　跳　躍", "primary", 38)
	_jump_b.custom_minimum_size.y = 96
	_jump_b.add_theme_font_override("font", JSUI.serif_bold())
	_jump_b.pressed.connect(func():
		if not _sel.is_empty():
			UISfx.play("confirm")
			jump.emit(_sel))
	jr.add_child(_jump_b)
	return p


func _select(q: Dictionary, anim := true) -> void:
	if not _sel.is_empty() and _rows.has(_sel["id"]):
		_style_row(_rows[_sel["id"]], false)
	_sel = q
	if _rows.has(q["id"]):
		_style_row(_rows[q["id"]], true)
	for c in _detail.get_children():
		c.queue_free()
	_build_detail(q)
	_detail_scroll.scroll_vertical = 0
	var correct := Game.state.is_correct(q)
	_jump_b.visible = not correct
	if not correct:
		var restore: bool = Game.state.answer(q) == q["real"]
		_jump_b.text = "時　空　跳　躍" + ("　―　史実修復" if restore else "")
		var tw := _jump_b.create_tween()
		_jump_b.modulate = Color(1.4, 1.4, 1.4)
		tw.tween_property(_jump_b, "modulate", Color.WHITE, 0.4)
	if anim:
		JSUI.fade_in(_detail, 0.2)


func _build_detail(q: Dictionary) -> void:
	var era: Dictionary = q["era"]
	var ans := Game.state.answer(q)
	var wc := Game.state.world_choice(q)
	var correct := Game.state.is_correct(q)
	var idx := Game.db.questions.find(q) + 1
	# 見出し
	var top := JSUI.hbox(14)
	top.add_child(JSUI.pill("問 %d" % idx, JSUI.INK4, Color.WHITE, 20))
	top.add_child(JSUI.pill(String(era["eraName"]).split("（")[0], JSUI.era_color(era["eraId"]).darkened(0.3), Color.WHITE, 20))
	top.add_child(JSUI.pill(JSUI.year_text(q["year"]), Color(1, 1, 1, 0.08), JSUI.TEXT, 20))
	_detail.add_child(top)
	var title := JSUI.heading(q["topic"], 40)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(title)
	# 判定バナー
	var bc := JSUI.CYAN if correct else JSUI.SHU
	var banner := JSUI.panel(JSUI.sb(Color(bc, 0.12), 12, 0, Color.TRANSPARENT, 0, 14))
	var bst: StyleBoxFlat = banner.get_theme_stylebox("panel")
	bst.border_width_left = 6; bst.border_color = bc
	var bh := JSUI.hbox(16)
	banner.add_child(bh)
	bh.add_child(JSUI.label("✓" if correct else "×", 40, bc, JSUI.sans_bold()))
	var bv := JSUI.vbox(0)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(bv)
	var msg := ""
	var sub := ""
	if correct:
		msg = "正解 ― この世界の史実はあなたの解答と一致"
		sub = "（この問題の史実はあなたの手で書き換えられている）" if Game.state.is_altered(q) else "（本来の史実どおり）"
	else:
		msg = "不正解 ― この世界の史実はあなたの解答と異なる"
		if Game.state.is_chaos_touched(q):
			var why := Game.state.reason(q)
			sub = "自由探索での大暴れの余波で史実がずれてしまった（%s）。%s" % [why if why != "" else "時空の混乱",
				"史実を修復せよ。" if ans == q["real"] else "あなたの解答「%s」が史実になるよう、歴史を改変せよ。" % JSUI.circled(ans)]
		elif ans == q["real"]:
			sub = "本来は正解だったが、過去の改変の連鎖で史実がずれてしまった。史実を修復せよ。"
		else:
			sub = "あなたの解答「%s」が史実になるよう、歴史を改変せよ。" % JSUI.circled(ans)
	bv.add_child(JSUI.label(msg, 26, Color.WHITE, JSUI.sans_bold(), true))
	bv.add_child(JSUI.label(sub, 21, JSUI.TEXT, null, true))
	_detail.add_child(banner)
	# 問題文（ミッション情報の後ろへ回す）
	var qsec := _section("問題と選択肢", JSUI.TEXT)
	_detail.add_child(qsec)
	var qt := JSUI.label(q["text"], 22, Color(JSUI.TEXT, 0.9), JSUI.serif(), true)
	qt.add_theme_constant_override("line_spacing", 6)
	_detail.add_child(qt)
	# 選択肢
	var cv := JSUI.vbox(8)
	_detail.add_child(cv)
	for k in 4:
		var tags: Array = []
		if k == ans: tags.append(["あなたの解答", JSUI.SHU, Color.WHITE])
		if k == wc: tags.append(["この世界の史実", Color("#1A7F93"), Color.WHITE])
		if k == q["real"]: tags.append(["本来の史実", JSUI.GOLD, JSUI.INK])
		var hl := k == wc
		var st := JSUI.sb(Color(JSUI.CYAN, 0.07) if hl else Color(1, 1, 1, 0.03), 10, 1, Color(JSUI.CYAN, 0.45) if hl else Color(1, 1, 1, 0.06), 0, 12)
		var cp := JSUI.panel(st)
		var ch := JSUI.hbox(14)
		cp.add_child(ch)
		var num := JSUI.label(JSUI.circled(k), 30, JSUI.CYAN if hl else JSUI.MUTED, JSUI.serif_bold())
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		ch.add_child(num)
		var cvv := JSUI.vbox(6)
		cvv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.add_child(cvv)
		cvv.add_child(JSUI.label(q["choices"][k], 23, JSUI.TEXT, null, true))
		if not tags.is_empty():
			var th := JSUI.hbox(8)
			for t in tags:
				th.add_child(JSUI.pill(t[0], t[1], t[2], 16))
			cvv.add_child(th)
		cv.add_child(cp)
	# 解説
	var exsec := _section("本来の史実の解説", JSUI.GOLD)
	_detail.add_child(exsec)
	var ex := JSUI.panel(JSUI.sb(Color(JSUI.GOLD, 0.06), 10, 0, Color.TRANSPARENT, 0, 16))
	var est: StyleBoxFlat = ex.get_theme_stylebox("panel")
	est.border_width_left = 4; est.border_color = Color(JSUI.GOLD, 0.7)
	var exl := JSUI.label("正解は %s。%s" % [JSUI.circled(q["real"]), q["explanation"]], 22, JSUI.TEXT, null, true)
	exl.add_theme_constant_override("line_spacing", 6)
	ex.add_child(exl)
	_detail.add_child(ex)
	var tail: Array = [qsec, qt, cv, exsec, ex]
	# ミッション
	if not correct and ans >= 0:
		var mis := Game.db.mission_for(q, ans)
		_detail.add_child(_section("時空ミッション", JSUI.SHU))
		var mp := JSUI.panel(JSUI.sb(Color("#2A1820"), 12, 1, Color(JSUI.SHU, 0.5), 0, 20))
		var mv := JSUI.vbox(10)
		mp.add_child(mv)
		mv.add_child(JSUI.label(mis.get("title", ""), 32, Color.WHITE, JSUI.serif_bold(), true))
		mv.add_child(JSUI.label(mis.get("briefing", ""), 22, JSUI.TEXT, null, true))
		mv.add_child(JSUI.label("目標：「%s」を%sにする" % [q["choices"][ans], "本来の史実に戻す" if ans == q["real"] else "この世界の史実"], 20, JSUI.GOLD, null, true))
		_detail.add_child(mp)
		# 波及予測
		var rip := Game.state.predict_ripple(q, ans)
		_detail.add_child(_section("波及予測（バタフライ効果）", JSUI.CYAN))
		if rip.is_empty():
			_detail.add_child(JSUI.label("この改変が他の設問へ波及する記録はない。", 21, JSUI.MUTED, null, true))
		else:
			for r in rip:
				var rq: Dictionary = r["question"]
				var rp := JSUI.panel(JSUI.sb(Color(JSUI.CYAN, 0.06), 10, 0, Color.TRANSPARENT, 0, 14))
				var rst: StyleBoxFlat = rp.get_theme_stylebox("panel")
				rst.border_width_left = 4; rst.border_color = JSUI.CYAN
				var rv := JSUI.vbox(4)
				rp.add_child(rv)
				var will_break: bool = Game.state.answer(rq) != r["to"]
				rv.add_child(JSUI.label("▲ この改変は%s『%s』にも波及する恐れ" % [JSUI.year_text(rq["year"]), rq["topic"]], 22, Color.WHITE, JSUI.sans_bold(), true))
				rv.add_child(JSUI.label("→ 史実が %s「%s」に変わる%s" % [JSUI.circled(r["to"]), rq["choices"][r["to"]], "（あなたの解答と不一致に！）" if will_break else "（あなたの解答と一致）"], 20, JSUI.SHU if will_break else JSUI.CYAN, null, true))
				rv.add_child(JSUI.label(r["note"], 19, JSUI.MUTED, null, true))
				_detail.add_child(rp)
		# 古い時代の誤答が残っているか
		var older := 0
		for oq in Game.db.questions:
			if oq["year"] < q["year"] and not Game.state.is_correct(oq):
				older += 1
		if older > 0:
			_detail.add_child(JSUI.label("ヒント：これより古い時代に誤答が %d 問残っています。因果は過去から未来へ流れるため、古い時代から直すのが確実です。" % older, 20, JSUI.GOLD, null, true))
	for n in tail:
		_detail.move_child(n, -1)


func _section(text: String, col: Color) -> Control:
	var h := JSUI.hbox(12)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(JSUI.label(text, 24, col, JSUI.sans_bold()))
	var l := JSUI.hline(Color(col, 0.25), 1)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var wrap := JSUI.vbox(0)
	wrap.add_child(JSUI.gap(8))
	wrap.add_child(h)
	return wrap


# ------------------------------------------------------------------ フッター
func _footer() -> Control:
	var h := JSUI.hbox(14)
	var hint := JSUI.label("因果は過去から未来へ。古い時代の誤答から順に直すのが近道。", 21, JSUI.MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hint)
	h.add_child(JSUI.spacer())
	var log_b := JSUI.button("改変ログ", "normal", 23, 170)
	log_b.pressed.connect(_show_log)
	h.add_child(log_b)
	if not Game.state.actions.is_empty() or Game.state.chaos_count > 0:
		var act_b := JSUI.button("自由行動の記録", "normal", 23, 220)
		act_b.pressed.connect(_show_actions)
		h.add_child(act_b)
	var free_b := JSUI.button("自由探索", "cyan", 23, 170)
	free_b.pressed.connect(func(): EraPicker.open(self, func(id): free_roam.emit(id)))
	h.add_child(free_b)
	var set_b := JSUI.button("設定", "normal", 23, 120)
	set_b.pressed.connect(func(): open_settings.emit())
	h.add_child(set_b)
	var title_b := JSUI.button("タイトルへ", "ghost", 23, 170)
	title_b.pressed.connect(func(): UISfx.play("back"); go_title.emit())
	h.add_child(title_b)
	var reset_b := JSUI.button("リセット", "danger", 23, 150)
	reset_b.pressed.connect(func():
		JSUI.confirm(self, "すべてリセット", "答案・歴史改変・ログをすべて消去し、世界を本来の史実に戻します。この操作は取り消せません。", "リセットする", "やめる", func(): reset_all.emit(), true))
	h.add_child(reset_b)
	return h


## 自由探索での行動（わざとでも、うっかりでも）と、その結果の年表
func _show_actions() -> void:
	var r := JSUI.modal(self, 1300, "自由行動の記録 ― あなたが動かした歴史")
	var overlay: Control = r[0]
	var v: VBoxContainer = r[1]
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var lv := JSUI.vbox(8)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lv)
	var number := {}
	for i in Game.db.questions.size():
		number[Game.db.questions[i]["id"]] = i + 1
	var acts: Array = Game.state.actions.filter(func(a): return not a.get("ruled", false))
	acts.sort_custom(func(a, b): return int(a.get("seq", 0)) < int(b.get("seq", 0)))
	if acts.is_empty():
		lv.add_child(JSUI.label("自由探索での行動はまだない（揺らぎのルールによる変化は改変ログを参照）。", 22, JSUI.MUTED, null, true))
	for a in acts:
		var era := Game.db.get_era(str(a.get("era", "")))
		var p := JSUI.panel(JSUI.sb(Color(1, 1, 1, 0.03), 8, 0, Color.TRANSPARENT, 0, 12))
		var st: StyleBoxFlat = p.get_theme_stylebox("panel")
		st.border_width_left = 4; st.border_color = JSUI.SHU
		var pv := JSUI.vbox(4)
		p.add_child(pv)
		var hh := JSUI.hbox(10)
		hh.add_child(JSUI.pill(String(era.get("eraName", "")).split("（")[0], JSUI.era_color(str(a.get("era", ""))).darkened(0.3), Color.WHITE, 16))
		var t := JSUI.label(HistoryActors.headline(Game.db, a), 22, Color.WHITE, JSUI.sans_bold(), true)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(t)
		pv.add_child(hh)
		if str(a.get("text", "")) != "":
			pv.add_child(JSUI.label(str(a["text"]), 19, JSUI.TEXT, null, true))
		var qs: PackedStringArray = []
		for qid in a.get("changed", []):
			var q: Dictionary = Game.db.by_id.get(qid, {})
			if not q.is_empty():
				qs.append("第%d問%s" % [number[qid], "○" if Game.state.is_correct(q) else "×"])
		pv.add_child(JSUI.label(("→ 書き換わった設問：" + "、".join(qs)) if not qs.is_empty() else "→ 設問の史実は変わらず（その後の歴史だけが動いた）", 18, JSUI.MUTED, null, true))
		lv.add_child(p)
	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var close := JSUI.button("閉じる", "ghost", 24, 200)
	close.pressed.connect(func(): UISfx.play("back"); JSUI.close_modal(overlay))
	row.add_child(close)
	v.add_child(row)
	close.call_deferred("grab_focus")


func _show_log() -> void:
	var r := JSUI.modal(self, 1300, "改変ログ")
	var overlay: Control = r[0]
	var v: VBoxContainer = r[1]
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var lv := JSUI.vbox(8)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lv)
	var log: Array = Game.state.history_log
	if log.is_empty():
		lv.add_child(JSUI.label("まだ歴史は一度も書き換えられていない。", 24, JSUI.MUTED))
	for i in log.size():
		var line: String = log[i]
		var chain := line.find("（連鎖：") >= 0 or line.find("（波及：") >= 0
		var chaos := line.find("時空の混乱") >= 0 or line.find("混乱の波及") >= 0
		var p := JSUI.panel(JSUI.sb(Color(1, 1, 1, 0.03), 8, 0, Color.TRANSPARENT, 0, 12))
		var st: StyleBoxFlat = p.get_theme_stylebox("panel")
		st.border_width_left = 4; st.border_color = JSUI.SHU if chaos else (JSUI.CYAN if chain else JSUI.GOLD)
		var h := JSUI.hbox(12)
		p.add_child(h)
		h.add_child(JSUI.label("%03d" % (i + 1), 20, JSUI.DIM, JSUI.sans_bold()))
		if chaos:
			h.add_child(JSUI.pill("混乱", Color(JSUI.SHU, 0.2), JSUI.SHU, 16))
		else:
			h.add_child(JSUI.pill("連鎖" if chain else "改変", Color(JSUI.CYAN, 0.2) if chain else Color(JSUI.GOLD, 0.2), JSUI.CYAN if chain else JSUI.GOLD, 16))
		var l := JSUI.label(line, 21, JSUI.TEXT, null, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		lv.add_child(p)
	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var close := JSUI.button("閉じる", "ghost", 24, 200)
	close.pressed.connect(func(): UISfx.play("back"); JSUI.close_modal(overlay))
	row.add_child(close)
	v.add_child(row)
	close.call_deferred("grab_focus")
	sc.call_deferred("set", "scroll_vertical", 100000)

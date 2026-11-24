extends Control
## ミッション・ブリーフィング（自由探索の場合は q を空にして era だけ渡す）

signal depart
signal back

var q: Dictionary = {}
var era: Dictionary = {}
var mission: Dictionary = {}
var method := 0

const STEP_INFO := {
	"goto": ["移動", "◆"], "talk": ["会話", "◇"], "defeat": ["撃退", "▲"], "collect": ["回収", "■"], "ride": ["騎乗", "▶"],
}
const VEHICLE_NAMES := {"horse": "馬", "car": "自動車", "plane": "飛行機"}
const CONTROLS := [
	["WASD", "移動"], ["Shift", "ダッシュ"], ["Space", "ジャンプ"], ["マウス", "視点"],
	["左クリック", "射撃"], ["右クリック", "エイム"], ["R", "リロード"], ["F", "乗り物 乗降"],
	["E", "話す・調べる"], ["Esc", "ポーズ"],
]
const PLANE_CONTROLS := [["W / S", "スロットル"], ["マウス", "機首"], ["A / D", "ロール"], ["Q / E", "ヨー"]]


func _ready() -> void:
	theme = JSUI.theme()
	JSUI.full_rect(self)
	if era.is_empty() and not q.is_empty():
		era = q["era"]
	if not q.is_empty():
		mission = Game.db.mission_for(q, Game.state.answer(q), method)
	var col := JSUI.era_color(era.get("eraId", ""))
	add_child(JSUI.background("ink"))
	# 巨大な時代名の透かし
	var wm := JSUI.label(String(era.get("eraName", "")).split("（")[0], 260, Color(col, 0.06), JSUI.serif_bold())
	wm.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wm.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wm.grow_vertical = Control.GROW_DIRECTION_BEGIN
	wm.position += Vector2(40, 60)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wm)

	var m := JSUI.margin(40)
	JSUI.full_rect(m)
	m.add_theme_constant_override("margin_left", 90)
	m.add_theme_constant_override("margin_right", 90)
	add_child(m)
	var v := JSUI.vbox(22)
	m.add_child(v)
	# 見出し
	var eyebrow := JSUI.hbox(14)
	eyebrow.add_child(JSUI.label("MISSION BRIEFING" if not q.is_empty() else "FREE ROAM", 20, JSUI.CYAN, JSUI.sans_bold()))
	eyebrow.add_child(JSUI.pill(era.get("eraName", ""), col.darkened(0.3), Color.WHITE, 20))
	eyebrow.add_child(JSUI.label(JSUI.era_years(era.get("eraId", "")), 20, JSUI.MUTED))
	if not q.is_empty() and EraTimeline.has_timeline(str(era.get("eraId", ""))):
		# 跳躍先の年（ミッションは問題の年に降り立つ。その年に生きている人物・港の船・建物の姿になる）
		eyebrow.add_child(JSUI.pill("跳躍先：" + EraTimeline.label(str(era["eraId"]), int(q["year"])), JSUI.INK4, JSUI.GOLD, 20))
	v.add_child(eyebrow)
	var title_text: String = mission.get("title", "") if not q.is_empty() else "%sを自由探索" % String(era.get("eraName", "")).split("（")[0]
	var title := JSUI.heading(title_text, 56)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	v.add_child(JSUI.hline(Color(col, 0.5), 3))

	var body := JSUI.hbox(40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# 左：ブリーフィング + 手順
	var left_sc := ScrollContainer.new()
	left_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_sc.size_flags_stretch_ratio = 1.5
	body.add_child(left_sc)
	var left := JSUI.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_sc.add_child(left)
	if not q.is_empty():
		var ans := Game.state.answer(q)
		var target := JSUI.panel(JSUI.sb(Color(JSUI.SHU, 0.12), 12, 0, Color.TRANSPARENT, 0, 18))
		var tst: StyleBoxFlat = target.get_theme_stylebox("panel")
		tst.border_width_left = 6; tst.border_color = JSUI.SHU
		var tv := JSUI.vbox(4)
		target.add_child(tv)
		tv.add_child(JSUI.label("%s　%s" % [JSUI.year_text(q["year"]), q["topic"]], 22, JSUI.MUTED))
		tv.add_child(JSUI.label("目標の史実：%s %s" % [JSUI.circled(ans), q["choices"][ans]], 26, Color.WHITE, JSUI.sans_bold(), true))
		left.add_child(target)
		# 手段の選択（手段ごとに歴史への波及が変わる）
		var methods := Game.db.missions_for(q, ans)
		if methods.size() > 1:
			left.add_child(JSUI.label("手段を選ぶ ― 同じ結果でも、手段によってその後の歴史が変わる", 20, JSUI.GOLD, JSUI.sans_bold()))
			var mrow := JSUI.hbox(10)
			left.add_child(mrow)
			for mi in methods.size():
				var mm: Dictionary = methods[mi]
				var rip := Game.state.predict_ripple(q, ans, mi)
				var label := "%s\n波及 %d件" % [mm.get("method", "手段%d" % (mi + 1)), rip.size()]
				var btn := Button.new()
				btn.text = label
				btn.custom_minimum_size = Vector2(220, 74)
				btn.toggle_mode = true
				btn.button_pressed = mi == method
				btn.add_theme_font_size_override("font_size", 22)
				var idx := mi
				btn.pressed.connect(func(): _select_method(idx))
				mrow.add_child(btn)
		left.add_child(JSUI.label(mission.get("briefing", ""), 25, JSUI.TEXT, JSUI.serif(), true))
		left.add_child(_section("作戦手順"))
		var steps: Array = mission.get("steps", [])
		var i := 0
		for s in steps:
			var info: Array = STEP_INFO.get(s.get("type", ""), ["目標", "◆"])
			var row := JSUI.panel(JSUI.sb(Color(1, 1, 1, 0.04), 10, 1, Color(1, 1, 1, 0.06), 0, 10))
			var h := JSUI.hbox(16)
			row.add_child(h)
			var n := JSUI.label("%d" % (i + 1), 30, JSUI.GOLD, JSUI.serif_bold())
			n.custom_minimum_size = Vector2(36, 0)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(n)
			var kind := JSUI.pill("%s %s" % [info[1], info[0]], Color(JSUI.CYAN, 0.16), JSUI.CYAN, 18)
			h.add_child(kind)
			var sv := JSUI.vbox(0)
			sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(sv)
			sv.add_child(JSUI.label(s.get("text", ""), 24, JSUI.TEXT, null, true))
			var at := HistoryDB.landmark_name(era, s.get("at", ""))
			var extra := ""
			match s.get("type", ""):
				"defeat": extra = "　敵：%s ×%d%s" % [s.get("enemy", "敵"), int(s.get("count", 1)), "（空中戦）" if s.get("air", false) else ""]
				"collect": extra = "　%s ×%d" % [s.get("item", ""), int(s.get("count", 1))]
				"ride": extra = "　%s・制限 %d秒" % [VEHICLE_NAMES.get(s.get("vehicle", ""), s.get("vehicle", "")), int(s.get("time", 60))]
				"talk": extra = "　相手：%s" % s.get("npc", "")
			sv.add_child(JSUI.label("場所：" + at + extra, 19, JSUI.MUTED, null, true))
			left.add_child(row)
			JSUI.fade_in(row, 0.3, 0.15 + i * 0.08)
			i += 1
	else:
		left.add_child(JSUI.label("ミッションも敵の修正力もない。%sの街道・寺社・港を自由に歩き、乗り物で駆け抜けよう。歴史は改変されない。Esc のポーズメニューから帰還できる。" % era.get("eraName", ""), 27, JSUI.TEXT, JSUI.serif(), true))
	left.add_child(JSUI.spacer(false))

	# 右：ランドマーク・操作
	var right := JSUI.vbox(18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var lp := JSUI.panel()
	var lv := JSUI.vbox(8)
	lp.add_child(lv)
	lv.add_child(JSUI.label("主な地点", 24, JSUI.GOLD, JSUI.sans_bold()))
	var used := {}
	for s in mission.get("steps", []):
		used[s.get("at", "")] = true
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	lv.add_child(grid)
	for lm in era.get("landmarks", []):
		var hot: bool = used.has(lm["key"])
		var l := JSUI.label(("◆ " if hot else "・") + lm["name"], 21, JSUI.CYAN if hot else JSUI.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(260, 0)
		grid.add_child(l)
	var vs: PackedStringArray = []
	for vk in era.get("vehicles", []):
		vs.append(VEHICLE_NAMES.get(vk, vk))
	lv.add_child(JSUI.label("乗り物：" + "・".join(vs), 20, JSUI.MUTED))
	right.add_child(lp)

	var cp := JSUI.panel()
	var cv := JSUI.vbox(10)
	cp.add_child(cv)
	cv.add_child(JSUI.label("操作方法", 24, JSUI.GOLD, JSUI.sans_bold()))
	cv.add_child(_controls_grid(CONTROLS, 2))
	if "plane" in era.get("vehicles", []):
		cv.add_child(JSUI.label("飛行機", 20, JSUI.CYAN, JSUI.sans_bold()))
		cv.add_child(_controls_grid(PLANE_CONTROLS, 2))
	right.add_child(cp)
	right.add_child(JSUI.spacer(false))

	# ボタン
	var row := JSUI.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_END
	var back_b := JSUI.button("戻る", "ghost", 28, 220)
	back_b.pressed.connect(func(): UISfx.play("back"); back.emit())
	row.add_child(back_b)
	var go := JSUI.button("出　発", "primary", 34, 360)
	go.add_theme_font_override("font", JSUI.serif_bold())
	go.custom_minimum_size.y = 76
	go.pressed.connect(func(): UISfx.play("confirm"); depart.emit())
	row.add_child(go)
	v.add_child(row)
	go.call_deferred("grab_focus")
	JSUI.fade_in(m, 0.35)


func _section(text: String) -> Control:
	var h := JSUI.hbox(12)
	h.add_child(JSUI.label(text, 24, JSUI.GOLD, JSUI.sans_bold()))
	var l := JSUI.hline(Color(JSUI.GOLD, 0.25), 1)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


func _controls_grid(items: Array, cols: int) -> Control:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 26)
	g.add_theme_constant_override("v_separation", 8)
	for it in items:
		var h := JSUI.hbox(12)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kc := JSUI.keycap(it[0])
		kc.custom_minimum_size = Vector2(130, 0)
		h.add_child(kc)
		var l := JSUI.label(it[1], 21, JSUI.TEXT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		g.add_child(h)
	return g


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not JSUI.modal_open(self):
		accept_event()
		back.emit()


func _select_method(i: int) -> void:
	if i == method:
		return
	method = i
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	_ready()

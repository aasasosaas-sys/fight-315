extends RefCounted
## 自由探索の時代選択モーダル。EraPicker.open(parent, func(era_id): ...)

const VEHICLE_NAMES := {"horse": "馬", "car": "自動車", "plane": "飛行機"}

## 時代の中の年を選んだ結果（era_id -> 年）。Flow.start_free_roam が take_year で受け取る（呼び出し側の信号は era_id だけのまま）
static var chosen := {}


static func take_year(era_id: String) -> int:
	var y := int(chosen.get(era_id, 0))
	chosen.erase(era_id)
	return y


## 年（時点）を選ぶモーダル（data/eras/<era>_timeline.json）。選ぶと chosen に入れて on_pick(era_id)
static func open_years(parent: Control, era_id: String, on_pick: Callable) -> Control:
	var era := Game.db.get_era(era_id)
	var col := JSUI.era_color(era_id)
	var r := JSUI.modal(parent, 1500, "%s ― 年を選ぶ" % String(era.get("eraName", era_id)).split("（")[0])
	var overlay: Control = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(JSUI.label("時代はひと続きではない。選んだ年に生きている人物だけが現れ、港の船・建物・人々の装いもその年の姿になる。前の年にしたことは後の年に残る。", 21, JSUI.MUTED, null, true))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1420, 620)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := JSUI.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var def := EraTimeline.default_year(era_id)
	var focus_b: Button = null
	var ship_names := {}
	for p in EraTimeline.points(era_id):
		var y := int(p["year"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(1380, 96)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_stylebox_override("normal", JSUI.sb(JSUI.INK3, 12, 1, JSUI.INK4, 0, 14))
		var hv := JSUI.sb(JSUI.INK4, 12, 2, col, 8, 14)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.add_theme_stylebox_override("focus", JSUI.sb(Color.TRANSPARENT, 12, 2, Color(JSUI.CYAN, 0.6), 0, 14))
		var m := JSUI.margin(14)
		JSUI.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var cv := JSUI.vbox(4)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(cv)
		var head := JSUI.label(str(p.get("label", EraTimeline.year_text(y))) + ("　（代表の年）" if y == def else ""), 26, Color.WHITE if y != def else col, JSUI.serif_bold())
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(head)
		var info: PackedStringArray = [str(p.get("desc", ""))]
		var sh := EraTimeline.ships_for(era_id, y, [])
		if EraTimeline.data(era_id).has("ships") and not sh.is_empty():
			for sid in sh:
				if not ship_names.has(sid):
					var sd := ShipData.load_ship(String(sid))
					ship_names[sid] = sd.name_ja if sd != null else sid
			info.append("港の船：" + "、".join(PackedStringArray(sh.map(func(x): return str(ship_names.get(x, x))))))
		var dl := JSUI.label("　".join(info), 17, JSUI.MUTED, null, true)
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(dl)
		b.pressed.connect(func():
			UISfx.play("confirm")
			JSUI.close_modal(overlay)
			chosen[era_id] = y
			on_pick.call(era_id))
		b.mouse_entered.connect(func(): UISfx.play("hover"))
		list.add_child(b)
		if y == def or focus_b == null:
			focus_b = b if y == def or focus_b == null else focus_b
	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var back := JSUI.button("時代を選び直す", "ghost", 24, 260)
	back.pressed.connect(func():
		UISfx.play("back")
		JSUI.close_modal(overlay)
		open(parent, on_pick))
	row.add_child(back)
	v.add_child(row)
	if focus_b:
		focus_b.call_deferred("grab_focus")
	return overlay


static func open(parent: Control, on_pick: Callable) -> Control:
	var r := JSUI.modal(parent, 1500, "自由探索 ― 時代を選ぶ")
	var overlay: Control = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(JSUI.label("ミッションなしで各時代のオープンワールドを自由に歩き回れます。歴史は改変されません。", 22, JSUI.MUTED, null, true))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	v.add_child(grid)
	var first: Button = null
	for era in Game.db.eras:
		var id: String = era["eraId"]
		var col := JSUI.era_color(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(340, 230)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var st := JSUI.sb(JSUI.INK3, 16, 1, JSUI.INK4, 6, 18)
		st.border_width_top = 6; st.border_color = col
		var hv := JSUI.sb(JSUI.INK4, 16, 2, col, 14, 18)
		hv.border_width_top = 6
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.add_theme_stylebox_override("focus", JSUI.sb(Color.TRANSPARENT, 16, 2, Color(JSUI.CYAN, 0.6), 0, 18))
		var m := JSUI.margin(20)
		JSUI.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var cv := JSUI.vbox(6)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(cv)
		var name_l := JSUI.label(String(era["eraName"]).split("（")[0], 30, Color.WHITE, JSUI.serif_bold(), true)
		cv.add_child(name_l)
		cv.add_child(JSUI.label(JSUI.era_years(id), 19, col))
		var lms: PackedStringArray = []
		for lm in era.get("landmarks", []).slice(0, 3):
			lms.append(lm["name"])
		var lml := JSUI.label("・".join(lms), 17, JSUI.MUTED, null, true)
		cv.add_child(lml)
		cv.add_child(JSUI.spacer(false))
		var vs: PackedStringArray = []
		for vk in era.get("vehicles", []):
			vs.append(VEHICLE_NAMES.get(vk, vk))
		cv.add_child(JSUI.label("乗り物：" + "・".join(vs), 18, JSUI.TEXT))
		for c in cv.get_children():
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(func():
			UISfx.play("confirm")
			JSUI.close_modal(overlay)
			if EraTimeline.has_timeline(id):
				open_years(parent, id, on_pick)
			else:
				on_pick.call(id))
		b.mouse_entered.connect(func(): UISfx.play("hover"))
		grid.add_child(b)
		if first == null:
			first = b
	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var back := JSUI.button("戻る", "ghost", 24, 200)
	back.pressed.connect(func(): UISfx.play("back"); JSUI.close_modal(overlay))
	row.add_child(back)
	v.add_child(row)
	if first:
		first.call_deferred("grab_focus")
	return overlay

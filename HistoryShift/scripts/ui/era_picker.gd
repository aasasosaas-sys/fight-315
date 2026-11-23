extends RefCounted
## 自由探索の時代選択モーダル。EraPicker.open(parent, func(era_id): ...)

const VEHICLE_NAMES := {"horse": "馬", "car": "自動車", "plane": "飛行機"}


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

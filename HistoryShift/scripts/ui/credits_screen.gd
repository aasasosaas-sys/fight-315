extends RefCounted
## クレジットモーダル。CreditsScreen.open(parent)

const POLYHAVEN_CREDITS := "res://assets/polyhaven/CREDITS.md"


static func open(parent: Control) -> Control:
	var r := JSUI.modal(parent, 1240, "クレジット")
	var overlay: Control = r[0]
	var v: VBoxContainer = r[1]
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 640)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var c := JSUI.vbox(14)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(c)

	var logo := JSUI.label("時空改変 共通テスト日本史 ―JIDAI SHIFT―", 34, Color.WHITE, JSUI.serif_bold())
	c.add_child(logo)
	c.add_child(JSUI.label("Godot Engine 4.5 / GDScript で制作。", 22, JSUI.MUTED))

	_section(c, "問題について", JSUI.SHU)
	c.add_child(JSUI.label("本作に収録された問題文・選択肢・解説・ミッションはすべて本作のためのオリジナルです。実際の大学入学共通テスト（大学入試センター）の過去問ではなく、同センターとは一切関係ありません。史実の解説は学習の参考になるよう努めていますが、ゲーム内の「改変後の史実」はフィクションです。", 22, JSUI.TEXT, null, true))

	_section(c, "Godot Engine", JSUI.CYAN)
	c.add_child(JSUI.label("Godot Engine — MIT License\nCopyright (c) 2014-present Godot Engine contributors. Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.\nhttps://godotengine.org/license", 21, JSUI.TEXT, null, true))

	_section(c, "フォント", JSUI.CYAN)
	c.add_child(JSUI.label("Noto Sans JP / Noto Serif JP — SIL Open Font License 1.1\nCopyright Google LLC / Adobe（Source Han）. https://fonts.google.com/noto", 21, JSUI.TEXT, null, true))

	_section(c, "人物モデル（MakeHuman / MPFB2, CC0）", JSUI.GOLD)
	c.add_child(JSUI.label("MakeHuman 基本メッシュ・肌・髪・衣服（system assets）と MPFB2 で自動生成。CC0（パブリックドメイン）。\nhttps://www.makehumancommunity.org", 21, JSUI.TEXT, null, true))

	_section(c, "キャラクター・アニメーション（KayKit, CC0）", JSUI.GOLD)
	c.add_child(JSUI.label("KayKit Character Animations 1.1 — Kay Lousberg (www.kaylousberg.com)\nMannequin_Medium と132種類のアニメーション。CC0（パブリックドメイン）。", 21, JSUI.TEXT, null, true))

	_section(c, "テクスチャ・HDRI（Poly Haven, CC0）", JSUI.GOLD)
	var lines := _polyhaven_lines()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 2)
	for ln in lines:
		var l := JSUI.label(ln, 19, JSUI.TEXT)
		l.custom_minimum_size = Vector2(540, 0)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		grid.add_child(l)
	c.add_child(grid)
	c.add_child(JSUI.label("Poly Haven の素材は CC0（パブリックドメイン）です。https://polyhaven.com/license", 19, JSUI.MUTED, null, true))

	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var close := JSUI.button("閉じる", "primary", 26, 220)
	close.pressed.connect(func(): UISfx.play("back"); JSUI.close_modal(overlay))
	row.add_child(close)
	v.add_child(row)
	close.call_deferred("grab_focus")
	return overlay


static func _section(c: Control, text: String, col: Color) -> void:
	c.add_child(JSUI.gap(6))
	c.add_child(JSUI.label(text, 25, col, JSUI.sans_bold()))
	c.add_child(JSUI.hline(Color(col, 0.25), 1))


static func _polyhaven_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	if not FileAccess.file_exists(POLYHAVEN_CREDITS):
		out.append("（CREDITS.md が見つかりません）")
		return out
	var text := FileAccess.get_file_as_string(POLYHAVEN_CREDITS)
	var re := RegEx.new()
	re.compile("^-\\s*(\\w+):\\s*`([^`]+)`\\s*—\\s*(\\S+)")
	for ln in text.split("\n"):
		var m := re.search(ln.strip_edges())
		if m:
			var url := m.get_string(3)
			out.append("%s  %s  —  %s" % [m.get_string(1), m.get_string(2), url.get_file()])
		elif ln.strip_edges().begins_with("- "):
			out.append(ln.strip_edges().substr(2))
	return out

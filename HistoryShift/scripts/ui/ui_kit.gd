class_name JSUI
extends RefCounted
## UI 共通：配色・フォント・StyleBox・ボタン・モーダル・小物。各画面はこれを使って Control ツリーをコードで組む。

const INK := Color("#120D1A")
const INK2 := Color("#1C1626")
const INK3 := Color("#2A2238")
const INK4 := Color("#3A3150")
const PAPER := Color("#F7F2E6")
const PAPER2 := Color("#EDE5D2")
const PAPER_LINE := Color("#D9CDB2")
const PAPER_INK := Color("#2A211C")
const SHU := Color("#DC3D33")
const SHU_DARK := Color("#A9281F")
const GOLD := Color("#F2C75A")
const CYAN := Color("#5EE7FF")
const TEXT := Color("#EEE9F6")
const MUTED := Color("#A69EB9")
const DIM := Color("#6F6784")
const OK := Color("#5EE7A8")

const CIRCLED := ["①", "②", "③", "④"]

const ERA_YEARS := {
	"jomon_kofun": "約1万6千年前 〜 6世紀",
	"asuka_nara": "592年 〜 794年",
	"heian": "794年 〜 1185年頃",
	"kamakura_muromachi": "1185年頃 〜 1573年",
	"sengoku": "1467年 〜 1603年",
	"edo": "1603年 〜 1868年",
	"meiji_taisho": "1868年 〜 1926年",
	"showa": "1926年 〜 1989年",
}

const ERA_COLORS := {
	"jomon_kofun": Color("#C98B4E"), "asuka_nara": Color("#9C7BD6"), "heian": Color("#E58FB2"),
	"kamakura_muromachi": Color("#6FAE7A"), "sengoku": Color("#DC3D33"), "edo": Color("#4F8FD8"),
	"meiji_taisho": Color("#D9A441"), "showa": Color("#5EE7FF"),
}

static var _fonts := {}
static var _theme: Theme = null


static func font(file: String) -> Font:
	if not _fonts.has(file):
		_fonts[file] = load("res://assets/fonts/%s.ttf" % file)
	return _fonts[file]

static func serif_bold() -> Font: return font("NotoSerifJP-Bold")
static func serif() -> Font: return font("NotoSerifJP-Regular")
static func sans_bold() -> Font: return font("NotoSansJP-Bold")
static func sans() -> Font: return font("NotoSansJP-Regular")


static func circled(i: int) -> String:
	return CIRCLED[i] if i >= 0 and i < 4 else "―"


static func era_color(era_id: String) -> Color:
	return ERA_COLORS.get(era_id, CYAN)


static func era_years(era_id: String) -> String:
	return ERA_YEARS.get(era_id, "")


static func year_text(y: int) -> String:
	return ("紀元前%d年頃" % -y) if y < 0 else ("%d年" % y)


# ---------------------------------------------------------------- StyleBox
static func sb(bg: Color, radius := 14, border := 0, border_col := Color.TRANSPARENT, shadow := 0, margin := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.shadow_size = shadow
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_offset = Vector2(0, shadow * 0.35)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 26
	t.set_color("font_color", "Label", TEXT)
	# Button
	t.set_stylebox("normal", "Button", sb(INK3, 12, 1, INK4, 0, 14))
	t.set_stylebox("hover", "Button", sb(INK4, 12, 2, CYAN, 6, 14))
	t.set_stylebox("pressed", "Button", sb(INK2, 12, 2, CYAN, 0, 14))
	t.set_stylebox("disabled", "Button", sb(Color(INK3, 0.5), 12, 1, Color(INK4, 0.5), 0, 14))
	t.set_stylebox("focus", "Button", sb(Color.TRANSPARENT, 12, 2, Color(CYAN, 0.6), 0, 14))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", CYAN)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_font("font", "Button", sans_bold())
	# Panel
	t.set_stylebox("panel", "PanelContainer", sb(Color(INK2, 0.94), 18, 1, INK4, 18, 24))
	t.set_stylebox("panel", "Panel", sb(Color(INK2, 0.94), 18, 1, INK4, 18, 24))
	# ScrollBar
	var grab := sb(Color(MUTED, 0.45), 6, 0, Color.TRANSPARENT, 0, 4)
	var grab_h := sb(Color(CYAN, 0.8), 6, 0, Color.TRANSPARENT, 0, 4)
	var track := sb(Color(1, 1, 1, 0.04), 6, 0, Color.TRANSPARENT, 0, 4)
	for kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", kind, grab)
		t.set_stylebox("grabber_highlight", kind, grab_h)
		t.set_stylebox("grabber_pressed", kind, grab_h)
		t.set_stylebox("scroll", kind, track)
	# Slider
	var sl := sb(INK4, 6, 0, Color.TRANSPARENT, 0, 0)
	sl.content_margin_top = 4; sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	var fill := sb(CYAN, 6, 0, Color.TRANSPARENT, 0, 0)
	fill.content_margin_top = 4; fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot_tex(26, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot_tex(30, CYAN))
	# CheckButton / OptionButton / PopupMenu
	for kind in ["CheckButton", "OptionButton"]:
		t.set_stylebox("normal", kind, sb(INK3, 12, 1, INK4, 0, 12))
		t.set_stylebox("hover", kind, sb(INK4, 12, 2, CYAN, 0, 12))
		t.set_stylebox("pressed", kind, sb(INK2, 12, 2, CYAN, 0, 12))
		t.set_stylebox("focus", kind, sb(Color.TRANSPARENT, 12, 2, Color(CYAN, 0.5), 0, 12))
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_pressed_color", kind, CYAN)
	t.set_stylebox("panel", "PopupMenu", sb(INK2, 10, 1, INK4, 12, 8))
	t.set_stylebox("hover", "PopupMenu", sb(INK4, 8, 0, Color.TRANSPARENT, 0, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", CYAN)
	t.set_font_size("font_size", "PopupMenu", 24)
	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", sb(INK, 8, 1, CYAN, 8, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return t


static func _dot_tex(size: int, col: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 部品
static func label(text: String, size := 26, color := TEXT, f: Font = null, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if f:
		l.add_theme_font_override("font", f)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func heading(text: String, size := 48, color := TEXT) -> Label:
	return label(text, size, color, serif_bold())


## kind: "normal" | "primary"(朱) | "gold" | "cyan" | "ghost" | "danger"
static func button(text: String, kind := "normal", size := 26, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, size * 2.1)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_ALL
	style_button(b, kind)
	b.mouse_entered.connect(func(): _hover_pop(b, true))
	b.mouse_exited.connect(func(): _hover_pop(b, false))
	return b


static func style_button(b: Button, kind: String) -> void:
	var base: Color; var edge: Color; var fg: Color; var hover_fg := Color.WHITE
	match kind:
		"primary":
			base = SHU; edge = Color("#FF6B5E"); fg = Color.WHITE
		"gold":
			base = GOLD; edge = Color("#FFE7A0"); fg = INK; hover_fg = INK
		"cyan":
			base = Color("#1D6F80"); edge = CYAN; fg = Color.WHITE
		"ghost":
			base = Color(1, 1, 1, 0.0); edge = Color(1, 1, 1, 0.18); fg = TEXT
		"danger":
			base = Color("#3A1C22"); edge = SHU; fg = Color("#FFB3AC")
		_:
			base = INK3; edge = INK4; fg = TEXT
	b.add_theme_stylebox_override("normal", sb(base, 12, 1, edge, 4 if kind != "ghost" else 0, 14))
	b.add_theme_stylebox_override("hover", sb(base.lightened(0.12), 12, 2, CYAN if kind in ["normal", "ghost", "cyan"] else edge.lightened(0.2), 10, 14))
	b.add_theme_stylebox_override("pressed", sb(base.darkened(0.15), 12, 2, edge, 0, 14))
	b.add_theme_stylebox_override("disabled", sb(Color(INK3, 0.6), 12, 1, Color(INK4, 0.6), 0, 14))
	b.add_theme_stylebox_override("focus", sb(Color.TRANSPARENT, 12, 2, Color(CYAN, 0.55), 0, 14))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", hover_fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", DIM)


static func _hover_pop(c: Control, on: bool) -> void:
	if not c.is_inside_tree():
		return
	if c.has_meta("no_pop") or (c is BaseButton and (c as BaseButton).disabled and on):
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * (1.03 if on else 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if on:
		UISfx.play("hover")


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func panel(style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	if style:
		p.add_theme_stylebox_override("panel", style)
	return p


static func margin(all := 24) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, all)
	return m


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	return c


static func hline(col := Color(1, 1, 1, 0.1), h := 2) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func pill(text: String, bg: Color, fg := Color.WHITE, size := 20) -> PanelContainer:
	var p := panel(sb(bg, 999, 0, Color.TRANSPARENT, 0, 6))
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 16; st.content_margin_right = 16; st.content_margin_top = 2; st.content_margin_bottom = 4
	var l := label(text, size, fg, sans_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func keycap(text: String) -> PanelContainer:
	var p := panel(sb(Color("#2E2640"), 8, 2, Color("#5A4F75"), 0, 6))
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.border_width_bottom = 5
	st.content_margin_left = 12; st.content_margin_right = 12; st.content_margin_top = 2; st.content_margin_bottom = 4
	var l := label(text, 20, Color.WHITE, sans_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.custom_minimum_size = Vector2(52, 0)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## 動く背景（ink のグラデーション + 時空の粒子）。kind: "ink" | "title" | "ending"
static func background(kind := "ink") -> ColorRect:
	var r := ColorRect.new()
	full_rect(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/ui/shaders/backdrop.gdshader")
	match kind:
		"title":
			m.set_shader_parameter("intensity", 1.0)
			m.set_shader_parameter("stars", 1.0)
		"ending":
			m.set_shader_parameter("intensity", 0.6)
			m.set_shader_parameter("stars", 1.6)
			m.set_shader_parameter("tint_b", Color("#F2C75A"))
		"desk":
			m.set_shader_parameter("intensity", 0.25)
			m.set_shader_parameter("stars", 0.15)
		_:
			m.set_shader_parameter("intensity", 0.45)
			m.set_shader_parameter("stars", 0.4)
	r.material = m
	return r


## 全画面の暗幕 + 中央パネル。返り値 [overlay, content_vbox]
static func modal(parent: Control, width := 900, title := "") -> Array:
	var overlay := ColorRect.new()
	overlay.color = Color(0.03, 0.02, 0.05, 0.72)
	full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_to_group("ui_modal")
	parent.add_child(overlay)
	var center := CenterContainer.new()
	full_rect(center)
	overlay.add_child(center)
	var p := panel(sb(INK2, 22, 2, Color(CYAN, 0.35), 32, 36))
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := vbox(18)
	p.add_child(v)
	if title != "":
		var h := heading(title, 38)
		v.add_child(h)
		v.add_child(hline(Color(CYAN, 0.25)))
	overlay.modulate.a = 0.0
	p.pivot_offset = Vector2(width / 2.0, 200)
	p.scale = Vector2(0.96, 0.96)
	var tw := overlay.create_tween().set_parallel()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.18)
	tw.tween_property(p, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	UISfx.play("open")
	return [overlay, v]


static func close_modal(overlay: Control) -> void:
	if not is_instance_valid(overlay):
		return
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.remove_from_group("ui_modal")
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, 0.14)
	tw.tween_callback(overlay.queue_free)


## 確認ダイアログ。on_ok は OK 時のみ呼ばれる。
static func confirm(parent: Control, title: String, body: String, ok_text: String, cancel_text: String, on_ok: Callable, danger := false) -> Control:
	var r := modal(parent, 820, title)
	var overlay: Control = r[0]
	var v: VBoxContainer = r[1]
	var l := label(body, 26, TEXT, null, true)
	l.custom_minimum_size = Vector2(740, 0)
	v.add_child(l)
	v.add_child(gap(8))
	var row := hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	var cancel := button(cancel_text, "ghost", 26, 200)
	var ok := button(ok_text, "danger" if danger else "primary", 26, 240)
	row.add_child(cancel)
	row.add_child(ok)
	v.add_child(row)
	cancel.pressed.connect(func(): UISfx.play("back"); close_modal(overlay))
	ok.pressed.connect(func(): UISfx.play("confirm"); close_modal(overlay); on_ok.call())
	ok.call_deferred("grab_focus")
	return overlay


## 一時的なトースト表示
static func toast(parent: Control, text: String, col := CYAN) -> void:
	var p := panel(sb(Color(INK, 0.95), 14, 2, col, 16, 18))
	var l := label(text, 24, TEXT, null, true)
	l.custom_minimum_size = Vector2(0, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.position.y -= 60
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


static func modal_open(n: Node) -> bool:
	return n.is_inside_tree() and not n.get_tree().get_nodes_in_group("ui_modal").is_empty()


static func fade_in(c: CanvasItem, dur := 0.35, delay := 0.0) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, dur)


static func slide_in(c: Control, from := Vector2(0, 30), dur := 0.4, delay := 0.0) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(func():
		var target := c.position
		c.position = target + from
		var t2 := c.create_tween().set_parallel()
		t2.tween_property(c, "position", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t2.tween_property(c, "modulate:a", 1.0, dur))

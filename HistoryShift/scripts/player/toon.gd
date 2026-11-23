class_name Toon
extends RefCounted
## アニメ調（セルルック）の表現：2段の影・輪郭線（反転ハル）・アニメ顔のデカール。

static var enabled := true
static var _outline_cache := {}
static var _face_cache := {}

const LINE := Color(0.13, 0.09, 0.09)


static func outline_mat(width: float, color := LINE) -> ShaderMaterial:
	var key := "%.4f%s" % [width, color.to_html()]
	if _outline_cache.has(key):
		return _outline_cache[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;
uniform vec4 line_color : source_color;
uniform float width = 0.006;
void vertex() {
	// 画面上でほぼ一定の太さになるよう、カメラ距離で少し補正
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * width * clamp(d * 0.35, 0.6, 3.0);
}
void fragment() {
	ALBEDO = line_color.rgb;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("line_color", color)
	m.set_shader_parameter("width", width)
	_outline_cache[key] = m
	return m


## StandardMaterial3D をセル調に（影は 2 段、ハイライトは硬く、縁に光）
static func toonify(src: Material, outline_w := 0.0, flat_color := Color(0, 0, 0, 0)) -> Material:
	if not (src is BaseMaterial3D):
		return src
	var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.metallic_specular = minf(m.metallic_specular, 0.3)
	m.roughness = maxf(m.roughness, 0.55)
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		sm.subsurf_scatter_enabled = false
		sm.clearcoat_enabled = false
		sm.rim_enabled = true
		sm.rim = 0.35
		sm.rim_tint = 0.3
		sm.normal_scale = minf(sm.normal_scale, 0.35)
		if flat_color.a > 0.0:
			sm.albedo_texture = null
			sm.albedo_color = flat_color
	if outline_w > 0.0:
		m.next_pass = outline_mat(outline_w)
	return m


static func apply(mi: MeshInstance3D, outline_w := 0.004, flat_color := Color(0, 0, 0, 0)) -> void:
	if mi.material_override:
		mi.material_override = toonify(mi.material_override, outline_w, flat_color)
		return
	for si in mi.mesh.get_surface_count():
		var cur := mi.get_surface_override_material(si)
		var base: Material = cur if cur else mi.mesh.surface_get_material(si)
		if base:
			mi.set_surface_override_material(si, toonify(base, outline_w, flat_color))


# ---------------------------------------------------------------- アニメ顔
## 目・眉・口を描いたテクスチャ（性別と表情の型ごとにキャッシュ）
static func face_texture(female: bool, style: int) -> Texture2D:
	var key := "%s%d" % [female, style]
	if _face_cache.has(key):
		return _face_cache[key]
	var W := 512
	var H := 320
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var iris_c: Color = [Color(0.24, 0.13, 0.07), Color(0.12, 0.08, 0.06), Color(0.3, 0.18, 0.1)][style % 3]
	var eye_rx := 0.105 if female else 0.095
	var eye_ry := 0.13 if female else 0.095
	var lash := 0.03 if female else 0.02
	for y in H:
		for x in W:
			var u := float(x) / W
			var v := float(y) / H
			var c := Color(0, 0, 0, 0)
			for si in 2:
				var side := -1.0 if si == 0 else 1.0
				var ex := 0.5 + side * 0.19
				var ey := 0.42
				var dx := (u - ex) / eye_rx
				var dy := (v - ey) / eye_ry * (H / float(W)) * 1.6
				var r := sqrt(dx * dx + dy * dy)
				# 白目
				if r < 1.0 and v > ey - eye_ry * 0.55:
					c = Color(0.97, 0.95, 0.93, 1)
					# 虹彩（下ほど明るいグラデーション）と瞳孔
					var ix := (u - ex) / (eye_rx * 0.62)
					var iy := (v - ey - 0.01) / (eye_ry * 0.9) * (H / float(W)) * 1.6
					var ir := sqrt(ix * ix + iy * iy)
					if ir < 1.0:
						var g := clampf((v - (ey - eye_ry * 0.4)) / (eye_ry * 1.2), 0.0, 1.0)
						c = iris_c.lerp(iris_c.lightened(0.55), g * 0.8)
						if ir < 0.45:
							c = iris_c.darkened(0.6)
						# ハイライト
						var hx := (u - (ex - eye_rx * 0.22)) / 0.022
						var hy := (v - (ey - eye_ry * 0.25)) / 0.035
						if hx * hx + hy * hy < 1.0:
							c = Color(1, 1, 1, 1)
						var hx2 := (u - (ex + eye_rx * 0.25)) / 0.011
						var hy2 := (v - (ey + eye_ry * 0.3)) / 0.018
						if hx2 * hx2 + hy2 * hy2 < 1.0:
							c = Color(1, 1, 1, 0.9)
				# 上まぶたの線（まつげ）：楕円の上縁に沿った太い弧
				if absf(r - 1.0) < lash * 3.0 / eye_rx * 0.35 and v < ey + eye_ry * 0.1 and v > ey - eye_ry * 0.75:
					c = LINE
				if female and u * side > (ex + side * eye_rx * 0.85) * side and v < ey - eye_ry * 0.1 and v > ey - eye_ry * 0.55 and absf(r - 1.05) < 0.12:
					c = LINE   # 目尻のはね
				# 下まぶた（薄く）
				if absf(r - 1.0) < 0.06 and v > ey + eye_ry * 0.45 and v < ey + eye_ry * 0.9:
					c = Color(LINE, 0.55)
				# 眉
				var bx := (u - ex) / 0.12
				var by := v - (0.13 - 0.025 * (1.0 - bx * bx) + (0.02 * bx * side if not female else 0.0))
				if absf(bx) < 1.0 and absf(by) < (0.018 if female else 0.026) * (1.0 - absf(bx) * 0.5):
					c = Color(0.1, 0.07, 0.06, 1)
			# 口（小さく）
			var mx := (u - 0.5) / 0.055
			var my := v - (0.9 + 0.012 * mx * mx)
			if absf(mx) < 1.0 and absf(my) < 0.007:
				c = Color(0.45, 0.2, 0.2, 0.9)
			# 鼻（点に近い短い影）
			var nx := (u - 0.505) / 0.012
			var ny := (v - 0.7) / 0.025
			if nx * nx + ny * ny < 1.0:
				c = Color(0.55, 0.35, 0.3, 0.35)
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_face_cache[key] = t
	return t


## 頭のボーンに顔デカールを付ける（顔の起伏に沿って投影される）
static func add_face(head_holder: Node3D, female: bool, style: int, hair_layer: int) -> Decal:
	var d := Decal.new()
	d.texture_albedo = face_texture(female, style)
	d.size = Vector3(0.15, 0.16, 0.115)
	d.position = Vector3(0, 0.036, 0.12)
	d.rotation_degrees = Vector3(90, 0, 0)    # -Y（投影方向）を顔へ向ける
	d.cull_mask = 0xFFFFF & ~hair_layer
	d.upper_fade = 0.0
	d.lower_fade = 0.0
	d.normal_fade = 0.3
	head_holder.add_child(d)
	return d

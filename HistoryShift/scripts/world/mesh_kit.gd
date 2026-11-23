class_name MeshKit
extends RefCounted
## 手続き的ジオメトリをマテリアル別にまとめて 1 つの ArrayMesh にするビルダー。
## UV はメートル単位（マテリアル側の uv1_scale でテクスチャの実寸に合わせる）。

var surf := {}   # mat_key -> [verts, norms, uvs, cols, idx, uv2(unit id, part)]
## 破壊ユニット ID（UV2.x に焼き込む。0 = 破壊対象外）。part は UV2.y（0=躯体, 1=屋根）
var cur_unit := 0
var has_units := false
var _cut: Array = []       # [Transform3D 逆変換, Rect2]: grid の格子のうち 4 隅がすべて内側のものを作らない（屋根）
const ROOF_MATS := ["rooftile", "thatch"]


func _s(key: String) -> Array:
	if not surf.has(key):
		surf[key] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array(), PackedVector2Array()]
	return surf[key]


## 以降の頂点を unit id に割り当てる（それまでの頂点は前の id で確定）
func set_unit(id: int) -> void:
	sync_units()
	cur_unit = id
	if id != 0:
		has_units = true


## UV2 配列を頂点数まで現在の unit id で埋める
func sync_units() -> void:
	for k in surf:
		var s: Array = surf[k]
		var n: int = s[0].size()
		var u: PackedVector2Array = s[5]
		var m := u.size()
		if m >= n:
			continue
		var part := 1.0 if k in ROOF_MATS else 0.0
		var val := Vector2(float(cur_unit), part)
		u.resize(n)
		for i in range(m, n):
			u[i] = val
		s[5] = u


func is_empty() -> bool:
	return surf.is_empty()


func vertex_count() -> int:
	var c := 0
	for k in surf:
		c += surf[k][0].size()
	return c


## 三角形（向きは n_hint 側を表に自動で揃える）
func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color, n_hint := Vector3.ZERO) -> void:
	var s := _s(mat)
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var flip := false
	if n_hint != Vector3.ZERO and n.dot(n_hint) < 0.0:
		n = -n
		flip = true
	var base: int = s[0].size()
	s[0].append(a); s[0].append(b); s[0].append(c)
	s[1].append(n); s[1].append(n); s[1].append(n)
	s[2].append(ua); s[2].append(ub); s[2].append(uc)
	s[3].append(col); s[3].append(col); s[3].append(col)
	# Godot は時計回りが表。数学的に反時計回り (a,b,c) の場合は (a,c,b) で出す
	if flip:
		s[4].append(base); s[4].append(base + 1); s[4].append(base + 2)
	else:
		s[4].append(base); s[4].append(base + 2); s[4].append(base + 1)


## 四角形 p0..p3 は表から見て反時計回り。UV は p0 を原点に p0→p1 を u、p0→p3 を v（メートル）
func quad(mat: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color, uv_world := true) -> void:
	var s := _s(mat)
	var n := (p1 - p0).cross(p2 - p0)
	if n.length_squared() < 1e-12:
		n = (p2 - p0).cross(p3 - p0)
		if n.length_squared() < 1e-12:
			return
	n = n.normalized()
	var uvs: Array
	if uv_world:
		uvs = _world_uv([p0, p1, p2, p3], n)
	else:
		var ua := (p1 - p0)
		var va := (p3 - p0)
		var ul := ua.length()
		var vl := va.length()
		uvs = [Vector2(0, vl), Vector2(ul, vl), Vector2(ul, 0), Vector2(0, 0)]
	var base: int = s[0].size()
	for i in 4:
		s[0].append([p0, p1, p2, p3][i])
		s[1].append(n)
		s[2].append(uvs[i])
		s[3].append(col)
	s[4].append(base); s[4].append(base + 2); s[4].append(base + 1)
	s[4].append(base); s[4].append(base + 3); s[4].append(base + 2)


## 面法線から世界座標の平面投影 UV を作る（隣接する箱どうしで模様が連続する）
func _world_uv(pts: Array, n: Vector3) -> Array:
	var out: Array = []
	if absf(n.y) > 0.7:
		for p in pts:
			out.append(Vector2(p.x, p.z))
	else:
		var u_axis := Vector3.UP.cross(n).normalized()
		for p in pts:
			out.append(Vector2(p.dot(u_axis), -p.y))
	return out


## 箱。xf の原点が箱の中心
func box(mat: String, xf: Transform3D, size: Vector3, col := Color.WHITE, skip_bottom := true) -> void:
	var hx := xf.basis.x * (size.x * 0.5)
	var hy := xf.basis.y * (size.y * 0.5)
	var hz := xf.basis.z * (size.z * 0.5)
	var c := xf.origin
	# +X
	_face(mat, c + hx, -hz, hy, col)
	_face(mat, c - hx, hz, hy, col)
	_face(mat, c + hz, hx, hy, col)
	_face(mat, c - hz, -hx, hy, col)
	_face(mat, c + hy, hx, -hz, col)
	if not skip_bottom:
		_face(mat, c - hy, hx, hz, col)


func _face(mat: String, c: Vector3, u: Vector3, v: Vector3, col: Color) -> void:
	quad(mat, c - u - v, c + u - v, c + u + v, c - u + v, col)


## 軸平行の箱（最小・最大の角で指定）
func box_mm(mat: String, a: Vector3, b: Vector3, col := Color.WHITE) -> void:
	var c := (a + b) * 0.5
	box(mat, Transform3D(Basis(), c), (b - a).abs(), col)


## 円柱/円錐台。xf の原点が底面中心、xf.basis.y 方向に高さ h
func cylinder(mat: String, xf: Transform3D, r0: float, r1: float, h: float, segs := 8, col := Color.WHITE, cap_top := true, uv_rot := false) -> void:
	var s := _s(mat)
	var bx := xf.basis.x.normalized()
	var by := xf.basis.y.normalized()
	var bz := xf.basis.z.normalized()
	var o := xf.origin
	var base: int = s[0].size()
	var circ := TAU * maxf(r0, r1)
	for i in segs + 1:
		var a := TAU * float(i) / segs
		var d := bx * cos(a) + bz * sin(a)
		var p0 := o + d * r0
		var p1 := o + by * h + d * r1
		var slope := (r0 - r1) / maxf(h, 0.001)
		var n := (d + by * slope).normalized()
		var u := circ * float(i) / segs
		s[0].append(p0); s[0].append(p1)
		s[1].append(n); s[1].append(n)
		if uv_rot:
			s[2].append(Vector2(0.0, u)); s[2].append(Vector2(h, u))
		else:
			s[2].append(Vector2(u, h)); s[2].append(Vector2(u, 0.0))
		s[3].append(col); s[3].append(col)
	for i in segs:
		var a0 := base + i * 2
		# 外向き: (p0_i, p0_i+1, p1_i+1) は外から見て反時計回り → Godot 用に反転
		s[4].append(a0); s[4].append(a0 + 2); s[4].append(a0 + 3)
		s[4].append(a0); s[4].append(a0 + 3); s[4].append(a0 + 1)
	if cap_top and r1 > 0.001:
		var cb: int = s[0].size()
		var top := o + by * h
		s[0].append(top); s[1].append(by); s[2].append(Vector2.ZERO); s[3].append(col)
		for i in segs + 1:
			var a := TAU * float(i) / segs
			var d := bx * cos(a) + bz * sin(a)
			s[0].append(top + d * r1); s[1].append(by); s[2].append(Vector2(cos(a), sin(a)) * r1); s[3].append(col)
		for i in segs:
			s[4].append(cb); s[4].append(cb + 1 + i); s[4].append(cb + 2 + i)


## 2 点間の円柱（電線・柱など）
func rod(mat: String, a: Vector3, b: Vector3, r: float, segs := 6, col := Color.WHITE) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	cylinder(mat, Transform3D(Basis(x, y, z), a), r, r, l, segs, col, false)


## 球（楕円体）。xf の原点が中心
func sphere(mat: String, xf: Transform3D, r: float, segs := 10, rings := 6, col := Color.WHITE) -> void:
	var s := _s(mat)
	var base: int = s[0].size()
	for j in rings + 1:
		var v := float(j) / rings
		var phi := PI * v
		for i in segs + 1:
			var u := float(i) / segs
			var th := TAU * u
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			s[0].append(xf * (n * r))
			s[1].append((xf.basis * n).normalized())
			s[2].append(Vector2(u * TAU * r, v * PI * r))
			s[3].append(col)
	for j in rings:
		for i in segs:
			var a := base + j * (segs + 1) + i
			var b := a + segs + 1
			s[4].append(a); s[4].append(b); s[4].append(a + 1)
			s[4].append(a + 1); s[4].append(b); s[4].append(b + 1)


## 任意の格子面。rows[j][i] の点列。法線は外向き参照点 center から離れる向き（または up）で揃える
func grid(mat: String, rows: Array, uvs: Array, col: Color, out_ref: Vector3, use_up := false, flip := false) -> void:
	var s := _s(mat)
	var nr := rows.size()
	if nr < 2:
		return
	var nc: int = rows[0].size()
	var base: int = s[0].size()
	for j in nr:
		for i in nc:
			var p: Vector3 = rows[j][i]
			var pi0: Vector3 = rows[j][maxi(i - 1, 0)]
			var pi1: Vector3 = rows[j][mini(i + 1, nc - 1)]
			var pj0: Vector3 = rows[maxi(j - 1, 0)][i]
			var pj1: Vector3 = rows[mini(j + 1, nr - 1)][i]
			var n := (pi1 - pi0).cross(pj1 - pj0)
			if n.length_squared() < 1e-10:
				n = Vector3.UP
			n = n.normalized()
			var ref := Vector3.UP if use_up else (p - out_ref)
			if n.dot(ref) < 0.0:
				n = -n
			if flip:
				n = -n
			s[0].append(p)
			s[1].append(n)
			s[2].append(uvs[j][i])
			s[3].append(col)
	for j in nr - 1:
		for i in nc - 1:
			var a := base + j * nc + i
			var b := a + 1
			var c := a + nc + 1
			var d := a + nc
			var pa: Vector3 = s[0][a]
			var pb: Vector3 = s[0][b]
			var pc: Vector3 = s[0][c]
			var pd: Vector3 = s[0][d]
			if not _cut.is_empty():
				var inv: Transform3D = _cut[0]
				var cr: Rect2 = _cut[1]
				var all_in := true
				for q in [pa, pb, pc, pd]:
					var lq: Vector3 = inv * q
					if not cr.has_point(Vector2(lq.x, lq.z)):
						all_in = false
						break
				if all_in:
					continue
			var nn: Vector3 = s[1][a] + s[1][c]
			var fn := (pb - pa).cross(pc - pa)
			if fn.length_squared() < 1e-12:
				fn = (pc - pa).cross(pd - pa)
			if fn.dot(nn) >= 0.0:
				s[4].append(a); s[4].append(c); s[4].append(b)
				s[4].append(a); s[4].append(d); s[4].append(c)
			else:
				s[4].append(a); s[4].append(b); s[4].append(c)
				s[4].append(a); s[4].append(c); s[4].append(d)


## 日本建築の屋根（寄棟・入母屋・切妻・宝形）。
## xf: 原点=軒先の高さの中心、basis.x が長辺。hw>=hd（軒の出を含む半幅）。
## gable_s: 0=寄棟(宝形) / 0.3-0.5=入母屋 / 1=切妻。curve: 反り(>1で凹)。lift: 隅の反り上がり(m)
func roof(xf: Transform3D, hw: float, hd: float, rise: float, gable_s: float, mat: String, under_mat: String,
		col := Color.WHITE, curve := 1.35, lift := 0.0, thick := 0.3, under_col := Color(0.55, 0.45, 0.38),
		gable_mat := "", gable_col := Color.WHITE, segs := 6, side_segs := 8, clamp_r := Rect2(), clamp_y := INF) -> void:
	# clamp_r（局所 xz）の内側の頂点は高さを clamp_y までに抑える（上に載る層の床下に屋根を収める）
	if hd > hw and gable_s < 1.0:
		xf = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		var t := hw; hw = hd; hd = t
		if clamp_r.size.x > 0.0:
			clamp_r = Rect2(-clamp_r.end.y, clamp_r.position.x, clamp_r.size.y, clamp_r.size.x)
	if clamp_r.size.x > 0.0:
		_cut = [xf.affine_inverse(), clamp_r]
	var ridge := hw - hd
	var levels: Array = []  # s 値
	for k in segs + 1:
		levels.append(float(k) / segs)
	if gable_s > 0.0 and gable_s < 1.0:
		# 入母屋の折れ目に必ず頂点を置く
		var has := false
		for v in levels:
			if absf(v - gable_s) < 0.02:
				has = true
		if not has:
			levels.append(gable_s)
			levels.sort()
	var center_ref := xf * Vector3(0, -rise * 2.0, 0)
	# 各辺: 0=前(+z) 1=右(+x) 2=後(-z) 3=左(-x)
	for side in 4:
		var rows_top: Array = []
		var uv_top: Array = []
		var gable_rows: Array = []
		var gable_uv: Array = []
		var slope_acc := PackedFloat32Array()
		slope_acc.resize(side_segs + 1)
		var prev_row: Array = []
		for li in levels.size():
			var sv: float = levels[li]
			var hx := ridge + hd * maxf(sv, gable_s) if gable_s < 1.0 else hw
			var hz := hd * sv
			var y := rise * pow(1.0 - sv, curve)
			var row: Array = []
			var urow: Array = []
			for i in side_segs + 1:
				var t := float(i) / side_segs
				var lp: Vector3
				var e := absf(t * 2.0 - 1.0)
				match side:
					0: lp = Vector3(lerpf(-hx, hx, t), y, hz)
					1: lp = Vector3(hx, y, lerpf(hz, -hz, t))
					2: lp = Vector3(lerpf(hx, -hx, t), y, -hz)
					_: lp = Vector3(-hx, y, lerpf(-hz, hz, t))
				if lift > 0.0:
					var k := pow(sv, 2.5) * pow(e, 3.0)
					lp.y += lift * k
					lp.x += signf(lp.x) * lift * 0.5 * k
					lp.z += signf(lp.z) * lift * 0.5 * k
				if clamp_r.size.x > 0.0 and clamp_r.has_point(Vector2(lp.x, lp.z)):
					lp.y = minf(lp.y, clamp_y)
				var wp := xf * lp
				row.append(wp)
				var along := t * (2.0 * (hx if side % 2 == 0 else hz))
				if li > 0:
					slope_acc[i] += wp.distance_to(prev_row[i])
				urow.append(Vector2(along, slope_acc[i]))
			var is_gable_part := gable_s > 0.0 and sv <= gable_s + 0.001 and (side == 1 or side == 3)
			if is_gable_part:
				gable_rows.append(row)
				gable_uv.append(urow)
			if not (is_gable_part and sv < gable_s - 0.001):
				rows_top.append(row)
				uv_top.append(urow)
			prev_row = row
		if rows_top.size() >= 2:
			grid(mat, rows_top, uv_top, col, center_ref)
		if gable_rows.size() >= 2:
			var gm := gable_mat if gable_mat != "" else mat
			var gc := gable_col if gable_mat != "" else col
			# 妻面（三角形）: 世界座標 UV
			for r in gable_rows.size():
				for i in gable_rows[r].size():
					var p: Vector3 = gable_rows[r][i]
					gable_uv[r][i] = Vector2((xf.affine_inverse() * p).z, -p.y)
			grid(gm, gable_rows, gable_uv, gc, center_ref)
		# 軒の厚み（鼻隠し）と軒裏
		var outer: Array = rows_top[rows_top.size() - 1]
		var down := -xf.basis.y.normalized() * thick
		var band_rows := [outer, []]
		var band_uv := [[], []]
		var acc := 0.0
		for i in outer.size():
			if i > 0:
				acc += (outer[i] as Vector3).distance_to(outer[i - 1])
			band_rows[1].append(outer[i] + down)
			band_uv[0].append(Vector2(acc, 0.0))
			band_uv[1].append(Vector2(acc, thick))
		grid(under_mat, band_rows, band_uv, under_col, center_ref)
		# 軒裏: 外周（厚み分下）から内側へ
		var inner_rows: Array = []
		var inner_uv: Array = []
		var s_in := 0.55
		var hx_in := ridge + hd * maxf(s_in, gable_s) if gable_s < 1.0 else hw
		var hz_in := hd * s_in
		var y_in := rise * pow(1.0 - s_in, curve) - thick
		var row_in: Array = []
		for i in side_segs + 1:
			var t := float(i) / side_segs
			var lp: Vector3
			match side:
				0: lp = Vector3(lerpf(-hx_in, hx_in, t), y_in, hz_in)
				1: lp = Vector3(hx_in, y_in, lerpf(hz_in, -hz_in, t))
				2: lp = Vector3(lerpf(hx_in, -hx_in, t), y_in, -hz_in)
				_: lp = Vector3(-hx_in, y_in, lerpf(-hz_in, hz_in, t))
			row_in.append(xf * lp)
		inner_rows = [band_rows[1], row_in]
		for r in 2:
			var ur: Array = []
			for i in side_segs + 1:
				var p: Vector3 = inner_rows[r][i]
				ur.append(Vector2(p.x, p.z))
			inner_uv.append(ur)
		grid(under_mat, inner_rows, inner_uv, under_col, xf * Vector3(0, rise * 4.0, 0))
	_cut = []


## 棟（むね）: 屋根の頂部の箱
func ridge_cap(xf: Transform3D, hw: float, hd: float, rise: float, gable_s: float, mat: String, col: Color, size := 0.5) -> void:
	if hd > hw and gable_s < 1.0:
		xf = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		var t := hw; hw = hd; hd = t
	var hx := hw - hd + hd * gable_s if gable_s < 1.0 else hw
	if hx < 0.05:
		return
	box(mat, xf * Transform3D(Basis(), Vector3(0, rise + size * 0.35, 0)), Vector3(hx * 2.0 + size, size, size * 0.9), col)


## 確定: ArrayMesh を作って MeshInstance3D を返す
func commit(name := "Mesh", shadows := true) -> MeshInstance3D:
	sync_units()
	var am := ArrayMesh.new()
	var keys := surf.keys()
	keys.sort()
	for k in keys:
		var s: Array = surf[k]
		if s[0].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_TEX_UV] = s[2]
		arrays[Mesh.ARRAY_COLOR] = s[3]
		arrays[Mesh.ARRAY_INDEX] = s[4]
		if has_units:
			arrays[Mesh.ARRAY_TEX_UV2] = s[5]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(am.get_surface_count() - 1, WorldMaterials.get_mat(k))
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 生の ArrayMesh（MultiMesh 用）。マテリアルは materials 辞書 or WorldMaterials から
func to_mesh(materials := {}) -> ArrayMesh:
	var am := ArrayMesh.new()
	var keys := surf.keys()
	keys.sort()
	for k in keys:
		var s: Array = surf[k]
		if s[0].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_TEX_UV] = s[2]
		arrays[Mesh.ARRAY_COLOR] = s[3]
		arrays[Mesh.ARRAY_INDEX] = s[4]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m: Material = materials.get(k, null)
		if m == null:
			m = WorldMaterials.get_mat(k)
		am.surface_set_material(am.get_surface_count() - 1, m)
	return am

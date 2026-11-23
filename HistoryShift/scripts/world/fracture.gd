class_name Fracture
extends RefCounted
## 破壊ユニットのジオメトリを格子で切り分けて破片メッシュを作る／瓦礫の山を作る。
## 入力はワールド生成時に結合メッシュへ積んだ頂点配列（MeshKit.surf）とユニットの範囲。
## 破片は元の建物と同じマテリアル・頂点カラー・UV を持つので「その建物のかけら」に見える。
## 切断面は閉じない代わりに裏面（暗い色）も出して、板状の破片として見せる。

const MAX_SURFACES := 2     # 破片 1 個あたりのマテリアル数（描画コール節約）
const SKIP_MATS := ["emissive", "wire", "water"]


## def: EraWorld.unit_defs の要素 / part_mask: 1=躯体 2=屋根 / frame: 格子の座標系（原点が格子の角）
## cell: 格子の大きさ / y_min_local: これより下（切断線より下）の格子は作らない（-INF で無制限）
## 返り値: Array[{pos: Vector3, mesh: ArrayMesh, size: Vector3, area: float, mat: String}]
static func slice(def: Dictionary, part_mask: int, frame: Transform3D, cell: Vector3, y_min_local := -INF,
		max_chunks := 16, darken := 1.0) -> Array:
	var id: int = def["id"]
	var surf: Dictionary = def["surf"]
	var ranges: Dictionary = def["ranges"]
	var inv := frame.affine_inverse()
	var buckets := {}   # Vector3i -> {mat -> [verts, norms, uvs, cols]}  verts はワールド座標
	var area_of := {}   # Vector3i -> float
	for mat in ranges:
		if mat in SKIP_MATS:
			continue
		var rg: Array = ranges[mat]
		var sa: Array = surf[mat]
		var V: PackedVector3Array = sa[0]
		var N: PackedVector3Array = sa[1]
		var UV: PackedVector2Array = sa[2]
		var C: PackedColorArray = sa[3]
		var I: PackedInt32Array = sa[4]
		var U2: PackedVector2Array = sa[5]
		var i0: int = rg[2]
		var i1: int = rg[3]
		var t := i0
		while t + 2 < i1:
			var ia := I[t]
			var ib := I[t + 1]
			var ic := I[t + 2]
			t += 3
			var u := U2[ia]
			if int(u.x) != id:
				continue
			if (part_mask & (1 << int(u.y))) == 0:
				continue
			var pa := V[ia]
			var pb := V[ib]
			var pc := V[ic]
			var la := inv * pa
			var lb := inv * pb
			var lc := inv * pc
			var mn := la.min(lb).min(lc)
			var mx := la.max(lb).max(lc)
			if mx.y < y_min_local:
				continue
			var c0 := Vector3i(floori(mn.x / cell.x), floori(mn.y / cell.y), floori(mn.z / cell.z))
			var c1 := Vector3i(floori(mx.x / cell.x), floori(mx.y / cell.y), floori(mx.z / cell.z))
			if y_min_local > -INF:
				c0.y = maxi(c0.y, floori(y_min_local / cell.y))
			var tri_area := (pb - pa).cross(pc - pa).length() * 0.5
			if c0 == c1:
				_add_tri(buckets, area_of, c0, mat, pa, pb, pc, N[ia], N[ib], N[ic], UV[ia], UV[ib], UV[ic], C[ia], C[ib], C[ic], tri_area)
				continue
			var ncell := (c1.x - c0.x + 1) * (c1.y - c0.y + 1) * (c1.z - c0.z + 1)
			if ncell > 96:
				# 巨大な三角形（屋根の一枚面など）は重心の格子へ
				var cc := (la + lb + lc) / 3.0
				var ci := Vector3i(floori(cc.x / cell.x), maxi(floori(cc.y / cell.y), c0.y), floori(cc.z / cell.z))
				_add_tri(buckets, area_of, ci, mat, pa, pb, pc, N[ia], N[ib], N[ic], UV[ia], UV[ib], UV[ic], C[ia], C[ib], C[ic], tri_area)
				continue
			# 格子ごとにクリップ（Sutherland-Hodgman）
			var poly0: Array = [[la, N[ia], UV[ia], C[ia]], [lb, N[ib], UV[ib], C[ib]], [lc, N[ic], UV[ic], C[ic]]]
			for ix in range(c0.x, c1.x + 1):
				var px := _clip(_clip(poly0, 0, ix * cell.x, false), 0, (ix + 1) * cell.x, true)
				if px.size() < 3:
					continue
				for iy in range(c0.y, c1.y + 1):
					var py := _clip(_clip(px, 1, iy * cell.y, false), 1, (iy + 1) * cell.y, true)
					if py.size() < 3:
						continue
					for iz in range(c0.z, c1.z + 1):
						var pz := _clip(_clip(py, 2, iz * cell.z, false), 2, (iz + 1) * cell.z, true)
						if pz.size() < 3:
							continue
						var key := Vector3i(ix, iy, iz)
						for k in range(1, pz.size() - 1):
							var A: Array = pz[0]
							var B: Array = pz[k]
							var Cc: Array = pz[k + 1]
							var wa: Vector3 = frame * (A[0] as Vector3)
							var wb: Vector3 = frame * (B[0] as Vector3)
							var wc: Vector3 = frame * (Cc[0] as Vector3)
							var ar := (wb - wa).cross(wc - wa).length() * 0.5
							if ar < 1e-5:
								continue
							_add_tri(buckets, area_of, key, mat, wa, wb, wc, A[1], B[1], Cc[1], A[2], B[2], Cc[2], A[3], B[3], Cc[3], ar)
	# 大きい順に max_chunks 個
	var keys := buckets.keys()
	keys.sort_custom(func(a, b): return float(area_of[a]) > float(area_of[b]))
	var out: Array = []
	for key in keys:
		if out.size() >= max_chunks:
			break
		if float(area_of[key]) < 0.05:
			continue
		var ch := _build_chunk(buckets[key], darken)
		if not ch.is_empty():
			ch["area"] = area_of[key]
			out.append(ch)
	return out


static func _add_tri(buckets: Dictionary, area_of: Dictionary, key: Vector3i, mat: String, pa: Vector3, pb: Vector3, pc: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ca: Color, cb: Color, cc: Color, ar: float) -> void:
	if not buckets.has(key):
		buckets[key] = {}
		area_of[key] = 0.0
	var b: Dictionary = buckets[key]
	if not b.has(mat):
		b[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray(), 0.0]
	var e: Array = b[mat]
	e[0].append(pa); e[0].append(pb); e[0].append(pc)
	e[1].append(na); e[1].append(nb); e[1].append(nc)
	e[2].append(ua); e[2].append(ub); e[2].append(uc)
	e[3].append(ca); e[3].append(cb); e[3].append(cc)
	e[4] = float(e[4]) + ar
	area_of[key] = float(area_of[key]) + ar


static func _clip(poly: Array, axis: int, val: float, keep_less: bool) -> Array:
	var out: Array = []
	var n := poly.size()
	if n == 0:
		return out
	var sgn := 1.0 if keep_less else -1.0
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		var da := ((a[0] as Vector3)[axis] - val) * sgn
		var db := ((b[0] as Vector3)[axis] - val) * sgn
		if da <= 0.0:
			out.append(a)
		if (da <= 0.0) != (db <= 0.0):
			var t := da / (da - db)
			out.append([(a[0] as Vector3).lerp(b[0], t), ((a[1] as Vector3).lerp(b[1], t)).normalized(),
				(a[2] as Vector2).lerp(b[2], t), (a[3] as Color).lerp(b[3], t)])
	return out


## バケット 1 個 → 原点中心の ArrayMesh（表＋暗い裏面）
static func _build_chunk(b: Dictionary, darken: float) -> Dictionary:
	var mats := b.keys()
	mats.sort_custom(func(x, y): return float(b[x][4]) > float(b[y][4]))
	# 小さいマテリアルは主マテリアルへ寄せる
	var groups := {}
	for i in mats.size():
		var target: String = mats[mini(i, MAX_SURFACES - 1)] if i < MAX_SURFACES else mats[0]
		if not groups.has(target):
			groups[target] = []
		groups[target].append(mats[i])
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for m in mats:
		for p in (b[m][0] as PackedVector3Array):
			mn = mn.min(p)
			mx = mx.max(p)
	if mn.x == INF:
		return {}
	var center := (mn + mx) * 0.5
	var am := ArrayMesh.new()
	for target in groups:
		var V := PackedVector3Array()
		var Nn := PackedVector3Array()
		var UV := PackedVector2Array()
		var C := PackedColorArray()
		for m in groups[target]:
			var e: Array = b[m]
			var ev: PackedVector3Array = e[0]
			var en: PackedVector3Array = e[1]
			var eu: PackedVector2Array = e[2]
			var ec: PackedColorArray = e[3]
			var n := ev.size()
			var k := 0
			while k + 2 < n:
				for j in [0, 1, 2]:
					V.append(ev[k + j] - center); Nn.append(en[k + j]); UV.append(eu[k + j])
					C.append(Color(ec[k + j].r * darken, ec[k + j].g * darken, ec[k + j].b * darken))
				# 裏面（暗い色、逆巻き）
				for j in [0, 2, 1]:
					V.append(ev[k + j] - center); Nn.append(-en[k + j]); UV.append(eu[k + j])
					C.append(Color(ec[k + j].r * 0.45 * darken, ec[k + j].g * 0.42 * darken, ec[k + j].b * 0.4 * darken))
				k += 3
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = V
		arrays[Mesh.ARRAY_NORMAL] = Nn
		arrays[Mesh.ARRAY_TEX_UV] = UV
		arrays[Mesh.ARRAY_COLOR] = C
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(am.get_surface_count() - 1, WorldMaterials.get_mat(target))
	return {"pos": center, "mesh": am, "size": (mx - mn).max(Vector3(0.15, 0.15, 0.15)), "mat": mats[0]}


## ユニット全体を 1 つのメッシュに（沈没する船など）。原点は frame の原点
static func whole(def: Dictionary, frame: Transform3D) -> ArrayMesh:
	var big := 1000.0
	var f := frame * Transform3D(Basis(), Vector3(-big * 0.5, -big * 0.5, -big * 0.5))
	var chunks := slice(def, 3, f, Vector3(big, big, big), -INF, 1)
	if chunks.is_empty():
		return null
	# slice はバケット中心が原点 → frame 原点基準に作り直す
	var ch: Dictionary = chunks[0]
	var off: Vector3 = ch["pos"] - frame.origin
	var src: ArrayMesh = ch["mesh"]
	var am := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in V.size():
			V[i] = frame.basis.inverse() * (V[i] + off)
		var Nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in Nn.size():
			Nn[i] = frame.basis.inverse() * Nn[i]
		arr[Mesh.ARRAY_VERTEX] = V
		arr[Mesh.ARRAY_NORMAL] = Nn
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(si, src.surface_get_material(si))
	return am


## ユニットが使っているマテリアルと平均色（頂点数の多い順）
static func material_palette(def: Dictionary) -> Array:
	var id: int = def["id"]
	var out: Array = []
	for mat in def["ranges"]:
		if mat in SKIP_MATS or mat == "glass":
			continue
		var rg: Array = def["ranges"][mat]
		var sa: Array = def["surf"][mat]
		var C: PackedColorArray = sa[3]
		var U2: PackedVector2Array = sa[5]
		var acc := Color(0, 0, 0, 0)
		var n := 0
		var step := maxi(1, (int(rg[1]) - int(rg[0])) / 64)
		for i in range(int(rg[0]), int(rg[1]), step):
			if int(U2[i].x) == id:
				acc += C[i]
				n += 1
		if n > 0:
			out.append([mat, Color(acc.r / n, acc.g / n, acc.b / n), n * step])
	out.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
	return out


## 瓦礫の山（静的メッシュ）。frame の原点が足元の中心、ext は半径（x,z）、h は山の高さ
static func rubble(palette: Array, frame: Transform3D, ext: Vector2, h: float, charred: float, seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var kit := MeshKit.new()
	if palette.is_empty():
		palette = [["stonewall", Color(0.8, 0.78, 0.74), 1]]
	var total := 0.0
	for p in palette:
		total += float(p[2])
	var area := ext.x * ext.y * 4.0
	var n := clampi(int(area / 2.2), 6, 34)
	var dark := lerpf(1.0, 0.3, charred)
	# 土台の盛り上がり（低い平たい塊）
	var base_col := Color(0.62, 0.55, 0.47) * dark
	for k in 3:
		var sx := ext.x * rng.randf_range(0.5, 0.85) * (1.0 - k * 0.22)
		var sz := ext.y * rng.randf_range(0.5, 0.85) * (1.0 - k * 0.22)
		var off := Vector3(rng.randf_range(-0.2, 0.2) * ext.x, h * 0.1 * k - h * 0.1, rng.randf_range(-0.2, 0.2) * ext.y)
		var b := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
		kit.box("earth", frame * Transform3D(b, off), Vector3(sx * 2.0, h * 0.3, sz * 2.0), base_col * rng.randf_range(0.85, 1.0))
	for k in n:
		var r := rng.randf() * total
		var pick: Array = palette[0]
		for p in palette:
			r -= float(p[2])
			if r <= 0.0:
				pick = p
				break
		var mat: String = pick[0]
		var c: Color = (pick[1] as Color) * rng.randf_range(0.7, 1.0) * dark
		var u := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var d := clampf(u.length(), 0.0, 1.0)
		var y := h * (1.0 - d * d) * rng.randf_range(0.35, 0.95)
		var size: Vector3
		match mat:
			"wood", "darkwood", "bamboo":
				# 梁・板（長い）
				size = Vector3(rng.randf_range(0.18, 0.35), rng.randf_range(0.15, 0.3), rng.randf_range(1.2, 3.2))
			"rooftile", "thatch":
				size = Vector3(rng.randf_range(0.6, 1.6), rng.randf_range(0.12, 0.3), rng.randf_range(0.6, 1.4))
			_:
				size = Vector3(rng.randf_range(0.4, 1.1), rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 1.0))
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.BACK, rng.randf_range(-0.4, 0.4))
		kit.box(mat, frame * Transform3D(b, Vector3(u.x * ext.x * 0.85, y, u.y * ext.y * 0.85)), size, c, false)
	if charred > 0.5:
		# 焼け残りの柱
		for k in rng.randi_range(2, 4):
			var u := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8))
			var ph := rng.randf_range(0.8, 2.2)
			var b := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.35))
			kit.box("darkwood", frame * Transform3D(b, Vector3(u.x * ext.x, ph * 0.5, u.y * ext.y)), Vector3(0.24, ph, 0.24), Color(0.12, 0.1, 0.09))
	return kit.to_mesh()

class_name TerrainGen
extends RefCounted
## 高さマップ生成（ノイズの丘・山・海岸・川・台地・道）とメッシュ/コリジョン/マスク作成。
## 正準座標（海が +Z 側）で地形を設計し、時代ごとに 90° 単位で回転させて変化をつける。

const N := 513                       # 2^9+1（Jolt の HeightField 条件）
const CHUNKS := 8
const OUTER := 1500.0                # 遠景リングの外径（半分）

var half := 600.0
var cell := 1200.0 / 512.0
var rot := 0                         # 0..3（90°単位）
var seed_v := 1
var water_level := 0.0

var h := PackedFloat32Array()        # 最終高さ
var road := PackedFloat32Array()     # 0..1
var plaza := PackedFloat32Array()    # 0..1（舗装・広場・建物まわり）
var field := PackedFloat32Array()    # 0..1（田畑）
var forest := PackedFloat32Array()   # 0..1（森）
var occ := PackedByteArray()         # 建物などの占有
var river_d := PackedFloat32Array()  # 川からの距離（なければ大）

var n_hills := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()

var peak := Vector2(40, -470)        # 正準座標
var river_pts: PackedVector2Array    # ワールド座標
var river_surface: PackedFloat32Array
var river_half_w := 10.0
var bridges: Array = []              # [{pos:Vector2, dir:Vector2, h:float, len:float}]
var road_lines: Array = []           # [{pts:PackedVector2Array, hts:PackedFloat32Array, w:float}]


func _init(p_rot: int, p_seed: int) -> void:
	rot = p_rot
	seed_v = p_seed
	var cnt := N * N
	h.resize(cnt)
	road.resize(cnt)
	plaza.resize(cnt)
	field.resize(cnt)
	forest.resize(cnt)
	occ.resize(cnt)
	river_d.resize(cnt)
	river_d.fill(1e6)
	n_hills.seed = p_seed
	n_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_hills.frequency = 0.0028
	n_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_hills.fractal_octaves = 4
	n_detail.seed = p_seed + 7
	n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_detail.frequency = 0.014
	n_detail.fractal_octaves = 3
	n_ridge.seed = p_seed + 13
	n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_ridge.frequency = 0.0065
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_ridge.fractal_octaves = 4
	n_forest.seed = p_seed + 29
	n_forest.frequency = 0.006
	n_forest.fractal_octaves = 3


# ---------------------------------------------------------------- 座標変換
func canon_to_world(c: Vector2) -> Vector2:
	match rot:
		1: return Vector2(-c.y, c.x)
		2: return Vector2(-c.x, -c.y)
		3: return Vector2(c.y, -c.x)
	return c


func world_to_canon(w: Vector2) -> Vector2:
	match rot:
		1: return Vector2(w.y, -w.x)
		2: return Vector2(-w.x, -w.y)
		3: return Vector2(-w.y, w.x)
	return w


func canon_basis_angle() -> float:
	return -float(rot) * PI * 0.5


func gi(x: float) -> int:
	return clampi(int(round((x + half) / cell)), 0, N - 1)


func gx(i: int) -> float:
	return -half + i * cell


func shore_v(u: float) -> float:
	return 425.0 + 32.0 * sin(u * 0.0075 + 1.3) + 14.0 * sin(u * 0.021 + 0.4)


## ノイズのみの基本地形（正準座標）
func base_height(u: float, v: float) -> float:
	var hills := n_hills.get_noise_2d(u, v)
	var detail := n_detail.get_noise_2d(u, v)
	var ridge := n_ridge.get_noise_2d(u, v) * 0.5 + 0.5
	var hgt := 11.0 + hills * 17.0 + detail * 2.5
	var sd := v - shore_v(u)
	var land := clampf(-sd / 230.0, 0.0, 1.0)
	land = land * land * (3.0 - 2.0 * land)
	hgt = lerpf(1.3 + detail * 0.4, hgt, land)
	if sd > 0.0:
		hgt = lerpf(1.3, -18.0, smoothstep(0.0, 80.0, sd))
	# 外周の山
	var e := maxf(absf(u), -v)
	var edge := smoothstep(410.0, 600.0, e)
	if edge > 0.0:
		hgt += edge * (60.0 + ridge * 110.0) * clampf(-sd / 90.0, 0.0, 1.0)
	# 主峰
	var dm := Vector2(u, v).distance_to(peak)
	if dm < 520.0:
		var g := exp(-dm * dm / (2.0 * 165.0 * 165.0))
		hgt += g * (150.0 + ridge * 45.0) + g * detail * 8.0
	return hgt


# ---------------------------------------------------------------- 生成
func generate_base() -> void:
	for j in N:
		var z := gx(j)
		for i in N:
			var c := world_to_canon(Vector2(gx(i), z))
			h[j * N + i] = base_height(c.x, c.y)


## 川: canon 点列から谷を刻む
func carve_river(canon_pts: Array) -> void:
	# Catmull-Rom で細かく
	var ctrl: Array = []
	for p in canon_pts:
		ctrl.append(canon_to_world(p))
	var pts := _spline(ctrl, 6.0)
	river_pts = pts
	# 水面高: 基本地形からの単調減少
	var surf := PackedFloat32Array()
	surf.resize(pts.size())
	var run := 1e9
	for k in pts.size():
		var bh := sample_grid(pts[k].x, pts[k].y) - 2.5
		run = minf(run, bh)
		surf[k] = run
	# 平滑化と海面への収束
	for _it in 6:
		var tmp := surf.duplicate()
		for k in range(1, pts.size() - 1):
			tmp[k] = (surf[k - 1] + surf[k] + surf[k + 1]) / 3.0
		surf = tmp
	for k in pts.size():
		surf[k] = maxf(surf[k], water_level + 0.15)
		var c := world_to_canon(pts[k])
		var to_sea := shore_v(c.x) - c.y
		if to_sea < 60.0:
			surf[k] = lerpf(water_level + 0.1, surf[k], clampf(to_sea / 60.0, 0.0, 1.0))
	# 単調性を再保証
	for k in range(1, pts.size()):
		surf[k] = minf(surf[k], surf[k - 1])
	river_surface = surf
	var w := river_half_w
	var band := 70.0
	var tmp_d := PackedFloat32Array()
	tmp_d.resize(N * N)
	tmp_d.fill(1e6)
	var tmp_s := PackedFloat32Array()
	tmp_s.resize(N * N)
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (w + band)
		var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (w + band)
		for j in range(gi(mn.y), gi(mx.y) + 1):
			for i in range(gi(mn.x), gi(mx.x) + 1):
				var p := Vector2(gx(i), gx(j))
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var id := j * N + i
				if d < tmp_d[id]:
					tmp_d[id] = d
					tmp_s[id] = lerpf(surf[k], surf[k + 1], t)
	for id in N * N:
		var d := tmp_d[id]
		if d > w + band:
			continue
		river_d[id] = d
		var s := tmp_s[id]
		var hh: float
		if d < w:
			var q := d / w
			hh = s - 2.6 * (1.0 - q * q) - 0.25
		else:
			var bank := s + 0.5 + (d - w) * 0.22 + 0.0
			var t := smoothstep(w, w + band, d)
			hh = lerpf(bank, h[id], t)
			hh = maxf(hh, s + 0.35)
		h[id] = hh


## 台地（円・カプセル）: h を目標高さへ寄せる
func flatten(pos: Vector2, r: float, fall: float, target: float, pos2 = null) -> void:
	var a := pos
	var b: Vector2 = pos if pos2 == null else pos2
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (r + fall)
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (r + fall)
	for j in range(gi(mn.y), gi(mx.y) + 1):
		for i in range(gi(mn.x), gi(mx.x) + 1):
			var p := Vector2(gx(i), gx(j))
			var d := _seg_dist(p, a, b)
			if d > r + fall:
				continue
			var t := 1.0 - smoothstep(r, r + fall, d)
			var id := j * N + i
			if river_d[id] < river_half_w + 4.0:
				continue
			h[id] = lerpf(h[id], target, t)


## 道: 端点の間をうねらせた曲線で結び、地形を均す
func add_road(a: Vector2, b: Vector2, half_w: float, wiggle: float, rng: RandomNumberGenerator) -> Dictionary:
	var ctrl: Array = [a]
	var d := b - a
	var L := d.length()
	var nrm := Vector2(-d.y, d.x).normalized()
	var segs := maxi(2, int(L / 110.0))
	for k in range(1, segs):
		var t := float(k) / segs
		ctrl.append(a + d * t + nrm * rng.randf_range(-wiggle, wiggle) * sin(t * PI))
	ctrl.append(b)
	var pts := _spline(ctrl, 4.0)
	# 中心線の高さ
	var hts := PackedFloat32Array()
	hts.resize(pts.size())
	for k in pts.size():
		hts[k] = sample_grid(pts[k].x, pts[k].y)
		var rd := river_dist_at(pts[k].x, pts[k].y)
		if rd < river_half_w + 18.0:
			hts[k] = maxf(hts[k], river_surface_near(pts[k]) + 1.6)
	for _it in 10:
		var tmp := hts.duplicate()
		for k in range(1, pts.size() - 1):
			tmp[k] = (hts[k - 1] + hts[k] * 2.0 + hts[k + 1]) * 0.25
		hts = tmp
	# 勾配制限
	var maxg := 0.13 * 4.0
	for k in range(1, pts.size()):
		hts[k] = clampf(hts[k], hts[k - 1] - maxg, hts[k - 1] + maxg)
	for k in range(pts.size() - 2, -1, -1):
		hts[k] = clampf(hts[k], hts[k + 1] - maxg, hts[k + 1] + maxg)
	var line := {"pts": pts, "hts": hts, "w": half_w}
	road_lines.append(line)
	return line


## 全道路をまとめてラスタライズ（交差部は重みの大きい方）
func apply_roads() -> void:
	var fall := 14.0
	var best_w := PackedFloat32Array()
	best_w.resize(N * N)
	var best_h := PackedFloat32Array()
	best_h.resize(N * N)
	for line in road_lines:
		var pts: PackedVector2Array = line["pts"]
		var hts: PackedFloat32Array = line["hts"]
		var w: float = line["w"]
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (w + fall)
			var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (w + fall)
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 0.0001)
			for j in range(gi(mn.y), gi(mx.y) + 1):
				for i in range(gi(mn.x), gi(mx.x) + 1):
					var p := Vector2(gx(i), gx(j))
					var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
					var dd := p.distance_to(a + ab * t)
					if dd > w + fall:
						continue
					var id := j * N + i
					var wt := 1.0 - smoothstep(w + 0.5, w + fall, dd)
					if river_d[id] < river_half_w + 3.0:
						wt = 0.0
					if wt > best_w[id]:
						best_w[id] = wt
						best_h[id] = lerpf(hts[k], hts[k + 1], t)
					var m := 1.0 - smoothstep(w - 1.2, w + 0.6, dd)
					if river_d[id] < river_half_w + 1.0:
						m = 0.0
					if m > road[id]:
						road[id] = m
	for id in N * N:
		if best_w[id] > 0.0:
			h[id] = lerpf(h[id], best_h[id], best_w[id])
	_find_bridges()


func _find_bridges() -> void:
	if river_pts.size() < 2:
		return
	for line in road_lines:
		var pts: PackedVector2Array = line["pts"]
		var hts: PackedFloat32Array = line["hts"]
		for k in pts.size() - 1:
			for r in river_pts.size() - 1:
				var hit = Geometry2D.segment_intersects_segment(pts[k], pts[k + 1], river_pts[r], river_pts[r + 1])
				if hit != null:
					var dir: Vector2 = (pts[k + 1] - pts[k]).normalized()
					var rdir: Vector2 = (river_pts[r + 1] - river_pts[r]).normalized()
					var sin_a := absf(dir.cross(rdir))
					var length := (river_half_w * 2.0 + 10.0) / maxf(sin_a, 0.5)
					var bh := maxf(hts[k], river_surface[r] + 2.2)
					bridges.append({"pos": hit, "dir": dir, "h": bh, "len": length, "w": float(line["w"]) * 2.0 + 1.0, "surface": river_surface[r]})


## 周囲より低く掘る（池・堀）。sdf<0 の内側が水域
func carve_sdf(sdf: Callable, bbox: Rect2, ref_h: float, depth: float, edge := 3.0) -> void:
	for j in range(gi(bbox.position.y), gi(bbox.end.y) + 1):
		for i in range(gi(bbox.position.x), gi(bbox.end.x) + 1):
			var p := Vector2(gx(i), gx(j))
			var d: float = sdf.call(p)
			if d > edge:
				continue
			var t := smoothstep(edge, -edge, d)
			var id := j * N + i
			h[id] = minf(h[id], lerpf(ref_h, ref_h - depth, t))


## 盛り土（古墳など）。sdf<0 の内側で高さ profile
func mound_sdf(sdf: Callable, bbox: Rect2, ref_h: float, height: float, slope_w: float) -> void:
	for j in range(gi(bbox.position.y), gi(bbox.end.y) + 1):
		for i in range(gi(bbox.position.x), gi(bbox.end.x) + 1):
			var p := Vector2(gx(i), gx(j))
			var d: float = sdf.call(p)
			if d > 0.5:
				continue
			var t := clampf(-d / slope_w, 0.0, 1.0)
			# 段築: 3 段のテラス
			var terr := t * 3.0
			var step_t := (floor(terr) + smoothstep(0.15, 0.85, fmod(terr, 1.0))) / 3.0
			var prof := lerpf(t, step_t, 0.55)
			var id := j * N + i
			h[id] = maxf(h[id], ref_h + height * prof)


# ---------------------------------------------------------------- マスク
func paint_rect(arr: PackedFloat32Array, center: Vector2, angle: float, hw: float, hd: float, val := 1.0, soft := 1.0) -> void:
	var ca := cos(angle)
	var sa := sin(angle)
	var r := Vector2(hw, hd).length() + soft
	for j in range(gi(center.y - r), gi(center.y + r) + 1):
		for i in range(gi(center.x - r), gi(center.x + r) + 1):
			var p := Vector2(gx(i), gx(j)) - center
			var lx := p.x * ca + p.y * sa
			var lz := -p.x * sa + p.y * ca
			var dx := absf(lx) - hw
			var dz := absf(lz) - hd
			var d := maxf(dx, dz)
			if d > soft:
				continue
			var m := val * (1.0 - smoothstep(-soft, soft, d))
			var id := j * N + i
			if m > arr[id]:
				arr[id] = m


func paint_line(arr: PackedFloat32Array, a: Vector2, b: Vector2, half_w: float, val := 1.0, soft := 1.0) -> void:
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (half_w + soft)
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (half_w + soft)
	for j in range(gi(mn.y), gi(mx.y) + 1):
		for i in range(gi(mn.x), gi(mx.x) + 1):
			var p := Vector2(gx(i), gx(j))
			var d := _seg_dist(p, a, b) - half_w
			if d > soft:
				continue
			var m := val * (1.0 - smoothstep(-soft, soft, d))
			var id := j * N + i
			if m > arr[id]:
				arr[id] = m


func paint_circle(arr: PackedFloat32Array, c: Vector2, r: float, val := 1.0, soft := 2.0) -> void:
	paint_line(arr, c, c, r, val, soft)


func occupy_rect(center: Vector2, angle: float, hw: float, hd: float) -> void:
	var ca := cos(angle)
	var sa := sin(angle)
	var r := Vector2(hw, hd).length() + cell
	for j in range(gi(center.y - r), gi(center.y + r) + 1):
		for i in range(gi(center.x - r), gi(center.x + r) + 1):
			var p := Vector2(gx(i), gx(j)) - center
			var lx := p.x * ca + p.y * sa
			var lz := -p.x * sa + p.y * ca
			if absf(lx) <= hw + cell * 0.5 and absf(lz) <= hd + cell * 0.5:
				occ[j * N + i] = 1


func is_occupied(x: float, z: float) -> bool:
	return occ[gi(z) * N + gi(x)] != 0


func compute_forest(amount: float) -> void:
	for j in N:
		for i in N:
			var id := j * N + i
			var x := gx(i)
			var z := gx(j)
			var f := n_forest.get_noise_2d(x, z) * 0.5 + 0.5
			f = smoothstep(0.62 - amount * 0.35, 0.78 - amount * 0.35, f)
			var hh := h[id]
			if hh < water_level + 2.5:
				f = 0.0
			# 山・外周は森が多い
			var c := world_to_canon(Vector2(x, z))
			var e := maxf(absf(c.x), -c.y)
			f = maxf(f, smoothstep(380.0, 470.0, e) * 0.9 * clampf((hh - 6.0) / 10.0, 0.0, 1.0))
			var dm := c.distance_to(peak)
			f = maxf(f, (1.0 - smoothstep(150.0, 300.0, dm)) * 0.85)
			f *= (1.0 - road[id]) * (1.0 - plaza[id]) * (1.0 - field[id])
			if river_d[id] < river_half_w + 6.0:
				f = 0.0
			forest[id] = f


# ---------------------------------------------------------------- 問い合わせ
func sample_grid(x: float, z: float) -> float:
	var fx := clampf((x + half) / cell, 0.0, N - 1.001)
	var fz := clampf((z + half) / cell, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := h[j * N + i]
	var b := h[j * N + i + 1]
	var c := h[(j + 1) * N + i]
	var d := h[(j + 1) * N + i + 1]
	# 三角形分割に合わせた補間（メッシュと一致）
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


func height_at(x: float, z: float) -> float:
	if absf(x) > half or absf(z) > half:
		var c := world_to_canon(Vector2(x, z))
		return base_height(c.x, c.y)
	return sample_grid(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var hl := sample_grid(x - e, z)
	var hr := sample_grid(x + e, z)
	var hd := sample_grid(x, z - e)
	var hu := sample_grid(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func mask_at(arr: PackedFloat32Array, x: float, z: float) -> float:
	return arr[gi(z) * N + gi(x)]


func river_dist_at(x: float, z: float) -> float:
	return river_d[gi(z) * N + gi(x)]


func river_surface_near(p: Vector2) -> float:
	var best := 1e9
	var s := water_level
	for k in range(0, river_pts.size(), 2):
		var d := p.distance_squared_to(river_pts[k])
		if d < best:
			best = d
			s = river_surface[k]
	return s


func is_water(x: float, z: float) -> bool:
	if height_at(x, z) < water_level + 0.4:
		return true
	return river_dist_at(x, z) < river_half_w + 1.5


# ---------------------------------------------------------------- 出力
func make_height_image() -> Image:
	var data := h.to_byte_array()
	return Image.create_from_data(N, N, false, Image.FORMAT_RF, data)


func make_control_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(N * N * 4)
	for id in N * N:
		bytes[id * 4] = int(clampf(road[id], 0.0, 1.0) * 255.0)
		var pz := plaza[id]
		if occ[id] != 0:
			pz = maxf(pz, 0.6)
		bytes[id * 4 + 1] = int(clampf(pz, 0.0, 1.0) * 255.0)
		bytes[id * 4 + 2] = int(clampf(field[id], 0.0, 1.0) * 255.0)
		bytes[id * 4 + 3] = int(clampf(forest[id], 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, bytes)
	return img


func make_collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(cell, 1.0, cell)
	body.add_child(cs)
	return body


## チャンク分割した地形メッシュ（LOD0: 全解像度 / LOD1: 1/4）
func build_meshes(parent: Node3D, mat: Material, quality: int) -> void:
	var per := (N - 1) / CHUNKS   # 64
	var lod_specs := [[1, 0.0, 340.0], [4, 300.0, 0.0]]
	if quality <= 0:
		lod_specs = [[2, 0.0, 300.0], [4, 260.0, 0.0]]
	for cj in CHUNKS:
		for ci in CHUNKS:
			for spec in lod_specs:
				var step: int = spec[0]
				var mesh := _chunk_mesh(ci * per, cj * per, per, step)
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = mat
				mi.name = "T%d_%d_%d" % [ci, cj, step]
				mi.visibility_range_begin = spec[1]
				mi.visibility_range_end = spec[2]
				if spec[1] > 0.0:
					mi.visibility_range_begin_margin = 20.0
				if spec[2] > 0.0:
					mi.visibility_range_end_margin = 20.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				parent.add_child(mi)


func _chunk_mesh(i0: int, j0: int, per: int, step: int) -> ArrayMesh:
	var n := per / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n + n * 4)
	norms.resize(n * n + n * 4)
	var k := 0
	for jj in n:
		var j := j0 + jj * step
		for ii in n:
			var i := i0 + ii * step
			var id := j * N + i
			verts[k] = Vector3(gx(i), h[id], gx(j))
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, N - 1)
			var jd := maxi(j - 1, 0)
			var ju := mini(j + 1, N - 1)
			norms[k] = Vector3((h[j * N + il] - h[j * N + ir]) / ((ir - il) * cell), 2.0 / 2.0, (h[jd * N + i] - h[ju * N + i]) / ((ju - jd) * cell)).normalized()
			k += 1
	var idx := PackedInt32Array()
	for jj in n - 1:
		for ii in n - 1:
			var a := jj * n + ii
			var b := a + 1
			var c := a + n
			var d := c + 1
			# 対角は a-d（sample_grid と一致: tx+tz<=1 側が a,b,c）
			idx.append(a); idx.append(b); idx.append(c)
			idx.append(b); idx.append(d); idx.append(c)
	# スカート（LOD 境界の隙間隠し）
	var edges := [[], [], [], []]
	for t in n:
		edges[0].append(t)                    # 上辺 (jj=0)
		edges[1].append((n - 1) * n + t)      # 下辺
		edges[2].append(t * n)                # 左辺
		edges[3].append(t * n + n - 1)        # 右辺
	for e in 4:
		var sb := k
		for t in n:
			var src: int = edges[e][t]
			verts[k] = verts[src] - Vector3(0, 3.0 * step, 0)
			norms[k] = norms[src]
			k += 1
		for t in n - 1:
			var a: int = edges[e][t]
			var b: int = edges[e][t + 1]
			var c := sb + t
			var d := sb + t + 1
			# 両面（向きを気にしない）
			idx.append(a); idx.append(b); idx.append(c)
			idx.append(b); idx.append(d); idx.append(c)
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## 遠景リング（コリジョンなし）: プレイ範囲の外側の山並み・海底
func build_outer(parent: Node3D, mat: Material) -> void:
	var step := 25.0
	var n := int(OUTER * 2.0 / step) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			var x := -OUTER + i * step
			var z := -OUTER + j * step
			var hh: float
			if absf(x) < half - 1.0 and absf(z) < half - 1.0:
				hh = -60.0
			else:
				var c := world_to_canon(Vector2(x, z))
				hh = base_height(c.x, c.y) - 0.6
				# 外側はさらに山を高く
				var e := maxf(absf(c.x), -c.y)
				var sd := c.y - shore_v(c.x)
				if sd < 0.0:
					hh += smoothstep(600.0, 900.0, e) * (90.0 + 60.0 * (n_ridge.get_noise_2d(c.x * 0.5, c.y * 0.5) * 0.5 + 0.5))
			hs[j * n + i] = hh
			verts[j * n + i] = Vector3(x, hh, z)
	for j in n:
		for i in n:
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr := hs[j * n + mini(i + 1, n - 1)]
			var hd := hs[maxi(j - 1, 0) * n + i]
			var hu := hs[mini(j + 1, n - 1) * n + i]
			norms[j * n + i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var x := -OUTER + (i + 0.5) * step
			var z := -OUTER + (j + 0.5) * step
			if absf(x) < half - step and absf(z) < half - step:
				continue
			var a := j * n + i
			idx.append(a); idx.append(a + 1); idx.append(a + n)
			idx.append(a + 1); idx.append(a + n + 1); idx.append(a + n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "OuterTerrain"
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---------------------------------------------------------------- ユーティリティ
static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _spline(ctrl: Array, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for k in n - 1:
		var p0: Vector2 = ctrl[maxi(k - 1, 0)]
		var p1: Vector2 = ctrl[k]
		var p2: Vector2 = ctrl[k + 1]
		var p3: Vector2 = ctrl[mini(k + 2, n - 1)]
		var steps := maxi(1, int(p1.distance_to(p2) / spacing))
		for s in steps:
			var t := float(s) / steps
			out.append(p1.cubic_interpolate(p2, p0, p3, t))
	out.append(ctrl[n - 1])
	return out

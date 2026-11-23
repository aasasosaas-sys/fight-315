class_name WorldLayouts
extends RefCounted
## 時代 × ランドマークごとの配置。ローカル座標は各ランドマークの台地中心が原点、
## -Z が北（山側）、+Z が南（海側）。中心付近（半径 ~12m）は広場として空けておく（landmark_pos）。

var w: EraWorld
var t: TerrainGen
var a: Architecture
var era := ""
var style: Dictionary
var rng := RandomNumberGenerator.new()
var extra_car_spawns: Array = []
var plane_spawns: Array = []
var kofun := {}          # 縄文・古墳の前方後円墳


func _init(world: EraWorld) -> void:
	w = world
	t = world.terrain
	era = world.era_id
	style = world.style
	rng.seed = world.rng.seed + 31


# ================================================================ 地形への追加
func plan_terrain() -> void:
	pass


func terrain_features() -> void:
	var lm: Dictionary
	match era:
		"jomon_kofun":
			# 前方後円墳（戦場の北側）
			lm = w.landmarks["battlefield"]
			var xf: Transform3D = lm["xf"]
			var c3 := xf * Vector3(22, 0, -4)
			var c := Vector2(c3.x, c3.z)
			var fwd3 := xf.basis * Vector3(-1, 0, 0)
			var fwd := Vector2(fwd3.x, fwd3.z).normalized()
			kofun = {"c": c, "fwd": fwd, "R": 16.0, "L": 32.0, "w0": 12.0, "w1": 25.0, "h": lm["h"]}
			var sdf := func(p: Vector2) -> float: return _keyhole_sdf(p, kofun)
			var bb := Rect2(c - Vector2(70, 70), Vector2(140, 140))
			t.carve_sdf(func(p: Vector2) -> float:
				var d: float = sdf.call(p)
				return absf(d - 6.5) - 4.5, bb, lm["h"], 2.2, 1.5)
			t.mound_sdf(sdf, bb, lm["h"], 7.5, 13.0)
			w.add_water_rect(Vector3(c.x + fwd.x * 14.0, float(lm["h"]) - 1.0, c.y + fwd.y * 14.0), Vector2(100, 62), atan2(-fwd.y, fwd.x))
		"asuka_nara":
			# 瀬田の唐橋: 戦場を横切る川
			lm = w.landmarks["battlefield"]
			_channel(lm, Vector2(0, -24), Vector2(0, 24), 6.0)
			# 水城: 大宰府の前の長い土塁（地形として盛る）
			var cl: Dictionary = w.landmarks["castle"]
			var p0: Vector3 = cl["xf"] * Vector3(-46, 0, 40)
			var p1: Vector3 = cl["xf"] * Vector3(-6, 0, 40)
			var p2: Vector3 = cl["xf"] * Vector3(6, 0, 40)
			var p3: Vector3 = cl["xf"] * Vector3(46, 0, 40)
			for seg in [[p0, p1], [p2, p3]]:
				var A := Vector2(seg[0].x, seg[0].z)
				var B := Vector2(seg[1].x, seg[1].z)
				var sdf := func(p: Vector2) -> float: return TerrainGen._seg_dist(p, A, B) - 6.0
				t.mound_sdf(sdf, Rect2(Vector2(minf(A.x, B.x), minf(A.y, B.y)) - Vector2(14, 14), (B - A).abs() + Vector2(28, 28)), cl["h"], 5.5, 6.0)
		"sengoku", "edo":
			# 城の堀
			lm = w.landmarks["castle" if era == "sengoku" else "capital"]
			var xf: Transform3D = lm["xf"]
			var off := Vector3(0, 0, -30) if era == "edo" else Vector3.ZERO
			var c3 := xf * off
			var half := 26.0 if era == "sengoku" else 21.0
			var ang := float(lm["angle"])
			var sdf := func(p: Vector2) -> float:
				var q := (p - Vector2(c3.x, c3.z)).rotated(ang)
				var d := maxf(absf(q.x), absf(q.y)) - half
				return absf(d - 9.0) - 6.0
			t.carve_sdf(sdf, Rect2(Vector2(c3.x, c3.z) - Vector2(60, 60), Vector2(120, 120)), lm["h"], 3.0, 1.5)
			w.add_water_rect(Vector3(c3.x, float(lm["h"]) - 1.3, c3.z), Vector2((half + 16.0) * 2.0, (half + 16.0) * 2.0), -ang)
		"meiji_taisho":
			# 宮城前の濠
			lm = w.landmarks["capital"]
			_channel(lm, Vector2(-48, -46), Vector2(48, -46), 6.0)


func _channel(lm: Dictionary, la: Vector2, lb: Vector2, half_w: float) -> void:
	var xf: Transform3D = lm["xf"]
	var pa := xf * Vector3(la.x, 0, la.y)
	var pb := xf * Vector3(lb.x, 0, lb.y)
	var A := Vector2(pa.x, pa.z)
	var B := Vector2(pb.x, pb.z)
	var sdf := func(p: Vector2) -> float: return TerrainGen._seg_dist(p, A, B) - half_w
	var mn := Vector2(minf(A.x, B.x), minf(A.y, B.y)) - Vector2(30, 30)
	var mx := Vector2(maxf(A.x, B.x), maxf(A.y, B.y)) + Vector2(30, 30)
	t.carve_sdf(sdf, Rect2(mn, mx - mn), lm["h"], 2.8, 2.0)
	var mid := (pa + pb) * 0.5
	var d := B - A
	w.add_water_rect(Vector3(mid.x, float(lm["h"]) - 1.2, mid.z), Vector2(half_w * 2.0 + 6.0, d.length() + 6.0), atan2(d.x, d.y))
	lm["channel"] = [A, B, half_w]


static func _keyhole_sdf(p: Vector2, k: Dictionary) -> float:
	var c: Vector2 = k["c"]
	var fwd: Vector2 = k["fwd"]
	var d_circle := p.distance_to(c) - float(k["R"])
	# 前方部（台形）
	var rel := p - c
	var along := rel.dot(fwd)
	var side := absf(rel.dot(Vector2(-fwd.y, fwd.x)))
	var L: float = k["L"]
	var t := clampf(along / (float(k["R"]) + L), 0.0, 1.0)
	var half_w := lerpf(float(k["w0"]), float(k["w1"]), t) * 0.5
	var d_trap := maxf(maxf(side - half_w, -along), along - (float(k["R"]) + L))
	return minf(d_circle, d_trap)


# ================================================================ 共通ヘルパ
func wp(lm: Dictionary, x: float, z: float) -> Vector3:
	var p: Vector3 = lm["xf"] * Vector3(x, 0, z)
	p.y = t.height_at(p.x, p.z)
	return p


func pl(lm: Dictionary, x: float, z: float, rot: float, foot := Vector2(6, 6)) -> Transform3D:
	return a.place(lm["xf"], x, z, rot, foot)


## 通りを塗り、町人の歩く点を記録
func street(lm: Dictionary, ax: float, az: float, bx_: float, bz: float, hw := 3.0, kind := "road") -> void:
	var pa := wp(lm, ax, az)
	var pb := wp(lm, bx_, bz)
	var A := Vector2(pa.x, pa.z)
	var B := Vector2(pb.x, pb.z)
	t.paint_line(t.road if kind == "road" else t.plaza, A, B, hw, 1.0, 0.8)
	var L := A.distance_to(B)
	var n := int(L / 9.0)
	var side := (B - A).normalized().orthogonal() * maxf(hw - 1.2, 0.5)
	for k in n + 1:
		var p := A.lerp(B, float(k) / maxf(n, 1))
		for s in [-1.0, 1.0]:
			var q: Vector2 = p + side * s
			if not t.is_occupied(q.x, q.y):
				w.add_street_point(Vector3(q.x, t.height_at(q.x, q.y), q.y))


func ring(lm: Dictionary, rr: float, hw := 3.0) -> void:
	var n := 40
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var pa := wp(lm, cos(a0) * rr, sin(a0) * rr)
		var pb := wp(lm, cos(a1) * rr, sin(a1) * rr)
		t.paint_line(t.road, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), hw, 0.9, 0.8)


## 外から来た道を台地の中心へつなぐ（建物の下に隠れる部分は見えない）
func _connect_roads(lm: Dictionary) -> void:
	if lm.has("a") or lm["key"] == "mountain":
		return
	var c: Vector2 = lm["center"]
	var r: float = lm["r"]
	for line in t.road_lines:
		var pts: PackedVector2Array = line["pts"]
		for end in [pts[0], pts[pts.size() - 1]]:
			var ep: Vector2 = end
			if ep.distance_to(c) < r * 1.05:
				var inner := c + (ep - c).normalized() * r * 0.15
				t.paint_line(t.road, ep, inner, float(line["w"]) - 0.8, 0.9, 0.8)


func plaza(lm: Dictionary, x: float, z: float, hw: float, hd: float, val := 0.9) -> void:
	var p := wp(lm, x, z)
	t.paint_rect(t.plaza, Vector2(p.x, p.z), -float(lm["angle"]), hw, hd, val, 1.5)


func field(lm: Dictionary, x: float, z: float, hw: float, hd: float) -> void:
	var p := wp(lm, x, z)
	# 平らな所だけ
	for c in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]:
		var q := wp(lm, x + c.x, z + c.y)
		if absf(q.y - p.y) > 1.2 or t.is_water(q.x, q.z):
			return
	t.paint_rect(t.field, Vector2(p.x, p.z), -float(lm["angle"]), hw, hd, 1.0, 0.6)
	# あぜ道
	t.paint_rect(t.plaza, Vector2(p.x, p.z), -float(lm["angle"]), hw + 1.0, hd + 1.0, 0.0, 0.5)


func corners(lm: Dictionary, x: float, z: float, hw: float, hd: float) -> Array:
	return [wp(lm, x - hw, z - hd), wp(lm, x + hw, z - hd), wp(lm, x + hw, z + hd), wp(lm, x - hw, z + hd)]


func tree(lm: Dictionary, sp: String, x: float, z: float, s := 1.0) -> void:
	var p := wp(lm, x, z)
	if t.is_occupied(p.x, p.z):
		return
	w.deco_trees.append([sp, p - Vector3(0, 0.1, 0), s])


## 通りに面して区画を並べる。side=+1 は進行方向の右側
func lots(lm: Dictionary, ax: float, az: float, bx_: float, bz: float, side: float, offset: float, depth: float, wmin: float, wmax: float, builder: Callable, gap := 0.4) -> void:
	var A := Vector2(ax, az)
	var B := Vector2(bx_, bz)
	var d := (B - A).normalized()
	var n := Vector2(-d.y, d.x) * side
	var L := A.distance_to(B)
	var s := 0.0
	while s < L:
		var fw := rng.randf_range(wmin, wmax)
		if s + fw > L:
			break
		var c := A + d * (s + fw * 0.5) + n * (offset + depth * 0.5)
		var front := -n
		var rot := atan2(front.x, front.y)
		var xf := pl(lm, c.x, c.y, rot, Vector2(fw, depth))
		builder.call(xf, fw - gap, depth)
		s += fw


## 格子状の町。half=範囲の半幅、block=街区の大きさ
func grid_town(lm: Dictionary, cx: float, cz: float, half_x: float, half_z: float, block: float, street_hw: float, depth: float, wmin: float, wmax: float, builder: Callable, skip := Rect2()) -> void:
	var nx := int(half_x * 2.0 / block)
	var nz := int(half_z * 2.0 / block)
	var x0 := cx - nx * block * 0.5
	var z0 := cz - nz * block * 0.5
	for i in nx + 1:
		street(lm, x0 + i * block, z0, x0 + i * block, z0 + nz * block, street_hw)
	for j in nz + 1:
		street(lm, x0, z0 + j * block, x0 + nx * block, z0 + j * block, street_hw)
	for i in nx:
		for j in nz:
			var bx0 := x0 + i * block
			var bz0 := z0 + j * block
			var center := Vector2(bx0 + block * 0.5, bz0 + block * 0.5)
			if skip.has_area() and skip.has_point(center):
				continue
			var e := street_hw + 0.6
			# 街区の 4 辺に外向きの区画
			lots(lm, bx0 + e, bz0, bx0 + block - e, bz0, -1.0, e, depth, wmin, wmax, builder)       # 北辺
			lots(lm, bx0 + block - e, bz0 + block, bx0 + e, bz0 + block, -1.0, e, depth, wmin, wmax, builder)   # 南辺
			if block - 2.0 * (e + depth) > wmin:
				lots(lm, bx0, bz0 + block - e - depth, bx0, bz0 + e + depth, -1.0, e, depth, wmin, wmax, builder)   # 西辺
				lots(lm, bx0 + block, bz0 + e + depth, bx0 + block, bz0 + block - e - depth, -1.0, e, depth, wmin, wmax, builder)   # 東辺


# ================================================================ 全体
func build_all() -> void:
	a = Architecture.new(w)
	for key in ["capital", "village", "temple", "port", "castle", "battlefield", "mountain"]:
		var lm: Dictionary = w.landmarks[key]
		_connect_roads(lm)
		plaza(lm, 0, 0, 13, 13, 0.85)
		var fn := "_%s_%s" % [key, _era_group(key)]
		a.landmark = key
		if has_method(fn):
			call(fn, lm)
		a.flush("Arch_" + key)
	a.landmark = "river"
	_bridges()
	a.landmark = "roads"
	_road_decor()
	a.flush("Arch_roads")
	a.landmark = ""
	_process_ponds()
	_lamp_lights()
	# 後から建った建物・池の上の歩行点を除く
	var kept: Array = []
	for p in w._street_points:
		if not t.is_occupied(p.x, p.z) and not t.is_water(p.x, p.z):
			p.y = t.height_at(p.x, p.z)
			kept.append(p)
	w._street_points = kept
	# スポーン: 都の南寄りの大通り
	var cap: Dictionary = w.landmarks["capital"]
	var sp := wp(cap, 0, 8)
	for zz in [30.0, 40.0, 50.0, 60.0, 70.0, 85.0, 20.0, 12.0]:
		var c := wp(cap, 0, zz)
		if not t.is_occupied(c.x, c.z) and not t.is_water(c.x, c.z) and t.normal_at(c.x, c.z).y > 0.95 and absf(c.y - float(cap["h"])) < 0.6:
			sp = c
			break
	w.player_spawn = sp + Vector3(0, 0.1, 0)


func _era_group(_key: String) -> String:
	return era


func _process_ponds() -> void:
	for pr in w.pond_requests:
		var c: Vector3 = pr["center"]
		var rx: float = pr["rx"]
		var rz: float = pr["rz"]
		var ang: float = pr["angle"]
		var ref := t.height_at(c.x, c.z)
		var sdf := func(p: Vector2) -> float:
			var q := (p - Vector2(c.x, c.z)).rotated(ang)
			return (Vector2(q.x / rx, q.y / rz).length() - 1.0) * minf(rx, rz)
		t.carve_sdf(sdf, Rect2(Vector2(c.x, c.z) - Vector2(rx + 8, rx + 8) - Vector2(rz, rz), Vector2(rx + rz + 8, rx + rz + 8) * 2.0), ref, 2.0, 2.0)
		w.add_water_rect(Vector3(c.x, ref - 0.55, c.z), Vector2(rx * 2.0 + 4.0, rz * 2.0 + 4.0), ang)
		t.occupy_rect(Vector2(c.x, c.z), -ang, rx, rz)


func _lamp_lights() -> void:
	var n := 0
	for p in a.lamp_points:
		n += 1
		if n % 3 != 0 or n > 90:
			continue
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(1.0, 0.75, 0.45) if style["lamp"] != "electric" else Color(1.0, 0.92, 0.8)
		l.light_energy = 1.4
		l.omni_range = 9.0
		l.shadow_enabled = false
		l.visible = false
		l.add_to_group("world_night_light")
		w.add_child(l)


func _bridges() -> void:
	var kind := "wood"
	match era:
		"asuka_nara", "heian": kind = "vermilion"
		"meiji_taisho": kind = "stone"
		"showa": kind = "steel"
	for b in t.bridges:
		a.bridge(b["pos"], b["dir"], b["len"], b["w"], b["h"], kind, 0.0 if kind in ["steel", "stone"] else 0.6)


func _road_decor() -> void:
	var lamp_kind: String = style["lamp"]
	var spacing := 34.0
	for line in t.road_lines:
		var pts: PackedVector2Array = line["pts"]
		var hw: float = line["w"]
		var acc := 0.0
		var poles: Array = []
		for k in range(1, pts.size()):
			acc += pts[k].distance_to(pts[k - 1])
			if acc < spacing:
				continue
			acc = 0.0
			var d := (pts[mini(k + 1, pts.size() - 1)] - pts[k - 1]).normalized()
			var side := Vector2(-d.y, d.x) * (hw + 1.6)
			var p := pts[k] + side
			if t.is_occupied(p.x, p.y) or t.river_dist_at(p.x, p.y) < t.river_half_w + 4.0:
				if poles.size() > 1:
					a.utility_line(poles)
				poles = []
				continue
			var p3 := Vector3(p.x, 0, p.y)
			if lamp_kind == "gas" or lamp_kind == "electric":
				if era == "showa":
					poles.append(p3)
				else:
					a.lamp(p3, "gas")
		if poles.size() > 1:
			a.utility_line(poles)
	if era == "meiji_taisho":
		# 明治: 電信柱（主要道路のみ反対側）
		for line in t.road_lines.slice(0, 3):
			var pts: PackedVector2Array = line["pts"]
			var poles: Array = []
			for k in range(4, pts.size() - 4, 11):
				var d := (pts[k + 1] - pts[k - 1]).normalized()
				var p := pts[k] - Vector2(-d.y, d.x) * (float(line["w"]) + 2.0)
				if t.is_occupied(p.x, p.y) or t.river_dist_at(p.x, p.y) < t.river_half_w + 4.0:
					if poles.size() > 1:
						a.utility_line(poles, 7.0)
					poles = []
					continue
				poles.append(Vector3(p.x, 0, p.y))
			if poles.size() > 1:
				a.utility_line(poles, 7.0)


# ================================================================ 汎用の住宅ビルダー
func _house_builder() -> Callable:
	match era:
		"jomon_kofun":
			return func(xf: Transform3D, fw: float, dp: float) -> void: a.pit_dwelling(xf, minf(fw, dp) * 0.42)
		"asuka_nara", "heian":
			return func(xf: Transform3D, fw: float, dp: float) -> void:
				if rng.randf() < 0.5:
					a.minka(xf, fw, dp * 0.8, "board")
				else:
					a.minka(xf, fw, dp * 0.8, "thatch")
		"kamakura_muromachi":
			return func(xf: Transform3D, fw: float, dp: float) -> void: a.minka(xf, fw, dp * 0.85, "board" if rng.randf() < 0.6 else "thatch")
		"sengoku", "edo":
			return func(xf: Transform3D, fw: float, dp: float) -> void: a.machiya(xf, fw, dp, 2 if rng.randf() < 0.7 else 1)
		"meiji_taisho":
			return func(xf: Transform3D, fw: float, dp: float) -> void:
				if rng.randf() < 0.25:
					a.brick_building(xf, maxf(fw, 10.0), dp, 2, {"mansard": false})
				else:
					a.machiya(xf, fw, dp, 2)
		_:
			return func(xf: Transform3D, fw: float, dp: float) -> void: a.showa_shop(xf, fw, dp)


# ================================================================ 共通の建物群
func _raised_hall(xf: Transform3D, wd: float, dp: float, fh: float) -> void:
	a.begin_unit("hall", xf, {"kind_detail": "raised_hall"})
	_raised_hall_body(xf, wd, dp, fh)
	a.end_unit()


func _raised_hall_body(xf: Transform3D, wd: float, dp: float, fh: float) -> void:
	for i in 5:
		for j in 3:
			a.cyl("wood", xf, Vector3(-wd * 0.5 + wd * i / 4.0, -0.5, -dp * 0.5 + dp * j / 2.0), 0.3, 0.28, fh + 0.5, 8, Architecture.DARK)
	a.bx("wood", xf, Vector3(0, fh, 0), Vector3(wd + 1.4, 0.3, dp + 1.4), Architecture.DARK)
	# 中に入れる（正面の板戸・梯子）
	a.shell("darkwood", xf, Vector3(0, fh + 1.75, 0), Vector3(wd, 3.2, dp), Color(0.92, 0.84, 0.74), [{"side": 0, "u": wd * 0.125, "w": 1.4, "h": 2.3}], {"th": 0.15})
	a.door_frame(xf, wd * 0.125, fh + 0.15, dp * 0.5, 1.4, 2.3, "leaves", Architecture.DARK)
	var run: float = a.entry_steps(xf, wd * 0.125, dp * 0.5 + 0.7, fh + 0.15, 1.2, "wood", Architecture.DARK, true)
	a.col(xf, Vector3(0, fh, 0), Vector3(wd + 1.4, 0.3, dp + 1.4))
	for i in 5:
		a.cyl("wood", xf, Vector3(-wd * 0.5 + wd * i / 4.0, fh, dp * 0.5), 0.25, 0.25, 3.4, 6, Architecture.DARK)
	a.roof(xf, fh + 3.4, wd * 0.5 + 1.6, dp * 0.5 + 1.8, dp * 0.55, "gable", "thatch", Architecture.THATCH, 0.0, Color(0.5, 0.4, 0.3), 1.0)
	# 千木・鰹木
	for sgn in [-1.0, 1.0]:
		var top := xf * Vector3(sgn * (wd * 0.5 + 1.6), fh + 3.4 + dp * 0.55, 0)
		a.kit.rod("wood", top + xf.basis * Vector3(0, -0.6, -0.8), top + xf.basis * Vector3(0, 1.8, 0.9), 0.1, 4, Architecture.DARK)
		a.kit.rod("wood", top + xf.basis * Vector3(0, -0.6, 0.8), top + xf.basis * Vector3(0, 1.8, -0.9), 0.1, 4, Architecture.DARK)
	for k in 5:
		a.kit.cylinder("wood", xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-wd * 0.35 + k * wd * 0.175 + 0.6, fh + 3.4 + dp * 0.55 + 0.45, 0)), 0.22, 0.22, 1.2, 6, Architecture.DARK)
	a.col(xf, Vector3(0, fh + 4.0, 0), Vector3(wd, 1.0, dp))
	a.occupy(xf, wd + 2, dp + 2, 2.0)
	var dd := Architecture.door(Vector3(wd * 0.125, fh + 0.15, dp * 0.5), Vector3.BACK, 1.4, 2.3)
	dd["out"] = Vector3(wd * 0.125, 0, dp * 0.5 + 0.7 + run + 1.4)
	a.reg_interior("raised_hall", xf, [Architecture.fl(fh + 0.15, Rect2(-wd * 0.5 + 0.15, -dp * 0.5 + 0.15, wd - 0.3, dp - 0.3), 3.2)], [dd])


## 回廊（朱塗りの柱列と瓦屋根）
func _kairo(cs: Array, gates: Array) -> void:
	for i in 4:
		var p0: Vector3 = cs[i]
		var p1: Vector3 = cs[(i + 1) % 4]
		var segs: Array = [[p0, p1]]
		if i in gates:
			var mid := (p0 + p1) * 0.5
			var dir := (p1 - p0).normalized()
			segs = [[p0, mid - dir * 7.0], [mid + dir * 7.0, p1]]
		for s in segs:
			var A: Vector3 = s[0]
			var B: Vector3 = s[1]
			var d := B - A
			var L := Vector2(d.x, d.z).length()
			var ang := atan2(d.x, d.z)
			var mid := (A + B) * 0.5
			mid.y = minf(a.ground(A), a.ground(B))
			var xf := Transform3D(Basis(Vector3.UP, ang), mid)
			a.begin_unit("wall", xf, {"kind_detail": "kairo"})
			a.foundation(xf, 4.6, L + 4.6, 0.4)
			var n := int(L / 3.2)
			for k in n + 1:
				for sx in [-1.6, 1.6]:
					a.cyl("plaster", xf, Vector3(sx, 0.4, -L * 0.5 + L * k / maxf(n, 1)), 0.2, 0.18, 3.4, 6, Architecture.VERMILION)
			# 外側は壁
			a.bx("plaster", xf, Vector3(-1.6, 0.4 + 1.7, 0), Vector3(0.25, 3.4, L), Architecture.PLASTER)
			a.bx("plaster", xf, Vector3(0, 0.4 + 3.4, 0), Vector3(3.6, 0.25, L + 0.2), Architecture.VERMILION)
			a.roof(xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), 0.4 + 3.6, L * 0.5 + 1.2, 2.8, 1.3, "gable", "rooftile", Architecture.TILE_DARK, 0.0, Color(0.7, 0.4, 0.3))
			a.col(xf, Vector3(-1.6, 2.0, 0), Vector3(0.4, 4.0, L))
			a.end_unit()
			t.occupy_rect(Vector2(mid.x, mid.z), -ang + PI * 0.5, L * 0.5, 2.2)


func _kinkaku(xf: Transform3D) -> void:
	a.begin_unit("hall", xf, {"kind_detail": "kinkaku"})
	_kinkaku_body(xf)
	a.end_unit()


func _kinkaku_body(xf: Transform3D) -> void:
	a.foundation(xf, 13.5, 11.5, 0.6)
	var gold := Architecture.GOLD
	# 1 層: 白木と障子
	a.shell("plaster", xf, Vector3(0, 0.6 + 1.6, 0), Vector3(12, 3.2, 10), Color(0.95, 0.92, 0.85), [{"side": 0, "u": 1.5, "w": 2.0, "h": 2.5}], {"th": 0.15})
	a.door_frame(xf, 1.5, 0.6, 5.0, 2.0, 2.5, "slide", Color(0.6, 0.5, 0.4))
	var run: float = a.entry_steps(xf, 1.5, 5.75, 0.6, 2.4)
	for i in 5:
		a.cyl("wood", xf, Vector3(-6 + i * 3, 0.6, 5), 0.16, 0.16, 3.2, 6, Color(0.85, 0.75, 0.62))
	a.bx("wood", xf, Vector3(0, 0.6 + 3.3, 0), Vector3(13, 0.25, 11), Color(0.75, 0.65, 0.55))
	# 2 層・3 層: 金
	a.bx("gold", xf, Vector3(0, 0.6 + 3.4 + 1.5, 0), Vector3(12, 3.0, 10), gold)
	a.roof(xf, 0.6 + 3.4 + 3.0 + 0.1, 7.6, 6.6, 0.9, "hip", "thatch", Architecture.BARK, 0.4, gold)
	a.bx("gold", xf, Vector3(0, 0.6 + 7.2 + 1.3, 0), Vector3(7.5, 2.6, 7.5), gold)
	a.roof(xf, 0.6 + 7.2 + 2.6 + 0.1, 5.6, 5.6, 2.8, "pyramid", "thatch", Architecture.BARK, 0.7, gold, 1.5)
	a.kit.box("gold", xf * Transform3D(Basis(), Vector3(0, 0.6 + 7.2 + 2.6 + 3.3, 0)), Vector3(0.6, 1.2, 0.3), gold)
	a.col(xf, Vector3(0, 0.6 + 3.3 + 3.2, 0), Vector3(12, 6.4, 10))
	a.occupy(xf, 14, 12, 0.0)
	var dd := Architecture.door(Vector3(1.5, 0.6, 5.0), Vector3.BACK, 2.0, 2.5)
	dd["out"] = Vector3(1.5, 0, 5.75 + run + 1.4)
	a.reg_interior("kinkaku", xf, [Architecture.fl(0.6, Rect2(-5.85, -4.85, 11.7, 9.7), 3.2)], [dd])


func _kairo_black(c: Array) -> void:
	for i in 4:
		var A: Vector3 = c[i]
		var B: Vector3 = c[(i + 1) % 4]
		if i == 2:
			var mid := (A + B) * 0.5
			var dir := (B - A).normalized()
			a.tsuiji(A, mid - dir * 5.0, 3.0, Color(0.2, 0.19, 0.18))
			a.tsuiji(mid + dir * 5.0, B, 3.0, Color(0.2, 0.19, 0.18))
		else:
			a.tsuiji(A, B, 3.0, Color(0.2, 0.19, 0.18))


func _dir2(lm: Dictionary, local: Vector2) -> Vector2:
	var v: Vector3 = lm["xf"].basis * Vector3(local.x, 0, local.y)
	return Vector2(v.x, v.z).normalized()


# ================================================================ 村 village


# ================================================================ 村 village
func _village_common(lm: Dictionary, builder: Callable, count := 16, inner := 18.0, outer := 52.0, fields := true) -> void:
	var placed: Array = []
	var tries := 0
	while placed.size() < count and tries < count * 20:
		tries += 1
		var ang := rng.randf() * TAU
		var rr := rng.randf_range(inner, outer)
		var p := Vector2(cos(ang), sin(ang)) * rr
		var ok := true
		for q in placed:
			if p.distance_to(q) < 12.5:
				ok = false
		if not ok:
			continue
		placed.append(p)
		var rot := atan2(-p.x, -p.y) + rng.randf_range(-0.3, 0.3)
		builder.call(pl(lm, p.x, p.y, rot, Vector2(10, 8)), rng.randf_range(8.0, 11.0), rng.randf_range(6.0, 8.0))
	# 小道
	for k in 6:
		var ang := TAU * k / 6.0 + 0.3
		street(lm, cos(ang) * 10, sin(ang) * 10, cos(ang) * float(lm["r"]) * 0.88, sin(ang) * float(lm["r"]) * 0.88, 2.0)
	if fields:
		for k in 14:
			var ang := rng.randf() * TAU
			var rr := rng.randf_range(outer + 6, float(lm["r"]) * 0.82)
			field(lm, cos(ang) * rr, sin(ang) * rr, rng.randf_range(6, 10), rng.randf_range(4, 7))


func _palace_complex(lm: Dictionary, z_hall: float, green := false) -> void:
	# 大極殿＋回廊＋朝堂＋門（コンパクト版）
	var tile := Architecture.TILE if not green else Color(0.5, 0.7, 0.62)
	a.jp_hall(pl(lm, 0, z_hall, 0, Vector2(26, 14)), 24.0, 12.0, {"base_h": 1.8, "wall_h": 5.4, "roof": "irimoya", "over": 2.8, "lift": 1.0, "rise": 0.42, "roof_col": tile})
	var c := corners(lm, 0, z_hall + 14, 36, 22)
	_kairo(c, [2])
	a.gate(pl(lm, 0, z_hall + 36, 0, Vector2(12, 6)), 10.0, "romon")
	for sgn in [-1.0, 1.0]:
		a.jp_hall(pl(lm, sgn * 22, z_hall + 20, -sgn * PI * 0.5, Vector2(18, 8)), 16.0, 7.0, {"base_h": 0.7, "wall_h": 3.6, "roof": "irimoya", "over": 1.8, "lift": 0.5, "roof_col": tile})
	plaza(lm, 0, z_hall + 14, 34, 20, 0.95)
	for sgn in [-1.0, 1.0]:
		a.stone_lantern(wp(lm, sgn * 5, z_hall + 28))


# ================================================================ 都 capital（半径 70m）
func _capital_jomon_kofun(lm: Dictionary) -> void:
	# 纒向: 柵で囲った宮域に大型掘立柱建物が東西一列
	a.wall_loop(corners(lm, 0, -24, 42, 26), 7.0, 2.8, Color.WHITE, "palisade", [2])
	plaza(lm, 0, -24, 40, 24, 0.7)
	_raised_hall(pl(lm, 0, -36, 0, Vector2(18, 12)), 17.0, 10.0, 2.4)
	_raised_hall(pl(lm, -26, -32, 0, Vector2(10, 8)), 9.0, 7.0, 2.0)
	_raised_hall(pl(lm, 26, -32, 0, Vector2(10, 8)), 9.0, 7.0, 2.0)
	a.raised_storehouse(pl(lm, -32, -10, 0.3), 4.2, 3.4)
	a.raised_storehouse(pl(lm, 32, -10, -0.2), 4.2, 3.4)
	for cx in [-38.0, 38.0]:
		a.watchtower(pl(lm, cx, -46, 0, Vector2(4, 4)), 9.0)
	street(lm, 0, -2, 0, 66, 3.5)
	a.model("stone_fire_pit", pl(lm, 0, -18, 0, Vector2(2, 2)))
	var placed: Array = []
	for k in 40:
		if placed.size() >= 16:
			break
		var x := rng.randf_range(-58, 58)
		var z := rng.randf_range(10, 58)
		if absf(x) < 8.0 or Vector2(x, z).length() > 62.0:
			continue
		var ok := true
		for q in placed:
			if Vector2(x, z).distance_to(q) < 11.0:
				ok = false
		if not ok:
			continue
		placed.append(Vector2(x, z))
		a.pit_dwelling(pl(lm, x, z, rng.randf() * TAU, Vector2(8, 8)), rng.randf_range(3.0, 3.8))
	for k in 6:
		tree(lm, "broadleaf", rng.randf_range(-60, 60), rng.randf_range(-62, -52), 0.9)


func _capital_asuka_nara(lm: Dictionary) -> void:
	_palace_complex(lm, -50)
	street(lm, 0, -14, 0, 66, 5.5)
	var b := _house_builder()
	for sgn in [-1.0, 1.0]:
		var c := corners(lm, sgn * 32, 34, 20, 20)
		for side in 4:
			if side == 3 and sgn > 0 or side == 1 and sgn < 0:
				var p0: Vector3 = c[side]
				var p1: Vector3 = c[(side + 1) % 4]
				var mid := (p0 + p1) * 0.5
				var dir := (p1 - p0).normalized()
				a.tsuiji(p0, mid - dir * 3.0, 2.6, Architecture.OCHRE)
				a.tsuiji(mid + dir * 3.0, p1, 2.6, Architecture.OCHRE)
			else:
				a.tsuiji(c[side], c[(side + 1) % 4], 2.6, Architecture.OCHRE)
		a.jp_hall(pl(lm, sgn * 32, 30, 0, Vector2(14, 9)), 13.0, 8.0, {"base_h": 0.6, "wall_h": 3.2, "roof": "irimoya", "over": 1.6, "lift": 0.4})
		a.minka(pl(lm, sgn * 24, 46, 0), 7.0, 5.0, "rooftile")
		a.minka(pl(lm, sgn * 40, 46, 0), 7.0, 5.0, "rooftile")
		street(lm, sgn * 58, -40, sgn * 58, 40, 3.0)
		lots(lm, sgn * 61, -36, sgn * 61, 36, sgn, 0.0, 7.0, 6.5, 8.5, b)
	for k in 7:
		tree(lm, "broadleaf", -7.5 if k % 2 == 0 else 7.5, -6 + k * 10.0, 0.6)


func _capital_heian(lm: Dictionary) -> void:
	_palace_complex(lm, -52, true)
	street(lm, 0, -16, 0, 66, 6.0)
	for k in 8:
		tree(lm, "broadleaf" if k % 3 else "sakura", -8.5 if k % 2 == 0 else 8.5, -8 + k * 9.0, 0.6)
	for sgn in [-1.0, 1.0]:
		a.shinden(lm["xf"], sgn * 34, 34, 34.0)
		street(lm, sgn * 58, -44, sgn * 58, 56, 3.0)
	var b := _house_builder()
	for sgn in [-1.0, 1.0]:
		lots(lm, sgn * 61, -40, sgn * 61, 50, sgn, 0.0, 7.0, 6.5, 8.5, b)


func _capital_kamakura_muromachi(lm: Dictionary) -> void:
	# 幕府御所（板塀の中に主殿・会所）
	a.wall_loop(corners(lm, 0, -38, 36, 24), 7.0, 2.2, Architecture.PLASTER, "fence", [2])
	a.gate(pl(lm, 0, -14, 0, Vector2(7, 4)), 5.5, "yakui", Color(0.8, 0.7, 0.6))
	var o := {"base_h": 0.5, "wall_h": 3.4, "pillar": Color(0.82, 0.72, 0.6), "pillar_mat": "wood", "roof": "irimoya", "roof_mat": "thatch", "roof_col": Architecture.BARK, "over": 1.8, "lift": 0.0, "door_mat": "wood", "door_col": Color(0.95, 0.92, 0.85), "raised": true}
	a.jp_hall(pl(lm, -4, -48, 0, Vector2(20, 11)), 18.0, 9.0, o)
	a.jp_hall(pl(lm, 22, -40, -PI * 0.5, Vector2(12, 8)), 10.0, 7.0, o)
	a.jp_hall(pl(lm, -24, -32, PI * 0.5, Vector2(10, 8)), 9.0, 6.0, o)
	plaza(lm, 0, -38, 34, 22, 0.8)
	street(lm, 0, -12, 0, 66, 5.0)
	for z in [20.0, 48.0]:
		a.torii(pl(lm, 0, z, 0), 8.0, 7.0)
	for sgn in [-1.0, 1.0]:
		a.buke_yashiki(lm["xf"], sgn * 30, 34, -sgn * PI * 0.5, 26.0, "thatch")
		street(lm, sgn * 56, -44, sgn * 56, 56, 2.8)
	var b := _house_builder()
	for sgn in [-1.0, 1.0]:
		lots(lm, sgn * 59, -40, sgn * 59, 50, sgn, 0.0, 7.0, 6.5, 9.0, b)


func _capital_sengoku(lm: Dictionary) -> void:
	# 聚楽第: 金の装飾の城郭風御殿＋城下の町割り
	a.castle(pl(lm, 0, -42, 0, Vector2(32, 32)), 30.0, 7.0, 3, Architecture.PLASTER, true)
	for sgn in [-1.0, 1.0]:
		a.jp_hall(pl(lm, sgn * 32, -40, -sgn * PI * 0.5, Vector2(16, 10)), 14.0, 9.0, {"base_h": 0.8, "wall_h": 3.8, "pillar": Color(0.2, 0.18, 0.16), "pillar_mat": "darkwood", "roof": "irimoya", "over": 1.8, "lift": 0.5, "roof_col": Architecture.TILE_DARK})
	var b := _house_builder()
	grid_town(lm, 0, 30, 60, 24, 24.0, 2.8, 8.5, 5.5, 7.5, b, Rect2(-12, 6, 24, 48))
	street(lm, 0, -18, 0, 66, 4.5)
	for k in 4:
		a.nobori(wp(lm, -6 + k * 4, -18), [Color(0.95, 0.85, 0.2), Color(0.85, 0.15, 0.1)][k % 2])


func _capital_edo(lm: Dictionary) -> void:
	# 江戸城（堀の内）＋本丸御殿＋城下
	a.castle(pl(lm, 0, -30, 0, Vector2(36, 36)), 36.0, 9.0, 5, Architecture.PLASTER, false)
	for sgn in [-1.0, 1.0]:
		a.jp_hall(pl(lm, sgn * 30, 24, 0, Vector2(18, 11)), 16.0, 10.0, {"base_h": 0.8, "wall_h": 3.8, "pillar": Color(0.85, 0.75, 0.62), "pillar_mat": "wood", "roof": "irimoya", "over": 2.0, "lift": 0.4, "roof_col": Architecture.TILE_DARK, "door_col": Color(0.95, 0.92, 0.85)})
	a.gate(pl(lm, 0, 18, 0, Vector2(12, 5)), 9.0, "nagaya", Color(0.25, 0.22, 0.2))
	var bp := wp(lm, 0, 1)
	a.bridge(Vector2(bp.x, bp.z), _dir2(lm, Vector2(0, 1)), 14.0, 5.0, float(lm["h"]) + 0.6, "wood", 0.7)
	street(lm, 0, 22, 0, 66, 4.0)
	var b := _house_builder()
	for sgn in [-1.0, 1.0]:
		lots(lm, sgn * 4.5, 36, sgn * 4.5, 64, sgn, 0.0, 8.5, 5.5, 7.5, b)
		street(lm, sgn * 58, -50, sgn * 58, 50, 2.8)
		lots(lm, sgn * 61, -46, sgn * 61, 46, sgn, 0.0, 8.0, 5.5, 7.5, b)
	for k in 5:
		tree(lm, "pine", rng.randf_range(-44, 44), rng.randf_range(10, 14), 0.75)


func _capital_meiji_taisho(lm: Dictionary) -> void:
	# 太政官（煉瓦＋時計塔）と宮城前広場・二重橋
	a.brick_building(pl(lm, 0, 34, PI, Vector2(34, 16)), 32.0, 14.0, 3, {"clock": true})
	plaza(lm, 0, -6, 52, 30, 0.95)
	var bp := wp(lm, 0, -46)
	a.bridge(Vector2(bp.x, bp.z), _dir2(lm, Vector2(0, 1)), 20.0, 7.0, float(lm["h"]) + 0.8, "stone", 1.4)
	a.castle(pl(lm, 0, -64, 0, Vector2(20, 20)), 20.0, 4.0, 1, Architecture.PLASTER, false)
	for k in 8:
		a.lamp(wp(lm, -35 + k * 10, 12), "gas")
		a.lamp(wp(lm, -35 + k * 10, -24), "gas")
	for sgn in [-1.0, 1.0]:
		a.brick_building(pl(lm, sgn * 54, 4, -sgn * PI * 0.5, Vector2(22, 14)), 22.0, 12.0, 2, {"mat": "plaster", "col": Color(0.95, 0.93, 0.88), "trim": Color(0.8, 0.78, 0.72)})
		a.brick_building(pl(lm, sgn * 50, 48, -sgn * PI * 0.5, Vector2(20, 12)), 18.0, 11.0, 2, {})
		street(lm, sgn * 38, -30, sgn * 38, 62, 3.5)
	street(lm, -66, 20, 66, 20, 4.0)
	for sgn in [-1.0, 1.0]:
		for k in 4:
			tree(lm, "pine", sgn * rng.randf_range(12, 44), rng.randf_range(-36, -30), 0.75)
	extra_car_spawns.append(w._xf_at(Vector2(wp(lm, 6, 0).x, wp(lm, 6, 0).z), _dir2(lm, Vector2(1, 0))))
	extra_car_spawns.append(w._xf_at(Vector2(wp(lm, -20, 20).x, wp(lm, -20, 20).z), _dir2(lm, Vector2(1, 0))))


func _capital_showa(lm: Dictionary) -> void:
	a.diet_building(pl(lm, 0, -48, 0, Vector2(82, 34)), 80.0)
	plaza(lm, 0, -12, 44, 18, 0.95)
	street(lm, 0, -24, 0, 66, 6.0)
	street(lm, -66, 4, 66, 4, 5.0)
	for k in 6:
		tree(lm, "broadleaf", -12 + 24 * (k % 2), -22 + (k / 2) * 8.0, 0.65)
	var spots := [[-36, 26, 0.0], [36, 26, 0.0], [-36, 52, 0.0], [36, 52, 0.0], [-58, -8, PI * 0.5], [58, -8, -PI * 0.5]]
	for sp in spots:
		a.concrete_building(pl(lm, sp[0], sp[1], sp[2], Vector2(18, 14)), rng.randf_range(14, 18), rng.randf_range(10, 13), rng.randi_range(4, 7))
	street(lm, -20, 4, -20, 66, 4.0)
	street(lm, 20, 4, 20, 66, 4.0)
	for k in 5:
		a.lamp(wp(lm, -7.5, 10 + k * 11), "electric")
		a.lamp(wp(lm, 7.5, 10 + k * 11), "electric")
	extra_car_spawns.append(w._xf_at(Vector2(wp(lm, 3.5, 20).x, wp(lm, 3.5, 20).z), _dir2(lm, Vector2(0, 1))))
	extra_car_spawns.append(w._xf_at(Vector2(wp(lm, 30, 6).x, wp(lm, 30, 6).z), _dir2(lm, Vector2(1, 0))))
	extra_car_spawns.append(w._xf_at(Vector2(wp(lm, -20, 40).x, wp(lm, -20, 40).z), _dir2(lm, Vector2(0, 1))))


# ================================================================ 村 village（半径 50m）
func _village_jomon_kofun(lm: Dictionary) -> void:
	# 三内丸山: 竪穴住居の環状集落＋大型掘立柱建物
	for k in 12:
		var ang := TAU * k / 12.0
		var rr := 27.0 + rng.randf_range(-3, 4)
		a.pit_dwelling(pl(lm, cos(ang) * rr, sin(ang) * rr, ang, Vector2(8, 8)), rng.randf_range(3.0, 3.8))
	var xf := pl(lm, -10, -6, 0, Vector2(12, 8))
	for i in 3:
		for j in 2:
			a.cyl("wood", xf, Vector3(-4.2 + i * 4.2, -0.5, -2.1 + j * 4.2), 0.5, 0.45, 15.5, 10, Architecture.DARK)
			a.col(xf, Vector3(-4.2 + i * 4.2, 7.5, -2.1 + j * 4.2), Vector3(1.0, 15, 1.0))
	for yy in [5.0, 10.0, 15.0]:
		a.bx("wood", xf, Vector3(0, yy, 0), Vector3(10.2, 0.4, 5.6), Architecture.DARK)
	a.occupy(xf, 11, 6, 2.0)
	var lh := pl(lm, 12, -10, 0.4, Vector2(18, 8))
	a.roof(lh, 0.0, 9.5, 4.0, 4.4, "hip", "thatch", Architecture.THATCH, 0.0, Color(0.5, 0.4, 0.3), 1.0)
	a.col(lh, Vector3(0, 2.0, 0), Vector3(16, 4, 7))
	a.occupy(lh, 19, 9, 2.0)
	for k in 4:
		var ang := TAU * k / 4.0 + 0.4
		a.raised_storehouse(pl(lm, cos(ang) * 41, sin(ang) * 41, ang, Vector2(5, 4)), 4.0, 3.2)
	for k in 5:
		var ang := TAU * k / 5.0 + 0.5
		street(lm, cos(ang) * 10, sin(ang) * 10, cos(ang) * 46, sin(ang) * 46, 1.6)
	plaza(lm, 0, 0, 18, 18, 0.8)
	a.model("stone_fire_pit", pl(lm, 5, 5, 0, Vector2(2, 2)))


func _village_asuka_nara(lm: Dictionary) -> void:
	var b := func(xf: Transform3D, fw: float, dp: float) -> void:
		if rng.randf() < 0.3:
			a.raised_storehouse(xf, 4.2, 3.4)
		else:
			a.farmhouse(xf, fw, dp)
	_village_common(lm, b, 10, 14.0, 30.0)


func _village_heian(lm: Dictionary) -> void:
	var b := func(xf: Transform3D, fw: float, dp: float) -> void:
		if rng.randf() < 0.35:
			a.minka(xf, fw * 0.9, dp, "board")
		else:
			a.farmhouse(xf, fw, dp)
	_village_common(lm, b, 10, 14.0, 30.0)
	a.torii(pl(lm, 0, -36, 0), 4.6, 4.4)
	a.jp_hall(pl(lm, 0, -43, 0, Vector2(7, 6)), 6.0, 4.5, {"base_h": 0.6, "wall_h": 2.6, "roof": "gable", "roof_mat": "thatch", "roof_col": Architecture.BARK, "over": 1.1, "lift": 0.0})


func _village_kamakura_muromachi(lm: Dictionary) -> void:
	var b := func(xf: Transform3D, fw: float, dp: float) -> void:
		if rng.randf() < 0.3:
			a.minka(xf, fw * 0.9, dp, "board")
		else:
			a.farmhouse(xf, fw, dp)
	_village_common(lm, b, 10, 16.0, 31.0)
	for k in 5:
		var ang := TAU * k / 5.0
		a.stall(pl(lm, cos(ang) * 9, sin(ang) * 9, ang + PI * 0.5, Vector2(3, 2)), [Color(0.6, 0.3, 0.2), Color(0.3, 0.35, 0.5), Color(0.8, 0.75, 0.6)][k % 3])
	a.torii(pl(lm, 0, -40, 0), 4.6, 4.4)


func _village_sengoku(lm: Dictionary) -> void:
	# 安土城下町: 格子の町割りと楽市
	var b := _house_builder()
	grid_town(lm, 0, 0, 40, 40, 26.0, 2.6, 8.0, 5.5, 7.5, b, Rect2(-13, -13, 26, 26))
	for k in 6:
		var ang := TAU * k / 6.0
		a.stall(pl(lm, cos(ang) * 8, sin(ang) * 8, ang + PI * 0.5, Vector2(3, 2)), [Color(0.8, 0.3, 0.2), Color(0.25, 0.3, 0.5), Color(0.85, 0.8, 0.6)][k % 3])
	for k in 4:
		a.nobori(wp(lm, rng.randf_range(-10, 10), rng.randf_range(-10, 10)), [Color(0.85, 0.15, 0.1), Color(0.95, 0.95, 0.9)][k % 2])


func _village_edo(lm: Dictionary) -> void:
	# 日本橋の町人地: 密な町家と蔵、火の見櫓
	var b := func(xf: Transform3D, fw: float, dp: float) -> void:
		if rng.randf() < 0.15:
			a.kura(xf, fw, dp * 0.8, 5.0)
		else:
			a.machiya(xf, fw, dp, 2 if rng.randf() < 0.75 else 1)
	grid_town(lm, 0, 0, 42, 42, 28.0, 2.6, 9.0, 5.0, 7.0, b, Rect2(-14, -14, 28, 28))
	a.watchtower(pl(lm, 6, -6, 0, Vector2(4, 4)), 11.0, 2.6, "rooftile")
	for k in 4:
		var ang := TAU * k / 4.0 + 0.6
		a.stall(pl(lm, cos(ang) * 8, sin(ang) * 8, ang + PI * 0.5, Vector2(3, 2)), [Color(0.2, 0.25, 0.45), Color(0.75, 0.25, 0.15)][k % 2])
	for k in 8:
		a.lamp(wp(lm, -10.5 + (k % 4) * 7, -11 if k < 4 else 11), "lantern")


func _village_meiji_taisho(lm: Dictionary) -> void:
	var b := func(xf: Transform3D, fw: float, dp: float) -> void: a.farmhouse(xf, fw, dp)
	_village_common(lm, b, 6, 18.0, 30.0)
	a.wooden_school(pl(lm, 0, -30, 0, Vector2(28, 12)), 26.0, 9.0)
	plaza(lm, 0, -12, 16, 8, 0.85)


func _village_showa(lm: Dictionary) -> void:
	# 下町の商店街・団地・住宅
	street(lm, -46, 0, 46, 0, 3.6)
	var b := func(xf: Transform3D, fw: float, dp: float) -> void: a.showa_shop(xf, fw, dp)
	lots(lm, -44, 0, 44, 0, 1.0, 4.0, 8.5, 5.0, 7.0, b)
	lots(lm, 44, 0, -44, 0, 1.0, 4.0, 8.5, 5.0, 7.0, b)
	a.utility_line([wp(lm, -44, 5.5), wp(lm, -22, 5.5), wp(lm, 0, 5.5), wp(lm, 22, 5.5), wp(lm, 44, 5.5)])
	a.apartment(pl(lm, -14, -32, 0, Vector2(36, 12)), 34.0, 9.0, 4)
	a.apartment(pl(lm, 24, -34, 0, Vector2(20, 12)), 18.0, 9.0, 4)
	for k in 5:
		a.minka(pl(lm, -32 + k * 16, 30, PI, Vector2(9, 7)), 8.0, 6.0, "rooftile")
	street(lm, -46, 22, 46, 22, 2.6)
	for k in 4:
		field(lm, -30 + k * 20, 42, 7, 3)
	extra_car_spawns.append(w._xf_at(Vector2(wp(lm, 12, 1.5).x, wp(lm, 12, 1.5).z), _dir2(lm, Vector2(1, 0))))


# ================================================================ 寺社 temple（半径 40m）
func _temple_jomon_kofun(lm: Dictionary) -> void:
	# 三輪山の祭祀場: 磐座としめ縄、三ツ鳥居
	var xf := pl(lm, 0, -14, 0, Vector2(12, 4))
	a.torii(xf, 5.0, 5.0, Color(0.85, 0.78, 0.66), "wood")
	a.torii(xf * Transform3D(Basis(), Vector3(-6.2, 0, 0)), 3.2, 3.6, Color(0.85, 0.78, 0.66), "wood")
	a.torii(xf * Transform3D(Basis(), Vector3(6.2, 0, 0)), 3.2, 3.6, Color(0.85, 0.78, 0.66), "wood")
	for k in 5:
		var p := wp(lm, -12 + k * 6, -26 + rng.randf_range(-2, 2))
		var s := rng.randf_range(1.4, 2.2)
		if not a.model("boulder_01", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s * 1.2), p - Vector3(0, 0.3, 0))):
			a.kit.sphere("rock", Transform3D(Basis().scaled(Vector3(s, s * 0.7, s * 0.85)), p + Vector3(0, s * 0.3, 0)), 1.0, 10, 6, Color(0.7, 0.7, 0.68))
		a.cols.append([Transform3D(Basis(), p + Vector3(0, s * 0.4, 0)), Vector3(s * 1.4, s * 1.2, s * 1.4)])
	var r1 := wp(lm, -14, -26) + Vector3(0, 2.0, 0)
	var r2 := wp(lm, 12, -26) + Vector3(0, 2.0, 0)
	a.kit.rod("cloth", r1, r2, 0.12, 6, Color(0.95, 0.92, 0.8))
	for k in 9:
		var p := r1.lerp(r2, (k + 0.5) / 9.0)
		a.kit.box("cloth", Transform3D(Basis(), p + Vector3(0, -0.45, 0)), Vector3(0.18, 0.7, 0.02), Color(1, 1, 1))
	for k in 10:
		tree(lm, "cedar", rng.randf_range(-34, 34), rng.randf_range(-38, -31), rng.randf_range(0.9, 1.2))
	street(lm, 0, -12, 0, 38, 2.2)
	for k in 4:
		a.stone_lantern(wp(lm, -3.5 if k % 2 == 0 else 3.5, 4 + (k / 2) * 12))


func _temple_asuka_nara(lm: Dictionary) -> void:
	# 法隆寺: 回廊内に五重塔と金堂、中門
	_kairo(corners(lm, 0, -10, 28, 20), [2])
	a.pagoda(pl(lm, -11, -12, 0, Vector2(9, 9)), 5, 6.4, 2.9)
	a.jp_hall(pl(lm, 11, -12, 0, Vector2(13, 11)), 12.0, 9.5, {"base_h": 1.3, "wall_h": 4.2, "roof": "irimoya", "over": 2.3, "lift": 0.8, "two_tier": true})
	a.gate(pl(lm, 0, 10, 0, Vector2(10, 5)), 8.5, "romon")
	plaza(lm, 0, -10, 26, 18, 0.95)
	street(lm, 0, 12, 0, 38, 3.0)
	for k in 4:
		a.stone_lantern(wp(lm, -4 if k % 2 == 0 else 4, 17 + (k / 2) * 9))
	for k in 6:
		tree(lm, "pine", (1.0 if k % 2 else -1.0) * rng.randf_range(12, 34), rng.randf_range(16, 34), 0.75)


func _temple_heian(lm: Dictionary) -> void:
	# 東寺: 高い五重塔・金堂・講堂
	a.wall_loop(corners(lm, 0, -6, 36, 30), 7.0, 2.8, Architecture.OCHRE, "tsuiji", [2])
	a.pagoda(pl(lm, 20, 8, 0, Vector2(10, 10)), 5, 7.4, 3.4)
	a.jp_hall(pl(lm, -6, -6, 0, Vector2(20, 12)), 18.0, 11.0, {"base_h": 1.3, "wall_h": 4.6, "roof": "irimoya", "over": 2.5, "lift": 0.9, "two_tier": true})
	a.jp_hall(pl(lm, 0, -27, 0, Vector2(20, 10)), 18.0, 9.0, {"base_h": 1.0, "wall_h": 4.0, "roof": "irimoya", "over": 2.2, "lift": 0.7})
	a.gate(pl(lm, 0, 24, 0, Vector2(10, 5)), 8.5, "romon")
	plaza(lm, 0, -6, 34, 28, 0.95)
	for k in 4:
		a.stone_lantern(wp(lm, -4 if k % 2 == 0 else 4, 12 + (k / 2) * 5))
	for k in 4:
		tree(lm, "sakura", rng.randf_range(-30, -16), rng.randf_range(6, 18), 0.7)


func _temple_kamakura_muromachi(lm: Dictionary) -> void:
	# 北山殿（金閣）と鏡湖池
	w.pond_requests.append({"center": wp(lm, 0, 8), "rx": 24.0, "rz": 13.0, "angle": float(lm["angle"])})
	_kinkaku(pl(lm, 0, -12, 0, Vector2(12, 10)))
	a.jp_hall(pl(lm, -24, -26, 0, Vector2(12, 8)), 11.0, 7.0, {"base_h": 0.6, "wall_h": 3.2, "pillar": Color(0.8, 0.7, 0.58), "pillar_mat": "wood", "roof": "irimoya", "roof_mat": "thatch", "roof_col": Architecture.BARK, "over": 1.6, "lift": 0.3, "door_mat": "wood", "door_col": Color(0.95, 0.92, 0.85)})
	for k in 10:
		var ang := rng.randf() * TAU
		tree(lm, "pine", cos(ang) * rng.randf_range(28, 36), 8 + sin(ang) * rng.randf_range(17, 24), rng.randf_range(0.55, 0.85))
	a.gate(pl(lm, 0, 32, 0, Vector2(7, 4)), 5.5, "yakui", Color(0.75, 0.65, 0.55))
	for k in 6:
		var ang := rng.randf() * TAU
		var p := wp(lm, cos(ang) * 27, 8 + sin(ang) * 15)
		a.model("rock_moss_set_02", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p - Vector3(0, 0.2, 0)))


func _temple_sengoku(lm: Dictionary) -> void:
	# 京の南蛮寺: 和風三層の建物に十字架
	var xf := pl(lm, 0, -16, 0, Vector2(15, 11))
	a.jp_hall(xf, 13.0, 9.0, {"base_h": 0.8, "wall_h": 3.8, "pillar": Color(0.3, 0.25, 0.22), "pillar_mat": "darkwood", "roof": "hip", "over": 1.7, "lift": 0.3, "roof_col": Architecture.TILE_DARK})
	var x2 := xf * Transform3D(Basis(), Vector3(0, 5.2 + 3.2, 0))
	a.bx("plaster", x2, Vector3(0, 1.5, 0), Vector3(8.4, 3.0, 6.4), Architecture.PLASTER)
	a.roof(x2, 3.1, 5.4, 4.4, 1.1, "hip", "rooftile", Architecture.TILE_DARK, 0.3)
	a.bx("plaster", x2, Vector3(0, 4.3 + 1.1, 0), Vector3(4.6, 2.2, 4.2), Architecture.PLASTER)
	a.roof(x2, 4.3 + 2.2, 3.3, 3.2, 2.0, "irimoya", "rooftile", Architecture.TILE_DARK, 0.3)
	var top := x2 * Vector3(0, 4.3 + 2.2 + 2.4, 0)
	a.kit.box("gold", Transform3D(xf.basis, top + Vector3(0, 1.2, 0)), Vector3(0.18, 2.4, 0.18), Architecture.GOLD)
	a.kit.box("gold", Transform3D(xf.basis, top + Vector3(0, 1.7, 0)), Vector3(1.2, 0.18, 0.18), Architecture.GOLD)
	a.wall_loop(corners(lm, 0, -6, 30, 24), 6.0, 2.4, Architecture.PLASTER, "tsuiji", [2])
	a.gate(pl(lm, 0, 18, 0, Vector2(6, 3)), 5.0, "yakui", Color(0.3, 0.25, 0.22))
	plaza(lm, 0, -6, 28, 22, 0.85)
	a.minka(pl(lm, 18, 4, -PI * 0.5), 9, 6, "rooftile")
	a.minka(pl(lm, -18, 4, PI * 0.5), 9, 6, "rooftile")


func _temple_edo(lm: Dictionary) -> void:
	# 湯島聖堂: 黒塗りの大成殿
	var black := Color(0.18, 0.17, 0.17)
	a.jp_hall(pl(lm, 0, -16, 0, Vector2(18, 12)), 16.0, 11.0, {"base_h": 1.5, "wall_h": 4.6, "pillar": black, "pillar_mat": "darkwood", "wall": Color(0.25, 0.23, 0.22), "roof": "irimoya", "over": 2.2, "lift": 0.4, "roof_col": Architecture.TILE_DARK, "door_col": Color(0.3, 0.27, 0.25)})
	_kairo_black(corners(lm, 0, -10, 26, 22))
	a.gate(pl(lm, 0, 12, 0, Vector2(7, 4)), 6.0, "yakui", black)
	a.gate(pl(lm, 0, 32, 0, Vector2(7, 4)), 6.0, "yakui", black)
	street(lm, 0, 14, 0, 38, 2.6)
	plaza(lm, 0, -10, 24, 20, 0.9)
	for k in 6:
		tree(lm, "broadleaf", (-1 if k % 2 else 1) * rng.randf_range(12, 32), rng.randf_range(16, 34), 0.75)


func _temple_meiji_taisho(lm: Dictionary) -> void:
	# 浅草寺: 本堂・五重塔・雷門・仲見世
	a.jp_hall(pl(lm, 0, -22, 0, Vector2(22, 16)), 20.0, 14.0, {"base_h": 1.6, "wall_h": 5.4, "roof": "irimoya", "over": 3.0, "lift": 1.0, "rise": 0.5, "roof_col": Architecture.TILE_DARK})
	a.pagoda(pl(lm, 22, -4, 0, Vector2(8, 8)), 5, 5.8, 2.7)
	var g := pl(lm, 0, 31, 0, Vector2(11, 5))
	a.gate(g, 9.0, "nagaya", Architecture.VERMILION)
	a.kit.cylinder("cloth", g * Transform3D(Basis(), Vector3(0, 1.4, 0)), 1.3, 1.3, 3.0, 14, Color(0.75, 0.12, 0.1))
	street(lm, 0, -8, 0, 38, 3.4)
	plaza(lm, 0, -18, 30, 12, 0.9)
	var b := func(xf: Transform3D, fw: float, dp: float) -> void: a.machiya(xf, fw, dp, 1, {"wall": Color(0.95, 0.85, 0.75)})
	for sgn in [-1.0, 1.0]:
		lots(lm, sgn * 4.2, -4, sgn * 4.2, 26, sgn, 0.0, 5.5, 4.0, 5.0, b)
	for k in 6:
		a.lamp(wp(lm, -3.6 if k % 2 == 0 else 3.6, -4 + (k / 2) * 10), "lantern")


func _temple_showa(lm: Dictionary) -> void:
	# 明治神宮: 大鳥居と銅板葺の社殿、深い杜
	var cedar_col := Color(0.82, 0.74, 0.62)
	a.torii(pl(lm, 0, 30, 0), 10.0, 9.0, cedar_col, "wood")
	a.torii(pl(lm, 0, 8, 0), 7.0, 6.5, cedar_col, "wood")
	var o := {"base_h": 1.1, "wall_h": 4.2, "pillar": cedar_col, "pillar_mat": "wood", "roof": "gable", "roof_col": Architecture.COPPER, "over": 2.6, "lift": 0.3, "rise": 0.38, "door_mat": "wood", "door_col": Color(0.95, 0.9, 0.82)}
	a.jp_hall(pl(lm, 0, -22, 0, Vector2(18, 12)), 16.0, 11.0, o)
	a.jp_hall(pl(lm, 0, -4, 0, Vector2(11, 7)), 10.0, 6.0, o)
	_kairo(corners(lm, 0, -14, 22, 18), [2])
	plaza(lm, 0, -14, 20, 16, 0.95)
	street(lm, 0, 6, 0, 38, 3.4)
	for k in 28:
		var x := rng.randf_range(-38, 38)
		var z := rng.randf_range(-38, 38)
		if absf(x) < 26 and z > -34 and z < 6:
			continue
		if absf(x) < 6:
			continue
		tree(lm, ["broadleaf", "cedar", "broadleaf"][k % 3], x, z, rng.randf_range(0.8, 1.1))


# ================================================================ 港 port（半径 40m）
func _port_layout(lm: Dictionary, pier_kind: String, boats: Array, wh_kind: String, n_wh: int, extra: Callable) -> void:
	# 岸線は +Z（海側）。岸の位置を探す
	var shore_z := 0.0
	for zz in range(0, 90, 1):
		var p := wp(lm, 0, zz)
		if p.y < w.water_level + 0.6:
			shore_z = zz
			break
	if shore_z == 0.0:
		shore_z = 40.0
	plaza(lm, 0, shore_z * 0.5 - 4.0, 36, shore_z * 0.5 + 2, 0.5)
	for k in 3:
		var x := -24.0 + k * 24.0
		var px := pl(lm, x, shore_z - 5.0, 0, Vector2(6, 2))
		px.origin.y = w.water_level + 1.0
		a.pier(px, 34.0, 5.0 if pier_kind == "wood" else 8.0, pier_kind)
		if k < boats.size():
			var bx_ := pl(lm, x + (6.0 if pier_kind == "wood" else 9.0), shore_z + 20.0, 0, Vector2(2, 2))
			bx_.origin.y = w.water_level
			a.boat(bx_, boats[k])
	for k in boats.size() - 3:
		var bx_ := pl(lm, rng.randf_range(-50, 50), shore_z + rng.randf_range(45, 90), rng.randf() * TAU, Vector2(2, 2))
		bx_.origin.y = w.water_level
		a.boat(bx_, boats[3 + k])
	for k in n_wh:
		var x := -30.0 + k * (60.0 / maxf(n_wh - 1, 1))
		var xf := pl(lm, x, shore_z - 20.0, 0, Vector2(14, 10))
		a.warehouse(xf, (60.0 / maxf(n_wh, 1)) - 3.0 if wh_kind != "kura" else 5.5, 9.0 if wh_kind != "kura" else 7.0, wh_kind)
	street(lm, -40, shore_z - 8.0, 40, shore_z - 8.0, 3.2)
	street(lm, 0, -30, 0, shore_z - 8.0, 3.0)
	extra.call(shore_z)
	# 実寸の大型船（data/ships → scripts/world/ships）: 岸近くか沖に錨泊。歩ける船内・浸水・沈没
	ShipYard.place_port(w, lm, era, shore_z)


func _port_jomon_kofun(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		for k in 4:
			a.pit_dwelling(pl(lm, -24 + k * 16, sz - 26, rng.randf() * TAU, Vector2(8, 8)), 3.2)
		a.raised_storehouse(pl(lm, -8, sz - 38, 0), 4.0, 3.2)
		a.raised_storehouse(pl(lm, 10, sz - 38, 0), 4.0, 3.2)
	_port_layout(lm, "wood", ["small", "small", "small", "small", "small"], "wood", 0, ex)


func _port_asuka_nara(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		a.jp_hall(pl(lm, 0, sz - 38, 0, Vector2(13, 9)), 12.0, 8.0, {"base_h": 0.6, "wall_h": 3.4, "roof": "irimoya", "over": 1.7, "lift": 0.5})
	_port_layout(lm, "wood", ["big", "small", "small", "small"], "wood", 3, ex)


func _port_heian(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		for k in 3:
			a.minka(pl(lm, -22 + k * 22, sz - 36, 0), 8.0, 5.5, "board")
	_port_layout(lm, "wood", ["big", "sail", "small", "small", "small"], "wood", 3, ex)


func _port_kamakura_muromachi(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		lots(lm, -36, sz - 33, 36, sz - 33, -1.0, 2.0, 7.5, 6.5, 9.0, _house_builder())
	_port_layout(lm, "wood", ["big", "big", "sail", "small", "small"], "wood", 3, ex)


func _port_sengoku(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		lots(lm, -36, sz - 33, 36, sz - 33, -1.0, 2.0, 8.0, 5.5, 7.5, _house_builder())
		for k in 3:
			a.nobori(wp(lm, -10 + k * 10, sz - 12), Color(0.9, 0.9, 0.85))
	_port_layout(lm, "wood", ["dutch", "sail", "small", "small", "small", "dutch"], "kura", 5, ex)


func _port_edo(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		lots(lm, -36, sz - 33, 36, sz - 33, -1.0, 2.0, 8.0, 5.5, 7.5, _house_builder())
		a.watchtower(pl(lm, 34, sz - 12, 0, Vector2(4, 4)), 8.0, 2.6, "rooftile")
	_port_layout(lm, "stone", ["sail", "steam", "dutch", "small", "small", "sail"], "kura", 6, ex)


func _port_meiji_taisho(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		for k in 6:
			a.lamp(wp(lm, -35 + k * 14, sz - 11), "gas")
		a.brick_building(pl(lm, 0, sz - 42, 0, Vector2(20, 12)), 18.0, 10.0, 2, {"mat": "plaster", "col": Color(0.95, 0.94, 0.9), "trim": Color(0.75, 0.72, 0.68), "dome": true})
	_port_layout(lm, "stone", ["steam", "sail", "steam", "small"], "brick", 3, ex)


func _port_showa(lm: Dictionary) -> void:
	var ex := func(sz: float) -> void:
		a.utility_line([wp(lm, -40, sz - 12), wp(lm, -14, sz - 12), wp(lm, 14, sz - 12), wp(lm, 40, sz - 12)])
		for k in 2:
			var xf := pl(lm, -12 + k * 24, sz - 2, 0, Vector2(6, 6))
			for cx in [-2.5, 2.5]:
				for cz in [-2.5, 2.5]:
					a.kit.box("metal", xf * Transform3D(Basis(), Vector3(cx, 8, cz)), Vector3(0.4, 16, 0.4), Color(0.85, 0.5, 0.15))
			a.kit.box("metal", xf * Transform3D(Basis(), Vector3(0, 16.5, 6)), Vector3(1.2, 1.2, 24), Color(0.85, 0.5, 0.15))
			a.col(xf, Vector3(0, 8, 0), Vector3(5.5, 16, 5.5))
		extra_car_spawns.append(w._xf_at(Vector2(wp(lm, 8, sz - 8).x, wp(lm, 8, sz - 8).z), _dir2(lm, Vector2(1, 0))))
	_port_layout(lm, "concrete", ["liner", "steam", "small"], "concrete", 3, ex)


# ================================================================ 城・官庁 castle（半径 50m）
func _castle_jomon_kofun(lm: Dictionary) -> void:
	# 吉野ヶ里: 環濠・柵・物見櫓
	var n := 26
	var rr := 40.0
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		if k == 6:
			continue
		a.palisade(wp(lm, cos(a0) * rr, sin(a0) * rr), wp(lm, cos(a1) * rr, sin(a1) * rr), 3.0)
	for k in 4:
		var ang := TAU * k / 4.0 + 0.4
		a.watchtower(pl(lm, cos(ang) * (rr - 6), sin(ang) * (rr - 6), 0, Vector2(4, 4)), 11.0)
	for k in 7:
		var ang := TAU * k / 7.0 + 0.2
		var r2 := rng.randf_range(18, 28)
		a.pit_dwelling(pl(lm, cos(ang) * r2, sin(ang) * r2, ang, Vector2(8, 8)), 3.4)
	for k in 3:
		a.raised_storehouse(pl(lm, -8 + k * 8, -6, 0), 3.8, 3.0)
	_raised_hall(pl(lm, 0, 8, 0, Vector2(12, 8)), 10.0, 7.0, 2.0)


func _castle_asuka_nara(lm: Dictionary) -> void:
	# 大宰府政庁と水城（土塁は terrain_features で盛る）
	a.jp_hall(pl(lm, 0, -22, 0, Vector2(20, 11)), 18.0, 10.0, {"base_h": 1.3, "wall_h": 4.4, "roof": "irimoya", "over": 2.3, "lift": 0.8})
	for sgn in [-1.0, 1.0]:
		a.jp_hall(pl(lm, sgn * 20, -2, -sgn * PI * 0.5, Vector2(14, 8)), 13.0, 7.0, {"base_h": 0.7, "wall_h": 3.4, "roof": "irimoya", "over": 1.6, "lift": 0.4})
	_kairo(corners(lm, 0, -8, 30, 22), [2])
	a.gate(pl(lm, 0, 14, 0, Vector2(10, 5)), 8.5, "romon")
	plaza(lm, 0, -8, 28, 20, 0.9)
	a.gate(pl(lm, 0, 42, 0, Vector2(8, 4)), 6.0, "yakui")


func _castle_heian(lm: Dictionary) -> void:
	# 胆沢城: 築地塀の方形の城柵と政庁
	a.wall_loop(corners(lm, 0, 0, 40, 40), 8.0, 3.2, Architecture.OCHRE, "tsuiji", [0, 1, 2, 3])
	a.gate(pl(lm, 0, 40, 0, Vector2(10, 5)), 8.5, "romon")
	a.jp_hall(pl(lm, 0, -18, 0, Vector2(18, 10)), 16.0, 9.0, {"base_h": 1.0, "wall_h": 4.0, "roof": "irimoya", "over": 2.0, "lift": 0.6})
	for sgn in [-1.0, 1.0]:
		a.jp_hall(pl(lm, sgn * 18, 2, -sgn * PI * 0.5, Vector2(12, 7)), 11.0, 6.0, {"base_h": 0.6, "wall_h": 3.2, "roof": "gable", "over": 1.4, "lift": 0.2})
		a.watchtower(pl(lm, sgn * 32, -32, 0, Vector2(4, 4)), 9.0, 3.0, "rooftile")
	plaza(lm, 0, -6, 26, 18, 0.85)
	street(lm, 0, 10, 0, 46, 3.0)


func _castle_kamakura_muromachi(lm: Dictionary) -> void:
	# 六波羅探題: 武家屋敷群
	for i in 2:
		for j in 2:
			a.buke_yashiki(lm["xf"], -22 + i * 44, -22 + j * 44, 0.0 if j == 1 else PI, 28.0, "thatch")
	street(lm, -48, 0, 48, 0, 3.4)
	street(lm, 0, -48, 0, 48, 3.4)
	for k in 5:
		a.nobori(wp(lm, -8 + k * 4, -5), Color(0.95, 0.95, 0.9) if k % 2 else Color(0.15, 0.15, 0.2))


func _castle_sengoku(lm: Dictionary) -> void:
	# 大坂城（黒と金）
	a.castle(pl(lm, 0, 0, 0, Vector2(40, 40)), 40.0, 11.0, 5, Architecture.PLASTER, true)
	var br := wp(lm, 0, 36)
	a.bridge(Vector2(br.x, br.z), _dir2(lm, Vector2(0, 1)), 14.0, 5.0, float(lm["h"]) + 0.6, "wood", 0.6)
	for k in 6:
		a.nobori(wp(lm, -11 + k * 4.4, 47), [Color(0.95, 0.85, 0.2), Color(0.85, 0.15, 0.1)][k % 2])


func _castle_edo(lm: Dictionary) -> void:
	# 大手町の大名屋敷街
	for i in 2:
		for j in 2:
			var c := pl(lm, -23 + i * 46, -23 + j * 46, 0.0 if j == 1 else PI, Vector2(34, 34))
			var hs := 15.0
			var cs := [c * Vector3(-hs, 0, -hs), c * Vector3(hs, 0, -hs), c * Vector3(hs, 0, hs), c * Vector3(-hs, 0, hs)]
			a.wall_loop(cs, 0.0, 2.8, Architecture.PLASTER, "tsuiji", [])
			a.gate(c * Transform3D(Basis(), Vector3(0, 0, hs + 1.5)), 12.0, "nagaya", Color(0.25, 0.22, 0.2))
			a.jp_hall(c * Transform3D(Basis(), Vector3(0, 0, -3)), 16.0, 10.0, {"base_h": 0.6, "wall_h": 3.4, "pillar": Color(0.82, 0.72, 0.6), "pillar_mat": "wood", "roof": "irimoya", "over": 1.8, "lift": 0.3, "roof_col": Architecture.TILE_DARK, "door_col": Color(0.95, 0.92, 0.85)})
			a.kura(c * Transform3D(Basis(), Vector3(9, 0, -10)), 4.5, 5.0, 4.4)
			t.paint_rect(t.plaza, Vector2(c.origin.x, c.origin.z), -c.basis.get_euler().y, hs, hs, 0.6, 1.5)
	street(lm, -50, 0, 50, 0, 4.0)
	street(lm, 0, -50, 0, 50, 3.4)


func _castle_meiji_taisho(lm: Dictionary) -> void:
	# 霞が関の煉瓦官庁（法務省旧本館風）
	a.brick_building(pl(lm, 0, -24, 0, Vector2(36, 16)), 34.0, 14.0, 3, {"roof_col": Color(0.35, 0.38, 0.42), "mansard": true})
	a.brick_building(pl(lm, -30, 20, PI * 0.5, Vector2(24, 13)), 22.0, 12.0, 3, {"mat": "plaster", "col": Color(0.96, 0.95, 0.9), "trim": Color(0.72, 0.7, 0.66)})
	a.brick_building(pl(lm, 30, 20, -PI * 0.5, Vector2(24, 13)), 22.0, 12.0, 2, {"dome": true})
	street(lm, -50, -4, 50, -4, 4.0)
	street(lm, 0, -4, 0, 50, 4.0)
	for k in 8:
		a.lamp(wp(lm, -35 + k * 10, 3), "gas")
	for k in 4:
		tree(lm, "broadleaf", -36 + k * 24, -10.5, 0.65)


func _castle_showa(lm: Dictionary) -> void:
	# 霞が関の官庁ビルと日本銀行（石造ドーム）
	a.brick_building(pl(lm, 0, -26, 0, Vector2(32, 18)), 30.0, 16.0, 3, {"mat": "concrete", "col": Color(0.9, 0.86, 0.78), "trim": Color(0.95, 0.92, 0.86), "dome": true})
	for sp in [[-32, 16, PI * 0.5], [32, 16, -PI * 0.5], [0, 36, PI]]:
		a.concrete_building(pl(lm, sp[0], sp[1], sp[2], Vector2(16, 14)), 15.0, 12.0, rng.randi_range(5, 7))
	street(lm, -50, -2, 50, -2, 4.6)
	street(lm, -16, -2, -16, 50, 3.4)
	street(lm, 16, -2, 16, 50, 3.4)
	for k in 6:
		a.lamp(wp(lm, -35 + k * 14, 5), "electric")
	extra_car_spawns.append(w._xf_at(Vector2(wp(lm, 10, -2).x, wp(lm, 10, -2).z), _dir2(lm, Vector2(1, 0))))


# ================================================================ 戦場 battlefield
func _bf_local(lm: Dictionary, s: float, side: float) -> Vector3:
	# s: -1..1 でカプセルの軸方向、side: 横方向 m
	var A: Vector2 = lm["a"]
	var B: Vector2 = lm["b"]
	var p := A.lerp(B, s * 0.5 + 0.5)
	var d := (B - A).normalized()
	var q := p + Vector2(-d.y, d.x) * side
	return Vector3(q.x, t.height_at(q.x, q.y), q.y)


func _bf_xf(lm: Dictionary, s: float, side: float, rot := 0.0, foot := Vector2(6, 6)) -> Transform3D:
	var A: Vector2 = lm["a"]
	var B: Vector2 = lm["b"]
	var d := (B - A).normalized()
	var p := _bf_local(lm, s, side)
	var base := atan2(d.x, d.y)
	var xf := Transform3D(Basis(Vector3.UP, base + rot), p)
	var y := INF
	for c in [Vector3(-foot.x, 0, -foot.y), Vector3(foot.x, 0, -foot.y), Vector3(-foot.x, 0, foot.y), Vector3(foot.x, 0, foot.y)]:
		var q: Vector3 = xf * (c * 0.5)
		y = minf(y, t.height_at(q.x, q.z))
	xf.origin.y = y
	return xf


func _battlefield_jomon_kofun(lm: Dictionary) -> void:
	plaza(lm, -10, 20, 34, 8, 0.6)
	if kofun.is_empty():
		return
	var c: Vector2 = kofun["c"]
	var fwd: Vector2 = kofun["fwd"]
	for k in 24:
		var ang := TAU * k / 24.0
		var p := c + Vector2(cos(ang), sin(ang)) * 17.5
		a.haniwa(Vector3(p.x, 0, p.y))
	for k in 8:
		var p := c + fwd * (18.0 + k * 4.0) + Vector2(-fwd.y, fwd.x) * (lerpf(6.5, 12.5, k / 7.0))
		var q := c + fwd * (18.0 + k * 4.0) - Vector2(-fwd.y, fwd.x) * (lerpf(6.5, 12.5, k / 7.0))
		a.haniwa(Vector3(p.x, 0, p.y))
		a.haniwa(Vector3(q.x, 0, q.y))
	# 広場の祭壇
	for k in 4:
		a.watchtower(_bf_xf(lm, -0.6 + k * 0.4, 21, 0, Vector2(4, 4)), 7.0)


func _battlefield_asuka_nara(lm: Dictionary) -> void:
	# 瀬田の唐橋
	if lm.has("channel"):
		var ch: Array = lm["channel"]
		var A: Vector2 = ch[0]
		var B: Vector2 = ch[1]
		var mid := (A + B) * 0.5
		var d := (B - A).normalized()
		a.bridge(mid, Vector2(-d.y, d.x), ch[2] * 2.0 + 6.0, 7.0, float(lm["h"]) + 0.5, "vermilion", 1.2)
	for k in 10:
		a.nobori(_bf_local(lm, rng.randf_range(-0.8, 0.8), rng.randf_range(-22, 22)), [Color(0.9, 0.2, 0.15), Color(0.95, 0.95, 0.9)][k % 2])
	for k in 4:
		a.jinmaku(_bf_local(lm, -0.75, -12 + k * 6), _bf_local(lm, -0.75, -6 + k * 6))


func _battlefield_heian(lm: Dictionary) -> void:
	# 白河北殿と源平の陣
	a.shinden(lm["xf"], -28, -3, 30.0)
	for k in 14:
		a.nobori(_bf_local(lm, rng.randf_range(-0.9, 0.9), rng.randf_range(-20, 20)), Color(0.95, 0.95, 0.92) if k % 2 else Color(0.85, 0.12, 0.1))
	for k in 6:
		var s := 0.05 + k * 0.12
		a.jinmaku(_bf_local(lm, s, 20), _bf_local(lm, s + 0.07, 20), Color(0.95, 0.94, 0.9))
		a.jinmaku(_bf_local(lm, -s, -20), _bf_local(lm, -s - 0.07, -20), Color(0.82, 0.18, 0.12))


func _battlefield_kamakura_muromachi(lm: Dictionary) -> void:
	# 博多湾の石築地（元寇防塁）
	a.stone_wall(_bf_local(lm, -0.95, 18), _bf_local(lm, 0.95, 18), 2.4)
	for k in 12:
		a.nobori(_bf_local(lm, -0.9 + k * 0.16, 12), Color(0.95, 0.95, 0.92) if k % 2 else Color(0.1, 0.1, 0.15))
	for k in 6:
		a.jinmaku(_bf_local(lm, -0.6 + k * 0.2, -14), _bf_local(lm, -0.6 + k * 0.2 + 0.08, -14))


func _battlefield_sengoku(lm: Dictionary) -> void:
	# 関ヶ原: 両軍の陣幕・のぼり・馬防柵
	var cols_e := [Color(0.1, 0.1, 0.12), Color(0.85, 0.75, 0.2)]
	var cols_w := [Color(0.85, 0.15, 0.1), Color(0.95, 0.95, 0.92)]
	for side in [-1.0, 1.0]:
		var s0: float = 0.7 * side
		for k in 4:
			var c := _bf_local(lm, s0, -18 + k * 12)
			var dd := 3.5
			a.jinmaku(c + Vector3(-dd, 0, -dd), c + Vector3(dd, 0, -dd))
			a.jinmaku(c + Vector3(dd, 0, -dd), c + Vector3(dd, 0, dd))
			a.jinmaku(c + Vector3(-dd, 0, dd), c + Vector3(-dd, 0, -dd))
		for k in 14:
			a.nobori(_bf_local(lm, s0 + rng.randf_range(-0.12, 0.12), rng.randf_range(-22, 22)), (cols_e if side > 0 else cols_w)[k % 2])
		for k in 4:
			a.baboosaku(_bf_local(lm, 0.3 * side, -24 + k * 12), _bf_local(lm, 0.3 * side, -14 + k * 12))
		for k in 2:
			var fp := _bf_local(lm, s0, -12 + k * 24)
			a.model("stone_fire_pit", Transform3D(Basis(), fp))


func _battlefield_edo(lm: Dictionary) -> void:
	# 両国広小路: 見世物小屋と屋台
	for k in 12:
		a.stall(_bf_xf(lm, -0.8 + k * 0.14, 14.0 if k % 2 else -14.0, PI * 0.5 if k % 2 else -PI * 0.5, Vector2(3, 2)), [Color(0.2, 0.25, 0.45), Color(0.8, 0.25, 0.15), Color(0.9, 0.85, 0.7), Color(0.3, 0.45, 0.3)][k % 4])
	var b := _house_builder()
	for sgn in [-1.0, 1.0]:
		for k in 10:
			var xf := _bf_xf(lm, -0.85 + k * 0.17, sgn * 24.0, PI if sgn > 0 else 0.0, Vector2(8, 10))
			b.call(xf, 7.0, 9.0)
	a.watchtower(_bf_xf(lm, 0.0, 0, 0, Vector2(3, 3)), 10.0, 2.4, "rooftile")
	for k in 12:
		a.lamp(_bf_local(lm, -0.9 + k * 0.16, 6), "lantern")


func _battlefield_meiji_taisho(lm: Dictionary) -> void:
	# 日比谷: 練兵場跡の広場と洋風の噴水
	var c := _bf_xf(lm, 0.0, 0, 0, Vector2(8, 8))
	a.cyl("stonewall", c, Vector3(0, -0.5, 0), 6.0, 6.0, 1.2, 20, Architecture.STONE)
	a.cyl("stonewall", c, Vector3(0, 0.7, 0), 1.0, 0.6, 2.8, 10, Architecture.STONE)
	a.cyl("stonewall", c, Vector3(0, 3.0, 0), 2.0, 2.0, 0.3, 12, Architecture.STONE)
	a.col(c, Vector3(0, 0.5, 0), Vector3(12, 1.2, 12))
	w.add_water_rect(c.origin + Vector3(0, 0.55, 0), Vector2(10.5, 10.5), 0.0)
	for k in 10:
		a.lamp(_bf_local(lm, -0.9 + k * 0.2, 9), "gas")
		a.lamp(_bf_local(lm, -0.9 + k * 0.2, -9), "gas")
	for sgn in [-1.0, 1.0]:
		a.brick_building(_bf_xf(lm, 0.5 * sgn, 22, PI, Vector2(22, 12)), 20.0, 10.0, 2, {})
	for k in 16:
		var p := _bf_local(lm, rng.randf_range(-0.9, 0.9), rng.randf_range(-24, -16) if k % 2 else rng.randf_range(-12, -8))
		if not t.is_occupied(p.x, p.z):
			w.deco_trees.append(["broadleaf" if k % 3 else "sakura", p, rng.randf_range(0.7, 1.0)])


func _battlefield_showa(lm: Dictionary) -> void:
	# 飛行場: 350m の滑走路・格納庫・管制塔（日比谷公園の広場を兼ねる）
	var A: Vector2 = lm["a"]
	var B: Vector2 = lm["b"]
	var d := (B - A).normalized()
	var n := Vector2(-d.y, d.x)
	var ra := A + d * 2.0
	var rb := B - d * 2.0
	t.paint_line(t.road, ra, rb, 15.0, 1.0, 1.0)
	# 中心線と端のマーキング
	var L := ra.distance_to(rb)
	var mark := MeshKit.new()
	var kk := 0.0
	while kk < L - 20.0:
		var p := ra + d * (kk + 14.0)
		var y := t.height_at(p.x, p.y) + 0.04
		var c3 := Vector3(p.x, y, p.y)
		mark.box("flat", Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), c3), Vector3(0.6, 0.02, 8.0), Color(0.95, 0.95, 0.9))
		kk += 16.0
	for end in [0.0, 1.0]:
		var base := ra.lerp(rb, end) + d * (6.0 if end == 0.0 else -6.0)
		for s in 8:
			var p := base + n * (-10.5 + s * 3.0)
			var y := t.height_at(p.x, p.y) + 0.04
			mark.box("flat", Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(p.x, y, p.y)), Vector3(1.2, 0.02, 10.0), Color(0.95, 0.95, 0.9))
	w.add_child(mark.commit("RunwayMarks", false))
	# 格納庫・管制塔（滑走路の脇）
	a.hangar(_bf_xf(lm, -0.55, 31, PI, Vector2(28, 22)), 28.0, 20.0)
	a.hangar(_bf_xf(lm, -0.3, 31, PI, Vector2(28, 22)), 28.0, 20.0)
	a.control_tower(_bf_xf(lm, -0.08, 26, 0, Vector2(7, 7)))
	# 吹き流し
	var ws := _bf_local(lm, 0.3, 22)
	a.kit.cylinder("metal", Transform3D(Basis(), ws), 0.06, 0.05, 6.0, 5, Color(0.8, 0.8, 0.8))
	a.kit.cylinder("cloth", Transform3D(Basis(Vector3.BACK, PI * 0.5), ws + Vector3(0, 5.6, 0)), 0.4, 0.15, 2.4, 8, Color(1.0, 0.45, 0.1))
	# 公園側（反対側）の木と街灯
	for k in 14:
		var p := _bf_local(lm, rng.randf_range(-0.9, 0.9), rng.randf_range(-26, -19))
		if not t.is_occupied(p.x, p.z):
			w.deco_trees.append(["broadleaf" if k % 4 else "sakura", p, rng.randf_range(0.7, 1.0)])
	for k in 8:
		a.lamp(_bf_local(lm, -0.8 + k * 0.23, -18), "electric")
	# 飛行機の出発位置: 滑走路の端、進行方向は滑走路沿い
	plane_spawns.append(w._xf_at(ra + d * 24.0, d))
	plane_spawns.append(w._xf_at(ra + d * 24.0 + n * 9.0, d))
	plane_spawns.append(w._xf_at(rb - d * 24.0, -d))


# ================================================================ 山 mountain
func _mountain_common(lm: Dictionary, kind: String) -> void:
	match kind:
		"shrine":
			a.torii(pl(lm, 0, 14, 0), 5.0, 4.8)
			a.jp_hall(pl(lm, 0, -12, 0, Vector2(10, 8)), 9.0, 7.0, {"base_h": 0.6, "wall_h": 3.0, "roof": "gable", "roof_mat": "thatch", "roof_col": Architecture.BARK, "over": 1.4, "lift": 0.0})
		"temple":
			a.jp_hall(pl(lm, 0, -14, 0, Vector2(18, 12)), 16.0, 11.0, {"base_h": 1.0, "wall_h": 4.0, "pillar": Color(0.82, 0.72, 0.6), "pillar_mat": "wood", "roof": "irimoya", "roof_mat": "thatch", "roof_col": Architecture.BARK, "over": 2.2, "lift": 0.3})
			for k in 4:
				a.stone_lantern(wp(lm, -4 if k % 2 == 0 else 4, 2 + (k / 2) * 8))
	for k in 6:
		var ang := rng.randf() * TAU
		tree(lm, "cedar", cos(ang) * rng.randf_range(18, 24), sin(ang) * rng.randf_range(18, 24), rng.randf_range(0.9, 1.2))


func _mountain_jomon_kofun(lm: Dictionary) -> void:
	_mountain_common(lm, "")
	for k in 4:
		var p := wp(lm, rng.randf_range(-14, 14), rng.randf_range(-14, 14))
		var s := rng.randf_range(1.5, 2.5)
		a.kit.sphere("rock", Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), p), 1.0, 10, 6, Color(0.7, 0.7, 0.68))
		a.cols.append([Transform3D(Basis(), p), Vector3(s * 1.6, s * 1.4, s * 1.6)])


func _mountain_asuka_nara(lm: Dictionary) -> void:
	_mountain_common(lm, "temple")


func _mountain_heian(lm: Dictionary) -> void:
	_mountain_common(lm, "temple")


func _mountain_kamakura_muromachi(lm: Dictionary) -> void:
	_mountain_common(lm, "temple")
	for k in 10:
		var ang := rng.randf() * TAU
		tree(lm, "sakura", cos(ang) * rng.randf_range(14, 30), sin(ang) * rng.randf_range(14, 30), rng.randf_range(0.7, 0.9))


func _mountain_sengoku(lm: Dictionary) -> void:
	_mountain_common(lm, "shrine")
	var c := wp(lm, 10, 4)
	a.jinmaku(c + Vector3(-5, 0, -5), c + Vector3(5, 0, -5))
	a.jinmaku(c + Vector3(5, 0, -5), c + Vector3(5, 0, 5))
	for k in 6:
		a.nobori(wp(lm, -14 + k * 5, 10), Color(0.95, 0.85, 0.2) if k % 2 else Color(0.1, 0.1, 0.12))


func _mountain_edo(lm: Dictionary) -> void:
	# 箱根の関所
	a.gate(pl(lm, 0, 0, 0, Vector2(6, 3)), 5.0, "kabuki", Color(0.8, 0.7, 0.6))
	a.jp_hall(pl(lm, -14, -4, PI * 0.5, Vector2(12, 7)), 11.0, 6.0, {"base_h": 0.4, "wall_h": 3.0, "pillar": Color(0.8, 0.7, 0.6), "pillar_mat": "wood", "roof": "irimoya", "roof_mat": "rooftile", "roof_col": Architecture.TILE_DARK, "over": 1.4, "lift": 0.2, "door_mat": "wood", "door_col": Color(0.95, 0.92, 0.85)})
	a.wood_fence(wp(lm, 3.5, 0), wp(lm, 18, 0), 2.2)
	a.wood_fence(wp(lm, -3.5, 0), wp(lm, -8, 0), 2.2)
	_mountain_common(lm, "")


func _mountain_meiji_taisho(lm: Dictionary) -> void:
	# 碓氷峠: 煉瓦アーチ橋（めがね橋）風の構造物と駅舎
	var xf := pl(lm, 0, -14, 0, Vector2(30, 8))
	for k in 4:
		var x := -15.0 + k * 10.0
		a.bx("brick", xf, Vector3(x, 3.0, 0), Vector3(2.4, 10.0, 6.0))
	a.bx("brick", xf, Vector3(0, 9.0, 0), Vector3(36.0, 2.4, 6.0))
	for k in 3:
		var x := -10.0 + k * 10.0
		for s in 6:
			var a0 := PI * s / 6.0
			a.bx("brick", xf, Vector3(x + cos(a0) * 3.8, 6.0 + sin(a0) * 2.0, 0), Vector3(1.6, 1.0, 6.0))
	a.col(xf, Vector3(0, 9.0, 0), Vector3(36, 2.4, 6))
	for k in 4:
		a.col(xf, Vector3(-15.0 + k * 10.0, 3.0, 0), Vector3(2.4, 10, 6))
	a.occupy(xf, 38, 8, 1.0)
	a.minka(pl(lm, 10, 8, 0), 8.0, 5.5, "rooftile")
	_mountain_common(lm, "")


func _mountain_showa(lm: Dictionary) -> void:
	_mountain_common(lm, "shrine")
	a.concrete_building(pl(lm, 16, 4, -PI * 0.5, Vector2(12, 10)), 10.0, 8.0, 1, {"tank": false})

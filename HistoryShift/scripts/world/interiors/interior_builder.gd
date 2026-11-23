class_name InteriorBuilder
extends RefCounted
## 内装 1 棟ぶんのジオメトリ・当たり判定・灯り・NPC 地点を作るビルダー。
## 座標はすべて建物の局所座標（Architecture.reg_interior の xf。原点=建物の足元中心、+Z=正面）。
## dry=true のときは地点（spots）だけを計算する（get_interior_points 用。描画物は作らない）。
## 見た目は外観と同じアニメ調の建物シェーダ（WorldMaterials）＋頂点カラーのベタ塗り。

var def: Dictionary
var era := ""
var dry := false
var kit := MeshKit.new()
var cols: Array = []        # [Transform3D(局所), Vector3 size]
var lights: Array = []      # {p, c, e, r}（実ライトの候補。マネージャが上限内で灯す）
var spots: Array = []       # {p, yaw, floor, role}
var fire_pts: Array = []    # 火災時に炎を出す位置（局所）
var rng := RandomNumberGenerator.new()    # 配置用（dry でも同じ順に消費する）
var vrng := RandomNumberGenerator.new()   # 見た目の揺らぎ用（dry では使わない）
var floors: Array = []
var shell_floors := false   # 外殻が上階の床面・天井面を持つ（町家・天守）


func _init(d: Dictionary, p_dry := false) -> void:
	def = d
	era = String(d.get("era", ""))
	dry = p_dry
	floors = d.get("floors", [])
	rng.seed = hash(int(d.get("id", 0)) * 7919 + 17)
	vrng.seed = rng.seed + 1
	shell_floors = String(d.get("type", "")) in ["machiya", "chaya", "nagaya", "castle"]


# ================================================================ 基本図形（dry なら何もしない）
func box(mat: String, c: Vector3, s: Vector3, colr := Color.WHITE, yaw := 0.0, collide := false, bottom := false) -> void:
	if collide:
		cols.append([Transform3D(Basis(Vector3.UP, yaw), c), s])
	if dry:
		return
	kit.box(mat, Transform3D(Basis(Vector3.UP, yaw), c), s, colr, not bottom)


func boxt(mat: String, t: Transform3D, s: Vector3, colr := Color.WHITE, bottom := false) -> void:
	if dry:
		return
	kit.box(mat, t, s, colr, not bottom)


func cyl(mat: String, base: Vector3, r0: float, r1: float, h: float, segs := 8, colr := Color.WHITE, collide := false) -> void:
	if collide:
		var r := maxf(r0, r1)
		cols.append([Transform3D(Basis(), base + Vector3(0, h * 0.5, 0)), Vector3(r * 1.6, h, r * 1.6)])
	if dry:
		return
	kit.cylinder(mat, Transform3D(Basis(), base), r0, r1, h, segs, colr)


func cylt(mat: String, t: Transform3D, r0: float, r1: float, h: float, segs := 8, colr := Color.WHITE) -> void:
	if dry:
		return
	kit.cylinder(mat, t, r0, r1, h, segs, colr)


func sph(mat: String, c: Vector3, r: float, colr := Color.WHITE, segs := 8, rings := 5, sc := Vector3.ONE) -> void:
	if dry:
		return
	kit.sphere(mat, Transform3D(Basis().scaled(sc), c), r, segs, rings, colr)


func rod(mat: String, a: Vector3, b: Vector3, r: float, colr := Color.WHITE, segs := 5) -> void:
	if dry:
		return
	kit.rod(mat, a, b, r, segs, colr)


func quad(mat: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, colr: Color) -> void:
	if dry:
		return
	kit.quad(mat, p0, p1, p2, p3, colr)


## 水平な矩形（up=上向き）。hole を抜く
func hrect(mat: String, r: Rect2, y: float, colr: Color, up := true, hole := Rect2()) -> void:
	if dry:
		return
	for q in rect_split(r, hole):
		var p0 := Vector3(q.position.x, y, q.end.y)
		var p1 := Vector3(q.end.x, y, q.end.y)
		var p2 := Vector3(q.end.x, y, q.position.y)
		var p3 := Vector3(q.position.x, y, q.position.y)
		if up:
			kit.quad(mat, p0, p1, p2, p3, colr)
		else:
			kit.quad(mat, p0, p3, p2, p1, colr)


static func rect_split(r: Rect2, hole: Rect2) -> Array:
	if hole.size.x < 0.01 or hole.size.y < 0.01:
		return [r]
	var h := hole.intersection(r)
	if h.size.x < 0.01 or h.size.y < 0.01:
		return [r]
	var out: Array = []
	for q in [Rect2(r.position.x, r.position.y, r.size.x, h.position.y - r.position.y),
			Rect2(r.position.x, h.end.y, r.size.x, r.end.y - h.end.y),
			Rect2(r.position.x, h.position.y, h.position.x - r.position.x, h.size.y),
			Rect2(h.end.x, h.position.y, r.end.x - h.end.x, h.size.y)]:
		if q.size.x > 0.01 and q.size.y > 0.01:
			out.append(q)
	return out


func col_box(c: Vector3, s: Vector3, yaw := 0.0) -> void:
	cols.append([Transform3D(Basis(Vector3.UP, yaw), c), s])


func ramp(a: Vector3, b: Vector3, w: float) -> void:
	var e := Architecture.ramp_shape(Transform3D.IDENTITY, a, b, w)
	if not e.is_empty():
		cols.append(e)


func spot(p: Vector3, yaw: float, role := "stand", floor_i := 0) -> void:
	spots.append({"p": p, "yaw": yaw, "floor": floor_i, "role": role})


func light(p: Vector3, c: Color, e := 1.0, r := 8.0) -> void:
	lights.append({"p": p, "c": c, "e": e, "r": r})


# ================================================================ 階の情報
func fy(i: int) -> float:
	return float(floors[i]["y"])


func fh(i: int) -> float:
	return float(floors[i]["h"])


func fr(i: int) -> Rect2:
	return floors[i]["rect"]


func fc(i: int) -> Vector3:
	var r := fr(i)
	var c := r.get_center()
	return Vector3(c.x, fy(i), c.y)


## 床の吹き抜け（下の階の階段が上がってくる穴）
func floor_hole(i: int) -> Rect2:
	if i <= 0:
		return Rect2()
	var below: Dictionary = floors[i - 1]
	return below.get("hole", Rect2())


## i 階の面 side の壁の内側の線: [始点, 方向(長さ付き), 内向き法線]
func side_line(i: int, side: int) -> Array:
	var r := fr(i)
	var y := fy(i)
	match side:
		0: return [Vector3(r.position.x, y, r.end.y), Vector3(r.size.x, 0, 0), Vector3(0, 0, -1)]
		2: return [Vector3(r.end.x, y, r.position.y), Vector3(-r.size.x, 0, 0), Vector3(0, 0, 1)]
		1: return [Vector3(r.end.x, y, r.end.y), Vector3(0, 0, -r.size.y), Vector3(-1, 0, 0)]
		_: return [Vector3(r.position.x, y, r.position.y), Vector3(0, 0, r.size.y), Vector3(1, 0, 0)]


## 面 side 上の開口（入口・窓）を、side_line の始点からの距離 [t0, t1, y0, y1]（y は床から）で返す
func openings(i: int, side: int) -> Array:
	var out: Array = []
	var sl := side_line(i, side)
	var o: Vector3 = sl[0]
	var d: Vector3 = sl[1]
	var L := d.length()
	var dn := d / maxf(L, 0.001)
	for dd in def.get("doors", []):
		var p: Vector3 = dd["p"]
		if absf(p.y - fy(i)) > 0.6:
			continue
		var n: Vector3 = dd["n"]
		if n.dot(-(sl[2] as Vector3)) < 0.7:
			continue
		# その面の近くにある入口だけ
		var off := (p - o)
		if absf(off.dot(sl[2])) > 1.2:
			continue
		var t := off.dot(dn)
		out.append([t - float(dd["w"]) * 0.5 - 0.08, t + float(dd["w"]) * 0.5 + 0.08, 0.0, float(dd["h"]) + 0.12])
	for wv in floors[i].get("win", []):
		if int(wv["side"]) != side:
			continue
		var u := float(wv["u"])
		var p := Vector3(u, 0, o.z) if side % 2 == 0 else Vector3(o.x, 0, u)
		var t := (p - Vector3(o.x, 0, o.z)).dot(dn)
		out.append([t - float(wv["w"]) * 0.5 - 0.05, t + float(wv["w"]) * 0.5 + 0.05, float(wv["y"]) - 0.05, float(wv["y"]) + float(wv["h"]) + 0.05])
	for ex in floors[i].get("open_extra", []):
		if int(ex[0]) == side:
			out.append([ex[1], ex[2], ex[3], ex[4]])
	out.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	return out


## 壁沿いに区間を並べる（開口を避ける）。fn(a: Vector3 区間始点, dir: Vector3 単位, len, n: Vector3 内向き)
func along_wall(i: int, side: int, y0: float, y1: float, fn: Callable, inset := 0.03, margin := 0.0) -> void:
	var sl := side_line(i, side)
	var o: Vector3 = sl[0]
	var d: Vector3 = sl[1]
	var n: Vector3 = sl[2]
	var L := d.length()
	var dn := d / maxf(L, 0.001)
	var cur := margin
	var segs: Array = []
	for op in openings(i, side):
		if float(op[3]) <= y0 or float(op[2]) >= y1:
			continue
		if float(op[0]) > cur:
			segs.append([cur, float(op[0])])
		cur = maxf(cur, float(op[1]))
	if L - margin > cur:
		segs.append([cur, L - margin])
	for sg in segs:
		var a: Vector3 = o + dn * float(sg[0]) + n * inset
		fn.call(a, dn, float(sg[1]) - float(sg[0]), n)


# ================================================================ 構造（床・天井・階段）
## 上階の床（当たり判定と見た目）、各階の天井（カメラが抜けないよう当たり判定も）、階段
func structure(ceil_mat := "wood", ceil_col := Color(0.62, 0.5, 0.4), stair_style := "wood", stair_col := Color(0.62, 0.46, 0.34)) -> void:
	for i in floors.size():
		var f: Dictionary = floors[i]
		var r := fr(i)
		var y := fy(i)
		var h := fh(i)
		var hole: Rect2 = f.get("hole", Rect2())
		# 上の階の床と重なるか
		var next_y := INF
		for j in floors.size():
			if j != i and absf(fy(j) - (y + h)) < 0.45 and fr(j).intersects(r):
				next_y = fy(j)
		# 天井の当たり判定（上階があればその床を兼ねる: 上面＝上階の床）
		var top := y + h if next_y == INF else minf(y + h, next_y)
		var s0 := top - 0.02
		var s1 := top + 0.24
		if next_y != INF:
			s0 = minf(top - 0.02, next_y - 0.24)
			s1 = next_y
		for q in rect_split(r.grow(0.15), hole):
			col_box(Vector3(q.get_center().x, (s0 + s1) * 0.5, q.get_center().y), Vector3(q.size.x, s1 - s0, q.size.y))
		# 見た目: 外殻が床・天井を持たない建物（洋館・ビル・商店）は中間の天井と上階の床を作る
		var more_above := int(def.get("floors_total", 0)) > floors.size() and next_y == INF and i == floors.size() - 1
		if not shell_floors and (next_y != INF or more_above):
			hrect(ceil_mat, r, top - 0.012, ceil_col, false, hole)
			# 吹き抜けの縁
			if hole.size.x > 0.0:
				var hc := hole.get_center()
				for sgn in [-1.0, 1.0]:
					box("wood", Vector3(hc.x, top - 0.12, hc.y + sgn * hole.size.y * 0.5), Vector3(hole.size.x, 0.24, 0.06), stair_col)
		var st: Dictionary = f.get("stair", {})
		if not st.is_empty():
			stairs(st, stair_style, stair_col)


## 階段（a=下の段の位置、b=上の段の位置、w=幅）。style: wood（板の段＋側桁）/ box（箱階段）/ solid（石・コンクリ）/ western（手すり）
func stairs(st: Dictionary, style := "wood", colr := Color(0.62, 0.46, 0.34)) -> void:
	var a: Vector3 = st["a"]
	var b: Vector3 = st["b"]
	var w: float = st.get("w", 1.0)
	var rise := b.y - a.y
	var hz := Vector3(b.x - a.x, 0, b.z - a.z)
	var run := hz.length()
	if run < 0.1:
		return
	var dn := hz / run
	var yaw := atan2(dn.x, dn.z)
	var bs := Basis(Vector3.UP, yaw)
	var n := maxi(3, int(ceil(rise / 0.22)))
	ramp(a - dn * 0.15 + Vector3(0, -0.02, 0), b + dn * 0.1, w)
	# 手すり側（上り口から見て右）
	var side := bs * Vector3(-1, 0, 0)
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var p := a + hz * (t0 + t1) * 0.5
		var top := a.y + rise * t1
		match style:
			"box", "solid":
				var bot := a.y
				var m := "darkwood" if style == "box" else "concrete"
				box(m, Vector3(p.x, (top + bot) * 0.5, p.z), Vector3(w, top - bot, run / n + 0.01), colr, yaw)
				if style == "box" and k < n - 2 and k % 2 == 0:
					# 箱階段の引き出し
					box("metal", Vector3(p.x, bot + (top - bot) * 0.5, p.z) + side * (w * 0.5 + 0.005), Vector3(0.02, 0.05, 0.12), Color(0.2, 0.18, 0.15), yaw)
			_:
				box("wood", Vector3(p.x, top - 0.04, p.z), Vector3(w, 0.08, run / n + 0.04), colr, yaw)
	if style in ["wood", "western"]:
		for sgn in [-1.0, 1.0]:
			var off: Vector3 = side * sgn * (w * 0.5 + 0.03)
			rod("darkwood", a + off + Vector3(0, -0.05, 0) - dn * 0.1, b + off + Vector3(0, -0.12, 0), 0.05, colr * 0.8, 4)
	if style == "western":
		var off := side * (w * 0.5 + 0.05)
		rod("darkwood", a + off + Vector3(0, 0.95, 0), b + off + Vector3(0, 0.95, 0), 0.04, Color(0.4, 0.26, 0.18), 5)
		for k in 6:
			var q := a.lerp(b, (k + 0.5) / 6.0) + off
			rod("wood", q, q + Vector3(0, 0.95, 0), 0.02, Color(0.9, 0.86, 0.78), 4)
	elif style == "solid":
		var off := side * (w * 0.5 + 0.05)
		rod("metal", a + off + Vector3(0, 0.9, 0), b + off + Vector3(0, 0.9, 0), 0.025, Color(0.3, 0.3, 0.32), 4)


# ================================================================ 床仕上げ
## style: tatami / boards / earth / stone / parquet / carpet / concrete / linoleum / tile / mat
func finish(r: Rect2, y: float, style: String, colr := Color.WHITE, hole := Rect2(), kyo := false) -> void:
	if dry:
		return
	var yy := y + 0.012
	match style:
		"tatami":
			tatami(r, y, hole, kyo)
		"boards":
			hrect("wood", r, yy, colr if colr != Color.WHITE else Color(0.86, 0.72, 0.56), true, hole)
			# 板目の筋
			var n := int(r.size.x / 0.3)
			for k in range(1, n):
				var x := r.position.x + k * r.size.x / n
				for q in rect_split(Rect2(x - 0.008, r.position.y, 0.016, r.size.y), hole):
					hrect("flat", q, yy + 0.003, Color(0.42, 0.32, 0.24), true)
		"earth":
			hrect("earth", r, yy, colr if colr != Color.WHITE else Color(0.72, 0.6, 0.48), true, hole)
		"stone":
			hrect("stonewall", r, yy, colr if colr != Color.WHITE else Color(0.7, 0.68, 0.64), true, hole)
		"parquet":
			hrect("wood", r, yy, colr if colr != Color.WHITE else Color(0.72, 0.5, 0.34), true, hole)
			var nx := int(r.size.x / 0.9)
			var nz := int(r.size.y / 0.9)
			for ix in nx:
				for iz in nz:
					if (ix + iz) % 2 == 0:
						var q := Rect2(r.position.x + ix * r.size.x / nx + 0.02, r.position.y + iz * r.size.y / nz + 0.02, r.size.x / nx - 0.04, r.size.y / nz - 0.04)
						if hole.size.x > 0.0 and hole.intersects(q):
							continue
						hrect("wood", q, yy + 0.003, Color(0.58, 0.38, 0.24), true)
		"carpet":
			hrect("cloth", r, yy + 0.01, colr, true, hole)
		"concrete", "linoleum", "tile":
			hrect("concrete" if style == "concrete" else "flat", r, yy, colr if colr != Color.WHITE else Color(0.72, 0.72, 0.7), true, hole)
			if style == "tile":
				var n := int(r.size.x / 0.6)
				for k in range(1, n):
					var x := r.position.x + k * r.size.x / n
					hrect("flat", Rect2(x - 0.01, r.position.y, 0.02, r.size.y), yy + 0.003, colr.darkened(0.25), true)
		"mat":
			hrect("tatami", r, yy, colr if colr != Color.WHITE else Color(0.86, 0.78, 0.55), true, hole)


## 畳敷き（京間 0.955×1.91 / 江戸間 0.88×1.76）。縁（へり）付き。行ごとに向きを変える
func tatami(r: Rect2, y: float, hole := Rect2(), kyo := false, heri := Color(0.16, 0.14, 0.12)) -> void:
	if dry:
		return
	var s := 0.955 if kyo else 0.88
	var ln := s * 2.0
	var tcol := Color(0.86, 0.84, 0.6) if era != "showa" else Color(0.84, 0.82, 0.62)
	var z := r.position.y
	var row := 0
	while z < r.end.y - 0.05:
		var horiz := row % 2 == 0
		var dz := s if horiz else ln
		dz = minf(dz, r.end.y - z)
		var x := r.position.x
		while x < r.end.x - 0.05:
			var dx := ln if horiz else s
			dx = minf(dx, r.end.x - x)
			var q := Rect2(x + 0.005, z + 0.005, dx - 0.01, dz - 0.01)
			if hole.size.x > 0.0 and hole.intersects(q):
				x += dx
				continue
			kit.box("tatami", Transform3D(Basis(), Vector3(q.get_center().x, y + 0.03, q.get_center().y)), Vector3(q.size.x, 0.06, q.size.y), tcol.lerp(Color(0.8, 0.82, 0.55), vrng.randf() * 0.3))
			# 縁（長辺）
			if horiz:
				for sgn in [-1.0, 1.0]:
					kit.box("cloth", Transform3D(Basis(), Vector3(q.get_center().x, y + 0.062, q.get_center().y + sgn * (q.size.y * 0.5 - 0.02))), Vector3(q.size.x, 0.006, 0.04), heri)
			else:
				for sgn in [-1.0, 1.0]:
					kit.box("cloth", Transform3D(Basis(), Vector3(q.get_center().x + sgn * (q.size.x * 0.5 - 0.02), y + 0.062, q.get_center().y)), Vector3(0.04, 0.006, q.size.y), heri)
			x += dx
		z += dz
		row += 1


# ================================================================ 壁の仕上げ
## 壁沿いの建具（style: shoji 障子 / fusuma 襖 / gold 金碧の襖 / panel 板壁 / misu 御簾）
func fittings(i: int, side: int, style: String, colr := Color.WHITE, h := 0.0) -> void:
	var hh := h if h > 0.0 else minf(fh(i) - 0.15, 2.4)
	var fyb := fy(i)
	along_wall(i, side, 0.0, hh, func(a: Vector3, dn: Vector3, L: float, n: Vector3) -> void:
		var np := maxi(1, int(round(L / 0.9)))
		var pw := L / np
		var yaw := atan2(dn.x, dn.z) - PI * 0.5
		for k in np:
			var c := a + dn * pw * (k + 0.5) + Vector3(0, hh * 0.5 + 0.02, 0)
			c.y = fyb + hh * 0.5 + 0.02
			match style:
				"shoji":
					box("flat", c, Vector3(pw - 0.02, hh, 0.02), Color(0.97, 0.96, 0.9), yaw)
					for g in 3:
						var gx := -pw * 0.5 + pw * (g + 1) / 4.0
						box("wood", c + dn * gx + n * 0.012, Vector3(0.025, hh, 0.012), Color(0.75, 0.62, 0.46), yaw)
					for g in 5:
						box("wood", c + Vector3(0, -hh * 0.5 + hh * (g + 1) / 6.0, 0) + n * 0.012, Vector3(pw, 0.025, 0.012), Color(0.75, 0.62, 0.46), yaw)
					box("wood", c + Vector3(0, -hh * 0.5 + 0.15, 0) + n * 0.014, Vector3(pw, 0.3, 0.014), Color(0.72, 0.58, 0.42), yaw)
				"fusuma", "gold":
					var pc := colr
					if style == "gold":
						pc = Color(0.93, 0.68, 0.22)   # 金箔地（ベタの濃い金）
					box("flat", c, Vector3(pw - 0.03, hh, 0.02), pc, yaw)
					# 縁と引手
					for sgn in [-1.0, 1.0]:
						box("darkwood", c + dn * sgn * (pw * 0.5 - 0.02) + n * 0.012, Vector3(0.035, hh, 0.02), Color(0.2, 0.15, 0.12), yaw)
						box("darkwood", c + Vector3(0, sgn * (hh * 0.5 - 0.02), 0) + n * 0.012, Vector3(pw, 0.035, 0.02), Color(0.2, 0.15, 0.12), yaw)
					box("metal", c + dn * (pw * 0.3 if k % 2 == 0 else -pw * 0.3) + n * 0.018, Vector3(0.06, 0.08, 0.01), Color(0.25, 0.2, 0.12), yaw)
					if style == "gold" and k % 2 == 0:
						# 障壁画: 松の枝と雲（ベタ塗りの形）
						box("flat", c + Vector3(0, -hh * 0.18, 0) + n * 0.014, Vector3(pw * 0.7, 0.12, 0.01), Color(0.25, 0.38, 0.22), yaw + 0.3)
						box("flat", c + Vector3(pw * 0.1, hh * 0.05, 0) + n * 0.014, Vector3(pw * 0.5, 0.22, 0.01), Color(0.2, 0.42, 0.26), yaw)
						box("flat", c + Vector3(-pw * 0.15, hh * 0.3, 0) + n * 0.013, Vector3(pw * 0.8, 0.14, 0.01), Color(1.0, 0.92, 0.65), yaw)
					elif style == "fusuma" and k % 3 == 1:
						box("flat", c + Vector3(0, -hh * 0.1, 0) + n * 0.014, Vector3(pw * 0.6, 0.06, 0.01), colr.darkened(0.3), yaw)
				"panel":
					box("wood", c, Vector3(pw - 0.01, hh, 0.03), colr if colr != Color.WHITE else Color(0.75, 0.6, 0.45), yaw)
					box("darkwood", c + dn * (pw * 0.5 - 0.02) + n * 0.02, Vector3(0.05, hh, 0.02), Color(0.4, 0.3, 0.24), yaw)
				"misu":
					# 御簾（竹のすだれ＋上の帽額）
					var mh := hh * 0.8
					var mc := c + Vector3(0, hh * 0.1, 0)
					box("bamboo", mc, Vector3(pw - 0.02, mh, 0.012), Color(0.86, 0.76, 0.5), yaw)
					for g in 6:
						box("flat", mc + Vector3(0, -mh * 0.5 + mh * (g + 0.5) / 6.0, 0) + n * 0.008, Vector3(pw, 0.012, 0.004), Color(0.55, 0.42, 0.25), yaw)
					box("cloth", mc + Vector3(0, mh * 0.5 - 0.06, 0) + n * 0.01, Vector3(pw, 0.14, 0.01), colr if colr != Color.WHITE else Color(0.55, 0.12, 0.18), yaw)
		, 0.03, 0.0)


## 長押（なげし）と欄間の帯
func nageshi(i: int, y_off := 2.1, colr := Color(0.55, 0.42, 0.32)) -> void:
	for side in 4:
		var sl := side_line(i, side)
		var a: Vector3 = sl[0]
		var d: Vector3 = sl[1]
		var n: Vector3 = sl[2]
		var c := a + d * 0.5 + n * 0.04 + Vector3(0, y_off, 0)
		box("wood", c, Vector3(d.length() if side % 2 == 0 else 0.08, 0.1, 0.08 if side % 2 == 0 else d.length()), colr)


## 洋室の壁紙・腰板・幅木
func wallpaper(i: int, colr: Color, wainscot := Color(0.45, 0.3, 0.2), h := 0.0) -> void:
	var hh := h if h > 0.0 else fh(i) - 0.05
	var yb := fy(i)
	for side in 4:
		along_wall(i, side, 0.0, hh, func(a: Vector3, dn: Vector3, L: float, n: Vector3) -> void:
			var c := a + dn * L * 0.5
			var yaw := atan2(dn.x, dn.z) - PI * 0.5
			box("flat", Vector3(c.x, yb + hh * 0.5 + 0.45, c.z), Vector3(L, hh - 0.9, 0.01), colr, yaw)
			box("wood", Vector3(c.x, yb + 0.45, c.z) + n * 0.01, Vector3(L, 0.9, 0.03), wainscot, yaw)
			box("wood", Vector3(c.x, yb + 0.92, c.z) + n * 0.02, Vector3(L, 0.06, 0.05), wainscot.darkened(0.2), yaw)
			box("wood", Vector3(c.x, yb + hh - 0.08, c.z) + n * 0.02, Vector3(L, 0.14, 0.06), Color(0.92, 0.9, 0.84), yaw)
			, 0.02)


## 内側から見える窓（外観の窓の位置に、空色のガラス面＋窓枠）
func faux_window(p: Vector3, n: Vector3, w: float, h: float, frame := Color(0.9, 0.88, 0.82)) -> void:
	var yaw := atan2(n.x, n.z)
	box("glass", p, Vector3(w, h, 0.02), Color(0.75, 0.85, 0.95), yaw)
	for sgn in [-1.0, 1.0]:
		box("wood", p + Basis(Vector3.UP, yaw) * Vector3(sgn * w * 0.5, 0, 0.02), Vector3(0.08, h + 0.08, 0.05), frame, yaw)
		box("wood", p + Vector3(0, sgn * h * 0.5, 0) + n * 0.02, Vector3(w + 0.08, 0.08, 0.05) if absf(n.z) > 0.5 else Vector3(0.05, 0.08, w + 0.08), frame)
	box("wood", p + n * 0.02, Vector3(0.04, h, 0.03), frame, yaw)


# ================================================================ 灯り
## 時代の灯り。kind: hearth / toumyo（灯明皿）/ toudai（灯台）/ andon（行灯）/ chouchin（提灯）/ shokudai（燭台）
## / lamp（石油ランプ）/ gaslight / bulb（電球）/ fluorescent / chandelier
func lamp(kind: String, p: Vector3, real := true) -> void:
	var warm := Color(1.0, 0.62, 0.3)
	match kind:
		"toudai", "toumyo":
			if kind == "toudai":
				cyl("darkwood", p, 0.12, 0.1, 0.05, 6, Color(0.25, 0.2, 0.16))
				rod("darkwood", p, p + Vector3(0, 0.9, 0), 0.02, Color(0.3, 0.22, 0.16))
			var top := p + Vector3(0, 0.92 if kind == "toudai" else 0.02, 0)
			cyl("earth", top, 0.07, 0.09, 0.03, 8, Color(0.6, 0.4, 0.3))
			sph("emissive", top + Vector3(0, 0.07, 0), 0.035, Color(1.0, 0.75, 0.35), 6, 4, Vector3(1, 1.8, 1))
			if real:
				light(top + Vector3(0, 0.3, 0), warm, 0.7, 5.5)
		"andon":
			box("darkwood", p + Vector3(0, 0.38, 0), Vector3(0.36, 0.04, 0.36), Color(0.3, 0.22, 0.16))
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					box("darkwood", p + Vector3(cx * 0.16, 0.42, cz * 0.16), Vector3(0.025, 0.84, 0.025), Color(0.3, 0.22, 0.16))
			box("emissive", p + Vector3(0, 0.58, 0), Vector3(0.3, 0.44, 0.3), Color(1.0, 0.78, 0.48))
			if real:
				light(p + Vector3(0, 0.7, 0), warm, 0.9, 6.0)
		"chouchin":
			rod("darkwood", p + Vector3(0, 0.5, 0), p + Vector3(0, 0.25, 0), 0.01, Color(0.2, 0.15, 0.1), 3)
			sph("emissive", p, 0.2, Color(1.0, 0.6, 0.32), 8, 5, Vector3(1, 1.4, 1))
			if real:
				light(p, warm, 0.9, 6.5)
		"shokudai":
			cyl("metal", p, 0.12, 0.08, 0.04, 6, Color(0.2, 0.18, 0.15))
			rod("metal", p, p + Vector3(0, 0.75, 0), 0.015, Color(0.2, 0.18, 0.15))
			cyl("flat", p + Vector3(0, 0.75, 0), 0.025, 0.025, 0.12, 6, Color(0.95, 0.92, 0.85))
			sph("emissive", p + Vector3(0, 0.92, 0), 0.03, Color(1.0, 0.75, 0.35), 6, 4, Vector3(1, 1.8, 1))
			if real:
				light(p + Vector3(0, 1.0, 0), warm, 0.8, 5.5)
		"hearth":
			if real:
				light(p + Vector3(0, 0.6, 0), Color(1.0, 0.5, 0.22), 1.3, 7.0)
		"lamp":
			# 石油ランプ（ガラスの火屋）
			cyl("metal", p, 0.08, 0.06, 0.12, 8, Color(0.6, 0.45, 0.2))
			sph("glass", p + Vector3(0, 0.2, 0), 0.08, Color(0.9, 0.9, 0.8), 8, 5)
			sph("emissive", p + Vector3(0, 0.2, 0), 0.04, Color(1.0, 0.8, 0.45))
			cyl("glass", p + Vector3(0, 0.26, 0), 0.03, 0.025, 0.18, 6, Color(0.9, 0.9, 0.85))
			if real:
				light(p + Vector3(0, 0.4, 0), Color(1.0, 0.72, 0.42), 1.0, 7.0)
		"gaslight":
			rod("metal", p + Vector3(0, 0.6, 0), p, 0.015, Color(0.2, 0.2, 0.2), 4)
			sph("emissive", p, 0.12, Color(1.0, 0.85, 0.55), 8, 5)
			if real:
				light(p, Color(1.0, 0.82, 0.58), 1.2, 9.0)
		"bulb":
			rod("wire", p + Vector3(0, 0.7, 0), p + Vector3(0, 0.1, 0), 0.008, Color(0.1, 0.1, 0.1), 3)
			cylt("metal", Transform3D(Basis(), p + Vector3(0, 0.02, 0)), 0.22, 0.04, 0.12, 10, Color(0.92, 0.9, 0.85))
			sph("emissive", p, 0.05, Color(1.0, 0.9, 0.7))
			if real:
				light(p + Vector3(0, -0.1, 0), Color(1.0, 0.86, 0.62), 1.1, 7.5)
		"fluorescent":
			box("metal", p + Vector3(0, 0.03, 0), Vector3(1.2, 0.05, 0.18), Color(0.92, 0.92, 0.9))
			box("emissive", p, Vector3(1.1, 0.04, 0.05), Color(0.9, 0.97, 1.0))
			if real:
				light(p + Vector3(0, -0.15, 0), Color(0.92, 0.97, 1.0), 1.0, 8.5)
		"chandelier":
			rod("metal", p + Vector3(0, 0.9, 0), p + Vector3(0, 0.2, 0), 0.02, Color(0.7, 0.55, 0.25), 4)
			sph("gold", p + Vector3(0, 0.15, 0), 0.12, Color(1, 0.85, 0.45))
			for k in 8:
				var a := TAU * k / 8.0
				var q := p + Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55)
				rod("metal", p + Vector3(0, 0.1, 0), q, 0.012, Color(0.75, 0.6, 0.3), 3)
				sph("emissive", q + Vector3(0, 0.08, 0), 0.05, Color(1.0, 0.9, 0.65), 6, 4, Vector3(1, 1.5, 1))
			for k in 6:
				var a := TAU * (k + 0.5) / 6.0
				sph("glass", p + Vector3(cos(a) * 0.3, -0.15, sin(a) * 0.3), 0.04, Color(0.95, 0.95, 1.0), 5, 3)
			if real:
				light(p, Color(1.0, 0.86, 0.62), 1.6, 12.0)


# ================================================================ 和の調度
func zabuton(p: Vector3, colr := Color(0.55, 0.18, 0.2), yaw := 0.0) -> void:
	box("cloth", p + Vector3(0, 0.05, 0), Vector3(0.55, 0.07, 0.6), colr, yaw)


func enza(p: Vector3) -> void:
	# 円座（藁の丸い敷物）
	cyl("thatch", p, 0.3, 0.3, 0.05, 12, Color(0.85, 0.75, 0.5))


func hibachi(p: Vector3) -> void:
	cyl("earth", p, 0.24, 0.27, 0.3, 10, Color(0.35, 0.4, 0.55), true)
	cyl("earth", p + Vector3(0, 0.24, 0), 0.2, 0.2, 0.04, 10, Color(0.72, 0.7, 0.66))
	sph("emissive", p + Vector3(0, 0.29, 0), 0.06, Color(1.0, 0.35, 0.1), 6, 3, Vector3(1.4, 0.5, 1.4))


func byobu(p: Vector3, yaw: float, colr := Color(1.0, 0.82, 0.42), panels := 6, h := 1.5) -> void:
	var pw := 0.5
	for k in panels:
		var a := yaw + (0.35 if k % 2 == 0 else -0.35)
		var off := Basis(Vector3.UP, yaw) * Vector3((k - panels * 0.5 + 0.5) * pw * 0.94, 0, 0)
		box("flat", p + off + Vector3(0, h * 0.5, 0), Vector3(pw, h, 0.03), Color(0.93, 0.68, 0.22) if colr.r > 0.95 else colr, a)
		box("darkwood", p + off + Vector3(0, h, 0), Vector3(pw, 0.04, 0.05), Color(0.15, 0.1, 0.08), a)
		if k % 2 == 1:
			box("flat", p + off + Vector3(0, h * 0.45, 0) + Basis(Vector3.UP, a) * Vector3(0, 0, 0.02), Vector3(pw * 0.6, 0.18, 0.01), Color(0.3, 0.45, 0.28), a)


func kicho(p: Vector3, yaw: float, colr := Color(0.75, 0.25, 0.25)) -> void:
	# 几帳（台＋柱＋横木に帷子を垂らす）
	box("darkwood", p + Vector3(0, 0.04, 0), Vector3(0.9, 0.08, 0.25), Color(0.3, 0.2, 0.15), yaw)
	var bs := Basis(Vector3.UP, yaw)
	for sgn in [-1.0, 1.0]:
		rod("darkwood", p + bs * Vector3(sgn * 0.4, 0, 0), p + bs * Vector3(sgn * 0.4, 1.5, 0), 0.02, Color(0.3, 0.2, 0.15))
	rod("darkwood", p + bs * Vector3(-0.5, 1.5, 0), p + bs * Vector3(0.5, 1.5, 0), 0.02, Color(0.3, 0.2, 0.15))
	for k in 4:
		var c := colr if k % 2 == 0 else colr.lightened(0.35)
		box("cloth", p + bs * Vector3(-0.36 + k * 0.24, 0.85, 0.02) + Vector3(0, 0, 0), Vector3(0.23, 1.3, 0.01), c, yaw)


## 置き畳（寝殿造: 板の間に必要な所だけ畳を置く。繧繝縁は貴人の座）
func oki_datami(p: Vector3, yaw: float, ungen := false) -> void:
	box("tatami", p + Vector3(0, 0.05, 0), Vector3(0.95, 0.1, 1.9), Color(0.86, 0.84, 0.6), yaw)
	var bs := Basis(Vector3.UP, yaw)
	for sgn in [-1.0, 1.0]:
		var c := p + bs * Vector3(sgn * 0.45, 0.101, 0)
		box("cloth", c, Vector3(0.06, 0.008, 1.9), Color(0.85, 0.2, 0.25) if ungen else Color(0.12, 0.12, 0.12), yaw)
		if ungen:
			box("cloth", c + bs * Vector3(0, 0.002, 0.0), Vector3(0.02, 0.008, 1.9), Color(0.2, 0.55, 0.3), yaw)


func kyosoku(p: Vector3, yaw: float) -> void:
	# 脇息
	box("darkwood", p + Vector3(0, 0.3, 0), Vector3(0.5, 0.06, 0.14), Color(0.25, 0.12, 0.1), yaw)
	for sgn in [-1.0, 1.0]:
		box("darkwood", p + Basis(Vector3.UP, yaw) * Vector3(sgn * 0.2, 0.15, 0), Vector3(0.05, 0.3, 0.1), Color(0.25, 0.12, 0.1), yaw)


func kakejiku(p: Vector3, n: Vector3, colr := Color(0.92, 0.88, 0.78), art := Color(0.3, 0.3, 0.35)) -> void:
	var yaw := atan2(n.x, n.z)
	box("cloth", p, Vector3(0.55, 1.4, 0.01), Color(0.4, 0.45, 0.4), yaw)
	box("flat", p + n * 0.006, Vector3(0.42, 1.0, 0.01), colr, yaw)
	box("flat", p + n * 0.01 + Vector3(0, 0.1, 0), Vector3(0.1, 0.5, 0.005), art, yaw)
	box("darkwood", p + Vector3(0, -0.72, 0) + n * 0.01, Vector3(0.62, 0.04, 0.04), Color(0.2, 0.15, 0.1), yaw)


## 床の間（床框・落掛・掛軸・花入）＋違い棚（＋付書院）。side の壁の中央付近 u（壁の始点からの距離）
func tokonoma(i: int, side: int, u: float, width := 1.8, shoin := true, tana := true) -> void:
	var sl := side_line(i, side)
	var a: Vector3 = sl[0]
	var d: Vector3 = sl[1]
	var n: Vector3 = sl[2]
	var dn := d.normalized()
	var yaw := atan2(dn.x, dn.z) - PI * 0.5
	var c := a + dn * u + n * 0.45
	var y := fy(i)
	# 床框と床板
	box("darkwood", Vector3(c.x, y + 0.08, c.z), Vector3(width, 0.16, 0.9), Color(0.3, 0.2, 0.15), yaw, true)
	box("wood", Vector3(c.x, y + 0.165, c.z), Vector3(width - 0.04, 0.01, 0.86), Color(0.8, 0.66, 0.5), yaw)
	# 落掛（上の横木）と床柱
	box("darkwood", Vector3(c.x, y + 1.95, c.z) + n * 0.4, Vector3(width, 0.1, 0.08), Color(0.25, 0.18, 0.14), yaw)
	cyl("darkwood", a + dn * (u + width * 0.5) + n * 0.85 + Vector3(0, 0, 0), 0.07, 0.07, 2.3, 8, Color(0.55, 0.4, 0.28))
	kakejiku(Vector3(c.x, y + 1.15, c.z) - n * 0.4, n)
	# 花入
	cyl("earth", Vector3(c.x, y + 0.17, c.z) + dn * 0.4, 0.07, 0.05, 0.25, 8, Color(0.35, 0.3, 0.28))
	sph("flat", Vector3(c.x, y + 0.5, c.z) + dn * 0.4, 0.09, Color(0.85, 0.3, 0.35), 6, 4)
	rod("flat", Vector3(c.x, y + 0.4, c.z) + dn * 0.4, Vector3(c.x, y + 0.65, c.z) + dn * 0.3, 0.012, Color(0.25, 0.4, 0.2), 3)
	if tana:
		# 違い棚（床脇）
		var t := a + dn * (u + width * 0.5 + 0.55) + n * 0.4
		box("wood", Vector3(t.x, y + 0.1, t.z), Vector3(0.9, 0.2, 0.8), Color(0.75, 0.6, 0.45), yaw)
		box("wood", Vector3(t.x, y + 0.85, t.z) + dn * -0.18, Vector3(0.5, 0.04, 0.4), Color(0.6, 0.45, 0.32), yaw)
		box("wood", Vector3(t.x, y + 1.0, t.z) + dn * 0.18, Vector3(0.5, 0.04, 0.4), Color(0.6, 0.45, 0.32), yaw)
		box("darkwood", Vector3(t.x, y + 1.7, t.z) - n * 0.15, Vector3(0.9, 0.4, 0.5), Color(0.3, 0.22, 0.16), yaw)
	if shoin:
		# 付書院（縁側へ張り出す机と明かり障子）
		var s := a + dn * (u - width * 0.5 - 0.5) + n * 0.25
		box("wood", Vector3(s.x, y + 0.42, s.z), Vector3(0.8, 0.06, 0.4), Color(0.75, 0.6, 0.45), yaw)
		box("flat", Vector3(s.x, y + 0.95, s.z) - n * 0.18, Vector3(0.8, 0.9, 0.02), Color(0.97, 0.96, 0.9), yaw)


func irori(p: Vector3, s := 1.0) -> void:
	# 囲炉裏（炉縁＋灰＋五徳＋自在鉤の鍋）
	for sgn in [-1.0, 1.0]:
		box("darkwood", p + Vector3(0, 0.03, sgn * 0.45 * s), Vector3(1.0 * s, 0.08, 0.1), Color(0.3, 0.2, 0.14))
		box("darkwood", p + Vector3(sgn * 0.45 * s, 0.03, 0), Vector3(0.1, 0.08, 1.0 * s), Color(0.3, 0.2, 0.14))
	box("earth", p + Vector3(0, 0.0, 0), Vector3(0.8 * s, 0.04, 0.8 * s), Color(0.6, 0.58, 0.55))
	sph("emissive", p + Vector3(0, 0.04, 0), 0.12, Color(1.0, 0.4, 0.12), 6, 3, Vector3(1.6, 0.5, 1.6))
	for k in 3:
		var a := TAU * k / 3.0
		rod("darkwood", p + Vector3(cos(a) * 0.15, 0.03, sin(a) * 0.15), p + Vector3(-cos(a) * 0.1, 0.12, -sin(a) * 0.1), 0.025, Color(0.2, 0.12, 0.08), 3)
	rod("bamboo", p + Vector3(0, 2.2, 0), p + Vector3(0, 0.6, 0), 0.025, Color(0.5, 0.4, 0.25), 4)
	box("darkwood", p + Vector3(0, 0.9, 0), Vector3(0.3, 0.06, 0.06), Color(0.25, 0.15, 0.1))
	cyl("metal", p + Vector3(0, 0.35, 0), 0.18, 0.2, 0.22, 10, Color(0.18, 0.17, 0.17))
	fire_pts.append(p + Vector3(0, 0.2, 0))
	lamp("hearth", p)


func kamado(p: Vector3, yaw: float, n := 2) -> void:
	# 竈（へっつい・おくどさん）: 漆喰の台に釜
	var bs := Basis(Vector3.UP, yaw)
	box("plaster", p + Vector3(0, 0.35, 0), Vector3(0.9 * n, 0.7, 0.8), Color(0.82, 0.78, 0.72), yaw, true)
	for k in n:
		var c := p + bs * Vector3((k - (n - 1) * 0.5) * 0.85, 0.7, 0)
		cyl("metal", c, 0.3, 0.26, 0.2, 10, Color(0.2, 0.18, 0.17))
		box("darkwood", c + Vector3(0, 0.22, 0), Vector3(0.5, 0.04, 0.5), Color(0.5, 0.38, 0.28))
		box("flat", c + bs * Vector3(0, -0.45, 0.4), Vector3(0.3, 0.25, 0.02), Color(0.08, 0.06, 0.05), yaw)
		sph("emissive", c + bs * Vector3(0, -0.5, 0.38), 0.06, Color(1.0, 0.42, 0.12), 5, 3, Vector3(1.6, 0.8, 0.4))
	fire_pts.append(p + Vector3(0, 0.5, 0))


func mizugame(p: Vector3) -> void:
	cyl("earth", p, 0.22, 0.3, 0.55, 10, Color(0.42, 0.32, 0.25), true)
	cyl("wood", p + Vector3(0, 0.55, 0), 0.3, 0.3, 0.03, 10, Color(0.7, 0.58, 0.42))
	rod("bamboo", p + Vector3(0, 0.6, 0), p + Vector3(0.3, 0.7, 0.1), 0.02, Color(0.6, 0.5, 0.3), 3)


func tansu(p: Vector3, yaw: float, w := 0.9, h := 1.0, colr := Color(0.55, 0.36, 0.22)) -> void:
	box("wood", p + Vector3(0, h * 0.5, 0), Vector3(w, h, 0.45), colr, yaw, true)
	var bs := Basis(Vector3.UP, yaw)
	var rows := maxi(2, int(h / 0.25))
	for k in rows:
		var c := p + Vector3(0, h * (k + 0.5) / rows, 0) + bs * Vector3(0, 0, 0.23)
		box("darkwood", c, Vector3(w - 0.06, 0.02, 0.01), Color(0.25, 0.16, 0.1), yaw)
		box("metal", c + Vector3(0, 0.06, 0) + bs * Vector3(0, 0, 0.01), Vector3(0.12, 0.03, 0.02), Color(0.2, 0.18, 0.15), yaw)


func komedawara(p: Vector3, yaw := 0.0) -> void:
	# 米俵（横置き）
	var t := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5), p + Vector3(0, 0.25, 0) + Basis(Vector3.UP, yaw) * Vector3(0.4, 0, 0))
	cylt("thatch", t, 0.25, 0.25, 0.8, 10, Color(0.9, 0.8, 0.55))
	for k in 3:
		var tk := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5), p + Vector3(0, 0.25, 0) + Basis(Vector3.UP, yaw) * Vector3(0.38 - (k + 1) * 0.2, 0, 0))
		cylt("thatch", tk, 0.265, 0.265, 0.04, 10, Color(0.7, 0.58, 0.36))


func senryobako(p: Vector3, yaw := 0.0) -> void:
	# 千両箱（樫の箱に鉄の帯）
	box("wood", p + Vector3(0, 0.08, 0), Vector3(0.45, 0.16, 0.15), Color(0.5, 0.32, 0.2), yaw)
	for sgn in [-1.0, 1.0]:
		box("metal", p + Vector3(0, 0.08, 0) + Basis(Vector3.UP, yaw) * Vector3(sgn * 0.17, 0, 0), Vector3(0.03, 0.17, 0.16), Color(0.25, 0.23, 0.2), yaw)


func tsubo(p: Vector3, s := 1.0, colr := Color(0.55, 0.4, 0.3)) -> void:
	cyl("earth", p, 0.12 * s, 0.2 * s, 0.25 * s, 8, colr)
	cyl("earth", p + Vector3(0, 0.25 * s, 0), 0.2 * s, 0.1 * s, 0.2 * s, 8, colr)
	cyl("earth", p + Vector3(0, 0.45 * s, 0), 0.1 * s, 0.12 * s, 0.06 * s, 8, colr)


## 棚（levels 段）。items: callable(p 段の上の点, yaw)
func shelf(p: Vector3, yaw: float, w: float, h: float, d: float, levels: int, colr := Color(0.6, 0.45, 0.32), items := Callable()) -> void:
	var bs := Basis(Vector3.UP, yaw)
	col_box(p + Vector3(0, h * 0.5, 0), Vector3(w, h, d), yaw)
	for sgn in [-1.0, 1.0]:
		box("wood", p + bs * Vector3(sgn * w * 0.5, 0, 0) + Vector3(0, h * 0.5, 0), Vector3(0.05, h, d), colr, yaw)
	for k in levels:
		var y := 0.05 + (h - 0.1) * k / maxf(levels - 1, 1)
		box("wood", p + Vector3(0, y, 0), Vector3(w, 0.04, d), colr, yaw)
		if items.is_valid() and k < levels - 1:
			var nn := maxi(1, int(w / 0.5))
			for j in nn:
				items.call(p + Vector3(0, y + 0.02, 0) + bs * Vector3(-w * 0.5 + w * (j + 0.5) / nn, 0, 0), yaw)


func kamidana(p: Vector3, n: Vector3) -> void:
	# 神棚（宮形・榊・注連縄）
	var yaw := atan2(n.x, n.z)
	box("wood", p, Vector3(1.0, 0.04, 0.35), Color(0.88, 0.78, 0.6), yaw)
	box("wood", p + Vector3(0, 0.2, 0), Vector3(0.4, 0.36, 0.22), Color(0.9, 0.82, 0.66), yaw)
	box("thatch", p + Vector3(0, 0.42, 0), Vector3(0.5, 0.08, 0.3), Color(0.5, 0.42, 0.32), yaw)
	for sgn in [-1.0, 1.0]:
		cyl("earth", p + Basis(Vector3.UP, yaw) * Vector3(sgn * 0.35, 0.02, 0), 0.04, 0.05, 0.12, 6, Color(0.95, 0.95, 0.95))
		sph("flat", p + Basis(Vector3.UP, yaw) * Vector3(sgn * 0.35, 0.2, 0), 0.07, Color(0.2, 0.42, 0.22), 6, 4)
	box("thatch", p + Vector3(0, -0.05, 0) + n * 0.18, Vector3(1.0, 0.04, 0.04), Color(0.9, 0.82, 0.55), yaw)


# ================================================================ 洋の調度
func table(p: Vector3, w: float, d: float, h := 0.72, colr := Color(0.5, 0.32, 0.2), yaw := 0.0, cloth := Color(0, 0, 0, 0)) -> void:
	var bs := Basis(Vector3.UP, yaw)
	box("wood", p + Vector3(0, h - 0.02, 0), Vector3(w, 0.04, d), colr, yaw, true)
	if cloth.a > 0.0:
		box("cloth", p + Vector3(0, h + 0.002, 0), Vector3(w + 0.1, 0.01, d + 0.1), cloth, yaw)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			box("wood", p + bs * Vector3(cx * (w * 0.5 - 0.06), 0, cz * (d * 0.5 - 0.06)) + Vector3(0, (h - 0.04) * 0.5, 0), Vector3(0.05, h - 0.04, 0.05), colr.darkened(0.2), yaw)


func chair(p: Vector3, yaw: float, colr := Color(0.45, 0.28, 0.18), seat := Color(0.55, 0.15, 0.15)) -> void:
	var bs := Basis(Vector3.UP, yaw)
	box("cloth", p + Vector3(0, 0.45, 0), Vector3(0.45, 0.06, 0.45), seat, yaw)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			box("wood", p + bs * Vector3(cx * 0.19, 0.22, cz * 0.19), Vector3(0.04, 0.44, 0.04), colr, yaw)
	box("wood", p + bs * Vector3(0, 0.75, -0.21), Vector3(0.42, 0.55, 0.04), colr, yaw)


func sofa(p: Vector3, yaw: float, w := 1.8, colr := Color(0.55, 0.15, 0.18)) -> void:
	var bs := Basis(Vector3.UP, yaw)
	box("cloth", p + Vector3(0, 0.25, 0), Vector3(w, 0.4, 0.8), colr, yaw, true)
	box("cloth", p + bs * Vector3(0, 0.6, -0.32) , Vector3(w, 0.6, 0.18), colr.darkened(0.1), yaw)
	for sgn in [-1.0, 1.0]:
		box("cloth", p + bs * Vector3(sgn * (w * 0.5 - 0.08), 0.5, 0), Vector3(0.16, 0.3, 0.8), colr.darkened(0.15), yaw)


func fireplace(p: Vector3, n: Vector3) -> void:
	# 暖炉（大理石のマントルピース・炉の火・鏡）
	var yaw := atan2(n.x, n.z)
	var bs := Basis(Vector3.UP, yaw)
	box("stonewall", p + Vector3(0, 0.6, 0) + n * 0.15, Vector3(1.6, 1.2, 0.3), Color(0.92, 0.9, 0.86), yaw, true)
	box("stonewall", p + Vector3(0, 1.24, 0) + n * 0.22, Vector3(1.8, 0.08, 0.45), Color(0.95, 0.93, 0.9), yaw)
	box("flat", p + Vector3(0, 0.42, 0) + n * 0.31, Vector3(0.9, 0.75, 0.02), Color(0.08, 0.06, 0.05), yaw)
	sph("emissive", p + Vector3(0, 0.18, 0) + n * 0.25, 0.16, Color(1.0, 0.45, 0.15), 6, 4, Vector3(2.2, 1.0, 0.8))
	box("glass", p + Vector3(0, 1.85, 0) + n * 0.04, Vector3(1.1, 0.9, 0.02), Color(0.85, 0.9, 0.95), yaw)
	box("gold", p + Vector3(0, 1.85, 0) + n * 0.03, Vector3(1.22, 1.02, 0.02), Color(1, 0.82, 0.45), yaw)
	for sgn in [-1.0, 1.0]:
		cyl("gold", p + Vector3(0, 1.28, 0) + bs * Vector3(sgn * 0.6, 0, 0.25), 0.05, 0.03, 0.25, 6, Color(1, 0.82, 0.45))
	fire_pts.append(p + n * 0.3 + Vector3(0, 0.2, 0))
	light(p + n * 0.8 + Vector3(0, 0.5, 0), Color(1.0, 0.55, 0.25), 0.7, 5.0)


func clock(p: Vector3, n: Vector3, standing := false) -> void:
	var yaw := atan2(n.x, n.z)
	if standing:
		box("wood", p + Vector3(0, 0.95, 0), Vector3(0.5, 1.9, 0.3), Color(0.4, 0.24, 0.14), yaw, true)
		cylt("flat", Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 1.6, 0) + n * 0.16), 0.17, 0.17, 0.02, 14, Color(0.95, 0.93, 0.85))
	else:
		box("wood", p, Vector3(0.36, 0.7, 0.12), Color(0.4, 0.24, 0.14), yaw)
		cylt("flat", Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0.12, 0) + n * 0.06), 0.14, 0.14, 0.02, 12, Color(0.95, 0.93, 0.85))
		box("metal", p + Vector3(0, -0.2, 0) + n * 0.06, Vector3(0.04, 0.2, 0.01), Color(0.8, 0.65, 0.3), yaw)


func frame_pic(p: Vector3, n: Vector3, w := 0.6, h := 0.8, art := Color(0.35, 0.4, 0.5)) -> void:
	var yaw := atan2(n.x, n.z)
	box("gold", p, Vector3(w + 0.1, h + 0.1, 0.03), Color(0.9, 0.72, 0.35), yaw)
	box("flat", p + n * 0.018, Vector3(w, h, 0.01), art, yaw)
	box("flat", p + n * 0.024 + Vector3(0, h * 0.1, 0), Vector3(w * 0.35, h * 0.45, 0.005), art.lightened(0.35), yaw)


func bookshelf(p: Vector3, yaw: float, w := 1.2, h := 2.0) -> void:
	shelf(p, yaw, w, h, 0.35, 5, Color(0.42, 0.26, 0.16), func(q: Vector3, y2: float) -> void:
		var bs2 := Basis(Vector3.UP, y2)
		for k in 6:
			var hh := vrng.randf_range(0.22, 0.3)
			var cc: Color = [Color(0.5, 0.15, 0.12), Color(0.15, 0.25, 0.45), Color(0.2, 0.35, 0.2), Color(0.55, 0.45, 0.3)][k % 4]
			box("flat", q + bs2 * Vector3(-0.2 + k * 0.075, hh * 0.5, 0), Vector3(0.06, hh, 0.25), cc, y2))


func desk(p: Vector3, yaw: float, w := 1.3, colr := Color(0.45, 0.28, 0.18)) -> void:
	var bs := Basis(Vector3.UP, yaw)
	box("wood", p + Vector3(0, 0.74, 0), Vector3(w, 0.05, 0.7), colr, yaw, true)
	for sgn in [-1.0, 1.0]:
		box("wood", p + bs * Vector3(sgn * (w * 0.5 - 0.2), 0.36, 0), Vector3(0.38, 0.72, 0.66), colr.darkened(0.1), yaw)
	box("flat", p + Vector3(0, 0.77, 0) + bs * Vector3(0.15, 0, 0.05), Vector3(0.3, 0.01, 0.22), Color(0.95, 0.94, 0.9), yaw + 0.1)


func rug(r: Rect2, y: float, colr: Color, border := Color(0.8, 0.65, 0.35)) -> void:
	hrect("cloth", r, y + 0.02, border, true)
	hrect("cloth", r.grow(-0.15), y + 0.025, colr, true)


# ================================================================ 昭和の生活
func chabudai(p: Vector3) -> void:
	cyl("wood", p + Vector3(0, 0.3, 0), 0.45, 0.45, 0.04, 16, Color(0.55, 0.32, 0.18), true)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		box("wood", p + Vector3(cos(a) * 0.3, 0.15, sin(a) * 0.3), Vector3(0.04, 0.3, 0.04), Color(0.4, 0.24, 0.14))
	cyl("earth", p + Vector3(0.12, 0.34, 0.05), 0.06, 0.05, 0.07, 8, Color(0.92, 0.9, 0.85))
	cyl("earth", p + Vector3(-0.15, 0.34, -0.1), 0.08, 0.06, 0.05, 8, Color(0.3, 0.45, 0.6))


func radio(p: Vector3, yaw: float) -> void:
	# 真空管ラジオ（木のキャビネット・布張りのスピーカー・ダイヤル）
	var bs := Basis(Vector3.UP, yaw)
	box("wood", p + Vector3(0, 0.17, 0), Vector3(0.45, 0.34, 0.24), Color(0.45, 0.26, 0.14), yaw)
	box("cloth", p + Vector3(0, 0.21, 0) + bs * Vector3(-0.07, 0, 0.121), Vector3(0.22, 0.2, 0.01), Color(0.75, 0.68, 0.5), yaw)
	cylt("flat", Transform3D(bs * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0.12, 0) + bs * Vector3(0.14, 0, 0.13)), 0.035, 0.035, 0.02, 8, Color(0.9, 0.88, 0.8))
	box("emissive", p + Vector3(0, 0.27, 0) + bs * Vector3(0.14, 0, 0.122), Vector3(0.12, 0.04, 0.01), Color(1.0, 0.8, 0.4), yaw)


func tv(p: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	for cx in [-1.0, 1.0]:
		box("wood", p + bs * Vector3(cx * 0.22, 0.2, 0), Vector3(0.03, 0.4, 0.03), Color(0.3, 0.2, 0.12), yaw)
	box("wood", p + Vector3(0, 0.65, 0), Vector3(0.6, 0.5, 0.45), Color(0.4, 0.25, 0.14), yaw, true)
	box("glass", p + Vector3(0, 0.67, 0) + bs * Vector3(-0.06, 0, 0.226), Vector3(0.38, 0.32, 0.01), Color(0.35, 0.42, 0.45), yaw)
	box("cloth", p + Vector3(0, 0.97, 0), Vector3(0.62, 0.02, 0.47), Color(0.85, 0.3, 0.3), yaw)


func futon_pile(p: Vector3, yaw: float) -> void:
	for k in 3:
		box("cloth", p + Vector3(0, 0.08 + k * 0.15, 0), Vector3(1.0, 0.14, 0.7), [Color(0.85, 0.82, 0.75), Color(0.6, 0.3, 0.35), Color(0.3, 0.4, 0.6)][k], yaw)


func crate(p: Vector3, s := 0.8, yaw := 0.0, colr := Color(0.72, 0.56, 0.38)) -> void:
	box("wood", p + Vector3(0, s * 0.5, 0), Vector3(s, s, s), colr, yaw, true)
	box("darkwood", p + Vector3(0, s * 0.5, 0), Vector3(s + 0.02, 0.06, s + 0.02), colr.darkened(0.3), yaw)


func sack(p: Vector3, colr := Color(0.82, 0.74, 0.58)) -> void:
	sph("cloth", p + Vector3(0, 0.22, 0), 0.32, colr, 8, 5, Vector3(1.0, 0.7, 0.75))


func barrel(p: Vector3, colr := Color(0.6, 0.42, 0.28)) -> void:
	cyl("wood", p, 0.3, 0.33, 0.85, 10, colr, true)
	for k in 2:
		cyl("metal", p + Vector3(0, 0.15 + k * 0.5, 0), 0.335, 0.335, 0.05, 10, Color(0.25, 0.25, 0.25))


# ================================================================ 間仕切り・上がり框
## 間仕切りの壁（局所 xz の a→b、床 y から高さ h）。gaps: [[t0, t1, gh]]（a からの距離・開口の高さ）
func partition(a: Vector2, b: Vector2, y: float, h: float, mat := "plaster", colr := Color(0.92, 0.9, 0.84), gaps := [], th := 0.1, collide := true) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.05:
		return
	var dn := d / L
	var yaw := atan2(dn.x, dn.y) - PI * 0.5
	var cur := 0.0
	var pieces: Array = []
	for g in gaps:
		pieces.append([cur, float(g[0]), 0.0])
		pieces.append([float(g[0]), float(g[1]), float(g[2])])
		cur = float(g[1])
	pieces.append([cur, L, 0.0])
	for pc in pieces:
		var t0: float = pc[0]
		var t1: float = pc[1]
		var gh: float = pc[2]
		if t1 - t0 < 0.02:
			continue
		var m := a + dn * (t0 + t1) * 0.5
		var y0 := y + gh
		if h - gh < 0.02:
			continue
		box(mat, Vector3(m.x, (y0 + y + h) * 0.5, m.y), Vector3(t1 - t0, y + h - y0, th), colr, yaw, collide and gh < 0.01, gh > 0.01)
		if gh > 0.01 and collide:
			col_box(Vector3(m.x, (y0 + y + h) * 0.5, m.y), Vector3(t1 - t0, y + h - y0, th), yaw)


## 上がり框のある床（土間から y_top まで上げる）。steps: 上がり口 [Vector3 縁の点, Vector3 土間側への向き]
func platform(r: Rect2, y0: float, y_top: float, style := "boards", colr := Color.WHITE, steps_at := [], hole := Rect2()) -> void:
	var hgt := y_top - y0
	col_box(Vector3(r.get_center().x, y0 + hgt * 0.5, r.get_center().y), Vector3(r.size.x, hgt, r.size.y))
	box("darkwood", Vector3(r.get_center().x, y0 + hgt * 0.5 - 0.01, r.get_center().y), Vector3(r.size.x, hgt - 0.02, r.size.y), Color(0.32, 0.24, 0.18))
	finish(r, y_top - 0.012, style, colr, hole)
	for st in steps_at:
		var p: Vector3 = st[0]
		var dirv: Vector3 = st[1]
		# 沓脱石＋坂の当たり判定
		box("stonewall", Vector3(p.x, y0 + hgt * 0.3, p.z) + dirv * 0.35, Vector3(0.7, hgt * 0.6, 0.45), Color(0.62, 0.6, 0.56), atan2(dirv.x, dirv.z))
		ramp(Vector3(p.x, y0 - 0.02, p.z) + dirv * 0.8, Vector3(p.x, y_top, p.z) - dirv * 0.1, 0.9)

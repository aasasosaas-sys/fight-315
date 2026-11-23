class_name ShipKit
extends RefCounted
## 船の手続きジオメトリ用ヘルパ。MeshKit（材質ごとに 1 メッシュ）＋箱コリジョン（船ローカル）。
## 床は穴（階段口）を抜き、壁は開口（扉）を抜く。階段は段の見た目＋斜面のコリジョン。

var kit := MeshKit.new()
var cols: Array = []            # [Transform3D, Vector3]（箱の中心と大きさ、船ローカル）
var faces := PackedVector3Array()  # 凹形状のコリジョン（船体外板）


func box(mat: String, c: Vector3, size: Vector3, colr: Color, collide := false, basis := Basis()) -> void:
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		return
	var xf := Transform3D(basis, c)
	kit.box(mat, xf, size, colr, false)
	if collide:
		cols.append([xf, size])


func col_box(c: Vector3, size: Vector3, basis := Basis()) -> void:
	cols.append([Transform3D(basis, c), size])


func cyl(mat: String, base: Vector3, r0: float, r1: float, h: float, segs: int, colr: Color, basis := Basis()) -> void:
	kit.cylinder(mat, Transform3D(basis, base), r0, r1, h, segs, colr)


func rod(mat: String, a: Vector3, b: Vector3, r: float, colr: Color, segs := 6) -> void:
	kit.rod(mat, a, b, r, segs, colr)


func quad(mat: String, a: Vector3, b: Vector3, cc: Vector3, d: Vector3, colr: Color, n_hint := Vector3.ZERO) -> void:
	var ua := Vector2(a.z + a.x, -a.y)
	var ub := Vector2(b.z + b.x, -b.y)
	var uc := Vector2(cc.z + cc.x, -cc.y)
	var ud := Vector2(d.z + d.x, -d.y)
	if absf((b - a).cross(d - a).normalized().y) > 0.7:
		ua = Vector2(a.x, a.z); ub = Vector2(b.x, b.z); uc = Vector2(cc.x, cc.z); ud = Vector2(d.x, d.z)
	kit.tri(mat, a, b, cc, ua, ub, uc, colr, n_hint)
	kit.tri(mat, a, cc, d, ua, uc, ud, colr, n_hint)


## 楕円柱（rx: 横, rz: 前後）。basis で傾ける
func ellipse(mat: String, base: Vector3, rx: float, rz: float, h: float, segs: int, colr: Color, basis := Basis(), cap := true) -> void:
	var up := basis.y.normalized()
	var ax := basis.x.normalized()
	var az := basis.z.normalized()
	var top := base + up * h
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var d0 := ax * cos(a0) * rx + az * sin(a0) * rz
		var d1 := ax * cos(a1) * rx + az * sin(a1) * rz
		quad(mat, base + d0, base + d1, top + d1, top + d0, colr, (d0 + d1).normalized())
		if cap:
			kit.tri(mat, top, top + d0, top + d1, Vector2.ZERO, Vector2(d0.x, d0.z), Vector2(d1.x, d1.z), colr, up)


## 床（矩形から穴を抜く）。y は床の上面。holes: [{z0,z1,x0,x1}]
func floor_rect(mat: String, y: float, z0: float, z1: float, x0: float, x1: float, holes: Array, colr: Color, th := 0.2, collide := true) -> void:
	var zs: Array = [z0, z1]
	var hs: Array = []
	for h in holes:
		var hd: Dictionary = h
		if float(hd["z1"]) <= z0 or float(hd["z0"]) >= z1 or float(hd["x1"]) <= x0 or float(hd["x0"]) >= x1:
			continue
		hs.append(hd)
		zs.append(clampf(float(hd["z0"]), z0, z1))
		zs.append(clampf(float(hd["z1"]), z0, z1))
	zs.sort()
	for k in zs.size() - 1:
		var za: float = zs[k]
		var zb: float = zs[k + 1]
		if zb - za < 0.02:
			continue
		var zm := (za + zb) * 0.5
		var xs: Array = [[x0, x1]]
		for hd in hs:
			if zm <= float(hd["z0"]) or zm >= float(hd["z1"]):
				continue
			var nxt: Array = []
			for seg in xs:
				var sa: float = seg[0]
				var sb: float = seg[1]
				var ha := float(hd["x0"])
				var hb := float(hd["x1"])
				if hb <= sa or ha >= sb:
					nxt.append(seg)
					continue
				if ha > sa:
					nxt.append([sa, ha])
				if hb < sb:
					nxt.append([hb, sb])
			xs = nxt
		for seg in xs:
			var xa: float = seg[0]
			var xb: float = seg[1]
			if xb - xa < 0.02:
				continue
			box(mat, Vector3((xa + xb) * 0.5, y - th * 0.5, zm), Vector3(xb - xa, th, zb - za), colr, collide)


## 船体形の床（甲板）。hb_fn(z) -> 半幅、y_fn(z) -> 上面の高さ。斜面はコリジョンを傾ける
func floor_hull(mat: String, z0: float, z1: float, hb_fn: Callable, y_fn: Callable, holes: Array, colr: Color, step := 2.0, th := 0.2, collide := true, inset := 0.05) -> void:
	var zs: Array = []
	var n := maxi(1, ceili((z1 - z0) / step))
	for i in n + 1:
		zs.append(lerpf(z0, z1, float(i) / n))
	for h in holes:
		var hd: Dictionary = h
		for zz: float in [float(hd["z0"]), float(hd["z1"])]:
			if zz > z0 and zz < z1:
				zs.append(zz)
	zs.sort()
	for k in zs.size() - 1:
		var za: float = zs[k]
		var zb: float = zs[k + 1]
		if zb - za < 0.03:
			continue
		var zm := (za + zb) * 0.5
		var hw := minf(float(hb_fn.call(za)), float(hb_fn.call(zb))) - inset
		var hwm := float(hb_fn.call(zm)) - inset
		hw = minf(hw, hwm)
		if hw < 0.15:
			continue
		var ya := float(y_fn.call(za))
		var yb := float(y_fn.call(zb))
		var xs: Array = [[-hw, hw]]
		for h in holes:
			var hd: Dictionary = h
			if zm <= float(hd["z0"]) or zm >= float(hd["z1"]):
				continue
			var nxt: Array = []
			for seg in xs:
				var sa: float = seg[0]
				var sb: float = seg[1]
				var ha := float(hd["x0"])
				var hb := float(hd["x1"])
				if hb <= sa or ha >= sb:
					nxt.append(seg)
					continue
				if ha > sa:
					nxt.append([sa, ha])
				if hb < sb:
					nxt.append([hb, sb])
			xs = nxt
		var ang := atan2(ya - yb, zb - za)
		var bs := Basis(Vector3.RIGHT, ang)
		var ln := Vector2(zb - za, yb - ya).length()
		for seg in xs:
			var xa: float = seg[0]
			var xb: float = seg[1]
			if xb - xa < 0.03:
				continue
			# 見た目は斜めの上面（隣と連続）＋厚み
			var p0 := Vector3(xa, ya, za)
			var p1 := Vector3(xb, ya, za)
			var p2 := Vector3(xb, yb, zb)
			var p3 := Vector3(xa, yb, zb)
			quad(mat, p0, p1, p2, p3, colr, Vector3.UP)
			quad(mat, p0 + Vector3.DOWN * th, p3 + Vector3.DOWN * th, p2 + Vector3.DOWN * th, p1 + Vector3.DOWN * th, colr.darkened(0.15), Vector3.DOWN)
			if collide:
				cols.append([Transform3D(bs, Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 - th * 0.5, zm)), Vector3(xb - xa, th, ln)])


## 壁。a, b は (x, z)。openings: [[u0, u1, top]]（a からの距離、上端の高さ。下端は床）
func wall(mat: String, a: Vector2, b: Vector2, y0: float, h: float, colr: Color, openings: Array = [], th := 0.12, collide := true) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.05:
		return
	var dir := d / ln
	var ang := atan2(dir.x, dir.y)
	var bs := Basis(Vector3.UP, ang)
	var cuts: Array = [0.0, ln]
	for op in openings:
		var oa: Array = op
		cuts.append(clampf(float(oa[0]), 0.0, ln))
		cuts.append(clampf(float(oa[1]), 0.0, ln))
	cuts.sort()
	for k in cuts.size() - 1:
		var u0: float = cuts[k]
		var u1: float = cuts[k + 1]
		if u1 - u0 < 0.02:
			continue
		var um := (u0 + u1) * 0.5
		var gap_top := -1.0
		for op in openings:
			var oa: Array = op
			if um > float(oa[0]) and um < float(oa[1]):
				gap_top = float(oa[2])
		var p := a + dir * um
		if gap_top < 0.0:
			box(mat, Vector3(p.x, y0 + h * 0.5, p.y), Vector3(th, h, u1 - u0), colr, collide, bs)
		elif gap_top < h - 0.05:
			box(mat, Vector3(p.x, y0 + (gap_top + h) * 0.5, p.y), Vector3(th, h - gap_top, u1 - u0), colr, collide, bs)


## 矩形の部屋の四面の壁（扉: door = {side: "x0"/"x1"/"z0"/"z1", u: 辺上の中心, w}）
func room_walls(mat: String, z0: float, z1: float, x0: float, x1: float, y0: float, h: float, colr: Color, doors: Array, th := 0.12, collide := true, skip_sides: Array = []) -> void:
	var sides := {"z0": [Vector2(x0, z0), Vector2(x1, z0)], "z1": [Vector2(x1, z1), Vector2(x0, z1)],
		"x0": [Vector2(x0, z1), Vector2(x0, z0)], "x1": [Vector2(x1, z0), Vector2(x1, z1)]}
	for sk in sides:
		if sk in skip_sides:
			continue
		var seg: Array = sides[sk]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ops: Array = []
		for dr in doors:
			var dd: Dictionary = dr
			if String(dd.get("side", "")) != sk:
				continue
			var w := float(dd.get("w", 1.0))
			var u := float(dd.get("u", 0.0))
			# u は辺の座標値（x か z）→ a からの距離に直す
			var dist := 0.0
			if sk == "z0":
				dist = u - x0
			elif sk == "z1":
				dist = x1 - u
			elif sk == "x0":
				dist = z1 - u
			else:
				dist = u - z0
			ops.append([dist - w * 0.5, dist + w * 0.5, float(dd.get("h", 2.05))])
		wall(mat, a, b, y0, h, colr, ops, th, collide)


## 手すり（柱＋横木）。solid なら腰壁
func rail(a: Vector3, b: Vector3, h: float, colr: Color, solid := false, collide := true, mat := "metal") -> void:
	var d := b - a
	var ln := Vector2(d.x, d.z).length()
	if ln < 0.1:
		return
	var ang := atan2(d.x, d.z)
	var bs := Basis(Vector3.UP, ang)
	var mid := (a + b) * 0.5
	if solid:
		box(mat, mid + Vector3(0, h * 0.5, 0), Vector3(0.1, h, ln), colr, false, bs)
	else:
		box(mat, mid + Vector3(0, h, 0), Vector3(0.06, 0.06, ln), colr, false, bs)
		box(mat, mid + Vector3(0, h * 0.5, 0), Vector3(0.04, 0.04, ln), colr, false, bs)
		var n := maxi(1, int(ln / 1.6))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			box(mat, p + Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.05), colr)
	if collide:
		cols.append([Transform3D(bs, mid + Vector3(0, h * 0.5 + 0.1, 0)), Vector3(0.12, h + 0.2, ln)])


## 矩形の縁の手すり（skip: 開ける辺 "z0"/"z1"/"x0"/"x1"）
func rail_rect(y: float, z0: float, z1: float, x0: float, x1: float, h: float, colr: Color, solid := false, skip: Array = [], gap: Dictionary = {}) -> void:
	var sides := {"z0": [Vector3(x0, y, z0), Vector3(x1, y, z0)], "z1": [Vector3(x0, y, z1), Vector3(x1, y, z1)],
		"x0": [Vector3(x0, y, z0), Vector3(x0, y, z1)], "x1": [Vector3(x1, y, z0), Vector3(x1, y, z1)]}
	for sk in sides:
		if sk in skip:
			continue
		var seg: Array = sides[sk]
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		if gap.has(sk):
			# 階段口の分だけ開ける: [u0, u1]（辺に沿った座標）
			var g: Array = gap[sk]
			var along_x: bool = sk == "z0" or sk == "z1"
			var g0 := float(g[0])
			var g1 := float(g[1])
			var pa := Vector3(g0, y, a.z) if along_x else Vector3(a.x, y, g0)
			var pb := Vector3(g1, y, a.z) if along_x else Vector3(a.x, y, g1)
			rail(a, pa, h, colr, solid)
			rail(pb, b, h, colr, solid)
		else:
			rail(a, b, h, colr, solid)


## 階段（ラッタル）。st: {y0, y1, z0, z1, x0, x1, dir, flights}
## dir = -1: 下端が z1 側、-z へ向かって登る（+1 はその逆）。flights > 1 は折り返し（x を 2 列に分け、端に踊り場）
func stair(mat: String, st: Dictionary, colr: Color, collide := true, rail_col := Color(0.3, 0.3, 0.32)) -> void:
	var y0 := float(st["y0"])
	var y1 := float(st["y1"])
	var z0 := float(st["z0"])
	var z1 := float(st["z1"])
	var x0 := float(st["x0"])
	var x1 := float(st["x1"])
	var fl := maxi(1, int(st.get("flights", 1)))
	var rise := (y1 - y0) / fl
	var land := 1.0 if fl > 1 else 0.0
	var land2 := 1.0 if fl >= 3 else 0.0
	var run := maxf((z1 - z0) - land - land2, 0.8)
	var lane_w := (x1 - x0) / (2.0 if fl > 1 else 1.0)
	var dirz := float(st.get("dir", -1))
	# 始点側（下端）と終点側の z
	var start_end := z1 - land2 if dirz < 0.0 else z0 + land2
	var far_end := start_end + dirz * run
	for f in fl:
		var lane := f % 2
		var xa := x0 + lane_w * lane
		var xb := xa + lane_w
		var ya := y0 + rise * f
		var yb := ya + rise
		var zstart := start_end if f % 2 == 0 else far_end
		var zend := far_end if f % 2 == 0 else start_end
		var up_dir := signf(zend - zstart)
		var nstep := maxi(2, ceili(rise / 0.22))
		for i in nstep:
			var t0 := float(i) / nstep
			var t1 := float(i + 1) / nstep
			var zz0 := lerpf(zstart, zend, t0)
			var zz1 := lerpf(zstart, zend, t1)
			var yy := lerpf(ya, yb, t1)
			box(mat, Vector3((xa + xb) * 0.5, yy - 0.06, (zz0 + zz1) * 0.5), Vector3(xb - xa - 0.08, 0.12, absf(zz1 - zz0) + 0.02), colr)
		for sx: float in [xa + 0.03, xb - 0.03]:
			var pa := Vector3(float(sx), ya, zstart)
			var pb := Vector3(float(sx), yb, zend)
			rod("metal", pa + Vector3(0, 0.9, 0), pb + Vector3(0, 0.9, 0), 0.03, rail_col, 4)
			rod("metal", pa, pb, 0.05, colr.darkened(0.3), 4)
		if collide:
			var ln := Vector2(run, rise).length()
			# 登る向きが -z なら x 軸まわりに正の回転で前が上がる
			var ang := atan2(rise, run) * (-up_dir)
			var bs := Basis(Vector3.RIGHT, ang)
			cols.append([Transform3D(bs, Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 - 0.12, (zstart + zend) * 0.5)), Vector3(xb - xa, 0.18, ln)])
		# 踊り場（次の階段がある時）
		if f < fl - 1:
			var lz := 0.0
			if f % 2 == 0:
				lz = far_end + dirz * land * 0.5
			else:
				lz = start_end - dirz * land2 * 0.5
			box(mat, Vector3((x0 + x1) * 0.5, yb - 0.08, lz), Vector3(x1 - x0, 0.16, land if f % 2 == 0 else land2), colr, collide)

class_name Architecture
extends RefCounted
## 時代建築のプレハブ群。すべて MeshKit にマテリアル別でまとめ、コリジョンは箱で近似する。
## 各関数の xf は「地面の高さの建物中心」、ローカル +Z が正面。

const VERMILION := Color(0.80, 0.25, 0.13)
const PLASTER := Color(0.96, 0.95, 0.91)
const OCHRE := Color(0.86, 0.72, 0.5)
const TILE := Color(0.62, 0.66, 0.72)
const TILE_DARK := Color(0.42, 0.45, 0.5)
const BARK := Color(0.62, 0.42, 0.32)
const THATCH := Color(0.98, 0.9, 0.72)
const WOOD := Color(1, 1, 1)
const DARK := Color(0.75, 0.7, 0.66)
const BLACK := Color(0.16, 0.15, 0.15)
const STONE := Color(0.92, 0.9, 0.86)
const GOLD := Color(1, 0.8, 0.4)
const COPPER := Color(0.45, 0.72, 0.62)

var w: EraWorld
var t: TerrainGen
var kit := MeshKit.new()
var cols: Array = []      # [Transform3D, Vector3]
var lamp_points: Array = []
var rng := RandomNumberGenerator.new()


func _init(world: EraWorld) -> void:
	w = world
	t = world.terrain
	rng.seed = world.rng.seed + 999


## glTF モデルを置く（無ければ false を返し、呼び出し側が代替を作る）
func model(id: String, xf: Transform3D, collide := Vector3.ZERO) -> bool:
	var parts := WorldModels.parts(id)
	if parts.is_empty():
		return false
	for e in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = e[0]
		mi.transform = xf * (e[1] as Transform3D)
		w.add_child(mi)
		if not _ustack.is_empty():
			_ustack.back()["models"].append(mi)
	if collide != Vector3.ZERO:
		cols.append([xf * Transform3D(Basis(), Vector3(0, collide.y * 0.5, 0)), collide])
	return true


func flush(name: String) -> void:
	if not kit.is_empty():
		var mi := kit.commit(name)
		w.add_child(mi)
	kit = MeshKit.new()
	cols.append_array(base_cols)
	base_cols.clear()
	for c in cols:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c[1]
		cs.shape = bs
		cs.transform = c[0]
		w.static_body.add_child(cs)
	cols.clear()


# ================================================================ 破壊ユニット
## 1 つの建物（や塀の 1 区画）をひとまとまりの「破壊ユニット」として記録する。
## ユニットのジオメトリは結合メッシュの中に残り（描画コール数は増えない）、UV2 に焼いた ID で
## シェーダが隠す/焦がす/切断する。コリジョンはユニット専用の StaticBody（Destructible）に移される。
var landmark := ""            # いま建てているランドマーク（layouts が設定）
var base_cols: Array = []     # 土台など、壊れない静的コリジョン
var _ustack: Array = []


func begin_unit(kind: String, xf := Transform3D.IDENTITY, opts := {}) -> void:
	w.next_unit_id += 1
	var id: int = w.next_unit_id
	var starts := {}
	for k in kit.surf:
		var sa: Array = kit.surf[k]
		starts[k] = [sa[0].size(), sa[4].size()]
	_ustack.append({"id": id, "kind": kind, "xf": xf, "landmark": landmark, "cols0": cols.size(), "starts": starts,
		"models": [], "base_top": -INF, "opts": opts})
	kit.set_unit(id)


func end_unit() -> void:
	if _ustack.is_empty():
		return
	var rec: Dictionary = _ustack.pop_back()
	kit.set_unit(int(_ustack.back()["id"]) if not _ustack.is_empty() else 0)
	var id: int = rec["id"]
	var ranges := {}
	var own := 0
	for k in kit.surf:
		var sa: Array = kit.surf[k]
		var st: Array = rec["starts"].get(k, [0, 0])
		var nv: int = sa[0].size()
		if nv <= int(st[0]):
			continue
		var u: PackedVector2Array = sa[5]
		var cnt := 0
		for i in range(int(st[0]), nv):
			if int(u[i].x) == id:
				cnt += 1
		if cnt == 0:
			continue
		own += cnt
		ranges[k] = [int(st[0]), nv, int(st[1]), (sa[4] as PackedInt32Array).size()]
	var c0: int = rec["cols0"]
	var shapes: Array = cols.slice(c0)
	cols.resize(c0)
	var models: Array = rec["models"]
	if own == 0 and models.is_empty():
		cols.append_array(shapes)   # 中身が無い（入れ子の子ユニットだけ）: 静的に戻す
		return
	w.unit_defs.append({"id": id, "kind": rec["kind"], "xf": rec["xf"], "landmark": rec["landmark"], "surf": kit.surf,
		"ranges": ranges, "shapes": shapes, "models": models, "base_top": rec["base_top"], "opts": rec["opts"], "verts": own})


## 長い塀を 7m 以内の区画に分ける
func _split_seg(a: Vector3, b: Vector3, max_len := 7.0) -> Array:
	var L := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, int(ceil(L / max_len)))
	var out: Array = []
	for i in n:
		out.append([a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n)])
	return out


func _seg_xf(a: Vector3, b: Vector3) -> Transform3D:
	var d := b - a
	var mid := (a + b) * 0.5
	mid.y = ground(mid)
	return Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), mid)


# ================================================================ 屋内（中空の壁体・入口・内装の登録）
## 建物の壁は「外から見た姿は従来の箱と同じ」中空の壁体で作り、入口の開口を抜く。
## 内装そのものは WorldInteriors（scripts/world/interiors/）が近づいた時だけ生成する。
## 面: 0=+Z(正面) 1=+X 2=-Z 3=-X。開口の u は局所座標（前後面は x、側面は z）。

## 1 枚の壁（c が中心、局所 X 方向に長さ size.x・高さ size.y・厚み size.z）に開口を抜く。
## openings: [{u: 壁の中心からの横位置, y: 壁の底からの下端, w, h}]。当たり判定は入口（y<0.45）だけ抜く
func slab(mat: String, xf: Transform3D, c: Vector3, size: Vector3, colr: Color, openings := [], collide := true, rot := 0.0) -> void:
	var ops: Array = openings.duplicate()
	ops.sort_custom(func(p, q): return float(p["u"]) < float(q["u"]))
	var sx := xf * Transform3D(Basis(Vector3.UP, rot), c)
	var hx := size.x * 0.5
	var y0 := -size.y * 0.5
	var y1 := size.y * 0.5
	var cur := -hx
	for op in ops:
		var a0 := clampf(float(op["u"]) - float(op["w"]) * 0.5, -hx, hx)
		var a1 := clampf(float(op["u"]) + float(op["w"]) * 0.5, -hx, hx)
		var oy0 := y0 + float(op.get("y", 0.0))
		var oy1 := minf(oy0 + float(op["h"]), y1)
		_slab_piece(mat, sx, cur, a0, y0, y1, size.z, colr, y0)
		_slab_piece(mat, sx, a0, a1, y0, oy0, size.z, colr, y0)
		_slab_piece(mat, sx, a0, a1, oy1, y1, size.z, colr, y0)
		cur = maxf(cur, a1)
	_slab_piece(mat, sx, cur, hx, y0, y1, size.z, colr, y0)
	if not collide:
		return
	cur = -hx
	for op in ops:
		if float(op.get("y", 0.0)) >= 0.45:
			continue
		var a0 := clampf(float(op["u"]) - float(op["w"]) * 0.5, -hx, hx)
		var a1 := clampf(float(op["u"]) + float(op["w"]) * 0.5, -hx, hx)
		_slab_col(sx, cur, a0, y0, y1, size.z)
		_slab_col(sx, a0, a1, minf(y0 + float(op.get("y", 0.0)) + float(op["h"]), y1), y1, size.z)
		cur = maxf(cur, a1)
	_slab_col(sx, cur, hx, y0, y1, size.z)


func _slab_piece(mat: String, sx: Transform3D, ua: float, ub: float, ya: float, yb: float, th: float, colr: Color, ybase: float) -> void:
	if ub - ua < 0.02 or yb - ya < 0.02:
		return
	kit.box(mat, sx * Transform3D(Basis(), Vector3((ua + ub) * 0.5, (ya + yb) * 0.5, 0)), Vector3(ub - ua, yb - ya, th), colr, ya <= ybase + 0.01)


func _slab_col(sx: Transform3D, ua: float, ub: float, ya: float, yb: float, th: float) -> void:
	if ub - ua < 0.05 or yb - ya < 0.05:
		return
	cols.append([sx * Transform3D(Basis(), Vector3((ua + ub) * 0.5, (ya + yb) * 0.5, 0)), Vector3(ub - ua, yb - ya, maxf(th, 0.12))])


## 中空の壁体。外寸 size・中心 c の箱と同じ外観（四面の壁＋天面）で、内側に天井面を持つ。
## openings: [{side, u, y, w, h}]（u は局所座標）。o: th 壁厚 / cap 天面 / ceil 天井 / hole 吹き抜け(Rect2, xz)
## / floor 床面（上階の床） / collide / ceil_col
func shell(mat: String, xf: Transform3D, c: Vector3, size: Vector3, colr: Color, openings := [], o := {}) -> void:
	var th: float = o.get("th", 0.2)
	var collide: bool = o.get("collide", true)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	for side in 4:
		var ops: Array = []
		for op in openings:
			if int(op.get("side", 0)) != side:
				continue
			var q: Dictionary = op.duplicate()
			q["u"] = float(op["u"]) - (c.x if side % 2 == 0 else c.z)
			ops.append(q)
		match side:
			0: slab(mat, xf, Vector3(c.x, c.y, c.z + hz - th * 0.5), Vector3(size.x, size.y, th), colr, ops, collide)
			2: slab(mat, xf, Vector3(c.x, c.y, c.z - hz + th * 0.5), Vector3(size.x, size.y, th), colr, ops, collide)
			1: slab(mat, xf, Vector3(c.x + hx - th * 0.5, c.y, c.z), Vector3(size.z - th * 2.0, size.y, th), colr, ops, collide, -PI * 0.5)
			_: slab(mat, xf, Vector3(c.x - hx + th * 0.5, c.y, c.z), Vector3(size.z - th * 2.0, size.y, th), colr, ops, collide, -PI * 0.5)
	var top := c.y + size.y * 0.5
	var hole: Rect2 = o.get("hole", Rect2())
	var outer := Rect2(c.x - hx, c.z - hz, size.x, size.z)
	var inner := outer.grow(-th)
	if o.get("cap", true):
		rect_quads(mat, xf, top, outer, hole, colr, true)
	if o.get("ceil", true):
		rect_quads(mat, xf, top - 0.01, inner, hole, o.get("ceil_col", colr * Color(0.82, 0.8, 0.78)), false)
	if o.get("floor", false):
		rect_quads(o.get("floor_mat", "wood"), xf, c.y - size.y * 0.5 + 0.01, inner, o.get("floor_hole", Rect2()), o.get("floor_col", Color(0.85, 0.75, 0.62)), true)


## 外側に巻く帯（下見板・胴蛇腹など）。天面・天井なし・当たり判定なし。中が見えても床の上に面が出ない
func band(mat: String, xf: Transform3D, c: Vector3, size: Vector3, colr: Color, openings := [], th := 0.25) -> void:
	shell(mat, xf, c, size, colr, openings, {"th": th, "cap": false, "ceil": false, "collide": false})


## 矩形の面（hole を抜く）。r は局所 xz（position=(x0,z0)）
func rect_quads(mat: String, xf: Transform3D, y: float, r: Rect2, hole: Rect2, colr: Color, up: bool) -> void:
	var rects: Array = [r]
	if hole.size.x > 0.01 and hole.size.y > 0.01:
		var h := hole.intersection(r)
		if h.size.x > 0.01 and h.size.y > 0.01:
			rects = [Rect2(r.position.x, r.position.y, r.size.x, h.position.y - r.position.y),
				Rect2(r.position.x, h.end.y, r.size.x, r.end.y - h.end.y),
				Rect2(r.position.x, h.position.y, h.position.x - r.position.x, h.size.y),
				Rect2(h.end.x, h.position.y, r.end.x - h.end.x, h.size.y)]
	for q in rects:
		if q.size.x < 0.01 or q.size.y < 0.01:
			continue
		var p0 := xf * Vector3(q.position.x, y, q.end.y)
		var p1 := xf * Vector3(q.end.x, y, q.end.y)
		var p2 := xf * Vector3(q.end.x, y, q.position.y)
		var p3 := xf * Vector3(q.position.x, y, q.position.y)
		if up:
			kit.quad(mat, p0, p1, p2, p3, colr)
		else:
			kit.quad(mat, p0, p3, p2, p1, colr)


## 坂の当たり判定（階段・梯子・式台）。局所 a（下）→ b（上）。breakable=false なら壊れない静的コリジョン
func ramp(xf: Transform3D, a: Vector3, b: Vector3, width: float, breakable := false) -> void:
	var e := ramp_shape(xf, a, b, width)
	if e.is_empty():
		return
	if breakable:
		cols.append(e)
	else:
		base_cols.append(e)


static func ramp_shape(xf: Transform3D, a: Vector3, b: Vector3, width: float) -> Array:
	var d := b - a
	var L := d.length()
	if L < 0.05:
		return []
	var z := d / L
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	return [xf * Transform3D(Basis(x, y, z), (a + b) * 0.5 - y * 0.15), Vector3(width, 0.3, L + 0.1)]


## 見た目の階段（a 下 → b 上、n 段）
func steps(mat: String, xf: Transform3D, a: Vector3, b: Vector3, width: float, colr: Color, n := 0) -> void:
	var hz := Vector3(b.x - a.x, 0, b.z - a.z)
	var run := hz.length()
	if run < 0.05:
		return
	if n <= 0:
		n = maxi(2, int(ceil((b.y - a.y) / 0.2)))
	var dirn := hz / run
	var yaw := atan2(dirn.x, dirn.z)
	for i in n:
		var top := a.y + (b.y - a.y) * float(i + 1) / n
		var bot := minf(a.y, b.y) - 0.25
		var p := a + dirn * run * (float(i) + 0.5) / n
		kit.box(mat, xf * Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, (top + bot) * 0.5, p.z)), Vector3(width, top - bot, run / n + 0.01), colr)


## 入口の段（土台の高さ h まで）: 見た目の段＋坂の当たり判定。x は入口の横位置、z_edge は土台の縁（+Z 向き）
func entry_steps(xf: Transform3D, x: float, z_edge: float, h: float, width: float, mat := "stonewall", colr := STONE, breakable := false) -> float:
	if h < 0.06:
		return 0.0
	var run := maxf(h / 0.62, 0.5)
	var top := Vector3(x, h, z_edge)
	var bot := Vector3(x, 0.0, z_edge + run)
	steps(mat, xf, bot, top, width, colr, maxi(1, int(ceil(h / 0.2))))
	ramp(xf, bot + Vector3(0, -0.05, 0.25), top + Vector3(0, 0, -0.05), width, breakable)
	return run


## 内装の登録。floors: [{y, rect(Rect2 局所 xz), h, hole?(この階の天井の吹き抜け), stair?}]
## doors: [{p 局所(敷居の中心), n 外向き, w, h, out 外の地面の点}]。o: tags / win / opts
func reg_interior(type: String, xf: Transform3D, floors: Array, doors: Array, o := {}) -> void:
	if _ustack.is_empty():
		return
	var yaw := xf.basis.get_euler().y
	var d := {"id": int(_ustack.back()["id"]), "type": type, "xf": Transform3D(Basis(Vector3.UP, yaw), xf.origin),
		"floors": floors, "doors": doors, "era": w.era_id, "landmark": landmark}
	for k in o:
		d[k] = o[k]
	w.interior_defs.append(d)
	# 斜面の敷地では地形が 1 階の床から突き出すので、部屋の下の地形を床より下げる（地形メッシュを作る前）
	var fxf: Transform3D = d["xf"]
	var inv := fxf.affine_inverse()
	for f in floors:
		var r: Rect2 = (f["rect"] as Rect2).grow(t.cell)
		var ymax: float = fxf.origin.y + float(f["y"]) - 0.08
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for cc in [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.position.x, 0, r.end.y), Vector3(r.end.x, 0, r.end.y)]:
			var wp: Vector3 = fxf * cc
			lo = lo.min(Vector2(wp.x, wp.z))
			hi = hi.max(Vector2(wp.x, wp.z))
		for j in range(t.gi(lo.y), t.gi(hi.y) + 1):
			for i in range(t.gi(lo.x), t.gi(hi.x) + 1):
				var lp := inv * Vector3(t.gx(i), 0, t.gx(j))
				if r.has_point(Vector2(lp.x, lp.z)):
					var id := j * TerrainGen.N + i
					if t.h[id] > ymax:
						t.h[id] = ymax


static func fl(y: float, rect: Rect2, h: float, o := {}) -> Dictionary:
	var d := {"y": y, "rect": rect, "h": h}
	for k in o:
		d[k] = o[k]
	return d


static func door(p: Vector3, n: Vector3, wd: float, ht: float, out_dist := 2.5) -> Dictionary:
	return {"p": p, "n": n, "w": wd, "h": ht, "out": p + n * out_dist}


## 開いた引き戸・板扉など入口の飾り（xf 局所、+Z 面の u に幅 dw・高さ dh、床 y、壁面 z）
func door_frame(xf: Transform3D, u: float, y: float, z: float, dw: float, dh: float, style := "frame", colr := DARK, cloth_col := Color(0.15, 0.2, 0.42)) -> void:
	var fx := xf
	var c := Vector3(u, y, z)
	for sgn in [-1.0, 1.0]:
		kit.box("darkwood", fx * Transform3D(Basis(), c + Vector3(sgn * (dw * 0.5 + 0.05), dh * 0.5, 0.04)), Vector3(0.1, dh, 0.22), colr)
	kit.box("darkwood", fx * Transform3D(Basis(), c + Vector3(0, dh + 0.06, 0.04)), Vector3(dw + 0.3, 0.12, 0.24), colr, false)
	match style:
		"leaves":
			# 観音開き（外へ開いた板扉）
			for sgn in [-1.0, 1.0]:
				kit.box("darkwood", fx * Transform3D(Basis(), c + Vector3(sgn * (dw * 0.5 - 0.04), dh * 0.48, dw * 0.25 + 0.06)), Vector3(0.07, dh * 0.96, dw * 0.5 - 0.02), Color(0.62, 0.48, 0.38))
		"slide":
			# 引き戸を片側へ開けた状態（外壁の前に重ねる）
			kit.box("darkwood", fx * Transform3D(Basis(), c + Vector3(dw * 0.98, dh * 0.48, 0.12)), Vector3(dw, dh * 0.96, 0.05), Color(0.55, 0.42, 0.34))
		"noren":
			kit.box("cloth", fx * Transform3D(Basis(), c + Vector3(0, dh - 0.36, 0.16)), Vector3(dw + 0.1, 0.7, 0.02), cloth_col)
		"glass":
			for sgn in [-1.0, 1.0]:
				kit.box("glass", fx * Transform3D(Basis(), c + Vector3(sgn * (dw * 0.5 + 0.02), dh * 0.48, dw * 0.25 + 0.04)), Vector3(0.05, dh * 0.94, dw * 0.48), Color(0.5, 0.58, 0.64))


# ================================================================ 基本ユーティリティ
func ground(p: Vector3) -> float:
	return t.height_at(p.x, p.z)


## ローカル（lm の座標系）→ 建物 Transform。y は足元の地面（四隅の最小）
func place(lm_xf: Transform3D, lx: float, lz: float, rot: float, foot := Vector2(4, 4)) -> Transform3D:
	var xf := lm_xf * Transform3D(Basis(Vector3.UP, rot), Vector3(lx, 0, lz))
	var y := INF
	for c in [Vector3(-foot.x, 0, -foot.y), Vector3(foot.x, 0, -foot.y), Vector3(-foot.x, 0, foot.y), Vector3(foot.x, 0, foot.y), Vector3.ZERO]:
		var p: Vector3 = xf * (c * 0.5)
		y = minf(y, ground(p))
	xf.origin.y = y
	return xf


func col(xf: Transform3D, center: Vector3, size: Vector3) -> void:
	cols.append([xf * Transform3D(Basis(), center), size])


func occupy(xf: Transform3D, wd: float, dp: float, plaza := 0.0) -> void:
	var p := Vector2(xf.origin.x, xf.origin.z)
	var ang := -xf.basis.get_euler().y
	t.occupy_rect(p, ang, wd * 0.5, dp * 0.5)
	if plaza > 0.0:
		t.paint_rect(t.plaza, p, ang, wd * 0.5 + plaza, dp * 0.5 + plaza, 0.75, 1.5)


func bx(mat: String, xf: Transform3D, c: Vector3, size: Vector3, colr := Color.WHITE) -> void:
	kit.box(mat, xf * Transform3D(Basis(), c), size, colr)


func cyl(mat: String, xf: Transform3D, base: Vector3, r0: float, r1: float, h: float, segs := 8, colr := Color.WHITE) -> void:
	kit.cylinder(mat, xf * Transform3D(Basis(), base), r0, r1, h, segs, colr)


## 土台（地面の起伏を隠す）
func foundation(xf: Transform3D, wd: float, dp: float, h: float, mat := "stonewall", colr := STONE) -> void:
	# 土台は壊れない（廃墟の基壇として残る）
	var prev := kit.cur_unit
	kit.set_unit(0)
	bx(mat, xf, Vector3(0, (h - 2.0) * 0.5, 0), Vector3(wd, h + 2.0, dp), colr)
	kit.set_unit(prev)
	base_cols.append([xf * Transform3D(Basis(), Vector3(0, (h - 2.0) * 0.5, 0)), Vector3(wd, h + 2.0, dp)])
	if not _ustack.is_empty():
		_ustack.back()["base_top"] = maxf(float(_ustack.back()["base_top"]), xf.origin.y + h)


func roof(xf: Transform3D, y: float, hw: float, hd: float, rise: float, style: String, mat := "rooftile", colr := TILE, lift := 0.5, under_col := Color(0.55, 0.42, 0.34), curve := 1.35, clamp := []) -> void:
	var gs := 0.0
	match style:
		"irimoya": gs = 0.42
		"gable": gs = 1.0
		"hip", "pyramid": gs = 0.0
	var thick := 0.32 if mat == "rooftile" else 0.7
	var gmat := "darkwood" if style != "gable" else "darkwood"
	var rx := xf * Transform3D(Basis(), Vector3(0, y, 0))
	if clamp.is_empty():
		kit.roof(rx, hw, hd, rise, gs, mat, "darkwood", colr, curve, lift, thick, under_col, gmat, Color(0.8, 0.75, 0.7))
	else:
		kit.roof(rx, hw, hd, rise, gs, mat, "darkwood", colr, curve, lift, thick, under_col, gmat, Color(0.8, 0.75, 0.7), 12, 16, clamp[0], clamp[1])
	if not clamp.is_empty():
		return   # 上の層に覆われる屋根: 棟・鬼瓦は上の層の部屋の中に出るので作らない
	if style != "pyramid":
		var cap_mat := mat if mat != "thatch" else "thatch"
		kit.ridge_cap(rx, hw, hd, rise, gs, cap_mat, colr * Color(0.7, 0.7, 0.7) if mat == "rooftile" else colr * Color(0.8, 0.8, 0.8), 0.55 if mat == "rooftile" else 0.9)
		if mat == "rooftile":
			# 鬼瓦
			var hx := (hw - hd + hd * gs) if gs < 1.0 else hw
			if hd > hw:
				hx = (hd - hw + hw * gs) if gs < 1.0 else hd
			var axis := Vector3.RIGHT if (hw >= hd or gs >= 1.0) else Vector3.BACK
			if gs >= 1.0:
				hx = hw
			for sgn in [-1.0, 1.0]:
				kit.box("rooftile", rx * Transform3D(Basis(), axis * sgn * (hx + 0.3) + Vector3(0, rise + 0.45, 0)), Vector3(0.6, 0.9, 0.6), colr * Color(0.6, 0.6, 0.6))
	else:
		# 宝珠
		kit.cylinder("metal", rx * Transform3D(Basis(), Vector3(0, rise - 0.2, 0)), 0.25, 0.08, 1.4, 6, Color(0.35, 0.3, 0.22))
		kit.sphere("gold", rx * Transform3D(Basis(), Vector3(0, rise + 1.3, 0)), 0.22, 6, 4)


# ================================================================ 日本建築
## 基壇の上に柱・壁・組物・屋根を持つ堂（宮殿・寺院の金堂・拝殿など）
func _u_jp_hall(xf: Transform3D, wd: float, dp: float, o := {}) -> void:
	var base_h: float = o.get("base_h", 1.0)
	var wall_h: float = o.get("wall_h", 4.0)
	var pillar_col: Color = o.get("pillar", VERMILION)
	var pillar_mat: String = o.get("pillar_mat", "plaster")
	var wall_col: Color = o.get("wall", PLASTER)
	var roof_style: String = o.get("roof", "irimoya")
	var roof_mat: String = o.get("roof_mat", "rooftile")
	var roof_col: Color = o.get("roof_col", TILE if roof_mat == "rooftile" else (THATCH if roof_mat == "thatch" else BARK))
	var over: float = o.get("over", 2.2)
	var rise_k: float = o.get("rise", 0.42)
	var lift: float = o.get("lift", 0.6)
	var base_mat: String = o.get("base_mat", "stonewall")
	var two_tier: bool = o.get("two_tier", false)
	var raised: bool = o.get("raised", false)
	# 入口は正面中央の間（柱と柱の間）
	var nbay := maxi(1, int(round(wd / 3.2)))
	var bay := wd / nbay
	var door_k := nbay / 2
	var door_x := -wd * 0.5 + bay * (door_k + 0.5)
	var dw := minf(bay * 0.72, 2.4)
	var dh := clampf(wall_h * 0.8, 2.1, 2.8)
	var z_out := dp * 0.5 + 1.2
	if base_h > 0.05:
		foundation(xf, wd + 2.4, dp + 2.4, base_h, base_mat, o.get("base_col", STONE))
		if not raised:
			# 正面の階段（入口の前）
			z_out += entry_steps(xf, door_x, dp * 0.5 + 1.2, base_h, maxf(minf(wd * 0.4, 6.0), dw + 1.2), base_mat, o.get("base_col", STONE))
	var y0 := base_h
	if raised:
		# 高床＋縁側（寝殿造など）
		var fh := 1.2
		for i in int(wd / 2.5) + 1:
			for j in [-1.0, 1.0]:
				cyl("wood", xf, Vector3(-wd * 0.5 - 0.8 + i * (wd + 1.6) / int(wd / 2.5), y0, j * (dp * 0.5 + 0.8)), 0.12, 0.12, fh, 6)
		bx("wood", xf, Vector3(0, y0 + fh - 0.1, 0), Vector3(wd + 1.8, 0.2, dp + 1.8), Color(0.9, 0.85, 0.8))
		# 高欄（正面は階の幅だけ開ける）
		var rmat := "plaster" if pillar_mat == "plaster" else "wood"
		var g0 := door_x - dw * 0.5 - 0.3
		var g1 := door_x + dw * 0.5 + 0.3
		var e0 := -(wd * 0.5 + 0.9)
		var e1 := wd * 0.5 + 0.9
		bx(rmat, xf, Vector3((e0 + g0) * 0.5, y0 + fh + 0.55, dp * 0.5 + 0.85), Vector3(g0 - e0, 0.08, 0.08), pillar_col)
		bx(rmat, xf, Vector3((g1 + e1) * 0.5, y0 + fh + 0.55, dp * 0.5 + 0.85), Vector3(e1 - g1, 0.08, 0.08), pillar_col)
		bx(rmat, xf, Vector3(0, y0 + fh + 0.55, -(dp * 0.5 + 0.85)), Vector3(wd + 1.8, 0.08, 0.08), pillar_col)
		for sgn in [-1.0, 1.0]:
			bx(rmat, xf, Vector3(sgn * (wd * 0.5 + 0.85), y0 + fh + 0.55, 0), Vector3(0.08, 0.08, dp + 1.8), pillar_col)
		y0 += fh
		col(xf, Vector3(0, y0 * 0.5, 0), Vector3(wd + 1.8, y0, dp + 1.8))
		# 階（木の階段）
		z_out = dp * 0.5 + 0.9 + entry_steps(xf, door_x, dp * 0.5 + 0.9, y0, minf(dw + 0.6, 2.6), "wood", Color(0.9, 0.85, 0.8), true)
	# 壁（柱の内側）: 中空の壁体＋入口
	var wwid := wd - 0.3
	var wdep := dp - 0.3
	shell("plaster", xf, Vector3(0, y0 + wall_h * 0.5, 0), Vector3(wwid, wall_h, wdep), wall_col, [{"side": 0, "u": door_x, "w": dw, "h": dh}], {"th": 0.18})
	# 腰壁・扉（正面は格子戸の帯）。入口の間は扉を外へ開く
	var door_mat: String = o.get("door_mat", "darkwood")
	for i in nbay:
		var x := -wd * 0.5 + bay * (i + 0.5)
		if i == door_k:
			door_frame(xf, door_x, y0, wdep * 0.5, dw, dh, "leaves", Color(0.55, 0.42, 0.34) if pillar_col != VERMILION else Color(0.7, 0.3, 0.2))
			continue
		bx(door_mat, xf, Vector3(x, y0 + wall_h * 0.42, dp * 0.5 - 0.1), Vector3(bay * 0.78, wall_h * 0.84, 0.12), o.get("door_col", Color(0.82, 0.74, 0.66)))
		# 格子
		for k in 5:
			bx("wood", xf, Vector3(x - bay * 0.3 + k * bay * 0.15, y0 + wall_h * 0.42, dp * 0.5 - 0.02), Vector3(0.05, wall_h * 0.84, 0.05), Color(0.7, 0.6, 0.5))
	# 柱
	var nx := nbay + 1
	var nz := maxi(2, int(round(dp / 3.2)) + 1)
	for i in nx:
		for j in nz:
			if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
				continue
			var x := -wd * 0.5 + wd * i / (nx - 1)
			var z := -dp * 0.5 + dp * j / (nz - 1)
			cyl(pillar_mat, xf, Vector3(x, y0, z), 0.24, 0.22, wall_h + 0.2, 8, pillar_col)
	# 長押・組物
	for yy in [y0 + wall_h * 0.82, y0 + wall_h]:
		bx(pillar_mat, xf, Vector3(0, yy, 0), Vector3(wd + 0.25, 0.22, dp + 0.25), pillar_col)
	bx("darkwood", xf, Vector3(0, y0 + wall_h + 0.35, 0), Vector3(wd + 0.9, 0.5, dp + 0.9), Color(0.7, 0.55, 0.42) if pillar_col == VERMILION else DARK)
	var ry := y0 + wall_h + 0.55
	var hw := wd * 0.5 + over
	var hd := dp * 0.5 + over
	var rise := minf(hw, hd) * rise_k * 2.0
	if two_tier:
		# 裳階（下の屋根）と上の身舎
		roof(xf, ry, hw, hd, rise * 0.3, "hip", roof_mat, roof_col, lift * 0.5)
		var w2 := wd * 0.72
		var d2 := dp * 0.72
		var y2 := ry + rise * 0.3 * 0.55
		bx("plaster", xf, Vector3(0, y2 + 1.4, 0), Vector3(w2, 2.8, d2), wall_col)
		for i in 4:
			var x := -w2 * 0.5 + w2 * i / 3.0
			for z in [-d2 * 0.5, d2 * 0.5]:
				cyl(pillar_mat, xf, Vector3(x, y2, z), 0.2, 0.2, 2.9, 6, pillar_col)
		bx("darkwood", xf, Vector3(0, y2 + 3.0, 0), Vector3(w2 + 0.8, 0.45, d2 + 0.8), DARK)
		roof(xf, y2 + 3.2, w2 * 0.5 + over, d2 * 0.5 + over, minf(w2, d2) * rise_k * 1.1, roof_style, roof_mat, roof_col, lift)
	else:
		roof(xf, ry, hw, hd, rise, roof_style, roof_mat, roof_col, lift)
	col(xf, Vector3(0, ry + rise * 0.4, 0), Vector3(wd + over, rise * 0.8, dp + over))
	occupy(xf, wd + 2.4, dp + 2.4, 2.0)
	# 内装の登録
	var th := 0.18
	var dd := door(Vector3(door_x, y0, wdep * 0.5), Vector3.BACK, dw, dh)
	dd["out"] = Vector3(door_x, 0.0, z_out + 1.2)
	var kind: String = o.get("interior", _hall_interior(base_h, roof_style, roof_mat, raised))
	reg_interior(kind, xf, [fl(y0, Rect2(-wwid * 0.5 + th, -wdep * 0.5 + th, wwid - th * 2.0, wdep - th * 2.0), wall_h)], [dd],
		{"pillar": pillar_col, "two_tier": two_tier, "wall": wall_col})


## 堂の用途（内装キット）を時代・場所・屋根から決める
func _hall_interior(base_h: float, roof_style: String, roof_mat: String, raised: bool) -> String:
	var era := w.era_id
	if raised:
		return "shinden"
	if landmark == "temple":
		if era == "showa" or roof_style == "gable":
			return "shrine"
		if era == "kamakura_muromachi" and roof_mat == "thatch":
			return "shoin"
		return "temple"
	if landmark == "village" and roof_style == "gable":
		return "shrine"
	if era in ["jomon_kofun", "asuka_nara", "heian"]:
		return "daigokuden" if base_h >= 1.5 else "palace"
	if era in ["sengoku", "edo"] and landmark == "capital":
		return "goten"
	return "shoin"


## 五重塔／三重塔
func _u_pagoda(xf: Transform3D, tiers := 5, base_w := 7.0, tier_h := 3.0, colr := VERMILION) -> void:
	foundation(xf, base_w + 3.0, base_w + 3.0, 1.0)
	var z_out := (base_w + 3.0) * 0.5
	z_out += entry_steps(xf, 0.0, z_out, 1.0, 2.6)
	var y := 1.0
	var y_t1 := 0.0
	for i in tiers:
		var wd := base_w * (1.0 - i * 0.075)
		var h := tier_h if i == 0 else tier_h * 0.72
		if i == 0:
			# 初層は中に入れる（心柱と四方仏）
			var dw := wd * 0.3
			var dh := minf(h * 0.78, 2.5)
			shell("plaster", xf, Vector3(0, y + h * 0.5, 0), Vector3(wd, h, wd), PLASTER, [{"side": 0, "u": 0.0, "w": dw, "h": dh}], {"th": 0.2})
			door_frame(xf, 0.0, y, wd * 0.5, dw, dh, "leaves", Color(0.6, 0.3, 0.2))
			var inner := Rect2(-wd * 0.5 + 0.2, -wd * 0.5 + 0.2, wd - 0.4, wd - 0.4)
			var dd := door(Vector3(0, y, wd * 0.5), Vector3.BACK, dw, dh)
			dd["out"] = Vector3(0, 0, z_out + 1.2)
			reg_interior("pagoda", xf, [fl(y, inner, h)], [dd])
		else:
			bx("plaster", xf, Vector3(0, y + h * 0.5, 0), Vector3(wd, h, wd), PLASTER)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				cyl("plaster", xf, Vector3(cx * wd * 0.5, y, cz * wd * 0.5), 0.2, 0.2, h, 6, colr)
		# 扉（正面）
		if i > 0:
			bx("darkwood", xf, Vector3(0, y + h * 0.45, wd * 0.5 + 0.02), Vector3(wd * 0.36, h * 0.75, 0.08), Color(0.6, 0.3, 0.2))
		bx("plaster", xf, Vector3(0, y + h - 0.1, 0), Vector3(wd + 0.3, 0.2, wd + 0.3), colr)
		bx("darkwood", xf, Vector3(0, y + h + 0.25, 0), Vector3(wd + 1.1, 0.5, wd + 1.1), Color(0.75, 0.5, 0.35))
		var hw := wd * 0.5 + 2.3
		roof(xf, y + h + 0.45, hw, hw, 1.25, "pyramid" if i == tiers - 1 else "hip", "rooftile", TILE_DARK, 0.75, Color(0.75, 0.42, 0.3), 1.6)
		y += h + 1.25 * 0.62
		if i == 0:
			y_t1 = y
	# 相輪
	var ty := y + 0.3
	cyl("metal", xf, Vector3(0, ty, 0), 0.6, 0.6, 0.6, 8, Color(0.3, 0.27, 0.2))
	cyl("metal", xf, Vector3(0, ty, 0), 0.12, 0.1, 8.0, 6, Color(0.3, 0.27, 0.2))
	for k in 9:
		cyl("metal", xf, Vector3(0, ty + 1.0 + k * 0.55, 0), 0.42 - k * 0.02, 0.42 - k * 0.02, 0.1, 10, Color(0.36, 0.32, 0.24))
	kit.sphere("gold", xf * Transform3D(Basis(), Vector3(0, ty + 8.2, 0)), 0.3, 8, 5)
	# 当たり判定: 初層は壁体（shell）、二層目から上は塊
	col(xf, Vector3(0, (y_t1 - 0.8 + y) * 0.5, 0), Vector3(base_w * 0.9, y - y_t1 + 0.8, base_w * 0.9))
	occupy(xf, base_w + 3, base_w + 3, 2.5)


## 鳥居（明神鳥居）
func _u_torii(xf: Transform3D, wd := 6.0, h := 6.0, colr := VERMILION, mat := "plaster") -> void:
	var r := wd * 0.055
	for sgn in [-1.0, 1.0]:
		var base := Vector3(sgn * wd * 0.5, 0, 0)
		var top := Vector3(sgn * wd * 0.46, h, 0)
		kit.rod(mat, xf * base, xf * top, r, 10, colr)
		kit.cylinder("darkwood", xf * Transform3D(Basis(), base), r * 1.35, r * 1.3, 0.6, 10, BLACK)
		col(xf, Vector3(sgn * wd * 0.48, h * 0.5, 0), Vector3(r * 2, h, r * 2))
	# 貫
	bx(mat, xf, Vector3(0, h * 0.78, 0), Vector3(wd * 1.12, r * 1.4, r * 0.9), colr)
	# 笠木（両端が反る）
	var segs := 6
	var span := wd * 1.42
	for k in segs:
		var a := -span * 0.5 + span * k / segs
		var b := -span * 0.5 + span * (k + 1) / segs
		var ya := h + 0.12 + pow(absf(a) / (span * 0.5), 2.5) * 0.45
		var yb := h + 0.12 + pow(absf(b) / (span * 0.5), 2.5) * 0.45
		var pa := Vector3(a, ya, 0)
		var pb := Vector3(b, yb, 0)
		var mid := (pa + pb) * 0.5
		var dir := (pb - pa).normalized()
		kit.box(mat, xf * Transform3D(Basis(Vector3.BACK, atan2(yb - ya, b - a)), mid), Vector3(pa.distance_to(pb) + 0.02, r * 1.3, r * 1.4), colr)
		kit.box("darkwood", xf * Transform3D(Basis(Vector3.BACK, atan2(yb - ya, b - a)), mid + Vector3(0, r * 0.9, 0)), Vector3(pa.distance_to(pb) + 0.02, r * 0.6, r * 1.6), BLACK)
	# 額束
	bx(mat, xf, Vector3(0, h * 0.89, 0), Vector3(r * 1.2, h * 0.2, r * 0.8), colr)


## 竪穴住居（茅葺きの円錐。正面の区画の下を抜いて屋根付きの入口を通す）
func _u_pit_dwelling(xf: Transform3D, r := 3.6) -> void:
	cyl("earth", xf, Vector3(0, -0.6, 0), r + 0.9, r + 0.5, 1.0, 14, Color(0.8, 0.72, 0.6))
	_thatch_cone(xf, 0.2, r + 0.35, 0.55, 4.4, 14, 3, 0.5)
	# 煙出しの小屋根
	roof(xf, 4.3, 0.95, 0.6, 0.7, "gable", "thatch", THATCH * 0.9, 0.0)
	# 入口（屋根付きの通路）
	var ex := xf * Transform3D(Basis(), Vector3(0, 0, r - 0.2))
	var dh := 1.95
	for sgn in [-1.0, 1.0]:
		bx("darkwood", ex, Vector3(sgn * 0.68, dh * 0.5 + 0.1, 0.35), Vector3(0.14, dh + 0.2, 1.9), Color(0.36, 0.3, 0.26))
		cols.append([xf * Transform3D(Basis(), Vector3(sgn * 0.7, 1.0, r - 0.3)), Vector3(0.18, 2.0, 2.6)])
	roof(ex, dh + 0.1, 1.05, 1.25, 0.75, "gable", "thatch", THATCH, 0.0)
	# 当たり判定: 内側の環（入口は開ける）＋床（盛り土の上面）
	var rin := r * 0.68
	var nseg := 10
	for k in nseg:
		var am := TAU * (k + 0.5) / nseg
		if absf(wrapf(am - PI * 0.5, -PI, PI)) < 0.3:
			continue
		var dv := Vector3(cos(am), 0, sin(am))
		cols.append([xf * Transform3D(Basis(Vector3.UP, atan2(dv.x, dv.z)), dv * (rin + 0.15) + Vector3(0, 1.6, 0)), Vector3(2.0 * rin * tan(PI / nseg) + 0.15, 2.4, 0.3)])
	for k in 2:
		base_cols.append([xf * Transform3D(Basis(Vector3.UP, PI * 0.25 * k), Vector3(0, -0.1, 0)), Vector3(r * 1.55, 1.0, r * 1.55)])
	ramp(xf, Vector3(0, 0.0, r + 1.5), Vector3(0, 0.4, rin), 1.2)
	occupy(xf, r * 2 + 1.5, r * 2 + 1.5, 1.5)
	var dd := door(Vector3(0, 0.4, rin), Vector3.BACK, 1.1, dh)
	dd["out"] = Vector3(0, 0, r + 2.6)
	reg_interior("pit", xf, [fl(0.4, Rect2(-rin, -rin, rin * 2.0, rin * 2.0), 2.6, {"round": rin, "cone": [0.2, r + 0.35, 0.55, 4.4]})], [dd])


## 茅葺きの円錐（外面＋煤けた内面）。gap_seg の区画は高さ比 gap_t より上だけ作る（入口）
func _thatch_cone(xf: Transform3D, y0: float, r0: float, r1: float, h: float, segs: int, gap_seg: int, gap_t: float,
		colr := THATCH, inner_col := Color(0.46, 0.36, 0.27)) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var t0 := gap_t if i == gap_seg else 0.0
		var ra := lerpf(r0, r1, t0)
		var ya := y0 + h * t0
		var p00 := xf * Vector3(cos(a0) * ra, ya, sin(a0) * ra)
		var p01 := xf * Vector3(cos(a1) * ra, ya, sin(a1) * ra)
		var p10 := xf * Vector3(cos(a0) * r1, y0 + h, sin(a0) * r1)
		var p11 := xf * Vector3(cos(a1) * r1, y0 + h, sin(a1) * r1)
		kit.quad("thatch", p00, p10, p11, p01, colr)
		var q00 := xf * Vector3(cos(a0) * (ra - 0.25), ya, sin(a0) * (ra - 0.25))
		var q01 := xf * Vector3(cos(a1) * (ra - 0.25), ya, sin(a1) * (ra - 0.25))
		var q10 := xf * Vector3(cos(a0) * maxf(r1 - 0.2, 0.2), y0 + h - 0.3, sin(a0) * maxf(r1 - 0.2, 0.2))
		var q11 := xf * Vector3(cos(a1) * maxf(r1 - 0.2, 0.2), y0 + h - 0.3, sin(a1) * maxf(r1 - 0.2, 0.2))
		kit.quad("thatch", q00, q01, q11, q10, inner_col)
		if i == gap_seg:
			# 入口の上の縁（厚み）
			kit.quad("thatch", p00, p01, q01, q00, inner_col * 0.8)


## 高床倉庫
func _u_raised_storehouse(xf: Transform3D, wd := 4.2, dp := 3.4, h := 1.9) -> void:
	for i in 3:
		for j in 2:
			var p := Vector3(-wd * 0.5 + wd * i / 2.0, 0, -dp * 0.5 + dp * j)
			cyl("wood", xf, p + Vector3(0, -0.5, 0), 0.16, 0.15, h + 0.5, 6, DARK)
			cyl("wood", xf, p + Vector3(0, h - 0.5, 0), 0.5, 0.5, 0.08, 8, DARK)
	bx("wood", xf, Vector3(0, h + 0.1, 0), Vector3(wd + 0.6, 0.25, dp + 0.6), DARK)
	var dw := 0.9
	var dh := 1.85
	shell("darkwood", xf, Vector3(0, h + 1.25, 0), Vector3(wd, 2.1, dp), Color(0.9, 0.82, 0.72), [{"side": 0, "u": 0.0, "w": dw, "h": dh}], {"th": 0.12})
	door_frame(xf, 0.0, h + 0.2, dp * 0.5, dw, dh, "slide", DARK)
	roof(xf, h + 2.3, wd * 0.5 + 0.9, dp * 0.5 + 1.0, 2.6, "gable", "thatch", THATCH, 0.0, Color(0.5, 0.4, 0.3), 1.0)
	# 刻み梯子（丸太に段を刻む）
	var top := Vector3(0, h + 0.22, dp * 0.5 + 0.3)
	var run := (h + 0.22) / 0.84
	var bot := Vector3(0, 0.0, dp * 0.5 + 0.3 + run)
	kit.rod("darkwood", xf * (bot + Vector3(0, -0.15, 0.1)), xf * (top + Vector3(0, -0.05, 0.0)), 0.17, 6, DARK)
	for k in 5:
		var q := bot.lerp(top, (k + 0.7) / 5.6)
		kit.box("wood", xf * Transform3D(Basis(), q + Vector3(0, 0.08, 0)), Vector3(0.42, 0.08, 0.22), DARK)
	ramp(xf, bot + Vector3(0, -0.05, 0.2), top + Vector3(0, 0, -0.05), 0.8, true)
	col(xf, Vector3(0, h + 0.1, 0), Vector3(wd + 0.6, 0.25, dp + 0.6))
	for i in 3:
		col(xf, Vector3(-wd * 0.5 + wd * i / 2.0, h * 0.5, 0), Vector3(0.3, h, dp))
	col(xf, Vector3(0, h + 3.0, 0), Vector3(wd, 1.2, dp))
	occupy(xf, wd + 1, dp + 1, 1.0)
	var dd := door(Vector3(0, h + 0.225, dp * 0.5), Vector3.BACK, dw, dh)
	dd["out"] = bot + Vector3(0, 0, 1.4)
	reg_interior("takayuka", xf, [fl(h + 0.225, Rect2(-wd * 0.5 + 0.12, -dp * 0.5 + 0.12, wd - 0.24, dp - 0.24), 2.0)], [dd])


## 物見櫓
func _u_watchtower(xf: Transform3D, h := 10.0, s := 3.4, roof_mat := "thatch") -> void:
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			kit.rod("wood", xf * Vector3(cx * s * 0.62, -0.5, cz * s * 0.62), xf * Vector3(cx * s * 0.5, h + 2.4, cz * s * 0.5), 0.17, 6, DARK)
			col(xf, Vector3(cx * s * 0.55, h * 0.5, cz * s * 0.55), Vector3(0.35, h, 0.35))
	# 筋交い
	for lvl in 2:
		var y0 := 1.0 + lvl * h * 0.45
		var y1 := y0 + h * 0.4
		for side in 4:
			var a := Vector3(-1, 0, 1).rotated(Vector3.UP, side * PI * 0.5) * s * 0.58
			var b := Vector3(1, 0, 1).rotated(Vector3.UP, side * PI * 0.5) * s * 0.58
			kit.rod("wood", xf * (a + Vector3(0, y0, 0)), xf * (b + Vector3(0, y1, 0)), 0.07, 4, DARK)
	bx("wood", xf, Vector3(0, h, 0), Vector3(s + 0.8, 0.25, s + 0.8), DARK)
	for side in 4:
		var c := Vector3(0, h + 0.55, (s + 0.7) * 0.5).rotated(Vector3.UP, side * PI * 0.5)
		kit.box("wood", xf * Transform3D(Basis(Vector3.UP, side * PI * 0.5), c), Vector3(s + 0.8, 0.9, 0.08), Color(0.85, 0.78, 0.7))
	roof(xf, h + 2.4, s * 0.5 + 0.8, s * 0.5 + 0.8, 1.3, "hip", roof_mat, THATCH if roof_mat == "thatch" else TILE, 0.0)
	col(xf, Vector3(0, h, 0), Vector3(s + 0.8, 0.3, s + 0.8))
	occupy(xf, s + 1.4, s + 1.4, 1.0)


## 柵（逆茂木風の丸太柵）
func _u_palisade(a: Vector3, b: Vector3, h := 2.6, gap := 0.42) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	var n := int(L / gap)
	for k in n:
		var p := a.lerp(b, (k + 0.5) / n)
		p.y = ground(p) - 0.4
		var hh := h + rng.randf_range(-0.25, 0.25)
		kit.cylinder("wood", Transform3D(Basis(), p), 0.13, 0.12, hh, 5, DARK, false, true)
		kit.cylinder("wood", Transform3D(Basis(), p + Vector3(0, hh, 0)), 0.12, 0.01, 0.35, 5, DARK, false, true)
	var mid := (a + b) * 0.5
	mid.y = ground(mid)
	var ang := atan2(d.x, d.z)
	cols.append([Transform3D(Basis(Vector3.UP, ang), mid + Vector3(0, h * 0.5, 0)), Vector3(0.3, h + 1.0, L)])
	# 横木
	for yy in [0.7, 1.9]:
		var pa := a + Vector3(0, ground(a) - a.y + yy, 0)
		var pb := b + Vector3(0, ground(b) - b.y + yy, 0)
		kit.rod("wood", pa, pb, 0.06, 4, DARK)
	t.paint_line(t.plaza, Vector2(a.x, a.z), Vector2(b.x, b.z), 1.2, 0.5, 1.0)


## 築地塀（瓦屋根付き土塀）。lines=筋（白線）
func _u_tsuiji(a: Vector3, b: Vector3, h := 2.8, colr := OCHRE, lines := false) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	if L < 0.5:
		return
	var ang := atan2(d.x, d.z)
	var mid := (a + b) * 0.5
	mid.y = minf(ground(a), minf(ground(b), ground(mid)))
	var xf := Transform3D(Basis(Vector3.UP, ang), mid)
	bx("stonewall", xf, Vector3(0, -0.6, 0), Vector3(1.4, 1.6, L), STONE)
	bx("plaster", xf, Vector3(0, h * 0.5, 0), Vector3(1.0, h, L), colr)
	if lines:
		for k in 5:
			bx("plaster", xf, Vector3(0, h * 0.35 + k * 0.22, 0), Vector3(1.04, 0.07, L), Color(0.98, 0.98, 0.96))
	roof(xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), h + 0.05, L * 0.5 + 0.2, 0.95, 0.55, "gable", "rooftile", TILE_DARK, 0.0)
	col(xf, Vector3(0, h * 0.5, 0), Vector3(1.0, h + 0.8, L))
	t.paint_line(t.plaza, Vector2(a.x, a.z), Vector2(b.x, b.z), 1.6, 0.6, 1.0)
	t.occupy_rect(Vector2(mid.x, mid.z), -ang + PI * 0.5, L * 0.5, 0.8)


## 築地塀で囲う（ゲートの隙間付き）。corners はワールド座標の四隅（時計回り）
func wall_loop(corners: Array, gate_w := 8.0, h := 2.8, colr := OCHRE, kind := "tsuiji", gates := [0, 1, 2, 3]) -> void:
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		if i in gates:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_wall_seg(a, mid - dir * gate_w * 0.5, h, colr, kind)
			_wall_seg(mid + dir * gate_w * 0.5, b, h, colr, kind)
		else:
			_wall_seg(a, b, h, colr, kind)


func _wall_seg(a: Vector3, b: Vector3, h: float, colr: Color, kind: String) -> void:
	match kind:
		"palisade": palisade(a, b, h)
		"fence": wood_fence(a, b, h)
		"stone": stone_wall(a, b, h)
		"brick": brick_wall(a, b, h)
		_: tsuiji(a, b, h, colr)


func _u_wood_fence(a: Vector3, b: Vector3, h := 1.8) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	if L < 0.3:
		return
	var ang := atan2(d.x, d.z)
	var mid := (a + b) * 0.5
	mid.y = ground(mid)
	var xf := Transform3D(Basis(Vector3.UP, ang), mid)
	bx("darkwood", xf, Vector3(0, h * 0.5 - 0.3, 0), Vector3(0.12, h + 0.6, L), Color(0.8, 0.72, 0.62))
	var n := int(L / 2.0) + 1
	for k in n:
		bx("wood", xf, Vector3(0, h * 0.5 - 0.3, -L * 0.5 + L * k / maxf(n - 1, 1)), Vector3(0.18, h + 0.65, 0.18), DARK)
	col(xf, Vector3(0, h * 0.5, 0), Vector3(0.2, h, L))


func _u_stone_wall(a: Vector3, b: Vector3, h := 2.0) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	if L < 0.3:
		return
	var ang := atan2(d.x, d.z)
	var mid := (a + b) * 0.5
	mid.y = minf(ground(a), ground(b))
	var xf := Transform3D(Basis(Vector3.UP, ang), mid)
	bx("stonewall", xf, Vector3(0, h * 0.5 - 0.7, 0), Vector3(1.6, h + 1.4, L), STONE)
	col(xf, Vector3(0, h * 0.5, 0), Vector3(1.6, h, L))
	t.occupy_rect(Vector2(mid.x, mid.z), -ang + PI * 0.5, L * 0.5, 0.9)


func _u_brick_wall(a: Vector3, b: Vector3, h := 1.6) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	if L < 0.3:
		return
	var ang := atan2(d.x, d.z)
	var mid := (a + b) * 0.5
	mid.y = minf(ground(a), ground(b))
	var xf := Transform3D(Basis(Vector3.UP, ang), mid)
	bx("brick", xf, Vector3(0, h * 0.5 - 0.5, 0), Vector3(0.5, h + 1.0, L))
	bx("plaster", xf, Vector3(0, h + 0.05, 0), Vector3(0.6, 0.12, L + 0.1), STONE)
	col(xf, Vector3(0, h * 0.5, 0), Vector3(0.5, h, L))


## 門（楼門=two_story / 四脚門 / 長屋門 / 冠木門）
func _u_gate(xf: Transform3D, wd := 8.0, kind := "romon", colr := VERMILION) -> void:
	var dp := 4.0 if kind == "romon" else 3.0
	var h := 5.0 if kind == "romon" else 3.8
	var pmat := "plaster" if colr == VERMILION else "wood"
	foundation(xf, wd + 1.0, dp + 1.0, 0.4)
	for i in 4:
		for j in 2:
			var x := -wd * 0.5 + wd * i / 3.0
			cyl(pmat, xf, Vector3(x, 0.4, -dp * 0.5 + dp * j), 0.26, 0.24, h, 8, colr)
	# 両脇の壁（中央は通路）
	for sgn in [-1.0, 1.0]:
		bx("plaster", xf, Vector3(sgn * wd * 0.42, 0.4 + h * 0.5, 0), Vector3(wd * 0.16, h, dp * 0.3), PLASTER)
		col(xf, Vector3(sgn * wd * 0.42, h * 0.5, 0), Vector3(wd * 0.18, h, dp))
	bx(pmat, xf, Vector3(0, 0.4 + h, 0), Vector3(wd + 0.4, 0.35, dp + 0.4), colr)
	bx("darkwood", xf, Vector3(0, 0.4 + h + 0.4, 0), Vector3(wd + 1.0, 0.5, dp + 1.0), DARK)
	if kind == "romon":
		roof(xf, h + 1.0, wd * 0.5 + 1.8, dp * 0.5 + 1.8, 0.8, "hip", "rooftile", TILE_DARK, 0.4)
		var y2 := h + 1.6
		bx("plaster", xf, Vector3(0, y2 + 1.5, 0), Vector3(wd * 0.8, 3.0, dp * 0.8), PLASTER)
		for i in 4:
			for z in [-dp * 0.4, dp * 0.4]:
				cyl(pmat, xf, Vector3(-wd * 0.4 + wd * 0.8 * i / 3.0, y2, z), 0.2, 0.2, 3.0, 6, colr)
		bx("darkwood", xf, Vector3(0, y2 + 3.2, 0), Vector3(wd * 0.8 + 0.8, 0.45, dp * 0.8 + 0.8), DARK)
		roof(xf, y2 + 3.4, wd * 0.4 + 2.2, dp * 0.4 + 2.2, 2.2, "irimoya", "rooftile", TILE_DARK, 0.6)
		col(xf, Vector3(0, y2 + 1.5, 0), Vector3(wd, 3.0 + 3.0, dp))
	elif kind == "nagaya":
		roof(xf, h + 0.9, wd * 0.5 + 1.0, dp * 0.5 + 1.0, 1.8, "irimoya", "rooftile", TILE_DARK, 0.2)
	elif kind == "kabuki":
		bx("wood", xf, Vector3(0, h - 0.1, 0), Vector3(wd + 1.2, 0.35, 0.35), DARK)
	else:
		roof(xf, h + 0.9, wd * 0.5 + 1.2, dp * 0.5 + 1.2, 1.6, "gable", "rooftile", TILE_DARK, 0.3)
	t.occupy_rect(Vector2(xf.origin.x, xf.origin.z), -xf.basis.get_euler().y, wd * 0.5, 0.5)


## 寝殿造: 寝殿＋対屋＋渡殿＋池＋釣殿＋築地塀
func shinden(lm_xf: Transform3D, lx: float, lz: float, size := 46.0) -> void:
	var c := place(lm_xf, lx, lz, 0.0, Vector2(size, size))
	var hs := size * 0.5
	var pillar := Color(0.88, 0.8, 0.7)
	var o := {"base_h": 0.3, "wall_h": 3.2, "pillar": pillar, "pillar_mat": "wood", "roof_mat": "thatch", "roof_col": BARK, "roof": "irimoya", "over": 1.8, "raised": true, "lift": 0.0, "rise": 0.38, "door_mat": "wood", "base_mat": "earth", "base_col": Color(0.8, 0.75, 0.68)}
	# 寝殿の幅は対屋と重ならないように（中に入れるので）
	var sw := clampf(hs * 1.24 - 7.6, 10.0, 16.0)
	jp_hall(c * Transform3D(Basis(), Vector3(0, 0, -hs * 0.35)), sw, 9.0, o)
	jp_hall(c * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-hs * 0.62, 0, -hs * 0.2)), 11.0, 7.0, o)
	jp_hall(c * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hs * 0.62, 0, -hs * 0.2)), 11.0, 7.0, o)
	# 渡殿
	for sgn in [-1.0, 1.0]:
		var p0 := Vector3(sgn * (sw * 0.5 + 0.5), 0, -hs * 0.35)
		var p1 := Vector3(sgn * (hs * 0.62 - 3.6), 0, -hs * 0.35)
		var mid := (p0 + p1) * 0.5
		var cx := c * Transform3D(Basis(), mid)
		var L := absf(p1.x - p0.x)
		bx("wood", cx, Vector3(0, 1.4, 0), Vector3(L, 0.2, 2.6), Color(0.9, 0.85, 0.8))
		for k in int(L / 2.5) + 1:
			for zz in [-1.2, 1.2]:
				cyl("wood", cx, Vector3(-L * 0.5 + k * L / int(L / 2.5), 0, zz), 0.11, 0.11, 3.6, 6, pillar)
		roof(cx, 3.6, L * 0.5 + 0.5, 1.9, 0.9, "gable", "thatch", BARK, 0.0)
	# 池と中島（南庭）
	w.pond_requests.append({"center": c * Vector3(0, 0, hs * 0.3), "rx": hs * 0.55, "rz": hs * 0.25, "angle": c.basis.get_euler().y})
	# 釣殿
	var tsuri := c * Transform3D(Basis(), Vector3(hs * 0.55, 0, hs * 0.18))
	for cx in [-1.5, 1.5]:
		for cz in [-1.5, 1.5]:
			cyl("wood", tsuri, Vector3(cx, -1.5, cz), 0.12, 0.12, 4.6, 6, pillar)
	bx("wood", tsuri, Vector3(0, 1.0, 0), Vector3(4.0, 0.2, 4.0), Color(0.9, 0.85, 0.8))
	roof(tsuri, 3.1, 2.6, 2.6, 1.3, "irimoya", "thatch", BARK, 0.0)
	# 白砂の南庭
	t.paint_rect(t.plaza, Vector2(c.origin.x, c.origin.z), -c.basis.get_euler().y, hs * 0.9, hs * 0.9, 0.8, 2.0)
	var corners := [c * Vector3(-hs, 0, -hs), c * Vector3(hs, 0, -hs), c * Vector3(hs, 0, hs), c * Vector3(-hs, 0, hs)]
	wall_loop(corners, 6.0, 2.6, Color(0.92, 0.88, 0.8), "tsuiji", [2])
	gate(c * Transform3D(Basis(), Vector3(0, 0, hs)), 5.0, "shikyaku", pillar)
	for k in 4:
		w.deco_trees.append(["sakura" if k % 2 == 0 else "pine", c * Vector3(rng.randf_range(-hs * 0.7, hs * 0.7), 0, hs * 0.75 + rng.randf_range(-2, 2)), rng.randf_range(0.6, 0.9)])


## 町家（ローカル +Z が通り側）。入口は通り庭の側（左）、二階へは箱階段
func _u_machiya(xf: Transform3D, wd := 6.0, dp := 11.0, stories := 2, o := {}) -> void:
	var wall: Color = o.get("wall", PLASTER.lerp(OCHRE, rng.randf() * 0.4))
	var h1 := 3.0
	foundation(xf, wd, dp, 0.3)
	var dw := 1.2
	var dh := 2.1
	var door_x := -wd * 0.5 + 0.95
	var fz := dp * 0.5 - 0.8
	var two := stories >= 2
	# 箱階段: 右の壁沿いに奥へ上る
	var st_w := 0.85
	var sx := wd * 0.5 - 0.2 - st_w * 0.5
	var z_b := fz - 2.3
	var z_t := z_b - 2.9
	var hole := Rect2(sx - st_w * 0.5 - 0.05, z_t, st_w + 0.1, z_b - z_t) if two else Rect2()
	shell("plaster", xf, Vector3(0, 0.3 + h1 * 0.5, -0.4), Vector3(wd - 0.1, h1, dp - 0.8), wall, [{"side": 0, "u": door_x, "w": dw, "h": dh}], {"th": 0.15, "hole": hole})
	# 正面の格子と暗い内部（入口だけ抜く）
	slab("darkwood", xf, Vector3(0, 0.3 + h1 * 0.45, dp * 0.5 - 0.45), Vector3(wd - 0.3, h1 * 0.9, 0.1), Color(0.25, 0.2, 0.18), [{"u": door_x, "w": dw + 0.1, "h": dh}], false)
	var n := int(wd / 0.16)
	for k in n:
		if k % 2 == 0:
			var lx := -wd * 0.5 + 0.15 + k * (wd - 0.3) / n
			if absf(lx - door_x) < dw * 0.5 + 0.08:
				continue
			bx("wood", xf, Vector3(lx, 0.3 + h1 * 0.42, dp * 0.5 - 0.35), Vector3(0.05, h1 * 0.78, 0.05), Color(0.55, 0.4, 0.32))
	# 暖簾（無い家は格子戸を開けてある）
	var has_noren := rng.randf() < 0.5
	var nc := Color(0.15, 0.2, 0.42)
	if has_noren:
		nc = [Color(0.15, 0.2, 0.42), Color(0.55, 0.15, 0.12), Color(0.2, 0.32, 0.22), Color(0.82, 0.78, 0.7)][rng.randi() % 4]
		rng.randf_range(-wd * 0.2, wd * 0.2)   # 旧配置の乱数（以降の並びを保つ）
	door_frame(xf, door_x, 0.3, dp * 0.5 - 0.42, dw, dh, "noren" if has_noren else "slide", DARK, nc)
	entry_steps(xf, door_x, dp * 0.5, 0.3, dw + 0.3)
	# 柱
	for sgn in [-1.0, 1.0]:
		bx("wood", xf, Vector3(sgn * (wd * 0.5 - 0.1), 0.3 + h1 * 0.5, dp * 0.5 - 0.35), Vector3(0.2, h1, 0.2), DARK)
	# 庇
	shed(xf, Vector3(0, 0.3 + h1 + 0.25, dp * 0.5 + 0.2), wd + 0.1, 1.5, 0.45)
	var top := 0.3 + h1
	if two:
		var h2 := 2.2
		shell("plaster", xf, Vector3(0, top + h2 * 0.5, -0.6), Vector3(wd - 0.1, h2, dp - 1.4), wall, [], {"th": 0.15, "cap": false})
		# 虫籠窓
		for k in 2:
			bx("darkwood", xf, Vector3(-wd * 0.22 + k * wd * 0.44, top + h2 * 0.55, dp * 0.5 - 1.28), Vector3(wd * 0.28, h2 * 0.4, 0.06), Color(0.2, 0.17, 0.15))
		top += h2
	roof(xf, top + 0.1, wd * 0.5 + 0.35, dp * 0.5 + 0.3, 2.0 if two else 2.3, "gable", "rooftile", TILE_DARK.lerp(TILE, rng.randf()), 0.0, Color(0.45, 0.38, 0.32), 1.15)
	col(xf, Vector3(0, top + 0.6, -0.3), Vector3(wd, 1.0, dp - 0.6))
	occupy(xf, wd, dp, 0.0)
	var floors: Array = [fl(0.3, Rect2(-wd * 0.5 + 0.2, -dp * 0.5 + 0.15, wd - 0.4, dp - 1.1), h1,
		{"hole": hole, "stair": {"a": Vector3(sx, 0.3, z_b), "b": Vector3(sx, 0.3 + h1, z_t), "w": st_w} if two else {}})]
	if two:
		floors.append(fl(0.3 + h1, Rect2(-wd * 0.5 + 0.2, -dp * 0.5 + 0.25, wd - 0.4, dp - 1.7), 2.2))
	var dd := door(Vector3(door_x, 0.3, fz), Vector3.BACK, dw, dh)
	dd["out"] = Vector3(door_x, 0.0, dp * 0.5 + 1.8)
	var kind := "machiya"
	if w.era_id == "edo" and landmark == "battlefield":
		kind = "chaya"
	elif w.era_id == "edo" and not two:
		kind = "nagaya"
	reg_interior(kind, xf, floors, [dd], {"doma_x": door_x, "noren": nc if has_noren else Color(0, 0, 0, 0)})


## 片流れの庇（正面 +Z に向かって下がる）
func shed(xf: Transform3D, c: Vector3, wd: float, depth: float, drop: float, mat := "rooftile", colr := TILE_DARK) -> void:
	var ang := atan2(drop, depth)
	kit.box(mat, xf * Transform3D(Basis(Vector3.RIGHT, ang), c), Vector3(wd, 0.12, Vector2(depth, drop).length()), colr)


## 民家（切妻・板葺/茅葺/瓦）。入口は左寄りの土間口
func _u_minka(xf: Transform3D, wd := 8.0, dp := 6.0, roof_mat := "thatch") -> void:
	foundation(xf, wd + 0.4, dp + 0.4, 0.3, "stonewall", STONE)
	var wall := Color(0.82, 0.72, 0.58) if roof_mat != "rooftile" else Color(0.9, 0.86, 0.78)
	var door_x := -wd / 3.0
	var dw := 1.3
	var dh := 2.0
	shell("plaster", xf, Vector3(0, 0.3 + 1.3, 0), Vector3(wd, 2.6, dp), wall, [{"side": 0, "u": door_x, "w": dw, "h": dh}], {"th": 0.15})
	slab("darkwood", xf, Vector3(0, 0.3 + 0.55, dp * 0.5 + 0.03), Vector3(wd, 1.1, 0.06), Color(0.8, 0.7, 0.6), [{"u": door_x, "w": dw, "h": 1.2}], false)
	for i in 4:
		bx("wood", xf, Vector3(-wd * 0.5 + wd * i / 3.0, 0.3 + 1.3, dp * 0.5 + 0.05), Vector3(0.18, 2.6, 0.18), DARK)
	door_frame(xf, door_x, 0.3, dp * 0.5, dw, dh, "slide")
	var rc := THATCH if roof_mat == "thatch" else (TILE_DARK if roof_mat == "rooftile" else Color(0.6, 0.5, 0.42))
	var rm := roof_mat if roof_mat != "board" else "darkwood"
	roof(xf, 2.95, wd * 0.5 + 0.7, dp * 0.5 + 0.8, 2.4 if roof_mat == "thatch" else 1.7, "gable", rm, rc, 0.0, Color(0.5, 0.4, 0.3), 1.0)
	if roof_mat == "board":
		# 石置き屋根の押さえ石
		for k in 4:
			kit.sphere("stonewall", xf * Transform3D(Basis(), Vector3(-wd * 0.3 + k * wd * 0.2, 2.95 + 1.0, dp * 0.25)), 0.25, 6, 4, STONE)
	col(xf, Vector3(0, 3.3, 0), Vector3(wd, 0.7, dp))
	var run := entry_steps(xf, door_x, dp * 0.5 + 0.2, 0.3, dw + 0.3)
	occupy(xf, wd + 0.6, dp + 0.6, 1.2)
	var dd := door(Vector3(door_x, 0.3, dp * 0.5), Vector3.BACK, dw, dh)
	dd["out"] = Vector3(door_x, 0.0, dp * 0.5 + 0.2 + run + 1.4)
	reg_interior("showa_house" if w.era_id == "showa" else "minka", xf, [fl(0.3, Rect2(-wd * 0.5 + 0.15, -dp * 0.5 + 0.15, wd - 0.3, dp - 0.3), 2.6)], [dd],
		{"doma_x": door_x, "roof_mat": roof_mat})


## 農家（茅葺き入母屋）。土間口は右寄り
func _u_farmhouse(xf: Transform3D, wd := 10.0, dp := 7.0) -> void:
	foundation(xf, wd + 0.6, dp + 0.6, 0.35, "stonewall", STONE)
	var door_x := wd * 0.375
	var dw := minf(1.8, wd * 0.25 - 0.4)
	var dh := 2.1
	shell("plaster", xf, Vector3(0, 0.35 + 1.4, 0), Vector3(wd, 2.8, dp), Color(0.86, 0.76, 0.6), [{"side": 0, "u": door_x, "w": dw, "h": dh}], {"th": 0.16})
	slab("darkwood", xf, Vector3(0, 0.35 + 0.6, dp * 0.5 + 0.02), Vector3(wd, 1.2, 0.06), Color(0.85, 0.75, 0.65), [{"u": door_x, "w": dw, "h": 1.3}], false)
	for i in 5:
		bx("wood", xf, Vector3(-wd * 0.5 + wd * i / 4.0, 0.35 + 1.4, dp * 0.5 + 0.05), Vector3(0.2, 2.8, 0.2), DARK)
	# 縁側
	bx("wood", xf, Vector3(-wd * 0.1, 0.75, dp * 0.5 + 0.6), Vector3(wd * 0.6, 0.12, 1.0), Color(0.85, 0.75, 0.65))
	door_frame(xf, door_x, 0.35, dp * 0.5, dw, dh, "slide")
	roof(xf, 3.2, wd * 0.5 + 1.2, dp * 0.5 + 1.2, 4.6, "irimoya", "thatch", THATCH.lerp(Color(0.8, 0.72, 0.58), rng.randf()), 0.0, Color(0.5, 0.4, 0.3), 1.05)
	col(xf, Vector3(0, 3.7, 0), Vector3(wd, 1.0, dp))
	var run := entry_steps(xf, door_x, dp * 0.5 + 0.3, 0.35, dw + 0.3)
	occupy(xf, wd + 1.5, dp + 1.5, 1.8)
	var dd := door(Vector3(door_x, 0.35, dp * 0.5), Vector3.BACK, dw, dh)
	dd["out"] = Vector3(door_x, 0.0, dp * 0.5 + 0.3 + run + 1.4)
	reg_interior("farmhouse", xf, [fl(0.35, Rect2(-wd * 0.5 + 0.16, -dp * 0.5 + 0.16, wd - 0.32, dp - 0.32), 2.8)], [dd], {"doma_x": door_x})


## 土蔵（観音開きの土扉）
func _u_kura(xf: Transform3D, wd := 5.0, dp := 6.5, h := 5.0) -> void:
	foundation(xf, wd + 0.4, dp + 0.4, 0.5)
	var dw := 1.2
	var dh := 2.2
	var ops := [{"side": 0, "u": 0.0, "w": dw, "h": dh}]
	shell("plaster", xf, Vector3(0, 0.5 + h * 0.5, 0), Vector3(wd, h, dp), PLASTER, ops, {"th": 0.3})
	band("stonewall", xf, Vector3(0, 0.5 + 0.7, 0), Vector3(wd + 0.06, 1.4, dp + 0.06), Color(0.45, 0.45, 0.48), ops, 0.2)
	door_frame(xf, 0.0, 0.5, dp * 0.5 + 0.03, dw, dh, "leaves", Color(0.3, 0.28, 0.26))
	bx("darkwood", xf, Vector3(0, 0.5 + h * 0.78, dp * 0.5 + 0.06), Vector3(0.8, 0.7, 0.1), BLACK)
	roof(xf, 0.5 + h + 0.15, wd * 0.5 + 0.5, dp * 0.5 + 0.6, 1.9, "gable", "rooftile", TILE_DARK, 0.0, Color(0.9, 0.9, 0.88), 1.1)
	col(xf, Vector3(0, 0.5 + h + 0.8, 0), Vector3(wd, 1.2, dp))
	var run := entry_steps(xf, 0.0, dp * 0.5 + 0.2, 0.5, dw + 0.4)
	occupy(xf, wd + 0.5, dp + 0.5, 1.0)
	var dd := door(Vector3(0, 0.5, dp * 0.5), Vector3.BACK, dw, dh)
	dd["out"] = Vector3(0, 0.0, dp * 0.5 + 0.2 + run + 1.4)
	reg_interior("kura", xf, [fl(0.5, Rect2(-wd * 0.5 + 0.3, -dp * 0.5 + 0.3, wd - 0.6, dp - 0.6), h)], [dd])


## 武家屋敷（塀・門・主屋・蔵）
func buke_yashiki(lm_xf: Transform3D, lx: float, lz: float, rot: float, size := 32.0, roof_mat := "rooftile") -> void:
	var c := place(lm_xf, lx, lz, rot, Vector2(size, size))
	var hs := size * 0.5
	var corners := [c * Vector3(-hs, 0, -hs), c * Vector3(hs, 0, -hs), c * Vector3(hs, 0, hs), c * Vector3(-hs, 0, hs)]
	if roof_mat == "rooftile":
		wall_loop(corners, 5.0, 2.4, PLASTER, "tsuiji", [2])
		gate(c * Transform3D(Basis(), Vector3(0, 0, hs)), 5.0, "yakui", Color(0.8, 0.72, 0.62))
	else:
		wall_loop(corners, 5.0, 1.8, PLASTER, "fence", [2])
		gate(c * Transform3D(Basis(), Vector3(0, 0, hs)), 4.5, "kabuki", Color(0.8, 0.72, 0.62))
	jp_hall(c * Transform3D(Basis(), Vector3(-2, 0, -hs * 0.25)), 15.0, 9.0, {"base_h": 0.5, "wall_h": 3.0, "pillar": Color(0.85, 0.75, 0.62), "pillar_mat": "wood",
		"roof_mat": roof_mat, "roof_col": TILE_DARK if roof_mat == "rooftile" else BARK, "roof": "irimoya", "over": 1.5, "lift": 0.2, "door_mat": "wood", "door_col": Color(0.95, 0.92, 0.85)})
	kura(c * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hs * 0.6, 0, -hs * 0.45)), 4.5, 6.0, 4.6)
	t.paint_rect(t.plaza, Vector2(c.origin.x, c.origin.z), -c.basis.get_euler().y, hs * 0.92, hs * 0.92, 0.6, 1.5)
	w.deco_trees.append(["pine", c * Vector3(hs * 0.55, 0, hs * 0.5), 0.7])


## 日本の城（石垣＋多層天守＋隅櫓＋塀）
func castle(xf: Transform3D, base_w := 40.0, base_h := 11.0, tiers := 5, wall_col := PLASTER, accent := false) -> void:
	# 石垣（勾配付き台形）
	var top_w := base_w - base_h * 0.6
	_ishigaki(xf, base_w, base_w, top_w, top_w, base_h)
	var y := base_h
	# 天守
	var tw := top_w * 0.55
	var td := tw * 0.82
	var lower_col := BLACK if accent else wall_col
	_ishigaki(xf * Transform3D(Basis(), Vector3(0, y, 0)), tw + 2.0, td + 2.0, tw + 1.0, td + 1.0, 1.2)
	y += 1.2
	begin_unit("castle_keep", xf * Transform3D(Basis(), Vector3(0, y, 0)), {"kind_detail": "tenshu", "tiers": tiers})
	# 各層の寸法を先に決める（階段の吹き抜けを上下の層で揃えるため）
	var ti: Array = []
	var yy := y
	for i in tiers:
		var k := 1.0 - i * 0.14
		var last := i == tiers - 1
		var hh := 4.2 if i == 0 else 3.4
		var rise := (2.4 if last else 1.35)
		ti.append({"ww": tw * k, "dd": td * k, "hh": hh, "y": yy, "rise": rise, "last": last})
		yy += hh + rise * (0.25 if not last else 0.0)
	# 階段（i 層から i+1 層へ。45°、層ごとに向きと位置を交互に）
	var stairs: Array = []
	for i in tiers - 1:
		var nx: Dictionary = ti[i + 1]
		var rise_f: float = float(nx["y"]) - float(ti[i]["y"])
		var sz := (1.0 if i % 2 == 0 else -1.0) * (float(nx["dd"]) * 0.5 - 1.1)
		var sd := 1.0 if i % 2 == 0 else -1.0
		var sa := Vector3(-sd * rise_f * 0.5, float(ti[i]["y"]), sz)
		var sb := Vector3(sd * rise_f * 0.5, float(nx["y"]), sz)
		stairs.append({"a": sa, "b": sb, "w": 1.0, "hole": Rect2(-rise_f * 0.5 - 0.1, sz - 0.6, rise_f + 0.2, 1.2)})
	var floors: Array = []
	var y_top := y
	for i in tiers:
		var t_: Dictionary = ti[i]
		var ww: float = t_["ww"]
		var dd: float = t_["dd"]
		var hh: float = t_["hh"]
		var ty: float = t_["y"]
		var last: bool = t_["last"]
		var body_col := wall_col
		# 窓（連子窓。内から外が見える）と入口
		var ops: Array = []
		var wy := hh * 0.66 - 0.45
		var nwin := maxi(2, int(ww / 3.0))
		for j in nwin:
			var wx := -ww * 0.5 + ww * (j + 0.5) / nwin
			ops.append({"side": 2, "u": wx, "y": wy, "w": 1.0, "h": 0.9})
			if i == 0 and absf(wx) < 1.6:
				continue
			ops.append({"side": 0, "u": wx, "y": wy, "w": 1.0, "h": 0.9})
		var nwin2 := maxi(2, int(dd / 3.0))
		for j in nwin2:
			var wz := -dd * 0.5 + dd * (j + 0.5) / nwin2
			ops.append({"side": 1, "u": wz, "y": wy, "w": 1.0, "h": 0.9})
			ops.append({"side": 3, "u": wz, "y": wy, "w": 1.0, "h": 0.9})
		var door_ops: Array = []
		if i == 0:
			door_ops = [{"side": 0, "u": 0.0, "w": 1.8, "h": 2.6}]
		var hole: Rect2 = stairs[i]["hole"] if i < stairs.size() else Rect2()
		var fhole: Rect2 = stairs[i - 1]["hole"] if i > 0 else Rect2()
		shell("plaster", xf, Vector3(0, ty + hh * 0.5, 0), Vector3(ww, hh, dd), body_col, ops + door_ops,
			{"th": 0.25, "cap": false, "hole": hole, "floor": i > 0, "floor_hole": fhole, "floor_col": Color(0.8, 0.68, 0.52)})
		# 下見板（黒）
		band("darkwood", xf, Vector3(0, ty + hh * 0.25, 0), Vector3(ww + 0.06, hh * 0.5, dd + 0.06), BLACK if accent or i == 0 else Color(0.32, 0.3, 0.3), door_ops, 0.28)
		for op in ops:
			_renji(xf, int(op["side"]), float(op["u"]), ty + wy + 0.45, ww, dd)
		if accent:
			bx("gold", xf, Vector3(0, ty + hh - 0.15, 0), Vector3(ww + 0.1, 0.18, dd + 0.1), GOLD)
		var hw := ww * 0.5 + 1.6
		var hd := dd * 0.5 + 1.6
		var rise: float = t_["rise"]
		# 下の層の屋根は上の層の床の下で平らに抑える（上の層の部屋に屋根が突き出さない）
		var clamp: Array = []
		if not last:
			var nx2: Dictionary = ti[i + 1]
			clamp = [Rect2(-float(nx2["ww"]) * 0.5 + 0.12, -float(nx2["dd"]) * 0.5 + 0.12, float(nx2["ww"]) - 0.24, float(nx2["dd"]) - 0.24), float(nx2["y"]) - (ty + hh) - 0.08]
		roof(xf, ty + hh, hw, hd, rise, "irimoya" if (last or i % 2 == 0) else "hip", "rooftile", TILE_DARK, 0.55, PLASTER, 1.35, clamp)
		# 屋根の当たり判定（壁の外側の軒の輪。上の層の中には入れない）
		if last:
			col(xf, Vector3(0, ty + hh + rise * 0.45, 0), Vector3(ww + 3.2, rise * 0.9, dd + 3.2))
		else:
			for sgn in [-1.0, 1.0]:
				col(xf, Vector3(0, ty + hh + rise * 0.3, sgn * (dd * 0.5 + 0.8)), Vector3(ww + 3.2, rise * 0.6, 1.6))
				col(xf, Vector3(sgn * (ww * 0.5 + 0.8), ty + hh + rise * 0.3, 0), Vector3(1.6, rise * 0.6, dd))
		# 千鳥破風
		if not last and i % 2 == 1:
			for sgn in [-1.0, 1.0]:
				var px := xf * Transform3D(Basis(Vector3.UP, PI * 0.5 if sgn > 0 else -PI * 0.5), Vector3(0, ty + hh + 0.3, sgn * (dd * 0.5 + 0.6)))
				kit.roof(px, 1.3, 1.3, 1.5, 1.0, "rooftile", "plaster", TILE_DARK, 1.1, 0.25, 0.25, PLASTER, "plaster", wall_col)   # 上の層の壁の外に収まる幅
		if accent and last:
			for sgn in [-1.0, 1.0]:
				var hx := ww * 0.5 + 1.6 - (dd * 0.5 + 1.6) + (dd * 0.5 + 1.6) * 0.42
				kit.box("gold", xf * Transform3D(Basis(), Vector3(sgn * hx, ty + hh + rise + 0.8, 0)), Vector3(0.5, 1.2, 0.35), GOLD)
		var win: Array = []
		for op in ops:
			win.append(op)
		floors.append(fl(ty, Rect2(-ww * 0.5 + 0.25, -dd * 0.5 + 0.25, ww - 0.5, dd - 0.5), hh,
			{"hole": hole, "stair": stairs[i] if i < stairs.size() else {}, "tier": i, "last": last, "win": win}))
		y_top = ty + hh
	y = y_top
	if not accent:
		var hx := tw * (1.0 - (tiers - 1) * 0.14) * 0.5 + 1.6 - ((td * (1.0 - (tiers - 1) * 0.14)) * 0.5 + 1.6) * 0.58
		for sgn in [-1.0, 1.0]:
			kit.box("gold", xf * Transform3D(Basis(), Vector3(sgn * hx, y + 2.4 + 0.9, 0)), Vector3(0.45, 1.1, 0.3), GOLD)
	# 天守台の石段（本丸から一層目の入口へ）
	var kx := xf * Transform3D(Basis(), Vector3(0, base_h, 0))
	var run := entry_steps(kx, 0.0, (td + 1.0) * 0.5, 1.2, 2.4)
	door_frame(xf, 0.0, float(ti[0]["y"]), td * 0.5, 1.8, 2.6, "leaves", BLACK if accent else Color(0.3, 0.28, 0.27))
	var dd0 := door(Vector3(0, float(ti[0]["y"]), td * 0.5), Vector3.BACK, 1.8, 2.6)
	dd0["out"] = Vector3(0, base_h, (td + 1.0) * 0.5 + run + 1.5)
	reg_interior("castle", xf, floors, [dd0], {"accent": accent, "tiers": tiers})
	end_unit()
	# 隅櫓と塀
	var ylo := top_w * 0.5 - 6.5
	var yagura_ok := ylo > tw * 0.5 + 0.3 or ylo > td * 0.5 + 0.3   # 小さな本丸では天守と重なるので置かない
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			if not yagura_ok:
				continue
			var p := Vector3(cx * (top_w * 0.5 - 3.5), base_h, cz * (top_w * 0.5 - 3.5))
			var yx := xf * Transform3D(Basis(), p)
			begin_unit("yagura", yx, {"kind_detail": "sumi_yagura"})
			# 入口は本丸の内側へ向ける
			var fx := yx * Transform3D(Basis(Vector3.UP, 0.0 if cz < 0.0 else PI), Vector3.ZERO)
			var yops := [{"side": 0, "u": 0.0, "w": 1.4, "h": 2.2}]
			shell("plaster", fx, Vector3(0, 2.0, 0), Vector3(6, 4, 6), wall_col, yops, {"th": 0.25})
			band("darkwood", fx, Vector3(0, 1.0, 0), Vector3(6.05, 2.0, 6.05), BLACK if accent else Color(0.35, 0.33, 0.32), yops, 0.25)
			door_frame(fx, 0.0, 0.0, 3.0, 1.4, 2.2, "leaves", BLACK if accent else Color(0.3, 0.28, 0.27))
			roof(yx, 4.0, 4.2, 4.2, 1.8, "irimoya", "rooftile", TILE_DARK, 0.4, PLASTER)
			col(yx, Vector3(0, 4.7, 0), Vector3(6, 1.2, 6))
			var ydd := door(Vector3(0, 0, 3.0), Vector3.BACK, 1.4, 2.2)
			reg_interior("yagura", fx, [fl(0.0, Rect2(-2.75, -2.75, 5.5, 5.5), 4.0)], [ydd])
			end_unit()
	var hs := top_w * 0.5 - 0.6
	for side in 4:
		var a := Vector3(-hs, base_h, hs).rotated(Vector3.UP, side * PI * 0.5)
		var b := Vector3(hs, base_h, hs).rotated(Vector3.UP, side * PI * 0.5)
		var mid := (a + b) * 0.5
		var sx := xf * Transform3D(Basis(Vector3.UP, side * PI * 0.5), mid)
		# 塀は 3 区画に分けて壊れる。正面（大手）の中央は開けて本丸に入れる
		var nseg := 3
		var seg_w := (top_w - 8.0) / nseg
		for k in nseg:
			if side == 0 and k == 1:
				continue
			var kx2 := sx * Transform3D(Basis(), Vector3(-(top_w - 8.0) * 0.5 + seg_w * (k + 0.5), 0, 0))
			begin_unit("wall", kx2, {"kind_detail": "castle_wall"})
			bx("plaster", kx2, Vector3(0, 1.1, 0), Vector3(seg_w + 0.02, 2.2, 0.5), wall_col)
			kit.roof(kx2 * Transform3D(Basis(), Vector3(0, 2.2, 0)), seg_w * 0.5, 0.65, 0.4, 1.0, "rooftile", "darkwood", TILE_DARK, 1.0, 0.0, 0.15)
			col(kx2, Vector3(0, 1.1, 0), Vector3(seg_w, 2.2, 0.5))
			end_unit()
	# 正面の登り坂（大手道）
	var rx := xf * Transform3D(Basis(), Vector3(0, 0, base_w * 0.5 + 7.0))
	var ramp_len := 16.0
	var slope := atan2(base_h, ramp_len)
	var ramp_xf := rx * Transform3D(Basis(Vector3.RIGHT, slope), Vector3(0, base_h * 0.5 - 0.3, -2.0))
	kit.box("stonewall", ramp_xf, Vector3(7.0, 0.6, Vector2(ramp_len, base_h).length() + 1.0), STONE)
	cols.append([ramp_xf, Vector3(7.0, 0.6, Vector2(ramp_len, base_h).length() + 1.0)])
	occupy(xf, base_w + 2, base_w + 2, 3.0)


func _ishigaki(xf: Transform3D, bw: float, bd: float, tw: float, td: float, h: float) -> void:
	var b0 := [Vector3(-bw * 0.5, -1.5, bd * 0.5), Vector3(bw * 0.5, -1.5, bd * 0.5), Vector3(bw * 0.5, -1.5, -bd * 0.5), Vector3(-bw * 0.5, -1.5, -bd * 0.5)]
	var t0 := [Vector3(-tw * 0.5, h, td * 0.5), Vector3(tw * 0.5, h, td * 0.5), Vector3(tw * 0.5, h, -td * 0.5), Vector3(-tw * 0.5, h, -td * 0.5)]
	# 反りのある石垣（下が緩く上が急）を 3 段で近似
	var steps := 3
	for s in steps:
		var f0 := float(s) / steps
		var f1 := float(s + 1) / steps
		var e0 := pow(f0, 0.6)
		var e1 := pow(f1, 0.6)
		for i in 4:
			var j := (i + 1) % 4
			var p0: Vector3 = (b0[i] as Vector3).lerp(t0[i], e0)
			var p1: Vector3 = (b0[j] as Vector3).lerp(t0[j], e0)
			var p2: Vector3 = (b0[j] as Vector3).lerp(t0[j], e1)
			var p3: Vector3 = (b0[i] as Vector3).lerp(t0[i], e1)
			p0.y = lerpf(-1.5, h, f0); p1.y = p0.y
			p2.y = lerpf(-1.5, h, f1); p3.y = p2.y
			kit.quad("stonewall", xf * p0, xf * p1, xf * p2, xf * p3, STONE)
	kit.quad("stonewall", xf * t0[0], xf * t0[1], xf * t0[2], xf * t0[3], Color(0.8, 0.78, 0.74))
	col(xf, Vector3(0, (h - 1.5) * 0.5, 0), Vector3((bw + tw) * 0.5, h + 1.5, (bd + td) * 0.5))


## 連子窓（外枠＋縦格子。開口の外面に付ける）
func _renji(xf: Transform3D, side: int, u: float, yc: float, ww: float, dd: float) -> void:
	var c: Vector3
	var rot := 0.0
	match side:
		0: c = Vector3(u, yc, dd * 0.5 + 0.03)
		2: c = Vector3(u, yc, -dd * 0.5 - 0.03)
		1:
			c = Vector3(ww * 0.5 + 0.03, yc, u)
			rot = PI * 0.5
		_:
			c = Vector3(-ww * 0.5 - 0.03, yc, u)
			rot = PI * 0.5
	var fx := xf * Transform3D(Basis(Vector3.UP, rot), c)
	var col_ := Color(0.12, 0.1, 0.1)
	for sgn in [-1.0, 1.0]:
		kit.box("darkwood", fx * Transform3D(Basis(), Vector3(0, sgn * 0.48, 0)), Vector3(1.12, 0.08, 0.1), col_, false)
		kit.box("darkwood", fx * Transform3D(Basis(), Vector3(sgn * 0.53, 0, 0)), Vector3(0.08, 0.9, 0.1), col_)
	for k in 4:
		kit.box("darkwood", fx * Transform3D(Basis(), Vector3(-0.3 + k * 0.2, 0, 0)), Vector3(0.05, 0.9, 0.06), col_)


## 石灯籠
func _u_stone_lantern(p: Vector3, s := 1.0) -> void:
	var xf := Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(p.x, ground(p), p.z))
	bx("stonewall", xf, Vector3(0, 0.15, 0), Vector3(0.7, 0.3, 0.7), STONE)
	kit.cylinder("stonewall", xf * Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.16 * s, 0.14 * s, 1.0 * s, 8, STONE)
	bx("stonewall", xf, Vector3(0, 1.38, 0), Vector3(0.6, 0.16, 0.6), STONE)
	bx("stonewall", xf, Vector3(0, 1.7, 0), Vector3(0.46, 0.5, 0.46), STONE)
	bx("emissive", xf, Vector3(0, 1.7, 0), Vector3(0.48, 0.22, 0.2), Color(1.0, 0.7, 0.35))
	kit.roof(xf * Transform3D(Basis(), Vector3(0, 1.98, 0)), 0.5 * s, 0.5 * s, 0.32 * s, 0.0, "stonewall", "stonewall", STONE, 1.3, 0.12 * s, 0.08 * s, STONE, "", STONE, 3, 3)
	kit.sphere("stonewall", xf * Transform3D(Basis(), Vector3(0, 2.4, 0)), 0.09 * s, 6, 4, STONE)
	col(xf, Vector3(0, 1.1, 0), Vector3(0.6, 2.2, 0.6) * s)


## 提灯・ガス灯・電灯
func _u_lamp(p: Vector3, kind: String) -> void:
	var y := ground(p)
	var xf := Transform3D(Basis(), Vector3(p.x, y, p.z))
	match kind:
		"gas":
			kit.cylinder("metal", xf, 0.12, 0.07, 3.4, 8, Color(0.15, 0.17, 0.16))
			bx("metal", xf, Vector3(0, 3.45, 0), Vector3(0.45, 0.08, 0.45), Color(0.15, 0.17, 0.16))
			bx("emissive", xf, Vector3(0, 3.75, 0), Vector3(0.36, 0.5, 0.36), Color(1.0, 0.8, 0.5))
			kit.roof(xf * Transform3D(Basis(), Vector3(0, 4.0, 0)), 0.32, 0.32, 0.3, 0.0, "metal", "metal", Color(0.15, 0.17, 0.16), 1.0, 0.0, 0.04, Color(0.15, 0.17, 0.16), "", Color.WHITE, 2, 2)
			lamp_points.append(xf.origin + Vector3(0, 3.8, 0))
		"electric":
			kit.cylinder("concrete", xf, 0.14, 0.1, 6.0, 8, Color(0.75, 0.75, 0.72))
			kit.rod("metal", xf * Vector3(0, 5.9, 0), xf * Vector3(1.2, 6.1, 0), 0.05, 5, Color(0.3, 0.3, 0.3))
			bx("emissive", xf, Vector3(1.25, 5.95, 0), Vector3(0.5, 0.12, 0.25), Color(1.0, 0.92, 0.75))
			lamp_points.append(xf.origin + Vector3(1.2, 5.8, 0))
		_:
			kit.cylinder("wood", xf, 0.08, 0.07, 2.2, 6, DARK)
			bx("wood", xf, Vector3(0, 2.25, 0), Vector3(0.5, 0.08, 0.5), DARK)
			kit.cylinder("emissive", xf * Transform3D(Basis(), Vector3(0, 2.3, 0)), 0.22, 0.22, 0.55, 8, Color(1.0, 0.62, 0.3))
			lamp_points.append(xf.origin + Vector3(0, 2.6, 0))
	col(xf, Vector3(0, 1.5, 0), Vector3(0.3, 3.0, 0.3))


## のぼり旗
func _u_nobori(p: Vector3, colr: Color) -> void:
	var y := ground(p)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y, p.z))
	kit.cylinder("wood", xf, 0.04, 0.03, 4.4, 5, DARK, false)
	bx("cloth", xf, Vector3(0.36, 2.9, 0), Vector3(0.66, 2.6, 0.02), colr)
	bx("wood", xf, Vector3(0.36, 4.25, 0), Vector3(0.75, 0.04, 0.04), DARK)


## 陣幕
func _u_jinmaku(a: Vector3, b: Vector3, colr := Color(0.92, 0.9, 0.86)) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	var ang := atan2(d.x, d.z)
	var mid := (a + b) * 0.5
	mid.y = ground(mid)
	var xf := Transform3D(Basis(Vector3.UP, ang), mid)
	bx("cloth", xf, Vector3(0, 1.4, 0), Vector3(0.04, 1.6, L), colr)
	bx("cloth", xf, Vector3(0, 1.4, 0), Vector3(0.05, 0.35, L), Color(0.12, 0.12, 0.14))
	for k in int(L / 3.0) + 1:
		bx("wood", xf, Vector3(0, 1.1, -L * 0.5 + k * 3.0), Vector3(0.1, 2.3, 0.1), DARK)
	col(xf, Vector3(0, 1.1, 0), Vector3(0.2, 2.2, L))


## 馬防柵
func _u_baboosaku(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	var ang := atan2(d.x, d.z)
	var n := int(L / 2.0)
	for k in n + 1:
		var p := a.lerp(b, float(k) / maxf(n, 1))
		p.y = ground(p)
		kit.rod("wood", p + Vector3(0, -0.3, 0), p + Vector3(0, 2.3, 0), 0.08, 5, DARK)
	for yy in [0.6, 1.3, 2.0]:
		kit.rod("wood", Vector3(a.x, ground(a) + yy, a.z), Vector3(b.x, ground(b) + yy, b.z), 0.06, 4, DARK)
	var mid := (a + b) * 0.5
	mid.y = ground(mid)
	cols.append([Transform3D(Basis(Vector3.UP, ang), mid + Vector3(0, 1.1, 0)), Vector3(0.3, 2.2, L)])


## 埴輪
func _u_haniwa(p: Vector3) -> void:
	var xf := Transform3D(Basis(), Vector3(p.x, ground(p), p.z))
	kit.cylinder("earth", xf, 0.28, 0.22, 1.0, 8, Color(1.0, 0.62, 0.42))
	kit.sphere("earth", xf * Transform3D(Basis(), Vector3(0, 1.15, 0)), 0.2, 8, 5, Color(1.0, 0.62, 0.42))


## 市の屋台
func _u_stall(xf: Transform3D, colr: Color) -> void:
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			cyl("wood", xf, Vector3(cx * 1.3, 0, cz * 0.9), 0.06, 0.06, 2.2 + (0.3 if cz < 0 else 0.0), 5, DARK)
	bx("wood", xf, Vector3(0, 0.85, 0), Vector3(2.6, 0.1, 1.6), Color(0.85, 0.75, 0.62))
	var rx := xf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 2.4, 0))
	kit.box("cloth", rx, Vector3(3.0, 0.05, 2.2), colr)
	for k in 4:
		bx("cloth", xf, Vector3(-0.9 + k * 0.6, 1.0, 0), Vector3(0.4, 0.15, 0.4), [Color(0.8, 0.3, 0.2), Color(0.9, 0.8, 0.3), Color(0.3, 0.5, 0.2), Color(0.6, 0.4, 0.3)][k])
	col(xf, Vector3(0, 0.5, 0), Vector3(2.6, 1.0, 1.6))
	occupy(xf, 3, 2.2)


# ================================================================ 近代建築
## 煉瓦造の洋館（明治）。clock=時計塔。正面の玄関から入れる（2 階まで）
var _brick_n := 0


func _u_brick_building(xf: Transform3D, wd := 24.0, dp := 14.0, floors := 3, o := {}) -> void:
	var fh := 4.2
	var wall_mat: String = o.get("mat", "brick")
	var wall_col: Color = o.get("col", Color(1.0, 0.68, 0.58) if wall_mat == "brick" else Color.WHITE)
	var trim: Color = o.get("trim", Color(0.92, 0.9, 0.84))
	var h := floors * fh
	var dw := 2.0
	var dh := 3.0
	var dops := [{"side": 0, "u": 0.0, "w": dw, "h": dh}]
	foundation(xf, wd + 0.4, dp + 0.4, 0.8, "stonewall", Color(0.82, 0.8, 0.76))
	shell(wall_mat, xf, Vector3(0, 0.8 + h * 0.5, 0), Vector3(wd, h, dp), wall_col, dops, {"th": 0.3})
	# 階ごとの帯（外側だけ）
	for f in floors + 1:
		var bh := 0.3 if f < floors else 0.6
		band("plaster", xf, Vector3(0, 0.8 + f * fh, 0), Vector3(wd + 0.3, bh, dp + 0.3), trim, [{"side": 0, "u": 0.0, "w": dw, "h": 1.0}] if f == 0 else [], 0.35)
	# 窓
	var nw := int(wd / 3.2)
	var nd := int(dp / 3.2)
	for f in floors:
		var wy := 0.8 + f * fh + fh * 0.5
		for i in nw:
			var x := -wd * 0.5 + wd * (i + 0.5) / nw
			for sgn in [-1.0, 1.0]:
				if f == 0 and sgn > 0.0 and absf(x) < 2.0:
					continue
				bx("plaster", xf, Vector3(x, wy, sgn * (dp * 0.5 + 0.05)), Vector3(1.4, 2.4, 0.12), trim)
				bx("glass", xf, Vector3(x, wy - 0.05, sgn * (dp * 0.5 + 0.1)), Vector3(1.0, 2.0, 0.06))
				bx("plaster", xf, Vector3(x, wy + 1.35, sgn * (dp * 0.5 + 0.12)), Vector3(1.7, 0.25, 0.2), trim)
		for i in nd:
			var z := -dp * 0.5 + dp * (i + 0.5) / nd
			for sgn in [-1.0, 1.0]:
				bx("plaster", xf, Vector3(sgn * (wd * 0.5 + 0.05), wy, z), Vector3(0.12, 2.4, 1.4), trim)
				bx("glass", xf, Vector3(sgn * (wd * 0.5 + 0.1), wy - 0.05, z), Vector3(0.06, 2.0, 1.0))
	# 隅石
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			bx("plaster", xf, Vector3(cx * wd * 0.5, 0.8 + h * 0.5, cz * dp * 0.5), Vector3(0.7, h, 0.7), trim)
	# 玄関ポーチ（柱＋破風）と石段
	var pz := dp * 0.5 + 1.8
	for k in 4:
		cyl("plaster", xf, Vector3(-3.0 + k * 2.0, 0.8, pz), 0.3, 0.26, fh, 10, trim)
		col(xf, Vector3(-3.0 + k * 2.0, 0.8 + fh * 0.5, pz), Vector3(0.55, fh, 0.55))
	bx("plaster", xf, Vector3(0, 0.8 + fh + 0.3, pz - 0.6), Vector3(7.6, 0.6, 4.4), trim)
	col(xf, Vector3(0, 0.8 + fh + 0.3, pz - 0.6), Vector3(7.6, 0.6, 4.4))
	kit.roof(xf * Transform3D(Basis(), Vector3(0, 0.8 + fh + 0.6, pz - 0.6)), 3.9, 2.4, 1.3, 1.0, "rooftile", "plaster", TILE_DARK, 1.0, 0.0, 0.3, trim, "plaster", trim)
	var run := entry_steps(xf, 0.0, dp * 0.5 + 0.2, 0.8, 3.2, "stonewall", Color(0.82, 0.8, 0.76))
	door_frame(xf, 0.0, 0.8, dp * 0.5, dw, dh, "leaves", Color(0.45, 0.3, 0.22))
	# 屋根
	var rcol: Color = o.get("roof_col", Color(0.42, 0.45, 0.5))
	if o.get("mansard", false):
		roof(xf, 0.8 + h + 0.3, wd * 0.5 + 0.4, dp * 0.5 + 0.4, 2.6, "hip", "rooftile", rcol, 0.0, trim, 0.55)
	else:
		roof(xf, 0.8 + h + 0.3, wd * 0.5 + 0.6, dp * 0.5 + 0.6, minf(wd, dp) * 0.28, "hip", "rooftile", rcol, 0.0, trim, 1.0)
	# 煙突
	for sgn in [-1.0, 1.0]:
		bx(wall_mat, xf, Vector3(sgn * wd * 0.3, 0.8 + h + 2.2, -dp * 0.2), Vector3(0.9, 3.0, 0.9), wall_col)
	if o.get("clock", false):
		_clock_tower(xf * Transform3D(Basis(), Vector3(0, 0, dp * 0.5 - 2.5)), 6.0, 0.8 + h, wall_mat, wall_col, trim, o.get("dome", false))
	if o.get("dome", false) and not o.get("clock", false):
		var dx := xf * Transform3D(Basis(), Vector3(0, 0.8 + h, 0))
		cyl(wall_mat, dx, Vector3.ZERO, 5.0, 5.0, 3.0, 16, wall_col)
		kit.sphere("metal", dx * Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), Vector3(0, 3.0, 0)), 5.0, 16, 8, COPPER)
	col(xf, Vector3(0, 0.8 + h + 1.2, 0), Vector3(wd, 1.8, dp))
	occupy(xf, wd + 1, dp + 5, 2.5)
	# 内装（1・2 階。階段は奥の壁沿い）
	var nfl := mini(floors, 2)
	var inner := Rect2(-wd * 0.5 + 0.3, -dp * 0.5 + 0.3, wd - 0.6, dp - 0.6)
	var sa := Vector3(-wd * 0.5 + 1.6, 0.8, -dp * 0.5 + 1.0)
	var sb := sa + Vector3(fh, fh, 0)
	var flist: Array = [fl(0.8, inner, fh, {"hole": Rect2(sa.x - 0.1, sa.z - 0.7, fh + 0.2, 1.4) if nfl >= 2 else Rect2(),
		"stair": {"a": sa, "b": sb, "w": 1.2} if nfl >= 2 else {}})]
	if nfl >= 2:
		flist.append(fl(0.8 + fh, inner, fh))
	var dd := door(Vector3(0, 0.8, dp * 0.5), Vector3.BACK, dw, dh)
	dd["out"] = Vector3(0, 0, dp * 0.5 + 0.2 + run + 1.6)
	_brick_n += 1
	reg_interior(_brick_interior(o), xf, flist, [dd], {"win_grid": {"nw": nw, "nd": nd, "fh": fh, "y0": 0.8}, "floors_total": floors, "n": _brick_n})


## 洋館の用途: 駅舎・役所・洋館（迎賓）・銀行
func _brick_interior(o: Dictionary) -> String:
	if w.era_id == "showa":
		return "bank"
	match landmark:
		"port":
			return "station"
		"castle":
			return "office"
		"capital":
			return "office" if (o.get("clock", false) or String(o.get("mat", "brick")) == "plaster") else "yokan"
	return "yokan"


func _clock_tower(xf: Transform3D, s: float, y0: float, mat: String, colr: Color, trim: Color, dome: bool) -> void:
	var th := 10.0
	bx(mat, xf, Vector3(0, y0 + th * 0.5, 0), Vector3(s, th, s), colr)
	bx("plaster", xf, Vector3(0, y0 + th, 0), Vector3(s + 0.5, 0.5, s + 0.5), trim)
	for side in 4:
		var r := Basis(Vector3.UP, side * PI * 0.5)
		var face := xf * Transform3D(r, Vector3(0, y0 + th - 2.6, s * 0.5 + 0.02))
		kit.cylinder("plaster", face * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 1.8, 1.8, 0.12, 20, Color(0.98, 0.97, 0.92))
		kit.cylinder("metal", face * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.0)), 1.95, 1.95, 0.06, 20, Color(0.2, 0.2, 0.2), false)
		kit.box("metal", face * Transform3D(Basis(Vector3.BACK, 0.5), Vector3(0.0, 0.5, 0.16)), Vector3(0.12, 1.1, 0.04), Color(0.05, 0.05, 0.05))
		kit.box("metal", face * Transform3D(Basis(Vector3.BACK, -1.9), Vector3(0.55, 0.25, 0.16)), Vector3(0.12, 1.4, 0.04), Color(0.05, 0.05, 0.05))
		# 窓
		kit.box("glass", face * Transform3D(Basis(), Vector3(0, -4.0, 0.05)), Vector3(1.2, 2.6, 0.06))
	if dome:
		kit.sphere("metal", xf * Transform3D(Basis().scaled(Vector3(1, 1.1, 1)), Vector3(0, y0 + th + 0.3, 0)), s * 0.5, 14, 7, COPPER)
	else:
		roof(xf, y0 + th + 0.25, s * 0.5 + 0.4, s * 0.5 + 0.4, 4.5, "pyramid", "rooftile", Color(0.38, 0.42, 0.46), 0.0, trim, 1.0)
	col(xf, Vector3(0, y0 + th * 0.5, 0), Vector3(s, th, s))


## 擬洋風の木造校舎（中央の塔屋が玄関）
func _u_wooden_school(xf: Transform3D, wd := 34.0, dp := 10.0) -> void:
	var h := 7.6
	var siding := Color(0.98, 0.95, 0.85)
	foundation(xf, wd + 0.4, dp + 0.4, 0.6)
	var dops := [{"side": 0, "u": 0.0, "w": 2.0, "h": 2.8}]
	shell("darkwood", xf, Vector3(0, 0.6 + h * 0.5, 0), Vector3(wd, h, dp), siding * 1.4, dops, {"th": 0.2})
	for f in 2:
		var wy := 0.6 + f * 3.8 + 2.0
		var n := int(wd / 2.6)
		for i in n:
			var x := -wd * 0.5 + wd * (i + 0.5) / n
			if absf(x) < 3.0:
				continue
			for sgn in [-1.0, 1.0]:
				bx("wood", xf, Vector3(x, wy, sgn * (dp * 0.5 + 0.04)), Vector3(1.5, 2.2, 0.1), Color(0.55, 0.62, 0.7))
				bx("glass", xf, Vector3(x, wy, sgn * (dp * 0.5 + 0.08)), Vector3(1.2, 1.9, 0.05))
				bx("wood", xf, Vector3(x, wy, sgn * (dp * 0.5 + 0.11)), Vector3(0.06, 1.9, 0.04), Color(0.95, 0.95, 0.95))
	band("wood", xf, Vector3(0, 0.6 + 3.8, 0), Vector3(wd + 0.2, 0.2, dp + 0.2), Color(0.55, 0.62, 0.7), [], 0.3)
	roof(xf, 0.6 + h + 0.1, wd * 0.5 + 0.8, dp * 0.5 + 0.8, 3.2, "hip", "rooftile", TILE_DARK, 0.0, siding)
	# 中央の玄関と塔屋
	var c := xf * Transform3D(Basis(), Vector3(0, 0, dp * 0.5 + 1.5))
	foundation(c, 5.2, 3.8, 0.6)
	shell("darkwood", c, Vector3(0, 0.6 + 5.0, 0), Vector3(5.0, 10.0, 3.6), siding * 1.4,
		[{"side": 0, "u": 0.0, "w": 2.0, "h": 2.8}, {"side": 2, "u": 0.0, "w": 2.0, "h": 2.8}], {"th": 0.2})
	door_frame(c, 0.0, 0.6, 1.8, 2.0, 2.8, "leaves", Color(0.35, 0.28, 0.22))
	var run := entry_steps(c, 0.0, 1.9, 0.6, 2.8, "stonewall", STONE)
	roof(c, 0.6 + 10.0, 3.0, 2.3, 1.6, "irimoya", "rooftile", TILE_DARK, 0.2, siding)
	bx("darkwood", c, Vector3(0, 0.6 + 12.4, 0), Vector3(2.4, 2.4, 2.4), siding * 1.4)
	roof(c, 0.6 + 13.6, 1.6, 1.6, 1.8, "pyramid", "rooftile", TILE_DARK, 0.0, siding)
	col(xf, Vector3(0, 0.6 + h + 1.4, 0), Vector3(wd, 2.4, dp))
	col(c, Vector3(0, 0.6 + 12.4, 0), Vector3(2.4, 2.4, 2.4))
	occupy(xf, wd + 1, dp + 5, 3.0)
	var inner := Rect2(-wd * 0.5 + 0.2, -dp * 0.5 + 0.2, wd - 0.4, dp - 0.4)
	var sa := Vector3(1.4, 0.6, -dp * 0.5 + 0.9)
	var sb := sa + Vector3(3.8, 3.8, 0)
	var dd := door(Vector3(0, 0.6, dp * 0.5 + 3.3), Vector3.BACK, 2.0, 2.8)
	dd["out"] = Vector3(0, 0, dp * 0.5 + 3.4 + run + 1.4)
	reg_interior("school", xf, [
		fl(0.6, inner, 3.8, {"hole": Rect2(sa.x - 0.1, sa.z - 0.65, 4.0, 1.3), "stair": {"a": sa, "b": sb, "w": 1.1}}),
		fl(0.6 + 3.8, inner, 3.8),
		fl(0.6, Rect2(-2.3, dp * 0.5 - 0.1, 4.6, 3.2), 3.6, {"hall": true})], [dd])


## 鉄筋コンクリートのビル（昭和）。1・2 階に入れる
func _u_concrete_building(xf: Transform3D, wd := 18.0, dp := 14.0, floors := 5, o := {}) -> void:
	var fh := 3.4
	var h := floors * fh
	var colr: Color = o.get("col", Color(0.9, 0.88, 0.84).lerp(Color(0.75, 0.72, 0.66), rng.randf()))
	var dw := 2.4
	var dh := 2.5
	var dops := [{"side": 0, "u": 0.0, "w": dw, "h": dh}]
	foundation(xf, wd + 0.3, dp + 0.3, 0.4, "concrete", Color(0.7, 0.7, 0.68))
	shell("concrete", xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h, dp), colr, dops, {"th": 0.3})
	for f in floors:
		var wy := 0.4 + f * fh + fh * 0.55
		for sgn in [-1.0, 1.0]:
			var gc := Color(0.55, 0.62, 0.7) if f > 0 else Color(0.35, 0.4, 0.45)
			if f == 0 and sgn > 0.0:
				# 入口の左右に分ける
				var seg := (wd - 1.2) * 0.5 - 1.6
				for s2 in [-1.0, 1.0]:
					bx("glass", xf, Vector3(s2 * (1.6 + seg * 0.5), wy, dp * 0.5 + 0.03), Vector3(seg, fh * 0.45, 0.06), gc)
			else:
				bx("glass", xf, Vector3(0, wy, sgn * (dp * 0.5 + 0.03)), Vector3(wd - 1.2, fh * 0.45, 0.06), gc)
			bx("glass", xf, Vector3(sgn * (wd * 0.5 + 0.03), wy, 0), Vector3(0.06, fh * 0.45, dp - 1.2), Color(0.55, 0.62, 0.7))
		band("concrete", xf, Vector3(0, 0.4 + f * fh + fh * 0.22, 0), Vector3(wd + 0.25, 0.25, dp + 0.25), colr * 0.95, dops if f == 0 else [], 0.3)
		# 窓の縦桟
		var n := int(wd / 1.8)
		for i in n:
			for sgn in [-1.0, 1.0]:
				var mx := -wd * 0.5 + 0.6 + (wd - 1.2) * i / maxf(n - 1, 1)
				if f == 0 and sgn > 0.0 and absf(mx) < 1.6:
					continue
				bx("concrete", xf, Vector3(mx, wy, sgn * (dp * 0.5 + 0.06)), Vector3(0.12, fh * 0.45, 0.06), colr)
	# 屋上
	bx("concrete", xf, Vector3(0, 0.4 + h + 0.5, 0), Vector3(wd, 1.0, dp), colr * 0.9)
	bx("concrete", xf, Vector3(0, 0.4 + h + 0.05, 0), Vector3(wd - 0.6, 0.1, dp - 0.6), Color(0.5, 0.5, 0.5))
	if o.get("tank", true):
		var tx := xf * Transform3D(Basis(), Vector3(wd * 0.25, 0.4 + h, -dp * 0.2))
		for cx in [-0.8, 0.8]:
			for cz in [-0.8, 0.8]:
				kit.box("metal", tx * Transform3D(Basis(), Vector3(cx, 1.0, cz)), Vector3(0.1, 2.0, 0.1), Color(0.4, 0.4, 0.4))
		kit.cylinder("metal", tx * Transform3D(Basis(), Vector3(0, 2.0, 0)), 1.2, 1.2, 1.8, 10, Color(0.75, 0.75, 0.72))
	# 看板
	if o.get("sign", true) and rng.randf() < 0.7:
		var sc: Color = [Color(0.9, 0.2, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.45, 0.8), Color(0.15, 0.6, 0.35)][rng.randi() % 4]
		var sx := xf * Transform3D(Basis(), Vector3(wd * 0.5 - 1.0, 0.4 + h * 0.55, dp * 0.5 + 0.6))
		kit.box("emissive", sx, Vector3(0.25, h * 0.6, 1.0), sc)
	# 1 階の入口（ガラス扉を開けてある）と庇
	door_frame(xf, 0.0, 0.4, dp * 0.5, dw, dh, "glass", Color(0.45, 0.46, 0.48))
	kit.box("concrete", xf * Transform3D(Basis(), Vector3(0, 0.4 + 3.0, dp * 0.5 + 1.0)), Vector3(4.5, 0.2, 2.0), colr)
	var run := entry_steps(xf, 0.0, dp * 0.5 + 0.15, 0.4, 3.0, "concrete", Color(0.7, 0.7, 0.68))
	col(xf, Vector3(0, 0.4 + h + 0.5, 0), Vector3(wd, 1.0, dp))
	occupy(xf, wd + 1, dp + 2, 1.5)
	var inner := Rect2(-wd * 0.5 + 0.3, -dp * 0.5 + 0.3, wd - 0.6, dp - 0.6)
	var sa := Vector3(-wd * 0.5 + 1.2, 0.4, -dp * 0.5 + 1.0)
	var sb := sa + Vector3(fh, fh, 0)
	var two := floors >= 2
	var flist: Array = [fl(0.4, inner, fh, {"hole": Rect2(sa.x - 0.1, sa.z - 0.7, fh + 0.2, 1.4) if two else Rect2(), "stair": {"a": sa, "b": sb, "w": 1.2} if two else {}})]
	if two:
		flist.append(fl(0.4 + fh, inner, fh))
	var dd := door(Vector3(0, 0.4, dp * 0.5), Vector3.BACK, dw, dh)
	dd["out"] = Vector3(0, 0, dp * 0.5 + 0.15 + run + 1.5)
	var kind := "warehouse_showa" if (not o.get("tank", true) and not o.get("sign", true)) else "office_showa"
	reg_interior(kind, xf, flist, [dd], {"floors_total": floors})


## 団地（板状アパート）。裏の階段室から 1 階の住戸（2DK）に入れる
func _u_apartment(xf: Transform3D, wd := 48.0, dp := 10.0, floors := 5) -> void:
	var fh := 2.8
	var h := floors * fh
	var colr := Color(0.92, 0.9, 0.85)
	foundation(xf, wd + 0.3, dp + 0.3, 0.4, "concrete", Color(0.7, 0.7, 0.68))
	var xs := -wd * 0.5 + 8.0
	shell("concrete", xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h, dp), colr, [{"side": 2, "u": xs, "w": 1.0, "h": 2.1}], {"th": 0.25})
	var units := int(wd / 4.0)
	for f in floors:
		var y := 0.4 + f * fh
		# バルコニー（南面 +Z）
		bx("concrete", xf, Vector3(0, y + 0.1, dp * 0.5 + 0.7), Vector3(wd, 0.18, 1.4), colr * 0.95)
		bx("concrete", xf, Vector3(0, y + 0.65, dp * 0.5 + 1.38), Vector3(wd, 0.9, 0.08), colr * 0.97)
		for u in units:
			var x := -wd * 0.5 + 4.0 * (u + 0.5)
			bx("glass", xf, Vector3(x, y + 1.4, dp * 0.5 + 0.03), Vector3(2.8, 1.9, 0.05), Color(0.5, 0.58, 0.66))
			bx("glass", xf, Vector3(x, y + 1.6, -dp * 0.5 - 0.03), Vector3(1.2, 1.0, 0.05), Color(0.5, 0.58, 0.66))
			bx("concrete", xf, Vector3(x + 2.0, y + 0.9, dp * 0.5 + 0.7), Vector3(0.12, 1.6, 1.4), colr * 0.93)
			# 洗濯物
			if rng.randf() < 0.3:
				bx("cloth", xf, Vector3(x + rng.randf_range(-0.8, 0.8), y + 1.6, dp * 0.5 + 1.1), Vector3(0.8, 0.7, 0.02), [Color(0.9, 0.9, 0.95), Color(0.6, 0.7, 0.9), Color(0.95, 0.8, 0.6)][rng.randi() % 3])
	# 階段室（最初の一つは中に入れる）
	var run := 0.0
	for k in int(wd / 16.0):
		var sxk := -wd * 0.5 + 8.0 + k * 16.0
		var sc := Vector3(sxk, 0.4 + (h + 1.5) * 0.5, -dp * 0.5 - 1.2)
		if k == 0:
			var rx := xf * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
			foundation(xf * Transform3D(Basis(), Vector3(sxk, 0, -dp * 0.5 - 1.2)), 3.2, 2.6, 0.4, "concrete", Color(0.7, 0.7, 0.68))
			shell("concrete", xf, sc, Vector3(3.0, h + 1.5, 2.4), colr * 0.96, [{"side": 2, "u": sxk, "w": 1.3, "h": 2.2}, {"side": 0, "u": sxk, "w": 1.0, "h": 2.1}], {"th": 0.2})
			door_frame(rx, -sxk, 0.4, dp * 0.5 + 2.4, 1.3, 2.2, "frame", Color(0.4, 0.42, 0.45))
			run = entry_steps(rx, -sxk, dp * 0.5 + 2.5, 0.4, 1.8, "concrete", Color(0.7, 0.7, 0.68))
		else:
			bx("concrete", xf, sc, Vector3(3.0, h + 1.5, 2.4), colr * 0.96)
			col(xf, sc, Vector3(3.0, h + 1.5, 2.4))
	bx("concrete", xf, Vector3(0, 0.4 + h + 0.3, 0), Vector3(wd + 0.2, 0.6, dp + 0.2), colr * 0.9)
	col(xf, Vector3(0, 0.4 + h + 0.3, 0), Vector3(wd, 0.6, dp))
	occupy(xf, wd + 1, dp + 6, 2.0)
	var dd := door(Vector3(xs, 0.4, -dp * 0.5 - 2.4), Vector3.FORWARD, 1.3, 2.2)
	dd["out"] = Vector3(xs, 0, -dp * 0.5 - 2.5 - run - 1.4)
	reg_interior("danchi", xf, [
		fl(0.4, Rect2(xs - 3.9, -dp * 0.5 + 0.25, 7.8, dp - 0.5), fh, {"unit": true}),
		fl(0.4, Rect2(xs - 1.3, -dp * 0.5 - 2.2, 2.6, 2.0), h + 1.5, {"stairwell": true})], [dd], {"xs": xs, "fh": fh})


## 昭和の木造家屋・商店（看板建築＋日よけ）。店先は開け放し、奥が茶の間、2 階は六畳
func _u_showa_shop(xf: Transform3D, wd := 6.0, dp := 9.0) -> void:
	var colr: Color = [Color(0.85, 0.82, 0.74), Color(0.7, 0.75, 0.72), Color(0.8, 0.7, 0.6), Color(0.9, 0.88, 0.82)][rng.randi() % 4]
	var ow := wd - 1.6
	var oh := 2.4
	foundation(xf, wd, dp, 0.25, "concrete", Color(0.7, 0.7, 0.68))
	shell("plaster", xf, Vector3(0, 0.25 + 3.3, -0.2), Vector3(wd - 0.1, 6.6, dp - 0.4), colr, [{"side": 0, "u": 0.0, "w": ow, "h": oh}], {"th": 0.15})
	# 看板建築の正面（店先を抜く）
	slab("concrete", xf, Vector3(0, 0.25 + 3.8, dp * 0.5 - 0.15), Vector3(wd, 7.6, 0.3), colr * 1.03, [{"u": 0.0, "w": ow, "h": oh + 0.25}], true)
	for sgn in [-1.0, 1.0]:
		bx("glass", xf, Vector3(sgn * (ow * 0.5 + 0.15), 0.25 + 1.3, dp * 0.5 + 0.02), Vector3(0.3, 2.4, 0.06), Color(0.32, 0.36, 0.4))
	# 開けたガラス戸を戸袋側に重ねる
	bx("glass", xf, Vector3(ow * 0.5 - 0.5, 0.25 + 1.2, dp * 0.5 - 0.45), Vector3(0.9, 2.2, 0.04), Color(0.45, 0.5, 0.55))
	bx("glass", xf, Vector3(0, 0.25 + 4.6, dp * 0.5 + 0.02), Vector3(wd * 0.6, 1.4, 0.06), Color(0.5, 0.56, 0.62))
	var ac: Color = [Color(0.85, 0.2, 0.15), Color(0.2, 0.5, 0.25), Color(0.9, 0.75, 0.2), Color(0.2, 0.35, 0.7), Color(0.95, 0.95, 0.9)][rng.randi() % 5]
	var aw := xf * Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.25 + 2.9, dp * 0.5 + 0.7))
	kit.box("cloth", aw, Vector3(wd - 0.2, 0.05, 1.6), ac)
	kit.box("emissive", xf * Transform3D(Basis(), Vector3(0, 0.25 + 3.45, dp * 0.5 + 0.05)), Vector3(wd * 0.7, 0.6, 0.05), Color(0.95, 0.92, 0.8))
	roof(xf, 0.25 + 6.6, wd * 0.5 + 0.2, dp * 0.5 + 0.1, 1.6, "gable", "rooftile", TILE_DARK, 0.0)
	col(xf, Vector3(0, 0.25 + 6.6 + 0.6, 0), Vector3(wd, 1.0, dp))
	var run := entry_steps(xf, 0.0, dp * 0.5, 0.25, ow, "concrete", Color(0.7, 0.7, 0.68))
	occupy(xf, wd, dp, 0.0)
	var inner := Rect2(-wd * 0.5 + 0.2, -dp * 0.5 + 0.15, wd - 0.4, dp - 0.7)
	var sa := Vector3(-wd * 0.5 + 0.65, 0.25, -dp * 0.5 + 0.45 + 3.3)
	var sb := Vector3(sa.x, 0.25 + 3.3, -dp * 0.5 + 0.45)
	var dd := door(Vector3(0, 0.25, dp * 0.5 - 0.4), Vector3.BACK, ow, oh)
	dd["out"] = Vector3(0, 0, dp * 0.5 + run + 1.6)
	reg_interior("showa_shop", xf, [
		fl(0.25, inner, 3.3, {"hole": Rect2(sa.x - 0.45, sb.z - 0.05, 0.9, 3.4), "stair": {"a": sa, "b": sb, "w": 0.8}}),
		fl(0.25 + 3.3, inner, 3.3)], [dd], {"awning": ac})


## 電柱と電線（points に沿って）
func utility_line(points: Array, h := 8.0) -> void:
	var tops: Array = []
	for p in points:
		var g := ground(p)
		var base := Vector3(p.x, g - 0.5, p.z)
		kit.cylinder("concrete", Transform3D(Basis(), base), 0.16, 0.11, h + 0.5, 7, Color(0.7, 0.68, 0.64))
		var top := base + Vector3(0, h + 0.2, 0)
		tops.append(top)
		cols.append([Transform3D(Basis(), base + Vector3(0, h * 0.5, 0)), Vector3(0.35, h, 0.35)])
	for i in tops.size() - 1:
		var a: Vector3 = tops[i]
		var b: Vector3 = tops[i + 1]
		var d := b - a
		var side := Vector3(-d.z, 0, d.x).normalized()
		kit.box("wood", Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), a + Vector3(0, -0.4, 0)), Vector3(1.6, 0.1, 0.1), DARK)
		for off in [-0.7, 0.0, 0.7]:
			var pa: Vector3 = a + side * off + Vector3(0, -0.35, 0)
			var pb: Vector3 = b + side * off + Vector3(0, -0.35, 0)
			var segs := 6
			for s in segs:
				var t0 := float(s) / segs
				var t1 := float(s + 1) / segs
				var q0: Vector3 = pa.lerp(pb, t0) - Vector3(0, sin(t0 * PI) * 0.6, 0)
				var q1: Vector3 = pa.lerp(pb, t1) - Vector3(0, sin(t1 * PI) * 0.6, 0)
				kit.rod("wire", q0, q1, 0.015, 3, Color(0.1, 0.1, 0.1))


# ================================================================ 港・橋
func pier(xf: Transform3D, length: float, width: float, kind := "wood") -> void:
	var deck_y := w.water_level + 1.8 - xf.origin.y
	var mat := "wood" if kind == "wood" else ("stonewall" if kind == "stone" else "concrete")
	var colr := Color(0.85, 0.78, 0.7) if kind == "wood" else Color(0.85, 0.83, 0.8)
	var deck := Vector3(0, deck_y, length * 0.5)
	bx(mat, xf, deck, Vector3(width, 0.5 if kind == "wood" else 1.2, length), colr)
	cols.append([xf * Transform3D(Basis(), deck), Vector3(width, 0.6 if kind == "wood" else 1.2, length)])
	var n := int(length / 4.0)
	for k in n + 1:
		for sgn in [-1.0, 1.0]:
			var p := Vector3(sgn * (width * 0.5 - 0.3), deck_y - 6.0, k * length / maxf(n, 1))
			if kind == "wood":
				cyl("darkwood", xf, p, 0.22, 0.22, 6.0, 6, Color(0.5, 0.45, 0.4))
			else:
				bx(mat, xf, p + Vector3(0, 3.0, 0), Vector3(1.0, 6.0, 1.0), colr)
			if k % 2 == 0:
				cyl("metal" if kind != "wood" else "darkwood", xf, Vector3(sgn * (width * 0.5 - 0.5), deck_y + 0.25, k * length / maxf(n, 1)), 0.2, 0.16, 0.6, 6, Color(0.2, 0.2, 0.2) if kind != "wood" else DARK)


## 和船・帆船・汽船（静的な飾り）
func _u_boat(xf: Transform3D, kind := "small") -> void:
	var y := w.water_level - xf.origin.y
	if kind == "dutch":
		# 南蛮船（写真ベースのモデル）
		if model("dutch_ship_medium", xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y + 0.3, 0)), Vector3.ZERO):
			cols.append([xf * Transform3D(Basis(), Vector3(0, y + 1.0, 0)), Vector3(5.0, 4.0, 21.0)])
			return
		kind = "big"
	var L := 7.0
	var B := 2.0
	match kind:
		"sail": L = 18.0; B = 5.0
		"big": L = 26.0; B = 7.0
		"steam": L = 34.0; B = 8.0
		"liner": L = 60.0; B = 12.0
	var hull_mat := "wood" if kind in ["small", "sail", "big"] else "metal"
	var hull_col := Color(0.7, 0.55, 0.42) if hull_mat == "wood" else Color(0.12, 0.12, 0.14)
	var hh := B * 0.45
	# 船体: 先細りの断面を重ねる
	var segs := 8
	for s in segs:
		var z0 := -L * 0.5 + L * s / segs
		var z1 := -L * 0.5 + L * (s + 1) / segs
		var b0 := B * (1.0 - pow(absf(z0) / (L * 0.5), 2.2) * 0.85)
		var b1 := B * (1.0 - pow(absf(z1) / (L * 0.5), 2.2) * 0.85)
		var bw := (b0 + b1) * 0.5
		var lift := pow(maxf(absf(z0), absf(z1)) / (L * 0.5), 3.0) * hh * 0.6
		bx(hull_mat, xf, Vector3(0, y + hh * 0.3 + lift * 0.5, (z0 + z1) * 0.5), Vector3(bw, hh + lift, absf(z1 - z0) + 0.02), hull_col)
	if hull_mat == "metal":
		bx("metal", xf, Vector3(0, y + hh * 0.85, 0), Vector3(B * 0.98, hh * 0.25, L * 0.85), Color(0.85, 0.85, 0.82))
	match kind:
		"small":
			kit.rod("wood", xf * Vector3(0, y + hh, -L * 0.5), xf * Vector3(0, y + hh + 0.6, -L * 0.5 - 1.6), 0.05, 4, DARK)
		"sail", "big":
			bx("wood", xf, Vector3(0, y + hh * 0.85, -L * 0.15), Vector3(B * 0.6, 1.6, L * 0.3), Color(0.8, 0.7, 0.58))
			var mh := L * 0.9
			cyl("wood", xf, Vector3(0, y + hh, 0), 0.25, 0.15, mh, 6, DARK)
			bx("cloth", xf, Vector3(0, y + hh + mh * 0.58, 0.3), Vector3(B * 1.6, mh * 0.62, 0.05), Color(0.94, 0.9, 0.82))
			bx("wood", xf, Vector3(0, y + hh + mh * 0.9, 0.3), Vector3(B * 1.8, 0.2, 0.2), DARK)
			roof(xf * Transform3D(Basis(), Vector3(0, y + hh + 1.6, L * 0.3)), 0.0, B * 0.35, 2.2, 0.8, "gable", "rooftile", TILE_DARK, 0.0)
		"steam":
			bx("plaster", xf, Vector3(0, y + hh + 1.5, 0), Vector3(B * 0.7, 3.0, L * 0.35), Color(0.92, 0.9, 0.85))
			cyl("metal", xf, Vector3(0, y + hh + 3.0, -1.0), 1.0, 1.0, 5.0, 10, Color(0.15, 0.15, 0.15))
			cyl("metal", xf, Vector3(0, y + hh + 7.5, -1.0), 1.02, 1.02, 0.8, 10, Color(0.75, 0.2, 0.15))
			for zz in [-L * 0.3, L * 0.3]:
				cyl("wood", xf, Vector3(0, y + hh, zz), 0.18, 0.12, 14.0, 6, DARK)
		"liner":
			bx("plaster", xf, Vector3(0, y + hh + 2.5, -2.0), Vector3(B * 0.85, 5.0, L * 0.55), Color(0.95, 0.95, 0.93))
			bx("plaster", xf, Vector3(0, y + hh + 6.0, -3.0), Vector3(B * 0.6, 2.4, L * 0.3), Color(0.95, 0.95, 0.93))
			for k in 2:
				cyl("metal", xf, Vector3(0, y + hh + 7.0, -8.0 + k * 9.0), 1.6, 1.6, 6.0, 12, Color(0.85, 0.65, 0.2))
				cyl("metal", xf, Vector3(0, y + hh + 12.0, -8.0 + k * 9.0), 1.62, 1.62, 1.2, 12, Color(0.1, 0.1, 0.1))
			for row in 2:
				for k in 14:
					bx("glass", xf, Vector3(B * 0.43, y + hh + 1.4 + row * 2.0, -L * 0.25 + k * 2.0), Vector3(0.05, 0.6, 0.9), Color(0.3, 0.35, 0.4))
	cols.append([xf * Transform3D(Basis(), Vector3(0, y + hh * 0.5, 0)), Vector3(B, hh * 1.5, L)])


## 倉庫（中央の戸口から入れる）
func _u_warehouse(xf: Transform3D, wd := 20.0, dp := 12.0, kind := "brick") -> void:
	match kind:
		"brick":
			var h := 9.0
			var nd := int(wd / 4.0)
			var dk := nd / 2
			var door_x := -wd * 0.5 + 4.0 * (dk + 0.5)
			foundation(xf, wd + 0.3, dp + 0.3, 0.5, "stonewall", STONE)
			shell("brick", xf, Vector3(0, 0.5 + h * 0.5, 0), Vector3(wd, h, dp), Color(1.0, 0.66, 0.55), [{"side": 0, "u": door_x, "w": 2.0, "h": 3.0}], {"th": 0.3})
			for i in nd:
				var x := -wd * 0.5 + 4.0 * (i + 0.5)
				for sgn in [-1.0, 1.0]:
					bx("metal", xf, Vector3(x, 0.5 + 6.0, sgn * (dp * 0.5 + 0.05)), Vector3(1.2, 1.8, 0.08), Color(0.25, 0.3, 0.28))
					if i == dk and sgn > 0.0:
						# 鉄扉を横へ引いてある
						bx("metal", xf, Vector3(x + 2.05, 0.5 + 1.6, dp * 0.5 + 0.14), Vector3(2.0, 3.0, 0.06), Color(0.3, 0.32, 0.3))
						continue
					bx("metal", xf, Vector3(x, 0.5 + 1.6, sgn * (dp * 0.5 + 0.05)), Vector3(2.0, 3.0, 0.08), Color(0.3, 0.32, 0.3))
			bx("plaster", xf, Vector3(0, 0.5 + h, 0), Vector3(wd + 0.3, 0.4, dp + 0.3), STONE)
			roof(xf, 0.5 + h + 0.2, wd * 0.5 + 0.4, dp * 0.5 + 0.4, 2.4, "gable", "rooftile", Color(0.38, 0.4, 0.44), 0.0)
			col(xf, Vector3(0, 0.5 + h + 0.6, 0), Vector3(wd, 1.2, dp))
			var run := entry_steps(xf, door_x, dp * 0.5 + 0.15, 0.5, 2.6)
			var dd := door(Vector3(door_x, 0.5, dp * 0.5), Vector3.BACK, 2.0, 3.0)
			dd["out"] = Vector3(door_x, 0, dp * 0.5 + 0.15 + run + 1.5)
			_wh_brick += 1
			reg_interior("factory" if _wh_brick == 1 else "warehouse", xf, [fl(0.5, Rect2(-wd * 0.5 + 0.3, -dp * 0.5 + 0.3, wd - 0.6, dp - 0.6), h)], [dd])
		"concrete":
			concrete_building(xf, wd, dp, 2, {"tank": false, "sign": false, "col": Color(0.78, 0.76, 0.72)})
			return
		"wood":
			var h := 4.0
			var nd := maxi(1, int(wd / 5.0))
			var dk := nd / 2
			var door_x := -wd * 0.5 + 5.0 * (dk + 0.5)
			foundation(xf, wd + 0.3, dp + 0.3, 0.4, "stonewall", STONE)
			shell("darkwood", xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h, dp), Color(0.85, 0.78, 0.7), [{"side": 0, "u": door_x, "w": 2.0, "h": 2.8}], {"th": 0.2})
			for i in int(wd / 5.0):
				if i == dk:
					door_frame(xf, door_x, 0.4, dp * 0.5, 2.0, 2.8, "slide", DARK)
					continue
				bx("darkwood", xf, Vector3(-wd * 0.5 + 5.0 * (i + 0.5), 0.4 + 1.5, dp * 0.5 + 0.04), Vector3(2.4, 3.0, 0.06), Color(0.35, 0.3, 0.26))
			roof(xf, 0.4 + h + 0.1, wd * 0.5 + 0.8, dp * 0.5 + 0.9, 3.0, "gable", "thatch" if w.era_id in ["jomon_kofun", "asuka_nara"] else "rooftile", THATCH if w.era_id in ["jomon_kofun", "asuka_nara"] else TILE_DARK, 0.0)
			col(xf, Vector3(0, 0.4 + h + 0.9, 0), Vector3(wd, 1.6, dp))
			var run := entry_steps(xf, door_x, dp * 0.5 + 0.15, 0.4, 2.6)
			var dd := door(Vector3(door_x, 0.4, dp * 0.5), Vector3.BACK, 2.0, 2.8)
			dd["out"] = Vector3(door_x, 0, dp * 0.5 + 0.15 + run + 1.5)
			reg_interior("storehouse", xf, [fl(0.4, Rect2(-wd * 0.5 + 0.2, -dp * 0.5 + 0.2, wd - 0.4, dp - 0.4), h)], [dd])
		_:
			kura(xf, wd, dp, 6.0)
			return
	occupy(xf, wd + 1, dp + 1, 2.0)


var _wh_brick := 0


## 橋。pos=中央(2D)、dir=進行方向、deck_h=床の高さ
func bridge(pos: Vector2, dir: Vector2, length: float, width: float, deck_h: float, kind := "wood", arch := 0.0) -> void:
	var ang := atan2(dir.x, dir.y)
	var xf := Transform3D(Basis(Vector3.UP, ang), Vector3(pos.x, deck_h, pos.y))
	t.occupy_rect(pos, -ang, width * 0.5 + 0.5, length * 0.5 + 6.0)
	var bridge_group := "bridge_%d_%d" % [int(pos.x), int(pos.y)]
	var segs := 10
	var mat := "wood" if kind == "wood" else ("stonewall" if kind == "stone" else "concrete")
	var colr := Color(0.8, 0.72, 0.62) if kind == "wood" else Color(0.85, 0.83, 0.8)
	var rail_col := VERMILION if kind == "vermilion" else colr
	if kind == "vermilion":
		mat = "wood"
	var ext := length * 0.5 + 6.0
	for s in segs:
		var z0 := -ext + 2.0 * ext * s / segs
		var z1 := -ext + 2.0 * ext * (s + 1) / segs
		var y0 := arch * (1.0 - pow(z0 / ext, 2.0))
		var y1 := arch * (1.0 - pow(z1 / ext, 2.0))
		# 端は地面へすり付け
		var g0 := ground(xf * Vector3(0, 0, z0)) - deck_h
		var g1 := ground(xf * Vector3(0, 0, z1)) - deck_h
		if absf(z0) > length * 0.5:
			y0 = lerpf(y0, maxf(g0, y0 - 3.0), clampf((absf(z0) - length * 0.5) / 6.0, 0.0, 1.0))
		if absf(z1) > length * 0.5:
			y1 = lerpf(y1, maxf(g1, y1 - 3.0), clampf((absf(z1) - length * 0.5) / 6.0, 0.0, 1.0))
		var mid := Vector3(0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
		var sl := atan2(y1 - y0, z1 - z0)
		var seg_xf := xf * Transform3D(Basis(Vector3.RIGHT, -sl), mid)
		var L := Vector2(z1 - z0, y1 - y0).length() + 0.05
		# 中央寄りの区画は壊れて落ちる（両端のすり付け部は残す）
		var breakable := absf((z0 + z1) * 0.5) < length * 0.5
		if breakable:
			begin_unit("bridge", seg_xf, {"kind_detail": "bridge_" + kind, "group": bridge_group})
		kit.box(mat, seg_xf, Vector3(width, 0.45, L), colr)
		cols.append([seg_xf, Vector3(width, 0.5, L)])
		for sgn in [-1.0, 1.0]:
			kit.box("plaster" if kind == "vermilion" else mat, seg_xf * Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.1), 0.75, 0)), Vector3(0.14, 0.12, L), rail_col)
			kit.box("plaster" if kind == "vermilion" else mat, seg_xf * Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.1), 0.45, 0)), Vector3(0.1, 0.6, 0.12), rail_col)
			cols.append([seg_xf * Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.1), 0.6, 0)), Vector3(0.2, 1.0, L)])
		if breakable:
			end_unit()
	# 橋脚
	var np := maxi(1, int(length / 9.0))
	for k in np:
		var z := -length * 0.5 + length * (k + 0.5) / np
		var y := arch * (1.0 - pow(z / ext, 2.0))
		for sgn in [-1.0, 1.0]:
			if kind == "wood" or kind == "vermilion":
				kit.cylinder("darkwood", xf * Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.5), y - 8.0, z)), 0.25, 0.25, 8.0, 6, DARK)
			else:
				kit.box(mat, xf * Transform3D(Basis(), Vector3(0, y - 4.0, z)), Vector3(width * 0.8, 8.0, 1.6), colr)
	if kind == "steel":
		for sgn in [-1.0, 1.0]:
			for s in 6:
				var z0 := -length * 0.5 + length * s / 6.0
				var z1 := z0 + length / 6.0
				kit.rod("metal", xf * Vector3(sgn * width * 0.5, 0.3, z0), xf * Vector3(sgn * width * 0.5, 4.5, (z0 + z1) * 0.5), 0.12, 4, Color(0.3, 0.32, 0.35))
				kit.rod("metal", xf * Vector3(sgn * width * 0.5, 4.5, (z0 + z1) * 0.5), xf * Vector3(sgn * width * 0.5, 0.3, z1), 0.12, 4, Color(0.3, 0.32, 0.35))
			kit.rod("metal", xf * Vector3(sgn * width * 0.5, 4.5, -length * 0.42), xf * Vector3(sgn * width * 0.5, 4.5, length * 0.42), 0.15, 4, Color(0.3, 0.32, 0.35))


# ================================================================ 昭和の飛行場
func _u_hangar(xf: Transform3D, wd := 30.0, dp := 26.0) -> void:
	foundation(xf, wd, dp, 0.2, "concrete", Color(0.7, 0.7, 0.68))
	var segs := 10
	var r := wd * 0.5
	for s in segs:
		var a0 := PI * s / segs
		var a1 := PI * (s + 1) / segs
		var p0 := Vector3(cos(a0) * r, sin(a0) * r * 0.6, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r * 0.6, 0)
		kit.quad("metal", xf * (p1 + Vector3(0, 0, -dp * 0.5)), xf * (p0 + Vector3(0, 0, -dp * 0.5)), xf * (p0 + Vector3(0, 0, dp * 0.5)), xf * (p1 + Vector3(0, 0, dp * 0.5)), Color(0.55, 0.58, 0.55))
		kit.quad("metal", xf * (p0 + Vector3(0, 0, dp * 0.5)), xf * (p0 + Vector3(0, 0, -dp * 0.5)), xf * (p1 + Vector3(0, 0, -dp * 0.5)), xf * (p1 + Vector3(0, 0, dp * 0.5)), Color(0.35, 0.36, 0.35))
	# 後ろの壁
	for s in segs:
		var a0 := PI * s / segs
		var a1 := PI * (s + 1) / segs
		kit.tri("metal", xf * Vector3(0, 0, -dp * 0.5), xf * Vector3(cos(a0) * r, sin(a0) * r * 0.6, -dp * 0.5), xf * Vector3(cos(a1) * r, sin(a1) * r * 0.6, -dp * 0.5), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.5, 0.52, 0.5), xf.basis * Vector3(0, 0, -1))
	col(xf, Vector3(-wd * 0.5 + 0.3, 2.5, 0), Vector3(0.6, 5, dp))
	col(xf, Vector3(wd * 0.5 - 0.3, 2.5, 0), Vector3(0.6, 5, dp))
	col(xf, Vector3(0, r * 0.6 - 0.5, 0), Vector3(wd * 0.7, 1.0, dp))
	col(xf, Vector3(0, r * 0.3, -dp * 0.5), Vector3(wd, r * 0.6, 0.5))
	occupy(xf, wd + 1, dp + 1, 2.0)
	reg_interior("hangar", xf, [fl(0.2, Rect2(-wd * 0.5 + 0.8, -dp * 0.5 + 0.6, wd - 1.6, dp - 1.2), r * 0.6 - 0.6)],
		[door(Vector3(0, 0.2, dp * 0.5), Vector3.BACK, wd * 0.7, r * 0.5)])


func _u_control_tower(xf: Transform3D) -> void:
	foundation(xf, 6, 6, 0.3, "concrete", Color(0.7, 0.7, 0.68))
	shell("concrete", xf, Vector3(0, 0.3 + 5.0, 0), Vector3(5, 10, 5), Color(0.88, 0.86, 0.8), [{"side": 0, "u": 0.0, "w": 1.2, "h": 2.2}], {"th": 0.25})
	door_frame(xf, 0.0, 0.3, 2.5, 1.2, 2.2, "frame", Color(0.4, 0.42, 0.45))
	bx("glass", xf, Vector3(0, 0.3 + 11.2, 0), Vector3(6.2, 2.4, 6.2), Color(0.4, 0.5, 0.55))
	bx("concrete", xf, Vector3(0, 0.3 + 12.6, 0), Vector3(7.0, 0.4, 7.0), Color(0.85, 0.84, 0.8))
	kit.rod("metal", xf * Vector3(2, 12.8, 2), xf * Vector3(2, 17, 2), 0.06, 4, Color(0.3, 0.3, 0.3))
	col(xf, Vector3(0, 0.3 + 11.5, 0), Vector3(6.2, 3.0, 6.2))
	var run := entry_steps(xf, 0.0, 3.0, 0.3, 1.6, "concrete", Color(0.7, 0.7, 0.68))
	occupy(xf, 7, 7, 2.0)
	var dd := door(Vector3(0, 0.3, 2.5), Vector3.BACK, 1.2, 2.2)
	dd["out"] = Vector3(0, 0, 3.0 + run + 1.4)
	reg_interior("tower", xf, [fl(0.3, Rect2(-2.25, -2.25, 4.5, 4.5), 3.0)], [dd])


## 国会議事堂（中央塔＋左右の翼）
func _u_diet_building(xf: Transform3D, wd := 110.0) -> void:
	var granite := Color(0.86, 0.82, 0.74)
	var dp := 30.0
	var h := 16.0
	var cw := 26.0
	foundation(xf, wd + 2, dp + 2, 1.2, "stonewall", granite)
	foundation(xf * Transform3D(Basis(), Vector3(0, 0, 2.0)), cw + 0.4, dp + 6.4, 1.2, "stonewall", granite)
	# 両翼（中は見えない。中央の広間との境は中央棟の壁）
	shell("concrete", xf, Vector3(0, 1.2 + h * 0.5, 0), Vector3(wd, h, dp), granite,
		[{"side": 0, "u": 0.0, "w": cw - 0.6, "h": h}, {"side": 2, "u": 0.0, "w": cw - 0.6, "h": h}], {"th": 0.4, "ceil": false})
	for f in 3:
		var wy := 1.2 + f * 5.0 + 2.8
		for i in 30:
			var x := -wd * 0.5 + wd * (i + 0.5) / 30.0
			if absf(x) < cw * 0.5 + 0.5:
				continue
			bx("glass", xf, Vector3(x, wy, dp * 0.5 + 0.05), Vector3(1.4, 2.6, 0.08), Color(0.25, 0.28, 0.3))
			bx("glass", xf, Vector3(x, wy, -dp * 0.5 - 0.05), Vector3(1.4, 2.6, 0.08), Color(0.25, 0.28, 0.3))
	for i in 31:
		var x := -wd * 0.5 + wd * i / 30.0
		if absf(x) < cw * 0.5 + 0.5:
			continue
		bx("concrete", xf, Vector3(x, 1.2 + h * 0.5, dp * 0.5 + 0.3), Vector3(0.9, h, 0.6), granite * 1.04)
	bx("concrete", xf, Vector3(0, 1.2 + h + 0.4, 0), Vector3(wd + 1, 0.8, dp + 1), granite * 1.05)
	# 翼端のパビリオン
	for sgn in [-1.0, 1.0]:
		bx("concrete", xf, Vector3(sgn * (wd * 0.5 - 6.0), 1.2 + (h + 4.0) * 0.5, 0), Vector3(12, h + 4.0, dp + 4.0), granite)
		col(xf, Vector3(sgn * (wd * 0.5 - 6.0), 1.2 + (h + 4.0) * 0.5, 0), Vector3(12, h + 4.0, dp + 4.0))
	# 中央塔（段々ピラミッド）。下は中央広間
	var cx := xf * Transform3D(Basis(), Vector3(0, 1.2, 0))
	var cd := dp + 6.0
	shell("concrete", cx, Vector3(0, h * 0.5 + 2.0, 2.0), Vector3(cw, h + 4.0, cd), granite, [{"side": 0, "u": 0.0, "w": 3.0, "h": 5.0}], {"th": 0.5, "ceil_col": Color(0.82, 0.76, 0.62)})
	door_frame(cx, 0.0, 0.0, 2.0 + cd * 0.5, 3.0, 5.0, "leaves", Color(0.35, 0.25, 0.18))
	for k in 4:
		cyl("concrete", cx, Vector3(-7.5 + k * 5.0, 0, dp * 0.5 + 4.6), 0.8, 0.7, h, 12, granite * 1.05)
	bx("concrete", cx, Vector3(0, h + 4.6, 2.0), Vector3(20, 5.0, 20), granite)
	for i in 4:
		bx("glass", cx, Vector3(-6.0 + i * 4.0, h + 4.6, 12.05), Vector3(1.6, 3.4, 0.1), Color(0.2, 0.22, 0.24))
	var y := h + 7.1
	for k in 6:
		var s := 17.0 - k * 2.6
		bx("concrete", cx, Vector3(0, y + 1.0, 2.0), Vector3(s, 2.0, s), granite * (1.0 + k * 0.01))
		y += 2.0
	cyl("concrete", cx, Vector3(0, y, 2.0), 1.2, 0.6, 4.0, 8, granite)
	var run := entry_steps(xf, 0.0, 2.0 + cd * 0.5 + 0.2, 1.2, 8.0, "stonewall", granite)
	col(xf, Vector3(0, 1.2 + h + 0.4, 0), Vector3(wd, 0.8, dp))
	col(cx, Vector3(0, (h + 2.1 + y) * 0.5, 2.0), Vector3(20, y - h - 2.1, 20))
	occupy(xf, wd + 4, dp + 12, 4.0)
	var dd := door(Vector3(0, 1.2, 2.0 + cd * 0.5), Vector3.BACK, 3.0, 5.0)
	dd["out"] = Vector3(0, 0, 2.0 + cd * 0.5 + 0.2 + run + 2.0)
	reg_interior("diet", xf, [fl(1.2, Rect2(-cw * 0.5 + 0.5, 2.0 - cd * 0.5 + 0.5, cw - 1.0, cd - 1.0), 13.0)], [dd])


# ================================================================ 破壊ユニットのラッパ（自動生成: 各建物を 1 ユニットに）
func jp_hall(xf: Transform3D, wd: float, dp: float, o := {}) -> void:
	begin_unit("hall", xf, {"kind_detail": "jp_hall"})
	_u_jp_hall(xf, wd, dp, o)
	end_unit()


func pagoda(xf: Transform3D, tiers := 5, base_w := 7.0, tier_h := 3.0, colr := VERMILION) -> void:
	begin_unit("pagoda", xf, {"kind_detail": "pagoda"})
	_u_pagoda(xf, tiers, base_w, tier_h, colr)
	end_unit()


func torii(xf: Transform3D, wd := 6.0, h := 6.0, colr := VERMILION, mat := "plaster") -> void:
	begin_unit("torii", xf, {"kind_detail": "torii"})
	_u_torii(xf, wd, h, colr, mat)
	end_unit()


func pit_dwelling(xf: Transform3D, r := 3.6) -> void:
	begin_unit("house", xf, {"kind_detail": "pit_dwelling"})
	_u_pit_dwelling(xf, r)
	end_unit()


func raised_storehouse(xf: Transform3D, wd := 4.2, dp := 3.4, h := 1.9) -> void:
	begin_unit("house", xf, {"kind_detail": "raised_storehouse"})
	_u_raised_storehouse(xf, wd, dp, h)
	end_unit()


func watchtower(xf: Transform3D, h := 10.0, s := 3.4, roof_mat := "thatch") -> void:
	begin_unit("tower", xf, {"kind_detail": "watchtower"})
	_u_watchtower(xf, h, s, roof_mat)
	end_unit()


func gate(xf: Transform3D, wd := 8.0, kind := "romon", colr := VERMILION) -> void:
	begin_unit("gate", xf, {"kind_detail": "gate"})
	_u_gate(xf, wd, kind, colr)
	end_unit()


func machiya(xf: Transform3D, wd := 6.0, dp := 11.0, stories := 2, o := {}) -> void:
	begin_unit("house", xf, {"kind_detail": "machiya"})
	_u_machiya(xf, wd, dp, stories, o)
	end_unit()


func minka(xf: Transform3D, wd := 8.0, dp := 6.0, roof_mat := "thatch") -> void:
	begin_unit("house", xf, {"kind_detail": "minka"})
	_u_minka(xf, wd, dp, roof_mat)
	end_unit()


func farmhouse(xf: Transform3D, wd := 10.0, dp := 7.0) -> void:
	begin_unit("house", xf, {"kind_detail": "farmhouse"})
	_u_farmhouse(xf, wd, dp)
	end_unit()


func kura(xf: Transform3D, wd := 5.0, dp := 6.5, h := 5.0) -> void:
	begin_unit("kura", xf, {"kind_detail": "kura"})
	_u_kura(xf, wd, dp, h)
	end_unit()


func stone_lantern(p: Vector3, s := 1.0) -> void:
	begin_unit("lantern", Transform3D(Basis(), p), {"kind_detail": "stone_lantern"})
	_u_stone_lantern(p, s)
	end_unit()


func lamp(p: Vector3, kind: String) -> void:
	begin_unit("lamp", Transform3D(Basis(), p), {"kind_detail": "lamp"})
	_u_lamp(p, kind)
	end_unit()


func nobori(p: Vector3, colr: Color) -> void:
	begin_unit("prop", Transform3D(Basis(), p), {"kind_detail": "nobori"})
	_u_nobori(p, colr)
	end_unit()


func haniwa(p: Vector3) -> void:
	begin_unit("prop", Transform3D(Basis(), p), {"kind_detail": "haniwa"})
	_u_haniwa(p)
	end_unit()


func stall(xf: Transform3D, colr: Color) -> void:
	begin_unit("stall", xf, {"kind_detail": "stall"})
	_u_stall(xf, colr)
	end_unit()


func brick_building(xf: Transform3D, wd := 24.0, dp := 14.0, floors := 3, o := {}) -> void:
	begin_unit("brick", xf, {"kind_detail": "brick_building"})
	_u_brick_building(xf, wd, dp, floors, o)
	end_unit()


func wooden_school(xf: Transform3D, wd := 34.0, dp := 10.0) -> void:
	begin_unit("school", xf, {"kind_detail": "wooden_school"})
	_u_wooden_school(xf, wd, dp)
	end_unit()


func concrete_building(xf: Transform3D, wd := 18.0, dp := 14.0, floors := 5, o := {}) -> void:
	begin_unit("concrete", xf, {"kind_detail": "concrete_building"})
	_u_concrete_building(xf, wd, dp, floors, o)
	end_unit()


func apartment(xf: Transform3D, wd := 48.0, dp := 10.0, floors := 5) -> void:
	begin_unit("concrete", xf, {"kind_detail": "apartment"})
	_u_apartment(xf, wd, dp, floors)
	end_unit()


func showa_shop(xf: Transform3D, wd := 6.0, dp := 9.0) -> void:
	begin_unit("house", xf, {"kind_detail": "showa_shop"})
	_u_showa_shop(xf, wd, dp)
	end_unit()


func boat(xf: Transform3D, kind := "small") -> void:
	begin_unit("boat", xf, {"kind_detail": "boat", "ship": kind, "big": kind in ["big", "dutch", "steam", "liner", "sail"]})
	_u_boat(xf, kind)
	end_unit()


func warehouse(xf: Transform3D, wd := 20.0, dp := 12.0, kind := "brick") -> void:
	begin_unit("warehouse", xf, {"kind_detail": "warehouse"})
	_u_warehouse(xf, wd, dp, kind)
	end_unit()


func hangar(xf: Transform3D, wd := 30.0, dp := 26.0) -> void:
	begin_unit("hangar", xf, {"kind_detail": "hangar"})
	_u_hangar(xf, wd, dp)
	end_unit()


func control_tower(xf: Transform3D) -> void:
	begin_unit("concrete", xf, {"kind_detail": "control_tower"})
	_u_control_tower(xf)
	end_unit()


func diet_building(xf: Transform3D, wd := 110.0) -> void:
	begin_unit("monument", xf, {"kind_detail": "diet_building"})
	_u_diet_building(xf, wd)
	end_unit()


func jinmaku(a: Vector3, b: Vector3, colr := Color(0.92, 0.9, 0.86)) -> void:
	begin_unit("fence", _seg_xf(a, b), {"kind_detail": "jinmaku"})
	_u_jinmaku(a, b, colr)
	end_unit()


func baboosaku(a: Vector3, b: Vector3) -> void:
	begin_unit("fence", _seg_xf(a, b), {"kind_detail": "baboosaku"})
	_u_baboosaku(a, b)
	end_unit()


func palisade(a: Vector3, b: Vector3, h := 2.6, gap := 0.42) -> void:
	for seg in _split_seg(a, b):
		begin_unit("fence", _seg_xf(seg[0], seg[1]), {"kind_detail": "palisade"})
		_u_palisade(seg[0], seg[1], h, gap)
		end_unit()


func tsuiji(a: Vector3, b: Vector3, h := 2.8, colr := OCHRE, lines := false) -> void:
	for seg in _split_seg(a, b):
		begin_unit("wall", _seg_xf(seg[0], seg[1]), {"kind_detail": "tsuiji"})
		_u_tsuiji(seg[0], seg[1], h, colr, lines)
		end_unit()


func wood_fence(a: Vector3, b: Vector3, h := 1.8) -> void:
	for seg in _split_seg(a, b):
		begin_unit("fence", _seg_xf(seg[0], seg[1]), {"kind_detail": "wood_fence"})
		_u_wood_fence(seg[0], seg[1], h)
		end_unit()


func stone_wall(a: Vector3, b: Vector3, h := 2.0) -> void:
	for seg in _split_seg(a, b):
		begin_unit("stonewall", _seg_xf(seg[0], seg[1]), {"kind_detail": "stone_wall"})
		_u_stone_wall(seg[0], seg[1], h)
		end_unit()


func brick_wall(a: Vector3, b: Vector3, h := 1.6) -> void:
	for seg in _split_seg(a, b):
		begin_unit("brickwall", _seg_xf(seg[0], seg[1]), {"kind_detail": "brick_wall"})
		_u_brick_wall(seg[0], seg[1], h)
		end_unit()

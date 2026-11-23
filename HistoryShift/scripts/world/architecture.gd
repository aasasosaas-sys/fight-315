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
	if collide != Vector3.ZERO:
		cols.append([xf * Transform3D(Basis(), Vector3(0, collide.y * 0.5, 0)), collide])
	return true


func flush(name: String) -> void:
	if not kit.is_empty():
		var mi := kit.commit(name)
		w.add_child(mi)
	kit = MeshKit.new()
	for c in cols:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c[1]
		cs.shape = bs
		cs.transform = c[0]
		w.static_body.add_child(cs)
	cols.clear()


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
	bx(mat, xf, Vector3(0, (h - 2.0) * 0.5, 0), Vector3(wd, h + 2.0, dp), colr)
	col(xf, Vector3(0, (h - 2.0) * 0.5, 0), Vector3(wd, h + 2.0, dp))


func roof(xf: Transform3D, y: float, hw: float, hd: float, rise: float, style: String, mat := "rooftile", colr := TILE, lift := 0.5, under_col := Color(0.55, 0.42, 0.34), curve := 1.35) -> void:
	var gs := 0.0
	match style:
		"irimoya": gs = 0.42
		"gable": gs = 1.0
		"hip", "pyramid": gs = 0.0
	var thick := 0.32 if mat == "rooftile" else 0.7
	var gmat := "darkwood" if style != "gable" else "darkwood"
	var rx := xf * Transform3D(Basis(), Vector3(0, y, 0))
	kit.roof(rx, hw, hd, rise, gs, mat, "darkwood", colr, curve, lift, thick, under_col, gmat, Color(0.8, 0.75, 0.7))
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
func jp_hall(xf: Transform3D, wd: float, dp: float, o := {}) -> void:
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
	if base_h > 0.05:
		foundation(xf, wd + 2.4, dp + 2.4, base_h, base_mat, o.get("base_col", STONE))
		# 正面の階段
		for s in 3:
			var sh := base_h * (3 - s) / 3.0
			bx(base_mat, xf, Vector3(0, sh * 0.5, dp * 0.5 + 1.2 + 0.45 + s * 0.45), Vector3(minf(wd * 0.4, 6.0), sh, 0.45), o.get("base_col", STONE))
	var y0 := base_h
	if raised:
		# 高床＋縁側（寝殿造など）
		var fh := 1.2
		for i in int(wd / 2.5) + 1:
			for j in [-1.0, 1.0]:
				cyl("wood", xf, Vector3(-wd * 0.5 - 0.8 + i * (wd + 1.6) / int(wd / 2.5), y0, j * (dp * 0.5 + 0.8)), 0.12, 0.12, fh, 6)
		bx("wood", xf, Vector3(0, y0 + fh - 0.1, 0), Vector3(wd + 1.8, 0.2, dp + 1.8), Color(0.9, 0.85, 0.8))
		# 高欄
		for sgn in [-1.0, 1.0]:
			bx("plaster" if pillar_mat == "plaster" else "wood", xf, Vector3(0, y0 + fh + 0.55, sgn * (dp * 0.5 + 0.85)), Vector3(wd + 1.8, 0.08, 0.08), pillar_col)
			bx("plaster" if pillar_mat == "plaster" else "wood", xf, Vector3(sgn * (wd * 0.5 + 0.85), y0 + fh + 0.55, 0), Vector3(0.08, 0.08, dp + 1.8), pillar_col)
		y0 += fh
		col(xf, Vector3(0, y0 * 0.5, 0), Vector3(wd + 1.8, y0, dp + 1.8))
	# 壁（柱の内側）
	bx("plaster", xf, Vector3(0, y0 + wall_h * 0.5, 0), Vector3(wd - 0.3, wall_h, dp - 0.3), wall_col)
	# 腰壁・扉（正面は格子戸の帯）
	var door_mat: String = o.get("door_mat", "darkwood")
	var nbay := maxi(1, int(round(wd / 3.2)))
	var bay := wd / nbay
	for i in nbay:
		var x := -wd * 0.5 + bay * (i + 0.5)
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
	col(xf, Vector3(0, y0 + wall_h * 0.5, 0), Vector3(wd, wall_h, dp))
	col(xf, Vector3(0, ry + rise * 0.4, 0), Vector3(wd + over, rise * 0.8, dp + over))
	occupy(xf, wd + 2.4, dp + 2.4, 2.0)


## 五重塔／三重塔
func pagoda(xf: Transform3D, tiers := 5, base_w := 7.0, tier_h := 3.0, colr := VERMILION) -> void:
	foundation(xf, base_w + 3.0, base_w + 3.0, 1.0)
	var y := 1.0
	for i in tiers:
		var wd := base_w * (1.0 - i * 0.075)
		var h := tier_h if i == 0 else tier_h * 0.72
		bx("plaster", xf, Vector3(0, y + h * 0.5, 0), Vector3(wd, h, wd), PLASTER)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				cyl("plaster", xf, Vector3(cx * wd * 0.5, y, cz * wd * 0.5), 0.2, 0.2, h, 6, colr)
		# 扉（正面）
		bx("darkwood", xf, Vector3(0, y + h * 0.45, wd * 0.5 + 0.02), Vector3(wd * 0.36, h * 0.75, 0.08), Color(0.6, 0.3, 0.2))
		bx("plaster", xf, Vector3(0, y + h - 0.1, 0), Vector3(wd + 0.3, 0.2, wd + 0.3), colr)
		bx("darkwood", xf, Vector3(0, y + h + 0.25, 0), Vector3(wd + 1.1, 0.5, wd + 1.1), Color(0.75, 0.5, 0.35))
		var hw := wd * 0.5 + 2.3
		roof(xf, y + h + 0.45, hw, hw, 1.25, "pyramid" if i == tiers - 1 else "hip", "rooftile", TILE_DARK, 0.75, Color(0.75, 0.42, 0.3), 1.6)
		y += h + 1.25 * 0.62
	# 相輪
	var ty := y + 0.3
	cyl("metal", xf, Vector3(0, ty, 0), 0.6, 0.6, 0.6, 8, Color(0.3, 0.27, 0.2))
	cyl("metal", xf, Vector3(0, ty, 0), 0.12, 0.1, 8.0, 6, Color(0.3, 0.27, 0.2))
	for k in 9:
		cyl("metal", xf, Vector3(0, ty + 1.0 + k * 0.55, 0), 0.42 - k * 0.02, 0.42 - k * 0.02, 0.1, 10, Color(0.36, 0.32, 0.24))
	kit.sphere("gold", xf * Transform3D(Basis(), Vector3(0, ty + 8.2, 0)), 0.3, 8, 5)
	col(xf, Vector3(0, y * 0.5, 0), Vector3(base_w, y, base_w))
	occupy(xf, base_w + 3, base_w + 3, 2.5)


## 鳥居（明神鳥居）
func torii(xf: Transform3D, wd := 6.0, h := 6.0, colr := VERMILION, mat := "plaster") -> void:
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


## 竪穴住居
func pit_dwelling(xf: Transform3D, r := 3.6) -> void:
	cyl("earth", xf, Vector3(0, -0.6, 0), r + 0.9, r + 0.5, 1.0, 14, Color(0.8, 0.72, 0.6))
	cyl("thatch", xf, Vector3(0, 0.2, 0), r + 0.35, 0.55, 4.4, 14, THATCH)
	# 煙出しの小屋根
	roof(xf, 4.3, 0.95, 0.6, 0.7, "gable", "thatch", THATCH * 0.9, 0.0)
	# 入口
	var ex := xf * Transform3D(Basis(), Vector3(0, 0, r - 0.2))
	bx("darkwood", ex, Vector3(0, 0.8, 0.6), Vector3(1.4, 1.6, 1.4), Color(0.25, 0.2, 0.18))
	roof(ex, 1.55, 1.05, 1.1, 0.75, "gable", "thatch", THATCH, 0.0)
	col(xf, Vector3(0, 1.2, 0), Vector3(r * 1.6, 2.4, r * 1.6))
	occupy(xf, r * 2 + 1.5, r * 2 + 1.5, 1.5)


## 高床倉庫
func raised_storehouse(xf: Transform3D, wd := 4.2, dp := 3.4, h := 1.9) -> void:
	for i in 3:
		for j in 2:
			var p := Vector3(-wd * 0.5 + wd * i / 2.0, 0, -dp * 0.5 + dp * j)
			cyl("wood", xf, p + Vector3(0, -0.5, 0), 0.16, 0.15, h + 0.5, 6, DARK)
			cyl("wood", xf, p + Vector3(0, h - 0.5, 0), 0.5, 0.5, 0.08, 8, DARK)
	bx("wood", xf, Vector3(0, h + 0.1, 0), Vector3(wd + 0.6, 0.25, dp + 0.6), DARK)
	bx("darkwood", xf, Vector3(0, h + 1.25, 0), Vector3(wd, 2.1, dp), Color(0.9, 0.82, 0.72))
	roof(xf, h + 2.3, wd * 0.5 + 0.9, dp * 0.5 + 1.0, 2.6, "gable", "thatch", THATCH, 0.0, Color(0.5, 0.4, 0.3), 1.0)
	# はしご
	var lx := xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 0, dp * 0.5 + 1.0))
	for sgn in [-0.3, 0.3]:
		kit.box("wood", lx * Transform3D(Basis(), Vector3(sgn, 1.1, 0)), Vector3(0.08, 2.4, 0.08), DARK)
	for k in 5:
		kit.box("wood", lx * Transform3D(Basis(), Vector3(0, 0.3 + k * 0.42, 0)), Vector3(0.62, 0.06, 0.08), DARK)
	col(xf, Vector3(0, h + 1.2, 0), Vector3(wd, 2.4, dp))
	for i in 3:
		col(xf, Vector3(-wd * 0.5 + wd * i / 2.0, h * 0.5, 0), Vector3(0.3, h, dp))
	occupy(xf, wd + 1, dp + 1, 1.0)


## 物見櫓
func watchtower(xf: Transform3D, h := 10.0, s := 3.4, roof_mat := "thatch") -> void:
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
func palisade(a: Vector3, b: Vector3, h := 2.6, gap := 0.42) -> void:
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
func tsuiji(a: Vector3, b: Vector3, h := 2.8, colr := OCHRE, lines := false) -> void:
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


func wood_fence(a: Vector3, b: Vector3, h := 1.8) -> void:
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


func stone_wall(a: Vector3, b: Vector3, h := 2.0) -> void:
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


func brick_wall(a: Vector3, b: Vector3, h := 1.6) -> void:
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
func gate(xf: Transform3D, wd := 8.0, kind := "romon", colr := VERMILION) -> void:
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
	jp_hall(c * Transform3D(Basis(), Vector3(0, 0, -hs * 0.35)), 16.0, 9.0, o)
	jp_hall(c * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-hs * 0.62, 0, -hs * 0.2)), 11.0, 7.0, o)
	jp_hall(c * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hs * 0.62, 0, -hs * 0.2)), 11.0, 7.0, o)
	# 渡殿
	for sgn in [-1.0, 1.0]:
		var p0 := Vector3(sgn * 8.5, 0, -hs * 0.35)
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


## 町家（ローカル +Z が通り側）
func machiya(xf: Transform3D, wd := 6.0, dp := 11.0, stories := 2, o := {}) -> void:
	var wall: Color = o.get("wall", PLASTER.lerp(OCHRE, rng.randf() * 0.4))
	var h1 := 3.0
	foundation(xf, wd, dp, 0.3)
	bx("plaster", xf, Vector3(0, 0.3 + h1 * 0.5, -0.4), Vector3(wd - 0.1, h1, dp - 0.8), wall)
	# 正面の格子と暗い内部
	bx("darkwood", xf, Vector3(0, 0.3 + h1 * 0.45, dp * 0.5 - 0.45), Vector3(wd - 0.3, h1 * 0.9, 0.1), Color(0.25, 0.2, 0.18))
	var n := int(wd / 0.16)
	for k in n:
		if k % 2 == 0:
			bx("wood", xf, Vector3(-wd * 0.5 + 0.15 + k * (wd - 0.3) / n, 0.3 + h1 * 0.42, dp * 0.5 - 0.35), Vector3(0.05, h1 * 0.78, 0.05), Color(0.55, 0.4, 0.32))
	# 暖簾
	if rng.randf() < 0.5:
		var nc: Color = [Color(0.15, 0.2, 0.42), Color(0.55, 0.15, 0.12), Color(0.2, 0.32, 0.22), Color(0.82, 0.78, 0.7)][rng.randi() % 4]
		bx("cloth", xf, Vector3(rng.randf_range(-wd * 0.2, wd * 0.2), 0.3 + h1 - 0.65, dp * 0.5 - 0.2), Vector3(1.6, 0.9, 0.03), nc)
	# 柱
	for sgn in [-1.0, 1.0]:
		bx("wood", xf, Vector3(sgn * (wd * 0.5 - 0.1), 0.3 + h1 * 0.5, dp * 0.5 - 0.35), Vector3(0.2, h1, 0.2), DARK)
	# 庇
	shed(xf, Vector3(0, 0.3 + h1 + 0.25, dp * 0.5 + 0.2), wd + 0.1, 1.5, 0.45)
	var top := 0.3 + h1
	if stories >= 2:
		var h2 := 2.2
		bx("plaster", xf, Vector3(0, top + h2 * 0.5, -0.6), Vector3(wd - 0.1, h2, dp - 1.4), wall)
		# 虫籠窓
		for k in 2:
			bx("darkwood", xf, Vector3(-wd * 0.22 + k * wd * 0.44, top + h2 * 0.55, dp * 0.5 - 1.28), Vector3(wd * 0.28, h2 * 0.4, 0.06), Color(0.2, 0.17, 0.15))
		top += h2
	roof(xf, top + 0.1, wd * 0.5 + 0.35, dp * 0.5 + 0.3, 2.0 if stories >= 2 else 2.3, "gable", "rooftile", TILE_DARK.lerp(TILE, rng.randf()), 0.0, Color(0.45, 0.38, 0.32), 1.15)
	col(xf, Vector3(0, top * 0.5 + 0.5, -0.3), Vector3(wd, top + 1.0, dp - 0.6))
	occupy(xf, wd, dp, 0.0)


## 片流れの庇（正面 +Z に向かって下がる）
func shed(xf: Transform3D, c: Vector3, wd: float, depth: float, drop: float, mat := "rooftile", colr := TILE_DARK) -> void:
	var ang := atan2(drop, depth)
	kit.box(mat, xf * Transform3D(Basis(Vector3.RIGHT, ang), c), Vector3(wd, 0.12, Vector2(depth, drop).length()), colr)


## 民家（切妻・板葺/茅葺/瓦）
func minka(xf: Transform3D, wd := 8.0, dp := 6.0, roof_mat := "thatch") -> void:
	foundation(xf, wd + 0.4, dp + 0.4, 0.3, "stonewall", STONE)
	var wall := Color(0.82, 0.72, 0.58) if roof_mat != "rooftile" else Color(0.9, 0.86, 0.78)
	bx("plaster", xf, Vector3(0, 0.3 + 1.3, 0), Vector3(wd, 2.6, dp), wall)
	bx("darkwood", xf, Vector3(0, 0.3 + 0.55, dp * 0.5 + 0.03), Vector3(wd, 1.1, 0.06), Color(0.8, 0.7, 0.6))
	for i in 4:
		bx("wood", xf, Vector3(-wd * 0.5 + wd * i / 3.0, 0.3 + 1.3, dp * 0.5 + 0.05), Vector3(0.18, 2.6, 0.18), DARK)
	bx("darkwood", xf, Vector3(-wd * 0.2, 0.3 + 1.1, dp * 0.5 + 0.07), Vector3(1.6, 2.0, 0.05), Color(0.28, 0.22, 0.2))
	var rc := THATCH if roof_mat == "thatch" else (TILE_DARK if roof_mat == "rooftile" else Color(0.6, 0.5, 0.42))
	var rm := roof_mat if roof_mat != "board" else "darkwood"
	roof(xf, 2.95, wd * 0.5 + 0.7, dp * 0.5 + 0.8, 2.4 if roof_mat == "thatch" else 1.7, "gable", rm, rc, 0.0, Color(0.5, 0.4, 0.3), 1.0)
	if roof_mat == "board":
		# 石置き屋根の押さえ石
		for k in 4:
			kit.sphere("stonewall", xf * Transform3D(Basis(), Vector3(-wd * 0.3 + k * wd * 0.2, 2.95 + 1.0, dp * 0.25)), 0.25, 6, 4, STONE)
	col(xf, Vector3(0, 1.8, 0), Vector3(wd, 3.6, dp))
	occupy(xf, wd + 0.6, dp + 0.6, 1.2)


## 農家（茅葺き入母屋）
func farmhouse(xf: Transform3D, wd := 10.0, dp := 7.0) -> void:
	foundation(xf, wd + 0.6, dp + 0.6, 0.35, "stonewall", STONE)
	bx("plaster", xf, Vector3(0, 0.35 + 1.4, 0), Vector3(wd, 2.8, dp), Color(0.86, 0.76, 0.6))
	bx("darkwood", xf, Vector3(0, 0.35 + 0.6, dp * 0.5 + 0.02), Vector3(wd, 1.2, 0.06), Color(0.85, 0.75, 0.65))
	for i in 5:
		bx("wood", xf, Vector3(-wd * 0.5 + wd * i / 4.0, 0.35 + 1.4, dp * 0.5 + 0.05), Vector3(0.2, 2.8, 0.2), DARK)
	# 縁側
	bx("wood", xf, Vector3(0, 0.75, dp * 0.5 + 0.6), Vector3(wd * 0.8, 0.12, 1.0), Color(0.85, 0.75, 0.65))
	bx("darkwood", xf, Vector3(wd * 0.25, 1.65, dp * 0.5 + 0.06), Vector3(2.4, 2.0, 0.05), Color(0.3, 0.25, 0.22))
	roof(xf, 3.2, wd * 0.5 + 1.2, dp * 0.5 + 1.2, 4.6, "irimoya", "thatch", THATCH.lerp(Color(0.8, 0.72, 0.58), rng.randf()), 0.0, Color(0.5, 0.4, 0.3), 1.05)
	col(xf, Vector3(0, 2.4, 0), Vector3(wd, 4.8, dp))
	occupy(xf, wd + 1.5, dp + 1.5, 1.8)


## 土蔵
func kura(xf: Transform3D, wd := 5.0, dp := 6.5, h := 5.0) -> void:
	foundation(xf, wd + 0.4, dp + 0.4, 0.5)
	bx("plaster", xf, Vector3(0, 0.5 + h * 0.5, 0), Vector3(wd, h, dp), PLASTER)
	bx("stonewall", xf, Vector3(0, 0.5 + 0.7, 0), Vector3(wd + 0.06, 1.4, dp + 0.06), Color(0.45, 0.45, 0.48))
	bx("darkwood", xf, Vector3(0, 0.5 + 1.3, dp * 0.5 + 0.08), Vector3(1.4, 2.4, 0.15), Color(0.3, 0.28, 0.26))
	bx("darkwood", xf, Vector3(0, 0.5 + h * 0.78, dp * 0.5 + 0.06), Vector3(0.8, 0.7, 0.1), BLACK)
	roof(xf, 0.5 + h + 0.15, wd * 0.5 + 0.5, dp * 0.5 + 0.6, 1.9, "gable", "rooftile", TILE_DARK, 0.0, Color(0.9, 0.9, 0.88), 1.1)
	col(xf, Vector3(0, (h + 1.0) * 0.5, 0), Vector3(wd, h + 1.0, dp))
	occupy(xf, wd + 0.5, dp + 0.5, 1.0)


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
	for i in tiers:
		var k := 1.0 - i * 0.14
		var ww := tw * k
		var dd := td * k
		var hh := 4.2 if i == 0 else 3.4
		var body_col := wall_col
		bx("plaster", xf, Vector3(0, y + hh * 0.5, 0), Vector3(ww, hh, dd), body_col)
		# 下見板（黒）
		bx("darkwood", xf, Vector3(0, y + hh * 0.25, 0), Vector3(ww + 0.06, hh * 0.5, dd + 0.06), BLACK if accent or i == 0 else Color(0.32, 0.3, 0.3))
		# 窓
		var nwin := maxi(2, int(ww / 3.0))
		for j in nwin:
			var wx := -ww * 0.5 + ww * (j + 0.5) / nwin
			bx("darkwood", xf, Vector3(wx, y + hh * 0.66, dd * 0.5 + 0.03), Vector3(1.0, 0.9, 0.08), Color(0.12, 0.1, 0.1))
			bx("darkwood", xf, Vector3(wx, y + hh * 0.66, -dd * 0.5 - 0.03), Vector3(1.0, 0.9, 0.08), Color(0.12, 0.1, 0.1))
		var nwin2 := maxi(2, int(dd / 3.0))
		for j in nwin2:
			var wz := -dd * 0.5 + dd * (j + 0.5) / nwin2
			bx("darkwood", xf, Vector3(ww * 0.5 + 0.03, y + hh * 0.66, wz), Vector3(0.08, 0.9, 1.0), Color(0.12, 0.1, 0.1))
			bx("darkwood", xf, Vector3(-ww * 0.5 - 0.03, y + hh * 0.66, wz), Vector3(0.08, 0.9, 1.0), Color(0.12, 0.1, 0.1))
		if accent:
			bx("gold", xf, Vector3(0, y + hh - 0.15, 0), Vector3(ww + 0.1, 0.18, dd + 0.1), GOLD)
		var last := i == tiers - 1
		var hw := ww * 0.5 + 1.6
		var hd := dd * 0.5 + 1.6
		var rise := (2.4 if last else 1.35)
		roof(xf, y + hh, hw, hd, rise, "irimoya" if (last or i % 2 == 0) else "hip", "rooftile", TILE_DARK, 0.55, PLASTER)
		# 千鳥破風
		if not last and i % 2 == 1:
			for sgn in [-1.0, 1.0]:
				var px := xf * Transform3D(Basis(Vector3.UP, PI * 0.5 if sgn > 0 else -PI * 0.5), Vector3(0, y + hh + 0.3, sgn * (dd * 0.5 + 0.6)))
				kit.roof(px, 2.2, 1.3, 1.5, 1.0, "rooftile", "plaster", TILE_DARK, 1.1, 0.25, 0.25, PLASTER, "plaster", wall_col)
		if accent and last:
			for sgn in [-1.0, 1.0]:
				var hx := ww * 0.5 + 1.6 - (dd * 0.5 + 1.6) + (dd * 0.5 + 1.6) * 0.42
				kit.box("gold", xf * Transform3D(Basis(), Vector3(sgn * hx, y + hh + rise + 0.8, 0)), Vector3(0.5, 1.2, 0.35), GOLD)
		y += hh + rise * (0.25 if not last else 0.0)
	if not accent:
		var hx := tw * (1.0 - (tiers - 1) * 0.14) * 0.5 + 1.6 - ((td * (1.0 - (tiers - 1) * 0.14)) * 0.5 + 1.6) * 0.58
		for sgn in [-1.0, 1.0]:
			kit.box("gold", xf * Transform3D(Basis(), Vector3(sgn * hx, y + 2.4 + 0.9, 0)), Vector3(0.45, 1.1, 0.3), GOLD)
	col(xf, Vector3(0, (y + base_h) * 0.5, 0), Vector3(tw, y - base_h + 2.0, td).max(Vector3.ONE) + Vector3(0, 0, 0))
	# 隅櫓と塀
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var p := Vector3(cx * (top_w * 0.5 - 3.5), base_h, cz * (top_w * 0.5 - 3.5))
			var yx := xf * Transform3D(Basis(), p)
			bx("plaster", yx, Vector3(0, 2.0, 0), Vector3(6, 4, 6), wall_col)
			bx("darkwood", yx, Vector3(0, 1.0, 0), Vector3(6.05, 2.0, 6.05), BLACK if accent else Color(0.35, 0.33, 0.32))
			roof(yx, 4.0, 4.2, 4.2, 1.8, "irimoya", "rooftile", TILE_DARK, 0.4, PLASTER)
			col(yx, Vector3(0, 2.0, 0), Vector3(6, 4, 6))
	var hs := top_w * 0.5 - 0.6
	for side in 4:
		var a := Vector3(-hs, base_h, hs).rotated(Vector3.UP, side * PI * 0.5)
		var b := Vector3(hs, base_h, hs).rotated(Vector3.UP, side * PI * 0.5)
		var mid := (a + b) * 0.5
		var sx := xf * Transform3D(Basis(Vector3.UP, side * PI * 0.5), mid)
		bx("plaster", sx, Vector3(0, 1.1, 0), Vector3(top_w - 8.0, 2.2, 0.5), wall_col)
		kit.roof(sx * Transform3D(Basis(), Vector3(0, 2.2, 0)), (top_w - 8.0) * 0.5, 0.65, 0.4, 1.0, "rooftile", "darkwood", TILE_DARK, 1.0, 0.0, 0.15)
		col(sx, Vector3(0, 1.1, 0), Vector3(top_w - 8.0, 2.2, 0.5))
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


## 石灯籠
func stone_lantern(p: Vector3, s := 1.0) -> void:
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
func lamp(p: Vector3, kind: String) -> void:
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
func nobori(p: Vector3, colr: Color) -> void:
	var y := ground(p)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y, p.z))
	kit.cylinder("wood", xf, 0.04, 0.03, 4.4, 5, DARK, false)
	bx("cloth", xf, Vector3(0.36, 2.9, 0), Vector3(0.66, 2.6, 0.02), colr)
	bx("wood", xf, Vector3(0.36, 4.25, 0), Vector3(0.75, 0.04, 0.04), DARK)


## 陣幕
func jinmaku(a: Vector3, b: Vector3, colr := Color(0.92, 0.9, 0.86)) -> void:
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
func baboosaku(a: Vector3, b: Vector3) -> void:
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
func haniwa(p: Vector3) -> void:
	var xf := Transform3D(Basis(), Vector3(p.x, ground(p), p.z))
	kit.cylinder("earth", xf, 0.28, 0.22, 1.0, 8, Color(1.0, 0.62, 0.42))
	kit.sphere("earth", xf * Transform3D(Basis(), Vector3(0, 1.15, 0)), 0.2, 8, 5, Color(1.0, 0.62, 0.42))


## 市の屋台
func stall(xf: Transform3D, colr: Color) -> void:
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
## 煉瓦造の洋館（明治）。clock=時計塔
func brick_building(xf: Transform3D, wd := 24.0, dp := 14.0, floors := 3, o := {}) -> void:
	var fh := 4.2
	var wall_mat: String = o.get("mat", "brick")
	var wall_col: Color = o.get("col", Color(1.0, 0.68, 0.58) if wall_mat == "brick" else Color.WHITE)
	var trim: Color = o.get("trim", Color(0.92, 0.9, 0.84))
	var h := floors * fh
	foundation(xf, wd + 0.4, dp + 0.4, 0.8, "stonewall", Color(0.82, 0.8, 0.76))
	bx(wall_mat, xf, Vector3(0, 0.8 + h * 0.5, 0), Vector3(wd, h, dp), wall_col)
	# 階ごとの帯
	for f in floors + 1:
		bx("plaster", xf, Vector3(0, 0.8 + f * fh, 0), Vector3(wd + 0.3, 0.3 if f < floors else 0.6, dp + 0.3), trim)
	# 窓
	var nw := int(wd / 3.2)
	var nd := int(dp / 3.2)
	for f in floors:
		var wy := 0.8 + f * fh + fh * 0.5
		for i in nw:
			var x := -wd * 0.5 + wd * (i + 0.5) / nw
			for sgn in [-1.0, 1.0]:
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
	# 玄関ポーチ（柱＋破風）
	var pz := dp * 0.5 + 1.8
	for k in 4:
		cyl("plaster", xf, Vector3(-3.0 + k * 2.0, 0.8, pz), 0.3, 0.26, fh, 10, trim)
	bx("plaster", xf, Vector3(0, 0.8 + fh + 0.3, pz - 0.6), Vector3(7.6, 0.6, 4.4), trim)
	kit.roof(xf * Transform3D(Basis(), Vector3(0, 0.8 + fh + 0.6, pz - 0.6)), 3.9, 2.4, 1.3, 1.0, "rooftile", "plaster", TILE_DARK, 1.0, 0.0, 0.3, trim, "plaster", trim)
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
	col(xf, Vector3(0, 0.8 + h * 0.5, 0), Vector3(wd, h, dp))
	col(xf, Vector3(0, 0.8 + fh * 0.5, pz), Vector3(7.6, fh, 2.0))
	occupy(xf, wd + 1, dp + 5, 2.5)


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


## 擬洋風の木造校舎
func wooden_school(xf: Transform3D, wd := 34.0, dp := 10.0) -> void:
	var h := 7.6
	var siding := Color(0.98, 0.95, 0.85)
	foundation(xf, wd + 0.4, dp + 0.4, 0.6)
	bx("darkwood", xf, Vector3(0, 0.6 + h * 0.5, 0), Vector3(wd, h, dp), siding * 1.4)
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
	bx("wood", xf, Vector3(0, 0.6 + 3.8, 0), Vector3(wd + 0.2, 0.2, dp + 0.2), Color(0.55, 0.62, 0.7))
	roof(xf, 0.6 + h + 0.1, wd * 0.5 + 0.8, dp * 0.5 + 0.8, 3.2, "hip", "rooftile", TILE_DARK, 0.0, siding)
	# 中央の玄関と塔屋
	var c := xf * Transform3D(Basis(), Vector3(0, 0, dp * 0.5 + 1.5))
	bx("darkwood", c, Vector3(0, 0.6 + 5.0, 0), Vector3(5.0, 10.0, 3.6), siding * 1.4)
	bx("darkwood", c, Vector3(0, 0.6 + 1.4, 1.81), Vector3(2.0, 2.8, 0.06), Color(0.35, 0.28, 0.22))
	roof(c, 0.6 + 10.0, 3.0, 2.3, 1.6, "irimoya", "rooftile", TILE_DARK, 0.2, siding)
	bx("darkwood", c, Vector3(0, 0.6 + 12.4, 0), Vector3(2.4, 2.4, 2.4), siding * 1.4)
	roof(c, 0.6 + 13.6, 1.6, 1.6, 1.8, "pyramid", "rooftile", TILE_DARK, 0.0, siding)
	col(xf, Vector3(0, 0.6 + h * 0.5, 0), Vector3(wd, h, dp))
	col(c, Vector3(0, 5.0, 0), Vector3(5.0, 10.0, 3.6))
	occupy(xf, wd + 1, dp + 5, 3.0)


## 鉄筋コンクリートのビル（昭和）
func concrete_building(xf: Transform3D, wd := 18.0, dp := 14.0, floors := 5, o := {}) -> void:
	var fh := 3.4
	var h := floors * fh
	var colr: Color = o.get("col", Color(0.9, 0.88, 0.84).lerp(Color(0.75, 0.72, 0.66), rng.randf()))
	foundation(xf, wd + 0.3, dp + 0.3, 0.4, "concrete", Color(0.7, 0.7, 0.68))
	bx("concrete", xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h, dp), colr)
	for f in floors:
		var wy := 0.4 + f * fh + fh * 0.55
		for sgn in [-1.0, 1.0]:
			bx("glass", xf, Vector3(0, wy, sgn * (dp * 0.5 + 0.03)), Vector3(wd - 1.2, fh * 0.45, 0.06), Color(0.55, 0.62, 0.7) if f > 0 else Color(0.35, 0.4, 0.45))
			bx("glass", xf, Vector3(sgn * (wd * 0.5 + 0.03), wy, 0), Vector3(0.06, fh * 0.45, dp - 1.2), Color(0.55, 0.62, 0.7))
		bx("concrete", xf, Vector3(0, 0.4 + f * fh + fh * 0.22, 0), Vector3(wd + 0.25, 0.25, dp + 0.25), colr * 0.95)
		# 窓の縦桟
		var n := int(wd / 1.8)
		for i in n:
			for sgn in [-1.0, 1.0]:
				bx("concrete", xf, Vector3(-wd * 0.5 + 0.6 + (wd - 1.2) * i / maxf(n - 1, 1), wy, sgn * (dp * 0.5 + 0.06)), Vector3(0.12, fh * 0.45, 0.06), colr)
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
	# 1 階の入口
	bx("glass", xf, Vector3(0, 0.4 + 1.3, dp * 0.5 + 0.05), Vector3(3.0, 2.6, 0.08), Color(0.3, 0.35, 0.4))
	kit.box("concrete", xf * Transform3D(Basis(), Vector3(0, 0.4 + 3.0, dp * 0.5 + 1.0)), Vector3(4.5, 0.2, 2.0), colr)
	col(xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h + 1.0, dp))
	occupy(xf, wd + 1, dp + 2, 1.5)


## 団地（板状アパート）
func apartment(xf: Transform3D, wd := 48.0, dp := 10.0, floors := 5) -> void:
	var fh := 2.8
	var h := floors * fh
	var colr := Color(0.92, 0.9, 0.85)
	foundation(xf, wd + 0.3, dp + 0.3, 0.4, "concrete", Color(0.7, 0.7, 0.68))
	bx("concrete", xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h, dp), colr)
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
	# 階段室
	for k in int(wd / 16.0):
		bx("concrete", xf, Vector3(-wd * 0.5 + 8.0 + k * 16.0, 0.4 + (h + 1.5) * 0.5, -dp * 0.5 - 1.2), Vector3(3.0, h + 1.5, 2.4), colr * 0.96)
	bx("concrete", xf, Vector3(0, 0.4 + h + 0.3, 0), Vector3(wd + 0.2, 0.6, dp + 0.2), colr * 0.9)
	col(xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h, dp + 2.8))
	occupy(xf, wd + 1, dp + 6, 2.0)


## 昭和の木造家屋・商店（看板建築＋日よけ）
func showa_shop(xf: Transform3D, wd := 6.0, dp := 9.0) -> void:
	var colr: Color = [Color(0.85, 0.82, 0.74), Color(0.7, 0.75, 0.72), Color(0.8, 0.7, 0.6), Color(0.9, 0.88, 0.82)][rng.randi() % 4]
	foundation(xf, wd, dp, 0.25, "concrete", Color(0.7, 0.7, 0.68))
	bx("plaster", xf, Vector3(0, 0.25 + 3.3, -0.2), Vector3(wd - 0.1, 6.6, dp - 0.4), colr)
	# 看板建築の正面
	bx("concrete", xf, Vector3(0, 0.25 + 3.8, dp * 0.5 - 0.15), Vector3(wd, 7.6, 0.3), colr * 1.03)
	bx("glass", xf, Vector3(0, 0.25 + 1.3, dp * 0.5 + 0.02), Vector3(wd - 1.0, 2.4, 0.06), Color(0.32, 0.36, 0.4))
	bx("glass", xf, Vector3(0, 0.25 + 4.6, dp * 0.5 + 0.02), Vector3(wd * 0.6, 1.4, 0.06), Color(0.5, 0.56, 0.62))
	var ac: Color = [Color(0.85, 0.2, 0.15), Color(0.2, 0.5, 0.25), Color(0.9, 0.75, 0.2), Color(0.2, 0.35, 0.7), Color(0.95, 0.95, 0.9)][rng.randi() % 5]
	var aw := xf * Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.25 + 2.9, dp * 0.5 + 0.7))
	kit.box("cloth", aw, Vector3(wd - 0.2, 0.05, 1.6), ac)
	kit.box("emissive", xf * Transform3D(Basis(), Vector3(0, 0.25 + 3.45, dp * 0.5 + 0.05)), Vector3(wd * 0.7, 0.6, 0.05), Color(0.95, 0.92, 0.8))
	roof(xf, 0.25 + 6.6, wd * 0.5 + 0.2, dp * 0.5 + 0.1, 1.6, "gable", "rooftile", TILE_DARK, 0.0)
	col(xf, Vector3(0, 0.25 + 3.4, 0), Vector3(wd, 7.0, dp))
	occupy(xf, wd, dp, 0.0)


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
func boat(xf: Transform3D, kind := "small") -> void:
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


## 倉庫
func warehouse(xf: Transform3D, wd := 20.0, dp := 12.0, kind := "brick") -> void:
	match kind:
		"brick":
			var h := 9.0
			foundation(xf, wd + 0.3, dp + 0.3, 0.5, "stonewall", STONE)
			bx("brick", xf, Vector3(0, 0.5 + h * 0.5, 0), Vector3(wd, h, dp), Color(1.0, 0.66, 0.55))
			for i in int(wd / 4.0):
				var x := -wd * 0.5 + 4.0 * (i + 0.5)
				for sgn in [-1.0, 1.0]:
					bx("metal", xf, Vector3(x, 0.5 + 6.0, sgn * (dp * 0.5 + 0.05)), Vector3(1.2, 1.8, 0.08), Color(0.25, 0.3, 0.28))
					bx("metal", xf, Vector3(x, 0.5 + 1.6, sgn * (dp * 0.5 + 0.05)), Vector3(2.0, 3.0, 0.08), Color(0.3, 0.32, 0.3))
			bx("plaster", xf, Vector3(0, 0.5 + h, 0), Vector3(wd + 0.3, 0.4, dp + 0.3), STONE)
			roof(xf, 0.5 + h + 0.2, wd * 0.5 + 0.4, dp * 0.5 + 0.4, 2.4, "gable", "rooftile", Color(0.38, 0.4, 0.44), 0.0)
			col(xf, Vector3(0, 0.5 + h * 0.5, 0), Vector3(wd, h + 1.0, dp))
		"concrete":
			concrete_building(xf, wd, dp, 2, {"tank": false, "sign": false, "col": Color(0.78, 0.76, 0.72)})
			return
		"wood":
			var h := 4.0
			foundation(xf, wd + 0.3, dp + 0.3, 0.4, "stonewall", STONE)
			bx("darkwood", xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h, dp), Color(0.85, 0.78, 0.7))
			for i in int(wd / 5.0):
				bx("darkwood", xf, Vector3(-wd * 0.5 + 5.0 * (i + 0.5), 0.4 + 1.5, dp * 0.5 + 0.04), Vector3(2.4, 3.0, 0.06), Color(0.35, 0.3, 0.26))
			roof(xf, 0.4 + h + 0.1, wd * 0.5 + 0.8, dp * 0.5 + 0.9, 3.0, "gable", "thatch" if w.era_id in ["jomon_kofun", "asuka_nara"] else "rooftile", THATCH if w.era_id in ["jomon_kofun", "asuka_nara"] else TILE_DARK, 0.0)
			col(xf, Vector3(0, 0.4 + h * 0.5, 0), Vector3(wd, h + 1.0, dp))
		_:
			kura(xf, wd, dp, 6.0)
			return
	occupy(xf, wd + 1, dp + 1, 2.0)


## 橋。pos=中央(2D)、dir=進行方向、deck_h=床の高さ
func bridge(pos: Vector2, dir: Vector2, length: float, width: float, deck_h: float, kind := "wood", arch := 0.0) -> void:
	var ang := atan2(dir.x, dir.y)
	var xf := Transform3D(Basis(Vector3.UP, ang), Vector3(pos.x, deck_h, pos.y))
	t.occupy_rect(pos, -ang, width * 0.5 + 0.5, length * 0.5 + 6.0)
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
		kit.box(mat, seg_xf, Vector3(width, 0.45, L), colr)
		cols.append([seg_xf, Vector3(width, 0.5, L)])
		for sgn in [-1.0, 1.0]:
			kit.box("plaster" if kind == "vermilion" else mat, seg_xf * Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.1), 0.75, 0)), Vector3(0.14, 0.12, L), rail_col)
			kit.box("plaster" if kind == "vermilion" else mat, seg_xf * Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.1), 0.45, 0)), Vector3(0.1, 0.6, 0.12), rail_col)
			cols.append([seg_xf * Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.1), 0.6, 0)), Vector3(0.2, 1.0, L)])
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
func hangar(xf: Transform3D, wd := 30.0, dp := 26.0) -> void:
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


func control_tower(xf: Transform3D) -> void:
	foundation(xf, 6, 6, 0.3, "concrete", Color(0.7, 0.7, 0.68))
	bx("concrete", xf, Vector3(0, 0.3 + 5.0, 0), Vector3(5, 10, 5), Color(0.88, 0.86, 0.8))
	bx("glass", xf, Vector3(0, 0.3 + 11.2, 0), Vector3(6.2, 2.4, 6.2), Color(0.4, 0.5, 0.55))
	bx("concrete", xf, Vector3(0, 0.3 + 12.6, 0), Vector3(7.0, 0.4, 7.0), Color(0.85, 0.84, 0.8))
	kit.rod("metal", xf * Vector3(2, 12.8, 2), xf * Vector3(2, 17, 2), 0.06, 4, Color(0.3, 0.3, 0.3))
	col(xf, Vector3(0, 6.5, 0), Vector3(6, 13, 6))
	occupy(xf, 7, 7, 2.0)


## 国会議事堂（中央塔＋左右の翼）
func diet_building(xf: Transform3D, wd := 110.0) -> void:
	var granite := Color(0.86, 0.82, 0.74)
	var dp := 30.0
	var h := 16.0
	foundation(xf, wd + 2, dp + 2, 1.2, "stonewall", granite)
	bx("concrete", xf, Vector3(0, 1.2 + h * 0.5, 0), Vector3(wd, h, dp), granite)
	for f in 3:
		var wy := 1.2 + f * 5.0 + 2.8
		for i in 30:
			var x := -wd * 0.5 + wd * (i + 0.5) / 30.0
			bx("glass", xf, Vector3(x, wy, dp * 0.5 + 0.05), Vector3(1.4, 2.6, 0.08), Color(0.25, 0.28, 0.3))
			bx("glass", xf, Vector3(x, wy, -dp * 0.5 - 0.05), Vector3(1.4, 2.6, 0.08), Color(0.25, 0.28, 0.3))
	for i in 31:
		var x := -wd * 0.5 + wd * i / 30.0
		bx("concrete", xf, Vector3(x, 1.2 + h * 0.5, dp * 0.5 + 0.3), Vector3(0.9, h, 0.6), granite * 1.04)
	bx("concrete", xf, Vector3(0, 1.2 + h + 0.4, 0), Vector3(wd + 1, 0.8, dp + 1), granite * 1.05)
	# 翼端のパビリオン
	for sgn in [-1.0, 1.0]:
		bx("concrete", xf, Vector3(sgn * (wd * 0.5 - 6.0), 1.2 + (h + 4.0) * 0.5, 0), Vector3(12, h + 4.0, dp + 4.0), granite)
	# 中央塔（段々ピラミッド）
	var cx := xf * Transform3D(Basis(), Vector3(0, 1.2, 0))
	bx("concrete", cx, Vector3(0, h * 0.5 + 2.0, 2.0), Vector3(26, h + 4.0, dp + 6.0), granite)
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
	col(xf, Vector3(0, 1.2 + h * 0.5, 0), Vector3(wd, h + 4.0, dp + 4.0))
	col(cx, Vector3(0, (y) * 0.5, 2.0), Vector3(20, y, 20))
	occupy(xf, wd + 4, dp + 12, 4.0)

class_name ShipExterior
extends RefCounted
## 船の外装（常に表示）: 船体外板・内張り・上甲板・部品（上部構造・煙突・マスト・帆・砲塔・飛行甲板・旗…）・外の階段。
## ShipData の layout.parts を解釈して ShipKit に積む。アニメ調（建物と同じトゥーン材質・頂点カラー）。

const GREY := Color(0.55, 0.56, 0.58)
const DARK := Color(0.16, 0.16, 0.17)
const WHITE := Color(0.95, 0.95, 0.93)
const WOOD := Color(0.86, 0.74, 0.58)
const GOLD := Color(1.0, 0.82, 0.35)
const RED := Color(0.82, 0.12, 0.1)

var sd: ShipData
var sk: ShipKit
var hull_col: Color
var sup_col: Color


static func build(p_sd: ShipData, p_sk: ShipKit) -> void:
	var e := ShipExterior.new()
	e.sd = p_sd
	e.sk = p_sk
	e.hull_col = p_sd.c("hull", GREY)
	e.sup_col = p_sd.c("super", e.hull_col.lightened(0.05))
	e._hull()
	if not bool((p_sd.lay.get("hull", {}) as Dictionary).get("no_deck", false)):
		e._weather_deck()
	e._anchors()
	for i in p_sd.parts.size():
		e._part(p_sd.parts[i], i)
	e._ext_stairs()
	e._ladder()


# ================================================================ 船体
func _hull() -> void:
	var ns := clampi(int(sd.L / 2.5), 24, 72)
	var nv := 13
	var rows: Array = []     # rows[i][j] = Vector3（右舷）
	var us: Array = []
	for i in ns + 1:
		var u := float(i) / ns
		# 端は細かく
		u = 0.5 - 0.5 * cos(u * PI) * 0.35 + (u - 0.5) * 0.65
		us.append(u)
	for i in ns + 1:
		var u: float = us[i]
		var kl := sd.keel_u(u)
		var tp := sd.top_u(u) + sd.bulwark
		var col: Array = []
		for j in nv + 1:
			var f := pow(float(j) / nv, 1.5)
			var y := lerpf(kl, tp, f)
			# 水線付近に必ず頂点を置く（塗り分けがきれいに出る）
			if j > 0 and j < nv:
				var fprev := pow(float(j - 1) / nv, 1.5)
				var yprev := lerpf(kl, tp, fprev)
				if yprev < 0.0 and y > 0.0:
					y = 0.0 if absf(y) < absf(yprev) else y
			var e := sd.z_ends(y)
			var z := lerpf(e.x, e.y, u)
			var x := sd.hb_u(u, y)
			col.append(Vector3(x, y, z))
		rows.append(col)
	var c_hull := hull_col
	var c_bot := sd.c("bottom", Color(0.55, 0.16, 0.12) if sd.steel else Color(0.22, 0.17, 0.14))
	var c_boot := sd.c("boot", Color(0.12, 0.12, 0.13) if sd.steel else c_bot)
	var c_str := sd.c("stripe", Color(-1, 0, 0))
	var sy: Array = sd.colors.get("stripe_y", [0.0, 0.0])
	var c_in := sd.c("inner", Color(0.92, 0.9, 0.84) if sd.steel else Color(0.78, 0.64, 0.48))
	var bw_col := sd.c("bulwark", c_hull)
	var mat := sd.hull_mat
	var th := 0.14 if sd.steel else 0.2
	var low_in := -INF
	for y in sd.hull_levels:
		low_in = minf(low_in if low_in > -INF else 999.0, float(y))
	for side: float in [1.0, -1.0]:
		for i in ns:
			for j in nv:
				var a: Vector3 = rows[i][j]
				var b: Vector3 = rows[i + 1][j]
				var cc: Vector3 = rows[i + 1][j + 1]
				var d: Vector3 = rows[i][j + 1]
				a.x *= side; b.x *= side; cc.x *= side; d.x *= side
				var ym := (a.y + b.y + cc.y + d.y) * 0.25
				var colr := c_hull
				if ym < -0.3:
					colr = c_bot
				elif ym < 0.45:
					colr = c_boot
				elif c_str.r >= 0.0 and ym > float(sy[0]) and ym < float(sy[1]):
					colr = c_str
				var tp := sd.top_u(float(us[i])) + 0.02
				if ym > tp:
					colr = bw_col
				var mid := (a + b + cc + d) * 0.25
				var hint := Vector3(mid.x, (mid.y - (sd.keel_u(float(us[i])) + tp) * 0.5) * 0.4, 0.0)
				if absf(mid.x) < 0.3:
					hint += Vector3(0, 0, signf(mid.z) * 0.6)
				hint += Vector3(0, 0, mid.z / (sd.L * 0.5) * 0.25)
				sk.quad(mat, a, b, cc, d, colr, hint)
				sk.faces.append_array([a, b, cc, a, cc, d])
				# 内張り（最下甲板より上だけ）
				if ym > low_in - 0.3:
					var ai := Vector3(a.x - side * th, a.y, a.z)
					var bi := Vector3(b.x - side * th, b.y, b.z)
					var ci := Vector3(cc.x - side * th, cc.y, cc.z)
					var di := Vector3(d.x - side * th, d.y, d.z)
					if absf(ai.x) < 0.05 or ai.x * side < 0.0:
						continue
					sk.quad(mat if ym > tp else "plaster" if sd.steel else "wood", ai, di, ci, bi, c_in if ym <= tp else bw_col.darkened(0.1), -hint)
		# 舷側の上端（ブルワークの天端）
		for i in ns:
			var a: Vector3 = rows[i][nv]
			var b: Vector3 = rows[i + 1][nv]
			a.x *= side; b.x *= side
			var ai := Vector3(a.x - side * th, a.y, a.z)
			var bi := Vector3(b.x - side * th, b.y, b.z)
			sk.quad(mat, a, ai, bi, b, sd.c("rail", bw_col.lightened(0.1)), Vector3.UP)
	# 船首・船尾の平らな面（トランサム）
	for end in [0, ns]:
		var w0 := sd.tb if end == 0 else sd.ts
		if w0 < 0.02:
			continue
		var nz := -1.0 if end == 0 else 1.0
		var r: Array = rows[end]
		for j in nv:
			var a: Vector3 = r[j]
			var b: Vector3 = r[j + 1]
			var pa := Vector3(-a.x, a.y, a.z)
			var pb := Vector3(-b.x, b.y, b.z)
			var ym := (a.y + b.y) * 0.5
			var colr := c_hull if ym > 0.45 else (c_boot if ym > -0.3 else c_bot)
			if ym > sd.top_u(1.0 if end else 0.0):
				colr = bw_col
			if end == ns:
				colr = sd.c("transom", colr) if ym > 0.45 else colr
			sk.quad(mat, pa, a, b, pb, colr, Vector3(0, 0, nz))
			sk.faces.append_array([pa, a, b, pa, b, pb])
	# 船底のコリジョン（最下甲板の下に落ちない）
	var kz := sd.z_ends(-sd.T * 0.5)
	sk.col_box(Vector3(0, -sd.T + 0.15, 0), Vector3(sd.B * 0.5, 0.3, (kz.y - kz.x) * 0.7))


func _hatches_at(y: float, z0 := -INF, z1 := INF, x0 := -INF, x1 := INF) -> Array:
	var out: Array = []
	for st in sd.stairs:
		var sy := float(st["y1"])
		if absf(sy - y) > 0.45:
			continue
		if not bool(st.get("hatch", false)) and not bool(st.get("roof_hole", true)):
			continue
		if float(st["z1"]) < z0 or float(st["z0"]) > z1 or float(st["x1"]) < x0 or float(st["x0"]) > x1:
			continue
		out.append({"z0": float(st["z0"]) - 0.1, "z1": float(st["z1"]) + 0.1, "x0": float(st["x0"]) - 0.1, "x1": float(st["x1"]) + 0.1})
	return out


func _weather_deck() -> void:
	var y := sd.top_m
	var e := sd.z_ends(y)
	var holes := []
	for st in sd.stairs:
		if bool(st.get("hatch", false)) and bool(st.get("ext", false)):
			holes.append({"z0": float(st["z0"]) - 0.1, "z1": float(st["z1"]) + 0.1, "x0": float(st["x0"]) - 0.1, "x1": float(st["x1"]) + 0.1})
	var th := 0.14 if sd.steel else 0.2
	var s := sd
	var hb_fn := func(z: float) -> float: return s.half_beam(z, s.top_at(z) - 0.02) - th
	var y_fn := func(z: float) -> float: return s.top_at(z)
	sk.floor_hull(sd.deck_mat, e.x + 0.05, e.y - 0.05, hb_fn, y_fn, holes, sd.c("deck", WOOD), clampf(sd.L / 40.0, 1.0, 4.0), 0.3)
	# 階段口の縁（ハッチのコーミング）
	for h in holes:
		var hd: Dictionary = h
		var zc := (float(hd["z0"]) + float(hd["z1"])) * 0.5
		var yy := sd.top_at(zc)
		var cc := sd.c("coaming", hull_col.darkened(0.1))
		sk.box("metal" if sd.steel else "wood", Vector3(float(hd["x0"]) - 0.05, yy + 0.3, zc), Vector3(0.1, 0.6, float(hd["z1"]) - float(hd["z0"])), cc, true)
		sk.box("metal" if sd.steel else "wood", Vector3(float(hd["x1"]) + 0.05, yy + 0.3, zc), Vector3(0.1, 0.6, float(hd["z1"]) - float(hd["z0"])), cc, true)
		sk.box("metal" if sd.steel else "wood", Vector3((float(hd["x0"]) + float(hd["x1"])) * 0.5, yy + 0.3, float(hd["z0"]) - 0.05), Vector3(float(hd["x1"]) - float(hd["x0"]) + 0.2, 0.6, 0.1), cc, true)
	# 舷側（ブルワーク）のコリジョン
	var n := maxi(4, int((e.y - e.x) / 4.0))
	for side: float in [-1.0, 1.0]:
		for i in n:
			var za := lerpf(e.x, e.y, float(i) / n)
			var zb := lerpf(e.x, e.y, float(i + 1) / n)
			var ya := sd.top_at(za)
			var yb := sd.top_at(zb)
			var xa := sd.half_beam(za, ya) * side
			var xb := sd.half_beam(zb, yb) * side
			var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 + sd.bulwark * 0.5, (za + zb) * 0.5)
			var dl := Vector2(xb - xa, zb - za)
			sk.col_box(mid, Vector3(0.25, sd.bulwark + 0.3, dl.length() + 0.2), Basis(Vector3.UP, atan2(dl.x, dl.y)))


func _anchors() -> void:
	if not sd.steel and sd.form != "wood_west":
		return
	var y := sd.top_b - 1.6
	var e := sd.z_ends(y)
	var z := e.x + 3.0
	for side: float in [-1.0, 1.0]:
		var x := sd.half_beam(z, y) * side
		sk.box("metal", Vector3(x + side * 0.15, y - 1.0, z), Vector3(0.3, 2.0, 0.5), DARK)
		sk.box("metal", Vector3(x + side * 0.2, y - 2.0, z), Vector3(0.35, 0.3, 1.6), DARK)
		sk.cyl("metal", Vector3(x, y + 0.3, z), 0.4, 0.4, 0.3, 8, DARK, Basis(Vector3.FORWARD, PI * 0.5 * side))


# ================================================================ 部品
func _part(p: Dictionary, idx: int) -> void:
	var t := String(p.get("t", ""))
	match t:
		"house", "island": _house(p, idx)
		"yagura": _house(p, idx, true)
		"tower": _tower(p, idx)
		"platform": _platform(p, idx)
		"castle": _castle(p, idx)
		"funnel": _funnel(p)
		"trunk": _trunk(p)
		"mast": _mast(p)
		"turret": _turret(p)
		"guns": _guns(p)
		"aa": _aa(p)
		"boats": _boats(p)
		"flight_deck": _flight_deck(p, idx)
		"paddle": _paddle(p)
		"roof": _roof(p)
		"oars": _oars(p)
		"flag": _flag(p)
		"crest": _crest(p)
		"eyes": _eyes(p)
		"bowsprit": _bowsprit(p)
		"rudder": _rudder(p)
		"catapult": _catapult(p)
		"crane": _crane(p)
		"rangefinder": _rangefinder(p)
		"searchlight": _searchlight(p)
		"vent": _vent(p)
		"ports": _ports(p)
		"stern_gallery": _stern_gallery(p)
		"pillars": _pillars(p)
		"shields": _shields(p)


func _pc(p: Dictionary, key: String, dflt: Color) -> Color:
	return ShipData.col(p.get(key, null), dflt)


func _y0_of(p: Dictionary, z: float) -> float:
	return float(p.get("y0", p.get("y", sd.top_at(z))))


## 箱型の上部構造（甲板室・艦橋・島型艦橋・矢倉）
func _house(p: Dictionary, idx: int, yagura := false) -> void:
	var r := sd.part_rect(p)
	var z0 := r.position.y
	var z1 := r.end.y
	var x0 := r.position.x
	var x1 := r.end.x
	var zc := (z0 + z1) * 0.5
	var y0 := _y0_of(p, zc)
	var y1 := float(p.get("y1", y0 + 2.5))
	var mat := String(p.get("mat", "metal" if sd.steel else "wood"))
	var colr := _pc(p, "col", sup_col)
	var h := y1 - y0
	# 扉（後ろ側の中央、長ければ前も）。矢倉は四方に出入口
	var dw := 1.1
	var doors: Array = [{"side": "z1", "u": (x0 + x1) * 0.5, "w": dw}]
	if z1 - z0 > 10.0 or yagura:
		doors.append({"side": "z0", "u": (x0 + x1) * 0.5, "w": dw})
	if yagura:
		doors.append({"side": "x0", "u": zc, "w": dw * 1.4})
		doors.append({"side": "x1", "u": zc, "w": dw * 1.4})
	for dd in p.get("doors", []):
		doors.append(dd)
	sk.room_walls(mat, z0, z1, x0, x1, y0, h, colr, doors, 0.15 if not yagura else 0.25)
	# 窓
	if bool(p.get("win", true)) and h > 1.6:
		var wy := y0 + minf(h * 0.55, 1.6)
		var wc := _pc(p, "win_col", Color(0.12, 0.14, 0.16))
		var glass := bool(p.get("glass", sd.year >= 1900 and sd.steel))
		var wm := "glass" if glass else "flat"
		var wh := float(p.get("win_h", 0.7))
		var nwz := maxi(1, int((z1 - z0) / 2.4))
		for side: float in [x0 - 0.02, x1 + 0.02]:
			for k in nwz:
				var zz := lerpf(z0, z1, (k + 0.5) / nwz)
				if absf(zz - zc) < dw and not yagura:
					pass
				sk.box(wm, Vector3(float(side), wy, zz), Vector3(0.04, wh, minf(1.2, (z1 - z0) / nwz * 0.6)), wc)
		var nwx := maxi(1, int((x1 - x0) / 2.4))
		for k in nwx:
			var xx := lerpf(x0, x1, (k + 0.5) / nwx)
			if absf(xx - (x0 + x1) * 0.5) < dw:
				continue
			sk.box(wm, Vector3(xx, wy, z0 - 0.02), Vector3(minf(1.2, (x1 - x0) / nwx * 0.6), wh, 0.04), wc)
	# 矢倉の狭間・鉄板
	if yagura:
		var iron := bool(p.get("iron", false))
		var lc := Color(0.08, 0.07, 0.07)
		var nz := maxi(2, int((z1 - z0) / 1.6))
		for side: float in [x0 - 0.03, x1 + 0.03]:
			for k in nz:
				var zz := lerpf(z0, z1, (k + 0.5) / nz)
				if absf(zz - zc) < dw:
					continue
				sk.box("flat", Vector3(float(side), y0 + h * 0.55, zz), Vector3(0.05, 0.35, 0.3), lc)
				if bool(p.get("ports", false)) and k % 2 == 0:
					sk.box("flat", Vector3(float(side), y0 + h * 0.3, zz), Vector3(0.05, 0.6, 0.7), lc)
		if iron:
			# 鉄板の継ぎ目（横の筋）
			for k in 3:
				var yy := y0 + h * (0.25 + 0.25 * k)
				for side: float in [x0 - 0.04, x1 + 0.04]:
					sk.box("metal", Vector3(float(side), yy, zc), Vector3(0.03, 0.05, z1 - z0), Color(0.28, 0.27, 0.27))
	# 屋根・上面
	var roof := String(p.get("roof", "flat"))
	var holes := _hatches_at(y1, z0, z1, x0, x1)
	if roof == "flat":
		var tc := _pc(p, "top_col", sd.c("deck", WOOD) if not sd.steel or bool(p.get("wood_top", false)) else colr.darkened(0.08))
		sk.floor_rect(String(p.get("top_mat", "wood" if not sd.steel or bool(p.get("wood_top", false)) else "metal")), y1 + 0.15, z0 - 0.1, z1 + 0.1, x0 - 0.1, x1 + 0.1, holes, tc, 0.3)
		# 天井（内側から見える）
		sk.box("plaster" if sd.steel else "wood", Vector3((x0 + x1) * 0.5, y1 - 0.18, zc), Vector3(x1 - x0 - 0.3, 0.04, z1 - z0 - 0.3), Color(0.9, 0.88, 0.82))
		if bool(p.get("rail", true)) and bool(p.get("floor", true)):
			var solid := bool(p.get("screen", yagura))
			sk.rail_rect(y1 + 0.15, z0 - 0.05, z1 + 0.05, x0 - 0.05, x1 + 0.05, 1.05 if not solid else 1.2, _pc(p, "rail_col", colr.darkened(0.2) if solid else DARK), solid)
	else:
		_roof({"s0": sd.s_of(z0), "s1": sd.s_of(z1), "w": x1 - x0, "x": (x0 + x1) * 0.5, "y": y1, "rise": float(p.get("rise", minf(x1 - x0, z1 - z0) * 0.35)),
			"style": roof, "col": p.get("roof_col", null), "mat": p.get("roof_mat", "rooftile"), "over": p.get("over", 0.6)})
		sk.box("plaster" if sd.steel else "wood", Vector3((x0 + x1) * 0.5, y1 - 0.05, zc), Vector3(x1 - x0, 0.1, z1 - z0), Color(0.85, 0.8, 0.7), true)
	# 柱（朱塗りの屋形など）
	if p.has("pillar_col"):
		var pc := _pc(p, "pillar_col", RED)
		for xx: float in [x0, x1]:
			var np := maxi(2, int((z1 - z0) / 2.2))
			for k in np + 1:
				sk.box("wood", Vector3(float(xx), y0 + h * 0.5, lerpf(z0, z1, float(k) / np)), Vector3(0.22, h, 0.22), pc)
		for zz: float in [z0, z1]:
			sk.box("wood", Vector3((x0 + x1) * 0.5, y1 - 0.2, float(zz)), Vector3(x1 - x0 + 0.3, 0.25, 0.25), pc)


func _tower(p: Dictionary, idx: int) -> void:
	var tiers: Array = p.get("tiers", [])
	for k in tiers.size():
		var tr: Dictionary = (tiers[k] as Dictionary).duplicate()
		tr["x"] = p.get("x", 0.0)
		if not tr.has("col"):
			tr["col"] = p.get("col", null)
		if k > 0:
			tr["doors"] = []
		if k < tiers.size() - 1:
			tr["rail"] = tr.get("rail", float((tiers[k + 1] as Dictionary).get("w", 0.0)) < float(tr.get("w", 0.0)) - 1.0)
		if not tr.has("mat"):
			tr["mat"] = p.get("mat", "metal")
		_house(tr, idx)


func _platform(p: Dictionary, idx: int) -> void:
	var r := sd.part_rect(p)
	var y := float(p.get("y", sd.top_m + 3.0))
	var colr := _pc(p, "col", sup_col)
	var holes := _hatches_at(y, r.position.y, r.end.y, r.position.x, r.end.x)
	sk.floor_rect("metal" if sd.steel else "wood", y, r.position.y, r.end.y, r.position.x, r.end.x, holes, _pc(p, "top_col", sd.c("deck", WOOD) if bool(p.get("wood_top", true)) else colr), 0.25)
	var solid := bool(p.get("screen", false))
	sk.rail_rect(y, r.position.y, r.end.y, r.position.x, r.end.x, 1.15 if solid else 1.0, _pc(p, "rail_col", Color(0.85, 0.85, 0.8) if solid else DARK), solid, [], {"z1": [r.end.x - ShipData.STAIR_W * 2.2 - 0.2, r.end.x]})
	# 支柱
	var zc := r.position.y + r.size.y * 0.5
	var below := sd.top_at(zc)
	if bool(p.get("posts", true)) and y - below > 1.0:
		for c in [Vector2(r.position.x + 0.3, r.position.y + 0.3), Vector2(r.end.x - 0.3, r.position.y + 0.3), Vector2(r.position.x + 0.3, r.end.y - 0.3), Vector2(r.end.x - 0.3, r.end.y - 0.3)]:
			var cv: Vector2 = c
			var by := float(p.get("base_y", below))
			sk.box("metal" if sd.steel else "wood", Vector3(cv.x, (y + by) * 0.5, cv.y), Vector3(0.25, y - by, 0.25), colr.darkened(0.2), true)


## 船首楼・船尾楼（舷側を上げて床を張る）
func _castle(p: Dictionary, idx: int) -> void:
	var z0 := sd.z_of(float(p.get("s0", 0.0)))
	var z1 := sd.z_of(float(p.get("s1", 8.0)))
	var y := float(p.get("y", sd.top_m + 2.5))
	var colr := _pc(p, "col", hull_col)
	var s := sd
	var at_end_b := z0 <= -sd.L * 0.5 + 1.0
	var at_end_s := z1 >= sd.L * 0.5 - 1.0
	var e := sd.z_ends(sd.top_m)
	if at_end_b:
		z0 = e.x - sd.rake * 0.2
	if at_end_s:
		z1 = e.y + sd.overhang * 0.3
	var hb_fn := func(z: float) -> float: return maxf(s.half_beam(clampf(z, e.x + 0.05, e.y - 0.05), s.top_at(z) - 0.05) - 0.05, 0.0)
	var n := maxi(2, int((z1 - z0) / 1.5))
	for side: float in [-1.0, 1.0]:
		for i in n:
			var za := lerpf(z0, z1, float(i) / n)
			var zb := lerpf(z0, z1, float(i + 1) / n)
			var xa := float(hb_fn.call(za)) * side
			var xb := float(hb_fn.call(zb)) * side
			var ya := sd.top_at(za)
			var yb := sd.top_at(zb)
			var yt := y + float(p.get("rail_h", 1.0))
			sk.quad(sd.hull_mat, Vector3(xa, ya, za), Vector3(xb, yb, zb), Vector3(xb, yt, zb), Vector3(xa, yt, za), colr, Vector3(side, 0, 0))
			sk.quad("wood", Vector3(xa - side * 0.2, ya, za), Vector3(xa - side * 0.2, yt, za), Vector3(xb - side * 0.2, yt, zb), Vector3(xb - side * 0.2, yb, zb), sd.c("inner", WOOD), Vector3(-side, 0, 0))
			sk.faces.append_array([Vector3(xa, ya, za), Vector3(xb, yb, zb), Vector3(xb, yt, zb), Vector3(xa, ya, za), Vector3(xb, yt, zb), Vector3(xa, yt, za)])
	# 床
	var holes := _hatches_at(y, z0, z1, -sd.B, sd.B)
	var yfn := func(_z: float) -> float: return y
	sk.floor_hull("wood", z0 + 0.1, z1 - 0.1, func(z: float) -> float: return float(hb_fn.call(z)) - 0.2, yfn, holes, sd.c("deck", WOOD), 1.5, 0.3)
	# 腰部の正面の壁（扉つき）と端の壁
	for zz: float in [z0, z1]:
		var zf := float(zz)
		var is_inner := (zf == z1 and not at_end_s) or (zf == z0 and not at_end_b)
		var hb := float(hb_fn.call(zf))
		if hb < 0.3:
			continue
		var ya := sd.top_at(zf)
		var ops: Array = [[hb - 0.6, hb + 0.6, 2.05]] if is_inner else []
		sk.wall("wood", Vector2(-hb, zf), Vector2(hb, zf), ya, y - ya, colr.darkened(0.05) if is_inner else colr, ops, 0.2)
		if not is_inner:
			sk.box("wood", Vector3(0, y + 0.5, zf), Vector3(hb * 2.0, 1.0, 0.15), colr, true)
	# 船尾窓
	if at_end_s and bool(p.get("windows", true)):
		var hb2 := float(hb_fn.call(z1 - 0.3))
		var nw := maxi(2, int(hb2 * 2.0 / 1.6))
		for k in nw:
			var xx := lerpf(-hb2 + 0.6, hb2 - 0.6, (k + 0.5) / nw)
			sk.box("glass", Vector3(xx, (y + sd.top_at(z1)) * 0.5 + 0.3, z1 + 0.12), Vector3(0.7, 0.8, 0.05), Color(0.5, 0.45, 0.3))


func _funnel(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.5)))
	var x := float(p.get("x", 0.0))
	var y0 := float(p.get("y0", sd.top_at(z)))
	var y1 := float(p.get("y1", y0 + 10.0))
	var rx := float(p.get("rx", p.get("r", 1.5)))
	var rz := float(p.get("rz", p.get("r", 1.5)))
	var rake := deg_to_rad(float(p.get("rake", 0.0)))
	var bs := Basis(Vector3.RIGHT, rake)
	var colr := _pc(p, "col", sup_col)
	var h := y1 - y0
	sk.ellipse("metal", Vector3(x, y0, z), rx, rz, h, 16, colr, bs, false)
	# 上端の色帯（黒い煙突の先・会社の帯）
	var bands: Array = p.get("bands", [])
	if p.has("top"):
		bands = bands.duplicate()
		bands.append({"y0": float(p.get("top_h", 1.8)), "col": p["top"]})
	for b in bands:
		var bd: Dictionary = b
		var off := float(bd.get("y0", 1.5))
		var bh := float(bd.get("h", off))
		var base := Vector3(x, y0, z) + bs.y * (h - off)
		sk.ellipse("metal", base, rx + 0.03, rz + 0.03, bh, 16, ShipData.col(bd.get("col", null), DARK), bs, false)
	# 口（中は黒）
	var top := Vector3(x, y0, z) + bs.y * h
	sk.ellipse("flat", top - bs.y * 0.6, rx * 0.92, rz * 0.92, 0.55, 14, Color(0.05, 0.05, 0.05), bs, true)
	sk.col_box(Vector3(x, (y0 + y1) * 0.5, z + sin(rake) * h * 0.5), Vector3(rx * 1.8, h, rz * 1.8), bs)
	# 煙突の付け根の囲い
	sk.box("metal", Vector3(x, y0 + 0.7, z), Vector3(rx * 2.4, 1.4, rz * 2.4), colr.darkened(0.1), true)


## 空母の下向き煙突など: 点列のチューブ
func _trunk(p: Dictionary) -> void:
	var pts: Array = p.get("pts", [])
	var r := float(p.get("r", 2.0))
	var colr := _pc(p, "col", sup_col)
	for k in pts.size() - 1:
		var a: Array = pts[k]
		var b: Array = pts[k + 1]
		var pa := Vector3(float(a[0]), float(a[1]), sd.z_of(float(a[2])))
		var pb := Vector3(float(b[0]), float(b[1]), sd.z_of(float(b[2])))
		sk.rod("metal", pa, pb, r, colr, 12)
		sk.kit.sphere("metal", Transform3D(Basis(), pb), r, 10, 6, colr)
	if pts.size() > 0:
		var e: Array = pts.back()
		var pe := Vector3(float(e[0]), float(e[1]), sd.z_of(float(e[2])))
		sk.kit.sphere("flat", Transform3D(Basis(), pe + Vector3(0, -r * 0.6, 0)), r * 0.85, 10, 6, Color(0.05, 0.05, 0.05))


func _mast(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.5)))
	var x := float(p.get("x", 0.0))
	var y0 := float(p.get("y0", sd.top_at(z)))
	var h := float(p.get("h", 20.0))
	var r := float(p.get("r", 0.35))
	var rake := deg_to_rad(float(p.get("rake", 0.0)))
	var bs := Basis(Vector3.RIGHT, rake)
	var colr := _pc(p, "col", WOOD.darkened(0.25) if not sd.steel else sup_col)
	var mat := "metal" if sd.steel else "wood"
	var base := Vector3(x, y0, z)
	sk.cyl(mat, base, r, r * 0.45, h, 8, colr, bs)
	sk.col_box(base + bs.y * h * 0.25, Vector3(r * 2.0, h * 0.5, r * 2.0), bs)
	var top := String(p.get("top", "none"))
	if top == "fighting":
		var ty := float(p.get("top_y", h * 0.55))
		var pt := base + bs.y * ty
		sk.cyl("metal", pt, 1.7, 1.9, 1.2, 12, colr)
		sk.cyl("metal", pt + Vector3(0, 1.2, 0), 1.9, 1.9, 0.1, 12, colr.darkened(0.2))
	elif top == "crow":
		var pt2 := base + bs.y * (h * 0.82)
		sk.cyl("wood", pt2, 0.7, 0.8, 0.8, 8, colr)
	# 帆桁
	for yd in p.get("yards", []):
		var ydd: Dictionary = yd
		var yy := float(ydd.get("y", h * 0.6))
		var w := float(ydd.get("w", 8.0))
		var c := base + bs.y * yy
		var ang := deg_to_rad(float(ydd.get("ang", 0.0)))
		var dirv := Vector3(cos(ang), sin(ang), 0) if not ydd.has("along") else Vector3(0, sin(ang), cos(ang))
		sk.rod(mat, c - dirv * w * 0.5, c + dirv * w * 0.5, maxf(0.06, r * 0.4), colr)
	# 帆
	for sl in p.get("sails", []):
		_sail(sl, base, bs, colr)
	# 静索（前後に張る線）
	if bool(p.get("stays", true)):
		var tip := base + bs.y * h
		var hbm := sd.half_beam(z, sd.top_at(z) - 0.1)
		for side: float in [-1.0, 1.0]:
			sk.rod("metal", tip - bs.y * 0.5, Vector3(hbm * side, sd.top_at(z) + 0.8, z + 2.0), 0.025, DARK, 3)
	if p.has("flag"):
		var tip2 := base + bs.y * h
		_flag({"kind": p["flag"], "at": tip2 - Vector3(0, 1.4, 0), "size": float(p.get("flag_size", 2.4)), "dir": float(p.get("flag_dir", 1.0))})


func _sail(sl: Dictionary, base: Vector3, bs: Basis, mast_col: Color) -> void:
	var kind := String(sl.get("kind", "square"))
	var y0 := float(sl.get("y0", 4.0))
	var y1 := float(sl.get("y1", 10.0))
	var w := float(sl.get("w", 8.0))
	var colr := ShipData.col(sl.get("col", null), Color(0.95, 0.93, 0.86))
	var off := float(sl.get("off", 0.4))
	var pa := base + bs.y * y0
	var pb := base + bs.y * y1
	match kind:
		"square", "mat":
			# 帆面は船首尾方向に向く（少し膨らむ）
			var bulge := Vector3(0, 0, -minf(w * 0.08, 0.8))
			var a := pa + Vector3(-w * 0.5, 0, -off)
			var b := pa + Vector3(w * 0.5, 0, -off)
			var cc := pb + Vector3(w * 0.5, 0, -off)
			var d := pb + Vector3(-w * 0.5, 0, -off)
			var m0 := (a + d) * 0.5 + bulge
			var m1 := (b + cc) * 0.5 + bulge
			sk.quad("cloth", a, b, m1, m0, colr, Vector3(0, 0, -1))
			sk.quad("cloth", m0, m1, cc, d, colr, Vector3(0, 0, -1))
			if kind == "mat":
				# 網代帆の格子
				var lc := colr.darkened(0.35)
				var nb := maxi(3, int((y1 - y0) / 1.0))
				for k in nb + 1:
					var t := float(k) / nb
					var l0 := a.lerp(d, t) + bulge * sin(t * PI)
					var l1 := b.lerp(cc, t) + bulge * sin(t * PI)
					sk.rod("wood", l0 + Vector3(0, 0, -0.04), l1 + Vector3(0, 0, -0.04), 0.04, lc, 3)
				for k in 5:
					var t2 := float(k) / 4.0
					sk.rod("wood", a.lerp(b, t2) + Vector3(0, 0, -0.04), d.lerp(cc, t2) + Vector3(0, 0, -0.04), 0.03, lc, 3)
			if bool(sl.get("cross", false)):
				# キリスト騎士団の赤い十字
				var cc2 := (a + cc) * 0.5 + bulge * 0.9 + Vector3(0, 0, -0.06)
				var s := minf(w, y1 - y0) * 0.32
				sk.box("cloth", cc2, Vector3(s * 0.35, s * 1.6, 0.02), RED)
				sk.box("cloth", cc2, Vector3(s * 1.4, s * 0.35, 0.02), RED)
		"furled":
			sk.rod("cloth", pb + Vector3(-w * 0.5, 0.1, -0.3), pb + Vector3(w * 0.5, 0.1, -0.3), 0.32, colr, 6)
		"batten", "lug":
			# ジャンクの網代・竹の桁の入った帆（船の中心面に近い向き、少し開く）
			var yaw := deg_to_rad(float(sl.get("yaw", 14.0)))
			var dirv := Vector3(sin(yaw), 0, cos(yaw))   # 後方へ
			var fwd := float(sl.get("fwd", w * 0.3))
			var a := pa - dirv * fwd
			var b := pa + dirv * (w - fwd)
			var cc := pb + dirv * (w - fwd) * 0.85
			var d := pb - dirv * fwd * 0.7
			sk.quad("cloth", a, b, cc, d, colr, Vector3(cos(yaw), 0, -sin(yaw)))
			var nb := maxi(3, int((y1 - y0) / 1.3))
			for k in nb + 1:
				var t := float(k) / nb
				sk.rod("wood", a.lerp(d, t) + Vector3(0.05, 0, 0), b.lerp(cc, t) + Vector3(0.05, 0, 0), 0.05, colr.darkened(0.45), 3)
		"lateen", "fore_aft", "gaff":
			var a := pa
			var b := pa + Vector3(0, 0, w)
			var cc := pb + Vector3(0, 0, w * (0.85 if kind == "gaff" else 0.15))
			var d := pb
			if kind == "lateen":
				d = pb + Vector3(0, 0, -w * 0.3)
				cc = pb + Vector3(0, y1 * 0.15, w * 0.1)
				sk.rod("wood", pa + Vector3(0, 0, w * 0.9), d + Vector3(0, 1.0, -w * 0.15), 0.1, mast_col, 4)
				sk.kit.tri("cloth", a + Vector3(0, 0, w * 0.9), d + Vector3(0, 1.0, -w * 0.15), a, Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), colr, Vector3(1, 0, 0))
				if bool(sl.get("cross", false)):
					var cc2 := (a + d) * 0.5 + Vector3(0.05, 0, w * 0.25)
					sk.box("cloth", cc2, Vector3(0.02, 1.6, 0.45), RED)
					sk.box("cloth", cc2, Vector3(0.02, 0.45, 1.4), RED)
				return
			sk.quad("cloth", a, b, cc, d, colr, Vector3(1, 0, 0))


func _turret(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.3)))
	var x := float(p.get("x", 0.0))
	var y := float(p.get("y", sd.top_at(z)))
	var w := float(p.get("w", 8.0))
	var d := float(p.get("d", 9.0))
	var h := float(p.get("h", 3.0))
	var bar := float(p.get("bar", 0.8))
	var colr := _pc(p, "col", sup_col)
	var face := -1.0 if String(p.get("dir", "fwd")) == "fwd" else 1.0
	# バーベット
	var deck_y := sd.top_at(z)
	if y + bar - deck_y > 0.05:
		sk.cyl("metal", Vector3(x, deck_y, z), w * 0.48, w * 0.48, y + bar - deck_y, 18, colr.darkened(0.12))
	var yb := y + bar
	# 砲室: 前面を傾けた箱（前は低い）
	var bsy := Basis(Vector3.UP, 0.0 if face < 0.0 else PI)
	var c := Vector3(x, yb + h * 0.5, z)
	sk.box("metal", c + bsy * Vector3(0, 0, d * 0.08), Vector3(w, h, d * 0.84), colr, true, bsy)
	var front := c + bsy * Vector3(0, -h * 0.12, -d * 0.42)
	sk.box("metal", front, Vector3(w * 0.96, h * 0.76, d * 0.18), colr.darkened(0.05), false, bsy * Basis(Vector3.RIGHT, 0.35))
	sk.box("metal", c + Vector3(0, h * 0.5 + 0.05, 0) + bsy * Vector3(0, 0, d * 0.1), Vector3(w * 0.92, 0.1, d * 0.78), colr.lightened(0.08), false, bsy)
	if bool(p.get("ears", false)):
		for sx: float in [-1.0, 1.0]:
			sk.cyl("metal", c + bsy * Vector3(sx * w * 0.5, h * 0.25, d * 0.2), 0.45, 0.45, 0.9, 8, colr, bsy * Basis(Vector3.FORWARD, PI * 0.5))
	# 砲身
	var n := int(p.get("guns", 2))
	var ln := float(p.get("len", 10.0))
	var r := float(p.get("r", 0.3))
	var elev := deg_to_rad(float(p.get("elev", 3.0)))
	for k in n:
		var gx := (float(k) - (n - 1) * 0.5) * (w * 0.8 / maxf(n, 1))
		var root := c + bsy * Vector3(gx, -h * 0.05, -d * 0.45)
		var dirv := bsy * Vector3(0, sin(elev), -cos(elev))
		sk.kit.cylinder("metal", Transform3D(_basis_y_to(dirv), root), r * 1.5, r, ln, 10, colr.darkened(0.15))
		sk.cyl("metal", root, r * 1.9, r * 1.9, 1.2, 10, colr.darkened(0.25), _basis_y_to(dirv))


static func _basis_y_to(dirv: Vector3) -> Basis:
	var y := dirv.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## 舷側の砲（ケースメイト・甲板砲）
func _guns(p: Dictionary) -> void:
	var n := int(p.get("n", 4))
	var s0 := float(p.get("s0", sd.L * 0.3))
	var s1 := float(p.get("s1", sd.L * 0.7))
	var y := float(p.get("y", sd.top_m - 1.5))
	var ln := float(p.get("len", 4.0))
	var r := float(p.get("r", 0.08))
	var cas := bool(p.get("casemate", false))
	var side_s := String(p.get("side", "both"))
	var sides: Array = [-1.0, 1.0] if side_s == "both" else ([1.0] if side_s == "starboard" else [-1.0])
	var colr := _pc(p, "col", sup_col if sd.steel else Color(0.15, 0.14, 0.13))
	for side in sides:
		for k in n:
			var s := lerpf(s0, s1, (k + 0.5) / n)
			var z := sd.z_of(s)
			var hb := sd.half_beam(z, minf(y, sd.top_at(z)))
			var x := float(side) * hb
			if cas:
				sk.box("metal", Vector3(x + float(side) * 0.3, y, z), Vector3(0.8, 1.6, 2.2), colr.darkened(0.05), true)
			elif bool(p.get("deck", false)):
				x = float(side) * (hb - 1.4)
				sk.box("metal", Vector3(x, y - 0.4, z), Vector3(0.9, 0.8, 1.2), colr)
				sk.box("metal", Vector3(x + float(side) * 0.3, y + 0.1, z), Vector3(0.08, 1.0, 1.3), colr.lightened(0.05))
			else:
				sk.box("flat", Vector3(x + float(side) * 0.02, y, z), Vector3(0.05, 0.7, 0.7), Color(0.06, 0.05, 0.05))
			var dirv := Vector3(float(side), 0.02, 0)
			sk.kit.cylinder("metal", Transform3D(_basis_y_to(dirv), Vector3(x - float(side) * 0.6, y, z)), r * 1.5, r, ln, 8, Color(0.2, 0.2, 0.21) if sd.steel else Color(0.75, 0.55, 0.25))


## 対空機銃座
func _aa(p: Dictionary) -> void:
	var n := int(p.get("n", 6))
	var s0 := float(p.get("s0", sd.L * 0.35))
	var s1 := float(p.get("s1", sd.L * 0.65))
	var y := float(p.get("y", sd.top_m))
	var colr := _pc(p, "col", sup_col)
	var inset := float(p.get("inset", 2.2))
	for side: float in [-1.0, 1.0]:
		for k in n:
			var z := sd.z_of(lerpf(s0, s1, (k + 0.5) / n))
			var x := float(side) * (sd.half_beam(z, sd.top_at(z) - 0.1) - inset)
			sk.cyl("metal", Vector3(x, y, z), 1.1, 1.1, 0.9, 10, colr.darkened(0.08))
			sk.box("metal", Vector3(x, y + 1.1, z), Vector3(0.9, 0.6, 1.0), colr)
			for b in 3:
				var bx := x + (b - 1) * 0.25
				sk.rod("metal", Vector3(bx, y + 1.2, z), Vector3(bx, y + 2.4, z - 1.3), 0.04, DARK, 4)


func _boats(p: Dictionary) -> void:
	var n := int(p.get("n", 2))
	var s0 := float(p.get("s0", sd.L * 0.4))
	var s1 := float(p.get("s1", sd.L * 0.6))
	var y := float(p.get("y", sd.top_m + 1.0))
	var ln := float(p.get("len", 7.0))
	var colr := _pc(p, "col", WHITE)
	var side_s := String(p.get("side", "both"))
	var sides: Array = [-1.0, 1.0] if side_s == "both" else [0.0]
	for side in sides:
		for k in n:
			var z := sd.z_of(lerpf(s0, s1, (k + 0.5) / n))
			var hb := sd.half_beam(z, minf(y, sd.top_at(z)))
			var x := float(side) * (hb - 1.2 + float(p.get("out", 0.0)))
			_small_boat(Vector3(x, y, z), ln, colr)
			if side != 0.0 and bool(p.get("davits", true)):
				for dz: float in [-ln * 0.35, ln * 0.35]:
					var b0 := Vector3(float(side) * (hb - 0.3), sd.top_at(z), z + float(dz))
					sk.rod("metal", b0, b0 + Vector3(0, y - sd.top_at(z) + 1.6, 0), 0.08, DARK, 4)
					sk.rod("metal", b0 + Vector3(0, y - sd.top_at(z) + 1.6, 0), Vector3(x, y + 1.5, z + float(dz)), 0.07, DARK, 4)


func _small_boat(c: Vector3, ln: float, colr: Color) -> void:
	var w := ln * 0.28
	var bs := Basis().scaled(Vector3(w * 0.5, 0.45, ln * 0.5))
	sk.kit.sphere("wood", Transform3D(bs, c), 1.0, 10, 4, colr)
	sk.box("wood", c + Vector3(0, 0.05, 0), Vector3(w * 0.9, 0.1, ln * 0.85), Color(0.8, 0.68, 0.5))


func _flight_deck(p: Dictionary, idx: int) -> void:
	var r := sd.part_rect(p)
	var y := float(p.get("y", sd.top_m))
	var holes := _hatches_at(y, r.position.y, r.end.y, r.position.x, r.end.x)
	var dc := _pc(p, "col", Color(0.82, 0.68, 0.48))
	sk.floor_rect("wood", y + 0.05, r.position.y, r.end.y, r.position.x, r.end.x, holes, dc, 0.45)
	sk.box("metal", Vector3(r.position.x + r.size.x * 0.5, y - 0.55, r.position.y + r.size.y * 0.5), Vector3(r.size.x - 0.2, 0.5, r.size.y - 0.2), sup_col.darkened(0.1))
	# 白線・縁の紅白・エレベーター
	var zc := r.position.y + r.size.y * 0.5
	sk.box("flat", Vector3(r.position.x + r.size.x * 0.5, y + 0.07, zc), Vector3(0.5, 0.02, r.size.y * 0.92), WHITE)
	for e: float in [r.position.y + 1.5, r.end.y - 1.5]:
		for k in 8:
			var xx := lerpf(r.position.x, r.end.x, (k + 0.5) / 8.0)
			sk.box("flat", Vector3(xx, y + 0.07, float(e)), Vector3(r.size.x / 8.0 * 0.98, 0.02, 2.5), RED if k % 2 == 0 else WHITE)
	for el in p.get("elevators", []):
		var ea: Array = el
		var ez := sd.z_of(float(ea[0]))
		sk.box("flat", Vector3(r.position.x + r.size.x * 0.5, y + 0.065, ez), Vector3(float(ea[1]), 0.02, float(ea[2])), dc.darkened(0.18))
	# 縁の手すり（低い）
	sk.rail_rect(y + 0.05, r.position.y, r.end.y, r.position.x, r.end.x, 0.5, DARK, false, ["z0", "z1"])
	# 船体の外にはみ出す部分の支柱
	var e2 := sd.z_ends(sd.top_m)
	for zz: float in [r.position.y, r.end.y]:
		var zf := float(zz)
		if zf < e2.x + 2.0 or zf > e2.y - 2.0:
			var zin := clampf(zf, e2.x + 6.0, e2.y - 6.0)
			for xx: float in [-r.size.x * 0.25, r.size.x * 0.25]:
				sk.rod("metal", Vector3(float(xx), y - 0.6, zf + signf(zin - zf) * 1.0), Vector3(float(xx) * 0.5, sd.top_at(zin) - 1.0, zin), 0.35, sup_col.darkened(0.2), 6)


func _paddle(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.5)))
	var r := float(p.get("r", 4.5))
	var w := float(p.get("w", 3.0))
	var yc := float(p.get("y", 0.6))
	var colr := _pc(p, "col", Color(0.1, 0.1, 0.1))
	var hb := sd.half_beam(z, 0.5)
	for side: float in [-1.0, 1.0]:
		var xc := float(side) * (hb + w * 0.5)
		# 外輪覆い（半円筒＋側板）
		var bs := Basis(Vector3.FORWARD, PI * 0.5)
		sk.cyl("wood", Vector3(xc - w * 0.5, yc, z), r + 0.3, r + 0.3, w, 18, colr, bs)
		sk.col_box(Vector3(xc, yc + r * 0.5, z), Vector3(w, r + 0.6, r * 2.0 + 0.6))
		# 扇の飾り
		var fc := _pc(p, "fan_col", Color(0.85, 0.7, 0.3))
		for k in 7:
			var a := PI * (0.15 + 0.7 * float(k) / 6.0)
			var tip := Vector3(xc + float(side) * (w * 0.5 + 0.03), yc + sin(a) * r * 0.85, z + cos(a) * r * 0.85)
			sk.rod("wood", Vector3(xc + float(side) * (w * 0.5 + 0.03), yc + 0.3, z), tip, 0.08, fc, 3)
		# 外輪覆いの上の通路（甲板と同じ高さ）
		sk.box("wood", Vector3(float(side) * (hb + w * 0.5), sd.top_at(z) - 0.1, z), Vector3(w + 0.6, 0.2, 2.2), sd.c("deck", WOOD), true)


func _roof(p: Dictionary) -> void:
	var z0 := sd.z_of(float(p.get("s0", 0.0)))
	var z1 := sd.z_of(float(p.get("s1", 4.0)))
	var w := float(p.get("w", 4.0))
	var x := float(p.get("x", 0.0))
	var y := float(p.get("y", sd.top_m + 3.0))
	var rise := float(p.get("rise", 1.5))
	var over := float(p.get("over", 0.6))
	var style := String(p.get("style", "irimoya"))
	var gs := 0.45 if style == "irimoya" else (1.0 if style == "gable" else 0.0)
	var mat := String(p.get("mat", "rooftile"))
	var colr := _pc(p, "col", Color(0.42, 0.45, 0.5))
	var hw := (z1 - z0) * 0.5 + over
	var hd := w * 0.5 + over
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, y, (z0 + z1) * 0.5))
	sk.kit.roof(xf, hw, hd, rise, gs, mat, "wood", colr, 1.3, 0.35)


func _oars(p: Dictionary) -> void:
	var n := int(p.get("n", 20))
	var s0 := float(p.get("s0", sd.L * 0.2))
	var s1 := float(p.get("s1", sd.L * 0.8))
	var y := float(p.get("y", sd.top_m * 0.7))
	var ln := float(p.get("len", 6.0))
	var colr := _pc(p, "col", WOOD.darkened(0.15))
	for side: float in [-1.0, 1.0]:
		for k in n:
			var z := sd.z_of(lerpf(s0, s1, (k + 0.5) / n))
			var hb := sd.half_beam(z, y)
			var a := Vector3(float(side) * (hb - 0.8), y + 0.4, z)
			var b := Vector3(float(side) * (hb + ln * 0.75), -0.2, z + 0.8)
			sk.rod("wood", a, b, 0.06, colr, 4)
			sk.box("wood", b + Vector3(0, 0.1, 0), Vector3(0.05, 0.25, 0.9), colr)


## 旗。kind: rising_sun / hinomaru / z / us / cross / banner / nyk / aoi / mon / ming / red
func _flag(p: Dictionary) -> void:
	var at: Vector3
	if p.has("at") and p["at"] is Vector3:
		at = p["at"]
	else:
		var z := sd.z_of(float(p.get("s", sd.L)))
		at = Vector3(float(p.get("x", 0.0)), float(p.get("y", sd.top_at(z) + 3.0)), z)
		if bool(p.get("pole", true)):
			var py := sd.top_at(clampf(z, -sd.L * 0.5, sd.L * 0.5))
			sk.rod("wood", Vector3(at.x, py, at.z), at + Vector3(0, 0.6, 0), 0.05, DARK, 4)
	var kind := String(p.get("kind", "hinomaru"))
	var sz := float(p.get("size", 2.0))
	var dirv := float(p.get("dir", 1.0))   # 旗のなびく向き（+z = 船尾へ）
	var w := sz * 1.5
	var h := sz
	if kind == "banner":
		w = sz * 0.45
		h = sz * 1.6
	var o := at + Vector3(0, -h * 0.5, dirv * w * 0.5)
	var nrm := Vector3(1, 0, 0)
	var bs := Basis(Vector3.UP, PI * 0.5)
	match kind:
		"rising_sun":
			sk.box("cloth", o, Vector3(w, h, 0.02), WHITE, false, bs)
			var cpos := o + Vector3(0, 0, -dirv * w * 0.12)
			for k in 16:
				if k % 2 == 1:
					continue
				var a0 := TAU * (float(k) - 0.5) / 16.0
				var a1 := TAU * (float(k) + 0.5) / 16.0
				var r := w
				for sx: float in [0.015, -0.015]:
					var pa := cpos + Vector3(float(sx), sin(a0) * r, cos(a0) * r)
					var pb := cpos + Vector3(float(sx), sin(a1) * r, cos(a1) * r)
					pa = Vector3(pa.x, clampf(pa.y, o.y - h * 0.5, o.y + h * 0.5), clampf(pa.z, o.z - w * 0.5, o.z + w * 0.5))
					pb = Vector3(pb.x, clampf(pb.y, o.y - h * 0.5, o.y + h * 0.5), clampf(pb.z, o.z - w * 0.5, o.z + w * 0.5))
					sk.kit.tri("cloth", cpos + Vector3(float(sx), 0, 0), pa, pb, Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), RED, nrm * signf(float(sx)))
			_disc(cpos, h * 0.3, RED)
		"hinomaru":
			sk.box("cloth", o, Vector3(w, h, 0.02), WHITE, false, bs)
			_disc(o, h * 0.3, RED)
		"z":
			# Z 旗: 上 黄・旗竿側 黒・下 青・外側 赤
			var c0 := o
			var tl := o + Vector3(0, h * 0.5, -dirv * w * 0.5)
			var tr := o + Vector3(0, h * 0.5, dirv * w * 0.5)
			var bl := o + Vector3(0, -h * 0.5, -dirv * w * 0.5)
			var br := o + Vector3(0, -h * 0.5, dirv * w * 0.5)
			for sx: float in [0.012, -0.012]:
				var dx := Vector3(float(sx), 0, 0)
				var nn := nrm * signf(float(sx))
				sk.kit.tri("cloth", c0 + dx, tl + dx, tr + dx, Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Color(1.0, 0.82, 0.05), nn)
				sk.kit.tri("cloth", c0 + dx, tr + dx, br + dx, Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Color(0.85, 0.1, 0.08), nn)
				sk.kit.tri("cloth", c0 + dx, br + dx, bl + dx, Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Color(0.1, 0.25, 0.75), nn)
				sk.kit.tri("cloth", c0 + dx, bl + dx, tl + dx, Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Color(0.05, 0.05, 0.05), nn)
		"us":
			for k in 7:
				var yy := o.y + h * 0.5 - h * (k + 0.5) / 7.0
				sk.box("cloth", Vector3(o.x, yy, o.z), Vector3(w, h / 7.0, 0.02), RED if k % 2 == 0 else WHITE, false, bs)
			sk.box("cloth", o + Vector3(0.02, h * 0.22, -dirv * w * 0.27), Vector3(w * 0.45, h * 0.54, 0.03), Color(0.1, 0.15, 0.45), false, bs)
		"cross":
			sk.box("cloth", o, Vector3(w, h, 0.02), WHITE, false, bs)
			sk.box("cloth", o + Vector3(0.02, 0, 0), Vector3(w * 0.2, h * 0.9, 0.025), RED, false, bs)
			sk.box("cloth", o + Vector3(0.02, 0, 0), Vector3(w * 0.9, h * 0.2, 0.025), RED, false, bs)
		"nyk":
			sk.box("cloth", o, Vector3(w, h, 0.02), WHITE, false, bs)
			for yy: float in [h * 0.18, -h * 0.18]:
				sk.box("cloth", o + Vector3(0.02, float(yy), 0), Vector3(w, h * 0.16, 0.025), RED, false, bs)
		"banner", "mon", "aoi":
			var bc := ShipData.col(p.get("col", null), WHITE)
			sk.box("cloth", o, Vector3(w, h, 0.02), bc, false, bs)
			_disc(o + Vector3(0, h * 0.18 if kind == "banner" else 0.0, 0), minf(w, h) * 0.3, ShipData.col(p.get("mon_col", null), Color(0.08, 0.08, 0.08)))
			if kind == "banner":
				sk.rod("wood", at + Vector3(0, 0.3, 0), at + Vector3(0, -h - 0.5, 0), 0.04, DARK, 4)
				sk.rod("wood", at, at + Vector3(0, 0, dirv * w), 0.03, DARK, 3)
		_:
			sk.box("cloth", o, Vector3(w, h, 0.02), ShipData.col(p.get("col", null), RED), false, bs)


func _disc(c: Vector3, r: float, colr: Color) -> void:
	for sx: float in [0.03, -0.03]:
		sk.kit.cylinder("cloth", Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * signf(float(sx))), c + Vector3(float(sx) * 0.5, 0, 0)), r, r, 0.02, 16, colr)


## 艦首の菊花紋章
func _crest(p: Dictionary) -> void:
	var y := float(p.get("y", sd.top_b - 0.8))
	var e := sd.z_ends(y)
	var z := e.x + 0.4
	var r := float(p.get("r", 0.6))
	sk.kit.cylinder("gold", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, y, z - 0.05)), r, r, 0.12, 16, GOLD)
	sk.kit.cylinder("gold", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, y, z - 0.12)), r * 0.35, r * 0.35, 0.1, 10, GOLD.lightened(0.2))


## ジャンクの船首の目
func _eyes(p: Dictionary) -> void:
	var y := float(p.get("y", sd.top_b - 0.7))
	var s := float(p.get("s", 1.5))
	var z := sd.z_of(s)
	var r := float(p.get("r", 0.45))
	for side: float in [-1.0, 1.0]:
		var x := sd.half_beam(z, y) * float(side) + float(side) * 0.04
		var bs := Basis(Vector3.FORWARD, PI * 0.5 * float(side))
		sk.cyl("flat", Vector3(x, y, z), r, r, 0.03, 14, WHITE, bs)
		sk.cyl("flat", Vector3(x + float(side) * 0.03, y, z), r * 0.5, r * 0.5, 0.03, 12, Color(0.05, 0.05, 0.05), bs)


func _bowsprit(p: Dictionary) -> void:
	var y := sd.top_b
	var e := sd.z_ends(y)
	var a := Vector3(0, y + 0.3, e.x + 2.0)
	var ln := float(p.get("len", sd.L * 0.25))
	var ang := deg_to_rad(float(p.get("rise", 20.0)))
	var b := a + Vector3(0, sin(ang), -cos(ang)) * ln
	sk.rod("wood", a, b, float(p.get("r", 0.25)), WOOD.darkened(0.25), 6)
	if p.has("sail"):
		var sl: Dictionary = p["sail"]
		var colr := ShipData.col(sl.get("col", null), Color(0.95, 0.93, 0.86))
		var pc := a.lerp(b, 0.7)
		sk.quad("cloth", pc + Vector3(-1.6, -0.3, 0), pc + Vector3(1.6, -0.3, 0), pc + Vector3(1.6, -2.6, 0.3), pc + Vector3(-1.6, -2.6, 0.3), colr, Vector3(0, 0, -1))
	if p.has("head"):
		sk.kit.sphere("gold", Transform3D(Basis(), a + Vector3(0, -0.8, -0.4)), 0.5, 8, 5, GOLD)


func _rudder(p: Dictionary) -> void:
	var e := sd.z_ends(0.0)
	var z := e.y + 0.3
	var big := bool(p.get("big", false))
	var h := sd.T * (1.4 if big else 0.9)
	var ln := float(p.get("len", sd.L * (0.1 if big else 0.05)))
	sk.box("wood", Vector3(0, -sd.T * 0.4 + 0.3, z + ln * 0.5), Vector3(0.25, h, ln), WOOD.darkened(0.4))
	if bool(p.get("tiller", false)):
		var ty := sd.top_s + 0.9
		sk.rod("wood", Vector3(0, ty - 1.0, z), Vector3(0, ty + 0.3, z), 0.25, WOOD.darkened(0.3), 6)
		sk.rod("wood", Vector3(0, ty + 0.1, z), Vector3(0, ty + 0.4, z - float(p.get("tiller_len", 4.0))), 0.1, WOOD.darkened(0.3), 4)


func _catapult(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.9)))
	var x := float(p.get("x", 0.0))
	var y := sd.top_at(z)
	var ln := float(p.get("len", 19.0))
	var ang := deg_to_rad(float(p.get("ang", 30.0))) * signf(x if x != 0.0 else 1.0)
	var bs := Basis(Vector3.UP, ang)
	sk.cyl("metal", Vector3(x, y, z), 1.0, 1.0, 0.8, 10, sup_col)
	sk.box("metal", Vector3(x, y + 1.1, z) + bs * Vector3(0, 0, -ln * 0.3), Vector3(1.0, 0.6, ln), sup_col.darkened(0.1), true, bs)
	if bool(p.get("plane", true)):
		var pc := Vector3(x, y + 1.9, z) + bs * Vector3(0, 0, -ln * 0.3)
		_seaplane(pc, bs)


func _seaplane(c: Vector3, bs: Basis) -> void:
	var col_p := Color(0.32, 0.4, 0.3)
	sk.box("metal", c, Vector3(0.9, 0.9, 8.0), col_p, false, bs)
	sk.box("metal", c + bs * Vector3(0, 0.5, -1.0), Vector3(11.0, 0.15, 1.8), col_p, false, bs)
	sk.box("metal", c + bs * Vector3(0, -1.2, -0.5), Vector3(0.8, 0.5, 5.0), col_p.lightened(0.1), false, bs)
	_disc_on(c + bs * Vector3(3.5, 0.6, -1.0), 0.5, RED)
	_disc_on(c + bs * Vector3(-3.5, 0.6, -1.0), 0.5, RED)


func _disc_on(c: Vector3, r: float, colr: Color) -> void:
	sk.kit.cylinder("flat", Transform3D(Basis(), c), r, r, 0.02, 12, colr)


func _crane(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.95)))
	var y := sd.top_at(z)
	var h := float(p.get("h", 8.0))
	sk.cyl("metal", Vector3(0, y, z), 0.5, 0.4, h, 8, sup_col)
	sk.rod("metal", Vector3(0, y + 1.0, z), Vector3(0, y + h * 1.1, z - h * 0.8), 0.22, sup_col.darkened(0.1), 6)


func _rangefinder(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.45)))
	var y := float(p.get("y", sd.top_m + 20.0))
	var ln := float(p.get("len", 10.0))
	sk.box("metal", Vector3(0, y + 0.6, z), Vector3(2.6, 1.6, 2.6), sup_col)
	sk.rod("metal", Vector3(-ln * 0.5, y + 1.0, z), Vector3(ln * 0.5, y + 1.0, z), 0.4, sup_col.darkened(0.1), 8)
	for sx: float in [-ln * 0.5, ln * 0.5]:
		sk.box("metal", Vector3(float(sx), y + 1.0, z), Vector3(0.6, 1.0, 1.0), sup_col.darkened(0.15))


func _searchlight(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.5)))
	var x := float(p.get("x", 0.0))
	var y := float(p.get("y", sd.top_m + 6.0))
	var r := float(p.get("r", 0.6))
	sk.box("metal", Vector3(x, y + 0.3, z), Vector3(0.4, 0.6, 0.4), DARK)
	sk.cyl("metal", Vector3(x, y + 0.9, z + r), r, r, r * 1.6, 10, DARK, Basis(Vector3.RIGHT, -PI * 0.5))
	sk.cyl("emissive", Vector3(x, y + 0.9, z - r * 0.62), r * 0.85, r * 0.85, 0.02, 10, Color(1, 0.95, 0.8), Basis(Vector3.RIGHT, -PI * 0.5))


func _vent(p: Dictionary) -> void:
	var z := sd.z_of(float(p.get("s", sd.L * 0.5)))
	var x := float(p.get("x", 0.0))
	var y := sd.top_at(z)
	var h := float(p.get("h", 2.5))
	var colr := _pc(p, "col", sup_col)
	sk.cyl("metal", Vector3(x, y, z), 0.45, 0.45, h, 10, colr)
	sk.kit.sphere("metal", Transform3D(Basis(), Vector3(x, y + h, z - 0.2)), 0.75, 10, 6, colr)
	sk.kit.sphere("flat", Transform3D(Basis(), Vector3(x, y + h, z - 0.55)), 0.55, 10, 6, Color(0.12, 0.05, 0.05))


## 舷窓・砲門の列（塗り）
func _ports(p: Dictionary) -> void:
	var n := int(p.get("n", 10))
	var s0 := float(p.get("s0", sd.L * 0.15))
	var s1 := float(p.get("s1", sd.L * 0.85))
	var y := float(p.get("y", sd.top_m * 0.5))
	var sz := float(p.get("size", 0.4))
	var colr := _pc(p, "col", Color(0.07, 0.07, 0.08))
	var rows := int(p.get("rows", 1))
	var round := bool(p.get("round", true))
	for row in rows:
		var yy := y - row * float(p.get("row_gap", 2.6))
		for side: float in [-1.0, 1.0]:
			for k in n:
				var z := sd.z_of(lerpf(s0, s1, (k + 0.5) / n))
				var hb := sd.half_beam(z, yy)
				if hb < 0.3:
					continue
				var x := float(side) * (hb + 0.03)
				if round:
					sk.cyl("glass" if sd.steel else "flat", Vector3(x, yy, z), sz * 0.5, sz * 0.5, 0.02, 10, colr, Basis(Vector3.FORWARD, PI * 0.5 * float(side)))
				else:
					sk.box("flat", Vector3(x, yy, z), Vector3(0.05, sz, sz * 1.1), colr)


func _stern_gallery(p: Dictionary) -> void:
	var y0 := float(p.get("y0", sd.top_s - 1.8))
	var y1 := float(p.get("y1", sd.top_s))
	var e := sd.z_ends((y0 + y1) * 0.5)
	var z := e.y + 0.15
	var hb := sd.half_beam(e.y - 0.3, (y0 + y1) * 0.5)
	var colr := _pc(p, "col", Color(0.75, 0.6, 0.3))
	sk.box("wood", Vector3(0, y0 - 0.1, z + 0.5), Vector3(hb * 2.0, 0.2, 1.0), colr)
	sk.rail(Vector3(-hb, y0, z + 1.0), Vector3(hb, y0, z + 1.0), 0.9, colr, false, false)
	var nw := maxi(2, int(hb * 2.0 / 1.4))
	for k in nw:
		sk.box("glass", Vector3(lerpf(-hb + 0.6, hb - 0.6, (k + 0.5) / nw), (y0 + y1) * 0.5 + 0.2, z), Vector3(0.6, (y1 - y0) * 0.55, 0.04), Color(0.55, 0.5, 0.35))


func _pillars(p: Dictionary) -> void:
	var pts: Array = p.get("pts", [])
	var colr := _pc(p, "col", sup_col)
	var r := float(p.get("r", 0.3))
	for q in pts:
		var a: Array = q
		var z := sd.z_of(float(a[1]))
		sk.rod("metal", Vector3(float(a[0]), float(a[2]), z), Vector3(float(a[0]), float(a[3]), z), r, colr, 6)


## 楯板（矢倉の上の胸壁・関船の舷側）
func _shields(p: Dictionary) -> void:
	var z0 := sd.z_of(float(p.get("s0", 2.0)))
	var z1 := sd.z_of(float(p.get("s1", sd.L - 2.0)))
	var y := float(p.get("y", sd.top_m))
	var h := float(p.get("h", 1.2))
	var colr := _pc(p, "col", WOOD.darkened(0.2))
	var w := float(p.get("w", 0.0))
	for side: float in [-1.0, 1.0]:
		var n := maxi(2, int((z1 - z0) / 1.8))
		for k in n:
			var za := lerpf(z0, z1, float(k) / n)
			var zb := lerpf(z0, z1, float(k + 1) / n)
			var x := float(side) * (w * 0.5 if w > 0.0 else sd.half_beam((za + zb) * 0.5, minf(y, sd.top_at((za + zb) * 0.5))) - 0.1)
			sk.box("wood", Vector3(x, y + h * 0.5, (za + zb) * 0.5), Vector3(0.1, h, zb - za - 0.06), colr, true)
			sk.box("flat", Vector3(x + float(side) * 0.04, y + h * 0.65, (za + zb) * 0.5), Vector3(0.03, 0.22, 0.18), Color(0.06, 0.05, 0.05))


# ================================================================ 外の階段・舷梯
func _ext_stairs() -> void:
	for st in sd.stairs:
		if not bool(st.get("ext", false)):
			continue
		if bool(st.get("hatch", false)):
			continue   # 甲板から船内へ下りる階段は船内側（ストリーミング）で作る
		sk.stair("metal" if sd.steel else "wood", st, sd.c("stair", Color(0.6, 0.6, 0.62) if sd.steel else WOOD.darkened(0.15)))


func _ladder() -> void:
	var lz := float(sd.ladder.get("z", 0.0))
	var side := float(sd.ladder.get("side", 1.0))
	var ly := sd.top_at(lz)
	var hb := sd.half_beam(lz, ly - 0.05)
	var x := side * (hb + 0.5)
	var colr := Color(0.7, 0.7, 0.72) if sd.steel else WOOD.darkened(0.1)
	# 斜めの舷梯と下の踊り場
	var run := float(sd.ladder.get("run", 4.0))
	var a := Vector3(x, 0.35, lz + run)
	var b := Vector3(x, ly + 0.1, lz)
	sk.rod("metal", a, b, 0.06, colr, 4)
	sk.rod("metal", a + Vector3(side * 0.8, 0, 0), b + Vector3(side * 0.8, 0, 0), 0.06, colr, 4)
	var n := maxi(4, int(ly / 0.3))
	for k in n:
		var p := a.lerp(b, (k + 0.5) / n)
		sk.box("metal", p + Vector3(side * 0.4, 0, 0), Vector3(0.8, 0.05, 0.25), colr)
	sk.box("wood", Vector3(x + side * 0.4, 0.3, lz + run + 0.6), Vector3(1.4, 0.15, 1.6), WOOD)

class_name InteriorKitsModern
extends RefCounted
## 明治〜昭和の内装キット（洋館・役所・銀行・駅舎・工場・倉庫・学校・議事堂・昭和の家・商店・団地・格納庫）。

const BRASS := Color(0.85, 0.68, 0.32)


static func build(b: InteriorBuilder, t: String) -> void:
	match t:
		"yokan": _yokan(b)
		"office": _office(b, false)
		"office_showa": _office(b, true)
		"bank": _bank(b)
		"station": _station(b)
		"factory": _factory(b)
		"warehouse": _warehouse(b, false)
		"warehouse_showa": _warehouse(b, true)
		"school": _school(b)
		"diet": _diet(b)
		"showa_shop": _showa_shop(b)
		"showa_house": _showa_house(b)
		"danchi": _danchi(b)
		"hangar": _hangar(b)
		"tower": _tower(b)
		_:
			_generic(b)


static func _generic(b: InteriorBuilder) -> void:
	b.structure()
	for i in b.floors.size():
		b.finish(b.fr(i), b.fy(i), "boards", Color.WHITE, b.floor_hole(i))
		b.lamp(InteriorKits.era_lamp(b.era), b.fc(i) + Vector3(0, b.fh(i) - 0.8, 0), i == 0)
		b.spot(b.fc(i), 0.0, "stand", i)


## 外観の窓の位置に内側の窓（win_grid: nw, nd, fh, y0）
static func _windows(b: InteriorBuilder, i: int, skip_front_center := true, w := 1.0, h := 2.0) -> void:
	var g: Dictionary = b.def.get("win_grid", {})
	if g.is_empty():
		return
	var r := b.fr(i)
	var wy := float(g["y0"]) + i * float(g["fh"]) + float(g["fh"]) * 0.5 - 0.05
	var wd := r.size.x + 0.6
	var dp := r.size.y + 0.6
	var nw := int(g["nw"])
	var nd := int(g["nd"])
	for k in nw:
		var x := -wd * 0.5 + wd * (k + 0.5) / nw
		if not (i == 0 and skip_front_center and absf(x) < 2.0):
			b.faux_window(Vector3(x, wy, r.end.y - 0.01), Vector3(0, 0, -1), w, h)
		b.faux_window(Vector3(x, wy, r.position.y + 0.01), Vector3(0, 0, 1), w, h)
	for k in nd:
		var z := -dp * 0.5 + dp * (k + 0.5) / nd
		b.faux_window(Vector3(r.end.x - 0.01, wy, z), Vector3(-1, 0, 0), w, h)
		b.faux_window(Vector3(r.position.x + 0.01, wy, z), Vector3(1, 0, 0), w, h)


## 帯状の窓（昭和のビル）
static func _band_windows(b: InteriorBuilder, i: int) -> void:
	var r := b.fr(i)
	var fhh := b.fh(i)
	var wy := b.fy(i) + fhh * 0.55 - 0.05
	for sgn in [-1.0, 1.0]:
		if i == 0 and sgn > 0.0:
			for s2 in [-1.0, 1.0]:
				var seg := r.size.x * 0.5 - 1.8
				b.faux_window(Vector3(s2 * (1.6 + seg * 0.5), wy, r.end.y - 0.01), Vector3(0, 0, -1), seg, fhh * 0.42, Color(0.6, 0.62, 0.64))
		else:
			b.faux_window(Vector3(r.get_center().x, wy, r.end.y - 0.01 if sgn > 0 else r.position.y + 0.01), Vector3(0, 0, -sgn), r.size.x - 0.8, fhh * 0.42, Color(0.6, 0.62, 0.64))


static func _stove(b: InteriorBuilder, p: Vector3) -> void:
	# だるまストーブ（石炭）＋煙突
	b.cyl("metal", p, 0.25, 0.3, 0.2, 10, Color(0.18, 0.18, 0.18), true)
	b.sph("metal", p + Vector3(0, 0.5, 0), 0.32, Color(0.2, 0.2, 0.2), 10, 6, Vector3(1, 1.1, 1))
	b.box("emissive", p + Vector3(0, 0.45, 0.3), Vector3(0.15, 0.1, 0.02), Color(1.0, 0.45, 0.12))
	b.rod("metal", p + Vector3(0, 0.8, 0), p + Vector3(0, 2.8, 0), 0.07, Color(0.2, 0.2, 0.2), 6)
	b.fire_pts.append(p + Vector3(0, 0.5, 0))


# ================================================================ 明治
static func _yokan(b: InteriorBuilder) -> void:
	# 洋館（鹿鳴館・旧岩崎邸の応接間を参考）: 寄木張りの床と絨毯、壁紙と腰板、暖炉、シャンデリア、ソファとテーブル、
	# 柱時計・肖像画・ピアノ。2 階は書斎と寝室
	var rokumei: bool = "rokumeikan" in b.def.get("tags", [])
	b.structure("flat", Color(0.95, 0.93, 0.88), "western", Color(0.45, 0.28, 0.18))
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.finish(r, y, "parquet")
	b.wallpaper(0, Color(0.72, 0.42, 0.42) if not rokumei else Color(0.86, 0.8, 0.62))
	_windows(b, 0)
	b.fireplace(Vector3(r.end.x - 0.02, y, r.get_center().y), Vector3(-1, 0, 0))
	var c := Vector3(r.get_center().x + 0.5, y, r.get_center().y + 0.4)
	b.lamp("chandelier", c + Vector3(0, h - 1.1, 0))
	if rokumei:
		# 舞踏室: 中央は空けて、壁際に椅子・奥に楽団
		b.lamp("chandelier", c + Vector3(-r.size.x * 0.28, h - 1.1, 0), false)
		b.lamp("chandelier", c + Vector3(r.size.x * 0.25, h - 1.1, 0), false)
		for k in int(r.size.x / 1.2):
			b.chair(Vector3(r.position.x + 0.8 + k * 1.2, y, r.end.y - 0.6), PI)
		for k in 4:
			b.chair(Vector3(r.position.x + 1.5 + k * 0.8, y, r.position.y + 1.5), 0.0)
			b.spot(Vector3(r.position.x + 1.5 + k * 0.8, y, r.position.y + 1.6), 0.0, "work")
		for k in 6:
			b.spot(c + Vector3(cos(k * 1.05) * 2.0, 0, sin(k * 1.05) * 1.4), k * 1.05, "scene")
		b.table(Vector3(r.position.x + 3.0, y, r.end.y - 2.0), 2.4, 0.8, 0.8, Color(0.4, 0.25, 0.15), 0.0, Color(0.97, 0.97, 0.95))
	else:
		b.rug(Rect2(c.x - 2.0, c.z - 1.5, 4.0, 3.0), y, Color(0.55, 0.15, 0.18))
		b.table(c, 1.1, 1.1, 0.7, Color(0.4, 0.24, 0.14), 0.0, Color(0.95, 0.93, 0.88))
		b.sofa(c + Vector3(0, 0, -1.3), 0.0, 1.9)
		for sgn in [-1.0, 1.0]:
			b.chair(c + Vector3(sgn * 1.2, 0, 0.3), -sgn * PI * 0.5)
			b.spot(c + Vector3(sgn * 1.2, 0, 0.3), -sgn * PI * 0.5, "sit")
		b.spot(c + Vector3(0, 0, -1.2), 0.0, "sit")
		b.lamp("lamp", c + Vector3(0, 0.72, 0), false)
	# ピアノ・柱時計・肖像画
	var pz := r.position.y + 0.5
	b.box("wood", Vector3(r.position.x + 1.4, y + 0.65, pz), Vector3(1.5, 1.3, 0.6), Color(0.12, 0.08, 0.06), 0.0, true)
	b.box("flat", Vector3(r.position.x + 1.4, y + 0.78, pz + 0.31), Vector3(1.3, 0.06, 0.02), Color(0.95, 0.95, 0.92))
	b.clock(Vector3(r.position.x + 0.35, y, r.get_center().y + 1.5), Vector3(1, 0, 0), true)
	b.frame_pic(Vector3(r.get_center().x, y + 2.2, r.position.y + 0.04), Vector3(0, 0, 1), 0.8, 1.0)
	b.frame_pic(Vector3(r.position.x + 0.04, y + 2.0, r.get_center().y - 1.0), Vector3(1, 0, 0), 0.7, 0.5, Color(0.4, 0.55, 0.4))
	# 鉢植えの棕櫚
	var pp := Vector3(r.end.x - 0.6, y, r.end.y - 0.6)
	b.cyl("earth", pp, 0.2, 0.25, 0.4, 10, Color(0.6, 0.4, 0.3), true)
	for k in 5:
		var a := TAU * k / 5.0
		b.rod("flat", pp + Vector3(0, 0.4, 0), pp + Vector3(cos(a) * 0.5, 1.2, sin(a) * 0.5), 0.05, Color(0.2, 0.45, 0.22), 3)
	b.spot(InteriorKits._door_in(b, 0, 1.2), PI, "stand")
	b.fire_pts.append(c)
	if b.floors.size() > 1:
		var r2 := b.fr(1)
		var y2 := b.fy(1)
		b.finish(r2, y2, "parquet", Color.WHITE, b.floor_hole(1))
		b.wallpaper(1, Color(0.4, 0.5, 0.42))
		_windows(b, 1)
		var dk := Vector3(r2.get_center().x + 1.5, y2, r2.position.y + 1.2)
		b.desk(dk, PI)
		b.chair(dk + Vector3(0, 0, -0.6), 0.0, Color(0.4, 0.24, 0.14), Color(0.25, 0.3, 0.2))
		b.spot(dk + Vector3(0, 0, -0.6), PI, "sit", 1)
		b.lamp("lamp", dk + Vector3(0.4, 0.77, 0))
		for k in 2:
			b.bookshelf(Vector3(r2.end.x - 1.0 - k * 1.3, y2, r2.position.y + 0.22), 0.0)
		# 寝台（真鍮の枠）
		var bd := Vector3(r2.end.x - 1.4, y2, r2.end.y - 1.4)
		b.box("cloth", bd + Vector3(0, 0.45, 0), Vector3(1.4, 0.3, 2.0), Color(0.95, 0.94, 0.9), 0.0, true)
		b.box("cloth", bd + Vector3(0, 0.62, 0.3), Vector3(1.42, 0.06, 1.3), Color(0.55, 0.2, 0.25))
		for sgn in [-1.0, 1.0]:
			b.rod("metal", bd + Vector3(-0.7, 0, sgn * 1.0), bd + Vector3(-0.7, 1.2, sgn * 1.0), 0.03, BRASS, 5)
			b.rod("metal", bd + Vector3(0.7, 0, sgn * 1.0), bd + Vector3(0.7, 1.0, sgn * 1.0), 0.03, BRASS, 5)
		b.rod("metal", bd + Vector3(-0.7, 1.2, -1.0), bd + Vector3(-0.7, 1.2, 1.0), 0.03, BRASS, 5)
		b.box("wood", Vector3(r2.position.x + 0.4, y2 + 1.0, r2.end.y - 1.0), Vector3(0.6, 2.0, 1.2), Color(0.4, 0.24, 0.14), 0.0, true)


static func _office(b: InteriorBuilder, showa: bool) -> void:
	# 明治の官庁（太政官・司法省）/ 昭和の事務所: カウンターで仕切った窓口、机の列、書類棚、時計。
	# 明治: 板張り・ガス灯・だるまストーブ・帳簿と硯 / 昭和: リノリウム・スチール机・黒電話・タイプライター・扇風機・蛍光灯
	b.structure("flat", Color(0.93, 0.92, 0.88), "solid" if showa else "western", Color(0.62, 0.6, 0.56) if showa else Color(0.45, 0.28, 0.18))
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.finish(r, y, "linoleum" if showa else "boards", Color(0.55, 0.6, 0.55) if showa else Color.WHITE)
	if showa:
		_band_windows(b, 0)
	else:
		b.wallpaper(0, Color(0.88, 0.85, 0.75), Color(0.42, 0.3, 0.2))
		_windows(b, 0)
	# 窓口カウンター（入口側の客溜まりを仕切る）
	var cz := r.end.y - minf(3.0, r.size.y * 0.35)
	var cw := r.size.x - 3.0
	b.box("wood", Vector3(r.get_center().x + 1.0, y + 0.5, cz), Vector3(cw, 1.0, 0.5), Color(0.45, 0.3, 0.2) if not showa else Color(0.6, 0.55, 0.45), 0.0, true)
	b.box("wood", Vector3(r.get_center().x + 1.0, y + 1.02, cz), Vector3(cw + 0.1, 0.05, 0.6), Color(0.35, 0.22, 0.14))
	for k in int(cw / 1.6):
		var x := r.get_center().x + 1.0 - cw * 0.5 + 0.8 + k * 1.6
		b.box("metal" if not showa else "glass", Vector3(x, y + 1.45, cz), Vector3(0.9, 0.8, 0.03), BRASS if not showa else Color(0.7, 0.8, 0.85))
		b.box("flat", Vector3(x, y + 1.95, cz), Vector3(0.6, 0.18, 0.04), Color(0.95, 0.93, 0.85))
		b.spot(Vector3(x, y, cz - 0.7), 0.0, "work")
		b.spot(Vector3(x, y, cz + 0.8), PI, "stand")
	# 机の列
	var dz := r.position.y + 1.2
	while dz < cz - 1.2:
		var nd := int((r.size.x - 1.0) / 1.7)
		for k in nd:
			var p := Vector3(r.position.x + 1.1 + k * 1.7, y, dz)
			if showa:
				b.box("metal", p + Vector3(0, 0.72, 0), Vector3(1.2, 0.04, 0.7), Color(0.55, 0.58, 0.6), 0.0, true)
				b.box("metal", p + Vector3(0.4, 0.36, 0), Vector3(0.38, 0.7, 0.66), Color(0.5, 0.53, 0.55))
				b.box("metal", p + Vector3(-0.3, 0.8, 0.15), Vector3(0.22, 0.1, 0.16), Color(0.1, 0.1, 0.1))
				if k % 3 == 1:
					b.box("metal", p + Vector3(0.2, 0.82, -0.05), Vector3(0.4, 0.15, 0.32), Color(0.25, 0.28, 0.3))
				b.chair(p + Vector3(0, 0, -0.55), 0.0, Color(0.4, 0.42, 0.45), Color(0.3, 0.35, 0.4))
			else:
				b.desk(p, 0.0, 1.3)
				b.box("flat", p + Vector3(-0.3, 0.8, 0.1), Vector3(0.25, 0.08, 0.3), Color(0.9, 0.86, 0.76))
				b.chair(p + Vector3(0, 0, -0.55), 0.0)
			b.spot(p + Vector3(0, 0, -0.55), PI, "sit")
		dz += 1.9
	# 書類棚・時計・ストーブ／扇風機
	for k in 3:
		var p := Vector3(r.position.x + 0.3, y, r.position.y + 1.0 + k * 1.3)
		if p.z > cz - 0.5:
			break
		if showa:
			b.box("metal", p + Vector3(0, 0.9, 0), Vector3(0.45, 1.8, 1.0), Color(0.55, 0.6, 0.58), 0.0, true)
		else:
			b.shelf(p, PI * 0.5, 1.1, 2.0, 0.4, 5, Color(0.4, 0.26, 0.16))
	b.clock(Vector3(r.get_center().x, y + 2.6, r.position.y + 0.08), Vector3(0, 0, 1))
	if showa:
		var fp := Vector3(r.end.x - 0.8, y, r.get_center().y)
		b.cyl("metal", fp, 0.15, 0.1, 1.3, 8, Color(0.3, 0.32, 0.35))
		b.sph("metal", fp + Vector3(0, 1.4, 0), 0.22, Color(0.3, 0.45, 0.4), 8, 5, Vector3(1, 1, 0.4))
		for k in 3:
			b.lamp("fluorescent", Vector3(r.position.x + r.size.x * (k + 0.5) / 3.0, y + h - 0.15, r.get_center().y), k == 1)
	else:
		_stove(b, Vector3(r.end.x - 1.0, y, r.get_center().y - 0.5))
		for k in 2:
			b.lamp("gaslight", Vector3(r.position.x + r.size.x * (k + 1) / 3.0, y + h - 0.6, r.get_center().y), k == 0)
	b.spot(InteriorKits._door_in(b, 0, 1.0), PI, "guard")
	if b.floors.size() > 1:
		var r2 := b.fr(1)
		var y2 := b.fy(1)
		b.finish(r2, y2, "carpet" if not showa else "linoleum", Color(0.35, 0.12, 0.12) if not showa else Color(0.5, 0.55, 0.5), b.floor_hole(1))
		if showa:
			_band_windows(b, 1)
		else:
			b.wallpaper(1, Color(0.82, 0.76, 0.62))
			_windows(b, 1)
		# 長官室: 大きな机と応接・会議の卓
		var dk := Vector3(r2.get_center().x + r2.size.x * 0.25, y2, r2.position.y + 1.3)
		b.desk(dk, PI, 1.8, Color(0.35, 0.2, 0.12))
		b.chair(dk + Vector3(0, 0, -0.65), 0.0, Color(0.3, 0.18, 0.1), Color(0.2, 0.25, 0.4))
		b.spot(dk + Vector3(0, 0, -0.65), PI, "scene", 1)
		b.frame_pic(Vector3(dk.x, y2 + 2.2, r2.position.y + 0.04), Vector3(0, 0, 1), 0.7, 0.9)
		var mt := Vector3(r2.get_center().x - r2.size.x * 0.15, y2, r2.get_center().y + 0.6)
		b.table(mt, 3.2, 1.2, 0.74, Color(0.4, 0.24, 0.14), 0.0, Color(0.2, 0.35, 0.25))
		for k in 4:
			for sgn in [-1.0, 1.0]:
				b.chair(mt + Vector3(-1.2 + k * 0.8, 0, sgn * 0.9), PI if sgn > 0 else 0.0)
				b.spot(mt + Vector3(-1.2 + k * 0.8, 0, sgn * 0.9), PI if sgn > 0 else 0.0, "sit", 1)
		b.lamp("fluorescent" if showa else "chandelier", mt + Vector3(0, b.fh(1) - (0.15 if showa else 1.0), 0))


static func _bank(b: InteriorBuilder) -> void:
	# 銀行の営業室（日本銀行本店の石造の営業場を参考）: 大理石の床・柱、窓口のカウンター、待合の長椅子、大金庫の扉
	b.structure("flat", Color(0.92, 0.9, 0.85), "solid", Color(0.85, 0.82, 0.76))
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.finish(r, y, "stone", Color(0.85, 0.83, 0.78))
	_windows(b, 0)
	for ix in 4:
		for sgn in [-1.0, 1.0]:
			b.cyl("stonewall", Vector3(r.position.x + r.size.x * (ix + 0.5) / 4.0, y, r.get_center().y + sgn * r.size.y * 0.22), 0.3, 0.3, h, 12, Color(0.92, 0.9, 0.86), true)
	var cz := r.get_center().y - 0.6
	b.box("stonewall", Vector3(r.get_center().x, y + 0.55, cz), Vector3(r.size.x - 2.0, 1.1, 0.6), Color(0.6, 0.5, 0.42), 0.0, true)
	for k in int((r.size.x - 2.0) / 1.5):
		var x := r.position.x + 1.75 + k * 1.5
		b.box("glass", Vector3(x, y + 1.6, cz), Vector3(1.2, 1.0, 0.03), Color(0.75, 0.82, 0.85))
		b.spot(Vector3(x, y, cz - 0.7), 0.0, "work")
	for k in 3:
		var p := Vector3(r.position.x + 2.0 + k * 3.0, y, r.end.y - 2.0)
		b.box("wood", p + Vector3(0, 0.42, 0), Vector3(2.0, 0.08, 0.5), Color(0.4, 0.24, 0.14), 0.0, true)
		b.box("wood", p + Vector3(0, 0.75, -0.24), Vector3(2.0, 0.6, 0.06), Color(0.4, 0.24, 0.14))
		b.spot(p + Vector3(0, 0, 0.1), 0.0, "sit")
	var v := Vector3(r.position.x + 0.05, y, r.position.y + 1.6)
	b.cylt("metal", Transform3D(Basis(Vector3.BACK, PI * 0.5), v + Vector3(0, 1.2, 0)), 1.0, 1.0, 0.25, 20, Color(0.55, 0.56, 0.58))
	for k in 6:
		b.rod("metal", v + Vector3(0.28, 1.2, 0), v + Vector3(0.28, 1.2 + cos(k * 1.05) * 0.5, sin(k * 1.05) * 0.5), 0.03, Color(0.3, 0.3, 0.32), 4)
	b.clock(Vector3(r.get_center().x, y + 3.0, r.position.y + 0.08), Vector3(0, 0, 1))
	for k in 3:
		b.lamp("chandelier", Vector3(r.position.x + r.size.x * (k + 0.5) / 3.0, y + h - 1.2, r.get_center().y + 1.5), k == 1)
	b.spot(InteriorKits._door_in(b, 0, 1.0), PI, "guard")
	if b.floors.size() > 1:
		var r2 := b.fr(1)
		b.finish(r2, b.fy(1), "carpet", Color(0.3, 0.12, 0.12), b.floor_hole(1))
		_windows(b, 1)
		var dk := Vector3(r2.get_center().x, b.fy(1), r2.position.y + 1.5)
		b.desk(dk, PI, 2.0)
		b.spot(dk + Vector3(0, 0, -0.6), PI, "scene", 1)
		b.lamp("chandelier", dk + Vector3(0, b.fh(1) - 1.0, 1.0))


static func _station(b: InteriorBuilder) -> void:
	# 駅舎（新橋停車場 1872 を参考）: 石張りの待合室、木の長椅子、出札口、改札口のラッチ、大時計、時刻表、手荷物台、ガス灯。2 階は駅長室
	b.structure("flat", Color(0.93, 0.92, 0.88), "western", Color(0.45, 0.3, 0.2))
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.finish(r, y, "tile", Color(0.75, 0.72, 0.66))
	b.wallpaper(0, Color(0.9, 0.88, 0.8), Color(0.4, 0.3, 0.22))
	_windows(b, 0)
	# 出札口（奥の壁）
	var tz := r.position.y + 0.4
	b.box("wood", Vector3(r.get_center().x - 1.5, y + 0.55, tz + 0.3), Vector3(4.0, 1.1, 0.6), Color(0.45, 0.3, 0.2), 0.0, true)
	for k in 3:
		var x := r.get_center().x - 2.8 + k * 1.3
		b.box("metal", Vector3(x, y + 1.6, tz + 0.6), Vector3(0.9, 1.0, 0.02), BRASS)
		b.box("flat", Vector3(x, y + 2.25, tz + 0.62), Vector3(0.7, 0.2, 0.02), Color(0.95, 0.92, 0.82))
		b.spot(Vector3(x, y, tz - 0.2), PI, "work")
	# 時刻表と大時計
	b.box("wood", Vector3(r.get_center().x + 2.5, y + 2.2, r.position.y + 0.05), Vector3(2.0, 1.2, 0.04), Color(0.15, 0.2, 0.15))
	for k in 5:
		b.box("flat", Vector3(r.get_center().x + 2.5, y + 2.6 - k * 0.2, r.position.y + 0.08), Vector3(1.7, 0.04, 0.01), Color(0.95, 0.95, 0.9))
	b.clock(Vector3(r.get_center().x, y + h - 1.0, r.position.y + 0.08), Vector3(0, 0, 1))
	# 待合の長椅子
	for row in 3:
		for k in 2:
			var p := Vector3(r.get_center().x - 3.0 + k * 6.0, y, r.position.y + 2.6 + row * 1.6)
			if p.z > r.end.y - 2.0:
				continue
			b.box("wood", p + Vector3(0, 0.42, 0), Vector3(2.6, 0.06, 0.45), Color(0.55, 0.38, 0.24), 0.0, true)
			b.box("wood", p + Vector3(0, 0.75, -0.22), Vector3(2.6, 0.5, 0.05), Color(0.55, 0.38, 0.24))
			for j in 3:
				b.spot(p + Vector3(-0.8 + j * 0.8, 0, 0.1), 0.0, "sit")
	# 改札口（側面の出口へ）
	var gx := r.end.x - 1.2
	for k in 3:
		b.box("wood", Vector3(gx, y + 0.5, r.get_center().y - 1.2 + k * 1.2), Vector3(1.0, 1.0, 0.15), Color(0.45, 0.3, 0.2), 0.0, true)
		b.box("metal", Vector3(gx - 0.2, y + 1.02, r.get_center().y - 1.2 + k * 1.2), Vector3(0.2, 0.04, 0.17), BRASS)
	b.spot(Vector3(gx, y, r.get_center().y - 0.6), -PI * 0.5, "work")
	# 手荷物（行李・トランク）
	for k in 3:
		b.box("wood", Vector3(r.position.x + 0.7, y + 0.2 + k * 0.32, r.end.y - 1.4), Vector3(0.8, 0.3, 0.5), [Color(0.45, 0.28, 0.18), Color(0.25, 0.3, 0.38), Color(0.6, 0.5, 0.32)][k], 0.1 * k, k == 0)
	for k in 2:
		b.lamp("gaslight", Vector3(r.get_center().x + (k - 0.5) * r.size.x * 0.5, y + h - 0.7, r.get_center().y), k == 0)
	b.spot(InteriorKits._door_in(b, 0, 1.0), PI, "stand")
	if b.floors.size() > 1:
		var r2 := b.fr(1)
		var y2 := b.fy(1)
		b.finish(r2, y2, "boards", Color.WHITE, b.floor_hole(1))
		_windows(b, 1)
		var dk := Vector3(r2.get_center().x + 1.0, y2, r2.position.y + 1.3)
		b.desk(dk, PI)
		# 電信機
		b.box("metal", dk + Vector3(-0.4, 0.82, 0.1), Vector3(0.3, 0.12, 0.2), Color(0.5, 0.4, 0.25))
		b.spot(dk + Vector3(0, 0, -0.6), PI, "sit", 1)
		b.lamp("lamp", dk + Vector3(0.4, 0.77, 0))


static func _factory(b: InteriorBuilder) -> void:
	# 煉瓦の製糸工場（富岡製糸場 繰糸所 1872 を参考）: 繰糸機の列（煮繭鍋と小枠）、天井の主軸（ライン・シャフト）と調車・ベルト、
	# 蒸気管、鉄の柱
	b.structure("wood", Color(0.62, 0.5, 0.38))
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.finish(r, y, "boards", Color(0.6, 0.48, 0.36))
	var shaft_y := y + 3.4
	var rows := 2
	for row in rows:
		var z := r.position.y + r.size.y * (row + 1) / (rows + 1)
		b.rod("metal", Vector3(r.position.x + 0.5, shaft_y, z), Vector3(r.end.x - 0.5, shaft_y, z), 0.06, Color(0.3, 0.3, 0.32), 6)
		var n := int((r.size.x - 2.0) / 1.6)
		for k in n:
			var x := r.position.x + 1.4 + k * 1.6
			var p := Vector3(x, y, z)
			# 繰糸機（台・鍋・小枠）
			b.box("wood", p + Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.7), Color(0.5, 0.36, 0.24), 0.0, true)
			b.cyl("metal", p + Vector3(-0.25, 0.9, 0.1), 0.18, 0.16, 0.14, 10, Color(0.6, 0.58, 0.55))
			b.cylt("wood", Transform3D(Basis(Vector3.BACK, PI * 0.5), p + Vector3(0.5, 1.25, -0.1)), 0.22, 0.22, 0.5, 8, Color(0.75, 0.6, 0.42))
			for j in 4:
				b.sph("flat", p + Vector3(-0.32 + j * 0.06, 0.98, 0.1), 0.03, Color(0.98, 0.96, 0.9), 5, 3)
			# 調車とベルト
			b.cylt("metal", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.27, shaft_y, z)), 0.2, 0.2, 0.08, 12, Color(0.35, 0.35, 0.36))
			b.rod("cloth", Vector3(x + 0.28, shaft_y - 0.15, z + 0.12), p + Vector3(0.28, 1.2, -0.1), 0.02, Color(0.35, 0.25, 0.18), 3)
			b.rod("cloth", Vector3(x + 0.28, shaft_y - 0.15, z - 0.12), p + Vector3(0.28, 1.2, -0.25), 0.02, Color(0.35, 0.25, 0.18), 3)
			b.spot(p + Vector3(0, 0, 0.75), PI, "work")
		# 鉄の柱
		for k in 4:
			b.cyl("metal", Vector3(r.position.x + r.size.x * (k + 0.5) / 4.0, y, z + 1.0), 0.12, 0.12, h, 8, Color(0.3, 0.32, 0.3), true)
	# 蒸気管（壁沿い）とボイラーへの口
	b.rod("metal", Vector3(r.position.x + 0.2, y + 2.2, r.position.y + 0.2), Vector3(r.end.x - 0.2, y + 2.2, r.position.y + 0.2), 0.08, Color(0.55, 0.45, 0.35), 6)
	for k in 4:
		b.faux_window(Vector3(r.position.x + r.size.x * (k + 0.5) / 4.0, y + 4.5, r.position.y + 0.01), Vector3(0, 0, 1), 1.2, 1.8)
		b.faux_window(Vector3(r.position.x + r.size.x * (k + 0.5) / 4.0, y + 4.5, r.end.y - 0.01), Vector3(0, 0, -1), 1.2, 1.8)
	for k in 2:
		b.lamp("gaslight", Vector3(r.position.x + r.size.x * (k + 1) / 3.0, y + 4.0, r.get_center().y), k == 0)
	b.spot(InteriorKits._door_in(b, 0, 1.2), PI, "stand")


static func _warehouse(b: InteriorBuilder, showa: bool) -> void:
	# 煉瓦倉庫（横浜赤レンガ倉庫を参考: 生糸・茶箱・樽・麻袋・秤）/ 昭和の倉庫（段ボール・パレット・ドラム缶・リヤカー）
	b.structure("wood" if not showa else "flat", Color(0.6, 0.5, 0.4) if not showa else Color(0.85, 0.85, 0.82), "solid", Color(0.65, 0.63, 0.6))
	var r := b.fr(0)
	var y := b.fy(0)
	b.finish(r, y, "boards" if not showa else "concrete", Color.WHITE)
	var nx := int((r.size.x - 1.0) / 2.4)
	for k in nx:
		var x := r.position.x + 1.4 + k * 2.4
		for zi in 2:
			var z := r.position.y + 1.0 + zi * 2.0
			if showa:
				b.box("wood", Vector3(x, y + 0.07, z), Vector3(1.2, 0.14, 1.0), Color(0.6, 0.48, 0.32))
				for j in 3:
					b.box("flat", Vector3(x + (j % 2) * 0.1 - 0.05, y + 0.44 + j * 0.5, z), Vector3(1.0, 0.48, 0.8), Color(0.72, 0.58, 0.4).darkened(j * 0.05))
				b.col_box(Vector3(x, y + 0.8, z), Vector3(1.2, 1.6, 1.0))
			elif (k + zi) % 3 == 0:
				for j in 3:
					b.box("cloth", Vector3(x, y + 0.25 + j * 0.45, z), Vector3(1.1, 0.42, 0.7), Color(0.95, 0.92, 0.82), 0.05 * j)
				b.col_box(Vector3(x, y + 0.7, z), Vector3(1.1, 1.4, 0.7))
			elif (k + zi) % 3 == 1:
				for j in 2:
					b.crate(Vector3(x - 0.3 + j * 0.6, y, z), 0.55, 0.0, Color(0.75, 0.6, 0.38))
					b.crate(Vector3(x - 0.3 + j * 0.6, y + 0.55, z), 0.55, 0.1, Color(0.75, 0.6, 0.38))
			else:
				for j in 2:
					b.barrel(Vector3(x - 0.35 + j * 0.7, y, z))
	if showa:
		for k in 3:
			b.barrel(Vector3(r.end.x - 0.6, y, r.end.y - 0.6 - k * 0.7), Color(0.2, 0.35, 0.55))
		# リヤカー
		var rc := Vector3(r.position.x + 1.6, y, r.end.y - 1.2)
		b.box("wood", rc + Vector3(0, 0.55, 0), Vector3(1.6, 0.06, 0.9), Color(0.55, 0.4, 0.28))
		for sgn in [-1.0, 1.0]:
			b.cylt("metal", Transform3D(Basis(Vector3.BACK, PI * 0.5), rc + Vector3(-0.05, 0.35, sgn * 0.5)), 0.35, 0.35, 0.05, 12, Color(0.2, 0.2, 0.2))
		for k in 2:
			b.lamp("bulb", Vector3(r.position.x + r.size.x * (k + 1) / 3.0, y + b.fh(0) - 1.0, r.get_center().y), k == 0)
	else:
		# 台秤
		var sc := Vector3(r.end.x - 1.2, y, r.end.y - 1.2)
		b.box("metal", sc + Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.6), Color(0.3, 0.32, 0.3), 0.0, true)
		b.rod("metal", sc + Vector3(0.35, 0.2, 0), sc + Vector3(0.35, 1.2, 0), 0.03, Color(0.3, 0.32, 0.3), 4)
		b.box("metal", sc + Vector3(0.1, 1.2, 0), Vector3(0.6, 0.04, 0.04), BRASS)
		for k in 2:
			b.lamp("lamp", Vector3(r.position.x + r.size.x * (k + 1) / 3.0, y + 3.0, r.get_center().y), k == 0)
	b.spot(Vector3(r.get_center().x, y, r.end.y - 1.0), PI, "work")
	b.spot(InteriorKits._door_in(b, 0, 1.0), PI, "stand")


static func _school(b: InteriorBuilder) -> void:
	# 明治の学校（旧開智学校 1876 を参考）: 玄関の土間と下駄箱、左右の教室（黒板・教壇・教卓・二人掛けの机と長椅子・掛図・だるまストーブ）、
	# 2 階は講堂
	b.structure("flat", Color(0.94, 0.92, 0.86), "western", Color(0.5, 0.34, 0.22))
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.finish(r, y, "boards", Color.WHITE)
	# 玄関（塔屋）
	if b.floors.size() > 2:
		var hall := b.fr(2)
		b.finish(hall, b.fy(2), "stone", Color(0.65, 0.62, 0.58))
		for k in 2:
			b.shelf(Vector3(hall.position.x + 0.25, b.fy(2), hall.get_center().y), PI * 0.5, 2.4, 1.2, 0.35, 4, Color(0.55, 0.42, 0.3))
		b.clock(Vector3(hall.end.x - 0.06, b.fy(2) + 2.2, hall.get_center().y), Vector3(-1, 0, 0))
		b.lamp("lamp", Vector3(hall.get_center().x, b.fy(2) + 2.6, hall.get_center().y))
		b.spot(Vector3(hall.get_center().x, b.fy(2), hall.get_center().y), PI, "stand")
	# 教室の間仕切り（中央の廊下を残す）
	for sgn in [-1.0, 1.0]:
		var x: float = sgn * 2.2
		b.partition(Vector2(x, r.position.y), Vector2(x, r.end.y), y, h, "darkwood", Color(0.9, 0.86, 0.76), [[r.size.y - 2.2, r.size.y - 1.0, 2.1]])
	for sgn in [-1.0, 1.0]:
		var cr := Rect2(2.2, r.position.y, r.end.x - 2.2, r.size.y) if sgn > 0 else Rect2(r.position.x, r.position.y, -2.2 - r.position.x, r.size.y)
		var bx_ := cr.end.x - 0.06 if sgn > 0 else cr.position.x + 0.06
		var n := Vector3(-sgn, 0, 0)
		# 黒板（外側の妻壁）と教壇
		b.box("flat", Vector3(bx_, y + 1.5, cr.get_center().y), Vector3(0.04, 1.2, 3.6), Color(0.12, 0.22, 0.16))
		b.box("wood", Vector3(bx_, y + 0.86, cr.get_center().y) + n * 0.05, Vector3(0.1, 0.04, 3.6), Color(0.55, 0.4, 0.28))
		b.box("wood", Vector3(bx_, y + 0.1, cr.get_center().y) + n * 0.8, Vector3(1.4, 0.2, 4.4), Color(0.6, 0.45, 0.3), 0.0, true)
		b.box("wood", Vector3(bx_, y + 0.6, cr.get_center().y) + n * 1.2, Vector3(0.6, 0.8, 1.0), Color(0.5, 0.34, 0.22), 0.0, true)
		b.spot(Vector3(bx_, y + 0.2, cr.get_center().y) + n * 0.8, atan2(n.x, n.z), "scene")
		b.frame_pic(Vector3(cr.get_center().x, y + 2.0, cr.position.y + 0.04), Vector3(0, 0, 1), 1.0, 1.2, Color(0.85, 0.8, 0.6))
		# 机の列
		var cols_n := 3
		for ci in cols_n:
			for ri in 3:
				var dx := (bx_ + n.x * 2.6) + n.x * ri * 1.2
				var dz := cr.position.y + 1.2 + ci * (cr.size.y - 2.4) / maxf(cols_n - 1, 1)
				var p := Vector3(dx, y, dz)
				if not cr.grow(-0.4).has_point(Vector2(p.x, p.z)):
					continue
				b.box("wood", p + Vector3(0, 0.62, 0), Vector3(0.45, 0.04, 1.2), Color(0.62, 0.46, 0.3), 0.0, true)
				b.box("wood", p + Vector3(0, 0.3, 0), Vector3(0.4, 0.6, 0.05), Color(0.5, 0.36, 0.24))
				b.box("wood", p + Vector3(-n.x * 0.45, 0.38, 0), Vector3(0.3, 0.04, 1.2), Color(0.55, 0.4, 0.26))
				for j in 2:
					b.spot(p + Vector3(-n.x * 0.45, 0, -0.3 + j * 0.6), atan2(n.x, n.z), "sit")
		_stove(b, Vector3(cr.get_center().x, y, cr.end.y - 1.0))
		b.lamp("lamp", Vector3(cr.get_center().x, y + h - 0.9, cr.get_center().y), sgn < 0)
	if b.floors.size() > 1:
		var r2 := b.fr(1)
		var y2 := b.fy(1)
		b.finish(r2, y2, "boards", Color.WHITE, b.floor_hole(1))
		# 講堂: 正面の演壇と長椅子
		b.box("wood", Vector3(r2.end.x - 1.2, y2 + 0.2, r2.get_center().y), Vector3(2.0, 0.4, 5.0), Color(0.6, 0.45, 0.3), 0.0, true)
		b.box("wood", Vector3(r2.end.x - 1.0, y2 + 0.9, r2.get_center().y), Vector3(0.5, 1.0, 0.8), Color(0.45, 0.3, 0.2), 0.0, true)
		b.spot(Vector3(r2.end.x - 1.4, y2 + 0.4, r2.get_center().y), -PI * 0.5, "scene", 1)
		for ri in 5:
			for side in [-1.0, 1.0]:
				var p := Vector3(r2.end.x - 3.5 - ri * 1.4, y2, r2.get_center().y + side * 1.6)
				if p.x < r2.position.x + 1.0:
					continue
				b.box("wood", p + Vector3(0, 0.42, 0), Vector3(0.4, 0.06, 2.2), Color(0.55, 0.4, 0.26), 0.0, true)
				b.spot(p, -PI * 0.5, "sit", 1)
		for k in 2:
			b.lamp("lamp", Vector3(r2.get_center().x + (k - 0.5) * r2.size.x * 0.4, y2 + b.fh(1) - 0.9, r2.get_center().y), k == 0)


static func _diet(b: InteriorBuilder) -> void:
	# 国会議事堂の中央広間（1936）: 床のモザイク、四隅の台座に伊藤博文・大隈重信・板垣退助の銅像と空の台座、
	# 列柱、奥の大階段、天井のステンドグラス
	b.structure("flat", Color(0.9, 0.86, 0.76))
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.finish(r, y, "stone", Color(0.82, 0.78, 0.7))
	var c := Vector3(r.get_center().x, y, r.get_center().y)
	for k in 4:
		var s := 7.0 - k * 1.6
		b.hrect("flat", Rect2(c.x - s, c.z - s, s * 2.0, s * 2.0), y + 0.02 + k * 0.002, [Color(0.55, 0.3, 0.25), Color(0.85, 0.8, 0.68), Color(0.3, 0.38, 0.45), Color(0.9, 0.85, 0.7)][k])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + Vector3(sx * 6.5, 0, sz * 6.5)
			b.box("stonewall", p + Vector3(0, 0.8, 0), Vector3(1.6, 1.6, 1.6), Color(0.85, 0.82, 0.75), 0.0, true)
			if not (sx > 0 and sz > 0):
				# 銅像（立像）
				b.cyl("metal", p + Vector3(0, 1.6, 0), 0.32, 0.26, 1.3, 10, Color(0.32, 0.38, 0.32))
				b.sph("metal", p + Vector3(0, 3.05, 0), 0.2, Color(0.32, 0.38, 0.32), 8, 5)
				b.box("metal", p + Vector3(0, 2.4, 0.05), Vector3(0.8, 0.35, 0.35), Color(0.3, 0.36, 0.3))
			for k in 2:
				var a := TAU * k / 2.0
				b.cyl("stonewall", c + Vector3(sx * 9.5, 0, sz * (3.0 + k * 6.0)), 0.5, 0.5, h, 12, Color(0.88, 0.84, 0.76), true)
	# 大階段（奥）と踊り場
	var sa := Vector3(c.x, y, r.position.y + 7.0)
	var sb := Vector3(c.x, y + 3.0, r.position.y + 2.6)
	b.stairs({"a": sa, "b": sb, "w": 6.0}, "solid", Color(0.85, 0.82, 0.75))
	b.box("stonewall", Vector3(c.x, y + 1.5, r.position.y + 1.3), Vector3(r.size.x - 1.0, 3.0, 2.6), Color(0.85, 0.82, 0.75), 0.0, true)
	b.box("cloth", Vector3(c.x, y + 3.02, r.position.y + 1.3), Vector3(6.0, 0.02, 2.6), Color(0.6, 0.12, 0.15))
	# ステンドグラスの天井
	var cy := y + h - 0.1
	for ix in 6:
		for iz in 6:
			var q := Rect2(c.x - 6.0 + ix * 2.0 + 0.1, c.z - 6.0 + iz * 2.0 + 0.1, 1.8, 1.8)
			b.hrect("emissive", q, cy, [Color(0.9, 0.8, 0.5), Color(0.5, 0.7, 0.85), Color(0.85, 0.6, 0.4)][(ix + iz) % 3] * 0.6, false)
	b.light(c + Vector3(0, h - 2.0, 0), Color(1.0, 0.9, 0.75), 1.6, 18.0)
	b.light(c + Vector3(0, 3.0, 5.0), Color(1.0, 0.88, 0.7), 0.8, 12.0)
	for k in 6:
		b.spot(c + Vector3(-5.0 + k * 2.0, 0, 3.5), PI, "stand")
	b.spot(sb + Vector3(0, 0, -0.8), 0.0, "scene")
	b.spot(InteriorKits._door_in(b, 0, 1.5), PI, "guard")


# ================================================================ 昭和の暮らし
static func _chanoma(b: InteriorBuilder, r: Rect2, y: float, fl := 0) -> void:
	# 茶の間: ちゃぶ台・座布団・真空管ラジオ（茶箪笥の上）・柱時計・裸電球
	var c := Vector3(r.get_center().x, y, r.get_center().y)
	b.chabudai(c)
	for k in 4:
		var a := TAU * k / 4.0
		b.zabuton(c + Vector3(cos(a) * 0.75, 0, sin(a) * 0.75), Color(0.55, 0.25, 0.25) if k % 2 == 0 else Color(0.3, 0.35, 0.5), -a)
		b.spot(c + Vector3(cos(a) * 0.75, 0.07, sin(a) * 0.75), -a - PI * 0.5, "sit", fl)
	var ts := Vector3(r.position.x + 0.5, y, r.position.y + 0.3)
	b.box("wood", ts + Vector3(0, 0.55, 0), Vector3(0.9, 1.1, 0.4), Color(0.5, 0.32, 0.2), 0.0, true)
	b.box("glass", ts + Vector3(0, 0.85, 0.21), Vector3(0.8, 0.4, 0.01), Color(0.7, 0.75, 0.8))
	b.radio(ts + Vector3(0, 1.1, 0), 0.0)
	b.clock(Vector3(r.end.x - 0.05, y + 1.9, r.get_center().y), Vector3(-1, 0, 0))
	b.box("flat", Vector3(r.end.x - 0.03, y + 1.3, r.get_center().y + 0.8), Vector3(0.01, 0.5, 0.35), Color(0.95, 0.93, 0.88))
	b.lamp("bulb", c + Vector3(0, b.fh(fl) - 0.75, 0))


static func _showa_shop(b: InteriorBuilder) -> void:
	# 昭和の商店（看板建築）: 店先の土間に商品（駄菓子屋・八百屋・酒屋・荒物屋）、レジ台、奥に上がり框の茶の間、2 階は六畳
	b.structure("wood", Color(0.66, 0.54, 0.4), "box", Color(0.45, 0.3, 0.2))
	var r := b.fr(0)
	var y := b.fy(0)
	var back_d := minf(3.4, r.size.y * 0.42)
	var shop := Rect2(r.position.x, r.position.y + back_d, r.size.x, r.size.y - back_d)
	var home := Rect2(r.position.x + 1.1, r.position.y, r.size.x - 1.1, back_d)
	b.finish(shop, y, "concrete", Color(0.62, 0.6, 0.56))
	b.finish(Rect2(r.position.x, r.position.y, 1.1, back_d), y, "concrete", Color(0.6, 0.58, 0.54))
	b.platform(home, y, y + 0.42, "tatami", Color.WHITE, [[Vector3(home.get_center().x, y, home.end.y), Vector3(0, 0, 1)]])
	_chanoma(b, home, y + 0.42)
	var kind := b.rng.randi() % 4
	match kind:
		0:
			# 駄菓子屋: ガラス瓶の並ぶ雛壇・くじ・風船
			for k in 3:
				b.box("wood", Vector3(shop.get_center().x - 0.4, y + 0.3 + k * 0.3, shop.position.y + 0.6 + k * 0.35), Vector3(shop.size.x - 2.0, 0.6 - k * 0.2, 0.35), Color(0.6, 0.45, 0.3), 0.0, k == 0)
				for j in int((shop.size.x - 2.0) / 0.35):
					b.cyl("glass", Vector3(shop.position.x + 1.2 + j * 0.35 - 0.4, y + 0.6 + k * 0.3, shop.position.y + 0.6 + k * 0.35), 0.11, 0.11, 0.28, 8, Color(0.9, 0.95, 0.95))
					b.sph("flat", Vector3(shop.position.x + 1.2 + j * 0.35 - 0.4, y + 0.68 + k * 0.3, shop.position.y + 0.6 + k * 0.35), 0.07, [Color(0.95, 0.4, 0.5), Color(0.95, 0.85, 0.3), Color(0.4, 0.7, 0.95), Color(0.5, 0.85, 0.45)][(j + k) % 4], 5, 3)
		1:
			# 八百屋: 傾けた台に籠の野菜
			for k in 3:
				var p := Vector3(shop.position.x + 1.0 + k * (shop.size.x - 2.0) * 0.5, y, shop.get_center().y + 0.3)
				b.boxt("wood", Transform3D(Basis(Vector3.RIGHT, 0.25), p + Vector3(0, 0.6, 0)), Vector3(1.3, 0.06, 1.0), Color(0.6, 0.45, 0.3))
				b.col_box(p + Vector3(0, 0.35, 0), Vector3(1.3, 0.7, 1.0))
				for j in 4:
					b.cyl("bamboo", p + Vector3(-0.45 + j * 0.3, 0.62, -0.1 + (j % 2) * 0.25), 0.13, 0.15, 0.12, 8, Color(0.75, 0.62, 0.4))
					b.sph("flat", p + Vector3(-0.45 + j * 0.3, 0.76, -0.1 + (j % 2) * 0.25), 0.09, [Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.3), Color(0.35, 0.6, 0.25), Color(0.6, 0.35, 0.6)][(j + k) % 4], 6, 4)
		2:
			# 酒屋: 一升瓶の棚と樽
			b.shelf(Vector3(shop.position.x + 0.3, y, shop.get_center().y), PI * 0.5, shop.size.y - 0.6, 1.8, 0.4, 4, Color(0.5, 0.36, 0.24), func(q: Vector3, yw: float) -> void:
				for j in 3:
					b.cyl("glass", q + Basis(Vector3.UP, yw) * Vector3(-0.15 + j * 0.15, 0, 0), 0.05, 0.03, 0.4, 6, Color(0.35, 0.5, 0.35)))
			for k in 2:
				b.barrel(Vector3(shop.end.x - 0.8, y, shop.get_center().y - 0.5 + k * 0.8), Color(0.65, 0.48, 0.3))
		_:
			# 荒物屋: 箒・笊・バケツ
			b.shelf(Vector3(shop.end.x - 0.3, y, shop.get_center().y), -PI * 0.5, shop.size.y - 0.6, 1.6, 0.45, 3, Color(0.5, 0.36, 0.24), func(q: Vector3, yw: float) -> void:
				b.cyl("bamboo", q, 0.18, 0.2, 0.1, 8, Color(0.75, 0.62, 0.4)))
			for k in 4:
				b.rod("bamboo", Vector3(shop.position.x + 0.2, y, shop.position.y + 0.5 + k * 0.3), Vector3(shop.position.x + 0.3, y + 1.4, shop.position.y + 0.55 + k * 0.3), 0.03, Color(0.7, 0.58, 0.35), 4)
			for k in 3:
				b.cyl("metal", Vector3(shop.get_center().x - 0.6 + k * 0.5, y, shop.get_center().y), 0.15, 0.18, 0.3, 10, Color(0.65, 0.68, 0.7))
	# レジ台
	var rg := Vector3(home.get_center().x + 0.4, y, home.end.y + 0.6)
	b.box("wood", rg + Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.5), Color(0.5, 0.34, 0.22), 0.0, true)
	b.box("metal", rg + Vector3(0.2, 1.0, 0), Vector3(0.4, 0.2, 0.35), Color(0.3, 0.3, 0.32))
	b.box("wood", rg + Vector3(-0.3, 0.92, 0), Vector3(0.3, 0.03, 0.1), Color(0.3, 0.2, 0.12))
	b.spot(rg + Vector3(0, 0, -0.6), 0.0, "work")
	b.lamp("bulb", Vector3(shop.get_center().x, y + b.fh(0) - 0.7, shop.get_center().y), false)
	b.spot(InteriorKits._door_in(b, 0, 1.5), PI, "stand")
	b.fire_pts.append(Vector3(home.get_center().x, y + 0.42, home.get_center().y))
	if b.floors.size() > 1:
		var r2 := b.fr(1)
		var y2 := b.fy(1)
		var hole := b.floor_hole(1)
		b.tatami(r2, y2, hole)
		b.fittings(1, 3, "fusuma", Color(0.86, 0.82, 0.72), 1.8)
		b.tansu(Vector3(r2.end.x - 0.4, y2, r2.position.y + 0.8), -PI * 0.5, 1.0, 1.3, Color(0.5, 0.3, 0.18))
		b.futon_pile(Vector3(r2.end.x - 0.6, y2, r2.end.y - 0.8), 0.0)
		b.tv(Vector3(r2.get_center().x + 0.6, y2, r2.position.y + 0.35), 0.0)
		# 鏡台
		var kd := Vector3(r2.get_center().x - 0.4, y2, r2.end.y - 0.3)
		b.box("wood", kd + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.35), Color(0.45, 0.28, 0.16), 0.0, true)
		b.box("glass", kd + Vector3(0, 0.85, 0.05), Vector3(0.35, 0.6, 0.02), Color(0.85, 0.9, 0.95), PI)
		b.zabuton(Vector3(r2.get_center().x + 0.4, y2, r2.get_center().y), Color(0.6, 0.3, 0.3))
		b.spot(Vector3(r2.get_center().x + 0.4, y2 + 0.07, r2.get_center().y), 0.0, "sit", 1)
		b.lamp("bulb", Vector3(r2.get_center().x, y2 + b.fh(1) - 0.7, r2.get_center().y))


static func _showa_house(b: InteriorBuilder) -> void:
	# 昭和の木造家屋: 土間の台所（流し・七輪・蝿帳・木の冷蔵庫）、茶の間（ちゃぶ台・ラジオ・柱時計）、仏壇
	b.structure("wood", Color(0.66, 0.54, 0.4))
	var r := b.fr(0)
	var y := b.fy(0)
	var dx: float = b.def.get("doma_x", r.position.x + 1.0)
	var doma := Rect2(r.position.x, r.position.y, 2.2, r.size.y)
	var room := Rect2(r.position.x + 2.2, r.position.y, r.size.x - 2.2, r.size.y)
	b.finish(doma, y, "concrete", Color(0.6, 0.58, 0.54))
	b.platform(room, y, y + 0.4, "tatami", Color.WHITE, [[Vector3(room.position.x, y, room.end.y - 1.0), Vector3(-1, 0, 0)]])
	b.fittings(0, 2, "fusuma", Color(0.86, 0.82, 0.72), 1.8)
	_chanoma(b, room, y + 0.4)
	# 仏壇
	var bd := Vector3(room.end.x - 0.4, y + 0.4, room.position.y + 0.6)
	b.box("darkwood", bd + Vector3(0, 0.6, 0), Vector3(0.6, 1.2, 0.8), Color(0.12, 0.08, 0.06), 0.0, true)
	b.box("gold", bd + Vector3(-0.31, 0.75, 0), Vector3(0.02, 0.7, 0.6), Color(1, 0.82, 0.45))
	# 台所
	var kz := doma.position.y + 0.5
	b.box("concrete", Vector3(doma.position.x + 0.35, y + 0.4, kz + 0.6), Vector3(0.6, 0.8, 1.2), Color(0.75, 0.75, 0.72), 0.0, true)
	b.box("metal", Vector3(doma.position.x + 0.35, y + 0.81, kz + 0.6), Vector3(0.5, 0.02, 0.6), Color(0.6, 0.62, 0.64))
	b.cyl("earth", Vector3(doma.get_center().x + 0.3, y, kz + 0.4), 0.16, 0.14, 0.25, 10, Color(0.75, 0.6, 0.4))
	b.sph("emissive", Vector3(doma.get_center().x + 0.3, y + 0.26, kz + 0.4), 0.05, Color(1.0, 0.4, 0.12), 5, 3)
	var ic := Vector3(doma.position.x + 0.4, y, kz + 2.0)
	b.box("wood", ic + Vector3(0, 0.6, 0), Vector3(0.6, 1.2, 0.55), Color(0.55, 0.38, 0.24), 0.0, true)
	b.box("metal", ic + Vector3(0.31, 0.9, 0), Vector3(0.02, 0.05, 0.2), Color(0.75, 0.75, 0.72))
	b.box("wood", Vector3(doma.position.x + 0.4, y + 0.6, kz + 2.9), Vector3(0.6, 0.9, 0.5), Color(0.55, 0.4, 0.28), 0.0, true)
	b.box("cloth", Vector3(doma.position.x + 0.71, y + 0.65, kz + 2.9), Vector3(0.01, 0.7, 0.4), Color(0.5, 0.52, 0.5))
	b.spot(Vector3(doma.get_center().x, y, kz + 1.0), -PI * 0.5, "work")
	b.spot(Vector3(dx, y, r.end.y - 0.8), PI, "stand")
	b.fire_pts.append(Vector3(room.get_center().x, y + 0.4, room.get_center().y))


static func _danchi(b: InteriorBuilder) -> void:
	# 公団住宅の 2DK（1955〜）: ダイニングキッチン（ステンレスの流し台・テーブルと椅子・冷蔵庫・食器棚）、六畳と四畳半（ちゃぶ台・テレビ・箪笥）。
	# 階段室には集合郵便受けと自転車
	b.structure("flat", Color(0.94, 0.93, 0.9), "solid", Color(0.7, 0.7, 0.68))
	var u := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	# 住戸の両端の壁（隣の住戸）
	for x in [u.position.x - 0.05, u.end.x + 0.05]:
		b.partition(Vector2(x, u.position.y), Vector2(x, u.end.y), y, h, "plaster", Color(0.9, 0.88, 0.84))
	var dk := Rect2(u.position.x, u.position.y, u.size.x, u.size.y * 0.42)
	var rooms := Rect2(u.position.x, dk.end.y, u.size.x, u.end.y - dk.end.y)
	b.finish(dk, y, "linoleum", Color(0.62, 0.55, 0.42))
	b.platform(rooms, y, y + 0.05, "tatami")
	b.partition(Vector2(u.get_center().x, rooms.position.y), Vector2(u.get_center().x, rooms.end.y), y + 0.05, 1.85, "flat", Color(0.86, 0.82, 0.72), [[0.3, 1.2, 1.8]], 0.04)
	b.partition(Vector2(u.position.x, rooms.position.y), Vector2(u.end.x, rooms.position.y), y, h, "plaster", Color(0.92, 0.9, 0.86), [[1.0, 2.0, 2.0], [u.size.x - 2.6, u.size.x - 1.6, 2.0]])
	# DK
	var sk := Vector3(u.position.x + 1.5, y, u.position.y + 0.35)
	b.box("metal", sk + Vector3(0, 0.42, 0), Vector3(1.8, 0.84, 0.55), Color(0.88, 0.88, 0.86), 0.0, true)
	b.box("metal", sk + Vector3(-0.3, 0.85, 0), Vector3(0.6, 0.02, 0.4), Color(0.75, 0.78, 0.8))
	b.box("metal", sk + Vector3(1.4, 0.5, 0), Vector3(0.6, 1.0, 0.55), Color(0.92, 0.92, 0.9), 0.0, true)
	b.box("metal", sk + Vector3(1.4, 0.85, 0.28), Vector3(0.1, 0.03, 0.01), Color(0.5, 0.5, 0.5))
	b.box("metal", Vector3(u.end.x - 0.4, y + 0.75, u.position.y + 0.35), Vector3(0.6, 1.5, 0.55), Color(0.95, 0.95, 0.92), 0.0, true)
	b.box("wood", Vector3(u.end.x - 1.2, y + 0.9, u.position.y + 0.25), Vector3(0.9, 1.8, 0.4), Color(0.6, 0.42, 0.28), 0.0, true)
	var tb := Vector3(u.get_center().x, y, dk.get_center().y + 0.2)
	b.table(tb, 1.2, 0.75, 0.7, Color(0.6, 0.42, 0.28), 0.0, Color(0.85, 0.85, 0.95))
	for k in 4:
		var sx := -0.35 if k % 2 == 0 else 0.35
		var sz := -0.6 if k < 2 else 0.6
		b.chair(tb + Vector3(sx, 0, sz), 0.0 if sz < 0 else PI, Color(0.55, 0.4, 0.28), Color(0.85, 0.5, 0.3))
		b.spot(tb + Vector3(sx, 0, sz), PI if sz < 0 else 0.0, "sit")
	b.lamp("fluorescent", tb + Vector3(0, h - 0.15, 0))
	# 六畳・四畳半
	var r6 := Rect2(rooms.position.x, rooms.position.y, rooms.size.x * 0.5, rooms.size.y)
	var r4 := Rect2(rooms.get_center().x, rooms.position.y, rooms.size.x * 0.5, rooms.size.y)
	b.chabudai(Vector3(r6.get_center().x, y + 0.05, r6.get_center().y))
	b.tv(Vector3(r6.position.x + 0.4, y + 0.05, r6.end.y - 0.35), PI)
	b.spot(Vector3(r6.get_center().x, y + 0.12, r6.get_center().y - 0.7), 0.0, "sit")
	b.tansu(Vector3(r4.end.x - 0.35, y + 0.05, r4.get_center().y), -PI * 0.5, 0.9, 1.2)
	b.futon_pile(Vector3(r4.get_center().x, y + 0.05, r4.end.y - 0.5), 0.0)
	b.lamp("bulb", Vector3(r4.get_center().x, y + h - 0.6, r4.get_center().y), false)
	for k in 3:
		b.faux_window(Vector3(u.position.x + u.size.x * (k + 0.5) / 3.0 - 0.0, y + 1.4, u.end.y - 0.01), Vector3(0, 0, -1), 2.6, 1.8)
	# 階段室
	if b.floors.size() > 1:
		var s := b.fr(1)
		b.finish(s, b.fy(1), "concrete", Color(0.68, 0.68, 0.66))
		var mb := Vector3(s.position.x + 0.1, b.fy(1) + 1.2, s.get_center().y)
		b.box("metal", mb, Vector3(0.12, 0.6, 1.4), Color(0.4, 0.5, 0.45))
		for k in 4:
			b.box("flat", mb + Vector3(0.07, 0.1, -0.5 + k * 0.33), Vector3(0.01, 0.06, 0.25), Color(0.95, 0.95, 0.9))
		# 上り階段の一段目（上階は扉を閉じている）
		b.stairs({"a": Vector3(s.end.x - 0.55, b.fy(1), s.end.y - 0.2), "b": Vector3(s.end.x - 0.55, b.fy(1) + 1.2, s.position.y + 0.6), "w": 0.9}, "solid", Color(0.7, 0.7, 0.68))
		b.box("concrete", Vector3(s.end.x - 0.55, b.fy(1) + 1.1, s.position.y + 0.3), Vector3(1.0, 0.2, 0.6), Color(0.7, 0.7, 0.68), 0.0, true)
		var bc := Vector3(s.position.x + 0.7, b.fy(1), s.end.y - 0.6)
		for sgn in [-1.0, 1.0]:
			b.cylt("metal", Transform3D(Basis(Vector3.BACK, PI * 0.5), bc + Vector3(-0.05, 0.33, sgn * 0.5)), 0.32, 0.32, 0.04, 12, Color(0.15, 0.15, 0.15))
		b.rod("metal", bc + Vector3(0, 0.33, -0.5), bc + Vector3(0, 0.85, 0.3), 0.02, Color(0.15, 0.2, 0.4), 4)
		b.lamp("bulb", Vector3(s.get_center().x, b.fy(1) + 2.6, s.get_center().y), false)
		b.spot(Vector3(s.get_center().x, b.fy(1), s.get_center().y), 0.0, "stand", 1)


static func _hangar(b: InteriorBuilder) -> void:
	# 格納庫: 整備中の機体（胴体・主翼・プロペラ）、作業台・工具箱・ドラム缶・脚立
	b.structure()
	var r := b.fr(0)
	var y := b.fy(0)
	var c := Vector3(r.get_center().x, y, r.get_center().y + 1.0)
	var green := Color(0.35, 0.42, 0.3)
	b.cylt("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, 1.6, -4.0)), 0.6, 0.75, 8.0, 12, green)
	b.box("metal", c + Vector3(0, 1.3, -1.0), Vector3(11.0, 0.18, 2.0), green, 0.0, true)
	b.box("metal", c + Vector3(0, 1.9, 3.5), Vector3(3.6, 0.1, 1.0), green)
	b.box("metal", c + Vector3(0, 2.4, 3.6), Vector3(0.1, 1.0, 1.0), green)
	b.box("metal", c + Vector3(0, 1.6, -4.2), Vector3(2.6, 0.18, 0.1), Color(0.2, 0.2, 0.2))
	b.cyl("metal", c + Vector3(0, 0, -0.5), 0.05, 0.05, 1.3, 6, Color(0.3, 0.3, 0.3))
	for sgn in [-1.0, 1.0]:
		b.cylt("metal", Transform3D(Basis(Vector3.BACK, PI * 0.5), c + Vector3(sgn * 1.6 - 0.1, 0.35, -1.2)), 0.35, 0.35, 0.2, 12, Color(0.12, 0.12, 0.12))
		b.box("emissive", c + Vector3(sgn * 4.0, 1.3, -1.0), Vector3(0.8, 0.02, 0.8), Color(0.9, 0.15, 0.1))
	b.col_box(c + Vector3(0, 1.6, 0), Vector3(1.5, 1.5, 8.0))
	for k in 3:
		var p := Vector3(r.position.x + 1.0, y, r.position.y + 2.0 + k * 3.0)
		b.box("wood", p + Vector3(0, 0.45, 0), Vector3(0.8, 0.9, 2.0), Color(0.5, 0.38, 0.26), 0.0, true)
		b.box("metal", p + Vector3(0, 0.98, 0.4), Vector3(0.4, 0.15, 0.3), Color(0.65, 0.2, 0.15))
		b.barrel(Vector3(r.end.x - 1.0, y, r.position.y + 2.0 + k * 1.0), Color(0.3, 0.32, 0.28))
	for k in 3:
		b.lamp("bulb", Vector3(r.position.x + r.size.x * (k + 0.5) / 3.0, y + b.fh(0) - 1.0, r.get_center().y), k == 1)
	b.spot(c + Vector3(2.0, 0, 1.5), PI, "work")
	b.spot(c + Vector3(-2.0, 0, -2.0), 0.0, "work")


static func _tower(b: InteriorBuilder) -> void:
	# 管制塔の 1 階: 無線機の卓・飛行場の地図・電話・時計
	b.structure("flat", Color(0.9, 0.9, 0.88), "solid", Color(0.7, 0.7, 0.68))
	var r := b.fr(0)
	var y := b.fy(0)
	b.finish(r, y, "linoleum", Color(0.5, 0.55, 0.5))
	var dk := Vector3(r.get_center().x, y, r.position.y + 0.5)
	b.box("metal", dk + Vector3(0, 0.4, 0), Vector3(3.0, 0.8, 0.7), Color(0.4, 0.44, 0.42), 0.0, true)
	for k in 3:
		b.box("metal", dk + Vector3(-1.0 + k, 1.1, -0.1), Vector3(0.7, 0.6, 0.45), Color(0.3, 0.33, 0.32))
		b.box("emissive", dk + Vector3(-1.0 + k, 1.2, 0.13), Vector3(0.3, 0.06, 0.01), Color(0.4, 1.0, 0.5))
	b.box("flat", Vector3(r.end.x - 0.03, y + 1.6, r.get_center().y), Vector3(0.01, 1.0, 1.6), Color(0.85, 0.85, 0.75))
	b.chair(dk + Vector3(0, 0, 0.7), PI, Color(0.4, 0.42, 0.45), Color(0.3, 0.35, 0.4))
	b.spot(dk + Vector3(0, 0, 0.7), 0.0, "work")
	b.clock(Vector3(r.position.x + 0.05, y + 2.2, r.get_center().y), Vector3(1, 0, 0))
	b.lamp("fluorescent", Vector3(r.get_center().x, y + b.fh(0) - 0.15, r.get_center().y))

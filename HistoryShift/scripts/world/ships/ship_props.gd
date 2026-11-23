class_name ShipProps
extends RefCounted
## 部屋の小道具。データの key_props・部屋名の語から選んで、壁際・列に並べる（通路と扉前は空ける）。
## 形は箱・円柱の組み合わせ（アニメ調のベタ塗り）。大きいものだけコリジョンを付ける。

const WOOD := Color(0.78, 0.6, 0.42)
const DARKW := Color(0.45, 0.32, 0.22)
const BRASS := Color(0.95, 0.75, 0.35)
const IRON := Color(0.25, 0.25, 0.27)
const STEELC := Color(0.55, 0.57, 0.6)
const WHITE := Color(0.94, 0.93, 0.9)
const CLOTH := Color(0.85, 0.82, 0.72)
const RED := Color(0.75, 0.15, 0.12)

var sk: ShipKit
var sd: ShipData
var rng := RandomNumberGenerator.new()
var r: Dictionary
var z0 := 0.0
var z1 := 0.0
var x0 := 0.0
var x1 := 0.0
var y := 0.0
var h := 2.4
var steel := true
var used: Array = []     # 置いた物の矩形（重なりを避ける）
var door_rect: Dictionary = {}


static func populate(p_sk: ShipKit, p_sd: ShipData, room: Dictionary, seed: int) -> void:
	var pp := ShipProps.new()
	pp.sk = p_sk
	pp.sd = p_sd
	pp.r = room
	pp.rng.seed = seed
	pp.z0 = float(room["z0"]) + 0.25
	pp.z1 = float(room["z1"]) - 0.25
	pp.x0 = float(room["x0"]) + 0.25
	pp.x1 = float(room["x1"]) - 0.25
	pp.y = float(room["y"])
	pp.h = float(room.get("h", 2.4))
	pp.steel = p_sd.steel
	var dr: Dictionary = room.get("door", {})
	if not dr.is_empty():
		pp.door_rect = dr
	pp._run(String(room.get("words", "")))


func _has(w: String, keys: Array) -> bool:
	for k in keys:
		if w.find(String(k)) >= 0:
			return true
	return false


func _run(w: String) -> void:
	var area := (z1 - z0) * (x1 - x0)
	if area < 2.0:
		return
	# 床の敷物（畳・絨毯）
	if _has(w, ["tatami", "畳", "mats"]):
		sk.box("tatami", Vector3((x0 + x1) * 0.5, y + 0.03, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.06, z1 - z0), Color(0.92, 0.88, 0.62))
	elif _has(w, ["carpet", "saloon", "social hall", "smoking", "commodore", "admiral", "長官", "great cabin", "lobby"]):
		sk.box("cloth", Vector3((x0 + x1) * 0.5, y + 0.02, (z0 + z1) * 0.5), Vector3((x1 - x0) * 0.8, 0.03, (z1 - z0) * 0.8), Color(0.55, 0.12, 0.12))
	# 壁の羽目板
	if _has(w, ["panel", "羽目", "admiral", "長官", "captain", "艦長", "wardroom", "士官", "smoking", "social", "saloon", "commodore", "great cabin"]):
		_panelling()
	var did := false
	if _has(w, ["aircraft", "hangar", "格納庫"]):
		_aircraft(w); did = true
	if _has(w, ["boiler", "汽罐", "罐室"]):
		_boilers(); did = true
	if _has(w, ["engine", "turbine", "機械", "機関", "diesel", "crosshead"]) and not _has(w, ["telegraph repeater only"]):
		_engines(w); did = true
	if _has(w, ["magazine", "弾火薬庫", "火薬庫", "shell", "charge", "powder", "bomb", "torpedo", "canister", "keg"]):
		_magazine(w); did = true
	if _has(w, ["hammock"]):
		_hammocks()
	if _has(w, ["bunk", "bed", "cot", "berth", "寝"]):
		_bunks(); did = true
	if _has(w, ["conference table", "dining", "mess table", "set tables", "table", "desk", "chart"]):
		_tables(w); did = true
	if _has(w, ["piano"]):
		_piano()
	if _has(w, ["armchair", "sofa", "chair", "leather"]):
		_chairs()
	if _has(w, ["fireplace"]):
		_fireplace()
	if _has(w, ["bar", "sideboard"]):
		_counter()
	if _has(w, ["stove", "range", "rice boiler", "kettle", "釜", "galley", "烹炊", "cooker", "ramune"]):
		_galley(); did = true
	if _has(w, ["binnacle", "compass", "羅針"]):
		_binnacle()
	if _has(w, ["wheel", "helm", "steering", "舵", "操舵"]) and not _has(w, ["paddle", "boiler"]):
		_wheel(w)
	if _has(w, ["telegraph"]):
		_telegraphs()
	if _has(w, ["voice tube"]):
		_voice_tubes()
	if _has(w, ["altar", "shrine", "mazu", "媽祖", "crucifix", "神棚"]):
		_altar(w)
	if _has(w, ["silk", "bale", "crate", "cargo", "porcelain", "rice", "jar", "cask", "barrel", "water", "provisions", "stores", "deerskin", "silver", "tribute"]):
		_cargo(w); did = true
	if _has(w, ["oar", "艪", "rowers"]):
		_oar_benches(); did = true
	if _has(w, ["gun", "cannon", "大筒", "matchlock", "casemate", "bronze guns", "pivot", "ports"]) and not _has(w, ["aircraft", "aa gun galleries"]):
		_guns_in(w)
	if _has(w, ["radio", "transmitter", "morse", "wireless", "無線"]):
		_radio()
	if _has(w, ["toy", "children"]):
		_toys()
	if _has(w, ["operating table", "sick", "医務"]):
		_sickbay()
	if _has(w, ["latrine", "厠", "heads"]):
		_latrine()
	if _has(w, ["locker", "chest", "ditty", "sea chest", "lacquered"]):
		_lockers()
	if _has(w, ["banner", "drum", "conch", "war fan"]):
		_banners(w)
	if _has(w, ["shield board", "楯板"]):
		pass
	if _has(w, ["fuel", "gasoline"]) and not did:
		_tanks(); did = true
	if _has(w, ["rangefinder", "binocular", "director"]):
		_binoculars()
	if _has(w, ["shaft", "propeller shaft", "shaft bearings"]):
		_shaft()
	if _has(w, ["capstan", "windlass"]):
		_capstan()
	if _has(w, ["staircase"]):
		_grand_stair()
	if _has(w, ["wash", "basin"]):
		_washstand()
	if _has(w, ["abacus", "red seal", "朱印", "scroll", "sutra"]):
		_scrolls()
	if not did and bool(r.get("enclosed", false)) and area > 6.0 and used.size() < 2:
		_tables(w)


# ------------------------------------------------------------ 置き場所
func _free(c: Vector3, size: Vector3) -> bool:
	var rr := {"z0": c.z - size.z * 0.5, "z1": c.z + size.z * 0.5, "x0": c.x - size.x * 0.5, "x1": c.x + size.x * 0.5}
	if rr["z0"] < z0 - 0.01 or rr["z1"] > z1 + 0.01 or rr["x0"] < x0 - 0.01 or rr["x1"] > x1 + 0.01:
		return false
	for u in used:
		if ShipData._rect_hit(rr, u, 0.15):
			return false
	if not door_rect.is_empty() and ShipData._rect_hit(rr, door_rect, 0.3):
		return false
	for st in sd.stairs:
		if absf(float(st["y0"]) - y) < 0.4 or absf(float(st["y1"]) - y) < 0.4:
			if ShipData._rect_hit(rr, st, 0.6):
				return false
	return true


func _take(c: Vector3, size: Vector3) -> void:
	used.append({"z0": c.z - size.z * 0.5, "z1": c.z + size.z * 0.5, "x0": c.x - size.x * 0.5, "x1": c.x + size.x * 0.5})


## 壁際に沿って並べる位置（長辺の両側）
func _along_walls(size: Vector3, spacing: float, max_n := 40) -> Array:
	var out: Array = []
	var long_z := (z1 - z0) >= (x1 - x0)
	if long_z:
		for xs: float in [x0 + size.x * 0.5, x1 - size.x * 0.5]:
			var zz := z0 + size.z * 0.5
			while zz <= z1 - size.z * 0.5 and out.size() < max_n:
				var c := Vector3(float(xs), y, zz)
				if _free(c, size):
					out.append(c)
					_take(c, size)
				zz += spacing
	else:
		for zs: float in [z0 + size.z * 0.5, z1 - size.z * 0.5]:
			var xx := x0 + size.x * 0.5
			while xx <= x1 - size.x * 0.5 and out.size() < max_n:
				var c := Vector3(xx, y, float(zs))
				if _free(c, size):
					out.append(c)
					_take(c, size)
				xx += spacing
	return out


## 部屋の中に格子で並べる
func _grid(size: Vector3, gap: float, max_n := 30) -> Array:
	var out: Array = []
	var zz := z0 + size.z * 0.5 + 0.3
	while zz <= z1 - size.z * 0.5 and out.size() < max_n:
		var xx := x0 + size.x * 0.5 + 0.3
		while xx <= x1 - size.x * 0.5 and out.size() < max_n:
			var c := Vector3(xx, y, zz)
			if _free(c, size):
				out.append(c)
				_take(c, size)
			xx += size.x + gap
		zz += size.z + gap
	return out


func _center_spot(size: Vector3) -> Vector3:
	var c := Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	for k in 9:
		var cc := c + Vector3(0, 0, (k / 2) * 1.2 * (1.0 if k % 2 == 0 else -1.0))
		if _free(cc, size):
			_take(cc, size)
			return cc
	return Vector3.INF


# ------------------------------------------------------------ 小道具
func _panelling() -> void:
	var colr := Color(0.62, 0.42, 0.26)
	for xs: float in [x0 - 0.2, x1 + 0.2]:
		sk.box("wood", Vector3(float(xs), y + 0.6, (z0 + z1) * 0.5), Vector3(0.04, 1.2, z1 - z0), colr)
	sk.box("wood", Vector3((x0 + x1) * 0.5, y + 1.22, z0 - 0.2), Vector3(x1 - x0, 0.06, 0.05), colr.darkened(0.2))


func _aircraft(w: String) -> void:
	var span := 11.0 if w.find("fold") < 0 else 7.0
	var size := Vector3(7.5, 3.0, 10.0)
	var pts := _grid(size, 1.5, 12)
	for c in pts:
		var cv: Vector3 = c
		var colr := Color(0.45, 0.52, 0.42) if sd.year >= 1940 else Color(0.75, 0.75, 0.68)
		sk.box("metal", cv + Vector3(0, 1.4, 0), Vector3(1.1, 1.1, 8.8), colr)
		sk.box("metal", cv + Vector3(0, 1.2, -1.2), Vector3(span * 0.5, 0.12, 1.9), colr)
		# 折りたたんだ翼
		for sx: float in [-1.0, 1.0]:
			sk.box("metal", cv + Vector3(float(sx) * span * 0.25, 2.4, -1.2), Vector3(0.12, 2.2, 1.9), colr.darkened(0.08))
		sk.box("metal", cv + Vector3(0, 1.6, 4.0), Vector3(3.0, 0.1, 1.0), colr)
		sk.box("metal", cv + Vector3(0, 2.2, 4.2), Vector3(0.1, 1.2, 1.0), colr)
		sk.cyl("metal", cv + Vector3(0, 1.4, -4.5), 0.65, 0.65, 0.3, 10, IRON, Basis(Vector3.RIGHT, PI * 0.5))
		sk.box("glass", cv + Vector3(0, 2.05, -0.4), Vector3(0.8, 0.4, 2.0), Color(0.5, 0.6, 0.7))
		for sx: float in [-1.0, 1.0]:
			sk.rod("metal", cv + Vector3(float(sx) * 1.2, 1.0, -1.6), cv + Vector3(float(sx) * 1.3, 0.3, -1.6), 0.06, IRON)
			sk.cyl("metal", cv + Vector3(float(sx) * 1.3, 0.3, -1.6), 0.3, 0.3, 0.18, 8, IRON, Basis(Vector3.FORWARD, PI * 0.5))
		sk.col_box(cv + Vector3(0, 1.4, 0), Vector3(2.0, 2.4, 8.8))
		sk.kit.cylinder("flat", Transform3D(Basis(), cv + Vector3(span * 0.18, 1.27, -1.2)), 0.45, 0.45, 0.02, 12, RED)
	# 爆弾・魚雷の運搬車
	if w.find("torpedo") >= 0 or w.find("bomb") >= 0 or w.find("trolley") >= 0:
		for c in _along_walls(Vector3(1.0, 1.0, 5.5), 7.0, 6):
			var cv: Vector3 = c
			sk.box("metal", cv + Vector3(0, 0.3, 0), Vector3(0.9, 0.2, 2.5), IRON)
			sk.kit.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), cv + Vector3(0, 0.75, 2.7)), 0.27, 0.27, 5.4, 10, STEELC)


func _boilers() -> void:
	var size := Vector3(3.0, 3.4, 4.0)
	for c in _along_walls(size, 4.6, 12):
		var cv: Vector3 = c
		sk.box("metal", cv + Vector3(0, 1.4, 0), Vector3(2.8, 2.8, 3.8), Color(0.32, 0.3, 0.3), true)
		sk.cyl("metal", cv + Vector3(0, 2.8, 0), 1.3, 1.3, 0.4, 12, Color(0.25, 0.24, 0.24))
		var face := 1.0 if cv.x < (x0 + x1) * 0.5 else -1.0
		sk.box("flat", cv + Vector3(face * 1.42, 0.8, 0), Vector3(0.05, 0.7, 1.0), Color(1.0, 0.45, 0.1))
		sk.box("metal", cv + Vector3(face * 1.42, 2.1, 0.8), Vector3(0.05, 0.35, 0.35), BRASS)
		sk.rod("metal", cv + Vector3(0, 3.0, 0), cv + Vector3(0, h - 0.1, 0), 0.4, IRON)
	# 石炭と円匙
	if sd.year < 1915:
		var pc := _center_spot(Vector3(2.4, 0.8, 2.4))
		if pc != Vector3.INF:
			sk.kit.sphere("earth", Transform3D(Basis().scaled(Vector3(1.2, 0.45, 1.2)), pc + Vector3(0, 0.1, 0)), 1.0, 8, 4, Color(0.12, 0.12, 0.13))


func _engines(w: String) -> void:
	var c := _center_spot(Vector3(minf(5.0, x1 - x0 - 1.6), 4.0, minf(10.0, z1 - z0 - 1.6)))
	if c == Vector3.INF:
		return
	var sx := minf(5.0, x1 - x0 - 1.6)
	var sz := minf(10.0, z1 - z0 - 1.6)
	var hh := minf(h - 0.4, 3.6)
	if w.find("turbine") >= 0 or w.find("diesel") >= 0:
		sk.kit.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, hh * 0.45, -sz * 0.5)), sx * 0.35, sx * 0.3, sz, 14, Color(0.4, 0.45, 0.42))
		sk.box("metal", c + Vector3(0, 0.3, 0), Vector3(sx, 0.6, sz), IRON, true)
	else:
		# 縦型三段膨張機関: シリンダ 3 本＋クロスヘッド
		sk.box("metal", c + Vector3(0, 0.4, 0), Vector3(sx, 0.8, sz), IRON, true)
		for k in 3:
			var cz := c.z - sz * 0.33 + sz * 0.33 * k
			sk.cyl("metal", Vector3(c.x, y + hh * 0.55, cz), 0.9 + k * 0.25, 0.9 + k * 0.25, hh * 0.45, 12, Color(0.35, 0.4, 0.38))
			for dx: float in [-0.6, 0.6]:
				sk.rod("metal", Vector3(c.x + float(dx), y + 0.8, cz), Vector3(c.x + float(dx), y + hh * 0.55, cz), 0.09, STEELC)
	sk.col_box(c + Vector3(0, hh * 0.5, 0), Vector3(sx, hh, sz))
	# 計器盤
	for p in _along_walls(Vector3(0.6, 1.8, 1.6), 6.0, 2):
		var pv: Vector3 = p
		sk.box("metal", pv + Vector3(0, 0.9, 0), Vector3(0.4, 1.8, 1.4), Color(0.2, 0.3, 0.25))
		for k in 3:
			sk.cyl("metal", pv + Vector3(0.21 * signf((x0 + x1) * 0.5 - pv.x), 1.3, -0.4 + k * 0.4), 0.15, 0.15, 0.03, 10, WHITE, Basis(Vector3.FORWARD, PI * 0.5))


func _magazine(w: String) -> void:
	# 砲弾・装薬・樽・爆弾（危険物は赤い印）
	var keg := not steel or w.find("keg") >= 0 or w.find("powder") >= 0 and sd.year < 1870
	if keg:
		for c in _grid(Vector3(0.8, 1.0, 0.8), 0.35, 30):
			var cv: Vector3 = c
			sk.cyl("wood", cv, 0.36, 0.36, 0.9, 10, DARKW)
			sk.cyl("metal", cv + Vector3(0, 0.25, 0), 0.38, 0.38, 0.06, 10, IRON)
	else:
		var big := w.find("46") >= 0 or w.find("12-inch") >= 0 or w.find("main") >= 0 or w.find("主砲") >= 0
		var sr := 0.25 if big else 0.12
		for c in _along_walls(Vector3(1.2, 1.6, 2.5), 2.7, 16):
			var cv: Vector3 = c
			sk.box("metal", cv + Vector3(0, 0.05, 0), Vector3(1.1, 0.1, 2.4), IRON)
			for i in 3:
				for j in 2:
					var p := cv + Vector3((i - 1) * sr * 2.2, 0.1 + sr + j * sr * 2.05, -0.6)
					sk.kit.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p), sr, sr, 1.8, 8, Color(0.35, 0.35, 0.3) if w.find("bomb") < 0 else Color(0.25, 0.3, 0.25))
		for c in _grid(Vector3(1.0, 1.0, 1.0), 0.6, 10):
			var cv: Vector3 = c
			sk.box("wood", cv + Vector3(0, 0.45, 0), Vector3(0.9, 0.9, 0.9), Color(0.6, 0.5, 0.35))
			sk.box("flat", cv + Vector3(0, 0.6, 0.46), Vector3(0.4, 0.3, 0.02), RED)
	# 揚弾機
	var hc := _center_spot(Vector3(1.4, h, 1.4))
	if hc != Vector3.INF:
		sk.box("metal", hc + Vector3(0, (h - 0.2) * 0.5, 0), Vector3(1.2, h - 0.2, 1.2), STEELC.darkened(0.1), true)


func _hammocks() -> void:
	var n := 0
	var zz := z0 + 1.0
	while zz < z1 - 0.8 and n < 28:
		for xs: float in [lerpf(x0, x1, 0.25), lerpf(x0, x1, 0.75)]:
			var c := Vector3(float(xs), y + minf(h - 0.6, 2.0), zz)
			sk.kit.sphere("cloth", Transform3D(Basis().scaled(Vector3(0.8, 0.16, 0.35)), c), 1.0, 8, 4, CLOTH)
			sk.rod("metal", c + Vector3(-0.8, 0, 0), c + Vector3(-0.85, h - 2.0 + 0.5, 0), 0.015, IRON, 3)
			sk.rod("metal", c + Vector3(0.8, 0, 0), c + Vector3(0.85, h - 2.0 + 0.5, 0), 0.015, IRON, 3)
			n += 1
		zz += 1.3


func _bunks() -> void:
	var tiers := 3 if h > 2.6 and (r.get("words", "") as String).find("third") >= 0 else (2 if h > 2.3 else 1)
	for c in _along_walls(Vector3(0.9, 1.0, 2.0), 2.2, 14):
		var cv: Vector3 = c
		for t in tiers:
			var yy := 0.35 + t * 0.85
			sk.box("wood" if not steel or sd.year < 1925 else "metal", cv + Vector3(0, yy, 0), Vector3(0.9, 0.14, 2.0), DARKW if not steel else Color(0.7, 0.68, 0.62), true)
			sk.box("cloth", cv + Vector3(0, yy + 0.12, 0), Vector3(0.82, 0.1, 1.9), WHITE)
		sk.box("wood", cv + Vector3(0, tiers * 0.45, -1.0), Vector3(0.9, tiers * 0.9, 0.06), DARKW)


func _tables(w: String) -> void:
	var long := w.find("conference") >= 0 or w.find("dining") >= 0 or w.find("mess") >= 0 or w.find("wardroom") >= 0 or w.find("士官") >= 0
	var chart := w.find("chart") >= 0 and not long
	if long and z1 - z0 > 4.0:
		var ln := minf(z1 - z0 - 2.4, 12.0)
		var nt := 1 if x1 - x0 < 6.0 else maxi(1, int((x1 - x0) / 4.0))
		for k in nt:
			var cx := lerpf(x0, x1, (k + 0.5) / nt)
			var c := Vector3(cx, y, (z0 + z1) * 0.5)
			if not _free(c, Vector3(1.4, 1.0, ln)):
				continue
			_take(c, Vector3(2.6, 1.0, ln))
			sk.box("wood", c + Vector3(0, 0.75, 0), Vector3(1.2, 0.06, ln), WOOD.darkened(0.1), true)
			if w.find("tablecloth") >= 0 or w.find("set tables") >= 0 or w.find("dining") >= 0 or w.find("conference") >= 0:
				sk.box("cloth", c + Vector3(0, 0.79, 0), Vector3(1.3, 0.02, ln + 0.1), WHITE)
			for sx: float in [-1.0, 1.0]:
				var nc := int(ln / 0.9)
				for i in nc:
					var pz := c.z - ln * 0.5 + (i + 0.5) * ln / nc
					_chair(Vector3(cx + float(sx) * 0.95, y, pz), -float(sx))
			sk.box("wood", c + Vector3(0, 0.37, 0), Vector3(0.12, 0.74, ln * 0.8), DARKW)
	else:
		var n := 1 if chart else maxi(1, int((z1 - z0) * (x1 - x0) / 10.0))
		var pts := _grid(Vector3(1.6, 1.0, 1.2), 1.4, mini(n, 6))
		for c in pts:
			var cv: Vector3 = c
			sk.box("wood", cv + Vector3(0, 0.76 if not chart else 0.95, 0), Vector3(1.4, 0.06, 1.0), WOOD.darkened(0.05), true)
			sk.box("wood", cv + Vector3(0, 0.38, 0), Vector3(0.1, 0.76, 0.1), DARKW)
			if chart:
				sk.box("cloth", cv + Vector3(0, 0.99, 0), Vector3(1.2, 0.01, 0.85), Color(0.95, 0.9, 0.75))
				sk.box("metal", cv + Vector3(0.4, 1.02, 0.2), Vector3(0.2, 0.05, 0.2), BRASS)
			else:
				_chair(cv + Vector3(0, 0, 0.9), -1.0, true)


func _chair(p: Vector3, face: float, along_z := false) -> void:
	var colr := DARKW
	sk.box("wood", p + Vector3(0, 0.45, 0), Vector3(0.45, 0.06, 0.45), colr)
	if along_z:
		sk.box("wood", p + Vector3(0, 0.75, 0.2 * -face), Vector3(0.45, 0.6, 0.05), colr)
	else:
		sk.box("wood", p + Vector3(0.2 * -face, 0.75, 0), Vector3(0.05, 0.6, 0.45), colr)
	sk.box("wood", p + Vector3(0, 0.22, 0), Vector3(0.06, 0.44, 0.06), colr)


func _piano() -> void:
	var c := _center_spot(Vector3(1.6, 1.0, 2.2))
	if c == Vector3.INF:
		return
	sk.box("wood", c + Vector3(0, 0.95, 0), Vector3(1.5, 0.25, 2.0), Color(0.06, 0.05, 0.05), true)
	sk.box("flat", c + Vector3(-0.6, 0.82, 0), Vector3(0.2, 0.05, 1.5), WHITE)
	for dz: float in [-0.8, 0.8]:
		sk.box("wood", c + Vector3(0.4, 0.42, float(dz)), Vector3(0.1, 0.84, 0.1), Color(0.06, 0.05, 0.05))
	sk.box("wood", c + Vector3(0.1, 1.4, 0.3), Vector3(1.2, 0.04, 1.4), Color(0.08, 0.06, 0.06), false, Basis(Vector3.FORWARD, 0.5))


func _chairs() -> void:
	for c in _grid(Vector3(1.0, 1.0, 1.0), 1.2, 8):
		var cv: Vector3 = c
		var colr := Color(0.5, 0.25, 0.15)
		sk.box("cloth", cv + Vector3(0, 0.3, 0), Vector3(0.9, 0.45, 0.85), colr, true)
		sk.box("cloth", cv + Vector3(0, 0.75, 0.38), Vector3(0.9, 0.6, 0.15), colr)
		for sx: float in [-0.42, 0.42]:
			sk.box("cloth", cv + Vector3(float(sx), 0.6, 0), Vector3(0.15, 0.3, 0.85), colr)


func _fireplace() -> void:
	for c in _along_walls(Vector3(0.6, 1.4, 1.8), 8.0, 1):
		var cv: Vector3 = c
		sk.box("stonewall", cv + Vector3(0, 0.7, 0), Vector3(0.5, 1.4, 1.8), Color(0.85, 0.82, 0.78), true)
		sk.box("emissive", cv + Vector3(signf((x0 + x1) * 0.5 - cv.x) * 0.26, 0.4, 0), Vector3(0.02, 0.5, 0.8), Color(1.0, 0.5, 0.15))


func _counter() -> void:
	for c in _along_walls(Vector3(0.7, 1.1, 3.0), 10.0, 1):
		var cv: Vector3 = c
		sk.box("wood", cv + Vector3(0, 0.55, 0), Vector3(0.6, 1.1, 2.9), DARKW, true)
		for k in 4:
			sk.cyl("glass", cv + Vector3(0, 1.1, -1.0 + k * 0.65), 0.06, 0.06, 0.28, 6, Color(0.4, 0.6, 0.4))


func _galley() -> void:
	for c in _along_walls(Vector3(1.0, 1.0, 2.0), 2.4, 6):
		var cv: Vector3 = c
		if not steel:
			sk.box("brick", cv + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 1.6), Color(0.75, 0.4, 0.3), true)
			sk.kit.sphere("metal", Transform3D(Basis().scaled(Vector3(0.5, 0.3, 0.5)), cv + Vector3(0, 1.0, 0)), 1.0, 8, 4, IRON)
		else:
			sk.box("metal", cv + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 1.9), Color(0.3, 0.3, 0.32), true)
			for dz: float in [-0.45, 0.45]:
				sk.cyl("metal", cv + Vector3(0, 0.9, float(dz)), 0.38, 0.4, 0.55, 10, STEELC)
			sk.rod("metal", cv + Vector3(0, 1.5, 0), cv + Vector3(0, h - 0.05, 0), 0.18, IRON)


func _binnacle() -> void:
	var c := _center_spot(Vector3(0.8, 1.2, 0.8))
	if c == Vector3.INF:
		c = Vector3((x0 + x1) * 0.5, y, z0 + 0.8)
	sk.cyl("wood", c, 0.25, 0.3, 1.0, 10, WOOD)
	sk.kit.sphere("metal", Transform3D(Basis(), c + Vector3(0, 1.15, 0)), 0.3, 10, 6, BRASS)
	for sx: float in [-0.45, 0.45]:
		sk.kit.sphere("metal", Transform3D(Basis(), c + Vector3(float(sx), 1.05, 0)), 0.14, 8, 5, Color(0.2, 0.35, 0.7) if sx < 0 else RED)


func _wheel(w: String) -> void:
	var c := Vector3((x0 + x1) * 0.5, y, z0 + 1.2)
	if not _free(c, Vector3(1.0, 1.0, 1.0)):
		c = _center_spot(Vector3(1.0, 1.0, 1.0))
		if c == Vector3.INF:
			return
	else:
		_take(c, Vector3(1.0, 1.0, 1.0))
	if w.find("tiller") >= 0 or w.find("whipstaff") >= 0:
		sk.rod("wood", c + Vector3(0, 1.0, 0.8), c + Vector3(0, 1.0, -1.5), 0.08, DARKW, 5)
		sk.box("wood", c + Vector3(0, 0.5, 0.8), Vector3(0.4, 1.0, 0.4), DARKW, true)
		return
	sk.box("wood", c + Vector3(0, 0.55, 0.2), Vector3(0.3, 1.1, 0.3), DARKW, true)
	var wc := c + Vector3(0, 1.2, -0.0)
	sk.kit.cylinder("wood", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), wc), 0.55, 0.55, 0.06, 14, WOOD.darkened(0.1))
	sk.kit.cylinder("flat", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), wc + Vector3(0, 0, -0.02)), 0.45, 0.45, 0.1, 14, Color(0.15, 0.12, 0.1))
	for k in 8:
		var a := TAU * k / 8.0
		sk.rod("wood", wc, wc + Vector3(cos(a), sin(a), 0) * 0.72, 0.03, BRASS, 3)


func _telegraphs() -> void:
	for c in _along_walls(Vector3(0.5, 1.2, 0.5), 1.0, 2):
		var cv: Vector3 = c
		sk.cyl("metal", cv, 0.1, 0.12, 1.0, 8, BRASS)
		sk.cyl("metal", cv + Vector3(0, 1.0, 0.12), 0.3, 0.3, 0.2, 12, BRASS, Basis(Vector3.RIGHT, PI * 0.5))
		sk.cyl("flat", cv + Vector3(0, 1.0, -0.09), 0.25, 0.25, 0.02, 12, WHITE, Basis(Vector3.RIGHT, PI * 0.5))


func _voice_tubes() -> void:
	var c := Vector3(x1 - 0.1, y, z0 + 0.5)
	for k in 4:
		var p := c + Vector3(0, 0, k * 0.25)
		sk.rod("metal", p + Vector3(0, 0.4, 0), p + Vector3(0, h - 0.1, 0), 0.04, BRASS, 5)
		sk.cyl("metal", p + Vector3(-0.08, 1.4, 0), 0.08, 0.05, 0.2, 6, BRASS, Basis(Vector3.FORWARD, PI * 0.5))


func _altar(w: String) -> void:
	for c in _along_walls(Vector3(0.7, 1.4, 1.6), 9.0, 1):
		var cv: Vector3 = c
		var colr := RED if w.find("mazu") >= 0 or w.find("媽祖") >= 0 else Color(0.85, 0.7, 0.3)
		sk.box("wood", cv + Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 1.5), colr, true)
		sk.box("gold", cv + Vector3(0, 1.15, 0), Vector3(0.3, 0.3, 0.5), Color(1, 0.8, 0.3))
		sk.box("emissive", cv + Vector3(0, 1.1, -0.6), Vector3(0.08, 0.15, 0.08), Color(1, 0.6, 0.2))
		sk.box("emissive", cv + Vector3(0, 1.1, 0.6), Vector3(0.08, 0.15, 0.08), Color(1, 0.6, 0.2))
		if w.find("crucifix") >= 0:
			sk.box("gold", cv + Vector3(0, 1.6, 0), Vector3(0.05, 0.7, 0.06), Color(1, 0.8, 0.3))
			sk.box("gold", cv + Vector3(0, 1.75, 0), Vector3(0.05, 0.06, 0.4), Color(1, 0.8, 0.3))


func _cargo(w: String) -> void:
	var kinds: Array = []
	if w.find("silk") >= 0 or w.find("bale") >= 0 or w.find("deerskin") >= 0 or w.find("rice") >= 0 or w.find("tribute") >= 0:
		kinds.append("bale")
	if w.find("jar") >= 0 or w.find("porcelain") >= 0:
		kinds.append("jar")
	if w.find("cask") >= 0 or w.find("barrel") >= 0 or w.find("water") >= 0:
		kinds.append("cask")
	if w.find("crate") >= 0 or w.find("silver") >= 0 or w.find("stores") >= 0 or w.find("provisions") >= 0 or kinds.is_empty():
		kinds.append("crate")
	var pts := _grid(Vector3(1.1, 1.0, 1.1), 0.25, 40)
	for i in pts.size():
		var cv: Vector3 = pts[i]
		# 通路を空けるため中央の列は飛ばす
		if absf(cv.x - (x0 + x1) * 0.5) < 0.7 and x1 - x0 > 4.0:
			continue
		var kd: String = kinds[i % kinds.size()]
		var stack := 1 + rng.randi() % 2
		for s in stack:
			var yy := cv.y + s * 0.85
			match kd:
				"bale":
					sk.box("cloth", Vector3(cv.x, yy + 0.4, cv.z), Vector3(1.0, 0.8, 0.9), Color(0.9, 0.85, 0.7) if w.find("silk") < 0 else Color(0.95, 0.92, 0.85), s == 0)
					sk.box("cloth", Vector3(cv.x, yy + 0.4, cv.z), Vector3(1.02, 0.1, 0.92), Color(0.5, 0.35, 0.2))
				"jar":
					sk.kit.sphere("plaster", Transform3D(Basis().scaled(Vector3(0.42, 0.45, 0.42)), Vector3(cv.x, yy + 0.45, cv.z)), 1.0, 8, 5, Color(0.55, 0.45, 0.35) if w.find("porcelain") < 0 else Color(0.9, 0.92, 0.98))
				"cask":
					sk.cyl("wood", Vector3(cv.x, yy, cv.z), 0.42, 0.42, 0.85, 10, DARKW, Basis())
					sk.cyl("metal", Vector3(cv.x, yy + 0.2, cv.z), 0.44, 0.44, 0.05, 10, IRON)
				_:
					sk.box("wood", Vector3(cv.x, yy + 0.4, cv.z), Vector3(0.95, 0.8, 0.95), WOOD.darkened(0.1), s == 0)
		if i > 34:
			break


func _oar_benches() -> void:
	for xs: float in [x0 + 0.5, x1 - 0.5]:
		var zz := z0 + 0.8
		while zz < z1 - 0.6:
			sk.box("wood", Vector3(float(xs), y + 0.4, zz), Vector3(0.8, 0.08, 0.35), DARKW)
			zz += 1.2


func _guns_in(w: String) -> void:
	var bronze := not steel
	var size := Vector3(1.4, 1.0, 2.4)
	var long_z := (z1 - z0) >= (x1 - x0)
	for c in _along_walls(size, 3.2, 10):
		var cv: Vector3 = c
		var out := Vector3(signf(cv.x - (x0 + x1) * 0.5), 0, 0) if long_z else Vector3(0, 0, signf(cv.z - (z0 + z1) * 0.5))
		var colr := Color(0.72, 0.52, 0.25) if bronze else Color(0.3, 0.31, 0.33)
		if bronze or sd.year < 1880:
			sk.box("wood", cv + Vector3(0, 0.3, 0), Vector3(1.0, 0.4, 1.4) if long_z else Vector3(1.4, 0.4, 1.0), DARKW)
			sk.kit.cylinder("metal", Transform3D(ShipExterior._basis_y_to(out), cv + Vector3(0, 0.65, 0) - out * 0.8), 0.22, 0.16, 2.2, 8, colr)
		else:
			sk.box("metal", cv + Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2), colr, true)
			sk.kit.cylinder("metal", Transform3D(ShipExterior._basis_y_to(out), cv + Vector3(0, 1.0, 0)), 0.12, 0.09, 3.0, 8, colr.darkened(0.2))


func _radio() -> void:
	for c in _along_walls(Vector3(0.8, 1.0, 1.6), 3.0, 1):
		var cv: Vector3 = c
		sk.box("wood", cv + Vector3(0, 0.75, 0), Vector3(0.7, 0.06, 1.5), DARKW, true)
		sk.box("metal", cv + Vector3(0, 1.2, 0.2), Vector3(0.5, 0.8, 0.8), Color(0.2, 0.2, 0.22))
		sk.box("emissive", cv + Vector3(0.26 * signf((x0 + x1) * 0.5 - cv.x), 1.4, 0.3), Vector3(0.02, 0.08, 0.08), Color(1, 0.6, 0.2))
		sk.box("metal", cv + Vector3(0, 0.8, -0.4), Vector3(0.15, 0.06, 0.25), BRASS)


func _toys() -> void:
	for c in _grid(Vector3(0.6, 0.6, 0.6), 1.0, 5):
		var cv: Vector3 = c
		sk.box("plaster", cv + Vector3(0, 0.2, 0), Vector3(0.35, 0.35, 0.35), [RED, Color(0.2, 0.4, 0.8), Color(0.9, 0.8, 0.2)][rng.randi() % 3])


func _sickbay() -> void:
	var c := _center_spot(Vector3(1.0, 1.0, 2.2))
	if c != Vector3.INF:
		sk.box("metal", c + Vector3(0, 0.85, 0), Vector3(0.8, 0.1, 2.0), WHITE, true)
		sk.box("metal", c + Vector3(0, 0.42, 0), Vector3(0.12, 0.84, 1.4), STEELC)
	_bunks()


func _latrine() -> void:
	for c in _along_walls(Vector3(0.8, 0.6, 1.8), 2.0, 3):
		var cv: Vector3 = c
		sk.box("wood", cv + Vector3(0, 0.25, 0), Vector3(0.7, 0.5, 1.7), DARKW, true)


func _lockers() -> void:
	for c in _along_walls(Vector3(0.5, 1.0, 0.9), 1.0, 10):
		var cv: Vector3 = c
		var lacq := (r.get("words", "") as String).find("lacquer") >= 0
		sk.box("wood", cv + Vector3(0, 0.3 if lacq else 0.9, 0), Vector3(0.45, 0.6 if lacq else 1.8, 0.85), Color(0.12, 0.06, 0.05) if lacq else Color(0.45, 0.5, 0.45))
		if lacq:
			sk.box("gold", cv + Vector3(0, 0.61, 0), Vector3(0.3, 0.02, 0.5), Color(1, 0.8, 0.3))


func _banners(w: String) -> void:
	for c in _along_walls(Vector3(0.3, 2.0, 0.3), 2.2, 6):
		var cv: Vector3 = c
		sk.rod("wood", cv, cv + Vector3(0, 2.6, 0), 0.03, DARKW, 4)
		sk.box("cloth", cv + Vector3(0, 1.8, 0.25), Vector3(0.02, 1.4, 0.5), WHITE)
		sk.kit.cylinder("cloth", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), cv + Vector3(-0.02, 2.0, 0.25)), 0.14, 0.14, 0.04, 10, Color(0.08, 0.08, 0.08))
	if w.find("drum") >= 0:
		var c2 := _center_spot(Vector3(1.0, 1.0, 1.0))
		if c2 != Vector3.INF:
			sk.cyl("wood", c2 + Vector3(0, 0.5, 0), 0.45, 0.45, 0.6, 12, RED.darkened(0.2), Basis(Vector3.FORWARD, PI * 0.5))
			sk.box("wood", c2 + Vector3(0, 0.25, 0), Vector3(0.8, 0.5, 0.3), DARKW)


func _tanks() -> void:
	for c in _along_walls(Vector3(2.0, 2.0, 3.0), 3.5, 6):
		var cv: Vector3 = c
		sk.kit.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), cv + Vector3(0, 1.0, -1.4)), 0.9, 0.9, 2.8, 12, Color(0.6, 0.55, 0.3))
		sk.col_box(cv + Vector3(0, 1.0, 0), Vector3(1.8, 1.8, 2.8))


func _binoculars() -> void:
	for c in _along_walls(Vector3(0.5, 1.4, 0.5), 2.0, 4):
		var cv: Vector3 = c
		sk.cyl("metal", cv, 0.08, 0.1, 1.2, 6, IRON)
		sk.box("metal", cv + Vector3(0, 1.3, 0), Vector3(0.35, 0.2, 0.5), Color(0.15, 0.15, 0.16))


func _shaft() -> void:
	var xc := (x0 + x1) * 0.5
	sk.kit.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(xc, y + 0.7, z0)), 0.25, 0.25, z1 - z0, 10, STEELC)
	var zz := z0 + 1.5
	while zz < z1 - 1.0:
		sk.box("metal", Vector3(xc, y + 0.35, zz), Vector3(0.9, 0.7, 0.6), IRON, true)
		zz += 4.0


func _capstan() -> void:
	var c := _center_spot(Vector3(1.4, 1.2, 1.4))
	if c == Vector3.INF:
		return
	sk.cyl("wood" if not steel else "metal", c, 0.55, 0.45, 1.0, 10, DARKW if not steel else IRON)
	sk.col_box(c + Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 1.0))
	if not steel:
		for k in 4:
			var a := TAU * k / 4.0
			sk.rod("wood", c + Vector3(0, 0.85, 0), c + Vector3(cos(a) * 1.3, 0.9, sin(a) * 1.3), 0.05, WOOD, 4)


func _grand_stair() -> void:
	var c := _center_spot(Vector3(3.0, 1.0, 3.0))
	if c == Vector3.INF:
		return
	for k in 6:
		sk.box("wood", c + Vector3(0, 0.1 + k * 0.18, -1.0 + k * 0.35), Vector3(2.6 - k * 0.1, 0.18, 0.4), Color(0.55, 0.35, 0.2))
	for sx: float in [-1.35, 1.35]:
		sk.rod("metal", c + Vector3(float(sx), 0.9, -1.0), c + Vector3(float(sx), 1.9, 1.0), 0.05, BRASS, 4)
		for k in 5:
			var p := c + Vector3(float(sx), 0.2 + k * 0.22, -1.0 + k * 0.5)
			sk.rod("metal", p, p + Vector3(0, 0.75, 0), 0.025, IRON, 3)


func _washstand() -> void:
	for c in _along_walls(Vector3(0.6, 1.0, 0.8), 3.0, 1):
		var cv: Vector3 = c
		sk.box("wood", cv + Vector3(0, 0.45, 0), Vector3(0.55, 0.9, 0.75), DARKW)
		sk.cyl("plaster", cv + Vector3(0, 0.9, 0), 0.25, 0.2, 0.12, 10, WHITE)


func _scrolls() -> void:
	var c := _center_spot(Vector3(1.2, 0.6, 0.8))
	if c == Vector3.INF:
		return
	sk.box("wood", c + Vector3(0, 0.18, 0), Vector3(1.1, 0.36, 0.7), Color(0.15, 0.08, 0.06))
	sk.kit.cylinder("cloth", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c + Vector3(-0.3, 0.42, 0)), 0.05, 0.05, 0.6, 6, Color(0.95, 0.9, 0.75))
	sk.box("cloth", c + Vector3(0.1, 0.37, 0.1), Vector3(0.4, 0.01, 0.3), Color(0.95, 0.88, 0.7))
	sk.box("flat", c + Vector3(0.1, 0.38, 0.1), Vector3(0.08, 0.01, 0.08), RED)

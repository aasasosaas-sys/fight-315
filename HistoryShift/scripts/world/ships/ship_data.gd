class_name ShipData
extends RefCounted
## 船の仕様: data/ships/<id>.json（調査データ＋"layout" ブロック）からゲーム用の形状・甲板・部屋・区画を作る。
## 座標（船ローカル）: 原点は設計水線面の船体中央。+Y 上、船首が -Z（車・馬と同じ前方）、+X が右舷、-X が左舷。
## s = 水線の船首材からの距離 m（データの position_from_bow_m と同じ向き）。z = s - L/2。
## 甲板の高さ level_m は水線からの高さ。ゲームでは天井高 HEADROOM 未満の甲板間隔だけ広げる（headroom_adjusted に記録）。

const DIR := "res://data/ships/"
const HEADROOM := 2.15
const STAIR_W := 1.25
static var _cache := {}

var id := ""
var raw: Dictionary = {}
var lay: Dictionary = {}
var name_ja := ""
var name_en := ""
var era := ""
var year := 1900
var form := "steel"
var L := 30.0
var B := 8.0
var T := 2.0
var disp := 300.0
var top_b := 2.0
var top_m := 1.5
var top_s := 2.0
var sim_fb := 1.5
var bulwark := 1.0
# 船体形状（plan: 水線面の平面形、section: 横断面）
var pb := 2.0
var ps := 2.6
var midp := 0.3
var qexp := 0.55
var tb := 0.0
var ts := 0.0
var bilge := 3.0
var flare := 0.0
var flare_bow := 0.0
var rake := 0.0
var forefoot := 0.0
var overhang := 0.0
var cutup := 0.0
var rise_b := 0.0
var rise_s := 0.0
var colors: Dictionary = {}
var hull_mat := "metal"
var deck_mat := "wood"
var parts: Array = []
var sim: Dictionary = {}
var pilot: Dictionary = {}
var lighting := "lantern"        # lantern / gas / electric / battle
var steel := true
var headroom_adjusted: Array = []

# ---- 配置計画（plan() で作る）
var decks: Array = []            # {name, level, kind("weather"/"internal"/"super"), rooms:Array, conf}
var regions: Array = []          # 床: {y, z0, z1, x0, x1, kind("hull"/"in"/"top"), covered, ceil, part}
var stairs: Array = []           # {y0, y1, z0, z1, x0, x1, dir(+1: +z へ登る), ext(外装側で作る)}
var rooms: Array = []            # {name, deck, y, h, z0, z1, x0, x1, enclosed, door, words, conf, src}
var bulkheads: Array = []        # s
var comps: Array = []            # {z0, z1, x0, x1, side, top, keel, vol, area, name, magazine, boiler}
var doors: Array = []            # {y, z, x, axis("z"/"x"), a, b, open}
var valves: Array = []           # {z, x, y, comp, area, name, kind}
var pumps: Array = []            # {z, x, y}
var ladder: Dictionary = {}      # {z, side, y}
var helm: Dictionary = {}        # {z, x, y}
var crew_points: Array = []      # Vector3 local
var hull_levels: Array = []      # 船体内の歩ける甲板（weather + internal）の高さ（降順）
var _planned := false


static func load_ship(sid: String) -> ShipData:
	if _cache.has(sid):
		return _cache[sid]
	var d := _read(sid)
	if d.is_empty():
		push_warning("ShipData: no data for %s" % sid)
		return null
	var sd := ShipData.new()
	sd._setup(d)
	sd.plan()
	_cache[sid] = sd
	return sd


static func _read(sid: String) -> Dictionary:
	var path := DIR + sid + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("ShipData: bad json %s" % path)
		return {}
	var d: Dictionary = parsed
	if d.has("variant_of"):
		var base := _read(String(d["variant_of"]))
		if base.is_empty():
			return d
		var merged: Dictionary = base.duplicate(true)
		for k in d:
			if k == "variant_of" or k == "layout_patch":
				continue
			merged[k] = d[k]
		if d.has("layout_patch"):
			merged["layout"] = _merge(merged.get("layout", {}), d["layout_patch"])
		return merged
	return d


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate(true)
	for k in b:
		if out.has(k) and out[k] is Dictionary and b[k] is Dictionary:
			out[k] = _merge(out[k], b[k])
		else:
			out[k] = b[k]
	return out


static func _num(v, dflt := 0.0) -> float:
	if v is float or v is int:
		return float(v)
	if v is Dictionary:
		var d: Dictionary = v
		for k in ["value", "full", "standard", "mid"]:
			if d.has(k) and (d[k] is float or d[k] is int):
				return float(d[k])
	return dflt


static func col(v, dflt: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return dflt


func c(key: String, dflt: Color) -> Color:
	return col(colors.get(key, null), dflt)


func z_of(s: float) -> float:
	return s - L * 0.5


func s_of(z: float) -> float:
	return z + L * 0.5


# ================================================================ 読み込み
func _setup(d: Dictionary) -> void:
	raw = d
	id = String(d.get("id", "ship"))
	var nm: Dictionary = d.get("name", {})
	name_ja = String(nm.get("ja", id))
	name_en = String(nm.get("en", id))
	era = String(d.get("era", ""))
	year = int(d.get("year", 1900))
	var dims: Dictionary = d.get("dimensions", {})
	lay = d.get("layout", {})
	var h: Dictionary = lay.get("hull", {})
	form = String(lay.get("form", "steel"))
	steel = form == "steel"
	L = _num(h.get("L", dims.get("length_overall_m", 30.0)), 30.0)
	B = _num(h.get("B", dims.get("beam_m", 8.0)), 8.0)
	T = _num(dims.get("draft_m", 2.0), 2.0)
	disp = _num(dims.get("displacement_t", 0.0), 0.0)
	if disp <= 0.0:
		disp = L * B * T * 0.6 * 1.025
	# 形の既定値（船型ごと）
	match form:
		"wood_jp":
			pb = 1.6; ps = 1.4; midp = 0.2; qexp = 0.6; tb = 0.35; ts = 0.6; bilge = 8.0; flare = 0.1
			rise_b = 0.35; rise_s = 0.2; hull_mat = "wood"; bulwark = 0.6
		"wood_cn":
			pb = 1.5; ps = 1.3; midp = 0.25; qexp = 0.6; tb = 0.3; ts = 0.7; bilge = 4.0; flare = 0.06
			rise_b = 0.3; rise_s = 0.15; hull_mat = "darkwood"; bulwark = 0.8
		"wood_west":
			pb = 1.8; ps = 2.2; midp = 0.25; ts = 0.45; bilge = 2.5; flare = -0.06; rake = 3.0; cutup = 1.5
			hull_mat = "darkwood"; bulwark = 1.0
		_:
			hull_mat = "metal"; bulwark = 1.0
	pb = float(h.get("pb", pb)); ps = float(h.get("ps", ps)); midp = float(h.get("mid", midp))
	qexp = float(h.get("q", qexp)); tb = float(h.get("tb", tb)); ts = float(h.get("ts", ts))
	bilge = float(h.get("bilge", bilge)); flare = float(h.get("flare", flare)); flare_bow = float(h.get("flare_bow", flare_bow))
	rake = float(h.get("rake", rake)); forefoot = float(h.get("forefoot", forefoot))
	overhang = float(h.get("overhang", overhang)); cutup = float(h.get("cutup", cutup))
	rise_b = float(h.get("rise_b", rise_b)); rise_s = float(h.get("rise_s", rise_s))
	bulwark = float(h.get("bulwark", bulwark))
	hull_mat = String(h.get("hull_mat", hull_mat))
	deck_mat = String(h.get("deck_mat", "wood"))
	colors = h.get("colors", {})
	# 乾舷・舷側の高さ
	var fbv = dims.get("freeboard_m", null)
	var fm := 2.0
	var fbow := -1.0
	var fst := -1.0
	if fbv is Dictionary:
		var fd: Dictionary = fbv
		fm = _num(fd.get("mid", fd.get("hull_main_deck", fd.get("flight_deck", 2.0))), 2.0)
		fbow = _num(fd.get("bow", -1.0), -1.0)
		fst = _num(fd.get("stern", -1.0), -1.0)
	elif fbv is float or fbv is int:
		fm = float(fbv)
	var fl: Dictionary = d.get("flooding", {})
	sim_fb = _num(fl.get("freeboard_m", fm), fm)
	top_m = fm
	top_b = fbow if fbow > 0.0 else fm * 1.15
	top_s = fst if fst > 0.0 else fm * 1.05
	if h.has("sheer"):
		var sh: Array = h["sheer"]
		top_b = float(sh[0]); top_m = float(sh[1]); top_s = float(sh[2])
	sim = lay.get("sim", {})
	sim_fb = float(sim.get("fb", sim_fb))
	pilot = lay.get("pilot", {})
	parts = lay.get("parts", [])
	var lt := String((d.get("lighting", {}) as Dictionary).get("type", "lantern")).to_lower()
	if lt.find("electric") >= 0 or lt.find("incandescent") >= 0:
		lighting = "electric" if year >= 1920 else "gas"
		if lt.find("red") >= 0:
			lighting = "battle"
	elif year >= 1890:
		lighting = "gas"
	else:
		lighting = "lantern"
	lighting = String(lay.get("lighting", lighting))


# ================================================================ 船体の形
## 水線面の半幅（t: -1 船首 … +1 船尾）
func plan_w(t: float) -> float:
	var a := absf(t)
	var tt := clampf((a - midp) / maxf(1.0 - midp, 0.01), 0.0, 1.0)
	var p := pb if t < 0.0 else ps
	var base := pow(maxf(0.0, 1.0 - pow(tt, p)), qexp)
	var tr := tb if t < 0.0 else ts
	return tr + (1.0 - tr) * base


## 舷側上端（甲板の縁）の高さ。u: 0 船首 … 1 船尾
func top_u(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	if u < 0.5:
		return lerpf(top_m, top_b, pow((0.5 - u) / 0.5, 2.0))
	return lerpf(top_m, top_s, pow((u - 0.5) / 0.5, 2.0))


func keel_u(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	var r := rise_b * smoothstep(0.3, 0.0, u) + rise_s * smoothstep(0.75, 1.0, u)
	return -T * (1.0 - r)


func top_at(z: float) -> float:
	return top_u(z / L + 0.5)


func keel_at(z: float) -> float:
	return keel_u(z / L + 0.5)


## 高さ y での船首材・船尾の z
func z_ends(y: float) -> Vector2:
	var zb := -L * 0.5
	var zs := L * 0.5
	if y >= 0.0:
		zb -= rake * clampf(y / maxf(top_b, 0.5), 0.0, 1.5)
		zs += overhang * clampf(y / maxf(top_s, 0.5), 0.0, 1.5)
	else:
		var k := clampf(-y / maxf(T, 0.1), 0.0, 1.0)
		zb += forefoot * k
		zs -= cutup * k
	return Vector2(zb, zs)


## 横断面の係数（y の高さで水線半幅の何倍か）
func section_k(u: float, y: float) -> float:
	if y < 0.0:
		var kl := keel_u(u)
		var yn := clampf(y / minf(kl, -0.05), 0.0, 1.0)
		return pow(maxf(0.0, 1.0 - pow(yn, bilge)), 1.0 / bilge)
	var tp := maxf(top_u(u), 0.5)
	var bow_k := smoothstep(0.45, 0.0, u)
	return maxf(0.05, 1.0 + flare * y / tp + flare_bow * bow_k * y / tp)


## 船体の半幅（パラメタ u と高さ y）
func hb_u(u: float, y: float) -> float:
	return B * 0.5 * plan_w(u * 2.0 - 1.0) * section_k(u, y)


## 船体の半幅（ローカル z と高さ y）。船体外なら 0
func half_beam(z: float, y: float) -> float:
	var e := z_ends(y)
	if z < e.x or z > e.y:
		return 0.0
	var u := (z - e.x) / maxf(e.y - e.x, 0.01)
	if y < keel_u(u) or y > top_u(u) + bulwark:
		return 0.0
	return hb_u(u, y)


func u_at(z: float, y: float) -> float:
	var e := z_ends(y)
	return clampf((z - e.x) / maxf(e.y - e.x, 0.01), 0.0, 1.0)


## ローカル点が船体の内側か
func inside(p: Vector3, margin := 0.0) -> bool:
	var hb := half_beam(p.z, p.y)
	return hb > 0.0 and absf(p.x) < hb - margin


# ================================================================ 配置計画
func plan() -> void:
	if _planned:
		return
	_planned = true
	_plan_decks()
	_plan_regions()
	_plan_stairs()
	_plan_rooms()
	_plan_compartments()
	_plan_fittings()


## 甲板一覧と分類
func _plan_decks() -> void:
	var lv_over: Dictionary = lay.get("deck_levels", {})
	var hints: Dictionary = lay.get("rooms", {})
	var list: Array = []
	var src: Array = raw.get("decks", [])
	for i in src.size():
		var dk: Dictionary = src[i]
		var lv := float(lv_over.get(str(i), dk.get("level_m", 0.0)))
		list.append({"name": String(dk.get("name", "")), "level": lv, "data_level": float(dk.get("level_m", 0.0)), "rooms": (dk.get("rooms", []) as Array).duplicate(), "conf": "data"})
	for ex in lay.get("extra_decks", []):
		var exd: Dictionary = ex
		list.append({"name": String(exd.get("name", "")), "level": float(exd.get("level_m", 0.0)), "data_level": float(exd.get("level_m", 0.0)),
			"rooms": (exd.get("rooms", []) as Array).duplicate(), "conf": "reconstruction"})
	# 部屋のヒントで別の甲板へ移す（同じ甲板に重なって並ぶ格納庫など）
	for dk in list:
		var keep: Array = []
		for r in dk["rooms"]:
			var hint := _hint_for(String((r as Dictionary).get("name", "")), hints)
			if hint.has("level") and absf(float(hint["level"]) - float(dk["level"])) > 0.3:
				var lv2 := float(hint["level"])
				var target: Dictionary = {}
				for dk2 in list:
					if absf(float(dk2["level"]) - lv2) < 0.3:
						target = dk2
				if target.is_empty():
					target = {"name": String(r.get("name", "")), "level": lv2, "data_level": lv2, "rooms": [], "conf": "reconstruction"}
					list.append(target)
				(target["rooms"] as Array).append(r)
			else:
				keep.append(r)
		dk["rooms"] = keep
	list.sort_custom(func(a, b): return float(a["level"]) > float(b["level"]))
	# 分類
	for dk in list:
		var lv: float = dk["level"]
		if lv > top_m + 1.2:
			dk["kind"] = "super"
		elif lv >= top_m - 1.2:
			dk["kind"] = "weather"
			dk["level"] = top_m
		else:
			dk["kind"] = "internal"
	# 天井高の確保（船体内の甲板と上部構造の甲板それぞれで）
	var keel := -T + 0.45
	var prev := top_m
	for dk in list:
		if dk["kind"] != "internal":
			continue
		var lv: float = dk["level"]
		if prev - lv < HEADROOM:
			var nl := prev - HEADROOM
			headroom_adjusted.append([dk["name"], lv, nl])
			dk["level"] = nl
		prev = dk["level"]
	var low := INF
	for dk in list:
		if dk["kind"] == "internal":
			low = minf(low, float(dk["level"]))
	if low < keel:
		# 船底に届いてしまう: いちばん下の甲板は船底の上に置き、届かない甲板は省く
		var out: Array = []
		for dk in list:
			if dk["kind"] == "internal" and float(dk["level"]) < keel:
				if absf(float(dk["level"]) - keel) < 0.8:
					dk["level"] = keel
				else:
					headroom_adjusted.append([dk["name"], dk["level"], "removed"])
					continue
			out.append(dk)
		list = out
	decks = list
	hull_levels.clear()
	for dk in decks:
		if dk["kind"] != "super":
			hull_levels.append(float(dk["level"]))
	if hull_levels.is_empty() or absf(float(hull_levels[0]) - top_m) > 0.01:
		hull_levels.push_front(top_m)
	# 同じ高さの重複を除く
	var uniq: Array = []
	for v in hull_levels:
		if uniq.is_empty() or absf(float(uniq.back()) - float(v)) > 0.3:
			uniq.append(v)
	hull_levels = uniq


func _hint_for(room_name: String, hints: Dictionary) -> Dictionary:
	for k in hints:
		if room_name.begins_with(String(k)):
			return hints[k]
	return {}


## 部品から床の領域を作る
func _plan_regions() -> void:
	regions.clear()
	for i in parts.size():
		var p: Dictionary = parts[i]
		var t := String(p.get("t", ""))
		match t:
			"house", "island", "yagura", "castle":
				var r := part_rect(p)
				var y0 := float(p.get("y0", top_at(r.position.y + r.size.y * 0.5)))
				var y1 := float(p.get("y1", p.get("y", y0 + 2.5)))
				if t == "castle":
					y0 = top_at(r.position.y + r.size.y * 0.5)
				regions.append({"y": y0, "z0": r.position.y, "z1": r.end.y, "x0": r.position.x, "x1": r.end.x, "kind": "in", "covered": true, "ceil": y1, "part": i})
				if bool(p.get("floor", true)):
					regions.append({"y": y1, "z0": r.position.y, "z1": r.end.y, "x0": r.position.x, "x1": r.end.x, "kind": "top", "covered": false, "ceil": INF, "part": i})
			"tower":
				var tiers: Array = p.get("tiers", [])
				for k in tiers.size():
					var tr: Dictionary = tiers[k]
					var q := tr.duplicate()
					q["x"] = p.get("x", 0.0)
					var r := part_rect(q)
					regions.append({"y": float(tr["y0"]), "z0": r.position.y, "z1": r.end.y, "x0": r.position.x, "x1": r.end.x, "kind": "in", "covered": true, "ceil": float(tr["y1"]), "part": i, "tier": k})
					regions.append({"y": float(tr["y1"]), "z0": r.position.y, "z1": r.end.y, "x0": r.position.x, "x1": r.end.x, "kind": "top", "covered": false, "ceil": INF, "part": i, "tier": k})
			"platform", "flight_deck":
				var r := part_rect(p)
				regions.append({"y": float(p.get("y", top_m)), "z0": r.position.y, "z1": r.end.y, "x0": r.position.x, "x1": r.end.x, "kind": "top", "covered": false, "ceil": INF, "part": i})
	# 上に別の床があれば covered
	for r in regions:
		if r["kind"] != "top":
			continue
		for o in regions:
			if o == r or float(o["y"]) <= float(r["y"]) + 0.5:
				continue
			if _overlap(r, o) > 0.6 * (float(r["z1"]) - float(r["z0"])) * (float(r["x1"]) - float(r["x0"])):
				r["covered"] = true
				r["ceil"] = minf(float(r["ceil"]), float(o["y"]))


## 部品の平面矩形（Rect2: position=(x0, z0), size=(w, d)）
func part_rect(p: Dictionary) -> Rect2:
	var s0 := float(p.get("s0", float(p.get("s", L * 0.5)) - float(p.get("d", 4.0)) * 0.5))
	var s1 := float(p.get("s1", float(p.get("s", L * 0.5)) + float(p.get("d", 4.0)) * 0.5))
	var w := float(p.get("w", 4.0))
	var x := float(p.get("x", 0.0))
	if p.has("side") and String(p.get("t", "")) == "island":
		var sd := float(p["side"])
		var y := float(p.get("y0", top_m))
		x = sd * (half_beam(z_of((s0 + s1) * 0.5), minf(y, top_m)) - w * 0.5 + float(p.get("out", 0.0)))
	if String(p.get("t", "")) == "castle" and not p.has("w"):
		w = 2.0 * half_beam(z_of((s0 + s1) * 0.5), top_m) - 0.4
	return Rect2(Vector2(x - w * 0.5, z_of(s0)), Vector2(w, s1 - s0))


static func _overlap(a: Dictionary, b: Dictionary) -> float:
	var dz := minf(float(a["z1"]), float(b["z1"])) - maxf(float(a["z0"]), float(b["z0"]))
	var dx := minf(float(a["x1"]), float(b["x1"])) - maxf(float(a["x0"]), float(b["x0"]))
	return maxf(dz, 0.0) * maxf(dx, 0.0)


static func _rect_hit(a: Dictionary, b: Dictionary, pad := 0.0) -> bool:
	return float(a["z0"]) < float(b["z1"]) + pad and float(b["z0"]) < float(a["z1"]) + pad \
		and float(a["x0"]) < float(b["x1"]) + pad and float(b["x0"]) < float(a["x1"]) + pad


## 甲板の上に立つ部品の床面の矩形（階段が重ならないように）
func _deck_obstacles(y: float) -> Array:
	var out: Array = []
	for p in parts:
		var pd: Dictionary = p
		var t := String(pd.get("t", ""))
		if t in ["turret", "funnel", "house", "island", "yagura", "tower", "castle", "mast", "catapult", "paddle", "boats", "crane"]:
			var r: Rect2
			if t == "tower":
				var tiers: Array = pd.get("tiers", [])
				if tiers.is_empty():
					continue
				var q: Dictionary = (tiers[0] as Dictionary).duplicate()
				q["x"] = pd.get("x", 0.0)
				r = part_rect(q)
			elif t in ["turret", "funnel", "mast", "catapult", "crane"]:
				var w := float(pd.get("w", float(pd.get("rx", float(pd.get("r", 1.0)))) * 2.0 + 1.0))
				var dd := float(pd.get("d", float(pd.get("rz", float(pd.get("r", 1.0)))) * 2.0 + 1.0))
				if t == "turret":
					dd += float(pd.get("len", 0.0)) * 0.0
				r = Rect2(Vector2(float(pd.get("x", 0.0)) - w * 0.5, z_of(float(pd.get("s", L * 0.5))) - dd * 0.5), Vector2(w, dd))
			elif t == "paddle":
				var pr := float(pd.get("r", 4.0))
				var zc := z_of(float(pd.get("s", L * 0.5)))
				r = Rect2(Vector2(-B, zc - pr - 1.0), Vector2(B * 2.0, pr * 2.0 + 2.0))
			elif t == "boats":
				r = Rect2(Vector2(-B * 0.5, z_of(float(pd.get("s0", 0.0)))), Vector2(B, float(pd.get("s1", 0.0)) - float(pd.get("s0", 0.0))))
				if String(pd.get("side", "both")) == "both":
					continue
			else:
				r = part_rect(pd)
			var y0 := float(pd.get("y0", pd.get("y", top_m)))
			if t == "castle":
				y0 = y - 0.1
			if absf(y0 - y) < 1.3 or (t in ["turret", "funnel", "mast", "tower", "catapult", "crane", "paddle"] and y0 < y + 1.3 and y0 > y - 3.0):
				out.append({"z0": r.position.y, "z1": r.end.y, "x0": r.position.x, "x1": r.end.x})
	return out


## 階段の配置: 船体内（甲板間）と上部構造（部品の床どうし）
func _plan_stairs() -> void:
	stairs.clear()
	# --- 船体内
	var n := 1 if L < 60.0 else (2 if L < 200.0 else 3)
	var at: Array = [0.52] if n == 1 else ([0.3, 0.68] if n == 2 else [0.24, 0.5, 0.76])
	if lay.has("stairs_at"):
		at = lay["stairs_at"]
	for k in range(hull_levels.size() - 1):
		var y1: float = hull_levels[k]
		var y0: float = hull_levels[k + 1]
		for j in at.size():
			var s := float(at[j]) * L + (2.5 if k % 2 == 1 else 0.0)
			var side := 1.0 if (j + k) % 2 == 0 else -1.0
			var z := z_of(s)
			var top := top_at(z) if k == 0 else y1
			var st := _make_stair(y0, top, z, side, k == 0)
			if not st.is_empty():
				stairs.append(st)
	# --- 上部構造
	for r in regions:
		if r["kind"] != "top":
			continue
		var y := float(r["y"])
		var below := _floor_below(r, y)
		if below.is_empty():
			continue
		var y0 := float(below["y"])
		var rise := y - y0
		if rise < 0.6:
			continue
		var run := _stair_run(rise)
		var p: Dictionary = parts[int(r["part"])]
		var t := String(p.get("t", ""))
		var ins := t in ["house", "island", "yagura", "tower", "castle"]
		var zc0 := float(r["z0"])
		var zc1 := float(r["z1"])
		var x0 := float(r["x0"])
		var x1 := float(r["x1"])
		var w := STAIR_W
		var st: Dictionary
		var flights := maxi(1, ceili(rise / 4.2))
		if ins:
			# 部品の中: 後端寄り、舷側寄り
			var len_needed := run / flights + _land_len(flights) + 0.2
			var zz1 := zc1 - 0.4
			var zz0 := maxf(zc0 + 0.4, zz1 - len_needed)
			var xs := x1 - 0.3 - w * (2.0 if flights > 1 else 1.0)
			if xs < x0 + 0.3:
				xs = x0 + 0.3
			st = {"y0": y0, "y1": y, "z0": zz0, "z1": zz1, "x0": xs, "x1": xs + w * (2.0 if flights > 1 else 1.0), "dir": -1, "ext": true, "flights": flights}
		else:
			# 足場（platform）: 後端から下の床へ
			var len_needed := run / flights + _land_len(flights) + 0.2
			st = {"y0": y0, "y1": y, "z0": zc1, "z1": zc1 + len_needed, "x0": x1 - w * (2.0 if flights > 1 else 1.0) - 0.2, "x1": x1 - 0.2, "dir": -1, "ext": true, "flights": flights}
			if t == "flight_deck":
				continue
		stairs.append(st)


## 甲板 y の位置 z に、下の甲板 y0 から登る階段を置く（障害物を避けて z をずらす）
func _make_stair(y0: float, y1: float, z: float, side: float, from_weather: bool) -> Dictionary:
	var rise := y1 - y0
	if rise < 0.5:
		return {}
	var flights := maxi(1, ceili(rise / 4.2))
	var run := _stair_run(rise) / flights + _land_len(flights) + 0.2
	var w := STAIR_W * (2.0 if flights > 1 else 1.0)
	var obst: Array = _deck_obstacles(y1) if from_weather else []
	for tries in 24:
		var zz := z + (float(tries / 2) * 3.0) * (1.0 if tries % 2 == 0 else -1.0)
		var hb0 := minf(half_beam(zz, y0 + 0.1), half_beam(zz + run, y0 + 0.1))
		var hb1 := minf(half_beam(zz, y1 - 0.1), half_beam(zz + run, y1 - 0.1))
		var hb := minf(hb0, hb1)
		if hb < w + 1.2:
			continue
		var xc := side * clampf(hb * 0.4, w * 0.5 + 0.6, hb - w * 0.5 - 0.6)
		var st := {"y0": y0, "y1": y1, "z0": zz, "z1": zz + run, "x0": xc - w * 0.5, "x1": xc + w * 0.5, "dir": -1, "ext": from_weather, "flights": flights, "hatch": true}
		var ok := true
		for o in obst:
			if _rect_hit(st, o, 0.6):
				ok = false
				break
		for o in stairs:
			if absf(float(o["y1"]) - y1) < 0.3 or absf(float(o["y0"]) - y0) < 0.3 or absf(float(o["y1"]) - y0) < 0.3:
				if _rect_hit(st, o, 0.8):
					ok = false
					break
		if ok:
			return st
	return {}


func _land_len(flights: int) -> float:
	return (1.0 if flights > 1 else 0.0) + (1.0 if flights >= 3 else 0.0)


func _stair_run(rise: float) -> float:
	return rise / tan(deg_to_rad(40.0))


## 床 r の真下にある床（部品の中の床、甲板）
func _floor_below(r: Dictionary, y: float) -> Dictionary:
	var best: Dictionary = {}
	var by := -INF
	var cz := (float(r["z0"]) + float(r["z1"])) * 0.5
	var cx := (float(r["x0"]) + float(r["x1"])) * 0.5
	for o in regions:
		if o == r:
			continue
		var oy := float(o["y"])
		if oy >= y - 0.5 or oy <= by:
			continue
		if cz >= float(o["z0"]) - 1.0 and cz <= float(o["z1"]) + 1.0 and cx >= float(o["x0"]) - 1.0 and cx <= float(o["x1"]) + 1.0:
			best = o
			by = oy
	var hy := top_at(cz)
	if hy > by and hy < y - 0.5:
		return {"y": hy, "z0": cz - 5.0, "z1": cz + 5.0, "x0": -B * 0.4, "x1": B * 0.4, "kind": "hull"}
	return best


# ================================================================ 部屋
const ENCLOSED_WORDS := ["room", "室", "cabin", "wheelhouse", "house", "chapel", "shrine", "galley", "lobby", "hall", "saloon",
	"office", "bridge", "艦橋", "tower", "司令塔", "heads", "厠", "sick", "医務", "wardroom", "smoking", "operations", "作戦", "magazine",
	"弾火薬庫", "火薬庫", "engine", "boiler", "機関", "機械", "罐", "汽罐", "steering", "舵", "wireless", "無線", "cabin", "tiller"]
const OPEN_WORDS := ["deck", "甲板", "turret", "砲塔", "battery", "gun", "funnel", "boat", "forecastle", "quarterdeck", "mast",
	"promenade", "hangar", "格納庫", "hold", "compartments", "waist", "platform", "galleries", "catapult", "sponson", "paddle",
	"lifeboats", "flight", "oar", "berth", "居住区", "uptakes", "trunk", "casemate", "steering"]


func _words(r: Dictionary) -> String:
	var s := (String(r.get("name", "")) + " " + String(r.get("purpose", "")) + " " + " ".join(PackedStringArray(r.get("key_props", [])))).to_lower()
	return s


func _has_any(s: String, words: Array) -> bool:
	for wd in words:
		if s.find(String(wd)) >= 0:
			return true
	return false


## position の文字列 → 船首からの比率の範囲の配列（複数の写し）
func _pos_ranges(pos: String) -> Array:
	var p := pos.to_lower()
	var both := p.find("bow and stern") >= 0 or p.find("fore and aft") >= 0 or p.find("bow and mid") >= 0
	if p.find("4 corners") >= 0:
		return [[0.3, 0.38], [0.66, 0.74]]
	if p.find("full length") >= 0:
		return [[0.06, 0.94]]
	if both:
		if p.find("bow and mid") >= 0:
			return [[0.1, 0.25], [0.42, 0.58]]
		return [[0.06, 0.26], [0.74, 0.94]]
	if p.find("mid-stern") >= 0 or p.find("stern-mid") >= 0 or p.find("aft of the bridge") >= 0:
		return [[0.56, 0.74]]
	if p.find("bow-mid") >= 0 or p.find("forward of amidships") >= 0 or p.find("mid-forward") >= 0 or p.find("slightly forward") >= 0:
		return [[0.28, 0.46]]
	if p.find("stern") >= 0 or p.find("aft") >= 0:
		return [[0.72, 0.94]]
	if p.find("bow") >= 0 or p.find("fore") >= 0:
		return [[0.06, 0.28]]
	return [[0.36, 0.64]]


func _pos_sides(pos: String) -> Array:
	var p := pos.to_lower()
	if p.find("port and starboard") >= 0 or p.find("4 corners") >= 0 or (p.find("port") >= 0 and p.find("starboard") >= 0):
		return [-1, 1]
	if p.find("starboard") >= 0:
		return [1]
	if p.find("port") >= 0:
		return [-1]
	return [0]


func _plan_rooms() -> void:
	rooms.clear()
	var hints: Dictionary = lay.get("rooms", {})
	var occupied := {}   # 甲板の高さ(文字列) -> Array[rect]
	for st in stairs:
		for y: float in [float(st["y0"]), float(st["y1"])]:
			var key := "%.1f" % y
			if not occupied.has(key):
				occupied[key] = []
			(occupied[key] as Array).append({"z0": float(st["z0"]) - 0.3, "z1": float(st["z1"]) + 0.3, "x0": float(st["x0"]) - 0.3, "x1": float(st["x1"]) + 0.3})
	for di in decks.size():
		var dk: Dictionary = decks[di]
		var lv: float = dk["level"]
		var kind: String = dk["kind"]
		var key := "%.1f" % lv
		if not occupied.has(key):
			occupied[key] = []
		var occ: Array = occupied[key]
		var ceil_y := _ceiling_above(lv, kind)
		for r in dk["rooms"]:
			var rd: Dictionary = r
			var hint := _hint_for(String(rd.get("name", "")), hints)
			if bool(hint.get("skip", false)):
				continue
			var words := _words(rd)
			var size: Array = rd.get("approx_size_m", [6, 4])
			var rl := float(size[0]) if size.size() > 0 else 6.0
			var rw := float(size[1]) if size.size() > 1 else 4.0
			var copies: Array = []
			if hint.has("copies"):
				for cp in hint["copies"]:
					var ca: Array = cp
					copies.append({"z0": z_of(float(ca[0])), "z1": z_of(float(ca[1])), "x0": float(ca[2]), "x1": float(ca[3]), "fixed": true})
			else:
				var rngs: Array = _pos_ranges(String(rd.get("position", "mid")))
				if hint.has("s"):
					var hs: Array = hint["s"]
					rngs = [[float(hs[0]) / L, float(hs[1]) / L]]
				var sides: Array = _pos_sides(String(rd.get("position", "")))
				if hint.has("side"):
					sides = [int(hint["side"])]
				for rg in rngs:
					var ra: Array = rg
					var s0 := float(ra[0]) * L
					var s1 := float(ra[1]) * L
					var sc := (s0 + s1) * 0.5
					var full := String(rd.get("position", "")).to_lower().find("full length") >= 0
					var ln := rl if not full else maxf(rl, s1 - s0)
					if hint.has("s"):
						ln = s1 - s0
					for sd in sides:
						copies.append({"zc": z_of(sc), "len": ln, "side": int(sd), "w": rw, "fixed": hint.has("s")})
			# 置く領域
			for cp in copies:
				var cpd: Dictionary = cp
				var reg := _region_for(lv, kind, float(cpd.get("zc", (float(cpd.get("z0", 0.0)) + float(cpd.get("z1", 0.0))) * 0.5)), words)
				if reg.is_empty():
					continue
				var rect := {}
				if cpd.has("z0"):
					rect = {"z0": float(cpd["z0"]), "z1": float(cpd["z1"]), "x0": float(cpd["x0"]), "x1": float(cpd["x1"])}
				else:
					rect = _fit_room(reg, float(cpd["zc"]), float(cpd["len"]), float(cpd["w"]), int(cpd["side"]), occ, bool(cpd.get("fixed", false)), lv)
				if rect.is_empty():
					continue
				var area_frac := ((float(rect["z1"]) - float(rect["z0"])) * (float(rect["x1"]) - float(rect["x0"]))) / maxf(1.0, (float(reg["z1"]) - float(reg["z0"])) * (float(reg["x1"]) - float(reg["x0"])))
				var enclosed := false
				var nm := String(rd.get("name", "")).to_lower()
				if kind == "internal":
					enclosed = area_frac < 0.4 and not _has_any(nm, ["hangar", "格納庫", "hold", "compartments", "oar deck", "gun deck", "berth", "居住区", "battery", "casemate", "uptakes", "trunk", "sponson"])
				else:
					enclosed = _has_any(nm, ENCLOSED_WORDS) and not _has_any(nm, ["deck", "甲板", "turret", "砲塔", "battery", "boat", "forecastle", "quarterdeck", "mast", "promenade", "flight", "catapult", "galleries", "funnel", "paddle", "pivot", "open", "platform", "steering"])
					if bool(reg.get("covered", false)) and reg["kind"] == "in":
						enclosed = enclosed or area_frac < 0.55
				# 甲板室・矢倉の中をほぼ占める部屋は、部品の壁がそのまま部屋の壁
				if reg["kind"] == "in" and area_frac > 0.6:
					enclosed = false
				if hint.has("enclosed"):
					enclosed = bool(hint["enclosed"])
				var h := (ceil_y if reg["kind"] == "hull" else float(reg.get("ceil", lv + 2.6))) - lv - 0.25
				if not is_finite(h) or h > 7.0:
					h = 2.6 if enclosed else 3.0
				h = maxf(h, 2.0)
				var room := {"name": String(rd.get("name", "")), "deck": di, "y": lv, "h": h, "z0": rect["z0"], "z1": rect["z1"], "x0": rect["x0"], "x1": rect["x1"],
					"enclosed": enclosed, "words": words, "conf": String(rd.get("confidence", dk.get("conf", ""))), "src": rd, "region": reg["kind"], "open_top": reg["kind"] == "top" or kind == "weather"}
				rooms.append(room)
				occ.append(rect)


## 甲板 lv の天井（その上の甲板の高さ）
func _ceiling_above(lv: float, kind: String) -> float:
	var best := INF
	if kind == "internal":
		for y in hull_levels:
			if float(y) > lv + 0.5:
				best = minf(best, float(y))
	return best


## 甲板 lv で z 付近の、部屋を置ける領域
func _region_for(lv: float, kind: String, zc: float, words: String) -> Dictionary:
	if kind == "internal":
		var e := z_ends(lv)
		var hb := half_beam(clampf(zc, e.x + 1.0, e.y - 1.0), lv + 0.3)
		var zmin := e.x + 1.5
		var zmax := e.y - 1.5
		return {"y": lv, "z0": zmin, "z1": zmax, "x0": -hb + 0.4, "x1": hb - 0.4, "kind": "hull", "covered": true}
	# 部品の床（中か上）で z を含むもの
	var best: Dictionary = {}
	var bd := INF
	for r in regions:
		if absf(float(r["y"]) - lv) > 0.7:
			continue
		var d := 0.0
		if zc < float(r["z0"]):
			d = float(r["z0"]) - zc
		elif zc > float(r["z1"]):
			d = zc - float(r["z1"])
		if r["kind"] == "in":
			d -= 0.5   # 囲われた中を優先
		if d < bd:
			bd = d
			best = r
	if not best.is_empty() and (bd < 12.0 or kind == "super"):
		return best
	if kind == "weather":
		var e2 := z_ends(top_m)
		var hb2 := half_beam(clampf(zc, e2.x + 2.0, e2.y - 2.0), top_at(zc) - 0.1)
		return {"y": top_m, "z0": e2.x + 2.0, "z1": e2.y - 2.0, "x0": -hb2 + 0.5, "x1": hb2 - 0.5, "kind": "hull", "covered": false}
	return {}


## 領域 reg の中に部屋を置く（重なりは z 方向にずらし、だめなら縮める）
func _fit_room(reg: Dictionary, zc: float, ln: float, wd: float, side: int, occ: Array, fixed: bool, lv: float) -> Dictionary:
	var z0r := float(reg["z0"])
	var z1r := float(reg["z1"])
	ln = clampf(ln, 2.0, z1r - z0r)
	for shrink in 4:
		var l2 := ln * pow(0.72, shrink)
		if l2 < 1.8:
			break
		for tries in 40:
			var zz := zc + float(tries / 2) * 1.5 * (1.0 if tries % 2 == 0 else -1.0)
			if fixed and tries > 0:
				break
			zz = clampf(zz, z0r + l2 * 0.5, z1r - l2 * 0.5)
			var za := zz - l2 * 0.5
			var zb := zz + l2 * 0.5
			var x0r := float(reg["x0"])
			var x1r := float(reg["x1"])
			if reg["kind"] == "hull":
				# 船体内は端で細るので z 範囲の両端で幅を確かめる
				var hb := minf(half_beam(za, lv + 0.3), half_beam(zb, lv + 0.3))
				hb = minf(hb, half_beam(zz, lv + 0.3)) - 0.4
				if hb < 1.2:
					continue
				x0r = maxf(x0r, -hb)
				x1r = minf(x1r, hb)
			var avail := x1r - x0r
			var corridor := 1.4 if avail > 7.0 else 0.0
			var w2: float
			var xa: float
			if side == 0:
				w2 = minf(wd, avail - corridor * 2.0)
				if w2 < 1.5:
					w2 = minf(wd, avail)
				xa = (x0r + x1r) * 0.5 - w2 * 0.5
			else:
				var half := avail * 0.5 - corridor * 0.5
				w2 = minf(wd, half)
				if w2 < 1.2:
					continue
				xa = x1r - w2 if side > 0 else x0r
			var rect := {"z0": za, "z1": zb, "x0": xa, "x1": xa + w2}
			var ok := true
			for o in occ:
				if _rect_hit(rect, o, 0.05):
					ok = false
					break
			if ok:
				return rect
	return {}


# ================================================================ 区画（浸水）
func _plan_compartments() -> void:
	bulkheads.clear()
	var fl: Dictionary = raw.get("flooding", {})
	var bl: Array = fl.get("bulkheads", [])
	for b in bl:
		bulkheads.append(float((b as Dictionary).get("position_from_bow_m", 0.0)))
	if sim.has("bulkheads"):
		bulkheads = (sim["bulkheads"] as Array).duplicate()
	elif bulkheads.is_empty():
		var nb := int(sim.get("n_bulkheads", 0))
		if nb == 0:
			var ws := String(fl.get("watertight_subdivision", "")).to_lower()
			if steel:
				nb = clampi(int(L / 18.0), 4, 14)
			elif ws.find("12 watertight") >= 0:
				nb = 12
			elif ws.find("bulkhead") >= 0 and ws.find("no ") < 0 and ws.find("without") < 0:
				nb = clampi(int(L / 9.0), 2, 6)
			else:
				nb = 0
		for k in nb:
			bulkheads.append(L * float(k + 1) / float(nb + 1))
	bulkheads.sort()
	var split := bool(sim.get("split", false))
	var edges: Array = [0.0]
	edges.append_array(bulkheads)
	edges.append(L)
	comps.clear()
	for k in edges.size() - 1:
		var s0: float = edges[k]
		var s1: float = edges[k + 1]
		if s1 - s0 < 0.5:
			continue
		var z0 := z_of(s0)
		var z1 := z_of(s1)
		var sides: Array = [0]
		if split and k > 0 and k < edges.size() - 2:
			sides = [-1, 1]
		for sd in sides:
			comps.append(_make_comp(z0, z1, int(sd)))
	# 弾火薬庫・缶室
	for m in sim.get("magazines", []):
		var md: Dictionary = m
		var za := z_of(float(md.get("s0", 0.0)))
		var zb := z_of(float(md.get("s1", 0.0)))
		for cp in comps:
			if float(cp["z0"]) < zb and float(cp["z1"]) > za:
				cp["magazine"] = String(md.get("name", "弾火薬庫"))
	var bo: Array = sim.get("boilers", [])
	if bo.size() >= 2:
		for cp in comps:
			if float(cp["z0"]) < z_of(float(bo[1])) and float(cp["z1"]) > z_of(float(bo[0])):
				cp["boiler"] = true


func _make_comp(z0: float, z1: float, side: int) -> Dictionary:
	var keel := keel_at((z0 + z1) * 0.5)
	var top := sim_fb
	var wsum := 0.0
	for f: float in [0.15, 0.5, 0.85]:
		var zz := lerpf(z0, z1, float(f))
		wsum += (half_beam(zz, -0.05) + half_beam(zz, keel * 0.5)) * 0.5
	var hbw := wsum / 3.0
	var x0 := -hbw
	var x1 := hbw
	if side < 0:
		x1 = 0.0
	elif side > 0:
		x0 = 0.0
	var width := x1 - x0
	var area := (z1 - z0) * width * 0.92
	var vol := area * (top - keel)
	return {"z0": z0, "z1": z1, "x0": x0, "x1": x1, "side": side, "top": top, "keel": keel, "vol": maxf(vol, 1.0), "area": maxf(area, 0.5),
		"name": "", "magazine": "", "boiler": false, "cx": (x0 + x1) * 0.5, "cz": (z0 + z1) * 0.5, "w": width}


func comp_at(p: Vector3) -> int:
	var best := -1
	for i in comps.size():
		var cp: Dictionary = comps[i]
		if p.z >= float(cp["z0"]) and p.z <= float(cp["z1"]):
			var sd := int(cp["side"])
			if sd == 0 or (sd < 0 and p.x <= 0.0) or (sd > 0 and p.x > 0.0):
				return i
			best = i
	if best < 0:
		best = 0 if p.z < 0.0 else comps.size() - 1
	return best


## 甲板 y が船体内でいちばん低い歩ける甲板（z の位置で）
func lowest_level_at(z: float) -> float:
	var best := top_m
	for y in hull_levels:
		var yy := float(y)
		if yy < best and half_beam(z, yy + 0.3) > 1.5:
			best = yy
	return best


# ================================================================ 艤装（扉・注水弁・ポンプ・舷梯・舵）
func _plan_fittings() -> void:
	doors.clear()
	valves.clear()
	pumps.clear()
	var split := bool(sim.get("split", false))
	# 水密扉: 船体内の甲板で、区画の境界ごと
	for y in hull_levels:
		var yy := float(y)
		if yy >= sim_fb - 0.5 or comps.size() < 2:
			continue
		for k in comps.size():
			var a: Dictionary = comps[k]
			for k2 in range(k + 1, comps.size()):
				var b: Dictionary = comps[k2]
				if absf(float(a["z1"]) - float(b["z0"])) < 0.05 and (int(a["side"]) == int(b["side"]) or int(a["side"]) == 0 or int(b["side"]) == 0):
					var z := float(a["z1"])
					var hb := half_beam(z, yy + 0.3)
					if hb < 1.5:
						continue
					var x := 0.0
					if int(a["side"]) != 0 and int(b["side"]) != 0:
						x = float(a["side"]) * clampf(hb * 0.5, 1.0, hb - 1.0)
					elif int(a["side"]) != 0 or int(b["side"]) != 0:
						var sd := int(a["side"]) if int(a["side"]) != 0 else int(b["side"])
						x = float(sd) * clampf(hb * 0.5, 1.0, hb - 1.0)
					if _door_blocked(yy, z, x):
						x = -x if x != 0.0 else clampf(hb * 0.5, 1.0, hb - 1.0)
					# 木造船の隔壁の口は水密扉ではない（開いたまま）
					doors.append({"y": yy, "z": z, "x": x, "axis": "z", "a": k, "b": k2, "open": yy > 0.2 or not steel, "hb": hb})
				elif split and int(a["side"]) == -1 and int(b["side"]) == 1 and absf(float(a["z0"]) - float(b["z0"])) < 0.05 and yy < 0.2:
					var zc := (float(a["z0"]) + float(a["z1"])) * 0.5
					if half_beam(zc, yy + 0.3) < 2.0:
						continue
					doors.append({"y": yy, "z": zc, "x": 0.0, "axis": "x", "a": k, "b": k2, "open": false, "len": float(a["z1"]) - float(a["z0"])})
	# 注水弁（キングストン弁・弾火薬庫注水弁・船底の栓）
	var cocks: Array = sim.get("sea_cocks", [])
	if cocks.is_empty():
		cocks = [{"s": L * 0.5, "side": 0, "name": "船底の栓（底板を外す）", "area": 0.5 if L < 40.0 else 0.8, "kind": "plug"}]
	for v in cocks:
		var vd: Dictionary = v
		var z := z_of(float(vd.get("s", L * 0.5)))
		var y := lowest_level_at(z)
		var hb := half_beam(z, y + 0.3)
		var x := float(vd.get("side", 0)) * clampf(hb * 0.55, 0.6, maxf(hb - 0.8, 0.6))
		var p := Vector3(x, y, z)
		valves.append({"z": z, "x": x, "y": y, "comp": comp_at(Vector3(x if x != 0.0 else 0.01, y, z)), "area": float(vd.get("area", 0.5)),
			"name": String(vd.get("name", "注水弁")), "kind": String(vd.get("kind", "kingston")), "p": p})
	# ポンプ
	var ps_ := float(sim.get("pump_s", L * 0.55))
	var pz := z_of(ps_)
	var py := lowest_level_at(pz)
	var phb := half_beam(pz, py + 0.3)
	pumps.append({"z": pz, "x": -clampf(phb * 0.5, 0.6, maxf(phb - 0.8, 0.6)), "y": py})
	# 舷梯（右舷中央）
	var lad: Dictionary = lay.get("ladder", {})
	var lz := z_of(float(lad.get("s", L * 0.55)))
	var lside := float(lad.get("side", 1.0))
	var ly := top_at(lz)
	ladder = {"z": lz, "side": lside, "y": ly, "hb": half_beam(lz, ly - 0.05), "run": maxf(4.0, ly * 0.9)}
	# 舵（操船位置）
	var hs := float(pilot.get("helm_s", L * 0.85))
	var hz := z_of(hs)
	helm = {"z": hz, "x": float(pilot.get("helm_x", 0.0)), "y": float(pilot.get("helm_y", top_at(hz)))}
	# 乗組員の歩く点（上甲板の空き）
	crew_points.clear()
	var obst := _deck_obstacles(top_m)
	var step := clampf(L / 14.0, 3.0, 14.0)
	var zz := -L * 0.5 + step
	while zz < L * 0.5 - step * 0.5:
		var hb := half_beam(zz, top_at(zz) - 0.05) - 1.2
		for xf in [-0.6, 0.0, 0.6]:
			var p := Vector3(float(xf) * hb, top_at(zz) + 0.2, zz)
			if hb < 0.8:
				continue
			var ok := true
			for o in obst:
				if p.z > float(o["z0"]) - 0.8 and p.z < float(o["z1"]) + 0.8 and p.x > float(o["x0"]) - 0.8 and p.x < float(o["x1"]) + 0.8:
					ok = false
					break
			for st in stairs:
				if bool(st.get("hatch", false)) and _rect_hit({"z0": p.z - 0.5, "z1": p.z + 0.5, "x0": p.x - 0.5, "x1": p.x + 0.5}, st):
					ok = false
			if ok:
				crew_points.append(p)
		zz += step


func _door_blocked(y: float, z: float, x: float) -> bool:
	for st in stairs:
		if absf(float(st["y0"]) - y) < 0.3 or absf(float(st["y1"]) - y) < 0.3:
			if z > float(st["z0"]) - 1.0 and z < float(st["z1"]) + 1.0 and x > float(st["x0"]) - 1.0 and x < float(st["x1"]) + 1.0:
				return true
	return false


## 予備浮力（乾舷甲板まで沈むのに要る水量 m³）
func reserve_volume() -> float:
	return L * B * sim_fb * 0.78


func waterplane_area() -> float:
	return L * B * float(sim.get("cw", 0.74 if steel else 0.8))


## 横メタセンタ高さ GM（m）
func gm() -> float:
	if sim.has("gm"):
		return float(sim["gm"])
	if steel:
		return clampf(B * 0.06, 0.8, 3.0)
	return clampf(B * 0.08, 0.35, 1.2)


func gm_long() -> float:
	return L * L / (12.0 * maxf(T, 0.5)) * 0.7


## 船体の強さ（爆発の被害 → 破孔の大きさの換算）
func strength() -> float:
	if sim.has("strength"):
		return float(sim["strength"])
	if steel:
		return clampf(disp / 15.0, 500.0, 2600.0)
	return clampf(100.0 + L * 4.0, 120.0, 420.0)


func value() -> int:
	return int(sim.get("value", clampf(disp / 8.0, 60.0, 6000.0)))

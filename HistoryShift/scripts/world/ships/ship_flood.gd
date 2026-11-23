class_name ShipFlood
extends RefCounted
## 浸水・復原性・火災のシミュレーション（ゲーム用の簡略モデル）。
## - 区画（水密隔壁で区切る。軍艦は左右にも分ける）ごとの水量。区画の床（船底）から乾舷甲板まで
## - 破孔からの流入 q = Cd·A·√(2g·Δh)（外の海面と区画内の水位の差。船が沈み・傾くと深くなる）
## - 水密扉・甲板の開口・隔壁の上端を通じた区画間の流れ、乾舷甲板が水に浸かると上からの流入
## - ポンプ（缶室が浸水すると停止）、注水弁（キングストン弁・弾火薬庫注水弁・注排水弁）
## - 沈下 δ = Σm / (ρ·Aw)、トリム θ = -Σm·z / (Δ·GM_L)、横傾斜は GZ(φ) = GM·sinφ·(1-(φ/φv)²) と傾斜モーメントの釣り合い
##   （自由水影響で GM が減る）。釣り合いが無ければ転覆。予備浮力を失えば沈没。
## - 火災: 船の長さ方向の区域ごと。木造船は延焼して舷側が焼け抜け（水線の破孔）、空母の格納庫は誘爆、
##   火が弾火薬庫に届くと時限で爆発（注水すれば防げる）

const G := 9.81
const CD := 0.62
const RHO := 1.025

var sd: ShipData
var n := 0
var vol := PackedFloat32Array()
var cap := PackedFloat32Array()
var area := PackedFloat32Array()
var keel := PackedFloat32Array()
var top := PackedFloat32Array()
var cpos: Array = []                 # 区画の中心 Vector3（水位の高さは別）
var breaches: Array = []             # {c, p: Vector3, a, kind}
var links: Array = []                # {a, b, y, p: Vector3, area, open, door}
var valve_open := PackedByteArray()
var pump_on := true
var pump_rate := 0.3
var pump_kind := "steam"
var power := true
var crew_aboard := true
var mag: Array = []                  # {comps:Array, name, state("ok"/"flooded"/"exploded"), heat}
var boilers_blown := {}
# 火災
var zones := 0
var zone_z := PackedFloat32Array()
var fire := PackedFloat32Array()
var integ := PackedFloat32Array()
var burnt := PackedByteArray()
var fire_kind := "wood"
var _ord_t := PackedFloat32Array()
var fire_y := 0.0
var fire_z0 := -INF
var fire_z1 := INF
var events: Array = []               # step() の出来事（Ship が演出する）
var total_in := 0.0


func _init(p_sd: ShipData) -> void:
	sd = p_sd
	n = sd.comps.size()
	vol.resize(n)
	cap.resize(n)
	area.resize(n)
	keel.resize(n)
	top.resize(n)
	for i in n:
		var c: Dictionary = sd.comps[i]
		vol[i] = 0.0
		cap[i] = float(c["vol"])
		area[i] = float(c["area"])
		keel[i] = float(c["keel"])
		top[i] = float(c["top"])
		cpos.append(Vector3(float(c["cx"]), 0.0, float(c["cz"])))
	# 区画間のつながり: 扉（甲板の高さ）と、隔壁の上端（扉の無い甲板の開口）
	for di in sd.doors.size():
		var d: Dictionary = sd.doors[di]
		links.append({"a": int(d["a"]), "b": int(d["b"]), "y": float(d["y"]), "p": Vector3(float(d["x"]), float(d["y"]), float(d["z"])),
			"area": 1.9, "open": bool(d.get("open", false)), "door": di})
	for i in n:
		for j in range(i + 1, n):
			var a: Dictionary = sd.comps[i]
			var b: Dictionary = sd.comps[j]
			var touch_z := absf(float(a["z1"]) - float(b["z0"])) < 0.05 and (int(a["side"]) == int(b["side"]) or int(a["side"]) == 0 or int(b["side"]) == 0)
			var touch_x := int(a["side"]) == -1 and int(b["side"]) == 1 and absf(float(a["z0"]) - float(b["z0"])) < 0.05
			if touch_z:
				# 隔壁の上端（乾舷甲板の直下）を越える
				links.append({"a": i, "b": j, "y": top[i] - 0.15, "p": Vector3(0, top[i] - 0.15, float(a["z1"])), "area": 3.0, "open": true, "door": -1})
			if touch_x:
				# 左右は喫水線より上で開いている（中心線隔壁は下の甲板だけ）
				links.append({"a": i, "b": j, "y": 0.4, "p": Vector3(0, 0.4, float(a["cz"])), "area": 6.0, "open": true, "door": -1})
	valve_open.resize(sd.valves.size())
	valve_open.fill(0)
	pump_rate = float(sd.sim.get("pump", 0.6 if sd.steel else 0.04))
	pump_kind = String(sd.sim.get("power", "steam" if sd.steel else "manual"))
	pump_on = true
	# 弾火薬庫
	var names := {}
	for i in n:
		var mn := String((sd.comps[i] as Dictionary).get("magazine", ""))
		if mn == "":
			continue
		if not names.has(mn):
			names[mn] = mag.size()
			mag.append({"comps": [], "name": mn, "state": "ok", "heat": 0.0})
		(mag[int(names[mn])]["comps"] as Array).append(i)
	# 火災区域
	fire_kind = String(sd.sim.get("fire", "wood" if not sd.steel else "steel"))
	var fz: Array = sd.sim.get("fire_zone", [])
	var z0 := -sd.L * 0.5
	var z1 := sd.L * 0.5
	if fz.size() >= 2:
		z0 = sd.z_of(float(fz[0]))
		z1 = sd.z_of(float(fz[1]))
	fire_z0 = z0
	fire_z1 = z1
	fire_y = float(sd.sim.get("fire_y", sd.top_m - 1.0))
	zones = clampi(int((z1 - z0) / 10.0), 3, 14)
	zone_z.resize(zones)
	fire.resize(zones)
	integ.resize(zones)
	burnt.resize(zones)
	_ord_t.resize(zones)
	for k in zones:
		zone_z[k] = lerpf(z0, z1, (k + 0.5) / zones)
		fire[k] = 0.0
		integ[k] = 1.0
		burnt[k] = 0
		_ord_t[k] = randf_range(10.0, 25.0)


func level_local(i: int) -> float:
	return keel[i] + vol[i] / maxf(area[i], 0.1)


func fill(i: int) -> float:
	return vol[i] / maxf(cap[i], 0.1)


func water_total() -> float:
	var s := 0.0
	for i in n:
		s += vol[i]
	return s


func flood_ratio() -> float:
	return water_total() / maxf(sd.reserve_volume(), 1.0)


## 破孔を開ける（c は区画、p は船ローカル）
func add_breach(p: Vector3, a: float, kind := "hole") -> void:
	if a <= 0.0:
		return
	var c := sd.comp_at(p)
	# 近い破孔はまとめる
	for b in breaches:
		if int(b["c"]) == c and (b["p"] as Vector3).distance_to(p) < 2.5:
			b["a"] = float(b["a"]) + a
			return
	breaches.append({"c": c, "p": p, "a": a, "kind": kind})


func has_activity() -> bool:
	if not breaches.is_empty() or burning() > 0:
		return true
	for v in valve_open:
		if v == 1:
			return true
	return false


## 区画 c とその隣の間の隔壁を壊す（弾火薬庫・缶の爆発）: 船底の高さで大きくつながる
func blow_bulkheads(c: int, a: float) -> void:
	var cc: Dictionary = sd.comps[c]
	for j in n:
		if j == c:
			continue
		var o: Dictionary = sd.comps[j]
		var touch := absf(float(o["z1"]) - float(cc["z0"])) < 0.05 or absf(float(o["z0"]) - float(cc["z1"])) < 0.05 \
			or (absf(float(o["z0"]) - float(cc["z0"])) < 0.05 and int(o["side"]) == -int(cc["side"]) and int(cc["side"]) != 0)
		if not touch:
			continue
		var zb := float(cc["z0"]) if absf(float(o["z1"]) - float(cc["z0"])) < 0.05 else float(cc["z1"])
		links.append({"a": c, "b": j, "y": keel[c] + 0.3, "p": Vector3(0, keel[c] + 0.3, zb), "area": maxf(a, 2.0), "open": true, "door": -1})


func set_valve(i: int, open: bool) -> void:
	if i < 0 or i >= valve_open.size():
		return
	valve_open[i] = 1 if open else 0


func set_door(di: int, open: bool) -> void:
	for l in links:
		if int(l["door"]) == di:
			l["open"] = open


func ignite_at(z: float, amount := 0.4) -> void:
	if zones == 0:
		return
	if z < fire_z0 - 5.0 or z > fire_z1 + 5.0:
		if fire_kind == "hangar":
			return
	var k := clampi(int((z - fire_z0) / maxf(fire_z1 - fire_z0, 1.0) * zones), 0, zones - 1)
	fire[k] = maxf(fire[k], amount)


func burning() -> int:
	var c := 0
	for k in zones:
		if fire[k] > 0.05:
			c += 1
	return c


func magazine_comp(i: int) -> int:
	for m in mag.size():
		if i in (mag[m]["comps"] as Array):
			return m
	return -1


# ================================================================ 1 ステップ
## xf: 船の現在の Transform（ワールド）、sea_y: 海面の高さ
func step(dt: float, xf: Transform3D, sea_y: float) -> void:
	events.clear()
	if n == 0:
		return
	var lw := PackedFloat32Array()
	lw.resize(n)
	for i in n:
		var p: Vector3 = cpos[i]
		lw[i] = (xf * Vector3(p.x, level_local(i), p.z)).y
	var dv := PackedFloat32Array()
	dv.resize(n)
	dv.fill(0.0)
	# 破孔・開いた注水弁
	var holes: Array = breaches.duplicate()
	for vi in valve_open.size():
		if valve_open[vi] == 1:
			var v: Dictionary = sd.valves[vi]
			var vp: Vector3 = v["p"]
			holes.append({"c": int(v["comp"]), "p": Vector3(vp.x, keel[int(v["comp"])] + 0.2, vp.z), "a": float(v["area"])})
	for b in holes:
		var c := int(b["c"])
		var bp: Vector3 = b["p"]
		var bwy := (xf * bp).y
		var h_out := maxf(0.0, sea_y - bwy)
		var h_in := maxf(0.0, lw[c] - bwy)
		var dh := h_out - h_in
		if absf(dh) < 0.001:
			continue
		var q := CD * float(b["a"]) * signf(dh) * sqrt(2.0 * G * absf(dh)) * dt
		var lim := (sea_y - lw[c]) * area[c]
		if q > 0.0:
			q = minf(q, maxf(lim, 0.0))
		else:
			q = maxf(q, minf(lim, 0.0))
		dv[c] += q
	# 乾舷甲板が海面下: 上から流れ込む（ハッチ・通風口・開口）
	for i in n:
		var p: Vector3 = cpos[i]
		var dy := (xf * Vector3(p.x, top[i], p.z)).y
		if dy < sea_y:
			var depth := minf(sea_y - dy, 4.0)
			var q2 := CD * (3.0 + area[i] * 0.03) * sqrt(2.0 * G * depth) * dt
			dv[i] += minf(q2, (sea_y - lw[i]) * area[i])
	# 区画間（扉・開口・隔壁の上端）
	for l in links:
		if not bool(l["open"]):
			continue
		var a := int(l["a"])
		var b := int(l["b"])
		var sill := (xf * (l["p"] as Vector3)).y
		var ha := maxf(0.0, lw[a] - sill)
		var hb := maxf(0.0, lw[b] - sill)
		var dh := ha - hb
		if absf(dh) < 0.002:
			continue
		var q := CD * float(l["area"]) * sqrt(2.0 * G * absf(dh)) * dt
		# 水位をそろえる以上は流さない
		var eq := absf(lw[a] - lw[b]) * area[a] * area[b] / (area[a] + area[b])
		q = minf(q, eq * 0.5)
		if dh > 0.0:
			q = minf(q, vol[a] + dv[a])
			dv[a] -= q
			dv[b] += q
		else:
			q = minf(q, vol[b] + dv[b])
			dv[b] -= q
			dv[a] += q
	# 動力（缶室が浸水すると止まる）
	var was := power
	power = true
	if pump_kind != "manual":
		for i in n:
			if bool((sd.comps[i] as Dictionary).get("boiler", false)) and fill(i) > 0.5:
				power = false
	else:
		power = crew_aboard
	if was and not power and pump_kind != "manual":
		events.append({"type": "power_lost"})
	# ポンプ: いちばん水の多い区画から汲み出す
	if pump_on and power and pump_rate > 0.0:
		var best := -1
		var bv := 0.5
		for i in n:
			if vol[i] + dv[i] > bv:
				bv = vol[i] + dv[i]
				best = i
		if best >= 0:
			dv[best] -= minf(pump_rate * dt, vol[best] + dv[best])
	# 反映（満水を超えた分は隣へあふれる）
	for i in n:
		var nv := vol[i] + dv[i]
		if dv[i] > 0.0:
			total_in += dv[i]
		if nv > cap[i]:
			var over := nv - cap[i]
			nv = cap[i]
			var nb := _neighbor_lowest(i)
			if nb >= 0:
				vol[nb] = minf(cap[nb], vol[nb] + over)
		vol[i] = maxf(0.0, nv)
	# 缶室の水蒸気爆発（熱い缶に海水）
	for i in n:
		if bool((sd.comps[i] as Dictionary).get("boiler", false)) and not boilers_blown.has(i) and fill(i) > 0.45 and was:
			boilers_blown[i] = true
			if randf() < 0.35:
				events.append({"type": "boiler", "c": i})
	# 弾火薬庫: 注水で安全化
	for m in mag:
		if String(m["state"]) != "ok":
			continue
		var f := 0.0
		for c in m["comps"]:
			f = maxf(f, fill(int(c)))
		if f > 0.55:
			m["state"] = "flooded"
			events.append({"type": "magazine_safe", "name": m["name"]})
	_fire_step(dt)


func _neighbor_lowest(i: int) -> int:
	var best := -1
	var bf := 2.0
	for l in links:
		var o := -1
		if int(l["a"]) == i:
			o = int(l["b"])
		elif int(l["b"]) == i:
			o = int(l["a"])
		if o < 0:
			continue
		if fill(o) < bf and fill(o) < 0.999:
			bf = fill(o)
			best = o
	return best


func _fire_step(dt: float) -> void:
	if zones == 0:
		return
	var spread := 0.03 if fire_kind == "wood" else (0.05 if fire_kind == "hangar" else 0.0015)
	var grow := 0.05 if fire_kind != "steel" else 0.02
	for k in zones:
		var f := fire[k]
		if f <= 0.0:
			continue
		# 水に浸かった区域は消える
		var c := sd.comp_at(Vector3(0, fire_y, zone_z[k]))
		if level_local(c) > fire_y + 0.3:
			fire[k] = 0.0
			continue
		if fire_kind != "wood":
			# 鋼船の火災は燃えるものが尽きると消える（格納庫は燃料・弾薬が多い）
			integ[k] = maxf(0.0, integ[k] - dt * (0.004 if fire_kind == "steel" else 0.0025) * f)
			f = f + dt * grow * (1.0 - f) * integ[k] - dt * 0.004
			if integ[k] < 0.15:
				f -= dt * 0.05
		else:
			f = minf(1.0, f + dt * grow * (0.4 + f))
		fire[k] = maxf(f, 0.0)
		for nb in [k - 1, k + 1]:
			if nb >= 0 and nb < zones and fire[nb] <= 0.0 and integ[nb] > 0.3 and (fire_kind != "steel" or f > 0.6) and randf() < spread * f * dt * (0.4 if crew_aboard else 1.0):
				fire[nb] = 0.15
		if fire_kind == "wood":
			integ[k] = maxf(0.0, integ[k] - dt * 0.0065 * f)
			if integ[k] < 0.42 and burnt[k] == 0:
				burnt[k] = 1
				events.append({"type": "burn_through", "z": zone_z[k], "a": 0.6 + sd.B * 0.06})
			elif integ[k] < 0.15 and burnt[k] == 1:
				burnt[k] = 2
				events.append({"type": "burn_through", "z": zone_z[k], "a": 1.2 + sd.B * 0.12})
		elif fire_kind == "hangar" and f > 0.5:
			_ord_t[k] -= dt
			if _ord_t[k] <= 0.0:
				_ord_t[k] = randf_range(14.0, 34.0)
				events.append({"type": "ordnance", "z": zone_z[k]})
	# 火が弾火薬庫へ
	for m in mag:
		if String(m["state"]) != "ok":
			continue
		var hot := 0.0
		for c in m["comps"]:
			var cp: Dictionary = sd.comps[int(c)]
			for k in zones:
				if zone_z[k] > float(cp["z0"]) - 8.0 and zone_z[k] < float(cp["z1"]) + 8.0:
					hot = maxf(hot, fire[k])
		if hot > 0.5:
			var before := float(m["heat"])
			m["heat"] = before + dt
			if before == 0.0:
				events.append({"type": "magazine_warn", "name": m["name"], "t": float(sd.sim.get("cookoff", 50.0))})
			if float(m["heat"]) > float(sd.sim.get("cookoff", 50.0)):
				events.append({"type": "magazine", "m": mag.find(m)})
		else:
			m["heat"] = maxf(0.0, float(m["heat"]) - dt * 0.5)


# ================================================================ 釣り合い
## 浸水から沈下・トリム・横傾斜の目標値。返り値 {sink, trim, heel, capsize, gm}
func attitude() -> Dictionary:
	var aw := sd.waterplane_area()
	var m := 0.0
	var mz := 0.0
	var mx := 0.0
	var fs := 0.0
	for i in n:
		var w := vol[i] * RHO
		if w <= 0.0:
			continue
		var c: Dictionary = sd.comps[i]
		m += w
		mz += w * float(c["cz"])
		var cx := float(c["cx"])
		if int(c["side"]) != 0:
			cx = float(c["cx"]) * 1.15
		mx += w * cx
		var f := fill(i)
		if f > 0.03 and f < 0.97:
			var wd := float(c["w"])
			fs += (float(c["z1"]) - float(c["z0"])) * wd * wd * wd / 12.0
	var disp := sd.disp + m
	var sink := m / (RHO * aw)
	var trim := -mz / (disp * sd.gm_long())
	var gm0 := sd.gm()
	var gm := gm0 - fs * RHO / disp * float(sd.sim.get("fs_k", 0.3))
	gm = maxf(gm, gm0 * 0.12)
	# 甲板の縁が浸かると復原力が落ちる
	var res := clampf(1.0 - sink / maxf(sd.sim_fb, 0.3), 0.0, 1.0)
	gm *= 0.35 + 0.65 * sqrt(res)
	var vanish := deg_to_rad(float(sd.sim.get("vanish", 65.0 if sd.steel else 55.0)))
	var heel := 0.0
	var capsize := false
	var mh := absf(mx)
	if mh > 0.01:
		var found := false
		var prev_f := -mh
		var prev_ph := 0.0
		for k in 60:
			var ph := vanish * float(k + 1) / 60.0
			var gz := gm * sin(ph) * (1.0 - pow(ph / vanish, 2.0))
			var f := disp * gz - mh * cos(ph)
			if f >= 0.0:
				# 前の刻みとの間を線形補間
				var t := clampf(-prev_f / maxf(f - prev_f, 0.0001), 0.0, 1.0)
				heel = lerpf(prev_ph, ph, t) * signf(mx)
				found = true
				break
			prev_f = f
			prev_ph = ph
		if not found:
			capsize = true
			heel = vanish * signf(mx)
	return {"sink": sink, "trim": trim, "heel": heel, "capsize": capsize, "gm": gm, "mass": m}

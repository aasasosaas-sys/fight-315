class_name ShipInterior
extends RefCounted
## 船内（プレイヤーが近く・乗船中だけ作る）: 船体内の甲板・階段・水密隔壁と扉・部屋の壁・小道具・灯り・注水弁・ポンプ。
## step() を毎フレーム呼ぶと少しずつ組み立て、終わると true を返す（ヒッチを避ける）。

const LAMP := {"lantern": Color(1.0, 0.62, 0.3), "gas": Color(1.0, 0.82, 0.55), "electric": Color(1.0, 0.92, 0.78), "battle": Color(1.0, 0.45, 0.38)}
const MAX_LIGHTS := 18

var sd: ShipData
var sk := ShipKit.new()
var root: Node3D               # 見た目（船の可動ボディの子）
var interact: Array = []       # {kind: door/valve/pump/ladder_down, p: Vector3(local), idx, node, label}
var door_nodes := {}           # door idx -> {panel: MeshInstance3D, shape: CollisionShape3D, closed_xf, open_xf}
var valve_nodes := {}          # valve idx -> MeshInstance3D（ハンドル）
var lights: Array = []
var _stage := 0
var _room_i := 0
var _lights_n := 0
var _seed := 1


func _init(p_sd: ShipData, p_root: Node3D, seed: int) -> void:
	sd = p_sd
	root = p_root
	_seed = seed


func step() -> bool:
	match _stage:
		0:
			_decks()
			_stage = 1
		1:
			_stairs()
			_bulkheads()
			_stage = 2
		2:
			var n := 0
			while _room_i < sd.rooms.size() and n < 8:
				_room(sd.rooms[_room_i], _room_i)
				_room_i += 1
				n += 1
			if _room_i >= sd.rooms.size():
				_stage = 3
		3:
			_fittings()
			_corridor_lights()
			_stage = 4
		4:
			if not sk.kit.is_empty():
				var mi := sk.kit.commit("Interior", false)
				root.add_child(mi)
			_stage = 5
			return true
	return _stage >= 5


# ------------------------------------------------------------ 甲板
func _holes_for(y: float) -> Array:
	var out: Array = []
	for st in sd.stairs:
		if bool(st.get("hatch", false)) and absf(float(st["y1"]) - y) < 0.3:
			out.append({"z0": float(st["z0"]) - 0.1, "z1": float(st["z1"]) + 0.1, "x0": float(st["x0"]) - 0.1, "x1": float(st["x1"]) + 0.1})
	return out


func _decks() -> void:
	var dc := sd.c("deck_in", Color(0.78, 0.68, 0.55) if not sd.steel else Color(0.62, 0.55, 0.48))
	if sd.steel and sd.year >= 1930:
		dc = sd.c("deck_in", Color(0.55, 0.42, 0.35))   # リノリウム
	for y in sd.hull_levels:
		var yy := float(y)
		if absf(yy - sd.top_m) < 0.3:
			continue
		var e := sd.z_ends(yy + 0.2)
		var s := sd
		var th := 0.14 if sd.steel else 0.2
		var hb_fn := func(z: float) -> float: return minf(s.half_beam(z, yy + 0.05), s.half_beam(z, yy + 0.6)) - th
		var y_fn := func(_z: float) -> float: return yy
		sk.floor_hull("wood" if not sd.steel or sd.year < 1925 else "concrete", e.x + 0.3, e.y - 0.3, hb_fn, y_fn, _holes_for(yy), dc, 2.0, 0.25, true, 0.0)
		# ハッチの縁の手すり
		for h in _holes_for(yy):
			var hd: Dictionary = h
			sk.rail_rect(yy, float(hd["z0"]), float(hd["z1"]), float(hd["x0"]), float(hd["x1"]), 0.95, Color(0.35, 0.35, 0.37), false, ["z1"])


func _stairs() -> void:
	for st in sd.stairs:
		if bool(st.get("hatch", false)):
			sk.stair("metal" if sd.steel else "wood", st, Color(0.58, 0.58, 0.6) if sd.steel else Color(0.6, 0.45, 0.3))


## 水密隔壁（横）と、左右分割の中心線隔壁。扉の位置は開口にして、扉板は別ノード
func _bulkheads() -> void:
	if sd.comps.size() < 2:
		return
	var wc := Color(0.86, 0.85, 0.8) if sd.steel else Color(0.6, 0.47, 0.33)
	var mat := "plaster" if sd.steel else "wood"
	var levels: Array = []
	for y in sd.hull_levels:
		if float(y) < sd.sim_fb - 0.5:
			levels.append(float(y))
	for li in levels.size():
		var yy: float = levels[li]
		var ceil := sd.top_m
		for y2 in sd.hull_levels:
			if float(y2) > yy + 0.5:
				ceil = minf(ceil, float(y2))
		var hgt := ceil - yy - 0.22
		for bs in sd.bulkheads:
			var z := sd.z_of(float(bs))
			var hb := sd.half_beam(z, yy + 0.3) - 0.12
			if hb < 0.8:
				continue
			var ops: Array = []
			for d in sd.doors:
				var dd: Dictionary = d
				if String(dd["axis"]) == "z" and absf(float(dd["y"]) - yy) < 0.2 and absf(float(dd["z"]) - z) < 0.3:
					var u := float(dd["x"]) + hb
					ops.append([u - 0.55, u + 0.55, 1.95])
			# 階段が隔壁にかかる所は開ける
			for st in sd.stairs:
				if absf(float(st["y0"]) - yy) < 0.3 and z > float(st["z0"]) - 0.2 and z < float(st["z1"]) + 0.2:
					ops.append([float(st["x0"]) + hb - 0.2, float(st["x1"]) + hb + 0.2, hgt])
			sk.wall(mat, Vector2(-hb, z), Vector2(hb, z), yy, hgt, wc, ops, 0.14)
		# 中心線の隔壁（左右分割で、喫水線より下の甲板）
		if bool(sd.sim.get("split", false)) and yy < 0.2:
			for cp in sd.comps:
				var cpd: Dictionary = cp
				if int(cpd["side"]) != -1:
					continue
				var za := float(cpd["z0"])
				var zb := float(cpd["z1"])
				var ops2: Array = []
				for d in sd.doors:
					var dd: Dictionary = d
					if String(dd["axis"]) == "x" and absf(float(dd["y"]) - yy) < 0.2 and float(dd["z"]) > za and float(dd["z"]) < zb:
						var u2 := float(dd["z"]) - za
						ops2.append([u2 - 0.55, u2 + 0.55, 1.95])
				for st in sd.stairs:
					if absf(float(st["y0"]) - yy) < 0.3 and float(st["x0"]) < 0.2 and float(st["x1"]) > -0.2:
						ops2.append([float(st["z0"]) - za - 0.2, float(st["z1"]) - za + 0.2, hgt])
				sk.wall(mat, Vector2(0, za), Vector2(0, zb), yy, hgt, wc, ops2, 0.14)


# ------------------------------------------------------------ 部屋
func _room(rm: Dictionary, idx: int) -> void:
	var y := float(rm["y"])
	var z0 := float(rm["z0"])
	var z1 := float(rm["z1"])
	var x0 := float(rm["x0"])
	var x1 := float(rm["x1"])
	var h := float(rm.get("h", 2.4))
	var enclosed := bool(rm.get("enclosed", false))
	var region := String(rm.get("region", "hull"))
	var on_weather := absf(y - sd.top_m) < 0.3 and region == "hull"
	var wc := sd.c("wall_in", Color(0.92, 0.9, 0.84) if sd.steel else Color(0.72, 0.56, 0.38))
	var words := String(rm.get("words", ""))
	if words.find("art deco") >= 0 or words.find("panel") >= 0 or words.find("carved") >= 0:
		wc = Color(0.72, 0.52, 0.34)
	var mat := "plaster" if sd.steel else "wood"
	# 扉: 中心線（通路）側。中心の部屋は後ろ側
	var door := {}
	if enclosed:
		var mx := (x0 + x1) * 0.5
		var side := ""
		var u := 0.0
		if absf(mx) > 0.8 and (x1 - x0) < 0.7 * sd.B:
			side = "x0" if mx > 0.0 else "x1"
			u = (z0 + z1) * 0.5
		else:
			side = "z1" if (z0 + z1) * 0.5 < 0.0 else "z0"
			u = mx
		door = {"side": side, "u": u, "w": 1.0, "h": minf(2.05, h - 0.1)}
		var dr := {"z0": 0.0, "z1": 0.0, "x0": 0.0, "x1": 0.0}
		match side:
			"x0": dr = {"z0": u - 0.7, "z1": u + 0.7, "x0": x0 - 0.2, "x1": x0 + 1.2}
			"x1": dr = {"z0": u - 0.7, "z1": u + 0.7, "x0": x1 - 1.2, "x1": x1 + 0.2}
			"z0": dr = {"z0": z0 - 0.2, "z1": z0 + 1.2, "x0": u - 0.7, "x1": u + 0.7}
			_: dr = {"z0": z1 - 1.2, "z1": z1 + 0.2, "x0": u - 0.7, "x1": u + 0.7}
		rm["door"] = dr
		var wall_h := h
		if on_weather or region == "top":
			wall_h = minf(h, 2.6)
		sk.room_walls(mat, z0, z1, x0, x1, y, wall_h, wc, [door], 0.12)
		# 屋外に立つ部屋（甲板室）は屋根を付ける
		if on_weather or region == "top":
			sk.box(sd.hull_mat if sd.steel else "wood", Vector3((x0 + x1) * 0.5, y + wall_h + 0.08, (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.3, 0.16, z1 - z0 + 0.3), sd.c("super", wc).darkened(0.05), true)
			# 窓
			var nw := maxi(1, int((z1 - z0) / 2.2))
			for k in nw:
				for xs: float in [x0 - 0.02, x1 + 0.02]:
					sk.box("glass" if sd.year >= 1890 else "flat", Vector3(float(xs), y + 1.5, lerpf(z0, z1, (k + 0.5) / nw)), Vector3(0.04, 0.6, 0.8), Color(0.15, 0.17, 0.2))
		# 名札（部屋名は HUD で出すので、扉の上に札だけ）
		var dp := Vector3(0, 0, 0)
		match side:
			"x0": dp = Vector3(x0 - 0.07, y + 2.25, u)
			"x1": dp = Vector3(x1 + 0.07, y + 2.25, u)
			"z0": dp = Vector3(u, y + 2.25, z0 - 0.07)
			_: dp = Vector3(u, y + 2.25, z1 + 0.07)
		if h > 2.4:
			sk.box("wood", dp, Vector3(0.5, 0.16, 0.5) if side.begins_with("x") else Vector3(0.5, 0.16, 0.04), Color(0.95, 0.92, 0.82))
	ShipProps.populate(sk, sd, rm, _seed + idx * 31)
	# 灯り（囲われた部屋を優先）
	if _lights_n < MAX_LIGHTS and (enclosed or (not on_weather and region != "top")):
		var lc: Color = LAMP.get(sd.lighting, LAMP["lantern"])
		if words.find("engine") >= 0 or words.find("boiler") >= 0 or words.find("magazine") >= 0 or words.find("機") >= 0 or words.find("罐") >= 0:
			if sd.lighting == "battle":
				lc = LAMP["battle"]
		var ly := y + minf(h, 3.2) - 0.35
		var lp := Vector3((x0 + x1) * 0.5, ly, (z0 + z1) * 0.5)
		_add_light(lp, lc, clampf(maxf(z1 - z0, x1 - x0) * 0.75, 4.0, 14.0), 1.1 if sd.lighting != "lantern" else 0.8)


func _add_light(p: Vector3, lc: Color, rng: float, energy: float) -> void:
	_lights_n += 1
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = lc
	l.omni_range = rng
	l.light_energy = energy
	l.shadow_enabled = false
	l.omni_attenuation = 1.2
	root.add_child(l)
	lights.append(l)
	# 灯具（ランタン・電球）
	if sd.lighting == "lantern":
		sk.box("emissive", p + Vector3(0, -0.2, 0), Vector3(0.22, 0.3, 0.22), lc)
		sk.box("wood", p + Vector3(0, 0.0, 0), Vector3(0.28, 0.05, 0.28), Color(0.2, 0.15, 0.1))
	else:
		sk.kit.sphere("emissive", Transform3D(Basis(), p + Vector3(0, 0.1, 0)), 0.13, 8, 5, lc)


func _corridor_lights() -> void:
	for y in sd.hull_levels:
		var yy := float(y)
		if absf(yy - sd.top_m) < 0.3:
			continue
		var ceil := sd.top_m
		for y2 in sd.hull_levels:
			if float(y2) > yy + 0.5:
				ceil = minf(ceil, float(y2))
		var e := sd.z_ends(yy + 0.3)
		var step := clampf((e.y - e.x) / 4.0, 8.0, 40.0)
		var z := e.x + step * 0.5
		while z < e.y and _lights_n < MAX_LIGHTS:
			if sd.half_beam(z, yy + 0.3) > 1.5:
				var lc: Color = LAMP.get(sd.lighting, LAMP["lantern"])
				_add_light(Vector3(0, ceil - 0.45, z), lc, clampf(step * 0.7, 5.0, 16.0), 0.7)
			z += step


# ------------------------------------------------------------ 扉・注水弁・ポンプ
func _fittings() -> void:
	var steel_c := Color(0.5, 0.52, 0.5)
	for i in sd.doors.size():
		var d: Dictionary = sd.doors[i]
		var p := Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
		var along_x := String(d["axis"]) == "z"    # 扉板は x 方向に広がる（横隔壁）
		var size := Vector3(1.1, 1.95, 0.12) if along_x else Vector3(0.12, 1.95, 1.1)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _door_mat()
		var closed := Transform3D(Basis(), p + Vector3(0, 0.98, 0))
		var opened := Transform3D(Basis(), p + Vector3(0, 0.98, 0) + (Vector3(1.05, 0, 0) if along_x else Vector3(0, 0, 1.05)))
		mi.transform = opened if bool(d.get("open", false)) else closed
		root.add_child(mi)
		# 取っ手（ドッグ）
		var dog := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.1, 0.4, 0.2) if along_x else Vector3(0.2, 0.4, 0.1)
		dog.mesh = bm2
		dog.material_override = Humanoid.mat(Color(0.85, 0.2, 0.15), 0.5)
		dog.position = Vector3(0.35, 0.1, 0.08) if along_x else Vector3(0.08, 0.1, 0.35)
		mi.add_child(dog)
		# 枠（色で水密扉とわかるように）
		sk.box("metal", p + Vector3(0, 2.0, 0), Vector3(1.4, 0.12, 0.2) if along_x else Vector3(0.2, 0.12, 1.4), Color(0.85, 0.75, 0.2))
		door_nodes[i] = {"panel": mi, "closed": closed, "opened": opened, "size": size}
		interact.append({"kind": "door", "p": p + Vector3(0, 1.0, 0), "idx": i})
	for i in sd.valves.size():
		var v: Dictionary = sd.valves[i]
		var p: Vector3 = v["p"]
		var kind := String(v.get("kind", "kingston"))
		var colr := Color(0.85, 0.15, 0.12) if kind == "magazine" else (Color(0.2, 0.55, 0.85) if kind == "counterflood" else Color(0.9, 0.75, 0.2))
		if kind == "plug":
			# 船底の栓・底板
			sk.box("wood", p + Vector3(0, 0.05, 0), Vector3(1.2, 0.1, 1.2), Color(0.45, 0.3, 0.2))
			sk.box("metal", p + Vector3(0, 0.12, 0), Vector3(0.3, 0.06, 0.3), Color(0.25, 0.25, 0.25))
		else:
			sk.rod("metal", p, p + Vector3(0, 0.9, 0), 0.08, steel_c, 6)
			sk.box("metal", p + Vector3(0, 0.1, 0), Vector3(0.6, 0.2, 0.6), steel_c.darkened(0.2))
			var wh := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.35
			cm.bottom_radius = 0.35
			cm.height = 0.06
			cm.radial_segments = 12
			wh.mesh = cm
			wh.material_override = Humanoid.mat(colr, 0.4, 0.3)
			wh.position = p + Vector3(0, 0.95, 0)
			root.add_child(wh)
			valve_nodes[i] = wh
		interact.append({"kind": "valve", "p": p + Vector3(0, 0.8, 0), "idx": i})
	for i in sd.pumps.size():
		var pm: Dictionary = sd.pumps[i]
		var p := Vector3(float(pm["x"]), float(pm["y"]), float(pm["z"]))
		if sd.steel:
			sk.box("metal", p + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 1.4), Color(0.25, 0.4, 0.3), true)
			sk.cyl("metal", p + Vector3(0, 1.2, 0), 0.3, 0.3, 0.4, 10, Color(0.7, 0.6, 0.3))
		else:
			sk.box("wood", p + Vector3(0, 0.6, 0), Vector3(0.6, 1.2, 0.6), Color(0.45, 0.32, 0.22), true)
			sk.rod("wood", p + Vector3(0, 1.2, 0), p + Vector3(0, 1.4, -1.0), 0.05, Color(0.55, 0.4, 0.25))
			for k in 3:
				sk.cyl("wood", p + Vector3(0.6 + k * 0.5, 0, 0.5), 0.2, 0.22, 0.4, 8, Color(0.55, 0.4, 0.25))
		interact.append({"kind": "pump", "p": p + Vector3(0, 1.0, 0), "idx": i})


static var _dmat: StandardMaterial3D


static func _door_mat() -> StandardMaterial3D:
	if _dmat == null:
		_dmat = Humanoid.mat(Color(0.48, 0.52, 0.5), 0.55, 0.4)
	return _dmat


## 扉の見た目とコリジョンを開閉に合わせる
func set_door(i: int, open: bool) -> void:
	if not door_nodes.has(i):
		return
	var dn: Dictionary = door_nodes[i]
	var mi: MeshInstance3D = dn["panel"]
	if is_instance_valid(mi):
		mi.transform = dn["opened"] if open else dn["closed"]
	var cs = dn.get("shape", null)
	if cs is CollisionShape3D and is_instance_valid(cs):
		(cs as CollisionShape3D).disabled = open

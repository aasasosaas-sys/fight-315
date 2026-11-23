class_name ShipYard
extends Node3D
## 港の大型船の管理（EraWorld の子。layouts.gd の港から place_port で作る）。
## - 時代ごとの船（data/ships）を実寸で配置: 浅い船は岸近く（桟橋つき）、喫水の深い船は沖に錨泊（小舟で渡る）
## - 爆発の通知（Destruction.blast_at → blast_all）を各船へ
## - 泳ぎ（海・浸水した区画）と息継ぎ、沈む船からの脱出、沖の船のまわりだけ遊べる範囲を広げる
## - 海面のマスク（船体の中に海面を描かない）、船の状態表示（HUD）
##
## 実寸と箱庭: 地形は 440m 四方（遊べる範囲 ±215m）、岸から境界まで 30〜40m しかない。
## 大和（263m）・赤城・加賀・氷川丸・三笠・サスケハナは実寸のまま境界の外の沖に錨泊させ、
## その船の周り（船体から 60m）にいる間だけ EraWorld.half_size を広げてプレイヤーが出られるようにする。

static var current: ShipYard

const ERA_SHIPS := {
	"asuka_nara": ["kentoshisen"],
	"heian": ["kentoshisen", "sosen"],
	"kamakura_muromachi": ["ming_junk"],
	"sengoku": ["atakebune", "sekibune", "ming_junk", "nanban_nau"],
	"edo": ["shuinsen", "kanrin_maru", "susquehanna"],
	"meiji_taisho": ["mikasa"],
	"showa": ["hikawa_maru", "yamato", "akagi", "kaga"],
}
const ZONE_PAD := 60.0
const BREATH := 30.0

var world: Node3D
var era_id := ""
var ships: Array = []
var launches: Array = []
var orig_half := 220.0
var breath := BREATH
var swimming := false
var _drown_t := 0.0
var _under_t := 0.0
var _sea_mat: ShaderMaterial
var _inner_mat: ShaderMaterial
var _hud: CanvasLayer
var _status: Label
var _prompt: Label
var _breath_bar: ProgressBar
var _tint: ColorRect
var _jetty_body: StaticBody3D
var placements: Array = []        # {id, inner(bool), xf}


# ================================================================ 配置（layouts.gd の港から）
static func place_port(w: Node3D, lm: Dictionary, era: String, shore_z: float) -> ShipYard:
	if not ERA_SHIPS.has(era):
		return null
	var yard: ShipYard = w.get_node_or_null("ShipYard")
	if yard == null:
		yard = ShipYard.new()
		yard.name = "ShipYard"
		yard.world = w
		yard.era_id = era
		w.add_child(yard)
	yard._place(lm, shore_z)
	return yard


func _place(lm: Dictionary, shore_z: float) -> void:
	var t = world.get("terrain")
	orig_half = float(world.get("half_size"))
	var lxf: Transform3D = lm["xf"]
	var wl := float(world.get("water_level"))
	var inner_x := -62.0
	var off: Array = []
	var ids: Array = ERA_SHIPS[era_id]
	var k := 0
	for sid in ids:
		var sd := ShipData.load_ship(String(sid))
		if sd == null:
			continue
		var placed := false
		# 岸近く（遊べる範囲の中）に置けるか
		if sd.T < 5.0:
			var cx := inner_x - sd.L * 0.5 - (sd.rake + 2.0)
			var z := shore_z + sd.B * 0.5 + 4.0
			while z < shore_z + 60.0:
				var xf := lxf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx, 0, z))
				xf.origin.y = wl
				if _clear(t, xf, sd, true):
					var s := _spawn(sd, xf, k)
					placements.append({"id": sd.id, "inner": true, "xf": xf})
					_jetty(t, lxf, s, shore_z)
					inner_x = cx - sd.L * 0.5 - 16.0
					placed = true
					break
				z += 1.0
		if not placed:
			off.append(sd)
		k += 1
	# 沖（境界の外）: 2 列に並べる（港の正面を中心に）
	var rows: Array = [[], []]
	var row_len := [0.0, 0.0]
	for sd in off:
		var r := 0 if row_len[0] <= row_len[1] else 1
		(rows[r] as Array).append(sd)
		row_len[r] = float(row_len[r]) + (sd as ShipData).L + 30.0
	var zrow := shore_z + 100.0
	for r in 2:
		var arr: Array = rows[r]
		if arr.is_empty():
			continue
		var maxb := 0.0
		for sd in arr:
			maxb = maxf(maxb, (sd as ShipData).B + (12.0 if (sd as ShipData).id == "susquehanna" else 0.0))
		var zc := zrow + maxb * 0.5
		var x := -float(row_len[r]) * 0.5
		for sd in arr:
			var sdd := sd as ShipData
			var cx := x + sdd.L * 0.5
			var xf := lxf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx, 0, zc))
			xf.origin.y = wl
			# 浅ければさらに沖へ
			var tries := 0
			while not _clear(t, xf, sdd, false) and tries < 30:
				zc += 4.0
				xf = lxf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx, 0, zc))
				xf.origin.y = wl
				tries += 1
			_spawn(sdd, xf, k)
			placements.append({"id": sdd.id, "inner": false, "xf": xf})
			x += sdd.L + 30.0
			k += 1
		zrow = zc + maxb * 0.5 + 50.0
	# 小舟（沖の船へ渡る）: 桟橋の先の西側
	var piers := 3
	for pi in piers:
		if launches.size() >= 3:
			break
		var px := -24.0 + pi * 24.0
		var half_w := 2.5 if era_id in ["jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku"] else 4.0
		var lp := lxf * Vector3(px - half_w - 1.5, 0, shore_z + 26.0)
		if t and float(t.height_at(lp.x, lp.z)) > -0.7:
			continue
		var b := ShipLaunch.create(era_id, 91 + pi)
		add_child(b)
		b.transform = Transform3D(lxf.basis * Basis(Vector3.UP, PI), Vector3(lp.x, -0.1, lp.z))
		launches.append(b)


## 船体の下が十分深いか（inner: 遊べる範囲に収まるか）
func _clear(t, xf: Transform3D, sd: ShipData, inner: bool) -> bool:
	var lim := orig_half - 6.0
	for p in [Vector3(0, 0, -sd.L * 0.5 - sd.rake), Vector3(0, 0, sd.L * 0.5), Vector3(sd.B * 0.5, 0, 0), Vector3(-sd.B * 0.5, 0, 0),
			Vector3(sd.B * 0.45, 0, -sd.L * 0.3), Vector3(-sd.B * 0.45, 0, -sd.L * 0.3), Vector3(sd.B * 0.45, 0, sd.L * 0.3), Vector3(-sd.B * 0.45, 0, sd.L * 0.3),
			Vector3(sd.B * 0.5 + 6.0, 0, sd.ladder.get("z", 0.0) + 4.0)]:
		var wp: Vector3 = xf * (p as Vector3)
		if inner and (absf(wp.x) > lim or absf(wp.z) > lim):
			return false
		if t and float(t.height_at(wp.x, wp.z)) > -(sd.T + 1.0):
			return false
	for o in ships:
		var os := o as Ship
		if os.anchor.origin.distance_to(xf.origin) < (os.sd.L + sd.L) * 0.5 + 10.0:
			return false
	return true


func _spawn(sd: ShipData, xf: Transform3D, k: int) -> Ship:
	var s := Ship.create(sd, xf, era_id, hash(era_id) + k * 101)
	s.landmark = "port"
	add_child(s)
	ships.append(s)
	return s


## 岸近くの船へ渡る桟橋（岸 → 舷梯の下）
func _jetty(t, lxf: Transform3D, s: Ship, shore_z: float) -> void:
	var sd := s.sd
	var lz := float(sd.ladder["z"])
	var side := float(sd.ladder["side"])
	var hb := float(sd.ladder.get("hb", sd.B * 0.5))
	var end := s.anchor * Vector3(side * (hb + 2.3), 0, lz + float(sd.ladder.get("run", 4.0)) + 0.6)
	# 岸側の始点: 舷梯の下から陸の方へ
	var to_land := (lxf.basis * Vector3(0, 0, -1)).normalized()
	var start := end
	for k in 80:
		var q := end + to_land * float(k)
		if t and float(t.height_at(q.x, q.z)) > 1.2:
			start = q
			break
	if start == end:
		return
	var deck_y := 1.25
	if _jetty_body == null:
		_jetty_body = StaticBody3D.new()
		_jetty_body.name = "Jetties"
		_jetty_body.collision_layer = Game.COLLISION_WORLD
		_jetty_body.collision_mask = 0
		add_child(_jetty_body)
	var kit := MeshKit.new()
	var d := end - start
	d.y = 0.0
	var ln := d.length()
	var ang := atan2(d.x, d.z)
	var mid := (start + end) * 0.5
	var bs := Basis(Vector3.UP, ang)
	var xf := Transform3D(bs, Vector3(mid.x, deck_y - 0.12, mid.z))
	kit.box("wood", xf, Vector3(2.4, 0.24, ln + 1.0), Color(0.78, 0.66, 0.5))
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.4, 0.3, ln + 1.0)
	cs.shape = bx
	cs.transform = xf
	_jetty_body.add_child(cs)
	var n := int(ln / 3.0)
	for i in n + 1:
		var p := start.lerp(end, float(i) / maxf(n, 1))
		for sx: float in [-1.1, 1.1]:
			var pp: Vector3 = p + bs * Vector3(float(sx), 0, 0)
			var gh := float(t.height_at(pp.x, pp.z)) if t else -3.0
			kit.cylinder("darkwood", Transform3D(Basis(), Vector3(pp.x, gh - 0.5, pp.z)), 0.16, 0.16, deck_y - gh + 0.5, 6, Color(0.5, 0.45, 0.4))
	var mi := kit.commit("Jetty_" + sd.id)
	add_child(mi)


# ================================================================ 爆発（Destruction.blast_at から）
static func blast_all(pos: Vector3, radius: float, damage: float, team := -1, fire_chance := 0.2) -> void:
	if current == null or not is_instance_valid(current) or not current.is_inside_tree():
		return
	for s in current.ships:
		var sh := s as Ship
		if not is_instance_valid(sh):
			continue
		if sh.xf_cur.origin.distance_to(pos) > sh.sd.L * 0.6 + radius + 10.0:
			continue
		sh.on_blast(pos, radius, damage, team, fire_chance)


# ================================================================ 本体
func _ready() -> void:
	current = self
	process_physics_priority = -50
	_sea_mat = null
	var sea := world.get_node_or_null("Sea") as MeshInstance3D if world else null
	if sea and sea.material_override is ShaderMaterial:
		_sea_mat = sea.material_override
	_build_hud()


func _exit_tree() -> void:
	if current == self:
		current = null
	if world and is_instance_valid(world):
		world.set("half_size", orig_half)


func inner_water_mat() -> ShaderMaterial:
	if _inner_mat == null:
		if _sea_mat:
			_inner_mat = _sea_mat.duplicate()
		else:
			_inner_mat = ShaderMaterial.new()
			_inner_mat.shader = WorldMaterials.shader("water")
		_inner_mat.set_shader_parameter("dry_n", 0)
		_inner_mat.set_shader_parameter("wave_amp", 0.05)
		_inner_mat.set_shader_parameter("foam_width", 0.5)
		_inner_mat.set_shader_parameter("clarity", 0.85)
	return _inner_mat


func _physics_process(dt: float) -> void:
	var pl := Game.player
	if pl == null or not is_instance_valid(pl):
		return
	_bounds(pl)
	_swim(pl, dt)


## 沖の船のまわりにいる間だけ遊べる範囲を広げる
func _bounds(pl: Node3D) -> void:
	var p := pl.global_position
	var ext := maxf(absf(p.x), absf(p.z))
	var hs := orig_half
	if ext > orig_half - 6.0:
		var in_zone := false
		for s in ships:
			var sh := s as Ship
			var lp: Vector3 = sh.xf_cur.affine_inverse() * p
			if absf(lp.x) < sh.sd.B * 0.5 + ZONE_PAD and absf(lp.z) < sh.sd.L * 0.5 + ZONE_PAD:
				in_zone = true
				break
		var cur := float(world.get("half_size"))
		if in_zone:
			hs = ext + 12.0
		elif bool(pl.call("in_vehicle")):
			hs = ext + 12.0
		else:
			# 船のまわりから外れて泳いでいく: その場を壁にする（少しずつ押し戻す）
			hs = maxf(orig_half, minf(cur, ext + 4.0) - 0.05)
	world.set("half_size", hs)


func _water_at(p: Vector3) -> float:
	for s in ships:
		var sh := s as Ship
		if sh.xf_cur.origin.distance_to(p) > sh.sd.L * 0.6 + 20.0:
			continue
		var wy := sh.water_y_at(p)
		if wy == INF:
			continue
		return wy
	var w = world
	if w and w.has_method("height_at"):
		if float(w.height_at(p.x, p.z)) < -0.3:
			return float(w.get("water_level"))
	return -INF


func _swim(pl: Node3D, dt: float) -> void:
	var player := pl as Player
	if player == null or player.dead or player.in_vehicle():
		swimming = false
		breath = minf(BREATH, breath + dt * 6.0)
		return
	var p := player.global_position
	var wy := _water_at(p)
	var depth := wy - p.y
	var was := swimming
	swimming = depth > 0.9
	if swimming:
		if not was:
			Effects.burst(get_tree(), Vector3(p.x, wy + 0.1, p.z), Vector3.UP, Color(0.9, 0.97, 1.0, 0.9), Color(0.7, 0.85, 1.0, 0.0), 22, 5.0, 0.7, 1.0, 0.8, false, 40)
			Sfx.play_at(get_tree(), Sfx.splash(), p, -2.0)
		var v := player.velocity
		var target := clampf((depth - 1.35) * 2.5, -2.0, 2.2)
		if Input.is_action_pressed("jump") and not Game.input_blocked:
			target = 2.4
		v.y = lerpf(v.y, target, 1.0 - exp(-dt * 4.0)) + 22.0 * dt
		var hv := Vector2(v.x, v.z)
		if hv.length() > 3.4:
			hv = hv.normalized() * 3.4
		v.x = hv.x
		v.z = hv.y
		player.velocity = v
		player.parachuting = false
	# 息
	var head_under := depth > 1.75
	if head_under:
		breath -= dt
		_under_t += dt
		if breath <= 0.0:
			_drown_t -= dt
			if _drown_t <= 0.0:
				_drown_t = 0.5
				player.take_hit(4.0, -1)
	else:
		breath = minf(BREATH, breath + dt * 8.0)
		_under_t = 0.0
	# 沈む船の中に閉じこめられたら、しばらくして海面へ出られる（いきなりは死なない）
	if head_under and _under_t > 5.0:
		for s in ships:
			var sh := s as Ship
			if sh.player_inside and sh.phase in ["plunge", "capsizing", "settling"]:
				var side := 1.0 if sh.player_local.x >= 0.0 else -1.0
				var out := sh.xf_cur * Vector3(side * (sh.sd.B * 0.5 + 6.0), 0.0, sh.player_local.z)
				player.teleport(Vector3(out.x, 0.2, out.z))
				_under_t = 0.0
				var hud = get_tree().get_first_node_in_group("hud")
				if hud and hud.has_method("toast"):
					hud.toast("沈む船から抜け出し、海面に浮かび上がった！", 3.0)
				break


# ================================================================ 表示
func _process(_dt: float) -> void:
	_update_mask()
	_update_hud()


func _update_mask() -> void:
	if _sea_mat == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var cp := cam.global_position if cam else Vector3.ZERO
	var sorted: Array = ships.duplicate()
	sorted.sort_custom(func(a, b): return (a as Ship).xf_cur.origin.distance_squared_to(cp) < (b as Ship).xf_cur.origin.distance_squared_to(cp))
	var arrs: Array = [PackedVector4Array(), PackedVector4Array(), PackedVector4Array(), PackedVector4Array(), PackedVector4Array(), PackedVector4Array()]
	var n := 0
	for s in sorted:
		if n >= 8:
			break
		var mp: Array = (s as Ship).mask_params()
		for i in 6:
			(arrs[i] as PackedVector4Array).append(mp[i])
		n += 1
	for i in 6:
		var a: PackedVector4Array = arrs[i]
		while a.size() < 8:
			a.append(Vector4.ZERO)
		arrs[i] = a
	_sea_mat.set_shader_parameter("dry_n", n)
	_sea_mat.set_shader_parameter("dry_o", arrs[0])
	_sea_mat.set_shader_parameter("dry_x", arrs[1])
	_sea_mat.set_shader_parameter("dry_z", arrs[2])
	_sea_mat.set_shader_parameter("dry_y", arrs[3])
	_sea_mat.set_shader_parameter("dry_p", arrs[4])
	_sea_mat.set_shader_parameter("dry_t", arrs[5])


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 6
	add_child(_hud)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(0.1, 0.35, 0.55, 0.38)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.visible = false
	_hud.add_child(_tint)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.position = Vector2(-1100, 130)
	_status.custom_minimum_size = Vector2(1076, 60)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_constant_override("outline_size", 7)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_status.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_status)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-400, -330)
	_prompt.custom_minimum_size = Vector2(800, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 26)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_prompt)
	_breath_bar = ProgressBar.new()
	_breath_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_breath_bar.position = Vector2(-150, -380)
	_breath_bar.custom_minimum_size = Vector2(300, 14)
	_breath_bar.max_value = BREATH
	_breath_bar.show_percentage = false
	_breath_bar.visible = false
	_breath_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_breath_bar)


func _update_hud() -> void:
	if _status == null:
		return
	var no_hud := get_tree().get_first_node_in_group("hud") == null
	var pl := Game.player
	var txt := ""
	var pr := ""
	if pl != null and is_instance_valid(pl) and not no_hud:
		var best: Ship = null
		var bd := 140.0
		for s in ships:
			var sh := s as Ship
			var d := sh.xf_cur.origin.distance_to((pl as Node3D).global_position) - sh.sd.L * 0.5
			if sh.player_aboard:
				d = -1.0
			if d < bd:
				bd = d
				best = sh
		if best:
			txt = best.status_text()
			if best.player_aboard:
				var lp := best.player_local
				for rm in best.sd.rooms:
					var r: Dictionary = rm
					if absf(float(r["y"]) - lp.y) < 1.2 and lp.z > float(r["z0"]) and lp.z < float(r["z1"]) and lp.x > float(r["x0"]) and lp.x < float(r["x1"]):
						txt += "\n" + String(r["name"]) + ("  [" + String(r["conf"]) + "]" if String(r["conf"]) != "" else "")
						break
			pr = best.prompt_text()
	_status.text = txt
	_prompt.text = pr
	_breath_bar.visible = breath < BREATH - 0.5 and not no_hud
	_breath_bar.value = breath
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var under := false
	if cam:
		var wy := _water_at(cam.global_position)
		under = cam.global_position.y < wy - 0.05
	_tint.visible = under

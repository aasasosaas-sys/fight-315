class_name Ship
extends Node3D
## 実寸の船（建物と同じく歩ける・壊せる・沈められる）。data/ships/<id>.json から ShipData → 外装/船内/浸水。
## - 外装（船体・上部構造・甲板・外の階段）は常に表示。船内はプレイヤーが近い・乗船中だけ作る（ストリーミング）
## - 被害: 弾（木造船は小さな漏水）・爆発（ShipYard.blast_all → on_blast）・砲弾の直撃・体当たり・火矢
## - 自沈: 注水弁（E）・水密扉を開けて浸水を広げる・弾火薬庫に爆薬（1905 年の三笠のように艦尾が吹き飛ぶ）
## - 沈下・トリム・横傾斜（ShipFlood.attitude）→ 転覆 → 沈没（海底に着底）。沈没で Game.chaos_event("sink", 名所, info)
## - 乗組員（町人と同じく倒れない）は浸水がひどくなると総員退船（短艇で岸へ）

signal sunk(ship: Ship)

const STREAM_IN := 70.0
const STREAM_OUT := 120.0

var sd: ShipData
var body: ShipBody
var anchor := Transform3D()
var era_id := ""
var landmark := "port"
var seed := 1
var flood: ShipFlood
var sink := 0.0
var trim := 0.0
var heel := 0.0
var plunge := 0.0
var plunge_v := 0.0
var phase := "afloat"           # afloat / capsizing / plunge / settling / wreck
var cause := "world"
var sunk_emitted := false
var abandon := false
var deep := false
var floor_y := -60.0
var nav_speed := 0.0
var nav_turn := 0.0
var helm_node: ShipHelm
var interior: ShipInterior
var int_root: Node3D
var int_ready := false
var int_shapes: Array = []
var crew: Array = []
var lifeboats: Array = []
var water_planes := {}
var fire_fx := {}
var hole_fx: Array = []
var player_near := false
var player_aboard := false
var player_inside := false
var player_local := Vector3.ZERO
var near_item: Dictionary = {}
var active := false
var capsize_mag_done := false
var _cap_rate := 0.0
var _sim_acc := 0.0
var _bob_t := 0.0
var _pending_ignite := 0.0
var _last_xf := Transform3D()
var xf_cur := Transform3D()     # 船の今の姿勢（ボディは物理ステップで追いつく）
var _crew_t := 0.0
var _foam_t := 0.0
var _settle_t := 0.0
var _toasts := {}
var _mag_warned := {}
var _wake_t := 0.0
var base_disp := 0.0
static var in_detonation := false


static func create(p_sd: ShipData, xf: Transform3D, p_era: String, p_seed: int) -> Ship:
	var s := Ship.new()
	s.sd = p_sd
	s.anchor = xf
	s.era_id = p_era
	s.seed = p_seed
	s.name = "Ship_" + p_sd.id
	s._build()
	return s


func _build() -> void:
	body = ShipBody.new()
	body.name = "Body"
	body.ship = self
	body.collision_layer = Game.COLLISION_WORLD
	body.collision_mask = 0
	body.sync_to_physics = true
	add_child(body)
	body.transform = anchor
	_last_xf = anchor
	xf_cur = anchor
	var sk := ShipKit.new()
	ShipExterior.build(sd, sk)
	var mi := sk.kit.commit("Hull", true)
	body.add_child(mi)
	for c in sk.cols:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c[1]
		cs.shape = bs
		cs.transform = c[0]
		body.add_child(cs)
	if sk.faces.size() >= 3:
		var cps := ConcavePolygonShape3D.new()
		cps.backface_collision = true
		cps.set_faces(sk.faces)
		var cs2 := CollisionShape3D.new()
		cs2.shape = cps
		cs2.name = "HullShell"
		body.add_child(cs2)
	flood = ShipFlood.new(sd)
	base_disp = sd.disp
	# 操船（小さめの船・または layout.pilot がある船）
	if bool(sd.pilot.get("enabled", sd.L <= 60.0)):
		helm_node = ShipHelm.new()
		helm_node.ship = self
		helm_node.name = "Helm"
		helm_node.position = Vector3(float(sd.helm["x"]), float(sd.helm["y"]), float(sd.helm["z"]))
		body.add_child(helm_node)


func _ready() -> void:
	add_to_group("ship")
	var w = Game.world
	var yard := get_parent() as ShipYard
	if yard != null and yard.world != null:
		w = yard.world
	# 海底: 地形の外（沖）は深い海として扱う（沈んだ船は見えなくなる深さまで沈む）
	var half := 220.0
	if w and "terrain" in w and w.terrain:
		half = float(w.terrain.half)
	var o := anchor.origin
	deep = absf(o.x) > half - 10.0 or absf(o.z) > half - 10.0
	floor_y = -(sd.T + sd.top_m + 30.0)
	if not deep and w and w.has_method("height_at"):
		var lo := INF
		for p in [Vector3(0, 0, -sd.L * 0.4), Vector3.ZERO, Vector3(0, 0, sd.L * 0.4)]:
			var wp: Vector3 = anchor * (p as Vector3)
			lo = minf(lo, float(w.height_at(wp.x, wp.z)))
		floor_y = lo


# ================================================================ 毎フレーム
func _physics_process(dt: float) -> void:
	_update_player()
	var busy := active or player_near or (helm_node != null and helm_node.driver != null) or phase != "afloat" or flood.has_activity()
	if not busy:
		return
	_pending_ignite = maxf(0.0, _pending_ignite - dt)
	# 浸水の計算（10 Hz）
	_sim_acc += dt
	while _sim_acc >= 0.1:
		_sim_acc -= 0.1
		if phase != "wreck":
			flood.crew_aboard = not abandon
			flood.step(0.1, xf_cur, 0.0)
			_handle_events()
	_attitude(dt)
	_pilot(dt)
	_apply_xf(dt)
	if player_aboard or player_near:
		_interaction()
	_crew_step(dt)
	if flood.water_total() > 0.5 or not flood.breaches.is_empty() or flood.burning() > 0:
		active = true


func _process(_dt: float) -> void:
	_stream()
	if int_ready:
		_update_water_planes()
	_update_fire_fx()


func _update_player() -> void:
	var pl := Game.player
	player_near = false
	player_aboard = false
	player_inside = false
	if pl == null or not is_instance_valid(pl):
		return
	var pp: Vector3 = (pl as Node3D).global_position
	var xf := xf_cur
	var lp := xf.affine_inverse() * pp
	player_local = lp
	var dz := maxf(absf(lp.z) - sd.L * 0.5, 0.0)
	var dx := maxf(absf(lp.x) - sd.B * 0.5, 0.0)
	var d := Vector2(dx, dz).length()
	player_near = d < STREAM_IN
	var hb := sd.half_beam(clampf(lp.z, -sd.L * 0.5, sd.L * 0.5), clampf(lp.y + 0.3, -sd.T + 0.1, sd.top_m + sd.bulwark))
	if absf(lp.x) < maxf(hb, 0.5) + 0.8 and lp.y > -sd.T - 1.0 and lp.y < sd.top_m + 60.0 and absf(lp.z) < sd.L * 0.5 + 6.0:
		player_aboard = true
		player_inside = lp.y < sd.top_at(lp.z) - 0.5 and absf(lp.x) < maxf(hb, 0.5)
	if helm_node and helm_node.driver != null:
		player_aboard = true


# ================================================================ 船内のストリーミング
func _stream() -> void:
	var pl := Game.player
	var want := false
	if pl != null and is_instance_valid(pl):
		var lp := player_local
		var dz := maxf(absf(lp.z) - sd.L * 0.5, 0.0)
		var dx := maxf(absf(lp.x) - sd.B * 0.5, 0.0)
		var d := Vector2(dx, dz).length()
		want = d < (STREAM_OUT if (interior != null) else STREAM_IN)
	if want and interior == null:
		int_root = Node3D.new()
		int_root.name = "Interior"
		body.add_child(int_root)
		interior = ShipInterior.new(sd, int_root, seed)
		int_ready = false
	if interior != null and not int_ready:
		if interior.step():
			_finish_interior()
	if not want and interior != null:
		_unload_interior()


func _finish_interior() -> void:
	int_ready = true
	for c in interior.sk.cols:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c[1]
		cs.shape = bs
		cs.transform = c[0]
		body.add_child(cs)
		int_shapes.append(cs)
	for di in interior.door_nodes:
		var dn: Dictionary = interior.door_nodes[di]
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = dn["size"]
		cs.shape = bs
		cs.transform = dn["closed"]
		cs.disabled = bool((sd.doors[int(di)] as Dictionary).get("open", false))
		body.add_child(cs)
		int_shapes.append(cs)
		dn["shape"] = cs
	for vi in interior.valve_nodes:
		_valve_visual(int(vi))
	if not abandon and phase == "afloat":
		_spawn_crew()


func _unload_interior() -> void:
	for cs in int_shapes:
		if is_instance_valid(cs):
			(cs as Node).queue_free()
	int_shapes.clear()
	if is_instance_valid(int_root):
		int_root.queue_free()
	int_root = null
	interior = null
	int_ready = false
	for wp in water_planes.values():
		if is_instance_valid(wp):
			(wp as Node).queue_free()
	water_planes.clear()
	for c in crew:
		if is_instance_valid(c):
			(c as Node).queue_free()
	crew.clear()


# ================================================================ 被害
func _cause_for(team: int) -> String:
	if team == 0:
		Destruction.note_player()
		return "player"
	if team >= 1:
		return "enemy"
	if Time.get_ticks_msec() / 1000.0 - Destruction.last_player_t < Destruction.INDIRECT_WINDOW:
		return "player_indirect"
	return "world"


## 弾（銃）
func on_hit(amount: float, from_team: int, point: Vector3, dir: Vector3) -> void:
	if phase == "wreck":
		return
	cause = _cause_for(from_team)
	_panic_crew(point)
	if sd.steel or point == Vector3.ZERO:
		return
	var lp := xf_cur.affine_inverse() * point
	# 木造船: 水線付近の弾痕から少しずつ漏れる
	if lp.y < 0.6 and lp.y > -sd.T:
		flood.add_breach(_hull_point(lp), amount * 0.00012, "shot")
		active = true


## 砲弾の直撃（爆発の前に Shell が呼ぶ）
func on_direct_blast(dmg: float, origin: Vector3, fire_chance: float) -> void:
	_damage_at(origin, dmg, 2.0, fire_chance, -1, true)


## 爆発（Effects.explosion → Destruction.blast_at → ShipYard.blast_all）
func on_blast(pos: Vector3, radius: float, damage: float, team: int, fire_chance: float) -> void:
	_damage_at(pos, damage, radius, fire_chance, team, false)


func on_ram(speed: float, vel: Vector3, mass_k: float, point: Vector3) -> void:
	if speed < 3.0 or phase == "wreck":
		return
	var p := point
	if p == Vector3.INF:
		var pl = Game.player
		if pl != null and is_instance_valid(pl) and pl.has_method("in_vehicle") and pl.in_vehicle():
			p = (pl.vehicle as Node3D).global_position + vel.normalized() * 2.0
			cause = "player"
			Destruction.note_player()
		else:
			p = xf_cur.origin - vel.normalized() * sd.B * 0.5
			cause = _cause_for(-1)
	var lp := xf_cur.affine_inverse() * p
	lp.y = clampf(lp.y, -sd.T * 0.6, sd.top_m)
	var a := (speed - 3.0) * mass_k * 0.08 / (sd.strength() / 300.0)
	flood.add_breach(_hull_point(lp), a, "ram")
	active = true
	_panic_crew(p)


func on_ignite(_point: Vector3) -> void:
	_pending_ignite = 0.4
	active = true


## 船体表面のいちばん近い点（ローカル）
func _hull_point(lp: Vector3) -> Vector3:
	var y := clampf(lp.y, -sd.T + 0.3, sd.top_at(lp.z))
	var e := sd.z_ends(y)
	var z := clampf(lp.z, e.x + 0.5, e.y - 0.5)
	var hb := sd.half_beam(z, y)
	return Vector3(signf(lp.x if lp.x != 0.0 else 1.0) * hb, y, z)


func _damage_at(pos: Vector3, damage: float, radius: float, fire_chance: float, team: int, direct: bool) -> void:
	if phase == "wreck" or damage <= 0.0:
		return
	var xf := xf_cur
	var lp := xf.affine_inverse() * pos
	var inside := sd.inside(lp, 0.0) and lp.y < sd.top_at(lp.z) - 0.2
	var hp := _hull_point(lp)
	var d := 0.0 if inside else lp.distance_to(hp)
	# 上部構造や甲板の上の爆発は船体（水線）から遠い
	if not inside and lp.y > sd.top_at(lp.z):
		d = maxf(d, lp.y - sd.top_at(lp.z))
	if d > radius + 1.0:
		return
	if team != -2:
		cause = _cause_for(team) if not direct else cause
	active = true
	var k := clampf(1.0 - d / maxf(radius, 0.5), 0.0, 1.0)
	var eff := damage * pow(k, 1.2) if not direct else damage
	var s := sd.strength() * (0.45 if inside else 1.0)
	var a := maxf(0.0, eff - s * 0.25) / s * 1.6
	if a > 0.01:
		var bp := hp
		if inside:
			# 船内の爆発: 近い舷側と（低ければ）船底
			bp = Vector3(signf(lp.x if lp.x != 0.0 else 1.0) * sd.half_beam(lp.z, clampf(lp.y, -sd.T + 0.3, sd.top_m)), clampf(lp.y, -sd.T + 0.3, sd.top_m), lp.z)
			if lp.y < 0.0:
				flood.add_breach(Vector3(bp.x * 0.3, sd.keel_at(lp.z) + 0.2, lp.z), a * 0.5, "blast")
		if bp.y < sd.top_at(bp.z) + 0.3:
			flood.add_breach(bp, a, "blast")
			_hole_visual(bp, a)
	# 火災
	var fc := fire_chance * (1.0 if not sd.steel else 0.35)
	if _pending_ignite > 0.0:
		fc = 1.0
		_pending_ignite = 0.0
	if randf() < fc:
		flood.ignite_at(lp.z, 0.3 + 0.4 * k)
	# 弾火薬庫・缶室
	if inside and lp.y < sd.sim_fb:
		var c := sd.comp_at(lp)
		var m := flood.magazine_comp(c)
		if m >= 0 and String(flood.mag[m]["state"]) == "ok" and eff > 120.0 and randf() < clampf(eff / 400.0, 0.2, 1.0):
			_detonate_magazine(m)
		elif bool((sd.comps[c] as Dictionary).get("boiler", false)) and eff > 300.0 and not flood.boilers_blown.has(c) and randf() < 0.3:
			flood.boilers_blown[c] = true
			_boiler_explosion(c)
	_panic_crew(pos)


func _hole_visual(bp: Vector3, a: float) -> void:
	if hole_fx.size() > 14:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var r := clampf(sqrt(a) * 0.6, 0.25, 3.5)
	cm.top_radius = r
	cm.bottom_radius = r * 1.15
	cm.height = 0.08
	cm.radial_segments = 9
	mi.mesh = cm
	mi.material_override = Humanoid.mat(Color(0.05, 0.04, 0.04), 0.9)
	var side := signf(bp.x if bp.x != 0.0 else 1.0)
	mi.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * side), bp + Vector3(side * 0.05, 0, 0))
	body.add_child(mi)
	hole_fx.append(mi)


# ================================================================ 出来事（浸水シミュレーションから）
func _handle_events() -> void:
	for ev in flood.events:
		var e: Dictionary = ev
		match String(e["type"]):
			"burn_through":
				var z := float(e["z"])
				for side: float in [-1.0, 1.0]:
					var bp := Vector3(float(side) * sd.half_beam(z, -0.15), -0.15, z)
					flood.add_breach(bp, float(e["a"]) * 0.5, "burn")
				_toast("burn", "%s: 舷側が焼け抜けた！ 浸水が始まる" % sd.name_ja)
			"ordnance":
				var z2 := float(e["z"])
				var p := xf_cur * Vector3(randf_range(-sd.B * 0.25, sd.B * 0.25), flood.fire_y, z2)
				Effects.explosion(get_tree(), p, 11.0, 160.0, -1, 0.8)
				_toast("ord", "%s: 格納庫で爆弾・魚雷が誘爆！" % sd.name_ja)
			"magazine_warn":
				if not _mag_warned.has(e["name"]):
					_mag_warned[e["name"]] = true
					_toast("magw", "%s: 火が%sに迫る！ 約%d秒で誘爆 — 注水弁（赤）を開けろ" % [sd.name_ja, String(e["name"]), int(float(e["t"]))], 5.0)
			"magazine":
				_detonate_magazine(int(e["m"]))
			"magazine_safe":
				_toast("mags", "%s: %sに注水した（誘爆の危険なし）" % [sd.name_ja, String(e["name"])])
			"boiler":
				_boiler_explosion(int(e["c"]))
			"power_lost":
				_toast("pow", "%s: 缶室が浸水、動力を失った（ポンプ停止）" % sd.name_ja)


func _detonate_magazine(m: int) -> void:
	if m < 0 or m >= flood.mag.size():
		return
	var md: Dictionary = flood.mag[m]
	if String(md["state"]) == "exploded":
		return
	md["state"] = "exploded"
	var comps: Array = md["comps"]
	var c0: Dictionary = sd.comps[int(comps[0])]
	var z := 0.0
	for c in comps:
		z += float((sd.comps[int(c)] as Dictionary)["cz"])
	z /= maxf(comps.size(), 1)
	var keel := sd.keel_at(z)
	var xf := xf_cur
	var wp := xf * Vector3(0, keel + 2.5, z)
	# 船体の大破孔（船底と両舷）
	var a := float(sd.sim.get("magazine_breach", clampf(sd.B * sd.T * 0.18, 4.0, 45.0)))
	flood.add_breach(Vector3(0.0, keel + 0.3, z), a * 0.5, "magazine")
	for side: float in [-1.0, 1.0]:
		var bp := Vector3(float(side) * sd.half_beam(z, keel * 0.4), keel * 0.4, z)
		flood.add_breach(bp, a * 0.25, "magazine")
		_hole_visual(bp, a * 0.25)
	# 爆発で隣の隔壁も吹き飛ぶ（区画どうしが大きくつながる）
	for c in comps:
		flood.blow_bulkheads(int(c), a * 0.3)
	flood.ignite_at(z, 1.0)
	flood.ignite_at(z + 8.0, 0.6)
	flood.ignite_at(z - 8.0, 0.6)
	in_detonation = true
	var r := clampf(sd.L * 0.18, 12.0, 34.0)
	Effects.explosion(get_tree(), wp, r, 190.0, -1, 0.9)
	in_detonation = false
	var top := xf * Vector3(0, sd.top_m + 2.0, z)
	Effects.burst(get_tree(), top, Vector3.UP, Color(1.0, 0.6, 0.2), Color(0.9, 0.2, 0.05), 90, 22.0, 2.2, 1.4, -0.1, true, 200)
	Effects.burst(get_tree(), top, Vector3.UP, Color(0.25, 0.22, 0.2, 0.9), Color(0.45, 0.42, 0.4, 0.0), 60, 9.0, 9.0, 6.0, -0.25, false, 150)
	Effects.flash(get_tree(), top, Color(1, 0.65, 0.3), 30.0, r * 6.0, 1.2)
	Effects.shake = maxf(Effects.shake, 1.2)
	Wanted.report(top, 1.0)
	_toast("mag", "%s: %sが爆発した！" % [sd.name_ja, String(md["name"])], 4.0)
	_panic_crew(wp)
	abandon_ship()


func _boiler_explosion(c: int) -> void:
	var cp: Dictionary = sd.comps[c]
	var z := float(cp["cz"])
	var p := xf_cur * Vector3(float(cp["cx"]), sd.keel_at(z) + 2.0, z)
	in_detonation = true
	Effects.explosion(get_tree(), p, 10.0, 120.0, -1, 0.4)
	in_detonation = false
	Effects.burst(get_tree(), xf_cur * Vector3(0, sd.top_m + 1.0, z), Vector3.UP, Color(0.95, 0.95, 0.95, 0.85), Color(0.8, 0.8, 0.8, 0.0), 50, 8.0, 5.0, 3.0, -0.2, false, 120)
	flood.add_breach(Vector3(float(cp["cx"]), sd.keel_at(z) + 0.4, z), 3.5, "boiler")
	_toast("boil", "%s: 缶室で水蒸気爆発！" % sd.name_ja)


# ================================================================ 姿勢・沈没
func _attitude(dt: float) -> void:
	var att := flood.attitude()
	var k := 1.0 - exp(-dt / 4.0)
	match phase:
		"afloat":
			sink = lerpf(sink, float(att["sink"]), k)
			trim = lerpf(trim, float(att["trim"]), k)
			heel = lerpf(heel, float(att["heel"]), 1.0 - exp(-dt / 5.0))
			if bool(att["capsize"]) and absf(heel) > deg_to_rad(8.0):
				phase = "capsizing"
				_cap_rate = 0.02
				_toast("cap", "%s が転覆する！" % sd.name_ja, 4.0)
				abandon_ship()
			elif flood.flood_ratio() > 0.95 or sink > sd.sim_fb + 0.4:
				_begin_plunge()
			if flood.flood_ratio() > 0.4 or absf(heel) > deg_to_rad(14.0) or flood.burning() > maxi(2, flood.zones / 2):
				abandon_ship()
		"capsizing":
			_cap_rate = minf(_cap_rate + dt * 0.05, 0.45)
			heel += signf(heel if heel != 0.0 else 1.0) * _cap_rate * dt
			sink = lerpf(sink, float(att["sink"]) + 1.0, k)
			trim = lerpf(trim, float(att["trim"]), k)
			if bool(sd.sim.get("capsize_magazine", false)) and not capsize_mag_done and absf(heel) > deg_to_rad(60.0):
				capsize_mag_done = true
				for m in flood.mag.size():
					if String(flood.mag[m]["state"]) == "ok":
						_detonate_magazine(m)
						break
			if absf(heel) > 2.5:
				heel = signf(heel) * 2.5
				_begin_plunge()
		"plunge", "settling":
			var vmax := clampf(sd.L / 60.0, 1.2, 4.0)
			plunge_v = minf(plunge_v + dt * 0.22, vmax)
			plunge += plunge_v * dt
			var tgt := signf(trim if trim != 0.0 else 1.0) * clampf(10.0 / sd.L, 0.12, 0.5)
			if phase == "plunge":
				trim = lerpf(trim, tgt, 1.0 - exp(-dt / 6.0))
			else:
				trim = lerpf(trim, trim * 0.3, 1.0 - exp(-dt / 3.0))
			if absf(heel) > 0.01 and phase == "plunge" and absf(heel) < 1.5:
				heel = lerpf(heel, heel * 1.3, 1.0 - exp(-dt / 10.0))
			_foam_t -= dt
			if _foam_t <= 0.0 and plunge < sd.top_m + 20.0:
				_foam_t = 0.35
				var c := xf_cur.origin
				Effects.burst(get_tree(), Vector3(c.x + randf_range(-sd.L * 0.3, sd.L * 0.3), 0.3, c.z + randf_range(-sd.B, sd.B)), Vector3.UP, Color(0.9, 0.97, 1.0, 0.9), Color(0.7, 0.85, 1.0, 0.0), 14, 5.0, 1.5, 1.6, 0.6, false, 40)
			var low := _lowest_y()
			if phase == "settling":
				_settle_t += dt
				if _settle_t > 4.0:
					_wreck()
					return
			if low <= floor_y:
				if phase == "plunge" and not deep:
					phase = "settling"
				elif phase == "settling" or deep:
					if _mid_keel_y() <= floor_y + 0.6 or deep:
						_wreck()
				# 底についたら沈下を止める
				plunge -= (floor_y - low) if phase == "settling" else 0.0
				plunge_v *= 0.5
			if deep and plunge > sd.T + sd.top_m + 45.0:
				_wreck()


func _begin_plunge() -> void:
	if phase == "plunge" or phase == "settling" or phase == "wreck":
		return
	phase = "plunge"
	plunge_v = 0.15
	abandon_ship()
	_toast("sink", "%s が沈んでいく……" % sd.name_ja, 4.0)
	_emit_sunk()


func _wreck() -> void:
	phase = "wreck"
	active = false
	_emit_sunk()
	for k in fire_fx:
		var n: Node = fire_fx[k]
		if is_instance_valid(n):
			n.queue_free()
	fire_fx.clear()
	for k in flood.zones:
		flood.fire[k] = 0.0


func _lowest_y() -> float:
	var xf := xf_cur
	var lo := INF
	for p in [Vector3(0, sd.keel_at(-sd.L * 0.45), -sd.L * 0.45), Vector3(0, sd.keel_at(sd.L * 0.45), sd.L * 0.45), Vector3(0, -sd.T, 0),
			Vector3(sd.B * 0.5, sd.top_m, 0), Vector3(-sd.B * 0.5, sd.top_m, 0), Vector3(0, sd.top_m + 6.0, 0)]:
		lo = minf(lo, (xf * (p as Vector3)).y)
	return lo


func _mid_keel_y() -> float:
	return (xf_cur * Vector3(0, -sd.T, 0)).y


func _emit_sunk() -> void:
	if sunk_emitted:
		return
	sunk_emitted = true
	var pos := xf_cur.origin
	var info := {"type": "ship", "ship": sd.id, "name": sd.name_ja, "pos": pos, "value": sd.value(), "cause": cause, "era": era_id,
		"landmark": landmark, "year": sd.year}
	var g = get_node_or_null("/root/Game")
	if g and g.has_signal("chaos_event"):
		g.emit_signal("chaos_event", "sink", landmark, info)
	var d := Destruction.current
	if d != null and is_instance_valid(d):
		d.stats["ships"] = int(d.stats["ships"]) + 1
		d.stats["ryo"] = int(d.stats["ryo"]) + sd.value()
	if cause in ["player", "player_indirect"]:
		Wanted.report(pos, 1.0)
	sunk.emit(self)


## 船ローカル → ワールドの変換（沈下・トリム・傾斜・揺れ）
func _apply_xf(dt: float) -> void:
	_bob_t += dt
	var bob := 0.0
	var roll := 0.0
	if phase == "afloat" and sd.L < 70.0 and player_near:
		var amp := clampf(3.0 / sd.L, 0.03, 0.18)
		bob = sin(_bob_t * 0.9) * amp
		roll = sin(_bob_t * 0.63) * clampf(1.2 / sd.L, 0.004, 0.04)
	# heel > 0: 右舷が下がる（+Z 軸まわりに -heel）。trim > 0: 艦首が下がる（+X 軸まわりに -trim）
	var basis := Basis(Vector3.FORWARD, heel + roll) * Basis(Vector3.RIGHT, -trim)
	var xf := anchor * Transform3D(basis, Vector3(0, -sink - plunge + bob, 0))
	if not xf.is_equal_approx(_last_xf):
		body.global_transform = xf
		xf_cur = xf
		_last_xf = xf


# ================================================================ 操船
func _pilot(dt: float) -> void:
	if helm_node == null:
		return
	var drv = helm_node.driver
	var throttle := 0.0
	var steer := 0.0
	if drv != null and not Game.input_blocked and phase == "afloat":
		var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		throttle = mv.y
		steer = -mv.x
	var vmax := float(sd.pilot.get("vmax", clampf(sd.L / 6.0, 3.0, 8.0)))
	var acc := float(sd.pilot.get("accel", clampf(12.0 / sd.L, 0.08, 0.6)))
	if Input.is_action_pressed("sprint") and drv != null:
		vmax *= 1.4
	nav_speed = move_toward(nav_speed, throttle * vmax * (1.0 if throttle >= 0.0 else 0.4), acc * dt)
	if flood.flood_ratio() > 0.3:
		nav_speed *= 0.995
	var turn := float(sd.pilot.get("turn", clampf(6.0 / sd.L, 0.06, 0.35)))
	nav_turn = lerpf(nav_turn, steer * turn * clampf(absf(nav_speed) / 2.0, 0.15, 1.0) * signf(nav_speed if nav_speed != 0.0 else 1.0), 1.0 - exp(-dt * 1.5))
	if absf(nav_speed) < 0.01 and absf(nav_turn) < 0.0005:
		return
	var nb := anchor.basis.rotated(Vector3.UP, nav_turn * dt)
	var fwd := -nb.z
	var np := anchor.origin + fwd * nav_speed * dt
	# 座礁・岸・ほかの船・場外
	var w = Game.world
	var bow := np + fwd * signf(nav_speed) * sd.L * 0.5
	var hit := false
	if w and w.has_method("height_at"):
		if float(w.height_at(bow.x, bow.z)) > -sd.T * 0.75:
			hit = true
	for o in get_tree().get_nodes_in_group("ship"):
		if o == self:
			continue
		var os := o as Ship
		var lp: Vector3 = os.xf_cur.affine_inverse() * bow
		if os.sd.inside(Vector3(lp.x, clampf(lp.y, -1.0, 1.0), lp.z), -1.0) or (absf(lp.x) < os.sd.B * 0.5 + 1.0 and absf(lp.z) < os.sd.L * 0.5 and absf(lp.y) < 6.0):
			hit = true
			if absf(nav_speed) > 1.5:
				os.on_ram(absf(nav_speed) * 1.6, fwd * nav_speed, clampf(sd.disp / 300.0, 1.0, 20.0), bow)
	if absf(np.x) > 900.0 or absf(np.z) > 900.0:
		hit = true
	if hit:
		if absf(nav_speed) > 2.0:
			_toast("ground", "%s: 座礁・衝突！" % sd.name_ja)
			flood.add_breach(Vector3(0, -sd.T * 0.7, -sd.L * 0.45 * signf(nav_speed)), (absf(nav_speed) - 2.0) * 0.08 / (sd.strength() / 300.0), "ground")
			active = true
		nav_speed = -nav_speed * 0.2
		return
	anchor = Transform3D(nb, np)
	_wake_t -= dt
	if _wake_t <= 0.0 and absf(nav_speed) > 1.0:
		_wake_t = 0.25
		var st := anchor * Vector3(randf_range(-sd.B * 0.3, sd.B * 0.3), 0.2, sd.L * 0.5)
		Effects.burst(get_tree(), st, Vector3.UP, Color(0.95, 0.98, 1.0, 0.85), Color(0.8, 0.9, 1.0, 0.0), 6, 2.0, 0.8, 1.2, 0.4, false, 30)


# ================================================================ 乗組員
func _spawn_crew() -> void:
	if not crew.is_empty() or sd.crew_points.is_empty():
		return
	var n := clampi(int(sd.L / 18.0) + 2, 2, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 5
	var pts: Array = []
	for p in sd.crew_points:
		pts.append(xf_cur * (p as Vector3))
	var parent: Node = get_parent()
	var cera := era_id
	for i in n:
		var p: Vector3 = pts[rng.randi() % pts.size()]
		var c := Civilian.spawn(parent, p + Vector3(0, 0.4, 0), cera, pts)
		c.set_meta("ship_crew", sd.id)
		crew.append(c)


func _panic_crew(from: Vector3) -> void:
	for c in crew:
		if is_instance_valid(c):
			(c as Civilian).panic(from)


## 総員退船: 乗組員は舷梯へ逃げ、短艇で岸へ向かう（倒れない）
func abandon_ship() -> void:
	if abandon:
		return
	abandon = true
	flood.crew_aboard = false
	_toast("abandon", "%s: 総員退船！" % sd.name_ja, 3.0)
	var top := xf_cur * Vector3(float(sd.ladder["side"]) * (float(sd.ladder.get("hb", sd.B * 0.5)) - 1.2), sd.top_at(float(sd.ladder["z"])) + 0.3, float(sd.ladder["z"]))
	for c in crew:
		if is_instance_valid(c):
			var cv := c as Civilian
			cv.points = [top]
			cv.set("_goal", top)
			cv.set("_panic", 0.0)


func _crew_step(dt: float) -> void:
	_crew_t -= dt
	if _crew_t <= 0.0:
		_crew_t = 0.5
		var keep: Array = []
		var gone := 0
		var top := xf_cur * Vector3(float(sd.ladder["side"]) * (float(sd.ladder.get("hb", sd.B * 0.5)) - 1.2), sd.top_at(float(sd.ladder["z"])) + 0.3, float(sd.ladder["z"]))
		for c in crew:
			if not is_instance_valid(c):
				continue
			var cv := c as Civilian
			var p := cv.global_position
			var done := false
			if abandon and p.distance_to(top) < 3.5:
				done = true
			if p.y < -0.8:
				done = true      # 海に飛び込んで泳いで離れる
				Effects.burst(get_tree(), Vector3(p.x, 0.2, p.z), Vector3.UP, Color(0.9, 0.97, 1.0, 0.8), Color(0.7, 0.85, 1.0, 0.0), 8, 3.0, 0.6, 1.0, 0.5, false, 20)
			if done:
				cv.queue_free()
				gone += 1
			else:
				if abandon:
					cv.points = [top]
					cv.set("_goal", top)
				keep.append(cv)
		crew = keep
		if gone > 0 and lifeboats.size() < 3:
			_launch_lifeboat()
	for lb in lifeboats:
		if is_instance_valid(lb):
			(lb as ShipLifeboat).step(dt)


func _launch_lifeboat() -> void:
	var side := float(sd.ladder["side"])
	var p := xf_cur * Vector3(side * (sd.B * 0.5 + 3.0), 0.0, float(sd.ladder["z"]) + 3.0)
	p.y = 0.0
	var lb := ShipLifeboat.new()
	var parent: Node = get_parent()
	parent.add_child(lb)
	lb.setup(p, anchor.basis.x.normalized() * side, sd.year)
	lifeboats.append(lb)


# ================================================================ 調べる（E）
func _interaction() -> void:
	near_item = {}
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or pl.in_vehicle():
		return
	var lp := player_local + Vector3(0, 1.0, 0)
	var best := 2.2
	var items: Array = []
	if int_ready:
		items = interior.interact
	# 舷梯（上と下）
	var lz := float(sd.ladder["z"])
	var side := float(sd.ladder["side"])
	var hb := float(sd.ladder.get("hb", sd.B * 0.5))
	var bottom := Vector3(side * (hb + 0.9), 0.9, lz + float(sd.ladder.get("run", 4.0)) + 0.6)
	var topp := Vector3(side * (hb - 1.0), sd.top_at(lz) + 1.0, lz)
	var ex: Array = [{"kind": "ladder_up", "p": bottom}, {"kind": "ladder_down", "p": topp}]
	for it in items + ex:
		var d := (it["p"] as Vector3).distance_to(lp)
		var r := 3.0 if String(it["kind"]).begins_with("ladder") else 2.2
		if d < r and d < best + (0.8 if String(it["kind"]).begins_with("ladder") else 0.0):
			best = d
			near_item = it
	if near_item.is_empty() or Game.input_blocked:
		return
	if Input.is_action_just_pressed("interact"):
		_use(near_item)


func prompt_text() -> String:
	if near_item.is_empty():
		return ""
	var it := near_item
	match String(it["kind"]):
		"door":
			var d: Dictionary = sd.doors[int(it["idx"])]
			return "E：水密扉を%s" % ("閉める" if bool(d.get("open", false)) else "開ける（浸水が広がる）")
		"valve":
			var v: Dictionary = sd.valves[int(it["idx"])]
			var open := flood.valve_open[int(it["idx"])] == 1
			return "E：%sを%s" % [String(v["name"]), "閉じる" if open else "開く（注水）"]
		"pump":
			return "E：ポンプを%s" % ("止める" if flood.pump_on else "動かす")
		"ladder_up":
			return "E：舷梯を登って乗船"
		"ladder_down":
			return "E：舷梯を降りる"
	return ""


func _use(it: Dictionary) -> void:
	var pl = Game.player
	match String(it["kind"]):
		"door":
			var i := int(it["idx"])
			var d: Dictionary = sd.doors[i]
			var open := not bool(d.get("open", false))
			d["open"] = open
			flood.set_door(i, open)
			interior.set_door(i, open)
			Sfx.play_at(get_tree(), Sfx.hit(), xf_cur * (it["p"] as Vector3), -4.0)
			if open:
				cause = "player"
				active = true
		"valve":
			var i := int(it["idx"])
			var open := flood.valve_open[i] == 0
			flood.set_valve(i, open)
			_valve_visual(i)
			var v: Dictionary = sd.valves[i]
			if open:
				cause = "player"
				Destruction.note_player()
				active = true
				_toast("valve%d" % i, "%sを開いた。海水が流れ込む！" % String(v["name"]), 3.0)
			Sfx.play_at(get_tree(), Sfx.click(), xf_cur * (it["p"] as Vector3), 0.0)
		"pump":
			flood.pump_on = not flood.pump_on
			_toast("pump", "ポンプを%s" % ("動かした" if flood.pump_on else "止めた"), 2.0)
		"ladder_up":
			var lz := float(sd.ladder["z"])
			var side := float(sd.ladder["side"])
			var hb := float(sd.ladder.get("hb", sd.B * 0.5))
			pl.teleport(xf_cur * Vector3(side * (hb - 1.6), sd.top_at(lz) + 0.4, lz - 1.0))
		"ladder_down":
			var lz2 := float(sd.ladder["z"])
			var side2 := float(sd.ladder["side"])
			var hb2 := float(sd.ladder.get("hb", sd.B * 0.5))
			var p := xf_cur * Vector3(side2 * (hb2 + 0.9), 0.5, lz2 + float(sd.ladder.get("run", 4.0)) + 0.6)
			p.y = maxf(p.y, 0.45)
			pl.teleport(p)


func _valve_visual(i: int) -> void:
	if interior == null or not interior.valve_nodes.has(i):
		return
	var wh: MeshInstance3D = interior.valve_nodes[i]
	if is_instance_valid(wh):
		wh.rotation.y = PI * 0.5 if flood.valve_open[i] == 1 else 0.0
		var vp: Vector3 = (sd.valves[i] as Dictionary)["p"]
		wh.position.y = vp.y + (1.05 if flood.valve_open[i] == 1 else 0.95)


func _toast(key: String, text: String, dur := 2.5) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _toasts.has(key) and now - float(_toasts[key]) < 8.0:
		return
	_toasts[key] = now
	if not (player_near or player_aboard):
		var pl = Game.player
		if pl == null or not is_instance_valid(pl) or (pl as Node3D).global_position.distance_to(xf_cur.origin) > 600.0:
			return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(text, dur)


# ================================================================ 表示（区画の水・火）
func _update_water_planes() -> void:
	var xf := xf_cur
	var yard := ShipYard.current
	for i in flood.n:
		var v := flood.vol[i]
		var wp: MeshInstance3D = water_planes.get(i, null)
		if v < 0.6 or flood.fill(i) > 0.995 and phase != "afloat":
			if wp and is_instance_valid(wp):
				wp.visible = false
			continue
		if wp == null or not is_instance_valid(wp):
			wp = MeshInstance3D.new()
			var pm := PlaneMesh.new()
			var cp: Dictionary = sd.comps[i]
			pm.size = Vector2(float(cp["w"]) * 0.96, (float(cp["z1"]) - float(cp["z0"])) * 0.98)
			wp.mesh = pm
			wp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if yard:
				wp.material_override = yard.inner_water_mat()
			add_child(wp)
			water_planes[i] = wp
		wp.visible = true
		var c: Vector3 = flood.cpos[i]
		var p := xf * Vector3(c.x, flood.level_local(i), c.z)
		var yaw := atan2(-xf.basis.z.x, -xf.basis.z.z)
		wp.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)


func _update_fire_fx() -> void:
	if phase == "wreck":
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var far := cam == null or cam.global_position.distance_to(xf_cur.origin) > 900.0
	for k in flood.zones:
		var f := flood.fire[k]
		var node: Node3D = fire_fx.get(k, null)
		if f <= 0.05 or far:
			if node and is_instance_valid(node):
				node.visible = false
			continue
		if node == null or not is_instance_valid(node):
			if fire_fx.size() >= 6:
				continue
			node = _make_flames()
			body.add_child(node)
			node.position = Vector3(0, maxf(flood.fire_y, sd.top_at(flood.zone_z[k])) + 0.3, flood.zone_z[k])
			fire_fx[k] = node
		node.visible = true
		node.scale = Vector3.ONE * clampf(0.5 + f * 0.6, 0.5, 1.1)


func _make_flames() -> Node3D:
	var root := Node3D.new()
	var fl := CPUParticles3D.new()
	fl.name = "Flames"
	fl.amount = 48
	fl.lifetime = 0.9
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var zl := (flood.fire_z1 - flood.fire_z0) / maxf(flood.zones, 1)
	fl.emission_box_extents = Vector3(sd.B * 0.3, 0.4, zl * 0.4)
	fl.direction = Vector3.UP
	fl.spread = 15.0
	fl.initial_velocity_min = 1.5
	fl.initial_velocity_max = 3.5
	fl.gravity = Vector3(0, 2.5, 0)
	fl.scale_amount_min = 2.5
	fl.scale_amount_max = 5.5
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.92, 0.45, 1.0))
	g.set_color(1, Color(0.85, 0.12, 0.04, 0.0))
	g.add_point(0.45, Color(1.0, 0.5, 0.1, 1.0))
	fl.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 1.2)
	q.material = Destruction._flame_mat()
	fl.mesh = q
	fl.local_coords = false
	root.add_child(fl)
	var sm := CPUParticles3D.new()
	sm.amount = 14
	sm.lifetime = 5.0
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sm.emission_box_extents = fl.emission_box_extents * 0.6
	sm.direction = Vector3(0.2, 1, 0.1)
	sm.spread = 12.0
	sm.initial_velocity_min = 2.5
	sm.initial_velocity_max = 4.0
	sm.gravity = Vector3(0.6, 0.8, 0)
	sm.scale_amount_min = 4.0
	sm.scale_amount_max = 9.0
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.2, 0.18, 0.17, 0.8))
	g2.set_color(1, Color(0.4, 0.38, 0.36, 0.0))
	sm.color_ramp = g2
	var q2 := QuadMesh.new()
	q2.size = Vector2(1.0, 1.0)
	q2.material = Effects.particle_mat(Color.WHITE, false)
	sm.mesh = q2
	sm.local_coords = false
	root.add_child(sm)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.omni_range = 14.0
	l.light_energy = 2.0
	l.position = Vector3(0, 2.0, 0)
	root.add_child(l)
	return root


# ================================================================ 情報（HUD・海面のマスク）
func status_text() -> String:
	var fr := flood.flood_ratio()
	var deg := rad_to_deg(heel)
	var tdeg := rad_to_deg(trim)
	var st := ""
	match phase:
		"afloat":
			st = "浮揚" if fr < 0.05 else ("浸水中" if fr < 0.5 else "大浸水")
		"capsizing": st = "転覆中"
		"plunge": st = "沈没中"
		"settling": st = "着底"
		"wreck": st = "沈没"
	var s := "%s（%d年）  %s  浸水 %d%%  傾斜 %s%.0f°  トリム %s%.1f°" % [sd.name_ja, sd.year, st, int(fr * 100.0),
		"右" if deg > 0.0 else "左", absf(deg), "艦首" if tdeg > 0.0 else "艦尾", absf(tdeg)]
	if flood.burning() > 0:
		s += "  火災 %d区域" % flood.burning()
	if not flood.power and sd.steel:
		s += "  動力喪失"
	if flood.breaches.size() > 0:
		s += "  破孔 %d" % flood.breaches.size()
	if not flood.pump_on:
		s += "  ポンプ停止"
	return s


## 海面のマスク（船体の中に海面を描かない）: [o, x, z, y, p, t]（Vector4）
func mask_params() -> Array:
	var xf := xf_cur
	var on := phase != "wreck" and absf(heel) < 1.2
	return [Vector4(xf.origin.x, xf.origin.y, xf.origin.z, sd.L * 0.5 if on else 0.0),
		Vector4(xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, sd.B * 0.5),
		Vector4(xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, sd.midp),
		Vector4(xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, sd.top_m - 0.15),
		Vector4(sd.pb, sd.ps, sd.qexp, 0.94),
		Vector4(sd.tb, sd.ts, 0.0, 0.0)]


## ワールド座標の点の水面（船内の区画の水位・または海面）。船内で乾いていれば -INF
func water_y_at(p: Vector3) -> float:
	var xf := xf_cur
	var lp := xf.affine_inverse() * p
	if not sd.inside(lp, -0.2) or lp.y > sd.top_at(lp.z):
		return INF
	var c := sd.comp_at(lp)
	if flood.vol[c] < 0.3:
		return -INF
	var cc: Vector3 = flood.cpos[c]
	return (xf * Vector3(cc.x, flood.level_local(c), cc.z)).y

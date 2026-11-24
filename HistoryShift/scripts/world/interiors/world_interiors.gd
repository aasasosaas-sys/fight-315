class_name WorldInteriors
extends Node3D
## 建物の内装のストリーミング（EraWorld の子）。
## - 生成時に Architecture.reg_interior が EraWorld.interior_defs に登録した建物（破壊ユニット ID ごと）を管理する。
## - プレイヤー（無ければカメラ）が LOAD_DIST 以内に来た建物だけ内装を生成し、FREE_DIST より離れたら外す。
##   外した内装は小さなプール（POOL）に残して再接近ですぐ戻す。描画は 1 棟につき 1 メッシュ＋当たり判定 1 体。
## - 実ライトは近い順に MAX_LIGHTS 灯だけ（それ以外は発光材の灯具と外光で見せる）。
## - 破壊と連動: 屋根崩落・炎上・倒壊した建物は入口を塞ぎ（中にいなければ内装も消す）、中にいる時に燃えたら屋内に炎、
##   倒壊したら外へ押し出してダメージ（即死はさせない）。

const LOAD_DIST := 25.0
const FREE_DIST := 60.0
const MAX_ACTIVE := 10
const POOL := 6
const MAX_LIGHTS := 4
const TICK := 0.12
const KITS_JSON := "res://data/interiors/kits.json"

static var current: WorldInteriors

var world: Node3D
var _indoor_k := 0.0
var defs := {}               # id -> def
var ids: Array = []
var active := {}             # id -> Node3D（ツリー内）
var pool := {}               # id -> Node3D（ツリー外）
var pool_order: Array = []
var pinned := {}
var blocked := {}            # id -> 理由（damaged / burning / destroyed）
var player_inside := -1
var stats := {"built": 0, "reused": 0, "released": 0, "ms_max": 0.0, "ms_total": 0.0, "lights": 0}
var kits_info := {}
var _t := 0.0
var _spots := {}             # id -> Array（dry 計算のキャッシュ）
var _barriers := {}
var _fire_fx := {}
var _burn_t := 0.0


static func attach(w: Node3D) -> WorldInteriors:
	var m := WorldInteriors.new()
	m.name = "Interiors"
	m.world = w
	w.add_child(m)
	m.setup(w.get("interior_defs"))
	current = m
	return m


func _exit_tree() -> void:
	if current == self:
		current = null
	if CameraRig.indoor:
		CameraRig.indoor = false


func setup(list: Array) -> void:
	_load_info()
	for d in list:
		var id: int = d["id"]
		# 足元の広がり（局所の床の和集合）→ 中心と半径
		var u := Rect2()
		var first := true
		var ytop := -INF
		for f in d["floors"]:
			var r: Rect2 = f["rect"]
			u = r if first else u.merge(r)
			first = false
			ytop = maxf(ytop, float(f["y"]) + float(f["h"]))
		var xf: Transform3D = d["xf"]
		var c := u.get_center()
		d["_c"] = xf * Vector3(c.x, 0, c.y)
		d["_r"] = u.size.length() * 0.5
		d["_inv"] = xf.affine_inverse()
		d["tags"] = d.get("tags", [])
		defs[id] = d
		ids.append(id)
	_assign_tags()
	_check_overlaps()
	print("[Interiors] %d enterable buildings (%d closed: overlapped by another building)" % [ids.size(), blocked.size()])


## レイアウトで別の建物と重なっている部屋は開けない（入口を塞ぐ）。中に他の建物の壁や屋根が突き出すため
func _check_overlaps() -> void:
	var dst := Destruction.current
	if dst == null or not is_instance_valid(dst):
		return
	for id in ids:
		var d: Dictionary = defs[id]
		var inv: Transform3D = d["_inv"]
		var f: Dictionary = d["floors"][0]
		var r: Rect2 = (f["rect"] as Rect2).grow(-0.3)
		var y0: float = f["y"]
		for u in dst.units_near(d["_c"], float(d["_r"]) + 15.0):
			var du := u as Destructible
			if du.id == id or du.kind in ["lamp", "lantern", "prop", "fence", "wall", "stonewall", "brickwall", "stall", "bridge", "boat", "torii"]:
				continue
			var hit := false
			for sh in du.def["shapes"]:
				var t: Transform3D = sh[0]
				if t.basis.y.normalized().dot(Vector3.UP) < 0.95:
					continue   # 坂（階段）は除く
				var c: Vector3 = inv * t.origin
				if r.has_point(Vector2(c.x, c.z)) and c.y > y0 - 0.5 and c.y < y0 + 8.0:
					hit = true
					break
			if hit:
				# 小さい方を閉じる
				var other: int = du.id
				var close: int = id
				if defs.has(other) and float(defs[other]["_r"]) < float(d["_r"]):
					close = other
				blocked[close] = "overlap"
				_add_barrier(close)
				break


func _load_info() -> void:
	if not FileAccess.file_exists(KITS_JSON):
		return
	var txt := FileAccess.get_file_as_string(KITS_JSON)
	var j = JSON.parse_string(txt)
	if j is Dictionary:
		kits_info = j


## 史実の場面に使う建物へ印を付ける（data/interiors/kits.json の scenes）
func _assign_tags() -> void:
	var era := String(world.get("era_id"))
	var scenes: Array = kits_info.get("scenes", {}).get(era, [])
	for sc in scenes:
		var best := -1
		var bd := INF
		var lm_key := String(sc.get("landmark", ""))
		var lp := Vector3.ZERO
		if world.has_method("landmark_pos") and lm_key != "":
			lp = world.call("landmark_pos", lm_key)
		for id in ids:
			var d: Dictionary = defs[id]
			if String(d["type"]) != String(sc.get("type", "")):
				continue
			if lm_key != "" and String(d.get("landmark", "")) != lm_key:
				continue
			if (d["floors"] as Array).size() < int(sc.get("floors", 1)):
				continue
			var dist := (d["_c"] as Vector3).distance_to(lp)
			if dist < bd:
				bd = dist
				best = id
		if best >= 0:
			(defs[best]["tags"] as Array).append(String(sc["tag"]))


# ================================================================ 公開 API（EraWorld から）
func find(tag: String) -> int:
	for id in ids:
		if tag in defs[id]["tags"]:
			return id
	return -1


func find_all(type := "", landmark := "") -> Array:
	var out: Array = []
	for id in ids:
		var d: Dictionary = defs[id]
		if type != "" and String(d["type"]) != type:
			continue
		if landmark != "" and String(d.get("landmark", "")) != landmark:
			continue
		out.append(id)
	return out


## 屋内の NPC 地点（ワールド座標）。内装を生成していなくても計算できる（キャッシュ）
func spots(id: int) -> Array:
	if not defs.has(id):
		return []
	if not _spots.has(id):
		var b := InteriorBuilder.new(defs[id], true)
		InteriorKits.build(b)
		var xf: Transform3D = defs[id]["xf"]
		var out: Array = []
		for s in b.spots:
			out.append({"pos": xf * (s["p"] as Vector3), "yaw": xf.basis.get_euler().y + float(s["yaw"]), "floor": int(s["floor"]), "role": String(s["role"])})
		_spots[id] = out
	return _spots[id]


func info(id: int) -> Dictionary:
	if not defs.has(id):
		return {}
	var d: Dictionary = defs[id]
	var k: Dictionary = kits_info.get("kits", {}).get(String(d["type"]), {})
	var xf: Transform3D = d["xf"]
	var doors: Array = []
	for dd in d["doors"]:
		doors.append({"pos": xf * (dd["p"] as Vector3), "out": xf * (dd["out"] as Vector3), "normal": xf.basis * (dd["n"] as Vector3)})
	return {"id": id, "type": d["type"], "name": k.get("name", d["type"]), "basis": k.get("basis", []), "era": d.get("era", ""),
		"landmark": d.get("landmark", ""), "floors": (d["floors"] as Array).size(), "tags": d["tags"], "doors": doors,
		"loaded": active.has(id), "blocked": blocked.get(id, "")}


## すぐに内装を作る（ミッションの場面・屋内 NPC の上階など）。pin=true なら離れても外さない
func ensure(id: int, pin := true) -> Node3D:
	if not defs.has(id) or blocked.has(id):
		return null
	if pin:
		pinned[id] = true
	if not active.has(id):
		_load(id)
	return active.get(id)


func release(id: int) -> void:
	pinned.erase(id)


func inside_at(p: Vector3) -> int:
	for id in active:
		if _contains(defs[id], p):
			return id
	for id in ids:
		var d: Dictionary = defs[id]
		if (d["_c"] as Vector3).distance_to(Vector3(p.x, (d["_c"] as Vector3).y, p.z)) < float(d["_r"]) + 1.0 and _contains(d, p):
			return id
	return -1


# ================================================================ 毎フレーム
func _process(dt: float) -> void:
	# 屋内の色調（目の慣れ）: 中にいる間は環境光を暖かく・露出を上げる。ゆっくり切り替える
	var want_k := 1.0 if player_inside >= 0 else 0.0
	if absf(_indoor_k - want_k) > 0.001:
		_indoor_k = move_toward(_indoor_k, want_k, dt * 1.5)
		if world and "env_nodes" in world:
			WorldAtmosphere.set_indoor(world.env_nodes, world.style, _indoor_k)
	_t += dt
	if _t < TICK:
		_fire_inside(dt)
		return
	_t = 0.0
	var p := _viewer_pos()
	_sync_damage()
	# 中にいるか
	var pl = Game.player if is_instance_valid(Game.player) else null
	var was := player_inside
	player_inside = -1
	if pl != null and not (pl.has_method("in_vehicle") and pl.in_vehicle()):
		for id in active:
			if _contains(defs[id], (pl as Node3D).global_position):
				player_inside = id
				break
	CameraRig.indoor = player_inside >= 0
	if was != player_inside and player_inside >= 0:
		_on_enter(player_inside)
	# 解放（遠い・上限超え）と生成（近い順に 1 棟／tick、ごく近ければ 2 棟）
	var cand: Array = []
	for id in ids:
		var d: Dictionary = defs[id]
		var dist := maxf(0.0, Vector2(p.x - (d["_c"] as Vector3).x, p.z - (d["_c"] as Vector3).z).length() - float(d["_r"]))
		d["_dist"] = dist
		if active.has(id):
			if dist > FREE_DIST and not pinned.has(id) and id != player_inside:
				_unload(id)
		elif dist < LOAD_DIST and not blocked.has(id):
			cand.append(id)
	cand.sort_custom(func(a, b): return float(defs[a]["_dist"]) < float(defs[b]["_dist"]))
	var budget := 2 if (not cand.is_empty() and float(defs[cand[0]]["_dist"]) < 6.0) else 1
	for id in cand:
		if budget <= 0:
			break
		_load(id)
		budget -= 1
	# 上限を超えたら遠いものから外す
	if active.size() > MAX_ACTIVE:
		var act: Array = active.keys()
		act.sort_custom(func(a, b): return float(defs[a].get("_dist", 0.0)) > float(defs[b].get("_dist", 0.0)))
		for id in act:
			if active.size() <= MAX_ACTIVE:
				break
			if not pinned.has(id) and id != player_inside:
				_unload(id)
	_budget_lights()
	_fire_inside(TICK)


func _viewer_pos() -> Vector3:
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and (pl as Node3D).is_inside_tree():
		return (pl as Node3D).global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		return cam.global_position
	return Vector3(0, -1e6, 0)


func _contains(d: Dictionary, wp: Vector3) -> bool:
	var lp: Vector3 = (d["_inv"] as Transform3D) * wp
	for f in d["floors"]:
		var y: float = f["y"]
		if lp.y < y - 0.6 or lp.y > y + float(f["h"]) + 0.2:
			continue
		if f.has("round"):
			if Vector2(lp.x, lp.z).length() < float(f["round"]) + 0.1:
				return true
		elif (f["rect"] as Rect2).grow(0.1).has_point(Vector2(lp.x, lp.z)):
			return true
	return false


# ================================================================ 生成・解放
func _load(id: int) -> void:
	if active.has(id):
		return
	var node: Node3D = pool.get(id)
	if node != null:
		pool.erase(id)
		pool_order.erase(id)
		add_child(node)
		active[id] = node
		stats["reused"] = int(stats["reused"]) + 1
		_apply_state(id)
		return
	var t0 := Time.get_ticks_usec()
	node = _build(defs[id])
	add_child(node)
	active[id] = node
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["built"] = int(stats["built"]) + 1
	stats["ms_total"] = float(stats["ms_total"]) + ms
	stats["ms_max"] = maxf(float(stats["ms_max"]), ms)
	_apply_state(id)


func _unload(id: int) -> void:
	var node: Node3D = active.get(id)
	if node == null:
		return
	active.erase(id)
	remove_child(node)
	stats["released"] = int(stats["released"]) + 1
	pool[id] = node
	pool_order.append(id)
	while pool_order.size() > POOL:
		var old: int = pool_order.pop_front()
		var on: Node3D = pool.get(old)
		pool.erase(old)
		if on:
			on.queue_free()


func _drop(id: int) -> void:
	# 完全に捨てる（倒壊など）
	if active.has(id):
		var n: Node3D = active[id]
		active.erase(id)
		n.queue_free()
	if pool.has(id):
		(pool[id] as Node3D).queue_free()
		pool.erase(id)
		pool_order.erase(id)
	_fire_fx.erase(id)
	pinned.erase(id)


func _build(d: Dictionary) -> Node3D:
	var b := InteriorBuilder.new(d, false)
	InteriorKits.build(b)
	var root := Node3D.new()
	root.name = "Interior_%d_%s" % [int(d["id"]), String(d["type"])]
	root.transform = d["xf"]
	if not b.kit.is_empty():
		var mi := b.kit.commit("Mesh", true)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# 建物シェーダの屋内の塗り（障子の透け・木と畳の暖色）
		mi.set_instance_shader_parameter("hs_indoor", 1.0)
		# 屋内は近くでしか見ないので、遠くでは描かない
		mi.visibility_range_end = FREE_DIST + 10.0
		root.add_child(mi)
	if not b.cols.is_empty():
		var sb := StaticBody3D.new()
		sb.name = "Body"
		sb.collision_layer = Game.COLLISION_WORLD
		sb.collision_mask = 0
		sb.add_to_group("interior")
		for c in b.cols:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = (c[1] as Vector3).max(Vector3(0.02, 0.02, 0.02))
			cs.shape = bs
			cs.transform = c[0]
			sb.add_child(cs)
		root.add_child(sb)
	var lights: Array = []
	for i in mini(b.lights.size(), 2):
		var l: Dictionary = b.lights[i]
		var ol := OmniLight3D.new()
		ol.name = "L%d" % i
		ol.position = l["p"]
		ol.light_color = l["c"]
		# 行灯・燭台の暖かい照り返しが部屋に回るよう、少し広く柔らかく
		ol.light_energy = float(l["e"]) * 1.25
		ol.omni_range = float(l["r"]) * 1.2
		ol.omni_attenuation = 0.9
		ol.shadow_enabled = false
		ol.light_specular = 0.2
		ol.visible = false
		ol.set_meta("e", float(l["e"]) * 1.25)
		root.add_child(ol)
		lights.append(ol)
	root.set_meta("lights", lights)
	root.set_meta("fire_pts", b.fire_pts)
	root.set_meta("tris", b.kit.vertex_count())
	return root


func _budget_lights() -> void:
	var act: Array = active.keys()
	act.sort_custom(func(a, b): return float(defs[a].get("_dist", 0.0)) < float(defs[b].get("_dist", 0.0)))
	var used := 0
	for id in act:
		var n: Node3D = active[id]
		for l in n.get_meta("lights", []):
			var ol := l as OmniLight3D
			if ol == null or not is_instance_valid(ol):
				continue
			var on: bool = used < MAX_LIGHTS and (id == player_inside or float(defs[id].get("_dist", 99.0)) < 14.0)
			ol.visible = on
			if on:
				used += 1
	stats["lights"] = used


# ================================================================ 破壊との連動
func _unit(id: int) -> Node:
	var d := Destruction.current
	if d == null or not is_instance_valid(d):
		return null
	return d.units.get(id)


## 屋根崩落・炎上は「損傷」: 入口を塞ぎ、中に誰もいなければ内装を消す
func _sync_damage() -> void:
	var dst := Destruction.current
	if dst == null or not is_instance_valid(dst):
		return
	for id in active.keys() + pool.keys():
		_check_unit(id)


func _check_unit(id: int) -> void:
	var u = _unit(id)
	if u == null:
		return
	if u.destroyed:
		if blocked.get(id, "") != "destroyed":
			on_destroyed(u)
		return
	var dmg: bool = int(u.stage) >= 2 or bool(u.burning)
	if not dmg:
		return
	var why := "burning" if u.burning else "damaged"
	if not blocked.has(id):
		blocked[id] = why
	if id != player_inside:
		_add_barrier(id)
		if active.has(id) and not pinned.has(id):
			_drop(id)
		elif pool.has(id):
			_drop(id)
	_apply_state(id)


func _apply_state(id: int) -> void:
	var u = _unit(id)
	var n: Node3D = active.get(id)
	if u == null or n == null:
		return
	if bool(u.burning) and not _fire_fx.has(id):
		_fire_fx[id] = _make_fire(n)
	if int(u.stage) >= 2 and not n.has_meta("rubble"):
		n.set_meta("rubble", true)
		var kit := MeshKit.new()
		var rr := RandomNumberGenerator.new()
		rr.seed = id
		var d: Dictionary = defs[id]
		var f: Dictionary = d["floors"][(d["floors"] as Array).size() - 1]
		var r: Rect2 = f["rect"]
		for k in 10:
			var p := Vector3(rr.randf_range(r.position.x, r.end.x), float(f["y"]) + 0.1, rr.randf_range(r.position.y, r.end.y))
			kit.box("darkwood" if k % 2 else "rooftile", Transform3D(Basis(Vector3.UP, rr.randf() * TAU).rotated(Vector3.RIGHT, rr.randf_range(-0.4, 0.4)), p), Vector3(rr.randf_range(0.3, 1.2), 0.12, rr.randf_range(0.2, 0.6)), Color(0.45, 0.38, 0.32))
		var mi := kit.commit("Rubble", false)
		n.add_child(mi)


func _add_barrier(id: int) -> void:
	if _barriers.has(id):
		return
	var d: Dictionary = defs[id]
	var sb := StaticBody3D.new()
	sb.name = "DoorBlock_%d" % id
	sb.collision_layer = Game.COLLISION_WORLD
	sb.collision_mask = 0
	for dd in d["doors"]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(dd["w"]) + 0.2, float(dd["h"]), 0.5)
		cs.shape = bs
		var n: Vector3 = dd["n"]
		cs.transform = Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), (dd["p"] as Vector3) + Vector3(0, float(dd["h"]) * 0.5, 0) + n * 0.1)
		sb.add_child(cs)
	sb.transform = d["xf"]
	add_child(sb)
	_barriers[id] = sb


## Destruction.destroy_unit から（倒壊の直前）。中にいたら外へ押し出してダメージ（即死させない）
func on_destroyed(u) -> void:
	var id: int = u.id
	if not defs.has(id):
		return
	blocked[id] = "destroyed"
	var inside := id == player_inside
	if not inside and is_instance_valid(Game.player):
		inside = _contains(defs[id], (Game.player as Node3D).global_position)
	_drop(id)
	if _barriers.has(id):
		(_barriers[id] as Node).queue_free()
		_barriers.erase(id)
	if inside:
		_push_out(id)
		player_inside = -1
		CameraRig.indoor = false


func _push_out(id: int) -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	var d: Dictionary = defs[id]
	var xf: Transform3D = d["xf"]
	var dd: Dictionary = d["doors"][0]
	var out: Vector3 = xf * (dd["out"] as Vector3)
	var n: Vector3 = (xf.basis * (dd["n"] as Vector3)).normalized()
	out += n * 1.5
	if world and world.has_method("height_at"):
		out.y = maxf(out.y, float(world.call("height_at", out.x, out.z)))
	var hp: float = float(pl.get("hp"))
	var dmg := clampf(hp - 20.0, 0.0, 45.0)
	if pl.has_method("teleport"):
		pl.teleport(out + Vector3.UP * 0.2)
	if pl is CharacterBody3D:
		(pl as CharacterBody3D).velocity = n * 6.0 + Vector3.UP * 3.0
	if dmg > 0.0 and pl.has_method("take_hit"):
		pl.take_hit(dmg, -1, out, n)
	Effects.shake = maxf(Effects.shake, 0.7)
	var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud and hud.has_method("toast"):
		hud.toast("建物が崩れた！ 外へ飛び出した")


func _on_enter(id: int) -> void:
	var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud and hud.has_method("toast"):
		var k: Dictionary = kits_info.get("kits", {}).get(String(defs[id]["type"]), {})
		var nm := String(k.get("name", ""))
		if nm != "":
			hud.toast(nm, 2.0)


# ================================================================ 屋内の火災
func _make_fire(n: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "IndoorFire"
	n.add_child(root)
	var pts: Array = n.get_meta("fire_pts", [])
	if pts.is_empty():
		pts = [Vector3.ZERO]
	for k in mini(pts.size(), 3):
		var fl := CPUParticles3D.new()
		fl.amount = 28
		fl.lifetime = 0.8
		fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		fl.emission_box_extents = Vector3(0.6, 0.2, 0.6)
		fl.direction = Vector3.UP
		fl.spread = 18.0
		fl.initial_velocity_min = 0.8
		fl.initial_velocity_max = 2.0
		fl.gravity = Vector3(0, 1.5, 0)
		fl.scale_amount_min = 1.0
		fl.scale_amount_max = 2.2
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.92, 0.45, 1.0))
		g.set_color(1, Color(0.85, 0.12, 0.04, 0.0))
		g.add_point(0.45, Color(1.0, 0.5, 0.1, 1.0))
		fl.color_ramp = g
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 1.0)
		q.material = Destruction._flame_mat()
		fl.mesh = q
		fl.position = pts[k]
		root.add_child(fl)
	var sm := CPUParticles3D.new()
	sm.amount = 14
	sm.lifetime = 4.0
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(2.0, 0.2, 2.0)
	sm.direction = Vector3(0.3, 1, 0)
	sm.initial_velocity_min = 0.3
	sm.initial_velocity_max = 0.8
	sm.gravity = Vector3(0.2, 0.1, 0)
	sm.scale_amount_min = 2.0
	sm.scale_amount_max = 4.0
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.3, 0.27, 0.27, 0.55))
	g2.set_color(1, Color(0.5, 0.48, 0.48, 0.0))
	sm.color_ramp = g2
	var q2 := QuadMesh.new()
	q2.material = Effects.particle_mat(Color.WHITE, false)
	sm.mesh = q2
	sm.position = (pts[0] as Vector3) + Vector3(0, 1.6, 0)
	root.add_child(sm)
	# 屋内の灯りを炎の色に
	for l in n.get_meta("lights", []):
		var ol := l as OmniLight3D
		if ol:
			ol.light_color = Color(1.0, 0.45, 0.15)
			ol.light_energy = 1.6
	return root


func _fire_inside(dt: float) -> void:
	if player_inside < 0 or not _fire_fx.has(player_inside):
		return
	_burn_t += dt
	var n: Node3D = active.get(player_inside)
	if n:
		for l in n.get_meta("lights", []):
			var ol := l as OmniLight3D
			if ol:
				ol.light_energy = 1.3 + sin(_burn_t * 17.0) * 0.25 + sin(_burn_t * 7.3) * 0.2
	if _burn_t >= 1.0:
		_burn_t = 0.0
		# 煙と熱で少しずつ（体力の 3 割までしか減らさない）
		var pl = Game.player
		if pl != null and is_instance_valid(pl) and pl.has_method("take_hit"):
			var hp: float = float(pl.get("hp"))
			var mx: float = float(pl.get("max_hp"))
			if hp > mx * 0.3:
				pl.take_hit(4.0, -1)


func debug_summary() -> String:
	var tris := 0
	for id in active:
		tris += int((active[id] as Node).get_meta("tris", 0))
	return "interiors: defs=%d active=%d pool=%d built=%d reused=%d avg=%.1fms max=%.1fms lights=%d verts=%d blocked=%d" % [
		ids.size(), active.size(), pool.size(), int(stats["built"]), int(stats["reused"]),
		float(stats["ms_total"]) / maxf(1.0, float(stats["built"])), float(stats["ms_max"]), int(stats["lights"]), tris, blocked.size()]

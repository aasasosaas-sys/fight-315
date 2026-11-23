class_name Destruction
extends Node3D
## ワールドの破壊システム（EraWorld の子。ワールドを作り直す＝時代に再入場するとリセット）。
## - 建物ユニット（Destructible）の生成・空間索引・状態テクスチャ（シェーダの destruct_tex）
## - 爆発の範囲被害（Effects.explosion から blast_at）・倒木・焦げ跡
## - 破片（RigidBody3D、プール・上限・眠ったら沈めて消す）・瓦礫・粉塵/木っ端/火の粉
## - 火災（木造は延焼。同時燃焼数と延焼回数に上限）
## - 手配度・被害カウンタ・Game.chaos_event（歴史シミュレーションへの通知）

static var current: Destruction

const TEX_W := 256
const CELL := 16.0
const MAX_DEBRIS := 64
const MAX_FIRES := 14
const MAX_FIRE_LIGHTS := 6
const MAX_FALLING_TREES := 24
const MAX_DECALS := 28
const FIRE_SPREAD_CAP := 36      # ランドマークごとの延焼回数の上限
const FIRE_CHAOS_STEPS := [5, 12, 24]
const DEBRIS_LIFE := Vector2(7.0, 11.0)

const MAT_FX := {
	"wood": [Color(0.58, 0.4, 0.26), Color(0.66, 0.58, 0.48, 0.85)],
	"plaster": [Color(0.93, 0.91, 0.86), Color(0.86, 0.83, 0.77, 0.85)],
	"stone": [Color(0.64, 0.62, 0.6), Color(0.74, 0.72, 0.68, 0.85)],
	"brick": [Color(0.74, 0.38, 0.3), Color(0.74, 0.6, 0.52, 0.85)],
	"metal": [Color(1.0, 0.8, 0.45), Color(0.45, 0.44, 0.43, 0.8)],
}

var world: Node3D
var era_id := ""
var units := {}                 # id -> Destructible
var _grid := {}                 # Vector2i -> Array[Destructible]
var _tree_grid := {}            # Vector2i -> PackedInt32Array
var _tree_dead := PackedByteArray()
var _img: Image
var _tex: ImageTexture
var _dirty := false
var _debris: Array = []         # [RigidBody3D, age, life]
var _pool: Array = []
var _fires: Array = []          # {u, fx, after, light}
var _falling: Array = []        # {node, t, axis, dur}
var _decals: Array = []
var _stumps: MultiMesh
var _stump_n := 0
var _fire_tick := 0.0
var _spread_tick := 0
var _fire_spread := {}          # landmark -> count
var _fire_chaos := {}           # landmark -> next step index
var _bridge_done := {}
var _units_root: Node3D
var stats := {"units": 0, "trees": 0, "ships": 0, "ryo": 0, "fires": 0}
var debris_peak := 0


static func attach(w: Node3D) -> Destruction:
	var d := Destruction.new()
	d.name = "Destruction"
	d.world = w
	d.era_id = String(w.get("era_id"))
	w.add_child(d)
	d._build()
	current = d
	return d


static func blast_at(_tree: SceneTree, pos: Vector3, radius: float, damage: float, team := -1, fire_chance := 0.2) -> void:
	if current != null and is_instance_valid(current) and current.is_inside_tree():
		current.blast(pos, radius, damage, team, fire_chance)


func _exit_tree() -> void:
	if current == self:
		current = null


func _build() -> void:
	var defs: Array = world.get("unit_defs")
	var max_id: int = int(world.get("next_unit_id"))
	var rows := maxi(2, int(ceil(float(max_id + 1) / TEX_W)) * 2)
	_img = Image.create(TEX_W, rows, false, Image.FORMAT_RGBAF)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	RenderingServer.global_shader_parameter_set("destruct_tex", _tex)
	_units_root = Node3D.new()
	_units_root.name = "Units"
	add_child(_units_root)
	for def in defs:
		var u := Destructible.new()
		u.setup(self, def)
		_units_root.add_child(u)
		units[u.id] = u
		var a := u.aabb
		for gx in range(_gi(a.position.x), _gi(a.end.x) + 1):
			for gz in range(_gi(a.position.z), _gi(a.end.z) + 1):
				var k := Vector2i(gx, gz)
				if not _grid.has(k):
					_grid[k] = []
				_grid[k].append(u)
	var trees: Array = world.get("tree_defs")
	_tree_dead.resize(trees.size())
	for i in trees.size():
		var o: Vector3 = (trees[i]["xf"] as Transform3D).origin
		var k := Vector2i(_gi(o.x), _gi(o.z))
		if not _tree_grid.has(k):
			_tree_grid[k] = PackedInt32Array()
		var arr: PackedInt32Array = _tree_grid[k]
		arr.append(i)
		_tree_grid[k] = arr
	print("[Destruction] %d units, %d trees" % [units.size(), trees.size()])


func _gi(v: float) -> int:
	return floori(v / CELL)


func units_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	var seen := {}
	for gx in range(_gi(p.x - r), _gi(p.x + r) + 1):
		for gz in range(_gi(p.z - r), _gi(p.z + r) + 1):
			var k := Vector2i(gx, gz)
			if not _grid.has(k):
				continue
			for u in _grid[k]:
				if seen.has(u):
					continue
				seen[u] = true
				out.append(u)
	return out


static func _aabb_dist(a: AABB, p: Vector3) -> float:
	var q := p.clamp(a.position, a.end)
	return q.distance_to(p)


# ================================================================ 状態テクスチャ
func push_state(u: Destructible) -> void:
	var x := u.id % TEX_W
	var y := (u.id / TEX_W) * 2
	if y + 1 >= _img.get_height():
		return
	var hb := u.hide_bits | (2 if u.roof_gone else 0)
	_img.set_pixel(x, y, Color(float(hb), u.char_amt, u.crack, 1.0 if u.burning else 0.0))
	if u.cut_y < 1e5:
		var amp := clampf((u.top_y - u.base_y) * 0.12, 0.25, 1.3)
		_img.set_pixel(x, y + 1, Color(u.cut_y, amp, 1.0, 0.0))
	_dirty = true


func _process(_dt: float) -> void:
	if _dirty:
		_dirty = false
		_tex.update(_img)
		# 他のワールド（タイトル背景など）に奪われていたら取り戻す
		RenderingServer.global_shader_parameter_set("destruct_tex", _tex)


# ================================================================ 爆発
func blast(pos: Vector3, radius: float, damage: float, _team := -1, fire_chance := 0.2) -> void:
	for u in units_near(pos, radius + 4.0):
		var du := u as Destructible
		if du.destroyed:
			continue
		var d := _aabb_dist(du.aabb, pos)
		if d > radius:
			continue
		var k := 1.0 - d / radius
		du.blast(damage * (0.3 + 0.7 * k), pos, fire_chance * (0.4 + 0.6 * k))
	# 倒木
	var rt := radius * 0.8
	var trees: Array = world.get("tree_defs")
	for gx in range(_gi(pos.x - rt), _gi(pos.x + rt) + 1):
		for gz in range(_gi(pos.z - rt), _gi(pos.z + rt) + 1):
			var key := Vector2i(gx, gz)
			if not _tree_grid.has(key):
				continue
			for i in (_tree_grid[key] as PackedInt32Array):
				if _tree_dead[i]:
					continue
				var o: Vector3 = (trees[i]["xf"] as Transform3D).origin
				var d := Vector2(o.x - pos.x, o.z - pos.z).length()
				if d < rt and absf(o.y - pos.y) < 10.0 and damage * (1.0 - d / rt) > 55.0:
					fell_tree(i, pos)
	_scorch(pos, radius)


# ================================================================ 被害の演出
func on_damage(u: Destructible, amount: float, point: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var mat: String = u.cfg["mat"]
	var fx: Array = MAT_FX.get(mat, MAT_FX["wood"])
	if now - u._fx_t > 0.12:
		u._fx_t = now
		var big := clampf(amount / 120.0, 0.3, 2.0)
		Effects.burst(get_tree(), point, Vector3.UP, fx[0], (fx[0] as Color).darkened(0.4), int(6 + 10 * big), 6.0 * big, 0.16, 0.9, 1.6, mat == "metal", 70)
		Effects.burst(get_tree(), point, Vector3.UP, fx[1], Color(fx[1], 0.0), int(3 + 4 * big), 1.5, 1.4 * big, 1.6, -0.05, false, 80)
	Wanted.report(point, minf(0.25, amount / u.max_hp * float(u.cfg["wanted"])))


## ひび段階: 小さな破片を少し落とす
func small_collapse(u: Destructible, point: Vector3, dir: Vector3) -> void:
	if u.palette.is_empty():
		u.palette = Fracture.material_palette(u.def)
	var n := 2 if bool(u.cfg.get("small", false)) else 4
	for k in n:
		var pick: Array = u.palette[randi() % mini(2, u.palette.size())] if not u.palette.is_empty() else ["stonewall", Color(0.8, 0.8, 0.8)]
		var kit := MeshKit.new()
		var s := Vector3(randf_range(0.25, 0.8), randf_range(0.1, 0.35), randf_range(0.25, 1.2))
		kit.box(pick[0], Transform3D.IDENTITY, s, pick[1], false)
		var p := point + Vector3(randf_range(-1, 1), randf_range(0, 1.5), randf_range(-1, 1))
		_spawn_one(kit.to_mesh(), p, s, (dir + Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1))).normalized() * randf_range(3, 7))
	Sfx.play_at(get_tree(), Sfx.wood_break() if u.cfg["mat"] == "wood" else Sfx.crumble(), point, -6.0)


func collapse_roof(u: Destructible, dir: Vector3) -> void:
	var ext := u.local_max - u.local_min
	var frame_g := u.frame * Transform3D(Basis(), u.local_min)
	var target := int(u.cfg["chunks"] * 0.6) + 2
	var c := clampf(pow(maxf(ext.x * ext.z * ext.y * 0.4, 1.0) / target, 1.0 / 3.0), 1.4, 7.0)
	var cell := _even_cell(ext, c)
	var chunks := Fracture.slice(u.def, 2, frame_g, cell, -INF, target, lerpf(1.0, 0.35, u.char_amt))
	push_state(u)
	var ctr := u.center()
	for ch in chunks:
		var p: Vector3 = ch["pos"]
		var out := p - ctr
		out.y = 0.0
		var v := out.normalized() * randf_range(1.5, 4.0) + dir * randf_range(0.0, 4.0) + Vector3.UP * randf_range(0.0, 2.0)
		_spawn_one(ch["mesh"], p, ch["size"], v)
	var top := Vector3(ctr.x, u.top_y - 0.5, ctr.z)
	Effects.burst(get_tree(), top, Vector3.UP, Color(0.5, 0.52, 0.56), Color(0.3, 0.3, 0.32), 30, 8.0, 0.25, 1.2, 1.6, false, 120)
	_dust(top, ext.length() * 0.35, MAT_FX["plaster"][1])
	Sfx.play_at(get_tree(), Sfx.tiles(), top, 0.0)
	Wanted.report(ctr, float(u.cfg["wanted"]) * 0.3)


func destroy_unit(u: Destructible, dir: Vector3, power: float) -> void:
	var ctr := u.center()
	var mat: String = u.cfg["mat"]
	if u.palette.is_empty():
		u.palette = Fracture.material_palette(u.def)
	stats["units"] = int(stats["units"]) + 1
	stats["ryo"] = int(stats["ryo"]) + int(u.cfg["value"])
	Wanted.report(ctr, float(u.cfg["wanted"]))
	get_tree().call_group("civilian", "panic", ctr)
	if u.kind == "boat":
		_sink(u)
		return
	var ext := u.local_max - u.local_min
	var small := bool(u.cfg.get("small", false))
	var full := u.kind == "bridge" or float(u.cfg["ruin"]) <= 0.0
	var h := maxf(u.top_y - u.base_y, 0.5)
	var cut := u.base_y + h * float(u.cfg["ruin"]) * randf_range(0.8, 1.2) * (0.6 if power > 1.2 else 1.0)
	if full:
		cut = u.base_y - 50.0
	# 破片（切断線より上）
	var frame_g := u.frame * Transform3D(Basis(), Vector3(u.local_min.x, cut - u.frame.origin.y, u.local_min.z))
	var above := maxf(u.top_y - cut, 0.5) if not full else ext.y
	if full:
		frame_g = u.frame * Transform3D(Basis(), u.local_min)
	var target: int = int(u.cfg["chunks"])
	var vol := maxf(ext.x * ext.z * above, 0.5)
	var c := clampf(pow(vol / target, 1.0 / 3.0), 0.7, 7.0)
	var ext2 := Vector3(ext.x, above, ext.z)
	var cell := _even_cell(ext2, c)
	var mask := 1 | (0 if u.roof_gone else 2)
	var chunks := Fracture.slice(u.def, mask, frame_g, cell, 0.0 if not full else -INF, int(target * 1.4), lerpf(1.0, 0.3, u.char_amt))
	if full:
		u.hide_bits = 3
	else:
		u.cut_y = cut
	u.roof_gone = true
	push_state(u)
	var sp := clampf(power, 0.5, 2.0)
	for ch in chunks:
		var p: Vector3 = ch["pos"]
		var out := p - ctr
		out.y = 0.0
		var v := out.normalized() * randf_range(1.0, 4.5) * sp + dir * randf_range(1.0, 6.0) * sp + Vector3.UP * randf_range(0.5, 4.0) * sp
		if u.kind == "bridge":
			v = Vector3(randf_range(-1, 1), randf_range(-1, 0.5), randf_range(-1, 1))
		_spawn_one(ch["mesh"], p, ch["size"], v)
	# 瓦礫・コリジョン
	if not full:
		var rh := clampf(h * 0.12, 0.25, 2.4) * (0.5 if small else 1.0)
		var rframe := u.frame * Transform3D(Basis(), Vector3((u.local_min.x + u.local_max.x) * 0.5, u.base_y - u.frame.origin.y, (u.local_min.z + u.local_max.z) * 0.5))
		var rext := Vector2(ext.x * 0.5 + 0.4, ext.z * 0.5 + 0.4)
		if small:
			rext *= 0.7
		var rm := Fracture.rubble(u.palette, Transform3D.IDENTITY, rext, rh, u.char_amt, u.id * 7919)
		var mi := MeshInstance3D.new()
		mi.name = "Rubble"
		mi.mesh = rm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		u.add_child(mi)
		mi.global_transform = rframe
		u.clip_collision(cut, small)
		if not small:
			u.add_rubble_collision(rh)
	else:
		u.clip_collision(-1e6, true)
	for m in u.def.get("models", []):
		if is_instance_valid(m):
			(m as Node3D).visible = false
	# 演出
	var fx: Array = MAT_FX.get(mat, MAT_FX["wood"])
	var r := ext.length() * 0.5
	if not small:
		_dust(Vector3(ctr.x, u.base_y + 0.5, ctr.z), r, fx[1])
		Effects.burst(get_tree(), ctr, Vector3.UP, fx[0], (fx[0] as Color).darkened(0.5), int(clampf(r * 6.0, 16, 60)), 9.0 * sp, 0.22, 1.4, 1.6, false, 100)
		Sfx.play_at(get_tree(), Sfx.crumble(), ctr, clampf(r * 0.6 - 2.0, -6.0, 6.0))
		if mat == "wood":
			Sfx.play_at(get_tree(), Sfx.wood_break(), ctr, 0.0)
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		if cam:
			Effects.shake = maxf(Effects.shake, clampf(r / 8.0 - cam.global_position.distance_to(ctr) / 120.0, 0.0, 0.8))
	else:
		Effects.burst(get_tree(), ctr, Vector3.UP, fx[0], (fx[0] as Color).darkened(0.4), 14, 6.0, 0.14, 0.9, 1.6, false, 100)
		Sfx.play_at(get_tree(), Sfx.wood_break() if mat == "wood" else Sfx.hit(), ctr, -4.0)
	if u.burning:
		for f in _fires:
			if f["u"] == u:
				var fxn: Node3D = f["fx"]
				if is_instance_valid(fxn):
					fxn.global_position = Vector3(ctr.x, u.base_y + 0.4, ctr.z)
	# 歴史シミュへ
	if u.kind == "bridge":
		var g: String = u.def.get("opts", {}).get("group", str(u.id))
		if not _bridge_done.has(g):
			_bridge_done[g] = true
			_chaos("bridge", u.landmark if u.landmark != "" else "river", {"type": u.def.get("opts", {}).get("kind_detail", "bridge"), "pos": ctr})
	elif bool(u.cfg["chaos"]):
		_chaos("destroy", _lm_id(u), {"type": u.kind, "detail": u.def.get("opts", {}).get("kind_detail", u.kind), "pos": ctr, "value": u.cfg["value"]})


func _lm_id(u: Destructible) -> String:
	if u.landmark == "" or u.landmark == "roads":
		return "town"
	return u.landmark


func _chaos(kind: String, id: String, info: Dictionary) -> void:
	info["era"] = era_id
	var g = get_node_or_null("/root/Game")
	if g and g.has_signal("chaos_event"):
		g.emit_signal("chaos_event", kind, id, info)


## 格子を範囲にぴったり割り切れる大きさに
func _even_cell(ext: Vector3, c: float) -> Vector3:
	return Vector3(ext.x / maxf(1.0, round(ext.x / c)), ext.y / maxf(1.0, round(ext.y / c)), ext.z / maxf(1.0, round(ext.z / c))).max(Vector3(0.3, 0.3, 0.3))


func _dust(p: Vector3, r: float, col: Color) -> void:
	var n := int(clampf(r * 3.0, 10, 40))
	Effects.burst(get_tree(), p, Vector3.UP, col, Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, 0.0), n, 3.0 + r * 0.25, clampf(r * 0.5, 2.0, 7.0), 3.5, -0.04, false, 90)
	# 地面を這う輪（アニメの土煙）
	Effects.burst(get_tree(), p + Vector3.UP * 0.2, Vector3.UP, col, Color(col, 0.0), n, 7.0 + r * 0.4, clampf(r * 0.35, 1.5, 4.5), 2.2, 0.0, false, 88)


# ================================================================ 沈没
func _sink(u: Destructible) -> void:
	var ctr := u.center()
	u.hide_bits = 3
	push_state(u)
	u.clip_collision(-1e6, true)
	var wl: float = float(world.get("water_level"))
	var nodes: Array = []
	var am := Fracture.whole(u.def, u.frame)
	if am:
		var mi := MeshInstance3D.new()
		mi.mesh = am
		u.add_child(mi)
		mi.global_transform = u.frame
		nodes.append(mi)
	for m in u.def.get("models", []):
		if is_instance_valid(m):
			nodes.append(m)
	var depth := (u.top_y - wl) + 4.0
	var tilt := randf_range(0.25, 0.45) * (1.0 if randf() < 0.5 else -1.0)
	for n in nodes:
		var nd := n as Node3D
		var start := nd.global_transform
		var pivot := Vector3(ctr.x, wl, ctr.z)
		var tw := nd.create_tween()
		tw.tween_method(func(t: float) -> void:
			if not is_instance_valid(nd):
				return
			var e := t * t
			var rot := Basis(u.frame.basis.x, tilt * minf(t * 2.0, 1.0)) * Basis(u.frame.basis.z, sin(t * 3.0) * 0.12)
			var rel := start.origin - pivot
			nd.global_transform = Transform3D(rot * start.basis, pivot + rot * rel + Vector3.DOWN * depth * e)
			, 0.0, 1.0, 11.0)
		tw.tween_callback(func() -> void:
			if is_instance_valid(nd):
				nd.visible = false)
	# 木っ端と水しぶき
	var chunks := Fracture.slice(u.def, 3, u.frame * Transform3D(Basis(), u.local_min), _even_cell(u.local_max - u.local_min, 3.0), -INF, 4, 0.8)
	for ch in chunks:
		_spawn_one(ch["mesh"], ch["pos"], ch["size"], Vector3(randf_range(-4, 4), randf_range(3, 7), randf_range(-4, 4)))
	var sp := Vector3(ctr.x, wl + 0.3, ctr.z)
	Effects.burst(get_tree(), sp, Vector3.UP, Color(0.85, 0.95, 1.0, 0.9), Color(0.6, 0.8, 0.95, 0.0), 50, 11.0, 1.2, 1.6, 1.4, false, 40)
	_dust(sp, (u.local_max - u.local_min).length() * 0.4, Color(0.9, 0.95, 1.0, 0.7))
	Sfx.play_at(get_tree(), Sfx.splash(), sp, 3.0)
	Sfx.play_at(get_tree(), Sfx.wood_break(), sp, 0.0)
	stats["ships"] = int(stats["ships"]) + 1
	if u.flammable:
		u.burning = false
		start_fire(u)
	_chaos("sink", _lm_id(u), {"type": "boat", "ship": u.def.get("opts", {}).get("ship", "boat"), "pos": ctr, "value": u.cfg["value"]})


# ================================================================ 破片
func _get_debris() -> RigidBody3D:
	var b: RigidBody3D
	if not _pool.is_empty():
		b = _pool.pop_back()
	elif _debris.size() >= MAX_DEBRIS:
		var old: Array = _debris.pop_front()
		b = old[0]
	else:
		b = RigidBody3D.new()
		b.name = "Debris"
		var mi := MeshInstance3D.new()
		mi.name = "M"
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.name = "S"
		cs.shape = BoxShape3D.new()
		b.add_child(cs)
		var pm := PhysicsMaterial.new()
		pm.friction = 0.85
		pm.bounce = 0.08
		b.physics_material_override = pm
		b.gravity_scale = 1.35
		b.angular_damp = 0.6
		b.linear_damp = 0.05
		b.can_sleep = true
		b.add_to_group("debris")
		add_child(b)
	return b


func _spawn_one(mesh: Mesh, pos: Vector3, size: Vector3, vel: Vector3) -> void:
	var b := _get_debris()
	var mi := b.get_node("M") as MeshInstance3D
	var cs := b.get_node("S") as CollisionShape3D
	mi.mesh = mesh
	mi.scale = Vector3.ONE
	mi.position = Vector3.ZERO
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if size.length() > 2.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(cs.shape as BoxShape3D).size = (size * 0.8).max(Vector3(0.12, 0.12, 0.12))
	cs.disabled = false
	b.collision_layer = Game.COLLISION_DEBRIS
	b.collision_mask = Game.COLLISION_WORLD | Game.COLLISION_DEBRIS
	b.mass = clampf(size.x * size.y * size.z * 60.0, 3.0, 500.0)
	b.freeze = false
	b.visible = true
	b.process_mode = Node.PROCESS_MODE_INHERIT
	b.global_transform = Transform3D(Basis(), pos)
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * randf_range(1.0, 4.0) / maxf(1.0, size.length() * 0.5)
	b.sleeping = false
	_debris.append([b, 0.0, randf_range(DEBRIS_LIFE.x, DEBRIS_LIFE.y)])
	debris_peak = maxi(debris_peak, _debris.size())


func _retire(b: RigidBody3D) -> void:
	b.freeze = true
	b.visible = false
	b.collision_layer = 0
	b.collision_mask = 0
	(b.get_node("S") as CollisionShape3D).disabled = true
	(b.get_node("M") as MeshInstance3D).mesh = null
	_pool.append(b)


func live_debris() -> int:
	return _debris.size()


func _physics_process(dt: float) -> void:
	# 破片: 寿命が来たら地面へ沈めて回収
	var i := 0
	while i < _debris.size():
		var e: Array = _debris[i]
		var b: RigidBody3D = e[0]
		e[1] = float(e[1]) + dt
		var life: float = e[2]
		if float(e[1]) > life:
			if not b.freeze:
				b.freeze = true
				(b.get_node("S") as CollisionShape3D).disabled = true
			var k := (float(e[1]) - life) / 1.6
			b.global_position.y -= dt * 0.9
			(b.get_node("M") as MeshInstance3D).scale = Vector3.ONE * maxf(0.05, 1.0 - k * 0.7)
			if k >= 1.0:
				_debris.remove_at(i)
				_retire(b)
				continue
		elif b.global_position.y < -80.0:
			_debris.remove_at(i)
			_retire(b)
			continue
		i += 1
	# 倒木
	var j := 0
	while j < _falling.size():
		var f: Dictionary = _falling[j]
		var nd: Node3D = f["node"]
		f["t"] = float(f["t"]) + dt
		var t: float = f["t"]
		if not is_instance_valid(nd):
			_falling.remove_at(j)
			continue
		var dur: float = f["dur"]
		var ang: float
		if t < dur:
			ang = 1.45 * pow(t / dur, 2.2)
		else:
			ang = 1.45 + sin(minf((t - dur) * 9.0, PI)) * 0.06 * exp(-(t - dur) * 3.0)
			if not bool(f["landed"]):
				f["landed"] = true
				var tip: Vector3 = nd.global_position + Basis(f["axis"], 1.45) * Vector3.UP * float(f["h"]) * 0.6
				Effects.burst(get_tree(), tip, Vector3.UP, f["leaf"], Color(f["leaf"], 0.0), 26, 5.0, 0.4, 1.4, 0.6, false, 120)
				_dust(nd.global_position + (tip - nd.global_position) * 0.5, 3.0, Color(0.66, 0.6, 0.5, 0.7))
				Sfx.play_at(get_tree(), Sfx.wood_break(), tip, -3.0)
		nd.global_transform.basis = Basis(f["axis"], ang)
		if t > dur + 6.0:
			nd.global_position.y -= dt * 0.8
			if t > dur + 8.0:
				nd.queue_free()
				_falling.remove_at(j)
				continue
		j += 1
	# 火災
	_fire_tick += dt
	if _fire_tick >= 0.5:
		_fire_tick -= 0.5
		_fire_step(0.5)


# ================================================================ 倒木
func fell_tree(i: int, from: Vector3) -> void:
	if _tree_dead[i]:
		return
	_tree_dead[i] = 1
	var td: Dictionary = (world.get("tree_defs") as Array)[i]
	var xf: Transform3D = td["xf"]
	for inst in td["inst"]:
		(inst[0] as MultiMesh).set_instance_transform(inst[1], Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin + Vector3.DOWN * 500.0))
	var col = td.get("col")
	if col != null and is_instance_valid(col):
		(col as CollisionShape3D).set_deferred("disabled", true)
	stats["trees"] = int(stats["trees"]) + 1
	_add_stump(xf)
	var sp: String = td["sp"]
	var leaf: Color = WorldVegetation.SPECIES.get(sp, {}).get("c2", Color(0.3, 0.5, 0.2))
	if _falling.size() >= MAX_FALLING_TREES:
		Effects.burst(get_tree(), xf.origin + Vector3.UP * 4.0, Vector3.UP, leaf, Color(leaf, 0.0), 20, 4.0, 0.4, 1.2, 0.5, false, 120)
		return
	var meshes: Array = WorldVegetation.species_meshes(sp)
	var pivot := Node3D.new()
	pivot.name = "FallingTree"
	var mi := MeshInstance3D.new()
	mi.mesh = meshes[0]
	mi.transform = Transform3D(xf.basis, Vector3.ZERO)
	pivot.add_child(mi)
	add_child(pivot)
	pivot.global_position = xf.origin
	var away := xf.origin - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var axis := Vector3.UP.cross(away.normalized()).normalized()
	var h := (meshes[0] as Mesh).get_aabb().end.y * xf.basis.get_scale().y
	_falling.append({"node": pivot, "t": 0.0, "axis": axis, "dur": randf_range(1.2, 1.8), "landed": false, "h": h, "leaf": leaf})
	Sfx.play_at(get_tree(), Sfx.wood_break(), xf.origin + Vector3.UP, -4.0)


func _add_stump(xf: Transform3D) -> void:
	if _stumps == null:
		_stumps = MultiMesh.new()
		_stumps.transform_format = MultiMesh.TRANSFORM_3D
		var kit := MeshKit.new()
		kit.cylinder("darkwood", Transform3D(Basis(), Vector3(0, -0.3, 0)), 0.36, 0.3, 1.0, 7, Color(0.62, 0.5, 0.4))
		kit.cylinder("wood", Transform3D(Basis(), Vector3(0, 0.68, 0)), 0.3, 0.05, 0.25, 7, Color(0.95, 0.85, 0.65))
		_stumps.mesh = kit.to_mesh()
		_stumps.instance_count = 512
		_stumps.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Stumps"
		mmi.multimesh = _stumps
		add_child(mmi)
	if _stump_n >= _stumps.instance_count:
		return
	var sc := xf.basis.get_scale().y
	_stumps.set_instance_transform(_stump_n, Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * sc), xf.origin))
	_stump_n += 1
	_stumps.visible_instance_count = _stump_n


# ================================================================ 焦げ跡
static var _scorch_tex: Texture2D


func _scorch(pos: Vector3, radius: float) -> void:
	var g: float = world.call("height_at", pos.x, pos.z)
	if pos.y - g > 4.0:
		return
	if _scorch_tex == null:
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		var n := FastNoiseLite.new()
		n.frequency = 0.06
		for y in 128:
			for x in 128:
				var d := Vector2(x - 63.5, y - 63.5).length() / 64.0
				var nn := n.get_noise_2d(x, y) * 0.35
				var a := clampf((1.0 - d + nn) * 1.6, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.07, 0.055, 0.05, a * 0.85))
		_scorch_tex = ImageTexture.create_from_image(img)
	var dc: Decal
	if _decals.size() >= MAX_DECALS:
		dc = _decals.pop_front()
	else:
		dc = Decal.new()
		dc.texture_albedo = _scorch_tex
		dc.cull_mask = 1
		add_child(dc)
	_decals.append(dc)
	var s := radius * 1.3
	dc.size = Vector3(s, 6.0, s)
	dc.global_position = Vector3(pos.x, g, pos.z)
	dc.rotation.y = randf() * TAU


# ================================================================ 火災
func start_fire(u: Destructible) -> void:
	if u.burning or _fires.size() >= MAX_FIRES:
		return
	var lm := _lm_id(u)
	u.burning = true
	stats["fires"] = int(stats["fires"]) + 1
	var fx := _make_fire_fx(u, _fire_light_count() < MAX_FIRE_LIGHTS)
	_fires.append({"u": u, "fx": fx, "after": 0.0})
	push_state(u)
	var cnt: int = int(_fire_spread.get(lm, 0)) + 1
	_fire_spread[lm] = cnt
	var step: int = int(_fire_chaos.get(lm, 0))
	if step < FIRE_CHAOS_STEPS.size() and cnt >= int(FIRE_CHAOS_STEPS[step]):
		_fire_chaos[lm] = step + 1
		_chaos("fire", lm, {"count": cnt, "pos": u.center(), "type": u.kind})


func burning_count() -> int:
	return _fires.size()


func _fire_light_count() -> int:
	var n := 0
	for f in _fires:
		if is_instance_valid(f["fx"]) and (f["fx"] as Node).has_node("L"):
			n += 1
	return n


func _fire_step(dt: float) -> void:
	_spread_tick += 1
	var spread := _spread_tick % 3 == 0
	var k := 0
	while k < _fires.size():
		var f: Dictionary = _fires[k]
		var u: Destructible = f["u"]
		if not is_instance_valid(u):
			_fires.remove_at(k)
			continue
		u.burn_step(dt)
		if u.destroyed:
			f["after"] = float(f["after"]) + dt
			if float(f["after"]) > 9.0:
				u.burning = false
				push_state(u)
				var fxn: Node3D = f["fx"]
				if is_instance_valid(fxn):
					for c in fxn.get_children():
						if c is CPUParticles3D:
							(c as CPUParticles3D).emitting = false
					var tw := fxn.create_tween()
					tw.tween_interval(4.0)
					tw.tween_callback(fxn.queue_free)
				_fires.remove_at(k)
				continue
		elif spread:
			var lm := _lm_id(u)
			if int(_fire_spread.get(lm, 0)) < FIRE_SPREAD_CAP and _fires.size() < MAX_FIRES:
				for n in units_near(u.center(), 10.0):
					var nu := n as Destructible
					if nu == u or nu.burning or nu.destroyed or not nu.flammable:
						continue
					var d := _aabb_dist(nu.aabb, u.center()) - u.aabb.size.length() * 0.35
					if d < 5.0 and randf() < 0.16 * (1.0 - clampf(d / 5.0, 0.0, 1.0)) + 0.04:
						start_fire(nu)
						break
		k += 1


func _make_fire_fx(u: Destructible, with_light: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	add_child(root)
	var ext := (u.local_max - u.local_min) * 0.5
	var ctr := u.center()
	var y := u.top_y - 1.0 if not u.destroyed else u.base_y + 0.4
	if u.kind == "boat":
		y = float(world.get("water_level")) + 1.0
	root.global_position = Vector3(ctr.x, maxf(y, u.base_y + 0.5), ctr.z)
	var fl := CPUParticles3D.new()
	fl.name = "Flames"
	fl.amount = 28
	fl.lifetime = 0.9
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fl.emission_box_extents = Vector3(maxf(ext.x * 0.7, 0.4), 0.5, maxf(ext.z * 0.7, 0.4))
	fl.direction = Vector3.UP
	fl.spread = 15.0
	fl.initial_velocity_min = 2.0
	fl.initial_velocity_max = 4.5
	fl.gravity = Vector3(0, 2.0, 0)
	fl.scale_amount_min = 1.2
	fl.scale_amount_max = clampf(ext.length() * 0.45, 1.6, 4.0)
	var c1 := Curve.new()
	c1.add_point(Vector2(0, 0.4)); c1.add_point(Vector2(0.3, 1.0)); c1.add_point(Vector2(1, 0.1))
	fl.scale_amount_curve = c1
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	g.set_color(1, Color(0.9, 0.12, 0.02, 0.0))
	g.add_point(0.35, Color(1.0, 0.55, 0.12, 0.95))
	fl.color_ramp = g
	var q := QuadMesh.new()
	q.material = Effects.particle_mat(Color.WHITE, true)
	fl.mesh = q
	fl.local_coords = false
	root.add_child(fl)
	var sm := CPUParticles3D.new()
	sm.name = "Smoke"
	sm.amount = 14
	sm.lifetime = 4.5
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sm.emission_box_extents = fl.emission_box_extents * 0.6
	sm.direction = Vector3(0.2, 1, 0.1)
	sm.spread = 12.0
	sm.initial_velocity_min = 2.0
	sm.initial_velocity_max = 3.5
	sm.gravity = Vector3(0.6, 0.4, 0.2)
	sm.scale_amount_min = 2.5
	sm.scale_amount_max = clampf(ext.length() * 0.8, 3.0, 8.0)
	var c2 := Curve.new()
	c2.add_point(Vector2(0, 0.3)); c2.add_point(Vector2(1, 1.0))
	sm.scale_amount_curve = c2
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.25, 0.22, 0.22, 0.75))
	g2.set_color(1, Color(0.5, 0.48, 0.48, 0.0))
	sm.color_ramp = g2
	var q2 := QuadMesh.new()
	q2.material = Effects.particle_mat(Color.WHITE, false)
	sm.mesh = q2
	sm.local_coords = false
	sm.position = Vector3(0, 1.5, 0)
	root.add_child(sm)
	if with_light:
		var l := OmniLight3D.new()
		l.name = "L"
		l.light_color = Color(1.0, 0.55, 0.2)
		l.light_energy = 2.2
		l.omni_range = clampf(ext.length() * 2.5, 8.0, 22.0)
		l.position = Vector3(0, 1.0, 0)
		root.add_child(l)
	var snd := Sfx.loop_player(root, Sfx.fire_loop(), -8.0)
	if snd:
		snd.max_distance = 70.0
		snd.play()
	return root


# ================================================================ HUD 用
func summary_text() -> String:
	var parts: Array = ["破壊 %d" % int(stats["units"])]
	if int(stats["trees"]) > 0:
		parts.append("倒木 %d" % int(stats["trees"]))
	if int(stats["ships"]) > 0:
		parts.append("撃沈 %d" % int(stats["ships"]))
	if _fires.size() > 0:
		parts.append("炎上中 %d" % _fires.size())
	parts.append("被害 %s両" % _commas(int(stats["ryo"])))
	return "  ".join(parts)


static func _commas(v: int) -> String:
	var s := str(v)
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		var rem := n - i - 1
		if rem > 0 and rem % 3 == 0:
			out += ","
	return out

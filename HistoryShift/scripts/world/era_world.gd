class_name EraWorld
extends Node3D
## 時代ごとのオープンワールド。地形・水・植生・建築・小道具・空/光を手続き生成する。
## 使い方: var w := EraWorld.build(Game.db.get_era("heian")); add_child(w)

# ---- 品質設定（UI の設定画面が build 前に書き換える）
static var quality := 2              # 0=低 1=中 2=高
static var sdfgi_enabled := true
static var ssao_enabled := true
static var ssil_enabled := true
static var volumetric_enabled := true
static var glow_enabled := true
static var grass_enabled := true
static var taa_enabled := true      # 高品質時にビューポートの TAA を有効化（葉のちらつき低減）

## 正準レイアウト（海が +Z 側）。時代ごとに 90° 単位で回転する
const CANON := {
	"capital": {"pos": Vector2(0, -38), "r": 70.0},
	"village": {"pos": Vector2(-122, 42), "r": 50.0},
	"temple": {"pos": Vector2(128, -108), "r": 40.0},
	"port": {"pos": Vector2(150, 132), "r": 40.0},
	"castle": {"pos": Vector2(-122, -112), "r": 50.0},
	"battlefield": {"pos": Vector2(45, 76), "r": 28.0, "half_len": 50.0},
	"mountain": {"pos": Vector2(0, -178), "r": 24.0},
}
## 昭和は滑走路（約 330m）を確保するため戦場と村・港の位置を変える
const CANON_SHOWA := {
	"village": {"pos": Vector2(-138, 8), "r": 48.0},
	"battlefield": {"pos": Vector2(-25, 98), "r": 25.0, "half_len": 140.0},
	"port": {"pos": Vector2(168, 142), "r": 38.0},
}
## 西の境界を流れる川
const RIVER_CANON := [Vector2(-196, -260), Vector2(-200, -150), Vector2(-198, -40), Vector2(-192, 80),
	Vector2(-186, 170), Vector2(-180, 260)]
const ROADS := [["capital", "village", 4.0], ["capital", "castle", 3.5], ["capital", "temple", 3.5],
	["capital", "battlefield", 4.0], ["capital", "port", 4.0], ["capital", "mountain", 3.0],
	["village", "castle", 3.0], ["village", "battlefield", 3.0], ["battlefield", "port", 3.5], ["temple", "port", 3.0]]

var era: Dictionary
var era_id := ""
var style: Dictionary
var half_size := 600.0
var water_level := 0.0
var player_spawn := Vector3.ZERO
var terrain: TerrainGen
var landmarks := {}      # key -> {pos:Vector3, center:Vector2, r, angle, xf:Transform3D, h}
var beacons := {}
var _vehicle_spawns := {"horse": [], "car": [], "plane": []}
var _street_points: Array = []
var env_nodes := {}
var grass_node: MultiMeshInstance3D
var grass_spacing := 0.5
var build_ms := 0
var rng := RandomNumberGenerator.new()
var height_tex: ImageTexture
var control_tex: ImageTexture
var static_body: StaticBody3D   # 建物などのコリジョン
var deco_trees: Array = []      # [species, Vector3, scale]（建築側が植える木）
var pond_requests: Array = []   # 池（建築側が要求）
var next_unit_id := 0           # 破壊ユニットの ID（Architecture.begin_unit が採番）
var unit_defs: Array = []       # 破壊ユニットの定義（Destruction が Destructible に変換）
var tree_defs: Array = []       # 倒せる木 [species, Transform3D, [MultiMesh, index]...]
var destruction: Destruction    # 破壊システム（ワールドごとに作り直し＝再入場でリセット）
var interior_defs: Array = []   # 入れる建物（Architecture.reg_interior が登録。内装は WorldInteriors が近づいた時だけ生成）
var interiors: WorldInteriors


static func build(p_era: Dictionary) -> EraWorld:
	var t0 := Time.get_ticks_msec()
	var w := EraWorld.new()
	w.name = "EraWorld"
	w.era = p_era
	w.era_id = String(p_era.get("eraId", "heian"))
	w._build()
	w.build_ms = Time.get_ticks_msec() - t0
	print("[EraWorld] %s built in %d ms" % [w.era_id, w.build_ms])
	return w


static var debug_timing := false
var _t_last := 0


func _tick(label: String) -> void:
	if debug_timing:
		var now := Time.get_ticks_msec()
		print("  [build] %s: %d ms" % [label, now - _t_last])
		_t_last = now


func _build() -> void:
	_t_last = Time.get_ticks_msec()
	style = EraStyles.get_style(era_id)
	var seed_v := hash(era_id) & 0x7fffffff
	rng.seed = seed_v
	terrain = TerrainGen.new(int(style["rot"]), seed_v % 100000)
	terrain.water_level = water_level
	half_size = terrain.half

	# ---- 地形
	terrain.generate_base()
	terrain.carve_river(RIVER_CANON)
	_setup_landmarks()
	var layouts := WorldLayouts.new(self)
	layouts.plan_terrain()
	_make_roads()
	terrain.apply_roads()
	layouts.terrain_features()
	_tick("terrain")

	static_body = StaticBody3D.new()
	static_body.name = "StaticWorld"
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)

	# ---- 建築（マスクや占有も塗る）
	layouts.build_all()
	_tick("architecture")
	var zones: Array = []
	for key in landmarks:
		var info: Dictionary = landmarks[key]
		if key == "mountain":
			continue
		zones.append([info.get("a", info["center"]), info.get("b", info["center"]), info["r"]])
	terrain.compute_forest(float(style["forest"]), zones)
	_tick("forest mask")

	# ---- メッシュ・コリジョン
	height_tex = ImageTexture.create_from_image(terrain.make_height_image())
	control_tex = ImageTexture.create_from_image(terrain.make_control_image())
	WorldMaterials.set_world_params(height_tex, half_size, TerrainGen.N)
	var tnode := Node3D.new()
	tnode.name = "Terrain"
	add_child(tnode)
	_tick("textures")
	var tmat := _terrain_material()
	terrain.build_meshes(tnode, tmat, quality)
	terrain.build_outer(tnode, tmat)
	add_child(terrain.make_collision())
	_tick("terrain mesh")

	_build_water()
	var veg := WorldVegetation.new(self)
	veg.build()
	_tick("vegetation")
	if grass_enabled:
		_build_grass()
	WorldProps.new(self).build()
	_tick("props")
	destruction = Destruction.attach(self)
	_tick("destruction")
	interiors = WorldInteriors.attach(self)
	_tick("interiors")
	env_nodes = WorldAtmosphere.build_environment(self, style)
	for key in landmarks:
		var b := WorldAtmosphere.make_beacon(landmarks[key]["pos"])
		b.name = "Beacon_" + key
		add_child(b)
		beacons[key] = b
	_compute_vehicle_spawns(layouts)


func _ready() -> void:
	if taa_enabled and quality >= 2 and get_viewport():
		get_viewport().use_taa = true
	if get_viewport():
		# 輪郭線・水の深度表現は深度テクスチャを読むため MSAA を切り、画面空間 AA（FXAA）で代替する
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var g = get_node_or_null("/root/Game")
	if g and g.get("world") == null and g.has_method("set_world"):
		g.set_world(self)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	var cam0 := vp.get_camera_3d() if vp else null
	if cam0:
		WorldAtmosphere.update_post(env_nodes.get("post"), env_nodes.get("sun"), cam0)
	if not grass_nodes.is_empty():
		var cam := cam0
		if cam:
			var p := to_local(cam.global_position)
			for g in grass_nodes:
				var sp: float = g[1]
				(g[0] as Node3D).position = Vector3(snappedf(p.x, sp), 0.0, snappedf(p.z, sp))


# ================================================================ 公開 API
func landmark_pos(key: String) -> Vector3:
	if landmarks.has(key):
		return landmarks[key]["pos"]
	return player_spawn


func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func random_ground_point_near(center: Vector3, radius: float, p_rng: RandomNumberGenerator) -> Vector3:
	var best := Vector3(center.x, height_at(center.x, center.z), center.z)
	for attempt in 40:
		var r := radius * sqrt(p_rng.randf())
		var a := p_rng.randf() * TAU
		var x := clampf(center.x + cos(a) * r, -half_size + 5.0, half_size - 5.0)
		var z := clampf(center.z + sin(a) * r, -half_size + 5.0, half_size - 5.0)
		if terrain.is_water(x, z):
			continue
		if terrain.is_occupied(x, z):
			continue
		if terrain.normal_at(x, z).y < 0.82:
			continue
		return Vector3(x, height_at(x, z), z)
	return best


func set_beacon(key: String, on: bool) -> void:
	if beacons.has(key):
		beacons[key].visible = on


func vehicle_spawns(kind: String) -> Array:
	if not (kind in era.get("vehicles", [])):
		return []
	return _vehicle_spawns.get(kind, []).duplicate()


func street_points() -> Array:
	return _street_points.duplicate()


func set_time_of_day(hours: float) -> void:
	var sun: DirectionalLight3D = env_nodes.get("sun")
	var env: Environment = env_nodes.get("env")
	if sun == null or env == null:
		return
	# 6 時に日の出、18 時に日没。空はシェーダが太陽の向きに追従する
	var t := (hours - 6.0) / 12.0
	var elev := sin(clampf(t, -0.2, 1.2) * PI) * 62.0
	var az := float(style["sun_az"]) + (t - 0.5) * 120.0
	var day := clampf((elev + 3.0) / 15.0, 0.0, 1.0)
	if elev < -2.0:
		# 夜: 月明かり（青白い弱い光）として太陽ライトを流用
		WorldAtmosphere.set_sun_dir(sun, az + 180.0, 35.0)
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = 0.18
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	else:
		WorldAtmosphere.set_sun_dir(sun, az, elev)
		var low := 1.0 - clampf(elev / 25.0, 0.0, 1.0)
		sun.light_color = (style["sun_color"] as Color).lerp(style["sunset_color"], low * 0.6)
		sun.light_energy = float(style["sun_energy"]) * 0.85 * lerpf(0.35, 1.0, day)
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	sun.visible = true
	env.ambient_light_energy = lerpf(0.14, float(style["ambient_energy"]), day)
	env.fog_light_color = Color(0.1, 0.13, 0.24).lerp(style["aerial"], day)
	var sky_mat: ShaderMaterial = env_nodes.get("sky_mat")
	if sky_mat:
		sky_mat.set_shader_parameter("night", 1.0 if elev < -2.0 else 0.0)
	WorldAtmosphere.apply_toon_globals(style, day)
	if is_inside_tree():
		for l in get_tree().get_nodes_in_group("world_night_light"):
			if is_ancestor_of(l):
				l.visible = day < 0.35


# ---- 屋内（scripts/world/interiors/）
## 建物（破壊ユニット ID）の屋内の NPC 地点（ワールド座標）。内装を生成していなくても返す
func get_interior_points(unit_id: int) -> Array:
	var out: Array = []
	if interiors:
		for s in interiors.spots(unit_id):
			out.append(s["pos"])
	return out


## 地点の詳細: [{pos, yaw, floor, role(stand/sit/work/guard/scene)}]
func get_interior_spots(unit_id: int) -> Array:
	return interiors.spots(unit_id) if interiors else []


## 史実の場面の建物（"honnoji" "omiya" "tenshu" "rokumeikan" など、data/interiors/kits.json の scenes）。無ければ -1
func find_interior(tag: String) -> int:
	return interiors.find(tag) if interiors else -1


## 入れる建物の ID 一覧（type: 内装キット名、landmark で絞り込み）
func find_interiors(type := "", landmark := "") -> Array:
	return interiors.find_all(type, landmark) if interiors else []


## {id, type, name, basis, era, landmark, floors, tags, doors:[{pos, out, normal}], loaded, blocked}
func get_interior_info(unit_id: int) -> Dictionary:
	return interiors.info(unit_id) if interiors else {}


## 内装をすぐ生成する（上階に NPC を立たせる前など）。pin=true の間は離れても外さない
func ensure_interior(unit_id: int, pin := true) -> Node3D:
	return interiors.ensure(unit_id, pin) if interiors else null


func release_interior(unit_id: int) -> void:
	if interiors:
		interiors.release(unit_id)


## p がどの建物の中か（-1 = 屋外）
func interior_at(p: Vector3) -> int:
	return interiors.inside_at(p) if interiors else -1


func add_street_point(p: Vector3) -> void:
	_street_points.append(p)


# ================================================================ 内部
func _setup_landmarks() -> void:
	var names := {}
	for lm in era.get("landmarks", []):
		names[lm["key"]] = lm.get("name", lm["key"])
	var ang := terrain.canon_basis_angle()
	for key in CANON:
		var c: Dictionary = CANON[key]
		if era_id == "showa" and CANON_SHOWA.has(key):
			c = CANON_SHOWA[key]
		var wpos := terrain.canon_to_world(c["pos"])
		var r: float = c["r"]
		var hh: float
		match key:
			"port":
				hh = 2.4
			"mountain":
				hh = clampf(terrain.sample_grid(wpos.x, wpos.y), 14.0, 30.0)
			_:
				hh = clampf(terrain.sample_grid(wpos.x, wpos.y), 3.5, 14.0)
		var info := {"key": key, "center": wpos, "r": r, "h": hh, "angle": ang, "name": names.get(key, key)}
		if c.has("half_len"):
			var dir := terrain.canon_to_world(Vector2(1, 0))
			info["a"] = wpos - dir * float(c["half_len"])
			info["b"] = wpos + dir * float(c["half_len"])
		info["xf"] = Transform3D(Basis(Vector3.UP, ang), Vector3(wpos.x, hh, wpos.y))
		info["pos"] = Vector3(wpos.x, hh, wpos.y)
		landmarks[key] = info
	for key in landmarks:
		var info: Dictionary = landmarks[key]
		var fall := 34.0
		if key == "mountain":
			fall = 22.0
		if info.has("a"):
			terrain.flatten(info["a"], info["r"], fall, info["h"], info["b"])
		elif key == "port":
			_flatten_port(info)
		else:
			terrain.flatten(info["center"], info["r"], fall, info["h"])


func _flatten_port(info: Dictionary) -> void:
	# 海側は持ち上げない（岸線を保つ）
	var c: Vector2 = info["center"]
	var r: float = info["r"]
	var fall := 24.0
	var tg: float = info["h"]
	for j in range(terrain.gi(c.y - r - fall), terrain.gi(c.y + r + fall) + 1):
		for i in range(terrain.gi(c.x - r - fall), terrain.gi(c.x + r + fall) + 1):
			var p := Vector2(terrain.gx(i), terrain.gx(j))
			var d := p.distance_to(c)
			var id := j * TerrainGen.N + i
			var hh: float = terrain.h[id]
			if hh < water_level + 0.3:
				continue
			var t := 1.0 - smoothstep(r, r + fall, d)
			terrain.h[id] = lerpf(hh, maxf(tg, minf(hh, tg)), t) if hh > tg else lerpf(hh, tg, t * clampf((hh - water_level) / 1.5, 0.0, 1.0))


func lm_edge_point(key: String, toward: Vector2) -> Vector2:
	var info: Dictionary = landmarks[key]
	if info.has("a"):
		var a: Vector2 = info["a"]
		var b: Vector2 = info["b"]
		var ab := b - a
		var t := clampf((toward - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var p := a + ab * t
		return p + (toward - p).normalized() * (float(info["r"]) * 0.8)
	var c: Vector2 = info["center"]
	return c + (toward - c).normalized() * (float(info["r"]) * 0.85)


func _make_roads() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = rng.seed + 5
	for spec in ROADS:
		var a_key: String = spec[0]
		var b_key: String = spec[1]
		var ca: Vector2 = landmarks[a_key]["center"]
		var cb: Vector2 = landmarks[b_key]["center"]
		if b_key == "mountain":
			# 山道は九十九折り
			var mid := terrain.canon_to_world(Vector2(70, -125))
			var pa := lm_edge_point(a_key, mid)
			var mid2 := terrain.canon_to_world(Vector2(45, -168))
			var pb := lm_edge_point(b_key, mid2)
			terrain.add_road(pa, mid, spec[2], 10.0, rr)
			terrain.add_road(mid, mid2, spec[2], 5.0, rr)
			terrain.add_road(mid2, pb, spec[2], 5.0, rr)
			continue
		var pa := lm_edge_point(a_key, cb)
		var pb := lm_edge_point(b_key, ca)
		terrain.add_road(pa, pb, spec[2], 9.0, rr)


func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WorldMaterials.shader("terrain")
	var arrs := WorldMaterials.terrain_arrays()
	if arrs.size() == 3:
		m.set_shader_parameter("alb_arr", arrs[0])
		m.set_shader_parameter("nrm_arr", arrs[1])
		m.set_shader_parameter("rgh_arr", arrs[2])
	m.set_shader_parameter("control_tex", control_tex)
	m.set_shader_parameter("macro_tex", WorldMaterials.macro_noise())
	m.set_shader_parameter("half_size", half_size)
	m.set_shader_parameter("grid_n", float(TerrainGen.N))
	m.set_shader_parameter("water_level", water_level)
	m.set_shader_parameter("L_GRASS", float(WorldMaterials.layer("grass")))
	m.set_shader_parameter("L_FOREST", float(WorldMaterials.layer("forest")))
	m.set_shader_parameter("L_ROCK", float(WorldMaterials.layer("rock")))
	m.set_shader_parameter("L_DIRT", float(WorldMaterials.layer("dirt")))
	m.set_shader_parameter("L_SAND", float(WorldMaterials.layer("sand")))
	var road_key: String = style["road"]
	var plaza_key: String = style["plaza"]
	m.set_shader_parameter("L_ROAD", float(WorldMaterials.layer(road_key)))
	m.set_shader_parameter("L_PLAZA", float(WorldMaterials.layer(plaza_key)))
	var road_scale := {"dirt": 0.2, "cobble": 0.4, "asphalt": 0.2, "sand": 0.25, "concrete": 0.25, "stonewall": 0.3}
	m.set_shader_parameter("road_scale", road_scale.get(road_key, 0.25))
	m.set_shader_parameter("plaza_scale", road_scale.get(plaza_key, 0.25))
	if era_id == "showa":
		m.set_shader_parameter("snow_height", 120.0)
		m.set_shader_parameter("snow_center", terrain.canon_to_world(terrain.peak))
		m.set_shader_parameter("snow_radius", 260.0)
	for k in ["grass_a", "grass_b", "grass_c", "forest_col", "dirt_col", "sand_col", "rock_col", "rock_col2", "field_col"]:
		m.set_shader_parameter(k, style[k])
	m.set_shader_parameter("road_textured", 1.0 if road_key in ["cobble", "asphalt", "concrete", "stonewall"] else 0.0)
	m.set_shader_parameter("plaza_textured", 1.0 if plaza_key in ["cobble", "asphalt", "concrete", "stonewall"] else 0.0)
	if road_key == "sand":
		m.set_shader_parameter("road_tint", Color(1.12, 1.1, 1.05))
	if plaza_key == "sand":
		m.set_shader_parameter("plaza_tint", Color(1.15, 1.12, 1.06))
	return m


func _build_water() -> void:
	var noise_tex := WorldMaterials.macro_noise()
	# 海
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(3200, 3200)
	pm.subdivide_width = 220
	pm.subdivide_depth = 220
	sea.mesh = pm
	var c := terrain.canon_to_world(Vector2(0, 1100))
	sea.position = Vector3(c.x, water_level, c.y)
	var mat := ShaderMaterial.new()
	mat.shader = WorldMaterials.shader("water")
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("shallow_color", style["water_shallow"])
	mat.set_shader_parameter("deep_color", style["water_deep"])
	mat.set_shader_parameter("sky_color", style["sky_horizon"])
	sea.material_override = mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# 水平線まで（遠景用の低分割）
	var far := MeshInstance3D.new()
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(16000, 16000)
	far.mesh = pm2
	var c2 := terrain.canon_to_world(Vector2(0, 2800 + 8000 - 1000))
	far.position = Vector3(c2.x, water_level - 0.05, c2.y)
	var mat2 := mat.duplicate()
	mat2.set_shader_parameter("wave_amp", 0.0)
	far.material_override = mat2
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	# 川
	if terrain.river_pts.size() > 1:
		add_child(_river_mesh(noise_tex))


func _river_mesh(noise_tex: Texture2D) -> MeshInstance3D:
	var pts := terrain.river_pts
	var surf := terrain.river_surface
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var w := terrain.river_half_w + 3.0
	var acc := 0.0
	for k in pts.size():
		var d: Vector2
		if k == 0:
			d = pts[1] - pts[0]
		elif k == pts.size() - 1:
			d = pts[k] - pts[k - 1]
		else:
			d = pts[k + 1] - pts[k - 1]
		d = d.normalized()
		var n := Vector2(-d.y, d.x)
		if k > 0:
			acc += pts[k].distance_to(pts[k - 1])
		var y := surf[k]
		var l := pts[k] + n * w
		var r := pts[k] - n * w
		verts.append(Vector3(l.x, y, l.y)); verts.append(Vector3(r.x, y, r.y))
		uvs.append(Vector2(acc, 0)); uvs.append(Vector2(acc, w * 2.0))
		norms.append(Vector3.UP); norms.append(Vector3.UP)
		if k > 0:
			var b := (k - 1) * 2
			# 上から見て時計回りになるよう両方試す（ArrayMesh は向きを法線で判定しないので両面にはしない）
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	# 向きの確認: 最初の三角形の外積が下向きなら反転
	if idx.size() >= 3:
		var a := verts[idx[0]]
		var b2 := verts[idx[1]]
		var c := verts[idx[2]]
		var fn := (b2 - a).cross(c - a)
		if fn.y > 0.0:
			for t in range(0, idx.size(), 3):
				var tmp := idx[t + 1]
				idx[t + 1] = idx[t + 2]
				idx[t + 2] = tmp
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = am
	var mat := ShaderMaterial.new()
	mat.shader = WorldMaterials.shader("water")
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("wave_amp", 0.0)
	mat.set_shader_parameter("flow_speed", 1.2)
	mat.set_shader_parameter("depth_scale", 2.0)
	mat.set_shader_parameter("shallow_color", (style["water_shallow"] as Color).lerp(Color(0.45, 0.75, 0.6), 0.3))
	mat.set_shader_parameter("deep_color", (style["water_deep"] as Color).lerp(Color(0.12, 0.45, 0.5), 0.3))
	mat.set_shader_parameter("sky_color", style["sky_horizon"])
	mat.set_shader_parameter("foam_width", 0.6)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 池・堀などの局所水面（矩形）。y は水面高
func add_water_rect(center: Vector3, size: Vector2, angle: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Pond"
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = int(size.x / 6.0)
	pm.subdivide_depth = int(size.y / 6.0)
	mi.mesh = pm
	mi.position = center
	mi.rotation.y = angle
	var mat := ShaderMaterial.new()
	mat.shader = WorldMaterials.shader("water")
	mat.set_shader_parameter("noise_tex", WorldMaterials.macro_noise())
	mat.set_shader_parameter("wave_amp", 0.0)
	mat.set_shader_parameter("depth_scale", 1.5)
	mat.set_shader_parameter("shallow_color", (style["water_shallow"] as Color).lerp(Color(0.4, 0.7, 0.55), 0.45))
	mat.set_shader_parameter("deep_color", (style["water_deep"] as Color).lerp(Color(0.1, 0.36, 0.4), 0.5))
	mat.set_shader_parameter("sky_color", style["sky_horizon"])
	mat.set_shader_parameter("foam_width", 0.3)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


var grass_nodes: Array = []


func _build_grass() -> void:
	var q := quality
	# 遠めのリング＋足元の高密度リング
	var rings := [[[30.0, 44.0, 56.0][q], [0.7, 0.55, 0.45][q], 0.0]]
	if q >= 1:
		rings.append([[0.0, 14.0, 18.0][q], [0.4, 0.3, 0.24][q], 0.0])
	for ring in rings:
		var radius: float = ring[0]
		var spacing: float = ring[1]
		var n := int(radius * 2.0 / spacing)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = WorldVegetation.grass_clump_mesh(spacing)
		mm.instance_count = n * n
		var k := 0
		for j in n:
			for i in n:
				mm.set_instance_transform(k, Transform3D(Basis(), Vector3((i - n * 0.5) * spacing, 0, (j - n * 0.5) * spacing)))
				k += 1
		mm.custom_aabb = AABB(Vector3(-radius, -50, -radius), Vector3(radius * 2.0, 450, radius * 2.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = WorldMaterials.shader("grass")
		mat.set_shader_parameter("height_tex", height_tex)
		mat.set_shader_parameter("control_tex", control_tex)
		mat.set_shader_parameter("noise_tex", WorldMaterials.macro_noise())
		mat.set_shader_parameter("half_size", half_size)
		mat.set_shader_parameter("grid_n", float(TerrainGen.N))
		mat.set_shader_parameter("spacing", spacing)
		mat.set_shader_parameter("radius", radius)
		mat.set_shader_parameter("water_level", water_level)
		mat.set_shader_parameter("base_color", style["grass_base"])
		mat.set_shader_parameter("tip_color", style["grass_tip"])
		for pk in ["grass_a", "grass_b", "grass_c", "tip_light"]:
			mat.set_shader_parameter(pk, style[pk])
		mat.set_shader_parameter("rice_color", (style["field_col"] as Color) * 1.15)
		mmi.material_override = mat
		add_child(mmi)
		grass_nodes.append([mmi, spacing])
	grass_node = grass_nodes[0][0]


func _compute_vehicle_spawns(layouts) -> void:
	var kinds: Array = era.get("vehicles", [])
	var spawn2 := Vector2(player_spawn.x, player_spawn.z)
	# 道沿いの点（スポーン近くから順に）
	var road_pts: Array = []
	for line in terrain.road_lines:
		var pts: PackedVector2Array = line["pts"]
		for k in range(2, pts.size() - 2, 3):
			var p := pts[k]
			if terrain.river_dist_at(p.x, p.y) < terrain.river_half_w + 12.0:
				continue
			var d := (pts[k + 1] - pts[k - 1]).normalized()
			road_pts.append([p, d, float(line["w"])])
	road_pts.sort_custom(func(a, b): return (a[0] as Vector2).distance_squared_to(spawn2) < (b[0] as Vector2).distance_squared_to(spawn2))
	if "horse" in kinds:
		var out: Array = []
		var used: Array = []
		for rp in road_pts:
			if out.size() >= 4:
				break
			var p: Vector2 = rp[0]
			if p.distance_to(spawn2) < 12.0:
				continue
			var ok := true
			for u in used:
				if p.distance_to(u) < 14.0:
					ok = false
			if not ok:
				continue
			used.append(p)
			var side := Vector2(-rp[1].y, rp[1].x) * (float(rp[2]) + 2.0)
			out.append(_xf_at(p + side, rp[1]))
		for key in ["village", "castle", "temple", "battlefield", "port"]:
			var lp: Vector3 = landmarks[key]["pos"]
			var gp := random_ground_point_near(lp + Vector3(8, 0, 8), 14.0, rng)
			out.append(_xf_at(Vector2(gp.x, gp.z), Vector2(1, 0).rotated(rng.randf() * TAU)))
		_vehicle_spawns["horse"] = out
	if "car" in kinds:
		var out: Array = []
		var used: Array = []
		for rp in road_pts:
			if out.size() >= 6:
				break
			var p: Vector2 = rp[0]
			if p.distance_to(spawn2) < 10.0 or terrain.is_occupied(p.x, p.y):
				continue
			var ok := true
			for u in used:
				if p.distance_to(u) < 25.0:
					ok = false
			if not ok:
				continue
			used.append(p)
			var side := Vector2(-rp[1].y, rp[1].x) * (float(rp[2]) * 0.5)
			out.append(_xf_at(p + side, rp[1]))
		out.append_array(layouts.extra_car_spawns)
		_vehicle_spawns["car"] = out
	if "plane" in kinds:
		_vehicle_spawns["plane"] = layouts.plane_spawns.duplicate()
		if _vehicle_spawns["plane"].is_empty():
			var info: Dictionary = landmarks["battlefield"]
			var a: Vector2 = info["a"]
			var b: Vector2 = info["b"]
			var d := (b - a).normalized()
			var p := a + d * 30.0
			_vehicle_spawns["plane"] = [_xf_at(p, d)]


## 地面上の Transform（-Z が進行方向 dir を向く）
func _xf_at(p: Vector2, dir: Vector2) -> Transform3D:
	var y := height_at(p.x, p.y)
	var fwd := Vector3(dir.x, 0, dir.y).normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	return Transform3D(basis, Vector3(p.x, y + 0.1, p.y))

class_name FallbackWorld
extends Node3D
## EraWorld が無い時の最小ワールド（テスト用）。EraWorld と同じ API を持つ。

var era: Dictionary
var half_size := 600.0
var water_level := -5.0
var player_spawn := Vector3.ZERO
var _lm := {}
var _beacons := {}


static func build(p_era: Dictionary) -> FallbackWorld:
	var w := FallbackWorld.new()
	w.era = p_era
	w.name = "FallbackWorld"
	w._make()
	return w


func height_at(x: float, z: float) -> float:
	return sin(x * 0.01) * 3.0 + cos(z * 0.013) * 3.0


func landmark_pos(key: String) -> Vector3:
	return _lm.get(key, Vector3.ZERO)


func random_ground_point_near(c: Vector3, r: float, rng: RandomNumberGenerator) -> Vector3:
	var a := rng.randf() * TAU
	var d := rng.randf() * r
	var x := c.x + cos(a) * d
	var z := c.z + sin(a) * d
	return Vector3(x, height_at(x, z), z)


func set_beacon(key: String, on: bool) -> void:
	if _beacons.has(key):
		_beacons[key].visible = on


func vehicle_spawns(kind: String) -> Array:
	if not kind in era.get("vehicles", []):
		return []
	var out: Array = []
	for i in 3:
		var p := player_spawn + Vector3(10 + i * 6, 0, -8)
		if kind == "plane":
			p = landmark_pos("battlefield") + Vector3(i * 20, 0, 0)
		p.y = height_at(p.x, p.z)
		out.append(Transform3D(Basis(), p))
	return out


func street_points() -> Array:
	var out: Array = []
	for k in ["village", "capital"]:
		for i in 12:
			var a := i * TAU / 12.0
			var p: Vector3 = landmark_pos(k) + Vector3(cos(a) * 25, 0, sin(a) * 25)
			p.y = height_at(p.x, p.z)
			out.append(p)
	return out


func _make() -> void:
	var keys := HistoryDB.LANDMARK_KEYS
	for i in keys.size():
		var a := i * TAU / keys.size()
		var p := Vector3(cos(a) * 300.0, 0, sin(a) * 300.0)
		p.y = height_at(p.x, p.z)
		_lm[keys[i]] = p
	player_spawn = _lm["village"] + Vector3(0, 0, 20)
	player_spawn.y = height_at(player_spawn.x, player_spawn.z)
	# 地面メッシュ
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 120
	var step := half_size * 2.0 / n
	for j in n:
		for i in n:
			var x0 := -half_size + i * step
			var z0 := -half_size + j * step
			var quad := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for qi in 4:
				quad[qi].y = height_at(quad[qi].x, quad[qi].z)
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(quad[idx].x, quad[idx].z) * 0.1)
				st.add_vertex(quad[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.5, 0.25)
	if ResourceLoader.exists("res://assets/polyhaven/textures/grass_diff.jpg"):
		m.albedo_texture = load("res://assets/polyhaven/textures/grass_diff.jpg")
		m.albedo_color = Color.WHITE
		m.uv1_scale = Vector3(1, 1, 1)
	mi.material_override = m
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Game.COLLISION_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
	# ランドマークに箱の建物
	for k in keys:
		for b in 5:
			var box := StaticBody3D.new()
			box.collision_layer = Game.COLLISION_WORLD
			var bs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(8, 6, 8)
			bs.shape = shape
			box.add_child(bs)
			var bm := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = shape.size
			bm.mesh = mesh
			box.add_child(bm)
			add_child(box)
			var bp: Vector3 = _lm[k] + Vector3(cos(b * 1.3) * 40, 0, sin(b * 1.3) * 40)
			box.position = Vector3(bp.x, height_at(bp.x, bp.z) + 3.0, bp.z)
		var beacon := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.0; cm.bottom_radius = 2.0; cm.height = 300.0
		beacon.mesh = cm
		beacon.material_override = Effects.emissive(Color(0.37, 0.91, 1.0, 0.25), 2.0)
		beacon.visible = false
		add_child(beacon)
		beacon.position = _lm[k] + Vector3.UP * 150.0
		_beacons[k] = beacon
	# 樽
	for i in 6:
		var ex := Explosive.new()
		var mesh2 := CylinderMesh.new()
		mesh2.top_radius = 0.4; mesh2.bottom_radius = 0.4; mesh2.height = 1.0
		var mm := MeshInstance3D.new()
		mm.mesh = mesh2
		mm.material_override = Humanoid.mat(Color(0.7, 0.1, 0.08), 0.6)
		ex.add_child(mm)
		var c2 := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4; cyl.height = 1.0
		c2.shape = cyl
		ex.add_child(c2)
		add_child(ex)
		var pp := player_spawn + Vector3(-10 - i * 2, 0, 5)
		ex.position = Vector3(pp.x, height_at(pp.x, pp.z) + 0.6, pp.z)
	# 環境
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)

class_name WorldProps
extends RefCounted
## 物理小道具（木箱・樽・桶）と爆発樽。RigidBody3D / group "physics_prop" / layer 32。

const ExplosiveScript := preload("res://scripts/player/explosive.gd")
const PER_LANDMARK := {"capital": [10, 2], "village": [12, 1], "temple": [5, 0], "port": [14, 3], "castle": [8, 2], "battlefield": [10, 5], "mountain": [3, 0]}

var w: EraWorld
static var _meshes := {}


func _init(world: EraWorld) -> void:
	w = world


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = w.rng.seed + 777
	var root := Node3D.new()
	root.name = "Props"
	w.add_child(root)
	for key in PER_LANDMARK:
		if not w.landmarks.has(key):
			continue
		var lm: Dictionary = w.landmarks[key]
		var spec: Array = PER_LANDMARK[key]
		var r: float = lm["r"]
		for i in int(spec[0]):
			# 小さな山積み（2〜3 個）
			var c := w.random_ground_point_near(lm["pos"], r * 0.75, rng)
			var n := rng.randi_range(1, 3)
			for k in n:
				var kind: String = ["crate", "barrel", "bucket", "crate"][rng.randi() % 4]
				var p := c + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
				p.y = w.height_at(p.x, p.z)
				root.add_child(_prop(kind, p, rng))
		for i in int(spec[1]):
			var p := w.random_ground_point_near(lm["pos"], r * 0.6, rng)
			root.add_child(_explosive(p, rng))


func _prop(kind: String, p: Vector3, rng: RandomNumberGenerator) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = kind.capitalize()
	b.collision_layer = 32
	b.collision_mask = 1 | 2 | 4 | 8 | 16 | 32
	b.add_to_group("physics_prop")
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	var half := 0.4
	match kind:
		"crate":
			var s := rng.randf_range(0.7, 1.0)
			mi.mesh = mesh("crate")
			mi.scale = Vector3.ONE * s
			var bs := BoxShape3D.new()
			bs.size = Vector3.ONE * 0.9 * s
			cs.shape = bs
			b.mass = 18.0 * s
			half = 0.45 * s
		"barrel":
			mi.mesh = mesh("barrel")
			var c := CylinderShape3D.new()
			c.radius = 0.36
			c.height = 1.0
			cs.shape = c
			b.mass = 25.0
			half = 0.5
		_:
			mi.mesh = mesh("bucket")
			var c := CylinderShape3D.new()
			c.radius = 0.24
			c.height = 0.36
			cs.shape = c
			b.mass = 3.0
			half = 0.18
	var model_id: String = {"crate": "wooden_crate_01", "barrel": "Barrel_01", "bucket": "wooden_bucket_01"}.get(kind, "")
	var parts := WorldModels.parts(model_id) if model_id != "" else []
	if not parts.is_empty():
		# 写真スキャンのモデル（形に合わせた箱コリジョン、底面を原点に）
		var bb := WorldModels.bounds(parts)
		var bs := BoxShape3D.new()
		bs.size = bb.size
		cs.shape = bs
		cs.position = Vector3.ZERO
		for e in parts:
			var m := MeshInstance3D.new()
			m.mesh = e[0]
			m.transform = Transform3D(Basis(), -bb.get_center()) * (e[1] as Transform3D)
			b.add_child(m)
		half = bb.size.y * 0.5
		b.mass = maxf(2.0, bb.size.x * bb.size.y * bb.size.z * 120.0)
	else:
		b.add_child(mi)
	b.add_child(cs)
	b.position = p + Vector3(0, half + 0.02, 0)
	b.rotation.y = rng.randf() * TAU
	b.can_sleep = true
	b.sleeping = true
	return b


func _explosive(p: Vector3, rng: RandomNumberGenerator) -> RigidBody3D:
	var b: RigidBody3D = ExplosiveScript.new()
	b.name = "ExplosiveBarrel"
	b.collision_layer = 32
	b.collision_mask = 1 | 2 | 4 | 8 | 16 | 32
	b.mass = 30.0
	var mi := MeshInstance3D.new()
	var modern := w.era_id in ["meiji_taisho", "showa"]
	mi.mesh = mesh("explosive_" + ("modern" if modern else "keg"))
	var parts := WorldModels.parts("Barrel_01") if not modern else []
	if not parts.is_empty():
		# 樽モデルを赤く塗った火薬樽
		var bb := WorldModels.bounds(parts)
		var k := 1.0 / maxf(bb.size.y, 0.1)
		for e in parts:
			var m := MeshInstance3D.new()
			m.mesh = e[0]
			m.transform = Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(0, -0.5, 0) - bb.get_center() * Vector3(k, 0, k) - Vector3(0, bb.position.y * k, 0)) * (e[1] as Transform3D)
			for si in (e[0] as Mesh).get_surface_count():
				var om := (e[0] as Mesh).surface_get_material(si)
				if om is BaseMaterial3D:
					var red := (om as BaseMaterial3D).duplicate() as BaseMaterial3D
					red.albedo_color = Color(1.0, 0.32, 0.25)
					m.set_surface_override_material(si, red)
			b.add_child(m)
		var mark := MeshInstance3D.new()
		var km := MeshKit.new()
		km.box("flat", Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0, 0.0, 0.3)), Vector3(0.2, 0.2, 0.02), Color(0.95, 0.92, 0.8))
		mark.mesh = km.to_mesh()
		b.add_child(mark)
	else:
		b.add_child(mi)
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 0.38
	c.height = 1.0
	cs.shape = c
	b.add_child(cs)
	b.position = p + Vector3(0, 0.52, 0)
	b.rotation.y = rng.randf() * TAU
	b.can_sleep = true
	b.sleeping = true
	return b


static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var k := MeshKit.new()
	match kind:
		"crate":
			k.box("wood", Transform3D(Basis(), Vector3.ZERO), Vector3(0.9, 0.9, 0.9), Color(0.95, 0.85, 0.7), false)
			for e in [-1.0, 1.0]:
				for f in [-1.0, 1.0]:
					k.box("darkwood", Transform3D(Basis(), Vector3(e * 0.44, 0, f * 0.44)), Vector3(0.06, 0.92, 0.06), Color(0.6, 0.5, 0.4))
					k.box("darkwood", Transform3D(Basis(), Vector3(0, e * 0.44, f * 0.44)), Vector3(0.92, 0.06, 0.06), Color(0.6, 0.5, 0.4))
					k.box("darkwood", Transform3D(Basis(), Vector3(e * 0.44, f * 0.44, 0)), Vector3(0.06, 0.06, 0.92), Color(0.6, 0.5, 0.4))
		"barrel":
			_barrel(k, Color(0.85, 0.72, 0.58), Color(0.25, 0.22, 0.2), "wood")
		"bucket":
			k.cylinder("wood", Transform3D(Basis(), Vector3(0, -0.18, 0)), 0.2, 0.24, 0.36, 10, Color(0.9, 0.78, 0.6))
			k.cylinder("metal", Transform3D(Basis(), Vector3(0, -0.1, 0)), 0.215, 0.215, 0.04, 10, Color(0.3, 0.3, 0.3), false)
			k.cylinder("metal", Transform3D(Basis(), Vector3(0, 0.08, 0)), 0.235, 0.235, 0.04, 10, Color(0.3, 0.3, 0.3), false)
		"explosive_keg":
			_barrel(k, Color(0.75, 0.14, 0.1), Color(0.12, 0.1, 0.1), "wood")
			# 「火」マーク代わりの白い菱形
			k.box("flat", Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0, 0.05, 0.37)), Vector3(0.22, 0.22, 0.02), Color(0.95, 0.92, 0.8))
		"explosive_modern":
			k.cylinder("metal", Transform3D(Basis(), Vector3(0, -0.5, 0)), 0.36, 0.36, 1.0, 14, Color(0.78, 0.12, 0.08))
			k.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.49, 0)), 0.36, 0.36, 0.01, 14, Color(0.78, 0.12, 0.08))
			for y in [-0.25, 0.25]:
				k.cylinder("metal", Transform3D(Basis(), Vector3(0, y - 0.03, 0)), 0.375, 0.375, 0.06, 14, Color(0.9, 0.75, 0.1), false)
			k.box("flat", Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0, 0.0, 0.36)), Vector3(0.24, 0.24, 0.02), Color(0.95, 0.85, 0.1))
	var m := k.to_mesh()
	_meshes[kind] = m
	return m


static func _barrel(k: MeshKit, body: Color, band: Color, mat: String) -> void:
	# 胴の膨らみ
	var segs := 4
	for s in segs:
		var y0 := -0.5 + float(s) / segs
		var y1 := -0.5 + float(s + 1) / segs
		var r0 := 0.32 + 0.05 * sin(float(s) / segs * PI)
		var r1 := 0.32 + 0.05 * sin(float(s + 1) / segs * PI)
		k.cylinder(mat, Transform3D(Basis(), Vector3(0, y0, 0)), r0, r1, y1 - y0, 14, body, s == segs - 1, true)
	k.cylinder(mat, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.49, 0)), 0.32, 0.32, 0.01, 14, body, true)
	for y in [-0.38, 0.0, 0.36]:
		var rr := 0.32 + 0.05 * sin((y + 0.5) * PI) + 0.012
		k.cylinder("metal", Transform3D(Basis(), Vector3(0, y - 0.03, 0)), rr, rr, 0.06, 14, band, false)

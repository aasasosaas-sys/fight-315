class_name Effects
extends RefCounted
## 弾道・火花・血しぶき・爆発・画面揺れ。すべて実行時生成。

static var shake := 0.0
static var _mats := {}

const CYAN := Color(0.37, 0.91, 1.0)
const GUARD := Color(1.0, 0.25, 0.9)


static func _root(tree: SceneTree) -> Node:
	var s = tree.current_scene
	return s if s != null else tree.root


static func emissive(c: Color, energy := 4.0) -> StandardMaterial3D:
	var key := "e%s%.1f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func particle_mat(c: Color, additive: bool) -> StandardMaterial3D:
	var key := "p%s%s" % [c.to_html(), additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


static var _dot: Texture2D
static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


static func burst(tree: SceneTree, pos: Vector3, normal: Vector3, c0: Color, c1: Color, count: int, speed: float,
		size: float, life: float, gravity: float, additive: bool, spread := 40.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = count
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8 * gravity, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1)); curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, c0); g.set_color(1, Color(c1, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = particle_mat(Color.WHITE, additive)
	p.mesh = q
	p.local_coords = false
	_root(tree).add_child(p)
	p.global_position = pos
	if normal.length_squared() > 0.01 and abs(normal.normalized().dot(Vector3.UP)) < 0.99:
		p.look_at(pos + normal, Vector3.UP)
		p.rotate_object_local(Vector3.RIGHT, -PI / 2)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func flash(tree: SceneTree, pos: Vector3, c: Color, energy: float, rng: float, time: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	_root(tree).add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)


static func tracer(tree: SceneTree, from: Vector3, to: Vector3, c: Color, width := 0.04) -> void:
	var len := from.distance_to(to)
	if len < 0.1:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, len)
	mi.mesh = bm
	mi.material_override = emissive(c, 6.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root(tree).add_child(mi)
	mi.global_position = (from + to) * 0.5
	if abs((to - from).normalized().dot(Vector3.UP)) < 0.999:
		mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.1, 0.1, 1.0), 0.08)
	tw.tween_callback(mi.queue_free)


static func muzzle(tree: SceneTree, pos: Vector3, dir: Vector3, c: Color) -> void:
	burst(tree, pos, dir, c, Color.WHITE, 6, 4.0, 0.15, 0.06, 0.0, true, 20)
	flash(tree, pos, c, 3.0, 5.0, 0.06)


static func spark(tree: SceneTree, pos: Vector3, normal: Vector3, c := Color(1, 0.8, 0.5)) -> void:
	burst(tree, pos, normal, c, Color.WHITE, 10, 7.0, 0.08, 0.35, 1.2, true)
	burst(tree, pos, normal, Color(0.55, 0.5, 0.45, 0.6), Color(0.3, 0.3, 0.3), 5, 1.5, 0.5, 0.9, -0.05, false)


static func blood(tree: SceneTree, pos: Vector3, normal: Vector3, guardian: bool) -> void:
	if guardian:
		burst(tree, pos, normal, GUARD, CYAN, 14, 5.0, 0.14, 0.5, 0.2, true)
	else:
		burst(tree, pos, normal, Color(0.5, 0.03, 0.03), Color(0.25, 0.02, 0.02), 10, 3.0, 0.08, 0.45, 1.5, false)


static func time_warp(tree: SceneTree, pos: Vector3) -> void:
	burst(tree, pos + Vector3.UP, Vector3.UP, CYAN, Color.WHITE, 90, 10.0, 0.3, 1.3, -0.3, true, 180)
	flash(tree, pos + Vector3.UP * 2, CYAN, 16.0, 30.0, 1.0)


## 爆発：範囲ダメージ・物理インパルス・誘爆・町人パニック・手配度上昇
static func explosion(tree: SceneTree, pos: Vector3, radius: float, damage: float, from_team: int) -> void:
	burst(tree, pos, Vector3.UP, Color(1, 0.62, 0.18), Color(1, 0.2, 0.05), 70, 14.0, 1.6, 0.7, -0.2, true, 180)
	burst(tree, pos, Vector3.UP, Color(0.22, 0.2, 0.19, 0.85), Color(0.4, 0.38, 0.35), 34, 5.0, 4.5, 3.2, -0.08, false, 90)
	burst(tree, pos, Vector3.UP, Color(1, 0.88, 0.45), Color.WHITE, 40, 24.0, 0.14, 1.3, 1.5, true, 180)
	flash(tree, pos + Vector3.UP, Color(1, 0.6, 0.3), 12.0, radius * 4.0, 0.6)
	Sfx.play_at(tree, Sfx.explode(), pos, 6.0)
	var cam := tree.root.get_viewport().get_camera_3d()
	if cam:
		shake = maxf(shake, clampf(1.6 - cam.global_position.distance_to(pos) / (radius * 6.0), 0.0, 1.0))
	var space := tree.root.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = shape
	qp.transform = Transform3D(Basis(), pos)
	qp.collide_with_areas = false
	var done := {}
	for hit in space.intersect_shape(qp, 64):
		var obj: Object = hit["collider"]
		if obj == null or done.has(obj):
			continue
		done[obj] = true
		var node := obj as Node3D
		if node == null:
			continue
		var k := 1.0 - clampf(node.global_position.distance_to(pos) / radius, 0.0, 1.0)
		var target := _hit_target(node)
		if target and target.has_method("take_hit") and not (target is Explosive):
			target.take_hit(damage * (0.35 + 0.65 * k), from_team, node.global_position, (node.global_position - pos).normalized())
		if node is RigidBody3D:
			var dir := (node.global_position - pos + Vector3.UP * 1.5).normalized()
			(node as RigidBody3D).apply_central_impulse(dir * (18.0 + 40.0 * k) * maxf(1.0, (node as RigidBody3D).mass * 0.5))
		if node is Explosive:
			(node as Explosive).detonate(0.12 + randf() * 0.25)
		if target and target.has_method("panic"):
			target.panic(pos)
	Wanted.report(pos, 0.9)


## 当たったコライダーから take_hit を持つノードを親方向に探す
static func _hit_target(n: Node) -> Node:
	var cur := n
	for i in 4:
		if cur == null:
			return null
		if cur.has_method("take_hit") or cur.has_method("panic"):
			return cur
		cur = cur.get_parent()
	return null


static func find_target(n: Node) -> Node:
	return _hit_target(n)

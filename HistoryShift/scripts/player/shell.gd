class_name Shell
extends Node3D
## 大筒の砲弾・棒火矢（ロケット）・擲弾。レイキャストで進み、当たると爆発する。

const SPEC := {
	"cannonball": {"radius": 7.0, "damage": 650.0, "fire": 0.3, "gravity": 9.8, "life": 12.0},
	"shell": {"radius": 9.0, "damage": 800.0, "fire": 0.35, "gravity": 9.8, "life": 12.0},
	"hiya": {"radius": 5.0, "damage": 200.0, "fire": 1.0, "gravity": 2.0, "life": 6.0},
	"grenade": {"radius": 7.0, "damage": 360.0, "fire": 0.3, "gravity": 9.8, "life": 8.0},
}

var kind := "cannonball"
var vel := Vector3.ZERO
var team := 0
var life := 8.0
var _trail: CPUParticles3D
var _snd: AudioStreamPlayer3D


static func fire(tree: SceneTree, p_kind: String, from: Vector3, velocity: Vector3, p_team := 0) -> Shell:
	var s := Shell.new()
	s.kind = p_kind
	s.vel = velocity
	s.team = p_team
	var sess = tree.get_first_node_in_group("session")
	var root: Node = sess if sess else (tree.current_scene if tree.current_scene else tree.root)
	root.add_child(s)
	s.global_position = from
	return s


func _ready() -> void:
	var sp: Dictionary = SPEC.get(kind, SPEC["cannonball"])
	life = float(sp["life"])
	var kit := MeshKit.new()
	match kind:
		"hiya":
			# 棒火矢: 矢柄＋火薬筒＋矢羽根
			kit.cylinder("wood", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.6)), 0.03, 0.03, 1.4, 5, Color(0.7, 0.55, 0.4))
			kit.cylinder("flat", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.1)), 0.09, 0.07, 0.5, 8, Color(0.75, 0.2, 0.12))
			kit.box("cloth", Transform3D(Basis(), Vector3(0, 0, 0.75)), Vector3(0.02, 0.22, 0.3), Color(0.95, 0.95, 0.9))
		_:
			kit.sphere("metal", Transform3D.IDENTITY, 0.16 if kind != "grenade" else 0.1, 8, 5, Color(0.12, 0.12, 0.12))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_trail = CPUParticles3D.new()
	_trail.amount = 40 if kind == "hiya" else 18
	_trail.lifetime = 0.9 if kind == "hiya" else 0.6
	_trail.direction = Vector3.BACK
	_trail.spread = 10.0
	_trail.initial_velocity_min = 0.5
	_trail.initial_velocity_max = 2.0
	_trail.gravity = Vector3(0, 0.6, 0)
	_trail.scale_amount_min = 0.3
	_trail.scale_amount_max = 0.8 if kind == "hiya" else 0.5
	var g := Gradient.new()
	if kind == "hiya":
		g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
		g.add_point(0.15, Color(1.0, 0.45, 0.1, 0.9))
		g.set_color(g.get_point_count() - 1, Color(0.5, 0.48, 0.46, 0.0))
	else:
		g.set_color(0, Color(0.85, 0.82, 0.78, 0.6))
		g.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	_trail.color_ramp = g
	var q := QuadMesh.new()
	q.material = Effects.particle_mat(Color.WHITE, kind == "hiya")
	_trail.mesh = q
	_trail.local_coords = false
	add_child(_trail)
	if kind == "hiya":
		_snd = Sfx.loop_player(self, Sfx.rocket(), -4.0)
		_snd.play()
	_orient()


func _orient() -> void:
	if vel.length_squared() > 0.01 and absf(vel.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + vel, Vector3.UP)


func _physics_process(dt: float) -> void:
	life -= dt
	var sp: Dictionary = SPEC.get(kind, SPEC["cannonball"])
	if life <= 0.0:
		_explode(global_position)
		return
	vel.y -= float(sp["gravity"]) * dt
	if kind == "hiya":
		vel *= 1.0 + dt * 0.15   # 推進
		vel += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * dt * 2.0
	var from := global_position
	var to := from + vel * dt
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.COLLISION_WORLD | Game.COLLISION_ENEMY | Game.COLLISION_VEHICLE | Game.COLLISION_PROP | Game.COLLISION_CIVILIAN)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col = hit["collider"]
		# 砲弾の直撃は建物に重く効く
		if col and col.has_method("blast") and kind != "hiya":
			col.blast(float(sp["damage"]) * 0.6, hit["position"], float(sp["fire"]))
		if col and kind == "hiya" and col.has_method("ignite"):
			col.ignite()   # 棒火矢は刺さった建物に必ず火をつける
		_explode(hit["position"] - vel.normalized() * 0.3)
		return
	var w = Game.world
	if w and w.has_method("height_at") and to.y < w.height_at(to.x, to.z):
		_explode(Vector3(to.x, w.height_at(to.x, to.z) + 0.2, to.z))
		return
	global_position = to
	_orient()


func _explode(p: Vector3) -> void:
	if not is_inside_tree():
		return
	var sp: Dictionary = SPEC.get(kind, SPEC["cannonball"])
	var tree := get_tree()
	queue_free()
	Effects.explosion(tree, p, float(sp["radius"]), float(sp["damage"]), team, float(sp["fire"]))
	if kind == "hiya":
		Effects.burst(tree, p, Vector3.UP, Color(1.0, 0.7, 0.2), Color(1.0, 0.2, 0.0), 50, 12.0, 0.2, 1.8, 1.0, true, 170)


## 弾道計算: from から target へ速さ v で届く初速（低い弾道）。届かなければ 45°
static func ballistic(from: Vector3, target: Vector3, v: float, g := 9.8) -> Vector3:
	var d := target - from
	var flat := Vector3(d.x, 0, d.z)
	var x := flat.length()
	var y := d.y
	if x < 0.5:
		return Vector3.UP * v
	var v2 := v * v
	var disc := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
	var ang: float
	if disc < 0.0:
		ang = PI * 0.25
	else:
		ang = atan((v2 - sqrt(disc)) / (g * x))
	var dirh := flat / x
	return dirh * cos(ang) * v + Vector3.UP * sin(ang) * v

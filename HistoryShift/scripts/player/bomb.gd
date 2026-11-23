class_name ThrownBomb
extends RigidBody3D
## 投げる/置く爆弾。kind: "horoku"（焙烙玉: 当たると割れて爆発）/ "dynamite"（導火線 3 秒）/ "keg"（火薬樽: 置いて 4 秒）
## / "grenade"（昭和の手榴弾）。爆発は Effects.explosion（建物には Destruction.blast が効く）。

const SPEC := {
	"horoku": {"radius": 7.0, "damage": 300.0, "fuse": 3.0, "impact": true, "fire": 0.55},
	"grenade": {"radius": 7.5, "damage": 320.0, "fuse": 2.5, "impact": false, "fire": 0.2},
	"dynamite": {"radius": 11.0, "damage": 700.0, "fuse": 3.0, "impact": false, "fire": 0.35},
	"keg": {"radius": 13.0, "damage": 900.0, "fuse": 4.0, "impact": false, "fire": 0.6},
}

var kind := "horoku"
var team := 0
var fuse := 3.0
var _age := 0.0
var _done := false
var power := 1.0       # 品質・建築の技能による威力の倍率（DestructionTools が設定）
var dud := 0.0         # 不発（湿気・導火線の不良）の確率
var _spark: CPUParticles3D
var _hiss: AudioStreamPlayer3D


static func spawn(tree: SceneTree, p_kind: String, pos: Vector3, vel: Vector3, p_team := 0) -> ThrownBomb:
	var b := ThrownBomb.new()
	b.kind = p_kind
	b.team = p_team
	var sess = tree.get_first_node_in_group("session")
	var root: Node = sess if sess else (tree.current_scene if tree.current_scene else tree.root)
	root.add_child(b)
	b.global_position = pos
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	return b


func _ready() -> void:
	var sp: Dictionary = SPEC.get(kind, SPEC["horoku"])
	fuse = float(sp["fuse"])
	collision_layer = Game.COLLISION_PROP
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_ENEMY | Game.COLLISION_VEHICLE | Game.COLLISION_PROP
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	body_entered.connect(_on_body)
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	var kit := MeshKit.new()
	match kind:
		"dynamite":
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.22, 0.22, 0.4)
			cs.shape = sh
			for k in 3:
				kit.cylinder("flat", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3((k - 1) * 0.075, 0.0 if k != 1 else 0.06, -0.2)), 0.04, 0.04, 0.4, 8, Color(0.85, 0.15, 0.1))
			kit.box("flat", Transform3D.IDENTITY, Vector3(0.24, 0.17, 0.05), Color(0.95, 0.9, 0.75))
			mass = 1.5
		"keg":
			var cy := CylinderShape3D.new()
			cy.radius = 0.38
			cy.height = 1.0
			cs.shape = cy
			mi.mesh = WorldProps.mesh("explosive_keg")
			mass = 30.0
		_:
			var ss := SphereShape3D.new()
			ss.radius = 0.17
			cs.shape = ss
			var c := Color(0.32, 0.26, 0.22) if kind == "horoku" else Color(0.3, 0.34, 0.24)
			kit.sphere("earth" if kind == "horoku" else "metal", Transform3D.IDENTITY, 0.17, 10, 6, c)
			kit.cylinder("darkwood", Transform3D(Basis(), Vector3(0, 0.13, 0)), 0.05, 0.04, 0.1, 6, Color(0.5, 0.4, 0.3))
			mass = 1.2
	if mi.mesh == null:
		mi.mesh = kit.to_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	add_child(cs)
	# 導火線の火花
	_spark = CPUParticles3D.new()
	_spark.amount = 14
	_spark.lifetime = 0.35
	_spark.direction = Vector3.UP
	_spark.spread = 60.0
	_spark.initial_velocity_min = 1.0
	_spark.initial_velocity_max = 3.0
	_spark.gravity = Vector3(0, -4, 0)
	_spark.scale_amount_min = 0.06
	_spark.scale_amount_max = 0.14
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.6))
	g.set_color(1, Color(1, 0.3, 0.05, 0))
	_spark.color_ramp = g
	var q := QuadMesh.new()
	q.material = Effects.particle_mat(Color.WHITE, true)
	_spark.mesh = q
	_spark.local_coords = false
	_spark.position = Vector3(0, 0.55 if kind == "keg" else 0.2, 0)
	add_child(_spark)
	_hiss = Sfx.loop_player(self, Sfx.fuse(), -10.0)
	_hiss.play()


func _physics_process(dt: float) -> void:
	_age += dt
	if _age >= fuse:
		detonate()


func _on_body(b: Node) -> void:
	if kind == "horoku" and _age > 0.12 and not (b is Player):
		detonate()


## 撃たれたり誘爆したりしたとき
func take_hit(_a: float, _t: int, _p := Vector3.ZERO, _d := Vector3.ZERO) -> void:
	detonate()


func detonate() -> void:
	if _done or not is_inside_tree():
		return
	_done = true
	var sp: Dictionary = SPEC.get(kind, SPEC["horoku"])
	var p := global_position + Vector3.UP * 0.3
	var tree := get_tree()
	queue_free()
	if dud > 0.0 and randf() < dud:
		# 不発：煙だけ
		Effects.burst(tree, p, Vector3.UP, Color(0.8, 0.8, 0.8, 0.7), Color(0.4, 0.4, 0.4), 14, 1.5, 1.0, 1.4, -0.05, false, 40)
		var hud = tree.get_first_node_in_group("hud")
		if hud and hud.has_method("toast") and team == 0:
			hud.toast("不発だった……（火薬の質が悪い）", 2.0)
		return
	Effects.explosion(tree, p, float(sp["radius"]) * (0.8 + 0.2 * power), float(sp["damage"]) * power, team, float(sp["fire"]))
	if kind == "horoku":
		# 焙烙玉は火の粉を撒く
		Effects.burst(tree, p, Vector3.UP, Color(1.0, 0.7, 0.2), Color(1.0, 0.2, 0.0), 40, 12.0, 0.18, 1.6, 1.2, true, 160)
	if kind == "keg" or kind == "dynamite":
		Effects.shake = maxf(Effects.shake, 0.9)

class_name HistFigure
extends CharacterBody3D
## 自由探索に現れる歴史上の人物（data/chaos/<era>.json の figures）。名所に護衛と一緒に立っている。
## 攻撃すると逃げ、護衛が反撃する。倒すと Game.chaos_event("kill", 名前, {type: "figure"}) を出し、歴史が揺らぐ。
## 姿は scripts/player/figures.gd（Figures.build）があればそれを、無ければ Humanoid を使う。

signal killed(fig)

const FIGURES_PATH := "res://scripts/player/figures.gd"

var figure_name := "人物"
var era_id := ""
var lines: Array = []
var hp := 120.0
var dead := false
var guards: Array = []
var home := Vector3.ZERO
var _rig: Node3D
var _tag: Label3D
var _ring: MeshInstance3D
var _flee := 0.0
var _flee_from := Vector3.ZERO
var _greeted := false


static func spawn(parent: Node, pos: Vector3, p_name: String, p_era: String, p_lines: Array = []) -> HistFigure:
	var f := HistFigure.new()
	f.figure_name = p_name
	f.era_id = p_era
	f.lines = p_lines
	parent.add_child(f)
	f.global_position = pos
	f.home = pos
	return f


## 車・馬の轢き判定や命中マーカーのため敵と同じ扱いにする（"enemy" グループには入れない）
func is_enemy() -> bool:
	return true


func _ready() -> void:
	add_to_group("figure")
	collision_layer = Game.COLLISION_ENEMY
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_PROP | Game.COLLISION_VEHICLE
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	_rig = _build_rig()
	_rig.rotation.y = PI
	add_child(_rig)
	_tag = Label3D.new()
	_tag.text = "◆ " + figure_name
	_tag.font = load("res://assets/fonts/NotoSerifJP-Bold.ttf")
	_tag.font_size = 60
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.outline_size = 12
	_tag.modulate = Color(1, 0.82, 0.4)
	_tag.position = Vector3(0, 2.5, 0)
	add_child(_tag)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0
	tm.outer_radius = 1.12
	_ring.mesh = tm
	_ring.material_override = Effects.emissive(Color(1, 0.75, 0.3), 1.6)
	_ring.position = Vector3(0, 0.05, 0)
	add_child(_ring)


func _build_rig() -> Node3D:
	var rig: Node3D = null
	if ResourceLoader.exists(FIGURES_PATH):
		var fs := load(FIGURES_PATH) as GDScript
		if fs != null and fs.can_instantiate() and _has_static(fs, "spec_for") and _has_static(fs, "build"):
			var spec: Variant = fs.callv("spec_for", [figure_name])
			if spec is Dictionary and not (spec as Dictionary).is_empty():
				var m: Variant = fs.callv("build", [figure_name, hash(figure_name)])
				if m is Node3D:
					rig = m
					_play_idle(rig)
	if rig == null:
		rig = Humanoid.build(Humanoid.outfit_for(era_id, "npc"), hash(figure_name), false, 1 if Humanoid.is_female_name(figure_name) else 0)
	return rig


static func _has_static(s: GDScript, fn: String) -> bool:
	for m in s.get_script_method_list():
		if m.get("name", "") == fn:
			return true
	return false


static func _play_idle(model: Node) -> void:
	var ap := model.find_child("Anim", true, false) as AnimationPlayer
	if ap == null:
		return
	for a in ap.get_animation_list():
		if String(a).to_lower().contains("idle"):
			ap.play(a)
			return


func take_hit(amount: float, from_team: int, point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if dead or from_team == 1:
		return
	hp -= amount
	_flee = 7.0
	_flee_from = point if point != Vector3.ZERO else global_position + Vector3.FORWARD
	if _rig.has_method("hurt"):
		_rig.call("hurt")
	_alert_guards()
	Wanted.report(global_position, 0.2)
	if hp <= 0.0:
		_die()


func _alert_guards() -> void:
	for g in guards:
		if is_instance_valid(g) and not g.dead:
			g.aggro_range = 140.0
			g._alert = true


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = Game.COLLISION_WORLD
	_tag.visible = false
	_ring.visible = false
	if _rig.has_method("die"):
		_rig.call("die")
	else:
		var tw := _rig.create_tween()
		tw.tween_property(_rig, "rotation:x", -PI * 0.5, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_rig, "position:y", 0.25, 0.6)
	Sfx.play_at(get_tree(), Sfx.hit(), global_position, -2.0)
	Effects.burst(get_tree(), global_position + Vector3.UP, Vector3.UP, Color(1, 0.8, 0.35), Effects.CYAN, 36, 5.0, 0.3, 1.0, -0.2, true, 160)
	Wanted.report(global_position, 1.2)
	_alert_guards()
	Game.chaos_event.emit("kill", figure_name, {"type": "figure", "era": era_id, "pos": global_position})
	killed.emit(self)
	await get_tree().create_timer(10.0).timeout
	if is_inside_tree():
		queue_free()


func _physics_process(dt: float) -> void:
	if dead:
		if not is_on_floor():
			velocity = Vector3(0, velocity.y - 22.0 * dt, 0)
			move_and_slide()
		return
	var p = Game.player
	var move := Vector3.ZERO
	var spd := 0.0
	_flee = maxf(0.0, _flee - dt)
	if _flee > 0.0:
		var away := global_position - _flee_from
		if p and is_instance_valid(p):
			away = global_position - (p as Node3D).global_position
		away.y = 0
		move = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		spd = 5.0
	else:
		var back := home - global_position
		back.y = 0
		if back.length() > 3.0:
			move = back.normalized()
			spd = 1.6
	if move.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z), dt * 6.0)
	elif p and is_instance_valid(p):
		var to: Vector3 = (p as Node3D).global_position - global_position
		to.y = 0
		if to.length() < 14.0 and to.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), dt * 3.0)
		if not _greeted and to.length() < 8.0 and not lines.is_empty():
			_greeted = true
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.toast("%s「%s」" % [figure_name, str(lines[randi() % lines.size()])], 4.0)
	velocity.x = move.x * spd
	velocity.z = move.z * spd
	velocity.y = -1.0 if is_on_floor() else velocity.y - 22.0 * dt
	move_and_slide()
	if "speed" in _rig:
		_rig.set("speed", Vector2(velocity.x, velocity.z).length())
	_ring.rotation.y += dt
	var w = Game.world
	if w and global_position.y < w.height_at(global_position.x, global_position.z) - 3.0:
		global_position.y = w.height_at(global_position.x, global_position.z) + 1.0

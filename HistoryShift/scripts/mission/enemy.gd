class_name Enemy
extends CharacterBody3D
## 地上の敵兵。時代に応じて弓・火縄銃・小銃・機関銃、修正力はエネルギー弾。
## mission_target = true のものだけがミッションの撃破数に数えられる。

signal killed(enemy)

var label := "敵"
var era_id := ""
var weapon := "bow"
var is_guardian := false
var is_leader := false
var mission_target := false
var hp := 60.0
var dead := false
var home := Vector3.ZERO
var aggro_range := 75.0
var _rig: Humanoid
var _tag: Label3D
var _cool := 1.0
var _burst := 0
var _strafe := 1.0
var _think := 0.0
var _alert := false
var _vy := 0.0
var _stun := 0.0                  # よろけ（主人公の強い振り・受け流し）
var _windup := -1.0               # 近接：振りかぶってから当たるまで（受け流しの合図）


static func spawn(parent: Node, pos: Vector3, p_label: String, p_era: String, leader := false) -> Enemy:
	var e := Enemy.new()
	e.label = p_label
	e.era_id = p_era
	e.is_leader = leader
	e.is_guardian = p_label.contains("修正力") or p_label.contains("番人") or p_label.contains("時空")
	parent.add_child(e)
	e.global_position = pos
	e.home = pos
	return e


func is_enemy() -> bool:
	return true


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = Game.COLLISION_ENEMY
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_PROP | Game.COLLISION_VEHICLE | Game.COLLISION_PLAYER
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	if is_guardian:
		weapon = "energy"
		hp = 80.0
	else:
		match era_id:
			"jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi": weapon = "bow"
			"sengoku", "edo": weapon = "musket"
			"meiji_taisho": weapon = "rifle"
			"showa": weapon = "mg"
		# 中世までの兵の一部は刀・槍で斬りかかってくる（受け・受け流しで捌ける）
		if CraftDB.era_index(era_id) <= CraftDB.era_index("edo") and CraftDB.era_index(era_id) >= CraftDB.era_index("heian") and not is_leader and randf() < 0.35:
			weapon = "spear" if randf() < 0.4 else "blade"
		hp = 60.0
	var outfit := Humanoid.outfit_for(era_id, "guardian" if is_guardian else "enemy")
	_rig = Humanoid.build_streamed(outfit, randi(), true, -1, "", Humanoid.PRIORITY_GUARD)   # 近づくまで見た目は組み立てない（mission_target は自動で優先）
	_rig.rotation.y = PI
	add_child(_rig)
	if is_leader:
		hp *= 3.0
		_rig.scale = Vector3.ONE * 1.15
		cs.scale = Vector3.ONE * 1.15
	_tag = Label3D.new()
	_tag.text = label + ("（隊長）" if is_leader else "")
	_tag.font = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	_tag.font_size = 48
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = false
	_tag.outline_size = 10
	_tag.modulate = Effects.GUARD if is_guardian else Color(1, 0.45, 0.4)
	_tag.position = Vector3(0, 2.35 if not is_leader else 2.6, 0)
	add_child(_tag)
	_cool = randf_range(0.5, 2.0)
	_strafe = 1.0 if randf() < 0.5 else -1.0
	if is_guardian:
		var l := OmniLight3D.new()
		l.light_color = Effects.GUARD
		l.light_energy = 0.8
		l.omni_range = 4.0
		l.position = Vector3(0, 1.4, 0)
		add_child(l)


func take_hit(amount: float, from_team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if dead or from_team == 1:
		return
	hp -= amount
	_alert = true
	_rig.hurt()
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = Game.COLLISION_WORLD
	_rig.die()
	_tag.visible = false
	Sfx.play_at(get_tree(), Sfx.hit(), global_position, -4.0)
	if is_guardian:
		Effects.burst(get_tree(), global_position + Vector3.UP, Vector3.UP, Effects.GUARD, Effects.CYAN, 40, 6.0, 0.25, 0.9, -0.2, true, 180)
	Wanted.report(global_position, 0.35)
	# 自由探索の「歴史の揺らぎ」：兵の撃破（修正力は数えない）
	Game.chaos_event.emit("kill", label, {"type": "guardian" if is_guardian else "soldier", "era": era_id, "pos": global_position, "leader": is_leader})
	LootDrop.drop_for_enemy(self)   # 武器・弾・銭を落とす（拾える）
	killed.emit(self)
	await get_tree().create_timer(6.0 if not is_guardian else 1.2).timeout
	if is_inside_tree():
		queue_free()


func _physics_process(dt: float) -> void:
	if dead:
		if not is_on_floor():
			velocity = Vector3(0, velocity.y - 22.0 * dt, 0)
			move_and_slide()
		return
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	var target: Vector3 = p.global_position
	if p.in_vehicle():
		target = p.vehicle.global_position
	var to := target - global_position
	var dist := to.length()
	if dist < aggro_range:
		_alert = true
	if dist > aggro_range * 2.2 and not mission_target:
		_alert = false
	var move := Vector3.ZERO
	_think -= dt
	if _think <= 0.0:
		_think = randf_range(1.5, 3.5)
		_strafe = -_strafe
	if _alert:
		var flat := Vector3(to.x, 0, to.z).normalized()
		var ideal := (14.0 if weapon != "bow" else 22.0) if not is_melee() else 1.4
		if is_guardian: ideal = 10.0
		if dist > ideal + 6.0:
			move = flat
		elif dist < ideal - 5.0:
			move = -flat
		if is_melee():
			move = flat if dist > 1.8 else Vector3.ZERO   # 斬りかかる間合いまで詰める
			if _stun > 0.0 or _windup >= 0.0:
				move = Vector3.ZERO
		move += flat.cross(Vector3.UP) * _strafe * (0.6 if not is_melee() else 0.15)
		# 障害物回避（前方レイ）
		var space := get_world_3d().direct_space_state
		var eye := global_position + Vector3.UP * 0.8
		var q := PhysicsRayQueryParameters3D.create(eye, eye + move.normalized() * 2.0, Game.COLLISION_WORLD | Game.COLLISION_PROP)
		if not space.intersect_ray(q).is_empty():
			move = move.rotated(Vector3.UP, PI * 0.5 * _strafe)
		var face := flat
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), dt * 8.0)
		_rig.aiming = true
		_combat(dt, target, dist)
	else:
		var back := home - global_position
		back.y = 0
		if back.length() > 6.0:
			move = back.normalized() * 0.5
			rotation.y = lerp_angle(rotation.y, atan2(-back.x, -back.z), dt * 4.0)
		_rig.aiming = false
	var spd := 4.2 if not is_guardian else 6.0
	velocity.x = move.x * spd
	velocity.z = move.z * spd
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 22.0 * dt
	move_and_slide()
	_rig.speed = Vector2(velocity.x, velocity.z).length()
	var w = Game.world
	if w and global_position.y < w.height_at(global_position.x, global_position.z) - 3.0:
		global_position.y = w.height_at(global_position.x, global_position.z) + 1.0


## 主人公の強い振り・受け流しでよろける
func stagger(t: float) -> void:
	_stun = maxf(_stun, t)
	_windup = -1.0
	_cool = maxf(_cool, t)
	if _rig:
		_rig.hurt()


func is_melee() -> bool:
	return weapon in ["blade", "spear"]


func _melee(dt: float, dist: float) -> void:
	var p = Game.player
	if p == null:
		return
	var reach := 2.3 if weapon == "blade" else 3.2
	# 見た目の武器を刀・槍に替える（人の形は近づいてから組み立てられるので、その後で）
	if _rig and _rig.weapon and is_instance_valid(_rig.weapon) and _rig.weapon.get_node_or_null("ArmsModel") == null:
		for c in _rig.weapon.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false
		_rig.weapon.add_child(WeaponModels.build("uchigatana" if weapon == "blade" else "yari", 0.4))
	if _windup >= 0.0:
		_windup -= dt
		if _windup < 0.0:
			_cool = randf_range(1.2, 2.0)
			if dist < reach + 0.5 and not p.in_vehicle():
				p.take_hit(14.0 if weapon == "blade" else 12.0, 1, global_position + Vector3.UP * 1.2, (p.global_position - global_position).normalized())
				Sfx.play_at(get_tree(), Sfx.hit(), global_position, -4.0)
			else:
				Sfx.play_at(get_tree(), Sfx.whoosh(), global_position, -6.0)
		return
	_cool -= dt
	if dist < reach and _cool <= 0.0:
		_windup = 0.45    # 振りかぶる（この間に受けると受け流せる）
		_tag.modulate = Color(1, 0.9, 0.3)
		get_tree().create_timer(0.45).timeout.connect(func(): if is_instance_valid(_tag): _tag.modulate = Color(1, 0.45, 0.4))


func _combat(dt: float, target: Vector3, dist: float) -> void:
	if _stun > 0.0:
		_stun -= dt
		return
	if is_melee():
		_melee(dt, dist)
		return
	_cool -= dt
	var rng: float = {"bow": 55.0, "musket": 70.0, "rifle": 90.0, "mg": 80.0, "energy": 60.0}.get(weapon, 60.0)
	if dist > rng or _cool > 0.0:
		return
	var muzzle: Vector3 = _rig.muzzle.global_position if _rig.muzzle else global_position + Vector3.UP * 1.4
	var aim := target + Vector3.UP * 1.1
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle, aim, Game.COLLISION_WORLD)
	if not space.intersect_ray(q).is_empty():
		_cool = 0.6
		return   # 射線が通らない
	var inacc := 0.035 + dist * 0.0007
	if weapon == "bow":
		aim += Vector3.UP * dist * dist * 0.0017  # 山なり
	var dir := (aim - muzzle).normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * inacc
	Projectile.fire(get_tree(), muzzle, dir, weapon, 1)
	match weapon:
		"bow":
			_cool = randf_range(1.8, 2.8); Sfx.play_at(get_tree(), Sfx.bow(), muzzle, -2.0)
		"musket":
			_cool = randf_range(3.0, 4.2); Sfx.play_at(get_tree(), Sfx.musket(), muzzle, 0.0)
			Effects.burst(get_tree(), muzzle, dir, Color(0.85, 0.85, 0.85, 0.7), Color(0.6, 0.6, 0.6), 12, 2.5, 1.0, 1.6, -0.05, false, 25)
		"rifle":
			_cool = randf_range(1.3, 2.0); Sfx.play_at(get_tree(), Sfx.shot(), muzzle, -2.0)
		"mg":
			_burst += 1
			_cool = 0.12 if _burst % 5 != 0 else randf_range(1.5, 2.5)
			Sfx.play_at(get_tree(), Sfx.shot(), muzzle, -4.0)
		"energy":
			_cool = randf_range(0.9, 1.5); Sfx.play_at(get_tree(), Sfx.energy(), muzzle, -2.0)
	if weapon != "bow":
		Effects.muzzle(get_tree(), muzzle, dir, Effects.GUARD if is_guardian else Color(1, 0.75, 0.35))

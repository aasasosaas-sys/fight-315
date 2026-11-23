class_name ShipLaunch
extends CharacterBody3D
## 小舟・はしけ・内火艇（自分で操る乗り物）。沖の大きな船へ渡る・体当たりする・岸へ戻る。
## W/S 前進・後進、A/D 旋回、Shift 全速。F で降りる（近くの船の舷梯・岸・その場の水へ）。

var kind := "boat"
var display_name := "小舟"
var driver = null
var seat: Node3D
var speed := 0.0
var hp := 160.0
var era_id := ""
var _turn := 0.0
var _t := 0.0
var _dead := false
var _sound: AudioStreamPlayer3D
var modern := false


static func create(p_era: String, seed: int) -> ShipLaunch:
	var b := ShipLaunch.new()
	b.name = "Launch"
	b.era_id = p_era
	b._build(seed)
	return b


func _build(_seed: int) -> void:
	add_to_group("vehicle")
	collision_layer = Game.COLLISION_VEHICLE
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_VEHICLE | Game.COLLISION_PROP
	floor_snap_length = 0.0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.2, 1.1, 6.6)
	cs.shape = bx
	cs.position = Vector3(0, 0.35, 0)
	add_child(cs)
	modern = era_id in ["meiji_taisho", "showa"]
	display_name = "内火艇" if era_id == "showa" else ("汽艇" if era_id == "meiji_taisho" else ("伝馬船" if era_id in ["edo", "sengoku"] else "小舟"))
	var kit := MeshKit.new()
	var hull := Color(0.9, 0.9, 0.88) if modern else Color(0.72, 0.56, 0.4)
	var mat := "metal" if modern else "wood"
	# 船体: 先細りの箱を重ねる（前が -Z）
	for i in 8:
		var z0 := -3.3 + i * 0.825
		var t := absf((z0 + 0.41) / 3.3)
		var w := 2.1 * (1.0 - pow(t, 2.4) * 0.8)
		kit.box(mat, Transform3D(Basis(), Vector3(0, 0.25 + pow(t, 3.0) * 0.25, z0 + 0.41)), Vector3(w, 0.8 + pow(t, 3.0) * 0.4, 0.84), hull)
	kit.box("wood", Transform3D(Basis(), Vector3(0, 0.62, 0)), Vector3(1.8, 0.06, 5.8), Color(0.8, 0.68, 0.5))
	kit.box("flat", Transform3D(Basis(), Vector3(0, -0.12, 0)), Vector3(2.0, 0.25, 6.2), Color(0.55, 0.16, 0.12) if modern else Color(0.25, 0.18, 0.13))
	if modern:
		kit.box("plaster", Transform3D(Basis(), Vector3(0, 1.25, -0.6)), Vector3(1.6, 1.2, 2.4), Color(0.95, 0.95, 0.93))
		kit.box("glass", Transform3D(Basis(), Vector3(0, 1.45, -1.82)), Vector3(1.4, 0.5, 0.04), Color(0.4, 0.5, 0.6))
		kit.cylinder("metal", Transform3D(Basis(), Vector3(0, 1.8, 0.2)), 0.22, 0.22, 0.9, 8, Color(0.15, 0.15, 0.15))
	else:
		# 櫓（艪）
		kit.rod("wood", Vector3(0.3, 0.8, 2.8), Vector3(0.6, -0.3, 5.2), 0.05, 5, Color(0.55, 0.42, 0.28))
	add_child(kit.commit("LaunchMesh"))
	seat = Node3D.new()
	seat.name = "Seat"
	seat.position = Vector3(0, 0.55, 1.4)
	add_child(seat)
	_sound = Sfx.loop_player(self, Sfx.engine() if modern else Sfx.wind(), -10.0)


func get_speed() -> float: return absf(speed)
func get_velocity_vec() -> Vector3: return -global_basis.z * speed


func enter(p) -> void:
	driver = p
	if modern:
		_sound.play()
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("W/S 前進・後進  A/D 旋回  Shift 全速  F 降りる（船の舷梯のそばなら乗船）", 4.0)


func exit() -> void:
	driver = null
	speed *= 0.3
	if _sound.playing:
		_sound.stop()


## 降りる場所: 近くの船の舷梯 → 甲板へ。岸が近ければ岸へ。なければ舟のそばの水へ
func exit_point() -> Vector3:
	var p := global_position
	var best := 16.0
	var out := Vector3.INF
	for s in get_tree().get_nodes_in_group("ship"):
		var sh := s as Ship
		if sh == null or sh.phase == "wreck":
			continue
		var lz := float(sh.sd.ladder["z"])
		var side := float(sh.sd.ladder["side"])
		var hb := float(sh.sd.ladder.get("hb", sh.sd.B * 0.5))
		var bottom := sh.xf_cur * Vector3(side * (hb + 0.9), 0.4, lz + float(sh.sd.ladder.get("run", 4.0)) + 0.6)
		var d := Vector2(bottom.x - p.x, bottom.z - p.z).length()
		if d < best:
			best = d
			out = sh.xf_cur * Vector3(side * (hb - 1.6), sh.sd.top_at(lz) + 0.4, lz - 1.0)
		# 船体のすぐそば（低い船は舷側から乗り移る）
		var lp: Vector3 = sh.xf_cur.affine_inverse() * p
		if absf(lp.z) < sh.sd.L * 0.5 - 1.0 and absf(lp.x) < sh.sd.B * 0.5 + 4.0 and sh.sd.top_at(lp.z) < 3.5:
			out = sh.xf_cur * Vector3(signf(lp.x) * (sh.sd.half_beam(lp.z, sh.sd.top_at(lp.z) - 0.1) - 1.2), sh.sd.top_at(lp.z) + 0.4, lp.z)
			best = 0.0
	if out != Vector3.INF:
		return out
	var w = Game.world
	if w and w.has_method("height_at"):
		for k in 16:
			var a := TAU * k / 16.0
			for r: float in [3.0, 5.0, 8.0]:
				var q := p + Vector3(cos(a), 0, sin(a)) * float(r)
				var h := float(w.height_at(q.x, q.z))
				if h > 0.25:
					return Vector3(q.x, h + 0.3, q.z)
	return p + global_basis.x * 2.0 + Vector3.UP * 0.3


func take_hit(amount: float, _team: int, _point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		_dead = true
		if driver != null and driver.has_method("exit_vehicle"):
			driver.exit_vehicle()
		remove_from_group("vehicle")
		Effects.burst(get_tree(), global_position + Vector3.UP, Vector3.UP, Color(0.6, 0.45, 0.3), Color(0.3, 0.2, 0.1), 20, 6.0, 0.4, 1.2, 1.5, false, 40)


func _physics_process(dt: float) -> void:
	_t += dt
	if _dead:
		global_position.y -= dt * 0.6
		if global_position.y < -4.0:
			queue_free()
		return
	var throttle := 0.0
	var steer := 0.0
	var boost := false
	if driver != null and not Game.input_blocked:
		var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		throttle = mv.y
		steer = -mv.x
		boost = Input.is_action_pressed("sprint")
	var top := (9.0 if modern else 4.5) * (1.4 if boost else 1.0)
	speed = move_toward(speed, throttle * (top if throttle > 0.0 else top * 0.4), (3.0 if modern else 1.6) * dt)
	if throttle == 0.0:
		speed = move_toward(speed, 0.0, 0.8 * dt)
	_turn = lerpf(_turn, steer * clampf(absf(speed) / 2.5, 0.25, 1.0) * 1.1 * signf(speed if speed != 0.0 else 1.0), 1.0 - exp(-dt * 4.0))
	rotation.y += _turn * dt
	var fwd := -global_basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	var ty := -0.12 + sin(_t * 1.4) * 0.07
	velocity.y = (ty - global_position.y) * 6.0
	rotation.x = lerpf(rotation.x, clampf(speed * 0.006, -0.05, 0.08) + sin(_t * 1.1) * 0.012, dt * 3.0)
	rotation.z = lerpf(rotation.z, -_turn * 0.05 + sin(_t * 0.9) * 0.02, dt * 3.0)
	move_and_slide()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o = c.get_collider()
		if absf(speed) > 3.5 and o and o.has_method("ram"):
			o.ram(absf(speed) * 1.3, fwd * speed, 1.5)
		elif o and o.has_method("panic"):
			o.panic(global_position)
	if get_slide_collision_count() > 0 and absf(speed) > 1.0:
		speed *= 0.5
	global_position.x = clampf(global_position.x, -900.0, 900.0)
	global_position.z = clampf(global_position.z, -900.0, 900.0)
	if driver != null and modern:
		_sound.pitch_scale = lerpf(0.7, 1.6, clampf(absf(speed) / 12.0, 0.0, 1.0))
	if absf(speed) > 1.5 and int(_t * 6.0) % 2 == 0:
		Effects.burst(get_tree(), global_position + global_basis.z * 3.2 + Vector3(0, 0.1, 0), Vector3.UP, Color(0.95, 0.98, 1.0, 0.8), Color(0.8, 0.9, 1.0, 0.0), 2, 1.5, 0.5, 0.8, 0.3, false, 16)

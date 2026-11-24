class_name PlayerArms
extends Node
## 主人公の手持ち武器（Player の子）。Game.profile の「手にしている品」を使う。
##  素手   左クリック：拳（速い）／長押しして離す：蹴り（重い・吹き飛ばす）
##  刀・槍 左クリック：軽い振り／長押しして離す：強い振り（威力 ×1.8・刃が傷む）／右クリック：受け（受け始めの一瞬は「受け流し」）
##  弓     左クリック長押しで引き、離して放つ（引きが満ちるほど強い）。右クリックで狙う
##  銃     左クリック：撃つ（連射できる銃は押し続ける）／R：装填。火縄銃は引き金から一拍おくれて火が回り、不発もある
## 1 キー（破壊ツールが「手持ち」のとき）で持ち替え。技能（Skills）が振りの速さ・威力・受け・集弾・反動・装填・不発・刃の傷みに効く。

var player: Node3D
var _model: Node3D
var _model_uid := -999
var _rig_weapon: Node3D
var _charge := -1.0               # 左クリックを押している時間（近接・弓）
var _busy_until := 0.0            # 振り・装填などで次の動作ができない時刻
var _swing_end := 0.0
var _swing_heavy := false
var _swing_hit_at := 0.0
var _swing_pending := false
var blocking := false
var _block_start := 0.0
var reloading := false
var _reload_end := 0.0
var _next_shot := 0.0
var _hang_fire := -1.0            # 火縄銃：引き金を引いてから火が回る時刻
var _dist_acc := 0.0

const HEAVY_HOLD := 0.32


func _ready() -> void:
	player = get_parent() as Node3D


func prof() -> PlayerProfile:
	return Game.profile


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------ 持っている物
func current() -> Dictionary:
	var p := prof()
	return p.weapon() if p else {}


func current_id() -> String:
	var w := current()
	return str(w.get("id", "fists")) if not w.is_empty() else "fists"


func base() -> Dictionary:
	return CraftDB.item(current_id())


func kind() -> String:
	var t := str(base().get("type", "melee"))
	return "fists" if current_id() == "fists" else t


func skill_id() -> String:
	return str(base().get("skill", "kenjutsu"))


func skill_level() -> float:
	var p := prof()
	return p.level(skill_id()) if p else 0.0


func stats() -> Dictionary:
	var w := current()
	if w.is_empty():
		return Crafting.item_stats("fists", 0.5)
	return w.get("stats", {})


func weapon_name() -> String:
	var w := current()
	if w.is_empty():
		return "素手"
	return prof().item_label(w)


func ammo_id() -> String:
	return str(base().get("ammo", ""))


func reserve() -> int:
	var a := ammo_id()
	return prof().count(a) if a != "" and prof() else 0


func mag() -> int:
	return int(current().get("mag", 0))


func durability_ratio() -> float:
	var w := current()
	var mx := float(w.get("stats", {}).get("max_dur", 0.0))
	if w.is_empty() or mx <= 0.0:
		return -1.0
	return clampf(float(w.get("dur", 0.0)) / mx, 0.0, 1.0)


func broken() -> bool:
	var r := durability_ratio()
	return r >= 0.0 and r <= 0.0


## HUD 用：弾・状態の一行
func ammo_text() -> String:
	match kind():
		"gun":
			if base().get("infinite", false):
				return "リロード中…" if reloading else "%d / ∞" % mag()
			if _hang_fire > 0.0:
				return "火が回る…"
			return ("装填中…" if reloading else "%d / %d" % [mag(), reserve()])
		"bow":
			return "矢 %d" % reserve()
		"fists":
			return "受け" if blocking else ""
	return "受け" if blocking else ("刃こぼれ" if broken() else "")


## 持ち替え（素手 → 持っている武器 → …）
func cycle() -> void:
	var p := prof()
	if p == null:
		return
	var ws: Array = p.weapons()
	var order: Array = [-1]
	for w in ws:
		order.append(int(w["uid"]))
	var i := order.find(p.equipped)
	p.equip(order[(i + 1) % order.size()])
	_announce()


func equip(uid: int) -> void:
	prof().equip(uid)
	_announce()


func _announce() -> void:
	reloading = false
	_hang_fire = -1.0
	blocking = false
	var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud and hud.has_method("toast"):
		var hint: String = {"fists": "左クリック:殴る　長押し:蹴る", "melee": "左クリック:斬る　長押し:強く斬る　右クリック:受け",
			"bow": "長押しで引いて離す", "gun": "左クリック:撃つ　R:装填"}.get(kind(), "")
		hud.toast("%s を手にした　%s" % [weapon_name(), hint], 2.0)
	refresh_model()


# ------------------------------------------------------------------ 見た目
func refresh_model() -> void:
	var rig = player.get("rig") if player else null
	if rig == null or not is_instance_valid(rig):
		return
	var wnode: Node3D = rig.get("weapon")
	if wnode == null or not is_instance_valid(wnode):
		return
	var uid: int = prof().equipped if prof() else -1
	if wnode == _rig_weapon and uid == _model_uid and _model and is_instance_valid(_model):
		return
	_rig_weapon = wnode
	_model_uid = uid
	if _model and is_instance_valid(_model):
		_model.queue_free()
	for c in wnode.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	_model = WeaponModels.build(current_id(), float(current().get("q", 0.5)))
	wnode.add_child(_model)


func _muzzle_pos() -> Vector3:
	if _model and is_instance_valid(_model):
		var m := _model.get_node_or_null("Muzzle") as Node3D
		if m:
			return m.global_position
	return player.global_position + Vector3.UP * 1.4


# ------------------------------------------------------------------ 毎フレーム（Player から呼ぶ）
func tick(dt: float) -> void:
	refresh_model()
	var t := _now()
	var k := kind()
	var cam := CameraRig.I
	# 受け（右クリック）
	var want_block := k in ["melee", "fists"] and Input.is_action_pressed("aim")
	if want_block and not blocking:
		_block_start = t
	blocking = want_block and t >= _swing_end
	if cam and blocking:
		cam.aiming = false
	match k:
		"fists", "melee":
			_tick_melee(t)
		"bow":
			_tick_bow(t, dt)
		"gun":
			_tick_gun(t)
	if _swing_pending and t >= _swing_hit_at:
		_swing_pending = false
		_do_swing_hit()
	if _model and is_instance_valid(_model) and k in ["melee", "fists"]:
		# 振りの見た目：刀身を振り下ろす
		var f := 1.0 - clampf((_swing_end - t) / maxf(0.05, _swing_end - (_swing_hit_at - 0.08)), 0.0, 1.0) if t < _swing_end else 0.0
		_model.rotation_degrees.x = (-70.0 + 140.0 * f) if t < _swing_end else (-35.0 if blocking else 0.0)
		_model.rotation_degrees.z = 70.0 if blocking else 0.0


func _tick_melee(t: float) -> void:
	if Input.is_action_just_pressed("fire") and t >= _busy_until and not blocking:
		_charge = t
	if _charge >= 0.0 and not Input.is_action_pressed("fire"):
		var held := t - _charge
		_charge = -1.0
		swing(held >= HEAVY_HOLD)
	elif _charge >= 0.0:
		var rig = player.get("rig")
		if rig:
			rig.set("aiming", true)


## 振る（テストからも呼べる）
func swing(heavy: bool) -> void:
	var t := _now()
	if t < _busy_until:
		return
	var st := stats()
	var lv := skill_level()
	var dur := float(st.get("speed", 0.4)) * Skills.melee_time_mult(lv) * (1.6 if heavy else 1.0)
	_swing_heavy = heavy
	_swing_end = t + dur
	_busy_until = t + dur
	_swing_hit_at = t + dur * 0.4
	_swing_pending = true
	var rig = player.get("rig")
	if rig:
		rig.set("aiming", true)
	Sfx.play_at(get_tree(), Sfx.whoosh(), player.global_position + Vector3.UP * 1.3, -6.0 if not heavy else -2.0)


func _facing() -> Vector3:
	var cam := CameraRig.I
	var f := cam.flat_forward() if cam else -player.global_basis.z
	return f.normalized()


func _do_swing_hit() -> void:
	var st := stats()
	var lv := skill_level()
	var heavy := _swing_heavy
	var fists := kind() == "fists"
	var reach := float(st.get("reach", 1.7)) + (0.8 if player.call("in_vehicle") else 0.0)
	var dmg := float(st.get("damage", 10.0)) * Skills.melee_damage_mult(lv) * (1.8 if heavy else 1.0)
	if broken():
		dmg *= 0.35
	var fwd := _facing()
	var origin := player.global_position + Vector3.UP * 1.1
	_slash_fx(origin, fwd, reach, heavy)
	var hits := 0
	var seen := {}
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = reach * 0.6
	q.shape = sph
	q.transform = Transform3D(Basis(), origin + fwd * reach * 0.55)
	q.collision_mask = Game.COLLISION_ENEMY | Game.COLLISION_CIVILIAN | Game.COLLISION_PROP | Game.COLLISION_VEHICLE
	q.exclude = [(player as CollisionObject3D).get_rid()] if player is CollisionObject3D else []
	for r in space.intersect_shape(q, 16):
		var col: Object = r.get("collider")
		if col == null or not (col is Node3D) or seen.has(col):
			continue
		seen[col] = true
		var tp: Vector3 = (col as Node3D).global_position + Vector3.UP * 1.0
		var to := tp - origin
		to.y = 0.0
		if to.length() > 0.3 and fwd.angle_to(to.normalized()) > deg_to_rad(75.0):
			continue
		var target: Node = Effects.find_target(col as Node)
		Player.apply_hit(get_tree(), {"collider": col, "position": tp, "normal": -fwd}, fwd, dmg, Player.TEAM)
		if target and target.has_method("is_enemy"):
			hits += 1
			if (heavy or fists) and target is CharacterBody3D:
				(target as CharacterBody3D).velocity += fwd * (7.0 if heavy else 2.5) + Vector3.UP * (2.5 if heavy else 0.5)
			if target.has_method("stagger"):
				target.stagger(0.6 if heavy else 0.25)
		if col is RigidBody3D:
			(col as RigidBody3D).apply_impulse(fwd * (9.0 if heavy else 4.0))
	if hits > 0:
		Sfx.play_at(get_tree(), Sfx.hit(), origin + fwd, 0.0)
		Effects.shake = maxf(Effects.shake, 0.18 if heavy else 0.08)
		_hit_stop(0.05 if heavy else 0.03)
		prof().practice(skill_id(), 0.35 * hits)
		_wear((2.0 if heavy else 1.0) * hits)
	else:
		prof().practice(skill_id(), 0.03)


func _wear(amount: float) -> void:
	var w := current()
	if w.is_empty() or float(w.get("stats", {}).get("max_dur", 0.0)) <= 0.0:
		return
	var was := float(w.get("dur", 0.0))
	w["dur"] = maxf(0.0, was - amount * Skills.wear_mult(skill_level()))
	if was > 0.0 and float(w["dur"]) <= 0.0:
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("%sが傷んだ！（刃こぼれ：威力が落ちる。砥石か工房で直せる）" % CraftDB.item_name(current_id()), 3.0)


## 当たった瞬間の一瞬の静止（ヒットストップ）
func _hit_stop(sec: float) -> void:
	if Engine.time_scale != 1.0 or not is_inside_tree():
		return
	Engine.time_scale = 0.08
	get_tree().create_timer(sec, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _slash_fx(origin: Vector3, fwd: Vector3, reach: float, heavy: bool) -> void:
	var im := ImmediateMesh.new()
	var right := fwd.cross(Vector3.UP).normalized()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := 10
	for i in n + 1:
		var a := lerpf(-1.1, 1.1, float(i) / n)
		var d := (fwd * cos(a) + right * sin(a)).normalized()
		var tilt := Vector3.UP * (0.35 * sin(a) if not heavy else -0.25 * float(i) / n)
		im.surface_set_color(Color(1, 1, 1, 0.0))
		im.surface_add_vertex(origin + d * reach * 0.35 + tilt)
		im.surface_set_color(Color(0.85, 0.95, 1.0, 0.75 if heavy else 0.5))
		im.surface_add_vertex(origin + d * reach + tilt)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sess = get_tree().get_first_node_in_group("session")
	(sess if sess else get_tree().root).add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------ 受け（Player.take_hit から）
## 受けた被害を減らす。戻り値は実際の被害
func filter_damage(amount: float, _dir: Vector3) -> float:
	if not blocking or not (kind() in ["melee", "fists"]):
		return amount
	var lv := skill_level()
	var t := _now()
	if t - _block_start <= Skills.parry_window(lv) and kind() == "melee":
		# 受け流し：無傷で、近くの敵がよろける
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and not e.get("dead") and (e as Node3D).global_position.distance_to(player.global_position) < 3.5 and e.has_method("stagger"):
				e.stagger(1.4)
		Sfx.play_at(get_tree(), Sfx.hit(), player.global_position + Vector3.UP * 1.4, 2.0)
		Effects.spark(get_tree(), player.global_position + Vector3.UP * 1.4 + _facing() * 0.6, -_facing(), Color(1, 0.95, 0.7))
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("受け流し！", 1.0)
		prof().practice(skill_id(), 0.5)
		_wear(0.5)
		return 0.0
	var red := clampf(Skills.block_reduction(lv) + float(stats().get("block", 0.0)), 0.0, 0.92)
	if kind() == "fists":
		red *= 0.5
	_wear(amount * 0.05)
	prof().practice(skill_id(), 0.08)
	return amount * (1.0 - red)


# ------------------------------------------------------------------ 弓
func _tick_bow(t: float, _dt: float) -> void:
	var st := stats()
	var lv := skill_level()
	var full := float(st.get("draw", 0.7)) * Skills.bow_draw_mult(lv)
	if Input.is_action_just_pressed("fire") and t >= _busy_until and reserve() > 0:
		_charge = t
	elif Input.is_action_just_pressed("fire") and reserve() <= 0:
		_no_ammo()
	if _charge >= 0.0:
		var rig = player.get("rig")
		if rig:
			rig.set("aiming", true)
		if CameraRig.I:
			CameraRig.I.aiming = true
		if not Input.is_action_pressed("fire"):
			var frac := clampf((t - _charge) / maxf(0.1, full), 0.0, 1.0)
			_charge = -1.0
			if frac > 0.2:
				shoot_arrow(frac)


func draw_fraction() -> float:
	if _charge < 0.0 or kind() != "bow":
		return 0.0
	var full := float(stats().get("draw", 0.7)) * Skills.bow_draw_mult(skill_level())
	return clampf((_now() - _charge) / maxf(0.1, full), 0.0, 1.0)


func shoot_arrow(frac: float) -> void:
	if not prof().take("ya", 1):
		_no_ammo()
		return
	var st := stats()
	var lv := skill_level()
	_busy_until = _now() + 0.25
	var cam := CameraRig.I
	var from := _muzzle_pos()
	var dir := cam.aim_dir() if cam else -player.global_basis.z
	if cam:
		var ex: Array[RID] = [(player as CollisionObject3D).get_rid()] if player is CollisionObject3D else []
		var hit := cam.aim_hit(300.0, ex)
		if not hit.is_empty():
			dir = ((hit["position"] as Vector3) - from).normalized()
	var sway := Skills.aim_sway(lv) * (1.5 - frac)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * sway).normalized()
	var spd := float(st.get("arrow_speed", 45.0)) * Skills.bow_power_mult(lv) * lerpf(0.5, 1.0, frac)
	var dmg := float(st.get("damage", 20.0)) * Skills.bow_power_mult(lv) * lerpf(0.4, 1.0, frac) * (0.8 + 0.4 * prof().stack_quality("ya"))
	Arrow.fire(get_tree(), from, dir * spd, dmg)
	Sfx.play_at(get_tree(), Sfx.bow(), from, -2.0)
	prof().practice("kyujutsu", 0.06)
	_wear(0.3)
	Wanted.report(player.global_position, 0.015)


# ------------------------------------------------------------------ 銃
func _tick_gun(t: float) -> void:
	var b := base()
	var st := stats()
	var lv := skill_level()
	var inf: bool = b.get("infinite", false)
	if _hang_fire > 0.0 and t >= _hang_fire:
		_hang_fire = -1.0
		_discharge()
	if reloading and t >= _reload_end:
		reloading = false
		_finish_reload()
	var w := current()
	if not reloading and _hang_fire < 0.0:
		var want := Input.is_action_just_pressed("reload") and mag() < int(st.get("mag", 1))
		if want or (mag() <= 0 and (inf or reserve() > 0) and t >= _next_shot):
			start_reload()
	if reloading or _hang_fire > 0.0 or t < _next_shot:
		return
	var auto: bool = b.get("auto", false)
	var pressed := Input.is_action_pressed("fire") if auto else Input.is_action_just_pressed("fire")
	if not pressed:
		return
	if mag() <= 0:
		if Input.is_action_just_pressed("fire"):
			_no_ammo()
		return
	_next_shot = t + 1.0 / maxf(0.2, float(st.get("fire_rate", 1.0)))
	# 不発：品の不発率 × 技能 × 傷み（耐久が減るほど増える）× 弾の質
	var misfire := float(st.get("misfire", 0.0)) * Skills.misfire_mult(lv)
	var dr := durability_ratio()
	if dr >= 0.0:
		misfire *= 1.0 + 2.0 * (1.0 - dr)
	if ammo_id() != "":
		misfire += (1.0 - prof().stack_quality(ammo_id())) * 0.04
	if randf() < misfire:
		_misfire()
		return
	if current_id() == "hinawaju":
		# 火縄が火皿の口薬に落ち、火が回るまで一拍
		_hang_fire = t + 0.18
		Effects.burst(get_tree(), _muzzle_pos(), Vector3.UP, Color(1, 0.9, 0.6), Color(0.6, 0.6, 0.6), 6, 1.5, 0.3, 0.6, 0.0, true, 40)
		return
	_discharge()


func start_reload() -> void:
	var b := base()
	if not b.get("infinite", false) and reserve() <= 0:
		return
	reloading = true
	var t := float(stats().get("reload", 2.0)) * Skills.reload_mult(skill_level())
	_reload_end = _now() + t
	if current_id() == "hinawaju":
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and randf() < 0.3:
			hud.toast("早合を銃口から込め、カルカで突き固める……", 1.6)


func _finish_reload() -> void:
	var w := current()
	if w.is_empty():
		return
	var cap := int(stats().get("mag", 1))
	var need := cap - int(w.get("mag", 0))
	if base().get("infinite", false):
		w["mag"] = cap
		return
	var n := mini(need, reserve())
	if n > 0:
		prof().take(ammo_id(), n)
		w["mag"] = int(w.get("mag", 0)) + n
	prof().practice("shageki", 0.04)


func _misfire() -> void:
	var w := current()
	Sfx.play_at(get_tree(), Sfx.click(), player.global_position + Vector3.UP * 1.4, 0.0)
	var hud = get_tree().get_first_node_in_group("hud")
	if current_id() == "hinawaju":
		# 火皿の口薬だけ燃えて弾が出ない（火皿の火）
		Effects.burst(get_tree(), _muzzle_pos(), Vector3.UP, Color(0.9, 0.9, 0.9, 0.7), Color(0.5, 0.5, 0.5), 10, 1.2, 0.8, 1.2, -0.05, false, 30)
		w["mag"] = maxi(0, int(w.get("mag", 0)) - 1)
		if hud:
			hud.toast("不発！（火皿の火）", 1.2)
	elif hud:
		hud.toast("不発！", 1.0)
	_next_shot = _now() + 0.7


func _no_ammo() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("%sがない（倒した兵・蔵・店で手に入る。弾薬は工房で作れる）" % CraftDB.item_name(ammo_id()) if ammo_id() != "" else "弾がない", 2.0)
	Sfx.play(get_tree(), Sfx.click(), -6.0)


func _discharge() -> void:
	var w := current()
	if w.is_empty():
		return
	var b := base()
	var st := stats()
	var lv := skill_level()
	w["mag"] = maxi(0, int(w.get("mag", 0)) - 1)
	var cam := CameraRig.I
	if cam == null:
		return
	var rig = player.get("rig")
	if rig:
		rig.set("aiming", true)
	var ex: Array[RID] = [(player as CollisionObject3D).get_rid()] if player is CollisionObject3D else []
	var veh = player.get("vehicle")
	if veh != null and is_instance_valid(veh) and veh is CollisionObject3D:
		ex.append((veh as CollisionObject3D).get_rid())
	var hit := cam.aim_hit(500.0, ex)
	var muzzle_pos := _muzzle_pos()
	var spread := float(st.get("spread", 0.01)) * Skills.spread_mult(lv) * (1.0 if cam.aiming else 2.4) + (0.01 if player.call("in_vehicle") else 0.0)
	var end := cam.global_position + cam.aim_dir() * 500.0
	if not hit.is_empty():
		end = hit["position"]
	end += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread * muzzle_pos.distance_to(end)
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + (end - muzzle_pos).normalized() * 520.0)
	q.exclude = ex
	var h2 := space.intersect_ray(q)
	if not h2.is_empty():
		end = h2["position"]
	var dirv := (end - muzzle_pos).normalized()
	var future: bool = b.get("infinite", false)
	var col := Effects.CYAN if future else Color(1, 0.8, 0.45)
	Effects.muzzle(get_tree(), muzzle_pos, dirv, col)
	Effects.tracer(get_tree(), muzzle_pos, end, col, 0.03)
	if current_id() in ["hinawaju", "murataju"]:
		# 黒色火薬の白煙
		Effects.burst(get_tree(), muzzle_pos, dirv, Color(0.9, 0.9, 0.9, 0.7), Color(0.6, 0.6, 0.6), 16, 3.0, 1.2, 1.8, -0.05, false, 25)
		Sfx.play(get_tree(), Sfx.musket(), -4.0)
	else:
		Sfx.play(get_tree(), Sfx.shot(), -8.0)
	# 反動：技能が低いほど銃口が跳ね上がる
	cam.pitch = clampf(cam.pitch + float(st.get("recoil", 1.0)) * Skills.recoil_mult(lv) * 0.012, -1.3, 1.2)
	cam.yaw += randf_range(-1, 1) * float(st.get("recoil", 1.0)) * Skills.recoil_mult(lv) * 0.004
	Wanted.report(player.global_position, 0.025)
	var dmg := float(st.get("damage", 26.0))
	if ammo_id() != "":
		dmg *= 0.8 + 0.4 * prof().stack_quality(ammo_id())
	if broken():
		dmg *= 0.7
	var hit_enemy := false
	if not h2.is_empty():
		var tgt: Node = Effects.find_target(h2["collider"] as Node) if h2["collider"] is Node else null
		hit_enemy = tgt != null and tgt.has_method("is_enemy")
		Player.apply_hit(get_tree(), h2, dirv, dmg, Player.TEAM)
	prof().practice("shageki", 0.18 if hit_enemy else 0.02)
	if not future:
		_wear(0.5)


# ------------------------------------------------------------------ 矢
class Arrow extends Node3D:
	var vel := Vector3.ZERO
	var damage := 20.0
	var life := 6.0
	var _stuck := false

	static func fire(tree: SceneTree, from: Vector3, velocity: Vector3, dmg: float) -> Node3D:
		var a := Arrow.new()
		a.vel = velocity
		a.damage = dmg
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 0.85)
		mi.mesh = bm
		mi.material_override = Humanoid.mat(Color(0.6, 0.45, 0.28), 0.7)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.add_child(mi)
		var sess = tree.get_first_node_in_group("session")
		(sess if sess else tree.root).add_child(a)
		a.global_position = from
		return a

	func _physics_process(dt: float) -> void:
		life -= dt
		if life <= 0.0:
			queue_free()
			return
		if _stuck:
			return
		vel.y -= 6.0 * dt
		var from := global_position
		var to := from + vel * dt
		var q := PhysicsRayQueryParameters3D.create(from, to, Game.COLLISION_WORLD | Game.COLLISION_ENEMY | Game.COLLISION_VEHICLE | Game.COLLISION_PROP | Game.COLLISION_CIVILIAN)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			Player.apply_hit(get_tree(), hit, vel.normalized(), damage, Player.TEAM)
			var tgt: Node = Effects.find_target(hit["collider"] as Node) if hit["collider"] is Node else null
			if tgt and tgt.has_method("is_enemy") and Game.profile:
				Game.profile.practice("kyujutsu", 0.2)
			global_position = hit["position"]
			_stuck = true
			life = 3.0
			return
		global_position = to
		if vel.length_squared() > 0.01 and absf(vel.normalized().dot(Vector3.UP)) < 0.999:
			look_at(global_position + vel, Vector3.UP)

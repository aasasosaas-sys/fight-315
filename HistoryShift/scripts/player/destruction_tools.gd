class_name DestructionTools
extends Node
## プレイヤーの破壊ツール（ミッション中も自由探索でも使える）。Player の子。
## 1: 銃（既存）  2: 焙烙玉/手榴弾（投げる）  3: 火薬樽（置く）/ダイナマイト（投げる・明治以降）
## 4: 大筒/野砲（1 回目で設置、以降は照準点へ砲撃。R で置き直し）  5: 棒火矢（火を噴く矢・必ず延焼）
## G: いつでも焙烙玉を投げる。マウスホイール / LB・RB で切替。

const SLOTS := 5
var current := 0
var cannon: FieldCannon
var _cool := 0.0
var _player: Node3D


func _ready() -> void:
	_player = get_parent() as Node3D


func era_id() -> String:
	var w = Game.world
	if w and "era_id" in w:
		return String(w.era_id)
	return "edo"


func modern() -> bool:
	return era_id() in ["meiji_taisho", "showa"]


func tool_name(i: int) -> String:
	match i:
		0: return "銃"
		1: return "手榴弾" if era_id() == "showa" else "焙烙玉"
		2: return "ダイナマイト" if modern() else "火薬樽"
		3: return "野砲" if modern() else "大筒"
		4: return "棒火矢"
	return ""


func hint(i: int) -> String:
	match i:
		1: return "左クリック:投げる"
		2: return "左クリック:投げる" if modern() else "左クリック:足元に置く（4秒）"
		3: return "左クリック:設置→砲撃  R:置き直し" if cannon == null else "左クリック:砲撃  R:置き直し"
		4: return "左クリック:発射（火がつく）"
	return "G:焙烙玉"


## HUD 表示用
func hud_text() -> String:
	var s := "[%d] %s" % [current + 1, tool_name(current)]
	if current != 0:
		s += "   " + hint(current)
	s += "   G:" + tool_name(1)
	return s


func blocks_gun() -> bool:
	return current != 0


func _can_act() -> bool:
	if Game.input_blocked or _player == null:
		return false
	if _player.get("dead") == true:
		return false
	var v = _player.get("vehicle")
	if v != null and is_instance_valid(v):
		return false
	return true


func select(i: int) -> void:
	i = clampi(i, 0, SLOTS - 1)
	if i == current:
		return
	current = i
	Sfx.play(get_tree(), Sfx.click(), -8.0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("%s を構えた　%s" % [tool_name(i), hint(i)], 2.0)


func _physics_process(dt: float) -> void:
	_cool -= dt
	if Game.input_blocked:
		return
	for k in SLOTS:
		if Input.is_action_just_pressed("weapon_%d" % (k + 1)):
			select(k)
	if Input.is_action_just_pressed("weapon_next"):
		select((current + 1) % SLOTS)
	if Input.is_action_just_pressed("weapon_prev"):
		select((current + SLOTS - 1) % SLOTS)
	if not _can_act():
		return
	if Input.is_action_just_pressed("throw") and _cool <= 0.0:
		throw_bomb("grenade" if era_id() == "showa" else "horoku")
	if current == 0:
		return
	if current == 3 and Input.is_action_just_pressed("reload"):
		place_cannon()
		return
	if Input.is_action_just_pressed("fire") and _cool <= 0.0:
		use_current()


func use_current() -> void:
	match current:
		1: throw_bomb("grenade" if era_id() == "showa" else "horoku")
		2:
			if modern():
				throw_bomb("dynamite")
			else:
				drop_keg()
		3:
			if cannon == null or not is_instance_valid(cannon) or cannon.global_position.distance_to(_player.global_position) > 80.0:
				place_cannon()
			else:
				fire_cannon(aim_point())
		4: fire_hiya()


func aim_point() -> Vector3:
	var cam := CameraRig.I
	if cam == null:
		return _player.global_position + Vector3(0, 0, -30)
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	var hit := cam.aim_hit(600.0, ex)
	if not hit.is_empty():
		return hit["position"]
	return cam.global_position + cam.aim_dir() * 300.0


func _hand() -> Vector3:
	var cam := CameraRig.I
	var fwd := cam.flat_forward() if cam else -_player.global_basis.z
	return _player.global_position + Vector3.UP * 1.6 + fwd * 0.5


func throw_bomb(kind: String) -> ThrownBomb:
	_cool = 0.55
	var from := _hand()
	var target := aim_point()
	var d := target - from
	var flat := Vector3(d.x, 0, d.z)
	# 届く範囲なら放物線で狙う、遠ければ最大飛距離
	var v := 18.0 if kind != "dynamite" else 16.0
	var vel := Shell.ballistic(from, target, v) if flat.length() < v * v / 9.8 * 0.95 else (flat.normalized() * 0.72 + Vector3.UP * 0.7).normalized() * v
	if flat.length() < 1.0:
		vel = (CameraRig.I.aim_dir() if CameraRig.I else Vector3.FORWARD) * v
	var rig = _player.get("rig")
	if rig:
		rig.set("aiming", true)
	Sfx.play_at(get_tree(), Sfx.whoosh(), from, -4.0)
	return ThrownBomb.spawn(get_tree(), kind, from, vel, 0)


func drop_keg() -> ThrownBomb:
	_cool = 1.0
	var cam := CameraRig.I
	var fwd := cam.flat_forward() if cam else -_player.global_basis.z
	var p := _player.global_position + fwd * 1.3 + Vector3.UP * 0.6
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("火薬樽を置いた！ 離れろ！", 2.0)
	return ThrownBomb.spawn(get_tree(), "keg", p, Vector3.ZERO, 0)


func place_cannon() -> FieldCannon:
	_cool = 0.6
	if cannon != null and is_instance_valid(cannon):
		cannon.queue_free()
	var cam := CameraRig.I
	var fwd := cam.flat_forward() if cam else -_player.global_basis.z
	var p := _player.global_position + fwd * 2.5
	var w = Game.world
	if w and w.has_method("height_at"):
		p.y = w.height_at(p.x, p.z)
	cannon = FieldCannon.place(get_tree(), p, atan2(-fwd.x, -fwd.z), modern())
	Sfx.play_at(get_tree(), Sfx.hit(), p, -2.0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("%sを据えた。照準して左クリックで砲撃！" % tool_name(3), 2.5)
	return cannon


func fire_cannon(target: Vector3) -> void:
	if cannon == null or not is_instance_valid(cannon):
		return
	_cool = 0.3
	cannon.fire_at(target, 0)


func fire_hiya() -> Shell:
	_cool = 0.9
	var cam := CameraRig.I
	var from := _hand()
	var target := aim_point()
	var dir := (target - from).normalized()
	if cam and from.distance_to(target) < 2.0:
		dir = cam.aim_dir()
	Effects.burst(get_tree(), from, -dir, Color(1, 0.8, 0.4), Color(1, 0.3, 0.1), 16, 4.0, 0.3, 0.3, 0.0, true, 30)
	Sfx.play_at(get_tree(), Sfx.whoosh(), from, 0.0)
	Wanted.report(from, 0.05)
	return Shell.fire(get_tree(), "hiya", from + dir * 0.8, dir * 48.0, 0)

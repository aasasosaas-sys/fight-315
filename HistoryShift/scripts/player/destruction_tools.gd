class_name DestructionTools
extends Node
## プレイヤーの破壊ツール（ミッション中も自由探索でも使える）。Player の子。
## 1: 銃（既存）  2: 焙烙玉/手榴弾（投げる）  3: 火薬樽（置く）/ダイナマイト（投げる・明治以降）
## 4: 大筒/野砲（1 回目で設置、以降は照準点へ砲撃。R で置き直し）  5: 棒火矢（火を噴く矢・必ず延焼）
## G: いつでも焙烙玉を投げる。マウスホイール / LB・RB で切替。
## 1 は手持ちの武器（PlayerArms：素手・刀・弓・銃）。もう一度押すと持ち替え。
## 2〜5 は持ち物（Game.profile）の焙烙玉・手榴弾・火薬樽・ダイナマイト・大筒＋砲弾・棒火矢を使う（無ければ使えない）。
## 爆弾の威力・不発は作り手の品質（Crafting）、火薬樽・ダイナマイトは建築の技能でも上がる。

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
		0:
			var arms = _player.get("arms") if _player else null
			return arms.weapon_name() if arms != null else "銃"
		1: return "手榴弾" if _throw_kind() == "grenade" else "焙烙玉"
		2: return "ダイナマイト" if _drop_kind() == "dynamite" else "火薬樽"
		3: return "野砲" if modern() else "大筒"
		4: return "棒火矢"
	return ""


## 持ち物（無ければ -1 = 持ち物を使わない昔の動き。テストや Game.profile が無いとき）
func _have(id: String) -> int:
	return Game.profile.count(id) if Game.profile else -1


func _throw_kind() -> String:
	if _have("grenade") > 0:
		return "grenade"
	if _have("horoku") > 0:
		return "horoku"
	return "grenade" if era_id() == "showa" else "horoku"


func _drop_kind() -> String:
	if _have("dynamite") > 0:
		return "dynamite"
	if _have("keg") > 0:
		return "keg"
	return "dynamite" if modern() else "keg"


func _slot_item(i: int) -> String:
	match i:
		1: return _throw_kind()
		2: return _drop_kind()
		3: return "taihou"
		4: return "hiya"
	return ""


func slot_count(i: int) -> int:
	var id := _slot_item(i)
	if id == "":
		return -1
	if id == "taihou":
		return _have("hodan") if _have("taihou") > 0 else 0
	return _have(id)


## 持ち物から 1 つ使う。[使えたか, 品質]
func _consume(id: String) -> Array:
	if Game.profile == null:
		return [true, 0.5]
	if Game.profile.count(id) <= 0:
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("%sを持っていない（店・蔵・倒した兵から、または工房で作れる）" % CraftDB.item_name(id), 2.2)
		Sfx.play(get_tree(), Sfx.click(), -6.0)
		return [false, 0.0]
	var q := Game.profile.stack_quality(id)
	Game.profile.take(id, 1)
	return [true, q]


## 品質・建築の技能を爆弾に効かせる
func _apply_quality(b: Node, id: String, q: float) -> void:
	if b == null or Game.profile == null:
		return
	var st := Crafting.item_stats(id, q)
	var pw := float(st.get("power", 1.0))
	if id in ["keg", "dynamite"]:
		pw *= Skills.demolition_mult(Game.profile.level("architecture"))
	b.set("power", pw)
	b.set("dud", float(st.get("dud", 0.0)))
	Game.profile.practice("powder", 0.1)


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
	var n := slot_count(current)
	if n >= 0:
		s += " ×%d" % n
	if current != 0:
		s += "   " + hint(current)
	var g := slot_count(1)
	s += "   G:" + tool_name(1) + (" ×%d" % g if g >= 0 else "")
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
		var arms = _player.get("arms") if _player else null
		if i == 0 and arms != null:
			arms.cycle()   # もう一度 1 で持ち替え
		return
	current = i
	Sfx.play(get_tree(), Sfx.click(), -8.0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("%s を構えた　%s" % [tool_name(i), hint(i)], 2.0)


func _physics_process(dt: float) -> void:
	_cool -= dt
	# 運転中（と降りて 10 秒）の墜落・炎上は player_indirect として歴史に数える
	var veh = _player.get("vehicle") if _player else null
	if veh != null and is_instance_valid(veh):
		Destruction.note_player()
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
		var tk := _throw_kind()
		var c := _consume(tk)
		if c[0]:
			_apply_quality(throw_bomb(tk), tk, c[1])
	if current == 0:
		return
	if current == 3 and Input.is_action_just_pressed("reload"):
		if Game.profile == null or Game.profile.count("taihou") > 0:
			place_cannon()
		return
	if Input.is_action_just_pressed("fire") and _cool <= 0.0:
		use_current()


func use_current() -> void:
	match current:
		1:
			var tk := _throw_kind()
			var c := _consume(tk)
			if c[0]:
				_apply_quality(throw_bomb(tk), tk, c[1])
		2:
			var dk := _drop_kind()
			var c2 := _consume(dk)
			if c2[0]:
				_apply_quality(throw_bomb("dynamite") if dk == "dynamite" else drop_keg(), dk, c2[1])
		3:
			if cannon == null or not is_instance_valid(cannon) or cannon.global_position.distance_to(_player.global_position) > 80.0:
				if Game.profile == null or Game.profile.count("taihou") > 0:
					place_cannon()
				else:
					_consume("taihou")
			else:
				var c3 := _consume("hodan")
				if c3[0]:
					fire_cannon(aim_point())
		4:
			var c4 := _consume("hiya")
			if c4[0]:
				_apply_quality(fire_hiya(), "hiya", c4[1])


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

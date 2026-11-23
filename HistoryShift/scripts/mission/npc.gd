class_name Npc
extends Node3D
## 会話相手の歴史上の人物など。近づいて E で話す。
## data/actors に載っている人物なら、ミッション中も自由探索と同じ会話メニュー（scripts/mission/actor_interact.gd）が開く。
## そのため HistFigure と同じ名前の項目（figure_name / actor / questions / dead / talking / follow_target / home）を持つ。

var npc_name := "人物"
var lines: Array = []
var era_id := ""
var talked := false
var _rig: Humanoid
var _tag: Label3D
var _ring: MeshInstance3D
# 会話メニュー（ActorInteract）用。HistFigure と同じ名前
var figure_name := "人物"
var actor: Dictionary = {}            # data/actors の人物（知らない人なら {}）
var questions: Array = []             # 関わる問題の id（未来を語る）
var dead := false                     # ミッションの人物は倒れない
var talking := false
var follow_target: Node3D = null      # 連れて行く相手（プレイヤー）
var home := Vector3.ZERO
var hint_on := true


static func spawn(parent: Node, pos: Vector3, p_name: String, p_lines: Array, p_era: String) -> Npc:
	var n := Npc.new()
	n.npc_name = p_name
	n.figure_name = p_name
	n.lines = p_lines
	n.era_id = p_era
	n.actor = actor_for(p_name)
	parent.add_child(n)
	n.global_position = pos
	n.home = pos
	return n


## 名前 → data/actors の人物（表記ゆれは HistoryDB.actor_name、だめなら Figures.resolve で引く）。知らなければ {}
static func actor_for(p_name: String) -> Dictionary:
	if Game.db == null:
		return {}
	var a: Dictionary = Game.db.actor(p_name)
	if a.is_empty():
		var key := Figures.resolve(p_name)
		if key != "":
			a = Game.db.actor(key)
	return a


## data/actors に載っている人物か（会話メニューを開ける）
func is_actor() -> bool:
	return not actor.is_empty()


func _ready() -> void:
	if is_actor():
		var an := str(actor.get("name", ""))
		for qid in Game.db.q_actors:
			for c in Game.db.q_actors[qid]:
				if c["name"] == an and not (qid in questions):
					questions.append(qid)
	var outfit := Humanoid.outfit_for(era_id, "npc")
	if npc_name.contains("記録者"):
		outfit = Humanoid.Outfit.MONK
	_rig = Humanoid.build_streamed(outfit, hash(npc_name), false, 1 if Humanoid.is_female_name(npc_name) else 0, npc_name, Humanoid.PRIORITY_TARGET)
	_rig.rotation.y = PI
	add_child(_rig)
	var body := StaticBody3D.new()
	body.collision_layer = Game.COLLISION_CIVILIAN
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	body.add_child(cs)
	add_child(body)
	_tag = Label3D.new()
	var title := String(Figures.spec_for(npc_name).get("title", ""))
	_tag.text = npc_name if title == "" else npc_name + "\n" + title
	_tag.font = load("res://assets/fonts/NotoSerifJP-Bold.ttf")
	_tag.font_size = 56
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.outline_size = 12
	_tag.modulate = Color(1, 0.9, 0.55)
	_tag.position = Vector3(0, 2.4, 0)
	add_child(_tag)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.05
	_ring.mesh = tm
	_ring.material_override = Effects.emissive(Color(1, 0.85, 0.4), 2.0)
	_ring.position = Vector3(0, 0.05, 0)
	add_child(_ring)


## HistFigure と同じ呼び出し口（ミッションの人物にはヒント表示はない）
func refresh_hint() -> void:
	pass


func _process(dt: float) -> void:
	var p: Node3D = Game.player
	var moving := false
	if follow_target and is_instance_valid(follow_target):
		moving = _follow(dt)
	elif p and is_instance_valid(p):
		var to: Vector3 = p.global_position - global_position
		to.y = 0
		if to.length() < 12.0 and to.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z) + PI, dt * 3.0)
	if _rig:
		_rig.speed = 3.5 if moving else 0.0
	_ring.rotation.y += dt
	_ring.visible = not talked and follow_target == null
	_tag.modulate.a = 0.6 if talked else 1.0


## 連れて行く：プレイヤーの後をついて歩く（地面の高さに合わせる）。歩いたら true
func _follow(dt: float) -> bool:
	var to := follow_target.global_position - global_position
	to.y = 0
	var w = Game.world
	if to.length() > 40.0:
		global_position = follow_target.global_position + Vector3(2, 0, 2)   # 乗り物に置いていかれたら追いつく
	elif to.length() > 3.0:
		var spd := 6.0 if to.length() > 8.0 else 3.5
		global_position += to.normalized() * minf(spd * dt, to.length() - 3.0)
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z) + PI, dt * 6.0)
	else:
		return false
	if w and w.has_method("height_at"):
		global_position.y = float(w.height_at(global_position.x, global_position.z))
	return true

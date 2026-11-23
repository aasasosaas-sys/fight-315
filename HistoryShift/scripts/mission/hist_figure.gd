class_name HistFigure
extends CharacterBody3D
## 自由探索に現れる歴史上の人物（data/chaos の figures と data/actors の人物）。名所に護衛と一緒に立っている。
## - E で会話メニュー（scripts/mission/actor_interact.gd）：説得・未来を語る・守る・連れて行く・渡す・書状
## - 倒れた原因は問わない（銃・流れ弾・爆発・火・暴走した乗り物・追手の撃ち合い）。倒れると Game.chaos_event("kill", 名前,
##   {type: "figure", cause}) を出す。天皇・皇族・宗教者・学者・女性・外国人・町人（noncombatant）は町人と同じく倒れず逃げる
## - 予定（schedule）がある人物は時間になると名所へ向かう。あなたのせいで（会話・追い回し・負傷・連れ回し）遅れると
##   Game.chaos_event("delay", 名前, {event, cause}) を出す

signal killed(fig)

var figure_name := "人物"
var era_id := ""
var lines: Array = []
var hp := 120.0
var dead := false
var killable := true
var guards: Array = []
var home := Vector3.ZERO
var actor: Dictionary = {}
var follow_target: Node3D = null      # 連れて行く相手（プレイヤー）
var questions: Array = []             # 関わる問題の番号（ヒント表示用）
var hint_on := true
var _rig: Node3D
var _tag: Label3D
var _hint: Label3D
var _ring: MeshInstance3D
var _flee := 0.0
var _flee_from := Vector3.ZERO
var _greeted := false
var _last_cause := "player"
var _last_hit_t := -99.0
var _fire_t := 0.0
# 予定
var appointments: Array = []          # この時代の予定すべて（順にこなす）
var _appt_i := -1
var appointment: Dictionary = {}      # いまの予定 {event, at, year, ...}
var appt_start := 0.0                 # セッション開始からの秒で、向かい始める時刻
var appt_deadline := 0.0
var appt_goal := Vector3.ZERO
var delay_secs := 0.0                 # あなたのせいで遅れた秒数
var _delay_cause := ""
var _appt_done := false
var _t := 0.0
var talking := false                  # 会話メニュー中（引き止め）

const DELAY_MISS := 25.0              # これだけ遅れると予定に間に合わない


static func spawn(parent: Node, pos: Vector3, p_name: String, p_era: String, p_lines: Array = [], p_actor: Dictionary = {}) -> HistFigure:
	var f := HistFigure.new()
	f.figure_name = p_name
	f.era_id = p_era
	f.lines = p_lines
	f.actor = p_actor
	f.killable = p_actor.is_empty() or not HistoryActors.is_noncombatant(p_actor)
	parent.add_child(f)
	f.global_position = pos
	f.home = pos
	return f


## 車・馬の轢き判定や命中マーカーのため敵と同じ扱い（"enemy" グループには入れない）。倒せない人物は町人と同じ扱い
func is_enemy() -> bool:
	return killable


func _ready() -> void:
	add_to_group("figure")
	# 敵の弾（COLLISION_CIVILIAN を見る）にも、車（COLLISION_ENEMY を見る）にも当たるように両方の層に置く
	collision_layer = Game.COLLISION_ENEMY | Game.COLLISION_CIVILIAN
	collision_mask = Game.COLLISION_WORLD | Game.COLLISION_PROP | Game.COLLISION_VEHICLE
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	var outfit := Humanoid.outfit_for(era_id, "npc")
	_rig = Humanoid.build_streamed(outfit, hash(figure_name), false, 1 if (Humanoid.is_female_name(figure_name) or "woman" in actor.get("tags", [])) else 0, figure_name, Humanoid.PRIORITY_TARGET)
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
	_hint = Label3D.new()
	_hint.font = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	_hint.font_size = 40
	_hint.pixel_size = 0.006
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.outline_size = 10
	_hint.modulate = Color(0.4, 0.95, 1.0)
	_hint.position = Vector3(0, 2.9, 0)
	_hint.visible = false
	add_child(_hint)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0
	tm.outer_radius = 1.12
	_ring.mesh = tm
	_ring.material_override = Effects.emissive(Color(1, 0.75, 0.3), 1.6)
	_ring.position = Vector3(0, 0.05, 0)
	add_child(_ring)
	refresh_hint()


## 「この人物は第N問に関わる」（今の史実が確定解答と違う問題だけ）
func refresh_hint() -> void:
	if _hint == null:
		return
	var nums: PackedStringArray = []
	for qid in questions:
		var q: Dictionary = Game.db.by_id.get(qid, {})
		if q.is_empty() or Game.state.answer(q) < 0 or Game.state.is_correct(q):
			continue
		nums.append(str(Game.db.questions.find(q) + 1))
	_hint.text = ("第%s問に関わる" % "・".join(nums)) if not nums.is_empty() else ""
	_hint.visible = hint_on and not nums.is_empty() and not dead


## 次の予定へ（delay 秒後に出発、そこから 120 秒以内に着けば史実どおり）
func next_appointment(w, delay: float) -> void:
	_appt_i += 1
	if _appt_i >= appointments.size():
		appointment = {}
		return
	var sc: Dictionary = appointments[_appt_i]
	set_appointment(sc, w.landmark_pos(str(sc["at"])), _t + delay, _t + delay + 120.0)
	_appt_done = false
	delay_secs = 0.0


## 予定を設定する（出現から start 秒で出発、deadline 秒までに着けば史実どおり）
func set_appointment(sc: Dictionary, goal: Vector3, start: float, deadline: float) -> void:
	appointment = sc
	appt_goal = goal
	appt_start = start
	appt_deadline = deadline


# ------------------------------------------------------------------ 被害
## 被害の原因を推定する（意図したかどうかは問わない）
func _cause_for(from_team: int) -> String:
	var p = Game.player
	match from_team:
		0:
			if p and is_instance_valid(p) and p.in_vehicle():
				var v: Node3D = p.vehicle
				if v.global_position.distance_to(global_position) < 7.0:
					var k := str(v.get("kind"))
					return "horse" if k == "horse" else ("plane" if k == "plane" else "vehicle")
			return "shot"
		1:
			return "crossfire" if Wanted.stars() > 0 else "stray"
		-2:
			return "fire"
		-3:
			return "debris"
	return "explosion"


func take_hit(amount: float, from_team: int, point := Vector3.ZERO, _dir := Vector3.ZERO) -> void:
	if dead:
		return
	_last_cause = _cause_for(from_team)
	_flee = 7.0
	_flee_from = point if point != Vector3.ZERO else global_position + Vector3.FORWARD
	_alert_guards()
	_add_delay(6.0, "襲われて逃げ回った")
	if not killable:
		return   # 倒れない（伏せて逃げる）
	hp -= amount
	_last_hit_t = Time.get_ticks_msec() / 1000.0
	if _rig.has_method("hurt"):
		_rig.call("hurt")
	Wanted.report(global_position, 0.2)
	if hp <= 0.0:
		_die()
	else:
		_add_delay(20.0, "けがをした")


## 銃声や爆発に驚いた（町人と同じ panic）
func panic(from: Vector3) -> void:
	if dead or global_position.distance_to(from) > 50.0:
		return
	_flee = maxf(_flee, 4.0)
	_flee_from = from
	_add_delay(3.0, "騒ぎに驚いて逃げた")


func _add_delay(sec: float, why: String) -> void:
	if appointment.is_empty() or _appt_done:
		return
	delay_secs += sec
	_delay_cause = why


func _alert_guards() -> void:
	for g in guards:
		if is_instance_valid(g) and not g.dead:
			g.aggro_range = 140.0
			g._alert = true


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = Game.COLLISION_WORLD
	follow_target = null
	_tag.visible = false
	_hint.visible = false
	_ring.visible = false
	if _rig.has_method("die"):
		_rig.call("die")
	Sfx.play_at(get_tree(), Sfx.hit(), global_position, -2.0)
	Effects.burst(get_tree(), global_position + Vector3.UP, Vector3.UP, Color(1, 0.8, 0.35), Effects.CYAN, 36, 5.0, 0.3, 1.0, -0.2, true, 160)
	Wanted.report(global_position, 1.2)
	_alert_guards()
	Game.chaos_event.emit("kill", figure_name, {"type": "figure", "era": era_id, "pos": global_position, "cause": _last_cause})
	killed.emit(self)
	await get_tree().create_timer(10.0).timeout
	if is_inside_tree():
		queue_free()


# ------------------------------------------------------------------ 動き
func _physics_process(dt: float) -> void:
	if dead:
		if not is_on_floor():
			velocity = Vector3(0, velocity.y - 22.0 * dt, 0)
			move_and_slide()
		return
	_t += dt
	var p = Game.player
	var move := Vector3.ZERO
	var spd := 0.0
	_flee = maxf(0.0, _flee - dt)
	if talking:
		_add_delay(dt, "あなたに引き止められた")
	elif _flee > 0.0:
		var away := global_position - _flee_from
		away.y = 0
		move = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		spd = 5.0
	elif follow_target and is_instance_valid(follow_target):
		var to := follow_target.global_position - global_position
		to.y = 0
		if to.length() > 40.0:
			global_position = follow_target.global_position + Vector3(2, 0.5, 2)   # 乗り物に置いていかれたら追いつく
		elif to.length() > 3.0:
			move = to.normalized()
			spd = 6.0 if to.length() > 8.0 else 3.5
		_add_delay(dt, "あなたに連れ回された")
	elif not appointment.is_empty() and not _appt_done and _t >= appt_start:
		var tg := appt_goal - global_position
		tg.y = 0
		if tg.length() > 6.0:
			move = tg.normalized()
			spd = 3.2
	else:
		var back := home - global_position
		back.y = 0
		if back.length() > 3.0:
			move = back.normalized()
			spd = 1.6
	_check_appointment()
	if move.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z), dt * 6.0)
	elif p and is_instance_valid(p):
		var to2: Vector3 = (p as Node3D).global_position - global_position
		to2.y = 0
		if to2.length() < 14.0 and to2.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-to2.x, -to2.z), dt * 3.0)
		if not _greeted and to2.length() < 8.0 and not lines.is_empty():
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
	_fire_t -= dt
	if _fire_t <= 0.0:
		_fire_t = 0.5
		_burn_check()
	var w = Game.world
	if w and global_position.y < w.height_at(global_position.x, global_position.z) - 3.0:
		global_position.y = w.height_at(global_position.x, global_position.z) + 1.0


## 燃えている建物のそばにいると火に巻かれる・崩れた建物の瓦礫で道をふさがれる
func _burn_check() -> void:
	var w = Game.world
	if w == null or not ("destruction" in w) or w.get("destruction") == null:
		return
	var d = w.get("destruction")
	if not d.has_method("units_near"):
		return
	for u in d.units_near(global_position, 5.0):
		if u.get("burning"):
			take_hit(10.0, -2, global_position)
			return
		if u.get("destroyed") and velocity.length() < 0.5 and not appointment.is_empty() and _t >= appt_start:
			_add_delay(0.5, "崩れた瓦礫で道をふさがれた")


func _check_appointment() -> void:
	if appointment.is_empty() or _appt_done or _t < appt_deadline:
		return
	_appt_done = true
	if delay_secs >= DELAY_MISS:
		Game.chaos_event.emit("delay", figure_name, {"era": era_id, "event": str(appointment.get("event", "")), "cause_text": _delay_cause, "pos": global_position})
	elif not dead:
		global_position = appt_goal + Vector3(2, 0.5, 0)   # 史実どおり間に合った（回り道をしてでも）
		home = global_position
	if not dead and Game.world:
		next_appointment(Game.world, 40.0)

class_name Wanted
extends Node
## 時空警戒度（★0〜5）。暴れると上がり、その時代の追手（検非違使・捕り方・巡査・憲兵…）と歴史の修正力が段階的に追ってくる。

static var heat := 0.0
static var _last_report := -99.0
static var enabled := true
## 民間人の犠牲（scripts/core/civil_harm.gd。設定オンのときだけ増える）。1人でも出たこの時空跳躍では警戒度が下がりきらない
static var civil_count := 0
const CIVIL_FLOOR := 4.0

var era_id := ""
var _spawn_t := 0.0
var _pursuers: Array = []
var _air: Array = []

const GUARDS := {
	"jomon_kofun": "ムラの戦士", "asuka_nara": "衛府の兵", "heian": "検非違使", "kamakura_muromachi": "侍所の武士",
	"sengoku": "足軽の追手", "edo": "町奉行所の捕り方", "meiji_taisho": "巡査隊", "showa": "憲兵隊",
}


static func stars() -> int:
	return clampi(int(floor(heat)), 0, 5)


static func report(_pos: Vector3, amount: float) -> void:
	if not enabled:
		return
	heat = clampf(heat + amount, 0.0, 5.99)
	_last_report = Time.get_ticks_msec() / 1000.0


static func clear() -> void:
	heat = CIVIL_FLOOR if civil_count > 0 else 0.0


## 民間人が倒れた：警戒度は最大に跳ね上がる
static func civil_casualty(_pos: Vector3) -> void:
	civil_count += 1
	if not enabled:
		return
	heat = 5.99
	_last_report = Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	civil_count = 0   # 時空跳躍（Session）ごとに数え直す


func _process(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_pursuers = _pursuers.filter(func(e): return is_instance_valid(e) and not e.dead)
	_air = _air.filter(func(e): return is_instance_valid(e) and not e.dead)
	# 一定時間おとなしくしていると下がる
	if now - _last_report > 12.0:
		heat = maxf(CIVIL_FLOOR if civil_count > 0 else 0.0, heat - dt * 0.12)
	var s := stars()
	if s == 0:
		for e in _pursuers:
			if is_instance_valid(e) and e.global_position.distance_to(Game.player.global_position if Game.player else Vector3.ZERO) > 90.0:
				e.queue_free()
		return
	_spawn_t -= dt
	if _spawn_t > 0.0 or Game.player == null or Game.world == null:
		return
	_spawn_t = 6.0
	var want := s * 2 + (3 if civil_count > 0 else 0)   # 民間人の犠牲が出ると追手が増える
	if _pursuers.size() < want:
		var p: Node3D = Game.player.vehicle if Game.player.in_vehicle() else Game.player
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ang := rng.randf() * TAU
		var c := p.global_position + Vector3(cos(ang), 0, sin(ang)) * 70.0
		var pos: Vector3 = Game.world.random_ground_point_near(c, 15.0, rng)
		var label: String = GUARDS.get(era_id, "追手")
		if s >= 4 and rng.randf() < 0.5:
			label = "歴史の修正力"
		var n := mini(want - _pursuers.size(), 3)
		for i in n:
			var e := Enemy.spawn(get_parent(), pos + Vector3(i * 1.5, 0.5, 0), label, era_id)
			e.aggro_range = 140.0
			if civil_count > 0:
				e.hp *= 1.5   # 民間人の犠牲が出ると、より手ごわい追手（精鋭）が来る
			_pursuers.append(e)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast(("民を害した者として%sが総出で追ってくる" if civil_count > 0 else "%sが追ってくる！") % label)
	if s >= 5 and era_id == "showa" and _air.size() < 2:
		var p2: Node3D = Game.player
		_air.append(AirEnemy.spawn(get_parent(), p2.global_position + Vector3(300, 180, 300), "修正力の飛行隊"))

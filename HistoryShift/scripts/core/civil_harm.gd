class_name CivilHarm
extends RefCounted
## 設定「民間人への危害（成人向け）」（既定オフ）。tools/SCHEMA_V2.md「data/chaos_civil」を参照。
## - オフ（既定）・教育版・DLC 未所有：町人は従来どおり倒れない（伏せて逃げる）。このクラスは何もしない。
## - オン：名もない町人（農民・職人・商人・町人・漁民）だけが、プレイヤーが原因の被害（銃・矢・刀・爆発・火・瓦礫・乗り物）で倒れる。
##   流血・死体・部位欠損はない（アニメ調に倒れて数秒で消える）。名のある人物（女性・宗教者・学者・天皇・皇族・外国人など
##   noncombatant）は HistFigure 側の扱いのままで、この設定に関係なく倒れない。
## - 史実の虐殺・戦災に重なる場面（data/chaos_civil/exclusions.json）では設定を無視する（町人は倒れない）。
## - 倒れると Game.chaos_event("casualty", 名所, {count, landmark, era, role, cause, pos})。手配度は最大に跳ね上がり下がりにくくなる。
##   歴史への影響は data/chaos_civil/<era>.json のルール（ChaosTracker が読む）。

const DIR := "res://data/chaos_civil"
static var ledger_path := "user://civil_ledger.json"   # テストは差し替える
const LANDMARK_RADIUS := 90.0
const ROLES := ["農民", "職人", "商人", "町人", "漁民"]
const UNREST_STEPS := [3, 8, 15]     # この自由探索での犠牲者数 → 民心離反の段階 1..3

static var _loaded := false
static var _eras: Dictionary = {}          # eraId -> {roles, rules}
static var _excl: Dictionary = {}          # exclusions.json
static var _ledger: Dictionary = {}        # eraId -> 犠牲者数（この世界の記録。新しいゲームで消える）
static var _ledger_loaded := false


# ------------------------------------------------------------------ 設定
## 設定がオンで、かつ成人向けコンテンツが使える
static func enabled() -> bool:
	if not MatureContent.is_unlocked():
		return false
	return bool(GameSettings.values.get("civil_harm", false))


# ------------------------------------------------------------------ データ
static func load_data(force := false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	_eras.clear()
	_excl = {}
	if MatureContent.is_edu() or not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(f)))
		if typeof(d) != TYPE_DICTIONARY:
			push_warning("chaos_civil/%s: JSON を読めません" % f)
			continue
		if f == "exclusions.json":
			_excl = d
		else:
			_eras[str(d.get("eraId", f.get_basename()))] = d


static func rules_for(era_id: String) -> Array:
	load_data()
	return _eras.get(era_id, {}).get("rules", [])


static func role_for(era_id: String, landmark: String) -> String:
	load_data()
	var roles: Dictionary = _eras.get(era_id, {}).get("roles", {})
	return str(roles.get(landmark, roles.get("town", "町人")))


static func exclusions() -> Dictionary:
	load_data()
	return _excl


# ------------------------------------------------------------------ 除外（史実の虐殺・戦災に重なる場面）
## 自由探索の名所、またはミッション（問題・選択肢・手段）が除外の場面か
static func excluded(era_id: String, landmark: String, q_id := "", choice := -1, method := "") -> bool:
	var ex := exclusions()
	for e in ex.get("eras", []):
		if str(e.get("era", "")) == era_id:
			return true
	for e in ex.get("landmarks", []):
		if str(e.get("era", "")) == era_id and str(e.get("at", "")) == landmark:
			return true
	if q_id != "":
		for e in ex.get("missions", []):
			if str(e.get("q", "")) != q_id:
				continue
			if e.has("choice") and int(e["choice"]) != choice:
				continue
			if e.has("method") and str(e["method"]) != method:
				continue
			return true
	return false


## いまの場面（Session の種類・ミッション）と位置で、町人が倒れうるか
static func allowed_here(tree: SceneTree, era_id: String, pos: Vector3) -> bool:
	if not enabled():
		return false
	var lm := landmark_of(pos)
	var s: Node = tree.get_first_node_in_group("session") if tree else null
	var qid := ""
	var ch := -1
	var meth := ""
	if s != null:
		var mode := str(s.get("mode"))
		if mode == "backdrop":
			return false
		if mode == "mission":
			var q: Variant = s.get("question")
			qid = str((q as Dictionary).get("id", "")) if q is Dictionary else ""
			ch = int(s.get("choice"))
			var m: Variant = s.get("mission")
			meth = str((m as Dictionary).get("method", "")) if m is Dictionary else ""
	return not excluded(era_id, lm, qid, ch, meth)


static func landmark_of(pos: Vector3) -> String:
	var w = Game.world
	if w == null or not is_instance_valid(w) or not w.has_method("landmark_pos"):
		return "town"
	var best := "town"
	var bd := LANDMARK_RADIUS
	for k in HistoryDB.LANDMARK_KEYS:
		var lp: Vector3 = w.landmark_pos(k)
		var d := Vector2(lp.x - pos.x, lp.z - pos.z).length()
		if d < bd:
			bd = d
			best = k
	return best


## 被害の原因がプレイヤーか（team 0 = プレイヤー。-1 世界・-2 火・-3 瓦礫は、直前にプレイヤーが何かを起こしていれば間接）
static func player_caused(team: int, unit_cause := "") -> bool:
	if team == 0:
		return true
	if team >= 1:
		return false
	if unit_cause != "":
		return unit_cause in ["player", "player_indirect"]
	return Time.get_ticks_msec() / 1000.0 - Destruction.last_player_t < Destruction.INDIRECT_WINDOW


# ------------------------------------------------------------------ 犠牲
static func on_casualty(era_id: String, pos: Vector3, cause: String) -> Dictionary:
	_load_ledger()
	_ledger[era_id] = int(_ledger.get(era_id, 0)) + 1
	_save_ledger()
	var lv0 := unrest_level()
	Wanted.civil_casualty(pos)
	var lv := unrest_level()
	var tree := Engine.get_main_loop() as SceneTree
	var hud = tree.get_first_node_in_group("hud") if tree else null
	if hud and lv > lv0:
		hud.banner(["", "民心離反 ― 人々はあなたを恐れて逃げる", "民心離反 ― 村々に一揆の気配", "民心離反 ― 町じゅうが騒然としている"][lv], Color(0.75, 0.75, 0.82), 3.0)
	var lm := landmark_of(pos)
	var info := {"count": 1, "landmark": lm, "era": era_id, "role": role_for(era_id, lm), "cause": cause, "pos": pos}
	if Game.has_signal("chaos_event"):
		Game.chaos_event.emit("casualty", lm, info)
	return info


## 民心離反の段階（0〜3）。この時空跳躍での犠牲者数から
static func unrest_level() -> int:
	var n := 0
	for s in UNREST_STEPS:
		if Wanted.civil_count >= s:
			n += 1
	return n


## 今回の時空跳躍での犠牲者（Wanted が Session ごとに数え直す）
static func session_count() -> int:
	return Wanted.civil_count


static func total() -> int:
	_load_ledger()
	var n := 0
	for k in _ledger:
		n += int(_ledger[k])
	return n


static func era_total(era_id: String) -> int:
	_load_ledger()
	return int(_ledger.get(era_id, 0))


static func reset_ledger() -> void:
	_ledger.clear()
	_ledger_loaded = true
	if FileAccess.file_exists(ledger_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ledger_path))


static func _load_ledger() -> void:
	if _ledger_loaded:
		return
	_ledger_loaded = true
	if FileAccess.file_exists(ledger_path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ledger_path))
		if d is Dictionary:
			_ledger = d


static func _save_ledger() -> void:
	var f := FileAccess.open(ledger_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_ledger))


## エンディング・アフター画面に添える一文（犠牲がなければ ""）。功績のようには書かない
static func ending_note() -> String:
	var n := total()
	if n <= 0:
		return ""
	return "この世界の歴史の陰には、時空の旅人のせいで命を落とした名もない人々がいる（犠牲者 %d 人）。年表には一行も残らないが、その一人ひとりに暮らしと家族があった。失われた命は、どの改変でも取り戻せない。" % n

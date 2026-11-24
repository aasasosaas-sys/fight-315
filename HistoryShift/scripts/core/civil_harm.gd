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
## - このクラスはデータ・除外・記録だけ（Game や Wanted に依存しない。HistoryState・ChaosTracker から使う）。
##   ゲーム中の判定（場面・名所・原因・倒れたときの処理）は scripts/mission/civil_runtime.gd（CivilRuntime）。

const DIR := "res://data/chaos_civil"
static var ledger_path := "user://civil_ledger.json"   # テストは差し替える
const ROLES := ["農民", "職人", "商人", "町人", "漁民"]

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


## 犠牲の記録（この世界の記録。新しいゲームで消える）
static func add_to_ledger(era_id: String) -> void:
	_load_ledger()
	_ledger[era_id] = int(_ledger.get(era_id, 0)) + 1
	_save_ledger()


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

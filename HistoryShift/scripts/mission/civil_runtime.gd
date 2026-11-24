class_name CivilRuntime
extends RefCounted
## 「民間人への危害（成人向け）」のゲーム中の判定（scripts/core/civil_harm.gd のデータ・除外・記録を使う）。
## 町人（scripts/mission/civilian.gd）と HUD から呼ぶ。

const LANDMARK_RADIUS := 90.0
const UNREST_STEPS := [3, 8, 15]     # この時空跳躍での犠牲者数 → 民心離反の段階 1..3


## いまの場面（Session の種類・ミッション）と位置で、町人が倒れうるか
static func allowed_here(tree: SceneTree, era_id: String, pos: Vector3) -> bool:
	if not CivilHarm.enabled():
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
	return not CivilHarm.excluded(era_id, lm, qid, ch, meth)


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
	CivilHarm.add_to_ledger(era_id)
	var lv0 := unrest_level()
	Wanted.civil_casualty(pos)
	var lv := unrest_level()
	var tree := Engine.get_main_loop() as SceneTree
	var hud = tree.get_first_node_in_group("hud") if tree else null
	if hud and lv > lv0:
		hud.banner(["", "民心離反 ― 人々はあなたを恐れて逃げる", "民心離反 ― 村々に一揆の気配", "民心離反 ― 町じゅうが騒然としている"][lv], Color(0.75, 0.75, 0.82), 3.0)
	var lm := landmark_of(pos)
	var info := {"count": 1, "landmark": lm, "era": era_id, "role": CivilHarm.role_for(era_id, lm), "cause": cause, "pos": pos}
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

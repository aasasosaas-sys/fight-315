class_name ChaosTracker
extends RefCounted
## 自由探索の「歴史の揺らぎ」（data/chaos/<era>.json）。
## Game.chaos_event(kind, id, info) を受けて時代ごとに出来事を数え、ルールの条件を満たしたら
## HistoryState.apply_chaos で歴史を書き換える（介入 cause "chaos"／歴史パラメータの変化）。
## 自由探索中（begin_session 〜 end_session）だけ有効。ミッション中の撃破や破壊は歴史を揺らさない。
##
## ルールの trigger（辞書、または「どれか1つ」を表す配列）:
##   kind  "destroy" / "sink" / "fire" / "bridge" / "kill"（必須）
##   id    名所キー（castle 等）や人物名。文字列または配列
##   type  info.type（kill の "soldier" / "figure"、destroy の建物の種類 "castle_keep" "pagoda" "hangar" など）。文字列または配列
##   at    出来事の起きた名所キー（info.landmark、id が名所キーならそれ、または info.pos に最も近い名所）
##   min   条件に合う出来事の数がこの値以上で発動（既定 1）。fire は名所ごとの延焼数 info.count（累計）の最大値の合計
##   value 条件に合う destroy の info.value（建物の格：家 30・御殿 200・塔 800・天守 5000 …）の合計がこの値以上
## 破壊の信号は scripts/world/destruction.gd が出す（建物1棟ごとの destroy、5/12/24 棟ごとの fire、sink、bridge）。

signal shifted(hit: Dictionary)

const DIR := "res://data/chaos"
const LANDMARK_RADIUS := 90.0

var db: HistoryDB
var state: HistoryState
var rules_by_era: Dictionary = {}     # eraId -> Array[rule]
var figures_by_era: Dictionary = {}   # eraId -> Array[{name, at, guards, guard, lines}]
var errors: PackedStringArray = []

var active_era := ""                  # 自由探索中の時代（"" = 無効）
var world: Node = null                # landmark_pos(key) を持つワールド（at 判定用、任意）
var events: Array = []                # 今回の自由探索の出来事 [{kind, id, type, at, count}]
var fired: Dictionary = {}            # 今回発動したルール id -> true
var session_hits: Array = []          # 今回発動した結果（最後の自由探索のぶんを end_session 後も保持）
var tally: Dictionary = {}            # 集計 kind -> 数（表示用）


func _init(p_db: HistoryDB, p_state: HistoryState, dir := DIR) -> void:
	db = p_db
	state = p_state
	load_rules(dir)


func load_rules(dir := DIR) -> void:
	rules_by_era.clear()
	figures_by_era.clear()
	if not DirAccess.dir_exists_absolute(dir):
		return
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if typeof(d) != TYPE_DICTIONARY:
			errors.append("chaos/%s: JSON を読めません" % f)
			continue
		var era := str(d.get("eraId", f.get_basename()))
		rules_by_era[era] = d.get("rules", [])
		figures_by_era[era] = d.get("figures", [])


func rules_for(era_id: String) -> Array: return rules_by_era.get(era_id, [])
func figures_for(era_id: String) -> Array: return figures_by_era.get(era_id, [])


func all_rules() -> Array:
	var out: Array = []
	for e in rules_by_era:
		out.append_array(rules_by_era[e])
	return out


func find_rule(rule_id: String) -> Dictionary:
	for r in all_rules():
		if r.get("id", "") == rule_id:
			return r
	return {}


# ------------------------------------------------------------------ セッション
func begin_session(era_id: String, p_world: Node = null) -> void:
	active_era = era_id
	world = p_world
	events.clear()
	fired.clear()
	session_hits.clear()
	tally.clear()


func end_session() -> Array:
	active_era = ""
	world = null
	return session_hits


func is_active() -> bool:
	return active_era != ""


# ------------------------------------------------------------------ 出来事
## Game.chaos_event のハンドラ
func on_event(kind: String, id: String, info: Dictionary) -> void:
	record(kind, id, info)


## 出来事を記録し、発動したルールの結果（hit の配列）を返す。テストからも直接呼べる。
func record(kind: String, id: String, info: Dictionary = {}) -> Array:
	if active_era == "" or state == null:
		return []
	var era := str(info.get("era", active_era))
	if era != "" and era != active_era:
		return []
	var ev := {"kind": kind, "id": id, "type": str(info.get("type", "")), "at": _landmark_of(kind, id, info),
		"count": maxi(1, int(info.get("count", 1))), "value": int(info.get("value", 100))}
	events.append(ev)
	tally[kind] = int(tally.get(kind, 0)) + (1 if kind != "fire" else 0)
	var hits: Array = []
	for r in rules_for(active_era):
		var rid := str(r.get("id", ""))
		if rid == "" or fired.has(rid):
			continue
		if not _trigger_hit(r.get("trigger", {}), ev):
			continue
		if not _satisfied(r.get("trigger", {})):
			continue
		fired[rid] = true
		if state.chaos_in_effect(r):
			continue
		var hit := _apply(r)
		if not hit.is_empty():
			hits.append(hit)
	return hits


func _landmark_of(kind: String, id: String, info: Dictionary) -> String:
	if info.has("landmark"):
		return str(info["landmark"])
	if info.has("at"):
		return str(info["at"])
	if kind != "kill" and id in HistoryDB.LANDMARK_KEYS:
		return id
	var pos: Variant = info.get("pos", null)
	if pos is Vector3 and world != null and is_instance_valid(world) and world.has_method("landmark_pos"):
		var best := ""
		var bd := LANDMARK_RADIUS
		for k in HistoryDB.LANDMARK_KEYS:
			var lp: Vector3 = world.landmark_pos(k)
			var d := Vector2(lp.x - (pos as Vector3).x, lp.z - (pos as Vector3).z).length()
			if d < bd:
				bd = d
				best = k
		return best
	return ""


static func _id_ok(want: Variant, ev: Dictionary) -> bool:
	var ids: Array = want if want is Array else [want]
	for w in ids:
		if str(w) == ev["id"] or (ev["kind"] == "destroy" and str(w) == ev["at"]):
			return true
	return false


## この出来事が trigger のどれかの条件に当てはまるか
func _trigger_hit(t: Variant, ev: Dictionary) -> bool:
	for c in (t if t is Array else [t]):
		if _cond_match(c, ev):
			return true
	return false


static func _cond_match(c: Dictionary, ev: Dictionary) -> bool:
	if str(c.get("kind", "")) != ev["kind"]:
		return false
	if c.has("id") and not _id_ok(c["id"], ev):
		return false
	if c.has("type"):
		var types: Array = c["type"] if c["type"] is Array else [c["type"]]
		if not (ev["type"] in types):
			return false
	if c.has("at") and str(c["at"]) != ev["at"]:
		return false
	return true


## これまでの出来事が trigger のどれか1つの min / value に届いたか
func _satisfied(t: Variant) -> bool:
	for c in (t if t is Array else [t]):
		if _metric(c) >= int(c.get("value", c.get("min", 1))):
			return true
	return false


func _metric(c: Dictionary) -> int:
	var n := 0
	if c.has("value"):
		for ev in events:
			if _cond_match(c, ev):
				n += int(ev["value"])
		return n
	if str(c.get("kind", "")) == "fire":
		var per := {}
		for ev in events:
			if _cond_match(c, ev):
				per[ev["at"]] = maxi(int(per.get(ev["at"], 0)), int(ev["count"]))
		for k in per:
			n += int(per[k])
		return n
	for ev in events:
		if _cond_match(c, ev):
			n += 1
	return n


## 今回の自由探索で燃えた建物の数（名所ごとの最大の合計）
func fire_total() -> int:
	return _metric({"kind": "fire"})


func _apply(r: Dictionary) -> Dictionary:
	var before := {}
	for q in db.questions:
		before[q["id"]] = state.is_correct(q)
	var changes := state.apply_chaos(r, active_era)
	var broke := false
	var fixed := false
	for c in changes:
		var q: Dictionary = c["question"]
		if state.answer(q) < 0:
			continue
		var ok := state.is_correct(q)
		c["was_correct"] = before.get(q["id"], false)
		c["now_correct"] = ok
		if before.get(q["id"], false) and not ok:
			broke = true
		elif not before.get(q["id"], false) and ok:
			fixed = true
	var hit := {"rule": r, "id": r.get("id", ""), "era": active_era, "title": r.get("title", ""), "text": r.get("text", ""),
		"changes": changes, "broke": broke, "fixed": fixed}
	session_hits.append(hit)
	shifted.emit(hit)
	return hit


## 今回の自由探索で起きた変化をまとめて返す（同じ問題は最後の結果だけ。アフター画面用）
func session_changes() -> Array:
	var seen := {}
	var out: Array = []
	for h in session_hits:
		for c in h["changes"]:
			var id: String = c["question"]["id"]
			if seen.has(id):
				var prev: Dictionary = out[seen[id]]
				prev["to"] = c["to"]
				continue
			seen[id] = out.size()
			out.append(c.duplicate())
	return out.filter(func(c): return c["from"] != c["to"])

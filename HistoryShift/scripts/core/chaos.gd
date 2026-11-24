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

## 行動の出来事（kind = 動詞）と、trigger で絞り込める info のキー
const VERB_KINDS := ["protect", "escort", "persuade", "give", "steal", "forge", "delay", "battle"]
const EXTRA_KEYS := ["arg", "item", "to", "event", "side", "cause", "cause_text"]
const SABOTAGE_VALUE := 400      # 手作りルールに当たらない破壊は、名所ごとに格の合計がこれを超えたら一般則で歴史を揺らす
const BATTLE_KILLS := 5          # 合戦で一方の兵をこれだけ倒すと、もう一方に加勢したことになる

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
var _sabotaged: Dictionary = {}       # 今回、一般則で壊した名所
var _battle_kills: Dictionary = {}    # "合戦id/側" -> 倒した数
var _battle_done: Dictionary = {}
var _taught: Dictionary = {}          # 今回教えた「人物/技能」
var _anachro: Dictionary = {}         # 今回過去に残した時代錯誤の品
var civil_events: Array = []          # 今回の民間人の犠牲 [{at, role, count, cause}]（設定オン時のみ。scripts/core/civil_harm.gd）


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
		var rs: Array = d.get("rules", [])
		# 人物名は表記ゆれをそろえる（「老中 田沼意次」→「田沼意次」）
		for r in rs:
			var t: Variant = r.get("trigger", {})
			for c in (t if t is Array else [t]):
				if c is Dictionary and c.has("id") and str(c.get("kind", "")) != "destroy":
					var ids: Array = c["id"] if c["id"] is Array else [c["id"]]
					var norm: Array = ids.map(func(x): return db.actor_name(str(x)) if db.actor_name(str(x)) != "" else str(x))
					c["id"] = norm if c["id"] is Array else norm[0]
		rules_by_era[era] = rs
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
	_sabotaged.clear()
	_battle_kills.clear()
	_battle_done.clear()
	_taught.clear()
	_anachro.clear()
	civil_events.clear()


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
	if kind == "casualty":
		return _record_casualty(id, info)
	if db.actor_name(id) != "":
		id = db.actor_name(id)
		# 一度倒れた人物はもう倒れない（同じ人物の死で二重に歴史を揺らさない）
		if kind == "kill" and str(info.get("type", "")) == "figure" and _actor_gone(id):
			return []
	var ev := {"kind": kind, "id": id, "type": str(info.get("type", "")), "at": _landmark_of(kind, id, info),
		"count": maxi(1, int(info.get("count", 1))), "value": int(info.get("value", 100))}
	for k in EXTRA_KEYS:
		if info.has(k):
			ev[k] = str(info[k])
	if kind == "kill" and not ev.has("cause"):
		ev["cause"] = "player"
	if kind != "kill" and db.actor_name(id) != "":
		ev["at"] = str(info.get("landmark", ev["at"]))
	events.append(ev)
	tally[kind] = int(tally.get(kind, 0)) + (1 if kind != "fire" else 0)
	var hits: Array = []
	var matched := false   # 手作りルールの条件に当てはまる出来事は、一般則では扱わない（ルールが発動済みでも）
	for r in rules_for(active_era):
		var rid := str(r.get("id", ""))
		if rid == "" or not _trigger_hit(r.get("trigger", {}), ev):
			continue
		matched = true
		if fired.has(rid):
			continue
		if not _satisfied(r.get("trigger", {})):
			continue
		fired[rid] = true
		if state.chaos_in_effect(r):
			continue
		var hit := _apply(r)
		if not hit.is_empty():
			hits.append(hit)
	if hits.is_empty() and not matched:
		hits.append_array(_generic(kind, id, info, ev))
	elif matched:
		_record_ruled(kind, id, info)
	if kind == "kill" and str(info.get("type", "")) == "soldier":
		hits.append_array(_battle_kill(id))
	return hits


## 民間人の犠牲（kind "casualty"）。data/chaos_civil/<era>.json のルールだけで解決する（一般則・既存の data/chaos は使わない）。
## 教育版・未所有ではルールを読まないので何も起きない。史実の虐殺・戦災に重なる場面（exclusions.json）は数えない
func _record_casualty(id: String, info: Dictionary) -> Array:
	if not MatureContent.is_unlocked():
		return []
	var lm := str(info.get("landmark", id if id != "" else "town"))
	if CivilHarm.excluded(active_era, lm):
		return []
	var ev := {"kind": "casualty", "at": lm, "role": str(info.get("role", CivilHarm.role_for(active_era, lm))),
		"count": maxi(1, int(info.get("count", 1))), "cause": str(info.get("cause", ""))}
	civil_events.append(ev)
	tally["casualty"] = int(tally.get("casualty", 0)) + int(ev["count"])
	var hits: Array = []
	for r in CivilHarm.rules_for(active_era):
		var rid := str(r.get("id", ""))
		if rid == "" or fired.has(rid) or not civil_satisfied(r.get("trigger", {}), civil_events):
			continue
		fired[rid] = true
		if state.chaos_in_effect(r):
			continue
		_add_recovery(r)
		var hit := _apply(r)
		if not hit.is_empty():
			hit["civil"] = true
			hit["unrest"] = bool(r.get("unrest", false))
			hits.append(hit)
	return hits


## 人の数・職人の技の損失は一、二世代で戻る（rule.recover 年後に vars を打ち消す変化を積む）。制度の変化（徳政令・刀狩など）は戻らない
func _add_recovery(r: Dictionary) -> void:
	if not r.has("recover"):
		return
	var rid2 := str(r["id"]) + "_rec"
	for m in state.chaos_mods:
		if m.get("rule", "") == rid2:
			return
	var neg := {}
	for k in (r.get("vars", {}) as Dictionary):
		neg[k] = -float(r["vars"][k])
	var ry := int(r.get("year", 0)) + int(r["recover"])
	state.chaos_mods.append({"rule": rid2, "era": db.era_of_year(ry), "year": ry, "effects": neg, "title": "（回復）" + str(r.get("title", ""))})


## 犠牲の出来事が trigger（辞書か「どれか1つ」の配列：at・role・min）を満たすか。min は人数の合計
static func civil_satisfied(t: Variant, evs: Array) -> bool:
	for c in (t if t is Array else [t]):
		if not (c is Dictionary) or str(c.get("kind", "casualty")) != "casualty":
			continue
		var n := 0
		for ev in evs:
			if c.has("at") and not (str(ev["at"]) in (c["at"] if c["at"] is Array else [c["at"]]).map(func(x): return str(x))):
				continue
			if c.has("role") and not (str(ev["role"]) in (c["role"] if c["role"] is Array else [c["role"]]).map(func(x): return str(x))):
				continue
			n += int(ev["count"])
		if n >= int(c.get("min", 1)):
			return true
	return false


## 手作りルールに当たらなかった出来事を一般則（HistoryActors）で解決する
func _generic(kind: String, id: String, info: Dictionary, ev: Dictionary) -> Array:
	var out: Array = []
	var nm := db.actor_name(id)
	match kind:
		"kill":
			if str(info.get("type", "")) == "figure" and nm != "" and not _actor_gone(nm):
				out.append(_act({"verb": "kill", "target": nm, "cause": ev.get("cause", "player")}))
		"destroy", "fire", "bridge", "sink":
			var key: String = ev["at"] if ev["at"] != "" else (id if id != "" else "town")
			if _sabotaged.has(key):
				return out
			var c := {"kind": kind}
			c["at"] = key
			var total := 0
			for e2 in events:
				if e2["kind"] in ["destroy", "bridge", "sink"] and e2["at"] == key:
					total += int(e2["value"])
				elif e2["kind"] == "fire" and e2["at"] == key:
					total = maxi(total, int(e2["count"]) * 60)
			if total >= SABOTAGE_VALUE or kind == "bridge":
				_sabotaged[key] = true
				out.append(_act({"verb": "sabotage", "target": key, "value": total}))
		"protect", "escort", "give", "steal", "forge", "delay":
			if nm != "":
				var a := {"verb": kind, "target": nm}
				for k in EXTRA_KEYS:
					if info.has(k):
						a[k] = info[k]
				out.append(_act(a))
		"persuade":
			if nm != "":
				var ok := HistoryActors.persuade_ok(db.actors[nm], str(info.get("arg", "")), trust(nm) + int(info.get("skill_bonus", 0)))
				if ok:
					out.append(_act({"verb": "persuade", "target": nm, "arg": info.get("arg", ""), "ok": true}))
				else:
					out.append({"refused": true, "id": "", "title": "%sは「%s」をはねつけた" % [nm, info.get("arg", "")], "changes": []})
		"steer":
			if nm != "" and db.by_id.has(str(info.get("q", ""))):
				var ok2 := HistoryActors.steer_ok(db.actors[nm], str(info["q"]), int(info.get("choice", 0)), trust(nm) + int(info.get("skill_bonus", 0)))
				if ok2:
					out.append(_act({"verb": "steer", "target": nm, "q": str(info["q"]), "choice": int(info.get("choice", 0)), "ok": true}))
				else:
					out.append({"refused": true, "id": "", "title": "%s「……証拠を見せてもらおう」" % nm, "changes": []})
		"battle":
			pass
		"teach":
			# 技術を教える（actor_interact の「技術を教える」）：人物がいればその人に、いなければその土地の職人に伝わる
			var sk := str(info.get("skill", ""))
			var tkey := (nm if nm != "" else id) + "/" + sk
			if sk != "" and not _taught.has(tkey) and not _done_before("teach", nm if nm != "" else id, {"skill": sk}):
				_taught[tkey] = true
				out.append(_act({"verb": "teach", "target": nm if nm != "" else id, "skill": sk, "level": int(info.get("level", 0))}))
		"industry":
			# 主人公が過去に建てた施設（工場・高炉・鉄道・学校…）。id = 施設の種類。同じ名所の同じ規模は一度だけ
			var sc := int(info.get("scale", 1))
			var lm := str(info.get("landmark", ev.get("at", "")))
			# stage "run" = 稼働が軌道に乗った（建てたときとは別に一度だけ）
			var stg := str(info.get("stage", ""))
			if not _done_before("industry", id, {"landmark": lm, "scale": sc, "stage": stg}):
				var ia := {"verb": "industry", "target": id, "landmark": lm, "scale": sc, "mult": float(info.get("mult", 1.0)), "bonus": bool(info.get("bonus", false))}
				if stg != "":
					ia["stage"] = stg
				out.append(_act(ia))
		"anachronism":
			# 時代錯誤の品が過去に残った（渡した・落とした・職人の前で作った）。同じ品は一度の自由探索で一度だけ
			var item := str(info.get("item", id))
			var gap := int(info.get("gap", 0))
			if gap > 0 and not _anachro.has(item):
				_anachro[item] = true
				var a2 := {"verb": "anachronism", "target": nm if nm != "" else item, "item": item, "gap": gap,
					"type": str(info.get("type", CraftDB.item_type(item))), "cause": str(info.get("cause", "lost"))}
				out.append(_act(a2))
		"project":
			if db.projects.has(id) and WarModel.available(db, state.actions, state.war.get("pillars", {}), id)[0]:
				out.append(_act({"verb": "project", "target": id}))
	return out.filter(func(h): return not h.is_empty())


## 同じ時代で同じ行動（同じ相手・同じ中身）をもう記録したか（教えた技・建てた施設は二重に効かない）
func _done_before(verb: String, target: String, keys: Dictionary) -> bool:
	for a in state.actions:
		if str(a.get("verb", "")) != verb or str(a.get("era", "")) != active_era or str(a.get("target", "")) != target:
			continue
		var same := true
		for k in keys:
			if str(a.get(k, "")) != str(keys[k]):
				same = false
		if same:
			return true
	return false


## 手作りルールに当たった人物への行動も記録だけはする（ruled: true）。効果はルールに任せ、一般則の効果は出さないが、
## 人物の状態（倒れた・救われた・信頼・後継者の判定）には数える
func _record_ruled(kind: String, id: String, info: Dictionary) -> void:
	var nm := db.actor_name(id)
	if nm == "":
		return
	if kind == "kill" and (str(info.get("type", "")) != "figure" or _actor_gone(nm)):
		return
	if not (kind in ["kill", "protect", "escort", "give", "persuade", "steal", "forge", "delay"]):
		return
	var a := {"verb": kind, "target": nm, "ruled": true, "era": active_era, "ok": true}
	for k in EXTRA_KEYS:
		if info.has(k):
			a[k] = info[k]
	state.record_action(a)


## UI（会話メニュー）からの行動。手作りルール → 一般則の順に解決し、hit（断られたら refused: true）を返す
func act(verb: String, target: String, info: Dictionary = {}) -> Dictionary:
	var inf := info.duplicate()
	inf["era"] = active_era
	var hs := record(verb, target, inf)
	return hs[0] if not hs.is_empty() else {}


## その人物への信頼（贈り物・命を救った・聞き入れた説得）
func trust(nm: String) -> int:
	var t := 0
	for a in state.actions:
		if db.actor_name(str(a.get("target", ""))) == nm:
			match str(a.get("verb", "")):
				"give", "persuade":
					t += 1
				"protect":
					t += 2
	return t


func _actor_gone(nm: String) -> bool:
	for a in state.actions:
		if str(a.get("target", "")) == nm and str(a.get("verb", "")) in ["kill"]:
			return true
	return false


## 合戦の兵を倒した：倒した側の相手に加勢したことになる
func _battle_kill(label: String) -> Array:
	for b in db.battles:
		if str(b.get("era", "")) != active_era or _battle_done.has(b["id"]):
			continue
		var sides: Array = b.get("sides", [])
		for i in sides.size():
			if str(sides[i].get("label", "")) != label:
				continue
			var key := "%s/%d" % [b["id"], i]
			_battle_kills[key] = int(_battle_kills.get(key, 0)) + 1
			if int(_battle_kills[key]) >= BATTLE_KILLS:
				_battle_done[b["id"]] = true
				var other: Dictionary = sides[(i + 1) % sides.size()]
				if other.has("wins"):
					var hs := record("battle", str(b["id"]), {"side": other["name"], "era": active_era})
					if not hs.is_empty():
						return hs
					return [_act({"verb": "battle", "target": b["id"], "side": other["name"], "battle_name": b.get("name", "")})]
	return []


func _act(a: Dictionary) -> Dictionary:
	a["era"] = active_era
	var war_before := state.war_tier()
	var before := _snapshot()
	var changes := state.apply_action(a)
	var last: Dictionary = state.actions[-1]
	return _finish("act%d" % int(last["seq"]), HistoryActors.headline(db, last), str(last.get("text", "")), changes, before,
		{"action": last, "war_before": war_before, "war_after": state.war_tier()})


func _snapshot() -> Dictionary:
	var before := {}
	for q in db.questions:
		before[q["id"]] = state.is_correct(q)
	return before


func _finish(id: String, title: String, text: String, changes: Array, before: Dictionary, extra: Dictionary) -> Dictionary:
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
	var hit := {"id": id, "era": active_era, "title": title, "text": text, "changes": changes, "broke": broke, "fixed": fixed}
	hit.merge(extra)
	session_hits.append(hit)
	shifted.emit(hit)
	return hit


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
	for k in EXTRA_KEYS:
		if c.has(k):
			var want: Array = c[k] if c[k] is Array else [c[k]]
			if not (str(ev.get(k, "")) in want.map(func(x): return str(x))):
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
	var war_before := state.war_tier()
	var before := _snapshot()
	var changes := state.apply_chaos(r, active_era)
	return _finish(str(r.get("id", "")), str(r.get("title", "")), str(r.get("text", "")), changes, before,
		{"rule": r, "war_before": war_before, "war_after": state.war_tier()})


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

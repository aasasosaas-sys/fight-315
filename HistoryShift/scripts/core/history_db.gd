class_name HistoryDB
extends RefCounted
## res://data の全JSON（tools/SCHEMA.md）を読み込み、年代順の問題リストと因果ルールを保持する。

const ERA_ORDER := ["jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"]
const LANDMARK_KEYS := ["capital", "village", "temple", "port", "castle", "battlefield", "mountain"]

var eras: Array = []            # Array[Dictionary]（ERA_ORDER 順）
var questions: Array = []       # Array[Dictionary]（年代順）。各問に "era" キーで所属時代の Dictionary を持たせる
var by_id: Dictionary = {}
var rules: Array = []
var errors: PackedStringArray = []
var modern: Dictionary = {}     # data/modern.json（現代エンディングの分岐）
var actors: Dictionary = {}     # 人物名 -> 人物データ（data/actors/<era>.json、HistoryActors が使う）
var actor_alias: Dictionary = {} # 別名 -> 人物名
var battles: Array = []         # 合戦（data/actors/<era>.json の battles）
var q_actors: Dictionary = {}   # qid -> [{name, at}]（その問題に関わる人物と、会える名所）


static func load_all(dir := "res://data") -> HistoryDB:
	var db := HistoryDB.new()
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(f))
		var d = JSON.parse_string(text)
		if typeof(d) != TYPE_DICTIONARY:
			db.errors.append("%s: JSON を読めません" % f)
			continue
		if f.begins_with("rules_"):
			db.rules.append_array(d.get("rules", []))
			continue
		if f == "modern.json":
			db.modern = d
			continue
		db.eras.append(d)
		db.rules.append_array(d.get("rules", []))
		for q in d.get("questions", []):
			q["era"] = d
			q["year"] = int(q["year"])
			q["real"] = int(q["real"])
			var per := {}
			for m in q.get("missions", []):
				m["choice"] = int(m["choice"])
				m["method_index"] = per.get(m["choice"], 0)
				per[m["choice"]] = m["method_index"] + 1
			if not q.has("effects"):
				q["effects"] = [{}, {}, {}, {}]
			if not q.has("resolve"):
				q["resolve"] = []
			db.by_id[q["id"]] = q
	db.eras.sort_custom(func(a, b): return ERA_ORDER.find(a["eraId"]) < ERA_ORDER.find(b["eraId"]))
	for e in db.eras:
		db.questions.append_array(e.get("questions", []))
	db.questions.sort_custom(func(a, b): return a["year"] < b["year"])
	# 因果は過去→未来のみ
	var ok: Array = []
	for r in db.rules:
		r["ifChoice"] = int(r["ifChoice"])
		r["thenChoice"] = int(r["thenChoice"])
		if db.by_id.has(r["ifQ"]) and db.by_id.has(r["thenQ"]) and db.by_id[r["ifQ"]]["year"] < db.by_id[r["thenQ"]]["year"]:
			ok.append(r)
	db.rules = ok
	db._load_actors(dir.path_join("actors"))
	return db


## data/actors/<era>.json を読む。問題に関わる人物（ミッションの npc に出る人物、actor.q）も集計する。
func _load_actors(adir: String) -> void:
	if not DirAccess.dir_exists_absolute(adir):
		return
	var files := DirAccess.get_files_at(adir)
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(adir.path_join(f)))
		if typeof(d) != TYPE_DICTIONARY:
			errors.append("actors/%s: JSON を読めません" % f)
			continue
		for a in d.get("actors", []):
			if not a.has("era"):
				a["era"] = d.get("eraId", "")
			actors[a["name"]] = a
			for al in a.get("aka", []):
				actor_alias[al] = a["name"]
		for b in d.get("battles", []):
			if not b.has("era"):
				b["era"] = d.get("eraId", "")
			battles.append(b)
	for q in questions:
		var lst: Array = []
		var seen := {}
		for m in q.get("missions", []):
			for st in m.get("steps", []):
				var an := actor_name(str(st.get("npc", "")))
				if an != "" and not seen.has(an):
					seen[an] = true
					lst.append({"name": an, "at": str(st.get("at", actors[an].get("spawn", "capital")))})
		q_actors[q["id"]] = lst
	for an in actors:
		for qid in actors[an].get("q", []):
			if q_actors.has(qid) and not q_actors[qid].any(func(x): return x["name"] == an):
				q_actors[qid].append({"name": an, "at": str(actors[an].get("spawn", "capital"))})


## 表記ゆれ（「老中 田沼意次」「羽柴秀吉」「厩戸王（聖徳太子）」）→ 人物名。知らなければ ""
func actor_name(n: String) -> String:
	if n == "":
		return ""
	if actors.has(n):
		return n
	if actor_alias.has(n):
		return actor_alias[n]
	var lp := n.find("（")
	if lp > 0:
		var head := n.substr(0, lp)
		if actors.has(head) or actor_alias.has(head):
			return actor_name(head)
	for k in actors:
		if k.length() >= 2 and (n.ends_with(" " + k) or n.ends_with("　" + k)):
			return k
	return ""


func actor(n: String) -> Dictionary:
	var k := actor_name(n)
	return actors[k] if k != "" else {}


## 年 → その年を含む時代（問題の年で判定。最初の問題より前は最初の時代）
func era_of_year(y: int) -> String:
	var best := ERA_ORDER[0]
	for e in eras:
		var ys: Array = e.get("questions", []).map(func(q): return int(q["year"]))
		if ys.is_empty():
			continue
		if y >= ys.min() or e["eraId"] == ERA_ORDER[0]:
			if ERA_ORDER.find(e["eraId"]) >= ERA_ORDER.find(best):
				best = e["eraId"]
	return best


func get_era(id: String) -> Dictionary:
	for e in eras:
		if e["eraId"] == id:
			return e
	return {}


static func landmark_name(era: Dictionary, key: String) -> String:
	for l in era.get("landmarks", []):
		if l["key"] == key:
			return l["name"]
	return key


## (問題, 選択肢) に対応する手段（ミッション）の一覧。無ければ自動生成の1件。
func missions_for(q: Dictionary, choice: int) -> Array:
	var out: Array = []
	for m in q.get("missions", []):
		if m["choice"] == choice:
			out.append(m)
	if out.is_empty():
		out.append(mission_for(q, choice))
	return out


## (問題, 目標の選択肢, 手段番号) のミッション。史実へ戻す場合などデータに無いものは自動生成する。
func mission_for(q: Dictionary, choice: int, method := 0) -> Dictionary:
	var found: Array = []
	for m in q.get("missions", []):
		if m["choice"] == choice:
			found.append(m)
	if not found.is_empty():
		return found[clampi(method, 0, found.size() - 1)]
	var restore: bool = choice == q["real"]
	var era: Dictionary = q["era"]
	var h: int = abs(hash(str(q["id"]) + str(choice)))
	var a: String = LANDMARK_KEYS[h % 7]
	var b: String = LANDMARK_KEYS[(h / 7 + 3) % 7]
	if a == b:
		b = LANDMARK_KEYS[(h + 1) % 7]
	var picked: String = q["choices"][choice]
	return {
		"choice": choice,
		"title": ("史実修復：%s" if restore else "時空改変：%s") % q["topic"],
		"briefing": "連鎖改変の余波で、この出来事が史実から外れてしまった。歪みを正し、本来の歴史を取り戻せ。" if restore else "「%s」が史実となるよう、歴史の分岐点に介入せよ。" % picked,
		"aftermath": "歴史は本来の流れに戻った。" if restore else "歴史は静かに別の道を歩み始めた。",
		"legacy": "" if restore else "%sに「%s」という史実が刻まれ、現代の教科書もそのように書かれている。" % [era["eraName"], picked],
		"generated": true,
		"method": "修復" if restore else "介入",
		"method_index": 0,
		"effects": {},
		"steps": [
			{"type": "goto", "at": a, "text": "%sに生じた時空の歪みへ向かう" % landmark_name(era, a)},
			{"type": "defeat", "at": a, "count": 4 + h % 3, "enemy": "歴史の修正力", "text": "歪みを守る「歴史の修正力」を撃退せよ"},
			{"type": "talk", "at": b, "npc": "時の記録者", "text": "%sで時の記録者に会う" % landmark_name(era, b),
			 "lines": ["歴史が本来の姿を取り戻そうとしている……。" if restore else "この歴史を書き換えるつもりか。",
					   ("記録しておこう。" + q["explanation"]) if restore else "よかろう。「%s」――それがこの世界の史実だ。" % picked]},
		],
	}

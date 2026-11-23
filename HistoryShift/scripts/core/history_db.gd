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
		db.eras.append(d)
		db.rules.append_array(d.get("rules", []))
		for q in d.get("questions", []):
			q["era"] = d
			q["year"] = int(q["year"])
			q["real"] = int(q["real"])
			for m in q.get("missions", []):
				m["choice"] = int(m["choice"])
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
	return db


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


## (問題, 目標の選択肢) のミッション。史実へ戻す場合などデータに無いものは自動生成する。
func mission_for(q: Dictionary, choice: int) -> Dictionary:
	for m in q.get("missions", []):
		if m["choice"] == choice:
			return m
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
		"steps": [
			{"type": "goto", "at": a, "text": "%sに生じた時空の歪みへ向かう" % landmark_name(era, a)},
			{"type": "defeat", "at": a, "count": 4 + h % 3, "enemy": "歴史の修正力", "text": "歪みを守る「歴史の修正力」を撃退せよ"},
			{"type": "talk", "at": b, "npc": "時の記録者", "text": "%sで時の記録者に会う" % landmark_name(era, b),
			 "lines": ["歴史が本来の姿を取り戻そうとしている……。" if restore else "この歴史を書き換えるつもりか。",
					   ("記録しておこう。" + q["explanation"]) if restore else "よかろう。「%s」――それがこの世界の史実だ。" % picked]},
		],
	}

class_name HistoryState
extends RefCounted
## 世界の歴史状態（各問題でどの選択肢が「史実」か）と受験者の確定解答を持つ因果エンジン。
## 状態空間は 4^問題数。ルールは過去→未来にのみ波及するため、古い時代から順に改変すれば必ず満点に到達できる。

const SAVE_PATH := "user://save_v1.json"

var db: HistoryDB
var world: Dictionary = {}      # qid -> 史実の選択肢
var answers: Dictionary = {}    # qid -> 確定解答 (-1 = 未解答)
var exam_submitted := false
var alterations := 0
var restorations := 0
var history_log: Array = []           # Array[String]


func _init(p_db: HistoryDB) -> void:
	db = p_db
	reset_all()


func reset_all() -> void:
	world.clear(); answers.clear(); history_log.clear()
	for q in db.questions:
		world[q["id"]] = q["real"]
		answers[q["id"]] = -1
	exam_submitted = false
	alterations = 0
	restorations = 0


func world_choice(q: Dictionary) -> int: return world.get(q["id"], q["real"])
func answer(q: Dictionary) -> int: return answers.get(q["id"], -1)
func set_answer(q: Dictionary, c: int) -> void:
	if not exam_submitted:
		answers[q["id"]] = c
func is_correct(q: Dictionary) -> bool: return answer(q) >= 0 and answer(q) == world_choice(q)
func is_altered(q: Dictionary) -> bool: return world_choice(q) != q["real"]


func correct_count() -> int:
	var n := 0
	for q in db.questions:
		if is_correct(q):
			n += 1
	return n


func score() -> int:
	return 0 if db.questions.is_empty() else roundi(100.0 * correct_count() / db.questions.size())


func perfect() -> bool:
	return not db.questions.is_empty() and correct_count() == db.questions.size()


## 改変を適用し、ルールに従って未来へ連鎖させる。起きた変化（depth 0 = 直接改変）を返す。
func apply_change(q: Dictionary, choice: int, cause: String) -> Array:
	var changes: Array = []
	var fired := {}
	var queue: Array = [[q, choice, cause, 0]]
	var guard := 0
	while not queue.is_empty() and guard < 1000:
		guard += 1
		var item: Array = queue.pop_front()
		var cq: Dictionary = item[0]
		var cc: int = item[1]
		var depth: int = item[3]
		var from := world_choice(cq)
		if from == cc and depth > 0:
			continue
		world[cq["id"]] = cc
		changes.append({"question": cq, "from": from, "to": cc, "cause": item[2], "depth": depth})
		for i in db.rules.size():
			var r: Dictionary = db.rules[i]
			if r["ifQ"] != cq["id"] or r["ifChoice"] != cc or fired.has(i):
				continue
			fired[i] = true
			if db.by_id.has(r["thenQ"]):
				queue.append([db.by_id[r["thenQ"]], r["thenChoice"], r["note"], depth + 1])
	if choice == q["real"]:
		restorations += 1
	else:
		alterations += 1
	for c in changes:
		var cq: Dictionary = c["question"]
		history_log.append("%d年 %s：%s → %s%s" % [cq["year"], cq["topic"], cq["choices"][c["from"]], cq["choices"][c["to"]],
			("（連鎖：%s）" % c["cause"]) if c["depth"] > 0 else ("（%s）" % c["cause"])])
	save()
	return changes


## 改変した場合に連鎖で影響を受けうる問題（ミッション前の予測表示用）。
func predict_ripple(q: Dictionary, choice: int) -> Array:
	var result: Array = []
	var seen := {q["id"]: true}
	var frontier: Array = [[q["id"], choice]]
	while not frontier.is_empty():
		var nxt: Array = []
		for f in frontier:
			for r in db.rules:
				if r["ifQ"] == f[0] and r["ifChoice"] == f[1] and not seen.has(r["thenQ"]):
					seen[r["thenQ"]] = true
					result.append({"question": db.by_id[r["thenQ"]], "to": r["thenChoice"], "note": r["note"]})
					nxt.append([r["thenQ"], r["thenChoice"]])
		frontier = nxt
	return result


## 改変の組み合わせから「この世界の令和日本」を合成する（全パターン自動生成）。[タイトル, 本文]
func compose_ending() -> Array:
	var altered: Array = db.questions.filter(func(q): return is_altered(q))
	var n := altered.size()
	var total := db.questions.size()
	var ratio := 0.0 if total == 0 else float(n) / total
	var title := "完全なる史実エンド"
	if n > 0:
		title = "ちょっとだけ違う日本エンド" if ratio < 0.15 else ("パラレル日本エンド" if ratio < 0.4 else ("大改変日本エンド" if ratio < 0.7 else "もはや別の国エンド"))
	var lines: PackedStringArray = []
	lines.append("2026年、令和の日本。あなたが書き換えた史実は%d件（全%d問中）。" % [n, total])
	lines.append("")
	if n == 0:
		lines.append("あなたは一度も歴史を曲げることなく満点を取った。教科書は何ひとつ変わらず、時空管理局はあなたを「最も誠実な受験生」として記録した。")
		return [title, "\n".join(lines)]
	var last_era := ""
	var eras_touched := {}
	for q in altered:
		var m := db.mission_for(q, world_choice(q))
		var en: String = q["era"]["eraName"]
		eras_touched[en] = true
		if en != last_era:
			lines.append("■ " + en)
			last_era = en
		var legacy: String = m.get("legacy", "")
		if legacy == "":
			legacy = "「%s」が史実となった。" % q["choices"][world_choice(q)]
		lines.append("・%d年 %s：%s" % [q["year"], q["topic"], legacy])
	lines.append("")
	var k := eras_touched.size()
	if k >= 6:
		lines.append("時代をまたいで積み重なった改変は互いに響き合い、この国の言葉・制度・街並みは、あなたの知る日本とはまるで違うものになった。それでも共通テストの日本史は、今年も満点だった。")
	elif k >= 3:
		lines.append("いくつもの時代に刻まれた改変が重なり、教科書の年表は見覚えのない出来事で埋まっている。それでも答案用紙には、満点の赤い丸が並んでいた。")
	else:
		lines.append("大筋はあなたの知る日本のまま。だが細部の違いに気づく人は少なくない。答案は満点――ただし、それを知っているのはあなただけだ。")
	return [title, "\n".join(lines)]


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"world": world, "answers": answers, "exam_submitted": exam_submitted,
		"alterations": alterations, "restorations": restorations, "log": history_log}))


func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	reset_all()
	for k in d.get("world", {}):
		if db.by_id.has(k):
			world[k] = int(d["world"][k])
	for k in d.get("answers", {}):
		if db.by_id.has(k):
			answers[k] = int(d["answers"][k])
	exam_submitted = d.get("exam_submitted", false)
	alterations = int(d.get("alterations", 0))
	restorations = int(d.get("restorations", 0))
	history_log = d.get("log", [])
	return true


static func has_save() -> bool: return FileAccess.file_exists(SAVE_PATH)
static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

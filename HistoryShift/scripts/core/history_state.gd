class_name HistoryState
extends RefCounted
## 歴史シミュレーション v2（tools/SCHEMA_V2.md）。
## 世界の歴史は「プレイヤーの介入の一覧」から毎回すべて再計算する。
##  - 歴史パラメータ（中央集権・武士・朝廷・宗教・商業・対外交流・技術・教育・民衆・軍事・民主化・経済・統一
##    ＋ 首都・支配勢力・学問の中心）を古い時代から順に積み上げる。
##  - 介入していない問題の「史実」は、その年の時点のパラメータ（resolve）と旧来の連鎖ルールで決まる。
##  - 因果は過去→未来にのみ流れるので、古い時代から順に直せば必ず満点に到達できる。
## 状態空間は「4択×手段」の組み合わせ×パラメータの連続値で、事実上無限。

const SAVE_PATH := "user://save_v2.json"
const NUM := ["centralization", "warrior", "court", "religion", "commerce", "open_asia", "open_west", "tech",
	"education", "commoners", "militarism", "democracy", "economy", "unity"]
const CAT := ["capital", "ruler", "edu_center"]
const LABELS := {
	"centralization": "中央集権", "warrior": "武士の力", "court": "朝廷・貴族", "religion": "宗教勢力", "commerce": "商業・都市",
	"open_asia": "大陸との交流", "open_west": "西洋との交流", "tech": "技術力", "education": "教育・学問", "commoners": "民衆の力",
	"militarism": "軍事優先", "democracy": "民主化", "economy": "経済力", "unity": "国内の安定",
	"capital": "首都", "ruler": "実権", "edu_center": "学問の中心",
}

var db: HistoryDB
var interventions: Dictionary = {}   # qid -> {"choice": int, "method": int}
var answers: Dictionary = {}         # qid -> 確定解答 (-1 = 未解答)
var exam_submitted := false
var alterations := 0
var restorations := 0
var history_log: Array = []

# 再計算結果
var world: Dictionary = {}           # qid -> 史実の選択肢
var reasons: Dictionary = {}         # qid -> その史実になった理由（resolve の note など）
var era_states: Dictionary = {}      # eraId -> その時代の終わりの状態
var final_state: Dictionary = {}


func _init(p_db: HistoryDB) -> void:
	db = p_db
	reset_all()


func reset_all() -> void:
	interventions.clear(); answers.clear(); history_log.clear()
	for q in db.questions:
		answers[q["id"]] = -1
	exam_submitted = false
	alterations = 0
	restorations = 0
	recompute()


# ---------- シミュレーション ----------
static func base_state() -> Dictionary:
	var st := {}
	for k in NUM:
		st[k] = 0.0
	for k in CAT:
		st[k] = ""
	return st


static func cond_match(c: Dictionary, st: Dictionary) -> bool:
	for k in c:
		var v := str(c[k])
		if k in NUM:
			var op := ">=" if v.begins_with(">=") else ("<=" if v.begins_with("<=") else (">" if v.begins_with(">") else "<"))
			var n := float(v.substr(op.length()))
			var x: float = st.get(k, 0.0)
			var ok := false
			match op:
				">=": ok = x >= n
				"<=": ok = x <= n
				">": ok = x > n
				"<": ok = x < n
			if not ok:
				return false
		else:
			var cur: String = st.get(k, "")
			if v.begins_with("=="):
				if cur != v.substr(2):
					return false
			elif v.begins_with("!="):
				if cur == v.substr(2):
					return false
	return true


static func apply_effects(st: Dictionary, e: Dictionary) -> void:
	for k in e:
		if k == "set":
			for ck in e["set"]:
				st[ck] = str(e["set"][ck])
		elif k in NUM:
			st[k] = clampf(float(st[k]) + float(e[k]), -100.0, 100.0)


## 介入一覧から歴史全体を計算する（純粋関数）。
func simulate(ivs: Dictionary) -> Dictionary:
	var st := base_state()
	var w := {}
	var why := {}
	var eras := {}
	var last_era := ""
	for q in db.questions:
		var era_id: String = q["era"]["eraId"]
		if last_era != "" and era_id != last_era:
			eras[last_era] = st.duplicate()
		last_era = era_id
		var qid: String = q["id"]
		var fact: int = q["real"]
		var method := -1
		if ivs.has(qid):
			fact = ivs[qid]["choice"]
			method = ivs[qid].get("method", 0)
			why[qid] = "あなたの介入"
		else:
			var done := false
			# 旧来の連鎖ルール（ある出来事が起きたら、後の出来事がこうなる）
			for r in db.rules:
				if r["thenQ"] == qid and w.get(r["ifQ"], -1) == r["ifChoice"]:
					fact = r["thenChoice"]; why[qid] = r["note"]; done = true
					break
			# 歴史パラメータによる解決
			if not done:
				for r in q.get("resolve", []):
					if cond_match(r.get("if", {}), st):
						fact = int(r["choice"]); why[qid] = r.get("note", "歴史の流れが変わった"); done = true
						break
		w[qid] = fact
		var eff: Array = q.get("effects", [])
		if fact < eff.size():
			apply_effects(st, eff[fact])
		if method >= 0 and fact != q["real"]:
			var m := db.mission_for(q, fact, method)
			apply_effects(st, m.get("effects", {}))
	if last_era != "":
		eras[last_era] = st.duplicate()
	return {"world": w, "reasons": why, "eras": eras, "final": st}


func recompute() -> void:
	var r := simulate(interventions)
	world = r["world"]
	reasons = r["reasons"]
	era_states = r["eras"]
	final_state = r["final"]


# ---------- 参照 ----------
func world_choice(q: Dictionary) -> int: return world.get(q["id"], q["real"])
func answer(q: Dictionary) -> int: return answers.get(q["id"], -1)
func set_answer(q: Dictionary, c: int) -> void:
	if not exam_submitted:
		answers[q["id"]] = c
func is_correct(q: Dictionary) -> bool: return answer(q) >= 0 and answer(q) == world_choice(q)
func is_altered(q: Dictionary) -> bool: return world_choice(q) != q["real"]
func is_intervened(q: Dictionary) -> bool: return interventions.has(q["id"])
func reason(q: Dictionary) -> String: return reasons.get(q["id"], "")


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


## 現在の世界のパラメータ（史実との差）。UI 表示用。
func param_lines(st: Dictionary = {}) -> Array:
	var s := st if not st.is_empty() else final_state
	var out: Array = []
	for k in NUM:
		var v: float = s.get(k, 0.0)
		if absf(v) >= 5.0:
			out.append({"key": k, "label": LABELS[k], "value": v})
	for k in CAT:
		if str(s.get(k, "")) != "":
			out.append({"key": k, "label": LABELS[k], "value": s[k]})
	return out


# ---------- 改変 ----------
## 改変を適用し、歴史全体を再計算する。起きた変化（depth 0 = 直接改変、1 = 波及）を返す。
func apply_change(q: Dictionary, choice: int, cause: String, method := 0) -> Array:
	var old := world.duplicate()
	interventions[q["id"]] = {"choice": choice, "method": method}
	recompute()
	var changes: Array = []
	for cq in db.questions:
		var id: String = cq["id"]
		var was: int = old.get(id, cq["real"])
		var now: int = world.get(id, cq["real"])
		if id == q["id"]:
			changes.push_front({"question": cq, "from": was, "to": now, "cause": cause, "depth": 0})
		elif was != now:
			changes.append({"question": cq, "from": was, "to": now, "cause": reasons.get(id, "歴史の流れが元に戻った") if now != cq["real"] else "歴史の流れが元に戻った", "depth": 1})
	if choice == q["real"]:
		restorations += 1
	else:
		alterations += 1
	for c in changes:
		var cq2: Dictionary = c["question"]
		history_log.append("%d年 %s：%s → %s%s" % [cq2["year"], cq2["topic"], cq2["choices"][c["from"]], cq2["choices"][c["to"]],
			("（波及：%s）" % c["cause"]) if c["depth"] > 0 else ("（%s）" % c["cause"])])
	save()
	return changes


## 改変した場合に変わる後の問題を正確に予測（ミッション前のプレビュー用）。
func predict_ripple(q: Dictionary, choice: int, method := 0) -> Array:
	var ivs := interventions.duplicate(true)
	ivs[q["id"]] = {"choice": choice, "method": method}
	var r := simulate(ivs)
	var out: Array = []
	for cq in db.questions:
		var id: String = cq["id"]
		if id == q["id"]:
			continue
		if r["world"].get(id, cq["real"]) != world.get(id, cq["real"]):
			out.append({"question": cq, "to": r["world"][id], "note": r["reasons"].get(id, "歴史の流れが元に戻った")})
	return out


# ---------- その後の歴史・エンディング ----------
## 時代ごとの「その後の歴史」。[{era, lines:[...], changed:bool}]
func era_timeline() -> Array:
	var out: Array = []
	for e in db.eras:
		var st: Dictionary = era_states.get(e["eraId"], base_state())
		var lines: Array = []
		for r in e.get("aftermath_rules", []):
			if cond_match(r.get("if", {}), st):
				lines.append(r["text"])
				if lines.size() >= 4:
					break
		var changed := not lines.is_empty()
		if lines.is_empty() and e.get("baseline_text", "") != "":
			lines.append(e["baseline_text"])
		out.append({"era": e, "lines": lines, "changed": changed})
	return out


## 令和の日本（topic -> 文章）
func modern_japan() -> Dictionary:
	var out := {}
	var base: Dictionary = db.modern.get("baseline", {})
	for r in db.modern.get("ending_rules", []):
		var t: String = r.get("topic", "")
		if t == "" or out.has(t):
			continue
		if cond_match(r.get("if", {}), final_state):
			out[t] = r["text"]
	for t in base:
		if not out.has(t):
			out[t] = base[t]
	return out


## 改変の組み合わせから「この世界の歴史と令和日本」を合成する（全パターン自動生成）。[タイトル, 本文]
func compose_ending() -> Array:
	var altered: Array = db.questions.filter(func(q): return is_altered(q))
	var n := altered.size()
	var total := db.questions.size()
	var ratio := 0.0 if total == 0 else float(n) / total
	var title := "完全なる史実エンド"
	if n > 0:
		title = "ちょっとだけ違う日本エンド" if ratio < 0.15 else ("パラレル日本エンド" if ratio < 0.4 else ("大改変日本エンド" if ratio < 0.7 else "もはや別の国エンド"))
	var lines: PackedStringArray = []
	lines.append("2026年、令和の日本。書き換わった史実は%d件（全%d問中）、あなたが直接介入したのは%d回。" % [n, total, interventions.size()])
	lines.append("")
	if n == 0:
		lines.append("あなたは一度も歴史を曲げることなく満点を取った。教科書は何ひとつ変わらず、時空管理局はあなたを「最も誠実な受験生」として記録した。")
	else:
		lines.append("―― この世界の歴史 ――")
		for item in era_timeline():
			var e: Dictionary = item["era"]
			var alt_here: Array = altered.filter(func(q): return q["era"]["eraId"] == e["eraId"])
			if alt_here.is_empty() and not item["changed"]:
				continue
			lines.append("■ " + e["eraName"])
			for q in alt_here:
				var how := "あなたの介入" if is_intervened(q) else "歴史の波及"
				var m := db.mission_for(q, world_choice(q), interventions.get(q["id"], {}).get("method", 0))
				var legacy: String = m.get("legacy", "")
				lines.append("・%d年 %s：「%s」（%s）%s" % [q["year"], q["topic"], q["choices"][world_choice(q)], how, ("\n　" + legacy) if legacy != "" and is_intervened(q) else ""])
			for t in item["lines"]:
				lines.append("　" + t)
	var mj := modern_japan()
	if not mj.is_empty():
		lines.append("")
		lines.append("―― 令和の日本 ――")
		for t in mj:
			lines.append("【%s】%s" % [t, mj[t]])
	var ps := param_lines()
	if not ps.is_empty():
		var parts: PackedStringArray = []
		for p in ps:
			parts.append("%s %s" % [p["label"], ("%+d" % int(p["value"])) if p["value"] is float else str(p["value"])])
		lines.append("")
		lines.append("（史実との差：" + "、".join(parts) + "）")
	lines.append("")
	lines.append("それでも共通テストの日本史は、満点だった。")
	return [title, "\n".join(lines)]


# ---------- セーブ ----------
func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"interventions": interventions, "answers": answers, "exam_submitted": exam_submitted,
		"alterations": alterations, "restorations": restorations, "log": history_log}))


func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	reset_all()
	var ivs: Dictionary = d.get("interventions", {})
	for k in ivs:
		if db.by_id.has(k):
			interventions[k] = {"choice": int(ivs[k]["choice"]), "method": int(ivs[k].get("method", 0))}
	for k in d.get("answers", {}):
		if db.by_id.has(k):
			answers[k] = int(d["answers"][k])
	exam_submitted = d.get("exam_submitted", false)
	alterations = int(d.get("alterations", 0))
	restorations = int(d.get("restorations", 0))
	history_log = d.get("log", [])
	recompute()
	return true


static func has_save() -> bool: return FileAccess.file_exists(SAVE_PATH)
static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

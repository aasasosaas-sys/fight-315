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
static var save_path := SAVE_PATH   # テストは別のファイルに差し替える（並行して走る他のテストとぶつからないように）
const NUM := ["centralization", "warrior", "court", "religion", "commerce", "open_asia", "open_west", "tech",
	"education", "commoners", "militarism", "democracy", "economy", "unity"]
const CAT := ["capital", "ruler", "edu_center", "war", "standing"]
const LABELS := {
	"centralization": "中央集権", "warrior": "武士の力", "court": "朝廷・貴族", "religion": "宗教勢力", "commerce": "商業・都市",
	"open_asia": "大陸との交流", "open_west": "西洋との交流", "tech": "技術力", "education": "教育・学問", "commoners": "民衆の力",
	"militarism": "軍事優先", "democracy": "民主化", "economy": "経済力", "unity": "国内の安定",
	"capital": "首都", "ruler": "実権", "edu_center": "学問の中心", "war": "太平洋戦争", "standing": "国際的地位",
}

var db: HistoryDB
var interventions: Dictionary = {}   # qid -> {"choice": int, "method": int}（自由探索の混乱は method -1, "cause": "chaos", "rule", "note"）
var chaos_mods: Array = []           # 自由探索の混乱による歴史パラメータの変化 [{rule, era, year, effects, title}]
var chaos_count := 0                 # 自由探索で歴史が揺らいだ回数
var actions: Array = []              # 自由な行動の記録 [{verb, target, era, seq, ...}]（HistoryActors.resolve で毎回解決）
var seq := 0                         # 介入・混乱・行動の通し番号（後のものが前のものを上書きする）
var _layer: Dictionary = {"forces": {}, "mods": [], "notes": {}}
var effective: Dictionary = {}       # 実際に効いている介入（ミッション・混乱・行動を通し番号でまとめたもの）
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
var chaos_touched: Dictionary = {}   # qid -> true（混乱がなければ史実が違っていた問題）
var war: Dictionary = {}             # 太平洋戦争の帰趨（WarModel.evaluate の結果：tier・pillars・score…）
var standing: Dictionary = {}        # 国際的地位の推移（WarModel.standing の結果：points[{year, score, tier, base…}]）


func _init(p_db: HistoryDB) -> void:
	db = p_db
	reset_all()


func reset_all() -> void:
	interventions.clear(); answers.clear(); history_log.clear(); chaos_mods.clear(); actions.clear()
	seq = 0
	for q in db.questions:
		answers[q["id"]] = -1
	exam_submitted = false
	alterations = 0
	restorations = 0
	chaos_count = 0
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


static func _mod_era(m: Dictionary) -> int:
	return HistoryDB.ERA_ORDER.find(str(m.get("era", "")))


## 介入一覧（と自由探索の混乱）から歴史全体を計算する（純粋関数）。mods を省略すると chaos_mods を使う。
## 混乱によるパラメータ変化は「前の時代のもの → 時代の区切り → 同じ時代で year <= 問題の年のもの」の順に積む。
func simulate(p_ivs: Dictionary, mods: Variant = null) -> Dictionary:
	var ivs := p_ivs if mods != null else _merge_layer(p_ivs)
	var st := base_state()
	var w := {}
	var why := {}
	var eras := {}
	var last_era := ""
	var pend: Array = (chaos_mods + _layer["mods"]) if mods == null else (mods as Array).duplicate()
	pend.sort_custom(func(a, b): return _mod_era(a) < _mod_era(b) or (_mod_era(a) == _mod_era(b) and int(a["year"]) < int(b["year"])))
	var mi := 0
	for q in db.questions:
		var era_id: String = q["era"]["eraId"]
		var qe := HistoryDB.ERA_ORDER.find(era_id)
		while mi < pend.size() and _mod_era(pend[mi]) < qe:
			apply_effects(st, pend[mi]["effects"]); mi += 1
		if last_era != "" and era_id != last_era:
			eras[last_era] = st.duplicate()
		last_era = era_id
		while mi < pend.size() and _mod_era(pend[mi]) == qe and int(pend[mi]["year"]) <= int(q["year"]):
			apply_effects(st, pend[mi]["effects"]); mi += 1
		var qid: String = q["id"]
		var fact: int = q["real"]
		var method := -1
		if ivs.has(qid):
			fact = ivs[qid]["choice"]
			method = ivs[qid].get("method", 0)
			var cz := str(ivs[qid].get("cause", ""))
			why[qid] = ("時空の混乱：" + str(ivs[qid].get("note", "自由探索での大暴れ"))) if cz == "chaos" else (("あなたの行動：" + str(ivs[qid].get("note", ""))) if cz == "actor" else "あなたの介入")
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
	while mi < pend.size():
		apply_effects(st, pend[mi]["effects"]); mi += 1
	if last_era != "":
		eras[last_era] = st.duplicate()
	return {"world": w, "reasons": why, "eras": eras, "final": st}


## 自由な行動の層（強制される史実）を、通し番号の新しいほうが勝つように介入へ重ねる
func _merge_layer(ivs: Dictionary) -> Dictionary:
	var forces: Dictionary = _layer["forces"]
	if forces.is_empty():
		return ivs
	var eff := ivs.duplicate()
	for qid in forces:
		var f: Dictionary = forces[qid]
		if not eff.has(qid) or int(eff[qid].get("seq", 0)) < int(f["seq"]):
			eff[qid] = {"choice": int(f["choice"]), "method": -1, "cause": "actor", "note": f["note"], "seq": int(f["seq"])}
	return eff


## 二段階の計算：まず戦前までの歴史を出して1941年の国力（WarModel）を評価し、その帰趨を1941年の変化として重ねて計算し直す
func _simulate_war(ivs: Dictionary, mods: Variant, acts: Array) -> Dictionary:
	var r1 := simulate(ivs, mods)
	var sd := WarModel.standing(db, r1["eras"], r1["world"], acts)
	var w := WarModel.evaluate(db, r1["eras"], r1["world"], acts, sd)
	var wm: Dictionary = w.get("mods", {})
	var extra: Array = (sd.get("mods", []) as Array).duplicate()
	if not wm.is_empty():
		extra.append({"rule": "war", "era": "showa", "year": int(db.war_model.get("war_year", 1941)), "effects": wm, "title": "太平洋戦争：" + str(w["tier"])})
	if extra.is_empty():
		r1["war"] = w
		r1["standing"] = sd
		return r1
	var base: Array = (chaos_mods + _layer["mods"]) if mods == null else (mods as Array)
	var ivs2 := ivs if mods != null else _merge_layer(ivs)
	var r2 := simulate(ivs2, base + extra)
	r2["war"] = w
	r2["standing"] = sd
	return r2


func war_tier() -> String:
	return str(war.get("tier", ""))


func next_seq() -> int:
	seq += 1
	return seq


func recompute() -> void:
	_layer = HistoryActors.resolve(db, actions) if not actions.is_empty() else {"forces": {}, "mods": [], "notes": {}}
	effective = _merge_layer(interventions)
	var r := _simulate_war(interventions, null, actions)
	war = r["war"]
	standing = r.get("standing", {})
	world = r["world"]
	reasons = r["reasons"]
	era_states = r["eras"]
	final_state = r["final"]
	# 混乱がなかった場合の世界と比べ、混乱で史実が変わった問題を記録する
	chaos_touched.clear()
	if has_chaos():
		var calm := {}
		for k in interventions:
			if not (str(interventions[k].get("cause", "")) in ["chaos", "actor"]):
				calm[k] = interventions[k]
		var r0 := _simulate_war(calm, [], [])
		for q in db.questions:
			if r0["world"].get(q["id"], q["real"]) != world.get(q["id"], q["real"]):
				chaos_touched[q["id"]] = true


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
## 自由探索の混乱で直接書き換わった問題か
func is_chaos(q: Dictionary) -> bool: return str(effective.get(q["id"], {}).get("cause", "")) in ["chaos", "actor"]
## 混乱がなければ史実が違っていた問題か（直接・波及の両方）
func is_chaos_touched(q: Dictionary) -> bool: return chaos_touched.has(q["id"])
func has_chaos() -> bool:
	if not chaos_mods.is_empty() or not actions.is_empty():
		return true
	for k in interventions:
		if interventions[k].get("cause", "") == "chaos":
			return true
	return false
## 混乱のせいで不正解になっている問題
func chaos_broken() -> Array:
	return db.questions.filter(func(q): return is_chaos_touched(q) and answer(q) >= 0 and not is_correct(q))


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
	interventions[q["id"]] = {"choice": choice, "method": method, "seq": next_seq()}
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


## 自由探索の混乱ルール（data/chaos/<era>.json の1件）を適用し、歴史全体を再計算する。
## force: 問題の史実を強制（介入 cause "chaos"。のちのミッションで上書き＝修復できる）
## vars:  歴史パラメータを year の時点で変化させる（同じルールは1回だけ）
## 戻り値は apply_change と同じ形の変化一覧（depth 0 = 混乱が直接書き換えた問題、1 = 波及）。
func apply_chaos(rule: Dictionary, era_id: String) -> Array:
	var old := world.duplicate()
	var rid := str(rule.get("id", ""))
	var title := str(rule.get("title", "時空の混乱"))
	var forced: Array = []
	var fs: Variant = rule.get("force", [])
	var flist: Array = fs if fs is Array else [fs]
	for f in flist:
		var qid := str(f.get("q", ""))
		if not db.by_id.has(qid):
			continue
		interventions[qid] = {"choice": int(f.get("choice", 0)), "method": -1, "cause": "chaos", "rule": rid, "note": title, "seq": next_seq()}
		forced.append(qid)
	if rule.has("vars"):
		var exists := false
		for m in chaos_mods:
			if m.get("rule", "") == rid:
				exists = true
		if not exists:
			chaos_mods.append({"rule": rid, "era": era_id, "year": int(rule.get("year", 0)), "effects": rule["vars"], "title": title})
	recompute()
	chaos_count += 1
	var changes: Array = []
	for cq in db.questions:
		var id: String = cq["id"]
		var was: int = old.get(id, cq["real"])
		var now: int = world.get(id, cq["real"])
		if was == now:
			continue
		var direct := id in forced
		var c := {"question": cq, "from": was, "to": now, "depth": 0 if direct else 1, "chaos": true,
			"cause": ("時空の混乱：" + title) if direct else (reasons.get(id, "歴史の流れが元に戻った") if now != cq["real"] else "歴史の流れが元に戻った")}
		if direct:
			changes.push_front(c)
		else:
			changes.append(c)
	history_log.append("【時空の混乱】%s" % title)
	for c in changes:
		var cq2: Dictionary = c["question"]
		history_log.append("%d年 %s：%s → %s（%s：%s）" % [cq2["year"], cq2["topic"], cq2["choices"][c["from"]], cq2["choices"][c["to"]],
			"時空の混乱" if c["depth"] == 0 else "混乱の波及", c["cause"]])
	save()
	return changes


## そのルールの結果がすでに今の歴史に入っているか（同じ混乱を二重にかけない）
func chaos_in_effect(rule: Dictionary) -> bool:
	var any := false
	if rule.has("vars"):
		var found := false
		for m in chaos_mods:
			if m.get("rule", "") == rule.get("id", ""):
				found = true
		if not found:
			return false
		any = true
	var fs: Variant = rule.get("force", [])
	for f in (fs if fs is Array else [fs]):
		var iv: Dictionary = effective.get(str(f.get("q", "")), {})
		if iv.get("cause", "") != "chaos" or int(iv.get("choice", -1)) != int(f.get("choice", 0)):
			return false
		any = true
	return any


## 効果を出さない行動の記録（手作りルールが効果を受け持った行動。人物の状態の判定にだけ使う）
func record_action(action: Dictionary) -> void:
	var a := action.duplicate(true)
	a["seq"] = next_seq()
	actions.append(a)
	recompute()
	save()


## 自由な行動（HistoryActors の動詞）を記録して歴史全体を再計算する。戻り値は apply_chaos と同じ形の変化一覧
func apply_action(action: Dictionary) -> Array:
	var old := world.duplicate()
	var a := action.duplicate(true)
	a["seq"] = next_seq()
	actions.append(a)
	recompute()
	chaos_count += 1
	var title := HistoryActors.headline(db, a)
	var notes: Array = _layer["notes"].get(a["seq"], [])
	a["text"] = "。".join(notes.filter(func(n): return n != "")) if not notes.is_empty() else ""
	var changes: Array = []
	for cq in db.questions:
		var id: String = cq["id"]
		var was: int = old.get(id, cq["real"])
		var now: int = world.get(id, cq["real"])
		if was == now:
			continue
		var direct: bool = str(effective.get(id, {}).get("cause", "")) == "actor" and int(effective[id].get("seq", 0)) == int(a["seq"])
		var c := {"question": cq, "from": was, "to": now, "depth": 0 if direct else 1, "chaos": true,
			"cause": ("あなたの行動：" + title) if direct else (reasons.get(id, "歴史の流れが元に戻った") if now != cq["real"] else "歴史の流れが元に戻った")}
		if direct:
			changes.push_front(c)
		else:
			changes.append(c)
	a["changed"] = changes.map(func(c): return c["question"]["id"])
	actions[-1] = a
	history_log.append("【自由な行動】%s" % title)
	for c in changes:
		var cq2: Dictionary = c["question"]
		history_log.append("%d年 %s：%s → %s（%s：%s）" % [cq2["year"], cq2["topic"], cq2["choices"][c["from"]], cq2["choices"][c["to"]],
			"時空の混乱" if c["depth"] == 0 else "混乱の波及", c["cause"]])
	save()
	return changes


## 改変した場合に変わる後の問題を正確に予測（ミッション前のプレビュー用）。
func predict_ripple(q: Dictionary, choice: int, method := 0) -> Array:
	var ivs := interventions.duplicate(true)
	ivs[q["id"]] = {"choice": choice, "method": method, "seq": seq + 1}
	var r := _simulate_war(ivs, null, actions)
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
	var ws := _world_seed()
	for e in db.eras:
		var st: Dictionary = era_states.get(e["eraId"], base_state())
		var lines: Array = []
		for r in e.get("aftermath_rules", []):
			if cond_match(r.get("if", {}), st):
				lines.append(pick_variant(r["text"], ws, e["eraId"], {}))
				if lines.size() >= 4:
					break
		var changed := not lines.is_empty()
		if lines.is_empty() and e.get("baseline_text", "") != "":
			lines.append(e["baseline_text"])
		out.append({"era": e, "lines": lines, "changed": changed})
	return out


## 令和の日本（topic -> 文章）
## text は文字列か候補の配列（modern.json・aftermath_rules）。同じ世界なら同じ文、違う世界なら違う文を選ぶ。
func modern_japan() -> Dictionary:
	var out := {}
	var used := {}   # 書き出し3字 -> true（同じエンディングで同じ書き出しを繰り返さない）
	var ws := _world_seed()
	var base: Dictionary = db.modern.get("baseline", {})
	for r in db.modern.get("ending_rules", []):
		var t: String = r.get("topic", "")
		if t == "" or out.has(t):
			continue
		if cond_match(r.get("if", {}), final_state):
			out[t] = pick_variant(r["text"], ws, t, used)
	for t in base:
		if not out.has(t):
			out[t] = pick_variant(base[t], ws, t, used)
	return out


## 世界の状態（各問題の史実＋首都・実権など）から決まる種。文章の言い換えの選択に使う。
func _world_seed() -> int:
	var parts := PackedStringArray()
	for q in db.questions:
		parts.append(str(world_choice(q)))
	for k in CAT:
		parts.append(str(final_state.get(k, "")))
	return absi("".join(parts).hash())


## v が配列なら salt ごとに1つ選ぶ。used にある書き出しはできるだけ避け、選んだ書き出しを used に足す。
static func pick_variant(v: Variant, wseed: int, salt: String, used: Dictionary = {}) -> String:
	if not (v is Array):
		var s := str(v)
		used[s.substr(0, 3)] = true
		return s
	if v.is_empty():
		return ""
	var n: int = v.size()
	var start := absi(wseed + salt.hash()) % n
	var pick := str(v[start])
	for i in n:
		var c := str(v[(start + i) % n])
		if not used.has(c.substr(0, 3)):
			pick = c
			break
	used[pick.substr(0, 3)] = true
	return pick


## 同じ時代の「その後の歴史」を2文目からつなぐ言葉（同じ言葉が続かないよう順に回す）
const LINKS := ["さらに", "また", "そして"]
static func _linked(t: String, i: int, wseed: int, salt: String) -> String:
	if i == 0 or t == "" or "「『【（―".contains(t[0]) or t[0].is_valid_int():
		return t
	for w in ["さらに", "また", "そして", "一方", "しかし", "だが", "こうして", "その", "それ", "やがて", "のち", "結局"]:
		if t.begins_with(w):
			return t
	return LINKS[absi(wseed + salt.hash() + i) % LINKS.size()] + "、" + t


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
		var ws := _world_seed()
		var seen := {}   # 同じ断片を二度並べない
		for item in era_timeline():
			var e: Dictionary = item["era"]
			var alt_here: Array = altered.filter(func(q): return q["era"]["eraId"] == e["eraId"])
			if alt_here.is_empty() and not item["changed"]:
				continue
			lines.append("■ " + e["eraName"])
			for q in alt_here:
				var how := "自由探索での混乱" if is_chaos(q) else ("あなたの介入" if is_intervened(q) else "歴史の波及")
				var m := db.mission_for(q, world_choice(q), interventions.get(q["id"], {}).get("method", 0))
				var legacy: String = m.get("legacy", "")
				lines.append("・%d年 %s：「%s」（%s）%s" % [q["year"], q["topic"], q["choices"][world_choice(q)], how, ("\n　" + legacy) if legacy != "" and is_intervened(q) and not is_chaos(q) else ""])
			var li := 0
			for t in item["lines"]:
				if not seen.has(t):
					seen[t] = true
					lines.append("　" + (_linked(t, li, ws, e["eraId"]) if item["changed"] else t))
					li += 1
	var wt: Dictionary = war.get("tier_def", {})
	if not wt.is_empty():
		lines.append("")
		lines.append("―― 太平洋戦争：%s ――" % wt.get("name", wt.get("id", "")))
		lines.append(str(wt.get("summary", "")))
	var spts: Array = standing.get("points", [])
	if not spts.is_empty():
		var seq_t: PackedStringArray = []
		for sp in spts:
			seq_t.append("%d年 %s" % [sp["year"], sp["tier"]])
		lines.append("（日本の国際的地位：" + " → ".join(seq_t) + "）")
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
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"interventions": interventions, "answers": answers, "exam_submitted": exam_submitted,
		"alterations": alterations, "restorations": restorations, "log": history_log,
		"chaos_mods": chaos_mods, "chaos_count": chaos_count, "actions": actions, "seq": seq}))


func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	reset_all()
	var ivs: Dictionary = d.get("interventions", {})
	for k in ivs:
		if db.by_id.has(k):
			interventions[k] = {"choice": int(ivs[k]["choice"]), "method": int(ivs[k].get("method", 0)), "seq": int(ivs[k].get("seq", 0))}
			if ivs[k].get("cause", "") == "chaos":
				interventions[k]["cause"] = "chaos"
				interventions[k]["rule"] = str(ivs[k].get("rule", ""))
				interventions[k]["note"] = str(ivs[k].get("note", ""))
	for k in d.get("answers", {}):
		if db.by_id.has(k):
			answers[k] = int(d["answers"][k])
	exam_submitted = d.get("exam_submitted", false)
	alterations = int(d.get("alterations", 0))
	restorations = int(d.get("restorations", 0))
	history_log = d.get("log", [])
	for m in d.get("chaos_mods", []):
		if typeof(m) == TYPE_DICTIONARY and m.has("effects"):
			chaos_mods.append({"rule": str(m.get("rule", "")), "era": str(m.get("era", "")), "year": int(m.get("year", 0)),
				"effects": m["effects"], "title": str(m.get("title", ""))})
	chaos_count = int(d.get("chaos_count", 0))
	for a in d.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY:
			a["seq"] = int(a.get("seq", 0))
			if a.has("choice"):
				a["choice"] = int(a["choice"])
			actions.append(a)
	seq = int(d.get("seq", 0))
	recompute()
	return true


static func has_save() -> bool: return FileAccess.file_exists(save_path)
static func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

class_name WarModel
extends RefCounted
## 太平洋戦争の帰趨モデル（data/war/model.json ＋ data/projects/<era>.json）。
## 1941年の日本の国力を8本の柱（工業力・資源・科学技術・海軍航空・情報・経済・外交・文民統制）で表し、
## アメリカ（＋イギリス）を100として史実の値（統計にもとづく base）から積み上げる。
##  - 歴史パラメータの変化：時代ごとの変化量 × 重み × 複利（1941年までの年数、100年ごとに growth.base 倍、上限 cap）
##  - 国家事業（verb "project"）：柱の点数 × 複利（事業の年から）
##  - 設問の史実（facts）：例「国際連盟にとどまった」→ 外交 +15
## 柱から帰趨の段階（開戦回避／勝利／有利な休戦／早期講和／敗戦／本土決戦）を決め、その段階の歴史パラメータの変化（mods）を
## 1941年に重ねて昭和の設問・その後の歴史・令和のエンディングへ波及させる（HistoryState が二段階で計算する）。


static func growth(m: Dictionary, year: int) -> float:
	var g: Dictionary = m.get("growth", {})
	var wy := int(m.get("war_year", 1941))
	var k := pow(float(g.get("base", 1.5)), maxf(0.0, float(wy - year)) / 100.0)
	return minf(k, float(g.get("cap", 4.0)))


static func _era_end_year(db: HistoryDB, era_id: String) -> int:
	var e := db.get_era(era_id)
	var ys: Array = e.get("questions", []).map(func(q): return int(q["year"]))
	return 0 if ys.is_empty() else int(ys.max())


## 1941年の国力。eras = その世界の各時代の終わりの状態、world = 設問の史実、acts = 行動の記録
static func evaluate(db: HistoryDB, eras: Dictionary, world: Dictionary, acts: Array, stand: Dictionary = {}) -> Dictionary:
	var m: Dictionary = db.war_model
	if m.is_empty():
		return {"tier": "", "pillars": {}, "mods": {}}
	var wy := int(m.get("war_year", 1941))
	var cap := float(m.get("vars_cap", 25))
	var pillars := {}
	var parts := {}
	for pl in m.get("pillars", []):
		parts[pl["id"]] = {"base": float(pl["base"]), "vars": 0.0, "projects": 0.0, "facts": 0.0, "list": []}
	# 歴史パラメータの変化（戦前の時代まで。早い時代ほど複利が大きい）
	var prev := HistoryState.base_state()
	for eid in HistoryDB.ERA_ORDER:
		if not eras.has(eid):
			continue
		var ey := _era_end_year(db, eid)
		if ey >= wy:
			break
		var st: Dictionary = eras[eid]
		var k := growth(m, ey)
		for pl in m.get("pillars", []):
			var add := 0.0
			for v in pl.get("vars", {}):
				add += float(pl["vars"][v]) * (float(st.get(v, 0.0)) - float(prev.get(v, 0.0)))
			parts[pl["id"]]["vars"] += add * k
		prev = st
	for pid in parts:
		parts[pid]["vars"] = clampf(parts[pid]["vars"], -cap, cap)
	# 設問の史実
	for pl in m.get("pillars", []):
		var facts: Dictionary = pl.get("facts", {})
		for qid in facts:
			var c := str(world.get(qid, -1))
			if facts[qid].has(c):
				parts[pl["id"]]["facts"] += float(facts[qid][c])
	# 国家事業
	for a in acts:
		if str(a.get("verb", "")) != "project" or a.get("ruled", false):
			continue
		var pr: Dictionary = db.projects.get(str(a.get("target", "")), {})
		if pr.is_empty():
			continue
		var k2 := growth(m, int(pr.get("year", wy)))
		for pid in pr.get("pillars", {}):
			if parts.has(pid):
				var pts := float(pr["pillars"][pid]) * k2
				parts[pid]["projects"] += pts
				parts[pid]["list"].append([pr["name"], pts])
	# 1900年の国際的地位が史実より高ければ（低ければ）外交・工業・資源に響く
	for sp in stand.get("points", []):
		if int(sp["year"]) == 1900:
			var dd := (float(sp["score"]) - float(sp["base"])) * 0.2
			for pid in ["diplomacy", "industry", "resources"]:
				if parts.has(pid) and absf(dd) >= 0.5:
					parts[pid]["projects"] += dd
					parts[pid]["list"].append(["1900年の国際的地位", dd])
	for pid in parts:
		var p: Dictionary = parts[pid]
		pillars[pid] = clampf(p["base"] + p["vars"] + p["projects"] + p["facts"], 0.0, 100.0)
	var core: Array = m.get("core", [])
	var vals: Array = core.map(func(c): return float(pillars.get(c, 0.0)))
	var mean := 0.0
	for v in vals:
		mean += v
	mean = mean / maxf(1.0, vals.size())
	var mn: float = vals.min() if not vals.is_empty() else 0.0
	var score := 0.5 * mean + 0.5 * mn
	var tier := _tier(m, pillars, score, core)
	return {"tier": tier["id"], "tier_def": tier, "pillars": pillars, "parts": parts, "score": score,
		"mods": tier.get("mods", {}), "historical": tier.get("historical", false)}


static func _val(pillars: Dictionary, score: float, k: String) -> float:
	return score if k == "score" else float(pillars.get(k, 0.0))


static func _meets(c: Dictionary, pillars: Dictionary, score: float, core: Array) -> bool:
	for k in c:
		if k == "any":
			var ok := false
			for k2 in c["any"]:
				if _val(pillars, score, k2) >= float(c["any"][k2]):
					ok = true
			if not ok:
				return false
		elif k == "core_at_least":
			var n := 0
			for cc in core:
				if float(pillars.get(cc, 0.0)) >= float(c[k][1]):
					n += 1
			if n < int(c[k][0]):
				return false
		elif _val(pillars, score, k) < float(c[k]):
			return false
	return true


static func _tier(m: Dictionary, pillars: Dictionary, score: float, core: Array) -> Dictionary:
	var hist: Dictionary = {}
	for t in m.get("tiers", []):
		if t.get("historical", false):
			hist = t
			continue
		if t.has("if") and _meets(t["if"], pillars, score, core):
			return t
		if t.has("if_any"):
			for c in t["if_any"]:
				if _meets(c, pillars, score, core):
					return t
		if t.has("if_max"):
			var all := true
			for k in t["if_max"]:
				if _val(pillars, score, k) > float(t["if_max"][k]):
					all = false
			if all:
				return t
	return hist


## 年 → 1941年の戦力にどれだけ響くか（UI 用「×2.4」）
static func leverage_text(m: Dictionary, year: int) -> String:
	return "×%.1f" % growth(m, year)


# ------------------------------------------------------------------ 国家事業
static func is_done(acts: Array, pid: String) -> bool:
	for a in acts:
		if str(a.get("verb", "")) == "project" and str(a.get("target", "")) == pid and not a.get("ruled", false):
			return true
	return false


## [着手できるか, 理由]
static func available(db: HistoryDB, acts: Array, pillars: Dictionary, pid: String) -> Array:
	var pr: Dictionary = db.projects.get(pid, {})
	if pr.is_empty():
		return [false, "不明な事業"]
	if is_done(acts, pid):
		return [false, "成し遂げた"]
	var alt: Dictionary = pr.get("alt_requires_pillar", {})
	var alt_ok := not alt.is_empty()
	for k in alt:
		if float(pillars.get(k, 0.0)) < float(alt[k]):
			alt_ok = false
	if not alt_ok:
		for r in pr.get("requires", []):
			if not is_done(acts, str(r)):
				return [false, "先に「%s」が必要" % db.projects.get(r, {}).get("name", r)]
	for k in pr.get("requires_pillar", {}):
		if float(pillars.get(k, 0.0)) < float(pr["requires_pillar"][k]):
			return [false, "%sが %d 以上必要（今 %d）" % [pillar_name(db, k), int(pr["requires_pillar"][k]), int(pillars.get(k, 0.0))]]
	return [true, ""]


static func pillar_name(db: HistoryDB, pid: String) -> String:
	for pl in db.war_model.get("pillars", []):
		if pl["id"] == pid:
			return pl["name"]
	return pid


static func projects_for(db: HistoryDB, era_id: String) -> Array:
	var out: Array = []
	for pid in db.projects:
		if str(db.projects[pid].get("era", "")) == era_id:
			out.append(db.projects[pid])
	out.sort_custom(func(a, b): return int(a["year"]) < int(b["year"]))
	return out


# ================================================================== 国際的地位の推移（data/war/standing.json）
## 各時点（1600・1700・1800・1853・1900・1919・1941年）の日本の国際的地位。
## 史実の値（base）＋ 事業（柱の点 × 重み × k × その時点までの複利）＋ 歴史パラメータの変化（時代の終わりまでの変化 × 重み × 複利）＋ 設問の史実（facts）
static func standing(db: HistoryDB, eras: Dictionary, world: Dictionary, acts: Array) -> Dictionary:
	var s: Dictionary = db.standing_model
	if s.is_empty():
		return {"points": [], "mods": []}
	var g: Dictionary = s.get("growth", {})
	var gb := float(g.get("base", 1.6))
	var gc := float(g.get("cap", 3.0))
	var k := float(s.get("k", 1.0))
	var w: Dictionary = s.get("weights", {})
	var vw: Dictionary = s.get("vars", {})
	var vcap := float(s.get("vars_cap", 12))
	var pts: Array = []
	for cp in s.get("checkpoints", []):
		var y := int(cp["year"])
		var proj := 0.0
		var plist: Array = []
		for a in acts:
			if str(a.get("verb", "")) != "project" or a.get("ruled", false):
				continue
			var pr: Dictionary = db.projects.get(str(a.get("target", "")), {})
			if pr.is_empty() or int(pr["year"]) >= y:
				continue
			var gr := minf(gc, pow(gb, float(y - int(pr["year"])) / 100.0))
			var add := 0.0
			for pid in pr.get("pillars", {}):
				add += float(w.get(pid, 0.0)) * float(pr["pillars"][pid])
			add *= k * gr
			proj += add
			if absf(add) >= 0.5:
				plist.append([pr["name"], add])
		var vars_part := 0.0
		var prev := HistoryState.base_state()
		for eid in HistoryDB.ERA_ORDER:
			if not eras.has(eid):
				continue
			var ey := _era_end_year(db, eid)
			if ey >= y:
				break
			var st: Dictionary = eras[eid]
			var gr2 := minf(gc, pow(gb, float(y - ey) / 100.0))
			for v in vw:
				vars_part += float(vw[v]) * (float(st.get(v, 0.0)) - float(prev.get(v, 0.0))) * gr2
			prev = st
		vars_part = clampf(vars_part, -vcap, vcap)
		var facts := 0.0
		var flist: Array = []
		for f in s.get("facts", []):
			if int(f.get("from", 0)) <= y and int(world.get(str(f["q"]), -1)) == int(f["choice"]):
				facts += float(f["points"])
				flist.append([f.get("note", ""), float(f["points"])])
		var score := clampf(float(cp["base"]) + proj + vars_part + facts, 0.0, 100.0)
		pts.append({"year": y, "score": score, "tier": standing_tier(s, score), "base": float(cp["base"]),
			"base_tier": standing_tier(s, float(cp["base"])), "basis": cp.get("basis", ""), "projects": plist, "vars": vars_part, "facts": flist})
	# その時点の地位がもたらす変化
	var mods: Array = []
	var notes: Array = []
	for c in s.get("consequences", []):
		for p in pts:
			if int(p["year"]) != int(c["year"]):
				continue
			var hit: bool = (c.has("if_min") and float(p["score"]) >= float(c["if_min"])) or (c.has("if_max") and float(p["score"]) <= float(c["if_max"]) and float(p["base"]) > float(c["if_max"]))
			if hit:
				mods.append({"rule": "standing%d" % int(c["year"]), "era": db.era_of_year(int(c["year"])), "year": int(c["year"]), "effects": c["mods"], "title": str(c.get("text", ""))})
				notes.append(str(c.get("text", "")))
	# 令和のエンディング用：1941年の地位（史実と違うとき、または1700年までに列強になっていたとき）
	if not pts.is_empty():
		var last: Dictionary = pts[-1]
		var early_power := false
		for p in pts:
			if int(p["year"]) <= 1800 and float(p["score"]) >= _tier_min(s, str(s.get("power_tier", "列強の一角"))):
				early_power = true
		if last["tier"] != last["base_tier"] or early_power:
			mods.append({"rule": "standing_end", "era": "showa", "year": 1941, "effects": {"set": {"standing": last["tier"]}}, "title": "国際的地位"})
	return {"points": pts, "mods": mods, "notes": notes}


static func standing_tier(s: Dictionary, score: float) -> String:
	var best := ""
	for t in s.get("tiers", []):
		if score >= float(t["min"]):
			best = t["id"]
	return best


static func _tier_min(s: Dictionary, tier: String) -> float:
	for t in s.get("tiers", []):
		if t["id"] == tier:
			return float(t["min"])
	return 999.0


## ある年までに列強（power_tier 以上）になっているか
static func power_by(st_res: Dictionary, s: Dictionary, year: int) -> bool:
	for p in st_res.get("points", []):
		if int(p["year"]) <= year and float(p["score"]) >= _tier_min(s, str(s.get("power_tier", "列強の一角"))):
			return true
	return false

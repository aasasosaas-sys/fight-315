class_name Knowledge
extends RefCounted
## 知識の木（data/crafting/knowledge.json）と施設（buildings.json）。状態は PlayerProfile.knowledge {id: {p: 原理を知る, m: 習熟}}。
## 学び方:
##  - 現代の常識（modern: true のノード）：はじめから「原理」だけ知っている（習熟 0）
##  - 師（工房・学問所の稽古）: 原理＋習熟（上限 100）
##  - 書物（『解体新書』など）・未来の教科書: 原理（前提の原理が要る）
##  - 自分で試す（実験：材料を使う）: 習熟（上限 60）
##  - 施設を動かす: 習熟（上限 80）
## 習熟はいつも「前提の習熟の最小 + 30」を超えられない（基礎なしに応用は身につかない）。
## 技術完全習得モードではすべての原理を知り、習熟 100。

const CAP_TEACHER := 100.0
const CAP_EXPERIMENT := 60.0
const CAP_RUN := 80.0

static var _data: Dictionary = {}
static var _nodes: Dictionary = {}
static var _order: Array = []
static var _buildings: Array = []


static func ensure() -> void:
	if not _data.is_empty():
		return
	var p := "res://data/crafting/knowledge.json"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	_data = d if d is Dictionary else {"nodes": [], "domains": {}, "schools": {}}
	for n in _data.get("nodes", []):
		_nodes[str(n["id"])] = n
		_order.append(str(n["id"]))
	var b := "res://data/crafting/buildings.json"
	var bd: Variant = JSON.parse_string(FileAccess.get_file_as_string(b)) if FileAccess.file_exists(b) else null
	_buildings = (bd as Dictionary).get("buildings", []) if bd is Dictionary else []


static func ids() -> Array:
	ensure()
	return _order


static func node(id: String) -> Dictionary:
	ensure()
	return _nodes.get(id, {})


static func node_name(id: String) -> String:
	return str(node(id).get("name", id))


static func domains() -> Dictionary:
	ensure()
	return _data.get("domains", {})


static func domain_of(id: String) -> Dictionary:
	return domains().get(str(node(id).get("domain", "")), {})


static func schools() -> Dictionary:
	ensure()
	return _data.get("schools", {})


static func nodes_in(domain: String) -> Array:
	return ids().filter(func(i): return str(node(i).get("domain", "")) == domain)


## 教われる工房・学問所の id（workshops.json の id か schools の id）
static func schools_for(id: String) -> Array:
	return node(id).get("schools", [])


## この工房・学問所で教わる知識（id -> 上限）
static func taught_at(school_id: String) -> Array:
	return ids().filter(func(i): return school_id in schools_for(i))


## schools を工房（workshops.json と同じ形）に変換して返す（CraftWorld が置く）
static func school_workshops(era_id: String) -> Array:
	var out: Array = []
	var sc := schools()
	for sid in sc:
		var s: Dictionary = sc[sid]
		if not (era_id in s.get("eras", [])):
			continue
		var w := s.duplicate()
		w["id"] = sid
		w["teaches"] = {}
		w["lessons"] = []
		w["stations"] = []
		w["is_school"] = true
		out.append(w)
	return out


static func vars_for(id: String) -> Dictionary:
	return node(id).get("vars", {})


# ------------------------------------------------------------------ 施設
static func buildings() -> Array:
	ensure()
	return _buildings


static func building(id: String) -> Dictionary:
	for b in buildings():
		if str(b.get("id", "")) == id:
			return b
	return {}


# ------------------------------------------------------------------ 状態（prof = PlayerProfile）
static func knows(prof, id: String) -> bool:
	if PlayerProfile.master_mode():
		return true
	return bool(prof.knowledge.get(id, {}).get("p", false))


static func mastery(prof, id: String) -> float:
	if PlayerProfile.master_mode():
		return 100.0
	return float(prof.knowledge.get(id, {}).get("m", 0.0))


static func prereqs_known(prof, id: String) -> bool:
	for pr in node(id).get("prereq", []):
		if not knows(prof, pr):
			return false
	return true


## 前提の習熟から決まる、今の習熟の上限
static func prereq_cap(prof, id: String) -> float:
	var m := 100.0
	for pr in node(id).get("prereq", []):
		m = minf(m, mastery(prof, pr) + 30.0)
	return m


## 原理を学ぶ。force = 現代の常識・師（前提を問わない）
static func learn(prof, id: String, force := false) -> bool:
	if node(id).is_empty():
		return false
	if not force and not prereqs_known(prof, id):
		return false
	var st: Dictionary = prof.knowledge.get(id, {"p": false, "m": 0.0})
	if st.get("p", false):
		return false
	st["p"] = true
	prof.knowledge[id] = st
	prof.knowledge_changed(id, 0.0, float(st.get("m", 0.0)), true)
	return true


## 習熟を上げる。上がった量を返す
static func train(prof, id: String, amount: float, cap: float) -> float:
	if PlayerProfile.master_mode() or node(id).is_empty():
		return 0.0
	var st: Dictionary = prof.knowledge.get(id, {"p": false, "m": 0.0})
	if not st.get("p", false):
		return 0.0
	var old := float(st.get("m", 0.0))
	var lim := minf(cap, prereq_cap(prof, id))
	if old >= lim:
		return 0.0
	var nv := minf(lim, old + Skills.gain(old, amount))
	st["m"] = nv
	prof.knowledge[id] = st
	prof.knowledge_changed(id, old, nv, false)
	return nv - old


## 現代の高校生の常識（はじめに知っている原理）
static func modern_pool() -> Array:
	return ids().filter(func(i): return bool(node(i).get("modern", false)))


static func known_count(prof) -> int:
	var n := 0
	for i in ids():
		if knows(prof, i):
			n += 1
	return n


## 未来の教科書を読む：前提の原理がそろったノードの原理をまとめて知る（くり返し読める）
static func read_textbook(prof) -> Array:
	var got: Array = []
	var changed := true
	while changed:
		changed = false
		for i in ids():
			if not knows(prof, i) and prereqs_known(prof, i) and learn(prof, i):
				got.append(i)
				changed = true
	return got


## 書物を読む（その本のノードの原理＋習熟 10）
static func read_book(prof, book_id: String) -> Dictionary:
	var nid := str(CraftDB.item(book_id).get("node", ""))
	if nid == "":
		return {"ok": false, "reason": "読めるところがない"}
	if not prereqs_known(prof, nid):
		var miss: Array = node(nid).get("prereq", []).filter(func(x): return not knows(prof, x))
		return {"ok": false, "reason": "前提がわからない：" + "、".join(miss.map(func(x): return node_name(x)))}
	var new := learn(prof, nid)
	var g := train(prof, nid, 10.0, CAP_EXPERIMENT)
	return {"ok": true, "node": nid, "new": new, "gain": g}


## 自分で試す（実験）の材料
static func experiment_mats(id: String) -> Dictionary:
	return domain_of(id).get("mats", {})


## 施設を建てられるか：[ok, 理由]
const AT_NAMES := {"capital": "都", "village": "村", "temple": "寺社", "port": "港", "castle": "城", "battlefield": "戦場", "mountain": "山"}


static func can_build(prof, b: Dictionary, era_id: String, at: String) -> Array:
	if b.is_empty():
		return [false, "施設がない"]
	for k in b.get("know", {}):
		if mastery(prof, k) < float(b["know"][k]):
			return [false, "知識：%s 習熟 %d が要る（今 %d）" % [node_name(k), int(b["know"][k]), int(mastery(prof, k))]]
	if at == "" or not (at in b.get("at", [])):
		return [false, "建てられる場所：" + "・".join((b.get("at", []) as Array).map(func(x): return str(AT_NAMES.get(str(x), x))))]
	if b.get("permit", false) and not prof.permits.get(era_id, false):
		return [false, "支配者の許しが要る（人物を説得するか冥加金を納める）"]
	if b.get("school", false) and known_count(prof) < 6:
		return [false, "教えられる知識が足りない（原理を6つ以上）"]
	var mats := build_mats(b, at)
	for m in mats:
		if prof.count(m) < int(mats[m]):
			return [false, "建材が足りない：%s %d/%d" % [CraftDB.item_name(m), prof.count(m), int(mats[m])]]
	if prof.money < int(b.get("money", 0)):
		return [false, "お金が足りない：%s" % CraftDB.money_text(int(b.get("money", 0)), era_id)]
	return [true, ""]


## 動力：water（川沿いの名所）か steam（蒸気機関）
static func power_mode(b: Dictionary, at: String) -> String:
	var pw := str(b.get("power", "none"))
	if pw == "water_or_steam":
		return "water" if at in ["village", "temple", "port"] else "steam"
	return pw


static func build_mats(b: Dictionary, at: String) -> Dictionary:
	var m: Dictionary = (b.get("mats", {}) as Dictionary).duplicate()
	if power_mode(b, at) == "steam":
		m["jouki"] = int(m.get("jouki", 0)) + 1
	return m


## 冥加金（許しを得るための上納金）
static func permit_fee(era_id: String) -> int:
	return 200000 + CraftDB.era_index(era_id) * 100000


## 施設 1 回の生産の効率（働き手・腕前・動力）
static func efficiency(rec: Dictionary) -> float:
	var b := building(str(rec.get("type", "")))
	var need := maxf(1.0, float(b.get("workers", 1)))
	var w := clampf(float(rec.get("workers", 0)) / need, 0.0, 1.0)
	var skill := clampf(float(rec.get("skill", 10)) / 100.0, 0.0, 1.0)
	var pw := 0.7 if str(rec.get("power", "none")) == "water" else 1.0
	var scale := 1.0 + 0.5 * (int(rec.get("scale", 1)) - 1)
	return w * (0.5 + 0.7 * skill) * pw * scale


## 歴史への効き目の倍率（拡張・学校は知っている原理の数）
static func industry_scale(prof, rec: Dictionary) -> float:
	var b := building(str(rec.get("type", "")))
	var s := 1.0 + 0.5 * (int(rec.get("scale", 1)) - 1)
	if b.get("school", false):
		s *= 1.0 + float(known_count(prof)) / 10.0
	return s

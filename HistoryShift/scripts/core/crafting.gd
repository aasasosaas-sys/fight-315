class_name Crafting
extends RefCounted
## 製作と品の能力値。品質 q（0〜1）は作り手の技能・材料の質・稽古（ミニゲーム）の出来で決まり、
## 刀なら切れ味（威力）・耐久・重さ（振りの速さ）、銃なら精度・不発・装填、弾薬・爆弾なら威力と不発に効く。
##
## 品質の式:  q = 0.15 + 0.6·主技能 + 0.15·補助技能 + 0.3·(材料の質 − 0.5) + 0.2·(出来 − 0.5)   （0.05〜1.0）
##   主技能 = レシピの skill の平均（技能/100）、補助技能 = aux の重み付き平均（無ければ主技能）
## 等級: 粗悪 < 0.3 ≤ 並 < 0.55 ≤ 上 < 0.8 ≤ 名工

const GRADES := [[0.0, "粗悪"], [0.3, "並"], [0.55, "上"], [0.8, "名工"]]
const GRADE_COLORS := {"粗悪": Color(0.65, 0.6, 0.55), "並": Color(0.9, 0.9, 0.9), "上": Color(0.45, 0.85, 1.0), "名工": Color(1.0, 0.8, 0.35)}


static func grade(q: float) -> String:
	var g := "粗悪"
	for pair in GRADES:
		if q >= float(pair[0]):
			g = pair[1]
	return g


static func grade_color(q: float) -> Color:
	return GRADE_COLORS.get(grade(q), Color.WHITE)


## 品の能力値（基本値 × 品質）
static func item_stats(id: String, q: float) -> Dictionary:
	var b := CraftDB.item(id)
	var t := str(b.get("type", ""))
	var st := {}
	match t:
		"melee":
			st["damage"] = float(b.get("damage", 10)) * (0.7 + 0.6 * q)
			st["speed"] = float(b.get("speed", 0.45)) * (1.15 - 0.3 * q)     # 振り 1 回の秒数（よく鍛えた刀は軽く釣り合いがよい）
			st["reach"] = float(b.get("reach", 2.0))
			st["max_dur"] = float(b.get("dur", 100)) * (0.5 + 1.0 * q)
			st["weight"] = float(b.get("weight", 1.0)) * (1.15 - 0.25 * q)
			st["block"] = float(b.get("block", 0.0))
		"bow":
			st["damage"] = float(b.get("damage", 20)) * (0.75 + 0.5 * q)
			st["draw"] = float(b.get("draw", 0.7)) * (1.2 - 0.4 * q)
			st["arrow_speed"] = float(b.get("arrow_speed", 45)) * (0.85 + 0.3 * q)
			st["max_dur"] = float(b.get("dur", 100)) * (0.6 + 0.8 * q)
		"gun":
			st["damage"] = float(b.get("damage", 30)) * (0.85 + 0.3 * q)
			st["spread"] = float(b.get("spread", 0.01)) * (1.6 - 1.0 * q)
			st["misfire"] = float(b.get("misfire", 0.02)) * (2.0 - 1.7 * q)
			st["reload"] = float(b.get("reload", 2.0)) * (1.3 - 0.45 * q)
			st["recoil"] = float(b.get("recoil", 1.0)) * (1.25 - 0.4 * q)
			st["fire_rate"] = float(b.get("fire_rate", 1.0))
			st["mag"] = int(b.get("mag", 1))
			st["max_dur"] = float(b.get("dur", 100)) * (0.6 + 0.8 * q)
		"bomb", "ammo", "heavy":
			st["power"] = 0.7 + 0.6 * q                   # 威力の倍率
			st["dud"] = pow(1.0 - q, 2.0) * 0.3            # 不発・湿気の確率
		"med":
			st["heal"] = float(b.get("heal", 50)) * (0.7 + 0.6 * q)
	return st


## 品（個体）を作る。stack 品（材料・弾・爆弾など）は呼ばない
static func make_item(id: String, q: float, maker := "", era := "") -> Dictionary:
	var st := item_stats(id, q)
	var inst := {"id": id, "q": snappedf(clampf(q, 0.0, 1.0), 0.001), "stats": st, "maker": maker, "era": era}
	inst["dur"] = float(st.get("max_dur", 0.0))
	inst["mag"] = 0
	return inst


static func is_stack(id: String) -> bool:
	return not (CraftDB.item_type(id) in ["melee", "bow", "gun"])


## レシピの主技能・補助技能（0〜1）
static func skill_parts(prof, r: Dictionary) -> Vector2:
	var sk: Dictionary = r.get("skill", {})
	var main := 0.0
	for k in sk:
		main += prof.level(k) / 100.0
	main = main / maxf(1.0, float(sk.size())) if not sk.is_empty() else 0.5
	var aux: Dictionary = r.get("aux", {})
	var aw := 0.0
	var av := 0.0
	for k in aux:
		aw += float(aux[k])
		av += float(aux[k]) * prof.level(k) / 100.0
	return Vector2(main, av / aw if aw > 0.0 else main)


static func quality(prof, r: Dictionary, mat_q := 0.5, game := 0.5) -> float:
	var p := skill_parts(prof, r)
	var q := 0.15 + 0.6 * p.x + 0.15 * p.y + 0.3 * (mat_q - 0.5) + 0.2 * (game - 0.5)
	return clampf(q, 0.05, 1.0)


## 作れるか：[ok, 理由, anachronistic]。station "" はどこでも作れる品だけ
static func can_craft(prof, r: Dictionary, era_id: String, station: String) -> Array:
	if r.is_empty():
		return [false, "レシピがない", false]
	var st := str(r.get("station", "any"))
	if st != "any" and st != station:
		return [false, "%sで作る" % CraftDB.station_name(st), false]
	var anach := CraftDB.era_index(era_id) < CraftDB.era_index(str(r.get("era", "jomon_kofun")))
	if anach:
		var need: Dictionary = r.get("anachro", {})
		if need.is_empty():
			return [false, "この時代にはまだ作り方がない", true]
		for k in need:
			if prof.level(k) < float(need[k]):
				return [false, "未来の技術：%s %d が要る" % [Skills.skill_name(k), int(need[k])], true]
	for k in r.get("skill", {}):
		if prof.level(k) < float(r["skill"][k]):
			return [false, "%s %d が要る" % [Skills.skill_name(k), int(r["skill"][k])], anach]
	var mats: Dictionary = r.get("mats", {})
	for m in mats:
		if prof.count(m) < int(mats[m]):
			return [false, "材料が足りない：%s %d/%d" % [CraftDB.item_name(m), prof.count(m), int(mats[m])], anach]
	return [true, "", anach]


## 製作する。材料を使い、品を持ち物に入れる。戻り値 {ok, reason, q, grade, item(個体 or {}), count, anachronism}
static func craft(prof, recipe_id: String, era_id: String, station: String, game := 0.5) -> Dictionary:
	var r := CraftDB.recipe(recipe_id)
	var chk := can_craft(prof, r, era_id, station)
	if not chk[0]:
		return {"ok": false, "reason": chk[1]}
	var mats: Dictionary = r.get("mats", {})
	var mq := 0.0
	var mn := 0
	for m in mats:
		mq += prof.stack_quality(m) * int(mats[m])
		mn += int(mats[m])
	mq = mq / maxf(1.0, float(mn))
	for m in mats:
		prof.take(m, int(mats[m]))
	var q := quality(prof, r, mq, game)
	var out := str(r.get("out", ""))
	var n := int(r.get("count", 1))
	var res := {"ok": true, "reason": "", "q": q, "grade": grade(q), "count": n, "out": out, "anachronism": chk[2], "item": {}}
	if is_stack(out):
		prof.add(out, n, q)
	else:
		for i in n:
			var inst := make_item(out, q, "あなた", era_id)
			res["item"] = prof.add_instance(inst)
	# 作ることそのものが稽古になる（主技能）
	for k in r.get("skill", {}):
		prof.practice(k, 1.5)
	return res


## 品の説明（UI 用の一行）
static func stats_text(inst: Dictionary) -> String:
	var id := str(inst.get("id", ""))
	var st: Dictionary = inst.get("stats", {})
	match CraftDB.item_type(id):
		"melee":
			return "威力 %d　振り %.2f秒　間合い %.1fm　耐久 %d/%d" % [int(st.get("damage", 0)), float(st.get("speed", 0)), float(st.get("reach", 0)), int(inst.get("dur", 0)), int(st.get("max_dur", 0))]
		"bow":
			return "威力 %d　引き %.2f秒　矢速 %d　耐久 %d/%d" % [int(st.get("damage", 0)), float(st.get("draw", 0)), int(st.get("arrow_speed", 0)), int(inst.get("dur", 0)), int(st.get("max_dur", 0))]
		"gun":
			if CraftDB.item(id).get("infinite", false):
				return "威力 %d　装弾 %d　弾は尽きない" % [int(st.get("damage", 0)), int(st.get("mag", 0))]
			return "威力 %d　精度 %.1f　不発 %d%%　装填 %.1f秒　装弾 %d　耐久 %d/%d" % [int(st.get("damage", 0)), 1.0 / maxf(0.0005, float(st.get("spread", 0.01))) / 100.0, roundi(float(st.get("misfire", 0)) * 100.0), float(st.get("reload", 0)), int(st.get("mag", 1)), int(inst.get("dur", 0)), int(st.get("max_dur", 0))]
	return ""

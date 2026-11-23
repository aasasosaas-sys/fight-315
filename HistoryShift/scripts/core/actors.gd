class_name HistoryActors
extends RefCounted
## 人物・場所への「自由な行動」の一般則（data/actors/<era>.json の人物データ＋汎用の既定値）。
## 手作りの揺らぎルール（data/chaos/<era>.json）に当てはまらなかった行動はここで解決される。
## HistoryState.actions（行動の記録）から純粋関数 resolve() で「強制される史実」と「歴史パラメータの変化」を毎回作り直す。
##
## 動詞（verb）:
##   kill     倒れた（原因は問わない：銃・流れ弾・爆発・火・暴走した乗り物…）→ その人物の貢献（contrib）が失われる。
##            後継者（successor）が健在なら出来事は引き継がれる。貢献のデータが無ければタグごとの既定値
##   escort   別の名所へ連れて行った（to）→ 元の役目からは消える＋行き先の名所の影響
##   protect  史実の非業の死を防いだ（saved）。give 特効薬 は病死を防ぐ
##   persuade 説得（arg）。受け入れるかは性格（traits）次第（ok を行動に記録）。人物ごとの特例（persuade）もある
##   give     物を渡した（item）
##   steal / forge  書状を盗む／偽の書状を渡す（doc があればそれ、無ければ既定値）
##   steer    「未来を語る」：問題 q を選択肢 choice の方へ導く（ok のときだけ）。どの問題・選択肢にも必ず届く道
##   delay    予定（schedule の event）に遅れさせた（会話で引き止めた・追い回した・橋が落ちて足止め…）
##   sabotage 名所を壊した・焼いた（target = 名所キー）
##   battle   合戦で一方に加勢した（target = 合戦 id、side = 勝たせた側の名前）

const VIOLENT := ["assassinated", "killed", "suicide", "executed", "accident", "poisoned"]
const NOKILL_TAGS := ["sacred", "woman", "foreigner", "commoner", "religious", "scholar", "artist"]
const VERBS := ["kill", "escort", "protect", "persuade", "give", "steal", "forge", "steer", "delay", "sabotage", "battle"]

## 説得の論点：trait（その性格が正なら受け入れやすい／sign -1 なら負で受け入れる）と効果（影響力を掛ける）
const ARGS := {
	"開国を勧める": {"trait": "open", "sign": 1, "vars": {"open_west": 10, "open_asia": 5, "commerce": 5}, "early": {"open_asia": 12, "commerce": 4}},
	"鎖国を勧める": {"trait": "open", "sign": -1, "vars": {"open_west": -12, "open_asia": -5}, "early": {"open_asia": -12}},
	"未来の技術を教える": {"trait": "reform", "sign": 1, "vars": {"tech": 12, "education": 5}},
	"改革を勧める": {"trait": "reform", "sign": 1, "vars": {"centralization": 8, "democracy": 6}, "early": {"centralization": 10}},
	"戦をやめさせる": {"trait": "war", "sign": -1, "vars": {"militarism": -10, "unity": 5}},
	"戦を勧める": {"trait": "war", "sign": 1, "vars": {"militarism": 10, "warrior": 6, "unity": -4}},
	"裏切りを促す": {"trait": "loyal", "sign": -1, "vars": {"unity": -10, "warrior": 4}},
	"忠義を説く": {"trait": "loyal", "sign": 1, "vars": {"unity": 8}},
	"民を大切に": {"trait": "reform", "sign": 1, "vars": {"commoners": 10, "democracy": 4}, "early": {"commoners": 10}},
	"学問を勧める": {"trait": "reform", "sign": 1, "vars": {"education": 10}},
	"信仰を勧める": {"trait": "faith", "sign": 1, "vars": {"religion": 10}},
	"倹約を勧める": {"trait": "reform", "sign": 1, "vars": {"commerce": -6, "economy": 4, "centralization": 3}},
}
## 渡す物
const ITEMS := {
	"未来の教科書": {"vars": {"education": 8, "tech": 5}},
	"鉄砲": {"vars": {"militarism": 8, "warrior": 8, "tech": 4}},
	"千両箱": {"vars": {"commerce": 8, "economy": 8}},
	"特効薬": {"vars": {"commoners": 3}},
	"世界地図": {"vars": {"open_west": 8, "open_asia": 4}, "early": {"open_asia": 10}},
	"蒸気機関の図面": {"vars": {"tech": 12, "economy": 4}},
}
## 人物がいなくなったときの既定値（タグごと、影響力を掛ける）
const TAG_ABSENT := {
	"ruler": {"unity": -10, "centralization": -10},
	"official": {"centralization": -6},
	"warrior": {"warrior": -8, "militarism": -5},
	"rebel": {"unity": 8, "warrior": -4},
	"diplomat": {"open_west": -8, "open_asia": -5},
	"scholar": {"education": -8},
	"religious": {"religion": -8},
	"reformer": {"centralization": -5, "democracy": -6},
	"merchant": {"commerce": -8, "economy": -5},
	"artist": {"education": -5},
}
## 非業の死を防いだときの既定値
const TAG_SAVED := {
	"ruler": {"unity": 8, "centralization": 8},
	"official": {"centralization": 5},
	"warrior": {"warrior": 6},
	"rebel": {"unity": -10, "warrior": 6},
	"diplomat": {"open_west": 6, "open_asia": 4},
	"scholar": {"education": 6},
	"religious": {"religion": 6},
	"reformer": {"democracy": 8, "centralization": 4},
	"merchant": {"commerce": 6, "economy": 4},
	"artist": {"education": 4},
}
## 名所を壊したとき（sabotage）・人を連れて行った先（escort）の既定値
const PLACE := {
	"capital": {"centralization": -8, "court": -6},
	"castle": {"militarism": -6, "warrior": -6},
	"temple": {"religion": -8, "education": -4},
	"port": {"commerce": -8, "open_west": -5, "open_asia": -5},
	"village": {"economy": -5, "commoners": -5},
	"battlefield": {"unity": -5},
	"mountain": {"commerce": -4, "unity": -3},
	"town": {"economy": -4, "commoners": -3},
	"river": {"commerce": -5, "economy": -3},
}
const ESCORT_TO := {
	"capital": {"centralization": 4, "court": 4},
	"castle": {"militarism": 4},
	"temple": {"religion": 5, "education": 3},
	"port": {"open_west": 6, "open_asia": 6},
	"village": {"commoners": 5},
	"battlefield": {"warrior": 4},
	"mountain": {"unity": -3},
}
## 倒れた原因の言い回し（info.cause）
const CAUSE_TEXT := {
	"player": "あなたの手で", "shot": "あなたの撃った弾で", "stray": "流れ弾に当たって", "explosion": "爆発に巻き込まれて",
	"fire": "火に巻かれて", "vehicle": "暴走した車にはねられて", "horse": "暴れ馬に蹴られて", "plane": "墜落する飛行機に巻き込まれて",
	"crossfire": "追手の撃ち合いに巻き込まれて", "debris": "崩れた瓦礫の下敷きになって", "world": "思わぬ事故で",
}


static func is_noncombatant(a: Dictionary) -> bool:
	for t in a.get("tags", []):
		if t in NOKILL_TAGS:
			return true
	return false


static func influence(a: Dictionary) -> float:
	var tags: Array = a.get("tags", [])
	if "ruler" in tags:
		return 1.0
	for t in ["official", "warrior", "reformer", "diplomat", "rebel"]:
		if t in tags:
			return 0.7
	return 0.5


static func is_early(era_id: String) -> bool:
	return HistoryDB.ERA_ORDER.find(era_id) < HistoryDB.ERA_ORDER.find("sengoku")


## 会話メニューに出す行動（protect は非業の死、特効薬は病死の人物だけ）
static func verbs_for(a: Dictionary) -> Array:
	var out: Array = ["persuade", "give", "escort"]
	if str(a.get("death", "")) in VIOLENT:
		out.append("protect")
	var tags: Array = a.get("tags", [])
	if a.has("doc") or "official" in tags or "ruler" in tags or "diplomat" in tags:
		out.append("steal")
		out.append("forge")
	return out


## 説得が通るか（性格 × 論点。同点はその人物と論点で決まった気まぐれ）。trust は贈り物などで増える
static func persuade_ok(a: Dictionary, arg: String, trust := 0) -> bool:
	var spec: Dictionary = ARGS.get(arg, {})
	if spec.is_empty():
		return false
	if a.get("persuade", {}).has(arg):
		return true
	var v := int(a.get("traits", {}).get(spec["trait"], 0)) * int(spec["sign"]) + trust
	if v != 0:
		return v > 0
	return absi(hash(str(a.get("name", "")) + arg)) % 2 == 0


## 「未来を語る」が通るか。信頼（贈り物・説得・命を救った）があれば必ず通る
static func steer_ok(a: Dictionary, qid: String, choice: int, trust := 0) -> bool:
	if trust > 0:
		return true
	return absi(hash(str(a.get("name", "")) + qid + str(choice))) % 3 != 0


static func _scale(v: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key in v:
		if key == "set":
			out["set"] = v["set"]
		else:
			out[key] = roundi(float(v[key]) * k)
	return out


static func _add(dst: Dictionary, v: Dictionary) -> void:
	for key in v:
		if key == "set":
			dst["set"] = v["set"]
		else:
			dst[key] = int(dst.get(key, 0)) + int(v[key])


static func _tags_vars(a: Dictionary, table: Dictionary, k: float) -> Dictionary:
	var out := {}
	for t in a.get("tags", []):
		if table.has(t):
			_add(out, table[t])
	return _scale(out, k * influence(a))


# ================================================================== 解決
## 行動の記録 → {"forces": {qid: {choice, seq, note}}, "mods": [{rule, era, year, effects, title}], "notes": {seq: [文章]}}
static func resolve(db: HistoryDB, actions: Array) -> Dictionary:
	var forces := {}
	var mods: Array = []
	var notes := {}
	# 1. 人物ごとの最終状態
	var st := {}
	for a in actions:
		var nm := db.actor_name(str(a.get("target", "")))
		if nm == "":
			continue
		if not st.has(nm):
			st[nm] = {"gone": -1, "saved": -1, "trust": 0}
		var s: Dictionary = st[nm]
		match str(a.get("verb", "")):
			"kill", "escort":
				if s["gone"] < 0:
					s["gone"] = int(a.get("seq", 0))
			"protect":
				s["saved"] = int(a.get("seq", 0))
				s["trust"] += 2
			"give":
				s["trust"] += 1
				var ad: Dictionary = db.actors[nm]
				if str(a.get("item", "")) == "特効薬" and str(ad.get("death", "")) == "illness":
					s["saved"] = int(a.get("seq", 0))
			"persuade":
				if a.get("ok", false):
					s["trust"] += 1
	# 2. 効果（ruled = 手作りルールが効果を受け持った行動は、状態にだけ数えて効果は出さない）
	for a in actions:
		if a.get("ruled", false):
			continue
		var seq := int(a.get("seq", 0))
		var verb := str(a.get("verb", ""))
		var era := str(a.get("era", ""))
		var nm := db.actor_name(str(a.get("target", "")))
		var ad: Dictionary = db.actors.get(nm, {})
		var yr := int(ad.get("active", 0)) if not ad.is_empty() else _era_mid(db, era)
		var aera := str(ad.get("era", era)) if not ad.is_empty() else era
		var out: Array = []   # [{force?, vars?, year, note}]
		match verb:
			"kill", "escort":
				if ad.is_empty() or st[nm]["gone"] != seq:
					pass
				else:
					var any := false
					for c in ad.get("contrib", []):
						var sc := str(c.get("successor", ad.get("successor", "")))
						if sc != "" and db.actors.has(sc) and not (st.has(sc) and st[sc]["gone"] >= 0):
							out.append({"note": "%sに代わって%sがその役目を引き継いだ" % [nm, sc]})
							any = true
							continue
						out.append(_contrib_effect(db, c, ad))
						any = true
					var sc0 := str(ad.get("successor", ""))
					if not any and sc0 != "" and db.actors.has(sc0) and not (st.has(sc0) and st[sc0]["gone"] >= 0):
						out.append({"note": "%sに代わって%sがその役目を引き継いだ" % [nm, sc0]})
						any = true
					if not any:
						out.append({"vars": _tags_vars(ad, TAG_ABSENT, 1.0), "year": yr, "era": aera,
							"note": "%sがいなくなり、その役目を担う者が欠けた" % nm})
					if verb == "escort":
						var to := str(a.get("to", ""))
						if ESCORT_TO.has(to):
							out.append({"vars": _scale(ESCORT_TO[to], influence(ad)), "year": yr, "era": aera,
								"note": "%sは%sで新しい人生を歩み始めた" % [nm, HistoryDB.landmark_name(db.get_era(era), to)]})
			"protect", "give":
				if not ad.is_empty() and st[nm]["saved"] == seq and st[nm]["gone"] < 0:
					var sv: Dictionary = ad.get("saved", {})
					if not sv.is_empty():
						var e := {"year": int(sv.get("year", ad.get("died", yr))), "note": str(sv.get("text", ""))}
						e["era"] = db.era_of_year(e["year"])
						if sv.has("force"):
							e["force"] = sv["force"]
						if sv.has("vars"):
							e["vars"] = sv["vars"]
						out.append(e)
					else:
						var dy := int(ad.get("died", yr)) if ad.get("died") != null else yr
						out.append({"vars": _tags_vars(ad, TAG_SAVED, 1.0), "year": dy, "era": db.era_of_year(dy),
							"note": "%sは生き延び、その後も働き続けた" % nm})
				elif verb == "give" and not ad.is_empty():
					var it: Dictionary = ITEMS.get(str(a.get("item", "")), {})
					var gv: Dictionary = ad.get("give", {}).get(str(a.get("item", "")), {})
					if not gv.is_empty():
						out.append(_special(db, gv, yr, aera))
					elif not it.is_empty():
						var vv: Dictionary = it.get("early", it["vars"]) if is_early(aera) else it["vars"]
						out.append({"vars": _scale(vv, influence(ad)), "year": yr, "era": aera,
							"note": "%sは未来の「%s」を手にした" % [nm, a.get("item", "")]})
			"persuade":
				if not ad.is_empty() and a.get("ok", false):
					var arg := str(a.get("arg", ""))
					var pv: Dictionary = ad.get("persuade", {}).get(arg, {})
					if not pv.is_empty():
						out.append(_special(db, pv, yr, aera))
					elif ARGS.has(arg):
						var spec: Dictionary = ARGS[arg]
						var vv2: Dictionary = spec.get("early", spec["vars"]) if is_early(aera) else spec["vars"]
						out.append({"vars": _scale(vv2, influence(ad)), "year": yr, "era": aera, "note": "%sは「%s」という進言を聞き入れた" % [nm, arg]})
			"steal", "forge":
				if not ad.is_empty():
					var doc: Dictionary = ad.get("doc", {})
					if verb == "steal" and doc.has("q"):
						out.append({"force": {"q": doc["q"], "choice": int(doc["choice"])}, "note": str(doc.get("text", ""))})
					else:
						var dv := {"centralization": -8, "unity": -5} if verb == "steal" else {"unity": -10, "court": -4}
						out.append({"vars": _scale(dv, influence(ad)), "year": yr, "era": aera,
							"note": ("%sの書状が盗まれ、政務が滞った" if verb == "steal" else "%sに偽の書状がつかまされ、疑心暗鬼が広がった") % nm})
			"steer":
				if a.get("ok", false) and db.by_id.has(str(a.get("q", ""))):
					out.append({"force": {"q": str(a["q"]), "choice": int(a.get("choice", 0))}, "note": "%sが未来の話に導かれた" % (nm if nm != "" else "人々")})
			"delay":
				if not ad.is_empty():
					var found := false
					for sc2 in ad.get("schedule", []):
						if str(sc2.get("event", "")) == str(a.get("event", "")):
							var ms: Dictionary = sc2.get("missed", {})
							out.append(_special(db, ms.merged({"text": sc2.get("text", ""), "year": sc2.get("year", yr)}), int(sc2.get("year", yr)), aera))
							found = true
					if not found:
						var dvv := {}
						for c in ad.get("contrib", []):
							if c.has("vars"):
								_add(dvv, c["vars"])
						if dvv.is_empty():
							dvv = _tags_vars(ad, TAG_ABSENT, 1.0)
						out.append({"vars": _scale(dvv, 0.4), "year": yr, "era": aera, "note": "%sが大事な場に遅れ、物事が少しずつずれていった" % nm})
			"sabotage":
				var key := str(a.get("target", ""))
				var k2 := clampf(float(a.get("value", 400)) / 800.0, 0.5, 2.0)
				out.append({"vars": _scale(PLACE.get(key, PLACE["town"]), k2), "year": _era_mid(db, era), "era": era,
					"note": "%sが壊され、人々の暮らしと政治に影が落ちた" % HistoryDB.landmark_name(db.get_era(era), key)})
			"battle":
				for b in db.battles:
					if b["id"] == str(a.get("target", "")):
						for side in b.get("sides", []):
							if side["name"] == str(a.get("side", "")) and side.has("wins"):
								out.append(_special(db, side["wins"].merged({"text": side.get("text", "")}), int(b.get("year", yr)), str(b.get("era", era))))
		var ns: Array = []
		for o in out:
			if o.has("force"):
				var f: Dictionary = o["force"]
				var qid := str(f.get("q", ""))
				if db.by_id.has(qid) and (not forces.has(qid) or int(forces[qid]["seq"]) <= seq):
					forces[qid] = {"choice": clampi(int(f.get("choice", 0)), 0, 3), "seq": seq, "note": str(o.get("note", ""))}
			if o.has("vars") and not (o["vars"] as Dictionary).is_empty():
				mods.append({"rule": "act%d" % seq, "era": str(o.get("era", era)), "year": int(o.get("year", yr)), "effects": o["vars"], "title": str(o.get("note", ""))})
			if str(o.get("note", "")) != "":
				ns.append(str(o["note"]))
		notes[seq] = ns
	return {"forces": forces, "mods": mods, "notes": notes}


static func _contrib_effect(db: HistoryDB, c: Dictionary, ad: Dictionary) -> Dictionary:
	var e := {"note": str(c.get("note", ""))}
	if c.has("choice") and db.by_id.has(str(c.get("q", ""))):
		e["force"] = {"q": c["q"], "choice": int(c["choice"])}
	if c.has("vars"):
		e["vars"] = c["vars"]
		e["year"] = int(c.get("year", ad.get("active", 0)))
		e["era"] = str(ad.get("era", ""))
	return e


static func _special(db: HistoryDB, sp: Dictionary, yr: int, era: String) -> Dictionary:
	var e := {"note": str(sp.get("text", ""))}
	if sp.has("force"):
		e["force"] = sp["force"]
	if sp.has("vars"):
		e["vars"] = sp["vars"]
		e["year"] = int(sp.get("year", yr))
		e["era"] = db.era_of_year(e["year"]) if HistoryDB.ERA_ORDER.find(db.era_of_year(e["year"])) > HistoryDB.ERA_ORDER.find(era) else era
	return e


static func _era_mid(db: HistoryDB, era: String) -> int:
	var e := db.get_era(era)
	var ys: Array = e.get("questions", []).map(func(q): return int(q["year"]))
	return 0 if ys.is_empty() else int((ys.min() + ys.max()) / 2)


## 行動の見出し（HUD・アフター画面・ハブの行動記録）
static func headline(db: HistoryDB, a: Dictionary) -> String:
	var nm := db.actor_name(str(a.get("target", "")))
	if nm == "":
		nm = str(a.get("target", ""))
	match str(a.get("verb", "")):
		"kill":
			return "%s%sが倒れた" % [CAUSE_TEXT.get(str(a.get("cause", "player")), "思わぬことで"), nm]
		"escort":
			return "%sを%sへ連れて行った" % [nm, HistoryDB.landmark_name(db.get_era(str(a.get("era", ""))), str(a.get("to", "")))]
		"protect":
			return "%sを刺客から守り抜いた" % nm
		"give":
			return "%sに「%s」を渡した" % [nm, a.get("item", "")]
		"persuade":
			return "%sに「%s」%s" % [nm, a.get("arg", ""), "――聞き入れられた" if a.get("ok", false) else "――はねつけられた"]
		"steal":
			return "%sの書状を盗んだ" % nm
		"forge":
			return "%sに偽の書状をつかませた" % nm
		"steer":
			var q: Dictionary = db.by_id.get(str(a.get("q", "")), {})
			return "%sに未来を語った（%s）" % [nm, q.get("topic", "")]
		"delay":
			return "%sが「%s」に遅れた（%s）" % [nm, a.get("event", "大事な用"), a.get("cause_text", "足止め")]
		"sabotage":
			return "%sを破壊した" % HistoryDB.landmark_name(db.get_era(str(a.get("era", ""))), str(a.get("target", "")))
		"battle":
			return "%sで%sに加勢した" % [a.get("battle_name", a.get("target", "")), a.get("side", "")]
	return str(a.get("verb", ""))

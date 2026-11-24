class_name EraTimeline
extends RefCounted
## 時代の中の「年」（data/eras/<eraId>_timeline.json）。各時代の箱庭は一枚の静止画ではなく、選んだ年の姿になる。
##  - 時点（points）：自由探索で選べる年。year / label / desc / basis（年の入った史実）/ guard（護衛の名）/ crowd（町人の装いの比率）/
##    enemy_outfit / crowd_n（町人の数の倍率）/ events（great_fire famine kurofune open_port earthquake air_raid olympics …）/
##    ruin（その年だけの被災：[{landmark, kind(文字列か配列), frac, burned}]）
##  - 時代全体：range / default（代表の年）/ ships（[{id, from, until, basis}]：港の大型船）/
##    units（[{landmark, kind, from, until, keep, basis}]：その年にまだ無い・もう無い建物。keep = 大きい順に残す数）
##  - 人物：生没年・活動開始年（active）と、あなたの行動（倒した年・救った）で、その年にいるかが決まる（actor_present）
##  - 予定（schedule）・合戦・国家事業は、その年に最も近い時点（人物がいる時点）に現れる
## Game を参照しない（-s で走るテストからも使える）。

const DIR := "res://data/eras"
const ACTIVE_LEAD := 10          # 活動開始年（active）の何年前から名所に立つか
const MIN_AGE := 15              # これより若い人物は出さない
const SAVED_LIFESPAN := 80       # 救われた人物は（生年が分かれば）この歳まで生きうる
const SAVED_EXTRA := 25          # 生年が分からなければ史実の没年 + この年数まで
const BATTLE_WINDOW := 2         # 合戦は最も近い時点か、年の差がこれ以内の時点に
const PROJECT_WINDOW := 15       # 国家事業も同じく
## 壊した建物が何年後まで残るか（それより後の時点では建て直されている）。ここに無い種類（天守・塔・御殿・門・寺社・洋館…）は残り続ける
const REBUILD_YEARS := {"house": 25, "kura": 30, "stall": 5, "tower": 15, "boat": 10, "fence": 3, "lamp": 5, "prop": 2,
	"lantern": 20, "wall": 20, "stonewall": 60, "brickwall": 30}

static var _cache := {}
## いまの時空跳躍の年（Session が設定。町人の装いなどが読む）。"" / 0 = 年の指定なし（従来どおり）
static var current_era := ""
static var current_year := 0


static func data(era_id: String) -> Dictionary:
	if _cache.has(era_id):
		return _cache[era_id]
	var d := {}
	var p := DIR.path_join(era_id + "_timeline.json")
	if FileAccess.file_exists(p):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if v is Dictionary:
			d = v
			var pts: Array = d.get("points", [])
			for pt in pts:
				pt["year"] = int(pt["year"])
			pts.sort_custom(func(a, b): return int(a["year"]) < int(b["year"]))
	_cache[era_id] = d
	return d


static func clear_cache() -> void:
	_cache.clear()


static func points(era_id: String) -> Array:
	return data(era_id).get("points", [])


static func years(era_id: String) -> Array:
	return points(era_id).map(func(p): return int(p["year"]))


static func has_timeline(era_id: String) -> bool:
	return not points(era_id).is_empty()


static func default_year(era_id: String) -> int:
	var d := data(era_id)
	if d.has("default"):
		return int(d["default"])
	var ys := years(era_id)
	return int(ys[ys.size() / 2]) if not ys.is_empty() else 0


static func year_range(era_id: String) -> Array:
	var r: Array = data(era_id).get("range", [])
	if r.size() == 2:
		return [int(r[0]), int(r[1])]
	var ys := years(era_id)
	return [int(ys.min()), int(ys.max())] if not ys.is_empty() else [0, 0]


## その年に効いている時点（その年以前で最も新しい時点。無ければ最初の時点）。ミッションの年など時点ちょうどでない年にも使う
static func point_for(era_id: String, year: int) -> Dictionary:
	var best := {}
	for p in points(era_id):
		if int(p["year"]) <= year:
			best = p
	if best.is_empty() and not points(era_id).is_empty():
		best = points(era_id)[0]
	return best


## 年ちょうどの時点（無ければ {}）
static func exact_point(era_id: String, year: int) -> Dictionary:
	for p in points(era_id):
		if int(p["year"]) == year:
			return p
	return {}


## 年に最も近い時点の年（candidates を渡せばその中から）
static func nearest_year(era_id: String, year: int, candidates: Array = []) -> int:
	var ys: Array = candidates if not candidates.is_empty() else years(era_id)
	var best := year
	var bd := 1 << 30
	for y in ys:
		var d := absi(int(y) - year)
		if d < bd:
			bd = d
			best = int(y)
	return best


static func year_text(y: int) -> String:
	return ("紀元前%d年頃" % -y) if y < 0 else ("%d年" % y)


## 表示用の見出し（「1853年 ペリー来航」）。時点ちょうどでなければ「1722年（享保の改革のころ）」
static func label(era_id: String, year: int) -> String:
	var ex := exact_point(era_id, year)
	if not ex.is_empty():
		return str(ex.get("label", year_text(year)))
	var p := point_for(era_id, year)
	if p.is_empty():
		return year_text(year)
	return "%s（%sのころ）" % [year_text(year), str(p.get("label", "")).trim_prefix(year_text(int(p["year"]))).strip_edges()]


static func events(era_id: String, year: int) -> Array:
	return point_for(era_id, year).get("events", [])


static func has_event(era_id: String, year: int, ev: String) -> bool:
	return ev in events(era_id, year)


static func set_current(era_id: String, year: int) -> void:
	current_era = era_id
	current_year = year


# ================================================================== 人々の装い・護衛
const OUTFIT_KEYS := ["AGENT", "COMMONER", "NOBLE", "SAMURAI", "ASHIGARU", "MONK", "WESTERN", "SOLDIER", "GUARDIAN", "ANCIENT", "POLICE", "KIMONO"]


## Humanoid.Outfit の番号（-1 = 指定なし）。role は Humanoid.outfit_for と同じ
static func crowd_outfit(era_id: String, role: String, r: float = -1.0) -> int:
	if current_era == "" or era_id != current_era or current_year == 0:
		return -1
	var p := point_for(era_id, current_year)
	if role == "enemy" and p.has("enemy_outfit"):
		return OUTFIT_KEYS.find(str(p["enemy_outfit"]))
	if role != "civilian" or not p.has("crowd"):
		return -1
	var mix: Dictionary = p["crowd"]
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	if total <= 0.0:
		return -1
	var x := (randf() if r < 0.0 else r) * total
	for k in mix:
		x -= float(mix[k])
		if x <= 0.0:
			return OUTFIT_KEYS.find(str(k))
	return OUTFIT_KEYS.find(str(mix.keys()[-1]))


static func guard_label(era_id: String, year: int, fallback: String) -> String:
	return str(point_for(era_id, year).get("guard", fallback)) if year != 0 else fallback


static func crowd_scale(era_id: String, year: int) -> float:
	return float(exact_point(era_id, year).get("crowd_n", 1.0)) if year != 0 else 1.0


# ================================================================== 人物
## 史実の在世・活動の範囲 [from, to]（-1<<30 / 1<<30 = 不明＝制限なし）
static func actor_window(a: Dictionary) -> Array:
	var lo := -(1 << 30)
	var hi := 1 << 30
	var b: Variant = a.get("born")
	var d: Variant = a.get("died")
	var ac: Variant = a.get("active")
	var has_lo := false
	if ac != null:
		lo = int(ac) - ACTIVE_LEAD
		has_lo = true
	if b != null:
		lo = maxi(lo, int(b) + MIN_AGE) if has_lo else int(b) + MIN_AGE
		has_lo = true
	if d != null:
		hi = int(d)
	elif b != null:
		hi = int(b) + 70
	elif ac != null:
		hi = int(ac) + 40
	if has_lo and lo > hi:
		lo = hi - 10   # 幼くして没した・データの食い違い（活動開始が没年より後など）は没年の少し前から（生年より前にはしない）
		if b != null:
			lo = maxi(lo, int(b))
	return [lo, hi]


## あなたの行動による人物の状態：{gone: 倒した/連れ去った年（無ければ null）, gone_era, saved}
static func actor_fate(db: HistoryDB, actions: Array, nm: String) -> Dictionary:
	var out := {"gone": null, "gone_era": "", "saved": false}
	for a in actions:
		if db.actor_name(str(a.get("target", ""))) != nm:
			continue
		match str(a.get("verb", "")):
			"kill", "escort":
				if out["gone"] == null:
					out["gone"] = int(a["year"]) if a.has("year") else null
					out["gone_era"] = str(a.get("era", ""))
					if not a.has("year"):
						out["gone"] = -(1 << 30)   # 年の記録が無い（以前のセーブ）：その時代では最初からいない
			"protect":
				out["saved"] = true
			"give":
				if str(a.get("item", "")) == "特効薬" and str(db.actors.get(nm, {}).get("death", "")) == "illness":
					out["saved"] = true
	return out


## その年、その時代の名所にこの人物がいるか（生きていて、活動している。あなたが倒していれば以後いない。救っていれば史実の没年を過ぎても）
static func actor_present(db: HistoryDB, actions: Array, a: Dictionary, era_id: String, year: int) -> bool:
	if a.is_empty() or year == 0:
		return true
	var w := actor_window(a)
	var nm := str(a.get("name", ""))
	var fate := actor_fate(db, actions, nm) if db != null and nm != "" else {"gone": null, "gone_era": "", "saved": false}
	var hi: int = w[1]
	if fate["saved"] and a.get("died") != null:
		var b: Variant = a.get("born")
		hi = maxi(hi, (int(b) + SAVED_LIFESPAN) if b != null else int(a["died"]) + SAVED_EXTRA)
	if year < int(w[0]) or year > hi:
		return false
	if fate["gone"] != null:
		var ge := HistoryDB.ERA_ORDER.find(str(fate["gone_era"]))
		var me := HistoryDB.ERA_ORDER.find(era_id)
		if ge >= 0 and ge < me:
			return false                 # 前の時代で倒れた
		if ge == me and year >= int(fate["gone"]):
			return false                 # この時代のその年に倒れた（それより前の年にはまだ生きている）
	return true


## 年齢（生年が分からなければ活動開始年を 30 歳として推定。-1 = 不明）
static func actor_age(a: Dictionary, year: int) -> int:
	if a.get("born") != null:
		return year - int(a["born"])
	if a.get("active") != null:
		return year - int(a["active"]) + 30
	return -1


## AnimeFace の年齢区分（Figures.face_opts と同じ区切り）
static func age_class(age: int) -> String:
	if age < 0:
		return ""
	return "child" if age < 13 else ("young" if age < 26 else ("adult" if age < 56 else "elder"))


## 予定のうち、その年の時点で起きるもの：予定の年に最も近い「人物がいる時点」がこの年なら
static func schedules_at(db: HistoryDB, actions: Array, a: Dictionary, era_id: String, year: int) -> Array:
	var all: Array = a.get("schedule", []).filter(func(sc): return str(sc.get("era", a.get("era", ""))) == era_id)
	if year == 0 or not has_timeline(era_id):
		return all
	var ys: Array = years(era_id).filter(func(y): return actor_present(db, [], a, era_id, int(y)))
	if not actor_present(db, actions, a, era_id, year):
		return []
	return all.filter(func(sc): return not sc.has("year") or nearest_year(era_id, int(sc["year"]), ys) == year)


static func _near(era_id: String, ev_year: int, year: int, window: int) -> bool:
	if year == 0 or not has_timeline(era_id):
		return true
	return absi(ev_year - year) <= window or nearest_year(era_id, ev_year) == year


static func battle_at(b: Dictionary, era_id: String, year: int) -> bool:
	return _near(era_id, int(b.get("year", year)), year, BATTLE_WINDOW)


static func project_at(pr: Dictionary, era_id: String, year: int) -> bool:
	return _near(era_id, int(pr.get("year", year)), year, PROJECT_WINDOW)


# ================================================================== 船・建物
## その年に港にいる大型船（data/ships の id）。時代の定義が無ければ fallback（ShipYard.ERA_SHIPS）のまま
static func ships_for(era_id: String, year: int, fallback: Array) -> Array:
	var d := data(era_id)
	if year == 0 or not d.has("ships"):
		return fallback.duplicate()
	var out: Array = []
	for s in d["ships"]:
		if (not s.has("from") or year >= int(s["from"])) and (not s.has("until") or year <= int(s["until"])):
			out.append(str(s["id"]))
	return out


static func _kinds(r: Dictionary) -> Array:
	var k: Variant = r.get("kind", [])
	return k if k is Array else [k]


## その年にまだ無い・もう無い建物の規則
static func absent_rules(era_id: String, year: int) -> Array:
	if year == 0:
		return []
	return data(era_id).get("units", []).filter(func(r): return (r.has("from") and year < int(r["from"])) or (r.has("until") and year > int(r["until"])))


## その年ちょうどの被災（明暦の大火・震災・空襲の直後）
static func ruin_rules(era_id: String, year: int) -> Array:
	return exact_point(era_id, year).get("ruin", []) if year != 0 else []


## 決まった割合の建物を選ぶ（ユニット ID の hash で固定。同じ年なら毎回同じ建物）
static func ruin_pick(unit_id: int, frac: float, salt: int) -> bool:
	return float(absi(hash(unit_id * 7919 + salt)) % 1000) / 1000.0 < frac


## あなたが前の年（またはこの年）に壊した建物で、この年にまだ壊れたままのもの
static func ruins_at(ruins: Array, year: int) -> Array:
	return ruins.filter(func(r):
		var ry := int(r.get("year", 0))
		if year != 0 and ry > year:
			return false
		var keep: int = REBUILD_YEARS.get(str(r.get("kind", "")), 1 << 20)
		return year == 0 or year - ry <= keep)


## 年の中の人々・建物・船について、その年に何が変わるかを 1 行ずつ（UI 用）
static func summary(era_id: String, year: int, ship_names: Dictionary = {}) -> PackedStringArray:
	var out: PackedStringArray = []
	var p := point_for(era_id, year)
	if p.has("desc"):
		out.append(str(p["desc"]))
	for r in absent_rules(era_id, year):
		out.append("・" + str(r.get("basis", "")))
	var sh := ships_for(era_id, year, [])
	if data(era_id).has("ships"):
		out.append("・港の船：" + ("、".join(PackedStringArray(sh.map(func(s): return str(ship_names.get(s, s))))) if not sh.is_empty() else "大型船なし"))
	return out

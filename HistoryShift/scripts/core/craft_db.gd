class_name CraftDB
extends RefCounted
## 持ち物・レシピ・工房・店・蔵のデータ（data/crafting/*.json）。静的にキャッシュして読む。

const DIR := "res://data/crafting"

static var _items: Dictionary = {}
static var _tech: Dictionary = {}
static var _recipes: Array = []
static var _stations: Dictionary = {}
static var _workshops: Array = []
static var _trade: Dictionary = {}
static var _loaded := false


static func _load_json(f: String) -> Dictionary:
	var p := DIR.path_join(f)
	if not FileAccess.file_exists(p):
		push_warning("crafting/%s がありません" % f)
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("crafting/%s を読めません" % f)
		return {}
	return d


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var it := _load_json("items.json")
	_items = it.get("items", {})
	_tech = it.get("tech", {})
	var rc := _load_json("recipes.json")
	_recipes = rc.get("recipes", [])
	_stations = rc.get("stations", {})
	_workshops = _load_json("workshops.json").get("workshops", [])
	_trade = _load_json("trade.json")


static func items() -> Dictionary:
	ensure()
	return _items


static func item(id: String) -> Dictionary:
	ensure()
	return _items.get(id, {})


static func has_item(id: String) -> bool:
	ensure()
	return _items.has(id)


static func item_name(id: String) -> String:
	return str(item(id).get("name", id))


static func item_type(id: String) -> String:
	return str(item(id).get("type", ""))


static func tech_vars(type: String) -> Dictionary:
	ensure()
	return _tech.get(type, {})


static func recipes() -> Array:
	ensure()
	return _recipes


static func recipe(id: String) -> Dictionary:
	for r in recipes():
		if str(r.get("id", "")) == id:
			return r
	return {}


static func recipes_for_station(station: String) -> Array:
	return recipes().filter(func(r): return str(r.get("station", "")) == station or (station != "" and str(r.get("station", "")) == "any"))


static func station_name(st: String) -> String:
	ensure()
	return str(_stations.get(st, st))


static func workshops() -> Array:
	ensure()
	return _workshops


static func workshop(id: String) -> Dictionary:
	for w in workshops():
		if str(w.get("id", "")) == id:
			return w
	return {}


static func workshops_for(era_id: String) -> Array:
	return workshops().filter(func(w): return era_id in w.get("eras", []))


static func shops_for(era_id: String) -> Array:
	ensure()
	return _trade.get("shops", []).filter(func(s): return era_id in s.get("eras", []))


static func loot_for(era_id: String) -> Array:
	ensure()
	return _trade.get("loot", []).filter(func(s): return era_id in s.get("eras", []))


static func drops(kind: String) -> Array:
	ensure()
	return _trade.get("drops", {}).get(kind, [])


static func era_index(era_id: String) -> int:
	return HistoryDB.ERA_ORDER.find(era_id)


## その品は今の時代には「まだない」か（時代錯誤）。戻り値は何時代ぶん未来の品か（0 = その時代にある）
static func anachronism_gap(id: String, era_id: String) -> int:
	var it := item(id)
	if it.is_empty() or era_id == "":
		return 0
	return maxi(0, era_index(str(it.get("era", "jomon_kofun"))) - era_index(era_id))


# ------------------------------------------------------------------ お金
static func currency(era_id: String) -> Dictionary:
	ensure()
	return _trade.get("currency", {}).get(era_id, {"name": "銭", "unit": "文"})


## 所持金（文）をその時代の呼び方で
static func money_text(mon: int, era_id: String) -> String:
	var unit := str(currency(era_id).get("unit", "文"))
	match unit:
		"両":
			var ryo := mon / 4000
			var rest := mon % 4000
			if ryo > 0 and rest > 0:
				return "%d両 %d文" % [ryo, rest]
			if ryo > 0:
				return "%d両" % ryo
			return "%d文" % rest
		"円":
			var yen := mon / 4000
			var sen := (mon % 4000) * 100 / 4000
			return ("%d円 %d銭" % [yen, sen]) if sen > 0 else ("%d円" % yen)
		"文分":
			return "%d文分の品" % mon
	return "%d文" % mon

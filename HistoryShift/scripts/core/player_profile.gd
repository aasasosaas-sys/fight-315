class_name PlayerProfile
extends RefCounted
## 主人公（現代の高校生）の技能・持ち物・所持金。時代をまたいで、また現代（ハブ）に戻っても持ち越す。
## user://profile.json に保存（歴史のセーブ save_v2.json とは別）。Game.profile。
##  - 技能は 0〜100（Skills）。設定「技術完全習得モード」なら level() は常に 100、レシピもすべて解禁。
##  - 持ち物は「個体」（武器：品質・耐久・装填数つき）と「束」（材料・弾・爆弾など：数と平均品質）。
##  - 貸与品（loan）はミッション開始時・「最初から武装」で一時的に持たせる品。セッション終了で返す（保存しない）。

signal changed
signal skill_up(id: String, old_level: float, new_level: float)
signal item_added(text: String)

const SAVE_PATH := "user://profile.json"
static var save_path := SAVE_PATH    # テストは別のファイルに差し替える
const START_MONEY := 1000

var skills: Dictionary = {}           # id -> float
var items: Array = []                 # 個体 [{uid, id, q, stats, dur, mag, maker, era, loan?}]
var stacks: Dictionary = {}           # id -> int
var stack_q: Dictionary = {}          # id -> 平均品質
var money := START_MONEY              # 文
var equipped := -1                    # 手にしている個体の uid（-1 = 素手）
var lessons: Dictionary = {}          # 工房 id -> 稽古の回数
var loan_stacks: Dictionary = {}      # 貸与した束の数（返すとき差し引く）
var next_uid := 1
var autosave := true
var _dirty := false
var _last_save := -100000
const SAVE_INTERVAL_MS := 3000      # 技能の細かな上昇はまとめて保存する（持ち物・お金の変化はすぐ保存）


func _init() -> void:
	reset()


func reset() -> void:
	var was := autosave
	autosave = false
	skills.clear()
	for k in Skills.ids():
		skills[k] = 0.0
	items.clear()
	stacks.clear()
	stack_q.clear()
	lessons.clear()
	loan_stacks.clear()
	money = START_MONEY
	equipped = -1
	next_uid = 1
	add("smartphone", 1, 0.5)
	autosave = was


# ------------------------------------------------------------------ モード
static func master_mode() -> bool:
	return bool(GameSettings.values.get("master_mode", false))


static func start_armed() -> bool:
	return bool(GameSettings.values.get("start_armed", false))


# ------------------------------------------------------------------ 技能
func raw_level(id: String) -> float:
	return float(skills.get(id, 0.0))


## 実際に効く技能（技術完全習得モードなら 100）
func level(id: String) -> float:
	if master_mode():
		return 100.0
	return raw_level(id)


func set_level(id: String, v: float) -> void:
	var old := raw_level(id)
	skills[id] = clampf(v, 0.0, 100.0)
	if floorf(skills[id] / 5.0) != floorf(old / 5.0) or Skills.rank(skills[id]) != Skills.rank(old):
		skill_up.emit(id, old, skills[id])
	_changed(false)


## 稽古（弟子入り）で上げる。cap = その工房で教われる上限。上がった量を返す
func train(id: String, amount: float, cap := 100.0) -> float:
	if master_mode():
		return 0.0
	var old := raw_level(id)
	if old >= cap:
		return 0.0
	var nv := minf(cap, old + Skills.gain(old, amount))
	set_level(id, nv)
	return nv - old


## 使って上げる（独学は Skills.PRACTICE_CAP まで）
func practice(id: String, amount: float) -> float:
	if not skills.has(id):
		return 0.0
	return train(id, amount, Skills.PRACTICE_CAP)


# ------------------------------------------------------------------ 持ち物
func count(id: String) -> int:
	if Crafting.is_stack(id):
		return int(stacks.get(id, 0))
	return items.filter(func(it): return str(it["id"]) == id).size()


func stack_quality(id: String) -> float:
	return float(stack_q.get(id, 0.5))


func add(id: String, n := 1, q := 0.5) -> void:
	if n <= 0 or not CraftDB.has_item(id):
		return
	if not Crafting.is_stack(id):
		for i in n:
			add_instance(Crafting.make_item(id, q))
		return
	var have := int(stacks.get(id, 0))
	stack_q[id] = (stack_quality(id) * have + q * n) / float(have + n)
	stacks[id] = have + n
	_changed()


func take(id: String, n := 1) -> bool:
	if Crafting.is_stack(id):
		if int(stacks.get(id, 0)) < n:
			return false
		stacks[id] = int(stacks[id]) - n
		if int(stacks[id]) <= 0:
			stacks.erase(id)
			stack_q.erase(id)
		_changed()
		return true
	for it in items:
		if str(it["id"]) == id:
			remove_instance(int(it["uid"]))
			return true
	return false


func add_instance(inst: Dictionary) -> Dictionary:
	var it := inst.duplicate(true)
	it["uid"] = next_uid
	next_uid += 1
	items.append(it)
	_changed()
	return it


func remove_instance(uid: int) -> Dictionary:
	for i in items.size():
		if int(items[i]["uid"]) == uid:
			var it: Dictionary = items[i]
			items.remove_at(i)
			if equipped == uid:
				equipped = -1
			_changed()
			return it
	return {}


func get_instance(uid: int) -> Dictionary:
	for it in items:
		if int(it["uid"]) == uid:
			return it
	return {}


func weapon() -> Dictionary:
	return get_instance(equipped) if equipped >= 0 else {}


func equip(uid: int) -> void:
	equipped = uid if not get_instance(uid).is_empty() else -1
	_changed()


## 手に取れる武器（素手を除く）
func weapons() -> Array:
	return items.filter(func(it): return CraftDB.item_type(str(it["id"])) in ["melee", "bow", "gun"])


## 使える武器があるか（弾のない銃・矢のない弓は数えない）
func has_usable_weapon() -> bool:
	for it in weapons():
		var b := CraftDB.item(str(it["id"]))
		var t := str(b.get("type", ""))
		if t == "melee":
			return true
		if b.get("infinite", false) or int(it.get("mag", 0)) > 0 or count(str(b.get("ammo", ""))) > 0:
			return true
	return false


func has_ranged_weapon() -> bool:
	for it in weapons():
		var b := CraftDB.item(str(it["id"]))
		if str(b.get("type", "")) in ["gun", "bow"] and (b.get("infinite", false) or int(it.get("mag", 0)) > 0 or count(str(b.get("ammo", ""))) > 0):
			return true
	return false


## 貸与（セッションの間だけ）
func lend(id: String, n := 1, q := 0.5) -> Dictionary:
	if Crafting.is_stack(id):
		add(id, n, q)
		loan_stacks[id] = int(loan_stacks.get(id, 0)) + n
		return {}
	var inst := Crafting.make_item(id, q, "貸与")
	inst["loan"] = true
	return add_instance(inst)


func return_loans() -> void:
	for it in items.duplicate():
		if it.get("loan", false):
			remove_instance(int(it["uid"]))
	for id in loan_stacks:
		var n := mini(int(loan_stacks[id]), int(stacks.get(id, 0)))
		if n > 0:
			take(id, n)
	loan_stacks.clear()
	_changed()


func add_money(mon: int) -> void:
	money = maxi(0, money + mon)
	_changed()


func spend(mon: int) -> bool:
	if money < mon:
		return false
	money -= mon
	_changed()
	return true


# ------------------------------------------------------------------ 保存
func _changed(important := true) -> void:
	changed.emit()
	if not autosave:
		return
	if important or Time.get_ticks_msec() - _last_save > SAVE_INTERVAL_MS:
		save()
	else:
		_dirty = true


## まとめて保存（セッションの終わり・ゲームの終了時）
func flush() -> void:
	if _dirty and autosave:
		save()


func to_dict() -> Dictionary:
	var its: Array = items.filter(func(it): return not it.get("loan", false))
	var st := stacks.duplicate()
	for id in loan_stacks:
		st[id] = int(st.get(id, 0)) - int(loan_stacks[id])
		if int(st[id]) <= 0:
			st.erase(id)
	var eq := equipped if not get_instance(equipped).get("loan", false) else -1
	return {"skills": skills, "items": its, "stacks": st, "stack_q": stack_q, "money": money, "equipped": eq, "lessons": lessons, "next_uid": next_uid, "v": 1}


func from_dict(d: Dictionary) -> void:
	reset()
	stacks.clear()
	stack_q.clear()
	items.clear()
	for k in d.get("skills", {}):
		if skills.has(k):
			skills[k] = clampf(float(d["skills"][k]), 0.0, 100.0)
	for it in d.get("items", []):
		if typeof(it) == TYPE_DICTIONARY and CraftDB.has_item(str(it.get("id", ""))):
			var inst: Dictionary = it
			inst["uid"] = int(inst.get("uid", 0))
			inst["mag"] = int(inst.get("mag", 0))
			inst["stats"] = Crafting.item_stats(str(inst["id"]), float(inst.get("q", 0.5)))   # 能力値はいつも式から作り直す
			items.append(inst)
	for k in d.get("stacks", {}):
		if CraftDB.has_item(str(k)):
			stacks[k] = int(d["stacks"][k])
	for k in d.get("stack_q", {}):
		stack_q[k] = float(d["stack_q"][k])
	money = int(d.get("money", START_MONEY))
	equipped = int(d.get("equipped", -1))
	lessons = d.get("lessons", {})
	next_uid = maxi(int(d.get("next_uid", 1)), 1)
	for it in items:
		next_uid = maxi(next_uid, int(it["uid"]) + 1)
	if get_instance(equipped).is_empty():
		equipped = -1


func save() -> void:
	_dirty = false
	_last_save = Time.get_ticks_msec()
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(to_dict()))


func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var was := autosave
	autosave = false
	from_dict(d)
	autosave = was
	changed.emit()
	return true


static func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# ------------------------------------------------------------------ 表示
func skills_summary(min_level := 1.0) -> Array:
	var out: Array = []
	for k in Skills.ids():
		var lv := level(k)
		if lv >= min_level:
			out.append({"id": k, "name": Skills.skill_name(k), "level": lv, "rank": Skills.rank(lv)})
	out.sort_custom(func(a, b): return a["level"] > b["level"])
	return out


func item_label(inst: Dictionary) -> String:
	var id := str(inst.get("id", ""))
	var s := CraftDB.item_name(id)
	if CraftDB.item_type(id) in ["melee", "bow", "gun"]:
		s += "（%s）" % Crafting.grade(float(inst.get("q", 0.5)))
	if inst.get("loan", false):
		s += "［貸与］"
	return s

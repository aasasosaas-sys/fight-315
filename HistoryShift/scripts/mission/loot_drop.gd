class_name LootDrop
extends Node3D
## 地面に落ちた品（倒した兵の武器・弾・銭、主人公が落とした品）。近づくと拾う（GTA 式）。
## contents: [{"id", "n", "q", "dur"(個体の耐久の割合 0〜1)}]、money: 文。

var contents: Array = []
var money := 0
var title := ""
var _t := 0.0
var _life := 120.0
var _taken := false
var _mesh: Node3D
var _arm := 0.8          # 落ちてすぐは拾わない（落とした本人がすぐ拾い直さないように）


static func spawn(parent: Node, pos: Vector3, p_contents: Array, p_money := 0, p_title := "") -> LootDrop:
	var d := LootDrop.new()
	d.contents = p_contents
	d.money = p_money
	d.title = p_title
	parent.add_child(d)
	d.global_position = pos
	return d


## 倒した兵の落とし物（Enemy._die から）。修正力（番人）は何も落とさない
static func drop_for_enemy(e: Node3D) -> LootDrop:
	if e == null or not e.is_inside_tree() or e.get("is_guardian") == true:
		return null
	var era := str(e.get("era_id"))
	var weapon := str(e.get("weapon"))
	var key := weapon
	if weapon == "bow" and era in ["jomon_kofun", "asuka_nara"]:
		key = "bow_ancient"
	elif weapon == "musket" and era == "edo":
		key = "musket_edo"
	var table := CraftDB.drops(key)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not table.is_empty():
		var pick: Array = table[rng.randi() % table.size()]
		for row in pick:
			var n := rng.randi_range(int(row[1]), int(row[2]))
			if n > 0:
				out.append({"id": str(row[0]), "n": n, "q": rng.randf_range(0.2, 0.6), "dur": rng.randf_range(0.35, 0.9)})
	var money := rng.randi_range(20, 120) * (1 + CraftDB.era_index(era))
	if e.get("is_leader") == true:
		money *= 4
	var sess = e.get_tree().get_first_node_in_group("session")
	var parent: Node = sess if sess else e.get_parent()
	return LootDrop.spawn(parent, e.global_position + Vector3.UP * 0.3, out, money, "%sの持ち物" % str(e.get("label")))


func _ready() -> void:
	add_to_group("loot_drop")
	_mesh = Node3D.new()
	add_child(_mesh)
	var main := "zeni"
	for c in contents:
		if CraftDB.item_type(str(c["id"])) in ["melee", "bow", "gun"]:
			main = str(c["id"])
			break
	if main != "zeni":
		var m := WeaponModels.build(main, float(contents[0].get("q", 0.5)))
		m.rotation_degrees = Vector3(0, 0, 90)
		_mesh.add_child(m)
	else:
		Humanoid.part(_mesh, "box", Humanoid.mat(Color(0.55, 0.42, 0.25), 0.8), Vector3.ZERO, Vector3(0.3, 0.2, 0.25))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1, 0.85, 0.5)
	glow.light_energy = 0.6
	glow.omni_range = 2.5
	glow.shadow_enabled = false
	glow.position = Vector3(0, 0.6, 0)
	add_child(glow)
	var tag := Label3D.new()
	tag.text = summary()
	tag.font_size = 32
	tag.pixel_size = 0.005
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 8
	tag.modulate = Color(1, 0.9, 0.6)
	tag.position = Vector3(0, 1.0, 0)
	add_child(tag)


func summary() -> String:
	var parts: PackedStringArray = []
	for c in contents.slice(0, 2):
		parts.append(CraftDB.item_name(str(c["id"])) + ("×%d" % int(c["n"]) if int(c["n"]) > 1 else ""))
	if contents.size() > 2:
		parts.append("ほか")
	if parts.is_empty() and money > 0:
		parts.append("銭")
	return "・".join(parts)


func _process(dt: float) -> void:
	if _taken:
		return
	_t += dt
	_arm -= dt
	_life -= dt
	if _life <= 0.0:
		queue_free()
		return
	_mesh.position.y = 0.25 + sin(_t * 2.5) * 0.06
	_mesh.rotation.y += dt * 1.2
	var w = Game.world
	if w and w.has_method("height_at") and _t < 0.5:
		global_position.y = maxf(global_position.y, w.height_at(global_position.x, global_position.z) + 0.1)
	var p = Game.player
	if _arm > 0.0 or p == null or not is_instance_valid(p) or p.get("dead") == true:
		return
	var pp: Vector3 = p.vehicle.global_position if p.in_vehicle() else p.global_position
	if pp.distance_to(global_position) < (2.2 if not p.in_vehicle() else 3.5):
		take()


## 拾う（テストからも呼べる）。持ち物に入れて HUD に知らせる
func take() -> void:
	if _taken or Game.profile == null:
		return
	_taken = true
	var lines: PackedStringArray = []
	var era := str(Game.world.get("era_id")) if Game.world and "era_id" in Game.world else ""
	for c in contents:
		var id := str(c["id"])
		var n := int(c["n"])
		var q := float(c.get("q", 0.5))
		if Crafting.is_stack(id):
			Game.profile.add(id, n, q)
			lines.append("%s ×%d" % [CraftDB.item_name(id), n])
		else:
			for i in n:
				var inst := Crafting.make_item(id, q, "", era)
				inst["dur"] = float(inst["dur"]) * float(c.get("dur", 1.0))
				if CraftDB.item_type(id) == "gun":
					inst["mag"] = int(inst["stats"].get("mag", 1)) if randf() < 0.5 else 0
				var it: Dictionary = Game.profile.add_instance(inst)
				lines.append(Game.profile.item_label(it))
	if money > 0:
		Game.profile.add_money(money)
		lines.append(CraftDB.money_text(money, era))
	Sfx.play(get_tree(), Sfx.pickup(), -6.0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast") and not lines.is_empty():
		hud.toast("拾った：" + "、".join(lines), 3.0)
	queue_free()

class_name CraftStation
extends Node3D
## 世界に置く「工房（弟子入り・製作）」「店」「蔵・武器庫」。CraftWorld が名所のそばに置く。
## kind: workshop / shop / loot。def は data/crafting の該当データ。

var kind := "workshop"
var def: Dictionary = {}
var display_name := ""
var landmark := ""
var looted := false
var teacher: Humanoid = null


static func spawn(parent: Node, pos: Vector3, yaw: float, p_kind: String, p_def: Dictionary, p_landmark: String) -> CraftStation:
	var s := CraftStation.new()
	s.kind = p_kind
	s.def = p_def
	s.landmark = p_landmark
	s.display_name = str(p_def.get("name", ""))
	parent.add_child(s)
	s.global_position = pos
	s.rotation.y = yaw
	return s


func _ready() -> void:
	add_to_group("craft_station")
	var wood := Humanoid.mat(Color(0.45, 0.32, 0.2), 0.8)
	var dark := Humanoid.mat(Color(0.16, 0.14, 0.13), 0.7)
	var white := Humanoid.mat(Color(0.9, 0.88, 0.82), 0.9)
	match kind:
		"workshop":
			# 看板・作業台・道具
			Humanoid.part(self, "box", wood, Vector3(-1.6, 1.0, 0), Vector3(0.12, 2.0, 0.12))
			Humanoid.part(self, "box", Humanoid.mat(Color(0.2, 0.15, 0.1), 0.7), Vector3(-1.6, 2.0, 0), Vector3(1.0, 0.55, 0.06))
			var sts: Array = def.get("stations", [])
			if "forge" in sts or "gunsmith" in sts:
				Humanoid.part(self, "box", dark, Vector3(0.8, 0.45, 0.6), Vector3(0.6, 0.3, 0.3))       # 金床
				Humanoid.part(self, "box", dark, Vector3(0.8, 0.2, 0.6), Vector3(0.3, 0.4, 0.25))
				Humanoid.part(self, "box", Humanoid.mat(Color(0.5, 0.35, 0.3), 0.9), Vector3(1.9, 0.6, 0.0), Vector3(1.0, 1.2, 1.0))  # 火床
				var fire := OmniLight3D.new()
				fire.light_color = Color(1.0, 0.55, 0.2)
				fire.light_energy = 1.4
				fire.omni_range = 5.0
				fire.position = Vector3(1.9, 1.4, 0)
				add_child(fire)
			elif "machine" in sts:
				Humanoid.part(self, "box", Humanoid.mat(Color(0.3, 0.35, 0.32), 0.5, 0.6), Vector3(1.0, 0.6, 0.4), Vector3(1.6, 0.9, 0.6))   # 旋盤
				Humanoid.part(self, "cyl", dark, Vector3(1.0, 1.15, 0.4), Vector3(0.25, 0.8, 0.25), Vector3(0, 0, 90))
			elif "lab" in sts or "powder" in sts:
				Humanoid.part(self, "box", wood, Vector3(1.0, 0.45, 0.4), Vector3(1.6, 0.9, 0.7))
				for i in 3:
					Humanoid.part(self, "cyl", Humanoid.mat(Color(0.6, 0.75, 0.8), 0.1, 0.2), Vector3(0.5 + i * 0.4, 1.0, 0.4), Vector3(0.12, 0.25, 0.12))
			else:
				Humanoid.part(self, "box", wood, Vector3(1.0, 0.4, 0.4), Vector3(1.4, 0.1, 0.8))
				Humanoid.part(self, "box", white, Vector3(1.0, 0.3, 0.4), Vector3(1.2, 0.5, 0.6))
			var outfit := Humanoid.Outfit.COMMONER
			var era := str(Game.world.get("era_id")) if Game.world and "era_id" in Game.world else ""
			if str(def.get("id", "")) in ["dojo", "yabusame", "teppo_shuren"]:
				outfit = Humanoid.Outfit.SAMURAI
			elif str(def.get("id", "")) in ["hikou", "shooting_range", "hohei_kosho"]:
				outfit = Humanoid.Outfit.SOLDIER
			elif str(def.get("id", "")) in ["terakoya", "miyadaiku"] and era in ["asuka_nara", "heian"]:
				outfit = Humanoid.Outfit.MONK
			elif era in ["meiji_taisho", "showa"]:
				outfit = Humanoid.Outfit.WESTERN
			elif era == "jomon_kofun":
				outfit = Humanoid.Outfit.ANCIENT
			teacher = Humanoid.build_streamed(outfit, absi(hash(str(def.get("id", "")))), false, 0)
			teacher.position = Vector3(0.2, 0, -0.9)
			add_child(teacher)
		"shop":
			# 屋台（棚と暖簾）
			Humanoid.part(self, "box", wood, Vector3(0, 0.5, 0), Vector3(2.4, 1.0, 1.0))
			Humanoid.part(self, "box", Humanoid.mat(Color(0.2, 0.25, 0.5), 0.9), Vector3(0, 2.2, 0.2), Vector3(2.6, 0.5, 0.05))
			for x in [-1.2, 1.2]:
				Humanoid.part(self, "box", wood, Vector3(x, 1.2, 0.2), Vector3(0.1, 2.4, 0.1))
			teacher = Humanoid.build_streamed(Humanoid.Outfit.COMMONER, absi(hash(display_name)), false)
			teacher.position = Vector3(0, 0, -0.9)
			add_child(teacher)
		"loot":
			# 蔵・武器庫の扉（白壁の小さな蔵）
			Humanoid.part(self, "box", white, Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 2.2))
			Humanoid.part(self, "box", dark, Vector3(0, 2.6, 0), Vector3(2.9, 0.4, 2.7))
			Humanoid.part(self, "box", Humanoid.mat(Color(0.3, 0.22, 0.15), 0.6, 0.3), Vector3(0, 0.9, 1.12), Vector3(1.0, 1.6, 0.06))
			var cs := StaticBody3D.new()
			cs.collision_layer = Game.COLLISION_WORLD
			var sh := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(2.4, 2.4, 2.2)
			sh.shape = bx
			sh.position = Vector3(0, 1.2, 0)
			cs.add_child(sh)
			add_child(cs)
	var tag := Label3D.new()
	tag.text = display_name + {"workshop": "\n（弟子入り・製作）", "shop": "\n（売り買い）", "loot": ""}.get(kind, "")
	tag.font = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	tag.font_size = 44
	tag.pixel_size = 0.006
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 10
	tag.modulate = {"workshop": Color(1.0, 0.85, 0.45), "shop": Color(0.6, 0.95, 1.0), "loot": Color(1.0, 0.6, 0.5)}.get(kind, Color.WHITE)
	tag.position = Vector3(0, 3.3, 0)
	add_child(tag)


## E で開くときの案内
func prompt() -> String:
	match kind:
		"workshop":
			return "E：%s（弟子入り・製作・修理）" % display_name
		"shop":
			return "E：%s（売り買い）" % display_name
		"loot":
			return ("E：%sを探る（盗み：手配度が上がる）" % display_name) if not looted else "%s（もう空っぽだ）" % display_name
	return ""


## 蔵の中身（一度だけ）
func roll_loot() -> Array:
	var out: Array = []
	if looted:
		return out
	looted = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for row in def.get("items", []):
		var n := rng.randi_range(int(row[1]), int(row[2]))
		if n > 0:
			out.append({"id": str(row[0]), "n": n, "q": rng.randf_range(0.35, 0.75)})
	return out

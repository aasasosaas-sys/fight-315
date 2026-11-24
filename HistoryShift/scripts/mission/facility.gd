class_name Facility
extends CraftStation
## 主人公が過去に建てた施設（data/crafting/buildings.json）。rec は PlayerProfile.buildings の 1 件（保存される）。
## 生産：cycle 秒ごとに inputs（蔵 rec.stock に入れた原料・燃料）を使って outputs / money_out を蔵にためる。
## 効率 = 働き手の充足 × (0.5 + 0.7×職人の腕) × 動力（水力 0.7・蒸気 1.0）× 規模。蒸気は 1 回ごとに石炭 1。
## 離れていた間の分は、次に来たとき最大 30 回ぶんまとめて生産する（Time.get_unix_time_from_system）。
## 動かすたびに必要な知識の習熟が上がる（Knowledge.CAP_RUN まで）。

var rec: Dictionary = {}
var bdef: Dictionary = {}
var running := false
var _smoke: Array = []
var _wheel: Node3D = null
var _train: Node3D = null
var _line_a := Vector3.ZERO
var _line_b := Vector3.ZERO
var _train_t := 0.0
var _lamps: Array = []

const MAX_STOCK := 300
const OFFLINE_CYCLES := 30


static func spawn_rec(parent: Node, p_rec: Dictionary) -> Facility:
	var f := Facility.new()
	f.rec = p_rec
	f.bdef = Knowledge.building(str(p_rec.get("type", "")))
	f.kind = "factory"
	f.landmark = str(p_rec.get("at", ""))
	f.display_name = str(f.bdef.get("name", "施設"))
	var d := f.bdef.duplicate()
	d["stations"] = f.bdef.get("station", [])
	f.def = d
	parent.add_child(f)
	var pv: Array = p_rec.get("pos", [0, 0, 0])
	f.global_position = Vector3(float(pv[0]), float(pv[1]), float(pv[2]))
	f.rotation.y = float(p_rec.get("yaw", 0.0))
	f.catch_up()
	return f


func _ready() -> void:
	add_to_group("craft_station")
	add_to_group("facility")
	_build_visual(str(bdef.get("visual", "workshop")))
	var tag := Label3D.new()
	tag.text = display_name + ("（規模 %d）" % int(rec.get("scale", 1)) if int(rec.get("scale", 1)) > 1 else "") + "\n（あなたの施設）"
	tag.font = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	tag.font_size = 44
	tag.pixel_size = 0.007
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 10
	tag.modulate = Color(0.6, 1.0, 0.7)
	tag.position = Vector3(0, 7.5, 0)
	add_child(tag)


func prompt() -> String:
	return "E：%s（あなたの施設：働き手・原料・受け取り・拡張）" % display_name


# ------------------------------------------------------------------ 生産
func needed_workers() -> int:
	return int(bdef.get("workers", 1))


func _has_inputs() -> bool:
	var st: Dictionary = rec.get("stock", {})
	for k in bdef.get("inputs", {}):
		if int(st.get(k, 0)) < int(bdef["inputs"][k]):
			return false
	if str(rec.get("power", "none")) == "steam" and int(st.get("sekitan", 0)) < 1:
		return false
	return true


func status_text() -> String:
	if int(rec.get("workers", 0)) <= 0:
		return "止まっている（働き手がいない）"
	if not _has_inputs():
		var need: PackedStringArray = []
		for k in bdef.get("inputs", {}):
			need.append("%s %d" % [CraftDB.item_name(k), int(bdef["inputs"][k])])
		if str(rec.get("power", "")) == "steam":
			need.append("石炭 1")
		return "止まっている（原料・燃料が足りない：1回に " + "、".join(need) + "）"
	return "稼働中　効率 %d%%" % roundi(Knowledge.efficiency(rec) * 100)


## 1 回生産する（成功したら true）
func produce_once() -> bool:
	if int(rec.get("workers", 0)) <= 0 or not _has_inputs():
		return false
	var st: Dictionary = rec.get("stock", {})
	for k in bdef.get("inputs", {}):
		st[k] = int(st.get(k, 0)) - int(bdef["inputs"][k])
	if str(rec.get("power", "none")) == "steam":
		st["sekitan"] = int(st.get("sekitan", 0)) - 1
	var outs: Dictionary = (bdef.get("outputs", {}) as Dictionary).duplicate()
	var bonus: Dictionary = bdef.get("bonus", {})
	var prof: PlayerProfile = Game.profile
	if bonus.has("outputs") and prof and Knowledge.mastery(prof, str(bonus.get("know", ""))) >= float(bonus.get("need", 30)):
		for k in bonus["outputs"]:
			outs[k] = int(outs.get(k, 0)) + int(bonus["outputs"][k])
	for k in outs:
		st["out_" + k] = mini(MAX_STOCK, int(st.get("out_" + k, 0)) + int(outs[k]))
	rec["money"] = mini(MAX_STOCK * 10000, int(rec.get("money", 0)) + int(bdef.get("money_out", 0)))
	rec["stock"] = st
	rec["made"] = int(rec.get("made", 0)) + 1
	if prof:
		for k in bdef.get("know", {}):
			Knowledge.train(prof, k, 0.25, Knowledge.CAP_RUN)
	run_milestone()
	return true


## 稼働が軌道に乗った（生産 Knowledge.RUN_MILESTONE 回）：歴史にもう一度知らせる。自由探索の外なら次の機会に
func run_milestone() -> Dictionary:
	if int(rec.get("made", 0)) < Knowledge.RUN_MILESTONE or rec.get("run_told", false):
		return {}
	if Game.chaos == null or not Game.chaos.is_active() or Game.profile == null:
		return {}
	rec["run_told"] = true
	var sc := int(rec.get("scale", 1))
	var hit: Dictionary = Game.chaos.act("industry", str(rec.get("type", "")), {"landmark": str(rec.get("at", "")), "scale": sc, "stage": "run",
		"mult": 0.5 * Knowledge.industry_scale(Game.profile, rec) / (1.0 + 0.5 * (sc - 1))})
	if is_inside_tree():
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("%sが軌道に乗った。まねをする者が現れ始めた" % display_name, 4.0)
	return hit


## できた品を問屋に卸す（時代の需要・売れ残りで値が変わる）。[[id, n, 稼ぎ]...]
func sell_outputs(prof: PlayerProfile, era_id: String) -> Array:
	var sold: Array = []
	var st: Dictionary = rec.get("stock", {})
	for k in st.keys():
		if str(k).begins_with("out_") and int(st[k]) > 0:
			var id := str(k).substr(4)
			var n := int(st[k])
			var mon := Knowledge.market_sell(prof, id, n, era_id)
			prof.add_money(mon)
			prof.practice("rhetoric", 0.05 * n)
			sold.append([id, n, mon])
			st[k] = 0
	rec["stock"] = st
	return sold


func catch_up() -> void:
	var now := Time.get_unix_time_from_system()
	var last := float(rec.get("last", now))
	var cyc := float(bdef.get("cycle", 30)) / maxf(0.05, Knowledge.efficiency(rec))
	var n := mini(OFFLINE_CYCLES, int((now - last) / maxf(1.0, cyc)))
	for i in n:
		if not produce_once():
			break
	rec["last"] = now


func _process(dt: float) -> void:
	var eff := Knowledge.efficiency(rec)
	running = eff > 0.0 and _has_inputs()
	if running:
		rec["prog"] = float(rec.get("prog", 0.0)) + dt * eff / float(bdef.get("cycle", 30))
		if float(rec["prog"]) >= 1.0:
			rec["prog"] = float(rec["prog"]) - 1.0
			produce_once()
		rec["last"] = Time.get_unix_time_from_system()
	for s in _smoke:
		if is_instance_valid(s):
			(s as CPUParticles3D).emitting = running
	if _wheel and running:
		_wheel.rotation.x += dt * 1.2
	for l in _lamps:
		if is_instance_valid(l):
			(l as OmniLight3D).visible = running
	if _train and running:
		_train_t += dt * 0.06
		var k := 0.5 - 0.5 * cos(_train_t * TAU)
		var p := _line_a.lerp(_line_b, k)
		var w = Game.world
		if w and w.has_method("height_at"):
			p.y = w.height_at(p.x, p.z) + 0.3
		_train.global_position = p
		var dir := (_line_b - _line_a) * (1.0 if sin(_train_t * TAU) >= 0.0 else -1.0)
		if Vector2(dir.x, dir.z).length() > 0.1:
			_train.global_rotation.y = atan2(-dir.x, -dir.z)


## 蔵の中身を持ち物へ
func collect(prof: PlayerProfile) -> Array:
	var got: Array = []
	var st: Dictionary = rec.get("stock", {})
	for k in st.keys():
		if str(k).begins_with("out_") and int(st[k]) > 0:
			var id := str(k).substr(4)
			prof.add(id, int(st[k]), 0.4 + 0.5 * clampf(float(rec.get("skill", 10)) / 100.0, 0.0, 1.0))
			got.append([id, int(st[k])])
			st[k] = 0
	var m := int(rec.get("money", 0))
	if m > 0:
		prof.add_money(m)
		got.append(["money", m])
		rec["money"] = 0
	return got


## 持ち物の原料・燃料を入れる
func deposit(prof: PlayerProfile) -> Array:
	var put: Array = []
	var st: Dictionary = rec.get("stock", {})
	var ids: Array = (bdef.get("inputs", {}) as Dictionary).keys()
	if str(rec.get("power", "")) == "steam" and not ("sekitan" in ids):
		ids.append("sekitan")
	for id in ids:
		var n := prof.count(id) - int(prof.loan_stacks.get(id, 0))
		if n > 0:
			prof.take(id, n)
			st[id] = int(st.get(id, 0)) + n
			put.append([id, n])
	rec["stock"] = st
	return put


# ------------------------------------------------------------------ 見た目
func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	return Humanoid.mat(c, rough)


func _house(size: Vector3, wall: Color, roof: Color, at := Vector3.ZERO) -> void:
	Humanoid.part(self, "box", _mat(wall), at + Vector3(0, size.y * 0.5, 0), size)
	Humanoid.part(self, "box", _mat(roof), at + Vector3(0, size.y + 0.25, 0), Vector3(size.x + 0.8, 0.5, size.z + 0.8))
	var body := StaticBody3D.new()
	body.collision_layer = Game.COLLISION_WORLD
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = at + Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	add_child(body)


func _chimney(at: Vector3, h: float, r := 0.6, col := Color(0.55, 0.25, 0.18)) -> void:
	Humanoid.part(self, "cyl", _mat(col), at + Vector3(0, h * 0.5, 0), Vector3(r * 2, h, r * 2))
	var sm := CPUParticles3D.new()
	sm.amount = 26
	sm.lifetime = 4.0
	sm.direction = Vector3.UP
	sm.spread = 12.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 2.5
	sm.gravity = Vector3(0.6, 0.4, 0)
	sm.scale_amount_min = 1.2
	sm.scale_amount_max = 2.6
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 0.3, 0.32, 0.7))
	g.set_color(1, Color(0.5, 0.5, 0.52, 0.0))
	sm.color_ramp = g
	var q := QuadMesh.new()
	q.material = Effects.particle_mat(Color.WHITE, false)
	sm.mesh = q
	sm.position = at + Vector3(0, h + 0.3, 0)
	sm.emitting = false
	add_child(sm)
	_smoke.append(sm)


const BRICK := Color(0.62, 0.3, 0.22)
const WOOD := Color(0.5, 0.36, 0.22)
const DARK := Color(0.2, 0.18, 0.17)
const ROOF := Color(0.25, 0.24, 0.26)


func _build_visual(v: String) -> void:
	match v:
		"watermill":
			_house(Vector3(4, 3, 4), WOOD, Color(0.4, 0.35, 0.25))
			_wheel = Node3D.new()
			_wheel.position = Vector3(2.4, 1.8, 0)
			add_child(_wheel)
			Humanoid.part(_wheel, "cyl", _mat(WOOD), Vector3.ZERO, Vector3(3.4, 0.4, 3.4), Vector3(0, 0, 90))
			for i in 4:
				Humanoid.part(_wheel, "box", _mat(WOOD.darkened(0.3)), Vector3.ZERO, Vector3(0.45, 3.6, 0.2), Vector3(i * 45.0, 0, 0))
		"workshop", "school":
			_house(Vector3(7, 3.4, 5), WOOD if v == "workshop" else Color(0.85, 0.82, 0.74), ROOF)
			if v == "workshop":
				_chimney(Vector3(2.6, 3.4, 1.5), 3.0, 0.35, DARK)
			else:
				Humanoid.part(self, "box", _mat(Color(0.95, 0.95, 0.9)), Vector3(0, 2.6, 2.6), Vector3(2.4, 0.6, 0.06))
		"tatara":
			_house(Vector3(9, 4, 7), WOOD.darkened(0.2), Color(0.3, 0.27, 0.22))
			_chimney(Vector3(0, 4.5, 0), 1.5, 0.8, DARK)
		"mine":
			Humanoid.part(self, "box", _mat(Color(0.35, 0.3, 0.26)), Vector3(0, 2.5, -2), Vector3(9, 5, 5))
			Humanoid.part(self, "box", _mat(Color(0.05, 0.05, 0.05)), Vector3(0, 1.4, 0.55), Vector3(2.6, 2.8, 0.2))
			for x in [-1.4, 1.4]:
				Humanoid.part(self, "box", _mat(WOOD), Vector3(x, 1.5, 0.7), Vector3(0.3, 3.0, 0.3))
			Humanoid.part(self, "box", _mat(WOOD), Vector3(0, 3.0, 0.7), Vector3(3.2, 0.3, 0.3))
			Humanoid.part(self, "sphere", _mat(Color(0.08, 0.08, 0.09)), Vector3(4, 0.6, 2.5), Vector3(3, 1.2, 3))   # 石炭の山
			_chimney(Vector3(-4, 0, 2), 6.0, 0.4, DARK)
		"reverb":
			_house(Vector3(8, 4, 6), BRICK, BRICK.darkened(0.3))
			_chimney(Vector3(-2.2, 4, 0), 12.0, 0.9, BRICK)
			_chimney(Vector3(2.2, 4, 0), 12.0, 0.9, BRICK)
		"blast":
			Humanoid.part(self, "cyl", _mat(BRICK), Vector3(0, 6, 0), Vector3(6, 12, 6))
			Humanoid.part(self, "cyl", _mat(DARK), Vector3(0, 12.6, 0), Vector3(4, 1.2, 4))
			_house(Vector3(8, 3, 6), WOOD, ROOF, Vector3(7, 0, 0))
			_chimney(Vector3(-5, 0, 0), 16.0, 0.8, BRICK)
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.5, 0.15)
			glow.light_energy = 2.5
			glow.omni_range = 9.0
			glow.position = Vector3(0, 1.5, 3.4)
			add_child(glow)
			_lamps.append(glow)
		"factory", "mill":
			var ln := 16.0 if v == "mill" else 12.0
			Humanoid.part(self, "box", _mat(BRICK), Vector3(0, 2.5, 0), Vector3(ln, 5, 8))
			var body := StaticBody3D.new()
			body.collision_layer = Game.COLLISION_WORLD
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(ln, 5, 8)
			cs.shape = bx
			cs.position = Vector3(0, 2.5, 0)
			body.add_child(cs)
			add_child(body)
			var n := int(ln / 3.0)
			for i in n:
				# のこぎり屋根
				Humanoid.part(self, "box", _mat(ROOF), Vector3(-ln * 0.5 + 1.5 + i * 3.0, 5.6, 0), Vector3(3.0, 0.2, 8.2), Vector3(0, 0, 25))
				Humanoid.part(self, "box", _mat(Color(0.7, 0.8, 0.85), 0.2), Vector3(-ln * 0.5 + 1.5 + i * 3.0, 2.8, 4.02), Vector3(1.4, 1.6, 0.05))
			_chimney(Vector3(ln * 0.5 + 2.0, 0, 0), 20.0, 0.9, BRICK)
		"chemical":
			_house(Vector3(8, 4, 6), BRICK, ROOF)
			for i in 3:
				Humanoid.part(self, "cyl", _mat(Color(0.6, 0.62, 0.6), 0.4), Vector3(-3 + i * 3, 2.5, 5.5), Vector3(2.2, 5, 2.2))
			_chimney(Vector3(4.5, 0, -2), 14.0, 0.6, BRICK)
		"shipyard":
			Humanoid.part(self, "box", _mat(WOOD), Vector3(0, 0.6, 0), Vector3(6, 1.2, 22), Vector3(-4, 0, 0))
			for z in [-8.0, 8.0]:
				for x in [-4.0, 4.0]:
					Humanoid.part(self, "box", _mat(DARK), Vector3(x, 5, z), Vector3(0.4, 10, 0.4))
				Humanoid.part(self, "box", _mat(DARK), Vector3(0, 10, z), Vector3(8.8, 0.4, 0.4))
			Humanoid.part(self, "box", _mat(WOOD.darkened(0.2)), Vector3(0, 2.4, 0), Vector3(3.2, 2.4, 14))   # 建造中の船体
			_house(Vector3(6, 3, 5), WOOD, ROOF, Vector3(9, 0, 0))
		"power":
			_house(Vector3(10, 6, 8), BRICK, ROOF)
			_chimney(Vector3(6, 0, 0), 18.0, 0.8, BRICK)
			var w = Game.world
			var pts: Array = w.street_points() if w and w.has_method("street_points") else []
			for i in mini(8, pts.size()):
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.92, 0.7)
				l.light_energy = 1.6
				l.omni_range = 10.0
				get_parent().add_child.call_deferred(l)
				l.set_deferred("global_position", (pts[(i * 7) % pts.size()] as Vector3) + Vector3.UP * 4.0)
				_lamps.append(l)
		"bank":
			_house(Vector3(9, 5, 7), Color(0.82, 0.8, 0.75), Color(0.45, 0.47, 0.5))
			for i in 4:
				Humanoid.part(self, "cyl", _mat(Color(0.92, 0.9, 0.85)), Vector3(-3 + i * 2, 2.5, 3.8), Vector3(0.6, 5, 0.6))
		"railway", "telegraph":
			_build_line(v)
		_:
			_house(Vector3(6, 3, 5), WOOD, ROOF)


## 鉄道・電信：rec.pos から rec.to の名所まで
func _build_line(v: String) -> void:
	var w = Game.world
	var to := str(rec.get("to", ""))
	if w == null or to == "":
		_house(Vector3(4, 3, 4), WOOD, ROOF)
		return
	_line_a = global_position
	_line_b = (w.landmark_pos(to) as Vector3) + Vector3(8, 0, 8)
	var d := _line_b - _line_a
	var flat := Vector3(d.x, 0, d.z)
	var length := flat.length()
	var dir := flat.normalized()
	var right := dir.cross(Vector3.UP)
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	if v == "railway":
		# 枕木（MultiMesh）とレール（区間ごとの細い箱）
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 0.15, 0.3)
		bm.material = _mat(Color(0.32, 0.24, 0.18))
		mm.mesh = bm
		var n := int(length / 1.5)
		mm.instance_count = n
		for i in n:
			var p := _line_a + dir * (i * 1.5)
			p.y = w.height_at(p.x, p.z) + 0.08
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
		var seg := 6.0
		var m := int(length / seg)
		for i in m:
			var a := _line_a + dir * (i * seg)
			var b := _line_a + dir * ((i + 1) * seg)
			a.y = w.height_at(a.x, a.z) + 0.25
			b.y = w.height_at(b.x, b.z) + 0.25
			for s in [-0.72, 0.72]:
				var mi := MeshInstance3D.new()
				var rb := BoxMesh.new()
				rb.size = Vector3(0.1, 0.12, a.distance_to(b))
				mi.mesh = rb
				mi.material_override = Humanoid.mat(Color(0.4, 0.38, 0.36), 0.3, 0.8)
				root.add_child(mi)
				mi.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5 + right * s)
		# 機関車
		_train = Node3D.new()
		_train.top_level = true
		add_child(_train)
		Humanoid.part(_train, "cyl", _mat(Color(0.12, 0.12, 0.13), 0.4), Vector3(0, 1.6, -0.5), Vector3(1.6, 4.0, 1.6), Vector3(90, 0, 0))
		Humanoid.part(_train, "box", _mat(Color(0.15, 0.15, 0.16)), Vector3(0, 1.9, 2.2), Vector3(2.2, 2.4, 2.0))
		Humanoid.part(_train, "box", _mat(Color(0.5, 0.12, 0.1)), Vector3(0, 0.6, 0.5), Vector3(2.4, 0.5, 6.5))
		Humanoid.part(_train, "cyl", _mat(Color(0.1, 0.1, 0.1)), Vector3(0, 3.2, -2.0), Vector3(0.6, 1.4, 0.6))
		var sm := CPUParticles3D.new()
		sm.amount = 20
		sm.lifetime = 2.5
		sm.direction = Vector3.UP
		sm.initial_velocity_min = 2.0
		sm.initial_velocity_max = 3.0
		sm.scale_amount_min = 0.8
		sm.scale_amount_max = 1.6
		var q := QuadMesh.new()
		q.material = Effects.particle_mat(Color(0.85, 0.85, 0.85, 0.6), false)
		sm.mesh = q
		sm.local_coords = false
		sm.position = Vector3(0, 4.0, -2.0)
		_train.add_child(sm)
		_smoke.append(sm)
		_train.global_position = _line_a
		_house(Vector3(6, 3, 4), BRICK, ROOF, Vector3(0, 0, 6))   # 駅舎
	else:
		var n2 := int(length / 25.0) + 1
		var prev := Vector3.ZERO
		for i in n2 + 1:
			var p := _line_a + dir * minf(length, i * 25.0)
			p.y = w.height_at(p.x, p.z)
			var pole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.1
			cm.bottom_radius = 0.14
			cm.height = 6.0
			pole.mesh = cm
			pole.material_override = _mat(WOOD)
			root.add_child(pole)
			pole.global_position = p + Vector3.UP * 3.0
			var top := p + Vector3.UP * 5.8
			if i > 0:
				var wi := MeshInstance3D.new()
				var wb := BoxMesh.new()
				wb.size = Vector3(0.03, 0.03, prev.distance_to(top))
				wi.mesh = wb
				wi.material_override = _mat(Color(0.1, 0.1, 0.1))
				root.add_child(wi)
				wi.global_transform = Transform3D(Basis.looking_at((top - prev).normalized(), Vector3.UP), (prev + top) * 0.5)
			prev = top
		_house(Vector3(4, 3, 4), Color(0.8, 0.78, 0.72), ROOF, Vector3(0, 0, 5))   # 電信局

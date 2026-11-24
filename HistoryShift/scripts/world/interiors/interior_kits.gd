class_name InteriorKits
extends RefCounted
## 時代×用途の内装キット。InteriorBuilder の局所座標（建物の足元中心・+Z が正面）で組む。
## 典拠は data/interiors/kits.json の basis に記す（復元建物・現存建築・博物館の展示など）。
## 方針: 外観と同じ寸法の中に、その時代の床（土間・板の間・置き畳・畳・寄木・リノリウム）・建具・調度・灯りを置く。

const WOOD_DARK := Color(0.42, 0.3, 0.22)
const VERM := Color(0.8, 0.27, 0.15)
const GOLDC := Color(1.0, 0.82, 0.42)


static func build(b: InteriorBuilder) -> void:
	var t := String(b.def.get("type", ""))
	match t:
		"pit": _pit(b)
		"takayuka": _takayuka(b)
		"raised_hall": _raised_hall(b)
		"shinden": _shinden(b)
		"palace", "daigokuden": _palace(b, t == "daigokuden")
		"temple": _temple(b)
		"kinkaku": _kinkaku(b)
		"pagoda": _pagoda(b)
		"shrine": _shrine(b)
		"shoin", "goten": _shoin(b, t == "goten")
		"machiya": _machiya(b)
		"nagaya": _nagaya(b)
		"chaya": _chaya(b)
		"minka", "farmhouse": _minka(b, t == "farmhouse")
		"kura": _kura(b)
		"storehouse": _storehouse(b)
		"castle": _castle(b)
		"yagura": _yagura(b)
		_:
			InteriorKitsModern.build(b, t)


## 時代の標準の灯り
static func era_lamp(era: String) -> String:
	match era:
		"jomon_kofun": return "toumyo"
		"asuka_nara", "heian", "kamakura_muromachi": return "toudai"
		"sengoku": return "shokudai"
		"edo": return "andon"
		"meiji_taisho": return "lamp"
	return "bulb"


static func _door_in(b: InteriorBuilder, k := 0, depth := 1.2) -> Vector3:
	var ds: Array = b.def.get("doors", [])
	if ds.is_empty():
		return b.fc(0)
	var d: Dictionary = ds[k]
	return (d["p"] as Vector3) - (d["n"] as Vector3) * depth


# ================================================================ 縄文〜古墳
static func _pit(b: InteriorBuilder) -> void:
	var f: Dictionary = b.floors[0]
	var y := b.fy(0)
	var rin: float = f.get("round", 2.4)
	b.structure()
	b.cyl("earth", Vector3(0, y - 0.01, 0), rin + 0.4, rin + 0.4, 0.025, 16, Color(0.6, 0.48, 0.36))
	# 主柱 4 本と桁
	var pr := rin * 0.55
	var tops: Array = []
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := Vector3(cos(a) * pr, y, sin(a) * pr)
		b.cyl("wood", p, 0.11, 0.1, 2.5, 7, Color(0.55, 0.4, 0.3), true)
		tops.append(p + Vector3(0, 2.45, 0))
	for k in 4:
		b.rod("wood", tops[k], tops[(k + 1) % 4], 0.07, Color(0.5, 0.36, 0.26), 5)
		# 垂木
		var o: Vector3 = tops[k] * Vector3(1, 0, 1)
		b.rod("wood", tops[k], o.normalized() * (rin + 0.6) + Vector3(0, y + 0.2, 0), 0.04, Color(0.45, 0.33, 0.24), 4)
	# 石囲炉（中央やや奥）
	var hp := Vector3(0, y, -0.25)
	for k in 9:
		var a := TAU * k / 9.0
		b.sph("stonewall", hp + Vector3(cos(a) * 0.42, 0.06, sin(a) * 0.42), 0.12, Color(0.6, 0.58, 0.55), 6, 4, Vector3(1, 0.6, 1))
	b.sph("emissive", hp + Vector3(0, 0.05, 0), 0.16, Color(1.0, 0.42, 0.12), 6, 3, Vector3(1.6, 0.5, 1.6))
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		b.rod("darkwood", hp + Vector3(cos(a) * 0.35, 0.05, sin(a) * 0.35), hp + Vector3(0, 0.12, 0), 0.04, Color(0.25, 0.18, 0.12), 4)
	b.fire_pts.append(hp + Vector3(0, 0.2, 0))
	b.lamp("hearth", hp)
	# 炉の上の火棚（燻製の魚・木の実）
	b.box("bamboo", hp + Vector3(0, 1.9, 0), Vector3(1.1, 0.04, 1.1), Color(0.5, 0.42, 0.28))
	for k in 4:
		b.box("flat", hp + Vector3(-0.3 + k * 0.2, 1.75, 0.1), Vector3(0.05, 0.25, 0.08), Color(0.55, 0.42, 0.3))
	# 寝床の莚・毛皮、土器（深鉢・浅鉢）、石皿と磨石
	for k in 3:
		var a := PI + 0.6 + k * 0.9
		var p := Vector3(cos(a) * rin * 0.72, y, sin(a) * rin * 0.72)
		b.box("tatami", p + Vector3(0, 0.02, 0), Vector3(1.6, 0.03, 0.8), Color(0.72, 0.6, 0.38), -a + PI * 0.5)
		if k == 1:
			b.box("cloth", p + Vector3(0, 0.05, 0), Vector3(0.9, 0.03, 0.6), Color(0.45, 0.32, 0.22), -a + PI * 0.5 + 0.3)
	var pot := Color(0.62, 0.42, 0.3)
	for k in 3:
		var a := 0.3 + k * 0.42
		var p := Vector3(cos(a) * rin * 0.75, y, sin(a) * rin * 0.75)
		b.cyl("earth", p, 0.12, 0.2, 0.42, 10, pot)
		b.cyl("earth", p + Vector3(0, 0.42, 0), 0.2, 0.24, 0.08, 10, pot.darkened(0.15))
	b.cyl("stonewall", Vector3(-rin * 0.3, y, rin * 0.55), 0.3, 0.32, 0.08, 10, Color(0.6, 0.58, 0.55))
	b.sph("stonewall", Vector3(-rin * 0.3, y + 0.12, rin * 0.55), 0.07, Color(0.5, 0.5, 0.5))
	# 貯蔵穴
	b.cyl("flat", Vector3(rin * 0.45, y + 0.004, rin * 0.35), 0.35, 0.35, 0.01, 10, Color(0.12, 0.1, 0.08))
	for k in 3:
		var a := TAU * k / 3.0 + 1.2
		b.spot(hp + Vector3(cos(a) * 1.1, 0, sin(a) * 1.1), -a + PI * 0.5, "sit")
	b.spot(_door_in(b, 0, 0.8), 0.0, "stand")


static func _takayuka(b: InteriorBuilder) -> void:
	var r := b.fr(0)
	var y := b.fy(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.78, 0.66, 0.5))
	# 穂首刈りの稲束を棚に積む・甕・籠
	for k in 3:
		var x := r.position.x + 0.5 + k * 0.6
		for j in 4:
			b.cylt("thatch", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y + 0.12 + (j % 2) * 0.2, r.position.y + 0.25 + j * 0.0)), 0.09, 0.09, 0.9, 6, Color(0.92, 0.82, 0.45))
	b.shelf(Vector3(r.end.x - 0.45, y, r.get_center().y), PI * 0.5, r.size.y - 0.4, 1.4, 0.6, 3, Color(0.6, 0.48, 0.36))
	for k in 2:
		var p := Vector3(r.end.x - 0.45, y + 0.05 + k * 0.67, r.get_center().y - 0.5)
		for j in 3:
			b.cylt("thatch", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0.1, j * 0.35)), 0.09, 0.09, 0.5, 6, Color(0.9, 0.8, 0.42))
	for k in 2:
		b.cyl("earth", Vector3(r.position.x + 0.5 + k * 0.6, y, r.end.y - 0.5), 0.2, 0.28, 0.55, 10, Color(0.6, 0.42, 0.3), true)
	b.cyl("bamboo", Vector3(r.get_center().x, y, r.position.y + 0.4), 0.22, 0.28, 0.35, 10, Color(0.7, 0.58, 0.38))
	b.light(Vector3(0, y + 1.6, r.end.y - 0.3), Color(0.95, 0.9, 0.8), 0.45, 4.0)
	b.spot(_door_in(b, 0, 0.7), PI, "work")


static func _raised_hall(b: InteriorBuilder) -> void:
	# 弥生〜古墳の大型掘立柱建物（祭殿）。棟持柱・祭壇・銅鏡・銅鐸
	var r := b.fr(0)
	var y := b.fy(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.72, 0.58, 0.42))
	for sgn in [-1.0, 1.0]:
		b.cyl("wood", Vector3(sgn * r.size.x * 0.3, y, 0), 0.2, 0.18, b.fh(0), 8, Color(0.55, 0.4, 0.3), true)
	var ax := Vector3(0, y, r.position.y + 0.8)
	b.box("wood", ax + Vector3(0, 0.3, 0), Vector3(2.4, 0.6, 0.9), Color(0.6, 0.45, 0.32), 0.0, true)
	b.box("cloth", ax + Vector3(0, 0.61, 0), Vector3(2.5, 0.02, 1.0), Color(0.9, 0.88, 0.82))
	for k in 3:
		var p := ax + Vector3(-0.8 + k * 0.8, 0.62, 0)
		b.rod("wood", p, p + Vector3(0, 0.35, 0), 0.02, Color(0.4, 0.3, 0.2))
		b.cylt("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0.55, 0.0)), 0.16, 0.16, 0.02, 14, Color(0.55, 0.6, 0.5))
	b.cyl("metal", ax + Vector3(1.6, 0.0, 0.2), 0.12, 0.22, 0.6, 8, Color(0.42, 0.55, 0.45))
	b.enza(ax + Vector3(0, 0, 1.3))
	b.spot(ax + Vector3(0, 0, 1.3), PI, "scene")
	for sgn in [-1.0, 1.0]:
		b.lamp("toumyo", ax + Vector3(sgn * 1.4, 0.62, 0), sgn > 0)
		b.spot(Vector3(sgn * r.size.x * 0.3, y, r.end.y - 0.8), PI, "guard")


# ================================================================ 平安〜室町
static func _shinden(b: InteriorBuilder) -> void:
	# 寝殿造: 板の間・母屋と廂の柱・御簾・几帳・置き畳（繧繝縁は主の座）・屏風・二階厨子・灯台
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.6, 0.46, 0.34))
	b.fittings(0, 0, "misu")
	for side in [1, 2, 3]:
		b.fittings(0, side, "panel", Color(0.7, 0.56, 0.42), h * 0.55)
	# 母屋の柱（廂との境）
	var inset := minf(1.6, r.size.y * 0.22)
	var core := r.grow(-inset)
	var nx := maxi(2, int(core.size.x / 2.6))
	for i in nx + 1:
		for z in [core.position.y, core.end.y]:
			var x := core.position.x + core.size.x * i / nx
			b.cyl("wood", Vector3(x, y, z), 0.13, 0.13, h, 8, Color(0.82, 0.72, 0.6), true)
	# 母屋前面の御簾（一部巻き上げ）
	for i in nx:
		if i == nx / 2:
			continue
		var x0 := core.position.x + core.size.x * (i + 0.5) / nx
		b.box("bamboo", Vector3(x0, y + h - 0.9, core.end.y), Vector3(core.size.x / nx - 0.3, 1.5, 0.015), Color(0.86, 0.76, 0.5))
		b.box("cloth", Vector3(x0, y + h - 0.18, core.end.y + 0.01), Vector3(core.size.x / nx - 0.3, 0.14, 0.01), Color(0.55, 0.12, 0.18))
	# 主の座
	var seat := Vector3(core.get_center().x, y, core.position.y + 1.4)
	b.oki_datami(seat, PI * 0.5, true)
	b.box("cloth", seat + Vector3(0, 0.13, 0.2), Vector3(0.7, 0.05, 0.7), Color(0.5, 0.2, 0.35))
	b.kyosoku(seat + Vector3(0.45, 0.1, 0.25), PI * 0.5)
	b.byobu(seat + Vector3(0, 0, -0.9), 0.0, Color(0.88, 0.84, 0.72), 6, 1.6)
	b.spot(seat + Vector3(0, 0.1, 0.25), 0.0, "scene")
	for sgn in [-1.0, 1.0]:
		b.kicho(seat + Vector3(sgn * 2.0, 0, 0.8), sgn * 0.5, Color(0.7, 0.25, 0.3) if sgn < 0 else Color(0.35, 0.45, 0.6))
		b.oki_datami(seat + Vector3(sgn * 2.4, 0, 1.6), 0.0, false)
		b.spot(seat + Vector3(sgn * 2.4, 0.1, 1.6), PI, "sit")
		b.lamp("toudai", seat + Vector3(sgn * 1.3, 0, 1.4), sgn < 0)
	# 二階厨子・唐櫃・火桶
	var zx := Vector3(core.end.x - 0.4, y, core.position.y + 0.5)
	b.box("darkwood", zx + Vector3(0, 0.45, 0), Vector3(0.9, 0.9, 0.45), Color(0.15, 0.1, 0.08), 0.0, true)
	b.box("gold", zx + Vector3(0, 0.92, 0), Vector3(0.92, 0.04, 0.47), GOLDC)
	b.box("darkwood", Vector3(core.position.x + 0.6, y + 0.3, core.position.y + 0.5), Vector3(0.9, 0.6, 0.6), Color(0.15, 0.1, 0.08), 0.0, true)
	b.cyl("wood", seat + Vector3(-0.9, 0, 0.9), 0.22, 0.2, 0.35, 10, Color(0.55, 0.4, 0.3))
	b.sph("emissive", seat + Vector3(-0.9, 0.33, 0.9), 0.07, Color(1.0, 0.4, 0.12), 5, 3, Vector3(1.4, 0.5, 1.4))
	b.spot(_door_in(b, 0, 1.0), PI, "stand")


static func _palace(b: InteriorBuilder, dk: bool) -> void:
	# 飛鳥〜平安の宮殿・朝堂・政庁: 塼敷きの床・朱の柱・高御座（大極殿）・官人の机と倚子
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.structure("wood", Color(0.75, 0.6, 0.45))
	b.finish(r, y, "stone", Color(0.6, 0.58, 0.55))
	var tile_n := int(r.size.x / 0.9)
	for k in range(1, tile_n):
		b.hrect("flat", Rect2(r.position.x + k * r.size.x / tile_n - 0.01, r.position.y, 0.02, r.size.y), y + 0.02, Color(0.45, 0.43, 0.4))
	# 内側の柱列（入側）
	var core := r.grow(-minf(1.8, r.size.y * 0.2))
	var nx := maxi(2, int(core.size.x / 3.0))
	for i in nx + 1:
		for z in [core.position.y, core.end.y]:
			b.cyl("plaster", Vector3(core.position.x + core.size.x * i / nx, y, z), 0.22, 0.2, h, 8, VERM, true)
	b.nageshi(0, h - 0.6, VERM)
	if dk:
		# 高御座（八角の屋形・三段の基壇）
		var c := Vector3(core.get_center().x, y, core.position.y + 1.6)
		for k in 3:
			b.cyl("darkwood", c + Vector3(0, k * 0.25, 0), 2.0 - k * 0.35, 2.0 - k * 0.35, 0.25, 8, Color(0.12, 0.1, 0.1) if k < 2 else VERM, true)
		for k in 8:
			var a := TAU * k / 8.0
			b.cyl("plaster", c + Vector3(cos(a) * 1.0, 0.75, sin(a) * 1.0), 0.05, 0.05, 2.0, 6, VERM)
		b.cylt("darkwood", Transform3D(Basis(), c + Vector3(0, 2.75, 0)), 1.35, 0.25, 0.8, 8, Color(0.12, 0.1, 0.1))
		b.sph("gold", c + Vector3(0, 3.6, 0), 0.22, GOLDC)
		b.box("gold", c + Vector3(0, 0.95, -0.2), Vector3(0.8, 0.4, 0.6), GOLDC)
		b.spot(c + Vector3(0, 0.75, 0.1), 0.0, "scene")
		for k in 4:
			b.box("cloth", Vector3(core.position.x + 1.0 + k * (core.size.x - 2.0) / 3.0, y + h - 1.5, core.position.y + 0.3), Vector3(0.4, 2.2, 0.02), [VERM, Color(0.2, 0.35, 0.6), Color(0.9, 0.8, 0.3), Color(0.25, 0.5, 0.3)][k])
	else:
		# 官人の机（朝堂・政庁）
		for row in 2:
			var z := core.position.y + 1.2 + row * 1.8
			if z > core.end.y - 0.6:
				break
			for k in maxi(1, int(core.size.x / 2.4)):
				var x := core.position.x + 1.2 + k * 2.4
				if x > core.end.x - 0.8:
					break
				b.box("wood", Vector3(x, y + 0.35, z), Vector3(1.2, 0.05, 0.5), Color(0.62, 0.42, 0.28), 0.0, true)
				for sgn in [-1.0, 1.0]:
					b.box("wood", Vector3(x + sgn * 0.5, y + 0.17, z), Vector3(0.06, 0.34, 0.45), Color(0.5, 0.34, 0.22))
				b.box("flat", Vector3(x - 0.2, y + 0.39, z), Vector3(0.3, 0.02, 0.2), Color(0.95, 0.92, 0.82))
				b.box("stonewall", Vector3(x + 0.35, y + 0.39, z), Vector3(0.12, 0.03, 0.18), Color(0.2, 0.2, 0.22))
				b.box("tatami", Vector3(x, y + 0.04, z + 0.6), Vector3(0.9, 0.08, 0.6), Color(0.8, 0.72, 0.5))
				b.spot(Vector3(x, y + 0.08, z + 0.6), PI, "sit")
		b.byobu(Vector3(core.get_center().x, y, core.position.y + 0.4), 0.0, Color(0.9, 0.86, 0.76), 6, 1.6)
	for sgn in [-1.0, 1.0]:
		b.lamp("toudai", Vector3(core.get_center().x + sgn * core.size.x * 0.3, y, core.get_center().y), sgn < 0)
	b.spot(_door_in(b, 0, 1.0), PI, "guard")


static func _coffered(b: InteriorBuilder, i: int, colr: Color, frame: Color, cell := 0.9) -> void:
	# 格天井（格縁の格子＋鏡板）
	var r := b.fr(i)
	var y := b.fy(i) + b.fh(i) - 0.06
	b.hrect("wood", r, y + 0.02, colr, false)
	var nx := maxi(1, int(r.size.x / cell))
	var nz := maxi(1, int(r.size.y / cell))
	for k in nx + 1:
		b.box("darkwood", Vector3(r.position.x + r.size.x * k / nx, y, r.get_center().y), Vector3(0.06, 0.06, r.size.y), frame)
	for k in nz + 1:
		b.box("darkwood", Vector3(r.get_center().x, y, r.position.y + r.size.y * k / nz), Vector3(r.size.x, 0.06, 0.06), frame)


static func _saobuchi(b: InteriorBuilder, i: int, colr := Color(0.72, 0.58, 0.44)) -> void:
	# 竿縁天井（板張り＋細い竿縁）
	var r := b.fr(i)
	var y := b.fy(i) + b.fh(i) - 0.04
	b.hrect("wood", r, y + 0.02, colr, false, b.floors[i].get("hole", Rect2()))
	var n := maxi(1, int(r.size.x / 0.45))
	for k in range(1, n):
		var x := r.position.x + r.size.x * k / n
		b.box("wood", Vector3(x, y, r.get_center().y), Vector3(0.03, 0.03, r.size.y), colr.darkened(0.35))


static func _temple(b: InteriorBuilder) -> void:
	# 本堂・金堂: 須弥壇と本尊・脇侍・天蓋・内陣の柱・前卓・礼盤・木魚・燭台・格天井。外陣は時代で塼／畳
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	var era := b.era
	var ancient := era in ["asuka_nara", "heian"]
	var black := (b.def.get("wall", Color.WHITE) as Color).v < 0.4
	b.structure()
	var inner_z := r.position.y + minf(3.4, r.size.y * 0.42)
	var naijin := Rect2(r.position.x, r.position.y, r.size.x, inner_z - r.position.y)
	var gejin := Rect2(r.position.x, inner_z, r.size.x, r.end.y - inner_z)
	if ancient:
		b.finish(r, y, "stone", Color(0.62, 0.6, 0.56))
	else:
		b.finish(naijin, y, "boards", Color(0.45, 0.3, 0.22))
		b.finish(gejin, y, "tatami")
		b.box("darkwood", Vector3(r.get_center().x, y + 0.04, inner_z), Vector3(r.size.x, 0.08, 0.12), Color(0.15, 0.1, 0.08))
	_coffered(b, 0, Color(0.85, 0.7, 0.45) if not black else Color(0.3, 0.25, 0.2), Color(0.25, 0.18, 0.12) if not black else GOLDC * 0.8)
	# 内陣の四天柱
	var cx := r.get_center().x
	var sz := r.position.y + 1.4
	for sx in [-1.0, 1.0]:
		for z in [sz - 0.9, inner_z - 0.1]:
			b.cyl("plaster", Vector3(cx + sx * minf(2.6, r.size.x * 0.25), y, z), 0.2, 0.18, h, 10, VERM if not black else Color(0.15, 0.12, 0.1), true)
	# 須弥壇（黒漆・金の縁）
	var dais := Vector3(cx, y, sz)
	for k in 3:
		var w := minf(3.6, r.size.x * 0.4) - k * 0.3
		b.box("darkwood", dais + Vector3(0, 0.25 + k * 0.3, 0), Vector3(w, 0.3, 1.6 - k * 0.2), Color(0.1, 0.08, 0.08), 0.0, k == 0)
		b.box("gold", dais + Vector3(0, 0.4 + k * 0.3, 0.8 - k * 0.1), Vector3(w, 0.04, 0.02), GOLDC)
	var top := dais + Vector3(0, 1.0, 0)
	_buddha(b, top, 1.0, true)
	if ancient or r.size.x > 12.0:
		for sgn in [-1.0, 1.0]:
			_buddha(b, top + Vector3(sgn * 1.1, 0, 0.1), 0.7, false)
	# 天蓋
	b.cylt("gold", Transform3D(Basis(), top + Vector3(0, 2.4, 0)), 0.9, 0.9, 0.15, 8, GOLDC)
	for k in 8:
		var a := TAU * k / 8.0
		b.box("gold", top + Vector3(cos(a) * 0.85, 2.15, sin(a) * 0.85), Vector3(0.05, 0.4, 0.05), GOLDC)
	# 前卓（香炉・花瓶・燭台）と礼盤・木魚・鏧子
	var mae := dais + Vector3(0, 0, 1.4)
	b.box("darkwood", mae + Vector3(0, 0.45, 0), Vector3(1.6, 0.06, 0.6), Color(0.12, 0.1, 0.08), 0.0, true)
	b.box("gold", mae + Vector3(0, 0.25, 0), Vector3(1.5, 0.4, 0.5), Color(0.6, 0.45, 0.25))
	b.cyl("metal", mae + Vector3(0, 0.48, 0), 0.12, 0.1, 0.12, 8, Color(0.3, 0.26, 0.2))
	for sgn in [-1.0, 1.0]:
		b.lamp("shokudai" if not ancient else "toudai", mae + Vector3(sgn * 0.6, 0.48, 0), sgn < 0)
		b.cyl("metal", mae + Vector3(sgn * 0.35, 0.48, 0), 0.06, 0.05, 0.22, 8, Color(0.6, 0.5, 0.3))
		b.sph("flat", mae + Vector3(sgn * 0.35, 0.78, 0), 0.08, Color(0.9, 0.85, 0.9))
	var rb := mae + Vector3(0, 0, 1.0)
	b.box("darkwood", rb + Vector3(0, 0.12, 0), Vector3(0.9, 0.24, 0.9), Color(0.12, 0.1, 0.08), 0.0, true)
	b.sph("wood", rb + Vector3(-0.7, 0.18, 0.1), 0.18, Color(0.62, 0.3, 0.18), 8, 5, Vector3(1.1, 0.85, 1.0))
	b.cyl("cloth", rb + Vector3(-0.7, 0, 0.1), 0.2, 0.2, 0.06, 8, Color(0.55, 0.15, 0.15))
	b.cyl("metal", rb + Vector3(0.7, 0.05, 0.1), 0.14, 0.18, 0.16, 10, Color(0.62, 0.5, 0.28))
	b.spot(rb + Vector3(0, 0.24, 0), 0.0, "sit")
	# 華鬘（内陣の上から下がる金具）
	for sgn in [-1.0, 1.0]:
		b.box("gold", Vector3(cx + sgn * 1.6, y + h - 0.6, inner_z - 0.3), Vector3(0.5, 0.35, 0.02), GOLDC)
	# 外陣: 参拝者の座
	var nrow := maxi(1, int((gejin.size.y - 1.2) / 1.2))
	for row in nrow:
		for k in 4:
			var p := Vector3(cx - 2.4 + k * 1.6, y + 0.07, inner_z + 1.0 + row * 1.2)
			if p.z > r.end.y - 1.2:
				continue
			b.spot(p, 0.0, "sit")
			if era in ["edo", "meiji_taisho", "showa"] and (row + k) % 2 == 0:
				b.zabuton(p, Color(0.5, 0.2, 0.25))
	# 本能寺（1582）: 信長の御座所・寝所の屏風と武具
	if "honnoji" in b.def.get("tags", []):
		var seat := Vector3(r.position.x + 1.6, y, inner_z + 1.2)
		b.byobu(seat + Vector3(-0.4, 0, 0), PI * 0.5, GOLDC, 6, 1.6)
		b.box("tatami", seat + Vector3(0.5, 0.05, 0), Vector3(1.9, 0.1, 0.95), Color(0.86, 0.84, 0.6), PI * 0.5)
		b.kyosoku(seat + Vector3(0.6, 0.1, 0.3), 0.0)
		b.spot(seat + Vector3(0.6, 0.1, 0), -PI * 0.5, "scene")
		_spear_rack(b, Vector3(r.end.x - 0.25, y, inner_z + 1.0), -PI * 0.5)
		b.spot(Vector3(r.end.x - 1.0, y, r.end.y - 1.0), PI, "guard")
		b.spot(Vector3(r.position.x + 1.0, y, r.end.y - 1.0), PI, "guard")
	b.spot(_door_in(b, 0, 1.0), PI, "stand")


static func _buddha(b: InteriorBuilder, p: Vector3, s: float, seated: bool) -> void:
	var g := GOLDC
	if seated:
		# 蓮華座＋結跏趺坐の像＋光背
		b.cyl("gold", p, 0.55 * s, 0.6 * s, 0.25 * s, 12, Color(0.95, 0.75, 0.4))
		b.sph("gold", p + Vector3(0, 0.32 * s, 0), 0.42 * s, g, 10, 6, Vector3(1.3, 0.45, 1.0))
		b.sph("gold", p + Vector3(0, 0.72 * s, 0), 0.32 * s, g, 10, 6, Vector3(1.0, 1.35, 0.8))
		b.sph("gold", p + Vector3(0, 1.22 * s, 0.03), 0.17 * s, g, 10, 6)
		b.sph("gold", p + Vector3(0, 1.38 * s, 0.02), 0.09 * s, Color(0.3, 0.25, 0.35), 8, 5)
		b.sph("gold", p + Vector3(0, 1.0 * s, -0.2 * s), 0.75 * s, Color(0.95, 0.72, 0.35), 14, 6, Vector3(1.0, 1.25, 0.06))
	else:
		b.cyl("gold", p, 0.25 * s, 0.28 * s, 0.15 * s, 10, Color(0.95, 0.75, 0.4))
		b.cyl("gold", p + Vector3(0, 0.15 * s, 0), 0.16 * s, 0.13 * s, 1.0 * s, 8, g)
		b.sph("gold", p + Vector3(0, 1.3 * s, 0), 0.14 * s, g, 8, 5)
		b.sph("gold", p + Vector3(0, 1.2 * s, -0.12 * s), 0.4 * s, Color(0.95, 0.72, 0.35), 12, 5, Vector3(1.0, 1.4, 0.06))


static func _kinkaku(b: InteriorBuilder) -> void:
	# 金閣 一層（法水院）: 宝冠釈迦如来坐像・足利義満像。寝殿造風の板の間と蔀戸
	var r := b.fr(0)
	var y := b.fy(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.66, 0.52, 0.38))
	b.fittings(0, 0, "shoji")
	b.fittings(0, 1, "panel", Color(0.75, 0.62, 0.48), 2.0)
	b.fittings(0, 3, "panel", Color(0.75, 0.62, 0.48), 2.0)
	_saobuchi(b, 0)
	var c := Vector3(-1.0, y, r.position.y + 1.2)
	b.box("darkwood", c + Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 1.2), Color(0.12, 0.1, 0.08), 0.0, true)
	_buddha(b, c + Vector3(0, 0.6, 0), 0.8, true)
	# 足利義満坐像（黒い法衣）
	var yo := Vector3(2.0, y, r.position.y + 1.4)
	b.box("darkwood", yo + Vector3(0, 0.2, 0), Vector3(1.0, 0.4, 0.9), Color(0.12, 0.1, 0.08), 0.0, true)
	b.sph("cloth", yo + Vector3(0, 0.65, 0), 0.38, Color(0.12, 0.12, 0.14), 8, 5, Vector3(1.2, 0.9, 1.0))
	b.sph("flat", yo + Vector3(0, 1.05, 0.05), 0.15, Color(0.9, 0.78, 0.65), 8, 5)
	for sgn in [-1.0, 1.0]:
		b.lamp("toudai", c + Vector3(sgn * 1.3, 0, 1.4), sgn < 0)
	b.spot(c + Vector3(0, 0, 2.6), PI, "sit")
	b.spot(_door_in(b, 0, 1.0), PI, "stand")


static func _pagoda(b: InteriorBuilder) -> void:
	# 五重塔の初層: 心柱・四天柱（彩色）・須弥壇の四方仏・壁の彩色
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.structure()
	b.finish(r, y, "stone", Color(0.6, 0.58, 0.55))
	_coffered(b, 0, Color(0.85, 0.6, 0.3), Color(0.3, 0.2, 0.15), 0.6)
	b.cyl("wood", Vector3(0, y, 0), 0.32, 0.3, h, 12, Color(0.7, 0.55, 0.4), true)
	var q := minf(1.3, r.size.x * 0.28)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * q, y, sz * q)
			b.cyl("plaster", p, 0.14, 0.14, h, 8, VERM, true)
			for k in 3:
				b.cyl("flat", p + Vector3(0, 0.6 + k * 0.7, 0), 0.145, 0.145, 0.12, 8, [Color(0.2, 0.45, 0.35), Color(0.9, 0.75, 0.3), Color(0.25, 0.35, 0.6)][k])
	b.box("darkwood", Vector3(0, y + 0.3, 0), Vector3(q * 2.0 + 0.6, 0.6, q * 2.0 + 0.6), Color(0.12, 0.1, 0.08))
	for k in 4:
		var a := PI * 0.5 * k
		var dv := Vector3(sin(a), 0, cos(a))
		_buddha(b, Vector3(0, y + 0.6, 0) + dv * (q * 0.75), 0.5, true)
	# 壁の彩色（菩薩・雲の帯をベタ塗りで）
	for side in [1, 2, 3]:
		var sl := b.side_line(0, side)
		var o: Vector3 = sl[0]
		var d: Vector3 = sl[1]
		var n: Vector3 = sl[2]
		for k in 3:
			var c := o + d * (k + 0.5) / 3.0 + n * 0.02 + Vector3(0, 1.4, 0)
			b.box("flat", c, Vector3(d.length() / 3.0 - 0.2, 1.6, 0.01) if side % 2 == 0 else Vector3(0.01, 1.6, d.length() / 3.0 - 0.2), [Color(0.35, 0.55, 0.5), Color(0.75, 0.45, 0.35), Color(0.4, 0.45, 0.7)][k])
	for sgn in [-1.0, 1.0]:
		b.lamp("toudai", Vector3(sgn * (q + 0.6), y, q + 0.5), sgn < 0)
	b.spot(_door_in(b, 0, 0.8), PI, "sit")


static func _shrine(b: InteriorBuilder) -> void:
	# 拝殿: 板の間・神前（神鏡・御幣・榊・三方の神饌）・注連縄・太鼓・賽銭箱・鈴
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.82, 0.7, 0.54))
	_saobuchi(b, 0, Color(0.85, 0.75, 0.6))
	var c := Vector3(r.get_center().x, y, r.position.y + 0.8)
	for k in 2:
		b.box("wood", c + Vector3(0, 0.25 + k * 0.3, -k * 0.2), Vector3(2.4 - k * 0.6, 0.3, 0.8), Color(0.9, 0.82, 0.66), 0.0, k == 0)
	b.cyl("metal", c + Vector3(0, 0.85, -0.2), 0.04, 0.04, 0.25, 6, Color(0.6, 0.5, 0.35))
	b.cylt("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, 1.25, -0.2)), 0.22, 0.22, 0.03, 16, Color(0.85, 0.85, 0.8))
	for sgn in [-1.0, 1.0]:
		var p := c + Vector3(sgn * 0.8, 0.55, 0.2)
		b.rod("wood", p, p + Vector3(0, 0.7, 0), 0.015, Color(0.85, 0.75, 0.55))
		for k in 4:
			b.box("flat", p + Vector3(0.05, 0.62 - k * 0.09, 0), Vector3(0.08, 0.08, 0.01), Color(0.98, 0.98, 0.96), 0.3 * (k % 2))
		b.cyl("earth", c + Vector3(sgn * 0.4, 0.55, 0.25), 0.05, 0.06, 0.15, 6, Color(0.95, 0.95, 0.95))
		b.sph("flat", c + Vector3(sgn * 0.4, 0.8, 0.25), 0.1, Color(0.18, 0.4, 0.2), 6, 4)
		b.lamp("toudai" if b.era != "showa" else "bulb", c + Vector3(sgn * 1.6, 0 if b.era != "showa" else h - 0.8, 0.6), sgn < 0)
	# 三方（神饌）
	for k in 3:
		var p := c + Vector3(-0.5 + k * 0.5, 0.56, 0.3)
		b.box("wood", p + Vector3(0, 0.06, 0), Vector3(0.3, 0.12, 0.3), Color(0.92, 0.86, 0.72))
		b.sph("flat", p + Vector3(0, 0.16, 0), 0.07, [Color(0.98, 0.98, 0.95), Color(0.9, 0.4, 0.3), Color(0.95, 0.85, 0.4)][k], 6, 4)
	# 注連縄
	b.box("thatch", Vector3(r.get_center().x, y + h - 0.5, r.position.y + 1.6), Vector3(r.size.x * 0.7, 0.14, 0.14), Color(0.92, 0.84, 0.55))
	for k in 4:
		b.box("flat", Vector3(r.get_center().x - r.size.x * 0.25 + k * r.size.x * 0.17, y + h - 0.75, r.position.y + 1.6), Vector3(0.1, 0.35, 0.01), Color(0.98, 0.98, 0.96))
	# 太鼓
	var tk := Vector3(r.end.x - 1.0, y, r.position.y + 1.6)
	b.box("darkwood", tk + Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.3), Color(0.2, 0.12, 0.1), 0.0, true)
	b.cylt("wood", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), tk + Vector3(0, 1.1, -0.25)), 0.4, 0.4, 0.5, 14, Color(0.6, 0.25, 0.15))
	# 賽銭箱・鈴
	var dp := _door_in(b, 0, 0.6)
	b.box("wood", dp + Vector3(0, 0.3, -0.4), Vector3(1.2, 0.6, 0.6), Color(0.6, 0.45, 0.3), 0.0, true)
	b.sph("gold", Vector3(dp.x, y + h - 0.4, dp.z - 0.4), 0.15, GOLDC)
	b.rod("cloth", Vector3(dp.x, y + h - 0.55, dp.z - 0.4), Vector3(dp.x, y + 1.0, dp.z - 0.4), 0.04, Color(0.85, 0.2, 0.2), 4)
	b.spot(c + Vector3(0, 0, 1.4), PI, "scene")
	for k in 3:
		b.enza(c + Vector3(-1.0 + k * 1.0, 0, 2.6))
		b.spot(c + Vector3(-1.0 + k * 1.0, 0.05, 2.6), PI, "sit")


static func _shoin(b: InteriorBuilder, goten: bool) -> void:
	# 書院造（武家屋敷の主殿・寺の書院）/ 御殿（金碧障壁画の大広間）: 畳・襖・障子・床の間・違い棚・付書院・長押
	var r := b.fr(0)
	var y := b.fy(0)
	var h := b.fh(0)
	var era := b.era
	b.structure()
	var dais := goten and r.size.y > 7.0
	var jodan := Rect2(r.position.x, r.position.y, r.size.x, minf(3.0, r.size.y * 0.32))
	if dais:
		b.platform(jodan, y, y + 0.3, "tatami")
		var main := Rect2(r.position.x, jodan.end.y, r.size.x, r.end.y - jodan.end.y)
		b.finish(main, y, "tatami")
		b.box("darkwood", Vector3(r.get_center().x, y + 0.15, jodan.end.y), Vector3(r.size.x, 0.3, 0.1), Color(0.12, 0.08, 0.06))
		b.box("gold", Vector3(r.get_center().x, y + 0.3, jodan.end.y + 0.06), Vector3(r.size.x, 0.03, 0.02), GOLDC)
	else:
		b.finish(r, y, "tatami", Color.WHITE, Rect2(), era in ["kamakura_muromachi", "sengoku"])
	b.fittings(0, 0, "shoji")
	var fus := Color(0.88, 0.85, 0.76) if not goten else Color.WHITE
	b.fittings(0, 1, "gold" if goten else "fusuma", fus)
	b.fittings(0, 3, "gold" if goten else "fusuma", fus)
	b.nageshi(0, minf(2.1, h - 0.4), Color(0.5, 0.38, 0.28))
	if goten:
		_coffered(b, 0, Color(1.0, 0.85, 0.5), Color(0.1, 0.08, 0.06), 0.75)
	else:
		_saobuchi(b, 0)
	# 床の間・違い棚・付書院（奥の壁）
	var by := y + (0.3 if dais else 0.0)
	var sl := b.side_line(0, 2)
	var L: float = (sl[1] as Vector3).length()
	b.floors[0]["_ty"] = by
	_tokonoma_at(b, by, L * 0.55)
	# 主の座（上段の中央）と家臣の列
	var seat := Vector3(r.get_center().x, by, r.position.y + 1.5)
	b.zabuton(seat, Color(0.55, 0.15, 0.2) if era != "kamakura_muromachi" else Color(0.75, 0.6, 0.35))
	b.kyosoku(seat + Vector3(0.45, 0.05, 0.1), PI * 0.5)
	b.spot(seat + Vector3(0, 0.07, 0), 0.0, "scene")
	var katana := seat + Vector3(-1.1, 0, -0.3)
	b.box("darkwood", katana + Vector3(0, 0.05, 0), Vector3(0.5, 0.1, 0.25), Color(0.1, 0.08, 0.06))
	for k in 2:
		b.box("darkwood", katana + Vector3(0, 0.3 + k * 0.22, 0), Vector3(0.9, 0.04, 0.04), Color(0.1, 0.08, 0.08), 0.15)
	var z0 := (jodan.end.y if dais else r.position.y + 2.8) + 0.9
	var rows := 0
	while z0 < r.end.y - 1.0 and rows < 4:
		for sgn in [-1.0, 1.0]:
			for k in 2:
				var p := Vector3(r.get_center().x + sgn * (1.0 + k * 1.1), y, z0)
				if absf(p.x - r.get_center().x) > r.size.x * 0.5 - 0.5:
					continue
				b.spot(p + Vector3(0, 0.07, 0), -sgn * PI * 0.5 if not goten else 0.0, "sit")
				if era == "edo":
					b.zabuton(p, Color(0.35, 0.3, 0.45))
		z0 += 1.2
		rows += 1
	var lp := era_lamp(era)
	for sgn in [-1.0, 1.0]:
		b.lamp(lp, Vector3(r.get_center().x + sgn * r.size.x * 0.35, by, r.position.y + 0.8), sgn < 0)
	b.hibachi(Vector3(r.get_center().x + 1.4, y, r.get_center().y + 0.6))
	if not goten:
		b.box("wood", Vector3(r.position.x + 1.0, y + 0.18, r.get_center().y), Vector3(0.9, 0.04, 0.45), Color(0.4, 0.26, 0.16))
		b.box("stonewall", Vector3(r.position.x + 1.1, y + 0.21, r.get_center().y), Vector3(0.15, 0.03, 0.22), Color(0.15, 0.15, 0.17))
		b.byobu(Vector3(r.end.x - 0.6, y, r.get_center().y), -PI * 0.5, Color(0.92, 0.88, 0.78), 6, 1.4)
	else:
		# 帳台構（武者隠しの襖）
		var ch := Vector3(r.end.x - 0.05, by, r.position.y + 1.2)
		b.box("darkwood", ch + Vector3(-0.05, 0.9, 0), Vector3(0.08, 1.8, 1.4), Color(0.12, 0.08, 0.06))
		b.box("cloth", ch + Vector3(-0.1, 0.85, 0), Vector3(0.02, 1.5, 1.2), Color(0.75, 0.2, 0.18))
		b.spot(Vector3(r.end.x - 1.0, y, r.end.y - 1.0), PI, "guard")
	b.spot(_door_in(b, 0, 1.0), PI, "guard")


## 奥の壁（side 2）の u に床の間（＋違い棚・付書院）。床の高さ by
static func _tokonoma_at(b: InteriorBuilder, by: float, u: float) -> void:
	var saved := b.fy(0)
	b.floors[0]["y"] = by
	b.tokonoma(0, 2, u, 1.8, true, true)
	b.floors[0]["y"] = saved


static func _spear_rack(b: InteriorBuilder, p: Vector3, yaw: float, n := 5) -> void:
	var bs := Basis(Vector3.UP, yaw)
	for k in 2:
		b.box("darkwood", p + Vector3(0, 1.4 + k * 0.5, 0), Vector3(1.8, 0.06, 0.08), Color(0.25, 0.18, 0.12), yaw)
	for k in n:
		var q := p + bs * Vector3(-0.7 + k * 0.35, 0, 0.05)
		b.rod("wood", q + Vector3(0, 0.1, 0), q + Vector3(0, 2.6, 0), 0.018, Color(0.3, 0.2, 0.12), 4)
		b.box("metal", q + Vector3(0, 2.7, 0), Vector3(0.03, 0.22, 0.01), Color(0.8, 0.82, 0.85), yaw)


static func _armor(b: InteriorBuilder, p: Vector3, yaw: float, colr := Color(0.15, 0.12, 0.12)) -> void:
	# 甲冑（具足櫃の上に飾る）
	b.box("darkwood", p + Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.45), Color(0.12, 0.08, 0.06), yaw, true)
	b.sph("cloth", p + Vector3(0, 0.85, 0), 0.25, colr, 8, 5, Vector3(1.2, 1.3, 0.9))
	for k in 3:
		b.box("cloth", p + Vector3(0, 0.6 - k * 0.07, 0), Vector3(0.6, 0.08, 0.4), colr.lightened(0.1 * k), yaw)
	b.sph("metal", p + Vector3(0, 1.25, 0), 0.16, Color(0.12, 0.12, 0.14), 8, 5, Vector3(1.2, 0.8, 1.2))
	b.box("gold", p + Vector3(0, 1.42, 0.05), Vector3(0.3, 0.16, 0.02), GOLDC, yaw)


# ================================================================ 町家・長屋・茶屋・民家
static func _machiya(b: InteriorBuilder) -> void:
	# 町家: 通り庭（土間・竈・流し・井戸）、店の間（帳場格子・帳場机・大福帳・算盤・銭箱）、中の間（長火鉢）、奥の間（床の間）。
	# 2 階は厨子二階（低い天井・虫籠窓・布団・行李・行灯）
	var r := b.fr(0)
	var y := b.fy(0)
	var dx: float = b.def.get("doma_x", r.position.x + 0.8)
	var doma_w := 1.55
	var doma := Rect2(r.position.x, r.position.y, doma_w, r.size.y)
	var room := Rect2(r.position.x + doma_w, r.position.y, r.size.x - doma_w, r.size.y)
	var ry := y + 0.42
	var two := b.floors.size() > 1
	if two:
		var st: Dictionary = b.floors[0]["stair"]
		var sa: Vector3 = st["a"]
		st["a"] = Vector3(sa.x, ry, sa.z)
	b.structure("wood", Color(0.5, 0.38, 0.28), "box", Color(0.4, 0.26, 0.16))
	b.finish(doma, y, "earth", Color(0.62, 0.52, 0.42))
	var shop_d := minf(2.4, r.size.y * 0.3)
	b.platform(room, y, ry, "boards", Color(0.66, 0.5, 0.36), [[Vector3(room.position.x, y, r.end.y - 1.2), Vector3(-1, 0, 0)], [Vector3(room.position.x, y, r.get_center().y), Vector3(-1, 0, 0)]])
	var mid := Rect2(room.position.x, r.position.y + 2.6, room.size.x, r.end.y - shop_d - r.position.y - 2.6)
	b.tatami(mid, ry - 0.06, b.floors[0].get("hole", Rect2()))
	var oku := Rect2(room.position.x, r.position.y, room.size.x, 2.6)
	b.tatami(oku, ry - 0.06)
	# 間仕切りの襖（中の間と奥の間）・格子（店の間と中の間）
	b.partition(Vector2(room.position.x, oku.end.y), Vector2(room.end.x, oku.end.y), ry, 2.0, "flat", Color(0.88, 0.85, 0.76), [[room.size.x * 0.3, room.size.x * 0.3 + 1.0, 1.85]], 0.04)
	# 店の間: 帳場
	var ch := Vector3(room.position.x + 1.0, ry, r.end.y - shop_d + 0.6)
	b.box("wood", ch + Vector3(0, 0.15, 0), Vector3(0.8, 0.3, 0.45), Color(0.45, 0.3, 0.18), 0.0, true)
	b.box("flat", ch + Vector3(0.1, 0.31, 0), Vector3(0.3, 0.02, 0.2), Color(0.95, 0.92, 0.82))
	b.box("wood", ch + Vector3(-0.2, 0.32, 0.05), Vector3(0.26, 0.03, 0.08), Color(0.3, 0.2, 0.12))
	for k in 6:
		b.box("wood", ch + Vector3(-0.45 + k * 0.18, 0.2, 0.42), Vector3(0.03, 0.4, 0.03), Color(0.35, 0.24, 0.15))
	b.box("wood", ch + Vector3(0, 0.4, 0.42), Vector3(1.0, 0.04, 0.04), Color(0.35, 0.24, 0.15))
	b.box("darkwood", ch + Vector3(-0.6, 0.12, -0.2), Vector3(0.4, 0.24, 0.3), Color(0.15, 0.1, 0.08))
	b.zabuton(ch + Vector3(0, 0, -0.5), Color(0.25, 0.3, 0.45))
	b.spot(ch + Vector3(0, 0.07, -0.5), 0.0, "work")
	if b.era == "edo" or b.era == "sengoku":
		b.shelf(Vector3(room.end.x - 0.35, ry, r.end.y - shop_d * 0.5), -PI * 0.5, shop_d - 0.3, 1.6, 0.5, 4, Color(0.55, 0.4, 0.28), func(q: Vector3, yw: float) -> void:
			b.box("cloth", q + Vector3(0, 0.1, 0), Vector3(0.3, 0.2, 0.3), Color(0.25, 0.3, 0.5).lerp(Color(0.6, 0.3, 0.2), absf(sin(q.z * 3.0))), yw))
	# 中の間: 長火鉢・行灯・神棚
	var mc := Vector3(mid.get_center().x, ry, mid.get_center().y)
	b.box("wood", mc + Vector3(0, 0.22, 0), Vector3(0.9, 0.44, 0.5), Color(0.5, 0.3, 0.18), 0.0, true)
	b.box("earth", mc + Vector3(0.15, 0.45, 0), Vector3(0.5, 0.02, 0.35), Color(0.6, 0.58, 0.55))
	b.sph("emissive", mc + Vector3(0.15, 0.47, 0), 0.05, Color(1.0, 0.4, 0.12), 5, 3, Vector3(1.5, 0.5, 1.5))
	b.cyl("metal", mc + Vector3(0.15, 0.46, 0), 0.08, 0.09, 0.14, 8, Color(0.2, 0.2, 0.2))
	b.spot(mc + Vector3(0, 0.07, 0.6), PI, "sit")
	b.spot(mc + Vector3(0.7, 0.07, 0), -PI * 0.5, "sit")
	var lp := era_lamp(b.era)
	b.lamp(lp if lp != "toudai" else "andon", mc + Vector3(-0.8, 0, -0.4))
	b.kamidana(Vector3(room.end.x - 0.25, ry + 1.85, mc.z), Vector3(-1, 0, 0))
	# 奥の間: 小さな床の間
	var tc := Vector3(oku.end.x - 0.6, ry, oku.position.y + 0.3)
	b.box("darkwood", tc + Vector3(0, 0.08, 0), Vector3(1.1, 0.16, 0.6), Color(0.3, 0.2, 0.15))
	b.kakejiku(tc + Vector3(0, 1.1, -0.25), Vector3(0, 0, 1))
	b.tansu(Vector3(oku.position.x + 0.6, ry, oku.position.y + 0.3), 0.0, 0.9, 1.1)
	# 通り庭: 竈・流し・水瓶・井戸
	var kz := r.position.y + r.size.y * 0.35
	b.kamado(Vector3(doma.get_center().x, y, kz), PI * 0.5, 2)
	b.box("stonewall", Vector3(doma.position.x + 0.35, y + 0.4, kz - 1.3), Vector3(0.6, 0.8, 0.9), Color(0.6, 0.58, 0.55), 0.0, true)
	b.mizugame(Vector3(doma.get_center().x + 0.2, y, kz + 1.2))
	b.cyl("stonewall", Vector3(doma.get_center().x, y, r.position.y + 0.7), 0.4, 0.42, 0.65, 10, Color(0.6, 0.58, 0.55), true)
	b.cylt("wood", Transform3D(Basis(), Vector3(doma.get_center().x, y + 0.66, r.position.y + 0.7)), 0.36, 0.36, 0.04, 10, Color(0.5, 0.4, 0.3))
	b.spot(Vector3(doma.get_center().x, y, kz + 0.6), -PI * 0.5, "work")
	b.spot(Vector3(dx, y, r.end.y - 0.9), PI, "stand")
	b.fire_pts.append(Vector3(room.get_center().x, ry, r.get_center().y))
	if two:
		_machiya_2f(b)


static func _machiya_2f(b: InteriorBuilder) -> void:
	var r := b.fr(1)
	var y := b.fy(1)
	var hole := b.floor_hole(1)
	b.tatami(r, y, hole)
	b.fittings(1, 0, "shoji", Color.WHITE, 1.5)
	b.fittings(1, 3, "fusuma", Color(0.86, 0.82, 0.72), 1.7)
	# 近江屋の二階（1867）: 八畳の座敷に行灯・火鉢・屏風・掛軸
	var omiya: bool = "omiya" in b.def.get("tags", [])
	var c := Vector3(r.get_center().x - 0.3, y, r.get_center().y + 0.4)
	b.lamp("andon" if b.era != "meiji_taisho" else "lamp", c + Vector3(-0.9, 0, -0.6))
	b.hibachi(c + Vector3(0.4, 0, 0.2))
	b.futon_pile(Vector3(r.position.x + 0.7, y, r.position.y + 0.6), 0.0)
	b.box("bamboo", Vector3(r.end.x - 0.8, y + 0.2, r.position.y + 0.5), Vector3(0.7, 0.4, 0.45), Color(0.72, 0.6, 0.4))
	b.spot(c + Vector3(0.4, 0.06, 0.9), PI, "sit")
	b.spot(c + Vector3(-0.4, 0.06, -0.2), 0.0, "sit", 1)
	if omiya:
		b.byobu(c + Vector3(0, 0, -1.6), 0.0, Color(0.92, 0.88, 0.78), 6, 1.2)
		b.kakejiku(Vector3(r.get_center().x, y + 1.1, r.position.y + 0.03), Vector3(0, 0, 1))
		b.spot(c + Vector3(0.0, 0.06, 0.4), PI, "scene", 1)
		b.spot(c + Vector3(1.0, 0.06, 0.4), PI, "scene", 1)
	for s in b.spots:
		if (s["p"] as Vector3).y > y - 0.1:
			s["floor"] = 1


static func _nagaya(b: InteriorBuilder) -> void:
	# 裏長屋（九尺二間）: 土間に竈・水瓶・流し、四畳半、枕屏風と畳んだ布団・行灯・長火鉢。隣とは壁一枚
	var r := b.fr(0)
	var y := b.fy(0)
	var dx: float = b.def.get("doma_x", r.position.x + 0.8)
	var unit_w := clampf(r.size.x * 0.55, 2.6, 3.4)
	var unit := Rect2(r.position.x, r.position.y, unit_w, r.size.y)
	b.structure()
	b.partition(Vector2(unit.end.x, r.position.y), Vector2(unit.end.x, r.end.y), y, b.fh(0), "plaster", Color(0.8, 0.74, 0.62))
	var doma := Rect2(unit.position.x, r.end.y - 1.8, unit.size.x, 1.8)
	b.finish(doma, y, "earth", Color(0.6, 0.5, 0.4))
	var tat := Rect2(unit.position.x, r.position.y, unit.size.x, r.size.y - 1.8)
	b.platform(tat, y, y + 0.4, "tatami", Color.WHITE, [[Vector3(dx, y, tat.end.y), Vector3(0, 0, 1)]])
	b.kamado(Vector3(unit.end.x - 0.55, y, doma.get_center().y), -PI * 0.5, 1)
	b.mizugame(Vector3(unit.end.x - 0.45, y, doma.end.y - 0.35))
	b.box("wood", Vector3(unit.position.x + 0.35, y + 0.7, doma.get_center().y), Vector3(0.5, 0.06, 1.0), Color(0.6, 0.48, 0.36), 0.0, true)
	var ty := y + 0.4
	b.byobu(Vector3(unit.position.x + 0.9, ty, r.position.y + 0.5), 0.0, Color(0.85, 0.8, 0.68), 2, 0.9)
	b.futon_pile(Vector3(unit.position.x + 0.7, ty, r.position.y + 0.55), 0.0)
	b.lamp("andon", Vector3(unit.end.x - 0.5, ty, r.position.y + 0.6))
	b.hibachi(Vector3(unit.get_center().x, ty, tat.get_center().y + 0.3))
	b.box("bamboo", Vector3(unit.end.x - 0.45, ty + 0.2, tat.get_center().y - 0.4), Vector3(0.6, 0.4, 0.4), Color(0.72, 0.6, 0.4))
	b.spot(Vector3(unit.get_center().x, ty + 0.06, tat.get_center().y + 0.9), PI, "sit")
	b.spot(Vector3(dx, y, r.end.y - 0.8), PI, "stand")
	b.fire_pts.append(Vector3(unit.get_center().x, ty, tat.get_center().y))


static func _chaya(b: InteriorBuilder) -> void:
	# 江戸の茶屋（両国広小路）: 土間に毛氈を敷いた縁台・茶釜の竈・団子の台・提灯・品書き。奥に小座敷、2 階は客座敷
	var r := b.fr(0)
	var y := b.fy(0)
	var two := b.floors.size() > 1
	if two:
		var st: Dictionary = b.floors[0]["stair"]
		var sa: Vector3 = st["a"]
		st["a"] = Vector3(sa.x, y + 0.42, sa.z)
	b.structure("wood", Color(0.5, 0.38, 0.28), "box", Color(0.4, 0.26, 0.16))
	var zash := Rect2(r.position.x + 1.6, r.position.y, r.size.x - 1.6, minf(3.2, r.size.y * 0.4))
	var front := Rect2(r.position.x, zash.end.y, r.size.x, r.end.y - zash.end.y)
	b.finish(front, y, "earth", Color(0.64, 0.54, 0.42))
	b.finish(Rect2(r.position.x, r.position.y, 1.6, zash.size.y), y, "earth", Color(0.62, 0.52, 0.4))
	b.platform(zash, y, y + 0.42, "tatami", Color.WHITE, [[Vector3(zash.get_center().x, y, zash.end.y), Vector3(0, 0, 1)]], b.floors[0].get("hole", Rect2()))
	for k in 2:
		var p := Vector3(r.get_center().x + 0.4, y, front.position.y + 1.2 + k * 1.7)
		if p.z > r.end.y - 0.6:
			break
		b.box("wood", p + Vector3(0, 0.4, 0), Vector3(1.8, 0.06, 0.6), Color(0.6, 0.45, 0.3), 0.0, true)
		b.box("cloth", p + Vector3(0, 0.435, 0), Vector3(1.8, 0.01, 0.62), Color(0.82, 0.12, 0.12))
		for sgn in [-1.0, 1.0]:
			b.box("wood", p + Vector3(sgn * 0.8, 0.2, 0), Vector3(0.06, 0.4, 0.5), Color(0.5, 0.36, 0.24))
		b.cyl("earth", p + Vector3(-0.4, 0.44, 0), 0.05, 0.04, 0.07, 8, Color(0.8, 0.75, 0.6))
		b.spot(p + Vector3(0.3, 0.44, 0), 0.0, "sit")
		b.spot(p + Vector3(-0.5, 0.44, 0), 0.0, "sit")
	# 茶釜の竈と団子
	var kp := Vector3(r.position.x + 0.6, y, front.position.y + 0.8)
	b.kamado(kp, PI * 0.5, 1)
	b.box("wood", kp + Vector3(0, 0.45, 1.1), Vector3(0.8, 0.9, 0.5), Color(0.55, 0.4, 0.28), 0.0, true)
	for k in 3:
		b.rod("bamboo", kp + Vector3(-0.2 + k * 0.2, 0.92, 1.1), kp + Vector3(-0.2 + k * 0.2, 1.1, 1.15), 0.008, Color(0.7, 0.6, 0.4), 3)
		for j in 3:
			b.sph("flat", kp + Vector3(-0.2 + k * 0.2, 0.96 + j * 0.05, 1.11), 0.025, [Color(0.95, 0.75, 0.8), Color(0.98, 0.98, 0.95), Color(0.6, 0.8, 0.5)][j], 5, 3)
	b.spot(kp + Vector3(0.6, 0, 0.4), -PI * 0.5, "work")
	# 提灯と品書き
	for k in 3:
		b.lamp("chouchin", Vector3(r.position.x + 1.0 + k * (r.size.x - 2.0) * 0.5, y + 2.3, front.get_center().y), k == 1)
	for k in 4:
		b.box("wood", Vector3(r.end.x - 0.03, y + 1.9, front.position.y + 0.6 + k * 0.4), Vector3(0.02, 0.5, 0.25), Color(0.85, 0.75, 0.58))
		b.box("flat", Vector3(r.end.x - 0.045, y + 1.9, front.position.y + 0.6 + k * 0.4), Vector3(0.01, 0.35, 0.05), Color(0.1, 0.1, 0.1))
	if two:
		var r2 := b.fr(1)
		var y2 := b.fy(1)
		b.tatami(r2, y2, b.floor_hole(1))
		b.fittings(1, 0, "shoji", Color.WHITE, 1.5)
		for k in 3:
			var p := Vector3(r2.position.x + 1.0 + k * 1.1, y2, r2.get_center().y)
			b.box("darkwood", p + Vector3(0, 0.12, 0), Vector3(0.36, 0.24, 0.36), Color(0.45, 0.12, 0.1))
			b.zabuton(p + Vector3(0, 0, 0.5), Color(0.6, 0.2, 0.25))
			b.spot(p + Vector3(0, 0.07, 0.5), PI, "sit", 1)
		b.lamp("andon", Vector3(r2.end.x - 0.6, y2, r2.position.y + 0.6))
	b.fire_pts.append(kp + Vector3(0, 0.5, 0))


static func _minka(b: InteriorBuilder, farm: bool) -> void:
	# 古代〜近代の民家・農家: 土間（竈・水瓶・臼・農具・藁）と板の間の囲炉裏（自在鉤）。農家は奥に座敷（近世以降は畳）
	var r := b.fr(0)
	var y := b.fy(0)
	var era := b.era
	var dx: float = b.def.get("doma_x", r.position.x + 1.0)
	b.structure()
	var left := dx < r.get_center().x
	var doma_w := clampf(r.size.x * 0.38, 2.2, 4.0)
	var doma := Rect2(r.position.x, r.position.y, doma_w, r.size.y) if left else Rect2(r.end.x - doma_w, r.position.y, doma_w, r.size.y)
	var room := Rect2(r.position.x + doma_w, r.position.y, r.size.x - doma_w, r.size.y) if left else Rect2(r.position.x, r.position.y, r.size.x - doma_w, r.size.y)
	b.finish(doma, y, "earth", Color(0.6, 0.5, 0.38))
	var ry := y + (0.4 if era != "jomon_kofun" else 0.25)
	var edge_x := room.position.x if left else room.end.x
	var to_doma := Vector3(-1, 0, 0) if left else Vector3(1, 0, 0)
	var tatami_ok := era in ["edo", "meiji_taisho", "showa"] or (era == "sengoku" and farm)
	var oku := Rect2()
	if farm and room.size.y > 4.5:
		oku = Rect2(room.position.x, room.position.y, room.size.x, room.size.y * 0.4)
		var hiroma := Rect2(room.position.x, oku.end.y, room.size.x, room.end.y - oku.end.y)
		b.platform(hiroma, y, ry, "boards", Color(0.52, 0.38, 0.26), [[Vector3(edge_x, y, hiroma.get_center().y), to_doma]])
		b.platform(oku, y, ry, "tatami" if tatami_ok else "boards", Color(0.55, 0.4, 0.28))
		b.partition(Vector2(oku.position.x, oku.end.y), Vector2(oku.end.x, oku.end.y), ry, 1.9, "flat", Color(0.86, 0.82, 0.72), [[oku.size.x * 0.35, oku.size.x * 0.35 + 1.0, 1.8]], 0.04)
	else:
		b.platform(room, y, ry, "boards", Color(0.52, 0.38, 0.26), [[Vector3(edge_x, y, room.get_center().y), to_doma]])
		if not tatami_ok:
			b.box("tatami", Vector3(room.get_center().x, ry + 0.012, room.position.y + 0.8), Vector3(minf(room.size.x - 0.4, 2.4), 0.02, 1.2), Color(0.72, 0.6, 0.38))
	# 囲炉裏
	var irp := Vector3(room.get_center().x, ry, (room.get_center().y if oku.size.y == 0.0 else (oku.end.y + room.end.y) * 0.5))
	b.irori(irp, 1.0)
	b.spot(irp + Vector3(0, 0, 0.85), PI, "sit")
	b.spot(irp + Vector3(0.85 * (1.0 if left else -1.0), 0, 0), -PI * 0.5 * (1.0 if left else -1.0), "sit")
	b.spot(irp + Vector3(0, 0, -0.85), 0.0, "sit")
	# 土間の竈・水瓶・臼と杵・農具・藁束・籠
	var dc := doma.get_center()
	b.kamado(Vector3(dc.x, y, doma.position.y + 0.7), 0.0, 2 if farm else 1)
	b.mizugame(Vector3(doma.position.x + 0.4 if left else doma.end.x - 0.4, y, doma.position.y + 1.7))
	b.cyl("wood", Vector3(dc.x + 0.3, y, dc.y + 0.4), 0.3, 0.32, 0.6, 10, Color(0.55, 0.4, 0.28), true)
	b.rod("wood", Vector3(dc.x + 0.55, y + 0.6, dc.y + 0.4), Vector3(dc.x + 0.9, y + 1.6, dc.y + 0.6), 0.05, Color(0.5, 0.36, 0.24), 5)
	var wx := doma.position.x + 0.08 if left else doma.end.x - 0.08
	for k in 3:
		b.rod("wood", Vector3(wx, y + 0.05, doma.position.y + 2.6 + k * 0.3), Vector3(wx, y + 1.6, doma.position.y + 2.7 + k * 0.3), 0.025, Color(0.45, 0.32, 0.22), 4)
		b.box("metal", Vector3(wx, y + 0.12, doma.position.y + 2.6 + k * 0.3), Vector3(0.04, 0.2, 0.18), Color(0.35, 0.33, 0.3))
	for k in 3:
		b.cylt("thatch", Transform3D(Basis(), Vector3(dc.x - 0.5 + k * 0.25, y, doma.end.y - 0.6)), 0.12, 0.08, 0.9, 6, Color(0.88, 0.78, 0.5))
	b.cyl("bamboo", Vector3(dc.x - 0.4, y, dc.y - 0.5), 0.22, 0.28, 0.4, 10, Color(0.7, 0.58, 0.38))
	b.spot(Vector3(dc.x, y, doma.position.y + 1.4), PI, "work")
	if farm:
		# 馬屋（土間の奥）: 柵と飼い葉桶
		var um := Vector3(dc.x, y, doma.end.y - 1.6)
		for k in 3:
			b.box("wood", um + Vector3(0, 0.4 + k * 0.4, 0.8), Vector3(doma_w - 0.3, 0.08, 0.08), Color(0.5, 0.36, 0.24))
		b.box("wood", um + Vector3(0, 0.3, -0.3), Vector3(1.0, 0.3, 0.4), Color(0.5, 0.36, 0.24))
	if era in ["edo", "meiji_taisho"]:
		b.kamidana(Vector3(room.get_center().x, ry + 1.9, room.position.y + 0.25), Vector3(0, 0, 1))
	if era == "meiji_taisho":
		b.lamp("lamp", irp + Vector3(1.2, 1.6, 0))
	elif era == "edo":
		b.lamp("andon", irp + Vector3(1.2, 0, -0.6), false)
	b.spot(Vector3(dx, y, r.end.y - 0.8), PI, "stand")


static func _kura(b: InteriorBuilder) -> void:
	# 土蔵: 両側の棚（葛籠・長持・木箱）、奥に千両箱と米俵の山、壺・甕
	var r := b.fr(0)
	var y := b.fy(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.62, 0.5, 0.38))
	for sgn in [-1.0, 1.0]:
		b.shelf(Vector3(r.get_center().x + sgn * (r.size.x * 0.5 - 0.35), y, r.get_center().y - 0.3), sgn * PI * 0.5, r.size.y - 2.2, 2.4, 0.6, 4, Color(0.55, 0.42, 0.3),
			func(q: Vector3, yw: float) -> void:
				b.box("bamboo", q + Vector3(0, 0.15, 0), Vector3(0.4, 0.3, 0.4), Color(0.7, 0.55, 0.35), yw))
	var bz := r.position.y + 0.7
	for row in 2:
		for k in 3 - row:
			b.komedawara(Vector3(r.get_center().x - 0.9 + k * 0.6 + row * 0.3, y + row * 0.45, bz), PI * 0.5)
	col_center(b, Vector3(r.get_center().x - 0.6, y + 0.45, bz), Vector3(1.8, 0.9, 0.6))
	var era := b.era
	if era in ["sengoku", "edo", "meiji_taisho"]:
		for k in 4:
			b.senryobako(Vector3(r.get_center().x + 1.0, y + (k % 2) * 0.17, bz + 0.1 + (k / 2) * 0.2), 0.0)
	b.box("darkwood", Vector3(r.get_center().x, y + 0.3, r.get_center().y + 0.6), Vector3(1.5, 0.6, 0.6), Color(0.3, 0.2, 0.14), 0.0, true)
	for k in 3:
		b.tsubo(Vector3(r.get_center().x - 0.6 + k * 0.6, y, r.end.y - 0.6), 1.0, [Color(0.45, 0.35, 0.28), Color(0.3, 0.32, 0.36), Color(0.55, 0.4, 0.3)][k])
	b.lamp("chouchin" if era != "meiji_taisho" else "lamp", Vector3(r.get_center().x, y + 2.2, r.get_center().y))
	b.spot(Vector3(r.get_center().x, y, r.get_center().y - 0.4), 0.0, "work")


static func col_center(b: InteriorBuilder, c: Vector3, s: Vector3) -> void:
	b.col_box(c, s)


static func _storehouse(b: InteriorBuilder) -> void:
	# 古代・中世の港の倉: 俵・甕・木箱・帆と櫂
	var r := b.fr(0)
	var y := b.fy(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.6, 0.48, 0.36))
	for k in int(r.size.x / 2.2):
		var x := r.position.x + 1.1 + k * 2.2
		for row in 2:
			for j in 2 - row:
				b.komedawara(Vector3(x - 0.3 + j * 0.6 + row * 0.3, y + row * 0.45, r.position.y + 0.7), PI * 0.5)
		b.col_box(Vector3(x, y + 0.45, r.position.y + 0.7), Vector3(1.4, 0.9, 0.6))
		if k % 2 == 0:
			b.tsubo(Vector3(x, y, r.position.y + 2.0), 1.4, Color(0.5, 0.38, 0.3))
		else:
			b.crate(Vector3(x, y, r.position.y + 2.0), 0.8)
	for k in 3:
		b.rod("wood", Vector3(r.end.x - 0.3, y + 0.1, r.end.y - 1.0 - k * 0.3), Vector3(r.end.x - 0.4, y + 2.6, r.end.y - 1.2 - k * 0.3), 0.04, Color(0.55, 0.42, 0.3), 4)
	b.cylt("cloth", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(r.position.x + 2.2, y + 0.3, r.end.y - 0.8)), 0.25, 0.25, 2.0, 8, Color(0.92, 0.88, 0.78))
	b.lamp(era_lamp(b.era), Vector3(r.get_center().x, y, r.end.y - 1.4))
	b.spot(Vector3(r.get_center().x, y, r.get_center().y + 0.6), 0.0, "work")
	b.spot(_door_in(b, 0, 1.0), PI, "stand")


# ================================================================ 城
static func _castle(b: InteriorBuilder) -> void:
	# 天守: 板張りの床、身舎と武者走り（入側）を分ける柱、急な木の階段、連子窓から外が見える、狭間、
	# 槍掛け・鉄砲棚・甲冑・弾薬箱。最上階は廻縁の眺め（豊臣・織田の天守は金碧）
	var accent: bool = b.def.get("accent", false)
	b.structure("wood", Color(0.55, 0.42, 0.3), "wood", Color(0.5, 0.36, 0.24))
	for i in b.floors.size():
		var f: Dictionary = b.floors[i]
		var r := b.fr(i)
		var y := b.fy(i)
		var h := b.fh(i)
		var last: bool = f.get("last", false)
		var hole := b.floor_hole(i)
		var ceil_hole: Rect2 = f.get("hole", Rect2())
		if last and accent:
			b.finish(r, y, "tatami", Color.WHITE, hole, true)
		else:
			b.finish(r, y, "boards", Color(0.58, 0.44, 0.32), hole)
		# 身舎の柱（武者走りとの境）
		var core := r.grow(-1.4)
		if core.size.x > 2.0 and core.size.y > 2.0:
			var nx := maxi(1, int(core.size.x / 2.4))
			var nz := maxi(1, int(core.size.y / 2.4))
			for ix in nx + 1:
				for iz in nz + 1:
					if ix != 0 and ix != nx and iz != 0 and iz != nz:
						continue
					var p := Vector3(core.position.x + core.size.x * ix / nx, y, core.position.y + core.size.y * iz / nz)
					if ceil_hole.grow(0.4).has_point(Vector2(p.x, p.z)) or hole.grow(0.4).has_point(Vector2(p.x, p.z)):
						continue
					b.cyl("wood", p, 0.15, 0.15, h, 8, Color(0.55, 0.42, 0.3), true)
			# 敷居（入側との段差を線で）
			b.box("darkwood", Vector3(core.get_center().x, y + 0.02, core.position.y), Vector3(core.size.x, 0.04, 0.08), Color(0.3, 0.22, 0.16))
			b.box("darkwood", Vector3(core.get_center().x, y + 0.02, core.end.y), Vector3(core.size.x, 0.04, 0.08), Color(0.3, 0.22, 0.16))
		# 梁
		b.box("wood", Vector3(r.get_center().x, y + h - 0.25, r.get_center().y), Vector3(r.size.x, 0.25, 0.3), Color(0.45, 0.33, 0.24))
		# 窓の内側（突上戸を開けてある）
		for wv in f.get("win", []):
			var side := int(wv["side"])
			var u := float(wv["u"])
			var wy := y + float(wv["y"])
			var p: Vector3
			var n: Vector3
			match side:
				0:
					p = Vector3(u, wy, r.end.y)
					n = Vector3(0, 0, -1)
				2:
					p = Vector3(u, wy, r.position.y)
					n = Vector3(0, 0, 1)
				1:
					p = Vector3(r.end.x, wy, u)
					n = Vector3(-1, 0, 0)
				_:
					p = Vector3(r.position.x, wy, u)
					n = Vector3(1, 0, 0)
			var yaw := atan2(n.x, n.z)
			b.box("darkwood", p + Vector3(0, -0.04, 0) + n * 0.12, Vector3(1.1, 0.05, 0.3), Color(0.35, 0.25, 0.18), yaw)
			b.boxt("darkwood", Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.9), p + Vector3(0, 0.95, 0) + n * 0.2), Vector3(1.05, 0.5, 0.04), Color(0.3, 0.22, 0.16))
		# 狭間（壁の低い所の小さな穴: 三角・四角）
		for side in 4:
			var sl := b.side_line(i, side)
			var o: Vector3 = sl[0]
			var d: Vector3 = sl[1]
			var n: Vector3 = sl[2]
			var cnt := int(d.length() / 2.2)
			for k in cnt:
				var q := o + d * (k + 0.5) / cnt + n * 0.01 + Vector3(0, 0.75, 0)
				var skip := false
				for op in b.openings(i, side):
					var tt := d.length() * (k + 0.5) / cnt
					if tt > float(op[0]) - 0.4 and tt < float(op[1]) + 0.4:
						skip = true
				if skip:
					continue
				b.box("flat", q, Vector3(0.18, 0.18, 0.01) if side % 2 == 0 else Vector3(0.01, 0.18, 0.18), Color(0.08, 0.07, 0.07))
		if last:
			if accent:
				for side in [1, 2, 3]:
					b.fittings(i, side, "gold", Color.WHITE, h * 0.55)
				_coffered(b, i, Color(1.0, 0.85, 0.5), Color(0.1, 0.08, 0.06), 0.8)
			else:
				b.kamidana(Vector3(r.get_center().x, y + 1.8, r.position.y + 0.25), Vector3(0, 0, 1))
			b.lamp("shokudai" if accent else era_lamp(b.era), Vector3(r.get_center().x + 1.0, y, r.get_center().y + 0.5))
			b.spot(Vector3(r.get_center().x, y, r.get_center().y - 0.6), PI, "scene", i)
			b.zabuton(Vector3(r.get_center().x, y, r.get_center().y - 0.6), Color(0.55, 0.15, 0.2))
		else:
			# 武具
			var side_x := r.position.x + 0.3 if i % 2 == 0 else r.end.x - 0.3
			_spear_rack(b, Vector3(side_x, y, r.get_center().y), PI * 0.5 if i % 2 == 0 else -PI * 0.5)
			var gun_z := r.position.y + 0.3
			b.box("darkwood", Vector3(r.get_center().x, y + 1.2, gun_z), Vector3(2.2, 0.06, 0.18), Color(0.25, 0.18, 0.12))
			for k in 6:
				b.rod("darkwood", Vector3(r.get_center().x - 0.9 + k * 0.36, y + 0.3, gun_z + 0.08), Vector3(r.get_center().x - 0.9 + k * 0.36, y + 1.6, gun_z + 0.05), 0.02, Color(0.3, 0.2, 0.14), 4)
			if i == 0:
				for k in 2:
					_armor(b, Vector3(r.end.x - 1.2 - k * 1.0, y, r.position.y + 0.6), 0.0, Color(0.15, 0.12, 0.12) if k == 0 else Color(0.5, 0.12, 0.1))
			for k in 2:
				b.crate(Vector3(r.end.x - 0.6, y, r.end.y - 0.7 - k * 0.8), 0.6, 0.0, Color(0.4, 0.28, 0.18))
			if i <= 1:
				b.lamp(era_lamp(b.era) if b.era != "meiji_taisho" else "lamp", Vector3(r.get_center().x - 1.0, y, r.get_center().y + 0.4), i == 0)
			b.spot(Vector3(r.position.x + 0.7, y, r.end.y - 0.7), 0.0, "guard", i)
			b.spot(Vector3(r.end.x - 0.7, y, r.position.y + 1.6), PI, "guard", i)
		b.fire_pts.append(Vector3(r.get_center().x, y, r.get_center().y))


static func _yagura(b: InteriorBuilder) -> void:
	var r := b.fr(0)
	var y := b.fy(0)
	b.structure()
	b.finish(r, y, "boards", Color(0.58, 0.44, 0.32))
	for side in [1, 2, 3]:
		var sl := b.side_line(0, side)
		var o: Vector3 = sl[0]
		var d: Vector3 = sl[1]
		var n: Vector3 = sl[2]
		for k in 3:
			var q := o + d * (k + 0.5) / 3.0 + n * 0.01 + Vector3(0, 0.8, 0)
			b.box("flat", q, Vector3(0.2, 0.2, 0.01) if side % 2 == 0 else Vector3(0.01, 0.2, 0.2), Color(0.08, 0.07, 0.07))
	_spear_rack(b, Vector3(r.position.x + 0.25, y, r.get_center().y), PI * 0.5, 4)
	for k in 3:
		b.crate(Vector3(r.end.x - 0.5, y, r.position.y + 0.5 + k * 0.7), 0.55, 0.0, Color(0.4, 0.28, 0.18))
	b.cylt("wood", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(r.get_center().x, y + 0.5, r.position.y + 0.6)), 0.35, 0.35, 0.45, 12, Color(0.55, 0.25, 0.15))
	b.lamp("chouchin", Vector3(r.get_center().x, y + 2.6, r.get_center().y))
	b.spot(Vector3(r.get_center().x, y, r.get_center().y), 0.0, "guard")

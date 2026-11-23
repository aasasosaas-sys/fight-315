class_name WorldVegetation
extends RefCounted
## 植生: 手続き的な樹木（杉・松・広葉樹・桜・竹）、低木、岩。MultiMesh＋距離 LOD。
## 草は EraWorld 側の GPU グラス（grass_clump_mesh を使う）。

const CELL := 60.0
const NEAR_END := 150.0
const FAR_BEGIN := 225.0

var w: EraWorld
var t: TerrainGen
static var _mesh_cache := {}
static var _mat_cache := {}

const SPECIES := {
	# アニメ背景調の明るい色（c1=影寄り, c2=日なた寄り）
	"cedar": {"c1": Color(0.10, 0.30, 0.22), "c2": Color(0.16, 0.38, 0.24), "count": 5.0, "size": 0.42, "aspect": 0.32, "bark": Color(0.52, 0.36, 0.28)},
	"pine": {"c1": Color(0.15, 0.36, 0.20), "c2": Color(0.22, 0.44, 0.22), "count": 7.0, "size": 0.4, "aspect": 0.25, "bark": Color(0.48, 0.36, 0.32)},
	"broadleaf": {"c1": Color(0.26, 0.50, 0.16), "c2": Color(0.38, 0.60, 0.18), "count": 5.0, "size": 0.44, "aspect": 0.55, "bark": Color(0.48, 0.40, 0.34)},
	"sakura": {"c1": Color(0.96, 0.70, 0.80), "c2": Color(1.0, 0.84, 0.90), "count": 7.0, "size": 0.42, "aspect": 0.8, "bark": Color(0.36, 0.28, 0.28)},
	"bamboo": {"c1": Color(0.36, 0.56, 0.18), "c2": Color(0.48, 0.66, 0.22), "count": 5.0, "size": 0.45, "aspect": 0.22, "bark": Color(0.58, 0.72, 0.34)},
	"bush": {"c1": Color(0.20, 0.42, 0.15), "c2": Color(0.30, 0.52, 0.17), "count": 6.0, "size": 0.42, "aspect": 0.55, "bark": Color(0.4, 0.34, 0.3)},
}


func _init(world: EraWorld) -> void:
	w = world
	t = world.terrain


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = w.rng.seed + 101
	var weights: Dictionary = w.style["trees"]
	var bamboo_noise := FastNoiseLite.new()
	bamboo_noise.seed = rng.seed
	bamboo_noise.frequency = 0.012
	var placements := {}   # species -> Array[Transform3D]
	for sp in SPECIES:
		placements[sp] = []
	var step: float = [9.0, 7.5, 6.5][EraWorld.quality]
	var half := t.half - 4.0
	var z := -half
	var trunk_cols: Array = []
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-step * 0.45, step * 0.45)
			var pz := z + rng.randf_range(-step * 0.45, step * 0.45)
			x += step
			var f := t.mask_at(t.forest, px, pz)
			var prob := f * 0.92 + 0.012
			if rng.randf() > prob:
				continue
			if not _ok_spot(px, pz, 1.5):
				continue
			var hh := t.height_at(px, pz)
			var sp := _pick_species(weights, rng, px, pz, hh, bamboo_noise)
			var sc := rng.randf_range(0.75, 1.25)
			if f < 0.3:
				sc *= 1.1
			if sp == "bamboo":
				# 竹林はまとまって
				for k in 3:
					var bx := px + rng.randf_range(-4, 4)
					var bz := pz + rng.randf_range(-4, 4)
					if _ok_spot(bx, bz, 1.0):
						placements["bamboo"].append(_xf(bx, bz, sc, rng))
				continue
			var xf := _xf(px, pz, sc, rng)
			placements[sp].append(xf)
			trunk_cols.append([xf.origin, sc, sp])
		z += step
	# 低木
	var bush_n: int = [600, 1200, 1800][EraWorld.quality]
	for k in bush_n:
		var px := rng.randf_range(-half, half)
		var pz := rng.randf_range(-half, half)
		var f := t.mask_at(t.forest, px, pz)
		var near_edge := f > 0.05 and f < 0.7
		if not near_edge and rng.randf() > 0.15:
			continue
		if not _ok_spot(px, pz, 1.0):
			continue
		placements["bush"].append(_xf(px, pz, rng.randf_range(0.6, 1.3), rng))
	# 建築側が置く植栽
	for d in w.deco_trees:
		var sp: String = d[0]
		var p: Vector3 = d[1]
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * float(d[2])), p)
		if not placements.has(sp):
			sp = "broadleaf"
		placements[sp].append(xf)
		if sp != "bush" and sp != "bamboo":
			trunk_cols.append([p, float(d[2]), sp])
	var shrubs := WorldModels.variants("shrub_02")
	if not shrubs.is_empty():
		_emit_model_cells("Shrubs", shrubs, placements["bush"], 150.0, rng)
		placements["bush"] = []
	w._tick("veg placement")
	for sp in placements:
		_emit_species(sp, placements[sp])
	w._tick("veg emit trees")
	_trunk_collisions(trunk_cols)
	_build_rocks(rng)
	_build_backdrop_forest(rng, weights)
	w._tick("veg rocks")
	_build_clutter(rng)


func _ok_spot(px: float, pz: float, margin: float) -> bool:
	if absf(px) > t.half - 2.0 or absf(pz) > t.half - 2.0:
		return false
	for key in w.landmarks:
		var info: Dictionary = w.landmarks[key]
		if key != "mountain" and TerrainGen._seg_dist(Vector2(px, pz), info.get("a", info["center"]), info.get("b", info["center"])) < float(info["r"]) * 0.92:
			return false
	if t.is_occupied(px, pz):
		return false
	if t.mask_at(t.road, px, pz) > 0.02 or t.mask_at(t.plaza, px, pz) > 0.05 or t.mask_at(t.field, px, pz) > 0.05:
		return false
	# 道のすぐ脇も避ける
	for o in [Vector2(margin + 2.0, 0), Vector2(-margin - 2.0, 0), Vector2(0, margin + 2.0), Vector2(0, -margin - 2.0)]:
		if t.mask_at(t.road, px + o.x, pz + o.y) > 0.3:
			return false
	if t.is_water(px, pz):
		return false
	if t.height_at(px, pz) < w.water_level + 1.8:
		return false
	if t.river_dist_at(px, pz) < t.river_half_w + 4.0:
		return false
	if t.normal_at(px, pz).y < 0.72:
		return false
	return true


func _pick_species(weights: Dictionary, rng: RandomNumberGenerator, px: float, pz: float, hh: float, bn: FastNoiseLite) -> String:
	var c := t.world_to_canon(Vector2(px, pz))
	if c.y > t.shore_v(c.x) - 140.0 and weights.has("pine") and rng.randf() < 0.75:
		return "pine"
	if weights.has("bamboo") and bn.get_noise_2d(px, pz) > 0.55:
		return "bamboo"
	if hh > 45.0 and weights.has("cedar") and rng.randf() < 0.7:
		return "cedar"
	var total := 0.0
	for k in weights:
		if k != "bamboo":
			total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		if k == "bamboo":
			continue
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return "broadleaf"


func _xf(px: float, pz: float, sc: float, rng: RandomNumberGenerator) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.06)) * b
	return Transform3D(b.scaled(Vector3.ONE * sc), Vector3(px, t.height_at(px, pz) - 0.15, pz))


func _emit_species(sp: String, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var meshes := species_meshes(sp)
	var cells := {}
	for xf in xfs:
		var key := Vector2i(int(floor((xf.origin.x + t.half) / CELL)), int(floor((xf.origin.z + t.half) / CELL)))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(xf)
	var root := Node3D.new()
	root.name = "Trees_" + sp
	w.add_child(root)
	var near_end := NEAR_END if sp != "bush" else 140.0
	var q := EraWorld.quality
	if q == 0:
		near_end *= 0.65
	for key in cells:
		var arr: Array = cells[key]
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[lod]
			mm.instance_count = arr.size()
			for i in arr.size():
				mm.set_instance_transform(i, arr[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if lod == 0:
				mmi.visibility_range_end = near_end
				mmi.visibility_range_end_margin = 20.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				if sp == "bush":
					continue
				mmi.visibility_range_begin = near_end - 25.0
				mmi.visibility_range_begin_margin = 20.0
				mmi.visibility_range_end = 1400.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)


func _trunk_collisions(list: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "TreeTrunks"
	body.collision_layer = 1
	body.collision_mask = 0
	var shapes := {}
	var count := 0
	for e in list:
		var p: Vector3 = e[0]
		var sc: float = e[1]
		# 道・広場の近く（プレイヤーが行き来する範囲）だけ
		var near := false
		for o in [Vector2(0, 0), Vector2(25, 0), Vector2(-25, 0), Vector2(0, 25), Vector2(0, -25)]:
			if t.mask_at(t.road, p.x + o.x, p.z + o.y) > 0.2 or t.mask_at(t.plaza, p.x + o.x, p.z + o.y) > 0.2:
				near = true
				break
		if not near:
			continue
		var r := snappedf(0.32 * sc, 0.05)
		if not shapes.has(r):
			var cs := CylinderShape3D.new()
			cs.radius = r
			cs.height = 7.0
			shapes[r] = cs
		var c := CollisionShape3D.new()
		c.shape = shapes[r]
		c.position = p + Vector3(0, 3.5, 0)
		body.add_child(c)
		count += 1
		if count > 2500:
			break
	w.add_child(body)


func _rock_variants() -> Array:
	# [parts, 基準サイズ(m)]
	var out: Array = []
	for id in ["boulder_01", "namaqualand_boulder_02"]:
		for v in WorldModels.variants(id):
			out.append(v)
	for id in ["rock_moss_set_01", "rock_moss_set_02"]:
		for v in WorldModels.variants(id):
			out.append(v)
	for id in ["rock_07", "rock_09", "stone_01"]:
		for v in WorldModels.variants(id):
			out.append(v)
	return out


func _build_rocks(rng: RandomNumberGenerator) -> void:
	var model_vars := _rock_variants()
	var meshes: Array = []
	var nv := 3
	if model_vars.is_empty():
		for v in 3:
			meshes.append(rock_mesh(v))
	else:
		nv = model_vars.size()
	var lists: Array = []
	for v in nv:
		lists.append([])
	var body := StaticBody3D.new()
	body.name = "Rocks"
	body.collision_layer = 1
	body.collision_mask = 0
	var n: int = [200, 320, 420][EraWorld.quality]
	var tries := 0
	var placed := 0
	while placed < n and tries < n * 12:
		tries += 1
		var px := rng.randf_range(-t.half + 5, t.half - 5)
		var pz := rng.randf_range(-t.half + 5, t.half - 5)
		var nrm := t.normal_at(px, pz)
		var hh := t.height_at(px, pz)
		var want := nrm.y < 0.88 or t.river_dist_at(px, pz) < t.river_half_w + 10.0 or (hh < w.water_level + 3.0 and hh > w.water_level - 1.0)
		if not want and rng.randf() > 0.08:
			continue
		if t.is_occupied(px, pz) or t.mask_at(t.road, px, pz) > 0.05 or t.mask_at(t.plaza, px, pz) > 0.05:
			continue
		var sc := rng.randf_range(0.4, 1.6)
		if rng.randf() < 0.1:
			sc *= 2.2
		var vi := rng.randi() % nv
		var xf: Transform3D
		if model_vars.is_empty():
			var b := Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU)
			b = b.scaled(Vector3(sc, sc * rng.randf_range(0.5, 0.9), sc))
			xf = Transform3D(b, Vector3(px, hh - 0.2 * sc, pz))
		else:
			# 写真スキャンの岩: 目標サイズに合わせて拡大、地面の傾きに沿わせる
			var bb := WorldModels.bounds(model_vars[vi])
			var ext := maxf(bb.size.x, bb.size.z)
			var k := (sc * 2.0) / maxf(ext, 0.01)
			var up := nrm.slerp(Vector3.UP, 0.4)
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			var axis := Vector3.UP.cross(up)
			if axis.length() > 0.001:
				b = Basis(axis.normalized(), Vector3.UP.angle_to(up)) * b
			xf = Transform3D(b.scaled(Vector3.ONE * k), Vector3(px, hh - bb.size.y * k * 0.18, pz))
		lists[vi].append(xf)
		placed += 1
		if sc > 1.0:
			var c := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = sc * 0.8
			c.shape = sh
			c.position = xf.origin + Vector3(0, -0.1 * sc, 0)
			body.add_child(c)
	var root := Node3D.new()
	root.name = "RocksMesh"
	w.add_child(root)
	if not model_vars.is_empty():
		for v in nv:
			if lists[v].is_empty():
				continue
			for node in WorldModels.multimesh_nodes(model_vars[v], lists[v], 700.0):
				root.add_child(node)
		w.add_child(body)
		return
	for v in 3:
		if lists[v].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[v]
		mm.instance_count = lists[v].size()
		for i in lists[v].size():
			mm.set_instance_transform(i, lists[v][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 700.0
		root.add_child(mmi)
	w.add_child(body)


## 境界の外（遠景の山）の森: 遠景 LOD のみ・影なし
func _build_backdrop_forest(rng: RandomNumberGenerator, weights: Dictionary) -> void:
	var n: int = [2000, 3500, 5000][EraWorld.quality]
	var lists := {}
	var tries := 0
	var placed := 0
	var bn := FastNoiseLite.new()
	while placed < n and tries < n * 6:
		tries += 1
		var ang := rng.randf() * TAU
		var r := t.half + 6.0 + pow(rng.randf(), 1.6) * 420.0
		var px := cos(ang) * r
		var pz := sin(ang) * r
		if absf(px) < t.half + 3.0 and absf(pz) < t.half + 3.0:
			continue
		var c := t.world_to_canon(Vector2(px, pz))
		if maxf(absf(c.x), -c.y) > 480.0:
			continue
		var hh := t.base_height(c.x, c.y) - 0.6
		if hh < w.water_level + 2.0:
			continue
		var e := 3.0
		var nx := t.base_height(c.x + e, c.y) - t.base_height(c.x - e, c.y)
		var nz := t.base_height(c.x, c.y + e) - t.base_height(c.x, c.y - e)
		if Vector2(nx, nz).length() / (2.0 * e) > 1.4:
			continue
		var sp := _pick_species(weights, rng, px, pz, hh, bn)
		if sp == "bamboo":
			sp = "broadleaf"
		if not lists.has(sp):
			lists[sp] = []
		var sc := rng.randf_range(0.9, 1.4)
		lists[sp].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(px, hh - 0.3, pz)))
		placed += 1
	var root := Node3D.new()
	root.name = "BackdropForest"
	w.add_child(root)
	for sp in lists:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = species_meshes(sp)[1]
		mm.instance_count = lists[sp].size()
		for i in lists[sp].size():
			mm.set_instance_transform(i, lists[sp][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


## モデルのバリエーションをセル分割した MultiMesh で配置（xfs はバリエーションに無作為に割当）
func _emit_model_cells(name: String, vars: Array, xfs: Array, vis_end: float, rng: RandomNumberGenerator, shadows := true, cell := CELL) -> void:
	if xfs.is_empty() or vars.is_empty():
		return
	var root := Node3D.new()
	root.name = name
	w.add_child(root)
	var cells := {}
	for xf in xfs:
		var key := Vector3i(int(floor((xf.origin.x + t.half) / cell)), int(floor((xf.origin.z + t.half) / cell)), rng.randi() % vars.size())
		if not cells.has(key):
			cells[key] = []
		cells[key].append(xf)
	for key in cells:
		for node in WorldModels.multimesh_nodes(vars[key.z], cells[key], vis_end, shadows):
			root.add_child(node)


## 森の下草・倒木・切り株・根・枯れ枝（モデルがある時のみ）
func _build_clutter(rng: RandomNumberGenerator) -> void:
	var sets := [
		# [id, 森の中の密度, 森の外, 表示距離, サイズ倍率範囲, 影]
		["fern_02", 0.55, 0.0, 70.0, Vector2(0.8, 1.5), false],
		["shrub_03", 0.25, 0.05, 55.0, Vector2(1.0, 2.0), false],
		["shrub_04", 0.12, 0.02, 60.0, Vector2(1.0, 1.8), false],
		["shrub_01", 0.0, 0.03, 60.0, Vector2(0.8, 1.2), false],
		["dead_tree_trunk", 0.03, 0.0, 120.0, Vector2(1.0, 1.6), true],
		["dead_tree_trunk_02", 0.03, 0.0, 120.0, Vector2(1.0, 1.4), true],
		["tree_stump_01", 0.03, 0.004, 120.0, Vector2(0.7, 1.1), true],
		["tree_stump_02", 0.03, 0.004, 120.0, Vector2(0.7, 1.1), true],
		["root_cluster_01", 0.015, 0.0, 100.0, Vector2(0.8, 1.2), true],
		["dry_branches_medium_01", 0.06, 0.0, 50.0, Vector2(1.0, 1.5), false],
	]
	var q := EraWorld.quality
	var step: float = [6.5, 5.0, 4.0][q]
	var active: Array = []
	var lists: Array = []
	for sdef in sets:
		var vars := WorldModels.variants(sdef[0])
		if vars.is_empty():
			continue
		active.append([sdef, vars])
		lists.append([])
	if active.is_empty():
		return
	var z := -t.half + 3.0
	while z < t.half - 3.0:
		var x := -t.half + 3.0
		while x < t.half - 3.0:
			var px := x + rng.randf_range(-step * 0.5, step * 0.5)
			var pz := z + rng.randf_range(-step * 0.5, step * 0.5)
			x += step
			var f := t.mask_at(t.forest, px, pz)
			var r := rng.randf()
			var pick := -1
			for i in active.size():
				var sdef: Array = active[i][0]
				r -= float(sdef[1]) * f + float(sdef[2]) * (1.0 - f)
				if r < 0.0:
					pick = i
					break
			if pick < 0 or not _ok_spot(px, pz, 0.5):
				continue
			var sd: Array = active[pick][0]
			var nrm := t.normal_at(px, pz)
			var sc := rng.randf_range(sd[4].x, sd[4].y)
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			var axis := Vector3.UP.cross(nrm)
			if axis.length() > 0.001:
				b = Basis(axis.normalized(), Vector3.UP.angle_to(nrm)) * b
			lists[pick].append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(px, t.height_at(px, pz) - 0.05, pz)))
		z += step
	for i in active.size():
		var sd: Array = active[i][0]
		_emit_model_cells("Clutter_" + String(sd[0]), active[i][1], lists[i], sd[3], rng, sd[5], 60.0)


# ================================================================ メッシュ生成
static func leaf_material(sp: String) -> ShaderMaterial:
	if _mat_cache.has(sp):
		return _mat_cache[sp]
	var d: Dictionary = SPECIES[sp]
	var m := ShaderMaterial.new()
	m.shader = WorldMaterials.shader("foliage")
	m.set_shader_parameter("leaf_color", d["c1"])
	m.set_shader_parameter("leaf_color2", d["c2"])
	m.set_shader_parameter("leaf_count", d["count"])
	m.set_shader_parameter("leaf_size", d["size"])
	m.set_shader_parameter("leaf_aspect", d["aspect"])
	match sp:
		"sakura":
			m.set_shader_parameter("translucency", 0.5)
			m.set_shader_parameter("tip_color", Color(1.0, 0.9, 0.95))
			m.set_shader_parameter("ao_strength", 0.35)
			m.set_shader_parameter("leaf_count", 9.0)
			m.set_shader_parameter("leaf_size", 0.36)
		"cedar", "pine":
			m.set_shader_parameter("blob", 0.5)
			m.set_shader_parameter("tip_color", Color(0.55, 0.8, 0.45))
		"bamboo":
			m.set_shader_parameter("blob", 0.35)
			m.set_shader_parameter("tip_color", Color(0.85, 0.95, 0.45))
	_mat_cache[sp] = m
	return m


static func bark_material(sp: String) -> ShaderMaterial:
	var k := "bark_" + sp
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := WorldMaterials._building_mat("bamboo" if sp == "bamboo" else "darkwood", 0.6, 1.0, 0.0)
	m.set_shader_parameter("albedo_mul", 1.0)
	m.set_shader_parameter("grime", 0.0)
	m.set_shader_parameter("detail", 0.5)
	# 幹の色はパレットで（テクスチャは模様だけ）
	var bc: Color = SPECIES[sp]["bark"]
	m.set_shader_parameter("base_override", Color(bc.r, bc.g, bc.b, 1.0))
	_mat_cache[k] = m
	return m


static func _model_tex(rel: String) -> Texture2D:
	var p := WorldModels.DIR + rel
	if WorldModels.enabled and ResourceLoader.exists(p):
		return load(p)
	return null


static func species_meshes(sp: String) -> Array:
	if _mesh_cache.has(sp):
		return _mesh_cache[sp]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sp)
	var near := MeshKit.new()
	var far := MeshKit.new()
	match sp:
		"cedar": _build_cedar(near, far, rng)
		"pine": _build_pine(near, far, rng)
		"broadleaf": _build_broadleaf(near, far, rng, false)
		"sakura": _build_broadleaf(near, far, rng, true)
		"bamboo": _build_bamboo(near, far, rng)
		_: _build_bush(near, far, rng)
	var mats := {"leaf": leaf_material(sp), "bark": bark_material(sp)}
	var res := [near.to_mesh(mats), far.to_mesh(mats)]
	_mesh_cache[sp] = res
	return res


## 葉カード群（楕円体の表面付近に配置）。col.r=明るさ(AO), g=揺れやすさ, a=0(カード)
static func cards(kit: MeshKit, center: Vector3, radii: Vector3, count: int, size: float, rng: RandomNumberGenerator, up_bias := 0.0, flex := 1.0, core := true) -> void:
	var s := kit._s("leaf")
	count = int(count * 1.35)
	size *= 1.3
	for i in count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1) + up_bias, rng.randf_range(-1, 1))
		if d.length_squared() < 0.01:
			d = Vector3.UP
		d = d.normalized()
		var p := center + d * radii * rng.randf_range(0.45, 1.0)
		var nrm := (d + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.6) + up_bias, rng.randf_range(-0.5, 0.5))).normalized()
		var tang := nrm.cross(Vector3.UP if absf(nrm.y) < 0.95 else Vector3.RIGHT).normalized()
		tang = tang.rotated(nrm, rng.randf() * TAU)
		var bit := nrm.cross(tang).normalized()
		var hs := size * rng.randf_range(0.8, 1.2) * 0.5
		var shade := clampf(0.55 + d.y * 0.35 + (p - center).length() / maxf(radii.x, 0.01) * 0.2, 0.2, 1.0)
		var col := Color(shade, flex, 0, 0)
		var vn := ((p - center).normalized() + Vector3.UP * 0.35).normalized()
		var base: int = s[0].size()
		var corners := [p - tang * hs - bit * hs, p + tang * hs - bit * hs, p + tang * hs + bit * hs, p - tang * hs + bit * hs]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in 4:
			s[0].append(corners[k])
			s[1].append(vn)
			s[2].append(uvs[k])
			s[3].append(col)
		s[4].append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if core:
		var cb: int = s[0].size()
		kit.sphere("leaf", Transform3D(Basis.from_scale(radii * 0.5), center), 1.0, 6, 4, Color(0.28, flex, 0, 1))
		# sphere は法線を正規化済み。色だけ上書き不要


static func far_blob(kit: MeshKit, center: Vector3, radii: Vector3, flex := 1.0) -> void:
	kit.sphere("leaf", Transform3D(Basis.from_scale(radii * 0.9), center), 1.0, 7, 4, Color(0.75, flex, 0, 1))


static func _build_cedar(near: MeshKit, far: MeshKit, rng: RandomNumberGenerator) -> void:
	var H := 17.0
	near.cylinder("bark", Transform3D(Basis(), Vector3.ZERO), 0.38, 0.06, H, 8, Color(1, 1, 1), false, true)
	far.cylinder("bark", Transform3D(Basis(), Vector3.ZERO), 0.38, 0.1, H * 0.6, 5, Color(1, 1, 1), false, true)
	var tiers := 7
	var s := near._s("leaf")
	for k in tiers:
		var tt := float(k) / (tiers - 1)
		var y0 := lerpf(3.5, H - 3.2, tt)
		var th := lerpf(4.2, 3.0, tt)
		var rr := lerpf(2.9, 0.9, tt)
		# 円錐の芯（暗い）
		near.cylinder("leaf", Transform3D(Basis(), Vector3(0, y0, 0)), rr * 0.7, 0.15, th, 8, Color(0.22, 0.5 + tt * 0.5, 0, 1), false)
		far.cylinder("leaf", Transform3D(Basis(), Vector3(0, y0, 0)), rr * 1.05, 0.2, th * 1.05, 6, Color(0.5, 0.5 + tt * 0.5, 0, 1), false)
		# 円錐表面の葉カード（外向き・やや下向き）
		var cnt := int(lerpf(34, 14, tt))
		for i in cnt:
			var a := rng.randf() * TAU
			var f := rng.randf()
			var r := lerpf(rr, 0.25, f) * rng.randf_range(0.85, 1.1)
			var p := Vector3(cos(a) * r, y0 + f * th, sin(a) * r)
			var out := Vector3(cos(a), 0.35, sin(a)).normalized()
			var tang := Vector3(-sin(a), 0, cos(a)).rotated(out, rng.randf_range(-0.6, 0.6))
			var bit := out.cross(tang).normalized()
			bit = (bit + Vector3(0, -0.4, 0)).normalized()
			var hs := rng.randf_range(0.7, 1.0) * lerpf(1.0, 0.7, tt)
			var shade := clampf(0.5 + f * 0.4 + tt * 0.2, 0.2, 1.0)
			var col := Color(shade, 0.4 + tt * 0.6, 0, 0)
			var base: int = s[0].size()
			var corners := [p - tang * hs - bit * hs, p + tang * hs - bit * hs, p + tang * hs + bit * hs, p - tang * hs + bit * hs]
			var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for c in 4:
				s[0].append(corners[c])
				s[1].append(out)
				s[2].append(uvs[c])
				s[3].append(col)
			s[4].append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func _build_pine(near: MeshKit, far: MeshKit, rng: RandomNumberGenerator) -> void:
	# 曲がった幹
	var p := Vector3.ZERO
	var dir := Vector3(0.25, 1, 0.1).normalized()
	var pts: Array = [p]
	for k in 4:
		var l := 2.6
		var np: Vector3 = pts[-1] + dir * l
		pts.append(np)
		dir = (dir + Vector3(rng.randf_range(-0.45, 0.45), 0.25, rng.randf_range(-0.45, 0.45))).normalized()
	for k in pts.size() - 1:
		var r0 := lerpf(0.34, 0.12, float(k) / (pts.size() - 1))
		var r1 := lerpf(0.34, 0.12, float(k + 1) / (pts.size() - 1))
		_seg(near, "bark", pts[k], pts[k + 1], r0, r1, 7)
		_seg(far, "bark", pts[k], pts[k + 1], r0, r1, 4)
	# 枝と葉の塊（雲形）
	var pads := 6
	for k in pads:
		var base_pt: Vector3 = pts[mini(1 + k * 3 / pads, pts.size() - 1)].lerp(pts[mini(2 + k * 3 / pads, pts.size() - 1)], rng.randf())
		var a := rng.randf() * TAU
		var reach := rng.randf_range(1.2, 2.6)
		var tip := base_pt + Vector3(cos(a) * reach, rng.randf_range(0.2, 1.0), sin(a) * reach)
		if k == pads - 1:
			tip = pts[-1] + Vector3(0, 0.6, 0)
		_seg(near, "bark", base_pt, tip, 0.1, 0.05, 5)
		var rad := Vector3(rng.randf_range(1.6, 2.3), rng.randf_range(0.55, 0.75), rng.randf_range(1.6, 2.3))
		cards(near, tip + Vector3(0, 0.25, 0), rad, 20, 1.1, rng, 0.9, 0.6)
		far_blob(far, tip + Vector3(0, 0.25, 0), rad, 0.6)


static func _build_broadleaf(near: MeshKit, far: MeshKit, rng: RandomNumberGenerator, sakura: bool) -> void:
	var trunk_h := 3.2 if sakura else 4.5
	var crown_y := 6.0 if sakura else 8.8
	var crown_r := 4.6 if sakura else 4.0
	_seg(near, "bark", Vector3.ZERO, Vector3(0.15, trunk_h, 0.05), 0.42, 0.3, 8)
	_seg(far, "bark", Vector3.ZERO, Vector3(0.15, trunk_h, 0.05), 0.42, 0.3, 5)
	var top := Vector3(0.15, trunk_h, 0.05)
	var nb := 4
	var tips: Array = []
	for k in nb:
		var a := TAU * k / nb + rng.randf_range(-0.3, 0.3)
		var tip := top + Vector3(cos(a) * crown_r * 0.55, crown_y - trunk_h + rng.randf_range(-0.6, 0.8), sin(a) * crown_r * 0.55)
		_seg(near, "bark", top, tip, 0.22, 0.08, 6)
		tips.append(tip)
	var clusters := 9 if sakura else 8
	for k in clusters:
		var a := TAU * k / clusters + rng.randf()
		var rr := crown_r * rng.randf_range(0.25, 0.8)
		var c := Vector3(cos(a) * rr, crown_y + rng.randf_range(-1.0, 1.6) - rr * 0.2, sin(a) * rr)
		if k == 0:
			c = Vector3(0, crown_y + 1.5, 0)
		var rad := Vector3(2.3, 1.7, 2.3) * rng.randf_range(0.85, 1.15)
		if sakura:
			rad = Vector3(2.5, 1.4, 2.5) * rng.randf_range(0.85, 1.15)
		cards(near, c, rad, 22, 1.5, rng, 0.2, 0.8)
		far_blob(far, c, rad, 0.8)


static func _build_bamboo(near: MeshKit, far: MeshKit, rng: RandomNumberGenerator) -> void:
	for k in 9:
		var base := Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
		var H := rng.randf_range(9.0, 13.0)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 1, rng.randf_range(-0.12, 0.12)).normalized()
		var tip := base + lean * H + Vector3(lean.x, 0, lean.z) * 2.0
		var col := Color(1, 1, 1).lerp(Color(0.8, 0.85, 0.6), rng.randf())
		near.rod("bark", base, tip, rng.randf_range(0.05, 0.08), 5, col)
		far.rod("bark", base, tip, 0.07, 3, col)
		# 節
		for n in int(H / 1.2):
			var pp := base.lerp(tip, float(n) / (H / 1.2))
			near.cylinder("bark", Transform3D(Basis(), pp), 0.085, 0.085, 0.05, 5, col * 0.8, false)
		for n in 5:
			var tt := lerpf(0.5, 1.0, float(n) / 4.0)
			var c := base.lerp(tip, tt) + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
			cards(near, c, Vector3(1.1, 0.8, 1.1), 7, 1.0, rng, -0.3, 0.3 + tt, n == 4)
		far_blob(far, base.lerp(tip, 0.8), Vector3(1.6, 3.2, 1.6), 1.0)


static func _build_bush(near: MeshKit, far: MeshKit, rng: RandomNumberGenerator) -> void:
	for k in 3:
		var c := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.5, 0.8), rng.randf_range(-0.6, 0.6))
		var rad := Vector3(1.0, 0.75, 1.0) * rng.randf_range(0.8, 1.2)
		cards(near, c, rad, 12, 0.9, rng, 0.3, 0.3)
		far_blob(far, c, rad, 0.3)


static func _seg(kit: MeshKit, mat: String, a: Vector3, b: Vector3, r0: float, r1: float, segs: int) -> void:
	var d := b - a
	var l := d.length()
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	kit.cylinder(mat, Transform3D(Basis(x, y, z), a), r0, r1, l * 1.04, segs, Color(1, 1, 1), false, true)


static func rock_mesh(variant: int) -> ArrayMesh:
	var key := "rock%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n := FastNoiseLite.new()
	n.seed = 77 + variant * 13
	n.frequency = 0.9
	n.fractal_octaves = 3
	# 同じ位置の頂点（継ぎ目）は同じ変位になるよう位置ベースで
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + n.get_noise_3dv(v * 1.3) * 0.35
		v *= d
		if v.y < -0.3:
			v.y = -0.3 + (v.y + 0.3) * 0.3
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var am := st.commit()
	var m := WorldMaterials._building_mat("rock", 1.0, 1.0, 0.0)
	m.set_shader_parameter("detail", 0.6)
	m.set_shader_parameter("posterize", 3.0)
	m.set_shader_parameter("grime", 0.3)
	m.set_shader_parameter("desat", 0.5)
	am.surface_set_material(0, m)
	_mesh_cache[key] = am
	return am


## 草の株（数枚の細い葉）。高さ 1 に正規化（シェーダでスケール）
static func grass_clump_mesh(spacing: float) -> ArrayMesh:
	var key := "grass%.2f" % spacing
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var blades := 7
	for b in blades:
		var off := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)) * spacing * 0.9
		var a := rng.randf() * TAU
		var side := Vector3(cos(a), 0, sin(a))
		var fwd := Vector3(-sin(a), 0, cos(a))
		var lean := rng.randf_range(0.1, 0.35)
		var hgt := rng.randf_range(0.65, 1.0)
		var wid := rng.randf_range(0.03, 0.05)
		var base := verts.size()
		var segs := 3
		for s in segs + 1:
			var tt := float(s) / segs
			var w := wid * (1.0 - tt * 0.85)
			var c := off + fwd * lean * tt * tt + Vector3(0, hgt * tt, 0)
			var n := (fwd * -1.0 + Vector3.UP * 0.4).normalized()
			verts.append(c - side * w)
			verts.append(c + side * w)
			norms.append(n); norms.append(n)
			uvs.append(Vector2(0, 1.0 - tt)); uvs.append(Vector2(1, 1.0 - tt))
		for s in segs:
			var i0 := base + s * 2
			idx.append_array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = am
	return am

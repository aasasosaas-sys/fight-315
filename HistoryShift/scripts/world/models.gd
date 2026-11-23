class_name WorldModels
extends RefCounted
## Poly Haven の glTF モデル（tools/download_assets.py で任意取得）を読み込むユーティリティ。
## モデルが無い環境では空配列を返し、呼び出し側は手続き生成にフォールバックする。

const DIR := "res://assets/polyhaven/models/"
static var _cache := {}
static var enabled := true


static func path(id: String) -> String:
	return DIR + id + "/" + id + ".gltf"


static func has(id: String) -> bool:
	return not parts(id).is_empty()


## [[Mesh, Transform3D], ...]（モデル原点基準）。読めなければ []
static func parts(id: String) -> Array:
	if _cache.has(id):
		return _cache[id]
	var out: Array = []
	if enabled:
		var p := path(id)
		if ResourceLoader.exists(p):
			var ps = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
			if ps is PackedScene:
				var inst: Node = ps.instantiate()
				if inst:
					_walk(inst, Transform3D(), out)
					inst.free()
	for e in out:
		_fix_materials(e[0])
	_cache[id] = out
	return out


## 各パーツを独立したバリエーションとして返す（原点を XZ 中心・底面に合わせる）
## [[[Mesh, Transform3D]], ...]
static func variants(id: String, filter := "") -> Array:
	var key := id + "#v" + filter
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	for e in parts(id):
		var m: Mesh = e[0]
		if filter != "" and not String(m.resource_name).contains(filter) and not String(e[2]).contains(filter):
			continue
		var xf: Transform3D = e[1]
		var bb := xf * m.get_aabb()
		var c := bb.get_center()
		xf.origin -= Vector3(c.x, bb.position.y, c.z)
		out.append([[m, xf]])
	_cache[key] = out
	return out


## モデル全体の AABB
static func bounds(list: Array) -> AABB:
	var bb := AABB()
	var first := true
	for e in list:
		var b: AABB = (e[1] as Transform3D) * (e[0] as Mesh).get_aabb()
		if first:
			bb = b
			first = false
		else:
			bb = bb.merge(b)
	return bb


static func _walk(n: Node, xf: Transform3D, out: Array) -> void:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		# MeshInstance 側のマテリアル上書きをメッシュへ反映
		for s in mesh.get_surface_count():
			var ov := mi.get_surface_override_material(s)
			if ov:
				mesh = mesh.duplicate()
				mesh.surface_set_material(s, ov)
		out.append([mesh, x, String(n.name)])
	for c in n.get_children():
		_walk(c, x, out)


static func _fix_materials(mesh: Mesh) -> void:
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and bm.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				bm.alpha_scissor_threshold = 0.45
			if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## MultiMesh 群を作る（パーツごと）。xfs はインスタンス Transform の配列
static func multimesh_nodes(list: Array, xfs: Array, vis_end := 0.0, shadows := true) -> Array:
	var nodes: Array = []
	for e in list:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e[0]
		mm.instance_count = xfs.size()
		var lx: Transform3D = e[1]
		for i in xfs.size():
			mm.set_instance_transform(i, (xfs[i] as Transform3D) * lx)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 10.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes.append(mmi)
	return nodes

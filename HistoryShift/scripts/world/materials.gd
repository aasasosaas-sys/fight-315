class_name WorldMaterials
extends RefCounted
## 共有マテリアル・テクスチャ配列のキャッシュ。ワールドを作り直しても使い回す。

const TEX_DIR := "res://assets/polyhaven/textures/"
## 地形用テクスチャ配列のレイヤ順
const TERRAIN_LAYERS := ["grass", "forest", "rock", "dirt", "sand", "cobble", "asphalt", "concrete", "stonewall"]

## 建物用マテリアル: key -> [テクスチャ, 1枚あたりのメートル, roughness 補正, metallic]
const BUILD_MATS := {
	"plaster": ["plaster", 2.5, 1.0, 0.0],
	"wood": ["wood", 2.0, 1.0, 0.0],
	"darkwood": ["darkwood", 2.0, 1.0, 0.0],
	"rooftile": ["rooftile", 1.6, 0.85, 0.0],
	"thatch": ["thatch", 2.2, 1.0, 0.0],
	"stonewall": ["stonewall", 3.2, 1.0, 0.0],
	"brick": ["brick", 2.4, 1.0, 0.0],
	"concrete": ["concrete", 3.0, 1.0, 0.0],
	"tatami": ["tatami", 1.8, 1.0, 0.0],
	"bamboo": ["bamboo", 1.6, 1.0, 0.0],
	"cobble": ["cobble", 2.5, 1.0, 0.0],
	"asphalt": ["asphalt", 4.0, 1.0, 0.0],
	"earth": ["dirt", 3.0, 1.0, 0.0],
	"sand": ["sand", 3.0, 1.0, 0.0],
	"rock": ["rock", 4.0, 1.0, 0.0],
	"grassmat": ["grass", 3.0, 1.0, 0.0],
}

static var _tex_cache := {}
static var _mat_cache := {}
static var _arrays: Array = []
static var _shader_cache := {}


static func tex(key: String, kind: String) -> Texture2D:
	var k := key + "_" + kind
	if _tex_cache.has(k):
		return _tex_cache[k]
	var path := TEX_DIR + k + ".jpg"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[k] = t
	return t


static func shader(name: String) -> Shader:
	if not _shader_cache.has(name):
		_shader_cache[name] = load("res://shaders/%s.gdshader" % name)
	return _shader_cache[name]


## 地形用 Texture2DArray [albedo, normal, roughness]。作れない環境（ヘッドレス等）では空配列。
static func terrain_arrays() -> Array:
	if not _arrays.is_empty():
		return _arrays
	var out: Array = []
	for kind in ["diff", "nor_gl", "rough"]:
		var imgs: Array[Image] = []
		var fmt := -1
		var ok := true
		for key in TERRAIN_LAYERS:
			var t := tex(key, kind)
			if t == null:
				ok = false
				break
			var img := t.get_image()
			if img == null or img.is_empty():
				ok = false
				break
			if fmt == -1:
				fmt = img.get_format()
			if img.get_format() != fmt or img.get_width() != 1024:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(1024, 1024)
				img.generate_mipmaps()
			imgs.append(img)
		if not ok:
			return []
		# 形式が混在した場合は全部 RGBA8 に揃える
		var mixed := false
		for im in imgs:
			if im.get_format() != imgs[0].get_format():
				mixed = true
		if mixed:
			for i in imgs.size():
				var im := imgs[i].duplicate()
				if im.is_compressed():
					im.decompress()
				im.convert(Image.FORMAT_RGBA8)
				if not im.has_mipmaps():
					im.generate_mipmaps()
				imgs[i] = im
		var arr := Texture2DArray.new()
		var err := arr.create_from_images(imgs)
		if err != OK:
			return []
		out.append(arr)
	_arrays = out
	return _arrays


static func layer(key: String) -> int:
	return TERRAIN_LAYERS.find(key)


## 建物などに使う共有 StandardMaterial3D（頂点カラーで色付け）
static func get_mat(key: String) -> Material:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: Material
	if BUILD_MATS.has(key):
		var d: Array = BUILD_MATS[key]
		m = _building_mat(d[0], 1.0 / float(d[1]), d[2], d[3])
	else:
		match key:
			"metal":
				# 塗装/鋳鉄: コンクリートの粗さで汚れ・ムラ
				var sh := _building_mat("concrete", 0.5, 0.55, 0.75)
				sh.set_shader_parameter("albedo_tex", null)
				sh.set_shader_parameter("rough_add", -0.1)
				m = sh
			"gold":
				var sh := _building_mat("plaster", 0.6, 0.35, 1.0)
				sh.set_shader_parameter("albedo_tex", null)
				sh.set_shader_parameter("grime", 0.3)
				sh.set_shader_parameter("normal_depth", 0.3)
				m = sh
			"flat":
				var sh := _building_mat("concrete", 0.5, 1.0, 0.0)
				sh.set_shader_parameter("albedo_tex", null)
				m = sh
			"glass":
				var sm := StandardMaterial3D.new()
				sm.albedo_color = Color(0.16, 0.2, 0.24)
				sm.vertex_color_use_as_albedo = true
				sm.metallic = 0.6
				sm.roughness = 0.08
				m = sm
			"cloth":
				var sm := StandardMaterial3D.new()
				sm.vertex_color_use_as_albedo = true
				sm.albedo_texture = tex("plaster", "diff")
				sm.normal_enabled = true
				sm.normal_texture = tex("tatami", "nor_gl")
				sm.normal_scale = 0.3
				sm.uv1_scale = Vector3(0.8, 0.8, 1)
				sm.roughness = 0.95
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED
				sm.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
				m = sm
			"emissive":
				var sh := ShaderMaterial.new()
				sh.shader = shader("emissive")
				m = sh
			"wire":
				var sm := StandardMaterial3D.new()
				sm.albedo_color = Color(0.05, 0.05, 0.05)
				sm.roughness = 0.6
				m = sm
			"water":
				var sh := ShaderMaterial.new()
				sh.shader = shader("water")
				m = sh
			_:
				var sm := StandardMaterial3D.new()
				sm.vertex_color_use_as_albedo = true
				sm.roughness = 0.85
				m = sm
	_mat_cache[key] = m
	return m


static var _building_mats: Array = []


static func _building_mat(tex_key: String, uv_scale: float, rough: float, metal: float) -> ShaderMaterial:
	var sh := ShaderMaterial.new()
	sh.shader = shader("building")
	sh.set_shader_parameter("albedo_tex", tex(tex_key, "diff"))
	sh.set_shader_parameter("normal_tex", tex(tex_key, "nor_gl"))
	sh.set_shader_parameter("rough_tex", tex(tex_key, "rough"))
	sh.set_shader_parameter("uv_scale", uv_scale)
	sh.set_shader_parameter("rough_mul", rough)
	sh.set_shader_parameter("metallic", metal)
	sh.set_shader_parameter("macro_tex", macro_noise())
	if _world_params.size() == 3:
		sh.set_shader_parameter("height_tex", _world_params[0])
		sh.set_shader_parameter("half_size", _world_params[1])
		sh.set_shader_parameter("grid_n", _world_params[2])
	_building_mats.append(sh)
	return sh


static var _world_params: Array = []


## ワールド生成ごとに地形の高さテクスチャを建物マテリアルへ渡す（地面際の汚れ用）
static func set_world_params(height_tex: Texture2D, half_size: float, grid_n: int) -> void:
	_world_params = [height_tex, half_size, float(grid_n)]
	for sh in _building_mats:
		sh.set_shader_parameter("height_tex", height_tex)
		sh.set_shader_parameter("half_size", half_size)
		sh.set_shader_parameter("grid_n", float(grid_n))


static func macro_noise() -> Texture2D:
	if _tex_cache.has("_macro"):
		return _tex_cache["_macro"]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.008
	n.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = n
	_tex_cache["_macro"] = nt
	return nt

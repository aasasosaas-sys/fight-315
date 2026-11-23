class_name GameSettings
extends RefCounted
## 設定の保持・適用・保存（user://settings.cfg）。
## 適用先: EraWorld.quality / EraWorld.sdfgi（static var があれば）, Game.set_meta("quality"|"sdfgi"|"mouse_sensitivity"),
##         AudioServer の Master バス, ウィンドウモード。

const PATH := "user://settings.cfg"
const ERA_WORLD_PATH := "res://scripts/world/era_world.gd"
const QUALITY_NAMES := ["低", "中", "高"]

static var values := {
	"quality": 1,               # 0=低 1=中 2=高
	"sdfgi": true,
	"mouse_sensitivity": 1.0,   # 倍率（0.2〜3.0）
	"volume": 0.8,              # 0〜1
	"fullscreen": true,
	"master_mode": false,       # 技術完全習得モード（すべての技能 100・レシピ解禁。scripts/core/player_profile.gd）
	"start_armed": false,       # 最初から武装（時空銃を貸与。気軽に遊びたい人向け）
}
static var _loaded_from_file := false


static func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	_loaded_from_file = cfg.load(PATH) == OK
	if _loaded_from_file:
		for k in values:
			values[k] = cfg.get_value("settings", k, values[k])
	apply(_loaded_from_file)


static func save() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


static func apply(apply_window := true) -> void:
	var game := _game()
	if game:
		game.set_meta("quality", int(values["quality"]))
		game.set_meta("sdfgi", bool(values["sdfgi"]))
		game.set_meta("mouse_sensitivity", float(values["mouse_sensitivity"]))
	_set_era_world_static("quality", int(values["quality"]))
	_set_era_world_static("sdfgi", bool(values["sdfgi"]))
	_apply_sdfgi_live(bool(values["sdfgi"]))
	var vol := clampf(float(values["volume"]), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(0, vol <= 0.001)
	if apply_window and DisplayServer.get_name() != "headless":
		var want_fs: bool = values["fullscreen"]
		var mode := DisplayServer.window_get_mode()
		var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)


static func set_value(key: String, v: Variant) -> void:
	values[key] = v
	apply(key == "fullscreen")
	save()


static func _game() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("Game")
	return null


## EraWorld に static var があれば設定する（world 担当が未実装でも安全）
static func _set_era_world_static(prop: String, v: Variant) -> void:
	if not ResourceLoader.exists(ERA_WORLD_PATH):
		return
	var s = load(ERA_WORLD_PATH)
	if s == null or not (s is GDScript):
		return
	if not s.can_instantiate():
		return
	var has := false
	for p in (s as GDScript).get_script_property_list():
		if p.get("name", "") == prop:
			has = true
			break
	if not has:
		has = prop in s
	if has:
		s.set(prop, v)


## 現在のワールドの WorldEnvironment に SDFGI を即時反映
static func _apply_sdfgi_live(on: bool) -> void:
	var game := _game()
	if game == null:
		return
	var w = game.get("world")
	if w == null or not is_instance_valid(w):
		return
	for n in (w as Node).find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if we.environment:
			we.environment.sdfgi_enabled = on

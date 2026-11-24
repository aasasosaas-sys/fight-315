extends Node
## グローバル（autoload "Game"）。データ・歴史状態・入力設定・画面遷移を管理する。

signal world_changed(world)
## 目立つ破壊（歴史シミュレーションへの通知）。kind: "destroy" / "sink" / "fire" / "bridge"
## id: ランドマークのキー（"capital" "village" "temple" "port" "castle" "battlefield" "mountain" / 道沿い等は "town" / 川の橋は "river"）
## info: {era, pos, type, ...}（scripts/world/destruction.gd が発行）
## 自由探索での撃破も同じ信号で通知する：kind "kill"（id: 人物名・兵の名前、info.type: "figure" / "soldier" / "guardian"）→ ChaosTracker
signal chaos_event(kind: String, id: String, info: Dictionary)

var db: HistoryDB
var state: HistoryState
var chaos: ChaosTracker           # 自由探索の「歴史の揺らぎ」（scripts/core/chaos.gd）
var profile: PlayerProfile        # 主人公の技能・持ち物・所持金（時代をまたいで持ち越す。scripts/core/player_profile.gd）
var world: Node3D = null          # 現在の EraWorld
var player: Node3D = null         # 現在の Player
var input_blocked := false        # UI が前面にあるとき true

const COLLISION_WORLD := 1
const COLLISION_PLAYER := 2
const COLLISION_ENEMY := 4
const COLLISION_CIVILIAN := 8
const COLLISION_VEHICLE := 16
const COLLISION_PROP := 32
const COLLISION_DEBRIS := 64     # 建物の破片（プレイヤー・町人とは当たらない）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	# 破壊状態テクスチャの既定値（黒＝無傷）。ワールド生成時に Destruction が差し替える
	var blank := Image.create(4, 2, false, Image.FORMAT_RGBAF)
	blank.fill(Color(0, 0, 0, 0))
	RenderingServer.global_shader_parameter_set("destruct_tex", ImageTexture.create_from_image(blank))
	db = HistoryDB.load_all()
	state = HistoryState.new(db)
	state.load_save()
	chaos = ChaosTracker.new(db, state)
	chaos_event.connect(chaos.on_event)
	profile = PlayerProfile.new()
	profile.load_save()
	for e in db.errors:
		push_warning(e)
	for e in chaos.errors:
		push_warning(e)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_E], "vehicle": [KEY_F],
		"reload": [KEY_R], "pause": [KEY_ESCAPE], "yaw_left": [KEY_Q], "yaw_right": [KEY_E],
		"map": [KEY_M], "horn": [KEY_H], "camera_toggle": [KEY_V],
		# 破壊ツール（1:銃 2:焙烙玉 3:火薬樽/ダイナマイト 4:大筒 5:棒火矢、G:焙烙玉を投げる）
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4], "weapon_5": [KEY_5],
		"throw": [KEY_G],
		# 持ち物・技能・製作の画面（Tab / I、ゲームパッドは Back）
		"inventory": [KEY_TAB, KEY_I],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)
	for pair in [["weapon_next", MOUSE_BUTTON_WHEEL_DOWN], ["weapon_prev", MOUSE_BUTTON_WHEEL_UP]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var wb := InputEventMouseButton.new()
		wb.button_index = pair[1]
		InputMap.action_add_event(pair[0], wb)
	# ゲームパッド
	var pad := {"jump": JOY_BUTTON_A, "interact": JOY_BUTTON_X, "vehicle": JOY_BUTTON_Y, "reload": JOY_BUTTON_B, "pause": JOY_BUTTON_START, "sprint": JOY_BUTTON_LEFT_STICK,
		"weapon_next": JOY_BUTTON_RIGHT_SHOULDER, "weapon_prev": JOY_BUTTON_LEFT_SHOULDER, "throw": JOY_BUTTON_RIGHT_STICK,
		"inventory": JOY_BUTTON_BACK}
	for action in pad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[action]
		InputMap.action_add_event(action, jb)
	for pair in [["fire", JOY_AXIS_TRIGGER_RIGHT], ["aim", JOY_AXIS_TRIGGER_LEFT]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = pair[1]; jm.axis_value = 1.0
		InputMap.action_add_event(pair[0], jm)
	for pair in [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0], ["move_forward", JOY_AXIS_LEFT_Y, -1.0], ["move_back", JOY_AXIS_LEFT_Y, 1.0]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = pair[1]; jm.axis_value = pair[2]
		InputMap.action_add_event(pair[0], jm)


func set_world(w: Node3D) -> void:
	world = w
	world_changed.emit(w)


func lock_mouse(locked: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if locked else Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and profile:
		profile.flush()

extends Node
## グローバル（autoload "Game"）。データ・歴史状態・入力設定・画面遷移を管理する。

signal world_changed(world)

var db: HistoryDB
var state: HistoryState
var world: Node3D = null          # 現在の EraWorld
var player: Node3D = null         # 現在の Player
var input_blocked := false        # UI が前面にあるとき true

const COLLISION_WORLD := 1
const COLLISION_PLAYER := 2
const COLLISION_ENEMY := 4
const COLLISION_CIVILIAN := 8
const COLLISION_VEHICLE := 16
const COLLISION_PROP := 32


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	db = HistoryDB.load_all()
	state = HistoryState.new(db)
	state.load_save()
	for e in db.errors:
		push_warning(e)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_E], "vehicle": [KEY_F],
		"reload": [KEY_R], "pause": [KEY_ESCAPE], "yaw_left": [KEY_Q], "yaw_right": [KEY_E],
		"map": [KEY_M], "horn": [KEY_H], "camera_toggle": [KEY_V],
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
	# ゲームパッド
	var pad := {"jump": JOY_BUTTON_A, "interact": JOY_BUTTON_X, "vehicle": JOY_BUTTON_Y, "reload": JOY_BUTTON_B, "pause": JOY_BUTTON_START, "sprint": JOY_BUTTON_LEFT_STICK}
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

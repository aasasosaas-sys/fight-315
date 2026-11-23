extends Node
## 画面遷移とセッション管理。main.gd が "Flow" として add_child する。
## タイトル → 試験 → 採点ハブ → ブリーフィング → ワープ → Session（ミッション）→ ワープ → 改変結果 → ハブ … → エンディング

const SESSION_PATH := "res://scripts/mission/session.gd"

const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const ExamScreen := preload("res://scripts/ui/exam_screen.gd")
const HubScreen := preload("res://scripts/ui/hub_screen.gd")
const BriefingScreen := preload("res://scripts/ui/briefing_screen.gd")
const WarpScreen := preload("res://scripts/ui/warp_screen.gd")
const AftermathScreen := preload("res://scripts/ui/aftermath_screen.gd")
const EndingScreen := preload("res://scripts/ui/ending_screen.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const CreditsScreen := preload("res://scripts/ui/credits_screen.gd")

const BACKDROP_SECONDS := 24.0
const MIN_WARP_SECONDS := 1.9

var ui_layer: CanvasLayer        # 画面（layer 20）
var fade_layer: CanvasLayer      # バックドロップ切替の暗転（layer 10、UI の下）
var warp_layer: CanvasLayer      # ワープ演出（layer 100）
var root: Control
var screen: Control = null
var session: Node = null         # 実行中の Session（ミッション / 自由探索）
var backdrop: Node = null        # タイトル背景用の Session
var current := ""                # 表示中の画面名
var allow_backdrop := true       # false でタイトル背景を 2D に固定（テスト用）

var _fader: ColorRect
var _backdrop_idx := 0
var _backdrop_timer := 0.0
var _mission_q: Dictionary = {}
var _free_era := ""
var _return_to := "hub"
var _score_before := 0
var _correct_before := 0
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.load_and_apply()
	fade_layer = CanvasLayer.new(); fade_layer.layer = 10; add_child(fade_layer)
	_fader = ColorRect.new()
	_fader.color = Color(JSUI.INK, 0.0)
	JSUI.full_rect(_fader)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fader)
	ui_layer = CanvasLayer.new(); ui_layer.layer = 20; add_child(ui_layer)
	root = Control.new()
	root.name = "UIRoot"
	JSUI.full_rect(root)
	root.theme = JSUI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root)
	warp_layer = CanvasLayer.new(); warp_layer.layer = 100; add_child(warp_layer)
	_backdrop_idx = randi() % maxi(Game.db.eras.size(), 1)
	show_title()


func _process(delta: float) -> void:
	if current == "title" and backdrop != null:
		_backdrop_timer += delta
		if _backdrop_timer >= BACKDROP_SECONDS:
			_backdrop_timer = 0.0
			_rotate_backdrop()


static func session_available() -> bool:
	return _session_script() != null


## Session スクリプトが存在しコンパイル可能なら返す（gameplay 側が未完成でも落ちない）
static func _session_script() -> GDScript:
	if not ResourceLoader.exists(SESSION_PATH):
		return null
	var s := load(SESSION_PATH) as GDScript
	if s == null or not s.can_instantiate():
		return null
	return s


## Session の static 生成関数を呼ぶ。存在しなければ null。
static func _session_make(fn: String, args: Array) -> Node:
	var s := _session_script()
	if s == null:
		return null
	var found := false
	for m in s.get_script_method_list():
		if m.get("name", "") == fn:
			found = true
			break
	if not found:
		push_warning("Flow: Session.%s がありません" % fn)
		return null
	return s.callv(fn, args) as Node


# ================================================================== 画面切替
func _show(s: Control, name_: String) -> Control:
	var old := screen
	screen = s
	current = name_
	root.add_child(s)
	_ui_mode()
	if old and is_instance_valid(old):
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := old.create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.2)
		tw.tween_callback(old.queue_free)
		s.modulate.a = 0.0
		s.create_tween().tween_property(s, "modulate:a", 1.0, 0.25)
	return s


func _clear_screen() -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = null
	current = ""
	for c in root.get_children():
		c.queue_free()


func _ui_mode() -> void:
	Game.input_blocked = true
	Game.lock_mouse(false)
	root.visible = true


func _play_mode() -> void:
	Game.input_blocked = false
	Game.lock_mouse(true)


# ------------------------------------------------------------------ タイトル
func show_title() -> void:
	_end_session()
	get_tree().paused = false
	_start_backdrop()
	var t := TitleScreen.new()
	t.has_backdrop = backdrop != null
	t.backdrop_era = _backdrop_era_id()
	t.new_game.connect(start_new_game)
	t.continue_game.connect(func(): show_hub())
	t.free_roam.connect(func(id): start_free_roam(id, "title"))
	t.open_settings.connect(func(): SettingsScreen.open(root))
	t.open_credits.connect(func(): CreditsScreen.open(root))
	t.quit_game.connect(func(): get_tree().quit())
	_show(t, "title")


func _backdrop_era_id() -> String:
	if Game.db.eras.is_empty():
		return ""
	return Game.db.eras[_backdrop_idx % Game.db.eras.size()]["eraId"]


func _start_backdrop() -> void:
	if backdrop != null or not allow_backdrop:
		return
	var b := _session_make("start_backdrop", [_backdrop_era_id()])
	if b == null:
		return
	backdrop = b
	add_child(backdrop)
	_backdrop_timer = 0.0


func _rotate_backdrop() -> void:
	var tw := create_tween()
	tw.tween_property(_fader, "color:a", 1.0, 0.8)
	tw.tween_callback(func():
		_stop_backdrop()
		_backdrop_idx = (_backdrop_idx + 1) % maxi(Game.db.eras.size(), 1)
		if current == "title":
			_start_backdrop()
			if screen and screen.has_method("set_backdrop_era"):
				screen.set_backdrop_era(_backdrop_era_id()))
	tw.tween_interval(0.2)
	tw.tween_property(_fader, "color:a", 0.0, 1.0)


func _stop_backdrop() -> void:
	if backdrop and is_instance_valid(backdrop):
		if backdrop.has_method("end"):
			backdrop.end()
		else:
			backdrop.queue_free()
	backdrop = null


# ------------------------------------------------------------------ 試験
func start_new_game() -> void:
	Game.state.reset_all()
	HistoryState.delete_save()
	show_exam()


func show_exam() -> void:
	_stop_backdrop()
	var e := ExamScreen.new()
	e.submitted.connect(_on_exam_submitted)
	_show(e, "exam")


func _on_exam_submitted() -> void:
	# 未解答は時空の揺らぎでランダムにマーク（未解答のままだと満点に到達できないため）
	for q in Game.db.questions:
		if Game.state.answer(q) < 0:
			Game.state.set_answer(q, randi() % 4)
	Game.state.exam_submitted = true
	Game.state.save()
	show_hub("", true)


# ------------------------------------------------------------------ ハブ
func show_hub(select_qid := "", reveal := false) -> void:
	_stop_backdrop()
	_end_session()
	get_tree().paused = false
	if not Game.state.exam_submitted:
		show_exam()
		return
	var h := HubScreen.new()
	h.select_qid = select_qid
	h.reveal = reveal
	h.jump.connect(show_briefing)
	h.free_roam.connect(func(id): start_free_roam(id, "hub"))
	h.go_ending.connect(show_ending)
	h.go_title.connect(show_title)
	h.reset_all.connect(func():
		Game.state.reset_all()
		HistoryState.delete_save()
		show_title())
	h.open_settings.connect(func(): SettingsScreen.open(root))
	_show(h, "hub")


# ------------------------------------------------------------------ ブリーフィング
func show_briefing(q: Dictionary) -> void:
	var b := BriefingScreen.new()
	b.q = q
	b.depart.connect(func(): depart(q, b.method))
	b.back.connect(func(): show_hub(q["id"]))
	_show(b, "briefing")


# ================================================================== セッション
## ミッションへ出発する（ワープ演出 → Session.start_mission(q, 解答)）
func depart(q: Dictionary, method := 0) -> void:
	if _busy:
		return
	_mission_q = q
	_free_era = ""
	_return_to = "hub"
	_score_before = Game.state.score()
	_correct_before = Game.state.correct_count()
	var choice := Game.state.answer(q)
	var era: Dictionary = q["era"]
	_warp_into(era["eraName"], JSUI.era_years(era["eraId"]), func(): return _session_make("start_mission", [q, choice, method]))


func start_free_roam(era_id: String, return_to := "hub") -> void:
	if _busy:
		return
	_mission_q = {}
	_free_era = era_id
	_return_to = return_to
	_score_before = Game.state.score()
	_correct_before = Game.state.correct_count()
	var era := Game.db.get_era(era_id)
	_warp_into(era.get("eraName", era_id), "自由探索　" + JSUI.era_years(era_id), func(): return _session_make("start_free_roam", [era_id]))


func _warp_into(title: String, subtitle: String, make: Callable) -> void:
	_busy = true
	var w := WarpScreen.new()
	w.title = title
	w.subtitle = subtitle
	w.caption = "時空跳躍"
	warp_layer.add_child(w)
	var t0 := Time.get_ticks_msec()
	await w.covered
	_stop_backdrop()
	_clear_screen()
	Game.input_blocked = true
	await get_tree().process_frame
	await get_tree().process_frame
	var s = make.call()
	if s == null:
		_busy = false
		await _hold_warp(t0)
		w.finish()
		if _mission_q.is_empty():
			if _return_to == "title":
				show_title()
			else:
				show_hub()
			_notify_missing_session()
		else:
			_debug_simulate_or_fail()
		return
	session = s
	_connect_session(s)
	add_child(s)
	await _hold_warp(t0)
	w.finish()
	_busy = false
	get_tree().paused = false
	_play_mode()


func _hold_warp(t0: int) -> void:
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	if elapsed < MIN_WARP_SECONDS:
		await get_tree().create_timer(MIN_WARP_SECONDS - elapsed).timeout


func _connect_session(s: Node) -> void:
	if s.has_signal("completed"):
		s.connect("completed", _on_session_completed)
	if s.has_signal("failed"):
		s.connect("failed", _on_session_failed)
	if s.has_signal("aborted"):
		s.connect("aborted", _on_session_aborted)


func _end_session() -> void:
	if session and is_instance_valid(session):
		for sig in ["completed", "failed", "aborted"]:
			if session.has_signal(sig):
				for c in session.get_signal_connection_list(sig):
					if c["callable"].get_object() == self:
						session.disconnect(sig, c["callable"])
		if session.has_method("end"):
			session.end()
		else:
			session.queue_free()
	session = null


## ワープで現代（ハブ）へ戻り、next を呼んで次の画面を出す
func _warp_out(title: String, subtitle: String, next: Callable) -> void:
	if _busy:
		return
	_busy = true
	Game.input_blocked = true
	var w := WarpScreen.new()
	w.title = title
	w.subtitle = subtitle
	w.caption = "帰還"
	warp_layer.add_child(w)
	var t0 := Time.get_ticks_msec()
	await w.covered
	_end_session()
	get_tree().paused = false
	next.call()
	await get_tree().process_frame
	await _hold_warp(t0)
	w.finish()
	_busy = false


func _on_session_completed(changes: Array) -> void:
	var q := _mission_q
	call_deferred("_warp_out", "令和八年", "2026年 ― 改変された現代へ", func(): show_aftermath(q, changes))


func _on_session_failed(reason: String) -> void:
	var q := _mission_q
	call_deferred("_warp_out", "令和八年", "2026年 ― 現代へ帰還", func(): show_failure(q, reason))


func _on_session_aborted() -> void:
	var back_to := "hub" if not _mission_q.is_empty() else _return_to
	var qid: String = _mission_q.get("id", "")
	# 自由探索で歴史が揺らいでいたら、その後の歴史を見せてから戻る
	if _mission_q.is_empty() and Game.chaos and not Game.chaos.session_hits.is_empty():
		var hits: Array = Game.chaos.session_hits.duplicate()
		var era_id := _free_era
		call_deferred("_warp_out", "令和八年", "2026年 ― 揺らいだ現代へ", func(): show_chaos_aftermath(hits, era_id, back_to))
		return
	call_deferred("_warp_out", "令和八年", "2026年 ― 現代へ帰還", func():
		if back_to == "title":
			show_title()
		else:
			show_hub(qid))


# ------------------------------------------------------------------ 結果
func show_aftermath(q: Dictionary, changes: Array) -> void:
	var a := AftermathScreen.new()
	a.success = true
	a.q = q
	a.changes = changes
	a.score_before = _score_before
	a.correct_before = _correct_before
	a.to_hub.connect(func(): show_hub(q.get("id", "")))
	_show(a, "aftermath")


## 自由探索の混乱で変わった歴史（aftermath_screen の混乱版）
func show_chaos_aftermath(hits: Array, era_id: String, back_to := "hub") -> void:
	var a := AftermathScreen.new()
	a.success = true
	a.chaos_hits = hits
	a.chaos_era = era_id
	a.changes = Game.chaos.session_changes() if Game.chaos else []
	a.score_before = _score_before
	a.correct_before = _correct_before
	a.to_hub.connect(func():
		if back_to == "title" or not Game.state.exam_submitted:
			show_title()
		else:
			var broken: Array = Game.state.chaos_broken()
			show_hub(broken[0]["id"] if not broken.is_empty() else ""))
	_show(a, "aftermath")


func show_failure(q: Dictionary, reason: String) -> void:
	var a := AftermathScreen.new()
	a.success = false
	a.q = q
	a.reason = reason
	a.to_hub.connect(func(): show_hub(q.get("id", "")))
	a.retry.connect(func(): depart(q))
	_show(a, "failed")


func show_ending() -> void:
	var e := EndingScreen.new()
	e.to_title.connect(show_title)
	e.replay.connect(start_new_game)
	_show(e, "ending")


# ------------------------------------------------------------------ Session 未実装時
func _notify_missing_session() -> void:
	if screen:
		JSUI.toast(screen, "ゲームプレイ（scripts/mission/session.gd）がまだありません。", JSUI.SHU)


## gameplay 未実装でもフローを確認できるよう、デバッグビルドではミッションを自動成功扱いにする
func _debug_simulate_or_fail() -> void:
	var q := _mission_q
	if OS.is_debug_build():
		var m := Game.db.mission_for(q, Game.state.answer(q))
		var changes := Game.state.apply_change(q, Game.state.answer(q), m.get("title", ""))
		show_aftermath(q, changes)
		JSUI.toast(screen, "【デバッグ】Session 未実装のため、ミッションを自動成功として処理しました。", JSUI.GOLD)
	else:
		show_hub(q.get("id", ""))
		_notify_missing_session()


func _unhandled_input(event: InputEvent) -> void:
	# 設定はどの UI 画面からでも F10 で開ける
	if session == null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10:
		if not JSUI.modal_open(root):
			SettingsScreen.open(root)

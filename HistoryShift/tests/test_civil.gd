extends SceneTree
## ヘッドレス: godot --headless --path . -s tests/test_civil.gd
## 設定「民間人への危害（成人向け）」（scripts/core/civil_harm.gd・data/chaos_civil）を検証する。
##  1. オフ（既定）：町人は銃・爆発・乗り物・火で倒れない（従来どおり）。手配度も犠牲も増えない
##  2. 教育版（edu）・DLC 未所有：設定は強制オフ、data/chaos_civil は読まない
##  3. オン：プレイヤーが原因の被害で倒れ、少しして消える。敵の流れ弾では倒れない。手配度は最大になり下がりきらない
##  4. 除外の場面（史実の虐殺・戦災）では設定を無視する
##  5. 歴史：data/chaos_civil の全ルールが条件どおりの犠牲で発動し、basis（年の入った史実）を持つ
##  6. 流血・遺体の資産や処理を使っていない

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("FAIL ", msg)
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _spawn_civ(era := "edo") -> Civilian:
	var c := Civilian.spawn(root, Vector3(0, 0.5, 0), era, [])
	return c


func _run() -> void:
	var game: Node = root.get_node("Game")
	HistoryState.save_path = "user://test_civil_%d.json" % OS.get_process_id()
	CivilHarm.ledger_path = "user://test_civil_ledger_%d.json" % OS.get_process_id()
	CivilHarm.reset_ledger()
	var saved_val: bool = GameSettings.values.get("civil_harm", false)
	game.set("world", null)

	# ---- 1. オフ
	GameSettings.values["civil_harm"] = false
	_check(not CivilHarm.enabled(), "off by default")
	var c := _spawn_civ()
	await _frames(2)
	_check(not c.civil_hit(500.0, 0, c.global_position), "off: civil_hit refuses")
	c.take_hit(500.0, 0, c.global_position)
	var fake_hit := {"collider": c, "position": c.global_position + Vector3.UP, "normal": Vector3.UP}
	Player.apply_hit(self, fake_hit, Vector3.FORWARD, 500.0, 0)
	await _frames(2)
	_check(is_instance_valid(c) and not c.down, "off: civilian never goes down")
	_check(Wanted.civil_count == 0, "off: no casualty counted")
	c.queue_free()

	# ---- 2. 教育版・未所有
	MatureContent.force_edu = true
	_check(not MatureContent.is_unlocked(), "edu: locked")
	GameSettings.values["civil_harm"] = true
	_check(not CivilHarm.enabled(), "edu: forced off even if value true")
	CivilHarm.load_data(true)
	_check(CivilHarm.rules_for("edo").is_empty(), "edu: chaos_civil not loaded")
	_check(game.chaos.record("casualty", "village", {"era": "edo"}).is_empty(), "edu: casualty ignored by chaos")
	MatureContent.force_edu = false
	MatureContent.force_locked = true
	_check(not CivilHarm.enabled(), "dlc missing: off")
	MatureContent.force_locked = false
	CivilHarm.load_data(true)
	_check(not CivilHarm.rules_for("edo").is_empty(), "unlocked: chaos_civil loaded")

	# ---- 3. オン
	GameSettings.values["civil_harm"] = true
	_check(CivilHarm.enabled(), "on")
	var c2 := _spawn_civ()
	await _frames(2)
	_check(not c2.civil_hit(500.0, 1, c2.global_position), "on: enemy stray bullet does not count")
	Destruction.last_player_t = -99.0
	_check(not c2.civil_hit(500.0, -1, c2.global_position), "on: world damage without the player does not count")
	Player.apply_hit(self, {"collider": c2, "position": c2.global_position + Vector3.UP, "normal": Vector3.UP}, Vector3.FORWARD, 500.0, 0)
	_check(c2.down, "on: player's shot downs a civilian")
	_check(Wanted.civil_count == 1, "on: casualty counted")
	_check(Wanted.heat >= 5.0, "on: wanted jumps to max")
	_check(CivilHarm.era_total("edo") == 1, "on: ledger")
	Wanted.clear()
	_check(Wanted.heat >= Wanted.CIVIL_FLOOR, "on: wanted stays high after clear")
	_check(not c2.is_in_group("civilian") and c2.collision_layer == 0, "on: downed civilian is inert")
	await create_timer(4.4).timeout
	_check(not is_instance_valid(c2), "on: downed civilian fades and is removed (no corpse)")
	# 爆発（team 0）・火（-2）・瓦礫（-3、原因つき）
	var c3 := _spawn_civ()
	await _frames(2)
	c3.take_hit(500.0, 0, c3.global_position)
	_check(c3.down, "on: explosion downs a civilian")
	var c4 := _spawn_civ()
	await _frames(2)
	_check(not c4.civil_hit(500.0, -2, c4.global_position, Vector3.ZERO, "world"), "on: natural fire does not count")
	_check(c4.civil_hit(500.0, -3, c4.global_position, Vector3.ZERO, "player_indirect") and c4.down, "on: player-caused debris counts")
	_check(CivilHarm.unrest_level() >= 1, "on: unrest level rises")

	# ---- 4. 除外
	_check(CivilHarm.excluded("showa", "village"), "excl: showa shitamachi (air raid)")
	_check(CivilHarm.excluded("heian", "mountain"), "excl: hieizan")
	_check(CivilHarm.excluded("edo", "capital", "edo_05", 0, "和議の仲介"), "excl: shimabara mission")
	_check(not CivilHarm.excluded("edo", "capital", "edo_05", 0, "説得"), "excl: other edo_05 method not excluded")
	_check(CivilHarm.excluded("showa", "capital", "showa_06", 1, "x"), "excl: wartime showa mission")
	_check(not CivilHarm.excluded("edo", "village"), "excl: nihonbashi not excluded")
	var sess := _FakeSession.new()
	sess.mode = "mission"
	sess.question = {"id": "showa_05"}
	sess.choice = 1
	sess.mission = {"method": "x"}
	root.add_child(sess)
	var c5 := _spawn_civ("showa")
	await _frames(2)
	_check(not c5.civil_hit(500.0, 0, c5.global_position) and not c5.down, "excl: wartime mission civilian unharmed")
	sess.mode = "backdrop"
	_check(not c5.civil_hit(500.0, 0, c5.global_position), "excl: title backdrop")
	sess.queue_free()
	c5.queue_free()
	await _frames(2)
	var tr := ChaosTracker.new(game.db, HistoryState.new(game.db))
	tr.begin_session("showa")
	_check(tr.record("casualty", "village", {"era": "showa", "landmark": "village", "count": 50, "role": "町人"}).is_empty(), "excl: chaos ignores excluded landmark")

	# ---- 5. 歴史ルール
	var n_rules := 0
	for era in ["jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"]:
		for r in CivilHarm.rules_for(era):
			n_rules += 1
			var st := HistoryState.new(game.db)
			var t := ChaosTracker.new(game.db, st)
			t.begin_session(era)
			var trig: Dictionary = r["trigger"]
			var at: String = str(trig["at"][0]) if trig.get("at") is Array else str(trig.get("at", "town"))
			if CivilHarm.excluded(era, at):
				at = "town"
			var role: String = str(trig["role"]) if trig.has("role") else CivilHarm.role_for(era, at)
			var got := false
			for i in int(trig.get("min", 1)):
				for h in t.record("casualty", at, {"era": era, "landmark": at, "role": role, "count": 1}):
					if h.get("id", "") == r["id"]:
						got = true
						_check(h.get("civil", false), "%s: hit flagged civil" % r["id"])
			_check(got and t.fired.has(r["id"]), "%s: fires at its threshold" % r["id"])
			var in_mods := false
			for m in st.chaos_mods:
				if m["rule"] == r["id"]:
					in_mods = true
			_check(in_mods, "%s: vars recorded" % r["id"])
			_check(not r.has("force"), "%s: no forced exam answers" % r["id"])
			var basis := str(r.get("basis", ""))
			_check(basis.length() > 15 and RegEx.create_from_string("[0-9]{2,4}年").search(basis) != null, "%s: basis with a dated fact" % r["id"])
			for k in (r["vars"] as Dictionary):
				_check(absi(int(r["vars"][k])) <= 20, "%s: small effect %s" % [r["id"], k])
	_check(n_rules >= 30, "rules loaded (%d)" % n_rules)
	# 名所の犠牲が少なければ発動しない
	var t2 := ChaosTracker.new(game.db, HistoryState.new(game.db))
	t2.begin_session("edo")
	t2.record("casualty", "village", {"era": "edo", "landmark": "village", "role": "商人"})
	_check(not t2.fired.has("cv_ed_nihonbashi"), "threshold not reached with one casualty")
	_check(t2.record("casualty", "village", {"era": "heian"}).is_empty(), "other era ignored")

	# ---- 6. 流血・遺体なし
	var src := FileAccess.get_file_as_string("res://scripts/mission/civilian.gd") + FileAccess.get_file_as_string("res://scripts/core/civil_harm.gd")
	for bad in ["blood", "decal", "Decal", "ragdoll", "corpse", "PhysicalBone"]:
		_check(not (bad in src), "no gore: %s" % bad)
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var i0 := psrc.find("civil_hit(dmg")
	_check(i0 > 0 and psrc.find("Effects.spark", i0) < psrc.find("Effects.blood", i0), "apply_hit: civilian branch uses spark, not blood")
	for f in DirAccess.get_files_at("res://data/chaos_civil"):
		var s := FileAccess.get_file_as_string("res://data/chaos_civil/" + f)
		_check(not ("res://" in s) and not ("assets/" in s), "no assets referenced in %s" % f)

	GameSettings.values["civil_harm"] = saved_val
	CivilHarm.reset_ledger()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HistoryState.save_path))
	print("test_civil: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)


class _FakeSession extends Node:
	var mode := "free"
	var question: Dictionary = {}
	var choice := 0
	var mission: Dictionary = {}

	func _ready() -> void:
		add_to_group("session")

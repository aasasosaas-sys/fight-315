class_name CraftUI
extends CanvasLayer
## ゲーム中の画面：工房（弟子入り・稽古・製作・修理・手伝い・技術を教える）／店（売り買い）／蔵の中身／
## 持ち物・技能・製作・メモ（Tab / I / ゲームパッド Back）。キーボード・ゲームパッドで操作できる（ボタンにフォーカス）。
## LB/RB（マウスホイール）で持ち物画面のタブを切り替え。Esc / Tab で閉じる。

signal closed
signal course_requested(station: CraftStation, lesson: Dictionary)

var era_id := ""
var mgr: Node = null                # CraftWorld
var _root: Control
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _msg: Label
var _station: CraftStation = null
var _page := ""
var _tab := 0
var _game: Minigame = null
var _first: Control = null

const TABS := ["持ち物", "技能", "製作", "メモ"]


func _ready() -> void:
	layer = 13
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.02, 0.01, 0.04, 0.6)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = JSUI.panel(JSUI.sb(Color(JSUI.INK2, 0.97), 20, 2, Color(JSUI.GOLD, 0.5), 24, 28))
	_panel.custom_minimum_size = Vector2(1240, 0)
	center.add_child(_panel)
	var v := JSUI.vbox(10)
	_panel.add_child(v)
	_title = JSUI.label("", 38, JSUI.GOLD, JSUI.serif_bold())
	v.add_child(_title)
	_sub = JSUI.label("", 19, JSUI.MUTED, null, true)
	_sub.custom_minimum_size = Vector2(1180, 0)
	v.add_child(_sub)
	v.add_child(JSUI.hline(Color(JSUI.GOLD, 0.25)))
	_msg = JSUI.label("", 22, JSUI.CYAN, JSUI.sans_bold(), true)
	_msg.custom_minimum_size = Vector2(1180, 0)
	v.add_child(_msg)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(1180, 620)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = JSUI.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func prof() -> PlayerProfile:
	return Game.profile


func _show() -> void:
	_root.visible = true
	add_to_group("game_modal")   # 開いている間は Esc でポーズしない（HUD）
	Game.input_blocked = true
	Game.lock_mouse(false)


func close() -> void:
	if _game and is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_root.visible = false
	_station = null
	remove_from_group("game_modal")
	Game.input_blocked = false
	Game.lock_mouse(true)
	closed.emit()


func _unhandled_input(ev: InputEvent) -> void:
	if not is_open():
		return
	if ev.is_action_pressed("pause") or (ev.is_action_pressed("inventory") and _page == "inventory"):
		get_viewport().set_input_as_handled()
		if _game:
			return
		close()
	elif _page == "inventory" and _game == null:
		if ev.is_action_pressed("weapon_next"):
			get_viewport().set_input_as_handled()
			_tab = (_tab + 1) % TABS.size()
			open_inventory()
		elif ev.is_action_pressed("weapon_prev"):
			get_viewport().set_input_as_handled()
			_tab = (_tab + TABS.size() - 1) % TABS.size()
			open_inventory()


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	_first = null


func _btn(t: String, cb: Callable, enabled := true, kind := "normal", parent: Node = null, w := 0) -> Button:
	var b := JSUI.button(t, kind, 22, w)
	b.disabled = not enabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func(): UISfx.play("click"); cb.call())
	(parent if parent else _body).add_child(b)
	if _first == null and enabled:
		_first = b
	return b


func _lbl(t: String, size := 21, col := JSUI.TEXT, parent: Node = null, bold := false) -> Label:
	var l := JSUI.label(t, size, col, JSUI.sans_bold() if bold else null, true)
	l.custom_minimum_size = Vector2(0, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent else _body).add_child(l)
	return l


func _focus() -> void:
	if _first and is_instance_valid(_first):
		_first.call_deferred("grab_focus")
	_scroll.scroll_vertical = 0


func _money() -> String:
	return CraftDB.money_text(prof().money, era_id)


# ================================================================== 工房
func open_workshop(st: CraftStation, msg := "") -> void:
	_station = st
	_page = "workshop"
	_show()
	_clear()
	var d := st.def
	_title.text = "%s　―　%s" % [d.get("name", ""), d.get("teacher", "")]
	_sub.text = "【史実】" + str(d.get("basis", ""))
	_msg.text = msg if msg != "" else "%s「よう来た。何を習いたい？」　所持金 %s" % [d.get("teacher", "師匠"), _money()]
	var teaches: Dictionary = d.get("teaches", {})
	var parts: PackedStringArray = []
	for k in teaches:
		parts.append("%s %d／上限 %d" % [Skills.skill_name(k), int(prof().level(k)), int(teaches[k])])
	_lbl("教われる技：" + "　".join(parts), 20, JSUI.MUTED)
	for les in d.get("lessons", []):
		var sk := str(les.get("skill", ""))
		var cap := float(teaches.get(sk, 100))
		var lv := prof().raw_level(sk)
		var done := lv >= cap
		var label := "弟子入り・稽古：%s（%s %d → 上限 %d）" % [les.get("title", ""), Skills.skill_name(sk), int(lv), int(cap)]
		if PlayerProfile.master_mode():
			label = "稽古：%s（技術完全習得モード：稽古は不要だが遊べる）" % les.get("title", "")
		elif done:
			label = "稽古：%s（免許皆伝――ここで教われることはもうない）" % les.get("title", "")
		var l2: Dictionary = les
		_btn(label, func(): _start_lesson(l2), true, "gold")
	var sts: Array = d.get("stations", [])
	if not sts.is_empty():
		_btn("製作する（%s）" % "・".join(sts.map(func(x): return CraftDB.station_name(str(x)))), func(): open_crafting(st))
	var w := prof().weapon()
	if not w.is_empty() and float(w.get("stats", {}).get("max_dur", 0)) > 0.0 and float(w["dur"]) < float(w["stats"]["max_dur"]):
		var cost := _repair_cost(w)
		_btn("手にしている%sを直してもらう（%s）" % [prof().item_label(w), CraftDB.money_text(cost, era_id)], func(): _repair(w, cost), prof().money >= cost)
	if d.has("job"):
		var job: Dictionary = d["job"]
		_btn("手伝いをする：%s（日銭 %s まで）" % [job.get("text", ""), CraftDB.money_text(int(job.get("pay", 500)), era_id)], func(): _start_job(job))
	var teachable := prof().skills_summary(40.0)
	if not teachable.is_empty():
		_btn("職人たちに未来の技を教える（歴史が動くかもしれない）", _teach_page)
	_btn("立ち去る", close, true, "ghost")
	_focus()


func _repair_cost(w: Dictionary) -> int:
	var miss := float(w["stats"].get("max_dur", 0)) - float(w.get("dur", 0))
	return int(ceil(miss * maxf(4.0, float(CraftDB.item(str(w["id"])).get("price", 1000)) / 1500.0)))


func _repair(w: Dictionary, cost: int) -> void:
	if not prof().spend(cost):
		return
	w["dur"] = float(w["stats"].get("max_dur", 0))
	prof().save()
	open_workshop(_station, "%s「ほれ、元どおりだ」" % _station.def.get("teacher", ""))


func _teach_page() -> void:
	_clear()
	_msg.text = "どの技を教える？（未来の知識が広まると、この時代の技術・軍事・暮らしが変わる）"
	for s in prof().skills_summary(40.0):
		var sid := str(s["id"])
		var lv := float(s["level"])
		_btn("%s（%s %d）" % [s["name"], s["rank"], int(lv)], func(): _teach(sid, lv))
	_btn("戻る", func(): open_workshop(_station), true, "ghost")
	_focus()


func _teach(sid: String, lv: float) -> void:
	var msg := ""
	if Game.chaos and Game.chaos.is_active():
		var hit: Dictionary = Game.chaos.act("teach", _station.landmark, {"skill": sid, "level": int(lv)})
		msg = "職人たちは%sの技を夢中で書き留めた。" % Skills.skill_name(sid) + ("" if not hit.is_empty() else "（もう教えたことだ）")
	else:
		msg = "職人たちは感心したが、任務中の今は歴史を動かせない。"
	prof().practice("rhetoric", 0.5)
	open_workshop(_station, msg)


# ------------------------------------------------------------------ 稽古
func _start_lesson(les: Dictionary) -> void:
	var game := str(les.get("game", "hammer"))
	var sk := str(les.get("skill", ""))
	if game == "course":
		var st := _station
		close()
		course_requested.emit(st, les)
		return
	_run_minigame(game, les, prof().level(sk), func(score: float): _lesson_done(les, score))


func _lesson_done(les: Dictionary, score: float) -> void:
	var sk := str(les.get("skill", ""))
	var cap := float(_station.def.get("teaches", {}).get(sk, 100))
	var before := prof().raw_level(sk)
	var got := prof().train(sk, 9.0 * (0.35 + 0.65 * score), cap)
	var wid := str(_station.def.get("id", ""))
	prof().lessons[wid] = int(prof().lessons.get(wid, 0)) + 1
	prof().save()
	var who := str(_station.def.get("teacher", "師匠"))
	var line := "見事だ" if score > 0.8 else ("筋がいい" if score > 0.55 else ("まだまだだな" if score > 0.3 else "……やり直しだ"))
	var msg := "%s「%s」　出来 %d 点　%s %.1f → %.1f" % [who, line, roundi(score * 100), Skills.skill_name(sk), before, before + got]
	if PlayerProfile.master_mode():
		msg = "%s「%s」　出来 %d 点（技術完全習得モード中）" % [who, line, roundi(score * 100)]
	elif got <= 0.0:
		msg += "（ここで教われるのは %d まで）" % int(cap)
	open_workshop(_station, msg)


func _start_job(job: Dictionary) -> void:
	var les := {"title": str(job.get("text", "手伝い")), "text": "うまくやれば日銭がはずむ。", "steps": job.get("steps", []), "target": job.get("target", [75, 10, 15]), "labels": job.get("labels", [])}
	if (les["steps"] as Array).is_empty():
		var first: Array = _station.def.get("lessons", [])
		for l in first:
			if l.has("steps"):
				les["steps"] = l["steps"]
				break
	var sk: String = str(_station.def.get("teaches", {}).keys()[0]) if not (_station.def.get("teaches", {}) as Dictionary).is_empty() else "rhetoric"
	_run_minigame(str(job.get("game", "hammer")), les, prof().level(sk), func(score: float):
		var pay := int(float(job.get("pay", 500)) * (0.3 + 0.7 * score))
		prof().add_money(pay)
		prof().practice(sk, 1.0)
		open_workshop(_station, "手伝いの駄賃 %s をもらった（所持金 %s）" % [CraftDB.money_text(pay, era_id), _money()]))


func _run_minigame(game: String, les: Dictionary, lv: float, on_done: Callable) -> void:
	_clear()
	_msg.text = ""
	var mg := Minigame.new()
	mg.setup(game, les, lv)
	_body.add_child(mg)
	_game = mg
	mg.finished.connect(func(score: float):
		await get_tree().create_timer(0.6, true, false, true).timeout
		if _game == mg:
			_game = null
			mg.queue_free()
			on_done.call(score))


## テスト用：今の稽古を score で終える
func finish_minigame(score: float) -> void:
	if _game and is_instance_valid(_game):
		_game.finish(score)


# ================================================================== 製作
func _stations_here() -> Array:
	if _station == null:
		return []
	return _station.def.get("stations", [])


func open_crafting(st: CraftStation, msg := "") -> void:
	_station = st
	_page = "crafting"
	_show()
	_clear()
	_title.text = "製作　―　%s" % (st.display_name if st else "手持ちの道具で")
	_sub.text = "品質＝0.15＋0.6×主技能＋0.15×補助技能＋材料の質＋仕上げの出来。等級：粗悪／並／上／名工。未来の技術は、技能が十分なら過去でも作れる（職人の前で作ると技術が漏れる）。"
	_msg.text = msg if msg != "" else "所持金 %s" % _money()
	var sts: Array = _stations_here() if st else []
	var list: Array = []
	for r in CraftDB.recipes():
		var rs := str(r.get("station", "any"))
		if rs == "any" or rs in sts:
			list.append(r)
	_recipe_rows(list, sts)
	_btn("戻る" if st else "閉じる", (func(): open_workshop(st)) if st else close, true, "ghost")
	_focus()


func _recipe_rows(list: Array, sts: Array) -> void:
	for r in list:
		var rs := str(r.get("station", "any"))
		var station := rs if rs != "any" else (str(sts[0]) if not sts.is_empty() else "any")
		var chk := Crafting.can_craft(prof(), r, era_id, rs)
		var out := str(r.get("out", ""))
		var q := Crafting.quality(prof(), r, 0.5, 0.5)
		var mats: PackedStringArray = []
		for m in r.get("mats", {}):
			mats.append("%s %d/%d" % [CraftDB.item_name(m), prof().count(m), int(r["mats"][m])])
		var req: PackedStringArray = []
		for k in r.get("skill", {}):
			req.append("%s %d" % [Skills.skill_name(k), int(r["skill"][k])])
		var row := JSUI.panel(JSUI.sb(Color(1, 1, 1, 0.03), 10, 1, Color(1, 1, 1, 0.06), 0, 10))
		var h := JSUI.hbox(14)
		row.add_child(h)
		var info := JSUI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var head := "%s ×%d　見込み：%s" % [CraftDB.item_name(out), int(r.get("count", 1)), Crafting.grade(q)]
		if chk[2]:
			head += "　［未来の技術］"
		_lbl(head, 23, Crafting.grade_color(q), info, true)
		_lbl("材料：%s　　必要：%s" % ["、".join(mats), "、".join(req) if not req.is_empty() else "なし"], 18, JSUI.MUTED, info)
		if not chk[0]:
			_lbl(str(chk[1]), 18, JSUI.SHU, info)
		elif r.has("basis"):
			_lbl("【史実】" + str(r["basis"]), 17, JSUI.DIM, info)
		var rid := str(r.get("id", ""))
		var b := JSUI.button("作る", "primary", 22, 140)
		b.disabled = not chk[0]
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): UISfx.play("confirm"); _do_craft(rid, rs))
		h.add_child(b)
		if _first == null and chk[0]:
			_first = b
		_body.add_child(row)


func _do_craft(rid: String, station: String) -> void:
	var r := CraftDB.recipe(rid)
	if station in ["forge", "gunsmith"]:
		_run_minigame("hammer", {"title": "仕上げ：" + CraftDB.item_name(str(r.get("out", ""))), "text": "仕上げの出来が品質に効く。拍子よく打て。", "skill": r.get("skill", {}).keys()[0] if not (r.get("skill", {}) as Dictionary).is_empty() else ""},
			prof().level(str(r.get("skill", {}).keys()[0]) if not (r.get("skill", {}) as Dictionary).is_empty() else "katana_smith"),
			func(score: float): _craft_now(rid, station, score))
	else:
		_craft_now(rid, station, 0.5)


func _craft_now(rid: String, station: String, score: float) -> void:
	var res := Crafting.craft(prof(), rid, era_id, station, score)
	var msg := ""
	if not res["ok"]:
		msg = "作れなかった：" + str(res["reason"])
	else:
		var it: Dictionary = res["item"]
		msg = "%s ×%d が仕上がった！　等級：%s（品質 %d）" % [CraftDB.item_name(str(res["out"])), int(res["count"]), res["grade"], roundi(float(res["q"]) * 100)]
		if not it.is_empty():
			msg += "\n" + Crafting.stats_text(it)
		if res["anachronism"] and _station != null:
			var gap := CraftDB.anachronism_gap(str(res["out"]), era_id)
			Game.chaos_event.emit("anachronism", str(res["out"]), {"era": era_id, "item": str(res["out"]), "gap": gap, "cause": "craft",
				"type": CraftDB.item_type(str(res["out"])), "landmark": _station.landmark})
			msg += "\n職人たちが息をのんで見ていた……（未来の技術が漏れた）"
	open_crafting(_station, msg)


# ================================================================== 店
func open_shop(st: CraftStation, msg := "", sell := false) -> void:
	_station = st
	_page = "shop"
	_show()
	_clear()
	_title.text = st.display_name
	var cur := CraftDB.currency(era_id)
	_sub.text = "【お金】%s：%s　話術が高いほど安く買えて高く売れる（買値 ×%.2f・売値 ×%.2f）" % [cur.get("name", ""), cur.get("note", ""), Skills.buy_mult(prof().level("rhetoric")), Skills.sell_mult(prof().level("rhetoric"))]
	_msg.text = msg if msg != "" else "所持金 %s" % _money()
	var tabs := JSUI.hbox(10)
	_body.add_child(tabs)
	_btn("買う", func(): open_shop(st, "", false), true, "cyan" if not sell else "normal", tabs, 160)
	_btn("売る", func(): open_shop(st, "", true), true, "cyan" if sell else "normal", tabs, 160)
	_btn("立ち去る", close, true, "ghost", tabs, 160)
	if not sell:
		for id in st.def.get("stock", []):
			var it := CraftDB.item(id)
			if it.is_empty():
				continue
			var n := 10 if str(it.get("type", "")) == "ammo" else 1
			var price := int(ceil(float(it.get("price", 100)) * n * Skills.buy_mult(prof().level("rhetoric"))))
			var sid := str(id)
			var label := "%s%s　%s　― %s" % [it.get("name", id), " ×%d" % n if n > 1 else "", CraftDB.money_text(price, era_id), it.get("desc", "")]
			_btn(label, func(): _buy(sid, n, price), prof().money >= price)
	else:
		for w in prof().weapons():
			if w.get("loan", false):
				continue
			var p := _sell_price(str(w["id"]), float(w.get("q", 0.5)))
			var uid := int(w["uid"])
			_btn("%s　→ %s" % [prof().item_label(w), CraftDB.money_text(p, era_id)], func(): _sell_inst(uid, p))
		for id in prof().stacks.keys():
			var it2 := CraftDB.item(id)
			if it2.get("keep", false) or int(it2.get("price", 0)) <= 0:
				continue
			var have := prof().count(id)
			if have - int(prof().loan_stacks.get(id, 0)) <= 0:
				continue
			var p2 := _sell_price(str(id), prof().stack_quality(id))
			var sid2 := str(id)
			_btn("%s ×%d　1つ → %s" % [it2.get("name", id), have, CraftDB.money_text(p2, era_id)], func(): _sell_stack(sid2, p2))
	_focus()


func _sell_price(id: String, q: float) -> int:
	var it := CraftDB.item(id)
	if it.has("money"):
		return int(it["money"])   # 小判・千両箱はそのままお金
	return maxi(1, int(float(it.get("price", 100)) * Skills.sell_mult(prof().level("rhetoric")) * (0.5 + q)))


func _buy(id: String, n: int, price: int) -> void:
	if not prof().spend(price):
		return
	prof().add(id, n, 0.5)
	prof().practice("rhetoric", 0.2)
	open_shop(_station, "%s を買った（所持金 %s）" % [CraftDB.item_name(id), _money()])


func _sell_inst(uid: int, p: int) -> void:
	var it := prof().remove_instance(uid)
	if it.is_empty():
		return
	prof().add_money(p)
	prof().practice("rhetoric", 0.2)
	open_shop(_station, "%s を売った（所持金 %s）" % [CraftDB.item_name(str(it["id"])), _money()], true)


func _sell_stack(id: String, p: int) -> void:
	if not prof().take(id, 1):
		return
	prof().add_money(p)
	prof().practice("rhetoric", 0.1)
	open_shop(_station, "%s を売った（所持金 %s）" % [CraftDB.item_name(id), _money()], true)


# ================================================================== 蔵
func open_loot(st: CraftStation, got: Array, heat: float) -> void:
	_station = st
	_page = "loot"
	_show()
	_clear()
	_title.text = st.display_name + "を探った"
	_sub.text = "盗みは見つかる。手配度 +%.1f" % heat
	_msg.text = "何も残っていなかった……" if got.is_empty() else "手に入れた："
	for g in got:
		_lbl("・%s ×%d" % [CraftDB.item_name(str(g["id"])), int(g["n"])], 24, JSUI.TEXT)
	_btn("閉じる", close, true, "primary")
	_focus()


# ================================================================== 持ち物・技能・製作・メモ
func open_inventory(msg := "") -> void:
	_station = null
	_page = "inventory"
	_show()
	_clear()
	_title.text = "時空鞄　―　%s" % TABS[_tab]
	_sub.text = "LB / RB（マウスホイール）でタブ切替　Tab / Esc で閉じる　技術完全習得モード：%s" % ("オン" if PlayerProfile.master_mode() else "オフ")
	_msg.text = msg if msg != "" else "所持金 %s　　手にしている：%s" % [_money(), prof().item_label(prof().weapon()) if not prof().weapon().is_empty() else "素手"]
	var tabs := JSUI.hbox(10)
	_body.add_child(tabs)
	for i in TABS.size():
		var ti := i
		_btn(TABS[i], func(): _tab = ti; open_inventory(), true, "cyan" if i == _tab else "normal", tabs, 150)
	_btn("閉じる", close, true, "ghost", tabs, 150)
	_first = null
	match _tab:
		0: _inv_items()
		1: _inv_skills()
		2: _inv_craft()
		3: _inv_memo()
	if _first == null and tabs.get_child_count() > 0:
		_first = tabs.get_child(_tab)
	_focus()


func _inv_items() -> void:
	_lbl("武器", 26, JSUI.GOLD, null, true)
	var fists := JSUI.hbox(12)
	_body.add_child(fists)
	_btn("手に取る" if prof().equipped >= 0 else "手にしている", func(): _equip(-1), prof().equipped >= 0, "normal", fists, 170)
	_lbl("素手　― 殴る・蹴る（剣術）", 21, JSUI.TEXT, fists)
	for w in prof().weapons():
		var uid := int(w["uid"])
		var row := JSUI.hbox(12)
		_body.add_child(row)
		_btn("手に取る" if prof().equipped != uid else "手にしている", func(): _equip(uid), prof().equipped != uid, "normal", row, 170)
		var info := JSUI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var head := prof().item_label(w)
		if str(w.get("maker", "")) == "あなた":
			head += "　あなたの作"
		var gap := CraftDB.anachronism_gap(str(w["id"]), era_id)
		if gap > 0:
			head += "　［この時代にはまだない品］"
		_lbl(head, 22, Crafting.grade_color(float(w.get("q", 0.5))), info, true)
		_lbl(Crafting.stats_text(w), 18, JSUI.MUTED, info)
		if not w.get("loan", false):
			_btn("捨てる", func(): _drop_inst(uid), true, "ghost", row, 120)
	_lbl("持ち物", 26, JSUI.GOLD, null, true)
	var keys: Array = prof().stacks.keys()
	keys.sort_custom(func(a, b): return ["ammo", "bomb", "heavy", "med", "tool", "valuable", "material"].find(CraftDB.item_type(a)) < ["ammo", "bomb", "heavy", "med", "tool", "valuable", "material"].find(CraftDB.item_type(b)))
	for id in keys:
		var it := CraftDB.item(id)
		var row2 := JSUI.hbox(12)
		_body.add_child(row2)
		var t := str(it.get("type", ""))
		var sid := str(id)
		var label := "%s ×%d" % [it.get("name", id), prof().count(id)]
		if t in ["ammo", "bomb", "material", "heavy", "med"]:
			label += "（%s）" % Crafting.grade(prof().stack_quality(id))
		if CraftDB.anachronism_gap(sid, era_id) > 0:
			label += "　［この時代にはまだない品］"
		var info2 := JSUI.vbox(0)
		info2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(info2)
		_lbl(label, 21, JSUI.TEXT, info2, true)
		_lbl(str(it.get("desc", "")), 17, JSUI.DIM, info2)
		if t in ["med", "tool", "valuable"] and (t != "valuable" or it.has("money")):
			_btn("使う", func(): _use(sid), true, "normal", row2, 110)
		if not it.get("keep", false) or sid == "smartphone":
			_btn("捨てる", func(): _drop_stack(sid), true, "ghost", row2, 110)


func _equip(uid: int) -> void:
	var p = Game.player
	if p and p.get("arms") != null:
		p.arms.equip(uid)
	else:
		prof().equip(uid)
	open_inventory()


func _use(id: String) -> void:
	var it := CraftDB.item(id)
	var msg := ""
	var p = Game.player
	match str(it.get("type", "")):
		"med":
			if p == null:
				return
			var heal := float(Crafting.item_stats(id, prof().stack_quality(id)).get("heal", 50)) * Skills.heal_mult(prof().level("medicine"))
			prof().take(id, 1)
			p.hp = minf(p.max_hp, p.hp + heal)
			prof().practice("medicine", 0.6)
			msg = "%sを使った（体力 +%d）" % [it.get("name", id), int(heal)]
		"valuable":
			prof().take(id, 1)
			prof().add_money(int(it.get("money", 0)))
			msg = "%sを開けた。所持金 %s" % [it.get("name", id), _money()]
		"tool":
			match id:
				"toishi":
					var w := prof().weapon()
					if w.is_empty() or CraftDB.item_type(str(w["id"])) != "melee":
						msg = "刃物を手にしてから使う"
					else:
						prof().take(id, 1)
						var add := Skills.whetstone_restore(prof().level("katana_smith"))
						w["dur"] = minf(float(w["stats"].get("max_dur", 0)), float(w["dur"]) + add)
						prof().practice("katana_smith", 0.4)
						prof().save()
						msg = "刃を研いだ（耐久 +%d）" % int(add)
				"shuri":
					var v := _near_vehicle()
					if v == null:
						msg = "近くに直せる乗り物がない（車・飛行機のそばで使う）"
					else:
						prof().take(id, 1)
						var amt := Skills.repair_amount(prof().level("machining"))
						var mx := 300.0 if str(v.get("kind")) == "plane" else 220.0
						v.set("hp", minf(mx, float(v.get("hp")) + amt))
						prof().practice("machining", 0.6)
						msg = "%sを修理した（+%d）" % [v.get("display_name"), int(amt)]
				"smartphone":
					_tab = 3
					open_inventory("圏外。でも地図とメモは見られる。")
					return
	open_inventory(msg)


func _near_vehicle() -> Node3D:
	var p = Game.player
	if p == null or not p.is_inside_tree():
		return null
	for v in p.get_tree().get_nodes_in_group("vehicle"):
		if v.get("hp") != null and (v as Node3D).global_position.distance_to(p.global_position) < 8.0:
			return v
	return null


func _drop_inst(uid: int) -> void:
	var it := prof().remove_instance(uid)
	if it.is_empty():
		return
	_drop_world([{"id": str(it["id"]), "n": 1, "q": float(it.get("q", 0.5)), "dur": float(it.get("dur", 0)) / maxf(1.0, float(it["stats"].get("max_dur", 1.0)))}], str(it["id"]))
	open_inventory("%sを捨てた" % CraftDB.item_name(str(it["id"])))


func _drop_stack(id: String) -> void:
	var n := prof().count(id) - int(prof().loan_stacks.get(id, 0))
	if n <= 0:
		return
	var q := prof().stack_quality(id)
	prof().take(id, n)
	_drop_world([{"id": id, "n": n, "q": q}], id)
	open_inventory("%s ×%d を捨てた" % [CraftDB.item_name(id), n])


## 過去の世界に品を置いていく。この時代にまだない品なら歴史が揺らぐ（拾った誰かが真似る）
func _drop_world(contents: Array, id: String) -> void:
	var p = Game.player
	if p == null or not p.is_inside_tree():
		return
	var d := LootDrop.spawn(p.get_parent(), p.global_position + p.global_basis.z * -1.2 + Vector3.UP * 0.3, contents, 0, "落とし物")
	d._arm = 6.0
	var gap := CraftDB.anachronism_gap(id, era_id)
	if gap > 0:
		Game.chaos_event.emit("anachronism", id, {"era": era_id, "item": id, "gap": gap, "cause": "lost", "type": CraftDB.item_type(id), "pos": p.global_position})


func _inv_skills() -> void:
	_lbl("技能は時代をまたいで持ち越す。使うだけでも %d までは上がる。その先は工房・道場・学校に弟子入りして稽古する。" % int(Skills.PRACTICE_CAP), 19, JSUI.MUTED)
	for k in Skills.ids():
		var lv := prof().level(k)
		var row := JSUI.hbox(14)
		_body.add_child(row)
		var nm := JSUI.label("%s" % Skills.skill_name(k), 23, JSUI.TEXT, JSUI.sans_bold())
		nm.custom_minimum_size = Vector2(180, 0)
		row.add_child(nm)
		var rk := JSUI.label(Skills.rank(lv), 20, JSUI.GOLD if lv >= 60 else JSUI.MUTED, JSUI.sans_bold())
		rk.custom_minimum_size = Vector2(90, 0)
		row.add_child(rk)
		var bar := ProgressBar.new()
		bar.max_value = 100
		bar.value = lv
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var num := JSUI.label("%d" % int(lv), 22, JSUI.CYAN, JSUI.sans_bold())
		num.custom_minimum_size = Vector2(50, 0)
		row.add_child(num)
		var ef := JSUI.label(Skills.effect_line(k, lv), 17, JSUI.MUTED, null, true)
		ef.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ef)


func _inv_craft() -> void:
	_lbl("ここで作れるのは「どこでも」の品だけ。刀・鉄砲・火薬・弾薬は工房（鍛冶場・鉄砲鍛冶・塩硝の里・蘭学塾・町工場・砲兵工廠）で。", 19, JSUI.MUTED)
	var list: Array = CraftDB.recipes().filter(func(r): return str(r.get("station", "")) == "any")
	_recipe_rows(list, [])
	_lbl("工房のレシピ", 24, JSUI.GOLD, null, true)
	for r in CraftDB.recipes():
		if str(r.get("station", "")) == "any":
			continue
		var req: PackedStringArray = []
		for k in r.get("skill", {}):
			req.append("%s %d" % [Skills.skill_name(k), int(r["skill"][k])])
		var era_name: String = Game.db.get_era(str(r.get("era", ""))).get("eraName", "") if Game.db else ""
		_lbl("・%s（%s／%s〜／%s）" % [CraftDB.item_name(str(r["out"])), CraftDB.station_name(str(r["station"])), era_name, "、".join(req)], 18, JSUI.DIM)


func _inv_memo() -> void:
	var era: Dictionary = Game.db.get_era(era_id) if Game.db else {}
	var cur := CraftDB.currency(era_id)
	_lbl("%s のメモ" % era.get("eraName", era_id), 26, JSUI.GOLD, null, true)
	_lbl("お金：%s ― %s" % [cur.get("name", ""), cur.get("note", "")], 20)
	_lbl("工房・学校（弟子入りできる）", 22, JSUI.CYAN, null, true)
	for w in CraftDB.workshops_for(era_id):
		var parts: PackedStringArray = []
		for k in w.get("teaches", {}):
			parts.append("%s〜%d" % [Skills.skill_name(k), int(w["teaches"][k])])
		_lbl("・%s（%s）：%s" % [w.get("name", ""), HistoryDB.landmark_name(era, str(w.get("at", ""))), "、".join(parts)], 19)
	_lbl("店", 22, JSUI.CYAN, null, true)
	for s in CraftDB.shops_for(era_id):
		_lbl("・%s（%s）" % [s.get("name", ""), HistoryDB.landmark_name(era, str(s.get("at", "")))], 19)
	_lbl("蔵・武器庫（盗むと手配度が上がる）", 22, JSUI.CYAN, null, true)
	for s in CraftDB.loot_for(era_id):
		_lbl("・%s（%s）" % [s.get("name", ""), HistoryDB.landmark_name(era, str(s.get("at", "")))], 19)
	_lbl("操作", 22, JSUI.CYAN, null, true)
	_lbl("左クリック：殴る・斬る・撃つ（長押しで強い振り・弓を引く）　右クリック：受け（刀）・狙う（銃・弓）　R：装填　1：持ち替え　2〜5：爆弾など　G：投げる　Tab：時空鞄　E：工房・店・蔵・人物", 18)

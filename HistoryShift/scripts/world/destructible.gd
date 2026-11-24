class_name Destructible
extends StaticBody3D
## 壊せる建物・塀・灯籠・船・橋など 1 ユニット。ワールド生成時に Destruction が
## EraWorld.unit_defs から作る。見た目は結合メッシュの中にあり（UV2 の ID でシェーダが状態を反映）、
## このノードはコリジョン・HP・段階（ひび→屋根崩落→倒壊）・火災を受け持つ。
## 被弾: take_hit(amount, from_team, point, dir)   体当たり: ram(speed, vel, mass_k)   着火: ignite()

## kind ごとの設定
## hp / armor(これ未満の一撃は 2 割しか効かない) / mat(破片の種類) / fire(燃える) / ruin(残骸の高さ比)
## wanted(倒壊時の手配度) / value(被害額・両) / chaos(歴史シミュへ通知) / chunks(破片数の目安) / small(倒壊後コリジョンなし)
const KINDS := {
	"house": {"hp": 520.0, "armor": 30.0, "mat": "wood", "fire": true, "ruin": 0.2, "wanted": 0.45, "value": 30, "chaos": true, "chunks": 12},
	"kura": {"hp": 700.0, "armor": 45.0, "mat": "plaster", "fire": false, "ruin": 0.34, "wanted": 0.5, "value": 60, "chaos": true, "chunks": 10},
	"hall": {"hp": 1100.0, "armor": 45.0, "mat": "wood", "fire": true, "ruin": 0.16, "wanted": 0.9, "value": 200, "chaos": true, "chunks": 18},
	"pagoda": {"hp": 2600.0, "armor": 80.0, "mat": "wood", "fire": true, "ruin": 0.1, "wanted": 1.5, "value": 800, "chaos": true, "chunks": 22},
	"castle_keep": {"hp": 6000.0, "armor": 120.0, "mat": "plaster", "fire": true, "ruin": 0.12, "wanted": 3.0, "value": 5000, "chaos": true, "chunks": 26},
	"yagura": {"hp": 900.0, "armor": 50.0, "mat": "plaster", "fire": true, "ruin": 0.25, "wanted": 0.6, "value": 150, "chaos": true, "chunks": 10},
	"gate": {"hp": 800.0, "armor": 50.0, "mat": "wood", "fire": true, "ruin": 0.15, "wanted": 0.8, "value": 150, "chaos": true, "chunks": 12},
	"tower": {"hp": 260.0, "armor": 20.0, "mat": "wood", "fire": true, "ruin": 0.08, "wanted": 0.3, "value": 15, "chaos": true, "chunks": 8},
	"torii": {"hp": 260.0, "armor": 30.0, "mat": "wood", "fire": true, "ruin": 0.12, "wanted": 0.6, "value": 40, "chaos": true, "chunks": 6},
	"wall": {"hp": 240.0, "armor": 25.0, "mat": "plaster", "fire": false, "ruin": 0.3, "wanted": 0.12, "value": 5, "chaos": false, "chunks": 5},
	"stonewall": {"hp": 420.0, "armor": 40.0, "mat": "stone", "fire": false, "ruin": 0.35, "wanted": 0.12, "value": 5, "chaos": false, "chunks": 5},
	"brickwall": {"hp": 300.0, "armor": 30.0, "mat": "brick", "fire": false, "ruin": 0.3, "wanted": 0.12, "value": 5, "chaos": false, "chunks": 5},
	"fence": {"hp": 60.0, "armor": 0.0, "mat": "wood", "fire": true, "ruin": 0.2, "wanted": 0.04, "value": 1, "chaos": false, "chunks": 4, "small": true},
	"stall": {"hp": 45.0, "armor": 0.0, "mat": "wood", "fire": true, "ruin": 0.1, "wanted": 0.08, "value": 3, "chaos": false, "chunks": 4, "small": true},
	"lantern": {"hp": 90.0, "armor": 10.0, "mat": "stone", "fire": false, "ruin": 0.2, "wanted": 0.05, "value": 4, "chaos": false, "chunks": 3, "small": true},
	"lamp": {"hp": 30.0, "armor": 0.0, "mat": "wood", "fire": false, "ruin": 0.12, "wanted": 0.03, "value": 2, "chaos": false, "chunks": 2, "small": true},
	"prop": {"hp": 15.0, "armor": 0.0, "mat": "wood", "fire": false, "ruin": 0.1, "wanted": 0.02, "value": 1, "chaos": false, "chunks": 2, "small": true},
	"boat": {"hp": 260.0, "armor": 20.0, "mat": "wood", "fire": true, "ruin": 0.0, "wanted": 0.5, "value": 60, "chaos": true, "chunks": 6},
	"bridge": {"hp": 380.0, "armor": 40.0, "mat": "wood", "fire": true, "ruin": 0.0, "wanted": 0.4, "value": 50, "chaos": true, "chunks": 4},
	"brick": {"hp": 1800.0, "armor": 60.0, "mat": "brick", "fire": false, "ruin": 0.28, "wanted": 1.0, "value": 300, "chaos": true, "chunks": 18},
	"concrete": {"hp": 2400.0, "armor": 80.0, "mat": "stone", "fire": false, "ruin": 0.22, "wanted": 1.2, "value": 400, "chaos": true, "chunks": 18},
	"school": {"hp": 900.0, "armor": 40.0, "mat": "wood", "fire": true, "ruin": 0.15, "wanted": 0.8, "value": 150, "chaos": true, "chunks": 16},
	"warehouse": {"hp": 1300.0, "armor": 50.0, "mat": "brick", "fire": false, "ruin": 0.25, "wanted": 0.8, "value": 200, "chaos": true, "chunks": 14},
	"hangar": {"hp": 1500.0, "armor": 50.0, "mat": "metal", "fire": false, "ruin": 0.1, "wanted": 1.0, "value": 300, "chaos": true, "chunks": 12},
	"monument": {"hp": 9000.0, "armor": 150.0, "mat": "stone", "fire": false, "ruin": 0.2, "wanted": 3.0, "value": 6000, "chaos": true, "chunks": 26},
}
## 大きさで HP を増やす種類
const SCALE_HP := ["house", "hall", "brick", "concrete", "warehouse", "school", "kura"]

var mgr: Destruction
var def: Dictionary
var id := 0
var kind := "house"
var cfg: Dictionary
var landmark := ""
var hp := 100.0
var max_hp := 100.0
var stage := 0                 # 0 無傷 1 ひび 2 屋根崩落 3 倒壊
var destroyed := false
var has_roof := false
var roof_gone := false
var flammable := false
var burning := false
var burn_t := 0.0
var char_amt := 0.0
var crack := 0.0
var frame := Transform3D()      # ユニットの座標系（yaw のみ、原点は足元中心）
var local_min := Vector3.ZERO
var local_max := Vector3.ONE
var aabb := AABB()              # ワールド
var base_y := 0.0               # 足元（土台の上）
var top_y := 1.0
var cut_y := 1e6
var hide_bits := 0             # 1 躯体 / 2 屋根 を隠す
var palette: Array = []        # [mat, 平均色, 頂点数]（瓦礫・小破片用、遅延計算）
var last_cause := "world"      # 最後に被害を与えた原因: player / player_indirect / enemy / world
var fire_cause := "world"
var _shape_nodes: Array = []
var _fx_t := 0.0
var _hit_flash_t := 0.0


func setup(p_mgr: Destruction, p_def: Dictionary) -> void:
	mgr = p_mgr
	def = p_def
	id = def["id"]
	kind = def["kind"]
	landmark = def.get("landmark", "")
	cfg = KINDS.get(kind, KINDS["house"])
	collision_layer = Game.COLLISION_WORLD
	collision_mask = 0
	add_to_group("destructible")
	name = "D%d_%s" % [id, kind]
	var opts: Dictionary = def.get("opts", {})
	var xf: Transform3D = def["xf"]
	frame = Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin)
	# コリジョン
	for sh in def["shapes"]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sh[1]
		cs.shape = bs
		cs.transform = sh[0]
		add_child(cs)
		_shape_nodes.append(cs)
	_compute_bounds()
	has_roof = false
	for mat in def["ranges"]:
		if mat in MeshKit.ROOF_MATS:
			has_roof = true
	flammable = bool(cfg["fire"])
	if kind == "boat" and String(opts.get("ship", "")) in ["steam", "liner"]:
		flammable = false
	if kind == "torii" or kind == "lantern":
		has_roof = false
	max_hp = float(cfg["hp"])
	if kind in SCALE_HP:
		var area := (local_max.x - local_min.x) * (local_max.z - local_min.z)
		max_hp *= clampf(area / 60.0, 0.6, 3.0)
	if kind == "boat" and bool(opts.get("big", false)):
		max_hp *= 3.0
	hp = max_hp


func _compute_bounds() -> void:
	var inv := frame.affine_inverse()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	var wmn := Vector3(INF, INF, INF)
	var wmx := Vector3(-INF, -INF, -INF)
	var pts: Array = []
	for sh in def["shapes"]:
		var t: Transform3D = sh[0]
		var s: Vector3 = (sh[1] as Vector3) * 0.5
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					pts.append(t * Vector3(s.x * cx, s.y * cy, s.z * cz))
	if true:
		# 形状が粗い／無いものは頂点から（間引き）
		var uid: int = id
		for mat in def["ranges"]:
			var rg: Array = def["ranges"][mat]
			var sa: Array = def["surf"][mat]
			var V: PackedVector3Array = sa[0]
			var U2: PackedVector2Array = sa[5]
			var step := maxi(1, (int(rg[1]) - int(rg[0])) / 160)
			for i in range(int(rg[0]), int(rg[1]), step):
				if int(U2[i].x) == uid:
					pts.append(V[i])
		for m in def.get("models", []):
			if m is MeshInstance3D and (m as MeshInstance3D).mesh:
				var ab: AABB = (m as MeshInstance3D).transform * (m as MeshInstance3D).mesh.get_aabb()
				pts.append(ab.position)
				pts.append(ab.end)
	for p in pts:
		var l: Vector3 = inv * p
		mn = mn.min(l)
		mx = mx.max(l)
		wmn = wmn.min(p)
		wmx = wmx.max(p)
	if mn.x == INF:
		mn = Vector3(-0.5, 0, -0.5)
		mx = Vector3(0.5, 1, 0.5)
		wmn = frame * mn
		wmx = frame * mx
	local_min = mn
	local_max = mx
	aabb = AABB(wmn, wmx - wmn)
	var bt: float = def.get("base_top", -INF)
	var g := frame.origin.y
	if mgr and mgr.world:
		var c := aabb.get_center()
		g = mgr.world.height_at(c.x, c.z)
	base_y = bt if bt > -1e8 else maxf(g, wmn.y)
	top_y = wmx.y


func center() -> Vector3:
	return aabb.get_center()


func size_class() -> float:
	return aabb.size.length()


# ================================================================ 被害
func take_hit(amount: float, from_team: int, point := Vector3.ZERO, dir := Vector3.ZERO) -> void:
	if destroyed:
		return
	var a := amount
	if a < float(cfg["armor"]):
		a *= 0.2
	if point == Vector3.ZERO:
		point = center()
	damage(a, point, dir, 0.0, mgr.cause_for(from_team))


## 乗り物の体当たり。mass_k: 馬 0.6 / 車 1 / 飛行機 4
func ram(speed: float, vel: Vector3, mass_k: float) -> void:
	if destroyed or speed < 4.0:
		return
	var dmg := (speed - 4.0) * 7.0 * mass_k
	if bool(cfg.get("small", false)):
		dmg *= 3.0
	var cause := mgr.cause_for(-1)
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and pl.has_method("in_vehicle") and pl.in_vehicle() \
			and (pl.vehicle as Node3D).global_position.distance_to(center()) < aabb.size.length() + 25.0:
		cause = "player"
		Destruction.note_player()
	damage(dmg, center() - vel.normalized() * aabb.size.length() * 0.3, vel.normalized(), 0.0, cause)


## 爆発（Destruction.blast から）
func blast(dmg: float, origin: Vector3, fire_chance: float, cause := "") -> void:
	if destroyed:
		return
	var dir := (center() - origin)
	dir.y = maxf(dir.y, 0.0)
	damage(dmg, origin.lerp(center(), 0.5), dir.normalized(), fire_chance, cause)


func damage(amount: float, point: Vector3, dir: Vector3, fire_chance: float, cause := "") -> void:
	if destroyed or amount <= 0.0:
		return
	if cause != "":
		last_cause = cause
	hp -= amount
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	crack = clampf((1.0 - frac) * 1.25, 0.0, 1.0)
	mgr.on_damage(self, amount, point)
	if fire_chance > 0.0 and flammable and randf() < fire_chance:
		ignite()
	if hp <= 0.0:
		destroy(dir, clampf(amount / max_hp, 0.3, 2.0))
		return
	if stage < 1 and frac < 0.7:
		stage = 1
		mgr.small_collapse(self, point, dir)
	if stage < 2 and frac < 0.4:
		stage = 2
		if has_roof and not roof_gone:
			collapse_roof(dir)
		else:
			mgr.small_collapse(self, point, dir)
	mgr.push_state(self)


func ignite() -> void:
	if destroyed and burn_t <= 0.0:
		return
	if not flammable or burning:
		return
	fire_cause = "player_indirect" if last_cause in ["player", "player_indirect"] else last_cause
	mgr.start_fire(self)


## Destruction の火災ティックから
func burn_step(dt: float) -> void:
	char_amt = minf(1.0, char_amt + dt * 0.09)
	if not destroyed:
		var rate := 0.028 if kind != "castle_keep" and kind != "pagoda" else 0.012
		hp -= max_hp * rate * dt
		crack = maxf(crack, char_amt * 0.6)
		var frac := hp / max_hp
		if stage < 2 and frac < 0.4 and has_roof and not roof_gone:
			stage = 2
			collapse_roof(Vector3.ZERO)
		if hp <= 0.0:
			last_cause = fire_cause
			destroy(Vector3.ZERO, 0.4)
	mgr.push_state(self)


# ================================================================ 段階
func collapse_roof(dir: Vector3) -> void:
	if roof_gone:
		return
	roof_gone = true
	mgr.collapse_roof(self, dir)


func destroy(dir: Vector3, power: float) -> void:
	if destroyed:
		return
	destroyed = true
	stage = 3
	hp = 0.0
	mgr.destroy_unit(self, dir, power)


## 倒壊後のコリジョン: 切断高さより上を削る（小物は全部消す）
func clip_collision(cut: float, remove_all: bool) -> void:
	for cs in _shape_nodes:
		var n := cs as CollisionShape3D
		if n == null or not is_instance_valid(n):
			continue
		var bs := n.shape as BoxShape3D
		if remove_all or bs == null:
			n.queue_free()
			continue
		var t := n.transform
		var up := t.basis.y.normalized()
		var hy := bs.size.y * 0.5
		var bottom := t.origin.y - hy
		var top := t.origin.y + hy
		if up.dot(Vector3.UP) < 0.95:
			if top > cut:
				n.queue_free()
			continue
		if top <= cut:
			continue
		var h := cut - bottom
		if h < 0.25:
			n.queue_free()
			continue
		var nb := BoxShape3D.new()
		nb.size = Vector3(bs.size.x, h, bs.size.z)
		n.shape = nb
		t.origin.y = bottom + h * 0.5
		n.transform = t
	_shape_nodes = _shape_nodes.filter(func(x): return is_instance_valid(x) and not (x as Node).is_queued_for_deletion())


## 瓦礫の山のコリジョン（低い箱）
func add_rubble_collision(h: float) -> void:
	if h < 0.3:
		return
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var ext := (local_max - local_min) * 0.8
	bs.size = Vector3(maxf(ext.x, 0.5), h * 0.6, maxf(ext.z, 0.5))
	cs.shape = bs
	var lc := (local_min + local_max) * 0.5
	cs.transform = frame * Transform3D(Basis(), Vector3(lc.x, base_y - frame.origin.y + h * 0.3, lc.z))
	add_child(cs)
	_shape_nodes.append(cs)

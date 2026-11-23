class_name Skills
extends RefCounted
## 技能（0〜100）の一覧と、技能が主人公のあらゆる能力に効く式。すべて静的な純関数（テストしやすいように）。
## s = 技能 / 100。低いと「ぎこちないが遊べる」、100 で「達人」。
## 技能は時代をまたいで持ち越す（PlayerProfile）。江戸で学んだ化学は昭和の弾薬づくりにも効く。

const LIST := {
	"kenjutsu":     {"name": "剣術", "cat": "武芸", "desc": "刀の振りの速さ・威力・受け流し・刃の傷みにくさ"},
	"sojutsu":      {"name": "槍術", "cat": "武芸", "desc": "槍・薙刀の振りの速さ・威力・受け"},
	"kyujutsu":     {"name": "弓術", "cat": "武芸", "desc": "弓を引く速さ・矢の勢い・狙いの揺れ"},
	"shageki":      {"name": "射撃", "cat": "武芸", "desc": "銃の集弾・反動・装填の速さ・不発の少なさ"},
	"katana_smith": {"name": "刀鍛冶", "cat": "匠", "desc": "刀・槍・玉鋼の品質（切れ味・耐久・重さ）、砥石の効き"},
	"gun_smith":    {"name": "鉄砲鍛冶", "cat": "匠", "desc": "鉄砲・大筒の品質（精度・不発・装填の速さ）"},
	"powder":       {"name": "火薬調合", "cat": "匠", "desc": "火薬・弾薬・爆弾の品質（威力・不発の少なさ）"},
	"machining":    {"name": "機械工作", "cat": "匠", "desc": "近代の銃・弾薬・修理道具の品質、乗り物の修理量"},
	"riding":       {"name": "乗馬", "cat": "乗り物", "desc": "馬の速さ・小回り・落馬しにくさ"},
	"sailing":      {"name": "操船", "cat": "乗り物", "desc": "舟の速さと舵の効き"},
	"driving":      {"name": "自動車運転", "cat": "乗り物", "desc": "ハンドルの反応・タイヤのグリップ・ふらつき"},
	"piloting":     {"name": "飛行機操縦", "cat": "乗り物", "desc": "旋回の速さ・機体の安定・失速しにくさ・着陸のしやすさ"},
	"medicine":     {"name": "医術", "cat": "学問", "desc": "体力の回復の速さ・薬の効き"},
	"chemistry":    {"name": "化学（蘭学）", "cat": "学問", "desc": "火薬・弾薬・薬の品質を底上げ（時代をまたいで効く）"},
	"shipbuilding": {"name": "造船", "cat": "匠", "desc": "舟の修理・造船の品質"},
	"architecture": {"name": "建築", "cat": "学問", "desc": "建物の急所がわかる（火薬樽・ダイナマイトの威力）"},
	"rhetoric":     {"name": "話術", "cat": "学問", "desc": "説得が通りやすい・値切り・武器を譲ってもらう"},
	"komonjo":      {"name": "古文読解", "cat": "学問", "desc": "書状を盗む・偽の書状を渡す成功率"},
}
const RANKS := [[0, "素人"], [15, "見習い"], [35, "一人前"], [60, "熟練"], [80, "名人"], [100, "極み"]]
const PRACTICE_CAP := 50.0    # 使うだけで上がるのはここまで（その先は弟子入りで）


static func ids() -> Array:
	return LIST.keys()


static func skill_name(id: String) -> String:
	return str(LIST.get(id, {}).get("name", id))


static func rank(level: float) -> String:
	var r := "素人"
	for pair in RANKS:
		if level >= float(pair[0]):
			r = pair[1]
	return r


static func _s(level: float) -> float:
	return clampf(level / 100.0, 0.0, 1.0)


## 稽古・使用で上がる量（上がるほど伸びにくい）
static func gain(level: float, amount: float) -> float:
	return amount * clampf(1.15 - _s(level), 0.15, 1.15)


# ------------------------------------------------------------------ 近接（剣術・槍術）
static func melee_damage_mult(level: float) -> float: return 0.7 + 0.6 * _s(level)
static func melee_time_mult(level: float) -> float: return 1.35 - 0.5 * _s(level)       # 振りの所要時間の倍率（小さいほど速い）
static func block_reduction(level: float) -> float: return 0.3 + 0.55 * _s(level)       # 受けたとき減らす割合
static func parry_window(level: float) -> float: return 0.12 + 0.23 * _s(level)         # 受け始めのこの秒数内に当たれば「受け流し」
static func wear_mult(level: float) -> float: return 1.6 - 1.1 * _s(level)              # 刃の傷み


# ------------------------------------------------------------------ 射撃・弓
static func spread_mult(level: float) -> float: return 1.9 - 1.4 * _s(level)
static func reload_mult(level: float) -> float: return 1.6 - 0.8 * _s(level)
static func recoil_mult(level: float) -> float: return 1.8 - 1.3 * _s(level)
static func misfire_mult(level: float) -> float: return 1.6 - 1.3 * _s(level)
static func bow_draw_mult(level: float) -> float: return 1.5 - 0.7 * _s(level)
static func bow_power_mult(level: float) -> float: return 0.75 + 0.45 * _s(level)
static func aim_sway(level: float) -> float: return 0.05 * pow(1.0 - _s(level), 1.5)     # 照準の揺れ（ラジアン）


# ------------------------------------------------------------------ 乗り物
static func car_steer_rate(level: float) -> float: return 2.5 + 6.0 * _s(level)         # 元は 6
static func car_grip(level: float) -> float: return 0.6 + 0.35 * _s(level)               # 元は 0.9
static func car_wobble(level: float) -> float: return 0.18 * pow(1.0 - _s(level), 2.0)  # ハンドルのふらつき
static func car_power_mult(level: float) -> float: return 0.8 + 0.3 * _s(level)
static func horse_speed_mult(level: float) -> float: return 0.75 + 0.35 * _s(level)
static func horse_turn_mult(level: float) -> float: return 0.65 + 0.5 * _s(level)
static func horse_throw_chance(level: float) -> float: return 0.6 * pow(1.0 - _s(level), 2.0)   # ぶつかった・跳んで着地したときに落馬する確率
static func plane_turn_mult(level: float) -> float: return 0.5 + 0.65 * _s(level)
static func plane_wobble(level: float) -> float: return 0.5 * pow(1.0 - _s(level), 2.0)  # 機体の揺れ（rad/s）
static func plane_stall_speed(level: float) -> float: return 18.0 + 10.0 * (1.0 - _s(level))   # 揚力がなくなる速さ（元は 18）
static func plane_land_speed(level: float) -> float: return 30.0 + 15.0 * _s(level)     # 着陸できる最大の速さ（元は 40）
static func plane_land_sink(level: float) -> float: return 4.0 + 6.0 * _s(level)        # 着陸できる最大の降下速度（元は 8）
static func boat_turn_mult(level: float) -> float: return 0.6 + 0.6 * _s(level)         # 舟（ships 側が使う）
static func boat_speed_mult(level: float) -> float: return 0.8 + 0.3 * _s(level)


# ------------------------------------------------------------------ 学問・その他
static func persuade_bonus(level: float) -> int: return int(floor(_s(level) * 2.99))   # 説得の信頼 +0〜2
static func forge_success(level: float) -> float: return 0.3 + 0.65 * _s(level)        # 書状を盗む・偽る
static func gift_success(rhetoric: float, trust: int) -> float: return clampf(0.2 + 0.5 * _s(rhetoric) + 0.15 * trust, 0.05, 0.95)
static func regen_mult(level: float) -> float: return 0.75 + 0.75 * _s(level)
static func heal_mult(level: float) -> float: return 0.75 + 0.75 * _s(level)
static func whetstone_restore(level: float) -> float: return 25.0 + 60.0 * _s(level)
static func repair_amount(level: float) -> float: return 40.0 + 140.0 * _s(level)
static func demolition_mult(level: float) -> float: return 1.0 + 0.3 * _s(level)       # 建築：火薬樽・ダイナマイトの威力
static func buy_mult(level: float) -> float: return 1.15 - 0.3 * _s(level)
static func sell_mult(level: float) -> float: return 0.3 + 0.3 * _s(level)


## 稽古（ミニゲーム）の難しさ：当たりの幅（0〜1 のバー上の割合）。上達するほど狭い＝奥伝
static func lesson_zone(level: float) -> float: return lerpf(0.24, 0.09, _s(level))
## 稽古 1 回で上がる量（score 0〜1）
static func lesson_gain(level: float, score: float) -> float: return gain(level, 9.0 * (0.35 + 0.65 * clampf(score, 0.0, 1.0)))

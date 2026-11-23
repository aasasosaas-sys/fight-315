# JIDAI SHIFT — アーキテクチャ（Godot 4.5 / GDScript / Forward+ / Jolt）

ゲームの流れ: タイトル → 共通テスト（解答は確定） → 採点ハブ → 誤答を選んで時空跳躍 → 該当時代のオープンワールドでミッション → 改変（連鎖） → ハブ → … → 満点でエンディング（改変の組み合わせから自動合成）。自由探索モードあり。

## ディレクトリ
```
data/*.json           問題・ミッション・連鎖ルール（tools/SCHEMA.md）
assets/polyhaven/     CC0 テクスチャ (textures/<key>_diff|_nor_gl|_rough.jpg) と HDRI (hdri/sky_<day|clear|hazy|evening>.hdr)
                      models/<id>/<id>.gltf は tools/download_assets.py で任意取得（無くても動くこと）
assets/fonts/         Noto Sans JP / Noto Serif JP (OFL)
scripts/core/         game.gd (autoload "Game"), history_db.gd, history_state.gd, main.gd
scripts/world/        ワールド生成（担当: world）
scripts/player/       プレイヤー・カメラ・銃・乗り物・エフェクト（担当: gameplay）
scripts/mission/      セッション・ミッション進行・敵・NPC・町人・手配度・HUD（担当: gameplay）
scripts/ui/           flow.gd と各画面（担当: ui）
tests/                ヘッドレステスト・スクリーンショット
```

## 共通ルール
- 衝突レイヤ（Game 定数）: 1 WORLD(地形・建物などの静的物), 2 PLAYER, 3 ENEMY(値4), 4 CIVILIAN(値8), 5 VEHICLE(値16), 6 PROP(値32)
- グループ: "explosive"（撃つと爆発: RigidBody3D に scripts/player/explosive.gd）, "physics_prop", "landmark"
- 単位はメートル。Y上。ワールド原点がマップ中央。
- 日本語フォントはテーマ（assets/theme.tres）で全UIに適用済み。
- `Game.input_blocked` が true の間、ゲームプレイ入力は無視される（UI 側が設定）。
- `Game.lock_mouse(bool)` でマウスキャプチャ切替。

## Game (autoload) API
```gdscript
Game.db : HistoryDB      # .eras, .questions(年代順), .by_id, .rules, .get_era(id), .mission_for(q, choice), HistoryDB.landmark_name(era, key)
Game.state : HistoryState # world_choice(q), answer(q), set_answer(q,c), is_correct(q), is_altered(q), correct_count(), score(), perfect(),
                         # apply_change(q, c, cause)->Array[{question,from,to,cause,depth}], predict_ripple(q,c)->Array[{question,to,note}],
                         # compose_ending()->[title, text], exam_submitted, alterations, restorations, history_log, save(), reset_all()
Game.world / Game.player / Game.input_blocked / Game.lock_mouse()
```

## EraWorld（担当: world）— `scripts/world/era_world.gd`
```gdscript
class_name EraWorld extends Node3D
static func build(era: Dictionary) -> EraWorld      # era = Game.db.get_era(id)。add_child は呼び出し側
var era: Dictionary
var half_size: float          # 遊べる範囲は [-half_size, half_size]（約 600）
var water_level: float
var player_spawn: Vector3
func landmark_pos(key: String) -> Vector3           # 地表の位置
func height_at(x: float, z: float) -> float
func random_ground_point_near(center: Vector3, radius: float, rng: RandomNumberGenerator) -> Vector3  # 水上・建物上を避ける
func set_beacon(key: String, on: bool)              # 目標地点の光の柱
func vehicle_spawns(kind: String) -> Array          # Array[Transform3D]。"horse" "car" "plane"（plane は滑走路/平地）
func street_points() -> Array                       # 町人が歩く地点 Array[Vector3]
func set_time_of_day(hours: float)                  # 任意（0-24）
```
WorldEnvironment・太陽（DirectionalLight3D）・空・霧・ポストエフェクトは EraWorld が持つ。カメラは gameplay 側。

## Session（担当: gameplay）— `scripts/mission/session.gd`
```gdscript
class_name Session extends Node3D
signal completed(changes: Array)      # ミッション成功時。apply_change 済みの変化リスト
signal failed(reason: String)
signal aborted
static func start_mission(q: Dictionary, choice: int) -> Session   # ワールド・プレイヤー・HUD・ミッション進行を生成
static func start_free_roam(era_id: String) -> Session
static func start_backdrop(era_id: String) -> Session              # タイトル背景用（カメラが周回、操作なし、HUD なし）
func end()                                                         # 片付け（queue_free）
```
呼び出し側（flow.gd）が `add_child(session)` する。Session 内で HUD・ポーズメニュー（再開/中断）・死亡時リトライを処理する。

## Flow（担当: ui）— `scripts/ui/flow.gd`
main.gd が `Flow` ノードとして生成する。タイトル・試験・採点ハブ・ブリーフィング・ワープ演出・改変結果（連鎖表示）・エンディング・改変ログ・設定・クレジットを担当。Session を生成/破棄して画面を切り替える。

## 破壊システム（担当: world/gameplay）— `scripts/world/destruction.gd` ほか
- 生成時: `Architecture.begin_unit(kind, xf)/end_unit()` で建物・塀区画・灯籠・船・橋区画などを「破壊ユニット」として記録（`EraWorld.unit_defs`）。
  ジオメトリは従来どおり結合メッシュに残り、UV2 にユニット ID を焼く（描画コールは増えない）。土台（foundation）は壊れない。
- `Destruction.attach(world)` が各ユニットを `Destructible`（StaticBody3D, layer WORLD, group "destructible"）に変換し、
  状態テクスチャ（global uniform `destruct_tex`）でシェーダが 隠す/焦げ/ひび/燃えさし/切断（廃墟の高さ）を描く（`shaders/destruct.gdshaderinc`）。
- 被害: `take_hit(amount, team, point, dir)`（弾）/ `ram(speed, vel, mass_k)`（乗り物）/ `Destruction.blast_at(tree, pos, r, dmg, team, fire)`（爆発。`Effects.explosion` が自動で呼ぶ）。
  段階: ひび → 屋根崩落（瓦が滑り落ちる）→ 倒壊（`Fracture.slice` で元メッシュを格子に切った破片 RigidBody＋瓦礫の山＋低いコリジョン）。
- 木は `EraWorld.tree_defs`（MultiMesh のインスタンス）を倒す。火災は木造に延焼（同時 14 棟・ランドマークごと 36 回まで）。
- 破片 layer は `Game.COLLISION_DEBRIS`(64)。プレイヤー・町人とは当たらない（町人は爆風でも倒れず逃げる）。
- `Game.chaos_event(kind, id, info)`: kind = destroy / sink / fire / bridge / block。id はランドマークのキー（道沿いは "town"、川の橋は "river"、block の橋は橋グループ ID）。
  info = {era, pos, type, cause("player"|"player_indirect"|"enemy"|"world"), ...}
- ツール（`scripts/player/destruction_tools.gd`）: 1 銃 / 2 焙烙玉 / 3 火薬樽・ダイナマイト / 4 大筒・野砲（設置→砲撃）/ 5 棒火矢、G で焙烙玉、ホイールで切替。

## 実寸の船（担当: world）— `scripts/world/ships/`
- データ: `data/ships/<id>.json`（調査）＋ `"layout"`（ゲーム用: 船型・部品・部屋の位置ヒント・浸水の設定）。`sosen.json` は ming_junk の変種（平安の宋船・仮）。
  座標は船ローカル（水線中央が原点、船首 -Z、右舷 +X）、部品の位置 `s` は水線の船首からの距離 m。
- `ShipData`（読込＋配置計画: 甲板の分類 weather/internal/super、天井高 2.15m 未満は広げる、部屋の配置、階段、区画・水密扉・注水弁）
  → `ShipExterior`（船体・上甲板・部品、常に表示）／`ShipInterior`（船内、近づくと数フレームに分けて生成・離れると解放）／`ShipProps`（key_props の語から小道具）。
- `Ship`（AnimatableBody3D の `ShipBody` を持つ）: 被害 `on_hit / on_blast / on_direct_blast / on_ram / on_ignite`、E で水密扉・注水弁・ポンプ・舷梯、
  小さめの船は舵（`ShipHelm`、F）で操船。沈没で `Game.chaos_event("sink", "port", {type:"ship", ship, name, pos, value, cause, era, landmark})`。
- `ShipFlood`: 区画ごとの水量、破孔流入 q=Cd·A·√(2gΔh)、扉・隔壁上端の流れ、ポンプ（缶室浸水で停止）、沈下・トリム・GZ 曲線による傾斜/転覆、
  木造の延焼と焼け抜け、空母格納庫の誘爆、火が弾火薬庫へ（注水で防げる）。
- `ShipYard`（EraWorld の子、`layouts.gd` の `_port_layout` 末尾の 1 行で配置）: 爆発の通知（`Destruction.blast_at` 内の 1 行 → `blast_all`）、
  泳ぎ・息・沈む船からの脱出、海面マスク（`water.gdshader` の dry_* uniform）、状態表示、`ShipLaunch`（小舟・内火艇）。
- 箱庭との縮尺: 地形は ±220m、岸から境界まで 30〜40m しかないので、喫水の深い船（大和・赤城・加賀・氷川丸・三笠・サスケハナ等）は実寸のまま
  境界の外の沖に錨泊させ、その船の周り 60m にいる間だけ `EraWorld.half_size` を広げる（小舟で渡る）。浅い船は岸近くに桟橋つきで置く。
- テスト: `tests/test_ships.tscn`（ヘッドレス: 全船の組立・自沈/爆薬/弾火薬庫/放火の早回し）、`tests/shot_ships.tscn`（外観・船内・沈没の連続写真）。

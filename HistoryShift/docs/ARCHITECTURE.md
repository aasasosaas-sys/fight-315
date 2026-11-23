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

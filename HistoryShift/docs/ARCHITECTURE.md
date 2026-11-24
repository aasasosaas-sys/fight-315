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
  例外：設定「民間人への危害（成人向け）」（既定オフ・教育版では無効）がオンなら、町人はプレイヤーが原因の被害で倒れる（瓦礫は町人が近くの建物の倒壊を見て判定。`scripts/core/civil_harm.gd`・`scripts/mission/civil_runtime.gd`・`data/chaos_civil/`、tools/SCHEMA_V2.md）。
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

## 屋内（担当: world）— `scripts/world/interiors/`
- 生成時: 建物の壁は `Architecture.shell()`（外から見た姿は従来の箱と同じ中空の壁体＋天面＋室内側の天井）で作り、入口の開口を抜く
  （`slab()` が見た目と当たり判定の両方を抜く。窓の開口は見た目だけ）。土台の段は `entry_steps()`（見た目の段＋坂の当たり判定）。
  外側の帯（下見板・胴蛇腹）は `band()`（天面なし＝室内に面が出ない）。いずれも破壊ユニットの begin/end の中で作るので、
  破片・状態テクスチャ・ユニットのコリジョンに自動で含まれる。
- 登録: `Architecture.reg_interior(type, xf, floors, doors, opts)` → `EraWorld.interior_defs`。
  floors = [{y, rect(局所 xz), h, hole(天井の吹き抜け), stair{a,b,w}, win(窓)}]、doors = [{p, n, w, h, out}]。寸法は外観と同じ。
- `WorldInteriors`（EraWorld の子）: プレイヤーが 25m 以内に来た建物だけ `InteriorBuilder`＋`InteriorKits`/`InteriorKitsModern` で内装を作り、
  60m 超で外す（6 棟までプール、同時 10 棟）。1 棟 = MeshInstance 1 つ＋StaticBody 1 つ。実ライトは近い順に 4 灯まで（無影）、他は発光材。
- キット（時代×用途）: pit 竪穴住居 / takayuka 高床倉庫 / raised_hall 祭殿 / shinden 寝殿造 / palace・daigokuden / temple 本堂 / pagoda / kinkaku /
  shrine 拝殿 / shoin 書院造 / goten 御殿 / machiya 町家（2 階）/ nagaya 長屋 / chaya 茶屋 / minka・farmhouse / kura 土蔵 / storehouse /
  castle 天守（全層・階段・連子窓）/ yagura / yokan 洋館 / office・office_showa / bank / station 駅舎 / factory 製糸場 / warehouse(_showa) /
  school / diet 中央広間 / showa_shop・showa_house / danchi 2DK / hangar / tower。典拠は `data/interiors/kits.json` の basis。
- 破壊との連動: 屋根崩落（stage>=2）・炎上で入口を塞ぐ（中にいなければ内装も消す）。中にいる時に燃えたら屋内に炎と煙（体力 3 割までの微ダメージ）。
  倒壊（`Destruction.destroy_unit` → `on_destroyed`）で内装を捨て、中のプレイヤーは入口の外へ押し出して最大 45 のダメージ（即死させない）。
- カメラ: `CameraRig.indoor`（WorldInteriors が設定）で腕を短く・低く、壁・天井の手前で止める（各階の天井に当たり判定あり）。
```gdscript
EraWorld.get_interior_points(unit_id) -> Array[Vector3]       # 屋内の NPC 地点（内装を作っていなくても返す）
EraWorld.get_interior_spots(unit_id) -> [{pos, yaw, floor, role}]   # role: stand/sit/work/guard/scene
EraWorld.find_interior(tag) -> int                            # "honnoji" "omiya" "tenshu" "rokumeikan" "shimbashi" "diet" ...（kits.json の scenes）
EraWorld.find_interiors(type, landmark) -> Array[int]
EraWorld.get_interior_info(unit_id) -> {type, name, basis, floors, tags, doors:[{pos, out, normal}], loaded, blocked}
EraWorld.ensure_interior(unit_id, pin) / release_interior(unit_id) # 上階に NPC を立たせる前などに先に作る
EraWorld.interior_at(pos) -> int
```

## 技能・持ち物・製作（担当: gameplay）— `scripts/core/skills.gd` ほか
主人公は現代の高校生なので**素手で始まる**。武器は過去で手に入れる（倒した兵の落とし物・蔵/武器庫を探る＝盗み・店で買う・人物に譲ってもらう・工房で作る）。
- データ: `data/crafting/items.json`（品：種類・基本値・史実の時代 `era`・値段（文）・時代錯誤の歴史効果 `tech`）、`recipes.json`（場所・時代・必要技能・補助技能・材料・`anachro`＝過去で作るのに要る未来の技能）、
  `workshops.json`（弟子入りできる工房・学校 19 か所：時代・名所・教われる技の上限・稽古・手伝い・史実の根拠 `basis`）、`trade.json`（時代ごとのお金・店・蔵・兵の落とし物）。
- `Game.profile : PlayerProfile`（`scripts/core/player_profile.gd`）: 技能 18 種（0〜100）・持ち物（個体＝武器：品質・耐久・装填数／束＝材料・弾・爆弾：数と平均品質）・所持金（文。1両=4000文=1円）。
  `user://profile.json` に保存（歴史のセーブとは別）。時代をまたいで、ハブに戻っても持ち越す。新しいゲーム・リセットで初期化。
  `level(id)`（技術完全習得モードなら 100）/ `train(id, amount, cap)`（弟子入り）/ `practice(id, amount)`（使うだけで上がる。50 まで）/ `lend()`・`return_loans()`（貸与品は保存しない）。
- `Skills`（純関数）: 技能→能力の式。剣術・槍術（威力 0.7〜1.3 倍・振りの時間 1.35〜0.85 倍・受け 30〜85%・受け流しの猶予・刃の傷み）、射撃（散らばり・反動・装填・不発）、弓術（引き・矢の勢い・揺れ）、
  自動車運転（ハンドル反応・グリップ・ふらつき・加速）、乗馬（速さ・小回り・落馬率）、飛行機操縦（旋回・揺れ・失速速度・着陸できる速さ/降下率）、操船（`boat_*`：船側が使う）、医術（回復）、話術（説得 +0〜2・売り買い）、古文読解（書状の成功率）、建築（爆薬の威力）。
- `Crafting`: 品質 q = 0.15＋0.6·主技能＋0.15·補助技能＋0.3·(材料の質−0.5)＋0.2·(仕上げの出来−0.5)。等級 粗悪/並/上/名工。品の能力値も q から（刀：威力・耐久・振りの速さ、銃：精度・不発・装填・反動、弾薬・爆弾：威力と不発）。
- `PlayerArms`（Player の子）: 素手（拳・溜めて蹴り）／刀・槍（軽い振り・長押しの強い振り・右クリックで受け／受け流し・耐久）／弓（引いて放つ）／銃（装填・時代の連射速度・火縄銃は一拍おくれて発火・不発）。
  破壊ツールの 2〜5（焙烙玉・手榴弾・火薬樽・ダイナマイト・大筒＋砲弾・棒火矢）は持ち物を消費する。`ThrownBomb.power/dud`・`Shell.power/dud`。
- `Enemy`: 中世〜江戸の兵の一部は刀・槍で斬りかかる（振りかぶりの間に受けると受け流せる）。倒すと `LootDrop`（武器・弾・銭）。修正力は落とさない。
- `CraftWorld`（Session の子）: 自由探索で工房・店・蔵を名所のそばに置く（`CraftStation`、E で開く）。Tab / I / Back で時空鞄（`CraftUI`：持ち物・技能・製作・メモ）。
  稽古は `Minigame`（hammer/heat/assembly/mix/target）か `CourseLesson`（馬・車・飛行機で目印を回る）。
- 歴史: 動詞 `teach`（人物・職人に技を教える：`HistoryActors.TEACH` × 技能/100 × 影響力）、`anachronism`（この時代にまだない品を渡した・落とした・職人の前で作った：`items.json` の tech × 何時代ぶん未来か（上限3）× 原因の重み）。
  どちらも一般則（手作りルールは追加していない）。説得・未来を語るは `info.skill_bonus`（話術）を信頼に足す。
- ミッション: 使える武器を持っていなければ、開始時にその時代の武器を貸与（`Session.MISSION_KITS`：縄文〜室町は弓＋刀、戦国・江戸は火縄銃＋刀、明治・昭和は三八式）。終われば返す。
- 設定: 「技術完全習得モード」（技能 100・レシピ解禁、学んだ値は残る）、「最初から武装」（時空銃＋爆薬を貸与）。どちらも既定はオフ。
- テスト: `tests/test_skills.gd`（ヘッドレス：式・製作・保存・時代をまたぐ持ち越し・完全習得・teach/anachronism・近接/受け/装填/落とし物/貸与）、`tests/shot_skills.tscn`（工房・稽古・製作・持ち物・近接の写真）。

### 知識の木と産業（主人公が自分で産業革命を起こす）— `scripts/core/knowledge.gd`・`scripts/mission/facility.gd`
- データ: `data/crafting/knowledge.json`（10 分野・39 ノード：冶金 たたら→反射炉→洋式高炉→製鋼／機械 からくり→旋盤→互換性部品→精密機械／動力 水車→蒸気機関→鉄道・内燃機関／
  化学 火薬→硫酸・ソーダ→化学肥料・石油精製／電気 エレキテル→電池→電信→発電／数理 和算→測量・天文→航海術／医学 漢方→蘭方→種痘→細菌学／繊維 手織→機械紡績・器械製糸／
  造船 和船→洋式帆船→蒸気船・飛行機／経営 複式簿記→株式会社・学校。各ノード: prereq・師のいる時代 era・schools（工房 id か学問所 id：佐賀藩精錬方・釜石の高炉・長崎海軍伝習所・天文方・
  からくり儀右衛門の工房・本草学者の工房・工部大学校・鉄道寮・富岡製糸場・伝染病研究所・国立銀行・八幡製鉄所・造幣寮…）・modern（現代の常識）・book・vars・basis）。
  `data/crafting/buildings.json`（16 施設：水車小屋・町の工房・たたら場・鉱山/炭鉱・反射炉・洋式高炉・機械工場・紡績工場・製糸場・化学工場・洋式造船所・発電所・鉄道・電信線・銀行・学校）。
- 状態 `PlayerProfile.knowledge {id: {p, m}}`・`permits {era: true}`・`buildings [rec]`（すべて保存）。はじめから現代の常識（modern）の原理だけ知り、`kyokasho`（未来の教科書）を持つ。
  習熟は 師（100 まで）・実験（60 まで）・施設の稼働（80 まで）。前提の習熟 +30 を超えられない。技術完全習得モードではすべて原理○・習熟 100。
- 建設（自由探索・名所から 90m 以内）: 知識の習熟・建材・費用・働き手・動力（水車は村/寺/港、蒸気は蒸気機関の品と毎回の石炭）・支配者の許し（ruler/official/reformer の人物を説得するか冥加金）。
  施設は生産（原料→品・稼ぎ）・職人の腕（「職人に教える」で上がる）・拡張（規模 3 まで）・製作の場所（`station`）。離れていた間の分は最大 30 回ぶん。
- 歴史への知らせ（ほかの担当が使える形）:
  `Game.chaos.act("industry", <buildings.json の id>, {"landmark": <名所キー>, "scale": 1〜3, "mult": <学校は 1+知っている原理/10>, "bonus": bool})`
  → 行動 `{verb:"industry", target, landmark, scale, mult, bonus, era, seq}`。効果は施設の vars ×(1+0.5(scale−1))×mult を、その時代の年に歴史パラメータへ（WarModel の複利で 1941 年の柱に効く）。
  同じ時代・同じ名所・同じ規模は一度だけ。知識を教える（`teach`、skill に知識ノード id）は knowledge.json の vars。同じ相手に同じ知識は一度だけ（`ChaosTracker._done_before`）。
  生産が `Knowledge.RUN_MILESTONE`（12）回に達すると `stage: "run"`・mult 0.5 でもう一度だけ知らせる（稼働する工場を見て真似る者が出る）。
- 市場: `buildings.json` の `markets`（品ごとの時代の需要倍率と史実の根拠。例 生糸は開港後の明治 ×1.4、玉鋼は廃刀令後 ×0.4）。
  施設画面の「問屋に卸す」＝ `Knowledge.market_price/market_sell`（品の値×0.6×需要×売れ残り（1つ 4%・最低 40%・30 秒で 1 つ分戻る）×話術）。
- 操船: `Player.apply_sailing(helm)` が乗船時に `ship.sd.pilot` の vmax・turn を操船の技能の倍率で置きかえる（ships/* は変えない）。舵を取って 40m 進むごとに操船の稽古。

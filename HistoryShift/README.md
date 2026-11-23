# 時空改変 共通テスト日本史 ―JIDAI SHIFT―

共通テスト日本史を解いて、**間違えた問題は過去へ跳んで史実のほうを書き換え**、満点を目指すオープンワールド・アクションです（Godot 4.5）。

## 遊び方
1. **共通テスト**：8時代・34問（オリジナル問題）に答える。提出すると答えは確定。
2. **採点ハブ**：今の世界での点数が出る。間違えた問題を選んで「時空跳躍」。
3. **改変ミッション**：その時代のオープンワールドで、移動・会話・回収・戦闘・乗り物レースをこなし、あなたの答えを「史実」にする。
4. **バタフライ効果**：改変は後の時代の問題の正解まで書き換えることがある。因果は過去→未来にしか流れないので、**古い時代から直すのが攻略のコツ**。
5. **満点でエンディング**：書き換えた歴史の組み合わせから「その世界の令和日本」が自動で語られる（4^34 ≈ 3×10^20 通り）。

自由探索モードでは、各時代で好き放題に暴れられます。暴れると**時空警戒度（★）**が上がり、その時代の追手（検非違使・捕り方・巡査・憲兵…）や「歴史の修正力」が追ってきます。

### 操作
| 操作 | キー |
|---|---|
| 移動 / ダッシュ / ジャンプ | WASD / Shift / Space |
| 視点 / 射撃 / エイム / リロード | マウス / 左クリック / 右クリック / R |
| 乗り物に乗る・降りる（奪う） | F |
| 話す | E |
| ポーズ | Esc |
| 馬・車 | W/S 前後, A/D 旋回, Shift 加速, Space ブレーキ（馬はジャンプ） |
| 飛行機（昭和） | W/S スロットル, マウスで進路, Shift ブースト, 左クリック 機銃。速度を上げてマウスを上へで離陸。空中で F を押すとパラシュート降下 |

ゲームパッドにも対応しています。

## 起動
1. [Godot 4.5](https://godotengine.org/download)（標準版）をインストール
2. Godot で `HistoryShift/project.godot` を開き、F5 で実行
3. 配布用ビルドは「プロジェクト → エクスポート」（Windows / macOS / Linux のプリセット入り。初回はエクスポートテンプレートのダウンロードが必要）

任意：高品質な3Dモデル（Poly Haven, CC0）を追加取得できます。
```bash
python3 tools/download_assets.py
```

## 構成
- `data/*.json` … 問題・改変ミッション・長期的影響・連鎖ルール（形式は `tools/SCHEMA.md`、検証は `python3 tools/validate_data.py`）
- `scripts/core` … 因果エンジン（`history_state.gd`）とデータ読み込み
- `scripts/world` … 時代ごとのワールド生成（地形・建物・植生・空・ポストエフェクト）
- `scripts/player` … プレイヤー・カメラ・銃・馬・車・飛行機・エフェクト・効果音
- `scripts/mission` … セッション・ミッション進行・敵（地上・航空）・町人・人物・手配度・HUD
- `scripts/ui` … タイトル・試験・採点ハブ・ブリーフィング・ワープ・結果・エンディング・設定
- 詳細は `docs/ARCHITECTURE.md`

## テスト
```bash
godot --headless --path . -s tests/test_history.gd          # 因果エンジン（ランダム答案200通りで必ず満点に到達できるか）
godot --headless --path . res://tests/test_missions.tscn    # 全136ミッション（34問×4択）を自動プレイして完了できるか
godot --headless --path . -s tests/test_flow.gd             # 画面遷移とセッションの一連の流れ
godot --headless --path . -s tests/parse_all.gd             # 全スクリプトの構文チェック
```

## クレジット
- 問題文はすべてオリジナルです（実際の共通テストの過去問ではありません）。
- テクスチャ・HDRI：[Poly Haven](https://polyhaven.com)（CC0）
- 人物モデル：MakeHuman / MPFB2 で自動生成（CC0）。再生成は `tools/make_humans.py`（Blender bpy + MPFB2）→ `tools/setup_retarget.gd`
- アニメーション：KayKit Character Animations — Kay Lousberg（CC0、取り込み時に人型プロファイルへリターゲット）
- フォント：Noto Sans JP / Noto Serif JP（SIL OFL 1.1）
- エンジン：Godot Engine（MIT）

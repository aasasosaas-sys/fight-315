# 歴史シミュレーション v2 データ仕様

v1（tools/SCHEMA.md）の項目はすべてそのまま有効。v2 では以下を**追加**する。
目的：1つの改変が「その後の日本のすべて」に波及する、仕組みとしての因果モデル。

## 歴史パラメータ（全時代共通・固定）
数値（-100〜100、**0 = 本来の史実**。値は「史実と比べてどれだけ強い/弱いか」）

| キー | 意味 |
|---|---|
| centralization | 中央集権の強さ（天皇・幕府・政府への権力集中） |
| warrior | 武士・軍事貴族の力 |
| court | 朝廷・貴族の力 |
| religion | 寺社・宗教勢力の力 |
| commerce | 商業・貨幣経済・都市の発達 |
| open_asia | 中国・朝鮮など大陸との交流 |
| open_west | 西洋との交流 |
| tech | 技術力（鉄器・鉄砲・工業・科学） |
| education | 教育・識字・学問 |
| commoners | 民衆・農民・町人の力 |
| militarism | 軍事優先・対外強硬 |
| democracy | 議会・民権・参政権 |
| economy | 経済規模・生産力 |
| unity | 国内の統一・安定（低いと分裂・内乱） |

カテゴリ（文字列。空 = 史実どおり）

| キー | 意味 | 値の例 |
|---|---|---|
| capital | 首都 | 奈良 / 京都 / 鎌倉 / 大坂 / 江戸 / 近江 / 博多 / 九州 など |
| ruler | 実権を握る家・勢力 | 蘇我 / 藤原 / 平氏 / 源氏 / 北条 / 足利 / 織田 / 豊臣 / 徳川 / 薩長 / 議会 / 軍部 など |
| edu_center | 学問・教育の中心地 | 奈良 / 京都 / 足利学校 / 長崎 / 大坂 / 江戸 / 東京 など |

## 条件式（"if"）
`{"warrior": ">=30", "ruler": "==織田", "capital": "!=京都"}` のように書く。全項目 AND。
数値は `>=` `<=` `>` `<`、カテゴリは `==値` `!=値`（`==` は空＝史実と比較するなら `==`）。

## Question への追加
```json
"effects": [ {}, {"warrior": 25, "unity": -15}, {"set": {"ruler": "平氏"}, "court": -20}, {...} ],
```
- 長さ4（選択肢ごと）。その選択肢が「史実」になったときにパラメータへ加える変化。
- **本来の正解（real）の effects は必ず `{}`**（基準＝0のため）。
- 数値は ±5〜40 程度。`"set"` でカテゴリを上書き。

```json
"resolve": [
  {"choice": 2, "if": {"warrior": ">=30"}, "note": "武士の力が強まっていたため、保元の乱が院政より先に起きた"},
  {"choice": 1, "if": {"court": "<=-25", "unity": "<=-20"}, "note": "..."}
]
```
- プレイヤーが直接改変していない問題で、**その年の時点のパラメータ**からどの選択肢が「史実」になるかを決める。上から順に評価し最初に一致したもの。どれも一致しなければ real。
- 2〜4本。**パラメータがすべて0（＝史実）のときに一致してはいけない**。
- しきい値は ±20〜50 程度（前の時代の大きな改変1〜2回で届く程度）。
- この問題より前の時代の改変で起こりうる、歴史的にもっともらしい因果にする。

## Mission（v1 から変更）
同じ選択肢に対して **2〜3通りの手段（method）** を用意する（`missions` 配列に choice が同じものを複数並べる）。
```json
{"choice": 1, "method": "暗殺阻止", "title": "...", "briefing": "...", "aftermath": "...", "legacy": "...",
 "effects": {"education": 10, "commoners": -5}, "steps": [...]}
```
- `method`：手段の短い名前（例：暗殺 / 暗殺阻止 / 説得 / 買収 / 妨害工作 / 機体の故障 / 書状の奪取 / 天候操作 / 護衛 / 先回り / 偽情報）。殺すだけでなく、事故・遅延・すり替え・救出など多様に。
- `effects`：その手段の**副作用**（選択肢の effects に上乗せ）。手段ごとに違うこと（例：暗殺は unity -15・militarism +10、説得は court +5）。
- 同じ choice の複数手段は、ステップ構成も違うものにする。

## Era への追加
```json
"aftermath_rules": [
  {"if": {"warrior": ">=30"}, "text": "武士の台頭が百年早まり、地方では国司より武士団が実権を握った。"},
  {"if": {"ruler": "==平氏"}, "text": "..."}
],
"baseline_text": "（何も変わっていないときに表示する、この時代のその後の史実の一文）"
```
- この時代の終わりの状態に応じて「その後の歴史」に並ぶ文章。8〜15本。具体的な固有名詞・地名・制度で。
- 誰が国を治めたか、首都、宗教、文化、教育の中心、外交、技術、民衆の暮らしなどを幅広く。

## data/modern.json（現代エンディング）
```json
{"ending_rules": [ {"if": {...}, "topic": "首相", "text": "..."} , ...], "baseline": {"首相": "...", ...}}
```
- topic ごと（首相・政治体制・首都・経済・教育・文化・外交・技術・暮らし など）に複数の分岐。最終状態で一致したものを topic ごとに最初の1つ採用。
- 首相は「どんな経歴・出自の人物か」（例：織田家の末裔、元陸軍将校、女性初の…）。実在の存命人物は使わない。

## data/chaos/<eraId>.json（自由探索の「歴史の揺らぎ」）
自由探索（ミッションなし）で人物を倒したり名所を壊したりすると、計画外に歴史が変わる。`scripts/core/chaos.gd`（ChaosTracker）が
`Game.chaos_event(kind, id, info)` を数え、条件を満たしたルールを `HistoryState.apply_chaos` で適用する。HistoryDB は data/ 直下しか読まないので、問題データには影響しない。
検証：`python3 tools/validate_chaos.py [-v]`、テスト：`godot --headless --path . -s tests/test_chaos.gd`。
```json
{"eraId": "sengoku",
 "figures": [{"name": "織田信長", "at": "village", "guards": 5, "guard": "織田家の馬廻", "lines": ["是非に及ばず。"]}],
 "rules": [
  {"id": "sg_kill_nobunaga", "title": "信長、本能寺の前に死す", "trigger": {"kind": "kill", "id": "織田信長"},
   "force": {"q": "sengoku_05", "choice": 3}, "text": "あなたのせいで織田信長が……"},
  {"id": "sg_massacre", "title": "一向一揆、燃え広がる", "trigger": {"kind": "kill", "type": "soldier", "min": 30},
   "vars": {"commoners": 30, "religion": 30}, "year": 1570, "text": "……"}]}
```
- `figures`：自由探索でその名所に立つ歴史上の人物（**その時代のミッションの npc 名**。故人のみ。天皇・宗教の開祖は対象にしない）。護衛は `guard` の名前の Enemy。
- `trigger`：辞書、または「どれか1つ」の配列。`kind`（destroy / sink / fire / bridge / kill）、`id`（名所キー・人物名、文字列か配列）、`type`（info.type。kill は figure / soldier、destroy は建物の種類 castle_keep・pagoda・hall・hangar など）、`at`（名所キー）、`min`（件数。fire は名所ごとの延焼数の最大値の合計）、`value`（destroy の info.value＝建物の格の合計）。
  破壊は建物1棟ごとに destroy が来るので、名所の破壊には `value` か `type` を必ず付ける。修正力（type guardian）は兵の数に入らない。
- `force`：問題の史実を強制する（介入 `cause: "chaos"`, `method: -1`）。本来の史実と違う選択肢にする。のちにその問題のミッション（修復ミッションは自動生成）を成功させれば上書きされる。
- `vars` + `year`：その年の時点で歴史パラメータを変える（`chaos_mods` に保存、同じルールは1回だけ）。前の時代の分は時代の区切りより前、同じ時代は year <= 問題の年 の問題より前に効く。
- `text`：HUD の「歴史が揺らいだ！」とアフター画面に出る、その時代の史実にもとづく一文（〇〇のせいで……）。民間人を標的にした描写はしない。

## data/actors/<eraId>.json と動詞（自由な歴史改変の一般則）
人物・合戦のデータ。手作りルールに当たらない行動は `scripts/core/actors.gd`（HistoryActors）の一般則で解決する。
行動は `HistoryState.actions` に記録され、`HistoryActors.resolve()` が毎回すべてを作り直す（純粋関数）。
検証：`python3 tools/validate_chaos.py --gaps --density 6`（名所の破壊ユニット表 tools/landmark_units.json は
`godot --headless --path . -s tools/dump_landmark_units.gd` で再生成）。

- 人物の項目：name / era / faction / born / died / death（natural illness assassinated killed suicide executed accident poisoned unknown）/
  active（活動開始年）/ tags / traits（open reform war loyal faith、-2..2）/ spawn / aka / successor / q /
  contrib（いなくなったとき）/ saved（非業の死・病死を防いだとき）/ doc（盗まれたとき）/ persuade / give（特例）/ schedule（予定）。
- 同じ人物を後の時代のファイルにも書くと、その時代での追加分として合成される（一覧は追加・辞書は上書き・saved/doc は差し替え・
  spawn はその時代の置き場所）。追加分の contrib・schedule はその時代以降の行動にだけ使う（前の時代の貢献を後の時代で倒して
  繰り返さない）。基本の項目（生没・死因・タグ・性格・active）は最も古い時代のもの。後の時代で行動したときの一般則の年はその時代の初め。
- successor：人物の後継者が健在なら、その人物の貢献（contrib）は引き継がれて起こらない（後継者もいなくなれば起こる）。
  contrib 単位で `"successor": ""` とすると、その貢献だけは後継者がいても失われる。
- saved の年が人物の時代の最初の問題より前なら、その年を含む時代（era_of_year）に入る。
- 説得：一般則では性格×論点（＋信頼）で受け入れが決まる。手作りルール（kind persuade）や人物の persuade 特例は「必ず受け入れる特例」。
- 手作りルールが行動に当たったときは、その行動は記録だけされ（ruled）、人物の状態（倒れた・救われた・信頼・後継者判定）には数えるが、
  一般則と人物データの効果は出さない（ルールが受け持つ）。検証の別解の数もそれに合わせて数える。
- 同じ出来事に当たるルールはすべて（各1回）発動する。同じ問題を強制するルールが複数あれば、後に書かれたもの（通し番号の新しいほう）が勝つ。
  原因つき（cause）の kill ルールを原因なしのルールの後ろに書けば、その原因のときだけ上書きになる。一度倒れた人物は二度と倒れない。
- 延焼（fire）は名所ごとに 5・12・24 棟目で通知される。min はその段に切り上がり、その名所に燃える建物が足りなければ検証エラー。
  名所ごとの通知される建物（destroy の type・value、橋、船）も tools/landmark_units.json で検証する。
- 自由探索では人物はプレイヤーから 110m 以内の近い順に最大16人だけ実体化し（護衛は1人3人・合計30人まで）、230m 離れると片づく
  （連れ回し中・予定の途中・倒れた人は残る）。予定（schedule）はその時代のものを順にこなす。
- 意図しなくても数える：倒れた原因（info.cause）は銃 shot・流れ弾 stray・爆発 explosion・火 fire・車 vehicle・馬 horse・飛行機 plane・
  追手の撃ち合い crossfire・瓦礫 debris。会話で引き止める・追い回す・けが・連れ回し・瓦礫で道がふさがる、で予定に 25 秒以上遅れると delay。
- 採点（○×・100点・エンディング）はミッションか自由な行動かを問わず、結果の歴史だけで決まる。どの問題×選択肢にも
  「未来を語る」（steer：関わる人物に未来の品を渡して信頼を得てから語る）で必ず届く。

## data/war/model.json と data/projects/<eraId>.json（太平洋戦争の帰趨と国家事業）
`scripts/core/war.gd`（WarModel）。検証：`python3 tools/validate_war.py`、テスト：`godot --headless --path . -s tests/test_war.gd`。
- 柱（pillars）：工業力・資源・科学技術・海軍航空・情報・経済・外交・文民統制。各柱は1941年の日本の力を、アメリカ（＋イギリス）を100として表す。
  `base` は史実の統計による値（例：粗鋼 1:11〜12 → 工業力12、石油の自給1割未満 → 資源8、GNP 1:10 → 経済10）。
  `basis` に年の入った史実を書き、`hint` にどの時代で変えられるかを書く（ハブの「戦局予測」で史実→この世界→変えるにはの順に出る）。
- 柱の値 ＝ base ＋ 歴史パラメータの変化（時代ごとの変化量 × vars の重み × 複利、±vars_cap）＋ 国家事業（pillars の点 × 複利）＋ 設問の史実（facts）。
  複利は「1941年まで100年ごとに growth.base 倍、上限 cap」：1560年の事業は約3倍、1880年は約1.3倍、1940年はほぼ1倍。
- 段階（tiers、上から順に判定）：開戦回避（外交・文民統制）→ 勝利（工業・資源・海軍航空・経済と総合点、技術か情報）→ 有利な休戦 → 早期講和 →
  本土決戦（総合点も文民統制も最低）→ 敗戦（史実、それ以外すべて）。総合点 ＝ 中核6柱の平均の半分 ＋ 最も弱い柱の半分（弱点があると勝てない）。
  段階の `mods` は1941年に重ねられ（HistoryState が二段階で計算）、昭和の設問・その後の歴史・令和のエンディング（modern.json の war 条件）に波及する。
- 事業：id / name / at（名所）/ year / task（defend：count 人の enemy を退ける、collect：from の名所で item を count 個集めて現場へ、talk：その場で）/
  pillars（柱の点、±12まで）/ vars（歴史パラメータ）/ requires（先に必要な事業）/ requires_pillar・alt_requires_pillar（柱の値の条件）/
  desc・basis（年の入った史実）/ text（成し遂げた結果）/ tags に colony があれば cost（現地の抵抗・統治の負担・列強との対立などの代償）必須。
- 自由探索では各事業の看板が名所に立ち、E で内容（史実・効き目・代償）を見て着手する。成し遂げると行動 verb "project" として記録される。

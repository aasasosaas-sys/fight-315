# 歴史データ JSON スキーマ

`Assets/StreamingAssets/HistoryData/<eraId>.json` に1時代1ファイル。
`Tools/validate_data.py` で検証すること。

## 時代ID（固定・この8つのみ）
| eraId | 時代 | 乗り物 |
|---|---|---|
| jomon_kofun | 縄文・弥生・古墳 | horse |
| asuka_nara | 飛鳥・奈良 | horse |
| heian | 平安 | horse |
| kamakura_muromachi | 鎌倉・室町 | horse |
| sengoku | 戦国・安土桃山 | horse |
| edo | 江戸 | horse |
| meiji_taisho | 明治・大正 | horse, car |
| showa | 昭和（戦前〜戦後） | car, plane |

## ランドマークキー（全時代共通・この7つのみ）
`capital`（都・政庁）, `village`（村・町）, `temple`（寺社）, `port`（港・海岸）,
`castle`（城・砦・官庁街）, `battlefield`（戦場・広場）, `mountain`（山・峠）
各時代ファイルで時代に合った表示名を付ける。

## ファイル構造
```json
{
  "eraId": "heian",
  "eraName": "平安時代",
  "landmarks": [ {"key": "capital", "name": "平安京 大内裏"}, ... 7件すべて ],
  "vehicles": ["horse"],
  "questions": [ Question, ... 4〜6問 ],
  "rules": [ Rule, ... ]
}
```

### Question
```json
{
  "id": "heian_01",            // <eraId>_NN
  "year": 894,                 // その出来事の西暦（因果の順序に使う。同時代内でも重複しないように）
  "topic": "遣唐使の停止",
  "text": "問題文（共通テスト風。史料・会話文・年表の読み取り風も可。オリジナル文章）",
  "choices": ["選択肢1", "選択肢2", "選択肢3", "選択肢4"],  // 4つちょうど。番号は付けない
  "real": 0,                   // 史実の正解インデックス 0-3
  "explanation": "史実の解説（2〜4文。受験に役立つポイント入り）",
  "missions": [ Mission, ... ] // real 以外の3つの選択肢それぞれに1つ（計3つ）
}
```

### Mission（「その選択肢が史実になる」ように歴史を改変するミッション）
```json
{
  "choice": 1,                 // 対応する選択肢インデックス（real以外）
  "title": "菅原道真を説得せよ",
  "briefing": "なぜこの改変が必要か、何をするか（2〜3文）",
  "aftermath": "改変直後〜その時代の世界がどうなったか（2〜3文、少しユーモア可）",
  "legacy": "この改変が令和の現代日本（2026年）に残した長期的影響（1〜2文。エンディングで他の改変と組み合わせて表示される。『〜となり、現代では〜』のように文として独立させる）",
  "steps": [ Step, ... ]       // 2〜5個
}
```

### Step（type は次の5種類のみ）
| type | 必須フィールド | 内容 |
|---|---|---|
| goto | at, text | ランドマークへ移動 |
| talk | at, npc, lines(2〜4行), text | NPCと会話 |
| defeat | at, count(3〜8), text, enemy | 敵を銃で撃退。enemy は敵の表示名（例:「平家の武者」「今川軍の足軽」「新政府軍」「米軍」「歴史の修正力」）。その時代の実在の軍勢でよい。戦国以前の武将・大名は合戦で討ち取ってよい。出題範囲（〜昭和）の実在の首相・指導者（すべて故人）は、歴史改変フィクションとして護衛部隊との戦闘の末に倒してよい（enemy に「〇〇の護衛隊」など）。史実のテロ事件も実行犯側・阻止側どちらの分岐も可。**存命の人物、平成・令和の実在の事件は扱わない**。民間人への攻撃・虐殺の描写も禁止 |
| collect | at, item, count(1〜5), text | アイテム回収 |
| ride | at, vehicle, time(30〜120秒), text | 乗り物に乗って制限時間内に到着。vehicle はその時代の vehicles に含まれるもの。plane は飛行機で、空路で目的地へ（到着時に着陸不要）。defeat ステップに "air": true を付けると上空で修正力の飛行体と空中戦になる（plane がある時代のみ） |

```json
{"type":"talk","at":"capital","npc":"菅原道真","lines":["…","…"],"text":"大内裏で道真と話す"}
```

### Rule（バタフライ効果。過去→未来方向のみ）
```json
{"ifQ":"heian_01","ifChoice":1,"thenQ":"heian_03","thenChoice":2,"note":"遣唐使が続いたので国風文化が育たず…"}
```
- ifQ の year < thenQ の year であること（因果は過去から未来へ）
- 同じ時代ファイル内の問題どうし、または過去の時代→自分の時代を参照可
- 1時代につき3〜6本

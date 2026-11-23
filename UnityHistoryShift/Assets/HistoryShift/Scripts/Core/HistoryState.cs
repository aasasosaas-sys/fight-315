using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;

namespace HistoryShift
{
    /// <summary>
    /// 世界の歴史状態（各問題について「どの選択肢が史実か」）と、受験者の確定解答を保持する因果エンジン。
    /// 状態空間は 4^問題数。ルールは「過去→未来」のみ波及するので、古い時代から順に改変すれば必ず満点に到達できる。
    /// </summary>
    public class HistoryState
    {
        const string SaveKey = "HistoryShift.Save.v1";

        public readonly HistoryDatabase Db;
        readonly Dictionary<string, int> world = new Dictionary<string, int>();
        readonly Dictionary<string, int> answers = new Dictionary<string, int>();
        public bool ExamSubmitted;
        public int Alterations;
        public int Restorations;
        public readonly List<string> Log = new List<string>();

        public HistoryState(HistoryDatabase db)
        {
            Db = db;
            ResetAll();
        }

        public void ResetAll()
        {
            world.Clear(); answers.Clear(); Log.Clear();
            foreach (var q in Db.Questions) { world[q.id] = q.real; answers[q.id] = -1; }
            ExamSubmitted = false; Alterations = 0; Restorations = 0;
        }

        public int WorldChoice(QuestionData q) => world.TryGetValue(q.id, out var v) ? v : q.real;
        public int Answer(QuestionData q) => answers.TryGetValue(q.id, out var v) ? v : -1;
        public void SetAnswer(QuestionData q, int choice) { if (!ExamSubmitted) answers[q.id] = choice; }
        public bool IsCorrect(QuestionData q) => Answer(q) >= 0 && Answer(q) == WorldChoice(q);
        public bool IsAltered(QuestionData q) => WorldChoice(q) != q.real;

        public int CorrectCount => Db.Questions.Count(IsCorrect);
        public int Score => Db.Questions.Count == 0 ? 0 : Mathf.RoundToInt(100f * CorrectCount / Db.Questions.Count);
        public bool Perfect => Db.Questions.Count > 0 && CorrectCount == Db.Questions.Count;

        /// <summary>プレイヤーの改変を適用し、ルールに従って未来へ連鎖させる。起きた変化を全て返す。</summary>
        public List<ChangeRecord> ApplyChange(QuestionData q, int choice, string cause)
        {
            var changes = new List<ChangeRecord>();
            var fired = new HashSet<RuleData>();
            var queue = new Queue<(QuestionData q, int choice, string cause, int depth)>();
            queue.Enqueue((q, choice, cause, 0));
            int guard = 0;
            while (queue.Count > 0 && guard++ < 1000)
            {
                var (cq, cc, cause2, depth) = queue.Dequeue();
                int from = WorldChoice(cq);
                if (from == cc && depth > 0) continue;
                world[cq.id] = cc;
                if (from != cc || depth == 0)
                    changes.Add(new ChangeRecord { question = cq, from = from, to = cc, cause = cause2, depth = depth });
                foreach (var r in Db.Rules)
                {
                    if (r.ifQ != cq.id || r.ifChoice != cc || fired.Contains(r)) continue;
                    fired.Add(r);
                    if (Db.ById.TryGetValue(r.thenQ, out var tq))
                        queue.Enqueue((tq, r.thenChoice, r.note, depth + 1));
                }
            }

            if (choice == q.real) Restorations++; else Alterations++;
            foreach (var c in changes)
                Log.Add($"{c.question.year}年 {c.question.topic}：{c.question.choices[c.from]} → {c.question.choices[c.to]}" +
                        (c.depth > 0 ? $"（連鎖：{c.cause}）" : $"（{c.cause}）"));
            Save();
            return changes;
        }

        /// <summary>このあと改変した場合に連鎖で影響を受ける問題を予測（ミッション前のプレビュー用）。</summary>
        public List<QuestionData> PredictRipple(QuestionData q, int choice)
        {
            var result = new List<QuestionData>();
            var seen = new HashSet<string> { q.id };
            var frontier = new List<(string, int)> { (q.id, choice) };
            while (frontier.Count > 0)
            {
                var next = new List<(string, int)>();
                foreach (var (id, c) in frontier)
                    foreach (var r in Db.Rules.Where(r => r.ifQ == id && r.ifChoice == c))
                        if (seen.Add(r.thenQ) && Db.ById.TryGetValue(r.thenQ, out var tq))
                        { result.Add(tq); next.Add((r.thenQ, r.thenChoice)); }
                frontier = next;
            }
            return result;
        }

        /// <summary>改変の組み合わせから「この世界の令和日本」エンディング文を合成する（全パターン自動生成）。</summary>
        public string ComposeEnding(out string title)
        {
            var altered = Db.Questions.Where(IsAltered).ToList();
            int n = altered.Count, total = Db.Questions.Count;
            float ratio = total == 0 ? 0 : (float)n / total;
            title = n == 0 ? "完全なる史実エンド" :
                    ratio < 0.15f ? "ちょっとだけ違う日本エンド" :
                    ratio < 0.4f ? "パラレル日本エンド" :
                    ratio < 0.7f ? "大改変日本エンド" : "もはや別の国エンド";

            var sb = new StringBuilder();
            sb.AppendLine($"2026年、令和の日本。あなたが書き換えた史実は{n}件（全{total}問中）。");
            sb.AppendLine();
            if (n == 0)
            {
                sb.AppendLine("あなたは一度も歴史を曲げることなく満点を取った。教科書は何ひとつ変わらず、時空管理局はあなたを「最も誠実な受験生」として記録した。");
                return sb.ToString();
            }
            string lastEra = null;
            foreach (var q in altered)
            {
                var m = Db.MissionFor(q, WorldChoice(q));
                if (q.era.eraName != lastEra) { sb.AppendLine($"■ {q.era.eraName}"); lastEra = q.era.eraName; }
                string legacy = string.IsNullOrEmpty(m?.legacy) ? $"「{q.choices[WorldChoice(q)]}」が史実となった。" : m.legacy;
                sb.AppendLine($"・{q.year}年 {q.topic}：{legacy}");
            }
            sb.AppendLine();
            var eras = altered.Select(q => q.era.eraName).Distinct().Count();
            sb.AppendLine(eras >= 6
                ? "時代をまたいで積み重なった改変は互いに響き合い、この国の言葉・制度・街並みは、あなたの知る日本とはまるで違うものになった。それでも共通テストの日本史は、今年も満点だった。"
                : eras >= 3
                    ? "いくつもの時代に刻まれた改変が重なり、教科書の年表は見覚えのない出来事で埋まっている。それでも答案用紙には、満点の赤い丸が並んでいた。"
                    : "大筋はあなたの知る日本のまま。だが細部の違いに気づく人は少なくない。答案は満点――ただし、それを知っているのはあなただけだ。");
            return sb.ToString();
        }

        public void Save()
        {
            var s = new SaveData { examSubmitted = ExamSubmitted, alterations = Alterations, restorations = Restorations, log = new List<string>(Log) };
            foreach (var q in Db.Questions) { s.qids.Add(q.id); s.worldChoice.Add(WorldChoice(q)); s.answers.Add(Answer(q)); }
            PlayerPrefs.SetString(SaveKey, JsonUtility.ToJson(s));
            PlayerPrefs.Save();
        }

        public bool Load()
        {
            if (!PlayerPrefs.HasKey(SaveKey)) return false;
            var s = JsonUtility.FromJson<SaveData>(PlayerPrefs.GetString(SaveKey));
            if (s == null) return false;
            ResetAll();
            for (int i = 0; i < s.qids.Count; i++)
            {
                if (!Db.ById.ContainsKey(s.qids[i])) continue;
                world[s.qids[i]] = s.worldChoice[i];
                answers[s.qids[i]] = s.answers[i];
            }
            ExamSubmitted = s.examSubmitted; Alterations = s.alterations; Restorations = s.restorations;
            Log.AddRange(s.log);
            return true;
        }

        public static bool HasSave() => PlayerPrefs.HasKey(SaveKey);
        public static void DeleteSave() { PlayerPrefs.DeleteKey(SaveKey); PlayerPrefs.Save(); }
    }
}

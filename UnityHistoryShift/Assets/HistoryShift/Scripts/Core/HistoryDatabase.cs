using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEngine;

namespace HistoryShift
{
    /// <summary>StreamingAssets/HistoryData の全JSONを読み込み、年代順の問題リストと因果ルールを保持する。</summary>
    public class HistoryDatabase
    {
        public static readonly string[] EraOrder =
        {
            "jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"
        };

        public readonly List<EraData> Eras = new List<EraData>();
        public readonly List<QuestionData> Questions = new List<QuestionData>();   // 年代順
        public readonly Dictionary<string, QuestionData> ById = new Dictionary<string, QuestionData>();
        public readonly List<RuleData> Rules = new List<RuleData>();
        public readonly List<string> LoadErrors = new List<string>();

        public static HistoryDatabase Load()
        {
            var db = new HistoryDatabase();
            string dir = Path.Combine(Application.streamingAssetsPath, "HistoryData");
            if (!Directory.Exists(dir))
            {
                db.LoadErrors.Add("HistoryData フォルダが見つかりません: " + dir);
                return db;
            }

            foreach (var file in Directory.GetFiles(dir, "*.json").OrderBy(f => f))
            {
                string json = File.ReadAllText(file, System.Text.Encoding.UTF8);
                string name = Path.GetFileName(file);
                try
                {
                    if (name.StartsWith("rules_"))
                    {
                        var rf = JsonUtility.FromJson<RulesFile>(json);
                        if (rf?.rules != null) db.Rules.AddRange(rf.rules);
                        continue;
                    }
                    var era = JsonUtility.FromJson<EraData>(json);
                    if (era == null || string.IsNullOrEmpty(era.eraId)) { db.LoadErrors.Add(name + ": eraId なし"); continue; }
                    db.Eras.Add(era);
                    if (era.rules != null) db.Rules.AddRange(era.rules);
                    if (era.questions != null)
                        foreach (var q in era.questions) { q.era = era; db.ById[q.id] = q; }
                }
                catch (System.Exception e)
                {
                    db.LoadErrors.Add(name + ": " + e.Message);
                }
            }

            db.Eras.Sort((a, b) => System.Array.IndexOf(EraOrder, a.eraId).CompareTo(System.Array.IndexOf(EraOrder, b.eraId)));
            foreach (var e in db.Eras)
                if (e.questions != null) db.Questions.AddRange(e.questions);
            db.Questions.Sort((a, b) => a.year.CompareTo(b.year));
            // 因果は過去→未来のみ（データ検証済みだが念のため）
            db.Rules.RemoveAll(r => !db.ById.ContainsKey(r.ifQ) || !db.ById.ContainsKey(r.thenQ) ||
                                    db.ById[r.ifQ].year >= db.ById[r.thenQ].year);
            return db;
        }

        public EraData GetEra(string id) => Eras.FirstOrDefault(e => e.eraId == id);

        /// <summary>
        /// (問題, 目標の選択肢) のミッションを返す。史実の選択肢へ戻す場合は「史実修復」ミッションを自動生成する。
        /// </summary>
        public MissionData MissionFor(QuestionData q, int choice)
        {
            var m = q.GetMission(choice);
            if (m != null) return m;

            bool restore = choice == q.real;
            var era = q.era;
            string[] keys = { "capital", "village", "temple", "port", "castle", "battlefield", "mountain" };
            int h = Mathf.Abs((q.id + choice).GetHashCode());
            string a = keys[h % keys.Length], b = keys[(h / 7 + 3) % keys.Length];
            if (a == b) b = keys[(h + 1) % keys.Length];
            var steps = new List<StepData>
            {
                new StepData { type = "goto", at = a, text = $"{era.LandmarkName(a)}に生じた時空の歪みへ向かう" },
                new StepData { type = "defeat", at = a, count = 4 + h % 3, text = "歪みを守る「歴史の修正力」を撃退せよ" },
                new StepData
                {
                    type = "talk", at = b, npc = "時の記録者",
                    lines = new[]
                    {
                        restore ? "歴史が本来の姿を取り戻そうとしている……。" : "この歴史を書き換えるつもりか。",
                        restore ? "記録しておこう。" + q.explanation : $"よかろう。「{q.choices[choice]}」――それがこの世界の史実だ。",
                    },
                    text = $"{era.LandmarkName(b)}で時の記録者に会う"
                }
            };
            return new MissionData
            {
                choice = choice,
                title = restore ? $"史実修復：{q.topic}" : $"時空改変：{q.topic}",
                briefing = restore
                    ? "連鎖改変の余波で、この出来事が史実から外れてしまった。歪みを正し、本来の歴史を取り戻せ。"
                    : $"「{q.choices[choice]}」が史実となるよう、歴史の分岐点に介入せよ。",
                aftermath = restore ? "歴史は本来の流れに戻った。" : "歴史は静かに別の道を歩み始めた。",
                legacy = restore ? "" : $"{era.eraName}に「{q.choices[choice]}」という史実が刻まれ、現代の教科書もそのように書かれている。",
                steps = steps.ToArray()
            };
        }
    }
}

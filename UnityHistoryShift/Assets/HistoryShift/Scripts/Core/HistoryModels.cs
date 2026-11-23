using System;
using System.Collections.Generic;

namespace HistoryShift
{
    // StreamingAssets/HistoryData/*.json の構造（Tools/SCHEMA.md 参照）。JsonUtility で読むため配列のみ。

    [Serializable]
    public class LandmarkDef
    {
        public string key;
        public string name;
    }

    [Serializable]
    public class StepData
    {
        public string type;      // goto / talk / defeat / collect / ride
        public string at;        // landmark key
        public string text;
        public string npc;
        public string[] lines;
        public int count;
        public string item;
        public string vehicle;   // horse / car / plane
        public float time;
        public bool air;         // defeat を上空戦にする
        public string enemy;     // 敵の表示名（実在の軍勢 or 歴史の修正力）
    }

    [Serializable]
    public class MissionData
    {
        public int choice;
        public string title;
        public string briefing;
        public string aftermath;
        public string legacy;
        public StepData[] steps;
    }

    [Serializable]
    public class QuestionData
    {
        public string id;
        public int year;
        public string topic;
        public string text;
        public string[] choices;
        public int real;
        public string explanation;
        public MissionData[] missions;

        [NonSerialized] public EraData era;

        public MissionData GetMission(int choice)
        {
            if (missions != null)
                foreach (var m in missions)
                    if (m.choice == choice) return m;
            return null;
        }
    }

    [Serializable]
    public class RuleData
    {
        public string ifQ;
        public int ifChoice;
        public string thenQ;
        public int thenChoice;
        public string note;
    }

    [Serializable]
    public class EraData
    {
        public string eraId;
        public string eraName;
        public LandmarkDef[] landmarks;
        public string[] vehicles;
        public QuestionData[] questions;
        public RuleData[] rules;

        public string LandmarkName(string key)
        {
            if (landmarks != null)
                foreach (var l in landmarks)
                    if (l.key == key) return l.name;
            return key;
        }

        public bool HasVehicle(string v) => vehicles != null && Array.IndexOf(vehicles, v) >= 0;
    }

    [Serializable]
    public class RulesFile
    {
        public RuleData[] rules;
    }

    /// <summary>連鎖によって起きた1件の変化。</summary>
    public class ChangeRecord
    {
        public QuestionData question;
        public int from;
        public int to;
        public string cause;     // ミッション名 or ルールの note
        public int depth;        // 0 = プレイヤーが直接起こした改変
    }

    /// <summary>セーブデータ。</summary>
    [Serializable]
    public class SaveData
    {
        public List<string> qids = new List<string>();
        public List<int> worldChoice = new List<int>();   // 世界の「史実」
        public List<int> answers = new List<int>();       // 受験者の確定解答 (-1 = 未解答)
        public bool examSubmitted;
        public int alterations;
        public int restorations;
        public List<string> log = new List<string>();
    }
}

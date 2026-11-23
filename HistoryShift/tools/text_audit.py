#!/usr/bin/env python3
"""結果テキストの文章品質監査（読み物として飽きないか）。

使い方:
  python3 tools/text_audit.py            # 要約と、問題の多い100件
  python3 tools/text_audit.py -n 30      # 上位30件だけ
  python3 tools/text_audit.py --json out.json   # 全テキストのスコアをJSONで書き出す（書き直し作業用）
  python3 tools/text_audit.py --summary  # 要約の数値だけ

対象:
  data/<era>.json      … missions[].briefing / aftermath / legacy、aftermath_rules[].text、baseline_text
  data/chaos/*.json    … rules[].text
  data/actors/*.json   … contrib[].note / saved.text / persuade.*.text / give.*.text / doc.text / schedule[].text、battles[].sides[].text
  data/projects/*.json … projects[].text / cost
  data/modern.json     … ending_rules[].text（文字列または候補の配列）、baseline

見るもの:
  長さ、書き出し・結び（文字 n-gram）の偏り、使い古された言い回し、重複・ほぼ重複、
  因果のつなぎ（〜ため・〜ので・〜により…）の欠如、文末の単調さ（「〜た。」の連続）、
  並んで表示されうる文章どうしの同じ断片（同じ時代の aftermath_rules、同じミッションの aftermath と legacy、
  同じ人物の文章どうし）。
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = os.path.join(ROOT, "data")

# 「結果の文章」（改変の結末を読ませるもの）。ブリーフィングや人物の貢献メモは因果チェックを緩める。
RESULT_KINDS = {"aftermath", "legacy", "era_rule", "chaos", "saved", "persuade", "give", "doc", "schedule",
                "battle", "project", "modern"}

OVERUSED = [
    ("のせいで", r"のせいで"),
    ("あなたが", r"^あなたが|。あなたが"),
    ("だった。", r"だった。"),
    ("結果、", r"結果、"),
    ("その結果", r"その結果"),
    ("ことになった", r"ことになった"),
    ("ようになった", r"ようになった"),
    ("こうして", r"こうして"),
    ("未来の", r"未来の"),
    ("一気に", r"一気に"),
    ("すっかり", r"すっかり"),
    ("大激怒/激怒", r"激怒"),
    ("〜てしまった", r"てしまった"),
    ("現代でも/現代の日本", r"現代でも|現代の日本"),
    ("いまも/今も", r"いまも|今も"),
    ("と呼ばれ", r"と呼ばれ"),
    ("恒例", r"恒例"),
    ("名物", r"名物"),
]

CAUSAL = re.compile(
    r"ため|ので|から[、。]|からこそ|により|によって|せいで|おかげで|結果|こうして|きっかけ|を受けて|ことで|"
    r"を機に|ゆえ|代わりに|に乗じ|を恐れ|を嫌|と知|と考え|を見て|に懲り|を失|をもとに|を口実|と悟|に驚|に怒|"
    r"に震え|を手に|ばかりに|以来|すると|を背景|あおり|が響|が効|に押され|を得て|に支えられ|理由|原因|発端|のもとで|"
    r"に感銘|に励まされ|に目覚め|を知った|をきっかけ|がなければ|いなければ|なかったら|なくなり|おかげ|に味をしめ|"
    r"ず、|ずに|うちに|あまり|と聞|に焦|あわて|慌て|根負け|業を煮や|見かね|あきらめ|に喜|せいか|とあって|だけに|"
    r"からだ|からで|からである|せいだ|せいで|せいか|名残|由来|にちなむ|にちなん|の結果|に行き着|がもとで|もとになっ|が生んだ|生まれた言葉|だけでは|がいない|が倒れ|を欠い|を奪われ|抜きで|なしに|なければ|と見た|と判断|に頼|を頼|に備え|に代わ|を逃|裏目"
)
SENT_SPLIT = re.compile(r"(?<=[。！？])")
CHRONICLE = re.compile(r"^(\d{3,4}年|[^\s、。]{1,6}元年)")


def era_of(path):
    return os.path.splitext(os.path.basename(path))[0]


def collect():
    """[{file, era, kind, path(list), text, group}] を返す。group は並んで表示されうる文章のまとまり。"""
    out = []

    def add(fp, kind, path, text, group=""):
        if isinstance(text, str) and text.strip():
            out.append({"file": os.path.relpath(fp, ROOT), "era": era_of(fp), "kind": kind, "path": path,
                        "text": text, "group": group})

    for fp in sorted(glob.glob(os.path.join(DATA, "*.json"))):
        d = json.load(open(fp, encoding="utf-8"))
        name = os.path.basename(fp)
        if name == "modern.json":
            for i, r in enumerate(d.get("ending_rules", [])):
                t = r.get("text")
                if isinstance(t, list):
                    for j, v in enumerate(t):
                        add(fp, "modern", ["ending_rules", i, "text", j], v, "modern:" + r.get("topic", ""))
                else:
                    add(fp, "modern", ["ending_rules", i, "text"], t, "modern:" + r.get("topic", ""))
            for k, t in d.get("baseline", {}).items():
                if isinstance(t, list):
                    for j, v in enumerate(t):
                        add(fp, "modern", ["baseline", k, j], v, "modern:" + k)
                else:
                    add(fp, "modern", ["baseline", k], t, "modern:" + k)
            continue
        if "questions" not in d:
            continue
        era = d.get("eraId", era_of(fp))
        for qi, q in enumerate(d["questions"]):
            for mi, m in enumerate(q.get("missions", [])):
                g = "mission:%s:%d" % (q.get("id"), mi)
                for k in ("briefing", "aftermath", "legacy"):
                    add(fp, k, ["questions", qi, "missions", mi, k], m.get(k), g)
        for i, r in enumerate(d.get("aftermath_rules", [])):
            add(fp, "era_rule", ["aftermath_rules", i, "text"], r.get("text"), "era_rules:" + era)
        add(fp, "era_rule", ["baseline_text"], d.get("baseline_text"), "era_rules:" + era)

    for fp in sorted(glob.glob(os.path.join(DATA, "chaos", "*.json"))):
        d = json.load(open(fp, encoding="utf-8"))
        for i, r in enumerate(d.get("rules", [])):
            add(fp, "chaos", ["rules", i, "text"], r.get("text"), "chaos:" + d.get("eraId", ""))

    for fp in sorted(glob.glob(os.path.join(DATA, "actors", "*.json"))):
        d = json.load(open(fp, encoding="utf-8"))
        for ai, a in enumerate(d.get("actors", [])):
            g = "actor:" + a.get("name", str(ai))
            for ci, c in enumerate(a.get("contrib", [])):
                add(fp, "contrib", ["actors", ai, "contrib", ci, "note"], c.get("note"), g)
            if isinstance(a.get("saved"), dict):
                add(fp, "saved", ["actors", ai, "saved", "text"], a["saved"].get("text"), g)
            if isinstance(a.get("doc"), dict):
                add(fp, "doc", ["actors", ai, "doc", "text"], a["doc"].get("text"), g)
            for key in ("persuade", "give"):
                for k, v in (a.get(key) or {}).items():
                    if isinstance(v, dict):
                        add(fp, key, ["actors", ai, key, k, "text"], v.get("text"), g)
            for si, s in enumerate(a.get("schedule", [])):
                add(fp, "schedule", ["actors", ai, "schedule", si, "text"], s.get("text"), g)
        for bi, b in enumerate(d.get("battles", [])):
            for si, s in enumerate(b.get("sides", [])):
                add(fp, "battle", ["battles", bi, "sides", si, "text"], s.get("text"), "battle:" + b.get("id", ""))

    for fp in sorted(glob.glob(os.path.join(DATA, "projects", "*.json"))):
        d = json.load(open(fp, encoding="utf-8"))
        for pi, p in enumerate(d.get("projects", [])):
            add(fp, "project", ["projects", pi, "text"], p.get("text"), "project:" + p.get("id", ""))
            add(fp, "project_cost", ["projects", pi, "cost"], p.get("cost"), "project:" + p.get("id", ""))
    return out


def grams(s, n=4):
    s = re.sub(r"[、。「」『』（）・！？\s]", "", s)
    return {s[i:i + n] for i in range(max(0, len(s) - n + 1))}


def common_sub(a, b, minlen=14):
    """a と b に共通する最長の部分文字列（minlen 以上なら返す）。"""
    best = ""
    for i in range(len(a) - minlen + 1):
        k = minlen
        if a[i:i + k] not in b:
            continue
        while i + k <= len(a) and a[i:i + k] in b:
            k += 1
        if k - 1 > len(best):
            best = a[i:i + k - 1]
    return best if len(best) >= minlen else ""


def sentences(t):
    return [s for s in SENT_SPLIT.split(t) if s.strip()]


def audit(items):
    opens = Counter(it["text"][:5] for it in items)
    ends = Counter(it["text"][-6:] for it in items)
    phrase_tot = Counter()
    for it in items:
        it["issues"] = []
        it["score"] = 0.0
        t = it["text"]
        L = len(t)
        it["len"] = L
        res = it["kind"] in RESULT_KINDS
        # 長さ
        if res and L < 40:
            it["issues"].append("短い(%d)" % L); it["score"] += 1.5
        if L > 170:
            it["issues"].append("長い(%d)" % L); it["score"] += 1.0 + (L - 170) / 60
        # 書き出し・結びの偏り
        o = opens[t[:5]]
        if o >= 6:
            it["issues"].append("書き出し「%s」×%d" % (t[:5], o)); it["score"] += min(4.0, o / 6)
        e = ends[t[-6:]]
        if e >= 4:
            it["issues"].append("結び「%s」×%d" % (t[-6:], e)); it["score"] += min(3.0, e / 4)
        # 使い古しの言い回し
        for label, pat in OVERUSED:
            c = len(re.findall(pat, t))
            if c:
                phrase_tot[label] += c
        if len(re.findall(r"のせいで", t)):
            it["issues"].append("「のせいで」"); it["score"] += 1.0
        if re.search(r"^あなた", t):
            it["issues"].append("「あなた」始まり"); it["score"] += 0.8
        c = len(re.findall(r"だった。", t))
        if c >= 2:
            it["issues"].append("「だった。」×%d" % c); it["score"] += 0.6 * c
        c = len(re.findall(r"ことになった|ようになった", t))
        if c >= 2:
            it["issues"].append("「〜になった」×%d" % c); it["score"] += 0.6 * c
        # 文末の単調さ
        ss = sentences(t)
        it["sents"] = len(ss)
        tail = [s.rstrip("。！？」』")[-1:] for s in ss]
        if len(ss) >= 3 and all(x == "た" for x in tail):
            it["issues"].append("文末すべて「た」(%d文)" % len(ss)); it["score"] += 1.2
        # 因果
        it["causal"] = bool(CAUSAL.search(t))
        if res and not it["causal"] and it["kind"] not in ("contrib",):
            it["issues"].append("因果のつなぎなし"); it["score"] += 1.5
    # 重複・ほぼ重複（同じ種類どうし）
    by_kind = defaultdict(list)
    for idx, it in enumerate(items):
        it["gram"] = grams(it["text"])
        by_kind[it["kind"] if it["kind"] != "legacy" else "aftermath"].append(idx)
    dup_pairs = []
    for kind, idxs in by_kind.items():
        inv = defaultdict(list)
        for i in idxs:
            for g in items[i]["gram"]:
                inv[g].append(i)
        shared = Counter()
        for g, lst in inv.items():
            if len(lst) > 40:
                continue
            for x in range(len(lst)):
                for y in range(x + 1, len(lst)):
                    shared[(lst[x], lst[y])] += 1
        for (a, b), c in shared.items():
            ga, gb = items[a]["gram"], items[b]["gram"]
            j = c / max(1, len(ga | gb))
            if j >= 0.45:
                dup_pairs.append((j, a, b))
    for j, a, b in dup_pairs:
        for x, y in ((a, b), (b, a)):
            items[x]["issues"].append("ほぼ重複%.2f↔%s" % (j, items[y]["text"][:14]))
            items[x]["score"] += 2.0 + 4 * (j - 0.45)
    # 並んで出る文章どうしの同じ断片
    groups = defaultdict(list)
    for idx, it in enumerate(items):
        if it["group"] and it["kind"] not in ("briefing", "contrib"):
            groups[it["group"]].append(idx)
    adj_pairs = 0
    for g, idxs in groups.items():
        for x in range(len(idxs)):
            for y in range(x + 1, len(idxs)):
                a, b = items[idxs[x]], items[idxs[y]]
                cs = common_sub(a["text"], b["text"], 16)
                if cs:
                    adj_pairs += 1
                    for it in (a, b):
                        it["issues"].append("隣の文と同じ断片「%s」" % cs[:16]); it["score"] += 1.0
    return {"opens": opens, "ends": ends, "phrases": phrase_tot, "dup_pairs": dup_pairs, "adj_pairs": adj_pairs}


def summary(items, st):
    lens = sorted(it["len"] for it in items)
    res = [it for it in items if it["kind"] in RESULT_KINDS]
    kinds = Counter(it["kind"] for it in items)
    lines = []
    lines.append("テキスト数 %d（結果の文章 %d）  種類: %s" % (len(items), len(res), ", ".join("%s %d" % kv for kv in sorted(kinds.items()))))
    lines.append("長さ: 平均 %.0f  中央 %d  最短 %d  最長 %d  （40字未満の結果文 %d、170字超 %d）" % (
        sum(lens) / len(lens), lens[len(lens) // 2], lens[0], lens[-1],
        sum(1 for it in res if it["len"] < 40), sum(1 for it in items if it["len"] > 170)))
    top_o = [(k, v) for k, v in st["opens"].most_common(12) if v >= 4]
    top_e = [(k, v) for k, v in st["ends"].most_common(12) if v >= 4]
    lines.append("書き出し（5字）6回以上: %d種 / 計%d件  上位: %s" % (
        sum(1 for v in st["opens"].values() if v >= 6), sum(v for v in st["opens"].values() if v >= 6),
        "、".join("「%s」%d" % kv for kv in top_o)))
    lines.append("結び（6字）4回以上: %d種 / 計%d件  上位: %s" % (
        sum(1 for v in st["ends"].values() if v >= 4), sum(v for v in st["ends"].values() if v >= 4),
        "、".join("「%s」%d" % kv for kv in top_e)))
    lines.append("言い回し: " + "、".join("%s %d" % (k, st["phrases"][k]) for k, _ in OVERUSED))
    lines.append("ほぼ重複のペア %d  並んで出うる文の同じ断片 %d" % (len(st["dup_pairs"]), st["adj_pairs"]))
    nc = [it for it in res if not it["causal"]]
    lines.append("因果のつなぎがない結果文 %d / %d" % (len(nc), len(res)))
    mono = sum(1 for it in items if any(s.startswith("文末すべて") for s in it["issues"]))
    lines.append("文末がすべて「た」の文章（3文以上） %d" % mono)
    styles = Counter()
    for it in res:
        t = it["text"]
        if CHRONICLE.search(t): styles["年代記"] += 1
        if t.startswith("【") or "号外" in t or "見出し" in t: styles["見出し/号外"] += 1
        if "瓦版" in t or "読売" in t: styles["瓦版"] += 1
        if re.search(r"「[^」]{4,}」と(言|語|詠|記|書|笑|嘆|叫|つぶや)", t): styles["人物の言葉"] += 1
        if re.search(r"(詠|狂歌|和歌|落首)", t): styles["和歌/狂歌"] += 1
    lines.append("文体の幅（結果文）: " + "、".join("%s %d" % kv for kv in styles.items()))
    flagged = sum(1 for it in items if it["score"] > 0)
    lines.append("問題ありの文章 %d / %d、スコア合計 %.1f、上位100件の合計 %.1f" % (
        flagged, len(items), sum(it["score"] for it in items),
        sum(sorted((it["score"] for it in items), reverse=True)[:100])))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=100)
    ap.add_argument("--json")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--kind", help="この種類だけ一覧（aftermath, chaos, ...）")
    a = ap.parse_args()
    items = collect()
    st = audit(items)
    print(summary(items, st))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump([{k: v for k, v in it.items() if k != "gram"} for it in items], f, ensure_ascii=False, indent=1)
    if a.summary:
        return
    pool = [it for it in items if not a.kind or it["kind"] == a.kind]
    pool.sort(key=lambda it: -it["score"])
    print("\n―― 問題の多い%d件 ――" % a.n)
    for i, it in enumerate(pool[:a.n], 1):
        print("%3d. [%.1f] %s %s %s" % (i, it["score"], it["file"], it["kind"], "/".join(map(str, it["path"]))))
        print("     " + it["text"])
        print("     → " + "；".join(it["issues"]))


if __name__ == "__main__":
    sys.exit(main())

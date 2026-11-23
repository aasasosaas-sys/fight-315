#!/usr/bin/env python3
"""歴史データJSONの検証。使い方: python3 Tools/validate_data.py [file.json ...]
引数なしなら data/ 以下すべてを検証し、因果グラフ全体もチェックする。"""
import json, sys, os, glob

ERAS = ["jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"]
VEH = {"jomon_kofun": ["horse"], "asuka_nara": ["horse"], "heian": ["horse"], "kamakura_muromachi": ["horse"],
       "sengoku": ["horse"], "edo": ["horse"], "meiji_taisho": ["horse", "car"], "showa": ["car", "plane"]}
LM = {"capital", "village", "temple", "port", "castle", "battlefield", "mountain"}
STEP_REQ = {"goto": ["at", "text"], "talk": ["at", "npc", "lines", "text"], "defeat": ["at", "count", "text", "enemy"],
            "collect": ["at", "item", "count", "text"], "ride": ["at", "vehicle", "time", "text"]}

errors = []
def err(f, msg): errors.append(f"{os.path.basename(f)}: {msg}")

def check_file(path, allq):
    try:
        d = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        err(path, f"JSON parse error: {e}"); return None
    if os.path.basename(path).startswith("rules_") or os.path.basename(path) == "modern.json":
        return d
    era = d.get("eraId")
    if era not in ERAS: err(path, f"bad eraId {era}")
    if not d.get("eraName"): err(path, "eraName missing")
    keys = {l.get("key") for l in d.get("landmarks", [])}
    if keys != LM: err(path, f"landmarks must be exactly {sorted(LM)}, got {sorted(k for k in keys if k)}")
    for l in d.get("landmarks", []):
        if not l.get("name"): err(path, f"landmark {l.get('key')} has no name")
    if d.get("vehicles") != VEH.get(era): err(path, f"vehicles must be {VEH.get(era)}")
    qs = d.get("questions", [])
    if not 4 <= len(qs) <= 6: err(path, f"need 4-6 questions, got {len(qs)}")
    for q in qs:
        qid = q.get("id", "?")
        if not str(qid).startswith(f"{era}_"): err(path, f"{qid}: id must start with {era}_")
        if qid in allq: err(path, f"{qid}: duplicate id")
        allq[qid] = q
        for k in ["year", "topic", "text", "explanation"]:
            if q.get(k) in (None, ""): err(path, f"{qid}: missing {k}")
        if not isinstance(q.get("year"), int): err(path, f"{qid}: year must be int")
        ch = q.get("choices", [])
        if len(ch) != 4 or not all(isinstance(c, str) and c for c in ch): err(path, f"{qid}: need 4 non-empty choices")
        real = q.get("real")
        if real not in (0, 1, 2, 3): err(path, f"{qid}: bad real")
        ms = q.get("missions", [])
        got = sorted(set(m.get("choice") for m in ms))
        want = sorted(i for i in range(4) if i != real)
        if got != want: err(path, f"{qid}: missions must cover choices {want}, got {got}")
        for m in ms:
            tag = f"{qid}/m{m.get('choice')}"
            for k in ["title", "briefing", "aftermath", "legacy"]:
                if not m.get(k): err(path, f"{tag}: missing {k}")
            st = m.get("steps", [])
            if not 2 <= len(st) <= 5: err(path, f"{tag}: need 2-5 steps")
            for s in st:
                t = s.get("type")
                if t not in STEP_REQ: err(path, f"{tag}: bad step type {t}"); continue
                for k in STEP_REQ[t]:
                    if s.get(k) in (None, "", []): err(path, f"{tag}: {t} step missing {k}")
                if s.get("at") not in LM: err(path, f"{tag}: bad landmark {s.get('at')}")
                if t == "talk" and not (2 <= len(s.get("lines", [])) <= 4): err(path, f"{tag}: talk needs 2-4 lines")
                if t == "defeat" and not (3 <= s.get("count", 0) <= 8): err(path, f"{tag}: defeat count 3-8")
                if t == "collect" and not (1 <= s.get("count", 0) <= 5): err(path, f"{tag}: collect count 1-5")
                if s.get("air") and "plane" not in VEH.get(era, []): err(path, f"{tag}: air combat only where plane exists")
                if t == "ride":
                    if s.get("vehicle") not in VEH.get(era, []): err(path, f"{tag}: vehicle not allowed in {era}")
                    if not (30 <= s.get("time", 0) <= 120): err(path, f"{tag}: ride time 30-120")
    return d

def main():
    base = os.path.join(os.path.dirname(__file__), "..", "data")
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(base, "*.json")))
    allq, docs = {}, []
    for f in files:
        d = check_file(f, allq)
        if d: docs.append((f, d))
    nrules = 0
    for f, d in docs:
        for r in d.get("rules", []):
            nrules += 1
            a, b = allq.get(r.get("ifQ")), allq.get(r.get("thenQ"))
            if not a or not b: err(f, f"rule refers to unknown question {r.get('ifQ')} -> {r.get('thenQ')}"); continue
            if r.get("ifChoice") not in (0, 1, 2, 3) or r.get("thenChoice") not in (0, 1, 2, 3): err(f, f"rule bad choice {r}")
            if not a["year"] < b["year"]: err(f, f"rule {r['ifQ']}->{r['thenQ']}: cause year must be earlier")
            if not r.get("note"): err(f, f"rule {r['ifQ']}->{r['thenQ']} missing note")
    for e in errors: print("ERROR", e)
    print(f"{len(files)} files, {len(allq)} questions, {nrules} rules, {len(errors)} errors")
    if allq: print(f"history state space: 4^{len(allq)} = {4**len(allq):,}")
    sys.exit(1 if errors else 0)

if __name__ == "__main__":
    main()

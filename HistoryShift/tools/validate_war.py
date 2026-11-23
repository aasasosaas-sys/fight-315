#!/usr/bin/env python3
"""太平洋戦争の帰趨モデル（data/war/model.json）と国家事業（data/projects/<era>.json）の検証。
python3 tools/validate_war.py [--min-projects N]

- 柱：id・name・base（0..100、史実の統計による）・vars の重み・basis（年の入った史実）・hint
- 段階：開戦回避・勝利・有利な休戦・早期講和・本土決戦・敗戦（historical）。mods の形式
- 事業：各時代に N 件以上（既定4）、名所・年（その時代の範囲）・task（defend / collect / talk）・pillars・basis（年の入った史実）・
  text・requires（存在して、同じ時代か前の時代）・植民地（tags に colony）は cost（代償）が必須
- どの柱も3つ以上の時代の事業で強められること
（勝ち筋の探索は tests/test_war.gd：単独の事業では勝てない・深い戦略なら勝てる・開戦を避ける道がある）
"""
import glob, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_v2 import NUM, CAT, eff_ok, errors, err  # noqa: E402

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
ERA_ORDER = ["jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"]
LANDMARKS = ["capital", "village", "temple", "port", "castle", "battlefield", "mountain"]
TIERS = ["開戦回避", "勝利", "有利な休戦", "早期講和", "本土決戦", "敗戦"]
DATED = re.compile(r"\d{3,4}年")


def main():
    n_min = int(sys.argv[sys.argv.index("--min-projects") + 1]) if "--min-projects" in sys.argv else 4
    m = json.load(open(os.path.join(BASE, "war", "model.json"), encoding="utf-8"))
    eras = {}
    for f in glob.glob(os.path.join(BASE, "*.json")):
        d = json.load(open(f, encoding="utf-8"))
        if "questions" in d:
            eras[d["eraId"]] = [int(q["year"]) for q in d["questions"]]
    pids = []
    for pl in m.get("pillars", []):
        w = f"pillar {pl.get('id')}"
        pids.append(pl.get("id"))
        if not pl.get("name") or not isinstance(pl.get("base"), (int, float)) or not 0 <= pl["base"] <= 100: err(f"{w}: name/base")
        for v in pl.get("vars", {}):
            if v not in NUM: err(f"{w}: bad var {v}")
        if not DATED.search(pl.get("basis", "")): err(f"{w}: basis needs a dated real fact (…年)")
        if not pl.get("hint"): err(f"{w}: hint")
    for c in m.get("core", []):
        if c not in pids: err(f"core {c} unknown")
    seen = []
    for t in m.get("tiers", []):
        w = f"tier {t.get('id')}"
        seen.append(t.get("id"))
        if t.get("id") not in TIERS: err(f"{w}: unknown tier")
        if not t.get("summary"): err(f"{w}: summary")
        eff_ok(t.get("mods", {}), w)
        for c in [t.get("if", {})] + t.get("if_any", []) + [t.get("if_max", {})]:
            for k in c:
                if k not in pids + ["score", "any", "core_at_least"]: err(f"{w}: bad condition {k}")
    if sorted(seen) != sorted(TIERS): err(f"tiers must be exactly {TIERS}")
    if [t for t in m["tiers"] if t.get("historical")] != [m["tiers"][-1]]: err("the last tier must be the only historical one")

    projects = {}
    per_era = {}
    pillar_eras = {p: set() for p in pids}
    for f in sorted(glob.glob(os.path.join(BASE, "projects", "*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        era = d.get("eraId")
        if era not in eras: err(f"{f}: unknown era"); continue
        for pr in d.get("projects", []):
            w = f"projects/{era}:{pr.get('id')}"
            if not pr.get("id") or pr["id"] in projects: err(f"{w}: missing/duplicate id")
            pr["_era"] = era
            projects[pr["id"]] = pr
            per_era[era] = per_era.get(era, 0) + 1
            if pr.get("at") not in LANDMARKS: err(f"{w}: bad at")
            y = pr.get("year")
            ys = eras[era]
            if not isinstance(y, int) or not (min(ys) - 400 <= y <= max(ys) + 50): err(f"{w}: year {y} outside era")
            t = pr.get("task", {})
            if t.get("type") not in ("defend", "collect", "talk"): err(f"{w}: task type")
            if t.get("type") == "defend" and (not t.get("enemy") or not 1 <= int(t.get("count", 0)) <= 8): err(f"{w}: defend enemy/count")
            if t.get("type") == "collect" and (not t.get("item") or t.get("from") not in LANDMARKS or not 1 <= int(t.get("count", 0)) <= 6): err(f"{w}: collect item/from/count")
            if not pr.get("pillars"): err(f"{w}: pillars")
            for k, v in pr.get("pillars", {}).items():
                if k not in pids or not isinstance(v, int) or abs(v) > 12: err(f"{w}: bad pillar {k}:{v}")
                if v > 0: pillar_eras[k].add(era)
            if "vars" in pr: eff_ok(pr["vars"], w)
            for k in ("name", "desc", "text"):
                if not pr.get(k): err(f"{w}: {k}")
            if not DATED.search(pr.get("basis", "")): err(f"{w}: basis needs a dated real fact (…年)")
            if "colony" in pr.get("tags", []) and not pr.get("cost"): err(f"{w}: colonial projects must state their cost")
            for k in ("requires_pillar", "alt_requires_pillar"):
                for kk in pr.get(k, {}):
                    if kk not in pids: err(f"{w}: {k} {kk}")
    for pr in projects.values():
        for r in pr.get("requires", []):
            if r not in projects: err(f"{pr['id']}: requires unknown {r}")
            elif ERA_ORDER.index(projects[r]["_era"]) > ERA_ORDER.index(pr["_era"]): err(f"{pr['id']}: requires a later-era project {r}")
    for e in ERA_ORDER:
        if per_era.get(e, 0) < n_min: err(f"{e}: needs >= {n_min} projects, got {per_era.get(e, 0)}")
    for p, es in pillar_eras.items():
        if len(es) < 3: err(f"pillar {p}: reachable from only {len(es)} eras {sorted(es)} (need 3)")
    # 国際的地位の推移（data/war/standing.json）
    sp = os.path.join(BASE, "war", "standing.json")
    if os.path.exists(sp):
        S = json.load(open(sp, encoding="utf-8"))
        tiers = [t["id"] for t in S.get("tiers", [])]
        if len(tiers) < 4 or [t["min"] for t in S["tiers"]] != sorted(t["min"] for t in S["tiers"]): err("standing: tiers must be >= 4 and sorted by min")
        if S.get("power_tier") not in tiers: err("standing: power_tier")
        ys = [c.get("year") for c in S.get("checkpoints", [])]
        if ys != sorted(ys) or len(ys) < 5: err("standing: checkpoints must be >= 5 and in order")
        for c in S.get("checkpoints", []):
            if not 0 <= c.get("base", -1) <= 100: err(f"standing {c.get('year')}: base")
            if not DATED.search(c.get("basis", "")): err(f"standing {c.get('year')}: basis needs a dated real fact")
        qs = {}
        for f in glob.glob(os.path.join(BASE, "*.json")):
            d = json.load(open(f, encoding="utf-8"))
            for q in d.get("questions", []): qs[q["id"]] = q
        for f in S.get("facts", []):
            q = qs.get(f.get("q"))
            if q is None or f.get("choice") not in (0, 1, 2, 3) or f["choice"] == q["real"]: err(f"standing fact {f}: q/choice")
            if not f.get("note") or not isinstance(f.get("from"), int): err(f"standing fact {f.get('q')}: note/from")
        for c in S.get("consequences", []):
            eff_ok(c.get("mods", {}), f"standing consequence {c.get('year')}")
            if not c.get("text") or not DATED.search(c.get("basis", "")): err(f"standing consequence {c.get('year')}: text / dated basis")
        if sorted(S.get("endings", {}).keys()) != sorted(tiers): err("standing: endings for every tier")
        mod = json.load(open(os.path.join(BASE, "modern.json"), encoding="utf-8"))
        for t in tiers:
            if not any(r.get("if", {}).get("standing") == "==" + t for r in mod["ending_rules"]): err(f"modern.json: no ending rule for standing {t}")
        print(f"standing: {len(ys)} checkpoints, {len(tiers)} tiers, {len(S.get('facts', []))} facts, {len(S.get('consequences', []))} consequences")
    if errors:
        for e in errors: print("ERROR", e)
        print(f"{len(errors)} errors"); sys.exit(1)
    print(f"{len(projects)} projects (" + ", ".join(f"{e}={per_era.get(e, 0)}" for e in ERA_ORDER) + ")")
    print("pillar eras: " + ", ".join(f"{p}={len(es)}" for p, es in pillar_eras.items()))
    print("OK")


if __name__ == "__main__":
    main()

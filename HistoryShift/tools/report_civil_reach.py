#!/usr/bin/env python3
"""民間人の犠牲だけで届く 問題×選択肢 の報告（data/chaos_civil。設定「民間人への危害（成人向け）」）。
python3 tools/report_civil_reach.py [-v] [--json tools/civil_reach.json] [--samples N]

- 形式チェック：ルールの id・trigger（kind casualty・at・role・min）・vars（±20 まで）・year（その時代の範囲）・text・basis（年の入った史実）、
  force は使わない（民間人の犠牲で試験の答えを直接書き換えない）。除外（exclusions.json）の名所に当たるルールはエラー。
- 到達の探索：各時代で、名所ごとの犠牲者数をルールのしきい値の組み合わせで総当たりし、実際に起こりうる「発動するルールの組」を求める
  （名所の役割＝農民・職人… は data の roles で決まる。合計の条件は町なか（town）の犠牲でも満たせる）。
  その組を、問題の時代と、それより前の時代1つずつ・前の時代すべて最大・ランダムな組み合わせ（--samples）で重ね、
  tools/validate_chaos.py と同じ simulate で「どの問題がどの選択肢になるか」を数える。
- 人の数・職人の技の損失（unrest でないルール）は recover 年後に打ち消される（scripts/core/chaos.gd _add_recovery）。
- 限界：太平洋戦争の帰趨（war 段階）・国際的地位（standing）の二段階計算は含めない（昭和の問題は、柱の変化を通した波及を数えない）。
  ゲーム内の結果は scripts/core/history_state.gd が決める。tests/test_civil.gd が --json の例を実際の HistoryState で確かめる。
"""
import itertools, json, os, random, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_chaos import load_eras, simulate, era_of_year, ERA_ORDER, LANDMARKS  # noqa: E402
from validate_v2 import NUM, eff_ok, errors, err  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CIVIL = os.path.join(ROOT, "data", "chaos_civil")
ROLES = ["農民", "職人", "商人", "町人", "漁民"]
PLACES = LANDMARKS + ["town"]


def as_list(v):
    return v if isinstance(v, list) else [v]


def load_civil(eras, byid):
    excl = json.load(open(os.path.join(CIVIL, "exclusions.json"), encoding="utf-8"))
    ex_lm = {(e["era"], e["at"]) for e in excl.get("landmarks", [])}
    ex_era = {e["era"] for e in excl.get("eras", [])}
    for e in excl.get("missions", []):
        if e.get("q") not in byid: err(f"exclusions: unknown q {e.get('q')}")
        if not e.get("basis"): err(f"exclusions: {e.get('q')} needs basis")
        if "method" in e:
            ms = [m.get("method") for m in byid[e["q"]].get("missions", []) if "choice" not in e or m.get("choice") == e["choice"]]
            if e["method"] not in ms: err(f"exclusions: {e['q']} has no method {e['method']}")
    for e in excl.get("landmarks", []):
        if e.get("at") not in LANDMARKS or e.get("era") not in eras or not e.get("basis"): err(f"exclusions: bad landmark {e}")
    data, ids = {}, set()
    for era in ERA_ORDER:
        p = os.path.join(CIVIL, era + ".json")
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        ys = [q["year"] for q in eras[era]["questions"]]
        nxt = ERA_ORDER.index(era) + 1
        y_end = min(q["year"] for q in eras[ERA_ORDER[nxt]]["questions"]) if nxt < len(ERA_ORDER) else 1989
        roles = d.get("roles", {})
        for k in PLACES:
            if roles.get(k) not in ROLES: err(f"chaos_civil/{era}: roles.{k} must be one of {ROLES}")
        for r in d.get("rules", []):
            w = f"chaos_civil/{era}:{r.get('id')}"
            if not r.get("id", "").startswith("cv_") or r["id"] in ids: err(f"{w}: id must be unique and start with cv_")
            ids.add(r.get("id"))
            t = r.get("trigger", {})
            for c in as_list(t):
                if c.get("kind") != "casualty": err(f"{w}: trigger kind must be casualty")
                for k in c:
                    if k not in ("kind", "at", "role", "min"): err(f"{w}: bad trigger key {k}")
                for a in as_list(c.get("at", [])):
                    if a not in PLACES: err(f"{w}: bad at {a}")
                    if (era, a) in ex_lm: err(f"{w}: at {a} is an excluded landmark")
                for ro in as_list(c.get("role", [])):
                    if ro not in ROLES: err(f"{w}: bad role {ro}")
                if not isinstance(c.get("min"), int) or c["min"] < 1: err(f"{w}: min")
            if "force" in r: err(f"{w}: force is not allowed for civilian rules")
            eff_ok(r.get("vars", {}), w)
            for k, v in r.get("vars", {}).items():
                if k not in NUM or abs(v) > 20: err(f"{w}: vars {k}={v} (numbers only, |v|<=20)")
            y = r.get("year")
            if not isinstance(y, int) or not (min(ys) - 3000 <= y < y_end): err(f"{w}: year {y} outside the era")
            if not r.get("text") or not r.get("title"): err(f"{w}: title/text")
            rc = r.get("recover")
            if r.get("unrest"):
                if rc is not None: err(f"{w}: unrest (policy) rules do not recover")
            elif not isinstance(rc, int) or not (20 <= rc <= 150): err(f"{w}: recover (20..150 years) required for population/labour losses")
            if not re.search(r"[0-9]{2,4}年", r.get("basis", "")): err(f"{w}: basis needs a dated fact")
            if era == "showa" and isinstance(y, int) and 1937 <= y <= 1945: err(f"{w}: wartime year {y}")
        data[era] = {"roles": roles, "rules": d.get("rules", []), "excluded": {a for (e, a) in ex_lm if e == era} | (set(PLACES) if era in ex_era else set())}
    return data, excl


def feasible_sets(cd):
    """名所ごとの犠牲者数を総当たりして、起こりうる発動ルールの組（frozenset of rule id）を返す"""
    rules, roles = cd["rules"], cd["roles"]
    places = [p for p in PLACES if p not in cd["excluded"]]

    def applies(c, p):
        return ("at" not in c or p in as_list(c["at"])) and ("role" not in c or roles.get(p) in as_list(c["role"]))
    levels = []
    for p in places:
        lv = {0}
        for r in rules:
            for c in as_list(r["trigger"]):
                if applies(c, p):
                    lv.add(c["min"])
        levels.append(sorted(lv))
    out = set()
    for counts in itertools.product(*levels):
        fired = set()
        for r in rules:
            for c in as_list(r["trigger"]):
                if sum(n for p, n in zip(places, counts) if applies(c, p)) >= c["min"]:
                    fired.add(r["id"]); break
        out.add(frozenset(fired))
    return sorted(out, key=lambda s: (len(s), sorted(s)))


def main():
    verbose = "-v" in sys.argv
    jpath = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    samples = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 20000
    eras, qs, byid, legacy = load_eras()
    data, excl = load_civil(eras, byid)
    if errors:
        print("\n".join("ERROR " + e for e in errors)); sys.exit(1)
    rule_by = {r["id"]: (era, r) for era in data for r in data[era]["rules"]}
    sets = {era: feasible_sets(data[era]) for era in data}
    base = simulate(qs, legacy, {}, [])

    def mods_of(ids):
        out = []
        for i in ids:
            era, r = rule_by[i]
            out.append({"era": era, "year": r["year"], "effects": r["vars"]})
            if "recover" in r:   # chaos.gd _add_recovery と同じ：recover 年後に打ち消す
                ry = r["year"] + r["recover"]
                out.append({"era": era_of_year(eras, ry), "year": ry, "effects": {k: -v for k, v in r["vars"].items()}})
        return out
    reach = {}   # (qid, choice) -> example rule ids

    def run(ids):
        w = simulate(qs, legacy, {}, mods_of(ids))
        for q in qs:
            c = w[q["id"]]
            if c != base[q["id"]] and (q["id"], c) not in reach:
                reach[(q["id"], c)] = sorted(ids, key=lambda i: (ERA_ORDER.index(rule_by[i][0]), i))
    n_runs = 0
    for e_i, era in enumerate(ERA_ORDER):
        if era not in sets:
            continue
        earlier = [e for e in ERA_ORDER[:e_i] if e in sets]
        for s in sets[era]:
            run(s); n_runs += 1
            for e2 in earlier:
                for s2 in sets[e2]:
                    run(s | s2); n_runs += 1
            run(s.union(*[sets[e2][-1] for e2 in earlier]) if earlier else s); n_runs += 1
    rng = random.Random(7)
    for _ in range(samples):
        ids = set()
        for era in sets:
            ids |= rng.choice(sets[era])
        run(ids); n_runs += 1

    # ---------------- 報告
    print(f"data/chaos_civil: {len(rule_by)} rules in {len(data)} eras; feasible rule-sets per era: "
          + ", ".join(f"{e}={len(sets[e])}" for e in sets) + f"; simulations: {n_runs}")
    print("excluded landmarks: " + ", ".join(f"{e['era']}/{e['at']}({e.get('name', '')})" for e in excl.get("landmarks", [])))
    print("excluded missions:  " + ", ".join(f"{e['q']}" + (f" c{e['choice']}" if "choice" in e else "") + (f" {e['method']}" if "method" in e else "") for e in excl.get("missions", [])))
    total = 0
    rows = []
    for q in qs:
        for c in range(4):
            if c == q["real"]:
                continue
            total += 1
            ex = reach.get((q["id"], c))
            rows.append({"q": q["id"], "year": q["year"], "topic": q["topic"], "choice": c, "reachable": ex is not None, "example": ex or []})
    n = sum(1 for r in rows if r["reachable"])
    print(f"\nreachable via civilian casualties only: {n} / {total} question x wrong-choice pairs\n")
    for r in rows:
        if r["reachable"]:
            print(f"  REACH  {r['q']:<24} c{r['choice']}  {r['topic'][:18]:<18}  <- " + " + ".join(r["example"]))
    if verbose:
        print("\nnot reachable:")
        for r in rows:
            if not r["reachable"]:
                print(f"  -      {r['q']:<24} c{r['choice']}  {r['topic'][:18]}")
    else:
        print(f"\n(not reachable: {total - n} pairs; -v to list them)")
    if jpath:
        json.dump({"rules": len(rule_by), "reachable": n, "total": total, "rows": rows,
                   "note": "python model (tools/validate_chaos.simulate); war/standing two-stage feedback not modelled"},
                  open(jpath, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()

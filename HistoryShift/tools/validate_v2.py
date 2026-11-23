#!/usr/bin/env python3
"""歴史シミュレーション v2 の検証（tools/SCHEMA_V2.md）。
python3 tools/validate_v2.py [--sim N]

- 形式チェック（effects / resolve / 手段 / aftermath_rules / modern.json）
- 基準状態（全パラメータ0）で全問題が史実どおりに解決されること
- ランダムな改変で「波及」が十分起きること、年代順に直せば必ず満点になること
"""
import glob, json, os, random, re, sys

NUM = ["centralization", "warrior", "court", "religion", "commerce", "open_asia", "open_west", "tech",
       "education", "commoners", "militarism", "democracy", "economy", "unity"]
CAT = ["capital", "ruler", "edu_center", "war"]
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
errors, warns = [], []


def err(m): errors.append(m)


def cond_ok(c, where):
    if not isinstance(c, dict) or not c:
        err(f"{where}: empty/invalid if"); return
    for k, v in c.items():
        if k in NUM:
            if not re.fullmatch(r"(>=|<=|>|<)-?\d+", str(v)): err(f"{where}: bad numeric cond {k}:{v}")
        elif k in CAT:
            if not re.fullmatch(r"(==|!=).*", str(v)): err(f"{where}: bad cat cond {k}:{v}")
        else:
            err(f"{where}: unknown var {k}")


def eff_ok(e, where):
    if not isinstance(e, dict): err(f"{where}: effects not dict"); return
    for k, v in e.items():
        if k == "set":
            for ck in v:
                if ck not in CAT: err(f"{where}: bad set key {ck}")
        elif k in NUM:
            if not isinstance(v, (int, float)) or abs(v) > 60: err(f"{where}: bad delta {k}:{v}")
        else:
            err(f"{where}: unknown effect key {k}")


def match(c, st):
    for k, v in c.items():
        v = str(v)
        if k in NUM:
            op = re.match(r"(>=|<=|>|<)", v).group(1); n = float(v[len(op):]); x = st[k]
            if not {">=": x >= n, "<=": x <= n, ">": x > n, "<": x < n}[op]: return False
        else:
            cur = st.get(k, "")
            if v.startswith("=="):
                if cur != v[2:]: return False
            elif cur == v[2:]: return False
    return True


def apply(st, e):
    for k, v in (e or {}).items():
        if k == "set":
            st.update(v)
        else:
            st[k] = max(-100, min(100, st[k] + v))


def simulate(qs, interventions):
    st = {k: 0 for k in NUM}; st.update({k: "" for k in CAT})
    world = {}
    for q in qs:
        iv = interventions.get(q["id"])
        if iv is not None:
            fact, m = iv
        else:
            fact, m = q["real"], None
            for r in q.get("resolve", []):
                if match(r["if"], st):
                    fact = r["choice"]; break
        world[q["id"]] = fact
        apply(st, q["effects"][fact] if q.get("effects") else {})
        if m is not None:
            apply(st, m.get("effects", {}))
    return world, st


def _text_ok(t):
    """文章は文字列、または言い換えの候補（空でない文字列の配列。HistoryState.pick_variant が世界ごとに選ぶ）。"""
    if isinstance(t, str): return bool(t.strip())
    return isinstance(t, list) and len(t) > 0 and all(isinstance(x, str) and x.strip() for x in t)


def main():
    sims = 300
    if "--sim" in sys.argv: sims = int(sys.argv[sys.argv.index("--sim") + 1])
    qs, eras = [], []
    for f in sorted(glob.glob(os.path.join(BASE, "*.json"))):
        name = os.path.basename(f)
        d = json.load(open(f, encoding="utf-8"))
        if name == "modern.json":
            rules = d.get("ending_rules", [])
            if len(rules) < 20: err(f"modern.json: need >=20 ending_rules, got {len(rules)}")
            for i, r in enumerate(rules):
                cond_ok(r.get("if"), f"modern.ending_rules[{i}]")
                if not r.get("topic") or not r.get("text"): err(f"modern.ending_rules[{i}]: topic/text")
                if not _text_ok(r.get("text")): err(f"modern.ending_rules[{i}]: text must be a string or a list of strings")
            if not d.get("baseline"): err("modern.json: baseline missing")
            for k, t in d.get("baseline", {}).items():
                if not _text_ok(t): err(f"modern.baseline[{k}]: text must be a string or a list of strings")
            continue
        if name.startswith("rules_"): continue
        eras.append(d)
        ar = d.get("aftermath_rules", [])
        if not 8 <= len(ar) <= 20: err(f"{name}: aftermath_rules 8-20, got {len(ar)}")
        for i, r in enumerate(ar):
            cond_ok(r.get("if"), f"{name}.aftermath_rules[{i}]")
            if not r.get("text"): err(f"{name}.aftermath_rules[{i}]: text")
        if not d.get("baseline_text"): err(f"{name}: baseline_text missing")
        for q in d["questions"]:
            q["year"] = int(q["year"]); qs.append(q)
            qid = q["id"]
            ef = q.get("effects")
            if not isinstance(ef, list) or len(ef) != 4: err(f"{qid}: effects must be list of 4"); continue
            for i, e in enumerate(ef): eff_ok(e, f"{qid}.effects[{i}]")
            if ef[q["real"]] != {}: err(f"{qid}: effects[real] must be {{}}")
            rs = q.get("resolve", [])
            if not 2 <= len(rs) <= 5: err(f"{qid}: resolve 2-5, got {len(rs)}")
            for i, r in enumerate(rs):
                cond_ok(r.get("if"), f"{qid}.resolve[{i}]")
                if r.get("choice") not in (0, 1, 2, 3) or r.get("choice") == q["real"]: err(f"{qid}.resolve[{i}]: bad choice")
                if not r.get("note"): err(f"{qid}.resolve[{i}]: note")
            by = {}
            for m in q.get("missions", []):
                by.setdefault(m["choice"], []).append(m)
                if not m.get("method"): err(f"{qid} c{m['choice']}: method missing")
                eff_ok(m.get("effects", {}), f"{qid} c{m['choice']} {m.get('method')}")
            for c in range(4):
                if c == q["real"]: continue
                n = len(by.get(c, []))
                if not 2 <= n <= 3: err(f"{qid} c{c}: need 2-3 methods, got {n}")
                ms = by.get(c, [])
                if len({json.dumps(m.get('effects', {}), sort_keys=True) for m in ms}) < len(ms): err(f"{qid} c{c}: methods need distinct effects")
    qs.sort(key=lambda q: q["year"])
    if errors:
        for e in errors[:200]: print("ERROR", e)
        print(f"{len(errors)} errors"); sys.exit(1)
    # 基準状態
    world, _ = simulate(qs, {})
    bad = [q["id"] for q in qs if world[q["id"]] != q["real"]]
    if bad: print("ERROR baseline does not reproduce real history:", bad); sys.exit(1)
    # ランダム改変による波及
    rng = random.Random(1)
    ripple_total, ripple_max, resolver_hits = 0, 0, {}
    for _ in range(sims):
        iv = {}
        for q in rng.sample(qs, rng.randint(1, 4)):
            ms = [m for m in q["missions"]]
            m = rng.choice(ms)
            iv[q["id"]] = (m["choice"], m)
        w, st = simulate(qs, iv)
        changed = [q for q in qs if q["id"] not in iv and w[q["id"]] != q["real"]]
        ripple_total += len(changed); ripple_max = max(ripple_max, len(changed))
        for q in changed: resolver_hits[q["id"]] = resolver_hits.get(q["id"], 0) + 1
        # 年代順に直せば満点
        answers = {q["id"]: rng.randint(0, 3) for q in qs}
        fix = {}
        for q in qs:
            w2, _ = simulate(qs, fix)
            if w2[q["id"]] != answers[q["id"]]:
                cand = [m for m in q["missions"] if m["choice"] == answers[q["id"]]] or [{"effects": {}}]
                fix[q["id"]] = (answers[q["id"]], cand[0])
        w3, _ = simulate(qs, fix)
        if any(w3[q["id"]] != answers[q["id"]] for q in qs): print("ERROR chronological fixing failed"); sys.exit(1)
    never = [q["id"] for q in qs[4:] if q["id"] not in resolver_hits]
    nm = sum(len(q["missions"]) for q in qs)
    print(f"{len(eras)} eras, {len(qs)} questions, {nm} missions, avg ripple per random alteration set {ripple_total / sims:.2f} (max {ripple_max})")
    print(f"questions never changed by ripple: {len(never)} {never[:12]}")
    print("OK")


if __name__ == "__main__":
    main()

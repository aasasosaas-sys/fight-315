#!/usr/bin/env python3
"""自由探索の「歴史の揺らぎ」ルール（data/chaos/<era>.json）の検証。
python3 tools/validate_chaos.py [-v]

- 形式チェック（trigger / force / vars / year / figures）
- 人物名はその時代のミッションに登場する NPC 名であること
- 強制する選択肢は本来の史実と異なり、問題はその時代以降のものであること
- 各ルールを単独で適用したときの波及（-v で一覧表示）
- すべての揺らぎが起きた世界でも、年代順に直せば必ず満点になること
"""
import glob, json, os, random, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_v2 import NUM, CAT, eff_ok, match, apply, errors, err  # noqa: E402

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
ERA_ORDER = ["jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"]
LANDMARKS = ["capital", "village", "temple", "port", "castle", "battlefield", "mountain"]
KINDS = ["destroy", "sink", "fire", "bridge", "kill"]


def load_eras():
    eras, qs, legacy = {}, [], []
    for f in sorted(glob.glob(os.path.join(BASE, "*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        if "questions" not in d:
            continue
        eras[d["eraId"]] = d
        legacy += d.get("rules", [])
        for q in d["questions"]:
            q["year"] = int(q["year"]); q["_era"] = d["eraId"]; qs.append(q)
    qs.sort(key=lambda q: q["year"])
    byid = {q["id"]: q for q in qs}
    legacy = [r for r in legacy if r["ifQ"] in byid and r["thenQ"] in byid and byid[r["ifQ"]]["year"] < byid[r["thenQ"]]["year"]]
    return eras, qs, byid, legacy


def simulate(qs, legacy, iv, mods):
    """history_state.gd の simulate と同じ順序（前の時代の揺らぎ → 時代の区切り → 同じ時代で year <= 問題の年）。"""
    st = {k: 0 for k in NUM}; st.update({k: "" for k in CAT})
    pend = sorted(mods, key=lambda m: (ERA_ORDER.index(m["era"]), m["year"]))
    mi, world = 0, {}
    for q in qs:
        qe = ERA_ORDER.index(q["_era"])
        while mi < len(pend) and ERA_ORDER.index(pend[mi]["era"]) < qe:
            apply(st, pend[mi]["effects"]); mi += 1
        while mi < len(pend) and ERA_ORDER.index(pend[mi]["era"]) == qe and pend[mi]["year"] <= q["year"]:
            apply(st, pend[mi]["effects"]); mi += 1
        if q["id"] in iv:
            fact = iv[q["id"]]
        else:
            fact = q["real"]; done = False
            for r in legacy:
                if r["thenQ"] == q["id"] and world.get(r["ifQ"]) == int(r["ifChoice"]):
                    fact = int(r["thenChoice"]); done = True; break
            if not done:
                for r in q.get("resolve", []):
                    if match(r["if"], st):
                        fact = r["choice"]; break
        world[q["id"]] = fact
        apply(st, q["effects"][fact])
    return world


def trig_ok(t, where, names):
    ts = t if isinstance(t, list) else [t]
    if not ts: err(f"{where}: empty trigger")
    for i, x in enumerate(ts):
        w = f"{where}.trigger[{i}]"
        if not isinstance(x, dict): err(f"{w}: not dict"); continue
        if x.get("kind") not in KINDS: err(f"{w}: bad kind {x.get('kind')}")
        for k in x:
            if k not in ("kind", "id", "type", "at", "min", "value"): err(f"{w}: unknown key {k}")
        if "value" in x and (x.get("kind") != "destroy" or not isinstance(x["value"], int) or x["value"] < 1): err(f"{w}: value is for destroy only (int)")
        if "type" in x and not isinstance(x["type"], (str, list)): err(f"{w}: bad type")
        if "at" in x and x["at"] not in LANDMARKS: err(f"{w}: bad landmark {x['at']}")
        if "min" in x and (not isinstance(x["min"], int) or x["min"] < 1): err(f"{w}: bad min")
        if x.get("kind") == "kill" and "id" in x:
            for n in (x["id"] if isinstance(x["id"], list) else [x["id"]]):
                if n not in names: err(f"{w}: kill target {n} is not in this era's figures")
        if x.get("kind") == "kill" and "id" not in x and x.get("type") != "soldier": err(f"{w}: kill needs id or type soldier")
        if x.get("kind") in ("destroy", "bridge", "sink") and isinstance(x.get("id"), str) and x["id"] not in LANDMARKS + ["town", "river", "airfield"]:
            err(f"{w}: {x['kind']} id should be a landmark key")
        if x.get("kind") == "destroy" and "id" in x and "value" not in x and "type" not in x:
            err(f"{w}: destroy at a landmark needs value or type (each building emits its own destroy)")


def main():
    verbose = "-v" in sys.argv
    eras, qs, byid, legacy = load_eras()
    files = sorted(glob.glob(os.path.join(BASE, "chaos", "*.json")))
    all_rules, ids = [], set()
    for f in files:
        name = os.path.basename(f)
        d = json.load(open(f, encoding="utf-8"))
        era = d.get("eraId")
        if era not in eras: err(f"{name}: unknown eraId {era}"); continue
        if name != era + ".json": err(f"{name}: file name must be <eraId>.json")
        npcs = set()
        for q in eras[era]["questions"]:
            for m in q.get("missions", []):
                for s in m["steps"]:
                    if s.get("npc"): npcs.add(s["npc"])
        figs = d.get("figures", [])
        if not 3 <= len(figs) <= 8: err(f"{name}: figures 3-8, got {len(figs)}")
        names = set()
        for i, fg in enumerate(figs):
            w = f"{name}.figures[{i}]"
            if fg.get("name") not in npcs: err(f"{w}: {fg.get('name')} is not an NPC of this era's missions")
            if fg.get("at") not in LANDMARKS: err(f"{w}: bad at")
            if not isinstance(fg.get("guards", 0), int) or not 0 <= fg.get("guards", 0) <= 6: err(f"{w}: guards 0-6")
            if not fg.get("lines"): err(f"{w}: lines")
            names.add(fg.get("name"))
        rules = d.get("rules", [])
        if not 6 <= len(rules) <= 14: err(f"{name}: rules 6-14, got {len(rules)}")
        era_years = [q["year"] for q in eras[era]["questions"]]
        for i, r in enumerate(rules):
            w = f"{name}.rules[{i}]({r.get('id')})"
            if not r.get("id") or r["id"] in ids: err(f"{w}: missing/duplicate id")
            ids.add(r.get("id"))
            for k in ("title", "text"):
                if not r.get(k): err(f"{w}: {k} missing")
            if len(r.get("text", "")) < 30: err(f"{w}: text too short")
            trig_ok(r.get("trigger"), w, names)
            if "force" not in r and "vars" not in r: err(f"{w}: needs force or vars")
            fs = r.get("force", [])
            for fo in (fs if isinstance(fs, list) else [fs]):
                q = byid.get(fo.get("q"))
                if q is None: err(f"{w}: force q {fo.get('q')} unknown"); continue
                if ERA_ORDER.index(q["_era"]) < ERA_ORDER.index(era): err(f"{w}: force on an earlier era")
                if fo.get("choice") not in (0, 1, 2, 3) or fo.get("choice") == q["real"]: err(f"{w}: force choice must differ from real")
            if "vars" in r:
                eff_ok(r["vars"], w + ".vars")
                y = r.get("year")
                if not isinstance(y, int): err(f"{w}: vars needs int year")
                elif not (min(era_years) - 3500 <= y <= max(era_years) + 60): err(f"{w}: year {y} outside era")
            r["_era"] = era
            all_rules.append(r)
    if errors:
        for e in errors[:200]: print("ERROR", e)
        print(f"{len(errors)} errors"); sys.exit(1)

    def mods_iv(rs):
        iv, mods = {}, []
        for r in rs:
            fs = r.get("force", [])
            for fo in (fs if isinstance(fs, list) else [fs]):
                iv[fo["q"]] = fo["choice"]
            if "vars" in r:
                mods.append({"era": r["_era"], "year": r["year"], "effects": r["vars"]})
        return iv, mods

    base = simulate(qs, legacy, {}, [])
    if any(base[q["id"]] != q["real"] for q in qs): print("ERROR baseline is not real history"); sys.exit(1)
    rippling, per_era = 0, {}
    for r in all_rules:
        iv, mods = mods_iv([r])
        w = simulate(qs, legacy, iv, mods)
        ch = [q for q in qs if w[q["id"]] != q["real"]]
        per_era.setdefault(r["_era"], [0, 0])
        per_era[r["_era"]][0] += 1
        if ch:
            rippling += 1; per_era[r["_era"]][1] += 1
        if verbose:
            print(f"  {r['id']:28s} {r['title']}: " + (", ".join(f"{q['id']}→{w[q['id']]}" for q in ch) or "（設問は不変・その後の歴史のみ）"))
    # すべての揺らぎ＋ランダム答案でも、年代順に直せば満点
    rng = random.Random(3)
    for trial in range(200):
        sub = rng.sample(all_rules, rng.randint(1, 12))
        iv, mods = mods_iv(sub)
        answers = {q["id"]: rng.randint(0, 3) for q in qs}
        fix = dict(iv)
        for q in qs:
            w2 = simulate(qs, legacy, fix, mods)
            if w2[q["id"]] != answers[q["id"]]:
                fix[q["id"]] = answers[q["id"]]
        w3 = simulate(qs, legacy, fix, mods)
        if any(w3[q["id"]] != answers[q["id"]] for q in qs): print("ERROR chronological repair failed"); sys.exit(1)
    print(f"{len(files)} chaos files, {len(all_rules)} rules, {rippling} change exam facts; per era " +
          ", ".join(f"{e}={v[0]}({v[1]})" for e, v in per_era.items()))
    print("OK")


if __name__ == "__main__":
    main()

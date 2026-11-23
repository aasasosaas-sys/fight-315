#!/usr/bin/env python3
"""自由な歴史改変（別解）のデータ検証。tools/SCHEMA_V2.md「data/chaos・data/actors」を参照。
python3 tools/validate_chaos.py [-v] [--era <eraId>] [--density N] [--gaps]

  data/actors/<era>.json  人物（actors）と合戦（battles）
  data/chaos/<era>.json   名所に立つ人物（figures）と手作りの別解ルール（rules）

- 形式チェック（trigger の kind・キー・論点・渡す物・名所・予定・合戦の側、force / vars / year、人物の項目）
- 人物名は data/actors の人物か、その時代のミッションの npc
- 強制する選択肢は本来の史実と異なり、問題はその時代以降のもの
- 別解の数：各ルール・各人物の効果を単独で適用したときに「どの問題がどの選択肢になるか」を数える
  （直接の force も、パラメータ変化による波及も1つの道として数える）。どの問題×選択肢にも「未来を語る」の道が1つある。
  --density N  手作りの道（未来を語る以外）が N 未満の 問題×選択肢 があればエラー（既定 0＝報告のみ）
  --gaps       手作りの道が少ない 問題×選択肢 を一覧する
- すべての揺らぎが起きた世界でも、年代順に直せば必ず満点になること
"""
import glob, json, os, random, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_v2 import NUM, CAT, eff_ok, match, apply, errors, err  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BASE = os.path.join(ROOT, "data")
ERA_ORDER = ["jomon_kofun", "asuka_nara", "heian", "kamakura_muromachi", "sengoku", "edo", "meiji_taisho", "showa"]
LANDMARKS = ["capital", "village", "temple", "port", "castle", "battlefield", "mountain"]
PLACE_IDS = LANDMARKS + ["town", "river"]
WORLD_KINDS = ["destroy", "sink", "fire", "bridge", "kill"]
VERB_KINDS = ["protect", "escort", "persuade", "give", "steal", "forge", "delay", "battle"]
KINDS = WORLD_KINDS + VERB_KINDS
TRIG_KEYS = ["kind", "id", "type", "at", "min", "value", "arg", "item", "to", "event", "side", "cause"]
TAGS = ["ruler", "official", "warrior", "rebel", "diplomat", "scholar", "religious", "artist", "merchant", "reformer",
        "sacred", "woman", "foreigner", "commoner"]
TRAITS = ["open", "reform", "war", "loyal", "faith"]
DEATHS = ["natural", "illness", "assassinated", "killed", "suicide", "executed", "accident", "poisoned", "unknown"]


def gd_keys(const):
    """scripts/core/actors.gd の定数辞書のキー（論点・渡す物・原因）を読む"""
    src = open(os.path.join(ROOT, "scripts", "core", "actors.gd"), encoding="utf-8").read()
    m = re.search(r"const " + const + r" := \{(.*?)\n\}", src, re.S)
    return re.findall(r'^\t"([^"]+)":', m.group(1), re.M) if m else []


ARGS, ITEMS, CAUSES = gd_keys("ARGS"), gd_keys("ITEMS"), gd_keys("CAUSE_TEXT")


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


def era_of_year(eras, y):
    best = ERA_ORDER[0]
    for e in ERA_ORDER:
        ys = [q["year"] for q in eras[e]["questions"]]
        if ys and y >= min(ys):
            best = e
    return best


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


def force_ok(fo, w, byid, era):
    q = byid.get(fo.get("q") if isinstance(fo, dict) else None)
    if q is None: err(f"{w}: force q {fo} unknown"); return
    if era and ERA_ORDER.index(q["_era"]) < ERA_ORDER.index(era): err(f"{w}: force on an earlier era")
    if fo.get("choice") not in (0, 1, 2, 3) or fo.get("choice") == q["real"]: err(f"{w}: force choice must differ from real")


def main():
    verbose = "-v" in sys.argv
    only = sys.argv[sys.argv.index("--era") + 1] if "--era" in sys.argv else None
    density = int(sys.argv[sys.argv.index("--density") + 1]) if "--density" in sys.argv else 0
    if not ARGS or not ITEMS: err("could not read ARGS/ITEMS from scripts/core/actors.gd")
    eras, qs, byid, legacy = load_eras()

    # ---------------- 人物・合戦
    actors, alias, battles = {}, {}, []
    for f in sorted(glob.glob(os.path.join(BASE, "actors", "*.json"))):
        name = os.path.basename(f)
        d = json.load(open(f, encoding="utf-8"))
        era = d.get("eraId")
        if era not in eras: err(f"actors/{name}: unknown eraId {era}"); continue
        if name != era + ".json": err(f"actors/{name}: file name must be <eraId>.json")
        for i, a in enumerate(d.get("actors", [])):
            w = f"actors/{name}[{i}]({a.get('name')})"
            n = a.get("name")
            if not n or n in actors: err(f"{w}: missing/duplicate name")
            a.setdefault("era", era); a["_file_era"] = era
            if a["era"] not in eras: err(f"{w}: bad era")
            actors[n] = a
            for al in a.get("aka", []): alias[al] = n
            for t in a.get("tags", []):
                if t not in TAGS: err(f"{w}: bad tag {t}")
            if not a.get("tags"): err(f"{w}: tags missing")
            for k, v in a.get("traits", {}).items():
                if k not in TRAITS or not isinstance(v, int) or abs(v) > 2: err(f"{w}: bad trait {k}={v}")
            if a.get("death") not in DEATHS: err(f"{w}: bad death {a.get('death')}")
            if not isinstance(a.get("active"), int): err(f"{w}: active year missing")
            for k in ("born", "died"):
                if a.get(k) is not None and not isinstance(a[k], int): err(f"{w}: {k} must be int or null")
            if a.get("spawn") and a["spawn"] not in LANDMARKS: err(f"{w}: bad spawn")
            for j, c in enumerate(a.get("contrib", [])):
                cw = f"{w}.contrib[{j}]"
                if "choice" in c: force_ok({"q": c.get("q"), "choice": c["choice"]}, cw, byid, None)
                if "vars" in c:
                    eff_ok(c["vars"], cw)
                    if not isinstance(c.get("year"), int): err(f"{cw}: vars needs year")
                if "choice" not in c and "vars" not in c: err(f"{cw}: needs choice or vars")
                if not c.get("note"): err(f"{cw}: note")
            for key in ("saved",):
                sv = a.get(key)
                if sv:
                    if "force" in sv: force_ok(sv["force"], f"{w}.saved", byid, None)
                    if "vars" in sv: eff_ok(sv["vars"], f"{w}.saved")
                    if not sv.get("text") or not isinstance(sv.get("year"), int): err(f"{w}.saved: text/year")
                    if a.get("death") not in ("assassinated", "killed", "suicide", "executed", "accident", "poisoned", "illness"):
                        err(f"{w}.saved: death {a.get('death')} cannot be prevented")
            doc = a.get("doc")
            if doc:
                force_ok({"q": doc.get("q"), "choice": doc.get("choice")}, f"{w}.doc", byid, None)
                if not doc.get("name") or not doc.get("text"): err(f"{w}.doc: name/text")
            for arg, sp in a.get("persuade", {}).items():
                if arg not in ARGS: err(f"{w}.persuade: unknown arg {arg}")
                if "force" in sp: force_ok(sp["force"], f"{w}.persuade", byid, None)
                if "vars" in sp: eff_ok(sp["vars"], f"{w}.persuade")
                if not sp.get("text"): err(f"{w}.persuade: text")
            for it, sp in a.get("give", {}).items():
                if it not in ITEMS: err(f"{w}.give: unknown item {it}")
                if "force" in sp: force_ok(sp["force"], f"{w}.give", byid, None)
                if "vars" in sp: eff_ok(sp["vars"], f"{w}.give")
            for j, sc in enumerate(a.get("schedule", [])):
                sw = f"{w}.schedule[{j}]"
                if sc.get("at") not in LANDMARKS or not sc.get("event") or not sc.get("text") or not isinstance(sc.get("year"), int): err(f"{sw}: event/at/year/text")
                ms = sc.get("missed", {})
                if "force" in ms: force_ok(ms["force"], sw, byid, None)
                if "vars" in ms: eff_ok(ms["vars"], sw)
                if not ms: err(f"{sw}: missed effect")
            for qid in a.get("q", []):
                if qid not in byid: err(f"{w}: q {qid} unknown")
        for i, b in enumerate(d.get("battles", [])):
            w = f"actors/{name}.battles[{i}]"
            b.setdefault("era", era)
            battles.append(b)
            if b.get("at") not in LANDMARKS or not b.get("id") or not isinstance(b.get("year"), int): err(f"{w}: id/at/year")
            sides = b.get("sides", [])
            if len(sides) != 2 or not any(s.get("historical") for s in sides): err(f"{w}: needs 2 sides, one historical")
            for s in sides:
                if not s.get("name") or not s.get("label"): err(f"{w}: side name/label")
                if "wins" in s:
                    if "force" in s["wins"]: force_ok(s["wins"]["force"], w, byid, era)
                    if "vars" in s["wins"]: eff_ok(s["wins"]["vars"], w)
                    if not s.get("text"): err(f"{w}: side text")

    def aname(n):
        if n in actors: return n
        if n in alias: return alias[n]
        if "（" in n and n.split("（")[0] in actors: return n.split("（")[0]
        for k in actors:
            if len(k) >= 2 and (n.endswith(" " + k) or n.endswith("　" + k)): return k
        return None

    # 問題に関わる人物（「未来を語る」の相手）
    q_actors = {q["id"]: set() for q in qs}
    for q in qs:
        for m in q.get("missions", []):
            for s in m["steps"]:
                if s.get("npc") and aname(s["npc"]): q_actors[q["id"]].add(aname(s["npc"]))
    for n, a in actors.items():
        for qid in a.get("q", []): q_actors.setdefault(qid, set()).add(n)
    for q in qs:
        if not q_actors[q["id"]]: err(f"{q['id']}: no actor can be told the future (add an actor with q: [{q['id']}])")

    # ---------------- 別解ルール
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
        if not 3 <= len(figs) <= 12: err(f"{name}: figures 3-12, got {len(figs)}")
        names = set()
        for i, fg in enumerate(figs):
            w = f"{name}.figures[{i}]"
            if fg.get("name") not in npcs and not aname(fg.get("name", "")): err(f"{w}: {fg.get('name')} is neither an actor nor an NPC of this era")
            if fg.get("at") not in LANDMARKS: err(f"{w}: bad at")
            if not isinstance(fg.get("guards", 0), int) or not 0 <= fg.get("guards", 0) <= 6: err(f"{w}: guards 0-6")
            if not fg.get("lines"): err(f"{w}: lines")
            names.add(fg.get("name")); names.add(aname(fg.get("name", "")))
        rules = d.get("rules", [])
        if len(rules) < 6: err(f"{name}: rules >= 6, got {len(rules)}")
        era_years = [q["year"] for q in eras[era]["questions"]]
        era_battles = {b["id"]: b for b in battles if b["era"] == era}
        for i, r in enumerate(rules):
            w = f"{name}.rules[{i}]({r.get('id')})"
            if not r.get("id") or r["id"] in ids: err(f"{w}: missing/duplicate id")
            ids.add(r.get("id"))
            for k in ("title", "text"):
                if not r.get(k): err(f"{w}: {k} missing")
            if len(r.get("text", "")) < 30: err(f"{w}: text too short (>=30)")
            ts = r.get("trigger") if isinstance(r.get("trigger"), list) else [r.get("trigger")]
            if not ts or ts == [None]: err(f"{w}: trigger missing")
            for j, x in enumerate(ts):
                tw = f"{w}.trigger[{j}]"
                if not isinstance(x, dict): err(f"{tw}: not dict"); continue
                k = x.get("kind")
                if k not in KINDS: err(f"{tw}: bad kind {k}")
                for key in x:
                    if key not in TRIG_KEYS: err(f"{tw}: unknown key {key}")
                if "at" in x and x["at"] not in PLACE_IDS: err(f"{tw}: bad landmark {x['at']}")
                if "min" in x and (not isinstance(x["min"], int) or x["min"] < 1): err(f"{tw}: bad min")
                if "value" in x and (k != "destroy" or not isinstance(x["value"], int) or x["value"] < 1): err(f"{tw}: value is for destroy only")
                idl = x.get("id") if isinstance(x.get("id"), list) else ([x["id"]] if "id" in x else [])
                if k == "kill":
                    for n in idl:
                        if n not in names and not aname(n): err(f"{tw}: kill target {n} is not an actor/figure")
                    if not idl and x.get("type") != "soldier" and "cause" not in x: err(f"{tw}: kill needs id or type soldier")
                if k in VERB_KINDS and k != "battle":
                    if not idl: err(f"{tw}: {k} needs actor id")
                    for n in idl:
                        if not aname(n): err(f"{tw}: {k} target {n} is not an actor")
                if k in ("destroy", "bridge", "sink"):
                    for n in idl:
                        if n not in PLACE_IDS: err(f"{tw}: {k} id should be a landmark key")
                    if k == "destroy" and idl and "value" not in x and "type" not in x:
                        err(f"{tw}: destroy at a landmark needs value or type (each building emits its own destroy)")
                for key, allowed in (("arg", ARGS), ("item", ITEMS), ("cause", CAUSES), ("to", LANDMARKS)):
                    if key in x:
                        for v in (x[key] if isinstance(x[key], list) else [x[key]]):
                            if v not in allowed: err(f"{tw}: bad {key} {v}")
                if k == "persuade" and "arg" not in x: err(f"{tw}: persuade needs arg")
                if k == "give" and "item" not in x: err(f"{tw}: give needs item")
                if k == "escort" and "to" not in x: err(f"{tw}: escort needs to")
                if k == "delay":
                    for n in idl:
                        a = actors.get(aname(n) or "", {})
                        evs = [s["event"] for s in a.get("schedule", [])]
                        if x.get("event") and x["event"] not in evs: err(f"{tw}: event {x['event']} not in {n}'s schedule")
                if k == "battle":
                    if not idl or idl[0] not in era_battles: err(f"{tw}: battle id must be one of {list(era_battles)}")
                    elif x.get("side") not in [s["name"] for s in era_battles[idl[0]]["sides"]]: err(f"{tw}: bad side")
            if "force" not in r and "vars" not in r: err(f"{w}: needs force or vars")
            fs = r.get("force", [])
            for fo in (fs if isinstance(fs, list) else [fs]):
                force_ok(fo, w, byid, era)
            if "vars" in r:
                eff_ok(r["vars"], w + ".vars")
                y = r.get("year")
                if not isinstance(y, int): err(f"{w}: vars needs int year")
                elif not (min(era_years) - 3500 <= y <= max(era_years) + 60): err(f"{w}: year {y} outside era")
            r["_era"] = era
            all_rules.append(r)
    if errors:
        for e in errors[:300]: print("ERROR", e)
        print(f"{len(errors)} errors"); sys.exit(1)

    # ---------------- 別解の数
    def effects_of(fs, vars_, year, era):
        iv, mods = {}, []
        for fo in (fs if isinstance(fs, list) else ([fs] if fs else [])):
            iv[fo["q"]] = fo["choice"]
        if vars_:
            mods.append({"era": era, "year": year, "effects": vars_})
        return iv, mods

    paths = {}   # (qid, choice) -> [説明]

    def count(label, iv, mods):
        w = simulate(qs, legacy, iv, mods)
        ch = [(q["id"], w[q["id"]]) for q in qs if w[q["id"]] != q["real"]]
        for k in ch: paths.setdefault(k, []).append(label)
        return ch

    base = simulate(qs, legacy, {}, [])
    if any(base[q["id"]] != q["real"] for q in qs): print("ERROR baseline is not real history"); sys.exit(1)
    for r in all_rules:
        ch = count("rule:" + r["id"], *effects_of(r.get("force"), r.get("vars"), r.get("year", 0), r["_era"]))
        if verbose and (not only or r["_era"] == only):
            print(f"  {r['id']:30s} {r['title']}: " + (", ".join(f"{a}→{b}" for a, b in ch) or "（設問は不変・その後の歴史のみ）"))
    for n, a in actors.items():
        e = a["era"]
        for c in a.get("contrib", []):
            fo = {"q": c["q"], "choice": c["choice"]} if "choice" in c else None
            count(f"actor:{n}:kill/escort", *effects_of(fo, c.get("vars"), c.get("year", a["active"]), e))
        sv = a.get("saved")
        if sv: count(f"actor:{n}:protect", *effects_of(sv.get("force"), sv.get("vars"), sv["year"], era_of_year(eras, sv["year"])))
        if a.get("doc"): count(f"actor:{n}:steal", *effects_of({"q": a["doc"]["q"], "choice": a["doc"]["choice"]}, None, 0, e))
        for arg, sp in a.get("persuade", {}).items():
            count(f"actor:{n}:persuade:{arg}", *effects_of(sp.get("force"), sp.get("vars"), sp.get("year", a["active"]), e))
        for it, sp in a.get("give", {}).items():
            count(f"actor:{n}:give:{it}", *effects_of(sp.get("force"), sp.get("vars"), sp.get("year", a["active"]), e))
        for sc in a.get("schedule", []):
            ms = sc["missed"]
            count(f"actor:{n}:delay:{sc['event']}", *effects_of(ms.get("force"), ms.get("vars"), sc["year"], e))
    for b in battles:
        for s in b["sides"]:
            if "wins" in s:
                count(f"battle:{b['id']}:{s['name']}", *effects_of(s["wins"].get("force"), s["wins"].get("vars"), b["year"], b["era"]))
    # 年代順に直せば満点（すべての別解ルールの一部が起きた世界）
    rng = random.Random(3)
    for trial in range(150):
        sub = rng.sample(all_rules, min(len(all_rules), rng.randint(1, 12)))
        iv, mods = {}, []
        for r in sub:
            i2, m2 = effects_of(r.get("force"), r.get("vars"), r.get("year", 0), r["_era"])
            iv.update(i2); mods += m2
        answers = {q["id"]: rng.randint(0, 3) for q in qs}
        fix = dict(iv)
        for q in qs:
            if simulate(qs, legacy, fix, mods)[q["id"]] != answers[q["id"]]:
                fix[q["id"]] = answers[q["id"]]
        w3 = simulate(qs, legacy, fix, mods)
        if any(w3[q["id"]] != answers[q["id"]] for q in qs): print("ERROR chronological repair failed"); sys.exit(1)
    # 報告
    pairs = [(q["id"], c) for q in qs for c in range(4) if c != q["real"]]
    if only: pairs = [p for p in pairs if byid[p[0]]["_era"] == only]
    hand = {p: len(set(paths.get(p, []))) for p in pairs}
    low = [p for p in pairs if hand[p] < max(density, 1)]
    total_paths = sum(hand.values())
    print(f"{len(files)} chaos files, {len(all_rules)} rules, {len(actors)} actors, {len(battles)} battles")
    print(f"question×choice pairs (non-real) {len(pairs)}: hand-made paths total {total_paths}, "
          f"min {min(hand.values()) if hand else 0}, pairs with 0 hand-made paths {sum(1 for p in pairs if hand[p] == 0)} "
          f"(each pair also has the generic 「未来を語る」 path)")
    per_era = {}
    for p in pairs:
        e = byid[p[0]]["_era"]; per_era.setdefault(e, [0, 0]); per_era[e][0] += hand[p]; per_era[e][1] += 1
    print("per era (paths/pairs): " + ", ".join(f"{e}={v[0]}/{v[1]}" for e, v in per_era.items()))
    if "--gaps" in sys.argv:
        for p in sorted(pairs, key=lambda p: (hand[p], p)):
            if hand[p] < max(density, 3):
                q = byid[p[0]]
                print(f"  GAP {p[0]} choice {p[1]} ({q['topic']}): {hand[p]} paths  {sorted(set(paths.get(p, [])))[:4]}")
    if density and low:
        print(f"ERROR {len(low)} pairs below density {density}"); sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()

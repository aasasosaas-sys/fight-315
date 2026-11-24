import math, random
from mathutils import Vector
from hairlib import *

D = math.radians


def taper(n, w0, wmax, p_root=0.15, tip_frac=0.55, tip_pow=1.0):
    """width profile: rises from w0 at root to wmax, then tapers to a point over the last tip_frac"""
    out = []
    for k in range(n):
        s = k / (n - 1)
        rise = smoothstep(0, p_root, s) if p_root > 0 else 1
        fall = min(1.0, (1 - s) / tip_frac) ** tip_pow
        # slight belly before the taper
        fall = fall * (1.0 + 0.12 * math.sin(math.pi * min(1.0, (1 - s) / tip_frac)))
        out.append((w0 + (wmax - w0) * rise) * fall)
    return out


def male_hairline():
    return interp_table([(0, 24), (35, 21), (60, 8), (75, -6), (88, -12), (100, -12),
                         (115, -22), (140, -40), (165, -56), (180, -62)])


# ---------------------------------------------------------------------------
def arc_clump(b, head, d0, d1, n=18, h0=0.007, h1=0.012, lift=0.0, w=0.04, t=0.011,
              w_root=0.7, tip_pow=1.0, tip_frac=0.55, uvoff=None, mat="hair", flat=0.45, extra=None, tw=None):
    """clump lying on the scalp from direction d0 to d1; lift: extra height growing at the tip."""
    hf = lambda s: h0 + (h1 - h0) * s + lift * s ** 3
    pts = arc_path(head, d0, d1, n, hf)
    if extra:
        pts = extra(pts)
    widths = taper(n, w * w_root, w, 0.2, tip_frac, tip_pow)
    if tw:
        widths = [wi * tw(k / (n - 1)) for k, wi in enumerate(widths)]
    thick = [t * (1 - 0.55 * k / (n - 1)) for k in range(n)]
    sweep(b, head, mat, pts, widths, thick, flat=flat, uvoff=random.random() if uvoff is None else uvoff)
    return pts


def zangiri(b, head):
    """Meiji 散切り: short, slightly messy side-parted anime cut."""
    lo = male_hairline()
    cap(b, head, lo, lambda th: math.pi / 2,
        lambda th, v: 0.005 + 0.010 * smoothstep(0, 0.4, v))
    whorl = head.dir(math.pi * 0.92, D(60))
    # --- back & sides: clumps from whorl down to the nape / over the ears
    tips = interp_table([(60, -12), (75, -24), (90, -22), (110, -24), (140, -44), (180, -58)])
    n_cl = 30
    for i in range(n_cl):
        th = D(62) + (D(236) * (i + random.uniform(-0.3, 0.3)) / (n_cl - 1))
        tph = tips(th) + D(random.uniform(-4, 4))
        dt = head.dir(th, tph)
        d0 = slerp(whorl, dt, random.uniform(0.0, 0.25))
        arc_clump(b, head, d0, dt, h0=0.012, h1=0.009, lift=0.006,
                  w=random.uniform(0.035, 0.05), t=0.012)
    # --- top / bangs: from a part line (left side) sweeping across the forehead
    part_th = D(28)
    bang_tips = [(-62, -6), (-48, 2), (-36, 6), (-22, 3), (-10, 9), (2, 5), (14, 10), (26, 7), (38, 14), (52, 4), (64, -8)]
    for k, (tth, tph) in enumerate(bang_tips):
        tth += random.uniform(-3, 3); tph += random.uniform(-3, 3)
        dt = head.dir(D(tth), D(tph))
        rph = D(random.uniform(55, 80))
        rth = part_th + D(random.uniform(-8, 8)) if tth < 30 else part_th + D(random.uniform(10, 30))
        d0 = head.dir(rth, rph) if tth < 30 else head.dir(D(170), D(70))
        arc_clump(b, head, d0, dt, n=20, h0=0.016, h1=0.012, lift=0.004,
                  w=random.uniform(0.048, 0.066), t=0.013, tip_frac=0.5)
    # crown volume clumps (cover the part / whorl transition)
    for k in range(8):
        th = D(-150 + k * 40 + random.uniform(-10, 10))
        dt = head.dir(th, D(random.uniform(15, 30)))
        arc_clump(b, head, slerp(whorl, dt, 0.05), dt, h0=0.018, h1=0.016, lift=0.002,
                  w=0.06, t=0.014)


def path_clump(b, head, pts, w, t, n=None, w_root=1.0, tip_frac=0.5, tip_pow=1.0, p_root=0.15,
               mat="hair", flat=0.45, sharp=0.75, tip=True, uvoff=None, tw=None, outs=None, K=10):
    """sweep a clump along given 3D points (resampled smoothly)."""
    if n is None:
        n = max(8, min(40, int(sum((pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)) / 0.008) + 2))
    P = resample(pts, n)
    widths = taper(n, w * w_root, w, p_root, tip_frac, tip_pow)
    if tw:
        widths = [wi * tw(k / (n - 1)) for k, wi in enumerate(widths)]
    thick = [t * (1 - 0.45 * k / (n - 1)) for k in range(n)]
    if tip == "blunt":
        # rounded blunt end: shrink the last rings a little
        widths = [w * w_root + (w - w * w_root) * smoothstep(0, p_root, k / (n - 1)) for k in range(n)]
        widths[-1] *= 0.75
        widths[-2] *= 0.93
        thick[-1] *= 0.6
    if outs is None:
        outs = [out_dir(head, p) for p in P]
    sweep(b, head, mat, P, widths, thick, outs=outs, flat=flat, sharp=sharp, tip=tip, K=K,
          uvoff=random.random() if uvoff is None else uvoff)
    return P


def tube(b, head, mat, pts, r, n=None, K=12, tip=False, uvfn=None, rt=None):
    """round tube (cords, pins)"""
    if n is None:
        n = max(4, len(pts))
    P = resample(pts, n) if len(pts) > 2 else [pts[0].lerp(pts[1], k / (n - 1)) for k in range(n)]
    rr = [r * (rt(k / (n - 1)) if rt else 1.0) for k in range(n)]
    sweep(b, head, mat, P, [2 * x for x in rr], [2 * x for x in rr], K=K, round_xs=True, tip=tip,
          uvfn=uvfn or (lambda v: (0.5, 0.5)))


def ring(b, head, mat, center, axis, radius, r, K=8, N=24):
    """torus (cord wrapped around a knot)"""
    axis = Vector(axis).normalized()
    a1 = axis.orthogonal().normalized()
    a2 = axis.cross(a1)
    pts = [Vector(center) + (a1 * math.cos(2 * math.pi * k / N) + a2 * math.sin(2 * math.pi * k / N)) * radius
           for k in range(N + 1)]
    outs = [(p - Vector(center)) for p in pts]
    sweep(b, head, mat, pts, [2 * r] * len(pts), [2 * r] * len(pts), outs=outs, K=K, round_xs=True,
          tip=False, root_cap=False, uvfn=lambda v: (0.5, 0.5))


def sakayaki_hi():
    """upper edge (elevation) of the remaining side/back hair around a shaved pate"""
    return interp_table([(0, -40), (42, -10), (52, 20), (66, 33), (90, 42), (125, 50), (155, 56), (180, 58)])


def combed_flow(b, head, lo, hi, target, n_cl, h0, h1, bump=0.0, w=(0.03, 0.042), t=0.009,
                th_range=(-180, 180), skip=None, phi_off=0.02):
    """strands combed from the lower hairline towards a gather point (target dir), lying on the cap."""
    for i in range(n_cl):
        th = D(th_range[0] + (th_range[1] - th_range[0]) * (i + 0.5 + random.uniform(-0.25, 0.25)) / n_cl)
        l, hh = lo(th), hi(th)
        if hh - l < D(3):
            continue
        if skip and skip(th):
            continue
        # several strands stacked between lo and hi so the whole band is covered
        span = hh - l
        rows = max(1, int(span / D(22)))
        for r in range(rows):
            ph = l + phi_off + (span - 2 * phi_off) * (r / rows) * 0.6
            d0 = head.dir(th, ph)
            def hf(s, r=r):
                emerge = smoothstep(0.0, 0.12, s) if r == 0 else 1.0
                return (h0 + (h1 - h0) * s + bump * math.sin(math.pi * min(1, s * 1.4)) * (1 - 0.3 * r)) * emerge - 0.0015 * (1 - emerge)
            n = 22
            pts = arc_path(head, d0, target, n, hf)
            ww = random.uniform(*w)
            widths = taper(n, ww * 0.9, ww, 0.1, 0.35, 1.0)
            thick = [t * (0.5 + 0.5 * smoothstep(0, 0.12, k / (n - 1))) if r == 0 else t for k in range(n)]
            sweep(b, head, "hair", pts, widths, thick, uvoff=random.random())


def chonmage(b, head):
    """江戸 丁髷: shaved pate (sakayaki), side/back hair combed up to a knot, folded queue on top."""
    lo = male_hairline()
    hi = sakayaki_hi()
    # side/back hair shell (thicker at the temples/back: bin & tabo)
    def hcap(th, v):
        side = abs(math.sin(th))
        return 0.004 + (0.008 + 0.003 * side) * smoothstep(0, 0.35, v) * (1 - 0.5 * smoothstep(0.7, 1.0, v))
    cap(b, head, lo, hi, hcap)
    # shaved pate, slightly bluish skin
    nat = lambda th: max(lo(th), hi(th))
    cap(b, head, nat, lambda th: math.pi / 2, lambda th, v: 0.0009, mat="skin", tuck=0.002)
    K = head.dir(math.pi, D(57))
    # combed strands from the hairline to the knot
    combed_flow(b, head, lo, hi, K, 44, 0.009, 0.007, bump=0.003, w=(0.032, 0.046), t=0.009)
    # strands along the upper (shaved) edge to give it a crisp combed rim
    for i in range(26):
        th = D(-150 + 300 * (i + 0.5) / 26)
        if abs(th) < D(56):
            continue
        d0 = head.dir(th, hi(th) - D(4))
        n = 20
        pts = arc_path(head, d0, K, n, lambda s: 0.011 - 0.002 * s)
        widths = taper(n, 0.024, 0.03, 0.1, 0.3)
        sweep(b, head, "hair", pts, widths, [0.008] * n, uvoff=random.random())
    # knot base (tied stub) and motoyui
    th_k, ph_k = math.pi, D(57)
    base = head.scalp(th_k, ph_k, 0.006)
    n_out = (base - head.C).normalized()
    fwd = Vector((0, 0, 1))
    side = Vector((1, 0, 0))
    stub_dir = (n_out * 0.7 + Vector((0, 1, 0)) * 0.6).normalized()
    p1 = base + stub_dir * 0.011
    ellipsoid(b, head, "hair", base, (0.017, 0.011, 0.015),
              basis=(side, n_out, n_out.cross(side)))
    tube(b, head, "hair", [base - stub_dir * 0.004, p1], 0.0095, n=4)
    for k in range(2):
        c = base.lerp(p1, 0.45 + 0.3 * k)
        ring(b, head, "acc_white", c, stub_dir, 0.0097, 0.0017)
    # the folded queue (mage) lying forward over the pate
    path = [p1 - stub_dir * 0.006, p1 + stub_dir * 0.006 + Vector((0, 0.002, 0.004)),
            head.scalp(math.pi, D(78), 0.012), head.scalp(0.0, D(88), 0.0095),
            head.scalp(0.0, D(79), 0.009), head.scalp(0.0, D(69), 0.0088)]
    n = 26
    P = smooth_pts(resample(path, n), 2)
    def mw(s):
        return 0.026 * (1.0 - 0.15 * s + 0.25 * smoothstep(0.86, 1.0, s))
    widths = [mw(k / (n - 1)) for k in range(n)]
    thick = [0.018 * (1 - 0.3 * k / (n - 1)) for k in range(n)]
    widths[-1] = widths[-2] * 0.55
    thick[-1] = thick[-2] * 0.55
    sweep(b, head, "hair", P, widths, thick, flat=0.55, sharp=0.9, uvoff=0.3, tip=False)


def female_hairline():
    return interp_table([(0, 27), (35, 22), (60, 8), (75, -8), (88, -16), (105, -20),
                         (125, -28), (150, -48), (180, -56)])


def full_combed(b, head, lo, target, n_cl=46, h0=0.009, h1=0.008, bump=0.003, cap_h=0.009, w=(0.032, 0.046)):
    cap(b, head, lo, lambda th: math.pi / 2,
        lambda th, v: 0.004 + cap_h * smoothstep(0, 0.35, v))
    combed_flow(b, head, lo, lambda th: math.pi / 2 - D(8), target, n_cl, h0, h1, bump=bump, w=w, t=0.009)


def chasen(b, head):
    """戦国 茶筅髷: all hair combed up to a crown knot, cord-wrapped stalk, whisk-like splayed tip."""
    lo = male_hairline()
    th_k, ph_k = math.pi, D(70)
    K = head.dir(th_k, ph_k)
    full_combed(b, head, lo, K, n_cl=50, h0=0.010, h1=0.008, bump=0.004)
    base = head.scalp(th_k, ph_k, 0.006)
    n_out = (base - head.C).normalized()
    side = Vector((1, 0, 0))
    ellipsoid(b, head, "hair", base, (0.02, 0.012, 0.018), basis=(side, n_out, n_out.cross(side)))
    sdir = (n_out * 0.55 + Vector((0, 1, 0)) * 0.75 + Vector((0, 0, -1)) * 0.25).normalized()
    L = 0.042
    p1 = base + sdir * L
    tube(b, head, "hair", [base - sdir * 0.004, p1], 0.0095, n=6)
    for k in range(6):
        ring(b, head, "acc_red", base.lerp(p1, 0.2 + 0.13 * k), sdir, 0.0098, 0.0021)
    # whisk tip: splayed pointed clumps
    a1 = sdir.orthogonal().normalized()
    a2 = sdir.cross(a1)
    for k in range(11):
        ang = 2 * math.pi * k / 11 + random.uniform(-0.2, 0.2)
        spread = random.uniform(0.35, 0.6)
        d = (sdir + (a1 * math.cos(ang) + a2 * math.sin(ang)) * spread).normalized()
        ln = random.uniform(0.045, 0.07)
        q0 = p1 - sdir * 0.006 + (a1 * math.cos(ang) + a2 * math.sin(ang)) * 0.004
        q1 = q0 + d * ln * 0.5
        q2 = q0 + d * ln + Vector((0, -0.012, 0)) + Vector((0, 0, -0.01))
        path_clump(b, head, [q0, q1, q2], 0.017, 0.008, n=12, w_root=0.7, tip_frac=0.7, outs=[d.cross(a1)] * 12)
    # a couple of loose locks at the temples
    for sgn in (-1, 1):
        for k, (th, ln, w) in enumerate([(34, 0.075, 0.024), (46, 0.06, 0.02)]):
            p0 = head.scalp(sgn * D(th), D(40), 0.009)
            v0 = Vector((sgn * 0.15, -1.0, 0.25))
            pts = drape(head, p0, v0, ln, hfn=lambda L: 0.009 + 0.05 * L, grav=0.2, step=0.004)
            path_clump(b, head, pts, w, 0.008, w_root=0.8, tip_frac=0.7)


def court_bun(b, head):
    """古代・平安 男: hair combed up into a topknot bun (worn under an eboshi)."""
    lo = male_hairline()
    th_k, ph_k = math.pi, D(80)
    K = head.dir(th_k, ph_k)
    full_combed(b, head, lo, K, n_cl=50, h0=0.008, h1=0.007, bump=0.002, cap_h=0.007)
    base = head.scalp(th_k, ph_k, 0.004)
    n_out = (base - head.C).normalized()
    up = (n_out * 0.3 + Vector((0, 1, 0))).normalized()
    side = Vector((1, 0, 0))
    fwd = side.cross(up)
    ellipsoid(b, head, "hair", base, (0.022, 0.010, 0.022), basis=(side, up, fwd))
    top = base + up * 0.034
    # bun: slightly bulging cylinder of wrapped hair
    sweep(b, head, "hair", [base + up * (0.034 * k / 9) for k in range(10)],
          [2 * 0.0165 * (1 + 0.12 * math.sin(math.pi * k / 9)) for k in range(10)],
          [2 * 0.0165 * (1 + 0.12 * math.sin(math.pi * k / 9)) for k in range(10)],
          outs=[fwd] * 10, round_xs=True, tip=False, K=16)
    ellipsoid(b, head, "hair", top, (0.0168, 0.008, 0.0168), basis=(side, up, fwd))
    ring(b, head, "acc_purple", base + up * 0.008, up, 0.017, 0.0022)
    ring(b, head, "acc_purple", base + up * 0.014, up, 0.0175, 0.0022)


def buzz(b, head):
    """近代 丸刈り（軍隊式）: very short cropped shell with a fuzzy hairline."""
    lo = interp_table([(0, 26), (35, 23), (60, 12), (75, -2), (88, -10), (100, -12),
                       (120, -24), (150, -48), (180, -56)])
    cap(b, head, lo, lambda th: math.pi / 2, lambda th, v: 0.0025 + 0.0025 * smoothstep(0, 0.3, v),
        mat="hair_buzz", tuck=0.002)
    # short bristle tufts along the hairline
    for i in range(140):
        th = -math.pi + 2 * math.pi * (i + random.uniform(-0.3, 0.3)) / 140
        ph = lo(th) + D(random.uniform(2, 6))
        d0 = head.dir(th, ph)
        d1 = head.dir(th + D(random.uniform(-2, 2)), ph - D(random.uniform(3, 6)))
        pts = arc_path(head, d0, d1, 5, lambda s: 0.003 + 0.0008 * s)
        sweep(b, head, "hair_buzz", pts, taper(5, 0.009, 0.009, 0.0, 0.8), [0.0035] * 5,
              uvoff=random.random())


def curl_in(head, pts, amount=0.014, drop=0.01):
    e = pts[-1]
    inward = Vector((-e.x, 0, -(e.z - head.C.z)))
    inward = inward.normalized() if inward.length > 1e-6 else Vector((0, 0, 1))
    return pts + [e + Vector((0, -drop * 0.6, 0)) + inward * amount * 0.35,
                  e + Vector((0, -drop, 0)) + inward * amount]


def bob(b, head):
    """昭和 おかっぱ/ボブ: blunt fringe above the brows, chin-length rounded bob."""
    lo = female_hairline()
    cap(b, head, lo, lambda th: math.pi / 2, lambda th, v: 0.004 + 0.007 * smoothstep(0, 0.4, v))
    W = head.dir(math.pi, D(84))
    chin = head.face_min[1] + 0.03
    fringe = head.brow_top + 0.010
    def cut(th):
        a = abs(th)
        if a < D(46):
            return fringe
        t = smoothstep(D(46), D(78), a)
        return fringe * (1 - t) + (chin + 0.01 * (a / math.pi)) * t
    for layer in range(2):
        n_cl = 44 if layer == 0 else 30
        for i in range(n_cl):
            th = -math.pi + 2 * math.pi * (i + 0.5 * layer + random.uniform(-0.15, 0.15)) / n_cl
            front = abs(th) < D(48)
            yc = cut(th) + (0.0 if layer == 0 else (0.006 if front else 0.02))
            hb = 0.010 if front else 0.016 - 0.005 * layer
            d1 = head.dir(th, D(50))
            sc = scalp_arc(head, slerp(W, d1, 0.1), d1, 6, 0.012 if front else hb)
            pts = hang_path(head, sc, yc, hfn=(lambda y: 0.012) if front else (lambda y, hb=hb: hb + 0.004 * smoothstep(head.C.y + 0.05, head.C.y - 0.04, y)),
                            dy=0.003)
            if not front:
                pts = curl_in(head, pts, 0.012, 0.008)
            w = random.uniform(0.04, 0.05) if front else random.uniform(0.05, 0.062)
            path_clump(b, head, pts, w, 0.011, w_root=0.6, p_root=0.1, tip="blunt")


def back_guide(head, layer=0.0, xlim=0.12):
    """force field that combs hanging hair behind the ears/shoulders into a curtain on the back."""
    def f(p, L):
        out = Vector((0, 0, 0))
        if p.y < head.C.y - 0.03:
            zt = head.back_z - 0.01 - layer
            if p.z > zt:
                out.z = -0.35 * min(1.0, (p.z - zt) / 0.03)
            if abs(p.x) > xlim and p.y < head.neck_y + 0.03:
                out.x = -0.2 * math.copysign(min(1.0, (abs(p.x) - xlim) / 0.03), p.x)
        return out
    return f


def suberakashi(b, head):
    """平安 垂髪: centre-parted straight hair to the knees, side locks (鬢削ぎ) at the collarbone."""
    lo = female_hairline()
    cap(b, head, lo, lambda th: math.pi / 2, lambda th, v: 0.005 + 0.006 * smoothstep(0, 0.4, v))
    knee = head.knee_y + 0.03
    collar = head.face_min[1] - 0.07
    NP = 16
    for sgn in (-1, 1):
        for k in range(NP):
            a = D(30) + (D(150) - D(30)) * k / (NP - 1)
            d0 = Vector((sgn * 0.045, math.sin(a), math.cos(a))).normalized()
            th_side = D(62) + D(112) * (k / (NP - 1)) ** 0.9
            d1 = head.dir(sgn * th_side, D(18))
            sc = [surf_pt(head, slerp(d0, d1, t / 9), 0.004 + 0.007 * smoothstep(0, 0.35, t / 9)) for t in range(10)]
            if k < 3:
                pts = hang_path(head, sc, collar - 0.01 * k, hfn=lambda y: 0.012, dy=0.003)
                path_clump(b, head, pts, 0.05, 0.011, w_root=0.6, p_root=0.08, tip="blunt")
                continue
            tb = sgn * max(th_side, D(150) + D(10) * (k - 3) / (NP - 4))
            def thf(y, t0=sgn * th_side, tb=tb):
                return t0 + (tb - t0) * smoothstep(head.C.y - 0.02, head.neck_y + 0.03, y)
            ln = random.uniform(-0.03, 0.03)
            pts = hang_path(head, sc, knee + ln, th_fn=thf, hfn=lambda y: 0.012 + 0.006 * smoothstep(head.C.y, head.neck_y, y),
                            dy=0.004, narrow=0.002)
            path_clump(b, head, pts, random.uniform(0.05, 0.062), 0.010, w_root=0.6, p_root=0.03, n=56, tip="blunt")
    # inner back layer (fills the curtain from the occiput)
    for i in range(12):
        th = math.pi + D(-50 + 100 * i / 11)
        sc = [head.scalp(th, D(30), 0.007), head.scalp(th, D(20), 0.007)]
        pts = hang_path(head, sc, knee + 0.04, hfn=lambda y: 0.007, dy=0.004, narrow=0.002)
        path_clump(b, head, pts, 0.06, 0.009, w_root=0.8, p_root=0.03, n=56, tip="blunt")


def puffed_flow(b, head, ths, lo, target, hfun, w=(0.034, 0.046), t=0.010, n=26, rows=1, lift_lo=0.02, uvoff=None):
    """strands from the hairline (at azimuths ths) to a target dir, with a height profile hfun(s, th)."""
    for th in ths:
        for r in range(rows):
            ph = lo(th) + lift_lo + D(9) * r
            d0 = head.dir(th, ph)
            pts = arc_path(head, d0, target, n, lambda s, th=th, r=r: hfun(s, th) * (1 - 0.25 * r) * smoothstep(-0.02, 0.1, s) - 0.0015 * (1 - smoothstep(0, 0.1, s)))
            ww = random.uniform(*w)
            widths = taper(n, ww * 0.85, ww, 0.12, 0.3, 1.0)
            thick = [t * (0.5 + 0.5 * smoothstep(0, 0.1, k / (n - 1))) for k in range(n)]
            sweep(b, head, "hair", pts, widths, thick, uvoff=random.random() if uvoff is None else uvoff)


def loop_band(b, head, mat, a, c, height, width, thick, normal_hint, N=28, bulge=1.0):
    """flattened loop (like a bow lobe) from point a out to point c and back; band width along normal_hint x tangent."""
    a, c = Vector(a), Vector(c)
    ax = c - a
    L = ax.length
    ax.normalize()
    up = Vector(normal_hint)
    up = (up - ax * up.dot(ax)).normalized()
    ctr = (a + c) * 0.5
    pts, outs = [], []
    for k in range(N + 1):
        t = math.pi + 2 * math.pi * k / N      # start at a (angle pi)
        x = math.cos(t) * L * 0.5
        y = math.sin(t) * height * (1.0 + 0.15 * bulge * math.cos(t))
        p = ctr + ax * x + up * y
        pts.append(p)
        outs.append((ax * (x / (L * 0.5)) / (L * 0.5) + up * (y / height) / height).normalized())
    sweep(b, head, mat, pts, [width] * len(pts), [thick] * len(pts), outs=outs, flat=1.0, sharp=0.6,
          tip=False, root_cap=False, uvfn=None if mat == "hair" else (lambda v: (0.5, 0.5)))


def pin(b, head, mat, p0, p1, r=0.0025):
    tube(b, head, mat, [Vector(p0), Vector(p1)], r, n=3)


def flower(b, head, center, normal, r=0.012, petal="acc_coral", heart="acc_gold"):
    n = Vector(normal).normalized()
    a1 = n.orthogonal().normalized()
    a2 = n.cross(a1)
    for k in range(5):
        ang = 2 * math.pi * k / 5
        d = a1 * math.cos(ang) + a2 * math.sin(ang)
        ellipsoid(b, head, petal, Vector(center) + d * r * 0.55, (r * 0.5, r * 0.18, r * 0.36),
                  basis=(d, n, d.cross(n)), nu=10, nv=6, uvfn=lambda v: (0.5, 0.5))
    ellipsoid(b, head, heart, Vector(center) + n * r * 0.1, (r * 0.28, r * 0.2, r * 0.28),
              basis=(a1, n, a2), nu=10, nv=6, uvfn=lambda v: (0.5, 0.5))


def shimada(b, head):
    """江戸 島田髷: maegami, puffed bin wings, tabo, folded shimada knot with kanoko tie, comb & kanzashi."""
    lo = female_hairline()
    cap(b, head, lo, lambda th: math.pi / 2, lambda th, v: 0.004 + 0.006 * smoothstep(0, 0.4, v))
    up = Vector((0, 1, 0))
    X = Vector((1, 0, 0))
    # mage tie point (crown, slightly back)
    T = head.scalp(math.pi, D(68), 0.03)
    # maegami: front pompadour gathered towards the top
    tgt_front = head.dir(math.pi, D(80))
    puffed_flow(b, head, [D(a) for a in range(-36, 37, 6)], lo, tgt_front,
                lambda s, th: 0.006 + 0.032 * math.sin(math.pi * min(1.0, s * 1.7)) ** 0.7 * (1 - 0.35 * abs(th) / D(36)),
                w=(0.036, 0.046), rows=2)
    # bin: side wings combed back, puffed out over the ears
    tgt_back = head.dir(math.pi, D(12))
    side_ths = [sg * D(a) for sg in (-1, 1) for a in range(44, 136, 7)]
    puffed_flow(b, head, side_ths, lo, tgt_back,
                lambda s, th: 0.006 + 0.036 * math.sin(math.pi * min(1.0, s * 1.5 + 0.08)) ** 0.6 * (0.55 + 0.45 * abs(math.sin(th))),
                w=(0.036, 0.05), rows=2)
    # tabo: nape hair combed up with a backward bulge
    tgt_up = head.dir(math.pi, D(64))
    back_ths = [math.pi + D(a) for a in range(-50, 51, 6)]
    puffed_flow(b, head, back_ths, lo, tgt_up,
                lambda s, th: 0.006 + 0.034 * math.sin(math.pi * min(1.0, s * 1.9 + 0.05)) ** 0.7 * (1 - 0.3 * abs(math.sin(th))),
                w=(0.036, 0.05), rows=2)
    # shimada knot: front & back lobes tied at T
    up = Vector((0, 1, 0))
    F = T + Vector((0, 0.026, 0.062))
    Bk = T + Vector((0, -0.004, -0.06))
    loop_band(b, head, "hair", T + Vector((0, 0, 0.004)), F, 0.017, 0.056, 0.013, up + Vector((0, 0, -0.4)))
    loop_band(b, head, "hair", T + Vector((0, 0, -0.004)), Bk, 0.018, 0.06, 0.013, up + Vector((0, 0, 0.3)))
    # base pad under the knot
    ellipsoid(b, head, "hair", T + Vector((0, -0.01, 0)), (0.028, 0.014, 0.03), nu=16, nv=8)
    # kanoko (red tie-dyed cloth) + white motoyui around the middle
    for k in range(2):
        z = 0.004 - 0.008 * k
        pts = []
        for j in range(25):
            a = 2 * math.pi * j / 24
            pts.append(T + Vector((math.cos(a) * 0.029, math.sin(a) * 0.016 - 0.002, z)))
        outs = [(p - T - Vector((0, -0.002, z))) for p in pts]
        sweep(b, head, "acc_red" if k == 0 else "acc_white", pts, [0.009 if k == 0 else 0.004] * 25,
              [0.007 if k == 0 else 0.004] * 25, outs=outs, round_xs=True, tip=False, root_cap=False,
              uvfn=lambda v: (0.5, 0.5))
    # kogai: tortoiseshell bar through the knot
    sweep(b, head, "acc_comb", [T + Vector((x, 0.003, 0.0)) for x in [-0.075 + 0.015 * k for k in range(11)]],
          [0.010 if k in (0, 10) else 0.007 for k in range(11)], [0.006] * 11, outs=[up] * 11,
          flat=1.0, sharp=0.5, tip=False, uvfn=lambda v: (0.5, 0.5))
    # kushi: half-moon comb standing in front of the knot
    cb = head.scalp(0.0, D(84), 0.02)
    n_c = (cb - head.C).normalized()
    fwd_c = (Vector((0, 0, 1)) - n_c * Vector((0, 0, 1)).dot(n_c)).normalized()
    up_c = n_c
    N = 21
    pts, ws = [], []
    for k in range(N):
        x = -0.04 + 0.08 * k / (N - 1)
        hgt = 0.021 * math.sqrt(max(0.0, 1 - (x / 0.04) ** 2))
        pts.append(cb + X * x + up_c * (hgt * 0.5 - 0.004))
        ws.append(hgt + 0.008)
    ws[0] = ws[-1] = 0.0
    sweep(b, head, "acc_comb", pts, ws, [0.006] * N, outs=[fwd_c] * N, flat=1.0, sharp=0.35, tip=True,
          uvfn=lambda v: (0.5, 0.5))
    # gold trim on the comb spine
    arc = [cb + X * (0.039 * math.cos(math.pi * k / 16)) + up_c * (0.021 * math.sin(math.pi * k / 16) + 0.0035) for k in range(17)]
    tube(b, head, "acc_gold", arc, 0.0016, n=17)
    # kanzashi: coral-ball pin and a flower pin
    p_in = T + Vector((0.01, 0.004, 0.012))
    p_out = p_in + Vector((0.085, 0.02, 0.03))
    pin(b, head, "acc_gold", p_in, p_out, 0.0022)
    ellipsoid(b, head, "acc_coral", p_out, (0.0105, 0.0105, 0.0105), nu=12, nv=8, uvfn=lambda v: (0.5, 0.5))
    p_in2 = head.scalp(-D(30), D(62), 0.02)
    p_out2 = p_in2 + Vector((-0.04, 0.045, 0.02))
    pin(b, head, "acc_gold", p_in2, p_out2, 0.0018)
    flower(b, head, p_out2, (p_out2 - p_in2), r=0.022)
    # dangling strips (bira-bira) under the flower
    for k in range(5):
        a = -0.5 + 0.25 * k
        q0 = p_out2 + Vector((math.sin(a) * 0.008, -0.004, math.cos(a) * 0.004))
        pin(b, head, "acc_gold", q0, q0 + Vector((-0.003 * k, -0.03 - 0.006 * (k % 2), 0.002)), 0.0009)


def sokuhatsu(b, head):
    """明治・大正 束髪: hisashigami (puffed eaves at the front), bun at the back, big ribbon."""
    lo = female_hairline()
    cap(b, head, lo, lambda th: math.pi / 2, lambda th, v: 0.004 + 0.006 * smoothstep(0, 0.4, v))
    Bdir = head.dir(math.pi, D(32))
    # hisashi: big front puff projecting forward
    ths = [D(a) for a in range(-66, 67, 6)]
    puffed_flow(b, head, ths, lo, Bdir,
                lambda s, th: 0.006 + 0.05 * math.sin(math.pi * min(1.0, s * 2.4 + 0.06)) ** 0.55 * (1 - 0.45 * abs(th) / D(66)) + 0.008 * s,
                w=(0.038, 0.05), rows=2, n=30)
    # sides / back combed into the bun
    ths2 = [sg * D(a) for sg in (-1, 1) for a in range(72, 181, 7)]
    puffed_flow(b, head, ths2, lo, Bdir,
                lambda s, th: 0.006 + 0.016 * math.sin(math.pi * min(1.0, s * 1.3)) ** 0.8,
                w=(0.036, 0.05), rows=2)
    # bun: coiled hair
    base = head.scalp(math.pi, D(32), 0.012)
    n_o = (base - head.C).normalized()
    a1 = Vector((1, 0, 0))
    a2 = n_o.cross(a1)
    pts, outs, ws = [], [], []
    M = 70
    for k in range(M):
        t = k / (M - 1)
        ang = 2 * math.pi * 2.2 * t
        rr = 0.03 * (1 - 0.75 * t)
        p = base + (a1 * math.cos(ang) + a2 * math.sin(ang)) * rr + n_o * (0.008 + 0.02 * t)
        pts.append(p)
        outs.append(((a1 * math.cos(ang) + a2 * math.sin(ang)) * 0.6 + n_o).normalized())
        ws.append(0.026 * (1 - 0.4 * t))
    sweep(b, head, "hair", pts, ws, [0.02 * (1 - 0.3 * t / M) for t in range(M)], outs=outs, tip=True, flat=0.7)
    ellipsoid(b, head, "hair", base + n_o * 0.006, (0.034, 0.016, 0.034), basis=(a1, n_o, a2))
    # ribbon on top of the bun
    K = base + n_o * 0.024 + Vector((0, 0.03, 0))
    rn = (n_o + Vector((0, 0.6, 0))).normalized()     # ribbon facing back-up
    ellipsoid(b, head, "acc_ribbon", K, (0.012, 0.014, 0.008), basis=(a1, rn.cross(a1).normalized(), rn),
              nu=12, nv=8, uvfn=lambda v: (0.5, 0.5))
    for sg in (-1, 1):
        c = K + a1 * (sg * 0.075) + Vector((0, 0.022, 0))
        loop_band(b, head, "acc_ribbon", K + a1 * (sg * 0.006), c, 0.022, 0.042, 0.004, rn, bulge=1.5)
        # tails
        tail = [K + a1 * (sg * 0.004), K + a1 * (sg * 0.02) + Vector((0, -0.04, 0)) + rn * 0.01,
                K + a1 * (sg * 0.04) + Vector((0, -0.09, 0)) + rn * 0.012]
        P = resample(tail, 10)
        sweep(b, head, "acc_ribbon", P, [0.03 + 0.012 * k / 9 for k in range(10)], [0.004] * 10,
              outs=[rn] * 10, flat=1.0, sharp=0.3, tip="blunt", uvfn=lambda v: (0.5, 0.5))


STYLES = {
    "chonmage": chonmage,
    "chasen": chasen,
    "court_bun": court_bun,
    "zangiri": zangiri,
    "buzz": buzz,
    "suberakashi": suberakashi,
    "bob": bob,
    "shimada": shimada,
    "sokuhatsu": sokuhatsu,
}

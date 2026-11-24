"""Procedural anime hair toolkit (Blender bpy module).

Coordinates: "local" = Godot convention relative to the VRM head bone:
  x = character's ... (Godot +X), y = up, z = forward (face direction).
Blender VRM import gives face toward +By, up Bz, and Godot x = -Bx.
"""
import bpy, bmesh, math, os
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))


def b2l(v, H):
    return Vector((-(v[0] - H[0]), v[2] - H[2], v[1] - H[1]))


class Head:
    def __init__(self, name):
        self.name = name
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "vrm", name + ".glb"))
        arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
        H = arm.matrix_world @ arm.data.bones["J_Bip_C_Head"].head_local
        self.H = H
        neck = arm.matrix_world @ arm.data.bones["J_Bip_C_Neck"].head_local
        self.neck_y = neck.z - H.z
        bz = lambda n: (arm.matrix_world @ arm.data.bones[n].head_local).z - H.z
        self.hips_y = bz("J_Bip_C_Hips")
        self.knee_y = bz("J_Bip_L_LowerLeg")
        self.chest_y = bz("J_Bip_C_UpperChest")
        self.shoulder_y = bz("J_Bip_L_UpperArm")
        skin_v, skin_f = [], []
        body_v, body_f = [], []
        face_skin_v = []
        for o in bpy.data.objects:
            if o.type != 'MESH' or o.name not in ("Face", "Body"):
                continue
            me = o.data
            mw = o.matrix_world
            vl = [b2l(mw @ v.co, H) for v in me.vertices]
            for p in me.polygons:
                mname = me.materials[p.material_index].name
                if "HairBack" in mname:
                    continue
                if o.name == "Body" and max(abs(vl[i].x) for i in p.vertices) < 0.16:
                    body_f.append([len(body_v) + i for i in range(len(p.vertices))])
                    body_v.extend(vl[i] for i in p.vertices)
                if "SKIN" in mname:
                    ys = [vl[i].y for i in p.vertices]
                    if o.name == "Face" or min(ys) > self.neck_y - 0.01:
                        skin_f.append([len(skin_v) + i for i in range(len(p.vertices))])
                        skin_v.extend(vl[i] for i in p.vertices)
                        if o.name == "Face" and "Face_00" in mname:
                            face_skin_v.extend(vl[i] for i in p.vertices)
                if o.name == "Face" and "FaceBrow" in mname:
                    pass
        self.skin = BVHTree.FromPolygons(skin_v, skin_f)
        self.body = BVHTree.FromPolygons(body_v, body_f)
        fs = np.array([tuple(v) for v in face_skin_v])
        self.face_min = fs.min(0)
        self.face_max = fs.max(0)
        allv = np.array([tuple(v) for v in skin_v])
        self.top_y = allv[:, 1].max()
        # brows
        bv = []
        for o in bpy.data.objects:
            if o.name == "Face":
                me = o.data
                for p in me.polygons:
                    if "FaceBrow" in me.materials[p.material_index].name:
                        bv.extend(b2l(o.matrix_world @ me.vertices[i].co, H) for i in p.vertices)
        bv = np.array([tuple(v) for v in bv])
        self.brow_top = bv[:, 1].max()
        self.brow_front = bv[:, 2].max()
        # cranium: vertices above brow
        cr = allv[allv[:, 1] > self.brow_top - 0.01]
        zmin = cr[:, 2].min()
        zmax = cr[:, 2].max()
        xmax = np.abs(cr[:, 0]).max()
        cy = self.brow_top + 0.0
        self.C = Vector((0.0, cy - 0.0, (zmin + zmax) * 0.5 - 0.005))
        self.R = float((self.top_y - cy) * 1.0)
        self.half_w = float(xmax)
        self.back_z = float(zmin)
        self.front_z = float(zmax)
        # radius map on (theta, phi) grid, smoothed, ears removed
        self._build_rmap()

    # ---- scalp ----
    @staticmethod
    def dir(th, ph):
        return Vector((math.sin(th) * math.cos(ph), math.sin(ph), math.cos(th) * math.cos(ph)))

    def _cast(self, d):
        o = self.C + d * 0.6
        hit = self.skin.ray_cast(o, -d, 0.6)
        if hit[0] is None:
            return None
        return (hit[0] - self.C).length

    def _build_rmap(self):
        nt, npf = 72, 50
        self.th_grid = np.linspace(-math.pi, math.pi, nt + 1)
        self.ph_grid = np.linspace(-1.2, math.pi / 2, npf)
        r = np.zeros((nt + 1, npf))
        for i, th in enumerate(self.th_grid):
            for j, ph in enumerate(self.ph_grid):
                d = self.dir(th, ph)
                rr = self._cast(d)
                r[i, j] = rr if rr else np.nan
        # fill nans with column neighbours
        for i in range(nt + 1):
            col = r[i]
            good = ~np.isnan(col)
            if good.any():
                r[i] = np.interp(np.arange(npf), np.where(good)[0], col[good])
        self.r_raw = r.copy()
        # ears stick out: replace by a smooth, convex-ish "skull" estimate
        # limit radius growth relative to the upper neighbours in phi
        self.rmap = r

    def r_at(self, th, ph):
        th = (th + math.pi) % (2 * math.pi) - math.pi
        ph = min(max(ph, self.ph_grid[0]), self.ph_grid[-1])
        fi = (th - self.th_grid[0]) / (self.th_grid[1] - self.th_grid[0])
        fj = (ph - self.ph_grid[0]) / (self.ph_grid[1] - self.ph_grid[0])
        i0 = int(min(max(math.floor(fi), 0), len(self.th_grid) - 2))
        j0 = int(min(max(math.floor(fj), 0), len(self.ph_grid) - 2))
        a, b = fi - i0, fj - j0
        R = self.rmap
        return ((1 - a) * (1 - b) * R[i0, j0] + a * (1 - b) * R[i0 + 1, j0] +
                (1 - a) * b * R[i0, j0 + 1] + a * b * R[i0 + 1, j0 + 1])

    def scalp(self, th, ph, h=0.0):
        d = self.dir(th, ph)
        return self.C + d * (self.r_at(th, ph) + h)

    def sph(self, p):
        q = p - self.C
        r = q.length
        ph = math.asin(max(-1, min(1, q.y / r)))
        th = math.atan2(q.x, q.z)
        return th, ph, r

    def push_out(self, p, h):
        """push point out so it's at least h above the head (radial scalp map) and the torso."""
        q = Vector(p)
        th, ph, r = self.sph(q)
        if ph > self.ph_grid[0] + 0.05:
            rs = self.r_at(th, ph) + h
            if r < rs:
                q = self.C + (q - self.C).normalized() * rs
        if q.y < self.C.y - 0.03:
            loc, n, idx, dist = self.body.find_nearest(q, 0.08)
            if loc is not None:
                ax = Vector((loc.x, 0.0, loc.z - (self.C.z - 0.01)))
                if ax.length > 1e-6 and n.dot(ax) < 0:
                    n = -n
                d = (q - loc).dot(n)
                if d < h:
                    q = q + n * (h - d)
        return q


# ---------------------------------------------------------------------------
# geometry builder
class Builder:
    def __init__(self):
        self.parts = {}   # material -> (verts, faces, uvs)

    def _get(self, mat):
        if mat not in self.parts:
            self.parts[mat] = ([], [], [])
        return self.parts[mat]

    def add(self, mat, verts, faces, uvs):
        V, F, U = self._get(mat)
        base = len(V)
        V.extend(verts)
        U.extend(uvs)
        for f in faces:
            F.append([base + i for i in f])

    def to_object(self, name, flip=True):
        """build a Blender mesh object. local (x,y,z) -> blender export coords (x,-z,y)."""
        me = bpy.data.meshes.new(name)
        allv, allf, allu, mats = [], [], [], []
        mat_index = []
        for mi, (mat, (V, F, U)) in enumerate(self.parts.items()):
            base = len(allv)
            allv.extend(V)
            allu.extend(U)
            for f in F:
                allf.append([base + i for i in f])
                mat_index.append(mi)
            mats.append(mat)
        me.from_pydata([(v[0], -v[2], v[1]) for v in allv], [], allf)
        uvl = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            poly.material_index = mat_index[poly.index]
            for li in poly.loop_indices:
                vi = me.loops[li].vertex_index
                uvl.data[li].uv = allu[vi]
        for m in mats:
            mat = bpy.data.materials.get(m) or bpy.data.materials.new(m)
            me.materials.append(mat)
        me.shade_smooth()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        # merge duplicate verts? no: keep, but recalc normals outward per part
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bm.to_mesh(me)
        bm.free()
        me.shade_smooth()
        return ob


def catmull(ctrl, n):
    """smooth path through control points (list of Vector), resampled by arc length to n points"""
    P = [Vector(c) for c in ctrl]
    if len(P) == 2:
        dense = [P[0].lerp(P[1], t / 40) for t in range(41)]
    else:
        P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
        dense = []
        for i in range(1, len(P) - 2):
            p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
            for k in range(20):
                t = k / 20
                t2, t3 = t * t, t * t * t
                dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                                    (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        dense.append(P[-2])
    L = [0.0]
    for i in range(1, len(dense)):
        L.append(L[-1] + (dense[i] - dense[i - 1]).length)
    out = []
    tot = L[-1]
    j = 0
    for k in range(n):
        s = tot * k / (n - 1)
        while j < len(L) - 2 and L[j + 1] < s:
            j += 1
        seg = L[j + 1] - L[j]
        a = (s - L[j]) / seg if seg > 1e-9 else 0
        out.append(dense[j].lerp(dense[j + 1], a))
    return out, tot


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------
# UV convention (shared with texture generator)
S_SPLIT = 0.25    # metres of arc from the crown mapped to uv.y in [0, 0.5]
S_MAX = 1.45


def s_to_v(s):
    if s < S_SPLIT:
        return 0.5 * s / S_SPLIT
    return 0.5 + 0.5 * min(1.0, (s - S_SPLIT) / (S_MAX - S_SPLIT))


def head_uv(head, p, off=0.0):
    q = p - head.C
    r = max(q.length, 1e-6)
    R = head.R
    if q.y >= 0:
        a = math.acos(max(-1, min(1, q.y / r)))
        s = a * R
    else:
        s = R * math.pi / 2 + (-q.y)
    th = math.atan2(q.x, q.z)
    return (th / (2 * math.pi) * 5.0 + off, 1.0 - s_to_v(s))


def slerp(a, b, t):
    a = a.normalized(); b = b.normalized()
    d = max(-1.0, min(1.0, a.dot(b)))
    om = math.acos(d)
    if om < 1e-5:
        return a.lerp(b, t).normalized()
    so = math.sin(om)
    return (a * (math.sin((1 - t) * om) / so) + b * (math.sin(t * om) / so)).normalized()


def lens(a, w, t, flat=0.45, sharp=0.75):
    """cross-section point of a hair clump. a: angle, returns (x, y)"""
    c, s = math.cos(a), math.sin(a)
    x = math.copysign(abs(c) ** sharp, c) * w * 0.5
    y = s * t * 0.5 * (1.0 if s > 0 else flat)
    return x, y


def sweep(b, head, mat, pts, widths, thicks, outs=None, K=10, uvoff=0.0, flat=0.45, sharp=0.75,
          tip=True, root_cap=True, round_xs=False, uvfn=None):
    n = len(pts)
    pts = [Vector(p) for p in pts]
    V, F, U = [], [], []
    rings = []
    for i in range(n):
        if i == 0:
            T = pts[1] - pts[0]
        elif i == n - 1:
            T = pts[-1] - pts[-2]
        else:
            T = pts[i + 1] - pts[i - 1]
        T.normalize()
        o = Vector(outs[i]) if outs is not None else (pts[i] - head.C)
        N = o - T * o.dot(T)
        if N.length < 1e-6:
            N = T.orthogonal()
        N.normalize()
        B = T.cross(N)
        w, t = widths[i], thicks[i]
        last = (i == n - 1 and tip is True)
        if last or w < 1e-5:
            rings.append([len(V)])
            V.append(pts[i])
            continue
        ring = []
        for j in range(K):
            a = 2 * math.pi * j / K
            if round_xs:
                x, y = math.cos(a) * w * 0.5, math.sin(a) * t * 0.5
            else:
                x, y = lens(a, w, t, flat, sharp)
            ring.append(len(V))
            V.append(pts[i] + B * x + N * y)
        rings.append(ring)
    for i in range(n - 1):
        r0, r1 = rings[i], rings[i + 1]
        if len(r0) == 1 and len(r1) == 1:
            continue
        if len(r1) == 1:
            for j in range(len(r0)):
                F.append([r0[j], r1[0], r0[(j + 1) % len(r0)]])
        elif len(r0) == 1:
            for j in range(len(r1)):
                F.append([r0[0], r1[j], r1[(j + 1) % len(r1)]])
        else:
            for j in range(K):
                F.append([r0[j], r1[j], r1[(j + 1) % K], r0[(j + 1) % K]])
    if tip == "blunt" and len(rings[-1]) > 1:
        c = len(V)
        rl = rings[-1]
        V.append(sum((V[k] for k in rl), Vector()) / len(rl))
        for j in range(K):
            F.append([rl[(j + 1) % K], rl[j], c])
    if root_cap and len(rings[0]) > 1:
        c = len(V)
        V.append(sum((V[k] for k in rings[0]), Vector()) / len(rings[0]))
        r0 = rings[0]
        for j in range(K):
            F.append([r0[j], r0[(j + 1) % K], c])
    for v in V:
        U.append(uvfn(v) if uvfn else head_uv(head, v, uvoff))
    # orientation: ensure faces point outward (check first quad normal vs radial)
    b.add(mat, V, F, U)


def ellipsoid(b, head, mat, center, axes, basis=None, nu=16, nv=10, uvoff=0.0, uvfn=None):
    """axes = (ax, ay, az) radii; basis = (X, Y, Z) unit vectors"""
    X, Y, Z = basis if basis else (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
    center = Vector(center)
    V, F, U = [], [], []
    for j in range(nv + 1):
        ph = -math.pi / 2 + math.pi * j / nv
        for i in range(nu):
            th = 2 * math.pi * i / nu
            p = center + X * (axes[0] * math.cos(ph) * math.cos(th)) + Z * (axes[2] * math.cos(ph) * math.sin(th)) + Y * (axes[1] * math.sin(ph))
            V.append(p)
    for j in range(nv):
        for i in range(nu):
            a = j * nu + i
            bb = j * nu + (i + 1) % nu
            F.append([a, a + nu, bb + nu, bb])
    for v in V:
        U.append(uvfn(v) if uvfn else head_uv(head, v, uvoff))
    b.add(mat, V, F, U)


def surf_pt(head, d, h):
    th, ph, _ = head.sph(head.C + d)
    return head.C + d.normalized() * (head.r_at(th, ph) + h)


def arc_path(head, d0, d1, n, hfn, extra=None):
    """path on scalp from direction d0 to d1 (from head centre), height hfn(s)."""
    pts = []
    for k in range(n):
        s = k / (n - 1)
        d = slerp(d0, d1, s)
        pts.append(surf_pt(head, d, hfn(s)))
    return pts


def cap(b, head, phi_lo, phi_hi, hfn, mat="hair", nth=120, nv=28, tuck=0.004, uvoff=0.0):
    """scalp shell. phi_lo(th)/phi_hi(th): elevation interval per azimuth column (hi=pi/2 -> pole).
    hfn(th, v) -> height above skin (v=0 at lo edge, 1 at hi edge)."""
    V, F, U = [], [], []
    cols = []
    for i in range(nth):
        th = -math.pi + 2 * math.pi * i / nth
        lo, hi = phi_lo(th), phi_hi(th)
        hidden = False
        if hi < lo + 1e-3:
            m = 0.5 * (hi + lo)
            hi = lo = m
            hidden = True
        col = []
        # tuck row below the lower edge
        rows = [(-1, lo)] + [(k, lo + (hi - lo) * k / nv) for k in range(nv + 1)]
        top_open = hi < math.pi / 2 - 1e-3
        if top_open:
            rows.append((nv + 1, hi))
        for k, ph in rows:
            if k < 0 or k > nv or hidden:
                h = -tuck * 1.5
            else:
                h = hfn(th, k / nv)
            col.append(len(V))
            V.append(head.scalp(th, ph, h))
        cols.append(col)
    nr = len(cols[0])
    for i in range(nth):
        a, c = cols[i], cols[(i + 1) % nth]
        for k in range(nr - 1):
            F.append([a[k], c[k], c[k + 1], a[k + 1]])
    for v in V:
        U.append(head_uv(head, v, uvoff))
    b.add(mat, V, F, U)


def interp_table(table):
    """table: list of (theta_deg, value) for theta in [0,180]; symmetric; smooth cosine interpolation"""
    tb = sorted(table)

    def f(th):
        x = abs(math.degrees((th + math.pi) % (2 * math.pi) - math.pi))
        for i in range(len(tb) - 1):
            if tb[i][0] <= x <= tb[i + 1][0]:
                a = (x - tb[i][0]) / (tb[i + 1][0] - tb[i][0])
                a = 0.5 - 0.5 * math.cos(math.pi * a)
                return math.radians(tb[i][1] + (tb[i + 1][1] - tb[i][1]) * a)
        return math.radians(tb[-1][1])
    return f


def export_glb(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=False, export_normals=True,
                              export_materials='EXPORT', export_animations=False)


def out_dir(head, p):
    """outward direction for clump cross-sections (radial on the head, horizontal on the back)."""
    q = p - head.C
    rad = q.normalized() if q.length > 1e-6 else Vector((0, 1, 0))
    hor = Vector((p.x, 0.0, p.z - (head.C.z - 0.01)))
    hor = hor.normalized() if hor.length > 1e-6 else Vector((0, 0, -1))
    a = smoothstep(-0.02, -0.16, q.y)
    v = rad.lerp(hor, a)
    return v.normalized()


def drape(head, p0, v0, max_len, hfn=lambda L: 0.01, stop=None, step=0.005, grav=0.12, stiff=None, force=None, hug_y=None):
    """lite hair simulation: walk from p0 along v0, bending under gravity, pushed out of skin/body."""
    pts = [Vector(p0)]
    v = Vector(v0).normalized()
    L = 0.0
    p = Vector(p0)
    while L < max_len:
        g = grav if stiff is None else grav * stiff(L)
        v = v + Vector((0, -g, 0))
        if force:
            v = v + force(p, L)
        v = v.normalized()
        q = p + v * step
        hy = head.C.y if hug_y is None else hug_y
        if q.y > hy:
            th, ph, _ = head.sph(q)
            q = head.scalp(th, ph, hfn(L))
        q = head.push_out(q, hfn(L))
        d = q - p
        if d.length < 1e-6:
            break
        v = d.normalized()
        L += d.length
        p = q
        pts.append(p.copy())
        if stop and stop(p, L):
            break
    return pts


def resample(pts, n):
    out, _ = catmull(pts if len(pts) < 8 else pts[::max(1, len(pts) // 12)] + [pts[-1]], n)
    return out


def smooth_pts(pts, it=3):
    P = [Vector(p) for p in pts]
    for _ in range(it):
        Q = [P[0]]
        for i in range(1, len(P) - 1):
            Q.append(P[i - 1] * 0.25 + P[i] * 0.5 + P[i + 1] * 0.25)
        Q.append(P[-1])
        P = Q
    return P


# ---------------------------------------------------------------------------
# hanging hair: per-azimuth envelope of the head (hair falls straight down from the widest point)
def _profile(head, th):
    key = int(round(math.degrees(th))) % 360
    cache = head.__dict__.setdefault("_prof", {})
    if key in cache:
        return cache[key]
    t = math.radians(key)
    ys, rh = [], []
    for k in range(0, 160):
        ph = math.radians(89 - k)
        r = head.r_at(t, ph)
        ys.append(head.C.y + r * math.sin(ph))
        rh.append(r * math.cos(ph))
    # cumulative max downward (hair can't follow the surface back in)
    env = []
    m = 0.0
    for v in rh:
        m = max(m, v)
        env.append(m)
    # smooth (window in index ~ 1 deg steps)
    sm = []
    for i in range(len(env)):
        a, b = max(0, i - 4), min(len(env), i + 5)
        sm.append(max(env[i], sum(env[a:b]) / (b - a)))
    # make y strictly decreasing for interpolation (drop non-monotonic samples)
    Y, R = [], []
    for y, r in zip(ys, sm):
        if not Y or y < Y[-1] - 1e-5:
            Y.append(y); R.append(r)
    cache[key] = (Y, R)
    return cache[key]


def rho_env(head, th, y):
    t0 = math.floor(math.degrees(th))
    a = math.degrees(th) - t0
    def one(td):
        Y, R = _profile(head, math.radians(td))
        if y >= Y[0]:
            return 0.0
        if y <= Y[-1]:
            return R[-1]
        lo, hi = 0, len(Y) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if Y[mid] > y:
                lo = mid
            else:
                hi = mid
        f = (Y[lo] - y) / (Y[lo] - Y[hi])
        return R[lo] + (R[hi] - R[lo]) * f
    return one(t0) * (1 - a) + one(t0 + 1) * a


def hang_path(head, scalp_pts, y_end, th_fn=None, hfn=lambda y: 0.012, dy=0.005, narrow=0.0, head_zone=None):
    """continue a strand from its scalp section straight down along the head envelope, then the body."""
    pts = [Vector(p) for p in scalp_pts]
    p = pts[-1]
    th0, _, _ = head.sph(p)
    y = p.y
    hz = head.neck_y + 0.03 if head_zone is None else head_zone
    while y > y_end:
        y -= dy
        h = hfn(y)
        if y > hz:
            th = th_fn(y) if th_fn else th0
            rho = max(rho_env(head, th, y) + h, 0.0)
            q = Vector((head.C.x + math.sin(th) * rho, y, head.C.z + math.cos(th) * rho))
        else:
            q = Vector((p.x * (1 - narrow), y, p.z))
        q = head.push_out(q, h)
        pts.append(q)
        p = q
    return pts


def scalp_arc(head, d0, d1, n, h):
    return [surf_pt(head, slerp(d0, d1, k / (n - 1)), h) for k in range(n)]

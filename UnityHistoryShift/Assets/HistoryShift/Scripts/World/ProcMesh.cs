using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace HistoryShift
{
    /// <summary>
    /// 手続き生成メッシュのビルダー。面ごとにフラット法線、UV はメートル単位（uvScale メートルで1リピート）。
    /// 面の向きは「外向きヒント」と照合して自動で反転するので、頂点の並び順を気にせず使える。
    /// </summary>
    public class MeshBuilder
    {
        readonly List<Vector3> verts = new List<Vector3>();
        readonly List<Vector3> norms = new List<Vector3>();
        readonly List<Vector2> uvs = new List<Vector2>();
        readonly List<int> tris = new List<int>();
        public float uvScale = 2f;

        public MeshBuilder(float uvScale = 2f) { this.uvScale = uvScale; }

        public int VertexCount => verts.Count;

        /// <summary>三角形を追加。outward は面が向くべき方向のヒント（ゼロなら頂点順のまま）。</summary>
        public void Tri(Vector3 a, Vector3 b, Vector3 c, Vector3 outward)
        {
            Vector3 n = Vector3.Cross(b - a, c - a);
            if (n.sqrMagnitude < 1e-10f) return;
            if (outward != Vector3.zero && Vector3.Dot(n, outward) < 0f) { var t = b; b = c; c = t; n = -n; }
            n.Normalize();
            // 面内の2軸でプレーナーUV
            Vector3 u = (b - a).normalized;
            Vector3 v = Vector3.Cross(n, u);
            int i = verts.Count;
            foreach (var p in new[] { a, b, c })
            {
                verts.Add(p); norms.Add(n);
                Vector3 d = p - a;
                uvs.Add(new Vector2(Vector3.Dot(d, u), Vector3.Dot(d, v)) / uvScale + PlanarOffset(a, n));
            }
            tris.Add(i); tris.Add(i + 1); tris.Add(i + 2);
        }

        // 隣接面のテクスチャ継ぎ目を目立たなくするためのワールド基準オフセット
        static Vector2 PlanarOffset(Vector3 a, Vector3 n)
        {
            if (Mathf.Abs(n.y) > 0.7f) return new Vector2(a.x, a.z) * 0.0f;
            return Vector2.zero;
        }

        /// <summary>四角形 a-b-c-d（周回順）。UV は a を原点に a→b を U、a→d を V とする。</summary>
        public void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 outward)
        {
            Vector3 n = Vector3.Cross(b - a, c - a);
            if (n.sqrMagnitude < 1e-10f) n = Vector3.Cross(c - a, d - a);
            if (n.sqrMagnitude < 1e-10f) return;
            if (outward != Vector3.zero && Vector3.Dot(n, outward) < 0f)
            {
                var t = b; b = d; d = t; n = -n;
            }
            n.Normalize();
            Vector3 u = (b - a); float lu = u.magnitude; if (lu < 1e-5f) { u = (c - d); lu = u.magnitude; }
            u = lu > 1e-5f ? u / lu : Vector3.right;
            Vector3 v = Vector3.Cross(n, u);
            int i = verts.Count;
            foreach (var p in new[] { a, b, c, d })
            {
                verts.Add(p); norms.Add(n);
                Vector3 dd = p - a;
                uvs.Add(new Vector2(Vector3.Dot(dd, u), Vector3.Dot(dd, v)) / uvScale);
            }
            tris.Add(i); tris.Add(i + 1); tris.Add(i + 2);
            tris.Add(i); tris.Add(i + 2); tris.Add(i + 3);
        }

        /// <summary>両面の四角形（屋根の軒裏など）。</summary>
        public void QuadDouble(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 outward)
        {
            Quad(a, b, c, d, outward);
            Quad(a, b, c, d, -outward);
        }

        public void Box(Vector3 center, Vector3 size)
        {
            Vector3 h = size * 0.5f;
            Vector3[] p =
            {
                center + new Vector3(-h.x, -h.y, -h.z), center + new Vector3(h.x, -h.y, -h.z),
                center + new Vector3(h.x, -h.y, h.z), center + new Vector3(-h.x, -h.y, h.z),
                center + new Vector3(-h.x, h.y, -h.z), center + new Vector3(h.x, h.y, -h.z),
                center + new Vector3(h.x, h.y, h.z), center + new Vector3(-h.x, h.y, h.z),
            };
            Quad(p[0], p[1], p[5], p[4], Vector3.back);
            Quad(p[1], p[2], p[6], p[5], Vector3.right);
            Quad(p[2], p[3], p[7], p[6], Vector3.forward);
            Quad(p[3], p[0], p[4], p[7], Vector3.left);
            Quad(p[4], p[5], p[6], p[7], Vector3.up);
            Quad(p[3], p[2], p[1], p[0], Vector3.down);
        }

        /// <summary>角錐台（底面 w0×d0 → 上面 w1×d1、高さ h）。底面中心が base。</summary>
        public void Frustum(Vector3 b, float w0, float d0, float w1, float d1, float h, bool top = true, bool bottom = false)
        {
            Vector3 c = b + Vector3.up * h * 0.5f;
            Vector3[] lo =
            {
                b + new Vector3(-w0 / 2, 0, -d0 / 2), b + new Vector3(w0 / 2, 0, -d0 / 2),
                b + new Vector3(w0 / 2, 0, d0 / 2), b + new Vector3(-w0 / 2, 0, d0 / 2)
            };
            Vector3 t = b + Vector3.up * h;
            Vector3[] hi =
            {
                t + new Vector3(-w1 / 2, 0, -d1 / 2), t + new Vector3(w1 / 2, 0, -d1 / 2),
                t + new Vector3(w1 / 2, 0, d1 / 2), t + new Vector3(-w1 / 2, 0, d1 / 2)
            };
            for (int i = 0; i < 4; i++)
            {
                int j = (i + 1) % 4;
                Vector3 mid = (lo[i] + lo[j] + hi[i] + hi[j]) * 0.25f;
                Quad(lo[i], lo[j], hi[j], hi[i], mid - c);
            }
            if (top) Quad(hi[0], hi[1], hi[2], hi[3], Vector3.up);
            if (bottom) Quad(lo[0], lo[1], lo[2], lo[3], Vector3.down);
        }

        /// <summary>円錐台（r0 → r1）。r1=0 で円錐、r0=r1 で円柱。</summary>
        public void Cone(Vector3 b, float r0, float r1, float h, int seg = 16, bool caps = true)
        {
            Vector3 top = b + Vector3.up * h;
            for (int i = 0; i < seg; i++)
            {
                float a0 = i * Mathf.PI * 2 / seg, a1 = (i + 1) * Mathf.PI * 2 / seg;
                Vector3 d0 = new Vector3(Mathf.Cos(a0), 0, Mathf.Sin(a0)), d1 = new Vector3(Mathf.Cos(a1), 0, Mathf.Sin(a1));
                Vector3 out0 = (d0 + d1) * 0.5f;
                if (r1 > 0.001f)
                    Quad(b + d0 * r0, b + d1 * r0, top + d1 * r1, top + d0 * r1, out0);
                else
                    Tri(b + d0 * r0, b + d1 * r0, top, out0 + Vector3.up * 0.3f);
                if (caps)
                {
                    Tri(b, b + d0 * r0, b + d1 * r0, Vector3.down);
                    if (r1 > 0.001f) Tri(top, top + d0 * r1, top + d1 * r1, Vector3.up);
                }
            }
        }

        /// <summary>
        /// 寄棟屋根（入母屋風の反り付き）。base は軒の高さの中心。
        /// w×d は軒先の外形（庇込み）、ridgeRatio は棟の長さ/幅、upturn は軒の反り上がり量。
        /// </summary>
        public void HipRoof(Vector3 b, float w, float d, float h, float ridgeRatio = 0.5f, float upturn = 0.4f, float thickness = 0.25f)
        {
            // 外周リング → 中間リング（反りの凹面）→ 棟
            float ex = w / 2, ez = d / 2;
            float rx = Mathf.Max(0.05f, (w - d) / 2 + d * ridgeRatio * 0.0f);
            rx = Mathf.Max(0.05f, ex * ridgeRatio);
            if (d > w) rx = Mathf.Max(0.05f, ex * ridgeRatio * (w / d));
            Vector3[] r0 =
            {
                b + new Vector3(-ex, upturn, -ez), b + new Vector3(ex, upturn, -ez),
                b + new Vector3(ex, upturn, ez), b + new Vector3(-ex, upturn, ez)
            };
            // 辺の中点は反りなし → 角を持ち上げた形を、外周を8点にして表現
            Vector3[] r0m =
            {
                b + new Vector3(0, 0, -ez), b + new Vector3(ex, 0, 0), b + new Vector3(0, 0, ez), b + new Vector3(-ex, 0, 0)
            };
            float t = 0.38f; // 中間リングの位置（外周から棟へ）
            float mh = h * 0.24f; // 凹面になるよう線形より低く
            float mx = Mathf.Lerp(ex, rx, t), mz = Mathf.Lerp(ez, 0f, t);
            Vector3[] r1 =
            {
                b + new Vector3(-mx, mh, -mz), b + new Vector3(mx, mh, -mz),
                b + new Vector3(mx, mh, mz), b + new Vector3(-mx, mh, mz)
            };
            Vector3[] r1m =
            {
                b + new Vector3(0, mh, -mz), b + new Vector3(mx, mh, 0), b + new Vector3(0, mh, mz), b + new Vector3(-mx, mh, 0)
            };
            Vector3 rA = b + new Vector3(-rx, h, 0), rB = b + new Vector3(rx, h, 0);
            Vector3[] r2 = { rA, rB, rB, rA };
            Vector3[] r2m = { b + new Vector3(0, h, 0), rB, b + new Vector3(0, h, 0), rA };
            Vector3 center = b + Vector3.up * (h * 0.3f);

            // 各辺 i（0:-z前, 1:+x右, 2:+z奥, 3:-x左）を角→中点→角の2枚ずつで張る
            for (int i = 0; i < 4; i++)
            {
                int j = (i + 1) % 4;
                Vector3 outDir = r0m[i] - b; outDir.y = 0; outDir = outDir.normalized + Vector3.up * 0.8f;
                // 外周帯
                QuadDouble(r0[i], r0m[i], r1m[i], r1[i], outDir);
                QuadDouble(r0m[i], r0[j], r1[j], r1m[i], outDir);
                // 上部帯
                QuadDouble(r1[i], r1m[i], r2m[i], r2[i], outDir);
                QuadDouble(r1m[i], r1[j], r2[j], r2m[i], outDir);
            }
            // 軒の厚み（鼻隠し）
            for (int i = 0; i < 4; i++)
            {
                int j = (i + 1) % 4;
                Vector3 outDir = r0m[i] - b; outDir.y = 0;
                Quad(r0[i], r0m[i], r0m[i] - Vector3.up * thickness, r0[i] - Vector3.up * thickness, outDir);
                Quad(r0m[i], r0[j], r0[j] - Vector3.up * thickness, r0m[i] - Vector3.up * thickness, outDir);
            }
            // 棟（大棟）
            Box((rA + rB) * 0.5f + Vector3.up * 0.15f, new Vector3(Mathf.Max(0.4f, rx * 2 + 0.4f), 0.5f, 0.6f));
        }

        /// <summary>切妻屋根。棟は x 方向。base は軒高さの中心。</summary>
        public void GableRoof(Vector3 b, float w, float d, float h, float thickness = 0.2f, bool closedEnds = true)
        {
            float ex = w / 2, ez = d / 2;
            Vector3 a0 = b + new Vector3(-ex, 0, -ez), a1 = b + new Vector3(ex, 0, -ez);
            Vector3 c0 = b + new Vector3(-ex, 0, ez), c1 = b + new Vector3(ex, 0, ez);
            Vector3 r0 = b + new Vector3(-ex, h, 0), r1 = b + new Vector3(ex, h, 0);
            QuadDouble(a0, a1, r1, r0, new Vector3(0, 1, -1));
            QuadDouble(c1, c0, r0, r1, new Vector3(0, 1, 1));
            Quad(a0, a1, a1 - Vector3.up * thickness, a0 - Vector3.up * thickness, Vector3.back);
            Quad(c0, c1, c1 - Vector3.up * thickness, c0 - Vector3.up * thickness, Vector3.forward);
            if (closedEnds)
            {
                float inset = Mathf.Min(0.6f, ex * 0.15f);
                Tri(a0 + Vector3.right * inset, c0 + Vector3.right * inset, r0 + Vector3.right * inset, Vector3.left);
                Tri(a1 - Vector3.right * inset, c1 - Vector3.right * inset, r1 - Vector3.right * inset, Vector3.right);
            }
            Box((r0 + r1) * 0.5f + Vector3.up * 0.1f, new Vector3(w + 0.2f, 0.3f, 0.4f));
        }

        public Mesh ToMesh(string name = "proc")
        {
            var m = new Mesh { name = name };
            if (verts.Count > 65000) m.indexFormat = IndexFormat.UInt32;
            m.SetVertices(verts);
            m.SetNormals(norms);
            m.SetUVs(0, uvs);
            m.SetTriangles(tris, 0);
            m.RecalculateBounds();
            m.RecalculateTangents();
            return m;
        }
    }

    public static class ProcMesh
    {
        static readonly Dictionary<string, Mesh> cache = new Dictionary<string, Mesh>();

        static Mesh Cached(string key, System.Func<Mesh> make)
        {
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            m = make();
            cache[key] = m;
            return m;
        }

        public static Mesh Box(Vector3 size, float uv = 2f) =>
            Cached($"box{size}{uv}", () => { var b = new MeshBuilder(uv); b.Box(Vector3.up * size.y * 0.5f, size); return b.ToMesh("box"); });

        public static Mesh Cylinder(float r, float h, int seg = 14, float uv = 2f) =>
            Cached($"cyl{r}{h}{seg}{uv}", () => { var b = new MeshBuilder(uv); b.Cone(Vector3.zero, r, r, h, seg); return b.ToMesh("cyl"); });

        public static Mesh Cone(float r, float h, int seg = 16, float uv = 2f) =>
            Cached($"cone{r}{h}{seg}{uv}", () => { var b = new MeshBuilder(uv); b.Cone(Vector3.zero, r, 0f, h, seg); return b.ToMesh("cone"); });

        public static Mesh FrustumCyl(float r0, float r1, float h, int seg = 24, float uv = 3f) =>
            Cached($"fcyl{r0}{r1}{h}{seg}{uv}", () => { var b = new MeshBuilder(uv); b.Cone(Vector3.zero, r0, r1, h, seg); return b.ToMesh("fcyl"); });

        public static Mesh Frustum(float w0, float d0, float w1, float d1, float h, float uv = 3f) =>
            Cached($"fr{w0}{d0}{w1}{d1}{h}{uv}", () => { var b = new MeshBuilder(uv); b.Frustum(Vector3.zero, w0, d0, w1, d1, h); return b.ToMesh("frustum"); });

        public static Mesh HipRoof(float w, float d, float h, float ridge = 0.5f, float upturn = 0.4f, float uv = 2f) =>
            Cached($"hip{w}{d}{h}{ridge}{upturn}{uv}", () => { var b = new MeshBuilder(uv); b.HipRoof(Vector3.zero, w, d, h, ridge, upturn); return b.ToMesh("hiproof"); });

        public static Mesh GableRoof(float w, float d, float h, float uv = 2f) =>
            Cached($"gab{w}{d}{h}{uv}", () => { var b = new MeshBuilder(uv); b.GableRoof(Vector3.zero, w, d, h); return b.ToMesh("gableroof"); });

        /// <summary>前方後円墳。後円部の中心が原点、前方部は +z 方向。length は全長。</summary>
        public static Mesh Kofun(float length, float height) =>
            Cached($"kofun{length}{height}", () =>
            {
                var b = new MeshBuilder(4f);
                float r = length * 0.3f;
                int tiers = 3;
                for (int i = 0; i < tiers; i++)
                {
                    float y = height * i / tiers, hh = height / tiers;
                    float rr0 = r * (1f - i * 0.22f), rr1 = r * (1f - (i + 1) * 0.22f + 0.06f);
                    b.Cone(Vector3.up * y, rr0, rr1, hh, 28, i == tiers - 1);
                    // 前方部（台形）: 後円部の中心から前へ伸びる
                    float fl = length - r;
                    float fw0 = r * 1.1f * (1f - i * 0.2f), fw1 = r * 1.9f * (1f - i * 0.2f);
                    float fh = hh * 0.92f;
                    float yb = y * 0.92f;
                    Vector3 c0 = new Vector3(0, yb, 0), c1 = new Vector3(0, yb, fl);
                    float s = 1f - 0.12f; // 上面の縮小
                    Vector3[] lo = { c0 + Vector3.left * fw0 / 2, c0 + Vector3.right * fw0 / 2, c1 + Vector3.right * fw1 / 2, c1 + Vector3.left * fw1 / 2 };
                    Vector3 up = Vector3.up * fh;
                    Vector3[] hi =
                    {
                        c0 + Vector3.left * fw0 / 2 * s + up, c0 + Vector3.right * fw0 / 2 * s + up,
                        c1 + Vector3.right * fw1 / 2 * s + up + Vector3.back * 2f, c1 + Vector3.left * fw1 / 2 * s + up + Vector3.back * 2f
                    };
                    Vector3 cen = (c0 + c1) * 0.5f + up * 0.5f;
                    for (int k = 0; k < 4; k++)
                    {
                        int j = (k + 1) % 4;
                        Vector3 mid = (lo[k] + lo[j] + hi[k] + hi[j]) * 0.25f;
                        b.Quad(lo[k], lo[j], hi[j], hi[k], mid - cen);
                    }
                    b.Quad(hi[0], hi[1], hi[2], hi[3], Vector3.up);
                }
                return b.ToMesh("kofun");
            });

        /// <summary>針葉樹（幹＋円錐3段）。submesh 0 = 幹, 1 = 葉。</summary>
        public static Mesh PineTree(float h) =>
            Cached($"pine{h}", () =>
            {
                var trunk = new MeshBuilder(1.5f);
                trunk.Cone(Vector3.zero, h * 0.035f, h * 0.02f, h * 0.45f, 7, false);
                var leaf = new MeshBuilder(2f);
                for (int i = 0; i < 3; i++)
                {
                    float y = h * (0.25f + i * 0.22f), rr = h * (0.3f - i * 0.075f);
                    leaf.Cone(Vector3.up * y, rr, 0f, h * (0.42f - i * 0.06f), 9, true);
                }
                return Combine2(trunk.ToMesh(), leaf.ToMesh(), "pine");
            });

        /// <summary>広葉樹（幹＋低ポリ球の塊）。submesh 0 = 幹, 1 = 葉。</summary>
        public static Mesh BroadleafTree(float h, int seed) =>
            Cached($"broad{h}{seed}", () =>
            {
                var rng = new System.Random(seed);
                var trunk = new MeshBuilder(1.5f);
                trunk.Cone(Vector3.zero, h * 0.05f, h * 0.03f, h * 0.55f, 7, false);
                var leaf = new MeshBuilder(2f);
                int blobs = 5;
                for (int i = 0; i < blobs; i++)
                {
                    float ang = (float)rng.NextDouble() * Mathf.PI * 2;
                    float dist = i == 0 ? 0 : h * 0.18f;
                    Vector3 c = new Vector3(Mathf.Cos(ang) * dist, h * (0.62f + (float)rng.NextDouble() * 0.18f), Mathf.Sin(ang) * dist);
                    float rr = h * (i == 0 ? 0.3f : 0.2f + (float)rng.NextDouble() * 0.06f);
                    Blob(leaf, c, rr, rng);
                }
                return Combine2(trunk.ToMesh(), leaf.ToMesh(), "broadleaf");
            });

        /// <summary>低ポリの「ゆがんだ二十面体」風の塊。</summary>
        public static void Blob(MeshBuilder b, Vector3 c, float r, System.Random rng)
        {
            int rings = 4, seg = 7;
            var pts = new Vector3[rings + 1, seg];
            for (int i = 0; i <= rings; i++)
            {
                float phi = Mathf.PI * i / rings;
                for (int j = 0; j < seg; j++)
                {
                    float th = Mathf.PI * 2 * j / seg + (i % 2) * 0.4f;
                    float jit = 1f + ((float)rng.NextDouble() - 0.5f) * 0.25f;
                    pts[i, j] = c + new Vector3(Mathf.Sin(phi) * Mathf.Cos(th), Mathf.Cos(phi) * 0.85f, Mathf.Sin(phi) * Mathf.Sin(th)) * r * jit;
                }
            }
            for (int i = 0; i < rings; i++)
                for (int j = 0; j < seg; j++)
                {
                    int k = (j + 1) % seg;
                    Vector3 mid = (pts[i, j] + pts[i + 1, k]) * 0.5f;
                    b.Quad(pts[i, j], pts[i, k], pts[i + 1, k], pts[i + 1, j], mid - c);
                }
        }

        public static Mesh Rock(int seed) =>
            Cached($"rock{seed}", () =>
            {
                var b = new MeshBuilder(1.5f);
                Blob(b, Vector3.up * 0.3f, 1f, new System.Random(seed));
                return b.ToMesh("rock");
            });

        public static Mesh Bush(int seed) =>
            Cached($"bush{seed}", () =>
            {
                var rng = new System.Random(seed);
                var b = new MeshBuilder(1f);
                for (int i = 0; i < 3; i++)
                    Blob(b, new Vector3(((float)rng.NextDouble() - 0.5f) * 1.2f, 0.5f, ((float)rng.NextDouble() - 0.5f) * 1.2f), 0.7f, rng);
                return b.ToMesh("bush");
            });

        static Mesh Combine2(Mesh a, Mesh b, string name)
        {
            var m = new Mesh { name = name };
            var ci = new[]
            {
                new CombineInstance { mesh = a, transform = Matrix4x4.identity },
                new CombineInstance { mesh = b, transform = Matrix4x4.identity }
            };
            m.CombineMeshes(ci, false, true);
            m.RecalculateBounds();
            SafeDestroy(a);
            SafeDestroy(b);
            return m;
        }

        public static void SafeDestroy(Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) Object.Destroy(o); else Object.DestroyImmediate(o);
        }
    }
}

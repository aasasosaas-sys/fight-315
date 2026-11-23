using UnityEngine;
using UnityEngine.Rendering;

namespace HistoryShift
{
    /// <summary>
    /// 時代ごとの建築物を手続き生成する。すべて (parent, pos, rotY, rng) を受け取り、ルート GameObject を返す。
    /// ルートのローカル座標で -z が「正面」。歩いて通り抜けられないよう BoxCollider をルートに付ける。
    /// </summary>
    public static class ArchitectureKit
    {
        // ---------- マテリアル ----------
        public static class M
        {
            public static Material Thatch => Mats.Get("thatch", new Color(0.88f, 0.8f, 0.62f), 1f, 0.05f);
            public static Material Bark => Mats.Get("thatch", new Color(0.55f, 0.38f, 0.27f), 1f, 0.05f);
            public static Material Wood => Mats.Get("wood", new Color(0.82f, 0.68f, 0.5f), 1f, 0.15f);
            public static Material PaleWood => Mats.Get("wood", new Color(0.95f, 0.88f, 0.75f), 1f, 0.15f);
            public static Material DarkWood => Mats.Get("darkwood", new Color(0.42f, 0.3f, 0.22f), 1f, 0.15f);
            public static Material Vermilion => Mats.Get("wood", new Color(0.9f, 0.26f, 0.13f), 1f, 0.35f);
            public static Material Plaster => Mats.Get("plaster", new Color(0.97f, 0.96f, 0.92f), 1f, 0.1f);
            public static Material Tile => Mats.Get("rooftile", new Color(0.58f, 0.6f, 0.65f), 1f, 0.35f);
            public static Material DarkTile => Mats.Get("rooftile", new Color(0.38f, 0.4f, 0.45f), 1f, 0.35f);
            public static Material Slate => Mats.Get("rooftile", new Color(0.32f, 0.34f, 0.38f), 1f, 0.4f);
            public static Material Stone => Mats.Get("stonewall", new Color(0.92f, 0.9f, 0.86f), 1f, 0.1f);
            public static Material Rock => Mats.Get("rock", new Color(0.82f, 0.82f, 0.8f), 1f, 0.1f);
            public static Material Brick => Mats.Get("brick", new Color(1f, 0.92f, 0.88f), 1f, 0.15f);
            public static Material Concrete => Mats.Get("concrete", new Color(0.86f, 0.86f, 0.83f), 1f, 0.15f);
            public static Material Earth => Mats.Get("dirt", new Color(0.8f, 0.7f, 0.6f), 1f, 0.05f);
            public static Material GrassM => Mats.Get("grass", new Color(0.85f, 0.95f, 0.75f), 1f, 0.05f);
            public static Material Tatami => Mats.Get("tatami", Color.white, 1f, 0.1f);
            public static Material Glass => Mats.Color(new Color(0.12f, 0.16f, 0.2f), 0.92f, 0.3f);
            public static Material Gold => Mats.Color(new Color(1f, 0.76f, 0.3f), 0.8f, 1f);
            public static Material Metal => Mats.Color(new Color(0.45f, 0.47f, 0.5f), 0.55f, 0.8f);
            public static Material BlackMetal => Mats.Color(new Color(0.08f, 0.08f, 0.09f), 0.4f, 0.6f);
            public static Material Paper => Mats.Color(new Color(0.97f, 0.95f, 0.87f), 0.1f);
            public static Material Lamp => Mats.Emissive(new Color(1f, 0.72f, 0.38f), 4f);
            public static Material Neon(Color c) => Mats.Emissive(c, 3f);
            public static Material Terracotta => Mats.Color(new Color(0.7f, 0.42f, 0.28f), 0.15f);
            public static Material Water => Mats.Transparent(new Color(0.12f, 0.28f, 0.32f, 0.82f), 0.95f);
            public static Material Paddy => Mats.Transparent(new Color(0.35f, 0.45f, 0.3f, 0.75f), 0.9f);
            public static Material Cloth(Color c) => Mats.Color(c, 0.05f);
            public static Material Asphalt => Mats.Get("asphalt", new Color(0.8f, 0.8f, 0.8f), 1f, 0.2f);
        }

        // ---------- 共通ヘルパー ----------
        public static float R(System.Random r, float a, float b) => a + (float)r.NextDouble() * (b - a);

        public static GameObject Root(Transform parent, string name, Vector3 pos, float rotY)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.position = pos;
            go.transform.rotation = Quaternion.Euler(0f, rotY, 0f);
            go.isStatic = true;
            return go;
        }

        public static GameObject Part(GameObject root, string name, Mesh mesh, Material mat, Vector3 local, Vector3 euler = default, bool shadows = true)
        {
            var go = new GameObject(name);
            go.transform.SetParent(root.transform, false);
            go.transform.localPosition = local;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            mr.shadowCastingMode = shadows ? ShadowCastingMode.On : ShadowCastingMode.Off;
            mr.receiveShadows = true;
            go.isStatic = true;
            return go;
        }

        public static GameObject PartMulti(GameObject root, string name, Mesh mesh, Material[] mats, Vector3 local, Vector3 euler = default)
        {
            var go = Part(root, name, mesh, mats[0], local, euler);
            go.GetComponent<MeshRenderer>().sharedMaterials = mats;
            return go;
        }

        /// <summary>底面中心 local の箱（見た目＋任意でコライダー）。</summary>
        public static GameObject Box(GameObject root, Vector3 local, Vector3 size, Material mat, bool collider = false, Vector3 euler = default, float uv = 2f)
        {
            var go = Part(root, "box", ProcMesh.Box(size, uv), mat, local, euler);
            if (collider) Col(root, local, size);
            return go;
        }

        public static GameObject Cyl(GameObject root, Vector3 local, float r, float h, Material mat, int seg = 12, Vector3 euler = default)
            => Part(root, "cyl", ProcMesh.Cylinder(r, h, seg), mat, local, euler);

        public static void Col(GameObject root, Vector3 localBottom, Vector3 size)
        {
            var bc = root.AddComponent<BoxCollider>();
            bc.center = localBottom + Vector3.up * size.y * 0.5f;
            bc.size = size;
        }

        public static GameObject Hip(GameObject root, Vector3 local, float w, float d, float h, Material mat, float ridge = 0.5f, float upturn = 0.4f)
            => Part(root, "roof", ProcMesh.HipRoof(w, d, h, ridge, upturn), mat, local);

        public static GameObject Gable(GameObject root, Vector3 local, float w, float d, float h, Material mat, float rotY = 0f)
            => Part(root, "roof", ProcMesh.GableRoof(w, d, h), mat, local, new Vector3(0, rotY, 0));

        // ---------- 縄文・弥生・古墳 ----------

        public static GameObject PitDwelling(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "竪穴住居", pos, rotY);
            float r = R(rng, 3.2f, 4.3f), h = r * R(rng, 1.05f, 1.25f);
            Part(g, "earth", ProcMesh.FrustumCyl(r + 0.5f, r + 0.15f, 0.5f, 18), M.Earth, Vector3.zero);
            Part(g, "roof", ProcMesh.Cone(r + 0.35f, h, 14), M.Thatch, new Vector3(0, 0.35f, 0));
            Part(g, "top", ProcMesh.Cone(0.7f, 0.9f, 8), M.Bark, new Vector3(0, 0.35f + h * 0.78f, 0));
            Gable(g, new Vector3(0, 0.3f, -r - 0.2f), 2.0f, 1.8f, 1.3f, M.Thatch, 90f);
            Col(g, Vector3.zero, new Vector3(r * 1.5f, 2.6f, r * 1.5f));
            return g;
        }

        public static GameObject RaisedGranary(Transform parent, Vector3 pos, float rotY, System.Random rng, float scale = 1f)
        {
            var g = Root(parent, "高床倉庫", pos, rotY);
            float w = 3.2f * scale, d = 2.6f * scale, ph = 1.8f * scale;
            foreach (var sx in new[] { -1, 1 })
                foreach (var sz in new[] { -1, 1 })
                {
                    var p = new Vector3(sx * w * 0.45f, 0, sz * d * 0.45f);
                    Cyl(g, p, 0.13f * scale, ph, M.DarkWood, 8);
                    Cyl(g, p + Vector3.up * ph * 0.7f, 0.38f * scale, 0.06f, M.DarkWood, 10); // ねずみ返し
                }
            if (scale > 1.5f)
                for (int i = -1; i <= 1; i += 2)
                    Cyl(g, new Vector3(0, 0, i * d * 0.45f), 0.13f * scale, ph, M.DarkWood, 8);
            Box(g, new Vector3(0, ph, 0), new Vector3(w + 0.4f, 0.2f, d + 0.4f), M.DarkWood);
            Box(g, new Vector3(0, ph + 0.2f, 0), new Vector3(w, 1.7f * scale, d), M.Wood);
            Gable(g, new Vector3(0, ph + 0.2f + 1.7f * scale, 0), w + 1.6f * scale, d + 1.8f * scale, 1.8f * scale, M.Thatch);
            Box(g, new Vector3(0, 0, -d * 0.5f - 0.9f * scale), new Vector3(0.5f, ph * 1.15f, 0.12f), M.Wood, false, new Vector3(-28, 0, 0));
            Col(g, Vector3.zero, new Vector3(w, ph + 2f * scale, d));
            return g;
        }

        public static GameObject Kofun(Transform parent, Vector3 pos, float rotY, System.Random rng, float length = 90f)
        {
            var g = Root(parent, "前方後円墳", pos, rotY);
            float h = length * 0.1f, r = length * 0.3f;
            var mound = Part(g, "mound", ProcMesh.Kofun(length, h), M.GrassM, Vector3.zero);
            var mc = mound.AddComponent<MeshCollider>();
            mc.sharedMesh = mound.GetComponent<MeshFilter>().sharedMesh;
            // 周濠
            float zc = (length - 2 * r) * 0.5f;
            Box(g, new Vector3(0, 0.04f, zc), new Vector3(r * 2.9f, 0.04f, length + 22f), M.Water, false, default, 6f)
                .GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
            // 埴輪
            for (int i = 0; i < 18; i++)
            {
                float a = i / 18f * Mathf.PI * 2f;
                if (Mathf.Sin(a) > 0.55f) continue;
                Cyl(g, new Vector3(Mathf.Cos(a) * r * 1.02f, 0.3f, Mathf.Sin(a) * r * 1.02f), 0.28f, 1.1f, M.Terracotta, 8);
            }
            return g;
        }

        public static GameObject Watchtower(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "物見櫓", pos, rotY);
            float s = 1.5f, ph = R(rng, 6f, 8f);
            foreach (var sx in new[] { -1, 1 })
                foreach (var sz in new[] { -1, 1 })
                    Cyl(g, new Vector3(sx * s, 0, sz * s), 0.18f, ph + 1.2f, M.DarkWood, 8);
            Box(g, new Vector3(0, ph, 0), new Vector3(s * 2 + 0.8f, 0.25f, s * 2 + 0.8f), M.Wood);
            Box(g, new Vector3(0, ph + 0.25f, -s - 0.35f), new Vector3(s * 2 + 0.8f, 0.9f, 0.1f), M.Wood);
            Box(g, new Vector3(0, ph + 0.25f, s + 0.35f), new Vector3(s * 2 + 0.8f, 0.9f, 0.1f), M.Wood);
            Hip(g, new Vector3(0, ph + 1.4f, 0), s * 2 + 2f, s * 2 + 2f, 1.6f, M.Thatch, 0.05f, 0.05f);
            Col(g, Vector3.zero, new Vector3(s * 2 + 0.4f, ph + 1f, s * 2 + 0.4f));
            return g;
        }

        /// <summary>先の尖った丸太の柵（環濠集落・山城）。a,b はワールド座標。</summary>
        public static GameObject Palisade(Transform parent, Vector3 a, Vector3 b, float height = 3f)
        {
            Vector3 d = b - a; d.y = 0; float L = d.magnitude;
            if (L < 0.5f) return null;
            var g = Root(parent, "柵", a, Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg - 90f);
            var mb = new MeshBuilder(1.2f);
            int n = Mathf.Max(2, Mathf.RoundToInt(L / 0.42f));
            var hr = new System.Random(Mathf.RoundToInt(a.x * 7 + a.z * 13));
            for (int i = 0; i < n; i++)
            {
                float x = L * i / (n - 1);
                float hh = height * R(hr, 0.85f, 1.1f);
                mb.Cone(new Vector3(x, -0.5f, 0), 0.19f, 0.19f, hh + 0.5f, 5, false);
                mb.Cone(new Vector3(x, hh, 0), 0.19f, 0f, 0.45f, 5, false);
            }
            mb.Box(new Vector3(L * 0.5f, height * 0.55f, 0.22f), new Vector3(L, 0.14f, 0.1f));
            Part(g, "posts", mb.ToMesh("palisade"), M.DarkWood, Vector3.zero);
            Col(g, new Vector3(L * 0.5f, 0, 0), new Vector3(L, height, 0.5f));
            return g;
        }

        /// <summary>低い木柵（馬防柵・田畑の柵）。</summary>
        public static GameObject Fence(Transform parent, Vector3 a, Vector3 b, float height = 1.6f, bool collider = true)
        {
            Vector3 d = b - a; d.y = 0; float L = d.magnitude;
            if (L < 0.5f) return null;
            var g = Root(parent, "柵", a, Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg - 90f);
            var mb = new MeshBuilder(1.5f);
            int n = Mathf.Max(2, Mathf.RoundToInt(L / 2.2f));
            for (int i = 0; i < n; i++)
                mb.Box(new Vector3(L * i / (n - 1), height * 0.5f - 0.3f, 0), new Vector3(0.16f, height + 0.6f, 0.16f));
            mb.Box(new Vector3(L * 0.5f, height * 0.8f, 0), new Vector3(L, 0.12f, 0.08f));
            mb.Box(new Vector3(L * 0.5f, height * 0.4f, 0), new Vector3(L, 0.12f, 0.08f));
            Part(g, "fence", mb.ToMesh("fence"), M.DarkWood, Vector3.zero);
            if (collider) Col(g, new Vector3(L * 0.5f, 0, 0), new Vector3(L, height, 0.4f));
            return g;
        }

        public static GameObject StoneCircle(Transform parent, Vector3 pos, System.Random rng, float radius = 9f)
        {
            var g = Root(parent, "環状列石", pos, 0f);
            int n = 22;
            for (int i = 0; i < n; i++)
            {
                float a = i * Mathf.PI * 2 / n;
                float s = R(rng, 0.5f, 1.0f);
                var p = Part(g, "stone", ProcMesh.Rock(i % 5), M.Rock, new Vector3(Mathf.Cos(a) * radius, 0, Mathf.Sin(a) * radius),
                    new Vector3(0, R(rng, 0, 360), 0));
                p.transform.localScale = new Vector3(s, s * R(rng, 0.8f, 2.2f), s);
            }
            var c = Part(g, "center", ProcMesh.Rock(7), M.Rock, Vector3.zero);
            c.transform.localScale = new Vector3(0.6f, 2.6f, 0.6f);
            return g;
        }

        // ---------- 飛鳥・奈良・平安 ----------

        /// <summary>宮殿・寺院の金堂（朱塗り柱＋瓦屋根）。doubleRoof で裳階付き。</summary>
        public static GameObject PalaceHall(Transform parent, Vector3 pos, float rotY, System.Random rng, float w = 24f, float d = 12f,
                                            bool vermilion = true, bool doubleRoof = false, Material roofMat = null)
        {
            var g = Root(parent, "殿舎", pos, rotY);
            roofMat = roofMat ?? M.Tile;
            var pillar = vermilion ? M.Vermilion : M.DarkWood;
            float baseH = 1.3f, colH = doubleRoof ? 8.5f : 5.5f;
            Part(g, "platform", ProcMesh.Frustum(w + 7f, d + 7f, w + 5.6f, d + 5.6f, baseH), M.Stone, Vector3.zero);
            Box(g, new Vector3(0, 0, -(d + 5.6f) / 2 - 1.2f), new Vector3(6f, baseH * 0.5f, 2.4f), M.Stone);
            Col(g, Vector3.zero, new Vector3(w + 6f, baseH, d + 6f));

            int nx = Mathf.Max(2, Mathf.RoundToInt(w / 4.5f)), nz = Mathf.Max(2, Mathf.RoundToInt(d / 4.5f));
            for (int i = 0; i <= nx; i++)
                for (int k = 0; k <= nz; k++)
                {
                    if (i != 0 && i != nx && k != 0 && k != nz) continue;
                    Cyl(g, new Vector3(-w / 2 + w * i / nx, baseH, -d / 2 + d * k / nz), 0.36f, colH, pillar, 12);
                }
            // 壁と扉
            Box(g, new Vector3(0, baseH, 0.3f), new Vector3(w - 1.2f, colH - 0.6f, d - 1.6f), M.Plaster, true);
            for (int i = 0; i < nx; i++)
            {
                float x = -w / 2 + w * (i + 0.5f) / nx;
                Box(g, new Vector3(x, baseH, -(d - 1.6f) / 2 + 0.25f), new Vector3(w / nx * 0.7f, colH * 0.72f, 0.12f), vermilion ? M.Vermilion : M.DarkWood);
                Box(g, new Vector3(x, baseH + colH * 0.72f + 0.3f, -(d - 1.6f) / 2 + 0.25f), new Vector3(w / nx * 0.75f, 0.9f, 0.1f), M.Paper);
            }
            // 梁
            float top = baseH + colH;
            Box(g, new Vector3(0, top - 0.6f, -d / 2), new Vector3(w + 0.8f, 0.6f, 0.5f), pillar);
            Box(g, new Vector3(0, top - 0.6f, d / 2), new Vector3(w + 0.8f, 0.6f, 0.5f), pillar);
            Box(g, new Vector3(-w / 2, top - 0.6f, 0), new Vector3(0.5f, 0.6f, d + 0.8f), pillar);
            Box(g, new Vector3(w / 2, top - 0.6f, 0), new Vector3(0.5f, 0.6f, d + 0.8f), pillar);
            Box(g, new Vector3(0, top, 0), new Vector3(w + 1.6f, 0.5f, d + 1.6f), M.DarkWood); // 組物
            if (doubleRoof)
                Hip(g, new Vector3(0, baseH + colH * 0.5f, 0), w + 3.6f, d + 3.6f, 1.3f, roofMat, 0.9f, 0.25f);
            float rh = d * 0.38f + 2f, rw = w + 6f;
            Hip(g, new Vector3(0, top + 0.5f, 0), rw, d + 6f, rh, roofMat, 0.6f, 0.7f);
            // 鴟尾
            float rx = rw / 2f * 0.6f;
            Box(g, new Vector3(-rx, top + 0.5f + rh, 0), new Vector3(0.6f, 1.6f, 0.9f), M.Gold, false, new Vector3(0, 0, 12));
            Box(g, new Vector3(rx, top + 0.5f + rh, 0), new Vector3(0.6f, 1.6f, 0.9f), M.Gold, false, new Vector3(0, 0, -12));
            return g;
        }

        public static GameObject Pagoda(Transform parent, Vector3 pos, float rotY, System.Random rng, int tiers = 5)
        {
            var g = Root(parent, tiers == 3 ? "三重塔" : "五重塔", pos, rotY);
            Part(g, "base", ProcMesh.Frustum(10f, 10f, 9f, 9f, 1.2f), M.Stone, Vector3.zero);
            Col(g, Vector3.zero, new Vector3(8f, 30f, 8f));
            float y = 1.2f;
            for (int i = 0; i < tiers; i++)
            {
                float s = 6.4f - i * 0.6f, th = i == 0 ? 3.8f : 2.6f;
                Box(g, new Vector3(0, y, 0), new Vector3(s, th, s), M.Vermilion);
                foreach (var face in new[] { 0f, 90f, 180f, 270f })
                {
                    var q = Quaternion.Euler(0, face, 0);
                    Box(g, new Vector3(0, y, 0) + q * new Vector3(0, 0.3f, -s / 2 - 0.02f), new Vector3(s * 0.45f, th - 0.8f, 0.06f), M.Plaster, false, new Vector3(0, face, 0));
                }
                Box(g, new Vector3(0, y + th, 0), new Vector3(s + 1f, 0.45f, s + 1f), M.DarkWood);
                float rs = s + 4.6f;
                Hip(g, new Vector3(0, y + th + 0.45f, 0), rs, rs, 1.5f, M.Tile, 0.02f, 0.55f);
                y += th + 1.35f;
            }
            Cyl(g, new Vector3(0, y, 0), 0.2f, 9f, M.Metal, 8);
            for (int i = 0; i < 9; i++) Cyl(g, new Vector3(0, y + 1.6f + i * 0.62f, 0), 0.55f - i * 0.02f, 0.14f, M.Metal, 12);
            Part(g, "hoju", ProcMesh.Cone(0.35f, 0.8f, 10), M.Gold, new Vector3(0, y + 9f, 0));
            return g;
        }

        public static GameObject Torii(Transform parent, Vector3 pos, float rotY, System.Random rng, float w = 5f, float h = 6f, Material mat = null)
        {
            var g = Root(parent, "鳥居", pos, rotY);
            mat = mat ?? M.Vermilion;
            foreach (var sx in new[] { -1, 1 })
            {
                Cyl(g, new Vector3(sx * w / 2, 0, 0), 0.3f, h, mat, 12);
                Cyl(g, new Vector3(sx * w / 2, 0, 0), 0.36f, 0.6f, M.BlackMetal, 12);
                Col(g, new Vector3(sx * w / 2, 0, 0), new Vector3(0.7f, h, 0.7f));
            }
            Box(g, new Vector3(0, h, 0), new Vector3(w + 2.2f, 0.42f, 0.62f), M.BlackMetal);
            Box(g, new Vector3(-(w + 2.2f) / 2 - 0.3f, h + 0.08f, 0), new Vector3(0.8f, 0.42f, 0.62f), M.BlackMetal, false, new Vector3(0, 0, -10));
            Box(g, new Vector3((w + 2.2f) / 2 + 0.3f, h + 0.08f, 0), new Vector3(0.8f, 0.42f, 0.62f), M.BlackMetal, false, new Vector3(0, 0, 10));
            Box(g, new Vector3(0, h - 0.38f, 0), new Vector3(w + 1.8f, 0.38f, 0.5f), mat);
            Box(g, new Vector3(0, h - 1.5f, 0), new Vector3(w + 0.9f, 0.32f, 0.32f), mat);
            Box(g, new Vector3(0, h - 1.2f, -0.05f), new Vector3(0.7f, 0.9f, 0.3f), M.BlackMetal);
            return g;
        }

        /// <summary>寝殿造の殿舎（檜皮葺き、高床、蔀戸）。</summary>
        public static GameObject ShindenHall(Transform parent, Vector3 pos, float rotY, System.Random rng, float w = 18f, float d = 12f)
        {
            var g = Root(parent, "寝殿", pos, rotY);
            float fh = 1.2f;
            for (int i = 0; i <= 5; i++)
                for (int k = 0; k <= 3; k++)
                    Cyl(g, new Vector3(-w / 2 + w * i / 5, 0, -d / 2 + d * k / 3), 0.2f, fh + 3.4f, M.DarkWood, 8);
            Box(g, new Vector3(0, fh, 0), new Vector3(w + 1.6f, 0.22f, d + 1.6f), M.Wood, true);
            Box(g, new Vector3(0, fh + 0.22f, 0), new Vector3(w - 2.4f, 3.1f, d - 2.4f), M.DarkWood, true);
            for (int i = 0; i < 5; i++)
                Box(g, new Vector3(-w / 2 + 1.2f + (w - 2.4f) * (i + 0.5f) / 5, fh + 1.6f, -(d - 2.4f) / 2 - 0.04f),
                    new Vector3((w - 2.4f) / 5 * 0.85f, 1.3f, 0.06f), M.Paper);
            // 高欄
            Box(g, new Vector3(0, fh + 0.9f, -(d + 1.6f) / 2), new Vector3(w + 1.6f, 0.12f, 0.12f), M.Vermilion);
            Box(g, new Vector3(0, fh + 0.9f, (d + 1.6f) / 2), new Vector3(w + 1.6f, 0.12f, 0.12f), M.Vermilion);
            Box(g, new Vector3(0, 0, -(d + 1.6f) / 2 - 1.4f), new Vector3(4f, 1.2f, 2.4f), M.Wood, false, new Vector3(-24, 0, 0));
            Hip(g, new Vector3(0, fh + 3.5f, 0), w + 4f, d + 4f, d * 0.32f + 1.5f, M.Bark, 0.62f, 0.25f);
            return g;
        }

        /// <summary>a→b の渡廊（回廊）。両側の柱と切妻屋根。</summary>
        public static GameObject Corridor(Transform parent, Vector3 a, Vector3 b, float width = 4f, Material pillar = null, Material roof = null)
        {
            Vector3 d = b - a; d.y = 0; float L = d.magnitude;
            if (L < 1f) return null;
            pillar = pillar ?? M.Vermilion; roof = roof ?? M.Tile;
            var g = Root(parent, "回廊", a, Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg - 90f);
            var mb = new MeshBuilder(2f);
            int n = Mathf.Max(2, Mathf.RoundToInt(L / 3.5f));
            for (int i = 0; i <= n; i++)
                foreach (var s in new[] { -1, 1 })
                    mb.Cone(new Vector3(L * i / n, 0, s * width / 2), 0.2f, 0.2f, 3.4f, 8, false);
            Part(g, "pillars", mb.ToMesh("corridor"), pillar, Vector3.zero);
            Box(g, new Vector3(L / 2, 0, 0), new Vector3(L, 0.25f, width + 0.6f), M.Stone);
            Box(g, new Vector3(L / 2, 3.2f, width / 2 + 0.05f), new Vector3(L, 0.35f, 0.3f), pillar);
            Box(g, new Vector3(L / 2, 3.2f, -width / 2 - 0.05f), new Vector3(L, 0.35f, 0.3f), pillar);
            Gable(g, new Vector3(L / 2, 3.5f, 0), L + 0.5f, width + 2.6f, 1.6f, roof);
            // 外側は連子窓の壁（片側のみ）
            Box(g, new Vector3(L / 2, 0.25f, width / 2), new Vector3(L, 3f, 0.25f), M.Plaster, true);
            return g;
        }

        /// <summary>築地塀（瓦屋根付きの土塀）。a,b はワールド座標。</summary>
        public static GameObject Wall(Transform parent, Vector3 a, Vector3 b, float height = 3.2f, bool stoneBase = false, Material body = null)
        {
            Vector3 d = b - a; d.y = 0; float L = d.magnitude;
            if (L < 0.5f) return null;
            body = body ?? M.Plaster;
            var g = Root(parent, "塀", (a + b) * 0.5f, Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg - 90f);
            float baseH = stoneBase ? 1.6f : 0.5f;
            Part(g, "base", ProcMesh.Frustum(L, stoneBase ? 2.4f : 1.5f, L, stoneBase ? 1.7f : 1.3f, baseH), M.Stone, new Vector3(0, -0.4f, 0));
            Box(g, new Vector3(0, baseH - 0.4f, 0), new Vector3(L, height, 1.1f), body, false, default, 3f);
            Box(g, new Vector3(0, baseH - 0.4f + height * 0.65f, 0), new Vector3(L + 0.02f, 0.18f, 1.14f), M.DarkWood);
            Gable(g, new Vector3(0, baseH - 0.4f + height, 0), L + 0.4f, 2.2f, 0.7f, M.DarkTile);
            Col(g, Vector3.zero, new Vector3(L, baseH + height, 1.6f));
            return g;
        }

        /// <summary>門（楼門／四脚門）。</summary>
        public static GameObject Gate(Transform parent, Vector3 pos, float rotY, System.Random rng, float w = 8f, bool vermilion = true, bool twoStory = false)
        {
            var g = Root(parent, "門", pos, rotY);
            var mat = vermilion ? M.Vermilion : M.DarkWood;
            float h = 5f;
            foreach (var sx in new[] { -1f, -0.33f, 0.33f, 1f })
                foreach (var sz in new[] { -1, 1 })
                    Cyl(g, new Vector3(sx * w / 2, 0, sz * 1.6f), 0.32f, h, mat, 10);
            Col(g, new Vector3(-w / 2, 0, 0), new Vector3(0.8f, h, 3.6f));
            Col(g, new Vector3(w / 2, 0, 0), new Vector3(0.8f, h, 3.6f));
            Box(g, new Vector3(0, h, 0), new Vector3(w + 1f, 0.6f, 4f), M.DarkWood);
            float y = h + 0.6f;
            if (twoStory)
            {
                Hip(g, new Vector3(0, y, 0), w + 4f, 7f, 1.2f, M.Tile, 0.9f, 0.4f);
                Box(g, new Vector3(0, y + 0.6f, 0), new Vector3(w - 0.6f, 3.4f, 3.2f), mat);
                y += 4f;
            }
            Hip(g, new Vector3(0, y, 0), w + 4.5f, 7.5f, 3f, M.Tile, 0.55f, 0.6f);
            return g;
        }

        public static GameObject GoldenPavilion(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "金閣", pos, rotY);
            Box(g, new Vector3(0, -0.3f, 0), new Vector3(36f, 0.05f, 30f), M.Water, false, default, 6f).GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
            Box(g, Vector3.zero, new Vector3(12f, 0.6f, 9f), M.Stone, true);
            Box(g, new Vector3(0, 0.6f, 0), new Vector3(10f, 3.2f, 7.5f), M.PaleWood, true);
            Box(g, new Vector3(0, 3.8f, 0), new Vector3(10.4f, 0.3f, 7.9f), M.DarkWood);
            Hip(g, new Vector3(0, 3.9f, 0), 13f, 10.5f, 0.9f, M.Bark, 0.85f, 0.2f);
            Box(g, new Vector3(0, 4.5f, 0), new Vector3(9.2f, 3f, 6.8f), M.Gold, true);
            Hip(g, new Vector3(0, 7.5f, 0), 12f, 9.5f, 0.9f, M.Bark, 0.85f, 0.2f);
            Box(g, new Vector3(0, 8.1f, 0), new Vector3(6f, 2.8f, 6f), M.Gold);
            Hip(g, new Vector3(0, 10.9f, 0), 9f, 9f, 2.6f, M.Bark, 0.02f, 0.45f);
            Box(g, new Vector3(0, 13.4f, 0), new Vector3(0.5f, 1.4f, 1.2f), M.Gold);
            return g;
        }

        // ---------- 中世〜近世 ----------

        public static GameObject Minka(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "民家", pos, rotY);
            float w = R(rng, 8f, 12f), d = R(rng, 6f, 8f);
            Box(g, Vector3.zero, new Vector3(w, 0.4f, d), M.Stone);
            Box(g, new Vector3(0, 0.4f, 0), new Vector3(w, 2.6f, d), M.Plaster, true);
            for (int i = 0; i <= 4; i++)
            {
                Box(g, new Vector3(-w / 2 + w * i / 4, 0.4f, -d / 2 - 0.05f), new Vector3(0.25f, 2.6f, 0.15f), M.DarkWood);
                Box(g, new Vector3(-w / 2 + w * i / 4, 0.4f, d / 2 + 0.05f), new Vector3(0.25f, 2.6f, 0.15f), M.DarkWood);
            }
            Box(g, new Vector3(-w * 0.15f, 0.4f, -d / 2 - 0.08f), new Vector3(w * 0.4f, 1.9f, 0.08f), M.DarkWood);
            Box(g, new Vector3(w * 0.25f, 1.2f, -d / 2 - 0.08f), new Vector3(w * 0.28f, 1.0f, 0.06f), M.Paper);
            Hip(g, new Vector3(0, 3f, 0), w + 3.2f, d + 3.2f, R(rng, 4.5f, 6f), M.Thatch, 0.5f, 0.05f);
            return g;
        }

        public static GameObject SamuraiResidence(Transform parent, Vector3 pos, float rotY, System.Random rng, float size = 32f, bool moat = false)
        {
            var g = Root(parent, "武士の館", pos, rotY);
            float h = size / 2;
            Box(g, new Vector3(0, 0, 3f), new Vector3(14f, 0.6f, 10f), M.Stone);
            Box(g, new Vector3(0, 0.6f, 3f), new Vector3(13f, 3.4f, 9f), M.PaleWood, true);
            Box(g, new Vector3(0, 1.4f, 3f - 4.55f), new Vector3(11f, 1.8f, 0.06f), M.Paper);
            Hip(g, new Vector3(0, 4f, 3f), 16.5f, 12.5f, 4.6f, M.Bark, 0.55f, 0.15f);
            Box(g, new Vector3(9f, 0, 9f), new Vector3(6f, 2.8f, 6f), M.Wood, true);
            Gable(g, new Vector3(9f, 2.8f, 9f), 7.4f, 7.4f, 2f, M.Thatch);
            var p = g.transform;
            Vector3 W(float x, float z) => g.transform.TransformPoint(new Vector3(x, 0, z));
            Fence(p, W(-h, -h), W(-4f, -h), 2.4f);
            Fence(p, W(4f, -h), W(h, -h), 2.4f);
            Fence(p, W(h, -h), W(h, h), 2.4f);
            Fence(p, W(h, h), W(-h, h), 2.4f);
            Fence(p, W(-h, h), W(-h, -h), 2.4f);
            // 門
            foreach (var sx in new[] { -1, 1 }) Cyl(g, new Vector3(sx * 4f, 0, -h), 0.25f, 4f, M.DarkWood, 8);
            Box(g, new Vector3(0, 4f, -h), new Vector3(9f, 0.4f, 0.5f), M.DarkWood);
            Gable(g, new Vector3(0, 4.4f, -h), 9.5f, 3f, 1.2f, M.Bark);
            var wt = Watchtower(p, W(h - 2f, -h + 2f), g.transform.eulerAngles.y, rng);
            if (moat)
            {
                float m = h + 4f;
                foreach (var (c, s) in new[] { (new Vector3(0, 0.05f, -m), new Vector3(2 * m + 6, 0.05f, 5)), (new Vector3(0, 0.05f, m), new Vector3(2 * m + 6, 0.05f, 5)),
                                               (new Vector3(-m, 0.05f, 0), new Vector3(5, 0.05f, 2 * m)), (new Vector3(m, 0.05f, 0), new Vector3(5, 0.05f, 2 * m)) })
                    Box(g, c, s, M.Water, false, default, 6f).GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
            }
            return g;
        }

        /// <summary>天守（石垣＋白漆喰の層塔＋瓦屋根＋千鳥破風＋金の鯱）。</summary>
        public static GameObject JapaneseCastle(Transform parent, Vector3 pos, float rotY, System.Random rng, int tiers = 5, bool blackWalls = false)
        {
            var g = Root(parent, "天守", pos, rotY);
            float bw = 30f, bd = 26f, bh = 11f;
            Part(g, "ishigaki", ProcMesh.Frustum(bw, bd, bw - 6f, bd - 6f, bh, 4f), M.Stone, Vector3.zero);
            Col(g, Vector3.zero, new Vector3(bw - 3f, bh, bd - 3f));
            Box(g, new Vector3(0, 0, -bd / 2 - 3f), new Vector3(6f, bh * 0.35f, 6f), M.Stone, false, new Vector3(-30, 0, 0));
            var body = blackWalls ? M.DarkWood : M.Plaster;
            float y = bh;
            float w = bw - 8f, d = bd - 8f;
            for (int i = 0; i < tiers; i++)
            {
                bool last = i == tiers - 1;
                float th = i == 0 ? 5.5f : 3.8f;
                Box(g, new Vector3(0, y, 0), new Vector3(w, th, d), body, true);
                Box(g, new Vector3(0, y, 0), new Vector3(w + 0.06f, 1.1f, d + 0.06f), M.DarkWood);
                int nw = Mathf.Max(2, Mathf.RoundToInt(w / 3.2f));
                for (int k = 0; k < nw; k++)
                {
                    float x = -w / 2 + w * (k + 0.5f) / nw;
                    Box(g, new Vector3(x, y + th * 0.45f, -d / 2 - 0.04f), new Vector3(1.0f, 1.0f, 0.08f), M.BlackMetal);
                    Box(g, new Vector3(x, y + th * 0.45f, d / 2 + 0.04f), new Vector3(1.0f, 1.0f, 0.08f), M.BlackMetal);
                }
                float rh = last ? 4.8f : 2.4f;
                Hip(g, new Vector3(0, y + th, 0), w + 4f, d + 4f, rh, M.DarkTile, last ? 0.45f : 0.82f, 0.75f);
                if (!last && i % 2 == 1)
                    foreach (var sz in new[] { -1, 1 })
                        Gable(g, new Vector3(0, y + th + 0.2f, sz * (d / 2 + 0.9f)), 4.5f, 3f, 2.2f, M.DarkTile, 90f);
                if (last)
                {
                    float rx = (w + 4f) / 2 * 0.45f;
                    Box(g, new Vector3(-rx, y + th + rh, 0), new Vector3(0.5f, 1.4f, 0.8f), M.Gold, false, new Vector3(0, 0, 15));
                    Box(g, new Vector3(rx, y + th + rh, 0), new Vector3(0.5f, 1.4f, 0.8f), M.Gold, false, new Vector3(0, 0, -15));
                }
                y += th + (last ? 0 : 1.6f);
                w *= 0.8f; d *= 0.8f;
            }
            return g;
        }

        /// <summary>町家の並び（-z が通り側）。farm=true で茅葺きの農家風。</summary>
        public static GameObject MachiyaRow(Transform parent, Vector3 pos, float rotY, System.Random rng, int count = 5, bool twoStory = true)
        {
            var g = Root(parent, "町家", pos, rotY);
            float hw = 6.6f, dd = 10f;
            float start = -(count - 1) * hw * 0.5f;
            for (int i = 0; i < count; i++)
            {
                float x = start + i * hw;
                float w = hw - 0.15f;
                Box(g, new Vector3(x, 0, 0), new Vector3(w, 3.0f, dd), M.DarkWood, false);
                Box(g, new Vector3(x, 0.25f, -dd / 2 - 0.06f), new Vector3(w * 0.85f, 2.3f, 0.12f), M.Wood);
                Box(g, new Vector3(x + w * 0.3f, 1.6f, -dd / 2 - 0.12f), new Vector3(1.4f, 1.2f, 0.04f),
                    M.Cloth(i % 3 == 0 ? new Color(0.15f, 0.2f, 0.45f) : i % 3 == 1 ? new Color(0.55f, 0.15f, 0.12f) : new Color(0.75f, 0.7f, 0.55f)));
                Box(g, new Vector3(x, 2.9f, -dd / 2 - 0.6f), new Vector3(w + 0.1f, 0.12f, 1.6f), M.DarkTile, false, new Vector3(16, 0, 0));
                float topY = 3f;
                if (twoStory)
                {
                    Box(g, new Vector3(x, 3f, 0.3f), new Vector3(w, 2.4f, dd - 0.6f), M.Plaster);
                    Box(g, new Vector3(x, 3.6f, -(dd - 0.6f) / 2 + 0.25f), new Vector3(w * 0.6f, 1.0f, 0.08f), M.DarkWood);
                    topY = 5.4f;
                }
                Gable(g, new Vector3(x, topY, 0), w + 0.4f, dd + 1.6f, R(rng, 2.0f, 2.6f), M.DarkTile);
            }
            Col(g, Vector3.zero, new Vector3(count * hw, 5f, dd));
            return g;
        }

        public static GameObject Kura(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "土蔵", pos, rotY);
            float w = R(rng, 4.5f, 6f), d = R(rng, 6f, 8f), h = 5.2f;
            Box(g, Vector3.zero, new Vector3(w + 0.4f, 0.7f, d + 0.4f), M.Stone);
            Box(g, new Vector3(0, 0.7f, 0), new Vector3(w, h, d), M.Plaster, true);
            Box(g, new Vector3(0, 0.7f, 0), new Vector3(w + 0.05f, 1.4f, d + 0.05f), M.DarkWood);
            Box(g, new Vector3(0, 0.7f, -d / 2 - 0.1f), new Vector3(1.6f, 2.4f, 0.2f), M.DarkWood);
            Gable(g, new Vector3(0, 0.7f + h, 0), d + 1.2f, w + 1.2f, 2f, M.DarkTile, 90f);
            return g;
        }

        public static GameObject StoneLantern(Transform parent, Vector3 pos, float rotY)
        {
            var g = Root(parent, "石灯籠", pos, rotY);
            Cyl(g, Vector3.zero, 0.5f, 0.3f, M.Rock, 8);
            Cyl(g, new Vector3(0, 0.3f, 0), 0.16f, 1.1f, M.Rock, 8);
            Box(g, new Vector3(0, 1.4f, 0), new Vector3(0.85f, 0.2f, 0.85f), M.Rock);
            Box(g, new Vector3(0, 1.6f, 0), new Vector3(0.55f, 0.5f, 0.55f), M.Lamp);
            Hip(g, new Vector3(0, 2.1f, 0), 1.3f, 1.3f, 0.45f, M.Rock, 0.02f, 0.12f);
            Part(g, "finial", ProcMesh.Cone(0.14f, 0.35f, 8), M.Rock, new Vector3(0, 2.55f, 0));
            Col(g, Vector3.zero, new Vector3(0.9f, 2.5f, 0.9f));
            return g;
        }

        public static GameObject Shrine(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "神社", pos, rotY);
            float w = 6f, d = 5f, fh = 1.1f;
            foreach (var sx in new[] { -1, 0, 1 })
                foreach (var sz in new[] { -1, 1 })
                    Cyl(g, new Vector3(sx * w / 2, 0, sz * d / 2), 0.2f, fh + 3f, M.PaleWood, 8);
            Box(g, new Vector3(0, fh, 0), new Vector3(w + 1.4f, 0.2f, d + 1.4f), M.PaleWood, true);
            Box(g, new Vector3(0, fh + 0.2f, 0), new Vector3(w - 0.4f, 2.8f, d - 0.4f), M.PaleWood, true);
            Box(g, new Vector3(0, 0, -d / 2 - 1.3f), new Vector3(2.2f, fh, 2.0f), M.PaleWood, false, new Vector3(-28, 0, 0));
            float ry = fh + 3f;
            Gable(g, new Vector3(0, ry, 0), w + 2f, d + 2.4f, 2.4f, M.Bark);
            foreach (var sx in new[] { -1, 1 })
                foreach (var tilt in new[] { -35f, 35f })
                    Box(g, new Vector3(sx * (w / 2 + 0.9f), ry + 1.9f, 0), new Vector3(0.12f, 2.2f, 0.35f), M.PaleWood, false, new Vector3(tilt, 0, 0));
            for (int i = 0; i < 5; i++)
                Cyl(g, new Vector3(-w * 0.35f + i * w * 0.175f, ry + 2.6f, -0.7f), 0.22f, 1.4f, M.Gold, 8, new Vector3(90, 0, 0));
            var p = g.transform;
            Torii(p, g.transform.TransformPoint(new Vector3(0, 0, -14f)), rotY, rng, 4.5f, 5.2f);
            StoneLantern(p, g.transform.TransformPoint(new Vector3(-3f, 0, -8f)), rotY);
            StoneLantern(p, g.transform.TransformPoint(new Vector3(3f, 0, -8f)), rotY);
            return g;
        }

        // ---------- 近代 ----------

        static void FacadeWindows(GameObject g, float w, float d, int floors, float floorH, float baseY, float spacing,
                                  Material frameMat, bool sides = true, float winW = 1.2f, float winH = 2.0f)
        {
            var glass = new MeshBuilder(2f);
            var frame = new MeshBuilder(1f);
            int n = Mathf.Max(1, Mathf.FloorToInt(w / spacing));
            int nd = Mathf.Max(1, Mathf.FloorToInt(d / spacing));
            for (int f = 0; f < floors; f++)
            {
                float y = baseY + f * floorH + floorH * 0.5f;
                for (int i = 0; i < n; i++)
                {
                    float x = -w / 2 + w * (i + 0.5f) / n;
                    foreach (var sz in new[] { -1, 1 })
                    {
                        glass.Box(new Vector3(x, y, sz * (d / 2 + 0.03f)), new Vector3(winW, winH, 0.08f));
                        frame.Box(new Vector3(x, y - winH / 2 - 0.1f, sz * (d / 2 + 0.08f)), new Vector3(winW + 0.4f, 0.18f, 0.16f));
                        frame.Box(new Vector3(x, y + winH / 2 + 0.12f, sz * (d / 2 + 0.06f)), new Vector3(winW + 0.3f, 0.22f, 0.12f));
                    }
                }
                if (sides)
                    for (int i = 0; i < nd; i++)
                    {
                        float z = -d / 2 + d * (i + 0.5f) / nd;
                        foreach (var sx in new[] { -1, 1 })
                            glass.Box(new Vector3(sx * (w / 2 + 0.03f), y, z), new Vector3(0.08f, winH, winW));
                    }
            }
            Part(g, "glass", glass.ToMesh("windows"), M.Glass, Vector3.zero);
            Part(g, "frames", frame.ToMesh("frames"), frameMat, Vector3.zero);
        }

        /// <summary>明治の煉瓦造（時計塔付き）。concrete=true で議事堂風の石造。</summary>
        public static GameObject BrickBuilding(Transform parent, Vector3 pos, float rotY, System.Random rng, bool clockTower = true, bool concrete = false)
        {
            var g = Root(parent, concrete ? "官庁" : "煉瓦館", pos, rotY);
            var wall = concrete ? M.Concrete : M.Brick;
            float w = R(rng, 26f, 36f), d = R(rng, 13f, 16f), fh = 4.4f;
            int floors = rng.Next(2, 4);
            float h = floors * fh;
            Box(g, Vector3.zero, new Vector3(w + 0.6f, 0.8f, d + 0.6f), M.Stone);
            Box(g, new Vector3(0, 0.8f, 0), new Vector3(w, h, d), wall, true, default, 3f);
            for (int f = 1; f <= floors; f++)
                Box(g, new Vector3(0, 0.8f + f * fh - 0.2f, 0), new Vector3(w + 0.25f, 0.35f, d + 0.25f), M.Plaster);
            FacadeWindows(g, w, d, floors, fh, 0.8f, 3.4f, M.Plaster);
            Hip(g, new Vector3(0, 0.8f + h + 0.15f, 0), w + 1.2f, d + 1.2f, 3.2f, M.Slate, 0.72f, 0f);
            // 玄関ポーチ
            Box(g, new Vector3(0, 0.8f, -d / 2 - 2.5f), new Vector3(8f, 0.4f, 5f), M.Stone);
            foreach (var x in new[] { -3.4f, -1.2f, 1.2f, 3.4f })
                Cyl(g, new Vector3(x, 1.2f, -d / 2 - 4.5f), 0.35f, 4.2f, M.Plaster, 12);
            Box(g, new Vector3(0, 5.4f, -d / 2 - 2.5f), new Vector3(8.4f, 0.8f, 5.2f), M.Plaster);
            if (clockTower)
            {
                float th = h + 8f;
                Box(g, new Vector3(0, 0.8f, 0), new Vector3(6.5f, th, 6.5f), wall, true, default, 3f);
                Box(g, new Vector3(0, 0.8f + th - 0.3f, 0), new Vector3(7f, 0.6f, 7f), M.Plaster);
                Cyl(g, new Vector3(0, 0.8f + th - 3.2f, -3.3f), 1.5f, 0.2f, M.Paper, 20, new Vector3(-90, 0, 0));
                Box(g, new Vector3(0, 0.8f + th - 3.2f, -3.55f), new Vector3(0.12f, 1.1f, 0.05f), M.BlackMetal);
                Box(g, new Vector3(0.35f, 0.8f + th - 3.2f, -3.55f), new Vector3(0.8f, 0.1f, 0.05f), M.BlackMetal);
                if (concrete)
                {
                    Part(g, "spire", ProcMesh.Frustum(6.5f, 6.5f, 1.5f, 1.5f, 9f), M.Concrete, new Vector3(0, 0.8f + th, 0));
                    Box(g, new Vector3(0, 0.8f + th + 9f, 0), new Vector3(1.8f, 1.2f, 1.8f), M.Concrete);
                }
                else
                {
                    Hip(g, new Vector3(0, 0.8f + th, 0), 7.5f, 7.5f, 5.5f, M.Slate, 0.02f, 0f);
                    Cyl(g, new Vector3(0, 0.8f + th + 5.3f, 0), 0.08f, 3f, M.Metal, 6);
                }
            }
            return g;
        }

        public static GameObject WoodenSchool(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "木造校舎", pos, rotY);
            float w = R(rng, 36f, 48f), d = 10f, fh = 3.8f;
            var wall = Mats.Get("wood", new Color(0.86f, 0.83f, 0.76f), 1f, 0.15f);
            Box(g, Vector3.zero, new Vector3(w + 0.4f, 0.5f, d + 0.4f), M.Concrete);
            Box(g, new Vector3(0, 0.5f, 0), new Vector3(w, fh * 2, d), wall, true);
            FacadeWindows(g, w, d, 2, fh, 0.5f, 2.6f, M.PaleWood, false, 1.8f, 1.9f);
            Gable(g, new Vector3(0, 0.5f + fh * 2, 0), w + 1.2f, d + 2f, 3f, M.Tile);
            Box(g, new Vector3(0, 0.5f, -d / 2 - 1.8f), new Vector3(5f, 3.2f, 3.6f), wall);
            Gable(g, new Vector3(0, 3.7f, -d / 2 - 1.8f), 4.4f, 5.6f, 1.6f, M.Tile, 90f);
            return g;
        }

        public static GameObject ShowaBuilding(Transform parent, Vector3 pos, float rotY, System.Random rng, bool apartment = false)
        {
            var g = Root(parent, apartment ? "団地" : "ビル", pos, rotY);
            float w = apartment ? R(rng, 36f, 50f) : R(rng, 16f, 26f), d = apartment ? 11f : R(rng, 12f, 18f), fh = 3.2f;
            int floors = apartment ? rng.Next(4, 6) : rng.Next(3, 8);
            float h = floors * fh;
            Box(g, Vector3.zero, new Vector3(w, h + 0.6f, d), M.Concrete, true, default, 3f);
            var glass = new MeshBuilder(2f);
            for (int f = 0; f < floors; f++)
            {
                float y = f * fh + 1.0f;
                if (apartment)
                {
                    int n = Mathf.FloorToInt(w / 3.4f);
                    for (int i = 0; i < n; i++)
                        glass.Box(new Vector3(-w / 2 + w * (i + 0.5f) / n, y + 0.6f, -d / 2 - 0.03f), new Vector3(2.2f, 1.6f, 0.06f));
                    if (f > 0)
                    {
                        Box(g, new Vector3(0, f * fh, -d / 2 - 0.65f), new Vector3(w, 0.16f, 1.3f), M.Concrete);
                        Box(g, new Vector3(0, f * fh + 0.16f, -d / 2 - 1.28f), new Vector3(w, 1.0f, 0.08f), M.Concrete);
                    }
                }
                else
                {
                    glass.Box(new Vector3(0, y + 0.65f, 0), new Vector3(w + 0.06f, 1.3f, d + 0.06f));
                }
            }
            Part(g, "glass", glass.ToMesh("bands"), M.Glass, Vector3.zero);
            Box(g, new Vector3(0, h + 0.6f, 0), new Vector3(w + 0.1f, 0.9f, d + 0.1f), M.Concrete);
            Cyl(g, new Vector3(w * 0.3f, h + 0.6f, d * 0.15f), 1.3f, 2.6f, M.Metal, 12);
            if (!apartment)
            {
                Color[] neon = { new Color(1f, 0.25f, 0.3f), new Color(0.3f, 0.8f, 1f), new Color(1f, 0.8f, 0.2f), new Color(0.4f, 1f, 0.5f) };
                Box(g, new Vector3(w / 2 + 0.2f, h * 0.35f, -d / 2 + 1.2f), new Vector3(0.3f, h * 0.5f, 1.4f), M.Neon(neon[rng.Next(neon.Length)]));
            }
            return g;
        }

        /// <summary>電柱と電線（LineRenderer のたるみ付き）。points はワールド座標（地面高さ）。</summary>
        public static GameObject UtilityLine(Transform parent, Vector3[] points, bool wooden = false)
        {
            if (points == null || points.Length < 2) return null;
            var g = new GameObject("電線");
            g.transform.SetParent(parent, false);
            var mat = wooden ? M.DarkWood : M.Concrete;
            float ph = 9f;
            var tops = new Vector3[points.Length];
            for (int i = 0; i < points.Length; i++)
            {
                var pole = Root(g.transform, "電柱", points[i], 0f);
                Cyl(pole, Vector3.zero, 0.16f, ph, mat, 8);
                Vector3 dir = (i < points.Length - 1 ? points[i + 1] - points[i] : points[i] - points[i - 1]);
                dir.y = 0;
                float yaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
                Box(pole, new Vector3(0, ph - 0.7f, 0), new Vector3(2.2f, 0.15f, 0.15f), M.DarkWood, false, new Vector3(0, yaw, 0));
                Col(pole, Vector3.zero, new Vector3(0.4f, ph, 0.4f));
                tops[i] = points[i] + Vector3.up * (ph - 0.55f);
            }
            var wireMat = Mats.Color(new Color(0.05f, 0.05f, 0.05f), 0.2f);
            for (int wi = -1; wi <= 1; wi++)
            {
                var lgo = new GameObject("wire");
                lgo.transform.SetParent(g.transform, false);
                var lr = lgo.AddComponent<LineRenderer>();
                lr.sharedMaterial = wireMat;
                lr.widthMultiplier = 0.04f;
                lr.shadowCastingMode = ShadowCastingMode.Off;
                lr.useWorldSpace = true;
                var pts = new System.Collections.Generic.List<Vector3>();
                for (int i = 0; i < tops.Length - 1; i++)
                {
                    Vector3 a = tops[i], b = tops[i + 1];
                    Vector3 side = Vector3.Cross(Vector3.up, (b - a).normalized) * wi * 0.95f;
                    for (int s = 0; s < 10; s++)
                    {
                        float t = s / 10f;
                        pts.Add(Vector3.Lerp(a, b, t) + side - Vector3.up * (Mathf.Sin(t * Mathf.PI) * 0.9f));
                    }
                }
                pts.Add(tops[tops.Length - 1] + Vector3.Cross(Vector3.up, (tops[tops.Length - 1] - tops[tops.Length - 2]).normalized) * wi * 0.95f);
                lr.positionCount = pts.Count;
                lr.SetPositions(pts.ToArray());
            }
            return g;
        }

        public static GameObject GasLamp(Transform parent, Vector3 pos)
        {
            var model = ModelLibrary.TryInstantiate("street_lamp_01", parent, pos, 0f);
            if (model != null) return model;
            var g = Root(parent, "ガス灯", pos, 0f);
            Cyl(g, Vector3.zero, 0.22f, 0.6f, M.BlackMetal, 8);
            Cyl(g, new Vector3(0, 0.6f, 0), 0.08f, 3.4f, M.BlackMetal, 8);
            Box(g, new Vector3(0, 4.0f, 0), new Vector3(0.5f, 0.6f, 0.5f), M.Lamp);
            Part(g, "cap", ProcMesh.Cone(0.45f, 0.4f, 8), M.BlackMetal, new Vector3(0, 4.6f, 0));
            Col(g, Vector3.zero, new Vector3(0.4f, 4.6f, 0.4f));
            return g;
        }

        public static GameObject Hangar(Transform parent, Vector3 pos, float rotY, System.Random rng)
        {
            var g = Root(parent, "格納庫", pos, rotY);
            Box(g, new Vector3(-17f, 0, 0), new Vector3(2f, 10f, 30f), M.Metal, true);
            Box(g, new Vector3(17f, 0, 0), new Vector3(2f, 10f, 30f), M.Metal, true);
            Box(g, new Vector3(0, 0, 14f), new Vector3(36f, 10f, 2f), M.Metal, true);
            Gable(g, new Vector3(0, 10f, 0), 32f, 38f, 3.5f, M.Metal, 90f);
            var t = Root(g.transform, "管制塔", g.transform.TransformPoint(new Vector3(30f, 0, 0)), rotY);
            Box(t, Vector3.zero, new Vector3(4f, 12f, 4f), M.Concrete, true);
            Box(t, new Vector3(0, 12f, 0), new Vector3(5.5f, 2.6f, 5.5f), M.Glass);
            Box(t, new Vector3(0, 14.6f, 0), new Vector3(6f, 0.4f, 6f), M.Concrete);
            return g;
        }

        // ---------- 水辺 ----------

        /// <summary>桟橋。原点から +z 方向へ length 伸びる。deckY は原点からの床の高さ。</summary>
        public static GameObject Pier(Transform parent, Vector3 pos, float rotY, float length, float deckY, float width = 3.5f)
        {
            var g = Root(parent, "桟橋", pos, rotY);
            var mb = new MeshBuilder(1.5f);
            int n = Mathf.Max(2, Mathf.RoundToInt(length / 4f));
            for (int i = 0; i <= n; i++)
                foreach (var s in new[] { -1, 1 })
                    mb.Cone(new Vector3(s * width * 0.45f, deckY - 6f, length * i / n), 0.2f, 0.2f, 6.6f, 6, false);
            Part(g, "piles", mb.ToMesh("piles"), M.DarkWood, Vector3.zero);
            Box(g, new Vector3(0, deckY, length / 2), new Vector3(width, 0.3f, length), M.Wood, true);
            return g;
        }

        /// <summary>船。style 0=小舟 1=遣唐使船/和船 2=蒸気船 3=南蛮船(帆船)。+z が船首。</summary>
        public static GameObject Boat(Transform parent, Vector3 pos, float rotY, int style, System.Random rng)
        {
            if (style == 3)
            {
                var m = ModelLibrary.TryInstantiate("dutch_ship_medium", parent, pos + Vector3.down * 0.6f, rotY);
                if (m != null) return m;
            }
            var g = Root(parent, "船", pos, rotY);
            g.isStatic = false;
            switch (style)
            {
                case 0:
                    Part(g, "hull", ProcMesh.Frustum(1.2f, 5f, 1.8f, 6f, 0.8f), M.Wood, new Vector3(0, -0.3f, 0));
                    Col(g, new Vector3(0, -0.3f, 0), new Vector3(1.6f, 0.8f, 5.6f));
                    break;
                case 1:
                    Part(g, "hull", ProcMesh.Frustum(3.6f, 16f, 5.4f, 22f, 2.6f), M.DarkWood, new Vector3(0, -1.2f, 0));
                    Box(g, new Vector3(0, 1.4f, -5f), new Vector3(4f, 2f, 5f), M.Vermilion);
                    Gable(g, new Vector3(0, 3.4f, -5f), 4.6f, 5.6f, 1.2f, M.Bark, 90f);
                    foreach (var z in new[] { 1f, 6f })
                    {
                        Cyl(g, new Vector3(0, 1.4f, z), 0.2f, 12f, M.DarkWood, 8);
                        Box(g, new Vector3(0, 4.5f, z + 0.3f), new Vector3(7f, 7f, 0.12f), Mats.Get("bamboo", new Color(0.9f, 0.8f, 0.6f)));
                    }
                    Col(g, new Vector3(0, -1.2f, 0), new Vector3(5f, 3.5f, 20f));
                    break;
                case 2:
                    Part(g, "hull", ProcMesh.Frustum(5f, 30f, 7f, 36f, 4.5f), M.BlackMetal, new Vector3(0, -2.2f, 0));
                    Box(g, new Vector3(0, 2.3f, -3f), new Vector3(5.6f, 3f, 12f), M.Plaster);
                    Box(g, new Vector3(0, 5.3f, -6f), new Vector3(4.5f, 2f, 4f), M.Plaster);
                    Cyl(g, new Vector3(0, 5.3f, 1f), 1.1f, 6f, M.BlackMetal, 14);
                    Cyl(g, new Vector3(0, 10.3f, 1f), 1.12f, 1f, M.Vermilion, 14);
                    Cyl(g, new Vector3(0, 2.3f, 9f), 0.16f, 12f, M.DarkWood, 6);
                    Col(g, new Vector3(0, -2.2f, 0), new Vector3(6.5f, 7f, 34f));
                    break;
                default:
                    Part(g, "hull", ProcMesh.Frustum(4.5f, 22f, 7f, 30f, 4.5f), M.DarkWood, new Vector3(0, -2f, 0));
                    Box(g, new Vector3(0, 2.5f, -11f), new Vector3(6.6f, 3.5f, 6f), M.DarkWood);
                    foreach (var (z, hgt) in new[] { (-4f, 16f), (4f, 20f), (11f, 14f) })
                    {
                        Cyl(g, new Vector3(0, 2.5f, z), 0.25f, hgt, M.DarkWood, 8);
                        Box(g, new Vector3(0, 2.5f + hgt * 0.35f, z), new Vector3(9f, hgt * 0.35f, 0.1f), M.Paper);
                        Box(g, new Vector3(0, 2.5f + hgt * 0.75f, z), new Vector3(6.5f, hgt * 0.22f, 0.1f), M.Paper);
                    }
                    Col(g, new Vector3(0, -2f, 0), new Vector3(6.5f, 8f, 28f));
                    break;
            }
            return g;
        }

        public static GameObject Bridge(Transform parent, Vector3 a, Vector3 b, float width = 5f, bool vermilion = true)
        {
            Vector3 d = b - a; float L = new Vector3(d.x, 0, d.z).magnitude;
            var g = Root(parent, "橋", (a + b) * 0.5f, Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg);
            var rail = vermilion ? M.Vermilion : M.DarkWood;
            Box(g, new Vector3(0, 0.6f, 0), new Vector3(width, 0.4f, L), M.Wood, true);
            var mb = new MeshBuilder(1f);
            int n = Mathf.Max(2, Mathf.RoundToInt(L / 2.5f));
            for (int i = 0; i <= n; i++)
                foreach (var s in new[] { -1, 1 })
                    mb.Box(new Vector3(s * width / 2, 1.5f, -L / 2 + L * i / n), new Vector3(0.22f, 1.4f, 0.22f));
            foreach (var s in new[] { -1, 1 })
                mb.Box(new Vector3(s * width / 2, 2.0f, 0), new Vector3(0.14f, 0.16f, L));
            Part(g, "rail", mb.ToMesh("rail"), rail, Vector3.zero);
            for (int i = 1; i < n; i += 2)
                Cyl(g, new Vector3(0, -4f, -L / 2 + L * i / n), 0.4f, 4.6f, M.DarkWood, 8);
            return g;
        }

        public static GameObject Paddy(Transform parent, Vector3 pos, float rotY, float w, float d)
        {
            var g = Root(parent, "水田", pos, rotY);
            Box(g, new Vector3(0, -0.15f, 0), new Vector3(w, 0.2f, d), M.Earth, false, default, 4f);
            Box(g, new Vector3(0, 0.03f, 0), new Vector3(w - 0.8f, 0.02f, d - 0.8f), M.Paddy, false, default, 4f)
                .GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
            return g;
        }

        public static GameObject Banner(Transform parent, Vector3 pos, float rotY, Color c)
        {
            var g = Root(parent, "幟", pos, rotY);
            Cyl(g, Vector3.zero, 0.05f, 5.5f, M.DarkWood, 6);
            Box(g, new Vector3(0.45f, 2.2f, 0), new Vector3(0.85f, 3.1f, 0.03f), M.Cloth(c), false);
            Box(g, new Vector3(0.45f, 5.3f, 0), new Vector3(0.95f, 0.05f, 0.05f), M.DarkWood);
            return g;
        }
    }
}

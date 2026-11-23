using UnityEngine;

namespace HistoryShift
{
    /// <summary>
    /// プリミティブから組み立てる人型モデル＋手続きアニメーション（歩行・走行・騎乗・倒れ）。
    /// 外部モデル無しで動くことを優先し、時代ごとの衣装は色と小物（笠・兜・帽子）で表現する。
    /// </summary>
    public class CharacterRig : MonoBehaviour
    {
        public enum Outfit { Agent, Commoner, Noble, Samurai, Ashigaru, Monk, Western, Soldier, Guardian, Ancient }

        public Transform Hips, Torso, Head, ArmL, ArmR, LegL, LegR, Weapon;
        public float Speed;           // 現在の移動速度 m/s（呼び出し側が設定）
        public bool Riding;
        public bool Aiming;
        float phase;
        float fall;                   // 0..1 倒れ
        bool dying;

        static Mesh capsule, cube, sphere, cylinder;
        static Mesh M(PrimitiveType t)
        {
            var go = GameObject.CreatePrimitive(t);
            var m = go.GetComponent<MeshFilter>().sharedMesh;
            Object.Destroy(go);
            return m;
        }

        public static Mesh Capsule => capsule != null ? capsule : (capsule = M(PrimitiveType.Capsule));
        public static Mesh Cube => cube != null ? cube : (cube = M(PrimitiveType.Cube));
        public static Mesh Sphere => sphere != null ? sphere : (sphere = M(PrimitiveType.Sphere));
        public static Mesh Cylinder => cylinder != null ? cylinder : (cylinder = M(PrimitiveType.Cylinder));

        public static Transform Part(Transform parent, Mesh mesh, Material mat, Vector3 pos, Vector3 scale, Vector3 euler = default, string name = "Part")
        {
            var go = new GameObject(name, typeof(MeshFilter), typeof(MeshRenderer));
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scale;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.GetComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.GetComponent<MeshRenderer>();
            r.sharedMaterial = mat;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
            return go.transform;
        }

        static Transform Pivot(Transform parent, string name, Vector3 pos)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.localPosition = pos;
            return t;
        }

        /// <summary>高さ約1.75mの人型を作る。原点は足元。</summary>
        public static CharacterRig Build(Transform parent, Outfit outfit, int seed, bool armed)
        {
            var rng = new System.Random(seed);
            var root = new GameObject("Rig").transform;
            root.SetParent(parent, false);
            var rig = root.gameObject.AddComponent<CharacterRig>();

            Color skin = Color.Lerp(new Color(0.93f, 0.78f, 0.64f), new Color(0.78f, 0.58f, 0.42f), (float)rng.NextDouble());
            Color body, legs, accent;
            switch (outfit)
            {
                case Outfit.Agent: body = new Color(0.12f, 0.13f, 0.17f); legs = new Color(0.09f, 0.09f, 0.11f); accent = UIKit.Cyan; break;
                case Outfit.Noble: body = Pick(rng, new Color(0.55f, 0.18f, 0.35f), new Color(0.2f, 0.3f, 0.6f), new Color(0.75f, 0.55f, 0.2f)); legs = new Color(0.85f, 0.82f, 0.75f); accent = new Color(0.1f, 0.1f, 0.1f); break;
                case Outfit.Samurai: body = Pick(rng, new Color(0.6f, 0.12f, 0.1f), new Color(0.15f, 0.18f, 0.3f), new Color(0.2f, 0.2f, 0.2f)); legs = new Color(0.2f, 0.17f, 0.14f); accent = new Color(0.8f, 0.65f, 0.25f); break;
                case Outfit.Ashigaru: body = new Color(0.25f, 0.22f, 0.18f); legs = new Color(0.3f, 0.26f, 0.2f); accent = new Color(0.35f, 0.15f, 0.1f); break;
                case Outfit.Monk: body = new Color(0.9f, 0.88f, 0.82f); legs = new Color(0.9f, 0.88f, 0.82f); accent = new Color(0.15f, 0.15f, 0.15f); break;
                case Outfit.Western: body = Pick(rng, new Color(0.1f, 0.1f, 0.12f), new Color(0.25f, 0.2f, 0.17f), new Color(0.2f, 0.22f, 0.3f)); legs = new Color(0.12f, 0.12f, 0.13f); accent = Color.white; break;
                case Outfit.Soldier: body = new Color(0.36f, 0.38f, 0.26f); legs = new Color(0.33f, 0.34f, 0.24f); accent = new Color(0.2f, 0.2f, 0.15f); break;
                case Outfit.Guardian: body = new Color(0.05f, 0.05f, 0.08f); legs = new Color(0.04f, 0.04f, 0.06f); accent = new Color(1f, 0.2f, 0.9f); break;
                case Outfit.Ancient: body = new Color(0.78f, 0.72f, 0.58f); legs = new Color(0.7f, 0.64f, 0.5f); accent = new Color(0.5f, 0.3f, 0.2f); break;
                default: body = Pick(rng, new Color(0.3f, 0.35f, 0.5f), new Color(0.45f, 0.35f, 0.25f), new Color(0.35f, 0.42f, 0.33f), new Color(0.55f, 0.5f, 0.42f)); legs = new Color(0.25f, 0.22f, 0.2f); accent = new Color(0.6f, 0.55f, 0.45f); break;
            }
            var mSkin = Mats.Color(skin, 0.35f);
            var mBody = Mats.Color(body, 0.25f);
            var mLegs = Mats.Color(legs, 0.2f);
            var mAccent = outfit == Outfit.Guardian || outfit == Outfit.Agent ? Mats.Emissive(accent, 2.5f) : Mats.Color(accent, 0.5f, outfit == Outfit.Samurai ? 0.6f : 0f);
            var mHair = Mats.Color(new Color(0.05f, 0.04f, 0.04f), 0.4f);

            rig.Hips = Pivot(root, "Hips", new Vector3(0, 0.95f, 0));
            rig.Torso = Pivot(rig.Hips, "Torso", Vector3.zero);
            Part(rig.Torso, Capsule, mBody, new Vector3(0, 0.3f, 0), new Vector3(0.42f, 0.33f, 0.26f));
            Part(rig.Torso, Cube, mAccent, new Vector3(0, 0.05f, 0), new Vector3(0.44f, 0.06f, 0.28f)); // 帯・ベルト
            if (outfit == Outfit.Noble || outfit == Outfit.Monk || outfit == Outfit.Ancient)
                Part(rig.Torso, Cylinder, mBody, new Vector3(0, -0.25f, 0), new Vector3(0.5f, 0.38f, 0.4f)); // 袴・裳
            rig.Head = Pivot(rig.Torso, "Head", new Vector3(0, 0.68f, 0));
            Part(rig.Head, Sphere, mSkin, new Vector3(0, 0.1f, 0), new Vector3(0.22f, 0.25f, 0.23f));
            Part(rig.Head, Sphere, mHair, new Vector3(0, 0.16f, -0.02f), new Vector3(0.235f, 0.2f, 0.235f));
            switch (outfit)
            {
                case Outfit.Samurai: // 兜
                    Part(rig.Head, Sphere, mBody, new Vector3(0, 0.18f, 0), new Vector3(0.3f, 0.2f, 0.3f));
                    Part(rig.Head, Cube, mAccent, new Vector3(0, 0.32f, 0.08f), new Vector3(0.28f, 0.12f, 0.02f), new Vector3(-20, 0, 0));
                    break;
                case Outfit.Ashigaru: // 陣笠
                    Part(rig.Head, Cylinder, mAccent, new Vector3(0, 0.25f, 0), new Vector3(0.48f, 0.03f, 0.48f));
                    Part(rig.Head, Cylinder, mAccent, new Vector3(0, 0.29f, 0), new Vector3(0.22f, 0.04f, 0.22f));
                    break;
                case Outfit.Noble: // 烏帽子
                    Part(rig.Head, Cylinder, mAccent, new Vector3(0, 0.33f, -0.02f), new Vector3(0.14f, 0.14f, 0.16f), new Vector3(-10, 0, 0));
                    break;
                case Outfit.Western: case Outfit.Soldier: // 帽子
                    Part(rig.Head, Cylinder, mLegs, new Vector3(0, 0.26f, 0), new Vector3(0.3f, 0.015f, 0.3f));
                    Part(rig.Head, Cylinder, mLegs, new Vector3(0, 0.31f, 0), new Vector3(0.22f, 0.06f, 0.22f));
                    break;
                case Outfit.Guardian: // 光る仮面
                    Part(rig.Head, Cube, mAccent, new Vector3(0, 0.12f, 0.11f), new Vector3(0.18f, 0.04f, 0.02f));
                    break;
                case Outfit.Agent: // バイザー
                    Part(rig.Head, Cube, mAccent, new Vector3(0, 0.13f, 0.105f), new Vector3(0.19f, 0.05f, 0.03f));
                    break;
            }

            rig.ArmL = Pivot(rig.Torso, "ArmL", new Vector3(-0.27f, 0.55f, 0));
            rig.ArmR = Pivot(rig.Torso, "ArmR", new Vector3(0.27f, 0.55f, 0));
            foreach (var arm in new[] { rig.ArmL, rig.ArmR })
            {
                Part(arm, Capsule, mBody, new Vector3(0, -0.28f, 0), new Vector3(0.12f, 0.3f, 0.12f));
                Part(arm, Sphere, mSkin, new Vector3(0, -0.6f, 0), new Vector3(0.1f, 0.1f, 0.1f));
            }
            rig.LegL = Pivot(rig.Hips, "LegL", new Vector3(-0.11f, 0, 0));
            rig.LegR = Pivot(rig.Hips, "LegR", new Vector3(0.11f, 0, 0));
            foreach (var leg in new[] { rig.LegL, rig.LegR })
            {
                Part(leg, Capsule, mLegs, new Vector3(0, -0.44f, 0), new Vector3(0.15f, 0.45f, 0.15f));
                Part(leg, Cube, mHair, new Vector3(0, -0.9f, 0.05f), new Vector3(0.13f, 0.08f, 0.25f));
            }

            if (armed)
            {
                rig.Weapon = Pivot(rig.ArmR, "Weapon", new Vector3(0, -0.6f, 0.05f));
                var metal = Mats.Color(new Color(0.12f, 0.12f, 0.13f), 0.7f, 0.8f);
                if (outfit == Outfit.Agent || outfit == Outfit.Guardian)
                {
                    Part(rig.Weapon, Cube, metal, new Vector3(0, 0, 0.18f), new Vector3(0.07f, 0.1f, 0.42f));
                    Part(rig.Weapon, Cube, mAccent, new Vector3(0, 0.04f, 0.2f), new Vector3(0.075f, 0.02f, 0.3f));
                }
                else
                {
                    var wood = Mats.Color(new Color(0.35f, 0.22f, 0.12f), 0.3f);
                    Part(rig.Weapon, Cube, wood, new Vector3(0, 0, 0.1f), new Vector3(0.06f, 0.08f, 0.5f));
                    Part(rig.Weapon, Cylinder, metal, new Vector3(0, 0.03f, 0.55f), new Vector3(0.03f, 0.35f, 0.03f), new Vector3(90, 0, 0));
                }
            }
            return rig;
        }

        static Color Pick(System.Random r, params Color[] c) => c[r.Next(c.Length)];

        public void Die() { dying = true; }

        void LateUpdate()
        {
            float dt = Time.deltaTime;
            if (dying)
            {
                fall = Mathf.MoveTowards(fall, 1, dt * 2.5f);
                transform.localRotation = Quaternion.Euler(-85 * Mathf.SmoothStep(0, 1, fall), 0, 0);
                transform.localPosition = new Vector3(0, 0.2f * fall, 0);
                return;
            }
            if (Riding)
            {
                LegL.localRotation = Quaternion.Euler(-70, 0, -25);
                LegR.localRotation = Quaternion.Euler(-70, 0, 25);
                ArmL.localRotation = Quaternion.Euler(-45, 0, 0);
                ArmR.localRotation = Aiming ? Quaternion.Euler(-90, 0, 0) : Quaternion.Euler(-45, 0, 0);
                Hips.localPosition = new Vector3(0, 0.95f + Mathf.Sin(Time.time * 12) * 0.03f * Mathf.Clamp01(Speed / 10), 0);
                return;
            }
            float s = Mathf.Clamp01(Speed / 7f);
            phase += dt * Mathf.Lerp(4f, 11f, s) * (Speed > 0.2f ? 1 : 0);
            float swing = Mathf.Sin(phase) * Mathf.Lerp(0, 50, Mathf.Clamp01(Speed / 3f)) * (0.6f + 0.4f * s);
            LegL.localRotation = Quaternion.Euler(swing, 0, 0);
            LegR.localRotation = Quaternion.Euler(-swing, 0, 0);
            ArmL.localRotation = Quaternion.Euler(-swing * 0.8f, 0, -4);
            ArmR.localRotation = Aiming ? Quaternion.Euler(-88, 0, 0) : Quaternion.Euler(swing * 0.8f, 0, 4);
            Torso.localRotation = Quaternion.Euler(Mathf.Lerp(0, 12, s), Aiming ? 0 : Mathf.Sin(phase) * 4 * s, 0);
            Hips.localPosition = new Vector3(0, 0.95f + Mathf.Abs(Mathf.Cos(phase)) * 0.06f * s, 0);
        }
    }
}

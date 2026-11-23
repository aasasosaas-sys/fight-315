using System.Collections;
using UnityEngine;

namespace HistoryShift
{
    /// <summary>弾道・火花・爆発・画面揺れなどのエフェクトを実行時に生成する。</summary>
    public class Effects : MonoBehaviour
    {
        static Effects inst;
        static Effects I
        {
            get
            {
                if (inst == null) inst = new GameObject("Effects").AddComponent<Effects>();
                return inst;
            }
        }

        public static float Shake;   // CameraRig が読む

        public static void Tracer(Vector3 from, Vector3 to, Color color, float width = 0.05f)
        {
            var go = new GameObject("Tracer");
            var lr = go.AddComponent<LineRenderer>();
            lr.positionCount = 2;
            lr.SetPosition(0, from); lr.SetPosition(1, to);
            lr.startWidth = width; lr.endWidth = width * 0.4f;
            lr.sharedMaterial = Mats.Emissive(color, 6f);
            lr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            I.StartCoroutine(FadeLine(lr, 0.07f));
        }

        static IEnumerator FadeLine(LineRenderer lr, float t)
        {
            float t0 = Time.time;
            while (Time.time - t0 < t && lr != null)
            {
                float k = 1 - (Time.time - t0) / t;
                lr.widthMultiplier = k;
                yield return null;
            }
            if (lr != null) Destroy(lr.gameObject);
        }

        public static void Flash(Vector3 pos, Color color, float intensity, float range, float time)
        {
            var go = new GameObject("Flash");
            go.transform.position = pos;
            var l = go.AddComponent<Light>();
            l.type = LightType.Point; l.color = color; l.intensity = intensity; l.range = range; l.shadows = LightShadows.None;
            I.StartCoroutine(FadeLight(l, time));
        }

        static IEnumerator FadeLight(Light l, float t)
        {
            float t0 = Time.time, i0 = l.intensity;
            while (Time.time - t0 < t && l != null)
            {
                l.intensity = i0 * (1 - (Time.time - t0) / t);
                yield return null;
            }
            if (l != null) Destroy(l.gameObject);
        }

        static ParticleSystem Burst(Vector3 pos, Vector3 normal, Color c0, Color c1, int count, float speed, float size, float life, float gravity, bool emissive)
        {
            var go = new GameObject("Burst");
            go.transform.position = pos;
            go.transform.rotation = Quaternion.LookRotation(normal.sqrMagnitude > 0 ? normal : Vector3.up);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.duration = 0.2f; main.loop = false;
            main.startLifetime = new ParticleSystem.MinMaxCurve(life * 0.5f, life);
            main.startSpeed = new ParticleSystem.MinMaxCurve(speed * 0.3f, speed);
            main.startSize = new ParticleSystem.MinMaxCurve(size * 0.5f, size);
            main.startColor = new ParticleSystem.MinMaxGradient(c0, c1);
            main.gravityModifier = gravity;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.stopAction = ParticleSystemStopAction.Destroy;
            var em = ps.emission; em.rateOverTime = 0; em.SetBursts(new[] { new ParticleSystem.Burst(0, (short)count) });
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Cone; sh.angle = 35; sh.radius = 0.05f;
            var col = ps.colorOverLifetime; col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) },
                      new[] { new GradientAlphaKey(1, 0), new GradientAlphaKey(0, 1) });
            col.color = g;
            var sz = ps.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1, AnimationCurve.Linear(0, 1, 1, 0.3f));
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = emissive ? Mats.Particle(c0, true) : Mats.Particle(c0, false);
            ps.Play();
            return ps;
        }

        public static void Spark(Vector3 pos, Vector3 normal, Color color)
        {
            Burst(pos, normal, color, Color.white, 10, 7, 0.08f, 0.35f, 1.2f, true);
            Burst(pos, normal, new Color(0.5f, 0.45f, 0.4f, 0.6f), new Color(0.3f, 0.3f, 0.3f, 0.4f), 5, 1.5f, 0.4f, 0.8f, -0.05f, false);
        }

        public static void Blood(Vector3 pos, Vector3 normal, bool guardian)
        {
            if (guardian) Burst(pos, normal, new Color(1f, 0.2f, 0.9f), UIKit.Cyan, 14, 5, 0.12f, 0.5f, 0.2f, true);
            else Burst(pos, normal, new Color(0.45f, 0.03f, 0.03f), new Color(0.25f, 0.02f, 0.02f), 10, 3, 0.07f, 0.45f, 1.5f, false);
        }

        public static void Muzzle(Vector3 pos, Vector3 dir, Color color)
        {
            Burst(pos, dir, color, Color.white, 6, 4, 0.12f, 0.06f, 0, true);
            Flash(pos, color, 6, 6, 0.05f);
        }

        public static void TimeWarp(Vector3 pos)
        {
            Burst(pos + Vector3.up, Vector3.up, UIKit.Cyan, Color.white, 80, 9, 0.25f, 1.2f, -0.3f, true);
            Flash(pos + Vector3.up * 2, UIKit.Cyan, 30, 30, 1.0f);
        }

        /// <summary>爆発：範囲ダメージ＋物理インパルス＋炎と煙。</summary>
        public static void Explosion(Vector3 pos, float radius, float damage, Team from)
        {
            Burst(pos, Vector3.up, new Color(1f, 0.6f, 0.15f), new Color(1f, 0.25f, 0.05f), 60, 14, 1.2f, 0.7f, -0.2f, true);
            Burst(pos, Vector3.up, new Color(0.2f, 0.2f, 0.2f, 0.8f), new Color(0.35f, 0.33f, 0.3f, 0.6f), 30, 5, 3.5f, 3f, -0.08f, false);
            Burst(pos, Vector3.up, new Color(1f, 0.85f, 0.4f), Color.white, 40, 22, 0.12f, 1.2f, 1.5f, true);
            Flash(pos + Vector3.up, new Color(1f, 0.6f, 0.3f), 60, radius * 4, 0.5f);
            Sfx.PlayAt(Sfx.ExplodeClip, pos, 1f);
            var cam = Camera.main;
            if (cam != null) Shake = Mathf.Max(Shake, Mathf.Clamp01(1.5f - Vector3.Distance(cam.transform.position, pos) / (radius * 6)));

            var hits = Physics.OverlapSphere(pos, radius, ~0, QueryTriggerInteraction.Ignore);
            var done = new System.Collections.Generic.HashSet<Object>();
            foreach (var c in hits)
            {
                float k = 1 - Mathf.Clamp01(Vector3.Distance(c.ClosestPoint(pos), pos) / radius);
                var h = Health.Find(c);
                if (h != null && done.Add(h)) h.Damage(damage * k, from);
                var rb = c.attachedRigidbody;
                if (rb != null && done.Add(rb)) rb.AddExplosionForce(900 * Mathf.Max(1, rb.mass * 0.2f), pos, radius * 1.5f, 1.5f, ForceMode.Impulse);
                var ex = c.GetComponentInParent<Explosive>();
                if (ex != null && done.Add(ex)) ex.Detonate(0.15f + Random.value * 0.2f);
                var civ = c.GetComponentInParent<Civilian>();
                if (civ != null) civ.Panic(pos);
            }
            WantedSystem.Report(pos, 0.8f);
        }
    }

    /// <summary>撃つと爆発する樽など。</summary>
    public class Explosive : MonoBehaviour
    {
        public float Radius = 7, Damage = 120;
        bool done;

        public void Detonate(float delay = 0)
        {
            if (done) return;
            done = true;
            StartCoroutine(Go(delay));
        }

        IEnumerator Go(float d)
        {
            if (d > 0) yield return new WaitForSeconds(d);
            Effects.Explosion(transform.position + Vector3.up * 0.5f, Radius, Damage, Team.Neutral);
            Destroy(gameObject);
        }
    }
}

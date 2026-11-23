using System.Collections.Generic;
using UnityEngine;

namespace HistoryShift
{
    /// <summary>効果音を実行時に合成する（音声素材不要）。</summary>
    public static class Sfx
    {
        static AudioSource source;
        static readonly Dictionary<string, AudioClip> clips = new Dictionary<string, AudioClip>();
        const int Rate = 44100;

        static AudioSource Src
        {
            get
            {
                if (source != null) return source;
                var go = new GameObject("Sfx");
                Object.DontDestroyOnLoad(go);
                source = go.AddComponent<AudioSource>();
                source.playOnAwake = false;
                return source;
            }
        }

        delegate float Synth(float t, float dur, System.Random r);

        static AudioClip Make(string name, float dur, Synth f)
        {
            if (clips.TryGetValue(name, out var c)) return c;
            int n = Mathf.CeilToInt(dur * Rate);
            var data = new float[n];
            var rng = new System.Random(name.GetHashCode());
            for (int i = 0; i < n; i++) data[i] = Mathf.Clamp(f(i / (float)Rate, dur, rng), -1f, 1f);
            c = AudioClip.Create(name, n, 1, Rate, false);
            c.SetData(data, 0);
            clips[name] = c;
            return c;
        }

        static float Noise(System.Random r) => (float)(r.NextDouble() * 2 - 1);
        static float Env(float t, float dur, float attack = 0.005f) => Mathf.Clamp01(t / attack) * Mathf.Pow(1 - t / dur, 2);

        public static AudioClip ClickClip => Make("click", 0.06f, (t, d, r) => Mathf.Sin(t * 2 * Mathf.PI * 1200) * Env(t, d) * 0.3f);
        public static AudioClip ShotClip => Make("shot", 0.35f, (t, d, r) =>
            (Noise(r) * 0.8f + Mathf.Sin(t * 2 * Mathf.PI * (120 - t * 200)) * 0.6f) * Mathf.Exp(-t * 14) * 0.9f);
        public static AudioClip HitClip => Make("hit", 0.15f, (t, d, r) => Noise(r) * Mathf.Exp(-t * 30) * 0.5f + Mathf.Sin(t * 2 * Mathf.PI * 300) * Env(t, d) * 0.3f);
        public static AudioClip ExplodeClip => Make("explode", 1.2f, (t, d, r) =>
            (Noise(r) * 0.9f + Mathf.Sin(t * 2 * Mathf.PI * (60 - t * 30)) * 0.7f) * Mathf.Exp(-t * 3.5f) * 0.9f);
        public static AudioClip PickupClip => Make("pickup", 0.35f, (t, d, r) =>
            Mathf.Sin(t * 2 * Mathf.PI * (660 + t * 1600)) * Env(t, d) * 0.35f);
        public static AudioClip SuccessClip => Make("success", 1.4f, (t, d, r) =>
        {
            float[] notes = { 523.25f, 659.25f, 783.99f, 1046.5f };
            int k = Mathf.Min(3, (int)(t / 0.18f));
            float lt = t - k * 0.18f;
            return Mathf.Sin(t * 2 * Mathf.PI * notes[k]) * Mathf.Exp(-lt * 3) * 0.3f + Mathf.Sin(t * 2 * Mathf.PI * notes[k] * 2) * Mathf.Exp(-lt * 6) * 0.08f;
        });
        public static AudioClip WarpClip => Make("warp", 2.2f, (t, d, r) =>
        {
            float f = 80 + Mathf.Pow(t / d, 2) * 2400;
            return (Mathf.Sin(t * 2 * Mathf.PI * f) * 0.25f + Noise(r) * 0.15f * (t / d)) * Mathf.Sin(Mathf.PI * t / d);
        });
        public static AudioClip FailClip => Make("fail", 0.9f, (t, d, r) => Mathf.Sin(t * 2 * Mathf.PI * (300 - t * 200)) * Env(t, d) * 0.35f);

        public static AudioClip EngineClip => Make("engine", 1.0f, (t, d, r) =>
            (Mathf.Sin(t * 2 * Mathf.PI * 55) * 0.5f + Mathf.Sin(t * 2 * Mathf.PI * 110) * 0.25f + Noise(r) * 0.08f) * 0.5f);
        public static AudioClip PropClip => Make("prop", 1.0f, (t, d, r) =>
            (Mathf.Sin(t * 2 * Mathf.PI * 90) * 0.3f + Noise(r) * 0.25f) * (0.6f + 0.4f * Mathf.Sin(t * 2 * Mathf.PI * 24)) * 0.5f);
        public static AudioClip HoofClip => Make("hoof", 0.5f, (t, d, r) =>
        {
            float a = Mathf.Exp(-(t % 0.25f) * 40);
            return Noise(r) * a * 0.3f + Mathf.Sin(t * 2 * Mathf.PI * 180) * a * 0.2f;
        });

        public static void Play(AudioClip c, float vol = 1f) { if (c != null) Src.PlayOneShot(c, vol); }
        public static void PlayAt(AudioClip c, Vector3 pos, float vol = 1f) { if (c != null) AudioSource.PlayClipAtPoint(c, pos, vol); }
        public static void Click() => Play(ClickClip, 0.6f);

        /// <summary>乗り物などのループ音を持つ AudioSource を作る。</summary>
        public static AudioSource Loop(GameObject host, AudioClip c, float vol)
        {
            var a = host.AddComponent<AudioSource>();
            a.clip = c; a.loop = true; a.volume = vol; a.spatialBlend = 0.6f; a.playOnAwake = false;
            return a;
        }
    }
}

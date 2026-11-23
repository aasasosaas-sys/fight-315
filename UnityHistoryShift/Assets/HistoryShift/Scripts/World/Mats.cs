using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace HistoryShift
{
    /// <summary>URP Lit マテリアルのキャッシュ付きファクトリ。Poly Haven テクスチャがあれば使い、なければ単色。</summary>
    public static class Mats
    {
        static readonly Dictionary<string, Material> cache = new Dictionary<string, Material>();
        static readonly Dictionary<string, Texture2D> texCache = new Dictionary<string, Texture2D>();
        static Shader litShader;

        public static Shader Lit
        {
            get
            {
                if (litShader == null)
                {
                    litShader = Shader.Find("Universal Render Pipeline/Lit");
                    if (litShader == null) litShader = Shader.Find("Standard");
                }
                return litShader;
            }
        }

        public static bool IsURP => Lit != null && Lit.name.StartsWith("Universal");

        public static Texture2D LoadTex(string name)
        {
            if (texCache.TryGetValue(name, out var t)) return t;
            t = Resources.Load<Texture2D>("PolyHaven/Textures/" + name);
            texCache[name] = t;
            return t;
        }

        static Material NewLit()
        {
            var m = new Material(Lit);
            m.enableInstancing = true;
            return m;
        }

        static void SetColor(Material m, Color c)
        {
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c);
            if (m.HasProperty("_Color")) m.SetColor("_Color", c);
        }

        static void SetSmooth(Material m, float s, float metallic)
        {
            if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", s);
            if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", s);
            if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", metallic);
        }

        /// <summary>テクスチャ付きマテリアル。texKey は grass/wood/rooftile など。</summary>
        public static Material Get(string texKey, Color tint, float tiling = 1f, float smoothness = 0.2f)
        {
            string key = $"tex:{texKey}:{tint}:{tiling}:{smoothness}";
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            m = NewLit();
            m.name = "HS_" + texKey;
            SetColor(m, tint);
            SetSmooth(m, smoothness, 0f);
            var diff = LoadTex(texKey + "_diff");
            if (diff != null)
            {
                if (m.HasProperty("_BaseMap")) { m.SetTexture("_BaseMap", diff); m.SetTextureScale("_BaseMap", Vector2.one * tiling); }
                if (m.HasProperty("_MainTex")) { m.SetTexture("_MainTex", diff); m.SetTextureScale("_MainTex", Vector2.one * tiling); }
                var nor = LoadTex(texKey + "_nor_gl");
                if (nor != null && m.HasProperty("_BumpMap"))
                {
                    m.SetTexture("_BumpMap", nor);
                    m.SetTextureScale("_BumpMap", Vector2.one * tiling);
                    m.EnableKeyword("_NORMALMAP");
                }
            }
            cache[key] = m;
            return m;
        }

        public static Material Color(Color c, float smoothness = 0.3f, float metallic = 0f)
        {
            string key = $"col:{c}:{smoothness}:{metallic}";
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            m = NewLit();
            m.name = "HS_Color";
            SetColor(m, c);
            SetSmooth(m, smoothness, metallic);
            cache[key] = m;
            return m;
        }

        public static Material Emissive(Color c, float intensity)
        {
            string key = $"emi:{c}:{intensity}";
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            m = NewLit();
            m.name = "HS_Emissive";
            SetColor(m, c);
            m.EnableKeyword("_EMISSION");
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
            if (m.HasProperty("_EmissionColor")) m.SetColor("_EmissionColor", c * intensity);
            cache[key] = m;
            return m;
        }

        public static Material Transparent(Color c, float smoothness = 0.9f)
        {
            string key = $"tra:{c}:{smoothness}";
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            m = NewLit();
            m.name = "HS_Transparent";
            SetColor(m, c);
            SetSmooth(m, smoothness, 0f);
            MakeTransparent(m);
            cache[key] = m;
            return m;
        }

        /// <summary>透明な発光マテリアル（ビーコン用、加算ブレンド）。</summary>
        public static Material Glow(Color c, float intensity)
        {
            string key = $"glow:{c}:{intensity}";
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            m = NewLit();
            m.name = "HS_Glow";
            SetColor(m, c);
            MakeTransparent(m);
            m.SetFloat("_Blend", 2f); // additive
            m.SetInt("_SrcBlend", (int)BlendMode.SrcAlpha);
            m.SetInt("_DstBlend", (int)BlendMode.One);
            m.EnableKeyword("_EMISSION");
            if (m.HasProperty("_EmissionColor")) m.SetColor("_EmissionColor", new Color(c.r, c.g, c.b) * intensity);
            if (m.HasProperty("_Cull")) m.SetFloat("_Cull", 0f);
            m.SetShaderPassEnabled("ShadowCaster", false);
            cache[key] = m;
            return m;
        }

        static Texture2D softDot;

        /// <summary>柔らかい円形の粒子テクスチャ（放射状フォールオフ）。</summary>
        public static Texture2D SoftDot
        {
            get
            {
                if (softDot != null) return softDot;
                const int n = 64;
                softDot = new Texture2D(n, n, TextureFormat.RGBA32, false) { name = "HS_SoftDot", wrapMode = TextureWrapMode.Clamp };
                var px = new Color[n * n];
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        float dx = (x + 0.5f) / n * 2f - 1f, dy = (y + 0.5f) / n * 2f - 1f;
                        float r = Mathf.Sqrt(dx * dx + dy * dy);
                        float a = Mathf.Clamp01(1f - r);
                        a = a * a * (3f - 2f * a);
                        px[y * n + x] = new Color(1f, 1f, 1f, a);
                    }
                softDot.SetPixels(px);
                softDot.Apply(false, true);
                return softDot;
            }
        }

        /// <summary>パーティクル用マテリアル（URP Particles/Unlit、加算 or アルファ）。</summary>
        public static Material Particle(Color c, bool additive)
        {
            string key = $"par:{c}:{additive}";
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            var sh = Shader.Find("Universal Render Pipeline/Particles/Unlit");
            if (sh == null) sh = Shader.Find("Particles/Standard Unlit");
            if (sh == null) sh = Shader.Find("Sprites/Default");
            m = new Material(sh) { name = additive ? "HS_ParticleAdd" : "HS_ParticleAlpha" };
            SetColor(m, c);
            if (m.HasProperty("_TintColor")) m.SetColor("_TintColor", c);
            if (m.HasProperty("_BaseMap")) m.SetTexture("_BaseMap", SoftDot);
            if (m.HasProperty("_MainTex")) m.SetTexture("_MainTex", SoftDot);
            if (m.HasProperty("_Surface")) m.SetFloat("_Surface", 1f);
            if (m.HasProperty("_Blend")) m.SetFloat("_Blend", additive ? 2f : 0f);
            m.SetOverrideTag("RenderType", "Transparent");
            m.SetInt("_SrcBlend", (int)BlendMode.SrcAlpha);
            m.SetInt("_DstBlend", additive ? (int)BlendMode.One : (int)BlendMode.OneMinusSrcAlpha);
            m.SetInt("_ZWrite", 0);
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            m.renderQueue = (int)RenderQueue.Transparent;
            cache[key] = m;
            return m;
        }

        static void MakeTransparent(Material m)
        {
            if (m.HasProperty("_Surface")) m.SetFloat("_Surface", 1f);
            if (m.HasProperty("_Blend")) m.SetFloat("_Blend", 0f);
            m.SetOverrideTag("RenderType", "Transparent");
            m.SetInt("_SrcBlend", (int)BlendMode.SrcAlpha);
            m.SetInt("_DstBlend", (int)BlendMode.OneMinusSrcAlpha);
            if (m.HasProperty("_SrcBlendAlpha")) m.SetInt("_SrcBlendAlpha", (int)BlendMode.One);
            if (m.HasProperty("_DstBlendAlpha")) m.SetInt("_DstBlendAlpha", (int)BlendMode.OneMinusSrcAlpha);
            m.SetInt("_ZWrite", 0);
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            m.DisableKeyword("_ALPHATEST_ON");
            m.renderQueue = (int)RenderQueue.Transparent;
        }
    }
}

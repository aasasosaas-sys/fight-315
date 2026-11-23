using System;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

namespace HistoryShift
{
    /// <summary>コードだけで UGUI を組み立てるためのヘルパー。日本語は OS フォントを動的に使う。</summary>
    public static class UIKit
    {
        public static readonly Color Ink = new Color(0.08f, 0.07f, 0.10f, 0.92f);
        public static readonly Color Paper = new Color(0.97f, 0.95f, 0.90f, 1f);
        public static readonly Color Accent = new Color(0.86f, 0.24f, 0.20f, 1f);     // 朱色
        public static readonly Color Gold = new Color(0.95f, 0.78f, 0.35f, 1f);
        public static readonly Color Cyan = new Color(0.35f, 0.90f, 1f, 1f);           // 時空エネルギー
        public static readonly Color Good = new Color(0.30f, 0.80f, 0.45f, 1f);
        public static readonly Color Dim = new Color(1, 1, 1, 0.55f);

        static Font font;
        public static Font Font
        {
            get
            {
                if (font != null) return font;
                string[] names =
                {
                    "Yu Gothic UI", "Yu Gothic", "Meiryo UI", "Meiryo", "MS Gothic", "Hiragino Sans", "Hiragino Kaku Gothic ProN",
                    "Noto Sans CJK JP", "Noto Sans JP", "Source Han Sans JP", "TakaoPGothic", "IPAGothic"
                };
                font = Font.CreateDynamicFontFromOSFont(names, 32);
                if (font == null) font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                return font;
            }
        }

        public static Canvas CreateCanvas(string name, int order)
        {
            var go = new GameObject(name, typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var c = go.GetComponent<Canvas>();
            c.renderMode = RenderMode.ScreenSpaceOverlay;
            c.sortingOrder = order;
            var s = go.GetComponent<CanvasScaler>();
            s.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            s.referenceResolution = new Vector2(1920, 1080);
            s.matchWidthOrHeight = 0.5f;
            EnsureEventSystem();
            return c;
        }

        public static void EnsureEventSystem()
        {
            if (UnityEngine.Object.FindFirstObjectByType<EventSystem>() != null) return;
            var es = new GameObject("EventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            UnityEngine.Object.DontDestroyOnLoad(es);
        }

        public static RectTransform Rect(GameObject go)
        {
            var rt = go.GetComponent<RectTransform>();
            return rt != null ? rt : go.AddComponent<RectTransform>();
        }

        /// <summary>アンカー指定（0-1）。offset はピクセル。</summary>
        public static RectTransform Place(RectTransform rt, Vector2 anchorMin, Vector2 anchorMax, Vector2 offMin = default, Vector2 offMax = default)
        {
            rt.anchorMin = anchorMin; rt.anchorMax = anchorMax;
            rt.offsetMin = offMin; rt.offsetMax = offMax;
            return rt;
        }

        public static RectTransform Fill(RectTransform rt, float pad = 0) =>
            Place(rt, Vector2.zero, Vector2.one, new Vector2(pad, pad), new Vector2(-pad, -pad));

        public static Image Panel(Transform parent, Color color, string name = "Panel")
        {
            var go = new GameObject(name, typeof(RectTransform), typeof(Image));
            go.transform.SetParent(parent, false);
            var img = go.GetComponent<Image>();
            img.color = color;
            return img;
        }

        public static Text Label(Transform parent, string text, int size = 28, Color? color = null, TextAnchor align = TextAnchor.UpperLeft, FontStyle style = FontStyle.Normal)
        {
            var go = new GameObject("Text", typeof(RectTransform), typeof(Text));
            go.transform.SetParent(parent, false);
            var t = go.GetComponent<Text>();
            t.font = Font; t.text = text; t.fontSize = size; t.fontStyle = style;
            t.color = color ?? Color.white; t.alignment = align;
            t.horizontalOverflow = HorizontalWrapMode.Wrap; t.verticalOverflow = VerticalWrapMode.Overflow;
            t.supportRichText = true; t.raycastTarget = false;
            t.lineSpacing = 1.15f;
            return t;
        }

        public static Button Button(Transform parent, string text, Action onClick, int size = 28, Color? bg = null, Color? fg = null)
        {
            var img = Panel(parent, bg ?? new Color(0.15f, 0.14f, 0.2f, 0.95f), "Button");
            var b = img.gameObject.AddComponent<Button>();
            var colors = b.colors;
            colors.highlightedColor = new Color(1.15f, 1.15f, 1.15f, 1);
            colors.pressedColor = new Color(0.8f, 0.8f, 0.8f, 1);
            colors.selectedColor = colors.highlightedColor;
            b.colors = colors;
            b.onClick.AddListener(() => { Sfx.Click(); onClick?.Invoke(); });
            var t = Label(img.transform, text, size, fg ?? Color.white, TextAnchor.MiddleCenter);
            Fill(t.rectTransform, 10);
            var outline = img.gameObject.AddComponent<Outline>();
            outline.effectColor = new Color(1, 1, 1, 0.12f);
            return b;
        }

        public static Text ButtonLabel(Button b) => b.GetComponentInChildren<Text>();

        /// <summary>縦スクロール領域。返り値の content に VerticalLayoutGroup が付いている。</summary>
        public static RectTransform ScrollArea(Transform parent, out ScrollRect scroll, float spacing = 12, int pad = 16)
        {
            var root = Panel(parent, new Color(0, 0, 0, 0.0f), "Scroll");
            scroll = root.gameObject.AddComponent<ScrollRect>();
            root.gameObject.AddComponent<RectMask2D>();
            var content = new GameObject("Content", typeof(RectTransform), typeof(VerticalLayoutGroup), typeof(ContentSizeFitter));
            content.transform.SetParent(root.transform, false);
            var rt = Rect(content);
            rt.anchorMin = new Vector2(0, 1); rt.anchorMax = new Vector2(1, 1); rt.pivot = new Vector2(0.5f, 1);
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
            var vl = content.GetComponent<VerticalLayoutGroup>();
            vl.spacing = spacing; vl.padding = new RectOffset(pad, pad, pad, pad);
            vl.childControlHeight = true; vl.childControlWidth = true; vl.childForceExpandHeight = false; vl.childForceExpandWidth = true;
            content.GetComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            scroll.content = rt; scroll.horizontal = false; scroll.scrollSensitivity = 40;
            scroll.movementType = ScrollRect.MovementType.Clamped;
            return rt;
        }

        public static LayoutElement Layout(Component c, float minHeight = -1, float preferredHeight = -1, float flexibleWidth = -1)
        {
            var le = c.GetComponent<LayoutElement>() ?? c.gameObject.AddComponent<LayoutElement>();
            le.minHeight = minHeight; le.preferredHeight = preferredHeight; le.flexibleWidth = flexibleWidth;
            return le;
        }

        public static HorizontalLayoutGroup Row(Transform parent, float spacing = 12, float height = 64)
        {
            var go = new GameObject("Row", typeof(RectTransform), typeof(HorizontalLayoutGroup));
            go.transform.SetParent(parent, false);
            var h = go.GetComponent<HorizontalLayoutGroup>();
            h.spacing = spacing; h.childControlWidth = true; h.childControlHeight = true;
            h.childForceExpandWidth = true; h.childForceExpandHeight = true;
            Layout(h, height, height);
            return h;
        }

        public static void Clear(Transform t)
        {
            for (int i = t.childCount - 1; i >= 0; i--) UnityEngine.Object.Destroy(t.GetChild(i).gameObject);
        }

        public static readonly string[] Circled = { "①", "②", "③", "④" };
    }
}

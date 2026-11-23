using System.Collections.Generic;
using UnityEngine;

namespace HistoryShift
{
    /// <summary>Tools/download_assets.py で取得した Poly Haven モデル（Resources/PolyHaven/Models）の読み込み。</summary>
    public static class ModelLibrary
    {
        static readonly Dictionary<string, GameObject> cache = new Dictionary<string, GameObject>();

        public static GameObject Load(string id)
        {
            if (cache.TryGetValue(id, out var go)) return go;
            go = Resources.Load<GameObject>($"PolyHaven/Models/{id}/{id}");
            cache[id] = go;
            return go;
        }

        public static bool Has(string id) => Load(id) != null;

        public static GameObject TryInstantiate(string polyHavenId, Transform parent, Vector3 pos, float yRot,
                                                float scale = 1f, bool addCollider = false)
        {
            var prefab = Load(polyHavenId);
            if (prefab == null) return null;
            var go = Object.Instantiate(prefab, pos, Quaternion.Euler(0f, yRot, 0f), parent);
            go.name = polyHavenId;
            go.transform.localScale = prefab.transform.localScale * scale;
            if (addCollider)
            {
                foreach (var mf in go.GetComponentsInChildren<MeshFilter>())
                {
                    if (mf.sharedMesh == null) continue;
                    var mc = mf.gameObject.AddComponent<MeshCollider>();
                    mc.sharedMesh = mf.sharedMesh;
                }
            }
            return go;
        }
    }
}

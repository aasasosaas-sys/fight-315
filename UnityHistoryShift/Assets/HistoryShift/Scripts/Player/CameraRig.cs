using UnityEngine;

namespace HistoryShift
{
    /// <summary>三人称カメラ。徒歩は肩越し、乗り物は後方追従、飛行機はチェイスカメラ。</summary>
    public class CameraRig : MonoBehaviour
    {
        public enum Mode { OnFoot, Ground, Plane, Orbit }

        public static CameraRig I { get; private set; }
        public Transform Target;
        public Mode CurrentMode = Mode.OnFoot;
        public float Yaw, Pitch = 10;
        public bool Aiming;
        Camera cam;
        float dist = 4.5f;
        Vector3 smoothPos;
        float orbitT;

        public Camera Cam => cam;
        public Vector3 FlatForward => Quaternion.Euler(0, Yaw, 0) * Vector3.forward;
        public Vector3 FlatRight => Quaternion.Euler(0, Yaw, 0) * Vector3.right;
        public Ray AimRay => cam.ViewportPointToRay(new Vector3(0.5f, 0.5f, 0));

        void Awake()
        {
            I = this;
            cam = GetComponent<Camera>();
        }

        public void Snap()
        {
            if (Target == null) return;
            smoothPos = Target.position;
            Yaw = Target.eulerAngles.y;
        }

        void LateUpdate()
        {
            if (Target == null) return;
            float dt = Time.deltaTime;
            bool blocked = GameManager.I != null && GameManager.I.InputBlocked;
            Vector2 look = blocked ? Vector2.zero : InputX.Look;

            if (CurrentMode == Mode.Orbit)
            {
                orbitT += dt * 0.05f;
                var c = Target.position + new Vector3(Mathf.Cos(orbitT) * 160, 70, Mathf.Sin(orbitT) * 160);
                transform.position = Vector3.Lerp(transform.position, c, dt * 0.5f);
                transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(Target.position + Vector3.up * 10 - transform.position), dt * 0.8f);
                cam.fieldOfView = 55;
                return;
            }

            if (CurrentMode == Mode.Plane)
            {
                var want = Target.position - Target.forward * 14f + Vector3.up * 3.5f;
                transform.position = Vector3.Lerp(transform.position, want, 1 - Mathf.Exp(-dt * 6));
                var lookAt = Target.position + Target.forward * 30f;
                transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(lookAt - transform.position, Vector3.Lerp(Vector3.up, Target.up, 0.4f)), 1 - Mathf.Exp(-dt * 8));
                cam.fieldOfView = Mathf.Lerp(cam.fieldOfView, 70, dt * 3);
                ApplyShake(dt);
                return;
            }

            Yaw += look.x * 2.2f;
            Pitch = Mathf.Clamp(Pitch - look.y * 2.0f, -35, 70);

            bool foot = CurrentMode == Mode.OnFoot;
            float wantDist = foot ? (Aiming ? 2.0f : 4.2f) : 8.5f;
            float height = foot ? 1.6f : 2.6f;
            float shoulder = foot ? (Aiming ? 0.75f : 0.55f) : 0f;
            dist = Mathf.Lerp(dist, wantDist, 1 - Mathf.Exp(-dt * 10));
            smoothPos = Vector3.Lerp(smoothPos, Target.position, 1 - Mathf.Exp(-dt * (foot ? 25 : 12)));

            var rot = Quaternion.Euler(Pitch, Yaw, 0);
            var pivot = smoothPos + Vector3.up * height + rot * Vector3.right * shoulder;
            var desired = pivot - rot * Vector3.forward * dist;

            // 壁抜け防止
            var dir = desired - pivot;
            float len = dir.magnitude;
            var hits = Physics.SphereCastAll(pivot, 0.25f, dir.normalized, len, ~0, QueryTriggerInteraction.Ignore);
            float best = len;
            foreach (var h in hits)
            {
                if (h.collider.transform.IsChildOf(Target.root)) continue;
                if (h.collider.GetComponentInParent<Civilian>() != null) continue;
                if (h.distance < best) best = h.distance;
            }
            transform.position = pivot + dir.normalized * Mathf.Max(0.3f, best - 0.1f);
            transform.rotation = rot;
            cam.fieldOfView = Mathf.Lerp(cam.fieldOfView, Aiming ? 48 : (foot ? 62 : 68), dt * 10);
            ApplyShake(dt);
        }

        void ApplyShake(float dt)
        {
            if (Effects.Shake <= 0) return;
            float s = Effects.Shake;
            transform.position += Random.insideUnitSphere * s * 0.25f;
            transform.rotation *= Quaternion.Euler(Random.Range(-1f, 1f) * s * 1.5f, Random.Range(-1f, 1f) * s * 1.5f, 0);
            Effects.Shake = Mathf.Max(0, s - dt * 1.8f);
        }
    }
}

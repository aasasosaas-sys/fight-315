using UnityEngine;

namespace HistoryShift
{
    /// <summary>時空エージェント（プレイヤー）。走る・跳ぶ・撃つ・乗り物に乗る・パラシュート降下。</summary>
    [RequireComponent(typeof(CharacterController))]
    public class PlayerController : MonoBehaviour
    {
        public static PlayerController I { get; private set; }
        public CharacterController CC { get; private set; }
        public CharacterRig Rig { get; private set; }
        public Health Health { get; private set; }
        public Gun Gun { get; private set; }
        public Vehicle Vehicle { get; private set; }
        public bool InVehicle => Vehicle != null;
        public bool Parachuting { get; private set; }

        Vector3 velocity;
        Transform chute;
        float vehicleCooldown;

        public static PlayerController Spawn(Vector3 pos)
        {
            var go = new GameObject("Player");
            go.transform.position = pos + Vector3.up * 0.2f;
            var cc = go.AddComponent<CharacterController>();
            cc.height = 1.8f; cc.radius = 0.35f; cc.center = new Vector3(0, 0.9f, 0); cc.stepOffset = 0.45f; cc.slopeLimit = 50;
            return go.AddComponent<PlayerController>();
        }

        void Awake()
        {
            I = this;
            CC = GetComponent<CharacterController>();
            Rig = CharacterRig.Build(transform, CharacterRig.Outfit.Agent, 7, true);
            Health = gameObject.AddComponent<Health>();
            Health.Init(150, Team.Player, 10);
            Health.OnDamaged += d => { Hud.I?.DamageFlash(d); Sfx.Play(Sfx.HitClip, 0.5f); };
            Health.OnDeath += () => GameManager.I?.OnPlayerDied();
            Gun = gameObject.AddComponent<Gun>();
            Gun.Owner = this;

            chute = new GameObject("Parachute").transform;
            chute.SetParent(transform, false);
            chute.localPosition = new Vector3(0, 4.2f, 0);
            CharacterRig.Part(chute, CharacterRig.Sphere, Mats.Color(new Color(0.9f, 0.3f, 0.2f), 0.2f), Vector3.zero, new Vector3(5, 1.4f, 5));
            chute.gameObject.SetActive(false);
        }

        void OnDestroy() { if (I == this) I = null; }

        void Update()
        {
            if (Health.Dead) return;
            bool blocked = GameManager.I != null && GameManager.I.InputBlocked;
            vehicleCooldown -= Time.deltaTime;

            if (InVehicle)
            {
                Rig.Speed = Vehicle.Speed;
                if (!blocked && InputX.Vehicle && vehicleCooldown <= 0) ExitVehicle();
                return;
            }

            var cam = CameraRig.I;
            Vector2 mv = blocked ? Vector2.zero : InputX.Move;
            Vector3 wish = cam != null ? (cam.FlatForward * mv.y + cam.FlatRight * mv.x) : new Vector3(mv.x, 0, mv.y);
            bool aiming = !blocked && (InputX.Aim || InputX.Fire);
            float speed = (!blocked && InputX.Sprint && !aiming) ? 9f : (aiming ? 3.8f : 5f);

            bool grounded = CC.isGrounded;
            if (grounded)
            {
                if (velocity.y < 0) velocity.y = -2f;
                Parachuting = false;
                if (!blocked && InputX.Jump) velocity.y = 6.5f;
            }
            else
            {
                velocity.y += -22f * Time.deltaTime;
                if (velocity.y < -14f) Parachuting = true;
                if (Parachuting) velocity.y = Mathf.Max(velocity.y, -4.5f);
            }
            chute.gameObject.SetActive(Parachuting);

            Vector3 horiz = wish * speed;
            float control = grounded ? 1 : (Parachuting ? 0.6f : 0.35f);
            Vector3 hv = new Vector3(velocity.x, 0, velocity.z);
            hv = Vector3.Lerp(hv, horiz, 1 - Mathf.Exp(-Time.deltaTime * 12 * control));
            velocity.x = hv.x; velocity.z = hv.z;
            CC.Move(velocity * Time.deltaTime);

            // 落下防止（地形より下に落ちたら戻す）
            var w = GameManager.I != null ? GameManager.I.World : null;
            if (w != null)
            {
                float h = w.HeightAt(transform.position.x, transform.position.z);
                if (transform.position.y < h - 3) { CC.enabled = false; transform.position = new Vector3(transform.position.x, h + 1, transform.position.z); CC.enabled = true; }
                float lim = w.HalfSize - 5;
                var p = transform.position;
                if (Mathf.Abs(p.x) > lim || Mathf.Abs(p.z) > lim)
                { CC.enabled = false; transform.position = new Vector3(Mathf.Clamp(p.x, -lim, lim), p.y, Mathf.Clamp(p.z, -lim, lim)); CC.enabled = true; }
            }

            // 向き
            Vector3 face = aiming && cam != null ? cam.FlatForward : (hv.sqrMagnitude > 0.5f ? hv.normalized : transform.forward);
            if (face.sqrMagnitude > 0.01f)
                transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(face), 1 - Mathf.Exp(-Time.deltaTime * (aiming ? 25 : 10)));

            Rig.Speed = hv.magnitude;
            Rig.Aiming = aiming;
            if (cam != null) cam.Aiming = !blocked && InputX.Aim;

            if (!blocked && InputX.Vehicle && vehicleCooldown <= 0)
            {
                var v = Vehicle.Nearest(transform.position, 4.5f);
                if (v != null) EnterVehicle(v);
            }
        }

        public void EnterVehicle(Vehicle v)
        {
            if (v == null || v.Driver != null) return;
            Vehicle = v;
            vehicleCooldown = 0.5f;
            CC.enabled = false;
            velocity = Vector3.zero;
            Parachuting = false; chute.gameObject.SetActive(false);
            transform.SetParent(v.Seat, false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
            Rig.Riding = true;
            v.Enter(this);
            if (CameraRig.I != null)
            {
                CameraRig.I.Target = v.transform;
                CameraRig.I.CurrentMode = v.Kind == VehicleKind.Plane ? CameraRig.Mode.Plane : CameraRig.Mode.Ground;
            }
            Hud.I?.Toast($"{v.DisplayName}に乗った（F で降りる）");
        }

        public void ExitVehicle()
        {
            if (Vehicle == null) return;
            var v = Vehicle;
            Vehicle = null;
            vehicleCooldown = 0.5f;
            v.Exit();
            transform.SetParent(null, true);
            Vector3 exitPos = v.ExitPoint();
            transform.position = exitPos;
            transform.rotation = Quaternion.Euler(0, v.transform.eulerAngles.y, 0);
            velocity = v.Velocity * 0.6f;
            Rig.Riding = false;
            CC.enabled = true;
            if (CameraRig.I != null) { CameraRig.I.Target = transform; CameraRig.I.CurrentMode = CameraRig.Mode.OnFoot; }
        }

        public void Teleport(Vector3 pos)
        {
            if (InVehicle) ExitVehicle();
            CC.enabled = false;
            transform.position = pos + Vector3.up * 0.3f;
            CC.enabled = true;
            velocity = Vector3.zero;
            CameraRig.I?.Snap();
        }
    }
}

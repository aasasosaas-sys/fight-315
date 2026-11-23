using UnityEngine;

namespace HistoryShift
{
    /// <summary>時空エージェントの光線銃（ヒットスキャン）。徒歩・騎乗・車上から撃てる。</summary>
    public class Gun : MonoBehaviour
    {
        public PlayerController Owner;
        public int MagSize = 30;
        public int Ammo = 30;
        public float FireRate = 9f;
        public float Damage = 24f;
        public float ReloadTime = 1.3f;
        public bool Reloading { get; private set; }
        float nextShot, reloadEnd;

        void Update()
        {
            if (Owner == null || Owner.Health.Dead) return;
            if (GameManager.I != null && GameManager.I.InputBlocked) return;
            if (Owner.InVehicle && Owner.Vehicle.Kind == VehicleKind.Plane) return; // 飛行機は機銃を使う

            if (Reloading && Time.time >= reloadEnd) { Reloading = false; Ammo = MagSize; }
            if (!Reloading && (InputX.Reload && Ammo < MagSize || Ammo <= 0)) { Reloading = true; reloadEnd = Time.time + ReloadTime; }
            if (Reloading || !InputX.Fire || Time.time < nextShot) return;

            nextShot = Time.time + 1f / FireRate;
            Ammo--;
            Fire();
        }

        void Fire()
        {
            var rig = CameraRig.I;
            if (rig == null) return;
            var ray = rig.AimRay;
            float spread = (rig.Aiming ? 0.004f : 0.015f) + (Owner.InVehicle ? 0.01f : 0);
            ray.direction = (ray.direction + Random.insideUnitSphere * spread).normalized;

            Vector3 muzzle = Owner.Rig.Weapon != null ? Owner.Rig.Weapon.position + Owner.Rig.Weapon.forward * 0.45f : Owner.transform.position + Vector3.up * 1.4f;
            Vector3 end = ray.origin + ray.direction * 400f;
            var hit = Raycast(ray, 400f, Owner.transform.root);
            if (hit.HasValue) end = hit.Value.point;

            Effects.Muzzle(muzzle, ray.direction, UIKit.Cyan);
            Effects.Tracer(muzzle, end, UIKit.Cyan, 0.04f);
            Sfx.Play(Sfx.ShotClip, 0.35f);
            WantedSystem.Report(Owner.transform.position, 0.02f);
            if (hit.HasValue) ApplyHit(hit.Value, ray.direction, Damage, Team.Player);
        }

        /// <summary>自分自身を無視するレイキャスト。</summary>
        public static RaycastHit? Raycast(Ray ray, float range, Transform ignoreRoot)
        {
            var hits = Physics.RaycastAll(ray, range, ~0, QueryTriggerInteraction.Ignore);
            RaycastHit? best = null;
            float bd = float.MaxValue;
            foreach (var h in hits)
            {
                if (ignoreRoot != null && h.collider.transform.IsChildOf(ignoreRoot)) continue;
                if (h.distance < bd) { bd = h.distance; best = h; }
            }
            return best;
        }

        public static void ApplyHit(RaycastHit h, Vector3 dir, float damage, Team from)
        {
            var health = Health.Find(h.collider);
            var civ = h.collider.GetComponentInParent<Civilian>();
            if (civ != null)
            {
                civ.Panic(h.point);        // 町人は倒れない：伏せて逃げる
                Effects.Spark(h.point, h.normal, Color.white);
            }
            else if (health != null)
            {
                health.Damage(damage, from);
                var en = health.GetComponent<Enemy>();
                Effects.Blood(h.point, h.normal, en != null && en.IsGuardian);
                if (from == Team.Player) Hud.I?.HitMarker(health.Dead);
            }
            else Effects.Spark(h.point, h.normal, new Color(1f, 0.8f, 0.5f));

            if (h.rigidbody != null) h.rigidbody.AddForceAtPosition(dir * 25f, h.point, ForceMode.Impulse);
            var ex = h.collider.GetComponentInParent<Explosive>();
            if (ex != null) ex.Detonate();
        }
    }
}

using System;
using UnityEngine;

namespace HistoryShift
{
    public enum Team { Player, Enemy, Neutral }

    public class Health : MonoBehaviour
    {
        public float Max = 100;
        public float Current = 100;
        public Team Team = Team.Neutral;
        public float RegenPerSec = 0;
        public float RegenDelay = 4;
        public bool Dead { get; private set; }
        public event Action<float> OnDamaged;
        public event Action OnDeath;
        float lastHit = -99;

        public void Init(float max, Team team, float regen = 0)
        {
            Max = Current = max; Team = team; RegenPerSec = regen; Dead = false;
        }

        public void Damage(float amount, Team from)
        {
            if (Dead || from == Team) return;
            Current = Mathf.Max(0, Current - amount);
            lastHit = Time.time;
            OnDamaged?.Invoke(amount);
            if (Current <= 0) { Dead = true; OnDeath?.Invoke(); }
        }

        public void HealFull() { Current = Max; Dead = false; }

        void Update()
        {
            if (!Dead && RegenPerSec > 0 && Time.time - lastHit > RegenDelay)
                Current = Mathf.Min(Max, Current + RegenPerSec * Time.deltaTime);
        }

        public static Health Find(Collider c) => c != null ? c.GetComponentInParent<Health>() : null;
    }
}

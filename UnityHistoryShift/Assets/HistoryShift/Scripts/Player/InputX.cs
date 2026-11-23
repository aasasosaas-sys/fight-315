using UnityEngine;
using UnityEngine.InputSystem;

namespace HistoryShift
{
    /// <summary>Input System の薄いラッパー（キーボード＋マウス、ゲームパッド対応）。</summary>
    public static class InputX
    {
        static Keyboard K => Keyboard.current;
        static Mouse M => Mouse.current;
        static Gamepad G => Gamepad.current;

        public static Vector2 Move
        {
            get
            {
                Vector2 v = Vector2.zero;
                if (K != null)
                {
                    if (K.wKey.isPressed || K.upArrowKey.isPressed) v.y += 1;
                    if (K.sKey.isPressed || K.downArrowKey.isPressed) v.y -= 1;
                    if (K.dKey.isPressed || K.rightArrowKey.isPressed) v.x += 1;
                    if (K.aKey.isPressed || K.leftArrowKey.isPressed) v.x -= 1;
                }
                if (G != null) v += G.leftStick.ReadValue();
                return Vector2.ClampMagnitude(v, 1f);
            }
        }

        public static Vector2 Look
        {
            get
            {
                Vector2 v = Vector2.zero;
                if (M != null && Cursor.lockState == CursorLockMode.Locked) v += M.delta.ReadValue() * 0.08f;
                if (G != null) v += G.rightStick.ReadValue() * 3f;
                return v;
            }
        }

        public static bool Jump => (K != null && K.spaceKey.wasPressedThisFrame) || (G != null && G.buttonSouth.wasPressedThisFrame);
        public static bool JumpHeld => (K != null && K.spaceKey.isPressed) || (G != null && G.buttonSouth.isPressed);
        public static bool Sprint => (K != null && K.leftShiftKey.isPressed) || (G != null && G.leftStickButton.isPressed);
        public static bool Fire => (M != null && Cursor.lockState == CursorLockMode.Locked && M.leftButton.isPressed) || (G != null && G.rightTrigger.isPressed);
        public static bool Aim => (M != null && Cursor.lockState == CursorLockMode.Locked && M.rightButton.isPressed) || (G != null && G.leftTrigger.isPressed);
        public static bool Interact => (K != null && K.eKey.wasPressedThisFrame) || (G != null && G.buttonWest.wasPressedThisFrame);
        public static bool Vehicle => (K != null && K.fKey.wasPressedThisFrame) || (G != null && G.buttonNorth.wasPressedThisFrame);
        public static bool Reload => (K != null && K.rKey.wasPressedThisFrame) || (G != null && G.buttonEast.wasPressedThisFrame);
        public static bool Pause => (K != null && K.escapeKey.wasPressedThisFrame) || (G != null && G.startButton.wasPressedThisFrame);
        public static bool Advance => Interact || (M != null && M.leftButton.wasPressedThisFrame) || (K != null && K.enterKey.wasPressedThisFrame);
        public static bool YawLeft => K != null && K.qKey.isPressed;
        public static bool YawRight => K != null && K.eKey.isPressed;
        public static bool Map => K != null && K.mKey.wasPressedThisFrame;
        public static float Scroll => M != null ? M.scroll.ReadValue().y : 0f;

        public static void LockCursor(bool locked)
        {
            Cursor.lockState = locked ? CursorLockMode.Locked : CursorLockMode.None;
            Cursor.visible = !locked;
        }
    }
}

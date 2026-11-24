"""hair lit/shade textures with an anime 'angel ring' highlight band (uv.y = arc from crown)."""
import numpy as np, zlib, struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hairlib import S_SPLIT, S_MAX

OUT = "/home/user/fight-315/HistoryShift/assets/characters/hair/"
W, H = 512, 1024
rng = np.random.default_rng(3)


def write_png(path, img):
    img = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, c = img.shape
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2 if c == 3 else 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


v = (np.arange(H) + 0.5) / H
s = np.where(v < 0.5, v / 0.5 * S_SPLIT, S_SPLIT + (v - 0.5) / 0.5 * (S_MAX - S_SPLIT))
u = (np.arange(W) + 0.5) / W
S, U = np.meshgrid(s, u, indexing="ij")

# ring mask: continuous band with pointed teeth (anime "angel ring")
def teeth(u, period, amps, sharp=1.0):
    x = u / period
    i = np.floor(x).astype(int) % len(amps)
    f = x - np.floor(x)
    tri = 1 - np.abs(2 * f - 1)          # 0 at tooth edges, 1 at tip
    return amps[i] * tri ** sharp
amps_d = rng.uniform(0.3, 1.0, 9)
amps_u = rng.uniform(0.2, 1.0, 6)
cen = 0.080 + 0.003 * np.sin(2 * np.pi * U * 2 + 1.0)
top = cen - 0.009 - 0.007 * teeth(U, 1 / 6, amps_u, 1.4)
bot = cen + 0.008 + 0.020 * teeth(U, 1 / 9, amps_d, 1.6)
ring = ((S > top) & (S < bot)).astype(float)
glow = np.clip(1 - np.abs(S - 0.083) / 0.035, 0, 1) ** 1.5
# soften slightly
from numpy.lib.stride_tricks import sliding_window_view
def blur(x, r=1):
    p = np.pad(x, r, mode="wrap")
    return sliding_window_view(p, (2 * r + 1, 2 * r + 1)).mean(axis=(-1, -2))
ring = blur(ring, 1)
ring = np.clip(ring, 0, 1)

# fine streaks along strands
streak = np.zeros(W)
for k in range(40):
    uc = rng.random(); wu = rng.uniform(0.002, 0.006)
    du = np.abs(((u - uc + 0.5) % 1.0) - 0.5)
    streak = np.maximum(streak, (du < wu) * rng.uniform(0.3, 1.0))
streak = blur(np.tile(streak, (8, 1)), 1)[0]
STR = np.tile(streak, (H, 1))

base_lit = np.array([0.20, 0.195, 0.265])
base_hi = np.array([0.24, 0.235, 0.32])    # crown slightly lighter
ring_col = np.array([0.52, 0.54, 0.70])
base_sh = np.array([0.07, 0.065, 0.105])
ring_sh = np.array([0.14, 0.14, 0.20])

g = np.clip(1 - S / 0.12, 0, 1)[..., None]
lit = base_lit * (1 - g) + base_hi * g
lit = lit * (1 - 0.035 * STR[..., None]) * (1 + 0.25 * glow[..., None])
lit = lit * (1 - ring[..., None]) + ring_col * ring[..., None]
sh = base_sh * (1 + 0.15 * glow[..., None])
sh = sh * (1 - ring[..., None] * 0.8) + ring_sh * ring[..., None] * 0.8

os.makedirs(OUT, exist_ok=True)
write_png(OUT + "hair_lit.png", lit)
write_png(OUT + "hair_shade.png", sh)
print("ok")

class_name Sfx
extends RefCounted
## 効果音を実行時に合成（音声素材なし）。

const RATE := 22050
static var _cache := {}


static func _make(name: String, dur: float, f: Callable, loop := false) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(f.call(t, dur, rng), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	_cache[name] = s
	return s


static func _env(t: float, d: float) -> float:
	return clampf(t / 0.005, 0.0, 1.0) * pow(1.0 - t / d, 2.0)


static func shot() -> AudioStreamWAV:
	return _make("shot", 0.3, func(t, d, r): return (r.randf_range(-1, 1) * 0.8 + sin(t * TAU * (130.0 - t * 220.0)) * 0.6) * exp(-t * 16.0) * 0.9)
static func musket() -> AudioStreamWAV:
	return _make("musket", 0.7, func(t, d, r): return (r.randf_range(-1, 1) * 0.9 + sin(t * TAU * (70.0 - t * 40.0)) * 0.7) * exp(-t * 6.0) * 0.9)
static func bow() -> AudioStreamWAV:
	return _make("bow", 0.25, func(t, d, r): return sin(t * TAU * (220.0 + 40.0 * sin(t * 90.0))) * exp(-t * 18.0) * 0.5 + r.randf_range(-1, 1) * exp(-t * 40.0) * 0.2)
static func energy() -> AudioStreamWAV:
	return _make("energy", 0.35, func(t, d, r): return sin(t * TAU * (900.0 - t * 2000.0)) * _env(t, d) * 0.4)
static func hit() -> AudioStreamWAV:
	return _make("hit", 0.15, func(t, d, r): return r.randf_range(-1, 1) * exp(-t * 30.0) * 0.5 + sin(t * TAU * 300.0) * _env(t, d) * 0.3)
static func explode() -> AudioStreamWAV:
	return _make("explode", 1.6, func(t, d, r): return (r.randf_range(-1, 1) * 0.9 + sin(t * TAU * (55.0 - t * 25.0)) * 0.8) * exp(-t * 3.0) * 0.95)
static func pickup() -> AudioStreamWAV:
	return _make("pickup", 0.35, func(t, d, r): return sin(t * TAU * (660.0 + t * 1600.0)) * _env(t, d) * 0.35)
static func success() -> AudioStreamWAV:
	return _make("success", 1.5, func(t, d, r):
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var k: int = mini(3, int(t / 0.18))
		var lt: float = t - k * 0.18
		return sin(t * TAU * notes[k]) * exp(-lt * 3.0) * 0.3 + sin(t * TAU * notes[k] * 2.0) * exp(-lt * 6.0) * 0.08)
static func fail() -> AudioStreamWAV:
	return _make("fail", 0.9, func(t, d, r): return sin(t * TAU * (300.0 - t * 200.0)) * _env(t, d) * 0.35)
static func warp() -> AudioStreamWAV:
	return _make("warp", 2.2, func(t, d, r):
		var f: float = 80.0 + pow(t / d, 2.0) * 2400.0
		return (sin(t * TAU * f) * 0.25 + r.randf_range(-1, 1) * 0.15 * (t / d)) * sin(PI * t / d))
static func engine() -> AudioStreamWAV:
	return _make("engine", 1.0, func(t, d, r): return (sin(t * TAU * 55.0) * 0.5 + sin(t * TAU * 110.0) * 0.25 + sin(t * TAU * 165.0) * 0.1 + r.randf_range(-1, 1) * 0.06) * 0.5, true)
static func propeller() -> AudioStreamWAV:
	return _make("prop", 1.0, func(t, d, r): return (sin(t * TAU * 90.0) * 0.3 + r.randf_range(-1, 1) * 0.25) * (0.6 + 0.4 * sin(t * TAU * 24.0)) * 0.5, true)
static func hooves() -> AudioStreamWAV:
	return _make("hoof", 1.0, func(t, d, r):
		var a: float = exp(-fmod(t, 0.25) * 40.0) * (1.0 if fmod(t, 0.5) < 0.25 else 0.7)
		return r.randf_range(-1, 1) * a * 0.35 + sin(t * TAU * 170.0) * a * 0.25, true)
static func wind() -> AudioStreamWAV:
	return _make("wind", 2.0, func(t, d, r): return r.randf_range(-1, 1) * (0.12 + 0.06 * sin(t * TAU * 0.5)), true)
static func click() -> AudioStreamWAV:
	return _make("click", 0.06, func(t, d, r): return sin(t * TAU * 1200.0) * _env(t, d) * 0.3)

## 破壊系（崩落・木の折れる音・瓦・火・大筒・導火線・水しぶき・投擲）
static func crumble() -> AudioStreamWAV:
	return _make("crumble", 2.2, func(t, d, r):
		var rumble: float = sin(t * TAU * (38.0 + 8.0 * sin(t * 3.0))) * 0.55 * exp(-t * 1.2)
		var grit: float = r.randf_range(-1, 1) * (0.35 + 0.3 * absf(sin(t * 23.0 + sin(t * 7.0) * 3.0))) * exp(-t * 1.5)
		return (rumble + grit) * clampf(t / 0.02, 0.0, 1.0) * 0.9)
static func wood_break() -> AudioStreamWAV:
	return _make("woodbreak", 0.9, func(t, d, r):
		var snap: float = r.randf_range(-1, 1) * exp(-t * 18.0) * 0.9
		var crk: float = (r.randf_range(-1, 1) if fmod(t * 47.0, 1.0) < 0.25 else 0.0) * exp(-t * 4.0) * 0.6
		return snap + crk + sin(t * TAU * (180.0 - t * 120.0)) * exp(-t * 9.0) * 0.4)
static func tiles() -> AudioStreamWAV:
	return _make("tiles", 1.6, func(t, d, r):
		var k: float = fmod(t * (9.0 + t * 6.0), 1.0)
		var clack: float = sin(t * TAU * (900.0 + 300.0 * sin(t * 40.0))) * exp(-k * 30.0) * 0.4
		return (clack + r.randf_range(-1, 1) * exp(-k * 25.0) * 0.4) * (1.0 - t / d))
static func fire_loop() -> AudioStreamWAV:
	return _make("fire", 2.0, func(t, d, r):
		var pop: float = r.randf_range(-1, 1) * (0.8 if r.randf() < 0.004 else 0.0)
		return r.randf_range(-1, 1) * (0.14 + 0.08 * sin(t * TAU * 1.5)) + pop, true)
static func cannon() -> AudioStreamWAV:
	return _make("cannon", 1.8, func(t, d, r): return (r.randf_range(-1, 1) * 0.8 + sin(t * TAU * (42.0 - t * 12.0)) * 1.0) * exp(-t * 3.2) * clampf(t / 0.003, 0.0, 1.0))
static func fuse() -> AudioStreamWAV:
	return _make("fuse", 1.0, func(t, d, r): return r.randf_range(-1, 1) * (0.18 + 0.1 * sin(t * TAU * 13.0)), true)
static func splash() -> AudioStreamWAV:
	return _make("splash", 1.8, func(t, d, r): return r.randf_range(-1, 1) * exp(-t * 2.4) * (0.6 + 0.4 * sin(t * TAU * 6.0)) * 0.8 + sin(t * TAU * 70.0) * exp(-t * 6.0) * 0.4)
static func whoosh() -> AudioStreamWAV:
	return _make("whoosh", 0.45, func(t, d, r): return r.randf_range(-1, 1) * sin(PI * t / d) * 0.35)
static func rocket() -> AudioStreamWAV:
	return _make("rocket", 1.0, func(t, d, r): return (r.randf_range(-1, 1) * 0.5 + sin(t * TAU * 240.0) * 0.12) * (0.7 + 0.3 * sin(t * TAU * 31.0)) * 0.6, true)


static func play(tree: SceneTree, s: AudioStream, vol_db := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = vol_db
	tree.root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func play_at(tree: SceneTree, s: AudioStream, pos: Vector3, vol_db := 0.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.unit_size = 12.0
	p.max_distance = 400.0
	var root = tree.current_scene if tree.current_scene else tree.root
	root.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


static func loop_player(host: Node3D, s: AudioStream, vol_db := -6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.unit_size = 10.0
	host.add_child(p)
	return p

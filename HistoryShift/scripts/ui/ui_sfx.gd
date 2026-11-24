class_name UISfx
extends RefCounted
## 合成した簡単な UI 効果音（外部ファイル不要）。UISfx.play("hover"|"click"|"confirm"|"back"|"open"|"mark"|"error"|"success"|"warp"|"tick")

const RATE := 22050
static var _streams := {}
static var _players: Array = []
static var _next := 0
static var enabled := true


static func play(kind: String, volume_db := 0.0) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if _players.is_empty() or not is_instance_valid(_players[0]):
		_players.clear()
		for i in 6:
			var p := AudioStreamPlayer.new()
			p.process_mode = Node.PROCESS_MODE_ALWAYS
			tree.root.add_child.call_deferred(p)
			_players.append(p)
		return
	if not _streams.has(kind):
		_streams[kind] = _make(kind)
	var pl: AudioStreamPlayer = _players[_next % _players.size()]
	_next += 1
	if not pl.is_inside_tree():
		return
	pl.stream = _streams[kind]
	pl.volume_db = volume_db
	pl.play()


static func _make(kind: String) -> AudioStreamWAV:
	var notes: Array = []   # [freq_start, freq_end, dur, amp, noise]
	match kind:
		"hover": notes = [[2400.0, 2600.0, 0.018, 0.05, 0.0]]
		"click": notes = [[880.0, 1320.0, 0.05, 0.18, 0.0]]
		"mark": notes = [[300.0, 180.0, 0.05, 0.10, 0.7]]
		"confirm": notes = [[660.0, 660.0, 0.07, 0.18, 0.0], [990.0, 990.0, 0.12, 0.18, 0.0]]
		"back": notes = [[660.0, 440.0, 0.09, 0.15, 0.0]]
		"open": notes = [[300.0, 900.0, 0.12, 0.08, 0.3]]
		"error": notes = [[220.0, 200.0, 0.12, 0.2, 0.0], [180.0, 160.0, 0.16, 0.2, 0.0]]
		"tick": notes = [[1500.0, 1500.0, 0.02, 0.08, 0.0]]
		"success": notes = [[523.0, 523.0, 0.1, 0.16, 0.0], [659.0, 659.0, 0.1, 0.16, 0.0], [784.0, 784.0, 0.1, 0.16, 0.0], [1046.0, 1046.0, 0.35, 0.16, 0.0]]
		"warp": notes = [[120.0, 1600.0, 1.6, 0.16, 0.5]]
		_: notes = [[800.0, 800.0, 0.04, 0.1, 0.0]]
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for n: Array in notes:
		var f0: float = n[0]; var f1: float = n[1]; var amp: float = n[3]; var nz: float = n[4]
		var count := int(RATE * float(n[2]))
		var phase := 0.0
		for i in count:
			var t := float(i) / count
			var f := lerpf(f0, f1, t)
			phase += TAU * f / RATE
			var env := minf(t * 30.0, 1.0) * pow(1.0 - t, 2.0)
			var s := sin(phase) * (1.0 - nz) + rng.randf_range(-1.0, 1.0) * nz
			var v := int(clampf(s * env * amp, -1.0, 1.0) * 32767.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

class_name SoundKit
extends RefCounted
## 全程序化合成音效：一段 PCM 直接用正弦/噪声算出来，不需要任何音频文件。
## 用法：SoundKit.play("clink", 0.95, -8.0)

const RATE := 22050

static var _cache: Dictionary = {}
static var _players: Array[AudioStreamPlayer] = []
static var _idx := 0
static var enabled := true


static func play(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not enabled:
		return
	if _players.is_empty():
		_ensure()
		return            # 第一次调用只做初始化（延迟入树），不发声
	var stream: AudioStreamWAV = _stream_for(name)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_idx]
	if not p.is_inside_tree():
		return            # 还在延迟入树，这一声先丢掉
	_idx = (_idx + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()


static func _ensure() -> void:
	if not _players.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child.call_deferred(p)
		_players.append(p)


static func _stream_for(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s := PackedFloat32Array()
	match name:
		"clink":
			s = _syn_clink(0.26, 1740.0)
		"hammer":
			s = _syn_clink(0.20, 980.0)
		"splash":
			s = _syn_splash(0.45, 0.22)
		"hiss":
			s = _syn_splash(0.90, 0.62)
		"steam":
			s = _syn_splash(1.40, 0.85)
		"click":
			s = _syn_click()
		"chime":
			s = _syn_chime()
		"plop":
			s = _syn_plop()
		_:
			return null
	_cache[name] = _mk(s)
	return _cache[name]


static func _mk(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 31000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## 金属敲击：几个非谐波正弦 + 起振噪声
static func _syn_clink(dur: float, base: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var ratio := [1.0, 1.58, 2.31, 3.12]
	var amp := [0.55, 0.30, 0.18, 0.10]
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for k in 4:
			v += sin(TAU * base * ratio[k] * t) * amp[k] * exp(-t * (16.0 + float(k) * 10.0))
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 150.0) * 0.55
		# 尾部一点点噪声，像砧子余震
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 22.0) * 0.06
		out[i] = v * 0.55
	return out


## 水/蒸汽：低通噪声 + 包络
static func _syn_splash(dur: float, lp_k: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var env := (1.0 - exp(-t * 300.0)) * exp(-t * (3.2 / dur))
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), lp_k)
		out[i] = lp * env * 0.85
	return out


static func _syn_click() -> PackedFloat32Array:
	var n := int(RATE * 0.055)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		out[i] = sin(TAU * 1250.0 * t) * exp(-t * 120.0) * 0.35
	return out


static func _syn_chime() -> PackedFloat32Array:
	var n := int(RATE * 1.1)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := [880.0, 1320.0, 1760.0]
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for k in 3:
			v += sin(TAU * f[k] * t) * exp(-t * (2.2 + float(k) * 1.2)) * (0.4 - float(k) * 0.1)
		out[i] = v * 0.5
	return out


## 水滴/鱼群惊散："噗通"一声 —— 正弦快速下滑 + 短噪声
static func _syn_plop() -> PackedFloat32Array:
	var n := int(RATE * 0.38)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		# 音高从 ~820Hz 指数滑到 ~240Hz，就是水滴那个"咚"
		var f := 820.0 * exp(-t * 8.5) + 240.0
		phase += TAU * f / float(RATE)
		var env := exp(-t * 8.0) * (1.0 - exp(-t * 260.0))
		var v := sin(phase) * env * 0.75
		# 入水的"滋"：极短低通噪声
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.22
		out[i] = v
	return out

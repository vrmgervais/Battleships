class_name Sfx
extends Node
## Procedurally synthesised sound effects - no audio files needed.

const RATE := 22050

var streams: Dictionary = {}
var players: Array = []
var ambient: AudioStreamPlayer
var enabled := true
var _next := 0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	streams["explosion"] = _to_stream(_explosion(0.9, 1.0, 4.0))
	streams["sunk"] = _to_stream(_sunk())
	streams["splash"] = _to_stream(_splash())
	streams["missile"] = _to_stream(_missile())
	streams["sonar"] = _to_stream(_sonar())
	streams["contact"] = _to_stream(_tones([880.0, 1320.0], 0.08, 12.0, 0.0))
	streams["clear"] = _to_stream(_tones([520.0, 390.0], 0.1, 10.0, 0.0))
	streams["win"] = _to_stream(_tones([523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5], 0.15, 3.5, 0.6))
	streams["lose"] = _to_stream(_tones([392.0, 349.2, 311.1, 261.6], 0.3, 3.0, 0.8))
	streams["alert"] = _to_stream(_tones([988.0, 740.0, 988.0, 740.0], 0.12, 9.0, 0.5))
	streams["error"] = _to_stream(_tones([170.0, 140.0], 0.08, 14.0, 1.0))
	streams["click"] = _to_stream(_tones([1300.0], 0.03, 70.0, 0.0))
	streams["ready"] = _to_stream(_tones([660.0, 880.0], 0.1, 9.0, 0.2))
	streams["place"] = _to_stream(_place())
	ambient = AudioStreamPlayer.new()
	add_child(ambient)
	ambient.stream = _to_stream(_ambient(), true)
	ambient.volume_db = -19.0
	ambient.play()
	ambient.stream_paused = not enabled


func set_enabled(on: bool) -> void:
	enabled = on
	if ambient != null:
		ambient.stream_paused = not on


func play(sound: String, pitch: float = 1.0, vol: float = 0.0) -> void:
	if not enabled or not streams.has(sound):
		return
	var p: AudioStreamPlayer = players[_next]
	_next = (_next + 1) % players.size()
	p.stream = streams[sound]
	p.pitch_scale = pitch
	p.volume_db = vol
	p.play()


# ---------------------------------------------------------------- synthesis

func _buf(n: int) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(n)
	return f


func _noise() -> float:
	return randf() * 2.0 - 1.0


func _to_stream(f: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(f.size() * 2)
	for i in f.size():
		bytes.encode_s16(i * 2, int(clampf(f[i], -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = f.size()
	return s


func _explosion(dur: float, deep: float, decay: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var f := _buf(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := _noise()
		lp += (nz - lp) * 0.22
		lp2 += (lp - lp2) * 0.12
		var env := exp(-t * decay)
		var thump := sin(TAU * 45.0 * deep * t * (1.0 - 0.4 * t)) * exp(-t * decay * 1.2)
		var v := (lp * 1.2 + lp2 * 1.6) * env + thump * 0.7 + nz * 0.3 * exp(-t * 25.0)
		f[i] = clampf(v * 0.85, -1.0, 1.0)
	return f


func _sunk() -> PackedFloat32Array:
	var f := _explosion(2.0, 1.5, 2.2)
	for i in f.size():
		var t := float(i) / RATE
		if t > 0.35:
			var tt := t - 0.35
			var wob := 160.0 + 90.0 * sin(t * 17.0)
			f[i] = clampf(f[i] + sin(TAU * wob * t) * exp(-tt * 2.4) * 0.16, -1.0, 1.0)
	return f


func _splash() -> PackedFloat32Array:
	var n := int(RATE * 0.75)
	var f := _buf(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := _noise()
		lp += (nz - lp) * 0.35
		var hp := nz - lp
		var env := minf(t / 0.015, 1.0) * exp(-t * 6.5)
		var bubble := 0.0
		if t > 0.06:
			bubble = sin(TAU * (500.0 + 1500.0 * t) * t) * exp(-(t - 0.06) * 18.0) * 0.25
		f[i] = hp * env * 0.75 + bubble
	return f


func _missile() -> PackedFloat32Array:
	var dur := 0.65
	var n := int(RATE * dur)
	var f := _buf(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var p := t / dur
		var freq := 2400.0 - 1700.0 * pow(p, 0.8)
		ph += TAU * freq / RATE
		var env := minf(t / 0.06, 1.0)
		if t > dur - 0.04:
			env *= (dur - t) / 0.04
		var nz := _noise()
		lp += (nz - lp) * (0.05 + 0.3 * p)
		f[i] = (sin(ph) * 0.2 + sin(ph * 2.0) * 0.05 + lp * 0.55) * env * (0.5 + 0.5 * p)
	return f


func _ping_tone(t: float) -> float:
	if t < 0.0:
		return 0.0
	var a := minf(t / 0.004, 1.0)
	return (sin(TAU * 1250.0 * t) * exp(-t * 5.0) + sin(TAU * 2500.0 * t) * exp(-t * 9.0) * 0.2) * a


func _sonar() -> PackedFloat32Array:
	var n := int(RATE * 2.0)
	var f := _buf(n)
	for i in n:
		var t := float(i) / RATE
		f[i] = (_ping_tone(t) + 0.45 * _ping_tone(t - 0.55) + 0.2 * _ping_tone(t - 1.1)) * 0.5
	return f


func _place() -> PackedFloat32Array:
	var n := int(RATE * 0.14)
	var f := _buf(n)
	for i in n:
		var t := float(i) / RATE
		var thud := sin(TAU * 150.0 * t * exp(-t * 12.0)) * exp(-t * 28.0)
		f[i] = thud * 0.8 + _noise() * exp(-t * 70.0) * 0.3
	return f


## A sequence of decaying notes. `harsh` mixes in odd harmonics (square-ish).
func _tones(freqs: Array, note: float, decay: float, harsh: float) -> PackedFloat32Array:
	var per := int(RATE * note)
	var tail := per + int(RATE * 0.45)
	var n := per * freqs.size() + int(RATE * 0.5)
	var f := _buf(n)
	for k in freqs.size():
		var fr: float = freqs[k]
		for i in tail:
			var at := k * per + i
			if at >= n:
				break
			var t := float(i) / RATE
			var env := exp(-t * decay) * minf(t / 0.004, 1.0)
			var s := sin(TAU * fr * t)
			s += harsh * (sin(TAU * fr * 3.0 * t) / 3.0 + sin(TAU * fr * 5.0 * t) / 5.0)
			f[at] += s * env * 0.33
	return f


func _ambient() -> PackedFloat32Array:
	var n := RATE * 6
	var cross := 3000
	var raw := _buf(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := _noise()
		lp += (nz - lp) * 0.04
		lp2 += (lp - lp2) * 0.08
		var swell := 0.55 + 0.45 * sin(TAU * t / 6.0 * 2.0)
		raw[i] = (lp * 1.4 + lp2 * 2.2) * swell * 0.55
	var out := _buf(n - cross)
	for i in out.size():
		out[i] = raw[i]
	for i in cross:
		var w := float(i) / cross
		out[i] = raw[i] * w + raw[n - cross + i] * (1.0 - w)
	return out

## Процедурный звук боя: взмах, попадание, точное попадание, звон парирования,
## блок, урон, замах врага, уклонение, гибель врага, победа и фон подземелья.
## Всё синтезируется один раз при запуске, файлов нет. Позже заменим записанными звуками.
extends Node

const RATE := 22050

var streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 77
	streams.swing = _wav(_swing(0.16, 900.0))
	streams.dodge = _wav(_swing(0.24, 500.0))
	streams.hit = _wav(_hit(0.0))
	streams.crit = _wav(_hit(1.0))
	streams.parry = _wav(_ring())
	streams.block = _wav(_block())
	streams.hurt = _wav(_hurt())
	streams.windup = _wav(_windup())
	streams.death = _wav(_death())
	streams.victory = _wav(_victory())
	streams.stun = _wav(_stun())
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	var amb := AudioStreamPlayer.new()
	var wav := _wav(_ambience())
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = wav.data.size() / 2
	amb.stream = wav
	amb.volume_db = -14.0
	add_child(amb)
	amb.play()


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	p.play()


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Свист: шум через простой фильтр с огибающей «вверх-вниз».
func _swing(seconds: float, cutoff: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var lp := 0.0
	var n := b.size()
	for i in n:
		var t := float(i) / n
		var a := clampf(cutoff * (0.5 + t) / RATE * 6.28, 0.0, 1.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * a
		b[i] = lp * sin(t * PI)
	return b


## Удар по телу: глухой низкий толчок + щелчок; точный — с металлическим призвуком.
func _hit(metal: float) -> PackedFloat32Array:
	var b := _buf(0.28)
	for i in b.size():
		var t := float(i) / RATE
		var thump := sin(TAU * (90.0 - 120.0 * t) * t) * exp(-t * 18.0)
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-t * 60.0)
		var ring := (sin(TAU * 1240.0 * t) + 0.6 * sin(TAU * 1873.0 * t)) * exp(-t * 14.0) * metal
		b[i] = thump * 0.9 + crack * 0.5 + ring * 0.35
	return b


## Звон парирования: негармонические частоты, долгий хвост.
func _ring() -> PackedFloat32Array:
	var b := _buf(0.9)
	var freqs := [880.0, 1397.0, 2093.0, 2961.0]
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for k in freqs.size():
			s += sin(TAU * float(freqs[k]) * t) * exp(-t * (4.0 + k * 2.5)) / (1.0 + k)
		s += _rng.randf_range(-1.0, 1.0) * exp(-t * 80.0) * 0.6
		b[i] = s
	return b


func _block() -> PackedFloat32Array:
	var b := _buf(0.3)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 140.0 * t) * exp(-t * 22.0) + _rng.randf_range(-1.0, 1.0) * exp(-t * 35.0) * 0.6 \
			+ sin(TAU * 620.0 * t) * exp(-t * 25.0) * 0.3
	return b


func _hurt() -> PackedFloat32Array:
	var b := _buf(0.35)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * (70.0 - 60.0 * t) * t) * exp(-t * 9.0) + _rng.randf_range(-1.0, 1.0) * exp(-t * 25.0) * 0.4
	return b


## Замах врага: нарастающее шипение.
func _windup() -> PackedFloat32Array:
	var b := _buf(0.5)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / b.size()
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.05 + t * 0.25)
		b[i] = lp * t * t + sin(TAU * (60.0 + 40.0 * t) * float(i) / RATE) * 0.25 * t
	return b


func _stun() -> PackedFloat32Array:
	var b := _buf(0.6)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 520.0 * t) + sin(TAU * 780.0 * t + sin(TAU * 6.0 * t) * 2.0)) * exp(-t * 5.0) * 0.5
	return b


func _death() -> PackedFloat32Array:
	var b := _buf(1.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.04
		b[i] = sin(TAU * (110.0 - 50.0 * t) * t) * exp(-t * 3.0) * 0.6 + lp * exp(-t * 2.5) * 2.0
	return b


func _victory() -> PackedFloat32Array:
	var b := _buf(2.0)
	var notes := [261.6, 329.6, 392.0, 523.3]
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for k in notes.size():
			var start := k * 0.12
			if t >= start:
				var tt := t - start
				s += (sin(TAU * float(notes[k]) * tt) + 0.3 * sin(TAU * float(notes[k]) * 2.0 * tt)) * exp(-tt * 1.6)
		b[i] = s
	return b


## Фон: низкий гул и редкие капли. Длина — целое число периодов, петля без щелчка.
func _ambience() -> PackedFloat32Array:
	var b := _buf(6.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.01
		b[i] = sin(TAU * 55.0 * t) * 0.15 + sin(TAU * 82.5 * t) * 0.08 + lp * 1.5
	for drop_t in [1.3, 3.7, 5.1]:
		var s0 := int(float(drop_t) * RATE)
		for j in 3000:
			if s0 + j < b.size():
				var tt := float(j) / RATE
				b[s0 + j] += sin(TAU * (1800.0 - 9000.0 * tt) * tt) * exp(-tt * 40.0) * 0.25
	return b


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var k := 0.8 / peak
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * k, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav

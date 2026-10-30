extends RefCounted
## Synth: sintetizador de efectos de sonido por DSP.
##
## Todo el audio del juego se genera proceduralmente al arrancar (armas,
## pasos, recargas, explosiones, zombies, ambiente y musica). No se usan
## samples de terceros: el resultado es 100% original y liviano.

class_name Synth

const RATE := 22050

# --- Primitivas ----------------------------------------------------------------


static func alloc(duration: float) -> PackedFloat32Array:
	var frames := int(duration * RATE)
	var buf := PackedFloat32Array()
	buf.resize(frames)
	return buf


static func add_noise(
	buf: PackedFloat32Array,
	start: float,
	duration: float,
	amp: float,
	decay: float,
	cutoff: float,
	seed: int = 1,
	attack: float = 0.001
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s0 := int(start * RATE)
	var n := int(duration * RATE)
	var n_total := buf.size()
	# Coeficiente de filtro paso bajo de un polo.
	var dt := 1.0 / RATE
	var rc := 1.0 / (TAU * maxf(cutoff, 20.0))
	var alpha := dt / (rc + dt)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var idx := s0 + i
		if idx < 0 or idx >= n_total:
			continue
		var t := float(i) / RATE
		var att := minf(1.0, t / maxf(attack, 0.0005))
		var env := exp(-t * decay) * att
		var white := rng.randf_range(-1.0, 1.0)
		lp += alpha * (white - lp)
		lp2 += alpha * (lp - lp2)
		buf[idx] += lp2 * amp * env


static func add_tone(
	buf: PackedFloat32Array,
	start: float,
	duration: float,
	f0: float,
	f1: float,
	amp: float,
	decay: float,
	shape: String = "sine",
	attack: float = 0.002
) -> void:
	var s0 := int(start * RATE)
	var n := int(duration * RATE)
	var n_total := buf.size()
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx < 0 or idx >= n_total:
			continue
		var t := float(i) / RATE
		var k := clampf(t / duration, 0.0, 1.0)
		var f: float = lerpf(f0, f1, k)
		phase += TAU * f / RATE
		var s := 0.0
		match shape:
			"sine":
				s = sin(phase)
			"saw":
				s = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			"square":
				s = signf(sin(phase))
			"tri":
				s = asin(sin(phase)) * 0.6366
		var att := minf(1.0, t / maxf(attack, 0.0005))
		var env := exp(-t * decay) * att
		buf[idx] += s * amp * env


static func add_thump(
	buf: PackedFloat32Array, start: float, amp: float, f0: float, f1: float, dur: float
) -> void:
	add_tone(buf, start, dur, f0, f1, amp, 6.0, "sine", 0.0008)


static func add_click(
	buf: PackedFloat32Array, start: float, amp: float, cutoff: float = 4200.0
) -> void:
	add_noise(buf, start, 0.035, amp, 90.0, cutoff, 7, 0.0002)
	add_tone(buf, start, 0.03, 1800.0, 900.0, amp * 0.35, 120.0, "square", 0.0003)


static func reverb(buf: PackedFloat32Array, delay: float, feedback: float, mix: float) -> void:
	var d := int(delay * RATE)
	var n := buf.size()
	if d <= 0 or d >= n:
		return
	var buffered := PackedFloat32Array()
	buffered.resize(d)
	var idx := 0
	for i in n:
		var wet: float = buffered[idx]
		var out: float = buf[i] + wet * mix
		buffered[idx] = out * feedback
		buf[i] = out
		idx = (idx + 1) % d


static func distort(buf: PackedFloat32Array, drive: float) -> void:
	for i in buf.size():
		buf[i] = clampf(tanh(buf[i] * drive), -1.0, 1.0)


static func normalize(buf: PackedFloat32Array, peak: float = 0.92) -> void:
	var max_abs := 0.0001
	for i in buf.size():
		max_abs = maxf(max_abs, absf(buf[i]))
	var k := peak / max_abs
	for i in buf.size():
		buf[i] = clampf(buf[i] * k, -1.0, 1.0)


static func to_stream(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
	return stream


# --- Armas ---------------------------------------------------------------------

const FIRE_SPECS := {
	"pistol": {"body": 220.0, "crack": 0.62, "dur": 0.16, "decay": 26.0, "tail": 0.10, "gain": 0.9},
	"pistol_heavy":
	{"body": 150.0, "crack": 0.78, "dur": 0.30, "decay": 15.0, "tail": 0.22, "gain": 1.0},
	"smg": {"body": 190.0, "crack": 0.66, "dur": 0.14, "decay": 30.0, "tail": 0.10, "gain": 0.85},
	"rifle": {"body": 140.0, "crack": 0.8, "dur": 0.24, "decay": 18.0, "tail": 0.18, "gain": 0.98},
	"rifle_heavy":
	{"body": 105.0, "crack": 0.9, "dur": 0.34, "decay": 13.0, "tail": 0.24, "gain": 1.0},
	"sniper": {"body": 80.0, "crack": 1.0, "dur": 0.52, "decay": 8.0, "tail": 0.38, "gain": 1.0},
	"shotgun": {"body": 90.0, "crack": 0.95, "dur": 0.42, "decay": 10.0, "tail": 0.30, "gain": 1.0},
	"lmg": {"body": 100.0, "crack": 0.9, "dur": 0.30, "decay": 15.0, "tail": 0.20, "gain": 1.0},
}


static func weapon_fire(family: String, variant: int = 0) -> AudioStreamWAV:
	var spec: Dictionary = FIRE_SPECS.get(family, FIRE_SPECS.rifle)
	var buf := alloc(spec.dur + spec.tail)
	var seed := 1000 + variant * 37 + family.length() * 13
	# Clic de percusor (muy corto y agudo).
	add_noise(buf, 0.0, 0.012, spec.crack * 0.55, 300.0, 9000.0, seed, 0.0002)
	# Cuerpo: ruido filtrado con caida exponencial.
	add_noise(buf, 0.0, spec.dur * 0.7, spec.crack, spec.decay, spec.body * 9.0, seed + 1)
	# Golpe grave.
	add_thump(buf, 0.0, 0.85 * spec.gain, spec.body, spec.body * 0.42, spec.dur * 0.75)
	# Cola de aire.
	add_noise(buf, 0.02, spec.tail, 0.22, 12.0, 1400.0, seed + 2, 0.004)
	add_noise(buf, 0.01, spec.tail * 0.8, 0.12, 9.0, 3400.0, seed + 3, 0.003)
	reverb(buf, 0.075, 0.32, 0.42)
	distort(buf, 1.35)
	normalize(buf, 0.9)
	return to_stream(buf)


static func shotgun_fire(variant: int = 0) -> AudioStreamWAV:
	var buf := alloc(0.55)
	add_noise(buf, 0.0, 0.02, 0.8, 200.0, 7000.0, 40 + variant, 0.0002)
	add_noise(buf, 0.0, 0.35, 1.0, 9.0, 900.0, 41 + variant)
	add_thump(buf, 0.0, 1.0, 110.0, 40.0, 0.4)
	add_noise(buf, 0.18, 0.2, 0.14, 10.0, 2200.0, 42 + variant, 0.01)
	reverb(buf, 0.09, 0.4, 0.5)
	distort(buf, 1.5)
	normalize(buf, 0.95)
	return to_stream(buf)


static func silent_shot() -> AudioStreamWAV:
	var buf := alloc(0.18)
	add_noise(buf, 0.0, 0.05, 0.35, 60.0, 2200.0, 9, 0.0005)
	add_thump(buf, 0.0, 0.5, 180.0, 70.0, 0.12)
	add_click(buf, 0.06, 0.18)
	normalize(buf, 0.6)
	return to_stream(buf)


# --- Mecanica de armas ---------------------------------------------------------


static func draw_weapon() -> AudioStreamWAV:
	var buf := alloc(0.34)
	add_click(buf, 0.0, 0.28, 2600.0)
	add_noise(buf, 0.02, 0.1, 0.2, 35.0, 5200.0, 11)
	add_click(buf, 0.14, 0.32, 3400.0)
	add_noise(buf, 0.16, 0.08, 0.24, 40.0, 2600.0, 12)
	add_tone(buf, 0.02, 0.12, 240.0, 160.0, 0.10, 30.0, "tri")
	normalize(buf, 0.65)
	return to_stream(buf)


static func reload_mag_out() -> AudioStreamWAV:
	var buf := alloc(0.36)
	add_click(buf, 0.0, 0.4, 3000.0)
	add_noise(buf, 0.02, 0.2, 0.22, 22.0, 2000.0, 21)
	add_click(buf, 0.17, 0.3, 1800.0)
	add_tone(buf, 0.02, 0.22, 320.0, 220.0, 0.12, 14.0, "tri", 0.004)
	normalize(buf, 0.7)
	return to_stream(buf)


static func reload_mag_in() -> AudioStreamWAV:
	var buf := alloc(0.4)
	add_noise(buf, 0.0, 0.12, 0.25, 20.0, 1600.0, 31, 0.004)
	add_click(buf, 0.06, 0.5, 2200.0)
	add_click(buf, 0.1, 0.36, 1200.0)
	add_tone(buf, 0.06, 0.25, 180.0, 120.0, 0.28, 16.0, "sine", 0.001)
	add_noise(buf, 0.18, 0.14, 0.2, 24.0, 4200.0, 32, 0.002)
	add_click(buf, 0.24, 0.4, 3400.0)
	normalize(buf, 0.8)
	return to_stream(buf)


static func reload_bolt() -> AudioStreamWAV:
	var buf := alloc(0.5)
	add_click(buf, 0.0, 0.35, 2800.0)
	add_noise(buf, 0.01, 0.16, 0.2, 25.0, 1900.0, 51)
	add_click(buf, 0.18, 0.5, 2100.0)
	add_click(buf, 0.26, 0.42, 3600.0)
	add_tone(buf, 0.18, 0.16, 420.0, 210.0, 0.2, 22.0, "tri", 0.001)
	add_noise(buf, 0.3, 0.16, 0.18, 22.0, 2600.0, 52, 0.004)
	normalize(buf, 0.75)
	return to_stream(buf)


static func pump_shotgun() -> AudioStreamWAV:
	var buf := alloc(0.55)
	add_click(buf, 0.0, 0.3, 2400.0)
	add_noise(buf, 0.04, 0.18, 0.3, 20.0, 1300.0, 61, 0.008)
	add_click(buf, 0.16, 0.55, 2900.0)
	add_noise(buf, 0.2, 0.2, 0.26, 18.0, 1100.0, 62, 0.006)
	add_click(buf, 0.36, 0.42, 3300.0)
	normalize(buf, 0.8)
	return to_stream(buf)


static func empty_click() -> AudioStreamWAV:
	var buf := alloc(0.1)
	add_click(buf, 0.0, 0.5, 5000.0)
	add_click(buf, 0.03, 0.3, 2600.0)
	normalize(buf, 0.55)
	return to_stream(buf)


static func knife_swing() -> AudioStreamWAV:
	var buf := alloc(0.32)
	add_noise(buf, 0.0, 0.26, 0.7, 14.0, 3200.0, 71, 0.06)
	add_noise(buf, 0.02, 0.2, 0.3, 18.0, 900.0, 72, 0.04)
	add_tone(buf, 0.0, 0.2, 900.0, 2200.0, 0.06, 18.0, "sine", 0.03)
	normalize(buf, 0.6)
	return to_stream(buf)


static func knife_hit() -> AudioStreamWAV:
	var buf := alloc(0.26)
	add_noise(buf, 0.0, 0.1, 0.7, 50.0, 1600.0, 81, 0.0005)
	add_thump(buf, 0.0, 0.8, 260.0, 90.0, 0.16)
	add_noise(buf, 0.01, 0.16, 0.2, 26.0, 5200.0, 82, 0.002)
	normalize(buf, 0.8)
	return to_stream(buf)


static func flesh_hit() -> AudioStreamWAV:
	var buf := alloc(0.24)
	add_noise(buf, 0.0, 0.14, 0.9, 34.0, 1100.0, 91, 0.001)
	add_thump(buf, 0.0, 0.7, 190.0, 70.0, 0.12)
	add_noise(buf, 0.02, 0.1, 0.25, 40.0, 2600.0, 92, 0.002)
	normalize(buf, 0.85)
	return to_stream(buf)


static func headshot_ding() -> AudioStreamWAV:
	var buf := alloc(0.34)
	add_tone(buf, 0.0, 0.28, 1480.0, 1460.0, 0.5, 12.0, "sine", 0.001)
	add_tone(buf, 0.0, 0.22, 2220.0, 2200.0, 0.28, 16.0, "sine", 0.001)
	add_noise(buf, 0.0, 0.03, 0.3, 90.0, 8000.0, 93, 0.0002)
	normalize(buf, 0.55)
	return to_stream(buf)


static func wall_hit() -> AudioStreamWAV:
	var buf := alloc(0.22)
	add_noise(buf, 0.0, 0.08, 0.85, 65.0, 4200.0, 101, 0.0003)
	add_noise(buf, 0.01, 0.16, 0.2, 30.0, 1400.0, 102, 0.002)
	add_click(buf, 0.0, 0.25, 2800.0)
	normalize(buf, 0.7)
	return to_stream(buf)


static func ricochet() -> AudioStreamWAV:
	var buf := alloc(0.45)
	add_tone(buf, 0.0, 0.4, 2600.0, 1200.0, 0.4, 9.0, "sine", 0.001)
	add_tone(buf, 0.02, 0.35, 3400.0, 1800.0, 0.2, 11.0, "sine", 0.001)
	add_noise(buf, 0.0, 0.06, 0.4, 70.0, 7000.0, 111, 0.0002)
	reverb(buf, 0.05, 0.3, 0.3)
	normalize(buf, 0.5)
	return to_stream(buf)


static func bullet_whiz() -> AudioStreamWAV:
	var buf := alloc(0.22)
	add_tone(buf, 0.0, 0.2, 1800.0, 600.0, 0.35, 22.0, "sine", 0.02)
	add_noise(buf, 0.0, 0.2, 0.35, 22.0, 3000.0, 121, 0.02)
	normalize(buf, 0.45)
	return to_stream(buf)


static func shell_drop() -> AudioStreamWAV:
	var buf := alloc(0.3)
	for i in 3:
		add_tone(
			buf, i * 0.055, 0.18, 3200.0 - i * 400.0, 2400.0 - i * 300.0, 0.16, 30.0, "sine", 0.0005
		)
		add_noise(buf, i * 0.055, 0.03, 0.12, 90.0, 9000.0, 131 + i, 0.0002)
	normalize(buf, 0.35)
	return to_stream(buf)


static func footstep(variant: int = 0) -> AudioStreamWAV:
	var buf := alloc(0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 141 + variant
	add_noise(buf, 0.0, 0.1, 0.7, 40.0, 900.0 + rng.randf_range(-150, 250), 145 + variant, 0.002)
	add_thump(buf, 0.0, 0.5, 150.0 + rng.randf_range(-20, 20), 60.0, 0.09)
	add_noise(buf, 0.01, 0.07, 0.22, 55.0, 3200.0, 150 + variant, 0.001)
	normalize(buf, 0.42)
	return to_stream(buf)


static func jump() -> AudioStreamWAV:
	var buf := alloc(0.24)
	add_noise(buf, 0.0, 0.14, 0.4, 26.0, 1200.0, 161, 0.01)
	add_tone(buf, 0.0, 0.18, 180.0, 90.0, 0.25, 18.0, "sine", 0.01)
	normalize(buf, 0.4)
	return to_stream(buf)


static func land() -> AudioStreamWAV:
	var buf := alloc(0.28)
	add_thump(buf, 0.0, 0.9, 120.0, 45.0, 0.16)
	add_noise(buf, 0.0, 0.14, 0.55, 28.0, 900.0, 171, 0.001)
	add_noise(buf, 0.02, 0.1, 0.2, 40.0, 2600.0, 172, 0.002)
	normalize(buf, 0.55)
	return to_stream(buf)


# --- Explosivos -----------------------------------------------------------------


static func explosion(duration: float = 1.6) -> AudioStreamWAV:
	var buf := alloc(duration)
	add_noise(buf, 0.0, 0.05, 1.0, 120.0, 8000.0, 181, 0.0002)
	add_noise(buf, 0.0, 0.9, 0.95, 4.0, 700.0, 182)
	add_thump(buf, 0.0, 1.0, 100.0, 28.0, 1.0)
	add_tone(buf, 0.0, 0.5, 70.0, 30.0, 0.7, 5.0, "sine", 0.001)
	add_noise(buf, 0.2, 1.2, 0.3, 2.6, 420.0, 183, 0.05)
	reverb(buf, 0.12, 0.45, 0.6)
	reverb(buf, 0.23, 0.35, 0.4)
	distort(buf, 1.8)
	normalize(buf, 0.98)
	return to_stream(buf)


static func grenade_bounce() -> AudioStreamWAV:
	var buf := alloc(0.16)
	add_tone(buf, 0.0, 0.12, 1100.0, 500.0, 0.3, 30.0, "sine", 0.0005)
	add_noise(buf, 0.0, 0.05, 0.3, 60.0, 4000.0, 191, 0.0003)
	normalize(buf, 0.45)
	return to_stream(buf)


static func grenade_throw() -> AudioStreamWAV:
	var buf := alloc(0.3)
	add_noise(buf, 0.0, 0.24, 0.5, 18.0, 1600.0, 201, 0.03)
	add_tone(buf, 0.0, 0.18, 400.0, 180.0, 0.15, 16.0, "tri", 0.01)
	normalize(buf, 0.5)
	return to_stream(buf)


static func flashbang() -> AudioStreamWAV:
	var buf := alloc(2.2)
	add_noise(buf, 0.0, 0.06, 1.0, 100.0, 12000.0, 211, 0.0001)
	add_thump(buf, 0.0, 1.0, 140.0, 40.0, 0.5)
	add_noise(buf, 0.0, 1.6, 0.25, 2.0, 6000.0, 212, 0.001)
	add_tone(buf, 0.0, 1.8, 3800.0, 3400.0, 0.12, 1.4, "sine", 0.0005)
	reverb(buf, 0.2, 0.5, 0.5)
	normalize(buf, 0.95)
	return to_stream(buf)


static func smoke_pop() -> AudioStreamWAV:
	var buf := alloc(1.4)
	add_noise(buf, 0.0, 0.1, 0.8, 40.0, 2200.0, 221, 0.0005)
	add_noise(buf, 0.05, 1.2, 0.35, 2.2, 1200.0, 222, 0.08)
	add_thump(buf, 0.0, 0.4, 200.0, 80.0, 0.15)
	normalize(buf, 0.6)
	return to_stream(buf)


static func bomb_beep() -> AudioStreamWAV:
	var buf := alloc(0.16)
	add_tone(buf, 0.0, 0.11, 2200.0, 2200.0, 0.5, 14.0, "square", 0.0005)
	add_tone(buf, 0.0, 0.11, 3300.0, 3300.0, 0.2, 16.0, "sine", 0.0005)
	normalize(buf, 0.4)
	return to_stream(buf)


static func bomb_plant() -> AudioStreamWAV:
	var buf := alloc(0.5)
	add_click(buf, 0.0, 0.4, 3000.0)
	add_tone(buf, 0.02, 0.3, 900.0, 400.0, 0.25, 10.0, "square", 0.001)
	add_click(buf, 0.25, 0.35, 2000.0)
	add_noise(buf, 0.26, 0.16, 0.3, 30.0, 2600.0, 231, 0.001)
	normalize(buf, 0.65)
	return to_stream(buf)


static func defuse() -> AudioStreamWAV:
	var buf := alloc(1.0)
	for i in 8:
		add_click(buf, i * 0.11, 0.18, 1800.0 + i * 120.0)
	add_noise(buf, 0.0, 0.8, 0.12, 3.0, 3000.0, 241, 0.02)
	normalize(buf, 0.55)
	return to_stream(buf)


# --- Cuerpos y personajes -------------------------------------------------------


static func body_fall() -> AudioStreamWAV:
	var buf := alloc(0.6)
	add_noise(buf, 0.0, 0.14, 0.7, 22.0, 700.0, 251, 0.002)
	add_thump(buf, 0.02, 1.0, 90.0, 35.0, 0.4)
	add_noise(buf, 0.12, 0.2, 0.2, 20.0, 900.0, 252, 0.01)
	normalize(buf, 0.6)
	return to_stream(buf)


static func death_cry() -> AudioStreamWAV:
	var buf := alloc(0.9)
	# Gemido con formantes; sin samples, solo sintesis.
	add_tone(buf, 0.0, 0.75, 210.0, 95.0, 0.4, 3.4, "saw", 0.02)
	add_tone(buf, 0.0, 0.7, 630.0, 300.0, 0.18, 4.0, "sine", 0.02)
	add_noise(buf, 0.05, 0.6, 0.12, 4.0, 1500.0, 261, 0.02)
	add_noise(buf, 0.5, 0.3, 0.18, 8.0, 800.0, 262, 0.01)
	normalize(buf, 0.5)
	return to_stream(buf)


static func zombie_growl(variant: int = 0) -> AudioStreamWAV:
	var buf := alloc(1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 301 + variant * 17
	var base := 72.0 + rng.randf_range(-14.0, 18.0)
	add_tone(buf, 0.0, 1.3, base, base * 0.72, 0.5, 1.6, "saw", 0.08)
	add_tone(buf, 0.0, 1.3, base * 2.02, base * 1.5, 0.26, 2.0, "saw", 0.1)
	add_noise(buf, 0.0, 1.2, 0.35, 2.0, 800.0, 310 + variant, 0.1)
	# Modulacion de formante (garganta).
	for i in 4:
		add_tone(buf, 0.1 + i * 0.28, 0.2, 300.0 + i * 60.0, 210.0, 0.08, 6.0, "sine", 0.02)
	distort(buf, 1.6)
	reverb(buf, 0.1, 0.3, 0.3)
	normalize(buf, 0.8)
	return to_stream(buf)


static func zombie_attack() -> AudioStreamWAV:
	var buf := alloc(0.6)
	add_noise(buf, 0.0, 0.12, 0.9, 30.0, 2200.0, 321, 0.001)
	add_tone(buf, 0.0, 0.35, 320.0, 120.0, 0.45, 8.0, "saw", 0.005)
	add_noise(buf, 0.05, 0.3, 0.3, 9.0, 900.0, 322, 0.01)
	distort(buf, 1.4)
	normalize(buf, 0.75)
	return to_stream(buf)


static func zombie_death() -> AudioStreamWAV:
	var buf := alloc(0.9)
	add_tone(buf, 0.0, 0.7, 150.0, 50.0, 0.5, 3.0, "saw", 0.01)
	add_noise(buf, 0.0, 0.5, 0.35, 5.0, 700.0, 331, 0.01)
	add_thump(buf, 0.35, 0.7, 80.0, 30.0, 0.35)
	distort(buf, 1.5)
	normalize(buf, 0.7)
	return to_stream(buf)


static func zombie_spawn() -> AudioStreamWAV:
	var buf := alloc(1.0)
	add_tone(buf, 0.0, 0.8, 60.0, 180.0, 0.4, 2.4, "saw", 0.2)
	add_noise(buf, 0.0, 0.8, 0.3, 2.4, 600.0, 341, 0.2)
	reverb(buf, 0.15, 0.4, 0.4)
	normalize(buf, 0.6)
	return to_stream(buf)


static func wave_start() -> AudioStreamWAV:
	var buf := alloc(2.0)
	add_tone(buf, 0.0, 1.6, 55.0, 110.0, 0.5, 1.4, "saw", 0.2)
	add_tone(buf, 0.0, 1.6, 110.0, 220.0, 0.22, 1.4, "tri", 0.2)
	add_noise(buf, 0.0, 1.4, 0.2, 1.8, 500.0, 351, 0.3)
	reverb(buf, 0.2, 0.45, 0.5)
	normalize(buf, 0.65)
	return to_stream(buf)


static func perk() -> AudioStreamWAV:
	var buf := alloc(0.9)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		add_tone(buf, i * 0.1, 0.4, notes[i], notes[i], 0.25, 8.0, "sine", 0.002)
	add_tone(buf, 0.4, 0.4, notes[3], notes[3], 0.1, 6.0, "tri", 0.01)
	normalize(buf, 0.5)
	return to_stream(buf)


# --- Interfaz y partida --------------------------------------------------------


static func ui_click() -> AudioStreamWAV:
	var buf := alloc(0.09)
	add_tone(buf, 0.0, 0.06, 1200.0, 700.0, 0.35, 60.0, "sine", 0.0005)
	add_noise(buf, 0.0, 0.02, 0.15, 120.0, 6000.0, 361, 0.0002)
	normalize(buf, 0.4)
	return to_stream(buf)


static func ui_hover() -> AudioStreamWAV:
	var buf := alloc(0.07)
	add_tone(buf, 0.0, 0.05, 1600.0, 1400.0, 0.18, 80.0, "sine", 0.0005)
	normalize(buf, 0.25)
	return to_stream(buf)


static func buy() -> AudioStreamWAV:
	var buf := alloc(0.35)
	add_tone(buf, 0.0, 0.15, 880.0, 880.0, 0.25, 16.0, "sine", 0.001)
	add_tone(buf, 0.1, 0.2, 1320.0, 1320.0, 0.22, 14.0, "sine", 0.001)
	add_click(buf, 0.0, 0.2, 3000.0)
	normalize(buf, 0.45)
	return to_stream(buf)


static func error() -> AudioStreamWAV:
	var buf := alloc(0.3)
	add_tone(buf, 0.0, 0.22, 220.0, 180.0, 0.4, 10.0, "square", 0.001)
	add_tone(buf, 0.0, 0.2, 110.0, 90.0, 0.2, 10.0, "sine", 0.001)
	normalize(buf, 0.4)
	return to_stream(buf)


static func hitmarker() -> AudioStreamWAV:
	var buf := alloc(0.12)
	add_noise(buf, 0.0, 0.03, 0.4, 100.0, 9000.0, 371, 0.0002)
	add_tone(buf, 0.0, 0.07, 2400.0, 1800.0, 0.2, 45.0, "sine", 0.0005)
	normalize(buf, 0.4)
	return to_stream(buf)


static func round_start() -> AudioStreamWAV:
	var buf := alloc(2.4)
	add_tone(buf, 0.0, 1.2, 98.0, 98.0, 0.35, 2.0, "saw", 0.02)
	add_tone(buf, 0.0, 1.2, 147.0, 147.0, 0.25, 2.0, "sine", 0.02)
	add_tone(buf, 1.1, 0.9, 196.0, 196.0, 0.3, 2.4, "saw", 0.02)
	add_noise(buf, 0.0, 0.9, 0.12, 3.0, 800.0, 381, 0.02)
	reverb(buf, 0.2, 0.4, 0.45)
	normalize(buf, 0.65)
	return to_stream(buf)


static func round_win(good: bool) -> AudioStreamWAV:
	var buf := alloc(2.6)
	var notes := [392.0, 523.25, 659.25, 783.99] if good else [330.0, 293.66, 246.94, 196.0]
	for i in notes.size():
		add_tone(buf, i * 0.26, 0.9, notes[i], notes[i], 0.3, 2.2, "tri", 0.01)
		add_tone(buf, i * 0.26, 0.8, notes[i] * 2.0, notes[i] * 2.0, 0.1, 2.6, "sine", 0.01)
	reverb(buf, 0.18, 0.4, 0.4)
	normalize(buf, 0.6)
	return to_stream(buf)


static func money() -> AudioStreamWAV:
	var buf := alloc(0.3)
	for i in 3:
		add_tone(buf, i * 0.05, 0.2, 2400.0 + i * 300.0, 2000.0, 0.16, 25.0, "sine", 0.0005)
	normalize(buf, 0.35)
	return to_stream(buf)


static func radio_beep() -> AudioStreamWAV:
	var buf := alloc(0.5)
	add_noise(buf, 0.0, 0.02, 0.3, 150.0, 5000.0, 391, 0.0002)
	add_tone(buf, 0.0, 0.1, 1400.0, 1400.0, 0.3, 20.0, "sine", 0.001)
	add_noise(buf, 0.0, 0.18, 0.1, 18.0, 3000.0, 392, 0.002)
	normalize(buf, 0.35)
	return to_stream(buf)


static func flash_ring() -> AudioStreamWAV:
	var buf := alloc(3.0)
	add_tone(buf, 0.0, 2.6, 4200.0, 4100.0, 0.18, 0.7, "sine", 0.01)
	add_tone(buf, 0.0, 2.6, 6100.0, 6000.0, 0.08, 0.9, "sine", 0.01)
	normalize(buf, 0.3)
	return to_stream(buf)


# --- Ambiente y musica ---------------------------------------------------------


static func ambience(kind: String) -> AudioStreamWAV:
	var duration := 10.0
	var buf := alloc(duration)
	match kind:
		"dust":
			add_noise(buf, 0.0, duration, 0.12, -1.0, 380.0, 401, 1.5)
			add_noise(buf, 0.0, duration, 0.05, -1.0, 1800.0, 402, 2.0)
			add_tone(buf, 0.0, duration, 48.0, 52.0, 0.05, -1.0, "sine", 2.0)
		"night":
			add_noise(buf, 0.0, duration, 0.07, -1.0, 260.0, 411, 2.0)
			for i in 12:
				add_tone(
					buf, i * 0.83, 0.05, 3800.0 + (i % 3) * 700.0, 3600.0, 0.05, 70.0, "sine", 0.002
				)
		"industrial":
			add_noise(buf, 0.0, duration, 0.1, -1.0, 220.0, 421, 1.0)
			add_tone(buf, 0.0, duration, 60.0, 60.0, 0.06, -1.0, "saw", 1.0)
			add_tone(buf, 0.0, duration, 120.0, 120.0, 0.03, -1.0, "sine", 1.0)
		"zombie":
			add_noise(buf, 0.0, duration, 0.16, -1.0, 160.0, 431, 1.2)
			add_tone(buf, 0.0, duration, 38.0, 41.0, 0.1, -1.0, "sine", 2.0)
			add_tone(buf, 0.0, duration, 76.0, 79.0, 0.04, -1.0, "tri", 2.0)
	normalize(buf, 0.45)
	return to_stream(buf, true)


static func menu_music() -> AudioStreamWAV:
	var duration := 16.0
	var buf := alloc(duration)
	var chords := [
		[110.0, 164.81, 220.0],
		[98.0, 146.83, 196.0],
		[130.81, 196.0, 261.63],
		[87.31, 130.81, 174.61],
	]
	for c in chords.size():
		var t0 := c * 4.0
		for note in chords[c]:
			add_tone(buf, t0, 4.0, note, note, 0.12, 0.0, "sine", 0.9)
			add_tone(buf, t0, 4.0, note * 2.0, note * 2.0, 0.035, 0.0, "tri", 1.2)
			add_tone(buf, t0, 4.0, note * 0.5, note * 0.5, 0.05, 0.0, "sine", 0.6)
	# Melodia lejana.
	var melody := [440.0, 523.25, 493.88, 392.0, 440.0, 659.25, 523.25, 392.0]
	for i in melody.size():
		add_tone(buf, i * 2.0, 1.8, melody[i], melody[i], 0.045, 0.6, "sine", 0.3)
	# Percusion grave.
	for i in 8:
		add_thump(buf, i * 2.0, 0.18, 70.0, 40.0, 0.3)
	add_noise(buf, 0.0, duration, 0.02, -1.0, 1400.0, 441, 1.0)
	normalize(buf, 0.5)
	return to_stream(buf, true)


static func zombie_music() -> AudioStreamWAV:
	var duration := 12.0
	var buf := alloc(duration)
	add_tone(buf, 0.0, duration, 55.0, 55.0, 0.16, -1.0, "saw", 1.0)
	add_tone(buf, 0.0, duration, 82.5, 82.5, 0.08, -1.0, "tri", 1.0)
	for i in 12:
		add_thump(buf, i * 1.0, 0.16, 62.0, 30.0, 0.16)
	add_noise(buf, 0.0, duration, 0.05, -1.0, 420.0, 451, 1.4)
	for i in 4:
		add_tone(buf, i * 3.0, 1.4, 220.0 + i * 15.0, 180.0 + i * 12.0, 0.03, 0.5, "sine", 0.2)
	normalize(buf, 0.55)
	return to_stream(buf, true)

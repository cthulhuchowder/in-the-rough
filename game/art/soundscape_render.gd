extends SceneTree
## Renders every biome's ambient sounds from filtered noise and simple synthesis (no recordings, so
## no licences): game/audio/ambience/<biome>/<clear name>.wav (16-bit mono, 22.05 kHz; base_* and
## water_* loop seamlessly, the rest are one-shots), and each biome's data/soundscapes/<biome>.tres
## (which file plays how, how often, how far off). Deterministic (fixed seeds). A recording dropped
## in under the same name replaces a sound; re-run to regenerate (it overwrites the .wav files).
## Run: godot --headless --path game -s res://art/soundscape_render.gd

const SR := 22050
const OUT := "res://audio/ambience"

var rng := RandomNumberGenerator.new()
var _made := 0


func _initialize() -> void:
	rng.seed = 7
	_parkland()
	_oasis()
	_underwater()
	_magma()
	_mystic()
	_deep_forest()
	_cemetery()
	print("  %d sounds rendered" % _made)
	quit()


# --- the biomes ---------------------------------------------------------------------------------

func _parkland() -> void:
	var b := "parkland"
	_save(b, "base_breeze", _loop(_wind(20.0, 420.0, 0.6, 0.15, 0.25, 1.0, 0.12), 2.0), 0.7)
	for k in 3:
		_save(b, "songbird_%d" % (k + 1), _songbird(1.4 + 0.3 * k, 2800.0 + 500.0 * k), 0.9)
	_save(b, "lawnmower", _lawnmower(8.0), 0.9)
	_save(b, "water_lapping", _loop(_lapping(14.0), 1.5), 0.7)
	_write_set(b, -14.0, -10.0, [
		_shot(b, ["songbird_1", "songbird_2", "songbird_3"], Vector2(2.5, 7.0), Vector2(20, 55), Vector2(3, 9), -6.0, Vector2(0.92, 1.1)),
		_shot(b, ["lawnmower"], Vector2(45, 90), Vector2(120, 150), Vector2(0, 1), -4.0, Vector2(0.95, 1.05))])


func _oasis() -> void:
	var b := "oasis"
	_save(b, "base_hot_wind", _loop(_add(_wind(20.0, 650.0, 0.6, 0.12, 0.3, 1.0, 0.22), _scale(_highpass(_noise(20.0), 3500.0), 0.05)), 2.0), 0.7)
	_save(b, "gust", _gust(3.5), 0.9)
	_save(b, "cicadas", _cicadas(5.0), 0.8)
	_save(b, "hawk_cry", _hawk(1.6), 0.9)
	_save(b, "water_lapping", _loop(_lapping(14.0), 1.5), 0.7)
	_write_set(b, -13.0, -12.0, [
		_shot(b, ["gust"], Vector2(6, 14), Vector2(10, 25), Vector2(1, 4), -8.0, Vector2(0.85, 1.15)),
		_shot(b, ["cicadas"], Vector2(4, 10), Vector2(15, 40), Vector2(1, 5), -10.0, Vector2(0.95, 1.05)),
		_shot(b, ["hawk_cry"], Vector2(25, 60), Vector2(50, 100), Vector2(25, 50), -6.0, Vector2(0.92, 1.06))])


func _underwater() -> void:
	var b := "underwater"
	_save(b, "base_drone", _loop(_drone(20.0), 2.0), 0.7)
	_save(b, "bubble_stream", _bubbles(2.8, 36, Vector2(500, 1600), Vector2(0.02, 0.06)), 0.85)
	_save(b, "whale_moan", _whale(6.0), 0.9)
	_save(b, "creak", _lowpass(_creak(2.4, Vector2(22, 60), [320.0, 700.0], 6.0), 1200.0), 0.85)
	_save(b, "water_bubbling", _loop(_add(_bubbles(14.0, 220, Vector2(350, 1400), Vector2(0.02, 0.07)), _scale(_lowpass(_brown(14.0), 160.0), 0.4)), 1.5), 0.7)
	_write_set(b, -11.0, -10.0, [
		_shot(b, ["bubble_stream"], Vector2(3, 8), Vector2(6, 20), Vector2(0, 3), -10.0, Vector2(0.85, 1.2)),
		_shot(b, ["whale_moan"], Vector2(25, 55), Vector2(80, 140), Vector2(5, 20), -5.0, Vector2(0.85, 1.1)),
		_shot(b, ["creak"], Vector2(12, 30), Vector2(25, 60), Vector2(0, 4), -8.0, Vector2(0.8, 1.1))])


func _magma() -> void:
	var b := "magma"
	_save(b, "base_rumble", _loop(_rumble(20.0), 2.0), 0.75)
	_save(b, "lava_crackle", _crackle(2.6, 45.0), 0.85)
	_save(b, "lava_pop", _pop(0.8, 140.0), 0.9)
	_save(b, "steam_hiss", _hiss(2.4), 0.8)
	_save(b, "water_lava_bubbling", _loop(_lava_bubbling(14.0), 1.5), 0.75)
	_write_set(b, -9.0, -8.0, [
		_shot(b, ["lava_crackle"], Vector2(2, 6), Vector2(10, 35), Vector2(0, 1), -10.0, Vector2(0.85, 1.15)),
		_shot(b, ["lava_pop"], Vector2(3, 9), Vector2(10, 40), Vector2(0, 1), -8.0, Vector2(0.75, 1.25)),
		_shot(b, ["steam_hiss"], Vector2(10, 24), Vector2(15, 45), Vector2(0, 2), -10.0, Vector2(0.9, 1.1))])


func _mystic() -> void:
	var b := "mystic_forest"
	_save(b, "base_shimmer", _loop(_shimmer(20.0), 2.0), 0.6)
	for k in 3:
		_save(b, "chime_%d" % (k + 1), _chime(3.6, [880.0, 1046.5, 1174.7, 1318.5, 1568.0][k + 1], [880.0, 1318.5, 1568.0][k]), 0.85)
	_save(b, "odd_hoot", _odd_hoot(1.8), 0.9)
	_save(b, "water_brook", _loop(_brook(14.0), 1.5), 0.7)
	_write_set(b, -15.0, -8.0, [
		_shot(b, ["chime_1", "chime_2", "chime_3"], Vector2(5, 12), Vector2(10, 35), Vector2(2, 8), -9.0, Vector2(0.95, 1.05)),
		_shot(b, ["odd_hoot"], Vector2(15, 35), Vector2(30, 70), Vector2(4, 12), -7.0, Vector2(0.85, 1.2))])


func _deep_forest() -> void:
	var b := "deep_forest"
	_save(b, "base_canopy_wind", _loop(_add(_wind(20.0, 380.0, 0.5, 0.07, 0.25, 1.0, 0.0), _scale(_mul(_highpass(_noise(20.0), 3500.0), _drift(20.0, 0.4, 0.1, 1.0)), 0.12)), 2.0), 0.7)
	_save(b, "trunk_creak", _creak(2.8, Vector2(12, 35), [220.0, 480.0], 8.0), 0.85)
	_save(b, "woodpecker", _woodpecker(1.5), 0.9)
	_save(b, "distant_owl", _owl(2.4), 0.85)
	_save(b, "water_lapping", _loop(_lapping(14.0), 1.5), 0.7)
	_write_set(b, -13.0, -11.0, [
		_shot(b, ["trunk_creak"], Vector2(10, 25), Vector2(15, 40), Vector2(2, 8), -8.0, Vector2(0.85, 1.15)),
		_shot(b, ["woodpecker"], Vector2(14, 35), Vector2(30, 70), Vector2(4, 12), -8.0, Vector2(0.92, 1.08)),
		_shot(b, ["distant_owl"], Vector2(25, 60), Vector2(60, 120), Vector2(6, 15), -8.0, Vector2(0.95, 1.05))])


func _cemetery() -> void:
	var b := "cemetery"
	_save(b, "base_cold_wind", _loop(_cold_wind(20.0), 2.0), 0.7)
	var caw := PlaceholderSounds.caw()
	_save(b, "crow", _from_wav(caw), 0.9)
	_save(b, "gate_creak", _creak(2.6, Vector2(40, 110), [1100.0, 2300.0], 12.0), 0.8)
	_save(b, "faint_howl", _howl(4.5), 0.85)
	_save(b, "church_bell", _bell(7.0, 196.0), 0.85)
	_save(b, "water_bog", _loop(_bog(14.0), 1.5), 0.7)
	_write_set(b, -12.0, -9.0, [
		_shot(b, ["crow"], Vector2(10, 25), Vector2(25, 60), Vector2(4, 12), -8.0, Vector2(0.85, 1.1)),
		_shot(b, ["gate_creak"], Vector2(20, 45), Vector2(25, 60), Vector2(0, 2), -9.0, Vector2(0.9, 1.1)),
		_shot(b, ["faint_howl"], Vector2(35, 80), Vector2(110, 150), Vector2(0, 5), -6.0, Vector2(0.92, 1.05)),
		_shot(b, ["church_bell"], Vector2(50, 110), Vector2(120, 150), Vector2(15, 30), -6.0, Vector2(0.98, 1.02))])


# --- the sounds -----------------------------------------------------------------------------------

## Wind: band-passed noise swelling slowly (`rate` Hz, `lo`..`hi`), with leaves (`leaves` of high hiss).
func _wind(seconds: float, hz: float, q: float, rate: float, lo: float, hi: float, leaves: float) -> PackedFloat32Array:
	var body := _mul(_bandpass(_noise(seconds), hz, q), _drift(seconds, rate, lo, hi))
	if leaves > 0.0:
		body = _add(body, _scale(_mul(_highpass(_noise(seconds), 2800.0), _drift(seconds, rate * 3.0, 0.1, 1.0)), leaves))
	return body


func _songbird(seconds: float, centre: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	var t := 0.05
	while t < seconds - 0.2:
		var trill := rng.randf() < 0.3
		var count := rng.randi_range(4, 8) if trill else 1
		var f0 := centre * rng.randf_range(0.8, 1.3)
		var sweep := rng.randf_range(-1400.0, 1400.0)
		for c in count:
			var dur := rng.randf_range(0.025, 0.05) if trill else rng.randf_range(0.06, 0.14)
			_chirp(out, t, dur, f0, sweep, rng.randf_range(0.5, 1.0))
			t += dur + (0.012 if trill else 0.0)
		t += rng.randf_range(0.06, 0.25)
	return _highpass(out, 1500.0)


## One bird note: a fast sine sweep with a flutter, sin² window.
func _chirp(out: PackedFloat32Array, at: float, dur: float, f0: float, sweep: float, amp: float) -> void:
	var start := int(at * SR)
	var n := int(dur * SR)
	var phase := 0.0
	var flutter := rng.randf_range(25.0, 60.0)
	for i in n:
		if start + i >= out.size():
			return
		var u := float(i) / n
		var f := f0 + sweep * u + 180.0 * sin(TAU * flutter * i / SR)
		phase += f / SR
		var w := sin(PI * u)
		out[start + i] += sin(TAU * phase) * w * w * amp


func _lawnmower(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var drift := _drift(seconds, 0.3, -1.0, 1.0)
	for i in n:
		var t := float(i) / SR
		var f := 31.0 + 3.0 * drift[i]
		phase += f / SR
		var saw := 0.0
		for k in range(1, 13):
			saw += sin(TAU * phase * k) / k
		var chug := 0.75 + 0.25 * sin(TAU * 7.3 * t)
		out[i] = saw * chug * minf(minf(t / 2.5, (seconds - t) / 2.5), 1.0)
	return _lowpass(_lowpass(_add(out, _scale(_lowpass(_noise(seconds), 900.0), 0.4)), 600.0), 420.0) # (far off: the top end gone)


func _gust(seconds: float) -> PackedFloat32Array:
	var low := _bandpass(_noise(seconds), 500.0, 0.7)
	var high := _bandpass(_noise(seconds), 1500.0, 0.8)
	var n := low.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var u := float(i) / n
		var swell := pow(sin(PI * u), 1.6)
		out[i] = (low[i] * (1.0 - u) + high[i] * u * 0.8) * swell
	return out


func _cicadas(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	for voice in [[4500.0, 112.0], [5300.0, 131.0]]:
		var tone := _bandpass(_noise(seconds), voice[0], 8.0)
		for i in out.size():
			var t := float(i) / SR
			var pulse := pow(absf(sin(PI * voice[1] * t)), 4.0)
			out[i] += tone[i] * pulse * pow(sin(PI * t / seconds), 1.5)
	return out


func _hawk(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var u := float(i) / n
		var f := 3300.0 - 1500.0 * u + 70.0 * sin(TAU * 24.0 * i / SR)
		phase += f / SR
		var env := minf(u / 0.06, 1.0) * pow(1.0 - u, 1.4)
		out[i] = (sin(TAU * phase) + 0.3 * sin(TAU * phase * 2.0)) * env
	return _add(out, _scale(_mul(_bandpass(_noise(seconds), 3000.0, 2.0), _envelope(n, 0.06, 1.4)), 0.25))


func _drone(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	var swell := _drift(seconds, 0.06, 0.5, 1.0)
	for i in out.size():
		var t := float(i) / SR
		out[i] = (sin(TAU * 41.0 * t) + sin(TAU * 43.4 * t) + 0.5 * sin(TAU * 62.0 * t)) * 0.3 * swell[i]
	return _lowpass(_add(out, _scale(_mul(_lowpass(_brown(seconds), 180.0), _drift(seconds, 0.08, 0.4, 1.0)), 1.2)), 320.0)


## Bubbles: `count` little rising blips, frequencies `f`, lengths `dur`.
func _bubbles(seconds: float, count: int, f: Vector2, dur: Vector2) -> PackedFloat32Array:
	var out := _zeros(seconds)
	for k in count:
		var start := int(rng.randf_range(0.0, seconds - dur.y) * SR)
		var n := int(rng.randf_range(dur.x, dur.y) * SR)
		var f0 := rng.randf_range(f.x, f.y)
		var amp := rng.randf_range(0.3, 1.0)
		var phase := 0.0
		for i in n:
			var u := float(i) / n
			phase += f0 * (1.0 + 2.5 * u) / SR
			out[start + i] += sin(TAU * phase) * exp(-u * 4.0) * minf(u * 30.0, 1.0) * amp
	return out


func _whale(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var u := float(i) / n
		var path := 160.0 + 150.0 * sin(PI * minf(u / 0.6, 1.0)) - 30.0 * maxf(u - 0.6, 0.0) / 0.4
		phase += (path + 6.0 * sin(TAU * 4.0 * i / SR)) / SR
		out[i] = (sin(TAU * phase) + 0.4 * sin(TAU * phase * 2.0) + 0.2 * sin(TAU * phase * 3.0)) * pow(sin(PI * u), 0.8)
	return _lowpass(out, 900.0)


## Stick-slip friction: a train of clicks, its rate gliding through `rate` and back, ringing
## resonators at `res` (Q `q`) — a creaking trunk, a hull, a gate's hinge.
func _creak(seconds: float, rate: Vector2, res: Array, q: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var clicks := PackedFloat32Array()
	clicks.resize(n)
	var next := 0.0
	while next < n:
		var u := next / n
		clicks[int(next)] = rng.randf_range(0.5, 1.0) * sin(PI * u)
		next += SR / lerpf(rate.x, rate.y, sin(PI * u))
	var out := PackedFloat32Array()
	out.resize(n)
	for f in res:
		out = _add(out, _bandpass(clicks, f, q))
	return out


func _rumble(seconds: float) -> PackedFloat32Array:
	var out := _mul(_lowpass(_brown(seconds), 70.0), _drift(seconds, 0.15, 0.5, 1.0))
	for i in out.size():
		out[i] = out[i] * 1.5 + 0.25 * sin(TAU * 28.0 * i / SR)
	return _add(out, _scale(_mul(_lowpass(_noise(seconds), 300.0), _drift(seconds, 0.3, 0.0, 1.0)), 0.15))


func _crackle(seconds: float, per_second: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	var t := 0.0
	while t < seconds - 0.02:
		var start := int(t * SR)
		var n := int(rng.randf_range(0.003, 0.009) * SR)
		var amp := pow(rng.randf(), 2.0)
		for i in n:
			out[start + i] += rng.randf_range(-1.0, 1.0) * exp(-float(i) / n * 5.0) * amp
		t += rng.randf_range(0.2, 1.8) / per_second
	return _mul(_highpass(out, 1500.0), _envelope(out.size(), 0.1, 1.0))


func _pop(seconds: float, f0: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		phase += (f0 * exp(-t * 6.0) + 50.0) / SR
		out[i] = sin(TAU * phase) * exp(-t * 9.0) + (rng.randf_range(-1.0, 1.0) * exp(-t * 600.0) * 0.6)
	return out


func _hiss(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	return _mul(_mul(_bandpass(_highpass(_noise(seconds), 2500.0), 5000.0, 0.7), _envelope(n, 0.03, 1.2)), _drift(seconds, 6.0, 0.6, 1.0))


func _lava_bubbling(seconds: float) -> PackedFloat32Array:
	var out := _scale(_lowpass(_brown(seconds), 120.0), 1.2)
	for k in 14:
		var pop := _pop(0.5, rng.randf_range(80.0, 160.0))
		var at := int(rng.randf_range(0.0, seconds - 0.6) * SR)
		for i in pop.size():
			out[at + i] += pop[i] * rng.randf_range(0.3, 0.7) if i == 0 else pop[i] * 0.5
	return _add(out, _scale(_crackle(seconds, 12.0), 0.3))


func _shimmer(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	for f in [1318.5, 1760.0, 1975.5, 2637.0, 2960.0, 3520.0]:
		var level := _drift(seconds, rng.randf_range(0.08, 0.25), 0.0, 1.0)
		for i in out.size():
			out[i] += sin(TAU * f * i / SR) * level[i] * level[i] * 0.15
	for i in out.size():
		out[i] += (sin(TAU * 220.0 * i / SR) + sin(TAU * 330.0 * i / SR)) * 0.05
	return _add(out, _scale(_mul(_bandpass(_noise(seconds), 7000.0, 1.0), _drift(seconds, 0.2, 0.2, 1.0)), 0.25))


## A wind chime: two struck notes, bell-like partials ringing down.
func _chime(seconds: float, f1: float, f2: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	for note in [[f1, 0.0], [f2, rng.randf_range(0.25, 0.6)]]:
		var start := int(note[1] * SR)
		for p in [[1.0, 1.0, 2.5], [2.0, 0.5, 1.5], [2.76, 0.35, 1.0], [5.4, 0.15, 0.5]]:
			for i in range(start, out.size()):
				var t := float(i - start) / SR
				out[i] += sin(TAU * note[0] * p[0] * t) * p[1] * exp(-t / p[2] * 2.0) * minf(t * 2000.0, 1.0)
	return out


func _odd_hoot(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	_hoo(out, 0.05, 0.25, 330.0, 330.0, 6.0, 8.0)
	_hoo(out, 0.45, 0.6, 440.0, 380.0, 6.0, 8.0)
	return _add(out, _scale(_mul(_bandpass(_noise(seconds), 420.0, 2.0), _envelope(out.size(), 0.1, 1.0)), 0.08))


## One hooted note at `at` for `dur`: a soft sine from `f_from` to `f_to`, wobbling by `depth` Hz at `wobble` Hz.
func _hoo(out: PackedFloat32Array, at: float, dur: float, f_from: float, f_to: float, wobble: float, depth: float) -> void:
	var start := int(at * SR)
	var n := int(dur * SR)
	var phase := 0.0
	for i in n:
		if start + i >= out.size():
			return
		var u := float(i) / n
		phase += (lerpf(f_from, f_to, u) + depth * sin(TAU * wobble * i / SR)) / SR
		out[start + i] += (sin(TAU * phase) + 0.15 * sin(TAU * phase * 3.0)) * pow(sin(PI * u), 0.7)


func _brook(seconds: float) -> PackedFloat32Array:
	var babble := _bubbles(seconds, int(seconds * 55.0), Vector2(700, 2500), Vector2(0.01, 0.04))
	return _lowpass(_add(_scale(babble, 0.6), _scale(_mul(_bandpass(_noise(seconds), 1800.0, 1.0), _drift(seconds, 0.7, 0.5, 1.0)), 0.5)), 6000.0)


func _woodpecker(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	var t := 0.05
	var count := rng.randi_range(14, 20)
	for k in count:
		var start := int(t * SR)
		var amp := 1.0 - 0.5 * float(k) / count
		for i in int(0.03 * SR):
			var s := float(i) / SR
			out[start + i] += (sin(TAU * 1100.0 * s) * exp(-s * 160.0) + rng.randf_range(-1.0, 1.0) * exp(-s * 900.0) * 0.5) * amp
		t += 0.05 + 0.012 * float(k) / count
	return _lowpass(out, 4000.0)


func _owl(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	_hoo(out, 0.1, 0.4, 370.0, 360.0, 3.0, 2.0)
	_hoo(out, 0.85, 0.22, 390.0, 385.0, 3.0, 2.0)
	_hoo(out, 1.15, 0.45, 375.0, 350.0, 3.0, 2.0)
	return _lowpass(_add(out, _scale(_mul(_bandpass(_noise(seconds), 400.0, 2.0), _envelope(out.size(), 0.1, 1.0)), 0.06)), 1500.0)


func _cold_wind(seconds: float) -> PackedFloat32Array:
	var out := _wind(seconds, 300.0, 0.5, 0.09, 0.3, 1.0, 0.05)
	for f in [760.0, 1020.0]: # a thin whistle through the railings
		out = _add(out, _scale(_mul(_bandpass(_noise(seconds), f, 18.0), _drift(seconds, 0.07, 0.0, 1.0)), 2.5))
	return out


func _howl(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var u := float(i) / n
		var f := 380.0 + 270.0 * minf(u / 0.15, 1.0) - 230.0 * maxf(u - 0.7, 0.0) / 0.3
		phase += (f + 10.0 * sin(TAU * 5.0 * i / SR) * minf(u / 0.2, 1.0)) / SR
		out[i] = (sin(TAU * phase) + 0.25 * sin(TAU * phase * 2.0) + 0.1 * sin(TAU * phase * 3.0)) * pow(sin(PI * u), 0.6)
	return _lowpass(_bandpass(out, 800.0, 0.5), 1500.0)


## A church bell far off: its partials (hum, prime, tierce, quint, nominal…) ringing down at their
## own rates, a faint echo, the top end softened by distance.
func _bell(seconds: float, f0: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	for p in [[0.5, 0.4, 5.0], [1.0, 0.8, 3.5], [1.19, 0.5, 2.5], [1.5, 0.3, 2.0], [2.0, 0.6, 1.6], [2.5, 0.25, 1.0], [3.0, 0.15, 0.8]]:
		for i in out.size():
			var t := float(i) / SR
			out[i] += sin(TAU * f0 * p[0] * t) * p[1] * exp(-t / p[2] * 2.0) * minf(t * 1500.0, 1.0)
	var echo := int(0.11 * SR)
	for i in range(out.size() - 1, echo, -1):
		out[i] += out[i - echo] * 0.3
	return _lowpass(out, 2500.0)


func _lapping(seconds: float) -> PackedFloat32Array:
	var body := _lowpass(_noise(seconds), 500.0)
	var splash := _highpass(_noise(seconds), 2000.0)
	var out := _scale(_lowpass(_noise(seconds), 200.0), 0.3)
	var t := 0.2
	while t < seconds - 2.0:
		var start := int(t * SR)
		var n := int(rng.randf_range(1.4, 2.0) * SR)
		var peak := rng.randf_range(0.3, 0.4)
		for i in n:
			var u := float(i) / n
			var swell := pow(sin(PI * minf(u / peak, 1.0) * 0.5), 2.0) * (1.0 if u < peak else exp(-(u - peak) * 3.0))
			out[start + i] += body[start + i] * swell * 1.5 + splash[start + i] * swell * swell * 0.25
		t += rng.randf_range(1.8, 3.0)
	return out


func _bog(seconds: float) -> PackedFloat32Array:
	var out := _scale(_mul(_lowpass(_noise(seconds), 300.0), _drift(seconds, 0.2, 0.3, 1.0)), 0.4)
	return _add(out, _bubbles(seconds, 11, Vector2(120, 350), Vector2(0.08, 0.2)))


# --- DSP --------------------------------------------------------------------------------------------

func _zeros(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * SR))
	return out


func _noise(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	for i in out.size():
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## Brown noise: white noise integrated, leaking back to zero (a deep, soft roar).
func _brown(seconds: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	var y := 0.0
	for i in out.size():
		y = y * 0.998 + rng.randf_range(-1.0, 1.0) * 0.06
		out[i] = y
	return out


## A slow random wander between `lo` and `hi`, a new target about `rate` times a second, eased.
func _drift(seconds: float, rate: float, lo: float, hi: float) -> PackedFloat32Array:
	var out := _zeros(seconds)
	var step := maxi(int(SR / rate), 1)
	var a := rng.randf_range(lo, hi)
	var b := rng.randf_range(lo, hi)
	for i in out.size():
		if i % step == 0 and i > 0:
			a = b
			b = rng.randf_range(lo, hi)
		var u := float(i % step) / step
		out[i] = lerpf(a, b, 0.5 - 0.5 * cos(PI * u))
	return out


## Linear in over `attack` (fraction), then down as (1 − u)^`fall`.
func _envelope(n: int, attack: float, fall: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var u := float(i) / n
		out[i] = minf(u / attack, 1.0) * pow(1.0 - u, fall)
	return out


static func _lowpass(x: PackedFloat32Array, hz: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * hz / SR)
	var y := 0.0
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		y += a * (x[i] - y)
		out[i] = y
	return out


static func _highpass(x: PackedFloat32Array, hz: float) -> PackedFloat32Array:
	var low := _lowpass(x, hz)
	for i in low.size():
		low[i] = x[i] - low[i]
	return low


## A band-pass biquad (RBJ, 0 dB peak) at `hz`, quality `q`.
static func _bandpass(x: PackedFloat32Array, hz: float, q: float) -> PackedFloat32Array:
	var w := TAU * hz / SR
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var b2 := -alpha / a0
	var a1 := -2.0 * cos(w) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		var y := b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = y
		out[i] = y
	return out


static func _add(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	for i in mini(a.size(), b.size()):
		out[i] += b[i]
	return out


static func _mul(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	for i in mini(a.size(), b.size()):
		out[i] *= b[i]
	return out


static func _scale(a: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var out := a.duplicate()
	for i in out.size():
		out[i] *= k
	return out


## Seamless loop: the last `fade` seconds cross-fade into the start (equal power), so the end runs on
## into the beginning with no click; the result is `fade` shorter.
static func _loop(x: PackedFloat32Array, fade: float) -> PackedFloat32Array:
	var f := int(fade * SR)
	var n := x.size() - f
	var out := x.slice(0, n)
	for i in f:
		var u := float(i) / f
		out[i] = x[i] * sin(u * PI * 0.5) + x[n + i] * cos(u * PI * 0.5)
	return out


static func _from_wav(wav: AudioStreamWAV) -> PackedFloat32Array:
	var data := wav.data
	var out := PackedFloat32Array()
	out.resize(data.size() / 2)
	for i in out.size():
		out[i] = data.decode_s16(i * 2) / 32768.0
	return out


## Normalised to `peak`, a short fade at each end of a one-shot (no clicks), saved as 16-bit WAV.
func _save(biome: String, name: String, x: PackedFloat32Array, peak: float) -> void:
	var top := 0.0
	for v in x:
		top = maxf(top, absf(v))
	var k := peak / maxf(top, 1e-6)
	var looped := name.begins_with("base_") or name.begins_with("water_")
	var edge := 0 if looped else int(0.01 * SR)
	var bytes := PackedByteArray()
	bytes.resize(x.size() * 2)
	for i in x.size():
		var fade := 1.0 if edge == 0 else minf(minf(float(i) / edge, float(x.size() - 1 - i) / edge), 1.0)
		bytes.encode_s16(i * 2, clampi(int(x[i] * k * fade * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [OUT, biome]))
	wav.save_to_wav(ProjectSettings.globalize_path("%s/%s/%s.wav" % [OUT, biome, name]))
	_made += 1


# --- the soundscape resources -------------------------------------------------------------------------

func _shot(biome: String, names: Array, interval: Vector2, distance: Vector2, height: Vector2, db: float, pitch: Vector2) -> Dictionary:
	return {biome = biome, names = names, interval = interval, distance = distance, height = height, db = db, pitch = pitch}


## data/soundscapes/<biome>.tres: the base and water loops (base_*, water_* in its folder) and the shots.
func _write_set(biome: String, base_db: float, water_db: float, shots: Array) -> void:
	var folder := "%s/%s" % [OUT, biome]
	var files := DirAccess.get_files_at(ProjectSettings.globalize_path(folder))
	var base := ""
	var water := ""
	for f in files:
		if f.ends_with(".wav") and f.begins_with("base_"):
			base = f
		elif f.ends_with(".wav") and f.begins_with("water_"):
			water = f
	var ext := ['[ext_resource type="Script" path="res://scripts/soundscape_set.gd" id="set"]',
		'[ext_resource type="Script" path="res://scripts/soundscape_shot.gd" id="shot"]',
		'[ext_resource type="AudioStream" path="%s/%s" id="base"]' % [folder, base],
		'[ext_resource type="AudioStream" path="%s/%s" id="water"]' % [folder, water]]
	var subs := []
	var ids := []
	for k in shots.size():
		var s: Dictionary = shots[k]
		var streams := []
		for name in s.names:
			var id := "%s_%d" % [name, k]
			ext.append('[ext_resource type="AudioStream" path="%s/%s.wav" id="%s"]' % [folder, name, id])
			streams.append('ExtResource("%s")' % id)
		subs.append('[sub_resource type="Resource" id="shot_%d"]\nscript = ExtResource("shot")\nstreams = Array[AudioStream]([%s])\ninterval = Vector2(%s, %s)\ndistance = Vector2(%s, %s)\nheight = Vector2(%s, %s)\nvolume_db = %s\npitch = Vector2(%s, %s)\n' % [
			k, ", ".join(streams), s.interval.x, s.interval.y, s.distance.x, s.distance.y, s.height.x, s.height.y, s.db, s.pitch.x, s.pitch.y])
		ids.append('SubResource("shot_%d")' % k)
	var text := '[gd_resource type="Resource" script_class="SoundscapeSet" format=3]\n\n%s\n\n%s\n[resource]\nscript = ExtResource("set")\nbase = ExtResource("base")\nbase_db = %s\nwater = ExtResource("water")\nwater_db = %s\nshots = Array[SoundscapeShot]([%s])\n' % [
		"\n".join(ext), "\n".join(subs), base_db, water_db, ", ".join(ids)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/soundscapes"))
	var f := FileAccess.open("res://data/soundscapes/%s.tres" % biome, FileAccess.WRITE)
	f.store_string(text)
	f.close()

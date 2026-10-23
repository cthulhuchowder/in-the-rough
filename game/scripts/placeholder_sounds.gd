class_name PlaceholderSounds
## Synthesised comedy sounds, to be replaced with recorded ones later: a swish for a whiff, applause
## for a hole-in, the fish slap, the squeak, the goose honk, clown steps, crows. (Hits, landings, the
## cup, the interface and coins are Kenney recordings: data/sounds.tres.)
## Deterministic (integer-hash noise), 16-bit mono.

const RATE := 22050


static func swish() -> AudioStreamWAV:
	var low := [0.0]
	return _make(0.32, func(t: float, n: float):
		var cut := 0.08 + 0.25 * sin(PI * t / 0.32) # brighter mid-swish
		low[0] += (n - low[0]) * cut
		var env := sin(PI * t / 0.32)
		return low[0] * env * env * 0.9)


## Hole-in applause, by the result against par (> 0 over, 0 par, −1 birdie, ≤ −2 eagle): a crowd of
## hand claps (short band-limited noise bursts at hashed times, denser and longer the better the
## score), and for an eagle a cheering roar and a few rising "woo"s on top.
static func applause(result: int) -> AudioStreamWAV:
	var tier := 0 if result > 0 else (1 if result == 0 else (2 if result == -1 else 3))
	var seconds: float = [0.7, 1.3, 2.2, 3.2][tier]
	var rate: float = [6.0, 14.0, 28.0, 46.0][tier] # claps per second
	var level: float = [0.35, 0.55, 0.75, 0.85][tier]
	var claps := PackedFloat32Array()
	var t := 0.0
	var k := 0
	while t < seconds:
		claps.append(t)
		k += 1
		t += (0.5 + float(Procgen.mix((k * 7919) & Procgen.MASK32) % 1000) / 1000.0) / rate
	var low := [0.0, 0.0]
	var phase := [0.0]
	var first := [0] # the oldest clap still ringing (the onsets are in order)
	return _make(seconds, func(time: float, n: float):
		var env := minf(time / 0.08, 1.0) * clampf((seconds - time) / (seconds * 0.45), 0.0, 1.0) # swell, then thin out
		var s := 0.0
		while first[0] < claps.size() and time - claps[first[0]] >= 0.025:
			first[0] += 1
		var i: int = first[0]
		while i < claps.size() and claps[i] <= time: # the claps ringing now (each ~25 ms)
			s += exp(-(time - claps[i]) * 180.0)
			i += 1
		low[0] += (n - low[0]) * 0.55 # crack: noise with the lowest rumble taken off
		var crack: float = n - low[0]
		var out: float = crack * minf(s, 2.0) * 1.3 * level
		if tier == 3: # cheering: a roar and rising woos
			low[1] += (n - low[1]) * 0.04
			out += low[1] * 1.8 * env
			var woo := fmod(time, 0.9)
			phase[0] += (300.0 + 260.0 * woo + 12.0 * sin(TAU * 6.0 * time)) / RATE
			out += sin(TAU * phase[0]) * 0.12 * sin(PI * clampf(woo / 0.6, 0.0, 1.0)) * env
		return out * env)


static func _make(seconds: float, sample: Callable) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var noise := float(Procgen.mix(i & Procgen.MASK32)) / 2147483647.5 - 1.0
		var v: float = clampf(sample.call(float(i) / RATE, noise), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


# --- the shop's goofy things ----------------------------------------------------------------------

## Fresh Catch impact: a wet slap — a dull low thud with a splatter of filtered noise.
static func wet_slap() -> AudioStreamWAV:
	var low := [0.0]
	return _make(0.22, func(t: float, n: float):
		low[0] += (n - low[0]) * 0.35
		return sin(TAU * (140.0 + 90.0 * exp(-t * 40.0)) * t) * 0.6 * exp(-t * 28.0) * minf(t / 0.002, 1.0) \
			+ low[0] * 1.6 * exp(-t * 22.0) * (0.6 + 0.4 * sin(TAU * 37.0 * t)))


## Squeaky Set impact: a rubber squeak — a nasal tone sliding up then down, with a buzz.
static func squeak() -> AudioStreamWAV:
	var phase := [0.0]
	return _make(0.26, func(t: float, _n: float):
		phase[0] += (900.0 + 700.0 * sin(PI * clampf(t / 0.24, 0.0, 1.0))) / RATE
		var s := sin(TAU * phase[0])
		return (s * 0.5 + signf(s) * 0.18 + sin(TAU * phase[0] * 2.0) * 0.15) * sin(PI * clampf(t / 0.26, 0.0, 1.0)) * 0.7)


## Course Goose: a honk — two nasal blasts, a rough reedy tone dropping in pitch.
static func honk() -> AudioStreamWAV:
	var phase := [0.0]
	return _make(0.55, func(t: float, n: float):
		var blast := t if t < 0.22 else t - 0.28
		if blast < 0.0:
			return 0.0
		phase[0] += (420.0 - 90.0 * blast / 0.25) / RATE
		var saw := fmod(phase[0], 1.0) * 2.0 - 1.0
		var env := minf(blast / 0.015, 1.0) * clampf((0.25 - blast) / 0.08, 0.0, 1.0)
		return (saw * 0.45 + sin(TAU * phase[0] * 3.0) * 0.15 + n * 0.08) * env * 0.8)


## Clown Shoes: a floppy slap on each step.
static func shoe_slap() -> AudioStreamWAV:
	var low := [0.0]
	return _make(0.12, func(t: float, n: float):
		low[0] += (n - low[0]) * 0.5
		return (low[0] * 1.4 + sin(TAU * 210.0 * t) * 0.3) * exp(-t * 45.0) * minf(t / 0.0015, 1.0))


## Cemetery crow: two harsh rasping caws.
static func caw() -> AudioStreamWAV:
	var phase := [0.0]
	var low := [0.0]
	return _make(0.62, func(t: float, n: float):
		var call := t if t < 0.26 else t - 0.34
		if call < 0.0 or call > 0.26:
			return 0.0
		phase[0] += (720.0 - 260.0 * call / 0.26) / RATE
		low[0] += (n - low[0]) * 0.3
		var saw := fmod(phase[0], 1.0) * 2.0 - 1.0
		var env := minf(call / 0.02, 1.0) * clampf((0.26 - call) / 0.1, 0.0, 1.0)
		return (saw * 0.4 + low[0] * 0.5 * absf(saw)) * env * 0.8)


// Terrain in the project look (rough, no specular) with the cup cut out: fragments over the cup
// opening are discarded so the liner below shows through. The lie is decided per fragment from the
// hole's quantised masks with the same bilinear sample and thresholds as GeneratedHole.surface_at(),
// so surface edges are crisp lines exactly where the ball's lie changes. Each lie is one flat palette
// color plus a flat pattern so rolling speed reads: mower stripes across the hole axis on fairway,
// coarse mottling on rough, a fine checker on the green. Vertex color R carries the low-frequency
// grass drift (0.5 = none). Caustics (underwater) ripple light over every lie.
shader_type spatial;

uniform vec2 cup_xz; // hole-local
uniform float cup_radius;

uniform sampler2D fairway_mask : filter_linear, repeat_disable;
uniform sampler2D green_mask : filter_linear, repeat_disable;
uniform sampler2D bunker_mask : filter_linear, repeat_disable;
uniform sampler2D rough_mask : filter_linear, repeat_disable;
uniform float grid_size; // px per side
uniform float metres_per_px;
uniform float surface_threshold; // 0..1, as ProcgenParams
uniform float oob_threshold;
uniform float water_y;

uniform vec3 fairway_color : source_color;
uniform vec3 rough_color : source_color;
uniform vec3 green_color : source_color;
uniform vec3 sand_color : source_color;
uniform vec3 water_color : source_color;
uniform vec3 oob_color : source_color;

uniform vec2 axis_origin; // tee, hole-local xz
uniform vec2 axis_dir; // unit, tee → cup
uniform float stripe_width; // m
uniform float stripe_shade;
uniform float mottle_size; // m
uniform float mottle_shade;
uniform float checker_size; // m
uniform float checker_shade;
uniform float caustics; // 0..1: rippling light over the ground (underwater biome)
uniform float rough_ripples; // 0..1: wind ripples drawn over the rough (desert dunes)
uniform vec2 ripple_dir; // unit, hole-local xz: the way the wind lays them
uniform int oob_pattern; // Biome.OobPattern: 0 plain, 1 ripples, 2 leaf litter, 3 ash, 4 moss

varying vec3 local_pos;
varying float drift;

void vertex() {
	local_pos = VERTEX;
	drift = COLOR.r - 0.5;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Lighter by +k (toward white), darker by −k: the same drift as Color.lightened / darkened.
vec3 shade(vec3 c, float k) {
	return k > 0.0 ? mix(c, vec3(1.0), k) : c * (1.0 + k);
}

void fragment() {
	vec2 xz = local_pos.xz;
	if (distance(xz, cup_xz) < cup_radius) {
		discard;
	}
	// Texel centres sit on the map pixels, as GeneratedHole._sample() bilinear-samples them.
	vec2 uv = (xz / metres_per_px + 0.5) / grid_size;
	// Hole axis frame: u along tee → cup, v across it.
	vec2 rel = xz - axis_origin;
	float u = dot(rel, axis_dir);
	float v = dot(rel, vec2(-axis_dir.y, axis_dir.x));
	vec3 c;
	float k = 0.0;
	if (local_pos.y < water_y) {
		c = water_color;
	} else if (texture(rough_mask, uv).r > oob_threshold) {
		c = oob_color; // the wild beyond the line: a stronger pattern of its own per biome
		if (oob_pattern == 1) { // dune ripples
			float w = dot(xz, ripple_dir) * 1.7 + value_noise(xz * 0.05) * 7.0;
			k = sin(w) * 0.09 + (value_noise(xz * 0.02) - 0.5) * 0.12;
		} else if (oob_pattern == 2) { // leaf litter: small scattered leaves in warm and dark tones
			float leaf = value_noise(xz * 1.4);
			c = leaf > 0.72 ? c * vec3(1.18, 0.98, 0.72) : (leaf < 0.25 ? c * vec3(0.82, 0.78, 0.74) : c);
			k = (floor(value_noise(xz / (mottle_size * 0.5)) * 3.0) - 1.0) * mottle_shade * 1.5;
		} else if (oob_pattern == 3) { // ash: grey speckle and faint glowing cracks
			float s = hash(floor(xz * 2.5));
			k = s > 0.86 ? 0.16 : (s < 0.12 ? -0.14 : 0.0);
			float crack = 1.0 - smoothstep(0.0, 0.025, abs(value_noise(xz * 0.22) - 0.5));
			c = mix(c, vec3(0.85, 0.32, 0.1), crack * 0.55);
		} else if (oob_pattern == 4) { // moss: soft big cushions over darker ground
			float n = value_noise(xz * 0.11) * 0.6 + value_noise(xz * 0.37) * 0.4;
			c = mix(c * 0.85, c * vec3(0.85, 1.2, 0.85), smoothstep(0.42, 0.62, n));
			k = (floor(value_noise(xz / mottle_size) * 3.0) - 1.0) * mottle_shade;
		}
	} else if (texture(bunker_mask, uv).r > surface_threshold) {
		c = sand_color;
	} else if (texture(green_mask, uv).r > surface_threshold) {
		c = green_color;
		k = mod(floor(u / checker_size) + floor(v / checker_size), 2.0) < 0.5 ? checker_shade : -checker_shade;
		k += drift;
	} else if (texture(fairway_mask, uv).r > surface_threshold) {
		c = fairway_color;
		k = mod(floor(u / stripe_width), 2.0) < 0.5 ? stripe_shade : -stripe_shade;
		k += drift;
	} else {
		c = rough_color;
		float n = value_noise(xz / mottle_size) * 0.65 + value_noise(xz / (mottle_size * 0.37)) * 0.35;
		k = (floor(n * 3.0) - 1.0) * mottle_shade; // three flat tones, crisp blob edges
		k += drift;
		if (rough_ripples > 0.0) { // wind ripples across the dunes
			float w = dot(xz, ripple_dir) * 1.9 + value_noise(xz * 0.06) * 6.0;
			k += sin(w) * 0.07 * rough_ripples;
		}
	}
	ALBEDO = shade(c, k);
	if (caustics > 0.0) { // two drifting interference patterns: bright thin ridges where they meet
		vec2 q = xz * 0.35;
		float a = sin(q.x + TIME * 0.6 + sin(q.y * 1.3 + TIME * 0.4));
		float b = sin(q.y * 0.9 - TIME * 0.5 + sin(q.x * 1.1 - TIME * 0.3));
		float ridge = pow(1.0 - abs(a * b), 6.0);
		ALBEDO = mix(ALBEDO, vec3(1.0), ridge * caustics * 0.35);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

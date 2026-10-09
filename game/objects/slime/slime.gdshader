shader_type canvas_item;
// Slime sprite + eyelids. The lids are drawn here, not as nodes, so a crowd of thousands blinks
// for free. The texture is an atlas of skins side by side (slime_skins.png); a crowd instance
// picks its skin by INSTANCE_CUSTOM.y = UV shift of its frame. `eyes` are in atlas px, 3 per skin
// (eye i belongs to skin i / 3; its place in the blink order is order_pos[i % 3]). Lid = ellipse rx·1.2 × ry sliding down from above (centre y − 2ry + 2ry·closure),
// clipped by the eye ellipse (+2 px) minus the eyes listed in its `over` mask, rim stroke on top
// (slime_crawl.html drawLids()). Coordinates are atlas px.
//
// Blink timing (crowd): the slime's series repeats every `slot` seconds and starts at a random
// moment inside the first `b_rand` of it, so pauses vary between b_pause and b_pause + 2·b_rand.
// INSTANCE_CUSTOM.x = per-slime random 0..1 (16-bit in Compatibility — fine for a seed).
// A single node (not instanced) sets `closure_override` from GDScript instead.

uniform vec2 tex_size = vec2(2128.0, 661.0);
const int MAX_EYES = 12;
uniform vec4 eyes[12];
uniform int eye_count = 0;
// Bit masks over the eyes of the same skin (bit j = eye j of the skin): cut out of this eye's lid.
uniform int over[12];
// Position of each eye in the blink order.
uniform vec3 order_pos = vec3(0.0, 2.0, 1.0);
uniform float b_close = 0.07;
uniform float b_hold = 0.05;
uniform float b_open = 0.11;
uniform float b_gap = 0.18;
uniform float b_pause = 2.2;
uniform float b_rand = 1.5;
uniform vec4 lid_top : source_color = vec4(0.635, 0.298, 0.949, 1.0);
uniform vec4 lid_bottom : source_color = vec4(0.392, 0.094, 0.722, 1.0);
uniform vec4 lid_rim : source_color = vec4(0.165, 0.024, 0.314, 1.0);
uniform float rim_px = 7.0;
// >= 0: use these closures (single slime driven by GDScript).
uniform vec3 closure_override = vec3(-1.0);

varying vec3 closure;

float hash11(float n) {
	return fract(sin(n) * 43758.5453);
}

float lid_of(float t, float k) {
	t -= k * b_gap;
	if (t < 0.0) return 0.0;
	if (t < b_close) return smoothstep(0.0, 1.0, t / b_close);
	if (t < b_close + b_hold) return 1.0;
	if (t < b_close + b_hold + b_open) return 1.0 - smoothstep(0.0, 1.0, (t - b_close - b_hold) / b_open);
	return 0.0;
}

void vertex() {
	UV.x += INSTANCE_CUSTOM.y;
	if (closure_override.x >= 0.0) {
		closure = closure_override;
	} else {
		float seed = INSTANCE_CUSTOM.x;
		float series = 2.0 * b_gap + b_close + b_hold + b_open;
		float slot = series + b_pause + b_rand;
		float t = TIME + seed * slot * 13.0;
		float k = floor(t / slot);
		float start = hash11(k * 12.9898 + seed * 78.233) * b_rand;
		float ts = t - k * slot - start;
		closure = vec3(lid_of(ts, order_pos.x), lid_of(ts, order_pos.y), lid_of(ts, order_pos.z));
	}
}

float ell(vec2 p, vec2 c, vec2 r) {
	vec2 d = (p - c) / r;
	return dot(d, d);
}

// Lid colour with coverage in alpha. aa = sprite px per screen px.
vec4 lid(vec2 p, vec4 e, float c, int over_mask, int base, float aa) {
	if (c <= 0.001) return vec4(0.0);
	// Clip: inside the eye (+2 px) …
	float de = (sqrt(ell(p, e.xy, e.zw + 2.0)) - 1.0) * min(e.z, e.w);
	float a = clamp(0.5 - de / aa, 0.0, 1.0);
	// … minus the eyes lying over this one.
	for (int j = 0; j < 3; j++) {
		if ((over_mask & (1 << j)) != 0) {
			vec4 o = eyes[base + j];
			float dj = (sqrt(ell(p, o.xy, o.zw)) - 1.0) * min(o.z, o.w);
			a *= clamp(0.5 + dj / aa, 0.0, 1.0);
		}
	}
	if (a <= 0.0) return vec4(0.0);
	float ly = e.y - 2.0 * e.w + 2.0 * e.w * c;
	vec2 lr = vec2(e.z * 1.2, e.w);
	float dl = (sqrt(ell(p, vec2(e.x, ly), lr)) - 1.0) * min(lr.x, lr.y);
	float half_rim = rim_px * 0.5;
	float outer = rim_px > 0.0 ? half_rim : 0.0;
	a *= clamp(0.5 - (dl - outer) / aa, 0.0, 1.0);
	float g = clamp((p.y - (e.y - e.w)) / (2.0 * e.w), 0.0, 1.0);
	vec4 col = mix(lid_top, lid_bottom, g);
	if (rim_px > 0.0) {
		float on_rim = clamp(0.5 + (dl + half_rim) / aa, 0.0, 1.0);
		col = mix(col, lid_rim, on_rim);
	}
	return vec4(col.rgb, a);
}

void fragment() {
	vec2 p = UV * tex_size;
	float aa = max(length(fwidth(p)), 0.75);
	vec4 col = COLOR;
	for (int i = 0; i < MAX_EYES; i++) {
		if (i >= eye_count) {
			break;
		}
		vec4 e = eyes[i];
		// Cheap reject: far from this eye (also skips the eyes of the other skins).
		if (abs(p.x - e.x) > e.z * 1.3 + 4.0 || abs(p.y - e.y) > e.w * 2.1 + 4.0) {
			continue;
		}
		int k = i % 3;
		float c = k == 0 ? closure.x : (k == 1 ? closure.y : closure.z);
		vec4 l = lid(p, e, c, over[i], i - k, aa);
		col.rgb = mix(col.rgb, l.rgb, l.a);
	}
	COLOR = col;
}

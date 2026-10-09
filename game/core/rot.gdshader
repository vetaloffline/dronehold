shader_type canvas_item;
// Purple corruption over the ground. Recedes around buildings: `clears` = (centre x, y, radius,
// soft edge) in map px, an ellipse flattened by cam_k (map_03_editor.html drawRot(): radial
// gradient from R − soft (fully cleared) to R + 1 (untouched), scaled by camK in y).
// The look follows makeRot(): dark base, purple / black blotches, thin glowing veins.

uniform sampler2D blotch_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D vein_noise : repeat_enable, filter_linear_mipmap;
uniform vec2 map_size = vec2(4992.0, 2784.0);
uniform float alpha = 0.85;
uniform float cam_k = 0.75;
uniform vec4 clears[64];
uniform int clear_count = 0;
uniform vec4 base_color : source_color = vec4(0.102, 0.059, 0.133, 1.0);
uniform vec4 blotch_color : source_color = vec4(0.275, 0.078, 0.353, 1.0);
uniform vec4 dark_color : source_color = vec4(0.039, 0.02, 0.059, 1.0);
uniform vec4 vein_color : source_color = vec4(0.745, 0.275, 1.0, 1.0);
// Map px per noise tile.
uniform float blotch_scale = 700.0;
uniform float vein_scale = 520.0;
uniform float vein_strength = 0.35;

void fragment() {
	vec2 p = UV * map_size;
	vec3 col = base_color.rgb;
	float n = texture(blotch_noise, p / blotch_scale).r;
	col = mix(col, blotch_color.rgb, smoothstep(0.5, 0.85, n) * 0.55);
	col = mix(col, dark_color.rgb, smoothstep(0.45, 0.15, n) * 0.5);
	float v = texture(vein_noise, p / vein_scale).r;
	col = mix(col, vein_color.rgb, smoothstep(0.78, 0.95, v) * vein_strength);
	float keep = 1.0;
	for (int i = 0; i < 64; i++) {
		if (i >= clear_count) {
			break;
		}
		vec4 c = clears[i];
		vec2 d = p - c.xy;
		d.y /= cam_k;
		keep *= smoothstep(c.z - c.w, c.z + 1.0, length(d));
	}
	COLOR = vec4(col, alpha * keep);
}

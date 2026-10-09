shader_type canvas_item;
// Cast shadow of the core (core_shadow_editor.html drawShadow()): the Codex shadow layer, or the
// building silhouette tinted to one colour; opacity; blur approximated with a mipmap bias.

uniform bool silhouette = false;
uniform vec4 tint : source_color = vec4(0.0118, 0.0431, 0.102, 1.0);
uniform float opacity = 1.0;
// log2 of the blur radius in texels; 0 = sharp.
uniform float blur_lod = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV, blur_lod);
	if (silhouette) {
		c.rgb = tint.rgb;
	}
	COLOR = vec4(c.rgb, c.a * opacity);
}

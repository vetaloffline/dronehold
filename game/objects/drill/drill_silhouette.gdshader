shader_type canvas_item;
// Flat dark silhouette of a sprite (drill_anim.html makeDark(): source-in fill rgb(3,11,26)).
// Opacity is applied once on the parent CanvasGroup, so overlapping segments do not darken twice.

uniform vec4 color : source_color = vec4(0.0118, 0.0431, 0.102, 1.0);

void fragment() {
	COLOR = vec4(color.rgb, texture(TEXTURE, UV).a);
}

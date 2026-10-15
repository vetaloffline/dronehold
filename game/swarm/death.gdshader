shader_type canvas_item;
// Corpse in the swarm MultiMesh (Corpses / SwarmView.update_deaths): the mesh is one death-atlas frame,
// INSTANCE_CUSTOM.zw shifts UV to the frame, INSTANCE_CUSTOM.y = how far it has melted (0 opaque, 1 gone).

varying float melt;

void vertex() {
	UV += INSTANCE_CUSTOM.zw;
	melt = INSTANCE_CUSTOM.y;
}

void fragment() {
	COLOR *= texture(TEXTURE, UV);
	COLOR.a *= 1.0 - melt;
}

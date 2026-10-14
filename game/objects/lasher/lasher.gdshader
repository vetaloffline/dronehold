shader_type canvas_item;
// Lasher in the swarm MultiMesh: the mesh is one atlas frame (UV 0..1/cols, 0..1/rows),
// INSTANCE_CUSTOM.zw shifts it to the run-cycle frame of this lasher (SwarmView.update_frames).

void vertex() {
	UV += INSTANCE_CUSTOM.zw;
}

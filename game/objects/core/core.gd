@tool
class_name Core
extends MapObject
## The core: 6×6 building, the enemies' target; losing it loses the game.
## Tree (core.tscn): CastPivot/CastShadow · ContactShadow · Body. Shadows come first in the tree,
## so they draw under the body without Y-sort (docs/godot-notes.md).
## All tunables live in `rig` (core_rig.tres, shared by every core).
## Drone landing points: DronePad1…3 markers in core.tscn (drone_pads()); drag them in the core scene.

const CAST_CODEX := preload("res://art/objects/buildings/core/core_shadow_cast.png")
const CAST_SILHOUETTE := preload("res://art/objects/buildings/core/core.png")

## Cargo drones the core sends out when the match starts (game only).
@export_range(0, 20, 1) var start_drones := 2

const CARGO_DRONE := preload("res://game/objects/cargo_drone/cargo_drone.gd")

@export var rig: CoreRig:
	set(v):
		if rig and rig.changed.is_connected(_apply):
			rig.changed.disconnect(_apply)
		rig = v
		if rig:
			rig.changed.connect(_apply)
		_apply()


func get_footprint() -> Vector2i:
	return Vector2i(6, 6)


func get_map_shift() -> Vector2:
	return rig.map_shift if rig else Vector2.ZERO


func get_map_scale() -> float:
	return rig.map_scale if rig else 1.0


func get_clear_radius() -> float:
	return 14.0


func get_path_cost() -> float:
	return 0.0


func _enter_tree() -> void:
	add_to_group("enemy_target", true)
	add_to_group("storage", true)  # drones bring crystals here
	super._enter_tree()


func _ready() -> void:
	_apply()
	if not Engine.is_editor_hint():
		_spawn_drones.call_deferred()


## Start drones hang next to the core and go to work at once.
func _spawn_drones() -> void:
	var par := get_parent()
	if par == null:
		return
	for i in start_drones:
		var d := CARGO_DRONE.new() as CargoDrone
		d.name = "CargoDrone%d" % (i + 1)
		d.slot = i
		d.position = position + Vector2(-40.0 + 80.0 * i, 30.0)
		par.add_child(d)


func _process(_dt: float) -> void:
	editor_snap()
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	draw_drone_pads()


func _apply() -> void:
	if rig == null or not is_inside_tree():
		return
	var pivot_node := get_node_or_null("CastPivot") as Node2D
	var cast := get_node_or_null("CastPivot/CastShadow") as Sprite2D
	var contact := get_node_or_null("ContactShadow") as Sprite2D
	var body := get_node_or_null("Body") as Sprite2D
	if pivot_node == null or cast == null or contact == null or body == null:
		return
	pivot_node.transform = rig.cast_transform()
	var sil := rig.source == CoreRig.ShadowSource.SILHOUETTE
	cast.texture = CAST_SILHOUETTE if sil else CAST_CODEX
	cast.offset = -rig.pivot
	var mat := cast.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("silhouette", sil)
		mat.set_shader_parameter("tint", rig.shadow_color)
		mat.set_shader_parameter("opacity", rig.opacity)
		mat.set_shader_parameter("blur_lod", log(1.0 + rig.blur) / log(2.0))
	contact.offset = -rig.pivot
	contact.modulate.a = rig.contact_opacity
	body.offset = -rig.pivot
	_place()

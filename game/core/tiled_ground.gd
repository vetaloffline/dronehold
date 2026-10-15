@tool
class_name TiledGround
extends Node2D
## Map ground from one seamless tile (art/maps/ground/), repeated over the whole map in one draw.
## draw_texture_rect(tile = true) takes 1 texel per local unit and repeats the texture (the GLES3
## canvas renderer forces repeat on tiled rects); the draw transform scales texels to map px.
## Obstacles (cliffs, pits, trees) are not in the tile: they are objects placed in the editor.
## The node needs texture_filter «Linear Mipmap» and a texture imported with mipmaps, or it
## shimmers when the camera zooms out.

@export var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
## Map px one tile covers (square). 1024-texel tile at 320 → 3.2 texels per map px: sharp at camera zoom 3.
@export_range(64.0, 2048.0, 1.0, "suffix:px") var tile_px := 320.0:
	set(v):
		tile_px = v
		queue_redraw()
## Area to cover, map px from (0, 0). Zero = the size of the parent GameMap's grid.
@export var size_px := Vector2.ZERO:
	set(v):
		size_px = v
		queue_redraw()


func _ready() -> void:
	queue_redraw()


## Covered area in map px (zero when there is nothing to cover yet).
func area() -> Vector2:
	if size_px.x > 0.0 and size_px.y > 0.0:
		return size_px
	var map := get_parent() as GameMap
	if map and map.grid:
		return map.grid.size_px()
	return Vector2.ZERO


func _draw() -> void:
	var a := area()
	if texture == null or a.x <= 0.0 or a.y <= 0.0:
		return
	var k := tile_px / float(texture.get_width())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	draw_texture_rect(texture, Rect2(Vector2.ZERO, a / k), true)

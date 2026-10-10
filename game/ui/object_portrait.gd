@tool
class_name ObjectPortrait
extends Control
## Picture of the selected object for the info card, put together from its real sprites:
## - a turret (`rig` set): base shadow, base and the head view facing the camera, placed exactly like
##   Turret.update_sprites() places them on the map;
## - anything else (show_sprites): a snapshot of the object's own Sprite2D nodes in their current pose
##   (shadows skipped), e.g. the drill's body and arm;
## - a placeholder block (`block` set): drawn like BlockBuilding draws itself on the map;
## - show_scene(): any building scene (the build menu cards) — one of the above for a fresh instance.

@export var rig: TurretRig:
	set(v): rig = v; _items.clear(); queue_redraw()
## Placeholder building (wall, relay): its block.
@export var block: BlockRig:
	set(v): block = v; queue_redraw()
## Ground angle of the turret head view to show, ° (90 = towards the camera).
@export_range(0.0, 360.0, 0.5) var view_deg := 90.0:
	set(v): view_deg = v; queue_redraw()
## Share of the box the picture fills.
@export_range(0.3, 1.0, 0.01) var fill := 0.9:
	set(v): fill = v; queue_redraw()

## Snapshot: [texture, transform from the texture's px to the object's px, region, modulate].
var _items := []


## Snapshot of `obj`'s sprites (not its shadows) relative to the object.
func show_sprites(obj: Node2D) -> void:
	rig = null
	block = null
	_items.clear()
	var inv := obj.global_transform.affine_inverse()
	for n in obj.find_children("*", "Sprite2D", true, false):
		var s := n as Sprite2D
		if s.texture == null or not _visible_under(s, obj) or _in_shadow(s, obj):
			continue
		var size := s.region_rect.size if s.region_enabled else s.texture.get_size()
		var top_left := s.offset - (size * 0.5 if s.centered else Vector2.ZERO)
		var xf := inv * s.global_transform * Transform2D(0.0, top_left)
		var region := s.region_rect if s.region_enabled else Rect2(Vector2.ZERO, size)
		_items.append([s.texture, xf, region, s.modulate * s.self_modulate])
	queue_redraw()


## Picture of what `scene` builds, as it looks on the map: a turret from its rig, a block building
## from its rig, anything else — a snapshot of a fresh instance's sprites (added under this control
## for a moment, invisible and not running, so its sprites get their scene pose).
func show_scene(scene: PackedScene) -> void:
	var o := scene.instantiate()
	if o is Turret:
		block = null
		rig = (o as Turret).get_rig()
		o.free()
		return
	if o is Wall and (o as Wall).wall_rig() and (o as Wall).wall_rig().pillar:
		# The wall: its pillar sprite (what a lone piece looks like on the map).
		var t := (o as Wall).wall_rig().pillar
		rig = null
		block = null
		_items = [[t, Transform2D.IDENTITY, Rect2(Vector2.ZERO, t.get_size()), Color.WHITE]]
		o.free()
		queue_redraw()
		return
	if o is BlockBuilding:
		rig = null
		_items.clear()
		block = (o as BlockBuilding).rig
		o.free()
		return
	var holder := Node2D.new()
	holder.modulate.a = 0.0
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	if o is MapObject:
		(o as MapObject).ghost = true
	add_child(holder)
	holder.add_child(o)
	show_sprites(o as Node2D)
	holder.free()


## Shown as a part of `top` (its own hidden nodes count; a hidden card strip above it does not).
static func _visible_under(n: Node, top: Node) -> bool:
	while n:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		if n == top:
			return true
		n = n.get_parent()
	return true


static func _in_shadow(n: Node, top: Node) -> bool:
	while n and n != top:
		if "Shadow" in String(n.name):
			return true
		n = n.get_parent()
	return false


func _draw() -> void:
	if rig:
		_draw_turret()
	elif block:
		var box := BlockBuilding.block_box(block)
		var k := minf(size.x / box.size.x, size.y / box.size.y) * fill
		draw_set_transform(size * 0.5 - box.get_center() * k, 0.0, Vector2(k, k))
		BlockBuilding.draw_block(self, block, false)
		draw_set_transform(Vector2.ZERO)
	elif not _items.is_empty():
		_draw_items()


func _draw_items() -> void:
	var box := Rect2()
	var first := true
	for it in _items:
		var u := used_rect(it[0])
		var reg: Rect2 = it[2]
		var r := Rect2(u.position - reg.position, u.size).intersection(Rect2(Vector2.ZERO, reg.size))
		var xf: Transform2D = it[1]
		for corner in [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]:
			var p: Vector2 = xf * corner
			box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
			first = false
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	var k := minf(size.x / box.size.x, size.y / box.size.y) * fill
	var at := Transform2D(0.0, Vector2(k, k), 0.0, size * 0.5 - box.get_center() * k)
	for it in _items:
		var reg: Rect2 = it[2]
		draw_set_transform_matrix(at * (it[1] as Transform2D))
		draw_texture_rect_region(it[0], Rect2(Vector2.ZERO, reg.size), reg, it[3])
	draw_set_transform(Vector2.ZERO)


func _draw_turret() -> void:
	if rig.base == null or rig.heads.is_empty():
		return
	var g := rig.ground_in_base()
	var v := rig.nearest_view(view_deg)
	var hs := rig.head_scale
	var off := rig.view_offsets[v] if v < rig.view_offsets.size() else Vector2.ZERO
	# Turret.head_at(v) without recoil: housing point of the head, base px from the ground point.
	var head_at := (rig.ring - g) + Vector2((rig.head_x + off.x) * hs, -rig.lift * hs + off.y * hs)
	var head: Texture2D = rig.heads[v]
	var head_rect := Rect2(head_at - rig.housing[v] * hs, head.get_size() * hs)
	# Fit the visible pixels (the PNGs have wide empty margins), not the whole textures.
	var bu := used_rect(rig.base)
	var hu := used_rect(head)
	var box := Rect2(-g + bu.position, bu.size).merge(Rect2(head_rect.position + hu.position * hs, hu.size * hs))
	var k := minf(size.x / box.size.x, size.y / box.size.y) * fill
	var at := size * 0.5 - box.get_center() * k
	draw_set_transform(at, 0.0, Vector2(k, k))
	if rig.base_shadow:
		draw_texture(rig.base_shadow, -g, Color(1, 1, 1, minf(1.0, rig.base_shadow_alpha)))
	draw_texture(rig.base, -g)
	draw_texture_rect(head, head_rect, false)
	draw_set_transform(Vector2.ZERO)


static var _used := {}

## Rect of the non-transparent pixels of a texture (cached per texture).
static func used_rect(t: Texture2D) -> Rect2:
	if not _used.has(t):
		var img := t.get_image()
		if img and img.is_compressed():
			img = img.duplicate()
			img.decompress()
		_used[t] = Rect2(img.get_used_rect()) if img else Rect2(Vector2.ZERO, t.get_size())
	return _used[t]

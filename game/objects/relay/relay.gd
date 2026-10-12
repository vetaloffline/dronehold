@tool
class_name Relay
extends BlockBuilding
## The relay: a BlockBuilding (hp, store for the drones, DronePad markers, cleared ground — numbers in
## RelayRig) drawn from sprites: base with its ground shadow, a radar dish on the mast top that spins
## slowly — rig.dishes views switch by angle (snap, as a turret head) — and the dish's shadow in code.
## Tree (relay.tscn): BaseShadow (z −1, on the ground) · Base · DishShadow (on the slab, over the base) ·
## Dish · DronePad1/2 (on the two drawn landing pads). Node origin = ground point,
## node scale = rig.map_scale, children in px of the base PNG. Without art in the rig it is the
## BlockBuilding block (scale 1).

## Current dish angle on the ground, ° (0 = right, 90 = to the camera).
var dish_angle := 0.0
## Index of the dish view on screen (−1 = none yet).
var dish_view := -1


func art() -> RelayRig:
	return rig as RelayRig


func has_art() -> bool:
	var a := art()
	return a != null and a.base != null


func get_map_scale() -> float:
	return art().map_scale if has_art() else 1.0


func _ready() -> void:
	super._ready()
	if art():
		dish_angle = art().start_angle
	update_sprites()


func _on_rig_changed() -> void:
	super._on_rig_changed()
	update_sprites()


func _process(dt: float) -> void:
	super._process(dt)
	var a := art()
	if not has_art() or a.dishes.is_empty() or a.spin_speed == 0.0:
		return
	dish_angle = fposmod(dish_angle + a.spin_speed * dt, 360.0)
	if a.nearest_view(dish_angle) != dish_view:
		_update_dish()


## Puts the textures and positions from the rig on the sprites (base, shadows, dish view).
func update_sprites() -> void:
	var a := art()
	var on := has_art()
	for n in ["BaseShadow", "Base", "DishShadow", "Dish"]:
		var s := get_node_or_null(n) as Sprite2D
		if s:
			s.visible = on
	if not on:
		return
	var base := get_node_or_null("Base") as Sprite2D
	var base_shadow := get_node_or_null("BaseShadow") as Sprite2D
	for s in [base, base_shadow]:
		if s:
			(s as Sprite2D).centered = false
			(s as Sprite2D).position = -a.ground
	if base:
		base.texture = a.base
	if base_shadow:
		base_shadow.texture = a.base_shadow
		base_shadow.modulate.a = minf(1.0, a.base_shadow_alpha)
	_update_dish()


func _update_dish() -> void:
	var a := art()
	var dish := get_node_or_null("Dish") as Sprite2D
	var shadow := get_node_or_null("DishShadow") as Sprite2D
	if a == null or a.dishes.is_empty():
		dish_view = -1
		for s in [dish, shadow]:
			if s:
				(s as Sprite2D).visible = false
		return
	dish_view = a.nearest_view(dish_angle)
	var at := a.housing - a.ground
	for s in [dish, shadow]:
		if s == null:
			continue
		var sp := s as Sprite2D
		sp.visible = true
		sp.centered = false
		sp.texture = a.dishes[dish_view]
		sp.offset = -a.dish_pivot
	if dish:
		dish.position = at
	if shadow:
		shadow.position = at + a.dish_shadow_offset
		shadow.scale = Vector2(1.0, a.dish_shadow_squash)
		shadow.modulate = Color(0, 0, 0, a.dish_shadow_alpha)


func _draw() -> void:
	if not has_art():
		super._draw()
		return
	var a := art()
	if a.max_hp > 0.0 and hp < a.max_hp and hp > 0.0:
		# Same bar as the block's (map px: footprint width − 12, 6 high), above the dish.
		var k := 1.0 / a.map_scale
		var w := (a.footprint.x * MapGrid.CELL.x - 12.0) * k
		var top := a.housing.y - a.ground.y - 360.0
		var bar := Rect2(-w * 0.5, top, w, 6.0 * k)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp / a.max_hp, bar.size.y)), Color(0.35, 0.95, 0.35))
	draw_drone_pads()

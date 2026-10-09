class_name BuildMenu
extends CanvasLayer
## Build mode (docs/concept.md «Будівництво»; concept art/concept/12_build_v1.png, button
## 13_build_button_v1 / 13_build_button_open_v1):
## - the round hammer button (bottom right) opens a strip of cards: picture made from the building's
##   own sprites, name, price. Open, the button shows ✕ and closes the mode;
## - tap a card — it is active (lifted, gold); tap it again — cancelled;
## - open, the whole map gets a light grid and the cells where nothing can be built are red;
## - tap the map — the ghost of the building stands there on its cells (green — can, red — can not);
##   another tap moves it. The drill only goes into a highlighted free vein slot;
## - ✔ next to the ghost builds it (takes the price), ✖ removes the ghost. The card stays active.
## A drag pans the camera and is not a tap (pointer moves less than TAP_SLOP px).

signal built(o: MapObject)

const GROUP := "build_menu"
const TAP_SLOP := 14.0
const BUTTON_TEX := preload("res://art/ui/build/build_button.png")
const CLOSE_TEX := preload("res://art/ui/build/build_button_close.png")
const CRYSTAL_TEX := preload("res://art/objects/resources/crystal_vein/crystal_shard_1.png")
const THEME := preload("res://game/ui/menu_theme.tres")

const BUTTON_SIZE := 150.0
const MARGIN := Vector2(28, 24)
const CARD_SIZE := Vector2(236, 214)
const CARD_GAP := 16.0
## How far the active card rises, px.
const LIFT := 18.0
const GOLD := Color(1.0, 0.78, 0.25)
const CYAN := Color(0.33, 0.82, 1.0, 0.9)
const PRICE_BAD := Color(1.0, 0.45, 0.4)

@export var map: GameMap
@export var wallet: Wallet
@export var catalog: BuildCatalog = preload("res://game/core/build_catalog.tres")

var is_open := false
var item: BuildItem
var ghost: MapObject
## Why the ghost can not be built ("" = it can).
var problem := ""

var _root: Control
var _toggle: TextureButton
var _strip: Control
var _cards: Array[Button] = []
var _confirm: Control
var _ok: Button
var _cancel: Button
var _hint: Label
var _overlay: BuildOverlay
var _press := Vector2.INF
var _t := 0.0


## The build menu of the scene `n` is in, if its build mode is open (else null).
static func open_in(n: Node) -> BuildMenu:
	if n == null or not n.is_inside_tree():
		return null
	var m := n.get_tree().get_first_node_in_group(GROUP) as BuildMenu
	return m if m and m.is_open else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	layer = 7
	_root = Control.new()
	_root.name = "Root"
	_root.theme = THEME
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_toggle()
	_build_strip()
	_build_confirm()
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.add_theme_font_size_override("font_size", 30)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 8)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_root.add_child(_hint)
	if map:
		_overlay = BuildOverlay.new()
		_overlay.name = "BuildOverlay"
		var ground := map.shadows()
		(ground if ground else map).add_child(_overlay)
		map.map_changed.connect(_refresh_map_layer)
	if wallet:
		wallet.changed.connect(func(_r: String, _a: int, _d: int) -> void: _refresh())
	_root.resized.connect(_layout)
	_layout()
	_refresh()


# ---------- UI

func _build_toggle() -> void:
	_toggle = TextureButton.new()
	_toggle.name = "Toggle"
	_toggle.texture_normal = BUTTON_TEX
	_toggle.ignore_texture_size = true
	_toggle.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_toggle.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	_toggle.pivot_offset = _toggle.size * 0.5
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.pressed.connect(func() -> void: set_open(not is_open))
	_toggle.button_down.connect(func() -> void: _toggle.scale = Vector2.ONE * 0.93)
	_toggle.button_up.connect(func() -> void: _toggle.scale = Vector2.ONE)
	_root.add_child(_toggle)


func _card_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.06, 0.1, 0.93) if not active else Color(0.09, 0.08, 0.05, 0.96)
	sb.set_border_width_all(4 if active else 3)
	sb.border_color = GOLD if active else CYAN
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(GOLD, 0.45) if active else Color(0, 0, 0, 0.4)
	sb.shadow_size = 16 if active else 8
	return sb


func _build_strip() -> void:
	_strip = Control.new()
	_strip.name = "Cards"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.visible = false
	_root.add_child(_strip)
	for i in catalog.items.size():
		var it := catalog.items[i]
		var b := Button.new()
		b.name = "Card%d" % i
		b.focus_mode = Control.FOCUS_NONE
		b.size = CARD_SIZE
		b.position = Vector2(i * (CARD_SIZE.x + CARD_GAP), 0)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _card_style(false))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_on_card.bind(it))
		var pic := ObjectPortrait.new()
		pic.name = "Picture"
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.position = Vector2(14, 10)
		pic.size = Vector2(CARD_SIZE.x - 28, 118)
		pic.fill = 0.95
		b.add_child(pic)
		var title := Label.new()
		title.name = "Title"
		title.text = it.title
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 28)
		title.position = Vector2(0, 128)
		title.size = Vector2(CARD_SIZE.x, 36)
		b.add_child(title)
		var price := HBoxContainer.new()
		price.name = "Price"
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.alignment = BoxContainer.ALIGNMENT_CENTER
		price.add_theme_constant_override("separation", 8)
		price.position = Vector2(0, 166)
		price.size = Vector2(CARD_SIZE.x, 40)
		var ico := TextureRect.new()
		ico.texture = CRYSTAL_TEX
		ico.custom_minimum_size = Vector2(24, 36)
		ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.add_child(ico)
		var cost := Label.new()
		cost.name = "Cost"
		cost.text = str(it.cost.get("crystal", 0))
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost.add_theme_font_size_override("font_size", 32)
		price.add_child(cost)
		b.add_child(price)
		_strip.add_child(b)
		_cards.append(b)
		pic.show_scene(it.scene)  # in the tree now: the snapshot needs its sprites visible


func _square_button(name_: String, col: Color, kind: StatIcon.Kind) -> Button:
	var b := Button.new()
	b.name = name_
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(88, 88)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.15 if st == "pressed" else 0.0)
		sb.set_border_width_all(4)
		sb.border_color = col.lightened(0.45)
		sb.set_corner_radius_all(16)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 6
		b.add_theme_stylebox_override(st, sb)
	var dis := StyleBoxFlat.new()
	dis.bg_color = Color(0.25, 0.27, 0.3, 0.9)
	dis.set_border_width_all(4)
	dis.border_color = Color(0.5, 0.52, 0.55)
	dis.set_corner_radius_all(16)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icon := StatIcon.new()
	icon.kind = kind
	icon.color = Color.WHITE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(icon)
	return b


func _build_confirm() -> void:
	var row := HBoxContainer.new()
	row.name = "Confirm"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.visible = false
	_ok = _square_button("Ok", Color(0.13, 0.6, 0.27), StatIcon.Kind.CHECK)
	_cancel = _square_button("Cancel", Color(0.72, 0.13, 0.15), StatIcon.Kind.CROSS)
	_ok.pressed.connect(confirm)
	_cancel.pressed.connect(clear_ghost)
	row.add_child(_ok)
	row.add_child(_cancel)
	_root.add_child(row)
	_confirm = row


func _layout() -> void:
	var s := _root.size
	_toggle.position = s - MARGIN - Vector2(BUTTON_SIZE, BUTTON_SIZE)
	var w := catalog.items.size() * CARD_SIZE.x + (catalog.items.size() - 1) * CARD_GAP
	var right := _toggle.position.x - 24.0
	var left := maxf(MainMenu.safe_left(s.x) + MARGIN.x, right - w)
	# Too narrow for the cards at full size: shrink the strip.
	var k := minf(1.0, (right - left) / w)
	_strip.scale = Vector2(k, k)
	_strip.position = Vector2(right - w * k, s.y - MARGIN.y - CARD_SIZE.y * k)
	_strip.size = Vector2(w, CARD_SIZE.y + LIFT)


## Cards: the active one lifted and gold; the price red when the wallet can not pay it.
func _refresh() -> void:
	for i in _cards.size():
		var it := catalog.items[i]
		var b := _cards[i]
		var active := it == item
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, _card_style(active))
		b.position.y = -LIFT if active else 0.0
		var can := wallet == null or wallet.can_pay(it.cost)
		(b.get_node("Price/Cost") as Label).add_theme_color_override("font_color", Color.WHITE if can else PRICE_BAD)
		(b.get_node("Picture") as Control).modulate = Color.WHITE if can else Color(0.6, 0.6, 0.65)
	if ghost:
		_check_ghost()


# ---------- build mode

func set_open(v: bool) -> void:
	if v == is_open:
		return
	is_open = v
	_toggle.texture_normal = CLOSE_TEX if v else BUTTON_TEX
	if not v:
		select(null)
	_refresh_map_layer()
	_strip.visible = true
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if v:
		_strip.modulate.a = 0.0
		var y := _strip.position.y
		_strip.position.y = y + 60.0
		tw.tween_property(_strip, "position:y", y, 0.22)
		tw.tween_property(_strip, "modulate:a", 1.0, 0.18)
		var info := get_tree().get_first_node_in_group("object_info") as ObjectInfo
		if info:
			info.select(null)
	else:
		tw.tween_property(_strip, "modulate:a", 0.0, 0.15)
		tw.chain().tween_callback(func() -> void:
			_strip.visible = is_open
			_layout())


func _on_card(it: BuildItem) -> void:
	select(null if it == item else it)


## Make `it` the active card (null = none). The ghost goes; the drill lights up the free slots.
func select(it: BuildItem) -> void:
	item = it
	clear_ghost()
	_refresh()
	_refresh_map_layer()


## Grid + red cells over the map while the mode is open (for the active card: the drill slots are
## red for anything but the drill). Again after every map change (a building put up or gone).
func _refresh_map_layer() -> void:
	if _overlay == null or map == null or map.grid == null:
		return
	if is_open:
		_overlay.show_blocked(true, map.grid, Builder.blocked_cells(map, item))
	else:
		_overlay.show_blocked(false)
	if ghost:
		_check_ghost()


func clear_ghost() -> void:
	if ghost and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	problem = ""
	_update_overlay()


## The ghost of the active card where map point `p` is (the drill: into the free slot under `p`).
## Returns false if nothing could be put there (the drill off a slot).
func place_at(p: Vector2) -> bool:
	if item == null or map == null:
		return false
	var cell: Vector2i
	if item.vein_slot_only:
		var v := Builder.slot_at(map, p, _drill_rig(item))
		if v == null:
			_flash_hint(Builder.NOT_A_SLOT)
			return false
		cell = v.drill_slot_cell()
	else:
		var f := Vector2(_footprint_of(item))
		cell = Vector2i(roundi(p.x / MapGrid.CELL.x - f.x * 0.5), roundi(p.y / MapGrid.CELL.y - f.y * 0.5))
	if ghost == null or ghost.cell != cell:
		if ghost and is_instance_valid(ghost):
			ghost.free()
		ghost = Builder.make(item, cell, true)
		ghost.z_index = 10
		map.world().add_child(ghost)
	_check_ghost()
	return true


## ✔: build the active card where the ghost stands.
func confirm() -> MapObject:
	if ghost == null or item == null:
		return null
	var why := []
	var o := Builder.build(map, item, ghost.cell, wallet, why)
	if o == null:
		_flash_hint(why[0] if why.size() > 0 else "")
		return null
	FloatText.pop(map.world(), o.position - Vector2(0, 70), "−%d" % int(item.cost.get("crystal", 0)), CRYSTAL_TEX)
	clear_ghost()
	_refresh()
	_refresh_map_layer()  # its cells go red now, not on the next map_changed
	built.emit(o)
	return o


var _drill_rigs := {}

## Rig of the drill `it` builds (where it stands in a slot).
func _drill_rig(it: BuildItem) -> DrillRig:
	if not _drill_rigs.has(it):
		var o := it.scene.instantiate()
		_drill_rigs[it] = (o as Drill).rig if o is Drill else null
		o.free()
	return _drill_rigs[it]


func _footprint_of(it: BuildItem) -> Vector2i:
	var o := it.scene.instantiate() as MapObject
	var f := o.get_footprint()
	o.free()
	return f


func _check_ghost() -> void:
	problem = Builder.problem(map, item, ghost, wallet)
	_ok.disabled = problem != ""
	_update_overlay()


func _update_overlay() -> void:
	if _overlay == null:
		return
	var slots: Array[Rect2] = []
	if item and item.vein_slot_only and map and _drill_rig(item):
		for v in Builder.free_slots(map):
			slots.append(Drill.slot_rect(v, _drill_rig(item)))
	var fp := Rect2i()
	var sq := Rect2()
	if ghost:
		fp = Rect2i(ghost.cell, ghost.get_footprint())
		sq = ghost.footprint_rect()
	_overlay.show_state(fp, sq, problem == "", slots)


func _flash_hint(text: String) -> void:
	if text == "":
		return
	_hint.text = text
	_hint.visible = true
	_hint.modulate.a = 1.0
	_hint.size = Vector2(_root.size.x, 40)
	_hint.position = Vector2(0, _strip.position.y - LIFT - 60.0)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_hint, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: _hint.visible = false)


func _process(dt: float) -> void:
	_t += dt
	if ghost and is_instance_valid(ghost):
		var a := 0.85 + 0.1 * sin(_t * 4.0)
		ghost.modulate = Color(0.75, 1.45, 0.8, a) if problem == "" else Color(1.5, 0.6, 0.6, a)
		# ✔ ✖ next to the top right corner of the ghost's square.
		var sq := ghost.footprint_rect()
		var corner := Vector2(sq.end.x, sq.position.y)
		var at := _screen_of(corner)
		_confirm.visible = true
		_confirm.reset_size()
		_confirm.position = (at + Vector2(18, -_confirm.size.y - 40)).clamp(Vector2.ZERO, _root.size - _confirm.size)
	else:
		_confirm.visible = false


func _screen_of(p: Vector2) -> Vector2:
	return map.get_viewport().get_canvas_transform() * (map.get_global_transform() * p)


func screen_to_map(p: Vector2) -> Vector2:
	var to_map := map.get_global_transform().affine_inverse() * map.get_viewport().get_canvas_transform().affine_inverse()
	return to_map * p


func _unhandled_input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		set_open(false)
		return
	if not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		_press = e.position
		return
	if _press == Vector2.INF:
		return
	var moved: float = (e.position - _press).length()
	_press = Vector2.INF
	if moved <= TAP_SLOP and item:
		place_at(screen_to_map(e.position))

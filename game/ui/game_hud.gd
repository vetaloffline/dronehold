class_name GameHud
extends CanvasLayer
## In-game HUD (concept art/concept/01_mining_v1.png): crystal counter top left.
## The counter rolls up to the new amount and the crystal icon bounces when crystals come in.

@export var wallet: Wallet
## Distance from the top left corner of the screen (plus the phone notch on the left), px.
@export var margin := Vector2(24, 20)

@onready var _root := $Root as Control
@onready var _panel := $Root/Crystals as Control
@onready var _icon := $Root/Crystals/Row/Icon as Control
@onready var _count := $Root/Crystals/Row/Count as Label

## The number on screen (rolls towards the wallet amount).
var shown := 0.0
var _roll: Tween


func _ready() -> void:
	if wallet:
		shown = wallet.amount("crystal")
		wallet.changed.connect(_on_changed)
	_count.text = str(int(shown))
	_root.resized.connect(_layout)
	_layout()


func _layout() -> void:
	_panel.position = margin + Vector2(MainMenu.safe_left(_root.size.x), 0)


func _on_changed(res: String, amount: int, delta: int) -> void:
	if res != "crystal":
		return
	if _roll:
		_roll.kill()
	_roll = create_tween()
	_roll.tween_method(_show, shown, float(amount), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if delta > 0:
		_icon.pivot_offset = _icon.size * 0.5
		var t := create_tween()
		t.tween_property(_icon, "scale", Vector2.ONE * 1.3, 0.08)
		t.tween_property(_icon, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_count.modulate = Color(0.7, 0.95, 1.4)
		create_tween().tween_property(_count, "modulate", Color.WHITE, 0.45)


func _show(v: float) -> void:
	shown = v
	_count.text = str(int(round(v)))

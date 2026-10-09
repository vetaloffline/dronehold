class_name Wallet
extends Node
## The player's resources in one match. Costs are dictionaries ({"crystal": 50}), so a second
## resource is one more key, not a rewrite. One wallet per game scene, found through the group.

signal changed(res: String, amount: int, delta: int)

const GROUP := "wallet"

## What the player starts the match with.
@export var start := {"crystal": 200}

var _amounts := {}
var _started := false


func _enter_tree() -> void:
	add_to_group(GROUP)


## The wallet of the scene `n` lives in (null in scenes without one, e.g. test ranges).
static func of(n: Node) -> Wallet:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group(GROUP) as Wallet


func amount(res: String) -> int:
	_start()
	return int(_amounts.get(res, 0))


func add(res: String, n: int) -> void:
	if n == 0:
		return
	_start()
	_amounts[res] = amount(res) + n
	changed.emit(res, amount(res), n)


func can_pay(cost: Dictionary) -> bool:
	for res in cost:
		if amount(res) < int(cost[res]):
			return false
	return true


## Takes the cost if there is enough of everything; else takes nothing and returns false.
func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for res in cost:
		add(res, -int(cost[res]))
	return true


## Fills in `start` on first use (the scene sets `start` after the node is created).
func _start() -> void:
	if not _started:
		_started = true
		_amounts = start.duplicate()

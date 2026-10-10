@tool
class_name BuildCatalog
extends Resource
## What the player can build, in the order of the build menu cards.
## Prices are temporary (docs/concept.md «Будівлі»), the balance pass will change them.

@export var items: Array[BuildItem] = []

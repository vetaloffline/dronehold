@tool
class_name LightMachineGunRig
extends MachineGunRig
## Легкий кулемет (docs/concept.md «Урон», рішення 2026-10-14): тонкий ствол, повільніше й слабше за
## кулемет — 8 урону за кулю, 8 куль/с, дальність 13 клітинок. Пробиття, трасери, гільзи — як у кулемета.
## Арт і заміри — art/objects/buildings/light_mg/ (light_mg_views.json, light_mg_base.json).

func _init() -> void:
	damage = 8.0
	fire_rate = 8.0
	range_px = 416.0  # 13 клітинок по 32 px

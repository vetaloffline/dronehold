"""Write game/objects/light_mg/light_mg_rig.tres and light_mg.tscn from the measurement files.

Inputs: light_mg_views.json (light_mg_place.py: housing, muzzle, measured azimuths of the 16 heads) and
light_mg_base.json (light_mg_base_export.py: ring, ring_h, ground point). Overwrites both game files, so
values tuned later in the Inspector are lost — after tuning, edit the .tres instead of re-running this.

    python3 light_mg_rig_export.py
"""
import json
import os

A = os.path.dirname(os.path.abspath(__file__)) + "/"
ROOT = os.path.normpath(os.path.join(A, "..", "..", "..", ".."))
v = json.load(open(A + "light_mg_views.json"))
b = json.load(open(A + "light_mg_base.json"))

MAP_SCALE = 0.222          # base feet 72 map px (machine gun 95) — a quarter smaller
TUNER_SCALE = 0.644        # effects in map px as the machine gun's: 0.3 / 0.87 = map_scale / tuner_scale


def name_of(az):
    return ("%05.1f" % az).replace(".", "_") if az % 1 else "%03d" % az


heads = [f"light_mg_head_{name_of(22.5 * k)}.png" for k in range(16)]
ext = ['[ext_resource type="Script" path="res://game/objects/light_mg/light_mg_rig.gd" id="s_rig"]',
       '[ext_resource type="Texture2D" path="res://art/objects/buildings/light_mg/light_mg_base.png" id="1_base"]',
       '[ext_resource type="Texture2D" path="res://art/objects/buildings/light_mg/light_mg_base_shadow.png" id="2_bsh"]']
ext += [f'[ext_resource type="Texture2D" path="res://art/objects/buildings/light_mg/{h}" id="h{k:02d}"]' for k, h in enumerate(heads)]


def vec_arr(pts):
    return "PackedVector2Array(" + ", ".join(f"{x:g}, {y:g}" for x, y in pts) + ")"


hx, hy = v["housing"]
tres = ['[gd_resource type="Resource" script_class="LightMachineGunRig" load_steps=20 format=3]', ""] + ext + ["", "[resource]",
    'script = ExtResource("s_rig")',
    'base = ExtResource("1_base")',
    'base_shadow = ExtResource("2_bsh")',
    "heads = Array[Texture2D]([" + ", ".join(f'ExtResource("h{k:02d}")' for k in range(16)) + "])",
    "housing = " + vec_arr([(hx, hy)] * 16),
    "muzzle = " + vec_arr(v["muzzle"]),
    "view_azimuths = PackedFloat32Array(" + ", ".join(f"{a:g}" for a in v["view_azimuths"]) + ")",
    f"ring = Vector2({b['ring'][0]:g}, {b['ring'][1]:g})",
    f"ring_h = {b['ring_h']:g}",
    f"map_scale = {MAP_SCALE:g}",
    f"tuner_scale = {TUNER_SCALE:g}",
    "head_scale = 1.0",
    "lift = 0.0",
    "view_offsets = " + vec_arr([(0, 0)] * 16),
    "rot_speed = 450.0",
    "range_px = 416.0",
    "fire_rate = 8.0",
    "damage = 8.0",
    "recoil = 4.0",
    "flash = 45.0",
    "tracer_width = 1.0",
    ""]
open(ROOT + "/game/objects/light_mg/light_mg_rig.tres", "w").write("\n".join(tres))

g = b["ground"]
tscn = f'''[gd_scene load_steps=8 format=3]

[ext_resource type="Script" path="res://game/objects/light_mg/light_mg.gd" id="1_lmg"]
[ext_resource type="Resource" path="res://game/objects/light_mg/light_mg_rig.tres" id="2_rig"]
[ext_resource type="Texture2D" path="res://art/objects/buildings/light_mg/light_mg_base_shadow.png" id="3_bsh"]
[ext_resource type="Texture2D" path="res://art/objects/buildings/light_mg/light_mg_base.png" id="4_base"]
[ext_resource type="Texture2D" path="res://art/objects/buildings/light_mg/light_mg_head_090.png" id="5_head"]

[sub_resource type="CanvasItemMaterial" id="CanvasItemMaterial_add"]
blend_mode = 1

[node name="LightMachineGun" type="Node2D"]
texture_filter = 4
position = Vector2(32, 24)
scale = Vector2({MAP_SCALE:g}, {MAP_SCALE:g})
script = ExtResource("1_lmg")
rig = ExtResource("2_rig")

[node name="BaseShadow" type="Sprite2D" parent="."]
position = Vector2({-g[0]:g}, {-g[1]:g})
texture = ExtResource("3_bsh")
centered = false

[node name="HeadShadow0" type="Sprite2D" parent="."]
modulate = Color(0, 0, 0, 0.35)
texture = ExtResource("5_head")
centered = false
offset = Vector2({-hx:g}, {-hy:g})

[node name="HeadShadow1" type="Sprite2D" parent="."]
visible = false
centered = false

[node name="Base" type="Sprite2D" parent="."]
position = Vector2({-g[0]:g}, {-g[1]:g})
texture = ExtResource("4_base")
centered = false

[node name="Head0" type="Sprite2D" parent="."]
position = Vector2(0, {-b['ring_h']:g})
texture = ExtResource("5_head")
centered = false
offset = Vector2({-hx:g}, {-hy:g})

[node name="Head1" type="Sprite2D" parent="."]
visible = false
centered = false

[node name="Fx" type="Node2D" parent="."]
z_index = 10
material = SubResource("CanvasItemMaterial_add")

[node name="FxTop" type="Node2D" parent="."]
z_index = 10
'''
open(ROOT + "/game/objects/light_mg/light_mg.tscn", "w").write(tscn)
print("ok")

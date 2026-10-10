@tool
class_name WallRig
extends BlockRig
## The wall's pieces (art: 3 sprites of one sheet, art/drafts/wall/ until approved): a pillar where the
## wall ends, turns or branches; between pillars a run of span — along x tiled from the "along" sprite,
## in depth the top face of the "depth" sprite stretched (in the 3/4 view the two look different). Without textures the wall is the plain block.
## `*_ground` = where the cell's ground point (cell centre) is in that sprite's px.

@export_group("Pieces")
@export var pillar: Texture2D
@export var pillar_ground := Vector2(68, 202)
@export var along: Texture2D
@export var along_ground := Vector2(-68, 142)
@export var depth: Texture2D
@export var depth_ground := Vector2(36, 58)
## Height of the spans above the ground, sprite px; rows of the depth span sprite that are its top face
## (the rest is its front end, always hidden behind the pillar that ends a run).
@export var span_h := 110.0
@export var depth_top := 88.0
## Sprite px → map px (the pieces are drawn ×8: a cell is 256×192 in them).
@export_range(0.01, 1.0, 0.005) var art_scale := 0.125
## Cast shadow of the pieces (sun upper right, falls left): alpha and how far left × height.
@export_range(0.0, 1.0, 0.01) var shadow_alpha := 0.28
@export_range(0.0, 2.0, 0.05) var shadow_len := 0.6

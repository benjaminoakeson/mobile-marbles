extends Control

## The profile glyph: a head and a pair of shoulders, drawn from primitives so
## the button needs no art -- the same way the thumbstick, the camera reset and
## the stick swap draw themselves.

@export var colour := Color(1, 1, 1, 0.9)

## Everything is a fraction of the button's smaller side, so the glyph scales
## with whatever box it is given.
@export var head_ratio := 0.16
@export var head_height_ratio := 0.13
@export var shoulder_ratio := 0.30
@export var shoulder_drop_ratio := 0.34

## How many segments the shoulders' curve is drawn with. Enough to read as round
## at the size a thumb sees it.
const SHOULDER_STEPS := 24


func _draw() -> void:
	var span := minf(size.x, size.y)
	var centre := size * 0.5

	draw_circle(centre - Vector2(0.0, span * head_height_ratio), span * head_ratio, colour)

	# The shoulders: the top half of a disc, built as a polygon rather than drawn
	# as a circle and covered up. Nothing painted over it would cut it -- the
	# button's own ground is behind the glyph, not in front of it -- so the flat
	# bottom edge has to be part of the shape.
	var shoulders := centre + Vector2(0.0, span * shoulder_drop_ratio)
	var width := span * shoulder_ratio

	var curve := PackedVector2Array()
	for step in SHOULDER_STEPS + 1:
		var angle := PI * float(step) / SHOULDER_STEPS
		curve.append(shoulders + Vector2(cos(angle), -sin(angle)) * width)

	draw_colored_polygon(curve, colour)

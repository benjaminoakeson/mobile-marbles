extends Control

## The reset-camera glyph: a ring broken at one side with an arrowhead on the
## open end, drawn from primitives so the button needs no art -- the same way
## the thumbstick draws itself.

@export var colour := Color(1, 1, 1, 0.9)

## Line width, and the radius, as fractions of the button's smaller side, so the
## glyph scales with whatever box it is given.
@export var thickness_ratio := 0.075
@export var radius_ratio := 0.3


func _draw() -> void:
	var span := minf(size.x, size.y)
	var centre := size * 0.5
	var radius := span * radius_ratio
	var thickness := span * thickness_ratio

	# Swept from the gap at the upper right the long way round, leaving the head
	# room to sit in the gap rather than on top of the line.
	var head_angle := deg_to_rad(-55.0)
	draw_arc(centre, radius, head_angle + deg_to_rad(45.0), head_angle + TAU, 48, colour, thickness, true)

	# The head, pointing back the way the sweep came from, so the ring reads as
	# turning anticlockwise -- winding the shot back.
	var out := Vector2(cos(head_angle), sin(head_angle))
	var along := Vector2(sin(head_angle), -cos(head_angle))
	var tip := centre + out * radius
	var head := thickness * 1.6

	draw_colored_polygon(PackedVector2Array([
		tip + along * head * 1.5,
		tip - along * head * 0.4 + out * head,
		tip - along * head * 0.4 - out * head,
	]), colour)

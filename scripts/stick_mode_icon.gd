extends Control

## The stick-swap glyph: the TRACK the stick is running in, with a knob sitting
## on it. Drawn from primitives so the button needs no art -- the same way the
## thumbstick and the camera reset draw themselves.
##
## Eight-sided with the knob parked in a corner while the gate is in; a plain
## ring with the knob sitting between the lanes while it is out. Same knob, two
## tracks, which is exactly what the button does to the stick.
##
## It shows the mode the stick is IN, not the one the tap would move to. A toggle
## that pictures its own opposite reads backwards the moment the player looks
## down mid-roll to check what they are steering with.

@export var colour := Color(1, 1, 1, 0.9)

## Line width, the track's radius and the knob's, as fractions of the button's
## smaller side, so the glyph scales with whatever box it is given.
@export var thickness_ratio := 0.075
@export var radius_ratio := 0.3
@export var knob_ratio := 0.13

## Where the knob sits on each track, in degrees round from the right. The gated
## one is a corner of the gate; the free one is deliberately not, because being
## able to stop between the lanes is the whole of the difference.
const GATED_KNOB_DEGREES := 45.0
const FREE_KNOB_DEGREES := 22.0


func _ready() -> void:
	GameState.stick_gated_changed.connect(_on_stick_gated_changed)


func _on_stick_gated_changed(_gated: bool) -> void:
	queue_redraw()


func _draw() -> void:
	var span := minf(size.x, size.y)
	var centre := size * 0.5
	var radius := span * radius_ratio
	var thickness := span * thickness_ratio

	var lanes := _lane_count()
	if lanes >= 3:
		var corners := PackedVector2Array()
		for i in lanes:
			corners.append(centre + _out(i * 360.0 / lanes) * radius)
		corners.append(corners[0])
		draw_polyline(corners, colour, thickness, true)
	else:
		draw_arc(centre, radius, 0.0, TAU, 48, colour, thickness, true)

	var knob := GATED_KNOB_DEGREES if GameState.stick_gated else FREE_KNOB_DEGREES
	draw_circle(centre + _out(knob) * radius, span * knob_ratio, colour)


## How many sides the track is drawn with, taken from the stick itself so a gate
## set to something other than eight lanes is pictured as what it actually is.
func _lane_count() -> int:
	if not GameState.stick_gated:
		return 0

	var stick := get_tree().get_first_node_in_group("thumbstick") as Thumbstick
	return stick.gate_directions if stick != null else 8


## A heading in degrees as a direction on SCREEN, where Y runs the other way.
func _out(degrees: float) -> Vector2:
	var angle := deg_to_rad(degrees)
	return Vector2(cos(angle), -sin(angle))

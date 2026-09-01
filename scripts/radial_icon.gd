class_name RadialIcon
extends Control

## One glyph for the radial menu, drawn from primitives.
##
## Five icons in one script rather than five scripts: they are all the same
## handful of lines in the same box, and the only thing that differs is which
## lines. The stick-swap glyph is NOT among them -- that one has to picture the
## mode the stick is actually in, so it lives in `stick_mode_icon.gd` and is
## reused here as it stands.
##
## Everything is a fraction of the box's smaller side, so a glyph is whatever
## size the button that holds it is.

enum Kind {
	ARROW_UP,
	ARROW_DOWN,
	MENU,
	RETRY,
	EXIT,
}

## Which glyph. Settable at runtime -- the radial's arrow turns over between
## ARROW_UP and ARROW_DOWN as the menu opens and shuts.
@export var kind: Kind = Kind.ARROW_UP:
	set(value):
		kind = value
		queue_redraw()

@export var colour := Color(1, 1, 1, 0.9)

## Line width as a fraction of the box's smaller side.
@export var thickness_ratio := 0.085


func _draw() -> void:
	var span := minf(size.x, size.y)
	var origin := (size - Vector2.ONE * span) * 0.5
	var thickness := span * thickness_ratio

	match kind:
		Kind.ARROW_UP:
			_chevron(origin, span, thickness, true)
		Kind.ARROW_DOWN:
			_chevron(origin, span, thickness, false)
		Kind.MENU:
			_bars(origin, span, thickness)
		Kind.RETRY:
			_retry(origin, span, thickness)
		Kind.EXIT:
			_exit(origin, span, thickness)


## The open/shut arrow. Pointing up means "there is more under here"; down means
## "put it away", which is the same shape turned over.
func _chevron(origin: Vector2, span: float, thickness: float, up: bool) -> void:
	var near := 0.38 if up else 0.62
	var far := 0.62 if up else 0.38

	draw_polyline(PackedVector2Array([
		origin + Vector2(0.26, far) * span,
		origin + Vector2(0.50, near) * span,
		origin + Vector2(0.74, far) * span,
	]), colour, thickness, true)


## Three bars. The one glyph on here that everybody already knows, which is why
## the button that opens the way out of the level wears it.
func _bars(origin: Vector2, span: float, thickness: float) -> void:
	for y: float in [0.34, 0.50, 0.66]:
		draw_line(
				origin + Vector2(0.28, y) * span,
				origin + Vector2(0.72, y) * span,
				colour, thickness, true)


## A ring with a bite out of it and an arrowhead on the end: round again.
##
## The arrowhead is built off the TANGENT at the arc's end rather than drawn as a
## fixed triangle, so it keeps pointing the way the line was travelling whatever
## the arc is changed to.
func _retry(origin: Vector2, span: float, thickness: float) -> void:
	var centre := origin + Vector2.ONE * span * 0.5
	var radius := span * 0.26

	var from := deg_to_rad(-40.0)
	var to := deg_to_rad(250.0)
	draw_arc(centre, radius, from, to, 32, colour, thickness, true)

	var tip := centre + Vector2(cos(from), sin(from)) * radius
	var tangent := Vector2(-sin(from), cos(from))
	var head := span * 0.16

	for turn: float in [34.0, -34.0]:
		draw_line(tip, tip + tangent.rotated(deg_to_rad(turn)) * head, colour, thickness, true)


## A box open on one side with an arrow leaving through the gap. The way out.
func _exit(origin: Vector2, span: float, thickness: float) -> void:
	draw_polyline(PackedVector2Array([
		origin + Vector2(0.56, 0.26) * span,
		origin + Vector2(0.28, 0.26) * span,
		origin + Vector2(0.28, 0.74) * span,
		origin + Vector2(0.56, 0.74) * span,
	]), colour, thickness, true)

	var tip := origin + Vector2(0.76, 0.50) * span
	draw_line(origin + Vector2(0.46, 0.50) * span, tip, colour, thickness, true)
	draw_line(tip, origin + Vector2(0.65, 0.38) * span, colour, thickness, true)
	draw_line(tip, origin + Vector2(0.65, 0.62) * span, colour, thickness, true)

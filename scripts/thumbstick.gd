class_name Thumbstick
extends Control

## On-screen dynamic thumbstick, drawn from primitives so it needs no art assets.
## `value` is clamped to unit length: +X is right, +Y is up the screen.
##
## It can steer through a GATE, the way an arcade stick sat in a restrictor
## plate: the heading it reports is snapped to one of [member gate_directions]
## lanes, so the four squares and the four diagonals are the only ways the ball
## can be sent. HOW HARD it is pushed is still read off the thumb, so a lane can
## be leaned into gently or thrown fully over -- what the gate takes away is the
## wobble between headings, not the difference between a nudge and a shove.
##
## What the gate must NOT do is arrive. A thumb on a free stick sweeps between
## headings over a tenth of a second or so, and everything downstream is built
## for that: the lean eases towards where it is pointed, and the camera closes
## most of the gap to the tilt it is asked for every single frame. Hand those a
## heading that changes by forty-five degrees between one frame and the next and
## they do exactly as they are told -- the shot snaps, the sky snaps back under
## it, and the level appears to jump. So the reported value SWEEPS to its new
## lane rather than appearing in it, which is the thumb's own movement put back
## by hand. Only the steady state is gated; getting there is as smooth as it
## ever was.
##
## Whether the gate is in is the player's to say, from the button in the corner,
## and it can be swapped mid-roll -- see [member GameState.stick_gated]. The
## swap is answered on the thumb that is already down rather than at the next
## touch: the whole point of putting it on screen during play is to feel the two
## against each other in the same corner.
##
## The point of it is that a direction becomes a PLACE. A thumb dragging round a
## free stick is always a little off the line it meant, and on a marble that
## holds every degree of that error the length of a straight, it never settles.
## Eight lanes can be found without looking, left, and come back to exactly.

## Controls that get first refusal on a touch landing inside them. The stick
## reads raw touches in `_input`, which Godot runs before it hands the event to
## the UI, so a button sitting over the stick's box -- the camera reset, in the
## bottom corner -- would otherwise be swallowed whole and never see the press.
const BLOCKER_GROUP := "blocks_thumbstick"

@export var knob_travel := 250.0 
@export var knob_radius := 90.0
@export var dead_zone := 0.1

## How many lanes the gate has WHEN IT IS IN. Eight is the arcade one -- the
## squares and the diagonals. Four makes it a d-pad. Whether the gate is in at
## all is not this: that is the player's setting, and it is read off
## [member GameState.stick_gated].
@export var gate_directions := 8

## How quickly the reported value follows the gate, and the ceiling on that in
## units of the stick's travel a second.
##
## Deliberately the same shape of smoothing the lean itself uses -- an ease with
## a cap on how fast it may travel -- because it is standing in for the same
## thing: a thumb crossing the gap between two headings takes about a tenth of a
## second to do it, and the cap is what makes the sweep a sweep rather than a
## lurch that tails off.
##
## The free stick is left alone by both. Its readings already move the way a
## thumb moves, so there is nothing here to give it but lag.
@export var gate_glide := 22.0
@export var gate_glide_rate := 7.0

## How far past the edge of a lane, in degrees, the thumb has to travel before
## the stick gives that lane up.
##
## Without it a thumb held on the line between two lanes flickers between them
## every frame, which is the exact wobble the gate is here to stop -- and worse
## than the free stick was, because it jumps in whole 45-degree steps. A real
## gate does this with a corner the stick has to be lifted out of. This is that
## corner.
@export var gate_stickiness := 7.0

var value := Vector2.ZERO

## Whether the gate is in. Owned by [GameState], mirrored here because it is read
## on every touch and drawn on every frame the stick is up.
var gated := true

## The lane the gate has picked, at the strength the thumb is pushing. What
## `value` is on its way to, and reaches once the sweep is over.
var _target := Vector2.ZERO

## Where the thumb is, in the stick's own axes, before the gate has had it.
##
## Kept because the gate can be taken in or out from under a thumb that is
## already down, and answering that needs the reading the gate was given, not the
## one it gave back.
var _thumb := Vector2.ZERO

## Which lane the stick is being held in, counted in whole lanes round from
## right, or -1 for a stick sitting in its dead zone. Kept between frames because
## the lane the stick is ALREADY in is the one it is reluctant to leave.
var _sector := -1

var _touch_index := -1
var _knob_offset := Vector2.ZERO

var _is_active := false
var _base_pos := Vector2.ZERO
var _global_base_pos := Vector2.ZERO


func _ready() -> void:
	gated = GameState.stick_gated
	GameState.stick_gated_changed.connect(_on_gate_swapped)


## The gate taken in or out mid-roll. The lane is forgotten either way: coming
## back to a gate that still remembered where the thumb used to sit would hand
## the player a heading they had not asked for.
func _on_gate_swapped(on: bool) -> void:
	gated = on
	_sector = -1
	_read_thumb()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and get_global_rect().has_point(event.position) \
					and not _blocked_at(event.position):
				_touch_index = event.index
				_is_active = true
				_global_base_pos = event.position
				_base_pos = event.position - global_position 
				_move_knob(event.position)
		elif event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_move_knob(event.position)


## Drops any touch in progress and stops listening for new ones. Used when the
## level ends, so the stick neither steers the level nor draws over the menu.
func disable() -> void:
	_release()
	set_process_input(false)
	hide()


## Whether a control that outranks the stick is sitting under this point.
func _blocked_at(pos: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group(BLOCKER_GROUP):
		var control := node as Control
		if control != null and control.is_visible_in_tree() \
				and control.get_global_rect().has_point(pos):
			return true
	return false


func _move_knob(pos: Vector2) -> void:
	var reach := (pos - _global_base_pos).limit_length(knob_travel) / knob_travel
	_thumb = Vector2(reach.x, -reach.y)
	_read_thumb()


## Turns wherever the thumb is into what the stick reports. Kept apart from the
## touch that moved it so the same reading can be taken again without one -- the
## gate being swapped is exactly that.
func _read_thumb() -> void:
	var strength := _thumb.length()

	if strength < dead_zone:
		# Back in the middle, so the next push picks its lane fresh rather than
		# favouring whichever one the last one ended in.
		#
		# Nothing is swept back to here. Letting go is not a change of heading:
		# it is the end of one, and the free stick has always answered it at
		# once. A stick that coasted back to the middle would go on steering
		# after the thumb had stopped asking it to.
		_sector = -1
		_target = Vector2.ZERO
		value = Vector2.ZERO
		_knob_offset = Vector2.ZERO
		queue_redraw()
		return

	_target = _lane(_thumb.angle()) * minf(strength, 1.0)

	# A free stick is already as smooth as the thumb holding it, so it is
	# reported as it is read. Only the gate has a gap to cross -- see `_process`.
	if not gated:
		value = _target

	_settle_knob()
	queue_redraw()


## Sweeps the reported value towards the lane the gate has picked.
##
## On the frame, not the physics tick: what this is smoothing for is what is
## SEEN -- the shot's tilt and the sky behind it -- and the lean reads whatever
## the latest frame left here anyway.
func _process(delta: float) -> void:
	if not gated or value.is_equal_approx(_target):
		return

	var eased := value.lerp(_target, 1.0 - exp(-gate_glide * delta))
	value += (eased - value).limit_length(gate_glide_rate * delta)

	_settle_knob()
	queue_redraw()


## Puts the knob where the stick IS, which during a sweep is between two lanes.
##
## Drawn from the reported value rather than from the lane, so what is on screen
## is what is being steered with. The lit spoke is the lane itself, and that
## snaps -- between them they say the gate took the input and the ball is on its
## way to answering it.
func _settle_knob() -> void:
	_knob_offset = Vector2(value.x, -value.y) * knob_travel


## The lane an angle falls in, as a unit vector, with [member gate_stickiness]
## worth of reluctance to leave whichever one the stick is already held in.
func _lane(angle: float) -> Vector2:
	if not gated or gate_directions < 2:
		return Vector2.from_angle(angle)

	var width := TAU / gate_directions

	if _sector >= 0:
		var held := _sector * width
		if absf(angle_difference(held, angle)) <= width * 0.5 + deg_to_rad(gate_stickiness):
			return Vector2.from_angle(held)

	_sector = roundi(angle / width)
	return Vector2.from_angle(_sector * width)


## A lane's heading as a direction on SCREEN, where Y runs the other way.
func _lane_on_screen(index: int) -> Vector2:
	var angle := index * TAU / gate_directions
	return Vector2(cos(angle), -sin(angle))


func _release() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	_thumb = Vector2.ZERO
	_target = Vector2.ZERO
	value = Vector2.ZERO
	_sector = -1
	_is_active = false
	queue_redraw()


func _draw() -> void:
	if not _is_active:
		return

	var centre := _base_pos

	# The gate, drawn as what it is: a ring with a corner on every lane, so the
	# shape under the thumb says where the stick can go before it is pushed.
	if gated and gate_directions >= 3:
		var corners := PackedVector2Array()
		for i in gate_directions:
			corners.append(centre + _lane_on_screen(i) * knob_travel)
		corners.append(corners[0])

		draw_colored_polygon(corners, Color(1, 1, 1, 0.08))
		draw_polyline(corners, Color(1, 1, 1, 0.30), 3.0, true)

		# And a spoke down each lane, with the one being steered lit. This is
		# what turns a heading into somewhere the thumb can aim.
		for i in gate_directions:
			var lit := _sector >= 0 and i == posmod(_sector, gate_directions)
			draw_line(
					centre + _lane_on_screen(i) * knob_travel * dead_zone,
					centre + _lane_on_screen(i) * knob_travel,
					Color(1, 1, 1, 0.45 if lit else 0.10), 2.0, true)

		draw_arc(centre, knob_travel * dead_zone, 0.0, TAU, 24,
				Color(1, 1, 1, 0.18), 2.0, true)
	else:
		draw_circle(centre, knob_travel, Color(1, 1, 1, 0.08))
		draw_arc(centre, knob_travel, 0.0, TAU, 48, Color(1, 1, 1, 0.30), 3.0, true)

	var knob := centre + _knob_offset
	draw_circle(knob, knob_radius, Color(1, 1, 1, 0.25))
	draw_arc(knob, knob_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.60), 3.0, true)

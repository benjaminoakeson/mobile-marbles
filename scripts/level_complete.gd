extends CanvasLayer

## Victory overlay. The goal ring spawns this once the ball is airborne.
##
## The score is STATED: the finished total, with the awards it was made of listed
## under it. It used to be counted out instead -- each award popping up on a chip,
## flying into a climbing total, the total throbbing while it ate the points. The
## crowns are what lands now, and a number counting itself up underneath them was
## two celebrations talking over each other.
##
## What the awards are, and the order they are listed in, is entirely the goal
## ring's business: this reads `GameState.last_award` and shows whatever is in it.
##
## The crowns above the score are the level's five, in their own colours. Any won
## for the first time this run spiral into place one at a time, each laying the
## words for what it was won for across itself in its own colour -- see
## `crowns.gd`. Those words stay up: a run that took four crowns should be able
## to show all four at the end, which is why they are slanted.

## How long the panel takes to fade up, so it does not snap over the celebration.
@export var fade_duration := 0.4

@export_group("Crowns")

## How a crown arrives: bigger than its slot, out at the end of a radius, and
## wound several turns round from square. All three run out together over the
## landing, so it spirals in, shrinks and straightens as one movement.
@export var crown_punch := 2.2
@export var crown_spiral_radius := 210.0
@export var crown_spiral_turns := 1.35

## How long that landing takes, and how long the panel waits on it before
## bringing in the next crown.
@export var crown_drop := 0.42
@export var crown_hold := 0.9

## How the words lie across their crown. Slanted so that several of them can be
## up at once: parallel lines, one crown apart, never cross each other however
## long they are.
@export var cheer_tilt_degrees := -45.0

## How long the words take to fade up as their crown lands.
##
## Slow, and slowest at the start: the crown spirals in hard and fast, and words
## that snapped on with it would be a second thing happening in the same instant.
## They surface under it instead, and are still arriving after it has landed.
@export var cheer_fade_in := 0.75

## What a tap multiplies the pace of the rest of the celebration by.
@export var tap_speed_up := 5.0

@export_group("Record Stamp")

## How far past its resting size the stamp starts, so it comes down onto the
## panel rather than fading up on it.
@export var record_punch := 2.3

## How long that landing takes.
@export var record_slam := 0.26

## How far off square the stamp sits once it has landed, in degrees. It winds in
## from further round than this.
@export var record_tilt_degrees := -7.0

## The pulse it keeps up afterwards: how far it swells, and how quickly.
@export var record_pulse := 0.05
@export var record_pulse_speed := 5.0

## The gap between the total's last digit and the stamp, and how close to the
## panel's edge the stamp may be pushed by a very long number.
@export var record_offset := 44.0
@export var record_margin := 24.0

@onready var _panel: Control = %Panel
@onready var _next_button: Button = %NextLevelButton
@onready var _menu_button: Button = %MenuButton
@onready var _total_label: Label = %TotalValue
@onready var _award_list: VBoxContainer = %AwardList
@onready var _award_row: HBoxContainer = %AwardRow
@onready var _crowns: HBoxContainer = %Crowns
@onready var _crown_slot: Control = %CrownSlot
@onready var _cheer_template: Label = %CheerTemplate
@onready var _stamp: Control = %RecordStamp

## Badge per crown, so the celebration can reach the one that has just been won.
var _badges := {}

## How much faster the rest of the celebration is running, after a tap.
var _speed := 1.0

## Set while crowns are still landing -- what makes a tap mean "hurry up".
var _celebrating := false

var _has_next := false

## Set once the stamp has landed, from which point `_process` owns its scale.
var _pulsing := false
var _pulse_time := 0.0


func _ready() -> void:
	_menu_button.pressed.connect(_change_scene.bind(LevelManager.MENU))

	# The last level -- and the scratch test level -- have nowhere to go next.
	var next_path := LevelManager.next_after(_current_level_path())
	_has_next = not next_path.is_empty()
	if _has_next:
		_next_button.pressed.connect(_change_scene.bind(next_path))

	Audio.wire_clicks(self)

	# Both buttons stay away until the crowns have landed. A tap anywhere hurries
	# them along, and a button sitting under that tap would swallow it and send
	# the player to the next level instead.
	_next_button.hide()
	_menu_button.hide()
	_stamp.hide()

	_show_score()
	_build_crowns()

	_panel.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(_panel, "modulate:a", 1.0, fade_duration)
	await fade.finished

	await _celebrate_crowns()

	if GameState.beat_best:
		Audio.play(Audio.NEW_RECORD)
		_stamp_record()

	_reveal_buttons()


func _process(delta: float) -> void:
	# The stamp breathes on its own clock, and only once it has finished landing
	# -- until then the slam tween owns its scale and the two would fight.
	if _pulsing:
		_pulse_time += delta
		_stamp.scale = Vector2.ONE * (1.0 + sin(_pulse_time * record_pulse_speed) * record_pulse)


## A tap hurries the rest of the celebration. Handled as unhandled input so it
## only ever picks up taps nothing else wanted.
func _unhandled_input(event: InputEvent) -> void:
	if not _celebrating:
		return

	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
	if tapped:
		_speed = maxf(_speed, tap_speed_up)


# --- The score ---

## The finished total, and the awards it came to under it.
##
## The total is read off [GameState] rather than added up here: it is the number
## that was actually banked, and a panel that did its own sums could show one
## thing while the save held another.
func _show_score() -> void:
	_total_label.text = GameState.format_gems(GameState.score)

	for award: Dictionary in GameState.last_award:
		if award.has("factor"):
			var factor := float(award["factor"])
			if factor <= 1.0:
				continue
			_add_award_row(str(award.get("label", "")), "×" + _trim_zeroes(factor))
			continue

		var points := int(award.get("points", 0))
		if points <= 0:
			continue
		_add_award_row(str(award.get("label", "")), "+" + GameState.format_gems(points))


func _add_award_row(label: String, value: String) -> void:
	var row: HBoxContainer = _award_row.duplicate()
	row.unique_name_in_owner = false
	row.visible = true
	(row.get_node("AwardName") as Label).text = label
	(row.get_node("AwardValue") as Label).text = value
	_award_list.add_child(row)


# --- The crowns ---

## All five slots, in their own colours for the ones this level has already given
## up and dark for the rest.
##
## Anything won on THIS run is left empty for now -- it is about to jump in.
func _build_crowns() -> void:
	var won := GameState.last_crowns_won
	var earned := GameState.crowns_for(GameState.current_level)

	for crown: int in Crowns.ORDER:
		var slot: Control = _crown_slot.duplicate()
		slot.unique_name_in_owner = false
		slot.visible = true
		_crowns.add_child(slot)

		var badge: TextureRect = slot.get_node("Badge")
		badge.modulate = Crowns.colour_for(crown) if earned & crown else Crowns.UNEARNED
		badge.visible = not (won & crown)
		_badges[crown] = badge


## The new crowns, one at a time: each drops into its slot with the words for
## what it was won for held over it.
func _celebrate_crowns() -> void:
	var won := Crowns.won_in(GameState.last_crowns_won)
	if won.is_empty():
		return

	_celebrating = true

	for crown: int in won:
		await _land_crown(crown)

	_celebrating = false


## One crown arriving: wound out and round, spiralling into its slot, with its
## words fading in over the top and out again a beat later.
##
## The spiral is driven from a single 0-to-1 run rather than as three separate
## tweens on position, rotation and scale. They are one movement -- the angle
## that swings the badge round is the same angle it is turned by -- and three
## tweens racing each other could never guarantee that.
##
## The words are faded out AFTER this returns rather than waited on, so the next
## crown is already on its way in while the last one's line clears.
func _land_crown(crown: int) -> void:
	var badge: TextureRect = _badges[crown]
	badge.pivot_offset = badge.size * 0.5
	_spiral(badge, 0.0)
	badge.show()

	# Told where the crown is GOING, not where it is: the badge is out at the end
	# of the spiral by now, and centring the line on it would fling the words
	# across the panel with it.
	_say(crown, badge.get_parent() as Control)
	Audio.play(Audio.EXTRA_LIFE)

	# The landing and the beat it is held for are one tween, not a tween followed
	# by a timer. A `SceneTreeTimer` made while a coroutine is being resumed by a
	# tween's `finished` never fires -- the crown after this one would never
	# land -- and an interval on the end of the chain says the same thing without
	# leaving the mechanism that works.
	var land := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	land.tween_method(func(along: float) -> void: _spiral(badge, along),
			0.0, 1.0, crown_drop / _speed)
	land.chain().tween_interval(crown_hold / _speed)
	await land.finished


## Where a crown is when it is `along` of the way in: 0 is wound right out, 1 is
## home, square and the size of its slot.
##
## The angle is what does the work. It runs down to nothing, and it is used three
## times over -- to swing the badge round its slot, to set how far out it is
## swung, and to turn the badge itself -- so all of it arrives at once.
func _spiral(badge: Control, along: float) -> void:
	var left := 1.0 - along
	var angle := crown_spiral_turns * TAU * left

	badge.position = Vector2.from_angle(angle) * crown_spiral_radius * left
	badge.rotation = angle
	badge.scale = Vector2.ONE * lerpf(crown_punch, 1.0, along)


## Lays this crown's words across it, in the crown's own colour, and fades them
## up.
##
## Centred on the slot rather than on the panel: five crowns in a row, and the
## line has to say which of them it is talking about. The colour says the same
## thing again -- a green line belongs to the green crown, whatever it is lying
## over by the time the fifth one lands.
##
## Added to the panel rather than to the crown's slot: a slot is one cell of a
## row, and a line this long hangs a good way out of it.
func _say(crown: int, slot: Control) -> void:
	var cheer: Label = _cheer_template.duplicate()
	cheer.unique_name_in_owner = false
	cheer.text = Crowns.name_for(crown)
	cheer.add_theme_color_override("font_color", Crowns.colour_for(crown))
	cheer.modulate.a = 0.0
	cheer.visible = true
	_panel.add_child(cheer)

	# Turned about its own corner and then hung so that the MIDDLE of it lands on
	# the crown. Turning it about its middle instead -- `pivot_offset` -- would
	# read better, but a control's pivot is not in the transform until the frame
	# after it is set, and this is placed the moment it is made. Rotating the
	# offset by hand is the same answer and needs nothing to have settled.
	var tilt := deg_to_rad(cheer_tilt_degrees)
	cheer.pivot_offset = Vector2.ZERO
	cheer.rotation = tilt
	cheer.global_position = slot.get_global_rect().get_center() \
			- (cheer.size * 0.5).rotated(tilt)

	var rise := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	rise.tween_property(cheer, "modulate:a", 1.0, cheer_fade_in / _speed)


# --- The record stamp ---

## Brings the stamp down beside the total and leaves it pulsing there.
func _stamp_record() -> void:
	_place_stamp()

	_stamp.pivot_offset = _stamp.size * 0.5
	_stamp.scale = Vector2.ONE * record_punch
	_stamp.modulate.a = 0.0

	# Wound further round than it will end up, so it twists square as it lands.
	_stamp.rotation = deg_to_rad(record_tilt_degrees - 16.0)
	_stamp.show()

	var slam := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	slam.tween_property(_stamp, "scale", Vector2.ONE, record_slam)
	slam.tween_property(_stamp, "rotation", deg_to_rad(record_tilt_degrees), record_slam)
	slam.tween_property(_stamp, "modulate:a", 1.0, record_slam * 0.4)

	await slam.finished
	_pulsing = true


## Puts the stamp just past the last digit of the total.
##
## The total's label runs the full width of the screen and centres its text, so
## the label's own rect says nothing about where the number ends -- that has to
## be measured off the text.
func _place_stamp() -> void:
	# Pinned to what the text actually needs before anything is measured off it.
	# The stamp has been hidden since the panel opened, so its box is still at
	# whatever the scene authored.
	_stamp.reset_size()

	var font := _total_label.get_theme_font("font")
	var font_size := _total_label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(
			_total_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

	var centre := _total_label.get_global_rect().get_center()
	var x := centre.x + text_width * 0.5 + record_offset

	# A big enough score would push the stamp off the edge, so it stops short and
	# overlaps the number instead of leaving the screen.
	x = minf(x, _panel.size.x - _stamp.size.x - record_margin)

	_stamp.global_position = Vector2(x, centre.y - _stamp.size.y * 0.5)


# --- Building blocks ---

## "2" rather than "2.0", but "2.5" kept as it is -- multipliers are written the
## way they would be said.
func _trim_zeroes(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _reveal_buttons() -> void:
	if _has_next:
		_next_button.show()
	_menu_button.show()

	for button: Button in [_next_button, _menu_button]:
		if not button.visible:
			continue
		button.modulate.a = 0.0
		create_tween().tween_property(button, "modulate:a", 1.0, 0.25)


func _current_level_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


func _change_scene(scene_path: String) -> void:
	# A fat finger can land on both buttons before the swap happens, so shut the
	# overlay down before asking for the next scene.
	_next_button.disabled = true
	_menu_button.disabled = true

	var result := get_tree().change_scene_to_file(scene_path)
	if result != OK:
		push_error("LevelComplete: could not load '%s' (error %d)" % [scene_path, result])
		_next_button.disabled = false
		_menu_button.disabled = false

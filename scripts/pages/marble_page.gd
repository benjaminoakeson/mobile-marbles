extends Control

## The marble page: the marble the player is actually wearing, turning in the
## middle of the screen, with every skin in the catalogue laid out under it.
##
## Nothing here is authored per skin. The tiles are built from `MarbleSkins`, so
## a skin added to the catalogue shows up on its own -- the same arrangement the
## levels page has with `LevelManager`.
##
## The dev tools used to live at the bottom of this page. They are on the levels
## page now, next to the start button.

## How many tiles fit across the page.
const COLUMNS := 3

## Every tile is ringed in its tier's colour, so a glance down the page reads as
## tiers even once the headings have scrolled off the top of it.
const RARITY_BORDER_WIDTH := 6

## Painted round the tile of the skin currently being worn: the same ring, more
## than twice as thick and in white.
##
## White because the tile itself carries the skin's colour and cannot be trusted
## not to look like whatever the marker is. Transcendent is white too, so up
## there the worn tile is told by its width alone -- there is nothing in that
## tier yet, and a ring this much thicker is not a subtle difference.
const SELECTED_BORDER := Color(1, 1, 1, 1)
const SELECTED_BORDER_WIDTH := 14

## A tile's colour is the skin's, so its label has to pick a side per tile --
## dark text on gold, light text on navy. Anything brighter than this counts as
## a light tile.
const DARK_TEXT_ABOVE := 0.55
const DARK_TEXT := Color(0.08, 0.09, 0.1, 1)
const LIGHT_TEXT := Color(1, 1, 1, 1)

@onready var _marble: MeshInstance3D = %Marble
@onready var _skin_list: VBoxContainer = %SkinList
@onready var _rarity_template: Label = %RarityTemplate
@onready var _skin_template: Button = %SkinTemplate

## Tile per skin id, so picking one can repaint just the two that changed rather
## than rebuilding the whole list under the player's thumb.
var _tiles := {}


func _ready() -> void:
	GameState.marble_skin_changed.connect(_on_skin_changed)

	# A marble bought in the shop should be here to wear the moment the player
	# comes back to this page.
	GameState.owned_skins_changed.connect(_build_picker)

	_build_picker()
	_show_skin(GameState.marble_skin)


# --- The picker ---

func _build_picker() -> void:
	_tiles.clear()
	for child in _skin_list.get_children():
		_skin_list.remove_child(child)
		child.queue_free()

	# One heading and one grid per tier, commonest first. A tier with nothing in
	# it is skipped rather than left as a heading over empty space -- which is
	# most of them until the shop has been visited, since only marbles the player
	# actually owns are offered here, and three of them hold nothing at all yet.
	for rarity in MarbleSkins.RARITIES:
		var ids := MarbleSkins.ids_in(rarity).filter(func(id: String) -> bool:
			return GameState.owns_skin(id))
		if ids.is_empty():
			continue

		var heading: Label = _rarity_template.duplicate()
		heading.unique_name_in_owner = false
		heading.visible = true
		heading.text = rarity

		# The tier's own colour, which is the whole of the colour coding: the
		# heading says which tier, and every tile under it is ringed to match.
		heading.add_theme_color_override("font_color", MarbleSkins.colour_of(rarity))
		_skin_list.add_child(heading)

		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 24)
		_skin_list.add_child(grid)

		for id: String in ids:
			var tile := _build_tile(id)
			grid.add_child(tile)
			_tiles[id] = tile


func _build_tile(id: String) -> Button:
	var tile: Button = _skin_template.duplicate()
	tile.unique_name_in_owner = false
	tile.visible = true
	tile.text = MarbleSkins.name_for(id)
	tile.pressed.connect(_pick.bind(id))

	# Built after the menu was given its clicks, so it asks for its own.
	Audio.wire_clicks(tile)

	_paint(tile, id, id == GameState.marble_skin)
	return tile


## Colours one tile in its own skin's colour, rings it in its tier's, and rings
## it in white instead if it is the one being worn.
##
## The stylebox is duplicated per tile rather than shared: the template's is one
## resource, and recolouring it in place would repaint every tile at once.
func _paint(tile: Button, id: String, selected: bool) -> void:
	var tint := MarbleSkins.tint_for(id)
	var ring := SELECTED_BORDER if selected else MarbleSkins.colour_for(id)
	var width := SELECTED_BORDER_WIDTH if selected else RARITY_BORDER_WIDTH

	for state: String in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = _skin_template.get_theme_stylebox(state).duplicate()
		style.bg_color = tint.darkened(0.25) if state == "pressed" else tint

		style.border_width_left = width
		style.border_width_top = width
		style.border_width_right = width
		style.border_width_bottom = width
		style.border_color = ring

		tile.add_theme_stylebox_override(state, style)

	var font_colour := DARK_TEXT if _is_light(tint) else LIGHT_TEXT
	tile.add_theme_color_override("font_color", font_colour)
	tile.add_theme_color_override("font_hover_color", font_colour)
	tile.add_theme_color_override("font_pressed_color", font_colour)


## Whether a tile wants dark text on it. Weighted for how the eye actually reads
## brightness -- green carries most of it, blue almost none -- so a saturated
## blue tile is treated as dark even though its colour is not.
func _is_light(tint: Color) -> bool:
	return tint.r * 0.299 + tint.g * 0.587 + tint.b * 0.114 > DARK_TEXT_ABOVE


func _pick(id: String) -> void:
	GameState.select_marble_skin(id)


# --- The marble on show ---

## Only the two tiles that changed are repainted. Rebuilding the list here would
## drop the scroll position back to the top every time a skin was tapped.
func _on_skin_changed(skin_id: String) -> void:
	for id: String in _tiles:
		_paint(_tiles[id], id, id == skin_id)

	_show_skin(skin_id)


func _show_skin(skin_id: String) -> void:
	# Named for the skin rather than just `material`: a Control already has one,
	# and shadowing it here reads as though this line touches the page's own.
	var skin_material := MarbleSkins.material_for(skin_id)
	if skin_material != null:
		_marble.set_surface_override_material(0, skin_material)

extends Control

## What the menu says about an award the player has already won.
##
## It hands over nothing. The marble went into the player's inventory the instant
## the award was met, back in the level -- see `GameState._check_awards()` -- so
## the Claim button only closes this. That is deliberate: a reward that waits on
## a button is a reward that can be lost to a crash on the way to the menu, and
## the player earned it in the level, not here.
##
## Shown one at a time. Winning two at once -- which the last level of a
## challenge run through a fully crowned world can do -- queues them, and closing
## one brings the next up rather than stacking a second panel on the first.

## How long the panel takes to fade up, and how far past its resting size the
## card starts so it lands rather than appears.
@export var fade_time := 0.25
@export var punch := 1.12
@export var land_time := 0.32

## How much darker than the marble's own rarity colour the card's edge sits, so
## the two read as one card lit from the middle rather than as a flat slab.
@export var edge_darkening := 0.45

@onready var _card: PanelContainer = %Card
@onready var _title: Label = %AwardName
@onready var _ask: Label = %AwardAsk
@onready var _skin_name: Label = %SkinName
@onready var _marble: MeshInstance3D = %Marble
@onready var _claim: Button = %ClaimButton

## Which award is on screen. Taken off the queue when the button is pressed, not
## when it is shown, so a game shut with this open still has it waiting.
var _showing := ""


func _ready() -> void:
	hide()
	_claim.pressed.connect(_on_claim)
	Audio.wire_clicks(self)


## Brings up whatever is waiting, if anything is. Called by the menu when it
## opens, and again each time one is closed.
func show_next() -> bool:
	var award_id := GameState.next_unclaimed_award()
	if award_id.is_empty():
		hide()
		return false

	_showing = award_id
	_dress(award_id)
	_arrive()
	return true


## The panel filled in for one award: what it is called, what was done for it,
## and the marble itself in the colour of its tier.
func _dress(award_id: String) -> void:
	_title.text = Awards.name_for(award_id)
	_ask.text = Awards.ask_for(award_id)

	var skin := Awards.skin_for(award_id)
	_skin_name.text = "%s  ·  %s" % [MarbleSkins.name_for(skin), MarbleSkins.rarity_for(skin)]

	var material := MarbleSkins.material_for(skin)
	if material != null:
		_marble.set_surface_override_material(0, material)

	# The card takes the marble's RARITY colour, not the marble's own tint. What
	# is being celebrated is how rare the thing is, and the tier colour is the
	# one the player already reads that off everywhere else in the menus.
	var colour := MarbleSkins.colour_for(skin)

	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = colour.darkened(edge_darkening)
	style.set_border_width_all(8)
	style.set_corner_radius_all(44)
	style.set_content_margin_all(48)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 24

	_card.add_theme_stylebox_override("panel", style)


## Fades the dimming up and drops the card onto it.
func _arrive() -> void:
	show()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, fade_time)

	# Set here rather than at load: the card is laid out by now, and a pivot
	# taken before that would swing it about its corner.
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2.ONE * punch

	var land := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	land.tween_property(_card, "scale", Vector2.ONE, land_time)


func _on_claim() -> void:
	if _showing.is_empty():
		return

	GameState.claim_award(_showing)
	_showing = ""

	# Straight into the next one if there is another waiting, so a player who won
	# two in the same run is told about both.
	show_next()

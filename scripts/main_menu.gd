extends Control

## The menu, in three pages: the shop, the levels, and the player's marble.
##
## A bar of three equal buttons along the bottom switches between them. The bar
## stays put while a page is dug through, so it is always one tap back to the
## other two.

## Which page is open, as an index into the bars's buttons.
##
## Static, so leaving for a level and coming back opens the page the player left
## from -- the menu scene itself is built afresh each time it is returned to.
static var _open_page := 1

@onready var _pages: Array[Control] = [%ShopPage, %LevelsPage, %MarblePage]
@onready var _tabs: Array[Button] = [%ShopTab, %LevelsTab, %MarbleTab]
@onready var _gems: Label = %GemValue
@onready var _gem: Node3D = %Gem
@onready var _award_popup: Control = %AwardPopup

## How fast the gem in the corner turns, in degrees a second. The same slow turn
## the ones in the levels have, so the counter reads as a gem rather than as an
## icon of one.
const GEM_SPIN := 45.0


func _ready() -> void:
	# Reaching the menu ends whatever run was on: the gems piled up towards the
	# next extra life are dropped here, wherever the player came from.
	GameState.leave_run()

	Audio.play_music(Audio.MENU_MUSIC)
	Audio.wire_clicks(self)

	for index in _tabs.size():
		_tabs[index].pressed.connect(_open_page_at.bind(index))

	GameState.bank_changed.connect(_show_gems)
	_show_gems(GameState.bank)

	_open_page_at(_open_page)

	# Last, and over the top of whatever page was opened. An award is won in a
	# level, where there is nothing to show for it, so this is where the player
	# is told -- on the first menu they see afterwards, however they got here.
	# The marble is already theirs; see `award_popup.gd`.
	_award_popup.show_next()


func _process(delta: float) -> void:
	_gem.rotate_y(deg_to_rad(GEM_SPIN) * delta)


## The count in the corner. Followed rather than read once: gems are spent in the
## shop while this is on screen, and the number has to come down as they go.
func _show_gems(bank: int) -> void:
	_gems.text = GameState.format_gems(bank)


func _open_page_at(index: int) -> void:
	_open_page = index

	for other in _pages.size():
		_pages[other].visible = other == index

		# Set without the signal: the bar's buttons are toggles, and moving one
		# from here is not a press to be handled all over again.
		_tabs[other].set_pressed_no_signal(other == index)

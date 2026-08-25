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


func _ready() -> void:
	# Reaching the menu ends whatever run was on: the gems piled up towards the
	# next extra life are dropped here, wherever the player came from.
	GameState.leave_run()

	Audio.play_music(Audio.MENU_MUSIC)
	Audio.wire_clicks(self)

	for index in _tabs.size():
		_tabs[index].pressed.connect(_open_page_at.bind(index))

	_open_page_at(_open_page)


func _open_page_at(index: int) -> void:
	_open_page = index

	for other in _pages.size():
		_pages[other].visible = other == index

		# Set without the signal: the bar's buttons are toggles, and moving one
		# from here is not a press to be handled all over again.
		_tabs[other].set_pressed_no_signal(other == index)

extends Control

## The shop: three marbles at a time, and a clock running down to three more.
##
## Which three is [GameState]'s to decide -- the cheapest marble left and two
## rolled by rarity, see [method GameState._pick_stock]. All this shows is what
## the tier a marble belongs to is worth and what colour it is.
##
## The stock itself is not kept here. Which marbles are out and when they change
## belong to [GameState] -- see [method GameState.shop_skins] -- because the ten
## minutes has to pass while the game is shut, and a page that only exists while
## the shop tab is open cannot be the thing that measures it. All this does is
## show what is on the shelf and take the money.
##
## Bought marbles are left on the shelf rather than replaced. The three on show
## are what this refresh is offering, and swapping a tile out from under the
## finger that just bought it reads as the shop taking the marble back.

## How fast the marbles turn on show, in degrees a second. Slow -- they are being
## looked at, not shown off.
const SPIN_DEGREES := 20.0

## How long "not on sale yet" stays up after one of the real-money items is
## tapped.
const NOTE_SECONDS := 2.0

## What the price reads in when it can be paid, when it cannot, and once the
## marble is the player's.
##
## The affordable one is the emerald the counter in the corner is drawn in, and
## the packs below it price themselves in. That colour is what says the number is
## in gems, which is why the price itself does not have to spell it out -- and
## "30,000 GEMS" spelt out at this size does not fit on a tile a third of the
## screen wide.
const CAN_AFFORD := Color(0.3372549, 0.8862745, 0.5137255)
const TOO_DEAR := Color(0.85, 0.42, 0.42)
const OWNED := Color(0.55, 0.75, 1.0)

## What the double-gems tile reads before it is bought and after. Owned, it shows
## no price at all, in the colour a bought marble's price turns -- so the one
## bought thing on the money row says it the way the shelf says it.
##
## The price is here as well as in the scene because the tile is repainted from
## code the moment the page opens: the scene's copy is the layout's, this one is
## the one that ends up on screen.
const DOUBLE_GEMS_PRICE := "$3.99"
const DOUBLE_GEMS_ACTIVE := "ACTIVE"

## What a money item's price reads in while it is still for sale. The grey the
## tiles are laid out with -- money prices are not in gems, so they are not in
## the gem colours above.
const UNSOLD := Color(0.63529414, 0.6784314, 0.6509804)

@onready var _slots: HBoxContainer = %Slots
@onready var _template: Button = %SlotTemplate
@onready var _restock: Label = %Restock
@onready var _sold_out: Label = %SoldOut
@onready var _note: Label = %Note
@onready var _double_gems: Button = %DoubleGems
@onready var _double_gems_cost: Label = %DoubleGemsCost

## One entry per tile on the shelf: the marble it is selling and the parts of the
## tile that have to be repainted when the gems or the ownership change.
var _shelf: Array[Dictionary] = []

## What is left of the note under the real-money items.
var _note_left := 0.0


func _ready() -> void:
	GameState.shop_changed.connect(_stock_shelf)

	# Both change what a tile should say without changing what is on it: gems
	# spent elsewhere can put a marble out of reach, and a marble bought here
	# turns its own tile over to owned.
	GameState.bank_changed.connect(func(_bank: int) -> void: _price_shelf())
	GameState.owned_skins_changed.connect(_price_shelf)

	# The things bought with money. There is no store behind any of them yet --
	# they are laid out so the page can be seen whole, and they say as much when
	# they are tapped rather than doing nothing, which reads as a broken button.
	for item: Button in [%NoAds, %PackSmall, %PackMedium, %PackLarge]:
		item.pressed.connect(_not_for_sale_yet)

	# Double gems is the exception, and only by half: there is still no store to
	# take the money, but what the money buys is built and permanent, so the tile
	# has an owned state to show and something to listen to.
	_double_gems.pressed.connect(_buy_double_gems)
	GameState.double_gems_changed.connect(func(_active: bool) -> void: _price_unlocks())

	_stock_shelf()
	_price_unlocks()


func _process(delta: float) -> void:
	# Three marbles being drawn every frame is not free, and the shop is one tab
	# of three -- so nothing here runs while the page is behind another one.
	var showing := is_visible_in_tree()
	for slot in _shelf:
		var view := slot["view"] as SubViewport
		view.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if showing
				else SubViewport.UPDATE_DISABLED)

	if not showing:
		return

	if _note_left > 0.0:
		_note_left -= delta
		_note.visible = _note_left > 0.0

	var left := GameState.shop_seconds_left()
	_restock.text = "NEW STOCK IN %d:%02d" % [left / 60, left % 60]

	# The clock has run out. Asking for the stock is what rolls it -- the answer
	# comes back through `shop_changed`, which restocks the shelf.
	if left <= 0:
		GameState.shop_skins()

	# Turned by hand rather than by each marble's own shader, because most of
	# them do not turn at all: a still marble in a shop window says less about
	# itself than a turning one does.
	for slot in _shelf:
		var marble := slot["marble"] as Node3D
		marble.rotate_y(deg_to_rad(SPIN_DEGREES) * delta)


## Puts the marbles the shop is offering onto the shelf, one tile each.
func _stock_shelf() -> void:
	# Asked for BEFORE the old tiles come down, because asking is what rolls the
	# stock when the clock has run out -- and that comes straight back here
	# through `shop_changed`. Clearing first would leave those tiles standing and
	# then build another three beside them, which is how the shelf ended up with
	# six marbles on it, two of each.
	var stock := GameState.shop_skins()

	for slot in _shelf:
		var tile := slot["tile"] as Node
		# Taken out of the row at once rather than at the end of the frame: a
		# freed tile is still a child until then, and the row would lay itself
		# out around it.
		_slots.remove_child(tile)
		tile.queue_free()
	_shelf.clear()

	# Nothing left to sell is a real state, not an error: a player who owns every
	# marble in the game has finished the shop.
	# The marbles run out; the rest of the shop does not.
	_sold_out.visible = stock.is_empty()
	_slots.visible = not stock.is_empty()
	_restock.visible = not stock.is_empty()

	for id: String in stock:
		_shelf.append(_build_slot(id))

	_price_shelf()


func _build_slot(id: String) -> Dictionary:
	var tile: Button = _template.duplicate()
	tile.unique_name_in_owner = false
	tile.visible = true
	tile.pressed.connect(_buy.bind(id))

	# Built after the menu was given its clicks, so it asks for its own.
	Audio.wire_clicks(tile)

	var marble: MeshInstance3D = tile.get_node("Stack/View/SubViewport/Marble")
	var skin_material := MarbleSkins.material_for(id)
	if skin_material != null:
		marble.set_surface_override_material(0, skin_material)

	var skin_name: Label = tile.get_node("Stack/SkinName")
	skin_name.text = MarbleSkins.name_for(id)

	# The name carries the tier's colour rather than a tier label being added
	# under it. The tile is a third of the screen wide and already holds a
	# marble, a name and a price; the colour is the same code the picker uses,
	# and it costs no room at all.
	skin_name.add_theme_color_override("font_color", MarbleSkins.colour_for(id))

	_slots.add_child(tile)

	return {
		"id": id,
		"tile": tile,
		"marble": marble,
		"view": tile.get_node("Stack/View/SubViewport") as SubViewport,
		"price": tile.get_node("Stack/Price") as Label,
	}


## Puts the right price on every tile, and takes away the ones that cannot be
## pressed. Called again whenever the gems or the ownership move, so a tile that
## was out of reach comes back within it the moment a level is finished.
func _price_shelf() -> void:
	for slot in _shelf:
		var id: String = slot["id"]
		var price: Label = slot["price"]
		var tile: Button = slot["tile"]

		if GameState.owns_skin(id):
			price.text = "OWNED"
			price.add_theme_color_override("font_color", OWNED)
			tile.disabled = true
			continue

		var cost := MarbleSkins.price_for(id)
		var afford := cost <= GameState.bank

		price.text = GameState.format_gems(cost)
		price.add_theme_color_override("font_color", CAN_AFFORD if afford else TOO_DEAR)
		tile.disabled = not afford


## Whatever was tapped is not wired to a store. Says so, and takes it back after
## a moment.
func _not_for_sale_yet() -> void:
	_note.visible = true
	_note_left = NOTE_SECONDS


## The double-gems tile. Owned, it does nothing -- it is bought once and kept for
## good, and a second sale of the same thing is the one outcome a shop must never
## have. Unowned, there is still no store to take the money, so it says so.
##
## What goes here when a store exists is the purchase flow, and the only thing it
## has to do on success is call `GameState.grant_double_gems()`. Everything else
## -- the tile, the save, the doubling itself -- already answers to that.
func _buy_double_gems() -> void:
	if GameState.double_gems:
		return

	_not_for_sale_yet()


## Repaints the money row for what is already owned.
func _price_unlocks() -> void:
	var owned := GameState.double_gems
	_double_gems_cost.text = DOUBLE_GEMS_ACTIVE if owned else DOUBLE_GEMS_PRICE
	_double_gems_cost.add_theme_color_override("font_color", OWNED if owned else UNSOLD)
	_double_gems.disabled = owned


func _buy(id: String) -> void:
	# The answer is ignored: everything that could refuse it has already greyed
	# the tile out, and the repaint comes back through `owned_skins_changed`.
	GameState.buy_skin(id)

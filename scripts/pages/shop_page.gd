extends Control

## The shop. Nothing to buy yet -- for now it is where the gems the player has
## banked are on show, so the pile they are building up is worth building up.

@onready var _bank_value: Label = %BankValue


func _ready() -> void:
	GameState.bank_changed.connect(_on_bank_changed)
	_on_bank_changed(GameState.bank)


func _on_bank_changed(bank: int) -> void:
	_bank_value.text = GameState.format_gems(bank)

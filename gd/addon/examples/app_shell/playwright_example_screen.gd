extends Control

@onready var _start_button: Button = $Panel/Margin/Content/StartButton
@onready var _start_event: PlaywrightEventEmitter = $StartEvent
@onready var _state: PlaywrightStatePublisher = $ExampleState

func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_state.publish({"ready": true})

func _on_start_pressed() -> void:
	_start_event.emit_playwright_event({"button": "start_button"})
	_state.set_value("started", true)

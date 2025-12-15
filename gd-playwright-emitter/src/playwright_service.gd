extends Node

const SETTINGS_PREFIX := "gd_playwright/"

const SETTING_ENABLED := SETTINGS_PREFIX + "enabled"
const SETTING_TEST_MODE := SETTINGS_PREFIX + "test_mode"
const SETTING_LOG_EVENTS := SETTINGS_PREFIX + "log_events"
const SETTING_EVENT_BUFFER_MAX := SETTINGS_PREFIX + "event_buffer_max"
const SETTING_EVENT_BUFFER_TRIM := SETTINGS_PREFIX + "event_buffer_trim"

const SETTING_TEST_USER1_EMAIL := SETTINGS_PREFIX + "test_user1_email"
const SETTING_TEST_USER1_PASSWORD := SETTINGS_PREFIX + "test_user1_password"
const SETTING_TEST_USER2_EMAIL := SETTINGS_PREFIX + "test_user2_email"
const SETTING_TEST_USER2_PASSWORD := SETTINGS_PREFIX + "test_user2_password"

const DEFAULT_LOG_EVENTS := true
const DEFAULT_EVENT_BUFFER_MAX := 1000
const DEFAULT_EVENT_BUFFER_TRIM := 500

# Defaults keep compatibility with the current Revik test suite, but can be overridden via ProjectSettings.
const DEFAULT_TEST_USER1_EMAIL := "nicozessoules+test1@gmail.com"
const DEFAULT_TEST_USER1_PASSWORD := "reviktest1"
const DEFAULT_TEST_USER2_EMAIL := "nicozessoules+test2@gmail.com"
const DEFAULT_TEST_USER2_PASSWORD := "reviktest2"

var _is_logging_in: bool = false
var _service_ready_emitted: bool = false
var _config_timeout_timer: Timer = null
var _config_listener: Callable = Callable()

func _ready() -> void:
	if not OS.has_feature("web"):
		return

	var env_service := _get_autoload("EnvService")
	if env_service != null:
		var is_loaded: bool = bool(env_service.get("is_loaded"))
		if is_loaded:
			_on_config_loaded()
		else:
			_config_listener = Callable(self, "_on_config_loaded")
			if env_service.has_method("register_config_listener"):
				env_service.call("register_config_listener", _config_listener)
			_start_config_timeout()
	else:
		_on_config_loaded()

func _start_config_timeout() -> void:
	_config_timeout_timer = Timer.new()
	_config_timeout_timer.wait_time = 5.0
	_config_timeout_timer.one_shot = true
	_config_timeout_timer.timeout.connect(_on_config_timeout)
	add_child(_config_timeout_timer)
	_config_timeout_timer.start()

func _on_config_timeout() -> void:
	if _service_ready_emitted:
		return

	if OS.has_feature("web"):
		JavaScriptBridge.eval("console.warn('[PLAYWRIGHT_TEST] CONFIG_LOADED not received after 5s, using fallback initialization')")

	_on_config_loaded()

func _on_config_loaded() -> void:
	if _service_ready_emitted:
		return

	var env_service := _get_autoload("EnvService")
	if env_service != null and _config_listener.is_valid() and env_service.has_method("unregister_config_listener"):
		env_service.call("unregister_config_listener", _config_listener)
		_config_listener = Callable()

	if _config_timeout_timer != null:
		_config_timeout_timer.stop()
		_config_timeout_timer.queue_free()
		_config_timeout_timer = null

	if not _is_test_mode_enabled():
		return

	_service_ready_emitted = true
	_expose_test_functions()

func _expose_test_functions() -> void:
	var js_code := """
		window.testLogin = function(username) {
			console.log('[PLAYWRIGHT_TEST] testLogin called with username: ' + username);
			if (username === 'user1') {
				window.testLoginRequested = 1;
			} else if (username === 'user2') {
				window.testLoginRequested = 2;
			} else {
				console.error('[PLAYWRIGHT_TEST] Invalid username: ' + username);
			}
		};
		console.log('[PLAYWRIGHT_TEST] Test login function exposed globally');
	"""
	JavaScriptBridge.eval(js_code)

	emit_event("service_ready")
	_start_login_polling()

func _start_login_polling() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_on_login_request_timeout)
	add_child(timer)
	timer.start()

func _on_login_request_timeout() -> void:
	if _is_logging_in:
		return

	var requested_user: int = int(JavaScriptBridge.eval("window.testLoginRequested || 0"))

	if requested_user == 1:
		JavaScriptBridge.eval("window.testLoginRequested = 0")
		_perform_test_login(_get_test_user_email(1), _get_test_user_password(1))
	elif requested_user == 2:
		JavaScriptBridge.eval("window.testLoginRequested = 0")
		_perform_test_login(_get_test_user_email(2), _get_test_user_password(2))

func _perform_test_login(email: String, password: String) -> void:
	_is_logging_in = true

	if OS.has_feature("web"):
		JavaScriptBridge.eval("console.log('[PLAYWRIGHT_TEST] Starting login for: " + email + "')")

	var golang_api_service := _get_autoload("GolangApiService")
	if golang_api_service == null or not golang_api_service.has_method("sign_in"):
		_is_logging_in = false
		if OS.has_feature("web"):
			JavaScriptBridge.eval("console.error('[PLAYWRIGHT_TEST] GolangApiService.sign_in unavailable; cannot perform test login')")
		emit_auth_completed(false)
		return

	golang_api_service.sign_in(email, password, func(result: Dictionary) -> void:
		_is_logging_in = false

		if result.get("success", false):
			if OS.has_feature("web"):
				JavaScriptBridge.eval("console.log('[PLAYWRIGHT_TEST] Login successful, emitting auth_completed(true)')")

			emit_auth_completed(true)
			var navigation_service := _get_autoload("NavigationService")
			if navigation_service != null and navigation_service.has_method("go_to"):
				navigation_service.go_to("home")
		else:
			var error_msg: String = result.get("error_message", "Login failed")

			if OS.has_feature("web"):
				JavaScriptBridge.eval("console.log('[PLAYWRIGHT_TEST] Login failed: " + error_msg + "')")

			emit_auth_completed(false)
	)

func emit_event_to_browser(event_name: String, data: Dictionary = {}) -> void:
	if not _should_emit_events():
		return

	var event_data := {
		"event": event_name,
		"timestamp": Time.get_ticks_msec(),
		"data": data
	}

	var json_string := JSON.stringify(event_data)

	var log_events: bool = bool(ProjectSettings.get_setting(SETTING_LOG_EVENTS, DEFAULT_LOG_EVENTS))
	if log_events:
		var log_msg := "[PLAYWRIGHT_EVENT] Emitting: " + event_name + " with data: " + json_string
		JavaScriptBridge.eval("console.log('" + log_msg + "')")

	var buffer_max: int = int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_MAX, DEFAULT_EVENT_BUFFER_MAX))
	var buffer_trim: int = int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_TRIM, DEFAULT_EVENT_BUFFER_TRIM))

	var buffer_management := """
		if (window.godotEvents && window.godotEvents.length >= %d) {
			window.godotEvents = window.godotEvents.slice(-%d);
		}
	""" % [buffer_max, buffer_trim]

	var event_push := """
		if (window.godotEvents) {
			window.godotEvents.push(%s);
		} else {
			window.godotEvents = [%s];
		}
		window.dispatchEvent(new CustomEvent('godot-event', { detail: %s }));
	""" % [json_string, json_string, json_string]

	var js_code := buffer_management + event_push

	JavaScriptBridge.eval(js_code)

	if log_events:
		JavaScriptBridge.eval("console.log('[PLAYWRIGHT_EVENT] Event emitted successfully')")

const EVENT_SCHEMAS := {
	"service_ready": [],
	"route_loaded": ["route"],
	"auth_completed": ["success"],
	"ui_element_ready": ["element"],
	"network_operation_completed": ["operation", "success"],
	"button_clicked": ["button"],
	"unit_selected": ["unit_id", "x", "y", "screen_x", "screen_y", "valid_moves"],
	"unit_move_preview": ["from_x", "from_y", "to_x", "to_y"],
	"unit_move_confirmed": ["from_x", "from_y", "to_x", "to_y"],
	"board_click": ["screen_x", "screen_y", "hex_x", "hex_y", "has_unit"],
	"debug_input": ["location", "event_type", "pos_x", "pos_y", "hex_x", "hex_y"],
	"turn_changed": ["turn", "active_player", "is_player_turn"],
	"card_preview_shown": [],
	"card_preview_hidden": [],
	"board_ready": ["board_width", "board_height", "units_placed"],
	"animation_complete": ["animation_type", "unit_id", "duration_ms"],
	"network_sync_complete": ["action", "status", "latency_ms"],
	"input_ready": ["ready"],
	"card_selected": ["card_id", "card_name", "player_slot"],
	"card_played": ["card_id", "card_name", "player_slot", "hand_size", "success", "mode"],
	"ui_state_ready": ["state", "player_turn", "ui_elements_updated"],
	"card_removed_from_deck": ["card_id"],
	"card_added_to_deck": ["card_id"],
	"deck_saved": [],
	"match_ended": ["winner_slot", "reason", "is_victory"],
	"hand_ready": ["player_slot", "card_count", "is_opponent", "cards", "viewport_width", "viewport_height"],
	"match_ready": [],
	"stat_bars_updated": ["player_turn", "ui_elements_updated"]
}

func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	if not _should_emit_events():
		return
	var schema = EVENT_SCHEMAS.get(event_name, [])
	for required_key in schema:
		if not payload.has(required_key):
			push_warning("PlaywrightService: Missing key %s for event %s" % [required_key, event_name])
			break
	emit_event_to_browser(event_name, payload)

func emit_route_loaded_deferred(route: String, defer_emit: bool = true) -> void:
	if defer_emit:
		await get_tree().process_frame
	emit_route_loaded(route)

func emit_route_loaded(route: String) -> void:
	emit_event("route_loaded", {"route": route})

func emit_auth_completed(success: bool) -> void:
	emit_event("auth_completed", {"success": success})

func emit_debug_input(location: String, event_type: String, position: Vector2 = Vector2.ZERO, hex_pos: Vector2i = Vector2i(-1, -1)) -> void:
	emit_event("debug_input", {
		"location": location,
		"event_type": event_type,
		"pos_x": position.x,
		"pos_y": position.y,
		"hex_x": hex_pos.x,
		"hex_y": hex_pos.y
	})

func emit_board_click(screen_pos: Vector2, hex_pos: Vector2i, has_unit: bool) -> void:
	emit_event("board_click", {
		"screen_x": screen_pos.x,
		"screen_y": screen_pos.y,
		"hex_x": hex_pos.x,
		"hex_y": hex_pos.y,
		"has_unit": has_unit
	})

func emit_unit_selected(unit_id: int, board_pos: Vector2i, screen_pos: Vector2, valid_moves: Array) -> void:
	emit_event("unit_selected", {
		"unit_id": unit_id,
		"x": board_pos.x,
		"y": board_pos.y,
		"screen_x": screen_pos.x,
		"screen_y": screen_pos.y,
		"valid_moves": valid_moves
	})

func emit_unit_move_preview(from_pos: Vector2i, to_pos: Vector2i) -> void:
	emit_event("unit_move_preview", {
		"from_x": from_pos.x,
		"from_y": from_pos.y,
		"to_x": to_pos.x,
		"to_y": to_pos.y
	})

func emit_unit_move_confirmed(from_pos: Vector2i, to_pos: Vector2i) -> void:
	emit_event("unit_move_confirmed", {
		"from_x": from_pos.x,
		"from_y": from_pos.y,
		"to_x": to_pos.x,
		"to_y": to_pos.y
	})

func emit_card_selected(card_id: String, card_name: String, player_slot: int) -> void:
	emit_event("card_selected", {
		"card_id": card_id,
		"card_name": card_name,
		"player_slot": player_slot
	})

func emit_card_played(card_id: String, card_name: String, player_slot: int, hand_size: int, success: bool, mode: String) -> void:
	emit_event("card_played", {
		"card_id": card_id,
		"card_name": card_name,
		"player_slot": player_slot,
		"hand_size": hand_size,
		"success": success,
		"mode": mode
	})

func emit_button_clicked(button_name: String) -> void:
	emit_event("button_clicked", {"button": button_name})

func emit_match_ended(winner_slot: int, reason: String, is_victory: bool) -> void:
	emit_event("match_ended", {
		"winner_slot": winner_slot,
		"reason": reason,
		"is_victory": is_victory
	})

func emit_turn_changed(turn: int, active_player: int, is_player_turn: bool) -> void:
	emit_event("turn_changed", {
		"turn": turn,
		"active_player": active_player,
		"is_player_turn": is_player_turn
	})

func emit_input_ready(ready: bool, blocked_reason: String = "") -> void:
	var payload := {"ready": ready}
	if not ready and blocked_reason != "":
		payload["blocked_reason"] = blocked_reason
	emit_event("input_ready", payload)

func emit_hand_ready(player_slot: int, card_count: int, is_opponent: bool, cards: Array = [], viewport_size: Vector2 = Vector2.ZERO) -> void:
	emit_event("hand_ready", {
		"player_slot": player_slot,
		"card_count": card_count,
		"is_opponent": is_opponent,
		"cards": cards,
		"viewport_width": viewport_size.x,
		"viewport_height": viewport_size.y
	})

func emit_board_ready(board_dimensions: Vector2, units_placed: int) -> void:
	emit_event("board_ready", {
		"board_width": board_dimensions.x,
		"board_height": board_dimensions.y,
		"units_placed": units_placed
	})

func emit_ui_state_ready(state: String, is_player_turn: bool, ui_elements_updated: int) -> void:
	emit_event("ui_state_ready", {
		"state": state,
		"player_turn": is_player_turn,
		"ui_elements_updated": ui_elements_updated
	})

func emit_match_ready() -> void:
	emit_event("match_ready")

func emit_card_preview_shown() -> void:
	emit_event("card_preview_shown")

func emit_card_preview_hidden() -> void:
	emit_event("card_preview_hidden")

func emit_network_sync_complete(action: String, status: String, latency_ms: float) -> void:
	emit_event("network_sync_complete", {
		"action": action,
		"status": status,
		"latency_ms": latency_ms
	})

func emit_animation_complete(animation_type: String, unit_id: int, duration_ms: int) -> void:
	emit_event("animation_complete", {
		"animation_type": animation_type,
		"unit_id": unit_id,
		"duration_ms": duration_ms
	})

func emit_card_added_to_deck(card_id: String) -> void:
	emit_event("card_added_to_deck", {"card_id": card_id})

func emit_card_removed_from_deck(card_id: String) -> void:
	emit_event("card_removed_from_deck", {"card_id": card_id})

func emit_deck_saved() -> void:
	emit_event("deck_saved")

func _should_emit_events() -> bool:
	if not OS.has_feature("web"):
		return false

	var env_service := _get_autoload("EnvService")
	if env_service != null:
		var is_loaded: bool = bool(env_service.get("is_loaded"))
		if not is_loaded:
			return true
		return bool(env_service.get("test_mode"))

	var enabled_setting: bool = bool(ProjectSettings.get_setting(SETTING_ENABLED, false))
	if enabled_setting:
		return true

	return OS.is_debug_build()

func _is_test_mode_enabled() -> bool:
	var env_service := _get_autoload("EnvService")
	if env_service != null:
		return bool(env_service.get("test_mode"))
	return bool(ProjectSettings.get_setting(SETTING_TEST_MODE, false))

func _get_autoload(name: String) -> Node:
	return get_node_or_null("/root/" + name)

func _get_test_user_email(user_index: int) -> String:
	if user_index == 1:
		return str(ProjectSettings.get_setting(SETTING_TEST_USER1_EMAIL, DEFAULT_TEST_USER1_EMAIL))
	if user_index == 2:
		return str(ProjectSettings.get_setting(SETTING_TEST_USER2_EMAIL, DEFAULT_TEST_USER2_EMAIL))
	return ""

func _get_test_user_password(user_index: int) -> String:
	if user_index == 1:
		return str(ProjectSettings.get_setting(SETTING_TEST_USER1_PASSWORD, DEFAULT_TEST_USER1_PASSWORD))
	if user_index == 2:
		return str(ProjectSettings.get_setting(SETTING_TEST_USER2_PASSWORD, DEFAULT_TEST_USER2_PASSWORD))
	return ""

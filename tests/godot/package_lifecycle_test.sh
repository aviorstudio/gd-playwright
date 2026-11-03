#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 ADDON_ZIP" >&2
    exit 2
fi
GODOT="${GODOT_BIN:-godot}"
ARCHIVE="$1"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
PROJECT="$TEMP/project"
ADDON_ID="@aviorstudio_gd-playwright"
mkdir -p "$PROJECT/addons/$ADDON_ID" "$PROJECT/addons/lifecycle_controller"
python3 - "$ARCHIVE" "$PROJECT/addons/$ADDON_ID" <<'PY'
from pathlib import Path
import sys
import zipfile

archive, destination = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(archive) as package:
    package.extractall(destination)
PY

cat > "$PROJECT/consumer_autoload.gd" <<'EOF'
extends Node
EOF
cat > "$PROJECT/project.godot" <<EOF
config_version=5

[application]
config/name="gd-playwright packaged lifecycle fixture"

[editor_plugins]
enabled=PackedStringArray("res://addons/$ADDON_ID/plugin.cfg", "res://addons/lifecycle_controller/plugin.cfg")

[consumer]
keep="consumer-owned"

[gd_playwright]
log_events=false
EOF
cat > "$PROJECT/addons/lifecycle_controller/plugin.cfg" <<'EOF'
[plugin]
name="Lifecycle controller"
description="Package lifecycle test controller"
author="Avior Studio"
version="1.0.0"
script="controller.gd"
EOF
cat > "$PROJECT/addons/lifecycle_controller/controller.gd" <<'EOF'
@tool
extends EditorPlugin

const TARGET := "@aviorstudio_gd-playwright"
const OWNED_SETTINGS := [
	"gd_playwright/enabled",
	"gd_playwright/test_mode",
	"gd_playwright/event_buffer_max",
	"gd_playwright/event_buffer_trim"
]

func _enter_tree() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("LIFECYCLE_FAIL: " + message)
	get_tree().quit(1)

func _consumer_configuration_is_intact() -> bool:
	return (
		str(ProjectSettings.get_setting("consumer/keep", "")) == "consumer-owned"
		and ProjectSettings.has_setting("gd_playwright/log_events")
		and not bool(ProjectSettings.get_setting("gd_playwright/log_events", true))
	)

func _run() -> void:
	var phase := OS.get_environment("GD_PACKAGE_LIFECYCLE_PHASE")
	# Editor plugins enter asynchronously during the first filesystem scan. Let
	# every enabled plugin finish its deferred initialization before inspection.
	for frame: int in range(5):
		await get_tree().process_frame
	if not _consumer_configuration_is_intact():
		_fail("consumer-owned configuration changed during " + phase)
		return
	if phase == "enabled" or phase == "restarted":
		if not EditorInterface.is_plugin_enabled(TARGET):
			_fail("packaged plugin is not enabled during " + phase)
			return
		var autoload_path := str(ProjectSettings.get_setting("autoload/PlaywrightService", "")).trim_prefix("*")
		var autoload_uid := FileAccess.get_file_as_string("res://addons/@aviorstudio_gd-playwright/autoload.gd.uid").strip_edges()
		if autoload_path != "res://addons/@aviorstudio_gd-playwright/autoload.gd" and autoload_path != autoload_uid:
			_fail("owned autoload is absent or incorrect during %s: '%s'" % [phase, autoload_path])
			return
		var service_script := load("res://addons/@aviorstudio_gd-playwright/autoload.gd")
		if service_script == null:
			_fail("packaged autoload smoke load failed")
			return
		var service: Node = service_script.new()
		if not service.has_method("configure") or not service.has_method("get_element_map"):
			_fail("packaged service smoke contract is missing")
			return
		service.free()
		if phase == "restarted":
			EditorInterface.set_plugin_enabled(TARGET, false)
			await get_tree().process_frame
			if EditorInterface.is_plugin_enabled(TARGET):
				_fail("plugin remained enabled after explicit disable")
				return
			if ProjectSettings.has_setting("autoload/PlaywrightService"):
				_fail("owned autoload remained after explicit disable")
				return
			for setting_name: String in OWNED_SETTINGS:
				if ProjectSettings.has_setting(setting_name):
					_fail("owned setting remained after disable: " + setting_name)
					return
			if ProjectSettings.has_setting("gd_playwright/_owned_settings") or ProjectSettings.has_setting("gd_playwright/_owns_autoload"):
				_fail("ownership markers remained after disable")
				return
			ProjectSettings.save()
			print("PASS gd-playwright package_lifecycle_disabled")
			get_tree().quit(0)
			return
		print("PASS gd-playwright package_lifecycle_enabled")
		get_tree().quit(0)
		return
	if phase == "disabled_restart":
		if EditorInterface.is_plugin_enabled(TARGET):
			_fail("plugin was enabled after disabled restart")
			return
		if ProjectSettings.has_setting("autoload/PlaywrightService"):
			_fail("owned autoload returned after disabled restart")
			return
		print("PASS gd-playwright package_lifecycle_disabled_restart")
		get_tree().quit(0)
		return
	if phase == "consumer_owned" or phase == "consumer_owned_restart":
		var configured_service := str(ProjectSettings.get_setting("autoload/PlaywrightService", ""))
		if configured_service.is_empty():
			_fail("consumer-owned PlaywrightService configuration was removed during " + phase)
			return
		if phase == "consumer_owned":
			EditorInterface.set_plugin_enabled(TARGET, false)
			await get_tree().process_frame
			if not ProjectSettings.has_setting("autoload/PlaywrightService"):
				_fail("consumer-owned PlaywrightService was removed on disable")
				return
			ProjectSettings.save()
			print("PASS gd-playwright package_lifecycle_consumer_owned")
		else:
			print("PASS gd-playwright package_lifecycle_consumer_owned_restart")
		get_tree().quit(0)
		return
	_fail("unknown phase: " + phase)
EOF

run_editor() {
    phase="$1"
    sentinel="$2"
    log="$TEMP/$phase.log"
    if ! GD_PACKAGE_LIFECYCLE_PHASE="$phase" timeout --foreground --kill-after=5s 45s \
        "$GODOT" --headless --editor --path "$PROJECT" 2>&1 | tee "$log"; then
        return 1
    fi
    if grep -Eq '(^|[[:space:]])(ERROR:|SCRIPT ERROR:|LIFECYCLE_FAIL:|Parse Error:)' "$log"; then
        return 1
    fi
    [ "$(grep -Fxc "$sentinel" "$log")" -eq 1 ]
}

run_editor enabled "PASS gd-playwright package_lifecycle_enabled"
run_editor restarted "PASS gd-playwright package_lifecycle_disabled"
run_editor disabled_restart "PASS gd-playwright package_lifecycle_disabled_restart"
cat > "$PROJECT/project.godot" <<EOF
config_version=5

[application]
config/name="gd-playwright consumer ownership fixture"

[autoload]
PlaywrightService="*res://consumer_autoload.gd"

[editor_plugins]
enabled=PackedStringArray("res://addons/$ADDON_ID/plugin.cfg", "res://addons/lifecycle_controller/plugin.cfg")

[consumer]
keep="consumer-owned"

[gd_playwright]
log_events=false
EOF
rm -rf "$PROJECT/.godot"
run_editor consumer_owned "PASS gd-playwright package_lifecycle_consumer_owned"
run_editor consumer_owned_restart "PASS gd-playwright package_lifecycle_consumer_owned_restart"
echo "ASSERTION_REACHED packaged_editor_enable_restart_disable_restart"

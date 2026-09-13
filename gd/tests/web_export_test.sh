#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 ADDON_ZIP" >&2
    exit 2
fi
GODOT="${GODOT_BIN:-godot}"
PLAYWRIGHT="${PLAYWRIGHT_CLI_BIN:-playwright-cli}"
ARCHIVE="$1"
OUTPUT_DIR="${GD_WEB_OUTPUT_DIR:-$(mktemp -d)}"
TEMP="${GD_WEB_TEMP_DIR:-$(mktemp -d)}"
mkdir -p "$TEMP"
SERVER_PID=""
SESSION="gd-playwright-web-$$"
cleanup() {
    "$PLAYWRIGHT" -s="$SESSION" close >/dev/null 2>&1 || true
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" >/dev/null 2>&1 || true; fi
    if [ -z "${GD_WEB_TEMP_DIR:-}" ]; then rm -rf "$TEMP"; fi
    if [ -z "${GD_WEB_OUTPUT_DIR:-}" ]; then rm -rf "$OUTPUT_DIR"; fi
}
trap cleanup EXIT
PROJECT="$TEMP/project"
mkdir -p "$PROJECT/addons/@aviorstudio_gd-playwright" "$OUTPUT_DIR/ordinary" "$OUTPUT_DIR/diagnostic"
python3 - "$ARCHIVE" "$PROJECT/addons/@aviorstudio_gd-playwright" <<'PY'
from pathlib import Path
import sys
import zipfile
with zipfile.ZipFile(Path(sys.argv[1])) as package:
    package.extractall(Path(sys.argv[2]))
PY
cat > "$PROJECT/project.godot" <<'EOF'
config_version=5

[application]
config/name="gd-playwright web identity fixture"
run/main_scene="res://main.tscn"

[autoload]
PlaywrightService="*res://addons/@aviorstudio_gd-playwright/autoload.gd"

[display]
window/size/viewport_width=640
window/size/viewport_height=360
window/size/window_width_override=640
window/size/window_height_override=360

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
cat > "$PROJECT/main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource path="res://main.gd" type="Script" id="1"]

[node name="Main" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")

[node name="Title" type="Label" parent="."]
offset_left = 40.0
offset_top = 40.0
offset_right = 600.0
offset_bottom = 80.0
text = "gd-playwright export identity"

[node name="Identity" type="Label" parent="."]
offset_left = 40.0
offset_top = 100.0
offset_right = 600.0
offset_bottom = 140.0

[node name="Contract" type="Label" parent="."]
offset_left = 40.0
offset_top = 160.0
offset_right = 600.0
offset_bottom = 220.0

[node name="StartButton" type="Button" parent="."]
offset_left = 40.0
offset_top = 250.0
offset_right = 240.0
offset_bottom = 310.0
text = "Normal input target"
EOF
cat > "$PROJECT/main.gd" <<'EOF'
extends Control

const ServiceModule = preload("res://addons/@aviorstudio_gd-playwright/src/playwright_service.gd")

func _ready() -> void:
	var diagnostic := OS.has_feature(ServiceModule.DIAGNOSTICS_EXPORT_FEATURE)
	$Identity.text = "Artifact: " + ("DIAGNOSTIC" if diagnostic else "ORDINARY")
	if not diagnostic:
		$Contract.text = "Bridge globals: ABSENT (settings cannot enable them)"
		PlaywrightService.configure(ServiceModule.PlaywrightConfig.new(true, true, false))
		PlaywrightService.emit_event("route_loaded", {"route": "ordinary"})
		return

	var policy := ServiceModule.PlaywrightPayloadPolicy.new(
		PackedStringArray(["start_button"]),
		PackedStringArray(),
		{"route_loaded": PackedStringArray(["route"])},
		{"fixture": PackedStringArray(["route", "cleanup", "input"])}
	)
	var config := ServiceModule.PlaywrightConfig.new(true, false, false, 100, 50, policy)
	PlaywrightService.configure(config)
	PlaywrightService.register_element("start_button", Vector2(140, 280), Vector2(200, 60), true)
	PlaywrightService.register_element("private_admin", Vector2.ZERO, Vector2.ONE, true)
	PlaywrightService.emit_event("route_loaded", {"route": "diagnostic"})
	PlaywrightService.emit_event("route_loaded", {"route": "rejected", "token": "never-published"})
	PlaywrightService.set_test_state("fixture", {"route": "diagnostic", "cleanup": false, "input": false})
	PlaywrightService.set_test_state("fixture", {"route": "rejected", "token": "never-published"})
	await get_tree().process_frame

	var stale := ServiceModule.new()
	get_tree().root.add_child(stale)
	stale.configure(config)
	stale.set_test_state("fixture", {"route": "stale", "cleanup": false, "input": false})
	PlaywrightService.set_test_state("fixture", {"route": "diagnostic", "cleanup": false, "input": false})
	stale.free()
	var isolated := bool(JavaScriptBridge.eval("window.godotTestState?.fixture?.route === 'diagnostic'"))

	var disposable := ServiceModule.new()
	get_tree().root.add_child(disposable)
	disposable.configure(config)
	disposable.set_test_state("fixture", {"route": "disposable", "cleanup": false, "input": false})
	disposable.free()
	var cleaned := bool(JavaScriptBridge.eval("window.__gdPlaywrightOwner === undefined && window.godotTestState === undefined"))

	PlaywrightService.configure(config)
	PlaywrightService.register_element("start_button", Vector2(140, 280), Vector2(200, 60), true)
	PlaywrightService.emit_event("route_loaded", {"route": "diagnostic"})
	PlaywrightService.set_test_state("fixture", {"route": "diagnostic", "cleanup": cleaned and isolated, "input": false})
	$Contract.text = "Read-only allowlist: PASS | owner cleanup/isolation: " + ("PASS" if cleaned and isolated else "FAIL")
	$StartButton.pressed.connect(_on_start_button_pressed)

func _on_start_button_pressed() -> void:
	PlaywrightService.set_test_state("fixture", {"route": "diagnostic", "cleanup": true, "input": true})
	$StartButton.text = "Normal input received"
EOF
cat > "$PROJECT/export_presets.cfg" <<'EOF'
[preset.0]
name="Ordinary"
platform="Web"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false

[preset.1]
name="Diagnostic"
platform="Web"
runnable=false
advanced_options=false
dedicated_server=false
custom_features="gd_playwright_diagnostics"
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.1.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
EOF

"$GODOT" --headless --path "$PROJECT" --export-release Ordinary "$OUTPUT_DIR/ordinary/index.html"
"$GODOT" --headless --path "$PROJECT" --export-release Diagnostic "$OUTPUT_DIR/diagnostic/index.html"

python3 - "$OUTPUT_DIR" <<'PY'
from pathlib import Path
import hashlib
import sys

root = Path(sys.argv[1])
lines = []
digests = {}
for identity in ("ordinary", "diagnostic"):
    tree = hashlib.sha256()
    files = sorted(path for path in (root / identity).rglob("*") if path.is_file())
    if not files:
        raise SystemExit(f"{identity} export is empty")
    for path in files:
        name = path.relative_to(root / identity).as_posix()
        tree.update(name.encode() + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    digests[identity] = tree.hexdigest()
    lines.append(f"GD_WEB_{identity.upper()}_TREE_SHA256={digests[identity]}")
if digests["ordinary"] == digests["diagnostic"]:
    raise SystemExit("ordinary and diagnostic artifact identities unexpectedly match")
(root / "web-artifact-identities.txt").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
PY

PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$OUTPUT_DIR" >"$TEMP/server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 30); do
    if curl --fail --silent "http://127.0.0.1:$PORT/ordinary/index.html" >/dev/null; then break; fi
    sleep 1
done

"$PLAYWRIGHT" -s="$SESSION" open "http://127.0.0.1:$PORT/ordinary/index.html"
"$PLAYWRIGHT" -s="$SESSION" run-code "async page => { await page.waitForTimeout(2000); if (!await page.locator('canvas').isVisible()) throw new Error('ordinary artifact canvas was not visible'); if (await page.evaluate(() => ['godotElements','godotEvents','godotTestState','__gdPlaywrightOwner'].some(k => window[k] !== undefined))) throw new Error('ordinary artifact exposed bridge globals'); }"
"$PLAYWRIGHT" -s="$SESSION" screenshot --filename="$OUTPUT_DIR/ordinary.png"
"$PLAYWRIGHT" -s="$SESSION" goto "http://127.0.0.1:$PORT/diagnostic/index.html"
"$PLAYWRIGHT" -s="$SESSION" run-code "async page => { await page.waitForFunction(() => window.godotTestState?.fixture?.cleanup === true); const result = await page.evaluate(() => ({ keys: Object.keys(window.godotElements || {}), state: window.godotTestState?.fixture, events: window.godotEvents || [] })); if (JSON.stringify(result.keys) !== JSON.stringify(['start_button'])) throw new Error('element allowlist failed: ' + JSON.stringify(result)); if (result.state?.route !== 'diagnostic' || result.state?.cleanup !== true || 'token' in result.state) throw new Error('state policy failed: ' + JSON.stringify(result)); if (result.events.length !== 1 || result.events[0].data.route !== 'diagnostic' || 'token' in result.events[0].data) throw new Error('event policy failed: ' + JSON.stringify(result)); const point = await page.evaluate(() => { const e = window.godotElements.start_button, v = window.godotElementsViewport, r = document.querySelector('canvas').getBoundingClientRect(); return {x: r.x + e.x * r.width / v.width, y: r.y + e.y * r.height / v.height}; }); await page.mouse.click(point.x, point.y); await page.waitForFunction(() => window.godotTestState.fixture.input === true); }"
"$PLAYWRIGHT" -s="$SESSION" screenshot --filename="$OUTPUT_DIR/diagnostic.png"
"$PLAYWRIGHT" -s="$SESSION" close
echo "ASSERTION_REACHED ordinary_diagnostic_web_artifacts_and_cleanup"

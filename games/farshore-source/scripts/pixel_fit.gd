class_name PixelFit
extends RefCounted
## Integer screen fit with no letterbox, for pixel-art phone games in portrait or landscape (proven in
## Chromaveil on an iPhone 14 web build).
##
## The rule: take the largest whole scale k at which the window still holds the design minimum (its long side
## follows the window's long side), then make the UI grid exactly window / k. Every art pixel is then k x k
## device pixels and the leftover is under k device pixels. Godot's own integer stretch letterboxes the
## remainder instead: a 1170 x 1992 Safari window with a fixed 192 x 416 base gave k = 4 (1992 / 416 = 4.79)
## and wide black bars. With a 192 x 336 minimum the same window gives k = 5 and a 234 x 398 grid.
##
## Use: call apply() on every root `size_changed` (an autoload is a good owner, so it runs before scene handlers):
## [codeblock]
## get_tree().root.size_changed.connect(func() -> void: PixelFit.apply(get_tree().root, DESIGN_MIN, true))
## [/codeblock]
## world_mode true (CANVAS_ITEMS) for HD-2D scenes, so a PixelView SubViewport can render finer than the UI
## grid; false (VIEWPORT) for 2D-only scenes, which render at the UI grid and scale up whole.
## The web export also wants allow_hidpi on (the default), or Safari upscales a small canvas with smoothing.
##
## Safe areas on the web: Godot cannot see the iPhone notch or home indicator, so the HTML shell exposes the
## CSS env() insets through a function that safe_insets() calls. Put this in the shell's head (the viewport meta
## must have viewport-fit=cover, or every inset reads 0):
## [codeblock]
## <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no, viewport-fit=cover">
## <style>:root { --safe-top: env(safe-area-inset-top, 0px); --safe-right: env(safe-area-inset-right, 0px);
##   --safe-bottom: env(safe-area-inset-bottom, 0px); --safe-left: env(safe-area-inset-left, 0px); }</style>
## <script>
## window.gameSafeArea = function () {
##   const s = getComputedStyle(document.documentElement);
##   const v = (n) => parseFloat(s.getPropertyValue(n)) || 0;
##   return [v('--safe-top'), v('--safe-right'), v('--safe-bottom'), v('--safe-left')].join(',');
## };
## </script>
## [/codeblock]

## The design minimum the Chromaveil layouts were built for (portrait form; landscape swaps it).
const DEFAULT_DESIGN_MIN := Vector2i(192, 336)
## Name of the web-shell function that returns the safe-area insets (see the class doc).
const DEFAULT_SAFE_AREA_JS := "gameSafeArea"


## The design minimum turned to match the window: the tall form for portrait windows, the wide form for
## landscape ones. Works whichever way round design_min is given.
static func oriented_min(window: Vector2i, design_min: Vector2i) -> Vector2i:
	var short_side := mini(design_min.x, design_min.y)
	var long_side := maxi(design_min.x, design_min.y)
	if window.y >= window.x:
		return Vector2i(short_side, long_side)
	return Vector2i(long_side, short_side)


## The largest whole scale k at which the window still holds the design minimum; never below 1.
## Example: 1170 x 1992 with 192 x 336 gives min(6, 5) = 5.
static func scale_for(window: Vector2i, design_min: Vector2i) -> int:
	var need := oriented_min(window, design_min)
	if need.x <= 0 or need.y <= 0:
		return 1
	return maxi(1, mini(window.x / need.x, window.y / need.y))


## The UI grid (content_scale_size) for a window: window / k, rounded down. Example: 1170 x 1992 gives 234 x 398.
static func content_size(window: Vector2i, design_min: Vector2i) -> Vector2i:
	var k := scale_for(window, design_min)
	return Vector2i(window.x / k, window.y / k)


## World render scale for a screen scale k: 2 when k is even, 1 when k is odd. The world view's pixels must land
## on whole device pixels: at k = 6 a 2x world pixel is 3 device px, while at k = 5 (iPhone 14 Safari portrait)
## a 2x world pixel would be 2.5 device px and shimmer, so the world renders at the UI grid.
static func world_scale(k: int) -> int:
	return 2 if k % 2 == 0 else 1


## Applies the fit to the root window and returns k. world_mode picks CANVAS_ITEMS (HD-2D scenes with a
## PixelView) or VIEWPORT (2D scenes). Stretch INTEGER, aspect KEEP, content size window / k. Safe to call on
## every size_changed: it only writes values that changed.
static func apply(root: Window, design_min: Vector2i, world_mode: bool) -> int:
	var window := DisplayServer.window_get_size()
	if root == null or window.x <= 0 or window.y <= 0:
		return 1
	var k := scale_for(window, design_min)
	var mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if world_mode else Window.CONTENT_SCALE_MODE_VIEWPORT
	if root.content_scale_mode != mode:
		root.content_scale_mode = mode
	if root.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_KEEP:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if root.content_scale_stretch != Window.CONTENT_SCALE_STRETCH_INTEGER:
		root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	var size := Vector2i(window.x / k, window.y / k)
	if root.content_scale_size != size:
		root.content_scale_size = size
	return k


## The scale k currently applied to the root (window width / UI grid width); 1 when no fit is applied.
static func current_scale(root: Window) -> int:
	var window := DisplayServer.window_get_size()
	if root == null or root.content_scale_size.x <= 0 or window.x <= 0:
		return 1
	return maxi(1, window.x / root.content_scale_size.x)


## True when the window is wider than tall.
static func is_landscape() -> bool:
	var s := DisplayServer.window_get_size()
	return s.x > s.y


## Safe-area insets in UI px ({"top", "right", "bottom", "left"}), read on the web from the shell function named
## js_function_name (see the class doc for the snippet). All zero off the web or when the hook is missing.
## Call it after apply(), and again on resize: the insets move when the phone turns.
static func safe_insets(js_function_name := DEFAULT_SAFE_AREA_JS) -> Dictionary:
	if not OS.has_feature("web") or not js_function_name.is_valid_identifier():
		return insets_from_css("", 1.0, 1.0)
	var css: Variant = JavaScriptBridge.eval("window.%s ? window.%s() : ''" % [js_function_name, js_function_name])
	var dpr := float(str(JavaScriptBridge.eval("window.devicePixelRatio || 1")))
	var tree := Engine.get_main_loop() as SceneTree
	var k := float(current_scale(tree.root if tree else null))
	return insets_from_css(str(css), dpr, k)


## Converts the shell's CSS-pixel insets ("top,right,bottom,left", or the older "top,bottom") to UI px:
## css x devicePixelRatio / k, rounded up so nothing tucks under the notch. Example: 47 CSS px at dpr 3, k 5 is 29.
static func insets_from_css(css: String, dpr: float, k: float) -> Dictionary:
	var out := {"top": 0, "right": 0, "bottom": 0, "left": 0}
	var parts := css.split(",", false)
	if k <= 0.0 or (parts.size() != 2 and parts.size() != 4):
		return out
	var keys: Array = ["top", "bottom"] if parts.size() == 2 else ["top", "right", "bottom", "left"]
	for i in keys.size():
		out[keys[i]] = maxi(0, ceili(parts[i].to_float() * dpr / k - 0.0001))
	return out

class_name FollowCamera
extends Node3D
## The hero-tracking HD-2D camera.
## A fixed-yaw, long-lens rig that follows smoothly with gentle look-ahead.
## Camera zones re-frame the shot for specific places (the canyon street
## looks up at its skybridges, the terrace pulls in, etc).  Never auto-rotates.
## Use: `var rig := FollowCamera.new()`, set `base` and `bounds`, add it to the world, then
## `rig.target = player` and `rig.snap()` (HD2D_RENDERING.md, Camera rig).

@export var target_path: NodePath
var target: Node3D
var cam: Camera3D

# base framing
var base := {"pitch": 25.0, "distance": 12.5, "fov": 32.0, "height": 1.15, "yaw": 0.0}
var zones: Array = []   # [{aabb: AABB, params: Dictionary, blend: float}]
var bounds := AABB(Vector3(-8.0, -5, -40), Vector3(18.5, 30, 47))

var _focus := Vector3.ZERO
var _look_ahead := Vector3.ZERO
var _cur := {}
var shake := 0.0
var cinematic := false   # when true, an external tween drives the camera

func _ready() -> void:
	cam = Camera3D.new()
	cam.current = true
	cam.near = 0.3
	cam.far = 220.0
	add_child(cam)
	_cur = base.duplicate()
	if target_path:
		target = get_node(target_path)
	if target:
		_focus = target.global_position

## Adds a camera zone: inside `aabb` the shot eases to `params` (any of pitch, distance, fov, height, yaw).
func add_zone(aabb: AABB, params: Dictionary) -> void:
	zones.append({"aabb": aabb, "params": params, "w": 0.0})

## Jumps straight to the target and the current framing, with no easing (after a spawn or a scene change).
func snap() -> void:
	if target:
		_focus = target.global_position
	_apply(1.0, 1.0)

func _physics_process(delta: float) -> void:
	if cinematic or target == null:
		return
	var tp := target.global_position
	var vel := Vector3.ZERO
	if target is CharacterBody3D:
		vel = (target as CharacterBody3D).velocity
	vel.y = 0
	_look_ahead = _look_ahead.lerp(vel * 0.35, 1.0 - exp(-delta * 2.0))
	var goal := tp + _look_ahead
	goal.x = clampf(goal.x, bounds.position.x, bounds.end.x)
	goal.z = clampf(goal.z, bounds.position.z, bounds.end.z)
	# vertical follow is damped more (stairs shouldn't jolt the shot)
	_focus.x = lerpf(_focus.x, goal.x, 1.0 - exp(-delta * 4.0))
	_focus.z = lerpf(_focus.z, goal.z, 1.0 - exp(-delta * 4.0))
	_focus.y = lerpf(_focus.y, goal.y, 1.0 - exp(-delta * 2.5))
	_apply(delta, 1.0 - exp(-delta * 2.2))

func _apply(delta: float, k: float) -> void:
	var want := base.duplicate()
	var tp: Vector3 = target.global_position if target else _focus
	for z in zones:
		var inside: bool = z.aabb.has_point(tp)
		z.w = move_toward(z.w, 1.0 if inside else 0.0, delta * 1.4)
		if z.w > 0.0:
			var e: float = z.w * z.w * (3.0 - 2.0 * z.w)
			for key in z.params:
				want[key] = lerpf(want[key], z.params[key], e)
	for key in want:
		_cur[key] = lerpf(_cur.get(key, want[key]), want[key], k)
	var pitch: float = deg_to_rad(float(_cur.pitch))
	var yaw: float = deg_to_rad(float(_cur.yaw))
	var look: Vector3 = _focus + Vector3(0, float(_cur.height), 0)
	var back: Vector3 = Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * float(_cur.distance)
	var p: Vector3 = look + back
	if shake > 0.0:
		p += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.15
		shake = move_toward(shake, 0.0, delta * 3.0)
	global_position = p
	cam.fov = _cur.fov
	look_at(look, Vector3.UP)
	RenderingServer.global_shader_parameter_set("camera_world_pos", global_position)
	if target and target.has_method("walk_to"):
		target.set("camera_yaw", yaw)

## The target's screen height (0.8 m above its feet) as 0 (top) to 1 (bottom), clamped to 0.2..0.85: the centre
## of the tilt-shift band (PixelView.focus_source reads it every frame).
func screen_focus_y() -> float:
	if target == null:
		return 0.55
	var sp := cam.unproject_position(target.global_position + Vector3(0, 0.8, 0))
	return clampf(sp.y / get_viewport().get_visible_rect().size.y, 0.2, 0.85)

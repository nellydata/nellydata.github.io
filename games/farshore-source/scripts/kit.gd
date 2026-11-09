class_name Kit
extends RefCounted
## Procedural architecture kit.
## Accumulates flat-shaded geometry per (material, spatial chunk) so that the
## whole district renders in a few dozen draw calls while every chunk still
## receives its nearby lamps (GL Compatibility caps lights per object).

const CHUNK := 10.0

var materials: Dictionary = {}     # key -> Material
var _tools: Dictionary = {}        # "key|cx|cz" -> SurfaceTool
var _occluder_keys: Dictionary = {}
var colliders: Array = []          # [{xform: Transform3D, size: Vector3}]
var ramps: Array = []              # [{a: Vector3, b: Vector3, width: float}]

func add_material(key: String, mat: Material, occluder := false) -> void:
	materials[key] = mat
	if occluder:
		_occluder_keys[key] = true

func _tool_for(key: String, p: Vector3) -> SurfaceTool:
	var cx := int(floor(p.x / CHUNK))
	var cz := int(floor(p.z / CHUNK))
	var k := "%s|%d|%d" % [key, cx, cz]
	if not _tools.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[k] = st
	return _tools[k]

# ------------------------------------------------------------------ primitives
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO, col := Color.WHITE) -> void:
	var st := _tool_for(key, (a + b + c) / 3.0)
	var n := (c - a).cross(b - a).normalized()  # clockwise = front face in Godot
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(uva); st.add_vertex(a)
	st.set_uv(uvb); st.add_vertex(b)
	st.set_uv(uvc); st.add_vertex(c)

## Quad with counter-clockwise winding seen from the front (a,b,c,d).
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv := Rect2(0, 0, 1, 1), col := Color.WHITE) -> void:
	var u0 := uv.position
	var u1 := uv.position + uv.size
	# a=bottom-left b=bottom-right c=top-right d=top-left
	tri(key, a, c, b, Vector2(u0.x, u1.y), Vector2(u1.x, u0.y), Vector2(u1.x, u1.y), col)
	tri(key, a, d, c, Vector2(u0.x, u1.y), Vector2(u0.x, u0.y), Vector2(u1.x, u0.y), col)

## Axis-aligned (optionally Y-rotated) box. Faces listed in `skip` are omitted
## ("top","bottom","n","s","e","w").
func box(key: String, center: Vector3, size: Vector3, rot_y := 0.0, col := Color.WHITE, skip: Array = [], collide := false) -> void:
	var h := size * 0.5
	var b := Basis(Vector3.UP, rot_y)
	var p := func(x: float, y: float, z: float) -> Vector3: return center + b * Vector3(x, y, z)
	var c: Array = [p.call(-h.x, -h.y, -h.z), p.call(h.x, -h.y, -h.z), p.call(h.x, -h.y, h.z), p.call(-h.x, -h.y, h.z),
			p.call(-h.x, h.y, -h.z), p.call(h.x, h.y, -h.z), p.call(h.x, h.y, h.z), p.call(-h.x, h.y, h.z)]
	if not "top" in skip: quad(key, c[7], c[6], c[5], c[4], Rect2(0, 0, 1, 1), col)
	if not "bottom" in skip: quad(key, c[0], c[1], c[2], c[3], Rect2(0, 0, 1, 1), col)
	if not "s" in skip: quad(key, c[3], c[2], c[6], c[7], Rect2(0, 0, 1, 1), col)   # +Z
	if not "n" in skip: quad(key, c[1], c[0], c[4], c[5], Rect2(0, 0, 1, 1), col)   # -Z
	if not "e" in skip: quad(key, c[2], c[1], c[5], c[6], Rect2(0, 0, 1, 1), col)   # +X
	if not "w" in skip: quad(key, c[0], c[3], c[7], c[4], Rect2(0, 0, 1, 1), col)   # -X
	if collide:
		add_collider(center, size, rot_y)

func add_collider(center: Vector3, size: Vector3, rot_y := 0.0) -> void:
	colliders.append({"xform": Transform3D(Basis(Vector3.UP, rot_y), center), "size": size})

## Vertical cylinder / prism (segments sides). Optional caps.
func cylinder(key: String, center: Vector3, radius: float, height: float, segments := 12, caps := true, col := Color.WHITE, radius_top := -1.0) -> void:
	var rt := radius if radius_top < 0.0 else radius_top
	var y0 := center.y
	var y1 := center.y + height
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := Vector3(center.x + cos(a0) * radius, y0, center.z + sin(a0) * radius)
		var p1 := Vector3(center.x + cos(a1) * radius, y0, center.z + sin(a1) * radius)
		var q0 := Vector3(center.x + cos(a0) * rt, y1, center.z + sin(a0) * rt)
		var q1 := Vector3(center.x + cos(a1) * rt, y1, center.z + sin(a1) * rt)
		quad(key, p1, p0, q0, q1, Rect2(0, 0, 1, 1), col)
		if caps:
			tri(key, Vector3(center.x, y1, center.z), q0, q1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
			tri(key, Vector3(center.x, y0, center.z), p1, p0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)

## Ring (annulus wall) — used for fountain basins.
func ring(key: String, center: Vector3, r_in: float, r_out: float, height: float, segments := 24, col := Color.WHITE) -> void:
	var y0 := center.y
	var y1 := center.y + height
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		var c := Vector3(center.x, 0, center.z)
		# outer wall
		quad(key, c + o1 * r_out + Vector3(0, y0, 0), c + o0 * r_out + Vector3(0, y0, 0), c + o0 * r_out + Vector3(0, y1, 0), c + o1 * r_out + Vector3(0, y1, 0), Rect2(0, 0, 1, 1), col)
		# inner wall
		quad(key, c + o0 * r_in + Vector3(0, y0, 0), c + o1 * r_in + Vector3(0, y0, 0), c + o1 * r_in + Vector3(0, y1, 0), c + o0 * r_in + Vector3(0, y1, 0), Rect2(0, 0, 1, 1), col)
		# top
		quad(key, c + o0 * r_out + Vector3(0, y1, 0), c + o0 * r_in + Vector3(0, y1, 0), c + o1 * r_in + Vector3(0, y1, 0), c + o1 * r_out + Vector3(0, y1, 0), Rect2(0, 0, 1, 1), col)

## Extrude a 2D outline (points in the local XY plane) along local Z by depth.
## The result is placed with `xform`. Outline must be convex-or-simple; caps
## are triangulated with Geometry2D.
func extrude(key: String, outline: PackedVector2Array, depth: float, xform: Transform3D, col := Color.WHITE, caps := true) -> void:
	var n := outline.size()
	var hz := depth * 0.5
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var p0 := xform * Vector3(a.x, a.y, hz)
		var p1 := xform * Vector3(b.x, b.y, hz)
		var p2 := xform * Vector3(b.x, b.y, -hz)
		var p3 := xform * Vector3(a.x, a.y, -hz)
		quad(key, p0, p3, p2, p1, Rect2(0, 0, 1, 1), col)
	if caps:
		var idx := Geometry2D.triangulate_polygon(outline)
		for t in range(0, idx.size(), 3):
			var a := outline[idx[t]]
			var b := outline[idx[t + 1]]
			var c := outline[idx[t + 2]]
			if (b - a).cross(c - a) < 0.0:
				var tmp := b
				b = c
				c = tmp
			tri(key, xform * Vector3(a.x, a.y, hz), xform * Vector3(c.x, c.y, hz), xform * Vector3(b.x, b.y, hz), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)
			tri(key, xform * Vector3(a.x, a.y, -hz), xform * Vector3(b.x, b.y, -hz), xform * Vector3(c.x, c.y, -hz), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)

## Semicircular arch ring (voussoirs) in local XY, extruded along Z.
func arch(key: String, xform: Transform3D, r_in: float, r_out: float, depth: float, segments := 10, col := Color.WHITE) -> void:
	for i in segments:
		var a0 := PI * i / segments
		var a1 := PI * (i + 1) / segments
		var outline := PackedVector2Array([
			Vector2(cos(a0) * r_out, sin(a0) * r_out), Vector2(cos(a1) * r_out, sin(a1) * r_out),
			Vector2(cos(a1) * r_in, sin(a1) * r_in), Vector2(cos(a0) * r_in, sin(a0) * r_in)])
		extrude(key, outline, depth, xform, col)

## Stairs going up along +dir from `start` (centre of bottom step front edge).
func stairs(key: String, start: Vector3, dir: Vector3, width: float, rise: float, steps: int, tread := 0.32, col := Color.WHITE) -> void:
	var d := dir.normalized()
	var rot := atan2(d.x, d.z)
	var step_h := rise / steps
	for i in steps:
		var c := start + d * (tread * (i + 0.5)) + Vector3(0, step_h * (i + 0.5), 0)
		var h := step_h * (i + 1)
		box(key, start + d * (tread * (i + 0.5)) + Vector3(0, h * 0.5, 0), Vector3(width, h, tread), rot, col, ["bottom"])
	ramps.append({"a": start, "b": start + d * tread * steps + Vector3(0, rise, 0), "width": width})

# ------------------------------------------------------------------ build
func build(parent: Node3D) -> void:
	for k in _tools.keys():
		var parts: PackedStringArray = k.split("|")
		var key := parts[0]
		var st: SurfaceTool = _tools[k]
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Geo_%s_%s_%s" % [key, parts[1], parts[2]]
		mi.mesh = mesh
		mi.material_override = materials.get(key)
		if _occluder_keys.has(key):
			mi.set_meta("occluder", true)
		parent.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	parent.add_child(body)
	for c in colliders:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c.size
		cs.shape = bs
		cs.transform = c.xform
		body.add_child(cs)
	for r in ramps:
		# invisible collision ramp so the character walks smoothly up steps
		var a: Vector3 = r.a
		var b: Vector3 = r.b
		var flat := Vector3(b.x - a.x, 0, b.z - a.z)
		var length := Vector3(flat.x, b.y - a.y, flat.z).length()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(r.width, 0.1, length)
		cs.shape = bs
		var fwd := (b - a).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var up := right.cross(fwd).normalized()
		cs.transform = Transform3D(Basis(right, up, -fwd).orthonormalized(), (a + b) * 0.5 - up * 0.04)
		body.add_child(cs)

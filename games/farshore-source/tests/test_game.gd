extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func reachable_landmarks(game: Node) -> Array:
	var visited := {}
	var queue: Array[Vector2i] = [Vector2i(-6, 16)]
	var reached := [false, false, false, false]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if visited.has(cell):
			continue
		visited[cell] = true
		var p := Vector2(cell) * 0.5
		var blocked := false
		for obstacle in game.obstacles:
			if p.distance_to(obstacle.center) < obstacle.radius + game.PLAYER_RADIUS + 0.05:
				blocked = true
				break
		if blocked:
			continue
		if p.length() < game.TOWER_REACH:
			reached[0] = true
		for i in 3:
			var target: Vector3 = game.STONES[i].position
			if p.distance_to(Vector2(target.x, target.z)) < 2.1:
				reached[i + 1] = true
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if absi(next.x) <= 29 and absi(next.y) <= 29 and not visited.has(next):
				queue.append(next)
	return reached


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._close_panel()
	check(not game.hero_sprite.no_depth_test, "hero is occluded by world geometry")
	check(game.hero_frames.up[0] != game.hero_frames.down[0] and game.hero_frames.down[1] != game.hero_frames.down[2], "directional walking frames exist")
	check(reachable_landmarks(game) == [true, true, true, true], "all landmarks remain reachable around obstacles")
	var saved_obstacles: Array[Dictionary] = game.obstacles.duplicate()
	game.obstacles.clear()
	game.obstacles.append({"center": Vector2.ZERO, "radius": 2.0})
	game.hero.position = Vector3(-4, 0, 0)
	game._move_hero(Vector2(8, 0))
	check(game.hero.position.x < -2.31, "large movement cannot tunnel through the tower")
	game.hero.position = Vector3(-3, 0, 0)
	game._move_hero(Vector2(2, 1))
	check(game.hero.position.z > 0.1 and game.hero.position.length() >= 2.31, "movement slides around obstacles")
	game.hero.position = Vector3.ZERO
	game._move_hero(Vector2(-4, 0))
	check(game.hero.position.x < -2.31, "old saves inside obstacles can escape")
	game.obstacles.clear()
	game.hero.position.x = 14.4
	game.held.right = true
	game._process(2.0)
	game.held.right = false
	check(game.hero.position.x == 14.5, "movement is bounded to the island")
	game.obstacles = saved_obstacles
	game.hero.position = game.TOWER
	game._interact()
	check(not game.complete and game.panel_title.text == "THE SIGNAL TOWER", "tower must require all stones")
	game._close_panel()
	for i in 3:
		game.hero.position = game.STONES[i].position
		game._interact()
		check(game.found[i] and not game.stones[i].visible, "stone %d collected" % i)
		game._close_panel()
		if i == 0:
			game._interact()
			check(game.found.count(true) == 1 and not game.panel.visible, "collected stone cannot be collected twice")
	game.hero.position = game.TOWER
	game._interact()
	check(game.complete and game.panel_title.text == "THE SIGNAL RETURNS", "tower completes after all stones")
	game.found = [false, false, false]
	game.complete = false
	game._load_progress()
	check(game.found == [true, true, true] and game.complete, "saved completion reloads")
	var file := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"version":1,"found":[true,false,false],"complete":true}')
	file.close()
	game.found = [false, false, false]
	game.complete = false
	game._load_progress()
	check(not game.complete and not game.save_warning.is_empty(), "invalid save is rejected visibly")
	game._show_panel("TEST", "Test", "OK")
	check(game.panel_text.text.contains("Save unavailable"), "save warning appears in modal")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.SAVE_PATH))
	game.queue_free()
	await process_frame
	print("Farshore tests: %s" % ("PASS" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)

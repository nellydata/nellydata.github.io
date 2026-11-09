extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._close_panel()
	game.hero.position.x = 14.4
	game.held.right = true
	game._process(2.0)
	game.held.right = false
	check(game.hero.position.x == 14.5, "movement is bounded to the island")
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

# Farshore

An original, small exploration game for the web by NellyData. Find three windstones
on the island and bring their light back to the old signal tower.

The project uses selected presentation helpers and shaders from NellyData's
HD2D-Framework at commit `a7f31de`, with original procedural game art. Godot 4.7.2
and its matching single-threaded Web export templates are required.

Import the project with Godot, then export the `Web` preset to `../farshore/index.html`.
The website hosts that exported build. Arrow keys/WASD and the on-screen controls move;
Space/Enter or the action button interact. Progress is saved in browser storage when
a windstone is found and on completion. Browser site-data clearing removes the save.

Run the quest and save checks in an isolated data directory with:

```sh
XDG_DATA_HOME=/tmp/farshore-test-data godot --headless --path games/farshore-source --script res://tests/test_game.gd
```

The test uses and removes the Farshore save in that directory. Use a fresh,
dedicated directory rather than the one containing your normal game data.

This is a short playable game, not a large open-world release. It has not been
validated on a physical phone; browser/device emulation is not a substitute.

# Farshore Unreal prototype

This is a separate Windows desktop prototype of Farshore for Unreal Engine 5.8.
It is not the Godot website build. The island and game code use original
procedural shapes and engine-provided primitives; it contains no assets copied
from other studio games. Move with WASD or arrows; use E, Space, or Enter.

Open `Farshore.uproject` in Unreal Engine 5.8.3 or build `FarshoreEditor` for
Win64 Development with UnrealBuildTool. The project creates its island at
runtime in the engine's Entry map. A packaged build and device validation are
not yet established.

References consulted: Epic's [engine access instructions](https://github.com/EpicGames/Signup)
and [Unreal Editor MCP setup](https://github.com/EpicGames/unreal-engine-skills-for-claude-code-plugin).
No third-party artwork or source was incorporated.

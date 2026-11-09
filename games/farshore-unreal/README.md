# Farshore Unreal prototype

This is a separate, early Windows desktop prototype of Farshore for Unreal Engine
5.8. It is not the Godot website build and does not yet match its art or polish.
The island and game code use original procedural shapes, an original generated
tint material, and engine-provided primitives; it contains no assets copied from
other studio games. Move with WASD or arrows; use E, Space, or Enter.

Open `Farshore.uproject` in Unreal Engine 5.8.3 or build `FarshoreEditor` for
Win64 Development with UnrealBuildTool. The project creates its island at
runtime in the engine's Entry map. Progress is stored in the separate
`FarshoreUnreal` Unreal save slot. Desktop input, collision, visual quality,
packaged behavior, audio, and performance still need a human playtest.

References consulted: Epic's [engine access instructions](https://github.com/EpicGames/Signup)
and [Unreal Editor MCP setup](https://github.com/EpicGames/unreal-engine-skills-for-claude-code-plugin).
No third-party artwork or source was incorporated.

# Research decisions

Godot 4.7.2 official Linux editor and matching templates are pinned and checksum verified.
Context7 Godot 4.7 documentation informed CLI import/export, navigation, scenes and persistence.
Mobile supports glow and regular fog; no volumetric fog is used. Real GPU performance
must be measured independently of headless checks.

Blender 5.2.1 is supplied locally. Host headless startup/exit works; restricted sandbox
GPU, audio-mainloop and keyring errors are environmental, not host failures.
The host Intel Core Ultra 5 125H / integrated Arc has Mesa 25.0.7 and Vulkan 1.4 support.
GLB exports make Blender unnecessary in normal Godot CI. No asset pack or test plugin.

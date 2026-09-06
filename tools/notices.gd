extends SceneTree

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/licenses")
	var license:=FileAccess.open("res://docs/licenses/GODOT_LICENSE.txt",FileAccess.WRITE)
	license.store_string(Engine.get_license_text())
	license.close()
	var copyright_file:=FileAccess.open("res://docs/licenses/GODOT_COPYRIGHT.json",FileAccess.WRITE)
	copyright_file.store_string(JSON.stringify(Engine.get_copyright_info(),"  "))
	copyright_file.close()
	var all_licenses:=FileAccess.open("res://docs/licenses/GODOT_LICENSES.json",FileAccess.WRITE)
	all_licenses.store_string(JSON.stringify(Engine.get_license_info(),"  "))
	all_licenses.close()
	print("ENGINE_NOTICES_OK")
	quit()

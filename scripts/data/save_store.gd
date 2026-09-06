class_name SaveStore
extends RefCounted

const GameSessionScript = preload("res://scripts/data/game_session.gd")

const SCHEMA_VERSION := 2
const LEGACY_SCHEMA_VERSION := 1
const PROFILE_COUNT := 3
const DEFAULT_ROOT_DIRECTORY := "user://saves"

const ERROR_NONE := ""
const ERROR_MISSING := "missing"
const ERROR_CORRUPT := "corrupt_json"
const ERROR_INVALID := "invalid_data"
const ERROR_UNSUPPORTED_VERSION := "unsupported_version"
const ERROR_INVALID_PROFILE := "invalid_profile"
const ERROR_IO := "io_error"

var root_directory: String


func _init(directory: String = DEFAULT_ROOT_DIRECTORY) -> void:
	root_directory = directory.trim_suffix("/")


func save_profile(index: int, resume: Dictionary, checkpoint: Dictionary) -> Error:
	if not _valid_profile_index(index):
		return ERR_INVALID_PARAMETER
	if not GameSessionScript.is_valid_snapshot(resume) or not GameSessionScript.is_valid_snapshot(checkpoint):
		return ERR_INVALID_DATA

	var write_check := can_write_profile(index)
	if not write_check.ok:
		return ERR_FILE_UNRECOGNIZED if write_check.error == ERROR_UNSUPPORTED_VERSION else ERR_FILE_CANT_WRITE

	var paths := _profile_paths(index)
	var active_inspection := _inspect_file(paths.active)

	var directory_error := DirAccess.make_dir_recursive_absolute(root_directory)
	if directory_error != OK and not DirAccess.dir_exists_absolute(root_directory):
		return directory_error

	var envelope := {
		"version": SCHEMA_VERSION,
		"resume": resume.duplicate(true),
		"checkpoint": checkpoint.duplicate(true),
	}
	var write_error := _write_envelope(paths.temporary, envelope)
	if write_error != OK:
		return write_error
	var temporary_inspection := _inspect_file(paths.temporary)
	if not temporary_inspection.ok:
		DirAccess.remove_absolute(paths.temporary)
		return ERR_FILE_CORRUPT

	# Only a validated active save may become the last-good backup.
	if active_inspection.ok:
		var backup_error := DirAccess.copy_absolute(paths.active, paths.backup)
		if backup_error != OK:
			DirAccess.remove_absolute(paths.temporary)
			return backup_error

	if FileAccess.file_exists(paths.active):
		var remove_error := DirAccess.remove_absolute(paths.active)
		if remove_error != OK:
			DirAccess.remove_absolute(paths.temporary)
			return remove_error
	var rename_error := DirAccess.rename_absolute(paths.temporary, paths.active)
	if rename_error != OK:
		if FileAccess.file_exists(paths.backup):
			DirAccess.copy_absolute(paths.backup, paths.active)
		return rename_error
	# Seed recovery on the first save, and repair a corrupt known-version backup
	# after the caller has explicitly chosen to overwrite an unusable profile.
	var backup_after_write := _inspect_file(paths.backup)
	if not backup_after_write.ok:
		var seed_backup_error := DirAccess.copy_absolute(paths.active, paths.backup)
		if seed_backup_error != OK:
			return seed_backup_error
	return OK


## Checks destructive compatibility before a caller mutates in-memory state for a new game.
## Corrupt or invalid known-version data remains writable after the caller confirms overwrite.
func can_write_profile(index: int) -> Dictionary:
	if not _valid_profile_index(index):
		return {"ok": false, "error": ERROR_INVALID_PROFILE}
	var paths := _profile_paths(index)
	for path: String in [paths.active, paths.backup]:
		var inspection := _inspect_file(path)
		if inspection.error == ERROR_UNSUPPORTED_VERSION:
			return {"ok": false, "error": ERROR_UNSUPPORTED_VERSION}
		if inspection.error == ERROR_IO:
			return {"ok": false, "error": ERROR_IO}
	return {"ok": true, "error": ERROR_NONE}


func load_profile(index: int) -> Dictionary:
	if not _valid_profile_index(index):
		return _load_result(false, ERROR_INVALID_PROFILE, false, false, 0, {})

	var paths := _profile_paths(index)
	var active := _inspect_file(paths.active)
	if active.ok:
		return _load_result(true, ERROR_NONE, false, active.migrated, active.version, active.data)
	if active.error == ERROR_UNSUPPORTED_VERSION:
		return _load_result(false, active.error, false, false, active.version, {})

	var backup := _inspect_file(paths.backup)
	if backup.ok:
		return _load_result(true, active.error, true, backup.migrated, backup.version, backup.data)
	if backup.error == ERROR_UNSUPPORTED_VERSION:
		return _load_result(false, backup.error, false, false, backup.version, {})

	var error: String = active.error
	if error == ERROR_MISSING:
		error = backup.error
	if error == ERROR_MISSING:
		return _load_result(false, ERROR_MISSING, false, false, 0, {})
	return _load_result(false, error, false, false, int(active.version), {})


func profile_summary(index: int) -> Dictionary:
	var loaded := load_profile(index)
	if not loaded.ok:
		return {
			"exists": loaded.error != ERROR_MISSING and loaded.error != ERROR_INVALID_PROFILE,
			"ok": false,
			"error": loaded.error,
			"recovered": loaded.recovered,
			"migrated": loaded.migrated,
			"version": loaded.version,
		}
	var resume: Dictionary = loaded.data.resume
	return {
		"exists": true,
		"ok": true,
		"error": loaded.error,
		"recovered": loaded.recovered,
		"migrated": loaded.migrated,
		"version": loaded.version,
		"scene_id": resume.scene_id,
		"artifact_collected": resume.flags.artifact_collected,
		"crystal_collected": resume.flags.crystal_collected,
	}


func _inspect_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": ERROR_MISSING, "version": 0, "migrated": false, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": ERROR_IO, "version": 0, "migrated": false, "data": {}}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": ERROR_CORRUPT, "version": 0, "migrated": false, "data": {}}
	var envelope: Variant = parser.data
	if typeof(envelope) != TYPE_DICTIONARY:
		return {"ok": false, "error": ERROR_INVALID, "version": 0, "migrated": false, "data": {}}

	var version: Variant = _read_schema_version(envelope.get("version"))
	if version == null:
		return {"ok": false, "error": ERROR_INVALID, "version": 0, "migrated": false, "data": {}}
	if version > SCHEMA_VERSION:
		return {"ok": false, "error": ERROR_UNSUPPORTED_VERSION, "version": version, "migrated": false, "data": {}}
	if version != SCHEMA_VERSION and version != LEGACY_SCHEMA_VERSION:
		return {"ok": false, "error": ERROR_UNSUPPORTED_VERSION, "version": version, "migrated": false, "data": {}}
	if not _has_exact_keys(envelope, ["version", "resume", "checkpoint"]):
		return {"ok": false, "error": ERROR_INVALID, "version": version, "migrated": false, "data": {}}

	var resume: Variant = envelope.resume
	var checkpoint: Variant = envelope.checkpoint
	var migrated: bool = version == LEGACY_SCHEMA_VERSION
	if migrated:
		resume = GameSessionScript.migrate_v1_snapshot(resume)
		checkpoint = GameSessionScript.migrate_v1_snapshot(checkpoint)
	if not GameSessionScript.is_valid_snapshot(resume) or not GameSessionScript.is_valid_snapshot(checkpoint):
		return {"ok": false, "error": ERROR_INVALID, "version": version, "migrated": false, "data": {}}
	return {
		"ok": true,
		"error": ERROR_NONE,
		"version": version,
		"migrated": migrated,
		"data": {"resume": resume.duplicate(true), "checkpoint": checkpoint.duplicate(true)},
	}


func _write_envelope(path: String, envelope: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(envelope, "\t"))
	file.flush()
	var file_error := file.get_error()
	file = null
	return file_error


func _profile_paths(index: int) -> Dictionary:
	var stem := "%s/profile_%d.json" % [root_directory, index + 1]
	return {"active": stem, "temporary": stem + ".tmp", "backup": stem + ".bak"}


func _valid_profile_index(index: int) -> bool:
	return index >= 0 and index < PROFILE_COUNT


static func _read_schema_version(value: Variant) -> Variant:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return null
	var parsed := float(value)
	if not is_finite(parsed) or parsed != floor(parsed) or parsed < 0.0 or parsed > 2147483647.0:
		return null
	return int(parsed)


static func _has_exact_keys(data: Dictionary, expected: Array) -> bool:
	if data.size() != expected.size():
		return false
	for key: String in expected:
		if not data.has(key):
			return false
	return true


static func _load_result(
	ok: bool,
	error: String,
	recovered: bool,
	migrated: bool,
	version: int,
	data: Dictionary
) -> Dictionary:
	return {
		"ok": ok,
		"error": error,
		"recovered": recovered,
		"migrated": migrated,
		"version": version,
		"data": data,
	}

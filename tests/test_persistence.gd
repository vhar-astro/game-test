extends RefCounted

const GameSessionScript = preload("res://scripts/data/game_session.gd")
const SaveStoreScript = preload("res://scripts/data/save_store.gd")

var _failures: Array[String] = []
var _root := ""


func run() -> Array[String]:
	_failures.clear()
	_root = "user://test_persistence_%d" % Time.get_ticks_usec()
	_test_progression_and_duplicate_collects()
	_test_transactional_restore_validation()
	_test_ship_state_transitions()
	_test_legacy_schema_migration()
	_test_roundtrip_profile_isolation_and_checkpoint()
	_test_corrupt_and_invalid_active_recover_from_backup()
	_test_future_schema_is_preserved()
	_cleanup()
	return _failures


func _test_progression_and_duplicate_collects() -> void:
	var session = GameSessionScript.new()
	_expect(not session.travel_to(GameSessionScript.SCENE_RUINS), "ruins must remain locked before crystal collection")
	_expect(not session.mark_robot_defeated(), "robot defeat must follow puzzle completion")
	_expect(not session.collect_artifact(), "artifact must remain gated before robot defeat")
	_expect(session.mark_puzzle_solved(), "puzzle should complete once")
	_expect(not session.mark_puzzle_solved(), "puzzle completion must be idempotent")
	_expect(session.mark_robot_defeated(), "robot should be defeated after the puzzle")
	_expect(session.collect_artifact(), "artifact should be collectible after robot defeat")
	_expect(not session.collect_artifact(), "duplicate artifact collection must be rejected")
	_expect(session.open_resonant_lock(), "artifact should open the resonant lock")
	_expect(not session.open_resonant_lock(), "opening the lock twice must be rejected")
	_expect(session.collect_crystal(), "crystal should be collectible after lock opens")
	_expect(not session.collect_crystal(), "duplicate crystal collection must be rejected")
	_expect(session.travel_to(GameSessionScript.SCENE_RUINS), "crystal should unlock ruins travel")
	_expect(session.travel_to(GameSessionScript.SCENE_HUB), "hub travel should be available")
	_expect(session.travel_to(GameSessionScript.SCENE_FOREST), "a visited dimension should remain revisitable")
	_expect(session.visited_scenes == ["forest", "ruins", "hub"], "visited scenes must retain unique traversal history")
	_expect(session.collect_memory_shard(GameSessionScript.FLIGHT_MEMORY_SHARD_ID), "the flight memory id should be accepted by the generic shard collector")
	_expect(not session.collect_memory_shard(GameSessionScript.FLIGHT_MEMORY_SHARD_ID), "the flight memory id should still reject duplicate collection")


func _test_transactional_restore_validation() -> void:
	var session = _completed_session(Vector3(3.0, 4.0, 5.0), 72.0)
	var before: Dictionary = session.to_dict()
	var invalid := before.duplicate(true)
	invalid.player.position[0] = INF
	_expect(not session.restore(invalid), "restore must reject non-finite transforms")
	_expect(session.to_dict() == before, "rejected restore must not partially mutate session")
	invalid = before.duplicate(true)
	invalid.flags.robot_defeated = false
	_expect(not session.restore(invalid), "restore must reject impossible progression flags")
	invalid = before.duplicate(true)
	invalid.health = 101.0
	_expect(not session.restore(invalid), "restore must reject out-of-range health")
	invalid = before.duplicate(true)
	invalid.movement_mode = GameSessionScript.MOVEMENT_SHIP
	_expect(not session.restore(invalid), "restore must reject an aboard snapshot whose ship is landed")
	_expect(session.to_dict() == before, "rejected ship state must not partially mutate session")
	invalid = before.duplicate(true)
	invalid.ship.rotation = [PI / 2.0 + 0.01, 0.0, 0.0]
	_expect(not session.restore(invalid), "restore must reject ship pitch outside plus or minus pi over two")
	invalid = before.duplicate(true)
	invalid.ship.rotation = [0.0, 0.0, 0.1]
	_expect(not session.restore(invalid), "restore must reject persisted ship roll")
	invalid = before.duplicate(true)
	invalid.ship["unexpected"] = true
	_expect(not session.restore(invalid), "restore must reject unknown ship fields")


func _test_ship_state_transitions() -> void:
	var session = GameSessionScript.new()
	_expect(session.movement_mode == GameSessionScript.MOVEMENT_ON_FOOT, "a new game should begin on foot")
	_expect(session.ship_scene_id == "forest" and session.ship_landed, "the personal ship should begin parked in the forest")
	_expect(session.ship_position == GameSessionScript.DEFAULT_SHIP_POSITION, "the personal ship should use its authored forest parking pose")
	_expect(not session.set_movement_mode(GameSessionScript.MOVEMENT_SHIP), "boarding cannot commit while the ship is still landed")
	_expect(session.set_ship_state(
		"forest",
		Vector3(-4.0, 3.5, 10.0),
		Vector3(0.25, 1.2, 0.0),
		false,
		GameSessionScript.DEFAULT_SHIP_POSITION,
		GameSessionScript.DEFAULT_SHIP_YAW
	), "lift-off should atomically record an airborne ship")
	_expect(session.set_movement_mode(GameSessionScript.MOVEMENT_SHIP), "boarding should commit after lift-off")
	var before_invalid := session.to_dict()
	_expect(not session.set_ship_state(
		"ruins", Vector3.ZERO, Vector3.ZERO, false, Vector3.ZERO, 0.0
	), "an aboard ship cannot move dimensions independently of the player")
	_expect(session.to_dict() == before_invalid, "a rejected ship setter must leave every ship field unchanged")
	_expect(not session.travel_ship_to("ruins", Vector3(2.0, 4.0, 5.0), Vector3.ZERO), "locked ruins must remain locked for ship travel")
	session.mark_puzzle_solved()
	session.mark_robot_defeated()
	session.collect_artifact()
	session.open_resonant_lock()
	session.collect_crystal()
	_expect(session.travel_ship_to(
		"ruins", Vector3(2.0, 4.0, 5.0), Vector3(-0.2, 0.7, 0.0)
	), "an unlocked ship portal should move the player and personal ship together")
	_expect(session.scene_id == "ruins" and session.ship_scene_id == "ruins", "ship portal travel must keep the aboard invariant")
	_expect(session.visited_scenes == ["forest", "ruins"], "ship portal travel should record destination history once")
	_expect(session.ship_last_landed_position == Vector3(2.0, 4.0, 5.0) and is_equal_approx(session.ship_last_landed_yaw, 0.7), "the destination launch pose should become the ship's safe recovery point")


func _test_legacy_schema_migration() -> void:
	var legacy_root := _root + "_legacy"
	var store = SaveStoreScript.new(legacy_root)
	var scene_names := ["forest", "ruins", "hub"]
	for index in scene_names.size():
		var legacy_session = _completed_session(Vector3(index + 0.25, 1.5, -index), 90.0 - index)
		if scene_names[index] != "forest":
			legacy_session.travel_to(scene_names[index])
		legacy_session.collect_memory_shard("legacy_shard_%d" % index)
		var legacy_resume := _v1_snapshot(legacy_session.to_dict())
		var legacy_checkpoint := legacy_resume.duplicate(true)
		legacy_checkpoint.player.position = [index + 10.0, 0.0, -2.0]
		var envelope := {"version": 1, "resume": legacy_resume, "checkpoint": legacy_checkpoint}
		var path := "%s/profile_%d.json" % [legacy_root, index + 1]
		var original_text := JSON.stringify(envelope)
		var persisted_envelope: Dictionary = JSON.parse_string(original_text)
		_write_text_at(legacy_root, path, original_text)

		var loaded: Dictionary = store.load_profile(index)
		_expect(loaded.ok and loaded.migrated and not loaded.recovered, "a valid v1 %s save should migrate in memory" % scene_names[index])
		_expect(loaded.version == 1, "a migrated load should report its source schema version")
		_expect(_v1_snapshot(loaded.data.resume) == persisted_envelope.resume, "v1 %s resume fields must survive migration without data loss" % scene_names[index])
		_expect(_v1_snapshot(loaded.data.checkpoint) == persisted_envelope.checkpoint, "v1 %s checkpoint fields must survive migration without data loss" % scene_names[index])
		_expect(loaded.data.resume.movement_mode == GameSessionScript.MOVEMENT_ON_FOOT, "legacy saves should seed on-foot movement")
		_expect(loaded.data.resume.ship.scene_id == "forest" and loaded.data.resume.ship.landed, "legacy saves should seed the one parked forest ship")
		_expect(_read_text_at(path) == original_text, "loading v1 must not rewrite the active file")

	var summary: Dictionary = store.profile_summary(1)
	_expect(summary.ok and summary.migrated and summary.version == 1, "profile summaries should expose legacy migration")
	var migrated_profile: Dictionary = store.load_profile(0)
	_expect(store.save_profile(0, migrated_profile.data.resume, migrated_profile.data.checkpoint) == OK, "the next save after migration should write schema v2")
	var rewritten: Variant = JSON.parse_string(_read_text_at("%s/profile_1.json" % legacy_root))
	var validated_backup: Variant = JSON.parse_string(_read_text_at("%s/profile_1.json.bak" % legacy_root))
	_expect(typeof(rewritten) == TYPE_DICTIONARY and rewritten.version == SaveStoreScript.SCHEMA_VERSION, "saving migrated data should produce a v2 active envelope")
	_expect(typeof(validated_backup) == TYPE_DICTIONARY and validated_backup.version == 1, "the validated v1 predecessor should remain available as recovery data")

	var backup_root := _root + "_legacy_backup"
	var backup_store = SaveStoreScript.new(backup_root)
	var backup_session = GameSessionScript.new()
	backup_session.player_position = Vector3(12.0, 0.0, 3.0)
	var backup_snapshot := _v1_snapshot(backup_session.to_dict())
	_write_text_at(backup_root, "%s/profile_1.json.bak" % backup_root, JSON.stringify({
		"version": 1, "resume": backup_snapshot, "checkpoint": backup_snapshot
	}))
	var backup_loaded: Dictionary = backup_store.load_profile(0)
	_expect(backup_loaded.ok and backup_loaded.recovered and backup_loaded.migrated, "a backup-only v1 profile should migrate and recover")
	_expect(backup_loaded.data.resume.player.position[0] == 12.0, "backup-only legacy recovery should preserve player data")

	var malformed_root := _root + "_legacy_malformed"
	var malformed_store = SaveStoreScript.new(malformed_root)
	var malformed := backup_snapshot.duplicate(true)
	malformed["movement_mode"] = GameSessionScript.MOVEMENT_ON_FOOT
	_write_text_at(malformed_root, "%s/profile_1.json" % malformed_root, JSON.stringify({
		"version": 1, "resume": malformed, "checkpoint": backup_snapshot
	}))
	var malformed_loaded: Dictionary = malformed_store.load_profile(0)
	_expect(not malformed_loaded.ok and malformed_loaded.error == SaveStoreScript.ERROR_INVALID, "a malformed v1 shape must be rejected instead of partially migrated")

	_cleanup_directory(legacy_root)
	_cleanup_directory(backup_root)
	_cleanup_directory(malformed_root)


func _test_roundtrip_profile_isolation_and_checkpoint() -> void:
	var store = SaveStoreScript.new(_root)
	var first = _completed_session(Vector3(10.0, 2.0, -4.0), 44.0)
	first.travel_to(GameSessionScript.SCENE_RUINS)
	first.collect_memory_shard()
	first.collect_memory_shard(GameSessionScript.FLIGHT_MEMORY_SHARD_ID)
	first.set_prism_orientation(0, 3)
	first.set_hint_progress(58.5, 2)
	_expect(first.set_ship_state(
		"ruins",
		Vector3(6.0, 8.0, -3.0),
		Vector3(-0.3, 2.2, 0.0),
		false,
		Vector3(4.0, 0.08, 2.0),
		1.1
	), "mid-flight setup should be valid")
	_expect(first.set_movement_mode(GameSessionScript.MOVEMENT_SHIP), "mid-flight resume should record ship movement mode")
	var checkpoint = GameSessionScript.new()
	checkpoint.player_position = Vector3(1.0, 0.0, 1.0)
	checkpoint.health = 100.0
	checkpoint.travel_to(GameSessionScript.SCENE_HUB)
	_expect(checkpoint.set_ship_state(
		"hub",
		Vector3(-2.0, 0.08, 5.0),
		Vector3(0.0, -0.8, 0.0),
		true,
		Vector3(-2.0, 0.08, 5.0),
		-0.8
	), "checkpoint should retain a personal ship parked outside the forest")
	_expect(store.save_profile(0, first.to_dict(), checkpoint.to_dict()) == OK, "profile 1 should save")

	var second = GameSessionScript.new()
	second.player_position = Vector3(-9.0, 0.0, 6.0)
	second.health = 81.0
	_expect(store.save_profile(1, second.to_dict(), second.to_dict()) == OK, "profile 2 should save independently")
	_expect(not store.load_profile(2).ok and store.load_profile(2).error == SaveStoreScript.ERROR_MISSING, "profile 3 should remain empty")

	var loaded_first: Dictionary = store.load_profile(0)
	var loaded_second: Dictionary = store.load_profile(1)
	_expect(loaded_first.ok and not loaded_first.recovered, "profile 1 should round-trip from active save")
	_expect(not loaded_first.migrated and loaded_first.version == SaveStoreScript.SCHEMA_VERSION, "native v2 loads should report no migration")
	_expect(loaded_second.ok and loaded_second.data.resume.player.position[0] == -9.0, "profile 2 data must stay isolated")
	var restored = GameSessionScript.new()
	_expect(restored.restore(loaded_first.data.resume), "resume snapshot should restore")
	_expect(restored.scene_id == "ruins" and restored.player_position == Vector3(10.0, 2.0, -4.0), "round-trip should preserve scene and transform")
	_expect(restored.memory_shards == [GameSessionScript.MEMORY_SHARD_ID, GameSessionScript.FLIGHT_MEMORY_SHARD_ID], "round-trip should preserve optional memory shards")
	_expect(restored.prism_orientations == [3, 0, 0] and restored.hint_level == 2, "round-trip should preserve puzzle and hint state")
	_expect(restored.movement_mode == GameSessionScript.MOVEMENT_SHIP and not restored.ship_landed, "round-trip should resume mid-flight aboard the ship")
	_expect(restored.ship_scene_id == "ruins" and restored.ship_position == Vector3(6.0, 8.0, -3.0), "mid-flight ship transform should round-trip")
	_expect(restored.ship_last_landed_position == Vector3(4.0, 0.08, 2.0), "mid-flight saves should retain the last safe landing")

	_expect(restored.restore(loaded_first.data.checkpoint), "encounter checkpoint should restore independently")
	_expect(restored.health == 100.0 and not restored.artifact_collected, "checkpoint rollback must discard post-checkpoint encounter progress")
	_expect(restored.movement_mode == GameSessionScript.MOVEMENT_ON_FOOT and restored.ship_landed, "checkpoint rollback should restore parked ship state")
	_expect(restored.ship_scene_id == "hub" and restored.ship_last_landed_position == Vector3(-2.0, 0.08, 5.0), "checkpoint should retain the ship's other-dimension landing")
	var summary: Dictionary = store.profile_summary(0)
	_expect(summary.ok and summary.scene_id == "ruins" and summary.crystal_collected, "profile summary should expose safe resume metadata")


func _test_corrupt_and_invalid_active_recover_from_backup() -> void:
	var first_save_root := _root + "_first_save"
	var first_save_store = SaveStoreScript.new(first_save_root)
	var first_snapshot = GameSessionScript.new()
	first_snapshot.player_position = Vector3(2.0, 0.0, 0.0)
	_expect(first_save_store.save_profile(0, first_snapshot.to_dict(), first_snapshot.to_dict()) == OK, "first save should seed recovery data")
	_write_text_at(first_save_root, "%s/profile_1.json" % first_save_root, "{ corrupt first active")
	var recovered_first: Dictionary = first_save_store.load_profile(0)
	_expect(recovered_first.ok and recovered_first.recovered and recovered_first.data.resume.player.position[0] == 2.0, "the very first save must recover after active-file corruption")
	_cleanup_directory(first_save_root)

	var store = SaveStoreScript.new(_root)
	var original = GameSessionScript.new()
	original.player_position = Vector3(7.0, 0.0, 0.0)
	var newer = GameSessionScript.new()
	newer.player_position = Vector3(8.0, 0.0, 0.0)
	_expect(store.save_profile(0, original.to_dict(), original.to_dict()) == OK, "recovery setup should create original active")
	_expect(store.save_profile(0, newer.to_dict(), newer.to_dict()) == OK, "second save should create last-good backup")
	_write_text(_profile_path(0), "{ definitely not json")
	var recovered_corrupt: Dictionary = store.load_profile(0)
	_expect(recovered_corrupt.ok and recovered_corrupt.recovered, "corrupt active save should recover from backup")
	_expect(recovered_corrupt.error == SaveStoreScript.ERROR_CORRUPT, "recovery should report why active save was rejected")
	_expect(recovered_corrupt.data.resume.player.position[0] == 7.0, "corrupt recovery should return last-good snapshot")

	var old_profile_two = GameSessionScript.new()
	old_profile_two.health = 93.0
	var new_profile_two = GameSessionScript.new()
	new_profile_two.health = 34.0
	_expect(store.save_profile(1, old_profile_two.to_dict(), old_profile_two.to_dict()) == OK, "invalid recovery setup should save original")
	_expect(store.save_profile(1, new_profile_two.to_dict(), new_profile_two.to_dict()) == OK, "invalid recovery setup should create backup")
	var invalid_envelope := {"version": SaveStoreScript.SCHEMA_VERSION, "resume": {"bad": true}, "checkpoint": new_profile_two.to_dict()}
	_write_text(_profile_path(1), JSON.stringify(invalid_envelope))
	var recovered_invalid: Dictionary = store.load_profile(1)
	_expect(recovered_invalid.ok and recovered_invalid.recovered, "structurally invalid active should recover from backup")
	_expect(recovered_invalid.error == SaveStoreScript.ERROR_INVALID, "invalid recovery should expose validation error")
	_expect(recovered_invalid.data.resume.health == 93.0, "invalid recovery should preserve last-good state")


func _test_future_schema_is_preserved() -> void:
	var store = SaveStoreScript.new(_root)
	var future_text := JSON.stringify({"version": 99, "marker": "keep_me", "resume": {}, "checkpoint": {}})
	_write_text(_profile_path(2), future_text)
	var active_write_check: Dictionary = store.can_write_profile(2)
	_expect(not active_write_check.ok and active_write_check.error == SaveStoreScript.ERROR_UNSUPPORTED_VERSION, "write check must reject a future active schema before state mutation")
	var loaded: Dictionary = store.load_profile(2)
	_expect(not loaded.ok and loaded.error == SaveStoreScript.ERROR_UNSUPPORTED_VERSION and loaded.version == 99, "future schema must produce a clear unsupported error")
	var fresh = GameSessionScript.new()
	_expect(store.save_profile(2, fresh.to_dict(), fresh.to_dict()) == ERR_FILE_UNRECOGNIZED, "save must refuse to overwrite a future schema")
	_expect(_read_text(_profile_path(2)) == future_text, "unsupported future save must remain byte-for-byte unchanged")

	var current_text := JSON.stringify({"version": SaveStoreScript.SCHEMA_VERSION, "resume": fresh.to_dict(), "checkpoint": fresh.to_dict()})
	_write_text(_profile_path(2), current_text)
	_write_text(_backup_path(2), future_text)
	var backup_write_check: Dictionary = store.can_write_profile(2)
	_expect(not backup_write_check.ok and backup_write_check.error == SaveStoreScript.ERROR_UNSUPPORTED_VERSION, "write check must reject a future backup schema before state mutation")
	_expect(store.save_profile(2, fresh.to_dict(), fresh.to_dict()) == ERR_FILE_UNRECOGNIZED, "save must also preserve an unsupported backup schema")
	_expect(_read_text(_profile_path(2)) == current_text and _read_text(_backup_path(2)) == future_text, "future backup and current active data must remain unchanged")
	var invalid_write_check: Dictionary = store.can_write_profile(3)
	_expect(not invalid_write_check.ok and invalid_write_check.error == SaveStoreScript.ERROR_INVALID_PROFILE, "write check must reject profile indices outside 0..2")


func _completed_session(position: Vector3, current_health: float):
	var session = GameSessionScript.new()
	session.player_position = position
	session.player_rotation = Vector3(0.1, 0.2, 0.3)
	session.health = current_health
	session.mark_puzzle_solved()
	session.mark_robot_defeated()
	session.collect_artifact()
	session.open_resonant_lock()
	session.collect_crystal()
	return session


func _v1_snapshot(snapshot: Dictionary) -> Dictionary:
	var legacy := snapshot.duplicate(true)
	legacy.erase("movement_mode")
	legacy.erase("ship")
	return legacy


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _profile_path(index: int) -> String:
	return "%s/profile_%d.json" % [_root, index + 1]


func _backup_path(index: int) -> String:
	return _profile_path(index) + ".bak"


func _write_text(path: String, content: String) -> void:
	_write_text_at(_root, path, content)


func _write_text_at(directory: String, path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("test fixture could not write %s" % path)
		return
	file.store_string(content)
	file.flush()


func _read_text(path: String) -> String:
	return _read_text_at(path)


func _read_text_at(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("test fixture could not read %s" % path)
		return ""
	return file.get_as_text()


func _cleanup() -> void:
	_cleanup_directory(_root)


func _cleanup_directory(directory: String) -> void:
	for profile_number in range(1, SaveStoreScript.PROFILE_COUNT + 1):
		var stem := "%s/profile_%d.json" % [directory, profile_number]
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(stem + suffix):
				DirAccess.remove_absolute(stem + suffix)
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)

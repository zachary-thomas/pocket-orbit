class_name SaveSystem
extends RefCounted
## Saves GameState as JSON in the user folder. Writes go to a temporary file
## first and then replace the save, so a crash mid-write can't corrupt it.

const PATH := "user://save.json"


static func save(state: GameState, path: String = PATH) -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: can't write %s" % temp)
		return false
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	return dir.rename(temp.get_file(), path.get_file()) == OK


## The saved state, or null if there's no save (or it can't be read).
static func load_state(path: String = PATH) -> GameState:
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSystem: %s is unreadable; starting fresh" % path)
		return null
	return GameState.from_dict(parsed)


static func delete(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

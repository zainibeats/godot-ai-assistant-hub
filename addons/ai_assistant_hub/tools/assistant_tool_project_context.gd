@tool
class_name AssistantToolProjectContext

const DEFAULT_ALLOWED_EXTENSIONS := {
	"gd": true,
	"tscn": true,
	"tres": true,
	"cs": true,
	"shader": true
}
const ALLOWED_EXACT_FILES := {
	"project.godot": true
}
const IGNORED_DIRECTORIES := {
	".godot": true,
	".git": true,
	".import": true
}
const MAX_FILE_BYTES := 256 * 1024
const MAX_READ_CHARS := 24000
const MAX_SEARCH_MATCHES := 40
const MAX_FILES_LISTED := 250
const MAX_FILES_SCANNED := 1000


func list_project_files(limit:int = MAX_FILES_LISTED) -> Dictionary:
	limit = clampi(limit, 1, MAX_FILES_LISTED)
	var files := _discover_project_files(limit)
	return {
		"tool": "list_project_files",
		"files": files,
		"count": files.size(),
		"truncated": files.size() >= limit
	}


func search_project(query:String, limit:int = MAX_SEARCH_MATCHES) -> Dictionary:
	query = query.strip_edges()
	if query.is_empty():
		return _error("project_search", "Query cannot be empty.")
	limit = clampi(limit, 1, MAX_SEARCH_MATCHES)
	
	var query_lower := query.to_lower()
	var matches := []
	for path in _discover_project_files(MAX_FILES_SCANNED):
		if matches.size() >= limit:
			break
		var text := _read_file_text(path, MAX_READ_CHARS)
		if text.is_empty():
			continue
		var lines := text.split("\n")
		for i in range(lines.size()):
			if lines[i].to_lower().find(query_lower) != -1:
				matches.append({
					"path": path,
					"line": i + 1,
					"preview": lines[i].strip_edges().left(220)
				})
				if matches.size() >= limit:
					break
	return {
		"tool": "project_search",
		"query": query,
		"matches": matches,
		"count": matches.size(),
		"truncated": matches.size() >= limit
	}


func read_project_file(path:String) -> Dictionary:
	path = _normalize_res_path(path)
	if path.is_empty():
		return _error("read_project_file", "Path must be a res:// project file.")
	if not _is_allowed_file(path):
		return _error("read_project_file", "File type is not allowed for project context.")
	if not FileAccess.file_exists(path):
		return _error("read_project_file", "File does not exist: %s" % path)
	var length := _file_length(path)
	if length > MAX_FILE_BYTES:
		return _error("read_project_file", "File is too large for project context: %s bytes" % length)
	var text := _read_file_text(path, MAX_READ_CHARS)
	return {
		"tool": "read_project_file",
		"path": path,
		"content": text,
		"bytes": length,
		"truncated": text.length() >= MAX_READ_CHARS
	}


func write_project_file(path:String, content:String, overwrite:bool = false) -> Dictionary:
	path = _normalize_res_path(path)
	if path.is_empty():
		return _error("write_project_file", "Path must be a res:// project file.")
	if not _is_allowed_file(path):
		return _error("write_project_file", "File type is not allowed for project writes.")
	var content_bytes := content.to_utf8_buffer().size()
	if content_bytes > MAX_FILE_BYTES:
		return _error("write_project_file", "File content is too large: %s bytes" % content_bytes)
	var already_exists := FileAccess.file_exists(path)
	if already_exists and not overwrite:
		return _error("write_project_file", "File already exists. Set overwrite to true to replace it: %s" % path)
	var dir_error := _ensure_directory(path.get_base_dir())
	if dir_error != OK:
		return _error("write_project_file", "Could not create directory %s. Error: %s" % [path.get_base_dir(), dir_error])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _error("write_project_file", "Could not open file for writing: %s. Error: %s" % [path, FileAccess.get_open_error()])
	file.store_string(content)
	file.close()
	return {
		"tool": "write_project_file",
		"path": path,
		"bytes": content_bytes,
		"created": not already_exists,
		"overwritten": already_exists
	}


func replace_in_project_file(path:String, old_text:String, new_text:String, expected_replacements:int = 1) -> Dictionary:
	path = _normalize_res_path(path)
	if path.is_empty():
		return _error("replace_in_project_file", "Path must be a res:// project file.")
	if not _is_allowed_file(path):
		return _error("replace_in_project_file", "File type is not allowed for project writes.")
	if not FileAccess.file_exists(path):
		return _error("replace_in_project_file", "File does not exist: %s" % path)
	if old_text.is_empty():
		return _error("replace_in_project_file", "old_text cannot be empty.")
	var length := _file_length(path)
	if length > MAX_FILE_BYTES:
		return _error("replace_in_project_file", "File is too large for project writes: %s bytes" % length)
	var text := _read_file_text(path, MAX_FILE_BYTES)
	var replacement_count := text.count(old_text)
	if replacement_count == 0:
		return _error("replace_in_project_file", "old_text was not found in %s" % path)
	if expected_replacements > 0 and replacement_count != expected_replacements:
		return _error("replace_in_project_file", "Expected %s replacement(s), but found %s." % [expected_replacements, replacement_count])
	var updated_text := text.replace(old_text, new_text)
	var updated_bytes := updated_text.to_utf8_buffer().size()
	if updated_bytes > MAX_FILE_BYTES:
		return _error("replace_in_project_file", "Updated file content is too large: %s bytes" % updated_bytes)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _error("replace_in_project_file", "Could not open file for writing: %s. Error: %s" % [path, FileAccess.get_open_error()])
	file.store_string(updated_text)
	file.close()
	return {
		"tool": "replace_in_project_file",
		"path": path,
		"replacements": replacement_count,
		"bytes": updated_bytes
	}


func execute_tool_call(tool_name:String, args:Dictionary) -> Dictionary:
	match tool_name:
		"list_project_files":
			return list_project_files(int(args.get("limit", MAX_FILES_LISTED)))
		"project_search":
			return search_project(str(args.get("query", "")), int(args.get("limit", MAX_SEARCH_MATCHES)))
		"read_project_file":
			return read_project_file(str(args.get("path", "")))
		"write_project_file":
			return write_project_file(
				str(args.get("path", "")),
				str(args.get("content", "")),
				bool(args.get("overwrite", false))
			)
		"replace_in_project_file":
			return replace_in_project_file(
				str(args.get("path", "")),
				str(args.get("old_text", "")),
				str(args.get("new_text", "")),
				int(args.get("expected_replacements", 1))
			)
	return _error(tool_name, "Unknown project context tool.")


func _discover_project_files(limit:int = MAX_FILES_LISTED) -> Array[String]:
	var files:Array[String] = []
	_collect_files("res://", files, limit)
	return files


func _collect_files(directory_path:String, files:Array[String], limit:int) -> void:
	if files.size() >= limit:
		return
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var path := "%s/%s" % [directory_path.trim_suffix("/"), file_name]
		if dir.current_is_dir():
			if not IGNORED_DIRECTORIES.has(file_name):
				_collect_files(path, files, limit)
		elif _is_allowed_file(path) and _file_length(path) <= MAX_FILE_BYTES:
			files.append(path)
			if files.size() >= limit:
				break
		file_name = dir.get_next()
	dir.list_dir_end()


func _is_allowed_file(path:String) -> bool:
	var file_name := path.get_file()
	if ALLOWED_EXACT_FILES.has(file_name):
		return true
	if file_name.ends_with(".import"):
		return false
	var extension := path.get_extension().to_lower()
	return DEFAULT_ALLOWED_EXTENSIONS.has(extension)


func _normalize_res_path(path:String) -> String:
	path = path.strip_edges()
	if path.is_empty():
		return ""
	if path.begins_with("res://"):
		path = path.simplify_path()
	else:
		path = ("res://%s" % path.trim_prefix("/")).simplify_path()
	if not path.begins_with("res://") or path.contains(".."):
		return ""
	return path


func _read_file_text(path:String, max_chars:int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text.left(max_chars)


func _file_length(path:String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


func _ensure_directory(path:String) -> Error:
	if DirAccess.dir_exists_absolute(path):
		return OK
	return DirAccess.make_dir_recursive_absolute(path)


func _error(tool_name:String, message:String) -> Dictionary:
	return {
		"tool": tool_name,
		"error": message
	}

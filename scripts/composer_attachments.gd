extends RefCounted

# Composer file/image attachments / Adjuntos de archivos e imágenes del compositor

const MAX_TEXT_CHARS := 8000
const MAX_IMAGE_BYTES := 2_000_000
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
const TEXT_EXTENSIONS: PackedStringArray = [
	"gd", "cs", "tscn", "md", "txt", "json", "cfg", "tres", "import", "shader", "glsl",
	"xml", "yaml", "yml", "csv", "ini", "toml", "env", "html", "css",
]

static func is_image_path(path: String) -> bool:
	return _extension(path) in IMAGE_EXTENSIONS

static func is_text_file_path(path: String) -> bool:
	var ext: String = _extension(path)
	if ext.is_empty():
		return false
	if ext in IMAGE_EXTENSIONS:
		return false
	return ext in TEXT_EXTENSIONS or ext == "tscn"

static func create_attachment_from_path(path: String) -> Dictionary:
	var normalized: String = _normalize_path(path)
	if normalized.is_empty() or not FileAccess.file_exists(normalized):
		return {"ok": false, "error": "File not found: %s" % path}
	if is_image_path(normalized):
		return _load_image_attachment(normalized)
	return _load_text_attachment(normalized)

static func build_file_context_block(attachments: Array) -> String:
	var sections: PackedStringArray = []
	for item in attachments:
		if not item is Dictionary:
			continue
		if String(item.get("kind", "")) != "file":
			continue
		var name: String = String(item.get("name", "file"))
		var text: String = String(item.get("text", ""))
		if text.is_empty():
			continue
		sections.append("### %s\n```\n%s\n```" % [name, text])
	if sections.is_empty():
		return ""
	return "## Attached files\n%s" % "\n\n".join(sections)

static func get_image_attachments(attachments: Array) -> Array:
	var images: Array = []
	for item in attachments:
		if item is Dictionary and String(item.get("kind", "")) == "image":
			images.append(item)
	return images

static func _load_image_attachment(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot read image: %s" % path}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.size() > MAX_IMAGE_BYTES:
		return {"ok": false, "error": "Image too large (max %d MB): %s" % [MAX_IMAGE_BYTES / 1_000_000, path.get_file()]}
	var mime: String = _mime_for_path(path)
	return {
		"ok": true,
		"kind": "image",
		"path": path,
		"name": path.get_file(),
		"mime": mime,
		"base64": Marshalls.raw_to_base64(bytes),
	}

static func _load_text_attachment(path: String) -> Dictionary:
	var ext: String = _extension(path)
	if ext == "tscn":
		return {
			"ok": true,
			"kind": "file",
			"path": path,
			"name": path.get_file(),
			"text": "[Scene file %s — open in editor for full content; path: %s]" % [path.get_file(), path],
		}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot read file: %s" % path}
	var text: String = file.get_as_text()
	file.close()
	if text.length() > MAX_TEXT_CHARS:
		text = text.substr(0, MAX_TEXT_CHARS) + "\n… [truncated]"
	return {
		"ok": true,
		"kind": "file",
		"path": path,
		"name": path.get_file(),
		"text": text,
	}

static func _normalize_path(path: String) -> String:
	var value: String = path.strip_edges()
	if value.begins_with("res://") or value.begins_with("user://"):
		return value
	if value.begins_with("/"):
		return value
	return ProjectSettings.globalize_path(value)

static func _extension(path: String) -> String:
	return path.get_extension().to_lower()

static func _mime_for_path(path: String) -> String:
	match _extension(path):
		"png":
			return "image/png"
		"jpg", "jpeg":
			return "image/jpeg"
		"webp":
			return "image/webp"
		"gif":
			return "image/gif"
		"bmp":
			return "image/bmp"
		_:
			return "application/octet-stream"

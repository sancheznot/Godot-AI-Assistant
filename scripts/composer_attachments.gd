extends RefCounted

# Composer file/image attachments / Adjuntos de archivos e imágenes del compositor

const MAX_TEXT_CHARS := 8000
const MAX_IMAGE_BYTES := 2_000_000
const PASTE_CACHE_DIR := "user://ai_assistant_plugin/paste_cache/"
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

static func create_attachment_from_clipboard_image(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {"ok": false, "error": "Clipboard image is empty"}
	var png_bytes: PackedByteArray = image.save_png_to_buffer()
	if png_bytes.is_empty():
		return {"ok": false, "error": "Could not encode clipboard image"}
	if png_bytes.size() > MAX_IMAGE_BYTES:
		return {
			"ok": false,
			"error": "Image too large (max %d MB)" % [MAX_IMAGE_BYTES / 1_000_000],
		}
	_ensure_paste_cache_dir()
	var filename: String = "paste_%d.png" % Time.get_ticks_msec()
	var saved_path: String = PASTE_CACHE_DIR + filename
	var out := FileAccess.open(saved_path, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "Could not save pasted image"}
	out.store_buffer(png_bytes)
	out.close()
	return {
		"ok": true,
		"kind": "image",
		"path": saved_path,
		"name": filename,
		"mime": "image/png",
		"base64": Marshalls.raw_to_base64(png_bytes),
	}

static func create_preview_texture(item: Dictionary) -> Texture2D:
	if not item is Dictionary or String(item.get("kind", "")) != "image":
		return null
	var b64: String = String(item.get("base64", ""))
	if b64.is_empty():
		return null
	var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK and img.load_jpg_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)

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

static func _ensure_paste_cache_dir() -> void:
	if not DirAccess.dir_exists_absolute(PASTE_CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(PASTE_CACHE_DIR)

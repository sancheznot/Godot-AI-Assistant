extends RefCounted

# Persists chat sessions to disk / Persiste sesiones de chat en disco

const HISTORY_PATH := "user://ai_assistant_plugin/chat_history.json"
const MAX_SESSIONS := 40
const MAX_MESSAGES := 150

var sessions: Array = []
var active_session_id: String = ""

func load_history() -> void:
	sessions = []
	active_session_id = ""
	if not FileAccess.file_exists(HISTORY_PATH):
		create_session("Nuevo chat")
		return
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file == null:
		create_session("Nuevo chat")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		sessions = parsed.get("sessions", [])
		active_session_id = String(parsed.get("active_session_id", ""))
		for session in sessions:
			if session is Dictionary:
				_normalize_session(session)
	if sessions.is_empty():
		create_session("Nuevo chat")
	elif active_session_id.is_empty() or _find_session(active_session_id).is_empty():
		active_session_id = String(sessions[0].get("id", ""))

func save_history() -> void:
	_ensure_dir()
	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("AI Assistant: could not save chat history")
		return
	file.store_string(JSON.stringify({
		"active_session_id": active_session_id,
		"sessions": sessions
	}, "\t"))
	file.close()

func create_session(title: String = "Nuevo chat") -> String:
	var session_id: String = "%d_%d" % [Time.get_unix_time_from_system(), randi()]
	var session := {
		"id": session_id,
		"title": title,
		"updated_at": Time.get_unix_time_from_system(),
		"pinned": false,
		"archived": false,
		"messages": []
	}
	sessions.insert(0, session)
	active_session_id = session_id
	_trim_sessions()
	save_history()
	return session_id

func replace_active_session(title: String = "Nuevo chat") -> void:
	var session: Dictionary = _find_session(active_session_id)
	if session.is_empty():
		create_session(title)
		return
	session["messages"] = []
	session["title"] = title
	session["updated_at"] = Time.get_unix_time_from_system()
	session["archived"] = false
	save_history()

func get_active_session_title() -> String:
	return get_session_title(active_session_id)

func get_session_title(session_id: String) -> String:
	var session: Dictionary = _find_session(session_id)
	if session.is_empty():
		return "Chat"
	return String(session.get("title", "Chat"))

func set_session_title(session_id: String, title: String) -> bool:
	var session: Dictionary = _find_session(session_id)
	if session.is_empty():
		return false
	session["title"] = title.strip_edges()
	session["updated_at"] = Time.get_unix_time_from_system()
	save_history()
	return true

func pin_session(session_id: String, pinned: bool) -> bool:
	var session: Dictionary = _find_session(session_id)
	if session.is_empty():
		return false
	session["pinned"] = pinned
	save_history()
	return true

func archive_session(session_id: String, archived: bool) -> bool:
	var session: Dictionary = _find_session(session_id)
	if session.is_empty():
		return false
	session["archived"] = archived
	if archived and session_id == active_session_id and not sessions.is_empty():
		for other in sessions:
			if other is Dictionary and not bool(other.get("archived", false)):
				active_session_id = String(other.get("id", ""))
				break
	save_history()
	return true

func delete_session(session_id: String) -> bool:
	return delete_sessions([session_id]) > 0

func delete_sessions(session_ids: Array) -> int:
	var id_set: Dictionary = {}
	for raw_id in session_ids:
		var session_id: String = String(raw_id).strip_edges()
		if not session_id.is_empty():
			id_set[session_id] = true
	if id_set.is_empty():
		return 0
	var removed: int = 0
	var kept: Array = []
	for session in sessions:
		if session is Dictionary:
			var session_id: String = String(session.get("id", ""))
			if id_set.has(session_id):
				removed += 1
			else:
				kept.append(session)
	if removed == 0:
		return 0
	sessions = kept
	if id_set.has(active_session_id) or _find_session(active_session_id).is_empty():
		if sessions.is_empty():
			create_session("Nuevo chat")
		else:
			active_session_id = String(sessions[0].get("id", ""))
	save_history()
	return removed

func archive_sessions(session_ids: Array, archived: bool) -> int:
	var changed: int = 0
	for raw_id in session_ids:
		if archive_session(String(raw_id), archived):
			changed += 1
	return changed

func get_session(session_id: String) -> Dictionary:
	return _find_session(session_id)

func set_active_session(session_id: String) -> bool:
	if _find_session(session_id).is_empty():
		return false
	active_session_id = session_id
	save_history()
	return true

func get_active_messages() -> Array:
	var session: Dictionary = _find_session(active_session_id)
	return session.get("messages", []).duplicate(true)

func add_message(role: String, content: String, is_error: bool = false, attachments: Array = [], retry_payload: Dictionary = {}) -> void:
	var session: Dictionary = _find_session(active_session_id)
	if session.is_empty():
		create_session(_title_from_message(content))
		session = _find_session(active_session_id)
	var messages: Array = session.get("messages", [])
	var entry: Dictionary = {
		"role": role,
		"content": content,
		"is_error": is_error,
		"timestamp": Time.get_unix_time_from_system(),
	}
	if is_error and retry_payload is Dictionary and not retry_payload.is_empty():
		entry["retry_payload"] = retry_payload.duplicate(true)
	if not attachments.is_empty():
		var meta: Array = []
		for item in attachments:
			if item is Dictionary:
				meta.append({
					"kind": String(item.get("kind", "")),
					"name": String(item.get("name", "")),
					"path": String(item.get("path", "")),
				})
		entry["attachments"] = meta
	messages.append(entry)
	if messages.size() > MAX_MESSAGES:
		messages = messages.slice(messages.size() - MAX_MESSAGES)
	session["messages"] = messages
	session["updated_at"] = Time.get_unix_time_from_system()
	if role == "user" and _count_user_messages(messages) <= 1:
		var current_title: String = String(session.get("title", ""))
		if current_title in ["Nuevo chat", "New chat", ""]:
			session["title"] = _title_from_message(content)
	save_history()

func remove_last_message() -> Dictionary:
	var session: Dictionary = _find_session(active_session_id)
	if session.is_empty():
		return {}
	var messages: Array = session.get("messages", [])
	if messages.is_empty():
		return {}
	var removed: Variant = messages.pop_back()
	session["messages"] = messages
	session["updated_at"] = Time.get_unix_time_from_system()
	save_history()
	if removed is Dictionary:
		return removed as Dictionary
	return {}

func _count_user_messages(messages: Array) -> int:
	var count: int = 0
	for message in messages:
		if message is Dictionary and String(message.get("role", "")) == "user":
			count += 1
	return count

func get_session_summaries(filter: String = "", include_archived: bool = false) -> Array:
	var normalized: String = filter.to_lower().strip_edges()
	var result: Array = []
	for session in sessions:
		if session is Dictionary:
			var archived: bool = bool(session.get("archived", false))
			if archived and not include_archived:
				continue
			var title: String = String(session.get("title", "Chat"))
			if not normalized.is_empty() and normalized not in title.to_lower():
				continue
			result.append({
				"id": String(session.get("id", "")),
				"title": title,
				"updated_at": int(session.get("updated_at", 0)),
				"message_count": int(session.get("messages", []).size()),
				"pinned": bool(session.get("pinned", false)),
				"archived": archived
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pinned_a: bool = bool(a.get("pinned", false))
		var pinned_b: bool = bool(b.get("pinned", false))
		if pinned_a != pinned_b:
			return pinned_a
		return int(a.get("updated_at", 0)) > int(b.get("updated_at", 0))
	)
	return result

func get_archived_summaries(filter: String = "") -> Array:
	var normalized: String = filter.to_lower().strip_edges()
	var result: Array = []
	for session in sessions:
		if session is Dictionary and bool(session.get("archived", false)):
			var title: String = String(session.get("title", "Chat"))
			if not normalized.is_empty() and normalized not in title.to_lower():
				continue
			result.append({
				"id": String(session.get("id", "")),
				"title": title,
				"updated_at": int(session.get("updated_at", 0)),
				"message_count": int(session.get("messages", []).size()),
				"pinned": bool(session.get("pinned", false)),
				"archived": true
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("updated_at", 0)) > int(b.get("updated_at", 0))
	)
	return result

func clear_active_session() -> void:
	var session: Dictionary = _find_session(active_session_id)
	if session.is_empty():
		return
	session["messages"] = []
	session["updated_at"] = Time.get_unix_time_from_system()
	save_history()

func clear_session_messages(session_id: String) -> bool:
	var session: Dictionary = _find_session(session_id)
	if session.is_empty():
		return false
	session["messages"] = []
	session["updated_at"] = Time.get_unix_time_from_system()
	save_history()
	return true

func _normalize_session(session: Dictionary) -> void:
	if not session.has("pinned"):
		session["pinned"] = false
	if not session.has("archived"):
		session["archived"] = false

func _find_session(session_id: String) -> Dictionary:
	for session in sessions:
		if session is Dictionary and String(session.get("id", "")) == session_id:
			return session
	return {}

func _title_from_message(text: String) -> String:
	var clean: String = text.strip_edges().replace("\n", " ")
	if clean.begins_with("/"):
		return clean.substr(0, mini(32, clean.length()))
	if clean.length() > 42:
		return clean.substr(0, 39) + "..."
	return clean if not clean.is_empty() else "Nuevo chat"

func _trim_sessions() -> void:
	if sessions.size() <= MAX_SESSIONS:
		return
	sessions = sessions.slice(0, MAX_SESSIONS)
	if _find_session(active_session_id).is_empty() and not sessions.is_empty():
		active_session_id = String(sessions[0].get("id", ""))

func _ensure_dir() -> void:
	var dir_path: String = HISTORY_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

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
		"messages": []
	}
	sessions.insert(0, session)
	active_session_id = session_id
	_trim_sessions()
	save_history()
	return session_id

func set_active_session(session_id: String) -> bool:
	if _find_session(session_id).is_empty():
		return false
	active_session_id = session_id
	save_history()
	return true

func get_active_messages() -> Array:
	var session: Dictionary = _find_session(active_session_id)
	return session.get("messages", []).duplicate(true)

func add_message(role: String, content: String, is_error: bool = false) -> void:
	var session: Dictionary = _find_session(active_session_id)
	if session.is_empty():
		create_session(_title_from_message(content))
		session = _find_session(active_session_id)
	var messages: Array = session.get("messages", [])
	messages.append({
		"role": role,
		"content": content,
		"is_error": is_error,
		"timestamp": Time.get_unix_time_from_system()
	})
	if messages.size() > MAX_MESSAGES:
		messages = messages.slice(messages.size() - MAX_MESSAGES)
	session["messages"] = messages
	session["updated_at"] = Time.get_unix_time_from_system()
	if role == "user" and (messages.size() <= 2 or String(session.get("title", "")) == "Nuevo chat"):
		session["title"] = _title_from_message(content)
	save_history()

func get_session_summaries() -> Array:
	var result: Array = []
	for session in sessions:
		if session is Dictionary:
			result.append({
				"id": String(session.get("id", "")),
				"title": String(session.get("title", "Chat")),
				"updated_at": int(session.get("updated_at", 0)),
				"message_count": int(session.get("messages", []).size())
			})
	return result

func clear_active_session() -> void:
	var session: Dictionary = _find_session(active_session_id)
	if session.is_empty():
		return
	session["messages"] = []
	session["updated_at"] = Time.get_unix_time_from_system()
	save_history()

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

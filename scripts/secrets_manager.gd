extends RefCounted

# Encrypted API key storage + env overrides / Almacén cifrado de API keys + variables de entorno

const SECRETS_DIR := "user://ai_assistant_plugin"
const SECRETS_FILE := "user://ai_assistant_plugin/secrets.enc"
const PASSPHRASE_SALT := "golem_ai_secrets_v1"

var _secrets: Dictionary = {}

func load_secrets() -> void:
	_ensure_dir()
	_secrets = {}
	if not FileAccess.file_exists(SECRETS_FILE):
		return
	var passphrase: String = _get_passphrase()
	var file := FileAccess.open_encrypted_with_pass(SECRETS_FILE, FileAccess.READ, passphrase)
	if file == null:
		push_warning("AI Assistant: could not decrypt secrets file (wrong GOLEM_AI_SECRETS_PASSPHRASE?)")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_secrets = parsed

func save_secrets() -> bool:
	_ensure_dir()
	var passphrase: String = _get_passphrase()
	var file := FileAccess.open_encrypted_with_pass(SECRETS_FILE, FileAccess.WRITE, passphrase)
	if file == null:
		push_error("AI Assistant: could not write encrypted secrets")
		return false
	file.store_string(JSON.stringify(_secrets, "\t"))
	file.close()
	return true

func get_api_key(provider_id: String) -> String:
	var env_value: String = _read_env_api_key(provider_id)
	if not env_value.is_empty():
		return env_value
	return String(_secrets.get(provider_id, "")).strip_edges()

func set_api_key(provider_id: String, api_key: String) -> void:
	var normalized: String = api_key.strip_edges()
	if normalized.is_empty():
		_secrets.erase(provider_id)
	else:
		_secrets[provider_id] = normalized
	save_secrets()

func clear_api_key(provider_id: String) -> void:
	_secrets.erase(provider_id)
	save_secrets()

func is_api_key_from_env(provider_id: String) -> bool:
	return not _read_env_api_key(provider_id).is_empty()

func get_env_var_name(provider_id: String) -> String:
	return "GOLEM_AI_API_KEY_%s" % provider_id.to_upper()

func get_secrets_file_path() -> String:
	return SECRETS_FILE

func import_plaintext_keys(source: Dictionary) -> bool:
	var changed: bool = false
	for provider_id in source.keys():
		var value: String = String(source.get(provider_id, "")).strip_edges()
		if value.is_empty():
			continue
		_secrets[String(provider_id)] = value
		changed = true
	if changed:
		return save_secrets()
	return false

func _read_env_api_key(provider_id: String) -> String:
	return String(OS.get_environment(get_env_var_name(provider_id))).strip_edges()

func _get_passphrase() -> String:
	var custom: String = String(OS.get_environment("GOLEM_AI_SECRETS_PASSPHRASE")).strip_edges()
	if not custom.is_empty():
		return custom
	return "%s:%s" % [PASSPHRASE_SALT, OS.get_unique_id()]

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SECRETS_DIR):
		DirAccess.make_dir_recursive_absolute(SECRETS_DIR)

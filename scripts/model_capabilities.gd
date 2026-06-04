extends RefCounted

# Model capability heuristics (vision / thinking) / Heurísticas de capacidades del modelo

const VISION_POSITIVE: PackedStringArray = [
	"vision", "vl", "llava", "moondream", "pixtral", "internvl", "minicpmv",
	"gemma3", "gemma4", "gpt4o", "gpt4turbo", "gpt4vision", "chatgpt4o",
	"claude3", "claudesonnet", "claudeopus", "claudehaiku3",
	"gemini", "kimik2", "kimiv", "qwen2vl", "qwenvl", "qwen3vl",
	"qwen35", "qwen36", "qwen37",
	"glm4v", "deepseekvl", "janus", "bakllava", "llama32vision",
	"minimaxvl",
]

const VISION_NEGATIVE: PackedStringArray = [
	"deepseekchat", "deepseekcoder", "deepseekr1", "qwen25coder", "qwen2coder", "qwen3coder",
	"codellama", "codegemma", "codestral", "starcoder", "wizardcoder", "phind", "embed", "whisper", "tts",
	"moonshotv18k", "moonshotv132k", "moonshotv1128k",
]

const THINKING_POSITIVE: PackedStringArray = [
	"gemma4", "gemma3", "qwen3", "qwen35", "qwen36", "qwen37", "qwq", "deepseekr1", "deepseekreasoner", "gptoss",
	"magistral", "kimik2thinking", "minimaxm2", "o1", "o3", "o4", "composer",
]

const THINKING_NEGATIVE: PackedStringArray = [
	"qwen25coder", "qwen2coder", "qwen3coder", "codellama", "codestral", "embed",
]

static func supports_vision(provider_id: String, model_id: String) -> bool:
	var keys: Dictionary = _model_match_keys(model_id)
	if keys.is_empty():
		return false
	if _matches_any(keys, VISION_NEGATIVE):
		return false
	if _matches_any(keys, VISION_POSITIVE):
		return true
	match provider_id:
		"gemini":
			return true
		"anthropic":
			return _contains_any(keys, ["claude3", "claudesonnet", "claudeopus"])
		"openai":
			return keys["compact"].begins_with("gpt4o") or _contains_any(keys, ["vision"])
		"kimi":
			return _contains_any(keys, ["kimik2", "vision"])
		"minimax":
			return _contains_any(keys, ["vl", "minimaxvl"])
		"cursor":
			return _cursor_supports_vision(keys)
		"openrouter", "lmstudio":
			return false
		_:
			return false

static func supports_thinking(provider_id: String, model_id: String) -> bool:
	var keys: Dictionary = _model_match_keys(model_id)
	if keys.is_empty():
		return false
	if _matches_any(keys, THINKING_NEGATIVE):
		return false
	if _matches_any(keys, THINKING_POSITIVE):
		return true
	if provider_id == "ollama":
		return _ollama_thinking_heuristic(keys)
	if provider_id == "anthropic" and _contains_any(keys, ["extendedthinking"]):
		return true
	if provider_id == "cursor":
		return _cursor_supports_thinking(keys)
	return false

static func _model_match_keys(model_id: String) -> Dictionary:
	var raw: String = model_id.strip_edges().to_lower()
	if raw.is_empty():
		return {}
	return {
		"raw": raw,
		"compact": _compact_model_key(raw),
	}

static func _compact_model_key(model_lower: String) -> String:
	return model_lower.replace("/", "").replace("-", "").replace("_", "").replace(".", "").replace(":", "")

static func _contains_any(keys: Dictionary, tokens: PackedStringArray) -> bool:
	for token in tokens:
		if String(token).is_empty():
			continue
		if keys["raw"].contains(token) or keys["compact"].contains(token):
			return true
	return false

static func _matches_any(keys: Dictionary, tokens: PackedStringArray) -> bool:
	for token in tokens:
		var needle: String = _compact_model_key(String(token).to_lower())
		if needle.is_empty():
			continue
		if keys["raw"].contains(String(token).to_lower()) or keys["compact"].contains(needle):
			return true
	return false

static func _cursor_supports_vision(keys: Dictionary) -> bool:
	# Cursor Composer agents accept image attachments via the proxy/API.
	# Los agentes Composer de Cursor aceptan imágenes vía proxy/API.
	return _contains_any(keys, ["composer", "gpt4o", "claude3", "gemini"])

static func _cursor_supports_thinking(keys: Dictionary) -> bool:
	return _contains_any(keys, ["composer", "o1", "o3", "o4", "deepseekr1"])

static func _ollama_thinking_heuristic(keys: Dictionary) -> bool:
	var prefixes: PackedStringArray = ["gemma4", "gemma3", "qwen3", "qwen35", "qwen36", "qwq", "deepseek", "gptoss", "magistral"]
	return _contains_any(keys, prefixes)

static func get_capability_summary(provider_id: String, model_id: String, catalog_caps: Dictionary = {}) -> Dictionary:
	var vision: bool
	var thinking: bool
	if catalog_caps.has("vision"):
		vision = bool(catalog_caps.get("vision"))
	else:
		vision = supports_vision(provider_id, model_id)
	if catalog_caps.has("thinking"):
		thinking = bool(catalog_caps.get("thinking"))
	else:
		thinking = supports_thinking(provider_id, model_id)
	return {
		"vision": vision,
		"thinking": thinking,
	}

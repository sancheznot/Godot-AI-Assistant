extends RefCounted

# Model capability heuristics (vision / thinking) / Heurísticas de capacidades del modelo

const VISION_POSITIVE: PackedStringArray = [
	"vision", "vl", "llava", "moondream", "pixtral", "internvl", "minicpmv",
	"gemma3", "gemma4", "gpt4o", "gpt4turbo", "gpt4vision", "chatgpt4o",
	"claude3", "claudesonnet", "claudeopus", "claudehaiku3",
	"gemini", "kimik2", "kimiv", "qwen2vl", "qwenvl", "qwen3vl",
	"qwen35", "qwen36", "qwen37",
	"glm4v", "deepseekvl", "janus", "bakllava", "llama32vision",
]

const VISION_NEGATIVE: PackedStringArray = [
	"deepseekchat", "deepseekcoder", "deepseekr1", "qwen25coder", "qwen2coder", "qwen3coder",
	"codellama", "codegemma", "codestral", "starcoder", "wizardcoder", "phind", "embed", "whisper", "tts",
	"moonshotv18k", "moonshotv132k", "moonshotv1128k",
]

const THINKING_POSITIVE: PackedStringArray = [
	"gemma4", "gemma3", "qwen3", "qwen35", "qwen36", "qwen37", "qwq", "deepseekr1", "deepseekreasoner", "gptoss",
	"magistral", "kimik2thinking", "o1", "o3", "o4", "composer",
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
			return _minimax_supports_vision(model_id)
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
	if provider_id == "minimax":
		return _minimax_supports_thinking(model_id)
	return false

# MiniMax official matrix (platform.minimax.io/docs, Anthropic-compatible API):
# - Vision (image/video): MiniMax-M3 ONLY
# - Thinking: M3 (toggleable), M2.7/M2.5/M2.1/M2 (always on at API level)
# - M2-her: dialogue model, text only, no multimodal
static func _minimax_supports_vision(model_id: String) -> bool:
	return _minimax_model_tier(model_id) == "m3"

static func _minimax_supports_thinking(model_id: String) -> bool:
	var tier: String = _minimax_model_tier(model_id)
	if tier.is_empty() or tier == "m2her":
		return false
	return tier in ["m3", "m27", "m25", "m21", "m2"]

static func _minimax_model_tier(model_id: String) -> String:
	var keys: Dictionary = _model_match_keys(model_id)
	if keys.is_empty():
		return ""
	var compact: String = keys["compact"]
	if compact == "minimaxm3" or compact.ends_with("minimaxm3"):
		return "m3"
	if compact.contains("m2her") or compact == "m2her":
		return "m2her"
	if compact.contains("minimaxm27") or compact.contains("m27highspeed"):
		return "m27"
	if compact.contains("minimaxm25") or compact.contains("m25highspeed"):
		return "m25"
	if compact.contains("minimaxm21") or compact.contains("m21highspeed"):
		return "m21"
	if compact.contains("minimaxm2") and not compact.contains("minimaxm21") and not compact.contains("minimaxm25") and not compact.contains("minimaxm27"):
		return "m2"
	if keys["raw"].begins_with("minimax-m3"):
		return "m3"
	if keys["raw"].begins_with("minimax-m2.7") or keys["raw"].begins_with("minimax-m2-7"):
		return "m27"
	if keys["raw"].begins_with("minimax-m2.5") or keys["raw"].begins_with("minimax-m2-5"):
		return "m25"
	if keys["raw"].begins_with("minimax-m2.1") or keys["raw"].begins_with("minimax-m2-1"):
		return "m21"
	if keys["raw"].begins_with("minimax-m2"):
		return "m2"
	return ""

static func get_minimax_capability_table() -> Array:
	# Reference table for docs / UI hints / Referencia para documentación
	return [
		{"model": "MiniMax-M3", "vision": true, "thinking": true, "thinking_notes": "toggleable (disabled/adaptive)"},
		{"model": "MiniMax-M2.7", "vision": false, "thinking": true, "thinking_notes": "always on (API)"},
		{"model": "MiniMax-M2.7-highspeed", "vision": false, "thinking": true, "thinking_notes": "always on (API)"},
		{"model": "MiniMax-M2.5", "vision": false, "thinking": true, "thinking_notes": "always on (API)"},
		{"model": "MiniMax-M2.5-highspeed", "vision": false, "thinking": true, "thinking_notes": "always on (API)"},
		{"model": "MiniMax-M2.1", "vision": false, "thinking": true, "thinking_notes": "always on (API)"},
		{"model": "MiniMax-M2.1-highspeed", "vision": false, "thinking": true, "thinking_notes": "always on (API)"},
		{"model": "MiniMax-M2", "vision": false, "thinking": true, "thinking_notes": "always on (API)"},
		{"model": "M2-her", "vision": false, "thinking": false, "thinking_notes": "dialogue / roleplay"},
	]

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

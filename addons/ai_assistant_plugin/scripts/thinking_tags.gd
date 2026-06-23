extends RefCounted

# Provider thinking tag parsing / Parseo de tags de reasoning de distintos proveedores

const TAG_NAMES: PackedStringArray = [
	"thinking",
	"think",
	"thought",
	"redacted_thinking",
	"redacted_reasoning",
]

static func extract_all_thinking(raw_text: String) -> Dictionary:
	var thinking_parts: PackedStringArray = []
	var content: String = raw_text
	for tag_name in TAG_NAMES:
		while true:
			var block: String = _extract_tag_block(content, tag_name)
			if block.is_empty():
				break
			thinking_parts.append(block.strip_edges())
			content = _remove_tag_block(content, tag_name)
	content = _strip_inline_think_prefix(content)
	return {
		"thinking": "\n\n".join(thinking_parts).strip_edges(),
		"content": content.strip_edges(),
	}

static func replace_xml_thinking_tags(text: String) -> String:
	var result: String = text
	for tag_name in TAG_NAMES:
		var regex := RegEx.new()
		regex.compile("(?i)(?s)<%s>(.*?)</%s>" % [tag_name, tag_name])
		while true:
			var match_result := regex.search(result)
			if match_result == null:
				break
			var inner: String = match_result.get_string(1).strip_edges()
			var block: String = "[Thinking]\n%s\n[/Thinking]" % inner
			result = result.substr(0, match_result.get_start()) + block + result.substr(match_result.get_end())
	return result

static func strip_all_thinking(text: String) -> String:
	return String(extract_all_thinking(text).get("content", text))

static func _extract_tag_block(text: String, tag_name: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?i)(?s)<%s>(.*?)</%s>" % [tag_name, tag_name])
	var match_result := regex.search(text)
	if match_result:
		return match_result.get_string(1)
	return ""

static func _remove_tag_block(text: String, tag_name: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?i)(?s)<%s>.*?</%s>" % [tag_name, tag_name])
	return regex.sub(text, "", true)

static func _strip_inline_think_prefix(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?i)(?m)^\\s*\\(think\\)\\s*\\n?")
	return regex.sub(text, "", true)

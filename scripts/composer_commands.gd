extends RefCounted

# Parses /slash commands in composer / Parsea comandos / en el composer

func try_parse(prompt: String) -> Dictionary:
	var trimmed: String = prompt.strip_edges()
	if not trimmed.begins_with("/"):
		return {"handled": false}
	var parts: PackedStringArray = trimmed.split(" ", false)
	var command: String = parts[0].substr(1).to_lower()
	var args: PackedStringArray = parts.slice(1) if parts.size() > 1 else PackedStringArray()
	return {
		"handled": true,
		"command": command,
		"args": args,
		"raw": trimmed
	}

func get_help_text() -> String:
	return """Comandos disponibles:
/clear — limpia el chat actual
/new — nuevo chat
/history — lista chats guardados
/skill [id] — cambia skill activo (sin id = lista)
/skills — abre carpeta de skills en el proyecto
/context basic|intermediate|full — profundidad de contexto
/models — refresca lista de modelos
/help — esta ayuda

Menciones @:
@scene @selection @res://ruta/archivo.tscn @skill:nombre"""

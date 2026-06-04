extends RefCounted

# Persistent project index (lexical + SceneBuilder + scene summaries) / Índice persistente del proyecto

signal sync_started()
signal sync_progress(ratio: float, message: String)
signal sync_finished(success: bool, summary: Dictionary)
signal index_deleted()

const INDEX_VERSION := 1
const EMBEDDINGS_VERSION := 1
const INDEX_ROOT := "user://ai_assistant_plugin/index/"
const SCENEBUILDER_ROOTS: PackedStringArray = [
	"res://Data/SceneBuilder",
	"res://data/SceneBuilder",
]
const INDEX_EXTENSIONS: PackedStringArray = [
	".gd", ".tscn", ".cs", ".md", ".json", ".cfg", ".tres",
]
const DEFAULT_IGNORE_DIRS: PackedStringArray = [
	".git", ".import", ".godot", "node_modules",
]
const MAX_SCENE_NODES := 48
const MAX_SYMBOLS_PER_FILE := 24
const DEFAULT_SEMANTIC_MAX_CHUNKS := 400
const DEFAULT_SEMANTIC_CHUNK_SIZE := 1200
const MAX_FILE_CHARS_FOR_EMBED := 12000

const ProjectDocsService := preload("res://addons/ai_assistant_plugin/scripts/project_docs_service.gd")

var _editor_plugin: EditorPlugin = null
var _config_manager: RefCounted = null
var _embedding_client: RefCounted = null
var _index: Dictionary = {}
var _embeddings: Dictionary = {}
var _ignore_patterns: PackedStringArray = []
var _syncing: bool = false
var _ready: bool = false
var _semantic_ready: bool = false
var _pending_preserved_chunks: Array = []
var _pending_embed_queue: Array = []

func setup(editor_plugin: EditorPlugin, config_mgr: RefCounted = null) -> void:
	_editor_plugin = editor_plugin
	_config_manager = config_mgr
	_load_ignore_rules()
	_embedding_client = preload("res://addons/ai_assistant_plugin/scripts/local_embedding_client.gd").new()
	_embedding_client.setup(editor_plugin, config_mgr)
	if not _embedding_client.batch_finished.is_connected(_on_embedding_batch_finished):
		_embedding_client.batch_finished.connect(_on_embedding_batch_finished)
	if not _embedding_client.batch_progress.is_connected(_on_embedding_batch_progress):
		_embedding_client.batch_progress.connect(_on_embedding_batch_progress)
	if _load_index_from_disk():
		_ready = true
	if _load_embeddings_from_disk():
		_semantic_ready = _embeddings_has_vectors()

func is_ready() -> bool:
	return _ready and not _index.is_empty()

func is_semantic_ready() -> bool:
	return _semantic_ready and _embeddings_has_vectors()

func is_syncing() -> bool:
	return _syncing

func get_status() -> Dictionary:
	return {
		"ready": is_ready(),
		"semantic_ready": is_semantic_ready(),
		"syncing": _syncing,
		"version": int(_index.get("version", 0)),
		"indexed_files": int(_index.get("file_count", 0)),
		"scenebuilder_items": int(_index.get("scenebuilder_count", 0)),
		"scene_summaries": int(_index.get("scene_count", 0)),
		"symbols": int(_index.get("symbol_count", 0)),
		"docs": int(_index.get("doc_count", 0)),
		"embedding_chunks": _embedding_chunk_count(),
		"embedding_model": String(_embeddings.get("model", "")),
		"progress": 1.0 if is_ready() and not _syncing else 0.0,
		"last_sync_unix": int(_index.get("synced_at", 0)),
		"embeddings_sync_unix": int(_embeddings.get("synced_at", 0)),
		"index_path": _index_file_path(),
		"embeddings_path": _embeddings_file_path(),
	}

func start_auto_sync() -> void:
	if _config_manager != null and not bool(_config_manager.get_setting("index_on_startup", true)):
		return
	if not bool(_config_manager.get_setting("enable_project_index", true)):
		return
	if is_ready() and not _index_is_stale():
		return
	call_deferred("sync_index")

func sync_index() -> void:
	if _syncing:
		return
	if _config_manager != null and not bool(_config_manager.get_setting("enable_project_index", true)):
		sync_finished.emit(false, {"error": "index_disabled"})
		return
	_syncing = true
	_ready = false
	sync_started.emit()
	sync_progress.emit(0.0, "Scanning project…")
	var built: Dictionary = {
		"version": INDEX_VERSION,
		"project": "res://",
		"synced_at": Time.get_unix_time_from_system(),
		"files": [],
		"scenebuilder": [],
		"scenes": [],
		"symbols": [],
		"docs": [],
		"file_count": 0,
		"scenebuilder_count": 0,
		"scene_count": 0,
		"symbol_count": 0,
		"doc_count": 0,
	}
	_scan_project_files("res://", built)
	sync_progress.emit(0.45, "Indexing SceneBuilder…")
	_index_scenebuilder(built)
	sync_progress.emit(0.75, "Summarizing scenes…")
	_summarize_scenes(built)
	sync_progress.emit(0.78, "Indexing documentation…")
	_index_documentation(built)
	built["file_count"] = (built.get("files", []) as Array).size()
	built["scenebuilder_count"] = (built.get("scenebuilder", []) as Array).size()
	built["scene_count"] = (built.get("scenes", []) as Array).size()
	built["symbol_count"] = (built.get("symbols", []) as Array).size()
	built["doc_count"] = (built.get("docs", []) as Array).size()
	_index = built
	_save_index_to_disk()
	if _should_sync_embeddings():
		sync_progress.emit(0.82, "Building semantic embeddings…")
		_start_embedding_sync(built)
		return
	_finish_sync(true)

func _finish_sync(success: bool) -> void:
	_ready = true
	_syncing = false
	sync_progress.emit(1.0, "Done")
	sync_finished.emit(success, get_status())

func delete_index() -> void:
	if _embedding_client != null:
		_embedding_client.cancel_batch()
	var dir_path := _index_dir_path()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		_remove_dir_recursive(dir_path)
	_index = {}
	_embeddings = {}
	_ready = false
	_semantic_ready = false
	index_deleted.emit()
	sync_finished.emit(true, {"deleted": true})

func search(query: String, kinds: Array = [], limit: int = 20, mode: String = "hybrid") -> Array:
	if not is_ready():
		return []
	var search_mode: String = mode.strip_edges().to_lower()
	if search_mode.is_empty():
		search_mode = "hybrid"
	var lexical: Array = _search_lexical(query, kinds, limit * 2)
	if search_mode == "lexical" or not is_semantic_ready():
		return lexical.slice(0, limit)
	var semantic: Array = _search_semantic(query, kinds, limit * 2)
	if search_mode == "semantic":
		return semantic.slice(0, limit)
	return _merge_hybrid_results(lexical, semantic, limit)

func _search_lexical(query: String, kinds: Array = [], limit: int = 20) -> Array:
	if not is_ready():
		return []
	var normalized: String = query.to_lower().strip_edges()
	if normalized.is_empty():
		return []
	var terms: PackedStringArray = _tokenize(normalized)
	if terms.is_empty():
		return []
	var allow: Dictionary = {}
	for kind in kinds:
		var k: String = String(kind).strip_edges()
		if not k.is_empty():
			allow[k] = true
	var use_filter: bool = not allow.is_empty()
	var results: Array = []
	_score_entries(_index.get("files", []), terms, "file", use_filter, allow, results)
	_score_entries(_index.get("scenebuilder", []), terms, "scenebuilder", use_filter, allow, results)
	_score_entries(_index.get("scenes", []), terms, "scene", use_filter, allow, results)
	_score_entries(_index.get("symbols", []), terms, "symbol", use_filter, allow, results)
	_score_entries(_index.get("docs", []), terms, "doc", use_filter, allow, results)
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	if results.size() > limit:
		return results.slice(0, limit)
	return results

func build_retrieval_context(query: String, max_chars: int = 10000) -> String:
	var kinds: Array = []
	if ProjectDocsService.prompt_needs_docs(query.to_lower()):
		kinds.append("doc")
	var hits: Array = search(query, kinds, 16, "hybrid")
	if hits.is_empty() and not kinds.is_empty():
		hits = search(query, [], 16, "hybrid")
	if hits.is_empty():
		return ""
	var parts: PackedStringArray = ["## Project index matches (lexical + semantic + docs, all local)"]
	var used: int = 0
	for hit in hits:
		if not hit is Dictionary:
			continue
		var line: String = _format_hit(hit)
		if line.is_empty():
			continue
		if used + line.length() > max_chars:
			break
		parts.append(line)
		used += line.length()
	return "\n".join(parts)

func build_agent_bootstrap(user_prompt: String) -> String:
	if not is_ready():
		return ""
	var lower: String = user_prompt.to_lower()
	var kinds: Array = []
	if _prompt_needs_scenebuilder(lower):
		kinds.append("scenebuilder")
	if ProjectDocsService.prompt_needs_docs(lower):
		kinds.append("doc")
	kinds.append("scene")
	kinds.append("file")
	var query: String = user_prompt
	if kinds.has("scenebuilder"):
		query = "%s SceneBuilder Wall Floor Door Ground" % user_prompt
	var hits: Array = search(query, kinds, 24, "hybrid")
	var parts: PackedStringArray = [
		"Preloaded project index (do NOT re-scan res:// from scratch).",
		"Use search_project_index (mode hybrid/semantic/lexical) or paths below.",
		"Use search_project_docs for Godot API / README / class_name questions (all local).",
		"Place assets with place_scene_builder_item / instance_scene.",
	]
	if ProjectDocsService.prompt_needs_docs(lower):
		parts.append("Doc/API query detected — prefer search_project_docs with your question.")
	if _prompt_needs_scenebuilder(lower):
		parts.append(_format_scenebuilder_summary())
	parts.append(_format_scene_snapshot_hint())
	parts.append("Top matches:")
	for hit in hits.slice(0, 14):
		if hit is Dictionary:
			parts.append("- %s" % _format_hit(hit))
	return "\n".join(parts)

func get_file_paths_for_autocomplete() -> Array:
	if not is_ready():
		return []
	var out: Array = []
	for entry in _index.get("files", []):
		if entry is Dictionary:
			var path: String = String(entry.get("path", ""))
			if not path.is_empty():
				out.append({
					"kind": "file",
					"path": path,
					"label": path.replace("res://", ""),
					"insert": "@%s" % path,
				})
	return out

func get_scenebuilder_entries() -> Array:
	if not is_ready():
		return []
	return (_index.get("scenebuilder", []) as Array).duplicate(true)

func search_docs(query: String, limit: int = 12, mode: String = "hybrid") -> Array:
	return search(query, ["doc"], limit, mode)

func get_doc_entries() -> Array:
	if not is_ready():
		return []
	return (_index.get("docs", []) as Array).duplicate(true)

func _index_documentation(built: Dictionary) -> void:
	if not ProjectDocsService.should_index_docs(_config_manager):
		built["docs"] = []
		built["doc_count"] = 0
		return
	var docs: Array = ProjectDocsService.build_docs_entries(
		_config_manager,
		built,
		_ignore_patterns,
		Callable(self, "_read_text_file"),
		Callable(self, "_tokenize"),
		Callable(self, "_should_ignore_dir"),
		Callable(self, "_should_ignore_file")
	)
	built["docs"] = docs
	built["doc_count"] = docs.size()

# --- persistence / persistencia ---

func _index_dir_path() -> String:
	return INDEX_ROOT.path_join(str(ProjectSettings.globalize_path("res://").hash()))

func _index_file_path() -> String:
	return _index_dir_path().path_join("index.json")

func _embeddings_file_path() -> String:
	return _index_dir_path().path_join("embeddings.json")

func _load_embeddings_from_disk() -> bool:
	var path := _embeddings_file_path()
	var parsed: Variant = _read_json_dict(path)
	if not parsed is Dictionary:
		return false
	if int(parsed.get("version", 0)) != EMBEDDINGS_VERSION:
		return false
	_embeddings = parsed
	return true

func _save_embeddings_to_disk() -> void:
	var dir_path := _index_dir_path()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var file := FileAccess.open(_embeddings_file_path(), FileAccess.WRITE)
	if file == null:
		push_warning("AI Assistant: could not save embeddings index")
		return
	file.store_string(JSON.stringify(_embeddings, "\t"))
	file.close()

func _embeddings_has_vectors() -> bool:
	if not _embeddings.has("chunks"):
		return false
	for chunk in _embeddings.get("chunks", []):
		if chunk is Dictionary and (chunk.get("vector", []) as Array).size() > 0:
			return true
	return false

func _embedding_chunk_count() -> int:
	return (_embeddings.get("chunks", []) as Array).size()

func _load_index_from_disk() -> bool:
	var path := _index_file_path()
	var parsed: Variant = _read_json_dict(path)
	if not parsed is Dictionary:
		return false
	if int(parsed.get("version", 0)) != INDEX_VERSION:
		return false
	_index = parsed
	if not _index.has("docs"):
		_index["docs"] = []
		_index["doc_count"] = 0
	return true

func _save_index_to_disk() -> void:
	var dir_path := _index_dir_path()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var file := FileAccess.open(_index_file_path(), FileAccess.WRITE)
	if file == null:
		push_warning("AI Assistant: could not save project index")
		return
	file.store_string(JSON.stringify(_index, "\t"))
	file.close()

func _index_is_stale() -> bool:
	var max_age: int = int(_config_manager.get_setting("index_max_age_hours", 24)) if _config_manager else 24
	if max_age <= 0:
		return false
	var synced: int = int(_index.get("synced_at", 0))
	if Time.get_unix_time_from_system() - synced > max_age * 3600:
		return true
	if _should_sync_embeddings() and not is_semantic_ready():
		return true
	var embed_synced: int = int(_embeddings.get("synced_at", 0))
	if _should_sync_embeddings() and embed_synced < synced:
		return true
	if ProjectDocsService.should_index_docs(_config_manager) and is_ready():
		if not _index.has("docs") or int(_index.get("doc_count", 0)) == 0:
			return true
	return false

func _should_sync_embeddings() -> bool:
	if _config_manager == null:
		return false
	if not bool(_config_manager.get_setting("enable_project_index", true)):
		return false
	if not bool(_config_manager.get_setting("enable_semantic_index", true)):
		return false
	if _embedding_client == null or not _embedding_client.is_available():
		return false
	if not bool(_config_manager.get_setting("semantic_index_on_sync", true)):
		return false
	if _embeddings.has("model") and _embedding_client.get_model() != String(_embeddings.get("model", "")):
		return true
	return true

func _start_embedding_sync(built: Dictionary) -> void:
	var chunks: Array = _build_embedding_chunks(built)
	var existing_by_id: Dictionary = {}
	for chunk in _embeddings.get("chunks", []):
		if chunk is Dictionary:
			existing_by_id[String(chunk.get("id", ""))] = chunk
	_pending_preserved_chunks.clear()
	_pending_embed_queue.clear()
	for chunk in chunks:
		if not chunk is Dictionary:
			continue
		var chunk_id: String = String(chunk.get("id", ""))
		var chunk_hash: int = int(chunk.get("hash", 0))
		if existing_by_id.has(chunk_id):
			var existing: Dictionary = existing_by_id[chunk_id]
			if int(existing.get("hash", -1)) == chunk_hash and (existing.get("vector", []) as Array).size() > 0:
				_pending_preserved_chunks.append(existing)
				continue
		_pending_embed_queue.append(chunk)
	if _pending_embed_queue.is_empty():
		_finalize_embeddings_store(_pending_preserved_chunks)
		_finish_sync(true)
		return
	_embedding_client.run_batch(_pending_embed_queue)

func _on_embedding_batch_progress(done: int, total: int, message: String) -> void:
	if total <= 0:
		return
	var ratio: float = clampf(0.82 + (float(done) / float(total)) * 0.18, 0.82, 0.99)
	sync_progress.emit(ratio, message)

func _on_embedding_batch_finished(success: bool, vectors: Dictionary) -> void:
	var stored: Array = _pending_preserved_chunks.duplicate(true)
	for chunk in _pending_embed_queue:
		if not chunk is Dictionary:
			continue
		var chunk_id: String = String(chunk.get("id", ""))
		if not vectors.has(chunk_id):
			continue
		var vector: Array = vectors[chunk_id]
		if vector is Array and vector.is_empty():
			continue
		stored.append({
			"id": chunk_id,
			"kind": chunk.get("kind", ""),
			"path": chunk.get("path", ""),
			"preview": chunk.get("preview", ""),
			"hash": chunk.get("hash", 0),
			"vector": vector,
		})
	_pending_preserved_chunks.clear()
	_pending_embed_queue.clear()
	if success or not stored.is_empty():
		_finalize_embeddings_store(stored)
	_finish_sync(success or not stored.is_empty())

func _finalize_embeddings_store(chunks: Array) -> void:
	_embeddings = {
		"version": EMBEDDINGS_VERSION,
		"model": _embedding_client.get_model() if _embedding_client else "",
		"provider": _embedding_client.get_provider() if _embedding_client else "",
		"synced_at": Time.get_unix_time_from_system(),
		"chunks": chunks,
	}
	_save_embeddings_to_disk()
	_semantic_ready = _embeddings_has_vectors()

func _build_embedding_chunks(built: Dictionary) -> Array:
	var max_chunks: int = int(_config_manager.get_setting("semantic_max_chunks", DEFAULT_SEMANTIC_MAX_CHUNKS)) if _config_manager else DEFAULT_SEMANTIC_MAX_CHUNKS
	var chunk_size: int = int(_config_manager.get_setting("semantic_chunk_size", DEFAULT_SEMANTIC_CHUNK_SIZE)) if _config_manager else DEFAULT_SEMANTIC_CHUNK_SIZE
	max_chunks = clampi(max_chunks, 32, 2000)
	chunk_size = clampi(chunk_size, 400, 4000)
	var out: Array = []
	for entry in built.get("scenebuilder", []):
		if out.size() >= max_chunks:
			break
		if not entry is Dictionary:
			continue
		var text: String = "SceneBuilder category=%s item=%s tres=%s scene=%s" % [
			entry.get("category", ""),
			entry.get("item", ""),
			entry.get("tres", ""),
			entry.get("scene", ""),
		]
		out.append(_make_embedding_chunk("scenebuilder", String(entry.get("tres", entry.get("scene", ""))), text, 0, chunk_size))
	for entry in built.get("scenes", []):
		if out.size() >= max_chunks:
			break
		if not entry is Dictionary:
			continue
		var nodes: Array = entry.get("nodes", [])
		var text: String = "Scene %s nodes: %s" % [entry.get("path", ""), ", ".join(PackedStringArray(nodes))]
		out.append(_make_embedding_chunk("scene", String(entry.get("path", "")), text, 0, chunk_size))
	for entry in built.get("symbols", []):
		if out.size() >= max_chunks:
			break
		if not entry is Dictionary:
			continue
		var text: String = "GDScript symbol %s in %s" % [entry.get("name", ""), entry.get("path", "")]
		out.append(_make_embedding_chunk("symbol", String(entry.get("path", "")), text, 0, chunk_size))
	for entry in built.get("files", []):
		if out.size() >= max_chunks:
			break
		if not entry is Dictionary:
			continue
		var path: String = String(entry.get("path", ""))
		if not (path.ends_with(".gd") or path.ends_with(".cs")):
			continue
		var file_text: String = _read_text_file(path)
		if file_text.is_empty():
			continue
		if file_text.length() > MAX_FILE_CHARS_FOR_EMBED:
			file_text = file_text.substr(0, MAX_FILE_CHARS_FOR_EMBED)
		var pieces: Array = _split_text_for_embedding(file_text, chunk_size)
		for piece_idx in pieces.size():
			if out.size() >= max_chunks:
				break
			out.append(_make_embedding_chunk("file", path, String(pieces[piece_idx]), piece_idx, chunk_size))
	for entry in built.get("docs", []):
		if out.size() >= max_chunks:
			break
		if not entry is Dictionary:
			continue
		var doc_path: String = String(entry.get("path", ""))
		var doc_text: String = String(entry.get("text", ""))
		if doc_text.is_empty():
			continue
		var pieces_doc: Array = _split_text_for_embedding(doc_text, chunk_size)
		for piece_idx in pieces_doc.size():
			if out.size() >= max_chunks:
				break
			out.append(_make_embedding_chunk("doc", doc_path, String(pieces_doc[piece_idx]), piece_idx, chunk_size))
	return out

func _make_embedding_chunk(kind: String, path: String, text: String, piece_idx: int, _chunk_size: int) -> Dictionary:
	var clean: String = text.strip_edges()
	var preview: String = clean.substr(0, mini(160, clean.length()))
	return {
		"id": "%s:%s:%d" % [kind, path, piece_idx],
		"kind": kind,
		"path": path,
		"text": clean,
		"preview": preview,
		"hash": hash(clean),
	}

func _split_text_for_embedding(text: String, chunk_size: int) -> Array:
	var out: Array = []
	var step: int = maxi(int(chunk_size * 0.75), 256)
	var pos: int = 0
	while pos < text.length():
		out.append(text.substr(pos, chunk_size))
		pos += step
		if out.size() >= 24:
			break
	return out

func _search_semantic(query: String, kinds: Array, limit: int) -> Array:
	if not is_semantic_ready() or _embedding_client == null:
		return []
	var qvec: Array = _embedding_client.embed_query(query)
	if qvec.is_empty():
		return []
	var allow: Dictionary = {}
	for kind in kinds:
		var k: String = String(kind).strip_edges()
		if not k.is_empty():
			allow[k] = true
	var use_filter: bool = not allow.is_empty()
	var min_score: float = float(_config_manager.get_setting("semantic_min_score", 0.32)) if _config_manager else 0.32
	var results: Array = []
	for chunk in _embeddings.get("chunks", []):
		if not chunk is Dictionary:
			continue
		var kind: String = String(chunk.get("kind", "file"))
		if use_filter and not allow.has(kind):
			continue
		var vector: Array = chunk.get("vector", [])
		if not vector is Array or vector.is_empty():
			continue
		var score: float = _cosine_similarity(qvec, vector)
		if score < min_score:
			continue
		results.append({
			"kind": kind,
			"score": score,
			"entry": chunk,
			"source": "semantic",
		})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	if results.size() > limit:
		return results.slice(0, limit)
	return results

func _merge_hybrid_results(lexical: Array, semantic: Array, limit: int) -> Array:
	var merged: Dictionary = {}
	for i in lexical.size():
		if not lexical[i] is Dictionary:
			continue
		var hit: Dictionary = (lexical[i] as Dictionary).duplicate(true)
		var key: String = _hit_merge_key(hit)
		hit["score"] = float(hit.get("score", 0.0)) * 0.45 + (1.0 / (50.0 + float(i)))
		hit["source"] = "lexical"
		merged[key] = hit
	for i in semantic.size():
		if not semantic[i] is Dictionary:
			continue
		var sem_hit: Dictionary = (semantic[i] as Dictionary).duplicate(true)
		var sem_key: String = _hit_merge_key(sem_hit)
		var sem_score: float = float(sem_hit.get("score", 0.0)) * 0.55 + (1.0 / (50.0 + float(i)))
		if merged.has(sem_key):
			var existing: Dictionary = merged[sem_key]
			existing["score"] = float(existing.get("score", 0.0)) + sem_score
			existing["source"] = "hybrid"
			merged[sem_key] = existing
		else:
			sem_hit["score"] = sem_score
			sem_hit["source"] = "semantic"
			merged[sem_key] = sem_hit
	var results: Array = merged.values()
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	if results.size() > limit:
		return results.slice(0, limit)
	return results

func _hit_merge_key(hit: Dictionary) -> String:
	var entry: Dictionary = hit.get("entry", {})
	var kind: String = String(hit.get("kind", entry.get("kind", "")))
	var path: String = String(entry.get("path", entry.get("tres", entry.get("scene", ""))))
	var preview: String = String(entry.get("preview", entry.get("item", entry.get("name", entry.get("title", "")))))
	return "%s|%s|%s" % [kind, path, preview]

func _cosine_similarity(a: Array, b: Array) -> float:
	var size: int = mini(a.size(), b.size())
	if size == 0:
		return 0.0
	var dot: float = 0.0
	var norm_a: float = 0.0
	var norm_b: float = 0.0
	for i in size:
		var av: float = float(a[i])
		var bv: float = float(b[i])
		dot += av * bv
		norm_a += av * av
		norm_b += bv * bv
	if norm_a <= 0.0 or norm_b <= 0.0:
		return 0.0
	return dot / (sqrt(norm_a) * sqrt(norm_b))

# --- scanning / escaneo ---

func _scan_project_files(path: String, built: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path := path.path_join(entry)
			if dir.current_is_dir():
				if not _should_ignore_dir(full_path, entry):
					_scan_project_files(full_path, built)
			elif _should_index_file(full_path, entry):
				var files: Array = built.get("files", [])
				files.append(_make_file_entry(full_path, entry))
				built["files"] = files
				if entry.ends_with(".gd"):
					_extract_gdscript_symbols(full_path, built)
		entry = dir.get_next()
	dir.list_dir_end()

func _make_file_entry(full_path: String, file_name: String) -> Dictionary:
	var ext := file_name.get_extension()
	if not ext.is_empty():
		ext = ".%s" % ext
	var tokens: Array = _tokenize("%s %s" % [full_path, file_name.replace("_", " ")])
	return {
		"path": full_path,
		"ext": ext,
		"name": file_name,
		"tokens": tokens,
	}

func _extract_gdscript_symbols(script_path: String, built: Dictionary) -> void:
	var text := _read_text_file(script_path)
	if text.is_empty():
		return
	var regex := RegEx.new()
	regex.compile("(?m)^\\s*func\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var count: int = 0
	for match_result in regex.search_all(text):
		if count >= MAX_SYMBOLS_PER_FILE:
			break
		var symbols: Array = built.get("symbols", [])
		symbols.append({
			"kind": "function",
			"path": script_path,
			"name": match_result.get_string(1),
			"tokens": _tokenize(match_result.get_string(1)),
		})
		built["symbols"] = symbols
		count += 1

func _index_scenebuilder(built: Dictionary) -> void:
	var root_path := ""
	for candidate in SCENEBUILDER_ROOTS:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
			root_path = candidate
			break
	if root_path.is_empty():
		return
	_scan_scenebuilder_dir(root_path, built)

func _scan_scenebuilder_dir(path: String, built: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path := path.path_join(entry)
			if dir.current_is_dir():
				if entry != "scenes":
					_scan_scenebuilder_dir(full_path, built)
			elif entry.ends_with(".tres"):
				_add_scenebuilder_tres(full_path, path.get_file(), built)
			elif entry.ends_with(".tscn") and path.ends_with("/scenes"):
				_add_scenebuilder_tscn(full_path, path.get_base_dir().get_file(), built)
		entry = dir.get_next()
	dir.list_dir_end()

func _add_scenebuilder_tres(tres_path: String, category: String, built: Dictionary) -> void:
	var item_name := tres_path.get_file().get_basename()
	var scene_path := tres_path.get_base_dir().path_join("scenes").path_join(item_name + ".tscn")
	if not FileAccess.file_exists(scene_path):
		scene_path = ""
	var entry := {
		"kind": "scenebuilder",
		"category": category,
		"item": item_name,
		"tres": tres_path,
		"scene": scene_path,
		"tokens": _tokenize("%s %s %s scenebuilder" % [category, item_name, tres_path]),
	}
	var items: Array = built.get("scenebuilder", [])
	items.append(entry)
	built["scenebuilder"] = items

func _add_scenebuilder_tscn(scene_path: String, category: String, built: Dictionary) -> void:
	var item_name := scene_path.get_file().get_basename()
	var tres_path := scene_path.get_base_dir().get_base_dir().path_join(item_name + ".tres")
	if not FileAccess.file_exists(tres_path):
		tres_path = ""
	for existing in built.get("scenebuilder", []):
		if existing is Dictionary and String(existing.get("item", "")) == item_name:
			if String(existing.get("scene", "")).is_empty():
				existing["scene"] = scene_path
			return
	var entry := {
		"kind": "scenebuilder",
		"category": category,
		"item": item_name,
		"tres": tres_path,
		"scene": scene_path,
		"tokens": _tokenize("%s %s %s scenebuilder" % [category, item_name, scene_path]),
	}
	var items: Array = built.get("scenebuilder", [])
	items.append(entry)
	built["scenebuilder"] = items

func _summarize_scenes(built: Dictionary) -> void:
	for entry in built.get("files", []):
		if not entry is Dictionary:
			continue
		var path: String = String(entry.get("path", ""))
		if not path.ends_with(".tscn"):
			continue
		var summary := _summarize_tscn(path)
		if summary.is_empty():
			continue
		var scenes: Array = built.get("scenes", [])
		scenes.append(summary)
		built["scenes"] = scenes

func _summarize_tscn(path: String) -> Dictionary:
	var text := _read_text_file(path)
	if text.is_empty():
		return {}
	var nodes: Array = []
	var regex := RegEx.new()
	regex.compile("\\[node name=\"([^\"]+)\"")
	for match_result in regex.search_all(text):
		if nodes.size() >= MAX_SCENE_NODES:
			break
		nodes.append(match_result.get_string(1))
	return {
		"kind": "scene",
		"path": path,
		"nodes": nodes,
		"node_count": nodes.size(),
		"tokens": _tokenize("%s %s" % [path, " ".join(PackedStringArray(nodes))]),
	}

# --- search scoring / puntuación ---

func _score_entries(entries: Variant, terms: PackedStringArray, kind: String, use_filter: bool, allow: Dictionary, results: Array) -> void:
	if not entries is Array:
		return
	if use_filter and not allow.has(kind):
		return
	for entry in entries:
		if not entry is Dictionary:
			continue
		var score: float = _score_entry(entry, terms, kind)
		if score <= 0.0:
			continue
		results.append({
			"kind": kind,
			"score": score,
			"entry": entry,
		})

func _score_entry(entry: Dictionary, terms: PackedStringArray, kind: String = "") -> float:
	var hay: String = ""
	if entry.has("tokens") and entry.get("tokens") is Array:
		for token in entry.get("tokens"):
			hay += " %s" % String(token)
	else:
		hay = JSON.stringify(entry)
	hay = hay.to_lower()
	var score: float = 0.0
	for term in terms:
		if term.is_empty():
			continue
		if term in hay:
			score += 1.0
		if entry.has("path") and term in String(entry.get("path", "")).to_lower():
			score += 2.0
		if entry.has("item") and term == String(entry.get("item", "")).to_lower():
			score += 3.0
		if entry.has("title") and term in String(entry.get("title", "")).to_lower():
			score += 2.5
		if kind == "doc" and entry.has("source") and term in String(entry.get("source", "")).to_lower():
			score += 1.5
	return score

func _format_hit(hit: Dictionary) -> String:
	var entry: Dictionary = hit.get("entry", {})
	var kind: String = String(hit.get("kind", ""))
	var preview: String = String(entry.get("preview", "")).strip_edges()
	match kind:
		"scenebuilder":
			return "SceneBuilder %s/%s → tres=%s scene=%s" % [
				entry.get("category", ""),
				entry.get("item", ""),
				entry.get("tres", ""),
				entry.get("scene", ""),
			]
		"scene":
			if entry.has("nodes"):
				var nodes: Array = entry.get("nodes", [])
				var node_preview: String = ", ".join(PackedStringArray(nodes).slice(0, 8))
				return "Scene %s nodes=[%s]" % [entry.get("path", ""), node_preview]
			return "Scene %s %s" % [entry.get("path", ""), preview]
		"symbol":
			if entry.has("name"):
				return "Symbol %s in %s" % [entry.get("name", ""), entry.get("path", "")]
			return "Symbol %s" % preview
		"file":
			if not preview.is_empty():
				return "File %s — %s" % [entry.get("path", ""), preview]
			return "File %s" % entry.get("path", "")
		"doc":
			var source: String = String(entry.get("source", ""))
			var title: String = String(entry.get("title", ""))
			if not preview.is_empty():
				return "Doc [%s] %s — %s" % [source, title, preview]
			return "Doc [%s] %s" % [source, title]
		_:
			if not preview.is_empty():
				return "%s %s — %s" % [kind, entry.get("path", ""), preview]
			return "%s %s" % [kind, entry.get("path", "")]

func _format_scenebuilder_summary() -> String:
	var by_cat: Dictionary = {}
	for entry in _index.get("scenebuilder", []):
		if not entry is Dictionary:
			continue
		var cat: String = String(entry.get("category", ""))
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(String(entry.get("item", "")))
	var lines: PackedStringArray = ["SceneBuilder catalog:"]
	for cat in by_cat.keys():
		var items: Array = by_cat[cat]
		var preview := ", ".join(PackedStringArray(items).slice(0, 8))
		lines.append("- %s (%d): %s" % [cat, items.size(), preview])
	return "\n".join(lines)

func _format_scene_snapshot_hint() -> String:
	var mundos: Array = _search_lexical("Mundo", ["scene"], 3)
	if mundos.is_empty():
		return ""
	var lines: PackedStringArray = ["Open scenes in index:"]
	for hit in mundos:
		if hit is Dictionary:
			var entry: Dictionary = hit.get("entry", {})
			lines.append("- %s" % entry.get("path", ""))
	return "\n".join(lines)

# --- ignore rules / reglas de exclusión ---

func _load_ignore_rules() -> void:
	_ignore_patterns = DEFAULT_IGNORE_DIRS.duplicate()
	var paths: PackedStringArray = [
		"res://.aiignore",
		"res://.gitignore",
		"res://addons/ai_assistant_plugin/.aiignore.example",
	]
	for path in paths:
		if FileAccess.file_exists(path):
			for line in _read_text_file(path).split("\n"):
				var rule := line.strip_edges()
				if rule.is_empty() or rule.begins_with("#"):
					continue
				_ignore_patterns.append(rule)

func _should_ignore_dir(full_path: String, entry_name: String) -> bool:
	if entry_name.begins_with("."):
		return entry_name not in ["godot"]
	for pattern in _ignore_patterns:
		if _path_matches_rule(full_path, entry_name, pattern):
			return true
	return false

func _should_index_file(full_path: String, file_name: String) -> bool:
	return not _should_ignore_file(full_path, file_name) and _file_has_index_extension(file_name)

func _should_ignore_file(full_path: String, file_name: String) -> bool:
	for pattern in _ignore_patterns:
		if _path_matches_rule(full_path, file_name, pattern):
			return true
	return false

func _file_has_index_extension(file_name: String) -> bool:
	for ext in INDEX_EXTENSIONS:
		if file_name.ends_with(ext):
			return true
	return false

func _path_matches_rule(full_path: String, entry_name: String, rule: String) -> bool:
	var r := rule.strip_edges()
	if r.is_empty():
		return false
	if r.ends_with("/"):
		return full_path.contains("/%s" % r.trim_suffix("/")) or entry_name == r.trim_suffix("/")
	if r.contains("*"):
		return entry_name.match(r.replace("*", "?"))
	return full_path.contains("/%s/" % r) or full_path.ends_with("/%s" % r) or entry_name == r

# --- helpers / utilidades ---

func _prompt_needs_scenebuilder(lower: String) -> bool:
	var keys: PackedStringArray = [
		"mapa", "piso", "pisos", "scenebuilder", "pared", "wall", "floor", "ground",
		"door", "escalera", "stairs", "coloca", "build",
	]
	for key in keys:
		if lower.contains(key):
			return true
	return false

func _tokenize(text: String) -> PackedStringArray:
	var regex := RegEx.new()
	regex.compile("[A-Za-z0-9_./:-]+")
	var out: PackedStringArray = []
	for match_result in regex.search_all(text.to_lower()):
		var token: String = match_result.get_string().strip_edges()
		if token.length() >= 2:
			out.append(token)
	return out

func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text

func _read_json_dict(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text: String = _read_text_file(path).strip_edges()
	if text.is_empty() or not text.begins_with("{"):
		_quarantine_bad_index_file(path, "empty or non-object JSON")
		return null
	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK or not json.data is Dictionary:
		_quarantine_bad_index_file(path, "parse error %s" % err)
		return null
	return json.data

func _quarantine_bad_index_file(path: String, reason: String) -> void:
	push_warning("AI Assistant: invalid index cache %s (%s) — will rebuild on next sync" % [path, reason])
	var global_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path):
		return
	var backup_path := ProjectSettings.globalize_path("%s.bad" % path)
	if FileAccess.file_exists("%s.bad" % path):
		DirAccess.remove_absolute(backup_path)
	DirAccess.rename_absolute(global_path, backup_path)

func _remove_dir_recursive(path: String) -> void:
	var global := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(global):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(child)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(global)

func connect_filesystem_watch(editor_plugin: EditorPlugin) -> void:
	if editor_plugin == null:
		return
	var fs: EditorFileSystem = editor_plugin.get_editor_interface().get_resource_filesystem()
	if fs == null:
		return
	if not fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.connect(_on_filesystem_changed)

func _on_filesystem_changed() -> void:
	if _config_manager != null and not bool(_config_manager.get_setting("index_auto_sync", true)):
		return
	if _syncing:
		return
	call_deferred("sync_index")
